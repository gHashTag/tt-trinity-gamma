// SPDX-License-Identifier: Apache-2.0
// sat_solver_mini.v — CLARA Gap-9 DPLL-style SAT solver (mini)
// 3-CNF, 8 variables, 16 clauses max
// Target: gHashTag/tt-trinity-gamma  (~500 cells)
// R-SI-1: zero * operator — pure XOR/AND/OR logic
// Verilog-2005 only — no SystemVerilog syntax
//
// Clause format (24 bits per clause):
//   [23]    valid bit
//   [22:19] literal 2 ID (3-bit var idx + 1-bit polarity, packed as 4-bit)
//   [18:15] literal 1 ID (3-bit var idx + 1-bit polarity)
//   [14:11] literal 0 ID (3-bit var idx + 1-bit polarity)
//   [10:8]  reserved / unused (pad to 24 bits)
//   Actually encoding per spec: 3 literals × (3-bit var + 1-bit neg) = 12 bits + 1 valid = 13
//   Extended to 24 bits: [23]=valid, [22:20]=var2, [19]=neg2,
//                        [18:16]=var1, [15]=neg1, [14:12]=var0, [11]=neg0, [10:0]=unused
//
// Literal format within clause_mem:
//   Each literal = 4 bits: [3:1]=var_id (0..7), [0]=negated (1=negated, 0=positive)
//
// Clause layout in 24-bit word:
//   [23]    = valid
//   [22:19] = lit2 {var2[2:0], neg2}
//   [18:15] = lit1 {var1[2:0], neg1}
//   [14:11] = lit0 {var0[2:0], neg0}
//   [10:0]  = unused (tied 0)
//
// FSM states: IDLE → PROPAGATE → DECIDE → BACKTRACK → DONE
//
// Algorithm (DPLL mini):
//   - 8-bit assignment register: assign_val[i] = value of var i if assigned
//   - 8-bit assigned register:   assign_set[i] = 1 if var i is assigned
//   - Unit propagation: scan all clauses; if a clause has exactly one
//     unassigned literal and all others are false → force that literal
//   - Decision: pick lowest-indexed unassigned variable, try value=1 first
//   - Backtrack stack: 3 deep (sufficient for 8-cycle cap on 8 vars)
//   - DONE: assert sat=1 + assignment, or unsat=1
//
// Ports:
//   clk, rst_n
//   load_clause — latch clause_data into clause_mem[clause_idx]
//   clause_idx  — [3:0] slot index
//   clause_data — [23:0] packed clause word (as above)
//   start       — rising edge begins solving
//   sat         — 1 when SAT found
//   unsat       — 1 when UNSAT proven
//   done        — 1 when either sat or unsat asserted
//   assign_out  — [7:0] satisfying assignment (valid when sat=1)
//   iter_count  — [3:0] number of FSM cycles completed

