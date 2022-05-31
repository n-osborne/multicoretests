open QCheck

module CounterSpec = struct
  type cmd =
    | Add of int
    | Read
    | Sub of int [@@deriving show { with_path = false }]

  let add i = Add i
  let sub i = Sub i

  let max = 10
  type state = int

  type sut = int ref

  let arb_cmd s =
    let open Gen in
    let int = int_bound 3 in
    let gen =
      if s = 0
      then oneof [ return Read; map add int ]
      else if s = 10
      then oneof [ return Read; map sub int ]
      else oneof [ return Read; map add (int_bound (max - s)); map sub (int_bound s)]
    in
    make gen

  let init_state = 0
  let next_state c s = match c with
    | Add i -> s + i
    | Read -> s
    | Sub i -> s - i

  let init_sut () = ref 0
  let cleanup sut = sut := 0
  let precond c s =
    match c with
    | Add i -> i + s <= max
    | Read -> true
    | Sub i -> s - i >= 0

  type res =
    | RAdd | RRead of int | RSub [@@deriving show { with_path = false }]


  let run cmd sut =
    match cmd with
    | Add i -> sut := !sut + i; RAdd
    | Read -> RRead (!sut)
    | Sub i -> sut := !sut - i; RSub

  let postcond c s res = match c,res with
    | Add _, RAdd -> true
    | Read, RRead i -> i = s
    | Sub _, RSub -> true
    | _, _ -> false

  let generators = make Gen.(oneof
                               [ return Read;
                                 map add (int_bound 3);
                                 map sub (int_bound 3)])
  end

module Counter = STM.Make (CounterSpec)

let prop hyp pg = assume (hyp pg); true

let test_smart = Test.make
                   ~name:"Generate a thousand of valid programs with smart generators"
                   ~count:1000
                   (Counter.arb_cmds_par_smart 20 10)
                   (prop (fun _ -> true))

let test_ordinary = Test.make
                      ~name:"Generate a thousand of valid programs with ordinary generators"
                      ~count:1000
                      ~max_gen:3000
                      (Counter.arb_cmds_par 20 10)
                      (prop (fun (pref,p0,p1) -> Counter.all_interleavings_ok pref p0 p1 CounterSpec.init_state))

let _ =
  let arg = Sys.argv.(1) in
  match arg with
  | "smart" -> QCheck_runner.run_tests ~verbose:false [ test_smart ]
  | "ordinary" -> QCheck_runner.run_tests ~verbose:false [ test_ordinary ]
  | s -> raise (Invalid_argument s)
