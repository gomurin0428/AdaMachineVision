--  Kernel of AMV.Image_Processing.IP_One_Image: the counterpart of
--  VisionPro's CogIPOneImageTool, which runs a list of image operators
--  (CogIPOneImageOperators) one after the other on an 8-bit image. The C
--  API is declared in include/amv_ip_one_image.h.
--
--  Operators. An operator is one record, Ks_IP_One_Image_Operator: a kind
--  code (one per operator class), Enabled (VisionPro's
--  ICogIPOneImageOperatorParams.Enabled; a disabled operator is skipped)
--  and one component per operator class holding the properties of that
--  class under their VisionPro names. Only the component of the record's
--  own kind is used (and checked); the others keep whatever they hold. The
--  operators of a run are a fixed-capacity list, Ks_IP_One_Image_Operators
--  (CogIPOneImageOperators: Count, then Items (0 .. Count - 1)), applied in
--  the order of the list, each to the image the previous one produced.
--
--  The kinds, with their codes (AMV codes: VisionPro's classes in the
--  order of their names, then three operators of our own, then the
--  VisionPro classes added later, in the order they were added):
--
--     0  AddSubtractConstant  value + ConstantValue (an integer);
--                             Bounded clamps to 0 .. 255, Wrap keeps the
--                             value modulo 256.
--     1  Convolve3x3          a 3 x 3 kernel of reals (positions 0 .. 8,
--                             row by row from NorthWest); the result is
--                             stored at the pixel under KernelOrigin.
--     2  ConvolveNxM          a KernelWidth x KernelHeight kernel of reals
--                             (odd sizes up to Max_Convolve_Size) centred
--                             on the pixel; BoundaryMode Reflected only.
--     3  Equalize             histogram equalisation over the region.
--     4  FlipRotate           flips and quarter turns of the whole image
--                             (OperationInPixelSpace, see below).
--     5  GaussSampler         a binomial approximation of a Gaussian
--                             along x and y (SmoothnessX, SmoothnessY),
--                             then MagnitudeShift.
--     6  GreyMorphologyNxM    erosion, dilation and their combinations
--                             with a flat KernelWidth x KernelHeight
--                             rectangle (Operation).
--     7  Median3x3            the median of the 3 x 3 neighbourhood.
--     8  MedianNxM            the median of a KernelWidth x KernelHeight
--                             neighbourhood.
--     9  MultiplyConstant     value * ConstantValue (a real >= 0),
--                             rounded; Bounded or Wrap as above.
--    10  PixelMap             a lookup table (as AMV.Kernels.Pixel_Map).
--    11  Quantize             keeps the Levels code + 1 highest bits.
--    12  BoxFilter (AMV)      the mean of a KernelWidth x KernelHeight
--                             neighbourhood.
--    13  Threshold (AMV)      HighValue for a value >= Threshold, LowValue
--                             otherwise.
--    14  UnsharpMask (AMV)    value + Amount * (value - smoothed value),
--                             smoothed as by GaussSampler.
--    15  Expand               each pixel repeated ExpansionX times along
--                             x and ExpansionY times along y.
--    16  HighPassFilter       value - smoothed value + 128, smoothed by
--                             ProcessingMode: Gauss (as GaussSampler,
--                             SmoothnessX, SmoothnessY), Mean (as
--                             BoxFilter) or Median (as MedianNxM), both
--                             with KernelWidth x KernelHeight.
--    17  SubSampler           every SampleX-th pixel along x and every
--                             SampleY-th along y, or with SpatialAverage
--                             the mean of each SampleX x SampleY block.
--    18  PelSet               PelValue in the pixels its InputImageMask
--                             marks "care" (SetCarePels) or "don't care"
--                             (SetDontCarePels).
--
--  Pixel values. Every operator reads and writes 8-bit grey levels. A
--  result that is a real or an integer outside 0 .. 255 is rounded to the
--  nearest integer (halves away from zero) and limited to 0 .. 255 unless
--  the operator's OverflowMode is Wrap.
--
--  Neighbourhoods. The neighbourhood operators (the convolutions, the
--  smoothing filters, the morphology and the medians) read pixels around
--  the one they compute; beyond the edge of the image the image is
--  continued by reflection about its border (column -1 reads column 0,
--  column -2 column 1, column Width column Width - 1, and so on, again and
--  again for a neighbourhood larger than the image). They read every pixel
--  of the image, also those outside the region.
--
--  GaussSampler and UnsharpMask (our own definition; VisionPro does not
--  publish its kernel): along x the image is convolved with the binomial
--  weights C (2 Sx, k) / 4**Sx, k = 0 .. 2 Sx, centred on the pixel (Sx =
--  SmoothnessX; the standard deviation is Sqrt (Sx / 2) pixels, so the
--  default 2 gives 1), the result rounded to a grey level; then the same
--  along y with SmoothnessY. GaussSampler then shifts the smoothed value
--  left by MagnitudeShift bits (limited to 255) or, for a negative shift,
--  right. GaussSampler's SampleX and SampleY then keep every SampleX-th
--  pixel along x and every SampleY-th along y, as SubSampler without
--  SpatialAverage (1 and 1, the defaults, keep every pixel). BoxFilter
--  likewise: the mean along x (rounded), then the mean of those along y
--  (rounded).
--
--  HighPassFilter (our own definition of the output): value - S + 128,
--  limited to 0 .. 255, S being the smoothed value of the pixel, so that
--  a flat area becomes the middle grey 128 and the details keep their
--  sign. ProcessingMode Gauss smooths as GaussSampler (without shift and
--  sampling; SigmaX = Sqrt (SmoothnessX / 2)), Mean as BoxFilter and
--  Median as MedianNxM, with the kernel's KernelWidth and KernelHeight.
--
--  SubSampler and Expand (our own definition of the pixel grid). For a W
--  x H image SubSampler gives Ceiling (W / SampleX) x Ceiling (H /
--  SampleY) pixels: output pixel (X, Y) is input pixel (X SampleX, Y
--  SampleY), or with SpatialAverage the mean (rounded half up) of the
--  block X SampleX .. X SampleX + SampleX - 1 by Y SampleY .. Y SampleY +
--  SampleY - 1, cut at the image's border. Expand gives W ExpansionX x H
--  ExpansionY pixels: output pixel (X, Y) is input pixel (X / ExpansionX,
--  Y / ExpansionY) (integer division).
--
--  GreyMorphologyNxM: Erode gives the minimum over the rectangle, Dilate
--  the maximum (each computed with the van Herk / Gil-Werman running
--  extrema, three comparisons per pixel and direction whatever the size),
--  Open = Dilate (Erode), Close = Erode (Dilate), DilateMinusErode,
--  CloseMinusOriginal and OriginalMinusOpen the differences (never
--  negative). The medians use a running histogram (Huang): the cost per
--  pixel grows with KernelHeight, not with the area.
--
--  Convolutions apply the kernel as written (a correlation: kernel cell
--  (Col, Row) multiplies the pixel Col - OX, Row - OY away, (OX, OY) being
--  the origin cell); the sum is rounded and limited to 0 .. 255.
--
--  Region. Execute takes a pixel region handle of AMV.Kernels.Regions
--  (the Ada API passes ks_pixel_region_whole_image for an empty Region):
--  each operator computes its result for the pixels the region contains
--  and copies the other pixels unchanged, so that pixels outside the
--  region keep their input values through the whole list. A null region
--  (the empty region) gives an unchanged copy of the image. Equalize uses
--  the histogram of the region's pixels.
--
--  FlipRotate. VisionPro's OperationInPixelSpace codes: 0 None, 1
--  Rotate90Deg, 2 Rotate180Deg, 3 Rotate270Deg (quarter turns clockwise
--  as the image is displayed, y down), 4 Flip (left-right mirror), 5
--  FlipAndRotate90Deg, 6 FlipAndRotate180Deg (top-bottom mirror), 7
--  FlipAndRotate270Deg (a transpose): the mirror first, then the turn.
--  Rotate90Deg, Rotate270Deg, 5 and 7 swap Width and Height.
--
--  PelSet (AMV's meaning of the mask, as for the other tools' masks).
--  The mask is an 8-bit image given with the operator list (Execute_Masked:
--  the mask of the operator at index I is Masks (I); the masks of other
--  operators are ignored). Mask pixel (U, V) lies over pixel (U +
--  InputImageMaskOffsetX, V + InputImageMaskOffsetY) of the image the
--  operator receives; a mask pixel of value 0 marks that pixel "don't
--  care", any other value, and every pixel no mask pixel lies over,
--  "care". The mask may have any size. An enabled PelSet needs a mask
--  (Bad_Parameter "Operators(I).InputImageMask is not set" otherwise; so
--  Execute, which passes no masks, rejects it).
--
--  Operators that change the pixel grid: an enabled FlipRotate other than
--  None, SubSampler or Expand with a factor above 1 along x or y, and
--  GaussSampler with SampleX or SampleY above 1 (Is_Geometric). They work
--  on the whole image: a list holding one needs a region that contains
--  every pixel of the image (Bad_Parameter naming Region otherwise), and
--  then every operator of the list works on the whole image. Every image
--  of the list (after each operator) must have at most Max_Pixels pixels
--  (Bad_Parameter naming the operator otherwise, before any pixel is
--  computed). Execute returns Output_From_Input, the transform from the
--  input image's pixel coordinates to the output image's (the identity
--  when the pixel grid is unchanged): an output pixel's centre stands for
--  the input point it was taken from (SubSampler: the centre of the pixel
--  it copies, or of the block it averages; Expand: the input pixel's
--  centre is the centre of its ExpansionX x ExpansionY block). The Ada
--  API composes it with the input's Pixel_From_Root transform so that
--  root coordinates keep their physical meaning in the output image.
--
--  Not offered (VisionPro classes): CogIPOneImageGreyMorphology (3 x 3
--  elements), CogIPOneImageSampleConvolve, CogIPOneImageMissingPixel;
--  the image masks of the operators other than PelSet, the
--  non-flat kernel of CogIPOneImageGreyMorphologyNxM (KernelEnabled) and
--  the Clipped boundary mode.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any image or
--  region handle that is null or came from the kernels, any operator list
--  (codes, sizes and reals checked first, non-finite values included); no
--  memory leaks; Gold: the output's Width and Height are those that
--  Size_After computes from the input's (quarter turns swap them,
--  SubSampler and GaussSampler's sampling divide them rounding up, Expand
--  multiplies them); for a list that does not change the pixel grid every
--  output pixel outside the region equals the input pixel and
--  Output_From_Input is the identity; and, for each operator: Threshold
--  gives exactly HighValue or LowValue by its rule, AddSubtractConstant,
--  MultiplyConstant and the convolutions give their sums limited to
--  0 .. 255 (Bounded) or modulo 256 (Wrap), Erode never raises and Dilate
--  never lowers a pixel, FlipRotate moves every pixel exactly where its
--  code says, Expand and SubSampler without SpatialAverage copy every
--  pixel from exactly where their definitions say, PelSet sets exactly
--  the pixels its mask and Operation select (Sets_Pixel).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Images;
with AMV.Kernels.Pixel_Map;
with AMV.Kernels.Regions;
with AMV.Kernels.Transforms;

