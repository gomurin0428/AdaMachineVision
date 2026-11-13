--  Kernel of AMV.Image_Math: floating-point images (Real_Image) and the
--  operations the tools build on: conversion from and to 8-bit images,
--  bilinear sampling, resampling through a transform, Gaussian and box
--  smoothing, Sobel gradients, 2 x 2 downsampling and statistics. No
--  VisionPro counterpart.
--
--  Handles. The pixels of a Real_Image live behind an owned handle
--  (Ks_Real_Image; C: ks_real_image *, opaque) that ks_real_image_create,
--  ks_real_image_duplicate and every operation returning an image give, and
--  ks_real_image_destroy frees. A handle holds Width and Height (each at
--  least 0, Width * Height at most Max_Pixels) and the pixels, row after
--  row: the pixel at column X and row Y is Pixels (Y, X), both 0-based, and
--  its centre is at (X, Y). An image whose Width or Height is 0 is empty:
--  it keeps its size but holds no pixels. A null handle is the empty image
--  of size 0 x 0 (the default Real_Image of the Ada API): Width and Height
--  give 0, Duplicate gives null, Destroy does nothing. A handle that is not
--  null must come from this kernel and not be destroyed yet (C cannot check
--  that); a record that is inconsistent anyway fails with Bad_Parameter.
--  The kernel never shares pixels between handles (the Ada API copies on
--  assignment), and every operation returns new handles, so passing one
--  handle twice is harmless.
--
--  Bounds. Every pixel value lies within [-Max_Value, Max_Value] (1.0E100).
--  With that bound no sum the operations form can overflow: a window of
--  Box_Smooth sums at most (2 * 2**31 + 1)**2 values (about 1.8E119 in
--  all), Gaussian_Smooth at most 2 * 3_000_001 + 2 per pass, Statistics at
--  most 2**31 values and 2**31 squared deviations of at most
--  (2 * 1.0E100)**2 each (about 8.6E209 in all), all far below
--  Long_Float'Last (about 1.8E308). A value an operation takes (Value of
--  Create, Set_Pixel and Fill, a value read from a stream) must be finite
--  and within the bound (Bad_Parameter otherwise; Image_File for a
--  stream), and every value an operation computes is clamped to the bound:
--  an average (a smoothed pixel, a bilinear sample, a 2 x 2 mean) or a
--  Sobel derivative lies within the range of the values it combines, so
--  the clamp can only act when rounding carries a value within a few units
--  in the last place of the bound past it. So every pixel of every handle
--  the kernel makes is within the bound, and every image the kernel
--  returns is a valid argument again. (Values read from a handle are also
--  clamped to the bound before use, which never changes them and keeps the
--  proofs free of facts about the pixels of an argument.)
--
--  Coordinates (Bilinear, Is_Inside) may be any finite numbers: they are
--  clamped to the image before any arithmetic. A transform (Resample) must
--  be within the bound of AMV.Kernels.Transforms (1.0E150), so the mapped
--  centres of output pixels (at most 2**31 per axis) stay below about
--  4.3E159. Sigma (Gaussian_Smooth) must be finite. A NaN or an infinity
--  anywhere gives Bad_Parameter.
--
--  Trusted parts (SPARK_Mode Off bodies, listed in docs/PROOF.md): the
--  allocation helpers, which turn a failed allocation into Out_Of_Memory,
--  and the conversion of the bits of a finite binary64 value into a
--  Long_Float for the stream helpers. Everything else is proved.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Interfaces;

with AMV.Kernels.Images;
with AMV.Kernels.Transforms;

