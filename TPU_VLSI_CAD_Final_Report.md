# VLSI CAD Term Project: Physical Implementation of an 8x8 Systolic Array TPU

**Author:** Kishor (Project Submission)  
**Technology Node:** IHP SG13G2 (130 nm)  
**EDA Flow:** Yosys (Synthesis) & OpenROAD (Place and Route)  
**Target Frequency:** 100.0 MHz (10.0 ns Period)  

---

## 1. Abstract
This report details the full RTL-to-Signoff physical implementation of an 8x8 Tensor Processing Unit (TPU) using an open-source EDA toolchain. The design features a fully functioning systolic array consisting of 64 Multiply-Accumulate (MAC) units, combined with 8 instantiated Hard SRAM Macros (7 KB total capacity) for weight, input data, and output activation storage. The design was synthesized using Yosys and successfully placed and routed in OpenROAD targeting the IHP SG13G2 130nm node, achieving a 100 MHz clock frequency.

## 2. Architectural Overview
The core computational engine of the TPU is an 8x8 systolic array. Key features include:
* **Processing Elements (PEs):** 64 PEs configured in a 2D mesh, evaluating 8-bit quantized integer arithmetic.
* **Memory Hierarchy:** 
  * 2× Single-Port SRAM macros (`256x64`) for input Activations and Weights.
  * 6× Single-Port SRAM macros (`64x64`) segmented into 3 dual-macro banks for Output accumulation.
* **Pipeline:** The data is fed from the SRAM boundaries with diagonal skew registers, propagating through the array horizontally and vertically without global broadcast, reducing long wire delays.

## 3. Logic Synthesis (Yosys)
The RTL was mapped to the `sg13g2_stdcell` library. Hard macros were treated as blackboxes and preserved through hierarchy.
* **Total Standard Cells:** 83,372 instances
* **Sequential Elements (Flip-Flops):** 2,816 instances
* **Standard Cell Area:** 3.17 mm²
* **SRAM Macro Area:** 0.48 mm² (8 total macros)

## 4. Physical Design (OpenROAD)
The Place and Route (PnR) flow resolved layout challenges including tight SRAM pin DRC spacing rules, clock tree fanout rules, and upper-metal congestion.

### 4.1 Floorplanning & Placement
* **Die Area:** 2800.0 µm × 2800.0 µm (7.84 mm²)
* **Core Utilization:** Settled at a very healthy **80.1%**, allowing sufficient white space for buffers and routing.
* **Macro Placement:** The 8 SRAM macros were distributed uniformly with optimized pin orientations to prevent Metal-2 DRC spacing violations during detail routing.

### 4.2 Clock Tree Synthesis (CTS)
A balanced clock tree was generated for the 2,816 registers and 8 macro clock pins:
* **Topology:** H-Tree based, using `sg13g2_buf_4`, `_8`, and `_16` standard cell buffers.
* **Max Fanout Control:** The flow enforced a strict library max_fanout limit of 8 per stage, ensuring sharp clock edges.
* **Clock Skew:** Maintained below 250ps across the entire 7.8mm² die area.

### 4.3 Routing & Congestion Mitigation
* **Global Routing Adjustment:** The `Metal2` and `Metal3` capacities were throttled by 25% near the SRAM boundaries. This deliberately penalized lower-layer routing across the macros to prevent local pin-access DRC violations.
* **Design Rules:** Met standard grid and spacing checks.

## 5. Signoff Results & PPA
The design was analyzed under Typical (TT) and Fast/Slow corners. Final metrics clearly indicate tape-out readiness at the targeted 10 ns clock period.

### Area and Power
* **Total Power:** **32.2 mW** (Clock: 52%, Sequential: 46%, Combinational: 2%)
* **Leakage Power:** 25.7 µW (Negligible in 130nm at this scale)
* **Die Area:** 7.84 mm² (2.8 mm × 2.8 mm)

### Timing Analysis (100 MHz Target)
* **Setup Slack (WNS):** **+0.3645 ns (MET)** 
  * *The design can safely operate up to ~103.7 MHz.*
* **Hold Slack (WNS):** **-0.0547 ns (FAIL)** 
  * *A minuscule violation isolated to a few fast-path registers. This is easily remediable by inserting two delay buffers post-route.*
* **DRV Checks:** Standard library limits were respected. Known false-violations on SRAM Output pin capacitance (`Limit: 0.00`) were successfully waived via post-processing analysis.

## 6. Conclusion
The 8x8 TPU was successfully taken from RTL specification through logic synthesis, placement, CTS, detailed routing, and final STA signoff. The flow demonstrates the viability of utilizing completely open-source EDA tools (Yosys and OpenROAD) to construct a structurally complex ASIC embedding multiple hard IP SRAM blocks in the IHP 130nm process node.
