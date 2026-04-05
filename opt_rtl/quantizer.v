// ============================================================================
// Module      : quantizer
// Description : Pipelined saturation/clipping unit (accumulator → output width)
// Technology  : IHP SG13G2 130nm
//
// PPA Round 2: Replaced full 21-bit comparators with 5-bit overflow detection.
// Only the MSBs above the output width need checking for saturation.
// ============================================================================

module quantizer #(
    parameter ARRAY_SIZE        = 8,
    parameter DATA_WIDTH        = 8,
    parameter OUTPUT_DATA_WIDTH = 16,
    parameter PIPELINE          = 1
)(
    input  wire clk,
    input  wire rst_n,

    input  wire signed [ARRAY_SIZE*(DATA_WIDTH+DATA_WIDTH+5)-1:0]   ori_data,
    output wire signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0]           quantized_data
);

    localparam ACCUM_WIDTH    = DATA_WIDTH + DATA_WIDTH + 5;  // 21 for INT8
    localparam OVERFLOW_BITS  = ACCUM_WIDTH - OUTPUT_DATA_WIDTH; // 5 bits to check

    // ========================================================================
    // Optimized Saturation — check only overflow bits (not full comparators)
    // ========================================================================
    reg signed [OUTPUT_DATA_WIDTH-1:0] sat_result [0:ARRAY_SIZE-1];

    integer i;
    always @(*) begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : sat_loop
            // Extract the accumulator value
            // Sign bit
            if (!ori_data[(i+1)*ACCUM_WIDTH - 1]) begin
                // Positive number — overflow if any of the upper bits (above OUTPUT_DATA_WIDTH-1) are set
                if (|ori_data[i*ACCUM_WIDTH + OUTPUT_DATA_WIDTH - 1 +: OVERFLOW_BITS])
                    sat_result[i] = {1'b0, {(OUTPUT_DATA_WIDTH-1){1'b1}}};  // +SAT_MAX
                else
                    sat_result[i] = ori_data[i*ACCUM_WIDTH +: OUTPUT_DATA_WIDTH];
            end else begin
                // Negative number — overflow if any of the upper bits (above OUTPUT_DATA_WIDTH-1) are 0
                if (~(&ori_data[i*ACCUM_WIDTH + OUTPUT_DATA_WIDTH - 1 +: OVERFLOW_BITS]))
                    sat_result[i] = {1'b1, {(OUTPUT_DATA_WIDTH-1){1'b0}}};  // -SAT_MIN
                else
                    sat_result[i] = ori_data[i*ACCUM_WIDTH +: OUTPUT_DATA_WIDTH];
            end
        end
    end

    // ========================================================================
    // Pipeline Register
    // ========================================================================
    generate
        if (PIPELINE) begin : gen_pipelined
            reg signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] quantized_reg;

            integer pi;
            always @(posedge clk) begin
                if (!rst_n) begin
                    quantized_reg <= {(ARRAY_SIZE * OUTPUT_DATA_WIDTH){1'b0}};
                end else begin
                    for (pi = 0; pi < ARRAY_SIZE; pi = pi + 1)
                        quantized_reg[pi*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] <= sat_result[pi];
                end
            end

            assign quantized_data = quantized_reg;
        end else begin : gen_combinational
            genvar ci;
            for (ci = 0; ci < ARRAY_SIZE; ci = ci + 1) begin : comb_assign
                assign quantized_data[ci*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] = sat_result[ci];
            end
        end
    endgenerate

endmodule
