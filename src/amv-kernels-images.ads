--  Kernel of AMV.Images: the pixels of CogImage8Grey and CogImage16Grey
--  (a CogImage24PlanarColor is three 8-bit images, one per plane) and the
--  coordinate space state of an image (ICogImage).
--
--  Pixel handles. An image's pixels live behind an owned handle
--  (Ks_Image_8_Grey, Ks_Image_16_Grey; C: ks_image_8_grey *,
--  ks_image_16_grey *, opaque) that ks_image_*_create returns and
--  ks_image_*_destroy frees. A handle holds Width and Height (both at least
--  1, Width * Height at most Max_Pixels) and the pixels, row after row: the
--  pixel at column X and row Y is Pixels (Y, X), both 0-based. The kernel
--  never shares pixels between handles; assignment sharing as in VisionPro
--  is done by the Ada API, which keeps a handle in a reference-counted box
--  (docs/DESIGN.md 9.1).
--
--  A null handle stands for an image without pixels (VisionPro: an
--  unallocated image): Width and Height give 0, Duplicate gives null,
--  Destroy does nothing, and every operation that needs pixels fails with
--  Image_No_Pixels ("Get_Pixel: the image has no pixels"). A handle that
--  is not null must come from create or duplicate and not be destroyed
--  yet (C cannot check that); a record that is inconsistent anyway fails
--  with Bad_Parameter. A coordinate outside the image fails with
--  Index_Out_Of_Range, which the Ada API turns into Constraint_Error.
--
--  SPARK does not allow comparing two handles, so an entry point cannot
--  tell whether a C caller passed the same image twice. None needs to:
--  every entry point that takes several handles only reads or writes
--  pixel values, never sizes or pixel arrays, so the same image given
--  twice cannot cause an invalid access; the results are then those of
--  doing the writes in the order of the arguments (Set_Plane of an image
--  onto itself changes nothing).
--
--  Trusted parts (SPARK_Mode Off bodies, listed in docs/PROOF.md):
--  allocation goes through a helper that turns a failed allocation into
--  Out_Of_Memory; the pixel copies from and to C memory (Get_Row and
--  Set_Row taking an address) view the C memory as an Ada array; and the
--  stream helpers convert the bits of a finite binary64 value to a
--  Long_Float. Everything else is proved.
--
--  Coordinate space state. An image has a coordinate space tree (the
--  record of AMV.Kernels.Coordinate_Spaces), a selected space name (a
--  Ks_Space_Name) and a Pixel_From_Root transform. The entry points
--  ks_image_* take them as separate arguments and implement the rules of
--  AMV.Images: "#" is pixel space, "." the selected space, every other
--  name a space of the tree; a selected name that is no longer in the
--  tree reads as "@".

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Interfaces;
with System;

with AMV.Kernels.Coordinate_Spaces;
with AMV.Kernels.Transforms;

