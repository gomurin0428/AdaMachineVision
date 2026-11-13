pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Numerics;

package body AMV.Kernels.PM_Align.Overlaps with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;

   Max_Vertices : constant := 8;
   --  A convex quadrilateral clipped by the four half-planes of another:
   --  each clip adds at most one corner.

   type Point_Array is array (0 .. Max_Vertices - 1) of Point;

   type Polygon is record
      Count    : Natural range 0 .. Max_Vertices := 0;
      Vertices : Point_Array;
   end record;

   Max_Cross : constant := 2.0 ** 84;
   --  The bound of a cross product of two differences of coordinates
   --  (each within 2**41).

   subtype Cross_Value is Long_Float range -Max_Cross .. Max_Cross;

   function Cross (O, P, Q : Point) return Cross_Value is
     ((P.X - O.X) * (Q.Y - O.Y) - (P.Y - O.Y) * (Q.X - O.X));
   --  (P - O) x (Q - O): positive when Q lies to the left of O -> P.

   function Signed_Area (V : Point_Array; Count : Natural) return Long_Float
   with Pre  => Count <= Max_Vertices,
        Post => abs Signed_Area'Result <= 2.0 ** 87;
   --  Half the shoelace sum of the polygon V (0 .. Count - 1): positive
   --  for corners counter-clockwise (y up).

   function Signed_Area (V : Point_Array; Count : Natural) return Long_Float
   is
      Sum : Long_Float := 0.0;
   begin
      for I in 0 .. Count - 1 loop
         pragma Loop_Invariant (abs Sum <= 2.0 ** 86);
         declare
            Next : constant Natural := (if I = Count - 1 then 0 else I + 1);
            Term : constant Long_Float :=
              V (I).X * V (Next).Y - V (Next).X * V (I).Y;
         begin
            --  At most 8 terms within 2**81 each: the limit never acts.
            Sum := N.Clamp (Sum + Term, 2.0 ** 86);
         end;
      end loop;
      return Sum / 2.0;
   end Signed_Area;

   procedure Clip
     (Subject : Polygon;
      E1, E2  : Point;
      Sign    : Long_Float;
      Result  : out Polygon)
   with Pre => Sign = 1.0 or else Sign = -1.0;
   --  The part of Subject on the inner side of the line E1 -> E2 (the side
   --  where Sign * Cross (E1, E2, P) >= 0).

   procedure Clip
     (Subject : Polygon;
      E1, E2  : Point;
      Sign    : Long_Float;
      Result  : out Polygon)
   is
      procedure Add (P : Point) with Global => (In_Out => Result);
      procedure Add (P : Point) is
      begin
         --  At most one more corner than Subject: the limit never acts.
         if Result.Count < Max_Vertices then
            Result.Vertices (Result.Count) := P;
            Result.Count := Result.Count + 1;
         end if;
      end Add;
   begin
      Result := (Count => 0, Vertices => [others => (others => <>)]);
      for I in 0 .. Subject.Count - 1 loop
         declare
            P  : constant Point := Subject.Vertices (I);
            Q  : constant Point :=
              Subject.Vertices (if I = Subject.Count - 1 then 0 else I + 1);
            CP : constant Long_Float := Sign * Cross (E1, E2, P);
            CQ : constant Long_Float := Sign * Cross (E1, E2, Q);
         begin
            if CP >= 0.0 then
               Add (P);
            end if;
            if (CP >= 0.0) /= (CQ >= 0.0) then
               declare
                  --  P and Q lie on opposite sides: the crossing is at the
                  --  fraction CP / (CP - CQ) of the way from P to Q.
                  Den : constant Long_Float := CP - CQ;
                  T   : constant Long_Float :=
                    (if Den /= 0.0
                       and then abs CP <= abs Den
                     then N.Unit_Ratio (CP, abs Den) * (if Den < 0.0
                                                        then -1.0 else 1.0)
                     else 0.0);
                  U   : constant Long_Float := N.Clamp_Unit (T);
               begin
                  Add ((X => N.Clamp (P.X + N.Times_Unit (Q.X - P.X, U),
                                      Max_Coordinate),
                        Y => N.Clamp (P.Y + N.Times_Unit (Q.Y - P.Y, U),
                                      Max_Coordinate)));
               end;
            end if;
         end;
      end loop;
   end Clip;

   function Overlap_Fraction (A, B : Quad) return Long_Float is
      Subject : Polygon;
      Next    : Polygon;
      Area_A, Area_B, Smaller, Shared : Long_Float;
      Sign    : Long_Float;
   begin
      Subject.Count := 4;
      Subject.Vertices := [others => (others => <>)];
      for I in 0 .. 3 loop
         Subject.Vertices (I) := A (I);
      end loop;
      Area_A := abs Signed_Area (Subject.Vertices, 4);
      declare
         BV : Point_Array := [others => (others => <>)];
      begin
         for I in 0 .. 3 loop
            BV (I) := B (I);
         end loop;
         Area_B := Signed_Area (BV, 4);
      end;
      Sign := (if Area_B >= 0.0 then 1.0 else -1.0);
      Area_B := abs Area_B;
      Smaller := Long_Float'Min (Area_A, Area_B);
      if Smaller < 1.0E-6 then
         return 0.0;
      end if;
      for E in 0 .. 3 loop
         Clip (Subject, B (E), B (if E = 3 then 0 else E + 1), Sign, Next);
         Subject := Next;
      end loop;
      Shared := abs Signed_Area (Subject.Vertices, Subject.Count);
      --  Shared is at most the smaller area but for rounding; the quotient
      --  is at most 2**87 / 1.0E-6.
      return N.Clamp_Unit (Shared / Smaller);
   end Overlap_Fraction;

end AMV.Kernels.PM_Align.Overlaps;
