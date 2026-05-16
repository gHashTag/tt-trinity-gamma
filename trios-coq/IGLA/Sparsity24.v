(* Sparsity24.v - Wave-29 Lane C - 2:4 structured sparsity safety lemma *)
(* Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877 *)

(* HoloOp alphabet lives in coq/IGLA/RMarker.v (Lane X, commit 5758b53c).
   Import via the T27 logical path registered in coq/_CoqProject. *)
From T27.IGLA Require Import RMarker.

(* A 2:4 sparsity mask is a 4-bit vector with exactly 2 bits set *)
Definition popcount4 (b0 b1 b2 b3 : bool) : nat :=
  (if b0 then 1 else 0) + (if b1 then 1 else 0) +
  (if b2 then 1 else 0) + (if b3 then 1 else 0).

Definition sparsity_mask_24_valid (b0 b1 b2 b3 : bool) : Prop :=
  popcount4 b0 b1 b2 b3 = 2.

(* The sparsity decoder is built from XOR/MUX over the holo_op alphabet *)
(* (we abstract the decoder as a sequence of LUT_LOOKUP ops over the mask) *)
Definition sparsity_24_decoder_oplist : list holo_op :=
  OP_LUT_LOOKUP :: OP_LUT_LOOKUP :: nil.

(* Safety theorem: the 2:4 sparsity decoder preserves rtl_uses_star = false *)
Theorem sparsity_24_safe :
  Forall (fun o => rtl_uses_star o = false) sparsity_24_decoder_oplist.
Proof.
  apply Forall_cons.
  - apply holographic_no_star.
  - apply Forall_cons.
    + apply holographic_no_star.
    + apply Forall_nil.
Qed.