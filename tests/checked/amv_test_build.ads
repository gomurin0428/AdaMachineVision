--  The build of the tests: this one (amv_tests.gpr, tests/contracts.adc)
--  checks every precondition, postcondition, predicate and piece of ghost
--  code of the library. The other (amv_tests_library.gpr) has the
--  library's policy, preconditions only (contracts.adc).

package AMV_Test_Build is

   pragma Pure;

   Contracts_Checked : constant Boolean := True;
   --  The postconditions run with the tests. A test whose result depends
   --  on the library's own speed (a timing), or which passes what the
   --  proofs assume away (a NaN or an infinity, docs/PROOF.md, Assumptions
   --  and limits) where a postcondition compares it, runs in the other
   --  build only.

end AMV_Test_Build;
