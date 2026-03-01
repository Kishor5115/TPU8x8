
# ============================================================
#?  Stage 7: Signoff (Final Verification, Reports & Output Files)
# ============================================================
# Comprehensive signoff: timing analysis, DRC, output generation,
# and professional summary report for tape-out readiness.
#
# Report generation pattern from:
# github.com/pulp-platform/croc (openroad/scripts/reports.tcl)
# ============================================================

# source config.tcl

# ── Helper: write to report file (append mode) ──────────────
# Reference: Croc SoC reports.tcl report_puts
proc report_puts { filename out } {
    set fileId [open $filename a]
    puts $fileId $out
    close $fileId
}
# read_db ${RESULT_DIR}/06_final.odb

read_sdc $SDC_FILE

puts ""
puts "╔═══════════════════════════════════════════════════════════╗"
puts "║              STAGE 7: SIGNOFF                            ║"
puts "╚═══════════════════════════════════════════════════════════╝"

#===============================================================
#               TODO : 1. Parasitic Extraction
#===============================================================

puts "\n━━━ 1. Parasitic Extraction ━━━"

estimate_parasitics -placement
puts "  Parasitic extraction complete (placement-based)"


#===============================================================
#               TODO : 2. Timing Analysis (Typical Corner)
#===============================================================

puts "\n━━━ 2. Timing Analysis ━━━"

puts "\n  ── Typical Corner (1.2V, 25°C) ──"
report_checks -path_delay min_max \
    -fields {slew cap input fanout} \
    -digits 4 \
    -format full_clock_expanded

report_worst_slack -min
report_worst_slack -max
report_tns

# Capture timing metrics
set tt_setup_wns [sta::worst_slack_cmd "max"]
set tt_hold_wns  [sta::worst_slack_cmd "min"]
set tt_setup_tns [sta::total_negative_slack_cmd "max"]
set tt_hold_tns  [sta::total_negative_slack_cmd "min"]

puts ""
puts "  ┌─────────────────────────────────────────┐"
puts "  │          Timing Summary (TT)            │"
puts "  ├──────────┬──────────────┬───────────────┤"
puts "  │  Check   │     WNS (ns) │    TNS (ns)   │"
puts "  ├──────────┼──────────────┼───────────────┤"
puts [format "  │  Setup   │ %12.4f │ %13.4f │" $tt_setup_wns $tt_setup_tns]
puts [format "  │  Hold    │ %12.4f │ %13.4f │" $tt_hold_wns $tt_hold_tns]
puts "  └──────────┴──────────────┴───────────────┘"

# Note: For full multi-corner signoff, add SS/FF corners here:
# define_corners ss ff
# read_liberty -corner ss <slow_lib>
# read_liberty -corner ff <fast_lib>


#===============================================================
#               TODO : 3. Constraint Coverage
#===============================================================

puts "\n━━━ 3. Constraint Coverage ━━━"

puts "\n  ── Unconstrained Paths ──"
report_checks -unconstrained -fields {slew cap input fanout}

puts "\n  ── Clock Skew ──"
report_clock_skew


#===============================================================
#               TODO : 4. Power Analysis
#===============================================================

puts "\n━━━ 4. Power Analysis ━━━"

catch {
    report_power -corner tt
    puts "  Power analysis complete"
}


#===============================================================
#               TODO : 5. Design Rule Checks
#===============================================================

puts "\n━━━ 5. Design Rule Checks ━━━"

puts "\n  ── Placement Check ──"
check_placement -verbose

puts "\n  ── Slew / Capacitance / Fanout Violations ──"
catch {report_check_types -max_slew -max_capacitance -max_fanout -violators}

puts "\n  NOTE: Final DRC/LVS must be run with Calibre, ICV, or KLayout"


#===============================================================
#               TODO : 6. Output File Generation
#===============================================================

puts "\n━━━ 6. Output File Generation ━━━"

exec mkdir -p ${RESULT_DIR}

# Final Verilog netlist
puts "  Writing final Verilog netlist..."
write_verilog ${RESULT_DIR}/${DESIGN}_final.v
puts "    → ${RESULT_DIR}/${DESIGN}_final.v"

# Final ODB (with fillers)
write_db ${RESULT_DIR}/07_signoff.odb
puts "    → ${RESULT_DIR}/07_signoff.odb"

# Final DEF
puts "  Writing final DEF..."
write_def ${RESULT_DIR}/${DESIGN}_final.def
puts "    → ${RESULT_DIR}/${DESIGN}_final.def"

# Final SDC
puts "  Writing final SDC..."
write_sdc ${RESULT_DIR}/${DESIGN}_final.sdc
puts "    → ${RESULT_DIR}/${DESIGN}_final.sdc"

