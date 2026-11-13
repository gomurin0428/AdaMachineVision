pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;

with AMV.Kernels.Numerics;

package body AMV.Kernels.Shapes with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package N renames AMV.Kernels.Numerics;

   Half_Pi : constant := Pi / 2.0;

   Half_Length : constant := Max_Length / 2.0;
   --  Half a side length or a radius: 2.0E150.

   Corner_Limit : constant := 8.0E150;
   --  Points computed from a valid shape before their bound is checked
   --  (a corner is at most Max_Value + 2 Half_Length away from the
   --  origin, an end point Max_Value + Max_Length): rounding included,
   --  well within this.

   Wide : constant := 1.0E152;
   --  Every intermediate value of the geometry below (differences of such
   --  points, their projections, sums of a few lengths) lies within this,
   --  far below the limit of N.Mul (about 3.4E153).

   Size_Tolerance : constant := 1.0E-9;
   --  The part of the boundary slack relative to the region's size L.

   Position_Tolerance : constant := 64.0 * Long_Float'Model_Epsilon;
   --  The part relative to P + L: 64 units in the last place.

   Initial_Capacity : constant := 16;
   --  The room for vertices a polygon gets when its first vertex is
   --  added; it doubles whenever it is full.

   procedure Free is new Ada.Unchecked_Deallocation
     (Vertex_Array, Vertex_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Polygon_Data, Ks_Polygon);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Polygon (Polygon : out Ks_Polygon)
   with
     Global => null,
     Post   => (if Polygon /= null
                then Polygon.Count = 0 and then Polygon.Vertices = null);
   --  A new handle without vertices, or null when the memory cannot be
   --  allocated. Trusted: the allocator raises Storage_Error, which SPARK
   --  cannot express.

   procedure Allocate_Polygon (Polygon : out Ks_Polygon)
     with SPARK_Mode => Off
   is
   begin
      Polygon := new Ks_Polygon_Data;
   exception
      when Storage_Error =>
         Polygon := null;
   end Allocate_Polygon;

   procedure Allocate_Vertices
     (Capacity : Positive;
      Vertices : out Vertex_Array_Access)
   with
     Global => null,
     Pre    => Capacity <= Max_Vertices,
     Post   => (if Vertices /= null
                then Vertices'First = 0
                     and then Vertices'Last = Capacity - 1);
   --  A new array of Capacity vertices (all (0, 0)), or null when the
   --  memory cannot be allocated. Trusted as above.

   procedure Allocate_Vertices
     (Capacity : Positive;
      Vertices : out Vertex_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Vertices := new Vertex_Array (0 .. Capacity - 1);
   exception
      when Storage_Error =>
         Vertices := null;
   end Allocate_Vertices;

   ---------------------------------------------------------------------
   --  Messages and failures
   ---------------------------------------------------------------------

   subtype Name_Text is String
     with Dynamic_Predicate =>
       Name_Text'First = 1 and then Name_Text'Length <= 80;
   --  A property or operation name that starts a message.

   function Image_Of (Value : Int64) return String
   with Pre  => Value > Int64'First,
        Post => Image_Of'Result'First = 1
                and then Image_Of'Result'Length in 1 .. 20;
   --  The decimal digits of Value, with a leading '-' when it is negative.

   function Image_Of (Value : Int64) return String is
      Text  : String (1 .. 20) := [others => '0'];
      Rest  : Int64 := abs Value;
      First : Positive;
   begin
      --  At most 19 digits; the first character is left for the sign.
      for K in reverse 2 .. 20 loop
         Text (K) := Character'Val (Character'Pos ('0') + Rest mod 10);
         Rest := Rest / 10;
         First := K;
         exit when Rest = 0;
         pragma Loop_Invariant (First = K and then Rest >= 1);
      end loop;
      if Value < 0 then
         First := First - 1;
         Text (First) := '-';
      end if;
      declare
         Last   : constant Natural := 21 - First;
         Result : constant String (1 .. Last) := Text (First .. 20);
      begin
         return Result;
      end;
   end Image_Of;

   procedure Bad (Status : out Ks_Status; Message : String)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Bad_Coordinate (Status : out Ks_Status; Name : Name_Text)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;
   --  "<Name> must be finite and within +/-1.0E150".

   procedure Bad_Coordinate (Status : out Ks_Status; Name : Name_Text) is
   begin
      Bad (Status, Name & " must be finite and within +/-1.0E150");
   end Bad_Coordinate;

   procedure Bad_Length
     (Status : out Ks_Status; Name : Name_Text; Value : Long_Float)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;
   --  "<Name> must be >= 0" for a negative Value, otherwise "<Name> must
   --  be finite and at most 4.0E150".

   procedure Bad_Length
     (Status : out Ks_Status; Name : Name_Text; Value : Long_Float) is
   begin
      if Value < 0.0 then
         Bad (Status, Name & " must be >= 0");
      else
         Bad (Status, Name & " must be finite and at most 4.0E150");
      end if;
   end Bad_Length;

   procedure Out_Of_Range (Status : out Ks_Status; What : Name_Text)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;
   --  "<What> would exceed the supported range".

   procedure Out_Of_Range (Status : out Ks_Status; What : Name_Text) is
   begin
      Bad (Status, What & " would exceed the supported range");
   end Out_Of_Range;

   procedure Bad_Transform (Status : out Ks_Status)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad_Transform (Status : out Ks_Status) is
   begin
      Bad (Status, "Transform must be finite and within +/-1.0E150");
   end Bad_Transform;

   procedure Check_Point
     (X, Y   : Long_Float;
      Status : out Ks_Status)
   with Post => Status_OK (Status)
                and then Succeeded (Status)
                           = (Bounded (X) and then Bounded (Y));
   --  The point argument of Contains_Point.

   procedure Check_Point
     (X, Y   : Long_Float;
      Status : out Ks_Status) is
   begin
      if not Bounded (X) then
         Bad_Coordinate (Status, "X");
      elsif not Bounded (Y) then
         Bad_Coordinate (Status, "Y");
      else
         Set_Success (Status);
      end if;
   end Check_Point;

   ---------------------------------------------------------------------
   --  Shared geometry
   ---------------------------------------------------------------------

   function Tolerance (Size, Position : Long_Float) return Long_Float is
     (Size_Tolerance * Size + Position_Tolerance * (Position + Size))
   with
     Pre  => Size in 0.0 .. Wide and then Position in 0.0 .. Wide,
     Post => Tolerance'Result in 0.0 .. 1.0E144;
   --  The boundary slack of a region of size L = Size whose position has
   --  the magnitude P = Position (see AMV.Shapes).

   function In_Span (Value, Bound_1, Bound_2, Slack : Long_Float)
     return Boolean
   is (Value >= Long_Float'Min (Bound_1, Bound_2) - Slack
       and then Value <= Long_Float'Max (Bound_1, Bound_2) + Slack)
   with Pre => abs Value <= Wide and then abs Bound_1 <= Wide
               and then abs Bound_2 <= Wide
               and then Slack in 0.0 .. Max_Slack;
   --  Value lies between the two bounds (in either order), widened by
   --  Slack on both sides.

   procedure Include (Value : Long_Float; Min_V, Max_V : in out Long_Float)
   with Pre  => Min_V <= Max_V,
        Post => Min_V = Long_Float'Min (Min_V'Old, Value)
                and then Max_V = Long_Float'Max (Max_V'Old, Value)
                and then Min_V <= Max_V;
   --  Widens [Min_V, Max_V] so that it contains Value.

   procedure Include (Value : Long_Float; Min_V, Max_V : in out Long_Float)
   is
   begin
      Min_V := Long_Float'Min (Min_V, Value);
      Max_V := Long_Float'Max (Max_V, Value);
   end Include;

   function Direction_Or_Zero (Y, X : Long_Float) return Long_Float is
     (if X = 0.0 and then Y = 0.0 then 0.0 else N.Direction (Y, X))
   with Post => Direction_Or_Zero'Result > -Pi
                and then Direction_Or_Zero'Result <= Pi;
   --  The angle of (X, Y) in (-Pi, Pi]; 0.0 for the zero vector.

   procedure Map_Point
     (T                  : KT.Ks_Transform_2D_Linear;
      X, Y               : Long_Float;
      Mapped_X, Mapped_Y : out Long_Float;
      OK                 : out Boolean)
   with
     Pre  => KT.Bounded (T) and then abs X <= Wide and then abs Y <= Wide,
     Post => (if OK then Bounded (Mapped_X) and then Bounded (Mapped_Y));
   --  (A X + B Y + Translation_X, C X + D Y + Translation_Y), evaluated
   --  as ks_transform_2d_linear_map_point evaluates it, for a point that
   --  may lie beyond Max_Value (a corner before its own check). OK is
   --  False when the result would exceed Max_Value.

   procedure Map_Point
     (T                  : KT.Ks_Transform_2D_Linear;
      X, Y               : Long_Float;
      Mapped_X, Mapped_Y : out Long_Float;
      OK                 : out Boolean)
   is
      MX : Long_Float := N.Mul (T.A, X) + N.Mul (T.B, Y);
      MY : Long_Float := N.Mul (T.C, X) + N.Mul (T.D, Y);
   begin
      MX := MX + T.Translation_X;
      MY := MY + T.Translation_Y;
      OK := Bounded (MX) and then Bounded (MY);
      Mapped_X := (if OK then MX else 0.0);
      Mapped_Y := (if OK then MY else 0.0);
   end Map_Point;

   procedure Map_Vector
     (T                  : KT.Ks_Transform_2D_Linear;
      X, Y               : Long_Float;
      Mapped_X, Mapped_Y : out Long_Float)
   with
     Pre  => KT.Bounded (T) and then abs X <= Wide and then abs Y <= Wide,
     Post => abs Mapped_X <= 2.0 ** 1021 and then abs Mapped_Y <= 2.0 ** 1021;
   --  (A X + B Y, C X + D Y), as ks_transform_2d_linear_map_vector
   --  evaluates it.

   procedure Map_Vector
     (T                  : KT.Ks_Transform_2D_Linear;
      X, Y               : Long_Float;
      Mapped_X, Mapped_Y : out Long_Float) is
   begin
      Mapped_X := N.Mul (T.A, X) + N.Mul (T.B, Y);
      Mapped_Y := N.Mul (T.C, X) + N.Mul (T.D, Y);
   end Map_Vector;

   type Similarity_Kind is (Not_Similar, Proper, Reflecting);
   --  Proper: rotation and uniform positive scaling (plus translation).
   --  Reflecting: the same followed by a mirror image (determinant < 0).

   procedure Classify
     (T      : KT.Ks_Transform_2D_Linear;
      Kind   : out Similarity_Kind;
      Status : out Ks_Status)
   with
     Pre  => KT.Bounded (T),
     Post => Status_OK (Status);
   --  Is_Similarity of T or, failing that, of T after the mirror
   --  (x, y) -> (x, -y) (which negates B and D), with
   --  Similarity_Tolerance.

   procedure Classify
     (T      : KT.Ks_Transform_2D_Linear;
      Kind   : out Similarity_Kind;
      Status : out Ks_Status)
   is
      Flag : Int32;
   begin
      Kind := Not_Similar;
      KT.Is_Similarity (T, Similarity_Tolerance, Flag, Status);
      if not Succeeded (Status) then
         return;
      elsif Flag = True_Value then
         Kind := Proper;
         return;
      end if;
      KT.Is_Similarity
        ((A => T.A, B => -T.B, C => T.C, D => -T.D,
          Translation_X => T.Translation_X,
          Translation_Y => T.Translation_Y),
         Similarity_Tolerance, Flag, Status);
      if Succeeded (Status) and then Flag = True_Value then
         Kind := Reflecting;
      end if;
   end Classify;

   procedure Map_Center_Radius
     (T                  : KT.Ks_Transform_2D_Linear;
      Center_X, Center_Y : Long_Float;
      Radius             : Long_Float;
      New_Center_X       : out Long_Float;
      New_Center_Y       : out Long_Float;
      New_Radius         : out Long_Float;
      Status             : out Ks_Status)
   with
     Pre  => KT.Bounded (T)
             and then Bounded (Center_X) and then Bounded (Center_Y)
             and then Length_Bounded (Radius),
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Bounded (New_Center_X)
                            and then Bounded (New_Center_Y)
                            and then Length_Bounded (New_Radius));
   --  The centre and radius of a circle, arc or annulus section under a
   --  (possibly reflecting) similarity: the centre is mapped and the
   --  radius multiplied by the length of the first matrix column (see
   --  AMV.Shapes).

   procedure Map_Center_Radius
     (T                  : KT.Ks_Transform_2D_Linear;
      Center_X, Center_Y : Long_Float;
      Radius             : Long_Float;
      New_Center_X       : out Long_Float;
      New_Center_Y       : out Long_Float;
      New_Radius         : out Long_Float;
      Status             : out Ks_Status)
   is
      OK     : Boolean;
      Scaled : Long_Float;
   begin
      New_Radius := 0.0;
      Map_Point (T, Center_X, Center_Y, New_Center_X, New_Center_Y, OK);
      if not OK then
         Out_Of_Range (Status, "Map: the mapped centre");
         return;
      end if;
      Scaled := N.Mul (Radius, N.Hypot (T.A, T.C));
      if Scaled > Max_Length then
         Out_Of_Range (Status, "Map: the mapped radius");
         return;
      end if;
      New_Radius := Scaled;
      Set_Success (Status);
   end Map_Center_Radius;

   procedure Map_Start_Angle
     (T               : KT.Ks_Transform_2D_Linear;
      Kind            : Similarity_Kind;
      Angle_Start     : Long_Float;
      New_Angle_Start : out Long_Float;
      Status          : out Ks_Status)
   with
     Pre  => KT.Bounded (T) and then Kind /= Not_Similar
             and then Bounded (Angle_Start),
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Bounded (New_Angle_Start));
   --  The start direction of an arc or annulus section under a (possibly
   --  reflecting) similarity, not normalised. A proper similarity turns
   --  every direction by the image of direction 0; a reflecting one sends
   --  A to (image of 0) - A. Working from the image of 0 keeps the start
   --  exact under an identity or a pure scaling.

   procedure Map_Start_Angle
     (T               : KT.Ks_Transform_2D_Linear;
      Kind            : Similarity_Kind;
      Angle_Start     : Long_Float;
      New_Angle_Start : out Long_Float;
      Status          : out Ks_Status)
   is
      Image_Of_Zero : Long_Float;
      Start         : Long_Float;
   begin
      New_Angle_Start := 0.0;
      KT.Map_Angle (T, 0.0, Image_Of_Zero, Status);
      if not Succeeded (Status) then
         Bad (Status, "Map: the transform is not a similarity");
         return;
      end if;
      if Kind = Reflecting then
         Start := Image_Of_Zero - Angle_Start;
      else
         Start := Angle_Start + Image_Of_Zero;
      end if;
      if not Bounded (Start) then
         Out_Of_Range (Status, "Map: the mapped Angle_Start");
         return;
      end if;
      New_Angle_Start := Start;
   end Map_Start_Angle;

   procedure Not_Similar_Failure (Status : out Ks_Status; Name : Name_Text)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;
   --  "<Name>.Map: the transform is not a similarity".

   procedure Not_Similar_Failure (Status : out Ks_Status; Name : Name_Text)
   is
   begin
      Bad (Status, Name & ".Map: the transform is not a similarity");
   end Not_Similar_Failure;

   ---------------------------------------------------------------------
   --  Argument checks of the records
   ---------------------------------------------------------------------

   procedure Check_Rectangle (R : Ks_Rectangle; Status : out Ks_Status)
   with Post => Status_OK (Status)
                and then Succeeded (Status) = Valid_Rectangle (R);

   procedure Check_Rectangle (R : Ks_Rectangle; Status : out Ks_Status) is
   begin
      if not Bounded (R.X) then
         Bad_Coordinate (Status, "Ks_Rectangle.X");
      elsif not Bounded (R.Y) then
         Bad_Coordinate (Status, "Ks_Rectangle.Y");
      elsif not Length_Bounded (R.Width) then
         Bad_Length (Status, "Ks_Rectangle.Width", R.Width);
      elsif not Length_Bounded (R.Height) then
         Bad_Length (Status, "Ks_Rectangle.Height", R.Height);
      else
         Set_Success (Status);
      end if;
   end Check_Rectangle;

   procedure Check_Rectangle_Affine
     (R : Ks_Rectangle_Affine; Status : out Ks_Status)
   with Post => Status_OK (Status)
                and then Succeeded (Status) = Valid_Rectangle_Affine (R);

   procedure Check_Rectangle_Affine
     (R : Ks_Rectangle_Affine; Status : out Ks_Status) is
   begin
      if not Bounded (R.Center_X) then
         Bad_Coordinate (Status, "Ks_Rectangle_Affine.Center_X");
      elsif not Bounded (R.Center_Y) then
         Bad_Coordinate (Status, "Ks_Rectangle_Affine.Center_Y");
      elsif not Length_Bounded (R.Side_X_Length) then
         Bad_Length
           (Status, "Ks_Rectangle_Affine.Side_X_Length", R.Side_X_Length);
      elsif not Length_Bounded (R.Side_Y_Length) then
         Bad_Length
           (Status, "Ks_Rectangle_Affine.Side_Y_Length", R.Side_Y_Length);
      elsif not Bounded (R.Rotation) then
         Bad_Coordinate (Status, "Ks_Rectangle_Affine.Rotation");
      elsif not Bounded (R.Skew) then
         Bad_Coordinate (Status, "Ks_Rectangle_Affine.Skew");
      else
         Set_Success (Status);
      end if;
   end Check_Rectangle_Affine;

   procedure Check_Circle (C : Ks_Circle; Status : out Ks_Status)
   with Post => Status_OK (Status)
                and then Succeeded (Status) = Valid_Circle (C);

   procedure Check_Circle (C : Ks_Circle; Status : out Ks_Status) is
   begin
      if not Bounded (C.Center_X) then
         Bad_Coordinate (Status, "Ks_Circle.Center_X");
      elsif not Bounded (C.Center_Y) then
         Bad_Coordinate (Status, "Ks_Circle.Center_Y");
      elsif not Length_Bounded (C.Radius) then
         Bad_Length (Status, "Ks_Circle.Radius", C.Radius);
      else
         Set_Success (Status);
      end if;
   end Check_Circle;

   procedure Check_Ellipse (E : Ks_Ellipse; Status : out Ks_Status)
   with Post => Status_OK (Status)
                and then Succeeded (Status) = Valid_Ellipse (E);

   procedure Check_Ellipse (E : Ks_Ellipse; Status : out Ks_Status) is
   begin
      if not Bounded (E.Center_X) then
         Bad_Coordinate (Status, "Ks_Ellipse.Center_X");
      elsif not Bounded (E.Center_Y) then
         Bad_Coordinate (Status, "Ks_Ellipse.Center_Y");
      elsif not Length_Bounded (E.Radius_X) then
         Bad_Length (Status, "Ks_Ellipse.Radius_X", E.Radius_X);
      elsif not Length_Bounded (E.Radius_Y) then
         Bad_Length (Status, "Ks_Ellipse.Radius_Y", E.Radius_Y);
      elsif not Bounded (E.Rotation) then
         Bad_Coordinate (Status, "Ks_Ellipse.Rotation");
      else
         Set_Success (Status);
      end if;
   end Check_Ellipse;

   procedure Check_Section
     (S : Ks_Circular_Annulus_Section; Status : out Ks_Status)
   with Post => Status_OK (Status)
                and then Succeeded (Status)
                           = Valid_Circular_Annulus_Section (S);

   procedure Check_Section
     (S : Ks_Circular_Annulus_Section; Status : out Ks_Status) is
   begin
      if not Bounded (S.Center_X) then
         Bad_Coordinate (Status, "Ks_Circular_Annulus_Section.Center_X");
      elsif not Bounded (S.Center_Y) then
         Bad_Coordinate (Status, "Ks_Circular_Annulus_Section.Center_Y");
      elsif not Length_Bounded (S.Radius) then
         Bad_Length (Status, "Ks_Circular_Annulus_Section.Radius", S.Radius);
      elsif not Bounded (S.Angle_Start) then
         Bad_Coordinate (Status, "Ks_Circular_Annulus_Section.Angle_Start");
      elsif not Bounded (S.Angle_Span) then
         Bad_Coordinate (Status, "Ks_Circular_Annulus_Section.Angle_Span");
      elsif S.Radial_Scale < 0.0 then
         Bad (Status, "Ks_Circular_Annulus_Section.Radial_Scale must be"
                      & " >= 0");
      elsif not (S.Radial_Scale <= Max_Value) then
         Bad (Status, "Ks_Circular_Annulus_Section.Radial_Scale must be"
                      & " finite and at most 1.0E150");
      elsif not (S.Radius * S.Radial_Scale <= Max_Length) then
         Out_Of_Range
           (Status, "Ks_Circular_Annulus_Section.Radius * Radial_Scale");
      else
         Set_Success (Status);
      end if;
   end Check_Section;

   procedure Check_Line (L : Ks_Line; Status : out Ks_Status)
   with Post => Status_OK (Status)
                and then Succeeded (Status) = Valid_Line (L);

   procedure Check_Line (L : Ks_Line; Status : out Ks_Status) is
   begin
      if not Bounded (L.X) then
         Bad_Coordinate (Status, "Ks_Line.X");
      elsif not Bounded (L.Y) then
         Bad_Coordinate (Status, "Ks_Line.Y");
      elsif not Bounded (L.Rotation) then
         Bad_Coordinate (Status, "Ks_Line.Rotation");
      else
         Set_Success (Status);
      end if;
   end Check_Line;

   procedure Check_Segment (S : Ks_Line_Segment; Status : out Ks_Status)
   with Post => Status_OK (Status)
                and then Succeeded (Status) = Valid_Line_Segment (S);

   procedure Check_Segment (S : Ks_Line_Segment; Status : out Ks_Status) is
   begin
      if not Bounded (S.Start_X) then
         Bad_Coordinate (Status, "Ks_Line_Segment.Start_X");
      elsif not Bounded (S.Start_Y) then
         Bad_Coordinate (Status, "Ks_Line_Segment.Start_Y");
      elsif not Bounded (S.End_X) then
         Bad_Coordinate (Status, "Ks_Line_Segment.End_X");
      elsif not Bounded (S.End_Y) then
         Bad_Coordinate (Status, "Ks_Line_Segment.End_Y");
      else
         Set_Success (Status);
      end if;
   end Check_Segment;

   procedure Check_Marker (M : Ks_Point_Marker; Status : out Ks_Status)
   with Post => Status_OK (Status)
                and then Succeeded (Status) = Valid_Point_Marker (M);

   procedure Check_Marker (M : Ks_Point_Marker; Status : out Ks_Status) is
   begin
      if not Bounded (M.X) then
         Bad_Coordinate (Status, "Ks_Point_Marker.X");
      elsif not Bounded (M.Y) then
         Bad_Coordinate (Status, "Ks_Point_Marker.Y");
      elsif not Bounded (M.Rotation) then
         Bad_Coordinate (Status, "Ks_Point_Marker.Rotation");
      else
         Set_Success (Status);
      end if;
   end Check_Marker;

   procedure Check_Arc (A : Ks_Circular_Arc; Status : out Ks_Status)
   with Post => Status_OK (Status)
                and then Succeeded (Status) = Valid_Circular_Arc (A);

   procedure Check_Arc (A : Ks_Circular_Arc; Status : out Ks_Status) is
   begin
      if not Bounded (A.Center_X) then
         Bad_Coordinate (Status, "Ks_Circular_Arc.Center_X");
      elsif not Bounded (A.Center_Y) then
         Bad_Coordinate (Status, "Ks_Circular_Arc.Center_Y");
      elsif not Length_Bounded (A.Radius) then
         Bad_Length (Status, "Ks_Circular_Arc.Radius", A.Radius);
      elsif not Bounded (A.Angle_Start) then
         Bad_Coordinate (Status, "Ks_Circular_Arc.Angle_Start");
      elsif not Bounded (A.Angle_Span) then
         Bad_Coordinate (Status, "Ks_Circular_Arc.Angle_Span");
      else
         Set_Success (Status);
      end if;
   end Check_Arc;

   ---------------------------------------------------------------------
   --  CogRectangle
   ---------------------------------------------------------------------

   procedure Set_XY_Width_Height
     (X, Y, Width, Height : Long_Float;
      Result              : out Ks_Rectangle;
      Status              : out Ks_Status)
   is
      Candidate : constant Ks_Rectangle := (X, Y, Width, Height);
   begin
      Result := (others => <>);
      Check_Rectangle (Candidate, Status);
      if Succeeded (Status) then
         Result := Candidate;
      end if;
   end Set_XY_Width_Height;

   procedure Set_Center_Width_Height
     (Center_X, Center_Y, Width, Height : Long_Float;
      Result                            : out Ks_Rectangle;
      Status                            : out Ks_Status) is
   begin
      Result := (others => <>);
      if not Bounded (Center_X) then
         Bad_Coordinate (Status, "Ks_Rectangle.Center_X");
      elsif not Bounded (Center_Y) then
         Bad_Coordinate (Status, "Ks_Rectangle.Center_Y");
      elsif not Length_Bounded (Width) then
         Bad_Length (Status, "Ks_Rectangle.Width", Width);
      elsif not Length_Bounded (Height) then
         Bad_Length (Status, "Ks_Rectangle.Height", Height);
      else
         declare
            X : constant Long_Float := Center_X - 0.5 * Width;
            Y : constant Long_Float := Center_Y - 0.5 * Height;
         begin
            if not (Bounded (X) and then Bounded (Y)) then
               Out_Of_Range (Status, "Ks_Rectangle.X or Y");
               return;
            end if;
            Result := (X, Y, Width, Height);
            Set_Success (Status);
         end;
      end if;
   end Set_Center_Width_Height;

   procedure Get_Center_Width_Height
     (Rectangle                         : Ks_Rectangle;
      Center_X, Center_Y, Width, Height : out Long_Float;
      Status                            : out Ks_Status)
   is
      R : Ks_Rectangle renames Rectangle;
   begin
      Center_X := 0.0;
      Center_Y := 0.0;
      Width := 0.0;
      Height := 0.0;
      Check_Rectangle (R, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         CX : constant Long_Float := R.X + 0.5 * R.Width;
         CY : constant Long_Float := R.Y + 0.5 * R.Height;
      begin
         if not (Bounded (CX) and then Bounded (CY)) then
            Out_Of_Range (Status, "Ks_Rectangle.Center_X or Center_Y");
            return;
         end if;
         Center_X := CX;
         Center_Y := CY;
         Width := R.Width;
         Height := R.Height;
      end;
   end Get_Center_Width_Height;

   function Rectangle_Slack (R : Ks_Rectangle) return Long_Float is
     (Tolerance (Size     => R.Width + R.Height,
                 Position => abs R.X + abs R.Y));

   function Rectangle_Contains
     (Rectangle : Ks_Rectangle;
      X, Y      : Long_Float) return Boolean
   is
      R   : Ks_Rectangle renames Rectangle;
      Tol : constant Long_Float := Rectangle_Slack (R);
   begin
      return X >= R.X - Tol
        and then X <= R.X + R.Width + Tol
        and then Y >= R.Y - Tol
        and then Y <= R.Y + R.Height + Tol;
   end Rectangle_Contains;

   procedure Contains_Point
     (Rectangle : Ks_Rectangle;
      X, Y      : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status) is
   begin
      Result := False_Value;
      Check_Rectangle (Rectangle, Status);
      if Succeeded (Status) then
         Check_Point (X, Y, Status);
      end if;
      if Succeeded (Status) and then Rectangle_Contains (Rectangle, X, Y)
      then
         Result := True_Value;
      end if;
   end Contains_Point;

   procedure Boundary_Slack
     (Rectangle : Ks_Rectangle;
      Result    : out Long_Float;
      Status    : out Ks_Status) is
   begin
      Result := 0.0;
      Check_Rectangle (Rectangle, Status);
      if Succeeded (Status) then
         Result := Rectangle_Slack (Rectangle);
      end if;
   end Boundary_Slack;

   procedure Get_Bounding_Box
     (Rectangle                  : Ks_Rectangle;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float;
      Status                     : out Ks_Status)
   is
      R : Ks_Rectangle renames Rectangle;
   begin
      Min_X := 0.0;
      Min_Y := 0.0;
      Max_X := 0.0;
      Max_Y := 0.0;
      Check_Rectangle (R, Status);
      if not Succeeded (Status) then
         return;
      elsif not (Bounded (R.X + R.Width) and then Bounded (R.Y + R.Height))
      then
         Out_Of_Range
           (Status, "Ks_Rectangle.Get_Bounding_Box: the far corner");
         return;
      end if;
      Min_X := R.X;
      Min_Y := R.Y;
      Max_X := R.X + R.Width;
      Max_Y := R.Y + R.Height;
   end Get_Bounding_Box;

   procedure Area
     (Rectangle : Ks_Rectangle;
      Result    : out Long_Float;
      Status    : out Ks_Status) is
   begin
      Result := 0.0;
      Check_Rectangle (Rectangle, Status);
      if Succeeded (Status) then
         Result := N.Mul (Rectangle.Width, Rectangle.Height);
      end if;
   end Area;

   procedure Perimeter
     (Rectangle : Ks_Rectangle;
      Result    : out Long_Float;
      Status    : out Ks_Status) is
   begin
      Result := 0.0;
      Check_Rectangle (Rectangle, Status);
      if Succeeded (Status) then
         Result := 2.0 * (Rectangle.Width + Rectangle.Height);
      end if;
   end Perimeter;

   ---------------------------------------------------------------------
   --  CogRectangleAffine geometry
   ---------------------------------------------------------------------

   type Affine_Frame is record
      Center_X, Center_Y : Long_Float;
      DX_X, DX_Y         : Long_Float;  --  unit vector along side X
      DY_X, DY_Y         : Long_Float;  --  unit vector along side Y
      HX_X, HX_Y         : Long_Float;  --  half of side X
      HY_X, HY_Y         : Long_Float;  --  half of side Y
   end record;
   --  The parallelogram's geometry: its corners are Center +/- HX +/- HY.

   function Frame_OK (F : Affine_Frame) return Boolean is
     (Bounded (F.Center_X) and then Bounded (F.Center_Y)
      and then abs F.DX_X <= 1.0 and then abs F.DX_Y <= 1.0
      and then abs F.DY_X <= 1.0 and then abs F.DY_Y <= 1.0
      and then abs F.HX_X <= Half_Length and then abs F.HX_Y <= Half_Length
      and then abs F.HY_X <= Half_Length
      and then abs F.HY_Y <= Half_Length);

   function Frame_Of (R : Ks_Rectangle_Affine) return Affine_Frame
   with Pre  => Valid_Rectangle_Affine (R),
        Post => Frame_OK (Frame_Of'Result);

   function Frame_Of (R : Ks_Rectangle_Affine) return Affine_Frame is
      Cos_X  : constant Long_Float := EF.Cos (R.Rotation);
      Sin_X  : constant Long_Float := EF.Sin (R.Rotation);
      Cos_Y  : constant Long_Float := EF.Cos (R.Rotation + R.Skew);
      Sin_Y  : constant Long_Float := EF.Sin (R.Rotation + R.Skew);
      Half_X : constant Long_Float := 0.5 * R.Side_X_Length;
      Half_Y : constant Long_Float := 0.5 * R.Side_Y_Length;
   begin
      return (Center_X => R.Center_X,
              Center_Y => R.Center_Y,
              DX_X     => Cos_X,
              DX_Y     => Sin_X,
              DY_X     => -Sin_Y,
              DY_Y     => Cos_Y,
              HX_X     => N.Times_Unit (Half_X, Cos_X),
              HX_Y     => N.Times_Unit (Half_X, Sin_X),
              HY_X     => -N.Times_Unit (Half_Y, Sin_Y),
              HY_Y     => N.Times_Unit (Half_Y, Cos_Y));
   end Frame_Of;

   function Corners_Of (F : Affine_Frame) return Ks_Rectangle_Affine_Corners
   is (Origin_X          => F.Center_X - F.HX_X - F.HY_X,
       Origin_Y          => F.Center_Y - F.HX_Y - F.HY_Y,
       Corner_X_X        => F.Center_X + F.HX_X - F.HY_X,
       Corner_X_Y        => F.Center_Y + F.HX_Y - F.HY_Y,
       Corner_Y_X        => F.Center_X - F.HX_X + F.HY_X,
       Corner_Y_Y        => F.Center_Y - F.HX_Y + F.HY_Y,
       Corner_Opposite_X => F.Center_X + F.HX_X + F.HY_X,
       Corner_Opposite_Y => F.Center_Y + F.HX_Y + F.HY_Y)
   with Pre  => Frame_OK (F),
        Post => abs Corners_Of'Result.Origin_X <= Corner_Limit
                and then abs Corners_Of'Result.Origin_Y <= Corner_Limit
                and then abs Corners_Of'Result.Corner_X_X <= Corner_Limit
                and then abs Corners_Of'Result.Corner_X_Y <= Corner_Limit
                and then abs Corners_Of'Result.Corner_Y_X <= Corner_Limit
                and then abs Corners_Of'Result.Corner_Y_Y <= Corner_Limit
                and then abs Corners_Of'Result.Corner_Opposite_X
                           <= Corner_Limit
                and then abs Corners_Of'Result.Corner_Opposite_Y
                           <= Corner_Limit;
   --  The four corners, not yet checked against Max_Value.

   function Corners_Bounded (C : Ks_Rectangle_Affine_Corners) return Boolean
   is (Bounded (C.Origin_X) and then Bounded (C.Origin_Y)
       and then Bounded (C.Corner_X_X) and then Bounded (C.Corner_X_Y)
       and then Bounded (C.Corner_Y_X) and then Bounded (C.Corner_Y_Y)
       and then Bounded (C.Corner_Opposite_X)
       and then Bounded (C.Corner_Opposite_Y));

   function Affine_Slack (R : Ks_Rectangle_Affine) return Long_Float is
     (Tolerance (Size     => R.Side_X_Length + R.Side_Y_Length,
                 Position => abs R.Center_X + abs R.Center_Y))
   with Pre  => Valid_Rectangle_Affine (R),
        Post => Affine_Slack'Result in 0.0 .. 1.0E144;
   --  The boundary slack of Contains_Point.

   procedure From_Corners
     (Origin_X, Origin_Y, Corner_X_X, Corner_X_Y : Long_Float;
      Corner_Y_X, Corner_Y_Y                     : Long_Float;
      Result : out Ks_Rectangle_Affine;
      Status : out Ks_Status)
   with
     Pre  => Bounded (Origin_X) and then Bounded (Origin_Y)
             and then Bounded (Corner_X_X) and then Bounded (Corner_X_Y)
             and then Bounded (Corner_Y_X) and then Bounded (Corner_Y_Y),
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Rectangle_Affine (Result)
                            and then Result.Rotation > -Pi
                            and then Result.Rotation <= Pi
                            and then Result.Skew > -Pi
                            and then Result.Skew <= Pi);
   --  Set_Origin_Corner_X_Corner_Y for bounded corners. Side Y points
   --  along Rotation + Skew + Pi/2. A side of zero length has no
   --  direction: the other side then decides the rotation and the skew is
   --  0 (both are 0 when the parallelogram is a point).

   procedure From_Corners
     (Origin_X, Origin_Y, Corner_X_X, Corner_X_Y : Long_Float;
      Corner_Y_X, Corner_Y_Y                     : Long_Float;
      Result : out Ks_Rectangle_Affine;
      Status : out Ks_Status)
   is
      VX_X : constant Long_Float := Corner_X_X - Origin_X;
      VX_Y : constant Long_Float := Corner_X_Y - Origin_Y;
      VY_X : constant Long_Float := Corner_Y_X - Origin_X;
      VY_Y : constant Long_Float := Corner_Y_Y - Origin_Y;
      Length_X : constant Long_Float := N.Hypot (VX_X, VX_Y);
      Length_Y : constant Long_Float := N.Hypot (VY_X, VY_Y);
      New_Rotation : Long_Float := 0.0;
      New_Skew     : Long_Float := 0.0;
      CX : constant Long_Float := Origin_X + 0.5 * (VX_X + VY_X);
      CY : constant Long_Float := Origin_Y + 0.5 * (VX_Y + VY_Y);
   begin
      Result := (others => <>);
      if Length_X > 0.0 then
         New_Rotation := N.Direction (VX_Y, VX_X);
         if Length_Y > 0.0 then
            New_Skew := N.Reduce_Two_Pi
              (N.Direction (VY_Y, VY_X) - Half_Pi - New_Rotation);
         end if;
      elsif Length_Y > 0.0 then
         New_Rotation := N.Reduce_Two_Pi (N.Direction (VY_Y, VY_X) - Half_Pi);
      end if;
      if not (Bounded (CX) and then Bounded (CY)) then
         Out_Of_Range (Status, "Ks_Rectangle_Affine.Center_X or Center_Y");
         return;
      end if;
      Result := (Center_X      => CX,
                 Center_Y      => CY,
                 Side_X_Length => Length_X,
                 Side_Y_Length => Length_Y,
                 Rotation      => New_Rotation,
                 Skew          => New_Skew);
      Set_Success (Status);
   end From_Corners;

   ---------------------------------------------------------------------
   --  CogRectangle: Map and the bounding box conversion
   ---------------------------------------------------------------------

   procedure Map
     (Rectangle        : Ks_Rectangle;
      Transform        : KT.Ks_Transform_2D_Linear;
      Result_Type      : out Int32;
      Rectangle_Result : out Ks_Rectangle;
      Affine_Result    : out Ks_Rectangle_Affine;
      Status           : out Ks_Status)
   is
      R    : Ks_Rectangle renames Rectangle;
      Flag : Int32;
      OK_0, OK_1, OK_2       : Boolean;
      X0, Y0, X1, Y1, X2, Y2 : Long_Float;
   begin
      Result_Type := 0;
      Rectangle_Result := (others => <>);
      Affine_Result := (others => <>);
      Check_Rectangle (R, Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Transform) then
         Bad_Transform (Status);
         return;
      end if;
      KT.Is_Axis_Aligned (Transform, Similarity_Tolerance, Flag, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Flag = True_Value then
         --  Two opposite corners determine the image; a reflection or a
         --  negative scale only swaps which of them is the minimum.
         Map_Point (Transform, R.X, R.Y, X0, Y0, OK_0);
         Map_Point (Transform, R.X + R.Width, R.Y + R.Height, X1, Y1, OK_1);
         if not (OK_0 and then OK_1) then
            Out_Of_Range (Status, "Ks_Rectangle.Map: the mapped rectangle");
            return;
         end if;
         Rectangle_Result := (X      => Long_Float'Min (X0, X1),
                              Y      => Long_Float'Min (Y0, Y1),
                              Width  => abs (X1 - X0),
                              Height => abs (Y1 - Y0));
         Result_Type := Shape_Rectangle;
         Set_Success (Status);
         return;
      end if;
      Map_Point (Transform, R.X, R.Y, X0, Y0, OK_0);
      Map_Point (Transform, R.X + R.Width, R.Y, X1, Y1, OK_1);
      Map_Point (Transform, R.X, R.Y + R.Height, X2, Y2, OK_2);
      if not (OK_0 and then OK_1 and then OK_2) then
         Out_Of_Range (Status, "Ks_Rectangle.Map: the mapped rectangle");
         return;
      end if;
      From_Corners (X0, Y0, X1, Y1, X2, Y2, Affine_Result, Status);
      if Succeeded (Status) then
         Result_Type := Shape_Rectangle_Affine;
      end if;
   end Map;

   procedure Rectangle_From_Bounding_Box
     (Min_X, Min_Y, Max_X, Max_Y : Long_Float;
      Result                     : out Ks_Rectangle;
      Status                     : out Ks_Status) is
   begin
      Result := (others => <>);
      if not Bounded (Min_X) then
         Bad_Coordinate (Status, "Min_X");
      elsif not Bounded (Min_Y) then
         Bad_Coordinate (Status, "Min_Y");
      elsif not Bounded (Max_X) then
         Bad_Coordinate (Status, "Max_X");
      elsif not Bounded (Max_Y) then
         Bad_Coordinate (Status, "Max_Y");
      elsif Max_X < Min_X then
         Bad (Status, "Max_X must be >= Min_X");
      elsif Max_Y < Min_Y then
         Bad (Status, "Max_Y must be >= Min_Y");
      else
         Result := (Min_X, Min_Y, Max_X - Min_X, Max_Y - Min_Y);
         Set_Success (Status);
      end if;
   end Rectangle_From_Bounding_Box;

   ---------------------------------------------------------------------
   --  CogRectangleAffine
   ---------------------------------------------------------------------

   procedure Set_Center_Lengths_Rotation_Skew
     (Center_X, Center_Y, Side_X_Length, Side_Y_Length : Long_Float;
      Rotation, Skew                                   : Long_Float;
      Result : out Ks_Rectangle_Affine;
      Status : out Ks_Status)
   is
      Candidate : constant Ks_Rectangle_Affine :=
        (Center_X, Center_Y, Side_X_Length, Side_Y_Length, Rotation, Skew);
   begin
      Result := (others => <>);
      Check_Rectangle_Affine (Candidate, Status);
      if Succeeded (Status) then
         Result := Candidate;
      end if;
   end Set_Center_Lengths_Rotation_Skew;

   procedure Set_Origin_Lengths_Rotation_Skew
     (Origin_X, Origin_Y, Side_X_Length, Side_Y_Length : Long_Float;
      Rotation, Skew                                   : Long_Float;
      Result : out Ks_Rectangle_Affine;
      Status : out Ks_Status)
   is
      Candidate : constant Ks_Rectangle_Affine :=
        (Origin_X, Origin_Y, Side_X_Length, Side_Y_Length, Rotation, Skew);
   begin
      Result := (others => <>);
      --  The candidate holds the origin where the centre goes, so that
      --  the messages name the properties; the centre is the origin plus
      --  half of both sides (the half-side vectors of the frame do not
      --  depend on the centre).
      if not Bounded (Origin_X) then
         Bad_Coordinate (Status, "Ks_Rectangle_Affine.Origin_X");
         return;
      elsif not Bounded (Origin_Y) then
         Bad_Coordinate (Status, "Ks_Rectangle_Affine.Origin_Y");
         return;
      end if;
      Check_Rectangle_Affine (Candidate, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         F  : constant Affine_Frame := Frame_Of (Candidate);
         CX : constant Long_Float := Origin_X + F.HX_X + F.HY_X;
         CY : constant Long_Float := Origin_Y + F.HX_Y + F.HY_Y;
      begin
         if not (Bounded (CX) and then Bounded (CY)) then
            Out_Of_Range (Status, "Ks_Rectangle_Affine.Center_X or Center_Y");
            return;
         end if;
         Result := (CX, CY, Side_X_Length, Side_Y_Length, Rotation, Skew);
      end;
   end Set_Origin_Lengths_Rotation_Skew;

   procedure Set_Origin_Corner_X_Corner_Y
     (Origin_X, Origin_Y, Corner_X_X, Corner_X_Y : Long_Float;
      Corner_Y_X, Corner_Y_Y                     : Long_Float;
      Result : out Ks_Rectangle_Affine;
      Status : out Ks_Status) is
   begin
      Result := (others => <>);
      if not Bounded (Origin_X) then
         Bad_Coordinate (Status, "Origin_X");
      elsif not Bounded (Origin_Y) then
         Bad_Coordinate (Status, "Origin_Y");
      elsif not Bounded (Corner_X_X) then
         Bad_Coordinate (Status, "Corner_X_X");
      elsif not Bounded (Corner_X_Y) then
         Bad_Coordinate (Status, "Corner_X_Y");
      elsif not Bounded (Corner_Y_X) then
         Bad_Coordinate (Status, "Corner_Y_X");
      elsif not Bounded (Corner_Y_Y) then
         Bad_Coordinate (Status, "Corner_Y_Y");
      else
         From_Corners (Origin_X, Origin_Y, Corner_X_X, Corner_X_Y,
                       Corner_Y_X, Corner_Y_Y, Result, Status);
      end if;
   end Set_Origin_Corner_X_Corner_Y;

   procedure Get_Corners
     (Rectangle : Ks_Rectangle_Affine;
      Result    : out Ks_Rectangle_Affine_Corners;
      Status    : out Ks_Status) is
   begin
      Result := (others => <>);
      Check_Rectangle_Affine (Rectangle, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         C : constant Ks_Rectangle_Affine_Corners :=
           Corners_Of (Frame_Of (Rectangle));
      begin
         if not Corners_Bounded (C) then
            Out_Of_Range (Status, "Ks_Rectangle_Affine: a corner");
            return;
         end if;
         Result := C;
      end;
   end Get_Corners;

   procedure Get_Parent_From_Child_Transform
     (Rectangle : Ks_Rectangle_Affine;
      Result    : out KT.Ks_Transform_2D_Linear;
      Status    : out Ks_Status) is
   begin
      Result := (others => <>);
      Check_Rectangle_Affine (Rectangle, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         F  : constant Affine_Frame := Frame_Of (Rectangle);
         OX : constant Long_Float := F.Center_X - F.HX_X - F.HY_X;
         OY : constant Long_Float := F.Center_Y - F.HX_Y - F.HY_Y;
      begin
         if not (Bounded (OX) and then Bounded (OY)) then
            Out_Of_Range (Status, "Ks_Rectangle_Affine: the corner origin");
            return;
         end if;
         --  Child (u, v) maps to Origin + u * DX + v * DY.
         Result := (A             => F.DX_X,
                    B             => F.DY_X,
                    C             => F.DX_Y,
                    D             => F.DY_Y,
                    Translation_X => OX,
                    Translation_Y => OY);
      end;
   end Get_Parent_From_Child_Transform;

   function Rectangle_Affine_Contains
     (Rectangle : Ks_Rectangle_Affine;
      X, Y      : Long_Float) return Boolean is
   begin
      declare
         F   : constant Affine_Frame := Frame_Of (Rectangle);
         C   : constant Ks_Rectangle_Affine_Corners := Corners_Of (F);
         Tol : constant Long_Float := Affine_Slack (Rectangle);
         --  The point relative to the corner origin.
         PX  : constant Long_Float := X - C.Origin_X;
         PY  : constant Long_Float := Y - C.Origin_Y;
         SX  : constant Long_Float := Rectangle.Side_X_Length;
         SY  : constant Long_Float := Rectangle.Side_Y_Length;
         --  cross (DX, DY) = cos Skew and dot (DX, DY) = -sin Skew.
         Cross_XY : constant Long_Float :=
           N.Times_Unit (F.DX_X, F.DY_Y) - N.Times_Unit (F.DX_Y, F.DY_X);
         Dot_XY   : constant Long_Float :=
           N.Times_Unit (F.DX_X, F.DY_X) + N.Times_Unit (F.DX_Y, F.DY_Y);
         --  Signed distances of P from the lines through the origin along
         --  DX and along DY (see AMV.Shapes), and its projections on DX
         --  and DY.
         Dist_X : constant Long_Float :=
           N.Times_Unit (PY, F.DX_X) - N.Times_Unit (PX, F.DX_Y);
         Dist_Y : constant Long_Float :=
           N.Times_Unit (PX, F.DY_Y) - N.Times_Unit (PY, F.DY_X);
         Proj_X : constant Long_Float :=
           N.Times_Unit (PX, F.DX_X) + N.Times_Unit (PY, F.DX_Y);
         Proj_Y : constant Long_Float :=
           N.Times_Unit (PX, F.DY_X) + N.Times_Unit (PY, F.DY_Y);
         --  The corners project on DX at 0, SX, SY * Dot_XY,
         --  SX + SY * Dot_XY and on DY at 0, SY, SX * Dot_XY,
         --  SY + SX * Dot_XY.
         Along_X : constant Long_Float := N.Times_Small (SY, Dot_XY);
         Along_Y : constant Long_Float := N.Times_Small (SX, Dot_XY);
      begin
         --  The first two slabs (between opposite sides) define the
         --  parallelogram; the projection slabs bound its extent when the
         --  sides are (nearly) collinear.
         if In_Span (Dist_X, 0.0, N.Times_Small (SY, Cross_XY), Tol)
           and then In_Span (Dist_Y, 0.0, N.Times_Small (SX, Cross_XY), Tol)
           and then In_Span (Proj_X,
                             Long_Float'Min (0.0, SX)
                             + Long_Float'Min (0.0, Along_X),
                             Long_Float'Max (0.0, SX)
                             + Long_Float'Max (0.0, Along_X),
                             Tol)
           and then In_Span (Proj_Y,
                             Long_Float'Min (0.0, SY)
                             + Long_Float'Min (0.0, Along_Y),
                             Long_Float'Max (0.0, SY)
                             + Long_Float'Max (0.0, Along_Y),
                             Tol)
         then
            return True;
         end if;
         return False;
      end;
   end Rectangle_Affine_Contains;

   procedure Contains_Point
     (Rectangle : Ks_Rectangle_Affine;
      X, Y      : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status) is
   begin
      Result := False_Value;
      Check_Rectangle_Affine (Rectangle, Status);
      if Succeeded (Status) then
         Check_Point (X, Y, Status);
      end if;
      if Succeeded (Status)
        and then Rectangle_Affine_Contains (Rectangle, X, Y)
      then
         Result := True_Value;
      end if;
   end Contains_Point;

   procedure Boundary_Slack
     (Rectangle : Ks_Rectangle_Affine;
      Result    : out Long_Float;
      Status    : out Ks_Status) is
   begin
      Result := 0.0;
      Check_Rectangle_Affine (Rectangle, Status);
      if Succeeded (Status) then
         --  Every accepted point is within Sqrt (2) times the slack of the
         --  parallelogram (see AMV.Shapes); twice it leaves room for
         --  rounding.
         Result := 2.0 * Affine_Slack (Rectangle);
      end if;
   end Boundary_Slack;

   procedure Get_Bounding_Box
     (Rectangle                  : Ks_Rectangle_Affine;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float;
      Status                     : out Ks_Status) is
   begin
      Min_X := 0.0;
      Min_Y := 0.0;
      Max_X := 0.0;
      Max_Y := 0.0;
      Check_Rectangle_Affine (Rectangle, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         F : constant Affine_Frame := Frame_Of (Rectangle);
         --  The corners are Center +/- HX +/- HY.
         Half_Width  : constant Long_Float := abs F.HX_X + abs F.HY_X;
         Half_Height : constant Long_Float := abs F.HX_Y + abs F.HY_Y;
         X0 : constant Long_Float := F.Center_X - Half_Width;
         X1 : constant Long_Float := F.Center_X + Half_Width;
         Y0 : constant Long_Float := F.Center_Y - Half_Height;
         Y1 : constant Long_Float := F.Center_Y + Half_Height;
      begin
         if not (Bounded (X0) and then Bounded (X1) and then Bounded (Y0)
                 and then Bounded (Y1))
         then
            Out_Of_Range
              (Status, "Ks_Rectangle_Affine.Get_Bounding_Box: the box");
            return;
         end if;
         Min_X := X0;
         Max_X := X1;
         Min_Y := Y0;
         Max_Y := Y1;
      end;
   end Get_Bounding_Box;

   procedure Area
     (Rectangle : Ks_Rectangle_Affine;
      Result    : out Long_Float;
      Status    : out Ks_Status) is
   begin
      Result := 0.0;
      Check_Rectangle_Affine (Rectangle, Status);
      if Succeeded (Status) then
         Result := N.Times_Unit
           (N.Mul (Rectangle.Side_X_Length, Rectangle.Side_Y_Length),
            abs EF.Cos (Rectangle.Skew));
      end if;
   end Area;

   procedure Map
     (Rectangle : Ks_Rectangle_Affine;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Rectangle_Affine;
      Status    : out Ks_Status)
   is
      OK_0, OK_1, OK_2       : Boolean;
      X0, Y0, X1, Y1, X2, Y2 : Long_Float;
   begin
      Result := (others => <>);
      Check_Rectangle_Affine (Rectangle, Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Transform) then
         Bad_Transform (Status);
         return;
      end if;
      declare
         C : constant Ks_Rectangle_Affine_Corners :=
           Corners_Of (Frame_Of (Rectangle));
      begin
         Map_Point (Transform, C.Origin_X, C.Origin_Y, X0, Y0, OK_0);
         Map_Point (Transform, C.Corner_X_X, C.Corner_X_Y, X1, Y1, OK_1);
         Map_Point (Transform, C.Corner_Y_X, C.Corner_Y_Y, X2, Y2, OK_2);
      end;
      if not (OK_0 and then OK_1 and then OK_2) then
         Out_Of_Range
           (Status, "Ks_Rectangle_Affine.Map: the mapped rectangle");
         return;
      end if;
      From_Corners (X0, Y0, X1, Y1, X2, Y2, Result, Status);
   end Map;

   ---------------------------------------------------------------------
   --  CogEllipse geometry (used by CogCircle.Map as well)
   ---------------------------------------------------------------------

   function Axis_Angle (E, F, G, H : Long_Float) return Long_Float
   with Post => Axis_Angle'Result >= -Pi and then Axis_Angle'Result <= Pi;
   --  The direction (Alpha + Beta) / 2 of the major axis of the image of
   --  an ellipse (see Map_Ellipse), where Alpha is the direction of
   --  (E, H) and Beta that of (F, G); the direction of the one that is
   --  not zero for a circle, whose every axis will do; 0.0 for a point.

   function Axis_Angle (E, F, G, H : Long_Float) return Long_Float is
      Rotation_Part   : constant Boolean := E /= 0.0 or else H /= 0.0;
      Reflection_Part : constant Boolean := F /= 0.0 or else G /= 0.0;
   begin
      if Rotation_Part and then Reflection_Part then
         return 0.5 * (N.Direction (H, E) + N.Direction (G, F));
      elsif Rotation_Part then
         return N.Direction (H, E);
      elsif Reflection_Part then
         return N.Direction (G, F);
      end if;
      return 0.0;
   end Axis_Angle;

   subtype Quarter is Natural range 0 .. 3;
   --  K for the axis direction Theta + K Pi/2.

   function Quarter_Turn (Theta : Long_Float; K : Quarter) return Long_Float
   is (N.Reduce_Two_Pi (Theta + Long_Float (K) * Half_Pi))
   with Pre  => Theta >= -Pi and then Theta <= Pi,
        Post => Quarter_Turn'Result > -Pi and then Quarter_Turn'Result <= Pi;
   --  Theta + K Pi/2, reduced into (-Pi, Pi].

   function Nearest_Quarter (Theta, Reference : Long_Float) return Quarter
   with Pre => Theta >= -Pi and then Theta <= Pi
               and then Reference >= -Pi and then Reference <= Pi;
   --  The K whose direction Theta + K Pi/2 is nearest to Reference (the
   --  first of equally near ones).

   function Nearest_Quarter (Theta, Reference : Long_Float) return Quarter
   is
      Best      : Quarter := 0;
      Best_Diff : Long_Float := Long_Float'Last;
   begin
      for K in Quarter loop
         declare
            Diff : constant Long_Float :=
              abs N.Reduce_Two_Pi
                (Theta + Long_Float (K) * Half_Pi - Reference);
         begin
            if Diff < Best_Diff then
               Best_Diff := Diff;
               Best := K;
            end if;
         end;
      end loop;
      return Best;
   end Nearest_Quarter;

   procedure Map_Ellipse
     (Center_X, Center_Y, Radius_X, Radius_Y, Rotation : Long_Float;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Ellipse;
      Status    : out Ks_Status)
   with
     Pre  => Bounded (Center_X) and then Bounded (Center_Y)
             and then Length_Bounded (Radius_X)
             and then Length_Bounded (Radius_Y)
             and then Bounded (Rotation) and then KT.Bounded (Transform),
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Ellipse (Result)
                            and then Result.Rotation > -Pi
                            and then Result.Rotation <= Pi);
   --  The image under Transform of the ellipse with these parameters.

   procedure Map_Ellipse
     (Center_X, Center_Y, Radius_X, Radius_Y, Rotation : Long_Float;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Ellipse;
      Status    : out Ks_Status)
   is
      T     : KT.Ks_Transform_2D_Linear renames Transform;
      Cos_T : constant Long_Float := EF.Cos (Rotation);
      Sin_T : constant Long_Float := EF.Sin (Rotation);
      --  The ellipse is Center + M (cos s, sin s) where the columns of M
      --  are its two semi-axis vectors. Its image is T (Center) + N (cos
      --  s, sin s) with N = L M (L the linear part of T): the columns of
      --  N are conjugate semi-axes of the image.
      A, B, C, D   : Long_Float;   --  N = [A B; C D]
      Ref_X, Ref_Y : Long_Float;   --  image of the original Radius_X axis
      MX, MY       : Long_Float;
      OK           : Boolean;
   begin
      Result := (others => <>);
      Map_Vector (T, N.Times_Unit (Radius_X, Cos_T),
                  N.Times_Unit (Radius_X, Sin_T), A, C);
      Map_Vector (T, -N.Times_Unit (Radius_Y, Sin_T),
                  N.Times_Unit (Radius_Y, Cos_T), B, D);
      Map_Vector (T, Cos_T, Sin_T, Ref_X, Ref_Y);
      Map_Point (T, Center_X, Center_Y, MX, MY, OK);
      --  Every entry of N is at most its largest singular value, the
      --  major radius of the image; beyond Max_Length the image is out of
      --  range anyway.
      if not (OK and then abs A <= Max_Length and then abs B <= Max_Length
              and then abs C <= Max_Length and then abs D <= Max_Length)
      then
         Out_Of_Range (Status, "Ks_Ellipse.Map: the mapped ellipse");
         return;
      end if;

      --  The axes of the image are the left singular vectors of N and
      --  its semi-axis lengths the singular values, in closed form:
      --  splitting N into a scaled rotation Q Rot (Alpha) plus a scaled
      --  reflection P Refl (Beta) gives the singular values Q + P and
      --  |Q - P| and the major axis direction (Alpha + Beta) / 2. This
      --  keeps the minor axis accurate even when it is tiny.
      declare
         E : constant Long_Float := 0.5 * (A + D);
         F : constant Long_Float := 0.5 * (A - D);
         G : constant Long_Float := 0.5 * (C + B);
         H : constant Long_Float := 0.5 * (C - B);
         Q : constant Long_Float := N.Hypot (E, H);
         P : constant Long_Float := N.Hypot (F, G);
         Major : constant Long_Float := Q + P;
         Minor : constant Long_Float := abs (Q - P);
         Theta : constant Long_Float := Axis_Angle (E, F, G, H);
         Best  : Quarter := 0;
      begin
         if not (Major <= Max_Length and then Minor <= Max_Length) then
            Out_Of_Range (Status, "Ks_Ellipse.Map: the mapped radii");
            return;
         end if;

         --  Theta, Theta + Pi/2, Theta + Pi and Theta + 3 Pi/2 (with the
         --  radii swapped for the odd ones) all describe the image. Pick
         --  the one whose Radius_X axis is closest to the image of the
         --  original Radius_X direction, so that maps which preserve the
         --  axes keep the ellipse's parametrisation.
         if Ref_X /= 0.0 or else Ref_Y /= 0.0 then
            Best := Nearest_Quarter (Theta, N.Direction (Ref_Y, Ref_X));
         end if;

         Result.Center_X := MX;
         Result.Center_Y := MY;
         Result.Rotation := Quarter_Turn (Theta, Best);
         if Best mod 2 = 0 then
            Result.Radius_X := Major;
            Result.Radius_Y := Minor;
         else
            Result.Radius_X := Minor;
            Result.Radius_Y := Major;
         end if;
         Set_Success (Status);
      end;
   end Map_Ellipse;

   function Ellipse_Slack (E : Ks_Ellipse) return Long_Float is
     (Tolerance (Size     => E.Radius_X + E.Radius_Y,
                 Position => abs E.Center_X + abs E.Center_Y))
   with Pre  => Valid_Ellipse (E),
        Post => Ellipse_Slack'Result in 0.0 .. 1.0E144;

   ---------------------------------------------------------------------
   --  CogCircle
   ---------------------------------------------------------------------

   procedure Set_Center_Radius
     (Center_X, Center_Y, Radius : Long_Float;
      Result                     : out Ks_Circle;
      Status                     : out Ks_Status)
   is
      Candidate : constant Ks_Circle := (Center_X, Center_Y, Radius);
   begin
      Result := (others => <>);
      Check_Circle (Candidate, Status);
      if Succeeded (Status) then
         Result := Candidate;
      end if;
   end Set_Center_Radius;

   function Circle_Slack (C : Ks_Circle) return Long_Float is
     (Tolerance (Size     => C.Radius,
                 Position => abs C.Center_X + abs C.Center_Y))
   with Pre  => Valid_Circle (C),
        Post => Circle_Slack'Result in 0.0 .. 1.0E144;

   function Circle_Contains
     (Circle : Ks_Circle;
      X, Y   : Long_Float) return Boolean
   is (N.Hypot (X - Circle.Center_X, Y - Circle.Center_Y)
         <= Circle.Radius + Circle_Slack (Circle));

   procedure Contains_Point
     (Circle : Ks_Circle;
      X, Y   : Long_Float;
      Result : out Int32;
      Status : out Ks_Status) is
   begin
      Result := False_Value;
      Check_Circle (Circle, Status);
      if Succeeded (Status) then
         Check_Point (X, Y, Status);
      end if;
      if Succeeded (Status) and then Circle_Contains (Circle, X, Y) then
         Result := True_Value;
      end if;
   end Contains_Point;

   procedure Boundary_Slack
     (Circle : Ks_Circle;
      Result : out Long_Float;
      Status : out Ks_Status) is
   begin
      Result := 0.0;
      Check_Circle (Circle, Status);
      if Succeeded (Status) then
         Result := Circle_Slack (Circle);
      end if;
   end Boundary_Slack;

   procedure Get_Bounding_Box
     (Circle                     : Ks_Circle;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float;
      Status                     : out Ks_Status) is
   begin
      Min_X := 0.0;
      Min_Y := 0.0;
      Max_X := 0.0;
      Max_Y := 0.0;
      Check_Circle (Circle, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         X0 : constant Long_Float := Circle.Center_X - Circle.Radius;
         X1 : constant Long_Float := Circle.Center_X + Circle.Radius;
         Y0 : constant Long_Float := Circle.Center_Y - Circle.Radius;
         Y1 : constant Long_Float := Circle.Center_Y + Circle.Radius;
      begin
         if not (Bounded (X0) and then Bounded (X1) and then Bounded (Y0)
                 and then Bounded (Y1))
         then
            Out_Of_Range (Status, "Ks_Circle.Get_Bounding_Box: the box");
            return;
         end if;
         Min_X := X0;
         Max_X := X1;
         Min_Y := Y0;
         Max_Y := Y1;
      end;
   end Get_Bounding_Box;

   procedure Area
     (Circle : Ks_Circle;
      Result : out Long_Float;
      Status : out Ks_Status) is
   begin
      Result := 0.0;
      Check_Circle (Circle, Status);
      if Succeeded (Status) then
         Result := N.Mul (Pi * Circle.Radius, Circle.Radius);
      end if;
   end Area;

   procedure Map
     (Circle         : Ks_Circle;
      Transform      : KT.Ks_Transform_2D_Linear;
      Result_Type    : out Int32;
      Circle_Result  : out Ks_Circle;
      Ellipse_Result : out Ks_Ellipse;
      Status         : out Ks_Status)
   is
      Kind : Similarity_Kind;
   begin
      Result_Type := 0;
      Circle_Result := (others => <>);
      Ellipse_Result := (others => <>);
      Check_Circle (Circle, Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Transform) then
         Bad_Transform (Status);
         return;
      end if;
      Classify (Transform, Kind, Status);
      if not Succeeded (Status) then
         return;
      elsif Kind = Not_Similar then
         Map_Ellipse (Circle.Center_X, Circle.Center_Y, Circle.Radius,
                      Circle.Radius, 0.0, Transform, Ellipse_Result, Status);
         if Succeeded (Status) then
            Result_Type := Shape_Ellipse;
         end if;
         return;
      end if;
      Map_Center_Radius
        (Transform, Circle.Center_X, Circle.Center_Y, Circle.Radius,
         Circle_Result.Center_X, Circle_Result.Center_Y,
         Circle_Result.Radius, Status);
      if Succeeded (Status) then
         Result_Type := Shape_Circle;
      else
         Circle_Result := (others => <>);
      end if;
   end Map;

   ---------------------------------------------------------------------
   --  CogEllipse
   ---------------------------------------------------------------------

   procedure Set_Center_XY_Radius_XY_Rotation
     (Center_X, Center_Y, Radius_X, Radius_Y, Rotation : Long_Float;
      Result : out Ks_Ellipse;
      Status : out Ks_Status)
   is
      Candidate : constant Ks_Ellipse :=
        (Center_X, Center_Y, Radius_X, Radius_Y, Rotation);
   begin
      Result := (others => <>);
      Check_Ellipse (Candidate, Status);
      if Succeeded (Status) then
         Result := Candidate;
      end if;
   end Set_Center_XY_Radius_XY_Rotation;

   function Ellipse_Contains
     (Ellipse : Ks_Ellipse;
      X, Y    : Long_Float) return Boolean
   is
      E : Ks_Ellipse renames Ellipse;
   begin
      declare
         Tol   : constant Long_Float := Ellipse_Slack (E);
         Cos_T : constant Long_Float := EF.Cos (E.Rotation);
         Sin_T : constant Long_Float := EF.Sin (E.Rotation);
         DX    : constant Long_Float := X - E.Center_X;
         DY    : constant Long_Float := Y - E.Center_Y;
         --  The point in the ellipse's own axes.
         U     : constant Long_Float :=
           N.Times_Unit (DX, Cos_T) + N.Times_Unit (DY, Sin_T);
         V     : constant Long_Float :=
           N.Times_Unit (DY, Cos_T) - N.Times_Unit (DX, Sin_T);
         --  Widening both radii by Tol keeps boundary points inside and
         --  turns a degenerate ellipse into a thin one around its
         --  segment. A widened radius is 0.0 only for a single point at
         --  the origin; its term is then 0.
         AU    : constant Long_Float := E.Radius_X + Tol;
         AV    : constant Long_Float := E.Radius_Y + Tol;
         QU, QV : Long_Float := 0.0;
      begin
         if abs U > AU or else abs V > AV then
            return False;
         end if;
         if AU > 0.0 then
            QU := N.Unit_Ratio (U, AU);
         end if;
         if AV > 0.0 then
            QV := N.Unit_Ratio (V, AV);
         end if;
         return N.Times_Unit (QU, QU) + N.Times_Unit (QV, QV) <= 1.0;
      end;
   end Ellipse_Contains;

   procedure Contains_Point
     (Ellipse : Ks_Ellipse;
      X, Y    : Long_Float;
      Result  : out Int32;
      Status  : out Ks_Status) is
   begin
      Result := False_Value;
      Check_Ellipse (Ellipse, Status);
      if Succeeded (Status) then
         Check_Point (X, Y, Status);
      end if;
      if Succeeded (Status) and then Ellipse_Contains (Ellipse, X, Y) then
         Result := True_Value;
      end if;
   end Contains_Point;

   procedure Boundary_Slack
     (Ellipse : Ks_Ellipse;
      Result  : out Long_Float;
      Status  : out Ks_Status) is
   begin
      Result := 0.0;
      Check_Ellipse (Ellipse, Status);
      if Succeeded (Status) then
         Result := Ellipse_Slack (Ellipse);
      end if;
   end Boundary_Slack;

   procedure Get_Bounding_Box
     (Ellipse                    : Ks_Ellipse;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float;
      Status                     : out Ks_Status)
   is
      E : Ks_Ellipse renames Ellipse;
   begin
      Min_X := 0.0;
      Min_Y := 0.0;
      Max_X := 0.0;
      Max_Y := 0.0;
      Check_Ellipse (E, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Cos_T : constant Long_Float := EF.Cos (E.Rotation);
         Sin_T : constant Long_Float := EF.Sin (E.Rotation);
         --  The extreme x of Center + Rx cos s Ux + Ry sin s Uy over s is
         --  sqrt ((Rx cos t)**2 + (Ry sin t)**2), and similarly for y.
         Half_Width  : constant Long_Float :=
           N.Hypot (N.Times_Unit (E.Radius_X, Cos_T),
                    N.Times_Unit (E.Radius_Y, Sin_T));
         Half_Height : constant Long_Float :=
           N.Hypot (N.Times_Unit (E.Radius_X, Sin_T),
                    N.Times_Unit (E.Radius_Y, Cos_T));
         X0 : constant Long_Float := E.Center_X - Half_Width;
         X1 : constant Long_Float := E.Center_X + Half_Width;
         Y0 : constant Long_Float := E.Center_Y - Half_Height;
         Y1 : constant Long_Float := E.Center_Y + Half_Height;
      begin
         if not (Bounded (X0) and then Bounded (X1) and then Bounded (Y0)
                 and then Bounded (Y1))
         then
            Out_Of_Range (Status, "Ks_Ellipse.Get_Bounding_Box: the box");
            return;
         end if;
         Min_X := X0;
         Max_X := X1;
         Min_Y := Y0;
         Max_Y := Y1;
      end;
   end Get_Bounding_Box;

   procedure Area
     (Ellipse : Ks_Ellipse;
      Result  : out Long_Float;
      Status  : out Ks_Status) is
   begin
      Result := 0.0;
      Check_Ellipse (Ellipse, Status);
      if Succeeded (Status) then
         Result := N.Mul (Pi * Ellipse.Radius_X, Ellipse.Radius_Y);
      end if;
   end Area;

   procedure Map
     (Ellipse   : Ks_Ellipse;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Ellipse;
      Status    : out Ks_Status) is
   begin
      Result := (others => <>);
      Check_Ellipse (Ellipse, Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Transform) then
         Bad_Transform (Status);
         return;
      end if;
      Map_Ellipse (Ellipse.Center_X, Ellipse.Center_Y, Ellipse.Radius_X,
                   Ellipse.Radius_Y, Ellipse.Rotation, Transform, Result,
                   Status);
   end Map;

   ---------------------------------------------------------------------
   --  CogPolygon
   ---------------------------------------------------------------------

   procedure Release (Polygon : in out Ks_Polygon)
   with Post => Polygon = null;
   --  Frees Polygon (if any) and its vertices.

   procedure Release (Polygon : in out Ks_Polygon) is
   begin
      if Polygon /= null then
         Free (Polygon.Vertices);
         Free (Polygon);
      end if;
   end Release;

   procedure Check_Handle
     (Polygon   : access constant Ks_Polygon_Data;
      Operation : Name_Text;
      Status    : out Ks_Status)
   with Post => Status_OK (Status)
                and then Succeeded (Status)
                           = (Polygon = null or else Valid_Polygon (Polygon));
   --  Bad_Parameter for a handle that is not null and inconsistent.

   procedure Check_Handle
     (Polygon   : access constant Ks_Polygon_Data;
      Operation : Name_Text;
      Status    : out Ks_Status) is
   begin
      if Polygon = null or else Valid_Polygon (Polygon) then
         Set_Success (Status);
      else
         Bad (Status, "Ks_Polygon." & Operation
                      & ": the handle is inconsistent");
      end if;
   end Check_Handle;

   procedure Bad_Index
     (Operation : Name_Text;
      Index     : Int32;
      Count     : Natural;
      Status    : out Ks_Status)
   with Pre  => Count <= Max_Vertices,
        Post => Valid (Status)
                and then Status.Failure = Failure_Index_Out_Of_Range;
   --  "Ks_Polygon.<Operation>: vertex index <Index> is out of range (the
   --  polygon has <Count> vertices)".

   procedure Bad_Index
     (Operation : Name_Text;
      Index     : Int32;
      Count     : Natural;
      Status    : out Ks_Status) is
   begin
      Set_Failure
        (Status, Failure_Index_Out_Of_Range,
         "Ks_Polygon." & Operation & ": vertex index "
         & Image_Of (Int64 (Index)) & " is out of range (the polygon has "
         & Image_Of (Int64 (Count)) & " vertices)");
   end Bad_Index;

   procedure Check_Vertex_Index
     (Polygon   : access constant Ks_Polygon_Data;
      Operation : Name_Text;
      Index     : Int32;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Index_Out_Of_Range
                and then (if Succeeded (Status)
                          then Valid_Polygon (Polygon)
                               and then Index
                                          in 0 .. Int32 (Polygon.Count) - 1);
   --  The handle, and Index in 0 .. NumVertices - 1.

   procedure Check_Vertex_Index
     (Polygon   : access constant Ks_Polygon_Data;
      Operation : Name_Text;
      Index     : Int32;
      Status    : out Ks_Status) is
   begin
      Check_Handle (Polygon, Operation, Status);
      if not Succeeded (Status) then
         return;
      elsif Index < 0 or else Index >= Int32 (Count_Of (Polygon)) then
         Bad_Index (Operation, Index, Count_Of (Polygon), Status);
      end if;
   end Check_Vertex_Index;

   procedure Create
     (Polygon : out Ks_Polygon;
      Status  : out Ks_Status) is
   begin
      Allocate_Polygon (Polygon);
      if Polygon = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Ks_Polygon.Create: not enough memory");
      else
         Set_Success (Status);
      end if;
   end Create;

   procedure Destroy
     (Polygon : in out Ks_Polygon;
      Status  : out Ks_Status) is
   begin
      Release (Polygon);
      Set_Success (Status);
   end Destroy;

   procedure Duplicate
     (Polygon : access constant Ks_Polygon_Data;
      Result  : out Ks_Polygon;
      Status  : out Ks_Status) is
   begin
      Result := null;
      Check_Handle (Polygon, "Duplicate", Status);
      if not Succeeded (Status) or else Polygon = null then
         return;
      end if;
      Allocate_Polygon (Result);
      if Result = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Ks_Polygon.Duplicate: not enough memory");
         return;
      end if;
      if Polygon.Count = 0 then
         return;
      end if;
      Allocate_Vertices (Polygon.Count, Result.Vertices);
      if Result.Vertices = null then
         Release (Result);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Ks_Polygon.Duplicate: not enough memory");
         return;
      end if;
      for J in 0 .. Polygon.Count - 1 loop
         Result.Vertices (J) := Polygon.Vertices (J);
         pragma Loop_Invariant
           (Result /= null and then Result.Vertices /= null
            and then Result.Count = 0
            and then Result.Vertices'First = 0
            and then Result.Vertices'Last = Polygon.Count - 1);
         pragma Loop_Invariant
           (for all K in 0 .. J
            => Result.Vertices (K) = Polygon.Vertices (K));
      end loop;
      Result.Count := Polygon.Count;
   end Duplicate;

   procedure Num_Vertices
     (Polygon : access constant Ks_Polygon_Data;
      Result  : out Int32;
      Status  : out Ks_Status) is
   begin
      Result := 0;
      Check_Handle (Polygon, "Num_Vertices", Status);
      if Succeeded (Status) then
         Result := Int32 (Count_Of (Polygon));
      end if;
   end Num_Vertices;

   procedure Get_Vertex
     (Polygon : access constant Ks_Polygon_Data;
      Index   : Int32;
      X, Y    : out Long_Float;
      Status  : out Ks_Status) is
   begin
      X := 0.0;
      Y := 0.0;
      Check_Vertex_Index (Polygon, "Get_Vertex", Index, Status);
      if Succeeded (Status) then
         X := Polygon.Vertices (Natural (Index)).X;
         Y := Polygon.Vertices (Natural (Index)).Y;
      end if;
   end Get_Vertex;

   procedure Set_Vertex
     (Polygon : Ks_Polygon;
      Index   : Int32;
      X, Y    : Long_Float;
      Status  : out Ks_Status) is
   begin
      if not Bounded (X) then
         Bad_Coordinate (Status, "Ks_Polygon.Set_Vertex: X");
         return;
      elsif not Bounded (Y) then
         Bad_Coordinate (Status, "Ks_Polygon.Set_Vertex: Y");
         return;
      end if;
      Check_Vertex_Index (Polygon, "Set_Vertex", Index, Status);
      if Succeeded (Status) then
         Polygon.Vertices (Natural (Index)) := (X, Y);
      end if;
   end Set_Vertex;

   procedure Grow
     (Polygon : Ks_Polygon;
      Status  : out Ks_Status)
   with
     Pre  => Valid_Polygon (Polygon) and then Polygon.Count < Max_Vertices,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then Valid_Polygon (Polygon)
             and then Polygon.Count = Polygon.Count'Old
             and then Vertices_Of (Polygon) = Vertices_Of (Polygon)'Old
             and then (if Succeeded (Status)
                       then Polygon.Vertices /= null
                            and then Polygon.Count
                                       <= Polygon.Vertices'Last);
   --  Makes room for one more vertex (doubling the room when it is full);
   --  Out_Of_Memory, with nothing changed, when that cannot be allocated.

   procedure Grow
     (Polygon : Ks_Polygon;
      Status  : out Ks_Status)
   is
      Count    : constant Natural := Polygon.Count;
      Capacity : Positive;
      Fresh    : Vertex_Array_Access;
   begin
      if Polygon.Vertices /= null
        and then Count <= Polygon.Vertices'Last
      then
         Set_Success (Status);
         return;
      end if;
      Capacity := Natural'Min
        (Natural'Max (2 * Count, Initial_Capacity), Max_Vertices);
      Allocate_Vertices (Capacity, Fresh);
      if Fresh = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Ks_Polygon.Add_Vertex: not enough memory");
         return;
      end if;
      for J in 0 .. Count - 1 loop
         Fresh (J) := Polygon.Vertices (J);
         pragma Loop_Invariant
           (Fresh'First = 0 and then Fresh'Last = Capacity - 1);
         pragma Loop_Invariant
           (for all K in 0 .. J => Fresh (K) = Polygon.Vertices (K));
      end loop;
      Free (Polygon.Vertices);
      Polygon.Vertices := Fresh;
      Set_Success (Status);
   end Grow;

   procedure Add_Vertex
     (Polygon : in out Ks_Polygon;
      X, Y    : Long_Float;
      Index   : Int32;
      Status  : out Ks_Status)
   is
      Count    : Natural;
      Position : Natural;
      Created  : Boolean := False;
   begin
      if not Bounded (X) then
         Bad_Coordinate (Status, "Ks_Polygon.Add_Vertex: X");
         return;
      elsif not Bounded (Y) then
         Bad_Coordinate (Status, "Ks_Polygon.Add_Vertex: Y");
         return;
      end if;
      Check_Handle (Polygon, "Add_Vertex", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Count := Count_Of (Polygon);
      if Index < -1 or else Index > Int32 (Count) then
         Bad_Index ("Add_Vertex", Index, Count, Status);
         return;
      elsif Count = Max_Vertices then
         Bad (Status, "Ks_Polygon.Add_Vertex: the polygon already has the "
                      & "maximum number of vertices (1048576)");
         return;
      end if;
      Position := (if Index = -1 then Count else Natural (Index));
      if Polygon = null then
         Allocate_Polygon (Polygon);
         if Polygon = null then
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Ks_Polygon.Add_Vertex: not enough memory");
            return;
         end if;
         Created := True;
      end if;
      Grow (Polygon, Status);
      if not Succeeded (Status) then
         if Created then
            Release (Polygon);
         end if;
         return;
      end if;
      declare
         Old : constant Vertex_Array := Vertices_Of (Polygon)
         with Ghost;
      begin
         --  Move the vertices from Position on up by one.
         for J in reverse Position + 1 .. Count loop
            Polygon.Vertices (J) := Polygon.Vertices (J - 1);
            pragma Loop_Invariant
              (Polygon /= null and then Polygon.Vertices /= null
               and then Polygon.Count = Count
               and then Valid_Polygon (Polygon)
               and then Count <= Polygon.Vertices'Last);
            pragma Loop_Invariant
              (for all K in 0 .. J - 1 => Polygon.Vertices (K) = Old (K));
            pragma Loop_Invariant
              (for all K in J .. Count
               => Polygon.Vertices (K) = Old (K - 1));
         end loop;
         Polygon.Vertices (Position) := (X, Y);
         Polygon.Count := Count + 1;
      end;
   end Add_Vertex;

   procedure Remove_Vertex
     (Polygon : Ks_Polygon;
      Index   : Int32;
      Status  : out Ks_Status) is
   begin
      Check_Vertex_Index (Polygon, "Remove_Vertex", Index, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Count    : constant Natural := Polygon.Count;
         Position : constant Natural := Natural (Index);
         Old      : constant Vertex_Array := Vertices_Of (Polygon)
         with Ghost;
      begin
         --  Move the vertices after Position down by one.
         for J in Position .. Count - 2 loop
            Polygon.Vertices (J) := Polygon.Vertices (J + 1);
            pragma Loop_Invariant
              (Polygon.Count = Count and then Valid_Polygon (Polygon));
            pragma Loop_Invariant
              (for all K in 0 .. Position - 1
               => Polygon.Vertices (K) = Old (K));
            pragma Loop_Invariant
              (for all K in Position .. J
               => Polygon.Vertices (K) = Old (K + 1));
            pragma Loop_Invariant
              (for all K in J + 1 .. Count - 1
               => Polygon.Vertices (K) = Old (K));
         end loop;
         Polygon.Count := Count - 1;
      end;
   end Remove_Vertex;

   procedure Clear
     (Polygon : Ks_Polygon;
      Status  : out Ks_Status) is
   begin
      Check_Handle (Polygon, "Clear", Status);
      if Succeeded (Status) and then Polygon /= null then
         Free (Polygon.Vertices);
         Polygon.Count := 0;
      end if;
   end Clear;

   procedure Polygon_Box
     (Polygon                    : access constant Ks_Polygon_Data;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float)
   with
     Pre  => Valid_Polygon (Polygon) and then Polygon.Count > 0,
     Post => Valid_Box (Min_X, Min_Y, Max_X, Max_Y);
   --  The smallest box around the vertices.

   procedure Polygon_Box
     (Polygon                    : access constant Ks_Polygon_Data;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float) is
   begin
      Min_X := Polygon.Vertices (0).X;
      Max_X := Min_X;
      Min_Y := Polygon.Vertices (0).Y;
      Max_Y := Min_Y;
      for J in 1 .. Polygon.Count - 1 loop
         Include (Polygon.Vertices (J).X, Min_X, Max_X);
         Include (Polygon.Vertices (J).Y, Min_Y, Max_Y);
         pragma Loop_Invariant (Valid_Box (Min_X, Min_Y, Max_X, Max_Y));
      end loop;
   end Polygon_Box;

   function Box_Slack (Min_X, Min_Y, Max_X, Max_Y : Long_Float)
     return Long_Float
   is (Tolerance
         (Size     => (Max_X - Min_X) + (Max_Y - Min_Y),
          Position => Long_Float'Max
                        (Long_Float'Max (abs Min_X, abs Max_X),
                         Long_Float'Max (abs Min_Y, abs Max_Y))))
   with Pre  => Valid_Box (Min_X, Min_Y, Max_X, Max_Y),
        Post => Box_Slack'Result in 0.0 .. 1.0E144;
   --  The boundary slack of a polygon with this bounding box.

   function Segment_Distance (PX, PY, AX, AY, BX, BY : Long_Float)
     return Long_Float
   with Pre => Bounded (PX) and then Bounded (PY) and then Bounded (AX)
               and then Bounded (AY) and then Bounded (BX)
               and then Bounded (BY);
   --  The distance from (PX, PY) to the closed segment from (AX, AY) to
   --  (BX, BY); the distance to A for a segment of no length.

   function Segment_Distance (PX, PY, AX, AY, BX, BY : Long_Float)
     return Long_Float
   is
      DX : constant Long_Float := BX - AX;
      DY : constant Long_Float := BY - AY;
      L2 : constant Long_Float := N.Mul (DX, DX) + N.Mul (DY, DY);
      T  : Long_Float := 0.0;
   begin
      --  T is the parameter of the nearest point, the projection
      --  ((P - A) . D) / L2 clamped to [0, 1]; the cases are told apart
      --  before dividing, so the quotient lies in [0, 1].
      if L2 > 0.0 then
         declare
            Num : constant Long_Float :=
              N.Mul (PX - AX, DX) + N.Mul (PY - AY, DY);
         begin
            if Num <= 0.0 then
               T := 0.0;
            elsif Num >= L2 then
               T := 1.0;
            else
               T := N.Unit_Ratio (Num, L2);
            end if;
         end;
      end if;
      return N.Hypot (PX - (AX + N.Times_Unit (DX, T)),
                      PY - (AY + N.Times_Unit (DY, T)));
   end Segment_Distance;

   function Crosses (X, Y : Long_Float; A, B : Ks_Vertex) return Boolean
   with Pre => Bounded (X) and then Bounded (Y);
   --  The edge from A to B crosses the ray from (X, Y) towards +x: its end
   --  points lie on different sides of the horizontal line through the
   --  point (one strictly above, the other on or below; a vertex on the
   --  ray counts once) and the crossing lies right of X.

   function Crosses (X, Y : Long_Float; A, B : Ks_Vertex) return Boolean is
      Num   : Long_Float := Y - A.Y;
      Den   : Long_Float := B.Y - A.Y;
      Ratio : Long_Float;
   begin
      if (A.Y > Y) = (B.Y > Y) then
         return False;
      elsif Den < 0.0 then
         Num := -Num;
         Den := -Den;
      end if;
      --  Y lies between A.Y and B.Y: the crossing is A + Ratio (B - A)
      --  with Ratio = (Y - A.Y) / (B.Y - A.Y) in [0, 1]. The cases are told
      --  apart before dividing (Den is never 0 here, since the end points
      --  lie on different sides of Y), so the quotient lies in [0, 1].
      if Den <= 0.0 or else Num <= 0.0 then
         Ratio := 0.0;
      elsif Num >= Den then
         Ratio := 1.0;
      else
         Ratio := N.Unit_Ratio (Num, Den);
      end if;
      return X < A.X + N.Times_Unit (B.X - A.X, Ratio);
   end Crosses;

   function Polygon_Contains
     (Polygon : access constant Ks_Polygon_Data;
      X, Y    : Long_Float) return Boolean
   is
      Count  : constant Natural := Count_Of (Polygon);
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
      Tol    : Long_Float;
      Inside : Boolean := False;
   begin
      if Count = 0 then
         return False;
      end if;
      Polygon_Box (Polygon, Min_X, Min_Y, Max_X, Max_Y);
      Tol := Box_Slack (Min_X, Min_Y, Max_X, Max_Y);
      if X < Min_X - Tol or else X > Max_X + Tol
        or else Y < Min_Y - Tol or else Y > Max_Y + Tol
      then
         return False;
      end if;

      --  Points on an edge (or on the single vertex) count as inside.
      for I in 0 .. Count - 1 loop
         declare
            A : constant Ks_Vertex := Polygon.Vertices (I);
            B : constant Ks_Vertex :=
              Polygon.Vertices (if I = Count - 1 then 0 else I + 1);
         begin
            if Segment_Distance (X, Y, A.X, A.Y, B.X, B.Y) <= Tol then
               return True;
            end if;
         end;
      end loop;

      if Count < 3 then
         return False;
      end if;

      --  Even-odd rule: count the edges the ray towards +x crosses.
      for I in 0 .. Count - 1 loop
         if Crosses (X, Y, Polygon.Vertices (I),
                     Polygon.Vertices (if I = 0 then Count - 1 else I - 1))
         then
            Inside := not Inside;
         end if;
      end loop;
      return Inside;
   end Polygon_Contains;

   procedure Contains_Point
     (Polygon : access constant Ks_Polygon_Data;
      X, Y    : Long_Float;
      Result  : out Int32;
      Status  : out Ks_Status) is
   begin
      Result := False_Value;
      Check_Handle (Polygon, "Contains_Point", Status);
      if Succeeded (Status) then
         Check_Point (X, Y, Status);
      end if;
      if Succeeded (Status) and then Polygon_Contains (Polygon, X, Y) then
         Result := True_Value;
      end if;
   end Contains_Point;

   procedure Boundary_Slack
     (Polygon : access constant Ks_Polygon_Data;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   is
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
   begin
      Result := 0.0;
      Check_Handle (Polygon, "Boundary_Slack", Status);
      if Succeeded (Status) and then Count_Of (Polygon) > 0 then
         --  Contains_Point rejects every point outside the box widened by
         --  the slack before anything else.
         Polygon_Box (Polygon, Min_X, Min_Y, Max_X, Max_Y);
         Result := Box_Slack (Min_X, Min_Y, Max_X, Max_Y);
      end if;
   end Boundary_Slack;

   procedure Get_Bounding_Box
     (Polygon                    : access constant Ks_Polygon_Data;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float;
      Status                     : out Ks_Status) is
   begin
      Min_X := 0.0;
      Min_Y := 0.0;
      Max_X := 0.0;
      Max_Y := 0.0;
      Check_Handle (Polygon, "Get_Bounding_Box", Status);
      if Succeeded (Status) and then Count_Of (Polygon) > 0 then
         Polygon_Box (Polygon, Min_X, Min_Y, Max_X, Max_Y);
      end if;
   end Get_Bounding_Box;

   Term_Limit : constant := 2.0 ** 1003;
   --  A term of the shoelace sum: the difference of two products of
   --  coordinate differences (each within 2 Max_Value < 2**501).

   function Add_Term (Sum, Term : Long_Float; Done : Natural)
     return Long_Float
   with
     Pre  => Done < Max_Vertices
             and then abs Sum <= Long_Float (Done) * Term_Limit
             and then abs Term <= Term_Limit,
     Post => abs Add_Term'Result <= Long_Float (Done + 1) * Term_Limit
             and then abs Add_Term'Result <= 2.0 ** 1023;
   --  Sum + Term, the shoelace sum after Done + 1 terms.

   function Add_Term (Sum, Term : Long_Float; Done : Natural)
     return Long_Float
   is
      Limit : constant Long_Float := Long_Float (Done + 1) * Term_Limit;
      R     : constant Long_Float := Sum + Term;
   begin
      --  abs (Sum + Term) <= (Done + 1) * Term_Limit exactly, and rounding
      --  keeps it so (the bound is a representable multiple of a power of
      --  two); the tests below state it for the prover and are never true.
      if R > Limit then
         return Limit;
      elsif R < -Limit then
         return -Limit;
      end if;
      return R;
   end Add_Term;

   procedure Area
     (Polygon : access constant Ks_Polygon_Data;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   is
      Count : Natural;
      Sum   : Long_Float := 0.0;
   begin
      Result := 0.0;
      Check_Handle (Polygon, "Area", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Count := Count_Of (Polygon);
      if Count < 3 then
         return;
      end if;
      --  Shoelace formula relative to the first vertex (better
      --  conditioned for polygons far from the origin).
      declare
         V0 : constant Ks_Vertex := Polygon.Vertices (0);
      begin
         for I in 1 .. Count - 2 loop
            pragma Loop_Invariant
              (abs Sum <= Long_Float (I - 1) * Term_Limit
               and then abs Sum <= 2.0 ** 1023);
            declare
               A : constant Ks_Vertex := Polygon.Vertices (I);
               B : constant Ks_Vertex := Polygon.Vertices (I + 1);
               Term : constant Long_Float :=
                 N.Mul_Small (A.X - V0.X, B.Y - V0.Y)
                 - N.Mul_Small (B.X - V0.X, A.Y - V0.Y);
            begin
               Sum := Add_Term (Sum, Term, I - 1);
            end;
         end loop;
      end;
      Result := 0.5 * abs Sum;
   end Area;

   Edge_Limit : constant := 2.0 ** 502;
   --  The length of an edge (at most 4 Max_Value < 2**502). 2**20 edges
   --  add up to at most 2**522 (Max_Perimeter, about 1.4E157).

   function Add_Length (Sum, Length : Long_Float; Done : Natural)
     return Long_Float
   with
     Pre  => Done < Max_Vertices
             and then Sum >= 0.0
             and then Sum <= Long_Float (Done) * Edge_Limit
             and then Length in 0.0 .. Edge_Limit,
     Post => Add_Length'Result >= 0.0
             and then Add_Length'Result <= Long_Float (Done + 1) * Edge_Limit
             and then Add_Length'Result <= 2.0 ** 522;
   --  Sum + Length, the perimeter after Done + 1 edges.

   function Add_Length (Sum, Length : Long_Float; Done : Natural)
     return Long_Float
   is
      Limit : constant Long_Float := Long_Float (Done + 1) * Edge_Limit;
      R     : constant Long_Float := Sum + Length;
   begin
      --  Sum + Length <= (Done + 1) * Edge_Limit exactly, and rounding
      --  keeps it so; the test below states it for the prover and is never
      --  true.
      if R > Limit then
         return Limit;
      end if;
      return R;
   end Add_Length;

   procedure Perimeter
     (Polygon : access constant Ks_Polygon_Data;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   is
      Count : Natural;
      Sum   : Long_Float := 0.0;
   begin
      Result := 0.0;
      Check_Handle (Polygon, "Perimeter", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Count := Count_Of (Polygon);
      if Count < 2 then
         return;
      end if;
      for I in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (Sum >= 0.0 and then Sum <= Long_Float (I) * Edge_Limit
            and then Sum <= 2.0 ** 522);
         declare
            A : constant Ks_Vertex := Polygon.Vertices (I);
            B : constant Ks_Vertex :=
              Polygon.Vertices (if I = Count - 1 then 0 else I + 1);
         begin
            Sum := Add_Length (Sum, N.Hypot (B.X - A.X, B.Y - A.Y), I);
         end;
      end loop;
      Result := Sum;
   end Perimeter;

   procedure Map
     (Polygon   : access constant Ks_Polygon_Data;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Polygon;
      Status    : out Ks_Status)
   is
      MX, MY : Long_Float;
      OK     : Boolean;
   begin
      Result := null;
      Check_Handle (Polygon, "Map", Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Transform) then
         Bad_Transform (Status);
         return;
      elsif Polygon = null then
         return;
      end if;
      Allocate_Polygon (Result);
      if Result = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Ks_Polygon.Map: not enough memory");
         return;
      end if;
      if Polygon.Count = 0 then
         return;
      end if;
      Allocate_Vertices (Polygon.Count, Result.Vertices);
      if Result.Vertices = null then
         Release (Result);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Ks_Polygon.Map: not enough memory");
         return;
      end if;
      for J in 0 .. Polygon.Count - 1 loop
         pragma Loop_Invariant
           (Result /= null and then Result.Vertices /= null
            and then Result.Count = 0
            and then Result.Vertices'First = 0
            and then Result.Vertices'Last = Polygon.Count - 1);
         Map_Point (Transform, Polygon.Vertices (J).X,
                    Polygon.Vertices (J).Y, MX, MY, OK);
         if not OK then
            Release (Result);
            Out_Of_Range (Status, "Ks_Polygon.Map: a mapped vertex");
            return;
         end if;
         Result.Vertices (J) := (MX, MY);
      end loop;
      Result.Count := Polygon.Count;
   end Map;

   function Same_Vertices
     (Left, Right : access constant Ks_Polygon_Data) return Boolean
   is
      Count : constant Natural := Count_Of (Left);
   begin
      if Count /= Count_Of (Right) then
         return False;
      end if;
      for J in 0 .. Count - 1 loop
         if Left.Vertices (J) /= Right.Vertices (J) then
            return False;
         end if;
         pragma Loop_Invariant
           (for all K in 0 .. J => Left.Vertices (K) = Right.Vertices (K));
      end loop;
      return True;
   end Same_Vertices;

   procedure Check_Stream_Count
     (Count  : Interfaces.Unsigned_32;
      Status : out Ks_Status) is
   begin
      if Count <= Max_Vertices then
         Set_Success (Status);
      else
         Bad (Status, "Ks_Polygon'Read: the stream announces more than "
                      & "1048576 vertices");
      end if;
   end Check_Stream_Count;

   ---------------------------------------------------------------------
   --  CogCircularAnnulusSection
   ---------------------------------------------------------------------

   procedure Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
     (Center_X, Center_Y, Radius, Angle_Start, Angle_Span : Long_Float;
      Radial_Scale                                        : Long_Float;
      Result : out Ks_Circular_Annulus_Section;
      Status : out Ks_Status)
   is
      Candidate : constant Ks_Circular_Annulus_Section :=
        (Center_X, Center_Y, Radius, Angle_Start, Angle_Span, Radial_Scale);
   begin
      Result := (others => <>);
      Check_Section (Candidate, Status);
      if Succeeded (Status) then
         Result := Candidate;
      end if;
   end Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale;

   procedure Get_Radii
     (S : Ks_Circular_Annulus_Section; Inner, Outer : out Long_Float)
   with Pre  => Valid_Circular_Annulus_Section (S),
        Post => Inner in 0.0 .. Max_Length
                and then Outer in 0.0 .. Max_Length
                and then Inner <= Outer;
   --  The two radii of the section, the smaller first.

   procedure Get_Radii
     (S : Ks_Circular_Annulus_Section; Inner, Outer : out Long_Float)
   is
      Other : constant Long_Float := S.Radius * S.Radial_Scale;
   begin
      Inner := Long_Float'Min (S.Radius, Other);
      Outer := Long_Float'Max (S.Radius, Other);
   end Get_Radii;

   function Section_Slack (S : Ks_Circular_Annulus_Section) return Long_Float
   with Pre  => Valid_Circular_Annulus_Section (S),
        Post => Section_Slack'Result in 0.0 .. 1.0E144;
   --  The boundary slack of Contains_Point.

   function Outer_Radius (S : Ks_Circular_Annulus_Section) return Long_Float
   is (Long_Float'Max (S.Radius, S.Radius * S.Radial_Scale))
   with Pre  => Valid_Circular_Annulus_Section (S),
        Post => Outer_Radius'Result in 0.0 .. Max_Length;
   --  The larger of the two radii.

   function Section_Slack (S : Ks_Circular_Annulus_Section) return Long_Float
   is (Tolerance (Size     => Outer_Radius (S),
                  Position => abs S.Center_X + abs S.Center_Y));

   function Wrap_Two_Pi (Angle : Long_Float) return Long_Float
   with Post => Wrap_Two_Pi'Result >= 0.0
                and then Wrap_Two_Pi'Result <= Two_Pi;
   --  Angle reduced into [0, 2 Pi]: itself when already there, otherwise
   --  its remainder modulo 2 Pi, plus 2 Pi when negative.

   function Wrap_Two_Pi (Angle : Long_Float) return Long_Float is
      R : Long_Float;
   begin
      if Angle >= 0.0 and then Angle <= Two_Pi then
         return Angle;
      end if;
      R := N.Reduce_Two_Pi (Angle);
      if R < 0.0 then
         R := R + Two_Pi;
      end if;
      return R;
   end Wrap_Two_Pi;

   function Section_Contains
     (Section : Ks_Circular_Annulus_Section;
      X, Y    : Long_Float) return Boolean
   is
      S : Ks_Circular_Annulus_Section renames Section;
      Inner, Outer : Long_Float;
   begin
      Get_Radii (S, Inner, Outer);
      declare
         Tol      : constant Long_Float := Section_Slack (S);
         DX       : constant Long_Float := X - S.Center_X;
         DY       : constant Long_Float := Y - S.Center_Y;
         Distance : constant Long_Float := N.Hypot (DX, DY);
         Offset, Extent, Angular_Tol : Long_Float;
      begin
         if Distance < Inner - Tol or else Distance > Outer + Tol then
            return False;
         elsif abs S.Angle_Span >= Two_Pi then
            return True;   --  a full annulus
         elsif Distance <= Tol then
            --  At the centre the direction is undefined. Passing the
            --  radial test here means the inner radius is (nearly) 0, so
            --  the point is at or next to the apex of the sector.
            return True;
         end if;

         --  The angle from the start, measured in the direction of the
         --  span, reduced into [0, 2 Pi].
         if S.Angle_Span >= 0.0 then
            Offset := Wrap_Two_Pi (N.Direction (DY, DX) - S.Angle_Start);
            Extent := S.Angle_Span;
         else
            Offset := Wrap_Two_Pi (S.Angle_Start - N.Direction (DY, DX));
            Extent := -S.Angle_Span;
         end if;
         --  Tol as an arc length at this distance; a point just before
         --  the start shows up with an offset just below 2 Pi.
         Angular_Tol := N.Unit_Ratio (Tol, Distance);
         return Offset <= Extent + Angular_Tol
           or else Offset >= Two_Pi - Angular_Tol;
      end;
   end Section_Contains;

   procedure Contains_Point
     (Section : Ks_Circular_Annulus_Section;
      X, Y    : Long_Float;
      Result  : out Int32;
      Status  : out Ks_Status) is
   begin
      Result := False_Value;
      Check_Section (Section, Status);
      if Succeeded (Status) then
         Check_Point (X, Y, Status);
      end if;
      if Succeeded (Status) and then Section_Contains (Section, X, Y) then
         Result := True_Value;
      end if;
   end Contains_Point;

   procedure Boundary_Slack
     (Section : Ks_Circular_Annulus_Section;
      Result  : out Long_Float;
      Status  : out Ks_Status) is
   begin
      Result := 0.0;
      Check_Section (Section, Status);
      if Succeeded (Status) then
         --  The radial and the angular slack add up, and a point next to
         --  the centre adds one more (see AMV.Shapes).
         Result := 3.0 * Section_Slack (Section);
      end if;
   end Boundary_Slack;

   Box_Limit : constant := 6.0E150;
   --  A point at either radius from a bounded centre, before the check.

   procedure Include_Radii
     (Center, Inner, Outer, Unit : Long_Float;
      Min_V, Max_V               : in out Long_Float)
   with
     Pre  => Bounded (Center)
             and then Inner in 0.0 .. Max_Length
             and then Outer in 0.0 .. Max_Length
             and then abs Unit <= 1.0
             and then abs Min_V <= Box_Limit and then abs Max_V <= Box_Limit
             and then Min_V <= Max_V,
     Post => abs Min_V <= Box_Limit and then abs Max_V <= Box_Limit
             and then Min_V <= Max_V;
   --  Widens [Min_V, Max_V] by Center + Inner * Unit and Center + Outer *
   --  Unit: one coordinate of the points at both radii in a direction.

   procedure Include_Radii
     (Center, Inner, Outer, Unit : Long_Float;
      Min_V, Max_V               : in out Long_Float)
   is
      Near : constant Long_Float := Center + N.Times_Unit (Inner, Unit);
      Far  : constant Long_Float := Center + N.Times_Unit (Outer, Unit);
   begin
      Include (Near, Min_V, Max_V);
      Include (Far, Min_V, Max_V);
   end Include_Radii;

   procedure Include_Direction
     (Center_X, Center_Y, Inner, Outer, Cos_A, Sin_A : Long_Float;
      Min_X, Min_Y, Max_X, Max_Y                     : in out Long_Float)
   with
     Pre  => Bounded (Center_X) and then Bounded (Center_Y)
             and then Inner in 0.0 .. Max_Length
             and then Outer in 0.0 .. Max_Length
             and then abs Cos_A <= 1.0 and then abs Sin_A <= 1.0
             and then abs Min_X <= Box_Limit and then abs Max_X <= Box_Limit
             and then abs Min_Y <= Box_Limit and then abs Max_Y <= Box_Limit
             and then Min_X <= Max_X and then Min_Y <= Max_Y,
     Post => abs Min_X <= Box_Limit and then abs Max_X <= Box_Limit
             and then abs Min_Y <= Box_Limit and then abs Max_Y <= Box_Limit
             and then Min_X <= Max_X and then Min_Y <= Max_Y;
   --  Widens the box by the points at both radii in direction
   --  (Cos_A, Sin_A).

   procedure Include_Direction
     (Center_X, Center_Y, Inner, Outer, Cos_A, Sin_A : Long_Float;
      Min_X, Min_Y, Max_X, Max_Y                     : in out Long_Float) is
   begin
      Include_Radii (Center_X, Inner, Outer, Cos_A, Min_X, Max_X);
      Include_Radii (Center_Y, Inner, Outer, Sin_A, Min_Y, Max_Y);
   end Include_Direction;

   procedure Full_Box
     (Center_X, Center_Y, Outer : Long_Float;
      X0, Y0, X1, Y1            : out Long_Float)
   with
     Pre  => Bounded (Center_X) and then Bounded (Center_Y)
             and then Outer in 0.0 .. Max_Length,
     Post => abs X0 <= Box_Limit and then abs X1 <= Box_Limit
             and then abs Y0 <= Box_Limit and then abs Y1 <= Box_Limit
             and then X0 <= X1 and then Y0 <= Y1;
   --  The box of a full annulus (or disc) of radius Outer.

   procedure Full_Box
     (Center_X, Center_Y, Outer : Long_Float;
      X0, Y0, X1, Y1            : out Long_Float) is
   begin
      X0 := Center_X - Outer;
      X1 := Center_X + Outer;
      Y0 := Center_Y - Outer;
      Y1 := Center_Y + Outer;
   end Full_Box;

   procedure Section_Box
     (S              : Ks_Circular_Annulus_Section;
      X0, Y0, X1, Y1 : out Long_Float)
   with
     Pre  => Valid_Circular_Annulus_Section (S),
     Post => abs X0 <= Box_Limit and then abs X1 <= Box_Limit
             and then abs Y0 <= Box_Limit and then abs Y1 <= Box_Limit
             and then X0 <= X1 and then Y0 <= Y1;
   --  The exact bounding box of the section, before its bound is checked.

   procedure Section_Box
     (S              : Ks_Circular_Annulus_Section;
      X0, Y0, X1, Y1 : out Long_Float)
   is
      Inner, Outer : Long_Float;
   begin
      Get_Radii (S, Inner, Outer);
      if abs S.Angle_Span >= Two_Pi then
         Full_Box (S.Center_X, S.Center_Y, Outer, X0, Y0, X1, Y1);
         return;
      end if;
      --  x = r cos a and y = r sin a over r in [Inner, Outer] and a in the
      --  span reach their extremes at r = Inner or Outer and at the ends of
      --  the span or where the direction crosses an axis.
      declare
         Cos_S     : constant Long_Float := EF.Cos (S.Angle_Start);
         Sin_S     : constant Long_Float := EF.Sin (S.Angle_Start);
         End_Angle : constant Long_Float := S.Angle_Start + S.Angle_Span;
         Low       : constant Long_Float :=
           N.Reduce_Two_Pi (Long_Float'Min (S.Angle_Start, End_Angle));
         High      : constant Long_Float := Low + abs S.Angle_Span;
         --  Low is in (-Pi, Pi] and High < Low + 2 Pi, so the multiples
         --  K Pi/2 in [Low, High] have K in -1 .. 6.
         First_K   : constant Long_Float := Long_Float'Ceiling (Low / Half_Pi);
         Last_K    : constant Long_Float := Long_Float'Floor (High / Half_Pi);
      begin
         X0 := S.Center_X + N.Times_Unit (Outer, Cos_S);
         X1 := X0;
         Y0 := S.Center_Y + N.Times_Unit (Outer, Sin_S);
         Y1 := Y0;
         Include_Direction (S.Center_X, S.Center_Y, Inner, Outer,
                            Cos_S, Sin_S, X0, Y0, X1, Y1);
         Include_Direction (S.Center_X, S.Center_Y, Inner, Outer,
                            EF.Cos (End_Angle), EF.Sin (End_Angle),
                            X0, Y0, X1, Y1);
         for K in -4 .. 8 loop
            pragma Loop_Invariant
              (abs X0 <= Box_Limit and then abs X1 <= Box_Limit
               and then abs Y0 <= Box_Limit and then abs Y1 <= Box_Limit
               and then X0 <= X1 and then Y0 <= Y1);
            if Long_Float (K) >= First_K and then Long_Float (K) <= Last_K
            then
               case K mod 4 is
                  when 0 =>
                     Include_Direction (S.Center_X, S.Center_Y, Inner, Outer,
                                        1.0, 0.0, X0, Y0, X1, Y1);
                  when 1 =>
                     Include_Direction (S.Center_X, S.Center_Y, Inner, Outer,
                                        0.0, 1.0, X0, Y0, X1, Y1);
                  when 2 =>
                     Include_Direction (S.Center_X, S.Center_Y, Inner, Outer,
                                        -1.0, 0.0, X0, Y0, X1, Y1);
                  when others =>
                     Include_Direction (S.Center_X, S.Center_Y, Inner, Outer,
                                        0.0, -1.0, X0, Y0, X1, Y1);
               end case;
            end if;
         end loop;
      end;
   end Section_Box;

   procedure Get_Bounding_Box
     (Section                    : Ks_Circular_Annulus_Section;
      Min_X, Min_Y, Max_X, Max_Y : out Long_Float;
      Status                     : out Ks_Status)
   is
      X0, Y0, X1, Y1 : Long_Float;
   begin
      Min_X := 0.0;
      Min_Y := 0.0;
      Max_X := 0.0;
      Max_Y := 0.0;
      Check_Section (Section, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Section_Box (Section, X0, Y0, X1, Y1);
      if not (Bounded (X0) and then Bounded (X1) and then Bounded (Y0)
              and then Bounded (Y1))
      then
         Out_Of_Range
           (Status, "Ks_Circular_Annulus_Section.Get_Bounding_Box: the box");
         return;
      end if;
      Min_X := X0;
      Max_X := X1;
      Min_Y := Y0;
      Max_Y := Y1;
   end Get_Bounding_Box;

   procedure Area
     (Section : Ks_Circular_Annulus_Section;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   is
      Inner, Outer : Long_Float;
   begin
      Result := 0.0;
      Check_Section (Section, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Get_Radii (Section, Inner, Outer);
      Result := N.Mul
        (N.Times_Small
           (Outer - Inner,
            0.5 * Long_Float'Min (abs Section.Angle_Span, Two_Pi)),
         Outer + Inner);
   end Area;

   procedure Map
     (Section   : Ks_Circular_Annulus_Section;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Circular_Annulus_Section;
      Status    : out Ks_Status)
   is
      Kind      : Similarity_Kind;
      Candidate : Ks_Circular_Annulus_Section := Section;
   begin
      Result := (others => <>);
      Check_Section (Section, Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Transform) then
         Bad_Transform (Status);
         return;
      end if;
      Classify (Transform, Kind, Status);
      if not Succeeded (Status) then
         return;
      elsif Kind = Not_Similar then
         Not_Similar_Failure (Status, "Ks_Circular_Annulus_Section");
         return;
      end if;
      Map_Center_Radius
        (Transform, Section.Center_X, Section.Center_Y, Section.Radius,
         Candidate.Center_X, Candidate.Center_Y, Candidate.Radius, Status);
      if Succeeded (Status) then
         Map_Start_Angle
           (Transform, Kind, Section.Angle_Start, Candidate.Angle_Start,
            Status);
      end if;
      if not Succeeded (Status) then
         return;
      end if;
      --  A reflection reverses the sense of rotation.
      if Kind = Reflecting then
         Candidate.Angle_Span := -Section.Angle_Span;
      end if;
      if not (Candidate.Radius * Candidate.Radial_Scale <= Max_Length) then
         Out_Of_Range
           (Status, "Ks_Circular_Annulus_Section.Map: the mapped radii");
         return;
      end if;
      Result := Candidate;
   end Map;

   ---------------------------------------------------------------------
   --  CogLine
   ---------------------------------------------------------------------

   procedure Set_XY_Rotation
     (X, Y, Rotation : Long_Float;
      Result         : out Ks_Line;
      Status         : out Ks_Status)
   is
      Candidate : constant Ks_Line := (X, Y, Rotation);
   begin
      Result := (others => <>);
      Check_Line (Candidate, Status);
      if Succeeded (Status) then
         Result := Candidate;
      end if;
   end Set_XY_Rotation;

   procedure From_Points
     (Operation                      : Name_Text;
      Start_X, Start_Y, End_X, End_Y : Long_Float;
      Result                         : out Ks_Line;
      Status                         : out Ks_Status)
   with
     Post => Status_OK (Status)
             and then (if Succeeded (Status)
                       then Valid_Line (Result)
                            and then Result.X = Start_X
                            and then Result.Y = Start_Y
                            and then Result.Rotation > -Pi
                            and then Result.Rotation <= Pi);
   --  The line through both points, directed from start to end.

   procedure From_Points
     (Operation                      : Name_Text;
      Start_X, Start_Y, End_X, End_Y : Long_Float;
      Result                         : out Ks_Line;
      Status                         : out Ks_Status) is
   begin
      Result := (others => <>);
      if not Bounded (Start_X) then
         Bad_Coordinate (Status, "Start_X");
      elsif not Bounded (Start_Y) then
         Bad_Coordinate (Status, "Start_Y");
      elsif not Bounded (End_X) then
         Bad_Coordinate (Status, "End_X");
      elsif not Bounded (End_Y) then
         Bad_Coordinate (Status, "End_Y");
      else
         declare
            DX : constant Long_Float := End_X - Start_X;
            DY : constant Long_Float := End_Y - Start_Y;
         begin
            --  Two different floating-point numbers never have a zero
            --  difference, so this rejects exactly the same points.
            if DX = 0.0 and then DY = 0.0 then
               Bad (Status, "Ks_Line." & Operation
                            & ": the start and end points must differ");
               return;
            end if;
            Result := (Start_X, Start_Y, N.Direction (DY, DX));
            Set_Success (Status);
         end;
      end if;
   end From_Points;

   procedure Set_From_Start_XY_End_XY
     (Start_X, Start_Y, End_X, End_Y : Long_Float;
      Result                         : out Ks_Line;
      Status                         : out Ks_Status) is
   begin
      From_Points ("Set_From_Start_XY_End_XY", Start_X, Start_Y, End_X,
                   End_Y, Result, Status);
   end Set_From_Start_XY_End_XY;

   procedure Set_From_Line_Segment
     (Segment : Ks_Line_Segment;
      Result  : out Ks_Line;
      Status  : out Ks_Status) is
   begin
      From_Points ("Set_From_Line_Segment", Segment.Start_X,
                   Segment.Start_Y, Segment.End_X, Segment.End_Y, Result,
                   Status);
   end Set_From_Line_Segment;

   procedure Set_Distance_Rotation
     (Distance, Rotation : Long_Float;
      Result             : out Ks_Line;
      Status             : out Ks_Status) is
   begin
      Result := (others => <>);
      if not (Distance >= -Max_Length and then Distance <= Max_Length) then
         Bad (Status, "Ks_Line.Distance must be finite and within "
                      & "+/-4.0E150");
         return;
      elsif not Bounded (Rotation) then
         Bad_Coordinate (Status, "Ks_Line.Rotation");
         return;
      end if;
      declare
         X : constant Long_Float :=
           -N.Times_Unit (Distance, EF.Sin (Rotation));
         Y : constant Long_Float := N.Times_Unit (Distance, EF.Cos (Rotation));
      begin
         if not (Bounded (X) and then Bounded (Y)) then
            Out_Of_Range (Status, "Ks_Line.X or Y");
            return;
         end if;
         Result := (X, Y, Rotation);
         Set_Success (Status);
      end;
   end Set_Distance_Rotation;

   procedure Get_Distance_Rotation
     (Line               : Ks_Line;
      Distance, Rotation : out Long_Float;
      Status             : out Ks_Status) is
   begin
      Distance := 0.0;
      Rotation := 0.0;
      Check_Line (Line, Status);
      if Succeeded (Status) then
         Distance := N.Times_Unit (Line.Y, EF.Cos (Line.Rotation))
                     - N.Times_Unit (Line.X, EF.Sin (Line.Rotation));
         Rotation := Line.Rotation;
      end if;
   end Get_Distance_Rotation;

   procedure Map
     (Line      : Ks_Line;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Line;
      Status    : out Ks_Status)
   is
      Candidate : Ks_Line;
   begin
      Result := (others => <>);
      Check_Line (Line, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KT.Map_Point (Transform, Line.X, Line.Y, Candidate.X, Candidate.Y,
                    Status);
      if not Succeeded (Status) then
         return;
      end if;
      KT.Map_Angle (Transform, Line.Rotation, Candidate.Rotation, Status);
      if Succeeded (Status) then
         Result := Candidate;
      end if;
   end Map;

   ---------------------------------------------------------------------
   --  CogLineSegment
   ---------------------------------------------------------------------

   procedure Set_Start_End
     (Start_X, Start_Y, End_X, End_Y : Long_Float;
      Result                         : out Ks_Line_Segment;
      Status                         : out Ks_Status)
   is
      Candidate : constant Ks_Line_Segment :=
        (Start_X, Start_Y, End_X, End_Y);
   begin
      Result := (others => <>);
      Check_Segment (Candidate, Status);
      if Succeeded (Status) then
         Result := Candidate;
      end if;
   end Set_Start_End;

   procedure Set_Start_Length_Rotation
     (Start_X, Start_Y, Length, Rotation : Long_Float;
      Result                            : out Ks_Line_Segment;
      Status                            : out Ks_Status) is
   begin
      Result := (others => <>);
      if not Bounded (Start_X) then
         Bad_Coordinate (Status, "Ks_Line_Segment.Start_X");
      elsif not Bounded (Start_Y) then
         Bad_Coordinate (Status, "Ks_Line_Segment.Start_Y");
      elsif not Length_Bounded (Length) then
         Bad_Length (Status, "Ks_Line_Segment.Length", Length);
      elsif not Bounded (Rotation) then
         Bad_Coordinate (Status, "Ks_Line_Segment.Rotation");
      else
         declare
            End_X : constant Long_Float :=
              Start_X + N.Times_Unit (Length, EF.Cos (Rotation));
            End_Y : constant Long_Float :=
              Start_Y + N.Times_Unit (Length, EF.Sin (Rotation));
         begin
            if not (Bounded (End_X) and then Bounded (End_Y)) then
               Out_Of_Range (Status, "Ks_Line_Segment.End_X or End_Y");
               return;
            end if;
            Result := (Start_X, Start_Y, End_X, End_Y);
            Set_Success (Status);
         end;
      end if;
   end Set_Start_Length_Rotation;

   procedure Get_Start_Length_Rotation
     (Segment                            : Ks_Line_Segment;
      Start_X, Start_Y, Length, Rotation : out Long_Float;
      Status                             : out Ks_Status)
   is
      S : Ks_Line_Segment renames Segment;
   begin
      Start_X := 0.0;
      Start_Y := 0.0;
      Length := 0.0;
      Rotation := 0.0;
      Check_Segment (S, Status);
      if Succeeded (Status) then
         Start_X := S.Start_X;
         Start_Y := S.Start_Y;
         Length := N.Hypot (S.End_X - S.Start_X, S.End_Y - S.Start_Y);
         Rotation :=
           Direction_Or_Zero (S.End_Y - S.Start_Y, S.End_X - S.Start_X);
      end if;
   end Get_Start_Length_Rotation;

   procedure Get_Midpoint
     (Segment : Ks_Line_Segment;
      X, Y    : out Long_Float;
      Status  : out Ks_Status) is
   begin
      X := 0.0;
      Y := 0.0;
      Check_Segment (Segment, Status);
      if Succeeded (Status) then
         X := 0.5 * (Segment.Start_X + Segment.End_X);
         Y := 0.5 * (Segment.Start_Y + Segment.End_Y);
      end if;
   end Get_Midpoint;

   procedure Map
     (Segment   : Ks_Line_Segment;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Line_Segment;
      Status    : out Ks_Status)
   is
      Candidate : Ks_Line_Segment;
   begin
      Result := (others => <>);
      Check_Segment (Segment, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KT.Map_Point (Transform, Segment.Start_X, Segment.Start_Y,
                    Candidate.Start_X, Candidate.Start_Y, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KT.Map_Point (Transform, Segment.End_X, Segment.End_Y,
                    Candidate.End_X, Candidate.End_Y, Status);
      if Succeeded (Status) then
         Result := Candidate;
      end if;
   end Map;

   ---------------------------------------------------------------------
   --  CogPointMarker
   ---------------------------------------------------------------------

   procedure Set_XY_Rotation
     (X, Y, Rotation : Long_Float;
      Result         : out Ks_Point_Marker;
      Status         : out Ks_Status)
   is
      Candidate : constant Ks_Point_Marker := (X, Y, Rotation);
   begin
      Result := (others => <>);
      Check_Marker (Candidate, Status);
      if Succeeded (Status) then
         Result := Candidate;
      end if;
   end Set_XY_Rotation;

   procedure Map
     (Marker    : Ks_Point_Marker;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Point_Marker;
      Status    : out Ks_Status)
   is
      Candidate : Ks_Point_Marker;
   begin
      Result := (others => <>);
      Check_Marker (Marker, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KT.Map_Point (Transform, Marker.X, Marker.Y, Candidate.X, Candidate.Y,
                    Status);
      if not Succeeded (Status) then
         return;
      end if;
      KT.Map_Angle (Transform, Marker.Rotation, Candidate.Rotation, Status);
      if Succeeded (Status) then
         Result := Candidate;
      end if;
   end Map;

   ---------------------------------------------------------------------
   --  CogCircularArc
   ---------------------------------------------------------------------

   procedure Set_Center_Radius_Angle_Start_Angle_Span
     (Center_X, Center_Y, Radius, Angle_Start, Angle_Span : Long_Float;
      Result : out Ks_Circular_Arc;
      Status : out Ks_Status)
   is
      Candidate : constant Ks_Circular_Arc :=
        (Center_X, Center_Y, Radius, Angle_Start, Angle_Span);
   begin
      Result := (others => <>);
      Check_Arc (Candidate, Status);
      if Succeeded (Status) then
         Result := Candidate;
      end if;
   end Set_Center_Radius_Angle_Start_Angle_Span;

   procedure Get_Start_End
     (Arc                            : Ks_Circular_Arc;
      Start_X, Start_Y, End_X, End_Y : out Long_Float;
      Status                         : out Ks_Status) is
   begin
      Start_X := 0.0;
      Start_Y := 0.0;
      End_X := 0.0;
      End_Y := 0.0;
      Check_Arc (Arc, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         End_Angle : constant Long_Float := Arc.Angle_Start + Arc.Angle_Span;
         SX : constant Long_Float :=
           Arc.Center_X + N.Times_Unit (Arc.Radius, EF.Cos (Arc.Angle_Start));
         SY : constant Long_Float :=
           Arc.Center_Y + N.Times_Unit (Arc.Radius, EF.Sin (Arc.Angle_Start));
         EX : constant Long_Float :=
           Arc.Center_X + N.Times_Unit (Arc.Radius, EF.Cos (End_Angle));
         EY : constant Long_Float :=
           Arc.Center_Y + N.Times_Unit (Arc.Radius, EF.Sin (End_Angle));
      begin
         if not (Bounded (SX) and then Bounded (SY) and then Bounded (EX)
                 and then Bounded (EY))
         then
            Out_Of_Range (Status, "Ks_Circular_Arc: an end point");
            return;
         end if;
         Start_X := SX;
         Start_Y := SY;
         End_X := EX;
         End_Y := EY;
      end;
   end Get_Start_End;

   procedure Map
     (Arc       : Ks_Circular_Arc;
      Transform : KT.Ks_Transform_2D_Linear;
      Result    : out Ks_Circular_Arc;
      Status    : out Ks_Status)
   is
      Kind      : Similarity_Kind;
      Candidate : Ks_Circular_Arc := Arc;
   begin
      Result := (others => <>);
      Check_Arc (Arc, Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Transform) then
         Bad_Transform (Status);
         return;
      end if;
      Classify (Transform, Kind, Status);
      if not Succeeded (Status) then
         return;
      elsif Kind = Not_Similar then
         Not_Similar_Failure (Status, "Ks_Circular_Arc");
         return;
      end if;
      Map_Center_Radius
        (Transform, Arc.Center_X, Arc.Center_Y, Arc.Radius,
         Candidate.Center_X, Candidate.Center_Y, Candidate.Radius, Status);
      if Succeeded (Status) then
         Map_Start_Angle
           (Transform, Kind, Arc.Angle_Start, Candidate.Angle_Start, Status);
      end if;
      if not Succeeded (Status) then
         return;
      end if;
      --  A reflection reverses the sense of rotation.
      if Kind = Reflecting then
         Candidate.Angle_Span := -Arc.Angle_Span;
      end if;
      Result := Candidate;
   end Map;

end AMV.Kernels.Shapes;
