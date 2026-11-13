--  The plane geometry of the dimensioning tools without ellipses: points,
--  lines, segments and circles that already lie in the measuring space and
--  within the kernel's bounds (the parent checks and maps every input
--  first). Internal: every subprogram has a precondition and no status;
--  a result point that would leave the bound is reported through a Fits
--  flag, and the caller turns it into Bad_Parameter.
--
--  The meaning of every result is documented with the entry points in
--  AMV.Kernels.Dimensioning; the comments here say how it is computed.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.Dimensioning.Planar
  with SPARK_Mode, Preelaborate
is

   subtype Coordinate is Long_Float range -Max_Value .. Max_Value;
   subtype Length is Long_Float range 0.0 .. Max_Length;
   subtype Signed_Length is Long_Float range -Max_Length .. Max_Length;
   subtype Unit is Long_Float range -1.0 .. 1.0;
   subtype Radius_Value is Long_Float range 0.0 .. Max_Value;
   subtype Angle_Value is Long_Float range -Pi .. Pi;

   type Point is record
      X, Y : Coordinate := 0.0;
   end record;

   Origin : constant Point := (0.0, 0.0);

   type Segment is record
      A, B : Point;
   end record;
   --  From A to B.

   type Line is record
      P        : Point;
      C        : Unit := 1.0;
      S        : Unit := 0.0;
      Rotation : Coordinate := 0.0;
   end record;
   --  The line through P with direction Rotation, whose cosine and sine
   --  are C and S. Its left normal is (-S, C).

   type Circle is record
      Center : Point;
      Radius : Radius_Value := 0.0;
   end record;

   Parallel_Tolerance : constant := 1.0E-12;
   Relative_Tolerance : constant := 1.0E-9;
   --  The tolerances documented in AMV.Kernels.Dimensioning.

   ---------------------------------------------------------------------
   --  Basic quantities
   ---------------------------------------------------------------------

   function Distance (P, Q : Point) return Length;
   --  |Q - P| without intermediate overflow.

   function Direction_Of (P, Q : Point) return Long_Float
   with Post => Direction_Of'Result > -Pi and then Direction_Of'Result <= Pi;
   --  The direction from P to Q in (-Pi, Pi]; 0 when they coincide.

   function Offset (P : Point; L : Line) return Signed_Length;
   --  The signed distance of P from L: (P - L.P) . (-S, C).

   function Along (P : Point; L : Line) return Signed_Length;
   --  The coordinate of P's foot along L, from L.P: (P - L.P) . (C, S).

   procedure Point_At
     (L    : Line;
      T    : Signed_Length;
      Q    : out Point;
      Fits : out Boolean)
   with Post => (if not Fits then Q = Origin);
   --  L.P + T (C, S); Fits is False (and Q the origin) when that would
   --  leave the bound.

   procedure Foot
     (P    : Point;
      L    : Line;
      Q    : out Point;
      Fits : out Boolean)
   with Post => (if not Fits then Q = Origin);
   --  The foot of the perpendicular from P to L (Point_At (L, Along)).

   function Between (A, B : Coordinate; T : Long_Float) return Coordinate
   with
     Pre  => T >= 0.0 and then T <= 1.0,
     Post => Between'Result >= Long_Float'Min (A, B)
             and then Between'Result <= Long_Float'Max (A, B)
             and then (if T = 0.0 then Between'Result = A);
   --  A + T (B - A), kept between A and B (rounding could otherwise step
   --  past B by an ulp).

   function Point_Between (A, B : Point; T : Long_Float) return Point
   with Pre => T >= 0.0 and then T <= 1.0;
   --  A + T (B - A), coordinate by coordinate as Between.

   procedure Point_Towards
     (C    : Point;
      R    : Radius_Value;
      UX   : Unit;
      UY   : Unit;
      Q    : out Point;
      Fits : out Boolean)
   with Post => (if not Fits then Q = Origin);
   --  C + R (UX, UY); Fits as for Point_At.

   type Direction_Info is record
      Length : Planar.Length := 0.0;
      UX     : Unit := 1.0;
      UY     : Unit := 0.0;
   end record;

   function Direction (S : Segment) return Direction_Info
   with Post => (if Direction'Result.Length = 0.0
                 then Direction'Result.UX = 1.0
                      and then Direction'Result.UY = 0.0);
   --  The length of S and its unit direction ((1, 0) for no length).

   function Line_Of (S : Segment) return Line;
   --  The line through S.A in the direction of S (Rotation 0 for a
   --  segment of no length).

   procedure Closest_On_Segment
     (P : Point;
      S : Segment;
      Q : out Point);
   --  The point of S nearest P.

   ---------------------------------------------------------------------
   --  Crossings
   ---------------------------------------------------------------------

   type Crossing is record
      Count : Int32 range -1 .. 1 := 0;
      Where : Point;
   end record;
   --  -1: the shapes overlap along a piece of a line; 0: they do not meet;
   --  1: they meet at Where (the origin otherwise).

   function Valid_Crossing (C : Crossing) return Boolean is
     (if C.Count /= 1 then C.Where = Origin);

   procedure Intersect_Segment_Line
     (S      : Segment;
      L      : Line;
      Result : out Crossing)
   with Post => Valid_Crossing (Result);

   procedure Intersect_Segments
     (S1, S2 : Segment;
      Result : out Crossing)
   with Post => Valid_Crossing (Result);

   procedure Intersect_Lines
     (L1, L2 : Line;
      Result : out Crossing;
      Fits   : out Boolean)
   with Post => Valid_Crossing (Result)
                and then (if not Fits then Result.Count = 0);
   --  Fits is False when the crossing point would leave the bound.

   ---------------------------------------------------------------------
   --  Distances
   ---------------------------------------------------------------------

   procedure Segment_Segment
     (S1, S2 : Segment;
      D      : out Length;
      Q1, Q2 : out Point)
   with Post => (if D = 0.0 then Q1 = Origin and then Q2 = Origin);

   procedure Segment_Line
     (S      : Segment;
      L      : Line;
      D      : out Length;
      QS, QL : out Point;
      Fits   : out Boolean)
   with Post => (if D = 0.0 then QS = Origin and then QL = Origin);

   procedure Point_Circle
     (P    : Point;
      C    : Circle;
      D    : out Signed_Length;
      Q    : out Point;
      Fits : out Boolean)
   with Post => D >= -C.Radius;

   procedure Line_Circle
     (L      : Line;
      C      : Circle;
      D      : out Length;
      QL, QC : out Point;
      Fits   : out Boolean)
   with Post => (if D = 0.0 then QL = Origin and then QC = Origin);

   procedure Segment_Circle
     (S      : Segment;
      C      : Circle;
      D      : out Signed_Length;
      QS, QC : out Point;
      Fits   : out Boolean)
   with Post => (if D = 0.0 then QS = Origin and then QC = Origin);

   procedure Circle_Circle
     (C1, C2 : Circle;
      D      : out Signed_Length;
      Q1, Q2 : out Point;
      Fits   : out Boolean)
   with Post => (if D = 0.0 then Q1 = Origin and then Q2 = Origin);

end AMV.Kernels.Dimensioning.Planar;