# SPEF parasitics
if {[info commands write_spef] != ""} {
    puts "  Writing SPEF parasitics..."
    write_spef ${RESULT_DIR}/${DESIGN}_final.spef
    puts "    → ${RESULT_DIR}/${DESIGN}_final.spef"
}

  puts "\n  GDSII: Generate with KLayout after signoff"
  puts "    Run: ./klayout/def2gds.sh"


#===============================================================
#               TODO : 7. Signoff Report Generation
# Pattern: Croc SoC reports.tcl — use >> for append, report_puts
# for stdout-only commands, ODB API for area computation.
#===============================================================

puts "\n━━━ 7. Generating Signoff Reports ━━━"

exec mkdir -p ${REPORT_DIR}/signoff

# (a) Final timing report
set rpt_file ${REPORT_DIR}/signoff/timing_final.rpt
set fileId [open $rpt_file w]; close $fileId
report_puts $rpt_file "=========================================================================="
report_puts $rpt_file "signoff report_checks -path_delay min"
report_puts $rpt_file "--------------------------------------------------------------------------"
report_checks -path_delay min -fields {slew cap input fanout} -digits 4 -format full_clock_expanded >> $rpt_file
report_puts $rpt_file "\n=========================================================================="
report_puts $rpt_file "signoff report_checks -path_delay max"
report_puts $rpt_file "--------------------------------------------------------------------------"
report_checks -path_delay max -fields {slew cap input fanout} -digits 4 -format full_clock_expanded >> $rpt_file
puts "    ✓ timing_final.rpt"

# (b) Clock reports
catch {report_clock_skew > ${REPORT_DIR}/signoff/clock_skew.rpt;          puts "    ✓ clock_skew.rpt"}
catch {report_clock_min_period > ${REPORT_DIR}/signoff/clock_period.rpt;   puts "    ✓ clock_period.rpt"}

# (c) Area report — report_design_area only writes to stdout
#     Use ODB API to compute area (reference: Croc SoC reports_area.tcl)
puts "    Generating area report..."
set rpt_file ${REPORT_DIR}/signoff/area.rpt
if {[catch {
    set db   [::ord::get_db]
    set block [[$db getChip] getBlock]
    set dbu_per_uu [expr double([[$db getTech] getDbUnitsPerMicron])]

    set die_bbox  [$block getDieArea]
    set die_area  [expr {[$die_bbox dx] * [$die_bbox dy] / ($dbu_per_uu * $dbu_per_uu)}]
    set core_bbox [$block getCoreArea]
    set core_area [expr {[$core_bbox dx] * [$core_bbox dy] / ($dbu_per_uu * $dbu_per_uu)}]

    # Count stdcell + macro area
    set stdcell_area 0.0
    set macro_area   0.0
    set stdcell_count 0
    set macro_count   0
    foreach inst [$block getInsts] {
        set master [$inst getMaster]
        if {[$master isFiller]} continue
        set inst_area [expr {[$master getWidth] * [$master getHeight] / ($dbu_per_uu * $dbu_per_uu)}]
        if {[$master isBlock]} {
            set macro_area [expr {$macro_area + $inst_area}]
            incr macro_count
        } else {
            set stdcell_area [expr {$stdcell_area + $inst_area}]
            incr stdcell_count
        }
    }

    set total_active [expr {$stdcell_area + $macro_area}]
    set util         [expr {$core_area > 0 ? $total_active / $core_area * 100.0 : 0.0}]
    set stdcell_util [expr {($core_area - $macro_area) > 0 ? $stdcell_area / ($core_area - $macro_area) * 100.0 : 0.0}]

    set fp [open $rpt_file w]
    puts $fp "=========================================================================="
    puts $fp "Design Area Summary"
    puts $fp "=========================================================================="
    puts $fp [format "Die Area:          %.2f um^2" $die_area]
    puts $fp [format "Core Area:         %.2f um^2" $core_area]
    puts $fp [format "Total Active Area: %.2f um^2" $total_active]
    puts $fp [format "  Std Cell Area:   %.2f um^2  (%d instances)" $stdcell_area $stdcell_count]
    puts $fp [format "  Macro Area:      %.2f um^2  (%d instances)" $macro_area $macro_count]
    puts $fp ""
    puts $fp [format "Core Utilization:       %.1f%%" $util]
    puts $fp [format "Std Cell Utilization:   %.1f%%" $stdcell_util]
    puts $fp "=========================================================================="
    close $fp
    puts "    ✓ area.rpt"
} err]} {
    puts "    ⚠ Area report failed: $err"
}

