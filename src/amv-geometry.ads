--  Plane geometry and least squares fitting shared by the caliper-based
--  tools, the dimensioning tools and calibration. This package has no
--  VisionPro counterpart; tools wrap it with VisionPro-style interfaces.
--
--  All quantities are in whatever coordinate space the caller uses; angles
--  are radians. Degenerate input (too few points, coincident or collinear
--  points, negative radii, a Used array of the wrong shape) raises
--  Ks_Bad_Parameter_Exception with a message that starts with the name of
--  the subprogram at fault.
--
--  Bounds. Every coordinate and radius must be finite and within
--  +/-Max_Coordinate (1.0E150), and every rotation finite; otherwise the
--  subprogram raises Ks_Bad_Parameter_Exception naming the argument
--  ("Distance: P.X must be finite and within +/-1.0E150"; for a fit,
--  "Fit_Line: Points (3) must be ..."). Every coordinate, length and
--  radius returned is within that bound too, so that it is a valid
--  argument again: a result that would leave it (possible only for
--  arguments beyond about 3.5E149, or for nearly parallel lines meeting
--  far away) raises Ks_Bad_Parameter_Exception ("Distance: the result
--  would exceed +/-1.0E150").
--
--  Lengths (Distance and the lengths inside the fits) are computed without
--  intermediate overflow or underflow (as AMV.Misc.Hypot), and the fits
--  scale the offsets of the points from their centroid by an exact power
--  of two before forming squares and higher powers. The fits therefore
--  work the same for tiny and for huge coordinates (a fit of points
--  multiplied by a power of two gives the same result multiplied by that
--  power) anywhere within the bound.
--
--  The work is done by the SPARK kernel AMV.Kernels.Geometry (C API:
--  ks_geometry_*); this package only calls it. The point, line and circle
--  types are the kernel's C structs (ks_point_2d, ks_line_2d,
--  ks_circle_2d), so that point arrays reach the kernel without a copy.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Kernels.Geometry;

