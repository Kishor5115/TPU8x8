# TPU Verification Guide
# ============================================================================
#
# This directory contains the functional and physical verification suite for the 
# 8x8 TPU designed for IHP SG13G2 130nm.
#
# Directory Structure:
#
#   sym/
#   ├── pre_synth/          — RTL Simulation (Master Source)
#   │   ├── tpu_tb.v        — Unified Master Testbench (All Cases)
#   │   └── Makefile        — Flow: make sim | make wave
#   │
#   ├── post_synth/         — Gate-Level Simulation (GLS)
#   │   └── Makefile        — Uses Master TB with synthesized netlist
#   │
#   └── lvs/                — Layout vs. Schematic
#       └── README.md       — LVS flow guide (KLayout / Netgen)
#
# ============================================================================

## Simulation Flow (Functional)

The project uses a **Converged Master Testbench** ([tpu_tb.v](pre_synth/tpu_tb.v)). This ensures that the exact same math verification applies to both the RTL and the final netlist.

### 1. Pre-Synthesis (RTL)
Verify the hardware logic design before synthesis.
```bash
cd pre_synth
make clean sim    # Compile and run
make wave         # View results in GTKWave
```
*Note: This mode includes a cycle-by-cycle **MAC Trace** in `sim.log`.*

### 2. Post-Synthesis (Gate-Level)
Verify the finalized routed netlist (silicon-equivalent) against the golden model.
```bash
cd post_synth
make clean sim    # Run Gate-level simulation
```

## Physical Verification (LVS)

To verify that the drafted layout matches the design schematic:
```bash
cd lvs
# Follow the instructions in lvs/README.md
```

## Tools Required
- **Icarus Verilog**: Dual-mode simulation ([env.sh](../env.sh) sets this up).
- **GTKWave**: Waveform viewing.
- **KLayout / Netgen**: Physical verification.
