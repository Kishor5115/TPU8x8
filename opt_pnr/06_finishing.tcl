
# ============================================================
#?  Stage 6: Finishing (Timing Check, Filler Insertion)
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

puts ""
puts "========================================="
puts "Stage 6: Finishing"
puts "========================================="
puts ""

#===============================================================
#               TODO : Read SDC
#===============================================================

read_sdc $SDC_FILE
set_propagated_clock [all_clocks]


#===============================================================
#               TODO : Timing Snapshot
# Use placement-based parasitics (routing data loaded from ODB
# may not be accessible for estimate_parasitics -global_routing
# when running standalone).
#===============================================================

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


#===============================================================
#               TODO : Setup Optimization (if needed)
#===============================================================

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


#===============================================================
#               TODO : Hold Report (skip repair — crashes on SRAM pins)
#===============================================================

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


#===============================================================
#               TODO : Placement Verification
#===============================================================

puts "\n--- Placement Verification ---"
catch {check_placement -verbose}


#===============================================================
#               TODO : Design Area
#===============================================================

puts "\n--- Design Area ---"
report_design_area


#===============================================================
#               TODO : Generate Reports
#===============================================================

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
# FILLER CELL INSERTION
# ══════════════════════════════════════════════════════════════
# Ensuring a clean slate before placement to avoid segfaults.
puts "\n--- Filler Cell Insertion ---"
puts "  Cleaning existing fillers/decaps..."
set block [ord::get_db_block]
set del_count 0
foreach inst [$block getInsts] {
    set mname [[$inst getMaster] getName]
    if {[string match "sg13g2_fill_*" $mname] || [string match "sg13g2_decap_*" $mname]} {
        odb::dbInst_destroy $inst
        incr del_count
    }
}
puts "  Deleted $del_count cells"
detailed_placement

set stdfill [list \
    sg13g2_decap_8 \
    sg13g2_decap_4 \
    sg13g2_fill_8 \
    sg13g2_fill_4 \
    sg13g2_fill_2 \
    sg13g2_fill_1 \
]
puts "  Using masters: $stdfill"

if {[catch {
    filler_placement $stdfill
    global_connect
    puts "   Filler placement complete"
    
    # Save checkpoint after successful filler insertion
    write_db ${RESULT_DIR}/06_post_filler.odb
    puts "  Checkpoint saved: ${RESULT_DIR}/06_post_filler.odb"
} err]} {
    puts "   WARNING: filler_placement failed: $err"
    puts "  (If this persists, fillers can be added in KLayout)"
}


#===============================================================
#               TODO : Layout Image
#===============================================================

if {[catch {save_image ${REPORT_DIR}/06_final.png} err]} {
    puts "⚠ WARNING: Could not save image"
} else {
    puts "Saved image: ${REPORT_DIR}/06_final.png"
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
