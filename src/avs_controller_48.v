// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/avs_controller_48.v
// AVS-48 Adaptive Voltage Controller (W36)
// 48 voltage islands, 4 levels each: 0.75V, 0.85V, 0.95V, 1.05V
// 2-bit per island, 3 banks × 16 islands
// phi^2 + phi^-2 = 3 | W36 Lane W

`default_nettype none
module avs_controller_48 (
    input  wire clk,
    input  wire rst_n,
    input  wire [95:0] voltage_target,  // 48 × 2-bit target
    input  wire [3:0]  reconf_trigger,     // Reconfig trigger
    output reg  [95:0] voltage_sel,       // Current selection
    output reg  [7:0]  status              // Controller status
);

    // Voltage levels (2-bit encoding)
    localparam V_750MV = 2'd0;  // Near-retention (floor)
    localparam V_850MV = 2'd1;  // Cruise (nominal)
    localparam V_950MV = 2'd2;  // Active (high perf)
    localparam V_1050MV = 2'd3; // Burst (maximum)

    // Island bank structure: 3 banks × 16 islands
    localparam NUM_BANKS = 3;
    localparam ISLANDS_PER_BANK = 16;
    localparam TOTAL_ISLANDS = 48;

    // Reconfiguration state machine
    reg [2:0]  state;
    reg [5:0]  reconf_counter;
    reg [5:0]  settle_counter;
    reg        reconf_active;

    // Wake-up latency: 8 cycles @ 400 MHz = 20 ns
    localparam RECONF_CYCLES = 4;
    localparam SETTLE_CYCLES = 4;
    localparam TOTAL_CYCLES = RECONF_CYCLES + SETTLE_CYCLES;

    // Island grouping for bank-level updates
    wire [15:0] bank0_islands = voltage_sel[15:0];
    wire [15:0] bank1_islands = voltage_sel[31:16];
    wire [15:0] bank2_islands = voltage_sel[47:32];

    // Per-bank power calculation (simplified)
    wire [7:0] bank0_power = calc_bank_power(bank0_islands);
    wire [7:0] bank1_power = calc_bank_power(bank1_islands);
    wire [7:0] bank2_power = calc_bank_power(bank2_islands);

    // Total power estimate
    wire [9:0] total_power = bank0_power + bank1_power + bank2_power;

    // Helper: calculate bank power from voltage selections
    function [7:0] calc_bank_power;
        input [15:0] island_sel;
        reg [7:0] power;
        integer i;
        begin
            power = 8'd0;
            for (i = 0; i < 16; i = i + 1) begin
                case ({island_sel[2*i+1], island_sel[2*i]})
                    2'd0: power = power + 8'd5;   // 0.75V: 5 mW
                    2'd1: power = power + 8'd10;  // 0.85V: 10 mW
                    2'd2: power = power + 8'd20;  // 0.95V: 20 mW
                    2'd3: power = power + 8'd40;  // 1.05V: 40 mW
                    default: power = power;
                endcase
            end
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= 3'd0;
            reconf_counter <= 6'd0;
            settle_counter <= 6'd0;
            reconf_active <= 1'b0;
            voltage_sel <= {TOTAL_ISLANDS{1'b0}};
            status <= 8'd0;
        end else begin
            case (state)
                3'd0: begin  // Idle
                    reconf_active <= 1'b0;
                    status[7:4] <= 4'd0;  // Bank status
                    status[3:0] <= 4'd1;  // Ready

                    if (reconf_trigger != 4'd0) begin
                        state <= 3'd1;
                        reconf_active <= 1'b1;
                        reconf_counter <= 6'd0;
                    end
                end

                3'd1: begin  // Apply new voltage targets
                    voltage_sel <= voltage_target;
                    reconf_counter <= reconf_counter + 1'd1;
                    status[3:0] <= 4'd2;  // Reconfiguring

                    if (reconf_counter >= RECONF_CYCLES) begin
                        reconf_counter <= 6'd0;
                        state <= 3'd2;
                    end
                end

                3'd2: begin  // Wait for PLL settle
                    settle_counter <= settle_counter + 1'd1;
                    status[3:0] <= 4'd3;  // Settling

                    if (settle_counter >= SETTLE_CYCLES) begin
                        settle_counter <= 6'd0;
                        state <= 3'd3;
                    end
                end

                3'd3: begin  // Validate and update status
                    status[7:4] <= 4'd0;  // Bank ready
                    status[3:0] <= 4'd4;  // Done

                    if (reconf_trigger == 4'd0) begin
                        state <= 3'd0;
                    end
                end

                default: state <= 3'd0;
            endcase
        end
    end

    // Bank-level health monitoring
    wire bank0_healthy = voltage_sel[15:0] != 16'hFFFF;
    wire bank1_healthy = voltage_sel[31:16] != 16'hFFFF;
    wire bank2_healthy = voltage_sel[47:32] != 16'hFFFF;
    wire all_banks_healthy = bank0_healthy && bank1_healthy && bank2_healthy;

endmodule
