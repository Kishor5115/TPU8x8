# ============================================================
# 01_floorplan.tcl — 8×8 TPU Hard Macro Floorplan
# ============================================================
#
# SRAM Layout Strategy (SoC Integration Friendly):
#
#   ┌─────────────────────────────────────────────┐
#   │              IO PAD RING (N)                │
#   │  ┌─────────────────────────────────────┐    │
#   │  │  [WEIGHT]         [DATA]            │    │
#   │  │  (1024×64)        (1024×64)         │    │
#   │  │                                     │    │
#   │  │  [OUT_A0] [OUT_A1] [OUT_B0]         │    │
#   │  │  [OUT_B1] [OUT_C0] [OUT_C1]         │    │
#   │  │  (256×64 each)                      │    │
#   │  │                                     │    │
#   │  │       ┌──────────────────┐          │    │
#   │  │       │  SYSTOLIC ARRAY  │          │    │
#   │  │       │  + CONTROL LOGIC │          │    │
#   │  │       │  (Standard Cells)│          │    │
#   │  │       └──────────────────┘          │    │
#   │  │              ↕ SoC Bus Interface     │    │
#   │  └─────────────────────────────────────┘    │
#   │              IO PAD RING (S)                │
#   └─────────────────────────────────────────────┘
#
# - SRAMs placed at TOP → short wires to systolic array
# - Logic at BOTTOM → clean connection to SoC bus
# - IO pads: clk/rst on WEST, signals on EAST
# - Power: distributed VDD/VSS on all 4 sides
# ============================================================

source $SCRIPT_DIR/floorplan_util.tcl

# ============================================================
# Die & Core Area
# ============================================================

set padBond 70.0

set core_lx $CORE_MARGIN
set core_ly $CORE_MARGIN
set core_ux [expr {$DIE_WIDTH - $CORE_MARGIN}]
set core_uy [expr {$DIE_HEIGHT - $CORE_MARGIN}]

initialize_floorplan \
    -die_area "0 0 $DIE_WIDTH $DIE_HEIGHT" \
    -core_area "$core_lx $core_ly $core_ux $core_uy" \
    -site CoreSite

# ============================================================
# IO Sites
# ============================================================

make_io_sites -horizontal_site sg13g2_ioSite \
    -vertical_site sg13g2_ioSite \
    -corner_site sg13g2_ioSite \
    -offset $padBond \
    -rotation_horizontal R0 \
    -rotation_vertical R0 \
    -rotation_corner R0

# ============================================================
# IO Pad Placement
# ============================================================
# Pad names match tpu_chip.sv (post-synthesis)
# Distributed power pads on all 4 sides for SRAM integrity

set mid_x [expr {$DIE_WIDTH / 2.0}]
set mid_y [expr {$DIE_HEIGHT / 2.0}]
set spacing 200.0

# --- WEST: Clock & Reset (critical signals near center) ---
place_pad -row IO_WEST -location [expr {$mid_y - $spacing}] pad_clk
place_pad -row IO_WEST -location [expr {$mid_y + $spacing}] pad_srstn
place_pad -row IO_WEST -location [expr {$mid_y - 2*$spacing}] pad_vdd_core_w
place_pad -row IO_WEST -location [expr {$mid_y + 2*$spacing}] pad_vss_core_w

# --- EAST: Signal pads + power ---
place_pad -row IO_EAST -location [expr {$mid_y - $spacing}] pad_tpu_start
place_pad -row IO_EAST -location [expr {$mid_y + $spacing}] pad_tpu_done
place_pad -row IO_EAST -location [expr {$mid_y - 2*$spacing}] pad_vdd_core_e
place_pad -row IO_EAST -location [expr {$mid_y + 2*$spacing}] pad_vss_core_e

# --- NORTH: Core power (close to SRAMs) ---
place_pad -row IO_NORTH -location [expr {$mid_x - $spacing}] pad_vdd_core_n
place_pad -row IO_NORTH -location [expr {$mid_x + $spacing}] pad_vss_core_n
place_pad -row IO_NORTH -location [expr {$mid_x - 2*$spacing}] pad_vdd_io_n
place_pad -row IO_NORTH -location [expr {$mid_x + 2*$spacing}] pad_vss_io_n

# --- SOUTH: IO power (near SoC interface) ---
place_pad -row IO_SOUTH -location [expr {$mid_x - $spacing}] pad_vdd_core_s
place_pad -row IO_SOUTH -location [expr {$mid_x + $spacing}] pad_vss_core_s
place_pad -row IO_SOUTH -location [expr {$mid_x - 2*$spacing}] pad_vdd_io_s
place_pad -row IO_SOUTH -location [expr {$mid_x + 2*$spacing}] pad_vss_io_s

# Create routing tracks
makeTracks

