(* Wave 45, S-194 + S-195 + S-200
   AVS-96 Dopamine Safety Coq proof
   anchor phi^2+phi^-2=3
   DOI 10.5281/zenodo.19227877
   basal-ganglia-DA
   S-200 milestone
   Refs gHashTag/trinity-fpga#175, gHashTag/trios#932
*)

Require Import Coq.Init.Nat.
Require Import Coq.Arith.Arith.

Module Avs96Safe.

Definition avs96_steps : nat := 96.
Definition avs96_bin_width_uv : nat := 6250.   (* 6.25 mV in micro-volts *)
Definition avs48_bin_width_uv : nat := 12500.  (* W36 baseline *)
Definition step_gate_input (occupancy_bin : nat) : nat :=
  if Nat.ltb occupancy_bin avs96_steps then occupancy_bin else 0.

(* Lemma 1: step count equals 96 *)
Lemma avs96_step_count : avs96_steps = 96.
Proof.
  reflexivity.
Qed.

(* Lemma 2: bin width is positive *)
Lemma avs96_bin_width_positive : avs96_bin_width_uv > 0.
Proof.
  unfold avs96_bin_width_uv. lia.
Qed.

(* Lemma 3: AVS-96 bin width is half of AVS-48 (W36 baseline) *)
Lemma avs96_half_of_avs48 : 2 * avs96_bin_width_uv = avs48_bin_width_uv.
Proof.
  unfold avs96_bin_width_uv, avs48_bin_width_uv. reflexivity.
Qed.

(* Lemma 4: step_gate passes in-range value 50 *)
Lemma step_gate_in_range : step_gate_input 50 = 50.
Proof.
  unfold step_gate_input. simpl. reflexivity.
Qed.

(* Lemma 5: step_gate clamps out-of-range value 100 to 0 *)
Lemma step_gate_clamp_out_of_range : step_gate_input 100 = 0.
Proof.
  unfold step_gate_input. simpl. reflexivity.
Qed.

(* Lemma 6: step_gate passes 0 as 0 *)
Lemma step_gate_zero : step_gate_input 0 = 0.
Proof.
  unfold step_gate_input. simpl. reflexivity.
Qed.

(* Lemma 7: step_gate passes maximum in-range value 95 *)
Lemma step_gate_max_in_range : step_gate_input 95 = 95.
Proof.
  unfold step_gate_input. simpl. reflexivity.
Qed.

(* Lemma 8 (extra): avs96_steps is nonzero *)
Lemma avs96_steps_ne_zero : avs96_steps <> 0.
Proof.
  unfold avs96_steps. lia.
Qed.

End Avs96Safe.
