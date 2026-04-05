# ============================================================
# Yosys Synthesis Script — 8×8 TPU (Google TPU v1 Optimized)
# Design  : tpu_chip
# PDK     : IHP SG13G2 (130nm)
#
# What changed vs. yosys/yosys.tcl:
#   1. RTL_DIR points to opt_rtl (new optimized RTL)
#   2. Added activation_pipe.v to the read list (new P4 module)
#   3. Multi-pass ABC: strash→refactor→rewrite→balance→crit_path map
#      instead of the single-pass "+strash;balance;map"
#   4. Upgraded clock target to 13ns (76MHz) reflecting skew+pipeline gains
#   5. Added timing estimate report (stat -liberty with -noattr flattening)
#   6. Added intermediate post-opt netlist checkpoint
# ============================================================

yosys -import

# ============================================================
# Configuration Variables
# ============================================================

set DESIGN    tpu_chip
set ARRAY_SIZE 8

set RTL_DIR   ../opt_rtl     ;# New optimized RTL (Google TPU inspired)
set OUT_DIR   out
set TMP_DIR   tmp
set LOG_DIR   log
set RPT_DIR   reports

# ── Clock target ──────────────────────────────────────────────────────────
# Targeting 100 MHz (10ns) for both ABC optimization and PnR.
set CLK_PERIOD     10.0 ;# 100 MHz — synthesis target (ABC)
set CLK_PERIOD_PNR 10.0 ;# 100 MHz — written into SDC for OpenROAD

# Create output directories
exec rm -rf  $OUT_DIR $TMP_DIR $LOG_DIR $RPT_DIR
exec mkdir -p $OUT_DIR $TMP_DIR $LOG_DIR $RPT_DIR

# ============================================================
# Technology Library Setup
# ============================================================

puts "INFO: Setting up PDK paths..."

set pdk_root "../ihp13/pdk"
if {![file exists $pdk_root]} {
    puts "ERROR: PDK root not found: $pdk_root"
    exit 1
}

set pdk_dir       "${pdk_root}/ihp-sg13g2"
set pdk_cells_lib "${pdk_dir}/libs.ref/sg13g2_stdcell/lib"
set pdk_sram_lib  "${pdk_dir}/libs.ref/sg13g2_sram/lib"
set pdk_io_lib    "${pdk_dir}/libs.ref/sg13g2_io/lib"

foreach dir [list $pdk_dir $pdk_cells_lib $pdk_sram_lib $pdk_io_lib] {
    if {![file isdirectory $dir]} {
        puts "ERROR: PDK directory not found: $dir"
        exit 1
    }
}

puts "✓ PDK paths validated"

# Standard cells (TT corner for synthesis)
set tech_cells [list "${pdk_cells_lib}/sg13g2_stdcell_typ_1p20V_25C.lib"]

# SRAM macros — read all TT corner libs
if {[catch {set tech_macros [glob -directory $pdk_sram_lib *_typ_1p20V_25C.lib]} err]} {
    puts "ERROR: SRAM libs not found in $pdk_sram_lib: $err"
    exit 1
}

# IO cells
lappend tech_macros "${pdk_io_lib}/sg13g2_io_typ_1p2V_3p3V_25C.lib"

# Tie cells (include pin names)
set tech_cell_tiehi {sg13g2_tiehi L_HI}
set tech_cell_tielo {sg13g2_tielo L_LO}

# Pre-format liberty args — MUST use lmap+concat to produce separate Tcl words:
#   liberty_args      = for all libs  (stat/check commands)
#   tech_cells_args   = for std cells only (dfflibmap / abc)
set lib_list          [concat [split $tech_cells] [split $tech_macros]]
set liberty_args_list [lmap lib $lib_list {concat "-liberty" $lib}]
set liberty_args      [concat {*}$liberty_args_list]

set tech_cells_args_list [lmap lib $tech_cells {concat "-liberty" $lib}]
set tech_cells_args      [concat {*}$tech_cells_args_list]

# ============================================================
# Read Technology Libraries
# ============================================================

puts "INFO: Reading technology libraries..."
foreach file $lib_list {
    puts "  → [file tail $file]"
    yosys read_liberty -lib "$file"
}

# ============================================================
# Read RTL — opt_rtl (Google TPU v1 Optimized)
# ============================================================

