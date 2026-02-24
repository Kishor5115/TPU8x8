# ============================================================
# IHP SG13G2 PDK Initialization
# ============================================================

source config.tcl

# PDK Paths
set pdk_cells_lib ${PDK_DIR}/libs.ref/sg13g2_stdcell/lib
set pdk_cells_lef ${PDK_DIR}/libs.ref/sg13g2_stdcell/lef
set pdk_sram_lib  ${PDK_DIR}/libs.ref/sg13g2_sram/lib
set pdk_sram_lef  ${PDK_DIR}/libs.ref/sg13g2_sram/lef
set pdk_io_lib    ${PDK_DIR}/libs.ref/sg13g2_io/lib
set pdk_io_lef    ${PDK_DIR}/libs.ref/sg13g2_io/lef

puts "========================================="
puts "Initializing IHP SG13G2 PDK"
puts "========================================="

########################################################
# verification of PDK paths before proceeding
######################################################
puts "Verifying PDK paths..."
set path_errors 0

foreach {name path} [list "Standard Cell Library" $pdk_cells_lib  "Standard Cell LEF" $pdk_cells_lef  "SRAM Library"  $pdk_sram_lib  "SRAM LEF"  $pdk_sram_lef "IO Library"    $pdk_io_lib "IO LEF"  $pdk_io_lef 
] {
    if {![file exists $path]} {
        puts "  ✗ ERROR: $name not found"
        puts "    Path: $path"
        incr path_errors
    } else {
        puts "  ✓ $name"
    }
}

if {$path_errors > 0} {
    puts ""
    puts "ERROR: $path_errors required PDK paths missing!"
    puts "Please check PDK installation at: $PDK_DIR"
    puts "========================================="
    exit 1
}

puts ""

# ============================================================
# SECTION 2: PROCESS CORNER DEFINITION
# ============================================================
# Multi-corner analysis ensures robust design across:
# - Process variation (fast/slow transistors)
# - Voltage variation (±10% typically)
# - Temperature variation (-40°C to 125°C)
#
# For TPU, multi-corner is CRITICAL because:
# - Systolic array has long combinational paths
# - Matrix multiply timing is performance bottleneck
# - High clock frequency requirements
# ============================================================

puts "--- Process Corner Configuration ---"
puts ""
puts "Defining corners for multi-corner analysis..."

# Define all corners
# OpenROAD/OpenSTA needs corners defined before reading libs
define_corners ss ff tt

puts "✓ Corners defined:"
puts "  - SS (Slow-Slow):   1.08V, 125°C  → Worst setup timing"
puts "  - FF (Fast-Fast):   1.32V, -40°C  → Worst hold timing"
puts "  - TT (Typical):     1.20V,  25°C  → Nominal operation"
puts ""


# ============================================================
# SECTION 3: STANDARD CELL LIBERTY FILES
# ============================================================
# Liberty (.lib) files contain complete cell characterization:
# - Timing arcs (input → output delay)
# - Power consumption (static + dynamic)
# - Functional behavior (truth tables)
# - Capacitance, transition time, etc.
#
# Must load for ALL corners to enable multi-corner analysis
# ============================================================

puts "--- Standard Cell Libraries ---"
puts ""

set stdcell_loaded 0

# --- Typical Corner (REQUIRED) ---
set tt_lib "${pdk_cells_lib}/sg13g2_stdcell_typ_1p20V_25C.lib"
if {![file exists $tt_lib]} {
    puts "ERROR: Typical corner library not found!"
    puts "Expected: $tt_lib"
    exit 1
}

read_liberty -corner tt $tt_lib
puts "✓ Loaded TT: [file tail $tt_lib]"
incr stdcell_loaded

# --- Slow Corner (for setup timing) ---
set ss_lib "${pdk_cells_lib}/sg13g2_stdcell_slow_1p08V_125C.lib"
if {[file exists $ss_lib]} {
    read_liberty -corner ss $ss_lib
    puts "✓ Loaded SS: [file tail $ss_lib]"
    incr stdcell_loaded
} else {
    puts "⚠ WARNING: Slow corner library not found"
    puts "  Setup timing will use TT corner only (less pessimistic)"
}

