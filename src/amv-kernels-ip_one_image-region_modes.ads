--  The region modes of the IP one-image tool (CogIPOneImageTool.RegionMode,
--  CogRegionModeConstants): the operators of AMV.Kernels.IP_One_Image run
--  on the part of the input image that the region selects, and the output
--  image is that part only.
--
--  * Pixel_Aligned_Bounding_Box (VisionPro's default; Execute_In_Box): the
--    part is the pixel-aligned bounding box of the region, that is the
--    rectangle of its pixel region. Every pixel of the box is processed,
--    as if the box were the whole input image: the operators read no
--    pixel outside it (their image border is the box's border), and the
--    operators that change the pixel grid are allowed.
--  * Pixel_Aligned_Bounding_Box_Adjust_Mask (Execute_In_Box): the same
--    box, but the first enabled operator of the list processes only the
--    region's own pixels; the other pixels of the box keep their input
--    values through it. The operators after it process the whole box (in
--    VisionPro the region mode concerns the first operator only). When
--    the first enabled operator changes the pixel grid, the region must
--    fill its box.
--  * Affine_Transform (Execute_Affine): the part is an affine rectangle,
--    resampled into an upright image by AMV.Kernels.Affine_Transform with
--    that kernel's default run parameters (scaling 1, so one output pixel
--    per input pixel along each side; its default sampling; samples
--    outside the image are 0). Every pixel of that image is processed.
--    As in VisionPro, a PelSet cannot be the first enabled operator.
--
--  What VisionPro documents is which pixels each mode covers, that the
--  output is the box (or the resampled rectangle), that the mode concerns
--  the first operator, and which operators support each mode. AMV's
--  choices where it says nothing: the operators never read pixels outside
--  the box; the Adjust_Mask mode is accepted for every operator (VisionPro
--  names four that support it: GaussSampler, GreyMorphologyNxM, MedianNxM
--  and PelSet); the mask of a PelSet lies over the image that operator
--  receives, so its offsets count from the box's corner.
--
--  The output keeps the physical places of the input: Output_From_Input
--  (Execute_In_Box) maps the input image's pixel coordinates to the
--  output's (a shift by the box's corner, then the changes of the pixel
--  grid the operators make), and Output_Pixel_From_Root (Execute_Affine)
--  is the output's pixel-from-root transform.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any image or
--  region handle that is null or came from the kernels and any operator
--  list; no memory leaks; Gold: for a list that keeps the pixel grid the
--  output has the size of the box (Execute_In_Box) or of the resampled
--  rectangle (Execute_Affine), and Output_From_Input is exactly the shift
--  by the box's corner.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Affine_Transform;
with AMV.Kernels.Shapes;

package AMV.Kernels.IP_One_Image.Region_Modes
  with SPARK_Mode, Preelaborate
