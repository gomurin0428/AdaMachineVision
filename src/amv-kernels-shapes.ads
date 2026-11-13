--  Kernel of AMV.Shapes: the geometry of CogRectangle, CogRectangleAffine,
--  CogCircle, CogEllipse, CogPolygon, CogCircularAnnulusSection, CogLine,
--  CogLineSegment, CogPointMarker and CogCircularArc (ICogShape and
--  ICogRegion). The meaning of every property and operation, the boundary
--  slack of Contains_Point included, is documented in AMV.Shapes; the
--  selected space name stays in the Ada API.
--
--  Values. Every fixed-size shape is a record with Convention C (C: the
--  ks_<shape> structs of include/amv.h), passed by reference. A polygon
--  has a variable number of vertices, so it lives behind an owned handle
--  (Ks_Polygon; C: ks_polygon *, opaque) that ks_polygon_create or
--  ks_polygon_add_vertex creates and ks_polygon_destroy frees. A null
--  handle is a polygon without vertices: its queries give 0 (or nothing),
--  Duplicate and Map give null, and ks_polygon_add_vertex creates the
--  handle. A handle that is not null must come from this kernel and not be
--  destroyed yet (C cannot check that); a record that is inconsistent
--  anyway fails with Bad_Parameter.
--
--  Bounds. Every coordinate and every angle a shape holds, takes or
--  returns lies within [-Max_Value, Max_Value] (1.0E150, the bound of
--  AMV.Kernels.Transforms, through which shapes are mapped), and every
--  length (Width, Height, a side length, a radius, Length, a Line's
--  distance from the origin) within [0, Max_Length] (4.0E150: the largest
--  distance between two points within the coordinate bound is
--  2 Sqrt (2) Max_Value, and the overflow-free length of a vector is
--  proved to be at most 2 Max_Value times 2). A Radial_Scale lies within
--  [0, Max_Value], and Radius * Radial_Scale within Max_Length. With these
--  bounds no product of two values and no sum of a few of them can
--  overflow. An argument outside its bound, a NaN or an infinity gives
--  Bad_Parameter naming the property; a result that would leave its bound
--  (a centre, a corner, a bounding box, an end point, a mapped shape) gives
--  Bad_Parameter too, so every shape and point the kernel returns is a
--  valid argument again. Areas lie within [0, Max_Area] and perimeters
--  within [0, Max_Perimeter]; they are no argument of any entry point. A
--  polygon has at most Max_Vertices vertices (2**20), few enough that the
--  shoelace sum of its area cannot overflow.
--
--  Trusted parts (SPARK_Mode Off bodies, listed in docs/PROOF.md): the
--  two allocation helpers of the polygon, which turn a failed allocation
--  into Out_Of_Memory. Everything else is proved.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics;
with Interfaces;

with AMV.Kernels.Transforms;