# Place logical ports at pad locations
puts "Placing top-level ports..."
place_pin -pin_name clk_pad       -layer Metal3 -location [list 0.0 [expr {$mid_y - $spacing}]]
place_pin -pin_name srstn_pad     -layer Metal3 -location [list 0.0 [expr {$mid_y + $spacing}]]
place_pin -pin_name tpu_start_pad -layer Metal3 -location [list $DIE_WIDTH [expr {$mid_y - $spacing}]]
place_pin -pin_name tpu_done_pad  -layer Metal3 -location [list $DIE_WIDTH [expr {$mid_y + $spacing}]]

# Corners
place_corners "sg13g2_Corner"

# IO Fill
set iofill {sg13g2_Filler10000 sg13g2_Filler4000 sg13g2_Filler2000 sg13g2_Filler1000 sg13g2_Filler400 sg13g2_Filler200}
place_io_fill -row IO_NORTH {*}$iofill
place_io_fill -row IO_SOUTH {*}$iofill
place_io_fill -row IO_WEST  {*}$iofill
place_io_fill -row IO_EAST  {*}$iofill

connect_by_abutment

# ============================================================
# SRAM Macro Placement (8 Macros at TOP of Core)
# ============================================================
#
# Instance names from Yosys netlist:
#   tpu_chip instantiates tpu_top as "u_tpu_top"
#   SRAMs are inside tpu_top, so hierarchical path is u_tpu_top/...
#
#   Input:  u_tpu_top/u_sram_weight
#           u_tpu_top/u_sram_data
#   Output: u_tpu_top/\output_a_srams[0].u_sram_out_a
#           u_tpu_top/\output_a_srams[1].u_sram_out_a
#           u_tpu_top/\output_b_srams[0].u_sram_out_b
#           u_tpu_top/\output_b_srams[1].u_sram_out_b
#           u_tpu_top/\output_c_srams[0].u_sram_out_c
#           u_tpu_top/\output_c_srams[1].u_sram_out_c
# ============================================================

# Helper to snap to manufacturing grid
proc snap_to_grid {val grid} {
    return [expr {round($val / $grid) * $grid}]
}

set grid_x 0.48  ;# Metal1 x-pitch (site width)
set grid_y 3.78  ;# Row height

# Get SRAM macro dimensions
set sram_256_dims  [getMacroDimensions "RM_IHPSG13_1P_256x64_c2_bm_bist"]
set sram_256_w     [lindex $sram_256_dims 0]
set sram_256_h     [lindex $sram_256_dims 1]

set sram_64_dims   [getMacroDimensions "RM_IHPSG13_1P_64x64_c2_bm_bist"]
set sram_64_w      [lindex $sram_64_dims 0]
set sram_64_h      [lindex $sram_64_dims 1]

puts ""
puts "SRAM Macro Dimensions:"
puts "  256×64: ${sram_256_w} µm × ${sram_256_h} µm"
puts "  64×64:  ${sram_64_w} µm × ${sram_64_h} µm"

set halo_x $MACRO_HALO_X
set halo_y $MACRO_HALO_Y
set gap    20.0  ;# Gap between macros

# Core area
set core_w [expr {$core_ux - $core_lx}]
set core_h [expr {$core_uy - $core_ly}]

# ============================================================
# Row 1 (TOP): 2× Input SRAMs (256×64) — Weight & Data
# ============================================================
# Place side-by-side, centered horizontally at top of core

set input_block_w [expr {2 * $sram_256_w + $gap}]
set input_start_x [expr {$core_lx + ($core_w - $input_block_w) / 2.0}]
set input_y       [expr {$core_uy - $halo_y - $sram_256_h - 10.0}]

# Weight SRAM (left)
set wx [snap_to_grid $input_start_x $grid_x]
set wy [snap_to_grid $input_y $grid_y]
puts ""
puts "Placing Input SRAMs (Row 1 — Top)..."
placeInstance "u_tpu_top/u_sram_weight" $wx $wy R0

# Data SRAM (right)
set dx [snap_to_grid [expr {$input_start_x + $sram_256_w + $gap}] $grid_x]
placeInstance "u_tpu_top/u_sram_data" $dx $wy R0

# ============================================================
# Rows 2-4: 6× Output SRAMs (64×64) — 3 Banks × 2 each
# ============================================================
#   Row 2: Bank A — output_a[0], output_a[1]
#   Row 3: Bank B — output_b[0], output_b[1]
#   Row 4: Bank C — output_c[0], output_c[1]
#
# Each row has 2 SRAMs centered, matching the input SRAM layout.
# Dynamic lookup by cell type avoids Tcl escaping issues.

# Find all 64×64 SRAM instances dynamically from the DB
puts ""
puts "Discovering output SRAM instances from DB..."
set block [ord::get_db_block]
set output_sram_insts {}

foreach inst [$block getInsts] {
    set master [$inst getMaster]
    set master_name [$master getName]
    if {[string match "RM_IHPSG13_1P_64x64*" $master_name]} {
        set inst_name [$inst getName]
        lappend output_sram_insts $inst_name
        puts "  Found: $inst_name"
    }
}

