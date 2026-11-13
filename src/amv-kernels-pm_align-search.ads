--  The grid search of AMV.Kernels.PM_Align: the coarse search over the
--  zones at the coarsest level, the tracking of the candidates down the
--  pyramid by hill climbing, and the interpolation of a grid pose
--  (PatQuick). Scores are sums of products of quantised directions
--  (integers), so the inner loop needs no floating-point bounds.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.PM_Align.Poses;
with AMV.Kernels.PM_Align.Pyramids;

private package AMV.Kernels.PM_Align.Search
  with SPARK_Mode, Preelaborate
is

   package P renames AMV.Kernels.PM_Align.Poses;
   package PY renames AMV.Kernels.PM_Align.Pyramids;

   type Candidate is record
      X, Y  : P.Position := 0.0;
      Theta : P.Zone_Angle_Value := 0.0;
      Scale : P.Scale_Value := 1.0;
      Score : P.Fraction := 0.0;
      Level : Level_Index := 0;
   end record;
   --  A pose of the model's centroid in pixels of level Level, with its
   --  score there.

   type Candidate_Array is array (0 .. Max_Candidates - 1) of Candidate;

   type Candidate_List is record
      Count : Natural range 0 .. Max_Candidates := 0;
      Items : Candidate_Array;
   end record;

   Dot_Norm : constant := 127 * 127;
   --  The product of two quantised unit vectors that agree.

   Max_Dot : constant := 2 * 127 * 128;
   --  The bound of one product (a direction image holds 0 .. 255).

   function Grid_Score
     (Q               : P.Quantised_Model;
      L               : PY.Level_Data;
      X, Y            : Int64;
      Ignore_Polarity : Boolean;
      Stop            : Int64) return Int64
   with Pre  => PY.Has_Directions (L)
                and then X in -2 ** 40 .. 2 ** 40
                and then Y in -2 ** 40 .. 2 ** 40,
        Post => abs Grid_Score'Result <= Int64 (Q.Count) * Max_Dot;
   --  The sum, over the features of Q placed with the centroid at pixel
   --  (X, Y), of the product of the feature's quantised normal and the
   --  direction of the pixel under it (its absolute value with
   --  Ignore_Polarity; 0 for a feature outside the level). Stops early,
   --  with a sum below Stop, once the remaining features cannot bring the
   --  sum to Stop.

   function Score_Of (Sum : Int64; Count : Feature_Count) return P.Fraction;
   --  Sum / (Dot_Norm * Count), limited to [0, 1] (0 for Count = 0).

   procedure Coarse
     (Pattern   : access constant Ks_PM_Align_Pattern_Data;
      F         : P.Frame;
      Pyr       : PY.Pyramid;
      Params    : Ks_PM_Align_Run_Params;
      Threshold : P.Fraction;
      List      : out Candidate_List;
      Status    : out Ks_Status)
   with
     Pre  => Trained_Pattern (Pattern) and then Valid_Run_Params (Params),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory;
   --  The coarse search at level Pattern.Coarsest (see AMV.Kernels.
   --  PM_Align): the candidates, sorted by score (highest first), without
   --  near duplicates.

   procedure Track
     (Pattern   : access constant Ks_PM_Align_Pattern_Data;
      F         : P.Frame;
      Pyr       : PY.Pyramid;
      Params    : Ks_PM_Align_Run_Params;
      Threshold : P.Fraction;
      Limit     : Positive;
      List      : in out Candidate_List)
   with Pre => Trained_Pattern (Pattern) and then Valid_Run_Params (Params);
   --  Follows the first Limit candidates of List (at level Coarsest) down
   --  to level Pattern.Finest by hill climbing; List keeps those whose
   --  score stays at least Threshold, at level Finest, sorted by score
   --  (highest first) without near duplicates (compared in level-0
   --  pixels). With the automatic grain (the pattern's
   --  Grain_Limit_Auto_Select) a candidate whose score falls below
   --  Threshold at a level stops at the level above instead of being
   --  dropped; each candidate's Level says where it is.

   procedure Interpolate
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      F       : P.Frame;
      Pyr     : PY.Pyramid;
      Params  : Ks_PM_Align_Run_Params;
      C       : in out Candidate)
   with Pre => Trained_Pattern (Pattern) and then Valid_Run_Params (Params);
   --  Moves a candidate at level Finest to the vertex of the parabolas
   --  through the scores of its neighbours along x, y and the angle
   --  (PatQuick).

   function Angle_Step
     (F      : P.Frame;
      Scale  : P.Scale_Value;
      Level  : Level_Index) return Long_Float
   with Post => Angle_Step'Result > 0.0 and then Angle_Step'Result <= 1.0;
   --  About one pixel at the model's radius at Level: 1 / radius.

end AMV.Kernels.PM_Align.Search;
