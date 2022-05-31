open QCheck

(** This is a parallel test of refs *)

module Sut_int =
  struct
    let init () = ref 0
    let get r = !r
    let set r i = r:=i
    let add r i = let old = !r in r:=i + old (* buggy: not atomic *)
    let incr r = incr r                      (* buggy: not atomic *)
    let decr r = decr r                      (* buggy: not atomic *)
end

module Sut_int64 =
  struct
    let init () = ref Int64.zero
    let get r = !r
    let set r i = r:=i
    let add r i = let old = !r in r:= Int64.add i old (* buggy: not atomic *)
    let incr r = add r Int64.one                      (* buggy: not atomic *)
    let decr r = add r Int64.minus_one                (* buggy: not atomic *)
end

module RConf_int =
struct
  type sut = int ref
  type state = int
  type cmd =
    | Get
    | Set of int
    | Add of int
    | Incr
    | Decr [@@deriving show { with_path = false }]

  let arb_cmd _s =
    let int_gen = Gen.nat in
    QCheck.make ~print:show_cmd
      (Gen.oneof
         [Gen.return Get;
	  Gen.map (fun i -> Set i) int_gen;
	  Gen.map (fun i -> Add i) int_gen;
          Gen.return Incr;
	  Gen.return Decr;
         ])

  let init_state  = 0
  let init_sut () = Sut_int.init ()
  let cleanup _   = ()

  let next_state c s = match c with
    | Get   -> s
    | Set i -> i (*if i<>1213 then i else s*) (* an artificial fault *)
    | Add i -> s+i
    | Incr  -> s+1
    | Decr  -> s-1

  let precond _ _ = true

  type res = RGet of int | RSet | RAdd | RIncr | RDecr [@@deriving show { with_path = false }]

  let run c r = match c with
    | Get   -> RGet (Sut_int.get r)
    | Set i -> (Sut_int.set r i; RSet)
    | Add i -> (Sut_int.add r i; RAdd)
    | Incr  -> (Sut_int.incr r; RIncr)
    | Decr  -> (Sut_int.decr r; RDecr)

  let postcond c s res = match c,res with
    | Get, RGet v -> v = s (*&& v<>42*) (*an injected bug*)
    | Set _, RSet -> true
    | Add _, RAdd -> true
    | Incr, RIncr -> true
    | Decr, RDecr -> true
    | _,_ -> false

  let generators = 
    let int_gen = Gen.nat in
    (QCheck.make ~print:show_cmd)
      (Gen.oneof
         [Gen.return Get;
	  Gen.map (fun i -> Set i) int_gen;
	  Gen.map (fun i -> Add i) int_gen;
          Gen.return Incr;
	  Gen.return Decr;
         ])
end

module RConf_int64 =
struct
  type sut = int64 ref
  type state = int64
  type cmd =
    | Get
    | Set of int64
    | Add of int64
    | Incr
    | Decr [@@deriving show { with_path = false }]

  let arb_cmd _s =
    let int64_gen = Gen.(map Int64.of_int nat) in
    QCheck.make ~print:show_cmd
      (Gen.oneof
         [Gen.return Get;
	  Gen.map (fun i -> Set i) int64_gen;
	  Gen.map (fun i -> Add i) int64_gen;
          Gen.return Incr;
	  Gen.return Decr;
         ])

  let init_state  = 0L
  let init_sut () = Sut_int64.init ()
  let cleanup _   = ()

  let next_state c s = match c with
    | Get   -> s
    | Set i -> i (*if i<>1213 then i else s*) (* an artificial fault *)
    | Add i -> Int64.add s i
    | Incr  -> Int64.succ s
    | Decr  -> Int64.pred s

  let precond _ _ = true

  type res = RGet of int64 | RSet | RAdd | RIncr | RDecr [@@deriving show { with_path = false }]

  let run c r = match c with
    | Get   -> RGet (Sut_int64.get r)
    | Set i -> (Sut_int64.set r i; RSet)
    | Add i -> (Sut_int64.add r i; RAdd)
    | Incr  -> (Sut_int64.incr r; RIncr)
    | Decr  -> (Sut_int64.decr r; RDecr)

  let postcond c s res = match c,res with
    | Get, RGet v -> v = s (*&& v<>42L*) (*an injected bug*)
    | Set _, RSet -> true
    | Add _, RAdd -> true
    | Incr, RIncr -> true
    | Decr, RDecr -> true
    | _,_ -> false

  let generators =
    let int64_gen = Gen.(map Int64.of_int nat) in
    (QCheck.make ~print:show_cmd)
      (Gen.oneof
         [Gen.return Get;
	  Gen.map (fun i -> Set i) int64_gen;
	  Gen.map (fun i -> Add i) int64_gen;
          Gen.return Incr;
	  Gen.return Decr;
         ])

end


module RT_int   = STM.Make(RConf_int)
module RT_int64 = STM.Make(RConf_int64)

module RConf_int_GC = STM.AddGC(RConf_int)
module RConf_int64_GC = STM.AddGC(RConf_int64)

module RT_int_GC = STM.Make(RConf_int_GC)
module RT_int64_GC = STM.Make(RConf_int64_GC)
;;
Util.set_ci_printing ()
;;
QCheck_runner.run_tests_main
  (let count = 1000 in
   [RT_int.agree_test        ~count ~name:"global int ref test";
    RT_int.agree_test_par    ~count ~name:"global int ref test";
    RT_int_GC.agree_test_par ~count ~name:"global int ref test (w/AddGC functor)";
    RT_int.agree_test        ~count ~name:"global int64 ref test";
    RT_int.agree_test_par    ~count ~name:"global int64 ref test";
    RT_int_GC.agree_test_par ~count ~name:"global int64 ref test (w/AddGC functor)";
   ])
