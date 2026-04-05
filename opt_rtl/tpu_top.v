// ============================================================================
// Module      : tpu_top
// Description : TPU Hard Macro Top-Level — 8×8 Systolic Array with SRAM Macros
// Technology  : IHP SG13G2 130nm (Optimized)
// SRAM Macros : 2× RM_IHPSG13_1P_256x64  (Weight + Data)
//             : 6× RM_IHPSG13_1P_64x64   (Output Banks A/B/C)
// Total SRAMs : 8
//
// Architecture:
//   ┌──────────────────────────────────────────────────┐
//   │                  SRAM Region                      │
//   │  ┌────────────┐ ┌────────────┐                   │
//   │  │ Weight SRAM │ │  Data SRAM │  (256×64 each)   │
//   │  └────────────┘ └────────────┘                   │
//   │  ┌──────┐┌──────┐┌──────┐┌──────┐┌──────┐┌──────┐│
//   │  │Out A0││Out A1││Out B0││Out B1││Out C0││Out C1││
//   │  └──────┘└──────┘└──────┘└──────┘└──────┘└──────┘│
//   │                 (64×64 each)                      │
//   ├──────────────────────────────────────────────────┤
//   │              TPU Core Logic (Optimized)           │
//   │  ┌──────────────────────────────────────────┐    │
//   │  │  systolic_controller → systolic_array     │    │
//   │  │  (8×8 pipelined PEs) → quantizer          │    │
//   │  │  → output_writer                          │    │
//   │  └──────────────────────────────────────────┘    │
//   └──────────────────────────────────────────────────┘
//
// Memory Map:
//   Weight SRAM : 256 × 64-bit = 2 KB  (holds 2× 32-bit weight banks)
//   Data SRAM   : 256 × 64-bit = 2 KB  (holds 2× 32-bit activation banks)
//   Output A    : 2×64 × 64-bit = 1 KB (128-bit output, split into 2×64)
//   Output B    : 2×64 × 64-bit = 1 KB
//   Output C    : 2×64 × 64-bit = 1 KB
// ============================================================================

