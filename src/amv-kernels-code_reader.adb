pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;
with AMV.Kernels.Code_Reader.Dark_Areas;
with AMV.Kernels.Code_Reader.Data_Matrix;
with AMV.Kernels.Code_Reader.Data_Matrix.Finder;
with AMV.Kernels.Code_Reader.Linear;
with AMV.Kernels.Code_Reader.Profiles;
with AMV.Kernels.Code_Reader.QR_Code;
with AMV.Kernels.Code_Reader.QR_Code.Finder;
with AMV.Kernels.Code_Reader.Reed_Solomon;
with AMV.Kernels.Code_Reader.Views;
with AMV.Kernels.Filter_Inputs;
with AMV.Kernels.Image_Sampling;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Code_Reader with SPARK_Mode is

   package DA renames AMV.Kernels.Code_Reader.Dark_Areas;
   package DM renames AMV.Kernels.Code_Reader.Data_Matrix;
   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package FI renames AMV.Kernels.Filter_Inputs;
   package FN renames AMV.Kernels.Code_Reader.Data_Matrix.Finder;
   package L renames AMV.Kernels.Code_Reader.Linear;
   package N renames AMV.Kernels.Numerics;
   package P renames AMV.Kernels.Code_Reader.Profiles;
   package QF renames AMV.Kernels.Code_Reader.QR_Code.Finder;
   package QR renames AMV.Kernels.Code_Reader.QR_Code;
   package RS renames AMV.Kernels.Code_Reader.Reed_Solomon;
   package Sampling renames AMV.Kernels.Image_Sampling;
   package VW renames AMV.Kernels.Code_Reader.Views;

   use type DA.Mark;
   use type KR.Flag_Matrix_Access;

   ---------------------------------------------------------------------
   --  Constants of the method
   ---------------------------------------------------------------------

   Min_Segment : constant := 24;
   --  The shortest segment of a scan line that is read, in samples. No
   --  symbol is that short, even at one pixel per module.

   Max_Line_Gap : constant := 3;
   --  A reading joins a candidate whose last reading is at most this many
   --  scan lines back.

   Join_Slack : constant := 2.0;
   --  From one scan line to the next the start and the end of a symbol
   --  move by at most the distance between the lines (a symbol turned by
   --  up to 45 degrees against the scan direction), plus this, in pixels.

   Inset : constant := 4;
   --  The two edges that place a symbol on a scan line, its inner edges,
   --  are this many runs from its start and from its end (see
   --  Candidate): the start of its third bar and the end of its third
   --  bar from the end. Every symbol has more runs than twice this.

   Min_Angle_Lines : constant := 3;
   --  From this many scan lines on, the angle of a result comes from the
   --  direction of the bars; with fewer it is the scan direction.

   ---------------------------------------------------------------------
   --  Types
   ---------------------------------------------------------------------

   type Level_Array_Access is access P.Level_Array;
   type Extreme_Array_Access is access P.Extreme_Array;
   type Position_Array_Access is access L.Position_Array;

   subtype Symbology_Code is Int32
     with Static_Predicate =>
       Symbology_Code in Symbology_EAN_13 | Symbology_EAN_8
                       | Symbology_UPC_A | Symbology_UPC_E
                       | Symbology_Code_128 | Symbology_Code_39
                       | Symbology_ITF;

   subtype Symbol_Length is Text_Length range 1 .. Max_Text_Length;

   subtype Unit is Long_Float range -1.0 .. 1.0;

   Origin_Limit : constant := P.Coordinate_Limit;
   --  The bound of the first sample of a scan line, in pixels.

   subtype Origin is Long_Float range -Origin_Limit .. Origin_Limit;

   Along_Limit : constant := 2.0 ** 21;
   --  The bound of a position along a scan line, in samples from its
   --  first one: Max_Line_Samples for the segment's start and as much
   --  again for the position in the segment.

   subtype Along is Long_Float range -Along_Limit .. Along_Limit;

   Point_Limit : constant := 2.0 ** 41;

   subtype Coordinate is Long_Float range -Point_Limit .. Point_Limit;

   type Point is record
      X : Coordinate := 0.0;
      Y : Coordinate := 0.0;
   end record;
   --  A point of pixel space.

   type Scan_Line is record
      Index : Natural := 0;
      --  The number of the line in its direction.
      X0    : Origin := 0.0;
      Y0    : Origin := 0.0;
      --  Its first sample, in pixel space.
      UX    : Unit := 1.0;
      UY    : Unit := 0.0;
      --  The step from a sample to the next: the scan direction.
   end record;

   Bar_Limit : constant := 2.0 * Along_Limit;

   subtype Bar_Width is Long_Float range 0.0 .. Bar_Limit;
   --  The distance between two positions along a scan line.

   type Candidate_State is (Pending, Accepted, Rejected);

   type Candidate is record
      Symbology : Symbology_Code := Symbology_EAN_13;
      Length    : Symbol_Length := 1;
      Text      : Code_Text := No_Text;
      Reversed  : Boolean := False;
      --  Read backwards along the scan direction.
      Last_Line : Natural := 0;
      --  The last scan line that read it.
      Lines     : Positive := 1;
      --  The number of scan lines that read it.
      First     : Scan_Line;
      --  The first scan line that read it.
      First_S_T : Along := 0.0;
      First_E_T : Along := 0.0;
      --  The inner edges of the symbol on the first line: the one near
      --  its start and the one near its end.
      Last_S_T  : Along := 0.0;
      Last_E_T  : Along := 0.0;
      --  The same on the last line.
      Bar_S     : Bar_Width := 0.0;
      Bar_E     : Bar_Width := 0.0;
      --  The distance from the start of the symbol to its inner edge and
      --  from the other inner edge to its end: the greatest that a line
      --  measured.
      BS1, BE1  : Point;
      --  The points at First_S_T and First_E_T of the first line.
      BS2, BE2  : Point;
      --  The points at Last_S_T and Last_E_T of the last line.
      S1, E1    : Point;
      --  The start and the end of the symbol on the first line: Bar_S
      --  before BS1 and Bar_E after BE1.
      S2, E2    : Point;
      --  The same on the last line.
      State     : Candidate_State := Pending;
   end record;
   --  The readings of one text by neighbouring scan lines of a direction.
   --
   --  A scan line through a corner of the symbol leaves the outermost
   --  bar through its side: it sees that bar cut short, and the edges
   --  next to it through the blur of the corner. The edges Inset runs
   --  further in are seen where they are, so they give the position of
   --  the symbol on a line and the direction of its bars, and the ends
   --  of the symbol lie as far out from them as the lines that cross the
   --  whole symbol measure it.

   type Candidate_Array is array (Natural range <>) of Candidate;
   type Candidate_Array_Access is access Candidate_Array;

   type Scan_Box is record
      X_Lo, X_Hi : Natural := 0;
      Y_Lo, Y_Hi : Natural := 0;
   end record;
   --  The pixels to scan: columns X_Lo .. X_Hi of rows Y_Lo .. Y_Hi.

   function Valid_Box (Box : Scan_Box) return Boolean is
     (Box.X_Lo <= Box.X_Hi and then Box.Y_Lo <= Box.Y_Hi
      and then Int64 (Box.X_Hi - Box.X_Lo) + Int64 (Box.Y_Hi - Box.Y_Lo)
                 < Max_Line_Samples);

   type Scan_Settings is record
      Spacing   : Long_Float := 4.0;
      Threshold : Positive := 12;
      Min_Lines : Positive := 2;
      Options   : L.Decode_Options;
   end record;
   --  The run parameters in the types of the body.

   function Valid_Settings (Settings : Scan_Settings) return Boolean is
     (Settings.Spacing >= 1.0 and then Settings.Spacing <= Max_Line_Spacing
      and then Settings.Threshold <= 255);

   type Map_Access is access DA.Mark_Map;
   type Block_Access is access KI.Grey_8_Matrix;
   type Extent_Access is access DA.Extent_Array;
   type Hull_Access is access DA.Point_Array;

   pragma Compile_Time_Error
     (DM.Max_Text_Length > Max_Matrix_Text_Length,
      "the text of a Data Matrix symbol must fit a result");
   pragma Compile_Time_Error
     (QR.Max_Text_Length > Max_Matrix_Text_Length,
      "the text of a QR Code symbol must fit a result");

   subtype Matrix_Length is Positive range 1 .. Max_Matrix_Text_Length;

   type Matrix_Kind is (Data_Matrix_Symbol, QR_Code_Symbol);

   type Matrix_Symbol is record
      Kind           : Matrix_Kind := Data_Matrix_Symbol;
      UL, UR, LR, LL : Point;
      --  The corners of the symbol as it is printed, in pixel space:
      --  the upper left, the upper right, the lower right and the lower
      --  left one (of a Data Matrix symbol the corner of the L; a QR
      --  Code symbol has its finder patterns in the three others).
      Middle         : Point;
      --  The middle of the symbol as it is printed (Sample of the two
      --  finders).
      Start          : Positive := 1;
      Length         : Matrix_Length := 1;
      --  Its text: Length characters of the pool, from Start on.
   end record;
   --  A two-dimensional symbol that was read.

   type Symbol_Array is array (Natural range <>) of Matrix_Symbol;
   type Symbol_Array_Access is access Symbol_Array;

   procedure Free is new Ada.Unchecked_Deallocation
     (DA.Mark_Map, Map_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Grey_8_Matrix, Block_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (DA.Extent_Array, Extent_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (DA.Point_Array, Hull_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Symbol_Array, Symbol_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Text_Pool, Text_Pool_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Offset_Array, Offset_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (P.Level_Array, Level_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (P.Extreme_Array, Extreme_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (L.Position_Array, Position_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Candidate_Array, Candidate_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Item_Array, Item_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Code_Reader_Results_Data, Ks_Code_Reader_Results);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Levels
     (Length : Positive;
      Levels : out Level_Array_Access)
   with
     Global => null,
     Post   => (if Levels /= null
                then Levels'First = 0 and then Levels'Last = Length - 1);
   --  A new array of Length levels indexed from 0, every one No_Sample,
   --  or null when the memory cannot be allocated. Trusted: the allocator
   --  raises Storage_Error, which SPARK cannot express.

   procedure Allocate_Levels
     (Length : Positive;
      Levels : out Level_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Levels := new P.Level_Array'(0 .. Length - 1 => P.No_Sample);
   exception
      when Storage_Error =>
         Levels := null;
   end Allocate_Levels;

   procedure Allocate_Extremes
     (Length   : Positive;
      Extremes : out Extreme_Array_Access)
   with
     Global => null,
     Post   => (if Extremes /= null
                then Extremes'First = 0
                     and then Extremes'Last = Length - 1);
   --  A new array of Length extremes indexed from 0, or null. Trusted
   --  as above.

   procedure Allocate_Extremes
     (Length   : Positive;
      Extremes : out Extreme_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Extremes := new P.Extreme_Array'(0 .. Length - 1 => <>);
   exception
      when Storage_Error =>
         Extremes := null;
   end Allocate_Extremes;

   procedure Allocate_Positions
     (Length    : Positive;
      Positions : out Position_Array_Access)
   with
     Global => null,
     Post   => (if Positions /= null
                then Positions'First = 0
                     and then Positions'Last = Length - 1);
   --  A new array of Length positions indexed from 0, every one 0, or
   --  null. Trusted as above.

   procedure Allocate_Positions
     (Length    : Positive;
      Positions : out Position_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Positions := new L.Position_Array'(0 .. Length - 1 => 0);
   exception
      when Storage_Error =>
         Positions := null;
   end Allocate_Positions;

   procedure Allocate_Candidates (Table : out Candidate_Array_Access)
   with
     Global => null,
     Post   => (if Table /= null
                then Table'First = 0
                     and then Table'Last = Max_Candidates - 1);
   --  A new table of Max_Candidates candidates indexed from 0 (the
   --  record's default values), or null. Trusted as above.

   procedure Allocate_Candidates (Table : out Candidate_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Table := new Candidate_Array (0 .. Max_Candidates - 1);
   exception
      when Storage_Error =>
         Table := null;
   end Allocate_Candidates;

   procedure Allocate_Items
     (Count : Positive;
      Items : out Item_Array_Access)
   with
     Global => null,
     Post   => (if Items /= null
                then Items'First = 0 and then Items'Last = Count - 1);
   --  A new array of Count results indexed from 0 (the record's default
   --  values), or null. Trusted as above.

   procedure Allocate_Items
     (Count : Positive;
      Items : out Item_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Items := new Item_Array (0 .. Count - 1);
   exception
      when Storage_Error =>
         Items := null;
   end Allocate_Items;

   procedure Allocate_Results (Results : out Ks_Code_Reader_Results)
   with
     Global => null,
     Post   => (if Results /= null
                then Results.Count = 0 and then Results.Items = null
                     and then Results.Starts = null
                     and then Results.Texts = null);
   --  A new results record with the record's default values, or null.
   --  Trusted as above.

   procedure Allocate_Results (Results : out Ks_Code_Reader_Results)
     with SPARK_Mode => Off
   is
   begin
      Results := new Ks_Code_Reader_Results_Data;
   exception
      when Storage_Error =>
         Results := null;
   end Allocate_Results;

   procedure Allocate_Map
     (Rows, Columns : Positive;
      Map           : out Map_Access)
   with
     Global => null,
     Post   => (if Map /= null
                then Map'First (1) = 0 and then Map'Last (1) = Rows - 1
                     and then Map'First (2) = 0
                     and then Map'Last (2) = Columns - 1);
   --  A new map of Rows by Columns pixels indexed from 0, every one
   --  light, or null. Trusted as above.

   procedure Allocate_Map
     (Rows, Columns : Positive;
      Map           : out Map_Access)
     with SPARK_Mode => Off
   is
   begin
      Map := new DA.Mark_Map (0 .. Rows - 1, 0 .. Columns - 1);
      for Y in Map'Range (1) loop
         for X in Map'Range (2) loop
            Map (Y, X) := DA.Light;
         end loop;
      end loop;
   exception
      when Storage_Error =>
         Map := null;
   end Allocate_Map;

   procedure Allocate_Blocks
     (Rows, Columns : Positive;
      Blocks        : out Block_Access)
   with
     Global => null,
     Post   => (if Blocks /= null
                then Blocks'First (1) = 0 and then Blocks'Last (1) = Rows - 1
                     and then Blocks'First (2) = 0
                     and then Blocks'Last (2) = Columns - 1);
   --  A new matrix of Rows by Columns levels indexed from 0, every one
   --  0, or null. Trusted as above.

   procedure Allocate_Blocks
     (Rows, Columns : Positive;
      Blocks        : out Block_Access)
     with SPARK_Mode => Off
   is
   begin
      Blocks := new KI.Grey_8_Matrix (0 .. Rows - 1, 0 .. Columns - 1);
      for Y in Blocks'Range (1) loop
         for X in Blocks'Range (2) loop
            Blocks (Y, X) := 0;
         end loop;
      end loop;
   exception
      when Storage_Error =>
         Blocks := null;
   end Allocate_Blocks;

   procedure Allocate_Extents
     (Length  : Positive;
      Value   : Integer;
      Extents : out Extent_Access)
   with
     Global => null,
     Post   => (if Extents /= null
                then Extents'First = 0 and then Extents'Last = Length - 1
                     and then (for all I in Extents'Range =>
                                 Extents (I) = Value));
   --  A new array of Length extents indexed from 0, every one Value, or
   --  null. Trusted as above.

   procedure Allocate_Extents
     (Length  : Positive;
      Value   : Integer;
      Extents : out Extent_Access)
     with SPARK_Mode => Off
   is
   begin
      Extents := new DA.Extent_Array (0 .. Length - 1);
      for I in Extents'Range loop
         Extents (I) := Value;
      end loop;
   exception
      when Storage_Error =>
         Extents := null;
   end Allocate_Extents;

   procedure Allocate_Hull
     (Length : Positive;
      Points : out Hull_Access)
   with
     Global => null,
     Post   => (if Points /= null
                then Points'First = 1 and then Points'Last = Length);
   --  A new array of Length points indexed from 1, every one (0, 0), or
   --  null. Trusted as above.

   procedure Allocate_Hull
     (Length : Positive;
      Points : out Hull_Access)
     with SPARK_Mode => Off
   is
   begin
      Points := new DA.Point_Array (1 .. Length);
      for I in Points'Range loop
         Points (I) := (0, 0);
      end loop;
   exception
      when Storage_Error =>
         Points := null;
   end Allocate_Hull;

   procedure Allocate_Symbols (Symbols : out Symbol_Array_Access)
   with
     Global => null,
     Post   => (if Symbols /= null
                then Symbols'First = 0
                     and then Symbols'Last = Max_Candidates - 1);
   --  A new table of Max_Candidates symbols indexed from 0 (the record's
   --  default values), or null. Trusted as above.

   procedure Allocate_Symbols (Symbols : out Symbol_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Symbols := new Symbol_Array (0 .. Max_Candidates - 1);
   exception
      when Storage_Error =>
         Symbols := null;
   end Allocate_Symbols;

   procedure Allocate_Texts
     (Length : Positive;
      Texts  : out Text_Pool_Access)
   with
     Global => null,
     Post   => (if Texts /= null
                then Texts'First = 1 and then Texts'Last = Length);
   --  A new pool of Length characters indexed from 1, every one NUL, or
   --  null. Trusted as above.

   procedure Allocate_Texts
     (Length : Positive;
      Texts  : out Text_Pool_Access)
     with SPARK_Mode => Off
   is
   begin
      Texts := new Text_Pool (1 .. Length);
      for I in Texts'Range loop
         Texts (I) := ASCII.NUL;
      end loop;
   exception
      when Storage_Error =>
         Texts := null;
   end Allocate_Texts;

   procedure Allocate_Starts
     (Count  : Positive;
      Starts : out Offset_Array_Access)
   with
     Global => null,
     Post   => (if Starts /= null
                then Starts'First = 0 and then Starts'Last = Count - 1);
   --  A new array of Count offsets indexed from 0, every one 0, or null.
   --  Trusted as above.

   procedure Allocate_Starts
     (Count  : Positive;
      Starts : out Offset_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Starts := new Offset_Array'(0 .. Count - 1 => 0);
   exception
      when Storage_Error =>
         Starts := null;
   end Allocate_Starts;

   ---------------------------------------------------------------------
   --  Messages and parameters
   ---------------------------------------------------------------------

   procedure Bad
     (Status  : out Ks_Status;
      Message : String)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad
     (Status  : out Ks_Status;
      Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Out_Of_Memory (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Out_Of_Memory;

   procedure Out_Of_Memory (Status : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Out_Of_Memory,
                   "CodeReader: out of memory");
   end Out_Of_Memory;

   function Valid_Params (Params : Ks_Code_Reader_Run_Params) return Boolean
   is
     (Params.Symbologies in 1 .. Symbology_All
      and then Params.Num_Directions in 1 .. Max_Directions
      and then N.In_Range (Params.First_Direction, Max_Value)
      and then Params.Line_Spacing >= 1.0
      and then Params.Line_Spacing <= Max_Line_Spacing
      and then Params.Contrast_Threshold in 1 .. 255
      and then Params.Min_Scan_Lines in 1 .. 1000
      and then Params.Code_39_Check_Digit in False_Value | True_Value
      and then Params.ITF_Check_Digit in False_Value | True_Value
      and then Params.ITF_Min_Digits in 2 .. 254);

   procedure Check_Params
     (Params : Ks_Code_Reader_Run_Params;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Valid_Params (Params));

   procedure Check_Params
     (Params : Ks_Code_Reader_Run_Params;
      Status : out Ks_Status) is
   begin
      if Params.Symbologies not in 1 .. Symbology_All then
         Bad (Status, "RunParams.Symbologies must be a sum of"
                      & " KS_CODE_READER_SYMBOLOGY_*, in 1 .. 511");
      elsif Params.Num_Directions not in 1 .. Max_Directions then
         Bad (Status, "RunParams.NumDirections must be in 1 .. 180");
      elsif not N.In_Range (Params.First_Direction, Max_Value) then
         Bad (Status, "RunParams.FirstDirection must be finite and within"
                      & " +/-1.0E150");
      elsif not (Params.Line_Spacing >= 1.0
                 and then Params.Line_Spacing <= Max_Line_Spacing)
      then
         Bad (Status, "RunParams.LineSpacing must be in 1.0 .. 1000.0");
      elsif Params.Contrast_Threshold not in 1 .. 255 then
         Bad (Status, "RunParams.ContrastThreshold must be in 1 .. 255");
      elsif Params.Min_Scan_Lines not in 1 .. 1000 then
         Bad (Status, "RunParams.MinScanLines must be in 1 .. 1000");
      elsif Params.Code_39_Check_Digit not in False_Value | True_Value then
         Bad (Status, "RunParams.Code39CheckDigit must be 0 or 1");
      elsif Params.ITF_Check_Digit not in False_Value | True_Value then
         Bad (Status, "RunParams.ITFCheckDigit must be 0 or 1");
      elsif Params.ITF_Min_Digits not in 2 .. 254 then
         Bad (Status, "RunParams.ITFMinDigits must be in 2 .. 254");
      else
         Set_Success (Status);
      end if;
   end Check_Params;

   function Has
     (Symbologies : Int32;
      Bit         : Int32) return Boolean
   is
     ((Symbologies / Bit) mod 2 = 1)
   with Pre => Symbologies >= 0 and then Bit >= 1;
   --  Bit (a power of two) is in the sum Symbologies.

   function Settings_Of
     (Params : Ks_Code_Reader_Run_Params) return Scan_Settings
   is
     (Spacing   => Params.Line_Spacing,
      Threshold => Positive (Params.Contrast_Threshold),
      Min_Lines => Positive (Params.Min_Scan_Lines),
      Options   =>
        (EAN_13         => Has (Params.Symbologies, Symbology_EAN_13),
         EAN_8          => Has (Params.Symbologies, Symbology_EAN_8),
         UPC_A          => Has (Params.Symbologies, Symbology_UPC_A),
         UPC_E          => Has (Params.Symbologies, Symbology_UPC_E),
         Code_128       => Has (Params.Symbologies, Symbology_Code_128),
         Code_39        => Has (Params.Symbologies, Symbology_Code_39),
         ITF            => Has (Params.Symbologies, Symbology_ITF),
         Code_39_Check  => Params.Code_39_Check_Digit = True_Value,
         ITF_Check      => Params.ITF_Check_Digit = True_Value,
         ITF_Min_Digits => Positive (Params.ITF_Min_Digits)))
   with
     Pre  => Valid_Params (Params),
     Post => Valid_Settings (Settings_Of'Result);

   ---------------------------------------------------------------------
   --  Scan lines
   ---------------------------------------------------------------------

   function To_Unit (X : Long_Float) return Unit is (N.Clamp (X, 1.0));
   --  A cosine or a sine; the limit never acts.

   function To_Origin (X : Long_Float) return Origin is
     (N.Clamp (X, Origin_Limit));
   --  The first sample of a line lies within a few image sizes of the
   --  image; the limit never acts.

   --  The functions below that have a body of their own are not
   --  expression functions, so that the proof of a caller gets their
   --  bounds and nothing else.

   function Middle (Lo, Hi : Natural) return Long_Float
   with Post => Middle'Result >= 0.0 and then Middle'Result <= 2.0 ** 31;
   --  The middle of two pixel coordinates.

   function Middle (Lo, Hi : Natural) return Long_Float is
   begin
      return (Long_Float (Lo) + Long_Float (Hi)) / 2.0;
   end Middle;

   function Half_Of (Count : Positive) return Long_Float
   with
     Pre  => Count <= Max_Line_Samples,
     Post => Half_Of'Result >= 0.0 and then Half_Of'Result <= 2.0 ** 19;
   --  From the first of Count items in a row to the middle of the row,
   --  in items.

   function Half_Of (Count : Positive) return Long_Float is
   begin
      return Long_Float (Count - 1) / 2.0;
   end Half_Of;

   function From_Middle (Index : Natural; Count : Positive) return Long_Float
   with
     Pre  => Index < Count and then Count <= Max_Line_Samples,
     Post => abs From_Middle'Result <= 2.0 ** 20;
   --  From the middle of a row of Count items to its item Index (the
   --  first one is item 0), in items.

   function From_Middle (Index : Natural; Count : Positive) return Long_Float
   is
   begin
      return Long_Float (Index) - Half_Of (Count);
   end From_Middle;

   function Count_Of
     (Extent : Long_Float;
      Max    : Positive) return Positive
   is
     (if not (Extent >= 1.0) then 1
      elsif Extent >= Long_Float (Max - 1) then Max
      else Natural'Min (Natural (Long_Float'Floor (Extent)), Max - 1) + 1)
   with
     Pre  => Max <= Max_Line_Samples,
     Post => Count_Of'Result <= Max;
   --  Floor (Extent) + 1, the number of steps of one unit that fit in
   --  Extent and one more, limited to 1 .. Max. The minimum never acts:
   --  Extent is below Max - 1 there, and so is its floor.

   function Extent (W, H : Long_Float; U, V : Unit) return Long_Float
   with
     Pre  => W >= 0.0 and then W <= 2.0 ** 31
             and then H >= 0.0 and then H <= 2.0 ** 31,
     Post => Extent'Result >= 0.0 and then Extent'Result <= 2.0 ** 32;
   --  The extent of a box of W by H along the direction (U, V).

   function Extent (W, H : Long_Float; U, V : Unit) return Long_Float is
   begin
      return N.Times_Unit (W, abs U) + N.Times_Unit (H, abs V);
   end Extent;

   function Line_Count
     (Across  : Long_Float;
      Spacing : Long_Float;
      Max     : Positive) return Positive
   with
     Pre  => Across >= 0.0 and then Across <= 2.0 ** 32
             and then Spacing >= 1.0 and then Spacing <= Max_Line_Spacing
             and then Max <= Max_Line_Samples,
     Post => Line_Count'Result <= Max;
   --  The number of lines, Spacing apart, of a box that is Across wide.

   function Line_Count
     (Across  : Long_Float;
      Spacing : Long_Float;
      Max     : Positive) return Positive is
   begin
      return Count_Of (Across / Spacing, Max);
   end Line_Count;

   Offset_Limit : constant := 2.0 ** 20 * Max_Line_Spacing;
   --  The middle line of a direction to any of its lines, at most.

   function Start_X
     (CX, Offset, Half : Long_Float;
      UX, UY           : Unit) return Origin
   with
     Pre => CX >= 0.0 and then CX <= 2.0 ** 31
            and then abs Offset <= Offset_Limit
            and then Half >= 0.0 and then Half <= 2.0 ** 19;
   --  The first sample of a scan line of the direction (UX, UY): from the
   --  centre of the box (CX, and CY below) Offset across the direction
   --  and Half back along it.

   function Start_X
     (CX, Offset, Half : Long_Float;
      UX, UY           : Unit) return Origin is
   begin
      return To_Origin (CX - N.Times_Unit (Offset, UY)
                        - N.Times_Unit (Half, UX));
   end Start_X;

   function Start_Y
     (CY, Offset, Half : Long_Float;
      UX, UY           : Unit) return Origin
   with
     Pre => CY >= 0.0 and then CY <= 2.0 ** 31
            and then abs Offset <= Offset_Limit
            and then Half >= 0.0 and then Half <= 2.0 ** 19;

   function Start_Y
     (CY, Offset, Half : Long_Float;
      UX, UY           : Unit) return Origin is
   begin
      return To_Origin (CY + N.Times_Unit (Offset, UX)
                        - N.Times_Unit (Half, UY));
   end Start_Y;

   function Turn_Of (Index : Natural; Count : Positive) return Long_Float
   with
     Pre  => Index < Count and then Count <= Max_Directions,
     Post => Turn_Of'Result >= 0.0 and then Turn_Of'Result <= 4.0;
   --  Pi * Index / Count: the part Index of Count of half a turn.

   function Turn_Of (Index : Natural; Count : Positive) return Long_Float is
   begin
      return N.Pi * Long_Float (Index) / Long_Float (Count);
   end Turn_Of;

   function Position_At
     (First : Natural;
      Pos   : L.Position) return Along
   with Pre => First <= Max_Line_Samples;
   --  The position Pos of the segment that starts at sample First, in
   --  samples from the start of the line.

   function Position_At
     (First : Natural;
      Pos   : L.Position) return Along
   is
      Part : constant Long_Float := Long_Float (Pos) / 256.0;
   begin
      pragma Assert (Long_Float (Pos) <= 2.0 ** 28);
      pragma Assert (Part >= 0.0 and then Part <= 2.0 ** 20);
      pragma Assert (Long_Float (First) <= 2.0 ** 20);
      return Long_Float (First) + Part;
   end Position_At;

   function Point_At
     (Line : Scan_Line;
      T    : Along) return Point
   is
     (X => Line.X0 + N.Times_Unit (T, Line.UX),
      Y => Line.Y0 + N.Times_Unit (T, Line.UY));
   --  The point of pixel space at T samples from the start of the line.

   ---------------------------------------------------------------------
   --  Candidates
   ---------------------------------------------------------------------

   function Table_OK
     (Table : Candidate_Array;
      Open  : Natural;
      Count : Natural) return Boolean
   is
     (Table'First = 0 and then Table'Last < Max_Candidates
      and then Count <= Table'Last + 1 and then Open <= Count);
   --  Table (0 .. Count - 1) are the candidates so far; those of the
   --  direction being scanned start at Open.

   procedure Compact
     (Table     : in out Candidate_Array;
      Open      : Natural;
      Count     : in out Natural;
      Before    : Natural;
      Min_Lines : Positive)
   with
     Pre  => Table_OK (Table, Open, Count),
     Post => Table_OK (Table, Open, Count) and then Count <= Count'Old;
   --  Removes the candidates of the direction being scanned that have
   --  fewer than Min_Lines lines and that no reading of line Before or a
   --  later line can join any more.

   procedure Compact
     (Table     : in out Candidate_Array;
      Open      : Natural;
      Count     : in out Natural;
      Before    : Natural;
      Min_Lines : Positive)
   is
      Keep : Natural := Open;
   begin
      for I in Open .. Count - 1 loop
         pragma Loop_Invariant (Keep in Open .. I);
         if Table (I).Lines >= Min_Lines
           or else Int64 (Table (I).Last_Line) + Max_Line_Gap
                     >= Int64 (Before)
         then
            if Keep /= I then
               Table (Keep) := Table (I);
            end if;
            Keep := Keep + 1;
         end if;
      end loop;
      Count := Keep;
   end Compact;

   procedure Add_Reading
     (Table     : in out Candidate_Array;
      Open      : Natural;
      Count     : in out Natural;
      Line      : Scan_Line;
      Reversed  : Boolean;
      Item      : L.Reading;
      Start_T   : Along;
      End_T     : Along;
      Bar_S_T   : Along;
      Bar_E_T   : Along;
      Settings  : Scan_Settings;
      Overflow  : out Boolean)
   with
     Pre  => Table_OK (Table, Open, Count)
             and then Valid_Settings (Settings)
             and then Is_Linear (Item.Symbology)
             and then Item.Length >= 1,
     Post => Table_OK (Table, Open, Count);
   --  A reading of scan line Line: the symbol Item, whose start and end
   --  are at Start_T and End_T and whose inner edges are at Bar_S_T and
   --  Bar_E_T. It joins the candidate of the same text that a
   --  neighbouring line read at about the same place, or starts a new
   --  one. Overflow: the table is full.

   function To_Along (X : Long_Float) return Along is
     (N.Clamp (X, Along_Limit));
   --  A position of a line, a few runs from one of its edges; the limit
   --  never acts.

   function Symbol_Start
     (Line     : Scan_Line;
      Reversed : Boolean;
      Bar_T    : Along;
      Bar      : Bar_Width) return Point
   is
     (Point_At
        (Line, To_Along (if Reversed then Bar_T + Bar else Bar_T - Bar)));
   --  The start of a symbol on a line where the inner edge near its
   --  start is at Bar_T, Bar from the start.

   function Symbol_End
     (Line     : Scan_Line;
      Reversed : Boolean;
      Bar_T    : Along;
      Bar      : Bar_Width) return Point
   is
     (Point_At
        (Line, To_Along (if Reversed then Bar_T - Bar else Bar_T + Bar)));
   --  The end of a symbol on a line where the inner edge near its end
   --  is at Bar_T, Bar from the end.

   procedure Add_Reading
     (Table     : in out Candidate_Array;
      Open      : Natural;
      Count     : in out Natural;
      Line      : Scan_Line;
      Reversed  : Boolean;
      Item      : L.Reading;
      Start_T   : Along;
      End_T     : Along;
      Bar_S_T   : Along;
      Bar_E_T   : Along;
      Settings  : Scan_Settings;
      Overflow  : out Boolean)
   is
      Bar_S_Point : constant Point := Point_At (Line, Bar_S_T);
      Bar_E_Point : constant Point := Point_At (Line, Bar_E_T);
      Bar_S       : constant Bar_Width := abs (Bar_S_T - Start_T);
      Bar_E       : constant Bar_Width := abs (End_T - Bar_E_T);
   begin
      Overflow := False;
      for I in reverse Open .. Count - 1 loop
         if Table (I).Reversed = Reversed
           and then Table (I).Symbology = Item.Symbology
           and then Table (I).Length = Item.Length
           and then Line.Index > Table (I).Last_Line
           and then Line.Index - Table (I).Last_Line <= Max_Line_Gap
         then
            declare
               Reach : constant Long_Float :=
                 Long_Float (Line.Index - Table (I).Last_Line)
                 * Settings.Spacing + Join_Slack;
            begin
               if abs (Bar_S_T - Table (I).Last_S_T) <= Reach
                 and then abs (Bar_E_T - Table (I).Last_E_T) <= Reach
                 and then Table (I).Text = Item.Text
               then
                  Table (I).Last_Line := Line.Index;
                  if Table (I).Lines < Positive'Last then
                     Table (I).Lines := Table (I).Lines + 1;
                  end if;
                  Table (I).Last_S_T := Bar_S_T;
                  Table (I).Last_E_T := Bar_E_T;
                  Table (I).Bar_S :=
                    Long_Float'Max (Table (I).Bar_S, Bar_S);
                  Table (I).Bar_E :=
                    Long_Float'Max (Table (I).Bar_E, Bar_E);
                  Table (I).BS2 := Bar_S_Point;
                  Table (I).BE2 := Bar_E_Point;
                  Table (I).S1 :=
                    Symbol_Start (Table (I).First, Reversed,
                                  Table (I).First_S_T, Table (I).Bar_S);
                  Table (I).E1 :=
                    Symbol_End (Table (I).First, Reversed,
                                Table (I).First_E_T, Table (I).Bar_E);
                  Table (I).S2 :=
                    Symbol_Start (Line, Reversed, Bar_S_T,
                                  Table (I).Bar_S);
                  Table (I).E2 :=
                    Symbol_End (Line, Reversed, Bar_E_T, Table (I).Bar_E);
                  return;
               end if;
            end;
         end if;
      end loop;

      if Count > Table'Last then
         --  Full: make room by dropping what can no longer grow.
         Compact (Table, Open, Count, Line.Index, Settings.Min_Lines);
      end if;
      if Count > Table'Last then
         Overflow := True;
         return;
      end if;
      Table (Count) :=
        (Symbology => Item.Symbology,
         Length    => Item.Length,
         Text      => Item.Text,
         Reversed  => Reversed,
         Last_Line => Line.Index,
         Lines     => 1,
         First     => Line,
         First_S_T => Bar_S_T,
         First_E_T => Bar_E_T,
         Last_S_T  => Bar_S_T,
         Last_E_T  => Bar_E_T,
         Bar_S     => Bar_S,
         Bar_E     => Bar_E,
         BS1       => Bar_S_Point,
         BE1       => Bar_E_Point,
         BS2       => Bar_S_Point,
         BE2       => Bar_E_Point,
         S1        => Point_At (Line, Start_T),
         E1        => Point_At (Line, End_T),
         S2        => Point_At (Line, Start_T),
         E2        => Point_At (Line, End_T),
         State     => Pending);
      Count := Count + 1;
   end Add_Reading;

   ---------------------------------------------------------------------
   --  Reading a scan line
   ---------------------------------------------------------------------

   function Arrays_OK
     (Levels   : P.Level_Array;
      Extremes : P.Extreme_Array;
      Edges    : L.Position_Array;
      Mirror   : L.Position_Array) return Boolean
   is
     (Levels'First = 0 and then Levels'Last < Max_Line_Samples
      and then Extremes'First = 0 and then Extremes'Last = Levels'Last
      and then Edges'First = 0 and then Edges'Last = Levels'Last + 4
      and then Mirror'First = 0 and then Mirror'Last = Edges'Last);
   --  The work arrays of a run: the levels of a scan line, the extremes
   --  and the edges of one of its segments, and the same edges seen from
   --  the other end.

   function Next_Start
     (Start     : Positive;
      Last_Edge : Natural) return Positive
   is
     (if Last_Edge < Start then Start + 2
      elsif Last_Edge mod 2 = 0 then Last_Edge + 1
      else Last_Edge + 2)
   with
     Pre  => Start mod 2 = 1 and then Start <= L.Max_Edges
             and then Last_Edge <= L.Max_Edges,
     Post => Next_Start'Result mod 2 = 1 and then Next_Start'Result > Start;
   --  The first bar after a symbol that started at edge Start and whose
   --  last bar ends at edge Last_Edge (an even edge after Start; the
   --  other cases never arise).

   procedure Read_Segment
     (Levels   : P.Level_Array;
      First    : Natural;
      Last     : Natural;
      Line     : Scan_Line;
      Settings : Scan_Settings;
      Open     : Natural;
      Extremes : in out P.Extreme_Array;
      Edges    : in out L.Position_Array;
      Mirror   : in out L.Position_Array;
      Table    : in out Candidate_Array;
      Count    : in out Natural;
      Overflow : out Boolean)
   with
     Pre  => Arrays_OK (Levels, Extremes, Edges, Mirror)
             and then First <= Last and then Last <= Levels'Last
             and then Valid_Settings (Settings)
             and then Table_OK (Table, Open, Count),
     Post => Table_OK (Table, Open, Count);
   --  Reads the symbols of the samples First .. Last of a scan line, all
   --  of them samples, forwards and backwards.

   procedure Read_Segment
     (Levels   : P.Level_Array;
      First    : Natural;
      Last     : Natural;
      Line     : Scan_Line;
      Settings : Scan_Settings;
      Open     : Natural;
      Extremes : in out P.Extreme_Array;
      Edges    : in out L.Position_Array;
      Mirror   : in out L.Position_Array;
      Table    : in out Candidate_Array;
      Count    : in out Natural;
      Overflow : out Boolean)
   is
      Edge_Last : Natural;
      Start     : Positive;
      Found     : Boolean;
      Item      : L.Reading;
      Total     : L.Position;
   begin
      Overflow := False;
      P.Find_Edges (Levels, First, Last, Settings.Threshold, Extremes,
                    Edges, Edge_Last);

      --  Forwards.
      Start := 1;
      while Start < Edge_Last loop
         pragma Loop_Invariant (Start mod 2 = 1);
         pragma Loop_Invariant (Table_OK (Table, Open, Count));
         pragma Loop_Variant (Increases => Start);
         L.Decode_At (Edges, Edge_Last, Start, Settings.Options, Found,
                      Item);
         if Found then
            Add_Reading
              (Table, Open, Count, Line, False, Item,
               Position_At (First, Edges (Start)),
               Position_At (First, Edges (Item.Last_Edge)),
               Position_At (First, Edges (Start + Inset)),
               Position_At (First, Edges (Item.Last_Edge - Inset)),
               Settings, Overflow);
            if Overflow then
               return;
            end if;
            Start := Next_Start (Start, Item.Last_Edge);
         else
            Start := Start + 2;
         end if;
      end loop;

      --  Backwards: the same edges measured from the end of the segment.
      --  Run K of Mirror is run Edge_Last - 1 - K of Edges, which is of
      --  the same kind (Edge_Last is odd).
      Total := Edges (Edge_Last);
      for K in 0 .. Edge_Last loop
         Mirror (K) :=
           (if Edges (Edge_Last - K) <= Total
            then Total - Edges (Edge_Last - K) else 0);
      end loop;
      Start := 1;
      while Start < Edge_Last loop
         pragma Loop_Invariant (Start mod 2 = 1);
         pragma Loop_Invariant (Table_OK (Table, Open, Count));
         pragma Loop_Variant (Increases => Start);
         L.Decode_At (Mirror, Edge_Last, Start, Settings.Options, Found,
                      Item);
         if Found then
            Add_Reading
              (Table, Open, Count, Line, True, Item,
               Position_At (First, Edges (Edge_Last - Start)),
               Position_At (First, Edges (Edge_Last - Item.Last_Edge)),
               Position_At (First, Edges (Edge_Last - Start - Inset)),
               Position_At
                 (First, Edges (Edge_Last - Item.Last_Edge + Inset)),
               Settings, Overflow);
            if Overflow then
               return;
            end if;
            Start := Next_Start (Start, Item.Last_Edge);
         else
            Start := Start + 2;
         end if;
      end loop;
   end Read_Segment;

   procedure Read_Line
     (Levels   : P.Level_Array;
      Samples  : Positive;
      Line     : Scan_Line;
      Settings : Scan_Settings;
      Open     : Natural;
      Extremes : in out P.Extreme_Array;
      Edges    : in out L.Position_Array;
      Mirror   : in out L.Position_Array;
      Table    : in out Candidate_Array;
      Count    : in out Natural;
      Overflow : out Boolean)
   with
     Pre  => Arrays_OK (Levels, Extremes, Edges, Mirror)
             and then Samples <= Levels'Length
             and then Valid_Settings (Settings)
             and then Table_OK (Table, Open, Count),
     Post => Table_OK (Table, Open, Count);
   --  Reads the symbols of a scan line of Samples samples: every run of
   --  at least Min_Segment samples is a segment.

   procedure Read_Line
     (Levels   : P.Level_Array;
      Samples  : Positive;
      Line     : Scan_Line;
      Settings : Scan_Settings;
      Open     : Natural;
      Extremes : in out P.Extreme_Array;
      Edges    : in out L.Position_Array;
      Mirror   : in out L.Position_Array;
      Table    : in out Candidate_Array;
      Count    : in out Natural;
      Overflow : out Boolean)
   is
      use type P.Level;
      I     : Natural := 0;
      First : Natural;
   begin
      Overflow := False;
      while I < Samples loop
         pragma Loop_Invariant (Table_OK (Table, Open, Count));
         pragma Loop_Variant (Increases => I);
         if Levels (I) = P.No_Sample then
            I := I + 1;
         else
            First := I;
            while I < Samples and then Levels (I) /= P.No_Sample loop
               pragma Loop_Invariant (I >= First);
               pragma Loop_Variant (Increases => I);
               I := I + 1;
            end loop;
            if I - First >= Min_Segment then
               Read_Segment (Levels, First, I - 1, Line, Settings, Open,
                             Extremes, Edges, Mirror, Table, Count,
                             Overflow);
               exit when Overflow;
            end if;
         end if;
      end loop;
   end Read_Line;

   procedure Scan_Direction
     (Image    : access constant KI.Ks_Image_8_Grey_Data;
      Region   : access constant KR.Ks_Pixel_Region_Data;
      Box      : Scan_Box;
      Angle    : Long_Float;
      Settings : Scan_Settings;
      Levels   : in out P.Level_Array;
      Extremes : in out P.Extreme_Array;
      Edges    : in out L.Position_Array;
      Mirror   : in out L.Position_Array;
      Table    : in out Candidate_Array;
      Count    : in out Natural;
      Overflow : out Boolean)
   with
     Pre  => KI.Valid_Image (Image)
             and then Valid_Box (Box)
             and then N.In_Range (Angle, 8.0)
             and then Valid_Settings (Settings)
             and then Arrays_OK (Levels, Extremes, Edges, Mirror)
             and then Levels'Last
                        = (Box.X_Hi - Box.X_Lo) + (Box.Y_Hi - Box.Y_Lo)
             and then Table_OK (Table, Count, Count),
     Post => Table_OK (Table, Count, Count);
   --  Scans the box along the direction Angle and adds the candidates of
   --  that direction that have at least Settings.Min_Lines lines.

   procedure Scan_Direction
     (Image    : access constant KI.Ks_Image_8_Grey_Data;
      Region   : access constant KR.Ks_Pixel_Region_Data;
      Box      : Scan_Box;
      Angle    : Long_Float;
      Settings : Scan_Settings;
      Levels   : in out P.Level_Array;
      Extremes : in out P.Extreme_Array;
      Edges    : in out L.Position_Array;
      Mirror   : in out L.Position_Array;
      Table    : in out Candidate_Array;
      Count    : in out Natural;
      Overflow : out Boolean)
   is
      UX : constant Unit := To_Unit (EF.Cos (Angle));
      UY : constant Unit := To_Unit (EF.Sin (Angle));
      EW : constant Long_Float := Long_Float (Box.X_Hi - Box.X_Lo);
      EH : constant Long_Float := Long_Float (Box.Y_Hi - Box.Y_Lo);

      --  The extent of the box along the scan direction and across it.
      Length : constant Long_Float := Extent (EW, EH, UX, UY);
      Across : constant Long_Float := Extent (EW, EH, UY, UX);

      Samples : constant Positive := Count_Of (Length, Levels'Length);
      Lines   : constant Positive :=
        Line_Count (Across, Settings.Spacing, Levels'Length);

      --  The centre of the box, and the middle sample and the middle
      --  line, which lie on it.
      CX   : constant Long_Float := Middle (Box.X_Lo, Box.X_Hi);
      CY   : constant Long_Float := Middle (Box.Y_Lo, Box.Y_Hi);
      Half : constant Long_Float := Half_Of (Samples);

      Open : constant Natural := Count;
   begin
      Overflow := False;
      for J in 0 .. Lines - 1 loop
         pragma Loop_Invariant (Table_OK (Table, Open, Count));
         declare
            Offset : constant Long_Float :=
              N.Mul_Within (From_Middle (J, Lines), Settings.Spacing,
                            2.0 ** 20, Max_Line_Spacing);
            Line   : constant Scan_Line :=
              (Index => J,
               X0    => Start_X (CX, Offset, Half, UX, UY),
               Y0    => Start_Y (CY, Offset, Half, UX, UY),
               UX    => UX,
               UY    => UY);
         begin
            P.Sample_Line (Image, Region, Line.X0, Line.Y0, UX, UY,
                           Samples, Levels);
            Read_Line (Levels, Samples, Line, Settings, Open, Extremes,
                       Edges, Mirror, Table, Count, Overflow);
         end;
         exit when Overflow;
      end loop;

      --  The direction is done: nothing joins its candidates any more.
      Compact (Table, Open, Count, Natural'Last, Settings.Min_Lines);
   end Scan_Direction;

   ---------------------------------------------------------------------
   --  The results of the candidates
   ---------------------------------------------------------------------

   function Centre (C : Candidate) return Point is
     (X => (C.S1.X + C.E1.X + C.E2.X + C.S2.X) / 4.0,
      Y => (C.S1.Y + C.E1.Y + C.E2.Y + C.S2.Y) / 4.0);
   --  The mean of the four corners.

   Span_Limit : constant := 4.0 * Point_Limit;

   subtype Span is Long_Float range -Span_Limit .. Span_Limit;
   --  A sum of two differences of coordinates.

   function Between (From, To : Coordinate) return Span
   with Post => abs Between'Result <= 2.0 * Point_Limit;
   --  To - From. Not an expression function, like Middle.

   function Between (From, To : Coordinate) return Span is
   begin
      return To - From;
   end Between;

   function Sum (A, B : Coordinate) return Span
   with Post => abs Sum'Result <= 2.0 * Point_Limit;
   --  A + B, in the same way.

   function Sum (A, B : Coordinate) return Span is
   begin
      return A + B;
   end Sum;

   function Covers
     (A, B    : Candidate;
      Spacing : Long_Float) return Boolean
   with Pre => Spacing >= 1.0 and then Spacing <= Max_Line_Spacing;
   --  The centre of B lies in the area of A: within half the length of A
   --  along its scan lines, and across them within half the distance from
   --  its first line to its last plus a line and a half.

   function Covers
     (A, B    : Candidate;
      Spacing : Long_Float) return Boolean
   is
      CA : constant Point := Centre (A);
      CB : constant Point := Centre (B);
      DX : constant Span := Between (CA.X, CB.X);
      DY : constant Span := Between (CA.Y, CB.Y);

      --  Twice the mean vector from the start of A to its end.
      AX : constant Span :=
        Between (A.S1.X, A.E1.X) + Between (A.S2.X, A.E2.X);
      AY : constant Span :=
        Between (A.S1.Y, A.E1.Y) + Between (A.S2.Y, A.E2.Y);

      --  From the first line of A to its last.
      WX : constant Span := Between (A.S1.X, A.S2.X);
      WY : constant Span := Between (A.S1.Y, A.S2.Y);

      --  Everything times the length of (AX, AY), so that nothing is
      --  divided: the distance of the centres along A and across it, and
      --  the distance across from the first line to the last.
      Length_2 : constant Long_Float := N.Square (AX) + N.Square (AY);
      Along_D  : constant Long_Float :=
        abs (N.Mul (DX, AX) + N.Mul (DY, AY));
      Across_D : constant Long_Float :=
        abs (N.Mul (DY, AX) - N.Mul (DX, AY));
      Height   : constant Long_Float :=
        abs (N.Mul (WY, AX) - N.Mul (WX, AY));
      Margin   : constant Long_Float :=
        N.Mul (3.0 * Spacing, N.Hypot (AX, AY));
   begin
      return Length_2 > 0.0
        and then 4.0 * Along_D <= Length_2
        and then 2.0 * Across_D <= Height + Margin;
   end Covers;

   function Crosses (A, B : Candidate) return Boolean;
   --  The middle line of A (from the middle of its two starts to the
   --  middle of its two ends) and that of B cross: each has its two ends
   --  strictly on either side of the other. Two lines that only touch, or
   --  that lie on one straight line, do not cross.

   function Crosses (A, B : Candidate) return Boolean is
      --  Twice the ends of the middle lines.
      ASX : constant Span := Sum (A.S1.X, A.S2.X);
      ASY : constant Span := Sum (A.S1.Y, A.S2.Y);
      AEX : constant Span := Sum (A.E1.X, A.E2.X);
      AEY : constant Span := Sum (A.E1.Y, A.E2.Y);
      BSX : constant Span := Sum (B.S1.X, B.S2.X);
      BSY : constant Span := Sum (B.S1.Y, B.S2.Y);
      BEX : constant Span := Sum (B.E1.X, B.E2.X);
      BEY : constant Span := Sum (B.E1.Y, B.E2.Y);

      Twice : constant := 2.0 * Point_Limit;

      function Side (PX, PY, QX, QY, RX, RY : Long_Float) return Long_Float
      is
        (N.Mul (QX - PX, RY - PY) - N.Mul (QY - PY, RX - PX))
      with
        Pre => abs PX <= Twice and then abs PY <= Twice
               and then abs QX <= Twice and then abs QY <= Twice
               and then abs RX <= Twice and then abs RY <= Twice;
      --  Positive when R is on the left of the line from P to Q, negative
      --  when it is on its right.

      function Opposite (U, V : Long_Float) return Boolean is
        ((U > 0.0 and then V < 0.0) or else (U < 0.0 and then V > 0.0));
   begin
      return Opposite (Side (ASX, ASY, AEX, AEY, BSX, BSY),
                       Side (ASX, ASY, AEX, AEY, BEX, BEY))
        and then Opposite (Side (BSX, BSY, BEX, BEY, ASX, ASY),
                           Side (BSX, BSY, BEX, BEY, AEX, AEY));
   end Crosses;

   procedure Make_Item
     (C    : Candidate;
      T    : KT.Ks_Transform_2D_Linear;
      Item : out Ks_Code_Reader_Result)
   with
     Pre  => KT.Bounded (T),
     Post => Valid_Item (Item) and then not Is_Matrix (Item.Symbology);
   --  The result of a candidate, in the space that T maps pixel space to.

   procedure Make_Item
     (C    : Candidate;
      T    : KT.Ks_Transform_2D_Linear;
      Item : out Ks_Code_Reader_Result)
   is
      Mid : constant Point := Centre (C);

      --  Along the scan lines, from the start of the symbol to its end.
      AX : constant Span :=
        Between (C.S1.X, C.E1.X) + Between (C.S2.X, C.E2.X);
      AY : constant Span :=
        Between (C.S1.Y, C.E1.Y) + Between (C.S2.Y, C.E2.Y);

      --  Along the bars, from the first line to the last, turned by a
      --  quarter of a turn: across the bars.
      QX : constant Span :=
        Between (C.BS1.Y, C.BS2.Y) + Between (C.BE1.Y, C.BE2.Y);
      QY : constant Span :=
        -(Between (C.BS1.X, C.BS2.X) + Between (C.BE1.X, C.BE2.X));

      Side   : Long_Float;
      RX, RY : Span;
      DX, DY : Long_Float;
   begin
      Item := No_Result;
      Item.Symbology := C.Symbology;
      Item.Length := Int32 (C.Length);
      for I in 1 .. C.Length loop
         Item.Text (I) := C.Text (I);
         pragma Loop_Invariant
           (for all K in I + 1 .. Code_Text'Last =>
              Item.Text (K) = ASCII.NUL);
      end loop;
      Item.Num_Scan_Lines := Int32 (C.Lines);

      --  The direction of the symbol in pixel space: across the bars,
      --  towards the end of the symbol, when enough lines give the
      --  direction of the bars; otherwise that of the scan lines.
      RX := AX;
      RY := AY;
      if C.Lines >= Min_Angle_Lines then
         Side := N.Mul (QX, AX) + N.Mul (QY, AY);
         if Side > 0.0 then
            RX := QX;
            RY := QY;
         elsif Side < 0.0 then
            RX := -QX;
            RY := -QY;
         end if;
      end if;
      DX := N.Mul (T.A, RX) + N.Mul (T.B, RY);
      DY := N.Mul (T.C, RX) + N.Mul (T.D, RY);
      if DX /= 0.0 or else DY /= 0.0 then
         Item.Angle := N.Direction (DY, DX);
      end if;

      Item.Center_X := Sampling.Map_X (T, Mid.X, Mid.Y);
      Item.Center_Y := Sampling.Map_Y (T, Mid.X, Mid.Y);
      Item.Corner_0_X := Sampling.Map_X (T, C.S1.X, C.S1.Y);
      Item.Corner_0_Y := Sampling.Map_Y (T, C.S1.X, C.S1.Y);
      Item.Corner_1_X := Sampling.Map_X (T, C.E1.X, C.E1.Y);
      Item.Corner_1_Y := Sampling.Map_Y (T, C.E1.X, C.E1.Y);
      Item.Corner_2_X := Sampling.Map_X (T, C.E2.X, C.E2.Y);
      Item.Corner_2_Y := Sampling.Map_Y (T, C.E2.X, C.E2.Y);
      Item.Corner_3_X := Sampling.Map_X (T, C.S2.X, C.S2.Y);
      Item.Corner_3_Y := Sampling.Map_Y (T, C.S2.X, C.S2.Y);
   end Make_Item;

   ---------------------------------------------------------------------
   --  Data Matrix symbols
   ---------------------------------------------------------------------

   Min_Twice_Area : constant := 128;
   Min_Height     : constant := 8;
   --  A dark area that is smaller (twice its area, in pixels), or less
   --  than Min_Height rows more than one tall, is not looked at: the L of
   --  a symbol is at least ten pixels long.

   subtype Size_Delta is Integer range -2 .. 2;

   Size_Deltas : constant array (1 .. 5) of Size_Delta :=
     [0, -1, 1, -2, 2];
   --  The sizes tried around the modules counted, the nearest first.

   subtype Matrix_Text is DM.Text_Buffer (1 .. DM.Max_Text_Length);

   type Pass_Outcome is (Done, No_Memory, Too_Many);

   procedure Read_Symbol
     (Map     : DA.Mark_Map;
      Field   : RS.Field;
      Shape   : in out FN.Outline;
      Centre  : out FN.Corner;
      Text    : out Matrix_Text;
      Length  : out Natural;
      Success : out Boolean)
   with
     Pre  => DA.Valid_Map (Map),
     Post => (if Success then Length in 1 .. DM.Max_Text_Length);
   --  Reads the symbol whose corners are Shape: counts its modules, and
   --  samples and decodes it at the sizes nearest to the count until one
   --  gives a text; then the same for the symbol seen from behind, and
   --  Shape is that outline if that is the one read. Centre: the middle
   --  of the symbol as it was read.

   procedure Read_Symbol
     (Map     : DA.Mark_Map;
      Field   : RS.Field;
      Shape   : in out FN.Outline;
      Centre  : out FN.Corner;
      Text    : out Matrix_Text;
      Length  : out Natural;
      Success : out Boolean)
   is
      Seen          : constant FN.Outline := Shape;
      Rows, Columns : Natural;
      R, C          : Integer;
      Size          : Natural;
      Grid          : DM.Module_Grid;

      Unused_Corrected : Natural;
   begin
      Centre := (others => <>);
      Length := 0;
      Success := False;
      Text := [others => ' '];
      --  The invariants keep gnatprove from unrolling the loops (250
      --  passes of the innermost one).
      for Mirror in Boolean loop
         pragma Loop_Invariant (not Success and then Length = 0);
         FN.Count_Modules (Map, Shape, Rows, Columns);
         if Rows <= DM.Max_Side + 2 and then Columns <= DM.Max_Side + 2 then
            for Sum in 0 .. 4 loop
               pragma Loop_Invariant (not Success and then Length = 0);
               for DR of Size_Deltas loop
                  pragma Loop_Invariant (not Success and then Length = 0);
                  for DC of Size_Deltas loop
                     pragma Loop_Invariant
                       (not Success and then Length = 0);
                     R := Rows + DR;
                     C := Columns + DC;
                     if abs DR + abs DC = Sum
                       and then R in 1 .. DM.Max_Side
                       and then C in 1 .. DM.Max_Side
                     then
                        Size := DM.Find_Size (R, C);
                        if Size > 0 then
                           FN.Sample (Map, Shape, R, C, Grid, Centre);
                           DM.Decode (Grid, Size, Field, Text, Length,
                                      Unused_Corrected, Success);
                           if Success and then Length > 0 then
                              return;
                           end if;
                           Length := 0;
                           Success := False;
                        end if;
                     end if;
                  end loop;
               end loop;
            end loop;
         end if;
         Shape := FN.Mirrored (Seen);
      end loop;
      Shape := Seen;
   end Read_Symbol;

   procedure Read_Area
     (Map     : in out DA.Mark_Map;
      X, Y    : Natural;
      Lefts   : in out DA.Extent_Array;
      Rights  : in out DA.Extent_Array;
      Points  : in out DA.Point_Array;
      Field   : RS.Field;
      Shape   : out FN.Outline;
      Centre  : out FN.Corner;
      Text    : out Matrix_Text;
      Length  : out Natural;
      Success : out Boolean)
   with
     Pre  => DA.Valid_Map (Map)
             and then Y <= Map'Last (1) and then X <= Map'Last (2)
             and then Map (Y, X) /= DA.Light
             and then DA.Extents_Fit (Lefts, Map)
             and then DA.Extents_Fit (Rights, Map)
             and then Points'First = 1
             and then Points'Length >= 2 * (Map'Length (1) + 1),
     Post => (if Success then Length in 1 .. DM.Max_Text_Length);
   --  Reads the symbol, if it is one, of the dark area whose outline
   --  passes the pixel (X, Y), which has a light pixel or the edge of the
   --  map on its left: traces the outline, and from its hull finds the
   --  corners (FN.Locate, FN.Refine) and reads the symbol. Shape: its
   --  corners, and Centre: its middle, as it was read. Lefts and Rights:
   --  DA.No_Left and DA.No_Right in every row, on entry and on return.

   procedure Read_Area
     (Map     : in out DA.Mark_Map;
      X, Y    : Natural;
      Lefts   : in out DA.Extent_Array;
      Rights  : in out DA.Extent_Array;
      Points  : in out DA.Point_Array;
      Field   : RS.Field;
      Shape   : out FN.Outline;
      Centre  : out FN.Corner;
      Text    : out Matrix_Text;
      Length  : out Natural;
      Success : out Boolean)
   is
      Y_Lo, Y_Hi : Natural;
      Area       : Int64;
      Closed     : Boolean;
      Count      : Natural;
      Found      : Boolean;
   begin
      Shape := (others => <>);
      Centre := (others => <>);
      Text := [others => ' '];
      Length := 0;
      Success := False;
      DA.Trace (Map, X, Y, Lefts, Rights, Y_Lo, Y_Hi, Area, Closed);
      if not Closed or else Area <= Min_Twice_Area
        or else Y_Hi - Y_Lo < Min_Height
      then
         DA.Clear (Lefts, Rights, Y_Lo, Y_Hi);
         return;
      end if;
      DA.Hull (Lefts, Rights, Y_Lo, Y_Hi, Points, Count);
      DA.Clear (Lefts, Rights, Y_Lo, Y_Hi);
      if Count < 3 then
         return;
      end if;
      FN.Locate (Map, Points (1 .. Count), Shape, Found);
      if Found then
         FN.Refine (Map, Lefts, Rights, Points, Shape);
         Read_Symbol (Map, Field, Shape, Centre, Text, Length, Success);
      end if;
   end Read_Area;

   ---------------------------------------------------------------------
   --  The symbols of a pass
   ---------------------------------------------------------------------

   function To_Point
     (C          : VW.Corner;
      X_Lo, Y_Lo : Natural) return Point;
   --  The point C of a map whose pixel (0, 0) is the pixel (X_Lo, Y_Lo)
   --  of the image, in pixel space (where the middle of a pixel, and not
   --  its upper left corner, has whole coordinates).

   function To_Point
     (C          : VW.Corner;
      X_Lo, Y_Lo : Natural) return Point is
   begin
      return (X => C.X + Long_Float (X_Lo) - 0.5,
              Y => C.Y + Long_Float (Y_Lo) - 0.5);
   end To_Point;

   Side_Limit : constant := 2.0 * Point_Limit;

   function Distance_2 (A, B : Point) return Long_Float
   with Post => Distance_2'Result >= 0.0
                and then Distance_2'Result <= 2.0 * Side_Limit * Side_Limit;
   --  The square of the distance from A to B.

   function Distance_2 (A, B : Point) return Long_Float is
   begin
      return N.Square_Within (Between (A.X, B.X), Side_Limit)
        + N.Square_Within (Between (A.Y, B.Y), Side_Limit);
   end Distance_2;

   function Near (A, B : Matrix_Symbol) return Boolean is
     (4.0 * Distance_2 (A.Middle, B.Middle)
        < Long_Float'Min (Distance_2 (A.LL, A.UL), Distance_2 (A.LL, A.LR)));
   --  The middle of B is less than half the shorter of the left and the
   --  lower side of A from the middle of A.

   Pool_Start : constant := 4096;
   Pool_Limit : constant := 2 * Max_Candidates * Max_Matrix_Text_Length;
   --  The characters of the pool of the texts at first, and at most.

   function Pool_OK
     (Pool : Text_Pool_Access;
      Used : Natural) return Boolean
   is
     (Pool /= null and then Pool'First = 1
      and then Pool'Last in Pool_Start .. Pool_Limit
      and then Used <= Pool'Last);

   function Symbols_OK
     (Symbols : Symbol_Array;
      Count   : Natural;
      Used    : Natural) return Boolean
   is
     (Symbols'First = 0 and then Symbols'Last = Max_Candidates - 1
      and then Count <= Max_Candidates
      and then Used <= Count * Max_Matrix_Text_Length
      and then (for all I in 0 .. Count - 1 =>
                  Symbols (I).Start - 1 <= Used - Symbols (I).Length));
   --  Symbols (0 .. Count - 1) are the symbols read so far, their texts
   --  within the first Used characters of the pool.

   function Same_Text
     (Pool   : Text_Pool;
      Start  : Positive;
      Text   : Text_Pool;
      Length : Positive) return Boolean
   is
     (for all I in 1 .. Length => Pool (Start - 1 + I) = Text (I))
   with Pre => Pool'First = 1 and then Text'First = 1
               and then Length <= Text'Last
               and then Length <= Pool'Last
               and then Start - 1 <= Pool'Last - Length;

   procedure Add_Symbol
     (Kind       : Matrix_Kind;
      Shape      : VW.Outline;
      Centre     : VW.Corner;
      X_Lo, Y_Lo : Natural;
      Text       : Text_Pool;
      Length     : Positive;
      Room       : Natural;
      Symbols    : in out Symbol_Array;
      Count      : in out Natural;
      Pool       : in out Text_Pool_Access;
      Used       : in out Natural;
      Outcome    : out Pass_Outcome)
   with
     Pre  => Text'First = 1 and then Length <= Text'Last
             and then Length <= Max_Matrix_Text_Length
             and then Room <= Max_Candidates and then Count <= Room
             and then Symbols_OK (Symbols, Count, Used)
             and then Pool_OK (Pool, Used),
     Post => Count <= Room and then Symbols_OK (Symbols, Count, Used)
             and then Pool_OK (Pool, Used);
   --  Adds the symbol with the corners Shape and the middle Centre (of
   --  the map whose first pixel is the pixel (X_Lo, Y_Lo) of the image)
   --  and the text Text (1 .. Length), unless it is there already: a
   --  symbol of the same kind with the same text whose middle is near
   --  the middle of this one. Room: the most symbols. Outcome: Too_Many
   --  when there is no room for it, and No_Memory when the pool cannot
   --  grow; nothing is added then.

   procedure Add_Symbol
     (Kind       : Matrix_Kind;
      Shape      : VW.Outline;
      Centre     : VW.Corner;
      X_Lo, Y_Lo : Natural;
      Text       : Text_Pool;
      Length     : Positive;
      Room       : Natural;
      Symbols    : in out Symbol_Array;
      Count      : in out Natural;
      Pool       : in out Text_Pool_Access;
      Used       : in out Natural;
      Outcome    : out Pass_Outcome)
   is
      Symbol : constant Matrix_Symbol :=
        (Kind   => Kind,
         UL     => To_Point (Shape.Upper_Left, X_Lo, Y_Lo),
         UR     => To_Point (Shape.Upper_Right, X_Lo, Y_Lo),
         LR     => To_Point (Shape.Lower_Right, X_Lo, Y_Lo),
         LL     => To_Point (Shape.Lower_Left, X_Lo, Y_Lo),
         Middle => To_Point (Centre, X_Lo, Y_Lo),
         Start  => Used + 1,
         Length => Length);
      Wanted : Positive;
      Bigger : Text_Pool_Access;
   begin
      Outcome := Done;
      for I in 0 .. Count - 1 loop
         if Symbols (I).Kind = Kind
           and then Symbols (I).Length = Length
           and then Near (Symbols (I), Symbol)
           and then Same_Text (Pool.all, Symbols (I).Start, Text, Length)
         then
            return;
         end if;
      end loop;
      if Count >= Room then
         Outcome := Too_Many;
         return;
      end if;

      if Length > Pool'Last - Used then
         Wanted := Positive'Max (Positive'Min (2 * Pool'Last, Pool_Limit),
                                 Used + Length);
         Allocate_Texts (Wanted, Bigger);
         if Bigger = null then
            Outcome := No_Memory;
            return;
         end if;
         for I in 1 .. Used loop
            Bigger (I) := Pool (I);
         end loop;
         Free (Pool);
         Pool := Bigger;
      end if;
      for I in 1 .. Length loop
         Pool (Used + I) := Text (I);
      end loop;
      Symbols (Count) := Symbol;
      Count := Count + 1;
      Used := Used + Length;
   end Add_Symbol;

   procedure Mask_Region
     (Region     : access constant KR.Ks_Pixel_Region_Data;
      X_Lo, Y_Lo : Natural;
      Map        : in out DA.Mark_Map)
   with Pre => DA.Valid_Map (Map)
               and then Map'Last (1) <= Integer'Last - Y_Lo
               and then Map'Last (2) <= Integer'Last - X_Lo;
   --  Light for every pixel of the map that is not in the region. The
   --  pixel (0, 0) of the map is the pixel (X_Lo, Y_Lo) of the image
   --  (which may be wider or higher than a map: X_Lo and Y_Lo are not
   --  held to DA.Max_Side).

   procedure Mask_Region
     (Region     : access constant KR.Ks_Pixel_Region_Data;
      X_Lo, Y_Lo : Natural;
      Map        : in out DA.Mark_Map) is
   begin
      for Y in Map'Range (1) loop
         for X in Map'Range (2) loop
            if not KR.Contains (Region, Int32 (X + X_Lo), Int32 (Y + Y_Lo))
            then
               Map (Y, X) := DA.Light;
            end if;
         end loop;
      end loop;
   end Mask_Region;

   ---------------------------------------------------------------------
   --  QR Code symbols
   ---------------------------------------------------------------------

   Max_Patterns : constant := 256;
   --  The finder patterns of a pass, at most: those of 85 symbols.

   Max_Partners : constant := 32;
   --  The finder patterns nearest to one that are tried as the two
   --  others of its symbol, at most.

   Max_Tries : constant := 16;
   --  The pairs of them that can be the two others, as far as the three
   --  patterns tell, and that are looked at without a text, at most,
   --  with one pattern in the corner.

   subtype Version_Step is Integer range -2 .. 2;

   Version_Steps : constant array (1 .. 5) of Version_Step :=
     [0, -1, 1, -2, 2];
   --  The versions tried around the one that the finder patterns give,
   --  the nearest first.

   subtype QR_Text is QR.Text_Buffer (1 .. QR.Max_Text_Length);

   procedure Read_Triple
     (Map                  : DA.Mark_Map;
      Field                : RS.Field;
      First, Second, Third : QF.Pattern;
      Shape                : out VW.Outline;
      Centre               : out VW.Corner;
      Text                 : in out QR_Text;
      Length               : out Natural;
      Tried                : out Boolean;
      Success              : out Boolean)
   with Pre  => DA.Valid_Map (Map),
        Post => (if Success
                 then Tried and then Length in 1 .. QR.Max_Text_Length);
   --  Reads the symbol whose finder patterns are First (the one in the
   --  corner between the two others), Second and Third, if the three
   --  can be those of a symbol: with either mapping of QF.Sample, with
   --  the version that the patterns give and the two before and after
   --  it, as it is and as its mirror image, until one gives a text that
   --  is not empty. Shape and Centre: its corners and its middle as it
   --  is printed. Text (1 .. Length): its text (the rest of Text has no
   --  meaning). Tried: the three can be those of a symbol (QF.Place),
   --  so that the modules were looked at. Field: the tables of
   --  RS.QR_Code_Polynomial.

   procedure Read_Triple
     (Map                  : DA.Mark_Map;
      Field                : RS.Field;
      First, Second, Third : QF.Pattern;
      Shape                : out VW.Outline;
      Centre               : out VW.Corner;
      Text                 : in out QR_Text;
      Length               : out Natural;
      Tried                : out Boolean;
      Success              : out Boolean)
   is
      Symbol           : QF.Placement;
      Version          : Integer;
      Grid             : QR.Module_Grid;
      Other            : VW.Corner;
      OK               : Boolean;
      Unused_Corrected : Natural;
   begin
      Shape := (others => <>);
      Centre := (others => <>);
      Length := 0;
      Success := False;
      QF.Place (Map, First, Second, Third, Symbol, Tried);
      if not Tried then
         return;
      end if;
      for Again in Boolean loop
         pragma Loop_Invariant (Tried and then not Success
                                and then Length = 0);
         for Step of Version_Steps loop
            pragma Loop_Invariant (Tried and then not Success
                                   and then Length = 0);
            Version := Symbol.Version + Step;
            if Version in QR.Version_Number then
               QF.Sample (Map, Symbol, Version, Again, Grid, Shape, Centre,
                          OK);
               if OK then
                  for Mirror in Boolean loop
                     pragma Loop_Invariant (Tried and then not Success
                                            and then Length = 0);
                     QR.Decode (Grid, Version, Mirror, Field, Text, Length,
                                Unused_Corrected, Success);
                     if Success and then Length > 0 then
                        if Mirror then
                           --  Seen from behind, the upper right corner
                           --  of the symbol as it is printed is where
                           --  the lower left one would be.
                           Other := Shape.Upper_Right;
                           Shape.Upper_Right := Shape.Lower_Left;
                           Shape.Lower_Left := Other;
                        end if;
                        return;
                     end if;
                     Length := 0;
                     Success := False;
                  end loop;
               end if;
            end if;
         end loop;
      end loop;
   end Read_Triple;

   procedure Find_QR_Symbols
     (Map        : DA.Mark_Map;
      X_Lo, Y_Lo : Natural;
      Room       : Natural;
      Symbols    : in out Symbol_Array;
      Count      : in out Natural;
      Pool       : in out Text_Pool_Access;
      Used       : in out Natural;
      Outcome    : out Pass_Outcome)
   with
     Pre  => DA.Valid_Map (Map)
             and then Room <= Max_Candidates and then Count <= Room
             and then Symbols_OK (Symbols, Count, Used)
             and then Pool_OK (Pool, Used),
     Post => Count <= Room and then Symbols_OK (Symbols, Count, Used)
             and then Pool_OK (Pool, Used);
   --  Adds the QR Code symbols of the map (whose first pixel is the
   --  pixel (X_Lo, Y_Lo) of the image) to Symbols (0 .. Count - 1) and
   --  their texts to the pool, in the order in which the rows of the
   --  map meet the finder pattern in the corner of each. Every finder
   --  pattern is tried as the one in the corner, with every two of the
   --  Max_Partners patterns nearest to it whose modules are about as
   --  wide (QF.Akin), the nearest first: the pairs with the nearest and
   --  the second nearest, then those with the third, and so on, until
   --  Max_Tries of them were looked at without a text. The patterns of
   --  a symbol that was read are not tried again. Room and Outcome: as
   --  for Add_Symbol.

   procedure Find_QR_Symbols
     (Map        : DA.Mark_Map;
      X_Lo, Y_Lo : Natural;
      Room       : Natural;
      Symbols    : in out Symbol_Array;
      Count      : in out Natural;
      Pool       : in out Text_Pool_Access;
      Used       : in out Natural;
      Outcome    : out Pass_Outcome)
   is
      subtype Pattern_Index is Positive range 1 .. Max_Patterns;
      type Flags is array (Pattern_Index) of Boolean;

      subtype Partner_Index is Positive range 1 .. Max_Partners;
      type Partner_List is array (Partner_Index) of Pattern_Index;
      type Way_List is array (Partner_Index) of VW.Length_Value;

      Field    : constant RS.Field := RS.Make_Field (RS.QR_Code_Polynomial);
      Patterns : QF.Pattern_Array (1 .. Max_Patterns);
      Taken    : Flags := [others => False];
      Found    : Natural;
      Near     : Partner_List := [others => 1];
      Ways     : Way_List := [others => 0.0];
      Nearest  : Natural range 0 .. Max_Partners;
      Way      : VW.Length_Value;
      Slot     : Partner_Index;
      Tries    : Natural range 0 .. Max_Tries;
      Shape    : VW.Outline;
      Centre   : VW.Corner;
      Text     : QR_Text := [others => ' '];
      Length   : Natural;
      Tried    : Boolean;
      Success  : Boolean;
   begin
      Outcome := Done;
      QF.Find_Patterns (Map, Patterns, Found);
      Corners :
      for I in 1 .. Found loop
         pragma Loop_Invariant
           (Outcome = Done and then Count <= Room
            and then Symbols_OK (Symbols, Count, Used)
            and then Pool_OK (Pool, Used));
         if not Taken (I) then

            --  Near (1 .. Nearest): the patterns that can be of one
            --  symbol with this one, the nearest first, and their
            --  distances in Ways.
            Nearest := 0;
            for J in 1 .. Found loop
               if J /= I and then not Taken (J)
                 and then QF.Akin (Patterns (I), Patterns (J))
               then
                  Way :=
                    VW.Distance (Patterns (I).Centre, Patterns (J).Centre);
                  if Nearest < Max_Partners
                    or else Way < Ways (Max_Partners)
                  then
                     if Nearest < Max_Partners then
                        Nearest := Nearest + 1;
                     end if;
                     Slot := Nearest;
                     while Slot > 1 and then Ways (Slot - 1) > Way loop
                        pragma Loop_Invariant (Slot in 2 .. Nearest);
                        pragma Loop_Variant (Decreases => Slot);
                        Ways (Slot) := Ways (Slot - 1);
                        Near (Slot) := Near (Slot - 1);
                        Slot := Slot - 1;
                     end loop;
                     Ways (Slot) := Way;
                     Near (Slot) := J;
                  end if;
               end if;
            end loop;

            Tries := 0;
            Pairs :
            for B in 2 .. Nearest loop
               pragma Loop_Invariant
                 (Outcome = Done and then Count <= Room
                  and then Tries < Max_Tries
                  and then Symbols_OK (Symbols, Count, Used)
                  and then Pool_OK (Pool, Used));
               for A in 1 .. B - 1 loop
                  pragma Loop_Invariant
                    (Outcome = Done and then Count <= Room
                     and then Tries < Max_Tries
                     and then Symbols_OK (Symbols, Count, Used)
                     and then Pool_OK (Pool, Used));
                  Read_Triple
                    (Map, Field, Patterns (I), Patterns (Near (A)),
                     Patterns (Near (B)), Shape, Centre, Text, Length,
                     Tried, Success);
                  if Success then
                     Add_Symbol (QR_Code_Symbol, Shape, Centre, X_Lo, Y_Lo,
                                 Text_Pool (Text), Length, Room, Symbols,
                                 Count, Pool, Used, Outcome);
                     exit Corners when Outcome /= Done;
                     Taken (I) := True;
                     Taken (Near (A)) := True;
                     Taken (Near (B)) := True;
                     exit Pairs;
                  end if;
                  if Tried then
                     Tries := Tries + 1;
                     exit Pairs when Tries = Max_Tries;
                  end if;
               end loop;
            end loop Pairs;
         end if;
      end loop Corners;
   end Find_QR_Symbols;

   ---------------------------------------------------------------------
   --  The pass for the two-dimensional symbols
   ---------------------------------------------------------------------

   procedure Find_Symbols
     (Image            : access constant KI.Ks_Image_8_Grey_Data;
      Region           : access constant KR.Ks_Pixel_Region_Data;
      Box              : Scan_Box;
      Contrast         : Positive;
      With_Data_Matrix : Boolean;
      With_QR_Code     : Boolean;
      Room             : Natural;
      Symbols          : in out Symbol_Array;
      Count            : out Natural;
      Pool             : in out Text_Pool_Access;
      Used             : out Natural;
      Outcome          : out Pass_Outcome)
   with
     Pre  => KI.Valid_Image (Image)
             and then KR.Valid_Region (Region)
             and then Valid_Box (Box)
             and then Box.X_Hi < Natural (Image.Width)
             and then Box.Y_Hi < Natural (Image.Height)
             and then Contrast <= 255
             and then Room <= Max_Candidates
             and then Symbols_OK (Symbols, 0, 0)
             and then Pool_OK (Pool, 0),
     Post => Count <= Room and then Symbols_OK (Symbols, Count, Used)
             and then Pool_OK (Pool, Used);
   --  The two-dimensional symbols of the pixels of the region in the
   --  box: Symbols (0 .. Count - 1), with their texts in the first Used
   --  characters of the pool. First the Data Matrix symbols
   --  (With_Data_Matrix), in the order of their first row and, in a
   --  row, of their first column; then the QR Code symbols
   --  (With_QR_Code), in the order of Find_QR_Symbols. Room: the most
   --  symbols. Outcome: Too_Many when there are more, No_Memory when
   --  the memory of the pass cannot be allocated.

   procedure Find_Symbols
     (Image            : access constant KI.Ks_Image_8_Grey_Data;
      Region           : access constant KR.Ks_Pixel_Region_Data;
      Box              : Scan_Box;
      Contrast         : Positive;
      With_Data_Matrix : Boolean;
      With_QR_Code     : Boolean;
      Room             : Natural;
      Symbols          : in out Symbol_Array;
      Count            : out Natural;
      Pool             : in out Text_Pool_Access;
      Used             : out Natural;
      Outcome          : out Pass_Outcome)
   is
      W : constant Positive := Box.X_Hi - Box.X_Lo + 1;
      H : constant Positive := Box.Y_Hi - Box.Y_Lo + 1;

      Field   : constant RS.Field := RS.Make_Field (RS.Data_Matrix_Polynomial);
      Map     : Map_Access;
      Lows    : Block_Access;
      Highs   : Block_Access;
      Lefts   : Extent_Access;
      Rights  : Extent_Access;
      Points  : Hull_Access;
      Shape   : FN.Outline;
      Centre  : FN.Corner;
      Text    : Matrix_Text;
      Length  : Natural;
      Success : Boolean;
   begin
      Count := 0;
      Used := 0;
      Outcome := Done;
      Allocate_Map (H, W, Map);
      Allocate_Blocks ((H - 1) / DA.Block + 1, (W - 1) / DA.Block + 1, Lows);
      Allocate_Blocks ((H - 1) / DA.Block + 1, (W - 1) / DA.Block + 1, Highs);
      Allocate_Extents (H, DA.No_Left, Lefts);
      Allocate_Extents (H, DA.No_Right, Rights);
      Allocate_Hull (2 * (H + 1), Points);
      if Map = null or else Lows = null or else Highs = null
        or else Lefts = null or else Rights = null or else Points = null
      then
         Free (Map);
         Free (Lows);
         Free (Highs);
         Free (Lefts);
         Free (Rights);
         Free (Points);
         Outcome := No_Memory;
         return;
      end if;

      DA.Binarise (Image.Pixels.all, Box.X_Lo, Box.Y_Lo, Contrast, Lows.all,
                   Highs.all, Map.all);
      Free (Lows);
      Free (Highs);
      if Region.Flags /= null then
         Mask_Region (Region, Box.X_Lo, Box.Y_Lo, Map.all);
      end if;

      if With_Data_Matrix then
         --  Every dark area once, at the first pixel of its outline.
         Rows :
         for Y in 0 .. H - 1 loop
            pragma Loop_Invariant
              (Map /= null and then Lefts /= null and then Rights /= null
               and then Points /= null);
            pragma Loop_Invariant
              (Map'First (1) = 0 and then Map'Last (1) = H - 1
               and then Map'First (2) = 0 and then Map'Last (2) = W - 1);
            pragma Loop_Invariant
              (DA.Extents_Fit (Lefts.all, Map.all)
               and then DA.Extents_Fit (Rights.all, Map.all)
               and then Points'First = 1
               and then Points'Last = 2 * (H + 1));
            pragma Loop_Invariant
              (Outcome = Done and then Count <= Room
               and then Symbols_OK (Symbols, Count, Used)
               and then Pool_OK (Pool, Used));
            for X in 0 .. W - 1 loop
               pragma Loop_Invariant
                 (Map /= null and then Lefts /= null and then Rights /= null
                  and then Points /= null);
               pragma Loop_Invariant
                 (Map'First (1) = 0 and then Map'Last (1) = H - 1
                  and then Map'First (2) = 0 and then Map'Last (2) = W - 1);
               pragma Loop_Invariant
                 (DA.Extents_Fit (Lefts.all, Map.all)
                  and then DA.Extents_Fit (Rights.all, Map.all)
                  and then Points'First = 1
                  and then Points'Last = 2 * (H + 1));
               pragma Loop_Invariant
                 (Outcome = Done and then Count <= Room
                  and then Symbols_OK (Symbols, Count, Used)
                  and then Pool_OK (Pool, Used));
               if Map (Y, X) = DA.Dark
                 and then (X = 0 or else Map (Y, X - 1) = DA.Light)
               then
                  Read_Area (Map.all, X, Y, Lefts.all, Rights.all, Points.all,
                             Field, Shape, Centre, Text, Length, Success);
                  if Success then
                     Add_Symbol (Data_Matrix_Symbol, Shape, Centre, Box.X_Lo,
                                 Box.Y_Lo, Text_Pool (Text), Length, Room,
                                 Symbols, Count, Pool, Used, Outcome);
                     exit Rows when Outcome /= Done;
                  end if;
               end if;
            end loop;
         end loop Rows;
      end if;

      --  The finder patterns, in the same pixels (an outline that
      --  was followed is marked, and still dark).
      if With_QR_Code and then Outcome = Done then
         Find_QR_Symbols (Map.all, Box.X_Lo, Box.Y_Lo, Room, Symbols, Count,
                          Pool, Used, Outcome);
      end if;
      Free (Map);
      Free (Lefts);
      Free (Rights);
      Free (Points);
   end Find_Symbols;

   procedure Make_Matrix_Item
     (Symbol : Matrix_Symbol;
      Pool   : Text_Pool;
      T      : KT.Ks_Transform_2D_Linear;
      Item   : out Ks_Code_Reader_Result)
   with
     Pre  => KT.Bounded (T) and then Pool'First = 1
             and then Symbol.Length <= Pool'Last
             and then Symbol.Start - 1 <= Pool'Last - Symbol.Length,
     Post => Valid_Item (Item)
             and then Is_Matrix (Item.Symbology)
             and then Item.Length = Int32 (Symbol.Length);
   --  The result of a symbol, in the space that T maps pixel space to.

   procedure Make_Matrix_Item
     (Symbol : Matrix_Symbol;
      Pool   : Text_Pool;
      T      : KT.Ks_Transform_2D_Linear;
      Item   : out Ks_Code_Reader_Result)
   is
      Shown : constant Positive :=
        Positive'Min (Symbol.Length, Max_Text_Length);

      Upper : constant Boolean := Symbol.Kind = QR_Code_Symbol;

      --  Along the lower side of a Data Matrix symbol, from the corner
      --  of the L, and along the upper side of a QR Code symbol, from
      --  its upper left finder pattern: the way of the rows of both as
      --  they are printed.
      AX : constant Span :=
        (if Upper then Between (Symbol.UL.X, Symbol.UR.X)
         else Between (Symbol.LL.X, Symbol.LR.X));
      AY : constant Span :=
        (if Upper then Between (Symbol.UL.Y, Symbol.UR.Y)
         else Between (Symbol.LL.Y, Symbol.LR.Y));

      --  The same in the selected space.
      DX : constant Long_Float := N.Mul (T.A, AX) + N.Mul (T.B, AY);
      DY : constant Long_Float := N.Mul (T.C, AX) + N.Mul (T.D, AY);
   begin
      Item := No_Result;
      Item.Symbology :=
        (if Upper then Symbology_QR_Code else Symbology_Data_Matrix);
      Item.Length := Int32 (Symbol.Length);
      for I in 1 .. Shown loop
         Item.Text (I) := Pool (Symbol.Start - 1 + I);
         pragma Loop_Invariant
           (for all K in I + 1 .. Code_Text'Last =>
              Item.Text (K) = ASCII.NUL);
      end loop;
      Item.Center_X :=
        Sampling.Map_X (T, Symbol.Middle.X, Symbol.Middle.Y);
      Item.Center_Y :=
        Sampling.Map_Y (T, Symbol.Middle.X, Symbol.Middle.Y);
      if DX /= 0.0 or else DY /= 0.0 then
         Item.Angle := N.Direction (DY, DX);
      end if;
      Item.Corner_0_X := Sampling.Map_X (T, Symbol.UL.X, Symbol.UL.Y);
      Item.Corner_0_Y := Sampling.Map_Y (T, Symbol.UL.X, Symbol.UL.Y);
      Item.Corner_1_X := Sampling.Map_X (T, Symbol.UR.X, Symbol.UR.Y);
      Item.Corner_1_Y := Sampling.Map_Y (T, Symbol.UR.X, Symbol.UR.Y);
      Item.Corner_2_X := Sampling.Map_X (T, Symbol.LR.X, Symbol.LR.Y);
      Item.Corner_2_Y := Sampling.Map_Y (T, Symbol.LR.X, Symbol.LR.Y);
      Item.Corner_3_X := Sampling.Map_X (T, Symbol.LL.X, Symbol.LL.Y);
      Item.Corner_3_Y := Sampling.Map_Y (T, Symbol.LL.X, Symbol.LL.Y);
      Item.Num_Scan_Lines := 0;
   end Make_Matrix_Item;

   ---------------------------------------------------------------------
   --  The results of a run
   ---------------------------------------------------------------------

   function In_Pool
     (Item  : Ks_Code_Reader_Result;
      Start : Natural;
      Last  : Natural) return Boolean
   is
     (Item.Length in 1 .. Max_Matrix_Text_Length
      and then Start >= 1
      and then Last >= Natural (Item.Length)
      and then Start - 1 <= Last - Natural (Item.Length));
   --  The text of the item is in a pool of Last characters, from Start
   --  on.

   procedure Build_Results
     (Table   : in out Candidate_Array;
      Count   : Natural;
      Spacing : Long_Float;
      Symbols : access constant Symbol_Array;
      Matrix  : Natural;
      Pool    : in out Text_Pool_Access;
      Used    : Natural;
      T       : KT.Ks_Transform_2D_Linear;
      Results : out Ks_Code_Reader_Results)
   with
     Pre  => Table_OK (Table, 0, Count)
             and then Spacing >= 1.0 and then Spacing <= Max_Line_Spacing
             and then Count <= Max_Candidates
             and then Matrix <= Max_Candidates - Count
             and then (if Matrix > 0
                       then Symbols /= null
                            and then Symbols_OK (Symbols.all, Matrix, Used)
                            and then Pool_OK (Pool, Used))
             and then KT.Bounded (T),
     Post => (if Results /= null then Gold_Results (Results));
   --  The results of the candidates Table (0 .. Count - 1): the one with
   --  the most lines first, and none that lies on top of an earlier one
   --  (its centre in the area of the earlier one, or the other way round)
   --  or whose middle line crosses that of an earlier one. Two symbols
   --  cannot do either, so these are readings of one symbol in two
   --  directions, or a misreading of a part of it. After them the
   --  symbols Symbols (0 .. Matrix - 1) in their order, with the pool of
   --  their texts, which is then no longer the caller's (Pool is null).
   --  Null when the memory cannot be allocated.

   procedure Build_Results
     (Table   : in out Candidate_Array;
      Count   : Natural;
      Spacing : Long_Float;
      Symbols : access constant Symbol_Array;
      Matrix  : Natural;
      Pool    : in out Text_Pool_Access;
      Used    : Natural;
      T       : KT.Ks_Transform_2D_Linear;
      Results : out Ks_Code_Reader_Results)
   is
      Most   : constant Positive := Positive'Max (Count + Matrix, 1);
      Items  : Item_Array_Access;
      Starts : Offset_Array_Access;
      Found  : Natural := 0;
      Best   : Natural;
      Have   : Boolean;
      Hidden : Boolean;
   begin
      Results := null;
      Allocate_Items (Most, Items);
      Allocate_Starts (Most, Starts);
      if Items = null or else Starts = null then
         Free (Items);
         Free (Starts);
         return;
      end if;

      --  Every round settles one candidate.
      for Round in 1 .. Count loop
         pragma Loop_Invariant (Items /= null);
         pragma Loop_Invariant
           (Items'First = 0 and then Items'Last = Most - 1);
         pragma Loop_Invariant (Found < Round);
         pragma Loop_Invariant
           (for all I in 0 .. Found - 1 =>
              Valid_Item (Items (I))
              and then not Is_Matrix (Items (I).Symbology));

         --  The candidate with the most lines among those not settled,
         --  the first of them when several have as many.
         Have := False;
         Best := 0;
         for I in 0 .. Count - 1 loop
            pragma Loop_Invariant (Best <= I);
            if Table (I).State = Pending
              and then (not Have or else Table (I).Lines > Table (Best).Lines)
            then
               Have := True;
               Best := I;
            end if;
         end loop;
         exit when not Have;

         Hidden := False;
         for I in 0 .. Count - 1 loop
            if Table (I).State = Accepted
              and then (Covers (Table (I), Table (Best), Spacing)
                        or else Covers (Table (Best), Table (I), Spacing)
                        or else Crosses (Table (I), Table (Best)))
            then
               Hidden := True;
               exit;
            end if;
         end loop;

         if Hidden then
            Table (Best).State := Rejected;
         else
            Table (Best).State := Accepted;
            Make_Item (Table (Best), T, Items (Found));
            Found := Found + 1;
         end if;
      end loop;

      --  The two-dimensional symbols after them.
      if Matrix > 0 then
         for I in 0 .. Matrix - 1 loop
            Make_Matrix_Item (Symbols (I), Pool.all, T, Items (Found + I));
            Starts (Found + I) := Symbols (I).Start;
            pragma Loop_Invariant
              (for all K in 0 .. Found + I => Valid_Item (Items (K)));
            pragma Loop_Invariant
              (for all K in 0 .. Found - 1 =>
                 not Is_Matrix (Items (K).Symbology));
            pragma Loop_Invariant
              (for all K in Found .. Found + I =>
                 In_Pool (Items (K), Starts (K), Pool'Last));
         end loop;
      end if;

      Allocate_Results (Results);
      if Results = null then
         Free (Items);
         Free (Starts);
         return;
      end if;
      Results.Count := Found + Matrix;
      Results.Items := Items;
      Results.Starts := Starts;
      if Matrix > 0 then
         Results.Texts := Pool;
         Pool := null;
      end if;
   end Build_Results;

   ---------------------------------------------------------------------
   --  The area to scan
   ---------------------------------------------------------------------

   procedure Find_Box
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Box    : out Scan_Box;
      Empty  : out Boolean)
   with
     Pre  => KI.Valid_Image (Image)
             and then (Region = null or else KR.Valid_Region (Region)),
     Post => (if not Empty
              then Region /= null
                   and then Box.X_Lo <= Box.X_Hi and then Box.Y_Lo <= Box.Y_Hi
                   and then Box.X_Hi < Natural (Image.Width)
                   and then Box.Y_Hi < Natural (Image.Height));
   --  The bounding box of the pixels of the region that are in the image.
   --  Empty: there are none (null is the empty region).

   procedure Find_Box
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Box    : out Scan_Box;
      Empty  : out Boolean)
   is
      W : constant Positive := Positive (Image.Width);
      H : constant Positive := Positive (Image.Height);
   begin
      Box := (others => 0);
      if Region = null
        or else Region.X_Min >= Image.Width
        or else Region.Y_Min >= Image.Height
      then
         Empty := True;
      else
         Empty := False;
         Box.X_Lo := Natural (Region.X_Min);
         Box.Y_Lo := Natural (Region.Y_Min);
         Box.X_Hi :=
           Natural (Int64'Min (Int64 (Region.X_Min)
                               + Int64 (Region.Width) - 1,
                               Int64 (W - 1)));
         Box.Y_Hi :=
           Natural (Int64'Min (Int64 (Region.Y_Min)
                               + Int64 (Region.Height) - 1,
                               Int64 (H - 1)));
      end if;
   end Find_Box;

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Run_Params_Default
     (Params : out Ks_Code_Reader_Run_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Run_Params_Default;

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Params              : Ks_Code_Reader_Run_Params;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : out Ks_Code_Reader_Results;
      Status              : out Ks_Status)
   is
      Settings : Scan_Settings;
      Box      : Scan_Box;
      Empty    : Boolean;
      Span     : Natural;
      Base     : Long_Float;
      Levels   : Level_Array_Access;
      Extremes : Extreme_Array_Access;
      Edges    : Position_Array_Access;
      Mirror   : Position_Array_Access;
      Table    : Candidate_Array_Access;
      Count    : Natural := 0;
      Overflow : Boolean := False;
      Symbols  : Symbol_Array_Access;
      Matrix   : Natural := 0;
      Pool     : Text_Pool_Access;
      Used     : Natural := 0;
      Outcome  : Pass_Outcome;
   begin
      Results := null;
      FI.Check_Input (Image, Region, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Selected_From_Pixel) then
         Bad (Status, "Selected_From_Pixel must be finite and within"
                      & " +/-1.0E150");
         return;
      end if;
      Settings := Settings_Of (Params);

      Find_Box (Image, Region, Box, Empty);
      if not Empty
        and then Int64 (Box.X_Hi - Box.X_Lo) + Int64 (Box.Y_Hi - Box.Y_Lo)
                   > Max_Line_Samples - 2
      then
         --  The box is that many columns plus one wide, and as many rows
         --  plus one tall.
         Bad (Status, "CodeReader: the width plus the height of the area"
                      & " to scan must not exceed 1048576");
         return;
      end if;

      Allocate_Candidates (Table);
      if Table = null then
         Out_Of_Memory (Status);
         return;
      end if;

      --  The linear symbologies, along the scan lines.
      if not Empty and then Params.Symbologies mod Symbology_Data_Matrix /= 0
      then
         Span := (Box.X_Hi - Box.X_Lo) + (Box.Y_Hi - Box.Y_Lo);
         Allocate_Levels (Span + 1, Levels);
         Allocate_Extremes (Span + 1, Extremes);
         Allocate_Positions (Span + 5, Edges);
         Allocate_Positions (Span + 5, Mirror);
         if Levels = null or else Extremes = null or else Edges = null
           or else Mirror = null
         then
            Free (Levels);
            Free (Extremes);
            Free (Edges);
            Free (Mirror);
            Free (Table);
            Out_Of_Memory (Status);
            return;
         end if;

         Base := N.Reduce_Two_Pi (Params.First_Direction);
         for K in 0 .. Natural (Params.Num_Directions) - 1 loop
            pragma Loop_Invariant
              (Levels /= null and then Extremes /= null
               and then Edges /= null and then Mirror /= null
               and then Table /= null);
            pragma Loop_Invariant
              (Arrays_OK (Levels.all, Extremes.all, Edges.all, Mirror.all)
               and then Levels'Last = Span);
            pragma Loop_Invariant (Table_OK (Table.all, Count, Count));
            Scan_Direction
              (Image, Region, Box,
               Base + Turn_Of (K, Natural (Params.Num_Directions)),
               Settings, Levels.all, Extremes.all, Edges.all, Mirror.all,
               Table.all, Count, Overflow);
            exit when Overflow;
         end loop;
         Free (Levels);
         Free (Extremes);
         Free (Edges);
         Free (Mirror);
         if Overflow then
            Free (Table);
            Set_Failure (Status, Failure_Other,
                         "CodeReader: more than 4096 candidates");
            return;
         end if;
      end if;

      --  The two-dimensional symbols, in the dark and light pixels.
      if not Empty
        and then (Has (Params.Symbologies, Symbology_Data_Matrix)
                  or else Has (Params.Symbologies, Symbology_QR_Code))
      then
         Allocate_Symbols (Symbols);
         Allocate_Texts (Pool_Start, Pool);
         if Symbols = null or else Pool = null then
            Free (Symbols);
            Free (Pool);
            Free (Table);
            Out_Of_Memory (Status);
            return;
         end if;
         --  A block has dark and light pixels when they differ by
         --  twice the contrast threshold: the lightest and the darkest
         --  of its 64 pixels differ by the whole swing of the noise.
         Find_Symbols (Image, Region, Box,
                       Integer'Min (2 * Settings.Threshold, 255),
                       Has (Params.Symbologies, Symbology_Data_Matrix),
                       Has (Params.Symbologies, Symbology_QR_Code),
                       Max_Candidates - Count, Symbols.all, Matrix, Pool,
                       Used, Outcome);
         if Outcome /= Done then
            Free (Symbols);
            Free (Pool);
            Free (Table);
            if Outcome = No_Memory then
               Out_Of_Memory (Status);
            else
               Set_Failure (Status, Failure_Other,
                            "CodeReader: more than 4096 candidates");
            end if;
            return;
         end if;
      end if;

      Build_Results (Table.all, Count, Settings.Spacing, Symbols, Matrix,
                     Pool, Used, Selected_From_Pixel, Results);
      Free (Table);
      Free (Symbols);
      Free (Pool);
      if Results = null then
         Out_Of_Memory (Status);
      else
         Set_Success (Status);
      end if;
   end Execute;

   procedure Results_Destroy (Results : in out Ks_Code_Reader_Results) is
   begin
      if Results /= null then
         Free (Results.Items);
         Free (Results.Starts);
         Free (Results.Texts);
         Free (Results);
      end if;
   end Results_Destroy;

   procedure Results_Count
     (Results : access constant Ks_Code_Reader_Results_Data;
      Count   : out Int32;
      Status  : out Ks_Status) is
   begin
      Count := 0;
      if Results = null then
         Set_Success (Status);
      elsif not Valid_Results (Results) then
         Bad (Status, "Results is not a valid code reader results handle");
      else
         Count := Int32 (Results.Count);
         Set_Success (Status);
      end if;
   end Results_Count;

   procedure Results_Item
     (Results : access constant Ks_Code_Reader_Results_Data;
      Index   : Int32;
      Item    : out Ks_Code_Reader_Result;
      Status  : out Ks_Status) is
   begin
      Item := No_Result;
      if Results /= null and then not Valid_Results (Results) then
         Bad (Status, "Results is not a valid code reader results handle");
      elsif Results = null or else Index < 0
        or else Index >= Int32 (Results.Count)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Item: index outside the results");
      else
         Item := Results.Items (Natural (Index));
         Set_Success (Status);
      end if;
   end Results_Item;

   procedure Results_Text
     (Results : access constant Ks_Code_Reader_Results_Data;
      Index   : Int32;
      First   : Int32;
      Text    : out Code_Text;
      Length  : out Int32;
      Status  : out Ks_Status) is
   begin
      Text := No_Text;
      Length := 0;
      if Results /= null and then not Valid_Results (Results) then
         Bad (Status, "Results is not a valid code reader results handle");
      elsif Results = null or else Index < 0
        or else Index >= Int32 (Results.Count)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Text: index outside the results");
      elsif not Valid_Item (Results.Items (Natural (Index)))
        or else (Is_Matrix (Results.Items (Natural (Index)).Symbology)
                 and then not Text_In_Pool (Results, Natural (Index)))
      then
         Bad (Status, "Results is not a valid code reader results handle");
      elsif First < 0
        or else First > Results.Items (Natural (Index)).Length
      then
         Bad (Status, "Text: First must be in 0 .. the length of the text");
      else
         declare
            I     : constant Natural := Natural (Index);
            Whole : constant Natural := Natural (Results.Items (I).Length);
            Skip  : constant Natural := Natural (First);
            Count : constant Natural :=
              Natural'Min (Whole - Skip, Max_Text_Length);
         begin
            if Is_Matrix (Results.Items (I).Symbology) then
               for K in 1 .. Count loop
                  Text (K) :=
                    Results.Texts (Results.Starts (I) - 1 + Skip + K);
                  pragma Loop_Invariant
                    (for all J in K + 1 .. Code_Text'Last =>
                       Text (J) = ASCII.NUL);
               end loop;
            else
               for K in 1 .. Count loop
                  Text (K) := Results.Items (I).Text (Skip + K);
                  pragma Loop_Invariant
                    (for all J in K + 1 .. Code_Text'Last =>
                       Text (J) = ASCII.NUL);
               end loop;
            end if;
            Length := Int32 (Count);
            Set_Success (Status);
         end;
      end if;
   end Results_Text;

   procedure Results_Whole_Text
     (Results : access constant Ks_Code_Reader_Results_Data;
      Index   : Int32;
      Text    : out String;
      Length  : out Natural;
      Status  : out Ks_Status) is
   begin
      Text := [others => ASCII.NUL];
      Length := 0;
      if Results /= null and then not Valid_Results (Results) then
         Bad (Status, "Results is not a valid code reader results handle");
      elsif Results = null or else Index < 0
        or else Index >= Int32 (Results.Count)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Text: index outside the results");
      elsif not Valid_Item (Results.Items (Natural (Index)))
        or else (Is_Matrix (Results.Items (Natural (Index)).Symbology)
                 and then not Text_In_Pool (Results, Natural (Index)))
      then
         Bad (Status, "Results is not a valid code reader results handle");
      elsif Natural (Results.Items (Natural (Index)).Length) > Text'Last
      then
         Bad (Status, "Text: the buffer is shorter than the text");
      else
         declare
            I     : constant Natural := Natural (Index);
            Whole : constant Natural := Natural (Results.Items (I).Length);
         begin
            if Is_Matrix (Results.Items (I).Symbology) then
               for K in 1 .. Whole loop
                  Text (K) := Results.Texts (Results.Starts (I) - 1 + K);
               end loop;
            else
               for K in 1 .. Whole loop
                  Text (K) := Results.Items (I).Text (K);
               end loop;
            end if;
            Length := Whole;
            Set_Success (Status);
         end;
      end if;
   end Results_Whole_Text;

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      FI.Check_Image (Image, Status);
   end Check_Input_Image;

   procedure Check_Result_Symbology
     (Item   : Ks_Code_Reader_Result;
      Status : out Ks_Status) is
   begin
      if Is_Symbology (Item.Symbology) then
         Set_Success (Status);
      else
         Bad (Status, "Result.Symbology is not the code of a symbology");
      end if;
   end Check_Result_Symbology;

   procedure Check_Result_Length
     (Item   : Ks_Code_Reader_Result;
      Status : out Ks_Status) is
   begin
      if Item.Length in 0 .. Max_Matrix_Text_Length then
         Set_Success (Status);
      else
         Bad (Status, "Result.Length must be in 0 .. 7089");
      end if;
   end Check_Result_Length;

end AMV.Kernels.Code_Reader;
