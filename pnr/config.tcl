
# Project Settings
set DESIGN          tpu_chip
set PLATFORM        ihpsg13

# Directories
set SYNTH_DIR       ../yosys/out
set PDK_DIR         ../ihp13/pdk/ihp-sg13g2
set SCRIPT_DIR      scripts
set REPORT_DIR      reports
set RESULT_DIR      results
set LOG_DIR         logs
set TEMP_DIR        temp

# Create directories
exec mkdir -p $REPORT_DIR $RESULT_DIR $LOG_DIR $TEMP_DIR

# Design Files
set VERILOG_FILE    $SYNTH_DIR/${DESIGN}.v
set SDC_FILE        $SYNTH_DIR/${DESIGN}.sdc

set netlist_size_bytes [file size $VERILOG_FILE]
set netlist_size_mb [expr {$netlist_size_bytes / 1048576.0}]

# Target Frequency
set CLK_PERIOD      10.0  ;# 100 MHz in ns  
set CLK_PORT        clk_pad
set CLK_FREQ_MHZ    [expr {1000.0 / $CLK_PERIOD}]

# Clock uncertainty (jitter + skew budget before CTS)
set CLK_UNCERTAINTY 0.3     ;# 500ps (2.5% of 20ns period)

set AVAILABLE_LOGIC_TIME [expr {$CLK_PERIOD - $CLK_UNCERTAINTY}]
puts "  Available for logic: ${AVAILABLE_LOGIC_TIME} ns"

# Input/Output delay constraints
set INPUT_DELAY_PCT  0.3    ;# 30% of clock period
set OUTPUT_DELAY_PCT 0.3    ;# 30% of clock period

set INPUT_DELAY  [expr {$CLK_PERIOD * $INPUT_DELAY_PCT}]
set OUTPUT_DELAY [expr {$CLK_PERIOD * $OUTPUT_DELAY_PCT}]

# ============================================================
# SECTION 4: TPU DESIGN PARAMETERS (from your RTL)
# ============================================================

puts "TPU Design Parameters:"

# From your tpu_top module
set ARRAY_SIZE          8
set DATA_WIDTH          8       ;# INT8 for inputs (weights & activations)
set OUTPUT_DATA_WIDTH   16      ;# INT16 for accumulated outputs
set SRAM_DATA_WIDTH     32      ;# SRAM interface width

puts "  Array size: ${ARRAY_SIZE}x${ARRAY_SIZE} (64 MACs)"
puts "  Input data width: ${DATA_WIDTH} bits (INT8)"
puts "  Output data width: ${OUTPUT_DATA_WIDTH} bits (INT16)"
puts "  SRAM interface: ${SRAM_DATA_WIDTH} bits"
puts ""




# ============================================================
# SECTION 5: MEMORY REQUIREMENTS
# ============================================================

puts "Memory Requirements:"

set matrix_size         $ARRAY_SIZE
set elements_per_matrix [expr {$matrix_size * $matrix_size}]

# Input matrices (weights or activations)
set bytes_per_input_matrix   [expr {$elements_per_matrix * $DATA_WIDTH / 8}]
set kb_per_input_matrix      [expr {$bytes_per_input_matrix / 1024.0}]

# Output matrices (accumulated results)
set bytes_per_output_matrix  [expr {$elements_per_matrix * $OUTPUT_DATA_WIDTH / 8}]
set kb_per_output_matrix     [expr {$bytes_per_output_matrix / 1024.0}]

puts "  Per Input Matrix (${matrix_size}×${matrix_size}, INT8):"
puts "    Elements: $elements_per_matrix"
puts "    Bytes: $bytes_per_input_matrix"
puts "    KB: [format %.4f $kb_per_input_matrix]"
puts ""
puts "  Per Output Matrix (${matrix_size}×${matrix_size}, INT16):"
puts "    Elements: $elements_per_matrix"
puts "    Bytes: $bytes_per_output_matrix"
puts "    KB: [format %.4f $kb_per_output_matrix]"
puts ""

