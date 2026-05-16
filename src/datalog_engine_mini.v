// SPDX-License-Identifier: Apache-2.0
// datalog_engine_mini.v — CLARA Gap-3 forward-chain Datalog engine
// Mini variant: MAX_CLAUSES=16 (spec: gHashTag/t27/specs/ar/datalog_engine.t27)
// Target: gHashTag/tt-trinity-gamma  (~800 cells)
// R-SI-1: zero * operator — pure XOR/AND/OR logic
// Verilog-2005 only — no SystemVerilog syntax
//
// Horn clause format (21 bits per clause):
//   [20]    valid bit
//   [19:16] head atom index (4-bit → indexes into fact_mask[15:0])
//   [15:12] body atom 3 index (0xF = "no atom" / unused)
//   [11:8]  body atom 2 index
//   [7:4]   body atom 1 index
//   [3:0]   body atom 0 index
//
// Body atom index 0xF (4'b1111) means "don't-care / empty slot"
// (all 4 body atoms = 0xF → fact / unconditional rule)
//
// Forward chaining:
//   Each clock cycle advances one inference pass (all 16 clauses checked
//   in parallel via combinational logic). `converged` is asserted when
//   fact_mask does not change between two successive passes (fixed point).
//   Max 8 passes (iter_count max 4'hF for pass 1..8, then stays).
//
// Ports:
//   clk, rst_n
//   load_clause  — when high, latch clause_head/clause_body/clause_valid
//                  into clause_mem[clause_idx]
//   clause_idx   — [3:0] which slot to write
//   clause_head  — [3:0] head atom index
//   clause_body  — [15:0] four 4-bit body atom indices packed:
//                  [15:12]=body3, [11:8]=body2, [7:4]=body1, [3:0]=body0
//   clause_valid — validity bit for this clause
//   fact_load    — when high, set fact_mask[fact_idx] = 1
//   fact_idx     — [3:0] which fact atom to assert
//   start        — rising edge begins forward chaining
//   fact_mask    — [15:0] current derived fact set (output)
//   converged    — high when fixed point reached
//   iter_count   — [3:0] number of passes completed

