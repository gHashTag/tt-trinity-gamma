// SPDX-License-Identifier: Apache-2.0
// =============================================================================
// d2d_holo_mesh.v — D2D Holographic Mesh Router Stub (4-port N/E/S/W)
// =============================================================================
//
// TRI-1 GAMMA — MAX-TRUE NEUROMORPHIC FLAGSHIP (8x4 = 32 tiles)
// Author  : Dmitrii Vasilev <admin@t27.ai>
// Shuttle : TTSKY26b, sky130A
//
// D2D cross-die mesh port stubs (4 directions: N/E/S/W)
// Adapted from tt-trinity-holo (TTSKY26c, 1x2) D2D port pattern.
//
// Pin mapping (uio[7:0]):
//   uio[0] = n_tx  — North TX  (output)
//   uio[1] = e_tx  — East TX   (output)
//   uio[2] = s_tx  — South TX  (output)
//   uio[3] = w_tx  — West TX   (output, SYNC strobe — LAYER-FROZEN gate)
//   uio[4] = n_rx  — North RX  (input, driven from external)
//   uio[5] = e_rx  — East RX   (input)
//   uio[6] = s_rx  — South RX  (input)
//   uio[7] = w_rx  — West RX   (input)
//
// LAYER-FROZEN gate (PhD Theorem 36.1, R18):
//   uio[3] (w_tx = SYNC strobe) is gated by layer_frozen register.
//   When layer_frozen=1, w_tx is always 0 (frozen — no SYNC broadcast).
//   This prevents spurious cross-die synchronisation after training converges.
//
// Protocol: R5-HONEST stub — full D2D mesh in a future wave.
//   TX pins driven by registered internal data (spike summary / GF16 tag).
//   RX pins latched synchronously for downstream processing.
//
// R-SI-1: ZERO `*` operators. Pure XOR/shift/add.
// Verilog-2005: NO SystemVerilog, NO logic, one reg per line.
//
// Anchor: phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module d2d_holo_mesh (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       ena,
    // Spike summary from cortex (4-bit count, 8-bit vector)
    input  wire [3:0] spike_count,
    input  wire [7:0] spike_vec,
    // GF16 tag from mesh (upper nibble of result for cross-die routing)
    input  wire [3:0] gf_tag,
    // Layer-frozen control (PhD Theorem 36.1, R18)
    // Set by FSM when holographic attractor has converged
    input  wire       layer_frozen,
    // RX inputs from external (4 directions)
    input  wire       n_rx,
    input  wire       e_rx,
    input  wire       s_rx,
    input  wire       w_rx,
    // TX outputs to external (4 directions)
    output reg        n_tx,
    output reg        e_tx,
    output reg        s_tx,
    output reg        w_tx,     // SYNC strobe: gated by layer_frozen
    // Received data latched (for downstream inspection)
    output reg        n_rx_q,
    output reg        e_rx_q,
    output reg        s_rx_q,
    output reg        w_rx_q,
    // Mesh OK: active when not in reset
    output wire       mesh_ok
);

    // -----------------------------------------------------------------------
    // TX logic
    // N: broadcast spike count MSB (highest activity indicator)
    // E: broadcast spike count LSB
    // S: broadcast GF16 tag[0] (route tag bit)
    // W: SYNC strobe — asserted when spike_count == 4'h8 (all columns fired)
    //    GATED by layer_frozen (PhD Theorem 36.1 R18): if frozen, w_tx = 0
    // -----------------------------------------------------------------------
    wire sync_strobe_raw;
    assign sync_strobe_raw = (spike_count == 4'h8);   // all 8 columns spiking

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n_tx <= 1'b0;
            e_tx <= 1'b0;
            s_tx <= 1'b0;
            w_tx <= 1'b0;
        end else if (ena) begin
            // N: upper activity bit from spike vector popcount[3]
            n_tx <= spike_count[3];
            // E: lower activity bit from spike vector popcount[0]
            e_tx <= spike_count[0];
            // S: GF16 route tag bit (die-to-die packet header bit)
            s_tx <= gf_tag[0];
            // W: SYNC strobe GATED by layer_frozen (R18 LAYER-FROZEN)
            // When layer_frozen=1: w_tx=0 (SYNC disabled, PhD Thm 36.1)
            // When layer_frozen=0: w_tx=sync_strobe_raw (normal operation)
            w_tx <= sync_strobe_raw & ~layer_frozen;
        end else begin
            n_tx <= 1'b0;
            e_tx <= 1'b0;
            s_tx <= 1'b0;
            w_tx <= 1'b0;
        end
    end

    // -----------------------------------------------------------------------
    // RX latch: synchronously sample all 4 incoming directions
    // -----------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            n_rx_q <= 1'b0;
            e_rx_q <= 1'b0;
            s_rx_q <= 1'b0;
            w_rx_q <= 1'b0;
        end else if (ena) begin
            n_rx_q <= n_rx;
            e_rx_q <= e_rx;
            s_rx_q <= s_rx;
            w_rx_q <= w_rx;
        end
    end

    // -----------------------------------------------------------------------
    // Mesh OK: high when out of reset and enabled
    // -----------------------------------------------------------------------
    assign mesh_ok = ena;

    // Suppress unused-signal lint warnings
    wire _unused = &{1'b0, spike_vec, 1'b0};

endmodule
