# PNR Script Commands Reference

Comprehensive guide to all OpenROAD commands used in the 8×8 TPU P&R flow with detailed switches and examples.

---

## Stage 0: Design Initialization (00_init.tcl)

### read_verilog
**Purpose:** Read synthesized Verilog netlist and load into database
```tcl
read_verilog $VERILOG_FILE
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<file>` | Required | Path to Verilog file | `../yosys/work/tpu_chip.v` |

---

### link_design
**Purpose:** Link design hierarchy and elaborate modules
```tcl
link_design $DESIGN
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<design_name>` | Required | Top-level module name | `tpu_chip` |

---

### set_dont_use
**Purpose:** Prevent OpenROAD from using specific cells (e.g., slow buffers)
```tcl
foreach pattern $DONT_USE {
    set_dont_use $pattern
}
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<pattern>` | Required | Cell pattern (glob) | `sg13g2_buf_1` |
| Optional: Multiple calls stack | — | Each call adds to dont_use list | — |

---

### read_sdc
**Purpose:** Read timing constraints in SDC format
```tcl
read_sdc $SDC_FILE
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<file>` | Required | SDC constraint file | `../yosys/work/tpu_chip.sdc` |

---

### create_clock
**Purpose:** Create clock constraint on port
```tcl
create_clock -name $CLK_PORT -period $CLK_PERIOD [get_ports $CLK_PORT]
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-name <name>` | Required | Clock name | `clk_pad` |
| `-period <ns>` | Required | Period in nanoseconds | `20.0` (50 MHz) |
| `<port>` | Required | Port object | `[get_ports clk_pad]` |

---

### set_clock_uncertainty
**Purpose:** Set clock jitter and skew budget
```tcl
set_clock_uncertainty $CLK_UNCERTAINTY [get_clocks $CLK_PORT]
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<ns>` | Required | Uncertainty in nanoseconds | `0.3` (1.5% of 20ns) |
| `<clock>` | Required | Clock object | `[get_clocks clk_pad]` |

---

### get_cells
**Purpose:** Query cells from design with filtering
```tcl
set sram_insts [get_cells -hierarchical * -filter {ref_name =~ RM_IHPSG13_1P_.*} -quiet]
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-hierarchical` | Optional | Include instances in hierarchies | Always used |
| `*` | Required | Match all cells | `*` or `u_tpu_core/*` |
| `-filter {<expr>}` | Optional | TCL filter expression | `ref_name =~ RM_IHPSG13_1P_.*` |
| `-quiet` | Optional | Suppress warnings | Used for optional queries |
| Filters: `ref_name =~` | — | Master name regex match | `RM_IHPSG13_1P_64x64.*` |
| Filters: `ref_name =~` | — | Wildcard master patterns | `sg13g2_buf*` |

---

### get_nets
**Purpose:** Query all nets in design
```tcl
set all_nets [get_nets -hierarchical * -quiet]
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-hierarchical` | Optional | Include nets in hierarchy | Always used |
| `*` | Required | Match all nets | `*` |
| `-quiet` | Optional | Suppress warnings | — |

---

