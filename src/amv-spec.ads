--  The root of the specifications of the kernels (docs/PLATINUM.md).
--
--  A child of AMV.Spec states what a kernel computes, as functions written
--  from a definition, not from the code: a standard (it cites the
--  section), mathematics, or the definition in AMV's documentation, which
--  it follows word for word. The postconditions of the kernels name these
--  functions; the code calls them only as ghost code.
--
--  Every unit of AMV.Spec:
--
--  * is ghost as a whole, so that the library holds none of it (its
--    policy ignores ghost code, contracts.adc), while the tests run it
--    (tests/contracts.adc) and test it on its own;
--  * depends only on AMV.Spec and its children, on AMV.Kernels (the types
--    that every kernel shares), on Interfaces and on the big numbers of
--    Ada 2022: never on the kernel that it specifies;
--  * is executable: every function has a body that runs, so that the
--    tests can compare a kernel with it.
--
--  make check enforces the first two (tools/shell_check).

pragma Validity_Checks ("F");

package AMV.Spec
  with SPARK_Mode, Ghost
is
   pragma Pure;
end AMV.Spec;
