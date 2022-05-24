open QCheck

module CounterSpec = struct
  type cmd =
    | Add of int
    | Read
    | Sub of int

  let add i = Add i
  let sub i = Sub i

  type state = int

  type sut = int ref

  let arb_cmd s =
    let open Gen in
    let max = 10 in
    let int = int_bound (max / 2) in
    let gen =
      if s = 0
      then oneof [ return Read; map add int ]
      else if s = 10
      then oneof [ return Read; map sub int ]
      else oneof [ return Read; map add (int_bound (max - s)); map sub (int_bound s)]
    in
    make gen


  end

open STM
(* let test = Make (CounterSpec) *)
