// ============================================================================
// Testbench     : tpu_tb (Converged Master Testbench)
// Description   : Unified verification of tpu_top (RTL) or tpu_chip (Gate-level)
// Technology    : IHP SG13G2 130nm
// 
// Modes:
//   - Default: Tests RTL (tpu_top)
//   - +define+GSR_NETLIST: Tests Gate-level netlist (tpu_chip)
//
// Verification Strategy:
//   Detailed system-level verification with optional cycle-by-cycle MAC tracing.
// ============================================================================

`timescale 1ns / 1ps

module tpu_tb;

    // ========================================================================
    // Parameters & Defines
    // ========================================================================
    parameter ARRAY_SIZE        = 8;
    parameter SRAM_DATA_WIDTH   = 32;
    parameter DATA_WIDTH        = 8;
    parameter OUTPUT_DATA_WIDTH = 16;
    parameter CLK_PERIOD        = 10;

    // Toggle this to see cycle-by-cycle MAC math in the log
    parameter ENABLE_MAC_TRACE  = 1; 

    // ========================================================================
    // DUT Interconnect
    // ========================================================================
    reg  clk, srstn, tpu_start;
    wire tpu_done;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

`ifdef GSR_NETLIST
    supply1 vdd;
    supply0 vss;

    // Chip-level ports for Gate-level simulation
    tpu_chip u_dut (
        .clk_pad(clk),
        .srstn_pad(srstn),
        .tpu_start_pad(tpu_start),
        .tpu_done_pad(tpu_done),
        .\IO_CORNER_NORTH_WEST_INST.vdd_RING (vdd),
        .\IO_CORNER_NORTH_WEST_INST.iovdd_RING (vdd),
        .\IO_CORNER_NORTH_WEST_INST.vss_RING (vss),
        .\IO_CORNER_NORTH_WEST_INST.iovss_RING (vss)
    );
`else
    // RTL-level ports
    tpu_top #(
        .ARRAY_SIZE(ARRAY_SIZE)
    ) u_dut (
        .clk(clk), .srstn(srstn), .tpu_start(tpu_start), .tpu_done(tpu_done)
    );
`endif

    // ========================================================================
    // Memory Path Redefinition (RTL vs Gate)
    // ========================================================================
`ifdef GSR_NETLIST
    `define WEIGHT_MEM u_dut.\u_tpu_top/u_sram_weight .i_SRAM_1P_behavioral_bm_bist.memory
    `define DATA_MEM   u_dut.\u_tpu_top/u_sram_data .i_SRAM_1P_behavioral_bm_bist.memory
    `define OUT_A0_MEM u_dut.\u_tpu_top/output_a_srams[0].u_sram_out_a .i_SRAM_1P_behavioral_bm_bist.memory
    `define OUT_A1_MEM u_dut.\u_tpu_top/output_a_srams[1].u_sram_out_a .i_SRAM_1P_behavioral_bm_bist.memory
`else
    `define WEIGHT_MEM u_dut.u_sram_weight.i_SRAM_1P_behavioral_bm_bist.memory
    `define DATA_MEM   u_dut.u_sram_data.i_SRAM_1P_behavioral_bm_bist.memory
    `define OUT_A0_MEM u_dut.output_a_srams[0].u_sram_out_a.i_SRAM_1P_behavioral_bm_bist.memory
    `define OUT_A1_MEM u_dut.output_a_srams[1].u_sram_out_a.i_SRAM_1P_behavioral_bm_bist.memory
