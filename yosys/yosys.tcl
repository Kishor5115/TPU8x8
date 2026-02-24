# ============================================================
# Yosys Synthesis Script - 8×8 TPU Hard Macro with SRAM Macros
# Design  : tpu_chip (8×8 systolic array)
# PDK     : IHP SG13G2 (130nm)
# Author  : Adapted from CROC SoC synthesis flow
# ============================================================

yosys -import

# Change to script directory if needed
# Change to script directory if needed
# if {[info script] ne ""} {
#     cd "[file dirname [info script]]/../"
# }

# ============================================================
# Configuration Variables
# ============================================================

set DESIGN tpu_chip
set ARRAY_SIZE 8

set RTL_DIR ../rtl
set OUT_DIR out
set TMP_DIR tmp
set LOG_DIR log
set RPT_DIR reports

# Target frequency - 50MHz initial, optimize to 100MHz later
set CLK_PERIOD 20.0 ;# 50 MHz = 20ns period
# set CLK_PERIOD 10.0 ;# 100 MHz (use after timing optimization)

# Create output directories
exec rm -rf $OUT_DIR $TMP_DIR $LOG_DIR $RPT_DIR
exec mkdir -p $OUT_DIR $TMP_DIR $LOG_DIR $RPT_DIR

# ============================================================
# Technology Library Setup (Following CROC SoC Pattern)
# ============================================================

# Check for PDK location - IHP SG13G2 PDK should be in ihp13/pdk/
puts "INFO: Setting up PDK paths..."

# From yosys/ directory, PDK is at ../ihp13/pdk/ihp-sg13g2
set pdk_root "../ihp13/pdk"

if {![file exists $pdk_root]} {
    puts "ERROR: PDK root directory not found: $pdk_root"
    puts "Expected structure: /home/kishor/tpu/ihp13/pdk/ihp-sg13g2/"
    exit 1
}

# Full PDK path with architecture
set pdk_dir "${pdk_root}/ihp-sg13g2"

if {![file exists $pdk_dir]} {
    puts "ERROR: PDK architecture directory not found: $pdk_dir"
    puts "Please ensure ihp-sg13g2 folder exists in $pdk_root"
    exit 1
}

set pdk_cells_lib ${pdk_dir}/libs.ref/sg13g2_stdcell/lib
set pdk_sram_lib  ${pdk_dir}/libs.ref/sg13g2_sram/lib
set pdk_io_lib    ${pdk_dir}/libs.ref/sg13g2_io/lib

# Validate PDK paths
puts "INFO: Validating PDK paths..."
if {![file isdirectory $pdk_cells_lib]} {
    puts "ERROR: Standard cell library directory not found: $pdk_cells_lib"
    exit 1
}
if {![file isdirectory $pdk_sram_lib]} {
    puts "ERROR: SRAM library directory not found: $pdk_sram_lib"
    exit 1
}
if {![file isdirectory $pdk_io_lib]} {
    puts "ERROR: IO library directory not found: $pdk_io_lib"
    exit 1
}

puts "✓ PDK paths validated:"
puts "  Root: $pdk_dir"
puts "  Standard cells: $pdk_cells_lib"
puts "  SRAM macros: $pdk_sram_lib"
puts "  IO cells: $pdk_io_lib"

# Standard cells
set tech_cells [list "$pdk_cells_lib/sg13g2_stdcell_typ_1p20V_25C.lib"]

# SRAM macros - read all available
if {[catch {set tech_macros [glob -directory $pdk_sram_lib *_typ_1p20V_25C.lib]} err]} {
    puts "WARNING: Failed to glob SRAM libraries from $pdk_sram_lib"
    puts "ERROR: $err"
    exit 1
}

# IO cells
lappend tech_macros "$pdk_io_lib/sg13g2_io_typ_1p2V_3p3V_25C.lib"

# Tie cells
# CORRECT - Includes pin names
set tech_cell_tiehi {sg13g2_tiehi L_HI}
set tech_cell_tielo {sg13g2_tielo L_LO}

# Pre-formatted arguments for yosys commands
set lib_list [concat [split $tech_cells] [split $tech_macros]]
set liberty_args_list [lmap lib $lib_list {concat "-liberty" $lib}]
set liberty_args [concat {*}$liberty_args_list]

set tech_cells_args_list [lmap lib $tech_cells {concat "-liberty" $lib}]
set tech_cells_args [concat {*}$tech_cells_args_list]

# ============================================================
# Read Liberty Files
# ============================================================

puts "INFO: Reading technology libraries..."
puts "  Standard cells: $tech_cells"
puts "  SRAM macros available:"

foreach file $lib_list {
    puts "    - [file tail $file]"
    yosys read_liberty -lib "$file"
}

# ============================================================
# Check SRAM Macro Availability
# ============================================================

