--  The build of the tests: this one (amv_tests_library.gpr) has the
--  library's policy, preconditions only (contracts.adc). The other
--  (amv_tests.gpr, tests/contracts.adc) checks every precondition,
--  postcondition, predicate and piece of ghost code of the library.

package AMV_Test_Build is

   pragma Pure;

   Contracts_Checked : constant Boolean := False;
   --  The postconditions do not run: every test runs here, those of
   --  timing and those that pass a NaN or an infinity included.

end AMV_Test_Build;