package AMV.Kernels.IP_One_Image with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;
   package KT renames AMV.Kernels.Transforms;
   package KP renames AMV.Kernels.Pixel_Map;

   use type KI.Grey_8;
   use type KI.Ks_Image_8_Grey;
   use type KT.Ks_Transform_2D_Linear;
   use type KR.Flag_Matrix_Access;

   ---------------------------------------------------------------------
   --  Codes (C: KS_IP_ONE_IMAGE_*)
   ---------------------------------------------------------------------

   --  Operator kinds.
   Kind_Add_Subtract_Constant : constant Int32 := 0;
   Kind_Convolve_3x3          : constant Int32 := 1;
   Kind_Convolve_NxM          : constant Int32 := 2;
   Kind_Equalize              : constant Int32 := 3;
   Kind_Flip_Rotate           : constant Int32 := 4;
   Kind_Gauss_Sampler         : constant Int32 := 5;
   Kind_Grey_Morphology_NxM   : constant Int32 := 6;
   Kind_Median_3x3            : constant Int32 := 7;
   Kind_Median_NxM            : constant Int32 := 8;
   Kind_Multiply_Constant     : constant Int32 := 9;
   Kind_Pixel_Map             : constant Int32 := 10;
   Kind_Quantize              : constant Int32 := 11;
   Kind_Box_Filter            : constant Int32 := 12;
   Kind_Threshold             : constant Int32 := 13;
   Kind_Unsharp_Mask          : constant Int32 := 14;
   Kind_Expand                : constant Int32 := 15;
   Kind_High_Pass_Filter      : constant Int32 := 16;
   Kind_Sub_Sampler           : constant Int32 := 17;
   Kind_Pel_Set               : constant Int32 := 18;

   subtype Operator_Kind is Int32
     range Kind_Add_Subtract_Constant .. Kind_Pel_Set;

   --  CogIPOneImageAddSubtractConstantOverflowModeConstants and
   --  CogIPOneImageMultiplyConstantOverflowModeConstants.
   Overflow_Mode_Bounded : constant Int32 := 0;
   Overflow_Mode_Wrap    : constant Int32 := 1;

   --  CogIPOneImageBoundaryModeConstants (only Reflected is supported).
   Boundary_Mode_Clipped   : constant Int32 := 1;
   Boundary_Mode_Reflected : constant Int32 := 2;

   --  CogIPOneImageConvolve3x3PositionConstants: the cells of a 3 x 3
   --  kernel, row by row (also their index in the kernel array).
   Position_North_West : constant Int32 := 0;
   Position_North      : constant Int32 := 1;
   Position_North_East : constant Int32 := 2;
   Position_West       : constant Int32 := 3;
   Position_Center     : constant Int32 := 4;
   Position_East       : constant Int32 := 5;
   Position_South_West : constant Int32 := 6;
   Position_South      : constant Int32 := 7;
   Position_South_East : constant Int32 := 8;

   --  CogIPOneImageFlipRotateOperationConstants.
   Flip_Rotate_None                    : constant Int32 := 0;
   Flip_Rotate_Rotate_90_Deg           : constant Int32 := 1;
   Flip_Rotate_Rotate_180_Deg          : constant Int32 := 2;
   Flip_Rotate_Rotate_270_Deg          : constant Int32 := 3;
   Flip_Rotate_Flip                    : constant Int32 := 4;
   Flip_Rotate_Flip_And_Rotate_90_Deg  : constant Int32 := 5;
   Flip_Rotate_Flip_And_Rotate_180_Deg : constant Int32 := 6;
   Flip_Rotate_Flip_And_Rotate_270_Deg : constant Int32 := 7;

   subtype Flip_Rotate_Code is Int32
     range Flip_Rotate_None .. Flip_Rotate_Flip_And_Rotate_270_Deg;

   --  CogIPOneImageMorphologyOperationConstants.
   Morphology_Erode                : constant Int32 := 1;
   Morphology_Dilate               : constant Int32 := 2;
   Morphology_Open                 : constant Int32 := 3;
   Morphology_Close                : constant Int32 := 4;
   Morphology_Dilate_Minus_Erode   : constant Int32 := 5;
   Morphology_Close_Minus_Original : constant Int32 := 6;
   Morphology_Original_Minus_Open  : constant Int32 := 7;

   subtype Morphology_Code is Int32
     range Morphology_Erode .. Morphology_Original_Minus_Open;

   --  CogIPOneImageQuantizeLevelConstants (s2 .. s128): 2**(code + 1)
   --  grey levels.
   Quantize_Level_S2   : constant Int32 := 0;
   Quantize_Level_S128 : constant Int32 := 6;

   --  CogIPOneImageHighPassFilterProcessingModeConstants.
   High_Pass_Gauss  : constant Int32 := 0;
   High_Pass_Mean   : constant Int32 := 1;
   High_Pass_Median : constant Int32 := 2;

   --  CogIPOneImagePelSetOperationConstants.
   Pel_Set_Care_Pels      : constant Int32 := 1;
   Pel_Set_Dont_Care_Pels : constant Int32 := 2;

   ---------------------------------------------------------------------
   --  Limits (C: KS_IP_ONE_IMAGE_MAX_*)
   ---------------------------------------------------------------------

   Max_Operators       : constant := 16;
   --  The capacity of an operator list.
   Max_Kernel_Size     : constant := 1001;
   --  The largest KernelWidth / KernelHeight of the morphology, the
   --  median and the box filter.
   Max_Convolve_Size   : constant := 15;
   --  The largest KernelWidth / KernelHeight of ConvolveNxM.
   Max_Convolve_Values : constant := Max_Convolve_Size * Max_Convolve_Size;
   --  The kernel array of ConvolveNxM: cell (Col, Row) is at index
   --  Row * Max_Convolve_Size + Col, whatever the kernel's size.
   Max_Kernel_Value    : constant := 1.0E6;
   --  The largest magnitude of a convolution kernel value.
   Max_Smoothness      : constant := 24;
   --  The largest SmoothnessX / SmoothnessY.
   Max_Magnitude_Shift : constant := 7;
   --  MagnitudeShift lies in -7 .. 7 (as in VisionPro).
   Max_Multiply_Value  : constant := 1.0E6;
   --  The largest ConstantValue of MultiplyConstant.
   Max_Amount          : constant := 1000.0;
   --  The largest Amount of UnsharpMask.
   Max_Sample          : constant := 256;
   --  The largest SampleX / SampleY (SubSampler, GaussSampler) and
   --  ExpansionX / ExpansionY (Expand).

   ---------------------------------------------------------------------
   --  Operator records (C: ks_ip_one_image_*)
   ---------------------------------------------------------------------

   type Ks_IP_One_Image_Add_Subtract_Constant is record
      Constant_Value : Int32 := 0;
      Overflow_Mode  : Int32 := Overflow_Mode_Bounded;
   end record
     with Convention => C;
   --  CogIPOneImageAddSubtractConstant. Any ConstantValue is accepted.

   type Convolve_3x3_Kernel is array (0 .. 8) of Long_Float
     with Convention => C;
   --  The nine values by position code.

   Identity_3x3 : constant Convolve_3x3_Kernel :=
     [4 => 1.0, others => 0.0];

   type Ks_IP_One_Image_Convolve_3x3 is record
      Kernel_Origin : Int32 := Position_Center;
      Kernel        : Convolve_3x3_Kernel := Identity_3x3;
   end record
     with Convention => C;
   --  CogIPOneImageConvolve3x3 (GetKernel / SetKernel: the array;
   --  GetKernelValue / SetKernelValue: one position). The default kernel
   --  copies the image.

   type Convolve_NxM_Kernel is
     array (0 .. Max_Convolve_Values - 1) of Long_Float
     with Convention => C;

   Identity_NxM : constant Convolve_NxM_Kernel :=
     [Max_Convolve_Size + 1 => 1.0, others => 0.0];
   --  1 at cell (1, 1), the centre of the default 3 x 3 kernel.

   type Ks_IP_One_Image_Convolve_NxM is record
      Kernel_Width  : Int32 := 3;
      Kernel_Height : Int32 := 3;
      Boundary_Mode : Int32 := Boundary_Mode_Reflected;
      Kernel        : Convolve_NxM_Kernel := Identity_NxM;
   end record
     with Convention => C;
   --  CogIPOneImageConvolveNxM (GetKernelValue / SetKernelValue (Col,
   --  Row)). The default 3 x 3 kernel copies the image.

   type Ks_IP_One_Image_Flip_Rotate is record
      Operation_In_Pixel_Space : Int32 := Flip_Rotate_None;
   end record
     with Convention => C;
   --  CogIPOneImageFlipRotate.

   type Ks_IP_One_Image_Gauss_Sampler is record
      Smoothness_X    : Int32 := 2;
      Smoothness_Y    : Int32 := 2;
      Magnitude_Shift : Int32 := 0;
      Sample_X        : Int32 := 1;
      Sample_Y        : Int32 := 1;
   end record
     with Convention => C;
   --  CogIPOneImageGaussSampler (SampleX, SampleY in 1 .. Max_Sample).

   type Ks_IP_One_Image_Grey_Morphology_NxM is record
      Operation     : Int32 := Morphology_Erode;
      Kernel_Width  : Int32 := 3;
      Kernel_Height : Int32 := 3;
   end record
     with Convention => C;
   --  CogIPOneImageGreyMorphologyNxM (a flat element: KernelEnabled is
   --  not offered).

   type Ks_IP_One_Image_Median_NxM is record
      Kernel_Width  : Int32 := 3;
      Kernel_Height : Int32 := 3;
   end record
     with Convention => C;
   --  CogIPOneImageMedianNxM.

   type Ks_IP_One_Image_Multiply_Constant is record
      Constant_Value : Long_Float := 1.0;
      Overflow_Mode  : Int32 := Overflow_Mode_Bounded;
   end record
     with Convention => C;
   --  CogIPOneImageMultiplyConstant.

   type Ks_IP_One_Image_Quantize is record
      Levels : Int32 := Quantize_Level_S2;
   end record
     with Convention => C;
   --  CogIPOneImageQuantize.

   type Ks_IP_One_Image_Box_Filter is record
      Kernel_Width  : Int32 := 3;
      Kernel_Height : Int32 := 3;
   end record
     with Convention => C;
   --  (AMV name) The mean filter.

   type Ks_IP_One_Image_Threshold is record
      Threshold  : Int32 := 128;
      Low_Value  : Int32 := 0;
      High_Value : Int32 := 255;
   end record
     with Convention => C;
   --  (AMV name) HighValue where the value is >= Threshold (0 .. 256),
   --  LowValue elsewhere; swap the two for the opposite polarity.

   type Ks_IP_One_Image_Unsharp_Mask is record
      Amount       : Long_Float := 1.0;
      Smoothness_X : Int32 := 2;
      Smoothness_Y : Int32 := 2;
   end record
     with Convention => C;
   --  (AMV name) Sharpening by the difference from a smoothed image.

   type Ks_IP_One_Image_Expand is record
      Expansion_X : Int32 := 2;
      Expansion_Y : Int32 := 2;
   end record
     with Convention => C;
   --  CogIPOneImageExpand (1 .. Max_Sample each; AMV defaults).

   type Ks_IP_One_Image_High_Pass_Filter is record
      Processing_Mode : Int32 := High_Pass_Gauss;
      Smoothness_X    : Int32 := 2;
      Smoothness_Y    : Int32 := 2;
      Kernel_Width    : Int32 := 3;
      Kernel_Height   : Int32 := 3;
   end record
     with Convention => C;
   --  CogIPOneImageHighPassFilter (SigmaX and SigmaY, read only, follow
   --  from the smoothness; AMV defaults). Gauss uses the smoothness, Mean
   --  and Median the kernel's size (odd, 1 .. Max_Kernel_Size); all five
   --  are checked whatever the mode.

   type Ks_IP_One_Image_Sub_Sampler is record
      Sample_X        : Int32 := 2;
      Sample_Y        : Int32 := 2;
      Spatial_Average : Int32 := False_Value;
   end record
     with Convention => C;
   --  CogIPOneImageSubSampler (1 .. Max_Sample each; AMV defaults).

   type Ks_IP_One_Image_Pel_Set is record
      Operation                 : Int32 := Pel_Set_Care_Pels;
      Pel_Value                 : Int32 := 0;
      Input_Image_Mask_Offset_X : Int32 := 0;
      Input_Image_Mask_Offset_Y : Int32 := 0;
   end record
     with Convention => C;
   --  CogIPOneImagePelSet without its InputImageMask, which is passed with
   --  the list (Execute_Masked). Operation SetCarePels or SetDontCarePels,
   --  PelValue in 0 .. 255, any offsets (AMV defaults).

   type Ks_IP_One_Image_Operator is record
      Kind                  : Int32 := Kind_Add_Subtract_Constant;
      Enabled               : Int32 := True_Value;
      Add_Subtract_Constant : Ks_IP_One_Image_Add_Subtract_Constant;
      Convolve_3x3          : Ks_IP_One_Image_Convolve_3x3;
      Convolve_NxM          : Ks_IP_One_Image_Convolve_NxM;
      Flip_Rotate           : Ks_IP_One_Image_Flip_Rotate;
      Gauss_Sampler         : Ks_IP_One_Image_Gauss_Sampler;
      Grey_Morphology_NxM   : Ks_IP_One_Image_Grey_Morphology_NxM;
      Median_NxM            : Ks_IP_One_Image_Median_NxM;
      Multiply_Constant     : Ks_IP_One_Image_Multiply_Constant;
      Pixel_Map             : KP.Ks_IP_One_Image_Pixel_Map;
      Quantize              : Ks_IP_One_Image_Quantize;
      Box_Filter            : Ks_IP_One_Image_Box_Filter;
      Threshold             : Ks_IP_One_Image_Threshold;
      Unsharp_Mask          : Ks_IP_One_Image_Unsharp_Mask;
      Expand                : Ks_IP_One_Image_Expand;
      High_Pass_Filter      : Ks_IP_One_Image_High_Pass_Filter;
      Sub_Sampler           : Ks_IP_One_Image_Sub_Sampler;
      Pel_Set               : Ks_IP_One_Image_Pel_Set;
   end record
     with Convention => C;
   --  C: ks_ip_one_image_operator (ICogIPOneImageOperator). The default
   --  record is an enabled AddSubtractConstant of 0 (which changes
   --  nothing); every component holds the defaults of its class.

   type Operator_Array is
     array (0 .. Max_Operators - 1) of Ks_IP_One_Image_Operator
     with Convention => C;

   type Ks_IP_One_Image_Operators is record
      Count : Int32 := 0;
      Items : Operator_Array;
   end record
     with Convention => C;
   --  C: ks_ip_one_image_operators (CogIPOneImageOperators): Items (0 ..
   --  Count - 1), applied in that order.

   ---------------------------------------------------------------------
   --  What the checks establish
   ---------------------------------------------------------------------

   function Odd_Size (Size : Int32; Limit : Int32) return Boolean is
     (Size >= 1 and then Size <= Limit and then Size mod 2 = 1);
   --  An odd kernel size in 1 .. Limit.

   function Valid_Operator (Op : Ks_IP_One_Image_Operator) return Boolean
   is
     (Op.Kind in Operator_Kind
      and then Op.Enabled in False_Value | True_Value
      and then
        (case Op.Kind is
            when Kind_Add_Subtract_Constant =>
              Op.Add_Subtract_Constant.Overflow_Mode
                in Overflow_Mode_Bounded | Overflow_Mode_Wrap,
            when Kind_Convolve_3x3 =>
              Op.Convolve_3x3.Kernel_Origin
                in Position_North_West .. Position_South_East,
            when Kind_Convolve_NxM =>
              Odd_Size (Op.Convolve_NxM.Kernel_Width, Max_Convolve_Size)
              and then Odd_Size (Op.Convolve_NxM.Kernel_Height,
                                 Max_Convolve_Size)
              and then Op.Convolve_NxM.Boundary_Mode
                         = Boundary_Mode_Reflected,
            when Kind_Equalize | Kind_Median_3x3 | Kind_Pixel_Map => True,
            when Kind_Flip_Rotate =>
              Op.Flip_Rotate.Operation_In_Pixel_Space in Flip_Rotate_Code,
            when Kind_Gauss_Sampler =>
              Op.Gauss_Sampler.Smoothness_X in 0 .. Max_Smoothness
              and then Op.Gauss_Sampler.Smoothness_Y in 0 .. Max_Smoothness
              and then Op.Gauss_Sampler.Magnitude_Shift
                         in -Max_Magnitude_Shift .. Max_Magnitude_Shift
              and then Op.Gauss_Sampler.Sample_X in 1 .. Max_Sample
              and then Op.Gauss_Sampler.Sample_Y in 1 .. Max_Sample,
            when Kind_Grey_Morphology_NxM =>
              Op.Grey_Morphology_NxM.Operation in Morphology_Code
              and then Odd_Size (Op.Grey_Morphology_NxM.Kernel_Width,
                                 Max_Kernel_Size)
              and then Odd_Size (Op.Grey_Morphology_NxM.Kernel_Height,
                                 Max_Kernel_Size),
            when Kind_Median_NxM =>
              Odd_Size (Op.Median_NxM.Kernel_Width, Max_Kernel_Size)
              and then Odd_Size (Op.Median_NxM.Kernel_Height,
                                 Max_Kernel_Size),
            when Kind_Multiply_Constant =>
              Op.Multiply_Constant.Constant_Value >= 0.0
              and then Op.Multiply_Constant.Constant_Value
                         <= Max_Multiply_Value
              and then Op.Multiply_Constant.Overflow_Mode
                         in Overflow_Mode_Bounded | Overflow_Mode_Wrap,
            when Kind_Quantize =>
              Op.Quantize.Levels in Quantize_Level_S2 .. Quantize_Level_S128,
            when Kind_Box_Filter =>
              Odd_Size (Op.Box_Filter.Kernel_Width, Max_Kernel_Size)
              and then Odd_Size (Op.Box_Filter.Kernel_Height,
                                 Max_Kernel_Size),
            when Kind_Threshold =>
              Op.Threshold.Threshold in 0 .. 256
              and then Op.Threshold.Low_Value in 0 .. 255
              and then Op.Threshold.High_Value in 0 .. 255,
            when Kind_Unsharp_Mask =>
              Op.Unsharp_Mask.Amount >= 0.0
              and then Op.Unsharp_Mask.Amount <= Max_Amount
              and then Op.Unsharp_Mask.Smoothness_X in 0 .. Max_Smoothness
              and then Op.Unsharp_Mask.Smoothness_Y in 0 .. Max_Smoothness,
            when Kind_Expand =>
              Op.Expand.Expansion_X in 1 .. Max_Sample
              and then Op.Expand.Expansion_Y in 1 .. Max_Sample,
            when Kind_High_Pass_Filter =>
              Op.High_Pass_Filter.Processing_Mode
                in High_Pass_Gauss .. High_Pass_Median
              and then Op.High_Pass_Filter.Smoothness_X
                         in 0 .. Max_Smoothness
              and then Op.High_Pass_Filter.Smoothness_Y
                         in 0 .. Max_Smoothness
              and then Odd_Size (Op.High_Pass_Filter.Kernel_Width,
                                 Max_Kernel_Size)
              and then Odd_Size (Op.High_Pass_Filter.Kernel_Height,
                                 Max_Kernel_Size),
            when Kind_Sub_Sampler =>
              Op.Sub_Sampler.Sample_X in 1 .. Max_Sample
              and then Op.Sub_Sampler.Sample_Y in 1 .. Max_Sample
              and then Op.Sub_Sampler.Spatial_Average
                         in False_Value | True_Value,
            when Kind_Pel_Set =>
              Op.Pel_Set.Operation
                in Pel_Set_Care_Pels | Pel_Set_Dont_Care_Pels
              and then Op.Pel_Set.Pel_Value in 0 .. 255,
            when others => False));
   --  The checks of one operator that its code relies on (the kernel
   --  values of the convolutions are checked too, but read through a
   --  limit, so no fact about them is needed).

   function Valid_Operators (Ops : Ks_IP_One_Image_Operators) return Boolean
   is
     (Ops.Count in 0 .. Max_Operators
      and then (for all I in 0 .. Integer (Ops.Count) - 1 =>
                  Valid_Operator (Ops.Items (I))));

   type Mask_Ref is access constant KI.Ks_Image_8_Grey_Data
     with Convention => C;
   --  C: const ks_image_8_grey *. A mask handle the caller keeps.

   type Operator_Masks is array (0 .. Max_Operators - 1) of Mask_Ref
     with Convention => C;
   --  The InputImageMask of each operator of a list, by index (C: an array
   --  of KS_IP_ONE_IMAGE_MAX_OPERATORS handles); null for none.

   No_Masks : constant Operator_Masks := [others => null];

   function Needs_Mask (Op : Ks_IP_One_Image_Operator) return Boolean is
     (Op.Kind = Kind_Pel_Set and then Op.Enabled = True_Value);
   --  An operator that reads its InputImageMask.

   function Masks_Given
     (Ops   : Ks_IP_One_Image_Operators;
      Masks : Operator_Masks) return Boolean
   is
     (for all I in 0 .. Integer (Ops.Count) - 1 =>
        (if Needs_Mask (Ops.Items (I))
         then KI.Valid_Image (Masks (I))))
   with Pre => Ops.Count in 0 .. Max_Operators;
   --  Every operator that needs a mask has one.

   function Cared
     (Mask   : access constant KI.Ks_Image_8_Grey_Data;
      OX, OY : Int32;
      X, Y   : Natural) return Boolean
   is
     (if Int64 (X) - Int64 (OX) in 0 .. Int64 (Mask.Width) - 1
         and then Int64 (Y) - Int64 (OY) in 0 .. Int64 (Mask.Height) - 1
      then Mask.Pixels (Natural (Int64 (Y) - Int64 (OY)),
                        Natural (Int64 (X) - Int64 (OX))) /= 0
      else True)
   with Pre => KI.Valid_Image (Mask);
   --  Pixel (X, Y) is "care" under the mask placed at offset (OX, OY).

   function Sets_Pixel
     (Params : Ks_IP_One_Image_Pel_Set;
      Mask   : access constant KI.Ks_Image_8_Grey_Data;
      X, Y   : Natural) return Boolean
   is
     (Cared (Mask, Params.Input_Image_Mask_Offset_X,
             Params.Input_Image_Mask_Offset_Y, X, Y)
        = (Params.Operation = Pel_Set_Care_Pels))
   with Pre => KI.Valid_Image (Mask);
   --  PelSet writes PelValue into pixel (X, Y) (when the region selects
   --  it).

   function Is_Geometric (Op : Ks_IP_One_Image_Operator) return Boolean is
     (Op.Enabled = True_Value
      and then
        (case Op.Kind is
            when Kind_Flip_Rotate =>
              Op.Flip_Rotate.Operation_In_Pixel_Space /= Flip_Rotate_None,
            when Kind_Gauss_Sampler =>
              Op.Gauss_Sampler.Sample_X /= 1
              or else Op.Gauss_Sampler.Sample_Y /= 1,
            when Kind_Expand =>
              Op.Expand.Expansion_X /= 1 or else Op.Expand.Expansion_Y /= 1,
            when Kind_Sub_Sampler =>
              Op.Sub_Sampler.Sample_X /= 1
              or else Op.Sub_Sampler.Sample_Y /= 1,
            when others => False));
   --  An operator that changes the pixel grid.

   function Transposes (Op : Ks_IP_One_Image_Operator) return Boolean is
     (Op.Kind = Kind_Flip_Rotate and then Is_Geometric (Op)
      and then Op.Flip_Rotate.Operation_In_Pixel_Space
                 in Flip_Rotate_Rotate_90_Deg | Flip_Rotate_Rotate_270_Deg
                  | Flip_Rotate_Flip_And_Rotate_90_Deg
                  | Flip_Rotate_Flip_And_Rotate_270_Deg);
   --  An operator that swaps Width and Height.

   function Has_Geometric (Ops : Ks_IP_One_Image_Operators) return Boolean
   is
     (for some I in 0 .. Integer (Ops.Count) - 1 =>
        Is_Geometric (Ops.Items (I)))
   with Pre => Ops.Count in 0 .. Max_Operators;
   --  The list changes the pixel grid (it then needs the whole image).

   Size_Limit : constant := 2**40;
   --  Sizes in Image_Size stop growing at this bound (far above any image
   --  size the kernels accept, so that a list whose sizes reach it is
   --  rejected).

   subtype Size_Value is Int64 range 1 .. Size_Limit;

   type Image_Size is record
      Width  : Size_Value := 1;
      Height : Size_Value := 1;
   end record;
   --  The size of an image of the list.

   function Shrunk (N : Size_Value; Factor : Int32) return Size_Value is
     ((N + Int64 (Factor) - 1) / Int64 (Factor))
   with Pre => Factor in 1 .. Max_Sample;
   --  Ceiling (N / Factor): the pixels kept by a sampling.

   function Grown (N : Size_Value; Factor : Int32) return Size_Value is
     (Int64'Min (N * Int64 (Factor), Size_Limit))
   with Pre => Factor in 1 .. Max_Sample;
   --  N Factor (limited to Size_Limit): the pixels of an expansion.

   function Step_Size
     (Op : Ks_IP_One_Image_Operator; S : Image_Size) return Image_Size
   is
     (if Op.Enabled /= True_Value then S
      else
        (case Op.Kind is
            when Kind_Flip_Rotate =>
              (if Transposes (Op) then (S.Height, S.Width) else S),
            when Kind_Gauss_Sampler =>
              (Shrunk (S.Width, Op.Gauss_Sampler.Sample_X),
               Shrunk (S.Height, Op.Gauss_Sampler.Sample_Y)),
            when Kind_Expand =>
              (Grown (S.Width, Op.Expand.Expansion_X),
               Grown (S.Height, Op.Expand.Expansion_Y)),
            when Kind_Sub_Sampler =>
              (Shrunk (S.Width, Op.Sub_Sampler.Sample_X),
               Shrunk (S.Height, Op.Sub_Sampler.Sample_Y)),
            when others => S))
   with Pre => Valid_Operator (Op);
   --  The size of the image Op makes from an image of size S.

   function Size_After
     (Ops : Ks_IP_One_Image_Operators;
      N   : Int32;
      S   : Image_Size) return Image_Size
   is
     (if N <= 0 then S
      else Step_Size (Ops.Items (Integer (N - 1)), Size_After (Ops, N - 1, S)))
   with
     Pre => Valid_Operators (Ops) and then N in 0 .. Ops.Count,
     Subprogram_Variant => (Decreases => N);
   --  The size of the image after the first N operators of the list.

   function Fits (S : Image_Size) return Boolean is
     (S.Width <= KI.Max_Pixels and then S.Height <= KI.Max_Pixels
      and then S.Width * S.Height <= KI.Max_Pixels);
   --  An image of that size is within the size limit of the kernels.

   function Size_Of
     (Image : access constant KI.Ks_Image_8_Grey_Data) return Image_Size
   is
     ((Int64 (Image.Width), Int64 (Image.Height)))
   with Pre => KI.Valid_Image (Image);
   --  The size of an image.

   ---------------------------------------------------------------------
   --  Entry points: operators and the operator list
   ---------------------------------------------------------------------

   procedure Operators_Default (Operators : out Ks_IP_One_Image_Operators)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_operators_default",
     Post => Operators.Count = 0;
   --  An empty list (every item the default record). Cannot fail.

   procedure Operator_Default
     (Kind     : Int32;
      Operator : out Ks_IP_One_Image_Operator;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_operator_default",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Operator.Kind = Kind
                            and then Operator.Enabled = True_Value
                            and then Valid_Operator (Operator));
   --  A new enabled operator of the given kind with the defaults of its
   --  class (the constructor of the class). Bad_Parameter for an unknown
   --  kind, Operator then being the default record.

   procedure Operators_Item
     (Operators : Ks_IP_One_Image_Operators;
      Index     : Int32;
      Operator  : out Ks_IP_One_Image_Operator;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_operators_item",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Operators.Count in 1 .. Max_Operators
                            and then Index in 0 .. Operators.Count - 1
                            and then Operator
                                       = Operators.Items (Integer (Index)));
   --  Item (get): a copy of Items (Index). Index_Out_Of_Range unless Index
   --  is in 0 .. Count - 1; Bad_Parameter when Count is not in 0 ..
   --  Max_Operators.

   procedure Operators_Set_Item
     (Operators : in out Ks_IP_One_Image_Operators;
      Index     : Int32;
      Operator  : Ks_IP_One_Image_Operator;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_operators_set_item",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Operators.Count = Operators.Count'Old
                            and then Index in 0 .. Operators.Count - 1
                            and then Operators.Items (Integer (Index))
                                       = Operator
                            and then
                              (for all J in Operator_Array'Range =>
                                 (if J /= Integer (Index)
                                  then Operators.Items (J)
                                         = Operators.Items'Old (J)))
                       else Operators = Operators'Old);
   --  Item (set): replaces Items (Index); the same failures.

   procedure Operators_Add
     (Operators : in out Ks_IP_One_Image_Operators;
      Operator  : Ks_IP_One_Image_Operator;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_operators_add",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Operators.Count = Operators.Count'Old + 1
                            and then Operators.Count in 1 .. Max_Operators
                            and then Operators.Items
                                       (Integer (Operators.Count) - 1)
                                       = Operator
                            and then
                              (for all J in 0 .. Integer (Operators.Count) - 2
                               => Operators.Items (J)
                                    = Operators.Items'Old (J))
                       else Operators = Operators'Old);
   --  Add: appends Operator. Bad_Parameter when the list is full
   --  (Max_Operators) or its Count is not in 0 .. Max_Operators.

   procedure Operators_Insert
     (Operators : in out Ks_IP_One_Image_Operators;
      Operator  : Ks_IP_One_Image_Operator;
      Index     : Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_operators_insert",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Operators.Count = Operators.Count'Old + 1
                            and then Operators.Count in 1 .. Max_Operators
                            and then Index in 0 .. Operators.Count - 1
                            and then Operators.Items (Integer (Index))
                                       = Operator
                            and then
                              (for all J in 0 .. Integer (Index) - 1 =>
                                 Operators.Items (J)
                                   = Operators.Items'Old (J))
                            and then
                              (for all J in Integer (Index) + 1
                                            .. Integer (Operators.Count) - 1
                               => Operators.Items (J)
                                    = Operators.Items'Old (J - 1))
                       else Operators = Operators'Old);
   --  Insert (value, index): puts Operator at Index, moving the items from
   --  Index on up by one. Index_Out_Of_Range unless Index is in 0 ..
   --  Count; Bad_Parameter when the list is full or Count is not valid.

   procedure Operators_Remove_At
     (Operators : in out Ks_IP_One_Image_Operators;
      Index     : Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_operators_remove_at",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Operators.Count = Operators.Count'Old - 1
                            and then Operators.Count in 0 .. Max_Operators - 1
                            and then Index in 0 .. Operators.Count
                            and then
                              (for all J in 0 .. Integer (Index) - 1 =>
                                 Operators.Items (J)
                                   = Operators.Items'Old (J))
                            and then
                              (for all J in Integer (Index)
                                            .. Integer (Operators.Count) - 1
                               => Operators.Items (J)
                                    = Operators.Items'Old (J + 1))
                       else Operators = Operators'Old);
   --  RemoveAt: removes Items (Index), moving the later items down by one.
   --  Index_Out_Of_Range unless Index is in 0 .. Count - 1; Bad_Parameter
   --  when Count is not valid.

   procedure Operators_Move
     (Operators  : in out Ks_IP_One_Image_Operators;
      From_Index : Int32;
      To_Index   : Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_operators_move",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Operators.Count = Operators.Count'Old
                            and then Operators.Count in 1 .. Max_Operators
                            and then From_Index in 0 .. Operators.Count - 1
                            and then To_Index in 0 .. Operators.Count - 1
                            and then Operators.Items (Integer (To_Index))
                                       = Operators.Items'Old
                                           (Integer (From_Index))
                       else Operators = Operators'Old);
   --  Move: the item at From_Index moves to To_Index, the items between
   --  them shifting by one place. Index_Out_Of_Range unless both indices
   --  are in 0 .. Count - 1; Bad_Parameter when Count is not valid.

   procedure Operators_Count
     (Operators : Ks_IP_One_Image_Operators;
      Count     : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_operators_count",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Count = Operators.Count
                            and then Count in 0 .. Max_Operators
                       else Count = 0);
   --  Count: Operators.Count. Bad_Parameter when it is not in
   --  0 .. Max_Operators (a list whose Count was set by hand).

   procedure Operator_Get_Kind
     (Operator : Ks_IP_One_Image_Operator;
      Kind     : out Int32;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_operator_get_kind",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Kind = Operator.Kind
                            and then Kind in Operator_Kind
                       else Kind = Kind_Add_Subtract_Constant);
   --  Operator.Kind. Bad_Parameter when it is not the code of a kind (a
   --  record changed by hand).

   procedure Operator_Get_Enabled
     (Operator : Ks_IP_One_Image_Operator;
      Enabled  : out Int32;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_operator_get_enabled",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Enabled = Operator.Enabled
                            and then Enabled in False_Value | True_Value
                       else Enabled = False_Value);
   --  Operator.Enabled. Bad_Parameter when it is not 0 or 1.

   procedure Convolve_NxM_Get_Kernel_Value
     (Params : Ks_IP_One_Image_Convolve_NxM;
      Col    : Int32;
      Row    : Int32;
      Value  : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_convolve_nxm_get_kernel_value",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Col in 0 .. Max_Convolve_Size - 1
                            and then Row in 0 .. Max_Convolve_Size - 1
                            and then Value
                                       = Params.Kernel
                                           (Integer (Row) * Max_Convolve_Size
                                            + Integer (Col))
                       else Value = 0.0);
   --  GetKernelValue (Col, Row). Bad_Parameter unless 0 <= Col <
   --  KernelWidth and 0 <= Row < KernelHeight, with sizes in 1 ..
   --  Max_Convolve_Size (as VisionPro's ArgumentException).

   procedure Convolve_NxM_Set_Kernel_Value
     (Params    : in out Ks_IP_One_Image_Convolve_NxM;
      Col       : Int32;
      Row       : Int32;
      New_Value : Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_convolve_nxm_set_kernel_value",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Col in 0 .. Max_Convolve_Size - 1
                            and then Row in 0 .. Max_Convolve_Size - 1
                            and then Params.Kernel
                                       (Integer (Row) * Max_Convolve_Size
                                        + Integer (Col)) = New_Value
                            and then Params.Kernel_Width
                                       = Params.Kernel_Width'Old
                            and then Params.Kernel_Height
                                       = Params.Kernel_Height'Old
                            and then Params.Boundary_Mode
                                       = Params.Boundary_Mode'Old
                       else Params = Params'Old);
   --  SetKernelValue (Col, Row, NewValue): the same index checks, and
   --  Bad_Parameter unless NewValue is finite and within
   --  +/-Max_Kernel_Value.

   procedure Convolve_3x3_Get_Kernel_Value
     (Params   : Ks_IP_One_Image_Convolve_3x3;
      Position : Int32;
      Value    : out Long_Float;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_convolve_3x3_get_kernel_value",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Position in 0 .. 8
                            and then Value = Params.Kernel (Integer (Position))
                       else Value = 0.0);
   --  GetKernelValue (position). Bad_Parameter for a position that is not
   --  a code of CogIPOneImageConvolve3x3PositionConstants.

   procedure Convolve_3x3_Set_Kernel_Value
     (Params   : in out Ks_IP_One_Image_Convolve_3x3;
      Position : Int32;
      Value    : Long_Float;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_convolve_3x3_set_kernel_value",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Position in 0 .. 8
                            and then Params.Kernel (Integer (Position))
                                       = Value
                            and then Params.Kernel_Origin
                                       = Params.Kernel_Origin'Old
                       else Params = Params'Old);
   --  SetKernelValue (position, value): the same position check, and
   --  Bad_Parameter unless Value is finite and within +/-Max_Kernel_Value.

   function Sigma (Smoothness : Int32) return Long_Float
   with
     Export, Convention => C, External_Name => "ks_ip_one_image_sigma",
     Post => Sigma'Result >= 0.0 and then Sigma'Result <= 4.0;
   --  SigmaX / SigmaY of GaussSampler and HighPassFilter: the standard
   --  deviation in pixels of the binomial smoothing of that smoothness,
   --  Sqrt (Smoothness / 2); 0.0 for a smoothness outside 0 ..
   --  Max_Smoothness.

   procedure Check_Operators
     (Operators : Ks_IP_One_Image_Operators;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_check_operators",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Operators (Operators));
   --  The checks of the operator list that Execute makes, alone:
   --  Bad_Parameter naming the operator and its property
   --  ("Operators(2).KernelWidth must be an odd number in 1 .. 1001"). A
   --  disabled operator is checked too.

   ---------------------------------------------------------------------
   --  Entry point: running
   ---------------------------------------------------------------------

   procedure Execute
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Region            : access constant KR.Ks_Pixel_Region_Data;
      Operators         : Ks_IP_One_Image_Operators;
      Output            : out KI.Ks_Image_8_Grey;
      Output_From_Input : out KT.Ks_Transform_2D_Linear;
      Status            : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_ip_one_image_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then KT.Bounded (Output_From_Input)
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then KI.Valid_Image (Output)
                     and then Valid_Operators (Operators)
                     and then
                       Size_After (Operators, Operators.Count, Size_Of (Image))
                         = Size_Of (Output)
                     and then
                       (if not Has_Geometric (Operators)
                        then Output.Width = Image.Width
                             and then Output.Height = Image.Height
                             and then Output_From_Input
                                        = KT.Ks_Transform_2D_Linear'
                                            (others => <>)
                             and then
                               (for all Y in Output.Pixels'Range (1) =>
                                  (for all X in Output.Pixels'Range (2) =>
                                     (if not KR.Contains
                                               (Region, Int32 (X), Int32 (Y))
                                      then Output.Pixels (Y, X)
                                             = Image.Pixels (Y, X)))))
                else Output = null);
   --  Applies the enabled operators in order (see above) and returns the
   --  result as a new image the caller owns (null when the call fails),
   --  with Output_From_Input (the identity when the call fails). The
   --  checks, in order: the image (Image_No_Pixels "InputImage has no
   --  pixels", Bad_Parameter "InputImage is not a valid image handle"),
   --  the region (Bad_Parameter "Region is not a valid pixel region
   --  handle"), the operators (Check_Operators), a list that changes the
   --  pixel grid with a region that does not contain the whole image
   --  (Bad_Parameter), an image of the list above Max_Pixels pixels
   --  (Bad_Parameter), then Out_Of_Memory. An enabled PelSet fails with
   --  Bad_Parameter (it needs a mask: Execute_Masked).

   procedure Execute_Masked
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Region            : access constant KR.Ks_Pixel_Region_Data;
      Operators         : Ks_IP_One_Image_Operators;
      Masks             : access constant Operator_Masks;
      Output            : out KI.Ks_Image_8_Grey;
      Output_From_Input : out KT.Ks_Transform_2D_Linear;
      Status            : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_one_image_execute_masked",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then KT.Bounded (Output_From_Input)
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then KI.Valid_Image (Output)
                     and then Valid_Operators (Operators)
                     and then
                       Size_After (Operators, Operators.Count, Size_Of (Image))
                         = Size_Of (Output)
                     and then
                       (if not Has_Geometric (Operators)
                        then Output.Width = Image.Width
                             and then Output.Height = Image.Height
                             and then Output_From_Input
                                        = KT.Ks_Transform_2D_Linear'
                                            (others => <>)
                             and then
                               (for all Y in Output.Pixels'Range (1) =>
                                  (for all X in Output.Pixels'Range (2) =>
                                     (if not KR.Contains
                                               (Region, Int32 (X), Int32 (Y))
                                      then Output.Pixels (Y, X)
                                             = Image.Pixels (Y, X)))))
                else Output = null);
   --  Execute with the InputImageMask of each operator: Masks (I) for the
   --  operator at index I (null Masks: none at all). The checks of
   --  Execute, then, after the operators, an enabled PelSet without a
   --  valid mask (Bad_Parameter "Operators(I).InputImageMask is not
   --  set").

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then KI.Valid_Image (Image));
   --  The image check of Execute, made by the Ada API before it
   --  rasterises the region.

end AMV.Kernels.IP_One_Image;
