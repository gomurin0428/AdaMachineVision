pragma SPARK_Mode (Off);

--  Node kinds that measure: a circle found by calipers, the distance
--  between two points, grey statistics. Each Create function returns a new
--  node of its kind (AMV.Flow.Kinds lists them by name).
--
--  FindCircle (AMV.Caliper.Find_Circle)
--     in   Image : Image_8_Grey
--     out  Found : Boolean; Pose : Transform (to the circle's centre, in
--          the image's selected space: for a Fixture); CenterX, CenterY,
--          Radius, Diameter, RMSError : Real; PointsUsed : Integer
--     params  Expected (a Circle in the image's selected space: where the
--             calipers go, all round), NumCalipers, SearchLength,
--             ProjectionLength, SearchDirection (Inward | Outward),
--             Polarity (DarkToLight | LightToDark | DontCare: the edge
--             going along the search direction), ContrastThreshold,
--             NumToIgnore (outliers left out of the fit)
--     Too few edges for a fit: Found is False, the result is Reject. The
--     editor draws the circle found and its centre.
--
--  Distance (AMV.Dimensioning.Ks_Distance_Point_Point_Tool)
--     in   X1, Y1, X2, Y2 : Real
--     out  Distance : Real; Angle : Real (of the segment from point 1 to
--          point 2, radians, in (-Pi, Pi])
--
--  Histogram (AMV.Image_Processing.Histogram)
--     in   Image : Image_8_Grey
--     out  Mean, StdDev : Real; Minimum, Maximum, Median, Samples,
--          Threshold : Integer (Threshold: Otsu's, between the dark and
--          the light samples)
--     params  Region (a region in the image's selected space; none: the
--             whole image)
--     A region that covers no pixel: Reject, no outputs.

package AMV.Flow.Nodes.Measure is

   function Create_Find_Circle return Node_Access;
   function Create_Distance return Node_Access;
   function Create_Histogram return Node_Access;

end AMV.Flow.Nodes.Measure;
