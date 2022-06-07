open QCheck
open Channel
module Chan = STM.Make (ChConf)


module StatisticsLength = struct
  let prop stats (_seq, p0, p1) =
    assume (List.length p0 > 1 && List.length p1 > 1);
    let i = List.length p0 + List.length p1 in
    stats.(i) <- stats.(i) + 1;
    true

  let par_len = 10
  let stats_custom = Array.make (2 * par_len + 1) 0
  let stats_ordinary = Array.make (2 * par_len + 1) 0
  let prop_custom = prop stats_custom
  let prop_ordinary pg =
    QCheck.(assume ((fun (pref, p0, p1) -> Chan.all_interleavings_ok pref p0 p1 ChConf.init_state) pg));
    prop stats_ordinary pg

  let test_custom = Test.make
                     ~name:"Statistics on concurrent suffixes' length with custom generators"
                     ~count:1000
                     (Chan.arb_cmds_par_custom 20 par_len)
                     prop_custom

  let test_ordinary = Test.make
                        ~name:"Statistics on concurrent suffixes' length with ordinary generators"
                        ~count:1000
                        ~max_gen:3000
                        (Chan.arb_cmds_par 20 par_len)
                        prop_ordinary

 let _ = QCheck_runner.run_tests ~verbose:false [ test_custom; test_ordinary ]
 let _ =
   let data ar = Array.to_list ar |> List.map Int.to_string |> String.concat "," in 
   let data_custom = "custom," ^ data stats_custom in
   let data_ordinary = "ordinary," ^ data stats_ordinary in
   Out_channel.with_open_text "length.data" (fun oc ->
       Printf.fprintf oc "%s\n%s\n" data_custom data_ordinary)
  end
