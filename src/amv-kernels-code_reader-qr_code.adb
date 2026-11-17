pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package body AMV.Kernels.Code_Reader.QR_Code with SPARK_Mode is

   use type RS.Element;

   subtype Module_Number is Natural range 0 .. Max_Side - 1;
   --  A row or a column, for arithmetic.

   function Dark
     (Grid        : Module_Grid;
      Mirror      : Boolean;
      Row, Column : Module_Number) return Boolean
   is
     (if Mirror
      then Grid (Module_Index (Column), Module_Index (Row))
      else Grid (Module_Index (Row), Module_Index (Column)));
   --  The module of the symbol in the row Row and the column Column.

   ---------------------------------------------------------------------
   --  The patterns
   ---------------------------------------------------------------------

   procedure Fill
     (Map                : in out Module_Grid;
      Row_1, Row_2       : Module_Number;
      Column_1, Column_2 : Module_Number);
   --  Marks the rows Row_1 .. Row_2 of the columns Column_1 .. Column_2.

   procedure Fill
     (Map                : in out Module_Grid;
      Row_1, Row_2       : Module_Number;
      Column_1, Column_2 : Module_Number) is
   begin
      for R in Row_1 .. Row_2 loop
         for C in Column_1 .. Column_2 loop
            Map (Module_Index (R), Module_Index (C)) := True;
         end loop;
      end loop;
   end Fill;

   --------------------
   -- Mark_Functions --
   --------------------

   procedure Mark_Functions
     (Version : Version_Number;
      Map     : out Module_Grid)
   is
      S    : constant Side_Length := Side (Version);
      List : constant Centre_List := Centres (Version);
      Last : Centre_Value := 0;
      --  The last row and column with alignment patterns.
   begin
      Map := [others => [others => False]];

      --  The finder patterns, the light modules around them and the
      --  format information; the module that is always dark is among
      --  those of the lower left corner.
      Fill (Map, 0, 8, 0, 8);
      Fill (Map, 0, 8, S - 8, S - 1);
      Fill (Map, S - 8, S - 1, 0, 8);

      --  The timing patterns.
      Fill (Map, 6, 6, 0, S - 1);
      Fill (Map, 0, S - 1, 6, 6);

      --  The alignment patterns: where the rows and columns of the list
      --  cross, but not in the three corners with a finder pattern.
      for K in List'Range loop
         Last := Centre_Value'Max (Last, List (K));
      end loop;
      for I in List'Range loop
         for J in List'Range loop
            declare
               R : constant Centre_Value := List (I);
               C : constant Centre_Value := List (J);
            begin
               if R >= 6 and then C >= 6
                 and then not (R = 6 and then C = 6)
                 and then not (R = 6 and then C = Last)
                 and then not (R = Last and then C = 6)
               then
                  Fill (Map, R - 2, R + 2, C - 2, C + 2);
               end if;
            end;
         end loop;
      end loop;

      --  The version information.
      if Version >= 7 then
         Fill (Map, 0, 5, S - 11, S - 9);
         Fill (Map, S - 11, S - 9, 0, 5);
      end if;
   end Mark_Functions;

   ---------------------------------------------------------------------
   --  The format and the version information
   ---------------------------------------------------------------------

   subtype Bit_Total is Natural range 0 .. 18;

   function Ones (Word : Info_Bits) return Bit_Total;
   --  The bits of Word that are one.

   function Ones (Word : Info_Bits) return Bit_Total is
      V      : Info_Bits := Word;
      Result : Bit_Total := 0;
   begin
      for K in 1 .. 18 loop
         pragma Loop_Invariant (Result <= K - 1);
         if V mod 2 = 1 then
            Result := Result + 1;
         end if;
         V := V / 2;
      end loop;
      return Result;
   end Ones;

   procedure Push (Word : in out Info_Bits; Bit : Boolean);
   --  Bit as the next lower bit of Word.

   procedure Push (Word : in out Info_Bits; Bit : Boolean) is
   begin
      Word := Word * 2 + (if Bit then 1 else 0);
   end Push;

   ------------
   -- Masked --
   ------------

   function Masked
     (Mask        : Mask_Pattern;
      Row, Column : Module_Index) return Boolean
   is
      I : constant Module_Number := Module_Number (Row);
      J : constant Module_Number := Module_Number (Column);
   begin
      return
        (case Mask is
            when 0 => (I + J) mod 2 = 0,
            when 1 => I mod 2 = 0,
            when 2 => J mod 3 = 0,
            when 3 => (I + J) mod 3 = 0,
            when 4 => (I / 2 + J / 3) mod 2 = 0,
            when 5 => (I * J) mod 2 + (I * J) mod 3 = 0,
            when 6 => ((I * J) mod 2 + (I * J) mod 3) mod 2 = 0,
            when 7 => ((I + J) mod 2 + (I * J) mod 3) mod 2 = 0);
   end Masked;

   -----------------
   -- Read_Format --
   -----------------

   procedure Read_Format
     (Grid       : Module_Grid;
      Version    : Version_Number;
      Mirror     : Boolean;
      Level_Read : out Level;
      Mask       : out Mask_Pattern;
      OK         : out Boolean)
   is
      S     : constant Side_Length := Side (Version);
      A, B  : Info_Bits := 0;
      --  The two copies, from the bit 14 down to the bit 0.
      Diff  : Bit_Total;
      Best  : Bit_Total := Bit_Total'Last;
      Which : Natural range 0 .. 31 := 0;
   begin
      --  Around the upper left finder pattern: along the row 8 to the
      --  right, then up the column 8, without the timing patterns.
      for C in 0 .. 5 loop
         Push (A, Dark (Grid, Mirror, 8, C));
      end loop;
      Push (A, Dark (Grid, Mirror, 8, 7));
      Push (A, Dark (Grid, Mirror, 8, 8));
      Push (A, Dark (Grid, Mirror, 7, 8));
      for R in reverse 0 .. 5 loop
         Push (A, Dark (Grid, Mirror, R, 8));
      end loop;

      --  Up the column 8 beside the lower left finder pattern, then
      --  along the row 8 below the upper right one.
      for R in reverse S - 7 .. S - 1 loop
         Push (B, Dark (Grid, Mirror, R, 8));
      end loop;
      for C in S - 8 .. S - 1 loop
         Push (B, Dark (Grid, Mirror, 8, C));
      end loop;

      for D in Format_Words'Range loop
         Diff := Bit_Total'Min
           (Ones (A xor Format_Words (D)), Ones (B xor Format_Words (D)));
         if Diff < Best then
            Best := Diff;
            Which := D;
         end if;
      end loop;

      OK := Best <= 3;
      Level_Read :=
        (case Which / 8 is
            when 0      => M,
            when 1      => L,
            when 2      => H,
            when others => Q);
      Mask := Which mod 8;
   end Read_Format;

   function Version_Agrees
     (Grid    : Module_Grid;
      Version : Version_Number;
      Mirror  : Boolean) return Boolean
   with Pre => Version >= 7;
   --  Either copy of the version information differs from that of
   --  Version in three bits at most.

   function Version_Agrees
     (Grid    : Module_Grid;
      Version : Version_Number;
      Mirror  : Boolean) return Boolean
   is
      S    : constant Side_Length := Side (Version);
      Word : constant Info_Bits := Version_Words (Version);
      A, B : Info_Bits := 0;
      --  The copy beside the upper right finder pattern (six rows of
      --  three modules) and the one beside the lower left pattern (six
      --  columns of three), from the bit 17 down to the bit 0.
      Far  : Module_Number;
   begin
      for Bit in reverse 0 .. 17 loop
         Far := S - 11 + Bit mod 3;
         Push (A, Dark (Grid, Mirror, Bit / 3, Far));
         Push (B, Dark (Grid, Mirror, Far, Bit / 3));
      end loop;
      return Ones (A xor Word) <= 3 or else Ones (B xor Word) <= 3;
   end Version_Agrees;

   ---------------------------------------------------------------------
   --  The codewords
   ---------------------------------------------------------------------

   subtype Stream is Codeword_Array (Codeword_Index);

   procedure Read_Codewords
     (Grid      : Module_Grid;
      Version   : Version_Number;
      Mirror    : Boolean;
      Mask      : Mask_Pattern;
      Functions : Module_Grid;
      Words     : out Stream;
      OK        : out Boolean);
   --  The codewords of the symbol in the order of their places, without
   --  the mask. Functions: Mark_Functions (Version). OK: they are as
   --  many as the version has (true for every version; the tests check
   --  it).

   procedure Read_Codewords
     (Grid      : Module_Grid;
      Version   : Version_Number;
      Mirror    : Boolean;
      Mask      : Mask_Pattern;
      Functions : Module_Grid;
      Words     : out Stream;
      OK        : out Boolean)
   is
      S     : constant Side_Length := Side (Version);
      Total : constant Codeword_Total := Codewords (Version);

      Count  : Codeword_Count := 0;
      Over   : Boolean := False;
      V      : RS.Element := 0;
      Bits   : Natural range 0 .. 7 := 0;
      Right  : Module_Number;
      Row    : Module_Number;
      Column : Module_Number;
   begin
      Words := [others => 0];

      --  The pairs of columns from the right; the column 6 (a timing
      --  pattern) is in none of them.
      for Pair in 0 .. (S - 1) / 2 - 1 loop
         Right := S - 1 - 2 * Pair;
         if Right <= 6 then
            Right := Right - 1;
         end if;

         for K in 0 .. S - 1 loop
            --  Upwards in the first pair, downwards in the next one.
            Row := (if Pair mod 2 = 0 then S - 1 - K else K);
            for Left in Boolean loop
               Column := (if Left then Right - 1 else Right);
               if not Functions (Module_Index (Row), Module_Index (Column))
               then
                  V := V * 2;
                  if Dark (Grid, Mirror, Row, Column)
                    /= Masked
                         (Mask, Module_Index (Row), Module_Index (Column))
                  then
                     V := V + 1;
                  end if;
                  if Bits < 7 then
                     Bits := Bits + 1;
                  else
                     if Count < Total then
                        Count := Count + 1;
                        Words (Count) := V;
                     else
                        Over := True;
                     end if;
                     Bits := 0;
                     V := 0;
                  end if;
               end if;
            end loop;
         end loop;
      end loop;

      OK := Count = Total and then not Over;
   end Read_Codewords;

   Max_Corrected : constant := 126 * 15;
   --  A bound of the codewords that Correct_Blocks changes, from the
   --  ranges of Block_Info: the blocks, and half the check codewords of
   --  each.

   procedure Correct_Blocks
     (Info      : Block_Info;
      Limit     : Positive;
      Total     : Codeword_Total;
      Field     : RS.Field;
      Words     : Stream;
      Data      : out Stream;
      N_Data    : out Codeword_Count;
      Corrected : out Natural;
      Success   : out Boolean)
   with Post => Corrected <= Max_Corrected
                and then N_Data <= Max_Data
                and then (if Success then N_Data >= 1);
   --  Takes the blocks out of the codewords Words (1 .. Total), corrects
   --  each and gives the codewords of the message, block after block,
   --  in Data (1 .. N_Data). No Success: a block cannot be corrected, or
   --  only by changing more than Limit codewords.
   --
   --  With NB blocks, the codeword I (from 0) of the message of the block
   --  B (from 0) is at the place I * NB + B + 1, and the last one of a
   --  block of the second group, which the blocks of the first group do
   --  not have, at the place Data_1 * NB + (B - Blocks_1) + 1; the check
   --  codeword J of the block B is at the place D + J * NB + B + 1,
   --  after the D codewords of the message.

   procedure Correct_Blocks
     (Info      : Block_Info;
      Limit     : Positive;
      Total     : Codeword_Total;
      Field     : RS.Field;
      Words     : Stream;
      Data      : out Stream;
      N_Data    : out Codeword_Count;
      Corrected : out Natural;
      Success   : out Boolean)
   is
      NB     : constant Positive := Info.Blocks_1 + Info.Blocks_2;
      D      : constant Positive := Info.Data_1 * NB + Info.Blocks_2;
      --  The codewords of the message.

      Word   : RS.Word (RS.Word_Index) := [others => 0];
      N      : Natural;
      N_Own  : Natural;
      --  The codewords of the message of a block.
      P      : Natural;
      Offset : Natural;
      Long   : Boolean;
      Fixed  : Natural;
      Good   : Boolean;
   begin
      Data := [others => 0];
      N_Data := 0;
      Corrected := 0;
      Success := False;

      --  Cannot be for the tables of the symbology (the tests check
      --  every version and level): the blocks have as many codewords as
      --  the version, and those of the message are no more than
      --  Max_Data.
      if D + Info.Check * NB /= Total or else D > Max_Data then
         return;
      end if;

      for B in 0 .. NB - 1 loop
         pragma Loop_Invariant (Corrected <= B * 15);

         Long := B >= Info.Blocks_1;
         N := 0;
         for I in 0 .. Info.Data_1 - 1 loop
            pragma Loop_Invariant (N = I);
            P := I * NB + B + 1;
            --  Cannot be: a place of the block is a place of the
            --  symbol. So for the three tests of P below.
            if P > Total then
               Corrected := 0;
               return;
            end if;
            N := N + 1;
            Word (N) := Words (P);
         end loop;
         if Long then
            P := Info.Data_1 * NB + (B - Info.Blocks_1) + 1;
            if P > Total then
               Corrected := 0;
               return;
            end if;
            N := N + 1;
            Word (N) := Words (P);
         end if;
         N_Own := N;
         for J in 0 .. Info.Check - 1 loop
            pragma Loop_Invariant (N = N_Own + J);
            P := D + J * NB + B + 1;
            if P > Total then
               Corrected := 0;
               return;
            end if;
            N := N + 1;
            Word (N) := Words (P);
         end loop;

         RS.Correct (Field, Word (1 .. N), Info.Check, 0, Fixed, Good);
         if not Good or else Fixed > Limit then
            Corrected := 0;
            return;
         end if;

         --  Cannot be: the codewords of the message of the blocks
         --  before this one, and its own, are among the D of them.
         Offset := B * Info.Data_1 + (if Long then B - Info.Blocks_1 else 0);
         if Offset + N_Own > D then
            Corrected := 0;
            return;
         end if;
         for I in 1 .. N_Own loop
            Data (Offset + I) := Word (I);
         end loop;

         Corrected := Corrected + Fixed;
      end loop;

      N_Data := D;
      Success := True;
   end Correct_Blocks;

   -------------
   -- To_Text --
   -------------

   procedure To_Text
     (Data    : Codeword_Array;
      Version : Version_Number;
      Text    : out Text_Buffer;
      Length  : out Natural;
      OK      : out Boolean)
   is
      type Value_16 is mod 2 ** 16;

      subtype Bit_Count is Positive range 1 .. 16;

      type Value_List is array (Bit_Count) of Value_16;

      Lowest : constant Value_List :=
        [1, 3, 7, 15, 31, 63, 127, 255, 511, 1023, 2047, 4095, 8191, 16383,
         32767, 65535];
      --  Lowest (K): the lowest K bits.

      type Element_List is array (0 .. 7) of RS.Element;

      Bit_Of : constant Element_List := [128, 64, 32, 16, 8, 4, 2, 1];
      --  The bits of a codeword, the most significant first.

      subtype Set_Value is Natural range 0 .. 44;

      Set : constant String (1 .. 45) :=
        "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
      --  The characters of the alphanumeric mode.

      Zero : constant := Character'Pos ('0');

      N      : constant Codeword_Index := Data'Last;
      N_Bits : constant Positive := 8 * N;

      Pos     : Natural := 0;
      --  The bits taken.
      Len     : Natural := 0;
      Good    : Boolean := True;
      Ended   : Boolean := False;
      FNC1    : Boolean := False;
      --  FNC1 in the first or in the second position.
      Percent : Boolean := False;
      --  With FNC1, the last character of the alphanumeric segment was
      --  a "%" that the text does not have yet.
      Mode    : Natural;
      Unused  : Natural;

      function Valid return Boolean is
        (Data'First = 1 and then N = Data'Last and then N_Bits = 8 * N
         and then Pos <= N_Bits
         and then Text'First = 1 and then Len <= Text'Last);
      --  What the steps below rely on and keep.

      function Width (Short, Medium, Long : Bit_Count) return Bit_Count is
        (if Version <= 9 then Short
         elsif Version <= 26 then Medium
         else Long);
      --  The bits of the count of a segment: those for the versions
      --  1 .. 9, 10 .. 26 and 27 .. 40.

      procedure Get (Count : Bit_Count; Value : out Natural)
      with
        Pre  => Valid,
        Post => Valid and then Value <= Natural (Lowest (Count));
      --  The next Count bits, the most significant first. If fewer are
      --  left, the message is not good, and Value is 0.

      procedure Get (Count : Bit_Count; Value : out Natural) is
         V : Value_16 := 0;
      begin
         Value := 0;
         if N_Bits - Pos < Count then
            Good := False;
            return;
         end if;
         for K in 1 .. Count loop
            pragma Loop_Invariant (Pos = Pos'Loop_Entry + (K - 1));
            V := V * 2;
            if (Data (Pos / 8 + 1) and Bit_Of (Pos mod 8)) /= 0 then
               V := V + 1;
            end if;
            Pos := Pos + 1;
         end loop;
         Value := Natural (V and Lowest (Count));
      end Get;

      procedure Put (Code : Natural)
      with
        Pre  => Valid and then Code <= 255,
        Post => Valid;
      --  Adds the character Code to the text.

      procedure Put (Code : Natural) is
      begin
         if Len >= Text'Last then
            Good := False;
         else
            Len := Len + 1;
            Text (Len) := Character'Val (Code);
         end if;
      end Put;

      procedure Put_Digits (Value : Natural; Count : Positive)
      with
        Pre  => Valid and then Count <= 3 and then Value <= 999,
        Post => Valid;
      --  The last Count decimal digits of Value.

      procedure Put_Digits (Value : Natural; Count : Positive) is
      begin
         if Count = 3 then
            Put (Zero + Value / 100);
         end if;
         if Count >= 2 then
            Put (Zero + (Value / 10) mod 10);
         end if;
         Put (Zero + Value mod 10);
      end Put_Digits;

      procedure Numeric
      with
        Pre  => Valid,
        Post => Valid;

      procedure Numeric is
         Count : Natural;
         V     : Natural;
      begin
         Get (Width (10, 12, 14), Count);
         for I in 1 .. Count / 3 loop
            pragma Loop_Invariant (Valid);
            Get (10, V);
            exit when not Good;
            if V > 999 then
               Good := False;
               exit;
            end if;
            Put_Digits (V, 3);
         end loop;
         if Good and then Count mod 3 = 2 then
            Get (7, V);
            if V > 99 then
               Good := False;
            elsif Good then
               Put_Digits (V, 2);
            end if;
         elsif Good and then Count mod 3 = 1 then
            Get (4, V);
            if V > 9 then
               Good := False;
            elsif Good then
               Put_Digits (V, 1);
            end if;
         end if;
      end Numeric;

      procedure Put_Of_Set (Value : Set_Value)
      with
        Pre  => Valid,
        Post => Valid;
      --  A character of the alphanumeric mode. With FNC1, "%" stands
      --  for the character GS and "%%" for "%".

      procedure Put_Of_Set (Value : Set_Value) is
         C : constant Character := Set (Value + 1);
      begin
         if FNC1 and then C = '%' then
            if Percent then
               Put (Character'Pos ('%'));
            end if;
            Percent := not Percent;
         else
            if Percent then
               Put (29);
               Percent := False;
            end if;
            Put (Character'Pos (C));
         end if;
      end Put_Of_Set;

      procedure Alphanumeric
      with
        Pre  => Valid,
        Post => Valid;

      procedure Alphanumeric is
         Count : Natural;
         V     : Natural;
      begin
         Percent := False;
         Get (Width (9, 11, 13), Count);
         for I in 1 .. Count / 2 loop
            pragma Loop_Invariant (Valid);
            Get (11, V);
            exit when not Good;
            if V >= 45 * 45 then
               Good := False;
               exit;
            end if;
            Put_Of_Set (V / 45);
            Put_Of_Set (V mod 45);
         end loop;
         if Good and then Count mod 2 = 1 then
            Get (6, V);
            if V >= 45 then
               Good := False;
            elsif Good then
               Put_Of_Set (V);
            end if;
         end if;
         if Percent then
            Put (29);
            Percent := False;
         end if;
      end Alphanumeric;

      procedure Bytes
      with
        Pre  => Valid,
        Post => Valid;

      procedure Bytes is
         Count : Natural;
         V     : Natural;
      begin
         Get (Width (8, 16, 16), Count);
         for I in 1 .. Count loop
            pragma Loop_Invariant (Valid);
            Get (8, V);
            exit when not Good;
            Put (V);
         end loop;
      end Bytes;

      procedure Kanji
      with
        Pre  => Valid,
        Post => Valid;
      --  Thirteen bits stand for a character of two bytes: 16#8140# ..
      --  16#9FFC# and 16#E040# .. 16#EBBF# of Shift JIS, less 16#8140#
      --  or 16#C140#, the first byte of the difference times 16#C0#
      --  plus the second one.

      procedure Kanji is
         Count : Natural;
         V     : Natural;
         W     : Natural;
      begin
         Get (Width (8, 10, 12), Count);
         for I in 1 .. Count loop
            pragma Loop_Invariant (Valid);
            Get (13, V);
            exit when not Good;
            W := (V / 16#C0#) * 256 + V mod 16#C0#;
            W := W + (if W < 16#1F00# then 16#8140# else 16#C140#);
            Put (W / 256);
            Put (W mod 256);
         end loop;
      end Kanji;

      procedure ECI
      with
        Pre  => Valid,
        Post => Valid;
      --  The designator of an extended channel interpretation, in one,
      --  two or three codewords as the first of them says; passed over.

      procedure ECI is
         V      : Natural;
         Unused : Natural;
      begin
         Get (8, V);
         if V >= 224 then
            Good := False;
         elsif V >= 192 then
            Get (16, Unused);
         elsif V >= 128 then
            Get (8, Unused);
         end if;
      end ECI;

      procedure Second_Position
      with
        Pre  => Valid,
        Post => Valid;
      --  FNC1 in the second position: the application indicator, two
      --  digits or (100 more than its code) a letter.

      procedure Second_Position is
         V : Natural;
      begin
         FNC1 := True;
         Get (8, V);
         if not Good then
            null;
         elsif V < 100 then
            Put_Digits (V, 2);
         elsif V in 165 .. 190 | 197 .. 222 then
            Put (V - 100);
         else
            Good := False;
         end if;
      end Second_Position;

   begin
      Text := [others => ' '];

      --  Every segment takes the four bits of its mode at least, so
      --  2 * N steps are enough.
      for Step in 1 .. 2 * N loop
         pragma Loop_Invariant (Valid);

         --  The message ends with the mode 0, or where fewer than four
         --  bits are left.
         exit when not Good or else Ended or else N_Bits - Pos < 4;

         Get (4, Mode);
         case Mode is
            when 0 =>
               Ended := True;
            when 1 =>
               Numeric;
            when 2 =>
               Alphanumeric;
            when 3 =>
               --  Structured append: the place of the symbol among
               --  those of a message, and a parity; passed over.
               Get (16, Unused);
            when 4 =>
               Bytes;
            when 5 =>
               FNC1 := True;
            when 7 =>
               ECI;
            when 8 =>
               Kanji;
            when 9 =>
               Second_Position;
            when others =>
               Good := False;
         end case;
      end loop;

      Length := (if Good then Len else 0);
      OK := Good;
   end To_Text;

   ------------
   -- Decode --
   ------------

   procedure Decode
     (Grid      : Module_Grid;
      Version   : Version_Number;
      Mirror    : Boolean;
      Field     : RS.Field;
      Text      : out Text_Buffer;
      Length    : out Natural;
      Corrected : out Natural;
      Success   : out Boolean)
   is
      Total : constant Codeword_Total := Codewords (Version);

      Functions  : Module_Grid;
      Words      : Stream;
      Data       : Stream;
      N_Data     : Codeword_Count;
      Level_Read : Level;
      Mask       : Mask_Pattern;
      OK         : Boolean;
   begin
      Text := [others => ' '];
      Length := 0;
      Corrected := 0;
      Success := False;

      Read_Format (Grid, Version, Mirror, Level_Read, Mask, OK);
      if not OK then
         return;
      end if;
      if Version >= 7 and then not Version_Agrees (Grid, Version, Mirror) then
         return;
      end if;

      Mark_Functions (Version, Functions);
      Read_Codewords (Grid, Version, Mirror, Mask, Functions, Words, OK);
      if not OK then
         return;
      end if;

      Correct_Blocks
        (Blocks (Version, Level_Read), Correctable (Version, Level_Read),
         Total, Field, Words, Data, N_Data, Corrected, OK);
      if not OK then
         Corrected := 0;
         return;
      end if;

      To_Text (Data (1 .. N_Data), Version, Text, Length, OK);
      if not OK then
         Length := 0;
         Corrected := 0;
         return;
      end if;

      Success := True;
   end Decode;

end AMV.Kernels.Code_Reader.QR_Code;
