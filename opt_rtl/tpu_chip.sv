// ============================================================================
// Module      : tpu_chip
// Description : TPU Hard Macro Chip-Level Wrapper with IO Pads (Optimized)
// Technology  : IHP SG13G2 130nm
//
// Pad Ring:
//   Signal IO Pads:
//     3× sg13g2_IOPadIn     — clk, srstn, tpu_start
//     1× sg13g2_IOPadOut4mA — tpu_done
//   Power Pads:
//     4× sg13g2_IOPadVdd    — Core VDD
//     4× sg13g2_IOPadVss    — Core VSS
//     2× sg13g2_IOPadIOVdd  — IO ring VDD
//     2× sg13g2_IOPadIOVss  — IO ring VSS
//   Corner Cells:
//     4× sg13g2_Corner      — LL, LR, UR, UL
//
// Hierarchy:
//   tpu_chip
//     └── tpu_top (optimized hard macro)
//           ├── tpu_core (optimized datapath)
//           │     ├── addr_gen
//           │     ├── systolic_array (8×8 pipelined PEs)
//           │     ├── systolic_controller
//           │     ├── quantizer (pipelined)
//           │     └── output_writer
//           ├── 2× RM_IHPSG13_1P_256x64  (Weight + Data SRAMs)
//           └── 6× RM_IHPSG13_1P_64x64   (Output Banks A/B/C)
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
    // TPU Hard Macro Core (Optimized)
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
    sg13g2_IOPadIn pad_clk (
        .pad(clk_pad),
        .p2c(clk_c)
    );

    sg13g2_IOPadIn pad_srstn (
        .pad(srstn_pad),
        .p2c(srstn_c)
    );

    sg13g2_IOPadIn pad_tpu_start (
        .pad(tpu_start_pad),
        .p2c(tpu_start_c)
    );

    sg13g2_IOPadOut4mA pad_tpu_done (
        .pad(tpu_done_pad),
        .c2p(tpu_done_c)
    );

    // ========================================================================
    // Core Power Pads — Distributed for SRAM Power Integrity
    // ========================================================================
    (* keep *) sg13g2_IOPadVdd  pad_vdd_core_n ();
    (* keep *) sg13g2_IOPadVss  pad_vss_core_n ();
    (* keep *) sg13g2_IOPadVdd  pad_vdd_core_s ();
    (* keep *) sg13g2_IOPadVss  pad_vss_core_s ();
    (* keep *) sg13g2_IOPadVdd  pad_vdd_core_e ();
    (* keep *) sg13g2_IOPadVss  pad_vss_core_e ();
    (* keep *) sg13g2_IOPadVdd  pad_vdd_core_w ();
    (* keep *) sg13g2_IOPadVss  pad_vss_core_w ();

    // ========================================================================
    // IO Ring Power Pads
    // ========================================================================
    (* keep *) sg13g2_IOPadIOVdd pad_vdd_io_n ();
    (* keep *) sg13g2_IOPadIOVss pad_vss_io_n ();
    (* keep *) sg13g2_IOPadIOVdd pad_vdd_io_s ();
    (* keep *) sg13g2_IOPadIOVss pad_vss_io_s ();

    // ========================================================================
    // Corner Cells
    // ========================================================================
    (* keep *) sg13g2_Corner corner_ll ();
    (* keep *) sg13g2_Corner corner_lr ();
    (* keep *) sg13g2_Corner corner_ur ();
    (* keep *) sg13g2_Corner corner_ul ();

endmodule

// ============================================================================
// Blackbox declaration for corner cell
// ============================================================================
(* blackbox *)
module sg13g2_Corner;
endmodule
