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


module StatisticsLength = struct
  let prop stats (_seq, p0, p1) =
    let i = List.length p0 + List.length p1 in
    stats.(i) <- stats.(i) + 1;
    true

  let par_len = 10
  let stats_smart = Array.make (2 * par_len + 1) 0
  let stats_ordinary = Array.make (2 * par_len + 1) 0
  let prop_smart = prop stats_smart
  let prop_ordinary = prop stats_ordinary

  let test_smart = Test.make
                     ~name:"Statistics on concurrent suffixes' length with smart generators"
                     ~count:1000
                     (Counter.arb_cmds_par_smart 20 par_len)
                     prop_smart

  let test_ordinary = Test.make
                        ~name:"Statistics on concurrent suffixes' length with ordinary generators"
                        ~count:1000
                        (Counter.arb_cmds_par 20 par_len)
                        prop_ordinary

 let _ = QCheck_runner.run_tests ~verbose:false [ test_smart; test_ordinary ]
 let _ =
   let data ar = Array.to_list ar |> List.map Int.to_string |> String.concat "," in 
   let data_smart = "smart," ^ data stats_smart in
   let data_ordinary = "ordinary," ^ data stats_ordinary in
   Out_channel.with_open_text "length.data" (fun oc ->
       Printf.fprintf oc "%s\n%s\n" data_smart data_ordinary)
   (* Printf.printf "%s\n%s\n" data_smart data_ordinary; *)
   (* close_out oc *)
  end
