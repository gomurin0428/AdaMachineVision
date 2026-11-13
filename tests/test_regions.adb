--  Tests for AMV.Regions: turning regions into sets of image pixels.
--
--  Every rasterised region is checked against ground truth computed here
--  independently (integer lattice arithmetic where the geometry allows it,
--  otherwise an explicit inside/outside margin together with a guard that
--  no pixel centre lies close enough to the boundary for rounding to
--  matter), and against the definition in the spec (Contains_Point of the
--  pixel centre mapped into the region's space) over the whole image.

with Ada.Exceptions;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Streams;
with Ada.Streams.Storage.Unbounded;
with Interfaces;

with AMV;                    use AMV;
with AMV.Coordinate_Spaces;  use AMV.Coordinate_Spaces;
with AMV.Images;             use AMV.Images;
with AMV.Misc;
with AMV.Regions;            use AMV.Regions;
with AMV.Shapes;             use AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Transforms;         use AMV.Transforms;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Regions is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package RH renames AMV.Shapes.Region_Holders;

   Pi : constant := AMV.Misc.Pi;

   W : constant := 40;
   H : constant := 30;
   --  Size of the default test image.

   Sink_Total : Natural := 0;
   --  Results fed to Consume end up here, so that calls made only for
   --  their exceptions cannot be optimised away.

   procedure Consume (R : Pixel_Region);

   procedure Consume (R : Pixel_Region) is
   begin
      Sink_Total := (Sink_Total + R.Pixel_Count) mod 1_000_000;
   end Consume;

   function Img (N : Integer) return String is
     (Integer'Image (N));

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   procedure Check_Bounds
     (R                          : Pixel_Region;
      Exp_X, Exp_Y, Exp_W, Exp_H : Natural;
      Exp_Count                  : Natural;
      Description                : String);
   --  Checks the bounding rectangle, the pixel count and Is_Empty.

   procedure Check_Bounds
     (R                          : Pixel_Region;
      Exp_X, Exp_Y, Exp_W, Exp_H : Natural;
      Exp_Count                  : Natural;
      Description                : String) is
   begin
      Check (R.X_Min = Exp_X and then R.Y_Min = Exp_Y
               and then R.Width = Exp_W and then R.Height = Exp_H,
             Description & ": bounds (" & Img (R.X_Min) & ","
             & Img (R.Y_Min) & "," & Img (R.Width) & "," & Img (R.Height)
             & " ), expected (" & Img (Exp_X) & "," & Img (Exp_Y) & ","
             & Img (Exp_W) & "," & Img (Exp_H) & " )");
      Check (R.Pixel_Count = Exp_Count,
             Description & ": pixel count" & Img (R.Pixel_Count)
             & ", expected" & Img (Exp_Count));
      Check (R.Is_Empty = (Exp_Count = 0), Description & ": Is_Empty");
   end Check_Bounds;

   procedure Check_Empty (R : Pixel_Region; Description : String);
   --  An empty region: all bounds 0 and no pixel at all is contained.

   procedure Check_Empty (R : Pixel_Region; Description : String) is
   begin
      Check_Bounds (R, 0, 0, 0, 0, 0, Description);
      Check (not R.Contains (0, 0) and then not R.Contains (5, 5)
               and then not R.Contains (-1, -1)
               and then not R.Contains (Integer'Last, Integer'Last)
               and then not R.Contains (Integer'First, Integer'First),
             Description & ": contains nothing");
   end Check_Empty;

   procedure Check_Pixels
     (R             : Pixel_Region;
      Image_Width   : Positive;
      Image_Height  : Positive;
      Expected      : not null access function (I, J : Integer)
                        return Boolean;
      Description   : String);
   --  Compares R with the pixel set described by Expected, evaluated at
   --  every pixel of an Image_Width x Image_Height image: membership of
   --  every pixel, the count, and the bounding rectangle (which must be
   --  the tight one). Also checks that no pixel just outside the image
   --  is contained.

   procedure Check_Pixels
     (R             : Pixel_Region;
      Image_Width   : Positive;
      Image_Height  : Positive;
      Expected      : not null access function (I, J : Integer)
                        return Boolean;
      Description   : String)
   is
      Count      : Natural := 0;
      Min_I      : Integer := Integer'Last;
      Max_I      : Integer := Integer'First;
      Min_J      : Integer := Integer'Last;
      Max_J      : Integer := Integer'First;
      Mismatches : Natural := 0;
      Bad_I      : Integer := 0;
      Bad_J      : Integer := 0;
      Outside    : Boolean := False;
   begin
      for J in 0 .. Image_Height - 1 loop
         for I in 0 .. Image_Width - 1 loop
            declare
               E : constant Boolean := Expected (I, J);
            begin
               if E then
                  Count := Count + 1;
                  Min_I := Integer'Min (Min_I, I);
                  Max_I := Integer'Max (Max_I, I);
                  Min_J := Integer'Min (Min_J, J);
                  Max_J := Integer'Max (Max_J, J);
               end if;
               if E /= R.Contains (I, J) then
                  if Mismatches = 0 then
                     Bad_I := I;
                     Bad_J := J;
                  end if;
                  Mismatches := Mismatches + 1;
               end if;
            end;
         end loop;
      end loop;

      Check (Mismatches = 0,
             Description & ":" & Img (Mismatches)
             & " pixels differ, first at (" & Img (Bad_I) & ","
             & Img (Bad_J) & " )");
      if Count = 0 then
         Check_Bounds (R, 0, 0, 0, 0, 0, Description);
      else
         Check_Bounds
           (R, Min_I, Min_J, Max_I - Min_I + 1, Max_J - Min_J + 1, Count,
            Description);
      end if;

      for I in -1 .. Image_Width loop
         Outside := Outside or else R.Contains (I, -1)
           or else R.Contains (I, Image_Height);
      end loop;
      for J in -1 .. Image_Height loop
         Outside := Outside or else R.Contains (-1, J)
           or else R.Contains (Image_Width, J);
      end loop;
      Check (not Outside, Description & ": nothing outside the image");
   end Check_Pixels;

   Guard_Distance : constant := 1.0E-6;

   procedure Check_Pixels_By_Margin
     (R            : Pixel_Region;
      Image_Width  : Positive;
      Image_Height : Positive;
      Margin       : not null access function (I, J : Integer) return Real;
      Description  : String);
   --  Like Check_Pixels with "Margin (I, J) >= 0" as the expected set,
   --  where Margin is positive inside and negative outside. First checks
   --  that no pixel has a margin within Guard_Distance of zero, so the
   --  floating point ground truth cannot be decided by rounding.

   procedure Check_Pixels_By_Margin
     (R            : Pixel_Region;
      Image_Width  : Positive;
      Image_Height : Positive;
      Margin       : not null access function (I, J : Integer) return Real;
      Description  : String)
   is
      Closest : Real := Real'Last;

      function Expected (I, J : Integer) return Boolean is
        (Margin (I, J) >= 0.0);
   begin
      for J in 0 .. Image_Height - 1 loop
         for I in 0 .. Image_Width - 1 loop
            Closest := Real'Min (Closest, abs Margin (I, J));
         end loop;
      end loop;
      Check (Closest > Guard_Distance,
             Description & ": ground truth is unambiguous (closest"
             & Real'Image (Closest) & ")");
      Check_Pixels
        (R, Image_Width, Image_Height, Expected'Access, Description);
   end Check_Pixels_By_Margin;

   procedure Check_Definition
     (Image       : Ks_Image'Class;
      Region      : Ks_Region'Class;
      R           : Pixel_Region;
      Description : String);
   --  Compares R over the whole image with the spec's definition: pixel
   --  (I, J) is in when Region.Contains_Point holds at
   --  Invert (Image.Get_Transform ("#", Region.Selected_Space_Name))
   --  applied to (I, J).

   procedure Check_Definition
     (Image       : Ks_Image'Class;
      Region      : Ks_Region'Class;
      R           : Pixel_Region;
      Description : String)
   is
      Inverse : constant Ks_Transform_2D_Linear :=
        Invert (Image.Get_Transform ("#", Region.Selected_Space_Name));

      function Expected (I, J : Integer) return Boolean is
         U, V : Real;
      begin
         Inverse.Map_Point (Real (I), Real (J), U, V);
         return Region.Contains_Point (U, V);
      end Expected;
   begin
      Check_Pixels
        (R, Image.Width, Image.Height, Expected'Access,
         Description & " [definition]");
   end Check_Definition;

   procedure Check_Same (A, B : Pixel_Region; Description : String);
   --  A and B hold the same pixels with the same bounding rectangle.

   procedure Check_Same (A, B : Pixel_Region; Description : String) is
      Differ : Natural := 0;
   begin
      Check_Bounds
        (B, A.X_Min, A.Y_Min, A.Width, A.Height, A.Pixel_Count,
         Description);
      for J in A.Y_Min - 1 .. A.Y_Min + A.Height loop
         for I in A.X_Min - 1 .. A.X_Min + A.Width loop
            if A.Contains (I, J) /= B.Contains (I, J) then
               Differ := Differ + 1;
            end if;
         end loop;
      end loop;
      Check (Differ = 0,
             Description & ":" & Img (Differ) & " pixels differ");
   end Check_Same;

   function Rectangle (X, Y, Width, Height : Real;
                       Space : String := ".") return Ks_Rectangle;
   function Rectangle (X, Y, Width, Height : Real;
                       Space : String := ".") return Ks_Rectangle is
   begin
      return Result : Ks_Rectangle do
         Result.Set_XY_Width_Height (X, Y, Width, Height);
         Result.Set_Selected_Space_Name (Space);
      end return;
   end Rectangle;

   function Circle (Center_X, Center_Y, Radius : Real;
                    Space : String := ".") return Ks_Circle;
   function Circle (Center_X, Center_Y, Radius : Real;
                    Space : String := ".") return Ks_Circle is
   begin
      return Result : Ks_Circle do
         Result.Set_Center_Radius (Center_X, Center_Y, Radius);
         Result.Set_Selected_Space_Name (Space);
      end return;
   end Circle;

   ---------------------------------------------------------------------
   --  Default value and Whole_Image
   ---------------------------------------------------------------------

   procedure Test_Default_And_Whole_Image is
      Default : Pixel_Region;
   begin
      Section ("default Pixel_Region");
      Check_Empty (Default, "default");

      Section ("Whole_Image");
      declare
         Image : constant Ks_Image_8_Grey := Create (W, H);
         R     : constant Pixel_Region := Whole_Image (Image);
         function All_Pixels (I, J : Integer) return Boolean is
           (I in 0 .. W - 1 and then J in 0 .. H - 1);
      begin
         Check_Bounds (R, 0, 0, W, H, W * H, "whole 40x30");
         Check_Pixels (R, W, H, All_Pixels'Access, "whole 40x30");
         Check (R.Contains (0, 0) and then R.Contains (W - 1, H - 1)
                  and then R.Contains (W - 1, 0)
                  and then R.Contains (0, H - 1),
                "whole: corners");
         Check (not R.Contains (W, 0) and then not R.Contains (0, H)
                  and then not R.Contains (-1, 0)
                  and then not R.Contains (0, -1),
                "whole: just outside");
         Check (not R.Contains (Integer'First, 0)
                  and then not R.Contains (Integer'Last, 0)
                  and then not R.Contains (0, Integer'First)
                  and then not R.Contains (0, Integer'Last)
                  and then not R.Contains (Integer'Last, Integer'Last),
                "whole: extreme coordinates");
      end;

      declare
         One : constant Ks_Image_8_Grey := Create (1, 1);
         R   : constant Pixel_Region := Whole_Image (One);
      begin
         Check_Bounds (R, 0, 0, 1, 1, 1, "whole 1x1");
         Check (R.Contains (0, 0) and then not R.Contains (1, 0)
                  and then not R.Contains (0, 1),
                "whole 1x1: membership");
      end;

      declare
         Image_16 : constant Ks_Image_16_Grey := Create (7, 5);
         Colour   : constant Ks_Image_24_Planar_Color := Create (3, 9);
      begin
         Check_Bounds (Whole_Image (Image_16), 0, 0, 7, 5, 35, "whole 16-bit");
         Check_Bounds (Whole_Image (Colour), 0, 0, 3, 9, 27, "whole colour");
      end;
   end Test_Default_And_Whole_Image;

   ---------------------------------------------------------------------
   --  Axis-aligned rectangles
   ---------------------------------------------------------------------

   procedure Test_Rectangles is
      Image : constant Ks_Image_8_Grey := Create (W, H);

      procedure Rect_Case
        (X, Y, Width, Height       : Real;
         Exp_X, Exp_Y, Exp_W, Exp_H : Natural;
         Description               : String);
      --  Rasterises the rectangle and checks the expected tight bounds
      --  (its pixels form the full Exp_W x Exp_H block), membership
      --  against the closed rectangle, and the definition.

      procedure Rect_Case
        (X, Y, Width, Height       : Real;
         Exp_X, Exp_Y, Exp_W, Exp_H : Natural;
         Description               : String)
      is
         Rect : constant Ks_Rectangle := Rectangle (X, Y, Width, Height);
         R    : constant Pixel_Region := Rasterize (Image, Rect);

         function Expected (I, J : Integer) return Boolean is
           (Real (I) >= X and then Real (I) <= X + Width
            and then Real (J) >= Y and then Real (J) <= Y + Height);
      begin
         Check_Bounds
           (R, Exp_X, Exp_Y, Exp_W, Exp_H, Exp_W * Exp_H, Description);
         Check_Pixels (R, W, H, Expected'Access, Description);
         Check_Definition (Image, Rect, R, Description);
      end Rect_Case;

   begin
      Section ("axis-aligned rectangles");
      --  Integer edges: both edges are included.
      Rect_Case (2.0, 3.0, 5.0, 4.0, 2, 3, 6, 5, "integer edges");
      Rect_Case (0.0, 0.0, 39.0, 29.0, 0, 0, W, H, "integer, whole image");
      --  Half-integer edges: they pass between pixel centres.
      Rect_Case (1.5, 2.5, 4.0, 3.0, 2, 3, 4, 3, "half-integer edges");
      Rect_Case (-0.5, -0.5, 40.0, 30.0, 0, 0, W, H,
                 "half-integer, image border");
      Rect_Case (1.25, 2.75, 3.5, 2.5, 2, 3, 3, 3, "quarter edges");
      Rect_Case (10.0, 4.5, 3.0, 2.0, 10, 5, 4, 2, "mixed edges");
      --  Degenerate rectangles reduce to segments or a point.
      Rect_Case (3.0, 2.0, 0.0, 4.0, 3, 2, 1, 5, "zero width");
      Rect_Case (3.0, 2.0, 4.0, 0.0, 3, 2, 5, 1, "zero height");
      Rect_Case (5.0, 6.0, 0.0, 0.0, 5, 6, 1, 1, "single point");

      declare
         Default_Rect : Ks_Rectangle;   --  (0, 0) 100 x 100
         R : constant Pixel_Region := Rasterize (Image, Default_Rect);
      begin
         Check_Bounds (R, 0, 0, W, H, W * H, "default rectangle");
      end;

      Check_Empty
        (Rasterize (Image, Rectangle (3.5, 2.0, 0.0, 4.0)),
         "zero width between centres");
      Check_Empty
        (Rasterize (Image, Rectangle (2.2, 2.2, 0.5, 0.5)),
         "small rectangle between centres");
   end Test_Rectangles;

   ---------------------------------------------------------------------
   --  Circles and ellipses
   ---------------------------------------------------------------------

   procedure Test_Circles is
      Image : constant Ks_Image_8_Grey := Create (W, H);

      procedure Lattice_Case
        (CX, CY : Integer; Radius : Real; R2 : Natural;
         Exp_Count : Natural; Description : String);
      --  A circle around a pixel centre: the expected pixels are those
      --  with DX**2 + DY**2 <= R2 (integers), and Exp_Count is the known
      --  number of lattice points in the disc.

      procedure Lattice_Case
        (CX, CY : Integer; Radius : Real; R2 : Natural;
         Exp_Count : Natural; Description : String)
      is
         C : constant Ks_Circle := Circle (Real (CX), Real (CY), Radius);
         R : constant Pixel_Region := Rasterize (Image, C);

         function Expected (I, J : Integer) return Boolean is
           ((I - CX) ** 2 + (J - CY) ** 2 <= R2);

         Reach : Natural := 0;   --  largest DX with DX**2 <= R2
      begin
         while (Reach + 1) ** 2 <= R2 loop
            Reach := Reach + 1;
         end loop;
         Check_Bounds
           (R, CX - Reach, CY - Reach, 2 * Reach + 1, 2 * Reach + 1,
            Exp_Count, Description);
         Check_Pixels (R, W, H, Expected'Access, Description);
         Check_Definition (Image, C, R, Description);
      end Lattice_Case;

      procedure Brute_Force_Case
        (CX, CY, Radius : Real; Description : String);
      --  Compares with the pixel centres whose distance from the centre
      --  is at most Radius, counted directly.

      procedure Brute_Force_Case
        (CX, CY, Radius : Real; Description : String)
      is
         C : constant Ks_Circle := Circle (CX, CY, Radius);
         R : constant Pixel_Region := Rasterize (Image, C);

         function Margin (I, J : Integer) return Real is
           (Radius - EF.Sqrt ((Real (I) - CX) ** 2 + (Real (J) - CY) ** 2));
      begin
         Check_Pixels_By_Margin (R, W, H, Margin'Access, Description);
         Check_Definition (Image, C, R, Description);
      end Brute_Force_Case;

   begin
      Section ("circles");
      --  Lattice point counts in discs of radius 1, sqrt 2, 2, 5, 10 (the
      --  boundary points, at exactly the radius, are included).
      Lattice_Case (20, 15, 1.0, 1, 5, "radius 1");
      Lattice_Case (20, 15, EF.Sqrt (2.0), 2, 9, "radius sqrt 2");
      Lattice_Case (20, 15, 2.0, 4, 13, "radius 2");
      Lattice_Case (20, 15, 5.0, 25, 81, "radius 5");
      Lattice_Case (20, 15, 10.0, 100, 317, "radius 10");
      Lattice_Case (7, 9, 0.0, 0, 1, "radius 0 on a pixel centre");

      Brute_Force_Case (20.5, 14.25, 7.3, "radius 7.3 off-grid");
      Brute_Force_Case (13.3, 17.9, 12.7, "radius 12.7 off-grid");
      Brute_Force_Case (10.5, 10.5, 3.0, "radius 3 at a pixel corner");
      Brute_Force_Case (31.77, 8.12, 0.81, "small radius");

      Check_Empty
        (Rasterize (Image, Circle (20.5, 15.0, 0.0)),
         "radius 0 between centres");
      Check_Empty
        (Rasterize (Image, Circle (5.5, 5.5, 0.3)),
         "small circle between centres");

      Section ("ellipses");
      declare
         CX : constant Real := 19.6;
         CY : constant Real := 14.3;
         RX : constant Real := 9.2;
         RY : constant Real := 4.7;
         Rot : constant Real := 0.6;
         E   : Ks_Ellipse;

         function Margin (I, J : Integer) return Real is
            DX : constant Real := Real (I) - CX;
            DY : constant Real := Real (J) - CY;
            U  : constant Real := DX * EF.Cos (Rot) + DY * EF.Sin (Rot);
            V  : constant Real := -DX * EF.Sin (Rot) + DY * EF.Cos (Rot);
         begin
            return 1.0 - ((U / RX) ** 2 + (V / RY) ** 2);
         end Margin;
      begin
         E.Set_Center_XY_Radius_XY_Rotation (CX, CY, RX, RY, Rot);
         declare
            R : constant Pixel_Region := Rasterize (Image, E);
         begin
            Check_Pixels_By_Margin (R, W, H, Margin'Access, "rotated");
            Check_Definition (Image, E, R, "rotated ellipse");
         end;
      end;
   end Test_Circles;

   ---------------------------------------------------------------------
   --  Affine rectangles
   ---------------------------------------------------------------------

   procedure Test_Affine_Rectangles is
      Image : constant Ks_Image_8_Grey := Create (W, H);

      function Affine
        (CX, CY, LX, LY, Rotation, Skew : Real) return Ks_Rectangle_Affine;
      function Affine
        (CX, CY, LX, LY, Rotation, Skew : Real) return Ks_Rectangle_Affine
      is
      begin
         return Result : Ks_Rectangle_Affine do
            Result.Set_Center_Lengths_Rotation_Skew
              (CX, CY, LX, LY, Rotation, Skew);
         end return;
      end Affine;

   begin
      Section ("affine rectangles: exact lattice cases");
      declare
         --  Turned by a quarter: side X (6) runs along +y, side Y (4)
         --  along -x, so it covers [18, 22] x [12, 18].
         A : constant Ks_Rectangle_Affine :=
           Affine (20.0, 15.0, 6.0, 4.0, Pi / 2.0, 0.0);
         R : constant Pixel_Region := Rasterize (Image, A);
         function Expected (I, J : Integer) return Boolean is
           (I in 18 .. 22 and then J in 12 .. 18);
      begin
         Check_Bounds (R, 18, 12, 5, 7, 35, "quarter turn");
         Check_Pixels (R, W, H, Expected'Access, "quarter turn");
         Check_Definition (Image, A, R, "quarter turn");
      end;

      declare
         --  A square of side 4 sqrt 2 turned by 45 degrees: the diamond
         --  abs DX + abs DY <= 4, with 2 * 4**2 + 2 * 4 + 1 = 41 points.
         A : constant Ks_Rectangle_Affine :=
           Affine (20.0, 15.0, 4.0 * EF.Sqrt (2.0), 4.0 * EF.Sqrt (2.0),
                   Pi / 4.0, 0.0);
         R : constant Pixel_Region := Rasterize (Image, A);
         function Expected (I, J : Integer) return Boolean is
           (abs (I - 20) + abs (J - 15) <= 4);
      begin
         Check_Bounds (R, 16, 11, 9, 9, 41, "diamond");
         Check_Pixels (R, W, H, Expected'Access, "diamond");
         Check_Definition (Image, A, R, "diamond");
      end;

      declare
         --  Zero side Y: the segment from (15, 15) to (25, 15).
         A : constant Ks_Rectangle_Affine :=
           Affine (20.0, 15.0, 10.0, 0.0, 0.0, 0.0);
         R : constant Pixel_Region := Rasterize (Image, A);
      begin
         Check_Bounds (R, 15, 15, 11, 1, 11, "horizontal segment");
         Check_Definition (Image, A, R, "horizontal segment");
      end;

      declare
         --  Zero side Y at 45 degrees: the diagonal from (18, 13) to
         --  (22, 17), through 5 pixel centres.
         A : constant Ks_Rectangle_Affine :=
           Affine (20.0, 15.0, 4.0 * EF.Sqrt (2.0), 0.0, Pi / 4.0, 0.0);
         R : constant Pixel_Region := Rasterize (Image, A);
         function Expected (I, J : Integer) return Boolean is
           (I in 18 .. 22 and then J = I - 5);
      begin
         Check_Bounds (R, 18, 13, 5, 5, 5, "diagonal segment");
         Check_Pixels (R, W, H, Expected'Access, "diagonal segment");
      end;

      Section ("affine rectangles: general position");
      declare
         CX  : constant Real := 19.3;
         CY  : constant Real := 15.2;
         LX  : constant Real := 17.1;
         LY  : constant Real := 7.7;
         Rot : constant Real := 0.4;
         A   : constant Ks_Rectangle_Affine :=
           Affine (CX, CY, LX, LY, Rot, 0.0);

         function Margin (I, J : Integer) return Real is
            DX : constant Real := Real (I) - CX;
            DY : constant Real := Real (J) - CY;
            U  : constant Real := DX * EF.Cos (Rot) + DY * EF.Sin (Rot);
            V  : constant Real := -DX * EF.Sin (Rot) + DY * EF.Cos (Rot);
         begin
            return Real'Min (LX / 2.0 - abs U, LY / 2.0 - abs V);
         end Margin;

         R : constant Pixel_Region := Rasterize (Image, A);
      begin
         Check_Pixels_By_Margin (R, W, H, Margin'Access, "rotated 0.4");
         Check_Definition (Image, A, R, "rotated 0.4");

         --  The same rectangle described with the rotation changed by
         --  +/- Pi (angles beyond the (-Pi, Pi] range, and wrapping).
         Check_Same
           (R, Rasterize (Image, Affine (CX, CY, LX, LY, Rot + Pi, 0.0)),
            "rotation + Pi");
         Check_Same
           (R, Rasterize (Image, Affine (CX, CY, LX, LY, Rot - Pi, 0.0)),
            "rotation - Pi");
         Check_Same
           (R, Rasterize
                 (Image, Affine (CX, CY, LX, LY, Rot + 4.0 * Pi, 0.0)),
            "rotation + 4 Pi");
      end;

      declare
         --  A skewed parallelogram given by three corners; inside means
         --  P = O + S * (CXc - O) + T * (CYc - O) with S, T in [0, 1].
         OX  : constant Real := 5.3;
         OY  : constant Real := 4.1;
         AX  : constant Real := 30.2 - OX;
         AY  : constant Real := 8.9 - OY;
         BX  : constant Real := 11.7 - OX;
         BY  : constant Real := 25.6 - OY;
         Det : constant Real := AX * BY - AY * BX;
         P   : Ks_Rectangle_Affine;

         function Margin (I, J : Integer) return Real is
            DX : constant Real := Real (I) - OX;
            DY : constant Real := Real (J) - OY;
            S  : constant Real := (DX * BY - DY * BX) / Det;
            T  : constant Real := (AX * DY - AY * DX) / Det;
         begin
            return Real'Min (Real'Min (S, 1.0 - S), Real'Min (T, 1.0 - T));
         end Margin;
      begin
         P.Set_Origin_Corner_X_Corner_Y (OX, OY, 30.2, 8.9, 11.7, 25.6);
         declare
            R : constant Pixel_Region := Rasterize (Image, P);
         begin
            Check_Pixels_By_Margin (R, W, H, Margin'Access, "skewed");
            Check_Definition (Image, P, R, "skewed");
         end;
      end;

      declare
         --  Rotated so far that most of it leaves the image at the top
         --  left (also checks clipping of a rotated candidate box).
         A : constant Ks_Rectangle_Affine :=
           Affine (2.3, 1.9, 21.4, 5.2, -2.5, 0.0);
         R : constant Pixel_Region := Rasterize (Image, A);
      begin
         Check (not R.Is_Empty, "rotated, partly outside: not empty");
         Check_Definition (Image, A, R, "rotated, partly outside");
      end;
   end Test_Affine_Rectangles;

   ---------------------------------------------------------------------
   --  Polygons
   ---------------------------------------------------------------------

   procedure Test_Polygons is
      Image : constant Ks_Image_8_Grey := Create (W, H);

      type Coordinates is array (Positive range <>) of Real;

      function Polygon (XY : Coordinates) return Ks_Polygon;
      --  The polygon through (XY (1), XY (2)), (XY (3), XY (4)), ...

      function Polygon (XY : Coordinates) return Ks_Polygon is
      begin
         return Result : Ks_Polygon do
            for K in 0 .. XY'Length / 2 - 1 loop
               Result.Add_Vertex
                 (XY (XY'First + 2 * K), XY (XY'First + 2 * K + 1));
            end loop;
         end return;
      end Polygon;

      procedure Lattice_Case
        (P           : Ks_Polygon;
         Expected    : not null access function (I, J : Integer)
                         return Boolean;
         Exp_X, Exp_Y, Exp_W, Exp_H, Exp_Count : Natural;
         Description : String);

      procedure Lattice_Case
        (P           : Ks_Polygon;
         Expected    : not null access function (I, J : Integer)
                         return Boolean;
         Exp_X, Exp_Y, Exp_W, Exp_H, Exp_Count : Natural;
         Description : String)
      is
         R : constant Pixel_Region := Rasterize (Image, P);
      begin
         Check_Bounds
           (R, Exp_X, Exp_Y, Exp_W, Exp_H, Exp_Count, Description);
         Check_Pixels (R, W, H, Expected, Description);
         Check_Definition (Image, P, R, Description);
      end Lattice_Case;

      --  Right triangle (2, 2), (12, 2), (2, 12): 1 + 2 + ... + 11 = 66
      --  lattice points, hypotenuse included.
      function In_Triangle (I, J : Integer) return Boolean is
        (I >= 2 and then J >= 2 and then I + J <= 14);

      --  L shape: [3, 13] x [3, 7] plus [3, 7] x [3, 13]; 55 + 30 = 85.
      function In_L (I, J : Integer) return Boolean is
        ((I in 3 .. 13 and then J in 3 .. 7)
         or else (I in 3 .. 7 and then J in 3 .. 13));

      --  Bow tie with crossing edges at (15, 15): two triangles of 121
      --  points each, sharing the crossing point.
      function In_Bow_Tie (I, J : Integer) return Boolean is
        ((J in 5 .. 15 and then I in J .. 30 - J)
         or else (J in 15 .. 25 and then I in 30 - J .. J));

      --  Two vertices: only the segment from (2, 2) to (8, 5), which
      --  passes through the pixel centres (2, 2), (4, 3), (6, 4), (8, 5).
      function On_Segment (I, J : Integer) return Boolean is
        (I in 2 .. 8 and then (I - 2) mod 2 = 0
         and then J = 2 + (I - 2) / 2);

      function Single (I, J : Integer) return Boolean is
        (I = 7 and then J = 9);

      Empty_Polygon : Ks_Polygon;
   begin
      Section ("polygons");
      Lattice_Case
        (Polygon ([2.0, 2.0, 12.0, 2.0, 2.0, 12.0]), In_Triangle'Access,
         2, 2, 11, 11, 66, "triangle");
      Lattice_Case
        (Polygon ([2.0, 12.0, 12.0, 2.0, 2.0, 2.0]), In_Triangle'Access,
         2, 2, 11, 11, 66, "triangle, clockwise");
      Lattice_Case
        (Polygon ([3.0, 3.0, 13.0, 3.0, 13.0, 7.0, 7.0, 7.0,
                   7.0, 13.0, 3.0, 13.0]),
         In_L'Access, 3, 3, 11, 11, 85, "concave L");
      Lattice_Case
        (Polygon ([5.0, 5.0, 25.0, 5.0, 5.0, 25.0, 25.0, 25.0]),
         In_Bow_Tie'Access, 5, 5, 21, 21, 241, "self-intersecting");
      Lattice_Case
        (Polygon ([2.0, 2.0, 8.0, 5.0]), On_Segment'Access,
         2, 2, 7, 4, 4, "two vertices");
      Lattice_Case
        (Polygon ([7.0, 9.0]), Single'Access, 7, 9, 1, 1, 1, "one vertex");

      Check_Empty (Rasterize (Image, Polygon ([7.5, 9.0])),
                   "one vertex between centres");
      Check_Empty (Rasterize (Image, Empty_Polygon), "no vertices");

      declare
         --  A star-like concave polygon in general position.
         P : constant Ks_Polygon :=
           Polygon ([20.3, 2.2, 24.1, 11.7, 35.6, 12.4, 26.2, 18.3,
                     30.9, 28.1, 20.2, 21.8, 9.4, 27.6, 14.1, 17.9,
                     4.4, 11.3, 16.2, 11.1]);
         R : constant Pixel_Region := Rasterize (Image, P);
      begin
         Check (R.Pixel_Count > 100, "star: plausible size");
         Check_Definition (Image, P, R, "star");
      end;
   end Test_Polygons;

   ---------------------------------------------------------------------
   --  Circular annulus sections
   ---------------------------------------------------------------------

   procedure Test_Annulus_Sections is
      Image : constant Ks_Image_8_Grey := Create (W, H);

      function Section_Of
        (CX, CY, Radius, Start, Span, Scale : Real)
         return Ks_Circular_Annulus_Section;
      function Section_Of
        (CX, CY, Radius, Start, Span, Scale : Real)
         return Ks_Circular_Annulus_Section is
      begin
         return Result : Ks_Circular_Annulus_Section do
            Result.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
              (CX, CY, Radius, Start, Span, Scale);
         end return;
      end Section_Of;

      procedure Lattice_Case
        (S           : Ks_Circular_Annulus_Section;
         Expected    : not null access function (I, J : Integer)
                         return Boolean;
         Description : String);

      procedure Lattice_Case
        (S           : Ks_Circular_Annulus_Section;
         Expected    : not null access function (I, J : Integer)
                         return Boolean;
         Description : String)
      is
         R : constant Pixel_Region := Rasterize (Image, S);
      begin
         Check_Pixels (R, W, H, Expected, Description);
         Check_Definition (Image, S, R, Description);
      end Lattice_Case;

      --  All around the centre (20, 15); DX = I - 20, DY = J - 15.

      function Ring (I, J : Integer; R1, R2 : Natural) return Boolean is
        ((I - 20) ** 2 + (J - 15) ** 2 in R1 .. R2);

      function Quadrant (I, J : Integer) return Boolean is
        (I >= 20 and then J >= 15 and then Ring (I, J, 16, 64));

      function Upper_Quadrant (I, J : Integer) return Boolean is
        (I >= 20 and then J <= 15 and then Ring (I, J, 16, 64));

      function Full_Ring (I, J : Integer) return Boolean is
        (Ring (I, J, 9, 36));

      --  Directions within 45 degrees of -x (the span crosses +/- Pi);
      --  the diagonal boundary rays are included.
      function Left_Wedge (I, J : Integer) return Boolean is
        (I <= 20 and then abs (J - 15) <= 20 - I and then Ring (I, J, 16, 64));

      function Pie (I, J : Integer) return Boolean is
        (I >= 20 and then J >= 15 and then Ring (I, J, 0, 25));
   begin
      Section ("annulus sections");
      Lattice_Case (Section_Of (20.0, 15.0, 4.0, 0.0, Pi / 2.0, 2.0),
                    Quadrant'Access, "quadrant");
      declare
         R : constant Pixel_Region :=
           Rasterize (Image, Section_Of (20.0, 15.0, 4.0, 0.0, Pi / 2.0, 2.0));
      begin
         Check_Bounds (R, 20, 15, 9, 9, R.Pixel_Count, "quadrant bounds");
      end;
      Lattice_Case (Section_Of (20.0, 15.0, 8.0, 0.0, Pi / 2.0, 0.5),
                    Quadrant'Access, "quadrant, radial scale < 1");
      Lattice_Case (Section_Of (20.0, 15.0, 4.0, 0.0, -Pi / 2.0, 2.0),
                    Upper_Quadrant'Access, "negative span");
      Lattice_Case (Section_Of (20.0, 15.0, 4.0, -Pi / 2.0, Pi / 2.0, 2.0),
                    Upper_Quadrant'Access, "negative start");
      Lattice_Case (Section_Of (20.0, 15.0, 3.0, 0.0, 2.0 * Pi, 2.0),
                    Full_Ring'Access, "full ring");
      Lattice_Case (Section_Of (20.0, 15.0, 3.0, 1.0, -7.0, 2.0),
                    Full_Ring'Access, "span beyond -2 Pi");
      Lattice_Case
        (Section_Of (20.0, 15.0, 4.0, 3.0 * Pi / 4.0, Pi / 2.0, 2.0),
         Left_Wedge'Access, "span across +/- Pi");
      Lattice_Case
        (Section_Of (20.0, 15.0, 4.0, -5.0 * Pi / 4.0, Pi / 2.0, 2.0),
         Left_Wedge'Access, "start below -Pi");
      Lattice_Case
        (Section_Of (20.0, 15.0, 4.0, 5.0 * Pi / 4.0, -Pi / 2.0, 2.0),
         Left_Wedge'Access, "start beyond Pi, negative span");
      Lattice_Case (Section_Of (20.0, 15.0, 5.0, 0.0, Pi / 2.0, 0.0),
                    Pie'Access, "pie slice (inner radius 0)");
      declare
         R : constant Pixel_Region :=
           Rasterize (Image, Section_Of (20.0, 15.0, 3.0, 0.0, 2.0 * Pi, 2.0));
      begin
         Check_Bounds (R, 14, 9, 13, 13, R.Pixel_Count, "full ring bounds");
      end;
   end Test_Annulus_Sections;

   ---------------------------------------------------------------------
   --  Regions partly or entirely outside the image
   ---------------------------------------------------------------------

   procedure Test_Outside is
      Image : constant Ks_Image_8_Grey := Create (W, H);
   begin
      Section ("partly outside");
      declare
         R : constant Pixel_Region :=
           Rasterize (Image, Rectangle (-5.5, -3.2, 10.0, 8.0));
      begin
         Check_Bounds (R, 0, 0, 5, 5, 25, "top left rectangle");
      end;
      declare
         R : constant Pixel_Region :=
           Rasterize (Image, Rectangle (35.0, 25.0, 10.0, 10.0));
      begin
         Check_Bounds (R, 35, 25, 5, 5, 25, "bottom right rectangle");
      end;
      declare
         R : constant Pixel_Region :=
           Rasterize (Image, Rectangle (-100.0, 10.0, 1000.0, 2.0));
      begin
         Check_Bounds (R, 0, 10, W, 3, 3 * W, "band across the image");
      end;
      declare
         C : constant Ks_Circle := Circle (0.0, 0.0, 5.0);
         R : constant Pixel_Region := Rasterize (Image, C);
         function Expected (I, J : Integer) return Boolean is
           (I ** 2 + J ** 2 <= 25);
      begin
         --  The quarter disc: 6 + 5 + 5 + 5 + 4 + 1 = 26 points.
         Check_Bounds (R, 0, 0, 6, 6, 26, "circle at the corner");
         Check_Pixels (R, W, H, Expected'Access, "circle at the corner");
         Check_Definition (Image, C, R, "circle at the corner");
      end;
      declare
         C : constant Ks_Circle := Circle (39.0, 29.0, 3.0);
         R : constant Pixel_Region := Rasterize (Image, C);
         function Expected (I, J : Integer) return Boolean is
           ((I - 39) ** 2 + (J - 29) ** 2 <= 9);
      begin
         --  Quarter disc of radius 3: 4 + 3 + 3 + 1 = 11 points.
         Check_Bounds (R, 36, 26, 4, 4, 11, "circle at the far corner");
         Check_Pixels (R, W, H, Expected'Access, "circle at the far corner");
      end;

      Section ("covering the whole image");
      Check_Bounds
        (Rasterize (Image, Rectangle (-1.0E6, -1.0E6, 2.0E6, 2.0E6)),
         0, 0, W, H, W * H, "huge rectangle");
      Check_Bounds
        (Rasterize (Image, Circle (20.0, 15.0, 1000.0)),
         0, 0, W, H, W * H, "huge circle");

      Section ("entirely outside");
      Check_Empty (Rasterize (Image, Rectangle (100.0, 100.0, 10.0, 10.0)),
                   "beyond bottom right");
      Check_Empty (Rasterize (Image, Rectangle (-20.0, -20.0, 10.0, 10.0)),
                   "beyond top left");
      Check_Empty (Rasterize (Image, Rectangle (-20.0, 5.0, 10.0, 5.0)),
                   "left");
      Check_Empty (Rasterize (Image, Rectangle (45.0, 5.0, 10.0, 5.0)),
                   "right");
      Check_Empty (Rasterize (Image, Rectangle (5.0, -20.0, 10.0, 5.0)),
                   "above");
      Check_Empty (Rasterize (Image, Rectangle (5.0, 35.0, 10.0, 5.0)),
                   "below");
      Check_Empty (Rasterize (Image, Rectangle (5.0, 29.6, 10.0, 5.0)),
                   "below, inside the last half pixel");
      Check_Empty (Rasterize (Image, Rectangle (39.6, 5.0, 0.3, 3.0)),
                   "right, inside the last half pixel");
      Check_Empty (Rasterize (Image, Rectangle (-0.6, 5.0, 0.5, 3.0)),
                   "left, inside the first half pixel");
      Check_Empty (Rasterize (Image, Rectangle (1.0E12, 1.0E12, 5.0, 5.0)),
                   "huge positive coordinates");
      Check_Empty
        (Rasterize (Image, Rectangle (-1.0E15, -1.0E15, 5.0, 5.0)),
         "huge negative coordinates");
      Check_Empty (Rasterize (Image, Circle (-30.0, 15.0, 29.0)),
                   "circle left of the image");
      Check_Empty (Rasterize (Image, Circle (-3.0, -3.0, 4.0)),
                   "circle whose box overlaps a corner");
   end Test_Outside;

   ---------------------------------------------------------------------
   --  Coordinate spaces
   ---------------------------------------------------------------------

   procedure Test_Spaces is
      SW : constant := 60;
      SH : constant := 50;

      Fixture_Pose : constant Ks_Transform_2D_Linear :=
        Create_Rigid (Pi / 6.0, 30.0, 20.0);
      --  Maps fixture coordinates to root (= pixel) coordinates.
      Cos_F : constant Real := EF.Cos (Pi / 6.0);
      Sin_F : constant Real := EF.Sin (Pi / 6.0);

      procedure To_Pixel (U, V : Real; X, Y : out Real);
      --  The fixture pose evaluated by hand.

      procedure To_Pixel (U, V : Real; X, Y : out Real) is
      begin
         X := 30.0 + Cos_F * U - Sin_F * V;
         Y := 20.0 + Sin_F * U + Cos_F * V;
      end To_Pixel;

      procedure To_Fixture (X, Y : Real; U, V : out Real);
      --  Its inverse, also by hand.

      procedure To_Fixture (X, Y : Real; U, V : out Real) is
      begin
         U := Cos_F * (X - 30.0) + Sin_F * (Y - 20.0);
         V := -Sin_F * (X - 30.0) + Cos_F * (Y - 20.0);
      end To_Fixture;

      function Fixtured_Image return Ks_Image_8_Grey;
      --  An SW x SH image whose tree holds "@\Fixture" (turned by 30
      --  degrees and moved to (30, 20)), "@\Quarter" (turned by 90
      --  degrees and moved to (25, 10)) and "@\Quarter\Part" (shifted by
      --  (2, 1) within "@\Quarter").

      function Fixtured_Image return Ks_Image_8_Grey is
         Tree : Ks_Coordinate_Space_Tree;
      begin
         return Result : Ks_Image_8_Grey := Create (SW, SH) do
            Tree.Add_Space ("@", "Fixture", Fixture_Pose);
            Tree.Add_Space
              ("@", "Quarter", Create (0.0, -1.0, 1.0, 0.0, 25.0, 10.0));
            Tree.Add_Space
              ("@\Quarter", "Part", Create (1.0, 0.0, 0.0, 1.0, 2.0, 1.0));
            Result.Set_Coordinate_Space_Tree (Tree);
         end return;
      end Fixtured_Image;

      Image : Ks_Image_8_Grey := Fixtured_Image;

      --  Rectangle in "@\Fixture" with sides parallel to the fixture axes.
      FX0 : constant Real := -7.3;
      FY0 : constant Real := -4.1;
      FW  : constant Real := 14.2;
      FH  : constant Real := 8.6;

      function Fixture_Rect_Margin (I, J : Integer) return Real is
         U, V : Real;
      begin
         To_Fixture (Real (I), Real (J), U, V);
         return Real'Min (Real'Min (U - FX0, FX0 + FW - U),
                          Real'Min (V - FY0, FY0 + FH - V));
      end Fixture_Rect_Margin;

      --  Circle in "@\Fixture".
      FCX : constant Real := 3.2;
      FCY : constant Real := -1.7;
      FR  : constant Real := 6.4;

      function Fixture_Circle_Margin (I, J : Integer) return Real is
         U, V : Real;
      begin
         To_Fixture (Real (I), Real (J), U, V);
         return FR - EF.Sqrt ((U - FCX) ** 2 + (V - FCY) ** 2);
      end Fixture_Circle_Margin;

      function In_Quarter_Rect (I, J : Integer) return Boolean is
        (I in 18 .. 22 and then J in 12 .. 18);

   begin
      Section ("spaces: rotated and translated fixture");
      declare
         Rect : constant Ks_Rectangle :=
           Rectangle (FX0, FY0, FW, FH, "@\Fixture");
         R    : constant Pixel_Region := Rasterize (Image, Rect);

         --  The same rectangle mapped into pixel space by hand.
         OX, OY, AX, AY, BX, BY : Real;
         Mapped : Ks_Rectangle_Affine;
      begin
         Check_Pixels_By_Margin
           (R, SW, SH, Fixture_Rect_Margin'Access, "fixture rectangle");
         Check_Definition (Image, Rect, R, "fixture rectangle");

         To_Pixel (FX0, FY0, OX, OY);
         To_Pixel (FX0 + FW, FY0, AX, AY);
         To_Pixel (FX0, FY0 + FH, BX, BY);
         Mapped.Set_Origin_Corner_X_Corner_Y (OX, OY, AX, AY, BX, BY);
         Mapped.Set_Selected_Space_Name ("#");
         Check_Same (R, Rasterize (Image, Mapped),
                     "fixture rectangle = hand-mapped affine rectangle");
      end;

      declare
         C : constant Ks_Circle := Circle (FCX, FCY, FR, "@\Fixture");
         R : constant Pixel_Region := Rasterize (Image, C);
         PX, PY : Real;
      begin
         Check_Pixels_By_Margin
           (R, SW, SH, Fixture_Circle_Margin'Access, "fixture circle");
         Check_Definition (Image, C, R, "fixture circle");
         To_Pixel (FCX, FCY, PX, PY);
         Check_Same (R, Rasterize (Image, Circle (PX, PY, FR, "#")),
                     "fixture circle = hand-mapped circle");
      end;

      declare
         --  A fixture polygon running off the right edge of the image.
         type Coordinates is array (1 .. 4) of Real;
         U : constant Coordinates := [10.2, 41.7, 38.3, 12.9];
         V : constant Coordinates := [-9.4, -2.1, 14.6, 8.8];
         In_Fixture : Ks_Polygon;
         In_Pixels  : Ks_Polygon;
         PX, PY     : Real;
      begin
         for K in 1 .. 4 loop
            In_Fixture.Add_Vertex (U (K), V (K));
            To_Pixel (U (K), V (K), PX, PY);
            In_Pixels.Add_Vertex (PX, PY);
         end loop;
         In_Fixture.Set_Selected_Space_Name ("@\Fixture");
         In_Pixels.Set_Selected_Space_Name ("#");
         declare
            R : constant Pixel_Region := Rasterize (Image, In_Fixture);
         begin
            Check (not R.Is_Empty and then R.X_Min + R.Width = SW,
                   "fixture polygon reaches the right edge");
            Check_Definition (Image, In_Fixture, R, "fixture polygon");
            Check_Same (R, Rasterize (Image, In_Pixels),
                        "fixture polygon = hand-mapped polygon");
         end;
      end;

      Section ("spaces: exact quarter-turn fixture");
      declare
         --  Quarter maps (U, V) to (25 - V, 10 + U), so [2, 8] x [3, 7]
         --  lands on [18, 22] x [12, 18].
         Rect : constant Ks_Rectangle :=
           Rectangle (2.0, 3.0, 6.0, 4.0, "@\Quarter");
         R    : constant Pixel_Region := Rasterize (Image, Rect);
      begin
         Check_Bounds (R, 18, 12, 5, 7, 35, "quarter rectangle");
         Check_Pixels (R, SW, SH, In_Quarter_Rect'Access, "quarter rectangle");
         Check_Definition (Image, Rect, R, "quarter rectangle");
      end;
      declare
         --  Part is Quarter shifted by (2, 1): the same rectangle.
         Rect : constant Ks_Rectangle :=
           Rectangle (0.0, 2.0, 6.0, 4.0, "@\Quarter\Part");
         R    : constant Pixel_Region := Rasterize (Image, Rect);
      begin
         Check_Bounds (R, 18, 12, 5, 7, 35, "nested space");
         Check_Pixels (R, SW, SH, In_Quarter_Rect'Access, "nested space");
      end;

      Section ("spaces: ""."" and ""#""");
      declare
         Rect_Fix : constant Ks_Rectangle :=
           Rectangle (FX0, FY0, FW, FH, "@\Fixture");
         Rect_Dot : constant Ks_Rectangle := Rectangle (FX0, FY0, FW, FH);
         Rect_Px  : constant Ks_Rectangle :=
           Rectangle (2.0, 3.0, 3.0, 2.0, "#");
         Reference : constant Pixel_Region := Rasterize (Image, Rect_Fix);
      begin
         --  Selected space "@" (the default): "." is the root, which is
         --  pixel space here.
         Check_Bounds (Rasterize (Image, Rectangle (2.0, 3.0, 3.0, 2.0)),
                       2, 3, 4, 3, 12, """."" = ""@"" = pixels");

         Image.Set_Selected_Space_Name ("@\Fixture");
         Check_Same (Reference, Rasterize (Image, Rect_Dot),
                     """."" with the fixture selected");
         Check_Bounds (Rasterize (Image, Rect_Px), 2, 3, 4, 3, 12,
                       """#"" ignores the selected space");

         Image.Set_Selected_Space_Name ("#");
         Check_Bounds (Rasterize (Image, Rectangle (2.0, 3.0, 3.0, 2.0)),
                       2, 3, 4, 3, 12, """."" with ""#"" selected");
         Image.Set_Selected_Space_Name ("@");
      end;

      Section ("spaces: pixel-from-root transform");
      declare
         Scaled : Ks_Image_8_Grey := Create (SW, SH);
      begin
         --  Pixel = 2 * root + (1, 1).
         Scaled.Set_Pixel_From_Root_Transform
           (Create (2.0, 0.0, 0.0, 2.0, 1.0, 1.0));
         declare
            --  Root [2, 5] x [3, 5] is pixel [5, 11] x [7, 11].
            Rect_Root : constant Ks_Rectangle :=
              Rectangle (2.0, 3.0, 3.0, 2.0, "@");
            Rect_Dot  : constant Ks_Rectangle :=
              Rectangle (2.0, 3.0, 3.0, 2.0);
            Rect_Px   : constant Ks_Rectangle :=
              Rectangle (2.0, 3.0, 3.0, 2.0, "#");
            R : constant Pixel_Region := Rasterize (Scaled, Rect_Root);
         begin
            Check_Bounds (R, 5, 7, 7, 5, 35, "root rectangle, scaled");
            Check_Definition (Scaled, Rect_Root, R, "root rectangle, scaled");
            Check_Same (R, Rasterize (Scaled, Rect_Dot),
                        """."" = ""@"", scaled");
            Check_Bounds (Rasterize (Scaled, Rect_Px), 2, 3, 4, 3, 12,
                          """#"", scaled");
         end;
         declare
            --  Half a root unit is one pixel: a root circle of radius 2.5
            --  around (9.5, 7) is a pixel circle of radius 5 around
            --  (20, 15).
            C : constant Ks_Circle := Circle (9.5, 7.0, 2.5, "@");
            R : constant Pixel_Region := Rasterize (Scaled, C);
            function Expected (I, J : Integer) return Boolean is
              ((I - 20) ** 2 + (J - 15) ** 2 <= 25);
         begin
            Check_Bounds (R, 15, 10, 11, 11, 81, "root circle, scaled");
            Check_Pixels (R, SW, SH, Expected'Access, "root circle, scaled");
         end;
      end;

      Section ("spaces: rounding at the edge of the candidate box");
      declare
         Sevenfold : Ks_Image_8_Grey := Create (SW, SH);
      begin
         --  With pixel = 7 * root, the root corner 29 / 7 maps to
         --  29.000000000000004, just past the pixel centre 29, whose own
         --  image 29 * (1 / 7) is on the rectangle's edge up to rounding.
         --  Column and row 29 must still be included.
         Sevenfold.Set_Pixel_From_Root_Transform
           (Create (7.0, 0.0, 0.0, 7.0, 0.0, 0.0));
         declare
            Rect : constant Ks_Rectangle :=
              Rectangle (29.0 / 7.0, 29.0 / 7.0, 5.0 / 7.0, 3.0 / 7.0, "@");
            R    : constant Pixel_Region := Rasterize (Sevenfold, Rect);
            Corner_X, Corner_Y : Real;
         begin
            Sevenfold.Get_Transform ("#", "@").Map_Point
              (Rect.X, Rect.Y, Corner_X, Corner_Y);
            Check (Corner_X > 29.0 and then Corner_Y > 29.0,
                   "sevenfold: the corner maps just past 29");
            Check_Bounds (R, 29, 29, 6, 4, 24, "sevenfold rectangle");
            Check_Definition (Sevenfold, Rect, R, "sevenfold rectangle");
         end;
      end;

      Section ("spaces: unknown names");
      declare
         procedure Missing is
         begin
            Consume (Rasterize (Image, Rectangle (0.0, 0.0, 5.0, 5.0,
                                                  "@\Missing")));
         end Missing;
         procedure No_Root is
         begin
            Consume (Rasterize (Image, Rectangle (0.0, 0.0, 5.0, 5.0,
                                                  "Fixture")));
         end No_Root;
         procedure Empty_Name is
         begin
            Consume (Rasterize (Image, Rectangle (0.0, 0.0, 5.0, 5.0, "")));
         end Empty_Name;
         procedure Trailing is
         begin
            Consume (Rasterize (Image, Rectangle (0.0, 0.0, 5.0, 5.0,
                                                  "@\Fixture\")));
         end Trailing;
         procedure Other_Image is
            Plain : constant Ks_Image_8_Grey := Create (SW, SH);
         begin
            Consume (Rasterize (Plain, Rectangle (0.0, 0.0, 5.0, 5.0,
                                                  "@\Fixture")));
         end Other_Image;

         Bad_Space : constant Ada.Exceptions.Exception_Id :=
           Ks_Image_Bad_Selected_Space_Name_Exception'Identity;
         procedure Check_Missing is new Check_Raises_Exactly
           (Missing, Bad_Space);
         procedure Check_No_Root is new Check_Raises_Exactly
           (No_Root, Bad_Space);
         procedure Check_Empty_Name is new Check_Raises_Exactly
           (Empty_Name, Bad_Space);
         procedure Check_Trailing is new Check_Raises_Exactly
           (Trailing, Bad_Space);
         procedure Check_Other_Image is new Check_Raises_Exactly
           (Other_Image, Bad_Space);
      begin
         Check_Missing ("unknown child space");
         Check_No_Root ("name without the root");
         Check_Empty_Name ("empty name");
         Check_Trailing ("trailing separator");
         Check_Other_Image ("space of another image's tree");
      end;
   end Test_Spaces;

   ---------------------------------------------------------------------
   --  Unallocated images
   ---------------------------------------------------------------------

   procedure Test_Unallocated is
      Empty_8      : Ks_Image_8_Grey;
      Empty_16     : Ks_Image_16_Grey;
      Empty_Colour : Ks_Image_24_Planar_Color;

      procedure Whole_8 is
      begin
         Consume (Whole_Image (Empty_8));
      end Whole_8;

      procedure Whole_16 is
      begin
         Consume (Whole_Image (Empty_16));
      end Whole_16;

      procedure Rasterize_Colour is
      begin
         Consume (Rasterize (Empty_Colour, Circle (5.0, 5.0, 3.0)));
      end Rasterize_Colour;

      procedure Rasterize_8 is
      begin
         Consume (Rasterize (Empty_8, Rectangle (0.0, 0.0, 5.0, 5.0)));
      end Rasterize_8;

      procedure Rasterize_Bad_Space is
      begin
         Consume
           (Rasterize (Empty_8, Rectangle (0.0, 0.0, 5.0, 5.0, "@\Nope")));
      end Rasterize_Bad_Space;

      procedure Empty_Holder is
      begin
         Consume (Rasterize (Empty_8, RH.Empty_Holder));
      end Empty_Holder;

      procedure Full_Holder is
      begin
         Consume (Rasterize (Empty_8, RH.To_Holder (Circle (5.0, 5.0, 3.0))));
      end Full_Holder;

      No_Pixels : constant Ada.Exceptions.Exception_Id :=
        Ks_Image_No_Pixels_Exception'Identity;
      procedure Check_Whole_8 is new Check_Raises_Exactly
        (Whole_8, No_Pixels);
      procedure Check_Whole_16 is new Check_Raises_Exactly
        (Whole_16, No_Pixels);
      procedure Check_Rasterize_Colour is new Check_Raises_Exactly
        (Rasterize_Colour, No_Pixels);
      procedure Check_Rasterize_8 is new Check_Raises_Exactly
        (Rasterize_8, No_Pixels);
      procedure Check_Rasterize_Bad_Space is new Check_Raises_Exactly
        (Rasterize_Bad_Space, No_Pixels);
      procedure Check_Empty_Holder is new Check_Raises_Exactly
        (Empty_Holder, No_Pixels);
      procedure Check_Full_Holder is new Check_Raises_Exactly
        (Full_Holder, No_Pixels);
   begin
      Section ("unallocated images");
      Check_Whole_8 ("Whole_Image, 8-bit");
      Check_Whole_16 ("Whole_Image, 16-bit");
      Check_Rasterize_Colour ("Rasterize, colour");
      Check_Rasterize_8 ("Rasterize, 8-bit");
      Check_Rasterize_Bad_Space ("Rasterize, unknown space too");
      Check_Empty_Holder ("Rasterize, empty holder");
      Check_Full_Holder ("Rasterize, holder with a circle");
   end Test_Unallocated;

   ---------------------------------------------------------------------
   --  Holders
   ---------------------------------------------------------------------

   procedure Test_Holders is
      Image  : constant Ks_Image_8_Grey := Create (W, H);
      Holder : RH.Holder;
      C      : constant Ks_Circle := Circle (20.0, 15.0, 5.0);
   begin
      Section ("region holders");
      Check_Same (Whole_Image (Image), Rasterize (Image, Holder),
                  "empty holder = whole image");
      Check_Bounds (Rasterize (Image, Holder), 0, 0, W, H, W * H,
                    "empty holder bounds");

      Holder := RH.To_Holder (C);
      Check_Same (Rasterize (Image, C), Rasterize (Image, Holder),
                  "holder with a circle");
      Check_Bounds (Rasterize (Image, Holder), 15, 10, 11, 11, 81,
                    "holder with a circle: bounds");

      Holder.Replace_Element (Rectangle (2.0, 3.0, 5.0, 4.0));
      Check_Bounds (Rasterize (Image, Holder), 2, 3, 6, 5, 30,
                    "holder with a rectangle");

      Holder.Replace_Element (Rectangle (500.0, 500.0, 5.0, 4.0));
      Check_Empty (Rasterize (Image, Holder), "holder, region outside");

      Holder.Clear;
      Check_Bounds (Rasterize (Image, Holder), 0, 0, W, H, W * H,
                    "cleared holder = whole image");

      declare
         procedure Bad_Space is
            Bad : constant RH.Holder :=
              RH.To_Holder (Rectangle (0.0, 0.0, 5.0, 5.0, "@\Nope"));
         begin
            Consume (Rasterize (Image, Bad));
         end Bad_Space;
         procedure Check_Bad_Space is new Check_Raises_Exactly
           (Bad_Space, Ks_Image_Bad_Selected_Space_Name_Exception'Identity);
      begin
         Check_Bad_Space ("holder, unknown space");
      end;
   end Test_Holders;

   ---------------------------------------------------------------------
   --  Copying
   ---------------------------------------------------------------------

   procedure Test_Copies is
      Image : constant Ks_Image_8_Grey := Create (W, H);

      function In_Disc (I, J : Integer) return Boolean is
        ((I - 20) ** 2 + (J - 15) ** 2 <= 25);

      function In_Rect (I, J : Integer) return Boolean is
        (I in 2 .. 7 and then J in 3 .. 7);

      function All_Pixels (I, J : Integer) return Boolean is
        (I in 0 .. W - 1 and then J in 0 .. H - 1);

      procedure Assign (Target : out Pixel_Region; Source : Pixel_Region);
      --  Target := Source, in a separate call so that both may name the
      --  same object.

      procedure Assign (Target : out Pixel_Region; Source : Pixel_Region) is
      begin
         Target := Source;
      end Assign;

      Copy, Copy_Of_Whole, Copy_Of_Empty : Pixel_Region;
   begin
      Section ("copies");
      declare
         Original : constant Pixel_Region :=
           Rasterize (Image, Circle (20.0, 15.0, 5.0));
         Whole    : constant Pixel_Region := Whole_Image (Image);
         Nothing  : constant Pixel_Region :=
           Rasterize (Image, Circle (500.0, 15.0, 5.0));
      begin
         Copy := Original;
         Copy_Of_Whole := Whole;
         Copy_Of_Empty := Nothing;
      end;
      --  The originals are finalized now; the copies must stand alone.
      Check_Pixels (Copy, W, H, In_Disc'Access, "copy outlives original");
      Check_Pixels (Copy_Of_Whole, W, H, All_Pixels'Access,
                    "copy of whole image");
      Check_Empty (Copy_Of_Empty, "copy of empty region");

      declare
         Source : Pixel_Region := Rasterize (Image, Circle (20.0, 15.0, 5.0));
         Second : Pixel_Region;
      begin
         Second := Source;
         Source := Rasterize (Image, Rectangle (2.0, 3.0, 5.0, 4.0));
         Check_Pixels (Second, W, H, In_Disc'Access,
                       "copy unchanged by reassigning the source");
         Check_Pixels (Source, W, H, In_Rect'Access,
                       "reassigned source");
         Source := Second;
         Second := Rasterize (Image, Circle (500.0, 15.0, 5.0));
         Check_Pixels (Source, W, H, In_Disc'Access, "copied back");
         Check_Empty (Second, "overwritten by an empty region");

         Assign (Source, Source);
         Check_Pixels (Source, W, H, In_Disc'Access, "self-assignment");
      end;

      declare
         type Region_Array is array (1 .. 3) of Pixel_Region;
         Regions : Region_Array;
         Copies  : Region_Array;
      begin
         Regions (1) := Rasterize (Image, Circle (20.0, 15.0, 5.0));
         Regions (2) := Whole_Image (Image);
         Regions (3) := Rasterize (Image, Rectangle (2.0, 3.0, 5.0, 4.0));
         Copies := Regions;
         Regions := [others => Rasterize (Image, Circle (500.0, 0.0, 1.0))];
         Check_Pixels (Copies (1), W, H, In_Disc'Access, "array copy 1");
         Check_Pixels (Copies (2), W, H, All_Pixels'Access, "array copy 2");
         Check_Pixels (Copies (3), W, H, In_Rect'Access, "array copy 3");
         Check_Empty (Regions (2), "array overwritten");
      end;

      --  Many short-lived regions (exercises finalization repeatedly).
      declare
         Total : Natural := 0;
      begin
         for K in 1 .. 500 loop
            declare
               R : constant Pixel_Region :=
                 Rasterize (Image, Circle (20.0, 15.0, Real (K mod 7)));
               Kept : constant Pixel_Region := R;
            begin
               Total := Total + Kept.Pixel_Count;
            end;
         end loop;
         --  Radii 0 .. 6 have 1, 5, 13, 29, 49, 81, 113 lattice points;
         --  K = 1 .. 500 visits radius K mod 7.
         declare
            Per_Radius : constant array (0 .. 6) of Natural :=
              [1, 5, 13, 29, 49, 81, 113];
            Expected   : Natural := 0;
         begin
            for K in 1 .. 500 loop
               Expected := Expected + Per_Radius (K mod 7);
            end loop;
            Check (Total = Expected,
                   "repeated rasterisation: total" & Img (Total)
                   & ", expected" & Img (Expected));
         end;
      end;
   end Test_Copies;

   ---------------------------------------------------------------------
   --  Other image types and a large image
   ---------------------------------------------------------------------

   procedure Test_Image_Types is
      Image_8  : constant Ks_Image_8_Grey := Create (W, H);
      Image_16 : constant Ks_Image_16_Grey := Create (W, H);
      Colour   : constant Ks_Image_24_Planar_Color := Create (W, H);
      C        : constant Ks_Circle := Circle (20.5, 14.25, 7.3);
      Ref      : constant Pixel_Region := Rasterize (Image_8, C);
   begin
      Section ("other image types");
      Check_Same (Ref, Rasterize (Image_16, C), "16-bit image");
      Check_Same (Ref, Rasterize (Colour, C), "colour image");

      Section ("large image");
      declare
         LW : constant := 1200;
         LH : constant := 900;
         Large : constant Ks_Image_8_Grey := Create (LW, LH);
         CX : constant Real := 600.37;
         CY : constant Real := 450.81;
         Radius : constant Real := 431.3;
         LC : constant Ks_Circle := Circle (CX, CY, Radius);
         R  : constant Pixel_Region := Rasterize (Large, LC);
         function Margin (I, J : Integer) return Real is
           (Radius - EF.Sqrt ((Real (I) - CX) ** 2 + (Real (J) - CY) ** 2));
      begin
         Check_Pixels_By_Margin (R, LW, LH, Margin'Access, "large circle");
         Check_Near (Real (R.Pixel_Count), Pi * Radius ** 2,
                     4.0 * Radius, "large circle: count near the area");
         Check_Bounds (Whole_Image (Large), 0, 0, LW, LH, LW * LH,
                       "large whole image");
      end;
   end Test_Image_Types;

   ---------------------------------------------------------------------
   --  Regions far from the origin, and regions whose boundary slack is
   --  more than half a pixel
   ---------------------------------------------------------------------

   procedure Test_Large_Coordinates is
      LW : constant := 60;
      LH : constant := 40;

      Offset : constant Real := 1.0E9;
      --  Rows of a line-scan web: root y = pixel y + Offset.

      function Line_Scan_Image return Ks_Image_8_Grey;

      function Line_Scan_Image return Ks_Image_8_Grey is
      begin
         return Result : Ks_Image_8_Grey := Create (LW, LH) do
            Result.Set_Pixel_From_Root_Transform
              (Create (1.0, 0.0, 0.0, 1.0, 0.0, -Offset));
         end return;
      end Line_Scan_Image;

      Line_Scan : constant Ks_Image_8_Grey := Line_Scan_Image;
      Plain     : constant Ks_Image_8_Grey := Create (LW, LH);

      function In_Disc (I, J : Integer) return Boolean is
        ((I - 30) ** 2 + (J - 20) ** 2 <= 144);

      function In_Rect (I, J : Integer) return Boolean is
        (I in 10 .. 30 and then J in 10 .. 25);

      procedure Compare
        (Far, Near : Ks_Region'Class; Label : String);
      --  Far (in "@" of Line_Scan) is Near (on Plain) moved down by
      --  Offset: both must give the same pixels, and Far its definition.

      procedure Compare
        (Far, Near : Ks_Region'Class; Label : String)
      is
         R_Far  : constant Pixel_Region := Rasterize (Line_Scan, Far);
         R_Near : constant Pixel_Region := Rasterize (Plain, Near);
      begin
         Check (R_Near.Pixel_Count > 100, Label & ": covers pixels");
         Check_Same (R_Near, R_Far, Label & ": same pixels as at the origin");
         Check_Definition (Line_Scan, Far, R_Far, Label);
      end Compare;

      procedure Huge
        (Image : Ks_Image'Class; Region : Ks_Region'Class;
         Exp_X_Min, Exp_X_Last : Natural; Label : String;
         Pixels_Per_Unit : Real := 1.0);
      --  A region whose boundary slack is more than half a pixel: the
      --  result must still be its definition, with the given columns.

      procedure Huge
        (Image : Ks_Image'Class; Region : Ks_Region'Class;
         Exp_X_Min, Exp_X_Last : Natural; Label : String;
         Pixels_Per_Unit : Real := 1.0)
      is
         R     : constant Pixel_Region := Rasterize (Image, Region);
         Slack : constant Real := Region.Boundary_Slack * Pixels_Per_Unit;
      begin
         Check (Slack > 0.5,
                Label & ": slack" & Real'Image (Slack)
                & " pixels is above half a pixel");
         Check_Definition (Image, Region, R, Label);
         Check (R.X_Min = Exp_X_Min
                  and then R.X_Min + R.Width - 1 = Exp_X_Last,
                Label & ": columns" & Img (R.X_Min) & " .."
                & Img (R.X_Min + R.Width - 1) & ", expected"
                & Img (Exp_X_Min) & " .." & Img (Exp_X_Last));
      end Huge;

   begin
      Section ("large coordinates: line-scan rows near 1E9");
      declare
         C : constant Ks_Circle := Circle (30.0, Offset + 20.0, 12.0, "@");
         R : constant Pixel_Region := Rasterize (Line_Scan, C);
      begin
         Check_Bounds (R, 18, 8, 25, 25, 441, "line-scan circle");
         Check_Pixels (R, LW, LH, In_Disc'Access, "line-scan circle");
         Check_Definition (Line_Scan, C, R, "line-scan circle");
      end;
      declare
         Rect : constant Ks_Rectangle :=
           Rectangle (10.0, Offset + 10.0, 20.0, 15.0, "@");
         R    : constant Pixel_Region := Rasterize (Line_Scan, Rect);
      begin
         Check_Bounds (R, 10, 10, 21, 16, 336, "line-scan rectangle");
         Check_Pixels (R, LW, LH, In_Rect'Access, "line-scan rectangle");
         Check_Definition (Line_Scan, Rect, R, "line-scan rectangle");
      end;
      declare
         Nano : Ks_Image_8_Grey := Create (LW, LH);
      begin
         --  Nanometre pixels, root space in metres.
         Nano.Set_Pixel_From_Root_Transform
           (Create (1.0E9, 0.0, 0.0, 1.0E9, 0.0, 0.0));
         declare
            C : constant Ks_Circle :=
              Circle (30.0E-9, 20.0E-9, 12.0E-9, "@");
            R : constant Pixel_Region := Rasterize (Nano, C);
         begin
            Check_Bounds (R, 18, 8, 25, 25, 441, "nanometre circle");
            Check_Pixels (R, LW, LH, In_Disc'Access, "nanometre circle");
            Check_Definition (Nano, C, R, "nanometre circle");
         end;
      end;

      Section ("large coordinates: every region type at 1E9");
      --  All coordinates are multiples of 1/64, so they are exact at 1E9
      --  too and both regions have exactly the same geometry.
      declare
         Far_Rect, Near_Rect : Ks_Rectangle;
      begin
         Far_Rect := Rectangle (10.25, Offset + 10.75, 20.5, 15.25, "@");
         Near_Rect := Rectangle (10.25, 10.75, 20.5, 15.25);
         Compare (Far_Rect, Near_Rect, "rectangle");
      end;
      declare
         Far_Affine, Near_Affine : Ks_Rectangle_Affine;
      begin
         Far_Affine.Set_Center_Lengths_Rotation_Skew
           (31.25, Offset + 19.75, 30.5, 14.625, 0.37, 0.21);
         Far_Affine.Set_Selected_Space_Name ("@");
         Near_Affine.Set_Center_Lengths_Rotation_Skew
           (31.25, 19.75, 30.5, 14.625, 0.37, 0.21);
         Compare (Far_Affine, Near_Affine, "affine rectangle");
      end;
      Compare (Circle (30.375, Offset + 19.625, 11.875, "@"),
               Circle (30.375, 19.625, 11.875), "circle");
      declare
         Far_Ellipse, Near_Ellipse : Ks_Ellipse;
      begin
         Far_Ellipse.Set_Center_XY_Radius_XY_Rotation
           (29.625, Offset + 20.375, 22.25, 9.75, -0.6);
         Far_Ellipse.Set_Selected_Space_Name ("@");
         Near_Ellipse.Set_Center_XY_Radius_XY_Rotation
           (29.625, 20.375, 22.25, 9.75, -0.6);
         Compare (Far_Ellipse, Near_Ellipse, "ellipse");
      end;
      declare
         type Coordinates is array (1 .. 4) of Real;
         X : constant Coordinates := [5.25, 52.75, 40.25, 12.75];
         Y : constant Coordinates := [3.125, 8.875, 36.375, 30.625];
         Far_Polygon, Near_Polygon : Ks_Polygon;
      begin
         for K in Coordinates'Range loop
            Far_Polygon.Add_Vertex (X (K), Offset + Y (K));
            Near_Polygon.Add_Vertex (X (K), Y (K));
         end loop;
         Far_Polygon.Set_Selected_Space_Name ("@");
         Compare (Far_Polygon, Near_Polygon, "polygon");
      end;
      declare
         Far_Section, Near_Section : Ks_Circular_Annulus_Section;
      begin
         Far_Section.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
           (30.25, Offset + 20.5, 9.75, 0.4, 4.1, 1.6);
         Far_Section.Set_Selected_Space_Name ("@");
         Near_Section.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
           (30.25, 20.5, 9.75, 0.4, 4.1, 1.6);
         Compare (Far_Section, Near_Section, "annulus section");
      end;

      Section ("regions whose boundary slack exceeds half a pixel");
      --  Regions about 1E9 pixels in size whose edge crosses the image:
      --  Contains_Point accepts pixel centres up to its slack (1E-9 of the
      --  size, here 1 to 4 pixels) beyond the edge, and Rasterize must
      --  test those pixels too. The edge is at x = 5 (x = 30 for the
      --  section, whose region lies left of it).
      Huge (Plain, Circle (1.0E9 + 5.0, 15.0, 1.0E9), 4, LW - 1, "circle");
      declare
         Nano : Ks_Image_8_Grey := Create (LW, LH);
      begin
         --  The same circle with nanometre pixels and a radius of 1 m.
         Nano.Set_Pixel_From_Root_Transform
           (Create (1.0E9, 0.0, 0.0, 1.0E9, 0.0, 0.0));
         Huge (Nano, Circle (1.0 + 5.0E-9, 15.0E-9, 1.0, "@"), 4, LW - 1,
               "metre circle, nanometre pixels", Pixels_Per_Unit => 1.0E9);
      end;
      Huge (Plain, Rectangle (5.0, -1.0E9, 2.0E9, 2.0E9), 1, LW - 1,
            "rectangle");
      declare
         E : Ks_Ellipse;
      begin
         E.Set_Center_XY_Radius_XY_Rotation
           (1.0E9 + 5.0, 15.0, 1.0E9, 0.5E9, 0.0);
         Huge (Plain, E, 4, LW - 1, "ellipse");
      end;
      declare
         A : Ks_Rectangle_Affine;
      begin
         A.Set_Origin_Lengths_Rotation_Skew
           (5.0, -1.0E9, 2.0E9, 2.0E9, 0.0, 0.0);
         Huge (Plain, A, 1, LW - 1, "affine rectangle");
      end;
      declare
         P : Ks_Polygon;
      begin
         P.Add_Vertex (5.0, -1.0E9);
         P.Add_Vertex (2.0E9, -1.0E9);
         P.Add_Vertex (2.0E9, 1.0E9);
         P.Add_Vertex (5.0, 1.0E9);
         Huge (Plain, P, 1, LW - 1, "polygon");
      end;
      declare
         S : Ks_Circular_Annulus_Section;
      begin
         S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
           (1.0E9 + 5.0, 15.0, 1.0E9, 0.0, 2.0 * Pi, 0.5);
         Huge (Plain, S, 4, LW - 1, "full annulus");
         --  A quarter section hanging down from far above the image: its
         --  start edge is the line x = 30, and the angular slack (an arc
         --  of about 2 pixels) reaches across it.
         S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
           (30.0, -1.0E9, 0.5E9, Pi / 2.0, Pi / 2.0, 4.0);
         Huge (Plain, S, 0, 32, "annulus section");
      end;
   end Test_Large_Coordinates;

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   procedure Test_Streams is
      package SU renames Ada.Streams.Storage.Unbounded;
      use type Ada.Streams.Stream_Element_Count;
      use type Interfaces.Unsigned_32;

      Image : constant Ks_Image_8_Grey := Create (W, H);

      Format : constant Interfaces.Unsigned_32 := 16#4B53_5247#;
      --  The format code of a stored Pixel_Region.

      function In_Disc (I, J : Integer) return Boolean is
        ((I - 20) ** 2 + (J - 15) ** 2 <= 25);

      procedure Put
        (S : not null access Ada.Streams.Root_Stream_Type'Class;
         V : Interfaces.Unsigned_32);
      --  Writes V as four stream elements, least significant first.

      procedure Put
        (S : not null access Ada.Streams.Root_Stream_Type'Class;
         V : Interfaces.Unsigned_32)
      is
         B    : Ada.Streams.Stream_Element_Array (1 .. 4);
         Rest : Interfaces.Unsigned_32 := V;
      begin
         for K in B'Range loop
            B (K) := Ada.Streams.Stream_Element (Rest and 16#FF#);
            Rest := Interfaces.Shift_Right (Rest, 8);
         end loop;
         Ada.Streams.Write (S.all, B);
      end Put;

      procedure Put_Header
        (S : not null access Ada.Streams.Root_Stream_Type'Class;
         Code, X_Min, Y_Min, Width, Height, Count : Interfaces.Unsigned_32);

      procedure Put_Header
        (S : not null access Ada.Streams.Root_Stream_Type'Class;
         Code, X_Min, Y_Min, Width, Height, Count : Interfaces.Unsigned_32)
      is
      begin
         Put (S, Code);
         Put (S, X_Min);
         Put (S, Y_Min);
         Put (S, Width);
         Put (S, Height);
         Put (S, Count);
      end Put_Header;

      procedure Round_Trip (Original : Pixel_Region; Label : String);
      --  'Write then 'Read into a region that already holds pixels.

      procedure Round_Trip (Original : Pixel_Region; Label : String) is
         S      : aliased SU.Stream_Type;
         Target : Pixel_Region :=
           Rasterize (Image, Circle (10.0, 10.0, 4.0));
      begin
         Pixel_Region'Write (S'Access, Original);
         Check (S.Element_Count
                  = 24 + (if Original.Pixel_Count = 0
                            or else Original.Pixel_Count
                                      = Original.Width * Original.Height
                          then 0
                          else Ada.Streams.Stream_Element_Count
                                 (Original.Width * Original.Height)),
                Label & ": stored by value (" & S.Element_Count'Image
                & " elements)");
         Pixel_Region'Read (S'Access, Target);
         Check_Same (Original, Target, Label & ": read back");
         Check (S.Element_Count = 0, Label & ": the whole record is read");
      end Round_Trip;

      Disc  : constant Pixel_Region :=
        Rasterize (Image, Circle (20.0, 15.0, 5.0));
      Ring  : Ks_Circular_Annulus_Section;

      type Corrupt_Case is
        (Wrong_Format, Short_Header, Empty_With_Bounds, Zero_Width,
         Size_Overflow, Past_Natural_Last, Count_Too_Large,
         Number_Too_Large, Bad_Element, Count_Mismatch, Loose_Bounds,
         Truncated_Pixels, Huge_And_Truncated);

      Current : Corrupt_Case := Wrong_Format;
      Target  : Pixel_Region;

      procedure Read_Corrupt is
         S : aliased SU.Stream_Type;

         procedure Elements (List : Ada.Streams.Stream_Element_Array) is
         begin
            S.Write (List);
         end Elements;
      begin
         case Current is
            when Wrong_Format =>
               Put_Header (S'Access, 16#DEAD_BEEF#, 0, 0, 0, 0, 0);
            when Short_Header =>
               Put (S'Access, Format);
               Put (S'Access, 0);
               Elements ([0, 0]);
            when Empty_With_Bounds =>
               Put_Header (S'Access, Format, 1, 0, 0, 0, 0);
            when Zero_Width =>
               Put_Header (S'Access, Format, 0, 0, 0, 5, 3);
            when Size_Overflow =>
               Put_Header (S'Access, Format, 0, 0, 65_536, 65_536, 5);
            when Past_Natural_Last =>
               Put_Header (S'Access, Format,
                           Interfaces.Unsigned_32 (Natural'Last), 0, 2, 1,
                           2);
            when Count_Too_Large =>
               Put_Header (S'Access, Format, 0, 0, 2, 2, 5);
            when Number_Too_Large =>
               Put_Header (S'Access, Format, 16#8000_0000#, 0, 1, 1, 1);
            when Bad_Element =>
               Put_Header (S'Access, Format, 0, 0, 2, 2, 2);
               Elements ([1, 2, 0, 1]);
            when Count_Mismatch =>
               Put_Header (S'Access, Format, 0, 0, 2, 2, 3);
               Elements ([1, 0, 0, 1]);
            when Loose_Bounds =>
               --  The first row is empty: the bounds are not the tight
               --  ones.
               Put_Header (S'Access, Format, 0, 0, 3, 3, 2);
               Elements ([0, 0, 0, 1, 0, 0, 0, 0, 1]);
            when Truncated_Pixels =>
               Put_Header (S'Access, Format, 0, 0, 3, 3, 2);
               Elements ([1, 0, 0, 0]);
            when Huge_And_Truncated =>
               --  About 2.1E9 pixels claimed, none present.
               Put_Header (S'Access, Format, 0, 0, 46_000, 46_000, 1);
         end case;
         Pixel_Region'Read (S'Access, Target);
      end Read_Corrupt;

      procedure Check_Corrupt is new Check_Raises_Exactly
        (Read_Corrupt, Ks_Image_File_Exception'Identity);

   begin
      Section ("streams: round trips by value");
      Ring.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (20.0, 15.0, 6.0, 0.5, 4.0, 1.7);
      Round_Trip (Disc, "disc (flags)");
      Round_Trip (Whole_Image (Image), "whole image");
      Round_Trip (Rasterize (Image, Rectangle (2.0, 3.0, 5.0, 4.0)),
                  "offset rectangle");
      Round_Trip (Rasterize (Image, Ring), "annulus section");
      Round_Trip (Rasterize (Image, Circle (500.0, 0.0, 1.0)), "empty");

      --  The copy read back owns its pixels: it outlives the original,
      --  and the stream can outlive both.
      declare
         S    : aliased SU.Stream_Type;
         Copy : Pixel_Region;
      begin
         declare
            Original : constant Pixel_Region :=
              Rasterize (Image, Circle (20.0, 15.0, 5.0));
         begin
            Pixel_Region'Write (S'Access, Original);
         end;
         for K in 1 .. 50 loop
            Consume (Rasterize (Image, Circle (20.0, 15.0, Real (K mod 9))));
         end loop;
         Pixel_Region'Read (S'Access, Copy);
         declare
            Original : constant Pixel_Region :=
              Rasterize (Image, Circle (20.0, 15.0, 5.0));
            Second   : Pixel_Region;
         begin
            Pixel_Region'Write (S'Access, Original);
            Pixel_Region'Read (S'Access, Second);
            Copy := Second;
         end;
         for K in 1 .. 50 loop
            Consume (Rasterize (Image, Circle (20.0, 15.0, Real (K mod 9))));
         end loop;
         Check_Pixels (Copy, W, H, In_Disc'Access,
                       "read copy outlives the original");
      end;

      --  'Output / 'Input and the class-wide forms.
      declare
         S : aliased SU.Stream_Type;
      begin
         Pixel_Region'Output (S'Access, Disc);
         declare
            Copy : constant Pixel_Region := Pixel_Region'Input (S'Access);
         begin
            Check_Same (Disc, Copy, "'Output / 'Input");
         end;
         Pixel_Region'Class'Output (S'Access, Disc);
         declare
            Copy : constant Pixel_Region'Class :=
              Pixel_Region'Class'Input (S'Access);
         begin
            Check_Same (Disc, Pixel_Region (Copy),
                        "'Class'Output / 'Class'Input");
         end;
      end;

      --  The documented layout, written by hand.
      declare
         S : aliased SU.Stream_Type;
         R : Pixel_Region;
      begin
         Put_Header (S'Access, Format, 4, 5, 2, 2, 3);
         S.Write ([1, 1, 0, 1]);
         Pixel_Region'Read (S'Access, R);
         Check_Bounds (R, 4, 5, 2, 2, 3, "hand-written region");
         Check (R.Contains (4, 5) and then R.Contains (5, 5)
                  and then not R.Contains (4, 6) and then R.Contains (5, 6),
                "hand-written region: pixels row by row");
         Put_Header (S'Access, Format, 7, 8, 3, 2, 6);
         Pixel_Region'Read (S'Access, R);
         Check_Bounds (R, 7, 8, 3, 2, 6, "hand-written full rectangle");
         Check (S.Element_Count = 0, "a full rectangle has no pixel elements");
      end;

      Section ("streams: malformed input");
      for C in Corrupt_Case loop
         Current := C;
         Target := Disc;
         Check_Corrupt (Corrupt_Case'Image (C) & " is rejected");
         Check_Same (Disc, Target,
                     Corrupt_Case'Image (C) & ": the target is unchanged");
      end loop;
   end Test_Streams;

   ---------------------------------------------------------------------
   --  Restriction by an image mask
   ---------------------------------------------------------------------

   procedure Test_Masks is
      Image : constant Ks_Image_8_Grey := Create (W, H);
      Whole : constant Pixel_Region := Whole_Image (Image);
      Box   : constant Pixel_Region :=
        Rasterize (Image, Rectangle (5.0, 4.0, 19.0, 13.0, "#"));
      --  Pixel centres 5 .. 24 by 4 .. 17: a full rectangle of 20 x 14.
      Disc  : constant Pixel_Region :=
        Rasterize (Image, Circle (20.0, 15.0, 9.5, "#"));
      No_Mask : Ks_Image_8_Grey;
      Empty   : Pixel_Region;

      use type Interfaces.Unsigned_8;

      function Dont_Care
        (Mask               : Ks_Image_8_Grey;
         Offset_X, Offset_Y : Integer;
         I, J               : Integer) return Boolean;
      --  The definition, computed here: a mask pixel of value 0 lies over
      --  pixel (I, J).

      function Dont_Care
        (Mask               : Ks_Image_8_Grey;
         Offset_X, Offset_Y : Integer;
         I, J               : Integer) return Boolean
      is
         U : constant Long_Long_Integer :=
           Long_Long_Integer (I) - Long_Long_Integer (Offset_X);
         V : constant Long_Long_Integer :=
           Long_Long_Integer (J) - Long_Long_Integer (Offset_Y);
      begin
         return Mask.Allocated
           and then U in 0 .. Long_Long_Integer (Mask.Width) - 1
           and then V in 0 .. Long_Long_Integer (Mask.Height) - 1
           and then Mask.Get_Pixel (Natural (U), Natural (V)) = 0;
      end Dont_Care;

      procedure Check_Masked
        (Source             : Pixel_Region;
         Mask               : Ks_Image_8_Grey;
         Offset_X, Offset_Y : Integer;
         Description        : String);
      --  Restricts Source by Mask and compares the result with the pixels
      --  of Source that Dont_Care leaves, over the whole image (count,
      --  membership of every pixel, the tight rectangle).

      procedure Check_Masked
        (Source             : Pixel_Region;
         Mask               : Ks_Image_8_Grey;
         Offset_X, Offset_Y : Integer;
         Description        : String)
      is
         function Expected (I, J : Integer) return Boolean is
           (Source.Contains (I, J)
            and then not Dont_Care (Mask, Offset_X, Offset_Y, I, J));
      begin
         Check_Pixels
           (Restrict_To_Mask (Source, Mask, Offset_X, Offset_Y), W, H,
            Expected'Access, Description);
      end Check_Masked;

      function Mask_Of
        (Width, Height : Positive;
         Value         : Grey_8 := 255) return Ks_Image_8_Grey
      is (Create (Width, Height, Value));
      --  A mask of one value, 255 ("care") unless given.
   begin
      Section ("Restrict_To_Mask: part of a rectangle");
      Check_Bounds (Box, 5, 4, 20, 14, 280, "the rectangle");
      declare
         Mask : Ks_Image_8_Grey := Mask_Of (6, 5);
         R    : Pixel_Region;
      begin
         --  Four "don't care" pixels, at (11, 9), (12, 9), (14, 11) and
         --  (10, 12) of the image.
         Mask.Set_Pixel (1, 1, 0);
         Mask.Set_Pixel (2, 1, 0);
         Mask.Set_Pixel (4, 3, 0);
         Mask.Set_Pixel (0, 4, 0);
         --  Values other than 0 and 255 are "care" too.
         Mask.Set_Pixel (3, 3, 1);
         Mask.Set_Pixel (5, 0, 128);
         Check_Masked (Box, Mask, 10, 8, "four pixels removed");
         R := Restrict_To_Mask (Box, Mask, 10, 8);
         Check_Bounds (R, 5, 4, 20, 14, 276, "four pixels removed");
         Check (not R.Contains (11, 9) and then not R.Contains (12, 9)
                and then not R.Contains (14, 11)
                and then not R.Contains (10, 12)
                and then R.Contains (13, 11) and then R.Contains (15, 8)
                and then R.Contains (10, 8),
                "four pixels removed: exactly those");
         Check (Box.Pixel_Count = 280, "the source is unchanged");
         Check_Masked (Disc, Mask, 10, 8, "four pixels of a disc");
         Check_Masked (Disc, Mask, 15, 10, "a disc, another offset");
      end;

      Section ("Restrict_To_Mask: a mask that covers nothing");
      declare
         Care : constant Ks_Image_8_Grey := Mask_Of (W, H, 7);
         Zero : constant Ks_Image_8_Grey := Mask_Of (8, 8, 0);
      begin
         Check_Same (Box, Restrict_To_Mask (Box, Care), "no 0 in the mask");
         Check_Same (Disc, Restrict_To_Mask (Disc, Care),
                     "no 0 in the mask, disc");
         Check_Same (Box, Restrict_To_Mask (Box, No_Mask),
                     "an unallocated mask");
         Check_Same (Disc, Restrict_To_Mask (Disc, No_Mask),
                     "an unallocated mask, disc");
         Check_Same (Box, Restrict_To_Mask (Box, Zero, 25, 0),
                     "zeros right of the rectangle");
         Check_Same (Box, Restrict_To_Mask (Box, Zero, -3, -4),
                     "zeros left of and above the rectangle");
         Check_Same (Box, Restrict_To_Mask (Box, Zero, 1000, 1000),
                     "zeros far outside the image");
         Check_Same (Whole, Restrict_To_Mask (Whole, Zero, -8, 0),
                     "zeros just left of the image");
         Check_Same (Whole, Restrict_To_Mask (Whole, Zero, W, H),
                     "zeros just beyond the image");
         Check_Same (Whole, Restrict_To_Mask (Whole, Zero, Integer'Last,
                                              Integer'First),
                     "extreme offsets");
         Check_Same (Whole, Restrict_To_Mask (Whole, Zero, Integer'First,
                                              Integer'Last),
                     "extreme offsets the other way");
         Check_Empty (Restrict_To_Mask (Empty, Zero),
                      "the empty region");
      end;

      Section ("Restrict_To_Mask: every pixel removed");
      declare
         Zero : constant Ks_Image_8_Grey := Mask_Of (W, H, 0);
         Fit  : constant Ks_Image_8_Grey := Mask_Of (20, 14, 0);
      begin
         Check_Empty (Restrict_To_Mask (Whole, Zero), "the whole image");
         Check_Empty (Restrict_To_Mask (Box, Zero), "the rectangle");
         Check_Empty (Restrict_To_Mask (Disc, Zero), "the disc");
         Check_Empty (Restrict_To_Mask (Box, Fit, 5, 4),
                      "a mask exactly over the rectangle");
         Check_Masked (Box, Fit, 6, 4, "the same mask one pixel right");
         Check_Bounds (Restrict_To_Mask (Box, Fit, 6, 4), 5, 4, 1, 14, 14,
                       "the same mask one pixel right");
      end;

      Section ("Restrict_To_Mask: offsets");
      declare
         Corner : constant Ks_Image_8_Grey := Mask_Of (10, 10, 0);
      begin
         Check_Masked (Whole, Corner, -5, -5, "a negative offset");
         Check (Restrict_To_Mask (Whole, Corner, -5, -5).Pixel_Count
                  = W * H - 25
                and then not Restrict_To_Mask (Whole, Corner, -5, -5)
                               .Contains (4, 4)
                and then Restrict_To_Mask (Whole, Corner, -5, -5)
                           .Contains (5, 4),
                "a negative offset: 5 x 5 pixels removed");
         Check_Masked (Whole, Corner, W - 5, H - 5, "beyond the image");
         Check (Restrict_To_Mask (Whole, Corner, W - 5, H - 5).Pixel_Count
                  = W * H - 25,
                "beyond the image: 5 x 5 pixels removed");
         Check_Masked (Whole, Corner, -9, 3, "one column inside");
         Check_Bounds (Restrict_To_Mask (Whole, Corner, -9, -9), 0, 0, W, H,
                       W * H - 1, "one corner pixel inside");
         Check_Masked (Disc, Corner, 13, 18, "a disc");
      end;

      Section ("Restrict_To_Mask: a full rectangle made sparse");
      declare
         Hole : Ks_Image_8_Grey := Mask_Of (3, 3);
      begin
         Hole.Set_Pixel (1, 1, 0);
         Check_Masked (Box, Hole, 11, 9, "a hole");
         Check_Bounds (Restrict_To_Mask (Box, Hole, 11, 9), 5, 4, 20, 14,
                       279, "a hole keeps the rectangle");
         Check_Masked (Box, Hole, 4, 3, "a hole at the corner");
         Check_Bounds (Restrict_To_Mask (Box, Hole, 4, 3), 5, 4, 20, 14,
                       279, "the corner pixel removed");
      end;

      Section ("Restrict_To_Mask: a border trimmed");
      declare
         Trim : Ks_Image_8_Grey := Mask_Of (20, 14);
      begin
         --  0 in the first column and the last row of the rectangle.
         for J in 0 .. 13 loop
            Trim.Set_Pixel (0, J, 0);
         end loop;
         for I in 0 .. 19 loop
            Trim.Set_Pixel (I, 13, 0);
         end loop;
         Check_Masked (Box, Trim, 5, 4, "first column and last row");
         Check_Bounds (Restrict_To_Mask (Box, Trim, 5, 4), 6, 4, 19, 13,
                       19 * 13, "the rectangle shrinks");
         Check_Masked (Disc, Trim, 11, 6, "a disc trimmed");
      end;

      Section ("Restrict_To_Mask: a pattern over a disc");
      declare
         Checker : Ks_Image_8_Grey := Mask_Of (17, 13);
      begin
         for J in 0 .. 12 loop
            for I in 0 .. 16 loop
               if (I + J) mod 2 = 0 then
                  Checker.Set_Pixel (I, J, 0);
               end if;
            end loop;
         end loop;
         Check_Masked (Disc, Checker, 12, 9, "a checkerboard");
         Check_Masked (Box, Checker, 0, 0, "a checkerboard over a corner");
      end;
   end Test_Masks;

   procedure Run_All is
   begin
      Test_Default_And_Whole_Image;
      Test_Rectangles;
      Test_Circles;
      Test_Affine_Rectangles;
      Test_Polygons;
      Test_Annulus_Sections;
      Test_Outside;
      Test_Spaces;
      Test_Unallocated;
      Test_Holders;
      Test_Copies;
      Test_Image_Types;
      Test_Large_Coordinates;
      Test_Streams;
      Test_Masks;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Regions;
