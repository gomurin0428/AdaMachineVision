pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package body AMV.Kernels.Code_Reader.Linear with SPARK_Mode is

   subtype Digit is Natural range 0 .. 9;
   type Digit_Array is array (Positive range <>) of Digit;
   subtype Twelve_Digits is Digit_Array (1 .. 12);

   subtype Extent is Int64 range 0 .. Max_Position;
   --  A distance between two edges.

   function Padded (Item : Reading) return Boolean is
     (for all I in Item.Length + 1 .. Code_Text'Last =>
        Item.Text (I) = ASCII.NUL)
   with Ghost;
   --  The characters after the text are NUL.

   function Good
     (Item : Reading; Start : Positive; Last : Natural) return Boolean
   is
     (Is_Symbology (Item.Symbology)
      and then Item.Length >= 1
      and then Last >= 16
      and then Start <= Last - 16
      and then Item.Last_Edge in Start + 16 .. Last
      and then Padded (Item))
   with Ghost;
   --  What every decoder promises of a symbol it found from run Start.

   ---------------------------------------------------------------------
   --  Margins (light runs before and after a symbol), in modules
   ---------------------------------------------------------------------

   EAN_Margin       : constant := 3;
   UPC_E_End_Margin : constant := 6;
   --  The runs after the six digits of a UPC-E symbol are also those
   --  after the left half of an EAN-13 symbol whose next bar is one
   --  module wide; the space after that bar is at most four modules.
   Code_128_Margin  : constant := 4;

   ---------------------------------------------------------------------
   --  Measures
   ---------------------------------------------------------------------

   function Width
     (Edges : Position_Array; From, To : Natural) return Extent
   is
     (if Edges (To) > Edges (From)
      then Int64 (Edges (To)) - Int64 (Edges (From))
      else 0)
   with Pre => From in Edges'Range and then To in Edges'Range;
   --  The distance from edge From to edge To.

   function Modules
     (W, Total : Extent; Count : Positive) return Int64
   is
     (if Total = 0
      then 0
      else (2 * Int64 (Count) * W + Total) / (2 * Total))
   with
     Pre  => Count <= 128,
     Post => Modules'Result in 0 .. 2 ** 40;
   --  W in modules, to the nearest, where Count modules are Total wide.

   function Similar (S, Other : Extent) return Boolean is
     (3 * S <= 4 * Other and then 3 * Other <= 4 * S);
   --  Two characters of the same number of modules, one after the other.

   function Margin_OK
     (Edges   : Position_Array;
      Last    : Natural;
      Run     : Natural;
      Total   : Extent;
      Count   : Positive;
      Need    : Positive;
      Lenient : Boolean) return Boolean
   is
     (Total > 0
      and then
        (if Lenient and then (Run = 0 or else Run + 1 = Last)
         then Width (Edges, Run, Run + 1) * Int64 (Count) >= Total
         else Width (Edges, Run, Run + 1) * Int64 (Count)
                >= Int64 (Need) * Total))
   with
     Pre => Edges'First = 0 and then Last <= Edges'Last
            and then Run < Last and then Count <= 128 and then Need <= 64;
   --  Run Run is at least Need modules wide, where Count modules are
   --  Total wide. Lenient: one module is enough for the first and the
   --  last run of the segment.

   function Digit_Character (D : Digit) return Character is
     (Character'Val (Character'Pos ('0') + D));

   procedure Put_Digits (Item : in out Reading; D : Digit_Array)
   with
     Pre  => D'First = 1 and then D'Last in 1 .. Max_Text_Length,
     Post => Item.Symbology = Item.Symbology'Old
             and then Item.Last_Edge = Item.Last_Edge'Old
             and then Item.Length = D'Last
             and then Padded (Item)
   is
   begin
      Item.Text := No_Text;
      for I in D'Range loop
         Item.Text (I) := Digit_Character (D (I));
         pragma Loop_Invariant
           (for all J in I + 1 .. Code_Text'Last =>
              Item.Text (J) = ASCII.NUL);
         pragma Loop_Invariant
           (Item.Symbology = Item.Symbology'Loop_Entry
            and then Item.Last_Edge = Item.Last_Edge'Loop_Entry);
      end loop;
      Item.Length := D'Last;
   end Put_Digits;

   ---------------------------------------------------------------------
   --  EAN-13, UPC-A, EAN-8 and UPC-E
   ---------------------------------------------------------------------

   --  A digit has seven modules in four runs. The two distances between
   --  edges of the same kind (run 1 + run 2 and run 2 + run 3, in
   --  modules) tell the digits and their two sets apart, except four
   --  pairs that the width of runs 1 and 3 together decides. Set B is
   --  set A read backwards.
   --
   --  The distances between edges of the same kind do not change when
   --  the bars of a symbol are all wider or all narrower than they
   --  should be (ink spread, a bright exposure, bars printed thin), but
   --  the width of runs 1 and 3 does: half a module per bar is enough to
   --  take 1 for 7 and 2 for 8. The guards tell how much it is: their
   --  bars and spaces are one module each, so the difference of their
   --  mean widths is what a bar gained on a space, and the width of
   --  runs 1 and 3 is corrected by it.

   Gain_Scale : constant := 60;

   subtype Bar_Gain is Int64 range -2 ** 36 .. 2 ** 36;
   --  How much wider a bar of the symbol is than a space of the same
   --  number of modules, times Gain_Scale; negative when it is narrower.

   function Guard_OK
     (Edges : Position_Array;
      First : Natural;
      Runs  : Positive;
      Total : Extent;
      Count : Positive) return Boolean
   is
     (for all K in 0 .. Runs - 2 =>
        Modules (Width (Edges, First + K, First + K + 2), Total, Count) = 2)
   with
     Pre => Edges'First = 0 and then Runs in 2 .. 6
            and then Edges'Last >= Runs
            and then First <= Edges'Last - Runs and then Count <= 128;
   --  Runs runs of one module each, from run First on: every two
   --  neighbours together measure two modules.

   function Runs_Width
     (Edges : Position_Array;
      First : Natural;
      Count : Positive) return Int64
   with
     Pre  => Edges'First = 0 and then Count <= 3
             and then Edges'Last >= 2 * Count
             and then First <= Edges'Last - 2 * Count + 1,
     Post => Runs_Width'Result in 0 .. Int64 (Count) * Max_Position
   is
      Sum : Int64 := 0;
   begin
      for K in 0 .. Count - 1 loop
         Sum := Sum + Width (Edges, First + 2 * K, First + 2 * K + 1);
         pragma Loop_Invariant (Sum in 0 .. Int64 (K + 1) * Max_Position);
      end loop;
      return Sum;
   end Runs_Width;
   --  The widths of Count runs together: run First and every second run
   --  after it.

   function EAN_Gain
     (Edges  : Position_Array;
      Start  : Natural;
      Middle : Natural;
      Stop   : Natural) return Bar_Gain
   is
     (2 * (5 * (Runs_Width (Edges, Start, 2)
                + Runs_Width (Edges, Middle + 1, 2)
                + Runs_Width (Edges, Stop, 2))
           - 6 * (Runs_Width (Edges, Start + 1, 1)
                  + Runs_Width (Edges, Middle, 3)
                  + Runs_Width (Edges, Stop + 1, 1))))
   with
     Pre => Edges'First = 0 and then Edges'Last >= 6
            and then Start <= Edges'Last - 3
            and then Middle <= Edges'Last - 5
            and then Stop <= Edges'Last - 3;
   --  The bar gain of an EAN-13 or EAN-8 symbol, from its guards of
   --  three runs from run Start, five from run Middle and three from run
   --  Stop: six bars and five spaces.

   function UPC_E_Gain
     (Edges : Position_Array;
      Start : Natural;
      Stop  : Natural) return Bar_Gain
   is
     (3 * (4 * (Runs_Width (Edges, Start, 2)
                + Runs_Width (Edges, Stop + 1, 3))
           - 5 * (Runs_Width (Edges, Start + 1, 1)
                  + Runs_Width (Edges, Stop, 3))))
   with
     Pre => Edges'First = 0 and then Edges'Last >= 6
            and then Start <= Edges'Last - 3
            and then Stop <= Edges'Last - 6;
   --  The bar gain of a UPC-E symbol, from its guards of three runs from
   --  run Start and six from run Stop: five bars and four spaces.

   procedure Read_EAN_Digit
     (Edges  : Position_Array;
      First  : Natural;
      Total  : Extent;
      Count  : Positive;
      Adjust : Bar_Gain;
      Value  : out Digit;
      Set_B  : out Boolean;
      OK     : out Boolean)
   with
     Pre => Edges'First = 0 and then Edges'Last >= 4
            and then First <= Edges'Last - 4 and then Count <= 128
   is
      S   : constant Extent := Width (Edges, First, First + 4);
      E1  : constant Int64 :=
        Modules (Width (Edges, First, First + 2), S, 7);
      E2  : constant Int64 :=
        Modules (Width (Edges, First + 1, First + 3), S, 7);
      W13 : constant Int64 :=
        7 * (Gain_Scale
             * (Width (Edges, First, First + 1)
                + Width (Edges, First + 2, First + 3))
             + Adjust);
      --  The width of runs 1 and 3 together, as it would be with bars
      --  and spaces of their own widths, times 7 * Gain_Scale. Adjust:
      --  the bar gain of the symbol where runs 1 and 3 are spaces, and
      --  minus the bar gain where they are bars.
      M   : constant Int64 := Gain_Scale * S;
      --  A module of the digit, on the same scale.
   begin
      Value := 0;
      Set_B := False;
      OK := False;

      --  Seven modules of the symbol, give or take one.
      if S = 0
        or else Int64 (Count) * S < 6 * Total
        or else Int64 (Count) * S > 8 * Total
        or else E1 not in 2 .. 5
        or else E2 not in 2 .. 5
      then
         return;
      end if;

      OK := True;
      case E1 * 10 + E2 is
         when 22 => Value := 6;
         when 23 => Value := 0; Set_B := True;
         when 24 => Value := 4;
         when 25 => Value := 3; Set_B := True;
         when 32 => Value := 9; Set_B := True;
         when 33 => Value := (if W13 >= 3 * M then 2 else 8);
         when 34 => Value := (if W13 >= 4 * M then 7 else 1);
                    Set_B := True;
         when 35 => Value := 5;
         when 42 => Value := 9;
         when 43 => Value := (if W13 >= 4 * M then 8 else 2);
                    Set_B := True;
         when 44 => Value := (if W13 >= 3 * M then 1 else 7);
         when 45 => Value := 5; Set_B := True;
         when 52 => Value := 6; Set_B := True;
         when 53 => Value := 0;
         when 54 => Value := 4; Set_B := True;
         when 55 => Value := 3;
         when others => OK := False;
      end case;
   end Read_EAN_Digit;

   type Parity_Table is array (Digit) of Natural;
   --  The sets of six digits as a number: 32 for the first digit in set
   --  B, 16 for the second, and so on.

   EAN_13_First_Digit : constant Parity_Table :=
     [16#00#, 16#0B#, 16#0D#, 16#0E#, 16#13#,
      16#19#, 16#1C#, 16#15#, 16#16#, 16#1A#];

   UPC_E_System_0 : constant Parity_Table :=
     [16#38#, 16#34#, 16#32#, 16#31#, 16#2C#,
      16#26#, 16#23#, 16#2A#, 16#29#, 16#25#];
   --  Number system 0, by check digit; number system 1 has the sets of
   --  EAN_13_First_Digit.

   procedure Find_Parity
     (Table : Parity_Table; Parity : Natural;
      Value : out Digit; OK : out Boolean)
   is
   begin
      Value := 0;
      OK := False;
      for D in Digit loop
         if Table (D) = Parity then
            Value := D;
            OK := True;
            return;
         end if;
      end loop;
   end Find_Parity;

   function Weighted_Sum
     (D : Digit_Array; Odd_Weight, Even_Weight : Positive) return Natural
   with
     Pre  => D'First = 1 and then D'Last in 0 .. 300
             and then Odd_Weight <= 3 and then Even_Weight <= 3,
     Post => Weighted_Sum'Result <= 27 * D'Last
   is
      Sum : Natural := 0;
   begin
      for I in D'Range loop
         Sum := Sum + D (I) * (if I mod 2 = 1 then Odd_Weight
                               else Even_Weight);
         pragma Loop_Invariant (Sum <= 27 * I);
      end loop;
      return Sum;
   end Weighted_Sum;
   --  The sum of the digits, those at odd places (1-based) times
   --  Odd_Weight and the others times Even_Weight.

   procedure Decode_EAN_13
     (Edges   : Position_Array;
      Last    : Natural;
      Start   : Positive;
      Options : Decode_Options;
      Found   : out Boolean;
      Item    : out Reading)
   with
     Pre  => Well_Formed (Edges, Last) and then Start < Last,
     Post => (if Found then Good (Item, Start, Last))
   is
      --  Guard (3 runs), six digits, guard (5), six digits, guard (3):
      --  59 runs and 95 modules.
      T      : Extent;
      Gain   : Bar_Gain;
      D      : Digit_Array (1 .. 13) := [others => 0];
      Parity : Natural := 0;
      Value  : Digit;
      Set_B  : Boolean;
      OK     : Boolean;
   begin
      Found := False;
      Item := No_Reading;
      if Last < 60 or else Start > Last - 60 then
         return;
      end if;

      T := Width (Edges, Start, Start + 59);
      if not Margin_OK (Edges, Last, Start - 1, T, 95, EAN_Margin, True)
        or else not Margin_OK
                      (Edges, Last, Start + 59, T, 95, EAN_Margin, True)
        or else not Guard_OK (Edges, Start, 3, T, 95)
        or else not Guard_OK (Edges, Start + 27, 5, T, 95)
        or else not Guard_OK (Edges, Start + 56, 3, T, 95)
      then
         return;
      end if;

      Gain := EAN_Gain (Edges, Start, Start + 27, Start + 56);

      for I in 0 .. 5 loop
         Read_EAN_Digit
           (Edges, Start + 3 + 4 * I, T, 95, Gain, Value, Set_B, OK);
         if not OK then
            return;
         end if;
         D (I + 2) := Value;
         Parity := 2 * Parity + (if Set_B then 1 else 0);
         pragma Loop_Invariant (Parity < 2 ** (I + 1));
      end loop;

      for I in 0 .. 5 loop
         Read_EAN_Digit
           (Edges, Start + 32 + 4 * I, T, 95, -Gain, Value, Set_B, OK);
         if not OK or else Set_B then
            return;
         end if;
         D (I + 8) := Value;
      end loop;

      Find_Parity (EAN_13_First_Digit, Parity, Value, OK);
      if not OK then
         return;
      end if;
      D (1) := Value;

      if Weighted_Sum (D, 1, 3) mod 10 /= 0 then
         return;
      end if;

      if D (1) = 0 and then Options.UPC_A then
         Item.Symbology := Symbology_UPC_A;
         Put_Digits (Item, Twelve_Digits (D (2 .. 13)));
      elsif Options.EAN_13 then
         Item.Symbology := Symbology_EAN_13;
         Put_Digits (Item, D);
      else
         return;
      end if;
      Item.Last_Edge := Start + 59;
      Found := True;
   end Decode_EAN_13;

   procedure Decode_EAN_8
     (Edges : Position_Array;
      Last  : Natural;
      Start : Positive;
      Found : out Boolean;
      Item  : out Reading)
   with
     Pre  => Well_Formed (Edges, Last) and then Start < Last,
     Post => (if Found then Good (Item, Start, Last))
   is
      --  Guard (3 runs), four digits, guard (5), four digits, guard (3):
      --  43 runs and 67 modules.
      T     : Extent;
      Gain  : Bar_Gain;
      D     : Digit_Array (1 .. 8) := [others => 0];
      Value : Digit;
      Set_B : Boolean;
      OK    : Boolean;
   begin
      Found := False;
      Item := No_Reading;
      if Last < 44 or else Start > Last - 44 then
         return;
      end if;

      T := Width (Edges, Start, Start + 43);
      if not Margin_OK (Edges, Last, Start - 1, T, 67, EAN_Margin, True)
        or else not Margin_OK
                      (Edges, Last, Start + 43, T, 67, EAN_Margin, True)
        or else not Guard_OK (Edges, Start, 3, T, 67)
        or else not Guard_OK (Edges, Start + 19, 5, T, 67)
        or else not Guard_OK (Edges, Start + 40, 3, T, 67)
      then
         return;
      end if;

      Gain := EAN_Gain (Edges, Start, Start + 19, Start + 40);

      for I in 0 .. 3 loop
         Read_EAN_Digit
           (Edges, Start + 3 + 4 * I, T, 67, Gain, Value, Set_B, OK);
         if not OK or else Set_B then
            return;
         end if;
         D (I + 1) := Value;
      end loop;

      for I in 0 .. 3 loop
         Read_EAN_Digit
           (Edges, Start + 24 + 4 * I, T, 67, -Gain, Value, Set_B, OK);
         if not OK or else Set_B then
            return;
         end if;
         D (I + 5) := Value;
      end loop;

      if Weighted_Sum (D, 3, 1) mod 10 /= 0 then
         return;
      end if;

      Item.Symbology := Symbology_EAN_8;
      Put_Digits (Item, D);
      Item.Last_Edge := Start + 43;
      Found := True;
   end Decode_EAN_8;

   procedure Decode_UPC_E
     (Edges : Position_Array;
      Last  : Natural;
      Start : Positive;
      Found : out Boolean;
      Item  : out Reading)
   with
     Pre  => Well_Formed (Edges, Last) and then Start < Last,
     Post => (if Found then Good (Item, Start, Last))
   is
      --  Guard (3 runs), six digits, guard (6): 33 runs and 51 modules.
      T      : Extent;
      D      : Digit_Array (1 .. 8) := [others => 0];
      --  The number system, the six digits and the check digit.
      A      : Digit_Array (1 .. 12) := [others => 0];
      --  The UPC-A number the symbol stands for.
      Parity : Natural := 0;
      Value  : Digit;
      Set_B  : Boolean;
      OK     : Boolean;
   begin
      Found := False;
      Item := No_Reading;
      if Last < 34 or else Start > Last - 34 then
         return;
      end if;

      T := Width (Edges, Start, Start + 33);
      if not Margin_OK (Edges, Last, Start - 1, T, 51, EAN_Margin, True)
        or else not Margin_OK
                      (Edges, Last, Start + 33, T, 51, UPC_E_End_Margin,
                       True)
        or else not Guard_OK (Edges, Start, 3, T, 51)
        or else not Guard_OK (Edges, Start + 27, 6, T, 51)
      then
         return;
      end if;

      for I in 0 .. 5 loop
         Read_EAN_Digit
           (Edges, Start + 3 + 4 * I, T, 51,
            UPC_E_Gain (Edges, Start, Start + 27), Value, Set_B, OK);
         if not OK then
            return;
         end if;
         D (I + 2) := Value;
         Parity := 2 * Parity + (if Set_B then 1 else 0);
         pragma Loop_Invariant (Parity < 2 ** (I + 1));
      end loop;

      Find_Parity (UPC_E_System_0, Parity, Value, OK);
      if OK then
         D (1) := 0;
      else
         Find_Parity (EAN_13_First_Digit, Parity, Value, OK);
         if not OK then
            return;
         end if;
         D (1) := 1;
      end if;
      D (8) := Value;

      --  The UPC-A number: where the zeros go depends on the last of the
      --  six digits.
      A (1) := D (1);
      A (2) := D (2);
      A (3) := D (3);
      case D (7) is
         when 0 .. 2 =>
            A (4) := D (7);
            A (9) := D (4);
            A (10) := D (5);
            A (11) := D (6);
         when 3 =>
            A (4) := D (4);
            A (10) := D (5);
            A (11) := D (6);
         when 4 =>
            A (4) := D (4);
            A (5) := D (5);
            A (11) := D (6);
         when 5 .. 9 =>
            A (4) := D (4);
            A (5) := D (5);
            A (6) := D (6);
            A (11) := D (7);
      end case;
      A (12) := D (8);

      if Weighted_Sum (A, 3, 1) mod 10 /= 0 then
         return;
      end if;

      Item.Symbology := Symbology_UPC_E;
      Put_Digits (Item, D);
      Item.Last_Edge := Start + 33;
      Found := True;
   end Decode_UPC_E;

   ---------------------------------------------------------------------
   --  Text
   ---------------------------------------------------------------------

   procedure Append
     (Item : in out Reading; Code : Natural; Fits : in out Boolean)
   with
     Pre  => Code <= 255,
     Post => Item.Symbology = Item.Symbology'Old
             and then Item.Last_Edge = Item.Last_Edge'Old
             and then Item.Length
                      = (if Item.Length'Old = Max_Text_Length
                         then Max_Text_Length
                         else Item.Length'Old + 1)
             and then Fits
                      = (Fits'Old
                         and then Item.Length'Old < Max_Text_Length)
             and then (if Padded (Item'Old) then Padded (Item))
   is
   begin
      if Item.Length = Max_Text_Length then
         Fits := False;
      else
         Item.Length := Item.Length + 1;
         Item.Text (Item.Length) := Character'Val (Code);
      end if;
   end Append;
   --  Adds the character with the code Code to the text; Fits becomes
   --  False when the text is full.

   ---------------------------------------------------------------------
   --  Code 128
   ---------------------------------------------------------------------

   --  A character has eleven modules in six runs, three bars and three
   --  spaces. The four distances between edges of the same kind, in
   --  modules, tell the characters apart; the three bars together must
   --  then measure the modules the character has in bars.

   subtype Code_128_Value is Natural range 0 .. 106;

   subtype Module_Count is Positive range 1 .. 4;
   type Run_Widths is array (1 .. 6) of Module_Count;
   type Code_128_Table is array (Code_128_Value) of Run_Widths;

   Code_128_Widths : constant Code_128_Table :=
     [[2, 1, 2, 2, 2, 2], [2, 2, 2, 1, 2, 2], [2, 2, 2, 2, 2, 1],
      [1, 2, 1, 2, 2, 3], [1, 2, 1, 3, 2, 2], [1, 3, 1, 2, 2, 2],
      [1, 2, 2, 2, 1, 3], [1, 2, 2, 3, 1, 2], [1, 3, 2, 2, 1, 2],
      [2, 2, 1, 2, 1, 3], [2, 2, 1, 3, 1, 2], [2, 3, 1, 2, 1, 2],
      [1, 1, 2, 2, 3, 2], [1, 2, 2, 1, 3, 2], [1, 2, 2, 2, 3, 1],
      [1, 1, 3, 2, 2, 2], [1, 2, 3, 1, 2, 2], [1, 2, 3, 2, 2, 1],
      [2, 2, 3, 2, 1, 1], [2, 2, 1, 1, 3, 2], [2, 2, 1, 2, 3, 1],
      [2, 1, 3, 2, 1, 2], [2, 2, 3, 1, 1, 2], [3, 1, 2, 1, 3, 1],
      [3, 1, 1, 2, 2, 2], [3, 2, 1, 1, 2, 2], [3, 2, 1, 2, 2, 1],
      [3, 1, 2, 2, 1, 2], [3, 2, 2, 1, 1, 2], [3, 2, 2, 2, 1, 1],
      [2, 1, 2, 1, 2, 3], [2, 1, 2, 3, 2, 1], [2, 3, 2, 1, 2, 1],
      [1, 1, 1, 3, 2, 3], [1, 3, 1, 1, 2, 3], [1, 3, 1, 3, 2, 1],
      [1, 1, 2, 3, 1, 3], [1, 3, 2, 1, 1, 3], [1, 3, 2, 3, 1, 1],
      [2, 1, 1, 3, 1, 3], [2, 3, 1, 1, 1, 3], [2, 3, 1, 3, 1, 1],
      [1, 1, 2, 1, 3, 3], [1, 1, 2, 3, 3, 1], [1, 3, 2, 1, 3, 1],
      [1, 1, 3, 1, 2, 3], [1, 1, 3, 3, 2, 1], [1, 3, 3, 1, 2, 1],
      [3, 1, 3, 1, 2, 1], [2, 1, 1, 3, 3, 1], [2, 3, 1, 1, 3, 1],
      [2, 1, 3, 1, 1, 3], [2, 1, 3, 3, 1, 1], [2, 1, 3, 1, 3, 1],
      [3, 1, 1, 1, 2, 3], [3, 1, 1, 3, 2, 1], [3, 3, 1, 1, 2, 1],
      [3, 1, 2, 1, 1, 3], [3, 1, 2, 3, 1, 1], [3, 3, 2, 1, 1, 1],
      [3, 1, 4, 1, 1, 1], [2, 2, 1, 4, 1, 1], [4, 3, 1, 1, 1, 1],
      [1, 1, 1, 2, 2, 4], [1, 1, 1, 4, 2, 2], [1, 2, 1, 1, 2, 4],
      [1, 2, 1, 4, 2, 1], [1, 4, 1, 1, 2, 2], [1, 4, 1, 2, 2, 1],
      [1, 1, 2, 2, 1, 4], [1, 1, 2, 4, 1, 2], [1, 2, 2, 1, 1, 4],
      [1, 2, 2, 4, 1, 1], [1, 4, 2, 1, 1, 2], [1, 4, 2, 2, 1, 1],
      [2, 4, 1, 2, 1, 1], [2, 2, 1, 1, 1, 4], [4, 1, 3, 1, 1, 1],
      [2, 4, 1, 1, 1, 2], [1, 3, 4, 1, 1, 1], [1, 1, 1, 2, 4, 2],
      [1, 2, 1, 1, 4, 2], [1, 2, 1, 2, 4, 1], [1, 1, 4, 2, 1, 2],
      [1, 2, 4, 1, 1, 2], [1, 2, 4, 2, 1, 1], [4, 1, 1, 2, 1, 2],
      [4, 2, 1, 1, 1, 2], [4, 2, 1, 2, 1, 1], [2, 1, 2, 1, 4, 1],
      [2, 1, 4, 1, 2, 1], [4, 1, 2, 1, 2, 1], [1, 1, 1, 1, 4, 3],
      [1, 1, 1, 3, 4, 1], [1, 3, 1, 1, 4, 1], [1, 1, 4, 1, 1, 3],
      [1, 1, 4, 3, 1, 1], [4, 1, 1, 1, 1, 3], [4, 1, 1, 3, 1, 1],
      [1, 1, 3, 1, 4, 1], [1, 1, 4, 1, 3, 1], [3, 1, 1, 1, 4, 1],
      [4, 1, 1, 1, 3, 1], [2, 1, 1, 4, 1, 2], [2, 1, 1, 2, 1, 4],
      [2, 1, 1, 2, 3, 2], [2, 3, 3, 1, 1, 1]];
   --  The runs of every character, in modules. 103, 104 and 105 start a
   --  symbol in code set A, B and C; 106 is the stop character, which
   --  has a seventh run, a bar of two modules.

   Code_128_Start_A : constant := 103;
   Code_128_Start_C : constant := 105;
   Code_128_Stop    : constant := 106;

   Max_Code_128_Characters : constant := 300;
   --  The most characters between the start and the stop characters. A
   --  text of Max_Text_Length characters takes fewer than that unless
   --  the symbol is mostly shifts.

   type Code_128_Values is
     array (1 .. Max_Code_128_Characters) of Code_128_Value;

   procedure Read_Code_128
     (Edges : Position_Array;
      First : Natural;
      S     : out Extent;
      Value : out Code_128_Value;
      OK    : out Boolean)
   with
     Pre => Edges'First = 0 and then Edges'Last >= 6
            and then First <= Edges'Last - 6
   is
      E    : array (1 .. 4) of Int64 := [others => 0];
      Bars : Int64;
   begin
      S := Width (Edges, First, First + 6);
      Value := 0;
      OK := False;
      if S = 0 then
         return;
      end if;

      for K in 1 .. 4 loop
         E (K) :=
           Modules (Width (Edges, First + K - 1, First + K + 1), S, 11);
         if E (K) not in 2 .. 7 then
            return;
         end if;
      end loop;

      Bars := Width (Edges, First, First + 1)
              + Width (Edges, First + 2, First + 3)
              + Width (Edges, First + 4, First + 5);

      for V in Code_128_Value loop
         declare
            W : Run_Widths renames Code_128_Widths (V);
         begin
            if Int64 (W (1) + W (2)) = E (1)
              and then Int64 (W (2) + W (3)) = E (2)
              and then Int64 (W (3) + W (4)) = E (3)
              and then Int64 (W (4) + W (5)) = E (4)
            then
               --  No other character has these distances.
               if 2 * abs (11 * Bars - Int64 (W (1) + W (3) + W (5)) * S)
                    < 3 * S
               then
                  Value := V;
                  OK := True;
               end if;
               return;
            end if;
         end;
      end loop;
   end Read_Code_128;
   --  The character whose first run is run First; S is its width.

   procedure Translate_Code_128
     (Values      : Code_128_Values;
      Count       : Natural;
      Start_Value : Code_128_Value;
      Item        : in out Reading;
      OK          : out Boolean)
   with
     Pre  => Count <= Max_Code_128_Characters,
     Post => Item.Symbology = Item.Symbology'Old
             and then Item.Last_Edge = Item.Last_Edge'Old
             and then Padded (Item)
             and then (if OK then Item.Length >= 1)
   is
      type Code_Set is (Set_A, Set_B, Set_C);

      Set        : Code_Set :=
        (if Start_Value = Code_128_Start_A then Set_A
         elsif Start_Value = Code_128_Start_C then Set_C
         else Set_B);
      Active     : Code_Set;
      Shift_Next : Boolean := False;
      --  SHIFT: the next character is of the other of the sets A and B.
      Upper      : Boolean := False;
      Upper_Once : Boolean := False;
      --  FNC4: the next character (once), or the characters from here on
      --  (twice), are 128 higher.
      Fits       : Boolean := True;
      V          : Code_128_Value;
      Code       : Natural;
   begin
      Item.Text := No_Text;
      Item.Length := 0;

      for I in 1 .. Count loop
         pragma Loop_Invariant
           (Item.Symbology = Item.Symbology'Loop_Entry
            and then Item.Last_Edge = Item.Last_Edge'Loop_Entry
            and then Padded (Item));
         V := Values (I);
         Active := Set;
         if Shift_Next and then Set /= Set_C then
            Active := (if Set = Set_A then Set_B else Set_A);
         end if;
         Shift_Next := False;

         if V = 102 then
            --  FNC1: in the first place it marks a GS1 symbol, later it
            --  separates fields.
            if I > 1 then
               Append (Item, 29, Fits);
            end if;

         elsif Active = Set_C then
            if V < 100 then
               Append (Item, Character'Pos ('0') + V / 10, Fits);
               Append (Item, Character'Pos ('0') + V mod 10, Fits);
            elsif V = 100 then
               Set := Set_B;
            elsif V = 101 then
               Set := Set_A;
            end if;

         elsif V < 96 then
            Code := (if Active = Set_B or else V < 64 then V + 32
                     else V - 64);
            if Upper /= Upper_Once then
               Code := Code + 128;
            end if;
            Upper_Once := False;
            Append (Item, Code, Fits);

         elsif V = 98 then
            Shift_Next := True;

         elsif V = 99 then
            Set := Set_C;

         elsif (V = 100 and then Active = Set_B)
           or else (V = 101 and then Active = Set_A)
         then
            --  FNC4.
            if Upper_Once then
               Upper := not Upper;
               Upper_Once := False;
            else
               Upper_Once := True;
            end if;

         elsif V = 100 then
            Set := Set_B;

         elsif V = 101 then
            Set := Set_A;

         end if;
         --  96 and 97 (FNC3 and FNC2) add nothing.
      end loop;

      OK := Fits and then Item.Length >= 1;
   end Translate_Code_128;
   --  The text of the Count data characters of a symbol.

   procedure Decode_Code_128
     (Edges : Position_Array;
      Last  : Natural;
      Start : Positive;
      Found : out Boolean;
      Item  : out Reading)
   with
     Pre  => Well_Formed (Edges, Last) and then Start < Last,
     Post => (if Found then Good (Item, Start, Last))
   is
      Values      : Code_128_Values := [others => 0];
      Count       : Natural := 0;
      E           : Natural;
      S           : Extent;
      S_Prev      : Extent;
      V           : Code_128_Value;
      Start_Value : Code_128_Value;
      OK          : Boolean;
      Sum         : Natural;
   begin
      Found := False;
      Item := No_Reading;

      --  The start character, a data character, the check character and
      --  the stop character with the run after it: 26 runs at least.
      if Last < 26 or else Start > Last - 26 then
         return;
      end if;

      Read_Code_128 (Edges, Start, S_Prev, Start_Value, OK);
      if not OK
        or else Start_Value not in Code_128_Start_A .. Code_128_Start_C
        or else not Margin_OK
                      (Edges, Last, Start - 1, S_Prev, 11, Code_128_Margin,
                       True)
      then
         return;
      end if;

      E := Start + 6;
      loop
         pragma Loop_Invariant (E in Start + 6 .. Last);
         pragma Loop_Invariant (Count <= Max_Code_128_Characters);
         pragma Loop_Invariant (E = Start + 6 + 6 * Count);
         pragma Loop_Variant (Increases => E);

         --  Room for the stop character and the run after it.
         if E > Last - 8 then
            return;
         end if;

         Read_Code_128 (Edges, E, S, V, OK);
         if not OK or else not Similar (S, S_Prev) then
            return;
         end if;
         exit when V = Code_128_Stop;

         if V >= Code_128_Start_A
           or else Count = Max_Code_128_Characters
         then
            return;
         end if;
         Count := Count + 1;
         Values (Count) := V;
         S_Prev := S;
         E := E + 6;
      end loop;

      --  The last bar of the stop character, which is as wide as its
      --  first bar (to half a module, whatever the ink spread), and the
      --  margin.
      if 22 * abs (Width (Edges, E + 6, E + 7) - Width (Edges, E, E + 1))
           >= S
        or else not Margin_OK
                      (Edges, Last, E + 7, S, 11, Code_128_Margin, True)
        or else Count < 2
      then
         return;
      end if;

      --  The last character is the check character.
      Sum := Start_Value;
      for I in 1 .. Count - 1 loop
         Sum := Sum + I * Values (I);
         pragma Loop_Invariant (Sum <= 106 + 106 * I * I);
      end loop;
      if Sum mod 103 /= Values (Count) then
         return;
      end if;

      Translate_Code_128 (Values, Count - 1, Start_Value, Item, OK);
      if not OK then
         Item := No_Reading;
         return;
      end if;
      Item.Symbology := Symbology_Code_128;
      Item.Last_Edge := E + 7;
      Found := True;
   end Decode_Code_128;

   ---------------------------------------------------------------------
   --  Code 39
   ---------------------------------------------------------------------

   --  A character has nine runs, five bars and four spaces, of which
   --  three are wide; a narrow space separates the characters. With wide
   --  runs of two to three modules a character is 12 to 15 modules wide,
   --  so a run wider than an eighth of the character is a wide one.

   subtype Code_39_Index is Positive range 1 .. 44;

   Code_39_Characters : constant String (Code_39_Index) :=
     "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%*";
   --  The 43 characters in the order of their values (the value is the
   --  index less one), and the start and stop character.

   Code_39_Star : constant Code_39_Index := 44;

   type Code_39_Table is array (Code_39_Index) of Natural;

   Code_39_Patterns : constant Code_39_Table :=
     [16#034#, 16#121#, 16#061#, 16#160#, 16#031#,
      16#130#, 16#070#, 16#025#, 16#124#, 16#064#,
      16#109#, 16#049#, 16#148#, 16#019#, 16#118#,
      16#058#, 16#00D#, 16#10C#, 16#04C#, 16#01C#,
      16#103#, 16#043#, 16#142#, 16#013#, 16#112#,
      16#052#, 16#007#, 16#106#, 16#046#, 16#016#,
      16#181#, 16#0C1#, 16#1C0#, 16#091#, 16#190#,
      16#0D0#, 16#085#, 16#184#, 16#0C4#, 16#0A8#,
      16#0A2#, 16#08A#, 16#02A#, 16#094#];
   --  The wide runs of every character: 256 for the first run (a bar),
   --  128 for the second, and so on to 1 for the ninth.

   Code_39_Margin : constant := 4;
   --  In twelfths of a character.

   procedure Read_Code_39
     (Edges : Position_Array;
      First : Natural;
      S     : out Extent;
      Index : out Code_39_Index;
      OK    : out Boolean)
   with
     Pre => Edges'First = 0 and then Edges'Last >= 9
            and then First <= Edges'Last - 9
   is
      Pattern : Natural := 0;
   begin
      S := Width (Edges, First, First + 9);
      Index := 1;
      OK := False;
      if S = 0 then
         return;
      end if;

      for K in 0 .. 8 loop
         Pattern :=
           2 * Pattern
           + (if 8 * Width (Edges, First + K, First + K + 1) > S then 1
              else 0);
         pragma Loop_Invariant (Pattern < 2 ** (K + 1));
      end loop;

      for I in Code_39_Index loop
         if Code_39_Patterns (I) = Pattern then
            Index := I;
            OK := True;
            return;
         end if;
      end loop;
   end Read_Code_39;
   --  The character whose first run is run First; S is its width.

   procedure Decode_Code_39
     (Edges   : Position_Array;
      Last    : Natural;
      Start   : Positive;
      Options : Decode_Options;
      Found   : out Boolean;
      Item    : out Reading)
   with
     Pre  => Well_Formed (Edges, Last) and then Start < Last,
     Post => (if Found then Good (Item, Start, Last))
   is
      E          : Natural;
      S          : Extent;
      S_Prev     : Extent;
      Index      : Code_39_Index;
      OK         : Boolean;
      Fits       : Boolean := True;
      Sum        : Natural := 0;
      Last_Value : Natural := 0;
   begin
      Found := False;
      Item := No_Reading;

      --  The start character, a data character and the stop character,
      --  the two runs between them and the run after: 30 runs at least.
      if Last < 30 or else Start > Last - 30 then
         return;
      end if;

      Read_Code_39 (Edges, Start, S_Prev, Index, OK);
      if not OK
        or else Index /= Code_39_Star
        or else not Margin_OK
                      (Edges, Last, Start - 1, S_Prev, 12, Code_39_Margin,
                       True)
      then
         return;
      end if;

      E := Start + 10;
      loop
         pragma Loop_Invariant (E in Start + 10 .. Last);
         pragma Loop_Invariant (Padded (Item));
         pragma Loop_Invariant (Sum <= 42 * Item.Length);
         pragma Loop_Invariant (Last_Value <= 42);
         pragma Loop_Variant (Increases => E);

         --  Room for a character and the run after it; the run before
         --  it is at most half a character.
         if E > Last - 10
           or else 2 * Width (Edges, E - 1, E) > S_Prev
         then
            return;
         end if;

         Read_Code_39 (Edges, E, S, Index, OK);
         if not OK or else not Similar (S, S_Prev) then
            return;
         end if;
         exit when Index = Code_39_Star;

         Append (Item, Character'Pos (Code_39_Characters (Index)), Fits);
         if not Fits then
            return;
         end if;
         Last_Value := Index - 1;
         Sum := Sum + Last_Value;
         S_Prev := S;
         E := E + 10;
      end loop;

      if not Margin_OK (Edges, Last, E + 9, S, 12, Code_39_Margin, True)
        or else Item.Length < 1
      then
         return;
      end if;

      --  The check character is the sum of the values of the others,
      --  modulo 43.
      if Options.Code_39_Check
        and then (Item.Length < 2
                  or else (Sum - Last_Value) mod 43 /= Last_Value)
      then
         return;
      end if;

      Item.Symbology := Symbology_Code_39;
      Item.Last_Edge := E + 9;
      Found := True;
   end Decode_Code_39;

   ---------------------------------------------------------------------
   --  Interleaved 2 of 5
   ---------------------------------------------------------------------

   --  Start: four narrow runs. Then pairs of digits in ten runs, the
   --  first digit in the five bars and the second in the five spaces;
   --  two of the five are wide. Stop: a wide bar, a narrow space and a
   --  narrow bar. With wide runs of two to three modules the five runs
   --  of a digit are 7 to 9 modules wide, so a run wider than 3/14 of
   --  them is a wide one.

   procedure Read_ITF_Digit
     (Edges : Position_Array;
      First : Natural;
      Value : out Digit;
      OK    : out Boolean)
   with
     Pre => Edges'First = 0 and then Edges'Last >= 9
            and then First <= Edges'Last - 9
   is
      Weights : constant array (0 .. 4) of Natural := [1, 2, 4, 7, 0];
      Total   : Int64 := 0;
      Wides   : Natural := 0;
      Code    : Natural := 0;
   begin
      for K in 0 .. 4 loop
         Total := Total + Width (Edges, First + 2 * K, First + 2 * K + 1);
         pragma Loop_Invariant
           (Total in 0 .. Int64 (K + 1) * Max_Position);
      end loop;

      for K in 0 .. 4 loop
         if 14 * Width (Edges, First + 2 * K, First + 2 * K + 1)
              > 3 * Total
         then
            Wides := Wides + 1;
            Code := Code + Weights (K);
         end if;
         pragma Loop_Invariant (Wides <= K + 1 and then Code <= 7 * Wides);
      end loop;

      --  Any two wide runs are a digit: 4 + 7 is the digit 0.
      OK := Total > 0 and then Wides = 2;
      Value := (if Code <= 9 then Code else 0);
   end Read_ITF_Digit;
   --  The digit in the runs First, First + 2, .. First + 8.

   function ITF_Narrow (W, Four : Extent) return Boolean is
     (8 * W >= Four and then 2 * W <= Four);
   --  A narrow run, where four narrow runs are about Four wide.

   function ITF_Stop_At
     (Edges : Position_Array; First : Natural; Four : Extent)
      return Boolean
   is
     (2 * Width (Edges, First, First + 1)
        >= 3 * Width (Edges, First + 2, First + 3)
      and then Width (Edges, First, First + 1) <= Four
      and then ITF_Narrow (Width (Edges, First + 1, First + 2), Four)
      and then ITF_Narrow (Width (Edges, First + 2, First + 3), Four)
      and then 2 * Width (Edges, First + 3, First + 4) >= 3 * Four)
   with
     Pre => Edges'First = 0 and then Edges'Last >= 4
            and then First <= Edges'Last - 4;
   --  The stop pattern and a margin of six narrow runs, from run First.

   Max_ITF_Digits : constant := 254;

   procedure Decode_ITF
     (Edges   : Position_Array;
      Last    : Natural;
      Start   : Positive;
      Options : Decode_Options;
      Found   : out Boolean;
      Item    : out Reading)
   with
     Pre  => Well_Formed (Edges, Last) and then Start < Last,
     Post => (if Found then Good (Item, Start, Last))
   is
      Four   : Extent;
      --  About four narrow runs.
      E      : Natural;
      P      : Extent;
      P_Prev : Extent := 0;
      D      : Digit_Array (1 .. Max_ITF_Digits) := [others => 0];
      Count  : Natural := 0;
      D1, D2 : Digit;
      OK     : Boolean;
      B1, B2 : Extent;
      S1, S2 : Extent;
   begin
      Found := False;
      Item := No_Reading;

      --  The start pattern, a pair, the stop pattern and the run after:
      --  18 runs at least.
      if Last < 18 or else Start > Last - 18 then
         return;
      end if;

      --  The start pattern: two narrow bars alike, two narrow spaces
      --  alike, and a margin of six narrow runs before them.
      Four := Width (Edges, Start, Start + 4);
      B1 := Width (Edges, Start, Start + 1);
      S1 := Width (Edges, Start + 1, Start + 2);
      B2 := Width (Edges, Start + 2, Start + 3);
      S2 := Width (Edges, Start + 3, Start + 4);
      if Four = 0
        or else not ITF_Narrow (B1, Four)
        or else not ITF_Narrow (S1, Four)
        or else not ITF_Narrow (B2, Four)
        or else not ITF_Narrow (S2, Four)
        or else 2 * B1 > 3 * B2 or else 2 * B2 > 3 * B1
        or else 2 * S1 > 3 * S2 or else 2 * S2 > 3 * S1
        or else 2 * Width (Edges, Start - 1, Start) < 3 * Four
      then
         return;
      end if;

      E := Start + 4;
      loop
         pragma Loop_Invariant (E in Start + 4 .. Last);
         pragma Loop_Invariant (Count <= Max_ITF_Digits);
         pragma Loop_Invariant (Count mod 2 = 0);
         pragma Loop_Invariant (E = Start + 4 + 5 * Count);
         pragma Loop_Variant (Increases => E);

         --  Room for the stop pattern and the run after it.
         if E > Last - 4 then
            return;
         end if;
         exit when Count > 0 and then ITF_Stop_At (Edges, E, Four);

         --  Room for a pair as well.
         if E > Last - 14 or else Count = Max_ITF_Digits then
            return;
         end if;

         --  A pair is 14 to 18 narrow runs wide.
         P := Width (Edges, E, E + 10);
         if Count = 0 then
            if 4 * P < 11 * Four or else 2 * P > 11 * Four then
               return;
            end if;
         elsif not Similar (P, P_Prev) then
            return;
         end if;

         Read_ITF_Digit (Edges, E, D1, OK);
         if not OK then
            return;
         end if;
         Read_ITF_Digit (Edges, E + 1, D2, OK);
         if not OK then
            return;
         end if;

         D (Count + 1) := D1;
         D (Count + 2) := D2;
         Count := Count + 2;
         P_Prev := P;
         Four := P / 4;
         E := E + 10;
      end loop;

      if Count < Options.ITF_Min_Digits then
         return;
      end if;

      --  The check digit: three times the digits at the odd places and
      --  the others add up to a multiple of ten.
      if Options.ITF_Check
        and then Weighted_Sum (Digit_Array'(D (1 .. Count)), 3, 1) mod 10
                   /= 0
      then
         return;
      end if;

      Item.Symbology := Symbology_ITF;
      Put_Digits (Item, Digit_Array'(D (1 .. Count)));
      Item.Last_Edge := E + 3;
      Found := True;
   end Decode_ITF;

   ---------------------------------------------------------------------
   --  Decode_At
   ---------------------------------------------------------------------

   procedure Decode_At
     (Edges   : Position_Array;
      Last    : Natural;
      Start   : Positive;
      Options : Decode_Options;
      Found   : out Boolean;
      Item    : out Reading)
   is
   begin
      Found := False;
      Item := No_Reading;

      if Options.Code_128 then
         Decode_Code_128 (Edges, Last, Start, Found, Item);
      end if;
      if not Found and then (Options.EAN_13 or else Options.UPC_A) then
         Decode_EAN_13 (Edges, Last, Start, Options, Found, Item);
      end if;
      if not Found and then Options.EAN_8 then
         Decode_EAN_8 (Edges, Last, Start, Found, Item);
      end if;
      if not Found and then Options.UPC_E then
         Decode_UPC_E (Edges, Last, Start, Found, Item);
      end if;
      if not Found and then Options.Code_39 then
         Decode_Code_39 (Edges, Last, Start, Options, Found, Item);
      end if;
      if not Found and then Options.ITF then
         Decode_ITF (Edges, Last, Start, Options, Found, Item);
      end if;

      if not Found then
         Item := No_Reading;
      end if;
   end Decode_At;

end AMV.Kernels.Code_Reader.Linear;
