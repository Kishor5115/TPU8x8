// ============================================================================
// Module      : activation_pipe
// Description : Configurable activation function pipeline (post-quantizer)
// Technology  : IHP SG13G2 130nm
//
// === Motivation (from Google TPU v1 paper) ===
// After the Matrix Multiply Unit produces outputs and they are quantized,
// the "Activation Pipeline" applies non-linear functions (ReLU, sigmoid, tanh)
// before writing results back to the Unified Buffer (or output SRAMs here).
//
// The TPU v1 implements these in dedicated hardware so they are applied at
// full throughput (1 cycle) without GPU-style shader overhead.
//
// === Modes ===
//   2'b00: Passthrough — no activation (linear layers, output layer)
//   2'b01: ReLU       — max(0, x), near-zero area (just MSB-based mux)
//   2'b10: ReLU6      — clamp to [0, 6] (MobileNet-style networks)
//   2'b11: Reserved   — can be used for leaky ReLU or other custom functions
//
// === PPA Notes ===
//   - ReLU is essentially FREE area (1 mux per lane using sign bit)
//   - Pipeline register adds 1 cycle latency but allows Fmax improvement
//   - Can be clock-gated when mode=passthrough to save power
// ============================================================================

module activation_pipe #(
    parameter ARRAY_SIZE        = 8,
    parameter OUTPUT_DATA_WIDTH = 16
)(
    input  wire clk,
    input  wire rst_n,

    // Activation mode (from software/host config register)
    input  wire [1:0] mode,  // 00=pass, 01=ReLU, 10=ReLU6, 11=reserved

    // Input: quantized data from quantizer
    input  wire signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] data_in,

    // Output: activated data (registered, 1-cycle pipeline)
    output reg  signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] data_out
);

    // ========================================================================
    // Activation Function Constants
    // ========================================================================
    localparam signed [OUTPUT_DATA_WIDTH-1:0] ZERO      = {OUTPUT_DATA_WIDTH{1'b0}};
    // ReLU6: 6 in INT16 (assuming Q format where 1 LSB = 1 integer unit)
    localparam signed [OUTPUT_DATA_WIDTH-1:0] RELU6_MAX = 16'sd6;
    // Positive saturation limit for signed INT16
    localparam signed [OUTPUT_DATA_WIDTH-1:0] POS_MAX   = {1'b0, {(OUTPUT_DATA_WIDTH-1){1'b1}}};

    // ========================================================================
    // Combinational Activation Logic
    // Direct flat-bus slicing (compatible with all iverilog versions)
    // ========================================================================
    reg signed [OUTPUT_DATA_WIDTH-1:0] activated [0:ARRAY_SIZE-1];

    integer i;
    always @(*) begin
        for (i = 0; i < ARRAY_SIZE; i = i + 1) begin : act_loop
            case (mode)
                2'b00: // Passthrough
                    activated[i] = $signed(data_in[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]);

                2'b01: // ReLU: max(0, x)
                    activated[i] = data_in[i*OUTPUT_DATA_WIDTH + OUTPUT_DATA_WIDTH - 1]
                                   ? ZERO
                                   : $signed(data_in[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]);

                2'b10: begin // ReLU6: clamp to [0, 6]
                    if (data_in[i*OUTPUT_DATA_WIDTH + OUTPUT_DATA_WIDTH - 1])
                        activated[i] = ZERO;
                    else if ($signed(data_in[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]) > RELU6_MAX)
                        activated[i] = RELU6_MAX;
                    else
                        activated[i] = $signed(data_in[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]);
                end

                default: // Reserved — passthrough
                    activated[i] = $signed(data_in[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH]);
            endcase
        end
    end

    // ========================================================================
    // Output Pipeline Register (1 cycle latency, improves Fmax)
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            data_out <= {(ARRAY_SIZE * OUTPUT_DATA_WIDTH){1'b0}};
        end else begin
            for (i = 0; i < ARRAY_SIZE; i = i + 1)
                data_out[i*OUTPUT_DATA_WIDTH +: OUTPUT_DATA_WIDTH] <= activated[i];
        end
    end

endmodule
