# ============================================================
# 05_routing.tcl — Global + Detailed Routing for 8×8 TPU
# ============================================================
#
# Design: 8 SRAM macros + ~2816 FFs, single clock domain
# Strategy:
#   - Signal layers: Metal2–TopMetal1
#   - Clock layers:  Metal2–TopMetal1
#   - Conservative layer adjustments for SRAM pin congestion
#   - Post-GR optimization skipped (causes OOM on SRAM nets)
#   - Direct global → detailed route flow
#   - filler_placement REMOVED (segfaults with IO pad ring)
# ============================================================

# source config.tcl
# source $SCRIPT_DIR/init_tech.tcl
# read_db ${RESULT_DIR}/04_cts.odb

read_sdc $SDC_FILE

puts ""
puts "========================================="
puts "Stage 5: Routing"
puts "========================================="

# ------------------------------------------------------------
# Wire RC & Routing Layer Setup
# ------------------------------------------------------------
set_wire_rc -signal -layer Metal3
set_wire_rc -clock  -layer Metal4

set_routing_layers -signal Metal2-TopMetal1 -clock Metal2-TopMetal1

# Layer adjustments — reduce capacity on congested layers
set_global_routing_layer_adjustment Metal2-Metal3 0.30
set_global_routing_layer_adjustment TopMetal1 0.20

# ------------------------------------------------------------
# Global Route
# ------------------------------------------------------------
puts "\n--- Global Route ---"
set start_time [clock seconds]

global_route \
    -guide_file ${RESULT_DIR}/route.guide \
    -congestion_report_file ${REPORT_DIR}/05_congestion.rpt \
    -allow_congestion \
    -verbose

set elapsed [expr {[clock seconds] - $start_time}]
puts "Global route completed in ${elapsed}s"

# ------------------------------------------------------------
# Design Repair (Slew, Capacitance, Fanout)
# ------------------------------------------------------------
# Performing repair_design after global route ensures that 
# buffering and sizing account for global routing parasitics.
puts "\n--- Design Repair ---"
estimate_parasitics -global_routing
repair_design -verbose

# Legalize any buffers inserted by repair_design
detailed_placement

# ------------------------------------------------------------
# Detailed Route
# ------------------------------------------------------------
puts "\n--- Detailed Route ---"
set_thread_count 8
set start_time [clock seconds]

detailed_route \
    -output_drc ${REPORT_DIR}/05_route_drc.rpt \
    -droute_end_iter 40 \
    -save_guide_updates \
    -clean_patches \
    -verbose 1

set elapsed [expr {[clock seconds] - $start_time}]
puts "Detailed route completed in ${elapsed}s"

# ------------------------------------------------------------
# NOTE: filler_placement REMOVED — causes OpenROAD segfault
# (Signal 11 in placeRowFillers with IO pad ring).
# Tcl catch{} cannot trap C-level crashes.
# Fillers are cosmetic for DRC — can be added in KLayout.
# ------------------------------------------------------------

global_connect

# ------------------------------------------------------------
# Save Results FIRST (before reports, in case anything crashes)
# ------------------------------------------------------------
puts "\n========================================="
puts "Saving Routed Design"
puts "========================================="

write_db ${RESULT_DIR}/05_route.odb
puts "Saved: ${RESULT_DIR}/05_route.odb"

write_def ${RESULT_DIR}/tpu_chip.def
puts "Saved: ${RESULT_DIR}/tpu_chip.def"

# ------------------------------------------------------------
# Post-Route Reports
# ------------------------------------------------------------
puts "\n========================================="
puts "Post-Route Timing"
puts "========================================="

estimate_parasitics -placement
report_worst_slack -max
report_worst_slack -min
report_tns

report_design_area

# DRC summary
puts "\n--- DRC Report ---"
puts "  See: ${REPORT_DIR}/05_route_drc.rpt"

if {[info commands save_image] != ""} {
    save_image ${REPORT_DIR}/05_route.png
}

puts "\n========================================="
puts "Stage 5 Complete"
puts "========================================="
puts "  Next: Run 06_finishing.tcl"