`default_nettype none
// gf16_popcount.v — 3-stage pipelined XOR-popcount for ternary dot product
// Apache-2.0
//
// L-S19: 3-stage pipeline raising Fmax from 50 MHz → 150 MHz (x3 TOPS).
//        LATENCY = 3 cycles (valid_out arrives 3 clock edges after valid_in).
//
// ANCHOR: φ²+φ⁻²=3 · DOI 10.5281/zenodo.19227877 · Apache-2.0 · EPIC gHashTag/trinity-fpga#51
//
// Computes the ternary inner product of two 8-element ternary vectors.
// Each element is 2-bit encoded: 00=+1, 01=-1, 10=0, 11=0
//
// Pipeline stages:
//   Stage 1 (registered): Decode magnitude (nonzero) and sign bits for each pair.
//     Compute per-element same_sign and diff_sign flags. Register + valid.
//   Stage 2 (registered): Popcount tree — sum same_sign[7:0] → count_pos[3:0],
//     sum diff_sign[7:0] → count_neg[3:0]. Register + valid.
//   Stage 3 (registered): Final subtraction result = count_pos - count_neg.
//     Sign-extend to 8 bits. Register + valid_out.
//
// Timing: valid_in asserted at edge T → valid_out at edge T+3.
//
// Parameters:
//   N_ELEMS = 8 (elements per vector; hard-coded for this variant)
//   LATENCY = 3

module gf16_popcount #(
    parameter N_ELEMS = 8,
    parameter LATENCY = 3
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,        // input data valid this cycle
    input  wire [15:0] a_row,           // 8 elements × 2 bits
    input  wire [15:0] b_row,           // 8 elements × 2 bits
    output reg         valid_out,       // output valid (3 cycles after valid_in)
    output reg  [7:0]  result           // signed 8-bit inner product
);

    // -------------------------------------------------------------------
    // Stage 1: register decode results + valid
    // -------------------------------------------------------------------
    // Combinational: for each element k, compute same_sign and diff_sign
    wire [7:0] s1_same_comb;
    wire [7:0] s1_diff_comb;

    genvar k;
    generate
        for (k = 0; k < 8; k = k + 1) begin : gen_decode
            // Verilog-2005 compatible: extract 2 bits using shift and mask
            wire [1:0] ae = (a_row >> (k * 2)) & 2'b11;
            wire [1:0] be = (b_row >> (k * 2)) & 2'b11;
            wire active = ~ae[1] & ~be[1];  // both nonzero
            assign s1_same_comb[k] = active & ~(ae[0] ^ be[0]);  // same sign
            assign s1_diff_comb[k] = active &  (ae[0] ^ be[0]);  // diff sign
        end
    endgenerate

    (* keep = "true" *) (* no_retiming = "true" *) reg [7:0] s1_same, s1_diff;
    (* keep = "true" *) (* no_retiming = "true" *) reg       s1_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_same  <= 8'b0;
            s1_diff  <= 8'b0;
            s1_valid <= 1'b0;
        end else begin
            s1_same  <= s1_same_comb;
            s1_diff  <= s1_diff_comb;
            s1_valid <= valid_in;
        end
    end

    // -------------------------------------------------------------------
    // Stage 2: popcount tree + register
    // Explicit 2-level adder tree for 8 bits → count in [0..8], fits 4 bits
    // -------------------------------------------------------------------
    // Level 1: four 2-bit partial sums
    wire [1:0] ps_comb [0:3];
    wire [1:0] pn_comb [0:3];
    assign ps_comb[0] = {1'b0, s1_same[0]} + {1'b0, s1_same[1]};
    assign ps_comb[1] = {1'b0, s1_same[2]} + {1'b0, s1_same[3]};
    assign ps_comb[2] = {1'b0, s1_same[4]} + {1'b0, s1_same[5]};
    assign ps_comb[3] = {1'b0, s1_same[6]} + {1'b0, s1_same[7]};
    assign pn_comb[0] = {1'b0, s1_diff[0]} + {1'b0, s1_diff[1]};
    assign pn_comb[1] = {1'b0, s1_diff[2]} + {1'b0, s1_diff[3]};
    assign pn_comb[2] = {1'b0, s1_diff[4]} + {1'b0, s1_diff[5]};
    assign pn_comb[3] = {1'b0, s1_diff[6]} + {1'b0, s1_diff[7]};

    // Level 2: two 3-bit partial sums, then one 4-bit sum
    wire [3:0] cnt_pos_comb = ({2'b00, ps_comb[0]} + {2'b00, ps_comb[1]}) +
                               ({2'b00, ps_comb[2]} + {2'b00, ps_comb[3]});
    wire [3:0] cnt_neg_comb = ({2'b00, pn_comb[0]} + {2'b00, pn_comb[1]}) +
                               ({2'b00, pn_comb[2]} + {2'b00, pn_comb[3]});

    (* keep = "true" *) (* no_retiming = "true" *) reg [3:0] s2_cnt_pos, s2_cnt_neg;
    (* keep = "true" *) (* no_retiming = "true" *) reg       s2_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_cnt_pos <= 4'b0;
            s2_cnt_neg <= 4'b0;
            s2_valid   <= 1'b0;
        end else begin
            s2_cnt_pos <= cnt_pos_comb;
            s2_cnt_neg <= cnt_neg_comb;
            s2_valid   <= s1_valid;
        end
    end

    // -------------------------------------------------------------------
    // Stage 3: final subtraction, sign-extend, register
    // -------------------------------------------------------------------
    // result ∈ [-8..+8], needs 5 bits signed; we sign-extend to 8 bits
    wire signed [4:0] sub_comb = {1'b0, s2_cnt_pos} - {1'b0, s2_cnt_neg};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result    <= 8'b0;
            valid_out <= 1'b0;
        end else begin
            result    <= {{3{sub_comb[4]}}, sub_comb};
            valid_out <= s2_valid;
        end
    end

endmodule
