
# ============================================================
#?  05_routing.tcl — Global + Detailed Routing for 8×8 TPU
# ============================================================
#
# Design: 8 SRAM macros + ~2816 FFs, single clock domain
# Strategy:
#   - Signal layers: Metal2–TopMetal1
#   - Clock layers:  Metal2–TopMetal1
#   - Conservative layer adjustments for SRAM pin congestion
#   - Post-GR optimization (repair_design)
#   - Direct global → detailed route flow
#   - filler_placement REMOVED (segfaults with IO pad ring)
# ============================================================

read_sdc $SDC_FILE

puts ""
puts "========================================="
puts "Stage 5: Routing"
puts "========================================="
puts ""

#===============================================================
#               TODO : Wire RC & Routing Layer Setup
#===============================================================

set_wire_rc -signal -layer Metal3
set_wire_rc -clock  -layer Metal4

set_routing_layers -signal Metal2-TopMetal1 -clock Metal2-TopMetal1

# Layer adjustments — reduce capacity on congested layers
set_global_routing_layer_adjustment Metal2-Metal3 0.30
set_global_routing_layer_adjustment TopMetal1 0.20

puts "Routing layers configured"
puts "  Signal: Metal2-TopMetal1"
puts "  Clock:  Metal2-TopMetal1"
puts "  Adjustment: Metal2-Metal3 30%, TopMetal1 20%"
puts ""

#===============================================================
#               TODO : Surgical Routing Blockages
# Force router to use higher layers in Metal2 hotspots
# where DRCs occur near SRAM macro corners.
#===============================================================

puts "Adding surgical routing blockages on Metal2..."
set block [ord::get_db_block]
set tech [ord::get_db_tech]
set m2 [$tech findLayer "Metal2"]
set m3 [$tech findLayer "Metal3"]
odb::dbObstruction_create $block $m2 [ord::microns_to_dbu 600] [ord::microns_to_dbu 2228] [ord::microns_to_dbu 612] [ord::microns_to_dbu 2237]
odb::dbObstruction_create $block $m2 [ord::microns_to_dbu 1410] [ord::microns_to_dbu 2072] [ord::microns_to_dbu 1411] [ord::microns_to_dbu 2073]
odb::dbObstruction_create $block $m2 [ord::microns_to_dbu 1493.9] [ord::microns_to_dbu 2145.9] [ord::microns_to_dbu 1495.5] [ord::microns_to_dbu 2146.4]
odb::dbObstruction_create $block $m2 [ord::microns_to_dbu 1543.2] [ord::microns_to_dbu 2219.1] [ord::microns_to_dbu 1547.5] [ord::microns_to_dbu 2219.5]
odb::dbObstruction_create $block $m3 [ord::microns_to_dbu 1495.0] [ord::microns_to_dbu 2153.8] [ord::microns_to_dbu 1495.4] [ord::microns_to_dbu 2154.1]
# DRC violations (05_route_drc.rpt):
#   Metal2 spacing @ (605.665,2335.10)-(605.760,2335.30)
#   Metal2 spacing @ (605.665,2338.88)-(605.760,2339.08)
#   Metal2 spacing @ (605.665,2395.58)-(605.760,2395.78)
# Extended blockages with 0.15 µm margin on all sides to ensure full coverage.
odb::dbObstruction_create $block $m2 [ord::microns_to_dbu 605.50] [ord::microns_to_dbu 2334.80] [ord::microns_to_dbu 606.00] [ord::microns_to_dbu 2335.60]
odb::dbObstruction_create $block $m2 [ord::microns_to_dbu 605.50] [ord::microns_to_dbu 2338.60] [ord::microns_to_dbu 606.00] [ord::microns_to_dbu 2339.30]
odb::dbObstruction_create $block $m2 [ord::microns_to_dbu 605.50] [ord::microns_to_dbu 2395.30] [ord::microns_to_dbu 606.00] [ord::microns_to_dbu 2396.10]

puts "   Metal2 blockages added at SRAM corners (DRC-refined bbox)"
puts ""

#===============================================================
#               TODO : Global Route
#===============================================================

puts "Running global route..."
set start_time [clock seconds]

global_route \
    -guide_file ${RESULT_DIR}/route.guide \
    -congestion_report_file ${REPORT_DIR}/05_congestion.rpt \
    -allow_congestion \
    -verbose

set elapsed [expr {[clock seconds] - $start_time}]
puts "Global route completed in ${elapsed}s"
puts ""

#===============================================================
#               TODO : Design Repair (Slew, Cap, Fanout)
#===============================================================

puts "Repairing design violations..."
estimate_parasitics -placement
repair_design -verbose

# Legalize any buffers inserted by repair_design
detailed_placement

puts "Design repair complete"
puts ""

#===============================================================
#               TODO : Detailed Route
#===============================================================

puts "Running detailed route..."
set_thread_count 8
set start_time [clock seconds]

detailed_route \
    -output_drc ${REPORT_DIR}/05_route_drc.rpt \
    -droute_end_iter 64 \
    -save_guide_updates \
    -clean_patches \
    -verbose 1

if {[file exists ${REPORT_DIR}/05_route_drc.rpt] && [file size ${REPORT_DIR}/05_route_drc.rpt] > 0} {
    puts "DRC violations remain after first detailed route pass; running cleanup pass..."
    if {[catch {
        detailed_route \
            -output_drc ${REPORT_DIR}/05_route_drc.rpt \
            -droute_end_iter 80 \
            -save_guide_updates \
            -clean_patches \
            -verbose 1x
    } dr_retry_err]} {
        puts "WARNING: cleanup detailed_route pass failed: $dr_retry_err"
        puts "WARNING: Continuing flow with first-pass routed result."
    }
}

set elapsed [expr {[clock seconds] - $start_time}]
puts "Detailed route completed in ${elapsed}s"
puts ""


global_connect

#===============================================================
#               TODO : Save Routed Design
#===============================================================

puts "========================================="
puts "Saving Routed Design"
puts "========================================="

write_db ${RESULT_DIR}/05_route.odb
puts "Saved: ${RESULT_DIR}/05_route.odb"

write_def ${RESULT_DIR}/tpu_chip.def
puts "Saved: ${RESULT_DIR}/tpu_chip.def"
puts ""

#===============================================================
#               TODO : Post-Route Timing & DRC Reports
#===============================================================

puts "========================================="
puts "Post-Route Timing"
puts "========================================="

estimate_parasitics -placement
report_worst_slack -max
report_worst_slack -min
report_tns

report_design_area

puts ""
puts "DRC Report: ${REPORT_DIR}/05_route_drc.rpt"

if {[catch {save_image ${REPORT_DIR}/05_route.png} err]} {
    puts "⚠ WARNING: Could not save image"
} else {
    puts "Saved image: ${REPORT_DIR}/05_route.png"
}

puts ""
puts "========================================="
puts "Stage 5 Complete"
puts "========================================="
puts "  Next: Run 06_finishing.tcl"
puts "=============================================================================================="
puts ""