# --- Fast Corner (for hold timing) ---
set ff_lib "${pdk_cells_lib}/sg13g2_stdcell_fast_1p32V_m40C.lib"
if {[file exists $ff_lib]} {
    read_liberty -corner ff $ff_lib
    puts "✓ Loaded FF: [file tail $ff_lib]"
    incr stdcell_loaded
} else {
    puts "⚠ WARNING: Fast corner library not found"
    puts "  Hold timing will use TT corner only (less pessimistic)"
}

puts "Standard cells: $stdcell_loaded corners loaded"
puts ""

# ============================================================
# SECTION 4: IO CELL LIBERTY FILES
# ============================================================
# IO cells interface core logic (1.2V) with external pads (3.3V)
# Include level shifters, ESD protection, drive strength buffers
# ============================================================

puts "--- IO Cell Libraries ---"
puts ""

set io_loaded 0

# Typical corner
set tt_io "${pdk_io_lib}/sg13g2_io_typ_1p2V_3p3V_25C.lib"
if {[file exists $tt_io]} {
    read_liberty -corner tt $tt_io
    puts "✓ Loaded TT: [file tail $tt_io]"
    incr io_loaded
}

# Slow corner
set ss_io "${pdk_io_lib}/sg13g2_io_slow_1p08V_3p0V_125C.lib"
if {[file exists $ss_io]} {
    read_liberty -corner ss $ss_io
    puts "✓ Loaded SS: [file tail $ss_io]"
    incr io_loaded
}

# Fast corner
set ff_io "${pdk_io_lib}/sg13g2_io_fast_1p32V_3p6V_m40C.lib"
if {[file exists $ff_io]} {
    read_liberty -corner ff $ff_io
    puts "✓ Loaded FF: [file tail $ff_io]"
    incr io_loaded
}

if {$io_loaded == 0} {
    puts "⚠ WARNING: No IO cell libraries loaded"
    puts "  Design must be core-only (no I/O pads)"
} else {
    puts "IO cells: $io_loaded corners loaded"
}

puts ""

# ============================================================
# SECTION 5: SRAM LIBERTY FILES
# ============================================================
# CRITICAL FOR TPU!
#
# Your TPU architecture requires significant on-chip memory:
# 1. Weight FIFO: Buffers weight matrices from external DRAM
# 2. Unified Buffer: Stores activation data locally
# 3. Accumulator storage: Holds partial results

# Need multiple SRAM macros or large memory compiler instances
# ============================================================

puts "--- SRAM Libraries (TPU Memory Blocks) ---"
puts ""

# Calculate TPU memory requirements
# Read parameters from config.tcl if available
if {[info exists ARRAY_SIZE]} {
    set matrix_size $ARRAY_SIZE
} else {
    set matrix_size 8  ;# Default: 8×8 array
}

if {[info exists DATA_WIDTH]} {
    set input_data_width $DATA_WIDTH
} else {
    set input_data_width 8  ;# Default: INT8
}

if {[info exists OUTPUT_DATA_WIDTH]} {
    set output_data_width $OUTPUT_DATA_WIDTH
} else {
    set output_data_width 16  ;# Default: INT16
}

# Calculate storage requirements
set elements_per_matrix [expr {$matrix_size * $matrix_size}]
set bytes_per_input_matrix [expr {($elements_per_matrix * $input_data_width) / 8}]
set bytes_per_output_matrix [expr {($elements_per_matrix * $output_data_width) / 8}]
set kb_per_input_matrix [expr {$bytes_per_input_matrix / 1024.0}]
set kb_per_output_matrix [expr {$bytes_per_output_matrix / 1024.0}]

