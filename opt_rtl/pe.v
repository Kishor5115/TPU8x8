// ============================================================================
// Module      : pe (Processing Element)
// Description : Weight-stationary MAC PE for the 8×8 systolic array
// Technology  : IHP SG13G2 130nm
//
// === Architecture (Google TPU v1 Style — 3-stage pipeline) ===
//
//          weight_in ──────────────► shadow_weight_reg
//                                          │ weight_swap (on clear)
//       ┌──────────────────────────────────▼──────────┐
//       │                weight_reg  (stationary)      │
//       └────────────────────┬────────────────────────┘
//                            │ weight_en
//  data_in ──►[MUL]──►mul_reg──►[ADD]──►accum_reg──►accum_out
//       │        ▲
//       └────►data_out (registered pass-through to right-neighbor PE)
//
// === Dataflow ===
//   - Weight-Stationary: weight loaded into active weight reg when weight_en high
//   - Shadow Register [P3]: New weights for the NEXT tile are pre-loaded via
//     shadow_weight_en. On the clear cycle (start of new tile), weight_swap
//     atomically copies shadow → active weight. This enables zero-stall
//     weight loading overlapped with computation (like Google TPU Weight FIFO).
//   - Activations: flow left → right via registered data_out
//   - MAC: accum += weight * data (signed INT8×INT8 → 21-bit)
//   - clear: resets accumulator for new computation tile
//
// === PPA Notes ===
//   - 2-stage pipeline (mul_reg, accum_reg) breaks MAC critical path
//   - shadow_weight_en uses separate path — no extra mux on critical path
//   - mac_en clock-gating: mul_reg holds on disabled cycles → power saving
// ============================================================================

module pe #(
    parameter DATA_WIDTH    = 8,                            // Input operand width
    parameter ACCUM_WIDTH   = DATA_WIDTH + DATA_WIDTH + 5   // 21-bit accumulator
)(
    input  wire                          clk,
    input  wire                          rst_n,

    // ── Weight loading ──────────────────────────────────────
    input  wire signed [DATA_WIDTH-1:0]  weight_in,         // Shared weight bus
    input  wire                          weight_en,          // Load directly to active reg
    input  wire                          shadow_weight_en,   // [P3] Load into shadow register
    input  wire                          weight_swap,        // [P3] Copy shadow → active (on clear)

    // ── Activation dataflow (left → right) ──────────────────
    input  wire signed [DATA_WIDTH-1:0]  data_in,
    output reg  signed [DATA_WIDTH-1:0]  data_out,           // Registered pass-through

    // ── MAC control ─────────────────────────────────────────
    input  wire                          mac_en,             // Enable MAC operation
    input  wire                          clear,              // Clear accumulator

    // ── Result ──────────────────────────────────────────────
    output reg  signed [ACCUM_WIDTH-1:0] accum_out
);

    // ========================================================================
    // Stage 0a: Shadow Weight Register [P3]
    // Pre-loads the NEXT tile's weight while current tile is computing.
    // Atomically copied to active weight on the clear cycle (tile boundary).
    // ========================================================================
    reg signed [DATA_WIDTH-1:0] shadow_weight_reg;

    always @(posedge clk) begin
        if (!rst_n)
            shadow_weight_reg <= {DATA_WIDTH{1'b0}};
        else if (shadow_weight_en)
            shadow_weight_reg <= weight_in;
    end

    // ========================================================================
    // Stage 0b: Active Weight Register (stationary during computation)
    // Two load paths:
    //   1. weight_en: direct load from weight bus (initial load / refresh)
    //   2. weight_swap: atomic swap from shadow at start of new tile
    // weight_swap takes priority so it matches the clear cycle precisely.
    // ========================================================================
    reg signed [DATA_WIDTH-1:0] weight_reg;

    always @(posedge clk) begin
        if (!rst_n)
            weight_reg <= {DATA_WIDTH{1'b0}};
        else if (weight_swap)
            weight_reg <= shadow_weight_reg;  // [P3] Atomic swap: new tile
        else if (weight_en)
            weight_reg <= weight_in;          // Direct load path (initial/override)
    end

    // ========================================================================
    // Stage 1: Multiply Register (pipeline stage 1)
    // Breaks the Tmul + Tadd critical path. Holds on mac_en=0 → no toggle.
    // ========================================================================
    reg signed [2*DATA_WIDTH-1:0] mul_reg;

    always @(posedge clk) begin
        if (!rst_n)
            mul_reg <= {(2*DATA_WIDTH){1'b0}};
        else if (mac_en)
            mul_reg <= weight_reg * data_in;
        // else: hold — no toggle, saves dynamic power
    end

    // ========================================================================
    // Stage 2: Accumulate Register (pipeline stage 2)
    // Sign-extends mul_reg from 16-bit to ACCUM_WIDTH before adding.
    // clear has priority over mac_en to prevent stale data on tile boundary.
    // ========================================================================
    wire signed [ACCUM_WIDTH-1:0] mul_sign_ext;
    assign mul_sign_ext = {{(ACCUM_WIDTH - 2*DATA_WIDTH){mul_reg[2*DATA_WIDTH-1]}}, mul_reg};

    always @(posedge clk) begin
        if (!rst_n)
            accum_out <= {ACCUM_WIDTH{1'b0}};
        else if (clear)
            accum_out <= {ACCUM_WIDTH{1'b0}};
        else if (mac_en)
            accum_out <= accum_out + mul_sign_ext;
    end

    // ========================================================================
    // Data Pass-through Register
    // Registered for timing closure. Provides the systolic delay between PEs.
    // ========================================================================
    always @(posedge clk) begin
        if (!rst_n)
            data_out <= {DATA_WIDTH{1'b0}};
        else
            data_out <= data_in;
    end

endmodule
