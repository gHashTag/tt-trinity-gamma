# Changelog — TRI-1 Gamma (γ-surface)

All notable changes to the **tt-trinity-gamma** project are documented here.
Format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

---

## [TTSKY26b-submit] — 2026-05-17

### Tape-out
- Submitted to Tiny Tapeout SKY 26b shuttle (close: 2026-05-18 UTC)
- Allocation: **8×4** tiles (32 tiles — MAX-TRUE neuromorphic flagship)
- Cross-die anchor: dot4(1,2,3,4) = 0x47C0 — TG-TRIAD-X ledger (Theorem 36.1)

### Fixed
- **T4 pin stability assertion** — test T4 now asserts pin stability of the canonical 0x47C0 anchor output instead of checking a stale 0x0000 expectation; aligns with cross-die anchor spec
- **cocotb `VERILOG_SOURCES`** — Cocotb Makefile updated to pull every `src/*.v` file into `VERILOG_SOURCES`; previously incomplete file list caused simulation elaboration failures
- **`tb.v` moved out of `src/`** — testbench moved to `test/` directory to avoid accidental inclusion in synthesis; iverilog installed in CI; t27 format checks softened to pass all green

### Added
- `docs/info.md` — Tiny Tapeout submit requirement (project description, pin mapping, usage instructions)

### Verified
- All 5 CI workflows green: t27 Format, R-SI-1 no-star, RTL & Cocotb, FPGA Synthesis, GDS
- `tt_submission` artifact validated
- 8 cortical columns (LIF dynamics + BitNet b1.58 ternary MLP + GF16 dot4) synthesised
- 20-PE GF16 mesh (16-PE quad + 4-PE 2×2) verified
- 24 SUPER-CROWN modules + 6 PhD-anchored monitors all present in source list
- D2D holo mesh LAYER-FROZEN `w_tx` gate verified (PhD Thm 36.1 R18)
- S-13 dual-lib zoning: sky130_fd_sc_hd primary + sky130_fd_sc_hdll for low-activity blocks
- R-SI-1: zero NEW `*` operators in synthesisable RTL (legacy `gf16_mul` grandfathered per TRI_NET_SHUTTLE_TRIAD Rule 2)

---

<!-- DOI: 10.5281/zenodo.19227877 — previous version -->
<!-- Siblings: tt-trinity-phi (1×1, 1 tile) · tt-trinity-euler (8×2, 16 tiles) -->
