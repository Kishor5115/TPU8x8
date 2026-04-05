
#? Project Settings
set DESIGN          tpu_chip
set PLATFORM        ihpsg13
puts " DESIGN   : $DESIGN"
puts " PLATFORM : $PLATFORM"
puts ""
# -----------------------------------------------------------------------------------------------------------------------
#? Project Directories
set SYNTH_DIR       ../opt_yosys/out
set PDK_DIR         ../ihp13/pdk/ihp-sg13g2
set SCRIPT_DIR      scripts
set REPORT_DIR      reports
set RESULT_DIR      results
set LOG_DIR         logs
set TEMP_DIR        temp

# create directories 
exec mkdir -p $REPORT_DIR $RESULT_DIR $LOG_DIR $TEMP_DIR
puts "  Creating Directories --> $REPORT_DIR $RESULT_DIR $LOG_DIR $TEMP_DIR "
puts ""

# ------------------------------------------------------------------------------------------------------------------------

#? DESIGN FILES
set VERILOG_FILE    $SYNTH_DIR/${DESIGN}.v
set SDC_FILE        $SYNTH_DIR/${DESIGN}.sdc

puts "  VERILOG TOP MODULE      : $VERILOG_FILE"
puts "  SDC_FILE (constraints)  : $SDC_FILE"

set netlist_size_bytes [file size $VERILOG_FILE]
set netlist_size_mb [expr {$netlist_size_bytes / 1048576.0}]

puts "  NETLIST size in mb      : [format %.2f $netlist_size_mb] MB"
puts ""

# -------------------------------------------------------------------------------------------------------------------------

#? CLK and time delay parameters
# Target Frequency
set CLK_PERIOD      10.0  ;# 100 MHz in ns  
set CLK_PORT        clk_pad
set CLK_FREQ_MHZ    [expr {1000.0 / $CLK_PERIOD}]

puts "  CLK PORT            : $CLK_PORT"
puts "  CLK PERIOD          : $CLK_PERIOD ns"
puts "  CLK FREQUENCY       : $CLK_FREQ_MHZ MHz"

# Clock uncertainty (jitter + skew budget before CTS)
set CLK_UNCERTAINTY 0.3     ;# 500ps (2.5% of 20ns period)

set AVAILABLE_LOGIC_TIME [expr {$CLK_PERIOD - $CLK_UNCERTAINTY}]
puts "  Available for logic : ${AVAILABLE_LOGIC_TIME} ns"

# Input/Output delay constraints
set INPUT_DELAY_PCT  0.1    ;# 30% of clock period
set OUTPUT_DELAY_PCT 0.1    ;# 30% of clock period

set INPUT_DELAY  [expr {$CLK_PERIOD * $INPUT_DELAY_PCT}]
set OUTPUT_DELAY [expr {$CLK_PERIOD * $OUTPUT_DELAY_PCT}]

puts "  INPUT DELAY         : $INPUT_DELAY"
puts "  OUTPUT DELAY        : $OUTPUT_DELAY"
puts ""

# -----------------------------------------------------------------------------------------------------------------------

# ============================================================
#?   SECTION 4: TPU DESIGN PARAMETERS (from your RTL)
# ============================================================

puts " TPU Design Parameters"

# From your tpu_top module
set ARRAY_SIZE          8
set DATA_WIDTH          8       ;# INT8 for inputs (weights & activations)
set OUTPUT_DATA_WIDTH   16      ;# INT16 for accumulated outputs
set SRAM_DATA_WIDTH     32      ;# SRAM interface width

puts "  Array size        : ${ARRAY_SIZE}x${ARRAY_SIZE} (64 MACs)"
puts "  Input data width  : ${DATA_WIDTH} bits (INT8)"
puts "  Output data width : ${OUTPUT_DATA_WIDTH} bits (INT16)"
puts "  SRAM interface    : ${SRAM_DATA_WIDTH} bits"
puts ""

# -----------------------------------------------------------------------------------------------------------------------

# ==================================================================
#?   SECTION 5 : Hard Macro Configuration
# ==================================================================

# Weight / Data SRAM macros
set IN_SRAM_DEPTH   256
set IN_SRAM_WIDTH   64   ;# bits 

# Output SRAM macros
set OUT_SRAM_DEPTH  64
set OUT_SRAM_WIDTH  64   ;# bits

# Number of macros
set NUM_WEIGHT_MACROS 1
set NUM_DATA_MACROS   1
set NUM_OUT_MACROS    6

# ==================================================================
#      Macro Memory Size Calculation
# ==================================================================

# Input macro size (in KB)
set in_sram_bits   [expr {$IN_SRAM_DEPTH * $IN_SRAM_WIDTH}]
set in_sram_kb     [expr {$in_sram_bits / 8.0 / 1024.0}]

