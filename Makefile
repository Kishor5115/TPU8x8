SHELL := /bin/bash

TOP ?= tpu_chip
YOSYS   ?= yosys
OPENROAD ?= openroad
KLAYOUT  ?= klayout

# Original design directories (switched from opt_pnr / opt_yosys)
YOSYS_DIR := yosys
PNR_DIR   := pnr

FINAL_VERILOG := $(PNR_DIR)/results/$(TOP)_final.v
FINAL_DEF     := $(PNR_DIR)/results/$(TOP)_final.def
FINAL_GDS     := $(PNR_DIR)/results/$(TOP)_final.gds

OPT_YOSYS_DIR := opt_yosys
OPT_PNR_DIR   := opt_pnr
OPT_FINAL_GDS := $(OPT_PNR_DIR)/results/$(TOP)_final.gds

KLAYOUT_DRC_DECK := ihp13/pdk/ihp-sg13g2/libs.tech/klayout/tech/drc/sg13g2_minimal.lydrc
KLAYOUT_LVS_DECK := ihp13/pdk/ihp-sg13g2/libs.tech/klayout/tech/lvs/sg13g2_full.lylvs

SIGNOFF_DIR   := $(PNR_DIR)/reports/signoff
KLAYOUT_RPT_DIR := $(SIGNOFF_DIR)/klayout
DRC_RDB       := $(KLAYOUT_RPT_DIR)/$(TOP)_drc.lyrdb
DRC_LOG       := $(KLAYOUT_RPT_DIR)/$(TOP)_drc.log
LVS_RDB       := $(KLAYOUT_RPT_DIR)/$(TOP)_lvs.lvsdb
LVS_LOG       := $(KLAYOUT_RPT_DIR)/$(TOP)_lvs.log
LVS_NETLIST   := $(PNR_DIR)/results/$(TOP)_final.cdl
LVS_EXTRACTED := $(PNR_DIR)/results/$(TOP)_extracted.cir

.PHONY: help all env yosys pnr flow gds gds-only drc lvs-netlist lvs tapeout clean opt_yosys opt_pnr view-gds view-opt-gds

help:
	@echo ""
	@echo "TPU Chip — Original Design Targets (Independent Actions)"
	@echo "==========================================="
	@echo "  yosys        - Run synthesis        (yosys/yosys.tcl)"
	@echo "  pnr          - Run OpenROAD PnR      (pnr/flow.tcl)"
	@echo "  flow         - Alias for pnr"
	@echo "  gds          - DEF→GDS via KLayout"
	@echo "  drc          - KLayout DRC on final GDS"
	@echo "  lvs-netlist  - Generate CDL netlist from Verilog"
	@echo "  lvs          - KLayout LVS"
	@echo "  tapeout      - Full tapeout check (runs drc + lvs)"
	@echo "  clean        - Remove KLayout DRC/LVS artifacts"
	@echo "  view-gds     - Open original GDS in KLayout GUI"
	@echo "  opt_yosys    - Run synthesis for Optimized Design"
	@echo "  opt_pnr      - Run OpenROAD PnR for Optimized Design"
	@echo "  view-opt-gds - Open optimized GDS in KLayout GUI"
	@echo ""

all: tapeout

env:
	@source ./env.sh > /dev/null && echo "Environment loaded"

yosys:
	@source ./env.sh && cd $(YOSYS_DIR) && $(YOSYS) -c yosys.tcl

pnr:
	@source ./env.sh && cd $(PNR_DIR) && mkdir -p logs && \
		set -o pipefail; \
		$(OPENROAD) -exit flow.tcl 2>&1 | tee logs/flow.log; \
		status=$$?; \
		rm -f logs/0*_*.log; \
		awk 'BEGIN { \
			stage[0]="init"; stage[1]="floorplan"; stage[2]="pdn"; stage[3]="placement"; \
			stage[4]="cts"; stage[5]="routing"; stage[6]="finishing"; stage[7]="signoff"; \
			cur="logs/00_init.log" \
		} { \
			if ($$1=="Stage" && $$2 ~ /^[0-7]:$$/) { \
				n=$$2; sub(":", "", n); \
				cur=sprintf("logs/%02d_%s.log", n, stage[n]); \
			} \
			print >> cur; \
		}' logs/flow.log; \
		exit $$status

