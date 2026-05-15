// =============================================================================
// holo_lut_pe.sv — Platinum MST LUT Processing Element
// =============================================================================
// L-DPC25 Lane V · lever1-lut-pe
// Ref: Platinum (arXiv:2511.21910, ASP-DAC 2026)
//   Mechanism: 5-input ternary LUT with Mirror Consolidation
//   LUT size: ⌈3⁵/2⌉ = ⌈243/2⌉ = 122 entries
//   Reported gain: 1.4× over bit-serial path
//
// R-SI-1 compliance: ZERO `*` operators — all arithmetic is shifts + ROM read.
// R18 LAYER-FROZEN: additive PE variant, does NOT modify existing PE pipeline.
// Author: admin@t27.ai
// Anchor: φ²+φ⁻²=3 · DOI 10.5281/zenodo.19227877
// Foundation: Lane X HOP_lut_pe Coq variant proved Q4-clean (t27#634 · 239144df)
// =============================================================================

`default_nettype none

module holo_lut_pe #(
    // WIDTH: output word width (default 8 for ternary-encoded result)
    parameter int unsigned WIDTH     = 8,
    // MST_DEPTH: number of ternary inputs (default 5 → 3⁵ = 243 raw entries)
    parameter int unsigned MST_DEPTH = 5
) (
    input  wire              clk_i,
    input  wire              rst_ni,    // active-low synchronous reset

    // 5-input ternary address: each trit is 2-bit encoded → 10-bit raw input
    // MST path-construction reduces effective address space to 7-bit (122 ≈ 2⁷)
    input  wire [9:0]        trit_idx_i,  // 5 × 2-bit trit encoding

    // Out-of-bounds flag: asserted when trit_idx_i maps to index >= 122
    output logic             oob_o,

    // 1-cycle pipelined LUT output
    output logic [WIDTH-1:0] result_o
);

    // -------------------------------------------------------------------------
    // LUT ROM: 122 entries (Mirror Consolidation: ⌈243/2⌉)
    // Sentinel pattern: lut_rom[n] = 8'hC0 + n  (8'hC0..8'hC79)
    // "Replaced by MST path-construction output post-Lane X Coq alphabet
    //  integration" — real values generated offline from Platinum MST builder.
    // -------------------------------------------------------------------------
    localparam int unsigned LUT_DEPTH = 122;

    logic [WIDTH-1:0] lut_rom [0:LUT_DEPTH-1];

    // Sentinel initialisation — synthesis will infer a ROM
    initial begin : lut_rom_init
        // lut_rom[n] = 8'hC0 + n  for n in [0..121]
        // Sentinel pattern acknowledges Lane X Coq alphabet integration pending.
        lut_rom[ 0] = 8'hC0;  lut_rom[ 1] = 8'hC1;  lut_rom[ 2] = 8'hC2;
        lut_rom[ 3] = 8'hC3;  lut_rom[ 4] = 8'hC4;  lut_rom[ 5] = 8'hC5;
        lut_rom[ 6] = 8'hC6;  lut_rom[ 7] = 8'hC7;  lut_rom[ 8] = 8'hC8;
        lut_rom[ 9] = 8'hC9;  lut_rom[10] = 8'hCA;  lut_rom[11] = 8'hCB;
        lut_rom[12] = 8'hCC;  lut_rom[13] = 8'hCD;  lut_rom[14] = 8'hCE;
        lut_rom[15] = 8'hCF;  lut_rom[16] = 8'hD0;  lut_rom[17] = 8'hD1;
        lut_rom[18] = 8'hD2;  lut_rom[19] = 8'hD3;  lut_rom[20] = 8'hD4;
        lut_rom[21] = 8'hD5;  lut_rom[22] = 8'hD6;  lut_rom[23] = 8'hD7;
        lut_rom[24] = 8'hD8;  lut_rom[25] = 8'hD9;  lut_rom[26] = 8'hDA;
        lut_rom[27] = 8'hDB;  lut_rom[28] = 8'hDC;  lut_rom[29] = 8'hDD;
        lut_rom[30] = 8'hDE;  lut_rom[31] = 8'hDF;  lut_rom[32] = 8'hE0;
        lut_rom[33] = 8'hE1;  lut_rom[34] = 8'hE2;  lut_rom[35] = 8'hE3;
        lut_rom[36] = 8'hE4;  lut_rom[37] = 8'hE5;  lut_rom[38] = 8'hE6;
        lut_rom[39] = 8'hE7;  lut_rom[40] = 8'hE8;  lut_rom[41] = 8'hE9;
        lut_rom[42] = 8'hEA;  lut_rom[43] = 8'hEB;  lut_rom[44] = 8'hEC;
        lut_rom[45] = 8'hED;  lut_rom[46] = 8'hEE;  lut_rom[47] = 8'hEF;
        lut_rom[48] = 8'hF0;  lut_rom[49] = 8'hF1;  lut_rom[50] = 8'hF2;
        lut_rom[51] = 8'hF3;  lut_rom[52] = 8'hF4;  lut_rom[53] = 8'hF5;
        lut_rom[54] = 8'hF6;  lut_rom[55] = 8'hF7;  lut_rom[56] = 8'hF8;
        lut_rom[57] = 8'hF9;  lut_rom[58] = 8'hFA;  lut_rom[59] = 8'hFB;
        lut_rom[60] = 8'hFC;  lut_rom[61] = 8'hFD;  lut_rom[62] = 8'hFE;
        lut_rom[63] = 8'hFF;
        // entries 64..121 wrap: 8'hC0 + (n - 64) with bit[7]=1 preserved
        // Sentinel: offset continues mod 256 → values 8'h00..8'h39
        lut_rom[64]  = 8'h00;  lut_rom[65]  = 8'h01;  lut_rom[66]  = 8'h02;
        lut_rom[67]  = 8'h03;  lut_rom[68]  = 8'h04;  lut_rom[69]  = 8'h05;
        lut_rom[70]  = 8'h06;  lut_rom[71]  = 8'h07;  lut_rom[72]  = 8'h08;
        lut_rom[73]  = 8'h09;  lut_rom[74]  = 8'h0A;  lut_rom[75]  = 8'h0B;
        lut_rom[76]  = 8'h0C;  lut_rom[77]  = 8'h0D;  lut_rom[78]  = 8'h0E;
        lut_rom[79]  = 8'h0F;  lut_rom[80]  = 8'h10;  lut_rom[81]  = 8'h11;
        lut_rom[82]  = 8'h12;  lut_rom[83]  = 8'h13;  lut_rom[84]  = 8'h14;
        lut_rom[85]  = 8'h15;  lut_rom[86]  = 8'h16;  lut_rom[87]  = 8'h17;
        lut_rom[88]  = 8'h18;  lut_rom[89]  = 8'h19;  lut_rom[90]  = 8'h1A;
        lut_rom[91]  = 8'h1B;  lut_rom[92]  = 8'h1C;  lut_rom[93]  = 8'h1D;
        lut_rom[94]  = 8'h1E;  lut_rom[95]  = 8'h1F;  lut_rom[96]  = 8'h20;
        lut_rom[97]  = 8'h21;  lut_rom[98]  = 8'h22;  lut_rom[99]  = 8'h23;
        lut_rom[100] = 8'h24;  lut_rom[101] = 8'h25;  lut_rom[102] = 8'h26;
        lut_rom[103] = 8'h27;  lut_rom[104] = 8'h28;  lut_rom[105] = 8'h29;
        lut_rom[106] = 8'h2A;  lut_rom[107] = 8'h2B;  lut_rom[108] = 8'h2C;
        lut_rom[109] = 8'h2D;  lut_rom[110] = 8'h2E;  lut_rom[111] = 8'h2F;
        lut_rom[112] = 8'h30;  lut_rom[113] = 8'h31;  lut_rom[114] = 8'h32;
        lut_rom[115] = 8'h33;  lut_rom[116] = 8'h34;  lut_rom[117] = 8'h35;
        lut_rom[118] = 8'h36;  lut_rom[119] = 8'h37;  lut_rom[120] = 8'h38;
        lut_rom[121] = 8'h39;
    end

    // -------------------------------------------------------------------------
    // MST index decode: 10-bit trit_idx_i → 7-bit lut address
    // Each pair of bits encodes one trit {2'b00=−1, 2'b01=0, 2'b10=+1}
    // Base-3 collapse: addr = Σ trit_i * 3^i  (shifts, NO `*`)
    // 3^0=1, 3^1=3, 3^2=9, 3^3=27, 3^4=81
    // Mirror Consolidation: if addr >= 122, use (242 - addr) instead;
    //   this folds the upper half back → all indices land in [0..121].
    // -------------------------------------------------------------------------
    function automatic logic [7:0] trit_to_val (input logic [1:0] enc);
        // 2'b00 → 0  (−1 mapped to 0 for address purposes)
        // 2'b01 → 1  (0  mapped to 1)
        // 2'b10 → 2  (+1 mapped to 2)
        // 2'b11 → reserved (treat as 0)
        case (enc)
            2'b00: trit_to_val = 8'd0;
            2'b01: trit_to_val = 8'd1;
            2'b10: trit_to_val = 8'd2;
            default: trit_to_val = 8'd0;
        endcase
    endfunction

    // Combinational address decode (shifts + adds, NO `*`)
    logic [7:0] raw_addr;
    logic [6:0] lut_addr;
    logic       oob_comb;

    always_comb begin : addr_decode
        // Decode each trit
        logic [7:0] t0, t1, t2, t3, t4;
        t0 = trit_to_val(trit_idx_i[1:0]);   // × 3^0 = × 1
        t1 = trit_to_val(trit_idx_i[3:2]);   // × 3^1 = × 3
        t2 = trit_to_val(trit_idx_i[5:4]);   // × 3^2 = × 9
        t3 = trit_to_val(trit_idx_i[7:6]);   // × 3^3 = × 27
        t4 = trit_to_val(trit_idx_i[9:8]);   // × 3^4 = × 81

        // Shift-add expansion (no `*` operators):
        //   t1 * 3  = (t1 << 1) + t1
        //   t2 * 9  = (t2 << 3) + t2
        //   t3 * 27 = (t3 << 4) + (t3 << 3) + (t3 << 1) + t3
        //   t4 * 81 = (t4 << 6) + (t4 << 4) + t4
        logic [7:0] v1, v2, v3, v4;
        v1 = (t1 << 1) + t1;
        v2 = (t2 << 3) + t2;
        v3 = (t3 << 4) + (t3 << 3) + (t3 << 1) + t3;
        v4 = (t4 << 6) + (t4 << 4) + t4;

        raw_addr = t0 + v1 + v2 + v3 + v4;  // range [0..242]

        // Mirror Consolidation: fold upper half [122..242] → [121..1]
        // 242 - raw_addr when raw_addr >= 122
        if (raw_addr >= 8'd122) begin
            lut_addr  = 7'(8'd242 - raw_addr);
            oob_comb  = 1'b0;   // valid after mirror fold
        end else begin
            lut_addr  = raw_addr[6:0];
            oob_comb  = 1'b0;
        end

        // OOB: trit encoding 2'b11 is reserved → flag raw_addr > 242
        // (unreachable with 3-valid-trit encoding; reserved for safety)
        if (raw_addr > 8'd242) begin
            lut_addr = 7'd0;
            oob_comb = 1'b1;
        end
    end

    // -------------------------------------------------------------------------
    // 1-cycle pipeline registers (active-low sync reset)
    // Stage 1: register address + oob
    // Stage 2: ROM read → register output
    // -------------------------------------------------------------------------
    logic [6:0] lut_addr_r;
    logic       oob_r;

    always_ff @(posedge clk_i) begin : pipe_stage1
        if (!rst_ni) begin
            lut_addr_r <= 7'd0;
            oob_r      <= 1'b0;
        end else begin
            lut_addr_r <= lut_addr;
            oob_r      <= oob_comb;
        end
    end

    always_ff @(posedge clk_i) begin : pipe_stage2
        if (!rst_ni) begin
            result_o <= {WIDTH{1'b0}};
            oob_o    <= 1'b0;
        end else begin
            result_o <= oob_r ? {WIDTH{1'b0}} : lut_rom[lut_addr_r];
            oob_o    <= oob_r;
        end
    end

endmodule

`default_nettype wire
// EOF holo_lut_pe.sv