# Output macro size (in KB)
set out_sram_bits  [expr {$OUT_SRAM_DEPTH * $OUT_SRAM_WIDTH}]
set out_sram_kb    [expr {$out_sram_bits / 8.0 / 1024.0}]

# Totals
set total_input_kb   [expr {$NUM_WEIGHT_MACROS * $in_sram_kb + $NUM_DATA_MACROS * $in_sram_kb}]
set total_output_kb  [expr {$NUM_OUT_MACROS * $out_sram_kb}]
set total_sram_kb    [expr {$total_input_kb + $total_output_kb}]

# ==================================================================
#   Print Summary
# ==================================================================

puts "  SRAM Macro Configuration:"
puts "    Weight SRAM : ${IN_SRAM_DEPTH}x${IN_SRAM_WIDTH}"
puts "    Data SRAM   : ${IN_SRAM_DEPTH}x${IN_SRAM_WIDTH}"
puts "    Output SRAM : ${OUT_SRAM_DEPTH}x${OUT_SRAM_WIDTH} (x${NUM_OUT_MACROS})"
puts ""

puts "  SRAM Size Summary:"
puts "    Per Input Macro : [format %.2f $in_sram_kb] KB"
puts "    Per Output Macro: [format %.2f $out_sram_kb] KB"
puts ""
puts "    Total Input SRAM : [format %.2f $total_input_kb] KB"
puts "    Total Output SRAM: [format %.2f $total_output_kb] KB"
puts "    TOTAL SRAM       : [format %.2f $total_sram_kb] KB"
puts ""

# -----------------------------------------------------------------------------------------------------------------------

# ============================================================
#?  SECTION 6 : DIE AND CORE DIMENSIONS
# ============================================================

puts "Die Planning:"

# ============================================================
# 1) Gate Count Estimation
# ============================================================

set MAC_UNITS           [expr {$ARRAY_SIZE * $ARRAY_SIZE}]
set GATES_PER_MAC       40      ;# INT8 MAC estimate

set MAC_GATES           [expr {$MAC_UNITS * $GATES_PER_MAC}]
set CONTROL_GATES       10000   ;# Controller + FSM + Bus
set BUFFER_GATES        5000    ;# FIFOs + interface logic

set TOTAL_GATES         [expr {$MAC_GATES + $CONTROL_GATES + $BUFFER_GATES}]

puts "  Gate count estimate:"
puts "    ${MAC_UNITS} MACs × ${GATES_PER_MAC} gates/MAC = [format %.1f [expr {$MAC_GATES / 1000.0}]]K gates"
puts "    Control logic: [format %.1f [expr {$CONTROL_GATES / 1000.0}]]K gates"
puts "    Buffers/FIFOs: [format %.1f [expr {$BUFFER_GATES / 1000.0}]]K gates"
puts "    Total: [format %.1f [expr {$TOTAL_GATES / 1000.0}]]K gates"
puts ""

# ============================================================
# 2) Core Area Estimation (Logic Only)
# ============================================================

set GATE_DENSITY_PER_MM2    150000.0
set CORE_AREA_MM2           [expr {$TOTAL_GATES / $GATE_DENSITY_PER_MM2}]
set AREA_MARGIN             1.5

set REQUIRED_AREA_MM2       [expr {$CORE_AREA_MM2 * $AREA_MARGIN}]
set CORE_SIDE_MM            [expr {sqrt($REQUIRED_AREA_MM2)}]

puts "  Logic area estimation:"
puts "    Raw logic area: [format %.3f $CORE_AREA_MM2] mm²"
puts "    With ${AREA_MARGIN}x margin: [format %.3f $REQUIRED_AREA_MM2] mm²"
puts "    Estimated core side: [format %.2f $CORE_SIDE_MM] mm"
puts ""

# ============================================================
# 3) IO Pad Frame Constraints (IHP SG13G2 Reference)
# ============================================================
set PAD_SIZE        70.0
set PAD_DEPTH      180.0
set POWER_RING      80.0

set CORE_MARGIN     [expr {$PAD_SIZE + $PAD_DEPTH + $POWER_RING}]  ;# 330 µm

#? Die size for 8×8 TPU 
set DIE_WIDTH       2800.0
set DIE_HEIGHT      2800.0

puts "  Selected die: ${DIE_WIDTH} µm × ${DIE_HEIGHT} µm"
puts "  Total die area: [format %.2f [expr {$DIE_WIDTH * $DIE_HEIGHT / 1e6}]] mm²"
puts ""

set CORE_WIDTH      [expr {$DIE_WIDTH - 2 * $CORE_MARGIN}]
set CORE_HEIGHT     [expr {$DIE_HEIGHT - 2 * $CORE_MARGIN}]

puts "  Core dimensions:"
puts "    ${CORE_WIDTH} µm × ${CORE_HEIGHT} µm"
puts "    Margin per side: ${CORE_MARGIN} µm"
puts ""

