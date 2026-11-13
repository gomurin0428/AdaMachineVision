--  The operators of AMV.Kernels.IP_One_Image whose output pixel depends
--  only on the input pixel (AddSubtractConstant, MultiplyConstant,
--  Quantize, Threshold, PixelMap) and Equalize, whose table depends on the
--  histogram of the region. Each builds a table of 256 grey levels and
--  maps the pixels the region selects through it. Internal.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.IP_One_Image.Common;

private package AMV.Kernels.IP_One_Image.Pointwise
  with SPARK_Mode, Preelaborate
is

   subtype Grey_8 is KI.Grey_8;
   subtype Table is KP.Pixel_Map_Table;

   ---------------------------------------------------------------------
   --  The value of one pixel (the Gold definitions)
   ---------------------------------------------------------------------

   function Add_Value
     (V : Grey_8;
      P : Ks_IP_One_Image_Add_Subtract_Constant) return Grey_8
   is
     (if P.Overflow_Mode = Overflow_Mode_Wrap
      then Grey_8 ((Int64 (V) + Int64 (P.Constant_Value)) mod 256)
      else Common.Limit_Grey (Int64 (V) + Int64 (P.Constant_Value)));
   --  AddSubtractConstant: V + ConstantValue, limited to 0 .. 255
   --  (Bounded) or modulo 256 (Wrap).

   function Product (V : Grey_8; C : Long_Float) return Long_Float
   with
     Pre  => C >= 0.0 and then C <= Max_Multiply_Value,
     Post => Product'Result >= 0.0
             and then Product'Result <= 255.0 * Max_Multiply_Value;
   --  V * C.

   function Multiply_Value
     (V : Grey_8;
      P : Ks_IP_One_Image_Multiply_Constant) return Grey_8
   is
     (if P.Overflow_Mode = Overflow_Mode_Wrap
      then Grey_8 (Int64 (Product (V, P.Constant_Value)) mod 256)
      else Common.Limit_Grey (Int64 (Product (V, P.Constant_Value))))
   with
     Pre => P.Constant_Value >= 0.0
            and then P.Constant_Value <= Max_Multiply_Value;
   --  MultiplyConstant: V * ConstantValue rounded to the nearest integer
   --  (halves away from zero), limited to 0 .. 255 (Bounded) or modulo
   --  256 (Wrap).

   type Mask_Table is array (Quantize_Level_S2 .. Quantize_Level_S128)
     of Grey_8;

   Quantize_Masks : constant Mask_Table :=
     [2#1000_0000#, 2#1100_0000#, 2#1110_0000#, 2#1111_0000#,
      2#1111_1000#, 2#1111_1100#, 2#1111_1110#];
   --  The bits Quantize keeps for each Levels code.

   function Quantize_Value
     (V : Grey_8;
      P : Ks_IP_One_Image_Quantize) return Grey_8
   is
     (V and Quantize_Masks (P.Levels))
   with Pre => P.Levels in Quantize_Level_S2 .. Quantize_Level_S128;
   --  Quantize: the Levels + 1 highest bits of V (2 levels: 0 and 128).

   function Threshold_Value
     (V : Grey_8;
      P : Ks_IP_One_Image_Threshold) return Grey_8
   is
     (if Int32 (V) >= P.Threshold then Grey_8 (P.High_Value)
      else Grey_8 (P.Low_Value))
   with Pre => P.Low_Value in 0 .. 255 and then P.High_Value in 0 .. 255;
   --  Threshold: HighValue for V >= Threshold, LowValue otherwise.

   ---------------------------------------------------------------------
   --  The operators
   ---------------------------------------------------------------------

   procedure Map_Pixels
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Map    : Table;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X)
                               = (if Common.Selected (Region, Whole, X, Y)
                                  then Map (Source.Pixels (Y, X))
                                  else Source.Pixels (Y, X))))
                else Result = null);
   --  A new image: Map (value) for the selected pixels, the value
   --  elsewhere (PixelMap).

   procedure Add_Subtract_Constant
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Add_Subtract_Constant;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X)
                               = (if Common.Selected (Region, Whole, X, Y)
                                  then Add_Value (Source.Pixels (Y, X),
                                                  Params)
                                  else Source.Pixels (Y, X))))
                else Result = null);

   procedure Multiply_Constant
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Multiply_Constant;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Params.Constant_Value >= 0.0
             and then Params.Constant_Value <= Max_Multiply_Value,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X)
                               = (if Common.Selected (Region, Whole, X, Y)
                                  then Multiply_Value (Source.Pixels (Y, X),
                                                       Params)
                                  else Source.Pixels (Y, X))))
                else Result = null);

   procedure Quantize
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Quantize;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Params.Levels
                        in Quantize_Level_S2 .. Quantize_Level_S128,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X)
                               = (if Common.Selected (Region, Whole, X, Y)
                                  then Quantize_Value (Source.Pixels (Y, X),
                                                       Params)
                                  else Source.Pixels (Y, X))))
                else Result = null);

   procedure Threshold
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Threshold;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Params.Low_Value in 0 .. 255
             and then Params.High_Value in 0 .. 255,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X)
                               = (if Common.Selected (Region, Whole, X, Y)
                                  then Threshold_Value (Source.Pixels (Y, X),
                                                        Params)
                                  else Source.Pixels (Y, X))))
                else Result = null);
   --  Gold: every selected pixel is exactly HighValue or LowValue by the
   --  rule of Threshold_Value.

   procedure Equalize
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             (if not Common.Selected (Region, Whole, X, Y)
                              then Result.Pixels (Y, X)
                                     = Source.Pixels (Y, X))))
                else Result = null);
   --  Histogram equalisation of the selected pixels: with N of them, C0
   --  of the lowest grey level present and Cdf (V) of grey levels <= V,
   --  V becomes (Cdf (V) - C0) * 255 / (N - C0) rounded (halves up), so
   --  that the lowest level present becomes 0 and the highest 255. A
   --  selection with fewer than two grey levels is left unchanged.

   function Pel_Set_Value
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Pel_Set;
      Mask   : access constant KI.Ks_Image_8_Grey_Data;
      X, Y   : Natural) return KI.Grey_8
   is
     (if Common.Selected (Region, Whole, X, Y)
        and then Sets_Pixel (Params, Mask, X, Y)
      then KI.Grey_8 (Params.Pel_Value)
      else Source.Pixels (Y, X))
   with
     Pre => KI.Valid_Image (Source) and then KI.Valid_Image (Mask)
            and then Params.Pel_Value in 0 .. 255
            and then X < Natural (Source.Width)
            and then Y < Natural (Source.Height);
   --  The pixel (X, Y) of PelSet's result.

   procedure Pel_Set
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Pel_Set;
      Mask   : access constant KI.Ks_Image_8_Grey_Data;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then KI.Valid_Image (Mask)
             and then Params.Pel_Value in 0 .. 255,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X)
                               = Pel_Set_Value (Source, Region, Whole, Params,
                                                Mask, X, Y)))
                else Result = null);
   --  Gold: PelValue exactly in the selected pixels the mask and
   --  Operation select (Sets_Pixel), the input elsewhere.

end AMV.Kernels.IP_One_Image.Pointwise;