opt_yosys:
	@source ./env.sh && cd $(OPT_YOSYS_DIR) && $(YOSYS) -c yosys.tcl

opt_pnr:
	@source ./env.sh && cd $(OPT_PNR_DIR) && mkdir -p logs && \
		set -o pipefail; \
		$(OPENROAD) -exit flow.tcl 2>&1 | tee logs/flow.log; \
		status=$$?; \
		rm -f logs/0*_*.log; \
		awk 'BEGIN { \
			stage[0]="init"; stage[1]="floorplan"; stage[2]="pdn"; stage[3]="placement"; \
			stage[4]="cts"; stage[5]="routing"; stage[6]="finishing"; stage[7]="signoff"; \
			cur="logs/00_init.log" \
		} { \
			if ($$1=="Stage" && $$2 ~ /^[0-7]:$$/) { \
				n=$$2; sub(":", "", n); \
				cur=sprintf("logs/%02d_%s.log", n, stage[n]); \
			} \
			print >> cur; \
		}' logs/flow.log; \
		exit $$status

flow: pnr

gds:
	@source ./env.sh && cd $(PNR_DIR)/klayout && ./def2gds.sh

view-gds:
	@source ./env.sh && $(KLAYOUT) -e $(FINAL_GDS)

view-opt-gds:
	@source ./env.sh && $(KLAYOUT) -e $(OPT_FINAL_GDS)

drc:
	@mkdir -p $(KLAYOUT_RPT_DIR)
	@source ./env.sh && $(KLAYOUT) -b -r $(KLAYOUT_DRC_DECK) \
		-rd in_gds="$(abspath $(FINAL_GDS))" \
		-rd cell="$(TOP)" \
		-rd report_file="$(abspath $(DRC_RDB))" \
		-rd log_file="$(abspath $(DRC_LOG))"
	@echo "DRC report: $(DRC_RDB)"
	@echo "DRC log:    $(DRC_LOG)"

lvs-netlist:
	@source ./env.sh && cd $(PNR_DIR) && \
		printf '%s\n' \
			'read_db results/07_signoff.odb' \
			'write_cdl -masters {../ihp13/pdk/ihp-sg13g2/libs.ref/sg13g2_stdcell/cdl/sg13g2_stdcell.cdl ../ihp13/pdk/ihp-sg13g2/libs.ref/sg13g2_io/cdl/sg13g2_io.cdl ../ihp13/pdk/ihp-sg13g2/libs.ref/sg13g2_sram/cdl/RM_IHPSG13_1P_64x64_c2_bm_bist.cdl ../ihp13/pdk/ihp-sg13g2/libs.ref/sg13g2_sram/cdl/RM_IHPSG13_1P_256x64_c2_bm_bist.cdl ../ihp13/bondpad/cdl/bondpad_70x70.cdl} results/$(TOP)_final.cdl' \
			'exit' | $(OPENROAD) -exit
	@echo "Generated LVS netlist: $(LVS_NETLIST)"

lvs:
	@mkdir -p $(KLAYOUT_RPT_DIR)
	@source ./env.sh && $(KLAYOUT) -b -r $(KLAYOUT_LVS_DECK) \
		-rd in_gds="$(abspath $(FINAL_GDS))" \
		-rd cdl_file="$(abspath $(LVS_NETLIST))" \
		-rd report_file="$(abspath $(LVS_RDB))" \
		-rd target_netlist="$(abspath $(LVS_EXTRACTED))" \
		-rd run_mode=hierarchical \
		-rd topcell="$(TOP)" \
		-rd verbose=false \
		-rd no_simplify=false \
		-rd no_net_names=false \
		-rd spice_comments=false \
		-rd thr=4 | tee $(LVS_LOG)

tapeout: drc lvs
	@echo "Tapeout checks finished. Review DRC/LVS reports before submission."

clean:
	@rm -f $(DRC_RDB) $(DRC_LOG) $(LVS_RDB) $(LVS_LOG) $(LVS_EXTRACTED) $(LVS_NETLIST)
	@echo "Cleaned KLayout DRC/LVS artifacts"
