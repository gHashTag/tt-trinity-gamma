`default_nettype none
// multi_tile_receipt_v2.v — CORRECTED multi-tile RECEIPT XOR fan-in.
// Apache-2.0
//
// FIX (2026-06): the shipped multi_tile_receipt accumulates each tile in its own
// `if (tN_valid) agg_checksum <= agg_checksum ^ tN_checksum;` block. Those are
// four NON-BLOCKING assignments to the SAME register in one always block, so when
// more than one tile is valid in the same cycle the LAST one wins and the other
// simultaneous contributions are DROPPED (verified: 4 distinct tiles valid in one
// cycle -> only t3 survives, not t0^t1^t2^t3). The attested_mask / all_attested
// path is unaffected (each mask bit is its own register). v2 folds all valid
// contributions into ONE expression so the XOR-sum is correct and order-
// independent regardless of how many tiles assert in a cycle.
//
// IMPORTANT — NOT a drop-in for the current Gamma/Euler tops. On those dies all
// four tile ports are tied to the SAME replicated source (mesh_rcpt_*), so the
// shipped last-wins bug happens to give the desired single-source accumulation
// (agg ^= checksum per valid cycle), while a *correct* 4-tile XOR over four
// identical inputs would give agg ^= (c^c^c^c) = 0. So v2 is the fix for the
// FUTURE case of four DISTINCT tile receipts and must be paired with distinct
// per-tile wiring; swapping it under the current replicated hookup would zero the
// aggregate. The fabricated dies use the original, frozen multi_tile_receipt.
//
// PhD anchor: Chapter 12 / DePIN — multi-tile attestability.

module multi_tile_receipt_v2 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        t0_valid,
    input  wire [7:0]  t0_checksum,
    input  wire [7:0]  t0_job_id,
    input  wire        t1_valid,
    input  wire [7:0]  t1_checksum,
    input  wire [7:0]  t1_job_id,
    input  wire        t2_valid,
    input  wire [7:0]  t2_checksum,
    input  wire [7:0]  t2_job_id,
    input  wire        t3_valid,
    input  wire [7:0]  t3_checksum,
    input  wire [7:0]  t3_job_id,
    output reg  [7:0]  agg_checksum,
    output reg  [7:0]  agg_job_id,
    output reg  [3:0]  attested_mask,
    output wire        all_attested,
    output wire        multi_rcpt_ok
);

    // Per-tile masked contributions (0 when that tile is not valid this cycle).
    wire [7:0] c0 = t0_valid ? t0_checksum : 8'h00;
    wire [7:0] c1 = t1_valid ? t1_checksum : 8'h00;
    wire [7:0] c2 = t2_valid ? t2_checksum : 8'h00;
    wire [7:0] c3 = t3_valid ? t3_checksum : 8'h00;
    wire [7:0] j0 = t0_valid ? t0_job_id  : 8'h00;
    wire [7:0] j1 = t1_valid ? t1_job_id  : 8'h00;
    wire [7:0] j2 = t2_valid ? t2_job_id  : 8'h00;
    wire [7:0] j3 = t3_valid ? t3_job_id  : 8'h00;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            agg_checksum  <= 8'b0;
            agg_job_id    <= 8'b0;
            attested_mask <= 4'b0;
        end else begin
            // FIX: single combined XOR-sum -> every simultaneous valid tile counts.
            agg_checksum <= agg_checksum ^ c0 ^ c1 ^ c2 ^ c3;
            agg_job_id   <= agg_job_id   ^ j0 ^ j1 ^ j2 ^ j3;
            // mask path was already correct (one register per bit)
            if (t0_valid) attested_mask[0] <= 1'b1;
            if (t1_valid) attested_mask[1] <= 1'b1;
            if (t2_valid) attested_mask[2] <= 1'b1;
            if (t3_valid) attested_mask[3] <= 1'b1;
        end
    end

    assign all_attested  = &attested_mask;
    assign multi_rcpt_ok = 1'b1;

endmodule
