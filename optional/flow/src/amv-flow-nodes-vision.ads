pragma SPARK_Mode (Off);

--  Node kinds over AMV's vision tools. Each Create function returns a new
--  node of its kind (AMV.Flow.Kinds lists them by name).
--
--  ShapeMatch (AMV.Shape_Match)
--     in   Image : Image_8_Grey
--     out  Found : Boolean; Pose : Transform (pattern to the image's
--          selected space); X, Y, Angle (radians), Score : Real
--     params  TrainImage (a path, relative to the flow file),
--             TrainRegion (a region in the train image; none: all of it),
--             OriginX, OriginY, OriginRotation (the pattern's origin in
--             the train image), AngleLow, AngleHigh (the angle range
--             searched; equal: no rotation), AcceptThreshold,
--             ContrastThreshold
--             PatternPath (where the trained pattern is kept)
--     Trains when the flow is loaded (Prepare). With PatternPath, the
--     trained pattern is saved there with what it was trained from (the
--     train image file's name, size and time, the region, the origin) and
--     loaded instead of training again while those stay the same; without
--     a train image (or with one that is missing), the saved pattern is
--     used as it is, so a flow can be shipped with its pattern only. Not
--     found: Found is False, the other outputs have no value, the result
--     is Reject.
--
--  Fixture (AMV.Calib_Fix.Ks_Fixture_Tool)
--     in   Image : Image_8_Grey; Transform : Transform
--     out  Image : Image_8_Grey (the same pixels, with the fixtured space
--          added and selected)
--     params  FixturedSpaceName
--
--  Caliper (AMV.Caliper)
--     in   Image : Image_8_Grey
--     out  Found : Boolean; Width, Position, X, Y, Score : Real
--     params  Region (a RectangleAffine in the image's selected space;
--             side X is the search direction), EdgeMode (SingleEdge |
--             Pair), Edge0Polarity, Edge1Polarity (DarkToLight |
--             LightToDark | DontCare), Edge0Position, Edge1Position,
--             ContrastThreshold, FilterHalfSize
--     No edge found: Found is False, the result is Reject.
--
--  Blob (AMV.Blob)
--     in   Image : Image_8_Grey
--     out  Found : Boolean; Count : Integer; Area, CenterX, CenterY : Real
--          (of the largest blob)
--     params  Threshold (0 .. 255), Polarity (Light | Dark), MinArea,
--             Region (a region; none: the whole image)
--     Count counts the blobs (not holes) of at least MinArea pixels.
--
--  Circularity (AMV.Flow.Circularity)
--     in   Image : Image_8_Grey
--     out  Found, Clipped : Boolean; Pose : Transform (from the circle's
--          centre, axes along the pixels', to the image's selected space:
--          for a Fixture); Roundness (smallest / largest radius
--          about the fitted circle), Circularity (4 Pi area / perimeter
--          squared), Diameter, Radius, Area, Perimeter, CenterX, CenterY :
--          Real (pixels)
--     params  AutoThreshold (Otsu's), Threshold (0 .. 255), Polarity
--             (Light | Dark), MinArea
--     The outer edge of the largest object, found along 720 rays (the
--     editor draws it). Nothing found: Reject; an object touching the
--     image border: Warning (the circle is fitted to the edge inside the
--     image).

package AMV.Flow.Nodes.Vision is

   function Create_Shape_Match return Node_Access;
   function Create_Fixture return Node_Access;
   function Create_Caliper return Node_Access;
   function Create_Blob return Node_Access;
   function Create_Circularity return Node_Access;

end AMV.Flow.Nodes.Vision;
