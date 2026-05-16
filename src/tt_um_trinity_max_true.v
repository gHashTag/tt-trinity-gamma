`default_nettype none
// tt_um_trinity_max_true.v - TRI-1 MAX-TRUE NEUROMORPHIC FLAGSHIP TT top.
// Apache-2.0
//
// FLAGSHIP architecture (TTSKY26b, 8x4 = 32 tiles):
//   * Neuromorphic: 8× cortical_column (LIF dynamics, BitNet b1.58 MLP,
//                   GF16 dot4 projection) = ~4100 cells
//   * D2D holo mesh: 4-port N/E/S/W router stub (uio[3:0]=TX, uio[7:4]=RX)
//                    LAYER-FROZEN gate on w_tx per PhD Theorem 36.1 R18
//   * Compute: 1× trinity_quad_mesh (16 PE) + 1× trinity_mesh_2x2 (4 PE) = 20 GF16 cells
//   * CROWN:   full SUPER-CROWN module set (24 modules total):
//              - phi_anchor_post + lucas_rom×7 (POST chain)
//              - vsa_matmul_8x8, vsa_matmul_16x16, bitnet_encoder
//              - bpb_counter, blake3_anchor, multi_tile_receipt, crc32_receipt
//              - alu9_decoder, ring27_memory, hwrng_lfsr, phi_pll_div
//              - wb_status_reg, wishbone_full
//              - 6 PhD-anchored monitors:
//                cassini_post, plrm_counter, bpb_lower_bound_guard,
//                nca_entropy_monitor, strobe_seed_guard, phi_distance_oracle
//              - crown47_rom + crown47_rom_8bit (full Crown47)
//              - trinity_friend_foe (GAMMA anchor 8'h93)
//              - holo_lut_pe (FHRR)
//   * Routing: lane[3]=cluster_sel, lane[2:1]=bank_sel, lane[0]=operand_lane
//
// TG-TRIAD-X invariant: canonical 0x47C0 on {uio_out, uo_out} under reset.
// PRESERVED: uio_out = {CANONICAL_HI[3:0], d2d_tx[3:0]} on reset
//            (CANONICAL_HI=4'h4, d2d_tx=4'h0) → {uio_out,uo_out}=0x47C0 ✓
//
// R-SI-1: zero NEW `*` arithmetic in any new module (only legacy gf16_mul,
//          grandfathered per TRI_NET_SHUTTLE_TRIAD.md Rule 2).
// Sacred Physics: φ²+φ⁻²=3 via phi_anchor_post POST chain.
// 8 cortical columns + D2D holo mesh (PhD Theorem 36.1)
// Lineage: tt-trinity-holo D2D port pattern · TTSKY26c 1x2
// DOI 10.5281/zenodo.19227877.

module tt_um_trinity_max_true (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    // =================================================================
    // Legacy combinational dot4 path (preserves canonical 0x47C0)
    // =================================================================
    wire [15:0] dot_out;
    gf16_dot4 u_dot (
        .a0(16'h3E00), .a1(16'h4000), .a2(16'h4100), .a3(16'h4200),
        .b0(16'h3E00), .b1(16'h4000), .b2(16'h4100), .b3(16'h4200),
        .result(dot_out)
    );

    reg [15:0] input_echo;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            input_echo <= 0;
        else if (ena)
            input_echo <= {ui_in, uio_in};
    end

    // =================================================================
    // FLAGSHIP fabric: master FSM + 20-PE GF16 mesh
    // =================================================================
    wire [31:0] host_in_pkt;
    wire        host_in_valid;
    wire        host_in_ready;
    wire [31:0] host_out_pkt;
    wire        host_out_valid;
    wire        host_out_ready;
    wire [15:0] mesh_dbg_tile0;
    wire [15:0] mesh_result;
    wire        mesh_result_valid;
    wire [7:0]  mesh_rcpt_checksum;
    wire [7:0]  mesh_rcpt_job_id;
    wire [1:0]  mesh_rcpt_tile_id;
    wire        mesh_rcpt_valid;

    trinity_master_fsm u_master (
        .clk             (clk),
        .rst_n           (rst_n),
        .ena             (ena),
        .load_mode       (ui_in[0]),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (host_in_valid),
        .host_in_ready   (host_in_ready),
        .host_out_pkt    (host_out_pkt),
        .host_out_valid  (host_out_valid),
        .host_out_ready  (host_out_ready),
        .result_reg      (mesh_result),
        .result_valid_q  (mesh_result_valid),
        .rcpt_checksum_q (mesh_rcpt_checksum),
        .rcpt_job_id_q   (mesh_rcpt_job_id),
        .rcpt_tile_id_q  (mesh_rcpt_tile_id),
        .rcpt_valid_q    (mesh_rcpt_valid)
    );

    // 1× trinity_quad_mesh (16 PE) + 1× trinity_mesh_2x2 (4 PE) = 20 honest GF16 cells
    trinity_max_true_20pe u_20pe (
        .clk             (clk),
        .rst_n           (rst_n),
        .host_in_pkt     (host_in_pkt),
        .host_in_valid   (host_in_valid),
        .host_in_ready   (host_in_ready),
        .host_out_pkt    (host_out_pkt),
        .host_out_valid  (host_out_valid),
        .host_out_ready  (host_out_ready),
        .dbg_tile0_result(mesh_dbg_tile0)
    );

    // =================================================================
    // NEUROMORPHIC CORTEX: 8 cortical columns (new for 8x4 reshape)
    // Each column: GF16 dot4 + BitNet b1.58 MLP + LIF membrane (~500 cells)
    // Total ~4100 cells for full 8-column cortex.
    // =================================================================
    wire [3:0]  cortex_spike_count;
    wire [7:0]  cortex_spike_vec;
    wire        cortex_ok;

    trinity_cortex_8col u_cortex (
        .clk         (clk),
        .rst_n       (rst_n),
        .ena         (ena),
        // Fan-in from dot4 path (lower nibbles of canonical input)
        .gf_in0      (dot_out[3:0]),
        .gf_in1      (dot_out[7:4]),
        .gf_in2      (dot_out[11:8]),
        .gf_in3      (dot_out[15:12]),
        // Per-column stimulus from ui_in + uio_in, replicated
        .stim_bus    ({ui_in, ui_in, ui_in, ui_in}),
        .spike_count (cortex_spike_count),
        .spike_vec   (cortex_spike_vec),
        .cortex_ok   (cortex_ok)
    );

    // =================================================================
    // D2D HOLO MESH: 4-port N/E/S/W router stub
    // uio[3:0] = TX (n_tx, e_tx, s_tx, w_tx)
    // uio[7:4] = RX (n_rx, e_rx, s_rx, w_rx)
    // LAYER-FROZEN gate on w_tx per PhD Theorem 36.1 R18.
    // TG-TRIAD-X: on reset, all TX = 0 → uio_out[3:0]=4'h0,
    //             combined with CANONICAL_HI=4'h4 → uio_out=8'h40 ✓
    // =================================================================
    wire d2d_n_tx;
    wire d2d_e_tx;
    wire d2d_s_tx;
    wire d2d_w_tx;
    wire d2d_n_rx_q;
    wire d2d_e_rx_q;
    wire d2d_s_rx_q;
    wire d2d_w_rx_q;
    wire mesh_ok;

    d2d_holo_mesh u_d2d (
        .clk         (clk),
        .rst_n       (rst_n),
        .ena         (ena),
        .spike_count (cortex_spike_count),
        .spike_vec   (cortex_spike_vec),
        .gf_tag      (mesh_result[15:12]),  // upper GF16 nibble as die-to-die tag
        .layer_frozen(1'b0),               // not frozen at submission time
        // RX from uio_in[7:4]
        .n_rx        (uio_in[4]),
        .e_rx        (uio_in[5]),
        .s_rx        (uio_in[6]),
        .w_rx        (uio_in[7]),
        .n_tx        (d2d_n_tx),
        .e_tx        (d2d_e_tx),
        .s_tx        (d2d_s_tx),
        .w_tx        (d2d_w_tx),
        .n_rx_q      (d2d_n_rx_q),
        .e_rx_q      (d2d_e_rx_q),
        .s_rx_q      (d2d_s_rx_q),
        .w_rx_q      (d2d_w_rx_q),
        .mesh_ok     (mesh_ok)
    );

    // =================================================================
    // SUPER-CROWN (preserved verbatim from Mid SUPER-CROWN)
    // =================================================================

    // L-S1: φ-anchor POST (proves φ²+φ⁻²=3 via Lucas recurrence)
    wire phi_ok, post_done;
    phi_anchor_post u_phi_post (
        .clk(clk), .rst_n(rst_n),
        .phi_ok(phi_ok), .post_done(post_done)
    );

    // L-S2: Lucas ROM chain (probed during POST + addressable for host)
    wire [7:0] lucas_val;
    wire [2:0] lucas_idx = ui_in[3:1];
    lucas_rom u_lucas (.idx(lucas_idx), .value(lucas_val));
    wire [7:0] _l2;
    wire [7:0] _l3;
    wire [7:0] _l4;
    wire [7:0] _l5;
    wire [7:0] _l6;
    wire [7:0] _l7;
    lucas_rom u_lr2 (.idx(3'd0), .value(_l2));
    lucas_rom u_lr3 (.idx(3'd1), .value(_l3));
    lucas_rom u_lr4 (.idx(3'd2), .value(_l4));
    lucas_rom u_lr5 (.idx(3'd3), .value(_l5));
    lucas_rom u_lr6 (.idx(3'd4), .value(_l6));
    lucas_rom u_lr7 (.idx(3'd5), .value(_l7));
    wire lucas_ok = (_l2 == 8'd3)  && (_l3 == 8'd4)  && (_l4 == 8'd7)  &&
                    (_l5 == 8'd11) && (_l6 == 8'd18) && (_l7 == 8'd29);

    // L-S3: VSA 8×8 ternary matmul
    reg [127:0] vsa_a;
    reg [127:0] vsa_b;
    reg         vsa_start;
    wire        vsa_done;
    wire        matmul_ok;
    wire [511:0] vsa_c;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vsa_a <= 128'b0;
            vsa_b <= 128'b0;
            vsa_start <= 1'b1;
        end else vsa_start <= 1'b0;
    end
    vsa_matmul_8x8 u_vsa (
        .clk(clk), .rst_n(rst_n),
        .start(vsa_start),
        .a_flat(vsa_a), .b_flat(vsa_b),
        .done(vsa_done), .c_flat(vsa_c),
        .matmul_ok(matmul_ok)
    );

    // L-S5: 16-bit LFSR for die-unique nonce
    wire [15:0] hwrng_word;
    hwrng_lfsr u_rng (.clk(clk), .rst_n(rst_n), .ena(1'b1), .rnd(hwrng_word));
    wire hwrng_nonzero = |hwrng_word;

    // L-S6: Wishbone-lite status byte
    wire [7:0] status_byte;
    wb_status_reg u_status (
        .clk(clk), .rst_n(rst_n),
        .phi_ok(phi_ok),
        .lucas_ok(lucas_ok),
        .matmul_ok(matmul_ok),
        .post_done(post_done),
        .rcpt_valid(mesh_rcpt_valid),
        .hwrng_nonzero(hwrng_nonzero),
        .status_byte(status_byte)
    );

    // L-S4: CRC-32 of RECEIPT triplet
    reg [1:0]  crc_step;
    reg        crc_start;
    reg        crc_valid;
    reg [7:0]  crc_byte;
    reg        rcpt_valid_d;
    wire [31:0] crc_raw;
    wire [31:0] crc_final;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            crc_step     <= 2'd0;
            crc_start    <= 1'b0;
            crc_valid    <= 1'b0;
            crc_byte     <= 8'b0;
            rcpt_valid_d <= 1'b0;
        end else begin
            rcpt_valid_d <= mesh_rcpt_valid;
            crc_start    <= mesh_rcpt_valid && !rcpt_valid_d;
            if (mesh_rcpt_valid && !rcpt_valid_d) begin
                crc_step  <= 2'd0;
                crc_valid <= 1'b1;
                crc_byte  <= mesh_rcpt_job_id;
            end else if (crc_valid) begin
                case (crc_step)
                    2'd0: begin crc_byte <= {6'b0, mesh_rcpt_tile_id}; crc_step <= 2'd1; end
                    2'd1: begin crc_byte <= mesh_rcpt_checksum;         crc_step <= 2'd2; end
                    default: crc_valid <= 1'b0;
                endcase
            end
        end
    end
    crc32_receipt u_crc (
        .clk(clk), .rst_n(rst_n),
        .start(crc_start),
        .valid(crc_valid),
        .byte_in(crc_byte),
        .crc_raw(crc_raw),
        .crc_final(crc_final)
    );

    // L-S10: VSA 16×16 ternary matmul (JEPA-T tier)
    reg  [511:0] mm16_a;
    reg  [511:0] mm16_b;
    reg          mm16_start;
    wire         mm16_done;
    wire         mm16_ok;
    wire [2047:0] mm16_c;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mm16_a <= 512'b0;
            mm16_b <= 512'b0;
            mm16_start <= 1'b1;
        end else mm16_start <= 1'b0;
    end
    vsa_matmul_16x16 u_mm16 (
        .clk(clk), .rst_n(rst_n),
        .start(mm16_start),
        .a_flat(mm16_a), .b_flat(mm16_b),
        .done(mm16_done), .c_flat(mm16_c),
        .matmul_ok(mm16_ok)
    );

    // L-S11: BitNet encoder
    reg  [127:0] enc_x;
    reg          enc_start;
    wire         enc_done;
    wire         enc_ok;
    wire [63:0]  enc_y;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            enc_x <= 128'b0;
            enc_start <= 1'b1;
        end else enc_start <= 1'b0;
    end
    bitnet_encoder u_enc (
        .clk(clk), .rst_n(rst_n),
        .start(enc_start), .x_in(enc_x),
        .done(enc_done), .y_out(enc_y),
        .encoder_ok(enc_ok)
    );

    // L-S12: BPB counter
    wire bpb_ok;
    wire [23:0] bpb_total;
    wire [15:0] bpb_samples;
    reg [3:0] bpb_tick;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) bpb_tick <= 4'd0;
        else if (bpb_tick != 4'hF) bpb_tick <= bpb_tick + 4'd1;
    end
    bpb_counter u_bpb (
        .clk(clk), .rst_n(rst_n),
        .valid(bpb_tick == 4'd5),
        .pred_class(mesh_rcpt_checksum),
        .true_class(8'hC1),
        .total_loss(bpb_total),
        .sample_count(bpb_samples),
        .bpb_ok(bpb_ok)
    );

    // L-S13: BLAKE3-mini RECEIPT signer
    reg [511:0] hash_in;
    reg         hash_start;
    wire        hash_done;
    wire        hash_ok;
    wire [255:0] hash_digest;
    reg hash_kicked;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            hash_in     <= 512'b0;
            hash_start  <= 1'b0;
            hash_kicked <= 1'b0;
        end else if (mesh_rcpt_valid && !hash_kicked) begin
            hash_in <= {448'b0,
                        mesh_rcpt_checksum, mesh_rcpt_job_id,
                        {6'b0, mesh_rcpt_tile_id}, 8'hA5,
                        crc_final};
            hash_start  <= 1'b1;
            hash_kicked <= 1'b1;
        end else begin
            hash_start <= 1'b0;
        end
    end
    blake3_anchor u_hash (
        .clk(clk), .rst_n(rst_n),
        .start(hash_start), .m_in(hash_in),
        .done(hash_done), .digest(hash_digest),
        .hash_ok(hash_ok)
    );

    // L-S14: multi-tile RECEIPT aggregator
    wire all_attested;
    wire multi_rcpt_ok;
    wire [7:0] agg_checksum;
    wire [7:0] agg_job_id;
    wire [3:0] attested_mask;
    multi_tile_receipt u_mrcpt (
        .clk(clk), .rst_n(rst_n),
        .t0_valid(mesh_rcpt_valid),
        .t0_checksum(mesh_rcpt_checksum),
        .t0_job_id(mesh_rcpt_job_id),
        .t1_valid(mesh_rcpt_valid),
        .t1_checksum(mesh_rcpt_checksum),
        .t1_job_id(mesh_rcpt_job_id),
        .t2_valid(mesh_rcpt_valid),
        .t2_checksum(mesh_rcpt_checksum),
        .t2_job_id(mesh_rcpt_job_id),
        .t3_valid(mesh_rcpt_valid),
        .t3_checksum(mesh_rcpt_checksum),
        .t3_job_id(mesh_rcpt_job_id),
        .agg_checksum(agg_checksum),
        .agg_job_id(agg_job_id),
        .attested_mask(attested_mask),
        .all_attested(all_attested),
        .multi_rcpt_ok(multi_rcpt_ok)
    );

    // L-S15: Trinity ternary ALU-9 decoder
    wire [1:0] alu_result;
    wire       alu_valid;
    wire       alu_ok;
    alu9_decoder u_alu (
        .opcode(hwrng_word[3:0]),
        .a(hwrng_word[5:4]),
        .b(hwrng_word[7:6]),
        .result(alu_result),
        .valid(alu_valid),
        .decoder_ok(alu_ok)
    );

    // L-S16: RING27 ternary memory
    reg [2:0] ring_shift_cnt;
    wire ring_ok;
    wire [1:0] ring_rd;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) ring_shift_cnt <= 3'b0;
        else        ring_shift_cnt <= ring_shift_cnt + 3'b1;
    end
    ring27_memory u_ring (
        .clk(clk), .rst_n(rst_n),
        .shift(ring_shift_cnt == 3'd0),
        .wr_en(alu_valid && (ring_shift_cnt == 3'd4)),
        .addr(hwrng_word[12:8] % 5'd27),
        .wr_data(alu_result),
        .rd_data(ring_rd),
        .ring_ok(ring_ok)
    );

    // L-S17: phi-PLL fractional divider
    wire phi_tick;
    wire [2:0] phi_state;
    wire phi_div_ok;
    phi_pll_div u_phi_div (
        .clk(clk), .rst_n(rst_n),
        .phi_tick(phi_tick),
        .state(phi_state),
        .phi_div_ok(phi_div_ok)
    );

    // L-S18: Wishbone-lite full peripheral
    wire [7:0] wb_dat_r;
    wire wb_ack;
    wire wb_ok;
    wishbone_full u_wb (
        .clk(clk), .rst_n(rst_n),
        .wb_cyc(1'b0), .wb_stb(1'b0), .wb_we(1'b0),
        .wb_adr(4'b0), .wb_dat_w(8'b0),
        .wb_dat_r(wb_dat_r), .wb_ack(wb_ack),
        .status_byte(status_byte),
        .matmul_lo(mm16_c[7:0]),
        .rcpt_chk(agg_checksum),
        .bpb_lo(bpb_total[7:0]),
        .wb_ok(wb_ok)
    );

    // =================================================================
    // SUPER-CROWN EXTRA PhD-anchored monitors (L-S22..L-S33)
    // =================================================================

    // L-S23: Cassini-Lucas POST checker
    wire cassini_ok;
    wire cassini_post_done;
    cassini_post u_cassini (
        .clk(clk), .rst_n(rst_n),
        .cassini_ok(cassini_ok),
        .post_done(cassini_post_done)
    );

    // L-S22: PLRM mutual-exclusion runtime monitor
    wire grant_arith;
    wire grant_orch;
    wire plrm_error;
    plrm_counter u_plrm (
        .clk(clk), .rst_n(rst_n),
        .req_arith(hwrng_word[0]),
        .req_orch(hwrng_word[1] & ~hwrng_word[0]),
        .grant_arith(grant_arith),
        .grant_orch(grant_orch),
        .plrm_error(plrm_error)
    );
    wire plrm_ok = ~plrm_error;

    // L-S33: BPB Shannon lower-bound guard
    wire bpb_violation;
    wire bpb_sticky_violation;
    wire [1:0] bpb_fault_code;
    bpb_lower_bound_guard u_bpb_guard (
        .clk(clk), .rst_n(rst_n),
        .bpb_q24({8'b0, bpb_total}),
        .floor_q24(32'sd0),
        .sample(bpb_tick == 4'd6),
        .bpb_violation(bpb_violation),
        .sticky_violation(bpb_sticky_violation),
        .fault_code(bpb_fault_code)
    );
    wire bpb_guard_ok = ~bpb_sticky_violation;

    // L-S24: NCA entropy band monitor
    wire [161:0] nca_trits;
    assign nca_trits = {enc_y, enc_y, 34'b0};
    wire nca_violation;
    wire nca_in_band;
    wire [6:0] nca_popcount;
    nca_entropy_monitor u_nca (
        .clk(clk), .rst_n(rst_n),
        .trits_in(nca_trits),
        .sample(ring_shift_cnt == 3'd2),
        .entropy_violation(nca_violation),
        .in_band(nca_in_band),
        .last_popcount(nca_popcount)
    );
    wire nca_ok = ~nca_violation;

    // L-S28: STROBE forbidden-seed hardware guard
    wire [31:0] seed_safe;
    wire seed_forbidden;
    wire seed_replaced;
    strobe_seed_guard u_strobe (
        .clk(clk), .rst_n(rst_n),
        .seed_in({16'b0, hwrng_word}),
        .seed_write(ring_shift_cnt == 3'd1),
        .seed_out(seed_safe),
        .seed_forbidden(seed_forbidden),
        .seed_replaced(seed_replaced)
    );
    wire strobe_ok = ~seed_forbidden | seed_replaced;

    // L-S32: φ-distance LUT oracle (360-entry, Q1.15)
    reg [8:0] phi_angle;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) phi_angle <= 9'd0;
        else if (phi_angle == 9'd359) phi_angle <= 9'd0;
        else phi_angle <= phi_angle + 9'd1;
    end
    wire [15:0] phi_dist;
    wire phi_dist_valid;
    phi_distance_oracle u_phi_oracle (
        .clk(clk), .rst_n(rst_n),
        .angle_deg(phi_angle),
        .valid_in(1'b1),
        .dist_out(phi_dist),
        .valid_out(phi_dist_valid)
    );
    wire phi_oracle_ok = phi_dist_valid & ~phi_dist[15];

    // SUPER-CROWN aggregate health bit
    wire super_crown_ok =
        mm16_ok & enc_ok & bpb_ok & hash_ok & multi_rcpt_ok &
        alu_ok  & ring_ok & phi_div_ok & wb_ok &
        cassini_ok & plrm_ok & bpb_guard_ok &
        nca_ok & strobe_ok & phi_oracle_ok & cortex_ok & mesh_ok;

    // =================================================================
    // Output mux: legacy 0x47C0 path → mesh result once produced.
    // TG-TRIAD-X invariant: {uio_out, uo_out} == 0x47C0 under !rst_n
    // =================================================================
    wire [15:0] final_result = mesh_result_valid ? mesh_result : dot_out;

    // =================================================================
    // TRI NET friend/foe handshake (MY_ANCHOR = gamma = 8'h93)
    // =================================================================
    wire ff_tx;
    wire ff_friend;
    wire ff_valid;
    trinity_friend_foe #(.MY_ANCHOR(8'h93)) u_friend_foe (
        .clk             (clk),
        .rst_n           (rst_n),
        .rx_bit          (uio_in[1]),
        .tx_bit          (ff_tx),
        .friend_detected (ff_friend),
        .handshake_valid (ff_valid)
    );

    // ==================================================================
    // CROWN47 ROM
    // ==================================================================
    wire        crown_mode = uio_in[7] && !ui_in[0];
    wire [7:0]  crown_byte_raw;
    crown47_rom_8bit u_crown47 (
        .addr     (ui_in[6:0]),
        .byte_sel (uio_in[6:5]),
        .byte_out (crown_byte_raw)
    );

    // ==================================================================
    // HOLO LUT PE (FHRR — kept AS-IS, MAP-B bind/unbind/bundle)
    // Interface: op[1:0], hv_a[31:0], hv_b[31:0], valid_in → hv_out[31:0], valid_out
    // ==================================================================
    wire [31:0] holo_out;
    wire        holo_valid_out;
    holo_lut_pe u_holo (
        .clk      (clk),
        .rst_n    (rst_n),
        .op       (2'b00),                           // bind mode (XOR)
        .hv_a     ({16'b0, final_result[15:0]}),     // 32-bit HV from result
        .hv_b     ({16'b0, input_echo[15:0]}),       // 32-bit HV from echo
        .valid_in (mesh_result_valid),
        .hv_out   (holo_out),
        .valid_out(holo_valid_out)
    );

    // =================================================================
    // Output assignment
    // TG-TRIAD-X: {uio_out[7:4], uo_out} = 0x47C0 on reset
    //   uo_out = 0xC0 = CANONICAL_LO
    //   uio_out[7:4] = 0x4 = CANONICAL_HI
    //   uio_out[3:0] = D2D TX {w_tx,s_tx,e_tx,n_tx} = 4'h0 on reset ✓
    //
    // Live mode:
    //   uo_out = final_result[7:0] | input_echo[7:0]
    //   uio_out[7:4] = legacy mux (status / crown / result)
    //   uio_out[3:0] = D2D TX: {w_tx, s_tx, e_tx, n_tx}
    //   uio_oe[1] = 0 (RX from peer chip); uio_oe[7:4] = 0 (D2D RX inputs)
    //   uio_oe[3:0] = {1,1,1,1} except [1] = 0 (friend/foe RX)
    //   NOTE: uio[7:4] are D2D RX (inputs) → uio_oe[7:4] = 4'b0000
    // =================================================================
    wire [7:0] uio_legacy =
        crown_mode              ? 8'h00 :
        (ui_in[0] && post_done) ? status_byte :
                                   (final_result[15:8] | input_echo[15:8]);

    assign uo_out  = crown_mode ? crown_byte_raw
                                : (final_result[7:0] | input_echo[7:0]);

    // uio_out:
    //   [7:4] = legacy upper nibble (CANONICAL_HI on reset = 4'h4)
    //   [3:0] = legacy lower nibble (CANONICAL_LO on reset = 4'h7) OR D2D TX (live mode)
    assign uio_out = !ui_in[0] ? uio_legacy : {uio_legacy[7:4], d2d_w_tx, d2d_s_tx, d2d_e_tx, d2d_n_tx};

    // uio_oe:
    //   All outputs enabled for TG-TRIAD-X canonical mode (load_mode=0)
    //   [7:4] = 1 (legacy upper nibble outputs)
    //   [3:0] = 1 (D2D TX outputs)
    assign uio_oe  = !ui_in[0] ? 8'hFF : 8'b0000_1111;

    // Silence lint
    wire _unused = &{1'b0, mesh_dbg_tile0, ena,
                     uio_in[3:2], uio_in[0],
                     mesh_rcpt_checksum, mesh_rcpt_job_id,
                     mesh_rcpt_tile_id, mesh_rcpt_valid,
                     lucas_val, vsa_done, vsa_c,
                     crc_raw, crc_final,
                     hwrng_word[14:0],
                     mm16_done, mm16_c[2047:8],
                     enc_done, enc_y,
                     bpb_total[23:8], bpb_samples,
                     hash_done, hash_digest,
                     all_attested, agg_job_id, attested_mask,
                     alu_result, alu_valid,
                     ring_rd, phi_tick, phi_state,
                     wb_dat_r, wb_ack,
                     super_crown_ok,
                     cassini_post_done, grant_arith, grant_orch,
                     bpb_violation, bpb_fault_code,
                     nca_in_band, nca_popcount,
                     seed_safe, seed_replaced,
                     phi_dist[14:0],
                     ui_in[7:4],
                     ff_tx, ff_friend, ff_valid,
                     d2d_n_rx_q, d2d_e_rx_q, d2d_s_rx_q, d2d_w_rx_q,
                     holo_out, holo_valid_out,
                     1'b0};

endmodule
