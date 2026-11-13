--  The checkerboard detector of AMV.Kernels.Calib_Fix (CogCalibCheckerboard
--  with its standard feature finder; our own method, from the public
--  literature on X-corner detection and checkerboard grid recovery).
--
--  1. Smoothing: the image is converted to floating point and smoothed
--     with a Gaussian of Sigma 1.5 pixels (AMV.Kernels.Image_Math).
--  2. Saddle response: at every pixel the negated determinant of the
--     Hessian of the smoothed image, Ixy**2 - Ixx * Iyy, from second
--     differences. Where four tiles meet the smoothed image is a saddle
--     (locally k x' y' in a frame along the tile edges), whose Hessian has
--     a determinant of -k**2 whatever the rotation; along a straight edge
--     the Hessian has rank one (response near 0), and at a blob it is
--     definite (response negative). The corner of a single tile (an
--     L-corner, where a tile meets a plain margin) responds as well; step
--     5 removes it.
--  3. Candidates: the pixels at least Margin pixels from the border whose
--     response is at least Relative_Threshold of the strongest response
--     (and at least Min_Response) and the largest within NMS_Radius
--     (ties go to the first in raster order).
--  4. Sub-pixel refinement: the corner is the point p that makes the
--     gradients g of the smoothed image within Window pixels orthogonal
--     to the offsets q - p in the least squares sense (along each edge
--     through the corner the gradient is normal to the edge): p solves
--     (sum g g^T) p = sum g g^T q, a 2 x 2 system, iterated up to three
--     times with the window moved to the nearest pixel of the estimate.
--     A candidate is dropped when the system is ill-conditioned (not two
--     strong gradient directions), when the estimate leaves the window,
--     and when it lies within 2 pixels of a corner kept before.
--  5. X-junction test, after the ring test of the ChESS detector (Bennett
--     and Lasenby, 2014): the smoothed image is sampled (bilinearly) at
--     Ring_Size points on a circle of Ring_Radius pixels about the corner.
--     With Mid the mean of the darkest and the lightest sample and the
--     contrast their difference, the corner is kept when the contrast is
--     at least Min_Contrast, the samples change between darker and lighter
--     than Mid exactly four times around the circle (four tiles of
--     alternating shade; an L-corner or an edge gives two changes, a blob
--     none), and opposite samples agree: the mean of |v (k) - v (k + 8)|
--     is at most Max_Asymmetry times the contrast (two lines through the
--     centre, not two parallel stripes or a corner next to a darker
--     background).
--  6. Grid: the corners grow into a grid from seeds, in the spirit of the
--     grid growing of Geiger et al. (2012) but with purely local
--     predictions, so that perspective and lens distortion do not stop
--     it.
--     a. Seed: the free corner nearest the image centre that has not been
--        tried yet. Its two edge lines come from the ring: the four points
--        where the samples cross Mid, interpolated along the ring, joined
--        in opposite pairs. The nearest free corner within 15 degrees of
--        either line gives the step U (the grid's I axis), the nearest
--        within 15 degrees of the other line the step V (the J axis); the
--        two steps must be at least 4 pixels long and 17.5 degrees apart.
--        The seed gets the grid indices (0, 0) once it passes the tile
--        test (d) with U and V, which also fixes the shade of the tile
--        (0, 0) between the corners (0, 0) and (1, 1).
--     b. Growth, breadth first: the corner at (I, J) predicts its
--        neighbour (I + 1, J) at its own position plus the local step,
--        which is p (I, J) - p (I - 1, J) when that corner is in the grid
--        (linear extrapolation), else p (I + 1, J +/- 1) - p (I, J +/- 1)
--        when those two are (the step of the adjacent row), else the step
--        it was found with; the other three neighbours alike. The free
--        corner nearest to the prediction within Search_Radius times the
--        shorter of the two local steps becomes a candidate for the
--        indices, which no other corner holds (a table of the grid's
--        indices keeps them unique).
--     c. The candidate joins the grid when it passes the tile test (d)
--        with the step that found it and the local step of the other axis.
--     d. Tile test: the four tile centres around the corner are sampled
--        at Cell_Fraction of each step along the diagonals; each must be
--        darker (or lighter) than the corner's Mid by Cell_Margin times its
--        contrast, as the alternating shades of the grid's tiles require
--        (tile (I, J) has the shade of tile (0, 0) when I + J is even);
--        and the four points Edge_Distance pixels from the corner along
--        the two steps, which lie on tile edges, must be within
--        Edge_Tolerance times the contrast of Mid.
--     e. A grid of fewer than Min_Corners corners gives its corners back;
--        a larger one keeps them. Seeds are tried until none is left,
--        Max_Seeds were tried, or the largest grid holds at least as many
--        corners as are free; the largest grid is the result.
--  7. Result: the grid axes are turned and flipped so that the I axis is
--     the step direction closest to the image's +x and the J axis the
--     other one, pointing to +y (for a grid that is not too skewed, the
--     image's handedness); the indices are shifted so that the corner
--     nearest the image centre is (0, 0); the corners are returned in rows
--     of increasing J, each of increasing I.
--
--  Limits: tiles of about 10 pixels or more (the windows and the ring
--  assume it) whose edges are not blurred over more than a few pixels;
--  corners less than about a third of a tile from the image border, or
--  whose tiles extend less than about a third of a tile (narrow border
--  tiles), are missed; the grid of the largest connected board in the
--  image is returned, with at most Max_Span steps from the seed along
--  each axis; at most Max_Corners corners (candidates beyond it are not
--  considered); image sides of at most 2**24 pixels (Bad_Parameter
--  otherwise). The positions are those of the image (the linear mode of
--  the calibration models no perspective and no lens distortion;
--  PerspectiveAndRadialWarp models both). The accuracy is tested
--  (on rendered boards about 0.05 pixel; up to about 0.1 pixel where
--  perspective skews the tiles strongly, since the window of step 4 is
--  not symmetric about a skewed junction that lies between pixels).
--
--  Proved: absence of run-time errors for any valid image; no memory
--  leaks; the corners returned number at least Min_Corners and at most
--  Max_Corners and lie inside the image, with grid indices within
--  Max_Grid_Index, in strictly increasing row-major order of their grid
--  indices (so no grid index is given twice).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.Calib_Fix.Checkerboard
  with SPARK_Mode, Preelaborate
is

   Sigma              : constant := 1.5;
   Window             : constant := 5;
   Margin             : constant := Window + 3;
   NMS_Radius         : constant := 4;
   Relative_Threshold : constant := 0.1;
   Min_Response       : constant := 1.0;

   Ring_Size     : constant := 16;
   Ring_Radius   : constant := 5.0;
   Min_Contrast  : constant := 10.0;
   Max_Asymmetry : constant := 0.15;

   Cell_Fraction  : constant := 0.3;
   Cell_Margin    : constant := 0.1;
   Edge_Distance  : constant := 5.0;
   Edge_Tolerance : constant := 0.3;
   Search_Radius  : constant := 0.35;
   Max_Seeds      : constant := 512;
   Max_Span       : constant := 255;

   function Row_Major_Less (A, B : Ks_Corner) return Boolean is
     (A.Grid_J < B.Grid_J
      or else (A.Grid_J = B.Grid_J and then A.Grid_I < B.Grid_I));
   --  A comes before B in rows of increasing J, each of increasing I.

   procedure Detect
     (Image   : access constant KI.Ks_Image_8_Grey_Data;
      Corners : out Corner_Array_Access;
      Count   : out Natural;
      Status  : out Ks_Status)
   with
     Pre  => KI.Valid_Image (Image),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Corners /= null
                            and then Count in Min_Corners .. Max_Corners
                            and then Corners'First = 0
                            and then Corners'Last = Count - 1
                            and then (for all K in Corners'Range
                                      => Corners (K).Pixel_X
                                           <= Long_Float (Image.Width - 1)
                                         and then Corners (K).Pixel_Y
                                                    <= Long_Float
                                                         (Image.Height - 1))
                            and then (for all K in 1 .. Count - 1
                                      => Row_Major_Less
                                           (Corners (K - 1), Corners (K)))
                       else Corners = null and then Count = 0);
   --  The corners of the checkerboard in Image, with their positions in
   --  pixel space and their grid indices, in strictly increasing row-major
   --  order of the indices. Bad_Parameter ("CalibrationImage: fewer than 9
   --  checkerboard corners were found") when the grid has fewer than
   --  Min_Corners corners; Out_Of_Memory.

end AMV.Kernels.Calib_Fix.Checkerboard;
