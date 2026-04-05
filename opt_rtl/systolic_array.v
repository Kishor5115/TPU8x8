// ============================================================================
// Module      : systolic_array
// Description : 8×8 Weight-Stationary Systolic Array (Google TPU v1 style)
// Technology  : IHP SG13G2 130nm
//
// === Architectural Improvements (Based on ISCA 2017 TPU paper) ===
//
//  Fix 1 [P2] — Diagonal Wavefront Input Skewing:
//    Row i receives its activation i cycles LATER than row 0.
//    This matches the real TPU "diagonal wavefront" execution, where:
//      - Activation from host enters row 0 at cycle T
//      - Activation enters row 1 at cycle T+1, row 2 at T+2, etc.
//    Without this, all rows receive the same activation simultaneously,
//    which breaks the systolic accumulation correctness for matrix multiply.
//
//  Fix 2 [P5] — 2-Stage Pipelined Readout:
//    Previously, all 64 PE outputs were muxed in a single register stage.
//    Now split into:
//      Stage 1: Compute per-row column index and latch row accumulator.
//      Stage 2: Pack all 8 row results into result_out.
//    This cuts the readout MUX depth in half, improving Fmax significantly.
//
//  Fix 3 [P3] — Shadow Weight Enable Pass-through:
//    New `shadow_weight_en` and `weight_swap` ports pass PE-level signals
//    for double-buffered weight loading.
//
// Dataflow (corrected):
//   - Weights: loaded column-by-column via weight_in[col], held stationary.
//   - Activations: staggered per-row via skew registers.
//   - PE chain: data flows left→right via registered data_out.
//   - Result readout: diagonal, 2-stage pipelined.
// ============================================================================

