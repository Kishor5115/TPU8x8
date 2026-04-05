# ============================================================================
# Makefile — Post-Synthesis Gate-Level Simulation (Icarus Verilog)
# TPU 8×8 Systolic Array — IHP SG13G2 130nm
# ============================================================================

# Paths
PNR_DIR     = ../../pnr/results
PDK_BASE    = ../../ihp13/pdk/ihp-sg13g2/libs.ref
BONDPAD_DIR = ../../ihp13/bondpad/verilog
STDCELL_DIR = $(PDK_BASE)/sg13g2_stdcell/verilog
IO_DIR      = $(PDK_BASE)/sg13g2_io/verilog
SRAM_DIR    = $(PDK_BASE)/sg13g2_sram/verilog

# Gate-Level Netlist
NETLIST     = $(PNR_DIR)/tpu_chip_final.v

# PDK Cell Libraries
PDK_FILES   = $(STDCELL_DIR)/sg13g2_stdcell.v \
              $(IO_DIR)/sg13g2_io.v \
			  $(BONDPAD_DIR)/bondpad_70x70.v \
              $(SRAM_DIR)/RM_IHPSG13_1P_core_behavioral_bm_bist.v \
              $(SRAM_DIR)/RM_IHPSG13_1P_256x64_c2_bm_bist.v \
              $(SRAM_DIR)/RM_IHPSG13_1P_64x64_c2_bm_bist.v

# Testbench (Master TB from Pre-Synth)
TB_FILE     = ../pre_synth/tpu_tb.v

# Compiler flags
IVERILOG    = iverilog
VVP         = vvp
DEFINES     = -DFUNCTIONAL -DGSR_NETLIST
IFLAGS      = -g2012 $(DEFINES) -Wall

# Output
SIM_OUT     = tpu_post_sim
VCD_FILE    = tpu_master.vcd

# ============================================================================
# Targets
# ============================================================================

.PHONY: all compile sim wave clean

all: sim

compile: $(SIM_OUT)

$(SIM_OUT): $(TB_FILE) $(NETLIST) $(PDK_FILES)
	$(IVERILOG) $(IFLAGS) -o $@ $^

sim: $(SIM_OUT)
	$(VVP) $< | tee sim.log
	@echo ""
	@echo "=== Post-Synth Simulation complete. VCD: $(VCD_FILE) ==="

wave: sim
	gtkwave $(VCD_FILE) &

clean:
	rm -f $(SIM_OUT) $(VCD_FILE) sim.log

help:
	@echo "Targets:"
	@echo "  all     - Compile and run post-synth simulation (default)"
	@echo "  compile - Compile only"
	@echo "  sim     - Compile and run"
	@echo "  wave    - Run and open waveform viewer"
	@echo "  clean   - Remove generated files"
