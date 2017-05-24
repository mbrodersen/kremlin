/- ********************************************************************-/
/-                                                                     -/
/-              The Compcert verified compiler                         -/
/-                                                                     -/
/-          Xavier Leroy, INRIA Paris-Rocquencourt                     -/
/-                                                                     -/
/-  Copyright Institut National de Recherche en Informatique et en     -/
/-  Automatique.  All rights reserved.  This file is distributed       -/
/-  under the terms of the GNU General Public License as published by  -/
/-  the Free Software Foundation, either version 2 of the License, or  -/
/-  (at your option) any later version.  This file is also distributed -/
/-  under the terms of the INRIA Non-Commercial License Agreement.     -/
/-                                                                     -/
/- ********************************************************************-/

/- Observable events, execution traces, and semantics of external calls. -/

Require Import String
Require Import Coqlib
Require Intv
Require Import AST
Require Import Integers
Require Import Floats
Require Import Values
Require Import Memory
Require Import Globalenvs

/- * Events and traces -/

/- The observable behaviour of programs is stated in terms of
  input/output events, which represent the actions of the program
  that the external world can observe.  CompCert leaves much flexibility as to
  the exact content of events: the only requirement is that they
  do not expose memory states nor pointer values
  (other than pointers to global variables), because these
  are not preserved literally during compilation.  For concreteness,
  we use the following type for events.  Each event represents either:

- A system call (e.g. an input/output operation), recording the
  name of the system call, its parameters, and its result.

- A volatile load from a global memory location, recording the chunk
  and address being read and the value just read.

- A volatile store to a global memory location, recording the chunk
  and address being written and the value stored there.

- An annotation, recording the text of the annotation and the values
  of the arguments.

  The values attached to these events are of the following form.
  As mentioned above, we do not expose pointer values directly.
  Pointers relative to a global variable are shown with the name
  of the variable instead of the block identifier.
-/

inductive eventval : Type :=
| EVint : int32 → eventval
| EVlong : int64 → eventval
| EVfloat : float → eventval
| EVsingle : float32 → eventval
| EVptr_global : ident → ptrofs → eventval

inductive event : Type :=
| Event_syscall : string → list eventval → eventval → event
| Event_vload : memory_chunk → ident → ptrofs → eventval → event
| Event_vstore : memory_chunk → ident → ptrofs → eventval → event
| Event_annot : string → list eventval → event

/- The dynamic semantics for programs collect traces of events.
  Traces are of two kinds: finite (type [trace]) or infinite (type [traceinf]). -/

def trace := list event

def E0 : trace := nil

def Eapp (t1 t2 : trace) : trace := t1 ++ t2

CoInductive traceinf : Type :=
| Econsinf : event → traceinf → traceinf

def Eappinf (t : trace) (T : traceinf) {struct t} : traceinf :=
  match t with
| nil := T
| ev :: t' := Econsinf ev (Eappinf t' T)
  end

/- Concatenation of traces is written [**] in the finite case
  or [***] in the infinite case. -/

Infix "**" := Eapp (at level 60, right associativity)
Infix "***" := Eappinf (at level 60, right associativity)

lemma E0_left : ∀ t, E0 ** t = t
Proof. auto. Qed

lemma E0_right : ∀ t, t ** E0 = t
Proof. intros. unfold E0, Eapp. rewrite <- app_nil_end. auto. Qed

lemma Eapp_assoc : ∀ t1 t2 t3, (t1 ** t2) ** t3 = t1 ** (t2 ** t3)
Proof. intros. unfold Eapp, trace. apply app_ass. Qed

lemma Eapp_E0_inv : ∀ t1 t2, t1 ** t2 = E0 → t1 = E0 ∧ t2 = E0
Proof (@app_eq_nil event)

lemma E0_left_inf : ∀ T, E0 *** T = T
Proof. auto. Qed

lemma Eappinf_assoc : ∀ t1 t2 T, (t1 ** t2) *** T = t1 *** (t2 *** T)
Proof
  induction t1; intros; simpl. auto. decEq; auto
Qed

Hint Rewrite E0_left E0_right Eapp_assoc
             E0_left_inf Eappinf_assoc : trace_rewrite

Opaque trace E0 Eapp Eappinf

/- The following [traceEq] tactic proves equalities between traces
  or infinite traces. -/

Ltac substTraceHyp :=
  match goal with
| [ H : (@eq trace ?x ?y) |- _ ] :=
       subst x || clear H
  end

Ltac decomposeTraceEq :=
  match goal with
| [ |- (_ ** _) = (_ ** _) ] :=
      apply (f_equal2 Eapp); auto; decomposeTraceEq
| _ :=
      auto
  end

Ltac traceEq :=
  repeat substTraceHyp; autorewrite with trace_rewrite; decomposeTraceEq

/- Bisimilarity between infinite traces. -/

CoInductive traceinf_sim : traceinf → traceinf → Prop :=
| traceinf_sim_cons : ∀ e T1 T2,
      traceinf_sim T1 T2 →
      traceinf_sim (Econsinf e T1) (Econsinf e T2)

lemma traceinf_sim_refl :
  ∀ T, traceinf_sim T T
Proof
  cofix COINDHYP; intros
  destruct T. constructor. apply COINDHYP
Qed

lemma traceinf_sim_sym :
  ∀ T1 T2, traceinf_sim T1 T2 → traceinf_sim T2 T1
Proof
  cofix COINDHYP; intros. inv H; constructor; auto
Qed

lemma traceinf_sim_trans :
  ∀ T1 T2 T3,
  traceinf_sim T1 T2 → traceinf_sim T2 T3 → traceinf_sim T1 T3
Proof
  cofix COINDHYP;intros. inv H; inv H0; constructor; eauto
Qed

CoInductive traceinf_sim' : traceinf → traceinf → Prop :=
| traceinf_sim'_cons : ∀ t T1 T2,
      t ≠ E0 → traceinf_sim' T1 T2 → traceinf_sim' (t *** T1) (t *** T2)

lemma traceinf_sim'_sim :
  ∀ T1 T2, traceinf_sim' T1 T2 → traceinf_sim T1 T2
Proof
  cofix COINDHYP; intros. inv H
  destruct t. elim H0; auto
Transparent Eappinf
Transparent E0
  simpl
  destruct t. simpl. constructor. apply COINDHYP; auto
  constructor. apply COINDHYP
  constructor. unfold E0; congruence. auto
Qed

/- An alternate presentation of infinite traces as
  infinite concatenations of nonempty finite traces. -/

CoInductive traceinf' : Type :=
| Econsinf' : ∀ (t : trace) (T : traceinf'), t ≠ E0 → traceinf'

Program def split_traceinf' (t : trace) (T : traceinf') (NE : t ≠ E0) : event * traceinf' :=
  match t with
| nil := _
| e :: nil := (e, T)
| e :: t' := (e, Econsinf' t' T _)
  end
Next Obligation
  elimtype false. elim NE. auto
Qed
Next Obligation
  red; intro. elim (H e). rewrite H0. auto
Qed

CoFixpoint traceinf_of_traceinf' (T' : traceinf') : traceinf :=
  match T' with
| Econsinf' t T'' NOTEMPTY :=
      let (e, tl) := split_traceinf' t T'' NOTEMPTY in
      Econsinf e (traceinf_of_traceinf' tl)
  end

theorem unroll_traceinf' :
  ∀ T, T = match T with Econsinf' t T' NE := Econsinf' t T' NE end
Proof
  intros. destruct T; auto
Qed

theorem unroll_traceinf :
  ∀ T, T = match T with Econsinf t T' := Econsinf t T' end
Proof
  intros. destruct T; auto
Qed

lemma traceinf_traceinf'_app :
  ∀ t T NE,
  traceinf_of_traceinf' (Econsinf' t T NE) = t *** traceinf_of_traceinf' T
Proof
  induction t
  intros. elim NE. auto
  intros. simpl
  rewrite (unroll_traceinf (traceinf_of_traceinf' (Econsinf' (a :: t) T NE)))
  simpl. destruct t. auto
Transparent Eappinf
  simpl. f_equal. apply IHt
Qed

/- Prefixes of traces. -/

def trace_prefix (t1 t2 : trace) :=
  ∃ t3, t2 = t1 ** t3

def traceinf_prefix (t1 : trace) (T2 : traceinf) :=
  ∃ T3, T2 = t1 *** T3

lemma trace_prefix_app :
  ∀ t1 t2 t,
  trace_prefix t1 t2 →
  trace_prefix (t ** t1) (t ** t2)
Proof
  intros. destruct H as [t3 EQ]. ∃ t3. traceEq
Qed

lemma traceinf_prefix_app :
  ∀ t1 T2 t,
  traceinf_prefix t1 T2 →
  traceinf_prefix (t ** t1) (t *** T2)
Proof
  intros. destruct H as [T3 EQ]. ∃ T3. subst T2. traceEq
