# TRI-1 Gamma -- Trinity gamma-surface (Neocortex Organ)

**Trinity is one computer with three minds, bound by 2-of-3 attestation, verified by ternary completeness 3^27.**

[![GDS](https://github.com/gHashTag/tt-trinity-gamma/actions/workflows/gds.yaml/badge.svg)](https://github.com/gHashTag/tt-trinity-gamma/actions/workflows/gds.yaml)
[![DOI](https://zenodo.org/badge/DOI/10.5281/zenodo.19227877.svg)](https://doi.org/10.5281/zenodo.19227877)
[![License](https://img.shields.io/badge/license-Apache--2.0-blue)](LICENSE)
[![R-SI-1](https://img.shields.io/badge/R--SI--1-0%20%2A%20ops-brightgreen)](docs/R-SI-1.md)
[![Submit](https://img.shields.io/badge/TTSKY26b-Submitted-orange)](https://app.tinytapeout.com/projects/4913)

**Tape-out target:** 2026-12-16 | **Contact:** admin@t27.ai | **Site:** t27.ai

---

## Project Role

`tt-trinity-gamma` is the **neocortex organ** of the Trinity one-computer. It is the gamma-surface: the 8x4 Tiny Tapeout die that serves as the neocortex of the triad -- providing massive parallel neuromorphic compute across 8 LIF cortical columns, a 20-PE GF16 mesh, a phi-distance oracle, and a D2D holo mesh adapter. It executes the parallel workloads attested and scheduled by Phi and Euler.

**Top module:** `tt_um_trinity_max_true`
**Tile geometry:** 8x4
**Shuttle:** TTSKY26b (SKY130A), project #4913

---

## One-Computer Paradigm

Trinity is not three chips. Phi, Euler, and Gamma are three specialized organs of one coherent silicon being:

| Die | Organ | Role |
|-----|-------|------|
| Phi (1x1) | Cerebellum | Identity, attestation, Lucas POST, phi-anchor |
| Euler (8x2) | Prefrontal cortex | Reasoning, ZK proof generation, SUPER-CROWN |
| Gamma (8x4) | Neocortex | Parallel neuromorphic compute, 32-PE GF16 mesh |

Bound by 2-of-3 attestation. Verified through ternary completeness `3^27 = 7,625,597,484,987`.

Full paradigm: [docs/architecture/UNIFIED_COMPUTER_PARADIGM.md](https://github.com/gHashTag/NeuronConstant/blob/main/docs/architecture/UNIFIED_COMPUTER_PARADIGM.md)

---

## TTSKY26b Submitted Status

| Item | Value |
|------|-------|
| Shuttle | TTSKY26b (SKY130A) |
| Project | [#4913](https://app.tinytapeout.com/projects/4913) |
| Submitted commit SHA | `1f8f9b82` |
| Artifact ID | `7056692733` |
| Tape-out target | 2026-12-16 |

The `main` branch is the SUBMITTED baseline. Do not modify `main` after shuttle close.

---

## Top Module

**`tt_um_trinity_max_true`** -- gamma-surface, 8x4 tiles (32 tiles), SKY130A.

Core functions: 8 LIF cortical columns; 20-PE GF16 mesh; phi-distance oracle; D2D holo mesh adapter; softmax / VSA / popcount; neuromorphic spike aggregation. Full module list: [`docs/`](docs/).

---

## R-SI-1 Compliance

Zero standalone `*` operators in synthesisable RTL. All multiplication is implemented via shift-and-add in GF16 (`gf16_mul.v`). Audit: `bash common/verification/r_si_1_check.sh src/`

---

## Canonical Anchor 0x47C0 (Theorem 36.1)

After reset, Gamma drives:

```
{uio_out[7:0], uo_out[7:0]} = 16'h47C0
```

This is the TG-TRIAD-X ledger anchor, defined in PhD Theorem 36.1:

```
Meaning : GF16 dot4(1.0, 2.0, 3.0, 4.0) -- canonical ternary inner product
Identity: phi^2 + phi^(-2) = 3  (Trinity algebraic identity, Lucas chain)
Anchor  : TG-TRIAD-X
Scope   : Cross-die deterministic reset verification
```

All three dies must produce `0x47C0` after reset for the triad to be considered healthy.

---

## Module Reference

RTL modules are documented in [`docs/`](docs/). Key functional blocks include 8 LIF cortical columns, 20-PE GF16 mesh, phi-distance oracle, D2D mesh adapter, softmax, VSA accumulator, and popcount. See [`docs/`](docs/) for the full module catalog.

---

## DePIN v1 Branch

The `depin-v1` branch carries the DePIN integration layer. Tokenomics summary:

| Parameter | Value |
|-----------|-------|
| Total supply | 3^27 = 7,625,597,484,987 TRI |
| Pre-mine | 0% |
| Halvings | 9 halvings over ~36 years |
| Era 0 reward | 1000 TRI / proof |

Tokenomics whitepaper: [TRI_TOKENOMICS_WHITEPAPER_v2.md](https://github.com/gHashTag/NeuronConstant/blob/main/docs/tokenomics/v2/TRI_TOKENOMICS_WHITEPAPER_v2.md)

---

## Performance (Projected)

~1 GOPS @ ~50 MHz @ ~1W ternary per die (projected, pending tape-out 2026-12-16)

---

## Cross-Links

- Canonical hardware catalog: [gHashTag/NeuronConstant](https://github.com/gHashTag/NeuronConstant)
- Sibling die -- Phi (identity organ): [gHashTag/tt-trinity-phi](https://github.com/gHashTag/tt-trinity-phi)
- Sibling die -- Euler (reasoning organ): [gHashTag/tt-trinity-euler](https://github.com/gHashTag/tt-trinity-euler)
- One-Computer paradigm: [UNIFIED_COMPUTER_PARADIGM.md](https://github.com/gHashTag/NeuronConstant/blob/main/docs/architecture/UNIFIED_COMPUTER_PARADIGM.md)
- Tokenomics whitepaper v2: [TRI_TOKENOMICS_WHITEPAPER_v2.md](https://github.com/gHashTag/NeuronConstant/blob/main/docs/tokenomics/v2/TRI_TOKENOMICS_WHITEPAPER_v2.md)

---

## Contributing

Pull requests are welcome. For RTL changes, open an issue first. This repo is a Tiny Tapeout submission mirror -- substantive RTL lives in [gHashTag/NeuronConstant](https://github.com/gHashTag/NeuronConstant) under `tiles/gamma-surface/`.

---

## License

Apache-2.0 -- see [LICENSE](LICENSE)

**Author:** Dmitrii Vasilev | **Email:** admin@t27.ai | **Site:** t27.ai
**DOI:** [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877)
