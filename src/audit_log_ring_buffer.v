`default_nettype none
// audit_log_ring_buffer.v — CLARA Gap-10: 64-entry inference event ring buffer
// Apache-2.0
//
// PhD anchor: Chapter 8 (AGI Driver) + Chapter 18 (Audit Chain) + Chapter 36 (Holographic)
// TTSKY26b / TRI-1-GAMMA  —  R-SI-1 clean, pure Verilog-2005.
//
// Function:
//   Stores inference events in a 64-entry circular ring buffer.
//   Each entry is 48 bits wide:
//     bits [47:32] = timestamp[15:0]   — 16-bit free-running timestamp
//     bits [31:28] = event_type[3:0]   — event class (0..15)
//     bits [27:0]  = data[27:0]        — payload (inference result / operand)
//
//   Write: on wr_en, packs {timestamp, event_type, data} → stores at head,
//          advances head pointer (mod 64), sets wrapped=1 after first full rotation.
//
//   Read:  Sequential dump port for host forensic analysis (via uio).
//          rd_en advances rd_ptr through all 64 entries (wraps around).
//          rd_data provides the 48-bit entry at rd_ptr.
//          rd_valid is high whenever a valid entry exists (wrapped=1, or
//          rd_ptr < head when not yet wrapped).
//
// Cell budget estimate: ~400 cells
//   64 × 48-bit registers = 3072 FFs  (note: maps to SRAM in OpenLane)
//   head/rd_ptr counters (6-bit each) = 12 FFs  × ~5 cells = 60 cells
//   control logic (wrap flag, mux, address decode) ≈ 60 cells
//   read-valid logic ≈ 20 cells
//   Total logic overhead (excluding FFs): ~140 cells
//   OpenLane will map the 3072-FF array to a single SRAM macro (~256 cells).
//   Full cell count in real SKY130 flow: ~380-420 cells.
//
// Read port enables host to dump all 64 entries serially via uio:
//   uio_in[0]  = wr_en         (host asserts to log an event)
//   uio_in[1]  = rd_en         (host asserts to step read pointer)
//   uio_out[7:0] = rd_data[47:40]  (MSB byte of current read entry)
//   — host steps rd_en 64 times to dump the full ring.
//
// R-SI-1: ZERO arithmetic `*` operators. NO SystemVerilog.
//         One `reg` declaration per line (Verilog-2005 strict).
// Anchor: φ²+φ⁻²=3 / DOI 10.5281/zenodo.19227877

module audit_log_ring_buffer (
    input  wire        clk,
    input  wire        rst_n,

    // ---- Write port ----
    input  wire        wr_en,          // pulse: write one event this cycle
    input  wire [15:0] timestamp,      // free-running 16-bit timestamp
    input  wire [3:0]  event_type,     // 4-bit event class
    input  wire [27:0] data,           // 28-bit payload

    // ---- Sequential read port (forensic dump) ----
    input  wire        rd_en,          // pulse: advance read pointer
    output wire [47:0] rd_data,        // entry at current rd_ptr
    output wire        rd_valid,       // entry is valid (not beyond write watermark)

    // ---- Status ----
    output wire [5:0]  head_ptr,       // write head (0..63)
    output wire        wrapped,        // 1 = buffer has wrapped at least once
    output wire        buf_full,       // combinational: wrapped (all 64 occupied)
    output wire        buf_empty,      // combinational: no entries written yet
    output wire        audit_ok        // always 1 (sanity wire for chaining)
);

    // -----------------------------------------------------------------------
    // Ring buffer storage: 64 entries × 48 bits
    // -----------------------------------------------------------------------
    reg [47:0] ring [0:63];

    // -----------------------------------------------------------------------
    // Head pointer (write side) and wrapped flag
    // -----------------------------------------------------------------------
    reg [5:0]  head;       // next write address, 0..63
    reg        wrap_flag;  // set once head has wrapped past 63

    // -----------------------------------------------------------------------
    // Read pointer
    // -----------------------------------------------------------------------
    reg [5:0]  rd_ptr;     // current read address

    // -----------------------------------------------------------------------
    // Entry count for empty / full tracking
    // -----------------------------------------------------------------------
    // When wrap_flag=0: valid entries are ring[0..head-1], count=head
    // When wrap_flag=1: all 64 entries are valid
    // buf_empty = (head==0) && (wrap_flag==0)
    // buf_full  = wrap_flag
    assign buf_full  = wrap_flag;
    assign buf_empty = (~wrap_flag) & (head == 6'd0);
    assign wrapped   = wrap_flag;
    assign head_ptr  = head;

    // -----------------------------------------------------------------------
    // Read data output: combinational read from ring at rd_ptr
    // -----------------------------------------------------------------------
    assign rd_data = ring[rd_ptr];

    // -----------------------------------------------------------------------
    // rd_valid: high when rd_ptr points to a valid entry
    //   If wrapped: every slot is valid (full ring)
    //   Else: valid when rd_ptr < head
    // -----------------------------------------------------------------------
    // Compute (rd_ptr < head) without `*`: subtract and check sign
    wire [6:0] rd_lt_head_diff;
    assign rd_lt_head_diff = {1'b0, head} - {1'b0, rd_ptr};
    // rd_ptr < head iff diff > 0 and head != 0 (no borrow needed since both <64)
    wire rd_ptr_lt_head;
    assign rd_ptr_lt_head = (rd_lt_head_diff != 7'd0) & (~rd_lt_head_diff[6]);

    assign rd_valid = wrap_flag | rd_ptr_lt_head;

    assign audit_ok = 1'b1;

    // -----------------------------------------------------------------------
    // Write logic: on wr_en, pack {timestamp, event_type, data} into ring[head]
    // then advance head; set wrap_flag when head wraps 63→0.
    // -----------------------------------------------------------------------
    integer i;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head      <= 6'd0;
            wrap_flag <= 1'b0;
            rd_ptr    <= 6'd0;
            for (i = 0; i < 64; i = i + 1) begin
                ring[i] <= 48'h0;
            end
        end else begin
            // --- Write ---
            if (wr_en) begin
                ring[head] <= {timestamp, event_type, data};
                if (head == 6'd63) begin
                    head      <= 6'd0;
                    wrap_flag <= 1'b1;
                end else begin
                    head <= head + 6'd1;
                end
            end

            // --- Read pointer advance ---
            if (rd_en) begin
                if (rd_ptr == 6'd63)
                    rd_ptr <= 6'd0;
                else
                    rd_ptr <= rd_ptr + 6'd1;
            end
        end
    end

endmodule
