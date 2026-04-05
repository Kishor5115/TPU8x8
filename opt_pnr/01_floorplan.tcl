
# ============================================================
#?       01_floorplan.tcl — 8×8 TPU Hard Macro Floorplan
# ============================================================
#
# SRAM Layout Strategy (SoC Integration Friendly):
#
#   ┌─────────────────────────────────────────────┐
#   │              IO PAD RING (N)                │
#   │  ┌─────────────────────────────────────┐    │
#   │  │  [WEIGHT]         [DATA]            │    │
#   │  │  (256x64)        (256x64)           │    │
#   │  │                                     │    │
#   │  │  [OUT_A0] [OUT_A1] [OUT_B0]         │    │
#   │  │  [OUT_B1] [OUT_C0] [OUT_C1]         │    │
#   │  │  (64x64 each)                       │    │
#   │  │                                     │    │
#   │  │       ┌──────────────────┐          │    │
#   │  │       │  SYSTOLIC ARRAY  │          │    │
#   │  │       │  + CONTROL LOGIC │          │    │
#   │  │       │  (Standard Cells)│          │    │
#   │  │       └──────────────────┘          │    │
#   │  │             ↕ SoC Bus Interface     │    │
#   │  └─────────────────────────────────────┘    │
#   │              IO PAD RING (S)                │
#   └─────────────────────────────────────────────┘
#
# - SRAMs placed at TOP → short wires to systolic array
# - Logic at BOTTOM → clean connection to SoC bus
# - IO pads: clk/rst on WEST, signals on EAST
# - Power: distributed VDD/VSS on all 4 sides
# ============================================================

puts "========================================="
puts "Stage 1: Floorplan & IO Setup"
puts "========================================="
puts ""

source $SCRIPT_DIR/floorplan_util.tcl

# ---------------------------------------------------------------------------------------------------

# ============================================================
#        TODO  :     Die & Core Area
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

puts "Die & Core floorplan initialized"
puts "  Die:  ${DIE_WIDTH} µm x ${DIE_HEIGHT} µm"
puts "  Core: [expr {$core_ux - $core_lx}] µm × [expr {$core_uy - $core_ly}] µm"
puts ""

# ---------------------------------------------------------------------------------------------------

# ============================================================
#          TODO :     IO Sites
# ============================================================

make_io_sites -horizontal_site sg13g2_ioSite \
    -vertical_site sg13g2_ioSite \
    -corner_site sg13g2_ioSite \
    -offset $padBond \
    -rotation_horizontal R0 \
    -rotation_vertical R0 \
    -rotation_corner R0

puts "IO sites configured"
puts ""

# ---------------------------------------------------------------------------------------------------

# ============================================================
#       TODO  :   IO Pad Placement
# ============================================================
# Pad names match tpu_chip.sv (post-synthesis)
# Distributed power pads on all 4 sides for SRAM integrity

puts "Placing IO pads..."

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

# NOTE: place_pin REMOVED — IO pad cells already provide physical pins
# for top-level bterms. Adding place_pin creates duplicate pins,
# causing DRT-0302 ("Unsupported multiple pins on bterm") during routing.


# Corners (uses OpenROAD built-in — correct orientations automatically)
set iocorner sg13g2_Corner
place_corners $iocorner

# IO Fill
set iofill {sg13g2_Filler10000 sg13g2_Filler4000 sg13g2_Filler2000 sg13g2_Filler1000 sg13g2_Filler400 sg13g2_Filler200}
place_io_fill -row IO_NORTH {*}$iofill
place_io_fill -row IO_SOUTH {*}$iofill
place_io_fill -row IO_WEST  {*}$iofill
place_io_fill -row IO_EAST  {*}$iofill


# Connect power rings by abutment
connect_by_abutment

# Place bondpads on top of IO cells (for wire bonding)
place_bondpad -bond bondpad_70x70 -offset {5.0 -70.0} pad_*

# Remove temporary IO site rows (no longer needed)
remove_io_rows

puts "IO pads placed and connected"
puts ""

# ---------------------------------------------------------------------------------------------------