# Total if using SRAM (optional)
set weight_buffer_depth 16
set activation_buffer_depth 32
set output_buffer_depth 8

set weight_buffer_kb    [expr {$weight_buffer_depth * $kb_per_input_matrix}]
set activation_buffer_kb [expr {$activation_buffer_depth * $kb_per_input_matrix}]
set output_buffer_kb    [expr {$output_buffer_depth * $kb_per_output_matrix}]
set total_sram_kb       [expr {$weight_buffer_kb + $activation_buffer_kb + $output_buffer_kb}]

puts "  Estimated SRAM (if using macros):"
puts "    Weight FIFO: [format %.2f $weight_buffer_kb] KB"
puts "    Unified Buffer: [format %.2f $activation_buffer_kb] KB"
puts "    Output Buffer: [format %.2f $output_buffer_kb] KB"
puts "    Total: [format %.2f $total_sram_kb] KB"
puts ""
puts "  NOTE: 8×8 TPU uses 8 SRAM macros:"
puts "        2× RM_IHPSG13_1P_256x64  (Weight + Data, 2 KB each)"
puts "        6× RM_IHPSG13_1P_64x64   (Output Banks A/B/C × 2, 0.5 KB each)"
puts "        Total SRAM: 7 KB"
puts "        Actual flip-flops from synthesis: 2,816"
puts ""

# ============================================================
# SECTION 7: DIE AND CORE DIMENSIONS
# ============================================================

puts "Die Planning:"

# Gate count for 8×8 INT8 TPU
set MAC_UNITS           [expr {$ARRAY_SIZE * $ARRAY_SIZE}]
set GATES_PER_MAC       40  ;# INT8 MAC is simpler than INT16

set MAC_GATES           [expr {$MAC_UNITS * $GATES_PER_MAC}]
set CONTROL_GATES       10000
set BUFFER_GATES        5000

set TOTAL_GATES         [expr {$MAC_GATES + $CONTROL_GATES + $BUFFER_GATES}]

puts "  Gate count estimate:"
puts "    ${MAC_UNITS} MACs × ${GATES_PER_MAC} gates/MAC = [format %.1f [expr {$MAC_GATES / 1000.0}]]K gates"
puts "    Control logic: [format %.1f [expr {$CONTROL_GATES / 1000.0}]]K gates"
puts "    Buffers/FIFOs: [format %.1f [expr {$BUFFER_GATES / 1000.0}]]K gates"
puts "    Total: [format %.1f [expr {$TOTAL_GATES / 1000.0}]]K gates"
puts ""

# Area calculation
set GATE_DENSITY_PER_MM2    150000
set CORE_AREA_MM2           [expr {$TOTAL_GATES / double($GATE_DENSITY_PER_MM2)}]
set AREA_MARGIN             1.5

set REQUIRED_AREA_MM2       [expr {$CORE_AREA_MM2 * $AREA_MARGIN}]
set DIE_SIZE_MM             [expr {sqrt($REQUIRED_AREA_MM2)}]

puts "  Area calculation:"
puts "    Raw area: [format %.3f $CORE_AREA_MM2] mm²"
puts "    With ${AREA_MARGIN}x margin: [format %.3f $REQUIRED_AREA_MM2] mm²"
puts "    Calculated die: [format %.2f $DIE_SIZE_MM] mm × [format %.2f $DIE_SIZE_MM] mm"
puts ""

# Die size for 8×8 TPU hard macro with IO pads
# Based on Croc SoC reference design (IHP SG13G2 padframe):
#   - Bonding pad size:     70µm
#   - IO pad depth:        180µm
#   - Power ring:           80µm
#   - Core margin = 70 + 180 + 80 = 330µm per side
set PAD_SIZE        70.0    ;# Bonding pad size
set PAD_DEPTH      180.0    ;# IO pad depth from edge
set POWER_RING      80.0    ;# Power ring reservation

set DIE_WIDTH       2800.0  ;# 3.5mm for 8×8 TPU with 8 SRAMs
set DIE_HEIGHT      2800.0

