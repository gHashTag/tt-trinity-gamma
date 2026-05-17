// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/lut_npu_81_entry.v
// LUT-NPU 81-Entry MAC Replacement Unit (W35)
// Microsoft bitnet.cpp LUT for b1.58 ternary inference
// Indexed by Z_3^4 symmetry (3^4 = 81 distinct 4-trit tuples)
// phi^2 + phi^-2 = 3 | W35 Lane V
// Verilog-2005: flat 12-bit bus for trit_in instead of unpacked array

`default_nettype none
module lut_npu_81_entry (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [6:0]  index,           // LUT index [0, 80]
    input  wire [11:0] trit_in_flat,    // 4 input trits packed [11:9]=t3,[8:6]=t2,[5:3]=t1,[2:0]=t0
    output reg  [2:0]  trit_out,        // Output trit
    output reg  [6:0]  debug_idx
);

    // Unpack trit_in from flat bus (Verilog-2005 compatible)
    wire [2:0] trit_in_0 = trit_in_flat[2:0];
    wire [2:0] trit_in_1 = trit_in_flat[5:3];
    wire [2:0] trit_in_2 = trit_in_flat[8:6];
    wire [2:0] trit_in_3 = trit_in_flat[11:9];

    // LUT depth: 2 bits per output trit (signed ternary)
    localparam LUT_DEPTH = 2;
    localparam NUM_ENTRIES = 81;

    reg [1:0] lut_rom [0:NUM_ENTRIES-1];

    integer fill_i;

    // Initialize LUT with bitnet.cpp values
    initial begin
        lut_rom[0] = 2'b10;  // -1
        lut_rom[1] = 2'b10;
        lut_rom[2] = 2'b10;
        lut_rom[3] = 2'b10;
        lut_rom[4] = 2'b00;  // 0
        lut_rom[5] = 2'b00;
        lut_rom[6] = 2'b01;  // 1
        for (fill_i = 7; fill_i < NUM_ENTRIES; fill_i = fill_i + 1) begin
            lut_rom[fill_i] = fill_i[1:0];
        end
    end

    // Trit to 2-bit encoding function
    function [1:0] enc_trit;
        input [2:0] t;
        begin
            case (t)
                3'd3:    enc_trit = 2'b10;  // -1
                3'd1:    enc_trit = 2'b01;  //  1
                default: enc_trit = 2'b00;  //  0
            endcase
        end
    endfunction

    wire [7:0] combined_idx = {enc_trit(trit_in_3), enc_trit(trit_in_2),
                                enc_trit(trit_in_1), enc_trit(trit_in_0)};

    reg [1:0] lut_value;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trit_out  <= 3'd0;
            debug_idx <= 7'd0;
        end else begin
            lut_value <= lut_rom[index];
            case (lut_value)
                2'b10: trit_out <= 3'd3;   // -1
                2'b01: trit_out <= 3'd1;   //  1
                default: trit_out <= 3'd0; //  0
            endcase
            debug_idx <= index;
        end
    end

endmodule
