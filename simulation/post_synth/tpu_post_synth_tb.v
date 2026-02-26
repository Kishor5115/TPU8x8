// ============================================================================
// Testbench     : tpu_post_synth_tb (Post-Synthesis / Gate-Level)
// Description   : Gate-level verification of tpu_chip after PnR
// Technology    : IHP SG13G2 130nm
//
// This testbench verifies the synthesized netlist (tpu_chip_final.v)
// which includes:
//   - Standard cells (sg13g2_stdcell.v)
//   - IO pads (sg13g2_io.v)
//   - SRAM macros (behavioral models with FUNCTIONAL define)
//
// Usage:
//   iverilog -DFUNCTIONAL -g2012 -o tpu_post_sim tpu_post_synth_tb.v \
//     ../../pnr/results/tpu_chip_final.v \
//     <pdk_stdcell.v> <pdk_io.v> <sram_models>
//   vvp tpu_post_sim
// ============================================================================

`timescale 1ns / 1ps

module tpu_post_synth_tb;

    // ========================================================================
    // Parameters
    // ========================================================================
    parameter CLK_PERIOD = 20;   // 50 MHz

    // ========================================================================
    // DUT Signals (chip-level ports with IO pads)
    // ========================================================================
    reg  clk_pad;
    reg  srstn_pad;
    reg  tpu_start_pad;
    wire tpu_done_pad;

    // ========================================================================
    // Clock Generation — 50 MHz
    // ========================================================================
    initial clk_pad = 0;
    always #(CLK_PERIOD/2) clk_pad = ~clk_pad;

    // ========================================================================
    // DUT Instantiation — Post-Synthesis Netlist
    // ========================================================================
    tpu_chip u_dut (
        .clk_pad      (clk_pad),
        .srstn_pad    (srstn_pad),
        .tpu_start_pad(tpu_start_pad),
        .tpu_done_pad (tpu_done_pad)
    );

    // ========================================================================
    // SRAM Preloading — Via hierarchical path into netlist
    // ========================================================================
    // Note: The post-synthesis netlist flattens the hierarchy, so the
    // hierarchical paths to SRAM memories may differ.
    // Use `$readmemh` or adjust paths based on your synthesized netlist.
    //
    // The SRAM behavioral model stores data in:
    //   <instance>.i_SRAM_1P_behavioral_bm_bist.mem[addr]
    //
    // In the post-synth netlist, the SRAM instance paths will be like:
    //   u_dut.u_sram_weight.i_SRAM_1P_behavioral_bm_bist.mem
    //   u_dut.u_sram_data.i_SRAM_1P_behavioral_bm_bist.mem

    integer i;
    reg [63:0] weight_word;
    reg [63:0] data_word;

    // ========================================================================
    // Test — Basic Smoke Test (Identity × Sequential)
    // ========================================================================
    initial begin
        $dumpfile("tpu_post_synth.vcd");
        $dumpvars(0, tpu_post_synth_tb);

        $display("============================================================");
        $display("  TPU 8x8 — Post-Synthesis Gate-Level Testbench");
        $display("  IHP SG13G2 130nm Technology");
        $display("============================================================");

        // --------------------------------------------------------------------
        // Reset
        // --------------------------------------------------------------------
        srstn_pad     = 0;
        tpu_start_pad = 0;
        repeat (10) @(posedge clk_pad);
        srstn_pad = 1;
        repeat (5) @(posedge clk_pad);
        $display("[%0t] Reset released", $time);

        // --------------------------------------------------------------------
        // Load Weight SRAM — Identity matrix
        // Row i: weight[i][i] = 1, rest = 0
        // 64-bit word: {w1[31:0], w0[31:0]}
        // w0 = {col0, col1, col2, col3}, w1 = {col4, col5, col6, col7}
        // --------------------------------------------------------------------
        for (i = 0; i < 8; i = i + 1) begin
            weight_word = 64'h0;
            // Set the identity element (value=1) at the correct byte position
            if (i < 4)
                weight_word[31 - i*8 -: 8] = 8'd1;  // in w0 (lower 32 bits)
            else
                weight_word[63 - (i-4)*8 -: 8] = 8'd1;  // in w1 (upper 32 bits)

            // Try hierarchical path for post-synth netlist
            // This path may need adjustment based on the actual netlist structure
            u_dut.u_tpu_top.u_sram_weight.i_SRAM_1P_behavioral_bm_bist.memory[i] = weight_word;
        end
        $display("[%0t] Weight SRAM loaded (Identity)", $time);

        // --------------------------------------------------------------------
        // Load Data SRAM — Sequential values 1..64
        // 64-bit word: {d1[31:0], d0[31:0]}
        // d0 = {row0, row1, row2, row3}, d1 = {row4, row5, row6, row7}
        // Each address holds one column of the data matrix
        // --------------------------------------------------------------------
        for (i = 0; i < 8; i = i + 1) begin
            data_word = {
                8'(4*8 + i + 1), 8'(5*8 + i + 1),
                8'(6*8 + i + 1), 8'(7*8 + i + 1),
                8'(0*8 + i + 1), 8'(1*8 + i + 1),
                8'(2*8 + i + 1), 8'(3*8 + i + 1)
            };
            u_dut.u_tpu_top.u_sram_data.i_SRAM_1P_behavioral_bm_bist.memory[i] = data_word;
        end
        $display("[%0t] Data SRAM loaded (Sequential 1..64)", $time);

        // --------------------------------------------------------------------
        // Start TPU
        // --------------------------------------------------------------------
        @(posedge clk_pad);
        tpu_start_pad = 1;
        @(posedge clk_pad);
        tpu_start_pad = 0;
        $display("[%0t] TPU start asserted", $time);

        // --------------------------------------------------------------------
        // Wait for tpu_done with timeout
        // --------------------------------------------------------------------
        fork
            begin
                wait (tpu_done_pad == 1);
                $display("[%0t] TPU DONE asserted — Post-synth test PASSED!", $time);
            end
            begin
                repeat (10000) @(posedge clk_pad);
                $display("[%0t] ERROR: Timeout — tpu_done not asserted!", $time);
            end
        join_any
        disable fork;

        repeat (20) @(posedge clk_pad);

        $display("============================================================");
        $display("  Post-Synthesis Simulation Complete");
        $display("============================================================");

        $finish;
    end

    // ========================================================================
    // Optional: Monitor key signals
    // ========================================================================
    initial begin
        forever begin
            @(posedge clk_pad);
            if (tpu_done_pad)
                $display("[%0t] >>> tpu_done_pad = 1", $time);
        end
    end

endmodule
