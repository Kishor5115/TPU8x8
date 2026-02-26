# LVS (Layout vs. Schematic) — IHP SG13G2 130nm
# ============================================================================
#
# LVS verifies that the final GDS layout matches the synthesized netlist.
#
# Tool Options:
#   1. KLayout LVS (built-in, uses IHP PDK rule deck)
#   2. Netgen (open-source LVS from efabless/OpenROAD ecosystem)
#
# ============================================================================

## Prerequisites

- **GDS file**: `pnr/klayout/tpu_chip.gds` (or generated via `def2gds.sh`)
- **Gate-level netlist**: `pnr/results/tpu_chip_final.v`
- **PDK LVS rules**: IHP SG13G2 KLayout LVS rule deck

## Using KLayout LVS

```bash
# Run KLayout LVS with IHP PDK rule deck
klayout -b -r <path-to-ihp-lvs-rules>/sg13g2_lvs.lylvs \
    -rd input=../../pnr/klayout/tpu_chip.gds \
    -rd schematic=../../pnr/results/tpu_chip_final.v \
    -rd report=lvs_report.txt
```

## Using Netgen

```bash
# Extract SPICE netlist from GDS using magic
magic -dnull -noconsole << EOF
gds read ../../pnr/klayout/tpu_chip.gds
load tpu_chip
extract all
ext2spice lvs
ext2spice
quit
EOF

# Run LVS comparison
netgen -batch lvs "tpu_chip.spice tpu_chip" \
    "../../pnr/results/tpu_chip_final.v tpu_chip" \
    <pdk_setup_file> lvs_report.txt
```

## Output

The LVS report will indicate:
- **MATCH**: Layout matches schematic — chip is LVS clean
- **MISMATCH**: Differences found — review the report for details

## Notes

- LVS requires the complete PDK installation with extraction rules
- SRAM macros are typically treated as black boxes in LVS
- Ensure power/ground nets (VDD, VSS) are properly connected
- IO pad cells must be included in both netlist and layout
