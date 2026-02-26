# ============================================================
# 03_placement.tcl — Global + Detailed Placement for 8×8 TPU
# ============================================================
#
# Flow:
#   1. Wire RC estimation (Metal3 signal, Metal4 clock)
#   2. Dont_use constraints
#   3. Macro halo padding (SRAM macros)
#   4. Protect IO ring
#   5. Global placement (timing-driven, 40% density)
#   6. Repair design (DRV fixes)
#   7. Tie cell fanout repair
#   8. Detailed placement + legalization
#   9. Filler + decap insertion
#  10. Final parasitic estimation + area/timing report
#
# NOTE: repair_timing removed — causes 1hr+ hang trying to
#       fix SRAM-internal hold violations (hard macro, unfixable).
#       Timing optimization deferred to post-route.
# ============================================================

# source config.tcl
# source $SCRIPT_DIR/init_tech.tcl
# read_db ${RESULT_DIR}/02_pdn.odb

puts ""
puts "========================================="
puts "Stage 3: Placement (8×8 TPU)"
puts "========================================="

set block [ord::get_db_block]
set inst_count [llength [$block getInsts]]
puts "  Total instances: $inst_count"

# ------------------------------------------------------------
# Wire RC Estimation Layers
# ------------------------------------------------------------
set_wire_rc -signal -layer Metal3
set_wire_rc -clock  -layer Metal4

# ------------------------------------------------------------
# Dont_Use Constraints
# ------------------------------------------------------------
if {[info exists DONT_USE] && [llength $DONT_USE] > 0} {
    puts "Applying dont_use constraints..."
    foreach pattern $DONT_USE {
        set_dont_use $pattern
        puts "  - $pattern"
    }
}

# ------------------------------------------------------------
# Macro Halo (Keep-out around SRAMs)
# ------------------------------------------------------------
set site_width 0.48
set pad_sites [expr {int($MACRO_HALO_X / $site_width)}]
puts "Macro halo: ${MACRO_HALO_X}µm → ${pad_sites} sites"

set_placement_padding -masters {RM_IHPSG13_1P_*} \
    -left $pad_sites \
    -right $pad_sites

# ------------------------------------------------------------
# Protect IO Ring (don't move pads/corners)
# ------------------------------------------------------------
set_dont_touch [get_cells -hierarchical -filter "ref_name =~ *sg13g2_IOPad* || ref_name =~ *sg13g2_Corner*"]

# ------------------------------------------------------------
# Surgical Placement Blockages (Keep logic cells away from SRAM corners)
# ------------------------------------------------------------
# These regions correspond to where routing congestion and pin
# conflicts have consistently caused Metal2 spacing violations.
puts "Adding surgical placement blockages near SRAM corners..."
set block [ord::get_db_block]
odb::dbBlockage_create $block [ord::microns_to_dbu 590] [ord::microns_to_dbu 2220] [ord::microns_to_dbu 620] [ord::microns_to_dbu 2245]
odb::dbBlockage_create $block [ord::microns_to_dbu 1400] [ord::microns_to_dbu 2060] [ord::microns_to_dbu 1425] [ord::microns_to_dbu 2085]

# ------------------------------------------------------------
# Global Placement
# ------------------------------------------------------------
puts ""
puts "Running global placement (density=$PLACE_DENSITY, timing-driven)..."

global_placement \
    -density $PLACE_DENSITY \
    -pad_left 2 \
    -pad_right 2 \
    -timing_driven

# ------------------------------------------------------------
# Design Repair (DRV fixes)
# ------------------------------------------------------------
puts ""
puts "Estimating parasitics and repairing design..."
estimate_parasitics -placement
repair_design

# ------------------------------------------------------------
# Tie Cell Fanout Repair
# ------------------------------------------------------------
# Separation=20 spreads tie cells to reduce local congestion
repair_tie_fanout -separation 20 "sg13g2_tiehi/L_HI"
repair_tie_fanout -separation 20 "sg13g2_tielo/L_LO"

# ------------------------------------------------------------
# Detailed Placement + Legalization
# ------------------------------------------------------------
puts ""
puts "Running detailed placement..."
detailed_placement
check_placement -verbose

# ------------------------------------------------------------
# Filler + Decap Insertion
# ------------------------------------------------------------
if {[info exists DECAP_CELLS] && [llength $DECAP_CELLS] > 0} {
    puts "Merging decap cells into filler list..."
    set FILLER_CELLS [concat $DECAP_CELLS $FILLER_CELLS]
}

puts "Placing fillers: $FILLER_CELLS"
filler_placement $FILLER_CELLS

# ------------------------------------------------------------
# Final Parasitic Estimation + Reports
# ------------------------------------------------------------
puts ""
puts "Final parasitic estimation..."
estimate_parasitics -placement

# repair_timing removed — causes 1hr+ hang on SRAM hold violations
# repair_design (above) already handles DRV fixes
# Timing optimization deferred to post-route (05_routing.tcl)

puts ""
puts "========================================="
puts "Placement Results"
puts "========================================="
report_design_area
report_worst_slack -max
report_worst_slack -min

# ------------------------------------------------------------
# Save Checkpoint
# ------------------------------------------------------------
set checkpoint "${RESULT_DIR}/03_placement.odb"
write_db $checkpoint
puts "Saved: $checkpoint"

save_image ${REPORT_DIR}/03_placement.png