set num_output_srams [llength $output_sram_insts]
puts "  Total: $num_output_srams (expected 6)"

# Sort for consistent order (A0, A1, B0, B1, C0, C1)
set output_sram_insts [lsort $output_sram_insts]

# Layout: 3 rows of 2, centered horizontally
set out_pair_w [expr {2 * $sram_64_w + $gap}]
set out_start_x [expr {$core_lx + ($core_w - $out_pair_w) / 2.0}]
set row_gap [expr {$halo_y + 10.0}]  ;# vertical gap between rows

puts ""
puts "Placing Output SRAMs (3 rows × 2, below inputs)..."
set current_y [expr {$wy - $halo_y - $sram_64_h - $gap}]

for {set i 0} {$i < $num_output_srams} {incr i} {
    set row [expr {$i / 2}]     ;# 0, 0, 1, 1, 2, 2
    set col [expr {$i % 2}]     ;# 0, 1, 0, 1, 0, 1
    
    set y_pos [expr {$current_y - $row * ($sram_64_h + $row_gap)}]
    set x_pos [expr {$out_start_x + $col * ($sram_64_w + $gap)}]
    
    set ox [snap_to_grid $x_pos $grid_x]
    set oy [snap_to_grid $y_pos $grid_y]
    
    set inst_name [lindex $output_sram_insts $i]
    placeInstance $inst_name $ox $oy R0
}

# ============================================================
# Surgical Per-Instance Placement Blockages (3µm band)
# ============================================================
# Uses odb::dbBlockage_create — the same API as add_macro_blockage
# in floorplan_util.tcl. Creates a 3µm keep-out zone around each
# output SRAM to prevent logic cells from crowding the pins.

set halo_dbu [ord::microns_to_dbu 3.0]
puts ""
puts "Adding 3µm placement blockages around output SRAMs..."

foreach inst_name $output_sram_insts {
    set inst [$block findInst $inst_name]
    if {$inst == "NULL"} { continue }
    set bbox [$inst getBBox]
    set xmin [$bbox xMin]
    set ymin [$bbox yMin]
    set xmax [$bbox xMax]
    set ymax [$bbox yMax]

    # Left band
    odb::dbBlockage_create $block [expr {$xmin - $halo_dbu}] $ymin $xmin $ymax
    # Right band
    odb::dbBlockage_create $block $xmax $ymin [expr {$xmax + $halo_dbu}] $ymax
    # Bottom band
    odb::dbBlockage_create $block [expr {$xmin - $halo_dbu}] [expr {$ymin - $halo_dbu}] [expr {$xmax + $halo_dbu}] $ymin
    # Top band
    odb::dbBlockage_create $block [expr {$xmin - $halo_dbu}] $ymax [expr {$xmax + $halo_dbu}] [expr {$ymax + $halo_dbu}]

    puts "  ✓ $inst_name: 3µm placement blockage"
}

# ============================================================
# Placement Blockage (std cells kept away by MACRO_HALO)
# ============================================================
# The area below the SRAMs is left open for systolic array logic.
puts ""
puts "SRAM placement complete."
puts "  Logic area available below SRAMs for systolic array + control."
puts "  Bottom of core reserved for future SoC bus interface."

# ============================================================
# Utilization Report
# ============================================================

set die_area [expr {$DIE_WIDTH * $DIE_HEIGHT}]
set core_area [expr {$CORE_WIDTH * $CORE_HEIGHT}]

set sram_area [expr {2 * $sram_256_w * $sram_256_h + 6 * $sram_64_w * $sram_64_h}]
set logic_area [expr {$core_area - $sram_area}]

puts ""
puts "========================================="
puts "Floorplan Summary"
puts "========================================="
puts "Die:  ${DIE_WIDTH} µm × ${DIE_HEIGHT} µm ([format %.2f [expr {$die_area / 1e6}]] mm²)"
puts "Core: ${CORE_WIDTH} µm × ${CORE_HEIGHT} µm ([format %.2f [expr {$core_area / 1e6}]] mm²)"
puts ""
puts "SRAM area:  [format %.0f $sram_area] µm² ([format %.3f [expr {$sram_area / 1e6}]] mm²)"
puts "Logic area: [format %.0f $logic_area] µm² ([format %.3f [expr {$logic_area / 1e6}]] mm²)"
puts ""
puts "Macros placed:"
puts "  Row 1: u_sram_weight + u_sram_data (2× 256×64)"
puts "  Row 2: Bank A (2× 64×64)"
puts "  Row 3: Bank B (2× 64×64)"
puts "  Row 4: Bank C (2× 64×64)"
puts "========================================="

# Save checkpoint
set checkpoint "${RESULT_DIR}/01_floorplan.odb"
write_db $checkpoint
puts "Saved: $checkpoint"

save_image ${REPORT_DIR}/01_floorplan.png