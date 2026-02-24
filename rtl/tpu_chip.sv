// ============================================================================
// Module      : tpu_chip
// Description : TPU Hard Macro Chip-Level Wrapper with IO Pads
// Technology  : IHP SG13G2 130nm
//
// Pad Ring:
//   Signal IO Pads:
//     3× sg13g2_IOPadIn     — clk, srstn, tpu_start
//     1× sg13g2_IOPadOut4mA — tpu_done
//   Power Pads:
//     4× sg13g2_IOPadVdd    — Core VDD (distributed for SRAM power integrity)
//     4× sg13g2_IOPadVss    — Core VSS
//     2× sg13g2_IOPadIOVdd  — IO ring VDD
//     2× sg13g2_IOPadIOVss  — IO ring VSS
//   Corner Cells:
//     4× sg13g2_Corner      — LL, LR, UR, UL
//
// Hierarchy:
//   tpu_chip
//     └── tpu_top (hard macro)
//           ├── tpu_core
//           │     ├── addr_sel
//           │     ├── systolic (8×8 MAC)
//           │     ├── systolic_controll
//           │     ├── quantize
//           │     └── write_out
//           ├── 2× RM_IHPSG13_1P_1024x64  (Weight + Data SRAMs)
//           └── 6× RM_IHPSG13_1P_256x64   (Output Banks A/B/C)
//
// ============================================================================

module tpu_chip (
    input  wire clk_pad,
    input  wire srstn_pad,
    input  wire tpu_start_pad,
    output wire tpu_done_pad
);

    // ========================================================================
    // Internal Core-Side Signals
    // ========================================================================
    wire clk_c, srstn_c, tpu_start_c, tpu_done_c;

    // ========================================================================
    // TPU Hard Macro Core
    // ========================================================================
    tpu_top u_tpu_top (
        .clk      (clk_c),
        .srstn    (srstn_c),
        .tpu_start(tpu_start_c),
        .tpu_done (tpu_done_c)
    );

    // ========================================================================
    // Signal IO Pads
    // ========================================================================

    // Clock input pad
    sg13g2_IOPadIn pad_clk (
        .pad(clk_pad),
        .p2c(clk_c)
    );

    // Active-low synchronous reset input pad
    sg13g2_IOPadIn pad_srstn (
        .pad(srstn_pad),
        .p2c(srstn_c)
    );

    // TPU start trigger input pad
    sg13g2_IOPadIn pad_tpu_start (
        .pad(tpu_start_pad),
        .p2c(tpu_start_c)
    );

    // TPU done status output pad (4mA drive)
    sg13g2_IOPadOut4mA pad_tpu_done (
        .pad(tpu_done_pad),
        .c2p(tpu_done_c)
    );

    // ========================================================================
    // Core Power Pads — Distributed for SRAM Power Integrity
    // 4 pairs of VDD/VSS ensure low IR-drop to SRAM macros
    // ========================================================================

    (* keep *) sg13g2_IOPadVdd  pad_vdd_core_n ();   // North side
    (* keep *) sg13g2_IOPadVss  pad_vss_core_n ();
    (* keep *) sg13g2_IOPadVdd  pad_vdd_core_s ();   // South side
    (* keep *) sg13g2_IOPadVss  pad_vss_core_s ();
    (* keep *) sg13g2_IOPadVdd  pad_vdd_core_e ();   // East side
    (* keep *) sg13g2_IOPadVss  pad_vss_core_e ();
    (* keep *) sg13g2_IOPadVdd  pad_vdd_core_w ();   // West side
    (* keep *) sg13g2_IOPadVss  pad_vss_core_w ();

    // ========================================================================
    // IO Ring Power Pads
    // ========================================================================

    (* keep *) sg13g2_IOPadIOVdd pad_vdd_io_n ();    // North side
    (* keep *) sg13g2_IOPadIOVss pad_vss_io_n ();
    (* keep *) sg13g2_IOPadIOVdd pad_vdd_io_s ();    // South side
    (* keep *) sg13g2_IOPadIOVss pad_vss_io_s ();

    // ========================================================================
    // Corner Cells — Required for pad ring continuity
    // ========================================================================

    (* keep *) sg13g2_Corner corner_ll ();   // Lower-Left
    (* keep *) sg13g2_Corner corner_lr ();   // Lower-Right
    (* keep *) sg13g2_Corner corner_ur ();   // Upper-Right
    (* keep *) sg13g2_Corner corner_ul ();   // Upper-Left

endmodule

// ============================================================================
// Blackbox declaration for corner cell (required by synthesis tools)
// ============================================================================

(* blackbox *)
module sg13g2_Corner;
endmodule