package AMV.Geometry is
   pragma Preelaborate;

   Max_Coordinate : constant := AMV.Kernels.Geometry.Max_Coordinate;
   --  1.0E150, the bound of coordinates, lengths and radii.

   subtype Point_2D is AMV.Kernels.Geometry.Ks_Point_2D;
   --  A record with components X, Y : Real (default 0.0).

   function "=" (Left, Right : Point_2D) return Boolean
     renames AMV.Kernels.Geometry."=";

   type Point_Array is new AMV.Kernels.Geometry.Point_Array;
   --  array (Natural range <>) of Point_2D.

   type Boolean_Array is new AMV.Kernels.Geometry.Flag_Array;
   --  array (Natural range <>) of Boolean.

   subtype Line_2D is AMV.Kernels.Geometry.Ks_Line_2D;
   --  A record with components X, Y (a point on the line) and Rotation (the
   --  direction of the line), all Real (default 0.0): the infinite line
   --  through (X, Y) with direction (cos R, sin R). Its left normal is
   --  (-sin R, cos R).

   function "=" (Left, Right : Line_2D) return Boolean
     renames AMV.Kernels.Geometry."=";

   subtype Circle_2D is AMV.Kernels.Geometry.Ks_Circle_2D;
   --  A record with components Center_X, Center_Y and Radius, all Real
   --  (default 0.0).

   function "=" (Left, Right : Circle_2D) return Boolean
     renames AMV.Kernels.Geometry."=";

   function Distance (P, Q : Point_2D) return Real;

   function Signed_Distance (P : Point_2D; Line : Line_2D) return Real;
   --  Positive when P lies on the side of the left normal. In a y-down
   --  image a line with Rotation 0 points to the right and its left normal
   --  points down, so points below it have positive distances. Reversing
   --  the line direction (adding Pi to Rotation) flips the sign.

   function Distance (P : Point_2D; Line : Line_2D) return Real;
   --  abs Signed_Distance.

   function Project (P : Point_2D; Line : Line_2D) return Point_2D;
   --  The foot of the perpendicular from P to Line.

   function Position_Along (P : Point_2D; Line : Line_2D) return Real;
   --  The signed coordinate of Project (P, Line) along the line direction,
   --  measured from (Line.X, Line.Y).

   function Distance (P : Point_2D; Circle : Circle_2D) return Real;
   --  abs (|P - centre| - radius).

   procedure Intersect
     (Line_1, Line_2 : Line_2D;
      Point          : out Point_2D;
      Parallel       : out Boolean);
   --  The intersection point; Parallel is True (and Point is (0, 0)) when
   --  the lines are parallel within a relative tolerance of 1.0E-12, that
   --  is when the sine of the angle between them is at most 1.0E-12 in
   --  magnitude. Anti-parallel and coincident lines count as parallel.

   procedure Intersect
     (Line         : Line_2D;
      Circle       : Circle_2D;
      Point_1      : out Point_2D;
      Point_2      : out Point_2D;
      Count        : out Natural);
   --  Count = 0, 1 (tangent; both points equal) or 2. Point_1 comes first
   --  along the line direction. The line counts as tangent when the
   --  distance from the centre to the line differs from the radius by at
   --  most 1.0E-9 * max (1, radius); the tangent point is then the foot of
   --  the perpendicular from the centre. Points that do not exist are
   --  (0, 0). Raises Ks_Bad_Parameter_Exception when the radius is
   --  negative. A circle of radius 0 behaves as a single point.

   procedure Intersect
     (Circle_1, Circle_2 : Circle_2D;
      Point_1            : out Point_2D;
      Point_2            : out Point_2D;
      Count              : out Natural);
   --  Count = 0, 1 (tangent; both points equal) or 2. Coincident circles
   --  give Count = 0, and so do concentric ones (centres closer than the
   --  tolerance below). With two points, Point_1 lies on the positive side
   --  (Signed_Distance > 0) of the line from centre 1 towards centre 2 and
   --  Point_2 on the negative side, so swapping the circles swaps the
   --  points. Contact (external or internal) counts as tangent when the
   --  centre distance matches the sum or the difference of the radii
   --  within 1.0E-9 * max (1, radius sum). Points that do not exist are
   --  (0, 0). Raises Ks_Bad_Parameter_Exception when a radius is negative.

   function Angle_Between (Line_1, Line_2 : Line_2D) return Real;
   --  Norm_Angle (Line_2.Rotation - Line_1.Rotation), in (-Pi, Pi] (each
   --  rotation reduced first when the difference would overflow, as
   --  AMV.Misc.Angle_Difference does).

   procedure Fit_Line
     (Points    : Point_Array;
      Line      : out Line_2D;
      RMS_Error : out Real);
   --  Orthogonal (total) least squares line. Line passes through the
   --  centroid; Line.Rotation is in (-Pi/2, Pi/2]. RMS_Error is the root
   --  mean square perpendicular distance. Raises Ks_Bad_Parameter_Exception
   --  for fewer than 2 points or when all points coincide (their RMS
   --  distance from the centroid is at most 1.0E-12 times the largest
   --  coordinate magnitude).
   --
   --  When the scatter is isotropic, so that every direction through the
   --  centroid fits equally well, Rotation is 0. Isotropic is judged up to
   --  rounding: with Sxx, Syy and Sxy the second moments about the
   --  centroid, the scatter counts as isotropic when
   --  |Sxx - Syy| + 2 |Sxy| (between 1 and Sqrt (2) times the difference
   --  of the two principal moments) is at most
   --  2**(-46) * (Sqrt (N) + M / Rho) * (Sxx + Syy), where N is the number
   --  of points, M the largest coordinate magnitude and Rho the RMS
   --  distance of the points from their centroid. Below that level the
   --  direction would be set by rounding alone: Sqrt (N) covers the
   --  rounding of the sums, and M / Rho the rounding of coordinates of
   --  magnitude M, which disturbs a scatter of radius Rho by about
   --  eps * M / Rho. For points near the origin the threshold is about
   --  1.0E-14 relative, so any real elongation is still resolved.

   procedure Fit_Line
     (Points        : Point_Array;
      Num_To_Ignore : Natural;
      Line          : out Line_2D;
      RMS_Error     : out Real;
      Used          : out Boolean_Array);
   --  Robust variant: discards Num_To_Ignore points one at a time, each
   --  time the point whose removal lowers the RMS error of the fit of the
   --  remaining points the most (leave-one-out: every point still in use
   --  is tried, so a single gross outlier is found even when it drags the
   --  fit of all points so far that good points have the largest
   --  residuals). Used (same index range as Points) tells which points
   --  the final fit used; RMS_Error is over the used points only.
   --  Num_To_Ignore = 0 gives the plain fit with every point used.
   --
   --  Removals whose results are equally good up to rounding (remaining
   --  sums of squared residuals within 1.0E-12 of the total scatter of the
   --  points in use, the sum of their squared distances from the
   --  centroid) count as ties: points are tried in index order and a later
   --  point is preferred only when it is better by more than that, so ties
   --  discard the lowest index first. A removal that would leave
   --  coinciding points is never chosen. Each step costs O(N): the effect
   --  of each removal on the fit is computed from updated sums.
   --
   --  The method is greedy, so outliers that mask one another can still
   --  defeat it: several identical (or clustered) outliers pull the fit of
   --  the remaining points towards themselves whichever one is removed,
   --  and good points may then be discarded instead.
   --
   --  At least 2 points must remain. Raises Ks_Bad_Parameter_Exception when
   --  Used'First /= Points'First or Used'Last /= Points'Last, when
   --  Num_To_Ignore leaves fewer than 2 points, and for the same
   --  degenerate input as the plain fit (checked on the points still in
   --  use before each removal and after the last).

   procedure Fit_Circle
     (Points    : Point_Array;
      Circle    : out Circle_2D;
      RMS_Error : out Real);
   --  Geometric least squares circle: an algebraic (Kasa) initial estimate
   --  refined on the radial residuals |P - centre| - radius. Each
   --  iteration takes the full Newton step (on the true Hessian of the sum
   --  of squared residuals) when that Hessian is positive definite, the
   --  step lowers the sum, and either the step is at least as long as the
   --  Gauss-Newton step or it is shorter than 1.0E-3 times the radius;
   --  otherwise it takes a Gauss-Newton step damped in the
   --  Levenberg-Marquardt manner. Newton gives quadratic convergence where
   --  Gauss-Newton alone would crawl (large residuals on a short arc); the
   --  length condition leaves Gauss-Newton in charge where the sum only
   --  flattens out towards infinity (nearly collinear points). The
   --  refinement stops when the centre moves by less than 1.0E-12 times
   --  the radius, no step lowers the cost, or 100 iterations have run (a
   --  safety net). If it stops on a saddle point (which exactly symmetric
   --  input can produce), it continues downhill from there. Unless the
   --  iteration cap ends it, the refinement ends at a local minimum of the
   --  sum of squared residuals, as closely as rounding in that sum can
   --  resolve. RMS_Error is the root mean square of |P - centre| - radius.
   --  Raises Ks_Bad_Parameter_Exception for fewer than 3 points, coincident
   --  points (as for Fit_Line), collinear points (the RMS scatter across
   --  the best line is at most 1.0E-8 times the RMS scatter along it; an
   --  arc flatter than that cannot be resolved in double precision), and
   --  points so close to collinear that the best circle lies at or near
   --  infinity (the centre runs off beyond 1.0E9 times the scatter along
   --  the line).

   procedure Fit_Circle
     (Points        : Point_Array;
      Num_To_Ignore : Natural;
      Circle        : out Circle_2D;
      RMS_Error     : out Real;
      Used          : out Boolean_Array);
   --  Robust variant, as for Fit_Line, with the residual
   --  Distance (P, Circle): each removal is judged by a full refit of the
   --  remaining points, so each step costs N circle fits. A removal is
   --  never chosen when the remaining points could not be fitted
   --  (collinear, coinciding, or with the best circle at infinity); when
   --  every removal fails that way, Ks_Bad_Parameter_Exception is raised.
   --  At least 3 points must remain.

end AMV.Geometry;
