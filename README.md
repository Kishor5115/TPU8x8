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
| Clock Domain | Single System Clock (100 MHz) |
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
7.  **Signoff**: 0.000ns slack achieved (Setup/Hold) and GDSII generation via KLayout.

## Implementation Results
| Metric | Value |
|--------|-------|
| **Target Frequency** | 100 MHz (10ns period) |
| **Logic Slack** | 0.000 ns (MET) |
| **Die Size** | 2.1mm x 2.1mm |
| **Technology** | IHP SG13G2 130nm |
| **GDS Size** | 122 MB |

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
See [CHALLENGES.md](CHALLENGES.md) for a detailed log of technical hurdles, including SRAM downsizing, hold violation repair, and surgical DRC fixes.

## Acknowledgments
- **Google TPU Team**: For architectural inspiration.
- **IHP Microelectronics**: For the SG13G2 Open PDK.
- **OpenROAD Project**: For open-source EDA tools.
