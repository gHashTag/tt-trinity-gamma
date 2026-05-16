`default_nettype none
`timescale 1ns / 1ps
// tb_audit_log_ring_buffer.v — testbench for audit_log_ring_buffer.v
// Apache-2.0
//
// 5 scenarios, 14+ assertions PASS
//   S1: empty read — verify buf_empty, rd_valid low, head_ptr=0
//   S2: single write / read — write 1 entry, verify rd_data readback
//   S3: wrap-around at 64 — fill 64 entries + 1 overwrite, verify wrapped + head
//   S4: read while writing — simultaneous wr_en + rd_en, verify coherence
//   S5: reset mid-operation — reset clears buffer, re-write works correctly

module tb_audit_log_ring_buffer;

    // -----------------------------------------------------------------------
    // DUT signal declarations
    // -----------------------------------------------------------------------
    reg        clk;
    reg        rst_n;
    reg        wr_en;
    reg [15:0] timestamp;
    reg [3:0]  event_type;
    reg [27:0] data;
    reg        rd_en;

    wire [47:0] rd_data;
    wire        rd_valid;
    wire [5:0]  head_ptr;
    wire        wrapped;
    wire        buf_full;
    wire        buf_empty;
    wire        audit_ok;

    // -----------------------------------------------------------------------
    // DUT instantiation
    // -----------------------------------------------------------------------
    audit_log_ring_buffer dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .wr_en      (wr_en),
        .timestamp  (timestamp),
        .event_type (event_type),
        .data       (data),
        .rd_en      (rd_en),
        .rd_data    (rd_data),
        .rd_valid   (rd_valid),
        .head_ptr   (head_ptr),
        .wrapped    (wrapped),
        .buf_full   (buf_full),
        .buf_empty  (buf_empty),
        .audit_ok   (audit_ok)
    );

    // -----------------------------------------------------------------------
    // Clock: 10 ns period
    // -----------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Assertion counters
    // -----------------------------------------------------------------------
    integer pass_count;
    integer fail_count;

    task check;
        input       cond;
        input [255:0] name;
        begin
            if (cond) begin
                $display("PASS: %0s", name);
                pass_count = pass_count + 1;
            end else begin
                $display("FAIL: %0s", name);
                fail_count = fail_count + 1;
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Helper: apply reset
    // -----------------------------------------------------------------------
    task do_reset;
        begin
            rst_n      <= 1'b0;
            wr_en      <= 1'b0;
            rd_en      <= 1'b0;
            timestamp  <= 16'h0000;
            event_type <= 4'h0;
            data       <= 28'h0;
            repeat(3) @(posedge clk); #1;
            rst_n <= 1'b1;
            @(posedge clk); #1;
        end
    endtask

    // -----------------------------------------------------------------------
    // Helper: write one event
    // -----------------------------------------------------------------------
    task write_event;
        input [15:0] ts;
        input [3:0]  etype;
        input [27:0] dval;
        begin
            @(posedge clk); #1;
            wr_en      <= 1'b1;
            timestamp  <= ts;
            event_type <= etype;
            data       <= dval;
            @(posedge clk); #1;
            wr_en      <= 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Helper: step read pointer
    // -----------------------------------------------------------------------
    task read_step;
        begin
            @(posedge clk); #1;
            rd_en <= 1'b1;
            @(posedge clk); #1;
            rd_en <= 1'b0;
        end
    endtask

    // -----------------------------------------------------------------------
    // Main test body
    // -----------------------------------------------------------------------
    integer idx;

    initial begin
        pass_count = 0;
        fail_count = 0;

        $display("=== tb_audit_log_ring_buffer START ===");

        // ===================================================================
        // S1: Empty read
        //   After reset, buffer must be empty; rd_valid=0; head_ptr=0
        // ===================================================================
        $display("--- S1: Empty read ---");
        do_reset;
        @(posedge clk); #1;  // let combinationals settle

        check(buf_empty == 1'b1,          "S1.1: buf_empty after reset");
        check(buf_full  == 1'b0,          "S1.2: buf_full=0 after reset");
        check(head_ptr  == 6'd0,          "S1.3: head_ptr=0 after reset");
        check(wrapped   == 1'b0,          "S1.4: wrapped=0 after reset");
        check(rd_valid  == 1'b0,          "S1.5: rd_valid=0 (buffer empty)");
        check(audit_ok  == 1'b1,          "S1.6: audit_ok wire high");

        // ===================================================================
        // S2: Single write / read
        //   Write one event at ts=0xABCD, etype=4'hF, data=28'h1234567
        //   Then verify rd_data readback and state
        // ===================================================================
        $display("--- S2: Single write/read ---");
        do_reset;

        write_event(16'hABCD, 4'hF, 28'h1234567);
        @(posedge clk); #1;

        // head_ptr should now be 1; buffer not empty, not full
        check(head_ptr  == 6'd1,          "S2.1: head_ptr=1 after single write");
        check(buf_empty == 1'b0,          "S2.2: buf_empty=0 after write");
        check(buf_full  == 1'b0,          "S2.3: buf_full=0 (not wrapped)");
        check(wrapped   == 1'b0,          "S2.4: wrapped=0 after single write");

        // rd_ptr=0 → rd_valid should be 1 (rd_ptr < head=1)
        check(rd_valid  == 1'b1,          "S2.5: rd_valid=1 (entry 0 available)");

        // Verify rd_data[47:0] = {0xABCD, 4'hF, 28'h1234567}
        // Packed: bits[47:32]=ts, [31:28]=etype, [27:0]=data
        check(rd_data == {16'hABCD, 4'hF, 28'h1234567},
                                          "S2.6: rd_data matches written entry");

        // Step rd_ptr past entry 0 → rd_ptr=1, beyond head → rd_valid=0
        read_step;
        @(posedge clk); #1;
        check(rd_valid == 1'b0,           "S2.7: rd_valid=0 after stepping past head");

        // ===================================================================
        // S3: Wrap-around at 64
        //   Write 65 events. After event 64 (index 63), head wraps to 0
        //   and wrap_flag=1. Event 65 (index 64) overwrites ring[0].
        // ===================================================================
        $display("--- S3: Wrap-around at 64 ---");
        do_reset;

        // Write 63 events (ts = index, etype = index[3:0], data = index)
        for (idx = 0; idx < 63; idx = idx + 1) begin
            write_event(idx[15:0], idx[3:0], idx[27:0]);
        end
        @(posedge clk); #1;
        check(wrapped   == 1'b0,          "S3.1: wrapped=0 after 63 writes");
        check(head_ptr  == 6'd63,         "S3.2: head_ptr=63 after 63 writes");
        check(buf_full  == 1'b0,          "S3.3: buf_full=0 at head=63");

        // Write entry 63 → head becomes 0, wrap_flag set
        write_event(16'hFF00, 4'hA, 28'hFFFFFFF);
        @(posedge clk); #1;
        check(wrapped   == 1'b1,          "S3.4: wrapped=1 after 64th write");
        check(head_ptr  == 6'd0,          "S3.5: head_ptr wraps to 0");
        check(buf_full  == 1'b1,          "S3.6: buf_full=1 when wrapped");
        check(buf_empty == 1'b0,          "S3.7: buf_empty=0 when full");

        // Write one more entry → overwrites ring[0], head=1
        write_event(16'h1234, 4'hB, 28'h0000001);
        @(posedge clk); #1;
        check(head_ptr  == 6'd1,          "S3.8: head_ptr=1 after overwrite write");
        check(wrapped   == 1'b1,          "S3.9: wrapped stays 1 after overwrite");

        // Verify ring[0] was overwritten with the last entry
        // rd_ptr is still at 1 from a previous read_step — reset to check
        // rd_ptr is at whatever state after S2 steps, but we just reset,
        // so rd_ptr=0 currently (reset was called at start of S3).
        // After 65 writes, rd_ptr=0 still.
        check(rd_data == {16'h1234, 4'hB, 28'h0000001},
                                          "S3.10: ring[0] overwritten correctly");

        // ===================================================================
        // S4: Read while writing (simultaneous wr_en + rd_en)
        //   Start from fresh reset. Write event A, then simultaneously
        //   assert wr_en + rd_en in one cycle: rd_ptr should advance
        //   and new write should land at head.
        // ===================================================================
        $display("--- S4: Read while writing ---");
        do_reset;

        write_event(16'h0001, 4'h1, 28'h0000011);   // ring[0], head→1
        write_event(16'h0002, 4'h2, 28'h0000022);   // ring[1], head→2
        @(posedge clk); #1;

        // rd_ptr=0 still; simultaneously write to ring[2] and advance rd_ptr
        @(posedge clk); #1;
        wr_en      <= 1'b1;
        rd_en      <= 1'b1;
        timestamp  <= 16'h0003;
        event_type <= 4'h3;
        data       <= 28'h0000033;
        @(posedge clk); #1;
        wr_en <= 1'b0;
        rd_en <= 1'b0;
        @(posedge clk); #1;

        // After simultaneous: head=3, rd_ptr=1
        check(head_ptr == 6'd3,           "S4.1: head=3 after concurrent write");
        // rd_ptr advanced to 1; rd_data now shows ring[1]
        check(rd_data == {16'h0002, 4'h2, 28'h0000022},
                                          "S4.2: rd_data=ring[1] after rd_en step");
        check(rd_valid == 1'b1,           "S4.3: rd_valid=1 (rd_ptr=1 < head=3)");
        check(wrapped  == 1'b0,           "S4.4: wrapped=0 in partial fill");

        // ===================================================================
        // S5: Reset mid-operation
        //   Write several entries, assert rst_n=0, verify buffer clears,
        //   then re-write and verify correct operation.
        // ===================================================================
        $display("--- S5: Reset mid-operation ---");
        do_reset;

        // Fill half the buffer
        for (idx = 0; idx < 32; idx = idx + 1) begin
            write_event(idx[15:0], idx[3:0], idx[27:0]);
        end
        @(posedge clk); #1;
        check(head_ptr == 6'd32,          "S5.1: head=32 before reset");
        check(buf_empty == 1'b0,          "S5.2: buf_empty=0 before reset");

        // Apply mid-operation reset
        @(posedge clk); #1;
        rst_n <= 1'b0;
        repeat(2) @(posedge clk); #1;
        rst_n <= 1'b1;
        @(posedge clk); #1;

        check(head_ptr  == 6'd0,          "S5.3: head=0 after mid-reset");
        check(wrapped   == 1'b0,          "S5.4: wrapped=0 after mid-reset");
        check(buf_empty == 1'b1,          "S5.5: buf_empty=1 after mid-reset");
        check(rd_valid  == 1'b0,          "S5.6: rd_valid=0 after mid-reset");

        // Write fresh event and verify
        write_event(16'hDEAD, 4'hC, 28'hBEEFCAF);
        @(posedge clk); #1;
        check(head_ptr == 6'd1,           "S5.7: head=1 after re-write post-reset");
        check(rd_data  == {16'hDEAD, 4'hC, 28'hBEEFCAF},
                                          "S5.8: rd_data correct after re-write");

        // ===================================================================
        // Final summary
        // ===================================================================
        $display("=== SUMMARY: %0d PASS, %0d FAIL ===", pass_count, fail_count);
        if (fail_count == 0)
            $display("ALL ASSERTIONS PASS");
        else
            $display("FAILURES DETECTED");

        $finish;
    end

endmodule
