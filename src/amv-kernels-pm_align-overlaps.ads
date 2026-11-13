--  The overlap of two results of AMV.Kernels.PM_Align (XYOverlap): the
--  area two convex quadrilaterals share, as a fraction of the smaller.
--
--  The method: Sutherland and Hodgman's polygon clipping (CACM 1974) of
--  the first quadrilateral by the half-planes of the second's edges, then
--  the shoelace formula for the areas. Coordinates are level-0 pixel
--  positions (within 2**34 in practice); every point a clip makes lies on
--  a segment between two points within the bound, and goes through a
--  limit of Max_Coordinate that never acts.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.PM_Align.Overlaps
  with SPARK_Mode, Preelaborate
is

   Max_Coordinate : constant := 2.0 ** 40;

   subtype Coordinate is Long_Float range -Max_Coordinate .. Max_Coordinate;

   type Point is record
      X, Y : Coordinate := 0.0;
   end record;

   type Quad is array (0 .. 3) of Point;
   --  A convex quadrilateral, its corners in order around it (either
   --  way round).

   function Overlap_Fraction (A, B : Quad) return Long_Float
   with Post => Overlap_Fraction'Result >= 0.0
                and then Overlap_Fraction'Result <= 1.0;
   --  The area of the intersection of A and B over the smaller of their
   --  areas, limited to [0, 1]; 0 when either area is below 1.0E-6.

end AMV.Kernels.PM_Align.Overlaps;
