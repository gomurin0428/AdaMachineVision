pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Numerics;

package body AMV.Kernels.Dimensioning.Planar with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;

   ---------------------------------------------------------------------
   --  Basic quantities
   ---------------------------------------------------------------------

   function Distance (P, Q : Point) return Length is
     (N.Hypot (Q.X - P.X, Q.Y - P.Y));

   function Direction_Of (P, Q : Point) return Long_Float is
      DX : constant Long_Float := Q.X - P.X;
      DY : constant Long_Float := Q.Y - P.Y;
   begin
      if DX = 0.0 and then DY = 0.0 then
         return 0.0;
      end if;
      return N.Direction (DY, DX);
   end Direction_Of;

   function Offset (P : Point; L : Line) return Signed_Length is
     (N.Times_Unit (P.Y - L.P.Y, L.C) - N.Times_Unit (P.X - L.P.X, L.S));

   function Along (P : Point; L : Line) return Signed_Length is
     (N.Times_Unit (P.X - L.P.X, L.C) + N.Times_Unit (P.Y - L.P.Y, L.S));

   procedure Point_At
     (L    : Line;
      T    : Signed_Length;
      Q    : out Point;
      Fits : out Boolean)
   is
      X : constant Long_Float := L.P.X + N.Times_Unit (T, L.C);
      Y : constant Long_Float := L.P.Y + N.Times_Unit (T, L.S);
   begin
      Fits := Bounded (X) and then Bounded (Y);
      Q := (if Fits then (X, Y) else Origin);
   end Point_At;

   procedure Foot
     (P    : Point;
      L    : Line;
      Q    : out Point;
      Fits : out Boolean) is
   begin
      Point_At (L, Along (P, L), Q, Fits);
   end Foot;

   function Between (A, B : Coordinate; T : Long_Float) return Coordinate is
      V : Long_Float;
   begin
      if T = 0.0 then
         return A;
      end if;
      V := A + N.Times_Unit (B - A, T);
      return Long_Float'Max
        (Long_Float'Min (A, B), Long_Float'Min (Long_Float'Max (A, B), V));
   end Between;

   function Point_Between (A, B : Point; T : Long_Float) return Point is
     ((Between (A.X, B.X, T), Between (A.Y, B.Y, T)));

   procedure Point_Towards
     (C    : Point;
      R    : Radius_Value;
      UX   : Unit;
      UY   : Unit;
      Q    : out Point;
      Fits : out Boolean)
   is
      X : constant Long_Float := C.X + N.Times_Unit (R, UX);
      Y : constant Long_Float := C.Y + N.Times_Unit (R, UY);
   begin
      Fits := Bounded (X) and then Bounded (Y);
      Q := (if Fits then (X, Y) else Origin);
   end Point_Towards;

   procedure Unit_Of
     (DX, DY : Long_Float;
      Len    : Long_Float;
      UX, UY : out Unit)
   with Pre => Len > 0.0;
   --  (DX, DY) / Len, each component limited to [-1, 1] (Len is the
   --  length of the vector, never shorter than a component).

   procedure Unit_Of
     (DX, DY : Long_Float;
      Len    : Long_Float;
      UX, UY : out Unit) is
   begin
      UX := N.Unit_Ratio (N.Clamp (DX, Len), Len);
      UY := N.Unit_Ratio (N.Clamp (DY, Len), Len);
   end Unit_Of;

   function Direction (S : Segment) return Direction_Info is
      DX     : constant Long_Float := S.B.X - S.A.X;
      DY     : constant Long_Float := S.B.Y - S.A.Y;
      Result : Direction_Info;
   begin
      Result.Length := N.Hypot (DX, DY);
      if Result.Length > 0.0 then
         Unit_Of (DX, DY, Result.Length, Result.UX, Result.UY);
      end if;
      return Result;
   end Direction;

   function Line_Of (S : Segment) return Line is
      D : constant Direction_Info := Direction (S);
   begin
      return (P        => S.A,
              C        => D.UX,
              S        => D.UY,
              Rotation => Direction_Of (S.A, S.B));
   end Line_Of;

   procedure Closest_On_Segment
     (P : Point;
      S : Segment;
      Q : out Point)
   is
      D : constant Direction_Info := Direction (S);
      T : Long_Float;
   begin
      if D.Length = 0.0 then
         Q := S.A;
         return;
      end if;
      T := N.Times_Unit (P.X - S.A.X, D.UX)
           + N.Times_Unit (P.Y - S.A.Y, D.UY);
      if T <= 0.0 then
         Q := S.A;
      elsif T >= D.Length then
         Q := S.B;
      else
         Q := Point_Between
           (S.A, S.B, Long_Float'Max (0.0, N.Unit_Ratio (T, D.Length)));
      end if;
   end Closest_On_Segment;

   ---------------------------------------------------------------------
   --  Crossings
   ---------------------------------------------------------------------

   function Same_Side (A, B : Long_Float) return Boolean is
     ((A > 0.0 and then B > 0.0) or else (A < 0.0 and then B < 0.0));
   --  A and B are both strictly positive or both strictly negative.

   function Crossing_Point (A, B : Point; DA, DB : Long_Float) return Point
   is
      Sum : constant Long_Float := abs DA + abs DB;
   begin
      if Sum > 0.0 then
         return Point_Between
           (A, B, Long_Float'Max (0.0, N.Unit_Ratio (N.Clamp (abs DA, Sum),
                                                     Sum)));
      else
         return A;
      end if;
   end Crossing_Point;
   --  The point between A and B where a quantity that is DA at A and DB at
   --  B (of opposite signs, or one of them 0) changes sign, linearly.

   procedure Intersect_Segment_Line
     (S      : Segment;
      L      : Line;
      Result : out Crossing)
   is
      SA  : constant Signed_Length := Offset (S.A, L);
      SB  : constant Signed_Length := Offset (S.B, L);
      D   : constant Direction_Info := Direction (S);
      Tol : constant Long_Float :=
        Relative_Tolerance * Long_Float'Max (1.0, D.Length);
   begin
      if abs SA <= Tol and then abs SB <= Tol then
         if D.Length = 0.0 then
            Result := (Count => 1, Where => S.A);
         else
            Result := (Count => -1, Where => Origin);
         end if;
      elsif Same_Side (SA, SB) then
         Result := (Count => 0, Where => Origin);
      elsif SA = 0.0 then
         Result := (Count => 1, Where => S.A);
      elsif SB = 0.0 then
         Result := (Count => 1, Where => S.B);
      else
         Result := (Count => 1, Where => Crossing_Point (S.A, S.B, SA, SB));
      end if;
   end Intersect_Segment_Line;

   procedure Point_On_Segment
     (P      : Point;
      S      : Segment;
      Tol    : Long_Float;
      Result : out Crossing)
   with Post => Valid_Crossing (Result);
   --  Count 1 at P when P lies within Tol of the segment S (of a length
   --  > 0), otherwise 0.

   procedure Point_On_Segment
     (P      : Point;
      S      : Segment;
      Tol    : Long_Float;
      Result : out Crossing)
   is
      L : constant Line := Line_Of (S);
      D : constant Direction_Info := Direction (S);
      T : constant Signed_Length := Along (P, L);
   begin
      if abs Offset (P, L) <= Tol and then T >= -Tol
        and then T <= D.Length + Tol
      then
         Result := (Count => 1, Where => P);
      else
         Result := (Count => 0, Where => Origin);
      end if;
   end Point_On_Segment;

   procedure Intersect_Collinear
     (S1, S2 : Segment;
      Tol    : Long_Float;
      Result : out Crossing)
   with Pre  => Tol >= 0.0,
        Post => Valid_Crossing (Result);
   --  S1 (of a length > 0) and S2 on one line: -1 when they overlap along
   --  more than Tol, 1 at the shared point when they only touch, else 0.

   procedure Intersect_Collinear
     (S1, S2 : Segment;
      Tol    : Long_Float;
      Result : out Crossing)
   is
      L1   : constant Line := Line_Of (S1);
      Len  : constant Length := Direction (S1).Length;
      TA   : constant Signed_Length := Along (S2.A, L1);
      TB   : constant Signed_Length := Along (S2.B, L1);
      Lo   : constant Long_Float :=
        Long_Float'Max (0.0, Long_Float'Min (TA, TB));
      Hi   : constant Long_Float :=
        Long_Float'Min (Len, Long_Float'Max (TA, TB));
      Mid  : Long_Float;
   begin
      if Hi - Lo > Tol then
         Result := (Count => -1, Where => Origin);
      elsif Hi - Lo >= -Tol and then Len > 0.0 then
         --  They share (about) one point: the middle of the overlap,
         --  limited to S1.
         Mid := Long_Float'Max
           (0.0, Long_Float'Min (Len, Lo / 2.0 + Hi / 2.0));
         Result := (Count => 1,
                    Where => Point_Between
                      (S1.A, S1.B,
                       Long_Float'Max
                         (0.0, N.Unit_Ratio (Mid, Len))));
      else
         Result := (Count => 0, Where => Origin);
      end if;
   end Intersect_Collinear;

   procedure Intersect_Segments
     (S1, S2 : Segment;
      Result : out Crossing)
   is
      D1  : constant Direction_Info := Direction (S1);
      D2  : constant Direction_Info := Direction (S2);
      Tol : constant Long_Float :=
        Relative_Tolerance
        * Long_Float'Max (1.0, Long_Float'Max (D1.Length, D2.Length));
   begin
      if D1.Length = 0.0 and then D2.Length = 0.0 then
         if S1.A = S2.A then
            Result := (Count => 1, Where => S1.A);
         else
            Result := (Count => 0, Where => Origin);
         end if;
      elsif D1.Length = 0.0 then
         Point_On_Segment (S1.A, S2, Tol, Result);
      elsif D2.Length = 0.0 then
         Point_On_Segment (S2.A, S1, Tol, Result);
      else
         declare
            Sine : constant Long_Float :=
              N.Times_Unit (D1.UX, D2.UY) - N.Times_Unit (D1.UY, D2.UX);
            L1   : constant Line := Line_Of (S1);
            L2   : constant Line := Line_Of (S2);
         begin
            if abs Sine <= Parallel_Tolerance then
               if abs Offset (S2.A, L1) <= Tol
                 and then abs Offset (S2.B, L1) <= Tol
               then
                  Intersect_Collinear (S1, S2, Tol, Result);
               else
                  Result := (Count => 0, Where => Origin);
               end if;
            else
               declare
                  DA : constant Signed_Length := Offset (S1.A, L2);
                  DB : constant Signed_Length := Offset (S1.B, L2);
                  DC : constant Signed_Length := Offset (S2.A, L1);
                  DD : constant Signed_Length := Offset (S2.B, L1);
               begin
                  if Same_Side (DA, DB) or else Same_Side (DC, DD) then
                     Result := (Count => 0, Where => Origin);
                  else
                     Result := (Count => 1,
                                Where => Crossing_Point (S1.A, S1.B, DA, DB));
                  end if;
               end;
            end if;
         end;
      end if;
   end Intersect_Segments;

   procedure Intersect_Lines
     (L1, L2 : Line;
      Result : out Crossing;
      Fits   : out Boolean)
   is
      Sine : constant Long_Float :=
        N.Times_Unit (L1.C, L2.S) - N.Times_Unit (L1.S, L2.C);
      --  sin (L2.Rotation - L1.Rotation)
      Num  : Signed_Length;
      T    : Long_Float;
      Q    : Point;
   begin
      Fits := True;
      if abs Sine <= Parallel_Tolerance then
         if abs Offset (L2.P, L1)
              <= Relative_Tolerance
                 * Long_Float'Max (1.0, Distance (L1.P, L2.P))
         then
            Result := (Count => -1, Where => Origin);
         else
            Result := (Count => 0, Where => Origin);
         end if;
         return;
      end if;
      --  L1.P + T (C1, S1) lies on L2 when its offset from L2,
      --  Offset (L1.P, L2) - T Sine, is 0.
      Num := Offset (L1.P, L2);
      N.Ratio_Within (abs Num, abs Sine, 4.0 * Max_Value, T, Fits);
      if not Fits then
         --  |T| > 4.0E150: the point lies beyond the bound.
         Result := (Count => 0, Where => Origin);
         return;
      end if;
      if (Num < 0.0) /= (Sine < 0.0) then
         T := -T;
      end if;
      Point_At (L1, T, Q, Fits);
      if Fits then
         Result := (Count => 1, Where => Q);
      else
         Result := (Count => 0, Where => Origin);
      end if;
   end Intersect_Lines;

   ---------------------------------------------------------------------
   --  Distances
   ---------------------------------------------------------------------

   procedure Segment_Segment
     (S1, S2 : Segment;
      D      : out Length;
      Q1, Q2 : out Point)
   is
      X      : Crossing;
      C      : Point;
      Trial  : Length;
   begin
      Intersect_Segments (S1, S2, X);
      if X.Count /= 0 then
         D := 0.0;
         Q1 := Origin;
         Q2 := Origin;
         return;
      end if;
      --  The distance between segments that do not meet is reached at an
      --  end point of one of them.
      Closest_On_Segment (S1.A, S2, C);
      D := Distance (S1.A, C);
      Q1 := S1.A;
      Q2 := C;
      Closest_On_Segment (S1.B, S2, C);
      Trial := Distance (S1.B, C);
      if Trial < D then
         D := Trial;
         Q1 := S1.B;
         Q2 := C;
      end if;
      Closest_On_Segment (S2.A, S1, C);
      Trial := Distance (S2.A, C);
      if Trial < D then
         D := Trial;
         Q1 := C;
         Q2 := S2.A;
      end if;
      Closest_On_Segment (S2.B, S1, C);
      Trial := Distance (S2.B, C);
      if Trial < D then
         D := Trial;
         Q1 := C;
         Q2 := S2.B;
      end if;
      if D = 0.0 then
         Q1 := Origin;
         Q2 := Origin;
      end if;
   end Segment_Segment;

   procedure Segment_Line
     (S      : Segment;
      L      : Line;
      D      : out Length;
      QS, QL : out Point;
      Fits   : out Boolean)
   is
      SA : constant Signed_Length := Offset (S.A, L);
      SB : constant Signed_Length := Offset (S.B, L);
   begin
      if not Same_Side (SA, SB) then
         D := 0.0;
         QS := Origin;
         QL := Origin;
         Fits := True;
      elsif abs SB < abs SA then
         D := abs SB;
         QS := S.B;
         Foot (S.B, L, QL, Fits);
      else
         D := abs SA;
         QS := S.A;
         Foot (S.A, L, QL, Fits);
      end if;
   end Segment_Line;

   procedure Point_Circle
     (P    : Point;
      C    : Circle;
      D    : out Signed_Length;
      Q    : out Point;
      Fits : out Boolean)
   is
      DX   : constant Long_Float := P.X - C.Center.X;
      DY   : constant Long_Float := P.Y - C.Center.Y;
      Dist : constant Length := N.Hypot (DX, DY);
      UX   : Unit;
      UY   : Unit;
   begin
      if Dist = 0.0 then
         --  At the centre: +Radius and the point at angle 0, as the
         --  reference documents.
         D := C.Radius;
         Point_Towards (C.Center, C.Radius, 1.0, 0.0, Q, Fits);
         return;
      end if;
      D := Dist - C.Radius;
      if D = 0.0 then
         Q := P;
         Fits := True;
      else
         Unit_Of (DX, DY, Dist, UX, UY);
         Point_Towards (C.Center, C.Radius, UX, UY, Q, Fits);
      end if;
   end Point_Circle;

   procedure Line_Circle
     (L      : Line;
      C      : Circle;
      D      : out Length;
      QL, QC : out Point;
      Fits   : out Boolean)
   is
      Off       : constant Signed_Length := Offset (C.Center, L);
      Gap       : constant Long_Float := abs Off - C.Radius;
      Fits_Line : Boolean;
   begin
      if Gap <= 0.0 then
         D := 0.0;
         QL := Origin;
         QC := Origin;
         Fits := True;
         return;
      end if;
      D := Gap;
      Foot (C.Center, L, QL, Fits_Line);
      --  The centre lies on the side of the left normal (-S, C) when Off
      --  is positive, so the line lies towards (S, -C) from it.
      if Off > 0.0 then
         Point_Towards (C.Center, C.Radius, L.S, -L.C, QC, Fits);
      else
         Point_Towards (C.Center, C.Radius, -L.S, L.C, QC, Fits);
      end if;
      Fits := Fits and then Fits_Line;
   end Line_Circle;

   procedure Segment_Circle
     (S      : Segment;
      C      : Circle;
      D      : out Signed_Length;
      QS, QC : out Point;
      Fits   : out Boolean)
   is
      Near  : Point;
      D_Min : Length;
      D_A   : constant Length := Distance (C.Center, S.A);
      D_B   : constant Length := Distance (C.Center, S.B);
      UX    : Unit;
      UY    : Unit;
   begin
      Closest_On_Segment (C.Center, S, Near);
      D_Min := Distance (C.Center, Near);
      if D_Min > C.Radius then
         --  Outside the circle.
         D := D_Min - C.Radius;
         QS := Near;
         Unit_Of (Near.X - C.Center.X, Near.Y - C.Center.Y, D_Min, UX, UY);
         Point_Towards (C.Center, C.Radius, UX, UY, QC, Fits);
      elsif D_A < C.Radius and then D_B < C.Radius then
         --  Inside: the end point farther from the centre is nearest the
         --  circle.
         if D_A >= D_B then
            D := D_A - C.Radius;
            QS := S.A;
         else
            D := D_B - C.Radius;
            QS := S.B;
         end if;
         if Long_Float'Max (D_A, D_B) > 0.0 then
            Unit_Of (QS.X - C.Center.X, QS.Y - C.Center.Y,
                     Long_Float'Max (D_A, D_B), UX, UY);
         else
            UX := 1.0;
            UY := 0.0;
         end if;
         Point_Towards (C.Center, C.Radius, UX, UY, QC, Fits);
      else
         D := 0.0;
         QS := Origin;
         QC := Origin;
         Fits := True;
      end if;
   end Segment_Circle;

   procedure Circle_Circle
     (C1, C2 : Circle;
      D      : out Signed_Length;
      Q1, Q2 : out Point;
      Fits   : out Boolean)
   is
      DX   : constant Long_Float := C2.Center.X - C1.Center.X;
      DY   : constant Long_Float := C2.Center.Y - C1.Center.Y;
      Dist : constant Length := N.Hypot (DX, DY);
      R1   : constant Radius_Value := C1.Radius;
      R2   : constant Radius_Value := C2.Radius;
      UX   : Unit;
      UY   : Unit;
      Fits_2 : Boolean;
   begin
      if Dist = 0.0 then
         if R1 = R2 then
            D := 0.0;
            Q1 := Origin;
            Q2 := Origin;
            Fits := True;
         else
            --  Concentric: the points at angle 0.
            D := -abs (R1 - R2);
            Point_Towards (C1.Center, R1, 1.0, 0.0, Q1, Fits);
            Point_Towards (C2.Center, R2, 1.0, 0.0, Q2, Fits_2);
            Fits := Fits and then Fits_2;
         end if;
         return;
      end if;
      Unit_Of (DX, DY, Dist, UX, UY);
      if Dist > R1 + R2 then
         --  Apart: the facing points on the line of the centres.
         D := Dist - (R1 + R2);
         Point_Towards (C1.Center, R1, UX, UY, Q1, Fits);
         Point_Towards (C2.Center, R2, -UX, -UY, Q2, Fits_2);
         Fits := Fits and then Fits_2;
      elsif Dist < abs (R1 - R2) then
         --  One inside the other: the facing points lie on the side of
         --  the inner centre, seen from the outer one.
         D := Dist - abs (R1 - R2);
         if R1 > R2 then
            Point_Towards (C1.Center, R1, UX, UY, Q1, Fits);
            Point_Towards (C2.Center, R2, UX, UY, Q2, Fits_2);
         else
            Point_Towards (C1.Center, R1, -UX, -UY, Q1, Fits);
            Point_Towards (C2.Center, R2, -UX, -UY, Q2, Fits_2);
         end if;
         Fits := Fits and then Fits_2;
      else
         D := 0.0;
         Q1 := Origin;
         Q2 := Origin;
         Fits := True;
      end if;
   end Circle_Circle;

end AMV.Kernels.Dimensioning.Planar;
