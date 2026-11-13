--  The train image mask of AMV.Kernels.PM_Align (TrainImageMask): which
--  pixels of a pyramid level training may use.
--
--  A mask pixel of value 0 marks a train image pixel "don't care"; any
--  other value, and every pixel the mask does not cover, "care". Mask
--  pixel (U, V) covers train image pixel (U + Offset_X, V + Offset_Y).
--  A pixel (I, J) of pyramid level K is cared for when no don't-care pixel
--  lies within 2**K + 1 image pixels, along x and along y, of the image
--  pixel at its centre (the one PY.Level_Pixel_In_Region tests): that is
--  the pixel's own block and one pixel of the level around it (the Sobel
--  operator), plus one image pixel for the smoothing. The test counts the
--  don't-care pixels of the square in a summed-area table of the window,
--  built once per training.
--
--  The table's values are counts of pixels (at most 2**31), exact in a
--  Long_Float; every value read goes through a limit of 2**31 that never
--  acts (docs/PROOF.md).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Image_Math;
with AMV.Kernels.PM_Align.Pyramids;

private package AMV.Kernels.PM_Align.Masks
  with SPARK_Mode, Preelaborate
is

   package KM renames AMV.Kernels.Image_Math;
   package PY renames AMV.Kernels.PM_Align.Pyramids;

   use type KM.Ks_Real_Image;

   type Care_Map is record
      Counts : KM.Ks_Real_Image;
      Area   : PY.Window;
   end record;
   --  Counts null: no mask, every pixel is cared for. Otherwise the
   --  summed-area table of the window Area of the train image: Counts
   --  (Y, X) is the number of don't-care pixels among the window's pixels
   --  (0 .. X - 1, 0 .. Y - 1), for X in 0 .. Area.Width and Y in 0 ..
   --  Area.Height.

   function Valid_Map (Map : Care_Map) return Boolean is
     (Map.Counts = null
      or else (KM.Valid_Image (Map.Counts)
               and then Map.Area.Width >= 1 and then Map.Area.Height >= 1
               and then Int64 (Map.Counts.Width)
                          = Int64 (Map.Area.Width) + 1
               and then Int64 (Map.Counts.Height)
                          = Int64 (Map.Area.Height) + 1));

   procedure Build
     (Mask     : access constant KI.Ks_Image_8_Grey_Data;
      Offset_X : Int32;
      Offset_Y : Int32;
      Area     : PY.Window;
      Map      : out Care_Map;
      Status   : out Ks_Status)
   with
     Pre  => Area.Width >= 1 and then Area.Height >= 1
             and then Area.X_Min >= 0 and then Area.Y_Min >= 0
             and then (Mask = null or else KI.Valid_Image (Mask)),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then Valid_Map (Map)
             and then (if not Succeeded (Status) then Map.Counts = null);
   --  The care map of Area for Mask placed at (Offset_X, Offset_Y) (no
   --  table for a null mask). Bad_Parameter when the table would exceed
   --  KM.Max_Pixels ("TrainImageMask: the train window is too large for a
   --  mask"); Out_Of_Memory.

   function Cared
     (Map   : Care_Map;
      Level : Level_Index;
      I, J  : Natural) return Boolean
   with Pre => Valid_Map (Map);
   --  Pixel (I, J) of Level is cared for (see above; True without a
   --  table).

   procedure Release (Map : in out Care_Map)
   with Post => Map.Counts = null;
   --  Frees the table.

end AMV.Kernels.PM_Align.Masks;
