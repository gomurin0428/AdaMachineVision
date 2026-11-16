--  Tests for the two-dimensional symbologies of AMV.Code_Reader and for
--  the kernels under them.
--
--  Reed-Solomon. The test has its own multiplication in GF(256) (shift
--  and xor, no tables) and checks the kernel's tables against it for
--  every pair of elements; its encoder (division by the generator
--  polynomial) is checked against published codewords. The correction is
--  then tried on every block shape of Data Matrix with every number of
--  errors up to half the check elements, and with more.
--
--  Data Matrix, from the modules to the text. The symbols come from the
--  test's own encoder (AMV_Test_Data_Matrix), which shares only the table
--  of the sizes with the kernel. The table is checked by itself; the
--  places of the codewords are compared for every size; the rules of
--  every encodation are tried on codewords; and symbols of every size
--  are read as they are, with as many wrong codewords in every block as
--  can be corrected, with one more, and with modules by chance.

pragma Validity_Checks ("F");

with Ada.Exceptions;
with Ada.Text_IO;
with Interfaces;

with AMV.Kernels.Code_Reader.Data_Matrix;
with AMV.Kernels.Code_Reader.Reed_Solomon;
with AMV_Test_Data_Matrix;
with AMV_Test_Support; use AMV_Test_Support;

