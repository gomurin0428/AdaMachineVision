with Interfaces; use Interfaces;

package body AMV_Test_QR_Code is

   use type QR.Level;

   ---------------------------------------------------------------------
   --  From a text to bits
   ---------------------------------------------------------------------

   Max_Bits : constant := 40_000;
   --  More than the largest symbol holds.

   type Builder is record
      Items : Bit_List (1 .. Max_Bits) := [others => False];
      Count : Natural := 0;
   end record;

   procedure Add (B : in out Builder; Value : Natural; Count : Natural);
   --  The lowest Count bits of Value.

   procedure Add (B : in out Builder; Value : Natural; Count : Natural) is
      V : Natural := Value;
   begin
      for K in reverse B.Count + 1 .. B.Count + Count loop
         B.Items (K) := V mod 2 = 1;
         V := V / 2;
      end loop;
      B.Count := B.Count + Count;
   end Add;

   function Bits (Value : Natural; Count : Natural) return Bit_List is
      B : Builder;
   begin
      Add (B, Value, Count);
      return B.Items (1 .. B.Count);
   end Bits;

   function Count_Bits
     (Kind    : Mode;
      Version : QR.Version_Number) return Positive
   is
     (case Kind is
         when Numeric      =>
           (if Version <= 9 then 10 elsif Version <= 26 then 12 else 14),
         when Alphanumeric =>
           (if Version <= 9 then 9 elsif Version <= 26 then 11 else 13),
         when Bytes        =>
           (if Version <= 9 then 8 else 16),
         when Kanji        =>
           (if Version <= 9 then 8 elsif Version <= 26 then 10 else 12));

   function Segment_Bits
     (Kind       : Mode;
      Characters : Natural;
      Version    : QR.Version_Number) return Positive
   is
     (4 + Count_Bits (Kind, Version)
      + (case Kind is
            when Numeric      =>
              10 * (Characters / 3)
              + (case Characters mod 3 is
                    when 0      => 0,
                    when 1      => 4,
                    when others => 7),
            when Alphanumeric =>
              11 * (Characters / 2) + 6 * (Characters mod 2),
            when Bytes        => 8 * Characters,
            when Kanji        => 13 * Characters));

   Set : constant String := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";

   function Value_Of (C : Character) return Natural;
   --  The value of a character of the alphanumeric mode.

   function Value_Of (C : Character) return Natural is
   begin
      for K in Set'Range loop
         if Set (K) = C then
            return K - Set'First;
         end if;
      end loop;
      raise Constraint_Error with "not a character of the mode";
   end Value_Of;

   function Segment
     (Kind    : Mode;
      Text    : String;
      Version : QR.Version_Number) return Bit_List
   is
      Width : constant Positive := Count_Bits (Kind, Version);
      Count : constant Natural :=
        (if Kind = Kanji then Text'Length / 2 else Text'Length);
      B     : Builder;
      I     : Integer := Text'First;
      V     : Natural;
      N     : Positive;
   begin
      if Count >= 2 ** Width then
         raise Constraint_Error with "more than the count can say";
      end if;

      case Kind is
         when Numeric =>
            Add (B, 1, 4);
            Add (B, Count, Width);
            while I <= Text'Last loop
               N := Integer'Min (3, Text'Last - I + 1);
               V := 0;
               for K in I .. I + N - 1 loop
                  if Text (K) not in '0' .. '9' then
                     raise Constraint_Error with "not a digit";
                  end if;
                  V := 10 * V
                    + Character'Pos (Text (K)) - Character'Pos ('0');
               end loop;
               Add (B, V, (case N is
                              when 3      => 10,
                              when 2      => 7,
                              when others => 4));
               I := I + N;
            end loop;

         when Alphanumeric =>
            Add (B, 2, 4);
            Add (B, Count, Width);
            while I <= Text'Last loop
               if I < Text'Last then
                  Add (B,
                       45 * Value_Of (Text (I)) + Value_Of (Text (I + 1)),
                       11);
                  I := I + 2;
               else
                  Add (B, Value_Of (Text (I)), 6);
                  I := I + 1;
               end if;
            end loop;

         when Bytes =>
            Add (B, 4, 4);
            Add (B, Count, Width);
            for C of Text loop
               Add (B, Character'Pos (C), 8);
            end loop;

         when Kanji =>
            if Text'Length mod 2 /= 0 then
               raise Constraint_Error with "half a character";
            end if;
            Add (B, 8, 4);
            Add (B, Count, Width);
            while I < Text'Last loop
               V := 256 * Character'Pos (Text (I))
                 + Character'Pos (Text (I + 1));
               if V mod 256 not in 16#40# .. 16#FC# then
                  raise Constraint_Error with "not a character of the mode";
               elsif V in 16#8140# .. 16#9FFC# then
                  V := V - 16#8140#;
               elsif V in 16#E040# .. 16#EBBF# then
                  V := V - 16#C140#;
               else
                  raise Constraint_Error with "not a character of the mode";
               end if;
               Add (B, 16#C0# * (V / 256) + V mod 256, 13);
               I := I + 2;
            end loop;
      end case;

      return B.Items (1 .. B.Count);
   end Segment;

   function ECI (Designator : Natural) return Bit_List is
     (Bits (7, 4)
      & (if Designator < 2 ** 7 then Bits (Designator, 8)
         elsif Designator < 2 ** 14 then Bits (2, 2) & Bits (Designator, 14)
         else Bits (6, 3) & Bits (Designator, 21)));

   function FNC1_First return Bit_List is (Bits (5, 4));

   function FNC1_Second (Indicator : Byte) return Bit_List is
     (Bits (9, 4) & Bits (Indicator, 8));

   function Structured_Append
     (Index, Last : Natural;
      Parity      : Byte) return Bit_List
   is (Bits (3, 4) & Bits (Index, 4) & Bits (Last, 4) & Bits (Parity, 8));

   ---------------------------------------------------------------------
   --  From bits to codewords
   ---------------------------------------------------------------------

   function Block_Count
     (Version : QR.Version_Number;
      Level   : QR.Level) return Positive
   is (QR.Blocks (Version, Level).Blocks_1
       + QR.Blocks (Version, Level).Blocks_2);

   function Data_Count
     (Version : QR.Version_Number;
      Level   : QR.Level) return Positive
   is (QR.Blocks (Version, Level).Data_1 * Block_Count (Version, Level)
       + QR.Blocks (Version, Level).Blocks_2);

   function Total_Count (Version : QR.Version_Number) return Positive is
      F : constant Module_Matrix := Function_Modules (Version);
      N : Natural := 0;
   begin
      for R in F'Range (1) loop
         for C in F'Range (2) loop
            if not F (R, C) then
               N := N + 1;
            end if;
         end loop;
      end loop;
      return N / 8;
   end Total_Count;

   function Smallest_Version
     (Kind  : Mode;
      Text  : String;
      Level : QR.Level) return QR.Version_Number
   is
      Count : constant Natural :=
        (if Kind = Kanji then Text'Length / 2 else Text'Length);
   begin
      for V in QR.Version_Number loop
         if Count < 2 ** Count_Bits (Kind, V)
           and then Segment_Bits (Kind, Count, V) <= 8 * Data_Count (V, Level)
         then
            return V;
         end if;
      end loop;
      raise Constraint_Error with "more than a symbol holds";
   end Smallest_Version;

   function Data_Codewords
     (Message : Bit_List;
      Version : QR.Version_Number;
      Level   : QR.Level) return Byte_List
   is
      N    : constant Positive := Data_Count (Version, Level);
      Room : constant Positive := 8 * N;
      All_Bits : Bit_List (1 .. Room) := [others => False];
      R    : Byte_List (1 .. N) := [others => 0];
      Used : Natural;
      V    : Natural;
   begin
      if Message'Length > Room then
         raise Constraint_Error with "more bits than the symbol holds";
      end if;
      All_Bits (1 .. Message'Length) := Message;

      --  The codewords with bits of the message or of the terminator;
      --  the zero bits that fill the last of them are there already.
      Used := (Integer'Min (Message'Length + 4, Room) + 7) / 8;

      for P in 1 .. N loop
         if P <= Used then
            V := 0;
            for K in 8 * P - 7 .. 8 * P loop
               V := 2 * V + (if All_Bits (K) then 1 else 0);
            end loop;
            R (P) := V;
         else
            R (P) := (if (P - Used) mod 2 = 1 then 236 else 17);
         end if;
      end loop;
      return R;
   end Data_Codewords;

   type Origin is record
      Block : Positive;
      Index : Positive;
   end record;
   --  The codeword Index of the block Block; the check codewords of a
   --  block follow those of the message.

   type Origin_List is array (Positive range <>) of Origin;

   function Origins
     (Version : QR.Version_Number;
      Level   : QR.Level) return Origin_List;
   --  Where the codeword at every place of a symbol comes from: the
   --  first codewords of all blocks, the second ones and so on (the
   --  blocks of the second group are one longer), then the check
   --  codewords in the same way.

   function Origins
     (Version : QR.Version_Number;
      Level   : QR.Level) return Origin_List
   is
      Info : constant QR.Block_Info := QR.Blocks (Version, Level);
      NB   : constant Positive := Block_Count (Version, Level);
      R    : Origin_List
        (1 .. Data_Count (Version, Level) + Info.Check * NB);
      P    : Natural := 0;
   begin
      for I in 1 .. Info.Data_1 + 1 loop
         for B in 1 .. NB loop
            if I <= Info.Data_1 or else B > Info.Blocks_1 then
               P := P + 1;
               R (P) := (B, I);
            end if;
         end loop;
      end loop;
      for J in 1 .. Info.Check loop
         for B in 1 .. NB loop
            P := P + 1;
            R (P) :=
              (B, Info.Data_1 + (if B > Info.Blocks_1 then 1 else 0) + J);
         end loop;
      end loop;
      return R;
   end Origins;

   function Blocks_Of_Places
     (Version : QR.Version_Number;
      Level   : QR.Level) return Number_List
   is
      From : constant Origin_List := Origins (Version, Level);
      R    : Number_List (From'Range);
   begin
      for P in From'Range loop
         R (P) := From (P).Block;
      end loop;
      return R;
   end Blocks_Of_Places;

   function "xor" (A, B : Byte) return Byte is
     (Byte (Unsigned_8 (A) xor Unsigned_8 (B)));

   function Mul (A, B : Byte) return Byte;
   --  The product in GF(256) modulo x**8 + x**4 + x**3 + x**2 + 1.

   function Mul (A, B : Byte) return Byte is
      X : Unsigned_16 := Unsigned_16 (A);
      Y : Unsigned_16 := Unsigned_16 (B);
      R : Unsigned_16 := 0;
   begin
      while Y /= 0 loop
         if (Y and 1) /= 0 then
            R := R xor X;
         end if;
         X := X * 2;
         if X >= 256 then
            X := X xor 16#11D#;
         end if;
         Y := Y / 2;
      end loop;
      return Byte (R);
   end Mul;

   function Stream
     (Data    : Byte_List;
      Version : QR.Version_Number;
      Level   : QR.Level) return Byte_List
   is
      Info  : constant QR.Block_Info := QR.Blocks (Version, Level);
      NB    : constant Positive := Block_Count (Version, Level);
      Check : constant Positive := Info.Check;
      From  : constant Origin_List := Origins (Version, Level);

      type Polynomial is array (Natural range <>) of Byte;

      G : Polynomial (0 .. Check) := [0 => 1, others => 0];
      --  The generator: the product of (x + Alpha ** J), J = 0 ..
      --  Check - 1. G (K) is the coefficient of x ** K.
      Remainder : Polynomial (0 .. Check - 1);
      Root      : Byte := 1;
      Top       : Byte;

      Words : array (1 .. NB, 1 .. Info.Data_1 + 1 + Check) of Byte :=
        [others => [others => 0]];
      --  The blocks.
      Next  : Natural := Data'First - 1;
      Own   : Positive;
      R     : Byte_List (From'Range);
   begin
      if Data'Length /= Data_Count (Version, Level) then
         raise Constraint_Error with "not the codewords of the version";
      end if;

      for J in 1 .. Check loop
         for K in reverse 0 .. J loop
            G (K) := Mul (G (K), Root) xor (if K > 0 then G (K - 1) else 0);
         end loop;
         Root := Mul (Root, 2);
      end loop;

      --  The codewords of the message go to the blocks one block after
      --  another.

      for B in 1 .. NB loop
         Own := Info.Data_1 + (if B > Info.Blocks_1 then 1 else 0);
         Remainder := [others => 0];
         for I in 1 .. Own loop
            Next := Next + 1;
            Words (B, I) := Data (Next);
            Top := Data (Next) xor Remainder (Check - 1);
            for K in reverse 1 .. Check - 1 loop
               Remainder (K) := Remainder (K - 1) xor Mul (Top, G (K));
            end loop;
            Remainder (0) := Mul (Top, G (0));
         end loop;
         for J in 1 .. Check loop
            Words (B, Own + J) := Remainder (Check - J);
         end loop;
      end loop;

      for P in R'Range loop
         R (P) := Words (From (P).Block, From (P).Index);
      end loop;
      return R;
   end Stream;

   ---------------------------------------------------------------------
   --  From codewords to a symbol
   ---------------------------------------------------------------------

   function Alignment_Centres
     (Version : QR.Version_Number) return Number_List
   is
      Count : constant Positive := Version / 7 + 2;
      Last  : constant Positive := 4 * Version + 10;
      Step  : constant Positive :=
        (if Version = 32 then 26
         else (4 * Version + 2 * Count + 1) / (2 * Count - 2) * 2);
      R     : Number_List (1 .. Count);
   begin
      if Version = 1 then
         return [1 .. 0 => 0];
      end if;
      R (1) := 6;
      for K in 2 .. Count loop
         R (K) := Last - Step * (Count - K);
      end loop;
      return R;
   end Alignment_Centres;

   function Remainder_Of
     (Value     : Natural;
      Generator : Natural;
      Degree    : Positive;
      Top       : Positive) return Natural;
   --  The remainder of Value * x ** Degree by the polynomial Generator
   --  of the degree Degree, with the bits as coefficients; Value has
   --  Top bits at most.

   function Remainder_Of
     (Value     : Natural;
      Generator : Natural;
      Degree    : Positive;
      Top       : Positive) return Natural
   is
      R : Unsigned_32 := Unsigned_32 (Value) * 2 ** Degree;
   begin
      for K in reverse Degree .. Degree + Top - 1 loop
         if (R and 2 ** K) /= 0 then
            R := R xor (Unsigned_32 (Generator) * 2 ** (K - Degree));
         end if;
      end loop;
      return Natural (R);
   end Remainder_Of;

   function Format_Word
     (Level : QR.Level;
      Mask  : QR.Mask_Pattern) return Natural
   is
      Data : constant Natural :=
        8 * (case Level is
                when QR.L => 1,
                when QR.M => 0,
                when QR.Q => 3,
                when QR.H => 2)
        + Mask;
      Word : constant Unsigned_32 :=
        Unsigned_32 (Data * 2 ** 10 + Remainder_Of (Data, 16#537#, 10, 5));
   begin
      return Natural (Word xor 2#101_0100_0001_0010#);
   end Format_Word;

   function Version_Word (Version : QR.Version_Number) return Natural is
     (Version * 2 ** 12 + Remainder_Of (Version, 16#1F25#, 12, 6));

   function Bit_Of (Word : Natural; K : Natural) return Boolean is
     ((Word / 2 ** K) mod 2 = 1);
   --  The bit K of Word; the bit 0 is the least significant one.

   procedure Put_Format
     (Symbol : in out Module_Matrix;
      Copy   : Copy_Number;
      Word   : Natural)
   is
      S : constant Positive := Symbol'Length (1);
   begin
      if Copy = 1 then
         for K in 0 .. 5 loop
            Symbol (K, 8) := Bit_Of (Word, K);
         end loop;
         Symbol (7, 8) := Bit_Of (Word, 6);
         Symbol (8, 8) := Bit_Of (Word, 7);
         Symbol (8, 7) := Bit_Of (Word, 8);
         for K in 9 .. 14 loop
            Symbol (8, 14 - K) := Bit_Of (Word, K);
         end loop;
      else
         for K in 0 .. 7 loop
            Symbol (8, S - 1 - K) := Bit_Of (Word, K);
         end loop;
         for K in 8 .. 14 loop
            Symbol (S - 15 + K, 8) := Bit_Of (Word, K);
         end loop;
      end if;
   end Put_Format;

   procedure Put_Version
     (Symbol : in out Module_Matrix;
      Copy   : Copy_Number;
      Word   : Natural)
   is
      S : constant Positive := Symbol'Length (1);
   begin
      for I in 0 .. 5 loop
         for J in 0 .. 2 loop
            if Copy = 1 then
               Symbol (I, S - 11 + J) := Bit_Of (Word, 3 * I + J);
            else
               Symbol (S - 11 + J, I) := Bit_Of (Word, 3 * I + J);
            end if;
         end loop;
      end loop;
   end Put_Version;

   function Masked
     (Mask        : QR.Mask_Pattern;
      Row, Column : Natural) return Boolean
   is
      P : constant Natural := Row * Column;
   begin
      return
        (case Mask is
            when 0 => Row mod 2 = Column mod 2,
            when 1 => Row mod 2 = 0,
            when 2 => Column mod 3 = 0,
            when 3 => (Row + Column) mod 3 = 0,
            when 4 => (Row / 2) mod 2 = (Column / 3) mod 2,
            when 5 => P mod 6 = 0,
            when 6 => P mod 6 < 3,
            when 7 => (Row + Column + P mod 3) mod 2 = 0);
   end Masked;

   procedure Paint
     (Version  : QR.Version_Number;
      Level    : QR.Level;
      Mask     : QR.Mask_Pattern;
      M        : out Module_Matrix;
      Reserved : out Module_Matrix);
   --  The patterns and the format and version information of a symbol,
   --  and which modules they take. M and Reserved: as large as the
   --  symbol, from (0, 0).

   procedure Paint
     (Version  : QR.Version_Number;
      Level    : QR.Level;
      Mask     : QR.Mask_Pattern;
      M        : out Module_Matrix;
      Reserved : out Module_Matrix)
   is
      S       : constant Positive := 17 + 4 * Version;
      Centres : constant Number_List := Alignment_Centres (Version);

      procedure Set (Row, Column : Integer; Dark : Boolean);
      --  A module of a pattern; nothing outside the symbol.

      procedure Set (Row, Column : Integer; Dark : Boolean) is
      begin
         if Row in 0 .. S - 1 and then Column in 0 .. S - 1 then
            M (Row, Column) := Dark;
            Reserved (Row, Column) := True;
         end if;
      end Set;

      procedure Finder (Row, Column : Natural);
      --  The finder pattern with its middle at (Row, Column), and the
      --  light modules around it.

      procedure Finder (Row, Column : Natural) is
      begin
         for DR in -4 .. 4 loop
            for DC in -4 .. 4 loop
               Set (Row + DR, Column + DC,
                    Integer'Max (abs DR, abs DC) not in 2 | 4);
            end loop;
         end loop;
      end Finder;

      procedure Reserve (Row_1, Row_2, Column_1, Column_2 : Natural);
      --  The modules are taken, whatever is written there.

      procedure Reserve (Row_1, Row_2, Column_1, Column_2 : Natural) is
      begin
         for R in Row_1 .. Row_2 loop
            for C in Column_1 .. Column_2 loop
               Reserved (R, C) := True;
            end loop;
         end loop;
      end Reserve;
   begin
      M := [others => [others => False]];
      Reserved := [others => [others => False]];

      Finder (3, 3);
      Finder (3, S - 4);
      Finder (S - 4, 3);

      --  The timing patterns, between the finder patterns.
      for I in 8 .. S - 9 loop
         Set (6, I, I mod 2 = 0);
         Set (I, 6, I mod 2 = 0);
      end loop;

      --  The alignment patterns.
      for R of Centres loop
         for C of Centres loop
            if not ((R = 6 and then C = 6)
                    or else (R = 6 and then C = S - 7)
                    or else (R = S - 7 and then C = 6))
            then
               for DR in -2 .. 2 loop
                  for DC in -2 .. 2 loop
                     Set (R + DR, C + DC,
                          Integer'Max (abs DR, abs DC) /= 1);
                  end loop;
               end loop;
            end if;
         end loop;
      end loop;

      --  The format information, twice, in the row 8 and the column 8
      --  beside the finder patterns. The module beside the lower left
      --  finder pattern is always dark.
      Reserve (0, 8, 8, 8);
      Reserve (8, 8, 0, 8);
      Reserve (8, 8, S - 8, S - 1);
      Reserve (S - 8, S - 1, 8, 8);
      Put_Format (M, 1, Format_Word (Level, Mask));
      Put_Format (M, 2, Format_Word (Level, Mask));
      M (S - 8, 8) := True;

      --  The version information, twice: six by three modules.
      if Version >= 7 then
         Reserve (0, 5, S - 11, S - 9);
         Reserve (S - 11, S - 9, 0, 5);
         Put_Version (M, 1, Version_Word (Version));
         Put_Version (M, 2, Version_Word (Version));
      end if;
   end Paint;

   function Function_Modules
     (Version : QR.Version_Number) return Module_Matrix
   is
      S : constant Positive := 17 + 4 * Version;
      M, Reserved : Module_Matrix (0 .. S - 1, 0 .. S - 1);
   begin
      Paint (Version, QR.L, 0, M, Reserved);
      return Reserved;
   end Function_Modules;

   function Modules
     (Codewords : Byte_List;
      Version   : QR.Version_Number;
      Level     : QR.Level;
      Mask      : QR.Mask_Pattern) return Module_Matrix
   is
      S      : constant Positive := 17 + 4 * Version;
      N_Bits : constant Natural := 8 * Codewords'Length;
      M, Reserved : Module_Matrix (0 .. S - 1, 0 .. S - 1);
      Placed : Natural := 0;
      Right  : Integer := S - 1;
      Up     : Boolean := True;
      Row    : Natural;

      function Bit (I : Natural) return Boolean is
        ((Codewords (Codewords'First + I / 8) / 2 ** (7 - I mod 8)) mod 2
         = 1);
      --  The bit I of the codewords, from 0, the most significant bit
      --  of a codeword first.
   begin
      if Codewords'Length /= Total_Count (Version) then
         raise Constraint_Error with "not the codewords of the version";
      end if;
      Paint (Version, Level, Mask, M, Reserved);

      --  Two columns at a time from the right, up and down in turn, the
      --  right module of a row before the left one; the column of the
      --  timing pattern is passed over. The modules that are left over
      --  after the last codeword are light before the mask.
      while Right >= 1 loop
         if Right = 6 then
            Right := 5;
         end if;
         for Step in 0 .. S - 1 loop
            Row := (if Up then S - 1 - Step else Step);
            for Column in reverse Right - 1 .. Right loop
               if not Reserved (Row, Column) then
                  M (Row, Column) :=
                    (Placed < N_Bits and then Bit (Placed))
                    xor Masked (Mask, Row, Column);
                  Placed := Placed + 1;
               end if;
            end loop;
         end loop;
         Up := not Up;
         Right := Right - 2;
      end loop;
      return M;
   end Modules;

   function Grid (Symbol : Module_Matrix) return QR.Module_Grid is
      G : QR.Module_Grid := [others => [others => False]];
   begin
      for R in Symbol'Range (1) loop
         for C in Symbol'Range (2) loop
            G (QR.Module_Index (R), QR.Module_Index (C)) := Symbol (R, C);
         end loop;
      end loop;
      return G;
   end Grid;

   function Transposed (Symbol : Module_Matrix) return Module_Matrix is
      T : Module_Matrix (Symbol'Range (2), Symbol'Range (1));
   begin
      for R in Symbol'Range (1) loop
         for C in Symbol'Range (2) loop
            T (C, R) := Symbol (R, C);
         end loop;
      end loop;
      return T;
   end Transposed;

end AMV_Test_QR_Code;
