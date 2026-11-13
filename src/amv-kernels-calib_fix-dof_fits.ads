--  The fits of AMV.Kernels.Calib_Fix: the transform of a DOF that maps
--  the B points of a list of pairs onto their A points with the least sum
--  of squared distances. The methods are described in the parent's spec.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.Calib_Fix.DOF_Fits
  with SPARK_Mode, Preelaborate
is

   Identity_Fit : constant Ks_N_Point_To_N_Point_Fit := (others => <>);

   procedure Fit
     (Pairs  : Pair_Array;
      Count  : Natural;
      DOF    : DOF_Code;
      Result : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   with
     Pre  => Pairs'First = 0
             and then Count <= Max_Pairs
             and then Count - 1 <= Pairs'Last
             and then Count >= Min_Points (DOF),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Gold_Fit (Result, DOF)
                       else Result = Identity_Fit);
   --  The fit of DOF to Pairs (0 .. Count - 1), whose count the caller has
   --  checked. Bad_Parameter for degenerate data (see the parent);
   --  Result is the identity then.

end AMV.Kernels.Calib_Fix.DOF_Fits;
