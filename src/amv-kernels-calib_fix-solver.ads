--  A small dense linear solver for the nonlinear calibration of
--  AMV.Kernels.Calib_Fix (AMV.Kernels.Calib_Fix.Radial): the normal
--  equations of the plane-to-image homography (8 x 8) and the damped
--  Gauss-Newton steps of the full model (10 x 10).
--
--  Gaussian elimination with partial pivoting (the textbook method; Golub
--  and Van Loan, "Matrix Computations", section 3.4). Every entry is kept
--  within Entry_Limit and every unknown within Solution_Limit: an entry
--  that would leave its bound during the elimination, a pivot below
--  Relative_Pivot times the largest entry of the matrix (a singular or
--  nearly singular system) and an unknown beyond its bound make the solver
--  report that it found no solution, which its callers turn into a
--  rejected step or Bad_Parameter. With partial pivoting no multiplier
--  exceeds 1, so an entry grows at most by a factor 2**(N - 1) = 512;
--  the callers' entries stay below 2**92, far from Entry_Limit.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.Calib_Fix.Solver
  with SPARK_Mode, Preelaborate
is

   Max_Order : constant := 10;

   subtype Order is Positive range 1 .. Max_Order;

   Entry_Limit : constant := 2.0 ** 100;
   subtype Entry_Value is Long_Float range -Entry_Limit .. Entry_Limit;

   Solution_Limit : constant := 2.0 ** 100;
   subtype Solution_Value is
     Long_Float range -Solution_Limit .. Solution_Limit;

   Relative_Pivot : constant := 2.0 ** (-44);
   --  About 5.7E-14: the smallest pivot accepted, relative to the largest
   --  entry of the matrix.

   type Matrix is array (Order, Order) of Entry_Value;
   type Vector is array (Order) of Entry_Value;
   type Solution is array (Order) of Solution_Value;

   Zero_Solution : constant Solution := [others => 0.0];

   procedure Solve
     (A     : Matrix;
      B     : Vector;
      N     : Order;
      X     : out Solution;
      Found : out Boolean)
   with
     Post => (if not Found then X = Zero_Solution);
   --  Solves A (1 .. N, 1 .. N) X (1 .. N) = B (1 .. N); the other
   --  entries of A and B are not used and those of X are 0. Found is
   --  False (and X zero) when the system is singular or nearly so, or
   --  when a value would leave its bound (see above).

end AMV.Kernels.Calib_Fix.Solver;