puts "TPU Memory Requirements (8×8 Array - 64 MACs):"
puts "  Array size: ${matrix_size}×${matrix_size} (${elements_per_matrix} MACs)"
puts "  Input data width: ${input_data_width} bits (INT${input_data_width})"
puts "  Output data width: ${output_data_width} bits (INT${output_data_width})"
puts ""
puts "  Storage per input matrix: ${bytes_per_input_matrix} bytes ([format %.4f $kb_per_input_matrix] KB)"
puts "  Storage per output matrix: ${bytes_per_output_matrix} bytes ([format %.4f $kb_per_output_matrix] KB)"
puts ""
puts "  Expected SRAM Macros for 8×8 TPU:"
puts "    - 2× RM_IHPSG13_1P_1024x64_c2_bm_bist (Weight + Data)"
puts "    - 6× RM_IHPSG13_1P_256x64_c2_bm_bist (Output A/B/C × 2)"
puts "    - Total: 8 SRAM macros"
puts ""

# Load SRAM libraries for all corners
# For 8×8 TPU: Need RM_IHPSG13_1P_1024x64 and RM_IHPSG13_1P_256x64
set sram_loaded 0
set sram_files_found 0
set sram_1024x64_found 0
set sram_256x64_found 0

foreach {corner suffix} {
    tt "typ_1p20V_25C"
    ss "slow_1p08V_125C"
    ff "fast_1p32V_m55C"
} {
    set pattern "${pdk_sram_lib}/*_${suffix}.lib"
    set files [glob -nocomplain $pattern]
    
    if {[llength $files] > 0} {
        foreach file $files {
            read_liberty -corner $corner $file
            set fname [file tail $file]
            puts "✓ [string toupper $corner]: $fname"
            
            # Check for specific TPU macros
            if {[string match "*1024x64*" $fname]} {
                set sram_1024x64_found 1
            }
            if {[string match "*256x64*" $fname]} {
                set sram_256x64_found 1
            }
            
            incr sram_loaded
        }
        incr sram_files_found
    }
}

if {$sram_loaded == 0} {
    puts "⚠ WARNING: No SRAM libraries found!"
    puts "  Searched in: $pdk_sram_lib"
    puts ""
    puts "  Critical for 8×8 TPU:"
    puts "  - RM_IHPSG13_1P_1024x64_c2_bm_bist (input weights/activations)"
    puts "  - RM_IHPSG13_1P_256x64_c2_bm_bist (output accumulators)"
    puts ""
    puts "  Impact: Cannot place SRAM macros - design will fail"
} else {
    puts ""
    puts "SRAM libraries: $sram_loaded files loaded across [expr {$sram_files_found}] corners"
    
    if {$sram_1024x64_found} {
        puts "✓ Found: RM_IHPSG13_1P_1024x64 (input SRAMs for 8×8 TPU)"
    } else {
        puts "⚠ Missing: RM_IHPSG13_1P_1024x64"
    }
    
    if {$sram_256x64_found} {
        puts "✓ Found: RM_IHPSG13_1P_256x64 (output SRAMs for 8×8 TPU)"
    } else {
        puts "⚠ Missing: RM_IHPSG13_1P_256x64"
    }
}

puts ""

# ============================================================
# SECTION 6: TECHNOLOGY LEF
# ============================================================
# Technology LEF defines:
# - Metal layers (thickness, spacing, resistance, capacitance)
# - Via definitions
# - Design rules (min width, min spacing, etc.)
# - Manufacturing grid
#
# MUST be loaded BEFORE cell LEFs!
# ============================================================

puts "--- Technology LEF ---"
puts ""

set tech_lef "${pdk_cells_lef}/sg13g2_tech.lef"

if {![file exists $tech_lef]} {
    puts "ERROR: Technology LEF not found!"
    puts "Expected: $tech_lef"
    exit 1
}

read_lef $tech_lef
puts "✓ Loaded: [file tail $tech_lef]"
puts ""

# Technology LEF defines:
# - 5 metal layers (Metal1-Metal5) typical for 130nm
# - Via layers (Via1-Via4)
# - Design rules for routing
# - Manufacturing grid (typically 5nm for 130nm process)