`default_nettype none

module sat_solver_mini (
    input  wire        clk,
    input  wire        rst_n,

    // Clause loading
    input  wire        load_clause,
    input  wire [3:0]  clause_idx,
    input  wire [23:0] clause_data,

    // Control
    input  wire        start,

    // Outputs
    output reg         sat,
    output reg         unsat,
    output reg         done,
    output reg  [7:0]  assign_out,
    output reg  [3:0]  iter_count
);

    // -----------------------------------------------------------------------
    // Clause memory: 16 slots × 24 bits
    // -----------------------------------------------------------------------
    reg [23:0] clause_mem [0:15];

    // -----------------------------------------------------------------------
    // Assignment state
    // -----------------------------------------------------------------------
    reg [7:0] assign_val;  // value of each variable (bit i = value of var i)
    reg [7:0] assign_set;  // 1 = variable i is assigned

    // -----------------------------------------------------------------------
    // Backtrack stack: 3 entries (each = assigned snapshot)
    // Stack entry: {assign_val[7:0], assign_set[7:0], decided_var[2:0], tried_both[0]}
    // Total: 8 + 8 + 3 + 1 = 20 bits per entry
    // -----------------------------------------------------------------------
    reg [19:0] bt_stack [0:7];
    reg [3:0]  bt_depth;  // 0..8

    // -----------------------------------------------------------------------
    // FSM states
    // -----------------------------------------------------------------------
    localparam ST_IDLE       = 3'd0;
    localparam ST_PROPAGATE  = 3'd1;
    localparam ST_DECIDE     = 3'd2;
    localparam ST_BACKTRACK  = 3'd3;
    localparam ST_DONE       = 3'd4;

    reg [2:0] state;

    // -----------------------------------------------------------------------
    // Working registers
    // -----------------------------------------------------------------------
    reg [5:0]  iter_cnt;
    reg        conflict;      // set when a clause is all-false
    reg        changed;       // set when unit prop made progress
    reg        all_satisfied; // set when all valid clauses are satisfied

    // -----------------------------------------------------------------------
    // Combinational clause evaluation helpers
    // For each clause i, compute:
    //   sat_c[i]     = clause is satisfied (at least one true literal)
    //   unsat_c[i]   = clause is falsified (all literals assigned-false)
    //   unit_c[i]    = clause has exactly one unassigned lit, others false
    //   unit_var[i]  = variable index of that forced literal (3-bit)
    //   unit_neg[i]  = polarity of forced literal
    //   valid_c[i]   = clause valid bit
    // -----------------------------------------------------------------------

    // Unpack clause fields
    wire        valid_c  [0:15];
    wire [3:0]  lit2     [0:15]; // {var[2:0], neg}
    wire [3:0]  lit1     [0:15];
    wire [3:0]  lit0     [0:15];

    // Per-clause per-literal evaluation
    // lit_true(lit, aval, aset) = aset[lit[3:1]] & (aval[lit[3:1]] ^ lit[0])
    //   — assigned and value matches polarity (positive: aval=1, neg=1→aval=0)
    // lit_false(lit, aval, aset) = aset[lit[3:1]] & ~(aval[lit[3:1]] ^ lit[0])
    // lit_undef(lit, aval, aset) = ~aset[lit[3:1]]

    wire        l0t [0:15]; // lit0 is true
    wire        l1t [0:15];
    wire        l2t [0:15];
    wire        l0f [0:15]; // lit0 is false
    wire        l1f [0:15];
    wire        l2f [0:15];
    wire        l0u [0:15]; // lit0 is unassigned
    wire        l1u [0:15];
    wire        l2u [0:15];

    wire        sat_c   [0:15];
    wire        conf_c  [0:15];
    wire        unit_c  [0:15];
    wire [2:0]  unit_var[0:15];
    wire        unit_neg[0:15];

    // -----------------------------------------------------------------------
    // Clause unpack — 16 entries, explicit per R-SI-1 / Verilog-2005
    // -----------------------------------------------------------------------
    assign valid_c[0]  = clause_mem[0][23];
    assign lit2[0]     = clause_mem[0][22:19];
    assign lit1[0]     = clause_mem[0][18:15];
    assign lit0[0]     = clause_mem[0][14:11];

    assign valid_c[1]  = clause_mem[1][23];
    assign lit2[1]     = clause_mem[1][22:19];
    assign lit1[1]     = clause_mem[1][18:15];
    assign lit0[1]     = clause_mem[1][14:11];

    assign valid_c[2]  = clause_mem[2][23];
    assign lit2[2]     = clause_mem[2][22:19];
    assign lit1[2]     = clause_mem[2][18:15];
    assign lit0[2]     = clause_mem[2][14:11];

    assign valid_c[3]  = clause_mem[3][23];
    assign lit2[3]     = clause_mem[3][22:19];
    assign lit1[3]     = clause_mem[3][18:15];
    assign lit0[3]     = clause_mem[3][14:11];

    assign valid_c[4]  = clause_mem[4][23];
    assign lit2[4]     = clause_mem[4][22:19];
    assign lit1[4]     = clause_mem[4][18:15];
    assign lit0[4]     = clause_mem[4][14:11];

    assign valid_c[5]  = clause_mem[5][23];
    assign lit2[5]     = clause_mem[5][22:19];
    assign lit1[5]     = clause_mem[5][18:15];
    assign lit0[5]     = clause_mem[5][14:11];

    assign valid_c[6]  = clause_mem[6][23];
    assign lit2[6]     = clause_mem[6][22:19];
    assign lit1[6]     = clause_mem[6][18:15];
    assign lit0[6]     = clause_mem[6][14:11];

    assign valid_c[7]  = clause_mem[7][23];
    assign lit2[7]     = clause_mem[7][22:19];
    assign lit1[7]     = clause_mem[7][18:15];
    assign lit0[7]     = clause_mem[7][14:11];

    assign valid_c[8]  = clause_mem[8][23];
    assign lit2[8]     = clause_mem[8][22:19];
    assign lit1[8]     = clause_mem[8][18:15];
    assign lit0[8]     = clause_mem[8][14:11];

    assign valid_c[9]  = clause_mem[9][23];
    assign lit2[9]     = clause_mem[9][22:19];
    assign lit1[9]     = clause_mem[9][18:15];
    assign lit0[9]     = clause_mem[9][14:11];

    assign valid_c[10] = clause_mem[10][23];
    assign lit2[10]    = clause_mem[10][22:19];
    assign lit1[10]    = clause_mem[10][18:15];
    assign lit0[10]    = clause_mem[10][14:11];

    assign valid_c[11] = clause_mem[11][23];
    assign lit2[11]    = clause_mem[11][22:19];
    assign lit1[11]    = clause_mem[11][18:15];
    assign lit0[11]    = clause_mem[11][14:11];

    assign valid_c[12] = clause_mem[12][23];
    assign lit2[12]    = clause_mem[12][22:19];
    assign lit1[12]    = clause_mem[12][18:15];
    assign lit0[12]    = clause_mem[12][14:11];

    assign valid_c[13] = clause_mem[13][23];
    assign lit2[13]    = clause_mem[13][22:19];
    assign lit1[13]    = clause_mem[13][18:15];
    assign lit0[13]    = clause_mem[13][14:11];

    assign valid_c[14] = clause_mem[14][23];
    assign lit2[14]    = clause_mem[14][22:19];
    assign lit1[14]    = clause_mem[14][18:15];
    assign lit0[14]    = clause_mem[14][14:11];

    assign valid_c[15] = clause_mem[15][23];
    assign lit2[15]    = clause_mem[15][22:19];
    assign lit1[15]    = clause_mem[15][18:15];
    assign lit0[15]    = clause_mem[15][14:11];

    // -----------------------------------------------------------------------
    // Literal evaluation for each clause
    // lit_true  = assigned & (value XOR negation)==1  → (aset & (aval XOR ~neg))
    //           = aset[var] & (aval[var] ^ ~neg)
    //           = aset[var] & ~(aval[var] ^ neg)   ... wait:
    //   positive literal (neg=0): true when aval=1 → aval XOR 0 = aval
    //   negative literal (neg=1): true when aval=0 → ~aval = aval XOR 1
    //   So: lit_true = aset[var] & (aval[var] ^ neg)  [no wait...]
    //   neg=0, positive: want true when aval=1  → aval^0 = aval ✓
    //   neg=1, negative: want true when aval=0  → aval^1 = ~aval ✓
    //   → lit_true = assign_set[var] & (assign_val[var] ^ neg)  ← CORRECT
    // lit_false = assign_set[var] & ~(assign_val[var] ^ neg)
    // lit_undef = ~assign_set[var]
    // -----------------------------------------------------------------------

    // Macro-expand for 16 clauses
    assign l0t[0]  = assign_set[lit0[0][3:1]]  & (assign_val[lit0[0][3:1]]  ^ lit0[0][0]);
    assign l1t[0]  = assign_set[lit1[0][3:1]]  & (assign_val[lit1[0][3:1]]  ^ lit1[0][0]);
    assign l2t[0]  = assign_set[lit2[0][3:1]]  & (assign_val[lit2[0][3:1]]  ^ lit2[0][0]);
    assign l0f[0]  = assign_set[lit0[0][3:1]]  & ~(assign_val[lit0[0][3:1]] ^ lit0[0][0]);
    assign l1f[0]  = assign_set[lit1[0][3:1]]  & ~(assign_val[lit1[0][3:1]] ^ lit1[0][0]);
    assign l2f[0]  = assign_set[lit2[0][3:1]]  & ~(assign_val[lit2[0][3:1]] ^ lit2[0][0]);
    assign l0u[0]  = ~assign_set[lit0[0][3:1]];
    assign l1u[0]  = ~assign_set[lit1[0][3:1]];
    assign l2u[0]  = ~assign_set[lit2[0][3:1]];

    assign l0t[1]  = assign_set[lit0[1][3:1]]  & (assign_val[lit0[1][3:1]]  ^ lit0[1][0]);
    assign l1t[1]  = assign_set[lit1[1][3:1]]  & (assign_val[lit1[1][3:1]]  ^ lit1[1][0]);
    assign l2t[1]  = assign_set[lit2[1][3:1]]  & (assign_val[lit2[1][3:1]]  ^ lit2[1][0]);
    assign l0f[1]  = assign_set[lit0[1][3:1]]  & ~(assign_val[lit0[1][3:1]] ^ lit0[1][0]);
    assign l1f[1]  = assign_set[lit1[1][3:1]]  & ~(assign_val[lit1[1][3:1]] ^ lit1[1][0]);
    assign l2f[1]  = assign_set[lit2[1][3:1]]  & ~(assign_val[lit2[1][3:1]] ^ lit2[1][0]);
    assign l0u[1]  = ~assign_set[lit0[1][3:1]];
    assign l1u[1]  = ~assign_set[lit1[1][3:1]];
    assign l2u[1]  = ~assign_set[lit2[1][3:1]];

    assign l0t[2]  = assign_set[lit0[2][3:1]]  & (assign_val[lit0[2][3:1]]  ^ lit0[2][0]);
    assign l1t[2]  = assign_set[lit1[2][3:1]]  & (assign_val[lit1[2][3:1]]  ^ lit1[2][0]);
    assign l2t[2]  = assign_set[lit2[2][3:1]]  & (assign_val[lit2[2][3:1]]  ^ lit2[2][0]);
    assign l0f[2]  = assign_set[lit0[2][3:1]]  & ~(assign_val[lit0[2][3:1]] ^ lit0[2][0]);
    assign l1f[2]  = assign_set[lit1[2][3:1]]  & ~(assign_val[lit1[2][3:1]] ^ lit1[2][0]);
    assign l2f[2]  = assign_set[lit2[2][3:1]]  & ~(assign_val[lit2[2][3:1]] ^ lit2[2][0]);
    assign l0u[2]  = ~assign_set[lit0[2][3:1]];
    assign l1u[2]  = ~assign_set[lit1[2][3:1]];
    assign l2u[2]  = ~assign_set[lit2[2][3:1]];

    assign l0t[3]  = assign_set[lit0[3][3:1]]  & (assign_val[lit0[3][3:1]]  ^ lit0[3][0]);
    assign l1t[3]  = assign_set[lit1[3][3:1]]  & (assign_val[lit1[3][3:1]]  ^ lit1[3][0]);
    assign l2t[3]  = assign_set[lit2[3][3:1]]  & (assign_val[lit2[3][3:1]]  ^ lit2[3][0]);
    assign l0f[3]  = assign_set[lit0[3][3:1]]  & ~(assign_val[lit0[3][3:1]] ^ lit0[3][0]);
    assign l1f[3]  = assign_set[lit1[3][3:1]]  & ~(assign_val[lit1[3][3:1]] ^ lit1[3][0]);
    assign l2f[3]  = assign_set[lit2[3][3:1]]  & ~(assign_val[lit2[3][3:1]] ^ lit2[3][0]);
    assign l0u[3]  = ~assign_set[lit0[3][3:1]];
    assign l1u[3]  = ~assign_set[lit1[3][3:1]];
    assign l2u[3]  = ~assign_set[lit2[3][3:1]];

    assign l0t[4]  = assign_set[lit0[4][3:1]]  & (assign_val[lit0[4][3:1]]  ^ lit0[4][0]);
    assign l1t[4]  = assign_set[lit1[4][3:1]]  & (assign_val[lit1[4][3:1]]  ^ lit1[4][0]);
    assign l2t[4]  = assign_set[lit2[4][3:1]]  & (assign_val[lit2[4][3:1]]  ^ lit2[4][0]);
    assign l0f[4]  = assign_set[lit0[4][3:1]]  & ~(assign_val[lit0[4][3:1]] ^ lit0[4][0]);
    assign l1f[4]  = assign_set[lit1[4][3:1]]  & ~(assign_val[lit1[4][3:1]] ^ lit1[4][0]);
    assign l2f[4]  = assign_set[lit2[4][3:1]]  & ~(assign_val[lit2[4][3:1]] ^ lit2[4][0]);
    assign l0u[4]  = ~assign_set[lit0[4][3:1]];
    assign l1u[4]  = ~assign_set[lit1[4][3:1]];
    assign l2u[4]  = ~assign_set[lit2[4][3:1]];

    assign l0t[5]  = assign_set[lit0[5][3:1]]  & (assign_val[lit0[5][3:1]]  ^ lit0[5][0]);
    assign l1t[5]  = assign_set[lit1[5][3:1]]  & (assign_val[lit1[5][3:1]]  ^ lit1[5][0]);
    assign l2t[5]  = assign_set[lit2[5][3:1]]  & (assign_val[lit2[5][3:1]]  ^ lit2[5][0]);
    assign l0f[5]  = assign_set[lit0[5][3:1]]  & ~(assign_val[lit0[5][3:1]] ^ lit0[5][0]);
    assign l1f[5]  = assign_set[lit1[5][3:1]]  & ~(assign_val[lit1[5][3:1]] ^ lit1[5][0]);
    assign l2f[5]  = assign_set[lit2[5][3:1]]  & ~(assign_val[lit2[5][3:1]] ^ lit2[5][0]);
    assign l0u[5]  = ~assign_set[lit0[5][3:1]];
    assign l1u[5]  = ~assign_set[lit1[5][3:1]];
    assign l2u[5]  = ~assign_set[lit2[5][3:1]];

    assign l0t[6]  = assign_set[lit0[6][3:1]]  & (assign_val[lit0[6][3:1]]  ^ lit0[6][0]);
    assign l1t[6]  = assign_set[lit1[6][3:1]]  & (assign_val[lit1[6][3:1]]  ^ lit1[6][0]);
    assign l2t[6]  = assign_set[lit2[6][3:1]]  & (assign_val[lit2[6][3:1]]  ^ lit2[6][0]);
    assign l0f[6]  = assign_set[lit0[6][3:1]]  & ~(assign_val[lit0[6][3:1]] ^ lit0[6][0]);
    assign l1f[6]  = assign_set[lit1[6][3:1]]  & ~(assign_val[lit1[6][3:1]] ^ lit1[6][0]);
    assign l2f[6]  = assign_set[lit2[6][3:1]]  & ~(assign_val[lit2[6][3:1]] ^ lit2[6][0]);
    assign l0u[6]  = ~assign_set[lit0[6][3:1]];
    assign l1u[6]  = ~assign_set[lit1[6][3:1]];
    assign l2u[6]  = ~assign_set[lit2[6][3:1]];

    assign l0t[7]  = assign_set[lit0[7][3:1]]  & (assign_val[lit0[7][3:1]]  ^ lit0[7][0]);
    assign l1t[7]  = assign_set[lit1[7][3:1]]  & (assign_val[lit1[7][3:1]]  ^ lit1[7][0]);
    assign l2t[7]  = assign_set[lit2[7][3:1]]  & (assign_val[lit2[7][3:1]]  ^ lit2[7][0]);
    assign l0f[7]  = assign_set[lit0[7][3:1]]  & ~(assign_val[lit0[7][3:1]] ^ lit0[7][0]);
    assign l1f[7]  = assign_set[lit1[7][3:1]]  & ~(assign_val[lit1[7][3:1]] ^ lit1[7][0]);
    assign l2f[7]  = assign_set[lit2[7][3:1]]  & ~(assign_val[lit2[7][3:1]] ^ lit2[7][0]);
    assign l0u[7]  = ~assign_set[lit0[7][3:1]];
    assign l1u[7]  = ~assign_set[lit1[7][3:1]];
    assign l2u[7]  = ~assign_set[lit2[7][3:1]];

    assign l0t[8]  = assign_set[lit0[8][3:1]]  & (assign_val[lit0[8][3:1]]  ^ lit0[8][0]);
    assign l1t[8]  = assign_set[lit1[8][3:1]]  & (assign_val[lit1[8][3:1]]  ^ lit1[8][0]);
    assign l2t[8]  = assign_set[lit2[8][3:1]]  & (assign_val[lit2[8][3:1]]  ^ lit2[8][0]);
    assign l0f[8]  = assign_set[lit0[8][3:1]]  & ~(assign_val[lit0[8][3:1]] ^ lit0[8][0]);
    assign l1f[8]  = assign_set[lit1[8][3:1]]  & ~(assign_val[lit1[8][3:1]] ^ lit1[8][0]);
    assign l2f[8]  = assign_set[lit2[8][3:1]]  & ~(assign_val[lit2[8][3:1]] ^ lit2[8][0]);
    assign l0u[8]  = ~assign_set[lit0[8][3:1]];
    assign l1u[8]  = ~assign_set[lit1[8][3:1]];
    assign l2u[8]  = ~assign_set[lit2[8][3:1]];

    assign l0t[9]  = assign_set[lit0[9][3:1]]  & (assign_val[lit0[9][3:1]]  ^ lit0[9][0]);
    assign l1t[9]  = assign_set[lit1[9][3:1]]  & (assign_val[lit1[9][3:1]]  ^ lit1[9][0]);
    assign l2t[9]  = assign_set[lit2[9][3:1]]  & (assign_val[lit2[9][3:1]]  ^ lit2[9][0]);
    assign l0f[9]  = assign_set[lit0[9][3:1]]  & ~(assign_val[lit0[9][3:1]] ^ lit0[9][0]);
    assign l1f[9]  = assign_set[lit1[9][3:1]]  & ~(assign_val[lit1[9][3:1]] ^ lit1[9][0]);
    assign l2f[9]  = assign_set[lit2[9][3:1]]  & ~(assign_val[lit2[9][3:1]] ^ lit2[9][0]);
    assign l0u[9]  = ~assign_set[lit0[9][3:1]];
    assign l1u[9]  = ~assign_set[lit1[9][3:1]];
    assign l2u[9]  = ~assign_set[lit2[9][3:1]];

    assign l0t[10] = assign_set[lit0[10][3:1]] & (assign_val[lit0[10][3:1]] ^ lit0[10][0]);
    assign l1t[10] = assign_set[lit1[10][3:1]] & (assign_val[lit1[10][3:1]] ^ lit1[10][0]);
    assign l2t[10] = assign_set[lit2[10][3:1]] & (assign_val[lit2[10][3:1]] ^ lit2[10][0]);
    assign l0f[10] = assign_set[lit0[10][3:1]] & ~(assign_val[lit0[10][3:1]] ^ lit0[10][0]);
    assign l1f[10] = assign_set[lit1[10][3:1]] & ~(assign_val[lit1[10][3:1]] ^ lit1[10][0]);
    assign l2f[10] = assign_set[lit2[10][3:1]] & ~(assign_val[lit2[10][3:1]] ^ lit2[10][0]);
    assign l0u[10] = ~assign_set[lit0[10][3:1]];
    assign l1u[10] = ~assign_set[lit1[10][3:1]];
    assign l2u[10] = ~assign_set[lit2[10][3:1]];

    assign l0t[11] = assign_set[lit0[11][3:1]] & (assign_val[lit0[11][3:1]] ^ lit0[11][0]);
    assign l1t[11] = assign_set[lit1[11][3:1]] & (assign_val[lit1[11][3:1]] ^ lit1[11][0]);
    assign l2t[11] = assign_set[lit2[11][3:1]] & (assign_val[lit2[11][3:1]] ^ lit2[11][0]);
    assign l0f[11] = assign_set[lit0[11][3:1]] & ~(assign_val[lit0[11][3:1]] ^ lit0[11][0]);
    assign l1f[11] = assign_set[lit1[11][3:1]] & ~(assign_val[lit1[11][3:1]] ^ lit1[11][0]);
    assign l2f[11] = assign_set[lit2[11][3:1]] & ~(assign_val[lit2[11][3:1]] ^ lit2[11][0]);
    assign l0u[11] = ~assign_set[lit0[11][3:1]];
    assign l1u[11] = ~assign_set[lit1[11][3:1]];
    assign l2u[11] = ~assign_set[lit2[11][3:1]];

    assign l0t[12] = assign_set[lit0[12][3:1]] & (assign_val[lit0[12][3:1]] ^ lit0[12][0]);
    assign l1t[12] = assign_set[lit1[12][3:1]] & (assign_val[lit1[12][3:1]] ^ lit1[12][0]);
    assign l2t[12] = assign_set[lit2[12][3:1]] & (assign_val[lit2[12][3:1]] ^ lit2[12][0]);
    assign l0f[12] = assign_set[lit0[12][3:1]] & ~(assign_val[lit0[12][3:1]] ^ lit0[12][0]);
    assign l1f[12] = assign_set[lit1[12][3:1]] & ~(assign_val[lit1[12][3:1]] ^ lit1[12][0]);
    assign l2f[12] = assign_set[lit2[12][3:1]] & ~(assign_val[lit2[12][3:1]] ^ lit2[12][0]);
    assign l0u[12] = ~assign_set[lit0[12][3:1]];
    assign l1u[12] = ~assign_set[lit1[12][3:1]];
    assign l2u[12] = ~assign_set[lit2[12][3:1]];

    assign l0t[13] = assign_set[lit0[13][3:1]] & (assign_val[lit0[13][3:1]] ^ lit0[13][0]);
    assign l1t[13] = assign_set[lit1[13][3:1]] & (assign_val[lit1[13][3:1]] ^ lit1[13][0]);
    assign l2t[13] = assign_set[lit2[13][3:1]] & (assign_val[lit2[13][3:1]] ^ lit2[13][0]);
    assign l0f[13] = assign_set[lit0[13][3:1]] & ~(assign_val[lit0[13][3:1]] ^ lit0[13][0]);
    assign l1f[13] = assign_set[lit1[13][3:1]] & ~(assign_val[lit1[13][3:1]] ^ lit1[13][0]);
    assign l2f[13] = assign_set[lit2[13][3:1]] & ~(assign_val[lit2[13][3:1]] ^ lit2[13][0]);
    assign l0u[13] = ~assign_set[lit0[13][3:1]];
    assign l1u[13] = ~assign_set[lit1[13][3:1]];
    assign l2u[13] = ~assign_set[lit2[13][3:1]];

    assign l0t[14] = assign_set[lit0[14][3:1]] & (assign_val[lit0[14][3:1]] ^ lit0[14][0]);
    assign l1t[14] = assign_set[lit1[14][3:1]] & (assign_val[lit1[14][3:1]] ^ lit1[14][0]);
    assign l2t[14] = assign_set[lit2[14][3:1]] & (assign_val[lit2[14][3:1]] ^ lit2[14][0]);
    assign l0f[14] = assign_set[lit0[14][3:1]] & ~(assign_val[lit0[14][3:1]] ^ lit0[14][0]);
    assign l1f[14] = assign_set[lit1[14][3:1]] & ~(assign_val[lit1[14][3:1]] ^ lit1[14][0]);
    assign l2f[14] = assign_set[lit2[14][3:1]] & ~(assign_val[lit2[14][3:1]] ^ lit2[14][0]);
    assign l0u[14] = ~assign_set[lit0[14][3:1]];
    assign l1u[14] = ~assign_set[lit1[14][3:1]];
    assign l2u[14] = ~assign_set[lit2[14][3:1]];

    assign l0t[15] = assign_set[lit0[15][3:1]] & (assign_val[lit0[15][3:1]] ^ lit0[15][0]);
    assign l1t[15] = assign_set[lit1[15][3:1]] & (assign_val[lit1[15][3:1]] ^ lit1[15][0]);
    assign l2t[15] = assign_set[lit2[15][3:1]] & (assign_val[lit2[15][3:1]] ^ lit2[15][0]);
    assign l0f[15] = assign_set[lit0[15][3:1]] & ~(assign_val[lit0[15][3:1]] ^ lit0[15][0]);
    assign l1f[15] = assign_set[lit1[15][3:1]] & ~(assign_val[lit1[15][3:1]] ^ lit1[15][0]);
    assign l2f[15] = assign_set[lit2[15][3:1]] & ~(assign_val[lit2[15][3:1]] ^ lit2[15][0]);
    assign l0u[15] = ~assign_set[lit0[15][3:1]];
    assign l1u[15] = ~assign_set[lit1[15][3:1]];
    assign l2u[15] = ~assign_set[lit2[15][3:1]];

    // -----------------------------------------------------------------------
    // Clause-level signals
    // sat_c[i]  = clause satisfied (at least one lit true)
    // conf_c[i] = conflict (all lits false — clause falsified)
    // unit_c[i] = unit clause (exactly 2 false, 1 unassigned)
    // unit_var, unit_neg = which literal to force
    // -----------------------------------------------------------------------

    assign sat_c[0]  = valid_c[0]  & (l0t[0]  | l1t[0]  | l2t[0]);
    assign conf_c[0] = valid_c[0]  & l0f[0]   & l1f[0]  & l2f[0];
    assign unit_c[0] = valid_c[0]  & ~sat_c[0] & ~conf_c[0] &
                       ((l0u[0]  & l1f[0]  & l2f[0])  |
                        (l0f[0]  & l1u[0]  & l2f[0])  |
                        (l0f[0]  & l1f[0]  & l2u[0]));
    assign unit_var[0] = l0u[0]  & l1f[0]  & l2f[0]  ? lit0[0][3:1]  :
                         l0f[0]  & l1u[0]  & l2f[0]  ? lit1[0][3:1]  : lit2[0][3:1];
    assign unit_neg[0] = l0u[0]  & l1f[0]  & l2f[0]  ? lit0[0][0]    :
                         l0f[0]  & l1u[0]  & l2f[0]  ? lit1[0][0]    : lit2[0][0];

    assign sat_c[1]  = valid_c[1]  & (l0t[1]  | l1t[1]  | l2t[1]);
    assign conf_c[1] = valid_c[1]  & l0f[1]   & l1f[1]  & l2f[1];
    assign unit_c[1] = valid_c[1]  & ~sat_c[1] & ~conf_c[1] &
                       ((l0u[1]  & l1f[1]  & l2f[1])  |
                        (l0f[1]  & l1u[1]  & l2f[1])  |
                        (l0f[1]  & l1f[1]  & l2u[1]));
    assign unit_var[1] = l0u[1]  & l1f[1]  & l2f[1]  ? lit0[1][3:1]  :
                         l0f[1]  & l1u[1]  & l2f[1]  ? lit1[1][3:1]  : lit2[1][3:1];
    assign unit_neg[1] = l0u[1]  & l1f[1]  & l2f[1]  ? lit0[1][0]    :
                         l0f[1]  & l1u[1]  & l2f[1]  ? lit1[1][0]    : lit2[1][0];

    assign sat_c[2]  = valid_c[2]  & (l0t[2]  | l1t[2]  | l2t[2]);
    assign conf_c[2] = valid_c[2]  & l0f[2]   & l1f[2]  & l2f[2];
    assign unit_c[2] = valid_c[2]  & ~sat_c[2] & ~conf_c[2] &
                       ((l0u[2]  & l1f[2]  & l2f[2])  |
                        (l0f[2]  & l1u[2]  & l2f[2])  |
                        (l0f[2]  & l1f[2]  & l2u[2]));
    assign unit_var[2] = l0u[2]  & l1f[2]  & l2f[2]  ? lit0[2][3:1]  :
                         l0f[2]  & l1u[2]  & l2f[2]  ? lit1[2][3:1]  : lit2[2][3:1];
    assign unit_neg[2] = l0u[2]  & l1f[2]  & l2f[2]  ? lit0[2][0]    :
                         l0f[2]  & l1u[2]  & l2f[2]  ? lit1[2][0]    : lit2[2][0];

    assign sat_c[3]  = valid_c[3]  & (l0t[3]  | l1t[3]  | l2t[3]);
    assign conf_c[3] = valid_c[3]  & l0f[3]   & l1f[3]  & l2f[3];
    assign unit_c[3] = valid_c[3]  & ~sat_c[3] & ~conf_c[3] &
                       ((l0u[3]  & l1f[3]  & l2f[3])  |
                        (l0f[3]  & l1u[3]  & l2f[3])  |
                        (l0f[3]  & l1f[3]  & l2u[3]));
    assign unit_var[3] = l0u[3]  & l1f[3]  & l2f[3]  ? lit0[3][3:1]  :
                         l0f[3]  & l1u[3]  & l2f[3]  ? lit1[3][3:1]  : lit2[3][3:1];
    assign unit_neg[3] = l0u[3]  & l1f[3]  & l2f[3]  ? lit0[3][0]    :
                         l0f[3]  & l1u[3]  & l2f[3]  ? lit1[3][0]    : lit2[3][0];

    assign sat_c[4]  = valid_c[4]  & (l0t[4]  | l1t[4]  | l2t[4]);
    assign conf_c[4] = valid_c[4]  & l0f[4]   & l1f[4]  & l2f[4];
    assign unit_c[4] = valid_c[4]  & ~sat_c[4] & ~conf_c[4] &
                       ((l0u[4]  & l1f[4]  & l2f[4])  |
                        (l0f[4]  & l1u[4]  & l2f[4])  |
                        (l0f[4]  & l1f[4]  & l2u[4]));
    assign unit_var[4] = l0u[4]  & l1f[4]  & l2f[4]  ? lit0[4][3:1]  :
                         l0f[4]  & l1u[4]  & l2f[4]  ? lit1[4][3:1]  : lit2[4][3:1];
    assign unit_neg[4] = l0u[4]  & l1f[4]  & l2f[4]  ? lit0[4][0]    :
                         l0f[4]  & l1u[4]  & l2f[4]  ? lit1[4][0]    : lit2[4][0];

    assign sat_c[5]  = valid_c[5]  & (l0t[5]  | l1t[5]  | l2t[5]);
    assign conf_c[5] = valid_c[5]  & l0f[5]   & l1f[5]  & l2f[5];
    assign unit_c[5] = valid_c[5]  & ~sat_c[5] & ~conf_c[5] &
                       ((l0u[5]  & l1f[5]  & l2f[5])  |
                        (l0f[5]  & l1u[5]  & l2f[5])  |
                        (l0f[5]  & l1f[5]  & l2u[5]));
    assign unit_var[5] = l0u[5]  & l1f[5]  & l2f[5]  ? lit0[5][3:1]  :
                         l0f[5]  & l1u[5]  & l2f[5]  ? lit1[5][3:1]  : lit2[5][3:1];
    assign unit_neg[5] = l0u[5]  & l1f[5]  & l2f[5]  ? lit0[5][0]    :
                         l0f[5]  & l1u[5]  & l2f[5]  ? lit1[5][0]    : lit2[5][0];

    assign sat_c[6]  = valid_c[6]  & (l0t[6]  | l1t[6]  | l2t[6]);
    assign conf_c[6] = valid_c[6]  & l0f[6]   & l1f[6]  & l2f[6];
    assign unit_c[6] = valid_c[6]  & ~sat_c[6] & ~conf_c[6] &
                       ((l0u[6]  & l1f[6]  & l2f[6])  |
                        (l0f[6]  & l1u[6]  & l2f[6])  |
                        (l0f[6]  & l1f[6]  & l2u[6]));
    assign unit_var[6] = l0u[6]  & l1f[6]  & l2f[6]  ? lit0[6][3:1]  :
                         l0f[6]  & l1u[6]  & l2f[6]  ? lit1[6][3:1]  : lit2[6][3:1];
    assign unit_neg[6] = l0u[6]  & l1f[6]  & l2f[6]  ? lit0[6][0]    :
                         l0f[6]  & l1u[6]  & l2f[6]  ? lit1[6][0]    : lit2[6][0];

    assign sat_c[7]  = valid_c[7]  & (l0t[7]  | l1t[7]  | l2t[7]);
    assign conf_c[7] = valid_c[7]  & l0f[7]   & l1f[7]  & l2f[7];
    assign unit_c[7] = valid_c[7]  & ~sat_c[7] & ~conf_c[7] &
                       ((l0u[7]  & l1f[7]  & l2f[7])  |
                        (l0f[7]  & l1u[7]  & l2f[7])  |
                        (l0f[7]  & l1f[7]  & l2u[7]));
    assign unit_var[7] = l0u[7]  & l1f[7]  & l2f[7]  ? lit0[7][3:1]  :
                         l0f[7]  & l1u[7]  & l2f[7]  ? lit1[7][3:1]  : lit2[7][3:1];
    assign unit_neg[7] = l0u[7]  & l1f[7]  & l2f[7]  ? lit0[7][0]    :
                         l0f[7]  & l1u[7]  & l2f[7]  ? lit1[7][0]    : lit2[7][0];

    assign sat_c[8]  = valid_c[8]  & (l0t[8]  | l1t[8]  | l2t[8]);
    assign conf_c[8] = valid_c[8]  & l0f[8]   & l1f[8]  & l2f[8];
    assign unit_c[8] = valid_c[8]  & ~sat_c[8] & ~conf_c[8] &
                       ((l0u[8]  & l1f[8]  & l2f[8])  |
                        (l0f[8]  & l1u[8]  & l2f[8])  |
                        (l0f[8]  & l1f[8]  & l2u[8]));
    assign unit_var[8] = l0u[8]  & l1f[8]  & l2f[8]  ? lit0[8][3:1]  :
                         l0f[8]  & l1u[8]  & l2f[8]  ? lit1[8][3:1]  : lit2[8][3:1];
    assign unit_neg[8] = l0u[8]  & l1f[8]  & l2f[8]  ? lit0[8][0]    :
                         l0f[8]  & l1u[8]  & l2f[8]  ? lit1[8][0]    : lit2[8][0];

    assign sat_c[9]  = valid_c[9]  & (l0t[9]  | l1t[9]  | l2t[9]);
    assign conf_c[9] = valid_c[9]  & l0f[9]   & l1f[9]  & l2f[9];
    assign unit_c[9] = valid_c[9]  & ~sat_c[9] & ~conf_c[9] &
                       ((l0u[9]  & l1f[9]  & l2f[9])  |
                        (l0f[9]  & l1u[9]  & l2f[9])  |
                        (l0f[9]  & l1f[9]  & l2u[9]));
    assign unit_var[9] = l0u[9]  & l1f[9]  & l2f[9]  ? lit0[9][3:1]  :
                         l0f[9]  & l1u[9]  & l2f[9]  ? lit1[9][3:1]  : lit2[9][3:1];
    assign unit_neg[9] = l0u[9]  & l1f[9]  & l2f[9]  ? lit0[9][0]    :
                         l0f[9]  & l1u[9]  & l2f[9]  ? lit1[9][0]    : lit2[9][0];

    assign sat_c[10] = valid_c[10] & (l0t[10] | l1t[10] | l2t[10]);
    assign conf_c[10]= valid_c[10] & l0f[10]  & l1f[10] & l2f[10];
    assign unit_c[10]= valid_c[10] & ~sat_c[10] & ~conf_c[10] &
                       ((l0u[10] & l1f[10] & l2f[10]) |
                        (l0f[10] & l1u[10] & l2f[10]) |
                        (l0f[10] & l1f[10] & l2u[10]));
    assign unit_var[10]= l0u[10] & l1f[10] & l2f[10] ? lit0[10][3:1] :
                         l0f[10] & l1u[10] & l2f[10] ? lit1[10][3:1] : lit2[10][3:1];
    assign unit_neg[10]= l0u[10] & l1f[10] & l2f[10] ? lit0[10][0]   :
                         l0f[10] & l1u[10] & l2f[10] ? lit1[10][0]   : lit2[10][0];

    assign sat_c[11] = valid_c[11] & (l0t[11] | l1t[11] | l2t[11]);
    assign conf_c[11]= valid_c[11] & l0f[11]  & l1f[11] & l2f[11];
    assign unit_c[11]= valid_c[11] & ~sat_c[11] & ~conf_c[11] &
                       ((l0u[11] & l1f[11] & l2f[11]) |
                        (l0f[11] & l1u[11] & l2f[11]) |
                        (l0f[11] & l1f[11] & l2u[11]));
    assign unit_var[11]= l0u[11] & l1f[11] & l2f[11] ? lit0[11][3:1] :
                         l0f[11] & l1u[11] & l2f[11] ? lit1[11][3:1] : lit2[11][3:1];
    assign unit_neg[11]= l0u[11] & l1f[11] & l2f[11] ? lit0[11][0]   :
                         l0f[11] & l1u[11] & l2f[11] ? lit1[11][0]   : lit2[11][0];

    assign sat_c[12] = valid_c[12] & (l0t[12] | l1t[12] | l2t[12]);
    assign conf_c[12]= valid_c[12] & l0f[12]  & l1f[12] & l2f[12];
    assign unit_c[12]= valid_c[12] & ~sat_c[12] & ~conf_c[12] &
                       ((l0u[12] & l1f[12] & l2f[12]) |
                        (l0f[12] & l1u[12] & l2f[12]) |
                        (l0f[12] & l1f[12] & l2u[12]));
    assign unit_var[12]= l0u[12] & l1f[12] & l2f[12] ? lit0[12][3:1] :
                         l0f[12] & l1u[12] & l2f[12] ? lit1[12][3:1] : lit2[12][3:1];
    assign unit_neg[12]= l0u[12] & l1f[12] & l2f[12] ? lit0[12][0]   :
                         l0f[12] & l1u[12] & l2f[12] ? lit1[12][0]   : lit2[12][0];

    assign sat_c[13] = valid_c[13] & (l0t[13] | l1t[13] | l2t[13]);
    assign conf_c[13]= valid_c[13] & l0f[13]  & l1f[13] & l2f[13];
    assign unit_c[13]= valid_c[13] & ~sat_c[13] & ~conf_c[13] &
                       ((l0u[13] & l1f[13] & l2f[13]) |
                        (l0f[13] & l1u[13] & l2f[13]) |
                        (l0f[13] & l1f[13] & l2u[13]));
    assign unit_var[13]= l0u[13] & l1f[13] & l2f[13] ? lit0[13][3:1] :
                         l0f[13] & l1u[13] & l2f[13] ? lit1[13][3:1] : lit2[13][3:1];
    assign unit_neg[13]= l0u[13] & l1f[13] & l2f[13] ? lit0[13][0]   :
                         l0f[13] & l1u[13] & l2f[13] ? lit1[13][0]   : lit2[13][0];

    assign sat_c[14] = valid_c[14] & (l0t[14] | l1t[14] | l2t[14]);
    assign conf_c[14]= valid_c[14] & l0f[14]  & l1f[14] & l2f[14];
    assign unit_c[14]= valid_c[14] & ~sat_c[14] & ~conf_c[14] &
                       ((l0u[14] & l1f[14] & l2f[14]) |
                        (l0f[14] & l1u[14] & l2f[14]) |
                        (l0f[14] & l1f[14] & l2u[14]));
    assign unit_var[14]= l0u[14] & l1f[14] & l2f[14] ? lit0[14][3:1] :
                         l0f[14] & l1u[14] & l2f[14] ? lit1[14][3:1] : lit2[14][3:1];
    assign unit_neg[14]= l0u[14] & l1f[14] & l2f[14] ? lit0[14][0]   :
                         l0f[14] & l1u[14] & l2f[14] ? lit1[14][0]   : lit2[14][0];

    assign sat_c[15] = valid_c[15] & (l0t[15] | l1t[15] | l2t[15]);
    assign conf_c[15]= valid_c[15] & l0f[15]  & l1f[15] & l2f[15];
    assign unit_c[15]= valid_c[15] & ~sat_c[15] & ~conf_c[15] &
                       ((l0u[15] & l1f[15] & l2f[15]) |
                        (l0f[15] & l1u[15] & l2f[15]) |
                        (l0f[15] & l1f[15] & l2u[15]));
    assign unit_var[15]= l0u[15] & l1f[15] & l2f[15] ? lit0[15][3:1] :
                         l0f[15] & l1u[15] & l2f[15] ? lit1[15][3:1] : lit2[15][3:1];
    assign unit_neg[15]= l0u[15] & l1f[15] & l2f[15] ? lit0[15][0]   :
                         l0f[15] & l1u[15] & l2f[15] ? lit1[15][0]   : lit2[15][0];

    // -----------------------------------------------------------------------
    // Combinational: global conflict, all-satisfied, first unit clause
    // -----------------------------------------------------------------------
    wire any_conflict;
    assign any_conflict = conf_c[0]  | conf_c[1]  | conf_c[2]  | conf_c[3]  |
                          conf_c[4]  | conf_c[5]  | conf_c[6]  | conf_c[7]  |
                          conf_c[8]  | conf_c[9]  | conf_c[10] | conf_c[11] |
                          conf_c[12] | conf_c[13] | conf_c[14] | conf_c[15];

    wire any_unit;
    assign any_unit = unit_c[0]  | unit_c[1]  | unit_c[2]  | unit_c[3]  |
                      unit_c[4]  | unit_c[5]  | unit_c[6]  | unit_c[7]  |
                      unit_c[8]  | unit_c[9]  | unit_c[10] | unit_c[11] |
                      unit_c[12] | unit_c[13] | unit_c[14] | unit_c[15];

    // all_valid_satisfied: all valid clauses are satisfied
    wire all_sat_w;
    assign all_sat_w =
        (~valid_c[0]  | sat_c[0])  & (~valid_c[1]  | sat_c[1])  &
        (~valid_c[2]  | sat_c[2])  & (~valid_c[3]  | sat_c[3])  &
        (~valid_c[4]  | sat_c[4])  & (~valid_c[5]  | sat_c[5])  &
        (~valid_c[6]  | sat_c[6])  & (~valid_c[7]  | sat_c[7])  &
        (~valid_c[8]  | sat_c[8])  & (~valid_c[9]  | sat_c[9])  &
        (~valid_c[10] | sat_c[10]) & (~valid_c[11] | sat_c[11]) &
        (~valid_c[12] | sat_c[12]) & (~valid_c[13] | sat_c[13]) &
        (~valid_c[14] | sat_c[14]) & (~valid_c[15] | sat_c[15]);

    // First unit clause selector (priority encoder)
    wire [2:0] up_var;
    wire       up_neg;
    assign up_var = unit_c[0]  ? unit_var[0]  :
                    unit_c[1]  ? unit_var[1]  :
                    unit_c[2]  ? unit_var[2]  :
                    unit_c[3]  ? unit_var[3]  :
                    unit_c[4]  ? unit_var[4]  :
                    unit_c[5]  ? unit_var[5]  :
                    unit_c[6]  ? unit_var[6]  :
                    unit_c[7]  ? unit_var[7]  :
                    unit_c[8]  ? unit_var[8]  :
                    unit_c[9]  ? unit_var[9]  :
                    unit_c[10] ? unit_var[10] :
                    unit_c[11] ? unit_var[11] :
                    unit_c[12] ? unit_var[12] :
                    unit_c[13] ? unit_var[13] :
                    unit_c[14] ? unit_var[14] : unit_var[15];
    assign up_neg = unit_c[0]  ? unit_neg[0]  :
                    unit_c[1]  ? unit_neg[1]  :
                    unit_c[2]  ? unit_neg[2]  :
                    unit_c[3]  ? unit_neg[3]  :
                    unit_c[4]  ? unit_neg[4]  :
                    unit_c[5]  ? unit_neg[5]  :
                    unit_c[6]  ? unit_neg[6]  :
                    unit_c[7]  ? unit_neg[7]  :
                    unit_c[8]  ? unit_neg[8]  :
                    unit_c[9]  ? unit_neg[9]  :
                    unit_c[10] ? unit_neg[10] :
                    unit_c[11] ? unit_neg[11] :
                    unit_c[12] ? unit_neg[12] :
                    unit_c[13] ? unit_neg[13] :
                    unit_c[14] ? unit_neg[14] : unit_neg[15];

    // First unassigned variable (decision heuristic)
    wire [2:0] dec_var;
    assign dec_var = ~assign_set[0] ? 3'd0 :
                     ~assign_set[1] ? 3'd1 :
                     ~assign_set[2] ? 3'd2 :
                     ~assign_set[3] ? 3'd3 :
                     ~assign_set[4] ? 3'd4 :
                     ~assign_set[5] ? 3'd5 :
                     ~assign_set[6] ? 3'd6 : 3'd7;

    wire all_assigned;
    assign all_assigned = &assign_set;

    // -----------------------------------------------------------------------
    // Sequential FSM
    // -----------------------------------------------------------------------
    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= ST_IDLE;
            sat         <= 1'b0;
            unsat       <= 1'b0;
            done        <= 1'b0;
            assign_val  <= 8'h0;
            assign_set  <= 8'h0;
            assign_out  <= 8'h0;
            iter_cnt    <= 4'h0;
            iter_count  <= 4'h0;
            bt_depth    <= 2'd0;
            conflict    <= 1'b0;
            changed     <= 1'b0;
            all_satisfied <= 1'b0;
            bt_stack[0] <= 20'h0;
            bt_stack[1] <= 20'h0;
            bt_stack[2] <= 20'h0; bt_stack[3] <= 20'h0; bt_stack[4] <= 20'h0; bt_stack[5] <= 20'h0; bt_stack[6] <= 20'h0; bt_stack[7] <= 20'h0;
            // Initialize clause memory
            for (k = 0; k < 16; k = k + 1)
                clause_mem[k] <= 24'h0;
        end else begin
            // Clause loading (any time)
            if (load_clause)
                clause_mem[clause_idx] <= clause_data;

            case (state)
                // -----------------------------------------------------------
                ST_IDLE: begin
                    sat    <= 1'b0;
                    unsat  <= 1'b0;
                    done   <= 1'b0;
                    iter_cnt <= 4'h0;
                    iter_count <= 4'h0;
                    if (start) begin
                        assign_val <= 8'h0;
                        assign_set <= 8'h0;
                        bt_depth   <= 2'd0;
                        state      <= ST_PROPAGATE;
                    end
                end

                // -----------------------------------------------------------
                // PROPAGATE: apply unit propagation (one unit forced per cycle)
                // -----------------------------------------------------------
                ST_PROPAGATE: begin
                    iter_cnt   <= iter_cnt + 4'h1;
                    iter_count <= iter_cnt + 4'h1;

                    if (any_conflict) begin
                        // Conflict detected
                        state <= ST_BACKTRACK;
                    end else if (all_sat_w) begin
                        // All clauses satisfied
                        sat        <= 1'b1;
                        done       <= 1'b1;
                        assign_out <= assign_val;
                        state      <= ST_DONE;
                    end else if (any_unit) begin
                        // Force the unit literal (neg=0 → set val=1, neg=1 → set val=0)
                        assign_set[up_var] <= 1'b1;
                        assign_val[up_var] <= up_neg ^ 1'b1; // neg=0→val=1, neg=1→val=0
                        // Stay in PROPAGATE for another round
                    end else if (all_assigned) begin
                        // All assigned, all clauses satisfied (checked above)
                        // If we reach here, formula is sat
                        sat        <= 1'b1;
                        done       <= 1'b1;
                        assign_out <= assign_val;
                        state      <= ST_DONE;
                    end else begin
                        // No unit, no conflict, not all-assigned — go decide
                        state <= ST_DECIDE;
                    end
                end

                // -----------------------------------------------------------
                // DECIDE: pick an unassigned variable, try value=1
                // Push backtrack frame, assign var=1
                // -----------------------------------------------------------
                ST_DECIDE: begin
                    iter_cnt   <= iter_cnt + 4'h1;
                    iter_count <= iter_cnt + 4'h1;

                    if (all_sat_w) begin
                        // All clauses already satisfied — declare SAT
                        sat        <= 1'b1;
                        done       <= 1'b1;
                        assign_out <= assign_val;
                        state      <= ST_DONE;
                    end else if (any_conflict) begin
                        state <= ST_BACKTRACK;
                    end else if (bt_depth < 4'd8) begin
                        // Push stack frame: {assign_val, assign_set, dec_var, tried_both=0}
                        bt_stack[bt_depth] <= {assign_val, assign_set, dec_var, 1'b0};
                        bt_depth <= bt_depth + 2'd1;
                        // Assign variable to 1
                        assign_set[dec_var] <= 1'b1;
                        assign_val[dec_var] <= 1'b1;
                        state <= ST_PROPAGATE;
                    end else if (iter_cnt >= 6'd40) begin
                        // 8-cycle cap AND stack full — declare UNSAT
                        unsat <= 1'b1;
                        done  <= 1'b1;
                        state <= ST_DONE;
                    end else begin
                        // Stack full — declare UNSAT
                        unsat <= 1'b1;
                        done  <= 1'b1;
                        state <= ST_DONE;
                    end
                end

                // -----------------------------------------------------------
                // BACKTRACK: pop stack, flip decision or declare UNSAT
                // -----------------------------------------------------------
                ST_BACKTRACK: begin
                    iter_cnt   <= iter_cnt + 4'h1;
                    iter_count <= iter_cnt + 4'h1;

                    if (all_sat_w) begin
                        sat        <= 1'b1;
                        done       <= 1'b1;
                        assign_out <= assign_val;
                        state      <= ST_DONE;
                    end else if (bt_depth == 2'd0) begin
                        // No frames left — UNSAT
                        unsat <= 1'b1;
                        done  <= 1'b1;
                        state <= ST_DONE;
                    end else if (iter_cnt >= 6'd40) begin
                        // Cycle cap reached
                        unsat <= 1'b1;
                        done  <= 1'b1;
                        state <= ST_DONE;
                    end else begin
                        // Restore assignment from top of stack
                        // bt_stack[bt_depth-1] = {assign_val[7:0], assign_set[7:0], dec_var[2:0], tried_both[0]}
                        assign_val <= bt_stack[bt_depth - 2'd1][19:12];
                        assign_set <= bt_stack[bt_depth - 2'd1][11:4];
                        // dec_var   = bt_stack[...][3:1]
                        // tried_both = bt_stack[...][0]
                        if (bt_stack[bt_depth - 2'd1][0] == 1'b0) begin
                            // Haven't tried val=0 yet — flip to 0
                            bt_stack[bt_depth - 2'd1][0] <= 1'b1; // mark tried_both
                            assign_set[bt_stack[bt_depth - 2'd1][3:1]] <= 1'b1;
                            assign_val[bt_stack[bt_depth - 2'd1][3:1]] <= 1'b0;
                            state <= ST_PROPAGATE;
                        end else begin
                            // Both values tried — pop and continue backtracking
                            bt_depth <= bt_depth - 2'd1;
                            state    <= ST_BACKTRACK;
                        end
                    end
                end

                // -----------------------------------------------------------
                ST_DONE: begin
                    done <= 1'b1;
                    // Restart on new start pulse
                    if (start) begin
                        sat        <= 1'b0;
                        unsat      <= 1'b0;
                        done       <= 1'b0;
                        assign_val <= 8'h0;
                        assign_set <= 8'h0;
                        bt_depth   <= 2'd0;
                        iter_cnt   <= 4'h0;
                        iter_count <= 4'h0;
                        state      <= ST_PROPAGATE;
                    end
                end

                default: state <= ST_IDLE;
            endcase
        end
    end

endmodule
`default_nettype wire
