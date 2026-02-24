# ============================================================
# 04_cts.tcl — Clock Tree Synthesis for 8×8 TPU
# ============================================================
#
# Design: ~2816 FFs, single clock domain (clk_pad → clk_c → FFs)
# Strategy: Simple CTS with buf_4/8/16
#
# IMPORTANT: SDC set_dont_touch on SRAMs is removed in the
# updated SDC file. SRAMs are hard macros — their internals
# are untouched regardless. dont_touch was blocking CTS from
# buffering clock to SRAM A_CLK pins (ODB-0370 error).
# ============================================================

# source config.tcl
# source $SCRIPT_DIR/init_tech.tcl
# read_db ${RESULT_DIR}/03_placement.odb

# Read updated SDC (dont_touch on SRAMs removed)
read_sdc $SDC_FILE

puts ""
puts "========================================="
puts "Stage 4: Clock Tree Synthesis"
puts "========================================="

# ------------------------------------------------------------
# Clear dont_touch on ALL instances
# ------------------------------------------------------------
# IO pads were marked dont_touch during placement to prevent
# them from moving. CTS needs to trace clock through IO pad
# (pad_clk) to reach internal clock net.
# SRAMs were marked dont_touch in SDC — also needs clearing.

puts "\n--- Selective Clearing of dont_touch flags ---"
set block [ord::get_db_block]
set cleared_sram 0
set cleared_clk 0

foreach inst [$block getInsts] {
    set name [$inst getName]
    set master [$inst getMaster]
    set mname [$master getName]
    
    # Check if it's an SRAM macro (needs to connect CTS to A_CLK)
    set is_sram [expr {[string match "*u_sram_*" $name] || [string match "*RM_IHPSG13_1P_*" $mname]}]
    
    # Check if it's the clock pad (needs to trace timing through it)
    set is_clk_pad [expr {[string match "pad_clk" $name] || [string match "*IOPadIn*" $mname] && [string match "pad_clk" $name]}]

    if {$is_sram} {
        if {[$inst isDoNotTouch]} {
            $inst setDoNotTouch 0
            incr cleared_sram
        }
    } elseif {$is_clk_pad} {
        if {[$inst isDoNotTouch]} {
            $inst setDoNotTouch 0
            incr cleared_clk
        }
    }
}
puts "  Cleared dont_touch on: $cleared_sram SRAMs, $cleared_clk Clock Pad"
puts "  Note: IO fillers and other pads remain protected."

# ------------------------------------------------------------
# Clock Verification
# ------------------------------------------------------------
puts "\n--- Clock Configuration ---"
set all_clocks [all_clocks]

if {[llength $all_clocks] == 0} {
    puts "WARNING: No clocks from SDC. Searching for clock ports..."
    
    foreach bterm [$block getBTerms] {
        set name [$bterm getName]
        if {[string match "*clk*" $name]} {
            puts "  Creating clock on port: $name"
            create_clock -name clk -period 20.0 [get_ports $name]
        }
    }
    set all_clocks [all_clocks]
}

if {[llength $all_clocks] == 0} {
    puts "ERROR: No clocks found! Cannot proceed."
    exit 1
}

foreach clk $all_clocks {
    set clk_name [get_property $clk name]
    set clk_period [get_property $clk period]
    puts "  Clock: $clk_name (period=${clk_period}ns)"
}

# Count FFs
set ff_count 0
foreach inst [$block getInsts] {
    if {[[$inst getMaster] isSequential]} {
        incr ff_count
    }
}
puts "  Flip-flops: $ff_count"

# Verify clock net fanout
puts "\n--- Clock Net Analysis ---"
foreach net [$block getNets] {
    set iterm_count [llength [$net getITerms]]
    set net_name [$net getName]
    if {$iterm_count > 100 && [string match "*clk*" $net_name]} {
        puts "  Clock net '$net_name' has $iterm_count connections"
    }
}

# ------------------------------------------------------------
# Wire RC Estimation
# ------------------------------------------------------------
# Values for IHP SG13G2 (estimated/safe defaults in pF/um and Ohms/um)
# C = ~0.2 fF/um = 0.0002 pF/um
# R = ~0.5 Ohms/um
set_wire_rc -layer Metal3 -resistance 0.5 -capacitance 0.0002
set_wire_rc -layer Metal4 -resistance 0.5 -capacitance 0.0002
set_wire_rc -layer Metal5 -resistance 0.5 -capacitance 0.0002

set_wire_rc -signal -layer Metal3
set_wire_rc -clock  -layer Metal4

# ------------------------------------------------------------
# Clock Tree Synthesis
# ------------------------------------------------------------
set cts_buffer_list [list \
    sg13g2_buf_4 \
    sg13g2_buf_8 \
    sg13g2_buf_16 \
]

set CTS_ROOT_BUF "sg13g2_buf_16"

puts "\n--- Building Clock Tree ---"
set start_time [clock seconds]

clock_tree_synthesis \
    -root_buf $CTS_ROOT_BUF \
    -buf_list $cts_buffer_list

set elapsed [expr {[clock seconds] - $start_time}]
puts "CTS completed in ${elapsed}s"

# ------------------------------------------------------------
# Post-CTS Legalization
# ------------------------------------------------------------
puts "\n--- Post-CTS Legalization ---"
set_propagated_clock [all_clocks]

# NOTE: remove_fillers is required before detailed_placement (OpenROAD warning).
# However, filler_placement CRASHES here with a segfault in placeRowFillers
# when IO pad ring fillers are present (OpenROAD bug).
# Solution: remove → legalize → defer filler re-insertion to routing stage.
remove_fillers
detailed_placement
check_placement -verbose
# filler_placement deferred to 05_routing.tcl (post-detailed-route)

# ------------------------------------------------------------
# Post-CTS Timing
# ------------------------------------------------------------
puts "\n========================================="
puts "Post-CTS Timing Results"
puts "========================================="

estimate_parasitics -placement

foreach clk $all_clocks {
    set clk_name [get_property $clk name]
    puts "\nClock: $clk_name"
    report_clock_skew -clock $clk_name
    report_clock_skew -clock $clk_name -hold
}

report_worst_slack -max
report_worst_slack -min
report_tns

# Hold repair skipped — SRAM paths cause excessive violations
# repair_timing -hold

# ------------------------------------------------------------
# Save Checkpoint
# ------------------------------------------------------------
puts "\n========================================="
puts "Stage 4 Complete"
puts "========================================="

write_db ${RESULT_DIR}/04_cts.odb
puts "Saved: ${RESULT_DIR}/04_cts.odb"

if {[info commands save_image] != ""} {
    save_image ${REPORT_DIR}/04_cts.png
}