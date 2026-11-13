--  The ellipse fit of AMV.Kernels.Dimensioning.Fitting (CogFitEllipse):
--  the direct least squares fit of Fitzgibbon, Pilu and Fisher in the form
--  of Halir and Flusser, with an optional fixed rotation and the greedy
--  removal of NumToIgnore points. Internal: a precondition and a status
--  whose only failure is Bad_Parameter (with the message of the reason).
--
--  The method (public literature; our own implementation). The points in
--  use are moved to their centroid, turned by minus the rotation
--  constraint when there is one, and divided by their largest coordinate
--  offset, so that every moment of them up to the fourth order lies in
--  [-1, 1]. With D1 = (x**2, xy, y**2) and D2 = (x, y, 1) per point and
--  the scatter matrices S1 = mean D1 D1', S2 = mean D1 D2', S3 = mean
--  D2 D2', the coefficients a2 of D2 that fit best for given coefficients
--  a1 of D1 are T a1 with T = -inv (S3) S2', and the algebraic error left
--  is a1' M a1 with M = S1 + S2 T. The ellipse minimises it under 4AC -
--  B**2 = 1, a generalised eigenproblem M a1 = Lambda C1 a1 whose
--  constraint matrix C1 has the entries 2 at (1, 3) and (3, 1) and -1 at
--  (2, 2); exactly one eigenvalue is positive (0 for points exactly on an
--  ellipse) and it lies below (m11 + 2 m13 + m33) / 4, the Rayleigh
--  quotient of a1 = (1, 0, 1). It is found by bisection on det (M - Lambda
--  C1), which is positive below it and negative above, and the eigenvector
--  is the longest cross product of two rows of M - Lambda C1. With a fixed
--  rotation B = 0, M is 2 x 2 and the solution is (A, C) = (sqrt m22,
--  sqrt m11). The conic is then turned into a centre, radii and the angle
--  of the major axis, and scaled back.
--
--  Degenerate input gives Bad_Parameter: too few points in use (5, or 4
--  with the rotation constraint), coinciding points, (nearly) collinear
--  points (the determinant of S3 at most 1.0E-14 times the square of its
--  trace), no ellipse among the solutions (the best conic is a hyperbola
--  or a parabola, or has no real points), and an ellipse whose centre or
--  radii would be more than 2**30 times the extent of the points, or
--  beyond 1.0E150.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Geometry;

private package AMV.Kernels.Dimensioning.Fit_Ellipse
  with SPARK_Mode, Preelaborate
is

   package KG renames AMV.Kernels.Geometry;

   Max_Points : constant := 2**20;

   type Ellipse_Value is record
      Center_X : Long_Float := 0.0;
      Center_Y : Long_Float := 0.0;
      Radius_X : Long_Float := 1.0;
      Radius_Y : Long_Float := 1.0;
      Rotation : Long_Float := 0.0;
   end record;

   function Valid_Value (E : Ellipse_Value) return Boolean is
     (Bounded (E.Center_X) and then Bounded (E.Center_Y)
      and then E.Radius_X > 0.0 and then E.Radius_X <= Max_Value
      and then E.Radius_Y > 0.0 and then E.Radius_Y <= Max_Value
      and then Bounded (E.Rotation));
   --  An ellipse within the bounds, with radii > 0.

   procedure Fit
     (Points        : KG.Point_Array;
      Num_To_Ignore : Natural;
      Constrained   : Boolean;
      Rotation      : Long_Float;
      Result        : out Ellipse_Value;
      Used          : out KG.Flag_Array;
      Status        : out Ks_Status)
   with
     Pre  => Points'First = 0 and then Points'Last < Max_Points
             and then Used'First = 0 and then Used'Last = Points'Last
             and then Bounded (Rotation),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Value (Result)
                            and then (if Constrained
                                      then Result.Rotation = Rotation));
   --  Fits an ellipse to Points (coordinates are read limited to 1.0E150),
   --  leaving out Num_To_Ignore of them; Used tells the points the final
   --  fit used. With Constrained the ellipse's first axis has the
   --  direction Rotation (and Radius_X lies along it); otherwise Radius_X
   --  >= Radius_Y and Rotation, the direction of the major axis, lies in
   --  (-Pi/2, Pi/2].

end AMV.Kernels.Dimensioning.Fit_Ellipse;
