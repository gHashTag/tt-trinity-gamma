# D2D_PROTOCOL — Die-to-Die / Chip-to-Chip Communication

> Single-page index for how `tt-trinity-gamma` (γ-surface, 8×4) talks to
> its TRI-NET siblings (`tt-trinity-phi`, `tt-trinity-euler`) and to
> downstream tooling. **No new protocol is invented here.** This file
> consolidates the protocol artefacts already present in this repo so a
> third-party integrator can locate them in one hop.

Last reviewed: 2026-05-18.

## TL;DR

- **Authoritative wire spec:** [`docs/INTERCONNECT_PROTOCOL_V1.md`](docs/INTERCONNECT_PROTOCOL_V1.md)
  — Trinity Interconnect Protocol (TIP) v1.0, FROZEN at TTSKY26b. DOI
  [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877).
- **Cross-tile assembly:** [`docs/CROSS_TILE_INTERCONNECT.md`](docs/CROSS_TILE_INTERCONNECT.md)
  — TTSKY26b DevKit role assignment (Phi master / Euler compute slave /
  Gamma neuromorphic slave) and the canonical anchor `0x47C0`.
- **γ-side RTL endpoint:** `src/d2d_holo_mesh.v` — 4-port N/E/S/W
  router, `uio[3:0]=TX`, `uio[7:4]=RX`. `w_tx` is **LAYER-FROZEN** per
  PhD Theorem 36.1 R18.
- **Audit hooks:** `src/multi_tile_receipt.v`, `src/crc32_receipt.v`,
  `src/blake3_anchor.v`, `src/audit_log_ring_buffer.v`,
  `src/proof_trace_writer.v`.

This document is **descriptive**: every claim points to a file in this
tree. Anything that is plan-only is labelled as such.

## 1. γ-surface role on the D2D fabric

γ is the **8×4 compute / mesh-surface endpoint** of TRI-NET.

| Role on board | Chip | Tiles | TT slot |
|---------------|------|------:|---------|
| Master / POST gate | TRI-1 Phi (`tt-trinity-phi`) | 1×1 | #4914 |
| Compute slave | TRI-1 Euler (`tt-trinity-euler`) | 8×2 | #4915 |
| **Neuromorphic / mesh slave (this repo)** | **TRI-1 Gamma** | **8×4** | **#4913** |

γ specifically provides:

- The 4-port D2D router (`src/d2d_holo_mesh.v`) terminating the on-board
  mesh edges.
- The 32-PE compute substrate the mesh feeds (`src/trinity_quad_mesh.v`,
  `src/trinity_mesh_2x2.v`, `src/cortical_column.v`).
- The receipt / audit primitives that bind a decision made on this die
  to a tamper-evident record (see §3).
- The TG-TRIAD-X cross-die anchor `0x47C0` on `{uio_out, uo_out}` at
  reset (`sim/tb_canonical.v`).

The `w_tx` SYNC strobe (uio[3]) is gated by `layer_frozen` per PhD
Theorem 36.1 R18 — once the holographic attractor has converged,
spurious cross-die SYNC must not be re-broadcast. This is visible in
`src/d2d_holo_mesh.v` at the `w_tx <= sync_strobe_raw & ~layer_frozen;`
assignment.

## 2. Pin map (γ side)

Authoritative pin map: [`docs/PINOUT.md`](docs/PINOUT.md) and
[`docs/API.md`](docs/API.md).

| Pin | Dir | Name | Function (op mode) |
|-----|-----|------|---------------------|
| `uio[0]` | out | `n_tx` | North TX |
| `uio[1]` | out | `e_tx` | East TX |
| `uio[2]` | out | `s_tx` | South TX |
| `uio[3]` | out | `w_tx` | West TX — **SYNC strobe, LAYER-FROZEN** |
| `uio[4]` | in  | `n_rx` | North RX |
| `uio[5]` | in  | `e_rx` | East RX |
| `uio[6]` | in  | `s_rx` | South RX |
| `uio[7]` | in  | `w_rx` | West RX |