puts ""
puts "========================================================"
puts "SRAM Macro Requirements for 8×8 TPU:"
puts "========================================================"
puts "Input Memory (Weight/Activation):"
puts "  - 1× RM_IHPSG13_1P_1024x64_c2_bm_bist (Weight)"
puts "  - 1× RM_IHPSG13_1P_1024x64_c2_bm_bist (Data)"
puts ""
puts "Output Memory:"
puts "  - 6× RM_IHPSG13_1P_256x64_c2_bm_bist"
puts "  - 3 banks × 2 SRAMs per bank (128-bit split to 2×64)"
puts ""
puts "Total: 8 SRAM macros (2 input + 6 output)"
puts ""
puts "Available SRAM macros in IHP SG13G2:"

# Use TCL glob instead of shell commands
if {[catch {glob -directory $pdk_sram_lib *.lib} sram_files]} {
    puts "  WARNING: Could not list SRAM files"
} else {
    foreach file $sram_files {
        set basename [file tail $file]
        if {![string match "*_io_*" $basename]} {
            puts "  - $basename"
        }
    }
}
puts "========================================================"
puts ""

# ============================================================
# Read RTL
# ============================================================

puts "INFO: Reading RTL files..."

# Read all Verilog source files in correct order
# IMPORTANT: Read tpu_core.v BEFORE tpu_top.v (dependency order)
read_verilog -sv $RTL_DIR/systolic.v
read_verilog -sv $RTL_DIR/systolic_controll.v
read_verilog -sv $RTL_DIR/addr_sel.v
read_verilog -sv $RTL_DIR/quantize.v
read_verilog -sv $RTL_DIR/write_out.v
read_verilog -sv $RTL_DIR/tpu_core.v      
read_verilog -sv $RTL_DIR/tpu_top.v       
read_verilog -sv $RTL_DIR/tpu_chip.sv       

# Set top module and check hierarchy
puts ""
puts "INFO: Setting top module: $DESIGN"
hierarchy -check -top $DESIGN

# ============================================================
# Design Hierarchy and Blackbox Handling
# ============================================================

puts "INFO: Design hierarchy (before synthesis):"
yosys tee -q -o $LOG_DIR/hierarchy_initial.log hierarchy -check

# CRITICAL: Mark SRAM macros to keep hierarchy BEFORE any optimization
# This prevents flatten from decomposing them later
yosys setattr -set keep_hierarchy 1 "t:RM_IHPSG13_1P_1024x64_c2_bm_bist*"
yosys setattr -set keep_hierarchy 1 "t:RM_IHPSG13_1P_256x64_c2_bm_bist*"

puts "INFO: SRAM macros marked with keep_hierarchy attribute"
puts "INFO: Pattern: t:RM_IHPSG13* will be preserved during flatten"

# Note: SRAM macros (RM_IHPSG13_1P_*) are automatically treated as
# blackboxes since they were read via read_liberty -lib.
# Explicitly set keep attribute to prevent optimization cleanup
yosys setattr -set keep 1 "t:RM_IHPSG13_*"
# Reinforce blackbox status
yosys blackbox "t:RM_IHPSG13_*"


# ============================================================
# Synthesis - Optimized for 8×8 TPU
# ============================================================

puts "INFO: Starting streamlined synthesis flow..."

# Using synth -top is more robust for large designs
# -noabc allows us to run mapping explicitly with more control
yosys synth -top $DESIGN -noabc

# Map DFFs to technology library
puts "INFO: Mapping flip-flops..."
yosys dfflibmap {*}$tech_cells_args

# Technology mapping with ABC optimization
# Using a simpler script to avoid memory explosion in 32x32 array
set period_ps [expr {int($CLK_PERIOD * 1000)}]
puts "INFO: Running ABC timing optimization: period=$period_ps ps"

yosys abc -D $period_ps {*}$tech_cells_args \
    -script "+strash;balance;map"

yosys clean -purge
yosys write_verilog -norename -noexpr ${TMP_DIR}/${DESIGN}_post_abc.v

# ============================================================
# Final Netlist Preparation and Reporting
# ============================================================

puts "INFO: Final netlist preparation..."

# Prepare for OpenROAD
yosys splitnets -ports -format __v
yosys setundef -zero
yosys clean -purge

# Add tie cell instances for constant 0/1 drivers
# hilomap creates sg13g2_tiehi and sg13g2_tielo instances
yosys hilomap -singleton -hicell {*}$tech_cell_tiehi -locell {*}$tech_cell_tielo

yosys clean -purge

puts "INFO: Generating final synthesis reports..."

# Detailed cell usage and area report using liberty files for accuracy
yosys tee -q -o "${RPT_DIR}/${DESIGN}_area.rpt" stat -top $DESIGN {*}$liberty_args

# Check for unmapped gates - this will fail if any $_ gates remain
puts "INFO: Verifying technology mapping..."
yosys tee -q -o "${RPT_DIR}/${DESIGN}_check.rpt" check -mapped

