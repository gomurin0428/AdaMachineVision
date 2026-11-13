--  Checks shared by the kernels of the image processing filters
--  (AMV.Kernels.Histogram, AMV.Kernels.Pixel_Map, AMV.Kernels.Sobel_Edge,
--  AMV.Kernels.Image_Sharpness): the input image and the pixel region
--  every one of them takes, and the decimal images used in messages.
--  Internal: not an entry point (no export), so the package is private to
--  the kernels.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Images;
with AMV.Kernels.Regions;

private package AMV.Kernels.Filter_Inputs with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;

   function Usable_Image
     (Image : access constant KI.Ks_Image_8_Grey_Data) return Boolean
   is
     (KI.Valid_Image (Image)
      and then Int64 (Image.Width) * Int64 (Image.Height) <= KI.Max_Pixels);
   --  A valid handle whose size is within the limit of the image kernel
   --  (every handle ks_image_8_grey_create returns), so that a count of
   --  its pixels fits in an Int32.

   procedure Check_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Usable_Image (Image));
   --  Image_No_Pixels for null ("InputImage has no pixels"), Bad_Parameter
   --  for a record that is not a usable handle ("InputImage is not a valid
   --  image handle").

   procedure Check_Input
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Usable_Image (Image)
                            and then (Region = null
                                      or else KR.Valid_Region (Region)));
   --  Check_Image, then Bad_Parameter for a region record that is not
   --  valid ("Region is not a valid pixel region handle"). Null is the
   --  empty region and is accepted. A region need not lie in the image:
   --  the tools use only its pixels inside the image.

   function Image_Of (Value : Int64) return String
   with Pre  => Value > Int64'First,
        Post => Image_Of'Result'First = 1
                and then Image_Of'Result'Length in 1 .. 20;
   --  The decimal digits of Value, with a leading '-' when it is negative.

end AMV.Kernels.Filter_Inputs;
