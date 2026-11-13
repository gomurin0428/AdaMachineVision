--  Tests for AMV.Shapes (shapes and regions) and AMV.Shapes.Region_Holders.

with Ada.Exceptions;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Tags;

with AMV;              use AMV;
with AMV.Misc;
with AMV.Shapes;       use AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Transforms;   use AMV.Transforms;
with AMV_Test_Support; use AMV_Test_Support;

procedure Test_Shapes is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   use type Ada.Tags.Tag;

   Pi  : constant := AMV.Misc.Pi;
   Tol : constant := 1.0E-12;
   H2  : constant Real := EF.Sqrt (2.0) / 2.0;   --  sin (Pi/4)

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   type Point is record
      X, Y : Real := 0.0;
   end record;

   type Point_Array is array (Positive range <>) of Point;

   function Map_P (T : Ks_Transform_2D_Linear; P : Point) return Point is
      Result : Point;
   begin
      T.Map_Point (P.X, P.Y, Result.X, Result.Y);
      return Result;
   end Map_P;

   function Segment_Samples
     (A, B : Point; N : Positive) return Point_Array
   is
      Result : Point_Array (1 .. N + 1);
   begin
      for K in 0 .. N loop
         declare
            T : constant Real := Real (K) / Real (N);
         begin
            Result (K + 1) :=
              (A.X + T * (B.X - A.X), A.Y + T * (B.Y - A.Y));
         end;
      end loop;
      return Result;
   end Segment_Samples;

   function Closed_Polyline_Samples
     (Corners : Point_Array; N_Per_Edge : Positive) return Point_Array
   is
      Per    : constant Positive := N_Per_Edge + 1;
      Result : Point_Array (1 .. Corners'Length * Per);
      Next   : Positive := 1;
   begin
      for I in Corners'Range loop
         declare
            J : constant Positive :=
              (if I = Corners'Last then Corners'First else I + 1);
         begin
            Result (Next .. Next + Per - 1) :=
              Segment_Samples (Corners (I), Corners (J), N_Per_Edge);
            Next := Next + Per;
         end;
      end loop;
      return Result;
   end Closed_Polyline_Samples;

   function Ellipse_Samples
     (CX, CY, RX, RY, Rot : Real; N : Positive) return Point_Array
   is
      Result : Point_Array (1 .. N);
      C : constant Real := EF.Cos (Rot);
      S : constant Real := EF.Sin (Rot);
   begin
      for K in 1 .. N loop
         declare
            A  : constant Real := 2.0 * Pi * Real (K - 1) / Real (N);
            U  : constant Real := RX * EF.Cos (A);
            V  : constant Real := RY * EF.Sin (A);
         begin
            Result (K) := (CX + U * C - V * S, CY + U * S + V * C);
         end;
      end loop;
      return Result;
   end Ellipse_Samples;

   function Arc_Samples
     (CX, CY, R, Start, Span : Real; N : Positive) return Point_Array
   is
      Result : Point_Array (1 .. N + 1);
   begin
      for K in 0 .. N loop
         declare
            A : constant Real := Start + Span * Real (K) / Real (N);
         begin
            Result (K + 1) := (CX + R * EF.Cos (A), CY + R * EF.Sin (A));
         end;
      end loop;
      return Result;
   end Arc_Samples;

   function Annulus_Samples
     (S : Ks_Circular_Annulus_Section; N : Positive) return Point_Array
   is
      R1 : constant Real := S.Radius;
      R2 : constant Real := S.Radius * S.Radial_Scale;
      Span : constant Real :=
        (if abs S.Angle_Span >= 2.0 * Pi then 2.0 * Pi else S.Angle_Span);
      End_A : constant Real := S.Angle_Start + Span;
   begin
      if abs S.Angle_Span >= 2.0 * Pi then
         --  A full annulus: the radial segment at the start is interior.
         return Arc_Samples
             (S.Center_X, S.Center_Y, R1, S.Angle_Start, Span, N)
           & Arc_Samples
             (S.Center_X, S.Center_Y, R2, S.Angle_Start, Span, N);
      end if;
      return Arc_Samples (S.Center_X, S.Center_Y, R1, S.Angle_Start, Span, N)
        & Arc_Samples (S.Center_X, S.Center_Y, R2, S.Angle_Start, Span, N)
        & Segment_Samples
            ((S.Center_X + R1 * EF.Cos (S.Angle_Start),
              S.Center_Y + R1 * EF.Sin (S.Angle_Start)),
             (S.Center_X + R2 * EF.Cos (S.Angle_Start),
              S.Center_Y + R2 * EF.Sin (S.Angle_Start)), 50)
        & Segment_Samples
            ((S.Center_X + R1 * EF.Cos (End_A),
              S.Center_Y + R1 * EF.Sin (End_A)),
             (S.Center_X + R2 * EF.Cos (End_A),
              S.Center_Y + R2 * EF.Sin (End_A)), 50);
   end Annulus_Samples;

   function Rectangle_Samples (R : Ks_Rectangle) return Point_Array is
     (Closed_Polyline_Samples
        ([(R.X, R.Y), (R.X + R.Width, R.Y),
          (R.X + R.Width, R.Y + R.Height), (R.X, R.Y + R.Height)], 40));

   function Affine_Samples (R : Ks_Rectangle_Affine) return Point_Array is
     (Closed_Polyline_Samples
        ([(R.Corner_Origin_X, R.Corner_Origin_Y),
          (R.Corner_X_X, R.Corner_X_Y),
          (R.Corner_Opposite_X, R.Corner_Opposite_Y),
          (R.Corner_Y_X, R.Corner_Y_Y)], 40));

   function Polygon_Samples (P : Ks_Polygon) return Point_Array is
      Corners : Point_Array (1 .. P.Num_Vertices);
   begin
      for I in Corners'Range loop
         Corners (I) := (P.Get_Vertex_X (I - 1), P.Get_Vertex_Y (I - 1));
      end loop;
      return Closed_Polyline_Samples (Corners, 40);
   end Polygon_Samples;

   function Contains (R : Ks_Region'Class; P : Point) return Boolean is
     (R.Contains_Point (P.X, P.Y));

   function On_Boundary
     (R : Ks_Region'Class; P : Point; Eps : Real) return Boolean is
   begin
      if not Contains (R, P) then
         return False;
      end if;
      for K in 0 .. 15 loop
         declare
            A : constant Real := Real (K) * Pi / 8.0;
         begin
            if not R.Contains_Point
              (P.X + Eps * EF.Cos (A), P.Y + Eps * EF.Sin (A))
            then
               return True;
            end if;
         end;
      end loop;
      return False;
   end On_Boundary;
   --  True when P is in R and some point at distance Eps from it is not.

   function Is_Interior
     (R : Ks_Region'Class; P : Point; Eps : Real) return Boolean is
   begin
      if not Contains (R, P) then
         return False;
      end if;
      for K in 0 .. 15 loop
         declare
            A : constant Real := Real (K) * Pi / 8.0;
         begin
            if not R.Contains_Point
              (P.X + Eps * EF.Cos (A), P.Y + Eps * EF.Sin (A))
            then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Is_Interior;

   procedure Check_All_On_Boundary
     (R : Ks_Region'Class; Samples : Point_Array; Eps : Real;
      Label : String)
   is
      Bad   : Natural := 0;
      First : Point;
   begin
      for P of Samples loop
         if not On_Boundary (R, P, Eps) then
            if Bad = 0 then
               First := P;
            end if;
            Bad := Bad + 1;
         end if;
      end loop;
      Check (Bad = 0,
             Label & ":" & Natural'Image (Bad) & " of"
             & Natural'Image (Samples'Length)
             & " samples not on the boundary"
             & (if Bad > 0
                then ", first at" & Real'Image (First.X) & ","
                     & Real'Image (First.Y)
                else ""));
   end Check_All_On_Boundary;

   type Sample_Box is record
      Min_X, Min_Y : Real := Real'Last;
      Max_X, Max_Y : Real := Real'First;
   end record;
   --  The extremes of a set of boundary samples; the default is the box
   --  of the empty set, which every Include widens.

   procedure Include (Box : in out Sample_Box; X, Y : Real) is
   begin
      Box.Min_X := Real'Min (Box.Min_X, X);
      Box.Min_Y := Real'Min (Box.Min_Y, Y);
      Box.Max_X := Real'Max (Box.Max_X, X);
      Box.Max_Y := Real'Max (Box.Max_Y, Y);
   end Include;

   procedure Check_Box_Against_Sample_Box
     (R         : Ks_Region'Class;
      Samples   : Sample_Box;
      Tight_Tol : Real;
      Label     : String)
   is
      Min_X, Min_Y, Max_X, Max_Y : Real;
   begin
      R.Get_Bounding_Box (Min_X, Min_Y, Max_X, Max_Y);
      Check (Samples.Min_X >= Min_X - 1.0E-9
             and then Samples.Max_X <= Max_X + 1.0E-9
             and then Samples.Min_Y >= Min_Y - 1.0E-9
             and then Samples.Max_Y <= Max_Y + 1.0E-9,
             Label & ": every boundary sample is inside the box");
      Check_Near (Min_X, Samples.Min_X, Tight_Tol, Label & " Min_X");
      Check_Near (Min_Y, Samples.Min_Y, Tight_Tol, Label & " Min_Y");
      Check_Near (Max_X, Samples.Max_X, Tight_Tol, Label & " Max_X");
      Check_Near (Max_Y, Samples.Max_Y, Tight_Tol, Label & " Max_Y");
   end Check_Box_Against_Sample_Box;
   --  The box of R must contain every sample and match their extremes
   --  within Tight_Tol.

   procedure Check_Box_Against_Samples
     (R         : Ks_Region'Class;
      Samples   : Point_Array;
      Tight_Tol : Real;
      Label     : String)
   is
      Box : Sample_Box;
   begin
      for P of Samples loop
         Include (Box, P.X, P.Y);
      end loop;
      Check_Box_Against_Sample_Box (R, Box, Tight_Tol, Label);
   end Check_Box_Against_Samples;

   function Annulus_Sample_Box
     (S : Ks_Circular_Annulus_Section; N : Positive) return Sample_Box
   is
      R1 : constant Real := S.Radius;
      R2 : constant Real := S.Radius * S.Radial_Scale;
      Full : constant Boolean := abs S.Angle_Span >= 2.0 * Pi;
      Span : constant Real := (if Full then 2.0 * Pi else S.Angle_Span);
      Box : Sample_Box;

      procedure Include_Segment (Angle : Real) is
         C : constant Real := EF.Cos (Angle);
         Sn : constant Real := EF.Sin (Angle);
      begin
         for K in 0 .. 50 loop
            declare
               T : constant Real := Real (K) / 50.0;
               R : constant Real := R1 + T * (R2 - R1);
            begin
               Include (Box, S.Center_X + R * C, S.Center_Y + R * Sn);
            end;
         end loop;
      end Include_Segment;

   begin
      for K in 0 .. N loop
         declare
            A : constant Real := S.Angle_Start + Span * Real (K) / Real (N);
            C : constant Real := EF.Cos (A);
            Sn : constant Real := EF.Sin (A);
         begin
            Include (Box, S.Center_X + R1 * C, S.Center_Y + R1 * Sn);
            Include (Box, S.Center_X + R2 * C, S.Center_Y + R2 * Sn);
         end;
      end loop;
      if not Full then
         Include_Segment (S.Angle_Start);
         Include_Segment (S.Angle_Start + Span);
      end if;
      return Box;
   end Annulus_Sample_Box;
   --  The extremes of the same boundary samples as Annulus_Samples (both
   --  arcs with N steps, and the two radial edges of a partial section),
   --  computed without storing them: with a large N the sample array
   --  would need megabytes of primary stack, more than a main program
   --  linked with the tasking runtime gets by default.

   procedure Check_Box
     (R : Ks_Region'Class; Min_X, Min_Y, Max_X, Max_Y : Real;
      Tolerance : Real; Label : String)
   is
      A, B, C, D : Real;
   begin
      R.Get_Bounding_Box (A, B, C, D);
      Check_Near (A, Min_X, Tolerance, Label & " Min_X");
      Check_Near (B, Min_Y, Tolerance, Label & " Min_Y");
      Check_Near (C, Max_X, Tolerance, Label & " Max_X");
      Check_Near (D, Max_Y, Tolerance, Label & " Max_Y");
   end Check_Box;

   --  The transforms used for the Map tests.

   type Map_Case is
     (MC_Identity, MC_Translation, MC_Rotation, MC_Uniform_Scaling,
      MC_Similarity, MC_Anisotropic, MC_Reflection, MC_Reflection_Rotated,
      MC_Shear);

   subtype Similar_Case is Map_Case range MC_Identity .. MC_Similarity;
   --  Proper similarities; MC_Reflection and MC_Reflection_Rotated are
   --  similarities with a reflection.

   function Transform_Of (C : Map_Case) return Ks_Transform_2D_Linear is
     (case C is
         when MC_Identity           => Identity,
         when MC_Translation        =>
           Create (1.0, 0.0, 0.0, 1.0, 10.0, -20.0),
         when MC_Rotation           => Create_Rigid (Pi / 6.0, 5.0, 7.0),
         when MC_Uniform_Scaling    => Create_Similarity (2.5, 0.0, 1.0, 2.0),
         when MC_Similarity         =>
           Create_Similarity (0.75, -2.0, -4.0, 3.0),
         when MC_Anisotropic        => Create (2.0, 0.0, 0.0, 0.5, 3.0, 4.0),
         when MC_Reflection         =>
           Create (-1.0, 0.0, 0.0, 1.0, 100.0, 0.0),
         when MC_Reflection_Rotated =>
           Create (1.5 * EF.Cos (0.6), 1.5 * EF.Sin (0.6),
                   1.5 * EF.Sin (0.6), -1.5 * EF.Cos (0.6), -2.0, 5.0),
         when MC_Shear              =>
           Create (1.2, 0.4, -0.3, 0.9, 7.0, -3.0));

   function Is_Similar (C : Map_Case) return Boolean is
     (C in Similar_Case | MC_Reflection | MC_Reflection_Rotated);

   procedure Check_Map_Region
     (Region  : Ks_Region'Class;
      Samples : Point_Array;
      Inside  : Point;
      T       : Ks_Transform_2D_Linear;
      Label   : String)
   is
      M : constant Ks_Shape'Class := Region.Map (T);
   begin
      Check (M in Ks_Region'Class, Label & ": the result is a region");
      if M not in Ks_Region'Class then
         return;
      end if;
      declare
         MR     : Ks_Region'Class renames Ks_Region'Class (M);
         Mapped : Point_Array (Samples'Range);
         Det    : constant Real := abs T.Matrix_Determinant;
      begin
         for I in Samples'Range loop
            Mapped (I) := Map_P (T, Samples (I));
         end loop;
         Check_All_On_Boundary (MR, Mapped, 1.0E-4, Label & " boundary");
         Check (Is_Interior (MR, Map_P (T, Inside), 1.0E-4),
                Label & ": an interior point maps inside");
         Check_Near (MR.Area, Region.Area * Det,
                     1.0E-9 * (1.0 + Region.Area * Det), Label & " area");
         Check (MR.Selected_Space_Name = Region.Selected_Space_Name,
                Label & ": selected space name kept");
      end;
   end Check_Map_Region;

   ---------------------------------------------------------------------
   --  Exception cases
   ---------------------------------------------------------------------

   type Bad_Parameter_Case is
     (Rect_Width, Rect_Height, Rect_XYWH_Width, Rect_XYWH_Height,
      Rect_Center_Width, Rect_Center_Height,
      Affine_Side_X, Affine_Side_Y, Affine_Center_Lengths_X,
      Affine_Center_Lengths_Y, Affine_Origin_Lengths_X,
      Affine_Origin_Lengths_Y,
      Circle_Radius, Circle_Center_Radius,
      Ellipse_Radius_X, Ellipse_Radius_Y, Ellipse_All_X, Ellipse_All_Y,
      Annulus_Radius, Annulus_Radial_Scale, Annulus_All_Radius,
      Annulus_All_Scale, Annulus_Map_Anisotropic, Annulus_Map_Shear,
      Annulus_Map_Singular,
      Line_Same_Points, Segment_Length,
      Arc_Radius, Arc_All_Radius, Arc_Map_Anisotropic, Arc_Map_Shear);

   Current_Bad : Bad_Parameter_Case := Rect_Width;

   procedure Run_Bad_Parameter_Case is
      Rect    : Ks_Rectangle;
      Affine  : Ks_Rectangle_Affine;
      Circle  : Ks_Circle;
      Ell     : Ks_Ellipse;
      Annulus : Ks_Circular_Annulus_Section;
      Line    : Ks_Line;
      Segment : Ks_Line_Segment;
      Arc     : Ks_Circular_Arc;
   begin
      case Current_Bad is
         when Rect_Width         => Rect.Set_Width (-1.0);
         when Rect_Height        => Rect.Set_Height (-0.5);
         when Rect_XYWH_Width    =>
            Rect.Set_XY_Width_Height (0.0, 0.0, -1.0, 1.0);
         when Rect_XYWH_Height   =>
            Rect.Set_XY_Width_Height (0.0, 0.0, 1.0, -1.0);
         when Rect_Center_Width  =>
            Rect.Set_Center_Width_Height (0.0, 0.0, -1.0, 1.0);
         when Rect_Center_Height =>
            Rect.Set_Center_Width_Height (0.0, 0.0, 1.0, -1.0E-300);
         when Affine_Side_X      => Affine.Set_Side_X_Length (-1.0);
         when Affine_Side_Y      => Affine.Set_Side_Y_Length (-1.0);
         when Affine_Center_Lengths_X =>
            Affine.Set_Center_Lengths_Rotation_Skew
              (0.0, 0.0, -1.0, 1.0, 0.0, 0.0);
         when Affine_Center_Lengths_Y =>
            Affine.Set_Center_Lengths_Rotation_Skew
              (0.0, 0.0, 1.0, -1.0, 0.0, 0.0);
         when Affine_Origin_Lengths_X =>
            Affine.Set_Origin_Lengths_Rotation_Skew
              (0.0, 0.0, -1.0, 1.0, 0.0, 0.0);
         when Affine_Origin_Lengths_Y =>
            Affine.Set_Origin_Lengths_Rotation_Skew
              (0.0, 0.0, 1.0, -1.0, 0.0, 0.0);
         when Circle_Radius      => Circle.Set_Radius (-1.0);
         when Circle_Center_Radius =>
            Circle.Set_Center_Radius (1.0, 1.0, -2.0);
         when Ellipse_Radius_X   => Ell.Set_Radius_X (-1.0);
         when Ellipse_Radius_Y   => Ell.Set_Radius_Y (-1.0);
         when Ellipse_All_X      =>
            Ell.Set_Center_XY_Radius_XY_Rotation (0.0, 0.0, -1.0, 1.0, 0.0);
         when Ellipse_All_Y      =>
            Ell.Set_Center_XY_Radius_XY_Rotation (0.0, 0.0, 1.0, -1.0, 0.0);
         when Annulus_Radius     => Annulus.Set_Radius (-1.0);
         when Annulus_Radial_Scale => Annulus.Set_Radial_Scale (-0.1);
         when Annulus_All_Radius =>
            Annulus.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
              (0.0, 0.0, -1.0, 0.0, 1.0, 1.0);
         when Annulus_All_Scale  =>
            Annulus.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
              (0.0, 0.0, 1.0, 0.0, 1.0, -1.0);
         when Annulus_Map_Anisotropic =>
            Check (Annulus.Map (Transform_Of (MC_Anisotropic)) in Ks_Shape,
                   "unreachable");
         when Annulus_Map_Shear =>
            Check (Annulus.Map (Transform_Of (MC_Shear)) in Ks_Shape,
                   "unreachable");
         when Annulus_Map_Singular =>
            Check (Annulus.Map (Create (0.0, 0.0, 0.0, 0.0, 1.0, 1.0))
                     in Ks_Shape, "unreachable");
         when Line_Same_Points   =>
            Line.Set_From_Start_XY_End_XY (3.0, 4.0, 3.0, 4.0);
         when Segment_Length     =>
            Segment.Set_Start_Length_Rotation (0.0, 0.0, -1.0, 0.0);
         when Arc_Radius         => Arc.Set_Radius (-1.0);
         when Arc_All_Radius     =>
            Arc.Set_Center_Radius_Angle_Start_Angle_Span
              (0.0, 0.0, -3.0, 0.0, 1.0);
         when Arc_Map_Anisotropic =>
            Check (Arc.Map (Transform_Of (MC_Anisotropic)) in Ks_Shape,
                   "unreachable");
         when Arc_Map_Shear =>
            Check (Arc.Map (Transform_Of (MC_Shear)) in Ks_Shape,
                   "unreachable");
      end case;
   end Run_Bad_Parameter_Case;

   procedure Check_Bad_Parameter is new Check_Raises_Exactly
     (Run_Bad_Parameter_Case, Ks_Bad_Parameter_Exception'Identity);

   type Index_Case is
     (Get_X_Empty, Get_X_Past_End, Get_Y_Past_End, Set_Past_End,
      Add_Too_Large, Add_Below_Minus_One, Remove_Past_End, Remove_Empty);

   Current_Index : Index_Case := Get_X_Empty;

   procedure Run_Index_Case is
      P : Ks_Polygon;
   begin
      if Current_Index /= Get_X_Empty and then Current_Index /= Remove_Empty
      then
         P.Add_Vertex (0.0, 0.0);
         P.Add_Vertex (1.0, 0.0);
         P.Add_Vertex (0.0, 1.0);
      end if;
      case Current_Index is
         when Get_X_Empty | Get_X_Past_End =>
            Check (P.Get_Vertex_X (P.Num_Vertices) = 0.0, "unreachable");
         when Get_Y_Past_End =>
            Check (P.Get_Vertex_Y (3) = 0.0, "unreachable");
         when Set_Past_End => P.Set_Vertex (3, 1.0, 1.0);
         when Add_Too_Large => P.Add_Vertex (1.0, 1.0, Index => 4);
         when Add_Below_Minus_One => P.Add_Vertex (1.0, 1.0, Index => -2);
         when Remove_Past_End => P.Remove_Vertex (3);
         when Remove_Empty => P.Remove_Vertex (0);
      end case;
   end Run_Index_Case;

   procedure Check_Index_Error is new Check_Raises_Exactly
     (Run_Index_Case, Constraint_Error'Identity);

   type Singular_Case is (Line_Map, Marker_Map);
   Current_Singular : Singular_Case := Line_Map;

   procedure Run_Singular_Case is
      --  Maps the direction (1, 1) to the zero vector.
      T      : constant Ks_Transform_2D_Linear :=
        Create (1.0, -1.0, 1.0, -1.0, 0.0, 0.0);
      Line   : Ks_Line;
      Marker : Ks_Point_Marker;
   begin
      case Current_Singular is
         when Line_Map =>
            Line.Set_Rotation (Pi / 4.0);
            Check (Line.Map (T) in Ks_Shape, "unreachable");
         when Marker_Map =>
            Marker.Set_Rotation (Pi / 4.0);
            Check (Marker.Map (T) in Ks_Shape, "unreachable");
      end case;
   end Run_Singular_Case;

   procedure Check_Singular is new Check_Raises_Exactly
     (Run_Singular_Case, Ks_Transform_Singular_Exception'Identity);

   ---------------------------------------------------------------------
   --  Test groups
   ---------------------------------------------------------------------

   procedure Test_Defaults is
      Rect    : Ks_Rectangle;
      Affine  : Ks_Rectangle_Affine;
      Circle  : Ks_Circle;
      Ell     : Ks_Ellipse;
      Poly    : Ks_Polygon;
      Annulus : Ks_Circular_Annulus_Section;
      Line    : Ks_Line;
      Segment : Ks_Line_Segment;
      Marker  : Ks_Point_Marker;
      Arc     : Ks_Circular_Arc;
   begin
      Section ("defaults");
      Check (Rect.X = 0.0 and then Rect.Y = 0.0
             and then Rect.Width = 100.0 and then Rect.Height = 100.0,
             "rectangle 0, 0, 100 x 100");
      Check (Rect.Center_X = 50.0 and then Rect.Center_Y = 50.0,
             "rectangle centre");
      Check (Affine.Center_X = 50.0 and then Affine.Center_Y = 50.0
             and then Affine.Side_X_Length = 100.0
             and then Affine.Side_Y_Length = 100.0
             and then Affine.Rotation = 0.0 and then Affine.Skew = 0.0,
             "affine rectangle");
      Check_Near (Affine.Corner_Origin_X, 0.0, Tol, "affine origin x");
      Check_Near (Affine.Corner_Origin_Y, 0.0, Tol, "affine origin y");
      Check_Near (Affine.Corner_X_X, 100.0, Tol, "affine corner X x");
      Check_Near (Affine.Corner_X_Y, 0.0, Tol, "affine corner X y");
      Check_Near (Affine.Corner_Y_X, 0.0, Tol, "affine corner Y x");
      Check_Near (Affine.Corner_Y_Y, 100.0, Tol, "affine corner Y y");
      Check_Near (Affine.Corner_Opposite_X, 100.0, Tol, "affine opp x");
      Check_Near (Affine.Corner_Opposite_Y, 100.0, Tol, "affine opp y");
      Check (Circle.Center_X = 0.0 and then Circle.Center_Y = 0.0
             and then Circle.Radius = 50.0, "circle");
      Check (Ell.Center_X = 0.0 and then Ell.Center_Y = 0.0
             and then Ell.Radius_X = 50.0 and then Ell.Radius_Y = 25.0
             and then Ell.Rotation = 0.0, "ellipse");
      Check (Poly.Num_Vertices = 0, "polygon has no vertices");
      Check (Annulus.Center_X = 0.0 and then Annulus.Center_Y = 0.0
             and then Annulus.Radius = 50.0
             and then Annulus.Radial_Scale = 1.5
             and then Annulus.Angle_Start = 0.0,
             "annulus section");
      Check_Near (Annulus.Angle_Span, 2.0 * Pi, 1.0E-15, "annulus span");
      Check (Line.X = 0.0 and then Line.Y = 0.0
             and then Line.Rotation = 0.0, "line");
      Check (Segment.Start_X = 0.0 and then Segment.Start_Y = 0.0
             and then Segment.End_X = 100.0 and then Segment.End_Y = 0.0,
             "segment");
      Check (Marker.X = 0.0 and then Marker.Y = 0.0
             and then Marker.Rotation = 0.0, "point marker");
      Check (Arc.Center_X = 0.0 and then Arc.Center_Y = 0.0
             and then Arc.Radius = 50.0 and then Arc.Angle_Start = 0.0,
             "arc");
      Check_Near (Arc.Angle_Span, Pi, 1.0E-15, "arc span");

      Check (Rect.Selected_Space_Name = "."
             and then Affine.Selected_Space_Name = "."
             and then Circle.Selected_Space_Name = "."
             and then Ell.Selected_Space_Name = "."
             and then Poly.Selected_Space_Name = "."
             and then Annulus.Selected_Space_Name = "."
             and then Line.Selected_Space_Name = "."
             and then Segment.Selected_Space_Name = "."
             and then Marker.Selected_Space_Name = "."
             and then Arc.Selected_Space_Name = ".",
             "every shape starts in space "".""");
      Rect.Set_Selected_Space_Name ("@\Fixture");
      Check (Rect.Selected_Space_Name = "@\Fixture", "space name set");
      Rect.Set_Selected_Space_Name ("");
      Check (Rect.Selected_Space_Name = "", "empty space name kept");
   end Test_Defaults;

   procedure Test_Rectangle is
      R : Ks_Rectangle;
   begin
      Section ("rectangle setters");
      R.Set_X (-3.0);
      R.Set_Y (4.5);
      R.Set_Width (10.0);
      R.Set_Height (6.0);
      Check (R.X = -3.0 and then R.Y = 4.5 and then R.Width = 10.0
             and then R.Height = 6.0, "individual setters");
      Check (R.Center_X = 2.0 and then R.Center_Y = 7.5, "centre");
      R.Set_XY_Width_Height (1.0, 2.0, 3.0, 4.0);
      Check (R.X = 1.0 and then R.Y = 2.0 and then R.Width = 3.0
             and then R.Height = 4.0, "Set_XY_Width_Height");
      R.Set_Center_Width_Height (10.0, 20.0, 8.0, 2.0);
      Check (R.X = 6.0 and then R.Y = 19.0 and then R.Width = 8.0
             and then R.Height = 2.0, "Set_Center_Width_Height");
      R.Set_Width (0.0);
      R.Set_Height (0.0);
      Check (R.Width = 0.0 and then R.Height = 0.0, "zero size allowed");

      --  A failed setter leaves the rectangle unchanged.
      R.Set_XY_Width_Height (1.0, 2.0, 3.0, 4.0);
      begin
         R.Set_XY_Width_Height (9.0, 9.0, 9.0, -9.0);
      exception
         when Ks_Bad_Parameter_Exception => null;
      end;
      Check (R.X = 1.0 and then R.Y = 2.0 and then R.Width = 3.0
             and then R.Height = 4.0, "failed set leaves it unchanged");
      begin
         R.Set_Width (-1.0);
      exception
         when E : Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E)
                     = "Ks_Rectangle.Width must be >= 0",
                   "message names the property");
      end;
      Check (R.Width = 3.0, "failed Set_Width leaves it unchanged");

      Section ("rectangle contains");
      R.Set_XY_Width_Height (0.0, 0.0, 100.0, 100.0);
      Check (R.Contains_Point (50.0, 50.0), "centre");
      Check (R.Contains_Point (0.0, 0.0), "corner (0, 0)");
      Check (R.Contains_Point (100.0, 100.0), "corner (100, 100)");
      Check (R.Contains_Point (100.0, 37.0), "right edge");
      Check (R.Contains_Point (12.0, 0.0), "top edge");
      Check (R.Contains_Point (100.0 + 1.0E-8, 50.0),
             "within the documented slack (2E-7 here)");
      Check (not R.Contains_Point (100.0 + 1.0E-6, 50.0),
             "just right of the edge");
      Check (not R.Contains_Point (50.0, -1.0E-6), "just above");
      Check (not R.Contains_Point (-1.0E-6, -1.0E-6), "near corner");
      Check (not R.Contains_Point (150.0, 50.0), "far outside");
      R.Set_XY_Width_Height (2.0, 3.0, 0.0, 5.0);
      Check (R.Contains_Point (2.0, 4.0), "zero width: on the segment");
      Check (not R.Contains_Point (2.001, 4.0), "zero width: beside it");

      Section ("rectangle box and area");
      R.Set_XY_Width_Height (-5.0, 7.0, 12.0, 3.0);
      Check_Box (R, -5.0, 7.0, 7.0, 10.0, 0.0, "box");
      Check_Box_Against_Samples (R, Rectangle_Samples (R), 1.0E-12,
                                 "sampled box");
      Check (R.Area = 36.0, "area");
      Check_All_On_Boundary (R, Rectangle_Samples (R), 1.0E-4,
                             "samples on the boundary");

      Section ("rectangle map");
      R.Set_XY_Width_Height (10.0, 20.0, 30.0, 40.0);
      R.Set_Selected_Space_Name ("@\A");
      declare
         M : constant Ks_Shape'Class :=
           R.Map (Transform_Of (MC_Translation));
      begin
         Check (M'Tag = Ks_Rectangle'Tag, "translation gives a rectangle");
         if M'Tag = Ks_Rectangle'Tag then
            declare
               MR : constant Ks_Rectangle := Ks_Rectangle (M);
            begin
               Check (MR.X = 20.0 and then MR.Y = 0.0
                      and then MR.Width = 30.0 and then MR.Height = 40.0,
                      "translated rectangle");
               Check (MR.Selected_Space_Name = "@\A", "space name kept");
            end;
         end if;
      end;
      declare
         M : constant Ks_Shape'Class :=
           R.Map (Transform_Of (MC_Anisotropic));
      begin
         Check (M'Tag = Ks_Rectangle'Tag, "axis scaling: a rectangle");
         if M'Tag = Ks_Rectangle'Tag then
            declare
               MR : constant Ks_Rectangle := Ks_Rectangle (M);
            begin
               Check_Near (MR.X, 23.0, Tol, "scaled X");
               Check_Near (MR.Y, 14.0, Tol, "scaled Y");
               Check_Near (MR.Width, 60.0, Tol, "scaled width");
               Check_Near (MR.Height, 20.0, Tol, "scaled height");
            end;
         end if;
      end;
      declare
         M : constant Ks_Shape'Class :=
           R.Map (Transform_Of (MC_Reflection));
      begin
         Check (M'Tag = Ks_Rectangle'Tag, "mirror: a rectangle");
         if M'Tag = Ks_Rectangle'Tag then
            declare
               MR : constant Ks_Rectangle := Ks_Rectangle (M);
            begin
               --  x -> 100 - x maps [10, 40] to [60, 90].
               Check_Near (MR.X, 60.0, Tol, "mirrored X normalised");
               Check_Near (MR.Width, 30.0, Tol, "mirrored width >= 0");
               Check_Near (MR.Y, 20.0, Tol, "mirrored Y");
               Check_Near (MR.Height, 40.0, Tol, "mirrored height");
            end;
         end if;
      end;
      declare
         M : constant Ks_Shape'Class :=
           R.Map (Create (-2.0, 0.0, 0.0, -3.0, 0.0, 0.0));
      begin
         Check (M'Tag = Ks_Rectangle'Tag, "point reflection: rectangle");
         if M'Tag = Ks_Rectangle'Tag then
            declare
               MR : constant Ks_Rectangle := Ks_Rectangle (M);
            begin
               Check_Near (MR.X, -80.0, Tol, "negated X");
               Check_Near (MR.Y, -180.0, Tol, "negated Y");
               Check_Near (MR.Width, 60.0, Tol, "negated width");
               Check_Near (MR.Height, 120.0, Tol, "negated height");
            end;
         end if;
      end;
      declare
         T : constant Ks_Transform_2D_Linear := Transform_Of (MC_Rotation);
         M : constant Ks_Shape'Class := R.Map (T);
         OX, OY : Real;
      begin
         Check (M'Tag = Ks_Rectangle_Affine'Tag,
                "rotation gives an affine rectangle");
         if M'Tag = Ks_Rectangle_Affine'Tag then
            declare
               MA : constant Ks_Rectangle_Affine :=
                 Ks_Rectangle_Affine (M);
            begin
               T.Map_Point (10.0, 20.0, OX, OY);
               Check_Near (MA.Corner_Origin_X, OX, 1.0E-12, "origin x");
               Check_Near (MA.Corner_Origin_Y, OY, 1.0E-12, "origin y");
               Check_Near (MA.Side_X_Length, 30.0, 1.0E-12, "side X");
               Check_Near (MA.Side_Y_Length, 40.0, 1.0E-12, "side Y");
               Check_Angle_Near (MA.Rotation, Pi / 6.0, 1.0E-12, "rotation");
               Check_Angle_Near (MA.Skew, 0.0, 1.0E-12, "skew");
               Check (MA.Selected_Space_Name = "@\A", "space name kept");
            end;
         end if;
      end;
      declare
         --  Swapping x and y is a reflection that is not axis aligned.
         M : constant Ks_Shape'Class :=
           R.Map (Create (0.0, 1.0, 1.0, 0.0, 0.0, 0.0));
      begin
         Check (M'Tag = Ks_Rectangle_Affine'Tag, "swap: affine");
         if M'Tag = Ks_Rectangle_Affine'Tag then
            declare
               MA : constant Ks_Rectangle_Affine :=
                 Ks_Rectangle_Affine (M);
            begin
               Check_Near (MA.Corner_X_X, 20.0, 1.0E-12, "swap corner X x");
               Check_Near (MA.Corner_X_Y, 40.0, 1.0E-12, "swap corner X y");
               Check_Near (MA.Corner_Y_X, 60.0, 1.0E-12, "swap corner Y x");
               Check_Near (MA.Corner_Y_Y, 10.0, 1.0E-12, "swap corner Y y");
               Check_Angle_Near (MA.Skew, Pi, 1.0E-12, "swap skew is Pi");
               Check_Near (MA.Area, 1200.0, 1.0E-9, "swap area");
            end;
         end if;
      end;
      for C in Map_Case loop
         Check_Map_Region
           (R, Rectangle_Samples (R), (25.0, 40.0), Transform_Of (C),
            "rectangle " & Map_Case'Image (C));
      end loop;
   end Test_Rectangle;

   procedure Test_Rectangle_Affine is
      R : Ks_Rectangle_Affine;
   begin
      Section ("affine rectangle setters");
      R.Set_Center_X (3.0);
      R.Set_Center_Y (-4.0);
      R.Set_Side_X_Length (7.0);
      R.Set_Side_Y_Length (2.0);
      R.Set_Rotation (0.25);
      R.Set_Skew (-0.5);
      Check (R.Center_X = 3.0 and then R.Center_Y = -4.0
             and then R.Side_X_Length = 7.0 and then R.Side_Y_Length = 2.0
             and then R.Rotation = 0.25 and then R.Skew = -0.5,
             "individual setters and getters");
      R.Set_Side_X_Length (11.0);
      R.Set_Rotation (1.0);
      R.Set_Skew (0.1);
      R.Set_Side_Y_Length (0.0);
      Check (R.Center_X = 3.0 and then R.Center_Y = -4.0,
             "setters keep the centre");
      Check_Near (0.5 * (R.Corner_Origin_X + R.Corner_Opposite_X), 3.0,
                  1.0E-12, "centre is the middle of the diagonal (x)");
      Check_Near (0.5 * (R.Corner_Origin_Y + R.Corner_Opposite_Y), -4.0,
                  1.0E-12, "centre is the middle of the diagonal (y)");

      Section ("affine rectangle corner formulas");
      --  Rotation Pi/2, skew -Pi/4: DX = (0, 1), DY = (-h, h).
      R.Set_Center_Lengths_Rotation_Skew
        (10.0, 20.0, 4.0, 6.0, Pi / 2.0, -Pi / 4.0);
      Check (R.Center_X = 10.0 and then R.Center_Y = 20.0
             and then R.Side_X_Length = 4.0 and then R.Side_Y_Length = 6.0
             and then R.Rotation = Pi / 2.0 and then R.Skew = -Pi / 4.0,
             "Set_Center_Lengths_Rotation_Skew stores the values");
      Check_Near (R.Corner_Origin_X, 10.0 + 3.0 * H2, Tol, "origin x");
      Check_Near (R.Corner_Origin_Y, 18.0 - 3.0 * H2, Tol, "origin y");
      Check_Near (R.Corner_X_X, 10.0 + 3.0 * H2, Tol, "corner X x");
      Check_Near (R.Corner_X_Y, 22.0 - 3.0 * H2, Tol, "corner X y");
      Check_Near (R.Corner_Y_X, 10.0 - 3.0 * H2, Tol, "corner Y x");
      Check_Near (R.Corner_Y_Y, 18.0 + 3.0 * H2, Tol, "corner Y y");
      Check_Near (R.Corner_Opposite_X, 10.0 - 3.0 * H2, Tol, "opposite x");
      Check_Near (R.Corner_Opposite_Y, 22.0 + 3.0 * H2, Tol, "opposite y");
      Check_Near (R.Area, 24.0 * H2, Tol, "area = SX SY cos K");

      --  General rotation and skew: check the defining relations.
      R.Set_Center_Lengths_Rotation_Skew (5.0, -3.0, 40.0, 20.0, 0.7, 0.2);
      declare
         OX : constant Real := R.Corner_Origin_X;
         OY : constant Real := R.Corner_Origin_Y;
      begin
         Check_Near (R.Corner_X_X - OX, 40.0 * EF.Cos (0.7), Tol,
                     "corner X = origin + SX DX (x)");
         Check_Near (R.Corner_X_Y - OY, 40.0 * EF.Sin (0.7), Tol,
                     "corner X = origin + SX DX (y)");
         Check_Near (R.Corner_Y_X - OX, -20.0 * EF.Sin (0.9), Tol,
                     "corner Y = origin + SY DY (x)");
         Check_Near (R.Corner_Y_Y - OY, 20.0 * EF.Cos (0.9), Tol,
                     "corner Y = origin + SY DY (y)");
         Check_Near (R.Corner_Opposite_X,
                     R.Corner_X_X + R.Corner_Y_X - OX, Tol, "opposite x");
         Check_Near (R.Corner_Opposite_Y,
                     R.Corner_X_Y + R.Corner_Y_Y - OY, Tol, "opposite y");
         Check_Near (0.5 * (OX + R.Corner_Opposite_X), 5.0, Tol, "centre x");
         Check_Near (0.5 * (OY + R.Corner_Opposite_Y), -3.0, Tol,
                     "centre y");
      end;

      Section ("affine rectangle constructors");
      R.Set_Origin_Lengths_Rotation_Skew (3.0, -2.0, 10.0, 5.0, -0.4, 0.3);
      Check_Near (R.Corner_Origin_X, 3.0, Tol, "origin x kept");
      Check_Near (R.Corner_Origin_Y, -2.0, Tol, "origin y kept");
      Check (R.Side_X_Length = 10.0 and then R.Side_Y_Length = 5.0
             and then R.Rotation = -0.4 and then R.Skew = 0.3,
             "lengths and angles stored");
      Check_Near (R.Center_X,
                  3.0 + 5.0 * EF.Cos (-0.4) - 2.5 * EF.Sin (-0.1), Tol,
                  "centre x from the origin");
      Check_Near (R.Center_Y,
                  -2.0 + 5.0 * EF.Sin (-0.4) + 2.5 * EF.Cos (-0.1), Tol,
                  "centre y from the origin");
      Check_Near (R.Corner_X_X, 3.0 + 10.0 * EF.Cos (-0.4), Tol,
                  "corner X x");
      Check_Near (R.Corner_Y_Y, -2.0 + 5.0 * EF.Cos (-0.1), Tol,
                  "corner Y y");

      R.Set_Origin_Corner_X_Corner_Y (1.0, 2.0, 4.0, 6.0, -3.0, 5.0);
      Check_Near (R.Side_X_Length, 5.0, Tol, "3-corner side X");
      Check_Near (R.Side_Y_Length, 5.0, Tol, "3-corner side Y");
      Check_Near (R.Rotation, EF.Arctan (4.0, 3.0), Tol, "3-corner rot");
      Check_Angle_Near (R.Skew, 0.0, Tol, "3-corner skew (square)");
      Check_Near (R.Center_X, 0.5, Tol, "3-corner centre x");
      Check_Near (R.Center_Y, 5.5, Tol, "3-corner centre y");
      Check_Near (R.Corner_Opposite_X, 0.0, Tol, "3-corner opposite x");
      Check_Near (R.Corner_Opposite_Y, 9.0, Tol, "3-corner opposite y");

      R.Set_Origin_Corner_X_Corner_Y (0.0, 0.0, 2.0, 0.0, 1.0, 1.0);
      Check_Near (R.Side_X_Length, 2.0, Tol, "skewed side X");
      Check_Near (R.Side_Y_Length, EF.Sqrt (2.0), Tol, "skewed side Y");
      Check_Near (R.Rotation, 0.0, Tol, "skewed rotation");
      Check_Near (R.Skew, -Pi / 4.0, Tol, "skewed skew");
      Check_Near (R.Corner_Y_X, 1.0, Tol, "skewed corner Y x");
      Check_Near (R.Corner_Y_Y, 1.0, Tol, "skewed corner Y y");
      Check_Near (R.Area, 2.0, Tol, "skewed area");

      Section ("affine rectangle degenerate constructors");
      R.Set_Origin_Corner_X_Corner_Y (0.0, 0.0, 10.0, 0.0, 5.0, 0.0);
      Check_Near (R.Side_X_Length, 10.0, Tol, "collinear side X");
      Check_Near (R.Side_Y_Length, 5.0, Tol, "collinear side Y");
      Check_Near (R.Skew, -Pi / 2.0, Tol, "collinear skew");
      Check_Near (R.Area, 0.0, 1.0E-12, "collinear area");
      Check_Near (R.Corner_Opposite_X, 15.0, 1.0E-12, "collinear opposite");
      Check (R.Contains_Point (7.0, 0.0), "collinear: on the segment");
      Check (R.Contains_Point (12.0, 0.0), "collinear: up to the far end");
      Check (R.Contains_Point (15.0, 0.0), "collinear: far end");
      Check (R.Contains_Point (0.0, 0.0), "collinear: origin");
      Check (not R.Contains_Point (15.001, 0.0), "collinear: past the end");
      Check (not R.Contains_Point (-0.001, 0.0), "collinear: before it");
      Check (not R.Contains_Point (1000.0, 0.0), "collinear: far along");
      Check (not R.Contains_Point (7.0, 0.001), "collinear: beside it");
      R.Set_Origin_Corner_X_Corner_Y (0.0, 0.0, 10.0, 0.0, -5.0, 0.0);
      Check_Near (R.Skew, Pi / 2.0, Tol, "anti-collinear skew");
      Check (R.Contains_Point (-5.0, 0.0), "anti-collinear: near end");
      Check (R.Contains_Point (10.0, 0.0), "anti-collinear: far end");
      Check (not R.Contains_Point (-5.001, 0.0), "anti-collinear: before");
      Check (not R.Contains_Point (10.001, 0.0), "anti-collinear: after");

      R.Set_Origin_Corner_X_Corner_Y (1.0, 1.0, 1.0, 1.0, 1.0, 5.0);
      Check_Near (R.Side_X_Length, 0.0, 0.0, "zero side X");
      Check_Near (R.Side_Y_Length, 4.0, Tol, "zero side X: side Y");
      Check_Near (R.Rotation, 0.0, Tol, "zero side X: rotation from Y");
      Check_Near (R.Skew, 0.0, 0.0, "zero side X: skew 0");
      Check (R.Contains_Point (1.0, 3.0), "zero side X: on the segment");
      Check (R.Contains_Point (1.0, 5.0), "zero side X: end");
      Check (not R.Contains_Point (1.001, 3.0), "zero side X: beside");
      Check (not R.Contains_Point (1.0, 5.001), "zero side X: past the end");
      Check (R.Area = 0.0, "zero side X: area");

      R.Set_Origin_Corner_X_Corner_Y (2.0, 3.0, 2.0, 3.0, 2.0, 3.0);
      Check (R.Side_X_Length = 0.0 and then R.Side_Y_Length = 0.0
             and then R.Rotation = 0.0 and then R.Skew = 0.0,
             "a point: zero lengths and angles");
      Check (R.Contains_Point (2.0, 3.0), "a point contains itself");
      Check (not R.Contains_Point (2.0, 3.001), "a point only");

      Section ("affine rectangle transform");
      R.Set_Center_Lengths_Rotation_Skew (5.0, -3.0, 40.0, 20.0, 0.7, 0.2);
      declare
         T : constant Ks_Transform_2D_Linear :=
           R.Get_Parent_From_Child_Transform;
         PX, PY : Real;
      begin
         T.Map_Point (0.0, 0.0, PX, PY);
         Check_Near (PX, R.Corner_Origin_X, Tol, "child (0, 0) -> origin x");
         Check_Near (PY, R.Corner_Origin_Y, Tol, "child (0, 0) -> origin y");
         T.Map_Point (40.0, 0.0, PX, PY);
         Check_Near (PX, R.Corner_X_X, Tol, "child (SX, 0) -> corner X x");
         Check_Near (PY, R.Corner_X_Y, Tol, "child (SX, 0) -> corner X y");
         T.Map_Point (0.0, 20.0, PX, PY);
         Check_Near (PX, R.Corner_Y_X, Tol, "child (0, SY) -> corner Y x");
         Check_Near (PY, R.Corner_Y_Y, Tol, "child (0, SY) -> corner Y y");
         T.Map_Point (40.0, 20.0, PX, PY);
         Check_Near (PX, R.Corner_Opposite_X, Tol, "child (SX, SY) x");
         Check_Near (PY, R.Corner_Opposite_Y, Tol, "child (SX, SY) y");
         Check_Near (T.Matrix_Determinant, EF.Cos (0.2), Tol,
                     "det = cos skew");
         Check_Near (T.Scaling_X, 1.0, Tol, "unit child x axis");
         Check_Near (T.Scaling_Y, 1.0, Tol, "unit child y axis");

         Section ("affine rectangle contains");
         declare
            function In_Child (U, V : Real) return Boolean is
               QX, QY : Real;
            begin
               T.Map_Point (U, V, QX, QY);
               return R.Contains_Point (QX, QY);
            end In_Child;
         begin
            Check (In_Child (20.0, 10.0), "centre");
            Check (In_Child (0.0, 10.0), "on side Y at the origin");
            Check (In_Child (40.0, 10.0), "on the opposite side");
            Check (In_Child (20.0, 0.0), "on side X");
            Check (In_Child (20.0, 20.0), "on the far side X");
            Check (In_Child (0.0, 0.0), "origin corner");
            Check (In_Child (40.0, 20.0), "opposite corner");
            Check (In_Child (39.999, 19.999), "just inside the corner");
            Check (not In_Child (-0.001, 10.0), "just outside u < 0");
            Check (not In_Child (40.001, 10.0), "just outside u > SX");
            Check (not In_Child (20.0, -0.001), "just outside v < 0");
            Check (not In_Child (20.0, 20.001), "just outside v > SY");
            Check (not In_Child (40.001, 20.001), "near the corner");
            Check (not In_Child (-0.001, -0.001), "near the origin");
            Check (not In_Child (100.0, 100.0), "far away");
         end;
      end;

      --  A strongly skewed parallelogram (cos K = 0.0707).
      R.Set_Center_Lengths_Rotation_Skew (0.0, 0.0, 10.0, 10.0, 0.0, 1.5);
      declare
         T : constant Ks_Transform_2D_Linear :=
           R.Get_Parent_From_Child_Transform;
         QX, QY : Real;
      begin
         T.Map_Point (5.0, 5.0, QX, QY);
         Check (R.Contains_Point (QX, QY), "skewed: centre");
         T.Map_Point (10.0, 10.0, QX, QY);
         Check (R.Contains_Point (QX, QY), "skewed: opposite corner");
         T.Map_Point (10.01, 10.0, QX, QY);
         Check (not R.Contains_Point (QX, QY), "skewed: beyond the corner");
         T.Map_Point (5.0, 10.01, QX, QY);
         Check (not R.Contains_Point (QX, QY), "skewed: beyond side");
      end;

      Section ("affine rectangle box and area");
      for K in 0 .. 11 loop
         declare
            Rot  : constant Real := -3.0 + 0.55 * Real (K);
            Skew : constant Real := -1.2 + 0.21 * Real (K);
         begin
            R.Set_Center_Lengths_Rotation_Skew
              (Real (K) - 4.0, 2.0 * Real (K), 30.0 + Real (K), 12.0,
               Rot, Skew);
            Check_Box_Against_Samples
              (R, Affine_Samples (R), 1.0E-12,
               "box" & Integer'Image (K));
            Check_Near (R.Area, (30.0 + Real (K)) * 12.0 * abs EF.Cos (Skew),
                        1.0E-10, "area" & Integer'Image (K));
            Check_All_On_Boundary
              (R, Affine_Samples (R), 1.0E-4,
               "samples on the boundary" & Integer'Image (K));
         end;
      end loop;

      Section ("affine rectangle map");
      R.Set_Center_Lengths_Rotation_Skew (5.0, -3.0, 40.0, 20.0, 0.7, 0.2);
      R.Set_Selected_Space_Name ("@\B");
      declare
         M : constant Ks_Shape'Class := R.Map (Transform_Of (MC_Rotation));
      begin
         Check (M'Tag = Ks_Rectangle_Affine'Tag, "rotation: affine");
         if M'Tag = Ks_Rectangle_Affine'Tag then
            declare
               MA : constant Ks_Rectangle_Affine :=
                 Ks_Rectangle_Affine (M);
               CX, CY : Real;
            begin
               Transform_Of (MC_Rotation).Map_Point (5.0, -3.0, CX, CY);
               Check_Near (MA.Center_X, CX, 1.0E-12, "rotated centre x");
               Check_Near (MA.Center_Y, CY, 1.0E-12, "rotated centre y");
               Check_Angle_Near (MA.Rotation, 0.7 + Pi / 6.0, 1.0E-12,
                                 "rotated rotation");
               Check_Angle_Near (MA.Skew, 0.2, 1.0E-12, "rotated skew");
               Check_Near (MA.Side_X_Length, 40.0, 1.0E-12, "side X");
               Check_Near (MA.Side_Y_Length, 20.0, 1.0E-12, "side Y");
            end;
         end if;
      end;
      declare
         M : constant Ks_Shape'Class :=
           R.Map (Transform_Of (MC_Uniform_Scaling));
      begin
         if M'Tag = Ks_Rectangle_Affine'Tag then
            declare
               MA : constant Ks_Rectangle_Affine :=
                 Ks_Rectangle_Affine (M);
            begin
               Check_Near (MA.Side_X_Length, 100.0, 1.0E-12, "scaled side X");
               Check_Near (MA.Side_Y_Length, 50.0, 1.0E-12, "scaled side Y");
               Check_Angle_Near (MA.Skew, 0.2, 1.0E-12, "scaled skew");
            end;
         else
            Fail ("scaling: not an affine rectangle");
         end if;
      end;
      for C in Map_Case loop
         Check_Map_Region
           (R, Affine_Samples (R), (R.Center_X, R.Center_Y),
            Transform_Of (C), "affine " & Map_Case'Image (C));
      end loop;
   end Test_Rectangle_Affine;

   procedure Test_Circle is
      C : Ks_Circle;
   begin
      Section ("circle setters");
      C.Set_Center_X (10.0);
      C.Set_Center_Y (-5.0);
      C.Set_Radius (5.0);
      Check (C.Center_X = 10.0 and then C.Center_Y = -5.0
             and then C.Radius = 5.0, "individual setters");
      C.Set_Center_Radius (1.0, 2.0, 3.0);
      Check (C.Center_X = 1.0 and then C.Center_Y = 2.0
             and then C.Radius = 3.0, "Set_Center_Radius");
      begin
         C.Set_Center_Radius (7.0, 7.0, -1.0);
      exception
         when Ks_Bad_Parameter_Exception => null;
      end;
      Check (C.Center_X = 1.0 and then C.Radius = 3.0,
             "failed Set_Center_Radius leaves it unchanged");

      Section ("circle contains");
      C.Set_Center_Radius (10.0, -5.0, 5.0);
      Check (C.Contains_Point (10.0, -5.0), "centre");
      Check (C.Contains_Point (13.0, -1.0), "on the circle (3-4-5)");
      Check (C.Contains_Point (5.0, -5.0), "leftmost point");
      Check (not C.Contains_Point (13.0001, -1.0), "just outside");
      Check (not C.Contains_Point (14.9, -0.1), "outside near the box corner");
      Check (C.Contains_Point (12.0, -3.0), "inside");
      C.Set_Radius (0.0);
      Check (C.Contains_Point (10.0, -5.0), "zero radius: the centre");
      Check (not C.Contains_Point (10.0, -4.999), "zero radius: only it");

      Section ("circle box and area");
      C.Set_Center_Radius (10.0, -5.0, 5.0);
      Check_Box (C, 5.0, -10.0, 15.0, 0.0, 0.0, "box");
      Check_Box_Against_Samples
        (C, Ellipse_Samples (10.0, -5.0, 5.0, 5.0, 0.0, 4000), 1.0E-12,
         "sampled box");
      Check_Near (C.Area, 25.0 * Pi, 1.0E-12, "area");
      Check_All_On_Boundary
        (C, Ellipse_Samples (10.0, -5.0, 5.0, 5.0, 0.3, 360), 1.0E-4,
         "samples on the boundary");

      Section ("circle map");
      C.Set_Center_Radius (10.0, -5.0, 20.0);
      C.Set_Selected_Space_Name ("@\C");
      for MC in Map_Case loop
         declare
            T : constant Ks_Transform_2D_Linear := Transform_Of (MC);
            M : constant Ks_Shape'Class := C.Map (T);
            CX, CY : Real;
         begin
            T.Map_Point (10.0, -5.0, CX, CY);
            if Is_Similar (MC) then
               Check (M'Tag = Ks_Circle'Tag,
                      Map_Case'Image (MC) & " gives a circle");
               if M'Tag = Ks_Circle'Tag then
                  Check_Near (Ks_Circle (M).Center_X, CX, 1.0E-12,
                              Map_Case'Image (MC) & " centre x");
                  Check_Near (Ks_Circle (M).Center_Y, CY, 1.0E-12,
                              Map_Case'Image (MC) & " centre y");
                  Check_Near (Ks_Circle (M).Radius,
                              20.0 * EF.Sqrt (abs T.Matrix_Determinant),
                              1.0E-12, Map_Case'Image (MC) & " radius");
               end if;
            else
               Check (M'Tag = Ks_Ellipse'Tag,
                      Map_Case'Image (MC) & " gives an ellipse");
            end if;
         end;
         Check_Map_Region
           (C, Ellipse_Samples (10.0, -5.0, 20.0, 20.0, 0.0, 360),
            (10.0, -5.0), Transform_Of (MC), "circle " & Map_Case'Image (MC));
      end loop;
      declare
         M : constant Ks_Shape'Class :=
           C.Map (Transform_Of (MC_Anisotropic));
      begin
         if M'Tag = Ks_Ellipse'Tag then
            declare
               E : constant Ks_Ellipse := Ks_Ellipse (M);
            begin
               Check_Near (E.Radius_X, 40.0, 1.0E-12, "aniso radius X");
               Check_Near (E.Radius_Y, 10.0, 1.0E-12, "aniso radius Y");
               Check_Angle_Near (E.Rotation, 0.0, 1.0E-12, "aniso rotation");
               Check_Near (E.Center_X, 23.0, 1.0E-12, "aniso centre x");
               Check_Near (E.Center_Y, 1.5, 1.0E-12, "aniso centre y");
               Check (E.Selected_Space_Name = "@\C", "space name kept");
            end;
         end if;
      end;
   end Test_Circle;

   procedure Test_Ellipse is
      E : Ks_Ellipse;
   begin
      Section ("ellipse setters");
      E.Set_Center_X (1.0);
      E.Set_Center_Y (2.0);
      E.Set_Radius_X (3.0);
      E.Set_Radius_Y (4.0);
      E.Set_Rotation (0.5);
      Check (E.Center_X = 1.0 and then E.Center_Y = 2.0
             and then E.Radius_X = 3.0 and then E.Radius_Y = 4.0
             and then E.Rotation = 0.5, "individual setters");
      E.Set_Center_XY_Radius_XY_Rotation (-1.0, -2.0, 6.0, 0.0, -2.5);
      Check (E.Center_X = -1.0 and then E.Center_Y = -2.0
             and then E.Radius_X = 6.0 and then E.Radius_Y = 0.0
             and then E.Rotation = -2.5, "Set_Center_XY_Radius_XY_Rotation");
      declare
         CX, CY, RX, RY, Rot : Real;

         procedure Set_Negative is
         begin
            E.Set_Center_XY_Radius_XY_Rotation (9.0, 9.0, 1.0, -1.0, 9.0);
         end Set_Negative;

         procedure Check_Negative is new Check_Raises_Exactly
           (Set_Negative, Ks_Bad_Parameter_Exception'Identity);
      begin
         E.Get_Center_XY_Radius_XY_Rotation (CX, CY, RX, RY, Rot);
         Check (CX = -1.0 and then CY = -2.0 and then RX = 6.0
                and then RY = 0.0 and then Rot = -2.5,
                "Get_Center_XY_Radius_XY_Rotation");
         Check_Negative ("Set_Center_XY_Radius_XY_Rotation, Radius_Y < 0");
         E.Get_Center_XY_Radius_XY_Rotation (CX, CY, RX, RY, Rot);
         Check (CX = -1.0 and then CY = -2.0 and then RX = 6.0
                and then RY = 0.0 and then Rot = -2.5,
                "a rejected Set_Center_XY_Radius_XY_Rotation changes "
                & "nothing");
      end;

      Section ("ellipse contains");
      E.Set_Center_XY_Radius_XY_Rotation (0.0, 0.0, 5.0, 3.0, 0.0);
      Check (E.Contains_Point (0.0, 0.0), "centre");
      Check (E.Contains_Point (5.0, 0.0), "end of the X axis");
      Check (E.Contains_Point (0.0, -3.0), "end of the Y axis");
      Check (E.Contains_Point (3.0, 2.4), "on the boundary (0.36 + 0.64)");
      Check (not E.Contains_Point (3.0, 2.401), "just outside");
      Check (not E.Contains_Point (5.0001, 0.0), "past the X axis");
      Check (not E.Contains_Point (4.0, 2.9), "outside, inside the box");
      E.Set_Rotation (Pi / 2.0);
      Check (E.Contains_Point (0.0, 5.0), "rotated: X axis is vertical");
      Check (not E.Contains_Point (5.0, 0.0), "rotated: not horizontal");
      Check (E.Contains_Point (-3.0, 0.0), "rotated: Y axis end");
      E.Set_Center_XY_Radius_XY_Rotation (7.0, -2.0, 50.0, 20.0, 0.4);
      declare
         C : constant Real := EF.Cos (0.4);
         S : constant Real := EF.Sin (0.4);
         Bad_In, Bad_Out : Natural := 0;
      begin
         for K in 0 .. 99 loop
            declare
               A : constant Real := 2.0 * Pi * Real (K) / 100.0;
               U : constant Real := 50.0 * EF.Cos (A);
               V : constant Real := 20.0 * EF.Sin (A);
            begin
               if not E.Contains_Point
                 (7.0 + U * C - V * S, -2.0 + U * S + V * C)
                 or else not E.Contains_Point
                   (7.0 + 0.9999 * (U * C - V * S),
                    -2.0 + 0.9999 * (U * S + V * C))
               then
                  Bad_In := Bad_In + 1;
               end if;
               if E.Contains_Point
                 (7.0 + 1.0001 * (U * C - V * S),
                  -2.0 + 1.0001 * (U * S + V * C))
               then
                  Bad_Out := Bad_Out + 1;
               end if;
            end;
         end loop;
         Check (Bad_In = 0, "rotated: boundary and scaled-in points inside");
         Check (Bad_Out = 0, "rotated: scaled-out points outside");
      end;
      E.Set_Center_XY_Radius_XY_Rotation (0.0, 0.0, 5.0, 0.0, 0.0);
      Check (E.Contains_Point (2.0, 0.0), "zero Radius_Y: on the segment");
      Check (E.Contains_Point (-5.0, 0.0), "zero Radius_Y: end");
      Check (not E.Contains_Point (2.0, 1.0E-6), "zero Radius_Y: beside");
      Check (not E.Contains_Point (5.0001, 0.0), "zero Radius_Y: past end");
      Check (E.Area = 0.0, "zero Radius_Y: area");
      E.Set_Radius_X (0.0);
      Check (E.Contains_Point (0.0, 0.0), "zero radii: the centre");
      Check (not E.Contains_Point (1.0E-6, 0.0), "zero radii: only it");

      Section ("ellipse box and area");
      E.Set_Center_XY_Radius_XY_Rotation (1.0, 2.0, 5.0, 3.0, 0.0);
      Check_Box (E, -4.0, -1.0, 6.0, 5.0, Tol, "unrotated box");
      E.Set_Rotation (Pi / 2.0);
      Check_Box (E, -2.0, -3.0, 4.0, 7.0, Tol, "quarter-turn box");
      E.Set_Rotation (Pi / 4.0);
      Check_Box (E, 1.0 - EF.Sqrt (17.0), 2.0 - EF.Sqrt (17.0),
                 1.0 + EF.Sqrt (17.0), 2.0 + EF.Sqrt (17.0), Tol,
                 "45 degree box (sqrt ((25 + 9) / 2))");
      for K in 0 .. 9 loop
         declare
            Rot : constant Real := -3.1 + 0.67 * Real (K);
         begin
            E.Set_Center_XY_Radius_XY_Rotation
              (Real (K), -Real (K), 40.0 - Real (K), 3.0 * Real (K), Rot);
            --  Uniform sampling of 20000 points: the extreme can fall
            --  between samples by at most R (1 - cos (Pi / 20000)).
            Check_Box_Against_Samples
              (E, Ellipse_Samples
                 (Real (K), -Real (K), 40.0 - Real (K), 3.0 * Real (K), Rot,
                  20000), 1.0E-6, "sampled box" & Integer'Image (K));
            Check_Near (E.Area, Pi * (40.0 - Real (K)) * 3.0 * Real (K),
                        1.0E-10, "area" & Integer'Image (K));
         end;
      end loop;

      Section ("ellipse map");
      E.Set_Center_XY_Radius_XY_Rotation (10.0, 20.0, 50.0, 25.0, 0.3);
      E.Set_Selected_Space_Name ("@\D");
      declare
         T : constant Ks_Transform_2D_Linear := Transform_Of (MC_Rotation);
         M : constant Ks_Shape'Class := E.Map (T);
         CX, CY : Real;
      begin
         T.Map_Point (10.0, 20.0, CX, CY);
         Check (M'Tag = Ks_Ellipse'Tag, "rotation gives an ellipse");
         Check_Near (Ks_Ellipse (M).Center_X, CX, 1.0E-12, "centre x");
         Check_Near (Ks_Ellipse (M).Center_Y, CY, 1.0E-12, "centre y");
         Check_Near (Ks_Ellipse (M).Radius_X, 50.0, 1.0E-12, "radius X");
         Check_Near (Ks_Ellipse (M).Radius_Y, 25.0, 1.0E-12, "radius Y");
         Check_Angle_Near (Ks_Ellipse (M).Rotation, 0.3 + Pi / 6.0,
                           1.0E-12, "rotation");
         Check (Ks_Ellipse (M).Selected_Space_Name = "@\D",
                "space name kept");
      end;
      declare
         M : constant Ks_Ellipse :=
           Ks_Ellipse (E.Map (Transform_Of (MC_Identity)));
      begin
         Check_Near (M.Radius_X, 50.0, 1.0E-12, "identity: radius X");
         Check_Near (M.Radius_Y, 25.0, 1.0E-12, "identity: radius Y");
         Check_Near (M.Rotation, 0.3, 1.0E-15, "identity keeps rotation");
      end;
      E.Set_Center_XY_Radius_XY_Rotation (0.0, 0.0, 50.0, 25.0, Pi / 2.0);
      declare
         M : constant Ks_Ellipse :=
           Ks_Ellipse (E.Map (Transform_Of (MC_Anisotropic)));
      begin
         --  The X axis (vertical, 50) is squeezed to 25 and the Y axis
         --  (horizontal, 25) stretched to 50; Radius_X stays vertical.
         Check_Near (M.Radius_X, 25.0, 1.0E-12, "aniso radius X");
         Check_Near (M.Radius_Y, 50.0, 1.0E-12, "aniso radius Y");
         Check_Angle_Near (M.Rotation, Pi / 2.0, 1.0E-12, "aniso rotation");
      end;
      E.Set_Center_XY_Radius_XY_Rotation (0.0, 0.0, 25.0, 50.0, 0.0);
      declare
         M : constant Ks_Ellipse :=
           Ks_Ellipse (E.Map (Transform_Of (MC_Translation)));
      begin
         --  Radius_X < Radius_Y: the parametrisation is kept.
         Check_Near (M.Radius_X, 25.0, 1.0E-12, "translation: radius X");
         Check_Near (M.Radius_Y, 50.0, 1.0E-12, "translation: radius Y");
         Check_Angle_Near (M.Rotation, 0.0, 1.0E-15, "translation: rotation");
      end;
      declare
         --  A singular map flattens the ellipse onto a line.
         M : constant Ks_Ellipse :=
           Ks_Ellipse (E.Map (Create (1.0, 2.0, 2.0, 4.0, 0.0, 0.0)));
      begin
         Check_Near (M.Radius_Y, 0.0, 1.0E-12, "singular: Radius_Y is 0");
         --  Rank one: the semi-major axis is the Frobenius norm of the
         --  mapped semi-axes (25, 50) and (100, 200).
         Check_Near (M.Radius_X, EF.Sqrt (53125.0), 1.0E-10,
                     "singular: Radius_X spans the image segment");
         Check_Near (M.Area, 0.0, 1.0E-9, "singular: zero area");
      end;
      E.Set_Center_XY_Radius_XY_Rotation (10.0, 20.0, 50.0, 25.0, 0.3);
      for MC in Map_Case loop
         Check_Map_Region
           (E, Ellipse_Samples (10.0, 20.0, 50.0, 25.0, 0.3, 360),
            (10.0, 20.0), Transform_Of (MC),
            "ellipse " & Map_Case'Image (MC));
         Check (E.Map (Transform_Of (MC))'Tag = Ks_Ellipse'Tag,
                "ellipse " & Map_Case'Image (MC) & " gives an ellipse");
      end loop;
      --  An ellipse with a zero radius maps to a segment-shaped ellipse.
      E.Set_Center_XY_Radius_XY_Rotation (0.0, 0.0, 10.0, 0.0, 0.5);
      declare
         T : constant Ks_Transform_2D_Linear := Transform_Of (MC_Shear);
         M : constant Ks_Ellipse := Ks_Ellipse (E.Map (T));
         EX, EY : Real;
      begin
         T.Map_Vector (10.0 * EF.Cos (0.5), 10.0 * EF.Sin (0.5), EX, EY);
         Check_Near (M.Radius_X, EF.Sqrt (EX * EX + EY * EY), 1.0E-12,
                     "flat ellipse: radius X is the mapped half length");
         Check_Near (M.Radius_Y, 0.0, 1.0E-12, "flat ellipse stays flat");
         Check_Angle_Near (M.Rotation, EF.Arctan (EY, EX), 1.0E-12,
                           "flat ellipse: direction");
      end;
   end Test_Ellipse;

   procedure Test_Polygon is
      P : Ks_Polygon;

      procedure Check_Vertices (Expected : Point_Array; Label : String) is
         Same : Boolean := P.Num_Vertices = Expected'Length;
      begin
         if Same then
            for I in Expected'Range loop
               Same := Same
                 and then P.Get_Vertex_X (I - Expected'First) = Expected (I).X
                 and then P.Get_Vertex_Y (I - Expected'First) = Expected (I).Y;
            end loop;
         end if;
         Check (Same, Label);
      end Check_Vertices;

      procedure Set_Polygon (Vertices : Point_Array) is
      begin
         P.Clear;
         for V of Vertices loop
            P.Add_Vertex (V.X, V.Y);
         end loop;
      end Set_Polygon;

   begin
      Section ("polygon vertices");
      P.Add_Vertex (0.0, 0.0);
      P.Add_Vertex (10.0, 0.0);
      Check_Vertices ([(0.0, 0.0), (10.0, 0.0)], "append by default");
      P.Add_Vertex (5.0, 5.0, Index => 0);
      Check_Vertices ([(5.0, 5.0), (0.0, 0.0), (10.0, 0.0)],
                      "insert before 0");
      P.Add_Vertex (7.0, 7.0, Index => 3);
      Check_Vertices ([(5.0, 5.0), (0.0, 0.0), (10.0, 0.0), (7.0, 7.0)],
                      "Index = Num_Vertices appends");
      P.Add_Vertex (1.0, 1.0, Index => 2);
      Check_Vertices ([(5.0, 5.0), (0.0, 0.0), (1.0, 1.0), (10.0, 0.0),
                       (7.0, 7.0)], "insert in the middle");
      P.Add_Vertex (2.0, 2.0, Index => -1);
      Check (P.Num_Vertices = 6 and then P.Get_Vertex_X (5) = 2.0,
             "Index = -1 appends");
      P.Set_Vertex (0, -5.0, -6.0);
      Check (P.Get_Vertex_X (0) = -5.0 and then P.Get_Vertex_Y (0) = -6.0,
             "Set_Vertex");
      P.Remove_Vertex (1);
      Check_Vertices ([(-5.0, -6.0), (1.0, 1.0), (10.0, 0.0), (7.0, 7.0),
                       (2.0, 2.0)], "Remove_Vertex shifts the rest down");
      P.Remove_Vertex (4);
      Check_Vertices ([(-5.0, -6.0), (1.0, 1.0), (10.0, 0.0), (7.0, 7.0)],
                      "remove the last vertex");
      P.Clear;
      Check (P.Num_Vertices = 0, "Clear");
      P.Add_Vertex (3.0, 4.0, Index => 0);
      Check_Vertices ([(3.0, 4.0)], "insert at 0 into an empty polygon");

      Section ("polygon contains: square and fewer vertices");
      P.Clear;
      Check (not P.Contains_Point (0.0, 0.0), "empty polygon: nothing");
      Check_Box (P, 0.0, 0.0, 0.0, 0.0, 0.0, "empty polygon box");
      Check (P.Area = 0.0, "empty polygon area");
      P.Add_Vertex (3.0, 4.0);
      Check (P.Contains_Point (3.0, 4.0), "one vertex: the vertex");
      Check (not P.Contains_Point (3.0, 4.001), "one vertex: only it");
      Check (P.Area = 0.0, "one vertex: area");
      Set_Polygon ([(0.0, 0.0), (10.0, 0.0)]);
      Check (P.Contains_Point (5.0, 0.0), "two vertices: on the segment");
      Check (P.Contains_Point (10.0, 0.0), "two vertices: end");
      Check (not P.Contains_Point (5.0, 0.001), "two vertices: beside");
      Check (not P.Contains_Point (10.001, 0.0), "two vertices: past end");
      Check (P.Area = 0.0, "two vertices: area");
      Set_Polygon ([(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)]);
      Check (P.Contains_Point (5.0, 5.0), "square: centre");
      Check (P.Contains_Point (10.0, 5.0), "square: right edge");
      Check (P.Contains_Point (5.0, 10.0), "square: bottom edge");
      Check (P.Contains_Point (10.0, 10.0), "square: vertex");
      Check (P.Contains_Point (0.0, 0.0), "square: first vertex");
      Check (not P.Contains_Point (10.000001, 5.0), "square: just right");
      Check (not P.Contains_Point (5.0, -0.000001), "square: just above");
      Check (not P.Contains_Point (15.0, 5.0), "square: outside");
      Check (not P.Contains_Point (-1.0, 0.0),
             "square: ray along the top edge");
      Check (not P.Contains_Point (-1.0, 10.0),
             "square: ray along the bottom edge");
      Check (not P.Contains_Point (-1.0, 5.0), "square: left of it");
      Check_Near (P.Area, 100.0, 0.0, "square area");
      Check_Box (P, 0.0, 0.0, 10.0, 10.0, 0.0, "square box");
      Set_Polygon ([(0.0, 10.0), (10.0, 10.0), (10.0, 0.0), (0.0, 0.0)]);
      Check_Near (P.Area, 100.0, 0.0, "clockwise square area");
      Check (P.Contains_Point (2.0, 3.0), "clockwise square: inside");
      Set_Polygon ([(0.0, 0.0), (4.0, 0.0), (0.0, 3.0)]);
      Check_Near (P.Area, 6.0, 0.0, "3-4-5 triangle area");
      Check (P.Contains_Point (2.0, 1.5), "triangle: on the hypotenuse");
      Check (not P.Contains_Point (2.01, 1.51), "triangle: beyond it");
      Set_Polygon ([(1.0E6, 1.0E6), (1.0E6 + 10.0, 1.0E6),
                    (1.0E6 + 10.0, 1.0E6 + 10.0), (1.0E6, 1.0E6 + 10.0)]);
      Check_Near (P.Area, 100.0, 1.0E-9, "far square area");
      Check (P.Contains_Point (1.0E6 + 10.0, 1.0E6 + 5.0),
             "far square: edge");
      Check (not P.Contains_Point (1.0E6 + 10.01, 1.0E6 + 5.0),
             "far square: outside");

      Section ("polygon contains: concave and self-intersecting");
      Set_Polygon ([(0.0, 0.0), (20.0, 0.0), (20.0, 10.0), (10.0, 10.0),
                    (10.0, 20.0), (0.0, 20.0)]);
      Check (P.Contains_Point (5.0, 15.0), "L: upper arm");
      Check (P.Contains_Point (15.0, 5.0), "L: lower arm");
      Check (not P.Contains_Point (15.0, 15.0), "L: the notch");
      Check (P.Contains_Point (10.0, 10.0), "L: reflex vertex");
      Check (P.Contains_Point (10.0, 15.0), "L: notch edge");
      Check (P.Contains_Point (15.0, 10.0), "L: other notch edge");
      Check (P.Contains_Point (5.0, 10.0),
             "L: ray through the reflex vertex");
      Check (not P.Contains_Point (25.0, 10.0), "L: right of a vertex");
      Check (not P.Contains_Point (-5.0, 10.0),
             "L: ray through two vertices");
      Check (not P.Contains_Point (15.0, 10.001), "L: inside the notch");
      Check_Near (P.Area, 300.0, 0.0, "L area");
      Check_Box (P, 0.0, 0.0, 20.0, 20.0, 0.0, "L box");
      Check_All_On_Boundary (P, Polygon_Samples (P), 1.0E-4,
                             "L samples on the boundary");

      --  A pentagram: the even-odd rule leaves the central pentagon out.
      P.Clear;
      for K in 0 .. 4 loop
         declare
            A : constant Real := Pi / 2.0 + Real (K) * 4.0 * Pi / 5.0;
         begin
            P.Add_Vertex (10.0 * EF.Cos (A), 10.0 * EF.Sin (A));
         end;
      end loop;
      Check (not P.Contains_Point (0.0, 0.0), "pentagram: centre is out");
      Check (P.Contains_Point (0.0, 8.0), "pentagram: top tip is in");
      Check (not P.Contains_Point (0.0, 10.01), "pentagram: beyond the tip");
      Check (P.Contains_Point (0.0, 10.0), "pentagram: tip vertex");
      Check_Near (P.Area, 2.5 * 100.0 * EF.Sin (4.0 * Pi / 5.0), 1.0E-12,
                  "pentagram net shoelace area");
      Check_Box_Against_Samples (P, Polygon_Samples (P), 1.0E-12,
                                 "pentagram box");

      Set_Polygon ([(0.0, 0.0), (10.0, 10.0), (10.0, 0.0), (0.0, 10.0)]);
      Check (P.Contains_Point (2.0, 5.0), "bow tie: left lobe");
      Check (P.Contains_Point (8.0, 5.0), "bow tie: right lobe");
      Check (not P.Contains_Point (5.0, 2.0), "bow tie: between lobes");
      Check (P.Contains_Point (5.0, 5.0), "bow tie: crossing point");
      Check_Near (P.Area, 0.0, 0.0, "bow tie net area");

      Section ("polygon map");
      Set_Polygon ([(0.0, 0.0), (20.0, 0.0), (20.0, 10.0), (10.0, 10.0),
                    (10.0, 20.0), (0.0, 20.0)]);
      P.Set_Selected_Space_Name ("@\E");
      declare
         T : constant Ks_Transform_2D_Linear := Transform_Of (MC_Shear);
         M : constant Ks_Shape'Class := P.Map (T);
         Same : Boolean := True;
      begin
         Check (M'Tag = Ks_Polygon'Tag, "shear gives a polygon");
         if M'Tag = Ks_Polygon'Tag then
            declare
               MP : constant Ks_Polygon := Ks_Polygon (M);
            begin
               Same := MP.Num_Vertices = 6;
               for I in 0 .. Natural'Min (MP.Num_Vertices, 6) - 1 loop
                  declare
                     Q : constant Point :=
                       Map_P (T, (P.Get_Vertex_X (I), P.Get_Vertex_Y (I)));
                  begin
                     Same := Same
                       and then abs (MP.Get_Vertex_X (I) - Q.X) <= Tol
                       and then abs (MP.Get_Vertex_Y (I) - Q.Y) <= Tol;
                  end;
               end loop;
               Check (Same, "vertices mapped one by one");
            end;
         end if;
      end;
      for C in Map_Case loop
         Check_Map_Region
           (P, Polygon_Samples (P), (5.0, 5.0), Transform_Of (C),
            "polygon " & Map_Case'Image (C));
      end loop;
   end Test_Polygon;

   function Default_Section return Ks_Circular_Annulus_Section is
      Result : Ks_Circular_Annulus_Section;
   begin
      return Result;
   end Default_Section;

   procedure Test_Annulus is
      S : Ks_Circular_Annulus_Section;

      function At_Polar (R, A : Real) return Point is
        (S.Center_X + R * EF.Cos (A), S.Center_Y + R * EF.Sin (A));

      function In_Polar (R, A : Real) return Boolean is
        (Contains (S, At_Polar (R, A)));

      type Config is record
         CX, CY, R, Scale, Start, Span : Real;
      end record;

      Configs : constant array (Positive range <>) of Config :=
        [(0.0, 0.0, 50.0, 1.5, 0.0, 2.0 * Pi),
         (10.0, -5.0, 40.0, 0.5, 0.3, 1.0),
         (0.0, 0.0, 30.0, 2.0, -0.5, 2.0),
         (5.0, 5.0, 20.0, 0.0, 2.5, 1.5),
         (0.0, 0.0, 25.0, 3.0, 1.0, -3.0),
         (1.0, 2.0, 10.0, 1.2, 3.0, 0.5),
         (0.0, 0.0, 10.0, 2.0, -3.0, -0.5),
         (0.0, 0.0, 10.0, 2.0, 7.0, 4.0),
         (3.0, 3.0, 10.0, 2.0, 1.0, -7.0),
         (0.0, 0.0, 10.0, 2.0, 0.7, 0.0),
         (-4.0, 6.0, 15.0, 0.0, 0.2, 0.5),
         (0.0, 0.0, 20.0, 1.0, 0.4, 1.2),
         (2.0, -1.0, 12.0, 1.5, -2.0, 6.2),
         (0.0, 0.0, 12.0, 0.25, Pi / 2.0, Pi)];
   begin
      Section ("annulus section setters");
      S.Set_Center_X (1.0);
      S.Set_Center_Y (2.0);
      S.Set_Radius (3.0);
      S.Set_Radial_Scale (0.5);
      S.Set_Angle_Start (-1.0);
      S.Set_Angle_Span (-2.0);
      Check (S.Center_X = 1.0 and then S.Center_Y = 2.0
             and then S.Radius = 3.0 and then S.Radial_Scale = 0.5
             and then S.Angle_Start = -1.0 and then S.Angle_Span = -2.0,
             "individual setters");
      S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (-1.0, -2.0, 30.0, 0.5, 1.5, 2.0);
      Check (S.Center_X = -1.0 and then S.Center_Y = -2.0
             and then S.Radius = 30.0 and then S.Angle_Start = 0.5
             and then S.Angle_Span = 1.5 and then S.Radial_Scale = 2.0,
             "combined setter (argument order)");
      S.Set_Radial_Scale (0.0);
      S.Set_Radius (0.0);
      Check (S.Radius = 0.0 and then S.Radial_Scale = 0.0, "zeros allowed");

      Section ("annulus section contains: full annulus");
      S := Default_Section;
      Check (S.Contains_Point (60.0, 0.0), "default: between the radii");
      Check (S.Contains_Point (50.0, 0.0), "default: inner circle");
      Check (S.Contains_Point (0.0, -75.0), "default: outer circle");
      Check (S.Contains_Point (-60.0, 0.0), "default: angle Pi");
      Check (S.Contains_Point (-60.0, -1.0E-9), "default: just below Pi");
      Check (not S.Contains_Point (40.0, 0.0), "default: inside the hole");
      Check (not S.Contains_Point (49.999, 0.0), "default: just inside it");
      Check (not S.Contains_Point (75.001, 0.0), "default: just outside");
      Check (not S.Contains_Point (0.0, 0.0), "default: the centre");
      S.Set_Radial_Scale (0.5);
      Check (S.Contains_Point (30.0, 0.0), "scale < 1: between 25 and 50");
      Check (S.Contains_Point (25.0, 0.0), "scale < 1: inner radius 25");
      Check (not S.Contains_Point (20.0, 0.0), "scale < 1: hole");
      Check (not S.Contains_Point (55.0, 0.0), "scale < 1: outside");
      S.Set_Angle_Span (7.0);
      Check (S.Contains_Point (0.0, -30.0), "span > 2 Pi: full");
      S.Set_Angle_Span (-2.0 * Pi);
      Check (S.Contains_Point (0.0, -30.0), "span = -2 Pi: full");
      Check (S.Contains_Point (-30.0, 0.0), "span = -2 Pi: angle Pi");

      Section ("annulus section contains: sections");
      S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (3.0, -4.0, 10.0, Pi / 4.0, Pi / 2.0, 2.0);
      Check (In_Polar (15.0, Pi / 2.0), "middle of the section");
      Check (not In_Polar (15.0, 0.0), "outside the angle range");
      Check (In_Polar (15.0, Pi / 4.0), "on the start edge");
      Check (In_Polar (15.0, 3.0 * Pi / 4.0), "on the end edge");
      Check (not In_Polar (15.0, Pi / 4.0 - 1.0E-6), "just before start");
      Check (not In_Polar (15.0, 3.0 * Pi / 4.0 + 1.0E-6), "just after end");
      Check (In_Polar (20.0, 3.0 * Pi / 4.0), "outer corner");
      Check (In_Polar (10.0, Pi / 4.0), "inner corner");
      Check (not In_Polar (20.001, 3.0 * Pi / 4.0 + 1.0E-4),
             "near the outer corner");
      Check (not In_Polar (9.999, Pi / 2.0), "inside the inner radius");
      Check (not In_Polar (15.0, Pi / 2.0 + Pi), "opposite direction");
      S.Set_Angle_Span (-Pi / 2.0);
      Check (In_Polar (15.0, 0.0), "negative span: towards -Pi/4");
      Check (In_Polar (15.0, -Pi / 4.0), "negative span: end edge");
      Check (not In_Polar (15.0, Pi / 2.0), "negative span: other side");
      Check (not In_Polar (15.0, -Pi / 4.0 - 1.0E-6),
             "negative span: past end");
      S.Set_Angle_Start (3.0 * Pi / 4.0);
      S.Set_Angle_Span (Pi / 2.0);
      Check (In_Polar (15.0, Pi), "across +/-Pi: at Pi");
      Check (In_Polar (15.0, -Pi + 1.0E-3), "across +/-Pi: just past Pi");
      Check (In_Polar (15.0, -3.0 * Pi / 4.0), "across +/-Pi: end");
      Check (not In_Polar (15.0, -Pi / 2.0), "across +/-Pi: outside");
      Check (not In_Polar (15.0, 0.0), "across +/-Pi: opposite");
      S.Set_Angle_Start (0.5 + 4.0 * Pi);
      S.Set_Angle_Span (0.5);
      Check (In_Polar (15.0, 0.75), "start beyond 2 Pi");
      Check (not In_Polar (15.0, 0.25), "start beyond 2 Pi: before");
      S.Set_Angle_Start (0.5);
      S.Set_Angle_Span (0.0);
      Check (In_Polar (12.0, 0.5), "zero span: on the radial segment");
      Check (not In_Polar (12.0, 0.501), "zero span: beside it");
      S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (0.0, 0.0, 10.0, 0.0, Pi / 2.0, 0.0);
      Check (S.Contains_Point (0.0, 0.0), "inner radius 0: centre is in");
      Check (S.Contains_Point (5.0, 5.0), "inner radius 0: inside");
      Check (S.Contains_Point (5.0, 0.0), "inner radius 0: on an edge");
      Check (S.Contains_Point (1.0E-6, 1.0E-6), "inner radius 0: near apex");
      Check (not S.Contains_Point (-1.0, 0.0), "inner radius 0: behind");
      Check (not S.Contains_Point (5.0, -1.0E-3), "inner radius 0: below");
      S.Set_Radial_Scale (1.0);
      Check (S.Contains_Point (10.0 * H2, 10.0 * H2), "scale 1: on the arc");
      Check (not S.Contains_Point (9.9 * H2, 9.9 * H2), "scale 1: inside");
      Check (not S.Contains_Point (0.0, 0.0), "scale 1: centre");

      Section ("annulus section box");
      S := Default_Section;
      Check_Box (S, -75.0, -75.0, 75.0, 75.0, 0.0, "default box");
      S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (0.0, 0.0, 10.0, 0.0, Pi / 2.0, 2.0);
      Check_Box (S, 0.0, 0.0, 20.0, 20.0, 1.0E-14, "quarter box");
      S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (1.0, 1.0, 10.0, 0.2, 0.5, 0.0);
      Check_Box (S, 1.0, 1.0, 1.0 + 10.0 * EF.Cos (0.2),
                 1.0 + 10.0 * EF.Sin (0.7), 1.0E-14,
                 "inner radius 0: the centre is a corner of the box");
      for I in Configs'Range loop
         declare
            C : constant Config := Configs (I);
         begin
            S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
              (C.CX, C.CY, C.R, C.Start, C.Span, C.Scale);
            --  Sampling error at most R (1 - cos (Pi / 100000)) < 1E-8.
            Check_Box_Against_Sample_Box
              (S, Annulus_Sample_Box (S, 100000), 1.0E-7,
               "config" & Integer'Image (I) & " box");
            Check_All_On_Boundary
              (S, Annulus_Samples (S, 300), 1.0E-4,
               "config" & Integer'Image (I) & " samples on the boundary");
         end;
      end loop;

      Section ("annulus section area");
      S := Default_Section;
      Check_Near (S.Area, 3125.0 * Pi, 1.0E-9, "default area");
      S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (0.0, 0.0, 10.0, Pi / 4.0, Pi / 2.0, 2.0);
      Check_Near (S.Area, 75.0 * Pi, 1.0E-10, "quarter area");
      S.Set_Angle_Span (-Pi / 2.0);
      Check_Near (S.Area, 75.0 * Pi, 1.0E-10, "negative span area");
      S.Set_Radial_Scale (0.5);
      --  Radii 5 and 10 over a quarter turn.
      Check_Near (S.Area, 0.25 * Pi * 75.0, 1.0E-10, "scale < 1 area");
      S.Set_Angle_Span (10.0);
      Check_Near (S.Area, Pi * 75.0, 1.0E-10, "span > 2 Pi area is full");
      S.Set_Radial_Scale (1.0);
      Check (S.Area = 0.0, "scale 1 area");
      S.Set_Radial_Scale (0.0);
      S.Set_Angle_Span (1.0);
      Check_Near (S.Area, 50.0, 1.0E-12, "sector area");

      Section ("annulus section map");
      S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (3.0, -4.0, 10.0, 0.4, 2.0, 1.8);
      S.Set_Selected_Space_Name ("@\F");
      declare
         T : constant Ks_Transform_2D_Linear := Transform_Of (MC_Similarity);
         M : constant Ks_Circular_Annulus_Section :=
           Ks_Circular_Annulus_Section (S.Map (T));
         CX, CY : Real;
      begin
         T.Map_Point (3.0, -4.0, CX, CY);
         Check_Near (M.Center_X, CX, 1.0E-12, "similarity centre x");
         Check_Near (M.Center_Y, CY, 1.0E-12, "similarity centre y");
         Check_Near (M.Radius, 7.5, 1.0E-12, "similarity radius");
         Check (M.Radial_Scale = 1.8, "radial scale kept");
         Check_Angle_Near (M.Angle_Start, 0.4 - 2.0, 1.0E-12,
                           "similarity start");
         Check (M.Angle_Span = 2.0, "similarity span kept");
         Check (M.Selected_Space_Name = "@\F", "space name kept");
      end;
      declare
         M : constant Ks_Circular_Annulus_Section :=
           Ks_Circular_Annulus_Section
             (S.Map (Transform_Of (MC_Identity)));
      begin
         Check (M.Angle_Start = 0.4 and then M.Angle_Span = 2.0
                and then M.Radius = 10.0, "identity keeps the angles");
      end;
      declare
         M : constant Ks_Circular_Annulus_Section :=
           Ks_Circular_Annulus_Section
             (S.Map (Transform_Of (MC_Reflection)));
      begin
         Check_Angle_Near (M.Angle_Start, Pi - 0.4, 1.0E-12,
                           "mirror: start direction mirrored");
         Check (M.Angle_Span = -2.0, "mirror: span negated");
         Check_Near (M.Center_X, 97.0, 1.0E-12, "mirror: centre x");
      end;
      declare
         M : constant Ks_Circular_Annulus_Section :=
           Ks_Circular_Annulus_Section
             (S.Map (Create (1.0, 0.0, 0.0, -1.0, 0.0, 0.0)));
      begin
         Check (M.Angle_Start = -0.4 and then M.Angle_Span = -2.0,
                "mirror in the x axis negates both angles exactly");
      end;
      for C in Map_Case loop
         if Is_Similar (C) then
            Check_Map_Region
              (S, Annulus_Samples (S, 300), At_Polar (14.0, 1.4),
               Transform_Of (C), "annulus " & Map_Case'Image (C));
         end if;
      end loop;
      S.Set_Angle_Span (-2.5);
      Check_Map_Region
        (S, Annulus_Samples (S, 300), At_Polar (14.0, -0.85),
         Transform_Of (MC_Reflection_Rotated),
         "annulus with negative span, rotated mirror");
   end Test_Annulus;

   procedure Test_Line is
      L : Ks_Line;
   begin
      Section ("line");
      L.Set_X (1.0);
      L.Set_Y (2.0);
      L.Set_Rotation (0.5);
      Check (L.X = 1.0 and then L.Y = 2.0 and then L.Rotation = 0.5,
             "individual setters");
      L.Set_XY_Rotation (-1.0, -2.0, -0.5);
      Check (L.X = -1.0 and then L.Y = -2.0 and then L.Rotation = -0.5,
             "Set_XY_Rotation");
      L.Set_From_Start_XY_End_XY (1.0, 1.0, 1.0, 5.0);
      Check (L.X = 1.0 and then L.Y = 1.0, "two points: through start");
      Check_Near (L.Rotation, Pi / 2.0, Tol, "two points: downwards");
      L.Set_From_Start_XY_End_XY (1.0, 1.0, -3.0, 1.0);
      Check_Near (L.Rotation, Pi, Tol, "two points: towards -x is +Pi");
      L.Set_From_Start_XY_End_XY (0.0, 0.0, 3.0, -3.0);
      Check_Near (L.Rotation, -Pi / 4.0, Tol, "two points: up-right");

      L.Set_XY_Rotation (1.0, 2.0, Pi / 4.0);
      L.Set_Selected_Space_Name ("@\G");
      declare
         T : constant Ks_Transform_2D_Linear := Transform_Of (MC_Rotation);
         M : constant Ks_Line := Ks_Line (L.Map (T));
         PX, PY : Real;
      begin
         T.Map_Point (1.0, 2.0, PX, PY);
         Check_Near (M.X, PX, Tol, "mapped point x");
         Check_Near (M.Y, PY, Tol, "mapped point y");
         Check_Angle_Near (M.Rotation, Pi / 4.0 + Pi / 6.0, Tol,
                           "mapped rotation");
         Check (M.Selected_Space_Name = "@\G", "space name kept");
      end;
      declare
         M : constant Ks_Line :=
           Ks_Line (L.Map (Transform_Of (MC_Anisotropic)));
      begin
         Check_Near (M.Rotation, EF.Arctan (0.5, 2.0), Tol,
                     "anisotropic rotation");
         Check_Near (M.X, 5.0, Tol, "anisotropic x");
         Check_Near (M.Y, 5.0, Tol, "anisotropic y");
      end;
      declare
         M : constant Ks_Line :=
           Ks_Line (L.Map (Transform_Of (MC_Reflection)));
      begin
         Check_Near (M.Rotation, 3.0 * Pi / 4.0, Tol, "mirrored rotation");
      end;
   end Test_Line;

   procedure Test_Segment is
      S : Ks_Line_Segment;
   begin
      Section ("line segment");
      Check (S.Length = 100.0 and then S.Rotation = 0.0
             and then S.Midpoint_X = 50.0 and then S.Midpoint_Y = 0.0,
             "default length, rotation, midpoint");
      S.Set_Start_X (1.0);
      S.Set_Start_Y (1.0);
      S.Set_End_X (4.0);
      S.Set_End_Y (5.0);
      Check (S.Start_X = 1.0 and then S.Start_Y = 1.0
             and then S.End_X = 4.0 and then S.End_Y = 5.0,
             "individual setters");
      Check_Near (S.Length, 5.0, Tol, "length");
      Check_Near (S.Rotation, EF.Arctan (4.0, 3.0), Tol, "rotation");
      Check (S.Midpoint_X = 2.5 and then S.Midpoint_Y = 3.0, "midpoint");
      S.Set_Start_End (2.0, 2.0, 2.0, 2.0);
      Check (S.Length = 0.0 and then S.Rotation = 0.0,
             "zero length: rotation 0");
      S.Set_Start_End (0.0, 0.0, -1.0, 0.0);
      Check_Near (S.Rotation, Pi, 0.0, "towards -x: +Pi");
      S.Set_Start_Length_Rotation (1.0, 2.0, 10.0, Pi / 2.0);
      Check (S.Start_X = 1.0 and then S.Start_Y = 2.0, "start kept");
      Check_Near (S.End_X, 1.0, Tol, "end x from length and rotation");
      Check_Near (S.End_Y, 12.0, Tol, "end y from length and rotation");
      Check_Near (S.Length, 10.0, Tol, "length read back");
      Check_Near (S.Rotation, Pi / 2.0, Tol, "rotation read back");
      S.Set_Start_Length_Rotation (1.0, 2.0, 0.0, 1.0);
      Check (S.End_X = 1.0 and then S.End_Y = 2.0, "zero length allowed");

      S.Set_Start_End (1.0, 2.0, 5.0, -1.0);
      S.Set_Selected_Space_Name ("@\H");
      for C in Map_Case loop
         declare
            T : constant Ks_Transform_2D_Linear := Transform_Of (C);
            M : constant Ks_Shape'Class := S.Map (T);
            A, B : Point;
         begin
            Check (M'Tag = Ks_Line_Segment'Tag,
                   Map_Case'Image (C) & " gives a segment");
            if M'Tag = Ks_Line_Segment'Tag then
               A := Map_P (T, (1.0, 2.0));
               B := Map_P (T, (5.0, -1.0));
               Check (abs (Ks_Line_Segment (M).Start_X - A.X) <= Tol
                      and then abs (Ks_Line_Segment (M).Start_Y - A.Y) <= Tol
                      and then abs (Ks_Line_Segment (M).End_X - B.X) <= Tol
                      and then abs (Ks_Line_Segment (M).End_Y - B.Y) <= Tol,
                      Map_Case'Image (C) & " end points mapped");
               Check (M.Selected_Space_Name = "@\H",
                      Map_Case'Image (C) & " space name kept");
            end if;
         end;
      end loop;
   end Test_Segment;

   procedure Test_Point_Marker is
      P : Ks_Point_Marker;
   begin
      Section ("point marker");
      P.Set_X (3.0);
      P.Set_Y (-4.0);
      P.Set_Rotation (0.25);
      Check (P.X = 3.0 and then P.Y = -4.0 and then P.Rotation = 0.25,
             "setters");
      P.Set_Selected_Space_Name ("@\I");
      declare
         M : constant Ks_Point_Marker :=
           Ks_Point_Marker (P.Map (Transform_Of (MC_Similarity)));
         PX, PY : Real;
      begin
         Transform_Of (MC_Similarity).Map_Point (3.0, -4.0, PX, PY);
         Check_Near (M.X, PX, Tol, "mapped x");
         Check_Near (M.Y, PY, Tol, "mapped y");
         Check_Angle_Near (M.Rotation, 0.25 - 2.0, Tol, "mapped rotation");
         Check (M.Selected_Space_Name = "@\I", "space name kept");
      end;
      declare
         M : constant Ks_Point_Marker :=
           Ks_Point_Marker (P.Map (Transform_Of (MC_Shear)));
      begin
         Check_Near (M.Rotation,
                     Transform_Of (MC_Shear).Map_Angle (0.25), 0.0,
                     "shear: rotation through Map_Angle");
      end;
   end Test_Point_Marker;

   procedure Test_Arc is
      A : Ks_Circular_Arc;
   begin
      Section ("circular arc");
      Check_Near (A.Start_X, 50.0, Tol, "default start x");
      Check_Near (A.Start_Y, 0.0, Tol, "default start y");
      Check_Near (A.End_X, -50.0, Tol, "default end x");
      Check_Near (A.End_Y, 0.0, 1.0E-10, "default end y");
      A.Set_Center_X (1.0);
      A.Set_Center_Y (2.0);
      A.Set_Radius (10.0);
      A.Set_Angle_Start (Pi / 2.0);
      A.Set_Angle_Span (-Pi / 2.0);
      Check (A.Center_X = 1.0 and then A.Center_Y = 2.0
             and then A.Radius = 10.0 and then A.Angle_Start = Pi / 2.0
             and then A.Angle_Span = -Pi / 2.0, "individual setters");
      Check_Near (A.Start_X, 1.0, Tol, "start x");
      Check_Near (A.Start_Y, 12.0, Tol, "start y");
      Check_Near (A.End_X, 11.0, Tol, "end x (negative span)");
      Check_Near (A.End_Y, 2.0, Tol, "end y (negative span)");
      A.Set_Center_Radius_Angle_Start_Angle_Span (-1.0, -1.0, 4.0, Pi, 0.5);
      Check (A.Center_X = -1.0 and then A.Center_Y = -1.0
             and then A.Radius = 4.0 and then A.Angle_Start = Pi
             and then A.Angle_Span = 0.5, "combined setter");
      A.Set_Radius (0.0);
      Check (A.Radius = 0.0, "zero radius allowed");

      A.Set_Center_Radius_Angle_Start_Angle_Span (1.0, 1.0, 10.0, 0.5, 1.0);
      A.Set_Selected_Space_Name ("@\J");
      for C in Map_Case loop
         if Is_Similar (C) then
            declare
               T : constant Ks_Transform_2D_Linear := Transform_Of (C);
               M : constant Ks_Circular_Arc := Ks_Circular_Arc (A.Map (T));
               S, E, Mid : Point;
               Label : constant String := Map_Case'Image (C);
            begin
               S := Map_P (T, (A.Start_X, A.Start_Y));
               E := Map_P (T, (A.End_X, A.End_Y));
               Mid := Map_P (T, (1.0 + 10.0 * EF.Cos (1.0),
                                 1.0 + 10.0 * EF.Sin (1.0)));
               Check_Near (M.Start_X, S.X, 1.0E-12, Label & " start x");
               Check_Near (M.Start_Y, S.Y, 1.0E-12, Label & " start y");
               Check_Near (M.End_X, E.X, 1.0E-12, Label & " end x");
               Check_Near (M.End_Y, E.Y, 1.0E-12, Label & " end y");
               Check_Near
                 (M.Center_X + M.Radius
                    * EF.Cos (M.Angle_Start + 0.5 * M.Angle_Span),
                  Mid.X, 1.0E-12, Label & " midpoint x");
               Check_Near
                 (M.Center_Y + M.Radius
                    * EF.Sin (M.Angle_Start + 0.5 * M.Angle_Span),
                  Mid.Y, 1.0E-12, Label & " midpoint y");
               Check_Near (M.Radius, 10.0 * EF.Sqrt (abs T.Matrix_Determinant),
                           1.0E-12, Label & " radius");
               Check (M.Angle_Span
                        = (if C in Similar_Case then 1.0 else -1.0),
                      Label & " span (negated by a reflection)");
               Check (M.Selected_Space_Name = "@\J",
                      Label & " space name kept");
            end;
         end if;
      end loop;
      declare
         M : constant Ks_Circular_Arc :=
           Ks_Circular_Arc (A.Map (Transform_Of (MC_Uniform_Scaling)));
      begin
         Check (M.Angle_Start = 0.5, "scaling keeps the start exactly");
         Check_Near (M.Radius, 25.0, 1.0E-12, "scaling radius");
         Check_Near (M.Center_X, 3.5, 1.0E-12, "scaling centre x");
         Check_Near (M.Center_Y, 4.5, 1.0E-12, "scaling centre y");
      end;
   end Test_Arc;

   procedure Test_Extreme_Scales is
      --  Similarities whose scale is so large or small that its square,
      --  the determinant, overflows or underflows although the mapped
      --  radius is representable.

      type Scale_Array is array (Positive range <>) of Real;
      Scales : constant Scale_Array := [1.0E140, 1.0E-160, 1.0E-170];

      Circle  : Ks_Circle;
      Arc     : Ks_Circular_Arc;
      Annulus : Ks_Circular_Annulus_Section;
   begin
      Section ("map: similarities of extreme scale");
      Circle.Set_Center_Radius (1.0, 1.0, 10.0);
      Arc.Set_Center_Radius_Angle_Start_Angle_Span (1.0, 1.0, 10.0, 0.5, 1.0);
      Annulus.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (1.0, 1.0, 10.0, 0.4, 2.0, 1.8);
      for S of Scales loop
         for Reflect in Boolean loop
            declare
               T : constant Ks_Transform_2D_Linear :=
                 (if Reflect
                  then Create (S * EF.Cos (0.3), S * EF.Sin (0.3),
                               S * EF.Sin (0.3), -(S * EF.Cos (0.3)),
                               0.0, 0.0)
                  else Create_Similarity (S, 0.3, 0.0, 0.0));
               Expected : constant Real := 10.0 * S;
               Label    : constant String :=
                 "scale" & Real'Image (S)
                 & (if Reflect then ", reflecting" else "");
               CX, CY   : Real;
            begin
               T.Map_Point (1.0, 1.0, CX, CY);
               begin
                  declare
                     M : constant Ks_Shape'Class := Circle.Map (T);
                  begin
                     Check (M'Tag = Ks_Circle'Tag, Label & ": a circle");
                     if M'Tag = Ks_Circle'Tag then
                        Check_Near (Ks_Circle (M).Radius, Expected,
                                    1.0E-12 * Expected,
                                    Label & ": circle radius");
                        Check_Near (Ks_Circle (M).Center_X, CX,
                                    1.0E-12 * abs CX,
                                    Label & ": circle centre x");
                     end if;
                  end;
               exception
                  when E : others =>
                     Fail (Label & ": circle Map: "
                           & Ada.Exceptions.Exception_Information (E));
               end;
               begin
                  declare
                     M : constant Ks_Circular_Arc :=
                       Ks_Circular_Arc (Arc.Map (T));
                  begin
                     Check_Near (M.Radius, Expected, 1.0E-12 * Expected,
                                 Label & ": arc radius");
                     Check (M.Angle_Span = (if Reflect then -1.0 else 1.0),
                            Label & ": arc span");
                  end;
               exception
                  when E : others =>
                     Fail (Label & ": arc Map: "
                           & Ada.Exceptions.Exception_Information (E));
               end;
               begin
                  declare
                     M : constant Ks_Circular_Annulus_Section :=
                       Ks_Circular_Annulus_Section (Annulus.Map (T));
                  begin
                     Check_Near (M.Radius, Expected, 1.0E-12 * Expected,
                                 Label & ": annulus radius");
                     Check (M.Radial_Scale = 1.8,
                            Label & ": annulus radial scale kept");
                  end;
               exception
                  when E : others =>
                     Fail (Label & ": annulus Map: "
                           & Ada.Exceptions.Exception_Information (E));
               end;
            end;
         end loop;
      end loop;
   end Test_Extreme_Scales;

   procedure Test_Slack is
      Model_Eps : constant Real := Real'Model_Epsilon;
   begin
      Section ("contains: the slack is relative to the region's size");
      --  The documented formula, 1E-9 * L + 64 * Model_Epsilon * (P + L).
      declare
         R : Ks_Rectangle;
      begin
         R.Set_XY_Width_Height (-3.0, 4.0, 100.0, 50.0);
         Check_Near (R.Boundary_Slack,
                     1.0E-9 * 150.0 + 64.0 * Model_Eps * (7.0 + 150.0),
                     1.0E-22, "rectangle: Boundary_Slack is the slack");
         Check (R.Contains_Point (97.0 + 1.4E-7, 30.0),
                "rectangle: inside the slack");
         Check (not R.Contains_Point (97.0 + 1.6E-7, 30.0),
                "rectangle: outside the slack");
      end;

      --  Far from the origin the slack no longer grows with 1E-9 times
      --  the coordinates (a whole unit at 1E9), only with their rounding.
      declare
         C : Ks_Circle;
      begin
         C.Set_Center_Radius (30.0, 1.0E9 + 20.0, 12.0);
         Check (C.Contains_Point (42.0, 1.0E9 + 20.0),
                "circle at 1E9: on the circle");
         Check (C.Contains_Point (30.0, 1.0E9 + 32.0),
                "circle at 1E9: lowest point");
         Check (not C.Contains_Point (42.5, 1.0E9 + 20.0),
                "circle at 1E9: half a unit outside");
         Check (not C.Contains_Point (30.0, 1.0E9 + 32.001),
                "circle at 1E9: 0.001 below the lowest point");
         Check (C.Boundary_Slack < 2.0E-5,
                "circle at 1E9: slack" & Real'Image (C.Boundary_Slack));
      end;
      declare
         E : Ks_Ellipse;
      begin
         E.Set_Center_XY_Radius_XY_Rotation (1.0E9, 0.0, 12.0, 6.0, 0.0);
         Check (E.Contains_Point (1.0E9 + 12.0, 0.0), "ellipse at 1E9: vertex");
         Check (not E.Contains_Point (1.0E9 + 12.5, 0.0),
                "ellipse at 1E9: half a unit outside");
      end;
      declare
         A : Ks_Rectangle_Affine;
      begin
         A.Set_Origin_Lengths_Rotation_Skew (1.0E9, 1.0E9, 12.0, 8.0, 0.0, 0.0);
         Check (A.Contains_Point (1.0E9 + 12.0, 1.0E9 + 4.0),
                "affine rectangle at 1E9: on a side");
         Check (not A.Contains_Point (1.0E9 + 12.5, 1.0E9 + 4.0),
                "affine rectangle at 1E9: half a unit outside");
      end;
      declare
         P : Ks_Polygon;
      begin
         P.Add_Vertex (1.0E9, 1.0E9);
         P.Add_Vertex (1.0E9 + 10.0, 1.0E9);
         P.Add_Vertex (1.0E9 + 10.0, 1.0E9 + 10.0);
         P.Add_Vertex (1.0E9, 1.0E9 + 10.0);
         Check (P.Contains_Point (1.0E9 + 10.0, 1.0E9 + 5.0),
                "polygon at 1E9: on an edge");
         Check (not P.Contains_Point (1.0E9 + 10.5, 1.0E9 + 5.0),
                "polygon at 1E9: half a unit outside");
      end;
      declare
         S : Ks_Circular_Annulus_Section;
      begin
         S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
           (1.0E9, 0.0, 10.0, 0.0, 2.0 * Pi, 1.5);
         Check (S.Contains_Point (1.0E9 + 15.0, 0.0),
                "annulus at 1E9: outer circle");
         Check (not S.Contains_Point (1.0E9 + 15.5, 0.0),
                "annulus at 1E9: half a unit outside");
         Check (not S.Contains_Point (1.0E9 + 9.5, 0.0),
                "annulus at 1E9: half a unit inside the hole");
      end;

      --  The slack does not depend on the unit: a circle in metres with
      --  nanometre-sized features is widened in proportion to its size,
      --  not by an absolute 1E-9.
      declare
         C : Ks_Circle;
      begin
         C.Set_Center_Radius (30.0E-9, 20.0E-9, 12.0E-9);
         Check (C.Contains_Point (42.0E-9, 20.0E-9),
                "nanometre circle: on the circle");
         Check (not C.Contains_Point (42.5E-9, 20.0E-9),
                "nanometre circle: half a nanometre outside");
      end;
      declare
         R : Ks_Rectangle;
      begin
         R.Set_XY_Width_Height (0.0, 0.0, 1.0E-6, 1.0E-6);
         Check (R.Contains_Point (1.0E-6, 5.0E-7), "tiny rectangle: edge");
         Check (not R.Contains_Point (1.0E-6 + 1.0E-12, 5.0E-7),
                "tiny rectangle: 1E-12 outside");
      end;

      --  A point region at the origin has no slack at all, and the
      --  ellipse test must not divide by its zero radii.
      declare
         E : Ks_Ellipse;
         C : Ks_Circle;
      begin
         E.Set_Center_XY_Radius_XY_Rotation (0.0, 0.0, 0.0, 0.0, 0.3);
         Check (E.Contains_Point (0.0, 0.0), "point ellipse: the origin");
         Check (not E.Contains_Point (1.0E-300, 0.0),
                "point ellipse: nothing else");
         Check (E.Boundary_Slack = 0.0, "point ellipse: no slack");
         C.Set_Center_Radius (0.0, 0.0, 0.0);
         Check (C.Contains_Point (0.0, 0.0), "point circle: the origin");
         Check (not C.Contains_Point (0.0, -1.0E-300),
                "point circle: nothing else");
      end;
   end Test_Slack;

   procedure Test_Boundary_Slack is
      --  Every point that Contains_Point accepts must lie within
      --  Boundary_Slack of the bounding box along each axis. The places
      --  where the slack reaches furthest are next to the points where a
      --  region touches its box (and at the corners of an affine
      --  rectangle), so a fine grid of points is tested around each of
      --  them.

      procedure Check_Bound
        (R : Ks_Region'Class; Around : Point_Array; Label : String)
      is
         S : constant Real := R.Boundary_Slack;
         Min_X, Min_Y, Max_X, Max_Y : Real;
         Beyond_Slack : Natural := 0;
         Beyond_Box   : Natural := 0;
      begin
         R.Get_Bounding_Box (Min_X, Min_Y, Max_X, Max_Y);
         for P of Around loop
            for I in -40 .. 40 loop
               for J in -40 .. 40 loop
                  declare
                     X : constant Real := P.X + Real (I) * S / 8.0;
                     Y : constant Real := P.Y + Real (J) * S / 8.0;
                  begin
                     if R.Contains_Point (X, Y) then
                        if X < Min_X - S or else X > Max_X + S
                          or else Y < Min_Y - S or else Y > Max_Y + S
                        then
                           Beyond_Slack := Beyond_Slack + 1;
                        end if;
                        if X < Min_X or else X > Max_X
                          or else Y < Min_Y or else Y > Max_Y
                        then
                           Beyond_Box := Beyond_Box + 1;
                        end if;
                     end if;
                  end;
               end loop;
            end loop;
         end loop;
         Check (S > 0.0, Label & ": positive slack");
         Check (Beyond_Slack = 0,
                Label & ":" & Natural'Image (Beyond_Slack)
                & " accepted points beyond Boundary_Slack");
         Check (Beyond_Box > 0,
                Label & ": the slack zone was reached (no accepted point"
                & " outside the box)");
      end Check_Bound;

      function Affine_Corners (R : Ks_Rectangle_Affine) return Point_Array is
        ([(R.Corner_Origin_X, R.Corner_Origin_Y),
          (R.Corner_X_X, R.Corner_X_Y),
          (R.Corner_Y_X, R.Corner_Y_Y),
          (R.Corner_Opposite_X, R.Corner_Opposite_Y)]);

      function Ellipse_Extremes (E : Ks_Ellipse) return Point_Array is
         --  Where Center + (Rx cos s, Ry sin s) turned by T has its
         --  extreme x (tan s = -Ry sin T / (Rx cos T)) and extreme y
         --  (tan s = Ry cos T / (Rx sin T)), and the opposite points.
         CT : constant Real := EF.Cos (E.Rotation);
         ST : constant Real := EF.Sin (E.Rotation);
         SX : constant Real :=
           EF.Arctan (-(E.Radius_Y * ST), E.Radius_X * CT);
         SY : constant Real := EF.Arctan (E.Radius_Y * CT, E.Radius_X * ST);

         function At_Parameter (S : Real) return Point is
           ((E.Center_X + E.Radius_X * EF.Cos (S) * CT
                        - E.Radius_Y * EF.Sin (S) * ST,
             E.Center_Y + E.Radius_X * EF.Cos (S) * ST
                        + E.Radius_Y * EF.Sin (S) * CT));
      begin
         return [At_Parameter (SX), At_Parameter (SX + Pi),
                 At_Parameter (SY), At_Parameter (SY + Pi)];
      end Ellipse_Extremes;

      Rect   : Ks_Rectangle;
      Affine : Ks_Rectangle_Affine;
      Circle : Ks_Circle;
      Ell    : Ks_Ellipse;
      Poly   : Ks_Polygon;
      Sect   : Ks_Circular_Annulus_Section;
   begin
      Section ("Boundary_Slack bounds every accepted point");
      Rect.Set_XY_Width_Height (2.0, 3.0, 10.0, 6.0);
      Check_Bound (Rect, [(2.0, 3.0), (12.0, 3.0), (2.0, 9.0), (12.0, 9.0)],
                   "rectangle");

      Circle.Set_Center_Radius (5.0, -3.0, 7.0);
      Check_Bound (Circle, [(12.0, -3.0), (-2.0, -3.0), (5.0, 4.0),
                            (5.0, -10.0)], "circle");
      Circle.Set_Center_Radius (1.0E9 + 5.0, 15.0, 1.0E9);
      Check_Bound (Circle, [(5.0, 15.0), (1.0E9 + 5.0, 1.0E9 + 15.0)],
                   "huge circle");

      Ell.Set_Center_XY_Radius_XY_Rotation (1.0, 2.0, 8.0, 3.0, 0.4);
      Check_Bound (Ell, Ellipse_Extremes (Ell), "ellipse");

      --  Affine rectangles: plain, skewed, and slivers whose sides are
      --  nearly or exactly collinear, where the widened sides meet far
      --  beyond the acute corners and the projection bounds cut them off.
      Affine.Set_Center_Lengths_Rotation_Skew (3.0, -2.0, 12.0, 7.0, 0.7, 0.0);
      Check_Bound (Affine, Affine_Corners (Affine), "affine rectangle");
      Affine.Set_Center_Lengths_Rotation_Skew (3.0, -2.0, 12.0, 7.0, 0.7, 1.2);
      Check_Bound (Affine, Affine_Corners (Affine), "skewed affine");
      Affine.Set_Center_Lengths_Rotation_Skew
        (3.0, -2.0, 12.0, 7.0, 0.7, Pi / 2.0 - 1.0E-6);
      Check_Bound (Affine, Affine_Corners (Affine), "sliver affine");
      Affine.Set_Center_Lengths_Rotation_Skew
        (3.0, -2.0, 12.0, 7.0, 0.7, -(Pi / 2.0 - 1.0E-9));
      Check_Bound (Affine, Affine_Corners (Affine), "sliver affine, -skew");
      Affine.Set_Origin_Corner_X_Corner_Y (0.0, 0.0, 10.0, 0.0, 5.0, 0.0);
      Check_Bound (Affine, Affine_Corners (Affine), "collinear affine");

      Poly.Add_Vertex (0.0, 0.0);
      Poly.Add_Vertex (20.0, 3.0);
      Poly.Add_Vertex (8.0, 15.0);
      Poly.Add_Vertex (10.0, 5.0);
      Check_Bound (Poly, [(0.0, 0.0), (20.0, 3.0), (8.0, 15.0), (10.0, 5.0)],
                   "polygon");

      --  Annulus sections: the ends of the span at both radii, the axis
      --  directions and the centre.
      declare
         procedure Check_Section (Label : String) is
            R1 : constant Real := Sect.Radius;
            R2 : constant Real := Sect.Radius * Sect.Radial_Scale;
            A1 : constant Real := Sect.Angle_Start;
            A2 : constant Real := Sect.Angle_Start + Sect.Angle_Span;
            CX : constant Real := Sect.Center_X;
            CY : constant Real := Sect.Center_Y;
         begin
            Check_Bound
              (Sect,
               [(CX, CY),
                (CX + R1 * EF.Cos (A1), CY + R1 * EF.Sin (A1)),
                (CX + R2 * EF.Cos (A1), CY + R2 * EF.Sin (A1)),
                (CX + R1 * EF.Cos (A2), CY + R1 * EF.Sin (A2)),
                (CX + R2 * EF.Cos (A2), CY + R2 * EF.Sin (A2)),
                (CX + R2, CY), (CX - R2, CY), (CX, CY + R2), (CX, CY - R2)],
               Label);
         end Check_Section;
      begin
         Sect.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
           (1.0, 2.0, 10.0, 0.3, 1.0, 1.5);
         Check_Section ("annulus section");
         Sect.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
           (1.0, 2.0, 10.0, 0.3, 1.0, 0.0);
         Check_Section ("sector (inner radius 0)");
         Sect.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
           (1.0, 2.0, 10.0, 0.3, 0.0, 1.0);
         Check_Section ("point section (zero span, radial scale 1)");
         Sect.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
           (1.0, 2.0, 10.0, 0.0, 2.0 * Pi, 1.5);
         Check_Section ("full annulus");
      end;
   end Test_Boundary_Slack;

   procedure Test_Enclosing_Rectangle is

      procedure Check_Enclosing (Region : Ks_Region'Class; Label : String) is
         Min_X, Min_Y, Max_X, Max_Y : Real;
         Box : constant Ks_Rectangle := Region.Enclosing_Rectangle;
      begin
         Region.Get_Bounding_Box (Min_X, Min_Y, Max_X, Max_Y);
         Check (Box.X = Min_X and then Box.Y = Min_Y
                and then Box.Width = Max_X - Min_X
                and then Box.Height = Max_Y - Min_Y,
                Label & ": the bounding box as a rectangle");
         Check (Box.Selected_Space_Name = Region.Selected_Space_Name,
                Label & ": same selected space");
      end Check_Enclosing;

      Rect    : Ks_Rectangle;
      Affine  : Ks_Rectangle_Affine;
      Circle  : Ks_Circle;
      Ellipse : Ks_Ellipse;
      Poly    : Ks_Polygon;
      Section_Shape : Ks_Circular_Annulus_Section;
   begin
      Section ("Enclosing_Rectangle");
      Rect.Set_XY_Width_Height (-3.0, 4.5, 10.0, 0.0);
      Rect.Set_Selected_Space_Name ("@\Fix");
      declare
         Box : constant Ks_Rectangle := Enclosing_Rectangle (Rect);
      begin
         Check (Box.X = -3.0 and then Box.Y = 4.5 and then Box.Width = 10.0
                and then Box.Height = 0.0
                and then Box.Selected_Space_Name = "@\Fix",
                "a rectangle encloses itself");
      end;
      Check_Enclosing (Rect, "rectangle");
      Rect.Set_XY_Width_Height (0.1, 0.7, 0.2, 0.1);
      declare
         Box : constant Ks_Rectangle := Rect.Enclosing_Rectangle;
      begin
         Check (Box.X = 0.1 and then Box.Y = 0.7
                and then abs (Box.Width - 0.2) <= 1.0E-16
                and then abs (Box.Height - 0.1) <= 1.0E-16,
                "a rectangle encloses itself up to the rounding of "
                & "(X + Width) - X");
      end;

      Affine.Set_Center_Lengths_Rotation_Skew (5.0, -2.0, 8.0, 3.0, 0.6, 0.2);
      Check_Enclosing (Affine, "affine rectangle");

      Circle.Set_Center_Radius (1.0, 2.0, 3.0);
      Circle.Set_Selected_Space_Name ("#");
      Check_Enclosing (Circle, "circle");
      declare
         Box : constant Ks_Rectangle := Circle.Enclosing_Rectangle;
      begin
         Check (Box.X = -2.0 and then Box.Y = -1.0 and then Box.Width = 6.0
                and then Box.Height = 6.0
                and then Box.Selected_Space_Name = "#",
                "circle: values");
      end;

      Ellipse.Set_Center_XY_Radius_XY_Rotation
        (10.0, 20.0, 5.0, 2.0, Pi / 2.0);
      Check_Enclosing (Ellipse, "rotated ellipse");
      declare
         Box : constant Ks_Rectangle := Ellipse.Enclosing_Rectangle;
      begin
         Check_Near (Box.Center_X, 10.0, Tol, "ellipse: centre x");
         Check_Near (Box.Center_Y, 20.0, Tol, "ellipse: centre y");
         Check_Near (Box.Width, 4.0, Tol, "ellipse: width (Radius_Y across)");
         Check_Near (Box.Height, 10.0, Tol,
                     "ellipse: height (Radius_X along y)");
      end;

      Check_Enclosing (Poly, "polygon without vertices");
      Check (Poly.Enclosing_Rectangle.Width = 0.0
             and then Poly.Enclosing_Rectangle.Area = 0.0,
             "polygon without vertices: an empty rectangle at the origin");
      Poly.Add_Vertex (1.0, 1.0);
      Poly.Add_Vertex (7.0, -2.0);
      Poly.Add_Vertex (4.0, 9.0);
      Check_Enclosing (Poly, "triangle");
      Check (Poly.Enclosing_Rectangle.X = 1.0
             and then Poly.Enclosing_Rectangle.Y = -2.0
             and then Poly.Enclosing_Rectangle.Width = 6.0
             and then Poly.Enclosing_Rectangle.Height = 11.0,
             "triangle: values");

      Section_Shape.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (0.0, 0.0, 10.0, 0.0, Pi / 2.0, 0.5);
      Check_Enclosing (Section_Shape, "annulus section");

      --  Through a holder (a class-wide region).
      declare
         H : constant AMV.Shapes.Region_Holders.Holder :=
           AMV.Shapes.Region_Holders.To_Holder (Circle);
      begin
         Check_Enclosing (H.Element, "circle in a holder");
      end;
   end Test_Enclosing_Rectangle;

   procedure Test_Errors is
   begin
      Section ("errors: bad parameters");
      for C in Bad_Parameter_Case loop
         Current_Bad := C;
         Check_Bad_Parameter (Bad_Parameter_Case'Image (C));
      end loop;

      Section ("errors: polygon indices");
      for C in Index_Case loop
         Current_Index := C;
         Check_Index_Error (Index_Case'Image (C));
      end loop;

      Section ("errors: singular directions");
      for C in Singular_Case loop
         Current_Singular := C;
         Check_Singular (Singular_Case'Image (C));
      end loop;
   end Test_Errors;

   procedure Test_Region_Holders is
      use AMV.Shapes.Region_Holders;
      H, H2  : Holder;
      Rect   : Ks_Rectangle;
      Circle : Ks_Circle;
   begin
      Section ("region holders");
      Check (H.Is_Empty, "a new holder is empty");
      Rect.Set_XY_Width_Height (0.0, 0.0, 10.0, 20.0);
      H := To_Holder (Rect);
      Check (not H.Is_Empty, "To_Holder fills it");
      Check (H.Element'Tag = Ks_Rectangle'Tag, "holds a rectangle");
      Check (H.Element.Contains_Point (5.0, 15.0), "dispatching contains");
      Check (not H.Element.Contains_Point (15.0, 5.0),
             "dispatching contains (outside)");
      Check (H.Element.Area = 200.0, "dispatching area");
      H2 := H;
      Circle.Set_Center_Radius (0.0, 0.0, 2.0);
      H.Replace_Element (Circle);
      Check (H.Element'Tag = Ks_Circle'Tag, "replaced by a circle");
      Check_Near (H.Element.Area, 4.0 * Pi, 1.0E-12, "circle area");
      Check (H2.Element'Tag = Ks_Rectangle'Tag,
             "a copy of the holder keeps its own region");
      declare
         Min_X, Min_Y, Max_X, Max_Y : Real;
      begin
         H.Element.Get_Bounding_Box (Min_X, Min_Y, Max_X, Max_Y);
         Check (Min_X = -2.0 and then Max_Y = 2.0, "dispatching box");
      end;
      declare
         M : constant Ks_Shape'Class :=
           H.Element.Map (Transform_Of (MC_Anisotropic));
      begin
         Check (M'Tag = Ks_Ellipse'Tag, "dispatching map");
      end;
      H.Clear;
      Check (H.Is_Empty, "Clear empties it");
      Check (not H2.Is_Empty, "the copy is still full");
   end Test_Region_Holders;

   procedure Run_All is
   begin
      Test_Defaults;
      Test_Rectangle;
      Test_Rectangle_Affine;
      Test_Circle;
      Test_Ellipse;
      Test_Polygon;
      Test_Annulus;
      Test_Line;
      Test_Segment;
      Test_Point_Marker;
      Test_Arc;
      Test_Extreme_Scales;
      Test_Slack;
      Test_Boundary_Slack;
      Test_Enclosing_Rectangle;
      Test_Errors;
      Test_Region_Holders;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Shapes;
