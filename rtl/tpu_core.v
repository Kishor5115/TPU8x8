// ============================================================================
// Module      : tpu_core
// Description : TPU Core Logic — 8×8 Systolic Array Datapath & Control
// Technology  : IHP SG13G2 130nm
//
// Submodules:
//   addr_sel          — SRAM address generation for weight/data banks
//   systolic (8×8)    — MAC array with weight-stationary dataflow
//   systolic_controll — FSM controller (IDLE → LOAD → ROLLING → DONE)
//   quantize          — 21-bit → 16-bit saturation/clipping
//   write_out         — Output demux to 3 SRAM banks (A/B/C)
//
// Interface:
//   2× 32-bit weight read ports  (w0, w1)
//   2× 32-bit data read ports    (d0, d1)
//   3× output write banks        (A, B, C) — 128-bit each
//
// ============================================================================

module tpu_core #(
    parameter ARRAY_SIZE        = 8,
    parameter SRAM_DATA_WIDTH   = 32,
    parameter DATA_WIDTH        = 8,
    parameter OUTPUT_DATA_WIDTH = 16
)
(
    input  wire clk,
    input  wire srstn,
    input  wire tpu_start,

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

// ============================================================================
// Local Parameters
// ============================================================================

localparam ORI_WIDTH       = DATA_WIDTH + DATA_WIDTH + 5;   // 21-bit accumulator
localparam CYCLE_NUM_WIDTH = 9;   // Matches systolic.v / systolic_controll.v [8:0]

// ============================================================================
// Internal Wires
// ============================================================================

// Address generator
wire [6:0] addr_serial_num;

// Quantizer
wire signed [ARRAY_SIZE*ORI_WIDTH-1:0]          ori_data;
wire signed [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0]  quantized_data;

// Systolic array control
wire                        alu_start;
wire [CYCLE_NUM_WIDTH-1:0]  cycle_num;
wire [5:0]                  matrix_index;
wire                        sram_write_enable;
wire [1:0]                  data_set;

// ============================================================================
// Address Selector — generates SRAM read addresses
// ============================================================================

addr_sel u_addr_sel (
    .clk              (clk),
    .addr_serial_num  (addr_serial_num),
    .sram_raddr_w0    (sram_raddr_w0),
    .sram_raddr_w1    (sram_raddr_w1),
    .sram_raddr_d0    (sram_raddr_d0),
    .sram_raddr_d1    (sram_raddr_d1)
);

// ============================================================================
// Quantizer — 21-bit → 16-bit saturation
// ============================================================================

quantize #(
    .ARRAY_SIZE       (ARRAY_SIZE),
    .SRAM_DATA_WIDTH  (SRAM_DATA_WIDTH),
    .DATA_WIDTH       (DATA_WIDTH),
    .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
) u_quantize (
    .ori_data         (ori_data),
    .quantized_data   (quantized_data)
);

// ============================================================================
// 8×8 Systolic Array — weight-stationary MAC datapath
// ============================================================================

systolic #(
    .ARRAY_SIZE      (ARRAY_SIZE),
    .SRAM_DATA_WIDTH (SRAM_DATA_WIDTH),
    .DATA_WIDTH      (DATA_WIDTH)
) u_systolic (
    .clk             (clk),
    .srstn           (srstn),
    .alu_start       (alu_start),
    .cycle_num       (cycle_num),
    .sram_rdata_w0   (sram_rdata_w0),
    .sram_rdata_w1   (sram_rdata_w1),
    .sram_rdata_d0   (sram_rdata_d0),
    .sram_rdata_d1   (sram_rdata_d1),
    .matrix_index    (matrix_index),
    .mul_outcome     (ori_data)
);

// ============================================================================
// Systolic Controller — FSM (IDLE → LOAD_DATA → WAIT → ROLLING → DONE)
// ============================================================================

systolic_controll #(
    .ARRAY_SIZE      (ARRAY_SIZE)
) u_systolic_controll (
    .clk               (clk),
    .srstn             (srstn),
    .tpu_start         (tpu_start),
    .sram_write_enable (sram_write_enable),
    .addr_serial_num   (addr_serial_num),
    .alu_start         (alu_start),
    .cycle_num         (cycle_num),
    .matrix_index      (matrix_index),
    .data_set          (data_set),
    .tpu_done          (tpu_done)
);

// ============================================================================
// Write-Out Demux — routes quantized results to output SRAM banks A/B/C
// ============================================================================

write_out #(
    .ARRAY_SIZE       (ARRAY_SIZE),
    .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
) u_write_out (
    .clk                 (clk),
    .srstn               (srstn),
    .sram_write_enable   (sram_write_enable),
    .data_set            (data_set),
    .matrix_index        (matrix_index),
    .quantized_data      (quantized_data),
    .sram_write_enable_a0(sram_write_enable_a0),
    .sram_wdata_a        (sram_wdata_a),
    .sram_waddr_a        (sram_waddr_a),
    .sram_write_enable_b0(sram_write_enable_b0),
    .sram_wdata_b        (sram_wdata_b),
    .sram_waddr_b        (sram_waddr_b),
    .sram_write_enable_c0(sram_write_enable_c0),
    .sram_wdata_c        (sram_wdata_c),
    .sram_waddr_c        (sram_waddr_c)
);

endmodule