`default_nettype none

module datalog_engine_mini (
    input  wire        clk,
    input  wire        rst_n,

    // Clause loading interface
    input  wire        load_clause,
    input  wire [3:0]  clause_idx,
    input  wire [3:0]  clause_head,
    input  wire [15:0] clause_body,
    input  wire        clause_valid,

    // Fact assertion interface
    input  wire        fact_load,
    input  wire [3:0]  fact_idx,

    // Control
    input  wire        start,

    // Outputs
    output reg  [15:0] fact_mask,
    output reg         converged,
    output reg  [3:0]  iter_count
);

    // -------------------------------------------------------------------
    // Clause memory: 16 slots × 21 bits {valid, head[3:0], body[15:0]}
    // -------------------------------------------------------------------
    reg [20:0] clause_mem [0:15];

    // -------------------------------------------------------------------
    // State machine: IDLE → RUNNING → DONE
    // -------------------------------------------------------------------
    localparam ST_IDLE    = 2'b00;
    localparam ST_RUNNING = 2'b01;
    localparam ST_DONE    = 2'b10;

    reg [1:0] state;
    reg [3:0] pass_count;

    // -------------------------------------------------------------------
    // Previous fact_mask (for convergence detection)
    // -------------------------------------------------------------------
    reg [15:0] prev_fact_mask;

    // -------------------------------------------------------------------
    // Combinational forward-chain logic: compute next_fact_mask
    // -------------------------------------------------------------------
    // For each clause i (if valid):
    //   Check body atoms b0..b3: if body atom index != 4'hF,
    //     fact_mask[body_atom_idx] must be set. If it IS 4'hF, treat as satisfied.
    //   If all 4 body checks pass → set next_fact_mask[head_idx]
    // -------------------------------------------------------------------

    reg [15:0] next_fact_mask;

    // Unpack per-clause fields
    wire        cv  [0:15]; // clause valid
    wire [3:0]  ch  [0:15]; // clause head
    wire [3:0]  cb0 [0:15]; // body atom 0
    wire [3:0]  cb1 [0:15]; // body atom 1
    wire [3:0]  cb2 [0:15]; // body atom 2
    wire [3:0]  cb3 [0:15]; // body atom 3

    // One-hot decode: clause fires → fires[i] high if clause i body satisfied
    wire [15:0] clause_fires;

    // Derive: head_set[h] = OR of clause_fires for all clauses with head==h
    // head_set[h] → sets bit h in next_fact_mask

    // We generate per-clause fire signals and per-head OR trees.
    // Body check helper: satisfied if index==4'hF OR fact_mask[idx] set.
    // Use a wire array for the 16×4 body checks.

    // --- Generate unpacked wires ---
    assign cv[0]  = clause_mem[0][20];   assign ch[0]  = clause_mem[0][19:16];
    assign cb3[0] = clause_mem[0][15:12]; assign cb2[0] = clause_mem[0][11:8];
    assign cb1[0] = clause_mem[0][7:4];   assign cb0[0] = clause_mem[0][3:0];

    assign cv[1]  = clause_mem[1][20];   assign ch[1]  = clause_mem[1][19:16];
    assign cb3[1] = clause_mem[1][15:12]; assign cb2[1] = clause_mem[1][11:8];
    assign cb1[1] = clause_mem[1][7:4];   assign cb0[1] = clause_mem[1][3:0];

    assign cv[2]  = clause_mem[2][20];   assign ch[2]  = clause_mem[2][19:16];
    assign cb3[2] = clause_mem[2][15:12]; assign cb2[2] = clause_mem[2][11:8];
    assign cb1[2] = clause_mem[2][7:4];   assign cb0[2] = clause_mem[2][3:0];

    assign cv[3]  = clause_mem[3][20];   assign ch[3]  = clause_mem[3][19:16];
    assign cb3[3] = clause_mem[3][15:12]; assign cb2[3] = clause_mem[3][11:8];
    assign cb1[3] = clause_mem[3][7:4];   assign cb0[3] = clause_mem[3][3:0];

    assign cv[4]  = clause_mem[4][20];   assign ch[4]  = clause_mem[4][19:16];
    assign cb3[4] = clause_mem[4][15:12]; assign cb2[4] = clause_mem[4][11:8];
    assign cb1[4] = clause_mem[4][7:4];   assign cb0[4] = clause_mem[4][3:0];

    assign cv[5]  = clause_mem[5][20];   assign ch[5]  = clause_mem[5][19:16];
    assign cb3[5] = clause_mem[5][15:12]; assign cb2[5] = clause_mem[5][11:8];
    assign cb1[5] = clause_mem[5][7:4];   assign cb0[5] = clause_mem[5][3:0];

    assign cv[6]  = clause_mem[6][20];   assign ch[6]  = clause_mem[6][19:16];
    assign cb3[6] = clause_mem[6][15:12]; assign cb2[6] = clause_mem[6][11:8];
    assign cb1[6] = clause_mem[6][7:4];   assign cb0[6] = clause_mem[6][3:0];

    assign cv[7]  = clause_mem[7][20];   assign ch[7]  = clause_mem[7][19:16];
    assign cb3[7] = clause_mem[7][15:12]; assign cb2[7] = clause_mem[7][11:8];
    assign cb1[7] = clause_mem[7][7:4];   assign cb0[7] = clause_mem[7][3:0];

    assign cv[8]  = clause_mem[8][20];   assign ch[8]  = clause_mem[8][19:16];
    assign cb3[8] = clause_mem[8][15:12]; assign cb2[8] = clause_mem[8][11:8];
    assign cb1[8] = clause_mem[8][7:4];   assign cb0[8] = clause_mem[8][3:0];

    assign cv[9]  = clause_mem[9][20];   assign ch[9]  = clause_mem[9][19:16];
    assign cb3[9] = clause_mem[9][15:12]; assign cb2[9] = clause_mem[9][11:8];
    assign cb1[9] = clause_mem[9][7:4];   assign cb0[9] = clause_mem[9][3:0];

    assign cv[10]  = clause_mem[10][20];   assign ch[10]  = clause_mem[10][19:16];
    assign cb3[10] = clause_mem[10][15:12]; assign cb2[10] = clause_mem[10][11:8];
    assign cb1[10] = clause_mem[10][7:4];   assign cb0[10] = clause_mem[10][3:0];

    assign cv[11]  = clause_mem[11][20];   assign ch[11]  = clause_mem[11][19:16];
    assign cb3[11] = clause_mem[11][15:12]; assign cb2[11] = clause_mem[11][11:8];
    assign cb1[11] = clause_mem[11][7:4];   assign cb0[11] = clause_mem[11][3:0];

    assign cv[12]  = clause_mem[12][20];   assign ch[12]  = clause_mem[12][19:16];
    assign cb3[12] = clause_mem[12][15:12]; assign cb2[12] = clause_mem[12][11:8];
    assign cb1[12] = clause_mem[12][7:4];   assign cb0[12] = clause_mem[12][3:0];

    assign cv[13]  = clause_mem[13][20];   assign ch[13]  = clause_mem[13][19:16];
    assign cb3[13] = clause_mem[13][15:12]; assign cb2[13] = clause_mem[13][11:8];
    assign cb1[13] = clause_mem[13][7:4];   assign cb0[13] = clause_mem[13][3:0];

    assign cv[14]  = clause_mem[14][20];   assign ch[14]  = clause_mem[14][19:16];
    assign cb3[14] = clause_mem[14][15:12]; assign cb2[14] = clause_mem[14][11:8];
    assign cb1[14] = clause_mem[14][7:4];   assign cb0[14] = clause_mem[14][3:0];

    assign cv[15]  = clause_mem[15][20];   assign ch[15]  = clause_mem[15][19:16];
    assign cb3[15] = clause_mem[15][15:12]; assign cb2[15] = clause_mem[15][11:8];
    assign cb1[15] = clause_mem[15][7:4];   assign cb0[15] = clause_mem[15][3:0];

    // Body-atom satisfaction: atom index 4'hF = don't-care (satisfied by default)
    // For index i, satisfied = (idx==4'hF) | fact_mask[idx]
    // We use a 16-bit one-hot decode of fact_mask for index lookup.
    // fact_sat(idx) = (idx==4'hF) | fact_mask[idx]
    //   = (&idx) | fact_mask[idx]   [because 4'hF = 4'b1111 → &idx == 1]

    // Helper: body_sat(idx) — fully combinational
    // &idx is 1 when idx=4'hF; fact_mask[idx] does index select

    // Per-clause body satisfied signals
    wire b0s  [0:15];
    wire b1s  [0:15];
    wire b2s  [0:15];
    wire b3s  [0:15];

    // Clause-level fire = valid & b0s & b1s & b2s & b3s
    // Inline for all 16 clauses (Verilog-2005 no generate with array)

    // We use a function-like macro pattern — manual expansion for 16 clauses.
    // body_sat: (&idx) selects 4'hF; then OR with fact_mask bit.
    // Since fact_mask is 16-bit and idx is 4-bit, index is fact_mask[idx].

    assign b0s[0]  = (&cb0[0])  | fact_mask[cb0[0]];
    assign b1s[0]  = (&cb1[0])  | fact_mask[cb1[0]];
    assign b2s[0]  = (&cb2[0])  | fact_mask[cb2[0]];
    assign b3s[0]  = (&cb3[0])  | fact_mask[cb3[0]];

    assign b0s[1]  = (&cb0[1])  | fact_mask[cb0[1]];
    assign b1s[1]  = (&cb1[1])  | fact_mask[cb1[1]];
    assign b2s[1]  = (&cb2[1])  | fact_mask[cb2[1]];
    assign b3s[1]  = (&cb3[1])  | fact_mask[cb3[1]];

    assign b0s[2]  = (&cb0[2])  | fact_mask[cb0[2]];
    assign b1s[2]  = (&cb1[2])  | fact_mask[cb1[2]];
    assign b2s[2]  = (&cb2[2])  | fact_mask[cb2[2]];
    assign b3s[2]  = (&cb3[2])  | fact_mask[cb3[2]];

    assign b0s[3]  = (&cb0[3])  | fact_mask[cb0[3]];
    assign b1s[3]  = (&cb1[3])  | fact_mask[cb1[3]];
    assign b2s[3]  = (&cb2[3])  | fact_mask[cb2[3]];
    assign b3s[3]  = (&cb3[3])  | fact_mask[cb3[3]];

    assign b0s[4]  = (&cb0[4])  | fact_mask[cb0[4]];
    assign b1s[4]  = (&cb1[4])  | fact_mask[cb1[4]];
    assign b2s[4]  = (&cb2[4])  | fact_mask[cb2[4]];
    assign b3s[4]  = (&cb3[4])  | fact_mask[cb3[4]];

    assign b0s[5]  = (&cb0[5])  | fact_mask[cb0[5]];
    assign b1s[5]  = (&cb1[5])  | fact_mask[cb1[5]];
    assign b2s[5]  = (&cb2[5])  | fact_mask[cb2[5]];
    assign b3s[5]  = (&cb3[5])  | fact_mask[cb3[5]];

    assign b0s[6]  = (&cb0[6])  | fact_mask[cb0[6]];
    assign b1s[6]  = (&cb1[6])  | fact_mask[cb1[6]];
    assign b2s[6]  = (&cb2[6])  | fact_mask[cb2[6]];
    assign b3s[6]  = (&cb3[6])  | fact_mask[cb3[6]];

    assign b0s[7]  = (&cb0[7])  | fact_mask[cb0[7]];
    assign b1s[7]  = (&cb1[7])  | fact_mask[cb1[7]];
    assign b2s[7]  = (&cb2[7])  | fact_mask[cb2[7]];
    assign b3s[7]  = (&cb3[7])  | fact_mask[cb3[7]];

    assign b0s[8]  = (&cb0[8])  | fact_mask[cb0[8]];
    assign b1s[8]  = (&cb1[8])  | fact_mask[cb1[8]];
    assign b2s[8]  = (&cb2[8])  | fact_mask[cb2[8]];
    assign b3s[8]  = (&cb3[8])  | fact_mask[cb3[8]];

    assign b0s[9]  = (&cb0[9])  | fact_mask[cb0[9]];
    assign b1s[9]  = (&cb1[9])  | fact_mask[cb1[9]];
    assign b2s[9]  = (&cb2[9])  | fact_mask[cb2[9]];
    assign b3s[9]  = (&cb3[9])  | fact_mask[cb3[9]];

    assign b0s[10] = (&cb0[10]) | fact_mask[cb0[10]];
    assign b1s[10] = (&cb1[10]) | fact_mask[cb1[10]];
    assign b2s[10] = (&cb2[10]) | fact_mask[cb2[10]];
    assign b3s[10] = (&cb3[10]) | fact_mask[cb3[10]];

    assign b0s[11] = (&cb0[11]) | fact_mask[cb0[11]];
    assign b1s[11] = (&cb1[11]) | fact_mask[cb1[11]];
    assign b2s[11] = (&cb2[11]) | fact_mask[cb2[11]];
    assign b3s[11] = (&cb3[11]) | fact_mask[cb3[11]];

    assign b0s[12] = (&cb0[12]) | fact_mask[cb0[12]];
    assign b1s[12] = (&cb1[12]) | fact_mask[cb1[12]];
    assign b2s[12] = (&cb2[12]) | fact_mask[cb2[12]];
    assign b3s[12] = (&cb3[12]) | fact_mask[cb3[12]];

    assign b0s[13] = (&cb0[13]) | fact_mask[cb0[13]];
    assign b1s[13] = (&cb1[13]) | fact_mask[cb1[13]];
    assign b2s[13] = (&cb2[13]) | fact_mask[cb2[13]];
    assign b3s[13] = (&cb3[13]) | fact_mask[cb3[13]];

    assign b0s[14] = (&cb0[14]) | fact_mask[cb0[14]];
    assign b1s[14] = (&cb1[14]) | fact_mask[cb1[14]];
    assign b2s[14] = (&cb2[14]) | fact_mask[cb2[14]];
    assign b3s[14] = (&cb3[14]) | fact_mask[cb3[14]];

    assign b0s[15] = (&cb0[15]) | fact_mask[cb0[15]];
    assign b1s[15] = (&cb1[15]) | fact_mask[cb1[15]];
    assign b2s[15] = (&cb2[15]) | fact_mask[cb2[15]];
    assign b3s[15] = (&cb3[15]) | fact_mask[cb3[15]];

    // clause_fires[i] = cv[i] & b0s[i] & b1s[i] & b2s[i] & b3s[i]
    assign clause_fires[0]  = cv[0]  & b0s[0]  & b1s[0]  & b2s[0]  & b3s[0];
    assign clause_fires[1]  = cv[1]  & b0s[1]  & b1s[1]  & b2s[1]  & b3s[1];
    assign clause_fires[2]  = cv[2]  & b0s[2]  & b1s[2]  & b2s[2]  & b3s[2];
    assign clause_fires[3]  = cv[3]  & b0s[3]  & b1s[3]  & b2s[3]  & b3s[3];
    assign clause_fires[4]  = cv[4]  & b0s[4]  & b1s[4]  & b2s[4]  & b3s[4];
    assign clause_fires[5]  = cv[5]  & b0s[5]  & b1s[5]  & b2s[5]  & b3s[5];
    assign clause_fires[6]  = cv[6]  & b0s[6]  & b1s[6]  & b2s[6]  & b3s[6];
    assign clause_fires[7]  = cv[7]  & b0s[7]  & b1s[7]  & b2s[7]  & b3s[7];
    assign clause_fires[8]  = cv[8]  & b0s[8]  & b1s[8]  & b2s[8]  & b3s[8];
    assign clause_fires[9]  = cv[9]  & b0s[9]  & b1s[9]  & b2s[9]  & b3s[9];
    assign clause_fires[10] = cv[10] & b0s[10] & b1s[10] & b2s[10] & b3s[10];
    assign clause_fires[11] = cv[11] & b0s[11] & b1s[11] & b2s[11] & b3s[11];
    assign clause_fires[12] = cv[12] & b0s[12] & b1s[12] & b2s[12] & b3s[12];
    assign clause_fires[13] = cv[13] & b0s[13] & b1s[13] & b2s[13] & b3s[13];
    assign clause_fires[14] = cv[14] & b0s[14] & b1s[14] & b2s[14] & b3s[14];
    assign clause_fires[15] = cv[15] & b0s[15] & b1s[15] & b2s[15] & b3s[15];

    // -------------------------------------------------------------------
    // Combinational: next_fact_mask generation
    // For each head bit h (0..15): set if any fired clause has ch[i]==h
    // Implement as 16 OR-of-AND trees (each bit is OR of all matching clauses).
    // We expand this as a for-loop in always @(*) — purely combinational.
    // -------------------------------------------------------------------

    integer i;
    always @(*) begin
        // Start from current fact_mask (monotonic — facts only accumulate)
        next_fact_mask = fact_mask;
        for (i = 0; i < 16; i = i + 1) begin
            if (clause_fires[i]) begin
                next_fact_mask[ch[i]] = 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------
    // Sequential: state machine + registers
    // -------------------------------------------------------------------
    integer j;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= ST_IDLE;
            fact_mask     <= 16'h0;
            prev_fact_mask <= 16'h0;
            converged     <= 1'b0;
            iter_count    <= 4'h0;
            pass_count    <= 4'h0;
            // Initialize clause memory
            for (j = 0; j < 16; j = j + 1)
                clause_mem[j] <= 21'h0;
        end else begin
            // Clause loading (can happen any time, including idle)
            if (load_clause) begin
                clause_mem[clause_idx] <= {clause_valid, clause_head, clause_body};
            end

            // Fact pre-loading (any time)
            if (fact_load) begin
                fact_mask[fact_idx] <= 1'b1;
            end

            case (state)
                ST_IDLE: begin
                    converged  <= 1'b0;
                    iter_count <= 4'h0;
                    pass_count <= 4'h0;
                    if (start) begin
                        prev_fact_mask <= fact_mask;
                        state <= ST_RUNNING;
                    end
                end

                ST_RUNNING: begin
                    // Apply one inference pass
                    fact_mask  <= next_fact_mask;
                    pass_count <= pass_count + 4'h1;
                    iter_count <= pass_count + 4'h1;

                    if (next_fact_mask == prev_fact_mask) begin
                        // Fixed point reached
                        converged <= 1'b1;
                        state     <= ST_DONE;
                    end else if (pass_count == 4'h7) begin
                        // Max 8 iterations — halt regardless
                        converged <= 1'b1;
                        state     <= ST_DONE;
                    end else begin
                        prev_fact_mask <= next_fact_mask;
                    end
                end

                ST_DONE: begin
                    converged <= 1'b1;
                    // Stay done until reset or new start
                    if (start) begin
                        // Allow re-trigger
                        converged      <= 1'b0;
                        prev_fact_mask <= fact_mask;
                        pass_count     <= 4'h0;
                        iter_count     <= 4'h0;
                        state          <= ST_RUNNING;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire
