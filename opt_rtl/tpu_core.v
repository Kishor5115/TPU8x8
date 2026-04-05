// ============================================================================
// Module      : tpu_core
// Description : TPU Core Logic — Google TPU v1 Inspired 8×8 Systolic Array
// Technology  : IHP SG13G2 130nm
//
// === Architecture (Google TPU v1 Style) ===
//
//   ┌─────────────┐    weights    ┌──────────────────┐    raw    ┌────────────┐
//   │  addr_gen   │──────────────►│                  │──────────►│ quantizer  │
//   │             │    acts       │  systolic_array  │           └─────┬──────┘
//   │             │──────────────►│   (8×8 Skewed    │                 │ INT16
//   └─────────────┘               │    WS Array)     │           ┌─────▼──────┐
//         ▲                       │                  │           │activation  │
//   ┌─────┴──────────────────────►│                  │           │  _pipe     │
//   │ systolic_controller         └──────────────────┘           └─────┬──────┘
//   │  (Overlapped LOAD FSM)                                           │
//   └──────────────────────────────────────────────────────────   ┌────▼───────┐
//                                                                  │output_     │
//                                                                  │ writer     │
//                                                                  └────────────┘
//
// === New Features vs. Previous opt_rtl ===
//   [P2] Diagonal wavefront activation skewing in systolic_array
//   [P3] Shadow weight pre-loading: shadow_weight_en + weight_swap
//   [P4] Activation Pipeline: configurable ReLU/ReLU6/passthrough
//   [P5] 2-stage pipelined result readout (+2 cycles, reduces MUX depth)
//
// === Interface (unchanged from original — drop-in compatible) ===
//   2× 32-bit weight read ports (w0, w1)
//   2× 32-bit data read ports   (d0, d1)
//   3× output write banks       (A, B, C) — 128-bit each
// ============================================================================

