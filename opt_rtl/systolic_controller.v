// ============================================================================
// Module      : systolic_controller
// Description : FSM controller for the systolic array TPU datapath
// Technology  : IHP SG13G2 130nm
//
// === Architecture (Google TPU v1 Inspired) ===
//
// The Google TPU v1 paper describes a 4-stage instruction pipeline:
//   Read_Host_Memory → Read_Weights → MatrixMultiply → Activate
//
// Key insight: "Read_Weights" and "MatrixMultiply" are overlapped using the
// Weight FIFO — weights for the NEXT tile are pre-fetched while the CURRENT
// tile is being computed.
//
// This controller implements that overlap via:
//   - `shadow_weight_en`: asserted during COMPUTE to pre-load next weights
//   - `weight_swap`:      asserted on the CLEAR cycle at the tile boundary,
//                         atomically swapping shadow → active weight in all PEs.
//
// === FSM States ===
//
//   S_IDLE    : Wait for tpu_start
//   S_LOAD    : Load first tile's weights into active weight regs
//   S_COMPUTE : Run matrix multiply + simultaneously pre-load next tile weights
//   S_DONE    : Assert tpu_done, return to IDLE
//
// === Pipeline Latency Accounting ===
//   +1 cycle : control signal registration at array boundary
//   +1 cycle : diagonal wavefront skew (max row = ARRAY_SIZE-1 = 7 cycles)
//   +2 cycles: PE 2-stage MAC pipeline (mul_reg, accum_reg)
//   +2 cycles: 2-stage result readout pipeline (stage1, stage2)
//   = PE_PIPELINE_LAT = ARRAY_SIZE + 4 cycles before first valid result
//
// ============================================================================

