--  Images: the counterparts of ICogImage, CogImage8Grey, CogImage16Grey and
--  CogImage24PlanarColor.
--
--  Pixel (X, Y) is column X, row Y, 0-based, origin at the upper left. The
--  centre of pixel (X, Y) is at (X, Y) in pixel space "#".
--
--  Pixels have .NET reference semantics: assigning an image shares its
--  pixel buffer (the buffer is reference counted and freed with its last
--  user), so Set_Pixel through one copy is visible through the other. Use
--  Copy for an independent image. The coordinate space tree, the selected
--  space name and the pixel-from-root transform are plain values: they are
--  copied by assignment.
--
--  Every image carries a coordinate space tree (see AMV.Coordinate_Spaces)
--  rooted at "@", a Pixel_From_Root_Transform that relates the root space to
--  pixel space (identity by default), and a Selected_Space_Name ("@" by
--  default). Get_Transform accepts every name in the tree plus "#" (pixel
--  space) and "." (the selected space).
--
--  An unallocated image has Width = Height = 0. Pixel access on it raises
--  Ks_Image_No_Pixels_Exception; out-of-range coordinates raise
--  Constraint_Error. Create and Allocate raise Ks_Bad_Parameter_Exception
--  when Width * Height exceeds Natural'Last (2**31 - 1 pixels), and
--  Storage_Error when the pixels cannot be allocated.
--
--  The work is done by the SPARK kernel AMV.Kernels.Images (the C
--  functions ks_image_8_grey_*, ks_image_16_grey_*,
--  ks_image_24_planar_color_* and ks_image_*): it owns the pixels of an
--  image behind a handle (one handle per plane of a colour image), checks
--  every coordinate and size, and implements the coordinate space rules
--  below. The kernel never shares pixels; this package keeps each handle in
--  a reference-counted box, which gives assignment its sharing semantics.
--  The kernel's failures map to the exceptions documented here (an index
--  failure to Constraint_Error, an allocation failure to Storage_Error).
--
--  The stream attributes of the image types store an image by value; see
--  "Streams" at the end of the visible part.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Finalization;
with Interfaces;

with AMV.Coordinate_Spaces;
with AMV.Transforms;

private with Ada.Streams;
private with AMV.Kernels.Coordinate_Spaces;
private with AMV.Kernels.Images;
private with AMV.Kernels.Transforms;