# -----------------------------------------------------------------------------------------------------------------------

# =================================================================================================
#?    SECTION 7 : PLACEMENT CONFIGURATION
# =================================================================================================

puts "Placement Configuration:"

# Reduced for macro-heavy TPU
set PLACE_DENSITY   0.40

set STDCELL_AREA    [expr {$CORE_WIDTH * $CORE_HEIGHT * $PLACE_DENSITY}]
set STDCELL_AREA_MM2 [expr {$STDCELL_AREA / 1e6}]

puts "  Density                : [expr {$PLACE_DENSITY * 100}]%"
puts "  Estimated stdcell area : [format %.3f $STDCELL_AREA_MM2] mm²"

# Halo around SRAM macros
set MACRO_HALO_X    10.0
set MACRO_HALO_Y    10.0

puts "  Macro halo             : ${MACRO_HALO_X} µm × ${MACRO_HALO_Y} µm"

set MACRO_PLACEMENT "manual"
puts "  Macro placement        : $MACRO_PLACEMENT"
puts ""

# =================================================================================================
#?     SECTION 8 : FILL CELLS AND DECAPS
# Note: IHP SG13G2 uses fill cells for well ties (no dedicated tap cells)
# =================================================================================================

puts "DRC Compliance:"

set TAPCELL_DIST    25.0
# IHP SG13G2 doesn't have dedicated tap cells - fill cells provide substrate ties
set FILL_CELLS      [list sg13g2_fill_1 sg13g2_fill_2 sg13g2_fill_4 sg13g2_fill_8]
set DECAP_CELLS     [list sg13g2_decap_4 sg13g2_decap_8]

puts "  Fill cells  : $FILL_CELLS"
puts "  Decap cells : $DECAP_CELLS"
puts ""

# -----------------------------------------------------------------------------------------------------------------------

# =================================================================================================
#?     SECTION 9 : POWER DISTRIBUTION
# =================================================================================================

puts "Power Distribution:"

# ============================================================
# Power Nets
# ============================================================

set POWER_NET       "VDD"
set GROUND_NET      "VSS"
set POWER_NETS      "$POWER_NET $GROUND_NET"

puts "  Power nets      : $POWER_NETS"

# ============================================================
# Power Estimation
# ============================================================

# Estimated for 64 INT8 MACs + SRAM + control at 100MHz
set ESTIMATED_POWER_MW  50

puts "  Estimated power : ${ESTIMATED_POWER_MW} mW (${CLK_FREQ_MHZ}MHz target)"

# ============================================================
#    PDN Configuration (IHP SG13G2)
# ============================================================

# Use upper metals for stronger grid
set PDN_METAL_LAYERS    [list Metal4 Metal5]

# Conservative grid for macro-heavy design
set PDN_STRIPE_PITCH    40.0
set PDN_STRIPE_WIDTH    4.5

puts "  PDN metals      : $PDN_METAL_LAYERS"
puts "  Stripe pitch    : ${PDN_STRIPE_PITCH} µm"
puts "  Stripe width    : ${PDN_STRIPE_WIDTH} µm"

# IR drop target (≈6–7% of 1.2V supply)
set MAX_IR_DROP_MV      80

puts "  IR drop target  : < ${MAX_IR_DROP_MV} mV"
puts ""

# -----------------------------------------------------------------------------------------------------------------------

# =================================================================================================
#? SECTION 10 : CLOCK TREE SYNTHESIS
# =================================================================================================

puts "Clock Tree Synthesis:"

# ============================================================
# Buffer Selection (SG13G2)
# ============================================================

set CTS_BUF_CELL    "sg13g2_buf_2"
set CTS_ROOT_BUF    "sg13g2_buf_4"
set CTS_BUF_CELLS   [list "sg13g2_buf_2" "sg13g2_buf_4"]

puts "  Root buffer                 : $CTS_ROOT_BUF"
puts "  Tree buffers                : $CTS_BUF_CELLS"

# ============================================================
# CTS Targets
# ============================================================

# 2% skew target (safe and realistic)
set CTS_TARGET_SKEW     0.4

# Comfortable latency
set CTS_TARGET_LATENCY  1.5

puts "  Target skew                 : ${CTS_TARGET_SKEW} ns"
puts "  Target latency              : ${CTS_TARGET_LATENCY} ns"

# Limit clock fanout to avoid large branches
set CTS_MAX_FANOUT      20

puts "  Max clock fanout per buffer : $CTS_MAX_FANOUT"

# ============================================================
# Flip-Flop Estimate (From Synthesis)
# ============================================================

set ESTIMATED_FF_COUNT  2816

puts "  Estimated flip-flops        : $ESTIMATED_FF_COUNT"
puts ""

