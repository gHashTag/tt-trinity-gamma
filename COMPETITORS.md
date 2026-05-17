# COMPETITORS — Restrained, evidence-backed positioning

> **TRI-NET is not in a TOPS race with commercial AI-edge silicon.**
> The differentiation axis is **open PDK / RTL, ternary / GoldenFloat
> research path, formal assurance / proof trace, CLARA-aligned AR/ML
> assurance, and a reproducible `.t27 → RTL → shuttle` path**. This
> document compares against the chips users most often ask about, with
> public sources for every factual claim.

Last reviewed: 2026-05-17. Spec numbers cited here come from each
vendor's public material; we do not rerun the benchmarks ourselves.

## The chips we get compared to

| Chip | Vendor | Public source |
|------|--------|---------------|
| **Cloud AI 100 Ultra** | Qualcomm | [Product brief PDF](https://www.qualcomm.com/content/dam/qcomm-martech/dm-assets/documents/Prod-Brief-QCOM-Cloud-AI-100-Ultra.pdf) |
| **Hailo-8** | Hailo | [Hailo-8 product page](https://hailo.ai/products/ai-accelerators/hailo-8-ai-accelerator/) |
| **Metis** | Axelera | [Metis AIPU page](https://axelera.ai/ai-accelerators/aipu/metis) |
| **Coral Edge TPU** | Google / Coral | [Coral Edge TPU benchmarks](https://www.coral.ai/docs/edgetpu/benchmarks/) |
| **Dimensity NPU (e.g. 9400+)** | MediaTek | [Dimensity 9400+ page](https://www.mediatek.com/products/smartphones/mediatek-dimensity-9400-plus) |

These five are mature, commercially shipping products with closed PDKs,
closed RTL, and proprietary tooling. They each target one or both of
*throughput per watt at INT8/FP16* and *integration into a shipping
SoC / module*. **None of those is what `tt-trinity-gamma` is for.** It
is a research substrate fabricated on the open SkyWater SKY130A PDK via
[Tiny Tapeout](https://tinytapeout.com/chips/).

## Honest comparison

| Axis | Cloud AI 100 Ultra | Hailo-8 | Axelera Metis | Coral Edge TPU | MediaTek NPU | **tt-trinity-gamma (this repo)** |
|------|--------------------|---------|---------------|----------------|--------------|----------------------------------|
| Target | Datacentre / generative AI inference (per Qualcomm brief) | Edge AI accelerator (per Hailo product page) | Edge AIPU, INT8 (per Axelera page) | Embedded ML inference (per Coral benchmarks page) | Smartphone SoC NPU (per MediaTek page) | **Open ternary AI silicon research substrate** |
| PDK / RTL | Proprietary | Proprietary | Proprietary | Proprietary | Proprietary | **Open — SKY130A + Apache-2.0 RTL** |
| Tooling | Vendor SDK | Vendor SDK | Vendor SDK | Vendor SDK + Edge TPU compiler | Vendor SDK | **Open — `.t27 → RTL → OpenLane2 → shuttle**, reproducible from a clone |
| Native ternary / K3 | Not advertised on linked source | Not advertised on linked source | Not advertised on linked source | Not advertised on linked source | Not advertised on linked source | **Yes** — `src/k3_alu.v`, `src/bitnet_encoder.v` |
| Native open GF(2ⁿ) family | Not advertised | Not advertised | Not advertised | Not advertised | Not advertised | **Yes** — GF4 … GF256 in `src/` + `specs/numeric/` |
| BitNet b1.58 (arXiv 2402.17764) primitive in silicon | Not advertised | Not advertised | Not advertised | Not advertised | Not advertised | **Yes** — `src/bitnet_encoder.v` |
| Per-decision proof / audit primitive | Not advertised | Not advertised | Not advertised | Not advertised | Not advertised | **Yes** — `src/proof_trace_writer.v`, `src/audit_log_ring_buffer.v`, `src/blake3_anchor.v` |
| CLARA-aligned assurance surface | Not in scope | Not in scope | Not in scope | Not in scope | Not in scope | **10/10 gap blocks present** — see [`CLARA_TRACEABILITY.md`](CLARA_TRACEABILITY.md) |
| Raw INT8 / FP16 throughput | Datacentre-class (per Qualcomm brief) | Multi-TOPS edge-class (per Hailo page) | Multi-TOPS edge-class (per Axelera page) | Edge-class TOPS (per Coral page) | Mobile-class TOPS (per MediaTek page) | **Not the goal** — small open-PDK research die |

> **"Not advertised on linked source"** means we did not find a claim of
> the capability on the vendor's own page linked above as of the review
> date. It does *not* mean the capability is impossible — it means
> TRI-NET's differentiator is that the capability is **exposed natively
> in open RTL** rather than (potentially) hidden behind a proprietary
> stack.

## What γ-surface gives you that a closed AI-edge chip cannot

1. **Auditable silicon.** Every cell in the GDS comes from a Verilog
   file in this repo. There is no closed IP block.
2. **A ternary substrate that matches the BitNet b1.58 research line**
   ([arXiv 2402.17764](https://arxiv.org/abs/2402.17764)) at the
   primitive level, not just as a quantization mode in a compiler.
3. **A formal-friendly path.** Coq trees (`coq/`, `trios-coq/`) bind
   RTL behaviour to proof obligations; a CLARA proof manifest
   (`docs/CLARA_PROOF_MANIFEST.md`) names which obligations belong with
   which blocks.
4. **Per-decision proof / audit trace baked into the surface.** Not a
   driver-level log — a hardware ring buffer + receipt anchor.
5. **A reproducible `.t27 → RTL → shuttle` pipeline**, governed by the
   [t27 toolchain](https://github.com/gHashTag/t27) and shippable
   through [Tiny Tapeout](https://tinytapeout.com/chips/).

## What γ-surface does **not** try to be

- ❌ Not a datacentre inference accelerator (that's Cloud AI 100's job).
- ❌ Not an edge SoC NPU (that's Hailo / Metis / Coral / Dimensity).
- ❌ Not a fixed-function INT8 throughput champion.
- ❌ Not a turnkey customer-grade product. It is a **research substrate**
      shipped on an open shuttle.

If your evaluation criterion is "INT8 TOPS/W at a 7 nm or 5 nm process
node with a vendor SDK," pick one of the five competitor chips. If
your evaluation criterion is "can I read every line of RTL, fabricate
it on an open PDK, and inspect the per-decision proof trace," that is
specifically what this line is for.

## Restraint policy (read before adding new comparison rows)

When extending this file, follow these rules. They exist to keep the
comparison defensible.

1. **Every comparison row cites a public vendor source** — vendor's own
   product page or whitepaper, linked at the top of this file.
2. **Never compare against a number the vendor did not publish.** If
   the page does not state INT8 TOPS at a corner, do not invent one.
3. **Never claim measured silicon parity** for `tt-trinity-gamma`.
   Until the chip returns and is measured, we say "not the goal" or
   "pre-silicon estimate" — see [`STATUS.md`](STATUS.md).
4. **Be specific about what *we* mean.** "K3 in silicon" means
   `src/k3_alu.v` gated in CI, not "we plan to support K3."
5. **Reference [`CLARA_TRACEABILITY.md`](CLARA_TRACEABILITY.md)** for
   CLARA-gap claims; do not duplicate them here.

## Sources

- Qualcomm Cloud AI 100 Ultra product brief — <https://www.qualcomm.com/content/dam/qcomm-martech/dm-assets/documents/Prod-Brief-QCOM-Cloud-AI-100-Ultra.pdf>
- Hailo-8 AI accelerator — <https://hailo.ai/products/ai-accelerators/hailo-8-ai-accelerator/>
- Axelera Metis AIPU — <https://axelera.ai/ai-accelerators/aipu/metis>
- Coral Edge TPU benchmarks — <https://www.coral.ai/docs/edgetpu/benchmarks/>
- MediaTek Dimensity 9400+ — <https://www.mediatek.com/products/smartphones/mediatek-dimensity-9400-plus>
- BitNet b1.58 — <https://arxiv.org/abs/2402.17764>
- DARPA CLARA — <https://www.darpa.mil/research/programs/clara>
- Tiny Tapeout chips — <https://tinytapeout.com/chips/>
