pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;
with AMV.Kernels.Code_Reader.Linear;
with AMV.Kernels.Code_Reader.Profiles;
with AMV.Kernels.Filter_Inputs;
with AMV.Kernels.Image_Sampling;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Code_Reader with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package FI renames AMV.Kernels.Filter_Inputs;
   package L renames AMV.Kernels.Code_Reader.Linear;
   package N renames AMV.Kernels.Numerics;
   package P renames AMV.Kernels.Code_Reader.Profiles;
   package Sampling renames AMV.Kernels.Image_Sampling;

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
                then Results.Count = 0 and then Results.Items = null);
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
     (Params.Symbologies in 1 .. Symbology_All_Linear
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
      if Params.Symbologies not in 1 .. Symbology_All_Linear then
         Bad (Status, "RunParams.Symbologies must be a sum of"
                      & " KS_CODE_READER_SYMBOLOGY_*, in 1 .. 127");
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
             and then Is_Symbology (Item.Symbology)
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
      Length : constant Long_Float :=
        N.Times_Unit (EW, abs UX) + N.Times_Unit (EH, abs UY);
      Across : constant Long_Float :=
        N.Times_Unit (EW, abs UY) + N.Times_Unit (EH, abs UX);

      Samples : constant Positive := Count_Of (Length, Levels'Length);
      Lines   : constant Positive :=
        Count_Of (Across / Settings.Spacing, Levels'Length);

      --  The centre of the box, and the middle sample and the middle
      --  line, which lie on it.
      CX   : constant Long_Float :=
        (Long_Float (Box.X_Lo) + Long_Float (Box.X_Hi)) / 2.0;
      CY   : constant Long_Float :=
        (Long_Float (Box.Y_Lo) + Long_Float (Box.Y_Hi)) / 2.0;
      Half : constant Long_Float := Long_Float (Samples - 1) / 2.0;
      Mid  : constant Long_Float := Long_Float (Lines - 1) / 2.0;

      Open : constant Natural := Count;
   begin
      Overflow := False;
      for J in 0 .. Lines - 1 loop
         pragma Loop_Invariant (Table_OK (Table, Open, Count));
         declare
            Offset : constant Long_Float :=
              N.Mul_Within (Long_Float (J) - Mid, Settings.Spacing,
                            2.0 ** 20, Max_Line_Spacing);
            pragma Assert
              (abs CX <= 2.0 ** 31 and then abs CY <= 2.0 ** 31);
            pragma Assert (Half >= 0.0 and then Half <= 2.0 ** 20);
            Line   : constant Scan_Line :=
              (Index => J,
               X0    => To_Origin (CX - N.Times_Unit (Offset, UY)
                                   - N.Times_Unit (Half, UX)),
               Y0    => To_Origin (CY + N.Times_Unit (Offset, UX)
                                   - N.Times_Unit (Half, UY)),
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
   --  Results
   ---------------------------------------------------------------------

   function Centre (C : Candidate) return Point is
     (X => (C.S1.X + C.E1.X + C.E2.X + C.S2.X) / 4.0,
      Y => (C.S1.Y + C.E1.Y + C.E2.Y + C.S2.Y) / 4.0);
   --  The mean of the four corners.

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
      DX : constant Long_Float := CB.X - CA.X;
      DY : constant Long_Float := CB.Y - CA.Y;

      --  Twice the mean vector from the start of A to its end.
      AX : constant Long_Float := (A.E1.X - A.S1.X) + (A.E2.X - A.S2.X);
      AY : constant Long_Float := (A.E1.Y - A.S1.Y) + (A.E2.Y - A.S2.Y);

      --  From the first line of A to its last.
      WX : constant Long_Float := A.S2.X - A.S1.X;
      WY : constant Long_Float := A.S2.Y - A.S1.Y;

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
      ASX : constant Long_Float := A.S1.X + A.S2.X;
      ASY : constant Long_Float := A.S1.Y + A.S2.Y;
      AEX : constant Long_Float := A.E1.X + A.E2.X;
      AEY : constant Long_Float := A.E1.Y + A.E2.Y;
      BSX : constant Long_Float := B.S1.X + B.S2.X;
      BSY : constant Long_Float := B.S1.Y + B.S2.Y;
      BEX : constant Long_Float := B.E1.X + B.E2.X;
      BEY : constant Long_Float := B.E1.Y + B.E2.Y;

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
     Post => Valid_Item (Item);
   --  The result of a candidate, in the space that T maps pixel space to.

   procedure Make_Item
     (C    : Candidate;
      T    : KT.Ks_Transform_2D_Linear;
      Item : out Ks_Code_Reader_Result)
   is
      Mid : constant Point := Centre (C);

      --  Along the scan lines, from the start of the symbol to its end.
      AX : constant Long_Float := (C.E1.X - C.S1.X) + (C.E2.X - C.S2.X);
      AY : constant Long_Float := (C.E1.Y - C.S1.Y) + (C.E2.Y - C.S2.Y);

      --  Along the bars, from the first line to the last, turned by a
      --  quarter of a turn: across the bars.
      QX : constant Long_Float :=
        (C.BS2.Y - C.BS1.Y) + (C.BE2.Y - C.BE1.Y);
      QY : constant Long_Float :=
        -((C.BS2.X - C.BS1.X) + (C.BE2.X - C.BE1.X));

      Side   : Long_Float;
      RX, RY : Long_Float;
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

   procedure Build_Results
     (Table   : in out Candidate_Array;
      Count   : Natural;
      Spacing : Long_Float;
      T       : KT.Ks_Transform_2D_Linear;
      Results : out Ks_Code_Reader_Results)
   with
     Pre  => Table_OK (Table, 0, Count)
             and then Spacing >= 1.0 and then Spacing <= Max_Line_Spacing
             and then KT.Bounded (T),
     Post => (if Results /= null then Gold_Results (Results));
   --  The results of the candidates Table (0 .. Count - 1): the one with
   --  the most lines first, and none that lies on top of an earlier one
   --  (its centre in the area of the earlier one, or the other way round)
   --  or whose middle line crosses that of an earlier one. Two symbols
   --  cannot do either, so these are readings of one symbol in two
   --  directions, or a misreading of a part of it.
   --  Null when the memory cannot be allocated.

   procedure Build_Results
     (Table   : in out Candidate_Array;
      Count   : Natural;
      Spacing : Long_Float;
      T       : KT.Ks_Transform_2D_Linear;
      Results : out Ks_Code_Reader_Results)
   is
      Items  : Item_Array_Access;
      Found  : Natural := 0;
      Best   : Natural;
      Have   : Boolean;
      Hidden : Boolean;
   begin
      Results := null;
      Allocate_Items (Positive'Max (Count, 1), Items);
      if Items = null then
         return;
      end if;

      --  Every round settles one candidate.
      for Round in 1 .. Count loop
         pragma Loop_Invariant (Items /= null);
         pragma Loop_Invariant
           (Items'First = 0 and then Items'Last = Positive'Max (Count, 1) - 1);
         pragma Loop_Invariant (Found < Round);
         pragma Loop_Invariant
           (for all I in 0 .. Found - 1 => Valid_Item (Items (I)));

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

      Allocate_Results (Results);
      if Results = null then
         Free (Items);
         return;
      end if;
      Results.Count := Found;
      Results.Items := Items;
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
              then Box.X_Lo <= Box.X_Hi and then Box.Y_Lo <= Box.Y_Hi
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

      if not Empty then
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
               Base + N.Pi * Long_Float (K)
                      / Long_Float (Params.Num_Directions),
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

      Build_Results (Table.all, Count, Settings.Spacing,
                     Selected_From_Pixel, Results);
      Free (Table);
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
      if Item.Length in 0 .. Max_Text_Length then
         Set_Success (Status);
      else
         Bad (Status, "Result.Length must be in 0 .. 255");
      end if;
   end Check_Result_Length;

end AMV.Kernels.Code_Reader;
