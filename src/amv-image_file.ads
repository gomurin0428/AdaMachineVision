--  Image files: the counterparts of CogImageFile, CogImageFileModeConstants
--  and CogImageFileTool.
--
--  Supported formats, all implemented here in Ada:
--
--  * PNM (Netpbm). Reading: P2 / P5 grey (maxval 1 .. 255 gives an 8-bit
--    image, 256 .. 65535 a 16-bit image whose binary samples are stored
--    most significant byte first) and P3 / P6 colour (maxval 1 .. 255
--    only; a larger maxval is rejected). Header fields may be separated by
--    comments ('#' up to the end of the line); the header ends with one
--    whitespace byte (or a comment and its line end) after the maxval.
--    Comments are also tolerated between the samples of the plain forms
--    P2 / P3. A width, height or maxval of 0 is an error. A file may hold
--    several images one after the other, possibly of different types;
--    whitespace between them is allowed, anything else after the last
--    image is an error. The last sample of a plain image must be followed
--    by whitespace or a comment when another image follows it. Samples
--    are returned as stored: the maxval does not rescale 8-bit samples.
--    Samples greater than the maxval are an error. Writing uses the binary
--    forms P5 (8-bit with maxval 255, 16-bit with maxval 65535) and P6
--    (maxval 255).
--
--  * BMP (Windows bitmap), one image per file. Reading: 1-, 4- and 8-bit
--    indexed images (a palette whose entries all have equal red, green and
--    blue gives an 8-bit grey image holding the palette grey levels; any
--    other palette gives a colour image) and 24- and 32-bit images
--    (uncompressed, or 32-bit with the standard bit-field masks), stored
--    bottom-up or top-down, with the information header of 12, 40 or more
--    bytes. Writing: 8-bit grey images as 8-bit indexed with a grey
--    palette, colour images as 24-bit; rows bottom-up and padded to a
--    multiple of four bytes.
--
--  When reading, the format is recognised from the file content ("BM" or
--  "P<digit>" at the start), never from the name. When writing, it is
--  chosen from the file name extension, ignoring case:
--
--     .pgm   P5; grey images only (a colour image is rejected)
--     .ppm   P6; colour images, and 8-bit grey images written with equal
--            red, green and blue (a 16-bit image is rejected)
--     .pnm   P5 for grey images, P6 for colour images
--     .bmp   BMP; 8-bit grey or colour (a 16-bit image is rejected)
--
--  Any other extension is rejected. Every failure to open, read, decode,
--  create or write a file raises Ks_Image_File_Exception with a message
--  that starts with the file name; in particular a malformed, truncated or
--  unsupported file never lets Constraint_Error or an Ada.IO_Exceptions
--  exception escape, and neither does a file too large for its contents
--  to be held in memory (reading loads the whole file first). Writing an
--  unallocated image raises Ks_Image_No_Pixels_Exception instead. Running
--  out of memory while creating the decoded images still raises
--  Storage_Error, as creating any image does; so does running out of
--  memory while writing, which builds the whole encoded image in memory
--  before writing it to the file. Whatever exception ends an operation,
--  the file is closed again, so the name stays usable.
--
--  The coordinate space tree, selected space and pixel-from-root transform
--  of an image are not stored in files; images read from a file have the
--  defaults.
--
--  The codecs and the rules of this package are the SPARK kernel
--  AMV.Kernels.Image_File (the C functions ks_image_file_*), which decodes
--  and encodes bytes in memory; this package reads and writes the files.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Tools;

private with Ada.Finalization;
private with Ada.Streams;
private with Ada.Strings.Unbounded;
private with AMV.Kernels.Image_File;

