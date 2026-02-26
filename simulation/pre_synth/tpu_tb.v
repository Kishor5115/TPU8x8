// ============================================================================
// Testbench     : tpu_tb (Pre-Synthesis)
// Description   : Full computation verification of tpu_top — 8×8 Systolic Array
// Technology    : IHP SG13G2 130nm
//
// Based on the reference testbench from:
//   github.com/abdelazeem201/Systolic-array-implementation-in-RTL-for-TPU
//
// Verification Strategy:
//   The input weight/data matrices must be loaded into SRAMs with diagonal
//   skewing (row i offset by i%4), matching the addr_sel module's staggered
//   address generation. The output SRAMs store results in anti-diagonal
//   order: output SRAM address k contains elements where i+j == k.
//   We compare the output SRAM contents against golden data transformed
//   into the same anti-diagonal layout.
//
// Usage: make sim
// ============================================================================

`timescale 1ns / 1ps

module tpu_tb;

    // ========================================================================
    // Parameters
    // ========================================================================
    parameter ARRAY_SIZE        = 8;
    parameter SRAM_DATA_WIDTH   = 32;
    parameter DATA_WIDTH        = 8;
    parameter OUTPUT_DATA_WIDTH = 16;
    parameter CLK_PERIOD        = 20;

    // ========================================================================
    // DUT
    // ========================================================================
    reg  clk, srstn, tpu_start;
    wire tpu_done;

    initial clk = 0;
    always #(CLK_PERIOD/2) clk = ~clk;

    tpu_top #(
        .ARRAY_SIZE       (ARRAY_SIZE),
        .SRAM_DATA_WIDTH  (SRAM_DATA_WIDTH),
        .DATA_WIDTH       (DATA_WIDTH),
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
    ) u_dut (
        .clk(clk), .srstn(srstn), .tpu_start(tpu_start), .tpu_done(tpu_done)
    );

    // ========================================================================
    // Test Variables
    // ========================================================================
    integer i, j, k;
    integer errors, test_errors, test_num, total_tests;

    reg signed [7:0]  weight_matrix [0:7][0:7];  // W
    reg signed [7:0]  data_matrix   [0:7][0:7];  // D
    reg signed [31:0] golden        [0:7][0:7];  // C = W × D (32-bit headroom)

    // Packed golden: each row is 128-bit = 8 × 16-bit values (like reference golden1/2/3)
    reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] golden_packed [0:7];

    // Anti-diagonal transformed golden (for comparison with output SRAMs)
    // 15 anti-diagonals (i+j = 0..14), each is 128 bits (8 × 16-bit)
    reg [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] trans_golden [0:14];

    // ========================================================================
    // Tasks
    // ========================================================================

    // --- Reset ---
    task reset_dut;
    begin
        srstn = 0; tpu_start = 0;
        repeat (5) @(posedge clk);
        srstn = 1;
        repeat (2) @(posedge clk);
    end
    endtask

    // --- Load weight SRAM with diagonal skewing ---
    // Our IHP design uses a single 64-bit SRAM with ONE address line (w0's).
    // memory[addr] = {w1[31:0], w0[31:0]}
    // w0 (rows 0-3): offset = i%4 = {0,1,2,3}
    // w1 (rows 4-7): offset = i%4 + 4 = {4,5,6,7} because addr_sel's
    //   4-address lag for w1 is NOT used (both w0/w1 read same address).
    task load_weight_sram;
        integer addr;
        integer ofs;
        reg [7:0] w0_byte [0:3];
        reg [7:0] w1_byte [0:3];
        reg [63:0] word;
    begin
        for (addr = 0; addr < 256; addr = addr + 1)
            u_dut.u_sram_weight.i_SRAM_1P_behavioral_bm_bist.memory[addr] = 64'h0;

        // w0 rows 0-3: need addresses 0..(8+3) = 0..10
        // w1 rows 4-7: need addresses 4..(8+7) = 4..14 (extra 4 offset)
        // Combined range: 0..14
        for (addr = 0; addr < ARRAY_SIZE + 7; addr = addr + 1) begin
            // w0: rows 0-3 with offset i
            for (i = 0; i < 4; i = i + 1) begin
                if (addr >= i && (addr - i) < ARRAY_SIZE)
                    w0_byte[i] = weight_matrix[i][addr - i];
                else
                    w0_byte[i] = 0;
            end
            // w1: rows 4-7 with offset (i+4)
            for (i = 0; i < 4; i = i + 1) begin
                ofs = i + 4;
                if (addr >= ofs && (addr - ofs) < ARRAY_SIZE)
                    w1_byte[i] = weight_matrix[i + 4][addr - ofs];
                else
                    w1_byte[i] = 0;
            end
            word = {w1_byte[0], w1_byte[1], w1_byte[2], w1_byte[3],
                    w0_byte[0], w0_byte[1], w0_byte[2], w0_byte[3]};
            u_dut.u_sram_weight.i_SRAM_1P_behavioral_bm_bist.memory[addr] = word;
        end
    end
    endtask

    // --- Load data SRAM with diagonal skewing ---
    // Same offset pattern as weight: d0 rows 0-3 offset i, d1 rows 4-7 offset (i+4)
    task load_data_sram;
        integer addr;
        integer ofs;
        reg [7:0] d0_byte [0:3];
        reg [7:0] d1_byte [0:3];
        reg [63:0] word;
    begin
        for (addr = 0; addr < 256; addr = addr + 1)
            u_dut.u_sram_data.i_SRAM_1P_behavioral_bm_bist.memory[addr] = 64'h0;

        for (addr = 0; addr < ARRAY_SIZE + 7; addr = addr + 1) begin
            for (i = 0; i < 4; i = i + 1) begin
                if (addr >= i && (addr - i) < ARRAY_SIZE)
                    d0_byte[i] = data_matrix[i][addr - i];
                else
                    d0_byte[i] = 0;
            end
            for (i = 0; i < 4; i = i + 1) begin
                ofs = i + 4;
                if (addr >= ofs && (addr - ofs) < ARRAY_SIZE)
                    d1_byte[i] = data_matrix[i + 4][addr - ofs];
                else
                    d1_byte[i] = 0;
            end
            word = {d1_byte[0], d1_byte[1], d1_byte[2], d1_byte[3],
                    d0_byte[0], d0_byte[1], d0_byte[2], d0_byte[3]};
            u_dut.u_sram_data.i_SRAM_1P_behavioral_bm_bist.memory[addr] = word;
        end
    end
    endtask

    // --- Compute golden result ---
    // Systolic dataflow: weight enters column j (flows down), data enters row i (flows right)
    // C[i][j] = Σ_k D[i][k] × W[j][k]  =  (D × Wᵀ)[i][j]
    task compute_golden;
        reg signed [15:0] q_val;
    begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            golden_packed[i] = 0;
            for (j = 0; j < ARRAY_SIZE; j = j + 1) begin
                golden[i][j] = 0;
                for (k = 0; k < ARRAY_SIZE; k = k + 1)
                    golden[i][j] = golden[i][j] +
                        ($signed(data_matrix[i][k]) * $signed(weight_matrix[j][k]));
                // Quantize: saturate 32b → 16b
                if (golden[i][j] > 32767)        q_val = 16'sd32767;
                else if (golden[i][j] < -32768)   q_val = -16'sd32768;
                else                              q_val = golden[i][j][15:0];
                // Pack into golden_packed[i] at column j position
                golden_packed[i][(j+1)*OUTPUT_DATA_WIDTH-1 -: OUTPUT_DATA_WIDTH] = q_val;
            end
        end
    end
    endtask

    // --- Transform golden into anti-diagonal layout ---
    // Matches write_out.v output ordering and golden_transform from reference TB
    // trans_golden[k] for anti-diagonal k where i+j==k
    task golden_transform;
        integer this_k, this_i, this_j;
    begin
        for (this_k = 0; this_k < 2*ARRAY_SIZE-1; this_k = this_k + 1)
            trans_golden[this_k] = 0;

        for (this_k = 0; this_k < 2*ARRAY_SIZE-1; this_k = this_k + 1)
            for (this_i = ARRAY_SIZE-1; this_i >= 0; this_i = this_i - 1)
                for (this_j = ARRAY_SIZE-1; this_j >= 0; this_j = this_j - 1)
                    if ((this_i + this_j) == this_k) begin
                        trans_golden[this_k] = {
                            golden_packed[this_i][(this_j+1)*OUTPUT_DATA_WIDTH-1 -: OUTPUT_DATA_WIDTH],
                            trans_golden[this_k][(ARRAY_SIZE*16-1) -: (7*OUTPUT_DATA_WIDTH)]
                        };
                    end
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
        join_any
        disable fork;
        repeat (5) @(posedge clk);
    end
    endtask

    // --- Verify output SRAMs against transformed golden ---
    // Read from output Bank A sub-SRAMs (2 × 64-bit = 128-bit per address)
    // output_a_srams[0] = bits [63:0], output_a_srams[1] = bits [127:64]
    task verify_result;
        integer addr;
        reg [127:0] actual_word;
        reg [127:0] expected_word;
    begin
        test_errors = 0;

        $display("  Verifying output SRAM Bank A (data_set=0):");
        for (addr = 0; addr < 2*ARRAY_SIZE-1; addr = addr + 1) begin
            // Read from 2 sub-SRAMs
            actual_word = {
                u_dut.output_a_srams[1].u_sram_out_a.i_SRAM_1P_behavioral_bm_bist.memory[addr],
                u_dut.output_a_srams[0].u_sram_out_a.i_SRAM_1P_behavioral_bm_bist.memory[addr]
            };
            expected_word = trans_golden[addr];

            if (actual_word == expected_word)
                $display("    Addr %2d: PASS", addr);
            else begin
                $display("    Addr %2d: MISMATCH", addr);
                $write("      Got:    ");
                for (i = ARRAY_SIZE; i > 0; i = i - 1)
                    $write("%6d ", $signed(actual_word[(i*OUTPUT_DATA_WIDTH-1) -: OUTPUT_DATA_WIDTH]));
                $write("\n");
                $write("      Expect: ");
                for (i = ARRAY_SIZE; i > 0; i = i - 1)
                    $write("%6d ", $signed(expected_word[(i*OUTPUT_DATA_WIDTH-1) -: OUTPUT_DATA_WIDTH]));
                $write("\n");
                test_errors = test_errors + 1;
            end
        end

        if (test_errors == 0)
            $display("  >>> TEST %0d PASSED — All %0d SRAM words match! <<<", test_num, 2*ARRAY_SIZE-1);
        else
            $display("  >>> TEST %0d: %0d / %0d SRAM words mismatched <<<",
                     test_num, test_errors, 2*ARRAY_SIZE-1);
        errors = errors + test_errors;
    end
    endtask

    // ========================================================================
    // Test Cases
    // ========================================================================

    task test_identity;
    begin
        test_num = 1;
        $display("\n============================================================");
        $display("  TEST %0d: Identity Weight × Sequential Data", test_num);
        $display("  W = I, D[i][j] = i*8+j+1  →  C = D×It = D");
        $display("============================================================");
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                weight_matrix[i][j] = (i == j) ? 8'd1 : 8'd0;
                data_matrix[i][j]   = i * 8 + j + 1;
            end
        reset_dut; load_weight_sram; load_data_sram;
        compute_golden; golden_transform; run_tpu;
        verify_result;
    end
    endtask

    task test_small_values;
    begin
        test_num = 2;
        $display("\n============================================================");
        $display("  TEST %0d: Small Values", test_num);
        $display("  W[i][j] = (i+j)%%3 + 1,  D[i][j] = (2i+j)%%3 + 1");
        $display("============================================================");
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                weight_matrix[i][j] = ((i + j) % 3) + 1;
                data_matrix[i][j]   = ((i * 2 + j) % 3) + 1;
            end
        reset_dut; load_weight_sram; load_data_sram;
        compute_golden; golden_transform; run_tpu;
        verify_result;
    end
    endtask

    task test_signed_values;
    begin
        test_num = 3;
        $display("\n============================================================");
        $display("  TEST %0d: Signed Values", test_num);
        $display("  W = ((i*13+j*7)%%61)-30, D = ((i*11+j*5)%%51)-25");
        $display("============================================================");
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                weight_matrix[i][j] = ((i * 13 + j * 7) % 61) - 30;
                data_matrix[i][j]   = ((i * 11 + j * 5) % 51) - 25;
            end
        reset_dut; load_weight_sram; load_data_sram;
        compute_golden; golden_transform; run_tpu;
        verify_result;
    end
    endtask

    task test_all_zeros;
    begin
        test_num = 4;
        $display("\n============================================================");
        $display("  TEST %0d: All Zeros", test_num);
        $display("============================================================");
        for (i = 0; i < 8; i = i + 1)
            for (j = 0; j < 8; j = j + 1) begin
                weight_matrix[i][j] = 0;
                data_matrix[i][j]   = 0;
            end
        reset_dut; load_weight_sram; load_data_sram;
        compute_golden; golden_transform; run_tpu;
        verify_result;
    end
    endtask

    // ========================================================================
    // Main
    // ========================================================================
    initial begin
        $dumpfile("tpu_pre_synth.vcd");
        $dumpvars(0, tpu_tb);

        $display("============================================================");
        $display("  TPU 8×8 — Pre-Synthesis Computation Verification");
        $display("  IHP SG13G2 130nm | Icarus Verilog");
        $display("  Golden: C = D × Wt  (verified against output SRAM)");
        $display("============================================================");

        errors = 0;
        total_tests = 4;

        test_identity;
        test_small_values;
        test_signed_values;
        test_all_zeros;

        $display("\n============================================================");
        if (errors == 0)
            $display("  ALL %0d TESTS PASSED — Computation Verified!", total_tests);
        else
            $display("  %0d TOTAL SRAM MISMATCHES across %0d tests — FAIL", errors, total_tests);
        $display("============================================================\n");
        #100; $finish;
    end

endmodule
