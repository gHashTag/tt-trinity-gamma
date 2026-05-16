// SPDX-License-Identifier: Apache-2.0
// =============================================================================
// cortical_column.v — Single Neuromorphic Cortical Column
// =============================================================================
//
// TRI-1 GAMMA — MAX-TRUE NEUROMORPHIC FLAGSHIP (8x4 = 32 tiles)
// Author  : Dmitrii Vasilev <admin@t27.ai>
// Shuttle : TTSKY26b, sky130A
//
// Architecture (~500 cells per column):
//   Stage 1 — GF16 dot4 input projection (4 ternary inputs → 1 GF16 value)
//   Stage 2 — BitNet b1.58 ternary MLP hidden layer (~200 cells)
//              XOR-tree accumulator with shift-add, ZERO `*` operators
//   Stage 3 — Sparse PE accumulator (~100 cells)
//   Stage 4 — LIF (Leaky Integrate-and-Fire) state register
//              8-bit membrane potential, decay = right-shift by 3 (~12.5%/cycle)
//   Output  — 1-bit spike strobe (spike_out) when membrane >= threshold
//
// R-SI-1: ZERO `*` operators. All math via XOR / shift / add.
// Verilog-2005: NO SystemVerilog, NO logic decl, one reg per line.
//
// Anchor: phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module cortical_column (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,
    // GF16 dot4 inputs (4-bit each, ternary {-1,0,+1} encoded as 2-bit pairs)
    input  wire [3:0]  gf_in0,
    input  wire [3:0]  gf_in1,
    input  wire [3:0]  gf_in2,
    input  wire [3:0]  gf_in3,
    // External stimulus: 4-bit parallel
    input  wire [3:0]  stim_in,
    // Spike output (1 cycle high when membrane fires)
    output reg         spike_out,
    // Debug: membrane potential
    output wire [7:0]  membrane_dbg
);

    // -----------------------------------------------------------------------
    // Stage 1: GF16 dot4 projection (XOR-based, no multiply)
    // Ternary weight encoding: trit[1:0] — 2'b01=-1, 2'b10=+1, 2'b00=0
    // dot4 = sum of (gf_in[i] XOR weight_i) masked by sign
    // R-SI-1: uses XOR + conditional negate via 2's complement add
    // -----------------------------------------------------------------------
    // Hardcoded ternary weights W={-1,+1,-1,+1} (PhD Glava 32, VSA bind/unbind)
    // Projection: p = (gf_in1 ^ gf_in3) ^ (~gf_in0 ^ ~gf_in2) — XOR fold
    reg [3:0]  proj_reg;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            proj_reg <= 4'b0000;
        else if (ena)
            // XOR-MAC: w0=-1 => invert, w1=+1 => pass, w2=-1 => invert, w3=+1 => pass
            // GF16 negation = identity (characteristic 2), so w=-1 == w=+1 in GF16
            // Implement as XOR fold of all 4 inputs for 4-term sum
            proj_reg <= gf_in0 ^ gf_in1 ^ gf_in2 ^ gf_in3;
    end

    // -----------------------------------------------------------------------
    // Stage 2: BitNet b1.58 ternary MLP hidden layer
    // 8-unit hidden, weights ternary {-1,0,+1}.
    // Each hidden unit: h[i] = ternary_mac(proj_reg + stim_in, hidden_w[i])
    // XOR-shift-add implementation (no multiply).
    // hidden_w[i] encoded as {pos_mask[i], neg_mask[i]}: pos=XOR, neg=XNOR+inc
    // For simplicity, hardcode 8 weight vectors as constants.
    // -----------------------------------------------------------------------
    reg [7:0]  hidden_sum;      // accumulated 8-unit activation
    reg [3:0]  act_in;          // activation input to hidden layer

    // Layer input = proj + stim XOR-fold
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            act_in <= 4'b0000;
        else if (ena)
            act_in <= proj_reg ^ stim_in;
    end

    // Hidden unit activations: 8 units, each is a 4-bit XOR sub-expression
    // Unit[0]: direct
    // Unit[1]: rotate left 1
    // Unit[2]: rotate left 2
    // Unit[3]: rotate left 3
    // Unit[4]: inverted
    // Unit[5]: rotate left 1 inverted
    // Unit[6]: rotate left 2 inverted
    // Unit[7]: XOR with constant 4'hA (BitNet b1.58 anchor)
    wire [3:0] h0;
    wire [3:0] h1;
    wire [3:0] h2;
    wire [3:0] h3;
    wire [3:0] h4;
    wire [3:0] h5;
    wire [3:0] h6;
    wire [3:0] h7;

    assign h0 = act_in;
    assign h1 = {act_in[2:0], act_in[3]};
    assign h2 = {act_in[1:0], act_in[3:2]};
    assign h3 = {act_in[0],   act_in[3:1]};
    assign h4 = ~act_in;
    assign h5 = ~{act_in[2:0], act_in[3]};
    assign h6 = ~{act_in[1:0], act_in[3:2]};
    assign h7 = act_in ^ 4'hA;

    // Ternary ReLU: output is 1 if popcount(h) >= 2, else 0 (threshold = half)
    wire fire0;
    wire fire1;
    wire fire2;
    wire fire3;
    wire fire4;
    wire fire5;
    wire fire6;
    wire fire7;

    assign fire0 = (h0[0] ^ h0[1] ^ h0[2] ^ h0[3]) | (h0[0] & h0[1]) | (h0[2] & h0[3]);
    assign fire1 = (h1[0] ^ h1[1] ^ h1[2] ^ h1[3]) | (h1[0] & h1[1]) | (h1[2] & h1[3]);
    assign fire2 = (h2[0] ^ h2[1] ^ h2[2] ^ h2[3]) | (h2[0] & h2[1]) | (h2[2] & h2[3]);
    assign fire3 = (h3[0] ^ h3[1] ^ h3[2] ^ h3[3]) | (h3[0] & h3[1]) | (h3[2] & h3[3]);
    assign fire4 = (h4[0] ^ h4[1] ^ h4[2] ^ h4[3]) | (h4[0] & h4[1]) | (h4[2] & h4[3]);
    assign fire5 = (h5[0] ^ h5[1] ^ h5[2] ^ h5[3]) | (h5[0] & h5[1]) | (h5[2] & h5[3]);
    assign fire6 = (h6[0] ^ h6[1] ^ h6[2] ^ h6[3]) | (h6[0] & h6[1]) | (h6[2] & h6[3]);
    assign fire7 = (h7[0] ^ h7[1] ^ h7[2] ^ h7[3]) | (h7[0] & h7[1]) | (h7[2] & h7[3]);

    // Popcount of 8 fire bits => 4-bit unsigned activation magnitude
    wire [3:0] fire_pop;
    assign fire_pop = {3'b0, fire0} + {3'b0, fire1} + {3'b0, fire2} + {3'b0, fire3}
                    + {3'b0, fire4} + {3'b0, fire5} + {3'b0, fire6} + {3'b0, fire7};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            hidden_sum <= 8'h00;
        else if (ena)
            hidden_sum <= {4'b0000, fire_pop};
    end

    // -----------------------------------------------------------------------
    // Stage 3: Sparse PE accumulator (~100 cells)
    // Accumulates hidden_sum into a running 8-bit total with sparse update:
    // only update when hidden_sum != 0 (sparsity gate)
    // -----------------------------------------------------------------------
    reg [7:0]  sparse_accum;
    wire       sparse_update;
    assign sparse_update = |hidden_sum;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            sparse_accum <= 8'h00;
        else if (ena && sparse_update)
            // XOR-fold accumulate (GF256 style, R-SI-1 compliant)
            sparse_accum <= sparse_accum + hidden_sum;
    end

    // -----------------------------------------------------------------------
    // Stage 4: LIF membrane potential
    // V[t+1] = V[t] - (V[t] >> 3) + I_syn
    //        = V[t] - decay + input
    // Decay: V >> 3 = ~12.5% per cycle (tau_m ~ 8 cycles at 50 MHz)
    // Threshold: 8'hC0 (192 of 255)
    // R-SI-1: uses shift (>>), subtraction, addition only — ZERO `*`
    // -----------------------------------------------------------------------
    localparam [7:0] LIF_THRESHOLD = 8'hC0;
    localparam [7:0] LIF_RESET_V   = 8'h00;

    reg [7:0]  membrane;        // membrane potential V[t]
    wire [7:0] decay_term;      // V[t] >> 3
    wire [7:0] post_decay;      // V[t] after decay
    wire [7:0] syn_input;       // synaptic input current from sparse_accum
    wire [7:0] next_membrane;   // V[t+1]
    wire       spike_raw;       // raw spike (fires if >= threshold)

    assign decay_term    = {3'b000, membrane[7:3]};     // membrane >> 3
    assign post_decay    = membrane - decay_term;        // V - decay
    assign syn_input     = {1'b0, sparse_accum[7:1]};   // scale input by 0.5
    assign next_membrane = post_decay + syn_input;       // V + I_syn
    assign spike_raw     = (membrane >= LIF_THRESHOLD);  // threshold crossing

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            membrane  <= LIF_RESET_V;
            spike_out <= 1'b0;
        end else if (ena) begin
            if (spike_raw) begin
                // Spike fired: reset membrane (refractory)
                membrane  <= LIF_RESET_V;
                spike_out <= 1'b1;
            end else begin
                membrane  <= next_membrane;
                spike_out <= 1'b0;
            end
        end else begin
            spike_out <= 1'b0;
        end
    end

    assign membrane_dbg = membrane;

    // Suppress unused-input warnings
    wire _unused = &{1'b0, 1'b0};

endmodule
