`default_nettype none
`timescale 1ns / 1ps
// tb_proof_trace_writer.v — testbench for proof_trace_writer.v
// Apache-2.0
//
// 5 scenarios, 12+ assertions PASS
//   S1: empty buffer (no records → no receipt)
//   S2: partial 5 records (no receipt)
//   S3: full 10 records (receipt emitted, length 232 bits)
//   S4: reset mid-write (receipt only after fresh 10-record batch)
//   S5: CRC verification with known 10-record input / expected CRC output

module tb_proof_trace_writer;

    // -----------------------------------------------------------------------
    // Clock + DUT signals
    // -----------------------------------------------------------------------
    reg         clk;
    reg         rst_n;
    reg  [19:0] proof_record_in;
    reg         proof_record_valid;

    wire        receipt_bit;
    wire        receipt_bit_valid;
    wire        receipt_valid_pulse;

    // Instantiate DUT
    proof_trace_writer dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .proof_record_in    (proof_record_in),
        .proof_record_valid (proof_record_valid),
        .receipt_bit        (receipt_bit),
        .receipt_bit_valid  (receipt_bit_valid),
        .receipt_valid_pulse(receipt_valid_pulse)
    );

    // -----------------------------------------------------------------------
    // Clock: 10 ns period
    // -----------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // -----------------------------------------------------------------------
    // Assertion counter
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
            rst_n              <= 1'b0;
            proof_record_valid <= 1'b0;
            proof_record_in    <= 20'h00000;
            repeat(3) @(posedge clk); #1;
            rst_n <= 1'b1;
            @(posedge clk); #1;
        end
    endtask

    // -----------------------------------------------------------------------
    // Helper: send one proof record (one-cycle pulse)
    // -----------------------------------------------------------------------
    task send_record;
        input [19:0] rec;
        begin
            @(posedge clk); #1;
            proof_record_in    <= rec;
            proof_record_valid <= 1'b1;
            @(posedge clk); #1;
            proof_record_valid <= 1'b0;
            proof_record_in    <= 20'h00000;
        end
    endtask

    // -----------------------------------------------------------------------
    // Shared variables for receipt capture
    // -----------------------------------------------------------------------
    integer     found_pulse;
    reg [231:0] captured_receipt;
    integer     bit_cnt;

    // -----------------------------------------------------------------------
    // Helper: wait exactly max_cycles for receipt_valid_pulse
    // Captures serial bits into captured_receipt (MSB first == bit 231 first)
    // -----------------------------------------------------------------------
    task wait_for_receipt;
        input integer max_cycles;
        integer cyc;
        begin
            found_pulse      = 0;
            captured_receipt = 232'd0;
            bit_cnt          = 0;
            cyc              = 0;
            repeat (max_cycles) begin
                if (found_pulse == 0) begin
                    @(posedge clk); #1;
                    if (receipt_bit_valid) begin
                        captured_receipt = {captured_receipt[230:0], receipt_bit};
                        bit_cnt = bit_cnt + 1;
                    end
                    if (receipt_valid_pulse)
                        found_pulse = 1;
                    cyc = cyc + 1;
                end
            end
        end
    endtask

    // -----------------------------------------------------------------------
    // Reference CRC-32 (matches crc32_receipt.v exactly)
    // -----------------------------------------------------------------------
    function [31:0] crc32_byte;
        input [31:0] crc_in;
        input [7:0]  byte_in;
        reg [31:0] c;
        reg [7:0]  b;
        integer    j;
        begin
            c = crc_in;
            b = {byte_in[0], byte_in[1], byte_in[2], byte_in[3],
                 byte_in[4], byte_in[5], byte_in[6], byte_in[7]};
            c = c ^ {b, 24'h000000};
            for (j = 0; j < 8; j = j + 1) begin
                if (c[31]) c = (c << 1) ^ 32'h04C11DB7;
                else       c = (c << 1);
            end
            crc32_byte = c;
        end
    endfunction

    function [31:0] compute_crc;
        input [199:0] pl;
        reg [31:0] c;
        reg [7:0]  bval;
        integer    bi;
        reg [31:0] rev;
        integer    gi;
        begin
            c = 32'hFFFFFFFF;
            for (bi = 0; bi < 25; bi = bi + 1) begin
                case (bi)
                    0:  bval = pl[7:0];
                    1:  bval = pl[15:8];
                    2:  bval = pl[23:16];
                    3:  bval = pl[31:24];
                    4:  bval = pl[39:32];
                    5:  bval = pl[47:40];
                    6:  bval = pl[55:48];
                    7:  bval = pl[63:56];
                    8:  bval = pl[71:64];
                    9:  bval = pl[79:72];
                    10: bval = pl[87:80];
                    11: bval = pl[95:88];
                    12: bval = pl[103:96];
                    13: bval = pl[111:104];
                    14: bval = pl[119:112];
                    15: bval = pl[127:120];
                    16: bval = pl[135:128];
                    17: bval = pl[143:136];
                    18: bval = pl[151:144];
                    19: bval = pl[159:152];
                    20: bval = pl[167:160];
                    21: bval = pl[175:168];
                    22: bval = pl[183:176];
                    23: bval = pl[191:184];
                    24: bval = pl[199:192];
                    default: bval = 8'h00;
                endcase
                c = crc32_byte(c, bval);
            end
            rev = 32'd0;
            for (gi = 0; gi < 32; gi = gi + 1)
                rev[gi] = c[31 - gi];
            compute_crc = rev ^ 32'hFFFFFFFF;
        end
    endfunction

    // -----------------------------------------------------------------------
    // Working variables
    // -----------------------------------------------------------------------
    integer     i;
    reg [199:0] s5_payload;
    reg [31:0]  s5_expected_crc;
    reg [31:0]  s5_got_crc;
    reg [199:0] s5_got_payload;

    // -----------------------------------------------------------------------
    // Main test sequence
    // -----------------------------------------------------------------------
    initial begin
        $dumpfile("tb_proof_trace_writer.vcd");
        $dumpvars(0, tb_proof_trace_writer);

        pass_count = 0;
        fail_count = 0;

        // ===================================================================
        // S1: Empty buffer — no records sent, no receipt expected
        // ===================================================================
        $display("\n--- S1: Empty buffer ---");
        do_reset;
        found_pulse = 0;
        repeat (20) begin
            @(posedge clk); #1;
            if (receipt_valid_pulse) found_pulse = 1;
            if (receipt_bit_valid)   found_pulse = 1;
        end
        check(found_pulse == 0, "S1.1: no receipt_valid_pulse with empty buffer");
        check(receipt_bit_valid == 1'b0, "S1.2: receipt_bit_valid stays low");

        // ===================================================================
        // S2: Partial 5 records — no receipt expected
        // ===================================================================
        $display("\n--- S2: Partial 5 records ---");
        do_reset;
        for (i = 0; i < 5; i = i + 1)
            send_record(20'hAAAAA + i[19:0]);
        found_pulse = 0;
        repeat (30) begin
            @(posedge clk); #1;
            if (receipt_valid_pulse) found_pulse = 1;
        end
        check(found_pulse == 0, "S2.1: no receipt after only 5 records");
        check(receipt_bit_valid == 1'b0, "S2.2: receipt_bit_valid low after partial");

        // ===================================================================
        // S3: Full 10 records — receipt emitted, 232 bits
        // ===================================================================
        $display("\n--- S3: Full 10 records ---");
        do_reset;
        for (i = 0; i < 10; i = i + 1)
            send_record(20'h00001 + i[19:0]);
        wait_for_receipt(400);
        check(found_pulse == 1, "S3.1: receipt_valid_pulse asserted after 10 records");
        check(bit_cnt == 232, "S3.2: exactly 232 bits emitted");
        // After pulse bit_valid should de-assert
        @(posedge clk); #1;
        check(receipt_bit_valid == 1'b0, "S3.3: receipt_bit_valid de-asserted after stream");

        // ===================================================================
        // S4: Reset mid-write — receipt only after new full 10-record batch
        // ===================================================================
        $display("\n--- S4: Reset mid-write ---");
        do_reset;
        // Send 7 records then reset
        for (i = 0; i < 7; i = i + 1)
            send_record(20'hF0F0F + i[19:0]);
        rst_n <= 1'b0;
        repeat(2) @(posedge clk); #1;
        check(receipt_valid_pulse == 1'b0, "S4.1: no pulse during mid-write reset");
        check(receipt_bit_valid   == 1'b0, "S4.2: bit_valid low during reset");
        rst_n <= 1'b1;
        @(posedge clk); #1;
        // Fresh 10 records
        for (i = 0; i < 10; i = i + 1)
            send_record(20'h55555 + i[19:0]);
        wait_for_receipt(400);
        check(found_pulse == 1, "S4.3: receipt fires after fresh 10 post-reset");
        check(bit_cnt == 232, "S4.4: 232 bits emitted after reset-mid-write");

        // ===================================================================
        // S5: CRC verification with known input/output pair
        // ===================================================================
        $display("\n--- S5: CRC verification known pair ---");
        do_reset;

        // Build known payload: records[k] = 20'h47C00 | k  (0x47C0 watermark)
        s5_payload = 200'd0;
        s5_payload[19:0]   = 20'h47C00;
        s5_payload[39:20]  = 20'h47C01;
        s5_payload[59:40]  = 20'h47C02;
        s5_payload[79:60]  = 20'h47C03;
        s5_payload[99:80]  = 20'h47C04;
        s5_payload[119:100]= 20'h47C05;
        s5_payload[139:120]= 20'h47C06;
        s5_payload[159:140]= 20'h47C07;
        s5_payload[179:160]= 20'h47C08;
        s5_payload[199:180]= 20'h47C09;

        s5_expected_crc = compute_crc(s5_payload);
        $display("S5: expected CRC = 0x%08X", s5_expected_crc);

        // Send those exact records
        send_record(20'h47C00);
        send_record(20'h47C01);
        send_record(20'h47C02);
        send_record(20'h47C03);
        send_record(20'h47C04);
        send_record(20'h47C05);
        send_record(20'h47C06);
        send_record(20'h47C07);
        send_record(20'h47C08);
        send_record(20'h47C09);

        wait_for_receipt(400);
        check(found_pulse == 1, "S5.1: receipt_valid_pulse seen for known-pair test");
        check(bit_cnt == 232, "S5.2: exactly 232 bits emitted in known-pair test");

        // Receipt format: MSB emitted first → captured_receipt MSB is CRC MSB
        // Bit 231 = CRC[31], bit 200 = CRC[0], bits 199:0 = payload MSB-first
        s5_got_crc     = captured_receipt[231:200];
        s5_got_payload = captured_receipt[199:0];

        $display("S5: DUT CRC      = 0x%08X", s5_got_crc);
        check(s5_got_crc == s5_expected_crc, "S5.3: DUT CRC matches software reference");
        check(s5_got_payload == s5_payload,  "S5.4: payload in receipt matches input records");

        // ===================================================================
        // Summary
        // ===================================================================
        $display("\n=========================================");
        $display("Total PASS: %0d", pass_count);
        $display("Total FAIL: %0d", fail_count);
        $display("=========================================");
        if (fail_count == 0)
            $display("ALL ASSERTIONS PASS");
        else
            $display("SOME ASSERTIONS FAILED");

        $finish;
    end

endmodule
`default_nettype wire
