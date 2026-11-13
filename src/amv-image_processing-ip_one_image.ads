--  The IP one-image tool: the counterpart of VisionPro's CogIPOneImageTool
--  and its operators (CogIPOneImageOperators, ICogIPOneImageOperator and
--  the operator classes CogIPOneImageGreyMorphologyNxM,
--  CogIPOneImageFlipRotate, CogIPOneImageGaussSampler, ...). The tool runs
--  a list of operators one after the other on Input_Image and produces
--  Output_Image:
--
--     Op : Ks_IP_One_Image_Operator := New_Operator (Median_NxM);
--     Op.Median_NxM.Kernel_Width := 5;
--     Add (Tool.Operators, Op);
--     Add (Tool.Operators, New_Operator (Equalize));
--     Tool.Input_Image := Image;
--     Tool.Run;
--     Out := Tool.Output_Image;
--
--  Operators. An operator is one record, Ks_IP_One_Image_Operator: its
--  Kind (one per VisionPro operator class), Enabled, and one component per
--  class holding that class's properties under their VisionPro names
--  (Op.Grey_Morphology_NxM.Operation, Op.Flip_Rotate.
--  Operation_In_Pixel_Space, ...); only the component of the operator's
--  own kind is used. New_Operator (Kind) is the class's constructor.
--  Enumerated properties are Int32 codes with VisionPro's values; the Code
--  functions below give them:
--
--     Op.Grey_Morphology_NxM.Operation := Code (Open);
--
--  Every operator, every limit and every definition (the kernels of the
--  smoothing filters, the reflection at the border, the rounding) is
--  described in AMV.Kernels.IP_One_Image, the SPARK kernel that does all
--  the work (C API: include/amv_ip_one_image.h). Its proofs cover, besides
--  the absence of run-time errors, the size of the output, that pixels
--  outside the region keep their values, and the definitions of
--  Threshold, AddSubtractConstant, MultiplyConstant, the convolutions,
--  erosion and dilation and the flips and rotations.
--
--  Region: each operator changes only the pixels the Region covers
--  (AMV.Regions.Rasterize; an empty holder means the whole image), and
--  the others keep their input values; neighbourhood operators read every
--  pixel of the image. This differs from VisionPro, whose RegionMode crops
--  the output to the region's bounding box. The operators that change the
--  pixel grid (a FlipRotate other than None, a SubSampler or an Expand
--  with a factor above 1, a GaussSampler with SampleX or SampleY above 1)
--  need the whole image: Run fails with Ks_Bad_Parameter_Exception when
--  Region is not empty (or covers less than the whole image).
--
--  Output_Image has the coordinate space tree and the selected space of
--  Input_Image. Its pixel-from-root transform is the input's, composed
--  with the transform the operators make of the pixel grid (flips,
--  rotations, sampling, expansion), so that a point given in the root
--  space "@" (or in any space of the tree) names the same physical content
--  in the input and the output image.
--
--  Run fails (Run_Status Error, Output_Image unallocated) with
--  Ks_Image_No_Pixels_Exception for an unallocated Input_Image,
--  Ks_Bad_Parameter_Exception for a bad operator ("Operators(2).
--  KernelWidth must be an odd number in 1 .. 1001", "Operators(0).
--  InputImageMask is not set" for a PelSet without a mask), a Region_Mode
--  that is not one of the three codes, a region that covers no pixel of
--  the image, a region that does not fill its box with Adjust_Mask and a
--  first operator that changes the pixel grid, a region that is not a
--  rectangle with Affine_Transform, a PelSet as the first operator with
--  Affine_Transform, an image of more than 2**31 - 1 pixels, and
--  Ks_Image_Bad_Selected_Space_Name_Exception for a region in an unknown
--  space (Ks_Transform_Singular_Exception for a rectangle too flat to
--  resample with Affine_Transform).

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels;
with AMV.Kernels.IP_One_Image;
with AMV.Kernels.IP_One_Image.Region_Modes;
with AMV.Kernels.Pixel_Map;
with AMV.Shapes.Region_Holders;
with AMV.Tools;

package AMV.Image_Processing.IP_One_Image is

   package KO renames AMV.Kernels.IP_One_Image;

   subtype Int32 is AMV.Kernels.Int32;

   ---------------------------------------------------------------------
   --  Enumerations (C: KS_IP_ONE_IMAGE_* codes)
   ---------------------------------------------------------------------

   type Ks_IP_One_Image_Operator_Kind is
     (Add_Subtract_Constant, Convolve_3x3, Convolve_NxM, Equalize,
      Flip_Rotate, Gauss_Sampler, Grey_Morphology_NxM, Median_3x3,
      Median_NxM, Multiply_Constant, Pixel_Map, Quantize, Box_Filter,
      Threshold, Unsharp_Mask, Expand, High_Pass_Filter, Sub_Sampler,
      Pel_Set);
   --  (AMV name) One kind per operator class: Add_Subtract_Constant stands
   --  for CogIPOneImageAddSubtractConstant, and so on; Box_Filter,
   --  Threshold and Unsharp_Mask are operators of our own (AMV names).

   type Ks_IP_One_Image_Morphology_Operation_Constants is
     (Erode, Dilate, Open, Close, Dilate_Minus_Erode, Close_Minus_Original,
      Original_Minus_Open);
   for Ks_IP_One_Image_Morphology_Operation_Constants use
     (Erode => 1, Dilate => 2, Open => 3, Close => 4,
      Dilate_Minus_Erode => 5, Close_Minus_Original => 6,
      Original_Minus_Open => 7);

   type Ks_IP_One_Image_Flip_Rotate_Operation_Constants is
     (None, Rotate_90_Deg, Rotate_180_Deg, Rotate_270_Deg, Flip,
      Flip_And_Rotate_90_Deg, Flip_And_Rotate_180_Deg,
      Flip_And_Rotate_270_Deg);
   --  Rotations are clockwise as the image is displayed (y down); Flip is
   --  a left-right mirror, applied before the rotation.

   type Ks_IP_One_Image_Quantize_Level_Constants is
     (S_2, S_4, S_8, S_16, S_32, S_64, S_128);
   --  VisionPro's s2 .. s128: the number of grey levels kept.

   type Ks_IP_One_Image_Add_Subtract_Constant_Overflow_Mode_Constants is
     (Bounded, Wrap);
   subtype Ks_IP_One_Image_Multiply_Constant_Overflow_Mode_Constants is
     Ks_IP_One_Image_Add_Subtract_Constant_Overflow_Mode_Constants;
   --  VisionPro has two enumerations with the same values; here the second
   --  is a subtype of the first, so that Bounded and Wrap need no
   --  qualification.

   type Ks_IP_One_Image_Boundary_Mode_Constants is (Clipped, Reflected);
   for Ks_IP_One_Image_Boundary_Mode_Constants use
     (Clipped => 1, Reflected => 2);
   --  Only Reflected is supported.

   type Ks_IP_One_Image_High_Pass_Filter_Processing_Mode_Constants is
     (Gauss, Mean, Median);
   --  The smoothing whose result HighPassFilter subtracts.

   type Ks_IP_One_Image_Pel_Set_Operation_Constants is
     (Set_Care_Pels, Set_Dont_Care_Pels);
   for Ks_IP_One_Image_Pel_Set_Operation_Constants use
     (Set_Care_Pels => 1, Set_Dont_Care_Pels => 2);
   --  The pixels PelSet writes: those its mask marks "care" or "don't
   --  care".

   type Ks_IP_One_Image_Convolve_3x3_Position_Constants is
     (North_West, North, North_East, West, Center, East, South_West, South,
      South_East);

   subtype Ks_Region_Mode_Constants is Int32 range 0 .. 2;
   --  CogRegionModeConstants (Cognex.VisionPro), with VisionPro's values:
   --  the codes of the tool's Region_Mode.

   Pixel_Aligned_Bounding_Box_Adjust_Mask :
     constant Ks_Region_Mode_Constants :=
       AMV.Kernels.IP_One_Image.Region_Modes
         .Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask;
   --  The box of the region; the first operator changes only the region's
   --  pixels.
   Pixel_Aligned_Bounding_Box : constant Ks_Region_Mode_Constants :=
     AMV.Kernels.IP_One_Image.Region_Modes
       .Region_Mode_Pixel_Aligned_Bounding_Box;
   --  The default: every pixel of the region's box is processed.
   Affine_Transform : constant Ks_Region_Mode_Constants :=
     AMV.Kernels.IP_One_Image.Region_Modes.Region_Mode_Affine_Transform;
   --  The rectangle Region resampled into an upright image.

   function Code (Value : Ks_IP_One_Image_Operator_Kind) return Int32 is
     (Ks_IP_One_Image_Operator_Kind'Pos (Value));
   function Code
     (Value : Ks_IP_One_Image_Morphology_Operation_Constants) return Int32
   is (Ks_IP_One_Image_Morphology_Operation_Constants'Enum_Rep (Value));
   function Code
     (Value : Ks_IP_One_Image_Flip_Rotate_Operation_Constants) return Int32
   is (Ks_IP_One_Image_Flip_Rotate_Operation_Constants'Pos (Value));
   function Code
     (Value : Ks_IP_One_Image_Quantize_Level_Constants) return Int32
   is (Ks_IP_One_Image_Quantize_Level_Constants'Pos (Value));
   function Code
     (Value : Ks_IP_One_Image_Add_Subtract_Constant_Overflow_Mode_Constants)
      return Int32
   is (Ks_IP_One_Image_Add_Subtract_Constant_Overflow_Mode_Constants'Pos
         (Value));
   function Code
     (Value : Ks_IP_One_Image_Boundary_Mode_Constants) return Int32
   is (Ks_IP_One_Image_Boundary_Mode_Constants'Enum_Rep (Value));
   function Code
     (Value : Ks_IP_One_Image_Convolve_3x3_Position_Constants) return Int32
   is (Ks_IP_One_Image_Convolve_3x3_Position_Constants'Pos (Value));
   function Code
     (Value : Ks_IP_One_Image_Pel_Set_Operation_Constants) return Int32
   is (Ks_IP_One_Image_Pel_Set_Operation_Constants'Enum_Rep (Value));
   function Code
     (Value : Ks_IP_One_Image_High_Pass_Filter_Processing_Mode_Constants)
      return Int32
   is (Ks_IP_One_Image_High_Pass_Filter_Processing_Mode_Constants'Pos
         (Value));
   --  The codes the operator records hold.

   function Operator_Kind (Code : Int32) return Ks_IP_One_Image_Operator_Kind
   is (Ks_IP_One_Image_Operator_Kind'Val (Code));
   function Morphology_Operation
     (Code : Int32) return Ks_IP_One_Image_Morphology_Operation_Constants
   is (Ks_IP_One_Image_Morphology_Operation_Constants'Enum_Val (Code));
   function Flip_Rotate_Operation
     (Code : Int32) return Ks_IP_One_Image_Flip_Rotate_Operation_Constants
   is (Ks_IP_One_Image_Flip_Rotate_Operation_Constants'Val (Code));
   function Quantize_Level
     (Code : Int32) return Ks_IP_One_Image_Quantize_Level_Constants
   is (Ks_IP_One_Image_Quantize_Level_Constants'Val (Code));
   function Overflow_Mode
     (Code : Int32)
      return Ks_IP_One_Image_Add_Subtract_Constant_Overflow_Mode_Constants
   is (Ks_IP_One_Image_Add_Subtract_Constant_Overflow_Mode_Constants'Val
         (Code));
   function Boundary_Mode
     (Code : Int32) return Ks_IP_One_Image_Boundary_Mode_Constants
   is (Ks_IP_One_Image_Boundary_Mode_Constants'Enum_Val (Code));
   function Position
     (Code : Int32) return Ks_IP_One_Image_Convolve_3x3_Position_Constants
   is (Ks_IP_One_Image_Convolve_3x3_Position_Constants'Val (Code));
   function Pel_Set_Operation
     (Code : Int32) return Ks_IP_One_Image_Pel_Set_Operation_Constants
   is (Ks_IP_One_Image_Pel_Set_Operation_Constants'Enum_Val (Code));
   function Processing_Mode
     (Code : Int32)
      return Ks_IP_One_Image_High_Pass_Filter_Processing_Mode_Constants
   is (Ks_IP_One_Image_High_Pass_Filter_Processing_Mode_Constants'Val
         (Code));
   --  The enumeration value of a code (Constraint_Error for a code that
   --  is not one).

   ---------------------------------------------------------------------
   --  Operators (ICogIPOneImageOperator and the operator classes)
   ---------------------------------------------------------------------

   subtype Ks_IP_One_Image_Add_Subtract_Constant is
     KO.Ks_IP_One_Image_Add_Subtract_Constant;
   --  Constant_Value (0), Overflow_Mode (Bounded).
   subtype Ks_IP_One_Image_Convolve_3x3 is KO.Ks_IP_One_Image_Convolve_3x3;
   --  Kernel_Origin (Center), Kernel (nine values by position; the
   --  default copies the image).
   subtype Ks_IP_One_Image_Convolve_NxM is KO.Ks_IP_One_Image_Convolve_NxM;
   --  Kernel_Width (3), Kernel_Height (3), Boundary_Mode (Reflected),
   --  Kernel (cell (Col, Row) at Row * 15 + Col; the default copies).
   subtype Ks_IP_One_Image_Flip_Rotate is KO.Ks_IP_One_Image_Flip_Rotate;
   --  Operation_In_Pixel_Space (None).
   subtype Ks_IP_One_Image_Gauss_Sampler is KO.Ks_IP_One_Image_Gauss_Sampler;
   --  Smoothness_X (2), Smoothness_Y (2), Magnitude_Shift (0), Sample_X
   --  (1), Sample_Y (1).
   subtype Ks_IP_One_Image_Grey_Morphology_NxM is
     KO.Ks_IP_One_Image_Grey_Morphology_NxM;
   --  Operation (Erode), Kernel_Width (3), Kernel_Height (3).
   subtype Ks_IP_One_Image_Median_NxM is KO.Ks_IP_One_Image_Median_NxM;
   --  Kernel_Width (3), Kernel_Height (3).
   subtype Ks_IP_One_Image_Multiply_Constant is
     KO.Ks_IP_One_Image_Multiply_Constant;
   --  Constant_Value (1.0), Overflow_Mode (Bounded).
   subtype Ks_IP_One_Image_Pixel_Map is
     AMV.Kernels.Pixel_Map.Ks_IP_One_Image_Pixel_Map;
   --  Map (the identity); also the run parameters of
   --  AMV.Image_Processing.Pixel_Map, whose Get_Map and Set_Map apply.
   subtype Ks_IP_One_Image_Quantize is KO.Ks_IP_One_Image_Quantize;
   --  Levels (S_2).
   subtype Ks_IP_One_Image_Box_Filter is KO.Ks_IP_One_Image_Box_Filter;
   --  (AMV name) Kernel_Width (3), Kernel_Height (3).
   subtype Ks_IP_One_Image_Threshold is KO.Ks_IP_One_Image_Threshold;
   --  (AMV name) Threshold (128), Low_Value (0), High_Value (255).
   subtype Ks_IP_One_Image_Unsharp_Mask is KO.Ks_IP_One_Image_Unsharp_Mask;
   --  (AMV name) Amount (1.0), Smoothness_X (2), Smoothness_Y (2).
   subtype Ks_IP_One_Image_Expand is KO.Ks_IP_One_Image_Expand;
   --  Expansion_X (2), Expansion_Y (2).
   subtype Ks_IP_One_Image_High_Pass_Filter is
     KO.Ks_IP_One_Image_High_Pass_Filter;
   --  Processing_Mode (Gauss), Smoothness_X (2), Smoothness_Y (2),
   --  Kernel_Width (3), Kernel_Height (3).
   subtype Ks_IP_One_Image_Sub_Sampler is KO.Ks_IP_One_Image_Sub_Sampler;
   --  Sample_X (2), Sample_Y (2), Spatial_Average (0: plain sampling).
   subtype Ks_IP_One_Image_Pel_Set is KO.Ks_IP_One_Image_Pel_Set;
   --  Operation (Set_Care_Pels), Pel_Value (0), Input_Image_Mask_Offset_X
   --  (0), Input_Image_Mask_Offset_Y (0). Its InputImageMask is the
   --  tool's Input_Image_Masks (I), I being the operator's index.

   function Sigma_X (Params : Ks_IP_One_Image_Gauss_Sampler) return Long_Float
   is (KO.Sigma (Params.Smoothness_X));
   function Sigma_Y (Params : Ks_IP_One_Image_Gauss_Sampler) return Long_Float
   is (KO.Sigma (Params.Smoothness_Y));
   function Sigma_X
     (Params : Ks_IP_One_Image_High_Pass_Filter) return Long_Float
   is (KO.Sigma (Params.Smoothness_X));
   function Sigma_Y
     (Params : Ks_IP_One_Image_High_Pass_Filter) return Long_Float
   is (KO.Sigma (Params.Smoothness_Y));
   --  SigmaX and SigmaY (read only): the standard deviation in pixels of
   --  the binomial smoothing, Sqrt (Smoothness / 2) (0.0 for a smoothness
   --  outside 0 .. 24).

   subtype Ks_IP_One_Image_Operator is KO.Ks_IP_One_Image_Operator;
   --  Kind (a code of Ks_IP_One_Image_Operator_Kind), Enabled (0 or 1)
   --  and one component per class (see above).

   function New_Operator (Kind : Ks_IP_One_Image_Operator_Kind)
      return Ks_IP_One_Image_Operator;
   --  A new enabled operator of that kind with the defaults of its class.

   function Kind (Operator : Ks_IP_One_Image_Operator)
      return Ks_IP_One_Image_Operator_Kind;
   --  The kind of Operator. Ks_Bad_Parameter_Exception when Operator.Kind
   --  is not the code of a kind (a record changed by hand).

   function Enabled (Operator : Ks_IP_One_Image_Operator) return Boolean;
   --  Ks_Bad_Parameter_Exception when Operator.Enabled is not 0 or 1.
   procedure Set_Enabled
     (Operator : in out Ks_IP_One_Image_Operator;
      Value    : Boolean);
   --  ICogIPOneImageOperatorParams.Enabled: a disabled operator is skipped.

   function Get_Kernel_Value
     (Params   : Ks_IP_One_Image_Convolve_NxM;
      Col, Row : Natural) return Real;
   procedure Set_Kernel_Value
     (Params    : in out Ks_IP_One_Image_Convolve_NxM;
      Col, Row  : Natural;
      New_Value : Real);
   --  GetKernelValue / SetKernelValue of CogIPOneImageConvolveNxM:
   --  Ks_Bad_Parameter_Exception unless Col < Kernel_Width and Row <
   --  Kernel_Height (and, for Set, New_Value is finite and within
   --  +/-1.0E6).

   subtype Convolve_3x3_Kernel is KO.Convolve_3x3_Kernel;
   --  array (0 .. 8) of Real, by position code.

   function Get_Kernel (Params : Ks_IP_One_Image_Convolve_3x3)
      return Convolve_3x3_Kernel
   is (Params.Kernel);
   procedure Set_Kernel
     (Params : in out Ks_IP_One_Image_Convolve_3x3;
      Kernel : Convolve_3x3_Kernel);
   --  GetKernel / SetKernel of CogIPOneImageConvolve3x3 (the values are
   --  checked when the tool runs).

   function Get_Kernel_Value
     (Params   : Ks_IP_One_Image_Convolve_3x3;
      Position : Ks_IP_One_Image_Convolve_3x3_Position_Constants)
      return Real;
   procedure Set_Kernel_Value
     (Params   : in out Ks_IP_One_Image_Convolve_3x3;
      Position : Ks_IP_One_Image_Convolve_3x3_Position_Constants;
      Value    : Real);
   --  GetKernelValue / SetKernelValue (position) of
   --  CogIPOneImageConvolve3x3 (Set: Ks_Bad_Parameter_Exception unless
   --  Value is finite and within +/-1.0E6).

   ---------------------------------------------------------------------
   --  The operator list (CogIPOneImageOperators)
   ---------------------------------------------------------------------

   subtype Ks_IP_One_Image_Operators is KO.Ks_IP_One_Image_Operators;
   --  At most KO.Max_Operators (16) operators: Items (0 .. Count - 1),
   --  applied in that order. Empty by default.

   function Count (Operators : Ks_IP_One_Image_Operators) return Natural;
   --  Operators.Count. Ks_Bad_Parameter_Exception when it is not in
   --  0 .. KO.Max_Operators (a list whose Count was set by hand).

   function Item
     (Operators : Ks_IP_One_Image_Operators;
      Index     : Natural) return Ks_IP_One_Image_Operator;
   procedure Set_Item
     (Operators : in out Ks_IP_One_Image_Operators;
      Index     : Natural;
      Operator  : Ks_IP_One_Image_Operator);
   --  Item (get and set). Constraint_Error unless Index < Count.

   procedure Add
     (Operators : in out Ks_IP_One_Image_Operators;
      Operator  : Ks_IP_One_Image_Operator);
   --  Appends Operator; Ks_Bad_Parameter_Exception when the list is full.

   procedure Insert
     (Operators : in out Ks_IP_One_Image_Operators;
      Operator  : Ks_IP_One_Image_Operator;
      Index     : Natural);
   --  Insert (value, index): Operator at Index, the later ones moved up.
   --  Constraint_Error unless Index <= Count; Ks_Bad_Parameter_Exception
   --  when the list is full.

   procedure Remove_At
     (Operators : in out Ks_IP_One_Image_Operators;
      Index     : Natural);
   --  Removes Items (Index); Constraint_Error unless Index < Count.

   procedure Move
     (Operators  : in out Ks_IP_One_Image_Operators;
      From_Index : Natural;
      To_Index   : Natural);
   --  Moves the operator at From_Index to To_Index; Constraint_Error
   --  unless both are < Count.

   procedure Clear (Operators : in out Ks_IP_One_Image_Operators);
   --  Removes every operator.

   ---------------------------------------------------------------------
   --  The tool (CogIPOneImageTool)
   ---------------------------------------------------------------------

   type Ks_IP_One_Image_Masks is
     array (0 .. KO.Max_Operators - 1) of AMV.Images.Ks_Image_8_Grey;
   --  (AMV name) The InputImageMask of each operator of a list, by the
   --  operator's index (unallocated: none). A mask stays at its index
   --  when operators are inserted, removed or moved.

   type Ks_IP_One_Image_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image       : AMV.Images.Ks_Image_8_Grey;
      Region            : AMV.Shapes.Region_Holders.Holder;
      --  Empty: the whole image.
      Region_Mode       : Int32 := Pixel_Aligned_Bounding_Box;
      --  A Ks_Region_Mode_Constants code (checked when the tool runs).
      Operators         : Ks_IP_One_Image_Operators;
      Input_Image_Masks : Ks_IP_One_Image_Masks;
      --  The masks of the PelSet operators (see Ks_IP_One_Image_Pel_Set).
      Output_Image      : AMV.Images.Ks_Image_8_Grey;
      --  Set by Run (read-only by convention); unallocated after a run
      --  that failed.
   end record;

   overriding procedure Execute (Tool : in out Ks_IP_One_Image_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_IP_One_Image_Tool);

end AMV.Image_Processing.IP_One_Image;
