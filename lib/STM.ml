open QCheck
include Util

type 'a ty = ..

type _ ty +=
  | Unit : unit ty
  | Bool : bool ty
  | Char : char ty
  | Int : int ty
  | Int32 : int32 ty
  | Int64 : int64 ty
  | Float : float ty
  | String : string ty
  | Bytes : bytes ty
  | Exn : exn ty
  | Option : 'a ty -> 'a option ty
  | Result : 'a ty * 'b ty -> ('a, 'b) result ty
  | List : 'a ty -> 'a list ty
  | Array : 'a ty -> 'a array ty
  | Seq : 'a ty -> 'a Seq.t ty

type 'a ty_show = 'a ty * ('a -> string)

let unit = (Unit, fun () -> "()")
let bool = (Bool, string_of_bool)
let char = (Char, fun c -> Printf.sprintf "%C" c)
let int = (Int, string_of_int)
let int32 = (Int32, Int32.to_string)
let int64 = (Int64, Int64.to_string)
let float = (Float, Float.to_string)
let string = (String, fun s -> Printf.sprintf "%S" s)
let bytes = (Bytes, fun b -> Printf.sprintf "%S" (Bytes.to_string b))
let option spec =
  let (ty,show) = spec in
  (Option ty, QCheck.Print.option show)
let exn = (Exn, Printexc.to_string)

let show_result show_ok show_err = function
  | Ok x    -> Printf.sprintf "Ok (%s)" (show_ok x)
  | Error y -> Printf.sprintf "Error (%s)" (show_err y)

let result spec_ok spec_err =
  let (ty_ok, show_ok) = spec_ok in
  let (ty_err, show_err) = spec_err in
  (Result (ty_ok, ty_err), show_result show_ok show_err)

let list spec =
  let (ty,show) = spec in
  (List ty, QCheck.Print.list show)

let array spec =
  let (ty,show) = spec in
  (Array ty, QCheck.Print.array show)

let seq spec =
  let (ty,show) = spec in
  (Seq ty, fun s -> QCheck.Print.list show (List.of_seq s))

type res =
  Res : 'a ty_show * 'a -> res

let show_res (Res ((_,show), v)) = show v

(** The specification of a state machine. *)
module type StmSpec =
sig
  type cmd
  type state
  type sut

  val arb_cmd : state -> cmd arbitrary
  val show_cmd : cmd -> string

  val init_state : state
  val next_state : cmd -> state -> state

  val init_sut : unit -> sut
  val cleanup : sut -> unit

  val precond : cmd -> state -> bool
  val run : cmd -> sut -> res
  val postcond : cmd -> state -> res -> bool
end


(** Derives a test framework from a state machine specification. *)
module Make(Spec : StmSpec) =
struct
  (** {3 The resulting test framework derived from a state machine specification} *)

  let rec gen_cmds arb s fuel =
    Gen.(if fuel = 0
         then return []
         else
          (arb s).gen >>= fun c ->
           (gen_cmds arb (Spec.next_state c s) (fuel-1)) >>= fun cs ->
             return (c::cs))
  (** A fueled command list generator.
      Accepts a state parameter to enable state-dependent [cmd] generation. *)

  let rec cmds_ok s cs = match cs with
    | [] -> true
    | c::cs ->
      Spec.precond c s &&
        let s' = Spec.next_state c s in
        cmds_ok s' cs

  let arb_cmds s =
    let cmds_gen = Gen.sized (gen_cmds Spec.arb_cmd s) in
    let shrinker = match (Spec.arb_cmd s).shrink with
                    | None   -> Shrink.list ~shrink:Shrink.nil (* no elem. shrinker provided *)
                    | Some s -> Shrink.list ~shrink:s in
    let ac = QCheck.make ~shrink:(Shrink.filter (cmds_ok Spec.init_state) shrinker) cmds_gen in
    (match (Spec.arb_cmd s).print with
     | None   -> ac
     | Some p -> set_print (Print.list p) ac)

  let consistency_test ~count ~name =
    Test.make ~name ~count (arb_cmds Spec.init_state) (cmds_ok Spec.init_state)

  let rec interp_agree s sut cs = match cs with
    | [] -> true
    | c::cs ->
      let res = Spec.run c sut in
      let b   = Spec.postcond c s res in
      let s'  = Spec.next_state c s in
      b && interp_agree s' sut cs

  let rec check_disagree s sut cs = match cs with
    | [] -> None
    | c::cs ->
      let res = Spec.run c sut in
      let b   = Spec.postcond c s res in
      let s'  = Spec.next_state c s in
      if b
      then
        match check_disagree s' sut cs with
        | None -> None
        | Some rest -> Some ((c,res)::rest)
      else Some [c,res]

  let print_seq_trace trace =
    List.fold_left
      (fun acc (c,r) -> Printf.sprintf "%s\n   %s : %s" acc (Spec.show_cmd c) (show_res r))
      "" trace

  let agree_prop =
    (fun cs ->
       assume (cmds_ok Spec.init_state cs);
       let sut = Spec.init_sut () in (* reset system's state *)
       let res = check_disagree Spec.init_state sut cs in
       let ()  = Spec.cleanup sut in
       match res with
       | None -> true
       | Some trace ->
           Test.fail_reportf "  Results incompatible with model\n%s"
           @@ print_seq_trace trace)

  let agree_test ~count ~name =
    Test.make ~name ~count (arb_cmds Spec.init_state) agree_prop

  let neg_agree_test ~count ~name =
    Test.make_neg ~name ~count (arb_cmds Spec.init_state) agree_prop

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

  let gen_cmds_size gen s size_gen = Gen.sized_size size_gen (gen_cmds gen s)

  (* Shrinks a single cmd, starting in the given state *)
  let shrink_cmd arb cmd state =
    Option.value (arb state).shrink ~default:Shrink.nil @@ cmd

  (* Shrinks cmd lists, starting in the given state *)
  let rec shrink_cmd_list arb cs state = match cs with
    | [] -> Iter.empty
    | c::cs ->
        if Spec.precond c state
        then
          Iter.(
            map (fun c -> c::cs) (shrink_cmd arb c state)
            <+>
            map (fun cs -> c::cs) (shrink_cmd_list arb cs Spec.(next_state c state))
          )
        else Iter.empty

  (* Shrinks cmd elements in triples *)
  let shrink_triple_elems arb0 arb1 arb2 (seq,p1,p2) =
    let shrink_prefix cs state =
      Iter.map (fun cs -> (cs,p1,p2)) (shrink_cmd_list arb0 cs state)
    in
    let rec shrink_par_suffix cs state = match cs with
      | [] ->
          (* try only one option: p1s or p2s first - both valid interleavings *)
          Iter.(map (fun p1 -> (seq,p1,p2)) (shrink_cmd_list arb1 p1 state)
                <+>
                map (fun p2 -> (seq,p1,p2)) (shrink_cmd_list arb2 p2 state))
      | c::cs ->
          (* walk seq prefix (again) to advance state *)
          if Spec.precond c state
          then shrink_par_suffix cs Spec.(next_state c state)
          else Iter.empty
    in
    match Spec.(arb_cmd init_state).shrink with
    | None -> Iter.empty (* stop early if no cmd shrinker is available *)
    | Some _ ->
        Iter.(shrink_prefix seq Spec.init_state
              <+>
              shrink_par_suffix seq Spec.init_state)

  (* General shrinker of cmd triples *)
  let shrink_triple arb0 arb1 arb2 =
    let open Iter in
    Shrink.filter
      (fun (seq,p1,p2) -> all_interleavings_ok seq p1 p2 Spec.init_state)
      (fun ((seq,p1,p2) as triple) ->
        (* Shrinking heuristic:
￼          First reduce the cmd list sizes as much as possible, since the interleaving
￼          is most costly over long cmd lists. *)
        (map (fun seq' -> (seq',p1,p2)) (Shrink.list_spine seq))
        <+>
        (match p1 with [] -> Iter.empty | c1::c1s -> Iter.return (seq@[c1],c1s,p2))
        <+>
        (match p2 with [] -> Iter.empty | c2::c2s -> Iter.return (seq@[c2],p1,c2s))
        <+>
        (map (fun p1' -> (seq,p1',p2)) (Shrink.list_spine p1))
        <+>
        (map (fun p2' -> (seq,p1,p2')) (Shrink.list_spine p2))
        <+>
        (* Secondly reduce the cmd data of individual list elements *)
        (shrink_triple_elems arb0 arb1 arb2 triple))

  let arb_triple seq_len par_len arb0 arb1 arb2 =
    let seq_pref_gen = gen_cmds_size arb0 Spec.init_state (Gen.int_bound seq_len) in
    let shrink_triple = shrink_triple arb0 arb1 arb2 in
    let gen_triple =
      Gen.(seq_pref_gen >>= fun seq_pref ->
           int_range 2 (2*par_len) >>= fun dbl_plen ->
           let spawn_state = List.fold_left (fun st c -> Spec.next_state c st) Spec.init_state seq_pref in
           let par_len1 = dbl_plen/2 in
           let par_gen1 = gen_cmds_size arb1 spawn_state (return par_len1) in
           let par_gen2 = gen_cmds_size arb2 spawn_state (return (dbl_plen - par_len1)) in
           triple (return seq_pref) par_gen1 par_gen2) in
    make ~print:(print_triple_vertical Spec.show_cmd) ~shrink:shrink_triple gen_triple

  let arb_cmds_par seq_len par_len = arb_triple seq_len par_len Spec.arb_cmd Spec.arb_cmd Spec.arb_cmd

  exception ThreadNotFinished

  (* Parallel agreement property based on [Threads] *)
  let agree_prop_thread (seq_pref,cmds1,cmds2) =
    assume (all_interleavings_ok seq_pref cmds1 cmds2 Spec.init_state);
    let sut = Spec.init_sut () in
    let obs1,obs2 = ref (Error ThreadNotFinished), ref (Error ThreadNotFinished) in
    let pref_obs = interp_sut_res sut seq_pref in
    let wait = ref true in
    let th1 = Thread.create (fun () -> while !wait do Thread.yield () done; obs1 := try Ok (interp_sut_res sut cmds1) with exn -> Error exn) () in
    let th2 = Thread.create (fun () -> wait := false; obs2 := try Ok (interp_sut_res sut cmds2) with exn -> Error exn) () in
    let () = Thread.join th1 in
    let () = Thread.join th2 in
    let obs1 = match !obs1 with Ok v -> v | Error exn -> raise exn in
    let obs2 = match !obs2 with Ok v -> v | Error exn -> raise exn in
    let ()   = Spec.cleanup sut in
    check_obs pref_obs obs1 obs2 Spec.init_state
      || Test.fail_reportf "  Results incompatible with linearized model\n\n%s"
         @@ print_triple_vertical ~fig_indent:5 ~res_width:35
           (fun (c,r) -> Printf.sprintf "%s : %s" (Spec.show_cmd c) (show_res r))
           (pref_obs,obs1,obs2)

  (* Parallel agreement property based on [Domain] *)
  let agree_prop_par (seq_pref,cmds1,cmds2) =
    assume (all_interleavings_ok seq_pref cmds1 cmds2 Spec.init_state);
    let sut = Spec.init_sut () in
    let pref_obs = interp_sut_res sut seq_pref in
    let wait = Atomic.make true in
    let dom1 = Domain.spawn (fun () -> while Atomic.get wait do Domain.cpu_relax() done; try Ok (interp_sut_res sut cmds1) with exn -> Error exn) in
    let dom2 = Domain.spawn (fun () -> Atomic.set wait false; try Ok (interp_sut_res sut cmds2) with exn -> Error exn) in
    let obs1 = Domain.join dom1 in
    let obs2 = Domain.join dom2 in
    let obs1 = match obs1 with Ok v -> v | Error exn -> raise exn in
    let obs2 = match obs2 with Ok v -> v | Error exn -> raise exn in
    let ()   = Spec.cleanup sut in
    check_obs pref_obs obs1 obs2 Spec.init_state
      || Test.fail_reportf "  Results incompatible with linearized model\n\n%s"
         @@ print_triple_vertical ~fig_indent:5 ~res_width:35
           (fun (c,r) -> Printf.sprintf "%s : %s" (Spec.show_cmd c) (show_res r))
           (pref_obs,obs1,obs2)

  let mk_agree_test ~count ~name prop =
    let rep_count = 25 in
    let seq_len,par_len = 20,12 in
    let max_gen = 3*count in (* precond filtering may require extra generation: max. 3*count though *)
    Test.make ~retries:15 ~max_gen ~count ~name
      (arb_cmds_par seq_len par_len)
      (repeat rep_count prop) (* 25 times each, then 25 * 15 times when shrinking *)

  let mk_neg_agree_test ~count ~name prop =
    let rep_count = 25 in
    let seq_len,par_len = 20,12 in
    let max_gen = 3*count in (* precond filtering may require extra generation: max. 3*count though *)
    Test.make_neg ~retries:15 ~max_gen ~count ~name
      (arb_cmds_par seq_len par_len)
      (repeat rep_count prop) (* 25 times each, then 25 * 15 times when shrinking *)

  let agree_test_par ~count ~name = mk_agree_test ~count ~name agree_prop_par
  let neg_agree_test_par ~count ~name = mk_neg_agree_test ~count ~name agree_prop_par
  let agree_test_conc ~count ~name = mk_agree_test ~count ~name agree_prop_thread
  let neg_agree_test_conc ~count ~name = mk_neg_agree_test ~count ~name agree_prop_thread
end

(** ********************************************************************** *)

module AddGC(Spec : StmSpec) : StmSpec
=
struct
  type cmd =
    | GC_minor
    | UserCmd of Spec.cmd

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

  let run c s = match c with
    | GC_minor  -> (Gc.minor (); Res (unit, ()))
    | UserCmd c -> Spec.run c s

  let postcond c s r = match c,r with
    | GC_minor,  Res ((Unit,_),_) -> true
    | UserCmd c, r -> Spec.postcond c s r
    | _,_ -> false
end
