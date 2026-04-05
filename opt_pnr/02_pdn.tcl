


puts "========================================="
puts "Stage 2: Power Distribution Network (PDN)"
puts "========================================="
puts ""

#===============================================================
#               TODO : Load Floorplan Checkpoint
#===============================================================

# if {![file exists ${RESULT_DIR}/01_floorplan.odb]} {
#     puts "ERROR: Floorplan checkpoint not found!"
#     puts "  Run 01_floorplan.tcl first"
#     exit 1
# }
# source config.tcl
# read_db ${RESULT_DIR}/01_floorplan.odb
# puts "Loaded floorplan checkpoint"
# puts ""

#===============================================================
#               TODO : Clear Dont Touch on Instances
#===============================================================

set block [ord::get_db_block]
foreach inst [$block getInsts] {
    $inst setDoNotTouch 0
}

puts "Cleared dont_touch on all instances"
puts ""

#================================================================================
#               TODO : Global Power & Ground Connections
# Connect all power pins to global VDD/VSS nets
# Pattern covers: std cells (VDD/VSS), SRAMs (VDD!/VSS!), IO (vdd/iovdd)
#================================================================================


puts "Establishing global power connections..."

add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VDD} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VDD!} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VDDARRAY!} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {vdd} -power
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {iovdd} -power

add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VSS} -ground
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VSS!} -ground
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {vss} -ground
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {iovss} -ground

global_connect

puts "Global power connections established"
puts ""

#===============================================================================
#               TODO : Define Voltage Domain
#===============================================================================

set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}

puts "Voltage domain CORE: VDD / VSS"
puts ""

#===============================================================================
#               TODO : Configure PDN Grid Parameters
# Stripe dimensions from config.tcl (PDN_STRIPE_WIDTH, PDN_STRIPE_PITCH)
# Pitch = 40µm aligned to SRAM row height for optimal connectivity
#===============================================================================


puts "Initializing PDN grid..."

define_pdn_grid -name {core_grid} -voltage_domains {CORE}

set ring_width   6.0
set ring_spacing 2.0
set ring_offset  2.0

set stripe_width $PDN_STRIPE_WIDTH
set stripe_pitch $PDN_STRIPE_PITCH
set stripe_offset [expr {$stripe_pitch / 2.0}]

puts "  Ring (M3/M4):   ${ring_width}µm wide, ${ring_spacing}µm spacing"
puts "  Stripes (M4/M5): ${stripe_width}µm @ ${stripe_pitch}µm pitch"
puts ""

#===============================================================================
#               TODO : Add Metal1 Followpin Distribution
#===============================================================================

add_pdn_stripe -grid {core_grid} \
    -layer {Metal1} \
    -width {0.44} \
    -followpins \
    -extend_to_core_ring

puts "Metal1 followpin rails established"
puts ""

#===============================================================================
#               TODO : Add Core Power Ring (M3/M4)
#===============================================================================

add_pdn_ring -grid {core_grid} \
    -layer {Metal3 Metal4} \
    -widths "$ring_width $ring_width" \
    -spacings "$ring_spacing $ring_spacing" \
    -core_offsets "$ring_offset $ring_offset"

puts "Core power ring (M3/M4) created"
puts ""

#===============================================================
#               TODO : Add Metal4 Vertical Stripes
#===============================================================

add_pdn_stripe -grid {core_grid} \
    -layer {Metal4} \
    -width $stripe_width \
    -pitch $stripe_pitch \
    -offset $stripe_offset \
    -extend_to_core_ring

puts "Metal4 vertical stripes added"
puts ""

#=============================================================================================
#               TODO : Add Metal5 Horizontal Stripes
# Connect layers in sequence: M1 (cell rails) → M3 (ring) → M4 (vert) → M5 (horiz)
# Creates complete current path from pads through all distribution layers
#=============================================================================================

add_pdn_stripe -grid {core_grid} \
    -layer {Metal5} \
    -width $stripe_width \
    -pitch $stripe_pitch \
    -offset $stripe_offset \
    -extend_to_core_ring

puts "Metal5 horizontal stripes added"
puts ""

#====================================================================================
#               TODO : Via Connections Between Layers
# Connect layers in sequence: M1 (cell rails) → M3 (ring) → M4 (vert) → M5 (horiz)
# Creates complete current path from pads through all distribution layers
#=====================================================================================


add_pdn_connect -grid {core_grid} -layers {Metal1 Metal3}
add_pdn_connect -grid {core_grid} -layers {Metal3 Metal4}
add_pdn_connect -grid {core_grid} -layers {Metal4 Metal5}

puts "Via connections established (M1-M3, M3-M4, M4-M5)"
puts ""

#==================================================================================
#               TODO : Generate PDN Network Structure
# Generates actual stripe geometry, via arrays, and validates connectivity
# Failed vias report: check if any vias couldn't be placed due to DRC
#==================================================================================

puts "========================================="
puts "Generating PDN..."
puts "========================================="
puts ""

pdngen -failed_via_report ${REPORT_DIR}/02_pdn_failed_vias.rpt

puts "PDN generation complete"
puts ""

#===============================================================
#               TODO : Verification & Summary Report
#===============================================================

report_design_area

set power_net_count 0
set ground_net_count 0

foreach net [$block getNets] {
    set sig_type [$net getSigType]
    if {$sig_type == "POWER"} {
        incr power_net_count
    } elseif {$sig_type == "GROUND"} {
        incr ground_net_count
    }
}

puts "========================================="
puts "PDN Summary"
puts "========================================="
puts "Power nets:  $power_net_count"
puts "Ground nets: $ground_net_count"
puts ""
puts "Ring:        Metal3/Metal4 (${ring_width}µm)"
puts "Stripes:     Metal4 + Metal5 (${stripe_width}µm @ ${stripe_pitch}µm)"
puts "========================================="
puts ""

#===============================================================
#               TODO : Save Checkpoint & Reports
#===============================================================

set checkpoint "${RESULT_DIR}/02_pdn.odb"
write_db $checkpoint
puts "Saved checkpoint: $checkpoint"

if {[catch {save_image ${REPORT_DIR}/02_pdn.png} err]} {
    puts "⚠ WARNING: Could not save image"
} else {
    puts "Saved floorplan image: ${REPORT_DIR}/02_pdn.png"
}

puts ""
puts "Next: Run 03_placement.tcl (global placement)"
puts "=============================================================================================="
puts ""
