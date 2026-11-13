pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;
with Interfaces;

with AMV.Kernels.Numerics;

package body AMV.Kernels.PM_Align.Refinement with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package N renames AMV.Kernels.Numerics;

   use type Interfaces.Unsigned_8;

   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Grey_8_Matrix, KI.Grey_8_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Ks_Image_8_Grey_Data, KI.Ks_Image_8_Grey);

   Max_Step : constant := 2.0;
   --  The largest change of one unknown per iteration (pixels, or pixels
   --  at the model's radius).

   Sum_Limit : constant := 2.0 ** 24;
   --  The limit of the sums of the normal equations: at most Max_Features
   --  terms of at most 16 (products of two columns limited to 4), far
   --  below it.

   Cos_Match : constant := 0.707_106_781_186_547;
   --  cos (Max_Match_Angle).

   subtype Sum_Value is Long_Float range -Sum_Limit .. Sum_Limit;
   subtype Column is Long_Float range -4.0 .. 4.0;
   subtype Distance is Long_Float range -2.5 .. 2.5;
   subtype Magnitude_Value is Long_Float range 0.0 .. 1024.0;

   ---------------------------------------------------------------------
   --  Edges along a normal
   ---------------------------------------------------------------------

   type Profile is array (-2 .. 2) of Long_Float;

   procedure Find_Edge
     (L            : PY.Level_Data;
      PX, PY_Point : Long_Float;
      UX, UY       : P.Unit;
      Reach        : Positive;
      Ignore       : Boolean;
      Min_Contrast : Long_Float;
      Found        : out Boolean;
      T            : out Distance;
      Cosine       : out P.Fraction;
      Magnitude    : out Magnitude_Value)
   with Pre => PY.Usable (L) and then Reach <= 2
               and then abs PX <= 2.0 ** 32
               and then abs PY_Point <= 2.0 ** 32;
   --  Samples the gradient projected on (UX, UY) (its magnitude with
   --  Ignore) at the points (PX, PY_Point) + K (UX, UY), K = -Reach ..
   --  Reach. Found when the largest sample lies strictly inside that range
   --  and reaches Min_Contrast (and is positive); T is then the vertex of
   --  the parabola through it and its neighbours (the edge's distance
   --  along the normal), Cosine the sample over the gradient's magnitude
   --  there, Magnitude that magnitude.

   procedure Find_Edge
     (L            : PY.Level_Data;
      PX, PY_Point : Long_Float;
      UX, UY       : P.Unit;
      Reach        : Positive;
      Ignore       : Boolean;
      Min_Contrast : Long_Float;
      Found        : out Boolean;
      T            : out Distance;
      Cosine       : out P.Fraction;
      Magnitude    : out Magnitude_Value)
   is
      H    : Profile := [others => 0.0];
      Best : Integer range -2 .. 2 := -Reach;
   begin
      Found := False;
      T := 0.0;
      Cosine := 0.0;
      Magnitude := 0.0;
      for K in -Reach .. Reach loop
         declare
            V : constant Long_Float :=
              PY.Projected (L, PX, PY_Point, UX, UY, Long_Float (K));
         begin
            H (K) := (if Ignore then abs V else V);
         end;
         pragma Loop_Invariant
           (for all J in -2 .. K => abs H (J) <= PY.Max_Projection);
      end loop;
      for K in -Reach + 1 .. Reach loop
         if H (K) > H (Best) then
            Best := K;
         end if;
      end loop;
      if Best <= -Reach or else Best >= Reach
        or else H (Best) <= 0.0 or else H (Best) < Min_Contrast
      then
         return;
      end if;
      T := Long_Float (Best)
        + PY.Parabola_Peak (H (Best - 1), H (Best), H (Best + 1));
      declare
         SX : constant P.Position := PX + N.Times_Unit (Long_Float (Best), UX);
         SY : constant P.Position :=
           PY_Point + N.Times_Unit (Long_Float (Best), UY);
         M  : constant Long_Float :=
           N.Hypot (PY.Bilinear (L.GX, SX, SY), PY.Bilinear (L.GY, SX, SY));
      begin
         Magnitude := Long_Float'Min (M, 1024.0);
         if M > 0.0 then
            Cosine := N.Clamp_Unit
              (if H (Best) <= M then N.Unit_Ratio (H (Best), M) else 1.0);
         end if;
      end;
      Found := True;
   end Find_Edge;

   ---------------------------------------------------------------------
   --  The normal equations
   ---------------------------------------------------------------------

   type Vector is array (0 .. 3) of Sum_Value;
   type Matrix is array (0 .. 3, 0 .. 3) of Sum_Value;
   type Columns is array (0 .. 3) of Column;
   type Flags is array (0 .. 3) of Boolean;

   function Added (Sum : Sum_Value; Term : Long_Float) return Sum_Value is
     (N.Clamp (Sum + Term, Sum_Limit))
   with Pre => abs Term <= 16.0;
   --  Sum + Term (the limit never acts, see Sum_Limit).

   procedure Accumulate
     (M : in out Matrix;
      B : in out Vector;
      C : Columns;
      T : Distance);
   --  Adds the row C with right-hand side T to the normal equations.

   procedure Accumulate
     (M : in out Matrix;
      B : in out Vector;
      C : Columns;
      T : Distance) is
   begin
      for I in 0 .. 3 loop
         B (I) := Added (B (I), N.Times_Small (T, C (I)));
         for J in 0 .. 3 loop
            M (I, J) := Added (M (I, J), N.Times_Small (C (I), C (J)));
         end loop;
      end loop;
   end Accumulate;

   function Step_Of (R, Den : Long_Float) return Long_Float is
     (if abs R >= Max_Step * Den then (if R > 0.0 then Max_Step else -Max_Step)
      else Max_Step * N.Unit_Ratio (R, Max_Step * Den))
   with Pre  => Den >= 1.0E-6 and then Den <= 4.0 * Sum_Limit,
        Post => abs Step_Of'Result <= Max_Step;
   --  R / Den limited to Max_Step.

   procedure Solve
     (M    : Matrix;
      B    : Vector;
      Free : Flags;
      D    : out Vector)
   with Post => (for all K in 0 .. 3 => abs D (K) <= Max_Step);
   --  Gauss-Seidel sweeps on (M + Damping I) D = B for the free unknowns
   --  (the others stay 0), each step limited to Max_Step. M is a sum of
   --  outer products, so its diagonal is not negative and the damped
   --  system is positive definite: the sweeps converge.

   procedure Solve
     (M    : Matrix;
      B    : Vector;
      Free : Flags;
      D    : out Vector)
   is
      Damping : constant Long_Float :=
        1.0E-6 + 1.0E-3 * (abs M (0, 0) + abs M (1, 1)) / 2.0;
   begin
      D := [others => 0.0];
      for Sweep in 1 .. 40 loop
         pragma Loop_Invariant
           (for all K in 0 .. 3 => abs D (K) <= Max_Step);
         for K in 0 .. 3 loop
            pragma Loop_Invariant
              (for all J in 0 .. 3 => abs D (J) <= Max_Step);
            if Free (K) then
               declare
                  R : Long_Float := B (K);
               begin
                  for J in 0 .. 3 loop
                     if J /= K then
                        R := R - N.Mul_Within (M (K, J), D (J), Sum_Limit,
                                               Max_Step);
                     end if;
                     pragma Loop_Invariant
                       (abs R <= Sum_Limit + Long_Float (J + 1) * Sum_Limit
                                               * Max_Step);
                  end loop;
                  D (K) := Step_Of
                    (R, Long_Float'Max (M (K, K), 0.0) + Damping);
               end;
            end if;
         end loop;
      end loop;
   end Solve;

   procedure Normal_Equations
     (Model  : Model_Level;
      F      : P.Frame;
      L      : PY.Level_Data;
      Level  : Level_Index;
      Params : Ks_PM_Align_Run_Params;
      X, Y   : P.Position;
      Theta  : P.Zone_Angle_Value;
      Scale  : P.Scale_Value;
      Reach  : Positive;
      M      : out Matrix;
      B      : out Vector)
   with Pre => PY.Usable (L) and then Reach <= 2
               and then Valid_Run_Params (Params);
   --  The normal equations of the pose: one row per feature with an edge
   --  along its normal (Find_Edge with Reach), the unknowns the moves of
   --  the centroid along x and y (pixels), the rotation times the radius
   --  and the change of scale over the scale times the radius.

   procedure Normal_Equations
     (Model  : Model_Level;
      F      : P.Frame;
      L      : PY.Level_Data;
      Level  : Level_Index;
      Params : Ks_PM_Align_Run_Params;
      X, Y   : P.Position;
      Theta  : P.Zone_Angle_Value;
      Scale  : P.Scale_Value;
      Reach  : Positive;
      M      : out Matrix;
      B      : out Vector)
   is
      R      : constant P.Rotation := P.Rotation_Of (Theta);
      RQ     : constant P.Rotation := P.Rotation_Of (Theta + P.Pi / 2.0);
      Radius : constant P.Pixel_Radius := P.Pixel_Radius_Of (F, Scale, Level);
   begin
      M := [others => [others => 0.0]];
      B := [others => 0.0];
      for I in 0 .. Model.Count - 1 loop
         declare
            RX : constant P.Relative := Model.Features (I).X - F.Centroid_X;
            RY : constant P.Relative := Model.Features (I).Y - F.Centroid_Y;
            DX, DY       : P.Offset;
            AX, AY       : P.Offset;
            UX, UY       : P.Unit;
            Found            : Boolean;
            T                : Distance;
            Unused_Cosine    : P.Fraction;
            Unused_Magnitude : Magnitude_Value;
         begin
            P.Map_Offset (F, R, Scale, Level, RX, RY, DX, DY);
            P.Map_Normal (F, R, Model.Features (I).NX, Model.Features (I).NY,
                          UX, UY);
            if (UX /= 0.0 or else UY /= 0.0)
              and then abs (X + DX) <= 2.0 ** 32
              and then abs (Y + DY) <= 2.0 ** 32
            then
               --  (A feature that far is outside every image.)
               Find_Edge (L, X + DX, Y + DY, UX, UY, Reach,
                          F.Ignore_Polarity, Params.Contrast_Threshold,
                          Found, T, Unused_Cosine, Unused_Magnitude);
               if Found then
                  P.Map_Offset (F, RQ, Scale, Level, RX, RY, AX, AY);
                  Accumulate
                    (M, B,
                     [0 => UX,
                      1 => UY,
                      2 => N.Clamp ((N.Times_Unit (AX, UX)
                                     + N.Times_Unit (AY, UY)) / Radius, 4.0),
                      3 => N.Clamp ((N.Times_Unit (DX, UX)
                                     + N.Times_Unit (DY, UY)) / Radius,
                                    4.0)],
                     T);
               end if;
            end if;
         end;
      end loop;
   end Normal_Equations;

   function Over_Radius (V : Long_Float; R : P.Pixel_Radius)
      return Long_Float
   is (2.0 * N.Unit_Ratio (V / 2.0, R))
   with Pre  => abs V <= Max_Step,
        Post => abs Over_Radius'Result <= Max_Step;
   --  V / R (R >= 1).

   procedure Refine
     (Model  : Model_Level;
      F      : P.Frame;
      L      : PY.Level_Data;
      Level  : Level_Index;
      Params : Ks_PM_Align_Run_Params;
      X, Y   : in out P.Position;
      Theta  : in out P.Zone_Angle_Value;
      Scale  : in out P.Scale_Value)
   is
      Free : constant Flags :=
        [0 | 1 => True,
         2     => Params.Zone_Angle.Configuration = Zone_Low_High,
         3     => Params.Zone_Scale.Configuration = Zone_Low_High];
      M    : Matrix;
      B    : Vector;
      D    : Vector;
   begin
      for Iteration in 1 .. Refine_Iterations loop
         Normal_Equations (Model, F, L, Level, Params, X, Y, Theta, Scale,
                           (if Iteration <= 2 then 2 else 1), M, B);
         Solve (M, B, Free, D);
         declare
            Radius : constant P.Pixel_Radius :=
              P.Pixel_Radius_Of (F, Scale, Level);
         begin
            X := N.Clamp (X + D (0), P.Max_Position);
            Y := N.Clamp (Y + D (1), P.Max_Position);
            if Free (2) then
               Theta := P.Angle_In_Zone (Theta + Over_Radius (D (2), Radius),
                                         Params.Zone_Angle);
            end if;
            if Free (3) then
               Scale := P.Scale_In_Zone
                 (Scale
                  + N.Times_Small (Over_Radius (D (3), Radius), Scale / 4.0)
                    * 4.0,
                  Params.Zone_Scale);
            end if;
         end;
         exit when abs D (0) < 1.0E-4 and then abs D (1) < 1.0E-4
           and then abs D (2) < 1.0E-4 and then abs D (3) < 1.0E-4;
      end loop;
   end Refine;

   ---------------------------------------------------------------------
   --  Clutter
   ---------------------------------------------------------------------

   function Round_Index (X : Long_Float) return Int64
   with Post => abs Round_Index'Result <= 2 ** 41;
   --  The integer nearest to X (X within 2**40 in practice).

   function Round_Index (X : Long_Float) return Int64 is
      C : constant Long_Float := N.Clamp (X, 2.0 ** 40);
   begin
      return Int64 (C);
   end Round_Index;

   function Fraction_Of (Part, Whole : Natural) return P.Fraction
   with Pre => Whole >= 1;
   --  Part / Whole, limited to [0, 1].

   function Fraction_Of (Part, Whole : Natural) return P.Fraction is
      Result : Long_Float;
      Fits   : Boolean;
   begin
      N.Ratio_Within (Long_Float (Part), Long_Float (Whole), 1.0, Result,
                      Fits);
      return (if Fits then Result else 1.0);
   end Fraction_Of;

   function In_Parallelogram
     (VX, VY, E1X, E1Y, E2X, E2Y, Det : Long_Float) return Boolean
   with Pre => abs VX <= 2.0 ** 35 and then abs VY <= 2.0 ** 35
               and then abs E1X <= 2.0 ** 22 and then abs E1Y <= 2.0 ** 22
               and then abs E2X <= 2.0 ** 22 and then abs E2Y <= 2.0 ** 22;
   --  V = A E1 + B E2 with A and B in [0, 1] (Det = cross (E1, E2), not 0
   --  for a True result): the point O + V lies in the parallelogram of
   --  corner O and sides E1, E2.

   function In_Parallelogram
     (VX, VY, E1X, E1Y, E2X, E2Y, Det : Long_Float) return Boolean
   is
      A : constant Long_Float :=
        N.Mul_Within (VX, E2Y, 2.0 ** 35, 2.0 ** 22)
        - N.Mul_Within (VY, E2X, 2.0 ** 35, 2.0 ** 22);
      B : constant Long_Float :=
        N.Mul_Within (E1X, VY, 2.0 ** 22, 2.0 ** 35)
        - N.Mul_Within (E1Y, VX, 2.0 ** 22, 2.0 ** 35);
   begin
      if Det > 0.0 then
         return A >= 0.0 and then A <= Det and then B >= 0.0
           and then B <= Det;
      elsif Det < 0.0 then
         return A <= 0.0 and then A >= Det and then B <= 0.0
           and then B >= Det;
      else
         return False;
      end if;
   end In_Parallelogram;

   type Box is record
      X_Min, X_Max, Y_Min, Y_Max : Int64 := 0;
   end record;

   Edge_Margin : constant := 2;
   --  A feature explains the edge pixels within this many pixels (in x and
   --  in y) of its own pixel, plus the spacing of the model's features
   --  (see Compute_Clutter).

   Max_Margin : constant := Edge_Margin + 225;
   --  Edge_Margin + 1.5 * (Max_Spacing - 1) * Max_Zone_Scale.

   function Offset_Of (Pixel : Int64; Origin : Long_Float) return Long_Float
   with Pre  => Pixel in 0 .. 2 ** 31
                and then Origin in -2.0 ** 34 .. 2.0 ** 34,
        Post => abs Offset_Of'Result <= 2.0 ** 35;
   --  Pixel - Origin, the offset of a pixel from the footprint's corner.

   function Offset_Of (Pixel : Int64; Origin : Long_Float) return Long_Float
   is
   begin
      return Long_Float (Pixel) - Origin;
   end Offset_Of;

   subtype Margin_Value is Int64 range Edge_Margin .. Max_Margin;

   function Clutter_Margin
     (Spacing : Spacing_Value;
      Scale   : P.Scale_Value) return Margin_Value;
   --  Edge_Margin, plus Ceiling (1.5 * (Spacing - 1) * Scale) for a
   --  thinned model (Spacing > 1).

   function Clutter_Margin
     (Spacing : Spacing_Value;
      Scale   : P.Scale_Value) return Margin_Value
   is
      Extra : constant Long_Float range 0.0 .. 225.0 :=
        Long_Float'Ceiling (1.5 * Long_Float (Spacing - 1) * Scale);
   begin
      return Edge_Margin + Int64 (Extra);
   end Clutter_Margin;

   Max_Ignored_Margin : constant := 482;
   --  1 + Ceiling (0.75 * Max_Ignored_Spacing * Max_Zone_Scale).

   subtype Ignored_Margin_Value is Int64 range 1 .. Max_Ignored_Margin;

   function Ignored_Margin
     (Spacing : Ignored_Spacing_Value;
      Scale   : P.Scale_Value) return Ignored_Margin_Value;
   --  1 + Ceiling (0.75 * Spacing * Scale): the square of that half size
   --  around a mapped ignored point covers its cell (Spacing x Spacing
   --  level pixels before the pose, whose half diagonal is about 0.71 *
   --  Spacing), whatever the rotation, and one more pixel for the edges
   --  that the left-out content makes at its border.

   function Ignored_Margin
     (Spacing : Ignored_Spacing_Value;
      Scale   : P.Scale_Value) return Ignored_Margin_Value
   is
      Extra : constant Long_Float range 0.0 .. 481.0 :=
        Long_Float'Ceiling (0.75 * Long_Float (Spacing) * Scale);
   begin
      return 1 + Int64 (Extra);
   end Ignored_Margin;

   Ignored_Mark : constant := 2;
   --  The value of a pixel of the footprint's marks that an ignored point
   --  covers (1: explained by a feature, 0: neither).

   function Largest_In_Box
     (L      : PY.Level_Data;
      Level  : Level_Index;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Area   : PY.Window;
      B      : Box;
      Marks  : access constant KI.Ks_Image_8_Grey_Data) return Long_Float
   with Pre  => PY.Usable (L)
                and then B.X_Min >= 1
                and then B.X_Max <= Int64 (L.GX.Width) - 2
                and then B.Y_Min >= 1
                and then B.Y_Max <= Int64 (L.GX.Height) - 2
                and then B.X_Min <= B.X_Max and then B.Y_Min <= B.Y_Max
                and then KI.Valid_Image (Marks)
                and then Int64 (Marks.Width) = B.X_Max - B.X_Min + 1
                and then Int64 (Marks.Height) = B.Y_Max - B.Y_Min + 1,
        Post => Largest_In_Box'Result >= 0.0
                and then Largest_In_Box'Result <= PY.Max_Magnitude_Squared;
   --  The largest squared gradient magnitude of the pixels of B in the
   --  region that no ignored point covers (0 when there is none).

   function Largest_In_Box
     (L      : PY.Level_Data;
      Level  : Level_Index;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Area   : PY.Window;
      B      : Box;
      Marks  : access constant KI.Ks_Image_8_Grey_Data) return Long_Float
   is
      Largest : Long_Float range 0.0 .. PY.Max_Magnitude_Squared := 0.0;
   begin
      for J in B.Y_Min .. B.Y_Max loop
         for I in B.X_Min .. B.X_Max loop
            if Marks.Pixels (Natural (J - B.Y_Min), Natural (I - B.X_Min))
                 /= Ignored_Mark
              and then PY.Level_Pixel_In_Region
                         (Region, Area, Level, Natural (I), Natural (J))
            then
               Largest := Long_Float'Max
                 (Largest, PY.Magnitude_Squared (L, Natural (I), Natural (J)));
            end if;
         end loop;
      end loop;
      return Largest;
   end Largest_In_Box;

   procedure Compute_Clutter
     (Model     : Model_Level;
      F         : P.Frame;
      L         : PY.Level_Data;
      Level     : Level_Index;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Area      : PY.Window;
      Threshold : Long_Float;
      X, Y      : P.Position;
      R         : P.Rotation;
      Scale     : P.Scale_Value;
      Clutter   : out P.Fraction;
      Status    : out Ks_Status)
   with
     Pre  => PY.Usable (L) and then Threshold >= 0.0
             and then Threshold <= Max_Contrast_Threshold,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory;
   --  The fraction of the edge pixels of Region inside the model's
   --  footprint that lie more than a margin from every mapped feature,
   --  along x and along y (0 when there is none): Edge_Margin, plus
   --  Ceiling (1.5 * (Spacing - 1) * Scale) for a thinned model. An edge
   --  pixel is PY.Is_Edge at the larger of Threshold and
   --  Train_Contrast_Fraction times the largest gradient magnitude in the
   --  footprint's bounding box (and the region), the rule training uses.
   --  The pixels within Ignored_Margin of a mapped ignored point (the part
   --  of the pattern the train image mask leaves out) count neither as
   --  edge pixels nor for that largest magnitude.

   procedure Compute_Clutter
     (Model     : Model_Level;
      F         : P.Frame;
      L         : PY.Level_Data;
      Level     : Level_Index;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Area      : PY.Window;
      Threshold : Long_Float;
      X, Y      : P.Position;
      R         : P.Rotation;
      Scale     : P.Scale_Value;
      Clutter   : out P.Fraction;
      Status    : out Ks_Status)
   is
      W          : constant Int64 := Int64 (L.GX.Width);
      H          : constant Int64 := Int64 (L.GX.Height);
      Min_X, Max_X, Min_Y, Max_Y : P.Relative;
      C0X, C0Y, C1X, C1Y, C3X, C3Y : P.Offset;
      Area_Box   : Box;
      Mask       : KI.Ks_Image_8_Grey;
      Total      : Natural := 0;
      Unexplained : Natural := 0;
      Edge_Threshold : Long_Float;
      Margin     : Margin_Value;
   begin
      Clutter := 0.0;
      Set_Success (Status);
      if Model.Count = 0 or else W < 3 or else H < 3 then
         return;
      end if;

      --  The margin: an edge pixel of the pattern lies within Spacing - 1
      --  pixels (along x and y) of a feature's pixel in training; mapped
      --  by the pose that becomes (Spacing - 1) * Scale * Sqrt (2) at most,
      --  rounded up here as Ceiling (1.5 * (Spacing - 1) * Scale).
      Margin := Clutter_Margin (Model.Spacing, Scale);

      --  The footprint: the bounding box of the features in pattern
      --  coordinates (relative to the centroid), mapped by the pose.
      Min_X := Model.Features (0).X - F.Centroid_X;
      Max_X := Min_X;
      Min_Y := Model.Features (0).Y - F.Centroid_Y;
      Max_Y := Min_Y;
      for I in 1 .. Model.Count - 1 loop
         Min_X := Long_Float'Min (Min_X, Model.Features (I).X - F.Centroid_X);
         Max_X := Long_Float'Max (Max_X, Model.Features (I).X - F.Centroid_X);
         Min_Y := Long_Float'Min (Min_Y, Model.Features (I).Y - F.Centroid_Y);
         Max_Y := Long_Float'Max (Max_Y, Model.Features (I).Y - F.Centroid_Y);
      end loop;
      P.Map_Offset (F, R, Scale, Level, Min_X, Min_Y, C0X, C0Y);
      P.Map_Offset (F, R, Scale, Level, Max_X, Min_Y, C1X, C1Y);
      P.Map_Offset (F, R, Scale, Level, Min_X, Max_Y, C3X, C3Y);
      declare
         subtype Side is Long_Float range -2.0 ** 22 .. 2.0 ** 22;
         subtype Corner is Long_Float range -2.0 ** 34 .. 2.0 ** 34;
         --  The sides of the footprint (differences of two offsets of at
         --  most 2**20) and its corner (a position plus an offset).
         E1X : constant Side := C1X - C0X;
         E1Y : constant Side := C1Y - C0Y;
         E2X : constant Side := C3X - C0X;
         E2Y : constant Side := C3Y - C0Y;
         C2X : constant Long_Float := C1X + E2X;
         C2Y : constant Long_Float := C1Y + E2Y;
         Det : constant Long_Float :=
           N.Mul_Within (E1X, E2Y, 2.0 ** 22, 2.0 ** 22)
           - N.Mul_Within (E1Y, E2X, 2.0 ** 22, 2.0 ** 22);
         OX  : constant Corner := X + C0X;
         OY  : constant Corner := Y + C0Y;
      begin
         if Det = 0.0 then
            return;
         end if;
         Area_Box :=
           (X_Min => Int64'Max
              (1, Round_Index (X + Long_Float'Min
                 (Long_Float'Min (C0X, C1X), Long_Float'Min (C2X, C3X)))
                  - Margin),
            X_Max => Int64'Min
              (W - 2, Round_Index (X + Long_Float'Max
                 (Long_Float'Max (C0X, C1X), Long_Float'Max (C2X, C3X)))
                  + Margin),
            Y_Min => Int64'Max
              (1, Round_Index (Y + Long_Float'Min
                 (Long_Float'Min (C0Y, C1Y), Long_Float'Min (C2Y, C3Y)))
                  - Margin),
            Y_Max => Int64'Min
              (H - 2, Round_Index (Y + Long_Float'Max
                 (Long_Float'Max (C0Y, C1Y), Long_Float'Max (C2Y, C3Y)))
                  + Margin));
         if Area_Box.X_Min > Area_Box.X_Max
           or else Area_Box.Y_Min > Area_Box.Y_Max
         then
            return;
         end if;

         KI.Create (Int32 (Area_Box.X_Max - Area_Box.X_Min + 1),
                    Int32 (Area_Box.Y_Max - Area_Box.Y_Min + 1), 0, Mask,
                    Status);
         if not Succeeded (Status) then
            return;
         end if;

         --  Mark the pixels each mapped feature explains.
         for I in 0 .. Model.Count - 1 loop
            pragma Loop_Invariant
              (KI.Valid_Image (Mask)
               and then Int64 (Mask.Width)
                          = Area_Box.X_Max - Area_Box.X_Min + 1
               and then Int64 (Mask.Height)
                          = Area_Box.Y_Max - Area_Box.Y_Min + 1);
            declare
               DX, DY : P.Offset;
            begin
               P.Map_Offset (F, R, Scale, Level,
                             Model.Features (I).X - F.Centroid_X,
                             Model.Features (I).Y - F.Centroid_Y, DX, DY);
               declare
                  FX : constant Int64 := Round_Index (X + DX);
                  FY : constant Int64 := Round_Index (Y + DY);
               begin
                  for MY in FY - Margin .. FY + Margin loop
                     for MX in FX - Margin .. FX + Margin loop
                        if MX >= Area_Box.X_Min and then MX <= Area_Box.X_Max
                          and then MY >= Area_Box.Y_Min
                          and then MY <= Area_Box.Y_Max
                        then
                           Mask.Pixels (Natural (MY - Area_Box.Y_Min),
                                        Natural (MX - Area_Box.X_Min)) := 1;
                        end if;
                     end loop;
                  end loop;
               end;
            end;
         end loop;

         --  Mark the pixels each mapped ignored point covers.
         declare
            IM : constant Ignored_Margin_Value :=
              Ignored_Margin (Model.Ignored_Spacing, Scale);
         begin
            for I in 0 .. Model.Ignored_Count - 1 loop
               pragma Loop_Invariant
                 (KI.Valid_Image (Mask)
                  and then Int64 (Mask.Width)
                             = Area_Box.X_Max - Area_Box.X_Min + 1
                  and then Int64 (Mask.Height)
                             = Area_Box.Y_Max - Area_Box.Y_Min + 1);
               declare
                  DX, DY : P.Offset;
               begin
                  P.Map_Offset (F, R, Scale, Level,
                                Model.Ignored (I).X - F.Centroid_X,
                                Model.Ignored (I).Y - F.Centroid_Y, DX, DY);
                  declare
                     GX : constant Int64 := Round_Index (X + DX);
                     GY : constant Int64 := Round_Index (Y + DY);
                  begin
                     for MY in Int64'Max (GY - IM, Area_Box.Y_Min)
                       .. Int64'Min (GY + IM, Area_Box.Y_Max)
                     loop
                        pragma Loop_Invariant
                          (KI.Valid_Image (Mask)
                           and then Int64 (Mask.Width)
                                      = Area_Box.X_Max - Area_Box.X_Min + 1
                           and then Int64 (Mask.Height)
                                      = Area_Box.Y_Max - Area_Box.Y_Min + 1);
                        for MX in Int64'Max (GX - IM, Area_Box.X_Min)
                          .. Int64'Min (GX + IM, Area_Box.X_Max)
                        loop
                           pragma Loop_Invariant
                             (KI.Valid_Image (Mask)
                              and then Int64 (Mask.Width)
                                         = Area_Box.X_Max - Area_Box.X_Min
                                           + 1
                              and then Int64 (Mask.Height)
                                         = Area_Box.Y_Max - Area_Box.Y_Min
                                           + 1);
                           Mask.Pixels (Natural (MY - Area_Box.Y_Min),
                                        Natural (MX - Area_Box.X_Min)) :=
                             Ignored_Mark;
                        end loop;
                     end loop;
                  end;
               end;
            end loop;
         end;

         --  The edge threshold, as in training: the larger of
         --  ContrastThreshold and Train_Contrast_Fraction times the largest
         --  magnitude in the footprint's bounding box (compared as
         --  squares). Training keeps only the edges above that fraction,
         --  so weaker texture in the pattern itself is not counted as
         --  clutter.
         Edge_Threshold :=
           Long_Float'Max (N.Square_Within (Threshold, Max_Contrast_Threshold),
                           Train_Contrast_Fraction * Train_Contrast_Fraction
                           * Largest_In_Box (L, Level, Region, Area,
                                             Area_Box, Mask));

         --  Count the edge pixels of the footprint and the unexplained
         --  ones. The pixel offsets from the footprint's corner stay within
         --  2**35: pixels lie within the level (at most 2**31 wide and
         --  high) and the corner within 2**34.
         pragma Assert (Area_Box.X_Min >= 1 and then Area_Box.X_Max <= W - 2
                        and then Area_Box.Y_Min >= 1
                        and then Area_Box.Y_Max <= H - 2
                        and then W <= 2 ** 31 and then H <= 2 ** 31);
         for J in Area_Box.Y_Min .. Area_Box.Y_Max loop
            pragma Loop_Invariant
              (KI.Valid_Image (Mask)
               and then Int64 (Mask.Width)
                          = Area_Box.X_Max - Area_Box.X_Min + 1
               and then Int64 (Mask.Height)
                          = Area_Box.Y_Max - Area_Box.Y_Min + 1
               and then Unexplained <= Total);
            pragma Assert (J >= 1 and then J <= 2 ** 31);
            for I in Area_Box.X_Min .. Area_Box.X_Max loop
               pragma Loop_Invariant (Unexplained <= Total);
               pragma Assert (I >= 1 and then I <= 2 ** 31);
               if Total < Natural'Last
                 and then Mask.Pixels (Natural (J - Area_Box.Y_Min),
                                       Natural (I - Area_Box.X_Min))
                            /= Ignored_Mark
                 and then In_Parallelogram
                            (Offset_Of (I, OX), Offset_Of (J, OY),
                             E1X, E1Y, E2X, E2Y, Det)
                 and then PY.Level_Pixel_In_Region
                            (Region, Area, Level, Natural (I), Natural (J))
                 and then PY.Is_Edge (L, Natural (I), Natural (J),
                                      Edge_Threshold)
               then
                  Total := Total + 1;
                  if Mask.Pixels (Natural (J - Area_Box.Y_Min),
                                  Natural (I - Area_Box.X_Min)) = 0
                  then
                     Unexplained := Unexplained + 1;
                  end if;
               end if;
            end loop;
         end loop;
         --  Freed in place (as ks_image_8_grey_destroy does).
         Free (Mask.Pixels);
         Free (Mask);
      end;
      if Total > 0 then
         Clutter := Fraction_Of (Unexplained, Total);
      end if;
   end Compute_Clutter;

   ---------------------------------------------------------------------
   --  Measures
   ---------------------------------------------------------------------

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
   is
      R        : constant P.Rotation := P.Rotation_Of (Theta);
      W        : constant Int64 := Int64 (L.GX.Width);
      H        : constant Int64 := Int64 (L.GX.Height);
      Inside   : Natural := 0;
      Outside  : Natural := 0;
      Matched  : Natural := 0;
      Sum_Cos  : Long_Float range 0.0 .. Long_Float (Max_Features) := 0.0;
      Sum_T2   : Long_Float range 0.0 .. Long_Float (Max_Features) := 0.0;
      Sum_Mag  : Long_Float range 0.0 .. 1024.0 * Long_Float (Max_Features)
        := 0.0;
   begin
      Result := (others => <>);
      Set_Success (Status);
      for I in 0 .. Model.Count - 1 loop
         pragma Loop_Invariant
           (Inside + Outside = I and then Matched <= Inside);
         declare
            DX, DY : P.Offset;
            UX, UY : P.Unit;
         begin
            P.Map_Offset (F, R, Scale, Level,
                          Model.Features (I).X - F.Centroid_X,
                          Model.Features (I).Y - F.Centroid_Y, DX, DY);
            declare
               PX : constant Long_Float := X + DX;
               PY_Point : constant Long_Float := Y + DY;
               IX : constant Int64 := Round_Index (PX);
               IY : constant Int64 := Round_Index (PY_Point);
            begin
               if IX >= 0 and then IX < W and then IY >= 0 and then IY < H
                 and then PY.Level_Pixel_In_Region
                            (Region, Area, Level, Natural (IX), Natural (IY))
               then
                  Inside := Inside + 1;
                  P.Map_Normal (F, R, Model.Features (I).NX,
                                Model.Features (I).NY, UX, UY);
                  if (UX /= 0.0 or else UY /= 0.0)
                    and then abs PX <= 2.0 ** 32
                    and then abs PY_Point <= 2.0 ** 32
                  then
                     declare
                        Found     : Boolean;
                        T         : Distance;
                        Cosine    : P.Fraction;
                        Magnitude : Magnitude_Value;
                     begin
                        Find_Edge (L, PX, PY_Point, UX, UY, 2,
                                   F.Ignore_Polarity,
                                   Params.Contrast_Threshold, Found, T,
                                   Cosine, Magnitude);
                        if Found and then abs T <= Match_Distance
                          and then Cosine >= Cos_Match
                        then
                           --  At most Max_Features terms of at most 1,
                           --  1 and 1024: the limits never act.
                           Matched := Matched + 1;
                           Sum_Cos := Long_Float'Min
                             (Sum_Cos + Cosine, Long_Float (Max_Features));
                           Sum_T2 := Long_Float'Min
                             (Sum_T2 + N.Square_Within (T, 1.0),
                              Long_Float (Max_Features));
                           Sum_Mag := Long_Float'Min
                             (Sum_Mag + Magnitude,
                              1024.0 * Long_Float (Max_Features));
                        end if;
                     end;
                  end if;
               else
                  Outside := Outside + 1;
               end if;
            end;
         end;
      end loop;

      if Model.Count > 0 then
         Result.Outside := Fraction_Of (Outside, Model.Count);
      end if;
      if Model.Count > 0 then
         Result.Coverage :=
           N.Clamp_Unit (Sum_Cos / Long_Float (Model.Count));
      end if;
      if Matched > 0 then
         declare
            Mean_T2 : constant Long_Float :=
              N.Clamp_Unit (Sum_T2 / Long_Float (Matched));
            Root    : constant Long_Float :=
              Long_Float'Min (EF.Sqrt (Mean_T2), 1.0);
         begin
            Result.Fit_Error :=
              Long_Float'Max (0.0, Root * P.Level_Size (Level));
            Result.Contrast := Long_Float'Min
              (Long_Float'Max (0.0, Sum_Mag / Long_Float (Matched)),
               Max_Contrast);
         end;
      end if;

      if Params.Score_Using_Clutter = True_Value
        and then Result.Coverage >= Params.Accept_Threshold
      then
         Compute_Clutter
           (Model, F, L, Level, Region, Area, Params.Contrast_Threshold,
            X, Y, R, Scale, Result.Clutter, Status);
      end if;
   end Measure;

end AMV.Kernels.PM_Align.Refinement;
