--  The dark areas of an image, for the two-dimensional symbologies of
--  AMV.Kernels.Code_Reader: which pixels are dark, the outline of a
--  connected dark area, and the convex hull of that outline. Internal:
--  no entry points of its own (no export); public so that the tests can
--  call it.
--
--  Dark pixels (Binarise). The area is divided into blocks of 8 by 8
--  pixels. A block whose lightest and darkest pixel differ by the
--  contrast threshold or more has a middle level; the threshold of a
--  block is the mean of the middle levels within two blocks around it.
--  Where there is none (modules as large as the blocks have no edge
--  within a block), it is the level halfway between the lightest and
--  the darkest pixel of those blocks if these differ by the contrast
--  threshold or more, else the mean of all the middle levels of the
--  area, or, without any, the level halfway between the lightest and
--  the darkest pixel of the area. A pixel is dark when its level is not
--  above the threshold of its block. An area whose lightest and darkest
--  pixel differ by less than the contrast threshold has no dark pixel.
--
--  Outlines (Trace). Dark pixels that touch, also by a corner, belong to
--  one area. The outline is followed from a dark pixel whose left
--  neighbour is light, clockwise as the image is seen, until it closes;
--  its pixels are marked, so that no outline is followed twice. The
--  outline around an area has a positive enclosed area, that of a hole
--  in it a negative one.
--
--  Hull. The convex hull of the squares that the pixels of an outline
--  cover, from the leftmost and the rightmost pixel of every row; its
--  corners are corners of pixels (whole numbers), clockwise as the image
--  is seen.
--
--  Proved (docs/PROOF.md): no run-time error for any image and map.

pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package AMV.Kernels.Code_Reader.Dark_Areas
  with SPARK_Mode, Preelaborate
is

   Max_Side : constant := 2 ** 26;
   --  The rows and the columns of a map, at most.

   Block : constant := 8;
   --  The side of a block of Binarise, in pixels.

   type Mark is (Light, Dark, Traced) with Size => 8;
   --  Traced: dark, and on an outline that has been followed.

   type Mark_Map is array (Natural range <>, Natural range <>) of Mark;
   --  (Y, X) from 0: the pixels of the area to search.

   function Valid_Map (Map : Mark_Map) return Boolean is
     (Map'First (1) = 0 and then Map'First (2) = 0
      and then Map'Last (1) in 0 .. Max_Side - 1
      and then Map'Last (2) in 0 .. Max_Side - 1);

   ---------------------------------------------------------------------
   --  Dark pixels
   ---------------------------------------------------------------------

   function Blocks_Fit (Levels : KI.Grey_8_Matrix; Map : Mark_Map)
     return Boolean
   is
     (Levels'First (1) = 0 and then Levels'First (2) = 0
      and then Levels'Last (1) = Map'Last (1) / Block
      and then Levels'Last (2) = Map'Last (2) / Block)
   with Pre => Valid_Map (Map);
   --  Levels has one element for every block of Map.

   procedure Binarise
     (Pixels     : KI.Grey_8_Matrix;
      X_Lo, Y_Lo : Natural;
      Contrast   : Positive;
      Lows       : in out KI.Grey_8_Matrix;
      Highs      : in out KI.Grey_8_Matrix;
      Map        : in out Mark_Map)
   with
     Pre => Valid_Map (Map)
            and then Pixels'First (1) = 0 and then Pixels'First (2) = 0
            and then Y_Lo <= Pixels'Last (1)
            and then X_Lo <= Pixels'Last (2)
            and then Map'Last (1) <= Pixels'Last (1) - Y_Lo
            and then Map'Last (2) <= Pixels'Last (2) - X_Lo
            and then Contrast <= 255
            and then Blocks_Fit (Lows, Map)
            and then Blocks_Fit (Highs, Map);
   --  Map (Y, X) := Dark or Light, from the pixel
   --  Pixels (Y_Lo + Y, X_Lo + X). Lows and Highs are work arrays.

   ---------------------------------------------------------------------
   --  Outlines
   ---------------------------------------------------------------------

   type Extent_Array is array (Natural range <>) of Integer;
   --  For every row of a map, a column.

   No_Left  : constant := Max_Side;
   No_Right : constant := -1;
   --  The leftmost and the rightmost column of a row without a pixel.

   function Extents_Fit (Extents : Extent_Array; Map : Mark_Map)
     return Boolean
   is (Extents'First = 0 and then Extents'Last = Map'Last (1));

   procedure Trace
     (Map        : in out Mark_Map;
      X, Y       : Natural;
      Lefts      : in out Extent_Array;
      Rights     : in out Extent_Array;
      Y_Lo, Y_Hi : out Natural;
      Area       : out Int64;
      Closed     : out Boolean)
   with
     Pre  => Valid_Map (Map)
             and then Y <= Map'Last (1) and then X <= Map'Last (2)
             and then Map (Y, X) /= Light
             and then Extents_Fit (Lefts, Map)
             and then Extents_Fit (Rights, Map),
     Post => Y_Lo <= Y and then Y <= Y_Hi and then Y_Hi <= Map'Last (1);
   --  Follows the outline through the pixel (X, Y), whose left neighbour
   --  is light or outside the map, and marks its pixels Traced.
   --  Lefts and Rights: lowered and raised to the leftmost and the
   --  rightmost pixel of the outline in every row (on entry No_Left and
   --  No_Right in every row). Y_Lo .. Y_Hi: the rows of the outline.
   --  Area: twice the area that the outline encloses (positive: around a
   --  dark area). Not Closed: given up after eight steps for every pixel
   --  of the map.

   procedure Clear
     (Lefts      : in out Extent_Array;
      Rights     : in out Extent_Array;
      Y_Lo, Y_Hi : Natural)
   with Pre => Lefts'First = 0 and then Rights'First = 0
               and then Lefts'Last = Rights'Last
               and then Y_Hi <= Lefts'Last;
   --  No_Left and No_Right in the rows Y_Lo .. Y_Hi.

   ---------------------------------------------------------------------
   --  Hull
   ---------------------------------------------------------------------

   type Point is record
      X, Y : Integer := 0;
   end record;
   --  A corner of pixels: (X, Y) is the upper left corner of the pixel
   --  (X, Y).

   type Point_Array is array (Positive range <>) of Point;

   procedure Hull
     (Lefts      : Extent_Array;
      Rights     : Extent_Array;
      Y_Lo, Y_Hi : Natural;
      Points     : in out Point_Array;
      Count      : out Natural)
   with
     Pre  => Lefts'First = 0 and then Rights'First = 0
             and then Lefts'Last = Rights'Last
             and then Lefts'Last < Max_Side
             and then Y_Lo <= Y_Hi and then Y_Hi <= Lefts'Last
             and then Points'First = 1
             and then Points'Length >= 2 * (Y_Hi - Y_Lo + 2),
     Post => Count <= Points'Length;
   --  Points (1 .. Count): the corners of the convex hull of the pixels
   --  between Lefts and Rights in the rows Y_Lo .. Y_Hi, clockwise as
   --  the image is seen, from the upper right one. Count = 0: no row
   --  has a pixel.

end AMV.Kernels.Code_Reader.Dark_Areas;
