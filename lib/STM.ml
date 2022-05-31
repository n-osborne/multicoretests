open QCheck
include Util

(** A revised state machine framework with parallel testing.
    This version does not come with built-in GC commands. *)

(** The specification of a state machine. *)
module type StmSpec =
sig
  type cmd
  (** The type of commands *)

  type state
  (** The type of the model's state *)

  type sut
  (** The type of the system under test *)

  val arb_cmd : state -> cmd arbitrary
  (** A command generator. Accepts a state parameter to enable state-dependent [cmd] generation. *)

  val init_state : state
  (** The model's initial state. *)

  val next_state : cmd -> state -> state
  (** Move the internal state machine to the next state. *)


  val init_sut : unit -> sut
  (** Initialize the system under test. *)

  val cleanup : sut -> unit
  (** Utility function to clean up the [sut] after each test instance,
      e.g., for closing sockets, files, or resetting global parameters*)

  (*val run_cmd : cmd -> state -> sut -> bool*)
  (** [run_cmd c s i] should interpret the command [c] over the system under test (typically side-effecting).
      [s] is in this case the model's state prior to command execution.
      The returned Boolean value should indicate whether the interpretation went well
      and in case [c] returns a value: whether the returned value agrees with the model's result. *)

  val precond : cmd -> state -> bool
  (** [precond c s] expresses preconditions for command [c].
      This is useful, e.g., to prevent the shrinker from breaking invariants when minimizing
      counterexamples. *)

  (* ************************ additions from here ************************ *)
  val show_cmd : cmd -> string
  (** [show_cmd c] returns a string representing the command [c]. *)

  type res
  (** The command result type *)

  val show_res : res -> string
  (** [show_res r] returns a string representing the result [r]. *)

  val run : cmd -> sut -> res
  (** [run c i] should interpret the command [c] over the system under test (typically side-effecting). *)

  val postcond : cmd -> state -> res -> bool
  (** [postcond c s res] checks whether [res] arising from interpreting the
      command [c] over the system under test with [run] agrees with the
      model's result.
      Note: [s] is in this case the model's state prior to command execution. *)

  val generators : cmd arbitrary
end

(** Derives a test framework from a state machine specification. *)
module Make(Spec : StmSpec) (*: StmTest *)
  : sig
    val cmds_ok : Spec.state -> Spec.cmd list -> bool
    val gen_cmds : Spec.state -> int -> Spec.cmd list Gen.t
    val arb_cmds : Spec.state -> Spec.cmd list arbitrary
    val consistency_test : count:int -> name:string -> Test.t
    val interp_agree : Spec.state -> Spec.sut -> Spec.cmd list -> bool
    val agree_prop : Spec.cmd list -> bool
    val agree_test : count:int -> name:string -> Test.t

    (* ****************************** additions from here ****************************** *)

  (*val check_and_next : (Spec.cmd * Spec.res) -> Spec.state -> bool * Spec.state*)
    val interp_sut_res : Spec.sut -> Spec.cmd list -> (Spec.cmd * Spec.res) list
    val check_obs : (Spec.cmd * Spec.res) list -> (Spec.cmd * Spec.res) list -> (Spec.cmd * Spec.res) list -> Spec.state -> bool
    val gen_cmds_size : Spec.state -> int Gen.t -> Spec.cmd list Gen.t
  (*val shrink_triple : ...*)
    val arb_cmds_par : int -> int -> (Spec.cmd list * Spec.cmd list * Spec.cmd list) arbitrary
    val agree_prop_par         : (Spec.cmd list * Spec.cmd list * Spec.cmd list) -> bool
    val agree_test_par         : count:int -> name:string -> Test.t
    val agree_test_par_smart   : count:int -> name:string -> Test.t
end
=
struct
  (** {3 The resulting test framework derived from a state machine specification} *)

  let rec gen_cmds s fuel =
    Gen.(if fuel = 0
         then return []
         else
  	  (Spec.arb_cmd s).gen >>= fun c ->
	   (gen_cmds (Spec.next_state c s) (fuel-1)) >>= fun cs ->
             return (c::cs))
  (** A fueled command list generator.
      Accepts a state parameter to enable state-dependent [cmd] generation. *)

  let rec cmds_ok s cs = match cs with
    | [] -> true
    | c::cs ->
      Spec.precond c s &&
	let s' = Spec.next_state c s in
	cmds_ok s' cs
  (** A precondition checker (stops early, thanks to short-circuit Boolean evaluation).
      Accepts the initial state and the command sequence as parameters.  *)

  let arb_cmds s =
    let cmds_gen = Gen.sized (gen_cmds s) in
    let shrinker = match (Spec.arb_cmd s).shrink with
                    | None   -> Shrink.list ~shrink:Shrink.nil (* no elem. shrinker provided *)
                    | Some s -> Shrink.list ~shrink:s in
    let ac = QCheck.make ~shrink:(Shrink.filter (cmds_ok Spec.init_state) shrinker) cmds_gen in
    (match (Spec.arb_cmd s).print with
     | None   -> ac
     | Some p -> set_print (Print.list p) ac)
  (** A generator of command sequences. Accepts the initial state as parameter. *)

  let consistency_test ~count ~name =
    Test.make ~name:name ~count:count (arb_cmds Spec.init_state) (cmds_ok Spec.init_state)
  (** A consistency test that generates a number of [cmd] sequences and
      checks that all contained [cmd]s satisfy the precondition [precond].
      Accepts two labeled parameters:
      [count] is the test count and [name] is the printed test name. *)

  let rec interp_agree s sut cs = match cs with
    | [] -> true
    | c::cs ->
      let res = Spec.run c sut in
      let b   = Spec.postcond c s res in
      let s'  = Spec.next_state c s in
      b && interp_agree s' sut cs
  (** Checks agreement between the model and the system under test
      (stops early, thanks to short-circuit Boolean evaluation). *)

  let agree_prop =
    (fun cs ->
       assume (cmds_ok Spec.init_state cs);
       let sut = Spec.init_sut () in (* reset system's state *)
       let res = interp_agree Spec.init_state sut cs in
       let ()  = Spec.cleanup sut in
       res)
  (** The agreement property: the command sequence [cs] yields the same observations
      when interpreted from the model's initial state and the [sut]'s initial state.
      Cleans up after itself by calling [Spec.cleanup] *)

  let agree_test ~count ~name =
    Test.make ~name:("sequential " ^ name) ~count (arb_cmds Spec.init_state) agree_prop
  (** An actual agreement test (for convenience). Accepts two labeled parameters:
      [count] is the test count and [name] is the printed test name. *)


  (* ****************************** additions from here ****************************** *)

  let check_and_next (c,res) s =
    let b  = Spec.postcond c s res in
    let s' = Spec.next_state c s in
    b,s'

  (* operate over arrays to avoid needless allocation underway *)
  let interp_sut_res sut cs =
    let cs_arr = Array.of_list cs in
    let res_arr = Array.map (fun c -> Domain.cpu_relax(); Spec.run c sut) cs_arr in
    List.combine cs (Array.to_list res_arr)

  (* checks that all interleavings of a cmd triple satisfies all preconditions *)
  let rec all_interleavings_ok pref cs1 cs2 s =
    match pref with
    | c::pref' ->
        Spec.precond c s &&
        let s' = Spec.next_state c s in
        all_interleavings_ok pref' cs1 cs2 s'
    | [] ->
        match cs1,cs2 with
        | [],[] -> true
        | [],c2::cs2' ->
            Spec.precond c2 s &&
            let s' = Spec.next_state c2 s in
            all_interleavings_ok pref cs1 cs2' s'
        | c1::cs1',[] ->
            Spec.precond c1 s &&
            let s' = Spec.next_state c1 s in
            all_interleavings_ok pref cs1' cs2 s'
        | c1::cs1',c2::cs2' ->
            (Spec.precond c1 s &&
             let s' = Spec.next_state c1 s in
             all_interleavings_ok pref cs1' cs2 s')
            &&
            (Spec.precond c2 s &&
             let s' = Spec.next_state c2 s in
             all_interleavings_ok pref cs1 cs2' s')

  let rec check_obs pref cs1 cs2 s =
    match pref with
    | p::pref' ->
       let b,s' = check_and_next p s in
       b && check_obs pref' cs1 cs2 s'
    | [] ->
       match cs1,cs2 with
       | [],[] -> true
       | [],p2::cs2' ->
          let b,s' = check_and_next p2 s in
          b && check_obs pref cs1 cs2' s'
       | p1::cs1',[] ->
          let b,s' = check_and_next p1 s in
          b && check_obs pref cs1' cs2 s'
       | p1::cs1',p2::cs2' ->
          (let b1,s' = check_and_next p1 s in
           b1 && check_obs pref cs1' cs2 s')
          ||
          (let b2,s' = check_and_next p2 s in
           b2 && check_obs pref cs1 cs2' s')

  let gen_cmds_size s size_gen = Gen.sized_size size_gen (gen_cmds s)

  let shrink_triple =
    let open Iter in
    let shrink_cmd = Option.value Spec.(arb_cmd init_state).shrink ~default:Shrink.nil in
    Shrink.filter
      (fun (seq,p1,p2) -> all_interleavings_ok seq p1 p2 Spec.init_state)
      (fun (seq,p1,p2) ->
        (map (fun seq' -> (seq',p1,p2)) (Shrink.list ~shrink:shrink_cmd seq))
        <+>
        (match p1 with [] -> Iter.empty | c1::c1s -> Iter.return (seq@[c1],c1s,p2))
        <+>
        (match p2 with [] -> Iter.empty | c2::c2s -> Iter.return (seq@[c2],p1,c2s))
        <+>
        (map (fun p1' -> (seq,p1',p2)) (Shrink.list ~shrink:shrink_cmd p1))
        <+>
        (map (fun p2' -> (seq,p1,p2')) (Shrink.list ~shrink:shrink_cmd p2)))

  let arb_cmds_par seq_len par_len =
    let seq_pref_gen = gen_cmds_size Spec.init_state (Gen.int_bound seq_len) in
    let gen_triple =
      Gen.(seq_pref_gen >>= fun seq_pref ->
           int_range 2 (2*par_len) >>= fun dbl_plen ->
           let spawn_state = List.fold_left (fun st c -> Spec.next_state c st) Spec.init_state seq_pref in
           let par_len1 = dbl_plen/2 in
           let par_gen1 = gen_cmds_size spawn_state (return par_len1) in
           let par_gen2 = gen_cmds_size spawn_state (return (dbl_plen - par_len1)) in
           triple (return seq_pref) par_gen1 par_gen2) in
    make ~print:(print_triple_vertical Spec.show_cmd) ~shrink:shrink_triple gen_triple

  module SmartGen : sig
    val arb_cmds_par_smart : int -> int -> (Spec.cmd list * Spec.cmd list * Spec.cmd list) arbitrary end
    = struct
  let run_pg state cmds = List.fold_right Spec.next_state cmds state

  (** [specialize p g] returns a generator that generate only one value but a
      value such that [p v] is true

      [g] must be the more general possible *)
  let specialize (p : 'a -> bool) (g : 'a Gen.t) : 'a option Gen.t =
    let rec aux fuel =
      if fuel = 0 then Gen.return None
      else
        let open Gen in
        g >>= fun c -> if p c then return (Some c) else aux (fuel - 1)
    in
    aux 10 (* XXX todo: find a good value for the fuel here *)

  let next_cmd (p : Spec.cmd -> bool) : Spec.cmd option Gen.t =
    (* maybe if the [oneof] is in specialize the result would be better *)
    specialize p Spec.generators.gen

  (** [valid_seq state pg] checks whether the sequential [pg] is valid
      precondition-wise when starting from [state] *)
  let rec valid_seq state : Spec.cmd list -> bool = function
    | [] -> true
    | c :: cmds ->
        Spec.precond c state && valid_seq (Spec.next_state c state) cmds

  (** [valid_last_cmd state cmd process] checks whether [cmd] is a valid last
      command in a process running conccurently with [process]. That is:

      - whenever [cmd] is run, the current state respects its precondition
      - whenever [cmd] is run, it does not break the preconditions of the
        commands that still has to be run in [process] *)
  let rec valid_last_cmd state cmd : Spec.cmd list -> bool = function
    | [] -> Spec.precond cmd state
    | x :: xs ->
        valid_seq state (cmd :: x :: xs)
        && valid_last_cmd (Spec.next_state x state) cmd xs

  (** [valid_par state p0 p1 cmd] checks that preconditions are respected in all
      the interleavings if we add [cmd] at the end of [p0]

      - precondition: all the interleavings of [p0] and [p1] are correct
        precondition-wise *)
  let rec valid_par (state : Spec.state) (p0 : Spec.cmd list)
      (p1 : Spec.cmd list) (cmd : Spec.cmd) : bool =
    match (p0, p1) with
    | [], ys ->
        (* now we can run cmd whenever we want *) valid_last_cmd state cmd ys
    | xs, [] ->
        (* now we should run all p0 before running cmd *)
        run_pg state xs |> Spec.precond cmd
    | x :: xs, y :: ys ->
        (* check both conccurrent steps *)
        (* XXX maybe maintain a set of state * p0 * p1? *)
        valid_par (Spec.next_state x state) xs (y :: ys) cmd
        && valid_par (Spec.next_state y state) (x :: xs) ys cmd

  let gen_par len (spawn_state : Spec.state) :
      (Spec.cmd list * Spec.cmd list) Gen.t =
    let open Gen in
    let rec aux len g0 g1 =
      if len = 0 then pair g0 g1
      else
        g0 >>= fun p0 ->
        g1 >>= fun p1 ->
        let p = valid_par spawn_state p0 p1 in
        let open Gen in
        next_cmd p >>= function
        | None ->
            pair g0 g1 (* XXX here we could have some local backtracking *)
        | Some c ->
            let g0 = return (p0 @ [ c ]) in
            aux (len - 1) g1 g0
    in
    aux len (return []) (return [])

  let gen_seq (len : int) : Spec.cmd list Gen.t =
    let rec aux len state =
      let open Gen in
      if len = 0 then return []
      else
        next_cmd (fun c -> Spec.precond c state) >>= function
        | None -> return []
        | Some c ->
            aux (len - 1) (Spec.next_state c state) >>= fun cmds ->
            return (c :: cmds)
    in
    aux len Spec.init_state

  let gen_pg seq_len par_len =
    let open Gen in
    gen_seq seq_len >>= fun pref ->
    run_pg Spec.init_state pref |> gen_par par_len >>= fun (p0, p1) ->
    triple (return pref) (return p0) (return p1)

  let print_pg : (Spec.cmd list * Spec.cmd list * Spec.cmd list) Print.t option
      =
    let open Print in
    match Spec.generators.print with
    | None -> None
    | Some p ->
        Some
          (fun (seq, p0, p1) ->
            let p = list p in
            p seq ^ (pair p p) (p0, p1))

  let arb_cmds_par_smart seq_len par_len =
    match print_pg with
    | None -> QCheck.make (gen_pg seq_len par_len)
    | Some print -> QCheck.make ~print (gen_pg seq_len par_len)
  end
  open SmartGen
  
  (* Parallel agreement property based on [Domain] *)
  let agree_prop_par =
    (fun (seq_pref,cmds1,cmds2) ->
      assume (all_interleavings_ok seq_pref cmds1 cmds2 Spec.init_state);
      let sut = Spec.init_sut () in
      let pref_obs = interp_sut_res sut seq_pref in
      let wait = Atomic.make true in
      let dom1 = Domain.spawn (fun () -> while Atomic.get wait do Domain.cpu_relax() done; interp_sut_res sut cmds1) in
      let dom2 = Domain.spawn (fun () -> Atomic.set wait false; interp_sut_res sut cmds2) in
      let obs1 = Domain.join dom1 in
      let obs2 = Domain.join dom2 in
      let ()   = Spec.cleanup sut in
      check_obs pref_obs obs1 obs2 Spec.init_state
      || Test.fail_reportf "  Results incompatible with linearized model\n\n%s"
         @@ print_triple_vertical ~fig_indent:5 ~res_width:35
              (fun (c,r) -> Printf.sprintf "%s : %s" (Spec.show_cmd c) (Spec.show_res r))
              (pref_obs,obs1,obs2))

  (* Parallel agreement test based on [Domain] which combines [repeat] and [~retries] *)
  let agree_test_par_arb arb ~count ~name =
    let rep_count = 25 in
    let seq_len,par_len = 20,12 in
    let max_gen = 3*count in (* precond filtering may require extra generation: max. 3*count though *)
    Test.make ~retries:15 ~max_gen ~count ~name:("parallel " ^ name)
      (arb seq_len par_len)
      (repeat rep_count agree_prop_par) (* 25 times each, then 25 * 15 times when shrinking *)

  let agree_test_par = agree_test_par_arb arb_cmds_par
  let agree_test_par_smart = agree_test_par_arb arb_cmds_par_smart
  
end

(** ********************************************************************** *)

module AddGC(Spec : StmSpec) : StmSpec
=
struct
  type cmd =
    | GC_minor
    | UserCmd of Spec.cmd

  let user_cmd c = UserCmd c

  type state = Spec.state
  type sut   = Spec.sut

  let init_state  = Spec.init_state
  let init_sut () = Spec.init_sut ()
  let cleanup sut = Spec.cleanup sut

  let show_cmd c = match c with
    | GC_minor -> "<GC.minor>"
    | UserCmd c -> Spec.show_cmd c

  let gen_cmd s =
    (Gen.frequency
       [(1,Gen.return GC_minor);
        (5,Gen.map (fun c -> UserCmd c) (Spec.arb_cmd s).gen)])

  let shrink_cmd s c = match c with
    | GC_minor  -> Iter.empty
    | UserCmd c ->
       match (Spec.arb_cmd s).shrink with
       | None     -> Iter.empty (* no shrinker provided *)
       | Some shk -> Iter.map (fun c' -> UserCmd c') (shk c)

  let arb_cmd s = make ~print:show_cmd ~shrink:(shrink_cmd s) (gen_cmd s)

  let next_state c s = match c with
    | GC_minor  -> s
    | UserCmd c -> Spec.next_state c s

  let precond c s = match c with
    | GC_minor  -> true
    | UserCmd c -> Spec.precond c s

  type res =
    | GCRes
    | UserRes of Spec.res

  let show_res c = match c with
    | GCRes     -> "<RGC.minor>"
    | UserRes r -> Spec.show_res r

  let run c s = match c with
    | GC_minor  -> (Gc.minor (); GCRes)
    | UserCmd c -> UserRes (Spec.run c s)

  let postcond c s r = match c,r with
    | GC_minor,  GCRes     -> true
    | UserCmd c, UserRes r -> Spec.postcond c s r
    | _,_ -> false

  let generators =
    let shrink a = function
      | GC_minor -> Iter.empty
      | UserCmd c -> (match a.shrink with
                      | None -> Iter.empty
                      | Some shk -> Iter.map user_cmd (shk c))
    in
    let lift a = make ~print:show_cmd ~shrink:(shrink a) (Gen.map user_cmd a.gen) in
     lift Spec.generators
end
