// ============================================================================
// Module      : tpu_top
// Description : TPU Hard Macro Top-Level — 8×8 Systolic Array with SRAM Macros
// Technology  : IHP SG13G2 130nm
// SRAM Macros : 2× RM_IHPSG13_1P_256x64  (Weight + Data)
//             : 6× RM_IHPSG13_1P_64x64   (Output Banks A/B/C)
// Total SRAMs : 8
// Author      : TPU Design Team
// ============================================================================
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
//   │              TPU Core Logic                       │
//   │  ┌──────────────────────────────────────────┐    │
//   │  │  systolic_controll → systolic(8×8 MAC)   │    │
//   │  │  → quantize → write_out                  │    │
//   │  └──────────────────────────────────────────┘    │
//   └──────────────────────────────────────────────────┘
//
// Memory Map:
//   Weight SRAM : 256 × 64-bit = 2 KB  (holds 2× 32-bit weight banks)
//   Data SRAM   : 256 × 64-bit = 2 KB  (holds 2× 32-bit activation banks)
//   Output A    : 2×64 × 64-bit = 1 KB (128-bit output, split into 2×64)
//   Output B    : 2×64 × 64-bit = 1 KB
//   Output C    : 2×64 × 64-bit = 1 KB
//
// ============================================================================

module tpu_top #(
    parameter ARRAY_SIZE        = 8,
    parameter SRAM_DATA_WIDTH   = 32,
    parameter DATA_WIDTH        = 8,
    parameter OUTPUT_DATA_WIDTH = 16
)
(
    input  wire clk,
    input  wire srstn,
    input  wire tpu_start,
    output wire tpu_done
);

// ============================================================================
// Internal Signals — TPU Core ↔ SRAM Interface
// ============================================================================

// Weight SRAM read data (2 ports × 32-bit for 8×8 array)
wire [SRAM_DATA_WIDTH-1:0] sram_rdata_w0;
wire [SRAM_DATA_WIDTH-1:0] sram_rdata_w1;

// Data/Activation SRAM read data (2 ports × 32-bit)
wire [SRAM_DATA_WIDTH-1:0] sram_rdata_d0;
wire [SRAM_DATA_WIDTH-1:0] sram_rdata_d1;

// Weight SRAM read addresses (2 ports × 10-bit from core, truncated to 8-bit)
wire [9:0] sram_raddr_w0;
wire [9:0] sram_raddr_w1;

// Data SRAM read addresses (2 ports × 10-bit from core, truncated to 8-bit)
wire [9:0] sram_raddr_d0;
wire [9:0] sram_raddr_d1;

