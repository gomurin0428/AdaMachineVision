--  Data Matrix (ECC 200): from a dark area of an image to the modules of
--  a symbol, for AMV.Kernels.Code_Reader. Internal: no entry points of
--  its own (no export); public so that the tests can call it.
--
--  The corners (Locate). The dark area with the two solid sides of a
--  symbol, the "L", has a convex hull with these two sides. Four corners
--  of the hull are taken as far apart as they are: the two that are
--  farthest from each other, and on either side the one farthest from
--  their line. A side is solid when the pixels a little inside it are
--  dark; two solid sides that meet, the other two not solid, are the L,
--  their common corner the lower left one of the symbol. The line of a
--  side is the longest straight part of the hull along it, for the two
--  alternating sides one that passes the end of the L; a corner is
--  where the lines of its two sides meet. Where the hull is not straight
--  along a quarter of a side, the corner of the hull stands for a
--  corner of the L, and the fourth corner of the parallelogram of the L
--  for the upper right corner, which no dark pixel marks (its module is
--  light).
--
--  All the dark pixels (Refine). The modules of the alternating sides
--  need not touch the area with the L. The corners are therefore taken
--  again from the hull of all the dark pixels within two pixels of the
--  outline found, until they stay, and from pixels farther around, up
--  to an eighth of the L, while the hull is not straight along half of
--  each alternating side.
--
--  The modules (Count_Modules, Sample). The changes between dark and
--  light just inside the alternating sides give the number of columns
--  and of rows. The middle of every module is looked up in the map of
--  the dark pixels through the perspective mapping that takes the unit
--  square to the four corners.

pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Code_Reader.Dark_Areas;

package AMV.Kernels.Code_Reader.Data_Matrix.Finder
  with SPARK_Mode
is

   package DA renames AMV.Kernels.Code_Reader.Dark_Areas;

   Limit : constant := 2.0 ** 28;

   subtype Coordinate is Long_Float range -Limit .. Limit;

   type Corner is record
      X, Y : Coordinate := 0.0;
   end record;
   --  A point of a map: the pixel (X, Y) covers X .. X + 1 and
   --  Y .. Y + 1.

   type Outline is record
      Upper_Left, Upper_Right, Lower_Right, Lower_Left : Corner;
   end record;
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
      Grid          : out Module_Grid)
   with Pre => DA.Valid_Map (Map)
               and then Rows <= Max_Side and then Columns <= Max_Side;
   --  Grid (R, C) for R < Rows and C < Columns: the module is dark.

   function Mirrored (Symbol : Outline) return Outline is
     (Upper_Left  => Symbol.Lower_Right,
      Upper_Right => Symbol.Upper_Right,
      Lower_Right => Symbol.Upper_Left,
      Lower_Left  => Symbol.Lower_Left);
   --  The corners of a symbol that is seen from behind.

end AMV.Kernels.Code_Reader.Data_Matrix.Finder;
