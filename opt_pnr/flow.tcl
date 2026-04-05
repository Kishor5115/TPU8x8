
#? PnR Flow Controller
#? This script sources all stages in sequence to perform the full implementation.

source 00_init.tcl
source 01_floorplan.tcl
source 02_pdn.tcl
source 03_placement.tcl
source 04_cts.tcl
source 05_routing.tcl
source 06_finishing.tcl
source 07_signoff.tcl