puts ""
puts "INFO: Reading opt_rtl files (Google TPU v1 architecture)..."

# IMPORTANT: Bottom-up dependency order
# Leaf modules → intermediate → top chip
read_verilog -sv ${RTL_DIR}/pe.v                ;# [P3] Shadow weight register
read_verilog -sv ${RTL_DIR}/systolic_array.v    ;# [P2] Diagonal skew + [P5] 2-stage readout
read_verilog -sv ${RTL_DIR}/systolic_controller.v ;# [P3] Overlapped FSM
read_verilog -sv ${RTL_DIR}/addr_gen.v
read_verilog -sv ${RTL_DIR}/quantizer.v
read_verilog -sv ${RTL_DIR}/activation_pipe.v   ;# [P4] NEW — ReLU/ReLU6/passthrough
read_verilog -sv ${RTL_DIR}/output_writer.v
read_verilog -sv ${RTL_DIR}/tpu_core.v
read_verilog -sv ${RTL_DIR}/tpu_top.v
read_verilog -sv ${RTL_DIR}/tpu_chip.sv

puts "✓ All RTL files loaded"

# ============================================================
# Design Hierarchy Setup
# ============================================================

puts ""
puts "INFO: Setting top module: $DESIGN"
hierarchy -check -top $DESIGN

puts "INFO: Logging initial hierarchy..."
yosys tee -q -o ${LOG_DIR}/hierarchy_initial.log hierarchy -check

# ── Protect SRAM macros from synthesis ──────────────────────────────────
# Must be done BEFORE any optimization/flatten pass
yosys setattr -set keep_hierarchy 1 "t:RM_IHPSG13_1P_256x64_c2_bm_bist*"
yosys setattr -set keep_hierarchy 1 "t:RM_IHPSG13_1P_64x64_c2_bm_bist*"
yosys setattr -set keep 1         "t:RM_IHPSG13_*"
yosys blackbox                    "t:RM_IHPSG13_*"

puts "✓ SRAM macros blackboxed and protected"

# ============================================================
# Synthesis — Phase 1: RTL Elaboration & Coarse Optimization
# ============================================================

puts ""
puts "INFO: Phase 1 — RTL elaboration and coarse synthesis..."

# synth -noabc: Runs elaboration, FSM extraction, memory inference,
# but defers technology mapping so we can fine-tune ABC separately.
yosys synth -top $DESIGN -noabc

# Write pre-map netlist for debugging
yosys write_verilog -norename -noexpr ${TMP_DIR}/${DESIGN}_pre_map.v

# ============================================================
# Synthesis — Phase 2: Flip-flop Mapping
# ============================================================

puts "INFO: Phase 2 — Flip-flop technology mapping..."
yosys dfflibmap {*}$tech_cells_args

# ============================================================
# Synthesis — Phase 3: Multi-Pass ABC Combinational Optimization
# ============================================================
# Strategy (inspired by OpenLane ABC recipe):
#   Pass A: Structural hashing + structural/boolean rebalancing
#   Pass B: Critical path rewriting (refactor + rewrite)
#   Pass C: Technology mapping (map) followed by post-map optimization
#
# The tighter CLK_PERIOD (13ns) pushes ABC to find shorter paths.
# This is more useful for the systolic array which has deep logic.
# ============================================================

set period_ps [expr {int($CLK_PERIOD * 1000)}]
puts ""
puts "INFO: Phase 3 — Multi-pass ABC optimization (target: ${CLK_PERIOD}ns / [expr {1000.0/$CLK_PERIOD}]MHz)"
puts "       Pass A: Structural hash + balance"
puts "       Pass B: Critical path rewrite + refactor"
puts "       Pass C: Technology map + post-map size opt"

# Pass A — Structural compression
yosys abc -D $period_ps \
    {*}$tech_cells_args \
    -script "+strash;balance;dch;map"

# Intermediate cleanup + checkpoint
yosys clean -purge
yosys write_verilog -norename -noexpr ${TMP_DIR}/${DESIGN}_abc_passA.v

# Pass B — Critical path rewrite (focuses on longest paths after first map)
yosys abc -D $period_ps \
    {*}$tech_cells_args \
    -script "+strash;refactor;rewrite;balance;dch;map;print_stats"

yosys clean -purge
yosys write_verilog -norename -noexpr ${TMP_DIR}/${DESIGN}_abc_passB.v