# ------------------------------------------------------------------------------------------------------------------------

# =================================================================================================
#?         SECTION 11 : FILLER CELLS
# ==================================================================================================

puts "Filler Cells:"

# ============================================================
# Standard Cell Fillers (Descending order is important)
# ============================================================

set FILLER_CELLS [list \
    sg13g2_fill_8 \
    sg13g2_fill_4 \
    sg13g2_fill_2 \
    sg13g2_fill_1 \
]

# Decap cells for local supply stabilization
set DECAP_CELLS [list \
    sg13g2_decap_8 \
    sg13g2_decap_4 \
]

# ============================================================
# IO Filler Cells (Pad ring gap fillers)
# ============================================================

set IO_FILLER_CELLS [list \
    sg13g2_Filler10000 \
    sg13g2_Filler4000 \
    sg13g2_Filler2000 \
    sg13g2_Filler1000 \
    sg13g2_Filler400 \
    sg13g2_Filler200 \
]

puts "  Standard fillers:"
foreach filler $FILLER_CELLS {
    puts "    - $filler"
}

puts "  Decap cells:"
foreach decap $DECAP_CELLS {
    puts "    - $decap"
}

puts "  IO fillers:"
foreach filler $IO_FILLER_CELLS {
    puts "    - $filler"
}
puts ""

# ------------------------------------------------------------------------------------------------------------------------

# =================================================================================================
#?              SECTION 12 :   ROUTING CONFIGURATION 
# =================================================================================================

puts "Routing Configuration:"

# ------------------------------------------------------------
# Routing Layer Strategy
# ------------------------------------------------------------

set MIN_ROUTING_LAYER  "Metal1"
set MAX_ROUTING_LAYER  "Metal5"

puts "  Routing layers: $MIN_ROUTING_LAYER → $MAX_ROUTING_LAYER"

# Reserve top metal primarily for PDN
set SIGNAL_MAX_LAYER "Metal4"

puts "  Signal routing limited to: $MIN_ROUTING_LAYER → $SIGNAL_MAX_LAYER"
puts "  Metal5 prioritized for PDN"

# ------------------------------------------------------------
# Via Stack Control
# ------------------------------------------------------------

set VIA_LAYERS [list Via1 Via2 Via3 Via4]

puts "  Via stack: $VIA_LAYERS"

# Enable via stacking (improves congestion in macro-heavy design)
set ENABLE_VIA_STACKING 1
puts "  Via stacking: Enabled"
puts ""

# -----------------------------------------------------------------------------------------------------------------------

# =================================================================================================
#?                   SECTION 13 : DONT USE CELLS
# =================================================================================================

puts "Cell Usage Restrictions:"

set DONT_USE [list]

# Prevent accidental IO pad use in core
lappend DONT_USE "sg13g2_IOPad*"

# Avoid delay cells unless explicitly needed
lappend DONT_USE "sg13g2_dly*"

puts "  Dont_use patterns:"
foreach pattern $DONT_USE {
    puts "    - $pattern"
}
puts ""

# -----------------------------------------------------------------------------------------------------------------------

# =================================================================================================
#?   CONFIGURATION SUMMARY
# ==================================================================================================

puts "========================================="
puts "Configuration Summary"
puts "========================================="

puts "Design:"
puts "  Name: $DESIGN"
puts "  Array: ${ARRAY_SIZE}×${ARRAY_SIZE} (${MAC_UNITS} MACs)"
puts "  Data: INT${DATA_WIDTH} inputs, INT${OUTPUT_DATA_WIDTH} outputs"
puts ""

puts "Physical:"
puts "  Die: ${DIE_WIDTH}µm × ${DIE_HEIGHT}µm ([format %.2f [expr {$DIE_WIDTH * $DIE_HEIGHT / 1e6}]] mm²)"
puts "  Core: ${CORE_WIDTH}µm × ${CORE_HEIGHT}µm"
puts "  Target Utilization: [expr {$PLACE_DENSITY * 100}]%"
puts ""

puts "Performance:"
puts "  Clock: ${CLK_FREQ_MHZ} MHz (${CLK_PERIOD} ns)"
puts "  Total Cells: ~79K"
puts "  Flip-Flops: $ESTIMATED_FF_COUNT"
puts "  Estimated Power (@${CLK_FREQ_MHZ}MHz): ~${ESTIMATED_POWER_MW} mW"
puts ""

puts "Memory (Hard SRAM Macros):"
puts "  2× RM_IHPSG13_1P_256x64  (Weight + Data)"
puts "  6× RM_IHPSG13_1P_64x64   (Output Banks A/B/C ×2)"
puts "  Total: 8 SRAM macros (~[format %.0f $total_sram_kb] KB)"
puts ""

puts "==================================================================================="
puts ""
puts "✓ Configuration complete"
puts ""
