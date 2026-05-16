// SPDX-License-Identifier: Apache-2.0
// =============================================================================
// trinity_cortex_8col.v — 8-Column Neuromorphic Cortex Array
// =============================================================================
//
// TRI-1 GAMMA — MAX-TRUE NEUROMORPHIC FLAGSHIP (8x4 = 32 tiles)
// Author  : Dmitrii Vasilev <admin@t27.ai>
// Shuttle : TTSKY26b, sky130A
//
// Instantiates 8 × cortical_column modules on a shared 50 MHz clock.
// Sums spike outputs via a popcount tree (4-bit result for up to 8 spikes).
// Routes shared gf_in inputs with fan-out.
//
// Cell estimate: 8 × ~500 + popcount overhead ≈ 4100 cells
//
// R-SI-1: ZERO `*` operators. Popcount via carry-save adder tree (add only).
// Verilog-2005 strict: NO SystemVerilog, NO logic, one reg per line.
//
// Anchor: phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877
// =============================================================================

`default_nettype none
`timescale 1ns / 1ps

module trinity_cortex_8col (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        ena,
    // Shared GF16 inputs (broadcast to all columns)
    input  wire [3:0]  gf_in0,
    input  wire [3:0]  gf_in1,
    input  wire [3:0]  gf_in2,
    input  wire [3:0]  gf_in3,
    // Per-column stimulus (8 × 4-bit, packed 32-bit bus)
    input  wire [31:0] stim_bus,   // stim_bus[(4xi)+3:(4xi)] = stim for col i
    // Spike popcount output (0..8, 4-bit)
    output wire [3:0]  spike_count,
    // Per-column spike vector
    output wire [7:0]  spike_vec,
    // Cortex aggregate OK flag
    output wire        cortex_ok
);

    // -----------------------------------------------------------------------
    // 8 × cortical_column instances
    // -----------------------------------------------------------------------
    wire [7:0]  spike_raw;      // spike_raw[i] = spike from column i
    wire [7:0]  mem_dbg_0;
    wire [7:0]  mem_dbg_1;
    wire [7:0]  mem_dbg_2;
    wire [7:0]  mem_dbg_3;
    wire [7:0]  mem_dbg_4;
    wire [7:0]  mem_dbg_5;
    wire [7:0]  mem_dbg_6;
    wire [7:0]  mem_dbg_7;

    cortical_column u_col0 (
        .clk         (clk),
        .rst_n       (rst_n),
        .ena         (ena),
        .gf_in0      (gf_in0),
        .gf_in1      (gf_in1),
        .gf_in2      (gf_in2),
        .gf_in3      (gf_in3),
        .stim_in     (stim_bus[3:0]),
        .spike_out   (spike_raw[0]),
        .membrane_dbg(mem_dbg_0)
    );

    cortical_column u_col1 (
        .clk         (clk),
        .rst_n       (rst_n),
        .ena         (ena),
        .gf_in0      (gf_in0),
        .gf_in1      (gf_in1),
        .gf_in2      (gf_in2),
        .gf_in3      (gf_in3),
        .stim_in     (stim_bus[7:4]),
        .spike_out   (spike_raw[1]),
        .membrane_dbg(mem_dbg_1)
    );

    cortical_column u_col2 (
        .clk         (clk),
        .rst_n       (rst_n),
        .ena         (ena),
        .gf_in0      (gf_in0),
        .gf_in1      (gf_in1),
        .gf_in2      (gf_in2),
        .gf_in3      (gf_in3),
        .stim_in     (stim_bus[11:8]),
        .spike_out   (spike_raw[2]),
        .membrane_dbg(mem_dbg_2)
    );

    cortical_column u_col3 (
        .clk         (clk),
        .rst_n       (rst_n),
        .ena         (ena),
        .gf_in0      (gf_in0),
        .gf_in1      (gf_in1),
        .gf_in2      (gf_in2),
        .gf_in3      (gf_in3),
        .stim_in     (stim_bus[15:12]),
        .spike_out   (spike_raw[3]),
        .membrane_dbg(mem_dbg_3)
    );

    cortical_column u_col4 (
        .clk         (clk),
        .rst_n       (rst_n),
        .ena         (ena),
        .gf_in0      (gf_in0),
        .gf_in1      (gf_in1),
        .gf_in2      (gf_in2),
        .gf_in3      (gf_in3),
        .stim_in     (stim_bus[19:16]),
        .spike_out   (spike_raw[4]),
        .membrane_dbg(mem_dbg_4)
    );

    cortical_column u_col5 (
        .clk         (clk),
        .rst_n       (rst_n),
        .ena         (ena),
        .gf_in0      (gf_in0),
        .gf_in1      (gf_in1),
        .gf_in2      (gf_in2),
        .gf_in3      (gf_in3),
        .stim_in     (stim_bus[23:20]),
        .spike_out   (spike_raw[5]),
        .membrane_dbg(mem_dbg_5)
    );

    cortical_column u_col6 (
        .clk         (clk),
        .rst_n       (rst_n),
        .ena         (ena),
        .gf_in0      (gf_in0),
        .gf_in1      (gf_in1),
        .gf_in2      (gf_in2),
        .gf_in3      (gf_in3),
        .stim_in     (stim_bus[27:24]),
        .spike_out   (spike_raw[6]),
        .membrane_dbg(mem_dbg_6)
    );

    cortical_column u_col7 (
        .clk         (clk),
        .rst_n       (rst_n),
        .ena         (ena),
        .gf_in0      (gf_in0),
        .gf_in1      (gf_in1),
        .gf_in2      (gf_in2),
        .gf_in3      (gf_in3),
        .stim_in     (stim_bus[31:28]),
        .spike_out   (spike_raw[7]),
        .membrane_dbg(mem_dbg_7)
    );

    // -----------------------------------------------------------------------
    // Spike popcount tree (8 → 4-bit, max value = 8)
    // Stage 1: sum pairs → 2-bit half-sums (4 × 2-bit)
    // Stage 2: sum pairs → 3-bit quarter-sums (2 × 3-bit)
    // Stage 3: final 4-bit sum
    // R-SI-1: uses + (add), no *
    // -----------------------------------------------------------------------
    wire [1:0] pc_s1_0;
    wire [1:0] pc_s1_1;
    wire [1:0] pc_s1_2;
    wire [1:0] pc_s1_3;

    assign pc_s1_0 = {1'b0, spike_raw[0]} + {1'b0, spike_raw[1]};
    assign pc_s1_1 = {1'b0, spike_raw[2]} + {1'b0, spike_raw[3]};
    assign pc_s1_2 = {1'b0, spike_raw[4]} + {1'b0, spike_raw[5]};
    assign pc_s1_3 = {1'b0, spike_raw[6]} + {1'b0, spike_raw[7]};

    wire [2:0] pc_s2_0;
    wire [2:0] pc_s2_1;

    assign pc_s2_0 = {1'b0, pc_s1_0} + {1'b0, pc_s1_1};
    assign pc_s2_1 = {1'b0, pc_s1_2} + {1'b0, pc_s1_3};

    assign spike_count = {1'b0, pc_s2_0} + {1'b0, pc_s2_1};

    // -----------------------------------------------------------------------
    // Registered spike output for stable downstream logic
    // -----------------------------------------------------------------------
    assign spike_vec = spike_raw;

    // -----------------------------------------------------------------------
    // Cortex health flag: at least one column is alive (non-zero membrane)
    // -----------------------------------------------------------------------
    assign cortex_ok = |(mem_dbg_0 | mem_dbg_1 | mem_dbg_2 | mem_dbg_3 |
                         mem_dbg_4 | mem_dbg_5 | mem_dbg_6 | mem_dbg_7);

    // Suppress unused warnings
    wire _unused = &{1'b0, mem_dbg_0, mem_dbg_1, mem_dbg_2, mem_dbg_3,
                     mem_dbg_4, mem_dbg_5, mem_dbg_6, mem_dbg_7, 1'b0};

endmodule
