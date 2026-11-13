--  The region modes of the Sobel edge tool (CogSobelEdge.RegionMode,
--  CogRegionModeConstants): the Sobel edge images of the part of the
--  input image that the region selects; the three output images are that
--  part only.
--
--  * Pixel_Aligned_Bounding_Box (VisionPro's default; Execute_In_Box): the
--    part is the pixel-aligned bounding box of the region (the rectangle
--    of its pixel region), whatever the region's shape. Every pixel of the
--    box is processed, as AMV.Kernels.Sobel_Edge.Execute processes a whole
--    image: the derivatives at the box's border replicate the box's
--    border pixels, so no pixel outside the box is read (AMV's choice;
--    VisionPro does not say).
--  * Affine_Transform (Execute_Affine): the part is an affine rectangle,
--    resampled into an upright image by AMV.Kernels.Affine_Transform with
--    that kernel's default run parameters (one output pixel per input
--    pixel along each side; samples outside the image are 0); every
--    pixel of that image is processed. VisionPro accepts only an affine
--    rectangle in this mode; the Ada API rejects other shapes.
--
--  PixelAlignedBoundingBoxAdjustMask is not a region mode of the Sobel
--  edge tool (Bad_Parameter, as VisionPro rejects it).
--
--  The outputs keep the physical places of the input: Output_From_Input
--  (Execute_In_Box) is the shift from the input's pixel coordinates to the
--  box's, and Output_Pixel_From_Root (Execute_Affine) is the outputs'
--  pixel-from-root transform.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any image or
--  region handle that is null or came from the kernels and any
--  parameters; no memory leaks; Gold: the three images have the size of
--  the box (Execute_In_Box) or of the resampled rectangle
--  (Execute_Affine), Output_From_Input is exactly the shift by the box's
--  corner, and the final magnitude image equals the magnitude image for
--  PostProcessMode None.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Affine_Transform;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;

package AMV.Kernels.Sobel_Edge.Region_Modes
  with SPARK_Mode, Preelaborate
