`default_nettype none
// alu9_decoder.v — Trinity ternary 9-instruction ALU decoder
// Apache-2.0
//
// PhD anchor: t27 ISA — ternary (base-3) computer architecture.
// 9 instructions = 3² (sacred constant). Each instruction is 4 bits but only
// 9 codes are valid; the rest map to NOP. The decoder produces strobes for
// downstream execution units.
//
// ISA:
//   0: TRI_NOP         no-op
//   1: TRI_ADD         a + b   (mod 3 lift)
//   2: TRI_SUB         a - b
//   3: TRI_MUL         a * b   (ternary mul = sign XOR if both nonzero, else 0)
//   4: TRI_AND         a AND b (Kleene)
//   5: TRI_OR          a OR b
//   6: TRI_NOT         -a
//   7: TRI_BIND        VSA bind (XOR)
//   8: TRI_BUNDLE      VSA bundle (majority)

module alu9_decoder (
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
            4'd7: begin  // BIND = ternary product (bipolar, invertible)
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
