// Trinity Friend/Foe handshake — minimal serial anchor exchange
// Anchor: phi^2 + phi^-2 = 3 | DOI 10.5281/zenodo.19227877
// TRI NET inter-chip recognition: phi (8'hCF) + e (8'hAE) + gamma (8'h93)
module trinity_friend_foe #(
    parameter [7:0] MY_ANCHOR = 8'hCF  // phi default, override per chip
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       rx_bit,        // from neighbor uio
    output wire       tx_bit,        // to neighbor uio
    output wire       friend_detected,
    output wire       handshake_valid
);
    reg [2:0] tx_idx;
    reg [7:0] rx_shift;
    reg [2:0] rx_cnt;
    reg       hs_valid_r;
    reg       friend_r;

    // Sacred constants table
    localparam [7:0] PHI_C   = 8'hCF;
    localparam [7:0] EULER_C = 8'hAE;
    localparam [7:0] GAMMA_C = 8'h93;

    // TX: shift out MY_ANCHOR LSB-first, 8 cycles, then repeat
    assign tx_bit = MY_ANCHOR[tx_idx];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_idx     <= 3'd0;
            rx_shift   <= 8'd0;
            rx_cnt     <= 3'd0;
            hs_valid_r <= 1'b0;
            friend_r   <= 1'b0;
        end else begin
            tx_idx   <= tx_idx + 3'd1;
            rx_shift <= {rx_bit, rx_shift[7:1]};
            rx_cnt   <= rx_cnt + 3'd1;
            if (rx_cnt == 3'd7) begin
                hs_valid_r <= 1'b1;
                friend_r <= (rx_shift == PHI_C)   ||
                            (rx_shift == EULER_C) ||
                            (rx_shift == GAMMA_C);
            end
        end
    end

    assign friend_detected = friend_r;
    assign handshake_valid = hs_valid_r;
endmodule
