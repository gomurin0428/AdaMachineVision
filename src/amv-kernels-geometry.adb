pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;

with AMV.Kernels.Numerics;

package body AMV.Kernels.Geometry with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package N renames AMV.Kernels.Numerics;

   ---------------------------------------------------------------------
   --  Tolerances (AMV.Geometry documents what each one means)
   ---------------------------------------------------------------------

   Parallel_Tolerance : constant := 1.0E-12;
   --  Largest |sin| of the angle between two lines treated as parallel.

   Tangency_Tolerance : constant := 1.0E-9;
   --  Relative slack, scaled by max (1, radius), for calling a line or a
   --  circle tangent to a circle.

   Coincidence_Tolerance : constant := 1.0E-12;
   --  Points whose RMS spread is at most this fraction of the largest
   --  coordinate magnitude are treated as one point.

   Max_Exponent_Gap : constant := 60;
   --  When the largest coordinate magnitude is more than 2**Max_Exponent_Gap
   --  times the largest offset from the centroid, the points coincide.

   Isotropy_Tolerance : constant := 2.0 ** (-46);
   --  The scatter counts as isotropic when |Sxx - Syy| + 2 |Sxy| is at most
   --  this times (Sqrt (N) + M / Rho) * (Sxx + Syy).

   Collinear_Tolerance : constant := 1.0E-8;
   Centre_Limit_Factor : constant := 1.0E9;
   Tie_Tolerance       : constant := 1.0E-12;
   Suspect_Fraction    : constant := 1.0E-8;

   Max_Circle_Iterations : constant := 100;
   Max_Saddle_Escapes    : constant := 4;
   Circle_Step_Tolerance : constant := 1.0E-12;
   Exact_Fit_Tolerance   : constant := 1.0E-14;
   Curvature_Tolerance   : constant := 1.0E-9;
   Local_Step_Fraction   : constant := 1.0E-3;
   Initial_Damping       : constant := 1.0E-3;
   Min_Damping           : constant := 1.0E-12;
   Max_Damping           : constant := 1.0E12;

   ---------------------------------------------------------------------
   --  Bounds of the scaled quantities
   ---------------------------------------------------------------------

   --  The fits work on the offsets of the points from their centroid
   --  multiplied by 2**(-E), where E is the exponent of the largest offset,
   --  so every scaled offset lies within [-1, 1]. With at most Max_Points
   --  (< 2**31) points, every sum and product below has a bound that holds
   --  mathematically; the clamps that state them for the prover never act
   --  (docs/PROOF.md lists them):
   --
   --  * Offset_Sum_Limit: a sum of offsets from the first point, at most
   --    2**31 * 2.0E150 < 2**530;
   --  * Moment_Limit: a sum of products of at most two scaled offsets or
   --    frame coordinates (at most 16 each), below 2**35;
   --  * Centre_Bound: a trial centre of the circle fit, within Limit =
   --    1.0E9 * Sqrt (Stt / N) <= 2.0E9;
   --  * Radius_Bound: a mean distance from such a centre, below 2**33;
   --  * Gradient_Bound, Curvature_Bound and Cost_Bound: sums over the
   --    points of a gradient term (at most 2 * 2**34), of a curvature term
   --    (at most 2**60, see Weight_Limit) and of a squared residual (at
   --    most 2**68).

   Offset_Sum_Limit : constant := 2.0 ** 560;
   Moment_Limit     : constant := 2.0 ** 40;
   Centre_Bound     : constant := 2.0 ** 32;
   Radius_Bound     : constant := 2.0 ** 40;
   Distance_Bound   : constant := 2.0 ** 34;
   Gradient_Bound   : constant := 2.0 ** 80;
   Curvature_Bound  : constant := 2.0 ** 100;
   Cost_Bound       : constant := 2.0 ** 120;
   Weight_Limit     : constant := 2.0 ** 60;
   --  The largest weight Res / Dist of the curvature term. A point closer
   --  to the trial centre than 2**(-60) times its residual adds nothing to
   --  the curvature, as a point exactly on the centre does.
   Step_Limit       : constant := 2.0 ** 35;
   --  The longest step formed (twice the largest Limit and more); a
   --  longer step leaves Limit, which makes the centre run off.

   type Fit_Status is
     (Fit_Ok,
      Too_Few_Points,
      Coincident_Points,
      Collinear_Points,
      Runaway_Centre);
   --  Outcome of an internal fit; only the entry points turn a failure
   --  into a status.

   ---------------------------------------------------------------------
   --  Messages
   ---------------------------------------------------------------------

   function Image_Of (Value : Int64) return String
   with Pre  => Value > Int64'First,
        Post => Image_Of'Result'First = 1
                and then Image_Of'Result'Length in 1 .. 20;
   --  The decimal digits of Value, with a leading '-' when it is negative.

   function Image_Of (Value : Int64) return String is
      Text  : String (1 .. 20) := [others => '0'];
      Rest  : Int64 := abs Value;
      First : Positive;
   begin
      for K in reverse 2 .. 20 loop
         Text (K) := Character'Val (Character'Pos ('0') + Rest mod 10);
         Rest := Rest / 10;
         First := K;
         exit when Rest = 0;
         pragma Loop_Invariant (First = K and then Rest >= 1);
      end loop;
      if Value < 0 then
         First := First - 1;
         Text (First) := '-';
      end if;
      declare
         Last   : constant Natural := 21 - First;
         Result : constant String (1 .. Last) := Text (First .. 20);
      begin
         return Result;
      end;
   end Image_Of;

   subtype Operation_Name is String
     with Dynamic_Predicate =>
       Operation_Name'First = 1 and then Operation_Name'Length <= 40;
   --  The name of the operation that starts a message.

   subtype Argument_Name is String
     with Dynamic_Predicate =>
       Argument_Name'First = 1 and then Argument_Name'Length <= 40;

   procedure Bad
     (Status  : out Ks_Status;
      Message : String)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad
     (Status  : out Ks_Status;
      Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Out_Of_Bound
     (Operation : Operation_Name;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;
   --  "<Operation>: the result would exceed +/-1.0E150".

   procedure Out_Of_Bound
     (Operation : Operation_Name;
      Status    : out Ks_Status) is
   begin
      Bad (Status, Operation & ": the result would exceed +/-1.0E150");
   end Out_Of_Bound;

   --  Argument checks. Each one leaves a failed Status as it is, and
   --  otherwise fails when its argument is out of bounds, so that a
   --  sequence of checks reports the first argument at fault.

   function Checkable (Status : Ks_Status) return Boolean is
     (Valid (Status)
      and then Status.Failure in Failure_None | Failure_Bad_Parameter);

   procedure Require_Value
     (Operation : Operation_Name;
      Name      : Argument_Name;
      X         : Long_Float;
      Status    : in out Ks_Status)
   with Pre  => Checkable (Status),
        Post => Checkable (Status)
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old) and then Bounded (X));
   --  "<Operation>: <Name> must be finite and within +/-1.0E150".

   procedure Require_Value
     (Operation : Operation_Name;
      Name      : Argument_Name;
      X         : Long_Float;
      Status    : in out Ks_Status) is
   begin
      if Succeeded (Status) and then not Bounded (X) then
         Bad (Status, Operation & ": " & Name
                      & " must be finite and within +/-1.0E150");
      end if;
   end Require_Value;

   procedure Require_Finite
     (Operation : Operation_Name;
      Name      : Argument_Name;
      X         : Long_Float;
      Status    : in out Ks_Status)
   with Pre  => Checkable (Status),
        Post => Checkable (Status)
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old) and then Is_Finite (X));
   --  "<Operation>: <Name> must be finite".

   procedure Require_Finite
     (Operation : Operation_Name;
      Name      : Argument_Name;
      X         : Long_Float;
      Status    : in out Ks_Status) is
   begin
      if Succeeded (Status) and then not Is_Finite (X) then
         Bad (Status, Operation & ": " & Name & " must be finite");
      end if;
   end Require_Finite;

   procedure Require_Point
     (Operation : Operation_Name;
      Name      : String;
      P         : Ks_Point_2D;
      Status    : in out Ks_Status)
   with Pre  => Checkable (Status)
                and then Name'First = 1 and then Name'Length <= 20,
        Post => Checkable (Status)
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old) and then Bounded (P));

   procedure Require_Point
     (Operation : Operation_Name;
      Name      : String;
      P         : Ks_Point_2D;
      Status    : in out Ks_Status) is
   begin
      Require_Value (Operation, Name & ".X", P.X, Status);
      Require_Value (Operation, Name & ".Y", P.Y, Status);
   end Require_Point;

   procedure Require_Line
     (Operation : Operation_Name;
      Name      : String;
      L         : Ks_Line_2D;
      Status    : in out Ks_Status)
   with Pre  => Checkable (Status)
                and then Name'First = 1 and then Name'Length <= 20,
        Post => Checkable (Status)
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old)
                               and then Valid_Line (L));

   procedure Require_Line
     (Operation : Operation_Name;
      Name      : String;
      L         : Ks_Line_2D;
      Status    : in out Ks_Status) is
   begin
      Require_Value (Operation, Name & ".X", L.X, Status);
      Require_Value (Operation, Name & ".Y", L.Y, Status);
      Require_Finite (Operation, Name & ".Rotation", L.Rotation, Status);
   end Require_Line;

   procedure Require_Circle
     (Operation : Operation_Name;
      Name      : String;
      C         : Ks_Circle_2D;
      Status    : in out Ks_Status)
   with Pre  => Checkable (Status)
                and then Name'First = 1 and then Name'Length <= 20,
        Post => Checkable (Status)
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old) and then Bounded (C));

   procedure Require_Circle
     (Operation : Operation_Name;
      Name      : String;
      C         : Ks_Circle_2D;
      Status    : in out Ks_Status) is
   begin
      Require_Value (Operation, Name & ".Center_X", C.Center_X, Status);
      Require_Value (Operation, Name & ".Center_Y", C.Center_Y, Status);
      Require_Value (Operation, Name & ".Radius", C.Radius, Status);
   end Require_Circle;

   ---------------------------------------------------------------------
   --  Small helpers
   ---------------------------------------------------------------------

   Origin : constant Ks_Point_2D := (X => 0.0, Y => 0.0);

   function Point_At (Points : Point_Array; I : Natural) return Ks_Point_2D
   is
     ((X => N.Clamp (Points (I).X, Max_Coordinate),
       Y => N.Clamp (Points (I).Y, Max_Coordinate)))
   with Pre  => I in Points'Range,
        Post => Bounded (Point_At'Result);
   --  Point I, read within the bound. The entry points check every point
   --  first, so the clamps never act.

   function Selected (Mask : Flag_Array; Index : Natural) return Boolean is
     (Mask'Length = 0 or else Mask (Index))
   with Pre => Mask'Length = 0 or else Index in Mask'Range;
   --  True when point Index takes part in a fit. An empty Mask means all.

   No_Mask : constant Flag_Array (1 .. 0) := [others => False];

   function Mask_Fits (Points : Point_Array; Mask : Flag_Array)
      return Boolean
   is
     (Mask'Length = 0
      or else (Mask'First = Points'First and then Mask'Last = Points'Last));

   function Unit_Quotient (X, Length : Long_Float) return Long_Float
   with Pre  => Length > 0.0 and then Length <= N.Mul_Limit,
        Post => abs Unit_Quotient'Result <= 1.0;
   --  X / Length for abs X <= Length (a component of a vector over the
   --  vector's length, which Hypot never makes shorter than either
   --  component): the test below always holds.

   function Unit_Quotient (X, Length : Long_Float) return Long_Float is
   begin
      if abs X <= Length then
         return N.Unit_Ratio (X, Length);
      elsif X > 0.0 then
         return 1.0;
      else
         return -1.0;
      end if;
   end Unit_Quotient;

   procedure Direction
     (DX, DY : Long_Float;
      Length : out Long_Float;
      U, V   : out Long_Float)
   with Pre  => abs DX <= 2.0 ** 100 and then abs DY <= 2.0 ** 100,
        Post => Length >= 0.0 and then Length <= 2.0 ** 101
                and then abs U <= 1.0 and then abs V <= 1.0;
   --  Length of (DX, DY) and the unit vector along it. The zero vector
   --  gets the arbitrary unit vector (1, 0): in the circle fit this is a
   --  point sitting exactly on the trial centre, where the distance has a
   --  cone-shaped kink, and any one-sided direction lets the descent move
   --  off the kink (a zero vector would fake a zero gradient there).

   procedure Direction
     (DX, DY : Long_Float;
      Length : out Long_Float;
      U, V   : out Long_Float) is
   begin
      Length := N.Hypot (DX, DY);
      if Length > 0.0 then
         U := Unit_Quotient (DX, Length);
         V := Unit_Quotient (DY, Length);
      else
         U := 1.0;
         V := 0.0;
      end if;
   end Direction;

   ---------------------------------------------------------------------
   --  Exact scaling by powers of two
   ---------------------------------------------------------------------

   --  gnatprove does not support the non-static attributes 'Exponent and
   --  'Scaling, so the exponent is found and the scaling done with static
   --  powers of two, which is just as exact: multiplying by a power of two
   --  rounds only when the result is subnormal.

   function Exponent_Of (X : Long_Float) return Integer
   with Pre  => X > 0.0 and then X <= 2.0 ** 500,
        Post => Exponent_Of'Result in -1074 .. 501;
   --  The E with 2**(E - 1) <= X < 2**E (Long_Float'Exponent (X)).

   function Exponent_Of (X : Long_Float) return Integer is
      Y : Long_Float := X;
      E : Integer := 1;
   begin
      --  X = Y * 2**(E - 1) throughout.
      if Y >= 1.0 then
         --  Y >= 1; the steps bring it below 2.
         if Y >= 2.0 ** 256 then
            Y := Y * 2.0 ** (-256);
            E := E + 256;
         end if;
         if Y >= 2.0 ** 128 then
            Y := Y * 2.0 ** (-128);
            E := E + 128;
         end if;
         if Y >= 2.0 ** 64 then
            Y := Y * 2.0 ** (-64);
            E := E + 64;
         end if;
         if Y >= 2.0 ** 32 then
            Y := Y * 2.0 ** (-32);
            E := E + 32;
         end if;
         if Y >= 2.0 ** 16 then
            Y := Y * 2.0 ** (-16);
            E := E + 16;
         end if;
         if Y >= 2.0 ** 8 then
            Y := Y * 2.0 ** (-8);
            E := E + 8;
         end if;
         if Y >= 2.0 ** 4 then
            Y := Y * 2.0 ** (-4);
            E := E + 4;
         end if;
         if Y >= 2.0 ** 2 then
            Y := Y * 2.0 ** (-2);
            E := E + 2;
         end if;
         if Y >= 2.0 then
            E := E + 1;
         end if;
      else
         --  Y < 1; the steps bring it to [1, 2) and keep it below 2.
         if Y < 2.0 ** (-511) then
            Y := Y * 2.0 ** 512;
            E := E - 512;
         end if;
         if Y < 2.0 ** (-511) then
            Y := Y * 2.0 ** 512;
            E := E - 512;
         end if;
         if Y < 2.0 ** (-255) then
            Y := Y * 2.0 ** 256;
            E := E - 256;
         end if;
         if Y < 2.0 ** (-127) then
            Y := Y * 2.0 ** 128;
            E := E - 128;
         end if;
         if Y < 2.0 ** (-63) then
            Y := Y * 2.0 ** 64;
            E := E - 64;
         end if;
         if Y < 2.0 ** (-31) then
            Y := Y * 2.0 ** 32;
            E := E - 32;
         end if;
         if Y < 2.0 ** (-15) then
            Y := Y * 2.0 ** 16;
            E := E - 16;
         end if;
         if Y < 2.0 ** (-7) then
            Y := Y * 2.0 ** 8;
            E := E - 8;
         end if;
         if Y < 2.0 ** (-3) then
            Y := Y * 2.0 ** 4;
            E := E - 4;
         end if;
         if Y < 2.0 ** (-1) then
            Y := Y * 2.0 ** 2;
            E := E - 2;
         end if;
         if Y < 1.0 then
            E := E - 1;
         end if;
      end if;
      --  E lies in -1073 .. 501 for X in (0, 2**500]; the limits state it
      --  for the prover and never act.
      return Integer'Max (-1074, Integer'Min (501, E));
   end Exponent_Of;

   function Power_Of_Two (K : Integer) return Long_Float
   with Pre  => K in -1074 .. 510,
        Post => Power_Of_Two'Result >= 0.0
                and then Power_Of_Two'Result <= 2.0 ** 510;
   --  2**K, exactly (a product of static powers of two).

   function Power_Of_Two (K : Integer) return Long_Float is
      R : Long_Float := 1.0;
      M : Integer := K;
   begin
      if M >= 0 then
         if M >= 256 then
            R := R * 2.0 ** 256;
            M := M - 256;
         end if;
         if M >= 128 then
            R := R * 2.0 ** 128;
            M := M - 128;
         end if;
         if M >= 64 then
            R := R * 2.0 ** 64;
            M := M - 64;
         end if;
         if M >= 32 then
            R := R * 2.0 ** 32;
            M := M - 32;
         end if;
         if M >= 16 then
            R := R * 2.0 ** 16;
            M := M - 16;
         end if;
         if M >= 8 then
            R := R * 2.0 ** 8;
            M := M - 8;
         end if;
         if M >= 4 then
            R := R * 2.0 ** 4;
            M := M - 4;
         end if;
         if M >= 2 then
            R := R * 2.0 ** 2;
            M := M - 2;
         end if;
         if M >= 1 then
            R := R * 2.0;
         end if;
      else
         M := -M;
         if M >= 512 then
            R := R * 2.0 ** (-512);
            M := M - 512;
         end if;
         if M >= 512 then
            R := R * 2.0 ** (-512);
            M := M - 512;
         end if;
         if M >= 256 then
            R := R * 2.0 ** (-256);
            M := M - 256;
         end if;
         if M >= 128 then
            R := R * 2.0 ** (-128);
            M := M - 128;
         end if;
         if M >= 64 then
            R := R * 2.0 ** (-64);
            M := M - 64;
         end if;
         if M >= 32 then
            R := R * 2.0 ** (-32);
            M := M - 32;
         end if;
         if M >= 16 then
            R := R * 2.0 ** (-16);
            M := M - 16;
         end if;
         if M >= 8 then
            R := R * 2.0 ** (-8);
            M := M - 8;
         end if;
         if M >= 4 then
            R := R * 2.0 ** (-4);
            M := M - 4;
         end if;
         if M >= 2 then
            R := R * 2.0 ** (-2);
            M := M - 2;
         end if;
         if M >= 1 then
            R := R * 0.5;
         end if;
      end if;
      --  R = 2**K <= 2**510; the limits state it for the prover and never
      --  act.
      return Long_Float'Max (0.0, Long_Float'Min (R, 2.0 ** 510));
   end Power_Of_Two;

   function Scaled_Offset (V : Long_Float; E : Integer) return Long_Float
   with Pre  => E in -1074 .. 501 and then abs V <= 2.0 ** 501,
        Post => abs Scaled_Offset'Result <= 1.0;
   --  V * 2**(-E) for an offset V of at most the largest offset, whose
   --  exponent E is (so abs V < 2**E and the result lies within [-1, 1]),
   --  as Long_Float'Scaling (V, -E) gives it. Below 2**(-500) the scaling
   --  is done in two exact steps.

   function Scaled_Offset (V : Long_Float; E : Integer) return Long_Float is
   begin
      if E >= -500 then
         return N.Clamp (N.Mul (V, Power_Of_Two (-E)), 1.0);
      else
         --  abs V < 2**E <= 2**(-501), so V * 2**600 < 2**99.
         return N.Clamp
           (N.Mul (N.Clamp (V, 2.0 ** (-500)) * 2.0 ** 600,
                   Power_Of_Two (-E - 600)),
            1.0);
      end if;
   end Scaled_Offset;

   function Scaled_Scale (S : Long_Float; E : Integer) return Long_Float
   with Pre  => E in -1074 .. 501 and then S >= 0.0
                and then S <= 2.0 ** 501,
        Post => Scaled_Scale'Result >= 0.0
                and then Scaled_Scale'Result <= 2.0 ** 61;
   --  S * 2**(-E) for the largest coordinate magnitude S once it is known
   --  to be below 2**(E + 60) (see Analyse_Scatter), so the result lies
   --  below 2**60.

   function Scaled_Scale (S : Long_Float; E : Integer) return Long_Float is
      R : Long_Float;
   begin
      if E >= -500 then
         R := N.Mul (S, Power_Of_Two (-E));
      else
         --  S < 2**(E + 60) <= 2**(-440), so S * 2**600 < 2**160.
         R := N.Mul (N.Clamp (S, 2.0 ** (-440)) * 2.0 ** 600,
                     Power_Of_Two (-E - 600));
      end if;
      return Long_Float'Max (0.0, Long_Float'Min (R, 2.0 ** 61));
   end Scaled_Scale;

   function Unscaled (V : Long_Float; E : Integer) return Long_Float
   with Pre  => E in -1074 .. 501 and then abs V <= 2.0 ** 200,
        Post => abs Unscaled'Result <= 2.0 ** 1020;
   --  V * 2**E, the inverse of the scaling (Long_Float'Scaling (V, E)).

   function Unscaled (V : Long_Float; E : Integer) return Long_Float is
     (N.Mul (V, Power_Of_Two (E)));

   function Rescaled_Cost (Cost : Long_Float; D : Integer) return Long_Float
   with Pre  => Cost >= 0.0 and then Cost <= Cost_Bound
                and then D in -3200 .. 3200,
        Post => abs Rescaled_Cost'Result <= 2.0 ** 1020;
   --  Cost * 2**D, a cost of the robust circle fit expressed in the units
   --  of another scaling. D is at most 2 (removing a point at most doubles
   --  the largest offset from the centroid), which the first limit states;
   --  very negative D take two steps.

   function Rescaled_Cost (Cost : Long_Float; D : Integer) return Long_Float
   is
      K : constant Integer := Integer'Min (D, 4);
   begin
      if K >= -1000 then
         return N.Mul (Cost, Power_Of_Two (K));
      else
         return N.Mul (Cost * 2.0 ** (-1000),
                       Power_Of_Two (Integer'Max (K + 1000, -1074)));
      end if;
   end Rescaled_Cost;

   ---------------------------------------------------------------------
   --  Distances and projections
   ---------------------------------------------------------------------

   procedure Set_Result
     (Operation : Operation_Name;
      Value     : Long_Float;
      Result    : out Long_Float;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then Bounded (Result)
                and then (if Succeeded (Status) then Result = Value
                          else Result = 0.0);
   --  Result := Value when it is within the bound, otherwise a failure.

   procedure Set_Result
     (Operation : Operation_Name;
      Value     : Long_Float;
      Result    : out Long_Float;
      Status    : out Ks_Status) is
   begin
      if Bounded (Value) then
         Result := Value;
         Set_Success (Status);
      else
         Result := 0.0;
         Out_Of_Bound (Operation, Status);
      end if;
   end Set_Result;

   procedure Distance
     (P, Q   : Ks_Point_2D;
      Result : out Long_Float;
      Status : out Ks_Status) is
   begin
      Result := 0.0;
      Set_Success (Status);
      Require_Point ("Distance", "P", P, Status);
      Require_Point ("Distance", "Q", Q, Status);
      if Succeeded (Status) then
         Set_Result ("Distance", N.Hypot (P.X - Q.X, P.Y - Q.Y), Result,
                     Status);
      end if;
   end Distance;

   function Signed_Offset (P : Ks_Point_2D; Line : Ks_Line_2D)
      return Long_Float
   is
     (N.Times_Unit (P.Y - Line.Y, EF.Cos (Line.Rotation))
      - N.Times_Unit (P.X - Line.X, EF.Sin (Line.Rotation)))
   with Pre  => Bounded (P) and then Valid_Line (Line),
        Post => abs Signed_Offset'Result <= 4.0 * Max_Coordinate;
   --  (P.Y - Line.Y) cos R - (P.X - Line.X) sin R.

   function Along (P : Ks_Point_2D; Line : Ks_Line_2D) return Long_Float is
     (N.Times_Unit (P.X - Line.X, EF.Cos (Line.Rotation))
      + N.Times_Unit (P.Y - Line.Y, EF.Sin (Line.Rotation)))
   with Pre  => Bounded (P) and then Valid_Line (Line),
        Post => abs Along'Result <= 4.0 * Max_Coordinate;
   --  (P.X - Line.X) cos R + (P.Y - Line.Y) sin R.

   procedure Signed_Distance
     (P      : Ks_Point_2D;
      Line   : Ks_Line_2D;
      Result : out Long_Float;
      Status : out Ks_Status) is
   begin
      Result := 0.0;
      Set_Success (Status);
      Require_Point ("Signed_Distance", "P", P, Status);
      Require_Line ("Signed_Distance", "Line", Line, Status);
      if Succeeded (Status) then
         Set_Result ("Signed_Distance", Signed_Offset (P, Line), Result,
                     Status);
      end if;
   end Signed_Distance;

   procedure Line_Distance
     (P      : Ks_Point_2D;
      Line   : Ks_Line_2D;
      Result : out Long_Float;
      Status : out Ks_Status) is
   begin
      Result := 0.0;
      Set_Success (Status);
      Require_Point ("Distance", "P", P, Status);
      Require_Line ("Distance", "Line", Line, Status);
      if Succeeded (Status) then
         Set_Result ("Distance", abs Signed_Offset (P, Line), Result,
                     Status);
      end if;
   end Line_Distance;

   procedure Position_Along
     (P      : Ks_Point_2D;
      Line   : Ks_Line_2D;
      Result : out Long_Float;
      Status : out Ks_Status) is
   begin
      Result := 0.0;
      Set_Success (Status);
      Require_Point ("Position_Along", "P", P, Status);
      Require_Line ("Position_Along", "Line", Line, Status);
      if Succeeded (Status) then
         Set_Result ("Position_Along", Along (P, Line), Result, Status);
      end if;
   end Position_Along;

   procedure Project
     (P      : Ks_Point_2D;
      Line   : Ks_Line_2D;
      Result : out Ks_Point_2D;
      Status : out Ks_Status) is
   begin
      Result := Origin;
      Set_Success (Status);
      Require_Point ("Project", "P", P, Status);
      Require_Line ("Project", "Line", Line, Status);
      if Succeeded (Status) then
         declare
            T : constant Long_Float := Along (P, Line);
            X : constant Long_Float :=
              Line.X + N.Times_Unit (T, EF.Cos (Line.Rotation));
            Y : constant Long_Float :=
              Line.Y + N.Times_Unit (T, EF.Sin (Line.Rotation));
         begin
            if Bounded (X) and then Bounded (Y) then
               Result := (X => X, Y => Y);
            else
               Out_Of_Bound ("Project", Status);
            end if;
         end;
      end if;
   end Project;

   procedure Circle_Distance
     (P      : Ks_Point_2D;
      Circle : Ks_Circle_2D;
      Result : out Long_Float;
      Status : out Ks_Status) is
   begin
      Result := 0.0;
      Set_Success (Status);
      Require_Point ("Distance", "P", P, Status);
      Require_Circle ("Distance", "Circle", Circle, Status);
      if Succeeded (Status) then
         Set_Result
           ("Distance",
            abs (N.Hypot (P.X - Circle.Center_X, P.Y - Circle.Center_Y)
                 - Circle.Radius),
            Result, Status);
      end if;
   end Circle_Distance;

   ---------------------------------------------------------------------
   --  Intersections and angles
   ---------------------------------------------------------------------

   procedure Intersect_Lines
     (Line_1, Line_2 : Ks_Line_2D;
      Point          : out Ks_Point_2D;
      Parallel       : out Int32;
      Status         : out Ks_Status) is
   begin
      Point := Origin;
      Parallel := False_Value;
      Set_Success (Status);
      Require_Line ("Intersect", "Line_1", Line_1, Status);
      Require_Line ("Intersect", "Line_2", Line_2, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         C1    : constant Long_Float := EF.Cos (Line_1.Rotation);
         S1    : constant Long_Float := EF.Sin (Line_1.Rotation);
         C2    : constant Long_Float := EF.Cos (Line_2.Rotation);
         S2    : constant Long_Float := EF.Sin (Line_2.Rotation);
         Cross : constant Long_Float :=
           N.Times_Unit (C1, S2) - N.Times_Unit (S1, C2);
         --  sin (Line_2.Rotation - Line_1.Rotation)
         Num   : Long_Float;
         T     : Long_Float;
         Fits  : Boolean;
      begin
         if abs Cross <= Parallel_Tolerance then
            Parallel := True_Value;
            return;
         end if;
         --  Solve P1 + T D1 = P2 + S D2: crossing both sides with D2
         --  eliminates S and leaves T = ((P2 - P1) x D2) / (D1 x D2). The
         --  quotient is at most 4.0E150 / 1.0E-12, so it always fits.
         Num := N.Times_Unit (Line_2.X - Line_1.X, S2)
                - N.Times_Unit (Line_2.Y - Line_1.Y, C2);
         N.Ratio_Within (abs Num, abs Cross, N.Mul_Limit, T, Fits);
         if not Fits then
            Out_Of_Bound ("Intersect", Status);
            return;
         end if;
         if (Num < 0.0) /= (Cross < 0.0) then
            T := -T;
         end if;
         declare
            X : constant Long_Float := Line_1.X + N.Times_Unit (T, C1);
            Y : constant Long_Float := Line_1.Y + N.Times_Unit (T, S1);
         begin
            if Bounded (X) and then Bounded (Y) then
               Point := (X => X, Y => Y);
            else
               Out_Of_Bound ("Intersect", Status);
            end if;
         end;
      end;
   end Intersect_Lines;

   procedure Intersect_Line_Circle
     (Line             : Ks_Line_2D;
      Circle           : Ks_Circle_2D;
      Point_1, Point_2 : out Ks_Point_2D;
      Count            : out Int32;
      Status           : out Ks_Status) is
   begin
      Point_1 := Origin;
      Point_2 := Origin;
      Count := 0;
      Set_Success (Status);
      Require_Line ("Intersect", "Line", Line, Status);
      Require_Circle ("Intersect", "Circle", Circle, Status);
      if not Succeeded (Status) then
         return;
      elsif Circle.Radius < 0.0 then
         Bad (Status, "Intersect: Circle.Radius must be >= 0");
         return;
      end if;
      declare
         C      : constant Long_Float := EF.Cos (Line.Rotation);
         S      : constant Long_Float := EF.Sin (Line.Rotation);
         WX     : constant Long_Float := Circle.Center_X - Line.X;
         WY     : constant Long_Float := Circle.Center_Y - Line.Y;
         Along  : constant Long_Float :=
           N.Times_Unit (WX, C) + N.Times_Unit (WY, S);
         Offset : constant Long_Float :=
           abs (N.Times_Unit (WY, C) - N.Times_Unit (WX, S));
         R      : constant Long_Float := Circle.Radius;
         Tol    : constant Long_Float :=
           Tangency_Tolerance * Long_Float'Max (1.0, R);
         Foot   : constant Ks_Point_2D :=
           (X => Line.X + N.Times_Unit (Along, C),
            Y => Line.Y + N.Times_Unit (Along, S));
         Half   : Long_Float;
         P1, P2 : Ks_Point_2D;
      begin
         if Offset > R + Tol then
            return;
         elsif Offset >= R - Tol then
            if Bounded (Foot) then
               Point_1 := Foot;
               Point_2 := Foot;
               Count := 1;
            else
               Out_Of_Bound ("Intersect", Status);
            end if;
            return;
         end if;
         --  Half chord; (R - Offset) * (R + Offset) avoids the cancellation
         --  of R**2 - Offset**2. The half chord is at most R; the limit
         --  states a weaker bound for the prover and never acts.
         Half := Long_Float'Min
           (EF.Sqrt (Long_Float'Max
                       (0.0, N.Mul_Within (R - Offset, R + Offset,
                                           Max_Coordinate,
                                           2.0 * Max_Coordinate))),
            2.0 * Max_Coordinate);
         P1 := (X => Foot.X - N.Times_Unit (Half, C),
                Y => Foot.Y - N.Times_Unit (Half, S));
         P2 := (X => Foot.X + N.Times_Unit (Half, C),
                Y => Foot.Y + N.Times_Unit (Half, S));
         if Bounded (P1) and then Bounded (P2) then
            Point_1 := P1;
            Point_2 := P2;
            Count := 2;
         else
            Out_Of_Bound ("Intersect", Status);
         end if;
      end;
   end Intersect_Line_Circle;

   procedure Intersect_Circles
     (Circle_1, Circle_2 : Ks_Circle_2D;
      Point_1, Point_2   : out Ks_Point_2D;
      Count              : out Int32;
      Status             : out Ks_Status) is
   begin
      Point_1 := Origin;
      Point_2 := Origin;
      Count := 0;
      Set_Success (Status);
      Require_Circle ("Intersect", "Circle_1", Circle_1, Status);
      Require_Circle ("Intersect", "Circle_2", Circle_2, Status);
      if not Succeeded (Status) then
         return;
      elsif Circle_1.Radius < 0.0 or else Circle_2.Radius < 0.0 then
         Bad (Status, "Intersect: circle radii must be >= 0");
         return;
      end if;
      declare
         R1   : constant Long_Float := Circle_1.Radius;
         R2   : constant Long_Float := Circle_2.Radius;
         WX   : constant Long_Float := Circle_2.Center_X - Circle_1.Center_X;
         WY   : constant Long_Float := Circle_2.Center_Y - Circle_1.Center_Y;
         Dist : constant Long_Float := N.Hypot (WX, WY);
         Tol  : constant Long_Float :=
           Tangency_Tolerance * Long_Float'Max (1.0, R1 + R2);
         UX, UY : Long_Float;
         Num    : Long_Float;
         A, H   : Long_Float;
         Fits   : Boolean;
         Mid    : Ks_Point_2D;
         P1, P2 : Ks_Point_2D;
      begin
         if Dist <= Tol                         --  concentric or coincident
           or else Dist > R1 + R2 + Tol         --  apart
           or else Dist < abs (R1 - R2) - Tol   --  one inside the other
         then
            return;
         end if;
         UX := Unit_Quotient (WX, Dist);
         UY := Unit_Quotient (WY, Dist);
         --  A is the signed distance from centre 1 to the radical line
         --  along the centre line: (Dist**2 + R1**2 - R2**2) / (2 Dist).
         --  Here its magnitude stays below about 2 R1, so the quotient
         --  always fits.
         Num := N.Mul_Within (Dist - R2, Dist + R2,
                              5.0 * Max_Coordinate, 5.0 * Max_Coordinate)
                + N.Mul_Within (R1, R1, Max_Coordinate, Max_Coordinate);
         N.Quotient_Within (abs Num, 2.0 * Dist, 2.0 ** 505, A, Fits);
         if not Fits then
            Out_Of_Bound ("Intersect", Status);
            return;
         end if;
         if Num < 0.0 then
            A := -A;
         end if;
         Mid := (X => Circle_1.Center_X + N.Times_Unit (A, UX),
                 Y => Circle_1.Center_Y + N.Times_Unit (A, UY));

         if abs (Dist - (R1 + R2)) <= Tol
           or else abs (Dist - abs (R1 - R2)) <= Tol
         then
            if Bounded (Mid) then
               Point_1 := Mid;
               Point_2 := Mid;
               Count := 1;
            else
               Out_Of_Bound ("Intersect", Status);
            end if;
            return;
         end if;
         --  The half chord is at most R1; the limit states a weaker bound
         --  for the prover and never acts.
         H := Long_Float'Min
           (EF.Sqrt (Long_Float'Max
                       (0.0, N.Mul_Within (R1 - A, R1 + A,
                                           2.0 ** 506, 2.0 ** 506))),
            2.0 ** 506);
         --  The left normal of the centre line is (-UY, UX).
         P1 := (X => Mid.X - N.Times_Unit (H, UY),
                Y => Mid.Y + N.Times_Unit (H, UX));
         P2 := (X => Mid.X + N.Times_Unit (H, UY),
                Y => Mid.Y - N.Times_Unit (H, UX));
         if Bounded (P1) and then Bounded (P2) then
            Point_1 := P1;
            Point_2 := P2;
            Count := 2;
         else
            Out_Of_Bound ("Intersect", Status);
         end if;
      end;
   end Intersect_Circles;

   procedure Angle_Between
     (Line_1, Line_2 : Ks_Line_2D;
      Result         : out Long_Float;
      Status         : out Ks_Status)
   is
      R1 : constant Long_Float := Line_1.Rotation;
      R2 : constant Long_Float := Line_2.Rotation;
   begin
      Result := 0.0;
      Set_Success (Status);
      Require_Line ("Angle_Between", "Line_1", Line_1, Status);
      Require_Line ("Angle_Between", "Line_2", Line_2, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if abs R1 <= Long_Float'Last / 2.0 and then abs R2 <= Long_Float'Last / 2.0
      then
         Result := N.Reduce_Two_Pi (R2 - R1);
      else
         --  R2 - R1 might overflow: reduce each angle first, as
         --  ks_misc_angle_difference does.
         Result := N.Reduce_Two_Pi (N.Reduce_Two_Pi (R2) - N.Reduce_Two_Pi (R1));
      end if;
   end Angle_Between;

   ---------------------------------------------------------------------
   --  Scatter of the points
   ---------------------------------------------------------------------

   type Scatter_Info is record
      Count         : Natural := 0;
      Centroid      : Ks_Point_2D;
      Exponent      : Integer := 0;
      --  Offsets from the centroid are used scaled by 2**(-Exponent),
      --  which brings the largest into [0.5, 1).
      Sxx, Syy, Sxy : Long_Float := 0.0;
      --  Second moments of the scaled offsets.
      Scale         : Long_Float := 0.0;
      --  The largest coordinate magnitude, scaled likewise.
      Rotation      : Long_Float := 0.0;
      --  Principal direction (see Principal_Direction).
   end record;

   function Bounded_Info (Info : Scatter_Info) return Boolean is
     (Info.Count in 2 .. Max_Points
      and then Bounded (Info.Centroid)
      and then Info.Exponent in -1074 .. 501
      and then Info.Sxx >= 0.0 and then Info.Sxx <= Moment_Limit
      and then Info.Syy >= 0.0 and then Info.Syy <= Moment_Limit
      and then abs Info.Sxy <= Moment_Limit
      and then Info.Scale >= 0.0 and then Info.Scale <= 2.0 ** 61
      and then Info.Rotation > -N.Half_Pi
      and then Info.Rotation <= N.Half_Pi);
   --  What a successful Analyse_Scatter gives.

   function Offset_X
     (Info : Scatter_Info; P : Ks_Point_2D) return Long_Float
   is
     (Scaled_Offset (P.X - Info.Centroid.X, Info.Exponent))
   with Pre  => Bounded_Info (Info) and then Bounded (P),
        Post => abs Offset_X'Result <= 1.0;
   --  The scaled x offset of P from the centroid.

   function Offset_Y
     (Info : Scatter_Info; P : Ks_Point_2D) return Long_Float
   is
     (Scaled_Offset (P.Y - Info.Centroid.Y, Info.Exponent))
   with Pre  => Bounded_Info (Info) and then Bounded (P),
        Post => abs Offset_Y'Result <= 1.0;

   function Principal_Direction (Sxx, Syy, Sxy, Level : Long_Float)
      return Long_Float
   with Pre  => abs Sxx <= Moment_Limit and then abs Syy <= Moment_Limit
                and then abs Sxy <= Moment_Limit,
        Post => Principal_Direction'Result > -N.Half_Pi
                and then Principal_Direction'Result <= N.Half_Pi;
   --  The direction in (-Pi/2, Pi/2] of the major axis of the scatter
   --  matrix [Sxx Sxy; Sxy Syy]; 0 when the scatter is isotropic, that is
   --  when |Sxx - Syy| + 2 |Sxy| (between 1 and Sqrt (2) times the
   --  difference of the eigenvalues) is at most Level.

   function Principal_Direction (Sxx, Syy, Sxy, Level : Long_Float)
      return Long_Float is
   begin
      if abs (Sxx - Syy) + 2.0 * abs Sxy <= Level
        or else (Sxx = Syy and then Sxy = 0.0)
      then
         return 0.0;
      end if;
      --  The major eigenvector of a symmetric 2x2 matrix makes the angle
      --  0.5 * atan2 (2 Sxy, Sxx - Syy) with the x axis; a negative zero
      --  Sxy can produce -Pi/2, which the reduction maps to Pi/2.
      return N.Reduce_Pi (0.5 * EF.Arctan (2.0 * Sxy, Sxx - Syy));
   end Principal_Direction;

   procedure Analyse_Scatter
     (Points    : Point_Array;
      Mask      : Flag_Array;
      Min_Count : Positive;
      Info      : out Scatter_Info;
      Status    : out Fit_Status)
   with
     Pre  => Points'Length <= Max_Points and then Mask_Fits (Points, Mask)
             and then Min_Count in 2 .. 3,
     Post => Info.Count <= Max_Points
             and then (if Status = Fit_Ok
                       then Bounded_Info (Info) and then Info.Count >= Min_Count);
   --  Counts the selected points, computes their centroid, scaled second
   --  moments and principal direction, and reports too few or coincident
   --  points. Info.Count is set even on failure.

   procedure Analyse_Scatter
     (Points    : Point_Array;
      Mask      : Flag_Array;
      Min_Count : Positive;
      Info      : out Scatter_Info;
      Status    : out Fit_Status)
   is
      Reference     : Ks_Point_2D := Origin;
      Count         : Natural := 0;
      Sum_X, Sum_Y  : Long_Float := 0.0;
      Scale         : Long_Float := 0.0;
      Largest       : Long_Float := 0.0;
      Centroid      : Ks_Point_2D;
      E             : Integer;
      P             : Ks_Point_2D;
      DX, DY        : Long_Float;
      Sxx, Syy, Sxy : Long_Float := 0.0;
      Spread        : Long_Float;
      Ratio         : Long_Float;
      Fits          : Boolean;
      Root_N        : Long_Float;
   begin
      Info := (others => <>);
      Status := Fit_Ok;

      --  Sum offsets from the first selected point rather than raw
      --  coordinates: identical points then give exactly zero spread, and
      --  large coordinates lose less precision.
      for I in Points'Range loop
         pragma Loop_Invariant
           (Count <= I - Points'First
            and then Bounded (Reference)
            and then abs Sum_X <= Offset_Sum_Limit
            and then abs Sum_Y <= Offset_Sum_Limit
            and then Scale >= 0.0 and then Scale <= Max_Coordinate);
         if Selected (Mask, I) then
            P := Point_At (Points, I);
            if Count = 0 then
               Reference := P;
            end if;
            Count := Count + 1;
            Sum_X := N.Clamp (Sum_X + (P.X - Reference.X), Offset_Sum_Limit);
            Sum_Y := N.Clamp (Sum_Y + (P.Y - Reference.Y), Offset_Sum_Limit);
            Scale := Long_Float'Max
              (Scale, Long_Float'Max (abs P.X, abs P.Y));
         end if;
      end loop;

      Info.Count := Count;
      if Count < Min_Count then
         Status := Too_Few_Points;
         return;
      end if;

      --  The centroid lies within the range of the points; rounding could
      --  carry it an ulp beyond the bound, where it is clamped.
      Centroid :=
        (X => N.Clamp (Reference.X + Sum_X / Long_Float (Count),
                       Max_Coordinate),
         Y => N.Clamp (Reference.Y + Sum_Y / Long_Float (Count),
                       Max_Coordinate));
      Info.Centroid := Centroid;

      for I in Points'Range loop
         pragma Loop_Invariant
           (Largest >= 0.0 and then Largest <= 2.0 * Max_Coordinate);
         if Selected (Mask, I) then
            P := Point_At (Points, I);
            Largest := Long_Float'Max
              (Largest,
               Long_Float'Max (abs (P.X - Centroid.X),
                               abs (P.Y - Centroid.Y)));
         end if;
      end loop;
      if Largest = 0.0 then
         Status := Coincident_Points;
         return;
      end if;
      E := Exponent_Of (Largest);
      Info.Exponent := E;

      for I in Points'Range loop
         pragma Loop_Invariant
           (Sxx >= 0.0 and then Sxx <= Moment_Limit
            and then Syy >= 0.0 and then Syy <= Moment_Limit
            and then abs Sxy <= Moment_Limit);
         if Selected (Mask, I) then
            P := Point_At (Points, I);
            DX := Offset_X (Info, P);
            DY := Offset_Y (Info, P);
            Sxx := Long_Float'Min
              (Sxx + N.Square_Within (DX, 1.0), Moment_Limit);
            Syy := Long_Float'Min
              (Syy + N.Square_Within (DY, 1.0), Moment_Limit);
            Sxy := N.Clamp (Sxy + N.Mul_Within (DX, DY, 1.0, 1.0),
                            Moment_Limit);
         end if;
      end loop;

      --  Coincidence: RMS spread <= Coincidence_Tolerance * Scale, compared
      --  in scaled units. The offsets are at most twice the coordinates, so
      --  the exponent gap is at least -2 and the scaled Scale stays below
      --  2**60.
      if Scale > 0.0 and then Exponent_Of (Scale) - E > Max_Exponent_Gap then
         Status := Coincident_Points;
         return;
      end if;
      Info.Scale := Scaled_Scale (Scale, E);
      --  The mean of DX**2 + DY**2 is at most 2; the limit states it for
      --  the prover and never acts.
      Spread := Long_Float'Min
        (EF.Sqrt ((Sxx + Syy) / Long_Float (Count)), 2.0);
      if Spread <= Coincidence_Tolerance * Info.Scale then
         Status := Coincident_Points;
         return;
      end if;

      Info.Sxx := Sxx;
      Info.Syy := Syy;
      Info.Sxy := Sxy;
      --  Info.Scale / Spread < 1 / Coincidence_Tolerance here, so the
      --  quotient always fits; Sqrt (Count) is below 2**16.
      N.Ratio_Within (Info.Scale, Spread, 2.0 ** 41, Ratio, Fits);
      if not Fits then
         Ratio := 2.0 ** 41;
      end if;
      Root_N := Long_Float'Min (EF.Sqrt (Long_Float (Count)), 2.0 ** 16);
      Info.Rotation := Principal_Direction
        (Sxx, Syy, Sxy,
         N.Mul_Within (Isotropy_Tolerance * (Root_N + Ratio), Sxx + Syy,
                       1.0, 2.0 * Moment_Limit));
   end Analyse_Scatter;

   ---------------------------------------------------------------------
   --  Line fitting
   ---------------------------------------------------------------------

   procedure Fit_Line_Core
     (Points    : Point_Array;
      Mask      : Flag_Array;
      Line      : out Ks_Line_2D;
      RMS_Error : out Long_Float;
      Info      : out Scatter_Info;
      Status    : out Fit_Status)
   with
     Pre  => Points'Length <= Max_Points and then Mask_Fits (Points, Mask),
     Post => Info.Count <= Max_Points
             and then Bounded (Line.X) and then Bounded (Line.Y)
             and then Line.Rotation > -N.Half_Pi
             and then Line.Rotation <= N.Half_Pi
             and then RMS_Error >= 0.0 and then RMS_Error <= 2.0 ** 1020
             and then (if Status = Fit_Ok then Bounded_Info (Info));
   --  Orthogonal regression over the points selected by Mask. On failure
   --  Line and RMS_Error are zero.

   procedure Fit_Line_Core
     (Points    : Point_Array;
      Mask      : Flag_Array;
      Line      : out Ks_Line_2D;
      RMS_Error : out Long_Float;
      Info      : out Scatter_Info;
      Status    : out Fit_Status)
   is
      C, S     : Long_Float;
      P        : Ks_Point_2D;
      Residual : Long_Float;
      Sum_Sq   : Long_Float := 0.0;
   begin
      Line := (others => 0.0);
      RMS_Error := 0.0;
      Analyse_Scatter (Points, Mask, 2, Info, Status);
      if Status /= Fit_Ok then
         return;
      end if;
      C := EF.Cos (Info.Rotation);
      S := EF.Sin (Info.Rotation);
      --  Residuals are computed directly rather than from the smaller
      --  eigenvalue, which would suffer from cancellation for good fits.
      --  They are formed from scaled offsets and scaled back at the end.
      for I in Points'Range loop
         pragma Loop_Invariant
           (Sum_Sq >= 0.0 and then Sum_Sq <= Moment_Limit);
         if Selected (Mask, I) then
            P := Point_At (Points, I);
            Residual := N.Times_Unit (Offset_Y (Info, P), C)
                        - N.Times_Unit (Offset_X (Info, P), S);
            Sum_Sq := Long_Float'Min
              (Sum_Sq + N.Square_Within (Residual, 2.0), Moment_Limit);
         end if;
      end loop;
      Line := (X        => Info.Centroid.X,
               Y        => Info.Centroid.Y,
               Rotation => Info.Rotation);
      --  The RMS residual is at most Sqrt (2) (scaled units); the limit
      --  states it for the prover and never acts.
      RMS_Error := Long_Float'Max
        (0.0,
         Unscaled (Long_Float'Min (EF.Sqrt (Sum_Sq / Long_Float (Info.Count)),
                                   2.0),
                   Info.Exponent));
   end Fit_Line_Core;

   ---------------------------------------------------------------------
   --  Circle fitting
   ---------------------------------------------------------------------

   --  The work is done in a frame centred on the centroid and aligned with
   --  the principal axes of the scatter (T along the best line, R across
   --  it), with the offsets scaled by 2**(-Info.Exponent). In that frame
   --  the scatter matrix is diagonal up to rounding, so the algebraic fit
   --  stays well conditioned even for short arcs whose centre lies far
   --  away on the R axis, and its third and fourth moments stay in range
   --  whatever the size of the coordinates.
   --
   --  Refinement minimises sum (d_i - mean d)**2 over the centre (A, B),
   --  where d_i is the distance from point i to the centre; the optimal
   --  radius for a given centre is the mean distance, so only the two
   --  centre coordinates are iterated.

   type Frame is record
      Info         : Scatter_Info;
      Cos_T, Sin_T : Long_Float := 0.0;
      N            : Long_Float := 0.0;
      Limit        : Long_Float := 0.0;
      --  A trial centre further than this from the centroid has run off.
   end record;

   function Valid_Frame (F : Frame) return Boolean is
     (Bounded_Info (F.Info)
      and then abs F.Cos_T <= 1.0 and then abs F.Sin_T <= 1.0
      and then F.N >= 1.0 and then F.N <= Long_Float (Max_Points)
      and then F.Limit >= 0.0 and then F.Limit <= Centre_Bound);

   procedure To_Frame
     (F    : Frame;
      P    : Ks_Point_2D;
      T, R : out Long_Float)
   with Pre  => Valid_Frame (F) and then Bounded (P),
        Post => abs T <= 2.0 and then abs R <= 2.0;
   --  P in the principal frame (scaled units).

   procedure To_Frame
     (F    : Frame;
      P    : Ks_Point_2D;
      T, R : out Long_Float)
   is
      DX : constant Long_Float := Offset_X (F.Info, P);
      DY : constant Long_Float := Offset_Y (F.Info, P);
   begin
      T := N.Times_Unit (DX, F.Cos_T) + N.Times_Unit (DY, F.Sin_T);
      R := N.Times_Unit (DY, F.Cos_T) - N.Times_Unit (DX, F.Sin_T);
   end To_Frame;

   type Evaluation is record
      A, B          : Long_Float := 0.0;
      --  Trial centre in the frame.
      Cost          : Long_Float := 0.0;
      --  sum r_i**2 with r_i = d_i - Radius.
      Radius        : Long_Float := 0.0;
      --  Optimal radius for this centre: the mean distance.
      H11, H12, H22 : Long_Float := 0.0;
      --  Gauss-Newton matrix J'J.
      G1, G2        : Long_Float := 0.0;
      --  Gradient J'r (half the gradient of Cost).
      C11, C12, C22 : Long_Float := 0.0;
      --  sum r_i * Hessian (d_i); J'J plus this is half the true Hessian
      --  of Cost.
   end record;

   function Bounded_Evaluation (E : Evaluation) return Boolean is
     (abs E.A <= Centre_Bound and then abs E.B <= Centre_Bound
      and then E.Cost >= 0.0 and then E.Cost <= Cost_Bound
      and then E.Radius >= 0.0 and then E.Radius <= Radius_Bound
      and then E.H11 >= 0.0 and then E.H11 <= Moment_Limit
      and then abs E.H12 <= Moment_Limit
      and then E.H22 >= 0.0 and then E.H22 <= Moment_Limit
      and then abs E.G1 <= Gradient_Bound and then abs E.G2 <= Gradient_Bound
      and then abs E.C11 <= Curvature_Bound
      and then abs E.C12 <= Curvature_Bound
      and then abs E.C22 <= Curvature_Bound);

   function Evaluate
     (Points : Point_Array;
      Mask   : Flag_Array;
      F      : Frame;
      A, B   : Long_Float) return Evaluation
   with Pre  => Valid_Frame (F) and then Mask_Fits (Points, Mask)
                and then abs A <= F.Limit and then abs B <= F.Limit,
        Post => Bounded_Evaluation (Evaluate'Result)
                and then Evaluate'Result.A = A
                and then Evaluate'Result.B = B;
   --  Everything the refinement needs at the centre (A, B). With u_i the
   --  unit vector from the centre to point i, d_i has gradient -u_i and
   --  Hessian (I - u_i u_i') / d_i with respect to the centre, so the
   --  Jacobian row of r_i is mean u - u_i. The sum of r_i times the Hessian
   --  of the mean distance vanishes because sum r_i = 0.

   function Evaluate
     (Points : Point_Array;
      Mask   : Flag_Array;
      F      : Frame;
      A, B   : Long_Float) return Evaluation
   is
      E                : Evaluation;
      P                : Ks_Point_2D;
      T, R, Dist, U, V : Long_Float;
      Res, DU, DV, W   : Long_Float;
      Fits             : Boolean;
      Sum_Dist         : Long_Float := 0.0;
      Sum_U, Sum_V     : Long_Float := 0.0;
      Mean_U, Mean_V   : Long_Float;
   begin
      E.A := A;
      E.B := B;
      for I in Points'Range loop
         pragma Loop_Invariant
           (Sum_Dist >= 0.0 and then Sum_Dist <= 2.0 ** 70
            and then abs Sum_U <= Moment_Limit
            and then abs Sum_V <= Moment_Limit
            and then E.A = A and then E.B = B);
         if Selected (Mask, I) then
            P := Point_At (Points, I);
            To_Frame (F, P, T, R);
            Direction (T - A, R - B, Dist, U, V);
            Sum_Dist := Long_Float'Min (Sum_Dist + Dist, 2.0 ** 70);
            Sum_U := N.Clamp (Sum_U + U, Moment_Limit);
            Sum_V := N.Clamp (Sum_V + V, Moment_Limit);
         end if;
      end loop;
      --  The mean distance is at most about 2 Limit + 3, the means of the
      --  unit vectors at most 1 in magnitude; the limits state that for the
      --  prover and never act.
      E.Radius := Long_Float'Min (Sum_Dist / F.N, Radius_Bound);
      Mean_U := N.Clamp (Sum_U / F.N, 1.0);
      Mean_V := N.Clamp (Sum_V / F.N, 1.0);

      --  A second pass forms the centred sums directly: for short arcs
      --  the u_i are nearly equal and sum (u_i**2) - N * mean**2 would
      --  cancel badly.
      for I in Points'Range loop
         pragma Loop_Invariant
           (Bounded_Evaluation (E) and then E.A = A and then E.B = B
            and then E.Radius = E.Radius'Loop_Entry);
         if Selected (Mask, I) then
            P := Point_At (Points, I);
            To_Frame (F, P, T, R);
            Direction (T - A, R - B, Dist, U, V);
            Dist := Long_Float'Min (Dist, Distance_Bound);
            Res := Dist - E.Radius;
            DU := Mean_U - U;
            DV := Mean_V - V;
            E.Cost := Long_Float'Min
              (E.Cost + N.Square_Within (Res, 2.0 * Radius_Bound),
               Cost_Bound);
            E.H11 := Long_Float'Min
              (E.H11 + N.Square_Within (DU, 2.0), Moment_Limit);
            E.H12 := N.Clamp (E.H12 + N.Mul_Within (DU, DV, 2.0, 2.0),
                              Moment_Limit);
            E.H22 := Long_Float'Min
              (E.H22 + N.Square_Within (DV, 2.0), Moment_Limit);
            E.G1 := N.Clamp
              (E.G1 + N.Mul_Within (DU, Res, 2.0, 2.0 * Radius_Bound),
               Gradient_Bound);
            E.G2 := N.Clamp
              (E.G2 + N.Mul_Within (DV, Res, 2.0, 2.0 * Radius_Bound),
               Gradient_Bound);
            --  The curvature of d_i is unbounded at Dist = 0 (a kink); such
            --  a point contributes nothing here, and neither does one so
            --  close to the centre that Res / Dist exceeds Weight_Limit.
            if Dist > 0.0 then
               N.Ratio_Within (abs Res, Dist, Weight_Limit, W, Fits);
               if Fits then
                  if Res < 0.0 then
                     W := -W;
                  end if;
                  E.C11 := N.Clamp
                    (E.C11 + N.Mul_Within (W, 1.0 - N.Square_Within (U, 1.0),
                                           Weight_Limit, 1.0),
                     Curvature_Bound);
                  E.C12 := N.Clamp
                    (E.C12 - N.Mul_Within (N.Mul_Within (W, U, Weight_Limit,
                                                         1.0),
                                           V, Weight_Limit, 1.0),
                     Curvature_Bound);
                  E.C22 := N.Clamp
                    (E.C22 + N.Mul_Within (W, 1.0 - N.Square_Within (V, 1.0),
                                           Weight_Limit, 1.0),
                     Curvature_Bound);
               end if;
            end if;
         end if;
      end loop;
      return E;
   end Evaluate;

   procedure Try
     (Points  : Point_Array;
      Mask    : Flag_Array;
      F       : Frame;
      A, B    : Long_Float;
      Trial   : out Evaluation;
      Runaway : in out Boolean)
   with Pre  => Valid_Frame (F) and then Mask_Fits (Points, Mask)
                and then abs A <= 2.0 ** 42 and then abs B <= 2.0 ** 42,
        Post => Bounded_Evaluation (Trial)
                and then (if not Runaway
                          then abs Trial.A <= F.Limit
                               and then abs Trial.B <= F.Limit)
                and then (if Runaway'Old then Runaway);
   --  Evaluate, unless the centre has run off beyond Limit (then Runaway
   --  is set and Trial is not evaluated). A coordinate beyond Limit puts
   --  the centre beyond it too; the test of the coordinates states that
   --  for the prover and changes nothing.

   procedure Try
     (Points  : Point_Array;
      Mask    : Flag_Array;
      F       : Frame;
      A, B    : Long_Float;
      Trial   : out Evaluation;
      Runaway : in out Boolean) is
   begin
      if abs A > F.Limit or else abs B > F.Limit
        or else N.Hypot (A, B) > F.Limit
      then
         Runaway := True;
         Trial := (others => <>);
      else
         Trial := Evaluate (Points, Mask, F, A, B);
      end if;
   end Try;

   procedure Signed_Quotient
     (Num, Den : Long_Float;
      Limit    : Long_Float;
      Result   : out Long_Float;
      Fits     : out Boolean)
   with Pre  => abs Num <= N.Mul_Limit and then Den > 0.0
                and then Den <= N.Mul_Limit
                and then Limit >= 1.0 and then Limit <= N.Mul_Limit,
        Post => abs Result <= Limit
                and then (if not Fits then Result = 0.0);
   --  Result := Num / Den and Fits := True when its magnitude is at most
   --  Limit; otherwise Fits := False and Result := 0.0.

   procedure Signed_Quotient
     (Num, Den : Long_Float;
      Limit    : Long_Float;
      Result   : out Long_Float;
      Fits     : out Boolean) is
   begin
      N.Ratio_Within (abs Num, Den, Limit, Result, Fits);
      if Num < 0.0 then
         Result := -Result;
      end if;
   end Signed_Quotient;

   procedure Newton_Trial
     (Points         : Point_Array;
      Mask           : Flag_Array;
      F              : Frame;
      Current        : Evaluation;
      Step_A, Step_B : out Long_Float;
      Trial          : out Evaluation;
      Lowers         : out Boolean)
   with Pre  => Valid_Frame (F) and then Mask_Fits (Points, Mask)
                and then Bounded_Evaluation (Current)
                and then abs Current.A <= F.Limit
                and then abs Current.B <= F.Limit,
        Post => abs Step_A <= Step_Limit and then abs Step_B <= Step_Limit
                and then Bounded_Evaluation (Trial)
                and then (if Lowers
                          then abs Trial.A <= F.Limit
                               and then abs Trial.B <= F.Limit);
   --  The full Newton step from Current, on the true Hessian F = J'J + C
   --  of the cost (halved, like the gradient G). Lowers is True when the
   --  step was eligible and Trial, the evaluation at its end, has a lower
   --  cost than Current. The step is eligible when F is positive definite,
   --  the step ends within Limit (a Newton step beyond it is simply not
   --  taken; it does not count as a runaway centre) and either it is at
   --  least as long as the undamped Gauss-Newton step (J'J)**(-1) G (the
   --  residual curvature then works against Gauss-Newton, which converges
   --  only linearly), or it is local, no longer than Local_Step_Fraction
   --  times the radius, so the quadratic model it relies on holds.
   --  Otherwise Gauss-Newton is left in charge (see AMV.Geometry).

   procedure Newton_Trial
     (Points         : Point_Array;
      Mask           : Flag_Array;
      F              : Frame;
      Current        : Evaluation;
      Step_A, Step_B : out Long_Float;
      Trial          : out Evaluation;
      Lowers         : out Boolean)
   is
      F_Bound : constant := Moment_Limit + Curvature_Bound;
      F11    : constant Long_Float := Current.H11 + Current.C11;
      F12    : constant Long_Float := Current.H12 + Current.C12;
      F22    : constant Long_Float := Current.H22 + Current.C22;
      Det_F  : constant Long_Float :=
        N.Mul_Within (F11, F22, F_Bound, F_Bound)
        - N.Mul_Within (F12, F12, F_Bound, F_Bound);
      Num_A  : constant Long_Float :=
        N.Mul_Within (F12, Current.G2, F_Bound, Gradient_Bound)
        - N.Mul_Within (F22, Current.G1, F_Bound, Gradient_Bound);
      Num_B  : constant Long_Float :=
        N.Mul_Within (F12, Current.G1, F_Bound, Gradient_Bound)
        - N.Mul_Within (F11, Current.G2, F_Bound, Gradient_Bound);
      Det_H  : constant Long_Float :=
        N.Mul_Within (Current.H11, Current.H22, Moment_Limit, Moment_Limit)
        - N.Mul_Within (Current.H12, Current.H12, Moment_Limit,
                        Moment_Limit);
      GN_A   : constant Long_Float :=
        N.Mul_Within (Current.H12, Current.G2, Moment_Limit, Gradient_Bound)
        - N.Mul_Within (Current.H22, Current.G1, Moment_Limit,
                        Gradient_Bound);
      GN_B   : constant Long_Float :=
        N.Mul_Within (Current.H12, Current.G1, Moment_Limit, Gradient_Bound)
        - N.Mul_Within (Current.H11, Current.G2, Moment_Limit,
                        Gradient_Bound);
      Bound  : Long_Float;
      Length : Long_Float;
      Fits_A : Boolean;
      Fits_B : Boolean;
   begin
      Step_A := 0.0;
      Step_B := 0.0;
      Trial := (others => <>);
      Lowers := False;
      if not (F11 > 0.0 and then Det_F > 0.0) then
         return;
      end if;
      --  A step longer than 2 * Limit cannot end within Limit (the
      --  current centre lies within it), so such steps are not formed:
      --  this also keeps the division from overflowing.
      Bound := N.Mul_Within (2.0 * F.Limit, Det_F, 2.0 * Centre_Bound,
                             2.0 * F_Bound * F_Bound);
      if abs Num_A > Bound or else abs Num_B > Bound then
         return;
      end if;
      --  The quotients are at most 2 * Limit; they always fit.
      Signed_Quotient (Num_A, Det_F, Step_Limit, Step_A, Fits_A);
      Signed_Quotient (Num_B, Det_F, Step_Limit, Step_B, Fits_B);
      if not (Fits_A and then Fits_B) then
         return;
      end if;
      Length := N.Hypot (Step_A, Step_B);
      --  |Newton| >= |Gauss-Newton| is compared without dividing:
      --  |Num| / Det_F >= |GN| / Det_H. Det_H <= 0 means an unbounded
      --  Gauss-Newton step, which the Newton step never beats.
      if not (Length <= Local_Step_Fraction * Current.Radius
              or else (Det_H > 0.0
                       and then N.Mul_Within
                                  (N.Hypot (Num_A, Num_B), Det_H,
                                   2.0 ** 184, 2.0 * Moment_Limit
                                                 * Moment_Limit)
                                >= N.Mul_Within
                                     (N.Hypot (GN_A, GN_B), Det_F,
                                      2.0 ** 123,
                                      2.0 * F_Bound * F_Bound)))
      then
         return;
      end if;
      if abs (Current.A + Step_A) > F.Limit
        or else abs (Current.B + Step_B) > F.Limit
        or else N.Hypot (Current.A + Step_A, Current.B + Step_B) > F.Limit
      then
         return;
      end if;
      Trial := Evaluate (Points, Mask, F, Current.A + Step_A,
                         Current.B + Step_B);
      Lowers := Trial.Cost < Current.Cost;
   end Newton_Trial;

   procedure Descend
     (Points  : Point_Array;
      Mask    : Flag_Array;
      F       : Frame;
      Current : in out Evaluation;
      Runaway : in out Boolean)
   with Pre  => Valid_Frame (F) and then Mask_Fits (Points, Mask)
                and then Bounded_Evaluation (Current)
                and then abs Current.A <= F.Limit
                and then abs Current.B <= F.Limit,
        Post => Bounded_Evaluation (Current)
                and then abs Current.A <= F.Limit
                and then abs Current.B <= F.Limit
                and then (if Runaway'Old then Runaway);
   --  Iterations from Current until the step is negligible, no step
   --  lowers the cost, the iteration cap, or a runaway centre. Each
   --  iteration takes the Newton step when it is eligible and lowers the
   --  cost (see Newton_Trial), and otherwise a Gauss-Newton step damped in
   --  the Levenberg-Marquardt manner.

   procedure Descend
     (Points  : Point_Array;
      Mask    : Flag_Array;
      F       : Frame;
      Current : in out Evaluation;
      Runaway : in out Boolean)
   is
      Trial          : Evaluation;
      Step_A, Step_B : Long_Float;
      M11, M22       : Long_Float;
      Floor, Det     : Long_Float;
      Num_A, Num_B   : Long_Float;
      Lambda         : Long_Float := Initial_Damping;
      Accepted       : Boolean;
      Fits_A, Fits_B : Boolean;
      Step_Bound     : constant Long_Float :=
        Long_Float'Max (1.0, 2.0 * F.Limit);
   begin
      for Iteration in 1 .. Max_Circle_Iterations loop
         pragma Loop_Invariant
           (Bounded_Evaluation (Current)
            and then abs Current.A <= F.Limit
            and then abs Current.B <= F.Limit
            and then Lambda >= Min_Damping
            and then Lambda <= Max_Damping
            and then (if Runaway'Loop_Entry then Runaway));
         exit when Current.Cost
                   <= N.Mul_Within
                        (F.N, N.Square_Within
                                (Exact_Fit_Tolerance * Current.Radius, 1.0),
                         Long_Float (Max_Points), 1.0);

         Newton_Trial (Points, Mask, F, Current, Step_A, Step_B, Trial,
                       Accepted);
         if Accepted then
            Current := Trial;
         else
            Damping : loop
               pragma Loop_Invariant
                 (Bounded_Evaluation (Current)
                  and then abs Current.A <= F.Limit
                  and then abs Current.B <= F.Limit
                  and then Lambda >= Min_Damping
                  and then Lambda <= Max_Damping
                  and then abs Step_A <= Step_Limit
                  and then abs Step_B <= Step_Limit
                  and then not Accepted
                  and then (if Runaway'Loop_Entry then Runaway));
               --  Marquardt scaling of the diagonal, with a small floor so
               --  that a vanishing diagonal entry is still damped.
               Floor := 1.0E-15 * (Current.H11 + Current.H22);
               M11 := Current.H11
                      + N.Mul_Within (Lambda,
                                      Long_Float'Max (Current.H11, Floor),
                                      Max_Damping, Moment_Limit);
               M22 := Current.H22
                      + N.Mul_Within (Lambda,
                                      Long_Float'Max (Current.H22, Floor),
                                      Max_Damping, Moment_Limit);
               Det := N.Mul_Within (M11, M22, 2.0 ** 81, 2.0 ** 81)
                      - N.Mul_Within (Current.H12, Current.H12,
                                      Moment_Limit, Moment_Limit);
               if Det > 0.0 then
                  Num_A := N.Mul_Within (Current.H12, Current.G2,
                                         Moment_Limit, Gradient_Bound)
                           - N.Mul_Within (M22, Current.G1,
                                           2.0 ** 81, Gradient_Bound);
                  Num_B := N.Mul_Within (Current.H12, Current.G1,
                                         Moment_Limit, Gradient_Bound)
                           - N.Mul_Within (M11, Current.G2,
                                           2.0 ** 81, Gradient_Bound);
                  --  A step longer than 2 * Limit puts the centre beyond
                  --  Limit (the current centre lies within it): the centre
                  --  has run off, as the evaluation of the trial would
                  --  find.
                  Signed_Quotient (Num_A, Det, Step_Bound, Step_A, Fits_A);
                  Signed_Quotient (Num_B, Det, Step_Bound, Step_B, Fits_B);
                  if not (Fits_A and then Fits_B) then
                     Runaway := True;
                     return;
                  end if;
                  Try (Points, Mask, F, Current.A + Step_A,
                       Current.B + Step_B, Trial, Runaway);
                  if Runaway then
                     return;
                  end if;
                  if Trial.Cost <= Current.Cost then
                     Current := Trial;
                     Lambda := Long_Float'Max (0.1 * Lambda, Min_Damping);
                     Accepted := True;
                     exit Damping;
                  end if;
               end if;
               Lambda := 10.0 * Lambda;
               exit Damping when Lambda > Max_Damping;
            end loop Damping;
         end if;

         --  Stop when no step reduces the cost any more (the minimum has
         --  been reached to working precision) or the step is negligible.
         exit when not Accepted
           or else N.Hypot (Step_A, Step_B)
                   <= Circle_Step_Tolerance * Current.Radius;
      end loop;
   end Descend;

   procedure Escape_Saddle
     (Points  : Point_Array;
      Mask    : Flag_Array;
      F       : Frame;
      Current : in out Evaluation;
      Runaway : in out Boolean;
      Escaped : out Boolean)
   with Pre  => Valid_Frame (F) and then Mask_Fits (Points, Mask)
                and then Bounded_Evaluation (Current)
                and then abs Current.A <= F.Limit
                and then abs Current.B <= F.Limit,
        Post => Bounded_Evaluation (Current)
                and then abs Current.A <= F.Limit
                and then abs Current.B <= F.Limit
                and then (if Runaway'Old then Runaway);
   --  When Current is a stationary point with negative curvature (a
   --  saddle, which symmetric input can produce exactly), moves Current
   --  downhill along the most negative curvature direction and sets
   --  Escaped; Escaped is False at a minimum or when the centre runs off.

   procedure Escape_Saddle
     (Points  : Point_Array;
      Mask    : Flag_Array;
      F       : Frame;
      Current : in out Evaluation;
      Runaway : in out Boolean;
      Escaped : out Boolean)
   is
      F11  : constant Long_Float := Current.H11 + Current.C11;
      F12  : constant Long_Float := Current.H12 + Current.C12;
      F22  : constant Long_Float := Current.H22 + Current.C22;
      Low  : constant Long_Float :=
        0.5 * (F11 + F22) - N.Hypot (0.5 * (F11 - F22), F12);
      EX, EY, Length : Long_Float;
      Step           : Long_Float;
      Sign           : Long_Float;
      Trial          : Evaluation;
   begin
      Escaped := False;
      if Low >= -Curvature_Tolerance * (Current.H11 + Current.H22) then
         return;
      end if;
      --  Eigenvector of [F11 F12; F12 F22] for Low: take the better
      --  conditioned of the two equivalent forms.
      if abs (Low - F11) >= abs (Low - F22) then
         EX := F12;
         EY := Low - F11;
      else
         EX := Low - F22;
         EY := F12;
      end if;
      Length := N.Hypot (EX, EY);
      if Length = 0.0 then
         return;
      end if;
      EX := Unit_Quotient (EX, Length);
      EY := Unit_Quotient (EY, Length);

      Step := Current.Radius;
      for Halving in 1 .. 40 loop
         pragma Loop_Invariant
           (Bounded_Evaluation (Current)
            and then abs Current.A <= F.Limit
            and then abs Current.B <= F.Limit
            and then Step >= 0.0 and then Step <= Radius_Bound
            and then not Escaped
            and then (if Runaway'Loop_Entry then Runaway));
         for Side in 1 .. 2 loop
            pragma Loop_Invariant
              (Bounded_Evaluation (Current)
               and then abs Current.A <= F.Limit
               and then abs Current.B <= F.Limit
               and then Step >= 0.0 and then Step <= Radius_Bound
               and then not Escaped
               and then (if Runaway'Loop_Entry then Runaway));
            Sign := (if Side = 1 then 1.0 else -1.0);
            Try (Points, Mask, F,
                 Current.A + N.Times_Unit (Sign * Step, EX),
                 Current.B + N.Times_Unit (Sign * Step, EY), Trial, Runaway);
            if Runaway then
               return;
            end if;
            if Trial.Cost < Current.Cost then
               Current := Trial;
               Escaped := True;
               return;
            end if;
         end loop;
         Step := 0.5 * Step;
      end loop;
   end Escape_Saddle;

   type Circle_Fit is record
      Status    : Fit_Status := Fit_Ok;
      Info      : Scatter_Info;
      Circle    : Ks_Circle_2D;
      RMS_Error : Long_Float := 0.0;
      Cost      : Long_Float := 0.0;
      --  Sum of squared radial residuals of the offsets scaled by
      --  2**(-Info.Exponent).
   end record;

   function Valid_Fit (Fit : Circle_Fit) return Boolean is
     (Fit.Circle.Radius >= 0.0
      and then Fit.RMS_Error >= 0.0
      and then (if Fit.Status = Fit_Ok
                then Bounded_Info (Fit.Info)
                     and then Fit.Cost >= 0.0
                     and then Fit.Cost <= Cost_Bound));

   procedure Fit_Circle_Core
     (Points : Point_Array;
      Mask   : Flag_Array;
      Fit    : out Circle_Fit)
   with
     Pre  => Points'Length <= Max_Points and then Mask_Fits (Points, Mask),
     Post => Valid_Fit (Fit);
   --  Geometric circle fit over the points selected by Mask.

   procedure Fit_Circle_Core
     (Points : Point_Array;
      Mask   : Flag_Array;
      Fit    : out Circle_Fit)
   is
      Info          : Scatter_Info;
      Status        : Fit_Status;
      F             : Frame;
      P             : Ks_Point_2D;
      T, R, Z       : Long_Float;
      Stt, Srr      : Long_Float := 0.0;
      Str, Stz, Srz : Long_Float := 0.0;
      Det           : Long_Float;
      Num_A, Num_B  : Long_Float;
      A0, B0        : Long_Float;
      Fits_A        : Boolean;
      Fits_B        : Boolean;
      Current       : Evaluation;
      Runaway       : Boolean := False;
      --  Set when a trial centre has run off beyond Limit: the fit is then
      --  given up as too close to collinear.
      Escaped       : Boolean;
   begin
      Fit := (others => <>);
      Analyse_Scatter (Points, Mask, 3, Info, Status);
      Fit.Info := Info;
      if Status /= Fit_Ok then
         Fit.Status := Status;
         return;
      end if;
      F := (Info  => Info,
            Cos_T => EF.Cos (Info.Rotation),
            Sin_T => EF.Sin (Info.Rotation),
            N     => Long_Float (Info.Count),
            Limit => 0.0);

      --  Moments in the principal frame (each term at most 16).
      for I in Points'Range loop
         pragma Loop_Invariant
           (Stt >= 0.0 and then Stt <= Moment_Limit
            and then Srr >= 0.0 and then Srr <= Moment_Limit
            and then abs Str <= Moment_Limit
            and then abs Stz <= Moment_Limit
            and then abs Srz <= Moment_Limit);
         if Selected (Mask, I) then
            P := Point_At (Points, I);
            To_Frame (F, P, T, R);
            Z := N.Square_Within (T, 2.0) + N.Square_Within (R, 2.0);
            Stt := Long_Float'Min (Stt + N.Square_Within (T, 2.0),
                                   Moment_Limit);
            Srr := Long_Float'Min (Srr + N.Square_Within (R, 2.0),
                                   Moment_Limit);
            Str := N.Clamp (Str + N.Mul_Within (T, R, 2.0, 2.0),
                            Moment_Limit);
            Stz := N.Clamp (Stz + N.Mul_Within (T, Z, 2.0, 8.0),
                            Moment_Limit);
            Srz := N.Clamp (Srz + N.Mul_Within (R, Z, 2.0, 8.0),
                            Moment_Limit);
         end if;
      end loop;

      if EF.Sqrt (Srr) <= Collinear_Tolerance * EF.Sqrt (Stt) then
         Fit.Status := Collinear_Points;
         return;
      end if;

      --  Kasa fit: minimise sum (Z + D T + E R + F)**2. With centred data
      --  the normal equations for D and E decouple from F:
      --     [Stt Str] [D]     [Stz]
      --     [Str Srr] [E] = - [Srz]
      --  and the centre is (-D/2, -E/2).
      Det := N.Mul_Within (Stt, Srr, Moment_Limit, Moment_Limit)
             - N.Mul_Within (Str, Str, Moment_Limit, Moment_Limit);
      if Det <= 0.0 then
         Fit.Status := Collinear_Points;
         return;
      end if;
      --  The RMS of T is at most 2; the limit states it for the prover and
      --  never acts.
      F.Limit := Centre_Limit_Factor
                 * Long_Float'Min (EF.Sqrt (Stt / F.N), 2.0);
      Num_A := 0.5 * (N.Mul_Within (Srr, Stz, Moment_Limit, Moment_Limit)
                      - N.Mul_Within (Str, Srz, Moment_Limit, Moment_Limit));
      Num_B := 0.5 * (N.Mul_Within (Stt, Srz, Moment_Limit, Moment_Limit)
                      - N.Mul_Within (Str, Stz, Moment_Limit, Moment_Limit));
      --  A centre beyond 2 * Limit has run off (Try would find so too); the
      --  quotients are only formed below that.
      Signed_Quotient (Num_A, Det, Long_Float'Max (1.0, 2.0 * F.Limit), A0,
                       Fits_A);
      Signed_Quotient (Num_B, Det, Long_Float'Max (1.0, 2.0 * F.Limit), B0,
                       Fits_B);
      if Fits_A and then Fits_B then
         Try (Points, Mask, F, A0, B0, Current, Runaway);
      else
         Runaway := True;
      end if;

      --  Geometric refinement, restarted after leaving a saddle point.
      if not Runaway then
         Descend (Points, Mask, F, Current, Runaway);
      end if;
      for Phase in 1 .. Max_Saddle_Escapes loop
         pragma Loop_Invariant
           (Bounded_Evaluation (Current)
            and then (if not Runaway
                      then abs Current.A <= F.Limit
                           and then abs Current.B <= F.Limit));
         exit when Runaway;
         Escape_Saddle (Points, Mask, F, Current, Runaway, Escaped);
         exit when Runaway or else not Escaped;
         Descend (Points, Mask, F, Current, Runaway);
      end loop;
      if Runaway then
         Fit.Status := Runaway_Centre;
         return;
      end if;

      declare
         A : constant Long_Float := Unscaled (Current.A, Info.Exponent);
         B : constant Long_Float := Unscaled (Current.B, Info.Exponent);
      begin
         Fit.Circle :=
           (Center_X => Info.Centroid.X + N.Times_Unit (A, F.Cos_T)
                        - N.Times_Unit (B, F.Sin_T),
            Center_Y => Info.Centroid.Y + N.Times_Unit (A, F.Sin_T)
                        + N.Times_Unit (B, F.Cos_T),
            Radius   => Long_Float'Max
                          (0.0, Unscaled (Current.Radius, Info.Exponent)));
      end;
      --  The RMS residual is at most the largest residual, below 2**41;
      --  the limit states a weaker bound for the prover and never acts.
      Fit.RMS_Error := Long_Float'Max
        (0.0,
         Unscaled (Long_Float'Min (EF.Sqrt (Current.Cost / F.N), 2.0 ** 60),
                   Info.Exponent));
      Fit.Cost := Current.Cost;
      Fit.Status := Fit_Ok;
   end Fit_Circle_Core;

   ---------------------------------------------------------------------
   --  Reporting fit failures
   ---------------------------------------------------------------------

   procedure Report
     (Fit       : Fit_Status;
      Operation : Operation_Name;
      Min_Count : Positive;
      Count     : Natural;
      Status    : out Ks_Status)
   with Pre  => Min_Count <= 3,
        Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (Succeeded (Status) = (Fit = Fit_Ok));
   --  The status of a fit: success, or Bad_Parameter describing the
   --  failure.

   procedure Report
     (Fit       : Fit_Status;
      Operation : Operation_Name;
      Min_Count : Positive;
      Count     : Natural;
      Status    : out Ks_Status) is
   begin
      case Fit is
         when Fit_Ok =>
            Set_Success (Status);
         when Too_Few_Points =>
            Bad (Status, Operation & ": at least "
                         & Image_Of (Int64 (Min_Count))
                         & " points are required, got "
                         & Image_Of (Int64 (Count)));
         when Coincident_Points =>
            Bad (Status, Operation & ": the points coincide");
         when Collinear_Points =>
            Bad (Status, Operation & ": the points are collinear");
         when Runaway_Centre =>
            Bad (Status, Operation & ": the points are too close to "
                         & "collinear");
      end case;
   end Report;

   procedure Check_Points
     (Operation : Operation_Name;
      Points    : Point_Array;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then (for all I in Points'Range
                                => Bounded (Points (I))));
   --  Every point finite and within the bound ("Fit_Line: Points (3) must
   --  be finite and within +/-1.0E150").

   procedure Check_Points
     (Operation : Operation_Name;
      Points    : Point_Array;
      Status    : out Ks_Status) is
   begin
      for I in Points'Range loop
         pragma Loop_Invariant
           (for all J in Points'First .. I - 1 => Bounded (Points (J)));
         if not Bounded (Points (I)) then
            Bad (Status, Operation & ": Points (" & Image_Of (Int64 (I))
                         & ") must be finite and within +/-1.0E150");
            return;
         end if;
      end loop;
      Set_Success (Status);
   end Check_Points;

   procedure Check_Robust_Arguments
     (Operation     : Operation_Name;
      Points        : Point_Array;
      Num_To_Ignore : Int32;
      Used          : Flag_Array;
      Min_Count     : Positive;
      Status        : out Ks_Status)
   with Pre  => Min_Count <= 3,
        Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Used'First = Points'First
                               and then Used'Last = Points'Last
                               and then Points'Length <= Max_Points
                               and then Num_To_Ignore >= 0
                               and then Int64 (Num_To_Ignore)
                                          <= Int64 (Points'Length)
                                             - Int64 (Min_Count));
   --  The checks of the robust fits, in the order of AMV.Geometry.

   procedure Check_Robust_Arguments
     (Operation     : Operation_Name;
      Points        : Point_Array;
      Num_To_Ignore : Int32;
      Used          : Flag_Array;
      Min_Count     : Positive;
      Status        : out Ks_Status)
   is
      Length : constant Int64 := Int64 (Points'Length);
   begin
      if Used'First /= Points'First or else Used'Last /= Points'Last then
         Bad (Status, Operation
                      & ": Used must have the same index range as Points");
      elsif Length > Max_Points then
         Bad (Status, Operation & ": at most 2147483647 points are allowed");
      elsif Length < Int64 (Min_Count) then
         Bad (Status, Operation & ": at least " & Image_Of (Int64 (Min_Count))
                      & " points are required, got " & Image_Of (Length));
      elsif Num_To_Ignore < 0 then
         Bad (Status, Operation & ": Num_To_Ignore must be >= 0");
      elsif Int64 (Num_To_Ignore) > Length - Int64 (Min_Count) then
         Bad (Status, Operation & ": Num_To_Ignore must leave at least "
                      & Image_Of (Int64 (Min_Count)) & " of the "
                      & Image_Of (Length) & " points");
      else
         Set_Success (Status);
      end if;
   end Check_Robust_Arguments;

   ---------------------------------------------------------------------
   --  Robust fitting by repeated leave-one-out removal
   ---------------------------------------------------------------------

   --  Each step discards the point whose removal leaves the smallest sum
   --  of squared residuals for a fit of the remaining points. Points are
   --  compared in index order and a later point replaces the current
   --  choice only when it is better by more than the tie tolerance, so
   --  ties go to the lowest index. Removals that would leave degenerate
   --  points are not chosen.

   procedure Choose_Line_Discard
     (Points : Point_Array;
      Used   : in out Flag_Array;
      Info   : Scatter_Info;
      Found  : out Boolean;
      Best   : out Natural)
   with
     Pre  => Points'Length in 2 .. Max_Points
             and then Used'First = Points'First
             and then Used'Last = Points'Last
             and then Bounded_Info (Info),
     Post => Used = Used'Old
             and then (if Found then Best in Points'Range);
   --  The point to discard from the points in use (Info describes them).
   --  For each candidate the scatter sums are downdated in O(1): removing
   --  offset d from N points leaves the centred scatter
   --  S - N / (N - 1) d d', whose smaller eigenvalue is the remaining sum
   --  of squared perpendicular residuals. Used is restored on return.
   --  Found is False only when every removal would leave coinciding
   --  points.

   procedure Choose_Line_Discard
     (Points : Point_Array;
      Used   : in out Flag_Array;
      Info   : Scatter_Info;
      Found  : out Boolean;
      Best   : out Natural)
   is
      Count   : constant Long_Float := Long_Float (Info.Count);
      W       : Long_Float;
      W_Fits  : Boolean;
      Trace   : constant Long_Float := Info.Sxx + Info.Syy;
      Tie     : constant Long_Float := Tie_Tolerance * Trace;
      Suspect : constant Long_Float :=
        Suspect_Fraction * Trace
        + N.Mul_Within
            (2.0 * (Count - 1.0),
             N.Square_Within (Coincidence_Tolerance * Info.Scale, 2.0 ** 22),
             2.0 * Long_Float (Max_Points), 2.0 ** 44);
      P             : Ks_Point_2D;
      DX, DY        : Long_Float;
      A, B, C       : Long_Float;
      Cost          : Long_Float;
      Best_Cost     : Long_Float := 0.0;
      Valid         : Boolean;
      Sub_Info      : Scatter_Info;
      Sub_Status    : Fit_Status;
   begin
      Found := False;
      Best := Points'First;
      --  N / (N - 1) is at most 2 for N >= 2.
      N.Ratio_Within (Count, Count - 1.0, 2.0, W, W_Fits);
      if not W_Fits then
         return;
      end if;
      for K in Points'Range loop
         pragma Loop_Invariant
           (Used = Used'Loop_Entry
            and then (if Found then Best in Points'Range)
            and then Best_Cost >= 0.0
            and then Best_Cost <= 4.0 * Moment_Limit);
         if Used (K) then
            P := Point_At (Points, K);
            DX := Offset_X (Info, P);
            DY := Offset_Y (Info, P);
            A := Info.Sxx - N.Mul_Within (N.Mul_Within (W, DX, 2.0, 1.0), DX,
                                          2.0, 1.0);
            B := Info.Syy - N.Mul_Within (N.Mul_Within (W, DY, 2.0, 1.0), DY,
                                          2.0, 1.0);
            C := Info.Sxy - N.Mul_Within (N.Mul_Within (W, DX, 2.0, 1.0), DY,
                                          2.0, 1.0);
            Cost := Long_Float'Min
              (Long_Float'Max
                 (0.0, 0.5 * (A + B) - N.Hypot (0.5 * (A - B), C)),
               4.0 * Moment_Limit);
            Valid := True;
            if A + B <= Suspect then
               --  Too little is left for the downdated sums to resolve:
               --  check the remaining points for coincidence directly.
               Used (K) := False;
               Analyse_Scatter (Points, Used, 2, Sub_Info, Sub_Status);
               Used (K) := True;
               --  (A successful analysis always counts at least 2 points.)
               Valid := Sub_Status = Fit_Ok and then Sub_Info.Count >= 2;
            end if;
            if Valid and then (not Found or else Cost < Best_Cost - Tie) then
               Found := True;
               Best := K;
               Best_Cost := Cost;
            end if;
         end if;
      end loop;
   end Choose_Line_Discard;

   ---------------------------------------------------------------------
   --  Fits (Ada arrays)
   ---------------------------------------------------------------------

   procedure Fit_Line
     (Points    : Point_Array;
      Line      : out Ks_Line_2D;
      RMS_Error : out Long_Float;
      Status    : out Ks_Status)
   is
      Info : Scatter_Info;
      Fit  : Fit_Status;
   begin
      Line := (others => 0.0);
      RMS_Error := 0.0;
      if Int64 (Points'Length) > Max_Points then
         Bad (Status, "Fit_Line: at most 2147483647 points are allowed");
         return;
      elsif Points'Length < 2 then
         Report (Too_Few_Points, "Fit_Line", 2, Points'Length, Status);
         return;
      end if;
      Check_Points ("Fit_Line", Points, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Fit_Line_Core (Points, No_Mask, Line, RMS_Error, Info, Fit);
      Report (Fit, "Fit_Line", 2, Info.Count, Status);
      if Succeeded (Status) and then RMS_Error > Max_Coordinate then
         Out_Of_Bound ("Fit_Line", Status);
      end if;
      if not Succeeded (Status) then
         Line := (others => 0.0);
         RMS_Error := 0.0;
      end if;
   end Fit_Line;

   procedure Fit_Line_Robust
     (Points        : Point_Array;
      Num_To_Ignore : Int32;
      Line          : out Ks_Line_2D;
      RMS_Error     : out Long_Float;
      Used          : out Flag_Array;
      Status        : out Ks_Status)
   is
      Info  : Scatter_Info;
      Fit   : Fit_Status;
      Found : Boolean;
      Best  : Natural;
   begin
      Line := (others => 0.0);
      RMS_Error := 0.0;
      Used := [others => False];
      Check_Robust_Arguments ("Fit_Line", Points, Num_To_Ignore, Used, 2,
                              Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Points ("Fit_Line", Points, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Used := [others => True];
      for Removed in 1 .. Num_To_Ignore loop
         pragma Loop_Invariant
           (Used'First = Points'First and then Used'Last = Points'Last);
         Analyse_Scatter (Points, Used, 2, Info, Fit);
         if Fit /= Fit_Ok then
            Report (Fit, "Fit_Line", 2, Info.Count, Status);
            Used := [others => False];
            return;
         end if;
         Choose_Line_Discard (Points, Used, Info, Found, Best);
         if not Found then
            Bad (Status, "Fit_Line: discarding any one point leaves "
                         & "coinciding points");
            Used := [others => False];
            return;
         end if;
         Used (Best) := False;
      end loop;
      Fit_Line_Core (Points, Used, Line, RMS_Error, Info, Fit);
      Report (Fit, "Fit_Line", 2, Info.Count, Status);
      if Succeeded (Status) and then RMS_Error > Max_Coordinate then
         Out_Of_Bound ("Fit_Line", Status);
      end if;
      if not Succeeded (Status) then
         Line := (others => 0.0);
         RMS_Error := 0.0;
         Used := [others => False];
      end if;
   end Fit_Line_Robust;

   procedure Finish_Circle
     (Fit       : Circle_Fit;
      Operation : Operation_Name;
      Circle    : out Ks_Circle_2D;
      RMS_Error : out Long_Float;
      Status    : out Ks_Status)
   with Pre  => Valid_Fit (Fit),
        Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then Bounded (Circle) and then Circle.Radius >= 0.0
                and then RMS_Error >= 0.0
                and then RMS_Error <= Max_Coordinate;
   --  The results of a circle fit, or its failure; Bad_Parameter when the
   --  circle or the error would exceed the bound.

   procedure Finish_Circle
     (Fit       : Circle_Fit;
      Operation : Operation_Name;
      Circle    : out Ks_Circle_2D;
      RMS_Error : out Long_Float;
      Status    : out Ks_Status) is
   begin
      Circle := (others => 0.0);
      RMS_Error := 0.0;
      Report (Fit.Status, Operation, 3, Fit.Info.Count, Status);
      if not Succeeded (Status) then
         return;
      elsif not Bounded (Fit.Circle)
        or else Fit.RMS_Error > Max_Coordinate
      then
         Out_Of_Bound (Operation, Status);
         return;
      end if;
      Circle := Fit.Circle;
      RMS_Error := Fit.RMS_Error;
   end Finish_Circle;

   procedure Fit_Circle
     (Points    : Point_Array;
      Circle    : out Ks_Circle_2D;
      RMS_Error : out Long_Float;
      Status    : out Ks_Status)
   is
      Fit : Circle_Fit;
   begin
      Circle := (others => 0.0);
      RMS_Error := 0.0;
      if Int64 (Points'Length) > Max_Points then
         Bad (Status, "Fit_Circle: at most 2147483647 points are allowed");
         return;
      elsif Points'Length < 3 then
         Report (Too_Few_Points, "Fit_Circle", 3, Points'Length, Status);
         return;
      end if;
      Check_Points ("Fit_Circle", Points, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Fit_Circle_Core (Points, No_Mask, Fit);
      Finish_Circle (Fit, "Fit_Circle", Circle, RMS_Error, Status);
   end Fit_Circle;

   procedure Fit_Circle_Robust
     (Points        : Point_Array;
      Num_To_Ignore : Int32;
      Circle        : out Ks_Circle_2D;
      RMS_Error     : out Long_Float;
      Used          : out Flag_Array;
      Status        : out Ks_Status)
   is
      Fit       : Circle_Fit;
      Trial     : Circle_Fit;
      Found     : Boolean;
      Best      : Natural;
      Cost      : Long_Float;
      Best_Cost : Long_Float;
      Tie       : Long_Float;
   begin
      Circle := (others => 0.0);
      RMS_Error := 0.0;
      Used := [others => False];
      Check_Robust_Arguments ("Fit_Circle", Points, Num_To_Ignore, Used, 3,
                              Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Points ("Fit_Circle", Points, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Used := [others => True];
      for Removed in 1 .. Num_To_Ignore loop
         pragma Loop_Invariant
           (Used'First = Points'First and then Used'Last = Points'Last);
         --  The points in use must be fit for a circle themselves.
         Fit_Circle_Core (Points, Used, Fit);
         if Fit.Status /= Fit_Ok then
            Report (Fit.Status, "Fit_Circle", 3, Fit.Info.Count, Status);
            Used := [others => False];
            return;
         end if;
         Tie := Tie_Tolerance * (Fit.Info.Sxx + Fit.Info.Syy);
         Found := False;
         Best := Points'First;
         Best_Cost := 0.0;
         for K in Points'Range loop
            pragma Loop_Invariant
              (Used = Used'Loop_Entry
               and then (if Found then Best in Points'Range)
               and then abs Best_Cost <= 2.0 ** 1020);
            if Used (K) then
               Used (K) := False;
               Fit_Circle_Core (Points, Used, Trial);
               Used (K) := True;
               if Trial.Status = Fit_Ok then
                  --  Express the cost in the units of the points in use.
                  Cost := Rescaled_Cost
                    (Trial.Cost,
                     2 * (Trial.Info.Exponent - Fit.Info.Exponent));
                  if not Found or else Cost < Best_Cost - Tie then
                     Found := True;
                     Best := K;
                     Best_Cost := Cost;
                  end if;
               end if;
            end if;
         end loop;
         if not Found then
            Bad (Status, "Fit_Circle: discarding any one point leaves points "
                         & "without a circle");
            Used := [others => False];
            return;
         end if;
         Used (Best) := False;
      end loop;
      Fit_Circle_Core (Points, Used, Fit);
      Finish_Circle (Fit, "Fit_Circle", Circle, RMS_Error, Status);
      if not Succeeded (Status) then
         Used := [others => False];
      end if;
   end Fit_Circle_Robust;

   ---------------------------------------------------------------------
   --  Fits (C memory)
   ---------------------------------------------------------------------

   type Int32_Array is array (Natural range <>) of Int32;
   type Flag_Array_Access is access Flag_Array;

   procedure Free is new Ada.Unchecked_Deallocation
     (Flag_Array, Flag_Array_Access);

   procedure Check_Points_Request
     (Operation : Operation_Name;
      Count     : Int32;
      Null_Points, Null_Used : Boolean;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Count >= 0
                               and then (if Count > 0
                                         then not Null_Points
                                              and then not Null_Used));
   --  The checks of the C fits: Count in 0 .. Max_Points, and the
   --  pointers not null when Count is positive.

   procedure Check_Points_Request
     (Operation : Operation_Name;
      Count     : Int32;
      Null_Points, Null_Used : Boolean;
      Status    : out Ks_Status) is
   begin
      if Count < 0 then
         Bad (Status, Operation & ": Count must be >= 0");
      elsif Count > 0 and then Null_Points then
         Bad (Status, Operation & ": Points must not be null");
      elsif Count > 0 and then Null_Used then
         Bad (Status, Operation & ": Used must not be null");
      else
         Set_Success (Status);
      end if;
   end Check_Points_Request;

   procedure Store_Flags (Flags : Flag_Array; Target : out Int32_Array)
   with Pre  => Target'First = Flags'First and then Target'Last = Flags'Last,
        Post => (for all I in Target'Range
                 => Target (I) = (if Flags (I) then True_Value
                                  else False_Value));
   --  The flags as C int32_t values.

   procedure Store_Flags (Flags : Flag_Array; Target : out Int32_Array) is
   begin
      Target := [others => False_Value];
      for I in Target'Range loop
         Target (I) := (if Flags (I) then True_Value else False_Value);
         pragma Loop_Invariant
           (for all J in Target'First .. I
            => Target (J) = (if Flags (J) then True_Value
                             else False_Value));
      end loop;
   end Store_Flags;

   No_Points : constant Point_Array (1 .. 0) := [others => (0.0, 0.0)];

   procedure Fit_Line_C
     (Points    : System.Address;
      Count     : Int32;
      Line      : out Ks_Line_2D;
      RMS_Error : out Long_Float;
      Status    : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
   begin
      Line := (others => 0.0);
      RMS_Error := 0.0;
      Check_Points_Request ("Fit_Line", Count,
                            Points = System.Null_Address, False, Status);
      if not Succeeded (Status) then
         return;
      elsif Count = 0 then
         Fit_Line (No_Points, Line, RMS_Error, Status);
      else
         declare
            View : Point_Array (0 .. Natural (Count) - 1)
              with Import, Address => Points;
         begin
            Fit_Line (View, Line, RMS_Error, Status);
         end;
      end if;
   end Fit_Line_C;

   procedure Fit_Circle_C
     (Points    : System.Address;
      Count     : Int32;
      Circle    : out Ks_Circle_2D;
      RMS_Error : out Long_Float;
      Status    : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
   begin
      Circle := (others => 0.0);
      RMS_Error := 0.0;
      Check_Points_Request ("Fit_Circle", Count,
                            Points = System.Null_Address, False, Status);
      if not Succeeded (Status) then
         return;
      elsif Count = 0 then
         Fit_Circle (No_Points, Circle, RMS_Error, Status);
      else
         declare
            View : Point_Array (0 .. Natural (Count) - 1)
              with Import, Address => Points;
         begin
            Fit_Circle (View, Circle, RMS_Error, Status);
         end;
      end if;
   end Fit_Circle_C;

   procedure Fit_Line_Robust_C
     (Points        : System.Address;
      Count         : Int32;
      Num_To_Ignore : Int32;
      Line          : out Ks_Line_2D;
      RMS_Error     : out Long_Float;
      Used          : System.Address;
      Status        : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
      Flags : Flag_Array_Access;
   begin
      Line := (others => 0.0);
      RMS_Error := 0.0;
      Check_Points_Request ("Fit_Line", Count, Points = System.Null_Address,
                            Used = System.Null_Address, Status);
      if not Succeeded (Status) then
         return;
      elsif Count = 0 then
         declare
            No_Flags : Flag_Array (1 .. 0);
         begin
            Fit_Line_Robust (No_Points, Num_To_Ignore, Line, RMS_Error,
                             No_Flags, Status);
         end;
         return;
      end if;
      begin
         Flags := new Flag_Array (0 .. Natural (Count) - 1);
      exception
         when Storage_Error =>
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Fit_Line: not enough memory for the flags");
            return;
      end;
      declare
         View   : Point_Array (0 .. Natural (Count) - 1)
           with Import, Address => Points;
         Target : Int32_Array (0 .. Natural (Count) - 1)
           with Import, Address => Used;
      begin
         Fit_Line_Robust (View, Num_To_Ignore, Line, RMS_Error, Flags.all,
                          Status);
         Store_Flags (Flags.all, Target);
      end;
      Free (Flags);
   end Fit_Line_Robust_C;

   procedure Fit_Circle_Robust_C
     (Points        : System.Address;
      Count         : Int32;
      Num_To_Ignore : Int32;
      Circle        : out Ks_Circle_2D;
      RMS_Error     : out Long_Float;
      Used          : System.Address;
      Status        : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
      Flags : Flag_Array_Access;
   begin
      Circle := (others => 0.0);
      RMS_Error := 0.0;
      Check_Points_Request ("Fit_Circle", Count, Points = System.Null_Address,
                            Used = System.Null_Address, Status);
      if not Succeeded (Status) then
         return;
      elsif Count = 0 then
         declare
            No_Flags : Flag_Array (1 .. 0);
         begin
            Fit_Circle_Robust (No_Points, Num_To_Ignore, Circle, RMS_Error,
                               No_Flags, Status);
         end;
         return;
      end if;
      begin
         Flags := new Flag_Array (0 .. Natural (Count) - 1);
      exception
         when Storage_Error =>
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Fit_Circle: not enough memory for the flags");
            return;
      end;
      declare
         View   : Point_Array (0 .. Natural (Count) - 1)
           with Import, Address => Points;
         Target : Int32_Array (0 .. Natural (Count) - 1)
           with Import, Address => Used;
      begin
         Fit_Circle_Robust (View, Num_To_Ignore, Circle, RMS_Error,
                            Flags.all, Status);
         Store_Flags (Flags.all, Target);
      end;
      Free (Flags);
   end Fit_Circle_Robust_C;

end AMV.Kernels.Geometry;