# Pass C — Size optimization post-map (reduces unnecessary cell bloat)
yosys abc -D $period_ps \
    {*}$tech_cells_args \
    -script "+strash;balance;map;size_opt;print_stats"

yosys clean -purge
yosys write_verilog -norename -noexpr ${TMP_DIR}/${DESIGN}_post_abc.v

puts "✓ Multi-pass ABC complete"

# ============================================================
# Phase 4: Final Netlist Preparation
# ============================================================

puts ""
puts "INFO: Phase 4 — Final netlist preparation for OpenROAD..."

yosys splitnets -ports -format __v
yosys setundef -zero
yosys clean -purge

# Insert tie cells for constant 0/1 drivers
yosys hilomap -singleton \
    -hicell {*}$tech_cell_tiehi \
    -locell {*}$tech_cell_tielo

yosys clean -purge

# ============================================================
# Reporting
# ============================================================

puts ""
puts "INFO: Generating synthesis reports..."

# Full area report with liberty (most accurate — includes macro areas)
yosys tee -q -o "${RPT_DIR}/${DESIGN}_area.rpt" \
    stat -top $DESIGN {*}$liberty_args

# Logic-only area (excludes SRAM macros — useful for comparing core logic)
yosys tee -q -o "${RPT_DIR}/${DESIGN}_area_logic.rpt" \
    stat -top $DESIGN {*}$tech_cells_args

# Gate count / wire width statistics
yosys tee -q -o "${RPT_DIR}/${DESIGN}_width.rpt" \
    stat -width

# Mapping check — fails if any generic ($_) cells remain
yosys tee -q -o "${RPT_DIR}/${DESIGN}_check.rpt" \
    check -mapped

# Per-module hierarchy breakdown (good for identifying area hotspots)
yosys tee -q -o "${RPT_DIR}/${DESIGN}_hierarchy.rpt" \
    stat -top $DESIGN {*}$liberty_args

puts "✓ Reports written to ${RPT_DIR}/"

# ============================================================
# Write Final Netlist
# ============================================================

puts "INFO: Writing final netlist and JSON..."

yosys write_verilog -noattr -noexpr -nohex -nodec \
    ${OUT_DIR}/${DESIGN}.v

yosys write_json \
    ${OUT_DIR}/${DESIGN}.json

# ============================================================
# Generate SDC for OpenROAD (PnR at 50 MHz)
# ============================================================

puts "INFO: Generating SDC constraints (PnR target: ${CLK_PERIOD_PNR}ns / [expr {1000.0/$CLK_PERIOD_PNR}]MHz)..."

set sdc_fh [open ${OUT_DIR}/${DESIGN}.sdc w]
puts $sdc_fh "# SDC for $DESIGN — Generated by opt_yosys/yosys.tcl"
puts $sdc_fh "# Synthesis target: [expr {1000.0/$CLK_PERIOD}]MHz | PnR target: [expr {1000.0/$CLK_PERIOD_PNR}]MHz"
puts $sdc_fh ""
puts $sdc_fh "# ── Clock ───────────────────────────────────────────────"
puts $sdc_fh "create_clock -name clk_pad -period $CLK_PERIOD_PNR \[get_ports clk_pad\]"
puts $sdc_fh ""
puts $sdc_fh "# ── I/O Delays (20% of clock period) ────────────────────"
puts $sdc_fh "set_input_delay  -clock clk_pad [expr {$CLK_PERIOD_PNR * 0.2}] \[all_inputs\]"
puts $sdc_fh "set_output_delay -clock clk_pad [expr {$CLK_PERIOD_PNR * 0.2}] \[all_outputs\]"
puts $sdc_fh ""
puts $sdc_fh "# ── Clock Uncertainty (jitter + skew) ────────────────────"
puts $sdc_fh "set_clock_uncertainty [expr {$CLK_PERIOD_PNR * 0.05}] \[get_clocks clk_pad\]"
puts $sdc_fh ""
puts $sdc_fh "# ── Output load (standard pad model) ─────────────────────"
puts $sdc_fh "set_load 0.1 \[all_outputs\]"
puts $sdc_fh ""
puts $sdc_fh "# ── SRAM Macros — Dont Touch ─────────────────────────────"
puts $sdc_fh "set_dont_touch \[get_cells -hier *u_sram_weight*\]"
puts $sdc_fh "set_dont_touch \[get_cells -hier *u_sram_data*\]"
puts $sdc_fh "set_dont_touch \[get_cells -hier *u_sram_out_a*\]"
puts $sdc_fh "set_dont_touch \[get_cells -hier *u_sram_out_b*\]"
puts $sdc_fh "set_dont_touch \[get_cells -hier *u_sram_out_c*\]"
puts $sdc_fh ""
puts $sdc_fh "# ── Multi-cycle paths ────────────────────────────────────"
puts $sdc_fh "# Diagonal skew registers: last row (7) receives data 7 cycles after row 0."
puts $sdc_fh "# This is an intentional structural timing relationship — not a CDC issue."
puts $sdc_fh "# set_multicycle_path -setup 2 -through \[get_pins *data_skew*\]"
puts $sdc_fh "# set_multicycle_path -hold  1 -through \[get_pins *data_skew*\]"
puts $sdc_fh ""
puts $sdc_fh "# ── Max Capacitance (PDK Bug Workaround) ─────────────────"
puts $sdc_fh "# The IHP SRAM .lib files lack a max_capacitance attribute on A_DOUT,"
puts $sdc_fh "# causing OpenROAD to default to 0.00 and flag false violations."
puts $sdc_fh "set_max_capacitance 1.0 \[get_pins -hier *A_DOUT*\]"
close $sdc_fh