Qed

/- * Relating values and event values -/

Set Implicit Arguments

section EVENTVAL

/- Symbol environment used to translate between global variable names and their block identifiers. -/
parameter ge : Senv.t

/- Translation between values and event values. -/

inductive eventval_match : eventval → typ → val → Prop :=
| ev_match_int : ∀ i,
      eventval_match (EVint i) Tint (Vint i)
| ev_match_long : ∀ i,
      eventval_match (EVlong i) Tlong (Vlong i)
| ev_match_float : ∀ f,
      eventval_match (EVfloat f) Tfloat (Vfloat f)
| ev_match_single : ∀ f,
      eventval_match (EVsingle f) Tsingle (Vsingle f)
| ev_match_ptr : ∀ id b ofs,
      Senv.public_symbol ge id = tt →
      Senv.find_symbol ge id = some b →
      eventval_match (EVptr_global id ofs) Tptr (Vptr b ofs)

inductive eventval_list_match : list eventval → list typ → list val → Prop :=
| evl_match_nil :
      eventval_list_match nil nil nil
| evl_match_cons :
      ∀ ev1 evl ty1 tyl v1 vl,
      eventval_match ev1 ty1 v1 →
      eventval_list_match evl tyl vl →
      eventval_list_match (ev1::evl) (ty1::tyl) (v1::vl)

/- Some properties of these translation predicates. -/

lemma eventval_match_type :
  ∀ ev ty v,
  eventval_match ev ty v → Val.has_type v ty
Proof
  intros. inv H; simpl; auto. unfold Tptr; destruct Archi.ptr64; auto
Qed

lemma eventval_list_match_length :
  ∀ evl tyl vl, eventval_list_match evl tyl vl → List.length vl = List.length tyl
Proof
  induction 1; simpl; eauto
Qed

lemma eventval_match_lessdef :
  ∀ ev ty v1 v2,
  eventval_match ev ty v1 → Val.lessdef v1 v2 → eventval_match ev ty v2
Proof
  intros. inv H; inv H0; constructor; auto
Qed

lemma eventval_list_match_lessdef :
  ∀ evl tyl vl1, eventval_list_match evl tyl vl1 →
  ∀ vl2, Val.lessdef_list vl1 vl2 → eventval_list_match evl tyl vl2
Proof
  induction 1; intros. inv H; constructor
  inv H1. constructor. eapply eventval_match_lessdef; eauto. eauto
Qed

/- Determinism -/

lemma eventval_match_determ_1 :
  ∀ ev ty v1 v2, eventval_match ev ty v1 → eventval_match ev ty v2 → v1 = v2
Proof
  intros. inv H; inv H0; auto. congruence
Qed

lemma eventval_match_determ_2 :
  ∀ ev1 ev2 ty v, eventval_match ev1 ty v → eventval_match ev2 ty v → ev1 = ev2
Proof
  intros. inv H; inv H0; auto
  decEq. eapply Senv.find_symbol_injective; eauto
Qed

lemma eventval_list_match_determ_2 :
  ∀ evl1 tyl vl, eventval_list_match evl1 tyl vl →
  ∀ evl2, eventval_list_match evl2 tyl vl → evl1 = evl2
Proof
  induction 1; intros. inv H. auto. inv H1. f_equal; eauto
  eapply eventval_match_determ_2; eauto
Qed

/- Validity -/

def eventval_valid (ev : eventval) : Prop :=
  match ev with
| EVint _ := true
| EVlong _ := true
| EVfloat _ := true
| EVsingle _ := true
| EVptr_global id ofs := Senv.public_symbol ge id = tt
  end

def eventval_type (ev : eventval) : typ :=
  match ev with
| EVint _ := Tint
| EVlong _ := Tlong
| EVfloat _ := Tfloat
| EVsingle _ := Tsingle
| EVptr_global id ofs := Tptr
  end

lemma eventval_match_receptive :
  ∀ ev1 ty v1 ev2,
  eventval_match ev1 ty v1 →
  eventval_valid ev1 → eventval_valid ev2 → eventval_type ev1 = eventval_type ev2 →
  ∃ v2, eventval_match ev2 ty v2
Proof
  intros. unfold eventval_type, Tptr in H2. remember Archi.ptr64 as ptr64
  inversion H; subst ev1 ty v1; clear H; destruct ev2; simpl in H2; inv H2
- ∃ (Vint i0); constructor
- simpl in H1; exploit Senv.public_symbol_exists; eauto. intros [b FS]
  ∃ (Vptr b i1); rewrite H3. constructor; auto
- ∃ (Vlong i0); constructor
- simpl in H1; exploit Senv.public_symbol_exists; eauto. intros [b FS]
  ∃ (Vptr b i1); rewrite H3; constructor; auto
