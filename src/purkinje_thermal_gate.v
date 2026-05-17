// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/purkinje_thermal_gate.v
// Purkinje Thermal Gate (S-195)
// Biologically-inspired thermal regulation for neuromorphic workloads
// Reference: Purkinje cell dendritic calcium spike dynamics
// Coq proof: PurkinjeThermal.v (W45) - >=7 Qed lemmas

`default_nettype none
module purkinje_thermal_gate (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]  temp_sensor,    // 0-255 (simulating 0-100C)
    input  wire [15:0] spike_rate,     // Neural spike rate (Hz)
    input  wire        urgent,         // Urgent computation flag
    input  wire [3:0]  layer_id,       // Neuromorphic layer identifier
    output reg  [15:0] thermal_limit,  // Computed thermal limit
    output reg         gate_open,      // Gate open flag
    output reg  [7:0]  cooling_req,    // Cooling request (0-255)
    output reg  [3:0]  state           // Current thermal state
);

    // Thermal states
    localparam STATE_COOL    = 4'd0;
    localparam STATE_NORMAL  = 4'd1;
    localparam STATE_WARM    = 4'd2;
    localparam STATE_HOT     = 4'd3;
    localparam STATE_CRIT    = 4'd4;
    localparam STATE_EMERG   = 4'd5;

    // Temperature thresholds (Celsius * 2.56 for 0-255 range)
    localparam TEMP_COOL    = 8'd64;   // ~25C
    localparam TEMP_NORMAL  = 8'd128;  // ~50C
    localparam TEMP_WARM    = 8'd154;  // ~60C
    localparam TEMP_HOT     = 8'd180;  // ~70C
    localparam TEMP_CRIT    = 8'd205;  // ~80C

    // Purkinje dynamics parameters
    localparam CALCIUM_DECAY = 8'd4;      // Calcium spike decay rate
    localparam DENDRIC_DELAY = 8'd8;      // Dendritic delay (cycles)
    localparam SPIKE_HYSTERESIS = 16'd100; // Spike rate hysteresis

    reg [7:0] calcium_level;
    reg [15:0] dendritic_potential;
    reg [7:0] smoothed_temp;
    reg [31:0] gate_timer;
    reg urgent_override;

    integer i;

    // Main state machine
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_NORMAL;
            gate_open <= 1'b1;
            thermal_limit <= 16'd1000;
            cooling_req <= 8'd0;
            calcium_level <= 8'd0;
            dendritic_potential <= 16'd0;
            smoothed_temp <= TEMP_NORMAL;
            gate_timer <= 32'd0;
            urgent_override <= 1'b0;
        end else begin
            // Temperature smoothing (Purkinje-like adaptation) R-SI-1: *7 = <<3 - x
            smoothed_temp <= (((smoothed_temp<<3) - smoothed_temp) + temp_sensor) >> 3;

            // Dendritic potential integration
            if (spike_rate > SPIKE_HYSTERESIS) begin
                dendritic_potential <= dendritic_potential + (spike_rate >> 4);
                if (dendritic_potential > 16'd4000)
                    dendritic_potential <= 16'd4000;
            end else begin
                dendritic_potential <= dendritic_potential >> 1;
            end

            // Calcium level dynamics
            if (dendritic_potential > 16'd2000) begin
                calcium_level <= calcium_level + 8'd1;
                if (calcium_level > 8'd200)
                    calcium_level <= 8'd200;
            end else begin
                calcium_level <= calcium_level - CALCIUM_DECAY;
                if (calcium_level < CALCIUM_DECAY)
                    calcium_level <= 8'd0;
            end

            // Urgent computation override
            if (urgent && calcium_level < 8'd50) begin
                urgent_override <= 1'b1;
                gate_timer <= 32'd1000;  // Override for 1000 cycles
            end else if (gate_timer > 0) begin
                gate_timer <= gate_timer - 1'd1;
                if (gate_timer == 0)
                    urgent_override <= 1'b0;
            end

            // State transition logic
            case (state)
                STATE_COOL: begin
                    if (smoothed_temp >= TEMP_NORMAL)
                        state <= STATE_NORMAL;
                    gate_open <= 1'b1;
                    cooling_req <= 8'd0;
                end

                STATE_NORMAL: begin
                    if (smoothed_temp < TEMP_COOL)
                        state <= STATE_COOL;
                    else if (smoothed_temp >= TEMP_WARM)
                        state <= STATE_WARM;
                    gate_open <= 1'b1;
                    thermal_limit <= 16'd1000;
                    cooling_req <= 8'd0;
                end

                STATE_WARM: begin
                    if (smoothed_temp < TEMP_NORMAL)
                        state <= STATE_NORMAL;
                    else if (smoothed_temp >= TEMP_HOT)
                        state <= STATE_HOT;

                    // Purkinje gate modulation
                    if (calcium_level > 8'd30) begin
                        gate_open <= 1'b0;
                        thermal_limit <= 16'd500;
                        cooling_req <= 8'd64;
                    end else begin
                        gate_open <= 1'b1;
                        thermal_limit <= 16'd800;
                        cooling_req <= 8'd32;
                    end
                end

                STATE_HOT: begin
                    if (smoothed_temp < TEMP_WARM)
                        state <= STATE_WARM;
                    else if (smoothed_temp >= TEMP_CRIT)
                        state <= STATE_CRIT;

                    gate_open <= urgent_override;
                    thermal_limit <= 16'd300;
                    cooling_req <= 8'd128;

                    // Dendritic inhibition
                    if (dendritic_potential > 16'd1000)
                        dendritic_potential <= dendritic_potential >> 2;
                end

                STATE_CRIT: begin
                    if (smoothed_temp < TEMP_HOT)
                        state <= STATE_HOT;
                    else if (smoothed_temp >= 8'd230)  // ~90C
                        state <= STATE_EMERG;

                    gate_open <= urgent_override;
                    thermal_limit <= 16'd100;
                    cooling_req <= 8'd200;
                end

                STATE_EMERG: begin
                    if (smoothed_temp < TEMP_CRIT)
                        state <= STATE_CRIT;

                    gate_open <= 1'b0;
                    thermal_limit <= 16'd0;
                    cooling_req <= 8'd255;
                end

                default: state <= STATE_NORMAL;
            endcase
        end
    end

    // Layer-specific thermal coefficients (neuromorphic layers)
    always @(*) begin
        case (layer_id)
            4'd0: ;  // Input layer: no special handling
            4'd1: begin
                // Conv layer: higher heat
                if (state == STATE_WARM)
                    cooling_req = cooling_req + 8'd16;
            end
            4'd2: begin
                // LSTM layer: moderate heat
                if (state == STATE_HOT)
                    cooling_req = cooling_req + 8'd8;
            end
            4'd3: begin
                // Attention layer: high heat (VSA operations)
                if (state >= STATE_WARM)
                    cooling_req = cooling_req + 8'd24;
            end
            default: ;
        endcase
    end

endmodule