--  Data Matrix (ECC 200): from a dark area of an image to the modules of
--  a symbol, for AMV.Kernels.Code_Reader. Internal: no entry points of
--  its own (no export); public so that the tests can call it.
--
--  The corners (Locate). The dark area with the two solid sides of a
--  symbol, the "L", has a convex hull with these two sides. Four corners
--  of the hull are taken as far apart as they are: the two that are
--  farthest from each other, and on either side the one farthest from
--  their line. The line of a side is the longest straight part of the
--  hull along it, and a side is solid when the pixels a little inside
--  its line are dark (1.5, 2.5 or 4 pixels inside: the edge of a bar in
--  a photograph is not a straight line). Two solid sides that meet are
--  the L, their common corner the lower left one of the symbol; of
--  several such pairs it is the one that is solid nearest to the hull,
--  and of these the one whose shorter side is the longest. An L with an
--  arm shorter than 10 pixels is not one.
--
--  The hull of the area with the L may cut through the symbol, from an
--  end of the L to modules that touch no others: the line of an
--  alternating side is therefore a straight part of the hull that
--  passes the end of an arm of the L and has no dark pixels 1.5 pixels
--  outside it. Where an outline turns, its pixels cut the tip off, and
--  the hull has two corners or more in place of the one: a line passes
--  the end of an arm when it runs within 2.5 pixels of the corner of
--  the hull there, or when it meets the line of the arm within 2.5
--  pixels of the last of the corners of the hull that follow within 8
--  pixels (at least the next one), or between these two corners (no
--  farther from either than they are apart, 8 pixels at most, and 2.5
--  pixels more).
--
--  A corner is where the lines of its two sides meet, if that is within
--  4 pixels of the corner of the hull, or within 2.5 pixels of a corner
--  of the hull next to it (the next one on either side, and those after
--  it within 8 pixels); two lines are taken to meet only within four
--  lengths of the straight part of the first of them. Else, and where a
--  side has no such line along a quarter of it, the corner of the hull
--  stands for a corner of the L, and the fourth corner of the
--  parallelogram of the L for the upper right corner, which no dark
--  pixel marks (its module is light); so it does where the two lines
--  meet on the side of the lower left corner, or less than half or more
--  than twice as far as that corner from the line through the ends of
--  the L.
--
--  All the dark pixels (Refine). The modules of the alternating sides
--  need not touch the area with the L. The corners are therefore taken
--  again from the hull of all the dark pixels within two pixels of the
--  outline found, until they stay (they move by half a pixel at most,
--  the four together, or come back to those of two rounds before), and
--  from pixels farther around, twice as far every time, up to an eighth
--  of the shorter arm of the L, while the hull is not straight along
--  half of each alternating side; eight rounds at most.
--
--  The modules (Count_Modules, Sample). The changes between dark and
--  light just inside the alternating sides give the number of columns
--  and of rows (1.5 pixels inside, and half a module inside where that
--  is more). The middle of every module is looked up in the map of the
--  dark pixels through the perspective mapping that takes the unit
--  square to the four corners.
--
--  The corners of a long symbol do not give the places of its columns
--  well (a small error of a corner is a large one of the point where
--  the upper and the lower side meet). For a symbol with twice as many
--  columns as rows, or more, the columns are therefore spaced as the
--  upper side shows them: the middle of that side is moved towards
--  either end in steps of an eighth of a module (up to half a module
--  for every time that the columns are as many as the rows; the two
--  ends stay), and the spacing is taken with which the most points of
--  the upper side, two a module, are dark and light as the side
--  alternates; of several such spacings next to each other the middle
--  one, and of several such groups the one nearest to what the corners
--  give. The centre of a symbol is its middle as it is printed, with
--  the columns spaced as they were read.
--
--  Proved (docs/PROOF.md): no run-time error for any map, hull and
--  outline. Not proved (tested): that the corners are those of a symbol
--  and the modules those printed.

pragma Validity_Checks ("F");
with AMV.Kernels.Code_Reader.Dark_Areas;
with AMV.Kernels.Code_Reader.Views;

package AMV.Kernels.Code_Reader.Data_Matrix.Finder
  with SPARK_Mode, Preelaborate
is

   package DA renames AMV.Kernels.Code_Reader.Dark_Areas;
   package VW renames AMV.Kernels.Code_Reader.Views;

   Limit : constant := VW.Limit;

   subtype Coordinate is VW.Coordinate;

   subtype Corner is VW.Corner;
   --  A point of a map: the pixel (X, Y) covers X .. X + 1 and
   --  Y .. Y + 1.

   subtype Outline is VW.Outline;
   --  The corners of a symbol as it is printed: the L runs from the
   --  upper left corner by the lower left one to the lower right one.

   procedure Locate
     (Map    : DA.Mark_Map;
      Hull   : DA.Point_Array;
      Symbol : out Outline;
      Found  : out Boolean)
   with Pre => DA.Valid_Map (Map) and then Hull'First = 1;
   --  The corners of the symbol of which Hull is the hull of the dark
   --  area with the L, as far as that area gives them (Refine gives
   --  them from all the dark pixels). Not Found: the hull has no L.

   procedure Refine
     (Map    : DA.Mark_Map;
      Lefts  : in out DA.Extent_Array;
      Rights : in out DA.Extent_Array;
      Points : in out DA.Point_Array;
      Symbol : in out Outline)
   with Pre => DA.Valid_Map (Map)
               and then DA.Extents_Fit (Lefts, Map)
               and then DA.Extents_Fit (Rights, Map)
               and then Points'First = 1
               and then Points'Length >= 2 * (Map'Length (1) + 1);
   --  The corners of the symbol from the hull of all the dark pixels
   --  within two pixels of the outline Symbol, taken again from the
   --  corners found until they stay, and from farther around while the
   --  alternating sides are not seen. Symbol stays as it is where that
   --  gives nothing better. Lefts and Rights: DA.No_Left and DA.No_Right
   --  in every row, on entry and on return; Points: a work array.

   procedure Count_Modules
     (Map           : DA.Mark_Map;
      Symbol        : Outline;
      Rows, Columns : out Natural)
   with Pre => DA.Valid_Map (Map);
   --  The modules along the right side and along the upper side, from
   --  the changes between dark and light.

   procedure Sample
     (Map           : DA.Mark_Map;
      Symbol        : Outline;
      Rows, Columns : Positive;
      Grid          : out Module_Grid;
      Centre        : out Corner)
   with Pre => DA.Valid_Map (Map)
               and then Rows <= Max_Side and then Columns <= Max_Side;
   --  Grid (R, C) for R < Rows and C < Columns: the module is dark.
   --  Centre: the middle of the symbol as it is printed, with the
   --  columns spaced as they were read; the mean of the corners where
   --  the mapping gives none, or a point farther than 2 ** 28 pixels
   --  from an axis.

   function Mirrored (Symbol : Outline) return Outline is
     (Upper_Left  => Symbol.Lower_Right,
      Upper_Right => Symbol.Upper_Right,
      Lower_Right => Symbol.Upper_Left,
      Lower_Left  => Symbol.Lower_Left);
   --  The corners of a symbol that is seen from behind.

end AMV.Kernels.Code_Reader.Data_Matrix.Finder;