module tpu_top #(
    parameter ARRAY_SIZE        = 8,
    parameter SRAM_DATA_WIDTH   = 32,
    parameter DATA_WIDTH        = 8,
    parameter OUTPUT_DATA_WIDTH = 16
)(
    input  wire clk,
    input  wire srstn,
    input  wire tpu_start,
    output wire tpu_done
);

    // ========================================================================
    // Internal Signals — TPU Core ↔ SRAM Interface
    // ========================================================================

    // Weight SRAM read data (2 ports × 32-bit for 8×8 array)
    wire [SRAM_DATA_WIDTH-1:0] sram_rdata_w0;
    wire [SRAM_DATA_WIDTH-1:0] sram_rdata_w1;

    // Data/Activation SRAM read data (2 ports × 32-bit)
    wire [SRAM_DATA_WIDTH-1:0] sram_rdata_d0;
    wire [SRAM_DATA_WIDTH-1:0] sram_rdata_d1;

    // Weight SRAM read addresses
    wire [9:0] sram_raddr_w0;
    wire [9:0] sram_raddr_w1;

    // Data SRAM read addresses
    wire [9:0] sram_raddr_d0;
    wire [9:0] sram_raddr_d1;

    // Output SRAM write interface — Bank A
    wire        sram_write_enable_a0;
    wire [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_a;
    wire [5:0]  sram_waddr_a;

    // Output SRAM write interface — Bank B
    wire        sram_write_enable_b0;
    wire [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_b;
    wire [5:0]  sram_waddr_b;

    // Output SRAM write interface — Bank C
    wire        sram_write_enable_c0;
    wire [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_c;
    wire [5:0]  sram_waddr_c;

    // ========================================================================
    // SRAM Data Bus Mapping
    // ========================================================================
    wire [63:0] sram_weight_rdata;
    wire [7:0]  sram_weight_addr;

    wire [63:0] sram_data_rdata;
    wire [7:0]  sram_data_addr;

    wire [63:0] sram_output_a_wdata [0:1];
    wire [63:0] sram_output_b_wdata [0:1];
    wire [63:0] sram_output_c_wdata [0:1];
    wire [5:0]  sram_output_addr_a;
    wire [5:0]  sram_output_addr_b;
    wire [5:0]  sram_output_addr_c;

    // Activation mode — tied to ReLU by default
    // Change to 2'b00 for linear/output layers, 2'b10 for ReLU6
    wire [1:0]  act_mode = 2'b01;  // ReLU

    // ========================================================================
    // Address and Data Mapping — Weight SRAM
    // ========================================================================
    assign {sram_rdata_w1, sram_rdata_w0} = sram_weight_rdata;
    assign sram_weight_addr = sram_raddr_w0[7:0];

    // ========================================================================
    // Address and Data Mapping — Data SRAM
    // ========================================================================
    assign {sram_rdata_d1, sram_rdata_d0} = sram_data_rdata;
    assign sram_data_addr = sram_raddr_d0[7:0];

    // ========================================================================
    // Address and Data Mapping — Output SRAMs (128-bit → 2× 64-bit)
    // ========================================================================
    assign sram_output_a_wdata[0] = sram_wdata_a[63:0];
    assign sram_output_a_wdata[1] = sram_wdata_a[127:64];

    assign sram_output_b_wdata[0] = sram_wdata_b[63:0];
    assign sram_output_b_wdata[1] = sram_wdata_b[127:64];

    assign sram_output_c_wdata[0] = sram_wdata_c[63:0];
    assign sram_output_c_wdata[1] = sram_wdata_c[127:64];

    assign sram_output_addr_a = sram_waddr_a;
    assign sram_output_addr_b = sram_waddr_b;
    assign sram_output_addr_c = sram_waddr_c;

    // ========================================================================
    // TPU Core Instantiation (Optimized)
    // ========================================================================
    tpu_core #(
        .ARRAY_SIZE       (ARRAY_SIZE),
        .SRAM_DATA_WIDTH  (SRAM_DATA_WIDTH),
        .DATA_WIDTH       (DATA_WIDTH),
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
    ) u_tpu_core (
        .clk                 (clk),
        .srstn               (srstn),
        .tpu_start           (tpu_start),
        .act_mode            (act_mode),

        .sram_rdata_w0       (sram_rdata_w0),
        .sram_rdata_w1       (sram_rdata_w1),
        .sram_raddr_w0       (sram_raddr_w0),
        .sram_raddr_w1       (sram_raddr_w1),

        .sram_rdata_d0       (sram_rdata_d0),
        .sram_rdata_d1       (sram_rdata_d1),
        .sram_raddr_d0       (sram_raddr_d0),
        .sram_raddr_d1       (sram_raddr_d1),

        .sram_write_enable_a0(sram_write_enable_a0),
        .sram_wdata_a        (sram_wdata_a),
        .sram_waddr_a        (sram_waddr_a),

        .sram_write_enable_b0(sram_write_enable_b0),
        .sram_wdata_b        (sram_wdata_b),
        .sram_waddr_b        (sram_waddr_b),

        .sram_write_enable_c0(sram_write_enable_c0),
        .sram_wdata_c        (sram_wdata_c),
        .sram_waddr_c        (sram_waddr_c),

        .tpu_done            (tpu_done)
    );

    // ========================================================================
    // INPUT SRAM — Weight Memory
    // 1× RM_IHPSG13_1P_256x64_c2_bm_bist
    // ========================================================================
    RM_IHPSG13_1P_256x64_c2_bm_bist u_sram_weight (
        .A_CLK      (clk),
        .A_MEN      (1'b1),
        .A_WEN      (1'b0),
        .A_REN      (1'b1),
        .A_ADDR     (sram_weight_addr),
        .A_DIN      (64'b0),
        .A_DLY      (1'b0),
        .A_DOUT     (sram_weight_rdata),
        .A_BM       (64'b0),
        .A_BIST_CLK (1'b0),
        .A_BIST_EN  (1'b0),
        .A_BIST_MEN (1'b0),
        .A_BIST_WEN (1'b0),
        .A_BIST_REN (1'b0),
        .A_BIST_ADDR(8'b0),
        .A_BIST_DIN (64'b0),
        .A_BIST_BM  (64'b0)
    );

    // ========================================================================
    // INPUT SRAM — Data/Activation Memory
    // 1× RM_IHPSG13_1P_256x64_c2_bm_bist
    // ========================================================================
    RM_IHPSG13_1P_256x64_c2_bm_bist u_sram_data (
        .A_CLK      (clk),
        .A_MEN      (1'b1),
        .A_WEN      (1'b0),
        .A_REN      (1'b1),
        .A_ADDR     (sram_data_addr),
        .A_DIN      (64'b0),
        .A_DLY      (1'b0),
        .A_DOUT     (sram_data_rdata),
        .A_BM       (64'b0),
        .A_BIST_CLK (1'b0),
        .A_BIST_EN  (1'b0),
        .A_BIST_MEN (1'b0),
        .A_BIST_WEN (1'b0),
        .A_BIST_REN (1'b0),
        .A_BIST_ADDR(8'b0),
        .A_BIST_DIN (64'b0),
        .A_BIST_BM  (64'b0)
    );

    // ========================================================================
    // OUTPUT SRAMs — Banks A, B, C (2× 64-bit each, generated)
    // ========================================================================
    genvar gi;

    generate
        for (gi = 0; gi < 2; gi = gi + 1) begin : output_a_srams
            RM_IHPSG13_1P_64x64_c2_bm_bist u_sram_out_a (
                .A_CLK      (clk),
                .A_MEN      (1'b1),
                .A_WEN      (~sram_write_enable_a0),
                .A_REN      (1'b0),
                .A_ADDR     (sram_output_addr_a),
                .A_DIN      (sram_output_a_wdata[gi]),
                .A_DLY      (1'b0),
                .A_DOUT     (),
                .A_BM       (64'hFFFF_FFFF_FFFF_FFFF),
                .A_BIST_CLK (1'b0),
                .A_BIST_EN  (1'b0),
                .A_BIST_MEN (1'b0),
                .A_BIST_WEN (1'b0),
                .A_BIST_REN (1'b0),
                .A_BIST_ADDR(6'b0),
                .A_BIST_DIN (64'b0),
                .A_BIST_BM  (64'b0)
            );
        end
    endgenerate

    generate
        for (gi = 0; gi < 2; gi = gi + 1) begin : output_b_srams
            RM_IHPSG13_1P_64x64_c2_bm_bist u_sram_out_b (
                .A_CLK      (clk),
                .A_MEN      (1'b1),
                .A_WEN      (~sram_write_enable_b0),
                .A_REN      (1'b0),
                .A_ADDR     (sram_output_addr_b),
                .A_DIN      (sram_output_b_wdata[gi]),
                .A_DLY      (1'b0),
                .A_DOUT     (),
                .A_BM       (64'hFFFF_FFFF_FFFF_FFFF),
                .A_BIST_CLK (1'b0),
                .A_BIST_EN  (1'b0),
                .A_BIST_MEN (1'b0),
                .A_BIST_WEN (1'b0),
                .A_BIST_REN (1'b0),
                .A_BIST_ADDR(6'b0),
                .A_BIST_DIN (64'b0),
                .A_BIST_BM  (64'b0)
            );
        end
    endgenerate

    generate
        for (gi = 0; gi < 2; gi = gi + 1) begin : output_c_srams
            RM_IHPSG13_1P_64x64_c2_bm_bist u_sram_out_c (
                .A_CLK      (clk),
                .A_MEN      (1'b1),
                .A_WEN      (~sram_write_enable_c0),
                .A_REN      (1'b0),
                .A_ADDR     (sram_output_addr_c),
                .A_DIN      (sram_output_c_wdata[gi]),
                .A_DLY      (1'b0),
                .A_DOUT     (),
                .A_BM       (64'hFFFF_FFFF_FFFF_FFFF),
                .A_BIST_CLK (1'b0),
                .A_BIST_EN  (1'b0),
                .A_BIST_MEN (1'b0),
                .A_BIST_WEN (1'b0),
                .A_BIST_REN (1'b0),
                .A_BIST_ADDR(6'b0),
                .A_BIST_DIN (64'b0),
                .A_BIST_BM  (64'b0)
            );
        end
    endgenerate

endmodule
