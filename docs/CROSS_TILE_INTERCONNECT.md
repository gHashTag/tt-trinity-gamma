# Cross-Tile Interconnect Specification
## TRI-1 Triad — Phi / Euler / Gamma on TTSKY26b DevKit Board

**Revision:** 1.0 · TTSKY26b  
**Applies to:** TRI-1 Phi (#4914, 1×1), TRI-1 Euler (#4915, 8×2), TRI-1 Gamma (#4913, 8×4)  
**DOI:** [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877) — Trinity Stack provenance

---

## 1. Overview

Three Trinity ASIC dies are co-mounted on a single Tiny Tapeout SKY130A DevKit board for the TTSKY26b shuttle run. Each chip occupies a separate TT slot and communicates through board-level IO mux traces. This document specifies:

- The canonical cross-die anchor (`0x47C0`)
- The role assignment (master / compute slave / neuromorphic slave)
- The 3-wire handshake protocol
- The DevKit IO mux configuration
- The end-to-end use case (Lucas POST → token forwarding → activation → φ-spiral consensus)

---

## 2. Canonical Cross-Die Anchor — TG-TRIAD-X (Theorem 36.1)

After reset (`rst_n` released), **all three chips** drive the same 16-bit constant:

```
{uio_out[7:0], uo_out[7:0]} = 16'h47C0  (binary: 0100_0111_1100_0000)
```

This is the **TG-TRIAD-X ledger anchor**, defined in PhD Theorem 36.1.

```
  Meaning: GF16 dot4(1.0, 2.0, 3.0, 4.0) — canonical ternary inner product
  Identity: φ² + φ⁻² = 3  (Trinity algebraic identity, Lucas chain)
  Anchor ID: TG-TRIAD-X
  Scope: Cross-die deterministic reset verification
```

### Anchor Verification Procedure

```
  After global rst_n release:
    t=0 ns: rst_n=1 (all three chips)
    t=20 ns (1 clock): sample {uio_out, uo_out} on each chip
    Phi   → expected 0x47C0  ✓ or FAULT
    Euler → expected 0x47C0  ✓ or FAULT
    Gamma → expected 0x47C0  ✓ or FAULT (note: uio[3:0] = D2D TX bits in op mode,
            but canonical mode sets full uio_out = 0x47)
```

If any chip does not produce `0x47C0`, that slot is held in reset until the anchor is confirmed. The other two chips wait in canonical mode (load_mode=0).

---

## 3. Role Assignment

```
  ┌────────────────────────────────────────────────────────────────────┐
  │                 TTSKY26b DevKit — TRI-1 Triad                      │
  │                                                                    │
  │  ┌──────────────┐   3-wire   ┌──────────────┐   D2D    ┌────────┐ │
  │  │  TRI-1 Phi   │ ──────────▶│ TRI-1 Euler  │ ────────▶│ TRI-1  │ │
  │  │  (φ-anchor)  │◀── ack ───│  (e-engine)  │◀── spike─│ Gamma  │ │
  │  │  1×1 #4914   │            │  8×2 #4915   │          │ 8×4    │ │
  │  │  MASTER      │            │  COMPUTE     │          │ #4913  │ │
  │  │  POST Gate   │            │  SLAVE       │          │ NEURO  │ │
  │  └──────────────┘            └──────────────┘          │ SLAVE  │ │
  │         ▲                                               └────────┘ │
  │         └──────────────── φ-spiral consensus ─────────────────────┘
  └────────────────────────────────────────────────────────────────────┘
```

| Role | Chip | Slot | Tiles |
|------|------|------|-------|
| **Master** (POST gate) | TRI-1 Phi | #4914 | 1×1 |
| **Compute slave** (ternary MAC, embedding+FSM) | TRI-1 Euler | #4915 | 8×2 |
| **Neuromorphic slave** (γ-surface, LIF columns) | TRI-1 Gamma | #4913 | 8×4 |

---

## 4. 3-Wire Handshake Protocol

The handshake uses 3 lines routed via the DevKit IO mux. All signals are referenced to the **Phi master** perspective.

```
  Wire A: LOAD_MODE  — Phi drives ui[0] of Euler and Gamma simultaneously
  Wire B: SYNC_STROBE — Phi compute_strobe (ui[6]) ORed/muxed to Euler & Gamma
  Wire C: ACK        — Open-drain OR of Euler uo[0] + Gamma uio[3] (w_tx SYNC)
```

### Handshake State Machine

```
  STATE        PHI (MASTER)              EULER (COMPUTE)       GAMMA (NEURO)
  ──────────── ──────────────────────    ──────────────────    ─────────────────
  IDLE         LOAD_MODE=0               LOAD_MODE=0           LOAD_MODE=0
               uo={0x47C0 low}           uo={0x47C0 low}       uo={0x47C0 low}
               uio={0x47C0 high}         uio={0x47C0 high}     uio={0x47 high}
               ACK line = high           ─                     ─

  FRIEND_FOE   trinity_friend_foe.v      friend_foe check      friend_foe check
               Phi drives friend_id=     verifies: self_id      verifies: self_id
               0x47 (φ-anchor byte)      ≠ foe_pattern         ≠ foe_pattern
               broadcasts on ui[7:0]     latch handshake OK     latch handshake OK

  TOKEN_LOAD   Set LOAD_MODE=1 (Wire A)  Latch ui[7:1] as      Pass-through in
               Place token on ui[7:1]    7-bit data field       canonical mode
               Pulse SYNC_STROBE (B)     Route to FSM block

  COMPUTE      Pulse compute_strobe      trinity_master_fsm     d2d_holo_mesh
               (via Wire B to Euler)     executes MAC/module    receives from Euler
               Wait ACK                  Drives result on uo    uio[7:4] RX active

  RESULT       Read Euler uo+uio         Drive result on uo     Process in cortex
               ACK = Euler uo[0]=1       Pull ACK low (uo[0])   spike_count → TX

  CONSENSUS    Read Gamma spike via       ─                     uio[3:0] TX spike
               board mux Gamma uio[1]                          bits to Phi mux
               Aggregate φ-spiral                               input
               Next token decision
```

### Friend/Foe Handshake (`trinity_friend_foe.v`)

Each chip implements `trinity_friend_foe.v`. Phi is the initiator:

```verilog
  // Friend pattern constants (from sacred_constants_rom.v):
  //   PHI_FRIEND_ID  = 8'h47  (φ-anchor byte, high byte of 0x47C0)
  //   EULER_FRIEND_ID = 8'hE2 (e-engine signature)
  //   GAMMA_FRIEND_ID = 8'h93 (GAMMA anchor, per tt-trinity-gamma description)
  //
  // On handshake init:
  //   Phi presents PHI_FRIEND_ID on ui[7:0] for 2 clock cycles.
  //   Euler and Gamma latch and compare to their expected initiator pattern.
  //   If match: slave sets uo[0]=1 (ACK/friend).
  //   If mismatch: slave remains in canonical mode (foe lockout).
```

---

## 5. Packet Path — `ui_in[0]=load_mode=1`

When Wire A (LOAD_MODE) is driven high by Phi:

```
  Phi master:
    ui[0] = 1  (load_mode = packet path)
    ui[7:1] = token[6:0] (7-bit token or embedding index)
    Rising edge on ui[6] (compute_strobe) = issue COMPUTE

  Euler (receiving on its own ui[0..7]):
    load_mode=1 → trinity_master_fsm activates
    data_bit[6:0] = token[6:0] from Phi mux
    FSM selects compute block from data_bit[2:0]
    Executes ternary MAC or SUPER-CROWN module
    Result driven on {uio_out, uo_out}

  Gamma (receiving from Euler D2D):
    Euler uo[7:0] → board trace → Gamma uio[4] (D2D n_rx) or uio[5] (D2D e_rx)
    d2d_holo_mesh routes to cortical_column array
    LIF columns integrate activation
    spike_count output → uio[3:0] (D2D TX back to board mux → Phi)
```

---

## 6. Sacred Constants ROM as Shared Address Space

All three chips carry `sacred_constants_rom.v` (75 PhD constants) and `crown47_rom.v` (Crown47 constants). These ROMs function as a **shared virtual address space** visible to the host:

```
  Address range 0x00–0x4A: sacred_constants_rom (75 entries × 8-bit)
  Address range 0x00–0x2E: crown47_rom (47 entries × 8-bit)
  Canonical anchor 0x47C0 lives at sacred_constants_rom[addr=0] conceptually.

  Access from host:
    1. Set Phi load_mode=0, lucas_idx=desired Lucas index → uo+uio = L_n value
    2. Set Gamma load_mode=0, uio[7]=1 (crown_mode), ui[6]=addr[6] → Crown ROM
    3. Euler SUPER-CROWN modules address ROM internally via trinity_master_fsm.
```

The anchor `0x47C0` at address 0 is the single point of synchrony: any read of this address across any of the three chips must return the same value, confirming cross-die ledger integrity.

---

## 7. DevKit Board IO Mux Configuration

The TT DevKit board uses a hardware IO mux (RP2040 + SPI mux) to select which chip's IO pins are connected to the host headers. For the Triad, three dedicated mux channels are required:

```
  MUX CHANNEL ASSIGNMENT
  ─────────────────────────────────────────────────────────────────────
  Channel 0 (Phi master output):
    Phi uo[0..7]  → host header row 0  (canonical anchor / MAC result low)
    Phi uio[0..7] → host header row 1  (canonical anchor / MAC result high)

  Channel 1 (Euler compute slave):
    Phi ui[0..7]  → Euler ui[0..7]  via trace J1 (LOAD_MODE + token data)
    Euler uo[0..7] → host header row 2 AND → Gamma uio[4] (D2D n_rx)
    Euler uio[0..7] → host header row 3

  Channel 2 (Gamma neuromorphic slave):
    Euler uo[0..7] → Gamma uio[5] (D2D e_rx) via trace J2
    Gamma uio[0..3] (D2D TX) → host header row 4 AND → Phi mux input J3
    Gamma uo[0..7]  → host header row 5

  HANDSHAKE WIRES (solder bridges or 0Ω resistors on PCB):
    Wire A (LOAD_MODE): Phi ui[0] driver → Euler ui[0] AND Gamma ui[0]
    Wire B (SYNC_STROBE): Phi ui[6] driver → Euler ui[0] pulse path (muxed)
    Wire C (ACK): Euler uo[0] + Gamma uio[3] → Phi dedicated GPIO input

  GLOBAL SIGNALS (all 3 chips):
    clk:   shared 50 MHz clock from DevKit oscillator → all three CLK pins
    rst_n: RP2040 GPIO drives all three rst_n pins simultaneously
```

### IO Mux Control Register (suggested firmware)

```c
  // RP2040 firmware pseudo-code
  #define MUX_ALL_RESET    0x07  // assert rst_n on all 3 chips simultaneously
  #define MUX_PHI_ONLY     0x01  // read Phi outputs
  #define MUX_EULER_ONLY   0x02  // read Euler outputs
  #define MUX_GAMMA_ONLY   0x04  // read Gamma outputs
  #define MUX_TRIAD_ACTIVE 0x07  // all 3 operational (handshake mode)

  tt_mux_write(MUX_ALL_RESET);   // Step 1: reset all
  delay_cycles(4);
  tt_mux_write(0x00);            // Step 2: release reset
  anchor_phi   = read_uio_uo(SLOT_PHI);
  anchor_euler = read_uio_uo(SLOT_EULER);
  anchor_gamma = read_uio_uo(SLOT_GAMMA);
  assert(anchor_phi == 0x47C0 && anchor_euler == 0x47C0 && anchor_gamma == 0x47C0);
```

---

## 8. End-to-End Use Case — φ-Spiral Consensus

```
  ╔══════════════════════════════════════════════════════════════════════╗
  ║           USE CASE: Lucas POST → Token → Activation → Consensus     ║
  ╚══════════════════════════════════════════════════════════════════════╝

  Phase 1 — RESET & ANCHOR VERIFICATION
    Host asserts rst_n=0 on all three chips (4 cycles minimum).
    Host releases rst_n=1 simultaneously.
    Reads {uio_out, uo_out} from each chip:
      Phi=0x47C0, Euler=0x47C0, Gamma=0x47C0  → TRIAD ONLINE.

  Phase 2 — FRIEND/FOE HANDSHAKE (trinity_friend_foe.v)
    Phi broadcasts PHI_FRIEND_ID=0x47 on ui[7:0] for 2 cycles.
    Euler and Gamma latch pattern, compare, assert ACK (uo[0]=1).
    Triad is in FRIEND state → proceed to POST.

  Phase 3 — LUCAS POST ON PHI
    Phi: load_mode=0, iterate lucas_idx 0→5.
    Verify L₂=3, L₃=4, L₄=7, L₅=11, L₆=18, L₇=29 (Lucas chain).
    φ-anchor POST: confirms φ² + φ⁻² = 3.
    Phi asserts SYNC_STROBE (Wire B) once POST is complete.

  Phase 4 — TOKEN FORWARDING TO EULER
    Phi: set load_mode=1 (Wire A high to all chips).
    Phi places first token on ui[7:1].
    Phi pulses compute_strobe (Wire B).
    Euler: trinity_master_fsm activates, routes token to ternary MAC block.
    Euler executes GF16 dot product or embedding lookup.
    Euler drives result on {uio_out, uo_out}.
    Euler pulls ACK (Wire C = uo[0]=1) when result is ready.
    Host or Phi reads Euler result.

  Phase 5 — ACTIVATION IN GAMMA
    Euler result (uo[7:0]) forwarded to Gamma uio[4] (D2D n_rx) via trace J1.
    Gamma d2d_holo_mesh receives activation, routes to cortical_column array.
    8 LIF columns integrate membrane potential.
    Columns emit spikes → spike_count[7:0] computed.
    spike_count[3] → uio[0] (D2D n_tx), spike_count[0] → uio[1] (D2D e_tx).
    Gamma uio[3] (D2D w_tx SYNC, LAYER-FROZEN gated) provides timing strobe.

  Phase 6 — φ-SPIRAL CONSENSUS
    Gamma uio[1] (e_tx) spike bit → board trace J3 → Phi mux input.
    Phi reads spike aggregate via dedicated GPIO.
    Phi sacred_constants_rom provides φ-distance oracle threshold.
    phi_distance_oracle (Gamma, mirrored in Phi) computes spiral distance:
      |spike_count - φ·previous_spike_count| < threshold → CONSENSUS
    If consensus: emit final result token, increment Lucas index.
    If no consensus: increment token, repeat Phase 4.
    Iteration converges on φ-spiral trajectory (PhD Ch. 36 Theorem 36.1).

  ═══════════════════════════════════════════════════════════════════════
  TIMING BUDGET (50 MHz clock, 20 ns period):
    Phase 1 (reset):         4 cycles   =  80 ns
    Phase 2 (friend/foe):    2 cycles   =  40 ns
    Phase 3 (Lucas POST):    6 cycles   = 120 ns (one per L_n read)
    Phase 4 (token→Euler):   3–5 cycles =  60–100 ns (FSM pipeline)
    Phase 5 (Euler→Gamma):   2 cycles   =  40 ns (D2D hop)
    Phase 6 (spike→Phi):     2 cycles   =  40 ns (GPIO read)
    Per-token total:         ~15 cycles = ~300 ns
  ═══════════════════════════════════════════════════════════════════════
```

---

## 9. Protocol Reference

| Protocol element | Source module | Chips |
|-----------------|--------------|-------|
| Friend/foe handshake | `trinity_friend_foe.v` | Phi, Euler, Gamma |
| Packet path (load_mode=1) | `trinity_master_fsm.v` | Euler |
| Sacred constants ROM | `sacred_constants_rom.v` | Phi, Euler, Gamma |
| Crown47 ROM | `crown47_rom.v` / `crown47_rom_8bit.v` | Phi, Euler, Gamma |
| D2D mesh routing | `d2d_holo_mesh.v` | Euler, Gamma |
| Lucas POST chain | `phi_anchor_post.v` + `lucas_rom.v` | Phi (master); Euler, Gamma mirror |
| CLARA Gap-4 restraint | `restraint_ctrl.v` | Phi, Euler |
| φ-spiral oracle | `phi_distance_oracle.v` | Gamma |
| Canonical anchor | `0x47C0` constant | All three |

---

## 10. Related Documents

| Document | Location |
|----------|----------|
| Phi PINOUT | `tt-trinity-phi/docs/PINOUT.md` |
| Euler PINOUT | `tt-trinity-euler/docs/PINOUT.md` |
| Gamma PINOUT | `tt-trinity-gamma/docs/PINOUT.md` |
| Gamma D2D dual-lib | `tt-trinity-gamma/docs/L-DPC22-K-DUAL-LIB.md` |
| Triad architecture spec | `tt-trinity-gf16/docs/architecture/TRI_NET_SHUTTLE_TRIAD.md` |
| PhD Theorem 36.1 | `trios/docs/phd/chapters/flos_70.tex` |
| DOI provenance | [10.5281/zenodo.19227877](https://doi.org/10.5281/zenodo.19227877) |
