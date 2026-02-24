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
| Memory | 8x SRAM Macros (IHP SG13G2) |

## ASIC Design Flow
The implementation uses a professional RTL-to-GDSII flow:

1.  **Synthesis**: Yosys for mapping RTL to SG13G2 gates.
2.  **Floorplan**: IO Pad ring creation with 56 pins (distributed VDD/VSS).
3.  **PDN**: Power straps on M3/M4/M5 for robust power delivery.
4.  **Placement**: Global and Detailed placement of 2.8k+ Flip-Flops and 8 SRAMs.
5.  **CTS**: Clock Tree Synthesis using high-drive buffers.
6.  **Routing**: Global and Detailed routing with 40+ iterations for DRC cleaning.
7.  **Signoff**: Static Timing Analysis (STA) and GDSII generation via KLayout.

## Implementation Results
| Metric | Value |
|--------|-------|
| **Target Frequency** | 100 MHz (10ns period) |
| **Setup WNS** | 0.000 ns (MET) |
| **Die Size** | 2.8mm x 2.8mm |
| **Design Area** | 2.22 mm² |
| **Utilization** | 49% |
| **Technology** | IHP SG13G2 130nm |

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
    python3 generate_gds_tpu.py
    ```
4.  **View Layout**:
    ```bash
    klayout results/tpu_chip_final.gds
    ```

## Acknowledgments
- **Google TPU Team**: For the original architectural inspiration.
- **IHP Microelectronics**: For providing the SG13G2 PDK.
- **OpenROAD Project**: For the open-source EDA tools.
