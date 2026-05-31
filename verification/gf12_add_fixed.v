// Corrected gf12_add (GF12 = 1/4/7, bias 7). Normalization ladder rebuilt for M=7
// (fm 8-bit leading@7, sum_m 9-bit; carry at bit8 -> exp+1, bit7 -> no change,
// below -> cancellation). Signed exponent accumulator for correct under/overflow.
`default_nettype none
module gf12_add (
    input  wire [11:0] a,
    input  wire [11:0] b,
    output reg  [11:0] result
);
    localparam BIAS = 4'd7;
    localparam EXP_MAX = 4'd15;
    wire       sign_a=a[11]; wire [3:0] exp_a=a[10:7]; wire [6:0] mant_a=a[6:0];
    wire       sign_b=b[11]; wire [3:0] exp_b=b[10:7]; wire [6:0] mant_b=b[6:0];
    wire is_zero_a=(exp_a==0)&&(mant_a==0); wire is_zero_b=(exp_b==0)&&(mant_b==0);
    wire is_special_a=(exp_a==EXP_MAX); wire is_special_b=(exp_b==EXP_MAX);
    wire is_inf_a=is_special_a&&(mant_a==0); wire is_inf_b=is_special_b&&(mant_b==0);
    wire is_nan_a=is_special_a&&(mant_a!=0); wire is_nan_b=is_special_b&&(mant_b!=0);
    wire a_larger=(exp_a>exp_b)||((exp_a==exp_b)&&(mant_a>=mant_b));

    reg [3:0]        shift;
    reg signed [6:0] big_exp, result_exp, final_exp;
    reg [7:0] big_fm, small_fm;
    reg [8:0] sum_m;
    reg       big_sign, small_sign, result_sign, g_bit, r_bit, s_bit, cancel;
    reg [7:0] norm, rounded;
    reg [6:0] final_mant;
    reg [11:0] fr;

    always @(*) begin
        cancel=0;result_exp=0;norm=0;g_bit=0;r_bit=0;s_bit=0;rounded=0;
        final_exp=0;final_mant=0;fr=0;result_sign=0;big_exp=0;big_fm=0;
        big_sign=0;small_fm=0;small_sign=0;shift=0;sum_m=0;
        if (is_nan_a||is_nan_b) result=12'hF01;
        else if (is_inf_a&&is_inf_b&&(sign_a!=sign_b)) result=12'hF01;
        else if (is_inf_a) result=sign_a?12'hF00:12'h700;
        else if (is_inf_b) result=sign_b?12'hF00:12'h700;
        else if (is_zero_a&&is_zero_b) result=12'h000;
        else if (is_zero_a) result=b;
        else if (is_zero_b) result=a;
        else begin
            if (a_larger) begin big_exp=$signed({3'b0,exp_a});big_fm={1'b1,mant_a};big_sign=sign_a;small_fm={1'b1,mant_b};small_sign=sign_b; end
            else          begin big_exp=$signed({3'b0,exp_b});big_fm={1'b1,mant_b};big_sign=sign_b;small_fm={1'b1,mant_a};small_sign=sign_a; end
            shift = (a_larger?exp_a:exp_b) - (a_larger?exp_b:exp_a);
            result_exp = big_exp;
            case (shift)
                4'd0: small_fm=small_fm;
                4'd1: small_fm={1'b0,small_fm[7:1]};
                4'd2: small_fm={2'b0,small_fm[7:2]};
                4'd3: small_fm={3'b0,small_fm[7:3]};
                4'd4: small_fm={4'b0,small_fm[7:4]};
                4'd5: small_fm={5'b0,small_fm[7:5]};
                4'd6: small_fm={6'b0,small_fm[7:6]};
                4'd7: small_fm={7'b0,small_fm[7]};
                default: small_fm=8'd0;
            endcase
            if (big_sign==small_sign) begin sum_m={1'b0,big_fm}+{1'b0,small_fm}; result_sign=big_sign; end
            else begin sum_m={1'b0,big_fm}-{1'b0,small_fm}; result_sign=big_sign; if(sum_m==9'd0) cancel=1; end
            if (!cancel) begin
                if (sum_m[8]) begin                         // [2,4): exp+1
                    result_exp = result_exp + 7'sd1; norm = sum_m[8:1]; g_bit = sum_m[0];
                end else if (sum_m[7]) norm = sum_m[7:0];   // [1,2): no change
                else if (sum_m[6]) begin norm={sum_m[6:0],1'b0}; result_exp=result_exp-7'sd1; end
                else if (sum_m[5]) begin norm={sum_m[5:0],2'b00}; result_exp=result_exp-7'sd2; end
                else if (sum_m[4]) begin norm={sum_m[4:0],3'b000}; result_exp=result_exp-7'sd3; end
                else if (sum_m[3]) begin norm={sum_m[3:0],4'b0000}; result_exp=result_exp-7'sd4; end
                else if (sum_m[2]) begin norm={sum_m[2:0],5'b0}; result_exp=result_exp-7'sd5; end
                else if (sum_m[1]) begin norm={sum_m[1:0],6'b0}; result_exp=result_exp-7'sd6; end
                else begin norm={sum_m[0],7'b0}; result_exp=result_exp-7'sd7; end
                if (g_bit && (r_bit||s_bit)) rounded = norm + 8'd1; else rounded = norm;
                if (rounded < norm) begin final_exp = result_exp + 7'sd1; final_mant = 7'd0; end
                else begin final_exp = result_exp; final_mant = rounded[6:0]; end
                if (final_exp <= 0) fr = result_sign?12'h800:12'h000;
                else if (final_exp >= $signed({3'b0,EXP_MAX})) fr = result_sign?12'hF00:12'h700;
                else fr = {result_sign, final_exp[3:0], final_mant};
                result = fr;
            end else result = 12'h000;
        end
    end
endmodule
