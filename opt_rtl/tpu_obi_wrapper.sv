// ============================================================================
// TPU OBI Wrapper (Optimized)
// Wraps the optimized systolic array TPU with an OBI subordinate interface
// for integration with Croc-SoC (parameterized array size)
//
// Register Map:
// 0x000: CTRL    - Write 1 to start TPU
// 0x004: STATUS  - Bit 0: done flag
// 0x008-0x0FF: Reserved
// 0x100-0x2FF: Weight SRAM 0 (128 words × 32-bit)
// 0x300-0x4FF: Weight SRAM 1 (128 words × 32-bit)
// 0x500-0x6FF: Data SRAM 0 (128 words × 32-bit)
// 0x700-0x8FF: Data SRAM 1 (128 words × 32-bit)
// 0x900-0xAFF: Output A (64 rows × 4 words each = 256 words, 128-bit per row)
// 0xB00-0xCFF: Output B
// 0xD00-0xEFF: Output C
// ============================================================================

module tpu_obi_wrapper
    import croc_pkg::*;
#(
    parameter int ARRAY_SIZE        = 32,
    parameter int SRAM_DATA_WIDTH   = 32,
    parameter int DATA_WIDTH        = 8,
    parameter int OUTPUT_DATA_WIDTH = 16
)(
    input  logic        clk_i,
    input  logic        rst_ni,

    // OBI subordinate interface
    input  sbr_obi_req_t obi_req_i,
    output sbr_obi_rsp_t obi_rsp_o
);

    // ========================================================================
    // Derived Parameters
    // ========================================================================
    localparam int WEIGHT_DATA_DEPTH = 128;
    localparam int OUTPUT_DEPTH      = 64;

    // ========================================================================
    // Control Registers
    // ========================================================================
    logic        tpu_start_reg;
    logic        tpu_start_pulse;
    logic        tpu_done;

    // ========================================================================
    // Internal SRAMs
    // ========================================================================
    logic [SRAM_DATA_WIDTH-1:0] weight_sram_0 [0:WEIGHT_DATA_DEPTH-1];
    logic [SRAM_DATA_WIDTH-1:0] weight_sram_1 [0:WEIGHT_DATA_DEPTH-1];
    logic [SRAM_DATA_WIDTH-1:0] data_sram_0   [0:WEIGHT_DATA_DEPTH-1];
    logic [SRAM_DATA_WIDTH-1:0] data_sram_1   [0:WEIGHT_DATA_DEPTH-1];

    localparam int OUTPUT_WIDTH = ARRAY_SIZE * OUTPUT_DATA_WIDTH;
    localparam int OUTPUT_WORDS_PER_ROW = (OUTPUT_WIDTH + 31) / 32;

    logic [OUTPUT_WIDTH-1:0] output_sram_a [0:OUTPUT_DEPTH-1];
    logic [OUTPUT_WIDTH-1:0] output_sram_b [0:OUTPUT_DEPTH-1];
    logic [OUTPUT_WIDTH-1:0] output_sram_c [0:OUTPUT_DEPTH-1];

    // ========================================================================
    // TPU Interface Signals
    // ========================================================================
    logic [9:0] sram_raddr_w0, sram_raddr_w1;
    logic [9:0] sram_raddr_d0, sram_raddr_d1;
    logic [SRAM_DATA_WIDTH-1:0] sram_rdata_w0, sram_rdata_w1;
    logic [SRAM_DATA_WIDTH-1:0] sram_rdata_d0, sram_rdata_d1;

    logic        sram_write_enable_a0;
    logic [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_a;
    logic [5:0]  sram_waddr_a;

    logic        sram_write_enable_b0;
    logic [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_b;
    logic [5:0]  sram_waddr_b;

    logic        sram_write_enable_c0;
    logic [ARRAY_SIZE*OUTPUT_DATA_WIDTH-1:0] sram_wdata_c;
    logic [5:0]  sram_waddr_c;

    // ========================================================================
    // OBI Transaction Tracking
    // ========================================================================
    logic        req_accepted;
    logic        rsp_pending;
    logic [31:0] rsp_rdata;
    logic [SbrObiCfg.IdWidth-1:0] rsp_rid;

    assign req_accepted = obi_req_i.req && obi_rsp_o.gnt;

    // ========================================================================
    // OBI Response
    // ========================================================================
    always_comb begin
        obi_rsp_o         = '0;
        obi_rsp_o.gnt     = !rsp_pending;
        obi_rsp_o.rvalid  = rsp_pending;
        obi_rsp_o.r.rdata = rsp_rdata;
        obi_rsp_o.r.rid   = rsp_rid;
        obi_rsp_o.r.err   = 1'b0;
    end

    // ========================================================================
    // Address Decoding
    // ========================================================================
    logic [11:0] word_addr;
    assign word_addr = obi_req_i.a.addr[13:2];

    localparam logic [11:0] CTRL_ADDR      = 12'h000;
    localparam logic [11:0] STATUS_ADDR    = 12'h001;
    localparam logic [11:0] WEIGHT0_START  = 12'h040;
    localparam logic [11:0] WEIGHT0_END    = 12'h0BF;
    localparam logic [11:0] WEIGHT1_START  = 12'h0C0;
    localparam logic [11:0] WEIGHT1_END    = 12'h13F;
    localparam logic [11:0] DATA0_START    = 12'h140;
    localparam logic [11:0] DATA0_END      = 12'h1BF;
    localparam logic [11:0] DATA1_START    = 12'h1C0;
    localparam logic [11:0] DATA1_END      = 12'h23F;
    localparam logic [11:0] OUTPUT_A_START = 12'h240;
    localparam logic [11:0] OUTPUT_A_END   = 12'h33F;
    localparam logic [11:0] OUTPUT_B_START = 12'h340;
    localparam logic [11:0] OUTPUT_B_END   = 12'h43F;
    localparam logic [11:0] OUTPUT_C_START = 12'h440;
    localparam logic [11:0] OUTPUT_C_END   = 12'h53F;

    // ========================================================================
    // SRAM Read Logic (for TPU)
    // ========================================================================
    always_ff @(posedge clk_i) begin
        sram_rdata_w0 <= weight_sram_0[sram_raddr_w0[6:0]];
        sram_rdata_w1 <= weight_sram_1[sram_raddr_w1[6:0]];
        sram_rdata_d0 <= data_sram_0[sram_raddr_d0[6:0]];
        sram_rdata_d1 <= data_sram_1[sram_raddr_d1[6:0]];
    end

    // ========================================================================
    // SRAM Write Logic (from TPU outputs — active-low write enable)
    // ========================================================================
    always_ff @(posedge clk_i) begin
        if (!sram_write_enable_a0)
            output_sram_a[sram_waddr_a] <= sram_wdata_a;
        if (!sram_write_enable_b0)
            output_sram_b[sram_waddr_b] <= sram_wdata_b;
        if (!sram_write_enable_c0)
            output_sram_c[sram_waddr_c] <= sram_wdata_c;
    end

    // ========================================================================
    // OBI Register Access
    // ========================================================================
    always_ff @(posedge clk_i or negedge rst_ni) begin
        if (!rst_ni) begin
            tpu_start_reg   <= 1'b0;
            tpu_start_pulse <= 1'b0;
            rsp_pending     <= 1'b0;
            rsp_rdata       <= 32'b0;
            rsp_rid         <= '0;
        end else begin
            tpu_start_pulse <= 1'b0;

            if (rsp_pending)
                rsp_pending <= 1'b0;

            if (req_accepted) begin
                rsp_pending <= 1'b1;
                rsp_rid     <= obi_req_i.a.aid;
                rsp_rdata   <= 32'hDEAD_BEEF;

                if (word_addr == CTRL_ADDR) begin
                    if (obi_req_i.a.we && obi_req_i.a.wdata[0])
                        tpu_start_pulse <= 1'b1;
                    rsp_rdata <= {31'b0, tpu_start_reg};

                end else if (word_addr == STATUS_ADDR) begin
                    rsp_rdata <= {31'b0, tpu_done};

                end else if (word_addr >= WEIGHT0_START && word_addr <= WEIGHT0_END) begin
                    if (obi_req_i.a.we)
                        weight_sram_0[word_addr - WEIGHT0_START] <= obi_req_i.a.wdata;
                    rsp_rdata <= weight_sram_0[word_addr - WEIGHT0_START];

                end else if (word_addr >= WEIGHT1_START && word_addr <= WEIGHT1_END) begin
                    if (obi_req_i.a.we)
                        weight_sram_1[word_addr - WEIGHT1_START] <= obi_req_i.a.wdata;
                    rsp_rdata <= weight_sram_1[word_addr - WEIGHT1_START];

                end else if (word_addr >= DATA0_START && word_addr <= DATA0_END) begin
                    if (obi_req_i.a.we)
                        data_sram_0[word_addr - DATA0_START] <= obi_req_i.a.wdata;
                    rsp_rdata <= data_sram_0[word_addr - DATA0_START];

                end else if (word_addr >= DATA1_START && word_addr <= DATA1_END) begin
                    if (obi_req_i.a.we)
                        data_sram_1[word_addr - DATA1_START] <= obi_req_i.a.wdata;
                    rsp_rdata <= data_sram_1[word_addr - DATA1_START];

                end else if (word_addr >= OUTPUT_A_START && word_addr <= OUTPUT_A_END) begin
                    automatic logic [7:0] row_idx = (word_addr - OUTPUT_A_START) / OUTPUT_WORDS_PER_ROW;
                    automatic logic [1:0] word_idx = (word_addr - OUTPUT_A_START) % OUTPUT_WORDS_PER_ROW;
                    if (word_idx*32 < OUTPUT_WIDTH)
                        rsp_rdata <= output_sram_a[row_idx][word_idx*32 +: 32];
                    else
                        rsp_rdata <= 32'h0;

                end else if (word_addr >= OUTPUT_B_START && word_addr <= OUTPUT_B_END) begin
                    automatic logic [7:0] row_idx = (word_addr - OUTPUT_B_START) / OUTPUT_WORDS_PER_ROW;
                    automatic logic [1:0] word_idx = (word_addr - OUTPUT_B_START) % OUTPUT_WORDS_PER_ROW;
                    if (word_idx*32 < OUTPUT_WIDTH)
                        rsp_rdata <= output_sram_b[row_idx][word_idx*32 +: 32];
                    else
                        rsp_rdata <= 32'h0;

                end else if (word_addr >= OUTPUT_C_START && word_addr <= OUTPUT_C_END) begin
                    automatic logic [7:0] row_idx = (word_addr - OUTPUT_C_START) / OUTPUT_WORDS_PER_ROW;
                    automatic logic [1:0] word_idx = (word_addr - OUTPUT_C_START) % OUTPUT_WORDS_PER_ROW;
                    if (word_idx*32 < OUTPUT_WIDTH)
                        rsp_rdata <= output_sram_c[row_idx][word_idx*32 +: 32];
                    else
                        rsp_rdata <= 32'h0;
                end
            end
        end
    end

    // ========================================================================
    // TPU Core Instance (Optimized)
    // ========================================================================
    tpu_top #(
        .ARRAY_SIZE       (ARRAY_SIZE),
        .SRAM_DATA_WIDTH  (SRAM_DATA_WIDTH),
        .DATA_WIDTH       (DATA_WIDTH),
        .OUTPUT_DATA_WIDTH(OUTPUT_DATA_WIDTH)
    ) i_tpu_top (
        .clk              (clk_i),
        .srstn            (rst_ni),
        .tpu_start        (tpu_start_pulse),
        .sram_rdata_w0    (sram_rdata_w0),
        .sram_rdata_w1    (sram_rdata_w1),
        .sram_raddr_w0    (sram_raddr_w0),
        .sram_raddr_w1    (sram_raddr_w1),
        .sram_rdata_d0    (sram_rdata_d0),
        .sram_rdata_d1    (sram_rdata_d1),
        .sram_raddr_d0    (sram_raddr_d0),
        .sram_raddr_d1    (sram_raddr_d1),
        .sram_write_enable_a0(sram_write_enable_a0),
        .sram_wdata_a        (sram_wdata_a),
        .sram_waddr_a        (sram_waddr_a),
        .sram_write_enable_b0(sram_write_enable_b0),
        .sram_wdata_b        (sram_wdata_b),
        .sram_waddr_b        (sram_waddr_b),
        .sram_write_enable_c0(sram_write_enable_c0),
        .sram_wdata_c        (sram_wdata_c),
        .sram_waddr_c        (sram_waddr_c),
        .tpu_done         (tpu_done)
    );

endmodule
