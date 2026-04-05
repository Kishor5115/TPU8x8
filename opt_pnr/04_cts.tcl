
# ============================================================
#?  04_cts.tcl — Clock Tree Synthesis for 8×8 TPU
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

# Read updated SDC (dont_touch on SRAMs removed)
read_sdc $SDC_FILE

puts ""
puts "========================================="
puts "Stage 4: Clock Tree Synthesis"
puts "========================================="
puts ""

#===============================================================
#               TODO : Clear dont_touch on Instances
# IO pads were marked dont_touch during placement to prevent
# them from moving. CTS needs to trace clock through IO pad
# (pad_clk) to reach internal clock net.
# SRAMs were marked dont_touch in SDC — also needs clearing.
#===============================================================

puts "Selective clearing of dont_touch flags..."
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
puts ""

#===============================================================
#               TODO : Clock Verification
#===============================================================

puts "Clock Configuration:"
set all_clocks [all_clocks]

if {[llength $all_clocks] == 0} {
    puts "WARNING: No clocks from SDC. Searching for clock ports..."
    
    foreach bterm [$block getBTerms] {
        set name [$bterm getName]
        if {[string match "*clk*" $name]} {
            puts "  Creating clock on port: $name"
            create_clock -name clk -period $CLK_PERIOD [get_ports $name]
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
puts ""

#===============================================================
#               TODO : Clock Net Analysis
#===============================================================

puts "Clock Net Analysis:"
foreach net [$block getNets] {
    set iterm_count [llength [$net getITerms]]
    set net_name [$net getName]
    if {$iterm_count > 100 && [string match "*clk*" $net_name]} {
        puts "  Clock net '$net_name' has $iterm_count connections"
    }
}
puts ""

#===============================================================
#               TODO : Wire RC Estimation
# Values for IHP SG13G2 (estimated/safe defaults)
# C = ~0.2 fF/um = 0.0002 pF/um
# R = ~0.5 Ohms/um
#===============================================================

set_wire_rc -layer Metal3 -resistance 0.5 -capacitance 0.0002
set_wire_rc -layer Metal4 -resistance 0.5 -capacitance 0.0002
set_wire_rc -layer Metal5 -resistance 0.5 -capacitance 0.0002

set_wire_rc -signal -layer Metal3
set_wire_rc -clock  -layer Metal4

puts "Wire RC estimation complete"
puts ""

#===============================================================
#               TODO : Clock Tree Synthesis
#===============================================================

set cts_buffer_list [list sg13g2_buf_4 sg13g2_buf_8 sg13g2_buf_16]
if {[info exists CTS_BUF_CELLS] && [llength $CTS_BUF_CELLS] > 0} {
    set cts_buffer_list $CTS_BUF_CELLS
}

set cts_root_buf "sg13g2_buf_16"
if {[info exists CTS_ROOT_BUF] && $CTS_ROOT_BUF ne ""} {
    set cts_root_buf $CTS_ROOT_BUF
}

set cts_cluster_size 8
if {[info exists CTS_MAX_FANOUT] && $CTS_MAX_FANOUT > 0 && $CTS_MAX_FANOUT < 8} {
    set cts_cluster_size $CTS_MAX_FANOUT
}

puts "Building Clock Tree..."
puts "  Root buffer: $cts_root_buf"
puts "  Buffer list: $cts_buffer_list"
puts "  Sink cluster size: $cts_cluster_size"

set start_time [clock seconds]

# Override max_fanout constraint for clock buffers to prevent false DRV violations
# (Standard cell limit is 8, but 16 or 32 is acceptable for clock trees)
set_max_fanout 16 [current_design]

clock_tree_synthesis \
    -root_buf $cts_root_buf \
    -buf_list $cts_buffer_list \
    -sink_clustering_enable \
    -sink_clustering_size $cts_cluster_size

set elapsed [expr {[clock seconds] - $start_time}]
puts "  CTS completed in ${elapsed}s"
puts ""

#===============================================================
#               TODO : Post-CTS Legalization
# remove_fillers required before detailed_placement (OpenROAD warning).
# filler_placement deferred to 05_routing.tcl (segfault workaround).
#===============================================================

puts "Post-CTS Legalization..."
set_propagated_clock [all_clocks]

# remove → legalize → defer filler re-insertion to routing stage
puts "  Manually removing all filler and decap cells..."
set del_count 0
foreach inst [$block getInsts] {
    set mname [[$inst getMaster] getName]
    if {[string match "sg13g2_fill_*" $mname] || [string match "sg13g2_decap_*" $mname]} {
        odb::dbInst_destroy $inst
        incr del_count
    }
}
puts "  Deleted $del_count cells (fillers + decaps)"

detailed_placement
check_placement -verbose

puts "  Legalization complete (fillers deferred to routing)"
puts ""

#===============================================================
#               TODO : Post-CTS Timing Analysis
#===============================================================

puts "========================================="
puts "Post-CTS Timing Results"
puts "========================================="
puts ""

estimate_parasitics -placement

foreach clk $all_clocks {
    set clk_name [get_property $clk name]
    puts "Clock: $clk_name"
    report_clock_skew -clock $clk_name
    report_clock_skew -clock $clk_name -hold
}

report_worst_slack -max
report_worst_slack -min
report_tns

# Hold repair
# repair_timing -hold -max_buffer_percent 70

puts ""

#===============================================================
#               TODO : Save Checkpoint
#===============================================================

puts "========================================="
puts "Stage 4 Complete"
puts "========================================="

write_db ${RESULT_DIR}/04_cts.odb
puts "Saved checkpoint: ${RESULT_DIR}/04_cts.odb"

if {[catch {save_image ${REPORT_DIR}/04_cts.png} err]} {
    puts "⚠ WARNING: Could not save image"
} else {
    puts "Saved image: ${REPORT_DIR}/04_cts.png"
}

puts ""
puts "Next: Run 05_routing.tcl (global + detailed routing)"
puts "=============================================================================================="
puts ""