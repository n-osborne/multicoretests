open QCheck
open Channel
module Chan = STM.Make (ChConf)

let count stats (_seq,p0,p1) =
  let open ChConf in
  let rec aux = function
    | [] -> ()
    | Send _ :: xs -> stats.(0) <- stats.(0) + 1; aux xs
    | Send_poll _ :: xs -> stats.(1) <- stats.(1) + 1; aux xs
    | Recv :: xs -> stats.(2) <- stats.(2) + 1; aux xs
    | Recv_poll :: xs -> stats.(3) <- stats.(3) + 1; aux xs
  in
  aux p0; aux p1

let par_len = 10
let stats_custom = Array.make 4 0
let stats_ordinary = Array.make 4 0
let prop_custom pg = count stats_custom pg; true
let prop_ordinary (pref, p0, p1) =
  assume (Chan.all_interleavings_ok pref p0 p1 ChConf.init_state);
  count stats_ordinary (pref,p0,p1);
  true

let test_custom = Test.make
                    ~name:"Distribution of commands with custom generator"
                    ~count:1000
                     ~max_gen:5000
                     (Chan.arb_cmds_par_custom 20 par_len)
                     prop_custom

let test_ordinary = Test.make
                      ~name:"Distribution of commands with ordinary generator"
                     ~count:1000
                     ~max_gen:5000
                     (Chan.arb_cmds_par 20 par_len)
                     prop_ordinary

let _ = QCheck_runner.run_tests ~verbose:false [ test_custom; test_ordinary ]
let _ =
  let data ar = Array.to_list ar |> List.map Int.to_string |> String.concat "," in 
  let data_custom = "custom," ^ data stats_custom in
  let data_ordinary = "ordinary," ^ data stats_ordinary in
  Out_channel.with_open_text "distribution.data" (fun oc ->
      Printf.fprintf oc "%s\n%s\n" data_custom data_ordinary)
