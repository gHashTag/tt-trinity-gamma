// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/posit16_quantizer.v
// Posit16 Quantization Unit (posit type 16, unum 1.0)
// Format: [S(1) | RS(1) | EXP/K(MANT) | useed=2]
// Used in arithmetic-agnostic neural network inference

`default_nettype none
module posit16_quantizer (
    input  wire signed [15:0] fp16_in,   // FP16 input
    output reg  [15:0]   posit16_out    // Posit16 output
);

    wire        sign = fp16_in[15];
    wire [4:0]  exp16 = fp16_in[14:10];
    wire [9:0]  mant16 = fp16_in[9:0];
    wire [14:0] magnitude = fp16_in[14:0];

    reg  [14:0]  abs_value;
    reg  [2:0]   regime;
    reg  [4:0]   exponent;
    reg  [9:0]   fraction;
    reg  [14:0]  posit_mant;
    reg  [2:0]   regime_bits;
    reg  [2:0]   rs;
    reg  [4:0]   exp_bits;
    reg  [5:0]   frac_bits;
    reg  [4:0]   remaining_exp;

    always @(*) begin
        if (exp16 == 5'd31) begin
            // Infinity or NaN in FP16
            if (mant16 == 10'd0)
                posit16_out = {sign, 15'h7FFF};  // Infinity (all 1s)
            else
                posit16_out = {sign, 15'h7FFE};  // NaR (Not a Real)
        end else if (exp16 == 5'd0 && mant16 == 10'd0) begin
            // Zero
            posit16_out = {sign, 15'd0};
        end else begin
            // Decode FP16 to components
            if (exp16 == 5'd0) begin
                // Denormal FP16
                exponent = 5'd0;
                fraction = {1'b0, mant16};  // Extra leading zero
            end else begin
                // Normal FP16
                exponent = exp16 - 5'd15;
                fraction = {1'b1, mant16};  // Implicit leading 1
            end

            // Find regime (number of leading 0s or 1s)
            if (exponent[4]) begin  // Negative exponent
                if (exponent[3]) regime = 3'd4;
                else if (exponent[2]) regime = 3'd3;
                else if (exponent[1]) regime = 3'd2;
                else if (exponent[0]) regime = 3'd1;
                else regime = 3'd0;
            end else begin  // Non-negative exponent
                if (exponent[3]) regime = 3'd4;
                else if (exponent[2]) regime = 3'd3;
                else if (exponent[1]) regime = 3'd2;
                else if (exponent[0]) regime = 3'd1;
                else regime = 3'd0;
            end

            // Clamp regime to available bits (max 7 bits including sign of regime)
            if (regime > 3'd3) regime = 3'd3;

            // Build posit: [sign | regime-sign | (regime-1) | remaining-exp | fraction]
            // RS bit = sign of regime (0 for positive, 1 for negative)
            rs = exponent[4] ? 3'd1 : 3'd0;

            // Build mantissa
            if (exponent[4]) begin  // Negative exponent
                // Regime bits: N 1s where N = min(regime, 3)
                if (regime >= 3'd3) regime_bits = 3'd7;
                else if (regime == 3'd2) regime_bits = 3'd3;
                else if (regime == 3'd1) regime_bits = 3'd1;
                else regime_bits = 3'd0;
            end else begin  // Non-negative exponent
                // Regime bits: N 0s where N = min(regime, 3)
                if (regime >= 3'd3) regime_bits = 3'd0;
                else if (regime == 3'd2) regime_bits = 3'd0;
                else if (regime == 3'd1) regime_bits = 3'd0;
                else regime_bits = 3'd0;
            end

            // Extract remaining exponent bits
            // Available bits after sign (1) + RS (1) + regime-1 (N-1)
            // Total remaining for exp+frac = 15 - (1+1+N-1) = 14-N
            if (regime == 3'd0) remaining_exp = exponent[3:0];
            else if (regime == 3'd1) remaining_exp = exponent[2:0];
            else if (regime == 3'd2) remaining_exp = exponent[1:0];
            else remaining_exp = {1'b0, exponent[0]};

            // Available fraction bits
            if (regime == 3'd0) frac_bits = fraction[9:4];
            else if (regime == 3'd1) frac_bits = fraction[9:5];
            else if (regime == 3'd2) frac_bits = fraction[9:6];
            else if (regime == 3'd3) frac_bits = fraction[9:7];
            else frac_bits = fraction[9:8];

            // Assemble posit mantissa (15 bits after sign)
            posit_mant = {regime_bits, remaining_exp, frac_bits};

            posit16_out = {sign, posit_mant};
        end
    end

endmodule

// Posit16 Dequantization Unit (simplified)
module posit16_dequantizer (
    input  wire [15:0]   posit16_in,   // Posit16 input
    output reg  signed [15:0] fp16_out    // FP16 output
);

    wire        sign = posit16_in[15];
    wire [14:0] posit_mant = posit16_in[14:0];

    reg  [4:0]  exp16;
    reg  [9:0]  mant16;
    reg  [2:0]  regime_count;
    reg         regime_sign;
    reg  [4:0]  exp_bits;
    reg  [9:0]  frac_bits;
    reg  [5:0]  bit_offset;

    always @(*) begin
        if (posit_mant == 15'd0) begin
            // Zero
            fp16_out = {sign, 15'd0};
        end else if (posit_mant == 15'h7FFF) begin
            // Infinity/NaR
            fp16_out = {sign, 5'd31, 10'd0};
        end else begin
            // Decode regime (find first run of identical bits)

            // Find regime sign (first bit after pos-14)
            regime_sign = posit_mant[14];

            // Count regime bits (simplified)
            if (posit_mant[14:13] == 2'b00 || posit_mant[14:13] == 2'b11) begin
                if (posit_mant[14:12] == 3'b000 || posit_mant[14:12] == 3'b111) begin
                    regime_count = 3'd2;
                end else begin
                    regime_count = 3'd1;
                end
            end else begin
                regime_count = 3'd0;
            end

            // Extract exponent and fraction
            // bit_offset = regime_count + 2; regime_count in {0,1,2}
            // Use case to avoid variable part-select (not legal in Verilog-2005)
            case (regime_count)
                3'd0: begin  // bit_offset=2: exp=[14:2] (13 bits), frac=[10:2] (9 bits)
                    exp_bits  = {1'b0, posit_mant[14:11]};  // top 4 exp bits
                    frac_bits = {1'b0, posit_mant[9:1]};    // top 9 frac bits
                end
                3'd1: begin  // bit_offset=3: exp=[14:3] (12 bits), frac=[9:3] (7 bits)
                    exp_bits  = {1'b0, posit_mant[14:11]};  // top 4 exp bits
                    frac_bits = {3'd0, posit_mant[9:3]};    // top 7 frac bits
                end
                3'd2: begin  // bit_offset=4: exp=[14:4] (11 bits), frac=[8:4] (5 bits)
                    exp_bits  = {1'b0, posit_mant[14:11]};  // top 4 exp bits
                    frac_bits = {5'd0, posit_mant[9:5]};    // top 5 frac bits
                end
                default: begin
                    exp_bits  = 5'd0;
                    frac_bits = 10'd0;
                end
            endcase
            bit_offset = {3'd0, regime_count} + 5'd2; // kept for reference only

            // Convert to FP16
            if (regime_sign) begin
                // Negative regime: exp = -2^regime_count * useed + exp_bits
                exp16 = 5'd15 - ({1'b0, regime_count} << 2'd2) + {1'b0, exp_bits[3:0]};
            end else begin
                // Positive regime: exp = (regime_count) * useed + exp_bits
                exp16 = 5'd15 + ({1'b0, regime_count} << 2'd2) + {1'b0, exp_bits[3:0]};
            end

            // Clamp exponent
            if (exp16 > 5'd30) exp16 = 5'd30;
            if (exp16 < 5'd1) exp16 = 5'd1;

            mant16 = {1'b0, frac_bits[8:0]};

            fp16_out = {sign, exp16, mant16};
        end
    end

endmodule