# (d) Unconstrained paths
catch {report_checks -unconstrained -fields {slew cap input fanout} > ${REPORT_DIR}/signoff/unconstrained.rpt; puts "    ✓ unconstrained.rpt"}

# (e) Violation report
set rpt_file ${REPORT_DIR}/signoff/violations.rpt
set fileId [open $rpt_file w]; close $fileId
report_puts $rpt_file "=========================================================================="
report_puts $rpt_file "signoff report_check_types -max_slew -max_capacitance -max_fanout -violators"
report_puts $rpt_file "--------------------------------------------------------------------------"
catch {report_check_types -max_slew -max_capacitance -max_fanout -violators >> $rpt_file}
report_puts $rpt_file "\n=========================================================================="
report_puts $rpt_file "signoff max_slew_violation_count"
report_puts $rpt_file "--------------------------------------------------------------------------"
report_puts $rpt_file "max slew violation count [sta::max_slew_violation_count]"
report_puts $rpt_file "\n=========================================================================="
report_puts $rpt_file "signoff max_fanout_violation_count"
report_puts $rpt_file "--------------------------------------------------------------------------"
report_puts $rpt_file "max fanout violation count [sta::max_fanout_violation_count]"
report_puts $rpt_file "\n=========================================================================="
report_puts $rpt_file "signoff max_cap_violation_count"
report_puts $rpt_file "--------------------------------------------------------------------------"
report_puts $rpt_file "max cap violation count [sta::max_capacitance_violation_count]"
puts "    ✓ violations.rpt"

# (f) Power report — must specify -corner for multi-corner
set rpt_file ${REPORT_DIR}/signoff/power.rpt
set fileId [open $rpt_file w]; close $fileId
report_puts $rpt_file "=========================================================================="
report_puts $rpt_file "signoff report_power -corner tt"
report_puts $rpt_file "--------------------------------------------------------------------------"
catch {report_power -corner tt >> $rpt_file}
report_puts $rpt_file "\n=========================================================================="
report_puts $rpt_file "signoff report_power_metric -corner tt"
report_puts $rpt_file "--------------------------------------------------------------------------"
catch {report_power_metric -corner tt >> $rpt_file}
puts "    ✓ power.rpt"


#===============================================================
#               TODO : 8. Professional Signoff Summary
#===============================================================

set timing_clean 1
if {$tt_setup_wns < 0 || $tt_hold_wns < 0} {
    set timing_clean 0
}

set fp [open ${REPORT_DIR}/signoff/summary.rpt w]

puts $fp "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
puts $fp "┃           TPU ASIC IMPLEMENTATION — SIGNOFF SUMMARY              ┃"
puts $fp "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
puts $fp ""
puts $fp "  Design Name    : $DESIGN"
puts $fp "  Technology     : IHP SG13G2 130nm"
puts $fp "  Target Freq    : ${CLK_FREQ_MHZ} MHz (${CLK_PERIOD} ns period)"
puts $fp "  Die Size       : ${DIE_WIDTH} µm × ${DIE_HEIGHT} µm"
puts $fp "  Generated      : [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $fp ""
puts $fp "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts $fp "  TIMING ANALYSIS"
puts $fp "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts $fp ""
puts $fp "  Corner   │  Check  │     WNS (ns) │     TNS (ns) │  Status"
puts $fp "  ─────────┼─────────┼──────────────┼──────────────┼──────────"

if {$tt_setup_wns >= 0} {
    puts $fp [format "  Typical  │  Setup  │ %12.4f │ %12.4f │  PASS" $tt_setup_wns $tt_setup_tns]
} else {
    puts $fp [format "  Typical  │  Setup  │ %12.4f │ %12.4f │  FAIL" $tt_setup_wns $tt_setup_tns]
}

if {$tt_hold_wns >= 0} {
    puts $fp [format "  Typical  │  Hold   │ %12.4f │ %12.4f │  PASS" $tt_hold_wns $tt_hold_tns]
} else {
    puts $fp [format "  Typical  │  Hold   │ %12.4f │ %12.4f │  FAIL" $tt_hold_wns $tt_hold_tns]
}

puts $fp ""

if {$timing_clean} {
    puts $fp "  ┌────────────────────────────────────────────┐"
    puts $fp "  │  ✅  ALL TIMING CHECKS PASSED              │"
    puts $fp "  └────────────────────────────────────────────┘"
} else {
    puts $fp "  ┌────────────────────────────────────────────┐"
    puts $fp "  │  ❌  TIMING VIOLATIONS DETECTED             │"
    puts $fp "  └────────────────────────────────────────────┘"
}

