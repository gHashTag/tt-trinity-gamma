`default_nettype none
// gf16_popcount16.v — 3-stage pipelined XOR-popcount for 16-element ternary dot product
// Apache-2.0
//
// L-S19: Variant of gf16_popcount for N_ELEMS=16 (used by vsa_matmul_16x16).
//        LATENCY = 3 cycles. Fmax target: 150 MHz.
//        valid_out arrives 3 clock edges after valid_in.
//
// ANCHOR: φ²+φ⁻²=3 · DOI 10.5281/zenodo.19227877 · Apache-2.0 · EPIC gHashTag/trinity-fpga#51
//
// Pipeline stages:
//   Stage 1: Decode 16 element pairs → same[15:0], diff[15:0]; register + valid
//   Stage 2: Popcount tree (16→5 bits) for both; register + valid
//   Stage 3: Final subtraction → signed 8-bit result; register + valid_out
//
// Parameters:
//   N_ELEMS = 16
//   LATENCY = 3

module gf16_popcount16 #(
    parameter N_ELEMS = 16,
    parameter LATENCY = 3
) (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        valid_in,
    input  wire [31:0] a_row,     // 16 elements × 2 bits
    input  wire [31:0] b_row,     // 16 elements × 2 bits
    output reg         valid_out,
    output reg  [7:0]  result
);

    // -------------------------------------------------------------------
    // Stage 1: combinational decode, register
    // -------------------------------------------------------------------
    wire [15:0] s1_same_comb;
    wire [15:0] s1_diff_comb;

    genvar k;
    generate
        for (k = 0; k < 16; k = k + 1) begin : gen_decode
            // Verilog-2005 compatible: extract 2 bits using shift and mask
            wire [1:0] ae = (a_row >> (k * 2)) & 2'b11;
            wire [1:0] be = (b_row >> (k * 2)) & 2'b11;
            wire active = ~ae[1] & ~be[1];
            assign s1_same_comb[k] = active & ~(ae[0] ^ be[0]);
            assign s1_diff_comb[k] = active &  (ae[0] ^ be[0]);
        end
    endgenerate

    (* keep = "true" *) (* no_retiming = "true" *) reg [15:0] s1_same, s1_diff;
    (* keep = "true" *) (* no_retiming = "true" *) reg        s1_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_same  <= 16'b0;
            s1_diff  <= 16'b0;
            s1_valid <= 1'b0;
        end else begin
            s1_same  <= s1_same_comb;
            s1_diff  <= s1_diff_comb;
            s1_valid <= valid_in;
        end
    end

    // -------------------------------------------------------------------
    // Stage 2: 4-level adder tree for 16 bits → 5-bit count
    // -------------------------------------------------------------------
    // 8 pairs → 4 × 2-bit sums → 2 × 3-bit sums → 1 × 4-bit sum → 5-bit total
    wire [1:0] sp0, sp1, sp2, sp3, sp4, sp5, sp6, sp7;
    wire [1:0] sn0, sn1, sn2, sn3, sn4, sn5, sn6, sn7;
    assign sp0 = {1'b0, s1_same[0]}  + {1'b0, s1_same[1]};
    assign sp1 = {1'b0, s1_same[2]}  + {1'b0, s1_same[3]};
    assign sp2 = {1'b0, s1_same[4]}  + {1'b0, s1_same[5]};
    assign sp3 = {1'b0, s1_same[6]}  + {1'b0, s1_same[7]};
    assign sp4 = {1'b0, s1_same[8]}  + {1'b0, s1_same[9]};
    assign sp5 = {1'b0, s1_same[10]} + {1'b0, s1_same[11]};
    assign sp6 = {1'b0, s1_same[12]} + {1'b0, s1_same[13]};
    assign sp7 = {1'b0, s1_same[14]} + {1'b0, s1_same[15]};

    assign sn0 = {1'b0, s1_diff[0]}  + {1'b0, s1_diff[1]};
    assign sn1 = {1'b0, s1_diff[2]}  + {1'b0, s1_diff[3]};
    assign sn2 = {1'b0, s1_diff[4]}  + {1'b0, s1_diff[5]};
    assign sn3 = {1'b0, s1_diff[6]}  + {1'b0, s1_diff[7]};
    assign sn4 = {1'b0, s1_diff[8]}  + {1'b0, s1_diff[9]};
    assign sn5 = {1'b0, s1_diff[10]} + {1'b0, s1_diff[11]};
    assign sn6 = {1'b0, s1_diff[12]} + {1'b0, s1_diff[13]};
    assign sn7 = {1'b0, s1_diff[14]} + {1'b0, s1_diff[15]};

    wire [4:0] cnt_pos_comb =
        ({3'b000, sp0} + {3'b000, sp1}) + ({3'b000, sp2} + {3'b000, sp3}) +
        ({3'b000, sp4} + {3'b000, sp5}) + ({3'b000, sp6} + {3'b000, sp7});
    wire [4:0] cnt_neg_comb =
        ({3'b000, sn0} + {3'b000, sn1}) + ({3'b000, sn2} + {3'b000, sn3}) +
        ({3'b000, sn4} + {3'b000, sn5}) + ({3'b000, sn6} + {3'b000, sn7});

    (* keep = "true" *) (* no_retiming = "true" *) reg [4:0] s2_cnt_pos, s2_cnt_neg;
    (* keep = "true" *) (* no_retiming = "true" *) reg       s2_valid;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_cnt_pos <= 5'b0;
            s2_cnt_neg <= 5'b0;
            s2_valid   <= 1'b0;
        end else begin
            s2_cnt_pos <= cnt_pos_comb;
            s2_cnt_neg <= cnt_neg_comb;
            s2_valid   <= s1_valid;
        end
    end

    // -------------------------------------------------------------------
    // Stage 3: final subtraction
    // result ∈ [-16..+16], needs 6 bits signed; sign-extend to 8 bits
    // -------------------------------------------------------------------
    wire signed [5:0] sub_comb = {1'b0, s2_cnt_pos} - {1'b0, s2_cnt_neg};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            result    <= 8'b0;
            valid_out <= 1'b0;
        end else begin
            result    <= {{2{sub_comb[5]}}, sub_comb};
            valid_out <= s2_valid;
        end
    end

endmodule