is

   package KA renames AMV.Kernels.Affine_Transform;
   package KS renames AMV.Kernels.Shapes;

   ---------------------------------------------------------------------
   --  Codes (CogRegionModeConstants; C: KS_REGION_MODE_*)
   ---------------------------------------------------------------------

   Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask : constant Int32 := 0;
   Region_Mode_Pixel_Aligned_Bounding_Box             : constant Int32 := 1;
   Region_Mode_Affine_Transform                       : constant Int32 := 2;

   ---------------------------------------------------------------------
   --  Gold
   ---------------------------------------------------------------------

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
   --  The transform from the input image's pixel coordinates to those of
   --  the box: a shift by the box's corner.

   function Fills_Whole_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data) return Boolean
   is
     (Region.Flags = null
      and then Region.X_Min = 0 and then Region.Y_Min = 0
      and then Region.Width = Image.Width
      and then Region.Height = Image.Height)
   with Pre => Image /= null and then Region /= null;
   --  The region is every pixel of the image (the box is the image).

   function First_Enabled (Ops : Ks_IP_One_Image_Operators) return Integer
   with
     Pre  => Ops.Count in 0 .. Max_Operators,
     Post => First_Enabled'Result in -1 .. Integer (Ops.Count) - 1
             and then
               (if First_Enabled'Result >= 0
                then Ops.Items (First_Enabled'Result).Enabled = True_Value)
             and then
               (for all I in 0 .. Integer (Ops.Count) - 1 =>
                  (if I < First_Enabled'Result or else First_Enabled'Result < 0
                   then Ops.Items (I).Enabled /= True_Value));
   --  The index of the first enabled operator, -1 when none is.

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Affine_Region
     (Kind      : Int32;
      Rectangle : KS.Ks_Rectangle;
      Affine    : KS.Ks_Rectangle_Affine;
      Result    : out KS.Ks_Rectangle_Affine;
      Status    : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then KS.Valid_Rectangle_Affine (Result));
   --  The region of the Affine_Transform mode for a region of type Kind
   --  (KS.Shape_*): Affine for an affine rectangle, Rectangle as an affine
   --  rectangle (no rotation, no skew) for a rectangle, Bad_Parameter
   --  "Region must be a rectangle or an affine rectangle for RegionMode
   --  AffineTransform" for any other type (and for values out of bounds).

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Execute_In_Box
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Region            : access constant KR.Ks_Pixel_Region_Data;
      Region_Mode       : Int32;
      Operators         : Ks_IP_One_Image_Operators;
      Masks             : access constant Operator_Masks;
      Output            : out KI.Ks_Image_8_Grey;
      Output_From_Input : out KT.Ks_Transform_2D_Linear;
      Status            : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_execute_in_box",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Transform_Singular
                         | Failure_Out_Of_Memory
             and then KT.Bounded (Output_From_Input)
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then Region /= null
                     and then KR.Valid_Region (Region)
                     and then KR.In_Image (Region, Image.Width, Image.Height)
                     and then KI.Valid_Image (Output)
                     and then Valid_Operators (Operators)
                     and then
                       (if not Has_Geometric (Operators)
                        then Output.Width = Region.Width
                             and then Output.Height = Region.Height
                             and then Output_From_Input
                                        = Box_Transform (Region))
                else Output = null);
   --  Runs the enabled operators on the bounding box of Region in the
   --  mode Region_Mode (Pixel_Aligned_Bounding_Box or
   --  Pixel_Aligned_Bounding_Box_Adjust_Mask, see above) and returns the
   --  result as a new image the caller owns (null when the call fails),
   --  with Output_From_Input (the identity when the call fails). Masks (I)
   --  is the InputImageMask of the operator at index I (null Masks: none).
   --  The checks, in order: the image (Image_No_Pixels "InputImage has no
   --  pixels", Bad_Parameter "InputImage is not a valid image handle"),
   --  Region_Mode (Bad_Parameter), the region (Bad_Parameter "Region
   --  covers no pixel of InputImage" for null, "Region is not a valid
   --  pixel region handle", "Region does not lie in InputImage"), the
   --  operators (Check_Operators), a first operator that changes the pixel
   --  grid in the Adjust_Mask mode with a region that does not fill its
   --  box (Bad_Parameter), then the checks of Execute_Masked on the box
   --  and Out_Of_Memory.

   procedure Execute_Affine
     (Image                  : access constant KI.Ks_Image_8_Grey_Data;
      Region                 : KS.Ks_Rectangle_Affine;
      Pixel_From_Region      : KT.Ks_Transform_2D_Linear;
      Pixel_From_Root        : KT.Ks_Transform_2D_Linear;
      Operators              : Ks_IP_One_Image_Operators;
      Masks                  : access constant Operator_Masks;
      Output                 : out KI.Ks_Image_8_Grey;
      Output_Pixel_From_Root : out KT.Ks_Transform_2D_Linear;
      Status                 : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_execute_affine",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Transform_Singular
                         | Failure_Out_Of_Memory
             and then KT.Bounded (Output_Pixel_From_Root)
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then KI.Valid_Image (Output)
                     and then Valid_Operators (Operators)
                     and then KS.Valid_Rectangle_Affine (Region)
                     and then KT.Bounded (Pixel_From_Region)
                     and then
                       (if not Has_Geometric (Operators)
                        then Output.Width
                               = KA.Output_Width
                                   (Region, Pixel_From_Region,
                                    KA.Ks_Affine_Transform'(others => <>))
                             and then Output.Height
                               = KA.Output_Height
                                   (Region, Pixel_From_Region,
                                    KA.Ks_Affine_Transform'(others => <>)))
                else Output = null);
   --  Resamples the affine rectangle Region of Image (Region is in the
   --  space that Pixel_From_Region maps to pixel coordinates;
   --  Pixel_From_Root is the image's pixel-from-root transform), runs the
   --  enabled operators on the result and returns it as a new image the
   --  caller owns (null when the call fails), with its pixel-from-root
   --  transform. The checks, in order: the image, the operators
   --  (Check_Operators), a PelSet as the first enabled operator
   --  (Bad_Parameter), then the checks of
   --  AMV.Kernels.Affine_Transform.Execute (the rectangle, the
   --  transforms, the size of the resampled image) and of Execute_Masked,
   --  and Out_Of_Memory.

end AMV.Kernels.IP_One_Image.Region_Modes;
