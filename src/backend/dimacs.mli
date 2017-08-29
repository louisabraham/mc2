(*
MSAT is free software, using the Apache license, see file LICENSE
Copyright 2014 Guillaume Bury
Copyright 2014 Simon Cruanes
*)

(** Dimacs backend for problems

    This module provides functiosn to export problems to the dimacs and
    iCNF formats.
*)

open Minismt_core

type clause = Clause.t
type 'c clause_sets = 'c Solver.clause_sets

val export :
  Format.formatter ->
  clause clause_sets ->
  unit
(** Export the given clause vectors to the dimacs format.
    The arguments should be transmitted directly from the corresponding
    function of the {Internal} module. *)

val export_icnf :
  Format.formatter ->
  clause clause_sets ->
  unit
  (** Export the given clause vectors to the dimacs format.
      The arguments should be transmitted directly from the corresponding
      function of the {Internal} module.
      This function may be called multiple times in order to add
      new clauses (and new local hyps) to the problem.
  *)
