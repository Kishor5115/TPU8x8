// ============================================================================
// Module      : addr_gen
// Description : Parameterized SRAM address generator for TPU datapath
// Technology  : IHP SG13G2 130nm
//
// Generates read addresses for weight and data SRAMs based on the
// serial address number from the controller.
//
// Key Improvements over original addr_sel.v:
//   - All constants derived from ARRAY_SIZE (no magic 98, 102, 127)
//   - Cleaner parameterization and naming
//   - Output register retained for SRAM setup/hold timing
// ============================================================================

module addr_gen #(
    parameter ARRAY_SIZE = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [6:0]  addr_serial_num,

    // Weight SRAM addresses (2 banks)
    output reg  [9:0]  sram_raddr_w0,    // Bank 0 (cols 0..3)
    output reg  [9:0]  sram_raddr_w1,    // Bank 1 (cols 4..7)

    // Data SRAM addresses (2 banks)
    output reg  [9:0]  sram_raddr_d0,    // Bank 0 (rows 0..3)
    output reg  [9:0]  sram_raddr_d1     // Bank 1 (rows 4..7)
);

    // ========================================================================
    // Derived Constants
    // ========================================================================
    // Maximum valid address for bank 0: covers ARRAY_SIZE + skew overhead
    localparam [6:0] BANK0_MAX_ADDR  = (2 * ARRAY_SIZE - 1) + (ARRAY_SIZE - 1) + (ARRAY_SIZE / 2) - 1;
    // Bank 1 starts ARRAY_SIZE/2 cycles later
    localparam [6:0] BANK1_START     = ARRAY_SIZE / 2;
    localparam [6:0] BANK1_MAX_ADDR  = BANK0_MAX_ADDR + BANK1_START;
    // Default address when out of range (beyond valid SRAM depth)
    localparam [9:0] DEFAULT_ADDR    = 10'd127;

    // ========================================================================
    // Address Computation (combinational)
    // ========================================================================
    wire [9:0] sram_raddr_w0_nxt;
    wire [9:0] sram_raddr_w1_nxt;
    wire [9:0] sram_raddr_d0_nxt;
    wire [9:0] sram_raddr_d1_nxt;

    assign sram_raddr_w0_nxt = (addr_serial_num <= BANK0_MAX_ADDR)
                               ? {{3{1'b0}}, addr_serial_num}
                               : DEFAULT_ADDR;

    assign sram_raddr_w1_nxt = (addr_serial_num >= BANK1_START && addr_serial_num <= BANK1_MAX_ADDR)
                               ? {{3{1'b0}}, addr_serial_num - BANK1_START}
                               : DEFAULT_ADDR;

    // Data uses same address scheme as weight (symmetric in this architecture)
    assign sram_raddr_d0_nxt = sram_raddr_w0_nxt;
    assign sram_raddr_d1_nxt = sram_raddr_w1_nxt;

    // ========================================================================
    // Output Registers (for SRAM setup timing)
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            sram_raddr_w0 <= DEFAULT_ADDR;
            sram_raddr_w1 <= DEFAULT_ADDR;
            sram_raddr_d0 <= DEFAULT_ADDR;
            sram_raddr_d1 <= DEFAULT_ADDR;
        end else begin
            sram_raddr_w0 <= sram_raddr_w0_nxt;
            sram_raddr_w1 <= sram_raddr_w1_nxt;
            sram_raddr_d0 <= sram_raddr_d0_nxt;
            sram_raddr_d1 <= sram_raddr_d1_nxt;
        end
    end

endmodule
