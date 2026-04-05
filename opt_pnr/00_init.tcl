
source config.tcl

source $SCRIPT_DIR/init_tech.tcl

puts "========================================="
puts "Stage 0: Loading Design Netlist"
puts "========================================="
puts ""

#=============================================================
#               TODO :    READ Synthesized Netlist
#=============================================================

puts "Reading Verilog netlist..."
puts "  File: $VERILOG_FILE"

if {![file exists $VERILOG_FILE]} {
    puts "ERROR: Netlist file not found!"
    puts "  Expected: $VERILOG_FILE"
    puts "  Run Yosys synthesis first"
    exit 1
}

read_verilog $VERILOG_FILE
puts "  Size: [format %.2f $netlist_size_mb] MB"
puts ""

#===============================================================
#                TODO :   Link DESIGN
#================================================================

puts "Linking design: $DESIGN"
link_design $DESIGN

puts "  Design linked successfully"
puts ""


#===============================================================
#               TODO : Apply Dont use constraits
#================================================================

if {[info exists DONT_USE] && [llength $DONT_USE] > 0} {
    puts "Applying dont_use constraints..."
    foreach pattern $DONT_USE {
        set_dont_use $pattern
        puts "  - $pattern"
    }
    puts ""
}


#===============================================================
#               TODO :  Read SDC Timing Constraints
#================================================================

puts "Reading SDC constraints..."
puts "  File: $SDC_FILE"

if {![file exists $SDC_FILE]} {
    puts "WARNING: SDC file not found!"
    puts "  Expected: $SDC_FILE"
    puts "  Creating default clock constraint..."
    
    # Create default clock if SDC missing
    create_clock -name $CLK_PORT -period $CLK_PERIOD [get_ports $CLK_PORT]
    set_clock_uncertainty $CLK_UNCERTAINTY [get_clocks $CLK_PORT]
    
    puts "  Created clock: $CLK_PORT @ ${CLK_FREQ_MHZ} MHz"
} else {
    read_sdc $SDC_FILE
    puts "  SDC loaded successfully"
}

puts ""


#===============================================================
#               TODO :  Design Statistics
#================================================================

set all_insts [get_cells -hierarchical * -quiet]
set inst_count [llength $all_insts]

# Count SRAM macro instances (critical for 8×8 TPU)
# Filter by master name (ref_name) instead of instance name pattern
set sram_insts [get_cells -hierarchical * -filter {ref_name =~ RM_IHPSG13_1P_*} -quiet]
set sram_count [llength $sram_insts]

set sram_64x64 [get_cells -hierarchical * -filter {ref_name =~ RM_IHPSG13_1P_64x64*} -quiet]
set sram_256x64 [get_cells -hierarchical * -filter {ref_name =~ RM_IHPSG13_1P_256x64*} -quiet]

set all_nets [get_nets -hierarchical * -quiet]
set net_count [llength $all_nets]

set all_ports [get_ports * -quiet]
set port_count [llength $all_ports]

puts "  Instances (total): $inst_count"
puts "  SRAM macros: $sram_count"
if {$sram_count > 0} {
    puts "    - 256x64 (input): [llength $sram_256x64]"
    puts "    - 64x64 (output): [llength $sram_64x64]"
}
puts "  Nets: $net_count"
puts "  Ports: $port_count"
puts ""


#===============================================================================
#               TODO :  SRAM Macro Verification (Critical for 8×8 TPU)
#==============================================================================

if {$sram_count > 0} {
    puts "✓ Found $sram_count SRAM macros"
    puts ""
    puts "Expected for 8x8 TPU:"
    puts "  - Input SRAMs: 2x RM_IHPSG13_1P_256x64 (Weight + Data)"
    puts "  - Output SRAMs (A): 2x RM_IHPSG13_1P_64x64"
    puts "  - Output SRAMs (B): 2x RM_IHPSG13_1P_64x64"
    puts "  - Output SRAMs (C): 2x RM_IHPSG13_1P_64x64"
    puts "  - Total: 8 macros"
    puts ""

    if {[llength $sram_256x64] == 2} {
        puts " Input SRAMs: Found exactly 2 (correct)"
    } else {
        puts " Input SRAMs: Found [llength $sram_256x64] (expected 2)"
    }
    
    if {[llength $sram_64x64] == 6} {
        puts "✓ Output SRAMs: Found exactly 6 (correct)"
    } else {
        puts " Output SRAMs: Found [llength $sram_64x64] (expected 6)"
    }

} else {
    puts "⚠ ERROR: No SRAM macros found in design!"
    puts ""
    puts "This is CRITICAL for 8x8 TPU:"
    puts "  Design needs 8 SRAM macros to function"
    puts "  Missing macros will cause synthesis/place&route failures"
    puts ""
    puts "Troubleshooting:"
    puts "  1. Check if Yosys synthesized SRAM instances"
    puts "  2. Verify PDK SRAM libraries are installed"
    puts "  3. Check init_tech.tcl for SRAM library loading errors"
}
puts ""

#===============================================================
#               TODO :   Timing Check
#================================================================

puts "========================================="
puts "Initial Timing Analysis"
puts "========================================="

# Report units for clarity
puts "Units:"
report_units
puts ""

# Check for timing issues
puts "Setup/Hold Timing (pre-placement):"
report_checks -path_delay min_max -format summary
puts ""
    
# Check for constraint issues
puts "Constraint Check:"
check_setup -verbose
puts ""

#===============================================================
#               TODO :   Design Hierarchy Summary
#================================================================

puts "========================================="
puts "Design Hierarchy"
puts "========================================="

# Report top-level ports
puts "Top-level ports:"
set input_ports [get_ports -filter {direction == input} -quiet]
set output_ports [get_ports -filter {direction == output} -quiet]
set inout_ports [get_ports -filter {direction == inout} -quiet]

puts "  Inputs: [llength $input_ports]"
puts "  Outputs: [llength $output_ports]"
puts "  Bidirectional: [llength $inout_ports]"
puts ""

# Clock port check
set clk_port [get_ports $CLK_PORT -quiet]
if {$clk_port eq ""} {
    puts "WARNING: Clock port '$CLK_PORT' not found!"
} else {
    puts "Clock: $CLK_PORT found"
}

puts ""


#===============================================================
#               TODO :   Summary
#================================================================

puts "========================================="
puts "Stage 0 Complete"
puts "========================================="
puts "Design: $DESIGN (8x8 TPU - 64 MACs)"
puts "  Instances: $inst_count"
if {$sram_count > 0} {
    puts "  SRAM macros: $sram_count (2 input + 6 output expected)"
    puts "     256x64: [llength $sram_256x64] instances"
    puts "     64x64: [llength $sram_64x64] instances"
} else {
    puts "   WARNING: No SRAM macros found!"
    puts "    Expected: 8 SRAM macros for 8x8 TPU"
}
puts "  Nets: $net_count"
puts "  Clock: ${CLK_FREQ_MHZ} MHz (${CLK_PERIOD} ns period)"
puts ""
puts "Next: Run 01_floorplan.tcl"
puts "=============================================================================================="
puts ""

#===============================================================
#               TODO :   Save Checkpoint
#================================================================

puts "========================================="
puts "Saving Checkpoint"
puts "========================================="

set checkpoint "${RESULT_DIR}/00_init.odb"
write_db $checkpoint

puts "  Saved: $checkpoint"
puts ""
