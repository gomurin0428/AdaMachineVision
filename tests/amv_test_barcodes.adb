with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;

with AMV_Test_Images;

package body AMV_Test_Barcodes is

   package EF renames Ada.Numerics.Long_Elementary_Functions;

   subtype Digit is Natural range 0 .. 9;

   function Value (C : Character) return Digit is
     (Character'Pos (C) - Character'Pos ('0'));
   --  Constraint_Error unless C is a digit.

   function Image (D : Digit) return Character is
     (Character'Val (Character'Pos ('0') + D));

   function Total (Widths : Width_List) return Real is
      Sum : Real := 0.0;
   begin
      for W of Widths loop
         Sum := Sum + W;
      end loop;
      return Sum;
   end Total;

   function Runs (Pattern : String) return Width_List;
   --  The runs of a string of '1' (dark) and '0' (light) modules that
   --  starts and ends dark.

   function Runs (Pattern : String) return Width_List is
      Result : Width_List (1 .. Pattern'Length);
      Count  : Natural := 0;
   begin
      for I in Pattern'Range loop
         if I = Pattern'First or else Pattern (I) /= Pattern (I - 1) then
            Count := Count + 1;
            Result (Count) := 1.0;
         else
            Result (Count) := Result (Count) + 1.0;
         end if;
      end loop;
      if Pattern (Pattern'First) /= '1' or else Count mod 2 = 0 then
         raise Constraint_Error with "Runs: not from bar to bar";
      end if;
      return Result (1 .. Count);
   end Runs;

   ---------------------------------------------------------------------
   --  EAN and UPC
   ---------------------------------------------------------------------

   subtype Seven is String (1 .. 7);

   Set_L : constant array (Digit) of Seven :=
     ["0001101", "0011001", "0010011", "0111101", "0100011",
      "0110001", "0101111", "0111011", "0110111", "0001011"];
   --  Number set A (odd parity). Set C (the right half) is its
   --  complement, set B (even parity) the mirror image of set C.

   function Set_R (D : Digit) return Seven;
   function Set_G (D : Digit) return Seven;

   function Set_R (D : Digit) return Seven is
      Result : Seven := Set_L (D);
   begin
      for C of Result loop
         C := (if C = '0' then '1' else '0');
      end loop;
      return Result;
   end Set_R;

   function Set_G (D : Digit) return Seven is
      R      : constant Seven := Set_R (D);
      Result : Seven;
   begin
      for I in Result'Range loop
         Result (I) := R (8 - I);
      end loop;
      return Result;
   end Set_G;

   subtype Six is String (1 .. 6);

   EAN_13_Parity : constant array (Digit) of Six :=
     ["LLLLLL", "LLGLGG", "LLGGLG", "LLGGGL", "LGLLGG",
      "LGGLLG", "LGGGLL", "LGLGLG", "LGLGGL", "LGGLGL"];
   --  The number sets of the six left digits, by the first digit.

   UPC_E_Parity : constant array (Digit) of Six :=
     ["GGGLLL", "GGLGLL", "GGLLGL", "GGLLLG", "GLGGLL",
      "GLLGGL", "GLLLGG", "GLGLGL", "GLGLLG", "GLLGLG"];
   --  The number sets of the six digits of a UPC-E symbol of number
   --  system 0, by the check digit. Number system 1 swaps the sets.

   function Encode (D : Digit; Set : Character) return Seven is
     (case Set is
         when 'L'    => Set_L (D),
         when 'G'    => Set_G (D),
         when others => Set_R (D));

   function Check_Digit (Digit_Text : String) return Character is
      Sum    : Natural := 0;
      Weight : Positive := 3;
   begin
      for I in reverse Digit_Text'Range loop
         Sum := Sum + Weight * Value (Digit_Text (I));
         Weight := 4 - Weight;
      end loop;
      return Image ((10 - Sum mod 10) mod 10);
   end Check_Digit;

   function EAN_13 (Digit_Text : String) return Width_List is
      D       : constant String (1 .. 13) := Digit_Text;
      Parity  : constant Six := EAN_13_Parity (Value (D (1)));
      Pattern : String (1 .. 95);
      Last    : Natural := 0;

      procedure Put (S : String);

      procedure Put (S : String) is
      begin
         Pattern (Last + 1 .. Last + S'Length) := S;
         Last := Last + S'Length;
      end Put;
   begin
      Put ("101");
      for I in 1 .. 6 loop
         Put (Encode (Value (D (I + 1)), Parity (I)));
      end loop;
      Put ("01010");
      for I in 8 .. 13 loop
         Put (Encode (Value (D (I)), 'R'));
      end loop;
      Put ("101");
      return Runs (Pattern);
   end EAN_13;

   function EAN_8 (Digit_Text : String) return Width_List is
      D       : constant String (1 .. 8) := Digit_Text;
      Pattern : String (1 .. 67);
      Last    : Natural := 0;

      procedure Put (S : String);

      procedure Put (S : String) is
      begin
         Pattern (Last + 1 .. Last + S'Length) := S;
         Last := Last + S'Length;
      end Put;
   begin
      Put ("101");
      for I in 1 .. 4 loop
         Put (Encode (Value (D (I)), 'L'));
      end loop;
      Put ("01010");
      for I in 5 .. 8 loop
         Put (Encode (Value (D (I)), 'R'));
      end loop;
      Put ("101");
      return Runs (Pattern);
   end EAN_8;

   function UPC_A (Digit_Text : String) return Width_List is
      D : constant String (1 .. 12) := Digit_Text;
   begin
      return EAN_13 ("0" & D);
   end UPC_A;

   function UPC_E_Check_Digit (Digit_Text : String) return Character is
      D : constant String (1 .. 7) := Digit_Text;
      --  The number system and the six digits.
   begin
      case D (7) is
         when '0' .. '2' =>
            return Check_Digit
              (D (1 .. 3) & D (7) & "0000" & D (4 .. 6));
         when '3' =>
            return Check_Digit (D (1 .. 4) & "00000" & D (5 .. 6));
         when '4' =>
            return Check_Digit (D (1 .. 5) & "00000" & D (6 .. 6));
         when others =>
            return Check_Digit (D (1 .. 6) & "0000" & D (7 .. 7));
      end case;
   end UPC_E_Check_Digit;

   function UPC_E (Digit_Text : String) return Width_List is
      D       : constant String (1 .. 8) := Digit_Text;
      Parity  : Six := UPC_E_Parity (Value (D (8)));
      Pattern : String (1 .. 51);
      Last    : Natural := 0;

      procedure Put (S : String);

      procedure Put (S : String) is
      begin
         Pattern (Last + 1 .. Last + S'Length) := S;
         Last := Last + S'Length;
      end Put;
   begin
      case D (1) is
         when '0' =>
            null;
         when '1' =>
            for C of Parity loop
               C := (if C = 'L' then 'G' else 'L');
            end loop;
         when others =>
            raise Constraint_Error with "UPC_E: number system 0 or 1";
      end case;
      Put ("101");
      for I in 1 .. 6 loop
         Put (Encode (Value (D (I + 1)), Parity (I)));
      end loop;
      Put ("010101");
      return Runs (Pattern);
   end UPC_E;

   ---------------------------------------------------------------------
   --  Code 128
   ---------------------------------------------------------------------

   Code_128_Patterns : constant array (0 .. 105) of Six :=
     ["212222", "222122", "222221", "121223", "121322", "131222",
      "122213", "122312", "132212", "221213", "221312", "231212",
      "112232", "122132", "122231", "113222", "123122", "123221",
      "223211", "221132", "221231", "213212", "223112", "312131",
      "311222", "321122", "321221", "312212", "322112", "322211",
      "212123", "212321", "232121", "111323", "131123", "131321",
      "112313", "132113", "132311", "211313", "231113", "231311",
      "112133", "112331", "132131", "113123", "113321", "133121",
      "313121", "211331", "231131", "213113", "213311", "213131",
      "311123", "311321", "331121", "312113", "312311", "332111",
      "314111", "221411", "431111", "111224", "111422", "121124",
      "121421", "141122", "141221", "112214", "112412", "122114",
      "122411", "142112", "142211", "241211", "221114", "413111",
      "241112", "134111", "111242", "121142", "121241", "114212",
      "124112", "124211", "411212", "421112", "421211", "212141",
      "214121", "412121", "111143", "111341", "131141", "114113",
      "114311", "411113", "411311", "113141", "114131", "311141",
      "411131", "211412", "211214", "211232"];
   --  The widths of the three bars and three spaces of every symbol
   --  character (bar, space, bar, space, bar, space).

   Code_128_Stop : constant String := "2331112";

   function Code_128
     (Values      : Value_List;
      Check_Error : Natural := 0) return Width_List
   is
      Result : Width_List (1 .. 6 * (Values'Length + 1) + 7);
      Last   : Natural := 0;
      Sum    : Natural := Values (Values'First);

      procedure Put (S : String);

      procedure Put (S : String) is
      begin
         for C of S loop
            Last := Last + 1;
            Result (Last) := Real (Value (C));
         end loop;
      end Put;
   begin
      for I in Values'Range loop
         Put (Code_128_Patterns (Values (I)));
         if I > Values'First then
            Sum := Sum + (I - Values'First) * Values (I);
         end if;
      end loop;
      Put (Code_128_Patterns ((Sum + Check_Error) mod 103));
      Put (Code_128_Stop);
      return Result;
   end Code_128;

   function Code_128_B (Text : String) return Width_List is
      Values : Value_List (1 .. Text'Length + 1);
   begin
      Values (1) := Start_B;
      for I in Text'Range loop
         Values (I - Text'First + 2) := Character'Pos (Text (I)) - 32;
      end loop;
      return Code_128 (Values);
   end Code_128_B;

   function Code_128_C (Digit_Text : String) return Width_List is
      D      : constant String (1 .. Digit_Text'Length) := Digit_Text;
      Values : Value_List (1 .. D'Length / 2 + 1);
   begin
      if D'Length mod 2 /= 0 then
         raise Constraint_Error with "Code_128_C: an odd number of digits";
      end if;
      Values (1) := Start_C;
      for I in 1 .. D'Length / 2 loop
         Values (I + 1) := 10 * Value (D (2 * I - 1)) + Value (D (2 * I));
      end loop;
      return Code_128 (Values);
   end Code_128_C;

   ---------------------------------------------------------------------
   --  Code 39 and Interleaved 2 of 5
   ---------------------------------------------------------------------

   subtype Five is String (1 .. 5);

   Two_Of_Five : constant array (Digit) of Five :=
     ["nnwwn", "wnnnw", "nwnnw", "wwnnn", "nnwnw",
      "wnwnn", "nwwnn", "nnnww", "wnnwn", "nwnwn"];
   --  Two wide elements of five, with the weights 1, 2, 4, 7 and parity
   --  (the digit 0 has the weights 4 and 7).

   Code_39_Characters : constant String :=
     "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ-. $/+%";
   --  In the order of their values, 0 .. 42.

   Code_39_Groups : constant array (1 .. 4) of String (1 .. 10) :=
     ["1234567890", "ABCDEFGHIJ", "KLMNOPQRST", "UVWXYZ-. *"];
   --  The character at position P of a group has the bars of the digit
   --  P mod 10; the group selects which of the four spaces is wide.

   Code_39_Wide_Space : constant array (1 .. 4) of Positive := [2, 3, 4, 1];

   subtype Nine is String (1 .. 9);

   function Code_39_Pattern (C : Character) return Nine;
   --  Bar, space, bar, space, bar, space, bar, space, bar.

   function Code_39_Pattern (C : Character) return Nine is
      Result : Nine := "nnnnnnnnn";
   begin
      case C is
         when '$' =>
            Result (2) := 'w';
            Result (4) := 'w';
            Result (6) := 'w';
         when '/' =>
            Result (2) := 'w';
            Result (4) := 'w';
            Result (8) := 'w';
         when '+' =>
            Result (2) := 'w';
            Result (6) := 'w';
            Result (8) := 'w';
         when '%' =>
            Result (4) := 'w';
            Result (6) := 'w';
            Result (8) := 'w';
         when others =>
            for G in Code_39_Groups'Range loop
               for P in 1 .. 10 loop
                  if Code_39_Groups (G) (P) = C then
                     for B in 1 .. 5 loop
                        Result (2 * B - 1) := Two_Of_Five (P mod 10) (B);
                     end loop;
                     Result (2 * Code_39_Wide_Space (G)) := 'w';
                     return Result;
                  end if;
               end loop;
            end loop;
            raise Constraint_Error with "Code_39: not a Code 39 character";
      end case;
      return Result;
   end Code_39_Pattern;

   function Code_39_Value (C : Character) return Natural;

   function Code_39_Value (C : Character) return Natural is
   begin
      for I in Code_39_Characters'Range loop
         if Code_39_Characters (I) = C then
            return I - Code_39_Characters'First;
         end if;
      end loop;
      raise Constraint_Error with "Code_39: not a Code 39 character";
   end Code_39_Value;

   function Code_39_Check (Text : String) return Character is
      Sum : Natural := 0;
   begin
      for C of Text loop
         Sum := Sum + Code_39_Value (C);
      end loop;
      return Code_39_Characters (Code_39_Characters'First + Sum mod 43);
   end Code_39_Check;

   function Code_39 (Text : String; Ratio : Real := 3.0) return Width_List is
      Symbol : constant String := "*" & Text & "*";
      Result : Width_List (1 .. 10 * Symbol'Length - 1);
      Last   : Natural := 0;
   begin
      for I in Symbol'Range loop
         if I > Symbol'First then
            Last := Last + 1;
            Result (Last) := 1.0;
         end if;
         if Symbol (I) = '*' and then I in Symbol'First + 1 .. Symbol'Last - 1
         then
            raise Constraint_Error with "Code_39: not a Code 39 character";
         end if;
         for E of Code_39_Pattern (Symbol (I)) loop
            Last := Last + 1;
            Result (Last) := (if E = 'w' then Ratio else 1.0);
         end loop;
      end loop;
      return Result;
   end Code_39;

   function ITF (Digit_Text : String; Ratio : Real := 3.0) return Width_List is
      D      : constant String (1 .. Digit_Text'Length) := Digit_Text;
      Result : Width_List (1 .. 4 + 5 * D'Length + 3);
      Last   : Natural := 0;

      procedure Put (Wide : Boolean);

      procedure Put (Wide : Boolean) is
      begin
         Last := Last + 1;
         Result (Last) := (if Wide then Ratio else 1.0);
      end Put;
   begin
      if D'Length mod 2 /= 0 then
         raise Constraint_Error with "ITF: an odd number of digits";
      end if;
      for I in 1 .. 4 loop
         Put (False);
      end loop;
      for P in 1 .. D'Length / 2 loop
         declare
            Bars   : constant Five := Two_Of_Five (Value (D (2 * P - 1)));
            Spaces : constant Five := Two_Of_Five (Value (D (2 * P)));
         begin
            for E in 1 .. 5 loop
               Put (Bars (E) = 'w');
               Put (Spaces (E) = 'w');
            end loop;
         end;
      end loop;
      Put (True);
      Put (False);
      Put (False);
      return Result;
   end ITF;

   ---------------------------------------------------------------------
   --  Drawing
   ---------------------------------------------------------------------

   procedure Draw
     (Image              : in out AMV.Images.Ks_Image_8_Grey;
      Widths             : Width_List;
      Center_X, Center_Y : Real;
      Module             : Real;
      Height             : Real;
      Rotation           : Real := 0.0;
      Dark               : AMV.Images.Grey_8 := 0;
      Bar_Growth         : Real := 0.0)
   is
      C   : constant Real := EF.Cos (Rotation);
      S   : constant Real := EF.Sin (Rotation);
      Pos : Real := -Total (Widths) / 2.0;
      --  The start of the current run, in modules from the centre.
   begin
      for I in Widths'Range loop
         if (I - Widths'First) mod 2 = 0 then
            declare
               T : constant Real := (Pos + Widths (I) / 2.0) * Module;
            begin
               AMV_Test_Images.Draw_Rectangle
                 (Image, Center_X + T * C, Center_Y + T * S,
                  Widths (I) * Module + Bar_Growth, Height, Rotation, Dark);
            end;
         end if;
         Pos := Pos + Widths (I);
      end loop;
   end Draw;

   procedure Blur
     (Image : in out AMV.Images.Ks_Image_8_Grey;
      Sigma : Real)
   is
      use AMV.Images;
   begin
      if Sigma <= 0.0 or else not Image.Allocated then
         return;
      end if;
      declare
         Reach  : constant Positive :=
           Positive (Real'Ceiling (3.0 * Sigma));
         Weight : array (-Reach .. Reach) of Real;
         Sum    : Real := 0.0;
         W      : constant Natural := Image.Width;
         H      : constant Natural := Image.Height;

         type Level_Matrix is
           array (Natural range <>, Natural range <>) of Real;
         type Level_Matrix_Access is access Level_Matrix;

         procedure Free is new Ada.Unchecked_Deallocation
           (Level_Matrix, Level_Matrix_Access);

         Rows   : Level_Matrix_Access :=
           new Level_Matrix (0 .. H - 1, 0 .. W - 1);
         --  Smoothed along x; on the heap, for the main stack of a test
         --  is small (see AMV_Test_Support).
         Acc    : Real;
      begin
         for K in Weight'Range loop
            Weight (K) := EF.Exp (-Real (K * K) / (2.0 * Sigma * Sigma));
            Sum := Sum + Weight (K);
         end loop;
         for Y in 0 .. H - 1 loop
            for X in 0 .. W - 1 loop
               Acc := 0.0;
               for K in Weight'Range loop
                  Acc := Acc
                    + Weight (K)
                      * Real (Image.Get_Pixel
                                (Integer'Max
                                   (0, Integer'Min (W - 1, X + K)), Y));
               end loop;
               Rows (Y, X) := Acc / Sum;
            end loop;
         end loop;
         for Y in 0 .. H - 1 loop
            for X in 0 .. W - 1 loop
               Acc := 0.0;
               for K in Weight'Range loop
                  Acc := Acc
                    + Weight (K)
                      * Rows (Integer'Max (0, Integer'Min (H - 1, Y + K)),
                              X);
               end loop;
               Image.Set_Pixel
                 (X, Y,
                  Grey_8 (Real'Max
                            (0.0, Real'Min (255.0,
                                            Real'Rounding (Acc / Sum)))));
            end loop;
         end loop;
         Free (Rows);
      end;
   end Blur;

   procedure Sharpen
     (Image  : in out AMV.Images.Ks_Image_8_Grey;
      Sigma  : Real;
      Amount : Real)
   is
      use AMV.Images;
   begin
      if Sigma <= 0.0 or else not Image.Allocated then
         return;
      end if;
      declare
         W : constant Natural := Image.Width;
         H : constant Natural := Image.Height;

         type Grey_Matrix is
           array (Natural range <>, Natural range <>) of Grey_8;
         type Grey_Matrix_Access is access Grey_Matrix;

         procedure Free is new Ada.Unchecked_Deallocation
           (Grey_Matrix, Grey_Matrix_Access);

         Before : Grey_Matrix_Access :=
           new Grey_Matrix (0 .. H - 1, 0 .. W - 1);
         --  The levels as they were; on the heap, as in Blur.
      begin
         for Y in 0 .. H - 1 loop
            for X in 0 .. W - 1 loop
               Before (Y, X) := Image.Get_Pixel (X, Y);
            end loop;
         end loop;
         Blur (Image, Sigma);
         for Y in 0 .. H - 1 loop
            for X in 0 .. W - 1 loop
               declare
                  Level  : constant Real := Real (Before (Y, X));
                  Smooth : constant Real := Real (Image.Get_Pixel (X, Y));
               begin
                  Image.Set_Pixel
                    (X, Y,
                     Grey_8 (Real'Max
                               (0.0,
                                Real'Min
                                  (255.0,
                                   Real'Rounding
                                     (Level
                                      + Amount * (Level - Smooth))))));
               end;
            end loop;
         end loop;
         Free (Before);
      end;
   end Sharpen;

   procedure Shade
     (Image       : in out AMV.Images.Ks_Image_8_Grey;
      Left, Right : Real)
   is
      use AMV.Images;
      W : constant Natural := Image.Width;
   begin
      for Y in 0 .. Image.Height - 1 loop
         for X in 0 .. W - 1 loop
            declare
               Factor : constant Real :=
                 (if W > 1
                  then Left + (Right - Left) * Real (X) / Real (W - 1)
                  else Left);
            begin
               Image.Set_Pixel
                 (X, Y,
                  Grey_8 (Real'Max
                            (0.0,
                             Real'Min
                               (255.0,
                                Real'Rounding
                                  (Factor
                                   * Real (Image.Get_Pixel (X, Y)))))));
            end;
         end loop;
      end loop;
   end Shade;

end AMV_Test_Barcodes;