package AMV.Image_File is

   type Ks_Image_File_Mode_Constants is (Closed, Read, Write, Update);
   --  CogImageFileModeConstants.
   --  Closed: the file is not open. Only Open_Mode reports it; it is not
   --          a mode to open a file with (Open rejects it).
   --  Read:   every image of an existing file is decoded into memory when
   --          the file is opened.
   --  Write:  the file is created, or emptied if it exists, when opened.
   --  Update: images are added after those already in the file; a missing
   --          file is created. VisionPro's Update opens an existing file
   --          for reading and writing; AMV's Update only appends (Item
   --          needs Read mode) and also accepts a missing file, which it
   --          creates.

   ---------------------------------------------------------------------
   --  CogImageFile
   ---------------------------------------------------------------------

   type Ks_Image_File is tagged private;
   --  Default value: closed. The object holds no operating system file
   --  handle: Read mode keeps the decoded images in memory, and every
   --  Append opens the file, writes one image and closes the file again.
   --  So the type is not limited; a copy has its own copy of the state
   --  (name, mode, count and decoded images) and, in Write or Update
   --  mode, writes to the same disk file.

   procedure Open
     (File      : in out Ks_Image_File;
      File_Name : String;
      Mode      : Ks_Image_File_Mode_Constants);
   --  Closes File if it is open, then opens File_Name in the given mode.
   --  Read: decodes every image now; a file without any image is an error.
   --  Write: creates or truncates the file now.
   --  Update: an existing non-empty file is decoded now, to check that it
   --  is in the format chosen by the extension (PNM for .pgm, .ppm and
   --  .pnm, BMP for .bmp) and to count its images; a missing file is
   --  created.
   --  In Write and Update mode an unsupported extension is rejected here.
   --  On any failure Ks_Image_File_Exception is raised and File stays
   --  closed. Mode Closed is rejected first, with
   --  Ks_Bad_Parameter_Exception (VisionPro: ArgumentException), and
   --  leaves File unchanged.

   procedure Close (File : in out Ks_Image_File);
   --  Returns File to its default (closed) state and drops the decoded
   --  images. Images already appended stay in the disk file. Closing a
   --  closed file does nothing.

   function Is_Open (File : Ks_Image_File) return Boolean;
   --  Open_Mode (File) /= Closed (an AMV addition).

   function File_Name (File : Ks_Image_File) return String;
   --  The name given to Open; "" when closed.

   function Open_Mode
     (File : Ks_Image_File) return Ks_Image_File_Mode_Constants;
   --  OpenMode: the mode given to Open; Closed when the file is closed.

   function Count (File : Ks_Image_File) return Natural;
   --  Read mode: the number of images in the file. Write mode: the number
   --  of images appended since Open. Update mode: the number of images the
   --  file held at Open plus those appended since. 0 when closed.

   function Item
     (File  : Ks_Image_File;
      Index : Natural) return AMV.Images.Ks_Image'Class;
   --  Image Index (0-based) of a file open in Read mode: a
   --  Ks_Image_8_Grey, Ks_Image_16_Grey or Ks_Image_24_Planar_Color
   --  according to the file. Each call returns an image with its own
   --  pixels, so changing it does not affect later calls.
   --  Raises Ks_Image_File_Exception when File is not open in Read mode
   --  and Constraint_Error when Index >= Count.

   procedure Append
     (File : in out Ks_Image_File; Image : AMV.Images.Ks_Image'Class);
   --  Writes Image to the end of the disk file at once (Write or Update
   --  mode) and increments Count. A PNM image is preceded by one line feed
   --  when the disk file is not empty and its last byte is not whitespace
   --  (as after a plain image without a final newline), so that the images
   --  already in the file stay readable; this is decided from the disk
   --  file at each Append. Raises Ks_Image_File_Exception when File is not
   --  open for writing, when the format cannot hold Image (see the table
   --  above), for a BMP file that is not empty (it already holds an image,
   --  whether this object, a copy of it or anything else wrote it), or on
   --  an I/O error; Ks_Image_No_Pixels_Exception when Image is
   --  unallocated. Every check is made before the file is changed, so a
   --  rejected image leaves the file and Count unchanged (only an I/O error
   --  in the middle of writing can leave part of an image behind; Count is
   --  then unchanged). An exception raised by Image itself (by a primitive
   --  that a type derived from an AMV image type overrides) propagates
   --  unchanged, with Count unchanged.

   ---------------------------------------------------------------------
   --  Convenience subprograms
   ---------------------------------------------------------------------

   function Read_Image
     (File_Name : String; Index : Natural := 0)
      return AMV.Images.Ks_Image'Class;
   --  Image Index (0-based) of the file, as Item returns it. Raises
   --  Ks_Image_File_Exception when the file cannot be read or holds no
   --  image number Index.

   function Read_Image_8_Grey
     (File_Name : String; Index : Natural := 0)
      return AMV.Images.Ks_Image_8_Grey;
   --  Like Read_Image, converted to 8-bit grey: 8-bit samples are kept,
   --  16-bit samples V become round (V * 255 / Maxval) with the maxval
   --  from the file, and colour pixels become
   --  round (0.299 * R + 0.587 * G + 0.114 * B). Rounding is half up,
   --  computed exactly in integer arithmetic.

   procedure Write_Image
     (File_Name : String; Image : AMV.Images.Ks_Image'Class);
   --  Creates (or truncates) File_Name and writes Image to it, in the
   --  format chosen by the extension. Same exceptions as Open and Append;
   --  an unallocated image or one the format cannot hold is rejected
   --  before an existing file is truncated.

   ---------------------------------------------------------------------
   --  CogImageFileTool
   ---------------------------------------------------------------------

   type Ks_Image_File_Tool is new AMV.Tools.Ks_Tool with record
      Operator     : Ks_Image_File;
      --  Open it before running the tool.
      Input_Image  : AMV.Images.Ks_Image_8_Grey;
      --  The image appended in Write and Update mode.
      Output_Image : AMV.Images.Ks_Image_8_Grey;
      --  The image read in Read mode (set by Run).
      Next_Index   : Natural := 0;
      --  Read mode: the index of the image the next run outputs. Taken
      --  modulo Count, so any value is usable.
   end record;

   overriding procedure Execute (Tool : in out Ks_Image_File_Tool);
   --  Read mode: Output_Image becomes image Next_Index mod Count, converted
   --  to 8-bit grey as Read_Image_8_Grey does (and with its own pixels),
   --  and Next_Index advances by one, back to 0 after the last image.
   --  Write and Update mode: appends Input_Image to the file
   --  (Ks_Image_No_Pixels_Exception when it is unallocated); Output_Image
   --  is not changed.
   --  Raises Ks_Image_File_Exception when Operator is not open.

   overriding procedure Reset_Results (Tool : in out Ks_Image_File_Tool);
   --  Clears Output_Image (to an unallocated image) when Operator is open
   --  in Read mode, because only a Read mode run produces it. In every other
   --  case Output_Image is left alone, so that a Write or Update run does
   --  not discard an image the tool read earlier.

private

   --  The decoded images of a file open in Read mode: a handle of the
   --  kernel (AMV.Kernels.Image_File.Ks_Image_File_Contents) in a box that
   --  the copies of a Ks_Image_File share. The decoded images never change
   --  (Item returns copies), so sharing them is invisible; the box is
   --  freed, with the handle, by its last user.

   type Reference_Count is new Integer with Atomic;

   type Contents_Record is limited record
      References : aliased Reference_Count := 1;
      Handle     : AMV.Kernels.Image_File.Ks_Image_File_Contents;
   end record;

   type Contents_Record_Access is access Contents_Record;

   type Contents_Box is new Ada.Finalization.Controlled with record
      Shared : Contents_Record_Access;
      --  Null when there are no decoded images.
   end record;

   overriding procedure Adjust (Box : in out Contents_Box);
   overriding procedure Finalize (Box : in out Contents_Box);

   --  Stream attributes: the decoded images by value (never the handle),
   --  as their number (Interfaces.Unsigned_32, 0 for none), the kind of
   --  file (Unsigned_32: 1 PNM, 2 BMP, 0 without images) and then for
   --  each image its type
   --  (Unsigned_32: 1 8-bit grey, 2 16-bit grey, 3 colour), its maxval
   --  (Unsigned_32) and the image, written with the stream attributes of
   --  its AMV.Images type. 'Read treats the stream as untrusted: the
   --  kernel checks every number before it is used and every image read
   --  (no pixel above its maxval); a malformed stream raises
   --  Ks_Image_File_Exception and leaves the box without images.

   procedure Write_Contents
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Contents_Box);
   procedure Read_Contents
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Contents_Box);

   for Contents_Box'Write use Write_Contents;
   for Contents_Box'Read use Read_Contents;

   type Ks_Image_File is tagged record
      Current  : Ks_Image_File_Mode_Constants := Closed;
      --  The value of Open_Mode.
      Name     : Ada.Strings.Unbounded.Unbounded_String;
      --  The name given to Open ("" when closed).
      Format   : AMV.Kernels.Int32 := 0;
      --  Write and Update mode: the format chosen by the extension (a
      --  format code of AMV.Kernels.Image_File).
      Contents : Contents_Box;
      --  Read mode: the decoded images.
      Count    : Natural := 0;
      --  The value of Count.
   end record;

end AMV.Image_File;