module systolic_array #(
    parameter ARRAY_SIZE      = 8,
    parameter SRAM_DATA_WIDTH = 32,
    parameter DATA_WIDTH      = 8,
    parameter ACCUM_WIDTH     = DATA_WIDTH + DATA_WIDTH + 5
)(
    input  wire clk,
    input  wire rst_n,

    // Control (registered internally at array boundary)
    input  wire mac_en,
    input  wire clear,

    // Weight input (2 × 32-bit SRAM words = 8 × 8-bit weights)
    input  wire [SRAM_DATA_WIDTH-1:0] weight_data_0,
    input  wire [SRAM_DATA_WIDTH-1:0] weight_data_1,
    input  wire                       weight_en,         // Load active weight
    input  wire                       shadow_weight_en,  // [P3] Load shadow weight
    input  wire                       weight_swap,       // [P3] Swap shadow→active

    // Activation input (2 × 32-bit = 8 × 8-bit activations)
    input  wire [SRAM_DATA_WIDTH-1:0] act_data_0,
    input  wire [SRAM_DATA_WIDTH-1:0] act_data_1,

    // Result readout
    input  wire [5:0]                                 result_index,
    output reg  signed [ARRAY_SIZE*ACCUM_WIDTH-1:0]   result_out
);

    localparam HALF = ARRAY_SIZE / 2;

    // ========================================================================
    // Register control signals at array boundary (decouples controller timing)
    // ========================================================================
    reg mac_en_r, clear_r, weight_en_r, shadow_weight_en_r, weight_swap_r;

    always @(posedge clk) begin
        if (!rst_n) begin
            mac_en_r           <= 1'b0;
            clear_r            <= 1'b0;
            weight_en_r        <= 1'b0;
            shadow_weight_en_r <= 1'b0;
            weight_swap_r      <= 1'b0;
        end else begin
            mac_en_r           <= mac_en;
            clear_r            <= clear;
            weight_en_r        <= weight_en;
            shadow_weight_en_r <= shadow_weight_en;
            weight_swap_r      <= weight_swap;
        end
    end

    // ========================================================================
    // Input Unpacking — extract 8-bit values from two 32-bit SRAM words
    // Packing: MSB-first: w[31:24]=col0, [23:16]=col1, [15:8]=col2, [7:0]=col3
    // ========================================================================
    wire signed [DATA_WIDTH-1:0] weight_in [0:ARRAY_SIZE-1];
    wire signed [DATA_WIDTH-1:0] data_in   [0:ARRAY_SIZE-1];

    genvar ug;
    generate
        for (ug = 0; ug < HALF; ug = ug + 1) begin : unpack
            assign weight_in[ug]        = weight_data_0[SRAM_DATA_WIDTH - 1 - DATA_WIDTH*ug -: DATA_WIDTH];
            assign weight_in[ug + HALF] = weight_data_1[SRAM_DATA_WIDTH - 1 - DATA_WIDTH*ug -: DATA_WIDTH];
            assign data_in[ug]          = act_data_0[SRAM_DATA_WIDTH - 1 - DATA_WIDTH*ug -: DATA_WIDTH];
            assign data_in[ug + HALF]   = act_data_1[SRAM_DATA_WIDTH - 1 - DATA_WIDTH*ug -: DATA_WIDTH];
        end
    endgenerate

    // ========================================================================
    // Stage 0: Register raw SRAM inputs (captures SRAM output timing)
    // ========================================================================
    reg signed [DATA_WIDTH-1:0] weight_reg [0:ARRAY_SIZE-1];
    reg signed [DATA_WIDTH-1:0] data_reg   [0:ARRAY_SIZE-1];

    integer ri;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (ri = 0; ri < ARRAY_SIZE; ri = ri + 1) begin
                weight_reg[ri] <= {DATA_WIDTH{1'b0}};
                data_reg[ri]   <= {DATA_WIDTH{1'b0}};
            end
        end else begin
            for (ri = 0; ri < ARRAY_SIZE; ri = ri + 1) begin
                weight_reg[ri] <= weight_in[ri];
                data_reg[ri]   <= data_in[ri];
            end
        end
    end

    // ========================================================================
    // [P2] DIAGONAL WAVEFRONT SKEW REGISTERS
    // ========================================================================
    // Row i receives activations i cycles LATER than row 0.
    // data_skew[row][0] = registered SRAM input
    // data_skew[row][k] = data_skew[row][k-1] delayed by 1 cycle
    // Row i col-0 PE is fed by data_skew[i][i].
    //
    // This creates the diagonal wave in the array:
    //   Cycle 0: Row 0 computes with act[0], rows 1-7 idle
    //   Cycle 1: Row 0 computes with act[1], Row 1 starts with act[0]
    //   ...etc.
    //
    // Maximum skew registers needed = ARRAY_SIZE-1 = 7 for row 7
    // Total skew FFs = sum(0..7) = 28 FFs (very cheap!)
    // ========================================================================
    // data_skew[i][j]: row i, j-th delay stage
    reg signed [DATA_WIDTH-1:0] data_skew [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    integer sk_i, sk_j;
    always @(posedge clk) begin
        if (!rst_n) begin
            for (sk_i = 0; sk_i < ARRAY_SIZE; sk_i = sk_i + 1)
                for (sk_j = 0; sk_j < ARRAY_SIZE; sk_j = sk_j + 1)
                    data_skew[sk_i][sk_j] <= {DATA_WIDTH{1'b0}};
        end else begin
            for (sk_i = 0; sk_i < ARRAY_SIZE; sk_i = sk_i + 1) begin
                data_skew[sk_i][0] <= data_reg[sk_i];  // Stage 0: registered input
                for (sk_j = 1; sk_j < ARRAY_SIZE; sk_j = sk_j + 1)
                    data_skew[sk_i][sk_j] <= data_skew[sk_i][sk_j-1];  // Shift
            end
        end
    end

    // ========================================================================
    // PE Grid — 8×8 Weight-Stationary Array
    // Connections:
    //   - Weight: each COLUMN j receives weight_reg[j] (same weight for all rows in that col)
    //   - Activation: row i col 0 receives data_skew[i][i] (diagonally skewed)
    //   - Activation: col j>0 receives pe_data_out[i][j-1] (registered pass-through from left PE)
    // ========================================================================
    wire signed [DATA_WIDTH-1:0]  pe_data_out  [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];
    wire signed [ACCUM_WIDTH-1:0] pe_accum_out [0:ARRAY_SIZE-1][0:ARRAY_SIZE-1];

    genvar gi, gj;
    generate
        for (gi = 0; gi < ARRAY_SIZE; gi = gi + 1) begin : pe_row
            for (gj = 0; gj < ARRAY_SIZE; gj = gj + 1) begin : pe_col

                // [P2] Activation source:
                //   Col 0: diagonally-skewed input (row gi delayed by gi cycles)
                //   Col j>0: registered pass-through from left neighbor PE
                wire signed [DATA_WIDTH-1:0] din;
                if (gj == 0) begin : first_col
                    assign din = data_skew[gi][gi];  // Key change: skewed input
                end else begin : other_cols
                    assign din = pe_data_out[gi][gj-1];
                end

                pe #(
                    .DATA_WIDTH  (DATA_WIDTH),
                    .ACCUM_WIDTH (ACCUM_WIDTH)
                ) u_pe (
                    .clk              (clk),
                    .rst_n            (rst_n),

                    // Weight for this column: stationary across all rows
                    .weight_in        (weight_reg[gj]),
                    .weight_en        (weight_en_r),
                    .shadow_weight_en (shadow_weight_en_r),  // [P3]
                    .weight_swap      (weight_swap_r),       // [P3]

                    .data_in          (din),
                    .data_out         (pe_data_out[gi][gj]),

                    .mac_en           (mac_en_r),
                    .clear            (clear_r),

                    .accum_out        (pe_accum_out[gi][gj])
                );
            end
        end
    endgenerate

    // ========================================================================
    // [P5] 2-STAGE PIPELINED READOUT
    // ========================================================================
    // Stage 1: For each row, compute the target column index and latch the
    //          PE accumulator for that diagonal (one register per row).
    // Stage 2: Pack all 8 row results into result_out (another register stage).
    //
    // This splits a wide 64-input MUX into 8 narrow 8-input MUXes + packing,
    // cutting the combinational depth roughly in half → better Fmax.
    // ========================================================================

    // Stage 1 registered outputs (one result per row)
    reg signed [ACCUM_WIDTH-1:0] stage1_result [0:ARRAY_SIZE-1];

    always @(posedge clk) begin
        if (!rst_n) begin
            for (ri = 0; ri < ARRAY_SIZE; ri = ri + 1)
                stage1_result[ri] <= {ACCUM_WIDTH{1'b0}};
        end else begin : s1_readout
            integer row_i;
            for (row_i = 0; row_i < ARRAY_SIZE; row_i = row_i + 1) begin
                // Diagonal readout: for diagonal result_index k, row i reads
                // from column j where j = (k - row_i) if in [0, N-1], else
                // j = (k + N - row_i) for lower region.
                if (result_index >= row_i && (result_index - row_i) < ARRAY_SIZE) begin
                    // Upper region: direct subtraction gives valid column
                    stage1_result[row_i] <= pe_accum_out[row_i][result_index - row_i];
                end else if ((result_index + ARRAY_SIZE) >= row_i &&
                             (result_index + ARRAY_SIZE - row_i) < ARRAY_SIZE) begin
                    // Lower region: offset by N to wrap
                    stage1_result[row_i] <= pe_accum_out[row_i][result_index + ARRAY_SIZE - row_i];
                end else begin
                    stage1_result[row_i] <= {ACCUM_WIDTH{1'b0}};
                end
            end
        end
    end

    // Stage 2: Pack row results into the output bus
    always @(posedge clk) begin
        if (!rst_n) begin
            result_out <= {(ARRAY_SIZE * ACCUM_WIDTH){1'b0}};
        end else begin
            for (ri = 0; ri < ARRAY_SIZE; ri = ri + 1)
                result_out[ri*ACCUM_WIDTH +: ACCUM_WIDTH] <= stage1_result[ri];
        end
    end

endmodule