package AMV.Kernels.Image_Math with SPARK_Mode, Preelaborate is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  Postconditions compare pixels with their values on entry through
   --  the total ghost function Pixels_Of (contracts are proved, never
   --  executed).

   package KI renames AMV.Kernels.Images;
   package KT renames AMV.Kernels.Transforms;

   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type KI.Ks_Image_8_Grey;

   Max_Value : constant := 1.0E100;
   --  The bound of every pixel value (C: KS_REAL_IMAGE_MAX_VALUE).

   Max_Pixels : constant := KI.Max_Pixels;
   --  The largest Width * Height, 2**31 - 1 (C: KS_REAL_IMAGE_MAX_PIXELS).

   Max_Sigma : constant := 1.0E6;
   --  The largest Sigma Gaussian_Smooth accepts (C: KS_REAL_IMAGE_MAX_SIGMA).

   function In_Bound (X : Long_Float) return Boolean is
     (X >= -Max_Value and then X <= Max_Value);
   --  X is finite and within the bound (False for NaN at run time).

   ---------------------------------------------------------------------
   --  Pixel arrays and handles
   ---------------------------------------------------------------------

   type Real_Matrix is
     array (Natural range <>, Natural range <>) of Long_Float;
   --  Pixels indexed (Y, X): rows first.

   type Real_Pixels is access Real_Matrix;

   type Ks_Real_Image_Data is limited record
      Width  : Int32 := 0;
      Height : Int32 := 0;
      Pixels : Real_Pixels;
   end record;
   --  What a handle designates (opaque for C). Valid_Image states its
   --  invariant.

   type Ks_Real_Image is access Ks_Real_Image_Data
     with Convention => C;
   --  C: ks_real_image *.

   function Valid_Image
     (Image : access constant Ks_Real_Image_Data) return Boolean
   is
     (Image /= null
      and then Image.Pixels /= null
      and then Image.Width >= 0 and then Image.Height >= 0
      and then Int64 (Image.Width) * Int64 (Image.Height) <= Max_Pixels
      and then Image.Pixels'First (1) = 0
      and then Image.Pixels'First (2) = 0
      and then Image.Pixels'Last (1) = Integer (Image.Height) - 1
      and then Image.Pixels'Last (2) = Integer (Image.Width) - 1);
   --  A handle: Height rows of Width pixels, indexed from 0 (no pixels
   --  when either is 0).

   function Has_Pixels
     (Image : access constant Ks_Real_Image_Data) return Boolean
   is
     (Valid_Image (Image)
      and then Image.Width >= 1 and then Image.Height >= 1);
   --  A handle that is not empty.

   function Bounded_Image
     (Image : access constant Ks_Real_Image_Data) return Boolean
   is
     (Valid_Image (Image)
      and then (for all Y in Image.Pixels'Range (1)
                => (for all X in Image.Pixels'Range (2)
                    => In_Bound (Image.Pixels (Y, X)))))
   with Ghost;
   --  A handle whose every pixel is within the bound.

   No_Pixels : constant Real_Matrix (1 .. 0, 1 .. 0) :=
     [others => [others => 0.0]];

   function Pixels_Of
     (Image : access constant Ks_Real_Image_Data) return Real_Matrix
   is
     (if Valid_Image (Image) then Image.Pixels.all else No_Pixels)
   with Ghost;
   --  The pixels of a valid handle (none otherwise), for contracts.

   type Image_Size is record
      Width, Height : Int32;
   end record
     with Ghost;

   function Size_Of
     (Image : access constant Ks_Real_Image_Data) return Image_Size
   is
     (if Image = null then (0, 0) else (Image.Width, Image.Height))
   with Ghost;
   --  Width and Height ((0, 0) for null), for contracts.

   function Filtered
     (Image  : access constant Ks_Real_Image_Data;
      Result : access constant Ks_Real_Image_Data) return Boolean
   is
     (if Image = null then Result = null
      else Bounded_Image (Result)
           and then Result.Width = Image.Width
           and then Result.Height = Image.Height)
   with Ghost;
   --  Result is the image a filter gives for Image: null for null,
   --  otherwise a bounded image of the same size.

   ---------------------------------------------------------------------
   --  Entry points: handles and pixels
   ---------------------------------------------------------------------

   procedure Create
     (Width, Height : Int32;
      Value         : Long_Float;
      Image         : out Ks_Real_Image;
      Status        : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_create",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Bounded_Image (Image)
                            and then Image.Width = Width
                            and then Image.Height = Height
                            and then (for all Y in Image.Pixels'Range (1)
                                      => (for all X in Image.Pixels'Range (2)
                                          => Image.Pixels (Y, X) = Value))
                       else Image = null);
   --  A new Width x Height image with every pixel set to Value (an empty
   --  one when Width or Height is 0). Bad_Parameter unless Width and
   --  Height are at least 0 and Width * Height is at most Max_Pixels
   --  ("Create: Width * Height is too large"), and unless Value is within
   --  the bound; Out_Of_Memory when the pixels cannot be allocated.

   procedure Destroy
     (Image  : in out Ks_Real_Image;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_destroy",
     Post => Valid (Status) and then Succeeded (Status) and then Image = null;
   --  Frees the image and sets Image to null. Nothing for null. Never
   --  fails.

   procedure Width
     (Image  : access constant Ks_Real_Image_Data;
      Result : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_width",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then Image /= null
                       then Valid_Image (Image) and then Result = Image.Width
                       else Result = 0);
   --  The width in pixels; 0 for null.

   procedure Height
     (Image  : access constant Ks_Real_Image_Data;
      Result : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_height",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then Image /= null
                       then Valid_Image (Image)
                            and then Result = Image.Height
                       else Result = 0);
   --  The height in pixels; 0 for null.

   procedure Get_Pixel
     (Image  : access constant Ks_Real_Image_Data;
      X, Y   : Int32;
      Value  : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_get_pixel",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then X in 0 .. Image.Width - 1
                            and then Y in 0 .. Image.Height - 1
                            and then Value
                                       = Image.Pixels (Natural (Y),
                                                       Natural (X))
                       else Value = 0.0);
   --  The pixel at column X, row Y. Index_Out_Of_Range unless X is in
   --  0 .. Width - 1 and Y in 0 .. Height - 1 (always for an empty image:
   --  "Get: pixel (0, 0) is outside the 0 x 0 image").

   procedure Set_Pixel
     (Image  : Ks_Real_Image;
      X, Y   : Int32;
      Value  : Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_set_pixel",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then Size_Of (Image) = Size_Of (Image)'Old
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then X in 0 .. Image.Width - 1
                            and then Y in 0 .. Image.Height - 1
                            and then In_Bound (Value)
                            and then Image.Pixels (Natural (Y), Natural (X))
                                       = Value
                            and then
                              (for all J in Image.Pixels'Range (1)
                               => (for all I in Image.Pixels'Range (2)
                                   => (if J /= Natural (Y)
                                         or else I /= Natural (X)
                                       then Image.Pixels (J, I)
                                              = Pixels_Of (Image)'Old (J, I))))
                       else Pixels_Of (Image) = Pixels_Of (Image)'Old);
   --  Sets the pixel at column X, row Y, and no other (Gold). Failures as
   --  for Get_Pixel, then Bad_Parameter unless Value is within the bound
   --  ("Set: Value must be finite and within +/-1.0E100"); a failed call
   --  changes nothing.

   procedure Fill
     (Image  : Ks_Real_Image;
      Value  : Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_fill",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Size_Of (Image) = Size_Of (Image)'Old
             and then (if Succeeded (Status) and then Image /= null
                       then Valid_Image (Image)
                            and then (for all Y in Image.Pixels'Range (1)
                                      => (for all X in Image.Pixels'Range (2)
                                          => Image.Pixels (Y, X) = Value))
                       else Pixels_Of (Image) = Pixels_Of (Image)'Old);
   --  Sets every pixel to Value (nothing for an empty image). Bad_Parameter
   --  unless Value is within the bound.

   procedure Duplicate
     (Image  : access constant Ks_Real_Image_Data;
      Result : out Ks_Real_Image;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_duplicate",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) and then Image /= null
                       then Valid_Image (Image) and then Valid_Image (Result)
                            and then Result.Width = Image.Width
                            and then Result.Height = Image.Height
                            and then Result.Pixels.all = Image.Pixels.all
                       else Result = null);
   --  A new image with the same size and pixels, sharing nothing with
   --  Image; null for null.

   ---------------------------------------------------------------------
   --  Entry points: conversion from and to 8-bit images
   ---------------------------------------------------------------------

   procedure From_Grey_8
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Result : out Ks_Real_Image;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_from_8_grey",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then KI.Valid_Image (Image)
                            and then Bounded_Image (Result)
                            and then Result.Width = Image.Width
                            and then Result.Height = Image.Height
                       else Result = null);
   --  The whole 8-bit image as a Real_Image. Image_No_Pixels for null
   --  ("From_Grey_8: the image has no pixels").

   procedure From_Grey_8_Window
     (Image                       : access constant KI.Ks_Image_8_Grey_Data;
      X_Min, Y_Min, Width, Height : Int32;
      Result                      : out Ks_Real_Image;
      Status                      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_real_image_from_8_grey_window",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Bounded_Image (Result)
                            and then Result.Width = Width
                            and then Result.Height = Height
                            and then Width >= 1 and then Height >= 1
                       else Result = null);
   --  The window: pixel (X, Y) of the result is pixel (X_Min + X,
   --  Y_Min + Y) of Image. Image_No_Pixels for null; Bad_Parameter when
   --  the window is empty ("From_Grey_8: the window must not be empty") or
   --  does not lie inside the image ("From_Grey_8: the window must lie
   --  inside the image").

   procedure To_Grey_8
     (Image  : access constant Ks_Real_Image_Data;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_to_8_grey",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Has_Pixels (Image)
                            and then KI.Valid_Image (Result)
                            and then Result.Width = Image.Width
                            and then Result.Height = Image.Height
                       else Result = null);
   --  A new 8-bit image: every value rounded to the nearest integer
   --  (halves away from zero) and clamped to 0 .. 255. Bad_Parameter for
   --  an empty image ("To_Grey_8: the image is empty").

   ---------------------------------------------------------------------
   --  Entry points: sampling
   ---------------------------------------------------------------------

   procedure Bilinear
     (Image  : access constant Ks_Real_Image_Data;
      X, Y   : Long_Float;
      Result : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_bilinear",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then In_Bound (Result)
             and then (if not Succeeded (Status) then Result = 0.0);
   --  Bilinear interpolation between pixel centres at (X, Y). Coordinates
   --  outside [0, Width - 1] x [0, Height - 1] are clamped to the border;
   --  an image one pixel wide (or high) is constant along that axis.
   --  Bad_Parameter for an empty image ("Bilinear: the image is empty")
   --  and for a coordinate that is not finite.

   procedure Bilinear_Grey_8
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      X, Y   : Long_Float;
      Result : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_real_image_bilinear_8_grey",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then In_Bound (Result)
             and then (if not Succeeded (Status) then Result = 0.0);
   --  The same, sampling an 8-bit image. Image_No_Pixels for null
   --  ("Bilinear: the image has no pixels").

   procedure Is_Inside
     (Image  : access constant Ks_Real_Image_Data;
      X, Y   : Long_Float;
      Result : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_is_inside",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result in False_Value | True_Value
             and then (if Result = True_Value
                       then Has_Pixels (Image)
                            and then X >= 0.0 and then Y >= 0.0
                            and then X <= Long_Float (Image.Width - 1)
                            and then Y <= Long_Float (Image.Height - 1));
   --  1 when (X, Y) lies in [0, Width - 1] x [0, Height - 1], 0 otherwise
   --  (always 0 for an empty image). Bad_Parameter for a coordinate that
   --  is not finite.

   procedure Resample
     (Image             : access constant Ks_Real_Image_Data;
      Pixel_From_Output : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      Result            : out Ks_Real_Image;
      Status            : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_resample",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Bounded_Image (Result)
                            and then Result.Width = Width
                            and then Result.Height = Height
                       else Result = null);
   --  A new Width x Height image whose pixel (I, J) is Bilinear (Image,
   --  Pixel_From_Output mapping (I, J)), the mapped point computed as
   --  ks_transform_2d_linear_map_point does. Bad_Parameter for an empty
   --  image ("Resample: the image is empty"), for a transform beyond the
   --  bound of AMV.Kernels.Transforms, unless Width and Height are at
   --  least 1, and when Width * Height exceeds Max_Pixels ("Resample:
   --  Width * Height is too large").

   procedure Resample_Grey_8
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Pixel_From_Output : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      Result            : out Ks_Real_Image;
      Status            : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_real_image_resample_8_grey",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Bounded_Image (Result)
                            and then Result.Width = Width
                            and then Result.Height = Height
                       else Result = null);
   --  The same, sampling an 8-bit image. Image_No_Pixels for null.

   ---------------------------------------------------------------------
   --  Entry points: filters and statistics
   ---------------------------------------------------------------------

   --  The filters return a new image of the size of Image: null for null,
   --  and an empty image of the same size for an empty one. Borders are
   --  replicated.

   procedure Gaussian_Smooth
     (Image  : access constant Ks_Real_Image_Data;
      Sigma  : Long_Float;
      Result : out Ks_Real_Image;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_real_image_gaussian_smooth",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) then Filtered (Image, Result)
                       else Result = null);
   --  Separable Gaussian filter, kernel radius ceiling (3 Sigma) (at least
   --  1), normalised. Sigma <= 0 gives a copy. Bad_Parameter when Sigma is
   --  not finite, and when it exceeds Max_Sigma ("Gaussian_Smooth: Sigma
   --  must not exceed Max_Sigma") for an image that is not empty.

   procedure Box_Smooth
     (Image     : access constant Ks_Real_Image_Data;
      Half_Size : Int32;
      Result    : out Ks_Real_Image;
      Status    : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_box_smooth",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) then Filtered (Image, Result)
                       else Result = null);
   --  The mean over a (2 Half_Size + 1) square window: separable running
   --  sums, O(1) per pixel whatever Half_Size, compensated (Neumaier) so
   --  that a huge value that has left the window leaves behind an error of
   --  at most about N eps**2 times its magnitude. Half_Size 0 gives a
   --  copy. Bad_Parameter when Half_Size is negative.

   procedure Sobel
     (Image  : access constant Ks_Real_Image_Data;
      Gx, Gy : out Ks_Real_Image;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_sobel",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Filtered (Image, Gx) and then Filtered (Image, Gy)
                       else Gx = null and then Gy = null);
   --  3 x 3 Sobel derivatives normalised by 1/8 (a unit ramp gives 1): Gx
   --  is d/dx (to the right), Gy is d/dy (downwards). Both null when the
   --  call fails (nothing is leaked when the second cannot be allocated).

   procedure Downsample_2
     (Image  : access constant Ks_Real_Image_Data;
      Result : out Ks_Real_Image;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_real_image_downsample_2",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then (if Has_Pixels (Image)
                             then Bounded_Image (Result)
                                  and then Result.Width
                                             = Int32'Max (1, Image.Width / 2)
                                  and then Result.Height
                                             = Int32'Max (1, Image.Height / 2)
                             else Filtered (Image, Result))
                       else Result = null);
   --  Halves both dimensions (rounding down, at least 1) by averaging
   --  2 x 2 blocks: output pixel (I, J) covers input pixels (2I .. 2I+1,
   --  2J .. 2J+1). An odd last column (or row) is dropped, except that an
   --  input one pixel wide (or high) is used as it is. An empty image
   --  gives an empty image of the same size.

   procedure Statistics
     (Image            : access constant Ks_Real_Image_Data;
      Mean, Std_Dev    : out Long_Float;
      Minimum, Maximum : out Long_Float;
      Status           : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_real_image_statistics",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Has_Pixels (Image)
                            and then In_Bound (Minimum)
                            and then In_Bound (Maximum)
                            and then Minimum <= Mean
                            and then Mean <= Maximum
                            and then Std_Dev >= 0.0
                            and then Std_Dev <= Maximum - Minimum
                       else Mean = 0.0 and then Std_Dev = 0.0
                            and then Minimum = 0.0 and then Maximum = 0.0);
   --  Population statistics over all pixels; the mean is computed as the
   --  sum divided by the count and then kept within [Minimum, Maximum]
   --  (rounding could otherwise carry the mean of equal values just
   --  outside), the standard deviation in a second pass about the mean.
   --  Bad_Parameter for an empty image ("Statistics: the image is
   --  empty").

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   --  Lean per-pixel access (AMV.Image_Math.Get and Set). Done is True
   --  exactly when the entry point of the same name succeeds, and the
   --  effect is then the same; nothing happens otherwise, and the Ada API
   --  calls the entry point to obtain the failure status.

   function Pixel_Exists
     (Image : access constant Ks_Real_Image_Data;
      X, Y  : Int32) return Boolean
   is
     (Valid_Image (Image)
      and then X in 0 .. Image.Width - 1
      and then Y in 0 .. Image.Height - 1);
   --  When Get_Pixel succeeds (and Set_Pixel, for a value within the
   --  bound).

   procedure Try_Get_Pixel
     (Image : access constant Ks_Real_Image_Data;
      X, Y  : Int32;
      Value : out Long_Float;
      Done  : out Boolean)
   with
     Inline,
     Post => Done = Pixel_Exists (Image, X, Y)
             and then (if Done
                       then Value = Image.Pixels (Natural (Y), Natural (X))
                       else Value = 0.0);

   procedure Try_Set_Pixel
     (Image : Ks_Real_Image;
      X, Y  : Int32;
      Value : Long_Float;
      Done  : out Boolean)
   with
     Inline,
     Post => Done = (Pixel_Exists (Image, X, Y) and then In_Bound (Value))
             and then Size_Of (Image) = Size_Of (Image)'Old
             and then (if Done
                       then Valid_Image (Image)
                            and then Image.Pixels (Natural (Y), Natural (X))
                                       = Value
                            and then
                              (for all J in Image.Pixels'Range (1)
                               => (for all I in Image.Pixels'Range (2)
                                   => (if J /= Natural (Y)
                                         or else I /= Natural (X)
                                       then Image.Pixels (J, I)
                                              = Pixels_Of (Image)'Old (J, I))))
                       else Pixels_Of (Image) = Pixels_Of (Image)'Old);

   --  Streams (the stream attributes of Real_Image, whose layout the spec
   --  of AMV.Image_Math describes). The Ada API reads and writes the
   --  stream in chunks of values; the kernel checks every field read and
   --  converts values to and from their bits. Every failure is
   --  Image_File, with a message that starts with "Real_Image'Read: ".

   subtype U32 is Interfaces.Unsigned_32;
   subtype U64 is Interfaces.Unsigned_64;

   Code_Real_Image : constant U32 := 16#4B53_5240#;
   --  "KSR" and 64, the bits per value: the format code of a Real_Image.

   Initial_Read_Capacity : constant := 65_536;
   --  Values allocated before the stream has shown that more exist.

   type Bits_Array is array (Positive range <>) of U64;
   --  Values as the bits of their IEEE 754 binary64 representation.

   type Pixel_Position is record
      Row    : Int32 := 0;
      Column : Int32 := 0;
   end record;
   --  The next pixel to write, row after row; (Height, 0) at the end.

   procedure Next_Write_Chunk
     (Image    : access constant Ks_Real_Image_Data;
      Position : Pixel_Position;
      Limit    : Positive;
      Length   : out Natural)
   with Post => Length <= Limit;
   --  The number of values the next chunk holds: at most Limit, 0 at the
   --  end and for an empty image.

   procedure Get_Bits
     (Image    : access constant Ks_Real_Image_Data;
      Position : in out Pixel_Position;
      Bits     : out Bits_Array;
      Status   : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  The bits of the next Bits'Length values, moving Position on.
   --  Bad_Parameter when the image is not valid or not that many values
   --  are left.

   type Real_Values is array (Natural range <>) of Long_Float;
   type Real_Values_Access is access Real_Values;

   type Read_State is record
      Width, Height : Int32 := 0;
      Count         : Int64 := 0;
      Filled        : Int64 := 0;
      Values        : Real_Values_Access;
   end record;
   --  An image being read: Width x Height (Count values), the first
   --  Filled of which are in Values. Values is owned (Finish_Read or
   --  Abandon_Read frees it).

   function Valid_State (State : Read_State) return Boolean is
     (State.Width >= 0 and then State.Height >= 0
      and then State.Count = Int64 (State.Width) * Int64 (State.Height)
      and then State.Count <= Max_Pixels
      and then State.Filled in 0 .. State.Count
      and then (if State.Count > 0
                then State.Values /= null
                     and then State.Values'First = 0
                     and then State.Values'Last >= 0
                     and then Int64 (State.Values'Last) in
                                State.Filled - 1 .. State.Count - 1
                else State.Values = null));
   --  What the read helpers keep.

   procedure Check_Read_Code
     (Code   : U32;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Image_File
                and then (if Succeeded (Status) then Code = Code_Real_Image);
   --  The format code read must be the one of a Real_Image.

   procedure Start_Read
     (Width, Height : U32;
      State         : out Read_State;
      Status        : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_File
                            | Failure_Out_Of_Memory
                and then (if Succeeded (Status)
                          then Valid_State (State)
                               and then State.Filled = 0
                          else State.Values = null);
   --  The size read: each at most Natural'Last ("Real_Image'Read: the size
   --  is too large") and Width * Height at most Max_Pixels
   --  ("Real_Image'Read: Width * Height is too large"). Allocates room for
   --  the first values (at most Initial_Read_Capacity).

   procedure Next_Read_Chunk
     (State  : in out Read_State;
      Limit  : Positive;
      Length : out Natural;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Out_Of_Memory
                and then Length <= Limit
                and then (if Succeeded (Status)
                          then Valid_State (State)
                               and then State.Filled = State.Filled'Old
                               and then Int64 (Length)
                                          <= State.Count - State.Filled
                               and then (Length = 0)
                                          = (State.Filled = State.Count)
                               and then (if Length > 0
                                         then State.Filled + Int64 (Length)
                                                <= Int64 (State.Values'Last)
                                                   + 1)
                          else Length = 0);
   --  The number of values to read next (at most Limit, 0 when the image
   --  is complete). When every value allocated so far has arrived, the
   --  room doubles first (up to Count), so a size that promises more
   --  values than the stream holds cannot make the reader allocate more
   --  than about twice what the stream contains. Bad_Parameter for a
   --  state that is not valid.

   procedure Store_Bits
     (State  : in out Read_State;
      Bits   : Bits_Array;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Image_File;
   --  Stores the values read, which must be finite ("Real_Image'Read: a
   --  pixel value is not finite") and within the bound ("Real_Image'Read:
   --  a pixel value is beyond +/-1.0E100"). Bad_Parameter when the state
   --  is not valid or Bits does not fit in the room Next_Read_Chunk made.

   procedure Finish_Read
     (State  : in out Read_State;
      Image  : out Ks_Real_Image;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Out_Of_Memory
                and then State.Values = null
                and then (if Succeeded (Status) then Bounded_Image (Image)
                          else Image = null);
   --  The image read (empty, of the size read, when it has no pixels);
   --  frees the values. Bad_Parameter unless every value has been stored.

   procedure Abandon_Read (State : in out Read_State)
   with Post => State.Values = null;
   --  Frees the values of a read that failed.

   procedure Stream_Ended (Status : out Ks_Status)
   with Post => Valid (Status) and then Status.Failure = Failure_Image_File;
   --  "Real_Image'Read: the stream ends before the image does".

end AMV.Kernels.Image_Math;
