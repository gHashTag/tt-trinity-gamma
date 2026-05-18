// SPDX-License-Identifier: Apache-2.0
// B4 — 8-port mesh router (simple round-robin rotate)
// Author: Dmitrii Vasilev (sole author, admin@t27.ai)
// R-SI-1 compliant: only register-to-register copies (muxes)

`default_nettype none

module depin_b4_mesh8 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  port_in_n,
    input  wire [7:0]  port_in_e,
    input  wire [7:0]  port_in_s,
    input  wire [7:0]  port_in_w,
    input  wire [7:0]  port_in_ne,
    input  wire [7:0]  port_in_nw,
    input  wire [7:0]  port_in_se,
    input  wire [7:0]  port_in_sw,
    output reg  [7:0]  port_out_n,
    output reg  [7:0]  port_out_e,
    output reg  [7:0]  port_out_s,
    output reg  [7:0]  port_out_w,
    output reg  [7:0]  port_out_ne,
    output reg  [7:0]  port_out_nw,
    output reg  [7:0]  port_out_se,
    output reg  [7:0]  port_out_sw
);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            port_out_n  <= 8'd0; port_out_e  <= 8'd0;
            port_out_s  <= 8'd0; port_out_w  <= 8'd0;
            port_out_ne <= 8'd0; port_out_nw <= 8'd0;
            port_out_se <= 8'd0; port_out_sw <= 8'd0;
        end else begin
            // Opposite-direction forwarding (round-robin antipodes)
            port_out_n  <= port_in_s;  port_out_s  <= port_in_n;
            port_out_e  <= port_in_w;  port_out_w  <= port_in_e;
            port_out_ne <= port_in_sw; port_out_sw <= port_in_ne;
            port_out_nw <= port_in_se; port_out_se <= port_in_nw;
        end
    end
endmodule

`default_nettype wire
