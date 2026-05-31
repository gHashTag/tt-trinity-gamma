// Corrected gf8_add (GF8 = 1/3/4, bias 3). Fix: normalization ladder was shifted
// (treated sum_m[5]=2^(M+1) carry as exp-1 and sum_m[4]=2^M no-change as exp-2),
// mirroring the gf8_mul generator MSB-position bug. Rebuilt on the verified
// gf16_add ladder scaled to M=4: same-sign sum is in [2^M,2^(M+2)); leading bit at
// M+1 -> [2,4) exp+1, at M -> [1,2) no change, below -> cancellation shift-up.
`default_nettype none
module gf8_add (
    input  wire [7:0] a,
    input  wire [7:0] b,
    output reg  [7:0] result
);
    localparam BIAS = 3'd3;
    localparam EXP_MAX = 3'd7;
    wire       sign_a=a[7]; wire [2:0] exp_a=a[6:4]; wire [3:0] mant_a=a[3:0];
    wire       sign_b=b[7]; wire [2:0] exp_b=b[6:4]; wire [3:0] mant_b=b[3:0];
    wire is_zero_a=(exp_a==0)&&(mant_a==0); wire is_zero_b=(exp_b==0)&&(mant_b==0);
    wire is_special_a=(exp_a==EXP_MAX); wire is_special_b=(exp_b==EXP_MAX);
    wire is_inf_a=is_special_a&&(mant_a==0); wire is_inf_b=is_special_b&&(mant_b==0);
    wire is_nan_a=is_special_a&&(mant_a!=0); wire is_nan_b=is_special_b&&(mant_b!=0);
    wire a_larger=(exp_a>exp_b)||((exp_a==exp_b)&&(mant_a>=mant_b));

    reg [3:0] big_exp, shift, result_exp;
    reg [5:0] big_fm, small_fm;
    reg [6:0] sum_m;
    reg       big_sign, small_sign, result_sign;
    reg [4:0] norm, rounded;
    reg       g_bit, r_bit, s_bit, cancel;
    reg [3:0] final_exp, final_mant;
    reg [7:0] fr;

    always @(*) begin
        cancel=0;result_exp=0;norm=0;g_bit=0;r_bit=0;s_bit=0;rounded=0;
        final_exp=0;final_mant=0;fr=0;result_sign=0;big_exp=0;big_fm=0;
        big_sign=0;small_fm=0;small_sign=0;shift=0;sum_m=0;
        if (is_nan_a||is_nan_b) result=8'hF1;
        else if (is_inf_a&&is_inf_b&&(sign_a!=sign_b)) result=8'hF1;
        else if (is_inf_a) result=sign_a?8'hF0:8'h70;
        else if (is_inf_b) result=sign_b?8'hF0:8'h70;
        else if (is_zero_a&&is_zero_b) result=8'h00;
        else if (is_zero_a) result=b;
        else if (is_zero_b) result=a;
        else begin
            if (a_larger) begin big_exp={1'b0,exp_a};big_fm={1'b1,mant_a};big_sign=sign_a;small_fm={1'b1,mant_b};small_sign=sign_b; end
            else          begin big_exp={1'b0,exp_b};big_fm={1'b1,mant_b};big_sign=sign_b;small_fm={1'b1,mant_a};small_sign=sign_a; end
            shift = big_exp - {1'b0,(a_larger?exp_b:exp_a)};
            result_exp = big_exp;
            case (shift)
                4'd0: small_fm=small_fm;
                4'd1: small_fm={1'b0,small_fm[4:1]};
                4'd2: small_fm={2'b00,small_fm[4:2]};
                4'd3: small_fm={3'b000,small_fm[4:3]};
                4'd4: small_fm={4'b0000,small_fm[4]};
                default: small_fm=6'd0;
            endcase
            if (big_sign==small_sign) begin sum_m={1'b0,big_fm}+{1'b0,small_fm}; result_sign=big_sign; end
            else begin sum_m={1'b0,big_fm}-{1'b0,small_fm}; result_sign=big_sign; if(sum_m==7'd0) cancel=1; end
            if (!cancel) begin
                if (sum_m[6] || sum_m[5]) begin            // [2,4): exp+1 (leading bit M+1)
                    result_exp = result_exp + 4'd1;
                    norm  = sum_m[5:1];
                    g_bit = sum_m[0];
                end else if (sum_m[4]) begin               // [1,2): no exponent change
                    norm = sum_m[4:0];
                end else if (sum_m[3]) begin
                    norm = {sum_m[3:0],1'b0}; result_exp = result_exp - 4'd1;
                end else if (sum_m[2]) begin
                    norm = {sum_m[2:0],2'b00}; result_exp = result_exp - 4'd2;
                end else if (sum_m[1]) begin
                    norm = {sum_m[1:0],3'b000}; result_exp = result_exp - 4'd3;
                end else begin
                    norm = {sum_m[0],4'b0000}; result_exp = result_exp - 4'd4;
                end
                if (g_bit && (r_bit||s_bit)) rounded = norm + 5'd1; else rounded = norm;
                if (rounded < norm) begin final_exp = result_exp + 4'd1; final_mant = 4'd0; end
                else begin final_exp = result_exp; final_mant = rounded[3:0]; end
                if (final_exp[3]) fr = result_sign?8'h80:8'h00;
                else if (final_exp[2:0] >= EXP_MAX) fr = result_sign?8'hF0:8'h70;
                else fr = {result_sign, final_exp[2:0], final_mant};
                result = fr;
            end else result = 8'h00;
        end
    end
endmodule