puts $fp ""
puts $fp "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts $fp "  OUTPUT FILES"
puts $fp "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts $fp ""
puts $fp "  File                │  Path"
puts $fp "  ────────────────────┼─────────────────────────────────────────"
puts $fp "  Final Netlist       │  ${RESULT_DIR}/${DESIGN}_final.v"
puts $fp "  Final DEF           │  ${RESULT_DIR}/${DESIGN}_final.def"
puts $fp "  Final SDC           │  ${RESULT_DIR}/${DESIGN}_final.sdc"
puts $fp "  Final SPEF          │  ${RESULT_DIR}/${DESIGN}_final.spef"
puts $fp "  GDSII               │  ${RESULT_DIR}/${DESIGN}_final.gds (via KLayout)"
puts $fp "  Signoff Checkpoint  │  ${RESULT_DIR}/07_signoff.odb"
puts $fp ""
puts $fp "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts $fp "  SIGNOFF REPORTS"
puts $fp "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts $fp ""
puts $fp "  Report              │  Path"
puts $fp "  ────────────────────┼─────────────────────────────────────────"
puts $fp "  Timing              │  ${REPORT_DIR}/signoff/timing_final.rpt"
puts $fp "  Clock Skew          │  ${REPORT_DIR}/signoff/clock_skew.rpt"
puts $fp "  Clock Period        │  ${REPORT_DIR}/signoff/clock_period.rpt"
puts $fp "  Area                │  ${REPORT_DIR}/signoff/area.rpt"
puts $fp "  Violations          │  ${REPORT_DIR}/signoff/violations.rpt"
puts $fp "  Unconstrained       │  ${REPORT_DIR}/signoff/unconstrained.rpt"
puts $fp "  Power               │  ${REPORT_DIR}/signoff/power.rpt"
puts $fp ""
puts $fp "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts $fp "  NEXT STEPS"
puts $fp "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
puts $fp ""
puts $fp "  1. Generate GDSII    :  ./klayout/def2gds.sh"
puts $fp "  2. DRC Verification  :  Run DRC deck in KLayout / Calibre"
puts $fp "  3. LVS Verification  :  Run LVS deck in KLayout / Calibre"
puts $fp "  4. Tape-out          :  Submit GDSII when DRC & LVS are clean"
puts $fp ""

if {$timing_clean} {
    puts $fp "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    puts $fp "┃          ✅  DESIGN READY FOR TAPE-OUT                            ┃"
    puts $fp "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
} else {
    puts $fp "┏━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓"
    puts $fp "┃          ❌  DESIGN REQUIRES TIMING FIXES BEFORE TAPE-OUT        ┃"
    puts $fp "┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛"
}

close $fp
puts "    ✓ summary.rpt (Professional Signoff Summary)"


#===============================================================
#               TODO : 9. Save Final Checkpoint
#===============================================================

puts "\n━━━ 8. Saving Final Checkpoint ━━━"

write_db ${RESULT_DIR}/07_signoff.odb
puts "  Checkpoint: ${RESULT_DIR}/07_signoff.odb"

# Layout image
if {[catch {save_image ${REPORT_DIR}/signoff/layout_final.png} err]} {
    puts "⚠ WARNING: Could not save layout image"
} else {
    puts "  Layout image: ${REPORT_DIR}/signoff/layout_final.png"
}


# ══════════════════════════════════════════════════════════════
# FINAL CONSOLE SUMMARY
# ══════════════════════════════════════════════════════════════
puts ""
puts "╔═══════════════════════════════════════════════════════════╗"
puts "║              SIGNOFF COMPLETE                            ║"
puts "╠═══════════════════════════════════════════════════════════╣"
puts [format "║  Setup WNS : %10.4f ns                                ║" $tt_setup_wns]
puts [format "║  Setup TNS : %10.4f ns                                ║" $tt_setup_tns]
puts [format "║  Hold  WNS : %10.4f ns                                ║" $tt_hold_wns]
puts [format "║  Hold  TNS : %10.4f ns                                ║" $tt_hold_tns]
puts "╠═══════════════════════════════════════════════════════════╣"

if {$timing_clean} {
    puts "║  ✅ TIMING CLEAN — READY FOR GDS GENERATION              ║"
} else {
    puts "║  ❌ TIMING VIOLATIONS — REQUIRES FIXES                    ║"
}

puts "╠═══════════════════════════════════════════════════════════╣"
puts "║  Output files : ${RESULT_DIR}/"
puts "║  Reports      : ${REPORT_DIR}/signoff/"
puts "║  Next step    : ./klayout/def2gds.sh                     ║"
puts "╚═══════════════════════════════════════════════════════════╝"
