(* Tenet.v - Wave-33 Lane T' - LEVER #3 TENET sparsity-aware LUT skip safety lemma *)
(* Anchor: phi^2 + phi^-2 = 3 · DOI 10.5281/zenodo.19227877 *)

(* HoloOp alphabet lives in coq/IGLA/RMarker.v (Lane X + Wave-33 ext).
   Import via the T27 logical path registered in coq/_CoqProject. *)
From Coq.Lists Require Import List.
Import ListNotations.
From T27.IGLA Require Import RMarker.

(* Wave-33 TENET sparsity-aware LUT skip controller pipeline:
   probe -> mask -> LUT lookup -> sparse skip -> NoC forward.

   This is the depth-5 alphabet chain link, extending the W31
   pdk_portable_oplist (depth-3) by adding OP_BITROM_READ and the
   new OP_SPARSE_SKIP (TRI-27 ISA 0xE1).

   R7 falsifier W-102-A: BitNet b1.58-3B runtime sparsity >= 25 %.
   Projection: x1.3 TOPS/W -> 195 TOPS/W on TTIHP27a generic synth. *)
Definition tenet_oplist : list holo_op :=
  OP_LUT_LOOKUP ::
  OP_BITROM_READ ::
  OP_SPARSE_SKIP ::
  OP_NOC_FORWARD ::
  OP_HOLO_MUX_1X2 ::
  nil.

(* Safety theorem: the full TENET pipeline preserves rtl_uses_star = false
   across all 5 ops -- alphabet chain depth 5 (was 4 after W31). *)
Theorem tenet_safe :
  Forall (fun o => rtl_uses_star o = false) tenet_oplist.
Proof.
  repeat (apply Forall_cons; [apply holographic_no_star|]).
  apply Forall_nil.
Qed.

(* Spot witness explicitly exported by name for RTL CI commit-message citation. *)
Lemma tenet_sparse_skip_no_star : rtl_uses_star OP_SPARSE_SKIP = false.
Proof. apply holographic_no_star. Qed.
