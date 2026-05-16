`default_nettype none
// =============================================================================
// crown47_rom_8bit.v — TT pin-budget wrapper for Crown47 ROM
// =============================================================================
// Adapts the 24-bit Crown47 ROM (`crown47_rom`) to TinyTapeout's 8-bit pin
// budget by exposing one byte at a time, selected by `byte_sel[1:0]`:
//   byte_sel=2'b00 -> rom_word[ 7:0]  (mantissa LSB)
//   byte_sel=2'b01 -> rom_word[15:8]  (mantissa MSB)
//   byte_sel=2'b10 -> rom_word[23:16] (signed exponent)
//   byte_sel=2'b11 -> {7'b0, tier_T}  (Tegmark-31 tier flag)
//
// Identical instance dropped into all 3 chips (PHI / EULER / GAMMA).
// Combinational — no clock, no reset — synthesises to a small mux tree
// fed by the underlying Crown47 case statement.
//
// Anchor: phi^2 + phi^-2 = 3 . DOI 10.5281/zenodo.19227877
// Pure Verilog-2005, R-SI-1 clean (zero standalone star operators).
// =============================================================================

module crown47_rom_8bit (
    input  wire [6:0] addr,        // 0..46 valid; 47..127 returns 0
    input  wire [1:0] byte_sel,    // 0=mant_lo 1=mant_hi 2=exp 3=tier_flag
    output reg  [7:0] byte_out
);

    wire [23:0] crown_word;
    wire        crown_tier_T;

    crown47_rom u_crown47 (
        .addr   (addr),
        .dout   (crown_word),
        .tier_T (crown_tier_T)
    );

    always @(*) begin
        case (byte_sel)
            2'b00:   byte_out = crown_word[7:0];
            2'b01:   byte_out = crown_word[15:8];
            2'b10:   byte_out = crown_word[23:16];
            2'b11:   byte_out = {7'b0, crown_tier_T};
            default: byte_out = 8'h00;
        endcase
    end

endmodule

`default_nettype wire