`endif

    // ========================================================================
    // Test Variables
    // ========================================================================
    integer i, j, k;
    integer errors, test_errors, test_num, total_tests;
    integer rand_seed;

    reg signed [7:0]  weight_matrix [0:7][0:7];
    reg signed [7:0]  data_matrix   [0:7][0:7];
    reg signed [31:0] golden        [0:7][0:7];
    reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] golden_packed [0:7];
    reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] trans_golden [0:14];

    // --- Reset ---
    task reset_dut;
    begin
        srstn = 0; tpu_start = 0;
        repeat (5) @(posedge clk);
        srstn = 1;
        repeat (2) @(posedge clk);
    end
    endtask

    // --- Load weight SRAM ---
    task load_weight_sram;
        integer addr, ofs;
        reg [7:0] w0_byte [0:3], w1_byte [0:3];
    begin
        for (addr = 0; addr < 256; addr = addr + 1) `WEIGHT_MEM[addr] = 64'h0;
        for (addr = 0; addr < ARRAY_SIZE + 7; addr = addr + 1) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (addr >= i && (addr - i) < ARRAY_SIZE) w0_byte[i] = weight_matrix[i][addr - i];
                else w0_byte[i] = 0;
                ofs = i + 4;
                if (addr >= ofs && (addr - ofs) < ARRAY_SIZE) w1_byte[i] = weight_matrix[ofs][addr - ofs];
                else w1_byte[i] = 0;
            end
            `WEIGHT_MEM[addr] = {w1_byte[0], w1_byte[1], w1_byte[2], w1_byte[3], w0_byte[0], w0_byte[1], w0_byte[2], w0_byte[3]};
        end
    end
    endtask

    // --- Load data SRAM ---
    task load_data_sram;
        integer addr, ofs;
        reg [7:0] d0_byte [0:3], d1_byte [0:3];
    begin
        for (addr = 0; addr < 256; addr = addr + 1) `DATA_MEM[addr] = 64'h0;
        for (addr = 0; addr < ARRAY_SIZE + 7; addr = addr + 1) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (addr >= i && (addr - i) < ARRAY_SIZE) d0_byte[i] = data_matrix[i][addr - i];
                else d0_byte[i] = 0;
                ofs = i + 4;
                if (addr >= ofs && (addr - ofs) < ARRAY_SIZE) d1_byte[i] = data_matrix[ofs][addr - ofs];
                else d1_byte[i] = 0;
            end
            `DATA_MEM[addr] = {d1_byte[0], d1_byte[1], d1_byte[2], d1_byte[3], d0_byte[0], d0_byte[1], d0_byte[2], d0_byte[3]};
        end
    end
    endtask

    // --- Compute golden ---
    task compute_golden;
        reg signed [15:0] q_val;
    begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            golden_packed[i] = 0;
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                golden[i][j] = 0;
                for (k = 0; k < ARRAY_SIZE; k = k + 1)
                    golden[i][j] = golden[i][j] + ($signed(data_matrix[i][k]) * $signed(weight_matrix[j][k]));
                if (golden[i][j] > 32767) q_val = 16'sd32767;
                else if (golden[i][j] < -32768) q_val = -16'sd32768;
                else q_val = golden[i][j][15:0];
                golden_packed[i][(j+1)*OUTPUT_DATA_WIDTH-1 -: OUTPUT_DATA_WIDTH] = q_val;
            end
        end
    end
    endtask

    // --- Transform golden ---
    task golden_transform;
        integer this_k, this_i, this_j;
    begin
        for (this_k = 0; this_k < 2*ARRAY_SIZE-1; this_k = this_k + 1) trans_golden[this_k] = 0;
        for (this_k = 0; this_k < 2*ARRAY_SIZE-1; this_k = this_k + 1)
            for (this_i = ARRAY_SIZE-1; this_i >= 0; this_i = this_i - 1)
                for (this_j = ARRAY_SIZE-1; this_j >= 0; this_j = this_j - 1)
                    if ((this_i + this_j) == this_k)
                        trans_golden[this_k] = {golden_packed[this_i][(this_j+1)*OUTPUT_DATA_WIDTH-1 -: OUTPUT_DATA_WIDTH], trans_golden[this_k][(ARRAY_SIZE*16-1) -: (7*OUTPUT_DATA_WIDTH)]};
    end
    endtask

    // --- Run TPU ---
    task run_tpu;
    begin
        @(posedge clk); tpu_start = 1;
        @(posedge clk); tpu_start = 0;
        fork
            begin wait (tpu_done == 1); end
            begin repeat(5000) @(posedge clk); $display("TIMEOUT!"); $finish; end
`ifndef GSR_NETLIST
            if (ENABLE_MAC_TRACE) begin
                wait (u_dut.u_tpu_core.u_systolic.alu_start);
                $display("\n [TIME]  | [CYC] | [W(0,0)] | [D(0,0)] |  [PROD]  | [ACCUMULATOR]");
                $display("---------|-------|----------|----------|----------|--------------");
                forever begin
                    @(posedge clk);
                    if (u_dut.u_tpu_core.u_systolic.alu_start)
                        $display(" %7t |  %3d  |   %4d   |   %4d   | %8d | %12d", $time, u_dut.u_tpu_core.u_systolic.cycle_num, $signed(u_dut.u_tpu_core.u_systolic.weight_queue[0][0]), $signed(u_dut.u_tpu_core.u_systolic.data_queue[0][0]), $signed({ {8{u_dut.u_tpu_core.u_systolic.weight_queue[0][0][7]}}, u_dut.u_tpu_core.u_systolic.weight_queue[0][0] }) * $signed({ {8{u_dut.u_tpu_core.u_systolic.data_queue[0][0][7]}}, u_dut.u_tpu_core.u_systolic.data_queue[0][0] }), $signed(u_dut.u_tpu_core.u_systolic.matrix_mul_2D[0][0]));
                    if (tpu_done) break;
                end
            end
