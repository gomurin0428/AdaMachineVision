--  Tests for the synthetic test image generator AMV_Test_Images: drawn
--  shapes must have the analytic area and centroid, edges must sit where
--  they were asked for, and patterns and noise must be reproducible.

with Ada.Exceptions;
with Ada.Numerics.Long_Elementary_Functions;

with AMV;              use AMV;
with AMV.Images;       use AMV.Images;
with AMV.Misc;
with AMV_Test_Images;  use AMV_Test_Images;
with AMV_Test_Support; use AMV_Test_Support;

procedure Test_Test_Images is

   package EF renames Ada.Numerics.Long_Elementary_Functions;

   use type AMV.Images.Grey_8;

   Pi : constant := AMV.Misc.Pi;

   Area_Tolerance     : constant := 0.005;   --  relative
   Centroid_Tolerance : constant := 0.02;    --  pixels

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   procedure Measure
     (Image             : Ks_Image_8_Grey;
      Background, Value : Grey_8;
      Area, Cx, Cy      : out Real)
   is
      --  Coverage-weighted area and centroid of what was drawn with Value
      --  on a uniform Background.
      Scale : constant Real := 1.0 / (Real (Value) - Real (Background));
      Sum, Sum_X, Sum_Y : Real := 0.0;
   begin
      for Y in 0 .. Image.Height - 1 loop
         for X in 0 .. Image.Width - 1 loop
            declare
               W : constant Real :=
                 (Real (Image.Get_Pixel (X, Y)) - Real (Background)) * Scale;
            begin
               Sum := Sum + W;
               Sum_X := Sum_X + W * Real (X);
               Sum_Y := Sum_Y + W * Real (Y);
            end;
         end loop;
      end loop;
      Area := Sum;
      if Sum /= 0.0 then
         Cx := Sum_X / Sum;
         Cy := Sum_Y / Sum;
      else
         Cx := 0.0;
         Cy := 0.0;
      end if;
   end Measure;

   procedure Check_Shape
     (Image                : Ks_Image_8_Grey;
      Background, Value    : Grey_8;
      Expected_Area        : Real;
      Expected_X           : Real;
      Expected_Y           : Real;
      Description          : String)
   is
      Area, Cx, Cy : Real;
   begin
      Measure (Image, Background, Value, Area, Cx, Cy);
      Check_Near (Area / Expected_Area, 1.0, Area_Tolerance,
                  Description & ": relative area");
      Check_Near (Cx, Expected_X, Centroid_Tolerance,
                  Description & ": centroid x");
      Check_Near (Cy, Expected_Y, Centroid_Tolerance,
                  Description & ": centroid y");
   end Check_Shape;

   function Same_Pixels (A, B : Ks_Image_8_Grey) return Boolean is
   begin
      if A.Width /= B.Width or else A.Height /= B.Height then
         return False;
      end if;
      for Y in 0 .. A.Height - 1 loop
         for X in 0 .. A.Width - 1 loop
            if A.Get_Pixel (X, Y) /= B.Get_Pixel (X, Y) then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Same_Pixels;

   type Box is record
      Left, Right, Top, Bottom : Real;
   end record;
   type Box_List is array (Positive range <>) of Box;

   function Overlap (Lo, Hi, A, B : Real) return Real is
     (Real'Max (0.0, Real'Min (Hi, B) - Real'Max (Lo, A)));

   function Box_Mismatches
     (Image : Ks_Image_8_Grey; Boxes : Box_List) return Natural
   is
      --  Number of pixels that differ from round (255 * coverage), where
      --  the coverage is the exact area of the disjoint axis-aligned boxes
      --  inside the pixel square (drawn with Value 255 on 0).
      Count : Natural := 0;
   begin
      for Y in 0 .. Image.Height - 1 loop
         for X in 0 .. Image.Width - 1 loop
            declare
               Cover : Real := 0.0;
            begin
               for B of Boxes loop
                  Cover := Cover
                    + Overlap (Real (X) - 0.5, Real (X) + 0.5,
                               B.Left, B.Right)
                    * Overlap (Real (Y) - 0.5, Real (Y) + 0.5,
                               B.Top, B.Bottom);
               end loop;
               if Image.Get_Pixel (X, Y) /= Grey_8 (Integer (255.0 * Cover))
               then
                  Count := Count + 1;
               end if;
            end;
         end loop;
      end loop;
      return Count;
   end Box_Mismatches;

   procedure Polygon_Area_Centroid
     (Vertices     : Vertex_List;
      Area, Cx, Cy : out Real)
   is
      --  Shoelace formulas for a simple polygon.
      N : constant Positive := Vertices'Length / 2;
      A, Sx, Sy : Real := 0.0;
   begin
      for I in 0 .. N - 1 loop
         declare
            J  : constant Natural := (I + 1) mod N;
            X0 : constant Real := Vertices (Vertices'First + 2 * I);
            Y0 : constant Real := Vertices (Vertices'First + 2 * I + 1);
            X1 : constant Real := Vertices (Vertices'First + 2 * J);
            Y1 : constant Real := Vertices (Vertices'First + 2 * J + 1);
            Cr : constant Real := X0 * Y1 - X1 * Y0;
         begin
            A := A + Cr;
            Sx := Sx + (X0 + X1) * Cr;
            Sy := Sy + (Y0 + Y1) * Cr;
         end;
      end loop;
      Area := abs (0.5 * A);
      Cx := Sx / (3.0 * A);
      Cy := Sy / (3.0 * A);
   end Polygon_Area_Centroid;

   ---------------------------------------------------------------------
   --  Tests
   ---------------------------------------------------------------------

   procedure Test_Blank is
      B : constant Ks_Image_8_Grey := Blank (7, 3, 42);
      Z : constant Ks_Image_8_Grey := Blank (2, 2);
   begin
      Section ("Blank");
      Check (B.Width = 7 and then B.Height = 3, "size");
      Check (B.Get_Pixel (0, 0) = 42 and then B.Get_Pixel (6, 2) = 42,
             "value");
      Check (Z.Get_Pixel (1, 1) = 0, "default value 0");
      Check_Near (Mean_Value (B, 0, 0, 7, 3), 42.0, 0.0, "Mean_Value");
   end Test_Blank;

   procedure Test_Circles is
      type Circle is record
         X, Y, R : Real;
      end record;
      Circles : constant array (Positive range <>) of Circle :=
        [(40.3, 35.7, 15.0), (50.0, 50.0, 20.25), (30.62, 28.15, 7.5),
         (64.81, 47.33, 31.7), (20.5, 20.5, 10.0), (33.333, 25.111, 12.345)];
   begin
      Section ("Draw_Circle");
      for C of Circles loop
         declare
            Img : Ks_Image_8_Grey := Blank (100, 100);
         begin
            Draw_Circle (Img, C.X, C.Y, C.R);
            Check_Shape (Img, 0, 255, Pi * C.R * C.R, C.X, C.Y,
                         "circle r" & C.R'Image);
         end;
      end loop;

      --  Darker shape on a bright background, other value and samples.
      declare
         Img : Ks_Image_8_Grey := Blank (80, 60, 200);
      begin
         Draw_Circle (Img, 41.27, 29.83, 18.0, Value => 50, Samples => 12);
         Check_Shape (Img, 200, 50, Pi * 18.0 * 18.0, 41.27, 29.83,
                      "dark circle, 12 samples");
         Check (Img.Get_Pixel (41, 30) = 50, "centre pixel fully covered");
         Check (Img.Get_Pixel (5, 5) = 200, "far pixel untouched");
      end;

      --  Clipped by the image corner: a quarter disc remains.
      declare
         Img          : Ks_Image_8_Grey := Blank (30, 30);
         Area, Cx, Cy : Real;
      begin
         Draw_Circle (Img, -0.5, -0.5, 20.0);
         Measure (Img, 0, 255, Area, Cx, Cy);
         Check_Near (Area / (Pi * 400.0 / 4.0), 1.0, Area_Tolerance,
                     "quarter disc area");
         --  Centroid of a quarter disc: 4 R / (3 Pi) from the corner.
         Check_Near (Cx, -0.5 + 80.0 / (3.0 * Pi), Centroid_Tolerance,
                     "quarter disc centroid x");
         Check_Near (Cy, -0.5 + 80.0 / (3.0 * Pi), Centroid_Tolerance,
                     "quarter disc centroid y");
      end;

      --  Entirely outside, degenerate radius: nothing changes.
      declare
         Img : Ks_Image_8_Grey := Blank (20, 20, 7);
         Ref : constant Ks_Image_8_Grey := Blank (20, 20, 7);
      begin
         Draw_Circle (Img, -30.0, 10.0, 5.0);
         Draw_Circle (Img, 10.0, 1.0E9, 5.0);
         Draw_Circle (Img, 10.0, 10.0, 0.0);
         Draw_Circle (Img, 10.0, 10.0, -3.0);
         Check (Same_Pixels (Img, Ref), "outside / degenerate circles");
      end;

      --  One sample per pixel gives a binary image.
      declare
         Img    : Ks_Image_8_Grey := Blank (40, 40);
         Binary : Boolean := True;
      begin
         Draw_Circle (Img, 20.3, 19.6, 11.0, Samples => 1);
         for Y in 0 .. 39 loop
            for X in 0 .. 39 loop
               Binary := Binary
                 and then (Img.Get_Pixel (X, Y) = 0
                           or else Img.Get_Pixel (X, Y) = 255);
            end loop;
         end loop;
         Check (Binary, "Samples = 1 gives a binary image");
         --  With one sample the pixel is set when its centre is inside.
         Check (Img.Get_Pixel (31, 20) = 255,
                "centre inside at distance 10.7");
         Check (Img.Get_Pixel (32, 20) = 0, "centre outside at distance 11.7");
      end;
   end Test_Circles;

   procedure Test_Rectangles is
      type Rect is record
         X, Y, W, H, R : Real;
      end record;
      --  Oblique rectangles: tight area and centroid checks.
      Rects : constant array (Positive range <>) of Rect :=
        [(50.4, 40.8, 30.0, 14.0, 0.3), (45.5, 45.5, 20.5, 20.5, 0.9),
         (60.2, 30.9, 40.0, 10.0, -1.1), (47.1, 52.9, 33.3, 17.7, 2.5),
         (50.6, 49.2, 25.0, 25.0, -3.0), (38.3, 61.7, 12.0, 31.0, 1.9)];

      --  Axis-aligned rectangles: every edge is quantised to the nearest
      --  multiple of 1/8 from a pixel boundary (the sample lattice), so
      --  the drawn shape is exactly the rectangle with snapped edges.
      Aligned : constant array (Positive range <>) of Rect :=
        [(40.25, 30.75, 21.5, 11.5, 0.0), (50.0, 50.0, 60.0, 8.0, Pi / 2.0),
         (50.625, 49.125, 25.0, 25.0, -Pi), (50.6, 49.2, 25.0, 25.0, 0.0),
         (33.37, 41.91, 17.3, 29.06, Pi / 2.0),
         (61.03, 44.44, 30.1, 9.9, Pi)];

      --  45 degree rectangles: whole edges are quantised along the
      --  diagonal, by up to half the diagonal sample spacing.
      Diagonal : constant array (Positive range <>) of Rect :=
        [(45.5, 45.5, 20.5, 20.5, Pi / 4.0),
         (52.3, 47.9, 30.0, 12.0, -3.0 * Pi / 4.0)];

      function Snap (E : Real) return Real is
        (Real'Rounding ((E + 0.5) * 8.0) / 8.0 - 0.5);
   begin
      Section ("Draw_Rectangle");
      for R of Rects loop
         declare
            Img : Ks_Image_8_Grey := Blank (100, 100);
         begin
            Draw_Rectangle (Img, R.X, R.Y, R.W, R.H, R.R);
            Check_Shape (Img, 0, 255, R.W * R.H, R.X, R.Y,
                         "rectangle" & R.W'Image & " x" & R.H'Image
                         & " rot" & R.R'Image);
         end;
      end loop;

      for R of Aligned loop
         declare
            Img      : Ks_Image_8_Grey := Blank (100, 100);
            Vertical : constant Boolean := abs (abs R.R - Pi / 2.0) < 0.1;
            Ex       : constant Real := 0.5 * (if Vertical then R.H else R.W);
            Ey       : constant Real := 0.5 * (if Vertical then R.W else R.H);
            Left     : constant Real := Snap (R.X - Ex);
            Right    : constant Real := Snap (R.X + Ex);
            Top      : constant Real := Snap (R.Y - Ey);
            Bottom   : constant Real := Snap (R.Y + Ey);
            Name     : constant String :=
              "aligned rectangle at" & R.X'Image & "," & R.Y'Image;
            Area, Cx, Cy : Real;
         begin
            Draw_Rectangle (Img, R.X, R.Y, R.W, R.H, R.R);
            Check (Box_Mismatches (Img, [(Left, Right, Top, Bottom)]) = 0,
                   Name & ": pixels match the snapped rectangle exactly");
            Measure (Img, 0, 255, Area, Cx, Cy);
            Check_Near (Area / (R.W * R.H), 1.0,
                        2.0 * (R.W + R.H) / 16.0 / (R.W * R.H) + 0.001,
                        Name & ": area within the quantisation bound");
            --  Edge quantisation (1/16) plus the bias of weighting a
            --  partly covered pixel at its centre (at most 1/8 of a pixel
            --  per edge pixel row, over a width of at least 8).
            Check (abs (Cx - R.X) <= 1.0 / 16.0 + 1.0 / 64.0
                   and then abs (Cy - R.Y) <= 1.0 / 16.0 + 1.0 / 64.0,
                   Name & ": centroid near the centre");
         end;
      end loop;

      for R of Diagonal loop
         declare
            Img   : Ks_Image_8_Grey := Blank (100, 100);
            Bound : constant Real :=
              2.0 * (R.W + R.H) * EF.Sqrt (2.0) / 32.0 + 0.5;
            Name  : constant String := "45 degree rectangle" & R.W'Image;
            Area, Cx, Cy : Real;
         begin
            Draw_Rectangle (Img, R.X, R.Y, R.W, R.H, R.R);
            Measure (Img, 0, 255, Area, Cx, Cy);
            Check_Near (Area, R.W * R.H, Bound, Name & ": area bound");
            Check_Near (Cx, R.X, 1.0 / 16.0 + 0.005, Name & ": centroid x");
            Check_Near (Cy, R.Y, 1.0 / 16.0 + 0.005, Name & ": centroid y");
         end;
      end loop;

      --  Axis-aligned edges on pixel boundaries and pixel middles give
      --  exact coverage: x in [29.5, 51.0], y in [25.0, 36.5].
      declare
         Img          : Ks_Image_8_Grey := Blank (80, 60);
         Area, Cx, Cy : Real;
      begin
         Draw_Rectangle (Img, 40.25, 30.75, 21.5, 11.5);
         Measure (Img, 0, 255, Area, Cx, Cy);
         Check (Img.Get_Pixel (29, 30) = 0, "left edge on a pixel boundary");
         Check (Img.Get_Pixel (30, 30) = 255, "first full column");
         Check (Img.Get_Pixel (50, 30) = 255, "last full column");
         Check (Img.Get_Pixel (51, 30) = 128,
                "half-covered column: round (127.5) = 128");
         Check (Img.Get_Pixel (52, 30) = 0, "right of the rectangle");
         Check (Img.Get_Pixel (40, 25) = 128, "half-covered row");
         Check (Img.Get_Pixel (40, 24) = 0, "above the rectangle");
         Check (Img.Get_Pixel (40, 36) = 255, "last full row");
         Check (Img.Get_Pixel (40, 37) = 0, "below the rectangle");
         Check (Img.Get_Pixel (51, 25) = 64,
                "quarter-covered corner: round (63.75) = 64");
      end;

      --  Blending onto existing content.
      declare
         Img : Ks_Image_8_Grey := Blank (20, 20, 100);
      begin
         Draw_Rectangle (Img, 10.0, 10.0, 5.0, 5.0);
         --  Pixel 12 covers [11.5, 12.5]; the edge is at 12.5: full.
         Check (Img.Get_Pixel (12, 10) = 255, "full pixel");
         Check (Img.Get_Pixel (13, 10) = 100, "outside pixel");
         Draw_Rectangle (Img, 3.0, 3.0, 2.0, 1.0);
         --  x in [2, 4]: pixels 2 and 4 half covered; y in [2.5, 3.5].
         Check (Img.Get_Pixel (2, 3) = 178,
                "half coverage blends: round (177.5) = 178");
         Check (Img.Get_Pixel (3, 3) = 255, "full coverage");
         Check (Img.Get_Pixel (3, 2) = 100, "row above untouched");
      end;

      declare
         Img : Ks_Image_8_Grey := Blank (20, 20);
         Ref : constant Ks_Image_8_Grey := Blank (20, 20);
      begin
         Draw_Rectangle (Img, 10.0, 10.0, 0.0, 5.0);
         Draw_Rectangle (Img, 10.0, 10.0, 5.0, -1.0);
         Draw_Rectangle (Img, 100.0, 100.0, 5.0, 5.0, 0.7);
         Check (Same_Pixels (Img, Ref), "degenerate / outside rectangles");
      end;
   end Test_Rectangles;

   procedure Test_Ellipses is
      type Ellipse is record
         X, Y, A, B, R : Real;
      end record;
      Ellipses : constant array (Positive range <>) of Ellipse :=
        [(50.3, 45.6, 20.0, 12.0, 0.5), (40.0, 40.0, 15.5, 8.25, 0.0),
         (55.7, 38.2, 25.0, 10.0, -2.0), (48.8, 51.4, 9.0, 30.0, 1.3),
         (50.5, 50.5, 14.0, 14.0, 0.9)];
   begin
      Section ("Draw_Ellipse");
      for E of Ellipses loop
         declare
            Img : Ks_Image_8_Grey := Blank (100, 100);
         begin
            Draw_Ellipse (Img, E.X, E.Y, E.A, E.B, E.R);
            Check_Shape (Img, 0, 255, Pi * E.A * E.B, E.X, E.Y,
                         "ellipse" & E.A'Image & " x" & E.B'Image
                         & " rot" & E.R'Image);
         end;
      end loop;

      --  The rotation turns the major axis: with Rotation = Pi / 2 the
      --  long axis is vertical.
      declare
         Img : Ks_Image_8_Grey := Blank (60, 60);
      begin
         Draw_Ellipse (Img, 30.0, 30.0, 20.0, 5.0, Pi / 2.0);
         Check (Img.Get_Pixel (30, 12) = 255, "vertical major axis");
         Check (Img.Get_Pixel (12, 30) = 0, "short horizontal axis");
      end;

      declare
         Img : Ks_Image_8_Grey := Blank (20, 20);
         Ref : constant Ks_Image_8_Grey := Blank (20, 20);
      begin
         Draw_Ellipse (Img, 10.0, 10.0, 0.0, 5.0);
         Draw_Ellipse (Img, 10.0, 10.0, 5.0, -2.0);
         Check (Same_Pixels (Img, Ref), "degenerate ellipses");
      end;
   end Test_Ellipses;

   function Rotated
     (Vertices         : Vertex_List;
      Angle            : Real;
      Pivot_X, Pivot_Y : Real;
      Shift_X, Shift_Y : Real := 0.0) return Vertex_List
   is
      --  The vertices rotated by Angle about the pivot, then shifted.
      Result : Vertex_List (Vertices'Range);
      C      : constant Real := EF.Cos (Angle);
      S      : constant Real := EF.Sin (Angle);
   begin
      for K in 0 .. Vertices'Length / 2 - 1 loop
         declare
            I  : constant Positive := Vertices'First + 2 * K;
            Dx : constant Real := Vertices (I) - Pivot_X;
            Dy : constant Real := Vertices (I + 1) - Pivot_Y;
         begin
            Result (I) := Pivot_X + C * Dx - S * Dy + Shift_X;
            Result (I + 1) := Pivot_Y + S * Dx + C * Dy + Shift_Y;
         end;
      end loop;
      return Result;
   end Rotated;

   procedure Test_Polygons is
      Triangle : constant Vertex_List :=
        [10.3, 12.1, 60.7, 20.4, 30.2, 55.9];
      L_Upright : constant Vertex_List :=
        [10.2, 10.4, 40.2, 10.4, 40.2, 20.4, 20.2, 20.4, 20.2, 45.4,
         10.2, 45.4];
      L_Shape   : constant Vertex_List :=
        Rotated (L_Upright, 0.37, 30.0, 30.0, 12.5, 9.0);
      Concave  : constant Vertex_List :=
        [15.5, 60.25, 30.0, 12.0, 45.3, 50.0, 62.0, 18.7, 80.1, 70.4];
      Rotated_Square : Vertex_List (1 .. 8);
   begin
      Section ("Draw_Polygon");
      for P in 1 .. 3 loop
         declare
            Img          : Ks_Image_8_Grey := Blank (100, 100);
            Area, Cx, Cy : Real;
         begin
            case P is
               when 1 =>
                  Draw_Polygon (Img, Triangle);
                  Polygon_Area_Centroid (Triangle, Area, Cx, Cy);
               when 2 =>
                  Draw_Polygon (Img, L_Shape);
                  Polygon_Area_Centroid (L_Shape, Area, Cx, Cy);
               when others =>
                  Draw_Polygon (Img, Concave);
                  Polygon_Area_Centroid (Concave, Area, Cx, Cy);
            end case;
            Check_Shape (Img, 0, 255, Area, Cx, Cy, "polygon" & P'Image);
         end;
      end loop;

      declare
         Area, Cx, Cy : Real;
      begin
         Polygon_Area_Centroid (L_Shape, Area, Cx, Cy);
         Check_Near (Area, 550.0, 1.0E-9, "L-shape analytic area");
      end;

      --  Upright, the L has axis-aligned edges, which are quantised to the
      --  sample lattice: x = 10.2 and 40.2 render as 10.25 and 40.25, so
      --  the shape moves right by 0.05; y = 10.4, 20.4 and 45.4 render as
      --  10.375, 20.375 and 45.375, so it moves up by 0.025.
      declare
         Img : Ks_Image_8_Grey := Blank (60, 60);
      begin
         Draw_Polygon (Img, L_Upright);
         Check (Box_Mismatches
                  (Img, [(10.25, 40.25, 10.375, 20.375),
                         (10.25, 20.25, 20.375, 45.375)]) = 0,
                "upright L matches the snapped boxes exactly");
      end;

      --  A square given as a polygon matches the analytic square, also
      --  with the vertices in clockwise order and starting elsewhere.
      for K in 0 .. 3 loop
         declare
            A : constant Real := 0.6 + Real (K) * Pi / 2.0;
         begin
            Rotated_Square (2 * K + 1) := 50.2 + 20.0 * EF.Cos (A);
            Rotated_Square (2 * K + 2) := 49.7 + 20.0 * EF.Sin (A);
         end;
      end loop;
      declare
         Img : Ks_Image_8_Grey := Blank (100, 100);
         Reversed : constant Vertex_List :=
           [Rotated_Square (7), Rotated_Square (8),
            Rotated_Square (5), Rotated_Square (6),
            Rotated_Square (3), Rotated_Square (4),
            Rotated_Square (1), Rotated_Square (2)];
         Img2 : Ks_Image_8_Grey := Blank (100, 100);
      begin
         Draw_Polygon (Img, Rotated_Square);
         Check_Shape (Img, 0, 255, 800.0, 50.2, 49.7, "rotated square");
         Draw_Polygon (Img2, Reversed);
         Check (Same_Pixels (Img, Img2), "vertex order does not matter");
      end;

      --  Even-odd rule on a self-intersecting bow tie: both triangles are
      --  filled (area 300 each), so the total is 600 around (30.3, 25.45)
      --  (tilted so that no edge is axis-aligned).
      declare
         Img     : Ks_Image_8_Grey := Blank (60, 50);
         Tilted  : Ks_Image_8_Grey := Blank (60, 50);
         Bow_Tie : constant Vertex_List :=
           [10.3, 10.45, 50.3, 40.45, 50.3, 10.45, 10.3, 40.45];
      begin
         Draw_Polygon (Img, Bow_Tie);
         Check (Img.Get_Pixel (30, 15) = 0, "bow tie gap above the crossing");
         Check (Img.Get_Pixel (30, 35) = 0, "bow tie gap below the crossing");
         Check (Img.Get_Pixel (15, 25) = 255, "bow tie left triangle");
         Check (Img.Get_Pixel (45, 25) = 255, "bow tie right triangle");
         Draw_Polygon (Tilted, Rotated (Bow_Tie, 0.2, 30.3, 25.45));
         Check_Shape (Tilted, 0, 255, 600.0, 30.3, 25.45, "tilted bow tie");
      end;

      --  A list with a non-default first index.
      declare
         Img     : Ks_Image_8_Grey := Blank (40, 40);
         Shifted : Vertex_List (11 .. 16);
         Area, Cx, Cy : Real;
      begin
         Shifted := [5.25, 5.5, 35.75, 8.0, 12.0, 33.3];
         Draw_Polygon (Img, Shifted);
         Polygon_Area_Centroid (Shifted, Area, Cx, Cy);
         Check_Shape (Img, 0, 255, Area, Cx, Cy, "vertex list from index 11");
      end;

      declare
         Img : Ks_Image_8_Grey := Blank (20, 20);
         Ref : constant Ks_Image_8_Grey := Blank (20, 20);
      begin
         Draw_Polygon (Img, [1.0, 1.0, 10.0, 10.0]);
         Draw_Polygon (Img, [1.0, 1.0, 10.0, 10.0, 15.0, 15.0]);  --  flat
         Check (Same_Pixels (Img, Ref), "fewer than 3 vertices / zero area");
      end;

      declare
         Img : Ks_Image_8_Grey := Blank (20, 20);
         procedure Odd_Length is
         begin
            Draw_Polygon (Img, [1.0, 1.0, 10.0, 10.0, 15.0]);
         end Odd_Length;
         procedure T1 is new Check_Raises_Exactly
           (Odd_Length, Ks_Bad_Parameter_Exception'Identity);
      begin
         T1 ("odd-length vertex list");
      end;
   end Test_Polygons;

   procedure Test_Annulus is
   begin
      Section ("Draw_Annulus");
      declare
         Img : Ks_Image_8_Grey := Blank (100, 100);
      begin
         Draw_Annulus (Img, 50.4, 50.6, 10.0, 20.0);
         Check_Shape (Img, 0, 255, Pi * (400.0 - 100.0), 50.4, 50.6,
                      "annulus 10 .. 20");
         Check (Img.Get_Pixel (50, 51) = 0, "hole is empty");
         Check (Img.Get_Pixel (65, 51) = 255, "ring is filled");
      end;
      declare
         Img : Ks_Image_8_Grey := Blank (80, 80);
      begin
         Draw_Annulus (Img, 40.15, 39.85, 25.3, 31.9, Value => 180);
         Check_Shape (Img, 0, 180, Pi * (31.9 ** 2 - 25.3 ** 2),
                      40.15, 39.85, "thin annulus");
      end;
      declare
         Img : Ks_Image_8_Grey := Blank (60, 60);
      begin
         Draw_Annulus (Img, 30.3, 29.4, 0.0, 12.0);
         Check_Shape (Img, 0, 255, Pi * 144.0, 30.3, 29.4,
                      "annulus with inner radius 0 is a disc");
      end;
      declare
         Img : Ks_Image_8_Grey := Blank (20, 20);
         Ref : constant Ks_Image_8_Grey := Blank (20, 20);
      begin
         Draw_Annulus (Img, 10.0, 10.0, 5.0, 5.0);
         Draw_Annulus (Img, 10.0, 10.0, 6.0, 3.0);
         Check (Same_Pixels (Img, Ref), "empty annuli draw nothing");
      end;
   end Test_Annulus;

   procedure Test_Half_Plane is
      W : constant := 64;
      H : constant := 48;
      type Natural_List is array (Positive range <>) of Natural;
   begin
      Section ("Draw_Half_Plane");

      --  Horizontal edge at y = 20.25, filled below (Rotation 0: the left
      --  normal (0, 1) points down). Edge on sample boundaries: exact.
      declare
         Img : Ks_Image_8_Grey := Blank (W, H);
      begin
         Draw_Half_Plane (Img, 10.0, 20.25, 0.0);
         for X of Natural_List'[0, 17, W - 1] loop
            declare
               Mean : constant Real := Mean_Value (Img, X, 0, 1, H);
            begin
               --  Covered length of the column is H - 0.5 - edge.
               Check_Near (Real (H) - 0.5 - Real (H) * Mean / 255.0, 20.25,
                           0.5 / 255.0 + 1.0E-9,
                           "horizontal edge from column" & X'Image);
            end;
         end loop;
         Check (Img.Get_Pixel (5, 19) = 0, "row above the edge");
         Check (Img.Get_Pixel (5, 20) = 64, "edge row: 2 of 8 sample rows");
         Check (Img.Get_Pixel (5, 21) = 255, "row below the edge");
      end;

      --  An edge between sample rows is located to 1 / (2 * Samples).
      declare
         Img : Ks_Image_8_Grey := Blank (W, H);
      begin
         Draw_Half_Plane (Img, 0.0, 20.3, 0.0);
         Check (Img.Get_Pixel (40, 20) = 64, "y = 20.3 still 2 of 8 rows");
      end;

      --  Vertical edge at x = 17.125 (Rotation Pi / 2: direction down,
      --  left normal (-1, 0), so the left side is filled).
      declare
         Img : Ks_Image_8_Grey := Blank (W, H);
      begin
         Draw_Half_Plane (Img, 17.125, 5.0, Pi / 2.0);
         for Y of Natural_List'[0, 23, H - 1] loop
            declare
               Mean : constant Real := Mean_Value (Img, 0, Y, W, 1);
            begin
               Check_Near (Real (W) * Mean / 255.0 - 0.5, 17.125,
                           0.5 / 255.0 + 1.0E-9,
                           "vertical edge from row" & Y'Image);
            end;
         end loop;
         Check (Img.Get_Pixel (17, 3) = 159, "edge column: 5 of 8 samples");
         Check (Img.Get_Pixel (16, 3) = 255 and then Img.Get_Pixel (18, 3) = 0,
                "left side filled");
      end;

      --  Rotation Pi fills above the line.
      declare
         Img : Ks_Image_8_Grey := Blank (W, H);
      begin
         Draw_Half_Plane (Img, 30.0, 10.75, Pi);
         Check (Img.Get_Pixel (30, 5) = 255
                and then Img.Get_Pixel (30, 15) = 0,
                "Rotation Pi fills above");
         Check_Near (Real (H) * Mean_Value (Img, 30, 0, 1, H) / 255.0 - 0.5,
                     10.75, 0.5 / 255.0 + 1.0E-9, "edge at y = 10.75");
      end;

      --  A tilted edge through (32, 24.5) with direction 0.3 rad: column
      --  X crosses it at y = 24.5 + (X - 32) tan 0.3. The column means
      --  give the crossing to a small fraction of a pixel.
      declare
         Img       : Ks_Image_8_Grey := Blank (W, H);
         Angle     : constant Real := 0.3;
         Worst     : Real := 0.0;
         Sum_Error : Real := 0.0;
         Count     : Natural := 0;
      begin
         Draw_Half_Plane (Img, 32.0, 24.5, Angle);
         for X in 0 .. W - 1 loop
            declare
               Truth : constant Real :=
                 24.5 + (Real (X) - 32.0) * EF.Tan (Angle);
               Mean  : constant Real := Mean_Value (Img, X, 0, 1, H);
               Est   : constant Real :=
                 Real (H) - 0.5 - Real (H) * Mean / 255.0;
            begin
               --  Only columns whose edge stays well inside the image.
               if Truth > 2.0 and then Truth < Real (H) - 3.0 then
                  Worst := Real'Max (Worst, abs (Est - Truth));
                  Sum_Error := Sum_Error + (Est - Truth);
                  Count := Count + 1;
               end if;
            end;
         end loop;
         Check (Count > 40, "enough profile columns");
         Check_Near (Worst, 0.0, 0.04, "tilted edge, worst column");
         Check_Near (Sum_Error / Real (Count), 0.0, 0.01,
                     "tilted edge, mean error");
         --  Points well away from the line.
         Check (Img.Get_Pixel (32, 30) = 255, "below a tilted line: filled");
         Check (Img.Get_Pixel (32, 19) = 0, "above a tilted line: empty");
      end;
   end Test_Half_Plane;

   procedure Test_Checkerboard is
   begin
      Section ("Checkerboard");
      declare
         Img    : Ks_Image_8_Grey := Blank (60, 50, 77);
         In_Range : Boolean := True;
      begin
         Checkerboard (Img, 10.0, 10.0, 8.0);
         Check (Img.Get_Pixel (14, 14) = 220, "square at the origin is light");
         Check (Img.Get_Pixel (22, 14) = 30, "next square along x is dark");
         Check (Img.Get_Pixel (14, 22) = 30, "next square along y is dark");
         Check (Img.Get_Pixel (22, 22) = 220, "diagonal square is light");
         Check (Img.Get_Pixel (6, 6) = 220, "square (-1, -1) is light");
         Check (Img.Get_Pixel (6, 14) = 30, "square (-1, 0) is dark");
         Check (Img.Get_Pixel (54, 46) = 30, "square (5, 4) is dark");
         Check (Img.Get_Pixel (10, 14) = 125,
                "pixel on a vertical boundary is half and half");
         Check (Img.Get_Pixel (10, 10) = 125,
                "pixel on a grid corner is half and half");
         for Y in 0 .. 49 loop
            for X in 0 .. 59 loop
               In_Range := In_Range and then Img.Get_Pixel (X, Y) >= 30
                 and then Img.Get_Pixel (X, Y) <= 220;
            end loop;
         end loop;
         Check (In_Range, "every pixel between Dark and Light");
      end;

      --  With square edges on pixel boundaries every pixel is pure, and a
      --  window of 6 x 4 whole squares has the mean of Dark and Light.
      declare
         Img  : Ks_Image_8_Grey := Blank (60, 50);
         Pure : Boolean := True;
      begin
         Checkerboard (Img, 9.5, 9.5, 8.0);
         for Y in 0 .. 49 loop
            for X in 0 .. 59 loop
               Pure := Pure and then (Img.Get_Pixel (X, Y) = 30
                                      or else Img.Get_Pixel (X, Y) = 220);
            end loop;
         end loop;
         Check (Pure, "aligned board has only Dark and Light pixels");
         Check_Near (Mean_Value (Img, 10, 10, 48, 32), 125.0, 0.0,
                     "mean over whole squares");
         Check (Img.Get_Pixel (10, 10) = 220
                and then Img.Get_Pixel (9, 10) = 30
                and then Img.Get_Pixel (17, 17) = 220
                and then Img.Get_Pixel (18, 17) = 30,
                "aligned board square boundaries");
      end;

      --  Rotated board: pixels nearest to square centres take the colour
      --  given by the parity of the square indices.
      declare
         Img   : Ks_Image_8_Grey := Blank (80, 70);
         Angle : constant Real := 0.4;
         S     : constant Real := 10.0;
         Ox    : constant Real := 40.3;
         Oy    : constant Real := 34.7;
         Dxx   : constant Real := EF.Cos (Angle);
         Dxy   : constant Real := EF.Sin (Angle);
         Ok    : Boolean := True;
         Seen  : Natural := 0;
      begin
         Checkerboard (Img, Ox, Oy, S, Angle, Dark => 0, Light => 200);
         for J in -3 .. 2 loop
            for I in -3 .. 2 loop
               declare
                  U  : constant Real := (Real (I) + 0.5) * S;
                  V  : constant Real := (Real (J) + 0.5) * S;
                  Px : constant Real := Ox + U * Dxx - V * Dxy;
                  Py : constant Real := Oy + U * Dxy + V * Dxx;
                  Xi : constant Integer := Integer (Px);
                  Yi : constant Integer := Integer (Py);
               begin
                  if Xi in 0 .. 79 and then Yi in 0 .. 69 then
                     Seen := Seen + 1;
                     Ok := Ok and then Img.Get_Pixel (Xi, Yi)
                       = (if (I + J) mod 2 = 0 then 200 else 0);
                  end if;
               end;
            end loop;
         end loop;
         Check (Seen >= 30, "enough square centres inside the image");
         Check (Ok, "rotated board colours by parity");
      end;

      declare
         Img : Ks_Image_8_Grey := Blank (10, 10);
         procedure Zero_Size is
         begin
            Checkerboard (Img, 0.0, 0.0, 0.0);
         end Zero_Size;
         procedure Negative_Size is
         begin
            Checkerboard (Img, 0.0, 0.0, -4.0);
         end Negative_Size;
         procedure T1 is new Check_Raises_Exactly
           (Zero_Size, Ks_Bad_Parameter_Exception'Identity);
         procedure T2 is new Check_Raises_Exactly
           (Negative_Size, Ks_Bad_Parameter_Exception'Identity);
      begin
         T1 ("Square_Size 0");
         T2 ("negative Square_Size");
      end;
   end Test_Checkerboard;

   procedure Test_Ramp is
   begin
      Section ("Horizontal_Ramp");
      declare
         R  : constant Ks_Image_8_Grey :=
           Horizontal_Ramp (11, 3, 10.0, 110.0);
         Ok : Boolean := True;
      begin
         Check (R.Width = 11 and then R.Height = 3, "size");
         for Y in 0 .. 2 loop
            for X in 0 .. 10 loop
               Ok := Ok and then R.Get_Pixel (X, Y) = Grey_8 (10 + 10 * X);
            end loop;
         end loop;
         Check (Ok, "values 10 + 10 X");
      end;
      declare
         R : constant Ks_Image_8_Grey := Horizontal_Ramp (4, 1, 0.0, 255.0);
      begin
         Check (R.Get_Pixel (0, 0) = 0 and then R.Get_Pixel (1, 0) = 85
                and then R.Get_Pixel (2, 0) = 170
                and then R.Get_Pixel (3, 0) = 255, "0 .. 255 in 4 steps");
      end;
      declare
         R : constant Ks_Image_8_Grey := Horizontal_Ramp (5, 2, 1.0, 2.0);
      begin
         --  1, 1.25, 1.5, 1.75, 2 rounded.
         Check (R.Get_Pixel (1, 0) = 1 and then R.Get_Pixel (2, 0) = 2
                and then R.Get_Pixel (3, 1) = 2, "rounding");
      end;
      declare
         R : constant Ks_Image_8_Grey :=
           Horizontal_Ramp (7, 1, -100.0, 400.0);
      begin
         Check (R.Get_Pixel (0, 0) = 0 and then R.Get_Pixel (6, 0) = 255
                and then R.Get_Pixel (3, 0) = 150, "clamping");
      end;
      declare
         R : constant Ks_Image_8_Grey := Horizontal_Ramp (1, 3, 12.6, 99.0);
      begin
         Check (R.Get_Pixel (0, 2) = 13, "width 1 uses Low");
      end;
      declare
         R : constant Ks_Image_8_Grey := Horizontal_Ramp (6, 1, 200.0, 50.0);
      begin
         Check (R.Get_Pixel (0, 0) = 200 and then R.Get_Pixel (5, 0) = 50
                and then R.Get_Pixel (2, 0) = 140, "descending ramp");
      end;
   end Test_Ramp;

   procedure Test_Noise is
      Base : constant Ks_Image_8_Grey := Blank (100, 100, 128);
   begin
      Section ("Add_Noise");
      declare
         A : Ks_Image_8_Grey := Base.Copy;
         B : Ks_Image_8_Grey := Base.Copy;
         C : Ks_Image_8_Grey := Base.Copy;
         D : Ks_Image_8_Grey := Base.Copy;
         Within : Boolean := True;
         Sum, Sum_Sq : Real := 0.0;
      begin
         Add_Noise (A, 20.0, Seed => 7);
         Add_Noise (B, 20.0, Seed => 7);
         Add_Noise (C, 20.0, Seed => 8);
         Add_Noise (D, -20.0, Seed => 7);
         Check (Same_Pixels (A, B), "same seed, same noise");
         Check (not Same_Pixels (A, C), "different seed, different noise");
         Check (Same_Pixels (A, D), "negative amplitude acts like positive");
         Check (not Same_Pixels (A, Base), "noise changes the image");
         Check (Base.Get_Pixel (0, 0) = 128, "the copied base is untouched");
         for Y in 0 .. 99 loop
            for X in 0 .. 99 loop
               declare
                  V : constant Real := Real (A.Get_Pixel (X, Y));
               begin
                  Within := Within and then V >= 108.0 and then V <= 148.0;
                  Sum := Sum + V;
                  Sum_Sq := Sum_Sq + (V - 128.0) ** 2;
               end;
            end loop;
         end loop;
         Check (Within, "noise within the amplitude");
         --  Uniform noise in [-20, 20]: mean 0, variance 400 / 3 (plus
         --  1 / 12 from rounding).
         Check_Near (Sum / 10_000.0, 128.0, 0.6, "noise mean");
         Check_Near (EF.Sqrt (Sum_Sq / 10_000.0),
                     EF.Sqrt (400.0 / 3.0 + 1.0 / 12.0), 0.5,
                     "noise standard deviation");
      end;

      declare
         A : Ks_Image_8_Grey := Base.Copy;
         B : Ks_Image_8_Grey := Base.Copy;
      begin
         Add_Noise (A, 0.0);
         Check (Same_Pixels (A, Base), "zero amplitude changes nothing");
         Add_Noise (B, 5.0);   --  default seed
         declare
            B2 : Ks_Image_8_Grey := Base.Copy;
         begin
            Add_Noise (B2, 5.0, Seed => 1);
            Check (Same_Pixels (B, B2), "default seed is 1");
         end;
         declare
            Z1 : Ks_Image_8_Grey := Base.Copy;
            Z2 : Ks_Image_8_Grey := Base.Copy;
         begin
            Add_Noise (Z1, 5.0, Seed => 0);
            Add_Noise (Z2, 5.0, Seed => 0);
            Check (Same_Pixels (Z1, Z2), "seed 0 is deterministic");
         end;
      end;

      declare
         Bright : Ks_Image_8_Grey := Blank (50, 50, 250);
         Dim    : Ks_Image_8_Grey := Blank (50, 50, 3);
         Hit_255, Hit_0 : Boolean := False;
      begin
         Add_Noise (Bright, 30.0, Seed => 3);
         Add_Noise (Dim, 30.0, Seed => 3);
         for Y in 0 .. 49 loop
            for X in 0 .. 49 loop
               Hit_255 := Hit_255 or else Bright.Get_Pixel (X, Y) = 255;
               Hit_0 := Hit_0 or else Dim.Get_Pixel (X, Y) = 0;
            end loop;
         end loop;
         Check (Hit_255 and then Hit_0, "noise clamps at 0 and 255");
      end;
   end Test_Noise;

   procedure Test_Mean_Value is
      Img : Ks_Image_8_Grey := Blank (5, 4);
   begin
      Section ("Mean_Value");
      for Y in 0 .. 3 loop
         for X in 0 .. 4 loop
            Img.Set_Pixel (X, Y, Grey_8 (X + 10 * Y));
         end loop;
      end loop;
      Check_Near (Mean_Value (Img, 0, 0, 5, 4), 17.0, 1.0E-12, "whole image");
      Check_Near (Mean_Value (Img, 1, 1, 2, 2), 16.5, 1.0E-12, "window");
      Check_Near (Mean_Value (Img, 4, 3, 1, 1), 34.0, 0.0, "last pixel");

      declare
         None : Ks_Image_8_Grey;
         procedure Empty_Window is
            V : constant Real := Mean_Value (Img, 0, 0, 0, 2);
         begin
            Check (V = V, "unreachable");
         end Empty_Window;
         procedure Outside_X is
            V : constant Real := Mean_Value (Img, 3, 0, 3, 1);
         begin
            Check (V = V, "unreachable");
         end Outside_X;
         procedure Outside_Y is
            V : constant Real := Mean_Value (Img, 0, 4, 1, 1);
         begin
            Check (V = V, "unreachable");
         end Outside_Y;
         procedure Huge is
            V : constant Real := Mean_Value (Img, Natural'Last, 0, 1, 1);
         begin
            Check (V = V, "unreachable");
         end Huge;
         procedure Unallocated is
            V : constant Real := Mean_Value (None, 0, 0, 1, 1);
         begin
            Check (V = V, "unreachable");
         end Unallocated;
         Bad : constant Ada.Exceptions.Exception_Id :=
           Ks_Bad_Parameter_Exception'Identity;
         procedure T1 is new Check_Raises_Exactly (Empty_Window, Bad);
         procedure T2 is new Check_Raises_Exactly (Outside_X, Bad);
         procedure T3 is new Check_Raises_Exactly (Outside_Y, Bad);
         procedure T4 is new Check_Raises_Exactly (Huge, Bad);
         procedure T5 is new Check_Raises_Exactly
           (Unallocated, Ks_Image_No_Pixels_Exception'Identity);
      begin
         T1 ("empty window");
         T2 ("window past the right edge");
         T3 ("window past the bottom edge");
         T4 ("window origin Natural'Last");
         T5 ("unallocated image");
      end;
   end Test_Mean_Value;

   procedure Test_Unallocated is
      None : Ks_Image_8_Grey;
      No_Pixels : constant Ada.Exceptions.Exception_Id :=
        Ks_Image_No_Pixels_Exception'Identity;
      procedure Rect is
      begin
         Draw_Rectangle (None, 1.0, 1.0, 2.0, 2.0);
      end Rect;
      procedure Circle is
      begin
         Draw_Circle (None, 1.0, 1.0, 2.0);
      end Circle;
      procedure Ellipse is
      begin
         Draw_Ellipse (None, 1.0, 1.0, 2.0, 1.0);
      end Ellipse;
      procedure Polygon is
      begin
         Draw_Polygon (None, [0.0, 0.0, 1.0, 0.0, 0.0, 1.0]);
      end Polygon;
      procedure Half_Plane is
      begin
         Draw_Half_Plane (None, 1.0, 1.0, 0.0);
      end Half_Plane;
      procedure Annulus is
      begin
         Draw_Annulus (None, 1.0, 1.0, 1.0, 2.0);
      end Annulus;
      procedure Noise is
      begin
         Add_Noise (None, 3.0);
      end Noise;
      procedure Board is
      begin
         Checkerboard (None, 0.0, 0.0, 4.0);
      end Board;
      procedure Degenerate_Circle is
      begin
         Draw_Circle (None, 1.0, 1.0, 0.0);
      end Degenerate_Circle;
      procedure T1 is new Check_Raises_Exactly (Rect, No_Pixels);
      procedure T2 is new Check_Raises_Exactly (Circle, No_Pixels);
      procedure T3 is new Check_Raises_Exactly (Ellipse, No_Pixels);
      procedure T4 is new Check_Raises_Exactly (Polygon, No_Pixels);
      procedure T5 is new Check_Raises_Exactly (Half_Plane, No_Pixels);
      procedure T6 is new Check_Raises_Exactly (Annulus, No_Pixels);
      procedure T7 is new Check_Raises_Exactly (Noise, No_Pixels);
      procedure T8 is new Check_Raises_Exactly (Board, No_Pixels);
      procedure T9 is new Check_Raises_Exactly
        (Degenerate_Circle, No_Pixels);
   begin
      Section ("Unallocated images");
      T1 ("Draw_Rectangle");
      T2 ("Draw_Circle");
      T3 ("Draw_Ellipse");
      T4 ("Draw_Polygon");
      T5 ("Draw_Half_Plane");
      T6 ("Draw_Annulus");
      T7 ("Add_Noise");
      T8 ("Checkerboard");
      T9 ("Draw_Circle with radius 0");
   end Test_Unallocated;

   procedure Test_Accuracy_Figures is
      --  The cases the spec's accuracy paragraph singles out, checked
      --  against the bounds it documents for the default Samples = 8.

      Step_Bound : constant Real := 1.0 / (2.0 * 8.0);
      --  Half a lattice step: the largest shift of an axis-aligned edge.

      function Edge_Bound (P, Q : Real) return Real is
        (Step_Bound / EF.Sqrt (P * P + Q * Q));
      --  The largest shift of an edge with direction (Q, P).

      procedure Check_Centroid
        (Img : Ks_Image_8_Grey; X, Y, Bound : Real; Description : String)
      is
         Area, Cx, Cy : Real;
      begin
         Measure (Img, 0, 255, Area, Cx, Cy);
         Check (EF.Sqrt ((Cx - X) ** 2 + (Cy - Y) ** 2) <= Bound,
                Description & ": centroid error"
                & Real'Image (EF.Sqrt ((Cx - X) ** 2 + (Cy - Y) ** 2))
                & " within" & Real'Image (Bound));
      end Check_Centroid;
   begin
      Section ("documented accuracy figures");

      --  A small circle: up to about 0.025 pixel and 1 percent.
      declare
         Img : Ks_Image_8_Grey := Blank (100, 100);
         X0  : constant Real := 50.7488543990701;
         Y0  : constant Real := 50.2403267400893;
         R   : constant Real := 3.44603004831140;
         Area, Cx, Cy : Real;
      begin
         Draw_Circle (Img, X0, Y0, R);
         Measure (Img, 0, 255, Area, Cx, Cy);
         Check_Centroid (Img, X0, Y0, 0.025, "circle of radius 3.45");
         Check_Near (Area / (Pi * R * R), 1.0, 0.01,
                     "circle of radius 3.45: relative area");
      end;
      declare
         Img : Ks_Image_8_Grey := Blank (100, 100);
         Area, Cx, Cy : Real;
      begin
         Draw_Circle (Img, 50.5, 50.0, 2.5);
         Measure (Img, 0, 255, Area, Cx, Cy);
         Check_Near (Area / (Pi * 6.25), 1.0, 0.01,
                     "circle of radius 2.5: relative area within 1%");
         Check (abs (Area / (Pi * 6.25) - 1.0) > Area_Tolerance,
                "circle of radius 2.5: beyond the 0.5% the larger circles"
                & " meet");
      end;

      --  Edges with slope 1/2 (and -2): up to sqrt 2 times the edge bound.
      declare
         Img : Ks_Image_8_Grey := Blank (100, 100);
         X0  : constant Real := 50.9841465908727;
         Y0  : constant Real := 50.8838373330411;
      begin
         Draw_Rectangle (Img, X0, Y0, 30.0, 14.0, EF.Arctan (0.5));
         Check_Centroid (Img, X0, Y0, EF.Sqrt (2.0) * Edge_Bound (1.0, 2.0),
                         "rectangle turned by atan (1/2)");
      end;

      --  An integer-vertex triangle, shifted: its steepest-bound edge has
      --  slope 1/2.
      declare
         Img : Ks_Image_8_Grey := Blank (100, 100);
         DX  : constant Real := 0.6707;
         DY  : constant Real := 0.7421;
      begin
         Draw_Polygon (Img, [10.0 + DX, 10.0 + DY, 50.0 + DX, 30.0 + DY,
                             20.0 + DX, 50.0 + DY]);
         Check_Centroid (Img, 80.0 / 3.0 + DX, 30.0 + DY,
                         EF.Sqrt (2.0) * Edge_Bound (1.0, 2.0),
                         "integer-vertex triangle");
      end;

      --  A generic direction averages out: about 0.002 pixel.
      declare
         Img : Ks_Image_8_Grey := Blank (100, 100);
         X0  : constant Real := 50.9841465908727;
         Y0  : constant Real := 50.8838373330411;
      begin
         Draw_Rectangle (Img, X0, Y0, 30.0, 14.0, 0.3);
         Check_Centroid (Img, X0, Y0, 0.003, "rectangle turned by 0.3");
      end;

      --  An axis-aligned edge: 1/16 plus the 8-bit rounding.
      declare
         Img : Ks_Image_8_Grey := Blank (40, 40);
         Area, Cx, Cy : Real;
      begin
         Draw_Rectangle (Img, 20.0, 20.0, 10.0, 10.125);
         Measure (Img, 0, 255, Area, Cx, Cy);
         Check (abs (Area / 10.0 - 10.125) <= 2.0 * (Step_Bound + 0.5 / 255.0),
                "axis-aligned edges: shift within 1/16 + 0.5/255 each");
      end;
   end Test_Accuracy_Figures;

   procedure Run_All is
   begin
      Test_Blank;
      Test_Circles;
      Test_Rectangles;
      Test_Ellipses;
      Test_Polygons;
      Test_Annulus;
      Test_Half_Plane;
      Test_Checkerboard;
      Test_Ramp;
      Test_Noise;
      Test_Mean_Value;
      Test_Unallocated;
      Test_Accuracy_Figures;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Test_Images;
