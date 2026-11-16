--  Tests for the two-dimensional symbologies of AMV.Code_Reader and for
--  the kernels under them.
--
--  Reed-Solomon. The test has its own multiplication in GF(256) (shift
--  and xor, no tables) and checks the kernel's tables against it for
--  every pair of elements; its encoder (division by the generator
--  polynomial) is checked against published codewords. The correction is
--  then tried on every block shape of Data Matrix with every number of
--  errors up to half the check elements, and with more.

pragma Validity_Checks ("F");

with Ada.Exceptions;
with Ada.Text_IO;
with Interfaces;

with AMV.Kernels.Code_Reader.Reed_Solomon;
with AMV_Test_Support; use AMV_Test_Support;

procedure Test_Code_Reader_2D is

   package RS renames AMV.Kernels.Code_Reader.Reed_Solomon;

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

   procedure Run_All is
   begin
      Test_Field;
      Test_Known_Words;
      Test_Correction;
      Test_Beyond;
      Test_Bad_Tables;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Code_Reader_2D;