### get_ports
**Purpose:** Query top-level ports with optional filtering
```tcl
set input_ports [get_ports -filter {direction == input} -quiet]
set all_ports [get_ports * -quiet]
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `*` or `<name>` | Required | Port pattern | `*` or `clk_pad` |
| `-filter {<expr>}` | Optional | Filter by attribute | `direction == input` |
| Filters: `direction ==` | — | Port direction | `input`, `output`, `inout` |
| `-quiet` | Optional | Suppress warnings | — |

---

### write_db
**Purpose:** Save OpenROAD database checkpoint (binary format)
```tcl
write_db $checkpoint
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<file>` | Required | ODB filename (.odb) | `results/00_init.odb` |

---

---

## Stage 1: Floorplan & IO Setup (01_floorplan.tcl)

### Overview
This stage initializes the chip floorplan and places IO ring for wire bonding:
- **Core area & die boundary** definition
- **IO pad placement** (clock, reset, data, power) on all 4 edges
- **Corner cells** at die corners
- **IO filler cells** to complete ring
- **Bondpad placement** on top of IO cells for wire bonding
- **SRAM macro placement** (weight, data, output banks)
- **Placement blockages** to protect SRAM macros from logic cell expansion

---

### initialize_floorplan
**Purpose:** Initialize die and core area boundaries
```tcl
initialize_floorplan \
    -die_area "0 0 $DIE_WIDTH $DIE_HEIGHT" \
    -core_area "$core_lx $core_ly $core_ux $core_uy" \
    -site CoreSite
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-die_area "<x1 y1 x2 y2>"` | Required | Die boundary (lower-left, upper-right) | `"0 0 3000 3000"` |
| `-core_area "<x1 y1 x2 y2>"` | Required | Core area (inside die with margins) | `"100 100 2900 2900"` |
| `-site <name>` | Required | Site type name from PDK | `CoreSite` |
| Format: Coordinates | — | All in µm, integers or floats | — |

---

### make_io_sites
**Purpose:** Configure IO cell sites for pad placement
```tcl
make_io_sites -horizontal_site sg13g2_ioSite \
    -vertical_site sg13g2_ioSite \
    -corner_site sg13g2_ioSite \
    -offset $padBond \
    -rotation_horizontal R0 \
    -rotation_vertical R0 \
    -rotation_corner R0
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-horizontal_site <name>` | Required | IO site for EAST/WEST edges | `sg13g2_ioSite` |
| `-vertical_site <name>` | Required | IO site for NORTH/SOUTH edges | `sg13g2_ioSite` |
| `-corner_site <name>` | Required | IO site for corners (4) | `sg13g2_ioSite` |
| `-offset <um>` | Required | Distance from die edge to pads | `70.0` |
| `-rotation_horizontal <R0|R90|...>` | Optional | Rotation for horizontal pads | `R0` (no rotation) |
| `-rotation_vertical <R0|R90|...>` | Optional | Rotation for vertical pads | `R0` |
| `-rotation_corner <R0|R90|...>` | Optional | Rotation for corner pads | `R0` |

---

### place_pad
**Purpose:** Place IO pad on the ring
```tcl
place_pad -row IO_WEST -location [expr {$mid_y - $spacing}] pad_clk
place_pad -row IO_NORTH -location [expr {$mid_x - $spacing}] pad_vdd_core_n
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-row <IO_NORTH\|IO_SOUTH\|IO_EAST\|IO_WEST>` | Required | Which edge to place on | `IO_WEST` |
| `-location <um>` | Required | Position along edge | `[expr {$mid_y - $spacing}]` → `1400.0` |
| `<pad_name>` | Required | Pad instance name | `pad_clk`, `pad_vdd_core_n` |

---

### place_bondpad
**Purpose:** Place wire-bonding pads on top of IO pad cells
```tcl
place_bondpad -bond bondpad_70x70 -offset {5.0 -70.0} pad_*
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-bond <cell>` | Required | Bondpad cell from PDK | `bondpad_70x70` |
| `-offset {x y}` | Required | Offset (µm) from pad center | `{5.0 -70.0}` (x, y relative) |
| `<pad_pattern>` | Required | Pad instance name pattern (glob) | `pad_*` (all pads), `pad_vdd*` |
| **Note:** | — | Bondpads overlay IO pads for wire bonding | — |

---

### remove_io_rows
**Purpose:** Delete temporary IO site rows after layout is complete
```tcl
remove_io_rows
```
| Parameter | Description |
|-----------|-------------|
| (none) | Cleans up temporary IO rows used during placement and routing |

---

### Note: place_pin Removed
⚠ **Deprecated:** The `place_pin` command has been removed from this flow.

**Reason:** IO pad cells (`sg13g2_IOPad`) in the IHP 130nm PDK already provide physical pins for top-level ports. Calling `place_pin` creates duplicate pins on the same terminal, causing a **DRT-0302 error** ("Unsupported multiple pins on bterm") during detailed routing.

**Previous behavior:** `place_pin` was used to explicitly locate logical port pins on die edges.  
**Current behavior:** Physical pins are now implicitly created by IO pad cell geometry.

---

### place_corners
**Purpose:** Place corner filler cells at all 4 die corners to complete IO ring
```tcl
place_corners "sg13g2_Corner"
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<cell_name>` | Required | Corner filler cell from PDK | `sg13g2_Corner` |
| **Note:** | — | Automatically orients cell correctly for each corner | — |

---

### place_io_fill
**Purpose:** Insert IO filler cells on specified edge to complete IO ring without gaps
```tcl
set iofill {sg13g2_Filler10000 sg13g2_Filler4000 sg13g2_Filler2000 sg13g2_Filler1000 sg13g2_Filler400 sg13g2_Filler200}
place_io_fill -row IO_NORTH {*}$iofill
place_io_fill -row IO_SOUTH {*}$iofill
place_io_fill -row IO_WEST  {*}$iofill
place_io_fill -row IO_EAST  {*}$iofill
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-row <IO_*>` | Required | Edge to fill | `IO_NORTH`, `IO_SOUTH`, `IO_EAST`, `IO_WEST` |
| `<cells...>` | Required | Filler cell list (largest→smallest for optimal packing) | `sg13g2_Filler10000 sg13g2_Filler4000 ...` |
| Note: Use `{*}$var` | — | Expand list with `{*}` prefix (TCL syntax) | — |
| **Purpose:** | — | Gaps between IO pads are filled with appropriately-sized fillers to maintain aspect ratio | — |

---

### makeTracks
**Purpose:** Create routing grid tracks on core boundary
```tcl
makeTracks
```
| Parameter | Description |
|-----------|-------------|
| (none) | Generates metal tracks based on tech rules and initialized floorplan |

---

### connect_by_abutment
**Purpose:** Connect abutting IO pads electrically (VSS/VDD cross pads)
```tcl
connect_by_abutment
```
| Parameter | Description |
|-----------|-------------|
| (none) | Merges connected VSS/VDD nets from adjacent pads |

---

### getMacroDimensions
**Purpose:** Get physical dimensions of hard macro
```tcl
set sram_256_dims [getMacroDimensions "RM_IHPSG13_1P_256x64_c2_bm_bist"]
set sram_256_w [lindex $sram_256_dims 0]
set sram_256_h [lindex $sram_256_dims 1]
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<cell_name>` | Required | SRAM macro name from PDK | `RM_IHPSG13_1P_256x64_c2_bm_bist` |
| **Returns:** List | `{width height}` in µm | `{600.48 530.76}` |

---

### placeInstance
**Purpose:** Place hard macro at absolute coordinates
```tcl
placeInstance "u_tpu_top/u_sram_weight" $wx $wy R0
placeInstance "u_tpu_top/u_sram_data" $dx $wy R0
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<inst_name>` | Required | Hierarchical instance path | `u_tpu_top/u_sram_weight` |
| `<x>` | Required | X coordinate (snapped to grid) | `605.76` |
| `<y>` | Required | Y coordinate (snapped to grid) | `2332.26` |
| `<orient>` | Required | Orientation | `R0` (0°), `R90`, `R180`, `R270`, `MX`, `MY` |

---

### ord::dbBlockage_create
**Purpose:** Create placement blockage to keep logic cells away from SRAMs
```tcl
odb::dbBlockage_create $block [expr {$xmin - $halo_dbu}] $ymin $xmin $ymax
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `$block` | Required | Design block from `ord::get_db_block` | `[ord::get_db_block]` |
| `<x1>` | Required | Lower-left X (DBU) | `[ord::microns_to_dbu 600]` |
| `<y1>` | Required | Lower-left Y (DBU) | `[ord::microns_to_dbu 2220]` |
| `<x2>` | Required | Upper-right X (DBU) | `[ord::microns_to_dbu 620]` |
| `<y2>` | Required | Upper-right Y (DBU) | `[ord::microns_to_dbu 2245]` |
| Note: Convert µm to DBU | — | Use `ord::microns_to_dbu <um>` | — |

---

---

## Stage 2: Power Distribution Network (02_pdn.tcl)

### read_db
**Purpose:** Load existing OpenROAD checkpoint
```tcl
read_db ${RESULT_DIR}/01_floorplan.odb
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<file>` | Required | ODB checkpoint path | `results/01_floorplan.odb` |

---

### add_global_connection
**Purpose:** Map power pins to global VDD/VSS nets
```tcl
add_global_connection -net {VDD} -inst_pattern {.*} -pin_pattern {VDD} -power
add_global_connection -net {VSS} -inst_pattern {.*} -pin_pattern {VSS} -ground
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-net <name>` | Required | Global net to connect to | `VDD`, `VSS` |
| `-inst_pattern <regex>` | Required | Instance pattern (regex) | `.*` (all), `RM_IHPSG13*` (SRAMs) |
| `-pin_pattern <name>` | Required | Pin name pattern | `VDD`, `VDD!`, `VDDARRAY!`, `vdd`, `iovdd` |
| `-power` | Conditional | Mark as power (use with VDD) | — |
| `-ground` | Conditional | Mark as ground (use with VSS) | — |

