pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;

package body AMV.Kernels.Code_Reader.Data_Matrix.Finder
  with SPARK_Mode
is

   package EF renames Ada.Numerics.Long_Elementary_Functions;

   use type DA.Mark;

   Inset : constant := 1.5;
   --  How far inside a side its pixels are looked at, in pixels.

   Min_Side : constant := 10.0;
   --  The shortest side of a symbol, in pixels.

   Solid_Share : constant := 0.85;
   --  The share of dark pixels along a solid side, at least.

   Num_Depths : constant := 3;

   Depths : constant array (1 .. Num_Depths) of Long_Float :=
     [1.5, 2.5, 4.0];
   --  How far inside a side it is looked at for being solid, in pixels:
   --  the side of a dark area is not as straight as its hull, and a side
   --  is solid when it is so at one of these depths.

   Straight : constant := 1.25;
   --  How far the corners of the hull along a straight side may be from
   --  the line, in pixels.

   Covered : constant := 0.5;
   --  The part of an alternating side along which the hull of a symbol
   --  is straight, at least.

   Trusted : constant := 0.25;
   --  The part of the alternating sides from which the upper right
   --  corner is taken, at least.

   Seen : constant := 0.5;
   --  The upper right corner of a symbol is at least Seen times, and at
   --  most 1 / Seen times, as far from the line through the two ends of
   --  the L as the lower left corner, on the other side of it: no symbol
   --  is seen at a steeper angle than that.

   Near : constant := 4.0;
   --  How far from the corner of the hull the lines of two sides may
   --  meet, in pixels, to be taken as the corner.

   Loose : constant := 2.0 * Straight;
   --  How far the line of an alternating side may pass from the end of
   --  the L, and how far from a corner of the hull next to the corner of
   --  a symbol the lines of two sides may meet, in pixels.

   Narrow : constant := 2.0;
   --  How far around an outline the dark pixels belong to the symbol,
   --  in pixels.

   Settled : constant := 0.5;
   --  The corners of an outline have settled when they move by no more
   --  than this from one round to the next, in pixels (the sum).

   Rounds : constant := 8;
   --  The rounds of Refine, at most.

   ---------------------------------------------------------------------
   --  Points
   ---------------------------------------------------------------------

   function To_Corner (P : DA.Point) return Corner is
     (X => Long_Float (P.X), Y => Long_Float (P.Y))
   with Pre => P.X in 0 .. DA.Max_Side and then P.Y in 0 .. DA.Max_Side;

   function Distance (A, B : Corner) return Long_Float is
     (EF.Sqrt ((B.X - A.X) ** 2 + (B.Y - A.Y) ** 2));

   function Fourth (A, B, C : Corner) return Corner is
     (if abs (A.X + B.X - C.X) < Limit and then abs (A.Y + B.Y - C.Y) < Limit
      then (A.X + B.X - C.X, A.Y + B.Y - C.Y) else C);
   --  The corner opposite C of the parallelogram with the sides from C
   --  to A and from C to B.

   function Off_Line (A, B, P : Corner) return Long_Float is
     ((B.X - A.X) * (P.Y - A.Y) - (B.Y - A.Y) * (P.X - A.X));
   --  The distance of P from the line from A to B, times the length of
   --  the line; positive on the right of the line as the image is seen.

   function Dark_At (Map : DA.Mark_Map; X, Y : Long_Float) return Boolean
   is
     (X >= 0.0 and then Y >= 0.0
      and then X < Long_Float (Map'Length (2))
      and then Y < Long_Float (Map'Length (1))
      and then Map (Natural (Long_Float'Floor (Y)),
                    Natural (Long_Float'Floor (X))) /= DA.Light)
   with Pre => DA.Valid_Map (Map);
   --  The pixel that holds the point is dark (outside the map: light).

   ---------------------------------------------------------------------
   --  A side
   ---------------------------------------------------------------------

   procedure Scan_Side
     (Map     : DA.Mark_Map;
      A, B    : Corner;
      Depth   : Long_Float;
      Lo, Hi  : Long_Float;
      Dark    : out Natural;
      Total   : out Natural;
      Changes : out Natural)
   with Pre => DA.Valid_Map (Map);
   --  Looks at the pixels along the line from A to B, Depth pixels to
   --  the right of it (inside a symbol that is gone around clockwise),
   --  every half pixel between the shares Lo and Hi of the way. Total:
   --  the points looked at; Dark: those that are dark; Changes: the
   --  changes between dark and light that last for two points.

   procedure Scan_Side
     (Map     : DA.Mark_Map;
      A, B    : Corner;
      Depth   : Long_Float;
      Lo, Hi  : Long_Float;
      Dark    : out Natural;
      Total   : out Natural;
      Changes : out Natural)
   is
      Length : constant Long_Float := Distance (A, B);
      UX, UY : Long_Float;
      X0, Y0 : Long_Float;
      Steps  : Natural;
      T      : Long_Float;
      Now    : Boolean;
      State  : Boolean := False;
      Odd    : Boolean := False;
   begin
      Dark := 0;
      Total := 0;
      Changes := 0;
      if Length < Min_Side or else Length > Limit then
         return;
      end if;
      UX := (B.X - A.X) / Length;
      UY := (B.Y - A.Y) / Length;
      X0 := A.X - UY * Depth;
      Y0 := A.Y + UX * Depth;
      Steps := Natural (Long_Float'Floor ((Hi - Lo) * Length * 2.0));
      for I in 0 .. Steps loop
         T := Lo * Length + 0.5 * Long_Float (I);
         Now := Dark_At (Map, X0 + UX * T, Y0 + UY * T);
         if Now then
            Dark := Dark + 1;
         end if;
         if I = 0 then
            State := Now;
         elsif Now = State then
            Odd := False;
         elsif Odd then
            State := Now;
            Odd := False;
            Changes := Changes + 1;
         else
            Odd := True;
         end if;
         Total := Total + 1;
      end loop;
   end Scan_Side;

   subtype Solidity is Natural range 0 .. Num_Depths;

   function Solid_At
     (Map  : DA.Mark_Map;
      A, B : Corner) return Solidity
   with Pre => DA.Valid_Map (Map);
   --  The first of the Depths at which the side from A to B is solid
   --  (0: at none).

   function Solid_At
     (Map  : DA.Mark_Map;
      A, B : Corner) return Solidity
   is
      Dark, Total, Changes : Natural;
   begin
      for K in Depths'Range loop
         Scan_Side (Map, A, B, Depths (K), 0.05, 0.95, Dark, Total, Changes);
         if Total > 0
           and then Long_Float (Dark) >= Solid_Share * Long_Float (Total)
         then
            return K;
         end if;
      end loop;
      return 0;
   end Solid_At;

   ---------------------------------------------------------------------
   --  The corners
   ---------------------------------------------------------------------

   function Valid_Hull (Hull : DA.Point_Array) return Boolean is
     (Hull'First = 1 and then Hull'Length >= 4
      and then (for all P of Hull => P.X in 0 .. DA.Max_Side
                                     and then P.Y in 0 .. DA.Max_Side));

   function Place
     (Hull  : DA.Point_Array;
      First : Positive;
      T     : Natural) return Positive
   is ((First - 1 + T) mod Hull'Length + 1)
   with Pre => Valid_Hull (Hull) and then First <= Hull'Last
               and then T <= Hull'Length;
   --  The place in Hull of the corner T corners after the corner First.

   function At_Place
     (Hull  : DA.Point_Array;
      First : Positive;
      T     : Natural) return Corner
   is (To_Corner (Hull (Place (Hull, First, T))))
   with Pre => Valid_Hull (Hull) and then First <= Hull'Last
               and then T <= Hull'Length;

   function Deviation
     (Hull     : DA.Point_Array;
      First    : Positive;
      From, To : Natural) return Long_Float
   with Pre => Valid_Hull (Hull) and then First <= Hull'Last
               and then From <= To and then To <= Hull'Length;
   --  The largest distance from the line through the corners From and
   --  To after First of the corners between them.

   function Deviation
     (Hull     : DA.Point_Array;
      First    : Positive;
      From, To : Natural) return Long_Float
   is
      A      : constant Corner := At_Place (Hull, First, From);
      B      : constant Corner := At_Place (Hull, First, To);
      Length : constant Long_Float := Distance (A, B);
      Worst  : Long_Float := 0.0;
   begin
      if Length < 1.0 then
         return Limit;
      end if;
      for T in From + 1 .. To - 1 loop
         Worst := Long_Float'Max
           (Worst, abs Off_Line (A, B, At_Place (Hull, First, T)) / Length);
      end loop;
      return Worst;
   end Deviation;

   procedure Meet
     (P1, P2 : Corner;
      P3, P4 : Corner;
      Where  : out Corner;
      OK     : out Boolean);
   --  Where the line through P1 and P2 meets the line through P3 and P4.

   procedure Meet
     (P1, P2 : Corner;
      P3, P4 : Corner;
      Where  : out Corner;
      OK     : out Boolean)
   is
      Den : constant Long_Float :=
        (P1.X - P2.X) * (P3.Y - P4.Y) - (P1.Y - P2.Y) * (P3.X - P4.X);
      T   : Long_Float;
      X   : Long_Float;
      Y   : Long_Float;
   begin
      Where := (0.0, 0.0);
      OK := False;
      if abs Den < 1.0E-6 then
         return;
      end if;
      T := ((P1.X - P3.X) * (P3.Y - P4.Y) - (P1.Y - P3.Y) * (P3.X - P4.X))
           / Den;
      if abs T > 4.0 then
         return;
      end if;
      X := P1.X + T * (P2.X - P1.X);
      Y := P1.Y + T * (P2.Y - P1.Y);
      if abs X < Limit and then abs Y < Limit then
         Where := (X, Y);
         OK := True;
      end if;
   end Meet;

   procedure Find_Four
     (Hull  : DA.Point_Array;
      Four  : out Positive;
      Three : out Positive;
      Two   : out Positive;
      One   : out Positive;
      Found : out Boolean)
   with Pre => Valid_Hull (Hull);
   --  Four corners of the hull, clockwise: One and Three are the two
   --  farthest from each other, Two and Four the farthest from their
   --  line on either side.

   procedure Find_Four
     (Hull  : DA.Point_Array;
      Four  : out Positive;
      Three : out Positive;
      Two   : out Positive;
      One   : out Positive;
      Found : out Boolean)
   is
      Best : Long_Float := -1.0;
      D    : Long_Float;
      A, B : Corner;
   begin
      One := 1;
      Two := 1;
      Three := 1;
      Four := 1;
      for I in 1 .. Hull'Last - 1 loop
         for J in I + 1 .. Hull'Last loop
            D := Distance (To_Corner (Hull (I)), To_Corner (Hull (J)));
            if D > Best then
               Best := D;
               One := I;
               Three := J;
            end if;
         end loop;
      end loop;
      A := To_Corner (Hull (One));
      B := To_Corner (Hull (Three));

      Best := 0.0;
      for K in One + 1 .. Three - 1 loop
         D := abs Off_Line (A, B, To_Corner (Hull (K)));
         if D > Best then
            Best := D;
            Two := K;
         end if;
      end loop;
      Found := Best > 0.0;

      Best := 0.0;
      for K in Hull'Range loop
         if K < One or else K > Three then
            D := abs Off_Line (A, B, To_Corner (Hull (K)));
            if D > Best then
               Best := D;
               Four := K;
            end if;
         end if;
      end loop;
      Found := Found and then Best > 0.0;
   end Find_Four;

   type Anchoring is record
      Anchored     : Boolean := False;
      Has_Arm      : Boolean := False;
      End_1, End_2 : Corner := (0.0, 0.0);
      Arm_1, Arm_2 : Corner := (0.0, 0.0);
   end record;
   --  What the line of an alternating side has to pass: the end of an
   --  arm of the L. End_1 is the corner of the hull there and End_2 the
   --  corner of the hull next to it along the alternating side: where an
   --  outline turns, the pixels cut its tip off, and the hull has a
   --  corner on either side of the true one. The line has to pass
   --  within Loose of End_1, or (Has_Arm: the line through Arm_1 and
   --  Arm_2 is that of the arm) to meet the line of the arm within Loose
   --  of End_2.

   function Passes
     (PI, PK : Corner;
      Anchor : Anchoring) return Boolean;
   --  The line through PI and PK passes what Anchor asks for.

   function Passes
     (PI, PK : Corner;
      Anchor : Anchoring) return Boolean
   is
      Where : Corner;
      Met   : Boolean;
   begin
      if not Anchor.Anchored
        or else abs Off_Line (PI, PK, Anchor.End_1)
                <= Loose * Distance (PI, PK)
      then
         return True;
      elsif not Anchor.Has_Arm then
         return False;
      end if;
      Meet (Anchor.Arm_1, Anchor.Arm_2, PI, PK, Where, Met);
      return Met and then Distance (Where, Anchor.End_2) <= Loose;
   end Passes;

   procedure Longest_Run
     (Hull     : DA.Point_Array;
      First    : Positive;
      Last     : Natural;
      Anchor   : Anchoring;
      From, To : out Natural;
      Length   : out Long_Float)
   with Pre => Valid_Hull (Hull) and then First <= Hull'Last
               and then Last <= Hull'Length;
   --  The longest straight part of the hull between the corner First and
   --  the corner Last corners after it: from the corner From to the
   --  corner To after First, Length pixels long (0.0: there is none).
   --  Only the parts whose line passes Anchor are looked at.

   procedure Longest_Run
     (Hull     : DA.Point_Array;
      First    : Positive;
      Last     : Natural;
      Anchor   : Anchoring;
      From, To : out Natural;
      Length   : out Long_Float)
   is
      PI : Corner;
      PK : Corner;
      D  : Long_Float;
   begin
      From := 0;
      To := 0;
      Length := 0.0;
      for I in 0 .. Last loop
         PI := At_Place (Hull, First, I);
         for K in I + 1 .. Last loop
            PK := At_Place (Hull, First, K);
            D := Distance (PI, PK);
            if D > Length and then D >= 1.0
              and then Passes (PI, PK, Anchor)
              and then Deviation (Hull, First, I, K) <= Straight
            then
               From := I;
               To := K;
               Length := D;
            end if;
         end loop;
      end loop;
   end Longest_Run;

   procedure Analyse
     (Map    : DA.Mark_Map;
      Hull   : DA.Point_Array;
      Symbol : out Outline;
      Found  : out Boolean;
      Share  : out Long_Float)
   with Pre => DA.Valid_Map (Map) and then Hull'First = 1;
   --  The corners of the symbol whose hull is Hull. Found: the hull has
   --  the L. Share: the part of the two alternating sides, at least,
   --  along which the hull is straight (0.0 .. 1.0). A corner is where
   --  the straight parts of its two sides meet when these are Trusted or
   --  more of the sides; else a corner of the L is the corner of the
   --  hull, and the upper right corner the fourth corner of the
   --  parallelogram of the L.

   procedure Analyse
     (Map    : DA.Mark_Map;
      Hull   : DA.Point_Array;
      Symbol : out Outline;
      Found  : out Boolean;
      Share  : out Long_Float)
   is
      type Side is mod 4;
      type Line is record
         P1, P2 : Corner := (0.0, 0.0);
         Good   : Boolean := False;
      end record;
      Q      : array (Side) of Positive := [others => 1];
      Solid  : array (Side) of Solidity;
      Long   : array (Side) of Long_Float;
      Lines  : array (Side) of Line;
      L      : Side := 0;
      Have_L : Boolean := False;
      Best   : Long_Float := 0.0;
      Short  : Long_Float;
      Deep   : Solidity;
      Least  : Solidity := Solidity'Last;
      OK     : Boolean;
      A, B   : Corner;
      C, D   : Corner;
      LA, LB : Long_Float;
      HC, HD : Long_Float;

      procedure Fit (S : Side; Alternating : Boolean);
      --  The line of the side S, good when the hull is straight along
      --  enough of the side. Alternating: the side is not an arm of
      --  the L, which is known. The hull of such a side may cut through
      --  the symbol, from one end of the L to dark modules that touch no
      --  others; its line is one that passes the end of the L and has
      --  nothing dark outside.

      procedure Fit (S : Side; Alternating : Boolean) is
         M        : constant Natural := (Q (S + 1) - Q (S)) mod Hull'Length;
         Chord    : constant Long_Float :=
           Distance (To_Corner (Hull (Q (S))), To_Corner (Hull (Q (S + 1))));
         From, To : Natural;
         Length   : Long_Float;
         Anchor   : Anchoring;
         P1, P2   : Corner;
         Dark     : Natural := 0;
         Total    : Natural := 0;
         Changes  : Natural;
      begin
         Lines (S).Good := False;
         if not Alternating then
            null;
         elsif S = L + 1 then
            --  From the end of the arm that is the side L.
            Anchor := (Anchored => True,
                       Has_Arm  => Lines (L).Good,
                       End_1    => To_Corner (Hull (Q (S))),
                       End_2    => At_Place (Hull, Q (S), Natural'Min (1, M)),
                       Arm_1    => Lines (L).P1,
                       Arm_2    => Lines (L).P2);
         else
            --  To the end of the arm that is the side L - 1.
            Anchor := (Anchored => True,
                       Has_Arm  => Lines (L - 1).Good,
                       End_1    => To_Corner (Hull (Q (S + 1))),
                       End_2    =>
                         At_Place (Hull, Q (S), M - Natural'Min (1, M)),
                       Arm_1    => Lines (L - 1).P1,
                       Arm_2    => Lines (L - 1).P2);
         end if;
         Longest_Run (Hull, Q (S), M, Anchor, From, To, Length);
         if Length >= Min_Side and then Length >= Trusted * Chord then
            P1 := At_Place (Hull, Q (S), From);
            P2 := At_Place (Hull, Q (S), To);
            if Alternating then
               Scan_Side (Map, P1, P2, -Inset, 0.0, 1.0, Dark, Total,
                          Changes);
            end if;
            if Long_Float (Dark)
               <= (1.0 - Solid_Share) * Long_Float (Total)
            then
               Lines (S) := (P1, P2, True);
            end if;
         end if;
      end Fit;

      function Corner_Of (S : Side) return Corner;
      --  The corner between the sides S - 1 and S: where their lines
      --  meet, if that is near the corner of the hull, or nearer still
      --  to the corner of the hull before or after it (the pixels cut
      --  the tip of a corner off).

      function Corner_Of (S : Side) return Corner is
         P      : constant Corner := To_Corner (Hull (Q (S)));
         Before : constant Corner := At_Place (Hull, Q (S), Hull'Length - 1);
         After  : constant Corner := At_Place (Hull, Q (S), 1);
         Where  : Corner;
         Met    : Boolean;
      begin
         if Lines (S - 1).Good and then Lines (S).Good then
            Meet (Lines (S - 1).P1, Lines (S - 1).P2,
                  Lines (S).P1, Lines (S).P2, Where, Met);
            if Met
              and then (Distance (P, Where) <= Near
                        or else Distance (Before, Where) <= Loose
                        or else Distance (After, Where) <= Loose)
            then
               return Where;
            end if;
         end if;
         return P;
      end Corner_Of;
   begin
      Symbol := (others => <>);
      Found := False;
      Share := 0.0;
      if not Valid_Hull (Hull) then
         return;
      end if;
      Find_Four (Hull, Q (3), Q (2), Q (1), Q (0), OK);
      if not OK then
         return;
      end if;

      --  The straight part of every side, and how solid the side is
      --  along it: the corners of the hull are not those of the symbol
      --  where a corner of the symbol is light, and the line from one to
      --  the next may run through the modules next to the side.
      for S in Side loop
         Fit (S, Alternating => False);
      end loop;

      --  The L: two solid sides that meet. A dark area with little more
      --  than the L has a hull of nearly three corners, and its fourth
      --  side, at the end of an arm of the L, may be solid as well; and
      --  so may an alternating side be where it is looked at as deep as
      --  the modules next to it. Of several pairs it is the one that is
      --  solid nearest to the hull, and of these the one whose shorter
      --  side is the longest.
      for S in Side loop
         if Lines (S).Good then
            Solid (S) := Solid_At (Map, Lines (S).P1, Lines (S).P2);
         else
            Solid (S) := Solid_At (Map, To_Corner (Hull (Q (S))),
                                   To_Corner (Hull (Q (S + 1))));
         end if;
         Long (S) := Distance (To_Corner (Hull (Q (S))),
                               To_Corner (Hull (Q (S + 1))));
      end loop;
      for S in Side loop
         if Solid (S - 1) > 0 and then Solid (S) > 0 then
            Deep := Solidity'Max (Solid (S - 1), Solid (S));
            Short := Long_Float'Min (Long (S - 1), Long (S));
            if Deep < Least or else (Deep = Least and then Short > Best) then
               Least := Deep;
               Best := Short;
               L := S;
               Have_L := True;
            end if;
         end if;
      end loop;
      if not Have_L then
         return;
      end if;
      --  The lines of the other two sides have to pass the ends of the
      --  arms.
      Fit (L + 1, Alternating => True);
      Fit (L + 2, Alternating => True);
      C := Corner_Of (L);
      A := Corner_Of (L + 1);
      B := Corner_Of (L + 3);
      if Distance (C, A) < Min_Side or else Distance (C, B) < Min_Side then
         return;
      end if;
      Symbol := (Upper_Left  => A,
                 Upper_Right => Fourth (A, B, C),
                 Lower_Right => B,
                 Lower_Left  => C);
      Found := True;

      --  The upper right corner: where the two alternating sides meet.
      if not (Lines (L + 1).Good and then Lines (L + 2).Good) then
         return;
      end if;
      Meet (Lines (L + 1).P1, Lines (L + 1).P2,
            Lines (L + 2).P1, Lines (L + 2).P2, D, OK);
      if not OK then
         return;
      end if;
      LA := Distance (A, D);
      LB := Distance (D, B);
      if LA < Min_Side or else LB < Min_Side then
         return;
      end if;

      --  Not where a symbol cannot have it: the two lines may be those
      --  of a hull that cuts through the symbol from one end of the L to
      --  the other.
      HC := Off_Line (A, B, C);
      HD := Off_Line (A, B, D);
      if (HC > 0.0) = (HD > 0.0) or else abs HD < Seen * abs HC
        or else Seen * abs HD > abs HC
      then
         return;
      end if;
      Share := Long_Float'Min
        (1.0,
         Long_Float'Min
           (Distance (Lines (L + 1).P1, Lines (L + 1).P2) / LA,
            Distance (Lines (L + 2).P1, Lines (L + 2).P2) / LB));
      if Share >= Trusted then
         Symbol.Upper_Right := D;
      else
         Share := 0.0;
      end if;
   end Analyse;

   procedure Locate
     (Map    : DA.Mark_Map;
      Hull   : DA.Point_Array;
      Symbol : out Outline;
      Found  : out Boolean)
   is
      Share : Long_Float;
   begin
      Analyse (Map, Hull, Symbol, Found, Share);
   end Locate;

   ---------------------------------------------------------------------
   --  All the dark pixels of a symbol
   ---------------------------------------------------------------------

   function Pushed
     (P, Before, After : Corner;
      Margin           : Long_Float) return Corner;
   --  The corner P of an outline, between the corners Before and After,
   --  moved outwards by Margin along both of its sides.

   function Pushed
     (P, Before, After : Corner;
      Margin           : Long_Float) return Corner
   is
      L1 : constant Long_Float := Distance (Before, P);
      L2 : constant Long_Float := Distance (After, P);
      X  : Long_Float := P.X;
      Y  : Long_Float := P.Y;
   begin
      if L1 >= 1.0 then
         X := X + Margin * (P.X - Before.X) / L1;
         Y := Y + Margin * (P.Y - Before.Y) / L1;
      end if;
      if L2 >= 1.0 then
         X := X + Margin * (P.X - After.X) / L2;
         Y := Y + Margin * (P.Y - After.Y) / L2;
      end if;
      if abs X < Limit and then abs Y < Limit then
         return (X, Y);
      else
         return P;
      end if;
   end Pushed;

   procedure Extents
     (Map        : DA.Mark_Map;
      Symbol     : Outline;
      Margin     : Long_Float;
      Lefts      : in out DA.Extent_Array;
      Rights     : in out DA.Extent_Array;
      Y_Lo, Y_Hi : out Natural;
      Any        : out Boolean)
   with Pre => DA.Valid_Map (Map)
               and then DA.Extents_Fit (Lefts, Map)
               and then DA.Extents_Fit (Rights, Map);
   --  The leftmost and the rightmost dark pixel of every row within the
   --  outline, grown by Margin. Any: there is one, in the rows
   --  Y_Lo .. Y_Hi.

   procedure Extents
     (Map        : DA.Mark_Map;
      Symbol     : Outline;
      Margin     : Long_Float;
      Lefts      : in out DA.Extent_Array;
      Rights     : in out DA.Extent_Array;
      Y_Lo, Y_Hi : out Natural;
      Any        : out Boolean)
   is
      type Four is array (0 .. 3) of Corner;
      P : constant Four :=
        [Pushed (Symbol.Upper_Left, Symbol.Lower_Left, Symbol.Upper_Right,
                 Margin),
         Pushed (Symbol.Upper_Right, Symbol.Upper_Left, Symbol.Lower_Right,
                 Margin),
         Pushed (Symbol.Lower_Right, Symbol.Upper_Right, Symbol.Lower_Left,
                 Margin),
         Pushed (Symbol.Lower_Left, Symbol.Lower_Right, Symbol.Upper_Left,
                 Margin)];
      Top    : Long_Float := P (0).Y;
      Bottom : Long_Float := P (0).Y;
      First  : Natural;
      Last   : Natural;
      YC     : Long_Float;
      X      : Long_Float;
      XL, XR : Long_Float;
      Have   : Boolean;
      IL, IR : Natural;
   begin
      Y_Lo := 0;
      Y_Hi := 0;
      Any := False;
      for K in 1 .. 3 loop
         Top := Long_Float'Min (Top, P (K).Y);
         Bottom := Long_Float'Max (Bottom, P (K).Y);
      end loop;
      if Bottom < 0.0 or else Top > Long_Float (Map'Last (1)) then
         return;
      end if;
      First := (if Top <= 0.0 then 0 else Natural (Long_Float'Floor (Top)));
      Last := (if Bottom >= Long_Float (Map'Last (1)) then Map'Last (1)
               else Natural (Long_Float'Floor (Bottom)));

      for Y in First .. Last loop
         --  The part of the row within the outline.
         YC := Long_Float (Y) + 0.5;
         Have := False;
         XL := 0.0;
         XR := 0.0;
         for K in 0 .. 3 loop
            declare
               A : constant Corner := P (K);
               B : constant Corner := P ((K + 1) mod 4);
            begin
               if (A.Y <= YC) /= (B.Y <= YC) then
                  X := A.X + (YC - A.Y) * (B.X - A.X) / (B.Y - A.Y);
                  if not Have then
                     XL := X;
                     XR := X;
                     Have := True;
                  else
                     XL := Long_Float'Min (XL, X);
                     XR := Long_Float'Max (XR, X);
                  end if;
               end if;
            end;
         end loop;
         if Have and then XR >= 0.0
           and then XL <= Long_Float (Map'Last (2))
         then
            IL := (if XL <= 0.0 then 0 else Natural (Long_Float'Floor (XL)));
            IR := (if XR >= Long_Float (Map'Last (2)) then Map'Last (2)
                   else Natural (Long_Float'Floor (XR)));
            for X in IL .. IR loop
               if Map (Y, X) /= DA.Light then
                  Lefts (Y) := X;
                  exit;
               end if;
            end loop;
            for X in reverse IL .. IR loop
               if Map (Y, X) /= DA.Light then
                  Rights (Y) := X;
                  exit;
               end if;
            end loop;
            if Rights (Y) /= DA.No_Right then
               if not Any then
                  Y_Lo := Y;
                  Any := True;
               end if;
               Y_Hi := Y;
            end if;
         end if;
      end loop;
   end Extents;

   function Moved (From, To : Outline) return Long_Float is
     (Distance (From.Upper_Left, To.Upper_Left)
      + Distance (From.Upper_Right, To.Upper_Right)
      + Distance (From.Lower_Right, To.Lower_Right)
      + Distance (From.Lower_Left, To.Lower_Left));

   procedure Refine
     (Map    : DA.Mark_Map;
      Lefts  : in out DA.Extent_Array;
      Rights : in out DA.Extent_Array;
      Points : in out DA.Point_Array;
      Symbol : in out Outline)
   is
      Widest : constant Long_Float :=
        Long_Float'Min
          (Distance (Symbol.Lower_Left, Symbol.Upper_Left),
           Distance (Symbol.Lower_Left, Symbol.Lower_Right)) / 8.0;
      Margin     : Long_Float := Narrow;
      Y_Lo, Y_Hi : Natural;
      Any        : Boolean;
      Count      : Natural;
      Now        : Outline := Symbol;
      Before     : Outline := Symbol;
      Next       : Outline;
      OK         : Boolean;
      Share      : Long_Float;
      Still      : Boolean;
      Have_Best  : Boolean := False;
   begin
      for Round in 1 .. Rounds loop
         Extents (Map, Now, Margin, Lefts, Rights, Y_Lo, Y_Hi, Any);
         exit when not Any;
         DA.Hull (Lefts, Rights, Y_Lo, Y_Hi, Points, Count);
         DA.Clear (Lefts, Rights, Y_Lo, Y_Hi);
         exit when Count < 4;
         Analyse (Map, Points (1 .. Count), Next, OK, Share);
         exit when not OK;

         --  Settled, also when the outline comes back to the one of two
         --  rounds before.
         Still := Moved (Now, Next) <= Settled
           or else (Round > 1 and then Moved (Before, Next) <= Settled);
         Before := Now;
         Now := Next;
         if Still and then Share >= Covered then
            if Margin <= Narrow then
               Symbol := Now;
               return;
            end if;
            Margin := Narrow;
         elsif Still then
            if not Have_Best then
               Symbol := Now;
               Have_Best := True;
            end if;
            Margin := 2.0 * Margin;
            exit when Margin > Widest;
         end if;
      end loop;
   end Refine;

   ---------------------------------------------------------------------
   --  The modules
   ---------------------------------------------------------------------

   procedure Count_Side
     (Map   : DA.Mark_Map;
      A, B  : Corner;
      Count : out Natural)
   with Pre => DA.Valid_Map (Map);
   --  The modules along the alternating side from A to B.

   procedure Count_Side
     (Map   : DA.Mark_Map;
      A, B  : Corner;
      Count : out Natural)
   is
      Length               : constant Long_Float := Distance (A, B);
      Dark, Total, Changes : Natural;
      Module               : Long_Float;
   begin
      Scan_Side (Map, A, B, Inset, 0.0, 1.0, Dark, Total, Changes);
      Count := Changes + 1;
      if Total = 0 then
         Count := 0;
         return;
      end if;
      Module := Length / Long_Float (Count);
      if Module > 2.0 * Inset then
         Scan_Side (Map, A, B, 0.5 * Module, 0.0, 1.0, Dark, Total,
                    Changes);
         Count := Changes + 1;
      end if;
   end Count_Side;

   procedure Count_Modules
     (Map           : DA.Mark_Map;
      Symbol        : Outline;
      Rows, Columns : out Natural) is
   begin
      --  Count_Side looks to the right of its line: the sides are gone
      --  along clockwise, whichever way the corners go around (the other
      --  way for a symbol that is seen from behind).
      if Off_Line (Symbol.Upper_Left, Symbol.Upper_Right, Symbol.Lower_Left)
         >= 0.0
      then
         Count_Side (Map, Symbol.Upper_Left, Symbol.Upper_Right, Columns);
         Count_Side (Map, Symbol.Upper_Right, Symbol.Lower_Right, Rows);
      else
         Count_Side (Map, Symbol.Upper_Right, Symbol.Upper_Left, Columns);
         Count_Side (Map, Symbol.Lower_Right, Symbol.Upper_Right, Rows);
      end if;
   end Count_Modules;

   procedure Sample
     (Map           : DA.Mark_Map;
      Symbol        : Outline;
      Rows, Columns : Positive;
      Grid          : out Module_Grid)
   is
      X0 : constant Long_Float := Symbol.Upper_Left.X;
      Y0 : constant Long_Float := Symbol.Upper_Left.Y;
      X1 : constant Long_Float := Symbol.Upper_Right.X;
      Y1 : constant Long_Float := Symbol.Upper_Right.Y;
      X2 : constant Long_Float := Symbol.Lower_Right.X;
      Y2 : constant Long_Float := Symbol.Lower_Right.Y;
      X3 : constant Long_Float := Symbol.Lower_Left.X;
      Y3 : constant Long_Float := Symbol.Lower_Left.Y;

      DX1 : constant Long_Float := X1 - X2;
      DX2 : constant Long_Float := X3 - X2;
      DX3 : constant Long_Float := X0 - X1 + X2 - X3;
      DY1 : constant Long_Float := Y1 - Y2;
      DY2 : constant Long_Float := Y3 - Y2;
      DY3 : constant Long_Float := Y0 - Y1 + Y2 - Y3;
      Den : constant Long_Float := DX1 * DY2 - DX2 * DY1;

      G, H, A, B, D, E, U, V, W : Long_Float;
   begin
      Grid := [others => [others => False]];
      if abs Den < 1.0E-9 then
         return;
      end if;
      --  The unit square to the four corners: (0, 0) the upper left,
      --  (1, 0) the upper right, (1, 1) the lower right one.
      G := (DX3 * DY2 - DX2 * DY3) / Den;
      H := (DX1 * DY3 - DX3 * DY1) / Den;
      A := X1 - X0 + G * X1;
      B := X3 - X0 + H * X3;
      D := Y1 - Y0 + G * Y1;
      E := Y3 - Y0 + H * Y3;
      for R in 0 .. Rows - 1 loop
         V := (Long_Float (R) + 0.5) / Long_Float (Rows);
         for C in 0 .. Columns - 1 loop
            U := (Long_Float (C) + 0.5) / Long_Float (Columns);
            W := G * U + H * V + 1.0;
            if W > 1.0E-6 then
               Grid (Module_Index (R), Module_Index (C)) :=
                 Dark_At
                   (Map,
                    (A * U + B * V + X0) / W,
                    (D * U + E * V + Y0) / W);
            end if;
         end loop;
      end loop;
   end Sample;

   function Middle (Symbol : Outline) return Corner is
      Where : Corner;
      OK    : Boolean;
   begin
      Meet (Symbol.Upper_Left, Symbol.Lower_Right, Symbol.Upper_Right,
            Symbol.Lower_Left, Where, OK);
      if not OK then
         Where :=
           (X => (Symbol.Upper_Left.X + Symbol.Upper_Right.X
                  + Symbol.Lower_Right.X + Symbol.Lower_Left.X) / 4.0,
            Y => (Symbol.Upper_Left.Y + Symbol.Upper_Right.Y
                  + Symbol.Lower_Right.Y + Symbol.Lower_Left.Y) / 4.0);
      end if;
      return Where;
   end Middle;

end AMV.Kernels.Code_Reader.Data_Matrix.Finder;
