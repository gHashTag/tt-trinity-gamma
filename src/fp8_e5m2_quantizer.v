// Corrected fp8_e5m2_quantizer. Bug: guard bit was mant16[8] (a KEPT bit of
// mant8=mant16[9:8]) instead of the first dropped bit mant16[7]; and mant_rounded
// was 2-bit so 3+1 wrapped to 0 while the overflow check looked for ==3. Fixed:
// guard=mant16[7], 3-bit mant_rounded, carry -> exp+1.
`default_nettype none
module fp8_e5m2_quantizer (
    input  wire signed [15:0] fp16_in,
    output reg  [7:0]    fp8_out
);
    wire        sign  = fp16_in[15];
    wire [4:0]  exp16 = fp16_in[14:10];
    wire [9:0]  mant16= fp16_in[9:0];
    wire [4:0]  exp8  = exp16;          // same bias (15)
    wire [1:0]  mant8 = mant16[9:8];

    reg  [4:0]  exp_clamped;
    reg  [2:0]  mant_rounded;           // FIX: 3-bit to hold rounding carry
    reg         guard, roundsticky;

    always @(*) begin
        if (exp16 == 5'd31)
            fp8_out = (mant16==10'd0) ? {sign,5'd31,2'd0} : {sign,5'd31,2'd1};
        else if (exp16 == 5'd0)
            fp8_out = {sign, 8'd0};
        else begin
            exp_clamped = (exp8 > 5'd30) ? 5'd30 : exp8;
            guard       = mant16[7];                 // FIX: first dropped bit
            roundsticky = |mant16[6:0];
            if (guard && (roundsticky || mant8[0])) // round-half-to-even
                mant_rounded = {1'b0, mant8} + 3'd1;
            else
                mant_rounded = {1'b0, mant8};
            if (mant_rounded[2]) begin              // carry out of the 2-bit field
                if (exp_clamped >= 5'd30)
                    mant_rounded = 3'd3;            // saturate to max finite (no exp31=inf overflow)
                else begin
                    exp_clamped  = exp_clamped + 5'd1;
                    mant_rounded = 3'd0;
                end
            end
            fp8_out = {sign, exp_clamped[4:0], mant_rounded[1:0]};
        end
    end
endmodule
