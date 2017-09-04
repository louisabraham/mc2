
(** Internal types (implementation)

    This modules actually implements the internal types used by the solver.
    Since mutation is heavily used in the solver, it is really, really, *really*
    discouraged to direclty use the functions in this module if you don't know the
    inner working of mSAT perfectly as even the simplest
    change can have dramatic effects on the solver.
*)

(** Internal types (interface)

    This modules defines the interface of most of the internal types
    used in the core solver.
*)

module Term_fields = BitField.Make(struct end)
module Clause_fields = BitField.Make(struct end)

(** {2 Type definitions} *)

type plugin_id = int

type term_view = ..
(** Extensible view on terms (generalized variables).
    Each plugin might declare its own terms. *)

type value_view = ..
(** Extensible view on values. *)

type decide_state = ..
(** State carried by a given term, depending on its type, and used
    for decisions and propagations related to the term.
    Typically it contains a set of constraints on the values this
    term can have (lower/upper bounds, etc.)
*)

type lemma_view = ..
(** Extensible proof object *)

type ty_view = ..
(** Extensible view on types *)

(** Types *)
type ty =
  | Bool (** Builtin type of booleans *)
  | Ty of {
      mutable id: int; (** unique ID of the type *)
      view: ty_view;
      tc: tc_ty; (** operations *)
    }
  (** An atomic type, with some attached data *)

and tc_ty = {
  tcty_decide: actions -> term -> value;
  (** How to make semantic decisions for terms of this type? *)
  tcty_pp: ty_view CCFormat.printer; (** print types *)
  tcty_mk_state: unit -> decide_state; (** decide state for a new term *)
}

and term = {
  t_tc: tc_term; (** typeclass for the term *)
  mutable t_id: int;
  (** unique ID, made of:
      - [k] bits plugin_id (with k small)
      - the rest is for plugin-specific id *)
  t_view: term_view; (** view *)
  t_ty: ty; (** type of the term *)
  mutable t_idx: int; (** position in heap *)
  mutable t_weight : float; (** Weight (for the heap), tracking activity *)
  mutable t_fields: Term_fields.t;
  (** bitfield for storing various info *)
  mutable t_level : int; (** Decision level of the assignment *)
  mutable t_var: var;
  (** The "generalized variable" part, for assignments. *)
}
(** Main term representation. A {!term}, contains almost all information
    necessary to process it, including:

    - its unique ID
    - its plugin-specific representation (possibly with subterms)
    - its current assignment, level, weight, etc.
    - some info related to its position in the queue of terms to decide

    It is worth noting that terms are also (generalized) {i variables}
    and behave mostly the same as boolean variables for the main
    solver, meaning that they need to be assigned a value in the model.
*)

and tc_term = {
  tct_pp : term_view CCFormat.printer; (** print views of this plugin *)
  tct_update_watches: actions -> term -> unit; (** one of the watches was updated *)
  tct_subterms: term_view -> (term->unit) -> unit; (** iterate on subterms *)
  tct_assign: actions -> term -> check_res; (** notify that the term is assigned *)
  tct_simplify : term -> term; (** Simplify the term into some canonical form, if possible *)
  tct_eval_bool : term -> eval_bool_res; (** Evaluate boolean term *)
}
(** type class for terms, packing all operations on terms *)

and eval_bool_res =
  | Eval_unknown (** The given formula does not have an evaluation *)
  | Eval_bool of bool * term list
  (** The given formula can be evaluated to the given bool.
      The list of terms to give is the list of terms that were effectively used
      for the evaluation.
  *)
(** The type of evaluation results for a given formula.
    For instance, let's suppose we want to evaluate the formula [x * y = 0], the
    following result are correct:
    - [Unknown] if neither [x] nor [y] are assigned to a value
    - [Valued (true, [x])] if [x] is assigned to [0]
    - [Valued (true, [y])] if [y] is assigned to [0]
    - [Valued (false, [x; y])] if [x] and [y] are assigned to 1 (or any non-zero number)
*)

and check_res =
  | Sat
  (** The current set of assumptions is satisfiable. *)
  | Unsat of atom list * lemma
  (** The current set of assumptions is *NOT* satisfiable, and here is a
      theory tautology (with its proof), for which every literal is false
      under the current assumptions. *)

(** The "generalized variable" part of a term, containing the
    current assignment, watched literals/terms, etc. *)
and var =
  (** Semantic variable *)
  | Var_semantic of {
      mutable v_value : semantic_assignment; (** Assignment *)
      mutable v_watched : term Vec.t; (** watched terms *)
      mutable v_decide_state: decide_state; (** used for decisions/assignments *)
    }

  (** Bool variable *)
  | Var_bool of {
      pa : atom; (** Link for the positive atom *)
      na : atom; (** Link for the negative atom *)
      mutable b_value : bool_assignment;
      (** Is the atom true ? Conversely, the atom is false iff a.neg.is_true *)
    }
  | Var_none (** Not a variable yet (not added) *)

and atom = {
  a_id : int; (** Unique identifier *)
  a_term : term; (** Link for the parent variable *)
  mutable a_watched : clause Vec.t; (** The vector of clauses that watch this atom *)
}
(** Atoms and variables wrap theory formulas. They exist in the form of
    triplet: a variable and two atoms. For a formula [f] in normal form,
    the variable v points to the positive atom [a] which wraps [f], while
    [a.neg] wraps the theory negation of [f]. *)

(** The value and reason for propagation/decision of the term *)
and semantic_assignment =
  | V_none
  | V_assign of {
      value: value;
      reason: reason;
    }

(** Boolean assignment *)
and bool_assignment =
  | B_none
  | B_true of reason
  | B_false of reason