puts "  Selected die: ${DIE_WIDTH} µm × ${DIE_HEIGHT} µm"
puts "  Total area: [format %.1f [expr {$DIE_WIDTH * $DIE_HEIGHT / 1e6}]] mm²"
puts "  IO pad configuration:"
puts "    Bonding pad: ${PAD_SIZE} µm"
puts "    Pad depth: ${PAD_DEPTH} µm"
puts "    Power ring: ${POWER_RING} µm"
puts ""
            
# Core margin accounts for IO pad frame
set CORE_MARGIN     [expr {$PAD_SIZE + $PAD_DEPTH + $POWER_RING}]  ;# 330µm for IO pads

set CORE_WIDTH      [expr {$DIE_WIDTH - 2 * $CORE_MARGIN}]
set CORE_HEIGHT     [expr {$DIE_HEIGHT - 2 * $CORE_MARGIN}]

puts "  Core: ${CORE_WIDTH} µm × ${CORE_HEIGHT} µm"
puts "  Margin: ${CORE_MARGIN} µm"
puts ""

# ============================================================
# SECTION 8: PLACEMENT CONFIGURATION
# ============================================================

puts "Placement Configuration:"

set PLACE_DENSITY   0.40  ;# Reduced to 40% for better routing resources

set STDCELL_AREA    [expr {$CORE_WIDTH * $CORE_HEIGHT * $PLACE_DENSITY}]
set STDCELL_AREA_MM2 [expr {$STDCELL_AREA / 1e6}]

puts "  Density: [expr {$PLACE_DENSITY * 100}]%"
puts "  Standard cell area: [format %.3f $STDCELL_AREA_MM2] mm²"

set MACRO_HALO_X    10.0
set MACRO_HALO_Y    10.0

puts "  Macro halo: ${MACRO_HALO_X} µm × ${MACRO_HALO_Y} µm"

set MACRO_PLACEMENT "auto"
puts "  Macro placement: $MACRO_PLACEMENT"
puts ""

# ============================================================
# SECTION 9: FILL CELLS AND DECAPS
# Note: IHP SG13G2 uses fill cells for well ties (no dedicated tap cells)
# ============================================================

puts "DRC Compliance:"

set TAPCELL_DIST    25.0
# IHP SG13G2 doesn't have dedicated tap cells - fill cells provide substrate ties
set FILL_CELLS      [list sg13g2_fill_1 sg13g2_fill_2 sg13g2_fill_4 sg13g2_fill_8]
set DECAP_CELLS     [list sg13g2_decap_4 sg13g2_decap_8]

puts "  Fill cells: $FILL_CELLS"
puts "  Decap cells: $DECAP_CELLS"
puts ""

# ============================================================
# SECTION 10: POWER DISTRIBUTION
# ============================================================

puts "Power Distribution:"

set POWER_NET       "VDD"
set GROUND_NET      "VSS"
set POWER_NETS      "$POWER_NET $GROUND_NET"

puts "  Power nets: $POWER_NETS"

# Power estimation for 8×8 INT8 TPU
set ESTIMATED_POWER_MW  50   ;# ~50 mW for 64 MACs at 100MHz

puts "  Estimated power: ${ESTIMATED_POWER_MW} mW"

set PDN_METAL_LAYERS    [list Metal4 Metal5]
set PDN_STRIPE_PITCH    40.0
set PDN_STRIPE_WIDTH    4.5

puts "  PDN metals: $PDN_METAL_LAYERS"
puts "  Stripe pitch: ${PDN_STRIPE_PITCH} µm"
puts "  Stripe width: ${PDN_STRIPE_WIDTH} µm"

set MAX_IR_DROP_MV      80

puts "  IR drop target: < ${MAX_IR_DROP_MV} mV"
puts ""

# ============================================================
# SECTION 11: CLOCK TREE SYNTHESIS
# ============================================================

puts "Clock Tree Synthesis:"

