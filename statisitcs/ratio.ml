open QCheck
open Channel
module Chan = STM.Make (ChConf)

let count cpt (seq,p0,p1) =
  assume (List.length p0 > 1 && List.length p1 > 1);
  try
    let res = Util.repeat 100 Chan.agree_prop_par (seq,p0,p1) in
    if not res then incr cpt;
    true
  with
    _ -> incr cpt; true

let par_len       = 10
let custom        = ref 0
let ordinary      = ref 0
let prop_custom   = count custom
let prop_ordinary = count ordinary

let test_custom = Test.make
                   ~name:"Statistics on buggy programs over 10000 with custom generator"
                   ~count:10000
                   (Chan.arb_cmds_par_custom 20 par_len)
                   prop_custom
    
let test_ordinary = Test.make
                   ~name:"Statistics on buggy programs over 10000 with ordinary generator"
                   ~count:10000
                   (Chan.arb_cmds_par 20 par_len)
                   prop_ordinary
  
let _ = QCheck_runner.run_tests ~verbose:false [ test_custom; test_ordinary ]
let _ = Printf.printf "Buggy programs with custom generator:  %i / 10_000\n%!" (!custom)
let _ = Printf.printf "Buggy programs with ordinay generator: %i / 10_000\n%!" (!ordinary)
