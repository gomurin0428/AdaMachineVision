pragma Validity_Checks ("F");
with Ada.Numerics.Long_Elementary_Functions;

with AMV.Kernels.Numerics;

package body AMV.Kernels.Code_Reader.QR_Code.Finder
  with SPARK_Mode
is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package N renames AMV.Kernels.Numerics;

   use type DA.Mark;

   ---------------------------------------------------------------------
   --  The runs of a finder pattern
   ---------------------------------------------------------------------

   subtype Run_Length is Natural range 0 .. 2 ** 28;
   --  The pixels of a run (a map has 2 ** 26 a side at most).

   subtype Walk_Length is Natural range 0 .. DA.Max_Side;

   type Run_Array is array (1 .. 5) of Run_Length;
   --  Dark, light, dark, light and dark.

   function Total (Runs : Run_Array) return Int64 is
     (Int64 (Runs (1)) + Int64 (Runs (2)) + Int64 (Runs (3))
      + Int64 (Runs (4)) + Int64 (Runs (5)));

   function In_Proportion (Runs : Run_Array) return Boolean is
     ((for all I in Runs'Range => Runs (I) > 0)
      and then (for all I in Runs'Range =>
                  (if I = 3
                   then 2 * abs (7 * Int64 (Runs (I)) - 3 * Total (Runs))
                        <= 3 * Total (Runs) + 7
                   else 2 * abs (7 * Int64 (Runs (I)) - Total (Runs))
                        <= Total (Runs) + 7)));
   --  The runs are those of a finder pattern: 1 : 1 : 3 : 1 : 1, the
   --  narrow ones within half a module and half a pixel of their width
   --  (those of a pattern with modules of two pixels may have one
   --  pixel or three, wherever the pattern lies on the pixels) and the
   --  wide one within a module and a half and half a pixel.

   function Alike (T, Other : Int64) return Boolean is
     (5 * abs (T - Other) < 2 * Other)
   with Pre => T in 0 .. 2 ** 32 and then Other in 0 .. 2 ** 32;
   --  The widths of a pattern along two lines differ by less than two
   --  fifths.

   subtype Step is Integer range -1 .. 1;

   procedure Walk
     (Map     : DA.Mark_Map;
      X, Y    : Natural;
      DX, DY  : Step;
      Most    : Walk_Length;
      A, B, C : out Run_Length;
      OK      : out Boolean)
   with Pre  => DA.Valid_Map (Map)
                and then X <= Map'Last (2) and then Y <= Map'Last (1),
        Post => A <= DA.Max_Side + 1 and then B <= DA.Max_Side + 1
                and then C <= DA.Max_Side + 1,
        Always_Terminates;
   --  From the pixel (X, Y) of the middle of a pattern in the direction
   --  (DX, DY): the dark pixels that follow it (A), the light ones
   --  after them (B) and the dark ones after these (C), to the edge of
   --  the map at most. Not OK: no light or no dark pixels after the
   --  middle, or a run of more than Most pixels.

   procedure Walk
     (Map     : DA.Mark_Map;
      X, Y    : Natural;
      DX, DY  : Step;
      Most    : Walk_Length;
      A, B, C : out Run_Length;
      OK      : out Boolean)
   is
      type Count_Array is array (0 .. 2) of Run_Length;

      Counts : Count_Array := [others => 0];
      State  : Natural range 0 .. 2 := 0;
      PX     : Integer := X;
      PY     : Integer := Y;
   begin
      loop
         pragma Loop_Invariant
           (PX in 0 .. Map'Last (2) and then PY in 0 .. Map'Last (1)
            and then (for all I in Counts'Range =>
                        Counts (I) <= Most + 1));
         pragma Loop_Variant
           (Increases => Counts (0) + Counts (1) + Counts (2));
         PX := PX + DX;
         PY := PY + DY;
         exit when PX not in 0 .. Map'Last (2)
           or else PY not in 0 .. Map'Last (1);
         if (Map (PY, PX) /= DA.Light) /= (State /= 1) then
            exit when State = 2;
            State := State + 1;
         end if;
         exit when Counts (State) > Most;
         Counts (State) := Counts (State) + 1;
      end loop;
      A := Counts (0);
      B := Counts (1);
      C := Counts (2);
      OK := A <= Most and then B in 1 .. Most and then C in 1 .. Most;
   end Walk;

   procedure Cross_Check
     (Map     : DA.Mark_Map;
      X, Y    : Natural;
      Along   : Boolean;
      Most    : Walk_Length;
      Width   : Int64;
      Place   : out Natural;
      Twice   : out Natural;
      Sum     : out Int64;
      OK      : out Boolean)
   with Pre  => DA.Valid_Map (Map)
                and then X <= Map'Last (2) and then Y <= Map'Last (1)
                and then Width in 0 .. 2 ** 32,
        Post => Twice <= 2 ** 28 and then Sum in 0 .. 2 ** 29
                and then (if OK
                          then Place <= (if Along then Map'Last (2)
                                         else Map'Last (1)));
   --  The five runs through the pixel (X, Y) of the middle of a
   --  pattern, along its row (Along) or its column. Place: the pixel in
   --  the middle of the third run, along that line; Twice: twice the
   --  coordinate of that middle; Sum: the five runs together. Not OK:
   --  the runs are not those of a pattern, or not Alike Width.

   procedure Cross_Check
     (Map     : DA.Mark_Map;
      X, Y    : Natural;
      Along   : Boolean;
      Most    : Walk_Length;
      Width   : Int64;
      Place   : out Natural;
      Twice   : out Natural;
      Sum     : out Int64;
      OK      : out Boolean)
   is
      DX     : constant Step := (if Along then 1 else 0);
      DY     : constant Step := 1 - DX;
      Start  : constant Natural := (if Along then X else Y);
      Last   : constant Natural :=
        (if Along then Map'Last (2) else Map'Last (1));
      A1, B1 : Run_Length;
      C1, A2 : Run_Length;
      B2, C2 : Run_Length;
      OK_1   : Boolean;
      OK_2   : Boolean;
      Runs   : Run_Array;
      First  : Integer;
   begin
      Walk (Map, X, Y, -DX, -DY, Most, A1, B1, C1, OK_1);
      Walk (Map, X, Y, DX, DY, Most, A2, B2, C2, OK_2);
      Runs := [C1, B1, A1 + 1 + A2, B2, C2];
      Sum := Total (Runs);
      First := Start - A1;
      Place := 0;
      Twice := 0;
      OK := OK_1 and then OK_2 and then In_Proportion (Runs)
        and then Alike (Sum, Width)
        and then First >= 0
        and then First + (A1 + A2) / 2 <= Last;
      --  The last two conditions always hold: the pixels of the third
      --  run are pixels of the map.
      if OK then
         Place := First + (A1 + A2) / 2;
         Twice := 2 * First + A1 + 1 + A2;
      end if;
   end Cross_Check;

   function Slanted
     (Map   : DA.Mark_Map;
      X, Y  : Natural;
      DY    : Step;
      Most  : Walk_Length;
      Width : Int64) return Boolean
   with Pre => DA.Valid_Map (Map)
               and then X <= Map'Last (2) and then Y <= Map'Last (1)
               and then Width in 0 .. 2 ** 32;
   --  The pixels through the pixel (X, Y) of the middle of a pattern
   --  along the diagonal (1, DY) are five runs of a pattern too, and
   --  as many together as a pattern Width pixels wide along its row
   --  has along a diagonal: from half as many (the pattern turned by
   --  half a right angle) to as many (upright), within two fifths.

   function Slanted
     (Map   : DA.Mark_Map;
      X, Y  : Natural;
      DY    : Step;
      Most  : Walk_Length;
      Width : Int64) return Boolean
   is
      A1, B1 : Run_Length;
      C1, A2 : Run_Length;
      B2, C2 : Run_Length;
      OK_1   : Boolean;
      OK_2   : Boolean;
      Runs   : Run_Array;
   begin
      Walk (Map, X, Y, -1, -DY, Most, A1, B1, C1, OK_1);
      Walk (Map, X, Y, 1, DY, Most, A2, B2, C2, OK_2);
      Runs := [C1, B1, A1 + 1 + A2, B2, C2];
      return OK_1 and then OK_2 and then In_Proportion (Runs)
        and then 10 * Total (Runs) >= 3 * Width
        and then 5 * Total (Runs) <= 7 * Width;
   end Slanted;

   ---------------------------------------------------------------------
   --  The patterns of a map
   ---------------------------------------------------------------------

   function Mean
     (Old   : VW.Coordinate;
      Seen  : Positive;
      Value : VW.Coordinate) return VW.Coordinate
   with Pre => Seen <= Max_Seen;
   --  The mean of Seen values, whose mean is Old, and of Value.

   function Mean
     (Old   : VW.Coordinate;
      Seen  : Positive;
      Value : VW.Coordinate) return VW.Coordinate
   is
      Count : constant Long_Float := Long_Float (Seen);
   begin
      return VW.Quotient
        (N.Mul_Within (Old, Count, VW.Limit, 2.0 ** 20) + Value,
         Count + 1.0, VW.Limit);
   end Mean;

   procedure Purge
     (Patterns : in out Pattern_Array;
      Count    : in out Natural;
      Row      : Long_Float)
   with Pre  => Patterns'First = 1 and then Count <= Patterns'Length,
        Post => Count <= Count'Old;
   --  Takes away the patterns found in one row only that the row Row
   --  is past: those whose middle is more than three of their modules
   --  and a pixel above it (no row so far below finds an even pattern
   --  again). The others keep their order.

   procedure Purge
     (Patterns : in out Pattern_Array;
      Count    : in out Natural;
      Row      : Long_Float)
   is
      Kept : Natural := 0;
      P    : Pattern;
   begin
      for I in 1 .. Count loop
         pragma Loop_Invariant (Kept < I);
         P := Patterns (I);
         if P.Seen >= 2 or else P.Centre.Y + 3.0 * P.Module + 1.0 >= Row
         then
            Kept := Kept + 1;
            Patterns (Kept) := P;
         end if;
      end loop;
      Count := Kept;
   end Purge;

   procedure Add
     (Patterns : in out Pattern_Array;
      Count    : in out Natural;
      X, Y     : VW.Coordinate;
      Module   : Module_Size;
      Row      : Natural)
   with Pre  => Patterns'First = 1 and then Count <= Patterns'Length,
        Post => Count <= Patterns'Length;
   --  A pattern found at (X, Y) in the row Row: one of
   --  Patterns (1 .. Count) seen once more, or a new one where there is
   --  room, or where there is after the patterns found once that the
   --  row is past are taken away.

   procedure Add
     (Patterns : in out Pattern_Array;
      Count    : in out Natural;
      X, Y     : VW.Coordinate;
      Module   : Module_Size;
      Row      : Natural)
   is
      P     : Pattern;
      Apart : Long_Float;
   begin
      for I in 1 .. Count loop
         P := Patterns (I);
         Apart := abs (Module - P.Module);
         if abs (X - P.Centre.X) <= P.Module
           and then abs (Y - P.Centre.Y) <= P.Module
           and then (Apart <= 1.0 or else Apart <= P.Module)
         then
            if P.Seen in 1 .. Max_Seen - 1 then
               Patterns (I) :=
                 (Centre => (X => Mean (P.Centre.X, P.Seen, X),
                             Y => Mean (P.Centre.Y, P.Seen, Y)),
                  Module =>
                    Long_Float'Max
                      (0.0, Mean (P.Module, P.Seen, Module)),
                  Seen   => P.Seen + 1);
            end if;
            return;
         end if;
      end loop;
      if Count = Patterns'Length then
         Purge (Patterns, Count, Long_Float (Row));
      end if;
      if Count < Patterns'Length then
         Count := Count + 1;
         Patterns (Count) :=
           (Centre => (X => X, Y => Y), Module => Module, Seen => 1);
      end if;
   end Add;

   Max_Reach : constant := 2 ** 12;
   --  The pixels of a row of the middle of a pattern, and its rows on
   --  one side of the middle one, as far as they are followed.

   subtype Reach_Length is Positive range 1 .. Max_Reach;

   function Dark_Beside
     (Map   : DA.Mark_Map;
      X, Y  : Natural;
      DX    : Step;
      Reach : Reach_Length) return Natural
   with Pre  => DA.Valid_Map (Map)
                and then X <= Map'Last (2) and then Y <= Map'Last (1)
                and then DX /= 0,
        Post => Dark_Beside'Result <= Reach
                and then (if DX = 1
                          then Dark_Beside'Result <= Map'Last (2) - X
                          else Dark_Beside'Result <= X);
   --  The dark pixels that follow the pixel (X, Y) in its row, after
   --  it (DX = 1) or before it, as far as Reach of them.

   function Dark_Beside
     (Map   : DA.Mark_Map;
      X, Y  : Natural;
      DX    : Step;
      Reach : Reach_Length) return Natural
   is
      Count : Natural := 0;
   begin
      for K in 1 .. Reach loop
         pragma Loop_Invariant
           (Count = K - 1
            and then (if DX = 1 then Count <= Map'Last (2) - X
                      else Count <= X));
         exit when (if DX = 1 then K > Map'Last (2) - X else K > X)
           or else Map (Y, X + DX * K) = DA.Light;
         Count := K;
      end loop;
      return Count;
   end Dark_Beside;

   function Weighted
     (Length : Reach_Length;
      Twice  : Natural) return Int64
   is (Int64 (Length) * Int64 (Twice))
   with Pre  => Twice <= 2 ** 28,
        Post => Weighted'Result in 0 .. 2 ** 40;
   --  Twice the coordinate of the middle of a row of Length pixels,
   --  for every pixel of the row.

   procedure Rows_Of
     (Map    : DA.Mark_Map;
      X0, Y0 : Natural;
      Down   : Boolean;
      Reach  : Reach_Length;
      Area   : out Int64;
      Sum_X  : out Int64;
      Sum_Y  : out Int64;
      OK     : out Boolean)
   with Pre  => DA.Valid_Map (Map)
                and then X0 <= Map'Last (2) and then Y0 <= Map'Last (1),
        Post => Area in 0 .. 2 ** 24 and then Sum_X in 0 .. 2 ** 52
                and then Sum_Y in 0 .. 2 ** 52;
   --  The rows of dark pixels of the middle of a pattern from the row
   --  Y0 on downwards (Down) or from the row before it on upwards: the
   --  first through the column X0, each of the others through the
   --  middle of the one before it, to the first that has a light pixel
   --  there or to the edge of the map. Area: their pixels; Sum_X and
   --  Sum_Y: twice the coordinates of the middles of the pixels,
   --  together. Not OK: a row of more than Reach pixels, or Reach rows
   --  or more.

   procedure Rows_Of
     (Map    : DA.Mark_Map;
      X0, Y0 : Natural;
      Down   : Boolean;
      Reach  : Reach_Length;
      Area   : out Int64;
      Sum_X  : out Int64;
      Sum_Y  : out Int64;
      OK     : out Boolean)
   is
      X      : Natural := X0;
      Y      : Natural;
      Left   : Natural;
      Right  : Natural;
      Length : Reach_Length;
   begin
      Area := 0;
      Sum_X := 0;
      Sum_Y := 0;
      OK := False;
      for K in 0 .. Reach - 1 loop
         pragma Loop_Invariant
           (X <= Map'Last (2) and then not OK
            and then Area in 0 .. Int64 (K) * Max_Reach
            and then Sum_X in 0 .. Int64 (K) * 2 ** 40
            and then Sum_Y in 0 .. Int64 (K) * 2 ** 40);
         if (if Down then K > Map'Last (1) - Y0 else K >= Y0) then
            OK := True;
            exit;
         end if;
         Y := (if Down then Y0 + K else Y0 - 1 - K);
         if Map (Y, X) = DA.Light then
            OK := True;
            exit;
         end if;
         Left := Dark_Beside (Map, X, Y, -1, Reach);
         Right := Dark_Beside (Map, X, Y, 1, Reach);
         exit when Left + Right >= Reach;
         Length := Left + 1 + Right;
         Area := Area + Int64 (Length);
         Sum_X := Sum_X + Weighted (Length, 2 * X - Left + Right + 1);
         Sum_Y := Sum_Y + Weighted (Length, 2 * Y + 1);
         X := X - Left + (Left + Right) / 2;
      end loop;
   end Rows_Of;

   procedure Settle
     (Map : DA.Mark_Map;
      P   : in out Pattern)
   with Pre => DA.Valid_Map (Map);
   --  The middle of the pattern, put where the dark pixels of the
   --  three modules by three in its middle have theirs: the rows of
   --  dark pixels above and below the middle as it was found, each
   --  followed through the middle of the one before it. The pattern
   --  stays as it is where its modules have more than 1000 pixels,
   --  where the pixel of its middle is not dark, where a row has more
   --  than four modules and two pixels, or there are that many rows or
   --  more on one side (dark pixels that are not only those of the
   --  middle of a pattern), and where the pixels have their middle
   --  more than a module from the one found.

   procedure Settle
     (Map : DA.Mark_Map;
      P   : in out Pattern)
   is
      Reach      : Reach_Length;
      X0, Y0     : Natural;
      Left       : Natural;
      Right      : Natural;
      A1, A2     : Int64;
      X1, X2     : Int64;
      Y1, Y2     : Int64;
      OK_1, OK_2 : Boolean;
      CX, CY     : VW.Coordinate;
   begin
      if P.Module > 1000.0
        or else not VW.Dark_At (Map, P.Centre.X, P.Centre.Y)
      then
         return;
      end if;
      Reach := 2 + VW.Floor_Index (4.0 * P.Module, 4000);
      X0 := VW.Floor_Index (P.Centre.X, Map'Last (2));
      Y0 := VW.Floor_Index (P.Centre.Y, Map'Last (1));
      Left := Dark_Beside (Map, X0, Y0, -1, Reach);
      Right := Dark_Beside (Map, X0, Y0, 1, Reach);
      X0 := X0 - Left + (Left + Right) / 2;
      Rows_Of (Map, X0, Y0, True, Reach, A1, X1, Y1, OK_1);
      Rows_Of (Map, X0, Y0, False, Reach, A2, X2, Y2, OK_2);
      if OK_1 and then OK_2 and then A1 + A2 > 0 then
         CX := VW.Quotient
           (Long_Float (X1 + X2), Long_Float (2 * (A1 + A2)), VW.Limit);
         CY := VW.Quotient
           (Long_Float (Y1 + Y2), Long_Float (2 * (A1 + A2)), VW.Limit);
         if abs (CX - P.Centre.X) <= P.Module
           and then abs (CY - P.Centre.Y) <= P.Module
         then
            P.Centre := (X => CX, Y => CY);
         end if;
      end if;
   end Settle;

   procedure Find_Patterns
     (Map      : DA.Mark_Map;
      Patterns : in out Pattern_Array;
      Count    : out Natural)
   is
      Runs : Run_Array;
      Dark : Boolean;

      procedure Check (X_End, Y : Natural)
      with Pre => DA.Valid_Map (Map) and then Patterns'First = 1
                  and then X_End <= Map'Last (2) + 1
                  and then Y <= Map'Last (1)
                  and then Count <= Patterns'Length
                  and then Total (Runs) <= Int64 (X_End),
           Post => Count <= Patterns'Length;
      --  The five runs that end before the column X_End of the row Y.

      procedure Check (X_End, Y : Natural) is
         Width   : constant Int64 := Total (Runs);
         Most    : constant Walk_Length :=
           Natural'Min (Runs (3), DA.Max_Side);
         X       : Natural;
         Row     : Natural;
         Line    : Natural;
         Middle  : Natural;
         Twice_X : Natural;
         Twice_Y : Natural;
         Sum_X   : Int64;
         Sum_Y   : Int64;
         OK      : Boolean;
      begin
         if not In_Proportion (Runs) then
            return;
         end if;
         X := X_End - Runs (5) - Runs (4) - (Runs (3) + 1) / 2;
         Cross_Check
           (Map, X, Y, False, Most, Width, Row, Twice_Y, Sum_Y, OK);
         if not OK then
            return;
         end if;
         Line := Row;
         Cross_Check
           (Map, X, Line, True, Most, Width, Middle, Twice_X, Sum_X, OK);

         --  A pattern with narrow modules may have a row that is not
         --  in proportion: then the row after the middle one, or the
         --  one before it.
         if not OK and then Row < Map'Last (1)
           and then Map (Row + 1, X) /= DA.Light
         then
            Line := Row + 1;
            Cross_Check
              (Map, X, Line, True, Most, Width, Middle, Twice_X, Sum_X,
               OK);
         end if;
         if not OK and then Row > 0
           and then Map (Row - 1, X) /= DA.Light
         then
            Line := Row - 1;
            Cross_Check
              (Map, X, Line, True, Most, Width, Middle, Twice_X, Sum_X,
               OK);
         end if;

         --  The two diagonals through the middle show the pattern too.
         OK := OK and then Slanted (Map, Middle, Line, 1, Most, Sum_X)
           and then Slanted (Map, Middle, Line, -1, Most, Sum_X);
         if OK then
            --  Half of Twice_X and of Twice_Y, and a fourteenth of
            --  the pixels of the row and of the column together (two
            --  patterns of seven modules); the bounds never act.
            Add (Patterns, Count,
                 VW.Quotient (Long_Float (Twice_X), 2.0, VW.Limit),
                 VW.Quotient (Long_Float (Twice_Y), 2.0, VW.Limit),
                 VW.Quotient (Long_Float (Sum_X + Sum_Y), 14.0, VW.Limit),
                 Y);
         end if;
      end Check;
   begin
      Count := 0;
      for Y in 0 .. Map'Last (1) loop
         pragma Loop_Invariant (Count <= Patterns'Length);
         Runs := [others => 0];
         Dark := False;
         for X in 0 .. Map'Last (2) loop
            pragma Loop_Invariant
              (Count <= Patterns'Length
               and then Total (Runs) <= Int64 (X));
            if (Map (Y, X) /= DA.Light) = Dark then
               Runs (5) := Runs (5) + 1;
            else
               if Dark then
                  Check (X, Y);
               end if;
               Runs := [Runs (2), Runs (3), Runs (4), Runs (5), 1];
               Dark := not Dark;
            end if;
         end loop;
         if Dark then
            Check (Map'Length (2), Y);
         end if;
      end loop;

      --  The patterns found in two rows or more, each where the pixels
      --  of its middle have theirs.
      Purge (Patterns, Count, 2.0 ** 40);
      for I in 1 .. Count loop
         pragma Loop_Invariant (Count <= Patterns'Length);
         Settle (Map, Patterns (I));
      end loop;
   end Find_Patterns;

   ---------------------------------------------------------------------
   --  Three patterns
   ---------------------------------------------------------------------

   Min_Arm : constant := 10.0;
   --  The shortest way from one finder pattern to the next, in pixels.

   Min_Module : constant := 0.5;
   --  The narrowest module, in pixels.

   Most_Steps : constant := 2 ** 20;
   --  The steps of half a pixel for which the way across a pattern is
   --  followed, at most.

   subtype Unit is Long_Float range -1.0 .. 1.0;

   procedure Half_Way
     (Map    : DA.Mark_Map;
      From   : Corner;
      UX, UY : Unit;
      Steps  : Natural;
      Length : out Long_Float;
      OK     : out Boolean)
   with Pre  => DA.Valid_Map (Map) and then Steps <= Most_Steps,
        Post => Length in 0.0 .. 2.0 ** 19;
   --  The way from the middle of a pattern in the direction (UX, UY)
   --  to its edge: to the third change between dark and light, in
   --  steps of half a pixel. Not OK: no such change in Steps steps.

   procedure Half_Way
     (Map    : DA.Mark_Map;
      From   : Corner;
      UX, UY : Unit;
      Steps  : Natural;
      Length : out Long_Float;
      OK     : out Boolean)
   is
      Dark    : Boolean := True;
      Changes : Natural range 0 .. 3 := 0;
      T       : Long_Float;
   begin
      Length := 0.0;
      OK := False;
      for K in 1 .. Steps loop
         pragma Loop_Invariant (Changes < 3);
         T := 0.5 * Long_Float (K);
         if VW.Dark_At
              (Map,
               From.X + N.Times_Unit (T, UX),
               From.Y + N.Times_Unit (T, UY)) /= Dark
         then
            Dark := not Dark;
            Changes := Changes + 1;
            if Changes = 3 then
               Length := T - 0.25;
               OK := True;
               return;
            end if;
         end if;
      end loop;
   end Half_Way;

   procedure Module_Along
     (Map    : DA.Mark_Map;
      P      : Pattern;
      UX, UY : Unit;
      Width  : out Long_Float;
      OK     : out Boolean)
   with Pre  => DA.Valid_Map (Map),
        Post => Width in 0.0 .. 2.0 ** 18;
   --  The width of a module of the pattern along the direction
   --  (UX, UY): a seventh of the way across the pattern.

   procedure Module_Along
     (Map    : DA.Mark_Map;
      P      : Pattern;
      UX, UY : Unit;
      Width  : out Long_Float;
      OK     : out Boolean)
   is
      Steps : constant Natural :=
        Natural (Long_Float'Min (12.0 * P.Module + 4.0, 2.0 ** 20));
      Ahead : Long_Float;
      Back  : Long_Float;
      OK_1  : Boolean;
      OK_2  : Boolean;
   begin
      Half_Way (Map, P.Centre, UX, UY, Steps, Ahead, OK_1);
      Half_Way (Map, P.Centre, -UX, -UY, Steps, Back, OK_2);
      OK := OK_1 and then OK_2;
      Width := (if OK then (Ahead + Back) / 7.0 else 0.0);
   end Module_Along;

   procedure Arm
     (Map      : DA.Mark_Map;
      From, To : Pattern;
      Modules  : out Long_Float;
      Change   : out Farther;
      OK       : out Boolean)
   with Pre  => DA.Valid_Map (Map),
        Post => Modules in 0.0 .. 2.0 ** 32;
   --  The modules from the middle of a pattern to that of another, and
   --  how much farther the other is: the root of the widths of a
   --  module at the first by that at the other, less one (0.0 where
   --  one of the widths is not seen). Not OK: the two are nearer than
   --  Min_Arm, or the width of a module is not seen at either, or is
   --  below Min_Module.

   procedure Arm
     (Map      : DA.Mark_Map;
      From, To : Pattern;
      Modules  : out Long_Float;
      Change   : out Farther;
      OK       : out Boolean)
   is
      Length : constant VW.Length_Value :=
        VW.Distance (From.Centre, To.Centre);
      UX, UY : Unit;
      W1, W2 : Long_Float;
      OK_1   : Boolean;
      OK_2   : Boolean;
      Width  : Long_Float;
      Root   : Long_Float;
   begin
      Modules := 0.0;
      Change := 0.0;
      OK := False;
      if Length < Min_Arm then
         return;
      end if;
      UX := VW.Quotient (To.Centre.X - From.Centre.X, Length, 1.0);
      UY := VW.Quotient (To.Centre.Y - From.Centre.Y, Length, 1.0);
      Module_Along (Map, From, UX, UY, W1, OK_1);
      Module_Along (Map, To, UX, UY, W2, OK_2);
      if OK_1 and then OK_2 then
         Width := (W1 + W2) / 2.0;
         if W1 >= Min_Module and then W2 >= Min_Module then
            Root := EF.Sqrt (VW.Quotient (W1, W2, 4.0));
            Change := Long_Float'Max (-0.5, Long_Float'Min (1.0, Root - 1.0));
         end if;
      elsif OK_1 then
         Width := W1;
      elsif OK_2 then
         Width := W2;
      else
         return;
      end if;
      if Width >= Min_Module then
         Modules := VW.Quotient (Length, Width, 2.0 ** 32);
         OK := True;
      end if;
   end Arm;

   procedure Place
     (Map         : DA.Mark_Map;
      First       : Pattern;
      Second      : Pattern;
      Third       : Pattern;
      Symbol      : out Placement;
      Found       : out Boolean)
   is
      P0 : constant Corner := First.Centre;
      P1 : constant Corner := Second.Centre;
      P2 : constant Corner := Third.Centre;
      D1 : constant VW.Length_Value := VW.Distance (P0, P1);
      D2 : constant VW.Length_Value := VW.Distance (P0, P2);

      Dot : constant Long_Float :=
        N.Mul_Within (P1.X - P0.X, P2.X - P0.X, VW.Span, VW.Span)
        + N.Mul_Within (P1.Y - P0.Y, P2.Y - P0.Y, VW.Span, VW.Span);
      Turn : constant VW.Cross := VW.Off_Line (P0, P1, P2);

      Narrow : constant Module_Size :=
        Long_Float'Min
          (First.Module, Long_Float'Min (Second.Module, Third.Module));
      N1, N2  : Long_Float;
      F1, F2  : Farther;
      Mean    : Long_Float;
      Version : Version_Number;
      OK      : Boolean;
   begin
      Symbol := (others => <>);
      Found := False;
      if D1 < Min_Arm or else D2 < Min_Arm
        or else D1 > 2.0 * D2 or else D2 > 2.0 * D1
        or else abs Dot > 0.5 * N.Mul_Within (D1, D2, VW.Far, VW.Far)
        or else Turn = 0.0
        or else not Akin (First, Second) or else not Akin (First, Third)
        or else not Akin (Second, Third)
        or else D1 < 7.0 * Narrow or else D2 < 7.0 * Narrow
      then
         return;
      end if;
      Arm (Map, First, Second, N1, F1, OK);
      if not OK then
         return;
      end if;
      Arm (Map, First, Third, N2, F2, OK);
      if not OK then
         return;
      end if;

      --  The modules between the middles of two patterns: those of a
      --  side less seven, 14 for the version 1 and four more for every
      --  version after it.
      Mean := (N1 + N2) / 2.0;
      if Mean < 10.0 or else Mean > 176.0 then
         return;
      end if;
      Version :=
        Integer'Max
          (1,
           Integer'Min
             (Max_Version,
              Integer (Long_Float'Rounding ((Mean - 10.0) / 4.0))));
      if Turn > 0.0 then
         Symbol :=
           (Upper_Left  => P0,
            Upper_Right => P1,
            Lower_Left  => P2,
            Version     => Version,
            Across      => F1,
            Down        => F2);
      else
         Symbol :=
           (Upper_Left  => P0,
            Upper_Right => P2,
            Lower_Left  => P1,
            Version     => Version,
            Across      => F2,
            Down        => F1);
      end if;
      Found := True;
   end Place;

   ---------------------------------------------------------------------
   --  The modules
   ---------------------------------------------------------------------

   Fine : constant := 16;
   --  The steps of a module: the middle of the alignment pattern is
   --  taken from the odd steps.

   Coarse : constant := Fine / 4;
   --  The steps from one place where the alignment pattern is looked
   --  for to the next: a quarter of a module.

   Reach : constant := 8 * Fine;
   --  How far around the place where it is expected the alignment
   --  pattern is looked for, in such steps, at most.

   subtype Shift is Integer range -(Reach + Fine) .. Reach + Fine;

   subtype Template_Index is Integer range -2 .. 2;

   function Share
     (Steps : Integer;
      Size  : Side_Length) return VW.Spread
   with Pre => Steps in -2 ** 12 .. 2 ** 12;
   --  Steps / (Fine * (Size - 7)): the coordinate, in the plane of a
   --  symbol of Size modules a side, of the point Steps steps (of
   --  which a module has Fine) after the middle of the upper left
   --  finder pattern. The middles of the other two finder patterns
   --  are at 1.

   function Share
     (Steps : Integer;
      Size  : Side_Length) return VW.Spread is
   begin
      return VW.Quotient
        (Long_Float (Steps), Long_Float (Fine * (Size - 7)), 4.0);
   end Share;

   Most_Awry : constant := 2;
   --  The modules of an alignment pattern, of its 25, that may be
   --  other than they should: blur rounds the corners of its ring.

   subtype Awry_Count is Natural range 0 .. Most_Awry + 1;

   function Awry
     (Map   : DA.Mark_Map;
      M     : VW.Mapping;
      Size  : Side_Length;
      P, Q  : Shift;
      Allow : Awry_Count) return Awry_Count
   with Pre  => DA.Valid_Map (Map) and then Allow <= Most_Awry,
        Post => Awry'Result <= Allow + 1;
   --  How many of the 25 modules around the point P and Q steps to the
   --  right of and below the place of the alignment pattern are not
   --  dark and light as that pattern is (its middle and the ring two
   --  modules from it dark, the ring between them light). They are
   --  counted as far as Allow + 1: more than Allow are too many.

   function Awry
     (Map   : DA.Mark_Map;
      M     : VW.Mapping;
      Size  : Side_Length;
      P, Q  : Shift;
      Allow : Awry_Count) return Awry_Count
   is
      Home  : constant Positive := Fine * (Size - 10);
      Count : Awry_Count := 0;
   begin
      for J in Template_Index loop
         pragma Loop_Invariant (Count <= Allow);
         for I in Template_Index loop
            pragma Loop_Invariant (Count <= Allow);
            if VW.Dark_In
                 (Map, M,
                  Share (Home + P + Fine * I, Size),
                  Share (Home + Q + Fine * J, Size))
              /= (Integer'Max (abs I, abs J) /= 1)
            then
               Count := Count + 1;
               if Count > Allow then
                  return Count;
               end if;
            end if;
         end loop;
      end loop;
      return Count;
   end Awry;

   Most_Amiss : constant := 4;
   --  The modules of the three finder patterns, of the 42 looked at,
   --  that may be other than they should.

   function Patterns_Fit
     (Map  : DA.Mark_Map;
      M    : VW.Mapping;
      Size : Side_Length) return Boolean
   with Pre => DA.Valid_Map (Map);
   --  The three finder patterns are where the mapping puts them: of
   --  the seven modules across the middle of each and the seven down,
   --  Most_Amiss at most are not dark or light as those of a pattern.

   function Patterns_Fit
     (Map  : DA.Mark_Map;
      M    : VW.Mapping;
      Size : Side_Length) return Boolean
   is
      Arm   : constant Positive := Fine * (Size - 7);
      Amiss : Natural := 0;
   begin
      for Which in 0 .. 2 loop
         pragma Loop_Invariant (Amiss <= 14 * Which);
         declare
            P : constant Natural := (if Which = 1 then Arm else 0);
            Q : constant Natural := (if Which = 2 then Arm else 0);
         begin
            for K in -3 .. 3 loop
               pragma Loop_Invariant
                 (Amiss <= 14 * Which + 2 * (K + 3));
               if VW.Dark_In
                    (Map, M, Share (P + Fine * K, Size), Share (Q, Size))
                 /= (abs K /= 2)
               then
                  Amiss := Amiss + 1;
               end if;
               if VW.Dark_In
                    (Map, M, Share (P, Size), Share (Q + Fine * K, Size))
                 /= (abs K /= 2)
               then
                  Amiss := Amiss + 1;
               end if;
            end loop;
         end;
      end loop;
      return Amiss <= Most_Amiss;
   end Patterns_Fit;

   function Timed
     (Map  : DA.Mark_Map;
      M    : VW.Mapping;
      Size : Side_Length) return Boolean
   with Pre => DA.Valid_Map (Map);
   --  One of the two timing patterns at least is where the mapping
   --  puts it. Along the seventh row and along the seventh column of a
   --  symbol, from the corner module of one finder pattern to that of
   --  the next, dark and light change with every module: Size - 13
   --  times. Looked at a quarter of a module before and after the
   --  middle of every module, they change as many times here along one
   --  of the two, a quarter more or less (two, where a quarter is
   --  less). The other may be covered: its modules hold no data.

   function Timed
     (Map  : DA.Mark_Map;
      M    : VW.Mapping;
      Size : Side_Length) return Boolean
   is
      Due     : constant Positive := Size - 13;
      Slack   : constant Positive := Integer'Max (2, Due / 4);
      Line    : constant VW.Spread := Share (3 * Fine, Size);
      Along   : VW.Spread;
      Dark    : Boolean;
      Now     : Boolean;
      Changes : Natural;
   begin
      for Down in Boolean loop
         Changes := 0;
         Dark := True;
         for K in 0 .. 2 * Due + 1 loop
            pragma Loop_Invariant (Changes <= K);
            Along := Share (3 * Fine - Fine / 4 + K * (Fine / 2), Size);
            Now := (if Down then VW.Dark_In (Map, M, Line, Along)
                    else VW.Dark_In (Map, M, Along, Line));
            if Now /= Dark then
               Dark := Now;
               Changes := Changes + 1;
            end if;
         end loop;
         if abs (Changes - Due) <= Slack then
            return True;
         end if;
      end loop;
      return False;
   end Timed;

   Far_Shift : constant := 1.0 * (Reach + Fine);

   function Mean_Of
     (Sum   : Integer;
      Count : Positive) return Long_Float
   with Post => abs Mean_Of'Result <= Far_Shift;
   --  Sum / Count, as far as a shift goes.

   function Mean_Of
     (Sum   : Integer;
      Count : Positive) return Long_Float is
   begin
      return VW.Quotient (Long_Float (Sum), Long_Float (Count), Far_Shift);
   end Mean_Of;

   function Beside_Corner
     (Size : Side_Length;
      Mean : Long_Float) return VW.Spread
   with Pre => abs Mean <= Far_Shift;
   --  Where in the plane of the symbol, along a side, a middle lies
   --  that is Mean steps after the one where the alignment pattern is
   --  expected: the middle of the seventh module from the end.

   function Beside_Corner
     (Size : Side_Length;
      Mean : Long_Float) return VW.Spread is
   begin
      return VW.Quotient
        (Long_Float (Fine * (Size - 10)) + Mean,
         Long_Float (Fine * (Size - 7)), 4.0);
   end Beside_Corner;

   procedure Find_Alignment
     (Map   : DA.Mark_Map;
      M     : VW.Mapping;
      Size  : Side_Length;
      U, V  : out VW.Spread;
      Found : out Boolean)
   with Pre => DA.Valid_Map (Map);
   --  The middle of the alignment pattern nearest to the corner
   --  without a finder pattern, in the plane of the symbol.

   procedure Find_Alignment
     (Map   : DA.Mark_Map;
      M     : VW.Mapping;
      Size  : Side_Length;
      U, V  : out VW.Spread;
      Found : out Boolean)
   is
      Span   : constant := Reach / (2 * Coarse);
      Best_P : Integer range -Reach .. Reach := 0;
      Best_Q : Integer range -Reach .. Reach := 0;
      Fewest : Awry_Count := Most_Awry + 1;
      Least  : Natural := Natural'Last;
      Sum_P  : Integer := 0;
      Sum_Q  : Integer := 0;
      Count  : Natural := 0;
      P, Q   : Shift;
   begin
      U := 0.0;
      V := 0.0;
      Found := False;

      --  The place where the fewest modules are amiss, and of such
      --  places the one nearest to the expected one: four modules
      --  around it, and eight where the pattern is not whole there.
      for Round in 1 .. 2 loop
         for J in -(Round * Span) .. Round * Span loop
            for I in -(Round * Span) .. Round * Span loop
               declare
                  Far   : constant Natural := I * I + J * J;
                  Allow : constant Integer :=
                    (if Far < Least then Integer'Min (Fewest, Most_Awry)
                     else Fewest - 1);
                  --  A nearer place may have as many amiss, a farther
                  --  one must have fewer.
                  Amiss : Awry_Count;
               begin
                  if Allow >= 0 then
                     Amiss := Awry
                       (Map, M, Size, Coarse * I, Coarse * J, Allow);
                     if Amiss <= Allow then
                        Fewest := Amiss;
                        Least := Far;
                        Best_P := Coarse * I;
                        Best_Q := Coarse * J;
                     end if;
                  end if;
               end;
            end loop;
         end loop;
         exit when Fewest = 0;
      end loop;
      if Fewest > Most_Awry then
         return;
      end if;

      --  The mean of the places within a module of it, at the odd
      --  steps, where no more modules are amiss: those of a pattern
      --  that lies on the pixels exactly are as many on either side of
      --  its middle.
      for J in -Fine / 2 .. Fine / 2 - 1 loop
         pragma Loop_Invariant
           (Count <= Fine * (J + Fine / 2)
            and then abs Sum_P <= (Reach + Fine) * Count
            and then abs Sum_Q <= (Reach + Fine) * Count);
         Q := Best_Q + 2 * J + 1;
         for I in -Fine / 2 .. Fine / 2 - 1 loop
            pragma Loop_Invariant
              (Count <= Fine * (J + Fine / 2) + I + Fine / 2
               and then abs Sum_P <= (Reach + Fine) * Count
               and then abs Sum_Q <= (Reach + Fine) * Count);
            P := Best_P + 2 * I + 1;
            if Awry (Map, M, Size, P, Q, Fewest) <= Fewest then
               Count := Count + 1;
               Sum_P := Sum_P + P;
               Sum_Q := Sum_Q + Q;
            end if;
         end loop;
      end loop;
      if Count = 0 then
         Count := 1;
         Sum_P := Best_P;
         Sum_Q := Best_Q;
      end if;
      U := Beside_Corner (Size, Mean_Of (Sum_P, Count));
      V := Beside_Corner (Size, Mean_Of (Sum_Q, Count));
      Found := True;
   end Find_Alignment;

   Clear : constant := 0.05;
   --  From here on, a finder pattern is taken as clearly farther or
   --  nearer than the upper left one: the widths of a module at the
   --  two differ by a tenth.

   function Frame
     (Symbol : Placement;
      G, H   : Farther) return VW.Mapping
   is (G  => G,
       H  => H,
       A  => VW.Factor_Of (Symbol.Upper_Left.X, Symbol.Upper_Right.X, G),
       B  => VW.Factor_Of (Symbol.Upper_Left.X, Symbol.Lower_Left.X, H),
       D  => VW.Factor_Of (Symbol.Upper_Left.Y, Symbol.Upper_Right.Y, G),
       E  => VW.Factor_Of (Symbol.Upper_Left.Y, Symbol.Lower_Left.Y, H),
       X0 => Symbol.Upper_Left.X,
       Y0 => Symbol.Upper_Left.Y);
   --  The mapping that takes (0, 0), (1, 0) and (0, 1) to the middles
   --  of the three finder patterns, with the upper right one G and the
   --  lower left one H farther than the upper left one (both 0.0: no
   --  perspective).

   procedure Tilt
     (Symbol : Placement;
      Size   : Side_Length;
      Q      : Corner;
      M      : in out VW.Mapping)
   with Pre => Size >= 25;
   --  The perspective mapping that takes (0, 0), (1, 0) and (0, 1) to
   --  the middles of the three finder patterns and that of the
   --  alignment pattern to Q. M stays as it is where there is none.

   procedure Tilt
     (Symbol : Placement;
      Size   : Side_Length;
      Q      : Corner;
      M      : in out VW.Mapping)
   is
      P0 : constant Corner := Symbol.Upper_Left;
      P1 : constant Corner := Symbol.Upper_Right;
      P2 : constant Corner := Symbol.Lower_Left;

      Place : constant Long_Float :=
        VW.Quotient (Long_Float (Size - 10), Long_Float (Size - 7), 1.0);
      Back  : constant Long_Float :=
        VW.Quotient (Long_Float (Size - 7), Long_Float (Size - 10), 4.0);
      --  The coordinate of the alignment pattern in the plane of the
      --  symbol, and one by it.

      Rest : constant Unit := 1.0 - 2.0 * Place;

      E1X : constant VW.Offset := P1.X - Q.X;
      E1Y : constant VW.Offset := P1.Y - Q.Y;
      E2X : constant VW.Offset := P2.X - Q.X;
      E2Y : constant VW.Offset := P2.Y - Q.Y;

      RX : constant Long_Float :=
        Q.X - N.Times_Unit (P1.X + P2.X, Place) - N.Times_Unit (P0.X, Rest);
      RY : constant Long_Float :=
        Q.Y - N.Times_Unit (P1.Y + P2.Y, Place) - N.Times_Unit (P0.Y, Rest);

      Den : constant VW.Cross :=
        N.Mul_Within (E1X, E2Y, VW.Span, VW.Span)
        - N.Mul_Within (E2X, E1Y, VW.Span, VW.Span);

      G, H : VW.Tilt;
   begin
      if abs Den < 1.0E-9 then
         return;
      end if;
      G := VW.Quotient
        (N.Times_Small
           (N.Mul_Within (RX, E2Y, VW.Far, VW.Span)
            - N.Mul_Within (RY, E2X, VW.Far, VW.Span),
            Back),
         Den, VW.Tilt_Limit);
      H := VW.Quotient
        (N.Times_Small
           (N.Mul_Within (E1X, RY, VW.Span, VW.Far)
            - N.Mul_Within (E1Y, RX, VW.Span, VW.Far),
            Back),
         Den, VW.Tilt_Limit);
      M := (G  => G,
            H  => H,
            A  => VW.Factor_Of (P0.X, P1.X, G),
            B  => VW.Factor_Of (P0.X, P2.X, H),
            D  => VW.Factor_Of (P0.Y, P1.Y, G),
            E  => VW.Factor_Of (P0.Y, P2.Y, H),
            X0 => P0.X,
            Y0 => P0.Y);
   end Tilt;

   procedure Point
     (M    : VW.Mapping;
      U, V : VW.Spread;
      P    : out Corner;
      OK   : in out Boolean)
   with Global => null;
   --  The point to which the mapping takes (U, V). OK becomes False
   --  where the mapping gives none, or one farther than VW.Limit from
   --  an axis.

   procedure Point
     (M    : VW.Mapping;
      U, V : VW.Spread;
      P    : out Corner;
      OK   : in out Boolean)
   is
      X, Y  : Long_Float;
      Ahead : Boolean;
   begin
      VW.Project (M, U, V, X, Y, Ahead);
      if Ahead and then abs X <= VW.Limit and then abs Y <= VW.Limit then
         P := (X => X, Y => Y);
      else
         P := (others => <>);
         OK := False;
      end if;
   end Point;

   procedure Sample
     (Map      : DA.Mark_Map;
      Symbol   : Placement;
      Version  : Version_Number;
      Again    : Boolean;
      Grid     : out Module_Grid;
      Shape    : out Outline;
      Centre   : out Corner;
      OK       : out Boolean)
   is
      Size : constant Side_Length := Side (Version);

      Leaning : constant Boolean :=
        (abs Symbol.Across >= Clear or else abs Symbol.Down >= Clear)
        /= Again;
      --  The symbol is taken as leaning first.

      Straight : constant VW.Mapping := Frame (Symbol, 0.0, 0.0);
      Leant    : constant VW.Mapping :=
        Frame (Symbol, Symbol.Across, Symbol.Down);
      First    : constant VW.Mapping := (if Leaning then Leant else Straight);
      Second   : constant VW.Mapping := (if Leaning then Straight else Leant);
      Fits_1   : constant Boolean :=
        Patterns_Fit (Map, First, Size) and then Timed (Map, First, Size);
      Fits_2   : constant Boolean :=
        Patterns_Fit (Map, Second, Size) and then Timed (Map, Second, Size);
      M        : VW.Mapping := (if Fits_1 then First else Second);

      Low  : constant VW.Spread := Share (-(Fine * 7) / 2, Size);
      High : constant VW.Spread := Share (Fine * Size - (Fine * 7) / 2, Size);
      --  The coordinates of the sides of the symbol in its plane.

      U, V  : VW.Spread;
      Q     : Corner;
      Found : Boolean := False;
   begin
      Grid := [others => [others => False]];
      Shape := (others => <>);
      Centre := (others => <>);

      --  Nothing to sample where neither mapping has the finder
      --  patterns and the timing patterns, and nothing new where only
      --  one has them.
      OK := (if Again then Fits_1 and then Fits_2
             else Fits_1 or else Fits_2);
      if not OK then
         return;
      end if;

      if Version >= 2 then
         if Fits_1 then
            Find_Alignment (Map, First, Size, U, V, Found);
            if Found then
               Point (First, U, V, Q, Found);
            end if;
         end if;
         if not Found and then Fits_2 then
            Find_Alignment (Map, Second, Size, U, V, Found);
            if Found then
               Point (Second, U, V, Q, Found);
            end if;
         end if;
         if Found then
            Tilt (Symbol, Size, Q, M);
         end if;
      end if;

      for R in 0 .. Size - 1 loop
         V := Share (Fine * R - Fine * 3, Size);
         for C in 0 .. Size - 1 loop
            Grid (Module_Index (R), Module_Index (C)) :=
              VW.Dark_In (Map, M, Share (Fine * C - Fine * 3, Size), V);
         end loop;
      end loop;

      Point (M, Low, Low, Shape.Upper_Left, OK);
      Point (M, High, Low, Shape.Upper_Right, OK);
      Point (M, High, High, Shape.Lower_Right, OK);
      Point (M, Low, High, Shape.Lower_Left, OK);
      Point (M, 0.5, 0.5, Centre, OK);
   end Sample;

end AMV.Kernels.Code_Reader.QR_Code.Finder;