and clause = {
  c_name : int; (** Clause name, mainly for printing, unique. *)
  c_tag : int option; (** User-provided tag for clauses. *)
  c_atoms : atom array; (** The atoms that constitute the clause.*)
  mutable c_premise : premise;
  (** The premise of the clause, i.e. the justification of why the clause must
      be satisfied. *)
  mutable c_activity : float;   (** Clause activity, used for the heap heuristics. *)
  mutable c_fields: Clause_fields.t; (** bitfield for clauses *)
}
(** The type of clauses. Each clause generated should be true, i.e. enforced
    by the current problem (for more information, see the cpremise field). *)

and value = {
  val_view: value_view; (** Actual shape of the value *)
  val_tc: tc_value; (** typeclass for values *)
}
(** A semantic value, part of the model's domain. For arithmetic, it would
    be a number; for arrays, a finite map + default value; etc.
    Note that terms map to values in the model but that values are
    not necessarily normal "terms" (i.e. generalized variables in
    the MCSat sense).
*)

and tc_value = {
  tcv_pp : value_view CCFormat.printer; (** printer *)
  tcv_equal : value_view -> value_view -> bool; (** equality *)
  tcv_hash : value_view -> int; (** hash function *)
}
(** Methods for values *)

and reason =
  | Decision
  (** The atom has been decided by the sat solver *)
  | Bcp of clause
  (** The atom has been propagated by the given clause *)
  | Semantic of term list
  (** The atom can be evaluated using the terms in the list *)

(* TODO?
  | Consequence of term * lemma lazy_t
  (** [Consequence (l, p)] means that the formulas in [l] imply the propagated
      formula [f]. The proof should be a proof of the clause "[l] implies [f]".
  *)
   *)
(** Reasons of propagation/decision of atoms/terms. *)

and premise =
  | Hyp (** The clause is a hypothesis, provided by the user. *)
  | Local
  (** The clause is a 1-atom clause, where the atom is a local assumption *)
  | Lemma of lemma
  (** The clause is a theory-provided tautology, with the given proof. *)
  | History of clause list
  (** The clause can be obtained by resolution of the clauses
      in the list. If the list has a single element [c] , then the clause can
      be obtained by simplifying [c] (i.e eliminating doublons in its atom
      list).  For a premise [History [a_1 :: ... :: a_n]] ([n > 0]) the clause
      is obtained by performing resolution of [a_1] with [a_2], and then
      performing a resolution step between the result and [a_3], etc...  Of
      course, each of the clause [a_i] also has its own premise.
  *)
(** Premises for clauses. Indeed each clause generated during a run of the solver
    should be satisfied, the premise is the justification of why it should be
    satisfied by the solver. *)

and lemma = {
  lemma_view: lemma_view; (** The lemma content *)
  lemma_tc: tc_lemma; (** Methods on the lemma *)
}
(** A lemma belonging to some plugin. Must be a tautology of the theory. *)

and tc_lemma = {
  tcl_pp : lemma_view CCFormat.printer;
}

and actions = {
  act_push_clause : clause -> unit;
  (** push a new clause *)
  act_propagate_bool : term -> bool -> term list -> unit;
  (** [act_propagate_bool t b l] propagates the boolean literal [t]
      assigned to boolean value [b], explained by evaluation of
      (sub)terms [l] *)
  act_on_backtrack : int -> (unit -> unit) -> unit;
  (** [act_on_backtrack level f] will call [f] when the given [level]
      is backtracked *)
}
(** Actions available to terms/plugins when doing propagation/model building,
    including adding clauses, registering actions to do upon
    backtracking, etc. *)

let field_t_is_deleted = Term_fields.mk_field () (* term deleted during GC? *)
let field_t_is_added = Term_fields.mk_field() (* term added to core solver? *)
let field_t_mark_pos = Term_fields.mk_field() (* positive atom marked? *)
let field_t_mark_neg = Term_fields.mk_field() (* negative atom marked? *)
let field_t_seen = Term_fields.mk_field() (* term seen during some traversal? *)
let field_t_negated = Term_fields.mk_field() (* negated term? *)
let field_t_gc_marked = Term_fields.mk_field() (* marked for GC? *)

let field_c_attached = Clause_fields.mk_field() (* clause added to state? *)
let field_c_visited = Clause_fields.mk_field() (* visited during some traversal? *)

type term_view += Dummy

let dummy_tct : tc_term = {
  tct_pp=(fun _ _ -> assert false);
  tct_update_watches=(fun _ _ -> assert false);
  tct_subterms=(fun _ _ -> assert false); (** iterate on subterms *)
  tct_assign=(fun _ _ -> assert false); (** notify that the term is assigned *)
  tct_simplify=(fun t -> t);
  tct_eval_bool=(fun _ -> Eval_unknown);
}

let dummy_term : term = {
  t_id= ~-1;
  t_tc=dummy_tct;
  t_idx= ~-1;
  t_view=Dummy;
  t_ty=Bool;
  t_fields= Term_fields.empty;
  t_weight= -1.;
  t_level= -1;
  t_var=Var_none;
}

let dummy_clause : clause = {
  c_name = -1;
  c_tag = None;
  c_atoms = [| |];
  c_activity = -1.;
  c_fields = Clause_fields.empty;
  c_premise = History [];
}

let dummy_atom : atom = {
  a_id= -1;
  a_term=dummy_term;
  a_watched=Vec.make_empty dummy_clause;
}

type bool_term = term (** Alias for boolean terms *)

(** {2 Decisions and propagations} *)

type trail = term Vec.t
(** A trail is a vector of assignments. An assignment is simply
    a term whose value is decided. *)

type assignment_view =
  | A_bool of term * bool
  | A_semantic of term * value

type 'a or_conflict = ('a, clause) CCResult.t
(** Either an ['a], or a conflict clause *)