--  The tests of the specifications of the kernels (AMV.Spec) call ghost
--  functions, which the library's policy of contracts ignores: they run
--  in the build of the tests that checks every contract only
--  (tests/checked/test_spec.adb).

with Ada.Text_IO;

procedure Test_Spec is
begin
   Ada.Text_IO.Put_Line ("Test_Spec: run by test_suite only");
end Test_Spec;