- ∃ (Vfloat f0); constructor
- destruct Archi.ptr64; discriminate
- ∃ (Vsingle f0); constructor; auto
- destruct Archi.ptr64; discriminate
- ∃ (Vint i); unfold Tptr; rewrite H5; constructor
- ∃ (Vlong i); unfold Tptr; rewrite H5; constructor
- destruct Archi.ptr64; discriminate
- destruct Archi.ptr64; discriminate
- exploit Senv.public_symbol_exists. eexact H1. intros [b' FS]
  ∃ (Vptr b' i0); constructor; auto
Qed

lemma eventval_match_valid :
  ∀ ev ty v, eventval_match ev ty v → eventval_valid ev
Proof
  destruct 1; simpl; auto
Qed

lemma eventval_match_same_type :
  ∀ ev1 ty v1 ev2 v2,
  eventval_match ev1 ty v1 → eventval_match ev2 ty v2 → eventval_type ev1 = eventval_type ev2
Proof
  destruct 1; intros EV; inv EV; auto
Qed

end EVENTVAL

/- Invariance under changes to the global environment -/

section EVENTVAL_INV

Variables ge1 ge2 : Senv.t

Hypothesis public_preserved :
  ∀ id, Senv.public_symbol ge2 id = Senv.public_symbol ge1 id

lemma eventval_valid_preserved :
  ∀ ev, eventval_valid ge1 ev → eventval_valid ge2 ev
Proof
  intros. destruct ev; simpl in *; auto. rewrite <- H; auto
Qed

Hypothesis symbols_preserved :
  ∀ id, Senv.find_symbol ge2 id = Senv.find_symbol ge1 id

lemma eventval_match_preserved :
  ∀ ev ty v,
  eventval_match ge1 ev ty v → eventval_match ge2 ev ty v
Proof
  induction 1; constructor; auto
  rewrite public_preserved; auto
  rewrite symbols_preserved; auto
Qed

lemma eventval_list_match_preserved :
  ∀ evl tyl vl,
  eventval_list_match ge1 evl tyl vl → eventval_list_match ge2 evl tyl vl
Proof
  induction 1; constructor; auto. eapply eventval_match_preserved; eauto
Qed

end EVENTVAL_INV

/- Compatibility with memory injections -/

section EVENTVAL_INJECT

parameter f : block → option (block * ℤ)
parameter ge1 ge2 : Senv.t

def symbols_inject : Prop :=
   (∀ id, Senv.public_symbol ge2 id = Senv.public_symbol ge1 id)
∧ (∀ id b1 b2 delta,
     f b1 = some(b2, delta) → Senv.find_symbol ge1 id = some b1 →
     delta = 0 ∧ Senv.find_symbol ge2 id = some b2)
∧ (∀ id b1,
     Senv.public_symbol ge1 id = tt → Senv.find_symbol ge1 id = some b1 →
     ∃ b2, f b1 = some(b2, 0) ∧ Senv.find_symbol ge2 id = some b2)
∧ (∀ b1 b2 delta,
     f b1 = some(b2, delta) →
     Senv.block_is_volatile ge2 b2 = Senv.block_is_volatile ge1 b1)

Hypothesis symb_inj : symbols_inject

lemma eventval_match_inject :
  ∀ ev ty v1 v2,
  eventval_match ge1 ev ty v1 → Val.inject f v1 v2 → eventval_match ge2 ev ty v2
Proof
  intros. inv H; inv H0; try constructor; auto
  destruct symb_inj as (A & B & C & D). exploit C; eauto. intros [b3 [EQ FS]]. rewrite H4 in EQ; inv EQ
  rewrite Ptrofs.add_zero. constructor; auto. rewrite A; auto
Qed

lemma eventval_match_inject_2 :
  ∀ ev ty v1,
  eventval_match ge1 ev ty v1 →
  ∃ v2, eventval_match ge2 ev ty v2 ∧ Val.inject f v1 v2
Proof
  intros. inv H; try (econstructor; split; eauto; constructor; fail)
  destruct symb_inj as (A & B & C & D). exploit C; eauto. intros [b2 [EQ FS]]
  ∃ (Vptr b2 ofs); split. econstructor; eauto
  econstructor; eauto. rewrite Ptrofs.add_zero; auto
Qed

lemma eventval_list_match_inject :
  ∀ evl tyl vl1, eventval_list_match ge1 evl tyl vl1 →
  ∀ vl2, Val.inject_list f vl1 vl2 → eventval_list_match ge2 evl tyl vl2
Proof
  induction 1; intros. inv H; constructor
  inv H1. constructor. eapply eventval_match_inject; eauto. eauto
Qed

end EVENTVAL_INJECT

/- * Matching traces. -/

section MATCH_TRACES

parameter ge : Senv.t

/- Matching between traces corresponding to single transitions.
  Arguments (provided by the program) must be equal.
  Results (provided by the outside world) can vary as long as they
  can be converted safely to values. -/

inductive match_traces : trace → trace → Prop :=
| match_traces_E0 :
      match_traces nil nil
| match_traces_syscall : ∀ id args res1 res2,
      eventval_valid ge res1 → eventval_valid ge res2 → eventval_type res1 = eventval_type res2 →
      match_traces (Event_syscall id args res1 :: nil) (Event_syscall id args res2 :: nil)
| match_traces_vload : ∀ chunk id ofs res1 res2,
      eventval_valid ge res1 → eventval_valid ge res2 → eventval_type res1 = eventval_type res2 →
      match_traces (Event_vload chunk id ofs res1 :: nil) (Event_vload chunk id ofs res2 :: nil)
| match_traces_vstore : ∀ chunk id ofs arg,
      match_traces (Event_vstore chunk id ofs arg :: nil) (Event_vstore chunk id ofs arg :: nil)
| match_traces_annot : ∀ id args,
      match_traces (Event_annot id args :: nil) (Event_annot id args :: nil)

end MATCH_TRACES

/- Invariance by change of global environment -/

section MATCH_TRACES_INV

Variables ge1 ge2 : Senv.t

Hypothesis public_preserved :
  ∀ id, Senv.public_symbol ge2 id = Senv.public_symbol ge1 id

lemma match_traces_preserved :
  ∀ t1 t2, match_traces ge1 t1 t2 → match_traces ge2 t1 t2
Proof
  induction 1; constructor; auto; eapply eventval_valid_preserved; eauto
Qed

end MATCH_TRACES_INV

/- An output trace is a trace composed only of output events,
  that is, events that do not take any result from the outside world. -/

def output_event (ev : event) : Prop :=
  match ev with
| Event_syscall _ _ _ := false
| Event_vload _ _ _ _ := false
| Event_vstore _ _ _ _ := true
| Event_annot _ _ := true
  end

def output_trace (t : trace) : Prop :=
  match t with
| nil := true
| ev :: t' := output_event ev ∧ output_trace t'
  end

/- * Semantics of volatile memory accesses -/

inductive volatile_load (ge : Senv.t) :
                   memory_chunk → mem → block → ptrofs → trace → val → Prop :=
| volatile_load_vol : ∀ chunk m b ofs id ev v,
      Senv.block_is_volatile ge b = tt →
      Senv.find_symbol ge id = some b →
      eventval_match ge ev (type_of_chunk chunk) v →
      volatile_load ge chunk m b ofs
                      (Event_vload chunk id ofs ev :: nil)
                      (Val.load_result chunk v)
| volatile_load_nonvol : ∀ chunk m b ofs v,
      Senv.block_is_volatile ge b = ff →
      Mem.load chunk m b (Ptrofs.unsigned ofs) = some v →
      volatile_load ge chunk m b ofs E0 v

inductive volatile_store (ge : Senv.t) :
                  memory_chunk → mem → block → ptrofs → val → trace → mem → Prop :=
| volatile_store_vol : ∀ chunk m b ofs id ev v,
      Senv.block_is_volatile ge b = tt →
      Senv.find_symbol ge id = some b →
      eventval_match ge ev (type_of_chunk chunk) (Val.load_result chunk v) →
      volatile_store ge chunk m b ofs v
                      (Event_vstore chunk id ofs ev :: nil)
                      m
| volatile_store_nonvol : ∀ chunk m b ofs v m',
      Senv.block_is_volatile ge b = ff →
      Mem.store chunk m b (Ptrofs.unsigned ofs) v = some m' →
      volatile_store ge chunk m b ofs v E0 m'

/- * Semantics of external functions -/

/- For each external function, its behavior is defined by a predicate relating:
- the global symbol environment
- the values of the arguments passed to this function
- the memory state before the call
- the result value of the call
- the memory state after the call
- the trace generated by the call (can be empty).
-/

def extcall_sem : Type :=
  Senv.t → list val → mem → trace → val → mem → Prop

/- We now specify the expected properties of this predicate. -/

def loc_out_of_bounds (m : mem) (b : block) (ofs : ℤ) : Prop :=
  ~Mem.perm m b ofs Max Nonempty

def loc_not_writable (m : mem) (b : block) (ofs : ℤ) : Prop :=
  ~Mem.perm m b ofs Max Writable

def loc_unmapped (f : meminj) (b : block) (ofs : ℤ) : Prop :=
  f b = none

def loc_out_of_reach (f : meminj) (m : mem) (b : block) (ofs : ℤ) : Prop :=
  ∀ b0 delta,
  f b0 = some(b, delta) → ~Mem.perm m b0 (ofs - delta) Max Nonempty

def inject_separated (f f' : meminj) (m1 m2 : mem) : Prop :=
  ∀ b1 b2 delta,
  f b1 = none → f' b1 = some(b2, delta) →
  ~Mem.valid_block m1 b1 ∧ ~Mem.valid_block m2 b2

structure extcall_properties (sem : extcall_sem) (sg : signature) : Prop :=
  mk_extcall_properties {

/- The return value of an external call must agree with its signature. -/
  ec_well_typed :
    ∀ ge vargs m1 t vres m2,
    sem ge vargs m1 t vres m2 →
    Val.has_type vres (proj_sig_res sg);

/- The semantics is invariant under change of global environment that preserves symbols. -/
  ec_symbols_preserved :
    ∀ ge1 ge2 vargs m1 t vres m2,
    Senv.equiv ge1 ge2 →
    sem ge1 vargs m1 t vres m2 →
    sem ge2 vargs m1 t vres m2;

/- External calls cannot invalidate memory blocks.  (Remember that
  freeing a block does not invalidate its block identifier.) -/
  ec_valid_block :
    ∀ ge vargs m1 t vres m2 b,
    sem ge vargs m1 t vres m2 →
    Mem.valid_block m1 b → Mem.valid_block m2 b;

/- External calls cannot increase the max permissions of a valid block.
    They can decrease the max permissions, e.g. by freeing. -/
  ec_max_perm :
    ∀ ge vargs m1 t vres m2 b ofs p,
    sem ge vargs m1 t vres m2 →
    Mem.valid_block m1 b → Mem.perm m2 b ofs Max p → Mem.perm m1 b ofs Max p;

/- External call cannot modify memory unless they have [Max, Writable]
   permissions. -/
  ec_readonly :
    ∀ ge vargs m1 t vres m2,
    sem ge vargs m1 t vres m2 →
    Mem.unchanged_on (loc_not_writable m1) m1 m2;

/- External calls must commute with memory extensions, in the
  following sense. -/
  ec_mem_extends :
    ∀ ge vargs m1 t vres m2 m1' vargs',
    sem ge vargs m1 t vres m2 →
    Mem.extends m1 m1' →
    Val.lessdef_list vargs vargs' →
    ∃ vres', ∃ m2',
       sem ge vargs' m1' t vres' m2'
    ∧ Val.lessdef vres vres'
    ∧ Mem.extends m2 m2'
    ∧ Mem.unchanged_on (loc_out_of_bounds m1) m1' m2';

/- External calls must commute with memory injections,
  in the following sense. -/
  ec_mem_inject :
    ∀ ge1 ge2 vargs m1 t vres m2 f m1' vargs',
    symbols_inject f ge1 ge2 →
    sem ge1 vargs m1 t vres m2 →
    Mem.inject f m1 m1' →
    Val.inject_list f vargs vargs' →
    ∃ f', ∃ vres', ∃ m2',
       sem ge2 vargs' m1' t vres' m2'
    ∧ Val.inject f' vres vres'
    ∧ Mem.inject f' m2 m2'
    ∧ Mem.unchanged_on (loc_unmapped f) m1 m2
    ∧ Mem.unchanged_on (loc_out_of_reach f m1) m1' m2'
    ∧ inject_incr f f'
    ∧ inject_separated f f' m1 m1';

/- External calls produce at most one event. -/
  ec_trace_length :
    ∀ ge vargs m t vres m',
    sem ge vargs m t vres m' → (length t <= 1)%ℕ;

/- External calls must be receptive to changes of traces by another, matching trace. -/
  ec_receptive :
    ∀ ge vargs m t1 vres1 m1 t2,
    sem ge vargs m t1 vres1 m1 → match_traces ge t1 t2 →
    ∃ vres2, ∃ m2, sem ge vargs m t2 vres2 m2;

/- External calls must be deterministic up to matching between traces. -/
  ec_determ :
    ∀ ge vargs m t1 vres1 m1 t2 vres2 m2,
    sem ge vargs m t1 vres1 m1 → sem ge vargs m t2 vres2 m2 →
    match_traces ge t1 t2 ∧ (t1 = t2 → vres1 = vres2 ∧ m1 = m2)
}

/- ** Semantics of volatile loads -/

inductive volatile_load_sem (chunk : memory_chunk) (ge : Senv.t) :
              list val → mem → trace → val → mem → Prop :=
| volatile_load_sem_intro : ∀ b ofs m t v,
      volatile_load ge chunk m b ofs t v →
      volatile_load_sem chunk ge (Vptr b ofs :: nil) m t v m

lemma volatile_load_preserved :
  ∀ ge1 ge2 chunk m b ofs t v,
  Senv.equiv ge1 ge2 →
  volatile_load ge1 chunk m b ofs t v →
  volatile_load ge2 chunk m b ofs t v
Proof
  intros. destruct H as (A & B & C). inv H0; constructor; auto
  rewrite C; auto
  rewrite A; auto
  eapply eventval_match_preserved; eauto
  rewrite C; auto
Qed

lemma volatile_load_extends :
  ∀ ge chunk m b ofs t v m',
  volatile_load ge chunk m b ofs t v →
  Mem.extends m m' →
  ∃ v', volatile_load ge chunk m' b ofs t v' ∧ Val.lessdef v v'
Proof
  intros. inv H
  econstructor; split; eauto. econstructor; eauto
  exploit Mem.load_extends; eauto. intros [v' [A B]]. ∃ v'; split; auto. constructor; auto
Qed

lemma volatile_load_inject :
  ∀ ge1 ge2 f chunk m b ofs t v b' ofs' m',
  symbols_inject f ge1 ge2 →
  volatile_load ge1 chunk m b ofs t v →
  Val.inject f (Vptr b ofs) (Vptr b' ofs') →
  Mem.inject f m m' →
  ∃ v', volatile_load ge2 chunk m' b' ofs' t v' ∧ Val.inject f v v'
Proof
  intros until m'; intros SI VL VI MI. generalize SI; intros (A & B & C & D)
  inv VL
- /- volatile load -/
  inv VI. exploit B; eauto. intros [U V]. subst delta
  exploit eventval_match_inject_2; eauto. intros (v2 & X & Y)
  rewrite Ptrofs.add_zero. ∃ (Val.load_result chunk v2); split
  constructor; auto
  erewrite D; eauto
  apply Val.load_result_inject. auto
- /- normal load -/
  exploit Mem.loadv_inject; eauto. simpl; eauto. simpl; intros (v2 & X & Y)
  ∃ v2; split; auto
  constructor; auto
  inv VI. erewrite D; eauto
Qed

lemma volatile_load_receptive :
  ∀ ge chunk m b ofs t1 t2 v1,
  volatile_load ge chunk m b ofs t1 v1 → match_traces ge t1 t2 →
  ∃ v2, volatile_load ge chunk m b ofs t2 v2
Proof
  intros. inv H; inv H0
  exploit eventval_match_receptive; eauto. intros [v' EM]
  ∃ (Val.load_result chunk v'). constructor; auto
  ∃ v1; constructor; auto
Qed

lemma volatile_load_ok :
  ∀ chunk,
  extcall_properties (volatile_load_sem chunk)
                     (mksignature (Tptr :: nil) (some (type_of_chunk chunk)) cc_default)
Proof
  intros; constructor; intros
/- well typed -/
- unfold proj_sig_res; simpl. inv H. inv H0. apply Val.load_result_type
  eapply Mem.load_type; eauto
/- symbols -/
- inv H0. constructor. eapply volatile_load_preserved; eauto
/- valid blocks -/
- inv H; auto
/- max perms -/
- inv H; auto
/- readonly -/
- inv H. apply Mem.unchanged_on_refl
/- mem extends -/
- inv H. inv H1. inv H6. inv H4
  exploit volatile_load_extends; eauto. intros [v' [A B]]
  ∃ v'; ∃ m1'; intuition. constructor; auto
/- mem injects -/
- inv H0. inv H2. inv H7. inversion H5; subst
  exploit volatile_load_inject; eauto. intros [v' [A B]]
  ∃ f; ∃ v'; ∃ m1'; intuition. constructor; auto
  red; intros. congruence
/- trace length -/
- inv H; inv H0; simpl; omega
/- receptive -/
- inv H. exploit volatile_load_receptive; eauto. intros [v2 A]
  ∃ v2; ∃ m1; constructor; auto
/- determ -/
- inv H; inv H0. inv H1; inv H7; try congruence
  assert (id = id0) by (eapply Senv.find_symbol_injective; eauto). subst id0
  split. constructor
  eapply eventval_match_valid; eauto
  eapply eventval_match_valid; eauto
  eapply eventval_match_same_type; eauto
  intros EQ; inv EQ
  assert (v = v0) by (eapply eventval_match_determ_1; eauto). subst v0
  auto
  split. constructor. intuition congruence
Qed

/- ** Semantics of volatile stores -/

inductive volatile_store_sem (chunk : memory_chunk) (ge : Senv.t) :
              list val → mem → trace → val → mem → Prop :=
| volatile_store_sem_intro : ∀ b ofs m1 v t m2,
      volatile_store ge chunk m1 b ofs v t m2 →
      volatile_store_sem chunk ge (Vptr b ofs :: v :: nil) m1 t Vundef m2

lemma volatile_store_preserved :
  ∀ ge1 ge2 chunk m1 b ofs v t m2,
  Senv.equiv ge1 ge2 →
  volatile_store ge1 chunk m1 b ofs v t m2 →
  volatile_store ge2 chunk m1 b ofs v t m2
Proof
  intros. destruct H as (A & B & C). inv H0; constructor; auto
  rewrite C; auto
  rewrite A; auto
  eapply eventval_match_preserved; eauto
  rewrite C; auto
Qed

lemma volatile_store_readonly :
  ∀ ge chunk1 m1 b1 ofs1 v t m2,
  volatile_store ge chunk1 m1 b1 ofs1 v t m2 →
  Mem.unchanged_on (loc_not_writable m1) m1 m2
Proof
  intros. inv H
  apply Mem.unchanged_on_refl
  eapply Mem.store_unchanged_on; eauto
  exploit Mem.store_valid_access_3; eauto. intros [P Q]
  intros. unfold loc_not_writable. red; intros. elim H2
  apply Mem.perm_cur_max. apply P. auto
Qed

lemma volatile_store_extends :
  ∀ ge chunk m1 b ofs v t m2 m1' v',
  volatile_store ge chunk m1 b ofs v t m2 →
  Mem.extends m1 m1' →
  Val.lessdef v v' →
  ∃ m2',
     volatile_store ge chunk m1' b ofs v' t m2'
  ∧ Mem.extends m2 m2'
  ∧ Mem.unchanged_on (loc_out_of_bounds m1) m1' m2'
Proof
  intros. inv H
- econstructor; split. econstructor; eauto
  eapply eventval_match_lessdef; eauto. apply Val.load_result_lessdef; auto
  auto with mem
- exploit Mem.store_within_extends; eauto. intros [m2' [A B]]
  ∃ m2'; intuition
+ econstructor; eauto
+ eapply Mem.store_unchanged_on; eauto
  unfold loc_out_of_bounds; intros
  assert (Mem.perm m1 b i Max Nonempty)
  { apply Mem.perm_cur_max. apply Mem.perm_implies with Writable; auto with mem
    exploit Mem.store_valid_access_3. eexact H3. intros [P Q]. eauto. }
  tauto
Qed

lemma volatile_store_inject :
  ∀ ge1 ge2 f chunk m1 b ofs v t m2 m1' b' ofs' v',
  symbols_inject f ge1 ge2 →
  volatile_store ge1 chunk m1 b ofs v t m2 →
  Val.inject f (Vptr b ofs) (Vptr b' ofs') →
  Val.inject f v v' →
  Mem.inject f m1 m1' →
  ∃ m2',
       volatile_store ge2 chunk m1' b' ofs' v' t m2'
    ∧ Mem.inject f m2 m2'
    ∧ Mem.unchanged_on (loc_unmapped f) m1 m2
    ∧ Mem.unchanged_on (loc_out_of_reach f m1) m1' m2'
Proof
  intros until v'; intros SI VS AI VI MI
  generalize SI; intros (P & Q & R & S)
  inv VS
- /- volatile store -/
  inv AI. exploit Q; eauto. intros [A B]. subst delta
  rewrite Ptrofs.add_zero. ∃ m1'; split
  constructor; auto. erewrite S; eauto
  eapply eventval_match_inject; eauto. apply Val.load_result_inject. auto
  intuition auto with mem
- /- normal store -/
  inversion AI; subst
  assert (Mem.storev chunk m1 (Vptr b ofs) v = some m2). simpl; auto
  exploit Mem.storev_mapped_inject; eauto. intros [m2' [A B]]
  ∃ m2'; intuition auto
+ constructor; auto. erewrite S; eauto
+ eapply Mem.store_unchanged_on; eauto
  unfold loc_unmapped; intros. inv AI; congruence
+ eapply Mem.store_unchanged_on; eauto
  unfold loc_out_of_reach; intros. red; intros. simpl in A
  assert (EQ : Ptrofs.unsigned (Ptrofs.add ofs (Ptrofs.repr delta)) = Ptrofs.unsigned ofs + delta)
  by (eapply Mem.address_inject; eauto with mem)
  rewrite EQ in *
  eelim H3; eauto
  exploit Mem.store_valid_access_3. eexact H0. intros [X Y]
  apply Mem.perm_cur_max. apply Mem.perm_implies with Writable; auto with mem
  apply X. omega
Qed

lemma volatile_store_receptive :
  ∀ ge chunk m b ofs v t1 m1 t2,
  volatile_store ge chunk m b ofs v t1 m1 → match_traces ge t1 t2 → t1 = t2
Proof
  intros. inv H; inv H0; auto
Qed

lemma volatile_store_ok :
  ∀ chunk,
  extcall_properties (volatile_store_sem chunk)
                     (mksignature (Tptr :: type_of_chunk chunk :: nil) none cc_default)
Proof
  intros; constructor; intros
/- well typed -/
- unfold proj_sig_res; simpl. inv H; constructor
/- symbols preserved -/
- inv H0. constructor. eapply volatile_store_preserved; eauto
/- valid block -/
- inv H. inv H1. auto. eauto with mem
/- perms -/
- inv H. inv H2. auto. eauto with mem
/- readonly -/
- inv H. eapply volatile_store_readonly; eauto
/- mem extends-/
- inv H. inv H1. inv H6. inv H7. inv H4
  exploit volatile_store_extends; eauto. intros [m2' [A [B C]]]
  ∃ Vundef; ∃ m2'; intuition. constructor; auto
/- mem inject -/
- inv H0. inv H2. inv H7. inv H8. inversion H5; subst
  exploit volatile_store_inject; eauto. intros [m2' [A [B [C D]]]]
  ∃ f; ∃ Vundef; ∃ m2'; intuition. constructor; auto. red; intros; congruence
/- trace length -/
- inv H; inv H0; simpl; omega
/- receptive -/
- assert (t1 = t2). inv H. eapply volatile_store_receptive; eauto
  subst t2; ∃ vres1; ∃ m1; auto
/- determ -/
- inv H; inv H0. inv H1; inv H8; try congruence
  assert (id = id0) by (eapply Senv.find_symbol_injective; eauto). subst id0
  assert (ev = ev0) by (eapply eventval_match_determ_2; eauto). subst ev0
  split. constructor. auto
  split. constructor. intuition congruence
Qed

/- ** Semantics of dynamic memory allocation (malloc) -/

inductive extcall_malloc_sem (ge : Senv.t) :
              list val → mem → trace → val → mem → Prop :=
| extcall_malloc_sem_intro : ∀ sz m m' b m'',
      Mem.alloc m (- size_chunk Mptr) (Ptrofs.unsigned sz) = (m', b) →
      Mem.store Mptr m' b (- size_chunk Mptr) (Vptrofs sz) = some m'' →
      extcall_malloc_sem ge (Vptrofs sz :: nil) m E0 (Vptr b Ptrofs.zero) m''

lemma extcall_malloc_ok :
  extcall_properties extcall_malloc_sem
                     (mksignature (Tptr :: nil) (some Tptr) cc_default)
Proof
  assert (UNCHANGED :
    ∀ (P : block → ℤ → Prop) m lo hi v m' b m'',
    Mem.alloc m lo hi = (m', b) →
    Mem.store Mptr m' b lo v = some m'' →
    Mem.unchanged_on P m m'')
  {
    intros
    apply Mem.unchanged_on_implies with (λ b1 ofs1 := b1 ≠ b)
    apply Mem.unchanged_on_trans with m'. 
    eapply Mem.alloc_unchanged_on; eauto
    eapply Mem.store_unchanged_on; eauto
    intros. eapply Mem.valid_not_valid_diff; eauto with mem
  }
  constructor; intros
/- well typed -/
- inv H. unfold proj_sig_res, Tptr; simpl. destruct Archi.ptr64; auto
/- symbols preserved -/
- inv H0; econstructor; eauto
/- valid block -/
- inv H. eauto with mem
/- perms -/
- inv H. exploit Mem.perm_alloc_inv. eauto. eapply Mem.perm_store_2; eauto
  rewrite dec_eq_false. auto
  apply Mem.valid_not_valid_diff with m1; eauto with mem
/- readonly -/
- inv H. eapply UNCHANGED; eauto
/- mem extends -/
- inv H. inv H1. inv H7
  assert (SZ : v2 = Vptrofs sz)
  { unfold Vptrofs in *. destruct Archi.ptr64; inv H5; auto. } 
  subst v2
  exploit Mem.alloc_extends; eauto. apply Zle_refl. apply Zle_refl
  intros [m3' [A B]]
  exploit Mem.store_within_extends. eexact B. eauto. eauto
  intros [m2' [C D]]
  ∃ (Vptr b Ptrofs.zero); ∃ m2'; intuition
  econstructor; eauto
  eapply UNCHANGED; eauto
/- mem injects -/
- inv H0. inv H2. inv H8
  assert (SZ : v' = Vptrofs sz)
  { unfold Vptrofs in *. destruct Archi.ptr64; inv H6; auto. } 
  subst v'
  exploit Mem.alloc_parallel_inject; eauto. apply Zle_refl. apply Zle_refl
  intros [f' [m3' [b' [ALLOC [A [B [C D]]]]]]]
  exploit Mem.store_mapped_inject. eexact A. eauto. eauto
  instantiate (1 := Vptrofs sz). unfold Vptrofs; destruct Archi.ptr64; constructor
  rewrite Zplus_0_r. intros [m2' [E G]]
  ∃ f'; ∃ (Vptr b' Ptrofs.zero); ∃ m2'; intuition auto
  econstructor; eauto
  econstructor. eauto. auto
  eapply UNCHANGED; eauto
  eapply UNCHANGED; eauto
  red; intros. destruct (eq_block b1 b)
  subst b1. rewrite C in H2. inv H2. eauto with mem
  rewrite D in H2 by auto. congruence
/- trace length -/
- inv H; simpl; omega
/- receptive -/
- assert (t1 = t2). inv H; inv H0; auto. subst t2
  ∃ vres1; ∃ m1; auto
/- determ -/
- inv H. simple inversion H0
  assert (EQ2 : sz0 = sz)
  { unfold Vptrofs in H4; destruct Archi.ptr64 eqn:SF
    rewrite <- (Ptrofs.of_int64_to_int64 SF sz0), <- (Ptrofs.of_int64_to_int64 SF sz). congruence
    rewrite <- (Ptrofs.of_int_to_int SF sz0), <- (Ptrofs.of_int_to_int SF sz). congruence
  }
  subst. 
  split. constructor. intuition congruence
Qed

/- ** Semantics of dynamic memory deallocation (free) -/

inductive extcall_free_sem (ge : Senv.t) :
              list val → mem → trace → val → mem → Prop :=
| extcall_free_sem_intro : ∀ b lo sz m m',
      Mem.load Mptr m b (Ptrofs.unsigned lo - size_chunk Mptr) = some (Vptrofs sz) →
      Ptrofs.unsigned sz > 0 →
      Mem.free m b (Ptrofs.unsigned lo - size_chunk Mptr) (Ptrofs.unsigned lo + Ptrofs.unsigned sz) = some m' →
      extcall_free_sem ge (Vptr b lo :: nil) m E0 Vundef m'

lemma extcall_free_ok :
  extcall_properties extcall_free_sem
                     (mksignature (Tptr :: nil) none cc_default)
Proof
  constructor; intros
/- well typed -/
- inv H. unfold proj_sig_res. simpl. auto
/- symbols preserved -/
- inv H0; econstructor; eauto
/- valid block -/
- inv H. eauto with mem
/- perms -/
- inv H. eapply Mem.perm_free_3; eauto
/- readonly -/
- inv H. eapply Mem.free_unchanged_on; eauto
  intros. red; intros. elim H3
  apply Mem.perm_cur_max. apply Mem.perm_implies with Freeable; auto with mem
  eapply Mem.free_range_perm; eauto
/- mem extends -/
- inv H. inv H1. inv H8. inv H6
  exploit Mem.load_extends; eauto. intros [v' [A B]]
  assert (v' = Vptrofs sz)
  { unfold Vptrofs in *; destruct Archi.ptr64; inv B; auto. }
  subst v'
  exploit Mem.free_parallel_extends; eauto. intros [m2' [C D]]
  ∃ Vundef; ∃ m2'; intuition
  econstructor; eauto
  eapply Mem.free_unchanged_on; eauto
  unfold loc_out_of_bounds; intros
  assert (Mem.perm m1 b i Max Nonempty)
  { apply Mem.perm_cur_max. apply Mem.perm_implies with Freeable; auto with mem
    eapply Mem.free_range_perm. eexact H4. eauto. }
  tauto
/- mem inject -/
- inv H0. inv H2. inv H7. inv H9
  exploit Mem.load_inject; eauto. intros [v' [A B]]
  assert (v' = Vptrofs sz)
  { unfold Vptrofs in *; destruct Archi.ptr64; inv B; auto. }
  subst v'
  assert (P : Mem.range_perm m1 b (Ptrofs.unsigned lo - size_chunk Mptr) (Ptrofs.unsigned lo + Ptrofs.unsigned sz) Cur Freeable)
    eapply Mem.free_range_perm; eauto
  exploit Mem.address_inject; eauto
    apply Mem.perm_implies with Freeable; auto with mem
    apply P. instantiate (1 := lo). 
    generalize (size_chunk_pos Mptr); omega
  intro EQ
  exploit Mem.free_parallel_inject; eauto. intros (m2' & C & D)
  ∃ f, Vundef, m2'; split
  apply extcall_free_sem_intro with (sz := sz) (m' := m2')
    rewrite EQ. rewrite <- A. f_equal. omega
    auto. auto
    rewrite ! EQ. rewrite <- C. f_equal; omega
  split. auto
  split. auto
  split. eapply Mem.free_unchanged_on; eauto. unfold loc_unmapped. intros; congruence
  split. eapply Mem.free_unchanged_on; eauto. unfold loc_out_of_reach
    intros. red; intros. eelim H2; eauto
    apply Mem.perm_cur_max. apply Mem.perm_implies with Freeable; auto with mem
    apply P. omega
  split. auto
  red; intros. congruence
/- trace length -/
- inv H; simpl; omega
/- receptive -/
- assert (t1 = t2). inv H; inv H0; auto. subst t2
  ∃ vres1; ∃ m1; auto
/- determ -/
- inv H; inv H0
  assert (EQ1 : Vptrofs sz0 = Vptrofs sz) by congruence
  assert (EQ2 : sz0 = sz)
  { unfold Vptrofs in EQ1; destruct Archi.ptr64 eqn:SF
    rewrite <- (Ptrofs.of_int64_to_int64 SF sz0), <- (Ptrofs.of_int64_to_int64 SF sz). congruence
    rewrite <- (Ptrofs.of_int_to_int SF sz0), <- (Ptrofs.of_int_to_int SF sz). congruence
  }
  subst sz0
  split. constructor. intuition congruence
Qed

/- ** Semantics of [memcpy] operations. -/

inductive extcall_memcpy_sem (sz al : ℤ) (ge : Senv.t) :
                        list val → mem → trace → val → mem → Prop :=
| extcall_memcpy_sem_intro : ∀ bdst odst bsrc osrc m bytes m',
      al = 1 ∨ al = 2 ∨ al = 4 ∨ al = 8 → sz >= 0 → (al | sz) →
      (sz > 0 → (al | Ptrofs.unsigned osrc)) →
      (sz > 0 → (al | Ptrofs.unsigned odst)) →
      bsrc ≠ bdst ∨ Ptrofs.unsigned osrc = Ptrofs.unsigned odst
                   ∨ Ptrofs.unsigned osrc + sz <= Ptrofs.unsigned odst
                   ∨ Ptrofs.unsigned odst + sz <= Ptrofs.unsigned osrc →
      Mem.loadbytes m bsrc (Ptrofs.unsigned osrc) sz = some bytes →
      Mem.storebytes m bdst (Ptrofs.unsigned odst) bytes = some m' →
      extcall_memcpy_sem sz al ge (Vptr bdst odst :: Vptr bsrc osrc :: nil) m E0 Vundef m'

lemma extcall_memcpy_ok :
  ∀ sz al,
  extcall_properties (extcall_memcpy_sem sz al)
                     (mksignature (Tptr :: Tptr :: nil) none cc_default)
Proof
  intros. constructor
- /- return type -/
  intros. inv H. constructor
- /- change of globalenv -/
  intros. inv H0. econstructor; eauto
- /- valid blocks -/
  intros. inv H. eauto with mem
- /- perms -/
  intros. inv H. eapply Mem.perm_storebytes_2; eauto
- /- readonly -/
  intros. inv H. eapply Mem.storebytes_unchanged_on; eauto
  intros; red; intros. elim H8
  apply Mem.perm_cur_max. eapply Mem.storebytes_range_perm; eauto
- /- extensions -/
  intros. inv H
  inv H1. inv H13. inv H14. inv H10. inv H11
  exploit Mem.loadbytes_length; eauto. intros LEN
  exploit Mem.loadbytes_extends; eauto. intros [bytes2 [A B]]
  exploit Mem.storebytes_within_extends; eauto. intros [m2' [C D]]
  ∃ Vundef; ∃ m2'
  split. econstructor; eauto
  split. constructor
  split. auto
  eapply Mem.storebytes_unchanged_on; eauto. unfold loc_out_of_bounds; intros
  assert (Mem.perm m1 bdst i Max Nonempty)
  apply Mem.perm_cur_max. apply Mem.perm_implies with Writable; auto with mem
  eapply Mem.storebytes_range_perm; eauto
  erewrite list_forall2_length; eauto
  tauto
- /- injections -/
  intros. inv H0. inv H2. inv H14. inv H15. inv H11. inv H12
  destruct (zeq sz 0)
+ /- special case sz = 0 -/
  assert (bytes = nil)
  { exploit (Mem.loadbytes_empty m1 bsrc (Ptrofs.unsigned osrc) sz). omega. congruence. }
  subst
  destruct (Mem.range_perm_storebytes m1' b0 (Ptrofs.unsigned (Ptrofs.add odst (Ptrofs.repr delta0))) nil)
  as [m2' SB]
  simpl. red; intros; omegaContradiction
  ∃ f, Vundef, m2'
  split. econstructor; eauto
  intros; omegaContradiction
  intros; omegaContradiction
  right; omega
  apply Mem.loadbytes_empty. omega
  split. auto
  split. eapply Mem.storebytes_empty_inject; eauto
  split. eapply Mem.storebytes_unchanged_on; eauto. unfold loc_unmapped; intros
  congruence
  split. eapply Mem.storebytes_unchanged_on; eauto
  simpl; intros; omegaContradiction
  split. apply inject_incr_refl
  red; intros; congruence
+ /- general case sz > 0 -/
  exploit Mem.loadbytes_length; eauto. intros LEN
  assert (RPSRC : Mem.range_perm m1 bsrc (Ptrofs.unsigned osrc) (Ptrofs.unsigned osrc + sz) Cur Nonempty)
    eapply Mem.range_perm_implies. eapply Mem.loadbytes_range_perm; eauto. auto with mem
  assert (RPDST : Mem.range_perm m1 bdst (Ptrofs.unsigned odst) (Ptrofs.unsigned odst + sz) Cur Nonempty)
    replace sz with (Z_of_nat (length bytes))
    eapply Mem.range_perm_implies. eapply Mem.storebytes_range_perm; eauto. auto with mem
    rewrite LEN. apply nat_of_Z_eq. omega
  assert (PSRC : Mem.perm m1 bsrc (Ptrofs.unsigned osrc) Cur Nonempty)
    apply RPSRC. omega
  assert (PDST : Mem.perm m1 bdst (Ptrofs.unsigned odst) Cur Nonempty)
    apply RPDST. omega
  exploit Mem.address_inject.  eauto. eexact PSRC. eauto. intros EQ1
  exploit Mem.address_inject.  eauto. eexact PDST. eauto. intros EQ2
  exploit Mem.loadbytes_inject; eauto. intros [bytes2 [A B]]
  exploit Mem.storebytes_mapped_inject; eauto. intros [m2' [C D]]
  ∃ f; ∃ Vundef; ∃ m2'
  split. econstructor; try rewrite EQ1; try rewrite EQ2; eauto
  intros; eapply Mem.aligned_area_inject with (m := m1); eauto
  intros; eapply Mem.aligned_area_inject with (m := m1); eauto
  eapply Mem.disjoint_or_equal_inject with (m := m1); eauto
  apply Mem.range_perm_max with Cur; auto
  apply Mem.range_perm_max with Cur; auto. omega
  split. constructor
  split. auto
  split. eapply Mem.storebytes_unchanged_on; eauto. unfold loc_unmapped; intros
  congruence
  split. eapply Mem.storebytes_unchanged_on; eauto. unfold loc_out_of_reach; intros. red; intros
  eelim H2; eauto
  apply Mem.perm_cur_max. apply Mem.perm_implies with Writable; auto with mem
  eapply Mem.storebytes_range_perm; eauto
  erewrite list_forall2_length; eauto
  omega
  split. apply inject_incr_refl
  red; intros; congruence
- /- trace length -/
  intros; inv H. simpl; omega
- /- receptive -/
  intros
  assert (t1 = t2). inv H; inv H0; auto. subst t2
  ∃ vres1; ∃ m1; auto
- /- determ -/
  intros; inv H; inv H0. split. constructor. intros; split; congruence
Qed

/- ** Semantics of annotations. -/

inductive extcall_annot_sem (text : string) (targs : list typ) (ge : Senv.t) :
              list val → mem → trace → val → mem → Prop :=
| extcall_annot_sem_intro : ∀ vargs m args,
      eventval_list_match ge args targs vargs →
      extcall_annot_sem text targs ge vargs m (Event_annot text args :: E0) Vundef m

lemma extcall_annot_ok :
  ∀ text targs,
  extcall_properties (extcall_annot_sem text targs)
                     (mksignature targs none cc_default)
Proof
  intros; constructor; intros
/- well typed -/
- inv H. simpl. auto
/- symbols -/
- destruct H as (A & B & C). inv H0. econstructor; eauto
  eapply eventval_list_match_preserved; eauto
/- valid blocks -/
- inv H; auto
/- perms -/
- inv H; auto
/- readonly -/
- inv H. apply Mem.unchanged_on_refl
/- mem extends -/
- inv H
  ∃ Vundef; ∃ m1'; intuition
  econstructor; eauto
  eapply eventval_list_match_lessdef; eauto
/- mem injects -/
- inv H0
  ∃ f; ∃ Vundef; ∃ m1'; intuition
  econstructor; eauto
  eapply eventval_list_match_inject; eauto
  red; intros; congruence
/- trace length -/
- inv H; simpl; omega
/- receptive -/
- assert (t1 = t2). inv H; inv H0; auto
  ∃ vres1; ∃ m1; congruence
/- determ -/
- inv H; inv H0
  assert (args = args0). eapply eventval_list_match_determ_2; eauto. subst args0
  split. constructor. auto
Qed

inductive extcall_annot_val_sem (text : string) (targ : typ) (ge : Senv.t) :
              list val → mem → trace → val → mem → Prop :=
| extcall_annot_val_sem_intro : ∀ varg m arg,
      eventval_match ge arg targ varg →
      extcall_annot_val_sem text targ ge (varg :: nil) m (Event_annot text (arg :: nil) :: E0) varg m

lemma extcall_annot_val_ok :
  ∀ text targ,
  extcall_properties (extcall_annot_val_sem text targ)
                     (mksignature (targ :: nil) (some targ) cc_default)
Proof
  intros; constructor; intros
/- well typed -/
- inv H. unfold proj_sig_res; simpl. eapply eventval_match_type; eauto
/- symbols -/
- destruct H as (A & B & C). inv H0. econstructor; eauto
  eapply eventval_match_preserved; eauto
/- valid blocks -/
- inv H; auto
/- perms -/
- inv H; auto
/- readonly -/
- inv H. apply Mem.unchanged_on_refl
/- mem extends -/
- inv H. inv H1. inv H6
  ∃ v2; ∃ m1'; intuition
  econstructor; eauto
  eapply eventval_match_lessdef; eauto
/- mem inject -/
- inv H0. inv H2. inv H7
  ∃ f; ∃ v'; ∃ m1'; intuition
  econstructor; eauto
  eapply eventval_match_inject; eauto
  red; intros; congruence
/- trace length -/
- inv H; simpl; omega
/- receptive -/
- assert (t1 = t2). inv H; inv H0; auto. subst t2
  ∃ vres1; ∃ m1; auto
/- determ -/
- inv H; inv H0
  assert (arg = arg0). eapply eventval_match_determ_2; eauto. subst arg0
  split. constructor. auto
Qed

inductive extcall_debug_sem (ge : Senv.t) :
              list val → mem → trace → val → mem → Prop :=
| extcall_debug_sem_intro : ∀ vargs m,
      extcall_debug_sem ge vargs m E0 Vundef m

lemma extcall_debug_ok :
  ∀ targs,
  extcall_properties extcall_debug_sem
                     (mksignature targs none cc_default)
Proof
  intros; constructor; intros
/- well typed -/
- inv H. simpl. auto
/- symbols -/
- inv H0. econstructor; eauto
/- valid blocks -/
- inv H; auto
/- perms -/
- inv H; auto
/- readonly -/
- inv H. apply Mem.unchanged_on_refl
/- mem extends -/
- inv H
  ∃ Vundef; ∃ m1'; intuition
  econstructor; eauto
/- mem injects -/
- inv H0
  ∃ f; ∃ Vundef; ∃ m1'; intuition
  econstructor; eauto
  red; intros; congruence
/- trace length -/
- inv H; simpl; omega
/- receptive -/
- inv H; inv H0. ∃ Vundef, m1; constructor
/- determ -/
- inv H; inv H0
  split. constructor. auto
Qed

/- ** Semantics of external functions. -/

/- For functions defined outside the program ([EF_external],
  [EF_builtin] and [EF_runtime]), we do not define their
  semantics, but only assume that it satisfies
  [extcall_properties]. -/

Parameter external_functions_sem : String.string → signature → extcall_sem

Axiom external_functions_properties :
  ∀ id sg, extcall_properties (external_functions_sem id sg) sg

/- We treat inline assembly similarly. -/

Parameter inline_assembly_sem : String.string → signature → extcall_sem

Axiom inline_assembly_properties :
  ∀ id sg, extcall_properties (inline_assembly_sem id sg) sg

/- ** Combined semantics of external calls -/

/- Combining the semantics given above for the various kinds of external calls,
  we define the predicate [external_call] that relates:
- the external function being invoked
- the values of the arguments passed to this function
- the memory state before the call
- the result value of the call
- the memory state after the call
- the trace generated by the call (can be empty).

This predicate is used in the semantics of all CompCert languages. -/

def external_call (ef : external_function) : extcall_sem :=
  match ef with
| EF_external name sg  := external_functions_sem name sg
| EF_builtin name sg   := external_functions_sem name sg
| EF_runtime name sg   := external_functions_sem name sg
| EF_vload chunk       := volatile_load_sem chunk
| EF_vstore chunk      := volatile_store_sem chunk
| EF_malloc            := extcall_malloc_sem
| EF_free              := extcall_free_sem
| EF_memcpy sz al      := extcall_memcpy_sem sz al
| EF_annot txt targs   := extcall_annot_sem txt targs
| EF_annot_val txt targ := extcall_annot_val_sem txt targ
| EF_inline_asm txt sg clb := inline_assembly_sem txt sg
| EF_debug kind txt targs := extcall_debug_sem
  end

theorem external_call_spec :
  ∀ ef,
  extcall_properties (external_call ef) (ef_sig ef)
Proof
  intros. unfold external_call, ef_sig; destruct ef
  apply external_functions_properties
  apply external_functions_properties
  apply external_functions_properties
  apply volatile_load_ok
  apply volatile_store_ok
  apply extcall_malloc_ok
  apply extcall_free_ok
  apply extcall_memcpy_ok
  apply extcall_annot_ok
  apply extcall_annot_val_ok
  apply inline_assembly_properties
  apply extcall_debug_ok
Qed

def external_call_well_typed ef := ec_well_typed (external_call_spec ef)
def external_call_symbols_preserved ef := ec_symbols_preserved (external_call_spec ef)
def external_call_valid_block ef := ec_valid_block (external_call_spec ef)
def external_call_max_perm ef := ec_max_perm (external_call_spec ef)
def external_call_readonly ef := ec_readonly (external_call_spec ef)
def external_call_mem_extends ef := ec_mem_extends (external_call_spec ef)
def external_call_mem_inject_gen ef := ec_mem_inject (external_call_spec ef)
def external_call_trace_length ef := ec_trace_length (external_call_spec ef)
def external_call_receptive ef := ec_receptive (external_call_spec ef)
def external_call_determ ef := ec_determ (external_call_spec ef)

/- Corollary of [external_call_valid_block]. -/

lemma external_call_nextblock :
  ∀ ef ge vargs m1 t vres m2,
  external_call ef ge vargs m1 t vres m2 →
  Ple (Mem.nextblock m1) (Mem.nextblock m2)
Proof
  intros. destruct (plt (Mem.nextblock m2) (Mem.nextblock m1))
  exploit external_call_valid_block; eauto. intros
  eelim Plt_strict; eauto
  unfold Plt, Ple in *; zify; omega
Qed

/- Special case of [external_call_mem_inject_gen] (for backward compatibility) -/

def meminj_preserves_globals (F V : Type) (ge : Genv.t F V) (f : block → option (block * ℤ)) : Prop :=
     (∀ id b, Genv.find_symbol ge id = some b → f b = some(b, 0))
  ∧ (∀ b gv, Genv.find_var_info ge b = some gv → f b = some(b, 0))
  ∧ (∀ b1 b2 delta gv, Genv.find_var_info ge b2 = some gv → f b1 = some(b2, delta) → b2 = b1)

lemma external_call_mem_inject :
  ∀ ef F V (ge : Genv.t F V) vargs m1 t vres m2 f m1' vargs',
  meminj_preserves_globals ge f →
  external_call ef ge vargs m1 t vres m2 →
  Mem.inject f m1 m1' →
  Val.inject_list f vargs vargs' →
  ∃ f', ∃ vres', ∃ m2',
     external_call ef ge vargs' m1' t vres' m2'
    ∧ Val.inject f' vres vres'
    ∧ Mem.inject f' m2 m2'
    ∧ Mem.unchanged_on (loc_unmapped f) m1 m2
    ∧ Mem.unchanged_on (loc_out_of_reach f m1) m1' m2'
    ∧ inject_incr f f'
    ∧ inject_separated f f' m1 m1'
Proof
  intros. destruct H as (A & B & C). eapply external_call_mem_inject_gen with (ge1 := ge); eauto
  repeat split; intros
  + simpl in H3. exploit A; eauto. intros EQ; rewrite EQ in H; inv H. auto
  + simpl in H3. exploit A; eauto. intros EQ; rewrite EQ in H; inv H. auto
  + simpl in H3. ∃ b1; split; eauto
  + simpl; unfold Genv.block_is_volatile
    destruct (Genv.find_var_info ge b1) as [gv1|] eqn:V1
    * exploit B; eauto. intros EQ; rewrite EQ in H; inv H. rewrite V1; auto
    * destruct (Genv.find_var_info ge b2) as [gv2|] eqn:V2; auto
      exploit C; eauto. intros EQ; subst b2. congruence
Qed

/- Corollaries of [external_call_determ]. -/

lemma external_call_match_traces :
  ∀ ef ge vargs m t1 vres1 m1 t2 vres2 m2,
  external_call ef ge vargs m t1 vres1 m1 →
  external_call ef ge vargs m t2 vres2 m2 →
  match_traces ge t1 t2
Proof
  intros. exploit external_call_determ. eexact H. eexact H0. tauto
Qed

lemma external_call_deterministic :
  ∀ ef ge vargs m t vres1 m1 vres2 m2,
  external_call ef ge vargs m t vres1 m1 →
  external_call ef ge vargs m t vres2 m2 →
  vres1 = vres2 ∧ m1 = m2
Proof
  intros. exploit external_call_determ. eexact H. eexact H0. intuition
Qed

/- * Evaluation of builtin arguments -/

section EVAL_BUILTIN_ARG

parameter A : Type
parameter ge : Senv.t
parameter e : A → val
parameter sp : val
parameter m : mem

inductive eval_builtin_arg : builtin_arg A → val → Prop :=
| eval_BA : ∀ x,
      eval_builtin_arg (BA x) (e x)
| eval_BA_int : ∀ n,
      eval_builtin_arg (BA_int n) (Vint n)
| eval_BA_long : ∀ n,
      eval_builtin_arg (BA_long n) (Vlong n)
| eval_BA_float : ∀ n,
      eval_builtin_arg (BA_float n) (Vfloat n)
| eval_BA_single : ∀ n,
      eval_builtin_arg (BA_single n) (Vsingle n)
| eval_BA_loadstack : ∀ chunk ofs v,
      Mem.loadv chunk m (Val.offset_ptr sp ofs) = some v →
      eval_builtin_arg (BA_loadstack chunk ofs) v
| eval_BA_addrstack : ∀ ofs,
      eval_builtin_arg (BA_addrstack ofs) (Val.offset_ptr sp ofs)
| eval_BA_loadglobal : ∀ chunk id ofs v,
      Mem.loadv chunk m (Senv.symbol_address ge id ofs) = some v →
      eval_builtin_arg (BA_loadglobal chunk id ofs) v
| eval_BA_addrglobal : ∀ id ofs,
      eval_builtin_arg (BA_addrglobal id ofs) (Senv.symbol_address ge id ofs)
| eval_BA_splitlong : ∀ hi lo vhi vlo,
      eval_builtin_arg hi vhi → eval_builtin_arg lo vlo →
      eval_builtin_arg (BA_splitlong hi lo) (Val.longofwords vhi vlo)

def eval_builtin_args (al : list (builtin_arg A)) (vl : list val) : Prop :=
  list_forall2 eval_builtin_arg al vl

lemma eval_builtin_arg_determ :
  ∀ a v, eval_builtin_arg a v → ∀ v', eval_builtin_arg a v' → v' = v
Proof
  induction 1; intros v' EV; inv EV; try congruence
  f_equal; eauto
Qed

lemma eval_builtin_args_determ :
  ∀ al vl, eval_builtin_args al vl → ∀ vl', eval_builtin_args al vl' → vl' = vl
Proof
  induction 1; intros v' EV; inv EV; f_equal; eauto using eval_builtin_arg_determ
Qed

end EVAL_BUILTIN_ARG

Hint Constructors eval_builtin_arg : barg

/- Invariance by change of global environment. -/

section EVAL_BUILTIN_ARG_PRESERVED

Variables A F1 V1 F2 V2 : Type
parameter ge1 : Genv.t F1 V1
parameter ge2 : Genv.t F2 V2
parameter e : A → val
parameter sp : val
parameter m : mem

Hypothesis symbols_preserved :
  ∀ id, Genv.find_symbol ge2 id = Genv.find_symbol ge1 id

lemma eval_builtin_arg_preserved :
  ∀ a v, eval_builtin_arg ge1 e sp m a v → eval_builtin_arg ge2 e sp m a v
Proof
  assert (EQ : ∀ id ofs, Senv.symbol_address ge2 id ofs = Senv.symbol_address ge1 id ofs)
  { unfold Senv.symbol_address; simpl; intros. rewrite symbols_preserved; auto. }
  induction 1; eauto with barg. rewrite <- EQ in H; eauto with barg. rewrite <- EQ; eauto with barg
Qed

lemma eval_builtin_args_preserved :
  ∀ al vl, eval_builtin_args ge1 e sp m al vl → eval_builtin_args ge2 e sp m al vl
Proof
  induction 1; constructor; auto; eapply eval_builtin_arg_preserved; eauto
Qed

end EVAL_BUILTIN_ARG_PRESERVED

/- Compatibility with the "is less defined than" relation. -/

section EVAL_BUILTIN_ARG_LESSDEF

parameter A : Type
parameter ge : Senv.t
Variables e1 e2 : A → val
parameter sp : val
Variables m1 m2 : mem

Hypothesis env_lessdef : ∀ x, Val.lessdef (e1 x) (e2 x)
Hypothesis mem_extends : Mem.extends m1 m2

lemma eval_builtin_arg_lessdef :
  ∀ a v1, eval_builtin_arg ge e1 sp m1 a v1 →
  ∃ v2, eval_builtin_arg ge e2 sp m2 a v2 ∧ Val.lessdef v1 v2
Proof
  induction 1
- ∃ (e2 x); auto with barg
- econstructor; eauto with barg
- econstructor; eauto with barg
- econstructor; eauto with barg
- econstructor; eauto with barg
- exploit Mem.loadv_extends; eauto. intros (v' & P & Q). ∃ v'; eauto with barg
- econstructor; eauto with barg
- exploit Mem.loadv_extends; eauto. intros (v' & P & Q). ∃ v'; eauto with barg
- econstructor; eauto with barg
- destruct IHeval_builtin_arg1 as (vhi' & P & Q)
  destruct IHeval_builtin_arg2 as (vlo' & R & S)
  econstructor; split; eauto with barg. apply Val.longofwords_lessdef; auto
Qed

lemma eval_builtin_args_lessdef :
  ∀ al vl1, eval_builtin_args ge e1 sp m1 al vl1 →
  ∃ vl2, eval_builtin_args ge e2 sp m2 al vl2 ∧ Val.lessdef_list vl1 vl2
Proof
  induction 1
- econstructor; split. constructor. auto
- exploit eval_builtin_arg_lessdef; eauto. intros (v1' & P & Q)
  destruct IHlist_forall2 as (vl' & U & V)
  ∃ (v1'::vl'); split; constructor; auto
Qed

end EVAL_BUILTIN_ARG_LESSDEF
