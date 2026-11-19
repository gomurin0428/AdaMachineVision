with Ada.Numerics.Long_Elementary_Functions;
with Interfaces; use Interfaces;

package body AMV_Test_Data_Matrix is

   package EF renames Ada.Numerics.Long_Elementary_Functions;

   ---------------------------------------------------------------------
   --  Lists that grow
   ---------------------------------------------------------------------

   type Builder is record
      Items : Byte_List (1 .. 8192) := [others => 0];
      Count : Natural := 0;
   end record;

   procedure Add (B : in out Builder; Value : Byte);

   procedure Add (B : in out Builder; Value : Byte) is
   begin
      B.Count := B.Count + 1;
      B.Items (B.Count) := Value;
   end Add;

   function List (B : Builder) return Byte_List is (B.Items (1 .. B.Count));

   ---------------------------------------------------------------------
   --  From a text to codewords
   ---------------------------------------------------------------------

   function ASCII (Text : String) return Byte_List is
      R : Builder;
      I : Positive := Text'First;
      C : Natural;
   begin
      while I <= Text'Last loop
         C := Character'Pos (Text (I));
         if I < Text'Last and then Text (I) in '0' .. '9'
           and then Text (I + 1) in '0' .. '9'
         then
            Add (R, 130 + (C - 48) * 10 + Character'Pos (Text (I + 1)) - 48);
            I := I + 2;
         elsif C < 128 then
            Add (R, C + 1);
            I := I + 1;
         else
            Add (R, 235);
            Add (R, C - 128 + 1);
            I := I + 1;
         end if;
      end loop;
      return List (R);
   end ASCII;

   procedure Add_Values
     (V        : in out Builder;
      Code     : Natural;
      Text_Set : Boolean);
   --  The values of the character Code in the C40 encodation or in the
   --  Text encodation.

   procedure Add_Values
     (V        : in out Builder;
      Code     : Natural;
      Text_Set : Boolean)
   is
      C : Natural := Code;
   begin
      if C >= 128 then
         --  Shift 2, upper shift.
         Add (V, 1);
         Add (V, 30);
         C := C - 128;
      end if;

      if C = 32 then
         Add (V, 3);
      elsif C in 48 .. 57 then
         Add (V, C - 48 + 4);
      elsif not Text_Set and then C in 65 .. 90 then
         Add (V, C - 65 + 14);
      elsif Text_Set and then C in 97 .. 122 then
         Add (V, C - 97 + 14);
      elsif C < 32 then
         Add (V, 0);
         Add (V, C);
      elsif C in 33 .. 47 then
         Add (V, 1);
         Add (V, C - 33);
      elsif C in 58 .. 64 then
         Add (V, 1);
         Add (V, C - 58 + 15);
      elsif C in 91 .. 95 then
         Add (V, 1);
         Add (V, C - 91 + 22);
      elsif not Text_Set then
         --  96 .. 127.
         Add (V, 2);
         Add (V, C - 96);
      elsif C = 96 then
         Add (V, 2);
         Add (V, 0);
      elsif C in 65 .. 90 then
         Add (V, 2);
         Add (V, C - 65 + 1);
      else
         --  123 .. 127.
         Add (V, 2);
         Add (V, C - 123 + 27);
      end if;
   end Add_Values;

   function Packed (Latch : Byte; Values : Builder) return Byte_List;
   --  The latch, the values three to two codewords (two values at the
   --  end are filled up with the value of shift 1), the unlatch.

   function Packed (Latch : Byte; Values : Builder) return Byte_List is
      V    : Builder := Values;
      R    : Builder;
      Full : Natural;
   begin
      if V.Count mod 3 = 2 then
         Add (V, 0);
      elsif V.Count mod 3 = 1 then
         raise Program_Error with "one value left over";
      end if;

      Add (R, Latch);
      for T in 0 .. V.Count / 3 - 1 loop
         Full := 1600 * V.Items (3 * T + 1) + 40 * V.Items (3 * T + 2)
                 + V.Items (3 * T + 3) + 1;
         Add (R, Full / 256);
         Add (R, Full mod 256);
      end loop;
      Add (R, 254);
      return List (R);
   end Packed;

   function Shifted
     (Latch    : Byte;
      Text     : String;
      Text_Set : Boolean) return Byte_List;
   --  The C40 or the Text encodation of Text.

   function Shifted
     (Latch    : Byte;
      Text     : String;
      Text_Set : Boolean) return Byte_List
   is
      V     : Builder;
      Count : Natural := 0;
      Last  : Natural := Text'First - 1;
      --  The characters up to Last have Count values, which can end the
      --  encodation.
   begin
      for I in Text'Range loop
         Add_Values (V, Character'Pos (Text (I)), Text_Set);
         if V.Count mod 3 /= 1 then
            Count := V.Count;
            Last := I;
         end if;
      end loop;
      V.Count := Count;
      return Packed (Latch, V) & ASCII (Text (Last + 1 .. Text'Last));
   end Shifted;

   function C40 (Text : String) return Byte_List is
     (Shifted (230, Text, Text_Set => False));

   function Lower (Text : String) return Byte_List is
     (Shifted (239, Text, Text_Set => True));

   function X12 (Text : String) return Byte_List is
      V : Builder;
   begin
      if Text'Length mod 3 /= 0 then
         raise Constraint_Error with "X12: not a multiple of three";
      end if;

      for C of Text loop
         case C is
            when Character'Val (13) =>
               Add (V, 0);
            when '*' =>
               Add (V, 1);
            when '>' =>
               Add (V, 2);
            when ' ' =>
               Add (V, 3);
            when '0' .. '9' =>
               Add (V, Character'Pos (C) - 48 + 4);
            when 'A' .. 'Z' =>
               Add (V, Character'Pos (C) - 65 + 14);
            when others =>
               raise Constraint_Error with "X12: no such character";
         end case;
      end loop;
      return Packed (238, V);
   end X12;

   function EDIFACT (Text : String) return Byte_List is
      V    : Builder;
      R    : Builder;
      I    : Positive := 1;
      K    : Positive;
      Bits : Natural;
   begin
      for C of Text loop
         if Character'Pos (C) not in 32 .. 94 then
            raise Constraint_Error with "EDIFACT: no such character";
         end if;
         Add (V, Character'Pos (C) mod 64);
      end loop;
      Add (V, 31);

      Add (R, 240);
      while I <= V.Count loop
         K := Natural'Min (4, V.Count - I + 1);
         Bits := 0;
         for J in 0 .. 3 loop
            Bits := Bits * 64 + (if J < K then V.Items (I + J) else 0);
         end loop;
         Add (R, Bits / 65536);
         if K >= 2 then
            Add (R, (Bits / 256) mod 256);
         end if;
         if K >= 3 then
            Add (R, Bits mod 256);
         end if;
         I := I + 4;
      end loop;
      return List (R);
   end EDIFACT;

   function Hidden (Value : Byte; Place : Positive) return Byte is
     ((Value + (149 * Place) mod 255 + 1) mod 256);

   function Base_256
     (Text  : String;
      First : Positive := 1) return Byte_List
   is
      R : Builder;
      P : Positive := First + 1;
      --  The place of the next codeword.

      procedure Put (Value : Byte);

      procedure Put (Value : Byte) is
      begin
         Add (R, Hidden (Value, P));
         P := P + 1;
      end Put;
   begin
      if Text'Length = 0 then
         raise Constraint_Error with "Base 256: no bytes";
      end if;

      Add (R, 231);
      if Text'Length < 250 then
         Put (Text'Length);
      else
         Put (Text'Length / 250 + 249);
         Put (Text'Length mod 250);
      end if;
      for C of Text loop
         Put (Character'Pos (C));
      end loop;
      return List (R);
   end Base_256;

   ---------------------------------------------------------------------
   --  From codewords to a symbol
   ---------------------------------------------------------------------

   function Smallest_Size
     (Count       : Positive;
      Rectangular : Boolean := False) return DM.Size_Index
   is
      First : constant DM.Size_Index := (if Rectangular then 25 else 1);
      Last  : constant DM.Size_Index := (if Rectangular then 30 else 24);
   begin
      for S in First .. Last loop
         if DM.Sizes (S).Data >= Count then
            return S;
         end if;
      end loop;
      raise Constraint_Error with "no size has so many codewords";
   end Smallest_Size;

   function Padded
     (Data : Byte_List;
      Size : DM.Size_Index) return Byte_List
   is
      R : Byte_List (1 .. DM.Sizes (Size).Data);
      V : Natural;
   begin
      R (1 .. Data'Length) := Data;
      for P in Data'Length + 1 .. R'Last loop
         if P = Data'Length + 1 then
            R (P) := 129;
         else
            --  A pad hidden behind a number that follows from its place.
            V := 129 + (149 * P) mod 253 + 1;
            R (P) := (if V > 254 then V - 254 else V);
         end if;
      end loop;
      return R;
   end Padded;

   function "xor" (A, B : Byte) return Byte is
     (Byte (Unsigned_8 (A) xor Unsigned_8 (B)));

   function Mul (A, B : Byte) return Byte;
   --  The product in GF(256) modulo x**8 + x**5 + x**3 + x**2 + 1.

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
            X := X xor 16#12D#;
         end if;
         Y := Y / 2;
      end loop;
      return Byte (R);
   end Mul;

   function Stream
     (Data : Byte_List;
      Size : DM.Size_Index) return Byte_List
   is
      Info   : constant DM.Size_Info := DM.Sizes (Size);
      Blocks : constant Positive := Info.Blocks;
      Parity : constant Positive := Info.Check / Blocks;

      type Polynomial is array (Natural range <>) of Byte;

      G : Polynomial (0 .. Parity) := [0 => 1, others => 0];
      --  The generator: the product of (x + Alpha ** J), J = 1 .. Parity.
      --  G (K) is the coefficient of x ** K.
      Remainder : Polynomial (0 .. Parity - 1);
      Root      : Byte := 1;
      Top       : Byte;
      K         : Natural;

      R : Byte_List (1 .. Info.Data + Info.Check) := [others => 0];
   begin
      if Data'Length /= Info.Data then
         raise Constraint_Error with "not the codewords of the size";
      end if;
      R (1 .. Info.Data) := Data;

      for J in 1 .. Parity loop
         Root := Mul (Root, 2);
         for K in reverse 0 .. J loop
            G (K) := Mul (G (K), Root) xor (if K > 0 then G (K - 1) else 0);
         end loop;
      end loop;

      --  The codewords of the message go to the blocks in turn, and the
      --  check codewords follow in turn where they left off.

      for B in 0 .. Blocks - 1 loop
         Remainder := [others => 0];
         for P in 1 .. Info.Data loop
            if (P - 1) mod Blocks = B then
               Top := R (P) xor Remainder (Parity - 1);
               for K in reverse 1 .. Parity - 1 loop
                  Remainder (K) := Remainder (K - 1) xor Mul (Top, G (K));
               end loop;
               Remainder (0) := Mul (Top, G (0));
            end if;
         end loop;

         K := Parity;
         for P in Info.Data + 1 .. R'Last loop
            if (P - 1) mod Blocks = B then
               K := K - 1;
               R (P) := Remainder (K);
            end if;
         end loop;
      end loop;

      return R;
   end Stream;

   function Symbol_Row
     (Size : DM.Size_Index;
      Row  : Natural) return Natural
   is (Row + 1 + 2 * (Row / DM.Sizes (Size).Region_Rows));

   function Symbol_Column
     (Size   : DM.Size_Index;
      Column : Natural) return Natural
   is (Column + 1 + 2 * (Column / DM.Sizes (Size).Region_Columns));

   function Marks (Size : DM.Size_Index) return Mark_Matrix is
      Info  : constant DM.Size_Info := DM.Sizes (Size);
      N_Row : constant Positive := Info.Region_Rows * Info.Regions_Down;
      N_Col : constant Positive := Info.Region_Columns * Info.Regions_Across;

      A   : Mark_Matrix (0 .. N_Row - 1, 0 .. N_Col - 1) :=
        [others => [others => 0]];
      Row : Integer := 4;
      Col : Integer := 0;
      Chr : Positive := 1;

      procedure Module (Row, Col : Integer; Bit : Positive);
      procedure Utah (Row, Col : Integer);
      procedure Corner (Which : Positive);

      procedure Module (Row, Col : Integer; Bit : Positive) is
         R : Integer := Row;
         C : Integer := Col;
      begin
         if R < 0 then
            R := R + N_Row;
            C := C + 4 - (N_Row + 4) mod 8;
         end if;
         if C < 0 then
            C := C + N_Col;
            R := R + 4 - (N_Col + 4) mod 8;
         end if;
         if R >= N_Row then
            --  Only in two sizes of the rectangular extension.
            R := R - N_Row;
         end if;
         A (R, C) := 10 * Chr + Bit;
      end Module;

      procedure Utah (Row, Col : Integer) is
      begin
         Module (Row - 2, Col - 2, 1);
         Module (Row - 2, Col - 1, 2);
         Module (Row - 1, Col - 2, 3);
         Module (Row - 1, Col - 1, 4);
         Module (Row - 1, Col, 5);
         Module (Row, Col - 2, 6);
         Module (Row, Col - 1, 7);
         Module (Row, Col, 8);
         Chr := Chr + 1;
      end Utah;

      procedure Corner (Which : Positive) is
      begin
         case Which is
            when 1 =>
               Module (N_Row - 1, 0, 1);
               Module (N_Row - 1, 1, 2);
               Module (N_Row - 1, 2, 3);
               Module (0, N_Col - 2, 4);
               Module (0, N_Col - 1, 5);
               Module (1, N_Col - 1, 6);
               Module (2, N_Col - 1, 7);
               Module (3, N_Col - 1, 8);
            when 2 =>
               Module (N_Row - 3, 0, 1);
               Module (N_Row - 2, 0, 2);
               Module (N_Row - 1, 0, 3);
               Module (0, N_Col - 4, 4);
               Module (0, N_Col - 3, 5);
               Module (0, N_Col - 2, 6);
               Module (0, N_Col - 1, 7);
               Module (1, N_Col - 1, 8);
            when 3 =>
               Module (N_Row - 3, 0, 1);
               Module (N_Row - 2, 0, 2);
               Module (N_Row - 1, 0, 3);
               Module (0, N_Col - 2, 4);
               Module (0, N_Col - 1, 5);
               Module (1, N_Col - 1, 6);
               Module (2, N_Col - 1, 7);
               Module (3, N_Col - 1, 8);
            when others =>
               Module (N_Row - 1, 0, 1);
               Module (N_Row - 1, N_Col - 1, 2);
               Module (0, N_Col - 3, 3);
               Module (0, N_Col - 2, 4);
               Module (0, N_Col - 1, 5);
               Module (1, N_Col - 3, 6);
               Module (1, N_Col - 2, 7);
               Module (1, N_Col - 1, 8);
         end case;
         Chr := Chr + 1;
      end Corner;

      function Free return Boolean is
        (Row in 0 .. N_Row - 1 and then Col in 0 .. N_Col - 1
         and then A (Row, Col) = 0);
   begin
      loop
         if Row = N_Row and then Col = 0 then
            Corner (1);
         end if;
         if Row = N_Row - 2 and then Col = 0 and then N_Col mod 4 /= 0 then
            Corner (2);
         end if;
         if Row = N_Row - 2 and then Col = 0 and then N_Col mod 8 = 4 then
            Corner (3);
         end if;
         if Row = N_Row + 4 and then Col = 2 and then N_Col mod 8 = 0 then
            Corner (4);
         end if;

         --  Up and to the right.
         loop
            if Free then
               Utah (Row, Col);
            end if;
            Row := Row - 2;
            Col := Col + 2;
            exit when Row < 0 or else Col >= N_Col;
         end loop;
         Row := Row + 1;
         Col := Col + 3;

         --  Down and to the left.
         loop
            if Free then
               Utah (Row, Col);
            end if;
            Row := Row + 2;
            Col := Col - 2;
            exit when Row >= N_Row or else Col < 0;
         end loop;
         Row := Row + 3;
         Col := Col + 1;

         exit when Row >= N_Row and then Col >= N_Col;
      end loop;

      if A (N_Row - 1, N_Col - 1) = 0 then
         A (N_Row - 1, N_Col - 1) := 1;
         A (N_Row - 2, N_Col - 2) := 1;
      end if;
      return A;
   end Marks;

   function Modules
     (Codewords : Byte_List;
      Size      : DM.Size_Index) return Module_Matrix
   is
      Info : constant DM.Size_Info := DM.Sizes (Size);
      A    : constant Mark_Matrix := Marks (Size);
      H    : constant Positive := Info.Region_Rows + 2;
      W    : constant Positive := Info.Region_Columns + 2;
      M    : Module_Matrix (0 .. Info.Rows - 1, 0 .. Info.Columns - 1) :=
        [others => [others => False]];
      Mark : Natural;
   begin
      if Codewords'First /= 1
        or else Codewords'Length /= Info.Data + Info.Check
      then
         raise Constraint_Error with "not the codewords of the size";
      end if;

      --  The border of each region: the left column and the bottom row
      --  dark, the top row and the right column alternating.

      for R in M'Range (1) loop
         for C in M'Range (2) loop
            if C mod W = 0 or else R mod H = H - 1 then
               M (R, C) := True;
            elsif R mod H = 0 then
               M (R, C) := C mod 2 = 0;
            elsif C mod W = W - 1 then
               M (R, C) := R mod 2 = 1;
            end if;
         end loop;
      end loop;

      for R in A'Range (1) loop
         for C in A'Range (2) loop
            Mark := A (R, C);
            M (Symbol_Row (Size, R), Symbol_Column (Size, C)) :=
              (if Mark >= 10
               then (Codewords (Mark / 10) / 2 ** (8 - Mark mod 10)) mod 2
                    = 1
               else Mark = 1);
         end loop;
      end loop;
      return M;
   end Modules;

   function Grid (Symbol : Module_Matrix) return DM.Module_Grid is
      G : DM.Module_Grid := [others => [others => False]];
   begin
      for R in Symbol'Range (1) loop
         for C in Symbol'Range (2) loop
            G (DM.Module_Index (R), DM.Module_Index (C)) := Symbol (R, C);
         end loop;
      end loop;
      return G;
   end Grid;

   ---------------------------------------------------------------------
   --  From the modules to an image
   ---------------------------------------------------------------------

   function Placed
     (Center_X, Center_Y : Long_Float;
      Width, Height      : Long_Float;
      Rotation           : Long_Float := 0.0;
      Mirror             : Boolean := False) return Corners
   is
      C  : constant Long_Float := EF.Cos (Rotation);
      S  : constant Long_Float := EF.Sin (Rotation);
      --  Along the lower side: (C, S). From the upper side to the lower
      --  one: (-S, C), and the other way in a mirror image.
      HX : constant Long_Float := 0.5 * Width * C;
      HY : constant Long_Float := 0.5 * Width * S;
      Turn : constant Long_Float := (if Mirror then -1.0 else 1.0);
      VX : constant Long_Float := -0.5 * Height * S * Turn;
      VY : constant Long_Float := 0.5 * Height * C * Turn;
   begin
      return (Upper_Left  => (Center_X - HX - VX, Center_Y - HY - VY),
              Upper_Right => (Center_X + HX - VX, Center_Y + HY - VY),
              Lower_Right => (Center_X + HX + VX, Center_Y + HY + VY),
              Lower_Left  => (Center_X - HX + VX, Center_Y - HY + VY));
   end Placed;

   type Mapping is array (1 .. 3, 1 .. 3) of Long_Float;

   function From_Square (Where : Corners) return Mapping;
   --  The perspective mapping that takes (0, 0), (1, 0), (1, 1) and
   --  (0, 1) to the upper left, upper right, lower right and lower left
   --  corner: X = (M11 U + M12 V + M13) / (M31 U + M32 V + M33), and Y
   --  with the second row.

   function From_Square (Where : Corners) return Mapping is
      P0  : Place renames Where.Upper_Left;
      P1  : Place renames Where.Upper_Right;
      P2  : Place renames Where.Lower_Right;
      P3  : Place renames Where.Lower_Left;
      DX1 : constant Long_Float := P1.X - P2.X;
      DX2 : constant Long_Float := P3.X - P2.X;
      DY1 : constant Long_Float := P1.Y - P2.Y;
      DY2 : constant Long_Float := P3.Y - P2.Y;
      SX  : constant Long_Float := P0.X - P1.X + P2.X - P3.X;
      SY  : constant Long_Float := P0.Y - P1.Y + P2.Y - P3.Y;
      Det : constant Long_Float := DX1 * DY2 - DX2 * DY1;
      G   : constant Long_Float := (SX * DY2 - DX2 * SY) / Det;
      H   : constant Long_Float := (DX1 * SY - SX * DY1) / Det;
   begin
      return [[P1.X - P0.X + G * P1.X, P3.X - P0.X + H * P3.X, P0.X],
              [P1.Y - P0.Y + G * P1.Y, P3.Y - P0.Y + H * P3.Y, P0.Y],
              [G, H, 1.0]];
   end From_Square;

   function Adjugate (M : Mapping) return Mapping is
     [[M (2, 2) * M (3, 3) - M (2, 3) * M (3, 2),
       M (1, 3) * M (3, 2) - M (1, 2) * M (3, 3),
       M (1, 2) * M (2, 3) - M (1, 3) * M (2, 2)],
      [M (2, 3) * M (3, 1) - M (2, 1) * M (3, 3),
       M (1, 1) * M (3, 3) - M (1, 3) * M (3, 1),
       M (1, 3) * M (2, 1) - M (1, 1) * M (2, 3)],
      [M (2, 1) * M (3, 2) - M (2, 2) * M (3, 1),
       M (1, 2) * M (3, 1) - M (1, 1) * M (3, 2),
       M (1, 1) * M (2, 2) - M (1, 2) * M (2, 1)]];
   --  The inverse mapping (a mapping times a number is the same one).

   function Middle (Where : Corners) return Place is
      M : constant Mapping := From_Square (Where);
      W : constant Long_Float := 0.5 * M (3, 1) + 0.5 * M (3, 2) + M (3, 3);
   begin
      --  The diagonals of the square cross at (0.5, 0.5).
      return ((0.5 * M (1, 1) + 0.5 * M (1, 2) + M (1, 3)) / W,
              (0.5 * M (2, 1) + 0.5 * M (2, 2) + M (2, 3)) / W);
   end Middle;

   procedure Draw
     (Image  : in out AMV.Images.Ks_Image_8_Grey;
      Symbol : Module_Matrix;
      Where  : Corners;
      Dark   : AMV.Images.Grey_8 := 0)
   is
      use AMV.Images;

      Samples : constant := 4;

      Back : constant Mapping := Adjugate (From_Square (Where));
      Rows : constant Long_Float := Long_Float (Symbol'Length (1));
      Cols : constant Long_Float := Long_Float (Symbol'Length (2));

      Left   : constant Long_Float :=
        Long_Float'Min
          (Long_Float'Min (Where.Upper_Left.X, Where.Upper_Right.X),
           Long_Float'Min (Where.Lower_Left.X, Where.Lower_Right.X));
      Right  : constant Long_Float :=
        Long_Float'Max
          (Long_Float'Max (Where.Upper_Left.X, Where.Upper_Right.X),
           Long_Float'Max (Where.Lower_Left.X, Where.Lower_Right.X));
      Top    : constant Long_Float :=
        Long_Float'Min
          (Long_Float'Min (Where.Upper_Left.Y, Where.Upper_Right.Y),
           Long_Float'Min (Where.Lower_Left.Y, Where.Lower_Right.Y));
      Bottom : constant Long_Float :=
        Long_Float'Max
          (Long_Float'Max (Where.Upper_Left.Y, Where.Upper_Right.Y),
           Long_Float'Max (Where.Lower_Left.Y, Where.Lower_Right.Y));

      function Clamped (Value : Long_Float; Last : Integer) return Integer is
        (if Value <= 0.0 then 0
         elsif Value >= Long_Float (Last) then Last
         else Integer (Value));

      X_Lo : constant Integer := Clamped (Left - 1.0, Image.Width - 1);
      X_Hi : constant Integer := Clamped (Right + 1.0, Image.Width - 1);
      Y_Lo : constant Integer := Clamped (Top - 1.0, Image.Height - 1);
      Y_Hi : constant Integer := Clamped (Bottom + 1.0, Image.Height - 1);

      PX, PY  : Long_Float;
      U, V, W : Long_Float;
      Hits    : Natural;
      Old     : Long_Float;
   begin
      for Y in Y_Lo .. Y_Hi loop
         declare
            Row     : Grey_8_Row (0 .. Image.Width - 1);
            Changed : Boolean := False;
            --  Written a row at a time: the tests check the postconditions
            --  of the image kernel, and those of its pixel setter compare
            --  the whole image at every call.
         begin
            for X in Row'Range loop
               Row (X) := Image.Get_Pixel (X, Y);
            end loop;
            for X in X_Lo .. X_Hi loop
               Hits := 0;
               for J in 0 .. Samples - 1 loop
                  PY := Long_Float (Y) - 0.5
                    + (Long_Float (J) + 0.5) / Long_Float (Samples);
                  for I in 0 .. Samples - 1 loop
                     PX := Long_Float (X) - 0.5
                       + (Long_Float (I) + 0.5) / Long_Float (Samples);
                     W := Back (3, 1) * PX + Back (3, 2) * PY + Back (3, 3);
                     if W /= 0.0 then
                        U := (Back (1, 1) * PX + Back (1, 2) * PY
                              + Back (1, 3)) / W;
                        V := (Back (2, 1) * PX + Back (2, 2) * PY
                              + Back (2, 3)) / W;
                        if U >= 0.0 and then U < 1.0 and then V >= 0.0
                          and then V < 1.0
                          and then Symbol
                            (Symbol'First (1)
                             + Natural (Long_Float'Floor (V * Rows)),
                             Symbol'First (2)
                             + Natural (Long_Float'Floor (U * Cols)))
                        then
                           Hits := Hits + 1;
                        end if;
                     end if;
                  end loop;
               end loop;
               if Hits > 0 then
                  Old := Long_Float (Row (X));
                  Row (X) :=
                    Grey_8 (Old + (Long_Float (Dark) - Old)
                                  * Long_Float (Hits)
                                  / Long_Float (Samples * Samples));
                  Changed := True;
               end if;
            end loop;
            if Changed then
               Image.Set_Row (Y, Row);
            end if;
         end;
      end loop;
   end Draw;

end AMV_Test_Data_Matrix;
