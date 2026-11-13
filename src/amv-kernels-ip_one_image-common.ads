--  What the operator families of AMV.Kernels.IP_One_Image share: the
--  images they accept, the pixels a region selects, the reflection of
--  coordinates beyond the border, grey level conversions, new images, and
--  the merge of a computed image with the input outside the region.
--  Internal (no entry points).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.IP_One_Image.Common
  with SPARK_Mode, Preelaborate
is

   subtype Grey_8 is KI.Grey_8;

   function Usable
     (Image : access constant KI.Ks_Image_8_Grey_Data) return Boolean
   is
     (KI.Valid_Image (Image)
      and then Int64 (Image.Width) * Int64 (Image.Height) <= KI.Max_Pixels);
   --  A valid handle within the size limit of the image kernel (as
   --  AMV.Kernels.Filter_Inputs.Usable_Image).

   function Same_Size
     (Result : access constant KI.Ks_Image_8_Grey_Data;
      Source : access constant KI.Ks_Image_8_Grey_Data) return Boolean
   is
     (KI.Valid_Image (Result)
      and then Result.Width = Source.Width
      and then Result.Height = Source.Height)
   with Pre => KI.Valid_Image (Source);
   --  Result is a valid handle of the size of Source.

   function Selected
     (Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      X, Y   : Natural) return Boolean
   is
     (Whole or else KR.Contains (Region, Int32 (X), Int32 (Y)));
   --  The operators compute pixel (X, Y): Whole (a list that changes the
   --  pixel grid works on the whole image) or the region contains it.

   Fold_Limit : constant := 2**40;
   --  Coordinates passed to Fold stay far within this bound (an image
   --  coordinate plus or minus a kernel's half size).

   function Fold (I : Int64; N : Int64) return Natural
   with
     Pre  => N in 1 .. KI.Max_Pixels and then I in -Fold_Limit .. Fold_Limit,
     Post => Int64 (Fold'Result) < N
             and then (if I in 0 .. N - 1 then Int64 (Fold'Result) = I);
   --  The coordinate I of a line of N pixels continued by reflection
   --  about its ends: I itself within 0 .. N - 1, -1 -> 0, -2 -> 1, N ->
   --  N - 1, N + 1 -> N - 2, and so on with period 2 N.

   function To_Grey (V : Long_Float) return Grey_8 is
     (if not (V > 0.0) then 0
      elsif V >= 255.0 then 255
      else Grey_8 (Int32 (V)));
   --  V rounded to the nearest integer (halves away from zero) and limited
   --  to 0 .. 255 (0 for a NaN, which cannot occur).

   function Limit_Grey (V : Int64) return Grey_8 is
     (if V <= 0 then 0 elsif V >= 255 then 255 else Grey_8 (V));
   --  V limited to 0 .. 255.

   procedure New_Image
     (Width, Height : Int32;
      Result        : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status)
   with
     Pre  => Width >= 1 and then Height >= 1
             and then Int64 (Width) * Int64 (Height) <= KI.Max_Pixels,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then KI.Valid_Image (Result)
                            and then Result.Width = Width
                            and then Result.Height = Height
                       else Result = null);
   --  A new image of that size (every pixel 0). Out_Of_Memory ("IPOneImage:
   --  not enough memory for an image") when it cannot be allocated.

   procedure Select_Pixels
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Full   : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Usable (Source) and then Same_Size (Full, Source),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X)
                               = (if Selected (Region, Whole, X, Y)
                                  then Full.Pixels (Y, X)
                                  else Source.Pixels (Y, X))))
                else Result = null);
   --  A new image holding Full's pixels where the operators compute and
   --  Source's elsewhere.

end AMV.Kernels.IP_One_Image.Common;
