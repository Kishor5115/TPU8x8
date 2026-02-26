# TPU Simulation Environment
# ============================================================================
#
# Directory Structure:
#
#   simulation/
#   ├── pre_synth/          — RTL-level functional simulation
#   │   ├── tpu_tb.v        — Pre-synthesis testbench (4 test cases)
#   │   └── Makefile         — Compile & run with Icarus Verilog
#   │
#   ├── post_synth/         — Gate-level simulation with synthesized netlist
#   │   ├── tpu_post_synth_tb.v  — Post-synthesis testbench
#   │   └── Makefile              — Compile & run with PDK cell libraries
#   │
#   └── lvs/                — Layout vs. Schematic verification
#       └── README.md        — LVS flow guide (KLayout / Netgen)
#
# ============================================================================

## Quick Start

### Pre-Synthesis Simulation
```bash
cd pre_synth
make          # Compile and run
make wave     # Open waveform viewer
```

### Post-Synthesis Simulation
```bash
cd post_synth
make          # Compile and run gate-level sim
make wave     # Open waveform viewer
```

### LVS
```bash
cd lvs
# Follow instructions in README.md
```

## Requirements

- **Icarus Verilog** (`iverilog`, `vvp`) for simulation
- **GTKWave** for waveform viewing (optional)
- **IHP SG13G2 PDK** with behavioral SRAM models
- **KLayout** or **Netgen** for LVS verification
