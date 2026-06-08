// SPDX-License-Identifier: Apache-2.0
// t27/rtl_gen/sparse_skip.v
// SPARSE_SKIP Controller (Sacred opcode 0xE1)
// Skips zero/sparse computations for power savings

`default_nettype none
module sparse_skip (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [7:0]   opcode,         // 0xE1 = SPARSE_SKIP (full 8-bit)
    input  wire [15:0]  sparse_mask,    // Bitmask of sparse inputs (1 = zero)
    input  wire [15:0]  compute_mask,   // Active compute lanes
    input  wire [7:0]   threshold,      // Sparsity threshold (0-255)
    output reg  [15:0]  active_lanes,   // Lanes to compute
    output reg  [7:0]   skip_count,     // Number of lanes skipped
    output reg  [7:0]   efficiency,     // Compute efficiency (0-100)
    output reg         skip_mode       // Skip mode active
);

    // Skip mode states
    localparam SKIP_OFF   = 1'b0;
    localparam SKIP_ON    = 1'b1;

    reg [7:0]  population_count;
    reg [15:0] inverted_mask;
    reg        skip_enabled;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            active_lanes <= 16'hFFFF;
            skip_count <= 8'd0;
            efficiency <= 8'd100;
            skip_mode <= SKIP_OFF;
            skip_enabled <= 1'b0;
        end else begin
            // Check for opcode 0xE1
            if (opcode == 8'hE1)
                skip_enabled <= 1'b1;

            if (skip_enabled) begin
                // Count sparse (zero) inputs
                population_count = 8'd0;
                inverted_mask = 16'hFFFF;

                if (sparse_mask[0])  population_count = population_count + 1;
                if (sparse_mask[1])  population_count = population_count + 1;
                if (sparse_mask[2])  population_count = population_count + 1;
                if (sparse_mask[3])  population_count = population_count + 1;
                if (sparse_mask[4])  population_count = population_count + 1;
                if (sparse_mask[5])  population_count = population_count + 1;
                if (sparse_mask[6])  population_count = population_count + 1;
                if (sparse_mask[7])  population_count = population_count + 1;
                if (sparse_mask[8])  population_count = population_count + 1;
                if (sparse_mask[9])  population_count = population_count + 1;
                if (sparse_mask[10]) population_count = population_count + 1;
                if (sparse_mask[11]) population_count = population_count + 1;
                if (sparse_mask[12]) population_count = population_count + 1;
                if (sparse_mask[13]) population_count = population_count + 1;
                if (sparse_mask[14]) population_count = population_count + 1;
                if (sparse_mask[15]) population_count = population_count + 1;

                skip_count <= population_count;

                // Calculate efficiency (percent)
                efficiency <= (8'd100 - (population_count << 2));  // Approx: 100 - sparse*4

                // Check threshold and set skip mode
                if (population_count >= threshold) begin
                    skip_mode <= SKIP_ON;
                    active_lanes <= inverted_mask & ~sparse_mask;
                end else begin
                    skip_mode <= SKIP_OFF;
                    active_lanes <= compute_mask;
                end
            end
        end
    end

endmodule