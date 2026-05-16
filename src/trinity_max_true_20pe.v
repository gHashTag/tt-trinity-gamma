`default_nettype none
// trinity_max_true_20pe.v - 20-cell flagship compute pool fitted to TT 4x5 tiles.
// Apache-2.0
//
// MAX-TRUE 4x5 TILE EDITION. Replaces trinity_max_true_dual (2x quad_mesh = 32 PE)
// with one quad_mesh (16 PE) + one mesh_2x2 (4 PE) = 20 honest GF16 PE total.
//
// Rationale: TTSKY26b enforces max 20 tiles per single-design submission.
// 4x5 = 20 tiles is the canonical fit. The 32-PE dual configuration exceeded
// this ceiling. 20 PE retains the dual-cluster routing topology, the dbg
// contract, and is byte-identical to a 16-PE quad_mesh + 4-PE mesh_2x2.
//
// Port interface is IDENTICAL to trinity_max_true_dual — drop-in replacement
// in tt_um_trinity_max_true.v with no top-level wiring changes.
//
// Routing contract:
//   lane[3]   = cluster_sel -> 0 = 16-PE quad cluster, 1 = 4-PE mesh cluster
//   lane[2:1] = bank_sel    -> passed unchanged to selected cluster
//   lane[0]   = preserved   -> passed unchanged
//   dst[27:26]= tile_id     -> passed unchanged
//
// Backward-compat: cluster 0, bank 0 path is byte-identical to a standalone
// trinity_mesh_2x2. All legacy GF16 dot4 canonical paths preserved.
//
// R-SI-1: zero NEW $mul. Cluster routing is single-bit XOR/AND.
// Sacred Physics: phi^2 + phi^-2 = 3. φ-anchor preserved upstream.

`include "trinity_packet.vh"

module trinity_max_true_20pe (
    input  wire                       clk,
    input  wire                       rst_n,

    // Host injection
    input  wire [`TRN_PKT_W-1:0]      host_in_pkt,
    input  wire                       host_in_valid,
    output wire                       host_in_ready,

    // Host ejection
    output wire [`TRN_PKT_W-1:0]      host_out_pkt,
    output wire                       host_out_valid,
    input  wire                       host_out_ready,

    // Debug: tile 0 result of cluster 0 bank 0 (preserves Mid debug contract)
    output wire [15:0]                dbg_tile0_result
);

    // ------------------------------------------------------------------
    // Cluster selector: lane[3] = pkt[23]
    //   0 -> trinity_quad_mesh (16 PE)
    //   1 -> trinity_mesh_2x2  ( 4 PE)
    // ------------------------------------------------------------------
    wire cluster_sel = host_in_pkt[23];

    wire c0_valid = host_in_valid && (cluster_sel == 1'b0);
    wire c1_valid = host_in_valid && (cluster_sel == 1'b1);
    wire c0_ready, c1_ready;

    assign host_in_ready = cluster_sel ? c1_ready : c0_ready;

    // ------------------------------------------------------------------
    // Per-cluster ejection
    // ------------------------------------------------------------------
    wire [`TRN_PKT_W-1:0] c0_out_pkt, c1_out_pkt;
    wire                  c0_out_valid, c1_out_valid;
    wire                  c0_out_ready, c1_out_ready;
    wire [15:0]           c0_dbg, c1_dbg;

    // Priority: cluster 0 > cluster 1 (steady-state only one active per cycle)
    assign host_out_pkt   = c0_out_valid ? c0_out_pkt   : c1_out_pkt;
    assign host_out_valid = c0_out_valid | c1_out_valid;
    assign c0_out_ready   = host_out_ready &  c0_out_valid;
    assign c1_out_ready   = host_out_ready & ~c0_out_valid & c1_out_valid;

    // ------------------------------------------------------------------
    // Cluster A: 16-PE quad_mesh (4 banks x 4 GF16 PE)
    // ------------------------------------------------------------------
    trinity_quad_mesh u_cluster_a (
        .clk             (clk),
        .rst_n           (rst_n),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (c0_valid),
        .host_in_ready   (c0_ready),
        .host_out_pkt    (c0_out_pkt),
        .host_out_valid  (c0_out_valid),
        .host_out_ready  (c0_out_ready),
        .dbg_tile0_result(c0_dbg)
    );

    // ------------------------------------------------------------------
    // Cluster B: 4-PE mesh_2x2 (1 bank x 4 GF16 PE)
    // ------------------------------------------------------------------
    trinity_mesh_2x2 u_cluster_b (
        .clk             (clk),
        .rst_n           (rst_n),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (c1_valid),
        .host_in_ready   (c1_ready),
        .host_out_pkt    (c1_out_pkt),
        .host_out_valid  (c1_out_valid),
        .host_out_ready  (c1_out_ready),
        .dbg_tile0_result(c1_dbg)
    );

    assign dbg_tile0_result = c0_dbg;

    wire _unused_20pe = &{1'b0, c1_dbg, 1'b0};

endmodule