package AMV.Kernels.Shapes with SPARK_Mode, Preelaborate is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  The polygon postconditions compare vertices with their values on
   --  entry through the total ghost function Vertices_Of.

   package KT renames AMV.Kernels.Transforms;

   use type Interfaces.Unsigned_32;

   Pi     : constant := Ada.Numerics.Pi;
   Two_Pi : constant := 2.0 * Pi;

   Max_Value     : constant := 1.0E150;
   Max_Length    : constant := 4.0E150;
   Max_Area      : constant := 2.0 ** 1022;
   Max_Perimeter : constant := 2.0 ** 522;
   Max_Slack     : constant := 1.0E145;
   Max_Vertices  : constant := 2**20;

   Similarity_Tolerance : constant := 1.0E-9;
   --  The relative tolerance with which Map recognises an axis-aligned
   --  transform (rectangles) and a similarity (circles, arcs and annulus
   --  sections): AMV.Transforms' default for Is_Axis_Aligned and
   --  Is_Similarity.

   function Bounded (X : Long_Float) return Boolean is
     (X >= -Max_Value and then X <= Max_Value);
   --  A coordinate or an angle: within [-Max_Value, Max_Value] (False for
   --  a NaN or an infinity at run time).

   function Length_Bounded (X : Long_Float) return Boolean is
     (X >= 0.0 and then X <= Max_Length);
   --  A length: within [0, Max_Length].

   function Valid_Box (Min_X, Min_Y, Max_X, Max_Y : Long_Float) return Boolean
   is (Bounded (Min_X) and then Bounded (Min_Y) and then Bounded (Max_X)
       and then Bounded (Max_Y) and then Min_X <= Max_X
       and then Min_Y <= Max_Y);
   --  A bounding box as Get_Bounding_Box returns it.

   function Status_OK (Status : Ks_Status) return Boolean is
     (Valid (Status)
      and then Status.Failure in Failure_None | Failure_Bad_Parameter);
   --  A valid status whose only possible failure is Bad_Parameter.

   ---------------------------------------------------------------------
   --  Shape type codes (Map's Result_Type; C: KS_SHAPE_*)
   ---------------------------------------------------------------------

   Shape_Rectangle                : constant Int32 := 1;
   Shape_Rectangle_Affine         : constant Int32 := 2;
   Shape_Circle                   : constant Int32 := 3;
   Shape_Ellipse                  : constant Int32 := 4;
   Shape_Polygon                  : constant Int32 := 5;
   Shape_Circular_Annulus_Section : constant Int32 := 6;
   Shape_Line                     : constant Int32 := 7;
   Shape_Line_Segment             : constant Int32 := 8;
   Shape_Point_Marker             : constant Int32 := 9;
   Shape_Circular_Arc             : constant Int32 := 10;

   ---------------------------------------------------------------------
   --  Records
   ---------------------------------------------------------------------

   type Ks_Rectangle is record
      X      : Long_Float := 0.0;
      Y      : Long_Float := 0.0;
      Width  : Long_Float := 100.0;
      Height : Long_Float := 100.0;
   end record
     with Convention => C;
   --  C: ks_rectangle. (X, Y) is the corner with the smallest coordinates.

   function Valid_Rectangle (R : Ks_Rectangle) return Boolean is
     (Bounded (R.X) and then Bounded (R.Y)
      and then Length_Bounded (R.Width) and then Length_Bounded (R.Height));

   type Ks_Rectangle_Affine is record
      Center_X      : Long_Float := 50.0;
      Center_Y      : Long_Float := 50.0;
      Side_X_Length : Long_Float := 100.0;
      Side_Y_Length : Long_Float := 100.0;
      Rotation      : Long_Float := 0.0;
      Skew          : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_rectangle_affine.

   function Valid_Rectangle_Affine (R : Ks_Rectangle_Affine) return Boolean
   is (Bounded (R.Center_X) and then Bounded (R.Center_Y)
       and then Length_Bounded (R.Side_X_Length)
       and then Length_Bounded (R.Side_Y_Length)
       and then Bounded (R.Rotation) and then Bounded (R.Skew));

   type Ks_Rectangle_Affine_Corners is record
      Origin_X          : Long_Float := 0.0;
      Origin_Y          : Long_Float := 0.0;
      Corner_X_X        : Long_Float := 0.0;
      Corner_X_Y        : Long_Float := 0.0;
      Corner_Y_X        : Long_Float := 0.0;
      Corner_Y_Y        : Long_Float := 0.0;
      Corner_Opposite_X : Long_Float := 0.0;
      Corner_Opposite_Y : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_rectangle_affine_corners. The four corners (CornerOrigin,
   --  CornerX, CornerY and CornerOpposite).

   type Ks_Circle is record
      Center_X : Long_Float := 0.0;
      Center_Y : Long_Float := 0.0;
      Radius   : Long_Float := 50.0;
   end record
     with Convention => C;
   --  C: ks_circle.

   function Valid_Circle (C : Ks_Circle) return Boolean is
     (Bounded (C.Center_X) and then Bounded (C.Center_Y)
      and then Length_Bounded (C.Radius));

   type Ks_Ellipse is record
      Center_X : Long_Float := 0.0;
      Center_Y : Long_Float := 0.0;
      Radius_X : Long_Float := 50.0;
      Radius_Y : Long_Float := 25.0;
      Rotation : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_ellipse.

   function Valid_Ellipse (E : Ks_Ellipse) return Boolean is
     (Bounded (E.Center_X) and then Bounded (E.Center_Y)
      and then Length_Bounded (E.Radius_X)
      and then Length_Bounded (E.Radius_Y) and then Bounded (E.Rotation));

   type Ks_Circular_Annulus_Section is record
      Center_X     : Long_Float := 0.0;
      Center_Y     : Long_Float := 0.0;
      Radius       : Long_Float := 50.0;
      Angle_Start  : Long_Float := 0.0;
      Angle_Span   : Long_Float := Two_Pi;
      Radial_Scale : Long_Float := 1.5;
   end record
     with Convention => C;
   --  C: ks_circular_annulus_section.

   function Valid_Circular_Annulus_Section
     (S : Ks_Circular_Annulus_Section) return Boolean
   is (Bounded (S.Center_X) and then Bounded (S.Center_Y)
       and then Length_Bounded (S.Radius)
       and then Bounded (S.Angle_Start) and then Bounded (S.Angle_Span)
       and then S.Radial_Scale >= 0.0 and then S.Radial_Scale <= Max_Value
       and then S.Radius * S.Radial_Scale <= Max_Length);
   --  Also the second radius, Radius * Radial_Scale, within Max_Length.

   type Ks_Line is record
      X        : Long_Float := 0.0;
      Y        : Long_Float := 0.0;
      Rotation : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_line.

   function Valid_Line (L : Ks_Line) return Boolean is
     (Bounded (L.X) and then Bounded (L.Y) and then Bounded (L.Rotation));

   type Ks_Line_Segment is record
      Start_X : Long_Float := 0.0;
      Start_Y : Long_Float := 0.0;
      End_X   : Long_Float := 100.0;
      End_Y   : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_line_segment.

   function Valid_Line_Segment (S : Ks_Line_Segment) return Boolean is
     (Bounded (S.Start_X) and then Bounded (S.Start_Y)
      and then Bounded (S.End_X) and then Bounded (S.End_Y));

   type Ks_Point_Marker is record
      X        : Long_Float := 0.0;
      Y        : Long_Float := 0.0;
      Rotation : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_point_marker.

   function Valid_Point_Marker (M : Ks_Point_Marker) return Boolean is
     (Bounded (M.X) and then Bounded (M.Y) and then Bounded (M.Rotation));

   type Ks_Circular_Arc is record
      Center_X    : Long_Float := 0.0;
      Center_Y    : Long_Float := 0.0;
      Radius      : Long_Float := 50.0;
      Angle_Start : Long_Float := 0.0;
      Angle_Span  : Long_Float := Pi;
   end record
     with Convention => C;
   --  C: ks_circular_arc.

   function Valid_Circular_Arc (A : Ks_Circular_Arc) return Boolean is
     (Bounded (A.Center_X) and then Bounded (A.Center_Y)
      and then Length_Bounded (A.Radius)
      and then Bounded (A.Angle_Start) and then Bounded (A.Angle_Span));

   ---------------------------------------------------------------------
   --  Polygon handles
   ---------------------------------------------------------------------

   subtype Coordinate is Long_Float range -Max_Value .. Max_Value;

   type Ks_Vertex is record
      X : Coordinate := 0.0;
      Y : Coordinate := 0.0;
   end record;
   --  A vertex of a polygon (not seen by C, which passes X and Y).

   type Vertex_Array is array (Natural range <>) of Ks_Vertex;

   type Vertex_Array_Access is access Vertex_Array;

   type Ks_Polygon_Data is limited record
      Count    : Natural := 0;
      Vertices : Vertex_Array_Access;
   end record;
   --  What a handle designates (opaque for C): Count vertices in
   --  Vertices (0 .. Count - 1); the array may be longer (room to add
   --  vertices) and is null when there is no room. Valid_Polygon states
   --  the invariant.

   type Ks_Polygon is access Ks_Polygon_Data
     with Convention => C;
   --  C: ks_polygon *.

   function Valid_Polygon
     (Polygon : access constant Ks_Polygon_Data) return Boolean
   is (Polygon /= null
       and then Polygon.Count <= Max_Vertices
       and then (if Polygon.Vertices = null then Polygon.Count = 0
                 else Polygon.Vertices'First = 0
                      and then Polygon.Vertices'Last < Max_Vertices
                      and then Polygon.Count <= Polygon.Vertices'Last + 1));
   --  A handle with its vertices in place.

   function Count_Of
     (Polygon : access constant Ks_Polygon_Data) return Natural
   is (if Valid_Polygon (Polygon) then Polygon.Count else 0);
   --  The number of vertices (0 for null or an inconsistent handle).

   No_Vertices : constant Vertex_Array (1 .. 0) := [others => (0.0, 0.0)];

   function Vertices_Of
     (Polygon : access constant Ks_Polygon_Data) return Vertex_Array
   is (if Valid_Polygon (Polygon) and then Polygon.Count > 0
       then Polygon.Vertices (0 .. Polygon.Count - 1)
       else No_Vertices)
   with Ghost;
   --  The vertices of a valid handle, indexed from 0 (none otherwise), for
   --  contracts.

   ---------------------------------------------------------------------
   --  CogRectangle
   ---------------------------------------------------------------------

   procedure Set_XY_Width_Height
     (X, Y, Width, Height : Long_Float;
      Result              : out Ks_Rectangle;
      Status              : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_set_xy_width_height",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Result = (X, Y, Width, Height)
                            and then Valid_Rectangle (Result));
   --  SetXYWidthHeight: the rectangle with exactly these properties.
   --  Width and Height must be >= 0.

   procedure Set_Center_Width_Height
     (Center_X, Center_Y, Width, Height : Long_Float;
      Result                            : out Ks_Rectangle;
      Status                            : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_set_center_width_height",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Rectangle (Result)
                            and then Result.Width = Width
                            and then Result.Height = Height);
   --  SetCenterWidthHeight: X = Center_X - Width / 2, Y = Center_Y -
   --  Height / 2. Bad_Parameter when X or Y would exceed Max_Value.

   procedure Get_Center_Width_Height
     (Rectangle                         : Ks_Rectangle;
      Center_X, Center_Y, Width, Height : out Long_Float;
      Status                            : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_get_center_width_height",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Bounded (Center_X) and then Bounded (Center_Y)
                            and then Width = Rectangle.Width
                            and then Height = Rectangle.Height);
   --  GetCenterWidthHeight: Center = (X + Width / 2, Y + Height / 2).
   --  Bad_Parameter when the centre would exceed Max_Value.

   function Rectangle_Slack (R : Ks_Rectangle) return Long_Float
   with
     Pre  => Valid_Rectangle (R),
     Post => Rectangle_Slack'Result in 0.0 .. Max_Slack;
   --  The boundary slack of Contains_Point (see AMV.Shapes).

   procedure Contains_Point
     (Rectangle : Ks_Rectangle;
      X, Y      : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_contains_point",
     Post => Status_OK (Status)
             and then Result in False_Value | True_Value
             and then (if Succeeded (Status) and then Result = True_Value
                       then Valid_Rectangle (Rectangle)
                            and then X >= Rectangle.X
                                          - Rectangle_Slack (Rectangle)
                            and then X <= Rectangle.X + Rectangle.Width
                                          + Rectangle_Slack (Rectangle)
                            and then Y >= Rectangle.Y
                                          - Rectangle_Slack (Rectangle)
                            and then Y <= Rectangle.Y + Rectangle.Height
                                          + Rectangle_Slack (Rectangle))
             and then (if Succeeded (Status)
                       then Valid_Rectangle (Rectangle)
                            and then Bounded (X) and then Bounded (Y)
                            and then (Result = True_Value)
                                       = Rectangle_Contains
                                           (Rectangle, X, Y));
   --  1 when (X, Y) lies in the rectangle widened by the boundary slack
   --  on every side, 0 otherwise. X and Y must be within Max_Value.

   procedure Boundary_Slack
     (Rectangle : Ks_Rectangle;
      Result    : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_boundary_slack",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Rectangle (Rectangle)
                            and then Result = Rectangle_Slack (Rectangle)
                       else Result = 0.0);
   --  The slack itself: with the postconditions of Contains_Point and
   --  Get_Bounding_Box, every accepted point lies within it of the box.

   procedure Get_Bounding_Box
     (Rectangle                  : Ks_Rectangle;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float;
      Status                     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_get_bounding_box",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Box (Min_X, Min_Y, Max_X, Max_Y)
                            and then Min_X = Rectangle.X
                            and then Min_Y = Rectangle.Y
                            and then Max_X = Rectangle.X + Rectangle.Width
                            and then Max_Y
                                       = Rectangle.Y + Rectangle.Height);
   --  (X, Y, X + Width, Y + Height). Bad_Parameter when the far corner
   --  would exceed Max_Value.

   procedure Area
     (Rectangle : Ks_Rectangle;
      Result    : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_area",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Area;
   --  Width * Height.

   procedure Perimeter
     (Rectangle : Ks_Rectangle;
      Result    : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_perimeter",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Perimeter;
   --  2 * (Width + Height).

   procedure Map
     (Rectangle        : Ks_Rectangle;
      Transform        : KT.Ks_Transform_2D_Linear;
      Result_Type      : out Int32;
      Rectangle_Result : out Ks_Rectangle;
      Affine_Result    : out Ks_Rectangle_Affine;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_map",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then (if Result_Type = Shape_Rectangle
                             then Valid_Rectangle (Rectangle_Result)
                             else Result_Type = Shape_Rectangle_Affine
                                  and then Valid_Rectangle_Affine
                                             (Affine_Result))
                       else Result_Type = 0);
   --  The image under Transform (within the bound of AMV.Kernels.
   --  Transforms): a rectangle (Result_Type = Shape_Rectangle, in
   --  Rectangle_Result) when the transform is axis-aligned, otherwise an
   --  affine rectangle (Shape_Rectangle_Affine, in Affine_Result); see
   --  AMV.Shapes. Bad_Parameter when the result would leave the bounds.

   procedure Rectangle_From_Bounding_Box
     (Min_X, Min_Y, Max_X, Max_Y : Long_Float;
      Result                     : out Ks_Rectangle;
      Status                     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_from_bounding_box",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Rectangle (Result)
                            and then Result.X = Min_X
                            and then Result.Y = Min_Y
                            and then Result.Width = Max_X - Min_X
                            and then Result.Height = Max_Y - Min_Y);
   --  EnclosingRectangle: the rectangle of a bounding box (as
   --  Get_Bounding_Box returns it). Bad_Parameter unless the box is valid
   --  (Valid_Box).

   ---------------------------------------------------------------------
   --  CogRectangleAffine
   ---------------------------------------------------------------------

   procedure Set_Center_Lengths_Rotation_Skew
     (Center_X, Center_Y, Side_X_Length, Side_Y_Length : Long_Float;
      Rotation, Skew                                   : Long_Float;
      Result : out Ks_Rectangle_Affine;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_affine_set_center_lengths_rotation_skew",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Result = (Center_X, Center_Y, Side_X_Length,
                                      Side_Y_Length, Rotation, Skew)
                            and then Valid_Rectangle_Affine (Result));
   --  SetCenterLengthsRotationSkew: exactly these properties.

   procedure Set_Origin_Lengths_Rotation_Skew
     (Origin_X, Origin_Y, Side_X_Length, Side_Y_Length : Long_Float;
      Rotation, Skew                                   : Long_Float;
      Result : out Ks_Rectangle_Affine;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_affine_set_origin_lengths_rotation_skew",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Rectangle_Affine (Result)
                            and then Result.Side_X_Length = Side_X_Length
                            and then Result.Side_Y_Length = Side_Y_Length
                            and then Result.Rotation = Rotation
                            and then Result.Skew = Skew);
   --  SetOriginLengthsRotationSkew: the centre is the corner origin plus
   --  half of both sides. Bad_Parameter when it would exceed Max_Value.

   procedure Set_Origin_Corner_X_Corner_Y
     (Origin_X, Origin_Y, Corner_X_X, Corner_X_Y : Long_Float;
      Corner_Y_X, Corner_Y_Y                     : Long_Float;
      Result : out Ks_Rectangle_Affine;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_affine_set_origin_corner_x_corner_y",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Rectangle_Affine (Result)
                            and then Result.Rotation > -Pi
                            and then Result.Rotation <= Pi
                            and then Result.Skew > -Pi
                            and then Result.Skew <= Pi);
   --  SetOriginCornerXCornerY: the parallelogram with these three corners
   --  (collinear corners allowed). Bad_Parameter when the centre would
   --  exceed Max_Value (which needs corners near the bound).

   procedure Get_Corners
     (Rectangle : Ks_Rectangle_Affine;
      Result    : out Ks_Rectangle_Affine_Corners;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_affine_get_corners",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Bounded (Result.Origin_X)
                            and then Bounded (Result.Origin_Y)
                            and then Bounded (Result.Corner_X_X)
                            and then Bounded (Result.Corner_X_Y)
                            and then Bounded (Result.Corner_Y_X)
                            and then Bounded (Result.Corner_Y_Y)
                            and then Bounded (Result.Corner_Opposite_X)
                            and then Bounded (Result.Corner_Opposite_Y));
   --  The four corners. Bad_Parameter when one would exceed Max_Value.

   procedure Get_Parent_From_Child_Transform
     (Rectangle : Ks_Rectangle_Affine;
      Result    : out KT.Ks_Transform_2D_Linear;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name =>
       "ks_rectangle_affine_get_parent_from_child_transform",
     Post => Status_OK (Status)
             and then (if Succeeded (Status) then KT.Bounded (Result));
   --  GetParentFromChildTransform: child (u, v) maps to Origin + u DirX +
   --  v DirY. Bad_Parameter when the corner origin would exceed Max_Value.

   procedure Contains_Point
     (Rectangle : Ks_Rectangle_Affine;
      X, Y      : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_affine_contains_point",
     Post => Status_OK (Status) and then Result in False_Value | True_Value
             and then (if Succeeded (Status)
                       then Valid_Rectangle_Affine (Rectangle)
                            and then Bounded (X) and then Bounded (Y)
                            and then (Result = True_Value)
                                       = Rectangle_Affine_Contains
                                           (Rectangle, X, Y));

   procedure Boundary_Slack
     (Rectangle : Ks_Rectangle_Affine;
      Result    : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_affine_boundary_slack",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Slack
             and then (if Succeeded (Status)
                       then Valid_Rectangle_Affine (Rectangle));

   procedure Get_Bounding_Box
     (Rectangle                  : Ks_Rectangle_Affine;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float;
      Status                     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_affine_get_bounding_box",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Box (Min_X, Min_Y, Max_X, Max_Y));

   procedure Area
     (Rectangle : Ks_Rectangle_Affine;
      Result    : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_affine_area",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Area;
   --  Side_X_Length * Side_Y_Length * abs cos (Skew).

   procedure Map
     (Rectangle : Ks_Rectangle_Affine;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Rectangle_Affine;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_rectangle_affine_map",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Rectangle_Affine (Result));
   --  The image of the three corners, as by Set_Origin_Corner_X_Corner_Y.

   ---------------------------------------------------------------------
   --  CogCircle
   ---------------------------------------------------------------------

   procedure Set_Center_Radius
     (Center_X, Center_Y, Radius : Long_Float;
      Result                     : out Ks_Circle;
      Status                     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circle_set_center_radius",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Result = (Center_X, Center_Y, Radius)
                            and then Valid_Circle (Result));
   --  SetCenterRadius: exactly these properties.

   procedure Contains_Point
     (Circle : Ks_Circle;
      X, Y   : Long_Float;
      Result : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circle_contains_point",
     Post => Status_OK (Status) and then Result in False_Value | True_Value
             and then (if Succeeded (Status)
                       then Valid_Circle (Circle)
                            and then Bounded (X) and then Bounded (Y)
                            and then (Result = True_Value)
                                       = Circle_Contains (Circle, X, Y));

   procedure Boundary_Slack
     (Circle : Ks_Circle;
      Result : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circle_boundary_slack",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Slack
             and then (if Succeeded (Status) then Valid_Circle (Circle));

   procedure Get_Bounding_Box
     (Circle                     : Ks_Circle;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float;
      Status                     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circle_get_bounding_box",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Box (Min_X, Min_Y, Max_X, Max_Y));

   procedure Area
     (Circle : Ks_Circle;
      Result : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circle_area",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Area;
   --  Pi * Radius**2.

   procedure Map
     (Circle         : Ks_Circle;
      Transform      : KT.Ks_Transform_2D_Linear;
      Result_Type    : out Int32;
      Circle_Result  : out Ks_Circle;
      Ellipse_Result : out Ks_Ellipse;
      Status         : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circle_map",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then (if Result_Type = Shape_Circle
                             then Valid_Circle (Circle_Result)
                             else Result_Type = Shape_Ellipse
                                  and then Valid_Ellipse (Ellipse_Result))
                       else Result_Type = 0);
   --  A circle (Shape_Circle) under a similarity, possibly reflecting,
   --  otherwise the image ellipse (Shape_Ellipse); see AMV.Shapes.

   ---------------------------------------------------------------------
   --  CogEllipse
   ---------------------------------------------------------------------

   procedure Set_Center_XY_Radius_XY_Rotation
     (Center_X, Center_Y, Radius_X, Radius_Y, Rotation : Long_Float;
      Result : out Ks_Ellipse;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ellipse_set_center_xy_radius_xy_rotation",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Result = (Center_X, Center_Y, Radius_X,
                                      Radius_Y, Rotation)
                            and then Valid_Ellipse (Result));
   --  SetCenterXYRadiusXYRotation: exactly these properties.

   procedure Contains_Point
     (Ellipse : Ks_Ellipse;
      X, Y    : Long_Float;
      Result  : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ellipse_contains_point",
     Post => Status_OK (Status) and then Result in False_Value | True_Value
             and then (if Succeeded (Status)
                       then Valid_Ellipse (Ellipse)
                            and then Bounded (X) and then Bounded (Y)
                            and then (Result = True_Value)
                                       = Ellipse_Contains (Ellipse, X, Y));

   procedure Boundary_Slack
     (Ellipse : Ks_Ellipse;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ellipse_boundary_slack",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Slack
             and then (if Succeeded (Status) then Valid_Ellipse (Ellipse));

   procedure Get_Bounding_Box
     (Ellipse                    : Ks_Ellipse;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float;
      Status                     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ellipse_get_bounding_box",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Box (Min_X, Min_Y, Max_X, Max_Y));

   procedure Area
     (Ellipse : Ks_Ellipse;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ellipse_area",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Area;
   --  Pi * Radius_X * Radius_Y.

   procedure Map
     (Ellipse   : Ks_Ellipse;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Ellipse;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ellipse_map",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Ellipse (Result)
                            and then Result.Rotation > -Pi
                            and then Result.Rotation <= Pi);
   --  The image ellipse; see AMV.Shapes.

   ---------------------------------------------------------------------
   --  CogPolygon
   ---------------------------------------------------------------------

   procedure Create
     (Polygon : out Ks_Polygon;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_create",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Polygon (Polygon) and then Polygon.Count = 0
                       else Polygon = null);
   --  A new polygon without vertices.

   procedure Destroy
     (Polygon : in out Ks_Polygon;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_destroy",
     Post => Valid (Status) and then Succeeded (Status)
             and then Polygon = null;
   --  Frees the polygon and sets Polygon to null. Nothing for null. Never
   --  fails.

   procedure Duplicate
     (Polygon : access constant Ks_Polygon_Data;
      Result  : out Ks_Polygon;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_duplicate",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) and then Polygon /= null
                       then Valid_Polygon (Polygon)
                            and then Valid_Polygon (Result)
                            and then Result.Count = Polygon.Count
                            and then Vertices_Of (Result)
                                       = Vertices_Of (Polygon)
                       else Result = null);
   --  A new polygon with the same vertices, sharing nothing with Polygon;
   --  null for null.

   procedure Num_Vertices
     (Polygon : access constant Ks_Polygon_Data;
      Result  : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_num_vertices",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Result = Int32 (Count_Of (Polygon))
                       else Result = 0);
   --  NumVertices; 0 for null.

   procedure Get_Vertex
     (Polygon : access constant Ks_Polygon_Data;
      Index   : Int32;
      X, Y    : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_get_vertex",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Polygon (Polygon)
                            and then Index in 0 .. Int32 (Polygon.Count) - 1
                            and then X = Polygon.Vertices (Natural (Index)).X
                            and then Y = Polygon.Vertices (Natural (Index)).Y
                       else X = 0.0 and then Y = 0.0);
   --  GetVertex: vertex Index (0-based). Index_Out_Of_Range unless Index
   --  is in 0 .. NumVertices - 1.

   procedure Set_Vertex
     (Polygon : Ks_Polygon;
      Index   : Int32;
      X, Y    : Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_set_vertex",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then Count_Of (Polygon) = Count_Of (Polygon)'Old
             and then (if Succeeded (Status)
                       then Valid_Polygon (Polygon)
                            and then Index in 0 .. Int32 (Polygon.Count) - 1
                            and then Polygon.Vertices (Natural (Index)).X
                                       = X
                            and then Polygon.Vertices (Natural (Index)).Y
                                       = Y
                            and then
                              (for all J in 0 .. Polygon.Count - 1
                               => (if J /= Natural (Index)
                                   then Polygon.Vertices (J)
                                          = Vertices_Of (Polygon)'Old (J)))
                       else Vertices_Of (Polygon) = Vertices_Of (Polygon)'Old);
   --  SetVertex: replaces vertex Index, and no other (Gold). X and Y must
   --  be within Max_Value; Index_Out_Of_Range as for Get_Vertex. A failed
   --  call changes nothing.

   Append_Index : constant Int32 := -1;
   --  The Index of Add_Vertex that appends (C: KS_POLYGON_APPEND).

   procedure Add_Vertex
     (Polygon : in out Ks_Polygon;
      X, Y    : Long_Float;
      Index   : Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_add_vertex",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Polygon (Polygon)
                            and then Polygon.Count = Count_Of (Polygon)'Old + 1
                            and then Index
                                       in -1 .. Int32 (Count_Of (Polygon)'Old)
                            and then
                              (declare
                                 Position : constant Natural :=
                                   (if Index = -1 then Count_Of (Polygon)'Old
                                    else Natural (Index));
                               begin
                                 Polygon.Vertices (Position).X = X
                                 and then Polygon.Vertices (Position).Y = Y
                                 and then
                                   (for all J in 0 .. Position - 1
                                    => Polygon.Vertices (J)
                                         = Vertices_Of (Polygon)'Old (J))
                                 and then
                                   (for all J in Position + 1
                                                 .. Polygon.Count - 1
                                    => Polygon.Vertices (J)
                                         = Vertices_Of (Polygon)'Old (J - 1)))
                       else Count_Of (Polygon) = Count_Of (Polygon)'Old
                            and then Vertices_Of (Polygon)
                                       = Vertices_Of (Polygon)'Old);
   --  AddVertex: inserts (X, Y) before position Index, or appends it when
   --  Index is -1, moving the later vertices up by one (Gold). Creates the
   --  handle when Polygon is null. X and Y must be within Max_Value;
   --  Index_Out_Of_Range unless Index is in -1 .. NumVertices;
   --  Bad_Parameter when the polygon already has Max_Vertices vertices;
   --  Out_Of_Memory when it cannot grow. A failed call changes nothing.

   procedure Remove_Vertex
     (Polygon : Ks_Polygon;
      Index   : Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_remove_vertex",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Polygon (Polygon)
                            and then Polygon.Count = Count_Of (Polygon)'Old - 1
                            and then Index in 0 .. Int32 (Polygon.Count)
                            and then
                              (for all J in 0 .. Natural (Index) - 1
                               => Polygon.Vertices (J)
                                    = Vertices_Of (Polygon)'Old (J))
                            and then
                              (for all J in Natural (Index)
                                            .. Polygon.Count - 1
                               => Polygon.Vertices (J)
                                    = Vertices_Of (Polygon)'Old (J + 1))
                       else Count_Of (Polygon) = Count_Of (Polygon)'Old
                            and then Vertices_Of (Polygon)
                                       = Vertices_Of (Polygon)'Old);
   --  RemoveVertex: deletes vertex Index, moving the later ones down by
   --  one (Gold). Index_Out_Of_Range as for Get_Vertex. A failed call
   --  changes nothing.

   procedure Clear
     (Polygon : Ks_Polygon;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_clear",
     Post => Status_OK (Status)
             and then (if Succeeded (Status) then Count_Of (Polygon) = 0);
   --  Removes every vertex (and frees their memory). Nothing for null.

   procedure Contains_Point
     (Polygon : access constant Ks_Polygon_Data;
      X, Y    : Long_Float;
      Result  : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_contains_point",
     Post => Status_OK (Status) and then Result in False_Value | True_Value
             and then (if Succeeded (Status)
                       then (Polygon = null or else Valid_Polygon (Polygon))
                            and then Bounded (X) and then Bounded (Y)
                            and then (Result = True_Value)
                                       = Polygon_Contains (Polygon, X, Y));
   --  The even-odd rule, with the boundary slack of AMV.Shapes; 0 for a
   --  polygon without vertices.

   procedure Boundary_Slack
     (Polygon : access constant Ks_Polygon_Data;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_boundary_slack",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Slack
             and then (if Succeeded (Status)
                       then Polygon = null or else Valid_Polygon (Polygon));
   --  0 for a polygon without vertices.

   procedure Get_Bounding_Box
     (Polygon                    : access constant Ks_Polygon_Data;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float;
      Status                     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_get_bounding_box",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Box (Min_X, Min_Y, Max_X, Max_Y));
   --  The smallest box around the vertices; all zeros without vertices.

   procedure Area
     (Polygon : access constant Ks_Polygon_Data;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_area",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Area;
   --  The absolute value of the signed shoelace area (see AMV.Shapes); 0
   --  with fewer than 3 vertices.

   procedure Perimeter
     (Polygon : access constant Ks_Polygon_Data;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_perimeter",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Perimeter;
   --  The length of the closed boundary (the edge from the last vertex
   --  back to the first included); 0 with fewer than 2 vertices.

   procedure Map
     (Polygon   : access constant Ks_Polygon_Data;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Polygon;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_polygon_map",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) and then Polygon /= null
                       then Valid_Polygon (Result)
                            and then Result.Count = Count_Of (Polygon)
                       else Result = null);
   --  A new polygon with every vertex mapped; null for null.
   --  Bad_Parameter when a mapped vertex would exceed Max_Value.

   ---------------------------------------------------------------------
   --  CogCircularAnnulusSection
   ---------------------------------------------------------------------

   procedure Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
     (Center_X, Center_Y, Radius, Angle_Start, Angle_Span : Long_Float;
      Radial_Scale                                        : Long_Float;
      Result : out Ks_Circular_Annulus_Section;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name =>
       "ks_circular_annulus_section_set_center_radius_angle_start_angle_"
       & "span_radial_scale",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Result = (Center_X, Center_Y, Radius, Angle_Start,
                                      Angle_Span, Radial_Scale)
                            and then Valid_Circular_Annulus_Section
                                       (Result));
   --  SetCenterRadiusAngleStartAngleSpanRadialScale: exactly these
   --  properties.

   procedure Contains_Point
     (Section : Ks_Circular_Annulus_Section;
      X, Y    : Long_Float;
      Result  : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circular_annulus_section_contains_point",
     Post => Status_OK (Status) and then Result in False_Value | True_Value
             and then (if Succeeded (Status)
                       then Valid_Circular_Annulus_Section (Section)
                            and then Bounded (X) and then Bounded (Y)
                            and then (Result = True_Value)
                                       = Section_Contains (Section, X, Y));

   procedure Boundary_Slack
     (Section : Ks_Circular_Annulus_Section;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circular_annulus_section_boundary_slack",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Slack
             and then (if Succeeded (Status)
                       then Valid_Circular_Annulus_Section (Section));

   procedure Get_Bounding_Box
     (Section                    : Ks_Circular_Annulus_Section;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float;
      Status                     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circular_annulus_section_get_bounding_box",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Box (Min_X, Min_Y, Max_X, Max_Y));

   procedure Area
     (Section : Ks_Circular_Annulus_Section;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circular_annulus_section_area",
     Post => Status_OK (Status) and then Result in 0.0 .. Max_Area;

   procedure Map
     (Section   : Ks_Circular_Annulus_Section;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Circular_Annulus_Section;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circular_annulus_section_map",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Circular_Annulus_Section (Result)
                            and then Result.Radial_Scale
                                       = Section.Radial_Scale);
   --  Similarities only (possibly reflecting); Bad_Parameter otherwise.

   ---------------------------------------------------------------------
   --  CogLine
   ---------------------------------------------------------------------

   procedure Set_XY_Rotation
     (X, Y, Rotation : Long_Float;
      Result         : out Ks_Line;
      Status         : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_line_set_xy_rotation",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Result = (X, Y, Rotation)
                            and then Valid_Line (Result));
   --  SetXYRotation: exactly these properties.

   procedure Set_From_Start_XY_End_XY
     (Start_X, Start_Y, End_X, End_Y : Long_Float;
      Result                         : out Ks_Line;
      Status                         : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_line_set_from_start_xy_end_xy",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Line (Result)
                            and then Result.X = Start_X
                            and then Result.Y = Start_Y
                            and then Result.Rotation > -Pi
                            and then Result.Rotation <= Pi);
   --  SetFromStartXYEndXY: through the start point, directed towards the
   --  end point. Bad_Parameter when the points are the same.

   procedure Set_From_Line_Segment
     (Segment : Ks_Line_Segment;
      Result  : out Ks_Line;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_line_set_from_line_segment",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Line (Result)
                            and then Result.X = Segment.Start_X
                            and then Result.Y = Segment.Start_Y);
   --  SetFromLineSegment: Set_From_Start_XY_End_XY with the segment's end
   --  points. Bad_Parameter for a segment of no length.

   procedure Set_Distance_Rotation
     (Distance, Rotation : Long_Float;
      Result             : out Ks_Line;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_line_set_distance_rotation",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Line (Result)
                            and then Result.Rotation = Rotation);
   --  SetDistanceRotation: the line with direction Rotation whose signed
   --  distance from the origin is Distance (within Max_Length in
   --  magnitude): (X, Y) = Distance * (-sin Rotation, cos Rotation), the
   --  point of the line nearest the origin. Bad_Parameter when that point
   --  would exceed Max_Value.

   procedure Get_Distance_Rotation
     (Line               : Ks_Line;
      Distance, Rotation : out Long_Float;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_line_get_distance_rotation",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then abs Distance <= Max_Length
                            and then Rotation = Line.Rotation);
   --  GetDistanceRotation: Distance = Y cos Rotation - X sin Rotation,
   --  the signed distance from the origin (positive when the origin lies
   --  to the right of the line, looking along its direction in a space
   --  whose y axis points up).

   procedure Map
     (Line      : Ks_Line;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Line;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_line_map",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Transform_Singular
             and then (if Succeeded (Status) then Valid_Line (Result));
   --  The point mapped, the direction mapped as by
   --  ks_transform_2d_linear_map_angle (Transform_Singular when it maps
   --  to zero).

   ---------------------------------------------------------------------
   --  CogLineSegment
   ---------------------------------------------------------------------

   procedure Set_Start_End
     (Start_X, Start_Y, End_X, End_Y : Long_Float;
      Result                         : out Ks_Line_Segment;
      Status                         : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_line_segment_set_start_end",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Result = (Start_X, Start_Y, End_X, End_Y)
                            and then Valid_Line_Segment (Result));
   --  SetStartEnd: exactly these end points.

   procedure Set_Start_Length_Rotation
     (Start_X, Start_Y, Length, Rotation : Long_Float;
      Result                            : out Ks_Line_Segment;
      Status                            : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_line_segment_set_start_length_rotation",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Line_Segment (Result)
                            and then Result.Start_X = Start_X
                            and then Result.Start_Y = Start_Y);
   --  SetStartLengthRotation: End = Start + Length (cos Rotation,
   --  sin Rotation). Length must be >= 0; Bad_Parameter when the end point
   --  would exceed Max_Value.

   procedure Get_Start_Length_Rotation
     (Segment                            : Ks_Line_Segment;
      Start_X, Start_Y, Length, Rotation : out Long_Float;
      Status                             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_line_segment_get_start_length_rotation",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Start_X = Segment.Start_X
                            and then Start_Y = Segment.Start_Y
                            and then Length_Bounded (Length)
                            and then Rotation > -Pi
                            and then Rotation <= Pi);
   --  GetStartLengthRotation: Length and Rotation (the direction from
   --  start to end, 0.0 for a segment of no length).

   procedure Get_Midpoint
     (Segment : Ks_Line_Segment;
      X, Y    : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_line_segment_get_midpoint",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Bounded (X) and then Bounded (Y));
   --  MidpointX, MidpointY.

   procedure Map
     (Segment   : Ks_Line_Segment;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Line_Segment;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_line_segment_map",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Line_Segment (Result));
   --  Both end points mapped.

   ---------------------------------------------------------------------
   --  CogPointMarker
   ---------------------------------------------------------------------

   procedure Set_XY_Rotation
     (X, Y, Rotation : Long_Float;
      Result         : out Ks_Point_Marker;
      Status         : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_point_marker_set_xy_rotation",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Result = (X, Y, Rotation)
                            and then Valid_Point_Marker (Result));
   --  X, Y and Rotation, exactly.

   procedure Map
     (Marker    : Ks_Point_Marker;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Point_Marker;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_point_marker_map",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Transform_Singular
             and then (if Succeeded (Status)
                       then Valid_Point_Marker (Result));
   --  As for a line.

   ---------------------------------------------------------------------
   --  CogCircularArc
   ---------------------------------------------------------------------

   procedure Set_Center_Radius_Angle_Start_Angle_Span
     (Center_X, Center_Y, Radius, Angle_Start, Angle_Span : Long_Float;
      Result : out Ks_Circular_Arc;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name =>
       "ks_circular_arc_set_center_radius_angle_start_angle_span",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Result = (Center_X, Center_Y, Radius, Angle_Start,
                                      Angle_Span)
                            and then Valid_Circular_Arc (Result));
   --  SetCenterRadiusAngleStartAngleSpan: exactly these properties.

   procedure Get_Start_End
     (Arc                            : Ks_Circular_Arc;
      Start_X, Start_Y, End_X, End_Y : out Long_Float;
      Status                         : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circular_arc_get_start_end",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Bounded (Start_X) and then Bounded (Start_Y)
                            and then Bounded (End_X)
                            and then Bounded (End_Y));
   --  StartX, StartY, EndX, EndY: the points at Angle_Start and
   --  Angle_Start + Angle_Span. Bad_Parameter when one would exceed
   --  Max_Value.

   procedure Map
     (Arc       : Ks_Circular_Arc;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Circular_Arc;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_circular_arc_map",
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Circular_Arc (Result));
   --  Similarities only (possibly reflecting); Bad_Parameter otherwise.

   ---------------------------------------------------------------------
   --  Ada-only helpers for the wrapper (no C entry points)
   ---------------------------------------------------------------------

   function Same_Vertices
     (Left, Right : access constant Ks_Polygon_Data) return Boolean
   with
     Post => Same_Vertices'Result
               = (Count_Of (Left) = Count_Of (Right)
                  and then Vertices_Of (Left) = Vertices_Of (Right));
   --  True when both polygons have the same vertices (null and an
   --  inconsistent handle have none): the "=" of AMV.Shapes.Ks_Polygon.

   procedure Check_Stream_Count
     (Count  : Interfaces.Unsigned_32;
      Status : out Ks_Status)
   with
     Post => Status_OK (Status)
             and then Succeeded (Status) = (Count <= Max_Vertices);
   --  Ks_Polygon'Read: Bad_Parameter when a stream announces more than
   --  Max_Vertices vertices.

   ---------------------------------------------------------------------
   --  Ada-only helpers for AMV.Kernels.Regions (no C entry points)
   ---------------------------------------------------------------------

   --  Contains_Point of each region type without the argument checks and
   --  the status: the entry points ks_*_contains_point check their
   --  arguments and then return exactly these (their postconditions say
   --  so), and AMV.Kernels.Regions calls them once per pixel.

   function Rectangle_Contains
     (Rectangle : Ks_Rectangle;
      X, Y      : Long_Float) return Boolean
   with
     Pre  => Valid_Rectangle (Rectangle)
             and then Bounded (X) and then Bounded (Y),
     Post => (if Rectangle_Contains'Result
              then X >= Rectangle.X - Rectangle_Slack (Rectangle)
                   and then X <= Rectangle.X + Rectangle.Width
                                 + Rectangle_Slack (Rectangle)
                   and then Y >= Rectangle.Y - Rectangle_Slack (Rectangle)
                   and then Y <= Rectangle.Y + Rectangle.Height
                                 + Rectangle_Slack (Rectangle));

   function Rectangle_Affine_Contains
     (Rectangle : Ks_Rectangle_Affine;
      X, Y      : Long_Float) return Boolean
   with
     Pre => Valid_Rectangle_Affine (Rectangle)
            and then Bounded (X) and then Bounded (Y);

   function Circle_Contains
     (Circle : Ks_Circle;
      X, Y   : Long_Float) return Boolean
   with
     Pre => Valid_Circle (Circle) and then Bounded (X) and then Bounded (Y);

   function Ellipse_Contains
     (Ellipse : Ks_Ellipse;
      X, Y    : Long_Float) return Boolean
   with
     Pre => Valid_Ellipse (Ellipse)
            and then Bounded (X) and then Bounded (Y);

   function Polygon_Contains
     (Polygon : access constant Ks_Polygon_Data;
      X, Y    : Long_Float) return Boolean
   with
     Pre => (Polygon = null or else Valid_Polygon (Polygon))
            and then Bounded (X) and then Bounded (Y);
   --  False for a polygon without vertices.

   function Section_Contains
     (Section : Ks_Circular_Annulus_Section;
      X, Y    : Long_Float) return Boolean
   with
     Pre => Valid_Circular_Annulus_Section (Section)
            and then Bounded (X) and then Bounded (Y);

end AMV.Kernels.Shapes;
