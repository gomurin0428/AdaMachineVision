pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;

with AMV.Kernels.Numerics;

package body AMV.Kernels.Dimensioning.Ellipses with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;
   package EF renames Ada.Numerics.Long_Elementary_Functions;

   subtype Unit is P.Unit;
   subtype Fraction is Long_Float range 0.0 .. 1.0;
   subtype Local_Value is Long_Float range -4.0 * Max_Value .. 4.0 * Max_Value;
   subtype Scale_Value is Long_Float range 0.0 .. 8.0 * Max_Value;

   Max_Bisection_Steps : constant := 1200;
   --  Enough to halve an interval of length 3 down to adjacent Long_Float
   --  values anywhere (the smallest step is 2**(-1074)).

   ---------------------------------------------------------------------
   --  Frames and scaling
   ---------------------------------------------------------------------

   procedure Local
     (Q    : P.Point;
      E    : Ellipse;
      U, V : out Local_Value);
   --  Q in the ellipse's frame: (Q - centre) turned by minus the rotation.

   procedure Local
     (Q    : P.Point;
      E    : Ellipse;
      U, V : out Local_Value)
   is
      DX : constant Long_Float := Q.X - E.Center.X;
      DY : constant Long_Float := Q.Y - E.Center.Y;
   begin
      U := N.Times_Unit (DX, E.C) + N.Times_Unit (DY, E.S);
      V := N.Times_Unit (DY, E.C) - N.Times_Unit (DX, E.S);
   end Local;

   function Fraction_Of (X, Y : Long_Float) return Fraction
   with Pre => X >= 0.0 and then Y > 0.0 and then X <= Y;
   --  X / Y for 0 <= X <= Y.

   function Fraction_Of (X, Y : Long_Float) return Fraction is
     (Long_Float'Max (0.0, N.Unit_Ratio (X, Y)));

   function Scaled (X, Scale : Long_Float) return Unit
   with Pre => Scale > 0.0 and then abs X <= Scale;
   --  X / Scale.

   function Scaled (X, Scale : Long_Float) return Unit is
     (N.Unit_Ratio (X, Scale));

   procedure To_World
     (E      : Ellipse;
      Scale  : Scale_Value;
      QU, QV : Long_Float;
      Q      : out P.Point;
      Fits   : out Boolean)
   with Pre  => abs QU <= 16.0 and then abs QV <= 16.0,
        Post => (if not Fits then Q = P.Origin);
   --  The point (QU, QV) of the ellipse's frame scaled by Scale, back in
   --  the measuring space; Fits is False when it leaves the bound.

   procedure To_World
     (E      : Ellipse;
      Scale  : Scale_Value;
      QU, QV : Long_Float;
      Q      : out P.Point;
      Fits   : out Boolean)
   is
      WX : constant Long_Float :=
        N.Times_Unit (QU, E.C) - N.Times_Unit (QV, E.S);
      WY : constant Long_Float :=
        N.Times_Unit (QU, E.S) + N.Times_Unit (QV, E.C);
      X  : constant Long_Float :=
        E.Center.X + N.Mul_Within (Scale, WX, 8.0 * Max_Value, 32.0);
      Y  : constant Long_Float :=
        E.Center.Y + N.Mul_Within (Scale, WY, 8.0 * Max_Value, 32.0);
   begin
      Fits := Bounded (X) and then Bounded (Y);
      Q := (if Fits then (X, Y) else P.Origin);
   end To_World;

   function World_Length (Scale : Scale_Value; L : Long_Float)
      return P.Length
   with Pre => L >= 0.0 and then L <= 4.0;
   --  Scale * L, a length in the measuring space. The limit to Max_Length
   --  never acts: every length measured here is at most the distance
   --  between two points within the bound plus a radius (about 3.9E150).

   function World_Length (Scale : Scale_Value; L : Long_Float)
      return P.Length is
     (Long_Float'Max
        (0.0, Long_Float'Min (N.Mul_Within (Scale, L, 8.0 * Max_Value, 4.0),
                              Max_Length)));

   ---------------------------------------------------------------------
   --  Nearest point (Eberly's bisection)
   ---------------------------------------------------------------------

   procedure Bounded_Quotient
     (X, Y, Limit : Long_Float;
      R           : out Long_Float;
      Fits        : out Boolean)
   with Pre  => X >= 0.0 and then X <= 1.0 and then Limit in 1.0 .. 2.0,
        Post => R >= 0.0 and then R <= Limit
                and then (if not Fits then R = Limit);
   --  R := X / Y when Y > 0 and the quotient is at most Limit (Fits True);
   --  otherwise R := Limit (Fits False).

   procedure Bounded_Quotient
     (X, Y, Limit : Long_Float;
      R           : out Long_Float;
      Fits        : out Boolean) is
   begin
      if Y > 0.0 and then Y <= 4.0 then
         N.Ratio_Within (X, Y, Limit, R, Fits);
         if Fits then
            return;
         end if;
      end if;
      Fits := False;
      R := Limit;
   end Bounded_Quotient;

   function Positive_F (T, E0, E1, Y0, Y1 : Long_Float) return Boolean
   with Pre => T >= -1.0 and then T <= 2.0
               and then E0 in 0.0 .. 1.0 and then E1 in 0.0 .. 1.0
               and then Y0 in 0.0 .. 1.0 and then Y1 in 0.0 .. 1.0;
   --  Whether F (T) = (E0 Y0 / (T + E0**2))**2 + (E1 Y1 / (T + E1**2))**2
   --  - 1 is positive. F decreases for T > -E1**2; at or below that pole,
   --  and when a quotient exceeds 2, F counts as positive.

   function Positive_F (T, E0, E1, Y0, Y1 : Long_Float) return Boolean is
      D0     : constant Long_Float := T + N.Times_Unit (E0, E0);
      D1     : constant Long_Float := T + N.Times_Unit (E1, E1);
      Q0, Q1 : Long_Float;
      Fits   : Boolean;
   begin
      Bounded_Quotient (N.Times_Unit (E0, Y0), D0, 2.0, Q0, Fits);
      if not Fits then
         return True;
      end if;
      Bounded_Quotient (N.Times_Unit (E1, Y1), D1, 2.0, Q1, Fits);
      if not Fits then
         return True;
      end if;
      return N.Square_Within (Q0, 2.0) + N.Square_Within (Q1, 2.0) > 1.0;
   end Positive_F;

   procedure Bisect
     (E0, E1, Y0, Y1 : Fraction;
      X0, X1         : out Fraction)
   with Pre => E0 >= E1 and then E1 > 0.0 and then Y0 > 0.0
               and then Y1 > 0.0;
   --  The nearest point (X0, X1) of the ellipse with semi-axes E0 >= E1
   --  to the point (Y0, Y1) of the open first quadrant: (E0**2 Y0 /
   --  (T + E0**2), E1**2 Y1 / (T + E1**2)) at the root T of F (see
   --  Positive_F), which lies between -E1**2 + E1 Y1 (where F >= 0) and
   --  -E1**2 + |(E0 Y0, E1 Y1)| (where F <= 0).

   procedure Bisect
     (E0, E1, Y0, Y1 : Fraction;
      X0, X1         : out Fraction)
   is
      Pole   : constant Fraction := N.Times_Unit (E1, E1);
      Lo     : Long_Float := N.Times_Unit (E1, Y1) - Pole;
      Hi     : Long_Float;
      Mid    : Long_Float;
      Q0, Q1 : Long_Float;
      Unused_Fits : Boolean;
   begin
      Hi := Long_Float'Max
        (Lo, N.Hypot (N.Times_Unit (E0, Y0), N.Times_Unit (E1, Y1)) - Pole);
      for Step in 1 .. Max_Bisection_Steps loop
         pragma Loop_Invariant
           (Lo >= -1.0 and then Lo <= Hi and then Hi <= 2.0);
         Mid := (Lo + Hi) / 2.0;
         exit when Mid <= Lo or else Mid >= Hi;
         if Positive_F (Mid, E0, E1, Y0, Y1) then
            Lo := Mid;
         else
            Hi := Mid;
         end if;
      end loop;
      --  At Hi, F <= 0 (or Hi is the root itself), so both quotients are
      --  at most 1; a quotient that cannot be formed (only through
      --  rounding next to the pole) is taken as 1.
      Bounded_Quotient
        (N.Times_Unit (E0, Y0), Hi + N.Times_Unit (E0, E0), 1.0, Q0,
         Unused_Fits);
      Bounded_Quotient
        (N.Times_Unit (E1, Y1), Hi + Pole, 1.0, Q1, Unused_Fits);
      X0 := N.Times_Unit (E0, Q0);
      X1 := N.Times_Unit (E1, Q1);
   end Bisect;

   procedure Nearest_In_Quadrant
     (E0, E1, Y0, Y1 : Fraction;
      X0, X1         : out Fraction)
   with Pre => E0 >= E1;
   --  The nearest point (X0, X1) (both >= 0) of the ellipse with semi-axes
   --  E0 >= E1 >= 0 to the point (Y0, Y1) (both >= 0). A semi-axis of 0
   --  (an ellipse too thin to resolve at this scale) is a segment or a
   --  point.

   procedure Nearest_In_Quadrant
     (E0, E1, Y0, Y1 : Fraction;
      X0, X1         : out Fraction)
   is
      Num, Den, R : Fraction;
   begin
      if E0 = 0.0 then
         X0 := 0.0;
         X1 := 0.0;
      elsif E1 = 0.0 then
         X0 := Long_Float'Min (Y0, E0);
         X1 := 0.0;
      elsif Y1 > 0.0 then
         if Y0 > 0.0 then
            Bisect (E0, E1, Y0, Y1, X0, X1);
         else
            --  On the minor axis.
            X0 := 0.0;
            X1 := E1;
         end if;
      else
         --  On the major axis: inside the evolute's cusp the nearest
         --  point lies off the axis, at X0 = E0**2 Y0 / (E0**2 - E1**2).
         Num := N.Times_Unit (E0, Y0);
         Den := Long_Float'Max
           (0.0, N.Times_Unit (E0, E0) - N.Times_Unit (E1, E1));
         if Num < Den then
            R := Fraction_Of (Num, Den);
            X0 := N.Times_Unit (E0, R);
            X1 := N.Times_Unit
              (E1, N.Clamp_Unit (EF.Sqrt (Long_Float'Max
                                            (0.0, 1.0 - R * R))));
         else
            X0 := E0;
            X1 := 0.0;
         end if;
      end if;
   end Nearest_In_Quadrant;

   function Signed (Magnitude : Fraction; Like : Long_Float) return Unit is
     (if Like < 0.0 then -Magnitude else Magnitude);
   --  Magnitude with the sign of Like (+ for 0).

   procedure Point_Ellipse
     (Q    : P.Point;
      E    : Ellipse;
      D    : out P.Signed_Length;
      Near : out P.Point;
      Fits : out Boolean)
   is
      U, V   : Local_Value;
      Scale  : Long_Float;
      UN, VN : Unit;
      AN, BN : Fraction;
      E0, E1 : Fraction;
      Y0, Y1 : Fraction;
      X0, X1 : Fraction;
      QU, QV : Unit;
      DN     : Long_Float;
      Inside : Boolean;
   begin
      Local (Q, E, U, V);
      if U = 0.0 and then V = 0.0 and then E.Radius_X = E.Radius_Y then
         --  The centre of a circle: +Radius and the point at the angle of
         --  the rotation, as the reference documents.
         D := E.Radius_X;
         P.Point_Towards (E.Center, E.Radius_X, E.C, E.S, Near, Fits);
         return;
      end if;
      Scale := Long_Float'Max
        (Long_Float'Max (E.Radius_X, E.Radius_Y),
         Long_Float'Max (abs U, abs V));
      UN := Scaled (U, Scale);
      VN := Scaled (V, Scale);
      AN := Fraction_Of (E.Radius_X, Scale);
      BN := Fraction_Of (E.Radius_Y, Scale);
      --  Work in the first quadrant with the longer semi-axis first.
      if AN >= BN then
         E0 := AN;
         E1 := BN;
         Y0 := abs UN;
         Y1 := abs VN;
      else
         E0 := BN;
         E1 := AN;
         Y0 := abs VN;
         Y1 := abs UN;
      end if;
      Nearest_In_Quadrant (E0, E1, Y0, Y1, X0, X1);
      --  Inside when (Y0 / E0)**2 + (Y1 / E1)**2 < 1.
      Inside := N.Square_Within (N.Times_Unit (E1, Y0), 1.0)
                + N.Square_Within (N.Times_Unit (E0, Y1), 1.0)
                < N.Square_Within (N.Times_Unit (E0, E1), 1.0);
      if AN >= BN then
         QU := Signed (X0, UN);
         QV := Signed (X1, VN);
      else
         QU := Signed (X1, UN);
         QV := Signed (X0, VN);
      end if;
      DN := N.Hypot (QU - UN, QV - VN);
      D := World_Length (Scale, Long_Float'Min (DN, 4.0));
      if Inside then
         D := -D;
      end if;
      if D = 0.0 then
         Near := Q;
         Fits := True;
      else
         To_World (E, Scale, QU, QV, Near, Fits);
      end if;
   end Point_Ellipse;

   ---------------------------------------------------------------------
   --  Lines
   ---------------------------------------------------------------------

   type Line_Frame is record
      DU, DV : Unit := 0.0;
      --  The line's direction in the ellipse's frame.
      NU, NV : Unit := 0.0;
      --  Its left normal (-DV, DU).
      Scale  : Scale_Value := 0.0;
      --  The largest of the radii and the line's distance from the
      --  centre (> 0).
      DN     : Unit := 0.0;
      --  The signed distance of the line from the centre along the
      --  normal, divided by Scale.
      AN, BN : Fraction := 0.0;
      --  The radii divided by Scale.
      HN     : Long_Float := 0.0;
      --  The ellipse's extent along the normal (its support), divided by
      --  Scale: |(AN NU, BN NV)|.
   end record;

   function Valid_Frame (F : Line_Frame) return Boolean is
     (F.Scale > 0.0 and then F.HN >= 0.0 and then F.HN <= 2.0);

   function Frame_Of (L : P.Line; E : Ellipse) return Line_Frame
   with Pre  => Valid_Ellipse (E),
        Post => Valid_Frame (Frame_Of'Result);

   function Normal_Offset (U, V : Local_Value; NU, NV : Unit)
      return Long_Float
   is (N.Times_Unit (U, NU) + N.Times_Unit (V, NV))
   with Post => abs Normal_Offset'Result <= 8.0 * Max_Value;
   --  (U, V) . (NU, NV).

   function Frame_Of (L : P.Line; E : Ellipse) return Line_Frame is
      U, V   : Local_Value;
      Offset : Long_Float;
      F      : Line_Frame;
   begin
      F.DU := N.Clamp (N.Times_Unit (L.C, E.C) + N.Times_Unit (L.S, E.S),
                       1.0);
      F.DV := N.Clamp (N.Times_Unit (L.S, E.C) - N.Times_Unit (L.C, E.S),
                       1.0);
      F.NU := -F.DV;
      F.NV := F.DU;
      Local (L.P, E, U, V);
      Offset := Normal_Offset (U, V, F.NU, F.NV);
      F.Scale := Long_Float'Max
        (Long_Float'Max (E.Radius_X, E.Radius_Y), abs Offset);
      F.DN := Scaled (Offset, F.Scale);
      F.AN := Fraction_Of (E.Radius_X, F.Scale);
      F.BN := Fraction_Of (E.Radius_Y, F.Scale);
      F.HN := N.Hypot (N.Times_Unit (F.AN, F.NU), N.Times_Unit (F.BN, F.NV));
      return F;
   end Frame_Of;

   procedure Support
     (F      : Line_Frame;
      Sign   : Unit;
      QU, QV : out Unit)
   with Pre => Valid_Frame (F);
   --  The point of the ellipse (in its frame, scaled) farthest along
   --  Sign times the normal: Sign (AN**2 NU, BN**2 NV) / HN.

   procedure Support
     (F      : Line_Frame;
      Sign   : Unit;
      QU, QV : out Unit)
   is
      AU : constant Long_Float := N.Times_Unit (F.AN, F.NU);
      BV : constant Long_Float := N.Times_Unit (F.BN, F.NV);
   begin
      if F.HN > 0.0 then
         QU := N.Times_Unit
           (N.Times_Unit (F.AN, N.Unit_Ratio (N.Clamp (AU, F.HN), F.HN)),
            Sign);
         QV := N.Times_Unit
           (N.Times_Unit (F.BN, N.Unit_Ratio (N.Clamp (BV, F.HN), F.HN)),
            Sign);
      else
         QU := 0.0;
         QV := 0.0;
      end if;
   end Support;

   procedure Line_Ellipse
     (L      : P.Line;
      E      : Ellipse;
      D      : out P.Length;
      QL, QE : out P.Point;
      Fits   : out Boolean)
   is
      F         : constant Line_Frame := Frame_Of (L, E);
      Sign      : Unit;
      Gap       : Long_Float;
      QU, QV    : Unit;
      Fits_Line : Boolean;
   begin
      if abs F.DN <= F.HN then
         D := 0.0;
         QL := P.Origin;
         QE := P.Origin;
         Fits := True;
         return;
      end if;
      Gap := abs F.DN - F.HN;
      Sign := (if F.DN > 0.0 then 1.0 else -1.0);
      Support (F, Sign, QU, QV);
      To_World (E, F.Scale, QU, QV, QE, Fits);
      --  The line's point facing the ellipse: the support point moved by
      --  the gap along the normal, towards the line.
      To_World (E, F.Scale,
                QU + N.Times_Unit (Gap, N.Times_Unit (Sign, F.NU)),
                QV + N.Times_Unit (Gap, N.Times_Unit (Sign, F.NV)),
                QL, Fits_Line);
      Fits := Fits and then Fits_Line;
      D := World_Length (F.Scale, Gap);
      if D = 0.0 then
         QL := P.Origin;
         QE := P.Origin;
      end if;
   end Line_Ellipse;

   function Parameter (Num, Den : Long_Float) return Long_Float
   with Pre  => abs Num <= 8.0 and then Den >= 0.0 and then Den <= 8.0,
        Post => abs Parameter'Result <= 8.0;
   --  Num / Den limited to [-8, 8] (0 for Den = 0). The parameters of the
   --  intersections are at most 2 in magnitude (the chord of an ellipse of
   --  radius at most 1 through a point at most 1 from its centre), so the
   --  limit acts only through rounding when Den is tiny.

   function Parameter (Num, Den : Long_Float) return Long_Float is
      R    : Long_Float;
      Fits : Boolean;
   begin
      if Den = 0.0 then
         return 0.0;
      end if;
      N.Ratio_Within (abs Num, Den, 8.0, R, Fits);
      if not Fits then
         R := 8.0;
      end if;
      return (if Num < 0.0 then -R else R);
   end Parameter;

   procedure Intersect_Line_Ellipse
     (L      : P.Line;
      E      : Ellipse;
      Result : out Two_Points;
      Fits   : out Boolean)
   is
      F      : constant Line_Frame := Frame_Of (L, E);
      Tol    : constant Long_Float :=
        P.Relative_Tolerance * Long_Float'Max (F.AN, F.BN);
      QU, QV : Unit;
      Q1, Q2 : P.Point;
      Fits_2 : Boolean;
   begin
      Result := (Count => 0, P1 => P.Origin, P2 => P.Origin);
      Fits := True;
      if abs F.DN > F.HN + Tol then
         return;
      elsif abs F.DN >= F.HN - Tol then
         --  Tangent: the support point on the line's side.
         Support (F, (if F.DN < 0.0 then -1.0 else 1.0), QU, QV);
         To_World (E, F.Scale, QU, QV, Q1, Fits);
         if Fits then
            Result := (Count => 1, P1 => Q1, P2 => P.Origin);
         end if;
         return;
      end if;
      --  Two points: from the foot of the centre on the line, FU + T DU
      --  and FV + T DV with (BN (FU + T DU))**2 + (AN (FV + T DV))**2 =
      --  (AN BN)**2, a quadratic A2 T**2 + 2 B1 T + C0 = 0.
      declare
         FU   : constant Unit := N.Times_Unit (F.DN, F.NU);
         FV   : constant Unit := N.Times_Unit (F.DN, F.NV);
         A2   : constant Fraction := N.Times_Unit (F.AN, F.AN);
         B2   : constant Fraction := N.Times_Unit (F.BN, F.BN);
         QA   : constant Long_Float :=
           N.Times_Unit (B2, N.Square_Within (F.DU, 1.0))
           + N.Times_Unit (A2, N.Square_Within (F.DV, 1.0));
         QB   : constant Long_Float :=
           N.Times_Unit (B2, N.Times_Unit (FU, F.DU))
           + N.Times_Unit (A2, N.Times_Unit (FV, F.DV));
         QC   : constant Long_Float :=
           N.Times_Unit (B2, N.Square_Within (FU, 1.0))
           + N.Times_Unit (A2, N.Square_Within (FV, 1.0))
           - N.Times_Unit (A2, B2);
         Disc : constant Long_Float :=
           Long_Float'Max
             (0.0, N.Square_Within (QB, 2.0)
                   - N.Mul_Within (QA, QC, 2.0, 3.0));
         Root : constant Long_Float :=
           Long_Float'Min (EF.Sqrt (Disc), 4.0);
         --  The stable form of the two roots: T1 = Q / QA, T2 = QC / Q
         --  with Q = -(QB + sign (QB) Root).
         Q    : constant Long_Float :=
           (if QB >= 0.0 then -(QB + Root) else Root - QB);
         T1   : constant Long_Float := Parameter (Q, QA);
         T2   : constant Long_Float :=
           (if Q = 0.0 then T1 else Parameter (QC, abs Q)
                                    * (if Q < 0.0 then -1.0 else 1.0));
         TA   : constant Long_Float := Long_Float'Min (T1, T2);
         TB   : constant Long_Float := Long_Float'Max (T1, T2);
      begin
         To_World (E, F.Scale,
                   FU + N.Times_Unit (TA, F.DU), FV + N.Times_Unit (TA, F.DV),
                   Q1, Fits);
         To_World (E, F.Scale,
                   FU + N.Times_Unit (TB, F.DU), FV + N.Times_Unit (TB, F.DV),
                   Q2, Fits_2);
         Fits := Fits and then Fits_2;
         if Fits then
            Result := (Count => 2, P1 => Q1, P2 => Q2);
         end if;
      end;
   end Intersect_Line_Ellipse;

   procedure Intersect_Segment_Ellipse
     (S      : P.Segment;
      E      : Ellipse;
      Result : out Two_Points;
      Fits   : out Boolean)
   is
      Dir   : constant P.Direction_Info := P.Direction (S);
      L     : constant P.Line := P.Line_Of (S);
      Found : Two_Points;
      Tol   : constant Long_Float := P.Relative_Tolerance * Dir.Length;
      Count  : Int32 range 0 .. 2 := 0;
      Kept_1 : P.Point := P.Origin;
      Kept_2 : P.Point := P.Origin;
      Point_D     : P.Signed_Length;
      Unused_Near : P.Point;
      Unused_Fits : Boolean;

      function Snapped (Q : P.Point) return P.Point is
        (if P.Along (Q, L) < 0.0 then S.A
         elsif P.Along (Q, L) > Dir.Length then S.B
         else Q);
      --  Q, moved onto the nearer end when it lies beyond one.

      function On_Segment (Q : P.Point) return Boolean is
        (P.Along (Q, L) >= -Tol and then P.Along (Q, L) <= Dir.Length + Tol);

   begin
      Result := (Count => 0, P1 => P.Origin, P2 => P.Origin);
      if Dir.Length = 0.0 then
         Point_Ellipse (S.A, E, Point_D, Unused_Near, Unused_Fits);
         Fits := True;
         if abs Point_D
              <= P.Relative_Tolerance
                 * Long_Float'Max (E.Radius_X, E.Radius_Y)
         then
            Result := (Count => 1, P1 => S.A, P2 => P.Origin);
         end if;
         return;
      end if;
      Intersect_Line_Ellipse (L, E, Found, Fits);
      if not Fits then
         return;
      end if;
      if Found.Count >= 1 and then On_Segment (Found.P1) then
         Kept_1 := Snapped (Found.P1);
         Count := 1;
      end if;
      if Found.Count = 2 and then On_Segment (Found.P2) then
         if Count = 0 then
            Kept_1 := Snapped (Found.P2);
            Count := 1;
         else
            Kept_2 := Snapped (Found.P2);
            Count := 2;
         end if;
      end if;
      Result := (Count => Count, P1 => Kept_1, P2 => Kept_2);
   end Intersect_Segment_Ellipse;

   procedure Segment_Ellipse
     (S      : P.Segment;
      E      : Ellipse;
      D      : out P.Signed_Length;
      QS, QE : out P.Point;
      Fits   : out Boolean)
   is
      Crossings      : Two_Points;
      D_A, D_B       : P.Signed_Length;
      Near_A, Near_B : P.Point;
      Fits_A, Fits_B : Boolean;
   begin
      D := 0.0;
      QS := P.Origin;
      QE := P.Origin;
      Intersect_Segment_Ellipse (S, E, Crossings, Fits);
      if not Fits or else Crossings.Count > 0 then
         return;
      end if;
      Point_Ellipse (S.A, E, D_A, Near_A, Fits_A);
      Point_Ellipse (S.B, E, D_B, Near_B, Fits_B);
      if D_A < 0.0 and then D_B < 0.0 then
         --  Inside: the end point nearer the boundary.
         if D_A >= D_B then
            D := D_A;
            QS := S.A;
            QE := Near_A;
            Fits := Fits_A;
         else
            D := D_B;
            QS := S.B;
            QE := Near_B;
            Fits := Fits_B;
         end if;
      elsif D_A > 0.0 and then D_B > 0.0 then
         --  Outside: the nearer end point, or the point where the segment
         --  passes the ellipse's point nearest its line.
         if D_B < D_A then
            D := D_B;
            QS := S.B;
            QE := Near_B;
            Fits := Fits_B;
         else
            D := D_A;
            QS := S.A;
            QE := Near_A;
            Fits := Fits_A;
         end if;
         declare
            L          : constant P.Line := P.Line_Of (S);
            Length     : constant P.Length := P.Direction (S).Length;
            D_L        : P.Length;
            Q_L, Q_E   : P.Point;
            Fits_L     : Boolean;
            T          : P.Signed_Length;
         begin
            Line_Ellipse (L, E, D_L, Q_L, Q_E, Fits_L);
            T := P.Along (Q_L, L);
            if D_L > 0.0 and then Fits_L and then D_L < D
              and then T > 0.0 and then T < Length
            then
               D := D_L;
               QS := Q_L;
               QE := Q_E;
               Fits := True;
            end if;
         end;
      end if;
      if D = 0.0 then
         QS := P.Origin;
         QE := P.Origin;
      end if;
   end Segment_Ellipse;

end AMV.Kernels.Dimensioning.Ellipses;