`endif
        join_any
        disable fork;
        repeat (5) @(posedge clk);
    end
    endtask

    // --- Verify ---
    task verify_result;
        integer addr;
        reg [127:0] actual_word, expected_word;
    begin
        test_errors = 0;
        for (addr = 0; addr < 2*ARRAY_SIZE-1; addr = addr + 1) begin
            actual_word = {`OUT_A1_MEM[addr], `OUT_A0_MEM[addr]};
            expected_word = trans_golden[addr];
            if (actual_word != expected_word) test_errors = test_errors + 1;
        end
        if (test_errors == 0) $display("  >>> TEST %0d PASSED!", test_num);
        else $display("  >>> TEST %0d FAILED with %0d errors", test_num, test_errors);
        errors = errors + test_errors;
    end
    endtask

    // ========================================================================
    // Main Test Loop
    // ========================================================================
    reg signed [7:0] stress_vectors [0:7];

    initial begin
        stress_vectors[0] = 127; stress_vectors[1] = -128; stress_vectors[2] = 85; stress_vectors[3] = -86;
        stress_vectors[4] = 64;  stress_vectors[5] = -1;   stress_vectors[6] = 123; stress_vectors[7] = -42;

        $dumpfile("tpu_master.vcd");
        $dumpvars(0, tpu_tb);

        $display("\n============================================================");
        $display("  MASTER TPU TESTBENCH: %s MODE", 
`ifdef GSR_NETLIST
            "GATE-LEVEL"
`else
            "RTL"
`endif
        );
        $display("============================================================\n");

        errors = 0; total_tests = 7;
        rand_seed = 32'h1A2B3C4D;

        // Test 1: Identity
        test_num = 1;
        for (i=0; i<8; i=i+1) for (j=0; j<8; j=j+1) begin
            weight_matrix[i][j] = (i==j) ? 1 : 0;
            data_matrix[i][j] = i*8+j+1;
        end
        reset_dut; load_weight_sram; load_data_sram; compute_golden; golden_transform; run_tpu; verify_result;

        // Test 2: Stress Vectors (Negative/Edge Cases)
        test_num = 2;
        for (i=0; i<8; i=i+1) for (j=0; j<8; j=j+1) begin
            weight_matrix[i][j] = stress_vectors[i];
            data_matrix[i][j] = stress_vectors[7-j];
        end
        reset_dut; load_weight_sram; load_data_sram; compute_golden; golden_transform; run_tpu; verify_result;

        // Test 3: All Zeros
        test_num = 3;
        for (i=0; i<8; i=i+1) for (j=0; j<8; j=j+1) begin weight_matrix[i][j] = 0; data_matrix[i][j] = 0; end
        reset_dut; load_weight_sram; load_data_sram; compute_golden; golden_transform; run_tpu; verify_result;

        // Test 4: Positive Saturation (force +32767 clamp)
        test_num = 4;
        for (i=0; i<8; i=i+1) for (j=0; j<8; j=j+1) begin
            weight_matrix[i][j] = 127;
            data_matrix[i][j] = 127;
        end
        reset_dut; load_weight_sram; load_data_sram; compute_golden; golden_transform; run_tpu; verify_result;

        // Test 5: Negative Saturation (force -32768 clamp)
        test_num = 5;
        for (i=0; i<8; i=i+1) for (j=0; j<8; j=j+1) begin
            weight_matrix[i][j] = 127;
            data_matrix[i][j] = -128;
        end
        reset_dut; load_weight_sram; load_data_sram; compute_golden; golden_transform; run_tpu; verify_result;

        // Test 6: Checkerboard signs (high cancellation / sign-mix case)
        test_num = 6;
        for (i=0; i<8; i=i+1) for (j=0; j<8; j=j+1) begin
            weight_matrix[i][j] = ((i+j)%2==0) ? 127 : -128;
            data_matrix[i][j] = ((i%2)==0) ? (j*7-28) : (28-j*7);
        end
        reset_dut; load_weight_sram; load_data_sram; compute_golden; golden_transform; run_tpu; verify_result;

        // Test 7: Pseudo-random signed matrix (deterministic seed)
        test_num = 7;
        for (i=0; i<8; i=i+1) begin
            for (j=0; j<8; j=j+1) begin
                rand_seed = $random(rand_seed);
                weight_matrix[i][j] = rand_seed[7:0];
                rand_seed = $random(rand_seed);
                data_matrix[i][j] = rand_seed[7:0];
            end
        end
        reset_dut; load_weight_sram; load_data_sram; compute_golden; golden_transform; run_tpu; verify_result;

        $display("\n============================================================");
        if (errors == 0) $display("  ALL %0d TESTS PASSED!", total_tests);
        else $display("  TOTAL ERRORS: %0d", errors);
        $display("============================================================\n");
        #100; $finish;
    end

endmodule
