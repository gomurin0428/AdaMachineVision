pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package body AMV.Kernels.Code_Reader.Dark_Areas
  with SPARK_Mode
is

   use type KI.Grey_8;

   subtype Level is Integer range 0 .. 255;

   Reach : constant := 2;
   --  The blocks on every side of a block whose middle levels make its
   --  threshold.

   ---------------------------------------------------------------------
   --  Dark pixels
   ---------------------------------------------------------------------

   function Last_Of (First, Last : Natural) return Natural is
     (if Last - First >= Block - 1 then First + (Block - 1) else Last)
   with
     Pre  => First <= Last,
     Post => Last_Of'Result in First .. Last
             and then Last_Of'Result - First <= Block - 1;
   --  The last row (or column) of the block that begins at First, in a
   --  map whose last one is Last.

   procedure Measure_Block
     (Pixels     : KI.Grey_8_Matrix;
      Y0, Y1     : Natural;
      X0, X1     : Natural;
      Low, High  : out KI.Grey_8)
   with
     Pre => Y0 <= Y1 and then Y1 <= Pixels'Last (1)
            and then Pixels'First (1) = 0 and then Pixels'First (2) = 0
            and then X0 <= X1 and then X1 <= Pixels'Last (2);
   --  The lowest and the highest level of the pixels in the rows
   --  Y0 .. Y1 and the columns X0 .. X1.

   procedure Measure_Block
     (Pixels     : KI.Grey_8_Matrix;
      Y0, Y1     : Natural;
      X0, X1     : Natural;
      Low, High  : out KI.Grey_8) is
   begin
      Low := 255;
      High := 0;
      for Y in Y0 .. Y1 loop
         for X in X0 .. X1 loop
            Low := KI.Grey_8'Min (Low, Pixels (Y, X));
            High := KI.Grey_8'Max (High, Pixels (Y, X));
         end loop;
      end loop;
   end Measure_Block;

   function Has_Middle
     (Low, High : KI.Grey_8;
      Contrast  : Positive) return Boolean
   is (High >= Low and then Integer (High) - Integer (Low) >= Contrast);

   procedure Local_Threshold
     (Lows, Highs : KI.Grey_8_Matrix;
      BY, BX      : Natural;
      Contrast    : Positive;
      Default     : Level;
      Threshold   : out Level)
   with
     Pre => Lows'First (1) = 0 and then Lows'First (2) = 0
            and then Highs'First (1) = 0 and then Highs'First (2) = 0
            and then Lows'Last (1) = Highs'Last (1)
            and then Lows'Last (2) = Highs'Last (2)
            and then Lows'Last (1) < Max_Side
            and then Lows'Last (2) < Max_Side
            and then BY <= Lows'Last (1) and then BX <= Lows'Last (2);
   --  The mean of the middle levels of the blocks within Reach of the
   --  block (BY, BX). If there is none: the level halfway between the
   --  darkest and the lightest pixel of these blocks if they differ by
   --  Contrast or more, else Default.

   procedure Local_Threshold
     (Lows, Highs : KI.Grey_8_Matrix;
      BY, BX      : Natural;
      Contrast    : Positive;
      Default     : Level;
      Threshold   : out Level)
   is
      Y0  : constant Natural := (if BY >= Reach then BY - Reach else 0);
      Y1  : constant Natural :=
        (if Lows'Last (1) - BY >= Reach then BY + Reach
         else Lows'Last (1));
      X0  : constant Natural := (if BX >= Reach then BX - Reach else 0);
      X1  : constant Natural :=
        (if Lows'Last (2) - BX >= Reach then BX + Reach
         else Lows'Last (2));
      Sum : Natural := 0;
      N   : Natural := 0;
      Low : Level := 255;
      High : Level := 0;
   begin
      for Y in Y0 .. Y1 loop
         pragma Loop_Invariant (N <= (Y - Y0) * (2 * Reach + 1));
         pragma Loop_Invariant (Sum <= N * 510);
         for X in X0 .. X1 loop
            pragma Loop_Invariant
              (N <= (Y - Y0) * (2 * Reach + 1) + (X - X0));
            pragma Loop_Invariant (Sum <= N * 510);
            if Has_Middle (Lows (Y, X), Highs (Y, X), Contrast) then
               Sum := Sum + Integer (Lows (Y, X)) + Integer (Highs (Y, X));
               N := N + 1;
            end if;
            Low := Integer'Min (Low, Integer (Lows (Y, X)));
            High := Integer'Max (High, Integer (Highs (Y, X)));
         end loop;
      end loop;
      if N > 0 then
         Threshold := Sum / (2 * N);
      elsif High - Low >= Contrast then
         Threshold := (Low + High) / 2;
      else
         Threshold := Default;
      end if;
   end Local_Threshold;

   function Mean_Level (Sum, N : Int64) return Level
   with Pre => N in 1 .. 2 ** 52 and then Sum in 0 .. 510 * N;
   --  Sum / (2 * N): the mean of N middle levels, where Sum is the sum
   --  of the lightest and of the darkest pixel of each.

   function Mean_Level (Sum, N : Int64) return Level is
      D : constant Int64 := 2 * N;
      Q : constant Int64 := Sum / D;
   begin
      --  The steps by which the provers see at once that the quotient
      --  is a level.
      pragma Assert (Sum <= 255 * D);
      pragma Assert (Q * D <= Sum);
      pragma Assert (if Q >= 256 then Q * D >= 256 * D);
      pragma Assert (Q <= 255);
      return Level (Q);
   end Mean_Level;

   procedure Binarise
     (Pixels     : KI.Grey_8_Matrix;
      X_Lo, Y_Lo : Natural;
      Contrast   : Positive;
      Lows       : in out KI.Grey_8_Matrix;
      Highs      : in out KI.Grey_8_Matrix;
      Map        : in out Mark_Map)
   is
      Sum       : Int64 := 0;
      N         : Int64 := 0;
      Low       : Level := 255;
      High      : Level := 0;
      Default   : Level;
      Threshold : Level;
      Y0, Y1    : Natural;
      X0, X1    : Natural;
   begin
      for BY in Lows'Range (1) loop
         pragma Loop_Invariant
           (N in 0 .. Int64 (BY) * (Int64 (Lows'Last (2)) + 1));
         pragma Loop_Invariant (Sum in 0 .. 510 * N);
         Y0 := BY * Block;
         Y1 := Last_Of (Y0, Map'Last (1));
         for BX in Lows'Range (2) loop
            pragma Loop_Invariant
              (N in 0 .. Int64 (BY) * (Int64 (Lows'Last (2)) + 1)
                         + Int64 (BX));
            pragma Loop_Invariant (Sum in 0 .. 510 * N);
            X0 := BX * Block;
            X1 := Last_Of (X0, Map'Last (2));
            Measure_Block (Pixels, Y_Lo + Y0, Y_Lo + Y1, X_Lo + X0,
                           X_Lo + X1, Lows (BY, BX), Highs (BY, BX));
            if Has_Middle (Lows (BY, BX), Highs (BY, BX), Contrast) then
               Sum := Sum + Int64 (Lows (BY, BX)) + Int64 (Highs (BY, BX));
               N := N + 1;
            end if;
            Low := Integer'Min (Low, Integer (Lows (BY, BX)));
            High := Integer'Max (High, Integer (Highs (BY, BX)));
         end loop;
      end loop;

      if N > 0 then
         Default := Mean_Level (Sum, N);
      elsif High - Low >= Contrast then
         Default := (Low + High) / 2;
      else
         Map := [others => [others => Light]];
         return;
      end if;

      for BY in Lows'Range (1) loop
         Y0 := BY * Block;
         Y1 := Last_Of (Y0, Map'Last (1));
         for BX in Lows'Range (2) loop
            X0 := BX * Block;
            X1 := Last_Of (X0, Map'Last (2));
            Local_Threshold (Lows, Highs, BY, BX, Contrast, Default,
                             Threshold);
            for Y in Y0 .. Y1 loop
               for X in X0 .. X1 loop
                  Map (Y, X) :=
                    (if Integer (Pixels (Y_Lo + Y, X_Lo + X)) <= Threshold
                     then Dark else Light);
               end loop;
            end loop;
         end loop;
      end loop;
   end Binarise;

   ---------------------------------------------------------------------
   --  Outlines
   ---------------------------------------------------------------------

   type Direction is mod 8;
   --  East, south-east, south, ... north-east: clockwise as the image
   --  is seen.

   subtype Step is Integer range -1 .. 1;

   DX : constant array (Direction) of Step := [1, 1, 0, -1, -1, -1, 0, 1];
   DY : constant array (Direction) of Step := [0, 1, 1, 1, 0, -1, -1, -1];

   West : constant Direction := 4;

   function Is_Dark (Map : Mark_Map; X, Y : Integer) return Boolean is
     (Y in 0 .. Map'Last (1) and then X in 0 .. Map'Last (2)
      and then Map (Y, X) /= Light)
   with Pre => Valid_Map (Map);

   procedure Next_Step
     (Map    : Mark_Map;
      X, Y   : Natural;
      Back   : Direction;
      Found  : out Boolean;
      Move   : out Direction)
   with
     Pre  => Valid_Map (Map)
             and then Y <= Map'Last (1) and then X <= Map'Last (2),
     Post => (if Found then Is_Dark (Map, X + DX (Move), Y + DY (Move)));
   --  The first dark neighbour of the pixel (X, Y), clockwise after the
   --  neighbour in the direction Back.

   procedure Next_Step
     (Map    : Mark_Map;
      X, Y   : Natural;
      Back   : Direction;
      Found  : out Boolean;
      Move   : out Direction)
   is
      D : Direction;
   begin
      Found := False;
      Move := Back;
      for K in Direction range 1 .. 7 loop
         D := Back + K;
         if Is_Dark (Map, X + DX (D), Y + DY (D)) then
            Found := True;
            Move := D;
            return;
         end if;
      end loop;
   end Next_Step;

   Area_Limit : constant := 2 ** 62;
   --  Twice the enclosed area of Trace, at most: a clamp that never acts
   --  for a map of fewer than 2 ** 19 rows and columns (the sum is at
   --  most the steps, eight a pixel, times the two coordinates).

   function Back_Of (Move : Direction) return Direction is
     (if Move mod 2 = 0 then Move + 6 else Move + 5);
   --  After a step in the direction Move: the direction of the light
   --  neighbour that was looked at last before the step.

   procedure Trace
     (Map        : in out Mark_Map;
      X, Y       : Natural;
      Lefts      : in out Extent_Array;
      Rights     : in out Extent_Array;
      Y_Lo, Y_Hi : out Natural;
      Area       : out Int64;
      Closed     : out Boolean)
   is
      Limit : constant Int64 :=
        8 * Int64 (Map'Length (1)) * Int64 (Map'Length (2));
      Term  : Int64;
      Steps : Int64 := 0;
      CX    : Natural := X;
      CY    : Natural := Y;
      NX    : Natural;
      NY    : Natural;
      Found : Boolean;
      First : Direction;
      Move  : Direction;
   begin
      Y_Lo := Y;
      Y_Hi := Y;
      Area := 0;
      Closed := False;
      Map (Y, X) := Traced;
      Lefts (Y) := Integer'Min (Lefts (Y), X);
      Rights (Y) := Integer'Max (Rights (Y), X);
      Next_Step (Map, X, Y, West, Found, First);
      if not Found then
         Closed := True;
         return;
      end if;
      Move := First;
      while Steps < Limit loop
         pragma Loop_Invariant
           (Is_Dark (Map, CX + DX (Move), CY + DY (Move)));
         pragma Loop_Invariant
           (Y_Lo <= Y and then Y <= Y_Hi and then Y_Hi <= Map'Last (1));
         pragma Loop_Invariant
           (CY <= Map'Last (1) and then CX <= Map'Last (2));
         pragma Loop_Invariant (Area in -Area_Limit .. Area_Limit);
         pragma Loop_Variant (Increases => Steps);
         NX := CX + DX (Move);
         NY := CY + DY (Move);
         Term := Int64 (CX) * Int64 (NY) - Int64 (NX) * Int64 (CY);
         pragma Assert (Term in -2 ** 53 .. 2 ** 53);
         Area :=
           Int64'Max (-Area_Limit, Int64'Min (Area_Limit, Area + Term));
         CX := NX;
         CY := NY;
         Steps := Steps + 1;
         Map (CY, CX) := Traced;
         Lefts (CY) := Integer'Min (Lefts (CY), CX);
         Rights (CY) := Integer'Max (Rights (CY), CX);
         Y_Lo := Natural'Min (Y_Lo, CY);
         Y_Hi := Natural'Max (Y_Hi, CY);
         Next_Step (Map, CX, CY, Back_Of (Move), Found, Move);
         exit when not Found;
         if CX = X and then CY = Y and then Move = First then
            Closed := True;
            exit;
         end if;
      end loop;
   end Trace;

   procedure Clear
     (Lefts      : in out Extent_Array;
      Rights     : in out Extent_Array;
      Y_Lo, Y_Hi : Natural) is
   begin
      for Y in Y_Lo .. Y_Hi loop
         Lefts (Y) := No_Left;
         Rights (Y) := No_Right;
      end loop;
   end Clear;

   ---------------------------------------------------------------------
   --  Hull
   ---------------------------------------------------------------------

   function Turn (A, B, C : Point) return Int64 is
     (Int64 (B.X - A.X) * Int64 (C.Y - B.Y)
      - Int64 (B.Y - A.Y) * Int64 (C.X - B.X));
   --  Positive: the way from A by B to C turns to the right, as the
   --  image is seen.

   function Rightmost
     (Rights     : Extent_Array;
      Y_Lo, Y_Hi : Natural;
      Y          : Natural) return Integer
   is
     (Integer'Max
        ((if Y <= Y_Hi then Rights (Y) else No_Right),
         (if Y > Y_Lo then Rights (Y - 1) else No_Right)))
   with Pre => Rights'First = 0 and then Rights'Last < Max_Side
               and then Y_Hi <= Rights'Last
               and then Y in Y_Lo .. Y_Hi + 1;
   --  The rightmost pixel of the two rows that meet at the height Y.

   function Leftmost
     (Lefts      : Extent_Array;
      Y_Lo, Y_Hi : Natural;
      Y          : Natural) return Integer
   is
     (Integer'Min
        ((if Y <= Y_Hi then Lefts (Y) else No_Left),
         (if Y > Y_Lo then Lefts (Y - 1) else No_Left)))
   with Pre => Lefts'First = 0 and then Lefts'Last < Max_Side
               and then Y_Hi <= Lefts'Last
               and then Y in Y_Lo .. Y_Hi + 1;

   procedure Hull
     (Lefts      : Extent_Array;
      Rights     : Extent_Array;
      Y_Lo, Y_Hi : Natural;
      Points     : in out Point_Array;
      Count      : out Natural)
   is
      Base : Natural;
      Edge : Integer;
      P    : Point;
   begin
      Count := 0;

      --  Down the right side.
      for Y in Y_Lo .. Y_Hi + 1 loop
         pragma Loop_Invariant (Count <= Y - Y_Lo);
         Edge := Rightmost (Rights, Y_Lo, Y_Hi, Y);
         if Edge in 0 .. Max_Side - 1 then
            P := (Edge + 1, Y);
            while Count >= 2
              and then Turn (Points (Count - 1), Points (Count), P) <= 0
            loop
               pragma Loop_Invariant (Count in 2 .. Count'Loop_Entry);
               Count := Count - 1;
            end loop;
            Count := Count + 1;
            Points (Count) := P;
         end if;
      end loop;

      --  Up the left side; the lowest corner of the right side stays.
      Base := Count;
      for Y in reverse Y_Lo .. Y_Hi + 1 loop
         pragma Loop_Invariant (Base <= Y_Hi - Y_Lo + 2);
         pragma Loop_Invariant (Count in Base .. Base + (Y_Hi + 1 - Y));
         Edge := Leftmost (Lefts, Y_Lo, Y_Hi, Y);
         if Edge in 0 .. Max_Side - 1 then
            P := (Edge, Y);
            while Count > Base and then Count >= 2
              and then Turn (Points (Count - 1), Points (Count), P) <= 0
            loop
               pragma Loop_Invariant
                 (Count in Base + 1 .. Count'Loop_Entry
                  and then Count >= 2);
               Count := Count - 1;
            end loop;
            Count := Count + 1;
            Points (Count) := P;
         end if;
      end loop;
   end Hull;

end AMV.Kernels.Code_Reader.Dark_Areas;
