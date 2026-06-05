// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/gf16_to_posit16.v
// GoldenFloat16 <-> Posit16 (es=2) converters (correct, variable-length regime).
// Posit16, es=2: [S(1) | regime (variable run + terminator) | exp (<=2) | fraction];
// useed = 2^(2^es) = 16; value = (-1)^S * 2^(4k+e) * (1+frac); 0x0000 = 0, 0x8000 =
// NaR. (The prior version assumed FIXED fields [S|R(1)|E(3)|M(11)] -- not a valid
// posit -- and was wrong in both directions. Both rewritten + verified by
// test/posit16_codec_verify.py: decoder exhaustive over 65536 codes, encoder by
// round-trip <= 1 posit ULP.)

`default_nettype none
// GF16 -> Posit16 (es=2) encoder.
// REWRITTEN 2026-06: the previous version emitted FIXED posit fields, which is not a
// valid posit (posits use a variable-length regime). This builds the standard posit16
// (es=2, useed=16): scale = gf_exp - 31 = 4k + e; the regime encodes k (k+1 ones + a
// 0 for k>=0, or -k zeros + a 1 for k<0), then the 2-bit exponent e, then the GF16
// mantissa, MSB-aligned into the 15-bit magnitude, round-to-nearest, then two's-
// complemented for negatives. For the GF16 exponent range the regime always fits
// (k in [-8,7]); a rounding carry saturates to maxpos. Specials: GF zero -> 0x0000,
// GF Inf/NaN -> NaR 0x8000. Verified by test/posit16_codec_verify.py (round-trip vs
// the exhaustively-verified decoder, <= 1 posit ULP).
module gf16_to_posit16 (
    input  wire [15:0] gf_in,
    output reg  [15:0] posit_out
);
    wire        sign    = gf_in[15];
    wire [5:0]  gf_exp  = gf_in[14:9];
    wire [8:0]  gf_mant = gf_in[8:0];

    wire is_gf_zero = (gf_exp == 6'd0) && (gf_mant == 9'd0);
    wire is_gf_spec = (gf_exp == 6'd63);                 // Inf or NaN -> NaR

    wire signed [6:0] scale = $signed({1'b0, gf_exp}) - 7'sd31;  // 4k + e
    wire signed [6:0] k     = scale >>> 2;                       // floor(scale/4)
    wire [1:0]        e     = scale[1:0];                        // scale mod 4
    wire [6:0]        nk    = k[6] ? (-k) : 7'd0;                // |k| for k<0 (<=8)

    reg  [23:0] pay;        // payload, MSB-first from bit 23
    integer i, bp;
    reg  [15:0] rounded;
    reg  [14:0] field;
    reg  [15:0] mag;

    always @(*) begin
        pay = 24'd0; bp = 23;
        if (k >= 0) begin
            for (i = 0; i < 8; i = i + 1)
                if (i <= k) begin pay[bp] = 1'b1; bp = bp - 1; end   // (k+1) ones
            pay[bp] = 1'b0; bp = bp - 1;                             // terminator 0
        end else begin
            for (i = 0; i < 8; i = i + 1)
                if (i < nk) begin pay[bp] = 1'b0; bp = bp - 1; end   // (-k) zeros
            pay[bp] = 1'b1; bp = bp - 1;                             // terminator 1
        end
        pay[bp] = e[1]; bp = bp - 1;
        pay[bp] = e[0]; bp = bp - 1;
        for (i = 8; i >= 0; i = i - 1) begin pay[bp] = gf_mant[i]; bp = bp - 1; end

        rounded = {1'b0, pay[23:9]} + pay[8];        // top 15 bits, round-half-up
        field   = rounded[15] ? 15'h7FFF : rounded[14:0];  // rounding carry -> maxpos
        mag     = {1'b0, field};

        if (is_gf_zero)      posit_out = 16'h0000;
        else if (is_gf_spec) posit_out = 16'h8000;   // NaR
        else                 posit_out = sign ? (~mag + 16'd1) : mag;
    end

endmodule

// Posit16 (es=2) -> GF16 decoder.
// REWRITTEN 2026-06: the previous version assumed FIXED fields [S|R(1)|E(3)|M(11)] --
// but a real posit has a VARIABLE-LENGTH regime (run of equal bits after the sign,
// terminated by the opposite bit), so the old decode was simply wrong. This decodes
// the standard posit16, es=2: useed = 2^(2^es) = 16. value =
// (-1)^S * 2^(4k + e) * (1 + frac), where k is the regime value, e the (<=2-bit)
// exponent, frac the trailing fraction. Specials: 0x0000 -> 0, 0x8000 (NaR) -> NaN.
// Exhaustively verified over all 65536 posit codes by test/posit16_codec_verify.py.
module posit16_to_gf16 (
    input  wire [15:0] posit_in,
    output reg  [15:0] gf_out
);
    // count leading ones of a 15-bit value (the regime run length, 1..15)
    function [4:0] clo15;
        input [14:0] x;
        integer i; reg done;
        begin
            clo15 = 5'd0; done = 1'b0;
            for (i = 14; i >= 0; i = i - 1)
                if (!done) begin
                    if (x[i]) clo15 = clo15 + 5'd1; else done = 1'b1;
                end
        end
    endfunction

    wire        sign  = posit_in[15];
    wire [15:0] mag   = sign ? (~posit_in + 16'd1) : posit_in;  // 2's-comp magnitude
    wire [14:0] field = mag[14:0];                              // regime|exp|frac
    wire        r0    = field[14];
    wire [14:0] runf  = r0 ? field : ~field;                    // leading 1s = the run
    wire [4:0]  run   = clo15(runf);                            // 1..15
    wire [4:0]  consumed = (run == 5'd15) ? 5'd15 : (run + 5'd1); // run + terminator
    wire signed [6:0] k = r0 ? ($signed({2'b00, run}) - 7'sd1)
                              : -$signed({2'b00, run});
    wire [14:0] rem  = field << consumed;          // exp+frac left-aligned
    wire [1:0]  pexp = rem[14:13];
    wire [12:0] frac = rem[12:0];
    wire signed [9:0] scale = ($signed({{3{k[6]}}, k}) <<< 2) + $signed({8'b0, pexp});
    wire signed [9:0] gexp  = scale + 10'sd31;     // gf16 biased exponent

    reg [9:0] mant_r;       // rounded mantissa (9 bits + carry)
    reg signed [9:0] fexp;
    reg [8:0] fmant;

    always @(*) begin
        mant_r = 10'd0; fexp = 10'sd0; fmant = 9'd0;
        if (posit_in == 16'h0000)
            gf_out = 16'h0000;                     // zero
        else if (posit_in == 16'h8000)
            gf_out = 16'hFE01;                     // NaR -> NaN
        else begin
            mant_r = {1'b0, frac[12:4]} + frac[3]; // round-half-up to 9 bits
            if (mant_r[9]) begin                   // mantissa carry-out
                fexp = gexp + 10'sd1; fmant = 9'd0;
            end else begin
                fexp = gexp; fmant = mant_r[8:0];
            end
            if (fexp <= 10'sd0)
                gf_out = sign ? 16'h8000 : 16'h0000;        // underflow -> signed 0
            else if (fexp >= 10'sd63)
                gf_out = sign ? 16'hFE00 : 16'h7E00;        // overflow -> signed Inf
            else
                gf_out = {sign, fexp[5:0], fmant};
        end
    end

endmodule
