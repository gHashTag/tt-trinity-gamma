// SPDX-License-Identifier: Apache-2.0
// stoch_round_v2.v -- CORRECTED Wave-41 stochastic rounding.
//
// The shipped stoch_round claims "round up with probability = fractional part" but
// the code does `if (data_in[0] && lfsr[0]) data_out <= data_in+1`, i.e. it rounds
// up with probability 0.5 ONLY when the LSB is set and 0 otherwise -- unrelated to
// any fractional part, and its interface has no residual/discarded-bits input from
// which a fractional part could be formed. So it is not stochastic rounding.
//
// True stochastic rounding: when quantizing a value whose discarded low bits form a
// fraction f in [0,1), round up with probability EXACTLY f. This unit takes the
// kept value, the discarded fraction `frac` (Q0.8, f = frac/256), and rounds up iff
// a uniform random byte < frac -> P(round up) = frac/256 = f. That makes the
// expected rounded value equal the true value (unbiased), which is the whole point
// of stochastic rounding for low-precision accumulation. Random source is an
// internal maximal-length 16-bit LFSR (taps 16,14,13,11), seedable.
// Verified unbiased: test/power_waves_audit.py. Dead-code library unit (not
// instantiated); this is the corrected Wave-41 reference. R-SI-1: zero `*`.

`default_nettype none
module stoch_round_v2 (
    input  wire        clk,
    input  wire        reset_n,
    input  wire        ena,          // assert to round this cycle
    input  wire [15:0] value,        // kept value (e.g. truncated GF16 / int)
    input  wire [7:0]  frac,         // discarded fraction, Q0.8 (f = frac/256)
    output reg  [15:0] result,       // value + stochastic carry
    output reg         valid
);
    reg [15:0] lfsr;
    wire fb = lfsr[15] ^ lfsr[13] ^ lfsr[12] ^ lfsr[10];   // maximal-length

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            lfsr   <= 16'hACE1;
            result <= 16'h0000;
            valid  <= 1'b0;
        end else if (ena) begin
            lfsr <= {lfsr[14:0], fb};
            // round up iff uniform random byte < frac  ->  P = frac/256
            result <= value + ((lfsr[7:0] < frac) ? 16'd1 : 16'd0);
            valid  <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end
endmodule

`default_nettype wire
// Wave-41: Stochastic rounding for quantization (corrected). R-SI-1: zero `*`.