---

### global_connect
**Purpose:** Execute all global connection mappings
```tcl
global_connect
```
| Parameter | Description |
|-----------|-------------|
| (none) | Connects all matched pins based on add_global_connection rules |

---

### set_voltage_domain
**Purpose:** Define voltage domain (power island)
```tcl
set_voltage_domain -name {CORE} -power {VDD} -ground {VSS}
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-name <name>` | Required | Domain identifier | `CORE`, `IO`, `ANALOG` |
| `-power <net>` | Required | Power net name | `VDD` |
| `-ground <net>` | Required | Ground net name | `VSS` |

---

### define_pdn_grid
**Purpose:** Create PDN grid structure for voltage domain
```tcl
define_pdn_grid -name {core_grid} -voltage_domains {CORE}
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-name <name>` | Required | Grid name (arbitrary) | `core_grid` |
| `-voltage_domains <list>` | Required | Domains to include | `{CORE}` or `{CORE IO}` |

---

### add_pdn_stripe
**Purpose:** Add power stripe on specified metal layer
```tcl
add_pdn_stripe -grid {core_grid} \
    -layer {Metal1} \
    -width {0.44} \
    -followpins \
    -extend_to_core_ring
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-grid <name>` | Required | Target grid | `core_grid` |
| `-layer <metal>` | Required | Metal layer | `Metal1`, `Metal4`, `Metal5` |
| `-width <um>` | Required | Stripe width | `0.44` (M1), `4.5` (M4/M5) |
| `-pitch <um>` | Optional | Spacing between stripes | `40.0` |
| `-offset <um>` | Optional | Starting offset | `20.0` |
| `-followpins` | Optional | Use existing cell pins (M1 only) | — |
| `-extend_to_core_ring` | Optional | Connect to core ring | — |

---

### add_pdn_ring
**Purpose:** Add core boundary power ring
```tcl
add_pdn_ring -grid {core_grid} \
    -layer {Metal3 Metal4} \
    -widths "$ring_width $ring_width" \
    -spacings "$ring_spacing $ring_spacing" \
    -core_offsets "$ring_offset $ring_offset"
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-grid <name>` | Required | Target grid | `core_grid` |
| `-layer <metals>` | Required | Metal layers (list) | `{Metal3 Metal4}` |
| `-widths <list>` | Required | Width for each layer | `"6.0 6.0"` |
| `-spacings <list>` | Required | VDD-VSS spacing per layer | `"2.0 2.0"` |
| `-core_offsets <list>` | Required | Offset from core boundary | `"2.0 2.0"` |

---

### add_pdn_connect
**Purpose:** Create via connections between metal layers
```tcl
add_pdn_connect -grid {core_grid} -layers {Metal1 Metal3}
add_pdn_connect -grid {core_grid} -layers {Metal3 Metal4}
add_pdn_connect -grid {core_grid} -layers {Metal4 Metal5}
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-grid <name>` | Required | Target grid | `core_grid` |
| `-layers <list>` | Required | Two layers to connect | `{Metal1 Metal3}` |
| Note: Two-layer connections | — | Creates Via1, Via3, Via4 as needed | — |

---

### pdngen
**Purpose:** Generate PDN structure (stripes, vias, connections)
```tcl
pdngen -failed_via_report ${REPORT_DIR}/02_pdn_failed_vias.rpt
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-failed_via_report <file>` | Optional | Report file for via failures | `reports/02_pdn_failed_vias.rpt` |
| Output: Actual geometry | — | Creates stripe polygons and via arrays | — |

---

### set_wire_rc (PDK Layers)
**Purpose:** Set wire resistance & capacitance for parasitic estimation
```tcl
set_wire_rc -layer Metal3 -resistance 0.5 -capacitance 0.0002
set_wire_rc -signal -layer Metal3
set_wire_rc -clock -layer Metal4
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-layer <metal>` | Required (v1) | Metal layer to configure | `Metal3`, `Metal4`, `Metal5` |
| `-resistance <Ω/µm>` | Optional | Resistance per unit length | `0.5` (IHP 130nm estimated) |
| `-capacitance <pF/µm>` | Optional | Capacitance per unit length | `0.0002` |
| `-signal` | Optional (v2) | Use for signal nets | — |
| `-clock` | Optional (v2) | Use for clock nets | — |

---

---

## Stage 3: Placement (03_placement.tcl)

### read_db
**Purpose:** Load existing OpenROAD checkpoint
```tcl
read_db ${RESULT_DIR}/02_pdn.odb
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<file>` | Required | ODB checkpoint path | `results/02_pdn.odb` |

---

### set_wire_rc (Signal/Clock)
**Purpose:** Set wire resistance & capacitance for parasitic estimation
```tcl
set_wire_rc -signal -layer Metal3
set_wire_rc -clock  -layer Metal4
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-signal` | Optional | Configure for signal nets | — |
| `-clock` | Optional | Configure for clock nets | — |
| `-layer <metal>` | Required | Metal layer | `Metal3`, `Metal4` |

---

### set_dont_use
**Purpose:** Mark cell types for exclusion from placement/optimization
```tcl
set_dont_use "sg13g2_stdcells/sg13g2_nand4/*"
set_dont_use "sg13g2_stdcells/sg13g2_nor4/*"
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<pattern>` | Required | Cell type pattern (regex) | `sg13g2_nand4/*` |

---

### set_placement_padding
**Purpose:** Add halo (site-based) padding around macro cells
```tcl
set_placement_padding -masters {RM_IHPSG13_1P_*} \
    -left $pad_sites \
    -right $pad_sites
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-masters <list>` | Required | Master cell pattern list | `{RM_IHPSG13_1P_*}` |
| `-left <sites>` | Required | Padding sites (westward) | `12` (12 × 0.48µm width) |
| `-right <sites>` | Required | Padding sites (eastward) | `12` |
| `-bottom <sites>` | Optional | Padding sites (southward) | `10` |
| `-top <sites>` | Optional | Padding sites (northward) | `10` |

---

### get_cells
**Purpose:** Query cell instances with filtering
```tcl
set io_pads [get_cells -hierarchical -filter "ref_name =~ *sg13g2_IOPad*"]
set_dont_touch $io_pads
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-hierarchical` | Optional | Include hierarchical instances | — |
| `-filter "<expr>"` | Optional | Filter by property expression | `ref_name =~ *IOPad*` |
| Return: | — | List of cell instances | — |

