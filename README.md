# 8x8 TPU ASIC Implementation (IHP 130nm)

A high-performance 8x8 Systolic Array TPU designed for matrix multiplication, implemented as a complete ASIC flow targeting the **IHP SG13G2 130nm** technology.

![Final Routed Layout](pnr/reports/signoff/layout_final.png)

## Overview
This project implement an 8x8 matrix multiplication accelerator (TPU) from RTL to GDSII. It features a systolic array architecture optimized for throughput, integrated with high-density SRAM macros for weight and data storage.

### Key Features
- **8x8 Systolic Array**: 64 Multiply-Accumulate (MAC) units working in parallel.
- **SRAM-Based Memory**: Dedicated SRAM macros for Weights, Data, and Accumulators.
- **ASIC Technology**: Targetted at IHP SG13G2 130nm Open PDK.
- **Automated PnR Flow**: Complete OpenROAD-based physical design flow with automated signoff and GDS generation.

## Architecture

The TPU performs matrix multiplication $C = D \times W^T$, where $D$ is the Data matrix and $W$ is the Weight matrix. This corresponds to the mathematical operation:
$C[i][j] = \sum_{k=0}^{7} D[i][k] \times W[j][k]$

### Data Flow
- **Systolic Array Type**: Output-Stationary. Each cell `(i,j)` contains an accumulator that stores the final results $C[i][j]$.
- **Weights ($W$)**: Enter from the top and flow down through rows.
- **Data ($D$)**: Enter from the left and flow right across columns.

### Input Skewing
To ensure correct time-alignment of partial products, inputs must be fed into the SRAMs with **diagonal skewing**:
- Row `i` of the Data matrix is delayed by `i` cycles.
- Row `i` of the Weight matrix is delayed by `i` cycles.
- For this specific implementation (using a single SRAM address for 4-row groups), the second group (rows 4-7) requires an additional 4-cycle offset to account for the integrated memory architecture.

Rendered results are stored in **anti-diagonal order** in the output SRAMs.

| Component | Specification |
|-----------|---------------|
| Array Size | 8x8 (64 MACs) |
| Data Width | 8-bit (INT8) |
| Accumulator | 16-bit (INT16) |
| Clock Domain | Single System Clock (50 MHz) |
| Memory | 2x RM_IHPSG13_1P_256x64 (Weights/Input) |
|        | 6x RM_IHPSG13_1P_64x64 (Output/Output Channels) |

## ASIC Design Flow
The implementation uses a professional RTL-to-GDSII flow:

1.  **Synthesis**: Yosys for mapping RTL to SG13G2 gates.
2.  **Floorplan**: IO Pad ring creation with customized power distribution.
3.  **PDN**: Power straps on M3/M4/M5 for robust power delivery.
4.  **Placement**: Surgical placement blockages near SRAM macro corners.
5.  **CTS**: Clock Tree Synthesis using high-drive buffers.
6.  **Routing**: Surgical Metal2 routing blockages to resolve spacing violations.
7.  **Signoff**: Comprehensive timing, power, and area analysis with automated report generation.

## Implementation Results (PPA)

### Performance
| Metric | Value |
|--------|-------|
| Target Frequency | 50 MHz (20 ns period) |
| Setup Timing (WNS) | 0.000 ns ✅ PASS |
| Hold Timing (WNS) | -0.002 ns ⚠️ FAIL |
| Estimated Max Freq | ~87 MHz |

### Power (Typical Corner: 1.20V, 25°C)
| Component | Internal | Switching | Leakage | Total | % |
|-----------|----------|-----------|---------|-------|---|
| Sequential | 7.52 mW | 0.00 mW | 1.30 µW | 7.52 mW | 49.5% |
| Combinational | 0.03 mW | 0.06 mW | 13.0 µW | 0.10 mW | 0.7% |
| Clock | 5.94 mW | 1.64 mW | 1.12 µW | 7.58 mW | 49.8% |
| Macro (SRAM) | — | — | 0.69 µW | 0.00 mW | 0.0% |
| **Total** | **13.5 mW** | **1.70 mW** | **16.1 µW** | **15.2 mW** | **100%** |

### Area
| Metric | Value |
|--------|-------|
| Die Size | 2.8 mm × 2.8 mm (7.84 mm²) |
| Core Area | 4.57 mm² |
| Std Cell Area | 3.08 mm² (100,283 instances) |
| Macro Area | 0.49 mm² (8 SRAM instances) |
| Core Utilization | 78.1% |
| Std Cell Utilization | 75.4% |
| Technology | IHP SG13G2 130nm |
| GDS Size | ~127 MB |

## Simulation (Functional Verification)

The project includes a master testbench for verifying matrix multiplication accuracy. See [VERIFICATION.md](sym/VERIFICATION.md) for a detailed guide.

1.  **RTL Simulation (Pre-Synthesis)**:
    ```bash
    cd sym/pre_synth
    make sim
    ```
    This verifies the hardware logic and provides a cycle-by-cycle **MAC Trace** for debugging internal math.

2.  **Gate-Level Simulation (Post-Synthesis)**:
    ```bash
    cd sym/post_synth
    make sim
    ```
    This verifies the final routed netlist against the same golden model.

## View Signoff Reports
All reports are located in `pnr/reports/signoff/`:

| Report | File | Description |
|--------|------|-------------|
| Timing | `timing_final.rpt` | Setup/Hold path analysis |
| Area | `area.rpt` | Die, core, stdcell, macro area |
| Power | `power.rpt` | Power breakdown by component |
| Violations | `violations.rpt` | DRV violations with counts |
| Clock Skew | `clock_skew.rpt` | Clock network skew |
| Summary | `summary.rpt` | Professional signoff summary |

## Getting Started
To run the automated physical design flow:

1.  **Setup Environment**: Ensure OpenROAD, Yosys, and KLayout are in your PATH. Configure the PDK path in `pnr/config.tcl`.
2.  **Run PN&R**:
    ```bash
    cd pnr
    openroad flow.tcl
    ```
3.  **Generate GDS**:
    ```bash
    cd pnr/klayout
    bash def2gds.sh
    ```
4.  **View Layout**:
    ```bash
    klayout pnr/results/tpu_chip_final.gds
    ```

## Development History
See [CHALLENGES.md](/docs/CHALLENGES.md) for a detailed log of technical hurdles, including SRAM downsizing, hold violation repair, and surgical DRC fixes.

## Acknowledgments
- **Google TPU Team**: For architectural inspiration.
- **IHP Microelectronics**: For the SG13G2 Open PDK.
- **OpenROAD Project**: For open-source EDA tools.
