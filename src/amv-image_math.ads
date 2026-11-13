--  Floating point images and the numeric building blocks shared by the
--  tools: sampling, resampling through a transform, separable Gaussian
--  smoothing, gradients and pyramids. This package has no VisionPro
--  counterpart.
--
--  A Real_Image is a heap-allocated Width x Height array of Real with value
--  semantics (assignment copies the pixels). Pixel (X, Y) has its centre at
--  (X, Y), as for the images of AMV.Images. If the allocation for a copy
--  fails (Storage_Error, which an assignment reports as Program_Error),
--  the target is left empty (0 x 0) and shares nothing with the source.
--
--  No operation of this package keeps pixel data, or any array whose
--  length grows with an image dimension, on the stack: images of any
--  legal size work inside tasks with small stacks.
--
--  An image whose Width or Height is zero is empty: it holds no pixels.
--  Filters (Gaussian_Smooth, Box_Smooth, Sobel, Downsample_2) return an
--  empty image of the same size for an empty input. Sampling an empty
--  Real_Image (Bilinear, Resample) raises Ks_Bad_Parameter_Exception;
--  sampling an unallocated Ks_Image_8_Grey raises
--  Ks_Image_No_Pixels_Exception.
--
--  Bounds. Every pixel value lies within [-Max_Value, Max_Value]
--  (1.0E100), so that no sum a filter or Statistics forms can overflow.
--  Create, Set and Fill raise Ks_Bad_Parameter_Exception for a value that
--  is not finite or not within it, and every value an operation computes
--  is clamped to it: an average (a smoothed pixel, a bilinear sample, a
--  2 x 2 mean) or a Sobel derivative lies within the range of the values
--  it combines, so only rounding at the very edge of the bound can reach
--  the clamp. Coordinates (Bilinear, Is_Inside) and Sigma must be finite
--  (Ks_Bad_Parameter_Exception otherwise).
--
--  The work is done by the SPARK kernel AMV.Kernels.Image_Math (C API:
--  ks_real_image_*); this package only calls it.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Transforms;

private with Ada.Finalization;
private with Ada.Streams;
private with AMV.Kernels.Image_Math;

