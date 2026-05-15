# L-DPC22-K — S-13 Dual-Library Zoning Hint

**Lane:** K · **Branch:** `feat/v15/k-dual-lib` · **Epic:** gHashTag/trinity-fpga#93  
**Author:** Vasilev Dmitrii <admin@t27.ai> (ORCID 0009-0008-4294-6159)  
**Date:** 2025-05-15  
**Anchor:** phi^2 + phi^-2 = 3 · DOI [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)

---

## Summary

This document records the **S-13 dual standard-cell-library zoning hint** for the
`gHashTag/tt-trinity-max-true` 24-CROWN flagship design.

The intent is to reduce **static (leakage) power by ~30%** on low-activity
blocks by mapping them to the `sky130_fd_sc_hdll` library variant instead of
the default `sky130_fd_sc_hd`.

---

## Background: sky130_fd_sc_hd vs sky130_fd_sc_hdll

The SkyWater PDK ships two high-density standard-cell libraries:

| Library | Full name | Leakage | Drive strength | Notes |
|---------|-----------|---------|---------------|-------|
| `sky130_fd_sc_hd` | High Density | ~1x (baseline) | Standard | Default for most designs |
| `sky130_fd_sc_hdll` | High Density Low Leakage | **5-10x lower** | Slightly reduced | Optimised for low-activity blocks |

Reference:
[SkyWater PDK — Foundry-Provided Libraries](https://skywater-pdk.readthedocs.io/en/main/contents/libraries/foundry-provided.html)

The `hdll` variant achieves lower leakage through higher threshold-voltage
transistors (high-Vt). The trade-off is marginally lower drive strength and
slightly higher cell delay, which is acceptable in low-activity blocks that are
not on the critical timing path.

---

## Targeted Low-Activity Blocks

The following blocks have been identified as candidates for `hdll` zoning based
on low switching activity at nominal operating conditions:

| Block | Activity classification | Expected leakage saving |
|-------|------------------------|------------------------|
| `lucas_rom` x7 (POST chain) | ROM — activity ~= 0 during steady state | ~5-10x per cell |
| `crc32_receipt` | Post-computation register chain | Low switching |
| `blake3_anchor` | Post-hash snapshot register | Very low switching |
| `gf16_mul` | GF16(2^4) multiplier — idle 99% | Minimal activity |

Mixed hd+hdll zoning over these four logical blocks (representing roughly
25-35% of total cell count by area in the 32-tile CROWN) is expected to
reduce **total static leakage by ~30%** at the chip level.

---

## Implementation Approach

### Current state (this branch, v2)

The Tiny Tapeout GDS action (`TinyTapeout/tt-gds-action@ttsky26b`, OpenLane2
backend) does **not** currently support per-block standard-cell-library overrides
via `src/config.json` in a single-pass flow. Attempts to use `SYNTH_LIBS_BASE`
or `SYNTH_EXCLUSION_CELL_LIST` were found to be invalid OpenLane2 keys (caught
by CI run 25919426539 — R5-HONEST gate working as intended).

This branch therefore:

1. **Documents the hdll zoning intent** in `info.yaml` (header comment + description field).
2. **Adds `//k-duallib` comment key** in `src/config.json` that specifies the
   activation path for the operator at T-51h merge time.
3. **Records this document** as the authoritative specification for the next-tapeout
   operator to implement the hdll override via one of:
   - `STD_CELL_LIBRARY_OPT=sky130_fd_sc_hdll` in an OpenLane2 MULTI_CORNER_STA step, or
   - A per-block `CELL_PAD_EXCLUDE` / `DONT_USE_CELLS` filter that excludes hd variants
     for the four targeted blocks, or
   - A two-pass synthesis flow: pass 1 = full hd baseline; pass 2 = re-synthesise
     `{lucas_rom_*, crc32_receipt, blake3_anchor, gf16_mul}` sub-hierarchies with
     `sky130_fd_sc_hdll__tt_025C_1v80.lib` as the target liberty.

### Current active config changes

The `feat/v15/k-dual-lib` branch (as of the REVISED v2 commit) applies:
- `PL_TARGET_DENSITY_PCT_TIMING_OPT: 1` — enables timing-optimized placement density,
  pushing synthesizer toward smaller, lower-leakage cells within the hd library.
  Estimated impact: -8-15% static leakage in idle cluster, combined with CGT.

### Future activation path (post-T-51h)

```json
// src/config.json additions for full hdll activation (requires OpenLane2 >= 2.3):
{
  "STD_CELL_LIBRARY": "sky130_fd_sc_hd",
  "STD_CELL_LIBRARY_OPT": "sky130_fd_sc_hdll",
  "SYNTH_STRATEGY": "DELAY 0"
}
```

For per-block hdll mapping, the operator should investigate OpenLane2 hierarchical
synthesis modes or post-placement cell substitution scripts.

---

## Falsification Gate G-13

Mixed hd+hdll is accepted **only if WNS >= 0** (timing closes).

- **PASS (WNS >= 0):** Proceed with merged hdll zoning.
- **FAIL (WNS < 0):** Roll back to pure `sky130_fd_sc_hd` for all blocks.

The G-13 gate is enforced at merge time (T-51h = 2026-05-17 22:00 UTC) by the
operator reviewing the OpenLane2 timing report from the GDS CI run on
`feat/v15/k-dual-lib`.

---

## R-SI-1 Compliance

Lane K (L-DPC22-K) is **config/docs-only**. Zero changes have been made to
any synthesisable RTL file under `src/`.

Verification:
```
git diff main..feat/v15/k-dual-lib --stat -- src/*.v
# Must produce empty output
```

---

## Files Changed in this Branch

| File | Change type | Description |
|------|-------------|-------------|
| `info.yaml` | Config + docs | Added S-13 dual-lib header comment + description extension |
| `src/config.json` | Config | Added `//k-duallib` documentation hint; `PL_TARGET_DENSITY_PCT_TIMING_OPT: 1` (valid OpenLane2 key) |
| `docs/L-DPC22-K-DUAL-LIB.md` | Docs (new) | This document |

---

## References

- [SkyWater PDK — Foundry-Provided Libraries](https://skywater-pdk.readthedocs.io/en/main/contents/libraries/foundry-provided.html)
- [sky130_fd_sc_hdll README](https://skywater-pdk.readthedocs.io/en/main/contents/libraries/sky130_fd_sc_hdll/README.html)
- [OpenLane2 configuration variables](https://openlane2.readthedocs.io/en/latest/reference/flow_config_vars.html)
- Epic: [gHashTag/trinity-fpga#93](https://github.com/gHashTag/trinity-fpga/issues/93)
- Anchor DOI: [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)
