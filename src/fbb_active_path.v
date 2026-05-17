// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/fbb_active_path.v
// Forward Body Bias (FBB) Active Path Control
// Sacred opcode: 0xF2
// Reduces leakage current by forward biasing transistor body
// Coq proof: FBBActive2.v

`default_nettype none
module fbb_active_path (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [3:0]   opcode,         // Must be 0xF2 for FBB
    input  wire [15:0]  path_id,        // Active path identifier
    input  wire        fbb_enable,     // Global FBB enable
    input  wire [7:0]   leakage_mon,    // Leakage current monitor
    input  wire        standby,        // Standby mode request
    output reg  [31:0] fbb_level,      // FBB voltage level (mV)
    output reg  [15:0] active_paths,   // Bitmask of active FBB paths
    output reg         leakage_ok,     // Leakage within limits
    output reg  [7:0]   fbb_status      // Status register
);

    // FBB levels in mV
    localparam FBB_OFF     = 16'd0;    // Disabled
    localparam FBB_LOW     = 16'd100;  // 0.1V (light FBB)
    localparam FBB_MED     = 16'd200;  // 0.2V (medium FBB)
    localparam FBB_HIGH    = 16'd300;  // 0.3V (strong FBB)
    localparam FBB_MAX     = 16'd400;  // 0.4V (maximum)

    // Leakage thresholds (arbitrary units)
    localparam LEAKAGE_LOW  = 8'd32;
    localparam LEAKAGE_HIGH = 8'd96;
    localparam LEAKAGE_CRIT = 8'd128;

    // Status bits
    localparam STS_OK      = 8'd1;   // FBB operating normally
    localparam STS_ADJUST  = 8'd2;   // Adjusting FBB level
    localparam STS_HIGH_LEAK = 8'd4; // High leakage detected
    localparam STS_CRIT    = 8'd8;   // Critical state
    localparam STS_STANDBY = 8'd16;  // In standby mode

    // Internal state
    reg [1:0] fbb_state;
    reg [31:0] fbb_timer;
    reg [15:0] path_history;
    reg fbb_enabled;
    reg [7:0] avg_leakage;

    integer i;

    // Opcode 0xF2: FBB control
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            fbb_level <= FBB_OFF;
            active_paths <= 16'h0000;
            leakage_ok <= 1'b1;
            fbb_status <= STS_OK;
            fbb_state <= 2'd0;
            fbb_timer <= 32'd0;
            path_history <= 16'h0000;
            fbb_enabled <= 1'b0;
            avg_leakage <= 8'd0;
        end else begin
            // Check for opcode 0xF2
            if (opcode == 4'h2) begin  // Lower nibble of 0xF2
                if (!fbb_enabled && fbb_enable) begin
                    fbb_enabled <= 1'b1;
                    fbb_state <= 2'd1;  // Enter active state
                end
            end

            // Leakage monitoring (R-SI-1: replace *3 with shift-add)
            avg_leakage <= (((avg_leakage<<1) + avg_leakage) + leakage_mon) >> 2;

            // Leakage threshold check
            if (avg_leakage >= LEAKAGE_CRIT) begin
                leakage_ok <= 1'b0;
                fbb_status <= STS_CRIT | STS_HIGH_LEAK;
            end else if (avg_leakage >= LEAKAGE_HIGH) begin
                leakage_ok <= 1'b1;
                fbb_status <= STS_HIGH_LEAK;
            end else begin
                leakage_ok <= 1'b1;
                if (!standby)
                    fbb_status <= STS_OK;
            end

            // Standby mode handling
            if (standby) begin
                fbb_status <= fbb_status | STS_STANDBY;
                // In standby, use minimum FBB
                if (fbb_level != FBB_LOW)
                    fbb_level <= FBB_LOW;
            end

            // FBB level control based on leakage
            case (fbb_state)
                2'd0: begin
                    // Disabled state
                    fbb_level <= FBB_OFF;
                    if (fbb_enable && opcode == 4'h2)
                        fbb_state <= 2'd1;
                end

                2'd1: begin
                    // Active state - adjust based on leakage
                    fbb_status <= STS_OK | STS_ADJUST;
                    if (avg_leakage >= LEAKAGE_HIGH) begin
                        if (fbb_level < FBB_MAX)
                            fbb_level <= fbb_level + 16'd50;
                    end else if (avg_leakage <= LEAKAGE_LOW) begin
                        if (fbb_level > FBB_LOW)
                            fbb_level <= fbb_level - 16'd50;
                        else if (fbb_level > FBB_OFF && standby)
                            fbb_level <= fbb_level - 16'd50;
                    end
                    fbb_timer <= 32'd100;
                    fbb_state <= 2'd2;
                end

                2'd2: begin
                    // Wait state
                    if (fbb_timer > 0)
                        fbb_timer <= fbb_timer - 1'd1;
                    else
                        fbb_state <= 2'd1;
                end

                default: fbb_state <= 2'd0;
            endcase

            // Path management (sacred opcode 0xF2)
            if (fbb_enabled && path_id != 16'd0) begin
                // Register path in active_paths
                if (path_id < 16)
                    active_paths[path_id] <= 1'b1;
                path_history <= path_history | (1'b1 << (path_id & 15));
            end

            // Clear disabled paths
            if (!fbb_enable) begin
                active_paths <= 16'h0000;
                fbb_level <= FBB_OFF;
                fbb_state <= 2'd0;
            end
        end
    end

    // FBB efficiency calculation (R-SI-1: use tri_mant_mul for squaring)
    wire [15:0] fbb_eff_prod;
    tri_mant_mul #(.W(8)) u_fbb_eff (
        .a(fbb_level[7:0]), .b(fbb_level[7:0]), .product(fbb_eff_prod)
    );
    wire [7:0] efficiency = fbb_eff_prod[15:8];

endmodule