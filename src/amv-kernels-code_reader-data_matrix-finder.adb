pragma Validity_Checks ("F");
with AMV.Kernels.Numerics;

package body AMV.Kernels.Code_Reader.Data_Matrix.Finder
  with SPARK_Mode
is

   package N renames AMV.Kernels.Numerics;

   use type DA.Mark;

   --  The points, the pixels and the mapping of Views, by the names
   --  that this body uses.

   Span : constant := VW.Span;
   Far  : constant := VW.Far;
   Wide : constant := VW.Wide;
   --  The difference of two coordinates, the distance of two points
   --  and Off_Line, at most.

   subtype Length_Value is VW.Length_Value;
   subtype Cross is VW.Cross;
   subtype Offset is VW.Offset;
   subtype Share_Value is Long_Float range 0.0 .. 1.0;

   function Distance (A, B : Corner) return Length_Value
     renames VW.Distance;

   function Off_Line (A, B, P : Corner) return Cross
     renames VW.Off_Line;
   --  The distance of P from the line from A to B, times the length of
   --  the line; positive on the right of the line as the image is seen.

   function Quotient
     (X, Y  : Long_Float;
      Bound : Long_Float) return Long_Float
     renames VW.Quotient;
   --  X / Y where that is within Bound of 0, else Bound with the sign
   --  of X / Y.

   function Floor_Index (X : Long_Float; High : Natural) return Natural
     renames VW.Floor_Index;
   --  The whole part of X, and High where that is more.

   function Dark_At (Map : DA.Mark_Map; X, Y : Long_Float) return Boolean
     renames VW.Dark_At;
   --  The pixel that holds the point is dark (outside the map: light).

   Most_Steps : constant := 2 ** 29;
   --  The points that Scan_Side looks at along a side, less one, at
   --  most: two for every pixel of a side of Limit pixels.

   Most_Corners : constant := 4 * DA.Max_Side;
   --  The corners of a hull, at most (DA.Hull gives two for every row
   --  of a map and two more).

   Farthest : constant := 4.0;
   --  Two lines meet no farther from the first point of the first line
   --  than this, in lengths from that point to the second one.

   Inset : constant := 1.5;
   --  How far inside a side its pixels are looked at, in pixels.

   Min_Side : constant := 10.0;
   --  The shortest side of a symbol, in pixels.

   Solid_Share : constant := 0.85;
   --  The share of dark pixels along a solid side, at least.

   Num_Depths : constant := 3;

   Depths : constant array (1 .. Num_Depths) of Offset :=
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

   Widest_Cut : constant := 8.0;
   --  Where an outline turns, the pixels cut its tip off, and a blurred
   --  image takes more of it: how far apart the two corners that the
   --  hull has in place of the tip may be, in pixels.

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
     (X => Long_Float (P.X), Y => Long_Float (P.Y));

   function Fourth (A, B, C : Corner) return Corner is
     (if abs (A.X + B.X - C.X) < Limit and then abs (A.Y + B.Y - C.Y) < Limit
      then (A.X + B.X - C.X, A.Y + B.Y - C.Y) else C);
   --  The corner opposite C of the parallelogram with the sides from C
   --  to A and from C to B.

   ---------------------------------------------------------------------
   --  A side
   ---------------------------------------------------------------------

   function Half_Of (I : Natural) return Length_Value is
     (0.5 * Long_Float (I))
   with Pre => I <= Most_Steps;
   --  The way along a side after I steps of half a pixel.

   procedure Scan_Side
     (Map     : DA.Mark_Map;
      A, B    : Corner;
      Depth   : Offset;
      Lo, Hi  : Share_Value;
      Dark    : out Natural;
      Total   : out Natural;
      Changes : out Natural)
   with Pre  => DA.Valid_Map (Map) and then Lo <= Hi,
        Post => Total <= Most_Steps + 1 and then Dark <= Total
                and then Changes <= Total;
   --  Looks at the pixels along the line from A to B, Depth pixels to
   --  the right of it (inside a symbol that is gone around clockwise),
   --  every half pixel between the shares Lo and Hi of the way. Total:
   --  the points looked at; Dark: those that are dark; Changes: the
   --  changes between dark and light that last for two points.

   procedure Scan_Side
     (Map     : DA.Mark_Map;
      A, B    : Corner;
      Depth   : Offset;
      Lo, Hi  : Share_Value;
      Dark    : out Natural;
      Total   : out Natural;
      Changes : out Natural)
   is
      Length : constant Length_Value := Distance (A, B);
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
      UX := Quotient (B.X - A.X, Length, 1.0);
      UY := Quotient (B.Y - A.Y, Length, 1.0);
      X0 := A.X - N.Times_Unit (Depth, UY);
      Y0 := A.Y + N.Times_Unit (Depth, UX);
      Steps :=
        Floor_Index (N.Times_Unit (Length, Hi - Lo) * 2.0, Most_Steps);
      for I in 0 .. Steps loop
         pragma Loop_Invariant
           (Total = I and then Dark <= I and then Changes <= I);
         T := N.Times_Unit (Length, Lo) + Half_Of (I);
         Now := Dark_At
           (Map, X0 + N.Times_Unit (T, UX), Y0 + N.Times_Unit (T, UY));
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
      Dark, Total    : Natural;
      Unused_Changes : Natural;
   begin
      for K in Depths'Range loop
         Scan_Side
           (Map, A, B, Depths (K), 0.05, 0.95, Dark, Total, Unused_Changes);
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
      and then Hull'Last <= Most_Corners);

   function Place
     (Hull  : DA.Point_Array;
      First : Positive;
      T     : Natural) return Positive
   is ((First - 1 + T) mod Hull'Length + 1)
   with Pre  => Valid_Hull (Hull) and then First <= Hull'Last
                and then T <= Hull'Length,
        Post => Place'Result <= Hull'Last;
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
   with Pre  => Valid_Hull (Hull) and then First <= Hull'Last
                and then From <= To and then To <= Hull'Length,
        Post => Deviation'Result in 0.0 .. Wide;
   --  The largest distance from the line through the corners From and
   --  To after First of the corners between them.

   function Deviation
     (Hull     : DA.Point_Array;
      First    : Positive;
      From, To : Natural) return Long_Float
   is
      A      : constant Corner := At_Place (Hull, First, From);
      B      : constant Corner := At_Place (Hull, First, To);
      Length : constant Length_Value := Distance (A, B);
      Worst  : Long_Float := 0.0;
   begin
      if Length < 1.0 then
         return Limit;
      end if;
      for T in From + 1 .. To - 1 loop
         pragma Loop_Invariant (Worst in 0.0 .. Wide);
         Worst := Long_Float'Max
           (Worst,
            Quotient
              (abs Off_Line (A, B, At_Place (Hull, First, T)), Length,
               Wide));
      end loop;
      return Worst;
   end Deviation;

   procedure Meet
     (P1, P2 : Corner;
      P3, P4 : Corner;
      Where  : out Corner;
      OK     : out Boolean)
   with Global => null, Post => True;
   --  Where the line through P1 and P2 meets the line through P3 and P4.

   procedure Meet
     (P1, P2 : Corner;
      P3, P4 : Corner;
      Where  : out Corner;
      OK     : out Boolean)
   is
      Den : constant Long_Float :=
        N.Mul_Within (P1.X - P2.X, P3.Y - P4.Y, Span, Span)
        - N.Mul_Within (P1.Y - P2.Y, P3.X - P4.X, Span, Span);
      Num : Long_Float;
      T   : Long_Float;
      X   : Long_Float;
      Y   : Long_Float;
   begin
      Where := (0.0, 0.0);
      OK := False;
      if abs Den < 1.0E-6 then
         return;
      end if;
      Num := N.Mul_Within (P1.X - P3.X, P3.Y - P4.Y, Span, Span)
        - N.Mul_Within (P1.Y - P3.Y, P3.X - P4.X, Span, Span);
      T := Quotient (Num, Den, 2.0 * Farthest);
      if abs T > Farthest then
         return;
      end if;
      X := P1.X + N.Times_Small (P2.X - P1.X, T);
      Y := P1.Y + N.Times_Small (P2.Y - P1.Y, T);
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
   with Pre  => Valid_Hull (Hull),
        Post => Four <= Hull'Last and then Three <= Hull'Last
                and then Two <= Hull'Last and then One <= Hull'Last;
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
         pragma Loop_Invariant
           (One <= Hull'Last and then Three <= Hull'Last);
         for J in I + 1 .. Hull'Last loop
            pragma Loop_Invariant
              (One <= Hull'Last and then Three <= Hull'Last);
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
         pragma Loop_Invariant (Two <= Hull'Last);
         D := abs Off_Line (A, B, To_Corner (Hull (K)));
         if D > Best then
            Best := D;
            Two := K;
         end if;
      end loop;
      Found := Best > 0.0;

      Best := 0.0;
      for K in Hull'Range loop
         pragma Loop_Invariant (Four <= Hull'Last);
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
   --  of End_2, or where the tip is that End_1 and End_2 are left of: no
   --  farther from either than they are apart (Widest_Cut at most) and
   --  Loose.

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
      Reach : Long_Float;
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
      if not Met then
         return False;
      end if;
      Reach :=
        Loose + Long_Float'Min (Distance (Anchor.End_1, Anchor.End_2),
                                Widest_Cut);
      return Distance (Where, Anchor.End_2) <= Loose
        or else (Distance (Where, Anchor.End_1) <= Reach
                 and then Distance (Where, Anchor.End_2) <= Reach);
   end Passes;

   procedure Longest_Run
     (Hull     : DA.Point_Array;
      First    : Positive;
      Last     : Natural;
      Anchor   : Anchoring;
      From, To : out Natural;
      Length   : out Length_Value)
   with Pre  => Valid_Hull (Hull) and then First <= Hull'Last
                and then Last <= Hull'Length,
        Post => From <= To and then To <= Last;
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
      Length   : out Length_Value)
   is
      PI : Corner;
      PK : Corner;
      D  : Length_Value;
   begin
      From := 0;
      To := 0;
      Length := 0.0;
      for I in 0 .. Last loop
         pragma Loop_Invariant (From <= To and then To <= Last);
         PI := At_Place (Hull, First, I);
         for K in I + 1 .. Last loop
            pragma Loop_Invariant (From <= To and then To <= Last);
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

   type Side is mod 4;
   --  The sides of the hull between the four corners, clockwise.

   type Line is record
      P1, P2 : Corner := (0.0, 0.0);
      I1, I2 : Positive := 1;
      Good   : Boolean := False;
   end record;
   --  The straight part of a side: from the corner I1 of the hull,
   --  at P1, to the corner I2, at P2.

   type Place_Array is array (Side) of Positive;
   type Line_Array is array (Side) of Line;

   function Places_Fit
     (Hull : DA.Point_Array;
      Q    : Place_Array) return Boolean
   is (for all S in Side => Q (S) <= Hull'Last);

   function Lines_Fit
     (Hull  : DA.Point_Array;
      Lines : Line_Array) return Boolean
   is
     (for all S in Side =>
        Lines (S).I1 <= Hull'Last and then Lines (S).I2 <= Hull'Last);

   procedure Fit
     (Map         : DA.Mark_Map;
      Hull        : DA.Point_Array;
      Q           : Place_Array;
      L           : Side;
      S           : Side;
      Alternating : Boolean;
      Lines       : in out Line_Array)
   with Pre  => DA.Valid_Map (Map) and then Valid_Hull (Hull)
                and then Places_Fit (Hull, Q)
                and then Lines_Fit (Hull, Lines),
        Post => Lines_Fit (Hull, Lines);
   --  The line of the side S, from the corner Q (S) of the hull to the
   --  next, good when the hull is straight along enough of the side.
   --  Alternating: the side is not an arm of the L, which is known (the
   --  sides L - 1 and L). The hull of such a side may cut through the
   --  symbol, from one end of the L to dark modules that touch no
   --  others; its line is one that passes the end of the L and has
   --  nothing dark outside.

   procedure Fit
     (Map         : DA.Mark_Map;
      Hull        : DA.Point_Array;
      Q           : Place_Array;
      L           : Side;
      S           : Side;
      Alternating : Boolean;
      Lines       : in out Line_Array)
   is
      M        : constant Natural := (Q (S + 1) - Q (S)) mod Hull'Length;
      Chord    : constant Length_Value :=
        Distance (To_Corner (Hull (Q (S))), To_Corner (Hull (Q (S + 1))));
      From, To : Natural;
      Length   : Length_Value;
      Anchor   : Anchoring;
      P1, P2   : Corner;
      Dark     : Natural := 0;
      Total    : Natural := 0;
      Tip      : Natural := Natural'Min (1, M);

      Unused_Changes : Natural;
   begin
      Lines (S).Good := False;
      if Alternating and then S = L + 1 then
         --  From the end of the arm that is the side L.
         while Tip < M
           and then Distance (To_Corner (Hull (Q (S))),
                              At_Place (Hull, Q (S), Tip + 1))
                    <= Widest_Cut
         loop
            pragma Loop_Invariant (Tip < M);
            Tip := Tip + 1;
         end loop;
         Anchor := (Anchored => True,
                    Has_Arm  => Lines (L).Good,
                    End_1    => To_Corner (Hull (Q (S))),
                    End_2    => At_Place (Hull, Q (S), Tip),
                    Arm_1    => Lines (L).P1,
                    Arm_2    => Lines (L).P2);
      elsif Alternating then
         --  To the end of the arm that is the side L - 1.
         while Tip < M
           and then Distance (To_Corner (Hull (Q (S + 1))),
                              At_Place (Hull, Q (S), M - Tip - 1))
                    <= Widest_Cut
         loop
            pragma Loop_Invariant (Tip < M);
            Tip := Tip + 1;
         end loop;
         Anchor := (Anchored => True,
                    Has_Arm  => Lines (L - 1).Good,
                    End_1    => To_Corner (Hull (Q (S + 1))),
                    End_2    => At_Place (Hull, Q (S), M - Tip),
                    Arm_1    => Lines (L - 1).P1,
                    Arm_2    => Lines (L - 1).P2);
      end if;
      Longest_Run (Hull, Q (S), M, Anchor, From, To, Length);
      if Length >= Min_Side and then Length >= Trusted * Chord then
         P1 := At_Place (Hull, Q (S), From);
         P2 := At_Place (Hull, Q (S), To);
         if Alternating then
            Scan_Side (Map, P1, P2, -Inset, 0.0, 1.0, Dark, Total,
                       Unused_Changes);
         end if;
         if Long_Float (Dark)
            <= (1.0 - Solid_Share) * Long_Float (Total)
         then
            Lines (S) := (P1, P2, Place (Hull, Q (S), From),
                          Place (Hull, Q (S), To), True);
         end if;
      end if;
   end Fit;

   function Corner_Of
     (Hull  : DA.Point_Array;
      Q     : Place_Array;
      Lines : Line_Array;
      S     : Side) return Corner
   with Pre => Valid_Hull (Hull) and then Places_Fit (Hull, Q);
   --  The corner between the sides S - 1 and S: where their lines
   --  meet, if that is near the corner of the hull, or nearer still
   --  to the corner of the hull before or after it (the pixels cut
   --  the tip of a corner off).

   function Corner_Of
     (Hull  : DA.Point_Array;
      Q     : Place_Array;
      Lines : Line_Array;
      S     : Side) return Corner
   is
      P     : constant Corner := To_Corner (Hull (Q (S)));
      Where : Corner;
      Met   : Boolean;
      Next  : Corner;
   begin
      if Lines (S - 1).Good and then Lines (S).Good then
         Meet (Lines (S - 1).P1, Lines (S - 1).P2,
               Lines (S).P1, Lines (S).P2, Where, Met);
         if Met then
            if Distance (P, Where) <= Near then
               return Where;
            end if;
            for Back in Boolean loop
               for T in 1 .. Hull'Length - 1 loop
                  Next := At_Place
                    (Hull, Q (S), (if Back then Hull'Length - T else T));
                  exit when T > 1
                    and then Distance (P, Next) > Widest_Cut;
                  if Distance (Next, Where) <= Loose then
                     return Where;
                  end if;
               end loop;
            end loop;
         end if;
      end if;
      return P;
   end Corner_Of;

   function Part_Of (Part, Whole : Length_Value) return Share_Value
   with Pre => Whole >= Min_Side;
   --  Part / Whole, and 1.0 where that is more.

   function Part_Of (Part, Whole : Length_Value) return Share_Value is
   begin
      return Long_Float'Min (1.0, Quotient (Part, Whole, Far));
   end Part_Of;

   procedure Take_Ends
     (Hull  : DA.Point_Array;
      Lines : Line_Array;
      L     : Side;
      Q     : in out Place_Array)
   with Pre  => Valid_Hull (Hull) and then Places_Fit (Hull, Q)
                and then Lines_Fit (Hull, Lines),
        Post => Places_Fit (Hull, Q);
   --  The ends of the arms of the L (the sides L - 1 and L). A corner of
   --  the hull that is off the line of its arm is not the end of the arm
   --  but a module of the alternating side beyond it: the end of the
   --  straight part of the arm takes its place.

   procedure Take_Ends
     (Hull  : DA.Point_Array;
      Lines : Line_Array;
      L     : Side;
      Q     : in out Place_Array) is
   begin
      pragma Assert
        (Lines (L).I2 <= Hull'Last and then Lines (L - 1).I1 <= Hull'Last);
      if Lines (L).Good
        and then abs Off_Line (Lines (L).P1, Lines (L).P2,
                               To_Corner (Hull (Q (L + 1))))
                 > Loose * Distance (Lines (L).P1, Lines (L).P2)
      then
         Q (L + 1) := Lines (L).I2;
      end if;
      if Lines (L - 1).Good
        and then abs Off_Line (Lines (L - 1).P1, Lines (L - 1).P2,
                               To_Corner (Hull (Q (L - 1))))
                 > Loose * Distance (Lines (L - 1).P1, Lines (L - 1).P2)
      then
         Q (L - 1) := Lines (L - 1).I1;
      end if;
   end Take_Ends;

   procedure Analyse
     (Map    : DA.Mark_Map;
      Hull   : DA.Point_Array;
      Symbol : out Outline;
      Found  : out Boolean;
      Share  : out Share_Value)
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
      Share  : out Share_Value)
   is
      Q      : Place_Array := [others => 1];
      Solid  : array (Side) of Solidity := [others => 0];
      Long   : array (Side) of Length_Value := [others => 0.0];
      Lines  : Line_Array;
      L      : Side := 0;
      Have_L : Boolean := False;
      Best   : Length_Value := 0.0;
      Short  : Length_Value;
      Deep   : Solidity;
      Least  : Solidity := Solidity'Last;
      OK     : Boolean;
      A, B   : Corner;
      C, D   : Corner;
      LA, LB : Length_Value;
      HC, HD : Cross;
      Other  : Share_Value;
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
         pragma Loop_Invariant (Lines_Fit (Hull, Lines));
         Fit (Map, Hull, Q, L, S, False, Lines);
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
      Take_Ends (Hull, Lines, L, Q);

      --  The lines of the other two sides have to pass the ends of the
      --  arms.
      Fit (Map, Hull, Q, L, L + 1, True, Lines);
      Fit (Map, Hull, Q, L, L + 2, True, Lines);
      C := Corner_Of (Hull, Q, Lines, L);
      A := Corner_Of (Hull, Q, Lines, L + 1);
      B := Corner_Of (Hull, Q, Lines, L + 3);
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
      Share := Part_Of (Distance (Lines (L + 1).P1, Lines (L + 1).P2), LA);
      Other := Part_Of (Distance (Lines (L + 2).P1, Lines (L + 2).P2), LB);
      if Other < Share then
         Share := Other;
      end if;
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
      Unused_Share : Share_Value;
   begin
      Analyse (Map, Hull, Symbol, Found, Unused_Share);
   end Locate;

   ---------------------------------------------------------------------
   --  All the dark pixels of a symbol
   ---------------------------------------------------------------------

   subtype Margin_Value is Long_Float range 0.0 .. Limit;
   --  How far around an outline its dark pixels are looked for.

   Push_Reach : constant := Limit * Span;
   --  A margin times the difference of two coordinates, at most.

   function Pushed
     (P, Before, After : Corner;
      Margin           : Margin_Value) return Corner
   with Post => abs Pushed'Result.X <= Limit
                and then abs Pushed'Result.Y <= Limit;
   --  The corner P of an outline, between the corners Before and After,
   --  moved outwards by Margin along both of its sides.

   function Pushed
     (P, Before, After : Corner;
      Margin           : Margin_Value) return Corner
   is
      L1 : constant Length_Value := Distance (Before, P);
      L2 : constant Length_Value := Distance (After, P);
      X  : Long_Float := P.X;
      Y  : Long_Float := P.Y;
   begin
      if L1 >= 1.0 then
         X := X + Quotient
                    (N.Mul_Within (Margin, P.X - Before.X, Limit, Span),
                     L1, Push_Reach);
         Y := Y + Quotient
                    (N.Mul_Within (Margin, P.Y - Before.Y, Limit, Span),
                     L1, Push_Reach);
      end if;
      if L2 >= 1.0 then
         X := X + Quotient
                    (N.Mul_Within (Margin, P.X - After.X, Limit, Span),
                     L2, Push_Reach);
         Y := Y + Quotient
                    (N.Mul_Within (Margin, P.Y - After.Y, Limit, Span),
                     L2, Push_Reach);
      end if;
      if abs X < Limit and then abs Y < Limit then
         return (X, Y);
      else
         return P;
      end if;
   end Pushed;

   type Quad is array (0 .. 3) of Corner;

   procedure Cut
     (P      : Quad;
      Y      : Natural;
      XL, XR : out Long_Float;
      Have   : out Boolean)
   with Pre => Y < DA.Max_Side;
   --  The part of the row Y, at the height of the middle of its pixels,
   --  that is within the outline with the corners P: from XL to XR. Not
   --  Have: none.

   procedure Cut
     (P      : Quad;
      Y      : Natural;
      XL, XR : out Long_Float;
      Have   : out Boolean)
   is
      YC : constant Coordinate := Long_Float (Y) + 0.5;
      X  : Long_Float;
   begin
      Have := False;
      XL := 0.0;
      XR := 0.0;
      for K in 0 .. 3 loop
         declare
            A  : constant Corner := P (K);
            B  : constant Corner := P ((K + 1) mod 4);
            DY : constant Offset := B.Y - A.Y;
         begin
            if (A.Y <= YC) /= (B.Y <= YC) and then DY /= 0.0 then
               X := A.X
                 + Quotient
                     (N.Mul_Within (YC - A.Y, B.X - A.X, Span, Span),
                      DY, 2.0 * Span);
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
   end Cut;

   procedure Extents
     (Map        : DA.Mark_Map;
      Symbol     : Outline;
      Margin     : Margin_Value;
      Lefts      : in out DA.Extent_Array;
      Rights     : in out DA.Extent_Array;
      Y_Lo, Y_Hi : out Natural;
      Any        : out Boolean)
   with Pre  => DA.Valid_Map (Map)
                and then DA.Extents_Fit (Lefts, Map)
                and then DA.Extents_Fit (Rights, Map),
        Post => Y_Lo <= Y_Hi and then Y_Hi <= Map'Last (1);
   --  The leftmost and the rightmost dark pixel of every row within the
   --  outline, grown by Margin. Any: there is one, in the rows
   --  Y_Lo .. Y_Hi.

   procedure Extents
     (Map        : DA.Mark_Map;
      Symbol     : Outline;
      Margin     : Margin_Value;
      Lefts      : in out DA.Extent_Array;
      Rights     : in out DA.Extent_Array;
      Y_Lo, Y_Hi : out Natural;
      Any        : out Boolean)
   is
      P : constant Quad :=
        [Pushed (Symbol.Upper_Left, Symbol.Lower_Left, Symbol.Upper_Right,
                 Margin),
         Pushed (Symbol.Upper_Right, Symbol.Upper_Left, Symbol.Lower_Right,
                 Margin),
         Pushed (Symbol.Lower_Right, Symbol.Upper_Right, Symbol.Lower_Left,
                 Margin),
         Pushed (Symbol.Lower_Left, Symbol.Lower_Right, Symbol.Upper_Left,
                 Margin)];
      Top    : Coordinate := P (0).Y;
      Bottom : Coordinate := P (0).Y;
      First  : Natural;
      Last   : Natural;
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
      First := (if Top <= 0.0 then 0
                else Floor_Index (Top, Map'Last (1)));
      Last := (if Bottom >= Long_Float (Map'Last (1)) then Map'Last (1)
               else Floor_Index (Bottom, Map'Last (1)));

      for Y in First .. Last loop
         pragma Loop_Invariant (Y_Lo <= Y_Hi and then Y_Hi <= Y);
         Cut (P, Y, XL, XR, Have);
         if Have and then XR >= 0.0
           and then XL <= Long_Float (Map'Last (2))
         then
            IL := (if XL <= 0.0 then 0
                   else Floor_Index (XL, Map'Last (2)));
            IR := (if XR >= Long_Float (Map'Last (2)) then Map'Last (2)
                   else Floor_Index (XR, Map'Last (2)));
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
      Shorter : constant Length_Value :=
        Long_Float'Min
          (Distance (Symbol.Lower_Left, Symbol.Upper_Left),
           Distance (Symbol.Lower_Left, Symbol.Lower_Right));
      Widest     : constant Long_Float range 0.0 .. Limit / 2.0 :=
        Shorter / 8.0;
      Margin     : Margin_Value := Narrow;
      Y_Lo, Y_Hi : Natural;
      Any        : Boolean;
      Count      : Natural;
      Now        : Outline := Symbol;
      Before     : Outline := Symbol;
      Next       : Outline;
      OK         : Boolean;
      Share      : Share_Value;
      Still      : Boolean;
      Have_Best  : Boolean := False;
   begin
      for Round in 1 .. Rounds loop
         pragma Loop_Invariant (Margin <= Limit / 2.0);
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
      Length       : constant Length_Value := Distance (A, B);
      Unused_Dark  : Natural;
      Unused_Total : Natural;
      Total        : Natural;
      Changes      : Natural;
      Module       : Length_Value;
   begin
      Scan_Side (Map, A, B, Inset, 0.0, 1.0, Unused_Dark, Total, Changes);
      Count := Changes + 1;
      if Total = 0 then
         Count := 0;
         return;
      end if;
      Module := Quotient (Length, Long_Float (Count), Far);
      if Module > 2.0 * Inset then
         Scan_Side (Map, A, B, 0.5 * Module, 0.0, 1.0, Unused_Dark,
                    Unused_Total, Changes);
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

   Fine : constant := 8;
   --  The steps of a module by which the places of the columns are
   --  tried.

   Reach : constant := 4;
   --  The places of the columns of a symbol with twice as many columns
   --  as rows, or more, are tried as far as Reach steps for every time
   --  that the columns are as many as the rows.

   Max_Steps : constant := Reach * Max_Side;

   subtype Step_Index is Integer range -Max_Steps .. Max_Steps;

   type Score_Array is array (Step_Index) of Natural;

   subtype Step_Count is Natural range 0 .. Max_Steps;

   subtype Step_Sum is Integer range -2 * Max_Steps .. 2 * Max_Steps;

   Tilt_Limit : constant := VW.Tilt_Limit;
   --  The two factors of a mapping that make the view a perspective
   --  one, at most: a sum of two products of differences of coordinates
   --  by a determinant of 1.0E-9 or more.

   subtype Skew is Long_Float range -Far .. Far;
   subtype Tilt is VW.Tilt;

   subtype Mapping is VW.Mapping;
   --  Here the perspective mapping that takes the unit square to the
   --  four corners of a symbol: (0, 0) to the upper left, (1, 0) to the
   --  upper right and (1, 1) to the lower right one.

   subtype Spacing is Long_Float range 0.25 .. 4.0;
   --  The factor K of Spaced.

   subtype Spread is VW.Spread;
   --  A share of the way along the upper side as Spaced gives it.

   function Share_Of
     (I     : Natural;
      Part  : Share_Value;
      Count : Positive) return Share_Value
   with Pre => I < Count and then Count <= Max_Side;
   --  (I + Part) / Count: the share of the way along Count modules at
   --  which the part Part of the module I is.

   function Share_Of
     (I     : Natural;
      Part  : Share_Value;
      Count : Positive) return Share_Value is
   begin
      return Quotient (Long_Float (I) + Part, Long_Float (Count), 1.0);
   end Share_Of;

   function Stretch (Step : Step_Sum; Parts : Positive) return Spacing
   with Pre => Parts <= 2 * Fine * Max_Side;
   --  The factor K of Spaced that takes the middle of the upper side
   --  Step / Parts of the side towards the upper right corner (a
   --  quarter of the side at most).

   function Stretch (Step : Step_Sum; Parts : Positive) return Spacing is
      S : constant Long_Float :=
        N.Clamp
          (Quotient (Long_Float (Step), Long_Float (Parts), 1.0), 0.25);
   begin
      return Long_Float'Max (0.25, Quotient (0.5 - S, 0.5 + S, 4.0));
   end Stretch;

   function Spaced (U : Share_Value; K : Spacing) return Spread
   with Post => abs Spaced'Result <= 4.0;
   --  The share U of the way along the upper side, with the shares
   --  0.0 and 1.0 in place, as a perspective view spaces it.

   function Spaced (U : Share_Value; K : Spacing) return Spread is
   begin
      return Quotient
        (U, Long_Float'Max (0.25, K + N.Times_Unit (1.0 - K, U)), 4.0);
   end Spaced;

   function Score
     (Map           : DA.Mark_Map;
      M             : Mapping;
      Rows, Columns : Positive;
      K             : Spacing) return Natural
   with Pre  => DA.Valid_Map (Map)
                and then Rows <= Max_Side and then Columns <= Max_Side,
        Post => Score'Result <= 2 * Columns;
   --  The points of the upper side, two a module, that are dark or
   --  light as the side alternates, with the columns spaced by K.

   function Score
     (Map           : DA.Mark_Map;
      M             : Mapping;
      Rows, Columns : Positive;
      K             : Spacing) return Natural
   is
      V0     : constant Share_Value := Share_Of (0, 0.5, Rows);
      U      : Share_Value;
      Result : Natural := 0;
   begin
      for C in 0 .. Columns - 1 loop
         pragma Loop_Invariant (Result <= 2 * C);
         for Half in Boolean loop
            U := Share_Of (C, (if Half then 0.75 else 0.25), Columns);
            if VW.Dark_In (Map, M, Spaced (U, K), V0) = (C mod 2 = 0) then
               Result := Result + 1;
            end if;
         end loop;
      end loop;
      return Result;
   end Score;

   function Middle
     (M    : Mapping;
      K    : Spacing;
      Mean : Corner) return Corner
   with Post => abs Middle'Result.X <= Limit
                and then abs Middle'Result.Y <= Limit;
   --  The middle of a symbol, with the columns spaced by K: where the
   --  mapping takes the middle of the unit square, and Mean where it
   --  gives no point, or one farther than Limit from an axis.

   function Middle
     (M    : Mapping;
      K    : Spacing;
      Mean : Corner) return Corner
   is
      X, Y  : Long_Float;
      Ahead : Boolean;
   begin
      VW.Project (M, Spaced (0.5, K), 0.5, X, Y, Ahead);
      if Ahead and then abs X <= Limit and then abs Y <= Limit then
         return (X, Y);
      else
         return Mean;
      end if;
   end Middle;

   procedure Sample
     (Map           : DA.Mark_Map;
      Symbol        : Outline;
      Rows, Columns : Positive;
      Grid          : out Module_Grid;
      Centre        : out Corner)
   is
      X0 : constant Coordinate := Symbol.Upper_Left.X;
      Y0 : constant Coordinate := Symbol.Upper_Left.Y;
      X1 : constant Coordinate := Symbol.Upper_Right.X;
      Y1 : constant Coordinate := Symbol.Upper_Right.Y;
      X2 : constant Coordinate := Symbol.Lower_Right.X;
      Y2 : constant Coordinate := Symbol.Lower_Right.Y;
      X3 : constant Coordinate := Symbol.Lower_Left.X;
      Y3 : constant Coordinate := Symbol.Lower_Left.Y;

      DX1 : constant Offset := X1 - X2;
      DX2 : constant Offset := X3 - X2;
      DX3 : constant Skew := X0 - X1 + X2 - X3;
      DY1 : constant Offset := Y1 - Y2;
      DY2 : constant Offset := Y3 - Y2;
      DY3 : constant Skew := Y0 - Y1 + Y2 - Y3;
      Den : constant Cross :=
        N.Mul_Within (DX1, DY2, Span, Span)
        - N.Mul_Within (DX2, DY1, Span, Span);

      Steps : constant Step_Count :=
        (if Columns >= 2 * Rows then Reach * (Columns / Rows) else 0);

      G, H   : Tilt;
      M      : Mapping;
      U      : Spread;
      V      : Share_Value;
      K      : Spacing;
      Scores : Score_Array := [others => 0];
      Best   : Natural := 0;
      Lo     : Step_Index := 0;
      Hi     : Step_Index;
   begin
      Grid := [others => [others => False]];
      Centre := (X => (X0 + X1 + X2 + X3) / 4.0,
                 Y => (Y0 + Y1 + Y2 + Y3) / 4.0);
      if abs Den < 1.0E-9 then
         return;
      end if;
      G := Quotient
        (N.Mul_Within (DX3, DY2, Far, Span)
         - N.Mul_Within (DX2, DY3, Span, Far),
         Den, Tilt_Limit);
      H := Quotient
        (N.Mul_Within (DX1, DY3, Span, Far)
         - N.Mul_Within (DX3, DY1, Far, Span),
         Den, Tilt_Limit);
      M := (G  => G,
            H  => H,
            A  => VW.Factor_Of (X0, X1, G),
            B  => VW.Factor_Of (X0, X3, H),
            D  => VW.Factor_Of (Y0, Y1, G),
            E  => VW.Factor_Of (Y0, Y3, H),
            X0 => X0,
            Y0 => Y0);

      --  The spacing of the columns that agrees best with the upper
      --  side: of the places that agree best, the middle of those next
      --  to each other that are nearest to what the corners give.
      for Step in -Steps .. Steps loop
         Scores (Step) :=
           Score (Map, M, Rows, Columns, Stretch (Step, Fine * Columns));
         Best := Natural'Max (Best, Scores (Step));
      end loop;
      for Step in 0 .. Steps loop
         if Scores (Step) = Best then
            Lo := Step;
            exit;
         elsif Scores (-Step) = Best then
            Lo := -Step;
            exit;
         end if;
      end loop;
      Hi := Lo;
      while Lo > -Steps and then Scores (Lo - 1) = Best loop
         Lo := Lo - 1;
      end loop;
      while Hi < Steps and then Scores (Hi + 1) = Best loop
         Hi := Hi + 1;
      end loop;
      K := Stretch (Lo + Hi, 2 * Fine * Columns);

      for R in 0 .. Rows - 1 loop
         V := Share_Of (R, 0.5, Rows);
         for C in 0 .. Columns - 1 loop
            U := Spaced (Share_Of (C, 0.5, Columns), K);
            Grid (Module_Index (R), Module_Index (C)) :=
              VW.Dark_In (Map, M, U, V);
         end loop;
      end loop;

      --  The middle of the symbol, with the columns spaced as they were
      --  read.
      Centre := Middle (M, K, Centre);
   end Sample;

end AMV.Kernels.Code_Reader.Data_Matrix.Finder;