package AMV.Kernels.Images with SPARK_Mode, Preelaborate is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  Postconditions compare pixels with their values on entry through
   --  the total ghost functions Pixels_Of, which can be evaluated on entry
   --  whatever the handle (contracts are proved, never executed).

   package KC renames AMV.Kernels.Coordinate_Spaces;
   package KT renames AMV.Kernels.Transforms;

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type KC.Ks_Space_Name;
   use type KC.Ks_Coordinate_Space_Tree;
   use type KT.Ks_Transform_2D_Linear;

   subtype Grey_8 is Interfaces.Unsigned_8;
   subtype Grey_16 is Interfaces.Unsigned_16;

   Max_Pixels : constant := 2**31 - 1;
   --  The largest Width * Height (C: KS_IMAGE_MAX_PIXELS), as in the Ada
   --  API before the kernel (Natural'Last pixels).

   ---------------------------------------------------------------------
   --  Pixel arrays and handles
   ---------------------------------------------------------------------

   type Grey_8_Matrix is
     array (Natural range <>, Natural range <>) of Grey_8;
   type Grey_16_Matrix is
     array (Natural range <>, Natural range <>) of Grey_16;
   --  Pixels indexed (Y, X): rows first, as in AMV.Images.

   type Grey_8_Row is array (Natural range <>) of Grey_8;
   type Grey_16_Row is array (Natural range <>) of Grey_16;

   type Grey_8_Pixels is access Grey_8_Matrix;
   type Grey_16_Pixels is access Grey_16_Matrix;

   type Ks_Image_8_Grey_Data is limited record
      Width  : Int32 := 0;
      Height : Int32 := 0;
      Pixels : Grey_8_Pixels;
   end record;
   --  What a handle designates (opaque for C). Valid_Image states its
   --  invariant.

   type Ks_Image_8_Grey is access Ks_Image_8_Grey_Data
     with Convention => C;
   --  C: ks_image_8_grey *.

   type Ks_Image_16_Grey_Data is limited record
      Width  : Int32 := 0;
      Height : Int32 := 0;
      Pixels : Grey_16_Pixels;
   end record;

   type Ks_Image_16_Grey is access Ks_Image_16_Grey_Data
     with Convention => C;
   --  C: ks_image_16_grey *.

   function Valid_Image
     (Image : access constant Ks_Image_8_Grey_Data) return Boolean
   is
     (Image /= null
      and then Image.Pixels /= null
      and then Image.Width >= 1 and then Image.Height >= 1
      and then Image.Pixels'First (1) = 0
      and then Image.Pixels'First (2) = 0
      and then Image.Pixels'Last (1) = Integer (Image.Height) - 1
      and then Image.Pixels'Last (2) = Integer (Image.Width) - 1);
   --  A handle with pixels: Height rows of Width pixels, indexed from 0.

   function Valid_Image
     (Image : access constant Ks_Image_16_Grey_Data) return Boolean
   is
     (Image /= null
      and then Image.Pixels /= null
      and then Image.Width >= 1 and then Image.Height >= 1
      and then Image.Pixels'First (1) = 0
      and then Image.Pixels'First (2) = 0
      and then Image.Pixels'Last (1) = Integer (Image.Height) - 1
      and then Image.Pixels'Last (2) = Integer (Image.Width) - 1);

   No_Grey_8  : constant Grey_8_Matrix (1 .. 0, 1 .. 0) :=
     [others => [others => 0]];
   No_Grey_16 : constant Grey_16_Matrix (1 .. 0, 1 .. 0) :=
     [others => [others => 0]];

   function Pixels_Of
     (Image : access constant Ks_Image_8_Grey_Data) return Grey_8_Matrix
   is
     (if Valid_Image (Image) then Image.Pixels.all else No_Grey_8)
   with Ghost;
   --  The pixels of a valid handle (empty otherwise), for contracts.

   function Pixels_Of
     (Image : access constant Ks_Image_16_Grey_Data) return Grey_16_Matrix
   is
     (if Valid_Image (Image) then Image.Pixels.all else No_Grey_16)
   with Ghost;

   type Image_Size is record
      Width, Height : Int32;
   end record
     with Ghost;

   function Size_Of
     (Image : access constant Ks_Image_8_Grey_Data) return Image_Size
   is
     (if Image = null then (0, 0) else (Image.Width, Image.Height))
   with Ghost;
   --  Width and Height ((0, 0) for null), for contracts that keep them.

   function Size_Of
     (Image : access constant Ks_Image_16_Grey_Data) return Image_Size
   is
     (if Image = null then (0, 0) else (Image.Width, Image.Height))
   with Ghost;

   ---------------------------------------------------------------------
   --  8-bit grey images (CogImage8Grey)
   ---------------------------------------------------------------------

   procedure Create
     (Width, Height : Int32;
      Value         : Grey_8;
      Image         : out Ks_Image_8_Grey;
      Status        : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_8_grey_create",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then Image.Width = Width
                            and then Image.Height = Height
                            and then (for all Y in Image.Pixels'Range (1)
                                      => (for all X in Image.Pixels'Range (2)
                                          => Image.Pixels (Y, X) = Value))
                       else Image = null);
   --  A new Width x Height image with every pixel set to Value.
   --  Bad_Parameter unless Width and Height are at least 1 and Width *
   --  Height is at most Max_Pixels; Out_Of_Memory when the pixels cannot
   --  be allocated. Image is null when the call fails.

   procedure Destroy
     (Image  : in out Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_8_grey_destroy",
     Post => Valid (Status) and then Succeeded (Status) and then Image = null;
   --  Frees the image and sets Image to null. Nothing for null. Never
   --  fails.

   procedure Width
     (Image  : access constant Ks_Image_8_Grey_Data;
      Result : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_8_grey_width",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then Image /= null
                       then Valid_Image (Image) and then Result = Image.Width
                       else Result = 0);
   --  The width in pixels; 0 for null.

   procedure Height
     (Image  : access constant Ks_Image_8_Grey_Data;
      Result : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_8_grey_height",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then Image /= null
                       then Valid_Image (Image)
                            and then Result = Image.Height
                       else Result = 0);
   --  The height in pixels; 0 for null.

   procedure Get_Pixel
     (Image  : access constant Ks_Image_8_Grey_Data;
      X, Y   : Int32;
      Value  : out Grey_8;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_8_grey_get_pixel",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then X in 0 .. Image.Width - 1
                            and then Y in 0 .. Image.Height - 1
                            and then Value
                                       = Image.Pixels (Natural (Y),
                                                       Natural (X))
                       else Value = 0);
   --  The pixel at column X, row Y. Index_Out_Of_Range unless X is in
   --  0 .. Width - 1 and Y in 0 .. Height - 1.

   procedure Set_Pixel
     (Image  : Ks_Image_8_Grey;
      X, Y   : Int32;
      Value  : Grey_8;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_8_grey_set_pixel",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range
             and then Size_Of (Image) = Size_Of (Image)'Old
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then X in 0 .. Image.Width - 1
                            and then Y in 0 .. Image.Height - 1
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
   --  for Get_Pixel; a failed call changes nothing.

   procedure Fill
     (Image  : Ks_Image_8_Grey;
      Value  : Grey_8;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_8_grey_fill",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then Size_Of (Image) = Size_Of (Image)'Old
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then (for all Y in Image.Pixels'Range (1)
                                      => (for all X in Image.Pixels'Range (2)
                                          => Image.Pixels (Y, X) = Value))
                       else Pixels_Of (Image) = Pixels_Of (Image)'Old);
   --  Sets every pixel to Value.

   procedure Duplicate
     (Image  : access constant Ks_Image_8_Grey_Data;
      Result : out Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_8_grey_duplicate",
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
   --  Image (VisionPro: Copy (CopyPixels)); null for null.

   procedure Get_Row
     (Image  : access constant Ks_Image_8_Grey_Data;
      Y      : Int32;
      Row    : System.Address;
      Length : Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_8_grey_get_row",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range;
   --  Copies row Y into the Length bytes at Row (C: uint8_t *). The
   --  checks, in order: Image (Image_No_Pixels, Bad_Parameter); Y in
   --  0 .. Height - 1 and Length = Width (Index_Out_Of_Range); Row not
   --  null (Bad_Parameter). Trusted: the memory at Row is viewed as an
   --  array of Length bytes, which C must provide.

   procedure Set_Row
     (Image  : Ks_Image_8_Grey;
      Y      : Int32;
      Row    : System.Address;
      Length : Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_8_grey_set_row",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range;
   --  Copies the Length bytes at Row into row Y; checks as for Get_Row.

   ---------------------------------------------------------------------
   --  16-bit grey images (CogImage16Grey)
   ---------------------------------------------------------------------

   --  The same operations and failures as for 8-bit images.

   procedure Create
     (Width, Height : Int32;
      Value         : Grey_16;
      Image         : out Ks_Image_16_Grey;
      Status        : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_16_grey_create",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then Image.Width = Width
                            and then Image.Height = Height
                            and then (for all Y in Image.Pixels'Range (1)
                                      => (for all X in Image.Pixels'Range (2)
                                          => Image.Pixels (Y, X) = Value))
                       else Image = null);

   procedure Destroy
     (Image  : in out Ks_Image_16_Grey;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_16_grey_destroy",
     Post => Valid (Status) and then Succeeded (Status) and then Image = null;

   procedure Width
     (Image  : access constant Ks_Image_16_Grey_Data;
      Result : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_16_grey_width",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then Image /= null
                       then Valid_Image (Image) and then Result = Image.Width
                       else Result = 0);

   procedure Height
     (Image  : access constant Ks_Image_16_Grey_Data;
      Result : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_16_grey_height",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then Image /= null
                       then Valid_Image (Image)
                            and then Result = Image.Height
                       else Result = 0);

   procedure Get_Pixel
     (Image  : access constant Ks_Image_16_Grey_Data;
      X, Y   : Int32;
      Value  : out Grey_16;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_16_grey_get_pixel",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then X in 0 .. Image.Width - 1
                            and then Y in 0 .. Image.Height - 1
                            and then Value
                                       = Image.Pixels (Natural (Y),
                                                       Natural (X))
                       else Value = 0);

   procedure Set_Pixel
     (Image  : Ks_Image_16_Grey;
      X, Y   : Int32;
      Value  : Grey_16;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_16_grey_set_pixel",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range
             and then Size_Of (Image) = Size_Of (Image)'Old
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then X in 0 .. Image.Width - 1
                            and then Y in 0 .. Image.Height - 1
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

   procedure Fill
     (Image  : Ks_Image_16_Grey;
      Value  : Grey_16;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_16_grey_fill",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then Size_Of (Image) = Size_Of (Image)'Old
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then (for all Y in Image.Pixels'Range (1)
                                      => (for all X in Image.Pixels'Range (2)
                                          => Image.Pixels (Y, X) = Value))
                       else Pixels_Of (Image) = Pixels_Of (Image)'Old);

   procedure Duplicate
     (Image  : access constant Ks_Image_16_Grey_Data;
      Result : out Ks_Image_16_Grey;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_16_grey_duplicate",
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

   procedure Get_Row
     (Image  : access constant Ks_Image_16_Grey_Data;
      Y      : Int32;
      Row    : System.Address;
      Length : Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_16_grey_get_row",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range;
   --  Row is a uint16_t array of Length elements. Trusted, as for 8 bits.

   procedure Set_Row
     (Image  : Ks_Image_16_Grey;
      Y      : Int32;
      Row    : System.Address;
      Length : Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_16_grey_set_row",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range;

   ---------------------------------------------------------------------
   --  24-bit planar colour images (CogImage24PlanarColor)
   ---------------------------------------------------------------------

   --  A colour image is three 8-bit images of the same size, Red, Green
   --  and Blue: all three null for an image without pixels. Any other mix
   --  (one null, different sizes, an invalid handle) fails with
   --  Bad_Parameter ("<Operation>: Red, Green and Blue must be planes of
   --  the same size"). Failures otherwise as for 8-bit images.

   procedure Create_Color
     (Width, Height                         : Int32;
      Red_Value, Green_Value, Blue_Value    : Grey_8;
      Red, Green, Blue                      : out Ks_Image_8_Grey;
      Status                                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_24_planar_color_create",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Image (Red) and then Valid_Image (Green)
                            and then Valid_Image (Blue)
                            and then Red.Width = Width
                            and then Red.Height = Height
                            and then Green.Width = Width
                            and then Green.Height = Height
                            and then Blue.Width = Width
                            and then Blue.Height = Height
                       else Red = null and then Green = null
                            and then Blue = null);
   --  Three new planes filled with the given values; all three null when
   --  the call fails (nothing is leaked when one allocation fails).

   procedure Get_Pixel_Color
     (Red, Green, Blue                   : access constant
                                             Ks_Image_8_Grey_Data;
      X, Y                               : Int32;
      Red_Value, Green_Value, Blue_Value : out Grey_8;
      Status                             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_24_planar_color_get_pixel",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Image (Red) and then Valid_Image (Green)
                            and then Valid_Image (Blue)
                            and then X in 0 .. Red.Width - 1
                            and then Y in 0 .. Red.Height - 1
                            and then Red_Value
                                       = Red.Pixels (Natural (Y), Natural (X))
                            and then Green_Value
                                       = Green.Pixels (Natural (Y),
                                                       Natural (X))
                            and then Blue_Value
                                       = Blue.Pixels (Natural (Y),
                                                      Natural (X))
                       else Red_Value = 0 and then Green_Value = 0
                            and then Blue_Value = 0);

   procedure Set_Pixel_Color
     (Red, Green, Blue                   : Ks_Image_8_Grey;
      X, Y                               : Int32;
      Red_Value, Green_Value, Blue_Value : Grey_8;
      Status                             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_24_planar_color_set_pixel",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range
             and then Size_Of (Red) = Size_Of (Red)'Old
             and then Size_Of (Green) = Size_Of (Green)'Old
             and then Size_Of (Blue) = Size_Of (Blue)'Old
             and then (if Succeeded (Status)
                       then Valid_Image (Red) and then Valid_Image (Green)
                            and then Valid_Image (Blue)
                            and then X in 0 .. Red.Width - 1
                            and then Y in 0 .. Red.Height - 1
                            and then Red.Pixels (Natural (Y), Natural (X))
                                       = Red_Value
                            and then Green.Pixels (Natural (Y), Natural (X))
                                       = Green_Value
                            and then Blue.Pixels (Natural (Y), Natural (X))
                                       = Blue_Value
                       else Pixels_Of (Red) = Pixels_Of (Red)'Old
                            and then Pixels_Of (Green) = Pixels_Of (Green)'Old
                            and then Pixels_Of (Blue) = Pixels_Of (Blue)'Old);
   --  Sets the pixel at (X, Y) of every plane.

   procedure Set_Plane
     (Plane  : Ks_Image_8_Grey;
      Pixels : access constant Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_24_planar_color_set_plane",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then Size_Of (Plane) = Size_Of (Plane)'Old
             and then (if Succeeded (Status)
                       then Valid_Image (Plane) and then Valid_Image (Pixels)
                            and then Plane.Pixels.all = Pixels.Pixels.all
                       else Pixels_Of (Plane) = Pixels_Of (Plane)'Old);
   --  Copies the pixels of Pixels into Plane, one plane of a colour image
   --  (null for a colour image without pixels). Image_No_Pixels when
   --  Pixels is null ("Set_Plane: Pixels has no pixels"); Bad_Parameter
   --  for an invalid handle and when the sizes differ ("Set_Plane: Pixels
   --  is 3 x 3 but the colour image is 4 x 3", a null Plane counting as
   --  0 x 0).

   procedure Duplicate_Color
     (Red, Green, Blue             : access constant Ks_Image_8_Grey_Data;
      New_Red, New_Green, New_Blue : out Ks_Image_8_Grey;
      Status                       : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_24_planar_color_duplicate",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) and then Red /= null
                       then Valid_Image (Red) and then Valid_Image (Green)
                            and then Valid_Image (Blue)
                            and then Valid_Image (New_Red)
                            and then Valid_Image (New_Green)
                            and then Valid_Image (New_Blue)
                            and then New_Red.Pixels.all = Red.Pixels.all
                            and then New_Green.Pixels.all = Green.Pixels.all
                            and then New_Blue.Pixels.all = Blue.Pixels.all
                       else New_Red = null and then New_Green = null
                            and then New_Blue = null);
   --  Copies of the three planes (three nulls for three nulls).

   ---------------------------------------------------------------------
   --  The coordinate space state of an image (ICogImage)
   ---------------------------------------------------------------------

   --  Tree is the image's tree, Selected the selected space name as the
   --  image stores it, Pixel_From_Root the transform from root space "@"
   --  to pixel space "#". Every entry point first checks
   --  KC.Valid_Tree (Tree) and fails with Bad_Parameter ("Tree is not a
   --  valid coordinate space tree") otherwise. Names returned are clean
   --  (NUL characters after their text).

   Root_Space_Name  : constant KC.Ks_Space_Name :=
     (Length => 1,
      Text   => [1 => KC.Root_Character, others => ASCII.NUL]);
   Pixel_Space_Name : constant KC.Ks_Space_Name :=
     (Length => 1,
      Text   => [1 => KC.Pixel_Character, others => ASCII.NUL]);

   procedure Selected_Space_Name
     (Tree     : KC.Ks_Coordinate_Space_Tree;
      Selected : KC.Ks_Space_Name;
      Result   : out KC.Ks_Space_Name;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_selected_space_name",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then KC.Fits (Result)
             and then (if not Succeeded (Status) then Result.Length = 0);
   --  The selection as it reads: Selected when it is "#" or a space of
   --  Tree, otherwise "@" (a selected space removed from the tree reads as
   --  the root). Storing the result settles a removed selection, so that
   --  it does not come back with a space of the same name.

   procedure Set_Selected_Space_Name
     (Tree       : KC.Ks_Coordinate_Space_Tree;
      Selected   : in out KC.Ks_Space_Name;
      Space_Name : KC.Ks_Space_Name;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_set_selected_space_name",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
             and then (if Succeeded (Status) then KC.Fits (Selected)
                       else Selected = Selected'Old);
   --  Selects Space_Name: "#" or a space of Tree; "." keeps the selection
   --  as Selected_Space_Name reads it. Image_Bad_Selected_Space_Name
   --  otherwise ("Selected_Space_Name: no space named "X" in the image's
   --  coordinate space tree"), leaving Selected unchanged.

   procedure Resolve_Space_Name
     (Tree       : KC.Ks_Coordinate_Space_Tree;
      Selected   : KC.Ks_Space_Name;
      Space_Name : KC.Ks_Space_Name;
      Result     : out KC.Ks_Space_Name;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_resolve_space_name",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
             and then KC.Fits (Result)
             and then (if not Succeeded (Status) then Result.Length = 0);
   --  "." becomes the selection as it reads; "#" and the spaces of Tree
   --  stay as they are; any other name fails with
   --  Image_Bad_Selected_Space_Name.

   procedure Get_Transform
     (Tree            : KC.Ks_Coordinate_Space_Tree;
      Selected        : KC.Ks_Space_Name;
      Pixel_From_Root : KT.Ks_Transform_2D_Linear;
      To_Space_Name   : KC.Ks_Space_Name;
      From_Space_Name : KC.Ks_Space_Name;
      Result          : out KT.Ks_Transform_2D_Linear;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_get_transform",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Transform_Singular
             and then (if Succeeded (Status) then KT.Bounded (Result));
   --  The transform from From_Space_Name to To_Space_Name, both resolved
   --  as by Resolve_Space_Name: exactly the identity when they resolve to
   --  the same name; between two spaces of the tree, the tree's
   --  Get_Transform (To, From); into "#",
   --  Pixel_From_Root.Compose (Tree.Get_Transform ("@", From)); out of
   --  "#", Tree.Get_Transform (To, "@").Compose (Pixel_From_Root.Invert).
   --  Bad_Parameter when Pixel_From_Root is not within the bound of
   --  AMV.Kernels.Transforms, or when a composition leaves it;
   --  Transform_Singular when an inverse is not within it. Result is the
   --  identity when the call fails.

   procedure Selection_For_New_Tree
     (Tree     : KC.Ks_Coordinate_Space_Tree;
      Selected : in out KC.Ks_Space_Name;
      New_Tree : KC.Ks_Coordinate_Space_Tree;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_selection_for_new_tree",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then KC.Fits (Selected)
                       else Selected = Selected'Old);
   --  The selection rule of Set_Coordinate_Space_Tree: the selection as it
   --  reads in Tree is kept when it is "#" or a space of New_Tree, and
   --  becomes "@" otherwise. The caller then replaces Tree by New_Tree.
   --  Bad_Parameter when either tree is not valid.

   procedure Set_Pixel_From_Root_Transform
     (Pixel_From_Root : in out KT.Ks_Transform_2D_Linear;
      Transform       : KT.Ks_Transform_2D_Linear;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_set_pixel_from_root_transform",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Transform_Singular
             and then (if Succeeded (Status)
                       then KT.Bounded (Pixel_From_Root)
                            and then Pixel_From_Root = Transform
                       else Pixel_From_Root = Pixel_From_Root'Old);
   --  Stores Transform exactly as given. Bad_Parameter unless it is finite
   --  and within the bound of AMV.Kernels.Transforms; Transform_Singular
   --  unless it is invertible within that bound (so that Get_Transform
   --  can always map out of "#").

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   --  Lean per-pixel access (AMV.Images.Get_Pixel and Set_Pixel, which
   --  the packages built on AMV.Images call once per pixel). Done is True
   --  exactly when the entry point of the same name succeeds, and the
   --  effect is then the same; nothing happens otherwise, and the Ada API
   --  calls the entry point to obtain the failure status. Building no
   --  status on success makes a call several times cheaper.

   function Pixel_Exists
     (Image : access constant Ks_Image_8_Grey_Data;
      X, Y  : Int32) return Boolean
   is
     (Valid_Image (Image)
      and then X in 0 .. Image.Width - 1
      and then Y in 0 .. Image.Height - 1);
   --  When Get_Pixel and Set_Pixel succeed.

   function Pixel_Exists
     (Image : access constant Ks_Image_16_Grey_Data;
      X, Y  : Int32) return Boolean
   is
     (Valid_Image (Image)
      and then X in 0 .. Image.Width - 1
      and then Y in 0 .. Image.Height - 1);

   function Pixel_Exists
     (Red, Green, Blue : access constant Ks_Image_8_Grey_Data;
      X, Y             : Int32) return Boolean
   is
     (Valid_Image (Red) and then Valid_Image (Green)
      and then Valid_Image (Blue)
      and then Green.Width = Red.Width and then Green.Height = Red.Height
      and then Blue.Width = Red.Width and then Blue.Height = Red.Height
      and then X in 0 .. Red.Width - 1
      and then Y in 0 .. Red.Height - 1);
   --  When Get_Pixel_Color and Set_Pixel_Color succeed.

   procedure Try_Get_Pixel
     (Image : access constant Ks_Image_8_Grey_Data;
      X, Y  : Int32;
      Value : out Grey_8;
      Done  : out Boolean)
   with
     Inline,
     Post => Done = Pixel_Exists (Image, X, Y)
             and then (if Done
                       then Value = Image.Pixels (Natural (Y), Natural (X))
                       else Value = 0);

   procedure Try_Set_Pixel
     (Image : Ks_Image_8_Grey;
      X, Y  : Int32;
      Value : Grey_8;
      Done  : out Boolean)
   with
     Inline,
     Post => Done = Pixel_Exists (Image, X, Y)
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

   procedure Try_Get_Pixel
     (Image : access constant Ks_Image_16_Grey_Data;
      X, Y  : Int32;
      Value : out Grey_16;
      Done  : out Boolean)
   with
     Inline,
     Post => Done = Pixel_Exists (Image, X, Y)
             and then (if Done
                       then Value = Image.Pixels (Natural (Y), Natural (X))
                       else Value = 0);

   procedure Try_Set_Pixel
     (Image : Ks_Image_16_Grey;
      X, Y  : Int32;
      Value : Grey_16;
      Done  : out Boolean)
   with
     Inline,
     Post => Done = Pixel_Exists (Image, X, Y)
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

   procedure Try_Get_Pixel_Color
     (Red, Green, Blue                   : access constant
                                             Ks_Image_8_Grey_Data;
      X, Y                               : Int32;
      Red_Value, Green_Value, Blue_Value : out Grey_8;
      Done                               : out Boolean)
   with
     Inline,
     Post => Done = Pixel_Exists (Red, Green, Blue, X, Y)
             and then (if Done
                       then Red_Value = Red.Pixels (Natural (Y), Natural (X))
                            and then Green_Value
                                       = Green.Pixels (Natural (Y),
                                                       Natural (X))
                            and then Blue_Value
                                       = Blue.Pixels (Natural (Y),
                                                      Natural (X))
                       else Red_Value = 0 and then Green_Value = 0
                            and then Blue_Value = 0);

   procedure Try_Set_Pixel_Color
     (Red, Green, Blue                   : Ks_Image_8_Grey;
      X, Y                               : Int32;
      Red_Value, Green_Value, Blue_Value : Grey_8;
      Done                               : out Boolean)
   with
     Inline,
     Post => Done = Pixel_Exists (Red, Green, Blue, X, Y)'Old
             and then Size_Of (Red) = Size_Of (Red)'Old
             and then Size_Of (Green) = Size_Of (Green)'Old
             and then Size_Of (Blue) = Size_Of (Blue)'Old
             and then (if Done
                       then Valid_Image (Red) and then Valid_Image (Green)
                            and then Valid_Image (Blue)
                            and then Red.Pixels (Natural (Y), Natural (X))
                                       = Red_Value
                            and then Green.Pixels (Natural (Y), Natural (X))
                                       = Green_Value
                            and then Blue.Pixels (Natural (Y), Natural (X))
                                       = Blue_Value
                       else Pixels_Of (Red) = Pixels_Of (Red)'Old
                            and then Pixels_Of (Green) = Pixels_Of (Green)'Old
                            and then Pixels_Of (Blue) = Pixels_Of (Blue)'Old);

   --  Rows and matrices (AMV.Images.Get_Row, Set_Row, To_Matrix,
   --  From_Matrix). A row array may have any bounds; its length must be
   --  Width (Index_Out_Of_Range otherwise, which the Ada API reports as
   --  Constraint_Error). Messages name the Ada operation.

   procedure Get_Row
     (Image  : access constant Ks_Image_8_Grey_Data;
      Y      : Int32;
      Row    : out Grey_8_Row;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then Y in 0 .. Image.Height - 1
                            and then Row'Length = Image.Width
                            and then (for all I in Row'Range
                                      => Row (I)
                                           = Image.Pixels (Natural (Y),
                                                           I - Row'First)));
   --  Copies row Y into Row (Gold: element by element).

   procedure Set_Row
     (Image  : Ks_Image_8_Grey;
      Y      : Int32;
      Row    : Grey_8_Row;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range
             and then Size_Of (Image) = Size_Of (Image)'Old
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then Y in 0 .. Image.Height - 1
                            and then Row'Length = Image.Width
                            and then
                              (for all J in Image.Pixels'Range (1)
                               => (for all I in Image.Pixels'Range (2)
                                   => Image.Pixels (J, I)
                                        = (if J = Natural (Y)
                                           then Row (Row'First + I)
                                           else Pixels_Of (Image)'Old (J, I))))
                       else Pixels_Of (Image) = Pixels_Of (Image)'Old);
   --  Copies Row into row Y, and changes no other row (Gold).

   procedure Get_Row
     (Image  : access constant Ks_Image_16_Grey_Data;
      Y      : Int32;
      Row    : out Grey_16_Row;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then Y in 0 .. Image.Height - 1
                            and then Row'Length = Image.Width
                            and then (for all I in Row'Range
                                      => Row (I)
                                           = Image.Pixels (Natural (Y),
                                                           I - Row'First)));

   procedure Set_Row
     (Image  : Ks_Image_16_Grey;
      Y      : Int32;
      Row    : Grey_16_Row;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range
             and then Size_Of (Image) = Size_Of (Image)'Old
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then Y in 0 .. Image.Height - 1
                            and then Row'Length = Image.Width
                            and then
                              (for all J in Image.Pixels'Range (1)
                               => (for all I in Image.Pixels'Range (2)
                                   => Image.Pixels (J, I)
                                        = (if J = Natural (Y)
                                           then Row (Row'First + I)
                                           else Pixels_Of (Image)'Old (J, I))))
                       else Pixels_Of (Image) = Pixels_Of (Image)'Old);

   procedure Matrix_Bounds
     (Image                 : access constant Ks_Image_8_Grey_Data;
      Last_Row, Last_Column : out Natural;
      Status                : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then Last_Row = Image.Pixels'Last (1)
                            and then Last_Column = Image.Pixels'Last (2)
                       else Last_Row = 0 and then Last_Column = 0);
   --  Height - 1 and Width - 1, the last indexes of To_Matrix's result.
   --  Image_No_Pixels ("To_Matrix: the image has no pixels") for null.

   procedure Get_Matrix
     (Image  : access constant Ks_Image_8_Grey_Data;
      Matrix : out Grey_8_Matrix;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then Matrix'Length (1) = Image.Height
                            and then Matrix'Length (2) = Image.Width
                            and then
                              (for all Y in Image.Pixels'Range (1)
                               => (for all X in Image.Pixels'Range (2)
                                   => Matrix (Matrix'First (1) + Y,
                                              Matrix'First (2) + X)
                                        = Image.Pixels (Y, X))));
   --  Copies the pixels into Matrix, whose lengths must be Height and
   --  Width (Index_Out_Of_Range otherwise); the bounds may be any.

   procedure Create_From_Matrix
     (Matrix : Grey_8_Matrix;
      Image  : out Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Image (Image)
                            and then Image.Height = Matrix'Length (1)
                            and then Image.Width = Matrix'Length (2)
                            and then
                              (for all Y in Image.Pixels'Range (1)
                               => (for all X in Image.Pixels'Range (2)
                                   => Image.Pixels (Y, X)
                                        = Matrix (Matrix'First (1) + Y,
                                                  Matrix'First (2) + X)))
                       else Image = null);
   --  A new image with the pixels of Matrix (any bounds): pixel (X, Y) is
   --  Matrix (Matrix'First (1) + Y, Matrix'First (2) + X). Bad_Parameter
   --  when a dimension is empty ("From_Matrix: the matrix must have at
   --  least one row and one column") or the image would be too large.

   --  Streams (the stream attributes of AMV.Images, whose spec describes
   --  the layout). The Ada API reads and writes the stream; the kernel
   --  checks every field read and converts transforms and pixels to and
   --  from their stream form. Every failure is Image_File, with a message
   --  that starts with the attribute ("Ks_Image_8_Grey'Read: ").

   subtype U32 is Interfaces.Unsigned_32;
   subtype U64 is Interfaces.Unsigned_64;

   Code_Spaces_Part : constant U32 := 16#4B53_4900#;
   Code_Grey_8      : constant U32 := 16#4B53_4908#;
   Code_Grey_16     : constant U32 := 16#4B53_4910#;
   Code_Colour      : constant U32 := 16#4B53_4918#;
   --  Format codes: "KSI" followed by the layout of what follows.

   subtype Stream_Code is U32
     with Static_Predicate =>
       Stream_Code in Code_Spaces_Part | Code_Grey_8 | Code_Grey_16
                    | Code_Colour;
   --  Names the attribute in messages: Ks_Image'Read, Ks_Image_8_Grey'Read,
   --  Ks_Image_16_Grey'Read, Ks_Image_24_Planar_Color'Read.

   type Transform_Bits is array (1 .. 6) of U64;
   --  A, B, C, D, Translation_X and Translation_Y as the bits of their IEEE
   --  754 binary64 values.

   function To_Bits (Transform : KT.Ks_Transform_2D_Linear)
      return Transform_Bits;

   procedure Check_Read_Code
     (Expected : Stream_Code;
      Code     : U32;
      Status   : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Image_File
                and then (if Succeeded (Status) then Code = Expected);
   --  The format code read must be Expected.

   procedure Check_Read_Size
     (Code                  : Stream_Code;
      Width, Height         : U32;
      Image_Width           : out Int32;
      Image_Height          : out Int32;
      Status                : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Image_File
                and then (if Succeeded (Status)
                          then (Image_Width = 0 and then Image_Height = 0)
                               or else (Image_Width >= 1
                                        and then Image_Height >= 1
                                        and then Int64 (Image_Width)
                                                   * Int64 (Image_Height)
                                                   <= Max_Pixels)
                          else Image_Width = 0 and then Image_Height = 0);
   --  The size read: 0 x 0 (no pixels) or within the limits of Create.

   procedure Read_Pixel_From_Root
     (Code   : Stream_Code;
      Bits   : Transform_Bits;
      Result : out KT.Ks_Transform_2D_Linear;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Image_File
                and then (if Succeeded (Status) then KT.Bounded (Result));
   --  The pixel-from-root transform read: every entry finite (checked on
   --  the bits), within the bound and invertible within it, as
   --  Set_Pixel_From_Root_Transform requires. Identity on failure.

   procedure Check_Read_Space_Count
     (Code   : Stream_Code;
      Count  : U32;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Image_File
                and then (if Succeeded (Status)
                          then Count <= KC.Max_Spaces - 1);
   --  The number of spaces other than "@" read must fit in a tree.

   procedure Check_Read_Name_Length
     (Code   : Stream_Code;
      Length : U32;
      Count  : out Natural;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Image_File
                and then Count <= KC.Max_Name_Length
                and then (if Succeeded (Status) then Count = Natural (Length)
                          else Count = 0);
   --  The length read for a space name must be at most Max_Name_Length.

   procedure Read_Space
     (Code   : Stream_Code;
      Tree   : in out KC.Ks_Coordinate_Space_Tree;
      Name   : KC.Ks_Space_Name;
      Bits   : Transform_Bits;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Image_File
                and then (if Succeeded (Status) then KC.Valid_Tree (Tree)
                          else Tree = Tree'Old);
   --  Adds the space read (its full name and its Parent_From_Child
   --  transform as bits) to Tree: the transform must be finite, and the
   --  space must pass KC.Add_Read_Space (its parent read before it, not
   --  repeated, a valid name and transform).

   procedure Read_Selection
     (Code     : Stream_Code;
      Tree     : KC.Ks_Coordinate_Space_Tree;
      Name     : KC.Ks_Space_Name;
      Selected : out KC.Ks_Space_Name;
      Status   : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Image_File
                and then KC.Fits (Selected);
   --  The selected name read must be "#" or a space of Tree; Selected is
   --  then that name, otherwise "@".

   procedure Stream_Ended
     (Code   : Stream_Code;
      Status : out Ks_Status)
   with Post => Valid (Status) and then Status.Failure = Failure_Image_File;
   --  The failure for a stream that ends before the image is complete.

   procedure Stream_Space_Count
     (Tree   : KC.Ks_Coordinate_Space_Tree;
      Count  : out U32;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then Count <= KC.Max_Spaces - 1;
   --  The number of spaces other than "@", as the stream stores it.

   procedure Create_For_Read
     (Width, Height : Int32;
      Image         : out Ks_Image_8_Grey;
      Status        : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Out_Of_Memory
                and then (if Succeeded (Status)
                          then (if Width = 0 and then Height = 0
                                then Image = null
                                else Valid_Image (Image))
                          else Image = null);
   --  Null for the size 0 x 0 of an image without pixels, otherwise
   --  Create (Width, Height, 0).

   procedure Create_For_Read
     (Width, Height : Int32;
      Image         : out Ks_Image_16_Grey;
      Status        : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Out_Of_Memory
                and then (if Succeeded (Status)
                          then (if Width = 0 and then Height = 0
                                then Image = null
                                else Valid_Image (Image))
                          else Image = null);

   procedure Create_Color_For_Read
     (Width, Height    : Int32;
      Red, Green, Blue : out Ks_Image_8_Grey;
      Status           : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Out_Of_Memory
                and then (if not Succeeded (Status)
                               or else (Width = 0 and then Height = 0)
                          then Red = null and then Green = null
                               and then Blue = null);

   --  Pixels in stream form: row after row from (0, 0), one byte per
   --  8-bit pixel and two per 16-bit pixel (the least significant byte
   --  first). A Pixel_Position is the next pixel to convert; the Ada API
   --  moves through an image in chunks: Next_Chunk gives the number of
   --  bytes of the next chunk (at most Limit; 0 at the end or for an image
   --  without pixels), Get_Bytes converts the next Bytes'Length bytes from
   --  the image and Put_Bytes into it, both moving Position on.

   type Pixel_Position is record
      Row    : Int32 := 0;
      Column : Int32 := 0;
   end record;

   function Valid_Position
     (Width, Height : Int32;
      Position      : Pixel_Position) return Boolean
   is
     ((Position.Row in 0 .. Height - 1
       and then Position.Column in 0 .. Width - 1)
      or else (Position.Row = Height and then Position.Column = 0))
   with Pre => Width >= 1 and then Height >= 1;
   --  Position is a pixel of the image, or the end (row Height, column 0).

   procedure Next_Chunk
     (Image    : access constant Ks_Image_8_Grey_Data;
      Position : Pixel_Position;
      Limit    : Positive;
      Length   : out Natural)
   with Post => Length <= Limit;

   procedure Next_Chunk
     (Image    : access constant Ks_Image_16_Grey_Data;
      Position : Pixel_Position;
      Limit    : Positive;
      Length   : out Natural)
   with Pre  => Limit >= 2,
        Post => Length <= Limit and then Length mod 2 = 0;
   --  An even number of bytes (whole pixels).

   procedure Get_Bytes
     (Image    : access constant Ks_Image_8_Grey_Data;
      Position : in out Pixel_Position;
      Bytes    : out Grey_8_Row;
      Status   : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter;
   --  Bad_Parameter when Position is not valid or Bytes is longer than
   --  what is left.

   procedure Get_Bytes
     (Image    : access constant Ks_Image_16_Grey_Data;
      Position : in out Pixel_Position;
      Bytes    : out Grey_8_Row;
      Status   : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter;
   --  Bytes'Length must also be even.

   procedure Put_Bytes
     (Image    : Ks_Image_8_Grey;
      Position : in out Pixel_Position;
      Bytes    : Grey_8_Row;
      Status   : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                and then Size_Of (Image) = Size_Of (Image)'Old;

   procedure Put_Bytes
     (Image    : Ks_Image_16_Grey;
      Position : in out Pixel_Position;
      Bytes    : Grey_8_Row;
      Status   : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                and then Size_Of (Image) = Size_Of (Image)'Old;

end AMV.Kernels.Images;
