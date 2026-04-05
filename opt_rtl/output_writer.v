// ============================================================================
// Module      : output_writer
// Description : Parameterized output demux for writing systolic results to SRAM
// Technology  : IHP SG13G2 130nm
//
// Routes quantized results from the systolic array to 3 output SRAM banks
// (A, B, C) based on the current data_set and result_index.
//
// Key Improvements over original write_out.v:
//   - De-duplicated: single bank-write logic reused for all 3 banks
//   - All index bounds derived from ARRAY_SIZE
//   - Output flip-flops retained for clean SRAM write timing
//   - Active-low write enable convention preserved for SRAM compatibility
//
// Result Mapping (for 8×8 array, 2 data sets):
//   data_set=0: diagonals 0..14  → Bank A (indices 0..7), Bank B (indices 8..14)
//   data_set=1: diagonals 0..14  → Bank B (indices 0..6), Bank C (indices 0..14)
// ============================================================================

module output_writer #(
    parameter ARRAY_SIZE        = 8,
    parameter OUTPUT_DATA_WIDTH = 16
)(
    input  wire clk,
    input  wire rst_n,

    // From controller
    input  wire        sram_write_enable,
    input  wire [1:0]  data_set,
    input  wire [5:0]  result_index,

    // Quantized data from quantizer
    input  wire signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] quantized_data,

    // Bank A output
    output reg         sram_write_enable_a0,
    output reg  [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_a,
    output reg  [5:0]  sram_waddr_a,

    // Bank B output
    output reg         sram_write_enable_b0,
    output reg  [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_b,
    output reg  [5:0]  sram_waddr_b,

    // Bank C output
    output reg         sram_write_enable_c0,
    output reg  [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_c,
    output reg  [5:0]  sram_waddr_c
);

    localparam MAX_INDEX  = ARRAY_SIZE - 1;
    localparam DIAG_COUNT = 2 * ARRAY_SIZE - 1;  // 15 for 8×8
    localparam TOTAL_WIDTH = ARRAY_SIZE * OUTPUT_DATA_WIDTH;

    // ========================================================================
    // Bank Write Logic — parameterized, reusable per bank
    // ========================================================================
    // Computes write data and address for a given bank based on region bounds.
    // A bank "owns" results where result_index falls within its region.

    // Next-state registers
    reg         we_a_nxt, we_b_nxt, we_c_nxt;
    reg [TOTAL_WIDTH-1:0] wdata_a_nxt, wdata_b_nxt, wdata_c_nxt;
    reg [5:0]   waddr_a_nxt, waddr_b_nxt, waddr_c_nxt;

    integer i;

    // ========================================================================
    // Combinational: data packing with diagonal re-ordering
    // ========================================================================
    // The quantized_data is already in PE-order. We need to re-pack it
    // with the correct number of valid elements per diagonal.

    reg [TOTAL_WIDTH-1:0] packed_data;

    always @(*) begin
        packed_data = {TOTAL_WIDTH{1'b0}};
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
            if (result_index < ARRAY_SIZE) begin
                // Upper diagonals: (result_index + 1) valid elements
                if (i <= result_index)
                    packed_data[(MAX_INDEX-i)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]
                        = quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
            end else begin
                // Lower diagonals: split between two regions
                if (i < DIAG_COUNT[5:0] - result_index)
                    packed_data[(MAX_INDEX-i)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]
                        = quantized_data[(i + 1 + (result_index - ARRAY_SIZE))*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
            end
        end
    end

    reg [TOTAL_WIDTH-1:0] packed_data_lower;

    always @(*) begin
        packed_data_lower = {TOTAL_WIDTH{1'b0}};
        if (result_index >= ARRAY_SIZE) begin
            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                if (i <= result_index - ARRAY_SIZE)
                    packed_data_lower[(MAX_INDEX-i)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]
                        = quantized_data[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
            end
        end
    end

    // ========================================================================
    // Bank Assignment Logic
    // ========================================================================
    always @(*) begin
        // Defaults: write disabled (active-low: 1 = not writing)
        we_a_nxt    = 1'b1;
        we_b_nxt    = 1'b1;
        we_c_nxt    = 1'b1;
        wdata_a_nxt = {TOTAL_WIDTH{1'b0}};
        wdata_b_nxt = {TOTAL_WIDTH{1'b0}};
        wdata_c_nxt = {TOTAL_WIDTH{1'b0}};
        waddr_a_nxt = 6'd0;
        waddr_b_nxt = 6'd0;
        waddr_c_nxt = 6'd0;

        if (sram_write_enable) begin
            case (data_set)
                2'd0: begin
                    // Data set 0: Bank A gets all upper diags + upper part of lower diags
                    //              Bank B gets lower part of lower diags
                    if (result_index < ARRAY_SIZE) begin
                        // Pure upper diagonal → Bank A only
                        we_a_nxt    = 1'b0;
                        wdata_a_nxt = packed_data;
                        waddr_a_nxt = result_index;
                    end else begin
                        // Mixed diagonal → upper portion to Bank A, lower to Bank B
                        we_a_nxt    = 1'b0;
                        wdata_a_nxt = packed_data;
                        waddr_a_nxt = result_index;

                        we_b_nxt    = 1'b0;
                        wdata_b_nxt = packed_data_lower;
                        waddr_b_nxt = result_index - ARRAY_SIZE;
                    end
                end

                2'd1: begin
                    // Data set 1: Bank C gets upper diags + upper part of lower diags
                    //             Bank B gets lower part that belongs to data_set 1
                    if (result_index < ARRAY_SIZE) begin
                        // Upper diagonal → Bank C
                        we_c_nxt    = 1'b0;
                        wdata_c_nxt = packed_data;
                        waddr_c_nxt = result_index;

                        // Also complete Bank B from data_set 0's lower region
                        if (result_index < ARRAY_SIZE - 1) begin
                            we_b_nxt    = 1'b0;
                            // Pack remaining elements for Bank B
                            wdata_b_nxt = {TOTAL_WIDTH{1'b0}};
                            for (i = 0; i < ARRAY_SIZE; i = i + 1) begin
                                if (i < ARRAY_SIZE - result_index - 1)
                                    wdata_b_nxt[(MAX_INDEX-i)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]
                                        = quantized_data[(i + 1 + result_index)*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH];
                            end
                            waddr_b_nxt = result_index + ARRAY_SIZE;
                        end
                    end else begin
                        // Lower diagonal → Bank C
                        we_c_nxt    = 1'b0;
                        wdata_c_nxt = packed_data;
                        waddr_c_nxt = result_index;
                    end
                end

                default: begin
                    // No writes for invalid data_set
                end
            endcase
        end
    end

    // ========================================================================
    // Output Registers (for SRAM write timing)
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            sram_write_enable_a0 <= 1'b1;  // Active-low: 1 = disabled
            sram_write_enable_b0 <= 1'b1;
            sram_write_enable_c0 <= 1'b1;
            sram_wdata_a         <= {TOTAL_WIDTH{1'b0}};
            sram_wdata_b         <= {TOTAL_WIDTH{1'b0}};
            sram_wdata_c         <= {TOTAL_WIDTH{1'b0}};
            sram_waddr_a         <= 6'd0;
            sram_waddr_b         <= 6'd0;
            sram_waddr_c         <= 6'd0;
        end else begin
            sram_write_enable_a0 <= we_a_nxt;
            sram_write_enable_b0 <= we_b_nxt;
            sram_write_enable_c0 <= we_c_nxt;
            sram_wdata_a         <= wdata_a_nxt;
            sram_wdata_b         <= wdata_b_nxt;
            sram_wdata_c         <= wdata_c_nxt;
            sram_waddr_a         <= waddr_a_nxt;
            sram_waddr_b         <= waddr_b_nxt;
            sram_waddr_c         <= waddr_c_nxt;
        end
    end

endmodule