package AMV.Image_Math is

   type Real_Image is tagged private;
   --  Default: empty (Width = Height = 0).

   Max_Value : constant := 1.0E100;
   --  The bound of every pixel value (AMV.Kernels.Image_Math.Max_Value).

   function Create
     (Width, Height : Natural; Value : Real := 0.0) return Real_Image;
   --  An image with every pixel set to Value. Raises
   --  Ks_Bad_Parameter_Exception when Width * Height exceeds Natural'Last
   --  and when Value is not finite or not within +/-Max_Value.

   function Width (Image : Real_Image) return Natural with Inline;
   function Height (Image : Real_Image) return Natural with Inline;

   function Get (Image : Real_Image; X, Y : Natural) return Real with Inline;
   procedure Set (Image : in out Real_Image; X, Y : Natural; Value : Real)
   with Inline;
   --  Constraint_Error when (X, Y) is outside the image. Set raises
   --  Ks_Bad_Parameter_Exception when Value is not finite or not within
   --  +/-Max_Value.

   procedure Fill (Image : in out Real_Image; Value : Real);
   --  Every pixel set to Value (nothing for an empty image). Raises
   --  Ks_Bad_Parameter_Exception when Value is not finite or not within
   --  +/-Max_Value.

   function From_Grey_8
     (Image : AMV.Images.Ks_Image_8_Grey) return Real_Image;
   --  The whole image. Raises Ks_Image_No_Pixels_Exception when Image is
   --  unallocated.

   function From_Grey_8
     (Image                       : AMV.Images.Ks_Image_8_Grey;
      X_Min, Y_Min, Width, Height : Natural) return Real_Image;
   --  The given window: pixel (X, Y) of the result is pixel
   --  (X_Min + X, Y_Min + Y) of Image. The window must be non-empty and lie
   --  inside the image (Ks_Bad_Parameter_Exception otherwise). Raises
   --  Ks_Image_No_Pixels_Exception when Image is unallocated.

   function To_Grey_8 (Image : Real_Image) return AMV.Images.Ks_Image_8_Grey;
   --  Rounds to the nearest integer (halves away from zero) and clamps to
   --  0 .. 255. Raises Ks_Bad_Parameter_Exception for an empty image.

   function Bilinear (Image : Real_Image; X, Y : Real) return Real;
   --  Bilinear interpolation between pixel centres. Coordinates outside
   --  [0, Width - 1] x [0, Height - 1] are clamped to the border. An image
   --  that is one pixel wide (or high) is constant along that axis. Raises
   --  Ks_Bad_Parameter_Exception when X or Y is not finite.

   function Bilinear
     (Image : AMV.Images.Ks_Image_8_Grey; X, Y : Real) return Real;
   --  Same, sampling an 8-bit image directly.

   function Is_Inside (Image : Real_Image; X, Y : Real) return Boolean;
   --  True when (X, Y) lies in [0, Width - 1] x [0, Height - 1] (always
   --  False for an empty image). Raises Ks_Bad_Parameter_Exception when X
   --  or Y is not finite.

   function Resample
     (Image             : AMV.Images.Ks_Image_8_Grey;
      Pixel_From_Output : AMV.Transforms.Ks_Transform_2D_Linear;
      Width, Height     : Positive) return Real_Image;
   --  Output pixel (I, J) is Bilinear (Image, Pixel_From_Output (I, J)).
   --  Raises Ks_Bad_Parameter_Exception when Width * Height exceeds
   --  Natural'Last.

   function Resample
     (Image             : Real_Image;
      Pixel_From_Output : AMV.Transforms.Ks_Transform_2D_Linear;
      Width, Height     : Positive) return Real_Image;

   Max_Sigma : constant := 1.0E6;
   --  The largest Sigma that Gaussian_Smooth accepts.

   function Gaussian_Smooth
     (Image : Real_Image; Sigma : Real) return Real_Image;
   --  Separable Gaussian filter, kernel radius ceiling (3 * Sigma),
   --  normalised, borders replicated. Sigma <= 0 returns a copy. Raises
   --  Ks_Bad_Parameter_Exception when Sigma is not finite, and when Sigma >
   --  Max_Sigma for an image that is not empty.

   function Box_Smooth
     (Image : Real_Image; Half_Size : Natural) return Real_Image;
   --  Mean over a (2 * Half_Size + 1) square window, borders replicated.
   --  Separable running sums, O(1) per pixel whatever Half_Size. The
   --  running sums are compensated (Neumaier), so a value that has left
   --  the window, however large, leaves behind an error of at most about
   --  N * eps**2 times its magnitude (N the length of the row or column),
   --  where plain running sums would keep an error of about eps times its
   --  magnitude for the rest of the row: a 1.0E17 pixel among pixels of 1
   --  no longer turns their means into 1/3 once it is out of the window.

   procedure Sobel (Image : Real_Image; Gx, Gy : out Real_Image);
   --  3 x 3 Sobel derivatives (normalised by 1/8 so that a unit ramp gives
   --  gradient 1), borders replicated. Gx is d/dx (to the right), Gy is
   --  d/dy (downwards). Because of the replication, a ramp gives half its
   --  slope in the first and last column (or row).

   function Downsample_2 (Image : Real_Image) return Real_Image;
   --  Halves both dimensions (rounding down, at least 1) by averaging 2 x 2
   --  blocks. Output pixel (I, J) covers input pixels (2I .. 2I+1,
   --  2J .. 2J+1), so its centre is at input (2I + 0.5, 2J + 0.5). An odd
   --  last input column (or row) is dropped, except that an input one pixel
   --  wide (or high) is used as it is: the output then averages the pixels
   --  that exist, and its centre is at input coordinate 0 along that axis.

   procedure Statistics
     (Image          : Real_Image;
      Mean, Std_Dev  : out Real;
      Minimum, Maximum : out Real);
   --  Population statistics over all pixels. The mean is the sum divided
   --  by the count, kept within [Minimum, Maximum] (rounding could carry
   --  the mean of equal values just outside); the standard deviation is
   --  computed about it in a second pass, so a large mean causes no
   --  cancellation. Raises Ks_Bad_Parameter_Exception for an empty image.

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   --  Real_Image has its own 'Write and 'Read (used by 'Output, 'Input and
   --  Real_Image'Class'Output and 'Input too). They store the image by
   --  value, never a reference to its buffer, as:
   --
   --  1. a format code (Interfaces.Unsigned_32) naming Real_Image and this
   --     layout;
   --  2. Width and Height (Unsigned_32 each);
   --  3. the Width * Height pixel values, row after row starting at
   --     (0, 0), each as the bits of its IEEE 754 binary64 value in an
   --     Interfaces.Unsigned_64.
   --
   --  The integers use the stream attributes of the Interfaces types,
   --  whose representation the compiler chooses (GNAT: the byte order of
   --  the platform), so a stream is meant to be read by a program built
   --  with the same compiler for the same kind of platform.
   --
   --  'Read treats the stream as untrusted. The format code must match,
   --  the size must satisfy Width * Height <= Natural'Last (as for
   --  Create), and every value must be finite and within +/-Max_Value.
   --  The values are collected in a buffer that grows as they arrive
   --  (starting from at most 65536 values and doubling), so a size that
   --  promises more values than the stream holds cannot make it allocate
   --  more than about twice what the stream really contains; the image is
   --  built from the buffer once every value has arrived. A field that
   --  fails a check, or a stream that ends before the image is complete,
   --  raises Ks_Image_File_Exception; any other exception from the stream
   --  propagates unchanged. On any failure the target keeps its previous
   --  value. The kernel (AMV.Kernels.Image_Math) makes the checks.

private

   type Real_Image is new Ada.Finalization.Controlled with record
      Handle : AMV.Kernels.Image_Math.Ks_Real_Image;
      --  The kernel's handle (owned; never shared with another image);
      --  null for the empty image of size 0 x 0.
   end record;

   overriding procedure Adjust (Image : in out Real_Image);
   overriding procedure Finalize (Image : in out Real_Image);

   --  The default stream attributes would write and read the buffer's
   --  address: every type that owns heap memory through an access
   --  component needs its own (see Streams above).

   procedure Write_Image
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Real_Image);
   procedure Read_Image
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Real_Image);

   for Real_Image'Write use Write_Image;
   for Real_Image'Read use Read_Image;

end AMV.Image_Math;