package AMV.Images is

   subtype Grey_8 is Interfaces.Unsigned_8;
   subtype Grey_16 is Interfaces.Unsigned_16;

   type Ks_Image_Copy_Mode_Constants is
     (Copy_Pixels, Share_Pixels, No_Pixels);
   --  How Copy treats the pixels (CogImageCopyModeConstants):
   --  Copy_Pixels:  the copy gets its own pixel buffer.
   --  Share_Pixels: the copy shares the pixel buffer (like assignment).
   --  No_Pixels:    the copy has no pixels (it is unallocated, Width =
   --                Height = 0); only the coordinate space state is
   --                copied.

   type Ks_Image_Plane_Constants is (Red, Green, Blue);

   ---------------------------------------------------------------------
   --  ICogImage
   ---------------------------------------------------------------------

   type Ks_Image is abstract new Ada.Finalization.Controlled with private;

   function Width (Image : Ks_Image) return Natural;
   function Height (Image : Ks_Image) return Natural;

   function Allocated (Image : Ks_Image) return Boolean;
   --  True when the image holds pixels (Width > 0 and Height > 0).

   function Selected_Space_Name (Image : Ks_Image) return String;
   --  The full name of the selected space; "@" by default. When the
   --  selected space is removed from the tree (by Delete_Subtree or Clear
   --  through Coordinate_Space_Tree, or by Set_Coordinate_Space_Tree), the
   --  selection becomes "@", here, in Resolve_Space_Name and in
   --  Get_Transform, and it stays "@" when a space of the same name is
   --  added again later. So two images whose selections read the same
   --  behave the same, whatever was selected before.
   --  One case is outside this rule: a reference returned by
   --  Coordinate_Space_Tree that is kept (renamed or held in an object)
   --  rather than used within one statement. The image settles its
   --  selection only when such a reference is created and when it ends, so
   --  a selected space removed and then added again through the same
   --  reference, while it exists, is still selected afterwards (in between
   --  the selection reads as "@").

   procedure Set_Selected_Space_Name
     (Image : in out Ks_Image; Space_Name : String);
   --  Space_Name must be "#" or a space in the coordinate space tree ("."
   --  is accepted and leaves the selection as Selected_Space_Name reads
   --  it). Raises Ks_Image_Bad_Selected_Space_Name_Exception otherwise.

   function Pixel_From_Root_Transform
     (Image : Ks_Image) return AMV.Transforms.Ks_Transform_2D_Linear;

   procedure Set_Pixel_From_Root_Transform
     (Image     : in out Ks_Image;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear);
   --  The transform is stored exactly as given. It must be finite and
   --  within the bound of AMV.Transforms (every entry within 1.0E150;
   --  Ks_Bad_Parameter_Exception otherwise) and invertible within it
   --  (Ks_Transform_Singular_Exception otherwise), so that Get_Transform
   --  can always map out of "#".

   type Ks_Coordinate_Space_Tree_Reference
     (Element :
        not null access AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree)
   is limited private
   with Implicit_Dereference => Element;

   function Coordinate_Space_Tree
     (Image : aliased in out Ks_Image)
      return Ks_Coordinate_Space_Tree_Reference;
   --  Direct access to the image's tree, so that
   --  Image.Coordinate_Space_Tree.Add_Space (...) works as in VisionPro.
   --  When the reference is created and again when it ends (for the form
   --  above, at the end of the statement), a selection naming a space that
   --  is no longer in the tree is replaced by "@" (see
   --  Selected_Space_Name).

   function Get_Coordinate_Space_Tree
     (Image : Ks_Image)
      return AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
   --  A copy of the image's tree.

   procedure Set_Coordinate_Space_Tree
     (Image : in out Ks_Image;
      Tree  : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree);
   --  Replaces the tree. The selection, as Selected_Space_Name reads it
   --  before the call, is kept when it is "#" or when Tree has a space of
   --  that name; otherwise it becomes "@".

   function Resolve_Space_Name
     (Image : Ks_Image; Space_Name : String) return String;
   --  "." becomes the selected space's full name; "#" and tree names are
   --  returned unchanged (indexed from 1). Raises
   --  Ks_Image_Bad_Selected_Space_Name_Exception for any other name.

   function Get_Transform
     (Image           : Ks_Image;
      To_Space_Name   : String;
      From_Space_Name : String) return AMV.Transforms.Ks_Transform_2D_Linear;
   --  The transform mapping coordinates in From_Space_Name to coordinates in
   --  To_Space_Name. Both names may be "#", "." or a tree space name.
   --  Between two tree spaces it is the tree's Get_Transform (To, From).
   --  Into "#" it is Pixel_From_Root_Transform composed with the tree's
   --  Get_Transform ("@", From) (which maps From into the root); out of
   --  "#" it is the tree's Get_Transform (To, "@") composed with the
   --  inverse of Pixel_From_Root_Transform. Names that resolve to the same
   --  space give exactly the identity. Raises
   --  Ks_Image_Bad_Selected_Space_Name_Exception for an unknown name, and
   --  Ks_Transform_Singular_Exception or Ks_Bad_Parameter_Exception in the
   --  extreme cases described for AMV.Coordinate_Spaces.Get_Transform.

   ---------------------------------------------------------------------
   --  CogImage8Grey
   ---------------------------------------------------------------------

   type Ks_Image_8_Grey is new Ks_Image with private;
   --  Default value: unallocated.

   type Grey_8_Row is array (Natural range <>) of Grey_8;
   type Grey_8_Matrix is array (Natural range <>, Natural range <>) of Grey_8;
   --  Matrix index order is (Y, X): rows first.

   function Create
     (Width, Height : Positive; Value : Grey_8 := 0) return Ks_Image_8_Grey;
   --  A new image with every pixel set to Value.

   procedure Allocate
     (Image : in out Ks_Image_8_Grey; Width, Height : Positive);
   --  Gives Image a new zero-filled buffer of the given size (other images
   --  sharing the old buffer keep it). The coordinate space tree, selected
   --  space and pixel-from-root transform are kept.

   function Get_Pixel
     (Image : Ks_Image_8_Grey; X, Y : Natural) return Grey_8
   with Inline;

   procedure Set_Pixel
     (Image : in out Ks_Image_8_Grey; X, Y : Natural; Value : Grey_8)
   with Inline;

   procedure Fill (Image : in out Ks_Image_8_Grey; Value : Grey_8);

   procedure Get_Row
     (Image : Ks_Image_8_Grey; Y : Natural; Row : out Grey_8_Row);
   --  Copies row Y into Row, which may have any bounds. Y must be a row of
   --  the image and Row'Length must equal Width (Constraint_Error
   --  otherwise; Row is then unspecified).

   procedure Set_Row
     (Image : in out Ks_Image_8_Grey; Y : Natural; Row : Grey_8_Row);
   --  Copies Row (any bounds) into row Y and changes no other row. Y must
   --  be a row of the image and Row'Length must equal Width
   --  (Constraint_Error otherwise).

   function To_Matrix (Image : Ks_Image_8_Grey) return Grey_8_Matrix;
   --  Matrix'Range (1) = 0 .. Height - 1, Matrix'Range (2) = 0 .. Width - 1.

   function From_Matrix (Pixels : Grey_8_Matrix) return Ks_Image_8_Grey;
   --  Pixels may have any bounds; pixel (X, Y) of the result is
   --  Pixels (Pixels'First (1) + Y, Pixels'First (2) + X). Both dimensions
   --  must be non-empty and the matrix must have at most Natural'Last
   --  elements (Ks_Bad_Parameter_Exception).

   function Copy
     (Image : Ks_Image_8_Grey;
      Mode  : Ks_Image_Copy_Mode_Constants := Copy_Pixels)
      return Ks_Image_8_Grey;
   --  A copy with the same tree, selected space and pixel-from-root
   --  transform; pixels copied, shared or left out according to Mode.
   --  An unallocated Image gives an unallocated copy in every mode. With
   --  No_Pixels the copy is unallocated and shares nothing with Image;
   --  Allocate gives it pixels of any size later, keeping the coordinate
   --  space state.

   function Shares_Pixels (Left, Right : Ks_Image_8_Grey) return Boolean;
   --  True when both images are allocated and use the same buffer.

   ---------------------------------------------------------------------
   --  CogImage16Grey
   ---------------------------------------------------------------------

   type Ks_Image_16_Grey is new Ks_Image with private;

   function Create
     (Width, Height : Positive; Value : Grey_16 := 0)
      return Ks_Image_16_Grey;

   procedure Allocate
     (Image : in out Ks_Image_16_Grey; Width, Height : Positive);

   function Get_Pixel
     (Image : Ks_Image_16_Grey; X, Y : Natural) return Grey_16
   with Inline;

   procedure Set_Pixel
     (Image : in out Ks_Image_16_Grey; X, Y : Natural; Value : Grey_16)
   with Inline;

   procedure Fill (Image : in out Ks_Image_16_Grey; Value : Grey_16);

   function Copy
     (Image : Ks_Image_16_Grey;
      Mode  : Ks_Image_Copy_Mode_Constants := Copy_Pixels)
      return Ks_Image_16_Grey;
   --  As for Ks_Image_8_Grey.

   function Shares_Pixels (Left, Right : Ks_Image_16_Grey) return Boolean;

   ---------------------------------------------------------------------
   --  CogImage24PlanarColor
   ---------------------------------------------------------------------

   type Ks_Image_24_Planar_Color is new Ks_Image with private;
   --  Three 8-bit planes (red, green, blue) of the same size.

   function Create
     (Width, Height : Positive; Red, Green, Blue : Grey_8 := 0)
      return Ks_Image_24_Planar_Color;

   procedure Allocate
     (Image : in out Ks_Image_24_Planar_Color; Width, Height : Positive);

   procedure Get_Pixel
     (Image            : Ks_Image_24_Planar_Color;
      X, Y             : Natural;
      Red, Green, Blue : out Grey_8);

   procedure Set_Pixel
     (Image            : in out Ks_Image_24_Planar_Color;
      X, Y             : Natural;
      Red, Green, Blue : Grey_8);

   function Get_Plane
     (Image : Ks_Image_24_Planar_Color'Class;
      Plane : Ks_Image_Plane_Constants) return Ks_Image_8_Grey;
   --  The plane as a grey image that shares the plane's pixels, with the
   --  colour image's tree, selected space and pixel-from-root transform.
   --  An unallocated colour image gives an unallocated grey image.

   procedure Set_Plane
     (Image  : in out Ks_Image_24_Planar_Color'Class;
      Plane  : Ks_Image_Plane_Constants;
      Pixels : Ks_Image_8_Grey'Class);
   --  Copies Pixels into the plane (so the change is visible through every
   --  image sharing that plane). Sizes must match
   --  (Ks_Bad_Parameter_Exception); an unallocated Pixels raises
   --  Ks_Image_No_Pixels_Exception.

   function Copy
     (Image : Ks_Image_24_Planar_Color;
      Mode  : Ks_Image_Copy_Mode_Constants := Copy_Pixels)
      return Ks_Image_24_Planar_Color;
   --  As for Ks_Image_8_Grey (Share_Pixels shares all three planes).

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   --  Ks_Image_8_Grey, Ks_Image_16_Grey and Ks_Image_24_Planar_Color have
   --  their own 'Write and 'Read, which 'Output, 'Input and the class-wide
   --  Ks_Image'Class'Output and Ks_Image'Class'Input use too. They store an
   --  image by value (never a reference to its pixel buffer) as:
   --
   --  1. a format code (Interfaces.Unsigned_32) naming the image type and
   --     this layout;
   --  2. Width and Height (Unsigned_32 each): 0 and 0 for an unallocated
   --     image;
   --  3. Pixel_From_Root_Transform: A, B, C, D, Translation_X and
   --     Translation_Y (see AMV.Transforms), each as the bits of its
   --     IEEE 754 binary64 value in an Interfaces.Unsigned_64;
   --  4. the number of spaces in the tree other than "@" (Unsigned_32),
   --     then for each of them, in Space_Name order, its full name and its
   --     Parent_From_Child transform (six entries as in 3);
   --  5. the selected space name, as Selected_Space_Name reads it;
   --  6. the pixels, row after row starting at (0, 0), as stream elements:
   --     one per pixel for an 8-bit image, two per pixel (least
   --     significant byte first) for a 16-bit image, and for a colour image
   --     the whole red plane, then the green plane, then the blue plane.
   --     Nothing for an unallocated image.
   --
   --  A name is its length (Unsigned_32) followed by its characters. The
   --  integers use the stream attributes of the Interfaces types, whose
   --  representation the compiler chooses (GNAT: the byte order of the
   --  platform), so a stream is meant to be read by a program built with
   --  the same compiler for the same kind of platform.
   --
   --  'Read (and so 'Input) treats the stream as untrusted. It first
   --  releases the target's pixels (other images sharing them keep them),
   --  then checks every field before using it: the format code must be
   --  the one of the target's type; the size must be 0 x 0 or within the
   --  limits of Create (both positive and Width * Height <= Natural'Last);
   --  every transform entry must be finite (checked on its bits) and
   --  within 1.0E150, and every transform invertible within that bound
   --  (as Set_Pixel_From_Root_Transform and Add_Space require); the
   --  number of spaces must fit in a tree (at most 63 besides "@") and a
   --  name must have at most 256 characters (checked before its
   --  characters are read); every space name must extend a space read
   --  before it (or "@") by one valid path component (see
   --  AMV.Coordinate_Spaces) and must not repeat; the selected name must
   --  be "#" or one of the spaces. The kernel (AMV.Kernels.Images) makes
   --  these checks.
   --  Only then is a pixel buffer of the declared size allocated and
   --  filled from the stream, so the image read never shares pixels with
   --  another image. A field that fails a check, or a stream that ends
   --  before the image is complete, raises Ks_Image_File_Exception (the
   --  exception AMV.Image_File raises for a malformed image file). On any
   --  failure, including an exception raised by the stream itself (which
   --  propagates unchanged), the target is left as a default image:
   --  unallocated, with the default tree, selection and transform.
   --  Ks_Image'Class'Input first reads the external tag of the type, as
   --  the language defines; a tag that names no image type raises
   --  Ada.Tags.Tag_Error.
   --
   --  Ks_Image'Write and Ks_Image'Read, reached through a view conversion
   --  to Ks_Image or as the parent part of a type derived from Ks_Image
   --  elsewhere, store only a format code of their own and items 3 to 5.
   --  That 'Read replaces the coordinate space state and nothing else, and
   --  on failure leaves the target unchanged.

private

   type Space_State is record
      Tree            :
        aliased AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
      Selected        : AMV.Kernels.Coordinate_Spaces.Ks_Space_Name :=
        AMV.Kernels.Images.Root_Space_Name;
      --  The selected space name as stored; it reads as "@" when it names
      --  a space that has left the tree (see Selected_Space_Name).
      Pixel_From_Root : AMV.Kernels.Transforms.Ks_Transform_2D_Linear;
   end record;

   type Ks_Image is abstract new Ada.Finalization.Controlled with record
      Width  : Natural := 0;
      Height : Natural := 0;
      --  The size the kernel reported for the pixels (0 x 0 without).
      Spaces : aliased Space_State;
   end record;

   --  Stream attributes. Every image type that owns heap memory through an
   --  access component must specify its own Read and Write: the default
   --  attributes would copy the pointer itself, without counting the new
   --  user, and Read would install whatever pointer the stream holds.

   procedure Write_Spaces_Part
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Ks_Image);
   procedure Read_Spaces_Part
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Image);

   for Ks_Image'Write use Write_Spaces_Part;
   for Ks_Image'Read use Read_Spaces_Part;

   --  The reference returned by Coordinate_Space_Tree. Its guard settles
   --  the selection of the image when the reference ends.

   type Space_State_Access is access all Space_State;

   type Selection_Guard is new Ada.Finalization.Limited_Controlled with
   record
      Spaces : Space_State_Access;
   end record;

   overriding procedure Finalize (Guard : in out Selection_Guard);

   type Ks_Coordinate_Space_Tree_Reference
     (Element :
        not null access AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree)
   is limited record
      Guard : Selection_Guard;
   end record;

   --  Reference-counted boxes for the kernel's pixel handles. A box holds
   --  one handle (never null) and is freed, with the handle, by its last
   --  user. The body updates References with
   --  System.Atomic_Operations.Integer_Arithmetic, so images may be copied
   --  and finalized from several tasks.

   type Atomic_Count is new Integer with Atomic;

   type Pixel_Box_8 is limited record
      References : aliased Atomic_Count := 1;
      Handle     : AMV.Kernels.Images.Ks_Image_8_Grey;
   end record;
   type Pixel_Box_8_Access is access Pixel_Box_8;

   type Pixel_Box_16 is limited record
      References : aliased Atomic_Count := 1;
      Handle     : AMV.Kernels.Images.Ks_Image_16_Grey;
   end record;
   type Pixel_Box_16_Access is access Pixel_Box_16;

   type Ks_Image_8_Grey is new Ks_Image with record
      Buffer : Pixel_Box_8_Access;
      --  Null for an unallocated image.
   end record;

   overriding procedure Adjust (Image : in out Ks_Image_8_Grey);
   overriding procedure Finalize (Image : in out Ks_Image_8_Grey);

   procedure Write_Grey_8
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Ks_Image_8_Grey);
   procedure Read_Grey_8
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Image_8_Grey);

   for Ks_Image_8_Grey'Write use Write_Grey_8;
   for Ks_Image_8_Grey'Read use Read_Grey_8;

   type Ks_Image_16_Grey is new Ks_Image with record
      Buffer : Pixel_Box_16_Access;
   end record;

   overriding procedure Adjust (Image : in out Ks_Image_16_Grey);
   overriding procedure Finalize (Image : in out Ks_Image_16_Grey);

   procedure Write_Grey_16
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Ks_Image_16_Grey);
   procedure Read_Grey_16
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Image_16_Grey);

   for Ks_Image_16_Grey'Write use Write_Grey_16;
   for Ks_Image_16_Grey'Read use Read_Grey_16;

   type Plane_Buffers is array (Ks_Image_Plane_Constants) of
     Pixel_Box_8_Access;
   --  All null for an unallocated image, otherwise three boxes of one
   --  size.

   type Ks_Image_24_Planar_Color is new Ks_Image with record
      Planes : Plane_Buffers;
   end record;

   overriding procedure Adjust (Image : in out Ks_Image_24_Planar_Color);
   overriding procedure Finalize (Image : in out Ks_Image_24_Planar_Color);

   procedure Write_Colour
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Ks_Image_24_Planar_Color);
   procedure Read_Colour
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Image_24_Planar_Color);

   for Ks_Image_24_Planar_Color'Write use Write_Colour;
   for Ks_Image_24_Planar_Color'Read use Read_Colour;

end AMV.Images;
