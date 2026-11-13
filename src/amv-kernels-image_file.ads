--  Kernel of AMV.Image_File: the PNM and BMP codecs, the choice of a write
--  format and encoding, and the state rules of CogImageFile and
--  CogImageFileTool.
--
--  The kernel works on bytes in memory; reading and writing operating
--  system files is left to the Ada API (AMV.Image_File), which reads a
--  whole file into a Byte_Array, has it decoded here, and writes the bytes
--  encoded here. The formats and their rules are described in the spec of
--  AMV.Image_File; this kernel implements them.
--
--  Decoding. Decode turns the complete contents of a file into an owned
--  handle (Ks_Image_File_Contents; C: ks_image_file_contents *, opaque)
--  that holds the decoded images: their kind (PNM or BMP), and for each
--  image its type (8-bit grey, 16-bit grey or colour), its maxval (255 for
--  BMP) and its pixels in handles of AMV.Kernels.Images. Every field of a
--  header is checked before it is used, and the size of the pixel data a
--  header announces is checked against the bytes actually present before
--  any pixels are allocated, so a malicious header can neither make the
--  decoder read outside the bytes nor allocate more than 8 pixels per byte
--  of input. A file without any image is a failure. Decoding makes two
--  passes over a PNM file: the first checks every image and counts them,
--  the second allocates and fills exactly that many.
--
--  The images of a contents handle are read through copies (Get_8_Grey,
--  Get_16_Grey, Get_24_Planar_Color, Get_8_Grey_Converted), new handles
--  owned by the caller; the contents never change after Decode. A null
--  contents handle holds no image (Count gives 0).
--
--  Encoding. Format_From_Name chooses the write format from a file name,
--  Choose_Encoding the encoding of an image in that format, Encoded_Size
--  the number of bytes, Check_Append the rules of appending to a file
--  (BMP holds one image; a PNM image after a plain one needs a line feed),
--  and Encode_* writes the bytes into a caller-provided array of exactly
--  that size.
--
--  Messages never contain the file name (a status holds 200 characters);
--  the Ada API puts the file name and ": " in front of them.
--
--  Trusted parts (SPARK_Mode Off bodies, listed in docs/PROOF.md): the
--  allocation of a contents handle, which turns a failed allocation into
--  Out_Of_Memory, and the C entry points that take bytes or a name in C
--  memory, which view that memory as an Ada array after a proved check of
--  the request. Everything else is proved.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Interfaces;
with System;

with AMV.Kernels.Images;