set CTS_BUF_CELL    "sg13g2_buf_2"
set CTS_BUF_CELLS   [list "sg13g2_buf_2" "sg13g2_buf_4"]
set CTS_ROOT_BUF    "sg13g2_buf_4"

puts "  Root buffer: $CTS_ROOT_BUF"
puts "  Tree buffers: $CTS_BUF_CELLS"

set CTS_TARGET_SKEW     0.4
set CTS_TARGET_LATENCY  1.5

puts "  Target skew: ${CTS_TARGET_SKEW} ns"
puts "  Target latency: ${CTS_TARGET_LATENCY} ns"

set ESTIMATED_FF_COUNT  2816  ;# From Yosys synthesis report

puts "  Estimated flip-flops: $ESTIMATED_FF_COUNT"
puts ""

# ============================================================
# SECTION 12: FILLER CELLS
# ============================================================

puts "Filler Cells:"

set FILLER_CELLS [list \
    sg13g2_fill_8 \
    sg13g2_fill_4 \
    sg13g2_fill_2 \
    sg13g2_fill_1 \
]

# IO Filler cells (for filling gaps between IO pads)
set IO_FILLER_CELLS [list \
    sg13g2_Filler10000 \
    sg13g2_Filler4000 \
    sg13g2_Filler2000 \
    sg13g2_Filler1000 \
    sg13g2_Filler400 \
    sg13g2_Filler200 \
]

foreach filler $FILLER_CELLS {
    puts "  - $filler"
}
foreach filler $IO_FILLER_CELLS {
    puts "  - $filler"
}
puts ""

# ============================================================
# SECTION 13: ROUTING CONFIGURATION
# ============================================================

puts "Routing Configuration:"

set MIN_ROUTING_LAYER  "Metal1"
set MAX_ROUTING_LAYER  "Metal5"

puts "  Layers: $MIN_ROUTING_LAYER to $MAX_ROUTING_LAYER"

set VIA_LAYERS [list Via1 Via2 Via3 Via4]

puts "  Vias: $VIA_LAYERS"
puts ""

# ============================================================
# SECTION 14: DONT_USE CELLS
# ============================================================

puts "Cell Usage Restrictions:"

set DONT_USE [list]

lappend DONT_USE "sg13g2_IOPad*"
lappend DONT_USE "sg13g2_dly*"

puts "  Dont_use patterns:"
foreach pattern $DONT_USE {
    puts "    - $pattern"
}
puts ""

# ============================================================
# CONFIGURATION SUMMARY
# ============================================================

puts "========================================="
puts "Configuration Summary"
puts "========================================="
puts "Design:"
puts "  Name: $DESIGN"
puts "  Array: ${ARRAY_SIZE}×${ARRAY_SIZE} (${MAC_UNITS} MACs)"
puts "  Data: INT${DATA_WIDTH} inputs, INT${OUTPUT_DATA_WIDTH} outputs"
puts ""
puts "Physical:"
puts "  Die: ${DIE_WIDTH}µm × ${DIE_HEIGHT}µm ([format %.1f [expr {$DIE_WIDTH * $DIE_HEIGHT / 1e6}]] mm²)"
puts "  Core: ${CORE_WIDTH}µm × ${CORE_HEIGHT}µm"
puts "  Utilization: [expr {$PLACE_DENSITY * 100}]%"
puts ""
puts "Performance:"
puts "  Clock: ${CLK_FREQ_MHZ} MHz (${CLK_PERIOD} ns)"
puts "  Gates: [format %.1f [expr {$TOTAL_GATES / 1000.0}]]K"
puts "  FFs: $ESTIMATED_FF_COUNT"
puts "  Power: ~${ESTIMATED_POWER_MW} mW"
puts ""
puts "Memory (SRAM macros):"
puts "  2× RM_IHPSG13_1P_256x64 (Weight + Data)"
puts "  6× RM_IHPSG13_1P_64x64 (Output Banks A/B/C × 2)"
puts "  Total: 8 SRAM macros (7 KB)"
puts "========================================="
puts ""
puts "✓ Configuration complete"
puts ""
