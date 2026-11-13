--  The correlation of the CNL search (private to the kernel): the score
--  of a window (r**2 of the zero-mean normalised cross-correlation, see
--  AMV.Kernels.CNL_Search), the contrast, and the sub-pixel peak of a
--  3 x 3 neighbourhood of scores.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.CNL_Search.Levels;

private package AMV.Kernels.CNL_Search.Correlation
  with SPARK_Mode, Preelaborate
is

   package KL renames AMV.Kernels.CNL_Search.Levels;

   subtype Score_Value is Long_Float range 0.0 .. 1.0;

   Max_Cross : constant := 65025 * KL.Max_Pattern_Pixels;
   subtype Cross_Value is Int64 range 0 .. Max_Cross;

   function Cross_Sum
     (Image   : KL.Grey_8_Matrix;
      I_Geo   : Level_Geometry;
      X, Y    : Natural;
      Pattern : KL.Grey_8_Matrix;
      P_Geo   : Level_Geometry) return Cross_Value
   with
     Pre => KL.Indexed_From_Zero (Image)
            and then KL.Indexed_From_Zero (Pattern)
            and then KL.Stacked (I_Geo, KL.Rows_Of (Image),
                                 KL.Columns_Of (Image))
            and then KL.Stacked (P_Geo, KL.Rows_Of (Pattern),
                                 KL.Columns_Of (Pattern))
            and then P_Geo.Width <= Max_Pattern_Side
            and then P_Geo.Height <= Max_Pattern_Side
            and then P_Geo.Width <= I_Geo.Width
            and then X <= I_Geo.Width - P_Geo.Width
            and then P_Geo.Height <= I_Geo.Height
            and then Y <= I_Geo.Height - P_Geo.Height;
   --  Sum (p w) over the pattern level P_Geo and the window at (X, Y) of
   --  the image level I_Geo.

   function Score_Of
     (Count           : KL.Count_Value;
      Cross           : Cross_Value;
      Pattern_Sum     : KL.Grey_Sum;
      Pattern_Spread  : KL.Positive_Spread;
      Window_Sum      : KL.Grey_Sum;
      Window_Square   : KL.Square_Sum;
      Ignore_Polarity : Boolean) return Score_Value;
   --  The score from the sums: r**2 for r > 0 (or for r /= 0 with
   --  Ignore_Polarity), 0 otherwise and for a flat window.

   function Score_At
     (Plan            : KL.Valid_Search_Plan;
      Image           : KL.Grey_8_Matrix;
      Sums            : KL.Sum_Matrix;
      Pattern         : KL.Grey_8_Matrix;
      Care            : KL.Grey_8_Matrix;
      L               : Natural;
      Ignore_Polarity : Boolean;
      X, Y            : Natural) return Score_Value
   with
     Pre => KL.Matches (Plan, Image, Sums, Pattern, Care)
            and then L < Plan.Levels
            and then X <= KL.Last_X (Plan, L)
            and then Y <= KL.Last_Y (Plan, L);
   --  The score of the window at position (X, Y) of level L (see
   --  KL.Search_Plan for the positions). A window inside the level: with
   --  a Masked plan the sums are taken over the cared-for pixels of the
   --  pattern level (and the window's pixels at their positions), one
   --  window at a time; otherwise the window's sums come from the integral
   --  image. A partial window (one that crosses a side of the level): the
   --  sums are taken over the cared-for pixels of the pattern whose window
   --  pixel lies inside the level, N_in of them; 0 when 4 N_in is less
   --  than the pattern level's count N or when those pattern pixels are
   --  flat; multiplied by N_in / N when the plan Reduces.

   subtype Contrast_Value is Long_Float range 0.0 .. 2.0 ** 28;

   function Contrast_At
     (Plan    : KL.Valid_Search_Plan;
      Image   : KL.Grey_8_Matrix;
      Sums    : KL.Sum_Matrix;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      L       : Natural;
      X, Y    : Natural) return Contrast_Value
   with
     Pre => KL.Matches (Plan, Image, Sums, Pattern, Care)
            and then L < Plan.Levels
            and then X <= KL.Last_X (Plan, L)
            and then Y <= KL.Last_Y (Plan, L);
   --  The contrast of the window at position (X, Y) of level L: the
   --  square root of its spread over the pattern level's spread (0 for a
   --  flat window), over the cared-for pixels with a Masked plan, and over
   --  the clipped part of a partial window (0 where Score_At gives 0 for
   --  the pixels inside).

   subtype Offset is Long_Float range -1.0 .. 1.0;

   type Neighbourhood is array (-2 .. 2, -2 .. 2) of Score_Value;
   type Presence is array (-2 .. 2, -2 .. 2) of Boolean;
   --  The scores of a position and of the positions up to two away,
   --  indexed (DY, DX), and whether each is a position (of the search
   --  area extended by the partial match limits).

   procedure Peak_Offset
     (Scores   : Neighbourhood;
      Present  : Presence;
      Accuracy : Int32;
      OX, OY   : out Offset)
   with
     Post => (if not (Present (0, -1) and then Present (0, 1))
              then OX = 0.0)
             and then (if not (Present (-1, 0) and then Present (1, 0))
                       then OY = 0.0)
             and then (if Accuracy = Accuracy_Coarse
                       then OX = 0.0 and then OY = 0.0);
   --  The sub-pixel offset of the peak from the centre position (see
   --  AMV.Kernels.CNL_Search). VeryFine: the maximum of the quadratic
   --  surface fitted by least squares to the 3 x 3 scores around the
   --  position; when that maximum lies more than a quarter pixel away
   --  along an axis, the fit is made again with four samples along that
   --  axis, centred half a pixel toward the maximum (a 3 x 4, 4 x 3 or
   --  4 x 4 grid), so that the samples lie about the peak symmetrically.
   --  A surface without a maximum within one pixel, or samples that are
   --  not positions, leave the earlier estimate (for the first fit: the
   --  estimate of Fine). Fine: the vertex of the parabola through the
   --  three scores of each axis whose two neighbours are present (within
   --  half a pixel). Coarse: 0.

end AMV.Kernels.CNL_Search.Correlation;
