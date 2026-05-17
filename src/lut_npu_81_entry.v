// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/lut_npu_81_entry.v
// LUT-NPU 81-Entry MAC Replacement Unit (W35)
// Microsoft bitnet.cpp LUT for b1.58 ternary inference
// Indexed by Z_3^4 symmetry (3^4 = 81 distinct 4-trit tuples)
// phi^2 + phi^-2 = 3 | W35 Lane V

`default_nettype none
module lut_npu_81_entry (
    input  wire clk,
    input  wire rst_n,
    input  wire [6:0]  index,           // LUT index [0, 80]
    input  wire [2:0]  trit_in [3:0],   // 4 input trits
    output reg  [2:0]  trit_out,        // Output trit
    output reg  [6:0]  debug_idx
);

    // LUT depth: 2 bits per output trit (signed ternary)
    // Total ROM: 81 entries × 2 bits = 162 bits
    localparam LUT_DEPTH = 2;
    localparam NUM_ENTRIES = 81;

    // ROM for LUT values (simplified - actual values from bitnet.cpp)
    // Indexed by ternary tuple: each trit ∈ {-1, 0, 1}
    // Output trit ∈ {-1, 0, 1}
    reg [1:0] lut_rom [0:NUM_ENTRIES-1];

    // Initialize LUT with bitnet.cpp values
    initial begin
        // 00 (all -1)
        lut_rom[0] = 2'b10;  // -1
        lut_rom[1] = 2'b10;
        lut_rom[2] = 2'b10;
        lut_rom[3] = 2'b10;
        
        // 01, 02, 03, ... (partial)
        lut_rom[4] = 2'b00;  // 0
        lut_rom[5] = 2'b00;
        lut_rom[6] = 2'b01;  // 1
        
        // ... (actual 81 entries from bitnet.cpp)
        
        // Fill remaining with identity mapping
        begin : fill_loop
            integer i;
            for (i = 7; i < NUM_ENTRIES; i = i + 1) begin
                lut_rom[i] = i[1:0];  // Placeholder
            end
        end
    end

    // Convert 4 trits to LUT index
    wire [7:0] combined_idx = {trit_in[3], trit_in[2], trit_in[1], trit_in[0]};

    // Trit to 2-bit encoding
    wire [1:0] trit_enc [3:0];

    always @(*) begin
        // Trit encoding: -1→10, 0→00, 1→01
        case (trit_in[0])
            3'd3: trit_enc[0] = 2'b10;  // -1
            3'd0: trit_enc[0] = 2'b00;  // 0
            3'd1: trit_enc[0] = 2'b01;  // 1
            default: trit_enc[0] = 2'b00;
        endcase
        
        case (trit_in[1])
            3'd3: trit_enc[1] = 2'b10;
            3'd0: trit_enc[1] = 2'b00;
            3'd1: trit_enc[1] = 2'b01;
            default: trit_enc[1] = 2'b00;
        endcase
        
        case (trit_in[2])
            3'd3: trit_enc[2] = 2'b10;
            3'd0: trit_enc[2] = 2'b00;
            3'd1: trit_enc[2] = 2'b01;
            default: trit_enc[2] = 2'b00;
        endcase
        
        case (trit_in[3])
            3'd3: trit_enc[3] = 2'b10;
            3'd0: trit_enc[3] = 2'b00;
            3'd1: trit_enc[3] = 2'b01;
            default: trit_enc[3] = 2'b00;
        endcase
    end

    reg [1:0] lut_value;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            trit_out <= 3'd0;
            debug_idx <= 7'd0;
        end else begin
            // LUT lookup
            lut_value <= lut_rom[index];
            
            // Convert back to trit
            case (lut_value)
                2'b10: trit_out <= 3'd3;  // -1
                2'b00: trit_out <= 3'd0;  // 0
                2'b01: trit_out <= 3'd1;  // 1
                default: trit_out <= 3'd0;
            endcase
            
            debug_idx <= index;
        end
    end

endmodule
