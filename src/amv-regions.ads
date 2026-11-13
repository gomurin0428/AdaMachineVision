--  Converting regions into sets of image pixels. Tools use this to decide
--  which pixels of their input image a Region covers.
--
--  A pixel belongs to the rasterised region when its centre, mapped from
--  pixel space into the region's selected space, satisfies
--  Contains_Point. The result is always clipped to the image.
--
--  A Pixel_Region is a value: assignment copies the pixel set, so a copy
--  stays valid after the original is changed or goes out of scope. The
--  stream attributes work by value too (see "Streams" at the end of the
--  visible part).
--
--  The logic lives in the SPARK kernel AMV.Kernels.Regions (C:
--  ks_pixel_region_*), which proves, among other things, that the pixel
--  count is the number of pixels Contains accepts and that the bounding
--  rectangle is the smallest one (docs/PROOF.md). When the memory for a
--  copy cannot be allocated, the assignment raises Storage_Error and the
--  target is left empty.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Shapes;
with AMV.Shapes.Region_Holders;

private with Ada.Finalization;
private with Ada.Streams;
private with AMV.Kernels.Regions;

package AMV.Regions is

   type Pixel_Region is tagged private;
   --  A set of pixels inside the rectangle
   --  [X_Min, X_Min + Width - 1] x [Y_Min, Y_Min + Height - 1] of pixel
   --  space. Default: empty.

   function Whole_Image
     (Image : AMV.Images.Ks_Image'Class) return Pixel_Region;
   --  Every pixel of Image. Raises Ks_Image_No_Pixels_Exception for an
   --  unallocated image.

   function Rasterize
     (Image  : AMV.Images.Ks_Image'Class;
      Region : AMV.Shapes.Ks_Region'Class) return Pixel_Region;
   --  The pixels of Image covered by Region, exactly as the definition
   --  above says: pixel (I, J) is included when Region.Contains_Point holds
   --  for Invert (T) applied to (I, J), where T = Image.Get_Transform ("#",
   --  Region.Selected_Space_Name) relates the region to pixel space.
   --
   --  Only candidate pixels are tested. Every point Contains_Point accepts
   --  lies within S = Region.Boundary_Slack of Region's bounding box along
   --  each axis. The four corners of the bounding box are mapped through
   --  T = [A B; C D] + translation; the axis-aligned box around the
   --  mapped corners is widened by 0.5 + S * (abs A + abs B) pixels in x
   --  and 0.5 + S * (abs C + abs D) in y (the image of the slack, plus
   --  half a pixel so that pixel centres on the edge of the box are not
   --  lost to rounding), clipped to the image, and the pixels in it are
   --  the candidates. So no pixel that satisfies the definition is
   --  skipped, however far the region is from the origin and whatever the
   --  scale of T.
   --
   --  The bounding rectangle of the result is the smallest one around the
   --  included pixels. A region that covers no pixel centre of the image
   --  (for example one lying entirely outside it) gives an empty
   --  Pixel_Region, not an exception.
   --
   --  A pixel centre that maps beyond the coordinate bound of AMV.Shapes
   --  (1.0E150) cannot be in the region and is not included.
   --
   --  Raises Ks_Image_No_Pixels_Exception for an unallocated image (this
   --  is checked before the space name) and
   --  Ks_Image_Bad_Selected_Space_Name_Exception for an unknown space;
   --  Ks_Transform_Singular_Exception only in the extreme cases described
   --  for AMV.Images.Get_Transform. Region must be of one of the region
   --  types of AMV.Shapes (or of a type derived from one, which is
   --  rasterised as that type); any other type derived from Ks_Region
   --  raises Ks_Bad_Parameter_Exception (checked before the space name).
   --  A region whose bounding box leaves the bounds of AMV.Shapes raises
   --  Ks_Bad_Parameter_Exception, as its Get_Bounding_Box does.

   function Rasterize
     (Image  : AMV.Images.Ks_Image'Class;
      Region : AMV.Shapes.Region_Holders.Holder) return Pixel_Region;
   --  Whole_Image when Region is empty, otherwise Rasterize of its element.

   function Bounding_Box (Region : Pixel_Region) return Pixel_Region;
   --  Every pixel of Region's bounding rectangle (the empty region for an
   --  empty Region). C: ks_pixel_region_bounding_box.

   function Restrict_To_Mask
     (Region   : Pixel_Region;
      Mask     : AMV.Images.Ks_Image_8_Grey'Class;
      Offset_X : Integer := 0;
      Offset_Y : Integer := 0) return Pixel_Region;
   --  The pixels of Region that Mask does not mark "don't care" (AMV
   --  name). Mask is laid over the pixels at an offset: mask pixel (U, V)
   --  lies over pixel (U + Offset_X, V + Offset_Y). A mask pixel of value
   --  0 marks the pixel under it "don't care"; a pixel under a mask pixel
   --  of any other value, and every pixel that no mask pixel lies over, is
   --  kept. So an unallocated Mask keeps every pixel of Region, and a
   --  mask placed partly outside the image affects only the pixels it
   --  lies over. The bounding rectangle of the result is the smallest one
   --  around the pixels kept; when none is kept the result is empty (no
   --  exception). Tools use it for their input image masks (for example
   --  AMV.Image_Processing.Histogram).

   function Is_Empty (Region : Pixel_Region) return Boolean;
   function Pixel_Count (Region : Pixel_Region) return Natural;

   function X_Min (Region : Pixel_Region) return Natural;
   function Y_Min (Region : Pixel_Region) return Natural;
   function Width (Region : Pixel_Region) return Natural;
   function Height (Region : Pixel_Region) return Natural;
   --  The bounding rectangle in pixel coordinates (all 0 when empty).

   function Contains (Region : Pixel_Region; X, Y : Integer) return Boolean
   with Inline;
   --  True when pixel (X, Y) belongs to the region; False for any pixel
   --  outside the bounding rectangle. Takes constant time.

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   --  Pixel_Region has its own 'Write and 'Read, which 'Output, 'Input
   --  and Pixel_Region'Class'Output / 'Input use too. They store the
   --  region by value, as stream elements (bytes):
   --
   --  1. a format code naming Pixel_Region and this layout;
   --  2. X_Min, Y_Min, Width, Height and Pixel_Count;
   --  3. only when 0 < Pixel_Count < Width * Height: Width * Height
   --     elements, 1 for a pixel of the region and 0 for any other, row
   --     after row starting at (X_Min, Y_Min).
   --
   --  The format code and the numbers in 2 take four elements each, least
   --  significant first, so the layout does not depend on the compiler or
   --  the platform.
   --
   --  'Read (and so 'Input) treats the stream as untrusted and checks
   --  every field before using it: the format code; for an empty region
   --  (Pixel_Count = 0) all four bounds 0; otherwise Width and Height
   --  positive, Width * Height and both X_Min + Width - 1 and
   --  Y_Min + Height - 1 at most Natural'Last, and Pixel_Count at most
   --  Width * Height. Only then are the pixel elements read: each must be
   --  0 or 1, their number of 1s must be Pixel_Count, and the bounding
   --  rectangle must be the smallest one around them (a 1 in its first
   --  and last row and column), as for every region this package makes.
   --  Memory for the pixels grows with the elements actually read, so a
   --  stream that claims a huge region but ends early allocates little.
   --  A field that fails a check, or a stream that ends before the region
   --  is complete, raises Ks_Image_File_Exception (as reading a malformed
   --  image from a stream does; see AMV.Images). On any failure, including
   --  an exception raised by the stream itself (which propagates
   --  unchanged), the target keeps the value it had.

private

   type Pixel_Region is new Ada.Finalization.Controlled with record
      Handle : AMV.Kernels.Regions.Ks_Pixel_Region;
      --  The kernel's handle, owned by this object; null for the empty
      --  region (the default).
   end record;

   overriding procedure Adjust (Region : in out Pixel_Region);
   --  Gives the copy its own handle (the kernel's duplicate). When that
   --  cannot be allocated, raises Storage_Error and leaves the copy
   --  empty.

   overriding procedure Finalize (Region : in out Pixel_Region);
   --  Destroys the handle and leaves the region empty; calling it again
   --  does nothing more.

   --  Stream attributes (see "Streams" above). Like every type that owns
   --  heap memory through an access component, Pixel_Region must not use
   --  the default attributes: they would write the pointer itself and
   --  read back whatever pointer the stream holds.

   procedure Write
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Pixel_Region);

   procedure Read
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Pixel_Region);

   for Pixel_Region'Write use Write;
   for Pixel_Region'Read use Read;

end AMV.Regions;
