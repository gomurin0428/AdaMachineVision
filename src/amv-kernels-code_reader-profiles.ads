--  The scan lines of AMV.Kernels.Code_Reader: the grey levels along a
--  line and the edges of a segment of it. Internal: not an entry point
--  (no export), so the package is private to the code reader.

pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Code_Reader.Linear;

private package AMV.Kernels.Code_Reader.Profiles
  with SPARK_Mode, Preelaborate
is

   package L renames AMV.Kernels.Code_Reader.Linear;

   type Level is range -1 .. 255 with Size => 16;
   --  A grey level, or No_Sample.

   No_Sample : constant Level := -1;
   --  A point outside the image or outside the region.

   type Level_Array is array (Natural range <>) of Level;

   Coordinate_Limit : constant := 2.0 ** 33;
   --  A bound of the coordinates of the first point of a line: beyond
   --  every image (at most 2 ** 31 pixels wide or tall) by more than the
   --  longest line.

   procedure Sample_Line
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      X0, Y0 : Long_Float;
      DX, DY : Long_Float;
      Count  : Natural;
      Levels : in out Level_Array)
   with
     Pre => KI.Valid_Image (Image)
            and then Levels'First = 0
            and then Levels'Last <= Max_Line_Samples
            and then Count <= Levels'Length
            and then abs X0 <= Coordinate_Limit
            and then abs Y0 <= Coordinate_Limit
            and then abs DX <= 1.0 and then abs DY <= 1.0;
   --  Levels (I) := the level at (X0 + I * DX, Y0 + I * DY), for I in
   --  0 .. Count - 1: interpolated bilinearly, or No_Sample for a point
   --  outside the image or whose nearest pixel is not in the region
   --  (null: every pixel). The points are those of
   --  AMV.Kernels.Image_Sampling (the area the pixels cover, with the
   --  border pixels repeated within the outer half pixel); they are
   --  followed in whole numbers of 1 / 2 ** 28 pixel, so that a sample
   --  costs no floating-point operation, which places the last sample of
   --  the longest line within 1 / 512 pixel.

   subtype Grey is Integer range 0 .. 255;

   type Extreme is record
      Pos   : Natural := 0;
      Value : Grey := 0;
   end record;
   --  A local maximum or minimum of a segment: its sample and its level.

   type Extreme_Array is array (Natural range <>) of Extreme;

   Envelope_Reach : constant := 6;
   --  The light and the dark level at an edge are taken from the two
   --  extremes it lies between and this many extremes on either side:
   --  about three characters of a symbol.

   procedure Find_Edges
     (Levels    : Level_Array;
      First     : Natural;
      Last      : Natural;
      Threshold : Positive;
      Extremes  : in out Extreme_Array;
      Edges     : in out L.Position_Array;
      Edge_Last : out Natural)
   with
     Pre  => Levels'First = 0
             and then First <= Last and then Last <= Levels'Last
             and then Levels'Last <= Max_Line_Samples
             and then Threshold <= 255
             and then Extremes'First = 0
             and then Extremes'Last >= Last - First
             and then Extremes'Last <= Max_Line_Samples
             and then Edges'First = 0
             and then Edges'Last <= L.Max_Edges
             and then Edges'Last >= Last - First + 4,
     Post => L.Well_Formed (Edges, Edge_Last);
   --  The edges of the segment Levels (First .. Last) as Linear wants
   --  them, in Edges (0 .. Edge_Last): positions in 1/256 sample from
   --  sample First, never decreasing. Extremes is work space.
   --
   --  The extremes of the segment are its local maxima and minima, in
   --  turn, each differing from the one before by Threshold or more
   --  (smaller ups and downs are ignored) and by a quarter or more of
   --  the steepest step nearby: the largest difference of two samples
   --  next to each other on the way to the extreme and on the
   --  Envelope_Reach rises and falls before and after it. In a sharp
   --  image the levels jump at the edges of the bars, and what swings by
   --  less than a quarter of such a jump is no bar: the overshoot next
   --  to an edge of a sharpened photograph, or the texture of the print.
   --  A blurred image has no steep step, so its narrow bars, which swing
   --  little, stay. An edge lies between two
   --  extremes, where the levels first cross the level halfway between
   --  the light and the dark level there: the highest and the lowest
   --  level of the two extremes and of the Envelope_Reach extremes
   --  before and after them. A narrow bar or space between wide ones
   --  does not reach the level of its neighbours in a blurred image, and
   --  the level halfway between its own extremes would make it too
   --  wide. The crossing level is kept at least a quarter of the way
   --  from either extreme, so that the run is not lost when its level
   --  does not reach halfway. No_Sample counts as level 0.

end AMV.Kernels.Code_Reader.Profiles;
