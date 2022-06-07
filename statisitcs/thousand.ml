open QCheck
open Channel
module Chan = STM.Make (ChConf)

let par_len = 10
let prop hyp pg = assume (hyp pg); true

let test_custom = Test.make
                   ~name:"Generate a thousand of valid programs with custom generators"
                   ~count:1000
                   (Chan.arb_cmds_par_custom 20 par_len)
                   (prop (fun _ -> true))

let test_ordinary = Test.make
                      ~name:"Generate a thousand of valid programs with ordinary generators"
                      ~count:1000
                      ~max_gen:3000
                      (Chan.arb_cmds_par 20 par_len)
                      (prop (fun (pref,p0,p1) -> Chan.all_interleavings_ok pref p0 p1 ChConf.init_state))

let _ =
  let arg = Sys.argv.(1) in
  match arg with
  | "custom" -> QCheck_runner.run_tests ~verbose:false [ test_custom ]
  | "ordinary" -> QCheck_runner.run_tests ~verbose:false [ test_ordinary ]
  | s -> raise (Invalid_argument s)
