--  SPARK kernel for the code reader: reads the linear barcodes of an
--  8-bit grey image, at any orientation and any number of them per image,
--  and its Data Matrix symbols when the run parameters ask for them.
--
--  Symbologies: EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39 and
--  Interleaved 2 of 5 (ITF); Data Matrix (ECC 200).
--
--  What a run does:
--
--   1. Scan lines. The reader scans the bounding box of the pixels of
--      the region that lie in the image, along NumDirections directions;
--      direction k makes the angle FirstDirection + k * Pi / NumDirections
--      with the x axis of pixel space. The scan lines of a direction are
--      parallel, LineSpacing pixels apart and centred on the box; each is
--      sampled bilinearly at steps of one pixel. A sample outside the
--      image or outside the region is not a sample, and splits its line
--      into segments that are read separately.
--
--   2. Edges. Along a segment the grey levels rise and fall. A rise or a
--      fall of at least ContrastThreshold grey levels between a local
--      minimum and the next local maximum (or the reverse) is an edge,
--      located to a fraction of a pixel where the profile crosses the
--      level halfway between the light and the dark level of the
--      surroundings: the highest and the lowest of the extremes nearby
--      (about three characters on either side). A narrow bar between
--      wide spaces does not reach the dark level in a blurred image, and
--      the level halfway between its own extremes would make it too
--      wide. The edges split the segment into alternating dark runs
--      (bars) and light runs (spaces).
--
--      A rise or fall is also ignored when it is less than a quarter of
--      the steepest step between two samples nearby (on the six rises
--      and falls on either side). In a sharp image the levels jump at
--      the edges of the bars, and what swings by less than a quarter of
--      such a jump is no bar: the overshoot next to an edge of a
--      sharpened photograph, or the texture of the print. A blurred
--      image has no steep step, so its narrow bars stay. An overshoot of
--      more than about a fifth of the contrast of the bars (a strong
--      sharpening) is not ignored: it gives edges where there are none,
--      and the symbol is read on few scan lines or not at all.
--
--      ContrastThreshold is an absolute number of grey levels: it must
--      be below the contrast of the symbols and above the swing of the
--      noise. In a noisy image the default finds edges in the noise,
--      which break up the bars and the light margins; raise it then.
--
--   3. Symbols. Every enabled symbology is tried at every bar, reading
--      the runs forwards and backwards (a symbol read backwards is one
--      turned by half a turn). The decoders work on integer run widths
--      and follow the reference decode algorithms: characters are
--      recognised from the distances between edges of the same kind,
--      which do not change when ink spread makes the bars wider and the
--      spaces narrower. The digits 1 and 7, and 2 and 8, of EAN/UPC
--      differ only in the widths of their bars; there the widths are
--      first corrected by how much wider the bars of the guard patterns
--      are than their spaces, which are equal in a perfect symbol. A
--      symbol must have its start and stop patterns,
--      its check character (EAN/UPC and Code 128 always; Code 39 and ITF
--      when the run parameters ask for it) and a light margin on both
--      sides.
--
--   4. Results. Readings of the same text by neighbouring scan lines of
--      one direction form one candidate: a reading joins the candidate
--      whose last reading is at most three lines back and at a matching
--      position (so two lines in between may fail to read the symbol; a
--      symbol that cannot be read over more lines in its middle gives a
--      candidate for each part). A candidate read by fewer than
--      MinScanLines lines is dropped. Of the candidates that lie on top
--      of each other or whose scan lines cross (the same symbol read
--      along two directions, or a partial reading of it) only the one
--      read by the most lines is kept. The results are ordered by the
--      number of scan lines, greatest first.
--
--   5. Data Matrix. When Symbology_Data_Matrix is among the symbologies,
--      a pass of its own follows, which does not use the scan lines. It
--      looks at the bounding box of the pixels of the region that lie in
--      the image; the children of this package describe its steps in
--      full.
--
--      Dark_Areas. The pixels are marked dark or light against a
--      threshold of their neighbourhood, from the blocks of 8 by 8
--      pixels around them whose lightest and darkest pixel differ by
--      ContrastThreshold or more (an area without such a difference has
--      no dark pixel); the pixels outside the region are light. Every
--      connected dark area is followed along its outline, once, and the
--      convex hull of the outline is formed. An outline that encloses
--      64 pixels or less, or that has fewer than nine rows, is passed
--      over, and so is the outline of a hole in a dark area.
--
--      Data_Matrix.Finder. A hull with two solid sides that meet (the
--      "L" of a symbol) and two sides that are not solid gives the four
--      corners of a symbol; they are taken again from all the dark
--      pixels near that outline. The modules are counted along the two
--      alternating sides and looked up at their middles through the
--      perspective mapping of the four corners (a symbol may be seen at
--      an angle); the columns of a symbol at least twice as wide as
--      high are spaced as its alternating upper side shows them, which
--      the corners of a long symbol do not give exactly.
--
--      Data_Matrix and Reed_Solomon. The codewords are read from the
--      modules, corrected and decoded. Until a size gives a text, the
--      sizes one or two modules off the count are tried as well, the
--      nearest first, and then the same for the mirror image of the
--      symbol. A symbol that is read from two dark areas (the same
--      text, and the middles less than half the shorter side of the L
--      apart) is reported once.
--
--      A symbol must be dark on light, with a light margin of two
--      pixels or more all around (the border of the image and the
--      pixels outside the region count as light); its L must be one
--      solid dark area that touches nothing else dark, so a symbol of
--      separate dots is not read, nor one printed light on dark; its
--      modules should be two pixels or more. The 24 square sizes (10 x
--      10 to 144 x 144 modules) and the 6 rectangular ones of ECC 200
--      are read, and the 18 sizes of the rectangular extension (DMRE,
--      ISO/IEC 21471: 8 x 48 to 26 x 64 modules); the older ECC 000 to
--      140 are not. A symbol whose text is empty is not reported.
--
--  Results. Each result has the symbology, the text, the centre, the
--  angle and the four corners of the area the reading scan lines cover:
--  the start of the symbol on the first line, its end on the first line,
--  its end on the last line and its start on the last line. The corners
--  bound the scan lines that read the symbol, not the full height of its
--  bars, and the centre is the middle of that area: across the scan
--  lines it can be about half a line spacing away from the middle of the
--  symbol. The angle is the direction from the start of the symbol to
--  its end: across its bars when at least three scan lines read it, and
--  the direction of the scan lines otherwise. A scan line that passes
--  through a corner of the symbol sees the outermost bar cut short, so
--  the direction of the bars and the ends of the symbol on a line are
--  measured from edges four runs inside the symbol, and the ends lie as
--  far out from them as the lines that cross the whole symbol measure
--  it. Positions are in the space that Selected_From_Pixel maps pixel
--  space to.
--
--  The Data Matrix results follow those of the linear barcodes, in the
--  order in which a scan of the area from its top, left to right, meets
--  their dark areas. Their corners are those of the symbol as it is
--  printed (0: upper left, 1: upper right, 2: lower right, 3: lower
--  left, the corner of the L; in the image the symbol may be turned or
--  mirrored), the angle is the direction from corner 3 to corner 2, the
--  centre is the middle of the symbol as it is printed (where the
--  diagonals cross; for a symbol at least twice as wide as high, the
--  middle of its columns as they were read), and NumScanLines is 0.
--
--  Text:
--   * Data Matrix: the characters of the ASCII, C40, Text, X12, EDIFACT
--     and Base 256 encodations, each as one character (0 .. 255; no
--     character set is applied). FNC1 in the first position (GS1) adds
--     nothing to the text, a later FNC1 is the character GS (29). The
--     macro codewords 05 and 06 add their header and their trailer.
--     ECI, structured append and reader programming codewords are
--     passed over. The text can have up to 3125 characters: a result
--     holds its first Max_Text_Length and its whole length, and
--     Results_Text gives all of it.
--   * EAN-13: 13 digits; EAN-8: 8 digits; UPC-A: 12 digits; UPC-E: 8
--     digits (the number system, the six digits of the symbol and the
--     check digit). A symbol that is both (an EAN-13 symbol whose first
--     digit is 0 is a UPC-A symbol) is reported as UPC-A when UPC-A is
--     enabled and as EAN-13 otherwise.
--   * Code 128: the data characters (code sets A, B and C, shifts and
--     FNC4 for the characters 128 .. 255). FNC1 in the first position
--     (GS1-128) adds nothing to the text; a later FNC1 is the character
--     GS (29). FNC2 and FNC3 add nothing.
--   * Code 39: the 43 characters of the symbology, without the start and
--     stop characters; a check character that was asked for is verified
--     and is part of the text.
--   * ITF: the digits; a check digit that was asked for is verified and
--     is part of the text.
--
--  Failures: Image_No_Pixels for a null image; Bad_Parameter for an
--  invalid image, region, transform or run parameter, and for a region
--  to scan whose width plus height exceeds Max_Line_Samples;
--  Out_Of_Memory; Other when more than Max_Candidates candidates (those
--  of the linear barcodes and the Data Matrix symbols together) arise.
--
--  Proved: no run-time error for any input, a valid status, and for every
--  results handle the facts of Gold_Results. The decoders themselves are
--  checked by the tests. The children of the Data Matrix pass
--  (Dark_Areas, Data_Matrix, Data_Matrix.Finder, Reed_Solomon) are
--  proved free of run-time errors as well, and a word that Reed_Solomon
--  has corrected is proved to be a codeword of its code; that a symbol
--  is found and that its text is the one printed is checked by the
--  tests.
--
--  Trusted parts: the allocation helpers of the body, which turn
--  Storage_Error into null.

pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Images;
with AMV.Kernels.Regions;
with AMV.Kernels.Transforms;

package AMV.Kernels.Code_Reader with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;
   package KT renames AMV.Kernels.Transforms;

   ---------------------------------------------------------------------
   --  Symbologies
   ---------------------------------------------------------------------

   --  One bit each: RunParams.Symbologies is a sum of them, a result's
   --  Symbology is one of them.
   Symbology_EAN_13   : constant := 1;
   Symbology_EAN_8    : constant := 2;
   Symbology_UPC_A    : constant := 4;
   Symbology_UPC_E    : constant := 8;
   Symbology_Code_128 : constant := 16;
   Symbology_Code_39  : constant := 32;
   Symbology_ITF      : constant := 64;

   Symbology_Data_Matrix : constant := 128;

   Symbology_All_Linear : constant := 127;
   Symbology_All        : constant := 255;

   function Is_Symbology (Value : Int32) return Boolean is
     (Value in Symbology_EAN_13 | Symbology_EAN_8 | Symbology_UPC_A
             | Symbology_UPC_E | Symbology_Code_128 | Symbology_Code_39
             | Symbology_ITF | Symbology_Data_Matrix);
   --  One symbology.

   ---------------------------------------------------------------------
   --  Limits
   ---------------------------------------------------------------------

   Max_Text_Length : constant := 255;
   --  The longest text of a linear symbol (one with more is not
   --  reported), and the most characters of any text that a result
   --  record holds.

   Max_Matrix_Text_Length : constant := 7089;
   --  The longest text of a two-dimensional symbol (that of a Data
   --  Matrix symbol has 3125 characters at most).

   Max_Directions : constant := 180;

   Max_Line_Spacing : constant := 1000.0;

   Max_Line_Samples : constant := 2 ** 20;
   --  The longest scan line: the width plus the height of the box to scan
   --  must not exceed it.

   Max_Candidates : constant := 4096;
   --  The most candidates of a run (those of the linear symbologies and
   --  the two-dimensional symbols read, together), and so the most
   --  results.

   Max_Value : constant := KT.Max_Value;
   --  The bound of every Long_Float input.

   ---------------------------------------------------------------------
   --  Run parameters
   ---------------------------------------------------------------------

   type Ks_Code_Reader_Run_Params is record
      Symbologies          : Int32 := Symbology_All_Linear;
      --  The symbologies to read: a sum of Symbology_* in 1 .. 255. Data
      --  Matrix is not among the default ones: its symbols are looked for
      --  in a pass of its own over the image, which takes its time.

      Num_Directions       : Int32 := 12;
      --  The number of scan directions, in 1 .. Max_Directions, evenly
      --  spaced over half a turn.

      First_Direction      : Long_Float := 0.0;
      --  The angle of direction 0 with the x axis of pixel space, in
      --  radians; finite and within Max_Value.

      Line_Spacing         : Long_Float := 4.0;
      --  The distance between neighbouring scan lines, in pixels, in
      --  1.0 .. Max_Line_Spacing.

      Contrast_Threshold   : Int32 := 12;
      --  The smallest rise or fall that is an edge, in grey levels, in
      --  1 .. 255. For Data Matrix: the smallest difference between the
      --  light and the dark pixels of a neighbourhood.

      Min_Scan_Lines       : Int32 := 2;
      --  The fewest scan lines that must read the same symbol, in
      --  1 .. 1000.

      Code_39_Check_Digit  : Int32 := False_Value;
      --  True: a Code 39 symbol must end with its modulo 43 check
      --  character.

      ITF_Check_Digit      : Int32 := False_Value;
      --  True: an ITF symbol must end with its modulo 10 check digit.

      ITF_Min_Digits       : Int32 := 6;
      --  The fewest digits of an ITF symbol, in 2 .. 254. A short ITF
      --  symbol has little to tell it from a part of a longer one.
   end record
   with Convention => C;

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   subtype Text_Length is Natural range 0 .. Max_Text_Length;

   type Code_Text is array (1 .. Max_Text_Length + 1) of Character
     with Convention => C;
   --  C: char[256]. The characters after the text are NUL, so the array
   --  is a C string whenever the text itself holds no NUL (Code 128 can
   --  encode one).

   No_Text : constant Code_Text := [others => ASCII.NUL];

   type Ks_Code_Reader_Result is record
      Symbology      : Int32 := Symbology_EAN_13;
      Length         : Int32 := 0;
      --  The number of characters of the text. A two-dimensional symbol
      --  can have more than Max_Text_Length.
      Text           : Code_Text := No_Text;
      --  The text, or its first Max_Text_Length characters (Results_Text
      --  gives all of them).
      Center_X       : Long_Float := 0.0;
      Center_Y       : Long_Float := 0.0;
      Angle          : Long_Float := 0.0;
      --  The direction from the start of the symbol to its end, in
      --  (-Pi, Pi].
      Corner_0_X     : Long_Float := 0.0;
      Corner_0_Y     : Long_Float := 0.0;
      --  The start of the symbol on the first scan line that read it.
      Corner_1_X     : Long_Float := 0.0;
      Corner_1_Y     : Long_Float := 0.0;
      --  Its end on that line.
      Corner_2_X     : Long_Float := 0.0;
      Corner_2_Y     : Long_Float := 0.0;
      --  Its end on the last scan line that read it.
      Corner_3_X     : Long_Float := 0.0;
      Corner_3_Y     : Long_Float := 0.0;
      --  Its start on that line.
      Num_Scan_Lines : Int32 := 1;
      --  The number of scan lines that read the symbol; 0 for a
      --  two-dimensional symbol, which is not read along scan lines.
   end record
   with Convention => C;
   --  One symbol; 360 bytes.

   No_Result : constant Ks_Code_Reader_Result := (others => <>);

   type Item_Array is array (Natural range <>) of Ks_Code_Reader_Result;
   type Item_Array_Access is access Item_Array;

   type Text_Pool is array (Positive range <>) of Character;
   type Text_Pool_Access is access Text_Pool;

   type Offset_Array is array (Natural range <>) of Natural;
   type Offset_Array_Access is access Offset_Array;

   type Ks_Code_Reader_Results_Data is limited record
      Count  : Natural := 0;
      Items  : Item_Array_Access;
      Starts : Offset_Array_Access;
      Texts  : Text_Pool_Access;
   end record;
   --  What a handle designates (opaque for C): Items (0 .. Count - 1).
   --  The whole text of a two-dimensional symbol, item I, is in Texts
   --  from Starts (I) on; Texts is null when there is no such item.

   type Ks_Code_Reader_Results is access Ks_Code_Reader_Results_Data
     with Convention => C;
   --  C: ks_code_reader_results *.

   function Valid_Results
     (Results : access constant Ks_Code_Reader_Results_Data) return Boolean
   is
     (Results /= null
      and then Results.Count <= Max_Candidates
      and then Results.Items /= null
      and then Results.Items'First = 0
      and then Results.Items'Last < Max_Candidates
      and then Results.Count <= Results.Items'Last + 1
      and then Results.Starts /= null
      and then Results.Starts'First = 0
      and then Results.Starts'Last = Results.Items'Last
      and then (Results.Texts = null or else Results.Texts'First = 1));
   --  A handle as Execute makes it (the structural part).

   function Is_Matrix (Symbology : Int32) return Boolean is
     (Symbology = Symbology_Data_Matrix);
   --  A two-dimensional symbology.

   function Is_Linear (Symbology : Int32) return Boolean is
     (Is_Symbology (Symbology) and then not Is_Matrix (Symbology));
   --  A symbology of linear barcodes.

   function Valid_Item (Item : Ks_Code_Reader_Result) return Boolean is
     (Is_Symbology (Item.Symbology)
      and then Item.Length >= 1
      and then (if Is_Matrix (Item.Symbology)
                then Item.Length <= Max_Matrix_Text_Length
                     and then Item.Num_Scan_Lines = 0
                else Item.Length <= Max_Text_Length
                     and then Item.Num_Scan_Lines >= 1)
      and then (for all I in Natural (Int32'Min (Item.Length,
                                                 Max_Text_Length)) + 1
                               .. Code_Text'Last =>
                  Item.Text (I) = ASCII.NUL));
   --  A symbology, a text that is not empty and whose part in the record
   --  ends with NUL, and at least one scan line for a linear symbol.

   function Text_In_Pool
     (Results : access constant Ks_Code_Reader_Results_Data;
      Index   : Natural) return Boolean
   is
     (Results.Texts /= null
      and then Results.Items (Index).Length
                 in 1 .. Max_Matrix_Text_Length
      and then Results.Starts (Index) >= 1
      and then Results.Texts'Last >= Natural (Results.Items (Index).Length)
      and then Results.Starts (Index) - 1
                 <= Results.Texts'Last
                    - Natural (Results.Items (Index).Length))
   with Pre => Valid_Results (Results) and then Index < Results.Count;
   --  The whole text of item Index is in the pool.

   function Gold_Results
     (Results : access constant Ks_Code_Reader_Results_Data) return Boolean
   is
     (Valid_Results (Results)
      and then (for all I in 0 .. Results.Count - 1 =>
                  Valid_Item (Results.Items (I))
                  and then (if Is_Matrix (Results.Items (I).Symbology)
                            then Text_In_Pool (Results, I))))
   with Ghost;
   --  The proved facts of every handle Execute returns.

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Run_Params_Default
     (Params : out Ks_Code_Reader_Run_Params;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_code_reader_run_params_default",
     Post => Valid (Status) and then Succeeded (Status);
   --  The default run parameters (the record's default values).

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Params              : Ks_Code_Reader_Run_Params;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : out Ks_Code_Reader_Results;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_code_reader_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
                         | Failure_Other
             and then (if Succeeded (Status)
                       then Gold_Results (Results)
                       else Results = null);
   --  Runs the code reader. Region: the pixels to read (the whole image is
   --  the region of ks_pixel_region_whole_image); only its pixels inside
   --  the image count, and a region with none (null, the empty region, is
   --  one) gives no results. Returns a new results handle (null on
   --  failure); a run that finds no symbol succeeds with no results.

   procedure Results_Destroy (Results : in out Ks_Code_Reader_Results)
   with
     Export, Convention => C,
     External_Name => "ks_code_reader_results_destroy",
     Post => Results = null;
   --  Frees the results; nothing for null.

   procedure Results_Count
     (Results : access constant Ks_Code_Reader_Results_Data;
      Count   : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_code_reader_results_count",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Count in 0 .. Max_Candidates;
   --  Count: the number of symbols (0 for null). Bad_Parameter for a
   --  record that is not a results handle.

   procedure Results_Item
     (Results : access constant Ks_Code_Reader_Results_Data;
      Index   : Int32;
      Item    : out Ks_Code_Reader_Result;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_code_reader_results_item",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Results (Results)
                            and then Index in 0 .. Int32 (Results.Count) - 1
                            and then Item
                                       = Results.Items (Natural (Index)));
   --  Item (Index), 0-based (Index_Out_Of_Range outside, always for null).

   procedure Results_Text
     (Results : access constant Ks_Code_Reader_Results_Data;
      Index   : Int32;
      First   : Int32;
      Text    : out Code_Text;
      Length  : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_code_reader_results_text",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then Length in 0 .. Max_Text_Length
             and then (for all I in Natural (Length) + 1 .. Code_Text'Last =>
                         Text (I) = ASCII.NUL);
   --  A part of the text of item Index (0-based): its characters from
   --  position First on (0-based), Max_Text_Length of them at most, in
   --  Text (1 .. Length); the rest of Text is NUL. The whole text of a
   --  two-dimensional symbol with more than Max_Text_Length characters
   --  is read in parts, First = 0, 255, 510, ... while First is less
   --  than the item's Length. Index_Out_Of_Range for an Index outside
   --  the results (always for null); Bad_Parameter for a First outside
   --  0 .. the length of the text (the length itself gives no
   --  character) and for a record that is not a results handle.

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter;
   --  The image check of Execute, made by the Ada API before it
   --  rasterises the region.

   procedure Check_Result_Symbology
     (Item   : Ks_Code_Reader_Result;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                and then Succeeded (Status) = Is_Symbology (Item.Symbology);
   --  Bad_Parameter for a record whose Symbology is not the code of a
   --  symbology (a record changed by hand; never a result of Execute).

   procedure Check_Result_Length
     (Item   : Ks_Code_Reader_Result;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                and then Succeeded (Status)
                         = (Item.Length in 0 .. Max_Matrix_Text_Length);
   --  Bad_Parameter for a record whose Length is not in
   --  0 .. Max_Matrix_Text_Length (a record changed by hand).

   procedure Results_Whole_Text
     (Results : access constant Ks_Code_Reader_Results_Data;
      Index   : Int32;
      Text    : out String;
      Length  : out Natural;
      Status  : out Ks_Status)
   with Pre  => Text'First = 1,
        Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Index_Out_Of_Range
                and then Length <= Text'Length
                and then (if not Succeeded (Status) then Length = 0);
   --  The whole text of item Index (0-based) in Text (1 .. Length); the
   --  rest of Text is NUL. Index_Out_Of_Range for an Index outside the
   --  results (always for null); Bad_Parameter for a Text that is
   --  shorter than the text of the item and for a record that is not a
   --  results handle.

end AMV.Kernels.Code_Reader;