# ============================================================
# SECTION 7: STANDARD CELL LEF
# ============================================================
# Standard cell LEF contains physical abstracts of all cells
# MUST be loaded AFTER technology LEF!
# ============================================================

puts "--- Standard Cell LEF ---"
puts ""

set stdcell_lef "${pdk_cells_lef}/sg13g2_stdcell.lef"

if {![file exists $stdcell_lef]} {
    puts "ERROR: Standard cell LEF not found!"
    puts "Expected: $stdcell_lef"
    exit 1
}

read_lef $stdcell_lef
puts "✓ Loaded: [file tail $stdcell_lef]"
puts ""

# ============================================================
# SECTION 8: IO CELL LEF
# ============================================================

puts "--- IO Cell LEF ---"
puts ""

set io_lef "${pdk_io_lef}/sg13g2_io.lef"

if {[file exists $io_lef]} {
    read_lef $io_lef
    puts "✓ Loaded: [file tail $io_lef]"
} else {
    puts "⚠ WARNING: IO cell LEF not found"
    puts "  Expected: $io_lef"
    puts "  Proceeding without IO cells"
}

puts ""

# ============================================================
# SECTION 9: SRAM LEF FILES
# ============================================================
# SRAM LEF files define physical abstracts of memory macros
# Critical for TPU - need proper placement of Weight FIFO and Buffer
# ============================================================

puts "--- SRAM LEF Files (TPU Memory Macros) ---"
puts ""

set sram_lef_files [glob -nocomplain ${pdk_sram_lef}/*.lef]

if {[llength $sram_lef_files] == 0} {
    puts "⚠ WARNING: No SRAM LEF files found"
    puts "  Searched in: $pdk_sram_lef"
    puts "  This will affect placement of SRAM macros"
} else {
    set sram_lef_count 0
    set sram_1024x64_lef 0
    set sram_256x64_lef 0
    
    foreach file $sram_lef_files {
        if {[catch {read_lef $file} err]} {
            puts "  ✗ ERROR loading [file tail $file]: $err"
        } else {
            set fname [file tail $file]
            puts "  ✓ $fname"
            
            # Track specific TPU macro LEFs
            if {[string match "*1024x64*" $fname]} {
                incr sram_1024x64_lef
            }
            if {[string match "*256x64*" $fname]} {
                incr sram_256x64_lef
            }
            
            incr sram_lef_count
        }
    }
    puts ""
    puts "SRAM LEFs: $sram_lef_count files loaded"
    puts "  - 1024×64 macros: $sram_1024x64_lef (input SRAMs)"
    puts "  - 256×64 macros: $sram_256x64_lef (output SRAMs)"
}

puts ""

# ============================================================
# SECTION 10: LIBRARY VERIFICATION
# ============================================================

puts "--- Library Verification ---"
puts ""

# Check what libraries were loaded
set loaded_libs [get_libs * -quiet]
set lib_count [llength $loaded_libs]

puts "Total libraries loaded: $lib_count"

if {$lib_count == 0} {
    puts "ERROR: No libraries loaded!"
    puts "Cannot proceed with physical design"
    exit 1
}

# List all loaded libraries (optional, for debugging)
if {$lib_count < 20} {  ;# Only print if reasonable number
    puts ""
    puts "Loaded libraries:"
    foreach lib $loaded_libs {
        puts "  - [get_object_name $lib]"
    }
}

# Check for SRAM macros used in 8×8 TPU
puts ""
puts "Verifying 8×8 TPU SRAM macros..."

# Look for input SRAM macros (1024x64)
set input_sram_cells [get_lib_cells */RM_IHPSG13_1P_1024x64* -quiet]
if {[llength $input_sram_cells] > 0} {
    puts "✓ Found RM_IHPSG13_1P_1024x64 (input weights/activations)"
    puts "  Variants: [llength $input_sram_cells]"
} else {
    puts "⚠ Missing RM_IHPSG13_1P_1024x64"
}