module tpu_core #(
    parameter ARRAY_SIZE        = 8,
    parameter SRAM_DATA_WIDTH   = 32,
    parameter DATA_WIDTH        = 8,
    parameter OUTPUT_DATA_WIDTH = 16,
    parameter ACT_MODE          = 2'b01  // Default: ReLU (override per layer)
)(
    input  wire clk,
    input  wire srstn,
    input  wire tpu_start,

    // Activation function mode (can be driven by a config register)
    input  wire [1:0] act_mode,

    // Weight SRAM read interface (2 ports × 32-bit)
    input  wire [SRAM_DATA_WIDTH-1:0] sram_rdata_w0,
    input  wire [SRAM_DATA_WIDTH-1:0] sram_rdata_w1,
    output wire [9:0] sram_raddr_w0,
    output wire [9:0] sram_raddr_w1,

    // Data/Activation SRAM read interface (2 ports × 32-bit)
    input  wire [SRAM_DATA_WIDTH-1:0] sram_rdata_d0,
    input  wire [SRAM_DATA_WIDTH-1:0] sram_rdata_d1,
    output wire [9:0] sram_raddr_d0,
    output wire [9:0] sram_raddr_d1,

    // Output SRAM write interface — Bank A
    output wire sram_write_enable_a0,
    output wire [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_a,
    output wire [5:0] sram_waddr_a,

    // Output SRAM write interface — Bank B
    output wire sram_write_enable_b0,
    output wire [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_b,
    output wire [5:0] sram_waddr_b,

    // Output SRAM write interface — Bank C
    output wire sram_write_enable_c0,
    output wire [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_c,
    output wire [5:0] sram_waddr_c,

    output wire tpu_done
);

    // ========================================================================
    // Local Parameters
    // ========================================================================
    localparam ACCUM_WIDTH = DATA_WIDTH + DATA_WIDTH + 5;  // 21-bit accumulator

    // ========================================================================
    // Internal Wires — Controller → Datapath
    // ========================================================================
    wire        mac_en;
    wire        clear;
    wire        weight_en;
    wire        shadow_weight_en;  // [P3] Pre-load next tile into shadow regs
    wire        weight_swap;       // [P3] Atomic swap shadow → active at tile boundary
    wire [6:0]  addr_serial_num;
    wire        sram_write_enable;
    wire [5:0]  result_index;
    wire [1:0]  data_set;

    // ========================================================================
    // Internal Wires — Datapath Connections
    // ========================================================================
    // Systolic array → quantizer
    wire signed [ARRAY_SIZE*ACCUM_WIDTH-1:0]        raw_result;

    // Quantizer → activation pipe
    wire signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0]  quantized_data;

    // Activation pipe → output writer
    wire signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0]  activated_data;

    // ========================================================================
    // Address Generator — SRAM read addresses
    // ========================================================================
    addr_gen #(
        .ARRAY_SIZE  (ARRAY_SIZE)
    ) u_addr_gen (
        .clk              (clk),
        .rst_n            (srstn),
        .addr_serial_num  (addr_serial_num),
        .sram_raddr_w0    (sram_raddr_w0),
        .sram_raddr_w1    (sram_raddr_w1),
        .sram_raddr_d0    (sram_raddr_d0),
        .sram_raddr_d1    (sram_raddr_d1)
    );

    // ========================================================================
    // Systolic Controller — Overlapped FSM
    // ========================================================================
    systolic_controller #(
        .ARRAY_SIZE  (ARRAY_SIZE)
    ) u_controller (
        .clk               (clk),
        .rst_n             (srstn),
        .tpu_start         (tpu_start),

        .mac_en            (mac_en),
        .clear             (clear),
        .weight_en         (weight_en),
        .shadow_weight_en  (shadow_weight_en),  // [P3]
        .weight_swap       (weight_swap),        // [P3]

        .addr_serial_num   (addr_serial_num),

        .sram_write_enable (sram_write_enable),
        .result_index      (result_index),
        .data_set          (data_set),

        .tpu_done          (tpu_done)
    );

    // ========================================================================
    // 8×8 Systolic Array — Diagonal Skew + 2-Stage Readout
    // ========================================================================
    systolic_array #(
        .ARRAY_SIZE      (ARRAY_SIZE),
        .SRAM_DATA_WIDTH (SRAM_DATA_WIDTH),
        .DATA_WIDTH      (DATA_WIDTH),
        .ACCUM_WIDTH     (ACCUM_WIDTH)
    ) u_systolic_array (
        .clk               (clk),
        .rst_n             (srstn),

        .mac_en            (mac_en),
        .clear             (clear),

        .weight_data_0     (sram_rdata_w0),
        .weight_data_1     (sram_rdata_w1),
        .weight_en         (weight_en),
        .shadow_weight_en  (shadow_weight_en),  // [P3]
        .weight_swap       (weight_swap),        // [P3]

        .act_data_0        (sram_rdata_d0),
        .act_data_1        (sram_rdata_d1),

        .result_index      (result_index),
        .result_out        (raw_result)
    );

    // ========================================================================
    // Quantizer — Pipelined saturation (21-bit → 16-bit INT)
    // ========================================================================
    quantizer #(
        .ARRAY_SIZE        (ARRAY_SIZE),
        .DATA_WIDTH        (DATA_WIDTH),
        .OUTPUT_DATA_WIDTH (OUTPUT_DATA_WIDTH),
        .PIPELINE          (1)
    ) u_quantizer (
        .clk            (clk),
        .rst_n          (srstn),
        .ori_data       (raw_result),
        .quantized_data (quantized_data)
    );

    // ========================================================================
    // [P4] Activation Pipeline — ReLU / ReLU6 / Passthrough
    // ========================================================================
    activation_pipe #(
        .ARRAY_SIZE        (ARRAY_SIZE),
        .OUTPUT_DATA_WIDTH (OUTPUT_DATA_WIDTH)
    ) u_activation_pipe (
        .clk      (clk),
        .rst_n    (srstn),
        .mode     (act_mode),
        .data_in  (quantized_data),
        .data_out (activated_data)
    );

    // ========================================================================
    // Output Writer — De-duplicated bank demux
    // ========================================================================
    output_writer #(
        .ARRAY_SIZE        (ARRAY_SIZE),
        .OUTPUT_DATA_WIDTH (OUTPUT_DATA_WIDTH)
    ) u_output_writer (
        .clk                  (clk),
        .rst_n                (srstn),
        .sram_write_enable    (sram_write_enable),
        .data_set             (data_set),
        .result_index         (result_index),
        .quantized_data       (activated_data),  // From activation pipe, not raw quantizer
        .sram_write_enable_a0 (sram_write_enable_a0),
        .sram_wdata_a         (sram_wdata_a),
        .sram_waddr_a         (sram_waddr_a),
        .sram_write_enable_b0 (sram_write_enable_b0),
        .sram_wdata_b         (sram_wdata_b),
        .sram_waddr_b         (sram_waddr_b),
        .sram_write_enable_c0 (sram_write_enable_c0),
        .sram_wdata_c         (sram_wdata_c),
        .sram_waddr_c         (sram_waddr_c)
    );

endmodule
