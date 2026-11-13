--  Tests for the IP one-image tool (AMV.Image_Processing.IP_One_Image)
--  through Run, and for its kernel (AMV.Kernels.IP_One_Image) called
--  directly for what the Ada API cannot reach: null handles, bad codes,
--  limits, non-finite values and the record layouts.
--
--  Every operator is compared pixel by pixel with a brute-force reference
--  written here from the definitions in AMV.Kernels.IP_One_Image (window
--  minima and maxima, a sorted window for the median, the binomial and box
--  sums, the convolution sums, the equalisation table, the flip and
--  rotation table), on small images of pseudo-random pixels (a linear
--  congruential generator), with kernels smaller and larger than the
--  image. Morphology identities, sequences of operators, regions, the
--  coordinate spaces of a turned, sampled or expanded image and the
--  timings of 640 x 480 runs are checked too.

pragma Validity_Checks ("F");
--  The kernel tests build a NaN on purpose.

with Ada.Exceptions;
with Ada.Text_IO;
with Interfaces;

with AMV;                    use AMV;
with AMV.Image_Processing.Affine_Transform;
with AMV.Image_Processing.IP_One_Image;
with AMV.Images;             use AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Images;
with AMV.Kernels.IP_One_Image;
with AMV.Kernels.Regions;
with AMV.Kernels.Transforms;
with AMV.Regions;
with AMV.Shapes;             use AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;              use AMV.Tools;
with AMV.Transforms;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_IP_One_Image is

   package IO renames AMV.Image_Processing.IP_One_Image;
   package K renames AMV.Kernels;
   package KO renames AMV.Kernels.IP_One_Image;
   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;
   package KT renames AMV.Kernels.Transforms;
   package RH renames AMV.Shapes.Region_Holders;

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;
   use type K.Int32;
   use type KI.Ks_Image_8_Grey;
   use type KT.Ks_Transform_2D_Linear;
   use type IO.Ks_IP_One_Image_Operator_Kind;
   use type IO.Ks_IP_One_Image_Flip_Rotate_Operation_Constants;
   use type IO.Ks_IP_One_Image_Add_Subtract_Constant_Overflow_Mode_Constants;

   subtype Matrix is AMV.Images.Grey_8_Matrix;

   type Integer_Array is array (Positive range <>) of Integer;
   type Real_Array is array (Positive range <>) of Real;
   type Int_Pair is array (1 .. 2) of Natural;
   type Int_Pairs is array (Positive range <>) of Int_Pair;

   Zero : constant Real := Real'Value ("0.0");
   --  Read at run time, so that Zero / Zero is not folded.

   No_Pixels_Name : constant String := "AMV.KS_IMAGE_NO_PIXELS_EXCEPTION";
   Bad_Name       : constant String := "AMV.KS_BAD_PARAMETER_EXCEPTION";
   Space_Name     : constant String :=
     "AMV.KS_IMAGE_BAD_SELECTED_SPACE_NAME_EXCEPTION";

   function Message_Of (Status : K.Ks_Status) return String is
     (String (Status.Message (1 .. Natural (Status.Length))));

   ---------------------------------------------------------------------
   --  Images, regions and operator lists
   ---------------------------------------------------------------------

   function Random_Image
     (Width, Height : Positive;
      Seed          : Interfaces.Unsigned_32) return Ks_Image_8_Grey;
   --  Pixels from a linear congruential generator.

   function Random_Image
     (Width, Height : Positive;
      Seed          : Interfaces.Unsigned_32) return Ks_Image_8_Grey
   is
      State  : Interfaces.Unsigned_32 := Seed;
      Result : Ks_Image_8_Grey := Create (Width, Height);
   begin
      for Y in 0 .. Height - 1 loop
         for X in 0 .. Width - 1 loop
            State := State * 1_664_525 + 1_013_904_223;
            Result.Set_Pixel
              (X, Y, Grey_8 (Interfaces.Shift_Right (State, 24)));
         end loop;
      end loop;
      return Result;
   end Random_Image;

   function Random_Real
     (State : in out Interfaces.Unsigned_32;
      Low, High : Real) return Real;
   --  A value in [Low, High] from the same generator.

   function Random_Real
     (State : in out Interfaces.Unsigned_32;
      Low, High : Real) return Real is
   begin
      State := State * 1_664_525 + 1_013_904_223;
      return Low + (High - Low) * Real (Interfaces.Shift_Right (State, 8))
                   / Real (2**24 - 1);
   end Random_Real;

   function Rectangle (X, Y, Width, Height : Real) return RH.Holder;

   function Rectangle (X, Y, Width, Height : Real) return RH.Holder is
      R : Ks_Rectangle;
   begin
      R.Set_XY_Width_Height (X, Y, Width, Height);
      return RH.To_Holder (R);
   end Rectangle;

   function Circle (X, Y, Radius : Real) return RH.Holder;

   function Circle (X, Y, Radius : Real) return RH.Holder is
      C : Ks_Circle;
   begin
      C.Set_Center_Radius (X, Y, Radius);
      return RH.To_Holder (C);
   end Circle;

   function List (Op : IO.Ks_IP_One_Image_Operator)
      return IO.Ks_IP_One_Image_Operators;
   --  A list of one operator.

   function List (Op : IO.Ks_IP_One_Image_Operator)
      return IO.Ks_IP_One_Image_Operators
   is
      Result : IO.Ks_IP_One_Image_Operators;
   begin
      IO.Add (Result, Op);
      return Result;
   end List;

   function Run
     (Image     : Ks_Image_8_Grey;
      Operators : IO.Ks_IP_One_Image_Operators;
      What      : String;
      Region    : RH.Holder := RH.Empty_Holder;
      Mode      : K.Int32 := IO.Pixel_Aligned_Bounding_Box) return Matrix;
   --  Runs the tool, checks Accept_Result and returns the output pixels.

   function Run
     (Image     : Ks_Image_8_Grey;
      Operators : IO.Ks_IP_One_Image_Operators;
      What      : String;
      Region    : RH.Holder := RH.Empty_Holder;
      Mode      : K.Int32 := IO.Pixel_Aligned_Bounding_Box) return Matrix
   is
      Tool : IO.Ks_IP_One_Image_Tool;
   begin
      Tool.Input_Image := Image;
      Tool.Region := Region;
      Tool.Region_Mode := Mode;
      Tool.Operators := Operators;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result,
             What & ": Accept_Result (" & Tool.Run_Status.Message & ")");
      if not Tool.Output_Image.Allocated then
         return [1 .. 0 => [1 .. 0 => 0]];
      end if;
      return Tool.Output_Image.To_Matrix;
   end Run;

   ---------------------------------------------------------------------
   --  References
   ---------------------------------------------------------------------

   function Fold (I, N : Integer) return Natural is
     (if I in 0 .. N - 1 then I
      else (declare
               M : constant Natural := I mod (2 * N);
            begin
               (if M < N then M else 2 * N - 1 - M)));
   --  Reflection about the ends of a line of N pixels.

   function At_Reflected (P : Matrix; X, Y : Integer) return Natural is
     (Natural (P (Fold (Y, P'Length (1)), Fold (X, P'Length (2)))));

   function Ref_Extreme
     (P       : Matrix;
      KW, KH  : Positive;
      Maximum : Boolean) return Matrix;

   function Ref_Extreme
     (P       : Matrix;
      KW, KH  : Positive;
      Maximum : Boolean) return Matrix
   is
      Result : Matrix (P'Range (1), P'Range (2));
   begin
      for Y in P'Range (1) loop
         for X in P'Range (2) loop
            declare
               E : Natural := (if Maximum then 0 else 255);
            begin
               for DY in -(KH / 2) .. KH / 2 loop
                  for DX in -(KW / 2) .. KW / 2 loop
                     E := (if Maximum
                           then Natural'Max (E, At_Reflected (P, X + DX,
                                                               Y + DY))
                           else Natural'Min (E, At_Reflected (P, X + DX,
                                                               Y + DY)));
                  end loop;
               end loop;
               Result (Y, X) := Grey_8 (E);
            end;
         end loop;
      end loop;
      return Result;
   end Ref_Extreme;

   function Ref_Difference (A, B : Matrix) return Matrix is
     ([for Y in A'Range (1) =>
         [for X in A'Range (2) =>
            (if A (Y, X) >= B (Y, X) then A (Y, X) - B (Y, X) else 0)]]);

   function Ref_Morphology
     (P         : Matrix;
      Operation : IO.Ks_IP_One_Image_Morphology_Operation_Constants;
      KW, KH    : Positive) return Matrix
   is
     (case Operation is
         when IO.Erode => Ref_Extreme (P, KW, KH, False),
         when IO.Dilate => Ref_Extreme (P, KW, KH, True),
         when IO.Open =>
           Ref_Extreme (Ref_Extreme (P, KW, KH, False), KW, KH, True),
         when IO.Close =>
           Ref_Extreme (Ref_Extreme (P, KW, KH, True), KW, KH, False),
         when IO.Dilate_Minus_Erode =>
           Ref_Difference (Ref_Extreme (P, KW, KH, True),
                           Ref_Extreme (P, KW, KH, False)),
         when IO.Close_Minus_Original =>
           Ref_Difference
             (Ref_Extreme (Ref_Extreme (P, KW, KH, True), KW, KH, False), P),
         when IO.Original_Minus_Open =>
           Ref_Difference
             (P, Ref_Extreme (Ref_Extreme (P, KW, KH, False), KW, KH,
                              True)));

   function Ref_Median (P : Matrix; KW, KH : Positive) return Matrix;
   --  The middle value of the sorted window.

   function Ref_Median (P : Matrix; KW, KH : Positive) return Matrix is
      Result : Matrix (P'Range (1), P'Range (2));
      Values : array (1 .. KW * KH) of Natural;
   begin
      for Y in P'Range (1) loop
         for X in P'Range (2) loop
            declare
               N : Natural := 0;
            begin
               for DY in -(KH / 2) .. KH / 2 loop
                  for DX in -(KW / 2) .. KW / 2 loop
                     N := N + 1;
                     Values (N) := At_Reflected (P, X + DX, Y + DY);
                  end loop;
               end loop;
               --  Insertion sort.
               for I in 2 .. N loop
                  declare
                     V : constant Natural := Values (I);
                     J : Natural := I - 1;
                  begin
                     while J >= 1 and then Values (J) > V loop
                        Values (J + 1) := Values (J);
                        J := J - 1;
                     end loop;
                     Values (J + 1) := V;
                  end;
               end loop;
               Result (Y, X) := Grey_8 (Values ((N + 1) / 2));
            end;
         end loop;
      end loop;
      return Result;
   end Ref_Median;

   type Big is range -2**62 .. 2**62;

   type Big_Array is array (Natural range <>) of Big;

   function Binomial_Row (N : Natural) return Big_Array;
   --  C (N, K) for K in 0 .. N (Pascal's triangle).

   function Binomial_Row (N : Natural) return Big_Array is
      R : Big_Array (0 .. N) := [0 => 1, others => 0];
   begin
      for M in 1 .. N loop
         for K in reverse 1 .. M loop
            R (K) := R (K) + R (K - 1);
         end loop;
      end loop;
      return R;
   end Binomial_Row;

   function Ref_Binomial (P : Matrix; SX, SY : Natural) return Matrix;
   --  The binomial weights of order 2 SX along x (rounded half up), then
   --  of order 2 SY along y.

   function Ref_Binomial (P : Matrix; SX, SY : Natural) return Matrix is
      Rows   : Matrix (P'Range (1), P'Range (2));
      Result : Matrix (P'Range (1), P'Range (2));
      CX     : constant Big_Array := Binomial_Row (2 * SX);
      CY     : constant Big_Array := Binomial_Row (2 * SY);
   begin
      for Y in P'Range (1) loop
         for X in P'Range (2) loop
            declare
               Sum : Big := 0;
            begin
               for I in CX'Range loop
                  Sum := Sum + CX (I) * Big (At_Reflected (P, X + I - SX, Y));
               end loop;
               Rows (Y, X) := Grey_8 ((Sum + 4**SX / 2) / 4**SX);
            end;
         end loop;
      end loop;
      for Y in P'Range (1) loop
         for X in P'Range (2) loop
            declare
               Sum : Big := 0;
            begin
               for I in CY'Range loop
                  Sum := Sum
                    + CY (I) * Big (At_Reflected (Rows, X, Y + I - SY));
               end loop;
               Result (Y, X) := Grey_8 ((Sum + 4**SY / 2) / 4**SY);
            end;
         end loop;
      end loop;
      return Result;
   end Ref_Binomial;

   function Shifted (V : Grey_8; Shift : Integer) return Grey_8 is
     (if Shift >= 0
      then Grey_8 (Natural'Min (255, Natural (V) * 2**Shift))
      else Grey_8 (Natural (V) / 2**(-Shift)));

   function Ref_Box (P : Matrix; KW, KH : Positive) return Matrix;
   --  The mean along x (rounded half up), then along y.

   function Ref_Box (P : Matrix; KW, KH : Positive) return Matrix is
      Rows   : Matrix (P'Range (1), P'Range (2));
      Result : Matrix (P'Range (1), P'Range (2));
   begin
      for Y in P'Range (1) loop
         for X in P'Range (2) loop
            declare
               Sum : Natural := 0;
            begin
               for DX in -(KW / 2) .. KW / 2 loop
                  Sum := Sum + At_Reflected (P, X + DX, Y);
               end loop;
               Rows (Y, X) := Grey_8 ((2 * Sum + KW) / (2 * KW));
            end;
         end loop;
      end loop;
      for Y in P'Range (1) loop
         for X in P'Range (2) loop
            declare
               Sum : Natural := 0;
            begin
               for DY in -(KH / 2) .. KH / 2 loop
                  Sum := Sum + At_Reflected (Rows, X, Y + DY);
               end loop;
               Result (Y, X) := Grey_8 ((2 * Sum + KH) / (2 * KH));
            end;
         end loop;
      end loop;
      return Result;
   end Ref_Box;

   function To_Grey (V : Real) return Grey_8 is
     (if not (V > 0.0) then 0
      elsif V >= 255.0 then 255
      else Grey_8 (Integer (V)));

   function Ref_Convolve
     (P                : Matrix;
      Kernel           : KO.Convolve_NxM_Kernel;
      KW, KH, OX, OY   : Natural) return Matrix;
   --  The sum over the cells, row by row (the kernel's order), rounded and
   --  limited.

   function Ref_Convolve
     (P                : Matrix;
      Kernel           : KO.Convolve_NxM_Kernel;
      KW, KH, OX, OY   : Natural) return Matrix
   is
      Result : Matrix (P'Range (1), P'Range (2));
   begin
      for Y in P'Range (1) loop
         for X in P'Range (2) loop
            declare
               Sum : Real := 0.0;
            begin
               for Row in 0 .. KH - 1 loop
                  for Col in 0 .. KW - 1 loop
                     Sum := Sum
                       + Kernel (Row * 15 + Col)
                         * Real (At_Reflected (P, X + Col - OX,
                                               Y + Row - OY));
                  end loop;
               end loop;
               Result (Y, X) := To_Grey (Sum);
            end;
         end loop;
      end loop;
      return Result;
   end Ref_Convolve;

   type Selection is array (Natural range <>, Natural range <>) of Boolean;

   function Whole (P : Matrix) return Selection is
     ([for Y in P'Range (1) => [for X in P'Range (2) => True]]);

   function Selected
     (Image : Ks_Image_8_Grey; Region : RH.Holder) return Selection;
   --  The pixels the rasterised region contains.

   function Selected
     (Image : Ks_Image_8_Grey; Region : RH.Holder) return Selection
   is
      R      : constant AMV.Regions.Pixel_Region :=
        AMV.Regions.Rasterize (Image, Region);
      Result : Selection (0 .. Image.Height - 1, 0 .. Image.Width - 1);
   begin
      for Y in Result'Range (1) loop
         for X in Result'Range (2) loop
            Result (Y, X) := R.Contains (X, Y);
         end loop;
      end loop;
      return Result;
   end Selected;

   function Ref_Equalize (P : Matrix; S : Selection) return Matrix;
   --  The equalisation table of the selected pixels, applied to them.

   function Ref_Equalize (P : Matrix; S : Selection) return Matrix is
      Hist   : array (0 .. 255) of Natural := [others => 0];
      Total  : Natural := 0;
      Lowest : Natural := 0;
      Map    : array (0 .. 255) of Natural;
      Cdf    : Natural := 0;
      Result : Matrix := P;
   begin
      for Y in P'Range (1) loop
         for X in P'Range (2) loop
            if S (Y, X) then
               Hist (Natural (P (Y, X))) := Hist (Natural (P (Y, X))) + 1;
               Total := Total + 1;
            end if;
         end loop;
      end loop;
      for V in Hist'Range loop
         if Hist (V) > 0 then
            Lowest := Hist (V);
            exit;
         end if;
      end loop;
      if Total <= Lowest then
         return P;
      end if;
      for V in Hist'Range loop
         Cdf := Cdf + Hist (V);
         Map (V) :=
           Natural'Max (0, Natural'Min (255, ((Cdf - Lowest) * 510
                                              + (Total - Lowest))
                                             / (2 * (Total - Lowest))));
      end loop;
      for Y in P'Range (1) loop
         for X in P'Range (2) loop
            if S (Y, X) then
               Result (Y, X) := Grey_8 (Map (Natural (P (Y, X))));
            end if;
         end loop;
      end loop;
      return Result;
   end Ref_Equalize;

   function Ref_Flip (P : Matrix; Code : Natural) return Matrix;
   --  The table of AMV.Kernels.IP_One_Image (output pixel (X, Y) from
   --  input pixel (SX, SY)).

   function Ref_Flip (P : Matrix; Code : Natural) return Matrix is
      W    : constant Natural := P'Length (2);
      H    : constant Natural := P'Length (1);
      Swap : constant Boolean := Code in 1 | 3 | 5 | 7;
      OW   : constant Natural := (if Swap then H else W);
      OH   : constant Natural := (if Swap then W else H);
      Result : Matrix (0 .. OH - 1, 0 .. OW - 1);
   begin
      for Y in Result'Range (1) loop
         for X in Result'Range (2) loop
            declare
               SX : constant Natural :=
                 (case Code is
                     when 0 | 6 => X,
                     when 2 | 4 => W - 1 - X,
                     when 1 | 7 => Y,
                     when others => W - 1 - Y);
               SY : constant Natural :=
                 (case Code is
                     when 0 | 4 => Y,
                     when 2 | 6 => H - 1 - Y,
                     when 3 | 7 => X,
                     when others => H - 1 - X);
            begin
               Result (Y, X) := P (SY, SX);
            end;
         end loop;
      end loop;
      return Result;
   end Ref_Flip;

   function Merge (Computed, P : Matrix; S : Selection) return Matrix is
     ([for Y in P'Range (1) =>
         [for X in P'Range (2) =>
            (if S (Y, X) then Computed (Y, X) else P (Y, X))]]);
   --  The computed pixels inside the selection, the input elsewhere.

   type Box is record
      X0, Y0 : Natural := 0;
      W, H   : Natural := 0;
   end record;

   function Box_Of (S : Selection) return Box;
   --  The smallest rectangle holding every selected pixel.

   function Box_Of (S : Selection) return Box is
      X_Min : Natural := S'Last (2);
      X_Max : Natural := 0;
      Y_Min : Natural := S'Last (1);
      Y_Max : Natural := 0;
   begin
      for Y in S'Range (1) loop
         for X in S'Range (2) loop
            if S (Y, X) then
               X_Min := Natural'Min (X_Min, X);
               X_Max := Natural'Max (X_Max, X);
               Y_Min := Natural'Min (Y_Min, Y);
               Y_Max := Natural'Max (Y_Max, Y);
            end if;
         end loop;
      end loop;
      return (X_Min, Y_Min, X_Max - X_Min + 1, Y_Max - Y_Min + 1);
   end Box_Of;

   function Crop (P : Matrix; B : Box) return Matrix is
     ([for Y in 0 .. B.H - 1 =>
         [for X in 0 .. B.W - 1 => P (B.Y0 + Y, B.X0 + X)]]);
   --  The pixels of the box, from (0, 0).

   function Crop (S : Selection; B : Box) return Selection is
     ([for Y in 0 .. B.H - 1 =>
         [for X in 0 .. B.W - 1 => S (B.Y0 + Y, B.X0 + X)]]);

   ---------------------------------------------------------------------
   --  Pointwise operators
   ---------------------------------------------------------------------

   procedure Test_Pointwise is
      Image : constant Ks_Image_8_Grey := Random_Image (23, 17, 11);
      P     : constant Matrix := Image.To_Matrix;
      Op    : IO.Ks_IP_One_Image_Operator;
   begin
      Section ("IP one image: AddSubtractConstant");
      for Mode in IO.Ks_IP_One_Image_Add_Subtract_Constant_Overflow_Mode_Constants
      loop
         for C of Integer_Array'[40, -300, 200, -1, 0, 1_000_000] loop
            Op := IO.New_Operator (IO.Add_Subtract_Constant);
            Op.Add_Subtract_Constant.Constant_Value := K.Int32 (C);
            Op.Add_Subtract_Constant.Overflow_Mode := IO.Code (Mode);
            declare
               Expected : constant Matrix :=
                 [for Y in P'Range (1) =>
                    [for X in P'Range (2) =>
                       (if Mode = IO.Wrap
                        then Grey_8 ((Integer (P (Y, X)) + C) mod 256)
                        else Grey_8 (Integer'Max
                                       (0, Integer'Min
                                             (255, Integer (P (Y, X)) + C))))]];
            begin
               Check (Run (Image, List (Op), "add") = Expected,
                      "add" & Integer'Image (C) & " " & Mode'Image);
            end;
         end loop;
      end loop;

      Section ("IP one image: MultiplyConstant");
      for Mode in IO.Ks_IP_One_Image_Multiply_Constant_Overflow_Mode_Constants
      loop
         for C of Real_Array'[1.7, 0.5, 3.3, 0.0, 1.0, 1.0E6] loop
            Op := IO.New_Operator (IO.Multiply_Constant);
            Op.Multiply_Constant.Constant_Value := C;
            Op.Multiply_Constant.Overflow_Mode := IO.Code (Mode);
            declare
               Expected : constant Matrix :=
                 [for Y in P'Range (1) =>
                    [for X in P'Range (2) =>
                       (declare
                           R : constant Long_Long_Integer :=
                             Long_Long_Integer (Real (P (Y, X)) * C);
                        begin
                           (if Mode = IO.Wrap then Grey_8 (R mod 256)
                            else Grey_8 (Long_Long_Integer'Min (R, 255))))]];
            begin
               Check (Run (Image, List (Op), "multiply") = Expected,
                      "multiply" & C'Image & " " & Mode'Image);
            end;
         end loop;
      end loop;

      Section ("IP one image: Quantize");
      for Level in IO.Ks_IP_One_Image_Quantize_Level_Constants loop
         Op := IO.New_Operator (IO.Quantize);
         Op.Quantize.Levels := IO.Code (Level);
         declare
            Step     : constant Natural :=
              2**(7 - IO.Ks_IP_One_Image_Quantize_Level_Constants'Pos
                        (Level));
            Expected : constant Matrix :=
              [for Y in P'Range (1) =>
                 [for X in P'Range (2) =>
                    Grey_8 (Natural (P (Y, X)) / Step * Step)]];
            Out_P    : constant Matrix := Run (Image, List (Op), "quantize");
            Levels   : array (0 .. 255) of Boolean := [others => False];
            Count    : Natural := 0;
         begin
            Check (Out_P = Expected, "quantize " & Level'Image);
            for V of Out_P loop
               Levels (Natural (V)) := True;
            end loop;
            for B of Levels loop
               Count := Count + Boolean'Pos (B);
            end loop;
            Check (Count <= 256 / Step,
                   "quantize " & Level'Image & ": at most"
                   & Natural'Image (256 / Step) & " grey levels");
         end;
      end loop;

      Section ("IP one image: Threshold");
      for T of Integer_Array'[100, 0, 256, 255, 1] loop
         Op := IO.New_Operator (IO.Threshold);
         Op.Threshold.Threshold := K.Int32 (T);
         Op.Threshold.Low_Value := 10;
         Op.Threshold.High_Value := 200;
         declare
            Out_P : constant Matrix := Run (Image, List (Op), "threshold");
            Good  : Boolean := Out_P'Length (1) = P'Length (1);
         begin
            if Good then
               for Y in P'Range (1) loop
                  for X in P'Range (2) loop
                     Good := Good
                       and then Out_P (Y, X)
                                  = (if Natural (P (Y, X)) >= T then 200
                                     else 10);
                  end loop;
               end loop;
            end if;
            Check (Good, "threshold" & Integer'Image (T)
                         & ": exactly HighValue or LowValue by the rule");
         end;
      end loop;

      Section ("IP one image: PixelMap");
      Op := IO.New_Operator (IO.Pixel_Map);
      for V in Op.Pixel_Map.Map'Range loop
         Op.Pixel_Map.Map (V) := 255 - V;
      end loop;
      Check (Run (Image, List (Op), "pixel map")
               = [for Y in P'Range (1) =>
                    [for X in P'Range (2) => 255 - P (Y, X)]],
             "an inverting map");

      Section ("IP one image: Equalize");
      Op := IO.New_Operator (IO.Equalize);
      declare
         Out_P : constant Matrix := Run (Image, List (Op), "equalize");
         Low   : Grey_8 := 255;
         High  : Grey_8 := 0;
      begin
         Check (Out_P = Ref_Equalize (P, Whole (P)),
                "equalize: the reference table");
         for V of Out_P loop
            Low := Grey_8'Min (Low, V);
            High := Grey_8'Max (High, V);
         end loop;
         Check (Low = 0 and then High = 255,
                "equalize: the levels span 0 .. 255");
      end;
      declare
         Flat : constant Ks_Image_8_Grey := Create (9, 4, 77);
      begin
         Check (Run (Flat, List (Op), "equalize flat") = Flat.To_Matrix,
                "equalize: a single grey level is left unchanged");
      end;
   end Test_Pointwise;

   ---------------------------------------------------------------------
   --  Neighbourhood operators
   ---------------------------------------------------------------------

   type Size_Pair is record
      W, H : Positive;
   end record;

   Kernel_Sizes : constant array (Positive range <>) of Size_Pair :=
     [(3, 3), (5, 1), (1, 7), (7, 5), (1, 1), (31, 3), (3, 41)];

   type Image_Array is array (Positive range <>) of Ks_Image_8_Grey;

   procedure Test_Morphology is
      Images : constant Image_Array :=
        [Random_Image (23, 17, 21), Random_Image (1, 9, 22),
         Random_Image (9, 1, 23), Random_Image (2, 2, 24)];
      Op     : IO.Ks_IP_One_Image_Operator;
   begin
      Section ("IP one image: GreyMorphologyNxM against brute force");
      for Image of Images loop
         declare
            P : constant Matrix := Image.To_Matrix;
         begin
            for S of Kernel_Sizes loop
               for Operation in
                 IO.Ks_IP_One_Image_Morphology_Operation_Constants
               loop
                  Op := IO.New_Operator (IO.Grey_Morphology_NxM);
                  Op.Grey_Morphology_NxM.Operation := IO.Code (Operation);
                  Op.Grey_Morphology_NxM.Kernel_Width := K.Int32 (S.W);
                  Op.Grey_Morphology_NxM.Kernel_Height := K.Int32 (S.H);
                  Check (Run (Image, List (Op), "morphology")
                           = Ref_Morphology (P, Operation, S.W, S.H),
                         "morphology " & Operation'Image & S.W'Image & " x"
                         & S.H'Image & " on" & Image.Width'Image & " x"
                         & Image.Height'Image);
               end loop;
            end loop;
         end;
      end loop;

      Section ("IP one image: morphology identities");
      declare
         Image : constant Ks_Image_8_Grey := Random_Image (40, 30, 25);
         P     : constant Matrix := Image.To_Matrix;

         function With_Op
           (Operation : IO.Ks_IP_One_Image_Morphology_Operation_Constants;
            On        : Ks_Image_8_Grey) return Matrix
         is
            O : IO.Ks_IP_One_Image_Operator :=
              IO.New_Operator (IO.Grey_Morphology_NxM);
         begin
            O.Grey_Morphology_NxM.Operation := IO.Code (Operation);
            O.Grey_Morphology_NxM.Kernel_Width := 5;
            O.Grey_Morphology_NxM.Kernel_Height := 3;
            return Run (On, List (O), "identity");
         end With_Op;

         E      : constant Matrix := With_Op (IO.Erode, Image);
         D      : constant Matrix := With_Op (IO.Dilate, Image);
         O      : constant Matrix := With_Op (IO.Open, Image);
         C      : constant Matrix := With_Op (IO.Close, Image);
         Order  : Boolean := True;
         Opened : Boolean := True;
      begin
         for Y in P'Range (1) loop
            for X in P'Range (2) loop
               Order := Order and then E (Y, X) <= P (Y, X)
                        and then P (Y, X) <= D (Y, X);
               Opened := Opened and then O (Y, X) <= P (Y, X)
                         and then P (Y, X) <= C (Y, X);
            end loop;
         end loop;
         Check (Order, "erode <= original <= dilate");
         Check (Opened, "open <= original <= close");
         Check (With_Op (IO.Open, From_Matrix (O)) = O,
                "open is idempotent");
         Check (With_Op (IO.Close, From_Matrix (C)) = C,
                "close is idempotent");
         Check (With_Op (IO.Dilate_Minus_Erode, Image)
                  = Ref_Difference (D, E),
                "DilateMinusErode = Dilate - Erode");
      end;
   end Test_Morphology;

   procedure Test_Median is
      Images : constant Image_Array :=
        [Random_Image (23, 17, 31), Random_Image (1, 9, 32),
         Random_Image (9, 1, 33), Random_Image (2, 3, 34)];
      Op     : IO.Ks_IP_One_Image_Operator;
   begin
      Section ("IP one image: MedianNxM and Median3x3 against sorting");
      for Image of Images loop
         declare
            P : constant Matrix := Image.To_Matrix;
         begin
            for S of Kernel_Sizes loop
               Op := IO.New_Operator (IO.Median_NxM);
               Op.Median_NxM.Kernel_Width := K.Int32 (S.W);
               Op.Median_NxM.Kernel_Height := K.Int32 (S.H);
               Check (Run (Image, List (Op), "median")
                        = Ref_Median (P, S.W, S.H),
                      "median" & S.W'Image & " x" & S.H'Image & " on"
                      & Image.Width'Image & " x" & Image.Height'Image);
            end loop;
            Check (Run (Image, List (IO.New_Operator (IO.Median_3x3)),
                        "median 3x3") = Ref_Median (P, 3, 3),
                   "Median3x3 on" & Image.Width'Image & " x"
                   & Image.Height'Image);
         end;
      end loop;
   end Test_Median;

   procedure Test_Smoothing is
      Images : constant Image_Array :=
        [Random_Image (23, 17, 41), Random_Image (1, 9, 42),
         Random_Image (9, 1, 43)];
      Op     : IO.Ks_IP_One_Image_Operator;
   begin
      Section ("IP one image: GaussSampler against the binomial sums");
      for Image of Images loop
         declare
            P : constant Matrix := Image.To_Matrix;
         begin
            for S of Int_Pairs'[[0, 0], [2, 2], [1, 3], [24, 0], [5, 24]] loop
               Op := IO.New_Operator (IO.Gauss_Sampler);
               Op.Gauss_Sampler.Smoothness_X := K.Int32 (S (1));
               Op.Gauss_Sampler.Smoothness_Y := K.Int32 (S (2));
               Check (Run (Image, List (Op), "gauss")
                        = Ref_Binomial (P, S (1), S (2)),
                      "gauss" & S (1)'Image & "," & S (2)'Image & " on"
                      & Image.Width'Image & " x" & Image.Height'Image);
            end loop;
            for Shift of Integer_Array'[3, -2, 7, -7] loop
               Op := IO.New_Operator (IO.Gauss_Sampler);
               Op.Gauss_Sampler.Magnitude_Shift := K.Int32 (Shift);
               declare
                  G : constant Matrix := Ref_Binomial (P, 2, 2);
               begin
                  Check (Run (Image, List (Op), "gauss shift")
                           = [for Y in G'Range (1) =>
                                [for X in G'Range (2) =>
                                   Shifted (G (Y, X), Shift)]],
                         "gauss: MagnitudeShift" & Shift'Image);
               end;
            end loop;
         end;
      end loop;
      Check (Run (Images (1), List (IO.New_Operator (IO.Gauss_Sampler)),
                  "gauss default") /= Images (1).To_Matrix,
             "gauss: the default smooths");

      Section ("IP one image: BoxFilter against the means");
      for Image of Images loop
         declare
            P : constant Matrix := Image.To_Matrix;
         begin
            for S of Kernel_Sizes loop
               Op := IO.New_Operator (IO.Box_Filter);
               Op.Box_Filter.Kernel_Width := K.Int32 (S.W);
               Op.Box_Filter.Kernel_Height := K.Int32 (S.H);
               Check (Run (Image, List (Op), "box") = Ref_Box (P, S.W, S.H),
                      "box" & S.W'Image & " x" & S.H'Image & " on"
                      & Image.Width'Image & " x" & Image.Height'Image);
            end loop;
         end;
      end loop;

      Section ("IP one image: UnsharpMask");
      for Image of Images loop
         declare
            P : constant Matrix := Image.To_Matrix;
         begin
            for A of Real_Array'[1.5, 0.0, 0.3, 1000.0] loop
               Op := IO.New_Operator (IO.Unsharp_Mask);
               Op.Unsharp_Mask.Amount := A;
               Op.Unsharp_Mask.Smoothness_X := 1;
               Op.Unsharp_Mask.Smoothness_Y := 2;
               declare
                  G : constant Matrix := Ref_Binomial (P, 1, 2);
               begin
                  Check (Run (Image, List (Op), "unsharp")
                           = [for Y in P'Range (1) =>
                                [for X in P'Range (2) =>
                                   To_Grey (Real (P (Y, X))
                                            + A * Real (Integer (P (Y, X))
                                                        - Integer (G (Y, X))))
                                ]],
                         "unsharp mask, amount" & A'Image & " on"
                         & Image.Width'Image & " x" & Image.Height'Image);
               end;
            end loop;
         end;
      end loop;
   end Test_Smoothing;

   procedure Test_Convolution is
      Images : constant Image_Array :=
        [Random_Image (23, 17, 51), Random_Image (1, 9, 52),
         Random_Image (9, 1, 53), Random_Image (3, 2, 54)];
      State  : Interfaces.Unsigned_32 := 99;
      Op     : IO.Ks_IP_One_Image_Operator;
   begin
      Section ("IP one image: ConvolveNxM against the sums");
      Check (Run (Images (1), List (IO.New_Operator (IO.Convolve_NxM)),
                  "convolve default") = Images (1).To_Matrix,
             "the default kernel copies the image");
      for Image of Images loop
         declare
            P : constant Matrix := Image.To_Matrix;
         begin
            for S of Int_Pairs'[[3, 3], [5, 3], [1, 15], [15, 15], [7, 1]] loop
               Op := IO.New_Operator (IO.Convolve_NxM);
               Op.Convolve_NxM.Kernel_Width := K.Int32 (S (1));
               Op.Convolve_NxM.Kernel_Height := K.Int32 (S (2));
               for Row in 0 .. S (2) - 1 loop
                  for Col in 0 .. S (1) - 1 loop
                     IO.Set_Kernel_Value
                       (Op.Convolve_NxM, Col, Row,
                        Random_Real (State, -0.6, 0.9));
                  end loop;
               end loop;
               Check (Run (Image, List (Op), "convolve")
                        = Ref_Convolve (P, Op.Convolve_NxM.Kernel, S (1),
                                        S (2), S (1) / 2, S (2) / 2),
                      "convolve" & S (1)'Image & " x" & S (2)'Image & " on"
                      & Image.Width'Image & " x" & Image.Height'Image);
            end loop;
         end;
      end loop;

      Section ("IP one image: Convolve3x3 with every origin");
      for Image of Images loop
         declare
            P : constant Matrix := Image.To_Matrix;
         begin
            for Origin in IO.Ks_IP_One_Image_Convolve_3x3_Position_Constants
            loop
               Op := IO.New_Operator (IO.Convolve_3x3);
               Op.Convolve_3x3.Kernel_Origin := IO.Code (Origin);
               declare
                  K3 : IO.Convolve_3x3_Kernel;
                  KN : KO.Convolve_NxM_Kernel := [others => 0.0];
               begin
                  for I in K3'Range loop
                     K3 (I) := Random_Real (State, -40.0, 60.0);
                     KN ((I / 3) * 15 + I mod 3) := K3 (I);
                  end loop;
                  IO.Set_Kernel (Op.Convolve_3x3, K3);
                  Check (Run (Image, List (Op), "convolve 3x3")
                           = Ref_Convolve
                               (P, KN, 3, 3,
                                Natural (IO.Code (Origin)) mod 3,
                                Natural (IO.Code (Origin)) / 3),
                         "convolve 3x3, origin " & Origin'Image & " on"
                         & Image.Width'Image & " x" & Image.Height'Image);
               end;
            end loop;
         end;
      end loop;
   end Test_Convolution;

   ---------------------------------------------------------------------
   --  Flips and rotations, coordinate spaces
   ---------------------------------------------------------------------

   procedure Test_Flip_Rotate is
      Image : Ks_Image_8_Grey := Random_Image (7, 5, 61);
      P     : constant Matrix := Image.To_Matrix;
      Tool  : IO.Ks_IP_One_Image_Tool;
      Op    : IO.Ks_IP_One_Image_Operator :=
        IO.New_Operator (IO.Flip_Rotate);
   begin
      Section ("IP one image: FlipRotate pixels and sizes");
      for Code in IO.Ks_IP_One_Image_Flip_Rotate_Operation_Constants loop
         Op.Flip_Rotate.Operation_In_Pixel_Space := IO.Code (Code);
         declare
            Out_P : constant Matrix := Run (Image, List (Op), "flip");
            Swap  : constant Boolean :=
              Code in IO.Rotate_90_Deg | IO.Rotate_270_Deg
                    | IO.Flip_And_Rotate_90_Deg
                    | IO.Flip_And_Rotate_270_Deg;
         begin
            Check (Out_P'Length (2) = (if Swap then 5 else 7)
                   and then Out_P'Length (1) = (if Swap then 7 else 5),
                   Code'Image & ": the output size");
            Check (Out_P = Ref_Flip (P, IO.Ks_IP_One_Image_Flip_Rotate_Operation_Constants'Pos (Code)),
                   Code'Image & ": every pixel where the table puts it");
         end;
      end loop;
      Op.Flip_Rotate.Operation_In_Pixel_Space := IO.Code (IO.Rotate_90_Deg);
      Check (Run (Image, List (Op), "rot90") (0, 4) = P (0, 0),
             "Rotate90Deg turns clockwise: the top left goes to the top"
             & " right");
      declare
         Pair : IO.Ks_IP_One_Image_Operators := List (Op);
         F    : IO.Ks_IP_One_Image_Operator :=
           IO.New_Operator (IO.Flip_Rotate);
      begin
         F.Flip_Rotate.Operation_In_Pixel_Space := IO.Code (IO.Flip);
         IO.Add (Pair, F);
         F.Flip_Rotate.Operation_In_Pixel_Space :=
           IO.Code (IO.Flip_And_Rotate_270_Deg);
         Check (Run (Image, Pair, "rot90 then flip")
                  = Run (Image, List (F), "transpose"),
                "Rotate90Deg then Flip is FlipAndRotate270Deg (a"
                & " transpose)");
         IO.Add (Pair, F);
         Check (Run (Image, Pair, "back") = P,
                "... and a second transpose restores the image");
      end;

      Section ("IP one image: FlipRotate keeps the meaning of root"
               & " coordinates");
      Image.Coordinate_Space_Tree.Add_Space
        ("@", "Fixture", AMV.Transforms.Create_Rigid (0.3, 12.0, 7.0));
      Image.Set_Selected_Space_Name ("@\Fixture");
      Image.Set_Pixel_From_Root_Transform
        (AMV.Transforms.Create_Similarity (0.5, 0.2, 3.0, -4.0));
      Tool.Input_Image := Image;
      for Code in IO.Ks_IP_One_Image_Flip_Rotate_Operation_Constants loop
         Op.Flip_Rotate.Operation_In_Pixel_Space := IO.Code (Code);
         Tool.Operators := List (Op);
         Tool.Run;
         declare
            Output    : constant Ks_Image_8_Grey := Tool.Output_Image;
            In_Root   : constant AMV.Transforms.Ks_Transform_2D_Linear :=
              Image.Get_Transform ("@", "#");
            Out_Pixel : constant AMV.Transforms.Ks_Transform_2D_Linear :=
              Output.Get_Transform ("#", "@");
            Sel_Pixel : constant AMV.Transforms.Ks_Transform_2D_Linear :=
              Output.Get_Transform ("#", ".");
            In_Sel    : constant AMV.Transforms.Ks_Transform_2D_Linear :=
              Image.Get_Transform (".", "#");
            Good      : Boolean := Tool.Run_Status.Result = Accept_Result;
            Worst     : Real := 0.0;
         begin
            Check (Good, Code'Image & ": Accept_Result ("
                         & Tool.Run_Status.Message & ")");
            Check (Output.Selected_Space_Name = "@\Fixture",
                   Code'Image & ": the selected space is kept");
            if Good then
               for Y in 0 .. Image.Height - 1 loop
                  for X in 0 .. Image.Width - 1 loop
                     declare
                        RX, RY, OX, OY, SX, SY, QX, QY : Real;
                     begin
                        In_Root.Map_Point (Real (X), Real (Y), RX, RY);
                        Out_Pixel.Map_Point (RX, RY, OX, OY);
                        In_Sel.Map_Point (Real (X), Real (Y), SX, SY);
                        Sel_Pixel.Map_Point (SX, SY, QX, QY);
                        Worst := Real'Max (Worst, abs (OX - Real'Rounding (OX)));
                        Worst := Real'Max (Worst, abs (OY - Real'Rounding (OY)));
                        Worst := Real'Max (Worst, abs (QX - OX));
                        Worst := Real'Max (Worst, abs (QY - OY));
                        Good := Good
                          and then Output.Get_Pixel
                                     (Natural (Real'Rounding (OX)),
                                      Natural (Real'Rounding (OY)))
                                   = Image.Get_Pixel (X, Y);
                     end;
                  end loop;
               end loop;
            end if;
            Check (Good and then Worst < 1.0E-9,
                   Code'Image & ": a point in ""@"" and in ""."" shows the"
                   & " same content in both images");
         end;
      end loop;
   end Test_Flip_Rotate;

   ---------------------------------------------------------------------
   --  SubSampler, Expand, GaussSampler's sampling and HighPassFilter
   ---------------------------------------------------------------------

   function Ref_Sub
     (P       : Matrix;
      SX, SY  : Positive;
      Average : Boolean) return Matrix;
   --  Every SX-th pixel along x and SY-th along y, or the mean (rounded
   --  half up) of each SX x SY block cut at the border.

   function Ref_Sub
     (P       : Matrix;
      SX, SY  : Positive;
      Average : Boolean) return Matrix
   is
      W      : constant Positive := P'Length (2);
      H      : constant Positive := P'Length (1);
      Result : Matrix (0 .. (H + SY - 1) / SY - 1, 0 .. (W + SX - 1) / SX - 1);
   begin
      for Y in Result'Range (1) loop
         for X in Result'Range (2) loop
            if Average then
               declare
                  Sum, Count : Natural := 0;
               begin
                  for J in Y * SY .. Natural'Min (Y * SY + SY - 1, H - 1) loop
                     for I in X * SX .. Natural'Min (X * SX + SX - 1, W - 1)
                     loop
                        Sum := Sum + Natural (P (J, I));
                        Count := Count + 1;
                     end loop;
                  end loop;
                  Result (Y, X) := Grey_8 ((2 * Sum + Count) / (2 * Count));
               end;
            else
               Result (Y, X) := P (Y * SY, X * SX);
            end if;
         end loop;
      end loop;
      return Result;
   end Ref_Sub;

   function Ref_Expand (P : Matrix; EX, EY : Positive) return Matrix;
   --  Each pixel repeated EX times along x and EY times along y.

   function Ref_Expand (P : Matrix; EX, EY : Positive) return Matrix is
      Result : Matrix (0 .. P'Length (1) * EY - 1, 0 .. P'Length (2) * EX - 1);
   begin
      for Y in Result'Range (1) loop
         for X in Result'Range (2) loop
            Result (Y, X) := P (Y / EY, X / EX);
         end loop;
      end loop;
      return Result;
   end Ref_Expand;

   function Ref_High_Pass (P, Low : Matrix) return Matrix is
     ([for Y in P'Range (1) =>
         [for X in P'Range (2) =>
            Grey_8 (Integer'Max (0, Integer'Min
                      (255, Integer (P (Y, X)) - Integer (Low (Y, X))
                            + 128)))]]);
   --  P - Low + 128, limited to 0 .. 255.

   procedure Test_Sampling is
      Images : constant Image_Array :=
        [Random_Image (13, 9, 71), Random_Image (1, 7, 72),
         Random_Image (8, 1, 73)];
      Op     : IO.Ks_IP_One_Image_Operator;
   begin
      Section ("IP one image: SubSampler against the reference");
      for Image of Images loop
         declare
            P : constant Matrix := Image.To_Matrix;
         begin
            for S of Int_Pairs'[[1, 1], [2, 2], [3, 1], [1, 4], [4, 3],
                                [20, 2], [256, 256]]
            loop
               for Average in Boolean loop
                  Op := IO.New_Operator (IO.Sub_Sampler);
                  Op.Sub_Sampler.Sample_X := K.Int32 (S (1));
                  Op.Sub_Sampler.Sample_Y := K.Int32 (S (2));
                  Op.Sub_Sampler.Spatial_Average :=
                    (if Average then K.True_Value else K.False_Value);
                  Check (Run (Image, List (Op), "subsample")
                           = Ref_Sub (P, S (1), S (2), Average),
                         "subsample" & S (1)'Image & " x" & S (2)'Image
                         & ", average " & Average'Image & " on"
                         & Image.Width'Image & " x" & Image.Height'Image);
               end loop;
            end loop;
         end;
      end loop;

      Section ("IP one image: Expand against the reference");
      for Image of Images loop
         declare
            P : constant Matrix := Image.To_Matrix;
         begin
            for S of Int_Pairs'[[1, 1], [2, 2], [3, 1], [1, 4], [5, 3]] loop
               Op := IO.New_Operator (IO.Expand);
               Op.Expand.Expansion_X := K.Int32 (S (1));
               Op.Expand.Expansion_Y := K.Int32 (S (2));
               Check (Run (Image, List (Op), "expand")
                        = Ref_Expand (P, S (1), S (2)),
                      "expand" & S (1)'Image & " x" & S (2)'Image & " on"
                      & Image.Width'Image & " x" & Image.Height'Image);
            end loop;
            declare
               Pair : IO.Ks_IP_One_Image_Operators;
               Sub  : IO.Ks_IP_One_Image_Operator :=
                 IO.New_Operator (IO.Sub_Sampler);
            begin
               Op := IO.New_Operator (IO.Expand);
               Op.Expand.Expansion_X := 3;
               Op.Expand.Expansion_Y := 2;
               Sub.Sub_Sampler.Sample_X := 3;
               Sub.Sub_Sampler.Sample_Y := 2;
               IO.Add (Pair, Op);
               IO.Add (Pair, Sub);
               Check (Run (Image, Pair, "expand, subsample") = P,
                      "an expansion then the same sampling restores the"
                      & " image");
               Sub.Sub_Sampler.Spatial_Average := K.True_Value;
               IO.Set_Item (Pair, 1, Sub);
               Check (Run (Image, Pair, "expand, mean") = P,
                      "... also with the mean");
            end;
         end;
      end loop;

      Section ("IP one image: GaussSampler's SampleX and SampleY");
      for Image of Images loop
         declare
            P : constant Matrix := Image.To_Matrix;
         begin
            Op := IO.New_Operator (IO.Gauss_Sampler);
            Op.Gauss_Sampler.Smoothness_X := 1;
            Op.Gauss_Sampler.Sample_X := 2;
            Op.Gauss_Sampler.Sample_Y := 3;
            Check (Run (Image, List (Op), "gauss sampled")
                     = Ref_Sub (Ref_Binomial (P, 1, 2), 2, 3, False),
                   "gauss 1, 2 sampled 2 x 3 on" & Image.Width'Image & " x"
                   & Image.Height'Image);
            Check (abs (IO.Sigma_X (Op.Gauss_Sampler) ** 2 - 0.5) < 1.0E-15
                   and then IO.Sigma_Y (Op.Gauss_Sampler) = 1.0,
                   "gauss: SigmaX and SigmaY");
         end;
      end loop;

      Section ("IP one image: HighPassFilter against the reference");
      for Image of Images loop
         declare
            P : constant Matrix := Image.To_Matrix;
         begin
            Op := IO.New_Operator (IO.High_Pass_Filter);
            Op.High_Pass_Filter.Smoothness_X := 1;
            Op.High_Pass_Filter.Smoothness_Y := 3;
            Check (Run (Image, List (Op), "high pass gauss")
                     = Ref_High_Pass (P, Ref_Binomial (P, 1, 3)),
                   "high pass, Gauss 1, 3 on" & Image.Width'Image & " x"
                   & Image.Height'Image);
            Op.High_Pass_Filter.Processing_Mode := IO.Code (IO.Mean);
            Op.High_Pass_Filter.Kernel_Width := 5;
            Op.High_Pass_Filter.Kernel_Height := 3;
            Check (Run (Image, List (Op), "high pass mean")
                     = Ref_High_Pass (P, Ref_Box (P, 5, 3)),
                   "high pass, Mean 5 x 3");
            Op.High_Pass_Filter.Processing_Mode := IO.Code (IO.Median);
            Op.High_Pass_Filter.Kernel_Width := 3;
            Op.High_Pass_Filter.Kernel_Height := 7;
            Check (Run (Image, List (Op), "high pass median")
                     = Ref_High_Pass (P, Ref_Median (P, 3, 7)),
                   "high pass, Median 3 x 7");
         end;
      end loop;
      declare
         Flat : Ks_Image_8_Grey := Create (6, 4);
      begin
         for Y in 0 .. 3 loop
            for X in 0 .. 5 loop
               Flat.Set_Pixel (X, Y, 77);
            end loop;
         end loop;
         Check (Run (Flat, List (IO.New_Operator (IO.High_Pass_Filter)),
                     "high pass flat")
                  = [0 .. 3 => [0 .. 5 => 128]],
                "high pass: a flat image becomes 128");
      end;

      Section ("IP one image: sampling and regions");
      declare
         Image  : constant Ks_Image_8_Grey := Images (1);
         P      : constant Matrix := Image.To_Matrix;
         Region : constant RH.Holder := Rectangle (1.5, 1.5, 4.0, 3.0);
         B      : constant Box := Box_Of (Selected (Image, Region));
         C      : constant Matrix := Crop (P, B);
         Tool   : IO.Ks_IP_One_Image_Tool;
      begin
         Check (B.W < 13 and then B.H < 9, "the rectangle's box is smaller");
         Op := IO.New_Operator (IO.Sub_Sampler);
         Op.Sub_Sampler.Sample_X := 1;
         Op.Sub_Sampler.Sample_Y := 1;
         Op.Sub_Sampler.Spatial_Average := K.True_Value;
         Check (Run (Image, List (Op), "subsample 1 x 1", Region) = C,
                "a sampling by 1 x 1 copies the region's box");
         Op := IO.New_Operator (IO.High_Pass_Filter);
         Check (Run (Image, List (Op), "high pass region", Region)
                  = Ref_High_Pass (C, Ref_Binomial (C, 2, 2)),
                "a high pass of the region's box, as of an image of its own");
         Op := IO.New_Operator (IO.Expand);
         Op.Expand.Expansion_X := 2;
         Op.Expand.Expansion_Y := 3;
         Check (Run (Image, List (Op), "expand region", Region)
                  = Ref_Expand (C, 2, 3),
                "an operator that changes the pixel grid works on the box");
         Check (Run (Image, List (Op), "expand region, adjust mask", Region,
                     IO.Pixel_Aligned_Bounding_Box_Adjust_Mask)
                  = Ref_Expand (C, 2, 3),
                "Adjust_Mask: a rectangle fills its box, so an expansion"
                & " may come first");
         Tool.Input_Image := Image;
         Tool.Region := Circle (6.5, 4.5, 3.3);
         Tool.Region_Mode := IO.Pixel_Aligned_Bounding_Box_Adjust_Mask;
         Tool.Operators := List (Op);
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Exception_Name = Bad_Name
                and then Tool.Run_Status.Message
                           = "RegionMode PixelAlignedBoundingBoxAdjustMask"
                             & " needs a Region that fills its bounding box"
                             & " when the first operator changes the pixel"
                             & " grid",
                "Adjust_Mask: an expansion first with a circle ("
                & Tool.Run_Status.Message & ")");
         Tool.Region_Mode := IO.Pixel_Aligned_Bounding_Box;
         Tool.Region := RH.Empty_Holder;
         Op := IO.New_Operator (IO.Expand);
         Op.Expand.Expansion_X := 256;
         Op.Expand.Expansion_Y := 256;
         Tool.Operators := List (Op);
         IO.Add (Tool.Operators, Op);
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Message
                           = "Operators(1) makes an image of more than"
                             & " 2147483647 pixels",
                "an image too large (" & Tool.Run_Status.Message & ")");
      end;

      Section ("IP one image: sampling keeps the meaning of root"
               & " coordinates");
      declare
         Image : Ks_Image_8_Grey := Random_Image (13, 9, 74);
         Tool  : IO.Ks_IP_One_Image_Tool;
         type Case_Kind is (Plain, Mean, Grow, Gauss);
      begin
         Image.Set_Pixel_From_Root_Transform
           (AMV.Transforms.Create_Similarity (0.5, 0.2, 3.0, -4.0));
         Tool.Input_Image := Image;
         for C in Case_Kind loop
            case C is
               when Plain | Mean =>
                  Op := IO.New_Operator (IO.Sub_Sampler);
                  Op.Sub_Sampler.Sample_X := 3;
                  Op.Sub_Sampler.Sample_Y := 2;
                  if C = Mean then
                     Op.Sub_Sampler.Spatial_Average := K.True_Value;
                  end if;
               when Grow =>
                  Op := IO.New_Operator (IO.Expand);
                  Op.Expand.Expansion_X := 3;
                  Op.Expand.Expansion_Y := 2;
               when Gauss =>
                  Op := IO.New_Operator (IO.Gauss_Sampler);
                  Op.Gauss_Sampler.Sample_X := 3;
                  Op.Gauss_Sampler.Sample_Y := 2;
            end case;
            Tool.Operators := List (Op);
            Tool.Run;
            Check (Tool.Run_Status.Result = Accept_Result,
                   C'Image & ": Accept_Result (" & Tool.Run_Status.Message
                   & ")");
            if Tool.Run_Status.Result = Accept_Result then
               declare
                  Output   : constant Ks_Image_8_Grey := Tool.Output_Image;
                  Out_Root : constant AMV.Transforms.Ks_Transform_2D_Linear :=
                    Output.Get_Transform ("@", "#");
                  In_Pixel : constant AMV.Transforms.Ks_Transform_2D_Linear :=
                    Image.Get_Transform ("#", "@");
                  Worst    : Real := 0.0;
               begin
                  for Y in 0 .. Output.Height - 1 loop
                     for X in 0 .. Output.Width - 1 loop
                        declare
                           RX, RY, IX, IY, EX, EY : Real;
                        begin
                           Out_Root.Map_Point (Real (X), Real (Y), RX, RY);
                           In_Pixel.Map_Point (RX, RY, IX, IY);
                           case C is
                              when Plain | Gauss =>
                                 EX := Real (3 * X);
                                 EY := Real (2 * Y);
                              when Mean =>
                                 EX := Real (3 * X) + 1.0;
                                 EY := Real (2 * Y) + 0.5;
                              when Grow =>
                                 EX := (Real (X) - 1.0) / 3.0;
                                 EY := (Real (Y) - 0.5) / 2.0;
                           end case;
                           Worst := Real'Max (Worst, abs (IX - EX));
                           Worst := Real'Max (Worst, abs (IY - EY));
                        end;
                     end loop;
                  end loop;
                  Check (Worst < 1.0E-9,
                         C'Image & ": every output pixel's centre is the"
                         & " input point it stands for (" & Worst'Image
                         & ")");
               end;
            end if;
         end loop;
      end;
   end Test_Sampling;

   ---------------------------------------------------------------------
   --  PelSet
   ---------------------------------------------------------------------

   function Ref_Pel_Set
     (P         : Matrix;
      Mask      : Matrix;
      OX, OY    : Integer;
      Care_Pels : Boolean;
      Value     : Grey_8;
      Inside    : Matrix) return Matrix;
   --  Value in the pixels the mask marks care (Care_Pels) or don't care,
   --  where Inside is not 0; P elsewhere. Mask pixel (U, V) lies over
   --  (U + OX, V + OY); pixels it does not cover are care.

   function Ref_Pel_Set
     (P         : Matrix;
      Mask      : Matrix;
      OX, OY    : Integer;
      Care_Pels : Boolean;
      Value     : Grey_8;
      Inside    : Matrix) return Matrix
   is
      Result : Matrix := P;
   begin
      for Y in P'Range (1) loop
         for X in P'Range (2) loop
            declare
               U    : constant Integer := X - OX;
               V    : constant Integer := Y - OY;
               Care : constant Boolean :=
                 (if U in Mask'Range (2) and then V in Mask'Range (1)
                  then Mask (V, U) /= 0 else True);
            begin
               if Inside (Y, X) /= 0 and then Care = Care_Pels then
                  Result (Y, X) := Value;
               end if;
            end;
         end loop;
      end loop;
      return Result;
   end Ref_Pel_Set;

   procedure Test_Pel_Set is
      Image : constant Ks_Image_8_Grey := Random_Image (13, 9, 81);
      P     : constant Matrix := Image.To_Matrix;
      All_1 : constant Matrix (P'Range (1), P'Range (2)) :=
        [others => [others => 1]];
      Mask  : Ks_Image_8_Grey := Random_Image (9, 5, 82);
      Tool  : IO.Ks_IP_One_Image_Tool;
      Op    : IO.Ks_IP_One_Image_Operator := IO.New_Operator (IO.Pel_Set);
   begin
      Section ("IP one image: PelSet against the reference");
      --  Make about a third of the mask "don't care".
      for V in 0 .. 4 loop
         for U in 0 .. 8 loop
            if Mask.Get_Pixel (U, V) < 85 then
               Mask.Set_Pixel (U, V, 0);
            end if;
         end loop;
      end loop;
      Tool.Input_Image := Image;
      Tool.Input_Image_Masks (0) := Mask;
      for Offset of Int_Pairs'[[0, 0], [2, 3], [10, 7], [20, 1]] loop
         for Care in Boolean loop
            Op.Pel_Set.Operation :=
              IO.Code (if Care then IO.Set_Care_Pels
                       else IO.Set_Dont_Care_Pels);
            Op.Pel_Set.Pel_Value := 222;
            Op.Pel_Set.Input_Image_Mask_Offset_X := K.Int32 (Offset (1));
            Op.Pel_Set.Input_Image_Mask_Offset_Y := K.Int32 (Offset (2));
            Tool.Operators := List (Op);
            Tool.Run;
            Check (Tool.Run_Status.Result = Accept_Result
                   and then Tool.Output_Image.To_Matrix
                              = Ref_Pel_Set (P, Mask.To_Matrix, Offset (1),
                                             Offset (2), Care, 222, All_1),
                   "PelSet, offset" & Offset (1)'Image & ","
                   & Offset (2)'Image & ", care " & Care'Image);
         end loop;
      end loop;
      Op.Pel_Set.Input_Image_Mask_Offset_X := -3;
      Op.Pel_Set.Input_Image_Mask_Offset_Y := -2;
      Op.Pel_Set.Operation := IO.Code (IO.Set_Care_Pels);
      Tool.Operators := List (Op);
      Tool.Run;
      Check (Tool.Output_Image.To_Matrix
               = Ref_Pel_Set (P, Mask.To_Matrix, -3, -2, True, 222, All_1),
             "PelSet, a negative offset");

      Section ("IP one image: PelSet in a region, after others, errors");
      declare
         Region : constant RH.Holder := Rectangle (1.5, 0.5, 6.0, 5.0);
         B      : constant Box := Box_Of (Selected (Image, Region));
         C      : constant Matrix := Crop (P, B);
         Ones   : constant Matrix (C'Range (1), C'Range (2)) :=
           [others => [others => 1]];
      begin
         Check (B = (2, 1, 6, 5), "the rectangle's box");
         Tool.Region := Region;
         Tool.Run;
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Output_Image.To_Matrix
                           = Ref_Pel_Set (C, Mask.To_Matrix, -3, -2, True,
                                          222, Ones),
                "PelSet on the region's box: the mask's offsets count from"
                & " the box's corner");
         Tool.Region := RH.Empty_Holder;
      end;
      --  The mask of operator I is Input_Image_Masks (I): here operator 1,
      --  after a quarter turn, on the turned image.
      declare
         Turn    : IO.Ks_IP_One_Image_Operator :=
           IO.New_Operator (IO.Flip_Rotate);
         Probe   : IO.Ks_IP_One_Image_Tool;
         Turned  : constant Matrix := Ref_Flip (P, 1);
         Ones    : constant Matrix (Turned'Range (1), Turned'Range (2)) :=
           [others => [others => 1]];
      begin
         Turn.Flip_Rotate.Operation_In_Pixel_Space :=
           IO.Code (IO.Rotate_90_Deg);
         Probe.Input_Image := Image;
         IO.Add (Probe.Operators, Turn);
         IO.Add (Probe.Operators, Op);
         Probe.Input_Image_Masks (1) := Mask;
         Probe.Run;
         Check (Probe.Run_Status.Result = Accept_Result
                and then Probe.Output_Image.To_Matrix
                           = Ref_Pel_Set (Turned, Mask.To_Matrix, -3, -2,
                                          True, 222, Ones),
                "the mask of operator 1, on the turned image ("
                & Probe.Run_Status.Message & ")");
      end;
      declare
         No_Image : Ks_Image_8_Grey;
      begin
         Tool.Input_Image_Masks (0) := No_Image;
      end;
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name = Bad_Name
             and then Tool.Run_Status.Message
                        = "Operators(0).InputImageMask is not set",
             "PelSet without a mask (" & Tool.Run_Status.Message & ")");
      Op.Enabled := K.False_Value;
      Tool.Operators := List (Op);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Output_Image.To_Matrix = P,
             "a disabled PelSet needs no mask");
   end Test_Pel_Set;

   ---------------------------------------------------------------------
   --  Sequences and regions
   ---------------------------------------------------------------------

   procedure Test_Sequence is
      Image : constant Ks_Image_8_Grey := Random_Image (19, 13, 71);
      P     : constant Matrix := Image.To_Matrix;
      Ops   : IO.Ks_IP_One_Image_Operators;
      Op    : IO.Ks_IP_One_Image_Operator;
   begin
      Section ("IP one image: several operators in sequence");
      IO.Add (Ops, IO.New_Operator (IO.Median_3x3));
      IO.Add (Ops, IO.New_Operator (IO.Gauss_Sampler));
      Op := IO.New_Operator (IO.Threshold);
      Op.Threshold.Threshold := 120;
      IO.Add (Ops, Op);
      Op := IO.New_Operator (IO.Flip_Rotate);
      Op.Flip_Rotate.Operation_In_Pixel_Space := IO.Code (IO.Rotate_90_Deg);
      IO.Add (Ops, Op);
      Op := IO.New_Operator (IO.Box_Filter);
      Op.Box_Filter.Kernel_Width := 5;
      IO.Add (Ops, Op);
      declare
         M : constant Matrix := Ref_Median (P, 3, 3);
         G : constant Matrix := Ref_Binomial (M, 2, 2);
         T : constant Matrix :=
           [for Y in G'Range (1) =>
              [for X in G'Range (2) => (if G (Y, X) >= 120 then 255 else 0)]];
         R : constant Matrix := Ref_Flip (T, 1);
         B : constant Matrix := Ref_Box (R, 5, 3);
      begin
         Check (Run (Image, Ops, "sequence") = B,
                "Median3x3, GaussSampler, Threshold, Rotate90Deg, BoxFilter");
         IO.Set_Enabled (Ops.Items (3), False);
         Check (Run (Image, Ops, "disabled")
                  = Ref_Box (T, 5, 3),
                "a disabled operator is skipped");
         Check (not IO.Enabled (IO.Item (Ops, 3)), "Enabled reads back");
      end;
      Check (Run (Image, IO.Ks_IP_One_Image_Operators'(others => <>),
                  "empty list") = P,
             "an empty list copies the image");
   end Test_Sequence;

   procedure Test_Region is
      Image  : constant Ks_Image_8_Grey := Random_Image (31, 23, 81);
      P      : constant Matrix := Image.To_Matrix;
      Region : constant RH.Holder := Circle (14.0, 10.5, 8.3);
      S      : constant Selection := Selected (Image, Region);
      B      : constant Box := Box_Of (S);
      C      : constant Matrix := Crop (P, B);
      SC     : constant Selection := Crop (S, B);
      Boxed  : constant Ks_Image_8_Grey := From_Matrix (C);
      Adjust : constant K.Int32 := IO.Pixel_Aligned_Bounding_Box_Adjust_Mask;
      Op     : IO.Ks_IP_One_Image_Operator;
      Count  : Natural := 0;

      type Mode_Array is array (Positive range <>) of K.Int32;

      function Same_As_Boxed
        (Ops : IO.Ks_IP_One_Image_Operators; What : String) return Boolean
      is (Run (Image, Ops, What, Region) = Run (Boxed, Ops, What & " (box)"));
      --  Pixel_Aligned_Bounding_Box gives what the operators give on the
      --  box as an image of its own.

   begin
      Section ("IP one image: Region_Mode Pixel_Aligned_Bounding_Box");
      for V of SC loop
         Count := Count + Boolean'Pos (V);
      end loop;
      Check (Count > 100 and then Count < B.W * B.H
             and then B.W < 31 and then B.H < 23,
             "the circle covers part of its box, the box part of the"
             & " image");
      declare
         Tool : IO.Ks_IP_One_Image_Tool;
      begin
         Check (Tool.Region_Mode = IO.Pixel_Aligned_Bounding_Box,
                "the default mode is Pixel_Aligned_Bounding_Box");
      end;
      Op := IO.New_Operator (IO.Median_NxM);
      Op.Median_NxM.Kernel_Width := 5;
      Check (Run (Image, List (Op), "median in box", Region)
               = Ref_Median (C, 5, 3),
             "median: every pixel of the box, the box's border reflected");
      Check (Same_As_Boxed (List (Op), "median"), "median: as on the box");
      Op := IO.New_Operator (IO.Grey_Morphology_NxM);
      Op.Grey_Morphology_NxM.Operation := IO.Code (IO.Close);
      Check (Run (Image, List (Op), "close in box", Region)
               = Ref_Morphology (C, IO.Close, 3, 3),
             "close: every pixel of the box");
      Op := IO.New_Operator (IO.Equalize);
      Check (Run (Image, List (Op), "equalize in box", Region)
               = Ref_Equalize (C, Whole (C)),
             "equalize: the histogram of the whole box");
      Check (Same_As_Boxed (List (IO.New_Operator (IO.Unsharp_Mask)),
                            "unsharp"),
             "unsharp mask: as on the box");
      declare
         Ops : IO.Ks_IP_One_Image_Operators;
      begin
         IO.Add (Ops, IO.New_Operator (IO.Box_Filter));
         IO.Add (Ops, IO.New_Operator (IO.Gauss_Sampler));
         Check (Run (Image, Ops, "two in box", Region)
                  = Ref_Binomial (Ref_Box (C, 3, 3), 2, 2),
                "two operators on the box");
      end;
      Op := IO.New_Operator (IO.Flip_Rotate);
      Op.Flip_Rotate.Operation_In_Pixel_Space := IO.Code (IO.Flip);
      Check (Run (Image, List (Op), "flip in box", Region)
               = Ref_Flip (C, 4),
             "an operator that changes the pixel grid works on the box");

      Section ("IP one image: the box keeps the meaning of root coordinates");
      declare
         Moved : Ks_Image_8_Grey := Image;
         T     : constant AMV.Transforms.Ks_Transform_2D_Linear :=
           AMV.Transforms.Create_Similarity (2.0, 0.2, 3.0, -4.0);
      begin
         --  The circle is in the selected space, the root space here: its
         --  box depends on the pixel-from-root transform.
         Moved.Set_Pixel_From_Root_Transform (T);
         declare
            MB   : constant Box := Box_Of (Selected (Moved, Region));
            Tool : IO.Ks_IP_One_Image_Tool;
            MX, MY, OX, OY : Real;
         begin
            Check (MB.W < 31 and then MB.H < 23 and then MB /= B,
                   "the circle's box moves with the transform");
            Tool.Input_Image := Moved;
            Tool.Region := Region;
            for Flip in Boolean loop
               if Flip then
                  Tool.Operators := List (Op);
               else
                  Tool.Operators := List (IO.New_Operator (IO.Median_3x3));
               end if;
               Tool.Run;
               Check (Tool.Run_Status.Result = Accept_Result
                      and then Tool.Output_Image.Width = MB.W
                      and then Tool.Output_Image.Height = MB.H,
                      "the output has the box's size (flip " & Flip'Image
                      & ")");
               --  The root point on input pixel (MB.X0 + 2, MB.Y0 + 3)
               --  lies on output pixel (2, 3), or on its mirror.
               T.Invert.Map_Point
                 (Real (MB.X0 + 2), Real (MB.Y0 + 3), MX, MY);
               Tool.Output_Image.Pixel_From_Root_Transform.Map_Point
                 (MX, MY, OX, OY);
               Check (abs (OX - (if Flip then Real (MB.W - 1 - 2) else 2.0))
                        < 1.0E-9
                      and then abs (OY - 3.0) < 1.0E-9,
                      "a root point keeps its place (flip " & Flip'Image
                      & "):" & OX'Image & OY'Image);
            end loop;
         end;
      end;

      Section ("IP one image: Region_Mode"
               & " Pixel_Aligned_Bounding_Box_Adjust_Mask");
      Op := IO.New_Operator (IO.Median_NxM);
      Op.Median_NxM.Kernel_Width := 5;
      Check (Run (Image, List (Op), "median, mask", Region, Adjust)
               = Merge (Ref_Median (C, 5, 3), C, SC),
             "median: the region's pixels of the box, the others copied");
      Op := IO.New_Operator (IO.Grey_Morphology_NxM);
      Op.Grey_Morphology_NxM.Operation := IO.Code (IO.Close);
      Check (Run (Image, List (Op), "close, mask", Region, Adjust)
               = Merge (Ref_Morphology (C, IO.Close, 3, 3), C, SC),
             "close: the region's pixels");
      Op := IO.New_Operator (IO.Equalize);
      Check (Run (Image, List (Op), "equalize, mask", Region, Adjust)
               = Ref_Equalize (C, SC),
             "equalize: the histogram of the region's pixels");
      declare
         Ops : IO.Ks_IP_One_Image_Operators;
      begin
         IO.Add (Ops, IO.New_Operator (IO.Box_Filter));
         IO.Add (Ops, IO.New_Operator (IO.Gauss_Sampler));
         Check (Run (Image, Ops, "two, mask", Region, Adjust)
                  = Ref_Binomial (Merge (Ref_Box (C, 3, 3), C, SC), 2, 2),
                "two operators: the first on the region's pixels, the"
                & " second on the whole box");
         IO.Set_Enabled (Ops.Items (0), False);
         Check (Run (Image, Ops, "disabled first, mask", Region, Adjust)
                  = Merge (Ref_Binomial (C, 2, 2), C, SC),
                "the first enabled operator is the one the region"
                & " restricts");
         IO.Set_Enabled (Ops.Items (1), False);
         Check (Run (Image, Ops, "none enabled, mask", Region, Adjust) = C,
                "no enabled operator: a copy of the box");
      end;
      declare
         Tool : IO.Ks_IP_One_Image_Tool;
      begin
         Op := IO.New_Operator (IO.Flip_Rotate);
         Op.Flip_Rotate.Operation_In_Pixel_Space := IO.Code (IO.Flip);
         Tool.Input_Image := Image;
         Tool.Operators := List (Op);
         Tool.Region := Region;
         Tool.Region_Mode := Adjust;
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Exception_Name = Bad_Name
                and then not Tool.Output_Image.Allocated,
                "a circle with a FlipRotate first: Error ("
                & Tool.Run_Status.Message & ")");
         Tool.Region := Rectangle (-0.5, -0.5, 31.0, 23.0);
         Tool.Run;
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Output_Image.To_Matrix = Ref_Flip (P, 4),
                "a region covering the whole image is accepted");
         IO.Add (Tool.Operators, Op);
         IO.Set_Enabled (Tool.Operators.Items (0), False);
         Tool.Region := Region;
         Tool.Run;
         Check (Tool.Run_Status.Result = Error,
                "a FlipRotate that becomes the first enabled one: Error");
         Tool.Operators := List (IO.New_Operator (IO.Median_3x3));
         IO.Add (Tool.Operators, Op);
         Tool.Run;
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Output_Image.To_Matrix
                           = Ref_Flip (Merge (Ref_Median (C, 3, 3), C, SC),
                                       4),
                "a FlipRotate after the first operator works on the box ("
                & Tool.Run_Status.Message & ")");
      end;

      Section ("IP one image: Region_Mode Affine_Transform");
      declare
         Tool   : IO.Ks_IP_One_Image_Tool;
         Affine : AMV.Image_Processing.Affine_Transform
                    .Ks_Affine_Transform_Tool;
         R      : Ks_Rectangle_Affine;
         Ops    : IO.Ks_IP_One_Image_Operators;
         MX, MY, AX, AY, OX, OY : Real;
      begin
         IO.Add (Ops, IO.New_Operator (IO.Median_3x3));
         IO.Add (Ops, IO.New_Operator (IO.Equalize));
         Tool.Input_Image := Image;
         Tool.Region_Mode := IO.Affine_Transform;
         Tool.Operators := Ops;
         Affine.Input_Image := Image;
         for Rotation of Real_Array'(0.0, 0.3, -1.2) loop
            R.Set_Center_Lengths_Rotation_Skew
              (15.0, 11.0, 12.0, 8.0, Rotation, 0.1);
            Tool.Region := RH.To_Holder (R);
            Tool.Run;
            Affine.Region := R;
            Affine.Run;
            Check (Tool.Run_Status.Result = Accept_Result
                   and then Affine.Run_Status.Result = Accept_Result
                   and then Tool.Output_Image.To_Matrix
                              = Run (Affine.Output_Image, Ops,
                                     "after the affine transform tool"),
                   "the rectangle resampled as the affine transform tool"
                   & " does, then the operators (rotation" & Rotation'Image
                   & "; " & Tool.Run_Status.Message & ")");
            --  Both outputs have the same pixel-from-root transform.
            Affine.Output_Image.Pixel_From_Root_Transform.Invert.Map_Point
              (3.0, 2.0, MX, MY);
            Affine.Output_Image.Pixel_From_Root_Transform.Map_Point
              (MX, MY, AX, AY);
            Tool.Output_Image.Pixel_From_Root_Transform.Map_Point
              (MX, MY, OX, OY);
            Check (abs (OX - AX) < 1.0E-9 and then abs (OY - AY) < 1.0E-9,
                   "the output's root coordinates are those of the"
                   & " resampled rectangle");
         end loop;
         R.Set_Center_Lengths_Rotation_Skew (15.0, 11.0, 12.0, 8.0, 0.0, 0.0);
         Affine.Region := R;
         Affine.Run;
         Tool.Region := Rectangle (9.0, 7.0, 12.0, 8.0);
         Tool.Run;
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Output_Image.To_Matrix
                           = Run (Affine.Output_Image, Ops, "upright"),
                "a Ks_Rectangle works as the affine rectangle it is");
         Tool.Region := RH.Empty_Holder;
         Tool.Run;
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Output_Image.To_Matrix
                           = Run (Image, Ops, "whole image"),
                "no region: the whole image");
         Tool.Region := Region;
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Exception_Name = Bad_Name
                and then Tool.Run_Status.Message
                           = "Region must be a rectangle or an affine"
                             & " rectangle for RegionMode AffineTransform",
                "a circle: Error (" & Tool.Run_Status.Message & ")");
         Tool.Region := RH.To_Holder (R);
         Op := IO.New_Operator (IO.Pel_Set);
         Tool.Operators := List (Op);
         Tool.Input_Image_Masks (0) := Image;
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Exception_Name = Bad_Name
                and then Tool.Run_Status.Message
                           = "RegionMode AffineTransform does not support a"
                             & " PelSet as the first operator",
                "a PelSet first: Error (" & Tool.Run_Status.Message & ")");
      end;

      Section ("IP one image: region errors");
      declare
         Tool : IO.Ks_IP_One_Image_Tool;
      begin
         Tool.Input_Image := Image;
         Tool.Operators := List (IO.New_Operator (IO.Median_3x3));
         for Mode in K.Int32 range 0 .. 1 loop
            Tool.Region := Rectangle (-50.0, -50.0, 10.0, 10.0);
            Tool.Region_Mode := Mode;
            Tool.Run;
            Check (Tool.Run_Status.Result = Error
                   and then Tool.Run_Status.Exception_Name = Bad_Name
                   and then Tool.Run_Status.Message
                              = "Region covers no pixel of InputImage",
                   "a region outside the image (" & Tool.Run_Status.Message
                   & ")");
         end loop;
         for Mode of Mode_Array'(-1, 3, K.Int32'Last) loop
            Tool.Region := RH.Empty_Holder;
            Tool.Region_Mode := Mode;
            Tool.Run;
            Check (Tool.Run_Status.Result = Error
                   and then Tool.Run_Status.Exception_Name = Bad_Name
                   and then Tool.Run_Status.Message
                              = "RegionMode must be"
                                & " PixelAlignedBoundingBoxAdjustMask (0) or"
                                & " PixelAlignedBoundingBox (1)",
                   "Region_Mode" & Mode'Image & " ("
                   & Tool.Run_Status.Message & ")");
         end loop;
      end;
   end Test_Region;

   ---------------------------------------------------------------------
   --  Errors and the operator list
   ---------------------------------------------------------------------

   procedure Test_Errors is
      Tool : IO.Ks_IP_One_Image_Tool;
      Op   : IO.Ks_IP_One_Image_Operator;
   begin
      Section ("IP one image: Run_Status Error");
      Tool.Operators := List (IO.New_Operator (IO.Median_3x3));
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name = No_Pixels_Name
             and then Tool.Run_Status.Message = "InputImage has no pixels"
             and then not Tool.Output_Image.Allocated,
             "an unallocated image");
      Tool.Input_Image := Random_Image (8, 6, 91);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Output_Image.Allocated, "then a good run");
      Op := IO.New_Operator (IO.Grey_Morphology_NxM);
      Op.Grey_Morphology_NxM.Kernel_Width := 4;
      IO.Add (Tool.Operators, Op);
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name = Bad_Name
             and then Tool.Run_Status.Message
                        = "Operators(1).KernelWidth must be an odd number in"
                          & " 1 .. 1001"
             and then not Tool.Output_Image.Allocated,
             "an even kernel width (" & Tool.Run_Status.Message
             & "), and the output reset");
      IO.Remove_At (Tool.Operators, 1);
      Op := IO.New_Operator (IO.Convolve_NxM);
      Op.Convolve_NxM.Boundary_Mode := IO.Code (IO.Clipped);
      IO.Insert (Tool.Operators, Op, 0);
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Message
                        = "Operators(0).BoundaryMode Clipped is not"
                          & " supported (use Reflected)",
             "BoundaryMode Clipped (" & Tool.Run_Status.Message & ")");
      IO.Clear (Tool.Operators);
      Op := IO.New_Operator (IO.Unsharp_Mask);
      Op.Unsharp_Mask.Amount := Zero / Zero;
      IO.Add (Tool.Operators, Op);
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Message
                        = "Operators(0).Amount must be finite, >= 0 and"
                          & " <= 1000",
             "a NaN Amount (" & Tool.Run_Status.Message & ")");
      IO.Clear (Tool.Operators);
      Tool.Region := Rectangle (0.0, 0.0, 3.0, 3.0);
      declare
         R : Ks_Rectangle;
      begin
         R.Set_XY_Width_Height (0.0, 0.0, 3.0, 3.0);
         R.Set_Selected_Space_Name ("@\Nowhere");
         Tool.Region := RH.To_Holder (R);
      end;
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name = Space_Name,
             "a region in an unknown space");
   end Test_Errors;

   procedure Test_Collection is
      Ops : IO.Ks_IP_One_Image_Operators;
      Op  : IO.Ks_IP_One_Image_Operator;
   begin
      Section ("IP one image: the operator list");
      Check (IO.Count (Ops) = 0, "a new list is empty");
      for Kind in IO.Ks_IP_One_Image_Operator_Kind loop
         Op := IO.New_Operator (Kind);
         Check (IO.Kind (Op) = Kind and then IO.Enabled (Op),
                Kind'Image & ": New_Operator");
      end loop;
      IO.Add (Ops, IO.New_Operator (IO.Equalize));
      IO.Add (Ops, IO.New_Operator (IO.Threshold));
      IO.Insert (Ops, IO.New_Operator (IO.Quantize), 1);
      IO.Insert (Ops, IO.New_Operator (IO.Median_3x3), 3);
      Check (IO.Count (Ops) = 4
             and then IO.Kind (IO.Item (Ops, 0)) = IO.Equalize
             and then IO.Kind (IO.Item (Ops, 1)) = IO.Quantize
             and then IO.Kind (IO.Item (Ops, 2)) = IO.Threshold
             and then IO.Kind (IO.Item (Ops, 3)) = IO.Median_3x3,
             "Add and Insert");
      IO.Move (Ops, 0, 2);
      Check (IO.Kind (IO.Item (Ops, 0)) = IO.Quantize
             and then IO.Kind (IO.Item (Ops, 1)) = IO.Threshold
             and then IO.Kind (IO.Item (Ops, 2)) = IO.Equalize
             and then IO.Kind (IO.Item (Ops, 3)) = IO.Median_3x3,
             "Move forward");
      IO.Move (Ops, 3, 0);
      Check (IO.Kind (IO.Item (Ops, 0)) = IO.Median_3x3
             and then IO.Kind (IO.Item (Ops, 1)) = IO.Quantize
             and then IO.Kind (IO.Item (Ops, 3)) = IO.Equalize,
             "Move back");
      IO.Remove_At (Ops, 1);
      Check (IO.Count (Ops) = 3
             and then IO.Kind (IO.Item (Ops, 1)) = IO.Threshold,
             "Remove_At");
      IO.Set_Item (Ops, 2, IO.New_Operator (IO.Box_Filter));
      Check (IO.Kind (IO.Item (Ops, 2)) = IO.Box_Filter, "Set_Item");

      declare
         procedure Item_Beyond is
            Dummy : constant IO.Ks_IP_One_Image_Operator := IO.Item (Ops, 3);
            pragma Unreferenced (Dummy);
         begin
            null;
         end Item_Beyond;
         procedure Check_Item is new Check_Raises_Exactly
           (Item_Beyond, Constraint_Error'Identity);

         procedure Insert_Beyond is
         begin
            IO.Insert (Ops, Op, 5);
         end Insert_Beyond;
         procedure Check_Insert is new Check_Raises_Exactly
           (Insert_Beyond, Constraint_Error'Identity);

         procedure Move_Beyond is
         begin
            IO.Move (Ops, 0, 3);
         end Move_Beyond;
         procedure Check_Move is new Check_Raises_Exactly
           (Move_Beyond, Constraint_Error'Identity);

         procedure Fill_Up is
         begin
            for I in 1 .. 20 loop
               IO.Add (Ops, Op);
            end loop;
         end Fill_Up;
         procedure Check_Full is new Check_Raises_Exactly
           (Fill_Up, Ks_Bad_Parameter_Exception'Identity);

         procedure Bad_Col is
            P : IO.Ks_IP_One_Image_Convolve_NxM;
         begin
            IO.Set_Kernel_Value (P, 3, 0, 1.0);
         end Bad_Col;
         procedure Check_Col is new Check_Raises_Exactly
           (Bad_Col, Ks_Bad_Parameter_Exception'Identity);

         procedure Bad_Value is
            P : IO.Ks_IP_One_Image_Convolve_3x3;
         begin
            IO.Set_Kernel_Value (P, IO.North, 2.0E6);
         end Bad_Value;
         procedure Check_Value is new Check_Raises_Exactly
           (Bad_Value, Ks_Bad_Parameter_Exception'Identity);
      begin
         Check_Item ("Item beyond Count: Constraint_Error");
         Check_Insert ("Insert beyond Count: Constraint_Error");
         Check_Move ("Move beyond Count: Constraint_Error");
         Check_Full ("a full list: Ks_Bad_Parameter_Exception");
         Check (IO.Count (Ops) = KO.Max_Operators, "the list holds 16");
         Check_Col ("SetKernelValue beyond KernelWidth");
         Check_Value ("SetKernelValue beyond 1.0E6");
      end;
      IO.Clear (Ops);
      Check (IO.Count (Ops) = 0, "Clear");

      declare
         P : IO.Ks_IP_One_Image_Convolve_NxM;
         C : IO.Ks_IP_One_Image_Convolve_3x3;
      begin
         P.Kernel_Width := 5;
         IO.Set_Kernel_Value (P, 4, 2, -3.5);
         Check (IO.Get_Kernel_Value (P, 4, 2) = -3.5
                and then P.Kernel (2 * 15 + 4) = -3.5
                and then IO.Get_Kernel_Value (P, 1, 1) = 1.0,
                "ConvolveNxM kernel values by (Col, Row)");
         IO.Set_Kernel_Value (C, IO.South_East, 0.25);
         Check (IO.Get_Kernel_Value (C, IO.South_East) = 0.25
                and then IO.Get_Kernel (C) (8) = 0.25
                and then IO.Get_Kernel_Value (C, IO.Center) = 1.0,
                "Convolve3x3 kernel values by position");
      end;
   end Test_Collection;

   ---------------------------------------------------------------------
   --  The kernel
   ---------------------------------------------------------------------

   procedure Test_Kernel is
      Image   : KI.Ks_Image_8_Grey;
      Region  : KR.Ks_Pixel_Region;
      Output  : KI.Ks_Image_8_Grey;
      T       : KT.Ks_Transform_2D_Linear;
      Ops     : KO.Ks_IP_One_Image_Operators;
      Op      : KO.Ks_IP_One_Image_Operator;
      Status  : K.Ks_Status;
      NaN     : constant Real := Zero / Zero;
      Identity : constant KT.Ks_Transform_2D_Linear := (others => <>);

      procedure Expect_Fault (What, Message : String) is
      begin
         KO.Operators_Default (Ops);
         KO.Operators_Add (Ops, Op, Status);
         KO.Check_Operators (Ops, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message_Of (Status) = Message,
                What & " (" & Message_Of (Status) & ")");
      end Expect_Fault;
   begin
      Section ("IP one image kernel: null handles");
      KO.Operators_Default (Ops);
      KO.Execute (null, null, Ops, Output, T, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels
             and then Message_Of (Status) = "InputImage has no pixels"
             and then Output = null and then T = Identity,
             "a null image has no pixels");
      KI.Create (6, 4, 9, Image, Status);
      KO.Operator_Default (KO.Kind_Median_3x3, Op, Status);
      KO.Operators_Add (Ops, Op, Status);
      KO.Execute (Image, null, Ops, Output, T, Status);
      declare
         V : KI.Grey_8;
         W, H : K.Int32;
      begin
         KI.Width (Output, W, Status);
         KI.Height (Output, H, Status);
         KI.Get_Pixel (Output, 5, 3, V, Status);
         Check (K.Succeeded (Status) and then W = 6 and then H = 4
                and then V = 9 and then T = Identity,
                "a null region gives an unchanged copy");
      end;
      KI.Destroy (Output, Status);
      KO.Operator_Default (KO.Kind_Flip_Rotate, Op, Status);
      Op.Flip_Rotate.Operation_In_Pixel_Space :=
        KO.Flip_Rotate_Rotate_90_Deg;
      KO.Operators_Default (Ops);
      KO.Operators_Add (Ops, Op, Status);
      KO.Execute (Image, null, Ops, Output, T, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Output = null,
             "a FlipRotate with the empty region ("
             & Message_Of (Status) & ")");
      KR.Whole_Image (6, 4, Region, Status);
      KO.Execute (Image, Region, Ops, Output, T, Status);
      declare
         W, H : K.Int32;
      begin
         KI.Width (Output, W, Status);
         KI.Height (Output, H, Status);
         Check (W = 4 and then H = 6
                and then T = (A => 0.0, B => -1.0, C => 1.0, D => 0.0,
                              Translation_X => 3.0, Translation_Y => 0.0),
                "Rotate90Deg: the sizes swap and the transform maps (x, y)"
                & " to (3 - y, x)");
      end;
      KI.Destroy (Output, Status);
      KR.Destroy (Region, Status);

      Section ("IP one image kernel: codes, limits and non-finite values");
      KO.Operator_Default (99, Op, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message_Of (Status)
                        = "Kind 99 is not a known operator kind",
             "an unknown kind");
      for Kind in KO.Operator_Kind loop
         KO.Operator_Default (Kind, Op, Status);
         KO.Operators_Default (Ops);
         KO.Operators_Add (Ops, Op, Status);
         KO.Check_Operators (Ops, Status);
         Check (K.Succeeded (Status) and then Op.Kind = Kind,
                "the default operator of kind" & Kind'Image & " is valid");
      end loop;
      KO.Operators_Default (Ops);
      Ops.Count := -1;
      KO.Check_Operators (Ops, Status);
      Check (Message_Of (Status) = "Operators.Count must be in 0 .. 16",
             "a negative Count");
      Ops.Count := 17;
      KO.Operators_Add (Ops, Op, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Ops.Count = 17,
             "Add to a list with a bad Count");
      KO.Execute (Image, null, Ops, Output, T, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Output = null,
             "Execute with a bad Count");

      Op := (others => <>);
      Op.Kind := 77;
      Expect_Fault ("a bad kind", "Operators(0).Kind is not a known operator"
                                  & " kind");
      KO.Operator_Default (KO.Kind_Threshold, Op, Status);
      Op.Enabled := 2;
      Expect_Fault ("a bad Enabled", "Operators(0).Enabled must be 0 or 1");
      KO.Operator_Default (KO.Kind_Grey_Morphology_NxM, Op, Status);
      Op.Grey_Morphology_NxM.Kernel_Height := 1003;
      Expect_Fault ("a kernel too high",
                    "Operators(0).KernelHeight must be an odd number in 1 .."
                    & " 1001");
      Op.Grey_Morphology_NxM.Kernel_Height := 3;
      Op.Grey_Morphology_NxM.Operation := 8;
      Expect_Fault ("a bad operation",
                    "Operators(0).Operation must be in 1 .. 7");
      KO.Operator_Default (KO.Kind_Gauss_Sampler, Op, Status);
      Op.Gauss_Sampler.Smoothness_Y := 25;
      Expect_Fault ("smoothness 25",
                    "Operators(0).SmoothnessY must be in 0 .. 24");
      Op.Gauss_Sampler.Smoothness_Y := 2;
      Op.Gauss_Sampler.Magnitude_Shift := -8;
      Expect_Fault ("shift -8",
                    "Operators(0).MagnitudeShift must be in -7 .. 7");
      KO.Operator_Default (KO.Kind_Multiply_Constant, Op, Status);
      Op.Multiply_Constant.Constant_Value := NaN;
      Expect_Fault ("a NaN constant",
                    "Operators(0).ConstantValue must be finite, >= 0 and <="
                    & " 1.0E6");
      Op.Multiply_Constant.Constant_Value := -0.5;
      Expect_Fault ("a negative constant",
                    "Operators(0).ConstantValue must be finite, >= 0 and <="
                    & " 1.0E6");
      Op.Multiply_Constant.Constant_Value := 2.0;
      Op.Multiply_Constant.Overflow_Mode := 2;
      Expect_Fault ("a bad overflow mode",
                    "Operators(0).OverflowMode must be Bounded (0) or Wrap"
                    & " (1)");
      KO.Operator_Default (KO.Kind_Convolve_NxM, Op, Status);
      Op.Convolve_NxM.Kernel (5 * 15 + 5) := NaN;
      KO.Operators_Default (Ops);
      KO.Operators_Add (Ops, Op, Status);
      KO.Check_Operators (Ops, Status);
      Check (K.Succeeded (Status),
             "a NaN in a cell outside the kernel's size is not used");
      Op.Convolve_NxM.Kernel_Width := 7;
      Op.Convolve_NxM.Kernel_Height := 7;
      Expect_Fault ("a NaN kernel value in cell (5, 5) of a 7 x 7 kernel",
                    "Operators(0).kernel values must be finite and within"
                    & " +/-1.0E6");
      Op.Convolve_NxM.Kernel_Width := 17;
      Expect_Fault ("a convolution 17 wide",
                    "Operators(0).KernelWidth must be an odd number in 1 .."
                    & " 15");
      Op.Convolve_NxM.Kernel_Width := 3;
      Op.Convolve_NxM.Kernel_Height := 3;
      Op.Convolve_NxM.Boundary_Mode := 0;
      Expect_Fault ("a bad boundary mode",
                    "Operators(0).BoundaryMode must be Clipped (1) or"
                    & " Reflected (2)");
      KO.Operator_Default (KO.Kind_Convolve_3x3, Op, Status);
      Op.Convolve_3x3.Kernel_Origin := 9;
      Expect_Fault ("a bad origin",
                    "Operators(0).KernelOrigin must be a position code in 0"
                    & " .. 8");
      Op.Convolve_3x3.Kernel_Origin := 0;
      Op.Convolve_3x3.Kernel (5) := -2.0E6;
      Expect_Fault ("a kernel value beyond the bound",
                    "Operators(0).kernel values must be finite and within"
                    & " +/-1.0E6");
      KO.Operator_Default (KO.Kind_Threshold, Op, Status);
      Op.Threshold.Threshold := 257;
      Expect_Fault ("threshold 257",
                    "Operators(0).Threshold must be in 0 .. 256");
      Op.Threshold.Threshold := 0;
      Op.Threshold.High_Value := -1;
      Expect_Fault ("high value -1",
                    "Operators(0).HighValue must be in 0 .. 255");
      KO.Operator_Default (KO.Kind_Quantize, Op, Status);
      Op.Quantize.Levels := 7;
      Expect_Fault ("levels 7", "Operators(0).Levels must be in 0 .. 6");
      KO.Operator_Default (KO.Kind_Flip_Rotate, Op, Status);
      Op.Flip_Rotate.Operation_In_Pixel_Space := 8;
      Expect_Fault ("flip code 8",
                    "Operators(0).OperationInPixelSpace must be in 0 .. 7");
      KO.Operator_Default (KO.Kind_Unsharp_Mask, Op, Status);
      Op.Unsharp_Mask.Amount := 1001.0;
      Expect_Fault ("amount 1001",
                    "Operators(0).Amount must be finite, >= 0 and <= 1000");

      declare
         P     : KO.Ks_IP_One_Image_Convolve_NxM;
         Value : Long_Float;
      begin
         KO.Convolve_NxM_Set_Kernel_Value (P, 0, 0, NaN, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then P.Kernel (0) = 0.0,
                "SetKernelValue rejects a NaN and changes nothing");
         KO.Convolve_NxM_Get_Kernel_Value (P, 0, 3, Value, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter and then Value = 0.0,
                "GetKernelValue beyond KernelHeight");
         P.Kernel_Width := 0;
         KO.Convolve_NxM_Get_Kernel_Value (P, 0, 0, Value, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter,
                "GetKernelValue with a KernelWidth of 0");
      end;
      declare
         C     : KO.Ks_IP_One_Image_Convolve_3x3;
         Value : Long_Float;
      begin
         KO.Convolve_3x3_Get_Kernel_Value (C, 9, Value, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter,
                "Convolve3x3 GetKernelValue at position 9");
      end;

      Section ("IP one image kernel: the list entry points");
      KO.Operators_Default (Ops);
      KO.Operators_Remove_At (Ops, 0, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range
             and then Message_Of (Status)
                        = "RemoveAt: index 0 is outside 0 .. Count - 1",
             "RemoveAt in an empty list");
      KO.Operators_Insert (Ops, Op, -1, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "Insert at -1");
      KO.Operators_Item (Ops, 0, Op, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range, "Item 0 of none");
      KO.Operators_Move (Ops, 0, 0, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range, "Move in none");

      Section ("IP one image kernel: record layouts");
      Check (KO.Ks_IP_One_Image_Operator'Size = 2328 * 8
             and then KO.Ks_IP_One_Image_Operators'Size = 37256 * 8
             and then KO.Ks_IP_One_Image_Convolve_NxM'Size = 1816 * 8
             and then KO.Ks_IP_One_Image_Convolve_3x3'Size = 80 * 8,
             "the sizes of the C structs");
      Check (Op.Convolve_3x3'Position = 16
             and then Op.Convolve_NxM'Position = 96
             and then Op.Flip_Rotate'Position = 1912
             and then Op.Gauss_Sampler'Position = 1916
             and then Op.Grey_Morphology_NxM'Position = 1936
             and then Op.Median_NxM'Position = 1948
             and then Op.Multiply_Constant'Position = 1960
             and then Op.Pixel_Map'Position = 1976
             and then Op.Quantize'Position = 2232
             and then Op.Box_Filter'Position = 2236
             and then Op.Threshold'Position = 2244
             and then Op.Unsharp_Mask'Position = 2256
             and then Op.Expand'Position = 2272
             and then Op.High_Pass_Filter'Position = 2280
             and then Op.Sub_Sampler'Position = 2300
             and then Op.Pel_Set'Position = 2312,
             "the offsets of the members of ks_ip_one_image_operator");
      KI.Destroy (Image, Status);
   end Test_Kernel;

   ---------------------------------------------------------------------
   --  Timing
   ---------------------------------------------------------------------

   procedure Test_Timing is
      Image : constant Ks_Image_8_Grey := Random_Image (640, 480, 101);
      Tool  : IO.Ks_IP_One_Image_Tool;

      procedure Time (Name : String; Op : IO.Ks_IP_One_Image_Operator) is
      begin
         Tool.Operators := List (Op);
         Tool.Run;
         Ada.Text_IO.Put_Line
           ("  640 x 480 " & Name & ":"
            & Integer'Image (Integer (Tool.Run_Status.Processing_Time))
            & " ms");
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Run_Status.Processing_Time < 1000.0,
                Name & " runs on 640 x 480 in well under a second");
      end Time;

      Op : IO.Ks_IP_One_Image_Operator;
   begin
      Section ("IP one image: timing (640 x 480)");
      Tool.Input_Image := Image;
      Tool.Input_Image_Masks (0) := Random_Image (640, 480, 102);
      --  The mask of PelSet (the other operators ignore it).
      for Kind in IO.Ks_IP_One_Image_Operator_Kind loop
         Op := IO.New_Operator (Kind);
         if Kind = IO.Flip_Rotate then
            Op.Flip_Rotate.Operation_In_Pixel_Space :=
              IO.Code (IO.Rotate_90_Deg);
         end if;
         Time (Kind'Image & " (default)", Op);
      end loop;
      Op := IO.New_Operator (IO.Grey_Morphology_NxM);
      Op.Grey_Morphology_NxM.Operation := IO.Code (IO.Close);
      Op.Grey_Morphology_NxM.Kernel_Width := 51;
      Op.Grey_Morphology_NxM.Kernel_Height := 51;
      Time ("Close 51 x 51", Op);
      Op := IO.New_Operator (IO.Median_NxM);
      Op.Median_NxM.Kernel_Width := 15;
      Op.Median_NxM.Kernel_Height := 15;
      Time ("MedianNxM 15 x 15", Op);
      Op := IO.New_Operator (IO.Box_Filter);
      Op.Box_Filter.Kernel_Width := 101;
      Op.Box_Filter.Kernel_Height := 101;
      Time ("BoxFilter 101 x 101", Op);
      Op := IO.New_Operator (IO.Gauss_Sampler);
      Op.Gauss_Sampler.Smoothness_X := 8;
      Op.Gauss_Sampler.Smoothness_Y := 8;
      Time ("GaussSampler smoothness 8", Op);
      Op := IO.New_Operator (IO.Convolve_NxM);
      Op.Convolve_NxM.Kernel_Width := 7;
      Op.Convolve_NxM.Kernel_Height := 7;
      Time ("ConvolveNxM 7 x 7", Op);
      Op.Convolve_NxM.Kernel_Width := 15;
      Op.Convolve_NxM.Kernel_Height := 15;
      Tool.Operators := List (Op);
      Tool.Run;
      Ada.Text_IO.Put_Line
        ("  640 x 480 ConvolveNxM 15 x 15:"
         & Integer'Image (Integer (Tool.Run_Status.Processing_Time))
         & " ms (225 products per pixel)");
      Check (Tool.Run_Status.Result = Accept_Result,
             "ConvolveNxM 15 x 15 runs");
   end Test_Timing;

   procedure Run_All is
   begin
      Test_Pointwise;
      Test_Morphology;
      Test_Median;
      Test_Smoothing;
      Test_Convolution;
      Test_Flip_Rotate;
      Test_Sampling;
      Test_Pel_Set;
      Test_Sequence;
      Test_Region;
      Test_Errors;
      Test_Collection;
      Test_Kernel;
      Test_Timing;
   exception
      when E : others =>
         Fail ("unexpected exception "
               & Ada.Exceptions.Exception_Information (E));
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_IP_One_Image;
