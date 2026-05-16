// SPDX-License-Identifier: Apache-2.0
// redteam_filter.v — CLARA Gap-1 adversarial input detector
// 5 detector categories from CLARA-RED-TEAM.md (gHashTag/trinity-clara)
//
// R-SI-1 compliant: zero `*` operator.
// Pure Verilog-2005. All arithmetic via XOR/subtract/compare.
//
// Cell budget estimate:
//   (a) fuel_deception:         ~50 cells  (8-bit abs + comparator)
//   (b) action_exhaustion:      ~90 cells  (4×4 slot popcount + comparator)
//   (c) timeline_manipulation:  ~50 cells  (sign-extend abs + comparator)
//   (d) resource_poisoning:     ~30 cells  (sign bit + comparator)
//   (e) proof_trace_overflow:   ~20 cells  (4-bit comparator)
//   Total estimate:             ~240 cells (~0.5% GAMMA 48k budget)
//
// Anchor: phi^2+phi^-2=3. DOI 10.5281/zenodo.19227877
// DARPA CLARA PA-25-07-02 TA1 Gap-1 silicon implementation.

`default_nettype none

module redteam_filter (
    // Fuel deception inputs (8-bit unsigned)
    input  wire [7:0] reported_fuel,   // agent-reported fuel level (%)
    input  wire [7:0] actual_fuel,     // sensor-measured actual fuel (%)

    // Action exhaustion: last 16 actions, 4 bits each = 64-bit bus
    // action_history[63:60]=slot15(newest) ... action_history[3:0]=slot0(oldest)
    input  wire [63:0] action_history,

    // Timeline manipulation: signed 8-bit offset
    input  wire [7:0] timeline_offset, // signed; |offset| > 50 triggers

    // Resource poisoning: signed 8-bit compute demand
    input  wire [7:0] compute_demand,  // signed; negative OR >150 triggers

    // Proof trace overflow: 4-bit trace length
    input  wire [3:0] proof_trace_len, // >10 triggers

    // Outputs
    output wire [4:0] attack_detected, // [0]=fuel [1]=action [2]=timeline [3]=resource [4]=trace
    output wire       filter_block     // OR of all — asserts when any attack detected
);

    // =========================================================
    // (a) fuel_deception: abs(reported_fuel - actual_fuel) > 30
    // =========================================================
    wire [7:0] fuel_diff;
    wire [7:0] fuel_diff_neg;
    wire       fuel_sub_neg;        // 1 if reported < actual (borrow)
    wire [7:0] fuel_abs;

    // Subtract: reported - actual (9-bit to capture borrow)
    wire [8:0] fuel_sub = {1'b0, reported_fuel} - {1'b0, actual_fuel};
    assign fuel_sub_neg  = fuel_sub[8];        // borrow bit = negative
    assign fuel_diff     = fuel_sub[7:0];
    // If negative, negate: ~diff + 1
    assign fuel_diff_neg = (~fuel_diff) + 8'd1;
    assign fuel_abs      = fuel_sub_neg ? fuel_diff_neg : fuel_diff;

    // Compare abs > 30 (threshold per CLARA-RED-TEAM.md §1)
    wire detect_fuel = (fuel_abs > 8'd30);

    // =========================================================
    // (b) action_exhaustion: most-frequent action in last 16 > 11
    //     (>70% of 16 = 11.2, so ≥12 means >70%)
    // =========================================================
    // Extract 16 action slots, 4 bits each
    wire [3:0] act0  = action_history[3:0];
    wire [3:0] act1  = action_history[7:4];
    wire [3:0] act2  = action_history[11:8];
    wire [3:0] act3  = action_history[15:12];
    wire [3:0] act4  = action_history[19:16];
    wire [3:0] act5  = action_history[23:20];
    wire [3:0] act6  = action_history[27:24];
    wire [3:0] act7  = action_history[31:28];
    wire [3:0] act8  = action_history[35:32];
    wire [3:0] act9  = action_history[39:36];
    wire [3:0] act10 = action_history[43:40];
    wire [3:0] act11 = action_history[47:44];
    wire [3:0] act12 = action_history[51:48];
    wire [3:0] act13 = action_history[55:52];
    wire [3:0] act14 = action_history[59:56];
    wire [3:0] act15 = action_history[63:60];

    // Count occurrences of each 4-bit action value (0..15) across 16 slots
    // For each value v, cnt[v] = sum of (act_i == v) for i in 0..15
    // We check if any count > 11.
    //
    // Approach: for each candidate value v (0..15), compute a 5-bit popcount
    // of "equal" bits, then check > 11.
    // "Equal" bit: act_i == v iff (act_i ^ v) == 0 iff ~|(act_i ^ v)
    //
    // We use a function-like wire array for each candidate value.
    // Verilog-2005: no generate-array, spell out all 16 candidates.

    // Helper: equality bit for slot i vs value v
    // eq[v][i] = (act_i == v)
    // We encode: wire eq_v_i = ~|(act_i ^ v_const)
    // For 16 values × 16 slots = 256 wires, compute 16 popcounts.

    // Candidate v=0
    wire [15:0] eq0;
    assign eq0[0]  = (act0  == 4'd0);
    assign eq0[1]  = (act1  == 4'd0);
    assign eq0[2]  = (act2  == 4'd0);
    assign eq0[3]  = (act3  == 4'd0);
    assign eq0[4]  = (act4  == 4'd0);
    assign eq0[5]  = (act5  == 4'd0);
    assign eq0[6]  = (act6  == 4'd0);
    assign eq0[7]  = (act7  == 4'd0);
    assign eq0[8]  = (act8  == 4'd0);
    assign eq0[9]  = (act9  == 4'd0);
    assign eq0[10] = (act10 == 4'd0);
    assign eq0[11] = (act11 == 4'd0);
    assign eq0[12] = (act12 == 4'd0);
    assign eq0[13] = (act13 == 4'd0);
    assign eq0[14] = (act14 == 4'd0);
    assign eq0[15] = (act15 == 4'd0);

    // Candidate v=1
    wire [15:0] eq1;
    assign eq1[0]  = (act0  == 4'd1);
    assign eq1[1]  = (act1  == 4'd1);
    assign eq1[2]  = (act2  == 4'd1);
    assign eq1[3]  = (act3  == 4'd1);
    assign eq1[4]  = (act4  == 4'd1);
    assign eq1[5]  = (act5  == 4'd1);
    assign eq1[6]  = (act6  == 4'd1);
    assign eq1[7]  = (act7  == 4'd1);
    assign eq1[8]  = (act8  == 4'd1);
    assign eq1[9]  = (act9  == 4'd1);
    assign eq1[10] = (act10 == 4'd1);
    assign eq1[11] = (act11 == 4'd1);
    assign eq1[12] = (act12 == 4'd1);
    assign eq1[13] = (act13 == 4'd1);
    assign eq1[14] = (act14 == 4'd1);
    assign eq1[15] = (act15 == 4'd1);

    // Candidate v=2
    wire [15:0] eq2;
    assign eq2[0]  = (act0  == 4'd2);
    assign eq2[1]  = (act1  == 4'd2);
    assign eq2[2]  = (act2  == 4'd2);
    assign eq2[3]  = (act3  == 4'd2);
    assign eq2[4]  = (act4  == 4'd2);
    assign eq2[5]  = (act5  == 4'd2);
    assign eq2[6]  = (act6  == 4'd2);
    assign eq2[7]  = (act7  == 4'd2);
    assign eq2[8]  = (act8  == 4'd2);
    assign eq2[9]  = (act9  == 4'd2);
    assign eq2[10] = (act10 == 4'd2);
    assign eq2[11] = (act11 == 4'd2);
    assign eq2[12] = (act12 == 4'd2);
    assign eq2[13] = (act13 == 4'd2);
    assign eq2[14] = (act14 == 4'd2);
    assign eq2[15] = (act15 == 4'd2);

    // Candidate v=3
    wire [15:0] eq3;
    assign eq3[0]  = (act0  == 4'd3);
    assign eq3[1]  = (act1  == 4'd3);
    assign eq3[2]  = (act2  == 4'd3);
    assign eq3[3]  = (act3  == 4'd3);
    assign eq3[4]  = (act4  == 4'd3);
    assign eq3[5]  = (act5  == 4'd3);
    assign eq3[6]  = (act6  == 4'd3);
    assign eq3[7]  = (act7  == 4'd3);
    assign eq3[8]  = (act8  == 4'd3);
    assign eq3[9]  = (act9  == 4'd3);
    assign eq3[10] = (act10 == 4'd3);
    assign eq3[11] = (act11 == 4'd3);
    assign eq3[12] = (act12 == 4'd3);
    assign eq3[13] = (act13 == 4'd3);
    assign eq3[14] = (act14 == 4'd3);
    assign eq3[15] = (act15 == 4'd3);

    // Candidate v=4
    wire [15:0] eq4;
    assign eq4[0]  = (act0  == 4'd4);
    assign eq4[1]  = (act1  == 4'd4);
    assign eq4[2]  = (act2  == 4'd4);
    assign eq4[3]  = (act3  == 4'd4);
    assign eq4[4]  = (act4  == 4'd4);
    assign eq4[5]  = (act5  == 4'd4);
    assign eq4[6]  = (act6  == 4'd4);
    assign eq4[7]  = (act7  == 4'd4);
    assign eq4[8]  = (act8  == 4'd4);
    assign eq4[9]  = (act9  == 4'd4);
    assign eq4[10] = (act10 == 4'd4);
    assign eq4[11] = (act11 == 4'd4);
    assign eq4[12] = (act12 == 4'd4);
    assign eq4[13] = (act13 == 4'd4);
    assign eq4[14] = (act14 == 4'd4);
    assign eq4[15] = (act15 == 4'd4);

    // Candidate v=5
    wire [15:0] eq5;
    assign eq5[0]  = (act0  == 4'd5);
    assign eq5[1]  = (act1  == 4'd5);
    assign eq5[2]  = (act2  == 4'd5);
    assign eq5[3]  = (act3  == 4'd5);
    assign eq5[4]  = (act4  == 4'd5);
    assign eq5[5]  = (act5  == 4'd5);
    assign eq5[6]  = (act6  == 4'd5);
    assign eq5[7]  = (act7  == 4'd5);
    assign eq5[8]  = (act8  == 4'd5);
    assign eq5[9]  = (act9  == 4'd5);
    assign eq5[10] = (act10 == 4'd5);
    assign eq5[11] = (act11 == 4'd5);
    assign eq5[12] = (act12 == 4'd5);
    assign eq5[13] = (act13 == 4'd5);
    assign eq5[14] = (act14 == 4'd5);
    assign eq5[15] = (act15 == 4'd5);

    // Candidate v=6
    wire [15:0] eq6;
    assign eq6[0]  = (act0  == 4'd6);
    assign eq6[1]  = (act1  == 4'd6);
    assign eq6[2]  = (act2  == 4'd6);
    assign eq6[3]  = (act3  == 4'd6);
    assign eq6[4]  = (act4  == 4'd6);
    assign eq6[5]  = (act5  == 4'd6);
    assign eq6[6]  = (act6  == 4'd6);
    assign eq6[7]  = (act7  == 4'd6);
    assign eq6[8]  = (act8  == 4'd6);
    assign eq6[9]  = (act9  == 4'd6);
    assign eq6[10] = (act10 == 4'd6);
    assign eq6[11] = (act11 == 4'd6);
    assign eq6[12] = (act12 == 4'd6);
    assign eq6[13] = (act13 == 4'd6);
    assign eq6[14] = (act14 == 4'd6);
    assign eq6[15] = (act15 == 4'd6);

    // Candidate v=7
    wire [15:0] eq7;
    assign eq7[0]  = (act0  == 4'd7);
    assign eq7[1]  = (act1  == 4'd7);
    assign eq7[2]  = (act2  == 4'd7);
    assign eq7[3]  = (act3  == 4'd7);
    assign eq7[4]  = (act4  == 4'd7);
    assign eq7[5]  = (act5  == 4'd7);
    assign eq7[6]  = (act6  == 4'd7);
    assign eq7[7]  = (act7  == 4'd7);
    assign eq7[8]  = (act8  == 4'd7);
    assign eq7[9]  = (act9  == 4'd7);
    assign eq7[10] = (act10 == 4'd7);
    assign eq7[11] = (act11 == 4'd7);
    assign eq7[12] = (act12 == 4'd7);
    assign eq7[13] = (act13 == 4'd7);
    assign eq7[14] = (act14 == 4'd7);
    assign eq7[15] = (act15 == 4'd7);

    // Candidate v=8
    wire [15:0] eq8;
    assign eq8[0]  = (act0  == 4'd8);
    assign eq8[1]  = (act1  == 4'd8);
    assign eq8[2]  = (act2  == 4'd8);
    assign eq8[3]  = (act3  == 4'd8);
    assign eq8[4]  = (act4  == 4'd8);
    assign eq8[5]  = (act5  == 4'd8);
    assign eq8[6]  = (act6  == 4'd8);
    assign eq8[7]  = (act7  == 4'd8);
    assign eq8[8]  = (act8  == 4'd8);
    assign eq8[9]  = (act9  == 4'd8);
    assign eq8[10] = (act10 == 4'd8);
    assign eq8[11] = (act11 == 4'd8);
    assign eq8[12] = (act12 == 4'd8);
    assign eq8[13] = (act13 == 4'd8);
    assign eq8[14] = (act14 == 4'd8);
    assign eq8[15] = (act15 == 4'd8);

    // Candidate v=9
    wire [15:0] eq9;
    assign eq9[0]  = (act0  == 4'd9);
    assign eq9[1]  = (act1  == 4'd9);
    assign eq9[2]  = (act2  == 4'd9);
    assign eq9[3]  = (act3  == 4'd9);
    assign eq9[4]  = (act4  == 4'd9);
    assign eq9[5]  = (act5  == 4'd9);
    assign eq9[6]  = (act6  == 4'd9);
    assign eq9[7]  = (act7  == 4'd9);
    assign eq9[8]  = (act8  == 4'd9);
    assign eq9[9]  = (act9  == 4'd9);
    assign eq9[10] = (act10 == 4'd9);
    assign eq9[11] = (act11 == 4'd9);
    assign eq9[12] = (act12 == 4'd9);
    assign eq9[13] = (act13 == 4'd9);
    assign eq9[14] = (act14 == 4'd9);
    assign eq9[15] = (act15 == 4'd9);

    // Candidate v=10
    wire [15:0] eq10;
    assign eq10[0]  = (act0  == 4'd10);
    assign eq10[1]  = (act1  == 4'd10);
    assign eq10[2]  = (act2  == 4'd10);
    assign eq10[3]  = (act3  == 4'd10);
    assign eq10[4]  = (act4  == 4'd10);
    assign eq10[5]  = (act5  == 4'd10);
    assign eq10[6]  = (act6  == 4'd10);
    assign eq10[7]  = (act7  == 4'd10);
    assign eq10[8]  = (act8  == 4'd10);
    assign eq10[9]  = (act9  == 4'd10);
    assign eq10[10] = (act10 == 4'd10);
    assign eq10[11] = (act11 == 4'd10);
    assign eq10[12] = (act12 == 4'd10);
    assign eq10[13] = (act13 == 4'd10);
    assign eq10[14] = (act14 == 4'd10);
    assign eq10[15] = (act15 == 4'd10);

    // Candidate v=11
    wire [15:0] eq11;
    assign eq11[0]  = (act0  == 4'd11);
    assign eq11[1]  = (act1  == 4'd11);
    assign eq11[2]  = (act2  == 4'd11);
    assign eq11[3]  = (act3  == 4'd11);
    assign eq11[4]  = (act4  == 4'd11);
    assign eq11[5]  = (act5  == 4'd11);
    assign eq11[6]  = (act6  == 4'd11);
    assign eq11[7]  = (act7  == 4'd11);
    assign eq11[8]  = (act8  == 4'd11);
    assign eq11[9]  = (act9  == 4'd11);
    assign eq11[10] = (act10 == 4'd11);
    assign eq11[11] = (act11 == 4'd11);
    assign eq11[12] = (act12 == 4'd11);
    assign eq11[13] = (act13 == 4'd11);
    assign eq11[14] = (act14 == 4'd11);
    assign eq11[15] = (act15 == 4'd11);

    // Candidate v=12
    wire [15:0] eq12;
    assign eq12[0]  = (act0  == 4'd12);
    assign eq12[1]  = (act1  == 4'd12);
    assign eq12[2]  = (act2  == 4'd12);
    assign eq12[3]  = (act3  == 4'd12);
    assign eq12[4]  = (act4  == 4'd12);
    assign eq12[5]  = (act5  == 4'd12);
    assign eq12[6]  = (act6  == 4'd12);
    assign eq12[7]  = (act7  == 4'd12);
    assign eq12[8]  = (act8  == 4'd12);
    assign eq12[9]  = (act9  == 4'd12);
    assign eq12[10] = (act10 == 4'd12);
    assign eq12[11] = (act11 == 4'd12);
    assign eq12[12] = (act12 == 4'd12);
    assign eq12[13] = (act13 == 4'd12);
    assign eq12[14] = (act14 == 4'd12);
    assign eq12[15] = (act15 == 4'd12);

    // Candidate v=13
    wire [15:0] eq13;
    assign eq13[0]  = (act0  == 4'd13);
    assign eq13[1]  = (act1  == 4'd13);
    assign eq13[2]  = (act2  == 4'd13);
    assign eq13[3]  = (act3  == 4'd13);
    assign eq13[4]  = (act4  == 4'd13);
    assign eq13[5]  = (act5  == 4'd13);
    assign eq13[6]  = (act6  == 4'd13);
    assign eq13[7]  = (act7  == 4'd13);
    assign eq13[8]  = (act8  == 4'd13);
    assign eq13[9]  = (act9  == 4'd13);
    assign eq13[10] = (act10 == 4'd13);
    assign eq13[11] = (act11 == 4'd13);
    assign eq13[12] = (act12 == 4'd13);
    assign eq13[13] = (act13 == 4'd13);
    assign eq13[14] = (act14 == 4'd13);
    assign eq13[15] = (act15 == 4'd13);

    // Candidate v=14
    wire [15:0] eq14;
    assign eq14[0]  = (act0  == 4'd14);
    assign eq14[1]  = (act1  == 4'd14);
    assign eq14[2]  = (act2  == 4'd14);
    assign eq14[3]  = (act3  == 4'd14);
    assign eq14[4]  = (act4  == 4'd14);
    assign eq14[5]  = (act5  == 4'd14);
    assign eq14[6]  = (act6  == 4'd14);
    assign eq14[7]  = (act7  == 4'd14);
    assign eq14[8]  = (act8  == 4'd14);
    assign eq14[9]  = (act9  == 4'd14);
    assign eq14[10] = (act10 == 4'd14);
    assign eq14[11] = (act11 == 4'd14);
    assign eq14[12] = (act12 == 4'd14);
    assign eq14[13] = (act13 == 4'd14);
    assign eq14[14] = (act14 == 4'd14);
    assign eq14[15] = (act15 == 4'd14);

    // Candidate v=15
    wire [15:0] eq15;
    assign eq15[0]  = (act0  == 4'd15);
    assign eq15[1]  = (act1  == 4'd15);
    assign eq15[2]  = (act2  == 4'd15);
    assign eq15[3]  = (act3  == 4'd15);
    assign eq15[4]  = (act4  == 4'd15);
    assign eq15[5]  = (act5  == 4'd15);
    assign eq15[6]  = (act6  == 4'd15);
    assign eq15[7]  = (act7  == 4'd15);
    assign eq15[8]  = (act8  == 4'd15);
    assign eq15[9]  = (act9  == 4'd15);
    assign eq15[10] = (act10 == 4'd15);
    assign eq15[11] = (act11 == 4'd15);
    assign eq15[12] = (act12 == 4'd15);
    assign eq15[13] = (act13 == 4'd15);
    assign eq15[14] = (act14 == 4'd15);
    assign eq15[15] = (act15 == 4'd15);

    // Popcount each candidate (5-bit result, 0..16)
    // Using adder tree: no * operator
    wire [4:0] cnt0;
    wire [4:0] cnt1;
    wire [4:0] cnt2;
    wire [4:0] cnt3;
    wire [4:0] cnt4;
    wire [4:0] cnt5;
    wire [4:0] cnt6;
    wire [4:0] cnt7;
    wire [4:0] cnt8;
    wire [4:0] cnt9;
    wire [4:0] cnt10;
    wire [4:0] cnt11;
    wire [4:0] cnt12;
    wire [4:0] cnt13;
    wire [4:0] cnt14;
    wire [4:0] cnt15;

    assign cnt0  = eq0[0]  + eq0[1]  + eq0[2]  + eq0[3]  + eq0[4]  + eq0[5]  + eq0[6]  + eq0[7]
                 + eq0[8]  + eq0[9]  + eq0[10] + eq0[11] + eq0[12] + eq0[13] + eq0[14] + eq0[15];
    assign cnt1  = eq1[0]  + eq1[1]  + eq1[2]  + eq1[3]  + eq1[4]  + eq1[5]  + eq1[6]  + eq1[7]
                 + eq1[8]  + eq1[9]  + eq1[10] + eq1[11] + eq1[12] + eq1[13] + eq1[14] + eq1[15];
    assign cnt2  = eq2[0]  + eq2[1]  + eq2[2]  + eq2[3]  + eq2[4]  + eq2[5]  + eq2[6]  + eq2[7]
                 + eq2[8]  + eq2[9]  + eq2[10] + eq2[11] + eq2[12] + eq2[13] + eq2[14] + eq2[15];
    assign cnt3  = eq3[0]  + eq3[1]  + eq3[2]  + eq3[3]  + eq3[4]  + eq3[5]  + eq3[6]  + eq3[7]
                 + eq3[8]  + eq3[9]  + eq3[10] + eq3[11] + eq3[12] + eq3[13] + eq3[14] + eq3[15];
    assign cnt4  = eq4[0]  + eq4[1]  + eq4[2]  + eq4[3]  + eq4[4]  + eq4[5]  + eq4[6]  + eq4[7]
                 + eq4[8]  + eq4[9]  + eq4[10] + eq4[11] + eq4[12] + eq4[13] + eq4[14] + eq4[15];
    assign cnt5  = eq5[0]  + eq5[1]  + eq5[2]  + eq5[3]  + eq5[4]  + eq5[5]  + eq5[6]  + eq5[7]
                 + eq5[8]  + eq5[9]  + eq5[10] + eq5[11] + eq5[12] + eq5[13] + eq5[14] + eq5[15];
    assign cnt6  = eq6[0]  + eq6[1]  + eq6[2]  + eq6[3]  + eq6[4]  + eq6[5]  + eq6[6]  + eq6[7]
                 + eq6[8]  + eq6[9]  + eq6[10] + eq6[11] + eq6[12] + eq6[13] + eq6[14] + eq6[15];
    assign cnt7  = eq7[0]  + eq7[1]  + eq7[2]  + eq7[3]  + eq7[4]  + eq7[5]  + eq7[6]  + eq7[7]
                 + eq7[8]  + eq7[9]  + eq7[10] + eq7[11] + eq7[12] + eq7[13] + eq7[14] + eq7[15];
    assign cnt8  = eq8[0]  + eq8[1]  + eq8[2]  + eq8[3]  + eq8[4]  + eq8[5]  + eq8[6]  + eq8[7]
                 + eq8[8]  + eq8[9]  + eq8[10] + eq8[11] + eq8[12] + eq8[13] + eq8[14] + eq8[15];
    assign cnt9  = eq9[0]  + eq9[1]  + eq9[2]  + eq9[3]  + eq9[4]  + eq9[5]  + eq9[6]  + eq9[7]
                 + eq9[8]  + eq9[9]  + eq9[10] + eq9[11] + eq9[12] + eq9[13] + eq9[14] + eq9[15];
    assign cnt10 = eq10[0] + eq10[1] + eq10[2] + eq10[3] + eq10[4] + eq10[5] + eq10[6] + eq10[7]
                 + eq10[8] + eq10[9] + eq10[10]+ eq10[11]+ eq10[12]+ eq10[13]+ eq10[14]+ eq10[15];
    assign cnt11 = eq11[0] + eq11[1] + eq11[2] + eq11[3] + eq11[4] + eq11[5] + eq11[6] + eq11[7]
                 + eq11[8] + eq11[9] + eq11[10]+ eq11[11]+ eq11[12]+ eq11[13]+ eq11[14]+ eq11[15];
    assign cnt12 = eq12[0] + eq12[1] + eq12[2] + eq12[3] + eq12[4] + eq12[5] + eq12[6] + eq12[7]
                 + eq12[8] + eq12[9] + eq12[10]+ eq12[11]+ eq12[12]+ eq12[13]+ eq12[14]+ eq12[15];
    assign cnt13 = eq13[0] + eq13[1] + eq13[2] + eq13[3] + eq13[4] + eq13[5] + eq13[6] + eq13[7]
                 + eq13[8] + eq13[9] + eq13[10]+ eq13[11]+ eq13[12]+ eq13[13]+ eq13[14]+ eq13[15];
    assign cnt14 = eq14[0] + eq14[1] + eq14[2] + eq14[3] + eq14[4] + eq14[5] + eq14[6] + eq14[7]
                 + eq14[8] + eq14[9] + eq14[10]+ eq14[11]+ eq14[12]+ eq14[13]+ eq14[14]+ eq14[15];
    assign cnt15 = eq15[0] + eq15[1] + eq15[2] + eq15[3] + eq15[4] + eq15[5] + eq15[6] + eq15[7]
                 + eq15[8] + eq15[9] + eq15[10]+ eq15[11]+ eq15[12]+ eq15[13]+ eq15[14]+ eq15[15];

    // Detect if any candidate appears > 11 times (>70% of 16 slots)
    wire detect_action =
        (cnt0  > 5'd11) | (cnt1  > 5'd11) | (cnt2  > 5'd11) | (cnt3  > 5'd11) |
        (cnt4  > 5'd11) | (cnt5  > 5'd11) | (cnt6  > 5'd11) | (cnt7  > 5'd11) |
        (cnt8  > 5'd11) | (cnt9  > 5'd11) | (cnt10 > 5'd11) | (cnt11 > 5'd11) |
        (cnt12 > 5'd11) | (cnt13 > 5'd11) | (cnt14 > 5'd11) | (cnt15 > 5'd11);

    // =========================================================
    // (c) timeline_manipulation: |timeline_offset| > 50
    //     timeline_offset is treated as signed 8-bit
    // =========================================================
    wire       tl_neg     = timeline_offset[7]; // sign bit
    wire [7:0] tl_neg_val = (~timeline_offset) + 8'd1;
    wire [7:0] tl_abs     = tl_neg ? tl_neg_val : timeline_offset;

    // Compare abs > 50
    wire detect_timeline = (tl_abs > 8'd50);

    // =========================================================
    // (d) resource_poisoning: compute_demand[7] (negative) OR > 150
    // =========================================================
    wire detect_resource = compute_demand[7] | (compute_demand > 8'd150);

    // =========================================================
    // (e) proof_trace_overflow: proof_trace_len > 10
    // =========================================================
    wire detect_trace = (proof_trace_len > 4'd10);

    // =========================================================
    // Output assembly
    // =========================================================
    assign attack_detected[0] = detect_fuel;
    assign attack_detected[1] = detect_action;
    assign attack_detected[2] = detect_timeline;
    assign attack_detected[3] = detect_resource;
    assign attack_detected[4] = detect_trace;

    assign filter_block = |attack_detected;

endmodule
`default_nettype wire