# Area breakdown specifically for standard cells
yosys tee -q -o "${RPT_DIR}/${DESIGN}_area_logic.rpt" stat -top $DESIGN {*}$tech_cells_args

# Report width statistics for busses
yosys tee -q -o "${RPT_DIR}/${DESIGN}_width.rpt" stat -width

# ============================================================
# Write Final Netlist
# ============================================================

puts "INFO: Writing final netlist..."

yosys write_verilog -noattr -noexpr -nohex -nodec ${OUT_DIR}/${DESIGN}.v

# Also write JSON for debugging
yosys write_json ${OUT_DIR}/${DESIGN}.json

# ============================================================
# Generate SDC File for OpenROAD
# ============================================================

puts "INFO: Generating SDC constraints..."

set sdc_fh [open ${OUT_DIR}/${DESIGN}.sdc w]
puts $sdc_fh "# Synopsys Design Constraints for $DESIGN (${ARRAY_SIZE}x${ARRAY_SIZE})"
puts $sdc_fh "# Generated by Yosys synthesis"
puts $sdc_fh ""
puts $sdc_fh "# Clock definition"
puts $sdc_fh "create_clock -name clk_pad -period $CLK_PERIOD \[get_ports clk_pad\]"
puts $sdc_fh ""
puts $sdc_fh "# Input/Output delays (20% of clock period)"
puts $sdc_fh "set_input_delay -clock clk_pad [expr $CLK_PERIOD * 0.2] \[all_inputs\]"
puts $sdc_fh "set_output_delay -clock clk_pad [expr $CLK_PERIOD * 0.2] \[all_outputs\]"
puts $sdc_fh ""
puts $sdc_fh "# Clock uncertainty (5% for jitter/skew)"
puts $sdc_fh "set_clock_uncertainty [expr $CLK_PERIOD * 0.05] \[get_clocks clk_pad\]"
puts $sdc_fh ""
puts $sdc_fh "# Load capacitance on outputs"
puts $sdc_fh "set_load 0.1 \[all_outputs\]"
puts $sdc_fh ""
puts $sdc_fh "# Exclude SRAM macros from optimization"
puts $sdc_fh "set_dont_touch \[get_cells -hier *u_sram_weight*\]"
puts $sdc_fh "set_dont_touch \[get_cells -hier *u_sram_data*\]"
puts $sdc_fh "set_dont_touch \[get_cells -hier *u_sram_out_a*\]"
puts $sdc_fh "set_dont_touch \[get_cells -hier *u_sram_out_b*\]"
puts $sdc_fh "set_dont_touch \[get_cells -hier *u_sram_out_c*\]"
puts $sdc_fh ""
puts $sdc_fh "# Multi-cycle paths (adjust after identifying critical paths)"
puts $sdc_fh "# set_multicycle_path -setup 2 -from \[get_pins systolic/*\] -to \[get_pins systolic/*\]"
puts $sdc_fh "# set_multicycle_path -hold 1 -from \[get_pins systolic/*\] -to \[get_pins systolic/*\]"
close $sdc_fh

# ============================================================
# Summary
# ============================================================

puts ""
puts "========================================================"
puts "Synthesis Completed Successfully!"
puts "========================================================"
puts "Design Configuration:"
puts "  Top Module:  $DESIGN"
puts "  Array Size:  ${ARRAY_SIZE}x${ARRAY_SIZE} (64 MACs)"
puts "  Clock:       $CLK_PERIOD ns"
puts "  Frequency:   [expr {1000.0 / $CLK_PERIOD}] MHz"
puts "  Technology:  IHP SG13G2 (130nm)"
puts ""
puts "Output Files:"
puts "  Netlist:     ${OUT_DIR}/${DESIGN}.v"
puts "  JSON:        ${OUT_DIR}/${DESIGN}.json"
puts "  SDC:         ${OUT_DIR}/${DESIGN}.sdc"
puts ""
puts "Reports:"
puts "  Area:        ${RPT_DIR}/${DESIGN}_area.rpt"
puts "  Logic area:  ${RPT_DIR}/${DESIGN}_area_logic.rpt"
puts "  Check:       ${RPT_DIR}/${DESIGN}_check.rpt"
puts "  Width:       ${RPT_DIR}/${DESIGN}_width.rpt"
puts "  All reports: ${RPT_DIR}/"
puts ""
puts "Next Steps:"
puts "  1. Review area and timing reports"
puts "  2. Check SRAM macro instantiation in area report"
puts "  3. Verify 8 SRAM macros are present (2 input + 6 output)"
puts "  4. Proceed to floorplanning with OpenROAD"
puts ""
puts "SRAM Macro Configuration:"
puts "  - 2× RM_IHPSG13_1P_1024x64_c2_bm_bist (Weight + Data)"
puts "  - 6× RM_IHPSG13_1P_256x64_c2_bm_bist (Output A/B/C × 2)"
puts "  - Total: 8 SRAM macros"
puts "========================================================"
puts ""

exit