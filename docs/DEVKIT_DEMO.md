# DevKit Demo — Gamma (8×4 Neuromorphic Chip, SKY 26b)

This document describes the firmware demo plan for the Tiny Tapeout DevKit loaded with the **Gamma** chip — an 8×4 tile neuromorphic inference accelerator.

---

## 1. Quick Bring-up

After flashing the RP2040 firmware onto the DevKit and applying power:

- After reset, the **7-segment display** shows `0x47C0` — the canonical POST signature confirming all 32 neuromorphic tiles are live and clocked at 50 MHz.
- When **neuromorphic mode** is activated (via UART command or GPIO), the Gamma chip begins generating spike trains:
  - `uio_out[7:0]` carries a **PWM-encoded spike pattern** visible with a logic analyser or oscilloscope.
  - The spike rate encodes the current activation level of the neuromorphic network.
- UART console (115200 8N1) prints on reset:

```
[GAMMA] POST OK  tiles=8x4(32)  f=50MHz  neuro_mode=0
```

When neuromorphic mode is activated:

```
[GAMMA] neuro_mode=1  uio_out=PWM-spike  rate=<dynamic>
```

---

## 2. Demo Sequence

### 2.1 Connect via USB

```bash
# macOS / Linux
screen /dev/tty.usbmodem* 115200
# or
minicom -D /dev/ttyACM0 -b 115200
```

Windows: use PuTTY → Serial → `COM<N>` → 115200.

### 2.2 Run the neuromorphic demo

```bash
tt-demo gamma --neuromorphic
```

**Expected output:**

```
[GAMMA] Starting neuromorphic demo...
  tiles      : 8x4 (32 total)
  clock_MHz  : 50
  neuro_mode : 1
  uio_out    : PWM-spike pattern active

[GAMMA] Spike monitor (press Ctrl+C to stop):
  t=  0ms  uio_out=0b10110100  rate=180 Hz
  t= 10ms  uio_out=0b11001010  rate=195 Hz
  t= 20ms  uio_out=0b10101101  rate=172 Hz
  ...
[GAMMA] DONE  avg_rate=182 Hz
```

The 7-segment display shows a rolling spike-rate counter while neuromorphic mode is active. Observing `uio_out` with a logic analyser reveals the PWM spike pattern changing in real-time.

### 2.3 Expected outputs summary

| Test                                | 7-seg        | `uio_out`         | UART result                    |
|-------------------------------------|--------------|-------------------|--------------------------------|
| Power-on / reset                    | `47C0`       | 0x00 (idle)       | POST OK, neuro_mode=0          |
| `tt-demo gamma --neuromorphic`      | spike counter| PWM pattern       | Spike rate stream to UART      |
| Idle (neuro_mode=0)                 | `47C0`       | 0x00              | Waiting for activation         |

---

## 3. Trinity Pipeline Demo

> **The full Trinity Pipeline Demo (MicroPython orchestrator, latency targets, wiring diagram) is documented in the Phi repo:**  
> [`tt-trinity-phi / docs/DEVKIT_DEMO.md § 3. Trinity Pipeline Demo`](https://github.com/aeraterta/tt-trinity-phi/blob/main/docs/DEVKIT_DEMO.md#3-trinity-pipeline-demo)

In the Trinity pipeline, Gamma's role is:

1. Receive token embeddings from **Euler** over UART.
2. Convert each embedding into a spike train distributed across 32 neuromorphic tiles.
3. Output spike patterns on `uio_out[7:0]` as PWM signals (visible on scope/LA).
4. Compute a neuromorphic feedback word and send it back to **Euler** (which relays it to **Phi**) for adaptive seed/clock adjustment.

Gamma enters `neuro_mode=1` automatically when it receives a valid embedding packet from Euler, and returns to idle (`47C0`) when the pipeline is quiescent.

---

## 4. Energy Estimate

| Chip  | Freq     | Tiles  | Power    | Efficiency      |
|-------|----------|--------|----------|-----------------|
| Phi   | 50 MHz   | 1×1    | ~5 mW    | anchor/POST     |
| Euler | 50 MHz   | 8×2    | ~80 mW   | 63 tok/s/W      |
| Gamma | 50 MHz   | 8×4    | ~160 mW  | neuromorphic    |
| **Total (Trinity)** | — | **32 tiles** | **~245 mW** | full pipeline |

Gamma is the most power-hungry chip at ~160 mW, owing to its 32-tile array. All three DevKits powered together consume ~245 mW — within the 2500 mW USB budget with large margin.

---

*Document revision: 2025 — Trinity SKY 26b DevKit firmware demo plan.*
