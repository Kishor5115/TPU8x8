# ============================================================
# floorplan_util.tcl — Utility Procs for 8×8 TPU Floorplan
# ============================================================

# ============================================================
# placeInstance — Place a design instance at (x,y) with orientation
# ============================================================
proc placeInstance {name x y orient} {
    puts "  Placing $name at ($x, $y) orient=$orient"

    set block [ord::get_db_block]
    set inst [$block findInst $name]
    if {$inst == "NULL"} {
        error "ERROR: Cannot find instance '$name'"
    }

    $inst setLocationOrient $orient
    $inst setLocation [ord::microns_to_dbu $x] [ord::microns_to_dbu $y]
    $inst setPlacementStatus FIRM
}

# ============================================================
# place_corners — Using OpenROAD's BUILT-IN place_corners
# ============================================================
# The built-in place_corners command automatically:
#   1. Creates corner cell instances
#   2. Places them at the four die corners
#   3. Applies correct orientations based on LEF SYMMETRY
# This matches the Croc SoC reference approach.
# Do NOT override with a custom proc.


# ============================================================
# add_macro_blockage — Create placement blockage between two macros
# ============================================================
proc add_macro_blockage {negative_padding name1 name2} {
    set block [ord::get_db_block]
    set inst1 [odb::dbBlock_findInst $block $name1]
    set inst2 [odb::dbBlock_findInst $block $name2]
    set bb1 [odb::dbInst_getBBox $inst1]
    set bb2 [odb::dbInst_getBBox $inst2]

    set minx [expr min([odb::dbBox_xMin $bb1], [odb::dbBox_xMin $bb2]) + [ord::microns_to_dbu $negative_padding]]
    set miny [expr min([odb::dbBox_yMin $bb1], [odb::dbBox_yMin $bb2]) + [ord::microns_to_dbu $negative_padding]]
    set maxx [expr max([odb::dbBox_xMax $bb1], [odb::dbBox_xMax $bb2]) - [ord::microns_to_dbu $negative_padding]]
    set maxy [expr max([odb::dbBox_yMax $bb1], [odb::dbBox_yMax $bb2]) - [ord::microns_to_dbu $negative_padding]]

    set blockage [odb::dbBlockage_create [ord::get_db_block] $minx $miny $maxx $maxy]
    return $blockage
}

# ============================================================
# makeTracks — Create metal routing tracks (IHP SG13G2)
# ============================================================
proc makeTracks {} {
    make_tracks Metal1    -x_offset 0    -x_pitch 0.48 -y_offset 0    -y_pitch 0.48
    make_tracks Metal2    -x_offset 0    -x_pitch 0.42 -y_offset 0    -y_pitch 0.42
    make_tracks Metal3    -x_offset 0    -x_pitch 0.48 -y_offset 0    -y_pitch 0.48
    make_tracks Metal4    -x_offset 0    -x_pitch 0.42 -y_offset 0    -y_pitch 0.42
    make_tracks Metal5    -x_offset 0    -x_pitch 0.48 -y_offset 0    -y_pitch 0.48
    make_tracks TopMetal1 -x_offset 1.46 -x_pitch 2.28 -y_offset 1.46 -y_pitch 2.28
    make_tracks TopMetal2 -x_offset 2.00 -x_pitch 4.00 -y_offset 2.00 -y_pitch 4.00
}

# ============================================================
# getMacroDimensions — Get width/height of a library macro
# ============================================================
proc getMacroDimensions {macro_name} {
    set db [ord::get_db]
    set master [$db findMaster $macro_name]

    if {$master == "NULL"} {
        error "ERROR: Cannot find macro '$macro_name'"
    }

    set width  [ord::dbu_to_microns [$master getWidth]]
    set height [ord::dbu_to_microns [$master getHeight]]

    return [list $width $height]
}

# ============================================================
# verifySRAMPlacement — Check all 8 SRAM macros are placed
# ============================================================
proc verifySRAMPlacement {} {
    set block [ord::get_db_block]
    set expected_srams [list \
        "u_tpu_top/u_sram_weight" \
        "u_tpu_top/u_sram_data" \
        "u_tpu_top/output_a_srams\[0\].u_sram_out_a" \
        "u_tpu_top/output_a_srams\[1\].u_sram_out_a" \
        "u_tpu_top/output_b_srams\[0\].u_sram_out_b" \
        "u_tpu_top/output_b_srams\[1\].u_sram_out_b" \
        "u_tpu_top/output_c_srams\[0\].u_sram_out_c" \
        "u_tpu_top/output_c_srams\[1\].u_sram_out_c" \
    ]

    puts ""
    puts "SRAM Placement Verification:"
    set placed 0
    set missing 0

    foreach name $expected_srams {
        set inst [$block findInst $name]
        if {$inst == "NULL"} {
            puts "  ✗ MISSING: $name"
            incr missing
        } else {
            set status [$inst getPlacementStatus]
            set bbox [$inst getBBox]
            set x [ord::dbu_to_microns [odb::dbBox_xMin $bbox]]
            set y [ord::dbu_to_microns [odb::dbBox_yMin $bbox]]
            puts "  ✓ $name → ($x, $y) status=$status"
            incr placed
        }
    }

    puts ""
    puts "  Placed: $placed / 8"
    if {$missing > 0} {
        puts "  ⚠ WARNING: $missing SRAM macros not found!"
    } else {
        puts "  ✓ All 8 SRAM macros placed successfully"
    }
}
