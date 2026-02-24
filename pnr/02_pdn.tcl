
# source config.tcl
# source $SCRIPT_DIR/init_tech.tcl 
# read_db ${RESULT_DIR}/01_floorplan.odb

# ============================================================
# 02_pdn.tcl — Power Distribution Network for 8×8 TPU
# ============================================================
#
# PDN Strategy:
#   Metal1  — Standard cell followpin rails (VDD/VSS)
#   Metal3  — Core power ring (horizontal component)
#   Metal4  — Core power ring (vertical) + vertical stripes
#   Metal5  — Horizontal stripes
#
# SRAM macros connect through the core grid stripes.
# 4× VDD/VSS core pads (N/S/E/W) feed the ring.
# ============================================================

puts ""
puts "========================================="
puts "Stage 2: Power Distribution Network"
puts "========================================="

# ------------------------------------------------------------
# Clear dont_touch to allow PDN connections
# ------------------------------------------------------------
set block [ord::get_db_block]
foreach inst [$block getInsts] {
    $inst setDoNotTouch 0
}
puts "Cleared dont_touch on all instances"

# ------------------------------------------------------------
# Global Power Connections
# ------------------------------------------------------------
# Standard cells: VDD / VSS
# SRAMs: VDD / VSS / VDD! / VSS! / VDDARRAY!
# IO pads: iovdd / iovss / vdd / vss

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

# ------------------------------------------------------------
# Voltage Domain
# ------------------------------------------------------------
set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}

# ------------------------------------------------------------
# Core PDN Grid
# ------------------------------------------------------------
define_pdn_grid -name {core_grid} -voltage_domains {CORE}

set ring_width   6.0
set ring_spacing 2.0
set ring_offset  2.0

set stripe_width $PDN_STRIPE_WIDTH   ;# 4.5 µm from config
set stripe_pitch $PDN_STRIPE_PITCH   ;# 40 µm from config
set stripe_offset [expr {$stripe_pitch / 2.0}]

# Metal1 — Standard cell VDD/VSS rails (followpins)
add_pdn_stripe -grid {core_grid} \
    -layer {Metal1} \
    -width {0.44} \
    -followpins \
    -extend_to_core_ring

# Metal3/Metal4 — Core power ring
add_pdn_ring -grid {core_grid} \
    -layer {Metal3 Metal4} \
    -widths "$ring_width $ring_width" \
    -spacings "$ring_spacing $ring_spacing" \
    -core_offsets "$ring_offset $ring_offset"

# Metal4 — Vertical power stripes
add_pdn_stripe -grid {core_grid} \
    -layer {Metal4} \
    -width $stripe_width \
    -pitch $stripe_pitch \
    -offset $stripe_offset \
    -extend_to_core_ring

# Metal5 — Horizontal power stripes
add_pdn_stripe -grid {core_grid} \
    -layer {Metal5} \
    -width $stripe_width \
    -pitch $stripe_pitch \
    -offset $stripe_offset \
    -extend_to_core_ring

# Via connections between layers
add_pdn_connect -grid {core_grid} -layers {Metal1 Metal3}
add_pdn_connect -grid {core_grid} -layers {Metal3 Metal4}
add_pdn_connect -grid {core_grid} -layers {Metal4 Metal5}

puts "PDN grid defined"
puts "  Ring: Metal3/Metal4, ${ring_width}µm wide"
puts "  Stripes: Metal4(V) + Metal5(H), ${stripe_width}µm @ ${stripe_pitch}µm pitch"

# ------------------------------------------------------------
# Generate PDN
# ------------------------------------------------------------
puts ""
puts "Generating PDN..."
pdngen -failed_via_report ${REPORT_DIR}/02_pdn_failed_vias.rpt

# ------------------------------------------------------------
# Verification
# ------------------------------------------------------------
report_design_area

set block [ord::get_db_block]
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

puts ""
puts "PDN Summary:"
puts "  Power nets:  $power_net_count"
puts "  Ground nets: $ground_net_count"
puts "  Ring: Metal3/Metal4 (${ring_width}µm)"
puts "  Stripes: Metal4 + Metal5 (${stripe_width}µm @ ${stripe_pitch}µm)"
puts ""

set checkpoint "${RESULT_DIR}/02_pdn.odb"
write_db $checkpoint
puts "Saved: $checkpoint"

save_image ${REPORT_DIR}/02_pdn.png