# Look for output SRAM macros (256x64)
set output_sram_cells [get_lib_cells */RM_IHPSG13_1P_256x64* -quiet]
if {[llength $output_sram_cells] > 0} {
    puts "✓ Found RM_IHPSG13_1P_256x64 (output accumulators A/B/C)"
    puts "  Variants: [llength $output_sram_cells]"
} else {
    puts "⚠ Missing RM_IHPSG13_1P_256x64"
}

# Alternative patterns
set sram_cells [get_lib_cells */RM_IHPSG13_* -quiet]

if {[llength $sram_cells] == 0} {
    # Try alternative naming pattern
    set sram_cells [get_lib_cells */*SRAM* -quiet]
}

if {[llength $sram_cells] > 0} {
    puts "✓ Total SRAM macros found: [llength $sram_cells]"
} else {
    puts "⚠ No RM_IHPSG13 SRAM macros found in libraries"
}


# ============================================================
# SECTION 11: CELL VERIFICATION
# ============================================================

puts "--- Cell Verification ---"
puts ""

# Verify critical cells exist
set critical_cells [list \
    "sg13g2_buf_2" \
    "sg13g2_buf_4" \
    "sg13g2_buf_8" \
    "sg13g2_dfrbp_1" \
    "sg13g2_and2_1" \
]

puts "Checking critical cells..."
set missing_cells 0

foreach cell_name $critical_cells {
    set cells [get_lib_cells */${cell_name} -quiet]
    if {[llength $cells] > 0} {
        puts "  ✓ $cell_name"
    } else {
        puts "  ✗ $cell_name NOT FOUND"
        incr missing_cells
    }
}

if {$missing_cells > 0} {
    puts ""
    puts "WARNING: $missing_cells critical cells missing"
    puts "This may cause issues during synthesis/PnR"
}

puts ""

# ============================================================
# SECTION 12: DONT_USE CONFIGURATION
# ============================================================
# Store dont_use list for application AFTER design is loaded
# Cannot apply now because no design is linked yet
# ============================================================

puts "--- Cell Usage Restrictions ---"
puts ""

if {[info exists DONT_USE]} {
    puts "Don't use patterns configured: [llength $DONT_USE]"
    puts "Patterns:"
    foreach pattern $DONT_USE {
        puts "  - $pattern"
    }
    puts ""
    puts "NOTE: Will be applied after design is loaded"
    puts "      Use command: set_dont_use \$DONT_USE"
} else {
    puts "No dont_use restrictions defined"
}

puts ""

# ============================================================
# SUMMARY
# ============================================================

puts "========================================="
puts "PDK Initialization Summary"
puts "========================================="
puts "Technology:"
puts "  ✓ IHP SG13G2 (130nm)"
puts "  ✓ Corners: TT, SS, FF"
puts ""
puts "Libraries Loaded:"
puts "  ✓ Standard cells: $stdcell_loaded corners"
puts "  ✓ IO cells: $io_loaded corners"
puts "  ✓ SRAM libs: $sram_loaded files"
if {[llength $sram_cells] > 0} {
    puts "  ✓ SRAM macros: [llength $sram_cells] available"
} else {
    puts "  ⚠ SRAM macros: None found"
}
puts "  ✓ Total libraries: $lib_count"
puts ""
if {[info exists matrix_size] && [info exists input_data_width]} {
    puts "TPU Design Parameters:"
    puts "  ✓ Array: ${matrix_size}×${matrix_size} (${elements_per_matrix} MACs)"
    puts "  ✓ Input: INT${input_data_width} (${bytes_per_input_matrix} bytes/matrix)"
    puts "  ✓ Output: INT${output_data_width} (${bytes_per_output_matrix} bytes/matrix)"
    puts ""
}
puts "========================================="
puts "PDK initialization complete!"
puts "Ready for netlist read and floorplanning"
puts "========================================="
puts ""


puts "Initialization completed"