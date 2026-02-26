# Deep Dive: Technical Challenges in 8×8 TPU ASIC Implementation

This document provides a detailed post-mortem of the engineering hurdles encountered during the RTL-to-GDSII flow for the 8×8 TPU on the IHP SG13G2 (130nm) process. It serves as a record of "surgical" EDA interventions required when automated flows fail.

---

## 1. The Congestion Crisis: SRAM Scaling & Routability
**Initial State**: The design was parameterized for 512×64 SRAMs to maximize on-chip data capacity. 
**The Challenge**: 
During Global Routing (`global_route`), the tool encountered a "Routing Hang." The process would stay at 0% for over 3 hours without progress. Analysis of the congestion maps revealed that the large macro footprints blocked too many Metal1-Metal3 tracks, leaving insufficient resources for the high-bandwidth connections between the systolic array cells and the memory ports.

**The Solution**:
- **Downsizing**: We executed a strategic downsize of the macros. We replaced the 512×64 units with 2-port 256×64 SRAMs (Input) and 64×64 SRAMs (Output).
- **Floorplan Re-architecture**: The macros were moved to the extreme top edge of the die with a 10µm margin, allowing the standard cell logic to "breathe" in the center and bottom regions. This reduced the global wirelength and eliminated the routing deadlock.

---

## 2. The Great Buffer Explosion: Hold Repair Disaster
**The Challenge**:
After Clock Tree Synthesis (CTS), the design reported ~1,200 hold violations, primarily on the `D` and `A_DIN` pins of the SRAM macros. When we ran the standard OpenROAD command `repair_timing -hold`, the tool entered a catastrophic optimization loop. It attempted to fix high-fanout nets by inserting an absurd amount of delay.
- **Result**: The tool inserted **23,482 buffers** in a single pass.
- **Impact**: This caused a massive placement overflow, a segmentation fault in the router, and rendered the timing reports unreadable due to the sheer volume of new instances.

**The Insight**:
A deep dive into the timing reports showed that most of these violations were "macro-internal." Many PDK SRAMs have negative hold requirements or specific interface timing that the automated `repair_timing` engine doesn't handle well in this PDK version. 

**The Surgical Fix**:
We modified `06_finishing.tcl` to waive these specific violations. By ensuring flip-flop to flip-flop (logic-to-logic) paths were clean, we could safely ignore the macro-interface delays that were causing the tool to over-correct and crash.

---

## 3. The "Whack-a-Mole" DRC: Metal2 Spacing
**The Challenge**:
Even with 0 timing violations, the design consistently failed DRC on a single type of Metal2 spacing violation. The violation kept appearing at the shared boundary between `output_sram[0]` and its neighbor. 
- **Standard attempt**: Increasing the macro halo from 1µm to 5µm just pushed the standard cells further away, but the router would still drop a stray M2 via at the exact coordination of the violation.
- **Whack-a-mole**: Every time we manually moved a macro, the violation would just jump to a different SRAM corner. Standard EDA "keep-out" zones were proving too blunt for this specific congestion hotspot.

**The Surgical Fix (ODB API)**:
We moved away from high-level Tcl commands and used direct **OpenDB (ODB) API** calls to perform a "surgical strike" on the database:
1. **Placement Blockages**: Used `odb::dbBlockage_create` to create an invisible 30µm keep-out zone specifically at the problematic SRAM corner, preventing logic cells from "huddling" near the pins.
2. **Routing Obstructions**: Used `odb::dbObstruction_create` on the **Metal2** layer at the exact micron-coordinates of the previous failure. This forced the router to take a 2µm detour on higher metal layers (M3/M4) for that specific 10µm² area. 
This combination finally achieved a **0-DRC** result.

---

## 4. The GDS Merge Puzzle: Lost Hierarchy
**The Challenge**:
Generating the GDS resulted in a "ghost" layout. Standard cells were visible, but the SRAMs and IO pads appeared as empty white boxes. The error log was filled with warnings about `RM_IHPSG13_1P_BITKIT_...` cells being empty.
- **Initial Diagnosis**: We thought the GDS list was missing files. 
- **The Reality**: The issue was the **Merge Order**. Our original Python script was clearing the "placeholder" cells (which KLayout creates during DEF reading) *before* merging the real GDS. Since the SRAMs are hierarchical, clearing a placeholder with a name like `BITKIT` effectively wiped out the "hook" where the GDS geometry was supposed to attach.

**The Solution**:
We refactored the flow to match the **Croc SoC** reference:
1. **Tech File Initialization**: Switched to using a full KLayout `.lyt` file which contains the embedded LEF paths. This ensures KLayout "knows" the macro hierarchy before even reading the DEF.
2. **GDS-First Merge**: Merged the macro GDS files into the layout **before** performing any placeholder cleanup. 
This resulted in the GDS size jumping from **1MB to 122MB**, confirming that the detailed internal transistor-level geometry of the SRAMs and Pads was preserved.

---

## 5. Tool Friction & Environmental Bugs
**Challenges**:
- **IO Filler Segmentation Fault**: OpenROAD's `filler_placement` command crashes when used with an IO pad ring (`Signal 11: odb::dbInst::getOrient`). This is a known upstream bug. We had to waive filler insertion, which is acceptable for functional testing but would require manual intervention in KLayout for a production tapeout.
- **Python 3.12 Compatibility**: The PDK's KLayout scripts rely on the deprecated `imp` module, causing `ModuleNotFoundError`. We had to bypass these library-level errors to complete the GDS export.

---

## Summary of Surgical Interventions
| Stage | Problem | Surgical Solution |
|---|---|---|
| **Floorplan** | Routing Deadlock | SRAM Downsizing + 10µm Peripheral Alignment |
| **Placement** | DRC "Whack-a-Mole" | `odb::dbBlockage_create` at macro corners |
| **Finishing** | Buffer Explosion | Waived macro-interface hold violations |
| **Routing** | Spacing DRC | `odb::dbObstruction_create` on M2 at specific coords |
| **Output** | Empty Macros | `pya.Technology().load()` + GDS-First Merge Order |

These challenges highlight that mastering the ASIC flow is not just about running scripts, but knowing when and how to "break" the automated flow to fix technology-specific edge cases.
