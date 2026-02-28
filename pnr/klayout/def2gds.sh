#!/bin/bash
# =========================================================
# def2gds.sh — DEF to GDS conversion for 8×8 TPU
# Based on Croc SoC reference: klayout/def2gds.sh
# =========================================================

set -e

export KLAYOUT=${KLAYOUT:-klayout}

# This directory
script_dir=$(realpath $(dirname "${BASH_SOURCE[0]}"))
cd "$script_dir"

################
### project  ###
################
top_design="tpu_chip"
def_path="$(realpath ../results/${top_design}_final.def)"

################
## technology ##
################
pdk_dir=$(realpath "../../ihp13/pdk/ihp-sg13g2")
tech="$pdk_dir/libs.tech/klayout/tech/sg13g2.lyt"

# Create a local klayout home and add PDK to path
export KLAYOUT_HOME="$script_dir/.klayout"
export KLAYOUT_PATH="$(realpath $pdk_dir/libs.tech/klayout):$KLAYOUT_PATH"
mkdir -p "$KLAYOUT_HOME/tech"

################
## LEF files  ##
################
pdk_cells_lef_dir="$pdk_dir/libs.ref/sg13g2_stdcell/lef"
pdk_sram_lef_dir="$pdk_dir/libs.ref/sg13g2_sram/lef"
pdk_io_lef_dir="$pdk_dir/libs.ref/sg13g2_io/lef"

lef="$(find "$pdk_cells_lef_dir" -name 'sg13g2_stdcell.lef' -exec realpath {} \;) \
     $(find "$pdk_cells_lef_dir" -name 'sg13g2_tech.lef' -exec realpath {} \;) \
     $(find "$pdk_sram_lef_dir" -name 'RM_IHPSG13*.lef' -exec realpath {} \;) \
     $(find "$pdk_io_lef_dir" -name 'sg13g2_io.lef' -exec realpath {} \;)"

################
## GDS files  ##
################
pdk_cells_gds_dir="$pdk_dir/libs.ref/sg13g2_stdcell/gds"
pdk_sram_gds_dir="$pdk_dir/libs.ref/sg13g2_sram/gds"
pdk_io_gds_dir="$pdk_dir/libs.ref/sg13g2_io/gds"
pdk_pad_gds_dir="$(realpath "../../ihp13/bondpad/gds")"

gds="$(find "$pdk_cells_gds_dir" -name 'sg13g2_stdcell.gds' -exec realpath {} \;) \
     $(find "$pdk_sram_gds_dir" -name 'RM_IHPSG13*.gds' -exec realpath {} \;) \
     $(find "$pdk_io_gds_dir" -name 'sg13g2_io.gds' -exec realpath {} \;) \
     $(find "$pdk_pad_gds_dir" -name 'bondpad_70x70.gds' -exec realpath {} \;)"

################
## Setup      ##
################

# Symlink layer map
ln -sfr "$script_dir/sg13g2.map" "$KLAYOUT_HOME/tech/sg13g2.map"

# Build <lef-files> entries for the tech file
lef_files=""
for lef_file in $lef; do
    lef_files+="<lef-files>$lef_file</lef-files>\n"
done

# Replace the placeholder tag with the real LEF files
sed "/<lef-files><\/lef-files>/c $lef_files" "$tech" > "$KLAYOUT_HOME/tech/sg13g2.lyt"

# Write GDS file list
echo "$gds" > "$KLAYOUT_HOME/tech/tech_gds.f"

################
## Run KLayout #
################
echo ""
echo "========================================="
echo "  DEF → GDS: $top_design"
echo "========================================="
echo "  DEF:  $def_path"
echo "  Tech: $KLAYOUT_HOME/tech/sg13g2.lyt"
echo "  Out:  ../results/${top_design}_final.gds"
echo "========================================="
echo ""

klayout_cmd="$KLAYOUT -zz \
          -rd design_name=\"$top_design\" \
          -rd in_def=\"$def_path\" \
          -rd gds_flist=\"$KLAYOUT_HOME/tech/tech_gds.f\" \
          -rd out_file=\"../results/${top_design}_final.gds\" \
          -rd tech_file=\"$KLAYOUT_HOME/tech/sg13g2.lyt\" \
          -rd layer_map=\"$KLAYOUT_HOME/tech/sg13g2.map\" \
          -rm def2stream.py"

echo "$klayout_cmd"
eval $klayout_cmd

echo ""
if [ -f "../results/${top_design}_final.gds" ]; then
    size=$(du -h "../results/${top_design}_final.gds" | cut -f1)
    echo "[SUCCESS] GDS generated: ../results/${top_design}_final.gds ($size)"
else
    echo "[FAILED] GDS generation failed"
    exit 1
fi
