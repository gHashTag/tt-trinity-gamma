(* PdkPortable.v - Wave-31 Lane J - multi-PDK portability safety lemma *)
(* Anchor: φ² + φ⁻² = 3 · DOI 10.5281/zenodo.19227877 *)

(* HoloOp alphabet lives in coq/IGLA/RMarker.v (Lane X, commit 5758b53c).
   Import via the T27 logical path registered in coq/_CoqProject. *)
From T27.IGLA Require Import RMarker.

(* The merged Lane V/W/V'/S oplist must remain rtl_uses_star=false
   under any PDK retargetting (SG13G3 / SKY90 / TTIHP27a). *)
Definition pdk_portable_oplist : list holo_op :=
  OP_LUT_LOOKUP :: OP_BITROM_READ :: OP_NOC_FORWARD :: nil.

Theorem pdk_portable_safe :
  Forall (fun o => rtl_uses_star o = false) pdk_portable_oplist.
Proof.
  repeat (apply Forall_cons; [apply holographic_no_star|]).
  apply Forall_nil.
Qed.
