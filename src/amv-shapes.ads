--  Shapes and regions: the counterparts of ICogShape, ICogRegion and the
--  CogRectangle, CogRectangleAffine, CogCircle, CogEllipse, CogPolygon,
--  CogCircularAnnulusSection, CogLine, CogLineSegment, CogPointMarker and
--  CogCircularArc classes. Only geometry is modelled (no graphics
--  properties).
--
--  Every shape has a Selected_Space_Name, "." by default, naming the
--  coordinate space of its coordinates (see docs/DESIGN.md section 5). All
--  angles are radians. Lengths are in the units of the selected space.
--
--  A region decides which points belong to it with Contains_Point; a point
--  on the boundary counts as inside. A tool converts a region into a set of
--  image pixels with AMV.Regions.
--
--  The geometry is computed by the SPARK kernel AMV.Kernels.Shapes (the C
--  functions ks_rectangle_*, ks_circle_*, ..., ks_polygon_*), which bounds
--  every value so that nothing can overflow:
--
--  * every coordinate and angle a shape holds or an operation takes must
--    be finite and within [-1.0E150, 1.0E150], every length (Width,
--    Height, a side length, a radius, a segment's Length, a line's
--    distance from the origin) within [0, 4.0E150], a Radial_Scale within
--    [0, 1.0E150] and Radius * Radial_Scale within 4.0E150; otherwise the
--    operation raises Ks_Bad_Parameter_Exception naming the property. A
--    NaN or infinite argument is rejected the same way (the checks
--    documented below, such as "Radius must be >= 0", come first for a
--    negative finite value);
--  * a result that would leave those bounds (a centre, a corner, a
--    bounding box, an end point, a mapped shape) raises
--    Ks_Bad_Parameter_Exception as well, so every shape and point an
--    operation returns is a valid argument again. Transforms passed to
--    Map are bounded as in AMV.Transforms;
--  * a polygon has at most 2**20 (1048576) vertices.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Transforms;

private with Ada.Finalization;
private with Ada.Streams;
private with Ada.Strings.Unbounded;
private with AMV.Kernels.Shapes;

