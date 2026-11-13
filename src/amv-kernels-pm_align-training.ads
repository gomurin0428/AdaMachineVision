--  The feature extraction of AMV.Kernels.PM_Align (Train): the edge
--  points of one pyramid level of the train image, moved to the peak of
--  the gradient along their normal, thinned to at most Max_Features (one
--  per cell of a grid) and
--  expressed in pattern coordinates.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.PM_Align.Masks;
with AMV.Kernels.PM_Align.Poses;
with AMV.Kernels.PM_Align.Pyramids;

private package AMV.Kernels.PM_Align.Training
  with SPARK_Mode, Preelaborate
is

   package MK renames AMV.Kernels.PM_Align.Masks;
   package P renames AMV.Kernels.PM_Align.Poses;
   package PY renames AMV.Kernels.PM_Align.Pyramids;

   procedure Extract
     (L                  : PY.Level_Data;
      Level              : Level_Index;
      Region             : access constant KR.Ks_Pixel_Region_Data;
      Area               : PY.Window;
      Care               : MK.Care_Map;
      Pattern_From_Pixel : KT.Ks_Transform_2D_Linear;
      Normals            : P.Unit_Linear;
      Model              : out Model_Level;
      Too_Far            : out Boolean)
   with Pre => PY.Usable (L) and then KT.Bounded (Pattern_From_Pixel)
               and then MK.Valid_Map (Care);
   --  The features of level Level (L) of a pyramid of Area: the edge
   --  pixels (PY.Is_Edge, at the train threshold of the level, see
   --  AMV.Kernels.PM_Align) that are not on the border of the level and
   --  whose centre lies in Region and that the mask's care map Care cares
   --  for (the threshold too is taken over those pixels only), each moved
   --  to the peak of the gradient
   --  projected on its unit gradient (a parabola through the projections
   --  one pixel before and after). They are thinned to one per occupied
   --  cell of a grid of Spacing x Spacing pixels (the cell's edge pixel of
   --  largest magnitude), Spacing the smallest size in 1 .. Max_Spacing
   --  that leaves at most Max_Features (the first Max_Features cells in
   --  raster order are kept when even Max_Spacing leaves more); every edge
   --  pixel is then within Spacing - 1 pixels, along x and along y, of a
   --  feature's pixel. Model.Spacing is that size. Positions are
   --  mapped from image pixels to pattern coordinates by
   --  Pattern_From_Pixel, normals by Normals (the normal map of its
   --  matrix). Too_Far is True when a position falls beyond
   --  Max_Pattern_Coordinate (Model then holds the features before it).

   procedure Extract_Ignored
     (L                  : PY.Level_Data;
      Level              : Level_Index;
      Region             : access constant KR.Ks_Pixel_Region_Data;
      Area               : PY.Window;
      Care               : MK.Care_Map;
      Pattern_From_Pixel : KT.Ks_Transform_2D_Linear;
      Model              : in out Model_Level)
   with Pre  => PY.Usable (L) and then KT.Bounded (Pattern_From_Pixel)
                and then MK.Valid_Map (Care),
        Post => Model.Count = Model.Count'Old
                and then Model.Spacing = Model.Spacing'Old
                and then Model.Features = Model.Features'Old;
   --  The cells of level Level (L) that the mask leaves out: the level is
   --  cut into cells of Spacing x Spacing pixels, Spacing the smallest
   --  size in 1 .. Max_Ignored_Spacing at which at most Max_Features cells
   --  hold a pixel whose centre lies in Region and that Care does not care
   --  for (the first Max_Features in raster order are kept when even
   --  Max_Ignored_Spacing leaves more); each such cell's centre, mapped to
   --  pattern coordinates as the features are, is an ignored point
   --  (Model.Ignored_Spacing is that size). A centre beyond
   --  Max_Pattern_Coordinate is left out. None without a mask.

end AMV.Kernels.PM_Align.Training;
