#!/usr/bin/env python3
# =========================================================
# TPU GDSII Generation Script (Robust Version)
# =========================================================

import os
import sys
import glob
import subprocess

# DESIGN setting - matches DESIGN in DEF file
DESIGN = "tpu_chip"

# Paths
PDK_DIR = os.path.abspath("../ihp13/pdk/ihp-sg13g2")
RESULTS_DIR = "results"
DEF_FILE = os.path.abspath(os.path.join(RESULTS_DIR, f"{DESIGN}_final.def"))
OUTPUT_GDS = os.path.abspath(os.path.join(RESULTS_DIR, f"{DESIGN}_final.gds"))
LAYER_MAP = os.path.abspath("sg13g2.map")

# PDK Subdirectories
STD_DIR = os.path.join(PDK_DIR, "libs.ref/sg13g2_stdcell")
IO_DIR = os.path.join(PDK_DIR, "libs.ref/sg13g2_io")
SRAM_DIR = os.path.join(PDK_DIR, "libs.ref/sg13g2_sram")

def main():
    print("=" * 60)
    print("  TPU GDSII Generation Flow")
    print("=" * 60)

    # 1. Collect LEF files
    lef_files = []
    lef_files.append(os.path.join(STD_DIR, "lef/sg13g2_tech.lef"))
    lef_files.append(os.path.join(STD_DIR, "lef/sg13g2_stdcell.lef"))
    lef_files.append(os.path.join(IO_DIR, "lef/sg13g2_io.lef"))
    sram_lefs = glob.glob(os.path.join(SRAM_DIR, "lef/*.lef"))
    lef_files.extend(sram_lefs)

    # Filter existing LEFs
    lef_files = [os.path.abspath(f) for f in lef_files if os.path.exists(f)]

    # Write LEF list
    lef_flist = "lef_list.f"
    with open(lef_flist, "w") as f:
        for l in lef_files:
            f.write(l + "\n")

    # 2. Collect GDS files
    gds_files = []
    gds_files.append(os.path.join(STD_DIR, "gds/sg13g2_stdcell.gds"))
    gds_files.append(os.path.join(IO_DIR, "gds/sg13g2_io.gds"))
    sram_gds = glob.glob(os.path.join(SRAM_DIR, "gds/*.gds"))
    gds_files.extend(sram_gds)

    # 3. Create GDS file list
    gds_flist = "gds_list.f"
    with open(gds_flist, "w") as f:
        for g in gds_files:
            if os.path.exists(g):
                f.write(os.path.abspath(g) + "\n")

    # 4. Check for DEF file
    if not os.path.exists(DEF_FILE):
        print(f"[ERROR] DEF file not found: {DEF_FILE}")
        sys.exit(1)

    # 5. Execute KLayout
    # We use -rd lef_flist instead of long lef_files string
    klayout_cmd = [
        "klayout", "-zz",
        "-rd", f"design_name={DESIGN}",
        "-rd", f"in_def={DEF_FILE}",
        "-rd", f"gds_flist={os.path.abspath(gds_flist)}",
        "-rd", f"lef_flist={os.path.abspath(lef_flist)}",
        "-rd", f"out_file={OUTPUT_GDS}",
        "-rd", f"layer_map={LAYER_MAP}",
        "-rm", "def2stream.py"
    ]

    print(f"\n[INFO] Executing KLayout...")
    process = subprocess.Popen(klayout_cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    
    for line in process.stdout:
        print(f"KLayout: {line.strip()}")
    
    process.wait()

    if process.returncode != 0:
        print(f"\n[ERROR] KLayout exited with code {process.returncode}")

    if os.path.exists(OUTPUT_GDS):
        size = os.path.getsize(OUTPUT_GDS) / (1024*1024)
        print(f"\n[SUCCESS] Final GDS generated: {OUTPUT_GDS} ({size:.2f} MB)")
    else:
        print("\n[FAILED] GDS generation failed.")

    print("=" * 60)

if __name__ == "__main__":
    main()
