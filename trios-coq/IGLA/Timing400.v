(* Timing400.v - Wave-30 Lane K - 400 MHz clock-push safety lemma *)
(* Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877 *)

(* HoloOp alphabet lives in coq/IGLA/RMarker.v (Lane X, commit 5758b53c).
   Import via the T27 logical path registered in coq/_CoqProject. *)
From T27.IGLA Require Import RMarker.

(* The 400 MHz constraint applies to the merged oplist;
   it must not silently introduce a * operator anywhere. *)
Definition timing_400mhz_oplist : list holo_op :=
  OP_LUT_LOOKUP :: OP_BITROM_READ :: OP_NOC_FORWARD :: nil.

Theorem timing_400mhz_safe :
  Forall (fun o => rtl_uses_star o = false) timing_400mhz_oplist.
Proof.
  repeat (apply Forall_cons; [apply holographic_no_star|]).
  apply Forall_nil.
Qed.
