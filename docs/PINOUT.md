# PINOUT — TRI-1 Gamma (tt_um_trinity_max_true)

**Project:** TRI-1 Gamma — MAX-TRUE NEUROMORPHIC FLAGSHIP 32-tile 8-column  
**Tile:** 8×4 (32 tiles) · Tiny Tapeout SKY130A (TTSKY26b, slot #4913)  
**Top module:** `tt_um_trinity_max_true`  
**Clock:** 50 MHz · **Reset:** active-low `rst_n`  
**Canonical anchor:** `0x47C0` on `{uio_out[7:0], uo_out[7:0]}` after reset (Theorem 36.1, TG-TRIAD-X)

> Cross-tile interconnect details: see [`docs/CROSS_TILE_INTERCONNECT.md`](CROSS_TILE_INTERCONNECT.md)

---

## Pin Table

```
 ┌─────────────────────────────────────────────────────────────────────────────┐
 │           TRI-1 Gamma (tt_um_trinity_max_true) — 8×4 tiles (32)            │
 │                                                                             │
 │  PIN       DIR    SIGNAL / FUNCTION                                         │
 │  ────────  ─────  ──────────────────────────────────────────────────────    │
 │  ui[0]     IN     load_mode                                                 │
 │                     0 = canonical mode: 0x47C0 on {uio_out,uo_out}          │
 │                         + status_byte; crown_mode via uio[7]                │
 │                     1 = packet path + status_byte output                    │
 │  ui[1]     IN     lucas_idx[0] — Lucas ROM L_n address bit 0               │
 │  ui[2]     IN     lucas_idx[1] — Lucas ROM L_n address bit 1               │
 │  ui[3]     IN     lucas_idx[2] — Lucas ROM L_n address bit 2               │
 │  ui[4]     IN     (unused — tie low)                                        │
 │  ui[5]     IN     (unused — tie low)                                        │
 │  ui[6]     IN     crown_addr[6] — MSB of 7-bit Crown ROM address            │
 │                     (lower 6 bits supplied via prior lane load)             │
 │  ui[7]     IN     (unused — tie low)                                        │
 │  ────────  ─────  ──────────────────────────────────────────────────────    │
 │  uo[0]     OUT    result[0]  — canonical 0x47C0[0]  (default = 0)          │
 │  uo[1]     OUT    result[1]  — canonical 0x47C0[1]  (default = 0)          │
 │  uo[2]     OUT    result[2]  — canonical 0x47C0[2]  (default = 0)          │
 │  uo[3]     OUT    result[3]  — canonical 0x47C0[3]  (default = 0)          │
 │  uo[4]     OUT    result[4]  — canonical 0x47C0[4]  (default = 0)          │
 │  uo[5]     OUT    result[5]  — canonical 0x47C0[5]  (default = 0)          │
 │  uo[6]     OUT    result[6]  — canonical 0x47C0[6]  (default = 1)          │
 │  uo[7]     OUT    result[7]  — canonical 0x47C0[7]  (default = 1)          │
 │  ────────  ─────  ──────────────────────────────────────────────────────    │
 │  uio[0]    OUT    D2D n_tx — North TX: spike_count[3] activity bit          │
 │  uio[1]    OUT    D2D e_tx — East TX:  spike_count[0] activity bit          │
 │  uio[2]    OUT    D2D s_tx — South TX: GF16 route tag bit                  │
 │  uio[3]    OUT    D2D w_tx — West TX SYNC strobe (LAYER-FROZEN gated,       │
 │                     PhD Theorem 36.1 R18)                                   │
 │  uio[4]    IN     D2D n_rx — North RX (input from peer die)                │
 │  uio[5]    IN     D2D e_rx — East RX  (input from peer die)                │
 │  uio[6]    IN     D2D s_rx — South RX (input from peer die)                │
 │  uio[7]    IN     D2D w_rx — West RX  (input from peer die)                │
 │                     doubles as: crown_mode enable when high + load_mode=0   │
 └─────────────────────────────────────────────────────────────────────────────┘
```

### uio direction note

`uio[3:0]` are **outputs** (D2D TX). `uio[7:4]` are **inputs** (D2D RX from peer dies).  
The TT `uio_oe` register must be set: `uio_oe = 8'b0000_1111` (lower nibble = output).

### Canonical default: 0x47C0

```
  {uio_out[7:0], uo_out[7:0]} = 16'h47C0
  Binary: 0100_0111_1100_0000
  Note: uio_out[7:0] in canonical mode = high byte of result register.
        D2D routing takes over uio_out[3:0] in operational mode.
  Theorem 36.1 cross-die anchor: φ² + φ⁻² = 3
  Shared by all three Triad chips: Phi (#4914), Euler (#4915), Gamma (#4913)
```

---

## Pin Function Details

| Pin | Signal | Direction | Notes |
|-----|--------|-----------|-------|
| ui[0] | `load_mode` | IN | Core mode select. 0 = canonical 0x47C0 default, crown_mode if uio[7]=1. 1 = packet path + status_byte output. |
| ui[1] | `lucas_idx[0]` | IN | LSB of Lucas ROM address. Selects L₂..L₇. |
| ui[2] | `lucas_idx[1]` | IN | Mid bit of Lucas index. |
| ui[3] | `lucas_idx[2]` | IN | MSB of Lucas index. |
| ui[4] | (unused) | IN | Tie low. Reserved for future cortical column control. |
| ui[5] | (unused) | IN | Tie low. Reserved for future BPB threshold. |
| ui[6] | `crown_addr[6]` | IN | MSB of 7-bit Crown47 ROM address (75 PhD constants + 47 Crown constants). |
| ui[7] | (unused) | IN | Tie low. |
| uo[7:0] | `result[7:0]` | OUT | Low byte of 16-bit mesh result. Canonical: `0xC0`. Post-FSM: GF16 mesh output or neuromorphic spike aggregate. |
| uio[0] | `D2D n_tx` | OUT | North D2D TX: spike_count[3] activity bit from cortical columns. |
| uio[1] | `D2D e_tx` | OUT | East D2D TX: spike_count[0] activity bit. |
| uio[2] | `D2D s_tx` | OUT | South D2D TX: GF16 route tag bit from `d2d_holo_mesh`. |
| uio[3] | `D2D w_tx` | OUT | West D2D TX SYNC strobe. **LAYER-FROZEN** per PhD Theorem 36.1 R18 — `w_tx` gate is combinatorially disabled in rtl; see `d2d_holo_mesh.v`. |
| uio[4] | `D2D n_rx` | IN | North D2D RX: receives activation from Euler north port. |
| uio[5] | `D2D e_rx` | IN | East D2D RX: receives activation from Euler east port. |
| uio[6] | `D2D s_rx` | IN | South D2D RX. |
| uio[7] | `D2D w_rx` / `crown_mode` | IN | West D2D RX from peer die. **Also:** when high with `load_mode=0`, enables Crown ROM access mode. |

---

## Clock and Reset Specification

| Parameter | Value |
|-----------|-------|
| Clock frequency | 50 MHz (target) |
| Clock period | 20 ns |
| Reset polarity | Active-low (`rst_n`) |
| Reset minimum pulse | 2 clock cycles minimum |
| Reset release | Synchronous release recommended |
| Post-reset latency | ≤ 1 clock cycle to assert 0x47C0 |
| Cell budget | ~34 100 cells estimated (~4 100 neuromorphic + ~30 000 SUPER-CROWN) |
| Max tile footprint | 8×4 = 32 tiles, 0.704 mm² SKY130A |

---

## Bring-Up Sequence

```
Step 1 — RESET
  Assert rst_n=0 for ≥ 4 clock cycles (80 ns at 50 MHz).
  Hold ui[7:0] = 0x00, uio[7:4] = 0x0 (RX inputs driven low) during reset.
  uio_oe = 8'b0000_1111 (configure lower nibble as outputs).

Step 2 — CHECK CANONICAL ANCHOR (0x47C0)
  Release rst_n=1. Wait 1 clock cycle (20 ns).
  Read {uio_out[7:0], uo_out[7:0]}.
  Expected: 0x47C0
  If mismatch → FAULT. Gamma chip not passing POST gate.
  Note: uio_out in canonical mode is 0x47 (high byte of 0x47C0);
        in operational D2D mode uio[3:0] carries TX spike bits.

Step 3 — POST (Power-On Self-Test)
  Set load_mode=0, lucas_idx={0,0,0} (L₂).
  Verify 0x47C0 anchor stable (≥ 3 clock cycles).
  Optionally probe Crown47 ROM: set uio[7]=1 (crown_mode), ui[6]=addr[6].
  POST COMPLETE when anchor is stable.

Step 4 — OPERATIONAL MODE (neuromorphic slave)
  Phi (master) enables cross-tile handshake via board mux.
  Euler sends activation results to Gamma D2D RX (uio[7:4]).
  Gamma d2d_holo_mesh routes incoming tokens into cortical columns.
  8 LIF cortical columns integrate; spike_count output drives D2D TX (uio[3:0]).
  Consensus φ-spiral: aggregate spike_count fed back to Phi for next token.

Step 5 — CROSS-TILE SYNC
  See CROSS_TILE_INTERCONNECT.md for full 3-wire handshake protocol.
  Gamma role: NEUROMORPHIC SLAVE (receives from Euler, returns spikes to Phi).
```

---

## Cortical Column Architecture

| Column Index | LIF Parameters | Input Projection |
|-------------|----------------|-----------------|
| col[0]..col[7] | 8-bit membrane potential, BitNet MLP hidden layer | GF16 dot4 input projection |

- 8 columns × ~500 cells = ~4 100 cortical cells total
- Spike output: `spike_count[7:0]` aggregated from all columns
- `spike_count[3]` → `uio[0]` (D2D n_tx); `spike_count[0]` → `uio[1]` (D2D e_tx)

## PhD Monitors

| Monitor | Function |
|---------|----------|
| `cassini_post` | Cassini POST verification |
| `plrm_counter` | PLRM theorem counter |
| `bpb_lower_bound_guard` | BPB lower bound guard |
| `nca_entropy_monitor` | NCA entropy monitor |
| `strobe_seed_guard` | Strobe seed integrity guard |
| `phi_distance_oracle` | φ-distance oracle for spiral consensus |

## D2D Dual-Lib Note (S-13)

Primary standard-cell library: `sky130_fd_sc_hd`.  
Low-activity blocks (`lucas_rom×7`, `crc32_receipt`, `blake3_anchor`, `gf16_mul`) targeted for `sky130_fd_sc_hdll` zoning — expected ~30% static leakage reduction.  
See `docs/L-DPC22-K-DUAL-LIB.md`.

---

## Related Documents

- [`docs/CROSS_TILE_INTERCONNECT.md`](CROSS_TILE_INTERCONNECT.md) — Cross-tile interconnect spec for Phi/Euler/Gamma DevKit board
- `docs/L-DPC22-K-DUAL-LIB.md` — Dual standard-cell library zoning specification
- DOI: [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877) — Trinity Stack provenance
- Sibling: [TRI-1 Phi (#4914)](https://tinytapeout.com/runs/ttsky26b/tt_um_trinity_nano) — φ-anchor 1×1 (master)
- Sibling: [TRI-1 Euler (#4915)](https://tinytapeout.com/runs/ttsky26b/tt_um_ghtag_trinity_gf16) — e-engine 8×2 (compute slave)
