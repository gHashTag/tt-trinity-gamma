# Trinity Gamma — 8x4 Neuromorphic Flagship

Largest sibling of the Trinity TTSKY26b triad. 32 tiles (8x4) neuromorphic accelerator with 8 cortical columns, 20-PE GF16 mesh, 24 SUPER-CROWN modules, 6 PhD-anchored monitors, and a 4-port die-to-die holographic mesh router.

## How it works

The design integrates several blocks around the canonical Trinity anchor:
- 8 cortical columns with LIF dynamics, BitNet b1.58 ternary MLP, GF16 dot4 projection, and sparse PE accumulator (~500 cells per column)
- GF16 mesh: 1 trinity_quad_mesh (16 PE) plus 1 trinity_mesh_2x2 (4 PE)
- 24 SUPER-CROWN modules: phi_anchor_post, 7 Lucas ROMs, vsa_matmul 8x8 and 16x16, BitNet encoder, BPB counter, Blake3 anchor, multi-tile receipt, CRC32 receipt, ALU9 decoder, ring27 memory, HW RNG LFSR, phi PLL divider, Wishbone status, full Wishbone, trinity master FSM, trinity_mesh_2x2, gf16_dot4
- 6 PhD-anchored monitors: cassini_post, plrm_counter, bpb_lower_bound_guard, nca_entropy_monitor, strobe_seed_guard, phi_distance_oracle
- 4-port die-to-die holographic mesh router (N/E/S/W) for multi-chip spike propagation
- Crown47 ROM encoding 47 fundamental constants in 24-bit pseudo-float

GF16 format: 1 sign + 6 exponent (bias=31) + 9 mantissa. All mantissa multiplies use shift-and-add (zero new standalone star operators in synthesisable RTL).

On reset the chip drives the canonical Trinity anchor 0x47C0 onto the output pins. This is the same constant emitted by the Phi (1x1) and Euler (8x2) siblings.

## How to test

After reset (ui_in = 0x00):
- uo_out  = 0xC0 (result low byte)
- uio_out = 0x47 (result high byte)

Combined: 0x47C0 = GF16(30.0) = dot4(1, 2, 3, 4) (1, 2, 3, 4).

To select packet path mode, drive ui_in[0] high. To probe the Lucas ROM, drive lucas_idx[2:0] on ui_in[3:1].

## External hardware

No external hardware required. The die-to-die mesh pins (uio_out[3:0] TX and uio_in[7:4] RX) are directly observable; in a single-die test they can be left unconnected.
