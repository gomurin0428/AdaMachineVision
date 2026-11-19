--  Tests for AMV.Kernels.Code_Reader.QR_Code: from the modules of a QR
--  Code symbol to its text.
--
--  The symbols come from the test's own encoder (AMV_Test_QR_Code), which
--  shares only the table of the blocks with the kernel. The tables are
--  checked by themselves: the blocks against the modules that hold
--  codewords and against the published capacities, the alignment
--  patterns against a formula, the words of the format and of the
--  version information against a division, the patterns and the masks
--  against the encoder's. The rules of every mode are tried on
--  codewords. Symbols of every version, level and mask are read as they
--  are and seen from behind; symbols of every version and level with as
--  many wrong codewords in every block as are corrected, and with one
--  more; then modules by chance, wrong bits in the format and in the
--  version information, and buffers too short for the text.

pragma Validity_Checks ("F");

with Ada.Text_IO;
with Interfaces;

with AMV.Kernels.Code_Reader.QR_Code;
with AMV.Kernels.Code_Reader.Reed_Solomon;
with AMV_Test_QR_Code;
with AMV_Test_Support; use AMV_Test_Support;

procedure Test_Code_Reader_QR_Symbol is

   package QR renames AMV.Kernels.Code_Reader.QR_Code;
   package RS renames AMV.Kernels.Code_Reader.Reed_Solomon;
   package Enc renames AMV_Test_QR_Code;

   use type Interfaces.Unsigned_32;
   use type QR.Level;
   use type Enc.Bit_List;
   use type Enc.Byte_List;
   use type Enc.Mode;

   Field : constant RS.Field := RS.Make_Field (RS.QR_Code_Polynomial);

   GS : constant Character := Character'Val (29);

   Set : constant String := "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:";
   --  The characters of the alphanumeric mode.

   No_Bits : constant Enc.Bit_List (1 .. 0) := [others => False];

   ---------------------------------------------------------------------
   --  Random numbers (the same ones in every run)
   ---------------------------------------------------------------------

   State : Interfaces.Unsigned_32 := 4711;

   function Random (Count : Positive) return Natural;
   --  One of 0 .. Count - 1.

   function Random (Count : Positive) return Natural is
   begin
      State := State * 1_103_515_245 + 12_345;
      return Natural (Interfaces.Shift_Right (State, 8) and 16#FFFF#)
             mod Count;
   end Random;

   function Image (Value : Integer) return String;

   function Image (Value : Integer) return String is
      S : constant String := Integer'Image (Value);
   begin
      return (if Value < 0 then S else S (S'First + 1 .. S'Last));
   end Image;

   function Distance (A, B : Natural) return Natural;
   --  The bits in which A and B differ.

   function Distance (A, B : Natural) return Natural is
      X : Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (A) xor Interfaces.Unsigned_32 (B);
      N : Natural := 0;
   begin
      while X /= 0 loop
         N := N + Natural (X and 1);
         X := Interfaces.Shift_Right (X, 1);
      end loop;
      return N;
   end Distance;

   function Flipped (Word : Natural; Width, Count : Positive) return Natural;
   --  Word with Count of its lowest Width bits, taken by chance, turned
   --  over.

   function Flipped (Word : Natural; Width, Count : Positive) return Natural
   is
      W    : Interfaces.Unsigned_32 := Interfaces.Unsigned_32 (Word);
      Bit  : Interfaces.Unsigned_32;
      Done : Natural := 0;
   begin
      while Done < Count loop
         Bit := Interfaces.Shift_Left (1, Random (Width));
         if ((W xor Interfaces.Unsigned_32 (Word)) and Bit) = 0 then
            W := W xor Bit;
            Done := Done + 1;
         end if;
      end loop;
      return Natural (W);
   end Flipped;

   ---------------------------------------------------------------------
   --  Texts
   ---------------------------------------------------------------------

   function Capacity
     (Kind    : Enc.Mode;
      Version : QR.Version_Number;
      Grade   : QR.Level) return Natural;
   --  The characters of one segment of the mode that a symbol holds.

   function Capacity
     (Kind    : Enc.Mode;
      Version : QR.Version_Number;
      Grade   : QR.Level) return Natural
   is
      Room : constant Positive := 8 * Enc.Data_Count (Version, Grade);
      N    : Natural := 0;
   begin
      while N + 1 < 2 ** Enc.Count_Bits (Kind, Version)
        and then Enc.Segment_Bits (Kind, N + 1, Version) <= Room
      loop
         N := N + 1;
      end loop;
      return N;
   end Capacity;

   function Text_By_Chance (Kind : Enc.Mode; Count : Natural) return String;
   --  Count characters of the mode (Kanji: of two bytes each).

   function Text_By_Chance (Kind : Enc.Mode; Count : Natural) return String
   is
      R     : String (1 .. (if Kind = Enc.Kanji then 2 * Count else Count));
      Lead  : Natural;
      Trail : Natural;
   begin
      case Kind is
         when Enc.Numeric =>
            for C of R loop
               C := Character'Val (Character'Pos ('0') + Random (10));
            end loop;
         when Enc.Alphanumeric =>
            for C of R loop
               C := Set (Set'First + Random (45));
            end loop;
         when Enc.Bytes =>
            for C of R loop
               C := Character'Val (Random (256));
            end loop;
         when Enc.Kanji =>
            for K in 1 .. Count loop
               Lead := Random (43);
               Lead := (if Lead < 31 then 16#81# + Lead
                        else 16#E0# + Lead - 31);
               Trail := 16#40#
                 + Random (if Lead = 16#EB# then 128 else 189);
               R (2 * K - 1) := Character'Val (Lead);
               R (2 * K) := Character'Val (Trail);
            end loop;
      end case;
      return R;
   end Text_By_Chance;

   ---------------------------------------------------------------------
   --  What the kernel gives
   ---------------------------------------------------------------------

   Text      : QR.Text_Buffer (1 .. QR.Max_Text_Length);
   Length    : Natural;
   OK        : Boolean;
   Corrected : Natural;
   Success   : Boolean;

   function Codewords_Of (Data : Enc.Byte_List) return QR.Codeword_Array;

   function Codewords_Of (Data : Enc.Byte_List) return QR.Codeword_Array is
      R : QR.Codeword_Array (1 .. Data'Length);
   begin
      for I in R'Range loop
         R (I) := RS.Element (Data (Data'First + I - 1));
      end loop;
      return R;
   end Codewords_Of;

   function Raw (Bits : Enc.Bit_List) return Enc.Byte_List;
   --  The bits in codewords, the last of them filled with zero bits: no
   --  terminator, no pads.

   function Raw (Bits : Enc.Bit_List) return Enc.Byte_List is
      R : Enc.Byte_List (1 .. (Bits'Length + 7) / 8) := [others => 0];
      K : Natural := 0;
   begin
      for B of Bits loop
         if B then
            R (K / 8 + 1) := R (K / 8 + 1) + 2 ** (7 - K mod 8);
         end if;
         K := K + 1;
      end loop;
      return R;
   end Raw;

   procedure Parse
     (Bits    : Enc.Bit_List;
      Version : QR.Version_Number;
      Grade   : QR.Level := QR.L);
   --  To_Text of the codewords of the message of a symbol with Bits.

   procedure Parse
     (Bits    : Enc.Bit_List;
      Version : QR.Version_Number;
      Grade   : QR.Level := QR.L) is
   begin
      QR.To_Text
        (Codewords_Of (Enc.Data_Codewords (Bits, Version, Grade)),
         Version, Text, Length, OK);
   end Parse;

   procedure Parse_Raw (Bits : Enc.Bit_List; Version : QR.Version_Number);
   --  To_Text of Raw (Bits).

   procedure Parse_Raw (Bits : Enc.Bit_List; Version : QR.Version_Number) is
   begin
      QR.To_Text (Codewords_Of (Raw (Bits)), Version, Text, Length, OK);
   end Parse_Raw;

   function Got (Expected : String) return Boolean is
     (OK and then Length = Expected'Length
      and then String (Text (1 .. Length)) = Expected);

   function Refused return Boolean is (not OK and then Length = 0);

   procedure Read
     (Symbol  : Enc.Module_Matrix;
      Version : QR.Version_Number;
      Mirror  : Boolean := False);
   --  Decode of the modules.

   procedure Read
     (Symbol  : Enc.Module_Matrix;
      Version : QR.Version_Number;
      Mirror  : Boolean := False) is
   begin
      QR.Decode
        (Enc.Grid (Symbol), Version, Mirror, Field, Text, Length,
         Corrected, Success);
   end Read;

   function Read_Is (Expected : String; Fixed : Natural) return Boolean is
     (Success and then Corrected = Fixed and then Length = Expected'Length
      and then String (Text (1 .. Length)) = Expected);

   function No_Read return Boolean is
     (not Success and then Length = 0 and then Corrected = 0);

   ---------------------------------------------------------------------
   --  The tables
   ---------------------------------------------------------------------

   procedure Test_Tables is
      use type QR.Centre_List;

      Level_Bits : constant array (QR.Level) of Natural :=
        [QR.L => 1, QR.M => 0, QR.Q => 3, QR.H => 2];

      type Capacity_Row is record
         Version : QR.Version_Number;
         Grade   : QR.Level;
         Digit_Count, Letter_Count, Byte_Count, Kanji_Count : Natural;
      end record;

      Published : constant array (1 .. 12) of Capacity_Row :=
        [(1, QR.L, 41, 25, 17, 10),
         (1, QR.M, 34, 20, 14, 8),
         (1, QR.Q, 27, 16, 11, 7),
         (1, QR.H, 17, 10, 7, 4),
         (10, QR.L, 652, 395, 271, 167),
         (10, QR.M, 513, 311, 213, 131),
         (10, QR.Q, 364, 221, 151, 93),
         (10, QR.H, 288, 174, 119, 74),
         (40, QR.L, 7089, 4296, 2953, 1817),
         (40, QR.M, 5596, 3391, 2331, 1435),
         (40, QR.Q, 3993, 2420, 1663, 1024),
         (40, QR.H, 3057, 1852, 1273, 784)];
      --  ISO/IEC 18004, the table of the data capacities.

      First_Totals : constant Enc.Number_List :=
        [26, 44, 70, 100, 134, 172, 196, 242, 292, 346];

      Sums      : Boolean := True;
      Lengths   : Boolean := True;
      Totals    : Boolean := True;
      Left_Over : Boolean := True;
      Capable   : Boolean := True;
      Longest   : Natural := 0;
      Limits    : Boolean := True;
      Same      : Boolean := True;
      Apart     : Natural;
      Map       : QR.Module_Grid;
      Free      : Natural;
   begin
      Section ("QR Code: the tables");

      --  The blocks.

      for V in QR.Version_Number loop
         declare
            F : constant Enc.Module_Matrix := Enc.Function_Modules (V);
         begin
            Free := 0;
            for R in F'Range (1) loop
               for C in F'Range (2) loop
                  if not F (R, C) then
                     Free := Free + 1;
                  end if;
               end loop;
            end loop;
            Totals := Totals and then Free / 8 = QR.Codewords (V)
                      and then Enc.Total_Count (V) = QR.Codewords (V);
            Left_Over := Left_Over and then Free mod 8 in 0 | 3 | 4 | 7;
         end;

         for L in QR.Level loop
            declare
               I    : constant QR.Block_Info := QR.Blocks (V, L);
               NB   : constant Positive := Enc.Block_Count (V, L);
               Data : constant Positive := Enc.Data_Count (V, L);
               Half : constant Positive := I.Check / 2;
            begin
               Sums := Sums and then Data + I.Check * NB = QR.Codewords (V);
               Lengths := Lengths and then Data <= QR.Max_Data;
               Limits := Limits
                 and then QR.Correctable (V, L)
                          = (if V = 1 and then L = QR.L then 2
                             elsif V = 1 and then L = QR.M then 4
                             elsif V = 2 and then L = QR.L then 4
                             else Half);
               for Kind in Enc.Mode loop
                  Longest := Natural'Max
                    (Longest,
                     Capacity (Kind, V, L)
                     * (if Kind = Enc.Kanji then 2 else 1));
               end loop;
            end;
         end loop;
      end loop;

      Check (Sums,
             "the blocks of every version and level have the codewords "
             & "of the version");
      Check (Lengths, "no message is longer than Max_Data codewords");
      Check (Totals,
             "the codewords of a version are an eighth of its modules "
             & "outside the patterns");
      Check (Left_Over, "0, 3, 4 or 7 modules are left over");
      Check ((for all V in First_Totals'Range =>
                QR.Codewords (V) = First_Totals (V)),
             "the published codewords of the versions 1 to 10");
      Check (Enc.Total_Count (40) = QR.Max_Codewords
             and then Enc.Data_Count (40, QR.L) = QR.Max_Data,
             "the version 40 has Max_Codewords codewords, Max_Data of "
             & "them of the message at the level L");

      for P of Published loop
         Capable := Capable
           and then Capacity (Enc.Numeric, P.Version, P.Grade)
                    = P.Digit_Count
           and then Capacity (Enc.Alphanumeric, P.Version, P.Grade)
                    = P.Letter_Count
           and then Capacity (Enc.Bytes, P.Version, P.Grade) = P.Byte_Count
           and then Capacity (Enc.Kanji, P.Version, P.Grade)
                    = P.Kanji_Count;
      end loop;
      Check (Capable,
             "the published capacities of the versions 1, 10 and 40 at "
             & "every level, in every mode");
      Check (Longest = QR.Max_Text_Length,
             "no symbol holds a longer text than Max_Text_Length ("
             & Image (Longest) & ")");

      Check (Limits,
             "Correctable is half the check codewords, but 2 for 1-L and "
             & "4 for 1-M and 2-L");
      Check (QR.Correctable (1, QR.L) = 2
             and then QR.Correctable (1, QR.M) = 4
             and then QR.Correctable (1, QR.Q) = 6
             and then QR.Correctable (1, QR.H) = 8
             and then QR.Correctable (2, QR.L) = 4
             and then QR.Correctable (2, QR.M) = 8
             and then QR.Correctable (3, QR.L) = 7
             and then QR.Correctable (5, QR.L) = 13
             and then QR.Correctable (40, QR.H) = 15,
             "the published numbers of codewords that are corrected");

      --  The alignment patterns.

      Same := True;
      for V in QR.Version_Number loop
         declare
            C : constant Enc.Number_List := Enc.Alignment_Centres (V);
         begin
            for K in QR.Centre_List'Range loop
               Same := Same
                 and then QR.Centres (V) (K)
                          = (if K <= C'Last then C (K) else 0);
            end loop;
         end;
      end loop;
      Check (Same, "the alignment patterns are where the formula has them");
      Check (QR.Centres (1) = [0, 0, 0, 0, 0, 0, 0]
             and then QR.Centres (2) = [6, 18, 0, 0, 0, 0, 0]
             and then QR.Centres (7) = [6, 22, 38, 0, 0, 0, 0]
             and then QR.Centres (32) = [6, 34, 60, 86, 112, 138, 0]
             and then QR.Centres (36) = [6, 24, 50, 76, 102, 128, 154]
             and then QR.Centres (40) = [6, 30, 58, 86, 114, 142, 170],
             "the published alignment patterns of the versions 1, 2, 7, "
             & "32, 36 and 40");

      --  The format and the version information.

      Same := True;
      for L in QR.Level loop
         for Mask in QR.Mask_Pattern loop
            Same := Same
              and then Natural (QR.Format_Words (8 * Level_Bits (L) + Mask))
                       = Enc.Format_Word (L, Mask);
         end loop;
      end loop;
      Check (Same, "the words of the format information are the division's");
      Check (Enc.Format_Word (QR.M, 0) = 16#5412#
             and then Enc.Format_Word (QR.L, 0) = 16#77C4#
             and then Enc.Format_Word (QR.M, 5) = 16#40CE#
             and then Enc.Format_Word (QR.H, 7) = 16#083B#
             and then Enc.Format_Word (QR.Q, 0) = 16#355F#,
             "published words of the format information");
      Apart := 15;
      for A in QR.Format_Words'Range loop
         for B in A + 1 .. QR.Format_Words'Last loop
            Apart := Natural'Min
              (Apart,
               Distance (Natural (QR.Format_Words (A)),
                         Natural (QR.Format_Words (B))));
         end loop;
      end loop;
      Check (Apart = 7,
             "two words of the format information differ in 7 bits or "
             & "more (" & Image (Apart) & ")");

      Check ((for all V in QR.Version_Words'Range =>
                Natural (QR.Version_Words (V)) = Enc.Version_Word (V)),
             "the words of the version information are the division's");
      Check (Enc.Version_Word (7) = 16#07C94#
             and then Enc.Version_Word (40) = 16#28C69#,
             "published words of the version information");
      Apart := 18;
      for A in QR.Version_Words'Range loop
         for B in A + 1 .. QR.Version_Words'Last loop
            Apart := Natural'Min
              (Apart,
               Distance (Natural (QR.Version_Words (A)),
                         Natural (QR.Version_Words (B))));
         end loop;
      end loop;
      Check (Apart = 8,
             "two words of the version information differ in 8 bits or "
             & "more (" & Image (Apart) & ")");

      --  The patterns and the masks.

      Same := True;
      for V in QR.Version_Number loop
         declare
            S : constant Positive := QR.Side (V);
            F : constant Enc.Module_Matrix := Enc.Function_Modules (V);
         begin
            QR.Mark_Functions (V, Map);
            for R in 0 .. QR.Max_Side - 1 loop
               for C in 0 .. QR.Max_Side - 1 loop
                  Same := Same
                    and then Map (QR.Module_Index (R), QR.Module_Index (C))
                             = (R < S and then C < S and then F (R, C));
               end loop;
            end loop;
         end;
      end loop;
      Check (Same,
             "Mark_Functions marks the modules that the encoder's "
             & "patterns take, and none outside the symbol");

      Same := True;
      for Mask in QR.Mask_Pattern loop
         for R in 0 .. QR.Max_Side - 1 loop
            for C in 0 .. QR.Max_Side - 1 loop
               Same := Same
                 and then QR.Masked
                            (Mask, QR.Module_Index (R), QR.Module_Index (C))
                          = Enc.Masked (Mask, R, C);
            end loop;
         end loop;
      end loop;
      Check (Same, "the eight masks are the encoder's, for every module");

      --  The sides.

      Check ((for all V in QR.Version_Number =>
                QR.Side (V) = 17 + 4 * V
                and then QR.Version_Of (QR.Side (V)) = V),
             "Version_Of the side of a version is the version");
      Check ((for all N in -4 .. QR.Max_Side + 8 =>
                (if N < 21 or else N > 177 or else (N - 17) mod 4 /= 0
                 then QR.Version_Of (N) = 0)),
             "Version_Of is 0 for the other numbers of modules");

      --  The encoder against published codewords.

      Check (Enc.Stream
               (Enc.Data_Codewords
                  (Enc.Segment (Enc.Numeric, "01234567", 1), 1, QR.M),
                1, QR.M)
             = [16#10#, 16#20#, 16#0C#, 16#56#, 16#61#, 16#80#, 16#EC#,
                16#11#, 16#EC#, 16#11#, 16#EC#, 16#11#, 16#EC#, 16#11#,
                16#EC#, 16#11#,
                16#A5#, 16#24#, 16#D4#, 16#C1#, 16#ED#, 16#36#, 16#C7#,
                16#87#, 16#2C#, 16#55#],
             "the test's codewords of 01234567 at 1-M are the published "
             & "ones");
      Check (Enc.Stream
               (Enc.Data_Codewords
                  (Enc.Segment (Enc.Alphanumeric, "HELLO WORLD", 1),
                   1, QR.Q),
                1, QR.Q)
             = [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236,
                168, 72, 22, 82, 217, 54, 156, 0, 46, 15, 180, 122, 16],
             "the test's codewords of HELLO WORLD at 1-Q are the "
             & "published ones");
   end Test_Tables;

   ---------------------------------------------------------------------
   --  The modes
   ---------------------------------------------------------------------

   procedure Test_Numeric is
      Groups : String (1 .. 3000);
      Good   : Boolean := True;
   begin
      Section ("QR Code: the numeric mode");

      for N in 0 .. 12 loop
         declare
            T : constant String := Text_By_Chance (Enc.Numeric, N);
         begin
            Parse (Enc.Segment (Enc.Numeric, T, 1), 1);
            Good := Good and then Got (T);
         end;
      end loop;
      Check (Good, "0 to 12 digits");

      for G in 0 .. 999 loop
         Groups (3 * G + 1) := Character'Val (Character'Pos ('0') + G / 100);
         Groups (3 * G + 2) :=
           Character'Val (Character'Pos ('0') + (G / 10) mod 10);
         Groups (3 * G + 3) := Character'Val (Character'Pos ('0') + G mod 10);
      end loop;
      declare
         V : constant QR.Version_Number :=
           Enc.Smallest_Version (Enc.Numeric, Groups, QR.L);
      begin
         Parse (Enc.Segment (Enc.Numeric, Groups, V), V);
         Check (Got (Groups), "every group of three digits");
      end;

      Parse_Raw (Enc.Bits (1, 4) & Enc.Bits (3, 10) & Enc.Bits (999, 10), 1);
      Check (Got ("999"), "ten bits: 999");
      Good := True;
      for G in 1000 .. 1023 loop
         Parse_Raw (Enc.Bits (1, 4) & Enc.Bits (3, 10) & Enc.Bits (G, 10), 1);
         Good := Good and then Refused;
      end loop;
      Check (Good, "ten bits: 1000 to 1023 are no three digits");

      Parse_Raw (Enc.Bits (1, 4) & Enc.Bits (2, 10) & Enc.Bits (99, 7), 1);
      Check (Got ("99"), "seven bits: 99");
      Good := True;
      for G in 100 .. 127 loop
         Parse_Raw (Enc.Bits (1, 4) & Enc.Bits (2, 10) & Enc.Bits (G, 7), 1);
         Good := Good and then Refused;
      end loop;
      Check (Good, "seven bits: 100 to 127 are no two digits");

      Parse_Raw (Enc.Bits (1, 4) & Enc.Bits (1, 10) & Enc.Bits (9, 4), 1);
      Check (Got ("9"), "four bits: 9");
      Good := True;
      for G in 10 .. 15 loop
         Parse_Raw (Enc.Bits (1, 4) & Enc.Bits (1, 10) & Enc.Bits (G, 4), 1);
         Good := Good and then Refused;
      end loop;
      Check (Good, "four bits: 10 to 15 are no digit");

      Parse_Raw
        (Enc.Bits (1, 4) & Enc.Bits (6, 10) & Enc.Bits (123, 10)
         & Enc.Bits (1000, 10),
         1);
      Check (Refused, "a wrong group after a good one: no text");
   end Test_Numeric;

   procedure Test_Alphanumeric is
      Good : Boolean := True;
      V    : QR.Version_Number;
   begin
      Section ("QR Code: the alphanumeric mode");

      for First in Set'Range loop
         declare
            T : String (1 .. 90);
         begin
            for K in 1 .. 45 loop
               T (2 * K - 1) := Set (First);
               T (2 * K) := Set (Set'First + K - 1);
            end loop;
            V := Enc.Smallest_Version (Enc.Alphanumeric, T, QR.L);
            Parse (Enc.Segment (Enc.Alphanumeric, T, V), V);
            Good := Good and then Got (T);
         end;
      end loop;
      Check (Good, "every pair of characters");

      Good := True;
      for K in Set'Range loop
         Parse (Enc.Segment (Enc.Alphanumeric, Set (K .. K), 1), 1);
         Good := Good and then Got (Set (K .. K));
      end loop;
      Check (Good, "every character by itself");

      Good := True;
      for N in 0 .. 12 loop
         declare
            T : constant String := Text_By_Chance (Enc.Alphanumeric, N);
         begin
            Parse (Enc.Segment (Enc.Alphanumeric, T, 1), 1);
            Good := Good and then Got (T);
         end;
      end loop;
      Check (Good, "0 to 12 characters");

      Parse_Raw (Enc.Bits (2, 4) & Enc.Bits (2, 9) & Enc.Bits (2024, 11), 1);
      Check (Got ("::"), "eleven bits: 2024");
      Good := True;
      for G in 2025 .. 2047 loop
         Parse_Raw (Enc.Bits (2, 4) & Enc.Bits (2, 9) & Enc.Bits (G, 11), 1);
         Good := Good and then Refused;
      end loop;
      Check (Good, "eleven bits: 2025 to 2047 are no two characters");

      Parse_Raw (Enc.Bits (2, 4) & Enc.Bits (1, 9) & Enc.Bits (44, 6), 1);
      Check (Got (":"), "six bits: 44");
      Good := True;
      for G in 45 .. 63 loop
         Parse_Raw (Enc.Bits (2, 4) & Enc.Bits (1, 9) & Enc.Bits (G, 6), 1);
         Good := Good and then Refused;
      end loop;
      Check (Good, "six bits: 45 to 63 are no character");
   end Test_Alphanumeric;

   procedure Test_Bytes_And_Kanji is
      Example_1 : constant String :=
        Character'Val (16#93#) & Character'Val (16#5F#);
      Example_2 : constant String :=
        Character'Val (16#E4#) & Character'Val (16#AA#);
      --  The two characters of the example of ISO/IEC 18004.

      Every : String (1 .. 256);
      Good  : Boolean := True;
      Count : Natural := 0;
      V     : QR.Version_Number;
   begin
      Section ("QR Code: the byte and the Kanji mode");

      for K in Every'Range loop
         Every (K) := Character'Val (K - 1);
      end loop;
      V := Enc.Smallest_Version (Enc.Bytes, Every, QR.L);
      Parse (Enc.Segment (Enc.Bytes, Every, V), V);
      Check (Got (Every), "every byte");

      for N in 0 .. 12 loop
         declare
            T : constant String := Text_By_Chance (Enc.Bytes, N);
         begin
            Parse (Enc.Segment (Enc.Bytes, T, 1), 1);
            Good := Good and then Got (T);
         end;
      end loop;
      Check (Good, "0 to 12 bytes");

      Check (Enc.Segment (Enc.Kanji, Example_1, 1)
             = Enc.Bits (8, 4) & Enc.Bits (1, 8) & Enc.Bits (16#D9F#, 13)
             and then Enc.Segment (Enc.Kanji, Example_2, 1)
                      = Enc.Bits (8, 4) & Enc.Bits (1, 8)
                        & Enc.Bits (16#1AAA#, 13),
             "the test's bits of the published characters 935F and E4AA");
      Parse_Raw
        (Enc.Bits (8, 4) & Enc.Bits (2, 8) & Enc.Bits (16#D9F#, 13)
         & Enc.Bits (16#1AAA#, 13),
         1);
      Check (Got (Example_1 & Example_2),
             "the published bits are the two characters");

      Good := True;
      for Lead in 16#81# .. 16#EB# loop
         if Lead <= 16#9F# or else Lead >= 16#E0# then
            declare
               Last : constant Natural :=
                 (if Lead = 16#EB# then 16#BF# else 16#FC#);
               T    : String (1 .. 2 * (Last - 16#40# + 1));
            begin
               for Trail in 16#40# .. Last loop
                  T (2 * (Trail - 16#40#) + 1) := Character'Val (Lead);
                  T (2 * (Trail - 16#40#) + 2) := Character'Val (Trail);
               end loop;
               V := Enc.Smallest_Version (Enc.Kanji, T, QR.L);
               Parse (Enc.Segment (Enc.Kanji, T, V), V);
               Good := Good and then Got (T);
               Count := Count + T'Length / 2;
            end;
         end if;
      end loop;
      Check (Good and then Count = 8066,
             "every character of the Kanji mode (" & Image (Count) & ")");

      Good := True;
      for G in 0 .. 8191 loop
         Parse_Raw (Enc.Bits (8, 4) & Enc.Bits (1, 8) & Enc.Bits (G, 13), 1);
         Good := Good and then OK and then Length = 2;
      end loop;
      Check (Good, "every value of thirteen bits is two bytes");
   end Test_Bytes_And_Kanji;

   procedure Test_Counts is
      type Width_Row is record
         Version : QR.Version_Number;
         Digit_Width, Letter_Width, Byte_Width, Kanji_Width : Positive;
      end record;

      Widths : constant array (1 .. 6) of Width_Row :=
        [(1, 10, 9, 8, 8), (9, 10, 9, 8, 8), (10, 12, 11, 16, 10),
         (26, 12, 11, 16, 10), (27, 14, 13, 16, 12), (40, 14, 13, 16, 12)];
      --  ISO/IEC 18004, the bits of the character count indicator.

      Kanji_Character : constant String :=
        Character'Val (16#93#) & Character'Val (16#5F#);

      Good : Boolean := True;
   begin
      Section ("QR Code: the counts of the segments");

      for W of Widths loop
         Parse_Raw
           (Enc.Bits (1, 4) & Enc.Bits (1, W.Digit_Width) & Enc.Bits (7, 4),
            W.Version);
         Good := Good and then Got ("7");
         Parse_Raw
           (Enc.Bits (2, 4) & Enc.Bits (1, W.Letter_Width)
            & Enc.Bits (10, 6),
            W.Version);
         Good := Good and then Got ("A");
         Parse_Raw
           (Enc.Bits (4, 4) & Enc.Bits (1, W.Byte_Width) & Enc.Bits (97, 8),
            W.Version);
         Good := Good and then Got ("a");
         Parse_Raw
           (Enc.Bits (8, 4) & Enc.Bits (1, W.Kanji_Width)
            & Enc.Bits (16#D9F#, 13),
            W.Version);
         Good := Good and then Got (Kanji_Character);
      end loop;
      Check (Good,
             "the published widths of the counts at the versions 1, 9, "
             & "10, 26, 27 and 40");

      Good := True;
      for W of Widths loop
         for Kind in Enc.Mode loop
            declare
               T : constant String := Text_By_Chance (Kind, 5);
            begin
               Parse (Enc.Segment (Kind, T, W.Version), W.Version);
               Good := Good and then Got (T);
            end;
         end loop;
      end loop;
      Check (Good, "five characters of every mode at these versions");

      Good := True;
      for Kind in Enc.Mode loop
         if Kind /= Enc.Bytes then
            declare
               T : constant String := Text_By_Chance (Kind, 5);
            begin
               Parse_Raw (Enc.Segment (Kind, T, 26), 27);
               Good := Good and then not Got (T);
            end;
         end if;
         declare
            T : constant String := Text_By_Chance (Kind, 5);
         begin
            Parse_Raw (Enc.Segment (Kind, T, 9), 10);
            Good := Good and then not Got (T);
         end;
      end loop;
      Check (Good,
             "a segment of the version 9 is not read as one of the "
             & "version 10, nor one of the version 26 as one of 27");
   end Test_Counts;

   ---------------------------------------------------------------------
   --  Where a message ends, and the other modes
   ---------------------------------------------------------------------

   procedure Test_Ends is
      One  : constant Enc.Bit_List := [1 => True];
      Five : constant Enc.Bit_List := Enc.Segment (Enc.Bytes, "abcde", 1);
      Good : Boolean;
   begin
      Section ("QR Code: the end of a message");

      Check (Enc.Segment (Enc.Numeric, "12345", 1)'Length = 31
             and then Enc.Segment (Enc.Alphanumeric, "AB:", 1)'Length = 30
             and then Enc.Segment (Enc.Numeric, "12", 1)'Length = 21
             and then Enc.Segment (Enc.Numeric, "123", 1)'Length = 24
             and then Enc.Segment (Enc.Numeric, "1234", 1)'Length = 28
             and then Five'Length = 52,
             "the bits of the test's segments");

      --  Fewer than four bits after a segment are no mode.
      Parse_Raw (Enc.Segment (Enc.Numeric, "12345", 1) & One, 1);
      Check (Got ("12345"), "one bit is left");
      Parse_Raw (Enc.Segment (Enc.Alphanumeric, "AB:", 1) & One & One, 1);
      Check (Got ("AB:"), "two bits are left");
      Parse_Raw (Enc.Segment (Enc.Numeric, "12", 1) & One & One & One, 1);
      Check (Got ("12"), "three bits are left");
      Parse_Raw (Enc.Segment (Enc.Numeric, "123", 1), 1);
      Check (Got ("123"), "no bit is left");
      Parse_Raw (Enc.Segment (Enc.Numeric, "1234", 1) & Enc.Bits (15, 4), 1);
      Check (Refused, "four bits are left, and they are no mode");
      Parse_Raw (Enc.Segment (Enc.Numeric, "1234", 1) & Enc.Bits (0, 4), 1);
      Check (Got ("1234"), "four zero bits are left: the end");
      Parse_Raw
        (Enc.Segment (Enc.Numeric, "1234", 1) & Enc.Bits (0, 4)
         & Enc.Bits (16#FFFF#, 16),
         1);
      Check (Got ("1234"), "what follows the end is not read");

      --  The symbol 1-L has 152 bits.
      declare
         A : constant String := Text_By_Chance (Enc.Alphanumeric, 25);
         N : constant String := Text_By_Chance (Enc.Numeric, 41);
         B : constant String := Text_By_Chance (Enc.Bytes, 17);
      begin
         Parse (Enc.Segment (Enc.Alphanumeric, A, 1), 1);
         Good := Got (A);
         Parse (Enc.Segment (Enc.Numeric, N, 1), 1);
         Check (Good and then Got (N),
                "151 bits of 152: one bit of the terminator");
         Parse (Enc.Segment (Enc.Bytes, B, 1), 1);
         Check (Got (B), "148 bits of 152: the terminator and no pad");
         Parse (Enc.FNC1_First & Enc.Segment (Enc.Bytes, B, 1), 1);
         Check (Got (B), "152 bits of 152: no terminator");
      end;

      --  Segments that say more than there is.
      Parse_Raw (Enc.Bits (1, 4) & Enc.Bits (6, 10) & Enc.Bits (123, 10), 1);
      Good := Refused;
      Parse_Raw (Enc.Bits (2, 4) & Enc.Bits (4, 9) & Enc.Bits (100, 11), 1);
      Good := Good and then Refused;
      Parse_Raw
        (Enc.Bits (4, 4) & Enc.Bits (10, 8)
         & Five (Five'First + 12 .. Five'Last),
         1);
      Good := Good and then Refused;
      Parse_Raw (Enc.Bits (8, 4) & Enc.Bits (2, 8) & Enc.Bits (0, 13), 1);
      Check (Good and then Refused,
             "fewer characters than the count says: no text");

      Good := True;
      for M in 1 .. 9 loop
         if M in 1 | 2 | 4 | 7 | 8 | 9 then
            Parse_Raw (Enc.Bits (M, 4) & Enc.Bits (0, 4), 1);
            Good := Good and then Refused;
         end if;
      end loop;
      Parse_Raw (Enc.Bits (3, 4) & Enc.Bits (0, 12), 1);
      Good := Good and then Refused;
      Parse_Raw (Enc.Bits (7, 4) & Enc.Bits (128, 8) & Enc.Bits (0, 4), 1);
      Good := Good and then Refused;
      Parse_Raw (Enc.Bits (7, 4) & Enc.Bits (192, 8) & Enc.Bits (0, 12), 1);
      Check (Good and then Refused,
             "a mode without all the bits that it takes: no text");

      Good := True;
      for M in 0 .. 15 loop
         if M in 6 | 10 .. 15 then
            Parse_Raw (Enc.Bits (M, 4) & Enc.Bits (0, 12), 1);
            Good := Good and then Refused;
         end if;
      end loop;
      Check (Good, "the modes 6 and 10 to 15 are none");
   end Test_Ends;

   procedure Test_Other_Modes is
      Kanji_Character : constant String :=
        Character'Val (16#93#) & Character'Val (16#5F#);

      Bytes_3 : constant Enc.Bit_List := Enc.Segment (Enc.Bytes, "abc", 1);
      Good    : Boolean;
   begin
      Section ("QR Code: several segments, ECI, FNC1, structured append");

      Parse
        (Enc.Segment (Enc.Numeric, "0123", 1)
         & Enc.Segment (Enc.Alphanumeric, "AB C", 1)
         & Enc.Segment (Enc.Bytes, "xyz", 1)
         & Enc.Segment (Enc.Kanji, Kanji_Character & Kanji_Character, 1),
         1);
      Check (Got ("0123AB Cxyz" & Kanji_Character & Kanji_Character),
             "a segment of every mode");
      Parse
        (Enc.Segment (Enc.Numeric, "", 1) & Bytes_3
         & Enc.Segment (Enc.Alphanumeric, "", 1)
         & Enc.Segment (Enc.Bytes, "", 1) & Enc.Segment (Enc.Kanji, "", 1)
         & Enc.Segment (Enc.Numeric, "7", 1),
         1);
      Check (Got ("abc7"), "segments without characters");
      Parse (No_Bits, 1);
      Check (OK and then Length = 0, "no segment: no characters");

      --  Extended channel interpretations.
      Check (Enc.ECI (26)'Length = 12 and then Enc.ECI (1000)'Length = 20
             and then Enc.ECI (20_000)'Length = 28
             and then Enc.ECI (999_999)'Length = 28,
             "the test's designators have one, two and three codewords");
      Parse (Enc.ECI (26) & Bytes_3, 1);
      Good := Got ("abc");
      Parse (Enc.ECI (1000) & Bytes_3, 1);
      Good := Good and then Got ("abc");
      Parse (Enc.ECI (20_000) & Bytes_3, 1);
      Good := Good and then Got ("abc");
      --  The first codeword of three: 192 above, 207 here.
      Parse (Enc.ECI (999_999) & Bytes_3, 1);
      Good := Good and then Got ("abc");
      Parse (Bytes_3 & Enc.ECI (899) & Bytes_3 & Enc.ECI (3), 1);
      Check (Good and then Got ("abcabc"), "the designators are passed over");
      Good := True;
      for First in 224 .. 255 loop
         Parse_Raw
           (Enc.Bits (7, 4) & Enc.Bits (First, 8) & Enc.Bits (0, 20), 1);
         Good := Good and then Refused;
      end loop;
      Check (Good, "a designator that begins with three one bits is none");

      --  FNC1 in the first position.
      Parse
        (Enc.FNC1_First & Enc.Segment (Enc.Alphanumeric, "A%B%%C", 1), 1);
      Check (Got ("A" & GS & "B%C"),
             "FNC1: a % is the separator, two are a %");
      Parse (Enc.FNC1_First & Enc.Segment (Enc.Alphanumeric, "AB%", 1), 1);
      Check (Got ("AB" & GS), "FNC1: a % at the end of a segment");
      Parse (Enc.FNC1_First & Enc.Segment (Enc.Alphanumeric, "%%%", 1), 1);
      Check (Got ("%" & GS), "FNC1: three %");
      Parse
        (Enc.FNC1_First & Enc.Segment (Enc.Alphanumeric, "A%", 1)
         & Enc.Segment (Enc.Alphanumeric, "%B", 1),
         1);
      Check (Got ("A" & GS & GS & "B"),
             "FNC1: the % of two segments are not one pair");
      Parse
        (Enc.FNC1_First & Enc.Segment (Enc.Bytes, "a%%b%", 1)
         & Enc.Segment (Enc.Numeric, "01", 1),
         1);
      Check (Got ("a%%b%01"), "FNC1: the % of a byte segment is a %");
      Parse (Enc.Segment (Enc.Alphanumeric, "A%B%%C", 1), 1);
      Check (Got ("A%B%%C"), "without FNC1 a % is a %");
      Parse
        (Enc.Segment (Enc.Alphanumeric, "A%", 1) & Enc.FNC1_First
         & Enc.Segment (Enc.Alphanumeric, "B%", 1),
         1);
      Check (Got ("A%B" & GS), "FNC1 acts on the segments after it");

      --  FNC1 in the second position.
      Good := True;
      for I in 0 .. 255 loop
         Parse
           (Enc.FNC1_Second (I) & Enc.Segment (Enc.Alphanumeric, "X%", 1),
            1);
         if I < 100 then
            Good := Good
              and then Got
                (Character'Val (Character'Pos ('0') + I / 10)
                 & Character'Val (Character'Pos ('0') + I mod 10)
                 & "X" & GS);
         elsif I in 165 .. 190 | 197 .. 222 then
            Good := Good and then Got (Character'Val (I - 100) & "X" & GS);
         else
            Good := Good and then Refused;
         end if;
      end loop;
      Check (Good,
             "FNC1 in the second position: two digits or a letter before "
             & "the text, and no other indicator");
      Parse (Enc.FNC1_Second (165), 1);
      Good := Got ("A");
      Parse (Enc.FNC1_Second (222), 1);
      Check (Good and then Got ("z"), "the letters from A to z");

      --  Structured append.
      Parse (Enc.Structured_Append (2, 5, 77) & Bytes_3, 1);
      Good := Got ("abc");
      Parse (Enc.Structured_Append (15, 15, 255) & Bytes_3, 1);
      Check (Good and then Got ("abc"),
             "the place among the symbols of a message is passed over");
   end Test_Other_Modes;

   procedure Test_Text_Room is
      Message : constant String := "0123456789ABCDEFGHIJ";
      Bits    : constant Enc.Bit_List :=
        Enc.Segment (Enc.Alphanumeric, Message, 1);
      Data    : constant QR.Codeword_Array :=
        Codewords_Of (Enc.Data_Codewords (Bits, 1, QR.L));
      Nothing : constant QR.Codeword_Array :=
        Codewords_Of (Enc.Data_Codewords (No_Bits, 1, QR.L));

      Long   : QR.Text_Buffer (1 .. 20);
      Short  : QR.Text_Buffer (1 .. 19);
      One    : QR.Text_Buffer (1 .. 1);
      Empty  : QR.Text_Buffer (1 .. 0);
      Len    : Natural;
      Fine   : Boolean;
      Good   : Boolean;
   begin
      Section ("QR Code: the room for the text");

      QR.To_Text (Data, 1, Long, Len, Fine);
      Check (Fine and then Len = 20 and then String (Long) = Message,
             "a buffer as long as the text");
      QR.To_Text (Data, 1, Short, Len, Fine);
      Good := not Fine and then Len = 0;
      QR.To_Text (Data, 1, One, Len, Fine);
      Good := Good and then not Fine and then Len = 0;
      QR.To_Text (Data, 1, Empty, Len, Fine);
      Check (Good and then not Fine and then Len = 0,
             "a shorter buffer: no text, and the length 0");
      QR.To_Text (Nothing, 1, Empty, Len, Fine);
      Check (Fine and then Len = 0,
             "a message without characters needs no room");

      --  One codeword, of every value: no error, and a length that
      --  the buffer has.
      Good := True;
      for V in 0 .. 255 loop
         declare
            Word : constant QR.Codeword_Array (1 .. 1) :=
              [1 => RS.Element (V)];
         begin
            for Version in QR.Version_Number loop
               QR.To_Text (Word, Version, One, Len, Fine);
               Good := Good and then Len <= 1
                       and then (Fine or else Len = 0);
            end loop;
         end;
      end loop;
      Check (Good, "one codeword of every value at every version");
   end Test_Text_Room;

   ---------------------------------------------------------------------
   --  Symbols
   ---------------------------------------------------------------------

   function Same_Text (Expected : String) return Boolean is
     (Success and then Length = Expected'Length
      and then String (Text (1 .. Length)) = Expected);
   --  The text read, however many codewords were changed.

   procedure Test_Round_Trips is
      Good   : Boolean := True;
      Count  : Natural := 0;
      Missed : Natural := 0;
   begin
      Section ("QR Code: symbols of every version, level and mask");

      for V in QR.Version_Number loop
         for L in QR.Level loop
            for Mask in QR.Mask_Pattern loop
               declare
                  Kind : constant Enc.Mode :=
                    Enc.Mode'Val ((V + QR.Level'Pos (L) + Mask) mod 4);
                  T    : constant String :=
                    Text_By_Chance (Kind, Capacity (Kind, V, L));
               begin
                  Read (Enc.Symbol (Enc.Segment (Kind, T, V), V, L, Mask), V);
                  Count := Count + 1;
                  if not Read_Is (T, 0) then
                     Missed := Missed + 1;
                     if Missed <= 5 then
                        Ada.Text_IO.Put_Line
                          ("  not read: version " & Image (V) & ", level "
                           & QR.Level'Image (L) & ", mask " & Image (Mask)
                           & ", " & Enc.Mode'Image (Kind));
                     end if;
                  end if;
               end;
            end loop;
         end loop;
      end loop;
      Check (Missed = 0 and then Count = 1280,
             "1280 symbols filled with one segment, the modes in turn ("
             & Image (Missed) & " not read)");

      declare
         T : constant String := Text_By_Chance (Enc.Numeric, 7089);
      begin
         Read
           (Enc.Symbol (Enc.Segment (Enc.Numeric, T, 40), 40, QR.L, 3), 40);
         Check (Read_Is (T, 0) and then Length = QR.Max_Text_Length,
                "the longest text: 7089 digits in the symbol 40-L");
      end;

      for V in QR.Version_Number loop
         for L in QR.Level loop
            declare
               Mask : constant QR.Mask_Pattern :=
                 (V + QR.Level'Pos (L)) mod 8;
               T    : constant String := "QR" & Image (V);
            begin
               Read (Enc.Symbol (Enc.Segment (Enc.Bytes, T, V), V, L, Mask),
                     V);
               Good := Good and then Read_Is (T, 0);
               Read (Enc.Symbol (No_Bits, V, L, Mask), V);
               Good := Good and then Read_Is ("", 0);
            end;
         end loop;
      end loop;
      Check (Good,
             "a short text and none, with pad codewords, in every version "
             & "and level");
   end Test_Round_Trips;

   procedure Test_Mirror is
      Good     : Boolean := True;
      Never    : Boolean := True;
      Refusals : Natural := 0;
   begin
      Section ("QR Code: symbols seen from behind");

      for V in QR.Version_Number loop
         declare
            L    : constant QR.Level := QR.Level'Val (V mod 4);
            T    : constant String :=
              Text_By_Chance (Enc.Bytes, Capacity (Enc.Bytes, V, L));
            Sym  : constant Enc.Module_Matrix :=
              Enc.Symbol (Enc.Segment (Enc.Bytes, T, V), V, L, V mod 8);
            Back : constant Enc.Module_Matrix := Enc.Transposed (Sym);
         begin
            Read (Back, V, Mirror => True);
            Good := Good and then Read_Is (T, 0);

            Read (Back, V, Mirror => False);
            Never := Never and then not Same_Text (T);
            if No_Read then
               Refusals := Refusals + 1;
            end if;

            Read (Sym, V, Mirror => True);
            Never := Never and then not Same_Text (T);
            if No_Read then
               Refusals := Refusals + 1;
            end if;
         end;
      end loop;
      Check (Good, "a symbol of every version, read as seen from behind");
      Check (Never,
             "read from the wrong side, none of them gives its text");
      Ada.Text_IO.Put_Line
        ("  from the wrong side: " & Image (Refusals) & " of 80 refused");
   end Test_Mirror;

   procedure Damage
     (Stream   : in out Enc.Byte_List;
      Block_Of : Enc.Number_List;
      Block    : Positive;
      Errors   : Natural);
   --  Errors codewords of the block, taken by chance, get another value.

   procedure Damage
     (Stream   : in out Enc.Byte_List;
      Block_Of : Enc.Number_List;
      Block    : Positive;
      Errors   : Natural)
   is
      Hit  : array (Stream'Range) of Boolean := [others => False];
      Done : Natural := 0;
      P    : Positive;
   begin
      while Done < Errors loop
         P := Stream'First + Random (Stream'Length);
         if Block_Of (P) = Block and then not Hit (P) then
            Hit (P) := True;
            Stream (P) := (Stream (P) + 1 + Random (255)) mod 256;
            Done := Done + 1;
         end if;
      end loop;
   end Damage;

   procedure Test_Correction is
      Good     : Boolean := True;
      Honest   : Boolean := True;
      Certain  : Boolean := True;
      Refusals : Natural := 0;
      Tried    : Natural := 0;
      Sure     : Natural := 0;
   begin
      Section ("QR Code: wrong codewords");

      for V in QR.Version_Number loop
         for L in QR.Level loop
            declare
               Mask     : constant QR.Mask_Pattern :=
                 (V + QR.Level'Pos (L)) mod 8;
               T        : constant String :=
                 Text_By_Chance (Enc.Bytes, Capacity (Enc.Bytes, V, L));
               Clean    : constant Enc.Byte_List :=
                 Enc.Stream
                   (Enc.Data_Codewords (Enc.Segment (Enc.Bytes, T, V), V, L),
                    V, L);
               Block_Of : constant Enc.Number_List :=
                 Enc.Blocks_Of_Places (V, L);
               NB       : constant Positive := Enc.Block_Count (V, L);
               Limit    : constant Positive := QR.Correctable (V, L);
               Checks   : constant Positive := QR.Blocks (V, L).Check;
               Hurt     : Enc.Byte_List := Clean;
               Worst    : Positive;
            begin
               --  As many wrong codewords in every block as are
               --  corrected.
               for B in 1 .. NB loop
                  Damage (Hurt, Block_Of, B, Limit);
               end loop;
               Read (Enc.Modules (Hurt, V, L, Mask), V);
               if not Read_Is (T, NB * Limit) then
                  Good := False;
                  Ada.Text_IO.Put_Line
                    ("  not corrected: version " & Image (V) & ", level "
                     & QR.Level'Image (L));
               end if;

               --  One more in one of the blocks. Nothing but the right
               --  block is within Limit + 1 codewords of what is read
               --  if the check codewords are odd in number, or if Limit
               --  is less than half of them: then the symbol is refused.
               --  Otherwise another block may be near enough, and then
               --  the text is another.
               for Round in 1 .. 2 loop
                  Hurt := Clean;
                  Worst := 1 + Random (NB);
                  for B in 1 .. NB loop
                     Damage
                       (Hurt, Block_Of, B,
                        (if B = Worst then Limit + 1
                         else Random (Limit + 1)));
                  end loop;
                  Read (Enc.Modules (Hurt, V, L, Mask), V);
                  Tried := Tried + 1;
                  if No_Read then
                     Refusals := Refusals + 1;
                  elsif Same_Text (T) or else not Success then
                     Honest := False;
                  end if;
                  if Checks mod 2 = 1 or else Limit < Checks / 2 then
                     Sure := Sure + 1;
                     Certain := Certain and then No_Read;
                  end if;
               end loop;
            end;
         end loop;
      end loop;
      Check (Good,
             "160 symbols with as many wrong codewords in every block as "
             & "are corrected");
      Check (Honest,
             "one wrong codeword more in a block: never the text");
      Check (Certain and then Sure > 0,
             "and no text at all where no other block can be near ("
             & Image (Sure) & " symbols)");
      Ada.Text_IO.Put_Line
        ("  one wrong codeword more: " & Image (Refusals) & " of "
         & Image (Tried) & " refused");
   end Test_Correction;

   procedure Test_Chance is
      Grid    : QR.Module_Grid;
      Small   : QR.Text_Buffer (1 .. 10);
      One     : QR.Text_Buffer (1 .. 1);
      Empty   : QR.Text_Buffer (1 .. 0);
      Len     : Natural;
      Fixed   : Natural;
      Fine    : Boolean;
      Good    : Boolean := True;
      Agree   : Boolean := True;
      Seen    : Natural := 0;
      Texts   : Natural := 0;
      Tried   : Natural := 0;

      procedure Again (Buffer : out QR.Text_Buffer; V : QR.Version_Number);
      --  The same reading with another buffer: it gives the text if and
      --  only if the buffer holds it.

      procedure Again (Buffer : out QR.Text_Buffer; V : QR.Version_Number) is
      begin
         QR.Decode (Grid, V, False, Field, Buffer, Len, Fixed, Fine);
         Good := Good and then Len <= Buffer'Length
                 and then Fixed <= QR.Max_Codewords
                 and then (Fine or else (Len = 0 and then Fixed = 0));
         Agree := Agree
           and then Fine = (Success and then Length <= Buffer'Length)
           and then (not Fine
                     or else (Len = Length and then Fixed = Corrected
                              and then String (Buffer (1 .. Len))
                                       = String (Text (1 .. Len))));
      end Again;
   begin
      Section ("QR Code: modules and codewords by chance");

      for V in QR.Version_Number loop
         for Round in 1 .. 2 loop
            for R in QR.Module_Index loop
               for C in QR.Module_Index loop
                  Grid (R, C) := Random (2) = 1;
               end loop;
            end loop;
            for Mirror in Boolean loop
               QR.Decode
                 (Grid, V, Mirror, Field, Text, Length, Corrected, Success);
               Good := Good and then Length <= Text'Length
                       and then Corrected <= QR.Max_Codewords
                       and then (Success
                                 or else (Length = 0
                                          and then Corrected = 0));
               if Success then
                  Seen := Seen + 1;
               end if;
            end loop;
         end loop;
      end loop;
      Check (Good, "modules by chance: no error, and nothing but a text");
      Check (Seen = 0,
             "modules by chance: no text in 160 grids, either side");

      --  Codewords by chance in good blocks: To_Text has what a symbol
      --  cannot say on purpose.
      Good := True;
      for V in QR.Version_Number loop
         for L in QR.Level loop
            for Round in 1 .. 4 loop
               declare
                  Data : Enc.Byte_List (1 .. Enc.Data_Count (V, L));
               begin
                  for D of Data loop
                     D := Random (256);
                  end loop;
                  Grid := Enc.Grid
                    (Enc.Modules (Enc.Stream (Data, V, L), V, L, Round));
               end;
               QR.Decode
                 (Grid, V, False, Field, Text, Length, Corrected, Success);
               Tried := Tried + 1;
               Good := Good and then Corrected = 0
                       and then (Success or else Length = 0);
               if Success then
                  Texts := Texts + 1;
               end if;
               Again (Small, V);
               Again (One, V);
               Again (Empty, V);
            end loop;
         end loop;
      end loop;
      Check (Good, "codewords by chance: no error, a text or none");
      Check (Agree,
             "with a buffer of 10, 1 and 0 characters: the same text if "
             & "the buffer holds it, and none otherwise");
      Ada.Text_IO.Put_Line
        ("  codewords by chance: " & Image (Texts) & " of " & Image (Tried)
         & " are a message");
   end Test_Chance;

   procedure Test_Format is
      Words : array (QR.Level, QR.Mask_Pattern) of Natural;
      Far   : Natural := 0;
      Found : Boolean := False;
      Apart : Natural;

      Three    : Boolean := True;
      One_Copy : Boolean := True;
      Four     : Boolean := True;
      None     : Boolean := True;
      Refusals : Natural := 0;
   begin
      Section ("QR Code: wrong bits in the format information");

      for L in QR.Level loop
         for Mask in QR.Mask_Pattern loop
            Words (L, Mask) := Enc.Format_Word (L, Mask);
         end loop;
      end loop;

      --  A word that is no format information, however it is read: four
      --  bits at least from every one. (The inverse of a word is
      --  another word, so it would not do.)
      for W in 0 .. 2 ** 15 - 1 loop
         Apart := 15;
         for Word of Words loop
            Apart := Natural'Min (Apart, Distance (W, Word));
         end loop;
         if Apart >= 4 then
            Far := W;
            Found := True;
            exit;
         end if;
      end loop;
      Check (Found, "there is a word four bits from every format word");
      Check (Distance (Words (QR.M, 0), 2 ** 15 - 1 - Words (QR.M, 0)) = 15
             and then (for some Word of Words =>
                         Word = 2 ** 15 - 1 - Words (QR.M, 0)),
             "the inverse of a format word is a format word");

      for L in QR.Level loop
         for Mask in QR.Mask_Pattern loop
            declare
               V    : constant QR.Version_Number :=
                 1 + (5 * QR.Level'Pos (L) + 3 * Mask) mod 40;
               T    : constant String :=
                 Text_By_Chance (Enc.Bytes, Capacity (Enc.Bytes, V, L));
               Word : constant Natural := Words (L, Mask);
               Sym  : constant Enc.Module_Matrix :=
                 Enc.Symbol (Enc.Segment (Enc.Bytes, T, V), V, L, Mask);
               Hurt : Enc.Module_Matrix := Sym;
            begin
               Enc.Put_Format (Hurt, 1, Flipped (Word, 15, 3));
               Enc.Put_Format (Hurt, 2, Flipped (Word, 15, 3));
               Read (Hurt, V);
               Three := Three and then Read_Is (T, 0);

               Hurt := Sym;
               Enc.Put_Format (Hurt, 1, Far);
               Enc.Put_Format (Hurt, 2, Flipped (Word, 15, 3));
               Read (Hurt, V);
               One_Copy := One_Copy and then Read_Is (T, 0);

               Hurt := Sym;
               Enc.Put_Format (Hurt, 1, Flipped (Word, 15, 3));
               Enc.Put_Format (Hurt, 2, Far);
               Read (Hurt, V);
               One_Copy := One_Copy and then Read_Is (T, 0);

               Hurt := Sym;
               Enc.Put_Format (Hurt, 1, Flipped (Word, 15, 4));
               Enc.Put_Format (Hurt, 2, Flipped (Word, 15, 4));
               Read (Hurt, V);
               Four := Four and then not Same_Text (T);
               if No_Read then
                  Refusals := Refusals + 1;
               end if;

               Hurt := Sym;
               Enc.Put_Format (Hurt, 1, Far);
               Enc.Put_Format (Hurt, 2, Far);
               Read (Hurt, V);
               None := None and then No_Read;
            end;
         end loop;
      end loop;
      Check (Three,
             "every level and mask with three wrong bits in both copies");
      Check (One_Copy,
             "one copy destroyed and three wrong bits in the other");
      Check (Four, "four wrong bits in both copies: never the text");
      Check (None, "both copies destroyed: no text");
      Ada.Text_IO.Put_Line
        ("  four wrong bits in both copies: " & Image (Refusals)
         & " of 32 refused");
   end Test_Format;

   procedure Test_Version_Information is
      Three    : Boolean := True;
      One_Copy : Boolean := True;
      Edge     : Boolean := True;
      Four     : Boolean := True;
      Beside   : Boolean := True;
      Refusals : Natural := 0;
      Tried    : Natural := 0;
   begin
      Section ("QR Code: wrong bits in the version information");

      for V in 7 .. QR.Max_Version loop
         declare
            L    : constant QR.Level := QR.Level'Val (V mod 4);
            T    : constant String :=
              Text_By_Chance (Enc.Bytes, Capacity (Enc.Bytes, V, L));
            Word : constant Natural := Enc.Version_Word (V);
            Sym  : constant Enc.Module_Matrix :=
              Enc.Symbol (Enc.Segment (Enc.Bytes, T, V), V, L, V mod 8);
            Hurt : Enc.Module_Matrix := Sym;
         begin
            Enc.Put_Version (Hurt, 1, Flipped (Word, 18, 3));
            Enc.Put_Version (Hurt, 2, Flipped (Word, 18, 3));
            Read (Hurt, V);
            Three := Three and then Read_Is (T, 0);

            Hurt := Sym;
            Enc.Put_Version (Hurt, 1, Flipped (Word, 18, 4));
            Read (Hurt, V);
            One_Copy := One_Copy and then Read_Is (T, 0);

            Hurt := Sym;
            Enc.Put_Version (Hurt, 2, 2 ** 18 - 1 - Word);
            Read (Hurt, V);
            One_Copy := One_Copy and then Read_Is (T, 0);

            --  One copy at the limit, the other beyond it: each copy
            --  is taken with three wrong bits, whatever the other says.
            Hurt := Sym;
            Enc.Put_Version (Hurt, 1, Flipped (Word, 18, 3));
            Enc.Put_Version (Hurt, 2, Flipped (Word, 18, 4));
            Read (Hurt, V);
            Edge := Edge and then Read_Is (T, 0);

            Hurt := Sym;
            Enc.Put_Version (Hurt, 1, Flipped (Word, 18, 4));
            Enc.Put_Version (Hurt, 2, Flipped (Word, 18, 3));
            Read (Hurt, V);
            Edge := Edge and then Read_Is (T, 0);

            Hurt := Sym;
            Enc.Put_Version (Hurt, 1, Flipped (Word, 18, 4));
            Enc.Put_Version (Hurt, 2, Flipped (Word, 18, 4));
            Read (Hurt, V);
            Four := Four and then No_Read;

            --  The modules of the symbol taken for those of the
            --  versions beside its own.
            for Other in V - 1 .. V + 1 loop
               if Other /= V and then Other <= QR.Max_Version then
                  Read (Sym, Other);
                  Tried := Tried + 1;
                  Beside := Beside and then not Same_Text (T);
                  if No_Read then
                     Refusals := Refusals + 1;
                  end if;
               end if;
            end loop;
         end;
      end loop;
      Check (Three,
             "the versions 7 to 40 with three wrong bits in both copies");
      Check (One_Copy,
             "one copy with four wrong bits, or inverted, the other whole");
      Check (Edge, "three wrong bits in one copy and four in the other");
      Check (Four, "four wrong bits in both copies: no text");
      Check (Beside,
             "read as the version before or after its own: never the text");
      Ada.Text_IO.Put_Line
        ("  read as another version: " & Image (Refusals) & " of "
         & Image (Tried) & " refused");
   end Test_Version_Information;

   procedure Test_Decode_Room is
      Message : constant String := "abcdefghijklmnopqrst";
      Sym     : constant Enc.Module_Matrix :=
        Enc.Symbol (Enc.Segment (Enc.Bytes, Message, 2), 2, QR.M, 5);
      Grid    : constant QR.Module_Grid := Enc.Grid (Sym);
      Nothing : constant QR.Module_Grid :=
        Enc.Grid (Enc.Symbol (No_Bits, 1, QR.L));

      Long  : QR.Text_Buffer (1 .. 20);
      Short : QR.Text_Buffer (1 .. 19);
      Empty : QR.Text_Buffer (1 .. 0);
      Len   : Natural;
      Fixed : Natural;
      Fine  : Boolean;
   begin
      Section ("QR Code: the room for the text of a symbol");

      QR.Decode (Grid, 2, False, Field, Long, Len, Fixed, Fine);
      Check (Fine and then Len = 20 and then Fixed = 0
             and then String (Long) = Message,
             "a buffer as long as the text");
      QR.Decode (Grid, 2, False, Field, Short, Len, Fixed, Fine);
      Check (not Fine and then Len = 0 and then Fixed = 0,
             "a buffer one character shorter: no text");
      QR.Decode (Grid, 2, False, Field, Empty, Len, Fixed, Fine);
      Check (not Fine and then Len = 0 and then Fixed = 0,
             "no buffer: no text");
      QR.Decode (Nothing, 1, False, Field, Empty, Len, Fixed, Fine);
      Check (Fine and then Len = 0 and then Fixed = 0,
             "a symbol without characters needs no room");

      --  With wrong codewords that are corrected, the text that does
      --  not fit is no text, and no codeword counts as changed.
      declare
         Hurt : Enc.Byte_List :=
           Enc.Stream
             (Enc.Data_Codewords
                (Enc.Segment (Enc.Bytes, Message, 2), 2, QR.M),
              2, QR.M);
      begin
         Damage (Hurt, Enc.Blocks_Of_Places (2, QR.M), 1, 5);
         declare
            G : constant QR.Module_Grid :=
              Enc.Grid (Enc.Modules (Hurt, 2, QR.M, 5));
         begin
            QR.Decode (G, 2, False, Field, Long, Len, Fixed, Fine);
            Check (Fine and then Len = 20 and then Fixed = 5
                   and then String (Long) = Message,
                   "five wrong codewords: the text, and 5 changed");
            QR.Decode (G, 2, False, Field, Short, Len, Fixed, Fine);
            Check (not Fine and then Len = 0 and then Fixed = 0,
                   "the same with the shorter buffer: no text, 0 changed");
         end;
      end;
   end Test_Decode_Room;

   procedure Run_All is
   begin
      Test_Tables;
      Test_Numeric;
      Test_Alphanumeric;
      Test_Bytes_And_Kanji;
      Test_Counts;
      Test_Ends;
      Test_Other_Modes;
      Test_Text_Room;
      Test_Round_Trips;
      Test_Mirror;
      Test_Correction;
      Test_Chance;
      Test_Format;
      Test_Version_Information;
      Test_Decode_Room;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Code_Reader_QR_Symbol;