procedure Test_Code_Reader_2D is

   package DM renames AMV.Kernels.Code_Reader.Data_Matrix;
   package RS renames AMV.Kernels.Code_Reader.Reed_Solomon;
   package Enc renames AMV_Test_Data_Matrix;

   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type RS.Element;
   use type RS.Word;

   DM_Field : constant RS.Field :=
     RS.Make_Field (RS.Data_Matrix_Polynomial);
   QR_Field : constant RS.Field := RS.Make_Field (RS.QR_Code_Polynomial);

   ---------------------------------------------------------------------
   --  Random numbers (the same ones in every run)
   ---------------------------------------------------------------------

   State : Interfaces.Unsigned_32 := 12345;

   function Random (Count : Positive) return Natural;
   --  One of 0 .. Count - 1.

   function Random (Count : Positive) return Natural is
   begin
      State := State * 1_103_515_245 + 12_345;
      return Natural (Interfaces.Shift_Right (State, 8) and 16#FFFF#)
             mod Count;
   end Random;

   ---------------------------------------------------------------------
   --  The test's own field arithmetic and encoder
   ---------------------------------------------------------------------

   function Slow_Mul
     (A, B       : RS.Element;
      Polynomial : RS.Field_Polynomial) return RS.Element;
   --  A * B modulo Polynomial, by shifting and adding.

   function Slow_Mul
     (A, B       : RS.Element;
      Polynomial : RS.Field_Polynomial) return RS.Element
   is
      X : Interfaces.Unsigned_16 := Interfaces.Unsigned_16 (A);
      Y : Interfaces.Unsigned_16 := Interfaces.Unsigned_16 (B);
      R : Interfaces.Unsigned_16 := 0;
   begin
      while Y /= 0 loop
         if (Y and 1) /= 0 then
            R := R xor X;
         end if;
         X := X * 2;
         if X >= 256 then
            X := X xor Interfaces.Unsigned_16 (Polynomial);
         end if;
         Y := Y / 2;
      end loop;
      return RS.Element (R);
   end Slow_Mul;

   function Slow_Power
     (Exponent   : Natural;
      Polynomial : RS.Field_Polynomial) return RS.Element;
   --  Alpha ** Exponent.

   function Slow_Power
     (Exponent   : Natural;
      Polynomial : RS.Field_Polynomial) return RS.Element
   is
      R : RS.Element := 1;
   begin
      for K in 1 .. Exponent loop
         R := Slow_Mul (R, 2, Polynomial);
      end loop;
      return R;
   end Slow_Power;

   function Slow_Value
     (W          : RS.Word;
      X          : RS.Element;
      Polynomial : RS.Field_Polynomial) return RS.Element;
   --  The value at X of the polynomial that W stands for.

   function Slow_Value
     (W          : RS.Word;
      X          : RS.Element;
      Polynomial : RS.Field_Polynomial) return RS.Element
   is
      R : RS.Element := 0;
   begin
      for I in W'Range loop
         R := Slow_Mul (R, X, Polynomial) xor W (I);
      end loop;
      return R;
   end Slow_Value;

   function Slow_Is_Codeword
     (W          : RS.Word;
      Parity     : Positive;
      First_Root : Natural;
      Polynomial : RS.Field_Polynomial) return Boolean
   is
     (for all J in 0 .. Parity - 1 =>
        Slow_Value
          (W, Slow_Power (First_Root + J, Polynomial), Polynomial) = 0);

   procedure Encode
     (F          : RS.Field;
      W          : in out RS.Word;
      Parity     : Positive;
      First_Root : Natural);
   --  Sets the last Parity elements of W so that W is a codeword: the
   --  remainder of the data times x ** Parity by the generator, the
   --  product of (x - Alpha ** (First_Root + j)). Uses RS.Mul, which
   --  Test_Field compares with Slow_Mul.

   procedure Encode
     (F          : RS.Field;
      W          : in out RS.Word;
      Parity     : Positive;
      First_Root : Natural)
   is
      G : RS.Word (1 .. Parity + 1) := [others => 0];
      --  The generator; G (K) is the coefficient of x ** (K - 1).
      R : RS.Word (1 .. Parity) := [others => 0];
      --  The remainder; R (1) is the highest coefficient.
      Root, Top : RS.Element;
      Data      : constant Natural := W'Length - Parity;
   begin
      G (1) := 1;
      for J in 0 .. Parity - 1 loop
         Root := F.Exp ((First_Root + J) mod 255);
         for K in reverse 1 .. J + 2 loop
            G (K) := RS.Mul (F, G (K), Root)
                     xor (if K > 1 then G (K - 1) else 0);
         end loop;
      end loop;

      for I in W'First .. W'First + Data - 1 loop
         Top := W (I) xor R (1);
         for K in 1 .. Parity - 1 loop
            R (K) := R (K + 1) xor RS.Mul (F, Top, G (Parity + 1 - K));
         end loop;
         R (Parity) := RS.Mul (F, Top, G (1));
      end loop;

      W (W'First + Data .. W'Last) := R;
   end Encode;

   function Distance (A, B : RS.Word) return Natural;
   --  The number of places where A and B differ.

   function Distance (A, B : RS.Word) return Natural is
      Count : Natural := 0;
   begin
      for I in A'Range loop
         if A (I) /= B (I) then
            Count := Count + 1;
         end if;
      end loop;
      return Count;
   end Distance;

   procedure Random_Codeword
     (F          : RS.Field;
      W          : out RS.Word;
      Parity     : Positive;
      First_Root : Natural);

   procedure Random_Codeword
     (F          : RS.Field;
      W          : out RS.Word;
      Parity     : Positive;
      First_Root : Natural) is
   begin
      for I in W'Range loop
         W (I) := RS.Element (Random (256));
      end loop;
      Encode (F, W, Parity, First_Root);
   end Random_Codeword;

   procedure Damage (W : in out RS.Word; Errors : Natural);
   --  Changes Errors different places of W.

   procedure Damage (W : in out RS.Word; Errors : Natural) is
      Hit   : array (W'Range) of Boolean := [others => False];
      Place : Positive;
   begin
      for E in 1 .. Errors loop
         loop
            Place := W'First + Random (W'Length);
            exit when not Hit (Place);
         end loop;
         Hit (Place) := True;
         W (Place) := W (Place) xor RS.Element (1 + Random (255));
      end loop;
   end Damage;

   function Image (Value : Integer) return String;

   function Image (Value : Integer) return String is
      S : constant String := Integer'Image (Value);
   begin
      return (if Value < 0 then S else S (S'First + 1 .. S'Last));
   end Image;

   ---------------------------------------------------------------------
   --  Reed-Solomon: the field
   ---------------------------------------------------------------------

   procedure Test_Field is

      procedure Check_Field
        (Name       : String;
         Polynomial : RS.Field_Polynomial)
      is
         F      : constant RS.Field := RS.Make_Field (Polynomial);
         Seen   : array (RS.Element) of Boolean := [others => False];
         Unique : Boolean := True;
         Logs   : Boolean := True;
         Wrong  : Natural := 0;
         Ones   : Boolean := True;
      begin
         for K in RS.Exponent loop
            if F.Exp (K) = 0 or else Seen (F.Exp (K)) then
               Unique := False;
            end if;
            Seen (F.Exp (K)) := True;
            if F.Log (F.Exp (K)) /= K then
               Logs := False;
            end if;
         end loop;
         Check (F.Exp (0) = 1 and then F.Exp (1) = 2
                and then F.Exp (8) = RS.Element (Polynomial - 256),
                Name & ": Alpha ** 0, 1 and 8");
         Check (Unique,
                Name & ": the powers of Alpha are the 255 elements "
                & "other than 0");
         Check (Logs, Name & ": Log (Exp (K)) = K");

         for A in RS.Element loop
            for B in RS.Element loop
               if RS.Mul (F, A, B) /= Slow_Mul (A, B, Polynomial) then
                  Wrong := Wrong + 1;
               end if;
            end loop;
            if A /= 0 and then RS.Mul (F, A, RS.Inverse (F, A)) /= 1 then
               Ones := False;
            end if;
         end loop;
         Check (Wrong = 0,
                Name & ": Mul is the product modulo the polynomial for "
                & "every pair (" & Image (Wrong) & " differ)");
         Check (Ones, Name & ": A * Inverse (A) = 1 for every A but 0");
      end Check_Field;

   begin
      Section ("Reed-Solomon: the field");
      Check_Field ("Data Matrix", RS.Data_Matrix_Polynomial);
      Check_Field ("QR code", RS.QR_Code_Polynomial);
   end Test_Field;

   ---------------------------------------------------------------------
   --  Reed-Solomon: published codewords
   ---------------------------------------------------------------------

   procedure Test_Known_Words is

      --  ISO/IEC 16022, the symbol of "123456": three data codewords
      --  and five check codewords.
      DM : constant RS.Word (1 .. 8) :=
        [142, 164, 186, 114, 25, 5, 88, 102];

      --  The QR code 1-M of "HELLO WORLD" that many descriptions of the
      --  QR code work through: 16 data and 10 check codewords.
      QR : constant RS.Word (1 .. 26) :=
        [32, 91, 11, 120, 209, 114, 220, 77, 67, 64, 236, 17, 236, 17,
         236, 17, 196, 35, 39, 119, 235, 215, 231, 226, 93, 23];

      W8  : RS.Word (1 .. 8) := DM;
      W26 : RS.Word (1 .. 26) := QR;

      Same : Boolean := True;
   begin
      Section ("Reed-Solomon: published codewords");

      Check (RS.Is_Codeword (DM_Field, DM, 5, 1),
             "the Data Matrix codewords of ""123456"" are a codeword");
      Check (Slow_Is_Codeword (DM, 5, 1, RS.Data_Matrix_Polynomial),
             "and by the test's own arithmetic");
      Check (not RS.Is_Codeword (DM_Field, DM, 5, 0)
             and then not RS.Is_Codeword (QR_Field, DM, 5, 1),
             "but not with the first root 0 or in the QR code field");
      W8 (4 .. 8) := [others => 0];
      Encode (DM_Field, W8, 5, 1);
      Check (W8 = DM, "the test's encoder gives its check codewords");

      Check (RS.Is_Codeword (QR_Field, QR, 10, 0),
             "the QR code codewords of ""HELLO WORLD"" are a codeword");
      Check (Slow_Is_Codeword (QR, 10, 0, RS.QR_Code_Polynomial),
             "and by the test's own arithmetic");
      W26 (17 .. 26) := [others => 0];
      Encode (QR_Field, W26, 10, 0);
      Check (W26 = QR, "the test's encoder gives its check codewords");

      for Root in RS.Exponent loop
         if RS.Syndrome (DM_Field, QR, Root)
           /= Slow_Value
                (QR, Slow_Power (Root, RS.Data_Matrix_Polynomial),
                 RS.Data_Matrix_Polynomial)
         then
            Same := False;
         end if;
      end loop;
      Check (Same, "Syndrome is the value at Alpha ** Root, every root");
   end Test_Known_Words;

   ---------------------------------------------------------------------
   --  Reed-Solomon: correction
   ---------------------------------------------------------------------

   type Shape is record
      Data, Parity : Positive;
   end record;

   type Shape_List is array (Positive range <>) of Shape;

   --  Every block of the Data Matrix sizes (ECC 200).
   DM_Shapes : constant Shape_List :=
     [(3, 5), (5, 7), (8, 10), (12, 12), (18, 14), (22, 18), (30, 20),
      (36, 24), (44, 28), (62, 36), (86, 42), (114, 48), (144, 56),
      (174, 68), (102, 42), (140, 56), (92, 36), (136, 56), (175, 68),
      (163, 62), (156, 62), (155, 62), (10, 11), (16, 14), (32, 24),
      (49, 28)];

   --  Some blocks of the QR code, and the extremes.
   QR_Shapes : constant Shape_List :=
     [(19, 7), (16, 10), (13, 13), (9, 17), (34, 10), (28, 16),
      (22, 22), (16, 28), (15, 30), (116, 30), (225, 30), (1, 2),
      (1, 254), (253, 2), (128, 127)];

   procedure Test_Correction is

      procedure Check_Shapes
        (Name       : String;
         F          : RS.Field;
         Polynomial : RS.Field_Polynomial;
         Shapes     : Shape_List;
         First_Root : Natural)
      is
         Runs, Bad : Natural := 0;
      begin
         for S of Shapes loop
            declare
               N         : constant Positive := S.Data + S.Parity;
               Sent      : RS.Word (1 .. N);
               W         : RS.Word (1 .. N);
               Corrected : Natural;
               Success   : Boolean;
            begin
               for Errors in 0 .. S.Parity / 2 loop
                  for Trial in 1 .. 4 loop
                     Random_Codeword (F, Sent, S.Parity, First_Root);
                     if Errors = 0 and then Trial = 1
                       and then not Slow_Is_Codeword
                                      (Sent, S.Parity, First_Root,
                                       Polynomial)
                     then
                        Bad := Bad + 1;
                     end if;
                     W := Sent;
                     Damage (W, Errors);
                     RS.Correct
                       (F, W, S.Parity, First_Root, Corrected, Success);
                     Runs := Runs + 1;
                     if not Success or else W /= Sent
                       or else Corrected /= Errors
                     then
                        Bad := Bad + 1;
                     end if;
                  end loop;
               end loop;
            end;
         end loop;
         Check (Bad = 0,
                Name & ": every word with errors in up to half as many "
                & "places as check elements is corrected, and the "
                & "errors are counted (" & Image (Bad) & " of "
                & Image (Runs) & " not)");
      end Check_Shapes;

      Zero      : RS.Word (1 .. 40) := [others => 0];
      W         : RS.Word (1 .. 40);
      Sent      : RS.Word (1 .. 40);
      Corrected : Natural;
      Success   : Boolean;
      Bad       : Natural := 0;
   begin
      Section ("Reed-Solomon: correction");
      Check_Shapes ("Data Matrix blocks", DM_Field,
                    RS.Data_Matrix_Polynomial, DM_Shapes, 1);
      Check_Shapes ("QR code blocks", QR_Field,
                    RS.QR_Code_Polynomial, QR_Shapes, 0);
      Check_Shapes ("first root 200", DM_Field,
                    RS.Data_Matrix_Polynomial, DM_Shapes (1 .. 12), 200);
      Check_Shapes ("first root 254", QR_Field,
                    RS.QR_Code_Polynomial, QR_Shapes (1 .. 9), 254);

      RS.Correct (DM_Field, Zero, 12, 1, Corrected, Success);
      Check (Success and then Corrected = 0
             and then Zero = [1 .. 40 => 0],
             "the word of zeros is a codeword");

      --  Every single place, and every pair of the first, the last data,
      --  the first check and the last place.
      Random_Codeword (DM_Field, Sent, 12, 1);
      for Place in Sent'Range loop
         W := Sent;
         W (Place) := W (Place) xor 16#FF#;
         RS.Correct (DM_Field, W, 12, 1, Corrected, Success);
         if not Success or else W /= Sent or else Corrected /= 1 then
            Bad := Bad + 1;
         end if;
      end loop;
      Check (Bad = 0, "an error at any one place is corrected");

      Bad := 0;
      for A of Shape_List'[(1, 28), (1, 29), (1, 40), (28, 29),
                           (28, 40), (29, 40)]
      loop
         W := Sent;
         W (A.Data) := W (A.Data) xor 1;
         W (A.Parity) := W (A.Parity) xor 16#80#;
         RS.Correct (DM_Field, W, 12, 1, Corrected, Success);
         if not Success or else W /= Sent or else Corrected /= 2 then
            Bad := Bad + 1;
         end if;
      end loop;
      Check (Bad = 0,
             "errors at the ends of the data and of the check elements "
             & "are corrected");

      --  One check element corrects nothing.
      declare
         One : RS.Word (1 .. 10);
         Got : RS.Word (1 .. 10);
      begin
         Random_Codeword (DM_Field, One, 1, 1);
         Got := One;
         RS.Correct (DM_Field, Got, 1, 1, Corrected, Success);
         Check (Success and then Corrected = 0 and then Got = One,
                "one check element: a codeword is accepted");
         Got (3) := Got (3) xor 5;
         One := Got;
         RS.Correct (DM_Field, Got, 1, 1, Corrected, Success);
         Check (not Success and then Corrected = 0 and then Got = One,
                "one check element: an error is found, the word is "
                & "left as it was");
      end;
   end Test_Correction;

   ---------------------------------------------------------------------
   --  Reed-Solomon: more errors than can be corrected, tables that are
   --  not those of a field
   ---------------------------------------------------------------------

   function Holds
     (F          : RS.Field;
      Given, W   : RS.Word;
      Parity     : Positive;
      First_Root : RS.Exponent;
      Corrected  : Natural;
      Success    : Boolean) return Boolean
   is
     (if Success
      then RS.Is_Codeword (F, W, Parity, First_Root)
           and then Corrected <= Parity / 2
           and then Corrected = Distance (W, Given)
      else W = Given and then Corrected = 0);
   --  What Correct promises.

   procedure Test_Beyond is
      Runs, Bad, Other : Natural := 0;
   begin
      Section ("Reed-Solomon: more errors than can be corrected");

      for S of DM_Shapes loop
         declare
            N         : constant Positive := S.Data + S.Parity;
            Half      : constant Natural := S.Parity / 2;
            Sent      : RS.Word (1 .. N);
            Given     : RS.Word (1 .. N);
            W         : RS.Word (1 .. N);
            Corrected : Natural;
            Success   : Boolean;
         begin
            for Errors in Half + 1 .. Natural'Min (N, Half + 6) loop
               for Trial in 1 .. 8 loop
                  Random_Codeword (DM_Field, Sent, S.Parity, 1);
                  Given := Sent;
                  Damage (Given, Errors);
                  W := Given;
                  RS.Correct (DM_Field, W, S.Parity, 1, Corrected, Success);
                  Runs := Runs + 1;
                  if not Holds
                           (DM_Field, Given, W, S.Parity, 1, Corrected,
                            Success)
                    or else W = Sent
                    or else
                      (Success
                       and then not Slow_Is_Codeword
                                      (W, S.Parity, 1,
                                       RS.Data_Matrix_Polynomial))
                  then
                     Bad := Bad + 1;
                  end if;
                  if Success then
                     Other := Other + 1;
                  end if;
               end loop;
            end loop;
         end;
      end loop;

      Check (Bad = 0,
             "the word is left as it was, or is another codeword that "
             & "is as near as a corrected one (" & Image (Bad) & " of "
             & Image (Runs) & " not)");
      Ada.Text_IO.Put_Line
        ("  " & Image (Other) & " of " & Image (Runs)
         & " words were nearer to another codeword");

      --  Random words.
      Runs := 0;
      Bad := 0;
      for S of DM_Shapes loop
         declare
            N         : constant Positive := S.Data + S.Parity;
            Given     : RS.Word (1 .. N);
            W         : RS.Word (1 .. N);
            Corrected : Natural;
            Success   : Boolean;
         begin
            for Trial in 1 .. 8 loop
               for I in Given'Range loop
                  Given (I) := RS.Element (Random (256));
               end loop;
               W := Given;
               RS.Correct (DM_Field, W, S.Parity, 1, Corrected, Success);
               Runs := Runs + 1;
               if not Holds
                        (DM_Field, Given, W, S.Parity, 1, Corrected,
                         Success)
               then
                  Bad := Bad + 1;
               end if;
            end loop;
         end;
      end loop;
      Check (Bad = 0,
             "the same for random words (" & Image (Bad) & " of "
             & Image (Runs) & " not)");
   end Test_Beyond;

   procedure Test_Bad_Tables is

      procedure Try (Name : String; F : RS.Field) is
         Runs, Bad : Natural := 0;
      begin
         for S of DM_Shapes loop
            declare
               N         : constant Positive := S.Data + S.Parity;
               Given     : RS.Word (1 .. N);
               W         : RS.Word (1 .. N);
               Corrected : Natural;
               Success   : Boolean;
               Root      : constant RS.Exponent := Random (255);
            begin
               for Trial in 1 .. 6 loop
                  for I in Given'Range loop
                     Given (I) :=
                       (if Trial mod 2 = 0 and then I > Trial
                        then 0
                        else RS.Element (Random (256)));
                  end loop;
                  W := Given;
                  RS.Correct (F, W, S.Parity, Root, Corrected, Success);
                  Runs := Runs + 1;
                  if not Holds
                           (F, Given, W, S.Parity, Root, Corrected,
                            Success)
                  then
                     Bad := Bad + 1;
                  end if;
               end loop;
            end;
         end loop;
         Check (Bad = 0,
                Name & ": no exception, and the word is left as it was "
                & "or has no syndrome left (" & Image (Bad) & " of "
                & Image (Runs) & " not)");
      exception
         when E : others =>
            Fail (Name & ": raised "
                  & Ada.Exceptions.Exception_Name (E));
      end Try;

      Mixed : RS.Field;
   begin
      Section ("Reed-Solomon: tables that are not those of a field");

      Try ("the tables of x ** 8", RS.Make_Field (16#100#));
      Try ("the tables of x ** 8 + 1", RS.Make_Field (16#101#));
      Try ("the tables of x ** 8 + x ** 4 + 1", RS.Make_Field (16#111#));
      Try ("tables never set", RS.Field'(others => <>));

      for Round in 1 .. 3 loop
         for K in RS.Exponent loop
            Mixed.Exp (K) := RS.Element (Random (256));
         end loop;
         for A in RS.Element loop
            Mixed.Log (A) := Random (255);
         end loop;
         Try ("random tables" & Integer'Image (Round), Mixed);
      end loop;
   end Test_Bad_Tables;

   ---------------------------------------------------------------------
   --  Data Matrix: the sizes and the places of the codewords
   ---------------------------------------------------------------------

   procedure Test_DM_Sizes is
      Good_Shape  : Boolean := True;
      Good_Count  : Boolean := True;
      Good_Blocks : Boolean := True;
      Good_Find   : Boolean := True;
      Ordered     : Boolean := True;
   begin
      Section ("Data Matrix: the sizes");

      for S in DM.Size_Index loop
         declare
            I      : constant DM.Size_Info := DM.Sizes (S);
            Area   : constant Positive :=
              I.Region_Rows * I.Regions_Down
              * I.Region_Columns * I.Regions_Across;
            Parity : constant Natural := I.Check / I.Blocks;
         begin
            if I.Rows /= (I.Region_Rows + 2) * I.Regions_Down
              or else I.Columns /= (I.Region_Columns + 2) * I.Regions_Across
            then
               Good_Shape := False;
            end if;

            if Area / 8 /= I.Data + I.Check then
               Good_Count := False;
            end if;

            --  The symbology has sixteen lengths of check codewords for
            --  a block, its rectangular extension (one block a size) has
            --  nine more, and no block is longer than the field allows.

            if I.Check mod I.Blocks /= 0
              or else (S <= 30
                       and then Parity not in 5 | 7 | 10 | 11 | 12 | 14 | 18
                                              | 20 | 24 | 28 | 36 | 42 | 48
                                              | 56 | 62 | 68)
              or else (S > 30
                       and then (I.Blocks /= 1
                                 or else Parity not in 15 | 18 | 22 | 27 | 28
                                                       | 32 | 34 | 36 | 38
                                                       | 41 | 42 | 46 | 50))
              or else (I.Data + I.Blocks - 1) / I.Blocks + Parity > 255
            then
               Good_Blocks := False;
            end if;

            if DM.Find_Size (I.Rows, I.Columns) /= S then
               Good_Find := False;
            end if;

            --  The squares and the rectangles in the order of their
            --  data, those of the extension in the order of their rows
            --  and columns.

            if S in 2 .. 24 | 26 .. 30
              and then I.Data <= DM.Sizes (S - 1).Data
            then
               Ordered := False;
            end if;
            if S in 32 .. 48
              and then (I.Rows < DM.Sizes (S - 1).Rows
                        or else (I.Rows = DM.Sizes (S - 1).Rows
                                 and then I.Columns
                                          <= DM.Sizes (S - 1).Columns))
            then
               Ordered := False;
            end if;
            if S > 30
              and then (I.Regions_Down /= 1 or else I.Rows >= I.Columns)
            then
               Ordered := False;
            end if;
         end;
      end loop;

      Check (Good_Shape,
             "the modules of every size are its regions with their borders");
      Check (Good_Count,
             "the codewords of every size fill its mapping matrix");
      Check (Good_Blocks,
             "the check codewords of every size divide among its blocks");
      Check (Good_Find, "every size is found by its rows and columns");
      Check (Ordered,
             "the sizes are in order: the squares and the rectangles by "
             & "their data, those of the extension by rows and columns");
      Check (DM.Find_Size (10, 12) = 0
             and then DM.Find_Size (18, 8) = 0
             and then DM.Find_Size (0, 0) = 0
             and then DM.Find_Size (-10, -10) = 0
             and then DM.Find_Size (146, 146) = 0
             and then DM.Find_Size (Integer'Last, Integer'First) = 0,
             "no other rows and columns are a size");
      Check (DM.Find_Size (8, 48) = 31
             and then DM.Find_Size (26, 64) = 48
             and then DM.Find_Size (48, 8) = 0
             and then DM.Find_Size (8, 56) = 0
             and then DM.Find_Size (26, 56) = 0,
             "the sizes of the rectangular extension, and no others");
      Check (DM.Sizes (24).Data = DM.Max_Data
             and then DM.Sizes (24).Data + DM.Sizes (24).Check
                      = DM.Max_Codewords,
             "the limits are those of the largest size");
   end Test_DM_Sizes;

   procedure Test_DM_Placement is
      Map      : DM.Placement;
      Count    : DM.Codeword_Count;
      OK       : Boolean;
      All_OK   : Boolean := True;
      All_Once : Boolean := True;
      All_Same : Boolean := True;
      All_Rest : Boolean := True;
   begin
      Section ("Data Matrix: the places of the codewords");

      for S in DM.Size_Index loop
         declare
            I     : constant DM.Size_Info := DM.Sizes (S);
            Total : constant Positive := I.Data + I.Check;
            A     : constant Enc.Mark_Matrix := Enc.Marks (S);
            Seen  : array (1 .. Total, DM.Bit_Index) of Natural :=
              [others => [others => 0]];
            Rest  : Natural := 0;
            Dark  : Natural := 0;
            Mark  : Natural;
            P     : DM.Module_Place;
         begin
            DM.Place (S, Map, Count, OK);
            if not OK or else Count /= Total then
               All_OK := False;
            end if;

            for R in A'Range (1) loop
               for C in A'Range (2) loop
                  Mark := A (R, C);
                  if Mark <= 1 then
                     Rest := Rest + 1;
                     Dark := Dark + Mark;
                  elsif Mark / 10 in 1 .. Total
                    and then Mark mod 10 in 1 .. 8
                  then
                     Seen (Mark / 10, Mark mod 10) := @ + 1;
                     P := Map (Mark / 10, Mark mod 10);
                     if Natural (P.Row) /= Enc.Symbol_Row (S, R)
                       or else Natural (P.Column) /= Enc.Symbol_Column (S, C)
                     then
                        All_Same := False;
                     end if;
                  else
                     All_Once := False;
                  end if;
               end loop;
            end loop;

            for N of Seen loop
               if N /= 1 then
                  All_Once := False;
               end if;
            end loop;

            --  What is left over is the four modules of the fixed
            --  pattern, in the sizes whose mapping matrix has them.

            if Rest /= A'Length (1) * A'Length (2) - 8 * Total
              or else Rest not in 0 | 4
              or else Dark /= Rest / 2
            then
               All_Rest := False;
            end if;
         end;
      end loop;

      Check (All_OK, "every size: all codewords placed");
      Check (All_Once,
             "every size: the test's placement has every bit once");
      Check (All_Same,
             "every size: the same places as the test's placement");
      Check (All_Rest,
             "every size: the other modules are the fixed pattern");
   end Test_DM_Placement;

   ---------------------------------------------------------------------
   --  Data Matrix: from the codewords to the text
   ---------------------------------------------------------------------

   function To_Codewords (Data : Enc.Byte_List) return DM.Codeword_Array;

   function To_Codewords (Data : Enc.Byte_List) return DM.Codeword_Array is
      R : DM.Codeword_Array (1 .. Data'Length);
   begin
      for I in R'Range loop
         R (I) := RS.Element (Data (Data'First + I - 1));
      end loop;
      return R;
   end To_Codewords;

   function Gives
     (Data     : Enc.Byte_List;
      Expected : String) return Boolean;
   --  The data codewords Data have the text Expected.

   function Gives
     (Data     : Enc.Byte_List;
      Expected : String) return Boolean
   is
      Text   : DM.Text_Buffer (1 .. DM.Max_Text_Length);
      Length : Natural;
      OK     : Boolean;
   begin
      DM.To_Text (To_Codewords (Data), Text, Length, OK);
      return OK and then String (Text (1 .. Length)) = Expected;
   end Gives;

   function Gives_Nothing (Data : Enc.Byte_List) return Boolean;
   --  The data codewords Data have no text.

   function Gives_Nothing (Data : Enc.Byte_List) return Boolean is
      Text   : DM.Text_Buffer (1 .. DM.Max_Text_Length);
      Length : Natural;
      OK     : Boolean;
   begin
      DM.To_Text (To_Codewords (Data), Text, Length, OK);
      return not OK and then Length = 0;
   end Gives_Nothing;

   Every : constant String (1 .. 256) :=
     [for I in 1 .. 256 => Character'Val (I - 1)];
   Mixed : constant String :=
     "Data Matrix 0123456789 {ecc 200} ~`_^|" & Character'Val (7)
     & Character'Val (200) & "Zz" & Character'Val (255) & "@";

   procedure Test_DM_ASCII is
      use type Enc.Byte_List;

      GS      : constant Character := Character'Val (29);
      Rec_Sep : constant Character := Character'Val (30);
      EOT     : constant Character := Character'Val (4);
   begin
      Section ("Data Matrix: the ASCII encodation");

      Check (Enc.ASCII ("123456") = [142, 164, 186],
             "the test's codewords of 123456 are the published ones");
      Check (Gives ([142, 164, 186], "123456"), "123456");
      Check (Gives (Enc.ASCII (Every), Every), "every character");
      Check (Gives (Enc.ASCII (Mixed), Mixed), "a mixed text");
      Check (Gives ([66, 129, 70, 1], "A"), "nothing after the first pad");
      Check (Gives ([1 => 129], ""), "only pads: the empty text");
      Check (Gives ([232, 66], "A"), "FNC1 first adds nothing");
      Check (Gives ([66, 232, 67], "A" & GS & "B"), "FNC1 later is GS");
      Check (Gives ([236, 66, 67],
                    "[)>" & Rec_Sep & "05" & GS & "AB" & Rec_Sep & EOT),
             "the macro 05");
      Check (Gives ([237, 66, 67, 129, 9],
                    "[)>" & Rec_Sep & "06" & GS & "AB" & Rec_Sep & EOT),
             "the macro 06");
      Check (Gives_Nothing ([66, 236]), "a macro that is not first");
      Check (Gives ([233, 20, 1, 1, 66], "A"),
             "structured append is passed over");
      Check (Gives_Nothing ([233, 20, 1]),
             "structured append without its codewords");
      Check (Gives ([234, 66], "A"), "reader programming is passed over");
      Check (Gives ([241, 27, 66], "A")
             and then Gives ([241, 128, 5, 66], "A")
             and then Gives ([241, 192, 5, 5, 66], "A"),
             "an extended channel interpretation is passed over");
      Check (Gives_Nothing ([241, 208, 66])
             and then Gives_Nothing ([1 => 241])
             and then Gives_Nothing ([241, 128])
             and then Gives_Nothing ([241, 0, 66]),
             "an extended channel interpretation that is not one");
      Check (Gives_Nothing ([1 => 0])
             and then Gives_Nothing ([66, 0])
             and then Gives_Nothing ([66, 242])
             and then Gives_Nothing ([66, 253, 67])
             and then Gives_Nothing ([1 => 255]),
             "codewords that are not defined");
      Check (Gives ([66, 254], "A") and then Gives_Nothing ([254, 66]),
             "the unlatch only as the last codeword");

      declare
         Text   : DM.Text_Buffer (1 .. 2);
         None   : DM.Text_Buffer (1 .. 0);
         Length : Natural;
         OK     : Boolean;
      begin
         DM.To_Text (To_Codewords (Enc.ASCII ("ABC")), Text, Length, OK);
         Check (not OK and then Length = 0, "a text longer than the buffer");
         DM.To_Text (To_Codewords (Enc.ASCII ("AB")), Text, Length, OK);
         Check (OK and then Length = 2 and then String (Text) = "AB",
                "a text as long as the buffer");
         DM.To_Text (To_Codewords ([1 => 129]), None, Length, OK);
         Check (OK and then Length = 0, "the empty text in no buffer");
         DM.To_Text (To_Codewords ([1 => 66]), None, Length, OK);
         Check (not OK and then Length = 0, "a text in no buffer");
      end;
   end Test_DM_ASCII;

   procedure Test_DM_Encodations is
      use type Enc.Byte_List;

      GS : constant Character := Character'Val (29);
      CR : constant Character := Character'Val (13);

      EDIFACT_Set : constant String (1 .. 63) :=
        [for I in 1 .. 63 => Character'Val (31 + I)];

      Good : Boolean;
   begin
      Section ("Data Matrix: the other encodations");

      --  C40 and Text.

      Check (Enc.C40 ("AIMAIMAIM") = [230, 91, 11, 91, 11, 91, 11, 254],
             "the test's C40 codewords of AIMAIMAIM are the published ones");
      Check (Gives ([230, 91, 11, 91, 11, 91, 11, 254], "AIMAIMAIM"),
             "C40: AIMAIMAIM");
      Check (Gives (Enc.C40 (Every), Every), "C40: every character");
      Check (Gives (Enc.Lower (Every), Every), "Text: every character");

      Good := True;
      for L in 0 .. Mixed'Length loop
         declare
            T : constant String := Mixed (1 .. L);
         begin
            Good := Good and then Gives (Enc.C40 (T), T)
                    and then Gives (Enc.Lower (T), T)
                    and then Gives (Enc.C40 (T) & Enc.ASCII ("12x"),
                                    T & "12x");
         end;
      end loop;
      Check (Good, "C40 and Text: a mixed text cut at every length");

      Check (Gives ([230, 91, 11], "AIM"),
             "C40: the data can end without the unlatch");
      Check (Gives ([230, 91, 11, 66], "AIMA")
             and then Gives ([239, 91, 11, 66], "aimA"),
             "C40 and Text: one codeword at the end is ASCII");
      Check (Gives ([230, 10, 124], GS & " "), "C40: FNC1 is GS");
      Check (Gives_Nothing ([230, 250, 1])
             and then Gives_Nothing ([230, 0, 0])
             and then Gives_Nothing ([230, 255, 255]),
             "C40: two codewords that are not three values");
      Check (Gives_Nothing ([230, 5, 4])
             and then Gives_Nothing ([230, 10, 164])
             and then Gives_Nothing ([230, 17, 132])
             and then Gives_Nothing ([239, 17, 132]),
             "C40 and Text: values that the shifted sets do not have");

      --  X12.

      Check (Gives (Enc.X12 ("AB1 2*>" & CR & "Z"), "AB1 2*>" & CR & "Z"),
             "X12: every kind of character");
      Check (Gives (Enc.X12 ("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ")
                    & Enc.ASCII ("ok"),
                    "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZok"),
             "X12: the digits and the letters, then ASCII");
      Check (Gives (Enc.X12 ("X12") (1 .. 3) & [1 => 66], "X12A"),
             "X12: one codeword at the end is ASCII");
      Check (Gives_Nothing ([238, 250, 1]),
             "X12: two codewords that are not three values");

      --  EDIFACT.

      Check (Gives (Enc.EDIFACT (EDIFACT_Set) & Enc.ASCII ("ok"),
                    EDIFACT_Set & "ok"),
             "EDIFACT: every character");

      Good := True;
      for L in 0 .. 9 loop
         declare
            T : constant String := EDIFACT_Set (30 .. 29 + L);
         begin
            Good := Good
                    and then Gives (Enc.EDIFACT (T) & Enc.ASCII ("xy"),
                                    T & "xy");
         end;
      end loop;
      Check (Good, "EDIFACT: texts of every length, then ASCII");

      Check (Gives (Enc.EDIFACT ("ABCD") (1 .. 4), "ABCD"),
             "EDIFACT: the data can end without the unlatch");
      Check (Gives (Enc.EDIFACT ("ABCD") (1 .. 4) & [66, 67], "ABCDAB"),
             "EDIFACT: two codewords at the end are ASCII");

      --  Base 256.

      Good := True;
      for L in 1 .. 1555 loop
         if L in 1 .. 3 | 249 .. 251 | 499 .. 501 | 1555 then
            declare
               T : String (1 .. L);
            begin
               for I in T'Range loop
                  T (I) := Character'Val ((I * 7 + L) mod 256);
               end loop;
               Good := Good and then Gives (Enc.Base_256 (T), T);
            end;
         end if;
      end loop;
      Check (Good, "Base 256: short and long texts");
      Check (Gives (Enc.Base_256 (Every), Every), "Base 256: every byte");
      Check (Gives (Enc.ASCII ("AB") & Enc.Base_256 ("xyz", First => 3)
                    & Enc.ASCII ("C"),
                    "ABxyzC"),
             "Base 256: between ASCII codewords");
      Check (Gives ([231, Enc.Hidden (0, 2), Enc.Hidden (65, 3),
                     Enc.Hidden (66, 4)],
                    "AB"),
             "Base 256: the length 0 is up to the end");
      Check (Gives_Nothing ([231, Enc.Hidden (5, 2), Enc.Hidden (65, 3)])
             and then Gives_Nothing
                        ([231, Enc.Hidden (250, 2), Enc.Hidden (9, 3),
                          Enc.Hidden (65, 4)]),
             "Base 256: a length beyond the end");

      --  One after another.

      Check (Gives (Enc.ASCII ("a1") & Enc.C40 ("C40")
                    & Enc.Lower ("text") & Enc.X12 ("X12")
                    & Enc.EDIFACT ("EDI") & Enc.Base_256 ("b", First => 20)
                    & Enc.ASCII ("z"),
                    "a1C40textX12EDIbz"),
             "the encodations one after another");
   end Test_DM_Encodations;

   ---------------------------------------------------------------------
   --  Data Matrix: from the modules to the text
   ---------------------------------------------------------------------

   procedure Test_DM_Decode is
      use type Enc.Byte_List;

      Text      : DM.Text_Buffer (1 .. DM.Max_Text_Length);
      Length    : Natural;
      Corrected : Natural;
      Success   : Boolean;

      function Letters (Count : Natural) return String;
      --  Count letters.

      function Letters (Count : Natural) return String is
         R : String (1 .. Count);
      begin
         for C of R loop
            C := Character'Val (Character'Pos ('A') + Random (26));
         end loop;
         return R;
      end Letters;

      procedure Read (Stream : Enc.Byte_List; Size : DM.Size_Index);
      --  Decodes the symbol of the size with the codewords Stream.

      procedure Read (Stream : Enc.Byte_List; Size : DM.Size_Index) is
      begin
         DM.Decode
           (Enc.Grid (Enc.Modules (Stream, Size)), Size, DM_Field,
            Text, Length, Corrected, Success);
      end Read;

      function Read_Is (Expected : String; Fixed : Natural) return Boolean
      is (Success and then Corrected = Fixed
          and then String (Text (1 .. Length)) = Expected);

      procedure Damage
        (Stream : in out Enc.Byte_List;
         Size   : DM.Size_Index;
         Block  : Positive;
         Errors : Natural);
      --  Changes Errors codewords of the block Block.

      procedure Damage
        (Stream : in out Enc.Byte_List;
         Size   : DM.Size_Index;
         Block  : Positive;
         Errors : Natural)
      is
         Blocks : constant Positive := DM.Sizes (Size).Blocks;
         Count  : constant Positive := (Stream'Last - Block) / Blocks + 1;
         Hit    : array (Stream'Range) of Boolean := [others => False];
         Done   : Natural := 0;
         P      : Positive;
      begin
         while Done < Errors loop
            P := Block + Blocks * Random (Count);
            if not Hit (P) then
               Hit (P) := True;
               Stream (P) := (Stream (P) + 1 + Random (255)) mod 256;
               Done := Done + 1;
            end if;
         end loop;
      end Damage;

      Clean    : Boolean := True;
      Padded   : Boolean := True;
      Repaired : Boolean := True;
      Honest   : Boolean := True;
      Refused  : Natural := 0;
      Tried    : Natural := 0;
      Random_Texts : Natural := 0;
   begin
      Section ("Data Matrix: from the modules to the text");

      Check (Enc.Stream (Enc.ASCII ("123456"), 1)
             = [142, 164, 186, 114, 25, 5, 88, 102],
             "the test's check codewords of 123456 are the published ones");

      for S in DM.Size_Index loop
         declare
            I      : constant DM.Size_Info := DM.Sizes (S);
            Parity : constant Positive := I.Check / I.Blocks;
            Full   : constant String := Letters (I.Data);
            Short  : constant String := "No" & Image (S);
            Stream : constant Enc.Byte_List :=
              Enc.Stream (Enc.ASCII (Full), S);
            Hurt   : Enc.Byte_List := Stream;
         begin
            --  As it is.

            Read (Stream, S);
            Clean := Clean and then Read_Is (Full, 0);

            Read (Enc.Stream (Enc.Padded (Enc.ASCII (Short), S), S), S);
            Padded := Padded and then Read_Is (Short, 0);

            --  As many wrong codewords in every block as can be
            --  corrected.

            for B in 1 .. I.Blocks loop
               Damage (Hurt, S, B, Parity / 2);
            end loop;
            Read (Hurt, S);
            Repaired := Repaired
                        and then Read_Is (Full, I.Blocks * (Parity / 2));

            --  One more in one block: the symbol is refused, or (rarely,
            --  for the few check codewords of the small sizes) read as
            --  another one.

            for Round in 1 .. 4 loop
               Hurt := Stream;
               Damage (Hurt, S, 1 + Random (I.Blocks), Parity / 2 + 1);
               Read (Hurt, S);
               Tried := Tried + 1;
               if not Success then
                  Refused := Refused + 1;
                  Honest := Honest and then Length = 0
                            and then Corrected = 0;
               elsif Read_Is (Full, Corrected) then
                  Honest := False;
               end if;
            end loop;

            --  Modules by chance.

            for Round in 1 .. 20 loop
               for W of Hurt loop
                  W := Random (256);
               end loop;
               Read (Hurt, S);
               if Success then
                  Random_Texts := Random_Texts + 1;
               end if;
            end loop;
         end;
      end loop;

      Check (Clean, "every size, full of letters");
      Check (Padded, "every size, a short text and pads");
      Check (Repaired,
             "every size, half the check codewords of every block wrong");
      Check (Honest,
             "one wrong codeword more: never the text of the symbol");
      Ada.Text_IO.Put_Line
        (" " & Image (Refused) & " of " & Image (Tried)
         & " symbols with one wrong codeword more were refused");
      Check (Random_Texts = 0, "modules by chance have no text");
   end Test_DM_Decode;

   procedure Run_All is
   begin
      Test_Field;
      Test_Known_Words;
      Test_Correction;
      Test_Beyond;
      Test_Bad_Tables;
      Test_DM_Sizes;
      Test_DM_Placement;
      Test_DM_ASCII;
      Test_DM_Encodations;
      Test_DM_Decode;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Code_Reader_2D;
