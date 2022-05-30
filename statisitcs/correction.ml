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

module TestCorrectness = struct

  let prop (seq, p0, p1) =
      let rec go_seq state = function
    | [] -> Some state
    | x :: xs -> (
        match CounterSpec.precond x state with
        | false -> None
        | true ->
            let state = CounterSpec.next_state x state in
            go_seq state xs)
  in
  let rec go_par state p0 p1 =
    match (p0, p1) with
    | [], [] -> true
    | pg, [] | [], pg -> Option.is_some (go_seq state pg)
    | x :: xs, y :: ys ->
        CounterSpec.precond x state && CounterSpec.precond y state
        && go_par (CounterSpec.next_state x state) xs (y :: ys)
        && go_par (CounterSpec.next_state y state) (x :: xs) ys
  in
  match go_seq CounterSpec.init_state seq with
  | None -> false
  | Some spawn_state -> go_par spawn_state p0 p1

  let count cpt pg =
    try
      if not (prop pg) then incr cpt;
      true
    with
      _ -> incr cpt; true

  let smart = ref 0
  let ordinary = ref 0
  let prop_smart = count smart
  let prop_ordinary = count ordinary
  
  let test_smart = Test.make
                     ~name:"Test output repects preconditions smart generator"
                     ~count:1000
                     (Counter.arb_cmds_par_smart 20 12)
                     prop_smart
  
  let test_ordinary = Test.make
                        ~name:"Test output repects preconditions ordinary generator"
                        ~count:1000
                        (Counter.arb_cmds_par 20 12)
                        prop_ordinary
  
 let _ = QCheck_runner.run_tests ~verbose:true [ test_smart; test_ordinary ]

 let _ = Printf.printf "smart generator:     %i / 1000\n%!" (!smart)
 let _ = Printf.printf "ordinary generator:  %i / 1000\n%!" (!ordinary)
end