package AMV.Kernels.Image_File with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;

   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_32;
   use type KI.Ks_Image_8_Grey;
   use type KI.Ks_Image_16_Grey;

   ---------------------------------------------------------------------
   --  Bytes
   ---------------------------------------------------------------------

   subtype Byte is Interfaces.Unsigned_8;

   Max_Length : constant := 2**56;
   --  The largest number of bytes the kernel accepts (C:
   --  KS_IMAGE_FILE_MAX_LENGTH). Every Byte_Array is indexed within
   --  1 .. Max_Length, so it has at most that many bytes; a C length must
   --  be in 0 .. Max_Length.

   subtype Byte_Index is Int64 range 1 .. Max_Length;

   type Byte_Array is array (Byte_Index range <>) of Byte;
   --  The contents of a file (C: const uint8_t *bytes, int64_t length).
   --  Any bounds within Byte_Index; the first byte is the file's offset 0.

   ---------------------------------------------------------------------
   --  Codes (C: the KS_IMAGE_FILE_* constants of include/amv.h)
   ---------------------------------------------------------------------

   --  Modes of CogImageFile (CogImageFileModeConstants).
   Mode_Closed : constant Int32 := 1;
   Mode_Read   : constant Int32 := 2;
   Mode_Write  : constant Int32 := 3;
   Mode_Update : constant Int32 := 4;

   --  Write formats, chosen from the extension of a file name.
   Format_PGM : constant Int32 := 1;   --  .pgm
   Format_PPM : constant Int32 := 2;   --  .ppm
   Format_PNM : constant Int32 := 3;   --  .pnm
   Format_BMP : constant Int32 := 4;   --  .bmp

   --  What a decoded file holds.
   Kind_PNM : constant Int32 := 1;
   Kind_BMP : constant Int32 := 2;

   --  Image types (of a decoded image, or of an image to write).
   Image_Type_Grey_8  : constant Int32 := 1;
   Image_Type_Grey_16 : constant Int32 := 2;
   Image_Type_Color   : constant Int32 := 3;

   --  Encodings of an image in a file.
   Encoding_P5_8         : constant Int32 := 1;  --  8-bit grey as P5, 255
   Encoding_P5_16        : constant Int32 := 2;  --  16-bit grey as P5, 65535
   Encoding_P6_From_Grey : constant Int32 := 3;  --  8-bit grey as P6, R=G=B
   Encoding_P6_Color     : constant Int32 := 4;  --  colour as P6, 255
   Encoding_BMP_8        : constant Int32 := 5;  --  8-bit grey, grey palette
   Encoding_BMP_24       : constant Int32 := 6;  --  colour, 24 bits

   --  Operations whose mode rules Require_Open and Require_Mode check.
   Operation_Item   : constant Int32 := 1;  --  CogImageFile.Item
   Operation_Append : constant Int32 := 2;  --  CogImageFile.Append
   Operation_Run    : constant Int32 := 3;  --  CogImageFileTool.Run

   subtype Mode_Code is Int32 range Mode_Closed .. Mode_Update;
   subtype Format_Code is Int32 range Format_PGM .. Format_BMP;
   subtype Kind_Code is Int32 range Kind_PNM .. Kind_BMP;
   subtype Image_Type_Code is Int32
     range Image_Type_Grey_8 .. Image_Type_Color;
   subtype Encoding_Code is Int32 range Encoding_P5_8 .. Encoding_BMP_24;
   subtype Operation_Code is Int32 range Operation_Item .. Operation_Run;

   Max_Images : constant := 2**31 - 1;
   --  The largest number of images of a file, and of a Count.

   Max_BMP_File_Size : constant := 2**32 - 1;
   --  The largest BMP file Encode writes (the file size field has 32 bits).

   ---------------------------------------------------------------------
   --  Decoded contents
   ---------------------------------------------------------------------

   type Image_Slot is record
      Image_Type : Int32 := 0;
      Maxval     : Int32 := 0;
      Grey_8     : KI.Ks_Image_8_Grey;
      --  An 8-bit grey image, or the red plane of a colour image.
      Grey_16    : KI.Ks_Image_16_Grey;
      Green      : KI.Ks_Image_8_Grey;
      Blue       : KI.Ks_Image_8_Grey;
   end record;
   --  One decoded image. Valid_Slot states what a decoded slot holds.

   type Slot_Array is array (Int32 range <>) of Image_Slot;

   type Ks_Image_File_Contents_Data (Count : Int32) is limited record
      Kind  : Int32 := 0;
      Slots : Slot_Array (1 .. Count);
   end record;
   --  What a contents handle designates (opaque for C): image I (0-based)
   --  is Slots (I + 1). Valid_Contents states its invariant.

   type Ks_Image_File_Contents is access Ks_Image_File_Contents_Data
     with Convention => C;
   --  C: ks_image_file_contents *.

   function No_Handles (Slot : Image_Slot) return Boolean is
     (Slot.Grey_8 = null and then Slot.Grey_16 = null
      and then Slot.Green = null and then Slot.Blue = null);
   --  A slot that owns no image.

   function Valid_Slot (Slot : Image_Slot) return Boolean is
     (case Slot.Image_Type is
         when Image_Type_Grey_8 =>
            KI.Valid_Image (Slot.Grey_8)
            and then Slot.Grey_16 = null
            and then Slot.Green = null and then Slot.Blue = null
            and then Slot.Maxval in 1 .. 255,
         when Image_Type_Grey_16 =>
            Slot.Grey_8 = null
            and then KI.Valid_Image (Slot.Grey_16)
            and then Slot.Green = null and then Slot.Blue = null
            and then Slot.Maxval in 256 .. 65_535,
         when Image_Type_Color =>
            KI.Valid_Image (Slot.Grey_8)
            and then KI.Valid_Image (Slot.Green)
            and then KI.Valid_Image (Slot.Blue)
            and then Slot.Green.Width = Slot.Grey_8.Width
            and then Slot.Green.Height = Slot.Grey_8.Height
            and then Slot.Blue.Width = Slot.Grey_8.Width
            and then Slot.Blue.Height = Slot.Grey_8.Height
            and then Slot.Grey_16 = null
            and then Slot.Maxval in 1 .. 255,
         when others => False);
   --  A decoded image: one valid 8-bit or 16-bit handle, or three valid
   --  planes of one size, and the maxval of its type (8-bit and colour
   --  samples are at most 255, a 16-bit image has a maxval above 255).

   function Slot_Pixels (Slot : Image_Slot) return Int64 is
     (if Slot.Grey_8 /= null
      then Int64 (Slot.Grey_8.Width) * Int64 (Slot.Grey_8.Height)
      elsif Slot.Grey_16 /= null
      then Int64 (Slot.Grey_16.Width) * Int64 (Slot.Grey_16.Height)
      else 0);
   --  The number of pixels of a slot's image.

   function Valid_Contents
     (Contents : access constant Ks_Image_File_Contents_Data) return Boolean
   is
     (Contents /= null
      and then Contents.Count >= 1
      and then Contents.Kind in Kind_Code
      and then (Contents.Kind = Kind_PNM or else Contents.Count = 1)
      and then (for all I in Contents.Slots'Range
                => Valid_Slot (Contents.Slots (I))));
   --  A handle that Decode returned: at least one image (exactly one for
   --  BMP), each a valid slot.

   function Within_Input
     (Contents : access constant Ks_Image_File_Contents_Data;
      Length   : Int64) return Boolean
   is
     (Contents /= null
      and then (for all I in Contents.Slots'Range
                => Slot_Pixels (Contents.Slots (I)) <= 8 * Length))
   with Pre => Length in 0 .. Max_Length;
   --  No image has more than 8 pixels per byte of input (the bound for
   --  1-bit BMP pixels; PNM images have at most one pixel per byte).

   ---------------------------------------------------------------------
   --  Decoding
   ---------------------------------------------------------------------

   procedure Decode
     (Bytes    : Byte_Array;
      Contents : out Ks_Image_File_Contents;
      Status   : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory | Failure_Other
             and then (if Succeeded (Status)
                       then Valid_Contents (Contents)
                            and then Within_Input (Contents, Bytes'Length)
                       else Contents = null);
   --  Decodes every image of Bytes, the complete contents of a PNM or BMP
   --  file (recognised from its first bytes). Image_File for anything that
   --  is not a well-formed, supported file, with the message of
   --  AMV.Image_File ("the file is empty", "image 1: the width is 0",
   --  "truncated BMP file: the pixel data needs 2700000054 bytes but the
   --  file has only 58", ...); Out_Of_Memory when the images cannot be
   --  allocated. Contents is null when the call fails. Failure_Other
   --  cannot occur (it would mean that the second pass over the bytes
   --  found other images than the first).

   procedure Decode
     (Bytes    : System.Address;
      Length   : Int64;
      Contents : out Ks_Image_File_Contents;
      Status   : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_image_file_decode",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory | Failure_Other
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Contents (Contents)
                       else Contents = null);
   --  The same for the Length bytes at Bytes (C: const uint8_t *).
   --  Bad_Parameter unless Length is in 0 .. Max_Length and Bytes is not
   --  null when Length > 0. Trusted: the memory at Bytes is viewed as an
   --  array of Length bytes, which C must provide.

   procedure Destroy
     (Contents : in out Ks_Image_File_Contents;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_contents_destroy",
     Post => Valid (Status) and then Succeeded (Status)
             and then Contents = null;
   --  Frees the contents and every image in it, and sets Contents to
   --  null. Nothing for null. Never fails.

   procedure Image_Count
     (Contents : access constant Ks_Image_File_Contents_Data;
      Result   : out Int32;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_contents_count",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result in 0 .. Max_Images
             and then (if Succeeded (Status) and then Contents /= null
                       then Result = Contents.Count
                       else Result = 0);
   --  The number of images; 0 for null. Bad_Parameter for a handle that
   --  is not consistent.

   procedure Contents_Kind
     (Contents : access constant Ks_Image_File_Contents_Data;
      Result   : out Int32;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_contents_kind",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then Contents /= null
                       then Result in Kind_Code
                       else Result = 0);
   --  Kind_PNM or Kind_BMP; 0 for null.

   procedure Image_Info
     (Contents   : access constant Ks_Image_File_Contents_Data;
      Index      : Int32;
      Image_Type : out Int32;
      Maxval     : out Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_contents_image_info",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Image_Type in Image_Type_Code
                            and then Maxval in 1 .. 65_535
                       else Image_Type = 0 and then Maxval = 0);
   --  The type and the maxval of image Index (0-based). Index_Out_Of_Range
   --  unless Index is in 0 .. Count - 1 ("Item: index 4 is not below Count
   --  (4)"); Bad_Parameter for an inconsistent handle.

   procedure Check_Read_Index
     (Contents : access constant Ks_Image_File_Contents_Data;
      Index    : Int32;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_contents_check_read_index",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_File
             and then (if Succeeded (Status)
                       then Contents /= null
                            and then Index in 0 .. Contents.Count - 1);
   --  The rule of Read_Image: Image_File unless the file holds an image
   --  with this index ("the file holds 2 image(s); there is no image with
   --  index 5").

   procedure Get_8_Grey
     (Contents : access constant Ks_Image_File_Contents_Data;
      Index    : Int32;
      Image    : out KI.Ks_Image_8_Grey;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_contents_get_8_grey",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range | Failure_Out_Of_Memory
             and then (if Succeeded (Status) then KI.Valid_Image (Image)
                       else Image = null);
   --  A copy of image Index, owned by the caller, which must be an 8-bit
   --  grey image (Bad_Parameter otherwise). Index_Out_Of_Range as for
   --  Image_Info.

   procedure Get_16_Grey
     (Contents : access constant Ks_Image_File_Contents_Data;
      Index    : Int32;
      Image    : out KI.Ks_Image_16_Grey;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_contents_get_16_grey",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range | Failure_Out_Of_Memory
             and then (if Succeeded (Status) then KI.Valid_Image (Image)
                       else Image = null);
   --  The same for a 16-bit grey image.

   procedure Get_24_Planar_Color
     (Contents         : access constant Ks_Image_File_Contents_Data;
      Index            : Int32;
      Red, Green, Blue : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_contents_get_24_planar_color",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then KI.Valid_Image (Red) and then KI.Valid_Image (Green)
                            and then KI.Valid_Image (Blue)
                            and then Green.Width = Red.Width
                            and then Green.Height = Red.Height
                            and then Blue.Width = Red.Width
                            and then Blue.Height = Red.Height
                       else Red = null and then Green = null
                            and then Blue = null);
   --  The same for a colour image: copies of its three planes.

   procedure Get_8_Grey_Converted
     (Contents : access constant Ks_Image_File_Contents_Data;
      Index    : Int32;
      Image    : out KI.Ks_Image_8_Grey;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_contents_get_8_grey_converted",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range | Failure_Out_Of_Memory
             and then (if Succeeded (Status) then KI.Valid_Image (Image)
                       else Image = null);
   --  Image Index converted to a new 8-bit grey image, the rule of
   --  Read_Image_8_Grey: 8-bit samples are kept, a 16-bit sample V becomes
   --  round (V * 255 / Maxval) and a colour pixel round (0.299 R + 0.587 G
   --  + 0.114 B), both rounded half up exactly in integers.

   ---------------------------------------------------------------------
   --  Formats, encodings and the rules of writing
   ---------------------------------------------------------------------

   procedure Format_From_Name
     (Name   : String;
      Format : out Int32;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status) then Format in Format_Code
                       else Format = 0);
   --  The write format chosen by the extension of Name (the text after the
   --  last '.' of the last path component, '/' or '\' separating
   --  components), ignoring the case of letters: .pgm, .ppm, .pnm, .bmp.
   --  Image_File for any other extension ("cannot choose an image format
   --  for writing from the extension "png" (use .pgm, .ppm, .pnm or
   --  .bmp)").

   procedure Format_From_Name
     (Name   : System.Address;
      Length : Int32;
      Format : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_format_from_name",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Format in Format_Code
                       else Format = 0);
   --  The same for the Length characters at Name (C: const char *, not
   --  NUL-terminated). Bad_Parameter unless Length >= 0 and Name is not
   --  null when Length > 0. Trusted: C provides Length characters there.

   procedure Choose_Encoding
     (Format        : Int32;
      Image_Type    : Int32;
      Width, Height : Int32;
      Encoding      : out Int32;
      Status        : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_choose_encoding",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_No_Pixels | Failure_Image_File
             and then (if Succeeded (Status) then Encoding in Encoding_Code
                       else Encoding = 0);
   --  How an image of this type and size is written in Format. The checks,
   --  in order: Format a format code and Width and Height not negative
   --  (Bad_Parameter); Image_No_Pixels when Width or Height is 0 ("the
   --  image to write has no pixels"); Image_File for an image type that is
   --  not a code ("unsupported image type") and when the format cannot
   --  hold the image ("a .pgm file cannot hold a colour image (use .ppm,
   --  .pnm or .bmp)"); Bad_Parameter when Width * Height is above
   --  KI.Max_Pixels; Image_File when a BMP file would be larger than
   --  Max_BMP_File_Size ("the image is too large for a BMP file").

   procedure Encoded_Size
     (Encoding      : Int32;
      Width, Height : Int32;
      Separator     : Int32;
      Size          : out Int64;
      Status        : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_encoded_size",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_File
             and then (if Succeeded (Status)
                       then Size in 1 .. 4 * KI.Max_Pixels + 2_000
                       else Size = 0);
   --  The number of bytes Encode writes for a Width x Height image, with a
   --  leading line feed when Separator is 1 (PNM only; 0 or 1). Width and
   --  Height must be at least 1 and their product at most KI.Max_Pixels
   --  (Bad_Parameter), and a BMP file at most Max_BMP_File_Size bytes
   --  (Image_File).

   procedure Check_Append
     (Encoding   : Int32;
      Count      : Int32;
      Disk_Size  : Int64;
      Final_Byte : Byte;
      Separator  : out Int32;
      New_Count  : out Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_check_append",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_File
             and then Separator in 0 .. 1
             and then (if Succeeded (Status)
                       then Count in 0 .. Max_Images - 1
                            and then New_Count = Count + 1
                            and then (if Encoding in Encoding_BMP_8
                                                   | Encoding_BMP_24
                                      then Separator = 0)
                       else New_Count = 0 and then Separator = 0);
   --  The rules of appending an image with this encoding to a file object
   --  that has appended Count images since it was opened (its Count in
   --  Write mode, the images found plus those appended in Update mode),
   --  to a disk file of Disk_Size bytes (0 for a missing file) whose last
   --  byte is Final_Byte (ignored when Disk_Size is 0). A BMP file holds
   --  one image: Image_File when Count > 0 ("a BMP file holds only one
   --  image and this one already has it") or Disk_Size > 0 ("... and this
   --  file is not empty"). A PNM image needs a leading line feed
   --  (Separator = 1) when the file is not empty and its last byte is not
   --  Netpbm whitespace, so that a plain image before it stays readable.
   --  New_Count is the Count after the append. Bad_Parameter for an
   --  encoding that is not a code or a negative Count or Disk_Size;
   --  Image_File when Count is already Max_Images.

   procedure Encode_8_Grey
     (Encoding  : Int32;
      Separator : Int32;
      Image     : access constant KI.Ks_Image_8_Grey_Data;
      Bytes     : in out Byte_Array;
      Status    : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_No_Pixels | Failure_Image_File;
   --  Writes Image in Bytes, which must have exactly the Encoded_Size of
   --  the image (Bad_Parameter otherwise), for Encoding_P5_8,
   --  Encoding_P6_From_Grey or Encoding_BMP_8 (Bad_Parameter for any other
   --  encoding, and for a Separator that is not 0 or 1, or 1 with BMP).
   --  Image_No_Pixels for null, Bad_Parameter for an inconsistent handle;
   --  Image_File for a BMP file larger than Max_BMP_File_Size. The bytes
   --  are those AMV.Image_File's writer has always produced: a PNM header
   --  "P5\nW H\n255\n" (P6 for Encoding_P6_From_Grey, each grey value then
   --  written three times) followed by the rows from the top; a BMP file
   --  header, a BITMAPINFOHEADER and a 256-entry grey palette followed by
   --  the rows from the bottom, each padded with zeros to a multiple of 4
   --  bytes. Bytes is unchanged when the call fails.

   procedure Encode_16_Grey
     (Encoding  : Int32;
      Separator : Int32;
      Image     : access constant KI.Ks_Image_16_Grey_Data;
      Bytes     : in out Byte_Array;
      Status    : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_No_Pixels | Failure_Image_File;
   --  The same for Encoding_P5_16: maxval 65535, samples most significant
   --  byte first.

   procedure Encode_24_Planar_Color
     (Encoding         : Int32;
      Separator        : Int32;
      Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data;
      Bytes            : in out Byte_Array;
      Status           : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_No_Pixels | Failure_Image_File;
   --  The same for a colour image (three planes of one size; three nulls
   --  give Image_No_Pixels), for Encoding_P6_Color (red, green, blue per
   --  pixel) or Encoding_BMP_24 (blue, green, red per pixel, rows from the
   --  bottom, padded).

   procedure Encode_8_Grey
     (Encoding  : Int32;
      Separator : Int32;
      Image     : access constant KI.Ks_Image_8_Grey_Data;
      Bytes     : System.Address;
      Length    : Int64;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_encode_8_grey",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_No_Pixels | Failure_Image_File;
   --  The C forms of the three Encode procedures write the Length bytes
   --  at Bytes (C: uint8_t *). Bad_Parameter unless Length is in
   --  0 .. Max_Length and Bytes is not null when Length > 0. Trusted: the
   --  memory at Bytes is viewed as an array of Length bytes.

   procedure Encode_16_Grey
     (Encoding  : Int32;
      Separator : Int32;
      Image     : access constant KI.Ks_Image_16_Grey_Data;
      Bytes     : System.Address;
      Length    : Int64;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_encode_16_grey",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_No_Pixels | Failure_Image_File;

   procedure Encode_24_Planar_Color
     (Encoding         : Int32;
      Separator        : Int32;
      Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data;
      Bytes            : System.Address;
      Length           : Int64;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_encode_24_planar_color",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_No_Pixels | Failure_Image_File;

   procedure Count_For_Update
     (Format : Int32;
      Bytes  : Byte_Array;
      Count  : out Int32;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_File
             and then Count in 0 .. Max_Images
             and then (if not Succeeded (Status) then Count = 0);
   --  Opening a file of these contents in Update mode with this write
   --  format: the number of images it holds (0 for no bytes). The images
   --  are checked as by Decode but not allocated; Image_File when they are
   --  not well formed, or when they do not match Format ("cannot append:
   --  the file holds a BMP image, which does not match the extension
   --  .pgm"). Bad_Parameter for a format that is not a code.

   procedure Count_For_Update
     (Format : Int32;
      Bytes  : System.Address;
      Length : Int64;
      Count  : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_count_for_update",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_File
             and then Count in 0 .. Max_Images
             and then (if not Succeeded (Status) then Count = 0);
   --  The same for the Length bytes at Bytes; checks and trust as for the
   --  C form of Decode.

   ---------------------------------------------------------------------
   --  The state rules of CogImageFile and CogImageFileTool
   ---------------------------------------------------------------------

   procedure Check_Open_Mode
     (Mode   : Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_check_open_mode",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Mode in Mode_Read .. Mode_Update);
   --  Open accepts Read, Write and Update; Bad_Parameter for Closed (which
   --  only Open_Mode reports) and any other value.

   procedure Require_Open
     (Mode      : Int32;
      Operation : Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_require_open",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_File
             and then (if Succeeded (Status)
                       then Mode in Mode_Read .. Mode_Update);
   --  Image_File when the file is closed ("Item: the image file is not
   --  open"; "Append: ..."; "Operator: ..." for Operation_Run).
   --  Bad_Parameter for a mode or an operation that is not a code.

   procedure Require_Mode
     (Mode      : Int32;
      Operation : Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_require_mode",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_File
             and then (if Succeeded (Status)
                       then Mode in Mode_Read .. Mode_Update
                            and then (if Operation = Operation_Item
                                      then Mode = Mode_Read)
                            and then (if Operation = Operation_Append
                                      then Mode /= Mode_Read));
   --  The checks of Require_Open, then: Item needs Read mode ("Item needs
   --  Read mode but the file is open in WRITE mode"), Append needs Write
   --  or Update mode ("Append needs Write or Update mode but the file is
   --  open in Read mode"); Run accepts every open mode.

   procedure Tool_Next_Index
     (Next_Index     : Int32;
      Count          : Int32;
      Index          : out Int32;
      New_Next_Index : out Int32;
      Status         : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_image_file_tool_next_index",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_File
             and then (if Succeeded (Status)
                       then Count >= 1
                            and then Index = Next_Index mod Count
                            and then New_Next_Index = (Index + 1) mod Count
                       else Index = 0 and then New_Next_Index = 0);
   --  The Read mode rule of CogImageFileTool: the image to output is
   --  Next_Index mod Count, and Next_Index then becomes the following one,
   --  back to 0 after the last. Image_File when Count is 0 ("the file
   --  holds no image"); Bad_Parameter when either is negative.

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   --  The Ada API reads a file into a Byte_Array of its size. These give
   --  the failures of that reading, with the messages of AMV.Image_File.

   procedure Check_File_Size
     (Size   : Int64;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_File
             and then (if Succeeded (Status) then Size in 0 .. Max_Length);
   --  Image_File when the file has more than Max_Length bytes ("the file is
   --  too large to read into memory (N bytes)"); Bad_Parameter for a
   --  negative size.

   procedure File_Too_Large
     (Size   : Int64;
      Status : out Ks_Status)
   with
     Post => Valid (Status) and then Status.Failure = Failure_Image_File;
   --  The same failure, when the memory for the bytes cannot be allocated.

   procedure Check_Whole_Read
     (Size, Read_Count : Int64;
      Status           : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status) then Read_Count = Size);
   --  Image_File when fewer bytes than the file's size could be read
   --  ("could not read the whole file").

   --  Streams (the stream attributes of the file object of
   --  AMV.Image_File, whose private part describes the layout). The Ada
   --  API reads the stream; these check every number read and rebuild a
   --  contents handle from the images read. Every failure is Image_File
   --  (Out_Of_Memory aside), with a message that starts with
   --  "Ks_Image_File'Read: ".

   procedure Read_Contents_Header
     (Count, Kind : Interfaces.Unsigned_32;
      Contents    : out Ks_Image_File_Contents;
      Status      : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) and then Count > 0
                       then Contents /= null
                            and then Contents.Count = Int32 (Count)
                            and then Contents.Kind in Kind_Code
                            and then (for all I in Contents.Slots'Range
                                      => No_Handles (Contents.Slots (I))
                                         and then Contents.Slots (I)
                                                    .Image_Type = 0)
                       else Contents = null);
   --  A contents of Count empty slots (null for 0 images, whose Kind must
   --  be 0): Count at most Max_Images, Kind a kind code, one image for
   --  BMP.

   procedure Read_Image_Header
     (Image_Type, Maxval : Interfaces.Unsigned_32;
      Status             : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status)
                       then Image_Type in 1 .. 3 and then Maxval in 1 .. 65_535);
   --  Image_Type an image type code and Maxval within the range of that
   --  type (1 .. 255 for 8-bit and colour images, 256 .. 65535 for 16-bit
   --  images).

   procedure Store_8_Grey
     (Contents : Ks_Image_File_Contents;
      Index    : Int32;
      Maxval   : Int32;
      Image    : access constant KI.Ks_Image_8_Grey_Data;
      Status   : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Contents /= null
                            and then Index in 0 .. Contents.Count - 1
                            and then Valid_Slot
                                       (Contents.Slots (Index + 1)));
   --  Copies Image into the empty slot of image Index (0-based) of a
   --  handle from Read_Contents_Header, with this maxval. Image_File
   --  unless the slot exists and is empty, Maxval suits the type, Image
   --  has pixels and none of them is above Maxval. Changes nothing when it
   --  fails.

   procedure Store_16_Grey
     (Contents : Ks_Image_File_Contents;
      Index    : Int32;
      Maxval   : Int32;
      Image    : access constant KI.Ks_Image_16_Grey_Data;
      Status   : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Contents /= null
                            and then Index in 0 .. Contents.Count - 1
                            and then Valid_Slot
                                       (Contents.Slots (Index + 1)));

   procedure Store_24_Planar_Color
     (Contents         : Ks_Image_File_Contents;
      Index            : Int32;
      Maxval           : Int32;
      Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data;
      Status           : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Contents /= null
                            and then Index in 0 .. Contents.Count - 1
                            and then Valid_Slot
                                       (Contents.Slots (Index + 1)));

end AMV.Kernels.Image_File;
