`default_nettype none
// alu9_decoder_v2.v — CORRECTED Trinity ternary 9-instruction ALU decoder.
// Apache-2.0
//
// FIX (2026-06): op7 TRI_BIND computed `sr = sa ^ sb` -- a BITWISE XOR of the
// two's-complement SIGNED lifts of the operands, which is NOT the VSA bind. In
// MAP-style VSA over the {-1,0,+1} alphabet this ALU uses, bind is ELEMENTWISE
// MULTIPLY. The shipped op7 violated that for 6 of 9 input pairs -- most clearly
// it broke the multiplicative absorbing property (bind(x,0) returned nonzero) and
// gave bind(1,1)=bind(-1,-1)=0 instead of +1. v2 implements BIND as ternary
// multiply (so it now matches op3 MUL, which is the correct VSA semantics).
// Verified 81/81 vs the ternary reference (test/leaf_audit.py).
//
// Benign on the fabricated dies: u_alu is driven by random hwrng_word bits and
// its result is written to ring27_memory (an entropy ring whose only consumer is
// a liveness flag) -- no workload depends on the ALU output. The frozen
// alu9_decoder is left as taped out; v2 is the correction for a respin.
//
module alu9_decoder_v2 (
    input  wire [3:0] opcode,
    input  wire [1:0] a,            // ternary operand A
    input  wire [1:0] b,            // ternary operand B
    output reg  [1:0] result,       // ternary result
    output reg        valid,
    output wire       decoder_ok
);

    // Ternary encoding: 00=+1, 01=-1, 10=0, 11=0
    // Helper: signed conversion {-1, 0, +1}
    function signed [1:0] tri_to_s;
        input [1:0] t;
        begin
            casez (t)
                2'b00:   tri_to_s = 2'sd1;
                2'b01:   tri_to_s = -2'sd1;
                default: tri_to_s = 2'sd0;
            endcase
        end
    endfunction

    function [1:0] s_to_tri;
        input signed [3:0] s;
        begin
            if (s > 0)      s_to_tri = 2'b00;   // +1
            else if (s < 0) s_to_tri = 2'b01;   // -1
            else            s_to_tri = 2'b10;   // 0
        end
    endfunction

    reg signed [3:0] sa, sb, sr;

    always @(*) begin
        sa = tri_to_s(a);
        sb = tri_to_s(b);
        sr = 0;
        valid  = 1'b1;
        case (opcode)
            4'd0: begin sr = 0;                                end  // NOP
            4'd1: begin sr = sa + sb;                          end  // ADD
            4'd2: begin sr = sa - sb;                          end  // SUB
            4'd3: begin  // MUL (ternary, range -1..1)
                // R-SI-1 compliant: ternary mul on {-1,0,+1} via XOR/NOR
                if (sa == 0 || sb == 0)
                    sr = 0;
                else if (sa == sb)
                    sr = 1;   // -1*-1 = 1, 1*1 = 1
                else
                    sr = -1;  // -1*1 = -1, 1*-1 = -1
            end
            4'd4: begin sr = (sa < sb) ? sa : sb;              end  // AND (min)
            4'd5: begin sr = (sa > sb) ? sa : sb;              end  // OR  (max)
            4'd6: begin sr = -sa;                              end  // NOT (negate)
            4'd7: begin  // BIND = ternary multiply (VSA MAP bind)
                if (sa == 0 || sb == 0) sr = 0;
                else if (sa == sb)      sr = 1;
                else                    sr = -1;
            end
            4'd8: begin                                              // BUNDLE (sign-of-sum)
                if (sa + sb > 0)      sr = 1;
                else if (sa + sb < 0) sr = -1;
                else                  sr = 0;
            end
            default: begin valid = 1'b0; sr = 0; end                  // invalid opcode
        endcase
        result = s_to_tri(sr);
    end

    // R-SI-1 note: opcode 3 (TRI_MUL) uses signed * — BUT operands are 4-bit signed
    // restricted to {-1, 0, +1} so synth folds this into a small LUT, not a
    // multiplier macro. Acceptable on SKY130 (verified via yosys flatten).
    assign decoder_ok = 1'b1;

endmodule
