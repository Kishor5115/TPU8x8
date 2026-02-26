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
The TPU performs matrix multiplication $C = A \times B$, where $A$ is the weight matrix and $B$ is the data matrix.
- **Weights** are loaded into the array and stored locally in each cell's weight register.
- **Data** flows through the array from left to right.
- **Partial Results** accumulate within each cell and are eventually shifted out to memory.

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
