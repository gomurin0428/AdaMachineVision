--  Test helper: checks that AMV.Checks.Check turns every kernel failure
--  code into the right exception. It is a child of AMV only so that its
--  body may see the private package AMV.Checks.

procedure AMV.Test_Check_Mapping;