is

   package KA renames AMV.Kernels.Affine_Transform;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   use type KT.Ks_Transform_2D_Linear;

   function Box_Transform
     (Region : access constant KR.Ks_Pixel_Region_Data)
      return KT.Ks_Transform_2D_Linear
   is
     ((A             => 1.0,
       B             => 0.0,
       C             => 0.0,
       D             => 1.0,
       Translation_X => -Long_Float (Region.X_Min),
       Translation_Y => -Long_Float (Region.Y_Min)))
   with Pre => Region /= null;
   --  The shift from the input image's pixel coordinates to the box's.

   function Box_Size
     (Region : access constant KR.Ks_Pixel_Region_Data;
      Output : access constant KI.Ks_Image_8_Grey_Data) return Boolean
   is
     (KI.Valid_Image (Output)
      and then Output.Width = Region.Width
      and then Output.Height = Region.Height)
   with Pre => Region /= null;
   --  Output is a valid image of the size of the region's box.

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Check_Affine_Region (Kind : Int32; Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  Bad_Parameter "Region must be an affine rectangle for RegionMode
   --  AffineTransform" unless Kind is KS.Shape_Rectangle_Affine.

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Execute_In_Box
     (Image                 : access constant KI.Ks_Image_8_Grey_Data;
      Region                : access constant KR.Ks_Pixel_Region_Data;
      Params                : Ks_Sobel_Edge;
      Edge_Magnitude_Image  : out KI.Ks_Image_8_Grey;
      Edge_Angle_Image      : out KI.Ks_Image_8_Grey;
      Final_Magnitude_Image : out KI.Ks_Image_8_Grey;
      Output_From_Input     : out KT.Ks_Transform_2D_Linear;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_sobel_edge_execute_in_box",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Transform_Singular
                         | Failure_Out_Of_Memory
             and then KT.Bounded (Output_From_Input)
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then Valid_Params (Params)
                     and then Region /= null
                     and then KR.Valid_Region (Region)
                     and then Box_Size (Region, Edge_Magnitude_Image)
                     and then Box_Size (Region, Edge_Angle_Image)
                     and then Box_Size (Region, Final_Magnitude_Image)
                     and then Output_From_Input = Box_Transform (Region)
                     and then
                       (if Params.Post_Process_Mode = Post_Process_None
                        then Final_Magnitude_Image.Pixels.all
                               = Edge_Magnitude_Image.Pixels.all)
                else Edge_Magnitude_Image = null
                     and then Edge_Angle_Image = null
                     and then Final_Magnitude_Image = null);
   --  The three Sobel images of the bounding box of Region (mode
   --  Pixel_Aligned_Bounding_Box, see above), new handles the caller owns
   --  (all null when the call fails), with Output_From_Input (the identity
   --  when the call fails). The checks, in order: the image
   --  (Image_No_Pixels "InputImage has no pixels", Bad_Parameter
   --  "InputImage is not a valid image handle"), the parameters (those of
   --  Execute, then "RunParams.RegionMode must be PixelAlignedBoundingBox
   --  (1) for ks_sobel_edge_execute_in_box"), the region (Bad_Parameter
   --  "Region covers no pixel of InputImage" for null, "Region is not a
   --  valid pixel region handle", "Region does not lie in InputImage"),
   --  then Out_Of_Memory.

   procedure Execute_Affine
     (Image                  : access constant KI.Ks_Image_8_Grey_Data;
      Region                 : KS.Ks_Rectangle_Affine;
      Pixel_From_Region      : KT.Ks_Transform_2D_Linear;
      Pixel_From_Root        : KT.Ks_Transform_2D_Linear;
      Params                 : Ks_Sobel_Edge;
      Edge_Magnitude_Image   : out KI.Ks_Image_8_Grey;
      Edge_Angle_Image       : out KI.Ks_Image_8_Grey;
      Final_Magnitude_Image  : out KI.Ks_Image_8_Grey;
      Output_Pixel_From_Root : out KT.Ks_Transform_2D_Linear;
      Status                 : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_sobel_edge_execute_affine",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Transform_Singular
                         | Failure_Out_Of_Memory
             and then KT.Bounded (Output_Pixel_From_Root)
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then Valid_Params (Params)
                     and then KI.Valid_Image (Edge_Magnitude_Image)
                     and then KI.Valid_Image (Edge_Angle_Image)
                     and then KI.Valid_Image (Final_Magnitude_Image)
                     and then KS.Valid_Rectangle_Affine (Region)
                     and then KT.Bounded (Pixel_From_Region)
                     and then Edge_Magnitude_Image.Width
                                = KA.Output_Width
                                    (Region, Pixel_From_Region,
                                     KA.Ks_Affine_Transform'(others => <>))
                     and then Edge_Magnitude_Image.Height
                                = KA.Output_Height
                                    (Region, Pixel_From_Region,
                                     KA.Ks_Affine_Transform'(others => <>))
                else Edge_Magnitude_Image = null
                     and then Edge_Angle_Image = null
                     and then Final_Magnitude_Image = null);
   --  The three Sobel images of the affine rectangle Region resampled (see
   --  above; Region is in the space Pixel_From_Region maps to pixel
   --  coordinates, Pixel_From_Root is the input's pixel-from-root
   --  transform), new handles the caller owns (all null when the call
   --  fails), with their pixel-from-root transform. The checks, in order:
   --  the image, the parameters (those of Execute, then
   --  "RunParams.RegionMode must be AffineTransform (2) for
   --  ks_sobel_edge_execute_affine"), then those of
   --  AMV.Kernels.Affine_Transform.Execute (the rectangle, the transforms,
   --  the size of the resampled image) and Out_Of_Memory.

end AMV.Kernels.Sobel_Edge.Region_Modes;
