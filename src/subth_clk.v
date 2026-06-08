// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/subth_clk.v
// Subthreshold Clock Generator (Sacred opcode 0xE5)
// Low-power clock gating and frequency scaling

`default_nettype none
module subth_clk (
    input  wire        clk_in,         // Main clock input
    input  wire        rst_n,
    input  wire [7:0]   opcode,         // 0xE5 = SUBTH_CLK (full 8-bit)
    input  wire [2:0]   divider,        // Clock divider (0=1x, 1=2x, 2=4x, 3=8x)
    input  wire        enable_gate,    // Enable clock gating
    input  wire [7:0]   duty_cycle,     // Duty cycle (50-200, 100=50%)
    output reg  [7:0]   clk_out,        // Clock outputs (8-phase)
    output reg         gate_active,    // Gate active flag
    output reg  [7:0]   clk_freq        // Frequency indicator
);

    // Frequency multipliers
    localparam FREQ_1X = 8'd1;
    localparam FREQ_2X = 8'd2;
    localparam FREQ_4X = 8'd4;
    localparam FREQ_8X = 8'd8;

    // Phase counter
    reg [2:0] phase_counter;
    reg [15:0] cycle_counter;

    always @(posedge clk_in or negedge rst_n) begin
        if (!rst_n) begin
            phase_counter <= 3'd0;
            cycle_counter <= 16'd0;
            clk_out <= 8'h00;
            gate_active <= 1'b0;
            clk_freq <= FREQ_1X;
        end else begin
            cycle_counter <= cycle_counter + 1;

            // Check for opcode 0xE5
            if (opcode == 8'hE5) begin
                gate_active <= enable_gate;

                // Update frequency based on divider
                case (divider)
                    3'd0: clk_freq <= FREQ_1X;
                    3'd1: clk_freq <= FREQ_2X;
                    3'd2: clk_freq <= FREQ_4X;
                    3'd3: clk_freq <= FREQ_8X;
                    default: clk_freq <= FREQ_1X;
                endcase
            end

            // Clock generation
            if (!gate_active) begin
                clk_out <= 8'h00;
            end else begin
                phase_counter <= phase_counter + 1;

                case (phase_counter)
                    3'd0: clk_out[0] <= ~clk_out[0];
                    3'd1: clk_out[1] <= ~clk_out[1];
                    3'd2: clk_out[2] <= ~clk_out[2];
                    3'd3: clk_out[3] <= ~clk_out[3];
                    3'd4: clk_out[4] <= ~clk_out[4];
                    3'd5: clk_out[5] <= ~clk_out[5];
                    3'd6: clk_out[6] <= ~clk_out[6];
                    3'd7: clk_out[7] <= ~clk_out[7];
                endcase
            end
        end
    end

endmodule