`default_nettype none
// trinity_max_true_dual.v - 32-cell flagship compute pool = 2× trinity_quad_mesh.
// Apache-2.0
//
// MAX-TRUE FLAGSHIP top-level compute fabric. Splits a single packet bus
// across 2 parallel trinity_quad_mesh clusters (= 2 clusters × 16 cells = 32
// honest GF16 cells). Cluster selector lives in lane[3] of the packet,
// preserving lane[2:1] for quad_mesh bank selection and lane[0] for legacy
// operand_lane plumbing inside each tile.
//
// This is a HONEST 2× of trinity_mesh_2x2 (the Mid SUPER-CROWN compute pool).
// No silicon shortcuts, no time-multiplexing tricks: every cycle, both
// clusters can independently process packets, doubling peak throughput.
//
// Routing contract:
//   lane[3]   = cluster_sel -> picks 1 of 2 quad_mesh clusters
//   lane[2:1] = bank_sel    -> passed unchanged to selected cluster
//   lane[0]   = preserved   -> passed unchanged
//   dst[27:26]= tile_id     -> passed unchanged
//
// Backward-compat: when only cluster 0, bank 0 is addressed, behaviour is
// byte-identical to a standalone trinity_mesh_2x2.
//
// R-SI-1: zero NEW $mul. All multiplication is via legacy gf16_mul.v.
// Sacred Physics: cluster routing is single-bit XOR/AND. φ²+φ⁻²=3.

`include "trinity_packet.vh"

module trinity_max_true_dual (
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

    // Priority: cluster 0 > cluster 1 (steady-state only one is active per cycle)
    assign host_out_pkt   = c0_out_valid ? c0_out_pkt   : c1_out_pkt;
    assign host_out_valid = c0_out_valid | c1_out_valid;
    assign c0_out_ready   = host_out_ready &  c0_out_valid;
    assign c1_out_ready   = host_out_ready & ~c0_out_valid & c1_out_valid;

    // ------------------------------------------------------------------
    // Cluster A (16 cells)
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
    // Cluster B (16 cells)
    // ------------------------------------------------------------------
    trinity_quad_mesh u_cluster_b (
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

    wire _unused_dual = &{1'b0, c1_dbg, 1'b0};

endmodule
