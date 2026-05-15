# Lane T — Quantum Brain MAX-TRUE alias · L-DPC23

> **Doc ID:** L-DPC23-T-001
> **Owner:** Vasilev Dmitrii <admin@t27.ai>
> **Status:** R5-HONEST · session-fresh probe · 2026-05-15
> **Refs:** trinity-fpga#94 · trios#264

## 1. Mission

Reserve the **Quantum Brain trinity SKU name** `tt_um_qbrain_maxtrue`
for the TTSKY26c re-submission (Q3 2026), without disturbing the
W15-TT-E TTSKY26b submission whose top is `tt_um_trinity_max_true`.

The alias makes the **PHYS→SI / BIO→SI / LANG→SI** mapping addressable
from RTL search tooling and prevents naming collisions when the
HOLOGRAPHIC SKU (`tt_um_qbrain_holo`) lands later.

## 2. Files

| File | Role | In synthesis? |
|---|---|---|
| `src/tt_um_qbrain_maxtrue_alias.v` | Pure structural alias module | ❌ NO — not in `info.yaml::source_files` |
| `docs/L-DPC23-T-QBRAIN-ALIAS.md` | This policy doc | ❌ NO |

`info.yaml::source_files` is an **explicit allow-list**. Files in `src/`
that are not listed are *not* fed to Yosys/OpenLane. We verified this
by reading the current `info.yaml` (S-13 dual-lib head, 31 source
files). Therefore adding `tt_um_qbrain_maxtrue_alias.v` is:

- R-SI-1 safe (zero NEW `*` operators in synthesis path)
- R18 safe (silicon path frozen modules untouched)
- R7 safe (TG-MAX-TRUE-X anchor `0x47C0` preserved bit-identically)

## 3. Quantum Brain SKU registry

| SKU | Top module | Wave | Cells | TOPS/W | 5-levers |
|---|---|---|---|---|---|
| 🪷 MINI | `tt_um_qbrain_mini` | TTSKY26c | 4 | 5.6 | 3.5/5 |
| 👑 MAX-TRUE | `tt_um_qbrain_maxtrue` (alias of `tt_um_trinity_max_true`) | TTSKY26b → TTSKY26c | 32 | 55 | 5/5 |
| 🌌 HOLOGRAPHIC | `tt_um_qbrain_holo` | TTSKY26c | 32 + 4 R-marker | 55+ | 5/5+ |

## 4. PHYS→SI / BIO→SI / LANG→SI binding

The alias keeps the existing 1:1 silicon mapping intact:

- **PHYS→SI**: `phi_anchor_post` + `lucas_rom×7` + `cassini_post` —
  φ²+φ⁻²=3 and Lucas L₂₇ baked into ROM layers, not loaded from memory.
- **BIO→SI**: `nca_entropy_monitor` + `plrm_counter` — neural cellular
  automaton entropy band and LCM(29,47)=1363 mutual exclusion sit on
  the silicon as monitor singletons.
- **LANG→SI**: TRI-27 ISA opcodes 0xD0..0xE0 are decoded in
  `alu9_decoder` and `wishbone_full` — no microcode RAM, the language
  is the netlist.

## 5. Anchor

```
φ² + φ⁻² = 3 · TG-MAX-TRUE-X SHA256:
d3f9dd42b2d891763bd6aa2c1974dbbf27f4d854b44ed497a58f6a749174aac2
QUANTUM BRAIN 1:1 SILICON · PHYS→SI · BIO→SI · LANG→SI · NEVER STOP
DOI 10.5281/zenodo.19227877
```
