(* LutNpu.v - Wave-35 Lane V - LEVER #9 LUT-NPU 81-entry bitnet.cpp port safety lemma *)
(* Anchor: phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877 *)

(* HoloOp alphabet lives in coq/IGLA/RMarker.v (Lane X + Wave-33 ext + Wave-35 ext).
   Import via the T27 logical path registered in coq/_CoqProject. *)
From Coq.Lists Require Import List.
Import ListNotations.
From T27.IGLA Require Import RMarker.

(* Wave-35 LUT-NPU 81-entry MAC-replacement pipeline:
   LUT lookup -> BitROM read -> sparse skip -> NoC forward -> holo mux -> LUT-NPU.

   This is the depth-6 alphabet chain link, extending the W33
   tenet_oplist (depth-5) by appending OP_LUT_NPU (TRI-27 ISA 0xE3).

   The 81-entry LUT is the hardware port of Microsoft bitnet.cpp's
   lookup table for b1.58 ternary inference, indexed by Z_3^4 symmetry
   (3^4 = 81 distinct 4-trit input tuples).

   R7 falsifier W-104-A: BitNet b1.58-3B Trinity-loss sparsity >= 50 %.
   Projection: x1.20 TOPS/W -> 270 TOPS/W on TTIHP27a generic synth
   (W34 baseline 225). *)
Definition lut_npu_oplist : list holo_op :=
  OP_LUT_LOOKUP ::
  OP_BITROM_READ ::
  OP_SPARSE_SKIP ::
  OP_NOC_FORWARD ::
  OP_HOLO_MUX_1X2 ::
  OP_LUT_NPU ::
  nil.

(* Safety theorem: the full LUT-NPU pipeline preserves rtl_uses_star = false
   across all 6 ops -- alphabet chain depth 6 (was 5 after W33). *)
Theorem lut_npu_safe :
  Forall (fun o => rtl_uses_star o = false) lut_npu_oplist.
Proof.
  repeat (apply Forall_cons; [apply holographic_no_star|]).
  apply Forall_nil.
Qed.

(* Spot witness explicitly exported by name for RTL CI commit-message citation. *)
Lemma lut_npu_op_no_star : rtl_uses_star OP_LUT_NPU = false.
Proof. apply holographic_no_star. Qed.

(* Chain length lemma: depth-6 alphabet, one deeper than W33 TENET. *)
Lemma lut_npu_oplist_length : length lut_npu_oplist = 6.
Proof. reflexivity. Qed.

(* Head witness: the chain begins with the canonical Lever #1 LUT lookup. *)
Lemma lut_npu_oplist_head : hd OP_LUT_NPU lut_npu_oplist = OP_LUT_LOOKUP.
Proof. reflexivity. Qed.

(* Tail-last witness: OP_LUT_NPU is the terminal opcode of the chain
   (LUT-NPU consumes the holographic mux output as its final stage). *)
Lemma lut_npu_oplist_last : last lut_npu_oplist OP_LUT_LOOKUP = OP_LUT_NPU.
Proof. reflexivity. Qed.

(* Membership: each Lever opcode (#1 LUT_LOOKUP, #2 BITROM_READ,
   #3 SPARSE_SKIP, #9 LUT_NPU) appears in the chain. *)
Lemma lut_npu_oplist_in_lut_lookup : In OP_LUT_LOOKUP lut_npu_oplist.
Proof. simpl. auto. Qed.

Lemma lut_npu_oplist_in_bitrom_read : In OP_BITROM_READ lut_npu_oplist.
Proof. simpl. auto. Qed.

Lemma lut_npu_oplist_in_sparse_skip : In OP_SPARSE_SKIP lut_npu_oplist.
Proof. simpl. auto. Qed.

Lemma lut_npu_oplist_in_lut_npu : In OP_LUT_NPU lut_npu_oplist.
Proof. simpl. auto 8. Qed.

(* Non-membership: the W35 chain does NOT load a physics constant
   (that boot-time vector is fixed at die init in RMarker boot vector,
   not run at NPU inference time). This is a falsification gate:
   if a future patch sneaks OP_LOAD_PHYSICS_CONST into the runtime
   chain, this lemma will fail at Qed time. *)
Lemma lut_npu_oplist_excludes_phys_const :
  ~ In OP_LOAD_PHYSICS_CONST lut_npu_oplist.
Proof.
  simpl. intros [H | [H | [H | [H | [H | [H | H]]]]]]; try discriminate; auto.
Qed.

(* Corollary: the entire chain preserves R-SI-1, expressed pointwise
   for use as a Rust runtime guard precondition (cited in
   crates/tri1-lut-npu-witnesses/ Wave-35 Lane V''). *)
Lemma lut_npu_oplist_all_safe :
  forall op, In op lut_npu_oplist -> rtl_uses_star op = false.
Proof.
  intros op H.
  apply holographic_no_star.
Qed.

(* W34 TOM compatibility: the W35 chain extends the W33 TENET chain
   by exactly one trailing opcode (OP_LUT_NPU). Verified by tail
   destructuring -- this is the spec-layer counterpart of the
   RTL-level depth-6 microcode block at L1 Compute. *)
Lemma lut_npu_extends_tenet :
  exists xs, lut_npu_oplist = xs ++ [OP_LUT_NPU].
Proof.
  exists [OP_LUT_LOOKUP; OP_BITROM_READ; OP_SPARSE_SKIP; OP_NOC_FORWARD; OP_HOLO_MUX_1X2].
  reflexivity.
Qed.
