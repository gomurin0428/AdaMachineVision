--  The ellipse geometry of the dimensioning tools and of the ellipse fit:
--  the nearest point of an ellipse to a point, the distance between a
--  line or a segment and an ellipse, and their intersections. Internal,
--  as AMV.Kernels.Dimensioning.Planar (preconditions, no status, Fits
--  flags for result points beyond the bound).
--
--  Every computation moves the problem into the ellipse's own frame (its
--  centre at the origin, its first axis along x) and divides the lengths
--  involved by the largest of them, so that every intermediate value lies
--  within a few units whatever the size of the coordinates; the results
--  are scaled back at the end.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Dimensioning.Planar;

private package AMV.Kernels.Dimensioning.Ellipses
  with SPARK_Mode, Preelaborate
is

   package P renames AMV.Kernels.Dimensioning.Planar;

   use type P.Point;

   type Ellipse is record
      Center   : P.Point;
      Radius_X : P.Radius_Value := 1.0;
      Radius_Y : P.Radius_Value := 1.0;
      C        : P.Unit := 1.0;
      S        : P.Unit := 0.0;
   end record;
   --  The ellipse with semi-axis Radius_X along the direction (C, S) (the
   --  cosine and sine of its rotation) and Radius_Y across it.

   function Valid_Ellipse (E : Ellipse) return Boolean is
     (E.Radius_X > 0.0 and then E.Radius_Y > 0.0);

   procedure Point_Ellipse
     (Q    : P.Point;
      E    : Ellipse;
      D    : out P.Signed_Length;
      Near : out P.Point;
      Fits : out Boolean)
   with Pre  => Valid_Ellipse (E),
        Post => (if not Fits then Near = P.Origin);
   --  The signed distance from Q to the ellipse (negative inside) and the
   --  nearest point of the ellipse (Q itself when D = 0; the point at the
   --  rotation's angle, with D = +Radius_X, for the centre of an ellipse
   --  whose radii are equal). D is computed even when Near does not fit.

   procedure Line_Ellipse
     (L      : P.Line;
      E      : Ellipse;
      D      : out P.Length;
      QL, QE : out P.Point;
      Fits   : out Boolean)
   with Pre  => Valid_Ellipse (E),
        Post => (if D = 0.0 then QL = P.Origin and then QE = P.Origin);
   --  The gap between the line and the ellipse (0 when they meet), the
   --  point of the line and the point of the ellipse that face each other.

   type Two_Points is record
      Count  : Int32 range 0 .. 2 := 0;
      P1, P2 : P.Point;
   end record;

   function Valid_Two_Points (T : Two_Points) return Boolean is
     ((if T.Count < 1 then T.P1 = P.Origin)
      and then (if T.Count < 2 then T.P2 = P.Origin));

   procedure Intersect_Line_Ellipse
     (L      : P.Line;
      E      : Ellipse;
      Result : out Two_Points;
      Fits   : out Boolean)
   with Pre  => Valid_Ellipse (E),
        Post => Valid_Two_Points (Result)
                and then (if not Fits then Result.Count = 0);
   --  The points where the line meets the ellipse, in the order of the
   --  line's direction (one point when it is tangent).

   procedure Intersect_Segment_Ellipse
     (S      : P.Segment;
      E      : Ellipse;
      Result : out Two_Points;
      Fits   : out Boolean)
   with Pre  => Valid_Ellipse (E),
        Post => Valid_Two_Points (Result)
                and then (if not Fits then Result.Count = 0);
   --  The points of Intersect_Line_Ellipse for the segment's line that
   --  lie on the segment, from its start to its end; a segment of no
   --  length is a point.

   procedure Segment_Ellipse
     (S      : P.Segment;
      E      : Ellipse;
      D      : out P.Signed_Length;
      QS, QE : out P.Point;
      Fits   : out Boolean)
   with Pre  => Valid_Ellipse (E),
        Post => (if D = 0.0 then QS = P.Origin and then QE = P.Origin);
   --  The signed distance between the segment and the ellipse and the two
   --  points (see ks_distance_segment_ellipse_execute).

end AMV.Kernels.Dimensioning.Ellipses;