// Output SRAM write interface — Bank A
wire        sram_write_enable_a0;
wire [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_a;   // 128-bit
wire [5:0]  sram_waddr_a;

// Output SRAM write interface — Bank B
wire        sram_write_enable_b0;
wire [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_b;   // 128-bit
wire [5:0]  sram_waddr_b;

// Output SRAM write interface — Bank C
wire        sram_write_enable_c0;
wire [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_c;   // 128-bit
wire [5:0]  sram_waddr_c;

// ============================================================================
// SRAM Data Bus Mapping
// ============================================================================
// Weight SRAM (256×64): upper 32 bits → w1, lower 32 bits → w0
// Data   SRAM (256×64): upper 32 bits → d1, lower 32 bits → d0
// Output SRAMs (64×64): 128-bit output split into 2× 64-bit SRAMs per bank

wire [63:0] sram_weight_rdata;      // Single 64-bit weight SRAM output
wire [7:0]  sram_weight_addr;       // 8-bit address for 256-depth

wire [63:0] sram_data_rdata;        // Single 64-bit data SRAM output
wire [7:0]  sram_data_addr;         // 8-bit address for 256-depth

// Output SRAMs: 2× 64-bit per bank (3 banks × 2 = 6 SRAMs)
wire [63:0] sram_output_a_wdata [0:1];
wire [63:0] sram_output_b_wdata [0:1];
wire [63:0] sram_output_c_wdata [0:1];
wire [5:0]  sram_output_addr_a;     // 6-bit for 64-depth
wire [5:0]  sram_output_addr_b;
wire [5:0]  sram_output_addr_c;

// ============================================================================
// Address and Data Mapping — Weight SRAM
// ============================================================================
// 64-bit SRAM → [63:32] = w1, [31:0] = w0

assign {sram_rdata_w1, sram_rdata_w0} = sram_weight_rdata;
// Truncate 10-bit core address to 8-bit for 256-depth SRAM
assign sram_weight_addr = sram_raddr_w0[7:0];

// ============================================================================
// Address and Data Mapping — Data SRAM
// ============================================================================
// 64-bit SRAM → [63:32] = d1, [31:0] = d0

assign {sram_rdata_d1, sram_rdata_d0} = sram_data_rdata;
assign sram_data_addr = sram_raddr_d0[7:0];

// ============================================================================
// Address and Data Mapping — Output SRAMs
// ============================================================================
// 128-bit output → 2× 64-bit SRAMs per bank

assign sram_output_a_wdata[0] = sram_wdata_a[63:0];
assign sram_output_a_wdata[1] = sram_wdata_a[127:64];

assign sram_output_b_wdata[0] = sram_wdata_b[63:0];
assign sram_output_b_wdata[1] = sram_wdata_b[127:64];

assign sram_output_c_wdata[0] = sram_wdata_c[63:0];
assign sram_output_c_wdata[1] = sram_wdata_c[127:64];

// 6-bit address maps directly to 64-depth SRAM
assign sram_output_addr_a = sram_waddr_a;
assign sram_output_addr_b = sram_waddr_b;
assign sram_output_addr_c = sram_waddr_c;

// ============================================================================
// TPU Core Instantiation
// ============================================================================

tpu_core #(
    .ARRAY_SIZE       (ARRAY_SIZE),
    .SRAM_DATA_WIDTH  (SRAM_DATA_WIDTH),
    .DATA_WIDTH       (DATA_WIDTH),
    .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
) u_tpu_core (
    .clk                (clk),
    .srstn              (srstn),
    .tpu_start          (tpu_start),

    // Weight SRAM read interface
    .sram_rdata_w0      (sram_rdata_w0),
    .sram_rdata_w1      (sram_rdata_w1),
    .sram_raddr_w0      (sram_raddr_w0),
    .sram_raddr_w1      (sram_raddr_w1),

    // Data SRAM read interface
    .sram_rdata_d0      (sram_rdata_d0),
    .sram_rdata_d1      (sram_rdata_d1),
    .sram_raddr_d0      (sram_raddr_d0),
    .sram_raddr_d1      (sram_raddr_d1),

    // Output SRAM write interface — Bank A
    .sram_write_enable_a0(sram_write_enable_a0),
    .sram_wdata_a        (sram_wdata_a),
    .sram_waddr_a        (sram_waddr_a),

    // Output SRAM write interface — Bank B
    .sram_write_enable_b0(sram_write_enable_b0),
    .sram_wdata_b        (sram_wdata_b),
    .sram_waddr_b        (sram_waddr_b),

    // Output SRAM write interface — Bank C
    .sram_write_enable_c0(sram_write_enable_c0),
    .sram_wdata_c        (sram_wdata_c),
    .sram_waddr_c        (sram_waddr_c),

    .tpu_done            (tpu_done)
);

// ============================================================================
// INPUT SRAM — Weight Memory
// 1× RM_IHPSG13_1P_256x64_c2_bm_bist
// Holds 2× 32-bit weight banks (w0, w1) packed into 64-bit word
// ============================================================================

RM_IHPSG13_1P_256x64_c2_bm_bist u_sram_weight (
    // Clock
    .A_CLK      (clk),

    // Memory control
    .A_MEN      (1'b1),                 // Memory enable — always active
    .A_WEN      (1'b0),                 // Write enable — read-only
    .A_REN      (1'b1),                 // Read enable — active

    // Address and data
    .A_ADDR     (sram_weight_addr),     // 8-bit address
    .A_DIN      (64'b0),               // No write data (read-only)
    .A_DLY      (1'b0),                // No delay
    .A_DOUT     (sram_weight_rdata),   // 64-bit read data
    .A_BM       (64'b0),               // Byte mask — not used for read

    // BIST interface — disabled
    .A_BIST_CLK (1'b0),
    .A_BIST_EN  (1'b0),
    .A_BIST_MEN (1'b0),
    .A_BIST_WEN (1'b0),
    .A_BIST_REN (1'b0),
    .A_BIST_ADDR(8'b0),
    .A_BIST_DIN (64'b0),
    .A_BIST_BM  (64'b0)
);

// ============================================================================
// INPUT SRAM — Data/Activation Memory
// 1× RM_IHPSG13_1P_256x64_c2_bm_bist
// Holds 2× 32-bit activation banks (d0, d1) packed into 64-bit word
// ============================================================================

RM_IHPSG13_1P_256x64_c2_bm_bist u_sram_data (
    // Clock
    .A_CLK      (clk),

    // Memory control
    .A_MEN      (1'b1),
    .A_WEN      (1'b0),
    .A_REN      (1'b1),

    // Address and data
    .A_ADDR     (sram_data_addr),       // 8-bit address
    .A_DIN      (64'b0),
    .A_DLY      (1'b0),
    .A_DOUT     (sram_data_rdata),
    .A_BM       (64'b0),

    // BIST interface — disabled
    .A_BIST_CLK (1'b0),
    .A_BIST_EN  (1'b0),
    .A_BIST_MEN (1'b0),
    .A_BIST_WEN (1'b0),
    .A_BIST_REN (1'b0),
    .A_BIST_ADDR(8'b0),
    .A_BIST_DIN (64'b0),
    .A_BIST_BM  (64'b0)
);

// ============================================================================
// OUTPUT SRAM — Bank A  (Result Storage)
// 2× RM_IHPSG13_1P_64x64_c2_bm_bist
// 128-bit output split: [63:0] → SRAM0, [127:64] → SRAM1
// ============================================================================

genvar gi;
generate
    for (gi = 0; gi < 2; gi = gi + 1) begin : output_a_srams
        RM_IHPSG13_1P_64x64_c2_bm_bist u_sram_out_a (
            .A_CLK      (clk),
            .A_MEN      (1'b1),
            .A_WEN      (~sram_write_enable_a0),    // Active-low write
            .A_REN      (1'b0),                     // Write-only
            .A_ADDR     (sram_output_addr_a),       // 6-bit address
            .A_DIN      (sram_output_a_wdata[gi]),
            .A_DLY      (1'b0),
            .A_DOUT     (),                         // Not used (write-only)
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

// ============================================================================
// OUTPUT SRAM — Bank B  (Result Storage)
// 2× RM_IHPSG13_1P_64x64_c2_bm_bist
// ============================================================================

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

// ============================================================================
// OUTPUT SRAM — Bank C  (Result Storage)
// 2× RM_IHPSG13_1P_64x64_c2_bm_bist
// ============================================================================

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