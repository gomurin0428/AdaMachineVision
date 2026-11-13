pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.Image_Math;
with AMV.Kernels.Numerics;

package body AMV.Kernels.PM_Align.Search with SPARK_Mode is

   package KM renames AMV.Kernels.Image_Math;
   package N renames AMV.Kernels.Numerics;

   use type KM.Real_Pixels;

   procedure Free is new Ada.Unchecked_Deallocation
     (KM.Real_Matrix, KM.Real_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KM.Ks_Real_Image_Data, KM.Ks_Real_Image);

   Stop_Dot : constant := 16_384;
   --  The largest product of two quantised unit vectors (each component
   --  rounded, so a length of at most 127.71): the early stop of
   --  Grid_Score assumes no feature adds more.

   Climb_Iterations : constant := 4;
   --  The most steps of a hill climb at one level.

   ---------------------------------------------------------------------
   --  Scores
   ---------------------------------------------------------------------

   Max_Product : constant := 127 * 128;

   function Product (Q : P.Quantum; V : KI.Grey_8) return Int64
   with Post => Product'Result in -Max_Product .. Max_Product;
   --  Q times the direction value V less Neutral (V - Neutral is in
   --  -127 .. 128).

   function Product (Q : P.Quantum; V : KI.Grey_8) return Int64 is
      Centred : constant Int64 range -127 .. 128 :=
        Int64 (V) - PY.Neutral;
   begin
      return Int64 (Q) * Centred;
   end Product;

   function Grid_Score
     (Q               : P.Quantised_Model;
      L               : PY.Level_Data;
      X, Y            : Int64;
      Ignore_Polarity : Boolean;
      Stop            : Int64) return Int64
   is
      W   : constant Int64 := Int64 (L.DX.Width);
      H   : constant Int64 := Int64 (L.DX.Height);
      Sum : Int64 := 0;
   begin
      for I in 0 .. Q.Count - 1 loop
         declare
            XX : constant Int64 := X + Int64 (Q.Items (I).OX);
            YY : constant Int64 := Y + Int64 (Q.Items (I).OY);
            D  : Int64;
         begin
            if XX >= 0 and then XX < W and then YY >= 0 and then YY < H then
               D := Product (Q.Items (I).QX,
                             L.DX.Pixels (Natural (YY), Natural (XX)))
                    + Product (Q.Items (I).QY,
                               L.DY.Pixels (Natural (YY), Natural (XX)));
               if Ignore_Polarity and then D < 0 then
                  D := -D;
               end if;
               Sum := Sum + D;
            end if;
         end;
         pragma Loop_Invariant (abs Sum <= Int64 (I + 1) * Max_Dot);
         exit when Sum + Stop_Dot * Int64 (Q.Count - 1 - I) < Stop;
      end loop;
      return Sum;
   end Grid_Score;

   function Score_Of (Sum : Int64; Count : Feature_Count) return P.Fraction
   is
      Result : Long_Float;
      Fits   : Boolean;
   begin
      if Count = 0 or else Sum <= 0 then
         return 0.0;
      end if;
      --  Sum is at most Count * Max_Dot, below 2**27.
      N.Ratio_Within (Long_Float (Int64'Min (Sum, 2 ** 27)),
                      Long_Float (Dot_Norm * Count), 1.0, Result, Fits);
      return (if Fits then Result else 1.0);
   end Score_Of;

   function Stop_Of (Threshold : P.Fraction; Count : Feature_Count)
      return Int64
   is (Int64 (Long_Float'Floor
                (N.Times_Unit (Long_Float (Dot_Norm * Count), Threshold))));
   --  The smallest sum whose score reaches Threshold, rounded down so that
   --  the early stop never drops such a position.

   function Angle_Step
     (F      : P.Frame;
      Scale  : P.Scale_Value;
      Level  : Level_Index) return Long_Float
   is
      R : constant P.Pixel_Radius := P.Pixel_Radius_Of (F, Scale, Level);
   begin
      return 1.0 / R;
   end Angle_Step;

   ---------------------------------------------------------------------
   --  Candidate lists
   ---------------------------------------------------------------------

   procedure Insert (List : in out Candidate_List; C : Candidate)
   with Post => List.Count >= List.Count'Old;
   --  Appends C, or replaces the worst candidate by C when the list is
   --  full and C is better.

   procedure Insert (List : in out Candidate_List; C : Candidate) is
      Worst : Natural range 0 .. Max_Candidates - 1 := 0;
   begin
      if List.Count < Max_Candidates then
         List.Items (List.Count) := C;
         List.Count := List.Count + 1;
         return;
      end if;
      for I in 1 .. Max_Candidates - 1 loop
         if List.Items (I).Score < List.Items (Worst).Score then
            Worst := I;
         end if;
      end loop;
      if C.Score > List.Items (Worst).Score then
         List.Items (Worst) := C;
      end if;
   end Insert;

   procedure Sort (List : in out Candidate_List)
   with Post => List.Count = List.Count'Old;
   --  Sorts by score, highest first (stable).

   procedure Sort (List : in out Candidate_List) is
   begin
      for I in 1 .. List.Count - 1 loop
         declare
            C : constant Candidate := List.Items (I);
            J : Natural := I;
         begin
            while J > 0 and then List.Items (J - 1).Score < C.Score loop
               pragma Loop_Invariant (J <= I);
               pragma Loop_Variant (Decreases => J);
               List.Items (J) := List.Items (J - 1);
               J := J - 1;
            end loop;
            List.Items (J) := C;
         end;
      end loop;
   end Sort;

   function Near
     (A, B             : Candidate;
      Pixels           : Long_Float;
      Angle_Tolerance  : Long_Float;
      Scale_Tolerance  : Long_Float) return Boolean
   is (abs (P.From_Level (A.X, A.Level) - P.From_Level (B.X, B.Level))
         <= Pixels
       and then abs (P.From_Level (A.Y, A.Level)
                     - P.From_Level (B.Y, B.Level)) <= Pixels
       and then P.Angle_Distance (A.Theta, B.Theta) <= Angle_Tolerance
       and then abs (A.Scale - B.Scale) <= Scale_Tolerance);

   procedure Suppress
     (List            : in out Candidate_List;
      Pixels          : Long_Float;
      Angle_Tolerance : Long_Float;
      Scale_Tolerance : Long_Float)
   with Post => List.Count <= List.Count'Old;
   --  Drops every candidate near a better one before it (List sorted by
   --  score, highest first).

   procedure Suppress
     (List            : in out Candidate_List;
      Pixels          : Long_Float;
      Angle_Tolerance : Long_Float;
      Scale_Tolerance : Long_Float)
   is
      Kept : Natural range 0 .. Max_Candidates := 0;
   begin
      for I in 0 .. List.Count - 1 loop
         pragma Loop_Invariant (Kept <= I);
         declare
            Duplicate : Boolean := False;
         begin
            for J in 0 .. Kept - 1 loop
               if Near (List.Items (J), List.Items (I), Pixels,
                        Angle_Tolerance, Scale_Tolerance)
               then
                  Duplicate := True;
                  exit;
               end if;
            end loop;
            if not Duplicate then
               List.Items (Kept) := List.Items (I);
               Kept := Kept + 1;
            end if;
         end;
      end loop;
      List.Count := Kept;
   end Suppress;

   ---------------------------------------------------------------------
   --  Sampling the zones
   ---------------------------------------------------------------------

   function Steps_For
     (Span, Step : Long_Float;
      Limit      : Positive) return Natural
   with Pre  => Span >= 0.0 and then Span <= 2.0E4
                and then Step > 0.0 and then Step <= 16.0
                and then Limit <= 2 ** 20,
        Post => Steps_For'Result <= Limit;
   --  Ceiling (Span / Step), at most Limit.

   function Steps_For
     (Span, Step : Long_Float;
      Limit      : Positive) return Natural
   is
      Ratio : Long_Float;
      Fits  : Boolean;
   begin
      N.Ratio_Within (Span, Step, Long_Float (Limit), Ratio, Fits);
      if not Fits then
         return Limit;
      end if;
      return Natural'Min (Natural (Long_Float'Ceiling (Ratio)), Limit);
   end Steps_For;

   function Sample
     (Low, Span : Long_Float;
      A, Count  : Natural) return Long_Float
   is (Low + N.Times_Unit (Span, N.Unit_Ratio (Long_Float (A),
                                                Long_Float (Count))))
   with Pre  => Count >= 1 and then A <= Count
                and then abs Low <= 1.0E4
                and then Span >= 0.0 and then Span <= 2.0E4,
        Post => abs Sample'Result <= 3.0E4;
   --  Low + Span * A / Count.

   type Sampling is record
      Count : Positive := 1;
      Low   : Long_Float range -1.0E4 .. 1.0E4 := 0.0;
      Span  : Long_Float range 0.0 .. 2.0E4 := 0.0;
      Steps : Positive := 1;
   end record;
   --  Count values Low + Span * K / Steps, K = 0 .. Count - 1.

   function Angle_Sampling
     (Zone : Ks_PM_Align_Zone_Angle;
      Step : Long_Float) return Sampling
   with Pre => Valid_Angle_Zone (Zone) and then Step > 0.0
               and then Step <= 1.0;
   --  The angles of the coarse search: Nominal alone; the whole circle in
   --  equal steps of at most Step (at most Max_Angle_Steps of them); or
   --  [Low, High] in equal steps of at most Step, both ends included.

   function Angle_Sampling
     (Zone : Ks_PM_Align_Zone_Angle;
      Step : Long_Float) return Sampling
   is
   begin
      if Zone.Configuration /= Zone_Low_High then
         return (Count => 1, Low => Zone.Nominal, Span => 0.0, Steps => 1);
      elsif Zone.High - Zone.Low >= P.Two_Pi then
         declare
            K : constant Natural :=
              Steps_For (P.Two_Pi, Step, Max_Angle_Steps);
         begin
            return (Count => Natural'Max (K, 1), Low => Zone.Low,
                    Span => P.Two_Pi, Steps => Natural'Max (K, 1));
         end;
      else
         declare
            Span : constant Long_Float := Zone.High - Zone.Low;
            K    : constant Natural :=
              Steps_For (Span, Step, Max_Angle_Steps - 1);
         begin
            return (Count => K + 1, Low => Zone.Low, Span => Span,
                    Steps => Natural'Max (K, 1));
         end;
      end if;
   end Angle_Sampling;

   function Scale_Sampling
     (Zone : Ks_PM_Align_Zone_Scale;
      Step : Long_Float) return Sampling
   with Pre => Valid_Scale_Zone (Zone) and then Step > 0.0
               and then Step <= 1.0;
   --  The scales of the coarse search: Nominal alone, or [Low, High] in
   --  equal steps of at most Low * Step, both ends included (at most
   --  Max_Scale_Steps values).

   function Scale_Sampling
     (Zone : Ks_PM_Align_Zone_Scale;
      Step : Long_Float) return Sampling
   is
   begin
      if Zone.Configuration /= Zone_Low_High then
         return (Count => 1, Low => Zone.Nominal, Span => 0.0, Steps => 1);
      end if;
      declare
         Span       : constant Long_Float := Zone.High - Zone.Low;
         Scale_Step : constant Long_Float :=
           Long_Float'Min
             (Long_Float'Max (N.Times_Small (Step, Zone.Low / 4.0) * 4.0,
                              1.0E-6),
              16.0);
         K          : constant Natural :=
           Steps_For (Span, Scale_Step, Max_Scale_Steps - 1);
      begin
         return (Count => K + 1, Low => Zone.Low, Span => Span,
                 Steps => Natural'Max (K, 1));
      end;
   end Scale_Sampling;

   function Value_At (S : Sampling; K : Natural) return Long_Float is
     (Sample (S.Low, S.Span, Natural'Min (K, S.Steps), S.Steps))
   with Post => abs Value_At'Result <= 3.0E4;

   ---------------------------------------------------------------------
   --  The coarse search
   ---------------------------------------------------------------------

   procedure Fill_Scores
     (Q               : P.Quantised_Model;
      L               : PY.Level_Data;
      Buffer          : KM.Ks_Real_Image;
      Stop            : Int64;
      Ignore_Polarity : Boolean)
   with Pre  => PY.Has_Directions (L) and then KM.Has_Pixels (Buffer)
                and then Buffer.Width = L.DX.Width
                and then Buffer.Height = L.DX.Height,
        Post => KM.Has_Pixels (Buffer)
                and then Buffer.Width = L.DX.Width
                and then Buffer.Height = L.DX.Height;
   --  Buffer (Y, X) := the score of the centroid at (X, Y) when its sum
   --  reaches Stop, -1 otherwise.

   procedure Fill_Scores
     (Q               : P.Quantised_Model;
      L               : PY.Level_Data;
      Buffer          : KM.Ks_Real_Image;
      Stop            : Int64;
      Ignore_Polarity : Boolean)
   is
   begin
      for Y in Buffer.Pixels'Range (1) loop
         pragma Loop_Invariant
           (KM.Has_Pixels (Buffer)
            and then Buffer.Width = L.DX.Width
            and then Buffer.Height = L.DX.Height);
         for X in Buffer.Pixels'Range (2) loop
            pragma Loop_Invariant
              (KM.Has_Pixels (Buffer)
               and then Buffer.Width = L.DX.Width
               and then Buffer.Height = L.DX.Height);
            declare
               Sum : constant Int64 :=
                 Grid_Score (Q, L, Int64 (X), Int64 (Y), Ignore_Polarity,
                             Stop);
            begin
               if Sum >= Stop then
                  Buffer.Pixels (Y, X) := Score_Of (Sum, Q.Count);
               else
                  Buffer.Pixels (Y, X) := -1.0;
               end if;
            end;
         end loop;
      end loop;
   end Fill_Scores;

   function Read_Score
     (Buffer : access constant KM.Ks_Real_Image_Data;
      X, Y   : Natural) return Long_Float
   is (N.Clamp (Buffer.Pixels (Y, X), 1.0))
   with Pre => KM.Valid_Image (Buffer)
               and then Y <= Buffer.Pixels'Last (1)
               and then X <= Buffer.Pixels'Last (2);
   --  A score of the buffer (every value is a score in [0, 1] or -1, so
   --  the limit never acts).

   function Is_Maximum
     (Buffer : access constant KM.Ks_Real_Image_Data;
      X, Y   : Natural) return Boolean
   with Pre => KM.Valid_Image (Buffer)
               and then Y <= Buffer.Pixels'Last (1)
               and then X <= Buffer.Pixels'Last (2);
   --  The score at (X, Y) is above those of its neighbours before it in
   --  raster order and at least those after it.

   function Is_Maximum
     (Buffer : access constant KM.Ks_Real_Image_Data;
      X, Y   : Natural) return Boolean
   is
      V : constant Long_Float := Read_Score (Buffer, X, Y);
   begin
      for DY in -1 .. 1 loop
         pragma Loop_Invariant (V <= 1.0);
         for DX in -1 .. 1 loop
            pragma Loop_Invariant (V <= 1.0);
            if (DX /= 0 or else DY /= 0)
              and then X + DX >= 0 and then Y + DY >= 0
              and then X + DX <= Buffer.Pixels'Last (2)
              and then Y + DY <= Buffer.Pixels'Last (1)
            then
               declare
                  W : constant Long_Float :=
                    Read_Score (Buffer, X + DX, Y + DY);
               begin
                  if DY < 0 or else (DY = 0 and then DX < 0) then
                     if W >= V then
                        return False;
                     end if;
                  elsif W > V then
                     return False;
                  end if;
               end;
            end if;
         end loop;
      end loop;
      return True;
   end Is_Maximum;

   procedure Collect_Maxima
     (Buffer    : access constant KM.Ks_Real_Image_Data;
      Theta     : P.Zone_Angle_Value;
      Scale     : P.Scale_Value;
      Threshold : P.Fraction;
      List      : in out Candidate_List)
   with Pre => KM.Valid_Image (Buffer);
   --  Inserts the local maxima of Buffer that reach Threshold.

   procedure Collect_Maxima
     (Buffer    : access constant KM.Ks_Real_Image_Data;
      Theta     : P.Zone_Angle_Value;
      Scale     : P.Scale_Value;
      Threshold : P.Fraction;
      List      : in out Candidate_List)
   is
   begin
      for Y in Buffer.Pixels'Range (1) loop
         for X in Buffer.Pixels'Range (2) loop
            declare
               V : constant Long_Float := Read_Score (Buffer, X, Y);
            begin
               if V >= Threshold and then V >= 0.0
                 and then Is_Maximum (Buffer, X, Y)
               then
                  Insert (List, (X     => Long_Float (X),
                                 Y     => Long_Float (Y),
                                 Theta => Theta,
                                 Scale => Scale,
                                 Score => V,
                                 Level => 0));
               end if;
            end;
         end loop;
      end loop;
   end Collect_Maxima;

   function Largest_Scale (Zone : Ks_PM_Align_Zone_Scale) return P.Scale_Value
   is (if Zone.Configuration = Zone_Low_High then Zone.High else Zone.Nominal)
   with Pre => Valid_Scale_Zone (Zone);

   procedure Coarse
     (Pattern   : access constant Ks_PM_Align_Pattern_Data;
      F         : P.Frame;
      Pyr       : PY.Pyramid;
      Params    : Ks_PM_Align_Run_Params;
      Threshold : P.Fraction;
      List      : out Candidate_List;
      Status    : out Ks_Status)
   is
      K      : constant Level_Index := Pattern.Coarsest;
      Step   : constant Long_Float :=
        Angle_Step (F, Largest_Scale (Params.Zone_Scale), K);
      Angles : constant Sampling :=
        Angle_Sampling (Params.Zone_Angle, Step);
      Scales : constant Sampling :=
        Scale_Sampling (Params.Zone_Scale, Step);
      Buffer : KM.Ks_Real_Image;
      Q      : P.Quantised_Model;
   begin
      List := (Count => 0, Items => [others => (others => <>)]);
      if K >= Pyr.Count or else not PY.Has_Directions (Pyr.Levels (K)) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "PMAlign: inconsistent pyramid");
         return;
      end if;
      KM.Create (Pyr.Levels (K).DX.Width, Pyr.Levels (K).DX.Height, -1.0,
                 Buffer, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for A in 0 .. Angles.Count - 1 loop
         pragma Loop_Invariant
           (KM.Has_Pixels (Buffer)
            and then Buffer.Width = Pyr.Levels (K).DX.Width
            and then Buffer.Height = Pyr.Levels (K).DX.Height);
         declare
            Theta : constant P.Zone_Angle_Value :=
              P.Angle_In_Zone (Value_At (Angles, A), Params.Zone_Angle);
            R     : constant P.Rotation := P.Rotation_Of (Theta);
         begin
            for J in 0 .. Scales.Count - 1 loop
               pragma Loop_Invariant
                 (KM.Has_Pixels (Buffer)
                  and then Buffer.Width = Pyr.Levels (K).DX.Width
                  and then Buffer.Height = Pyr.Levels (K).DX.Height);
               declare
                  Scale : constant P.Scale_Value :=
                    P.Scale_In_Zone (Value_At (Scales, J), Params.Zone_Scale);
               begin
                  P.Quantise (Pattern.Levels (K), F, K, R, Scale, Q);
                  Fill_Scores (Q, Pyr.Levels (K), Buffer,
                               Stop_Of (Threshold, Q.Count),
                               F.Ignore_Polarity);
                  Collect_Maxima (Buffer, Theta, Scale, Threshold, List);
               end;
            end loop;
         end;
      end loop;
      --  Freed in place (as ks_real_image_destroy does).
      Free (Buffer.Pixels);
      Free (Buffer);
      Sort (List);
      Suppress (List, 1.5, 1.5 * Step,
                (if Params.Zone_Scale.Configuration = Zone_Low_High
                 then 1.5 * Step * Params.Zone_Scale.High else 0.0));
   end Coarse;

   ---------------------------------------------------------------------
   --  Tracking
   ---------------------------------------------------------------------

   function Grid_Position (X : Long_Float) return Int64 is
     (Int64 (Long_Float'Floor (N.Clamp (X, 2.0 ** 32))))
   with Post => abs Grid_Position'Result <= 2 ** 32;
   --  The pixel at or left of X, limited to 2**32 (positions in an image
   --  are below 2**31).

   procedure Try_Positions
     (Q      : P.Quantised_Model;
      L      : PY.Level_Data;
      XC, YC : Int64;
      Theta  : P.Zone_Angle_Value;
      Scale  : P.Scale_Value;
      Ignore : Boolean;
      Best   : in out Candidate)
   with Pre => PY.Has_Directions (L)
               and then XC in -2 ** 32 .. 2 ** 32
               and then YC in -2 ** 32 .. 2 ** 32;
   --  Scores the pose (Theta, Scale) of Q with the centroid at the nine
   --  pixels around (XC, YC); Best becomes the best of them when it is
   --  better than Best.

   procedure Try_Positions
     (Q      : P.Quantised_Model;
      L      : PY.Level_Data;
      XC, YC : Int64;
      Theta  : P.Zone_Angle_Value;
      Scale  : P.Scale_Value;
      Ignore : Boolean;
      Best   : in out Candidate) is
   begin
      --  (The loop invariants keep the provers from unrolling the
      --  loops.)
      for DY in Int64 range -1 .. 1 loop
         pragma Loop_Invariant (Best.Score >= 0.0);
         for DX in Int64 range -1 .. 1 loop
            pragma Loop_Invariant (Best.Score >= 0.0);
            declare
               Score : constant P.Fraction :=
                 Score_Of (Grid_Score (Q, L, XC + DX, YC + DY, Ignore,
                                       Int64'First),
                           Q.Count);
            begin
               if Score > Best.Score then
                  Best := (X     => Long_Float (XC + DX),
                           Y     => Long_Float (YC + DY),
                           Theta => Theta,
                           Scale => Scale,
                           Score => Score,
                           Level => Best.Level);
               end if;
            end;
         end loop;
      end loop;
   end Try_Positions;

   procedure Climb
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      F       : P.Frame;
      L       : PY.Level_Data;
      Level   : Level_Index;
      Params  : Ks_PM_Align_Run_Params;
      C       : in out Candidate)
   with Pre => Trained_Pattern (Pattern) and then PY.Has_Directions (L)
               and then Valid_Run_Params (Params);
   --  Moves C (already at Level) to the best of its neighbours (one pixel,
   --  one angle step and one scale step of Level) until none is better,
   --  at most Climb_Iterations times; C.Score becomes its score at Level.

   procedure Climb
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      F       : P.Frame;
      L       : PY.Level_Data;
      Level   : Level_Index;
      Params  : Ks_PM_Align_Run_Params;
      C       : in out Candidate)
   is
      Radius : constant P.Pixel_Radius :=
        P.Pixel_Radius_Of (F, C.Scale, Level);
      DA     : constant Long_Float range 0.0 .. 1.0 :=
        (if Params.Zone_Angle.Configuration = Zone_Low_High
         then Long_Float'Max (0.0, N.Unit_Ratio (1.0, Radius)) else 0.0);
      DS     : constant Long_Float range 0.0 .. 16.0 :=
        (if Params.Zone_Scale.Configuration = Zone_Low_High
         then Long_Float'Max
                (0.0,
                 N.Times_Small (N.Unit_Ratio (1.0, Radius), C.Scale / 4.0)
                 * 4.0)
         else 0.0);
      Q      : P.Quantised_Model;
      Best   : Candidate := C;
      Centre : Candidate;
      Theta  : P.Zone_Angle_Value;
      Scale  : P.Scale_Value;
   begin
      Best.Score := 0.0;
      --  (The loop invariants keep the provers from unrolling the
      --  loops.)
      for Iteration in 1 .. Climb_Iterations loop
         pragma Loop_Invariant (Best.Score >= 0.0);
         Centre := Best;
         for DAI in -1 .. 1 loop
            pragma Loop_Invariant (Best.Score >= 0.0);
            for DSI in -1 .. 1 loop
               pragma Loop_Invariant (Best.Score >= 0.0);
               if (DAI = 0 or else DA > 0.0)
                 and then (DSI = 0 or else DS > 0.0)
               then
                  Theta := P.Angle_In_Zone
                    (Centre.Theta + N.Times_Unit (Long_Float (DAI), DA),
                     Params.Zone_Angle);
                  Scale := P.Scale_In_Zone
                    (Centre.Scale + N.Times_Small (DS, Long_Float (DSI)),
                     Params.Zone_Scale);
                  P.Quantise (Pattern.Levels (Level), F, Level,
                              P.Rotation_Of (Theta), Scale, Q);
                  Try_Positions (Q, L, Grid_Position (Centre.X),
                                 Grid_Position (Centre.Y), Theta, Scale,
                                 F.Ignore_Polarity, Best);
               end if;
            end loop;
         end loop;
         exit when Best.X = Centre.X and then Best.Y = Centre.Y
           and then Best.Theta = Centre.Theta
           and then Best.Scale = Centre.Scale;
      end loop;
      C := Best;
   end Climb;

   procedure Track
     (Pattern   : access constant Ks_PM_Align_Pattern_Data;
      F         : P.Frame;
      Pyr       : PY.Pyramid;
      Params    : Ks_PM_Align_Run_Params;
      Threshold : P.Fraction;
      Limit     : Positive;
      List      : in out Candidate_List)
   is
      Last : constant Natural := Natural'Min (List.Count, Limit);
      Kept : Natural range 0 .. Max_Candidates := 0;
   begin
      for I in 0 .. Last - 1 loop
         pragma Loop_Invariant (Kept <= I);
         declare
            C  : Candidate := List.Items (I);
            Ok : Boolean := True;
            Adaptive : constant Boolean :=
              Pattern.Params.Grain_Limit_Auto_Select = True_Value;
         begin
            C.Level := Pattern.Coarsest;
            for K in reverse Pattern.Finest .. Pattern.Coarsest - 1 loop
               if K < Pyr.Count and then PY.Has_Directions (Pyr.Levels (K))
               then
                  declare
                     Next : Candidate := C;
                  begin
                     --  From the pixels of level K + 1 to those of level K:
                     --  x -> 2 x + 1/2.
                     Next.X := N.Clamp (2.0 * C.X + 0.5, P.Max_Position);
                     Next.Y := N.Clamp (2.0 * C.Y + 0.5, P.Max_Position);
                     Climb (Pattern, F, Pyr.Levels (K), K, Params, Next);
                     Next.Level := K;
                     --  With the automatic grain, a candidate that misses
                     --  the threshold here stops at the level above (see
                     --  Track's spec).
                     exit when Adaptive and then Next.Score < Threshold
                       and then C.Score >= Threshold;
                     C := Next;
                  end;
               else
                  Ok := False;
               end if;
               if C.Score < Threshold then
                  Ok := False;
               end if;
               exit when not Ok;
            end loop;
            if Ok then
               List.Items (Kept) := C;
               Kept := Kept + 1;
            end if;
         end;
      end loop;
      List.Count := Kept;
      Sort (List);
      declare
         Step : constant Long_Float :=
           Angle_Step (F, Largest_Scale (Params.Zone_Scale), Pattern.Finest);
      begin
         Suppress (List, 1.5 * P.Level_Size (Pattern.Finest), 1.5 * Step,
                   (if Params.Zone_Scale.Configuration = Zone_Low_High
                    then 1.5 * Step * Params.Zone_Scale.High else 0.0));
      end;
   end Track;

   ---------------------------------------------------------------------
   --  PatQuick
   ---------------------------------------------------------------------

   procedure Interpolate
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      F       : P.Frame;
      Pyr     : PY.Pyramid;
      Params  : Ks_PM_Align_Run_Params;
      C       : in out Candidate)
   is
      K  : constant Level_Index := C.Level;
      Q  : P.Quantised_Model;
      XC : constant Int64 := Grid_Position (C.X);
      YC : constant Int64 := Grid_Position (C.Y);
   begin
      if K >= Pyr.Count or else not PY.Has_Directions (Pyr.Levels (K)) then
         return;
      end if;
      P.Quantise (Pattern.Levels (K), F, K, P.Rotation_Of (C.Theta), C.Scale,
                  Q);
      declare
         L      : PY.Level_Data renames Pyr.Levels (K);
         Ignore : constant Boolean := F.Ignore_Polarity;
         Centre : constant P.Fraction :=
           Score_Of (Grid_Score (Q, L, XC, YC, Ignore, Int64'First), Q.Count);
         DX     : constant Long_Float :=
           PY.Parabola_Peak
             (Score_Of (Grid_Score (Q, L, XC - 1, YC, Ignore, Int64'First),
                        Q.Count),
              Centre,
              Score_Of (Grid_Score (Q, L, XC + 1, YC, Ignore, Int64'First),
                        Q.Count));
         DY     : constant Long_Float :=
           PY.Parabola_Peak
             (Score_Of (Grid_Score (Q, L, XC, YC - 1, Ignore, Int64'First),
                        Q.Count),
              Centre,
              Score_Of (Grid_Score (Q, L, XC, YC + 1, Ignore, Int64'First),
                        Q.Count));
      begin
         C.X := N.Clamp (Long_Float (XC) + DX, P.Max_Position);
         C.Y := N.Clamp (Long_Float (YC) + DY, P.Max_Position);
         C.Score := Centre;
         if Params.Zone_Angle.Configuration = Zone_Low_High then
            declare
               DA    : constant Long_Float := Angle_Step (F, C.Scale, K);
               Minus : P.Fraction;
               Plus  : P.Fraction;
            begin
               P.Quantise (Pattern.Levels (K), F, K,
                           P.Rotation_Of (C.Theta - DA), C.Scale, Q);
               Minus := Score_Of
                 (Grid_Score (Q, L, XC, YC, Ignore, Int64'First), Q.Count);
               P.Quantise (Pattern.Levels (K), F, K,
                           P.Rotation_Of (C.Theta + DA), C.Scale, Q);
               Plus := Score_Of
                 (Grid_Score (Q, L, XC, YC, Ignore, Int64'First), Q.Count);
               C.Theta :=
                 P.Angle_In_Zone
                   (C.Theta + PY.Parabola_Peak (Minus, Centre, Plus) * DA,
                    Params.Zone_Angle);
            end;
         end if;
      end;
   end Interpolate;

end AMV.Kernels.PM_Align.Search;
