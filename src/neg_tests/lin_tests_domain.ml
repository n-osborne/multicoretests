open Lin_tests_common

(** This is a driver of the negative tests over the Domain module *)

;;
QCheck_base_runner.run_tests_main
  (let count = 15000 in
   [RT_int_domain.neg_lin_test    ~count ~name:"Lin ref int test with Domain";
    RT_int64_domain.neg_lin_test  ~count ~name:"Lin ref int64 test with Domain";
    CLT_int_domain.neg_lin_test   ~count ~name:"Lin CList int test with Domain";
    CLT_int64_domain.neg_lin_test ~count ~name:"Lin CList int64 test with Domain"])