---

### set_dont_touch (Instance List)
**Purpose:** Apply dont_touch to instance collection
```tcl
set_dont_touch [get_cells -hierarchical -filter "ref_name =~ *sg13g2_IOPad*"]
```
| Parameter | Description |
|-----------|-------------|
| `<instance_list>` | Instances to protect (don't modify) |
| Result: | Instances become fixed during placement |

---

### global_placement
**Purpose:** Run timing-driven global placement of cells
```tcl
global_placement \
    -density $PLACE_DENSITY \
    -pad_left 2 \
    -pad_right 2 \
    -timing_driven
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-density <fraction>` | Required | Target cell density (0.0-1.0) | `0.40` (40% density) |
| `-pad_left <sites>` | Optional | Left padding sites | `2` |
| `-pad_right <sites>` | Optional | Right padding sites | `2` |
| `-pad_top <sites>` | Optional | Top padding sites | `2` |
| `-pad_bottom <sites>` | Optional | Bottom padding sites | `2` |
| `-timing_driven` | Optional | Use timing path information | — |
| `-routability_driven` | Optional | Optimize for routing | — |

---

### estimate_parasitics
**Purpose:** Compute wire capacitance & resistance
```tcl
estimate_parasitics -placement
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-placement` | Optional | Use placement-stage estimates | — |
| `-global_route` | Optional | Use global routing | — |
| `-detailed_route` | Optional | Use detailed routing (post-route) | — |

---

### repair_design
**Purpose:** Fix timing/DRV violations (slew, cap, fanout)
```tcl
repair_design
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-slew_margin <ps>` | Optional | Slew tolerance margin | `0.0` (default) |
| `-cap_margin <pF>` | Optional | Capacitance tolerance margin | `0.0` (default) |
| Return: | — | Number of fixes applied | — |

---

### repair_tie_fanout
**Purpose:** Limit fanout of tie cells (VDD/GND connectors)
```tcl
repair_tie_fanout -separation 20 "sg13g2_tiehi/L_HI"
repair_tie_fanout -separation 20 "sg13g2_tielo/L_LO"
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-separation <um>` | Required | Max distance between tie fanouts | `20` (µm) |
| `<cell_name>` | Required | Tie cell pin to repair | `sg13g2_tiehi/L_HI`, `sg13g2_tielo/L_LO` |

---

### detailed_placement
**Purpose:** Legalize placement (remove overlaps, enforce site rows)
```tcl
detailed_placement
```
| Parameter | Description |
|-----------|-------------|
| (none) | Enforces cell placement on valid sites |

---

### check_placement
**Purpose:** Verify cell placement legality
```tcl
check_placement -verbose
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-verbose` | Optional | Report detailed violation info | — |

---

### filler_placement
**Purpose:** Insert filler cells to complete rows
```tcl
filler_placement $FILLER_CELLS
```
| Parameter | Description | Example |
|-----------|-------------|---------|
| `<cell_list>` | Filler cell types (largest → smallest) | `sg13g2_fillcap_64 sg13g2_fillcap_16 sg13g2_fillcap_4 sg13g2_fill_1` |
| Note: | Use in order of decreasing width | Fills gaps left-to-right |

---

### report_design_area
**Purpose:** Print total die/core area used
```tcl
report_design_area
```
| Output | Example |
|--------|---------|
| Total area | `[area=12345.67 µm²]` |

---

### report_worst_slack
**Purpose:** Print maximum timing slack
```tcl
report_worst_slack -max
report_worst_slack -min
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-max` | Condition | Report setup slack (max delay) | — |
| `-min` | Condition | Report hold slack (min delay) | — |

---

---

## Stage 4: Clock Tree Synthesis (04_cts.tcl)

### read_db
**Purpose:** Load existing OpenROAD checkpoint
```tcl
read_db ${RESULT_DIR}/03_placement.odb
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<file>` | Required | ODB checkpoint path | `results/03_placement.odb` |

---

### read_sdc
**Purpose:** Load timing constraints and clock definitions
```tcl
read_sdc $SDC_FILE
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | SDC file path | `constraints/tpu_chip.sdc` |

---

### ord::get_db_block
**Purpose:** Get current design block for database operations
```tcl
set block [ord::get_db_block]
foreach inst [$block getInsts] { ... }
```
| Return | Description |
|--------|-------------|
| `<dbBlock>` | Current design block object |
| Methods: | `getInsts`, `getBTerms`, `getNets`, `getRows`, etc. |

---

### Instance Methods (dbInst)
**Purpose:** Query/modify individual cell instances
```tcl
set name [$inst getName]
set master [$inst getMaster]
set is_dont_touch [$inst isDoNotTouch]
$inst setDoNotTouch 0
```
| Method | Return | Description | Example |
|--------|--------|-------------|---------|
| `getName` | string | Instance name | `u_tpu_top/u_sram_weight` |
| `getMaster` | dbMaster | Cell type reference | Can query name, pins |
| `isDoNotTouch` | 0/1 | Check dont_touch flag | — |
| `setDoNotTouch <0/1>` | — | Set dont_touch flag | `$inst setDoNotTouch 0` |

---

### Master Methods (dbMaster)
**Purpose:** Query cell type properties
```tcl
set mname [$master getName]
set is_seq [$master isSequential]
```
| Method | Return | Description | Example |
|--------|--------|-------------|---------|
| `getName` | string | Cell type name | `sg13g2_buf_16` |
| `isSequential` | 0/1 | Is flip-flop/latch | Used to count FFs |

---

### all_clocks
**Purpose:** Get all defined clock objects
```tcl
set all_clocks [all_clocks]
foreach clk $all_clocks { ... }
```
| Return | Description | Example |
|--------|-------------|---------|
| list | Clock objects | `{clk0 clk1}` or `{clk}` |

---

### create_clock
**Purpose:** Define clock constraint if not in SDC
```tcl
create_clock -name clk -period 20.0 [get_ports pad_clk_in]
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-name <name>` | Required | Clock name | `clk` |
| `-period <ns>` | Required | Clock period | `20.0` (50 MHz) |
| `<port>` | Required | Source port | `[get_ports pad_clk_in]` |

---

### get_ports
**Purpose:** Query top-level port objects
```tcl
get_ports pad_clk_in
get_ports "*clk*"
```
| Parameter | Description | Example |
|-----------|-------------|---------|
| `<pattern>` | Port name or regex | `pad_clk_in`, `*clk*` |
| Return: | Port object(s) | Used with create_clock, set_input_delay |

---

### set_wire_rc (Layer Configuration)
**Purpose:** Define RLC parasitics for specific metal layers
```tcl
set_wire_rc -layer Metal3 -resistance 0.5 -capacitance 0.0002
set_wire_rc -layer Metal4 -resistance 0.5 -capacitance 0.0002
set_wire_rc -signal -layer Metal3
set_wire_rc -clock  -layer Metal4
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-layer <metal>` | Required | Metal layer | `Metal3`, `Metal4`, `Metal5` |
| `-resistance <Ω/µm>` | Optional | Per-unit resistance | `0.5` |
| `-capacitance <pF/µm>` | Optional | Per-unit capacitance | `0.0002` |
| `-signal` | Optional (use v2) | Use for signal timing | — |
| `-clock` | Optional (use v2) | Use for clock timing | — |

---

### clock_tree_synthesis
**Purpose:** Build clock distribution tree with buffers
```tcl
clock_tree_synthesis \
    -root_buf sg13g2_buf_16 \
    -buf_list {sg13g2_buf_4 sg13g2_buf_8 sg13g2_buf_16}
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-root_buf <cell>` | Required | Root buffer cell type | `sg13g2_buf_16` (largest) |
| `-buf_list <cells>` | Required | Buffer hierarchy (small→large) | `{sg13g2_buf_4 sg13g2_buf_8 sg13g2_buf_16}` |
| `-target_skew <ps>` | Optional | Skew target | `100.0` (ps) |
| `-max_slew <ps>` | Optional | Max slew rate | `100.0` (ps) |

---

### set_propagated_clock
**Purpose:** Enable propagated clock timing model (vs. ideal)
```tcl
set_propagated_clock [all_clocks]
```
| Parameter | Description |
|-----------|-------------|
| `<clocks>` | Clock object list (from `all_clocks`) |
| Effect: | Uses actual buffer delays in timing analysis |

---

### remove_fillers
**Purpose:** Delete previously-inserted filler cells
```tcl
remove_fillers
```
| Parameter | Description |
|-----------|-------------|
| (none) | Removes all sg13g2_fill* and sg13g2_fillcap* cells |
| Use case: | Pre-legalization (before detailed_placement) |

---

### get_property
**Purpose:** Query object attributes
```tcl
set clk_name [get_property $clk name]
set clk_period [get_property $clk period]
```
| Parameter | Description | Example |
|-----------|-------------|---------|
| `<object>` | Clock/net/cell/port object | `$clk`, `$net`, `$inst` |
| `<property>` | Property name | `name`, `period`, `ref_name` |
| Return: | Property value | String or numeric |

---

### report_clock_skew
**Purpose:** Print clock timing skew analysis
```tcl
report_clock_skew -clock clk
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-clock <name>` | Optional | Specific clock | `clk` |
| Output: | — | Min/max arrival times at leafs | — |

---

### report_worst_slack
**Purpose:** Print worst timing slack
```tcl
report_worst_slack -max
report_worst_slack -min
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-max` | Condition | Setup slack (setup violations) | — |
| `-min` | Condition | Hold slack (hold violations) | — |

---

### report_tns
**Purpose:** Print total negative slack (sum of all slack violations)
```tcl
report_tns
```
| Output | Description |
|--------|-------------|
| TNS value | Sum of slacks ≤ 0; negative is better |

---

### write_db
**Purpose:** Save current design checkpoint
```tcl
write_db ${RESULT_DIR}/04_cts.odb
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output ODB path | `results/04_cts.odb` |

---

### save_image
**Purpose:** Export design view as PNG/PDF
```tcl
save_image ${REPORT_DIR}/04_cts.png
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output image path | `reports/04_cts.png` |
| `-width <px>` | Optional | Image width | `1920` |
| `-height <px>` | Optional | Image height | `1080` |

---
| `set_propagated_clock` | `<clocks>` | Mark clocks as routed (for timing) |
| `remove_fillers` | — | Delete filler cells (before re-legalize) |
| `set_wire_rc` | See Stage 2 | Recalculate for CTS nets |
| `report_clock_skew` | `-clock <name>` `-hold` | Analyze clock delays & hold margin |
| `report_tns` | — | Total negative slack (sum of violations) |

---

## Stage 5: Routing (05_routing.tcl)

### read_db
**Purpose:** Load existing OpenROAD checkpoint
```tcl
read_db ${RESULT_DIR}/04_cts.odb
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<file>` | Required | ODB checkpoint path | `results/04_cts.odb` |

---

### read_sdc
**Purpose:** Load timing constraints and clock definitions
```tcl
read_sdc $SDC_FILE
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | SDC file path | `constraints/tpu_chip.sdc` |

---

### set_wire_rc (Signal/Clock)
**Purpose:** Set wire resistance & capacitance for parasitic estimation
```tcl
set_wire_rc -signal -layer Metal3
set_wire_rc -clock  -layer Metal4
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-signal` | Optional | Configure for signal nets | — |
| `-clock` | Optional | Configure for clock nets | — |
| `-layer <metal>` | Required | Metal layer | `Metal3`, `Metal4` |

---

### set_routing_layers
**Purpose:** Restrict routing to specified metal layers
```tcl
set_routing_layers -signal Metal2-TopMetal1 -clock Metal2-TopMetal1
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-signal <layers>` | Optional | Signal routing layer range | `Metal2-Metal9`, `Metal2-TopMetal1` |
| `-clock <layers>` | Optional | Clock routing layer range | `Metal2-Metal9`, `Metal2-TopMetal1` |
| Note: | — | Both can be same range | Specify contiguous layer names |

---

### set_global_routing_layer_adjustment
**Purpose:** Adjust metal layer capacity (for congestion control)
```tcl
set_global_routing_layer_adjustment Metal2-Metal3 0.30
set_global_routing_layer_adjustment TopMetal1 0.20
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<layer>` | Required | Metal layer name | `Metal2`, `Metal3-Metal4`, `TopMetal1` |
| `<factor>` | Required | Capacity multiplier (0.0-1.0) | `0.30` (30% capacity), `1.0` (full) |
| Use: | — | Reduce capacity near SRAM pins | `0.20` around congested regions |

---

### global_route
**Purpose:** Generate routing guides (coarse routing)
```tcl
global_route \
    -guide_file ${RESULT_DIR}/route.guide \
    -congestion_report_file ${REPORT_DIR}/05_congestion.rpt \
    -allow_congestion \
    -verbose
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-guide_file <file>` | Required | Output routing guides | `results/route.guide` |
| `-congestion_report_file <file>` | Optional | Congestion metrics output | `reports/05_congestion.rpt` |
| `-allow_congestion` | Optional | Permit over-capacity routes | — |
| `-verbose` | Optional | Detailed output | — |

---

### estimate_parasitics (Post-Routing)
**Purpose:** Compute wire capacitance & resistance
```tcl
estimate_parasitics -placement
estimate_parasitics -global_route
estimate_parasitics -detailed_route
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-placement` | Optional | Use placement-stage estimates | — |
| `-global_route` | Optional | Use global routing topology | — |
| `-detailed_route` | Optional | Use actual detailed routing | Most accurate post-route |

---

### repair_design (Post-Global-Route)
**Purpose:** Fix timing/DRV violations introduced by routing
```tcl
repair_design -verbose
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-verbose` | Optional | Detailed violation reporting | — |

---

### detailed_placement
**Purpose:** Legalize placement after routing repair
```tcl
detailed_placement
```
| Parameter | Description |
|-----------|-------------|
| (none) | Enforces cell placement on valid sites |

---

### set_thread_count
**Purpose:** Configure parallel processing threads
```tcl
set_thread_count 8
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<N>` | Required | Number of threads | `8` (use 8 cores) |
| Use: | — | Set before detailed_route | Affects router speed |

---

### detailed_route
**Purpose:** Perform actual wire routing on metal layers
```tcl
detailed_route \
    -output_drc ${REPORT_DIR}/05_route_drc.rpt \
    -droute_end_iter 40 \
    -save_guide_updates \
    -clean_patches \
    -verbose 1
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-output_drc <file>` | Optional | DRC violation report | `reports/05_route_drc.rpt` |
| `-droute_end_iter <N>` | Optional | Max routing iterations | `40` |
| `-save_guide_updates` | Optional | Save refined routing guides | — |
| `-clean_patches` | Optional | Clean routing artifacts | — |
| `-verbose <0-2>` | Optional | Verbosity level | `0` (quiet), `1` (normal), `2` (verbose) |

---

### global_connect (Final)
**Purpose:** Execute all global connection mappings (final pass)
```tcl
global_connect
```
| Parameter | Description |
|-----------|-------------|
| (none) | Connects all matched pins based on add_global_connection rules |

---

### write_db
**Purpose:** Save current design checkpoint
```tcl
write_db ${RESULT_DIR}/05_route.odb
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output ODB path | `results/05_route.odb` |

---

### write_def
**Purpose:** Export design in DEF format (standard industry format)
```tcl
write_def ${RESULT_DIR}/tpu_chip.def
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output DEF file | `results/tpu_chip.def` |
| Use: | — | For DRC, LVS tools, verification | Standard Cadence/Siemens format |

---

### report_worst_slack
**Purpose:** Print worst timing slack
```tcl
report_worst_slack -max
report_worst_slack -min
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-max` | Condition | Setup slack (setup violations) | — |
| `-min` | Condition | Hold slack (hold violations) | — |

---

### report_tns
**Purpose:** Print total negative slack (sum of all slack violations)
```tcl
report_tns
```
| Output | Description |
|--------|-------------|
| TNS value | Sum of slacks ≤ 0; negative is better |

---

### report_design_area
**Purpose:** Print total die/core area used
```tcl
report_design_area
```
| Output | Example |
|--------|---------|
| Total area | `[area=12345.67 µm²]` |

---

### save_image
**Purpose:** Export design view as PNG/PDF
```tcl
save_image ${REPORT_DIR}/05_route.png
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output image path | `reports/05_route.png` |
| `-width <px>` | Optional | Image width | `1920` |
| `-height <px>` | Optional | Image height | `1080` |

---

## Stage 6: Finishing (06_finishing.tcl)

### read_db
**Purpose:** Load existing OpenROAD checkpoint
```tcl
read_db ${RESULT_DIR}/05_route.odb
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<file>` | Required | ODB checkpoint path | `results/05_route.odb` |

---

### read_sdc
**Purpose:** Load timing constraints and clock definitions
```tcl
read_sdc $SDC_FILE
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | SDC file path | `constraints/tpu_chip.sdc` |

---

### set_wire_rc (Final)
**Purpose:** Set wire resistance & capacitance for parasitic estimation
```tcl
set_wire_rc -signal -layer Metal3
set_wire_rc -clock  -layer Metal4
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-signal` | Optional | Configure for signal nets | — |
| `-clock` | Optional | Configure for clock nets | — |
| `-layer <metal>` | Required | Metal layer | `Metal3`, `Metal4` |

---

### estimate_parasitics (Final)
**Purpose:** Compute final wire capacitance & resistance
```tcl
estimate_parasitics -placement
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-placement` | Optional | Use placement-stage estimates | Most accurate at finishing |
| `-global_route` | Optional | Use global routing | — |
| `-detailed_route` | Optional | Use detailed routing | — |

---

### report_checks
**Purpose:** Print timing path information and violations
```tcl
report_checks -path_delay min_max -digits 3
report_checks -path_delay min_max \
    -fields {slew cap input fanout} \
    -digits 3 \
    -format full_clock_expanded
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-path_delay <type>` | Optional | Path type: `min_max`, `min`, `max` | `min_max` |
| `-fields <list>` | Optional | Report fields | `{slew cap input fanout}` |
| `-digits <N>` | Optional | Precision (decimal places) | `3`, `4` |
| `-format <fmt>` | Optional | Format: `full_clock_expanded`, `full_clock`, `short` | `full_clock_expanded` |

---

### sta::worst_slack_cmd
**Purpose:** Get worst-case timing slack (TCL API)
```tcl
set setup_slack [sta::worst_slack_cmd "max"]
set hold_slack  [sta::worst_slack_cmd "min"]
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<type>` | Required | `"max"` (setup) or `"min"` (hold) | `"max"` |
| Return: | float | Slack value in nanoseconds | `0.123`, `-0.456` |

---

### sta::total_negative_slack_cmd
**Purpose:** Get total negative slack (TCL API)
```tcl
set setup_tns [sta::total_negative_slack_cmd "max"]
set hold_tns  [sta::total_negative_slack_cmd "min"]
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<type>` | Required | `"max"` (setup) or `"min"` (hold) | `"max"` |
| Return: | float | TNS value in nanoseconds | `-1.234` (negative is bad) |

---

### repair_timing
**Purpose:** Fix timing violations by inserting buffers/resizing cells
```tcl
repair_timing -setup -slack_margin 0.1
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-setup` | Conditional | Repair setup violations | — |
| `-hold` | Conditional | Repair hold violations (use with caution) | — |
| `-slack_margin <ns>` | Optional | Safety margin | `0.1` (100ps) |
| Note: | — | May fail on SRAM macro pins | — |

---

### check_placement
**Purpose:** Verify cell placement legality
```tcl
check_placement -verbose
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-verbose` | Optional | Report detailed violation info | — |

---

### report_design_area
**Purpose:** Print total die/core area used
```tcl
report_design_area
```
| Output | Example |
|--------|---------|
| Total area | `[area=12345.67 µm²]` |

---

### write_db
**Purpose:** Save current design checkpoint
```tcl
write_db ${RESULT_DIR}/06_finishing.odb
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output ODB path | `results/06_finishing.odb` |

---

### save_image
**Purpose:** Export design view as PNG/PDF
```tcl
save_image ${REPORT_DIR}/06_finishing.png
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output image path | `reports/06_finishing.png` |

---

## Stage 7: Signoff & Tape-Out (07_signoff.tcl)

### read_db
**Purpose:** Load existing OpenROAD checkpoint
```tcl
read_db ${RESULT_DIR}/06_finishing.odb
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `<file>` | Required | ODB checkpoint path | `results/06_finishing.odb` |

---

### read_sdc
**Purpose:** Load timing constraints and clock definitions
```tcl
read_sdc $SDC_FILE
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | SDC file path | `constraints/tpu_chip.sdc` |

---

### estimate_parasitics (Signoff)
**Purpose:** Compute final wire parasitics for signoff
```tcl
estimate_parasitics -placement
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-placement` | Optional | Use placement-stage estimates | Best for final signoff |

---

### report_checks (Detailed)
**Purpose:** Print comprehensive timing path information
```tcl
report_checks -path_delay min_max \
    -fields {slew cap input nets fanout} \
    -digits 4
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-path_delay <type>` | Optional | `min_max`, `min`, `max` | `min_max` |
| `-fields <list>` | Optional | Report fields | `{slew cap input nets fanout}` |
| `-digits <N>` | Optional | Precision | `3`, `4` |

---

### report_clock_skew
**Purpose:** Print clock timing skew analysis
```tcl
report_clock_skew
```
| Output | Description |
|--------|-------------|
| Skew report | Min/max arrival times, skew budget |

---

### report_clock_min_period
**Purpose:** Print minimum achievable clock period
```tcl
report_clock_min_period
```
| Output | Description |
|--------|-------------|
| Min period | Clock frequency limit |

---

### report_check_types
**Purpose:** Report specific DRV violations
```tcl
report_check_types -max_slew -max_capacitance -max_fanout -violators
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-max_slew` | Optional | Report slew violations | — |
| `-max_capacitance` | Optional | Report capacitance violations | — |
| `-max_fanout` | Optional | Report fanout violations | — |
| `-violators` | Optional | List only violating paths | — |

---

### report_power
**Purpose:** Estimate power consumption
```tcl
report_power -corner tt
```
| Switch | Type | Description | Example |
|--------|------|-------------|---------|
| `-corner <name>` | Optional | PVT corner name | `tt` (typical), `ss`, `ff` |

---

### write_verilog
**Purpose:** Export design as Verilog netlist
```tcl
write_verilog ${RESULT_DIR}/${DESIGN}_final.v
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output Verilog path | `results/tpu_chip_final.v` |

---

### write_def
**Purpose:** Export design in DEF format (standard industry format)
```tcl
write_def ${RESULT_DIR}/${DESIGN}_final.def
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output DEF file | `results/tpu_chip_final.def` |

---

### write_sdc
**Purpose:** Export timing constraints in SDC format
```tcl
write_sdc ${RESULT_DIR}/${DESIGN}_final.sdc
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output SDC file | `results/tpu_chip_final.sdc` |

---

### write_spef
**Purpose:** Export parasitics in SPEF format
```tcl
write_spef ${RESULT_DIR}/${DESIGN}_final.spef
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output SPEF file | `results/tpu_chip_final.spef` |
| Note: | — | Used for DRC, LVS, power analysis | Standard format |

---

### exec mkdir
**Purpose:** Create directories (Tcl system command)
```tcl
exec mkdir -p ${REPORT_DIR}/signoff
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `-p` | Optional | Create parent dirs | — |
| `<path>` | Required | Directory path | `reports/signoff` |

---

### write_db (Final)
**Purpose:** Save final design checkpoint
```tcl
write_db ${RESULT_DIR}/07_signoff.odb
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output ODB path | `results/07_signoff.odb` |

---

### save_image (Final)
**Purpose:** Export final design view as PNG/PDF
```tcl
save_image ${REPORT_DIR}/signoff/layout_final.png
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | Output image path | `reports/signoff/layout_final.png` |

---

---

## Utility Commands (All Stages)

### puts
**Purpose:** Print text to console and log file
```tcl
puts "========================================="
puts "Loaded floorplan checkpoint"
puts "  Total instances: $inst_count"
```
| Parameter | Description | Example |
|-----------|-------------|---------|
| `<string>` | Text to print | `"Stage 1: Floorplan"` |
| Concatenation: | Use `$var` for variable substitution | `"Count: $count"` |

---

### source
**Purpose:** Execute another TCL script (loads functions, configs)
```tcl
source config.tcl
source scripts/floorplan_util.tcl
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<file>` | Required | File path (relative or absolute) | `config.tcl`, `scripts/init_tech.tcl` |

---

### expr
**Purpose:** Evaluate mathematical/logical expressions
```tcl
set total_width [expr {$width + $margin}]
set site_count [expr {int($halo_x / $site_width)}]
set is_sram [expr {[string match "*RM_IHPSG13*" $name]}]
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `{expression}` | Required | Math/boolean expression | `{$a + $b}`, `{int($x / $y)}` |
| Operators: | — | `+`, `-`, `*`, `/`, `==`, `!=`, `<`, `>`, `&&`, `||` | — |
| Functions: | — | `int()`, `ceil()`, `floor()`, `sqrt()`, `abs()` | — |

---

### if / else
**Purpose:** Conditional code execution
```tcl
if {![file exists ${RESULT_DIR}/02_pdn.odb]} {
    puts "ERROR: File not found!"
    exit 1
}

if {$value > 100} {
    puts "Large"
} else {
    puts "Small"
}
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `{condition}` | Required | Boolean expression | `$x > 0`, `[file exists $f]` |
| `{then_body}` | Required | Code if true | `{puts "yes"}` |
| `else {else_body}` | Optional | Code if false | `{puts "no"}` |
| Note: | — | Use `&&` and `||` for AND/OR | `{$a > 0 && $b < 10}` |

---

### foreach
**Purpose:** Loop over list of elements
```tcl
foreach inst [$block getInsts] {
    set name [$inst getName]
    puts "Instance: $name"
}

foreach layer {Metal1 Metal3 Metal5} {
    puts "Layer: $layer"
}
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<var>` | Required | Loop variable name | `inst`, `layer`, `clk` |
| `<list>` | Required | List to iterate | `[$block getInsts]`, `{M1 M3 M5}` |
| `<body>` | Required | Code for each iteration | `{puts $var}` |

---

### set
**Purpose:** Create/assign variable
```tcl
set count 10
set file_path "/home/ref_tpu/pnr/"
set block [ord::get_db_block]
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<var_name>` | Required | Variable identifier | `count`, `file_path`, `block` |
| `<value>` | Required | Value (string/number/object) | `42`, `"text"`, `$obj` |

---

### info exists
**Purpose:** Check if variable is defined
```tcl
if {[info exists DONT_USE] && [llength $DONT_USE] > 0} {
    foreach pattern $DONT_USE {
        set_dont_use $pattern
    }
}
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<var_name>` | Required | Variable to check | `DONT_USE`, `PLACE_DENSITY` |
| Return: | 1/0 | 1 if defined, 0 if not | — |

---

### file exists
**Purpose:** Check if file path exists
```tcl
if {![file exists ${RESULT_DIR}/02_pdn.odb]} {
    puts "ERROR: PDN checkpoint not found!"
    exit 1
}
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<path>` | Required | File/directory path | `results/01_floorplan.odb` |
| Return: | 1/0 | 1 if exists, 0 if not | — |

---

### llength
**Purpose:** Get number of elements in list
```tcl
set ff_count [llength [$block getInsts]]
if {[llength [$block getBTerms]] > 0} { }
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<list>` | Required | List to measure | `$my_list`, `[$obj getItems]` |
| Return: | integer | Count of elements | `0`, `5`, `100` |

---

### lindex
**Purpose:** Get element at specific position in list
```tcl
set first_item [lindex $my_list 0]
set sram_dims [getMacroDimensions "RM_..."]
set sram_w [lindex $sram_dims 0]
set sram_h [lindex $sram_dims 1]
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<list>` | Required | List source | `$items`, `{a b c}` |
| `<index>` | Required | Position (0-based) | `0` (first), `1` (second) |
| Return: | value | Element at index | — |

---

### lsort
**Purpose:** Sort list elements
```tcl
set sorted [lsort $unsorted_list]
set sorted_desc [lsort -decreasing $list]
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<list>` | Required | List to sort | `$items` |
| `-increasing` | Optional | Sort ascending (default) | — |
| `-decreasing` | Optional | Sort descending | — |
| Return: | sorted list | Elements in order | — |

---

### string match
**Purpose:** Check if string matches pattern (wildcard)
```tcl
if {[string match "*u_sram_*" $name]} { }
if {[string match "*sg13g2_IOPad*" $ref]} { }
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `<pattern>` | Required | Wildcard pattern | `*IOPad*`, `RM_IHPSG13*` |
| `<string>` | Required | String to test | `$inst_name` |
| Return: | 1/0 | 1 if match, 0 if not | — |

---

### catch
**Purpose:** Execute code and catch errors (for error handling)
```tcl
if {[catch {save_image ${REPORT_DIR}/04_cts.png} err]} {
    puts "⚠ WARNING: Could not save image"
} else {
    puts "Saved image successfully"
}
```
| Parameter | Type | Description | Example |
|-----------|------|-------------|---------|
| `{code}` | Required | Code to execute | `{save_image $file}` |
| `<var>` | Optional | Variable for error message | `err` |
| Return: | 0/1 | 0 if success, 1 if error | — |

---

### clock seconds
**Purpose:** Get current time in seconds (for timing)
```tcl
set start_time [clock seconds]
set elapsed [expr {[clock seconds] - $start_time}]
puts "Completed in ${elapsed}s"
```
| Return | Description | Example |
|--------|-------------|---------|
| seconds | Unix timestamp | `1609459200` |

---

---

## Key Parameter Variables (from config.tcl)

| Variable | Default | Usage |
|----------|---------|-------|
| `$DIE_WIDTH` | — | Die width (µm) |
| `$DIE_HEIGHT` | — | Die height (µm) |
| `$CORE_WIDTH` | — | Core width (µm) |
| `$CORE_HEIGHT` | — | Core height (µm) |
| `$CORE_MARGIN` | — | Margin from die edge to core (µm) |
| `$MACRO_HALO_X` / `_Y` | — | Keep-out zone around macros (µm) |
| `$PDN_STRIPE_WIDTH` | 4.5 | Power stripe width (µm) |
| `$PDN_STRIPE_PITCH` | 40.0 | Power stripe spacing (µm) |
| `$PLACE_DENSITY` | 40 | Target placement density (%) |
| `$RESULT_DIR` | ./results | Output checkpoint directory |
| `$REPORT_DIR` | ./reports | Reports & images directory |
| `$CLK_PORT` | clk_pad | Top-level clock port name |
| `$CLK_PERIOD` | 20.0 | Clock period (ns) = 50 MHz |

---

## Common Filter Patterns

| Filter | Meaning |
|--------|---------|
| `ref_name =~ RM_IHPSG13_1P_.*` | All SRAM macros (regex: .* = any chars) |
| `ref_name =~ .*sg13g2_buf.*` | All buffer cells |
| `direction == input` | Input ports |
| `direction == output` | Output ports |
| `[string match "*clk*" $name]` | Name contains "clk" (Tcl glob) |

---

## Notes

- **DBU (Database Units)**: OpenROAD uses integer DBU internally. Use `ord::microns_to_dbu` for conversions.
- **Database Block**: `set block [ord::get_db_block]` gives access to design instance graph.
- **Regex vs Glob**: OpenROAD filters use regex (`=~`). Tcl `string match` uses glob patterns.
- **Checkpoints**: `.odb` files capture full design state (geometry, timing, connectivity) for resuming runs.
- **Reports**: DRC, timing, area reports written to `$REPORT_DIR/` for post-analysis.

---

## References

- [OpenROAD GitHub](https://github.com/The-OpenROAD-Project/OpenROAD)
- [OpenROAD Docs](https://openroad.readthedocs.io/)
- IHP SG13G2 PDK: Metal1–Metal5, Via1–Via4, 130nm technology
