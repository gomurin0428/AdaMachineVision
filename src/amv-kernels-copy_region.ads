--  Kernel of AMV.Image_Processing.Copy_Region: the copy region tool
--  (CogCopyRegionTool, whose run parameters are a CogCopyRegion). The C
--  API is declared in include/amv_ip_geometry.h.
--
--  Execute copies the pixels of a region of an 8-bit image into a new
--  image of the size of the region's pixel-aligned bounding box (the
--  smallest rectangle of pixels around the region, which a pixel region
--  handle of AMV.Kernels.Regions stores): output pixel (X, Y) belongs to
--  input pixel (X + X_Min, Y + Y_Min). RegionMode
--  (CogRegionModeConstants, VisionPro's values) says which pixels of the
--  box count as the region's: PixelAlignedBoundingBoxAdjustMask (0, the
--  default) only those the region contains, PixelAlignedBoundingBox (1)
--  all of them; AffineTransform (2) is not implemented (Bad_Parameter).
--  A pixel of the region gets FillRegionValue when FillRegion is set and
--  the input pixel otherwise; any other pixel of the box gets
--  FillBoundingBoxValue when FillBoundingBox is set (the default) and the
--  input pixel otherwise.
--
--  VisionPro can also copy into an existing destination image, with an
--  alignment of the two images; AMV always makes a new image (no
--  DestinationImage, no alignment).
--
--  Coordinates. The output gets the input's coordinate space tree and
--  selected space (the Ada API copies them) and the pixel-from-root
--  transform Output_Pixel_From_Root that Execute returns: the input's
--  Pixel_From_Root followed by the shift (-X_Min, -Y_Min), so that every
--  space of the tree names the same physical place in both images.
--
--  The region is a pixel region handle that lies in the image (the Ada API
--  rasterises the tool's Region, the whole image for an empty holder).
--  Null, the empty region, has no bounding box and fails with
--  Bad_Parameter ("Region covers no pixel of InputImage").
--
--  Proved (docs/PROOF.md): absence of run-time errors for any image or
--  region handle that is null or came from the kernels and any parameter
--  values; no memory leaks; Gold: the output has the size of the region's
--  bounding box, and every output pixel is exactly the input pixel at its
--  place, or the fill value its kind of pixel (region or not) gets when
--  that fill is on.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Images;
with AMV.Kernels.Regions;
with AMV.Kernels.Transforms;

package AMV.Kernels.Copy_Region with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;
   package KT renames AMV.Kernels.Transforms;

   use type KI.Grey_8;
   use type KI.Ks_Image_8_Grey;

   ---------------------------------------------------------------------
   --  Run parameters (CogCopyRegion; C: ks_copy_region)
   ---------------------------------------------------------------------

   Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask : constant Int32 := 0;
   Region_Mode_Pixel_Aligned_Bounding_Box             : constant Int32 := 1;
   Region_Mode_Affine_Transform                       : constant Int32 := 2;
   --  CogRegionModeConstants (C: KS_REGION_MODE_*).

   type Ks_Copy_Region is record
      Fill_Bounding_Box       : Int32 := True_Value;
      Fill_Bounding_Box_Value : Int32 := 0;
      Fill_Region             : Int32 := False_Value;
      Fill_Region_Value       : Int32 := 255;
      Region_Mode             : Int32 :=
        Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask;
   end record
     with Convention => C;
   --  C: ks_copy_region, with VisionPro's defaults (flags 0 or 1, values
   --  in 0 .. 255).

   procedure Run_Params_Default (Params : out Ks_Copy_Region)
   with
     Export, Convention => C,
     External_Name => "ks_copy_region_run_params_default",
     Post => Params = (others => <>);
   --  The default run parameters. Cannot fail.

   function Valid_Params (Params : Ks_Copy_Region) return Boolean is
     (Params.Fill_Bounding_Box in 0 .. 1
      and then Params.Fill_Bounding_Box_Value in 0 .. 255
      and then Params.Fill_Region in 0 .. 1
      and then Params.Fill_Region_Value in 0 .. 255
      and then Params.Region_Mode
                 in Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask
                  | Region_Mode_Pixel_Aligned_Bounding_Box);
   --  Run parameters Execute accepts.

   ---------------------------------------------------------------------
   --  The output pixels (Gold)
   ---------------------------------------------------------------------

   function Usable_Input
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data) return Boolean
   is
     (KI.Valid_Image (Image)
      and then Region /= null
      and then KR.Valid_Region (Region)
      and then KR.In_Image (Region, Image.Width, Image.Height));
   --  A valid image and a non-empty region that lies in it.

   function In_Copied_Region
     (Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Copy_Region;
      X, Y   : Natural) return Boolean
   is
     (Params.Region_Mode = Region_Mode_Pixel_Aligned_Bounding_Box
      or else KR.Contains (Region, Region.X_Min + Int32 (X),
                           Region.Y_Min + Int32 (Y)))
   with Pre => KR.Valid_Region (Region)
               and then X < Natural (Region.Width)
               and then Y < Natural (Region.Height);
   --  Output pixel (X, Y) counts as a pixel of the region.

   function Copied_Pixel
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Copy_Region;
      X, Y   : Natural) return KI.Grey_8
   is
     (if In_Copied_Region (Region, Params, X, Y)
      then (if Params.Fill_Region = True_Value
            then KI.Grey_8 (Params.Fill_Region_Value)
            else Image.Pixels (Natural (Region.Y_Min) + Y,
                               Natural (Region.X_Min) + X))
      else (if Params.Fill_Bounding_Box = True_Value
            then KI.Grey_8 (Params.Fill_Bounding_Box_Value)
            else Image.Pixels (Natural (Region.Y_Min) + Y,
                               Natural (Region.X_Min) + X)))
   with Pre => Usable_Input (Image, Region) and then Valid_Params (Params)
               and then X < Natural (Region.Width)
               and then Y < Natural (Region.Height);
   --  Output pixel (X, Y): the input pixel at its place, or a fill value.

   ---------------------------------------------------------------------
   --  Entry point
   ---------------------------------------------------------------------

   procedure Execute
     (Image                  : access constant KI.Ks_Image_8_Grey_Data;
      Region                 : access constant KR.Ks_Pixel_Region_Data;
      Pixel_From_Root        : KT.Ks_Transform_2D_Linear;
      Params                 : Ks_Copy_Region;
      Output                 : out KI.Ks_Image_8_Grey;
      Output_Pixel_From_Root : out KT.Ks_Transform_2D_Linear;
      Status                 : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_copy_region_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Transform_Singular
                         | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Usable_Input (Image, Region)
                     and then Valid_Params (Params)
                     and then KI.Valid_Image (Output)
                     and then Output.Width = Region.Width
                     and then Output.Height = Region.Height
                     and then KT.Bounded (Output_Pixel_From_Root)
                     and then
                       (for all Y in Output.Pixels'Range (1)
                        => (for all X in Output.Pixels'Range (2)
                            => Output.Pixels (Y, X)
                                 = Copied_Pixel (Image, Region, Params,
                                                 X, Y)))
                else Output = null);
   --  The copy (see above). Pixel_From_Root is the input image's
   --  pixel-from-root transform. The checks, in order: the image
   --  (Image_No_Pixels "InputImage has no pixels", Bad_Parameter
   --  "InputImage is not a valid image handle"), the region (Bad_Parameter
   --  "Region covers no pixel of InputImage" for null, "Region is not a
   --  valid pixel region handle", "Region does not lie in InputImage"),
   --  Pixel_From_Root ("InputImage.PixelFromRootTransform must be finite and
   --  within 1.0E150"), the run parameters ("RunParams.FillBoundingBox must
   --  be 0 or 1", ..., "RunParams.RegionMode AffineTransform is not
   --  implemented"), the output's transform (Bad_Parameter beyond
   --  1.0E150, Transform_Singular without an inverse within it), then
   --  Out_Of_Memory. Output is a new handle the caller owns, null when the
   --  call fails.

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter;
   --  The image check of Execute, made by the Ada API before it computes
   --  the transforms of the region (whose space may be unknown).

end AMV.Kernels.Copy_Region;
