# TVM-VTA Bridge for TRI-1 MAX-TRUE

**Squeeze vector:** S-51 (L-DPC22 Lane Q)
**Status:** SKELETON · awaits silicon validation post-W15-TT-E
**Anchor:** `phi^2 + phi^-2 = 3`

## Purpose

Bridge between Apache TVM (Tensor Virtual Machine) and the 32-cell GF16 MAX-TRUE accelerator. TVM-VTA (Versatile Tensor Accelerator) provides a hardware-friendly tensor ISA; we map it to MAX-TRUE's packet-based ABI:

- **VTA `LOAD`** → MAX-TRUE Load weight packet (W*=GF16 element)
- **VTA `GEMM`** → MAX-TRUE matmul cluster activation (lane[3] cluster select)
- **VTA `ALU`** → MAX-TRUE cassini permutation / plrm / bpb_guard ops
- **VTA `STORE`** → MAX-TRUE result packet emission

## ABI Mapping

| VTA opcode | MAX-TRUE packet | Cluster |
|---|---|---|
| LOAD UOP | `lane[3:0]=0xA` | both |
| LOAD W | `lane[3:0]=0xB` | both |
| LOAD INP | `lane[3:0]=0xC` | both |
| GEMM | `lane[3]=cluster`, `lane[2:0]=tile_id` | A or B (parallel) |
| ALU | `lane[3:0]=0xD..0xE` (cassini/plrm) | both |
| STORE OUT | `lane[3:0]=0xF` | both |
| FINISH | `lane[3:0]=0x0` | supervisor |

## Compute Profile (target post-W15-TT-E)

Assuming v2.1 TURBO (10-12 GigaOPS · 80-110 TOPS/W @ 125 MHz):

- INT8 GEMM throughput: 4-5 TOPS effective via GF16 ternary expansion (8b→4b×2 packed)
- Latency-bound INT4 inference: 12-15 TOPS effective
- Verifiable compute mode (R7 falsification witness emitted per GEMM): -30% throughput, +SHA256 proof per result

## Roadmap

1. **Phase 1 (post-W15-TT-E silicon):** PyTVM codegen target stub
2. **Phase 2:** Quantization-aware GF16 packing
3. **Phase 3:** ONNX → TVM → MAX-TRUE end-to-end (target: MobileNetV3-Small @ 100 FPS, 5 mW)
4. **Phase 4:** Multi-die scaling (S-61) — 4× MAX-TRUE = 40-48 GigaOPS

## Falsification Gate (G-51)

**REJECT phase 1 if:** generated VTA-to-MAX-TRUE packet stream fails to produce bit-identical TG-MAX-TRUE-X anchor on canonical W*=((1,2,3,4)→0x47C0).

## References

- TVM-VTA upstream: https://tvm.apache.org/docs/topic/vta/
- MAX-TRUE packet ABI: see `src/tt_um_trinity_max_true.v` (HEAD @ 87a079d)
- Cross-die anchor: RVR-019 (Nano/Mid/MAX bit-identical)
- ONE SHOT: gHashTag/trinity-fpga#93
