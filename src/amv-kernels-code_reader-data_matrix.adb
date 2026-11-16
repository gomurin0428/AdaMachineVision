pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package body AMV.Kernels.Code_Reader.Data_Matrix with SPARK_Mode is

   use type RS.Element;

   ---------------------------------------------------------------------
   --  The sizes
   ---------------------------------------------------------------------

   Max_Mapping : constant := 144;
   --  A bound of the modules along a side of the mapping matrix, from
   --  the ranges of Size_Info (the largest mapping matrix has 132).

   subtype Mapping_Side is Positive range 6 .. Max_Mapping;
   subtype Mapping_Index is Natural range 0 .. Max_Mapping - 1;

   --  The three functions below are not expression functions, so that
   --  the proof of a caller gets their bounds and not the table.

   function Mapping_Rows (Size : Size_Index) return Mapping_Side;
   function Mapping_Columns (Size : Size_Index) return Mapping_Side;
   --  The modules of the mapping matrix.

   function Codewords (Size : Size_Index) return Codeword_Index;
   --  The codewords of the size, data and check.

   function Mapping_Rows (Size : Size_Index) return Mapping_Side is
   begin
      return Sizes (Size).Region_Rows * Sizes (Size).Regions_Down;
   end Mapping_Rows;

   function Mapping_Columns (Size : Size_Index) return Mapping_Side is
   begin
      return Sizes (Size).Region_Columns * Sizes (Size).Regions_Across;
   end Mapping_Columns;

   function Codewords (Size : Size_Index) return Codeword_Index is
   begin
      return Sizes (Size).Data + Sizes (Size).Check;
   end Codewords;

   ---------------
   -- Find_Size --
   ---------------

   function Find_Size (Rows, Columns : Integer) return Natural is
   begin
      for S in Size_Index loop
         if Sizes (S).Rows = Rows and then Sizes (S).Columns = Columns then
            return S;
         end if;
      end loop;
      return 0;
   end Find_Size;

   ---------------------------------------------------------------------
   --  The places of the codewords
   ---------------------------------------------------------------------

   type Used_Map is array (Mapping_Index, Mapping_Index) of Boolean;
   --  The modules of the mapping matrix that have a codeword.

   subtype Near is Integer range -2 .. Max_Mapping - 1;
   --  A row or column of the mapping matrix, or one of the two before
   --  the first, which stand for places on the other side of it.

   function In_Symbol
     (M      : Mapping_Index;
      Region : Positive) return Natural
   with Post => In_Symbol'Result > M;
   --  From a row or column of the mapping matrix to that of the symbol:
   --  each region before this one adds the two modules of its border,
   --  and this one adds one. Region: the modules of a region.

   function In_Symbol
     (M      : Mapping_Index;
      Region : Positive) return Natural is
   begin
      return M + 1 + 2 * (M / Region);
   end In_Symbol;

   procedure Put_Module
     (Size         : Size_Index;
      N_Row, N_Col : Mapping_Side;
      Row, Col     : Near;
      Chr          : Codeword_Index;
      Bit          : Bit_Index;
      Map          : in out Placement;
      Used         : in out Used_Map;
      Good         : in out Boolean)
   with Post => (if Good then Good'Old);
   --  Gives the module (Row, Col) of the mapping matrix to the bit Bit
   --  of the codeword Chr. A row or column before the first wraps to
   --  the other side, shifted as the symbology defines. Good becomes
   --  False if the module is then not in the matrix.

   procedure Put_Module
     (Size         : Size_Index;
      N_Row, N_Col : Mapping_Side;
      Row, Col     : Near;
      Chr          : Codeword_Index;
      Bit          : Bit_Index;
      Map          : in out Placement;
      Used         : in out Used_Map;
      Good         : in out Boolean)
   is
      R      : Integer := Row;
      C      : Integer := Col;
      SR, SC : Natural;
   begin
      if R < 0 then
         R := R + N_Row;
         C := C + 4 - ((N_Row + 4) mod 8);
      end if;
      if C < 0 then
         C := C + N_Col;
         R := R + 4 - ((N_Col + 4) mod 8);
      end if;

      if R not in 0 .. N_Row - 1 or else C not in 0 .. N_Col - 1 then
         Good := False;
         return;
      end if;

      SR := In_Symbol (R, Sizes (Size).Region_Rows);
      SC := In_Symbol (C, Sizes (Size).Region_Columns);

      if SR > Max_Side - 1 or else SC > Max_Side - 1 then
         Good := False;
         return;
      end if;

      Used (R, C) := True;
      Map (Chr, Bit) :=
        (Row => Module_Index (SR), Column => Module_Index (SC));
   end Put_Module;

   procedure Utah
     (Size         : Size_Index;
      N_Row, N_Col : Mapping_Side;
      Row, Col     : Mapping_Index;
      Chr          : Codeword_Index;
      Map          : in out Placement;
      Used         : in out Used_Map;
      Good         : in out Boolean)
   with Post => (if Good then Good'Old);
   --  The usual shape of a codeword, named after the state: the module
   --  (Row, Col) is its last bit.

   procedure Utah
     (Size         : Size_Index;
      N_Row, N_Col : Mapping_Side;
      Row, Col     : Mapping_Index;
      Chr          : Codeword_Index;
      Map          : in out Placement;
      Used         : in out Used_Map;
      Good         : in out Boolean)
   is
      type Offset is record
         Row, Col : Integer range -2 .. 0;
      end record;

      Shape : constant array (Bit_Index) of Offset :=
        [(-2, -2), (-2, -1), (-1, -2), (-1, -1), (-1, 0), (0, -2),
         (0, -1), (0, 0)];
   begin
      for Bit in Bit_Index loop
         Put_Module
           (Size, N_Row, N_Col, Row + Shape (Bit).Row,
            Col + Shape (Bit).Col, Chr, Bit, Map, Used, Good);
      end loop;
   end Utah;

   subtype Corner_Index is Positive range 1 .. 4;

   procedure Corner
     (Which        : Corner_Index;
      Size         : Size_Index;
      N_Row, N_Col : Mapping_Side;
      Chr          : Codeword_Index;
      Map          : in out Placement;
      Used         : in out Used_Map;
      Good         : in out Boolean)
   with Post => (if Good then Good'Old);
   --  The four shapes of the codeword that lies across the corners.

   procedure Corner
     (Which        : Corner_Index;
      Size         : Size_Index;
      N_Row, N_Col : Mapping_Side;
      Chr          : Codeword_Index;
      Map          : in out Placement;
      Used         : in out Used_Map;
      Good         : in out Boolean)
   is
      type Module is record
         Row, Col : Integer range -4 .. 3;
      end record;
      --  Below 0: counted from the last row or column, which is -1.

      type Shape is array (Bit_Index) of Module;

      Shapes : constant array (Corner_Index) of Shape :=
        [1 => [(-1, 0), (-1, 1), (-1, 2), (0, -2), (0, -1), (1, -1),
               (2, -1), (3, -1)],
         2 => [(-3, 0), (-2, 0), (-1, 0), (0, -4), (0, -3), (0, -2),
               (0, -1), (1, -1)],
         3 => [(-3, 0), (-2, 0), (-1, 0), (0, -2), (0, -1), (1, -1),
               (2, -1), (3, -1)],
         4 => [(-1, 0), (-1, -1), (0, -3), (0, -2), (0, -1), (1, -3),
               (1, -2), (1, -1)]];

      M : Module;
   begin
      for Bit in Bit_Index loop
         M := Shapes (Which) (Bit);
         Put_Module
           (Size, N_Row, N_Col,
            (if M.Row < 0 then N_Row + M.Row else M.Row),
            (if M.Col < 0 then N_Col + M.Col else M.Col),
            Chr, Bit, Map, Used, Good);
      end loop;
   end Corner;

   -----------
   -- Place --
   -----------

   procedure Place
     (Size  : Size_Index;
      Map   : out Placement;
      Count : out Codeword_Count;
      OK    : out Boolean)
   is
      Max_Passes : constant := 40;
      --  More than any size needs: a pass moves eight places along the
      --  two sides together.

      N_Row : constant Mapping_Side := Mapping_Rows (Size);
      N_Col : constant Mapping_Side := Mapping_Columns (Size);
      Total : constant Codeword_Index := Codewords (Size);

      Used : Used_Map := [others => [others => False]];
      Good : Boolean := True;
      Done : Boolean := False;

      --  The place of the last bit of the next codeword. It moves as
      --  the symbology defines: up and to the right in steps of two,
      --  then down and to the left, and so on; the places that are not
      --  in the matrix or are taken are passed over.
      Row : Integer := 4;
      Col : Integer := 0;

      procedure Next_Utah
      with
        Global => (Input  => (Size, N_Row, N_Col, Total, Row, Col),
                   In_Out => (Map, Used, Good, Count)),
        Pre    => Count <= Total,
        Post   => Count <= Total;
      --  Places a codeword of the usual shape at (Row, Col), if that
      --  module is in the matrix and free.

      procedure Next_Utah is
      begin
         if Row in 0 .. N_Row - 1 and then Col in 0 .. N_Col - 1
           and then not Used (Row, Col)
         then
            if Count < Total then
               Count := Count + 1;
               Utah (Size, N_Row, N_Col, Row, Col, Count, Map, Used, Good);
            else
               Good := False;
            end if;
         end if;
      end Next_Utah;

      procedure Next_Corner (Which : Corner_Index)
      with
        Global => (Input  => (Size, N_Row, N_Col, Total),
                   In_Out => (Map, Used, Good, Count)),
        Pre    => Count <= Total,
        Post   => Count <= Total;

      procedure Next_Corner (Which : Corner_Index) is
      begin
         if Count < Total then
            Count := Count + 1;
            Corner (Which, Size, N_Row, N_Col, Count, Map, Used, Good);
         else
            Good := False;
         end if;
      end Next_Corner;

   begin
      Map := [others => [others => (0, 0)]];
      Count := 0;

      for Pass in 1 .. Max_Passes loop
         pragma Loop_Invariant (Row + Col = 8 * Pass - 4);
         pragma Loop_Invariant (Row >= 4 and then Col >= -1);
         pragma Loop_Invariant (Count <= Total);

         if Col = 0 then
            if Row = N_Row then
               Next_Corner (1);
            elsif Row = N_Row - 2 and then N_Col mod 4 /= 0 then
               Next_Corner (2);
            elsif Row = N_Row - 2 and then N_Col mod 8 = 4 then
               Next_Corner (3);
            end if;
         elsif Col = 2 and then Row = N_Row + 4 and then N_Col mod 8 = 0
         then
            Next_Corner (4);
         end if;

         loop
            Next_Utah;
            Row := Row - 2;
            Col := Col + 2;
            pragma Loop_Invariant (Row + Col = 8 * Pass - 4);
            pragma Loop_Invariant (Row >= -2 and then Col >= 1);
            pragma Loop_Invariant (Count <= Total);
            pragma Loop_Variant (Decreases => Row);
            exit when Row < 0 or else Col >= N_Col;
         end loop;

         Row := Row + 1;
         Col := Col + 3;

         loop
            Next_Utah;
            Row := Row + 2;
            Col := Col - 2;
            pragma Loop_Invariant (Row + Col = 8 * Pass);
            pragma Loop_Invariant (Row >= 1 and then Col >= -2);
            pragma Loop_Invariant (Count <= Total);
            pragma Loop_Variant (Decreases => Col);
            exit when Row >= N_Row or else Col < 0;
         end loop;

         Row := Row + 3;
         Col := Col + 1;

         if Row >= N_Row and then Col >= N_Col then
            Done := True;
            exit;
         end if;
      end loop;

      OK := Good and then Done and then Count = Total;
   end Place;

   ---------------------------------------------------------------------
   --  The codewords
   ---------------------------------------------------------------------

   subtype Stream is Codeword_Array (Codeword_Index);
   --  The codewords in the order of their places: those of the message,
   --  then the check codewords.

   procedure Read_Codewords
     (Grid  : Module_Grid;
      Map   : Placement;
      Total : Codeword_Index;
      Words : out Stream);
   --  The codewords 1 .. Total of the symbol.

   procedure Read_Codewords
     (Grid  : Module_Grid;
      Map   : Placement;
      Total : Codeword_Index;
      Words : out Stream)
   is
      V : RS.Element;
   begin
      Words := [others => 0];
      for I in 1 .. Total loop
         V := 0;
         for Bit in Bit_Index loop
            V := V * 2;
            if Grid (Map (I, Bit).Row, Map (I, Bit).Column) then
               V := V + 1;
            end if;
         end loop;
         Words (I) := V;
      end loop;
   end Read_Codewords;

   procedure Correct_Blocks
     (Size      : Size_Index;
      Field     : RS.Field;
      Words     : in out Stream;
      Corrected : out Natural;
      Success   : out Boolean)
   with Post => Corrected <= Max_Codewords;
   --  Corrects the codewords block by block. Codeword P belongs to the
   --  block (P - 1) mod Blocks + 1: the blocks take the codewords of the
   --  message in turn and then the check codewords in turn, and every
   --  block has the same number of check codewords.

   procedure Correct_Blocks
     (Size      : Size_Index;
      Field     : RS.Field;
      Words     : in out Stream;
      Corrected : out Natural;
      Success   : out Boolean)
   is
      Total  : constant Codeword_Index := Codewords (Size);
      Blocks : constant Positive := Sizes (Size).Blocks;
      Parity : constant Natural := Sizes (Size).Check / Blocks;

      Word  : RS.Word (RS.Word_Index) := [others => 0];
      N     : Natural;
      K     : Natural;
      Fixed : Natural;
      Good  : Boolean;
   begin
      Corrected := 0;
      Success := False;

      for B in 1 .. Blocks loop
         pragma Loop_Invariant (Corrected <= (B - 1) * 127);

         N := 0;
         for P in B .. Total loop
            pragma Loop_Invariant (N <= P - B);
            if (P - B) mod Blocks = 0 then
               N := N + 1;
               if N <= RS.Max_Length then
                  Word (N) := Words (P);
               end if;
            end if;
         end loop;

         --  Cannot be for the sizes of the symbology: a block has more
         --  codewords than check codewords, and no more than a word of
         --  the code can have.
         if Parity = 0 or else N <= Parity or else N > RS.Max_Length then
            return;
         end if;

         RS.Correct (Field, Word (1 .. N), Parity, 1, Fixed, Good);
         if not Good then
            return;
         end if;

         K := 0;
         for P in B .. Total loop
            pragma Loop_Invariant (K <= N);
            if (P - B) mod Blocks = 0 and then K < N then
               K := K + 1;
               Words (P) := Word (K);
            end if;
         end loop;

         Corrected := Corrected + Fixed;
      end loop;

      Success := True;
   end Correct_Blocks;

   -------------
   -- To_Text --
   -------------

   procedure To_Text
     (Data   : Codeword_Array;
      Text   : out Text_Buffer;
      Length : out Natural;
      OK     : out Boolean)
   is
      type Encodation is (ASCII, C40, Lower, X12, EDIFACT, Base_256);
      --  Lower: the Text encodation.

      subtype Value_40 is Natural range 0 .. 39;
      --  A value of the C40, Text and X12 encodations.

      N : constant Codeword_Index := Data'Last;

      Mode  : Encodation := ASCII;
      Pos   : Positive := 1;
      --  The next codeword.
      Len   : Natural := 0;
      Good  : Boolean := True;
      Ended : Boolean := False;
      --  A pad codeword: the message ends before the data codewords do.
      Upper : Boolean := False;
      --  The upper shift: the next character is 128 more.
      Shift : Natural range 0 .. 3 := 0;
      --  The set of the next C40 or Text value.
      Macro : Boolean := False;
      Left  : Natural;

      function Valid return Boolean is
        (Data'First = 1 and then N = Data'Last and then Text'First = 1
         and then Len <= Text'Last);
      --  What the steps below rely on and keep.

      procedure Put (Code : Natural)
      with
        Pre  => Valid,
        Post => Valid;
      --  Adds the character Code to the text.

      procedure Put (Code : Natural) is
      begin
         if Code > 255 or else Len >= Text'Last then
            Good := False;
         else
            Len := Len + 1;
            Text (Len) := Character'Val (Code);
         end if;
      end Put;

      procedure Put_Char (Code : Natural)
      with
        Pre  => Valid and then Code <= 255,
        Post => Valid;
      --  The same, for a character that the upper shift applies to.

      procedure Put_Char (Code : Natural) is
      begin
         if Upper then
            Upper := False;
            Put (Code + 128);
         else
            Put (Code);
         end if;
      end Put_Char;

      procedure Latch (To : Encodation);
      --  The shifts do not last beyond their encodation.

      procedure Latch (To : Encodation) is
      begin
         Mode := To;
         Upper := False;
         Shift := 0;
      end Latch;

      procedure ASCII_Step
      with
        Pre  => Valid and then Pos <= N,
        Post => Pos > Pos'Old and then Pos <= N + 1
                and then Valid;
      --  One codeword of the ASCII encodation, with those it governs.

      procedure ASCII_Step is
         C    : constant Natural := Natural (Data (Pos));
         Skip : Natural := 0;
         --  The codewords after this one to pass over.
      begin
         case C is
            when 1 .. 128 =>
               Put_Char (C - 1);

            when 129 =>
               Ended := True;

            when 130 .. 229 =>
               Put (Character'Pos ('0') + (C - 130) / 10);
               Put (Character'Pos ('0') + (C - 130) mod 10);

            when 230 =>
               Latch (C40);

            when 231 =>
               Latch (Base_256);

            when 232 =>
               --  FNC1.
               if Pos > 1 then
                  Put (29);
               end if;

            when 233 =>
               --  Structured append: as the first codeword it has the
               --  place of the symbol in the sequence and the identity
               --  of the file after it.
               if Pos = 1 then
                  Skip := 3;
               end if;

            when 234 =>
               --  Reader programming.
               null;

            when 235 =>
               Upper := True;

            when 236 | 237 =>
               --  The macros, which only the first codeword can be.
               if Pos = 1 then
                  Macro := True;
                  Put (Character'Pos ('['));
                  Put (Character'Pos (')'));
                  Put (Character'Pos ('>'));
                  Put (30);
                  Put (Character'Pos ('0'));
                  Put (Character'Pos (if C = 236 then '5' else '6'));
                  Put (29);
               else
                  Good := False;
               end if;

            when 238 =>
               Latch (X12);

            when 239 =>
               Latch (Lower);

            when 240 =>
               Latch (EDIFACT);

            when 241 =>
               --  An extended channel interpretation: its number takes
               --  one to three codewords.
               if Pos = N then
                  Good := False;
               else
                  case Natural (Data (Pos + 1)) is
                     when 1 .. 127 =>
                        Skip := 1;
                     when 128 .. 191 =>
                        Skip := 2;
                     when 192 .. 207 =>
                        Skip := 3;
                     when others =>
                        Good := False;
                  end case;
               end if;

            when 254 =>
               --  The unlatch of the other encodations, which some
               --  encoders put at the very end.
               if Pos < N then
                  Good := False;
               end if;

            when others =>
               Good := False;
         end case;

         if Skip > N - Pos then
            Good := False;
            Pos := N + 1;
         else
            Pos := Pos + 1 + Skip;
         end if;
      end ASCII_Step;

      procedure C40_Value (V : Value_40)
      with
        Pre  => Valid,
        Post => Valid;
      --  One value of the C40 or Text encodation.

      procedure C40_Value (V : Value_40) is
         Set : constant Natural := Shift;
      begin
         Shift := 0;

         case Set is
            when 0 =>
               --  The basic set.
               case V is
                  when 0 .. 2 =>
                     Shift := V + 1;
                  when 3 =>
                     Put_Char (Character'Pos (' '));
                  when 4 .. 13 =>
                     Put_Char (Character'Pos ('0') + V - 4);
                  when 14 .. 39 =>
                     if Mode = C40 then
                        Put_Char (Character'Pos ('A') + V - 14);
                     else
                        Put_Char (Character'Pos ('a') + V - 14);
                     end if;
               end case;

            when 1 =>
               --  The control characters.
               if V <= 31 then
                  Put_Char (V);
               else
                  Good := False;
               end if;

            when 2 =>
               case V is
                  when 0 .. 14 =>
                     Put_Char (Character'Pos ('!') + V);
                  when 15 .. 21 =>
                     Put_Char (Character'Pos (':') + V - 15);
                  when 22 .. 26 =>
                     Put_Char (Character'Pos ('[') + V - 22);
                  when 27 =>
                     --  FNC1.
                     Put (29);
                  when 30 =>
                     Upper := True;
                  when others =>
                     Good := False;
               end case;

            when others =>
               if V > 31 then
                  Good := False;
               elsif Mode = C40 then
                  Put_Char (Character'Pos ('`') + V);
               else
                  case V is
                     when 0 =>
                        Put_Char (Character'Pos ('`'));
                     when 1 .. 26 =>
                        Put_Char (Character'Pos ('A') + V - 1);
                     when others =>
                        Put_Char (Character'Pos ('{') + V - 27);
                  end case;
               end if;
         end case;
      end C40_Value;

      procedure X12_Value (V : Value_40)
      with
        Pre  => Valid,
        Post => Valid;

      procedure X12_Value (V : Value_40) is
      begin
         case V is
            when 0 =>
               Put (13);
            when 1 =>
               Put (Character'Pos ('*'));
            when 2 =>
               Put (Character'Pos ('>'));
            when 3 =>
               Put (Character'Pos (' '));
            when 4 .. 13 =>
               Put (Character'Pos ('0') + V - 4);
            when 14 .. 39 =>
               Put (Character'Pos ('A') + V - 14);
         end case;
      end X12_Value;

      procedure Pair_Step
      with
        Pre  => Valid and then Pos < N,
        Post => Pos > Pos'Old and then Pos <= N + 1
                and then Valid;
      --  C40, Text and X12: two codewords that hold three values, or
      --  the codeword that goes back to the ASCII encodation.

      procedure Pair_Step is
         First : constant Natural := Natural (Data (Pos));
         Full  : Integer;
         V     : Value_40;
      begin
         if First = 254 then
            Latch (ASCII);
            Pos := Pos + 1;
            return;
         end if;

         Full := First * 256 + Natural (Data (Pos + 1)) - 1;
         Pos := Pos + 2;

         if Full not in 0 .. 40 * 1600 - 1 then
            Good := False;
            return;
         end if;

         for K in 1 .. 3 loop
            pragma Loop_Invariant (Len <= Text'Last);
            V := (case K is
                    when 1      => Full / 1600,
                    when 2      => (Full mod 1600) / 40,
                    when others => Full mod 40);
            if Mode = X12 then
               X12_Value (V);
            else
               C40_Value (V);
            end if;
         end loop;
      end Pair_Step;

      procedure EDIFACT_Step
      with
        Pre  => Valid and then Pos <= N - 2,
        Post => Pos > Pos'Old and then Pos <= N + 1
                and then Valid;
      --  Three codewords that hold four values of six bits.

      procedure EDIFACT_Step is
         Bits : constant Natural :=
           Natural (Data (Pos)) * 65536 + Natural (Data (Pos + 1)) * 256
           + Natural (Data (Pos + 2));

         Unit : constant array (1 .. 4) of Positive :=
           [262144, 4096, 64, 1];

         V : Natural;
      begin
         for K in 1 .. 4 loop
            pragma Loop_Invariant (Len <= Text'Last);
            pragma Loop_Invariant (Pos = Pos'Loop_Entry);

            V := (Bits / Unit (K)) mod 64;

            if V = 31 then
               --  Back to the ASCII encodation, at the next codeword.
               Latch (ASCII);
               Pos := Pos + Natural'Min (K, 3);
               return;
            end if;

            Put (if V < 32 then V + 64 else V);
         end loop;

         Pos := Pos + 3;
      end EDIFACT_Step;

      function Plain (P : Codeword_Index) return Natural
      with
        Pre  => Data'First = 1 and then N = Data'Last and then P <= N,
        Post => Plain'Result <= 255;
      --  The codeword P of the Base 256 encodation, which hides its
      --  values behind numbers that follow from their places.

      function Plain (P : Codeword_Index) return Natural is
         Mask : constant Positive := (149 * P) mod 255 + 1;
         V    : constant Integer := Natural (Data (P)) - Mask;
      begin
         return (if V >= 0 then V else V + 256);
      end Plain;

      procedure Base_256_Step
      with
        Pre  => Valid and then Pos <= N,
        Post => Pos > Pos'Old and then Pos <= N + 1
                and then Valid;
      --  The whole of a Base 256 field: its length, then its bytes.

      procedure Base_256_Step is
         D1    : constant Natural := Plain (Pos);
         Count : Natural;
      begin
         Latch (ASCII);
         Pos := Pos + 1;

         if D1 = 0 then
            --  To the end of the symbol.
            Count := N - Pos + 1;
         elsif D1 < 250 then
            Count := D1;
         elsif Pos > N then
            Good := False;
            return;
         else
            Count := 250 * (D1 - 249) + Plain (Pos);
            Pos := Pos + 1;
         end if;

         if Count > N - Pos + 1 then
            Good := False;
            Pos := N + 1;
            return;
         end if;

         for K in 1 .. Count loop
            pragma Loop_Invariant (Len <= Text'Last);
            Put (Plain (Pos + K - 1));
         end loop;

         Pos := Pos + Count;
      end Base_256_Step;

   begin
      Text := [others => ' '];

      --  Every step takes a codeword at least, so N steps are enough.

      for Step in 1 .. N loop
         pragma Loop_Invariant (Pos >= Step and then Pos <= N + 1);
         pragma Loop_Invariant (Len <= Text'Last);

         exit when Pos > N or else not Good or else Ended;

         --  The last codewords of a symbol, too few for a unit of the
         --  encodation, are in the ASCII encodation.
         Left := N - Pos + 1;
         if (Mode in C40 | Lower | X12 and then Left < 2)
           or else (Mode = EDIFACT and then Left < 3)
         then
            Latch (ASCII);
         end if;

         case Mode is
            when ASCII =>
               ASCII_Step;
            when C40 | Lower | X12 =>
               Pair_Step;
            when EDIFACT =>
               EDIFACT_Step;
            when Base_256 =>
               Base_256_Step;
         end case;
      end loop;

      if Macro then
         Put (30);
         Put (4);
      end if;

      Length := (if Good then Len else 0);
      OK := Good;
   end To_Text;

   ------------
   -- Decode --
   ------------

   procedure Decode
     (Grid      : Module_Grid;
      Size      : Size_Index;
      Field     : RS.Field;
      Text      : out Text_Buffer;
      Length    : out Natural;
      Corrected : out Natural;
      Success   : out Boolean)
   is
      Total  : constant Codeword_Index := Codewords (Size);
      N_Data : constant Codeword_Index := Sizes (Size).Data;

      Map   : Placement;
      Count : Codeword_Count;
      Words : Stream;
      OK    : Boolean;
   begin
      Text := [others => ' '];
      Length := 0;
      Corrected := 0;
      Success := False;

      Place (Size, Map, Count, OK);
      if not OK or else Count /= Total then
         return;
      end if;

      Read_Codewords (Grid, Map, Total, Words);

      Correct_Blocks (Size, Field, Words, Corrected, OK);
      if not OK then
         Corrected := 0;
         return;
      end if;

      To_Text (Words (1 .. N_Data), Text, Length, OK);
      if not OK then
         Length := 0;
         Corrected := 0;
         return;
      end if;

      Success := True;
   end Decode;

end AMV.Kernels.Code_Reader.Data_Matrix;
