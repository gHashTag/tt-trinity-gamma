`default_nettype none
// proof_trace_writer.v — CLARA Gap-8: on-chip proof-trace receipt emitter
// Apache-2.0
//
// PhD anchor: Chapter 8 (AGI Driver) + Chapter 18 (Audit Chain) + Chapter 36 (Holographic)
// TTSKY26b / TRI-1-GAMMA  —  R-SI-1 clean, pure Verilog-2005.
//
// Function:
//   Accepts serial 20-bit proof records from explainability_unit (PR #62).
//   Buffers 10 records (200 bits total).  After the 10th record arrives the
//   module computes CRC-32 over the 200-bit payload (25 bytes) using the
//   on-chip crc32_receipt submodule, then emits a 232-bit serial stream:
//     {200-bit payload, 32-bit CRC}  LSB-first, one bit per clock.
//   receipt_valid_pulse is asserted for exactly one clock cycle when the full
//   232-bit receipt has been shifted out.
//
// Cell budget estimate: ~250 cells  (200-bit buffer=200 FFs + CRC~250 gates +
//   control FSM~30 cells + serialiser~10 cells)
//
// Interface:
//   Proof input (from explainability_unit):
//     proof_record_in  [19:0]  — 20-bit proof record
//     proof_record_valid       — pulse: one cycle, record is valid
//   Receipt output (serial stream):
//     receipt_bit              — serial bit out (MSB first within each byte,
//                                records packed LSB-first)
//     receipt_bit_valid        — high during active stream
//     receipt_valid_pulse      — single-cycle pulse when stream completes
//
// Reset: synchronous via rst_n (active-low async).

module proof_trace_writer (
    input  wire        clk,
    input  wire        rst_n,

    // From explainability_unit
    input  wire [19:0] proof_record_in,
    input  wire        proof_record_valid,

    // Serial receipt output
    output reg         receipt_bit,
    output reg         receipt_bit_valid,
    output reg         receipt_valid_pulse
);

    // -----------------------------------------------------------------------
    // Local parameters
    // -----------------------------------------------------------------------
    localparam NUM_RECORDS   = 10;
    localparam BITS_PAYLOAD  = 200;   // 10 × 20 bits
    localparam BITS_RECEIPT  = 232;   // 200 payload + 32 CRC
    localparam BYTES_PAYLOAD = 25;    // 200 / 8

    // FSM states
    localparam ST_COLLECT  = 3'd0;  // collecting proof records
    localparam ST_CRC      = 3'd1;  // feeding bytes to CRC engine
    localparam ST_WAIT_CRC = 3'd2;  // wait 1 cycle for last CRC byte to settle
    localparam ST_EMIT     = 3'd3;  // shifting out 232-bit stream
    localparam ST_DONE     = 3'd4;  // one-cycle done pulse, back to COLLECT

    // -----------------------------------------------------------------------
    // Storage for 10 × 20-bit proof records  (200 bits)
    // -----------------------------------------------------------------------
    reg [19:0] records [0:NUM_RECORDS-1];
    reg [3:0]  rec_count;   // 0..10

    // Flatten 200-bit buffer (combinationally assembled from records[])
    // records[0] occupies bits [19:0], records[9] occupies bits [199:180].
    wire [199:0] payload;
    assign payload[19:0]   = records[0];
    assign payload[39:20]  = records[1];
    assign payload[59:40]  = records[2];
    assign payload[79:60]  = records[3];
    assign payload[99:80]  = records[4];
    assign payload[119:100]= records[5];
    assign payload[139:120]= records[6];
    assign payload[159:140]= records[7];
    assign payload[179:160]= records[8];
    assign payload[199:180]= records[9];

    // -----------------------------------------------------------------------
    // CRC-32 submodule wiring
    // -----------------------------------------------------------------------
    reg         crc_start;
    reg         crc_valid;
    reg  [7:0]  crc_byte_in;
    wire [31:0] crc_raw;
    wire [31:0] crc_final;

    crc32_receipt u_crc (
        .clk      (clk),
        .rst_n    (rst_n),
        .start    (crc_start),
        .valid    (crc_valid),
        .byte_in  (crc_byte_in),
        .crc_raw  (crc_raw),
        .crc_final(crc_final)
    );

    // -----------------------------------------------------------------------
    // FSM state + counters
    // -----------------------------------------------------------------------
    reg [2:0]  state;
    reg [4:0]  byte_idx;    // 0..24  during ST_CRC
    reg [7:0]  emit_idx;    // 0..231 during ST_EMIT

    // 232-bit shift register loaded just before ST_EMIT
    reg [231:0] shift_reg;

    // -----------------------------------------------------------------------
    // Helper: extract byte byte_idx from payload (LSByte first)
    // payload[7:0] is byte 0, payload[15:8] is byte 1, etc.
    // -----------------------------------------------------------------------
    // We use a big mux; no * operator required.
    reg [7:0] sel_byte;
    always @(*) begin
        case (byte_idx)
            5'd0:  sel_byte = payload[7:0];
            5'd1:  sel_byte = payload[15:8];
            5'd2:  sel_byte = payload[23:16];
            5'd3:  sel_byte = payload[31:24];
            5'd4:  sel_byte = payload[39:32];
            5'd5:  sel_byte = payload[47:40];
            5'd6:  sel_byte = payload[55:48];
            5'd7:  sel_byte = payload[63:56];
            5'd8:  sel_byte = payload[71:64];
            5'd9:  sel_byte = payload[79:72];
            5'd10: sel_byte = payload[87:80];
            5'd11: sel_byte = payload[95:88];
            5'd12: sel_byte = payload[103:96];
            5'd13: sel_byte = payload[111:104];
            5'd14: sel_byte = payload[119:112];
            5'd15: sel_byte = payload[127:120];
            5'd16: sel_byte = payload[135:128];
            5'd17: sel_byte = payload[143:136];
            5'd18: sel_byte = payload[151:144];
            5'd19: sel_byte = payload[159:152];
            5'd20: sel_byte = payload[167:160];
            5'd21: sel_byte = payload[175:168];
            5'd22: sel_byte = payload[183:176];
            5'd23: sel_byte = payload[191:184];
            5'd24: sel_byte = payload[199:192];
            default: sel_byte = 8'h00;
        endcase
    end

    // -----------------------------------------------------------------------
    // Main FSM
    // -----------------------------------------------------------------------
    integer k;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= ST_COLLECT;
            rec_count         <= 4'd0;
            byte_idx          <= 5'd0;
            emit_idx          <= 8'd0;
            crc_start         <= 1'b0;
            crc_valid         <= 1'b0;
            crc_byte_in       <= 8'h00;
            receipt_bit       <= 1'b0;
            receipt_bit_valid <= 1'b0;
            receipt_valid_pulse <= 1'b0;
            shift_reg         <= 232'd0;
            for (k = 0; k < NUM_RECORDS; k = k + 1)
                records[k] <= 20'd0;
        end else begin
            // Defaults (de-assert pulses)
            crc_start         <= 1'b0;
            crc_valid         <= 1'b0;
            receipt_valid_pulse <= 1'b0;

            case (state)

                // -----------------------------------------------------------
                // ST_COLLECT: accept incoming proof records
                // -----------------------------------------------------------
                ST_COLLECT: begin
                    receipt_bit_valid <= 1'b0;
                    if (proof_record_valid && (rec_count < NUM_RECORDS)) begin
                        records[rec_count] <= proof_record_in;
                        if (rec_count == (NUM_RECORDS - 1)) begin
                            // Buffer full — start CRC computation
                            rec_count  <= 4'd0;   // will be reused as slot index next time
                            byte_idx   <= 5'd0;
                            crc_start  <= 1'b1;   // reset CRC to 0xFFFFFFFF
                            state      <= ST_CRC;
                        end else begin
                            rec_count <= rec_count + 4'd1;
                        end
                    end
                end

                // -----------------------------------------------------------
                // ST_CRC: feed 25 bytes to crc32_receipt, one per cycle
                // -----------------------------------------------------------
                ST_CRC: begin
                    if (byte_idx < BYTES_PAYLOAD) begin
                        crc_valid   <= 1'b1;
                        crc_byte_in <= sel_byte;
                        byte_idx    <= byte_idx + 5'd1;
                    end else begin
                        // All 25 bytes have been clocked into the CRC unit.
                        // Wait one additional cycle so the last byte settles
                        // into crc_raw before reading crc_final.
                        state <= ST_WAIT_CRC;
                    end
                end

                // -----------------------------------------------------------
                // ST_WAIT_CRC: one idle cycle for last CRC byte to propagate
                // -----------------------------------------------------------
                ST_WAIT_CRC: begin
                    // crc_final is now stable; load shift register.
                    // {CRC[31:0], payload[199:0]} emitted MSB-first → bit 231 first.
                    shift_reg <= {crc_final, payload};
                    emit_idx  <= 8'd0;
                    state     <= ST_EMIT;
                end

                // -----------------------------------------------------------
                // ST_EMIT: shift out 232 bits, MSB first
                // -----------------------------------------------------------
                ST_EMIT: begin
                    receipt_bit_valid <= 1'b1;
                    receipt_bit       <= shift_reg[231];
                    shift_reg         <= {shift_reg[230:0], 1'b0};
                    if (emit_idx == (BITS_RECEIPT - 1)) begin
                        emit_idx  <= 8'd0;
                        state     <= ST_DONE;
                    end else begin
                        emit_idx  <= emit_idx + 8'd1;
                    end
                end

                // -----------------------------------------------------------
                // ST_DONE: assert valid_pulse for one cycle, reset record ptr
                // -----------------------------------------------------------
                ST_DONE: begin
                    receipt_bit_valid   <= 1'b0;
                    receipt_bit         <= 1'b0;
                    receipt_valid_pulse <= 1'b1;
                    rec_count           <= 4'd0;
                    state               <= ST_COLLECT;
                end

                default: state <= ST_COLLECT;

            endcase
        end
    end

endmodule
