(*
MSAT is free software, using the Apache license, see file LICENSE
Copyright 2015 Guillaume Bury
*)

(** Coq Backend

    This module provides an easy way to produce coq scripts
    corresponding to the resolution proofs output by the
    sat solver. *)

open Minismt_core

module type S = Backend_intf.S
(** Interface for exporting proofs. *)

module type Arg = sig
  (** Term printing for Coq *)

  type hyp
  type lemma
  type assumption
  (** The types of hypotheses, lemmas, and assumptions *)

  val prove_hyp : Format.formatter -> string -> hyp -> unit
  val prove_lemma : Format.formatter -> string -> lemma -> unit
  val prove_assumption : Format.formatter -> string -> assumption -> unit
  (** Proving function for hypotheses, lemmas and assumptions.
      [prove_x fmt name x] should prove [x], and be such that after
      executing it, [x] is among the coq hypotheses under the name [name].
      The hypothesis should be the encoding of the given clause, i.e
      for a clause [a \/ not b \/ c], the proved hypothesis should be:
      [ ~ a -> ~ ~ b -> ~ c -> False ], keeping the same order as the
      one in the atoms array of the clause. *)

end

module Make(A : Arg with type hyp := Clause.t
                     and type lemma := Clause.t
                     and type assumption := Clause.t) : S with type t := Res.proof
(** Base functor to output Coq proofs *)


module Simple(A : Arg with type hyp = Term.t list
                       and type lemma := Clause.t
                       and type assumption := Term.t) : S with type t := Res.proof
(** Simple functo to output Coq proofs *)

