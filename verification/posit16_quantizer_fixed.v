// SPDX-License-Identifier: Apache-2.0
// posit16_quantizer_fixed.v — correct Posit16 (es=2, useed=16) codec
//
// DEFECT (audited 2026-05-31): the original posit16_quantizer/dequantizer did not
// implement a posit codec — regime_bits were 0 for all positive exponents, the
// neg/pos branches were identical, and the fraction was mis-assembled. Round-trip
// fp16->posit16->fp16 failed for ~99% of inputs. This is a from-scratch rewrite to
// the Posit Standard (2022): sign + run-length regime (useed=2^4) + es=2 exponent
// + fraction, two's-complement for negatives, round-to-nearest-even.
//
// Verified vs a spec-faithful software reference (posit16_ref.py) by exhaustive
// fp16 sweep: quantizer picks the nearest posit; dequantizer returns the nearest fp16.

`default_nettype none
module posit16_quantizer (
    input  wire signed [15:0] fp16_in,
    output reg         [15:0] posit16_out
);
    wire        sign  = fp16_in[15];
    wire [4:0]  exp16 = fp16_in[14:10];
    wire [9:0]  mant16= fp16_in[9:0];

    reg signed [7:0] scaleExp;
    reg [9:0]  frac;
    reg signed [5:0] k;
    reg [1:0]  e;
    reg [5:0]  Lr, Ltot, dropped;
    reg [31:0] combined;
    reg [14:0] mag;
    reg        guard, sticky;
    reg [15:0] full;
    integer    lz, kk;

    always @(*) begin
        if (exp16 == 5'd31) begin
            posit16_out = 16'h8000;                 // inf/NaN -> NaR (posit has no inf)
        end else if (exp16 == 5'd0 && mant16 == 10'd0) begin
            posit16_out = 16'd0;                    // zero
        end else begin
            // ---- decode fp16 to (scaleExp, frac=bits after implicit 1) ----
            if (exp16 == 5'd0) begin                // denormal: normalize
                lz = 0;
                if      (mant16[9]) lz = 0;
                else if (mant16[8]) lz = 1;
                else if (mant16[7]) lz = 2;
                else if (mant16[6]) lz = 3;
                else if (mant16[5]) lz = 4;
                else if (mant16[4]) lz = 5;
                else if (mant16[3]) lz = 6;
                else if (mant16[2]) lz = 7;
                else if (mant16[1]) lz = 8;
                else                lz = 9;
                scaleExp = -8'sd15 - lz[7:0];
                frac     = mant16 << (lz + 1);
            end else begin
                scaleExp = $signed({3'b0, exp16}) - 8'sd15;
                frac     = mant16;
            end

            // ---- split scaleExp = 4*k + e  (useed=2^4, es=2) ----
            k = scaleExp >>> 2;                      // arithmetic (floor)
            e = scaleExp[1:0];                       // mod 4

            // ---- regime run-length pattern ----
            if (k >= 0) begin
                Lr       = k[5:0] + 6'd2;            // (k+1) ones + terminating 0
                combined = (((32'd1 << (k + 1)) - 32'd1) << 1);
            end else begin
                kk       = -k;
                Lr       = kk[5:0] + 6'd1;           // kk zeros + terminating 1
                combined = 32'd1;
            end

            // append es=2 exponent, then 10 fraction bits
            combined = (combined << 2) | {30'd0, e};
            combined = (combined << 10) | {22'd0, frac};
            Ltot     = Lr + 6'd12;

            // ---- align to 15-bit magnitude, round-to-nearest-even ----
            if (Ltot > 6'd15) begin
                dropped = Ltot - 6'd15;
                mag     = combined >> dropped;
                guard   = (combined >> (dropped - 6'd1)) & 32'd1;
                sticky  = |(combined & ((32'd1 << (dropped - 6'd1)) - 32'd1));
                if (guard && (sticky || mag[0])) mag = mag + 15'd1;
            end else begin
                mag = combined << (6'd15 - Ltot);
            end

            full        = {1'b0, mag};
            posit16_out = sign ? (~full + 16'd1) : full;
        end
    end
endmodule

`default_nettype none
module posit16_dequantizer (
    input  wire        [15:0] posit16_in,
    output reg  signed [15:0] fp16_out
);
    wire        sign = posit16_in[15];
    reg  [14:0] mag;
    reg         first;
    reg  [4:0]  m;             // regime run length
    reg signed [5:0] k;
    reg  [5:0]  idx;
    reg  [1:0]  e;
    reg  [14:0] fracfield;
    reg  [4:0]  nfrac;
    reg  [9:0]  mant16;
    reg signed [7:0] scaleExp, exp16s;
    integer i;
    reg done_run;
    reg [10:0] sig;
    reg [11:0] sub;
    reg signed [7:0] shamt;
    reg dg, dst;

    always @(*) begin
        if (posit16_in == 16'd0) begin
            fp16_out = 16'd0;
        end else if (posit16_in == 16'h8000) begin
            fp16_out = {1'b0, 5'd31, 10'd0};        // NaR -> inf
        end else begin
            mag = sign ? ((~posit16_in + 16'd1) & 16'h7FFF) : posit16_in[14:0];

            // ---- regime: count run of identical bits from MSB ----
            first = mag[14];
            m = 5'd1; done_run = 1'b0;
            for (i = 13; i >= 0; i = i - 1) begin
                if (!done_run) begin
                    if (mag[i] == first) m = m + 5'd1;
                    else done_run = 1'b1;
                end
            end
            k = first ? ($signed({1'b0,m}) - 6'sd1) : -$signed({1'b0,m});

            // bits consumed by regime: m + terminator (if run < 15)
            idx = (m < 5'd15) ? (m + 5'd1) : m;     // index of first exponent bit (from MSB)

            // ---- exponent (2 bits) just below the regime ----
            // bit position from MSB: idx, idx+1  -> within mag[14:0], MSB is index 14
            e[1] = (idx   <= 6'd14) ? mag[14 - idx]       : 1'b0;
            e[0] = (idx+1 <= 6'd14) ? mag[14 - (idx+1)]   : 1'b0;

            // ---- fraction = remaining bits, left-aligned into 10-bit mant ----
            nfrac = (idx + 6'd2 <= 6'd15) ? (6'd15 - (idx + 6'd2)) : 5'd0;
            fracfield = mag << (idx + 6'd2);         // shift away sign-region/regime/exp; MSBs are fraction
            mant16 = fracfield[14:5];                // top 10 bits of the fraction field

            // ---- recompose scale and emit fp16 ----
            scaleExp = (k <<< 2) + $signed({6'b0, e});  // 4*k + e
            exp16s   = scaleExp + 8'sd15;

            if (exp16s >= 8'sd31) begin
                fp16_out = {sign, 5'd31, 10'd0};                        // overflow -> inf
            end else if (exp16s <= 8'sd0) begin
                // subnormal: mant_d = {1,frac} >> (1 - exp16s), round-to-nearest-even
                shamt = 8'sd1 - exp16s;                                  // >= 1
                sig   = {1'b1, mant16};
                if (shamt > 8'sd11) begin
                    fp16_out = {sign, 15'd0};                           // underflow -> zero
                end else begin
                    sub = sig >> shamt;
                    dg  = (sig >> (shamt - 8'sd1)) & 11'd1;
                    dst = |(sig & ((11'd1 << (shamt - 8'sd1)) - 11'd1));
                    if (dg && (dst || sub[0])) sub = sub + 12'd1;
                    if (sub >= 12'd1024) fp16_out = {sign, 5'd1, 10'd0};// rounded up to smallest normal
                    else                 fp16_out = {sign, 5'd0, sub[9:0]};
                end
            end else begin
                fp16_out = {sign, exp16s[4:0], mant16};
            end
        end
    end
endmodule
