// champion_bpb_oracle.v — Trinity TRI silicon: champion BPB constant ROM
//
// Exposes the canonical Trinity invariants for host-software chip
// authenticity verification:
//   * phi-anchor 0x47C0 (TG-TRIAD-X Theorem 36.1) on {uio_out, uo_out}
//   * Champion BPB lock 2.2393 (Q4.12 fixed point = 16'h23D3)
//
// Pure combinational. Zero flops. Folds into top without tile
// increase. R-SI-1 compliant: no standalone star operators.
//
// Selector encoding:
//   2'b00 -> anchor   (16'h47C0)
//   2'b01 -> bpb_lock (16'h23D3, 2.2393 in Q4.12)
//   2'b10 -> version  (16'h0100, v1.0)
//   2'b11 -> reserved (16'h0000)
//
// Apache-2.0
// SPDX-License-Identifier: Apache-2.0
// Author: Dmitrii Vasilev <admin@t27.ai>

`default_nettype none

module champion_bpb_oracle #(
    parameter [15:0] ANCHOR    = 16'h47C0,
    parameter [15:0] BPB_LOCK  = 16'h23D3,
    parameter [15:0] VERSION   = 16'h0100
) (
    input  wire [1:0]  sel,
    output wire [15:0] data_out,
    output wire        valid
);

    assign valid = 1'b1;

    assign data_out =
        (sel == 2'b00) ? ANCHOR   :
        (sel == 2'b01) ? BPB_LOCK :
        (sel == 2'b10) ? VERSION  :
                         16'h0000;

endmodule

`default_nettype wire