package AMV.Shapes is
   pragma Preelaborate;

   ---------------------------------------------------------------------
   --  ICogShape
   ---------------------------------------------------------------------

   type Ks_Shape is abstract tagged private;

   function Selected_Space_Name (Shape : Ks_Shape) return String;
   procedure Set_Selected_Space_Name
     (Shape : in out Ks_Shape; Space_Name : String);

   function Map
     (Shape     : Ks_Shape;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class is abstract;
   --  The shape with every point mapped by Transform. The result may be of
   --  a different type when the original type cannot represent the mapped
   --  shape (a rectangle under rotation becomes a CogRectangleAffine, a
   --  circle under a non-similarity becomes a CogEllipse). The selected
   --  space name is copied unchanged. Shapes that cannot represent the
   --  mapped geometry at all raise Ks_Bad_Parameter_Exception (see each
   --  type).

   ---------------------------------------------------------------------
   --  ICogRegion
   ---------------------------------------------------------------------

   type Ks_Region is abstract new Ks_Shape with private;

   function Contains_Point
     (Region : Ks_Region; X, Y : Real) return Boolean is abstract;
   --  True when (X, Y), in the region's selected space, is inside the
   --  region or on its boundary.
   --
   --  So that points computed to lie exactly on the boundary still count
   --  as inside despite rounding, the boundary is widened by a slack of
   --
   --     1.0E-9 * L + 64.0 * Real'Model_Epsilon * (P + L)
   --
   --  selected-space units, where L is the region's own size and P the
   --  magnitude of its position:
   --
   --     rectangle         L = Width + Height,  P = |X| + |Y|
   --     affine rectangle  L = Side_X_Length + Side_Y_Length,
   --                       P = |Center_X| + |Center_Y|
   --     circle            L = Radius,          P = |Center_X| + |Center_Y|
   --     ellipse           L = Radius_X + Radius_Y,
   --                       P = |Center_X| + |Center_Y|
   --     annulus section   L = the larger radius,
   --                       P = |Center_X| + |Center_Y|
   --     polygon           L = width + height of the bounding box,
   --                       P = the largest absolute coordinate of that box
   --
   --  The first term is a fixed fraction of the region's size, so it does
   --  not depend on the unit of the space. The second (about
   --  1.4E-14 * (P + L)) covers the rounding of coordinates of that
   --  magnitude: a region far from the origin is widened by a few dozen
   --  units in the last place of its coordinates only (a circle of radius
   --  12 centred near y = 1.0E9 by about 1.4E-5, not by a whole unit).
   --  Degenerate regions (zero lengths or radii, collinear sides) contain
   --  the points of the segment or point they reduce to.

   function Boundary_Slack (Region : Ks_Region) return Real is abstract;
   --  How far, along either axis, a point that Contains_Point accepts can
   --  lie outside the region's bounding box (see Get_Bounding_Box), in
   --  selected-space units: every accepted point (X, Y) satisfies
   --  Min_X - S <= X <= Max_X + S and Min_Y - S <= Y <= Max_Y + S with
   --  S = Boundary_Slack (Region). S is the slack described above for a
   --  rectangle, circle, ellipse or polygon, twice it for an affine
   --  rectangle (its widened sides meet up to sqrt 2 times the slack
   --  beyond a corner) and three times it for an annulus section (where
   --  the angular slack adds to the radial one). AMV.Regions uses it to
   --  choose the pixels it tests. An AMV addition with no VisionPro
   --  counterpart.

   procedure Get_Bounding_Box
     (Region                 : Ks_Region;
      Min_X, Min_Y, Max_X, Max_Y : out Real) is abstract;
   --  The smallest axis-aligned box (in the selected space) that contains
   --  the region. An AMV primitive; Enclosing_Rectangle (after
   --  Ks_Rectangle below) returns the same box as a rectangle.

   function Area (Region : Ks_Region) return Real is abstract;
   --  The region's area in squared selected-space units. For every region
   --  type it is the area of the set of points Contains_Point accepts
   --  (without the boundary slack), with one exception: for a Ks_Polygon
   --  whose boundary crosses or retraces itself, Area is the net
   --  (signed shoelace) area instead; see Ks_Polygon.Area.

   ---------------------------------------------------------------------
   --  CogRectangle: axis-aligned, X/Y is the corner with the smallest
   --  coordinates.
   ---------------------------------------------------------------------

   type Ks_Rectangle is new Ks_Region with private;
   --  Default: X = 0, Y = 0, Width = 100, Height = 100.

   function X (Rectangle : Ks_Rectangle) return Real;
   function Y (Rectangle : Ks_Rectangle) return Real;
   function Width (Rectangle : Ks_Rectangle) return Real;
   function Height (Rectangle : Ks_Rectangle) return Real;
   function Center_X (Rectangle : Ks_Rectangle) return Real;
   function Center_Y (Rectangle : Ks_Rectangle) return Real;

   procedure Set_X (Rectangle : in out Ks_Rectangle; Value : Real);
   procedure Set_Y (Rectangle : in out Ks_Rectangle; Value : Real);
   procedure Set_Width (Rectangle : in out Ks_Rectangle; Value : Real);
   procedure Set_Height (Rectangle : in out Ks_Rectangle; Value : Real);
   --  Width and Height must be >= 0 (Ks_Bad_Parameter_Exception).

   procedure Set_XY_Width_Height
     (Rectangle : in out Ks_Rectangle; X, Y, Width, Height : Real);
   --  SetXYWidthHeight.

   procedure Get_XY_Width_Height
     (Rectangle : Ks_Rectangle; X, Y, Width, Height : out Real);
   --  GetXYWidthHeight.

   procedure Set_Center_Width_Height
     (Rectangle : in out Ks_Rectangle;
      Center_X, Center_Y, Width, Height : Real);
   --  SetCenterWidthHeight: X = Center_X - Width / 2, Y = Center_Y -
   --  Height / 2.

   procedure Get_Center_Width_Height
     (Rectangle : Ks_Rectangle;
      Center_X, Center_Y, Width, Height : out Real);
   --  GetCenterWidthHeight: Center_X and Center_Y as the functions of that
   --  name return them.

   overriding function Map
     (Shape     : Ks_Rectangle;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class;
   --  Ks_Rectangle when Transform.Is_Axis_Aligned: the image of two
   --  opposite corners, normalised so that X/Y is again the corner with
   --  the smallest coordinates and Width/Height are >= 0 (a reflection
   --  or negative scale swaps the corners). Otherwise a
   --  Ks_Rectangle_Affine whose corner origin, Corner_X and Corner_Y are
   --  the images of (X, Y), (X + Width, Y) and (X, Y + Height).

   overriding function Contains_Point
     (Region : Ks_Rectangle; X, Y : Real) return Boolean;
   overriding function Boundary_Slack (Region : Ks_Rectangle) return Real;
   overriding procedure Get_Bounding_Box
     (Region                 : Ks_Rectangle;
      Min_X, Min_Y, Max_X, Max_Y : out Real);
   overriding function Area (Region : Ks_Rectangle) return Real;

   function Perimeter (Rectangle : Ks_Rectangle) return Real;
   --  2 * (Width + Height).

   function Enclosing_Rectangle (Region : Ks_Region'Class) return Ks_Rectangle;
   --  EnclosingRectangle: the bounding box of Region (Get_Bounding_Box)
   --  as a Ks_Rectangle with X = Min_X, Y = Min_Y, Width = Max_X - Min_X
   --  and Height = Max_Y - Min_Y, in Region's selected space (the result
   --  gets Region's Selected_Space_Name). For a Ks_Rectangle that is the
   --  same X and Y, and the same Width and Height up to the rounding of
   --  (X + Width) - X and (Y + Height) - Y. Declared for regions only,
   --  which have a bounding box in AMV (VisionPro offers it on every
   --  shape); VisionPro's copyFlags argument has no counterpart, since AMV
   --  shapes have no graphics properties. It is class-wide rather than a
   --  primitive of Ks_Region, which would have to be declared before
   --  Ks_Rectangle; the prefix notation Region.Enclosing_Rectangle works
   --  all the same.

   ---------------------------------------------------------------------
   --  CogRectangleAffine: a parallelogram.
   --
   --  Side X runs from the corner origin in direction Rotation; side Y runs
   --  from the corner origin in direction Rotation + Skew + Pi/2:
   --
   --     DirX = (cos R, sin R)       DirY = (-sin (R + K), cos (R + K))
   --     Corner_X        = Origin + Side_X_Length * DirX
   --     Corner_Y        = Origin + Side_Y_Length * DirY
   --     Corner_Opposite = Origin + Side_X_Length * DirX
   --                              + Side_Y_Length * DirY
   --     Center          = (Origin + Corner_Opposite) / 2
   ---------------------------------------------------------------------

   type Ks_Rectangle_Affine is new Ks_Region with private;
   --  Default: centre (50, 50), side lengths 100 x 100, rotation 0,
   --  skew 0.

   function Center_X (Rectangle : Ks_Rectangle_Affine) return Real;
   function Center_Y (Rectangle : Ks_Rectangle_Affine) return Real;
   function Side_X_Length (Rectangle : Ks_Rectangle_Affine) return Real;
   function Side_Y_Length (Rectangle : Ks_Rectangle_Affine) return Real;
   function Rotation (Rectangle : Ks_Rectangle_Affine) return Real;
   function Skew (Rectangle : Ks_Rectangle_Affine) return Real;

   procedure Set_Center_X
     (Rectangle : in out Ks_Rectangle_Affine; Value : Real);
   procedure Set_Center_Y
     (Rectangle : in out Ks_Rectangle_Affine; Value : Real);
   procedure Set_Side_X_Length
     (Rectangle : in out Ks_Rectangle_Affine; Value : Real);
   procedure Set_Side_Y_Length
     (Rectangle : in out Ks_Rectangle_Affine; Value : Real);
   procedure Set_Rotation
     (Rectangle : in out Ks_Rectangle_Affine; Value : Real);
   procedure Set_Skew (Rectangle : in out Ks_Rectangle_Affine; Value : Real);
   --  Side lengths must be >= 0 (Ks_Bad_Parameter_Exception). Changing one
   --  property keeps the centre and the other properties.

   function Corner_Origin_X (Rectangle : Ks_Rectangle_Affine) return Real;
   function Corner_Origin_Y (Rectangle : Ks_Rectangle_Affine) return Real;
   function Corner_X_X (Rectangle : Ks_Rectangle_Affine) return Real;
   function Corner_X_Y (Rectangle : Ks_Rectangle_Affine) return Real;
   function Corner_Y_X (Rectangle : Ks_Rectangle_Affine) return Real;
   function Corner_Y_Y (Rectangle : Ks_Rectangle_Affine) return Real;
   function Corner_Opposite_X (Rectangle : Ks_Rectangle_Affine) return Real;
   function Corner_Opposite_Y (Rectangle : Ks_Rectangle_Affine) return Real;

   procedure Set_Center_Lengths_Rotation_Skew
     (Rectangle : in out Ks_Rectangle_Affine;
      Center_X, Center_Y, Side_X_Length, Side_Y_Length, Rotation, Skew : Real);

   procedure Get_Center_Lengths_Rotation_Skew
     (Rectangle : Ks_Rectangle_Affine;
      Center_X, Center_Y, Side_X_Length, Side_Y_Length, Rotation, Skew :
        out Real);

   procedure Set_Origin_Lengths_Rotation_Skew
     (Rectangle : in out Ks_Rectangle_Affine;
      Origin_X, Origin_Y, Side_X_Length, Side_Y_Length, Rotation, Skew : Real);

   procedure Get_Origin_Lengths_Rotation_Skew
     (Rectangle : Ks_Rectangle_Affine;
      Origin_X, Origin_Y, Side_X_Length, Side_Y_Length, Rotation, Skew :
        out Real);
   --  Origin_X and Origin_Y are Corner_Origin_X and Corner_Origin_Y.

   procedure Set_Origin_Corner_X_Corner_Y
     (Rectangle : in out Ks_Rectangle_Affine;
      Origin_X, Origin_Y, Corner_X_X, Corner_X_Y,
      Corner_Y_X, Corner_Y_Y : Real);
   --  Defines the parallelogram by three corners. Degenerate (collinear)
   --  corners are allowed and give side lengths / skew accordingly.

   procedure Get_Origin_Corner_X_Corner_Y
     (Rectangle : Ks_Rectangle_Affine;
      Origin_X, Origin_Y, Corner_X_X, Corner_X_Y,
      Corner_Y_X, Corner_Y_Y : out Real);
   --  The three corners, as the Corner_* functions return them.

   function Get_Parent_From_Child_Transform
     (Rectangle : Ks_Rectangle_Affine)
      return AMV.Transforms.Ks_Transform_2D_Linear;
   --  Maps the rectangle's own frame into its selected space: child (0, 0)
   --  is the corner origin, child (Side_X_Length, 0) is Corner_X and child
   --  (0, Side_Y_Length) is Corner_Y. So child x runs along side X and
   --  child y along side Y, both in selected-space units.

   overriding function Map
     (Shape     : Ks_Rectangle_Affine;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class;
   --  Always a Ks_Rectangle_Affine (the three corners are mapped and
   --  passed to Set_Origin_Corner_X_Corner_Y).

   overriding function Contains_Point
     (Region : Ks_Rectangle_Affine; X, Y : Real) return Boolean;
   --  A point is inside when its child coordinates (u, v), see
   --  Get_Parent_From_Child_Transform, satisfy 0 <= u <= Side_X_Length
   --  and 0 <= v <= Side_Y_Length. A degenerate parallelogram (a zero
   --  side length, or sides that are collinear so that the transform is
   --  singular) contains the points of the segment or point it reduces
   --  to.
   overriding function Boundary_Slack
     (Region : Ks_Rectangle_Affine) return Real;
   overriding procedure Get_Bounding_Box
     (Region                 : Ks_Rectangle_Affine;
      Min_X, Min_Y, Max_X, Max_Y : out Real);
   overriding function Area (Region : Ks_Rectangle_Affine) return Real;

   ---------------------------------------------------------------------
   --  CogCircle
   ---------------------------------------------------------------------

   type Ks_Circle is new Ks_Region with private;
   --  Default: centre (0, 0), radius 50.

   function Center_X (Circle : Ks_Circle) return Real;
   function Center_Y (Circle : Ks_Circle) return Real;
   function Radius (Circle : Ks_Circle) return Real;

   procedure Set_Center_X (Circle : in out Ks_Circle; Value : Real);
   procedure Set_Center_Y (Circle : in out Ks_Circle; Value : Real);
   procedure Set_Radius (Circle : in out Ks_Circle; Value : Real);
   --  Radius must be >= 0 (Ks_Bad_Parameter_Exception).

   procedure Set_Center_Radius
     (Circle : in out Ks_Circle; Center_X, Center_Y, Radius : Real);

   procedure Get_Center_Radius
     (Circle : Ks_Circle; Center_X, Center_Y, Radius : out Real);

   overriding function Map
     (Shape     : Ks_Circle;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class;
   --  Ks_Circle when Transform is a similarity: a rotation and uniform
   --  scaling, possibly combined with a reflection (Is_Similarity of the
   --  transform or of the transform composed with a mirror). The centre
   --  is mapped and the radius is multiplied by the scale of the
   --  similarity, taken as the length of its first matrix column,
   --  sqrt (A**2 + C**2) (the image of a unit step along x), computed
   --  without intermediate overflow or underflow (AMV.Misc.Hypot), so any
   --  representable result is obtained. For an exact similarity that
   --  length equals sqrt (abs Matrix_Determinant); for a transform that is
   --  a similarity only within the relative tolerance of the
   --  classification (1.0E-9) the two may differ by about that relative
   --  amount.
   --  Otherwise the Ks_Ellipse that is the image of the circle (see
   --  Ks_Ellipse.Map).

   overriding function Contains_Point
     (Region : Ks_Circle; X, Y : Real) return Boolean;
   overriding function Boundary_Slack (Region : Ks_Circle) return Real;
   overriding procedure Get_Bounding_Box
     (Region                 : Ks_Circle;
      Min_X, Min_Y, Max_X, Max_Y : out Real);
   overriding function Area (Region : Ks_Circle) return Real;

   ---------------------------------------------------------------------
   --  CogEllipse: semi-axis Radius_X along direction Rotation, semi-axis
   --  Radius_Y perpendicular to it.
   ---------------------------------------------------------------------

   type Ks_Ellipse is new Ks_Region with private;
   --  Default: centre (0, 0), radii 50 x 25, rotation 0.

   function Center_X (Ellipse : Ks_Ellipse) return Real;
   function Center_Y (Ellipse : Ks_Ellipse) return Real;
   function Radius_X (Ellipse : Ks_Ellipse) return Real;
   function Radius_Y (Ellipse : Ks_Ellipse) return Real;
   function Rotation (Ellipse : Ks_Ellipse) return Real;

   procedure Set_Center_X (Ellipse : in out Ks_Ellipse; Value : Real);
   procedure Set_Center_Y (Ellipse : in out Ks_Ellipse; Value : Real);
   procedure Set_Radius_X (Ellipse : in out Ks_Ellipse; Value : Real);
   procedure Set_Radius_Y (Ellipse : in out Ks_Ellipse; Value : Real);
   procedure Set_Rotation (Ellipse : in out Ks_Ellipse; Value : Real);
   --  Radii must be >= 0 (Ks_Bad_Parameter_Exception).

   procedure Set_Center_XY_Radius_XY_Rotation
     (Ellipse : in out Ks_Ellipse;
      Center_X, Center_Y, Radius_X, Radius_Y, Rotation : Real);
   --  SetCenterXYRadiusXYRotation: sets all five properties; both radii
   --  must be >= 0 (Ks_Bad_Parameter_Exception, Ellipse unchanged).

   procedure Get_Center_XY_Radius_XY_Rotation
     (Ellipse : Ks_Ellipse;
      Center_X, Center_Y, Radius_X, Radius_Y, Rotation : out Real);
   --  GetCenterXYRadiusXYRotation: the five properties, as the individual
   --  getters return them.

   overriding function Map
     (Shape     : Ks_Ellipse;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class;
   --  Always a Ks_Ellipse (the image of an ellipse under an affine map).
   --  The images of two conjugate semi-axes give the shape of the result;
   --  its radii and rotation come from the eigen-decomposition of that
   --  2x2 shape matrix. Of the equivalent parametrisations (rotation
   --  changed by multiples of Pi/2, swapping the radii for odd ones) the
   --  one whose Radius_X axis is nearest to the mapped original Radius_X
   --  direction is chosen, so translations, rotations and axis scalings
   --  keep Radius_X on the same axis. A singular transform flattens the
   --  result: Radius_Y becomes 0 up to rounding (both radii for a zero
   --  matrix).

   overriding function Contains_Point
     (Region : Ks_Ellipse; X, Y : Real) return Boolean;
   overriding function Boundary_Slack (Region : Ks_Ellipse) return Real;
   overriding procedure Get_Bounding_Box
     (Region                 : Ks_Ellipse;
      Min_X, Min_Y, Max_X, Max_Y : out Real);
   overriding function Area (Region : Ks_Ellipse) return Real;

   ---------------------------------------------------------------------
   --  CogPolygon: a closed polygon; inside is decided by the even-odd
   --  rule. A polygon with fewer than 3 vertices contains only points on
   --  its edges.
   ---------------------------------------------------------------------

   type Ks_Polygon is new Ks_Region with private;
   --  Default: no vertices.

   function Num_Vertices (Polygon : Ks_Polygon) return Natural;
   function Get_Vertex_X (Polygon : Ks_Polygon; Index : Natural) return Real;
   function Get_Vertex_Y (Polygon : Ks_Polygon; Index : Natural) return Real;
   --  Index is 0-based; Constraint_Error when Index >= Num_Vertices.

   procedure Get_Vertex
     (Polygon : Ks_Polygon; Index : Natural; X, Y : out Real);
   --  GetVertex: both coordinates of vertex Index (Constraint_Error as
   --  above).

   procedure Set_Vertex
     (Polygon : in out Ks_Polygon; Index : Natural; X, Y : Real);
   --  Replaces vertex Index; Constraint_Error when Index >= Num_Vertices.

   procedure Add_Vertex
     (Polygon : in out Ks_Polygon; X, Y : Real; Index : Integer := -1);
   --  Inserts the vertex before position Index; -1 appends.
   --  Constraint_Error when Index > Num_Vertices or Index < -1;
   --  Ks_Bad_Parameter_Exception when the polygon already has 2**20
   --  vertices.

   procedure Remove_Vertex (Polygon : in out Ks_Polygon; Index : Natural);
   --  Deletes vertex Index, moving the later ones down by one;
   --  Constraint_Error when Index >= Num_Vertices.

   procedure Clear (Polygon : in out Ks_Polygon);

   overriding function Map
     (Shape     : Ks_Polygon;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class;
   --  Always a Ks_Polygon.

   overriding function Contains_Point
     (Region : Ks_Polygon; X, Y : Real) return Boolean;
   overriding procedure Get_Bounding_Box
     (Region                 : Ks_Polygon;
      Min_X, Min_Y, Max_X, Max_Y : out Real);
   --  All zeros for a polygon without vertices.
   overriding function Boundary_Slack (Region : Ks_Polygon) return Real;
   function Perimeter (Polygon : Ks_Polygon) return Real;
   --  The length of the closed boundary, the edge from the last vertex
   --  back to the first included; 0.0 with fewer than 2 vertices.
   overriding function Area (Region : Ks_Polygon) return Real;
   --  The absolute value of the signed shoelace area: the sum, over the
   --  edges, of the signed areas of the triangles that each edge forms
   --  with a fixed point. For a simple polygon (one whose boundary
   --  neither crosses nor retraces itself) this is the area of the set
   --  Contains_Point accepts. For any other polygon it is the net area,
   --  in which parts traced in opposite senses cancel and parts traced
   --  twice count twice, so it differs from the area of the even-odd set
   --  Contains_Point accepts: a bow tie (0, 0), (10, 10), (10, 0),
   --  (0, 10) has Area 0 although its two lobes (area 50) are inside, a
   --  pentagram has the area of its five tips plus twice that of the
   --  central pentagon, which is outside, and a square traced twice has
   --  twice its area although only its edges are inside.
   --
   --  Ks_Polygon is a value: assignment copies the vertices, and "="
   --  compares them. The stream attributes write the selected space name,
   --  the number of vertices (Interfaces.Unsigned_32) and each vertex as
   --  X and Y (Real); 'Read raises Ks_Bad_Parameter_Exception for a count
   --  above 2**20 or a coordinate beyond the bounds, and leaves the
   --  polygon's vertices unchanged then.

   ---------------------------------------------------------------------
   --  CogCircularAnnulusSection: points whose distance from the centre is
   --  between Radius and Radius * Radial_Scale (in either order) and whose
   --  direction from the centre lies in [Angle_Start, Angle_Start +
   --  Angle_Span] (Angle_Span may be negative; |Angle_Span| >= 2 Pi is a
   --  full annulus).
   ---------------------------------------------------------------------

   type Ks_Circular_Annulus_Section is new Ks_Region with private;
   --  Default: centre (0, 0), radius 50, radial scale 1.5, start 0, span
   --  2 Pi.

   function Center_X (Section : Ks_Circular_Annulus_Section) return Real;
   function Center_Y (Section : Ks_Circular_Annulus_Section) return Real;
   function Radius (Section : Ks_Circular_Annulus_Section) return Real;
   function Radial_Scale (Section : Ks_Circular_Annulus_Section) return Real;
   function Angle_Start (Section : Ks_Circular_Annulus_Section) return Real;
   function Angle_Span (Section : Ks_Circular_Annulus_Section) return Real;

   procedure Set_Center_X
     (Section : in out Ks_Circular_Annulus_Section; Value : Real);
   procedure Set_Center_Y
     (Section : in out Ks_Circular_Annulus_Section; Value : Real);
   procedure Set_Radius
     (Section : in out Ks_Circular_Annulus_Section; Value : Real);
   procedure Set_Radial_Scale
     (Section : in out Ks_Circular_Annulus_Section; Value : Real);
   procedure Set_Angle_Start
     (Section : in out Ks_Circular_Annulus_Section; Value : Real);
   procedure Set_Angle_Span
     (Section : in out Ks_Circular_Annulus_Section; Value : Real);
   --  Radius and Radial_Scale must be >= 0 (Ks_Bad_Parameter_Exception).

   procedure Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
     (Section : in out Ks_Circular_Annulus_Section;
      Center_X, Center_Y, Radius, Angle_Start, Angle_Span,
      Radial_Scale : Real);

   procedure Get_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
     (Section : Ks_Circular_Annulus_Section;
      Center_X, Center_Y, Radius, Angle_Start, Angle_Span,
      Radial_Scale : out Real);

   overriding function Map
     (Shape     : Ks_Circular_Annulus_Section;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class;
   --  Supported for similarities only (rotation and uniform scaling,
   --  possibly with a reflection, as for Ks_Circle.Map); otherwise raises
   --  Ks_Bad_Parameter_Exception. The centre is mapped, Radius is
   --  multiplied by the scale of the similarity (the length of the first
   --  matrix column, as for Ks_Circle.Map), Radial_Scale is kept and
   --  Angle_Start becomes the mapped start direction. A reflection
   --  (negative determinant) also negates Angle_Span, since it reverses
   --  the sense of rotation.

   overriding function Contains_Point
     (Region : Ks_Circular_Annulus_Section; X, Y : Real) return Boolean;
   --  At the centre itself the direction is undefined: the centre is
   --  inside exactly when the smaller radius is 0 (within the slack).
   --  Around the centre the slack is applied as an arc length (the span
   --  is widened by the angle slack / distance at each end), so a point
   --  up to the slack beyond a radial edge still counts as inside.
   overriding function Boundary_Slack
     (Region : Ks_Circular_Annulus_Section) return Real;
   overriding procedure Get_Bounding_Box
     (Region                 : Ks_Circular_Annulus_Section;
      Min_X, Min_Y, Max_X, Max_Y : out Real);
   --  The exact box: it accounts for the span's end points at both radii
   --  and for every axis direction the span crosses.
   overriding function Area
     (Region : Ks_Circular_Annulus_Section) return Real;
   --  0.5 * min (abs Angle_Span, 2 Pi) * abs (R2**2 - R1**2) where R1 and
   --  R2 are Radius and Radius * Radial_Scale.

   ---------------------------------------------------------------------
   --  CogLineSegment
   ---------------------------------------------------------------------

   type Ks_Line_Segment is new Ks_Shape with private;
   --  Default: from (0, 0) to (100, 0).

   function Start_X (Segment : Ks_Line_Segment) return Real;
   function Start_Y (Segment : Ks_Line_Segment) return Real;
   function End_X (Segment : Ks_Line_Segment) return Real;
   function End_Y (Segment : Ks_Line_Segment) return Real;
   function Length (Segment : Ks_Line_Segment) return Real;
   function Rotation (Segment : Ks_Line_Segment) return Real;
   --  Direction from start to end; 0.0 for a zero-length segment.
   function Midpoint_X (Segment : Ks_Line_Segment) return Real;
   function Midpoint_Y (Segment : Ks_Line_Segment) return Real;

   procedure Set_Start_X (Segment : in out Ks_Line_Segment; Value : Real);
   procedure Set_Start_Y (Segment : in out Ks_Line_Segment; Value : Real);
   procedure Set_End_X (Segment : in out Ks_Line_Segment; Value : Real);
   procedure Set_End_Y (Segment : in out Ks_Line_Segment; Value : Real);

   procedure Set_Start_End
     (Segment : in out Ks_Line_Segment;
      Start_X, Start_Y, End_X, End_Y : Real);

   procedure Get_Start_End
     (Segment : Ks_Line_Segment;
      Start_X, Start_Y, End_X, End_Y : out Real);

   procedure Set_Start_Length_Rotation
     (Segment : in out Ks_Line_Segment;
      Start_X, Start_Y, Length, Rotation : Real);
   --  Length must be >= 0 (Ks_Bad_Parameter_Exception).

   procedure Get_Start_Length_Rotation
     (Segment : Ks_Line_Segment;
      Start_X, Start_Y, Length, Rotation : out Real);
   --  Length and Rotation as the functions of that name return them.

   overriding function Map
     (Shape     : Ks_Line_Segment;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class;
   --  Always a Ks_Line_Segment.

   ---------------------------------------------------------------------
   --  CogLine: the infinite line through (X, Y) with direction Rotation.
   ---------------------------------------------------------------------

   type Ks_Line is new Ks_Shape with private;
   --  Default: through (0, 0), rotation 0.

   function X (Line : Ks_Line) return Real;
   function Y (Line : Ks_Line) return Real;
   function Rotation (Line : Ks_Line) return Real;

   procedure Set_X (Line : in out Ks_Line; Value : Real);
   procedure Set_Y (Line : in out Ks_Line; Value : Real);
   procedure Set_Rotation (Line : in out Ks_Line; Value : Real);

   procedure Set_XY_Rotation (Line : in out Ks_Line; X, Y, Rotation : Real);
   --  SetXYRotation.

   procedure Get_XY_Rotation (Line : Ks_Line; X, Y, Rotation : out Real);
   --  GetXYRotation.

   procedure Set_From_Start_XY_End_XY
     (Line : in out Ks_Line; Start_X, Start_Y, End_X, End_Y : Real);
   --  SetFromStartXYEndXY: the line through both points, directed from
   --  start to end (X, Y become the start point). The points must differ
   --  (Ks_Bad_Parameter_Exception).

   procedure Set_From_Line_Segment
     (Line : in out Ks_Line; Segment : Ks_Line_Segment'Class);
   --  SetFromLineSegment: Set_From_Start_XY_End_XY with the segment's end
   --  points (Ks_Bad_Parameter_Exception for a segment of no length). The
   --  selected space name of Line is kept.

   procedure Set_Distance_Rotation
     (Line : in out Ks_Line; Distance, Rotation : Real);
   --  SetDistanceRotation: the line with direction Rotation whose signed
   --  distance from the origin is Distance (abs Distance <= 4.0E150): X
   --  and Y become the point of the line nearest the origin,
   --  Distance * (-sin Rotation, cos Rotation).

   procedure Get_Distance_Rotation
     (Line : Ks_Line; Distance, Rotation : out Real);
   --  GetDistanceRotation: Distance = Y cos Rotation - X sin Rotation, the
   --  signed distance of the line from the origin, measured along the
   --  normal (-sin Rotation, cos Rotation) (positive when the origin lies
   --  to the right of the line, looking along Rotation with the y axis
   --  pointing up), and Rotation itself. This sign convention is AMV's:
   --  VisionPro's has not been checked.

   overriding function Map
     (Shape     : Ks_Line;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class;
   --  Always a Ks_Line; the mapped direction is
   --  Transform.Map_Angle (Rotation), which raises
   --  Ks_Transform_Singular_Exception when the direction maps to zero.

   ---------------------------------------------------------------------
   --  CogPointMarker
   ---------------------------------------------------------------------

   type Ks_Point_Marker is new Ks_Shape with private;
   --  Default: (0, 0), rotation 0.

   function X (Marker : Ks_Point_Marker) return Real;
   function Y (Marker : Ks_Point_Marker) return Real;
   function Rotation (Marker : Ks_Point_Marker) return Real;

   procedure Set_X (Marker : in out Ks_Point_Marker; Value : Real);
   procedure Set_Y (Marker : in out Ks_Point_Marker; Value : Real);
   procedure Set_Rotation (Marker : in out Ks_Point_Marker; Value : Real);

   overriding function Map
     (Shape     : Ks_Point_Marker;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class;
   --  Always a Ks_Point_Marker; the rotation is mapped with Map_Angle
   --  (Ks_Transform_Singular_Exception when it maps to zero).

   ---------------------------------------------------------------------
   --  CogCircularArc: the arc of the circle (Center, Radius) from
   --  Angle_Start through Angle_Span (signed).
   ---------------------------------------------------------------------

   type Ks_Circular_Arc is new Ks_Shape with private;
   --  Default: centre (0, 0), radius 50, start 0, span Pi.

   function Center_X (Arc : Ks_Circular_Arc) return Real;
   function Center_Y (Arc : Ks_Circular_Arc) return Real;
   function Radius (Arc : Ks_Circular_Arc) return Real;
   function Angle_Start (Arc : Ks_Circular_Arc) return Real;
   function Angle_Span (Arc : Ks_Circular_Arc) return Real;
   function Start_X (Arc : Ks_Circular_Arc) return Real;
   function Start_Y (Arc : Ks_Circular_Arc) return Real;
   function End_X (Arc : Ks_Circular_Arc) return Real;
   function End_Y (Arc : Ks_Circular_Arc) return Real;

   procedure Set_Center_X (Arc : in out Ks_Circular_Arc; Value : Real);
   procedure Set_Center_Y (Arc : in out Ks_Circular_Arc; Value : Real);
   procedure Set_Radius (Arc : in out Ks_Circular_Arc; Value : Real);
   procedure Set_Angle_Start (Arc : in out Ks_Circular_Arc; Value : Real);
   procedure Set_Angle_Span (Arc : in out Ks_Circular_Arc; Value : Real);
   --  Radius must be >= 0 (Ks_Bad_Parameter_Exception).

   procedure Set_Center_Radius_Angle_Start_Angle_Span
     (Arc : in out Ks_Circular_Arc;
      Center_X, Center_Y, Radius, Angle_Start, Angle_Span : Real);

   procedure Get_Center_Radius_Angle_Start_Angle_Span
     (Arc : Ks_Circular_Arc;
      Center_X, Center_Y, Radius, Angle_Start, Angle_Span : out Real);

   overriding function Map
     (Shape     : Ks_Circular_Arc;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class;
   --  Supported for similarities only, mapped like
   --  Ks_Circular_Annulus_Section (the radius is multiplied by the length
   --  of the first matrix column, a reflection negates Angle_Span);
   --  otherwise raises Ks_Bad_Parameter_Exception.

private

   --  Every shape keeps its geometry in the kernel's record (the C struct
   --  of include/amv.h) and its selected space name here. The defaults of
   --  the kernel records are the defaults documented above.
   --
   --  Every concrete shape has its own 'Read (its 'Write is the predefined
   --  one, so the stream holds the selected space name and then the
   --  kernel record, or the vertices): it reads into a fresh shape and
   --  assigns it to Item only when the whole shape was read, and raises
   --  Ks_Image_File_Exception for a stream that ends early (a polygon's
   --  vertex count and vertices raise Ks_Bad_Parameter_Exception as
   --  documented above).

   type Ks_Shape is abstract tagged record
      Space_Name : Ada.Strings.Unbounded.Unbounded_String :=
        Ada.Strings.Unbounded.To_Unbounded_String (".");
   end record;

   type Ks_Region is abstract new Ks_Shape with null record;

   type Ks_Rectangle is new Ks_Region with record
      Data : AMV.Kernels.Shapes.Ks_Rectangle;
   end record;

   procedure Read_Rectangle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Rectangle);
   for Ks_Rectangle'Read use Read_Rectangle;

   type Ks_Rectangle_Affine is new Ks_Region with record
      Data : AMV.Kernels.Shapes.Ks_Rectangle_Affine;
   end record;

   procedure Read_Rectangle_Affine
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Rectangle_Affine);
   for Ks_Rectangle_Affine'Read use Read_Rectangle_Affine;

   type Ks_Circle is new Ks_Region with record
      Data : AMV.Kernels.Shapes.Ks_Circle;
   end record;

   procedure Read_Circle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Circle);
   for Ks_Circle'Read use Read_Circle;

   type Ks_Ellipse is new Ks_Region with record
      Data : AMV.Kernels.Shapes.Ks_Ellipse;
   end record;

   procedure Read_Ellipse
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Ellipse);
   for Ks_Ellipse'Read use Read_Ellipse;

   --  The vertices of a polygon: a kernel handle (null for none) that
   --  each Ks_Polygon owns. Assignment duplicates it, finalization
   --  destroys it, "=" compares the vertices, and the stream attributes
   --  read and write the vertices by value (see Ks_Polygon).

   type Polygon_Vertices is new Ada.Finalization.Controlled with record
      Handle : AMV.Kernels.Shapes.Ks_Polygon;
   end record;

   overriding procedure Adjust (Vertices : in out Polygon_Vertices);
   overriding procedure Finalize (Vertices : in out Polygon_Vertices);

   overriding function "=" (Left, Right : Polygon_Vertices) return Boolean;

   procedure Write_Vertices
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Polygon_Vertices);
   procedure Read_Vertices
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Polygon_Vertices);

   for Polygon_Vertices'Write use Write_Vertices;
   for Polygon_Vertices'Read use Read_Vertices;

   type Ks_Polygon is new Ks_Region with record
      Vertices : Polygon_Vertices;
   end record;

   procedure Read_Polygon
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Polygon);
   for Ks_Polygon'Read use Read_Polygon;

   type Ks_Circular_Annulus_Section is new Ks_Region with record
      Data : AMV.Kernels.Shapes.Ks_Circular_Annulus_Section;
   end record;

   procedure Read_Circular_Annulus_Section
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Circular_Annulus_Section);
   for Ks_Circular_Annulus_Section'Read use Read_Circular_Annulus_Section;

   type Ks_Line_Segment is new Ks_Shape with record
      Data : AMV.Kernels.Shapes.Ks_Line_Segment;
   end record;

   procedure Read_Line_Segment
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Line_Segment);
   for Ks_Line_Segment'Read use Read_Line_Segment;

   type Ks_Line is new Ks_Shape with record
      Data : AMV.Kernels.Shapes.Ks_Line;
   end record;

   procedure Read_Line
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Line);
   for Ks_Line'Read use Read_Line;

   type Ks_Point_Marker is new Ks_Shape with record
      Data : AMV.Kernels.Shapes.Ks_Point_Marker;
   end record;

   procedure Read_Point_Marker
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Point_Marker);
   for Ks_Point_Marker'Read use Read_Point_Marker;

   type Ks_Circular_Arc is new Ks_Shape with record
      Data : AMV.Kernels.Shapes.Ks_Circular_Arc;
   end record;

   procedure Read_Circular_Arc
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Circular_Arc);
   for Ks_Circular_Arc'Read use Read_Circular_Arc;

end AMV.Shapes;