# ============================================================
#        TODO :  SRAM Macro Placement Strategy
# ============================================================
# 
# Instance names from Yosys netlist:
#   tpu_chip instantiates tpu_top as "u_tpu_top"
#   SRAMs are inside tpu_top, so hierarchical paths:
#
#   Input SRAMs (256×64):
#     - u_tpu_top/u_sram_weight
#     - u_tpu_top/u_sram_data
#
#   Output SRAMs (64×64):
#     - u_tpu_top/\output_a_srams[0].u_sram_out_a
#     - u_tpu_top/\output_a_srams[1].u_sram_out_a
#     - u_tpu_top/\output_b_srams[0].u_sram_out_b
#     - u_tpu_top/\output_b_srams[1].u_sram_out_b
#     - u_tpu_top/\output_c_srams[0].u_sram_out_c
#     - u_tpu_top/\output_c_srams[1].u_sram_out_c
#
# Layout:
#   Row 1 (TOP):    Weight + Data SRAMs (256×64)
#   Rows 2-4:       Bank A, B, C (2× 64×64 each)
#   Remaining Core: Systolic array logic
# ============================================================ 

puts "========================================="
puts "Stage 2: SRAM Macro Placement"
puts "========================================="
puts ""

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

puts "SRAM Macro Dimensions:"
puts "  256x64: ${sram_256_w} µm x ${sram_256_h} µm"
puts "  64x64:  ${sram_64_w} µm x ${sram_64_h} µm"
puts ""

set halo_x $MACRO_HALO_X
set halo_y $MACRO_HALO_Y
set gap    20.0  ;# Gap between adjacent macros

# Core area dimensions
set core_w [expr {$core_ux - $core_lx}]
set core_h [expr {$core_uy - $core_ly}]

# ============================================================
#        Row 1 (TOP): Input SRAMs — Weight & Data Macros
# ============================================================
# Dimensions: 2× RM_IHPSG13_1P_256x64
# Layout: Side-by-side, centered horizontally at top of core
#
# ┌────────────┬────────────┐
# │   Weight   │    Data    │
# │ (256×64)   │ (256×64)   │
# └────────────┴────────────┘

set input_block_w [expr {2 * $sram_256_w + $gap}]
set input_start_x [expr {$core_lx + ($core_w - $input_block_w) / 2.0}]
set input_y       [expr {$core_uy - $halo_y - $sram_256_h - 10.0}]

# Weight SRAM (left)
set wx [snap_to_grid $input_start_x $grid_x]
set wy [snap_to_grid $input_y $grid_y]

puts "Row 1: Input SRAMs"
placeInstance "u_tpu_top/u_sram_weight" $wx $wy R0
puts "  ✓ u_tpu_top/u_sram_weight @ ($wx, $wy)"

# Data SRAM (right)
set dx [snap_to_grid [expr {$input_start_x + $sram_256_w + $gap}] $grid_x]
placeInstance "u_tpu_top/u_sram_data" $dx $wy R0
puts "  ✓ u_tpu_top/u_sram_data @ ($dx, $wy)"
puts ""

# ============================================================
#        Rows 2-4: Output SRAMs — Bank A, B, C
# ============================================================
# Dimensions: 6× RM_IHPSG13_1P_64x64 (2 per bank)
# Layout:
#   Row 2: Bank A — [A0] [A1]
#   Row 3: Bank B — [B0] [B1]
#   Row 4: Bank C — [C0] [C1]
#
# Each row is centered horizontally, matching input SRAM alignment.
# Dynamic lookup from database avoids Tcl escaping issues.

puts "Rows 2-4: Output SRAMs"
puts "Discovering instances from design database..."

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
puts "  Total: $num_output_srams instances (expected 6)"
puts ""

if {$num_output_srams != 6} {
    puts " WARNING: Expected 6 output SRAMs, found $num_output_srams"
}

# Sort for consistent order (A0, A1, B0, B1, C0, C1)
set output_sram_insts [lsort $output_sram_insts]

# Layout: 3 rows of 2, centered horizontally
set out_pair_w [expr {2 * $sram_64_w + $gap}]
set out_start_x [expr {$core_lx + ($core_w - $out_pair_w) / 2.0}]
set row_gap [expr {$halo_y + 10.0}]  ;# vertical gap between rows

puts "Placing output SRAMs (3 rows × 2)..."
set current_y [expr {$wy - $halo_y - $sram_64_h - $gap}]

for {set i 0} {$i < $num_output_srams} {incr i} {
    set row [expr {$i / 2}]     ;# 0, 0, 1, 1, 2, 2 (Bank A, B, C)
    set col [expr {$i % 2}]     ;# 0, 1, 0, 1, 0, 1 (Instance 0, 1 per bank)
    
    set y_pos [expr {$current_y - $row * ($sram_64_h + $row_gap)}]
    set x_pos [expr {$out_start_x + $col * ($sram_64_w + $gap)}]
    
    set ox [snap_to_grid $x_pos $grid_x]
    set oy [snap_to_grid $y_pos $grid_y]
    
    set inst_name [lindex $output_sram_insts $i]
    placeInstance $inst_name $ox $oy R0
    puts "  ✓ $inst_name @ ($ox, $oy)"
}

