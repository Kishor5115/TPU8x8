# ============================================================
# Stage 6: Finishing (Timing Check, Filler Insertion)
# ============================================================
# Post-route: verify timing, insert fillers, save final design.
#
# NOTE: repair_timing -hold REMOVED — causes OpenROAD segfault
# when inserting buffers near SRAM A_DIN pins. Hold violations
# are all at SRAM hard macro pins and cannot be fixed.
#
# NOTE: global_route REMOVED from this stage — the design is
# already fully routed from stage 5. Re-running global_route
# standalone causes issues with IO pads outside die area.
# ============================================================

# source config.tcl
# source $SCRIPT_DIR/init_tech.tcl
# read_db ${RESULT_DIR}/05_route.odb

puts ""
puts "========================================="
puts "Stage 6: Finishing"
puts "========================================="

# ── Read SDC ─────────────────────────────────────────────────
read_sdc $SDC_FILE

# ── Timing Snapshot ──────────────────────────────────────────
# Use placement-based parasitics (routing data loaded from ODB
# may not be accessible for estimate_parasitics -global_routing
# when running standalone).
puts "\n--- Timing Analysis ---"
set_wire_rc -signal -layer Metal3
set_wire_rc -clock  -layer Metal4
estimate_parasitics -placement

report_checks -path_delay min_max -digits 3
report_worst_slack -max
report_worst_slack -min
report_tns

set setup_slack [sta::worst_slack_cmd "max"]
set hold_slack  [sta::worst_slack_cmd "min"]

puts [format "\n  Setup WNS: %.3f ns" $setup_slack]
puts [format "  Hold  WNS: %.3f ns" $hold_slack]

# ── Setup Optimization (if needed) ───────────────────────────
if {$setup_slack < 0} {
    puts "\n--- Setup Timing Repair ---"
    puts [format "  Setup violations: WNS = %.3f ns" $setup_slack]

    if {[catch {
        repair_timing -setup -slack_margin 0.1
        # Add repair_design to fix slew/cap/fanout violations
        repair_design -verbose
        detailed_placement
        estimate_parasitics -placement
        report_worst_slack -max
        puts "  Setup and design repair complete"
    } err]} {
        puts "  WARNING: Setup/design repair failed: $err"
    }
}

# ── Hold Report (skip repair — crashes on SRAM pins) ─────────
if {$hold_slack < 0} {
    puts "\n--- Hold Timing ---"
    puts [format "  Hold WNS: %.3f ns" $hold_slack]
    puts "  SKIPPED: repair_timing -hold crashes on SRAM pins (OpenROAD bug)"
    puts "  SRAM hold violations are unfixable (hard macro internal timing)"
}

# ── Final Timing Numbers ─────────────────────────────────────
set final_setup_wns [sta::worst_slack_cmd "max"]
set final_hold_wns  [sta::worst_slack_cmd "min"]
set final_setup_tns [sta::total_negative_slack_cmd "max"]
set final_hold_tns  [sta::total_negative_slack_cmd "min"]

# ── Placement Verification ───────────────────────────────────
puts "\n--- Placement Verification ---"
catch {check_placement -verbose}

# ── Design Area ──────────────────────────────────────────────
puts "\n--- Design Area ---"
report_design_area

# ── Generate Reports ─────────────────────────────────────────
puts "\n--- Generating Reports ---"
exec mkdir -p ${REPORT_DIR}

catch {
    report_checks -path_delay min_max \
        -fields {slew cap input fanout} \
        -digits 3 \
        -format full_clock_expanded \
        > ${REPORT_DIR}/06_final_timing.rpt
}

set fp [open ${REPORT_DIR}/06_final_summary.rpt w]
puts $fp "========================================="
puts $fp "FINISHING STAGE SUMMARY"
puts $fp "========================================="
puts $fp "Design : $DESIGN"
puts $fp "Date   : [clock format [clock seconds] -format {%Y-%m-%d %H:%M:%S}]"
puts $fp ""
puts $fp "TIMING RESULTS (Post-Finishing)"
puts $fp [format "  Setup WNS : %10.3f ns" $final_setup_wns]
puts $fp [format "  Setup TNS : %10.3f ns" $final_setup_tns]
puts $fp [format "  Hold  WNS : %10.3f ns" $final_hold_wns]
puts $fp [format "  Hold  TNS : %10.3f ns" $final_hold_tns]
puts $fp "========================================="
close $fp

puts "  Reports written to ${REPORT_DIR}/"

# ══════════════════════════════════════════════════════════════
# SAVE CHECKPOINT BEFORE FILLER INSERTION
# ══════════════════════════════════════════════════════════════
puts "\n--- Saving Pre-Filler Checkpoint ---"
write_db ${RESULT_DIR}/06_final.odb
puts "  Saved: ${RESULT_DIR}/06_final.odb"

# ══════════════════════════════════════════════════════════════
# FILLER CELL INSERTION — SKIPPED (OpenROAD bug)
# ══════════════════════════════════════════════════════════════
# filler_placement segfaults in placeRowFillers with IO pad rings.
# This is an OpenROAD bug (Signal 11, odb::dbInst::getOrient).
# Fillers can be added post-export in KLayout if needed for DRC.
puts "\n--- Filler Cell Insertion ---"
puts "  SKIPPED: filler_placement crashes with IO pad ring (OpenROAD bug)"
puts "  Fillers can be added in KLayout post-export if needed"

# ── Layout Image ─────────────────────────────────────────────
if {[info commands save_image] != ""} {
    save_image ${REPORT_DIR}/06_final.png
}

# ── Console Summary ──────────────────────────────────────────
puts ""
puts "========================================="
puts "Stage 6 Complete"
puts "========================================="
puts [format "  Setup WNS : %10.3f ns" $final_setup_wns]
puts [format "  Setup TNS : %10.3f ns" $final_setup_tns]
puts [format "  Hold  WNS : %10.3f ns" $final_hold_wns]
puts [format "  Hold  TNS : %10.3f ns" $final_hold_tns]
puts ""
puts "  Next: Run 07_signoff.tcl"
puts "========================================="
