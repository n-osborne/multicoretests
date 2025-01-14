open Lin

(** functor to build an internal module representing concurrent tests *)
module Make_internal (Spec : Internal.CmdSpec) : sig
  val arb_cmds_par : int -> int -> (Spec.cmd list * Spec.cmd list * Spec.cmd list) QCheck.arbitrary
  val lin_prop_thread : (Spec.cmd list * Spec.cmd list * Spec.cmd list) -> bool
  val lin_test : count:int -> name:string -> QCheck.Test.t
  val neg_lin_test : count:int -> name:string -> QCheck.Test.t
end

(** functor to build a module for concurrent testing *)
module Make (Spec : Spec) : sig
  val lin_test : count:int -> name:string -> QCheck.Test.t
  (** [lin_test ~count:c ~name:n] builds a concurrent test with the name [n]
      that iterates [c] times. The test fails if one of the generated programs
      is not sequentially consistent. In that case it fails, and prints a
      reduced counter example.
  *)

  val neg_lin_test : count:int -> name:string -> QCheck.Test.t
  (** [neg_lin_test ~count:c ~name:n] builds a negative concurrent test with
      the name [n] that iterates [c] times. The test fails if no counter example
      is found, and succeeds if a counter example is indeed found, and prints it
      afterwards.
  *)
end