puts ""

# ---------------------------------------------------------------------------------------------------

# ============================================================
#        TODO  :  Placement Blockages (3µm Halo)
# ============================================================
# Surgical per-instance blockages prevent standard cells from
# crowding SRAM macro pins. Uses odb::dbBlockage_create API.

puts "Adding placement blockages..."
set halo_dbu [ord::microns_to_dbu 3.0]

foreach inst_name $output_sram_insts {
    set inst [$block findInst $inst_name]
    if {$inst == "NULL"} { continue }
    
    set bbox [$inst getBBox]
    set xmin [$bbox xMin]
    set ymin [$bbox yMin]
    set xmax [$bbox xMax]
    set ymax [$bbox yMax]

    # Create 4 blockage bands: left, right, bottom, top
    # Left band
    odb::dbBlockage_create $block [expr {$xmin - $halo_dbu}] $ymin $xmin $ymax
    # Right band
    odb::dbBlockage_create $block $xmax $ymin [expr {$xmax + $halo_dbu}] $ymax
    # Bottom band
    odb::dbBlockage_create $block [expr {$xmin - $halo_dbu}] [expr {$ymin - $halo_dbu}] [expr {$xmax + $halo_dbu}] $ymin
    # Top band
    odb::dbBlockage_create $block [expr {$xmin - $halo_dbu}] $ymax [expr {$xmax + $halo_dbu}] [expr {$ymax + $halo_dbu}]

    puts "  ✓ $inst_name: 3µm blockage"
}

puts ""

# ---------------------------------------------------------------------------------------------------

# ============================================================
#        TODO  : Area & Utilization Summary
# ============================================================

set die_area [expr {$DIE_WIDTH * $DIE_HEIGHT}]
set core_area [expr {$CORE_WIDTH * $CORE_HEIGHT}]

set sram_area [expr {2 * $sram_256_w * $sram_256_h + 6 * $sram_64_w * $sram_64_h}]
set logic_area [expr {$core_area - $sram_area}]

puts "========================================="
puts "Stage 2 Complete: Floorplan Summary"
puts "========================================="
puts "Die Dimensions:"
puts "  Size: ${DIE_WIDTH} µm × ${DIE_HEIGHT} µm"
puts "  Area: [format %.2f [expr {$die_area / 1e6}]] mm²"
puts ""
puts "Core Dimensions:"
puts "  Size: ${CORE_WIDTH} µm × ${CORE_HEIGHT} µm"
puts "  Area: [format %.2f [expr {$core_area / 1e6}]] mm²"
puts ""
puts "Memory Distribution:"
puts "  SRAM area:  [format %.0f $sram_area] µm²      ([format %.3f [expr {$sram_area / 1e6}]] mm²)"
puts "  Logic area: [format %.0f $logic_area] µm²   ([format %.3f [expr {$logic_area / 1e6}]] mm²)"
puts ""
puts "SRAM Macros Placed:"
puts "  Row 1: u_sram_weight + u_sram_data     (2× 256×64)"
puts "  Row 2: Bank A (output_a\[0\], output_a\[1\])  (2× 64×64)"
puts "  Row 3: Bank B (output_b\[0\], output_b\[1\])  (2× 64×64)"
puts "  Row 4: Bank C (output_c\[0\], output_c\[1\])  (2× 64×64)"
puts ""
puts "Layout Structure:"
puts "  - SRAMs placed at TOP of core (short interconnect)"
puts "  - Systolic array logic: center/bottom area"
puts "  - SoC bus interface: SOUTH edge"
puts "  - 3µm placement blockage around each SRAM"
puts "========================================="
puts ""

# ---------------------------------------------------------------------------------------------------
# ---------------------------------------------------------------------------------------------------

# ============================================================
#        TODO  : Save Checkpoint & Reports
# ============================================================

set checkpoint "${RESULT_DIR}/01_floorplan.odb"
write_db $checkpoint
puts "Saved checkpoint: $checkpoint"

if {[catch {save_image ${REPORT_DIR}/01_floorplan.png} err]} {
    puts " WARNING: Could not save floorplan image: $err"
} else {
    puts "Saved floorplan image: ${REPORT_DIR}/01_floorplan.png"
}

puts ""
puts "Next: Run 02_pdn.tcl (power delivery network)"
puts "=============================================================================================="
puts ""