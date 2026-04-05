# ============================================================================
# Makefile — Pre-Synthesis Simulation (Icarus Verilog)
# TPU 8×8 Systolic Array — IHP SG13G2 130nm
# ============================================================================

# Paths
RTL_DIR     = ../../rtl
PDK_BASE    = ../../ihp13/pdk/ihp-sg13g2/libs.ref
SRAM_DIR    = $(PDK_BASE)/sg13g2_sram/verilog

# RTL Sources
RTL_FILES   = $(RTL_DIR)/tpu_top.v \
              $(RTL_DIR)/tpu_core.v \
              $(RTL_DIR)/systolic.v \
              $(RTL_DIR)/systolic_controll.v \
              $(RTL_DIR)/addr_sel.v \
              $(RTL_DIR)/quantize.v \
              $(RTL_DIR)/write_out.v

# SRAM Behavioral Models (need FUNCTIONAL define)
SRAM_FILES  = $(SRAM_DIR)/RM_IHPSG13_1P_core_behavioral_bm_bist.v \
              $(SRAM_DIR)/RM_IHPSG13_1P_256x64_c2_bm_bist.v \
              $(SRAM_DIR)/RM_IHPSG13_1P_64x64_c2_bm_bist.v

# Testbench
TB_FILE     = tpu_tb.v

# Compiler flags
IVERILOG    = iverilog
VVP         = vvp
DEFINES     = -DFUNCTIONAL
IFLAGS      = -g2012 $(DEFINES) -Wall

# Output
SIM_OUT     = tpu_sim
VCD_FILE    = tpu_master.vcd

# ============================================================================
# Targets
# ============================================================================

.PHONY: all compile sim wave clean

all: sim

compile: $(SIM_OUT)

$(SIM_OUT): $(TB_FILE) $(RTL_FILES) $(SRAM_FILES)
	$(IVERILOG) $(IFLAGS) -o $@ $^

sim: $(SIM_OUT)
	$(VVP) $< | tee sim.log
	@echo ""
	@echo "=== Simulation complete. VCD: $(VCD_FILE) ==="

wave: sim
	gtkwave $(VCD_FILE) &

clean:
	rm -f $(SIM_OUT) $(VCD_FILE) sim.log

help:
	@echo "Targets:"
	@echo "  all     - Compile and run simulation (default)"
	@echo "  compile - Compile only"
	@echo "  sim     - Compile and run"
	@echo "  wave    - Run and open waveform viewer"
	@echo "  clean   - Remove generated files"
