--  The code reader, Ks_Code_Reader_Tool, with its run parameters
--  (Ks_Code_Reader) and results (Ks_Code_Reader_Results,
--  Ks_Code_Reader_Result).
--
--  The tool reads the linear barcodes of an 8-bit grey image: EAN-13,
--  EAN-8, UPC-A, UPC-E, Code 128, Code 39 and Interleaved 2 of 5 (ITF), at
--  any orientation and any number of them per image:
--
--     Tool.Input_Image := Image;
--     Tool.Run;
--     for I in 0 .. Tool.Results.Count - 1 loop
--        Put_Line (Text (Tool.Results.Item (I)));
--     end loop;
--
--  The image is scanned along parallel lines in NumDirections directions;
--  the edges along each line give the widths of bars and spaces, every
--  enabled symbology is tried at every bar, forwards and backwards, and a
--  symbol is reported when at least MinScanLines neighbouring lines read
--  the same text at matching positions. Check digits are verified (those
--  of Code 39 and ITF when asked for). The method, the rules for the text
--  of each symbology and every limit are described in
--  AMV.Kernels.Code_Reader, the SPARK kernel that does all the work (C
--  API: include/amv_code_reader.h).
--
--  A symbol is read along a line that crosses all of its bars, so the
--  scan directions must be dense enough for its shape. The nearest scan
--  direction is at most 90 / NumDirections degrees away from the
--  direction of a symbol: the default 12 directions (every 15 degrees)
--  read symbols whose bars are at least a fifth as tall as the symbol is
--  long, and 24 directions read bars a tenth as tall. When the direction
--  of the symbols is known, NumDirections = 1 with FirstDirection reads
--  them along it, in a twelfth of the time.
--
--  Image quality. The narrowest bars and spaces (the modules) must be at
--  least 1.5 pixels wide. ContrastThreshold is an absolute number of
--  grey levels, below the contrast of the symbols and above the swing of
--  the noise: in a noisy image the default (12) finds edges in the
--  noise, so raise it there. The overshoot beside the bars of a
--  sharpened image is ignored while it is small, up to about a fifth of
--  the contrast between bars and spaces; a stronger sharpening gives
--  edges where there are none, and the symbol is read on few scan lines
--  or not at all. A symbol that cannot be read over three or more
--  neighbouring scan lines in its middle (a scratch along it) is
--  reported once for each readable part.
--
--  Accuracy. On clean symbols the angle is right to about half a degree
--  and the ends of the symbol to a pixel. The corners bound the scan
--  lines that read the symbol, not the full height of its bars, and the
--  centre is the middle of that area: across the scan lines it can be
--  half a LineSpacing away from the middle of the symbol.
--
--  Coordinates: the region is taken in its own selected space; the
--  centre, the corners and the angle of a result are reported in the
--  input image's selected space (".").
--
--  Run parameters: Ks_Code_Reader is the kernel's C-compatible record, so
--  Booleans are 0 or 1 and Symbologies is a sum of codes:
--
--     Tool.Run_Params.Symbologies := Code (EAN_13) + Code (Code_128);
--     Tool.Run_Params.Num_Directions := 2;   --  horizontal and vertical
--
--  Results are shared by copies of the tool or of the results (read-only;
--  the next run replaces them) and are not stored in streams.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels.Code_Reader;
with AMV.Shapes.Region_Holders;
with AMV.Tools;

private with AMV.Shared_Handles;