At reset (`ui_in[0]=0`, canonical mode), `{uio_out, uo_out} = 0x47C0`
on every chip in the triad.

## 3. Audit / route hooks (γ side)

The D2D path is not just a data mover — every packet that affects a
recorded decision is bound to an on-die receipt. RTL evidence in this
repo:

| Hook | RTL | Testbench |
|------|-----|-----------|
| Per-decision CRC32 receipt | `src/crc32_receipt.v` | `test/tb_proof_trace_writer.v` (writer path) |
| Long-horizon audit anchor | `src/blake3_anchor.v` | `sim/tb_canonical.v` (anchor on `{uio_out,uo_out}`) |
| Cross-tile receipt binding | `src/multi_tile_receipt.v` | `test/tb_proof_trace_writer.v`, `test/tb_audit_log_ring_buffer.v` |
| Tamper-evident audit log | `src/audit_log_ring_buffer.v` | `test/tb_audit_log_ring_buffer.v` |
| Proof trace writer | `src/proof_trace_writer.v` | `test/tb_proof_trace_writer.v` |
| 4-port D2D router (γ endpoint) | `src/d2d_holo_mesh.v` | `sim/tb_canonical.v` (LAYER-FROZEN check) |
| Local mesh + router | `src/trinity_mesh_2x2.v`, `src/trinity_router_2x2.v`, `src/trinity_quad_mesh.v` | `test/tb.v` (cocotb harness) |

These hooks are wired together in BENCHMARKS Demo 3
([`BENCHMARKS.md`](BENCHMARKS.md#demo-3--proof--audit-receipt--mesh-route)).

## 4. Protocol layers

The full layer breakdown is in
[`docs/INTERCONNECT_PROTOCOL_V1.md`](docs/INTERCONNECT_PROTOCOL_V1.md);
the summary that matters for γ-side integration:

| Layer | Where it lives | γ implementation |
|-------|----------------|------------------|
| Electrical (Wire A / B / C, 3.3 V CMOS) | `docs/INTERCONNECT_PROTOCOL_V1.md` §2 | TT slot board IO |
| Physical pin map | `docs/INTERCONNECT_PROTOCOL_V1.md` §3, `docs/PINOUT.md` | `src/tt_um_trinity_max_true.v` (top) |
| Logical state machine (master/slave) | `docs/INTERCONNECT_PROTOCOL_V1.md` §4 | Gamma is **slave** — accepts LOAD_MODE / SYNC_STROBE |
| Frame format | `docs/INTERCONNECT_PROTOCOL_V1.md` §5 | `ui_in[7:0]` packet path |
| Friend-foe handshake | `docs/INTERCONNECT_PROTOCOL_V1.md` §6 | POST status surface |
| D2D mesh transport | (γ-specific) | `src/d2d_holo_mesh.v` + neighbours |

## 5. What this document does **not** claim

- ❌ A new TIP version. v1.0 is FROZEN at TTSKY26b; v1.1+ is the
  forward-compat shim defined in
  [`docs/INTERCONNECT_PROTOCOL_V1.md`](docs/INTERCONNECT_PROTOCOL_V1.md) §1.3.
- ❌ Measured cross-die signal integrity. The 0x47C0 anchor is
  verified in **simulation** by `sim/tb_canonical.v` only;
  packaged-board measurements are pending silicon return.
- ❌ Forward error correction on the D2D fabric. The current router
  (`src/d2d_holo_mesh.v`) is a registered TX / latched RX stub; FEC is
  a future-wave item, not implemented.

## See also

- [`docs/INTERCONNECT_PROTOCOL_V1.md`](docs/INTERCONNECT_PROTOCOL_V1.md) — full wire spec
- [`docs/CROSS_TILE_INTERCONNECT.md`](docs/CROSS_TILE_INTERCONNECT.md) — board-level role assignment
- [`docs/PINOUT.md`](docs/PINOUT.md), [`docs/API.md`](docs/API.md) — γ pin / register map
- [`BENCHMARKS.md`](BENCHMARKS.md) — Demo 3: receipt + mesh route
- [`STATUS.md`](STATUS.md) — readiness gates
