--  GreyMorphologyNxM of AMV.Kernels.IP_One_Image: grey-level erosion and
--  dilation with a flat KernelWidth x KernelHeight rectangle centred on
--  the pixel, and their combinations. Each extreme is separable (rows,
--  then columns) and computed with the running extrema of van Herk and
--  Gil-Werman: the line is cut into blocks of the kernel's length, the
--  extreme from each block's start and from each block's end is
--  accumulated, and every window is the extreme of one value of each, so
--  that a pixel costs three comparisons per direction whatever the size.
--  Internal.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.IP_One_Image.Common;

private package AMV.Kernels.IP_One_Image.Morphology
  with SPARK_Mode, Preelaborate
is

   procedure Erode
     (Source        : access constant KI.Ks_Image_8_Grey_Data;
      Width, Height : Int32;
      Result        : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Odd_Size (Width, Max_Kernel_Size)
             and then Odd_Size (Height, Max_Kernel_Size),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Usable (Result)
                     and then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X) <= Source.Pixels (Y, X)))
                else Result = null);
   --  The minimum over the Width x Height rectangle around each pixel
   --  (Gold: never above the pixel itself, which the rectangle contains;
   --  the result is also limited to it, a limit that never acts).

   procedure Dilate
     (Source        : access constant KI.Ks_Image_8_Grey_Data;
      Width, Height : Int32;
      Result        : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Odd_Size (Width, Max_Kernel_Size)
             and then Odd_Size (Height, Max_Kernel_Size),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Usable (Result)
                     and then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X) >= Source.Pixels (Y, X)))
                else Result = null);
   --  The maximum, in the same way (Gold: never below the pixel).

   procedure Grey_Morphology
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Grey_Morphology_NxM;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Params.Operation in Morphology_Code
             and then Odd_Size (Params.Kernel_Width, Max_Kernel_Size)
             and then Odd_Size (Params.Kernel_Height, Max_Kernel_Size),
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
                     and then
                       (if Params.Operation = Morphology_Erode
                        then (for all Y in Result.Pixels'Range (1) =>
                                (for all X in Result.Pixels'Range (2) =>
                                   Result.Pixels (Y, X)
                                     <= Source.Pixels (Y, X))))
                     and then
                       (if Params.Operation = Morphology_Dilate
                        then (for all Y in Result.Pixels'Range (1) =>
                                (for all X in Result.Pixels'Range (2) =>
                                   Result.Pixels (Y, X)
                                     >= Source.Pixels (Y, X))))
                else Result = null);
   --  The operator: Operation computed over the whole image, then the
   --  selected pixels taken from it and the others from Source. Open =
   --  Dilate (Erode), Close = Erode (Dilate); the three differences are
   --  limited to >= 0 (Dilate - Erode never is negative, by the Gold facts
   --  above; Close - Original and Original - Open are not negative either,
   --  closing never lowering and opening never raising a pixel, which is
   --  not proved).

end AMV.Kernels.IP_One_Image.Morphology;