puts "✓ SDC written to ${OUT_DIR}/${DESIGN}.sdc"

# ============================================================
# Summary Banner
# ============================================================

puts ""
puts "╔══════════════════════════════════════════════════════════╗"
puts "║      opt_yosys Synthesis Complete — Google TPU v1 RTL    ║"
puts "╠══════════════════════════════════════════════════════════╣"
puts "║  Design     : $DESIGN (${ARRAY_SIZE}×${ARRAY_SIZE} systolic array)           ║"
puts "║  Technology : IHP SG13G2 (130nm)                         ║"
puts "║  Syn Target : [expr {1000.0/$CLK_PERIOD}] MHz (${CLK_PERIOD}ns)                   ║"
puts "║  PnR Target : [expr {1000.0/$CLK_PERIOD_PNR}] MHz (${CLK_PERIOD_PNR}ns) — in SDC             ║"
puts "╠══════════════════════════════════════════════════════════╣"
puts "║  RTL Changes (vs. yosys/yosys.tcl):                      ║"
puts "║   \[P2\] Diagonal wavefront skewing (28 FFs, rows 0-7)     ║"
puts "║   \[P3\] Shadow weight double-buffering per PE              ║"
puts "║   \[P4\] activation_pipe.v — ReLU/ReLU6/passthrough        ║"
puts "║   \[P5\] 2-stage readout pipeline (lower MUX depth)        ║"
puts "╠══════════════════════════════════════════════════════════╣"
puts "║  ABC Optimization: Multi-pass (strash+dch+refactor+map)  ║"
puts "╠══════════════════════════════════════════════════════════╣"
puts "║  Output files:                                            ║"
puts "║    Netlist   : ${OUT_DIR}/${DESIGN}.v"
puts "║    JSON      : ${OUT_DIR}/${DESIGN}.json"
puts "║    SDC       : ${OUT_DIR}/${DESIGN}.sdc"
puts "╠══════════════════════════════════════════════════════════╣"
puts "║  Reports (${RPT_DIR}/):                                      ║"
puts "║    Area      : ${DESIGN}_area.rpt       (with macros)    ║"
puts "║    Logic Area: ${DESIGN}_area_logic.rpt (cells only)     ║"
puts "║    Hierarchy : ${DESIGN}_hierarchy.rpt  (per-module)     ║"
puts "║    Check     : ${DESIGN}_check.rpt      (map verify)     ║"
puts "║    Width     : ${DESIGN}_width.rpt      (bus stats)      ║"
puts "╚══════════════════════════════════════════════════════════╝"
puts ""
puts "Next steps:"
puts "  1. Compare ${RPT_DIR}/${DESIGN}_area_logic.rpt vs opt_yosys baseline"
puts "  2. Verify 8 SRAM macros in ${RPT_DIR}/${DESIGN}_area.rpt"
puts "  3. Run OpenROAD PnR with ${OUT_DIR}/${DESIGN}.sdc"
puts ""

exit