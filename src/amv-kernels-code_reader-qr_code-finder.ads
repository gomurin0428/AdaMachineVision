--  QR Code (Model 2): from the dark pixels of an image to the modules
--  of a symbol, for AMV.Kernels.Code_Reader. Internal: no entry points
--  of its own (no export); public so that the tests can call it.
--
--  The finder patterns (Find_Patterns). A line through the middle of a
--  finder pattern crosses dark, light, dark, light and dark in the
--  proportions 1 : 1 : 3 : 1 : 1, whatever its direction. Every row of
--  the map is searched for five such runs: the module being a seventh
--  of the five together, each narrow run is within half a module and
--  half a pixel of a module, and the wide one within a module and a
--  half and half a pixel of three (the runs of a pattern with modules
--  of two pixels have a pixel more or less, wherever the pattern lies
--  on the pixels). The column through the middle of the third run must
--  show the five runs too, and so must the row through the middle that
--  the column gives, or the row after or before it; no run may be
--  longer than the third run of the row first found, and the five
--  together differ by less than two fifths from those of that row. The
--  two diagonals through the middle so found must show the five runs
--  as well, with as many pixels together as a square pattern has along
--  a diagonal: from half as many as along the row to as many, within
--  two fifths. The pattern is where the middles of the third runs of
--  the column and of the last row are. What is found within a module
--  of a pattern found before, with a module of about the same width,
--  is the same pattern: its place and its module are the means. A
--  pattern must be found in two rows; where the table is full, the
--  patterns found in one row that the rows have passed make room.
--
--  The middle of a run is known within half a pixel, which is a quarter
--  of a module where the modules have two pixels, and the far corner of
--  a symbol without an alignment pattern lies where the three middles
--  put it. So every pattern found is put at last where the dark pixels
--  of the three modules by three in its middle have theirs: the rows of
--  dark pixels above and below the middle as it was found, each
--  followed through the middle of the one before it. A pattern stays
--  where it was found if these are not the pixels of such a middle (a
--  row of more than four modules and two pixels, or more rows than that
--  on one side), if they have their middle more than a module from the
--  one found, or if its modules have more than 1000 pixels.
--
--  Three patterns (Place). The three finder patterns of a symbol are
--  the corners of half a square. Of three patterns, one is taken as the
--  upper left one; the two arms from it to the others must be about as
--  long as each other (neither more than twice the other), at least
--  seven modules of the narrowest of the three patterns, and stand at
--  60 to 120 degrees, and no pattern may have modules more than twice
--  as wide as another. The width of a module along an arm is a seventh
--  of the way across a pattern along that arm: from the middle of the
--  pattern to the third change between dark and light on either side,
--  the mean of the patterns at the two ends. The arm is as many modules
--  long as the symbol has along a side, less seven; that gives the
--  version, which the caller tries with its neighbours. The pattern on
--  the right of the way from the first to the second arm is the upper
--  right one: a symbol seen from behind is found with its rows for
--  columns.
--
--  A symbol seen at an angle has wider modules where it is nearer:
--  along an arm, the widths of a module at the two ends are, inversely,
--  as the squares of the distances of the two patterns. So the two
--  widths give how much farther the pattern at the far end is than the
--  upper left one, less exactly than the middles of the patterns are
--  known.
--
--  The modules (Sample). The three middles give two mappings: a
--  straight one, without perspective, and a leaning one, with the
--  perspective that the widths of the modules tell. The straight one is
--  exact for a symbol seen from the front, where the leaning one has
--  the error of the widths; so the leaning one is the first where the
--  widths at the two ends of an arm differ by a tenth or more, and the
--  straight one otherwise. A mapping is of use where it puts the three
--  finder patterns on those of the map: of the seven modules across the
--  middle of each and the seven down, four at most may be other than
--  those of a pattern. It must put one of the two timing patterns at
--  least on its modules as well: along the seventh row and along the
--  seventh column of a symbol, from the corner module of one finder
--  pattern to that of the next, dark and light change with every
--  module, as many times as a side has modules, less 13; where the
--  mapping puts one of the two, they must change as many times, a
--  quarter more or less (two, where a quarter is less), so that a
--  version that is not that of the symbol, and three patterns that are
--  not those of one symbol, are given up before anything else is looked
--  for. The other timing pattern may be covered: its modules hold no
--  data. Where neither mapping is of use, there is nothing to sample.
--  From version 2 on, the alignment pattern nearest to the corner
--  without a finder pattern is looked for around where the first
--  mapping puts it, four modules to either side in steps of a quarter
--  of a module, then eight, and then likewise with the other mapping: a
--  place is one where the 25 middles of its modules are dark and light
--  as the pattern is. Of the places a sixteenth of a module on either
--  side of the steps of an eighth, within a module of the place nearest
--  to where the pattern was expected, the mean is its middle (those of
--  a pattern that lies exactly on the pixels are as many on either side
--  of it). With the alignment pattern, the mapping is the perspective
--  one that takes the four middles to where they are; without it, the
--  mapping is the first one of use. The middle of every module is
--  looked up in the map through the mapping. A caller that cannot read
--  the modules asks again, for the other mapping to be the first: that
--  is something else only where both are of use.
--
--  Proved (docs/PROOF.md): no run-time error for any map and patterns.
--  Not proved (tested): that the patterns are those of a symbol and the
--  modules those printed.

pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Code_Reader.Dark_Areas;
with AMV.Kernels.Code_Reader.Views;

package AMV.Kernels.Code_Reader.QR_Code.Finder
  with SPARK_Mode, Preelaborate
is

   package DA renames AMV.Kernels.Code_Reader.Dark_Areas;
   package VW renames AMV.Kernels.Code_Reader.Views;

   subtype Corner is VW.Corner;
   subtype Outline is VW.Outline;

   subtype Module_Size is Long_Float range 0.0 .. VW.Limit;
   --  The width of a module, in pixels.

   Max_Seen : constant := 2 ** 20;

   type Pattern is record
      Centre : Corner;
      Module : Module_Size := 0.0;
      Seen   : Natural range 0 .. Max_Seen := 0;
   end record;
   --  A finder pattern: its middle, the width of a module as the rows
   --  and the columns through it show it (wider than it is where the
   --  symbol is turned), and the rows in which it was found (no more
   --  are counted than Max_Seen).

   type Pattern_Array is array (Positive range <>) of Pattern;

   function Akin (First, Second : Pattern) return Boolean is
     (First.Module <= 2.0 * Second.Module
      and then Second.Module <= 2.0 * First.Module);
   --  Neither pattern has modules more than twice as wide as those of
   --  the other: the two can be finder patterns of one symbol.

   procedure Find_Patterns
     (Map      : DA.Mark_Map;
      Patterns : in out Pattern_Array;
      Count    : out Natural)
   with Pre  => DA.Valid_Map (Map) and then Patterns'First = 1,
        Post => Count <= Patterns'Length;
   --  Patterns (1 .. Count): the finder patterns of the map, in the
   --  order of the rows in which they were first found. No more are
   --  found than Patterns holds.

   subtype Farther is Long_Float range -0.5 .. 1.0;
   --  How much farther from the eye than the upper left finder pattern
   --  another one is, as a part of the distance of the upper left one.

   type Placement is record
      Upper_Left, Upper_Right, Lower_Left : Corner;
      Version                             : Version_Number := 1;
      Across, Down                        : Farther := 0.0;
   end record;
   --  The middles of the three finder patterns of a symbol, its
   --  version as their distances give it, and how much farther the
   --  upper right (Across) and the lower left (Down) patterns are as
   --  the widths of the modules give it (0.0: the width is not seen at
   --  both ends of the arm).

   procedure Place
     (Map         : DA.Mark_Map;
      First       : Pattern;
      Second      : Pattern;
      Third       : Pattern;
      Symbol      : out Placement;
      Found       : out Boolean)
   with Pre => DA.Valid_Map (Map);
   --  The symbol with First as its upper left finder pattern and Second
   --  and Third as the two others. Not Found: the three are not the
   --  corners of half a square, or the width of a module is not seen.

   procedure Sample
     (Map      : DA.Mark_Map;
      Symbol   : Placement;
      Version  : Version_Number;
      Again    : Boolean;
      Grid     : out Module_Grid;
      Shape    : out Outline;
      Centre   : out Corner;
      OK       : out Boolean)
   with Pre => DA.Valid_Map (Map);
   --  Grid (R, C) for R and C below Side (Version): the module is
   --  dark. Shape and Centre: the corners and the middle of the symbol.
   --  Again: with the other of the two mappings first (for a symbol
   --  that was not read with the first).
   --  Not OK: no mapping puts the finder patterns and a timing
   --  pattern of a symbol of that version on those of the map (Again:
   --  one of the two does not, so that there is no other to be the
   --  first); or the mapping gives no such points, or points farther
   --  than 2 ** 28 pixels from an axis.

end AMV.Kernels.Code_Reader.QR_Code.Finder;