package AMV.Code_Reader is

   package KC renames AMV.Kernels.Code_Reader;

   subtype Int32 is AMV.Kernels.Int32;

   ---------------------------------------------------------------------
   --  Symbologies
   ---------------------------------------------------------------------

   type Ks_Code_Reader_Symbology_Constants is
     (EAN_13, EAN_8, UPC_A, UPC_E, Code_128, Code_39, ITF);
   for Ks_Code_Reader_Symbology_Constants use
     (EAN_13   => KC.Symbology_EAN_13,
      EAN_8    => KC.Symbology_EAN_8,
      UPC_A    => KC.Symbology_UPC_A,
      UPC_E    => KC.Symbology_UPC_E,
      Code_128 => KC.Symbology_Code_128,
      Code_39  => KC.Symbology_Code_39,
      ITF      => KC.Symbology_ITF);

   function Code (Value : Ks_Code_Reader_Symbology_Constants) return Int32
   is (Ks_Code_Reader_Symbology_Constants'Enum_Rep (Value));
   --  The code of a symbology: one bit each, so that
   --  Run_Params.Symbologies is a sum of codes.

   All_Linear_Symbologies : constant Int32 := KC.Symbology_All_Linear;
   --  The sum of all of them (the default of Run_Params.Symbologies).

   ---------------------------------------------------------------------
   --  Run parameters
   ---------------------------------------------------------------------

   subtype Ks_Code_Reader is KC.Ks_Code_Reader_Run_Params;
   --  The run parameters, with their defaults: Symbologies (all),
   --  Num_Directions (12, evenly spaced over half a turn),
   --  First_Direction (0.0 radians from the x axis of pixel space),
   --  Line_Spacing (4.0 pixels between scan lines), Contrast_Threshold
   --  (12 grey levels: the smallest rise or fall that is an edge),
   --  Min_Scan_Lines (2), Code_39_Check_Digit and ITF_Check_Digit (0:
   --  no check character is expected) and ITF_Min_Digits (6). They are
   --  checked when the tool runs (Ks_Bad_Parameter_Exception naming the
   --  property, "RunParams.NumDirections must be in 1 .. 180").

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   subtype Ks_Code_Reader_Result is KC.Ks_Code_Reader_Result;
   --  A symbol: Symbology (a code), Length and Text (see the function
   --  Text), Center_X and Center_Y, Angle (the direction from the start
   --  of the symbol to its end, in (-Pi, Pi]), the corners (0: the start
   --  of the symbol on the first scan line that read it, 1: its end on
   --  that line, 2 and 3: its end and its start on the last such line)
   --  and Num_Scan_Lines (the number of scan lines that read it).

   function Symbology
     (Result : Ks_Code_Reader_Result)
      return Ks_Code_Reader_Symbology_Constants;
   --  Result.Symbology as an enumeration value.
   --  Ks_Bad_Parameter_Exception for a record whose Symbology is not a
   --  code (a record changed by hand; never a result of the tool).

   function Text (Result : Ks_Code_Reader_Result) return String;
   --  The text of the symbol: Result.Text (1 .. Result.Length). For
   --  EAN-13, EAN-8, UPC-A and UPC-E the digits with the check digit (13,
   --  8, 12 and 8 of them); for the other symbologies the characters the
   --  symbol encodes. Ks_Bad_Parameter_Exception for a record whose
   --  Length is not in 0 .. 255 (never for a result of the tool).

   type Ks_Code_Reader_Results is tagged private;
   --  The results of a run; empty before the first successful run.

   function Count (Results : Ks_Code_Reader_Results) return Natural;
   --  The number of symbols read.

   function Item
     (Results : Ks_Code_Reader_Results;
      Index   : Natural) return Ks_Code_Reader_Result;
   --  Symbol Index (0-based); the symbols read by the most scan lines
   --  come first. Constraint_Error unless Index < Count.

   ---------------------------------------------------------------------
   --  The tool
   ---------------------------------------------------------------------

   type Ks_Code_Reader_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Region      : AMV.Shapes.Region_Holders.Holder;
      Run_Params  : Ks_Code_Reader;
      Results     : Ks_Code_Reader_Results;
   end record;
   --  Region: any region type of AMV.Shapes in a space of Input_Image's
   --  tree; an empty holder is the whole image. Only the pixels of the
   --  region are read, so a symbol must lie in it with its light margins.
   --  Results is set by Run.

   overriding procedure Execute (Tool : in out Ks_Code_Reader_Tool);
   --  Reads the symbols of Input_Image within Region. Raises
   --  Ks_Image_No_Pixels_Exception for an unallocated image,
   --  Ks_Bad_Parameter_Exception for bad run parameters or an area to
   --  scan that is too large (its width plus its height above 1048576
   --  pixels) and Ks_Exception when more than 4096 candidates arise (see
   --  AMV.Kernels.Code_Reader), besides the exceptions of
   --  AMV.Regions.Rasterize for the region; Run reports them in
   --  Run_Status. Finding no symbol is a success with no results.

   overriding procedure Reset_Results (Tool : in out Ks_Code_Reader_Tool);

private

   procedure Destroy (Handle : in out KC.Ks_Code_Reader_Results);

   package Results_Holders is new AMV.Shared_Handles
     (KC.Ks_Code_Reader_Results, null, Destroy);

   type Ks_Code_Reader_Results is tagged record
      Holder : Results_Holders.Holder;
   end record;

end AMV.Code_Reader;
