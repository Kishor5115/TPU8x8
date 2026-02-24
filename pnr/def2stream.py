import pya
import re
import json
import copy
import sys
import os

print("[DEBUG] def2stream.py script started")

# Parameters from globals (passed via -rd)
# design_name, in_def, gds_flist, lef_flist, out_file, layer_map

errors = 0

# 1. Setup LoadLayoutOptions
layoutOptions = pya.LoadLayoutOptions()

# 2. Setup Layer Map (Must be absolute path)
if 'layer_map' in globals() and layer_map != "":
    print(f"[INFO] Using layer map: {layer_map}")
    layoutOptions.lefdef_config.map_file = layer_map

# 3. Load LEF files (Crucial for VIA definitions)
# Use lef_flist if available
if 'lef_flist' in globals() and os.path.exists(lef_flist):
    print(f"[INFO] Reading LEF list: {lef_flist}")
    with open(lef_flist, 'r') as f:
        lefs = f.read().splitlines()
    for l in lefs:
        if l.strip() != "" and os.path.exists(l):
            print(f"\t{l}")
            layoutOptions.lefdef_config.lef_files.append(l)
        elif l.strip() != "":
            print(f"\t[WARNING] LEF not found: {l}")
elif 'lef_files' in globals() and len(lef_files) > 0:
    # Fallback to space-separated string
    print("[INFO] Reading LEFs from string ...")
    for f in lef_files.split():
        if os.path.exists(f):
            print(f"\t{f}")
            layoutOptions.lefdef_config.lef_files.append(f)

# 4. Load DEF file
main_layout = pya.Layout()
print(f"[INFO] Reading DEF: {in_def}")
if os.path.exists(in_def):
    try:
        main_layout.read(in_def, layoutOptions)
    except Exception as e:
        print(f"[ERROR] Failed to read DEF: {e}")
        sys.exit(1)
else:
    print(f"[ERROR] DEF file not found: {in_def}")
    sys.exit(1)

# 5. Determine Top Cell
if 'design_name' not in globals() or design_name == "":
    top_cell = main_layout.top_cell()
    design_name = top_cell.name
    top_cell_index = top_cell.cell_index()
    print(f"[INFO] design_name not provided. Using top cell: {design_name}")
else:
    top_cell = main_layout.cell(design_name)
    if top_cell is None:
        print(f"[ERROR] Top cell '{design_name}' not found in DEF!")
        # Print available cells for debugging
        print("[INFO] Available cells (first 10):")
        count = 0
        for i in main_layout.each_cell():
            print(f"\t{i.name}")
            count += 1
            if count > 10: break
        sys.exit(1)
    top_cell_index = top_cell.cell_index()

# 6. Clear placeholders (but keep VIAs)
print("[INFO] Clearing placeholder cells...")
for i in main_layout.each_cell():
    if i.cell_index() != top_cell_index:
        if not (i.name.startswith("VIA_") or i.name.startswith("Via")):
            i.clear()

# 7. Merge GDS files
print("[INFO] Merging GDS files...")
if 'gds_flist' in globals() and os.path.exists(gds_flist):
    with open(gds_flist, 'r') as file:
        gds_files = file.read().splitlines()
    for fil in gds_files:
        if fil.strip() != "":
            if os.path.exists(fil):
                print(f"\t{fil}")
                main_layout.read(fil)
            else:
                print(f"\t[WARNING] GDS file not found: {fil}")

# 8. Copy top level and verify
print(f"[INFO] Copying toplevel cell '{design_name}'")
top_only_layout = pya.Layout()
top_only_layout.dbu = main_layout.dbu
top = top_only_layout.create_cell(design_name)
top.copy_tree(main_layout.cell(design_name))

print("[INFO] Verifying cell merge...")
missing_cell = False
for i in top_only_layout.each_cell():
    if i.is_empty():
        if not (i.name.startswith("VIA_") or i.name.startswith("Via")):
            print(f"[ERROR] Cell '{i.name}' is empty after merge!")
            missing_cell = True
            errors += 1

if not missing_cell:
    print("[INFO] All cells merged successfully")

# 9. Write out the GDS
print(f"[INFO] Writing final GDS: {out_file}")
top_only_layout.write(out_file)

print("[INFO] def2stream.py completed")
sys.exit(errors)
