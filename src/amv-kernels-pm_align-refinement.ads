--  The least squares refinement of AMV.Kernels.PM_Align (PatMax) and the
--  measures of a result: coverage, clutter, fit error, contrast and the
--  fraction of the model outside the search region.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.PM_Align.Poses;
with AMV.Kernels.PM_Align.Pyramids;

private package AMV.Kernels.PM_Align.Refinement
  with SPARK_Mode, Preelaborate
is

   package P renames AMV.Kernels.PM_Align.Poses;
   package PY renames AMV.Kernels.PM_Align.Pyramids;

   Max_Fit_Error : constant := 64.0;
   Max_Contrast  : constant := 1024.0;

   type Measures is record
      Coverage  : P.Fraction := 0.0;
      Clutter   : P.Fraction := 0.0;
      Outside   : P.Fraction := 0.0;
      Fit_Error : Long_Float range 0.0 .. Max_Fit_Error := 0.0;
      Contrast  : Long_Float range 0.0 .. Max_Contrast := 0.0;
   end record;
   --  The measures of a pose (see AMV.Kernels.PM_Align): Coverage,
   --  Clutter, the fraction of the features outside the search region,
   --  FitError (pixels of the input image) and Contrast (grey levels per
   --  pixel of the level).

   procedure Refine
     (Model  : Model_Level;
      F      : P.Frame;
      L      : PY.Level_Data;
      Level  : Level_Index;
      Params : Ks_PM_Align_Run_Params;
      X, Y   : in out P.Position;
      Theta  : in out P.Zone_Angle_Value;
      Scale  : in out P.Scale_Value)
   with Pre => PY.Usable (L) and then Valid_Run_Params (Params);
   --  The least squares refinement of the pose (the centroid at X, Y in
   --  pixels of Level, Theta, Scale) on the features of Model, at most
   --  Refine_Iterations times (see AMV.Kernels.PM_Align). Theta and Scale
   --  stay in their zones (and keep their value for a Nominal zone).

   procedure Measure
     (Model  : Model_Level;
      F      : P.Frame;
      L      : PY.Level_Data;
      Level  : Level_Index;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Area   : PY.Window;
      Params : Ks_PM_Align_Run_Params;
      X, Y   : P.Position;
      Theta  : P.Zone_Angle_Value;
      Scale  : P.Scale_Value;
      Result : out Measures;
      Status : out Ks_Status)
   with
     Pre  => PY.Usable (L) and then Valid_Run_Params (Params),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory;
   --  The measures of the pose. Clutter is computed only when
   --  ScoreUsingClutter is set and Coverage reaches AcceptThreshold (it
   --  is 0 otherwise); it needs a mask of the footprint, whose allocation
   --  may fail (Out_Of_Memory).

end AMV.Kernels.PM_Align.Refinement;