module systolic_controller #(
    parameter ARRAY_SIZE = 8
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       tpu_start,

    // ── Systolic array controls ──────────────────────────────
    output reg        mac_en,
    output reg        clear,
    output reg        weight_en,          // Direct active-weight load
    output reg        shadow_weight_en,   // [P3] Pre-load shadow weight
    output reg        weight_swap,        // [P3] Swap shadow → active at tile start

    // ── Address generator ────────────────────────────────────
    output reg  [6:0] addr_serial_num,

    // ── Output write controls ────────────────────────────────
    output reg        sram_write_enable,
    output reg  [5:0] result_index,
    output reg  [1:0] data_set,

    // ── Completion ───────────────────────────────────────────
    output reg        tpu_done
);

    // ========================================================================
    // Derived Constants
    // ========================================================================
    localparam DIAG_COUNT      = 2 * ARRAY_SIZE - 1;     // 15 for 8×8
    // Pipeline latency:
    //   1 (ctrl reg) + (ARRAY_SIZE-1) (skew) + 2 (PE mac stages) + 2 (readout stages)
    //   = ARRAY_SIZE + 4
    localparam PE_PIPELINE_LAT = ARRAY_SIZE + 4;         // 12 for ARRAY_SIZE=8
    localparam FIRST_RESULT    = ARRAY_SIZE + PE_PIPELINE_LAT;
    localparam TOTAL_COMPUTE   = FIRST_RESULT + DIAG_COUNT;
    localparam MAX_ADDR        = 2 * DIAG_COUNT;
    localparam MAX_RESULT_IDX  = DIAG_COUNT;
    localparam NUM_DATA_SETS   = 2;

    // Shadow weight load window
    localparam SHADOW_LOAD_START = ARRAY_SIZE;          // Start after N cycles
    localparam SHADOW_LOAD_END   = 2 * ARRAY_SIZE;      // End after 2N cycles

    // ========================================================================
    // State Encoding (one-hot for fast decode and small area)
    // ========================================================================
    localparam [3:0] S_IDLE    = 4'b0001;
    localparam [3:0] S_LOAD    = 4'b0010;
    localparam [3:0] S_COMPUTE = 4'b0100;
    localparam [3:0] S_DONE    = 4'b1000;

    reg [3:0] state, state_nxt;

    // ========================================================================
    // Internal Counters & Next-State Signals
    // ========================================================================
    reg [8:0]  cycle_cnt,        cycle_cnt_nxt;
    reg [6:0]  addr_serial_nxt;
    reg [5:0]  result_index_nxt;
    reg [1:0]  data_set_nxt;

    // ========================================================================
    // Sequential Logic
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n) begin
            state           <= S_IDLE;
            cycle_cnt       <= 9'd0;
            addr_serial_num <= 7'd0;
            result_index    <= 6'd0;
            data_set        <= 2'd0;
            tpu_done        <= 1'b0;
        end else begin
            state           <= state_nxt;
            cycle_cnt       <= cycle_cnt_nxt;
            addr_serial_num <= addr_serial_nxt;
            result_index    <= result_index_nxt;
            data_set        <= data_set_nxt;
            tpu_done        <= (state_nxt == S_DONE);
        end
    end

    // ========================================================================
    // Combinational Next-State & Output Logic
    // ========================================================================
    always @(*) begin
        // ── Registered next-state signals ──
        state_nxt         = state;
        cycle_cnt_nxt     = cycle_cnt;
        addr_serial_nxt   = addr_serial_num;
        result_index_nxt  = result_index;
        data_set_nxt      = data_set;

        // ── Output defaults (safe state) ──
        mac_en            = 1'b0;
        clear             = 1'b0;
        weight_en         = 1'b0;
        shadow_weight_en  = 1'b0;
        weight_swap       = 1'b0;
        sram_write_enable = 1'b0;

        case (state)
            // ── IDLE: Wait for start signal ──────────────────────────────
            S_IDLE: begin
                if (tpu_start) begin
                    state_nxt         = S_LOAD;
                    cycle_cnt_nxt     = 9'd0;
                    addr_serial_nxt   = 7'd0;
                    result_index_nxt  = 6'd0;
                    data_set_nxt      = 2'd0;
                end
            end

            // ── LOAD: Load first tile's weights into active weight regs ──
            // One clock cycle — weight_en is pulsed, array boundary reg adds 1 more.
            // clear is asserted to reset accumulators before computation begins.
            S_LOAD: begin
                weight_en     = 1'b1;
                clear         = 1'b1;
                addr_serial_nxt = 7'd1;
                cycle_cnt_nxt   = 9'd1;
                state_nxt       = S_COMPUTE;
            end

            // ── COMPUTE: Run matrix multiply (MAC) ───────────────────────
            // Simultaneously pre-loads next tile's weights via shadow registers.
            // Results start appearing after PE_PIPELINE_LAT cycles.
            S_COMPUTE: begin
                mac_en = 1'b1;

                // ── Address counter (drives SRAM reads for activations) ──
                if (addr_serial_num < MAX_ADDR[6:0])
                    addr_serial_nxt = addr_serial_num + 7'd1;
                else
                    addr_serial_nxt = addr_serial_num;

                // ── Cycle counter ──
                cycle_cnt_nxt = cycle_cnt + 9'd1;

                // ── [P3] Shadow weight pre-loading ──────────────────────────
                // After SHADOW_LOAD_START cycles, begin loading next weights
                // into shadow registers. weight_en goes LOW so active weight
                // is not disturbed. shadow_weight_en goes HIGH for ARRAY_SIZE cycles.
                if (cycle_cnt >= SHADOW_LOAD_START &&
                    cycle_cnt < SHADOW_LOAD_END) begin
                    shadow_weight_en = 1'b1;
                end

                // ── [P3] Weight swap at tile boundary (on the clear cycle) ──
                // weight_swap is asserted exactly when the next tile starts
                // (when data_set increments and clear resets accumulators).
                // We'll assert it when result draining completes for a set.
                // (Handled below in result draining section)

                // ── Result draining — starts after pipeline fills ──────────
                if (cycle_cnt >= FIRST_RESULT[8:0]) begin
                    sram_write_enable = 1'b1;

                    if (result_index == MAX_RESULT_IDX[5:0]) begin
                        result_index_nxt = 6'd0;
                        data_set_nxt     = data_set + 2'd1;

                        // [P3] Swap shadow weights atomically at tile start
                        weight_swap = 1'b1;
                        clear       = 1'b1;  // Reset accumulators for new tile

                        if (data_set == NUM_DATA_SETS[1:0] - 2'd1) begin
                            state_nxt = S_DONE;
                        end
                    end else begin
                        result_index_nxt = result_index + 6'd1;
                    end
                end
            end

            // ── DONE: Pulse tpu_done, return to IDLE ─────────────────────
            S_DONE: begin
                state_nxt = S_IDLE;
            end

            default: begin
                state_nxt = S_IDLE;
            end
        endcase
    end

endmodule
