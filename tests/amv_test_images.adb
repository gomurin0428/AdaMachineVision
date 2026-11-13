with Ada.Numerics.Generic_Elementary_Functions;
with Interfaces;

package body AMV_Test_Images is

   use AMV.Images;

   package Math is new Ada.Numerics.Generic_Elementary_Functions (Real);

   Margin : constant Real := 0.7072;
   --  Slightly more than half the diagonal of a pixel square: every sample
   --  point of a pixel lies closer than this to the pixel centre.

   type Pixel_Class is (Outside, Inside, Partial);
   --  What is known about a whole pixel square: entirely outside the
   --  shape, entirely inside, or unknown (sample it).

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   procedure Require (Image : Ks_Image_8_Grey; Caller : String) is
   begin
      if not Image.Allocated then
         raise Ks_Image_No_Pixels_Exception
           with Caller & ": the image has no pixels";
      end if;
   end Require;

   function To_Grey (Value : Real) return Grey_8 is
   begin
      if not (Value > 0.0) then
         return 0;
      elsif Value >= 255.0 then
         return 255;
      else
         return Grey_8 (Integer (Value));  --  rounds halves away from zero
      end if;
   end To_Grey;

   function First_Pixel (Low : Real; Count : Positive) return Integer is
     (Integer'Max
        (0,
         Integer (Real'Floor (Real'Max (-2.0, Real'Min (Low, Real (Count)))))
         - 1));
   --  The first pixel index to visit for a bounding box starting at Low
   --  (one pixel of margin), clamped to the image.

   function Last_Pixel (High : Real; Count : Positive) return Integer is
     (Integer'Min
        (Count - 1,
         Integer
           (Real'Ceiling (Real'Max (-2.0, Real'Min (High, Real (Count)))))
         + 1));

   generic
      with function Classify (X, Y : Real) return Pixel_Class;
      --  Classifies the pixel square centred on (X, Y). It may return
      --  Inside (or Outside) only when every sample point of the square is
      --  inside (or outside) according to Is_Inside; Partial is always
      --  allowed.
      with function Is_Inside (X, Y : Real) return Boolean;
   procedure Paint
     (Image        : in out Ks_Image_8_Grey;
      X_Min, X_Max : Real;
      Y_Min, Y_Max : Real;
      Value        : Grey_8;
      Samples      : Positive);
   --  Blends Value into every pixel near the bounding box
   --  [X_Min, X_Max] x [Y_Min, Y_Max] by its coverage.

   procedure Paint
     (Image        : in out Ks_Image_8_Grey;
      X_Min, X_Max : Real;
      Y_Min, Y_Max : Real;
      Value        : Grey_8;
      Samples      : Positive)
   is
      W  : constant Positive := Image.Width;
      H  : constant Positive := Image.Height;
      XF : constant Integer := First_Pixel (X_Min, W);
      XL : constant Integer := Last_Pixel (X_Max, W);
      YF : constant Integer := First_Pixel (Y_Min, H);
      YL : constant Integer := Last_Pixel (Y_Max, H);

      S       : constant Real := Real (Samples);
      Offsets : array (0 .. Samples - 1) of Real;
      Total   : constant Real := S * S;
      Row     : Grey_8_Row (0 .. W - 1);

      function Coverage (X, Y : Real) return Real is
         Count : Natural := 0;
      begin
         case Classify (X, Y) is
            when Inside =>
               return 1.0;
            when Outside =>
               return 0.0;
            when Partial =>
               for B in Offsets'Range loop
                  for A in Offsets'Range loop
                     if Is_Inside (X + Offsets (A), Y + Offsets (B)) then
                        Count := Count + 1;
                     end if;
                  end loop;
               end loop;
               return Real (Count) / Total;
         end case;
      end Coverage;
   begin
      if XF > XL or else YF > YL then
         return;
      end if;
      for A in Offsets'Range loop
         Offsets (A) := -0.5 + (Real (A) + 0.5) / S;
      end loop;
      for Y in YF .. YL loop
         Image.Get_Row (Y, Row);
         for X in XF .. XL loop
            declare
               C : constant Real := Coverage (Real (X), Real (Y));
            begin
               if C > 0.0 then
                  Row (X) := To_Grey
                    (Real (Row (X)) * (1.0 - C) + Real (Value) * C);
               end if;
            end;
         end loop;
         Image.Set_Row (Y, Row);
      end loop;
   end Paint;

   ---------------------------------------------------------------------
   --  Images
   ---------------------------------------------------------------------

   function Blank
     (Width, Height : Positive;
      Value         : AMV.Images.Grey_8 := 0)
      return AMV.Images.Ks_Image_8_Grey
   is (AMV.Images.Create (Width, Height, Value));

   ---------------------------------------------------------------------
   --  Shapes
   ---------------------------------------------------------------------

   procedure Draw_Rectangle
     (Image                   : in out AMV.Images.Ks_Image_8_Grey;
      Center_X, Center_Y      : Real;
      Width, Height           : Real;
      Rotation                : Real := 0.0;
      Value                   : AMV.Images.Grey_8 := 255;
      Samples                 : Positive := Default_Samples)
   is
      Cos_R : constant Real := Math.Cos (Rotation);
      Sin_R : constant Real := Math.Sin (Rotation);
      Hw    : constant Real := 0.5 * Width;
      Hh    : constant Real := 0.5 * Height;

      procedure Local (X, Y : Real; U, V : out Real) is
         Dx : constant Real := X - Center_X;
         Dy : constant Real := Y - Center_Y;
      begin
         U := Cos_R * Dx + Sin_R * Dy;
         V := -Sin_R * Dx + Cos_R * Dy;
      end Local;

      function Is_Inside (X, Y : Real) return Boolean is
         U, V : Real;
      begin
         Local (X, Y, U, V);
         return abs U <= Hw and then abs V <= Hh;
      end Is_Inside;

      function Classify (X, Y : Real) return Pixel_Class is
         U, V : Real;
      begin
         Local (X, Y, U, V);
         if abs U <= Hw - Margin and then abs V <= Hh - Margin then
            return Inside;
         elsif abs U > Hw + Margin or else abs V > Hh + Margin then
            return Outside;
         else
            return Partial;
         end if;
      end Classify;

      procedure Paint_Rectangle is new Paint (Classify, Is_Inside);
   begin
      Require (Image, "Draw_Rectangle");
      if not (Width > 0.0 and then Height > 0.0) then
         return;
      end if;
      declare
         Ex : constant Real := abs Cos_R * Hw + abs Sin_R * Hh;
         Ey : constant Real := abs Sin_R * Hw + abs Cos_R * Hh;
      begin
         Paint_Rectangle
           (Image, Center_X - Ex, Center_X + Ex, Center_Y - Ey, Center_Y + Ey,
            Value, Samples);
      end;
   end Draw_Rectangle;

   procedure Draw_Circle
     (Image              : in out AMV.Images.Ks_Image_8_Grey;
      Center_X, Center_Y : Real;
      Radius             : Real;
      Value              : AMV.Images.Grey_8 := 255;
      Samples            : Positive := Default_Samples)
   is
      R2 : constant Real := Radius * Radius;

      function Is_Inside (X, Y : Real) return Boolean is
        ((X - Center_X) ** 2 + (Y - Center_Y) ** 2 <= R2);

      function Classify (X, Y : Real) return Pixel_Class is
         D : constant Real :=
           Math.Sqrt ((X - Center_X) ** 2 + (Y - Center_Y) ** 2);
      begin
         if D + Margin <= Radius then
            return Inside;
         elsif D - Margin > Radius then
            return Outside;
         else
            return Partial;
         end if;
      end Classify;

      procedure Paint_Circle is new Paint (Classify, Is_Inside);
   begin
      Require (Image, "Draw_Circle");
      if not (Radius > 0.0) then
         return;
      end if;
      Paint_Circle
        (Image, Center_X - Radius, Center_X + Radius,
         Center_Y - Radius, Center_Y + Radius, Value, Samples);
   end Draw_Circle;

   procedure Draw_Ellipse
     (Image              : in out AMV.Images.Ks_Image_8_Grey;
      Center_X, Center_Y : Real;
      Radius_X, Radius_Y : Real;
      Rotation           : Real := 0.0;
      Value              : AMV.Images.Grey_8 := 255;
      Samples            : Positive := Default_Samples)
   is
      Cos_R : constant Real := Math.Cos (Rotation);
      Sin_R : constant Real := Math.Sin (Rotation);

      function Normalised_Radius (X, Y : Real) return Real is
         --  The squared "radius" of (X, Y) in the frame where the ellipse
         --  is the unit circle.
         Dx : constant Real := X - Center_X;
         Dy : constant Real := Y - Center_Y;
         U  : constant Real := (Cos_R * Dx + Sin_R * Dy) / Radius_X;
         V  : constant Real := (-Sin_R * Dx + Cos_R * Dy) / Radius_Y;
      begin
         return U * U + V * V;
      end Normalised_Radius;

      function Is_Inside (X, Y : Real) return Boolean is
        (Normalised_Radius (X, Y) <= 1.0);

      function Classify (X, Y : Real) return Pixel_Class is
         --  Distances shrink by at most 1 / min (Radius_X, Radius_Y) in
         --  the normalised frame.
         Q : constant Real := Math.Sqrt (Normalised_Radius (X, Y));
         M : constant Real := Margin / Real'Min (Radius_X, Radius_Y);
      begin
         if Q + M <= 1.0 then
            return Inside;
         elsif Q - M > 1.0 then
            return Outside;
         else
            return Partial;
         end if;
      end Classify;

      procedure Paint_Ellipse is new Paint (Classify, Is_Inside);
   begin
      Require (Image, "Draw_Ellipse");
      if not (Radius_X > 0.0 and then Radius_Y > 0.0) then
         return;
      end if;
      declare
         Ex : constant Real :=
           Math.Sqrt ((Radius_X * Cos_R) ** 2 + (Radius_Y * Sin_R) ** 2);
         Ey : constant Real :=
           Math.Sqrt ((Radius_X * Sin_R) ** 2 + (Radius_Y * Cos_R) ** 2);
      begin
         Paint_Ellipse
           (Image, Center_X - Ex, Center_X + Ex, Center_Y - Ey, Center_Y + Ey,
            Value, Samples);
      end;
   end Draw_Ellipse;

   procedure Draw_Polygon
     (Image    : in out AMV.Images.Ks_Image_8_Grey;
      Vertices : Vertex_List;
      Value    : AMV.Images.Grey_8 := 255;
      Samples  : Positive := Default_Samples)
   is
      N : constant Natural := Vertices'Length / 2;

      function VX (K : Natural) return Real is
        (Vertices (Vertices'First + 2 * K));
      function VY (K : Natural) return Real is
        (Vertices (Vertices'First + 2 * K + 1));

      function Is_Inside (X, Y : Real) return Boolean is
         --  Even-odd rule: count the edges crossed by the ray from (X, Y)
         --  towards +x. An edge counts when its end points lie on
         --  different sides of the horizontal line through Y (one end
         --  strictly below it), so a vertex on the ray is counted once.
         Result : Boolean := False;
         J      : Natural := N - 1;
      begin
         for I in 0 .. N - 1 loop
            declare
               Xi : constant Real := VX (I);
               Yi : constant Real := VY (I);
               Xj : constant Real := VX (J);
               Yj : constant Real := VY (J);
            begin
               if (Yi > Y) /= (Yj > Y)
                 and then X < Xi + (Y - Yi) * (Xj - Xi) / (Yj - Yi)
               then
                  Result := not Result;
               end if;
            end;
            J := I;
         end loop;
         return Result;
      end Is_Inside;

      function Classify (X, Y : Real) return Pixel_Class is
         --  A pixel square that no edge comes near is uniformly inside or
         --  outside, like its centre.
         Limit : constant Real := Margin * Margin;
         J     : Natural := N - 1;
      begin
         for I in 0 .. N - 1 loop
            declare
               Ax : constant Real := VX (J);
               Ay : constant Real := VY (J);
               Ex : constant Real := VX (I) - Ax;
               Ey : constant Real := VY (I) - Ay;
               Dx : constant Real := X - Ax;
               Dy : constant Real := Y - Ay;
               L2 : constant Real := Ex * Ex + Ey * Ey;
               T  : Real := 0.0;
            begin
               if L2 > 0.0 then
                  T := Real'Max
                    (0.0, Real'Min (1.0, (Dx * Ex + Dy * Ey) / L2));
               end if;
               if (Dx - T * Ex) ** 2 + (Dy - T * Ey) ** 2 <= Limit then
                  return Partial;
               end if;
            end;
            J := I;
         end loop;
         return (if Is_Inside (X, Y) then Inside else Outside);
      end Classify;

      procedure Paint_Polygon is new Paint (Classify, Is_Inside);
   begin
      Require (Image, "Draw_Polygon");
      if Vertices'Length mod 2 /= 0 then
         raise Ks_Bad_Parameter_Exception
           with "Draw_Polygon: Vertices must hold X, Y pairs (even length)";
      elsif N < 3 then
         return;
      end if;
      declare
         Min_X : Real := VX (0);
         Max_X : Real := VX (0);
         Min_Y : Real := VY (0);
         Max_Y : Real := VY (0);
      begin
         for K in 1 .. N - 1 loop
            Min_X := Real'Min (Min_X, VX (K));
            Max_X := Real'Max (Max_X, VX (K));
            Min_Y := Real'Min (Min_Y, VY (K));
            Max_Y := Real'Max (Max_Y, VY (K));
         end loop;
         Paint_Polygon (Image, Min_X, Max_X, Min_Y, Max_Y, Value, Samples);
      end;
   end Draw_Polygon;

   procedure Draw_Half_Plane
     (Image    : in out AMV.Images.Ks_Image_8_Grey;
      X, Y     : Real;
      Rotation : Real;
      Value    : AMV.Images.Grey_8 := 255;
      Samples  : Positive := Default_Samples)
   is
      Nx : constant Real := -Math.Sin (Rotation);
      Ny : constant Real := Math.Cos (Rotation);

      function Distance (Px, Py : Real) return Real is
        ((Px - X) * Nx + (Py - Y) * Ny);
      --  Signed distance from the line, positive on the filled side.

      function Is_Inside (Px, Py : Real) return Boolean is
        (Distance (Px, Py) >= 0.0);

      function Classify (Px, Py : Real) return Pixel_Class is
         D : constant Real := Distance (Px, Py);
      begin
         if D >= Margin then
            return Inside;
         elsif D <= -Margin then
            return Outside;
         else
            return Partial;
         end if;
      end Classify;

      procedure Paint_Half_Plane is new Paint (Classify, Is_Inside);
   begin
      Require (Image, "Draw_Half_Plane");
      Paint_Half_Plane
        (Image, 0.0, Real (Image.Width - 1), 0.0, Real (Image.Height - 1),
         Value, Samples);
   end Draw_Half_Plane;

   procedure Draw_Annulus
     (Image              : in out AMV.Images.Ks_Image_8_Grey;
      Center_X, Center_Y : Real;
      Inner_Radius       : Real;
      Outer_Radius       : Real;
      Value              : AMV.Images.Grey_8 := 255;
      Samples            : Positive := Default_Samples)
   is
      Inner : constant Real := Real'Max (0.0, Inner_Radius);
      I2    : constant Real := Inner * Inner;
      O2    : constant Real := Outer_Radius * Outer_Radius;

      function Is_Inside (X, Y : Real) return Boolean is
         D2 : constant Real := (X - Center_X) ** 2 + (Y - Center_Y) ** 2;
      begin
         return D2 >= I2 and then D2 <= O2;
      end Is_Inside;

      function Classify (X, Y : Real) return Pixel_Class is
         D : constant Real :=
           Math.Sqrt ((X - Center_X) ** 2 + (Y - Center_Y) ** 2);
      begin
         if D - Margin >= Inner and then D + Margin <= Outer_Radius then
            return Inside;
         elsif D + Margin < Inner or else D - Margin > Outer_Radius then
            return Outside;
         else
            return Partial;
         end if;
      end Classify;

      procedure Paint_Annulus is new Paint (Classify, Is_Inside);
   begin
      Require (Image, "Draw_Annulus");
      if not (Outer_Radius > Inner) then
         return;
      end if;
      Paint_Annulus
        (Image, Center_X - Outer_Radius, Center_X + Outer_Radius,
         Center_Y - Outer_Radius, Center_Y + Outer_Radius, Value, Samples);
   end Draw_Annulus;

   ---------------------------------------------------------------------
   --  Gradients, noise, patterns
   ---------------------------------------------------------------------

   function Horizontal_Ramp
     (Width, Height : Positive;
      Low, High     : Real) return AMV.Images.Ks_Image_8_Grey
   is
   begin
      return Result : AMV.Images.Ks_Image_8_Grey :=
        AMV.Images.Create (Width, Height)
      do
         declare
            Row : Grey_8_Row (0 .. Width - 1);
         begin
            for X in Row'Range loop
               if Width = 1 then
                  Row (X) := To_Grey (Low);
               else
                  Row (X) := To_Grey
                    (Low + (High - Low) * Real (X) / Real (Width - 1));
               end if;
            end loop;
            for Y in 0 .. Height - 1 loop
               Result.Set_Row (Y, Row);
            end loop;
         end;
      end return;
   end Horizontal_Ramp;

   procedure Add_Noise
     (Image     : in out AMV.Images.Ks_Image_8_Grey;
      Amplitude : Real;
      Seed      : Natural := 1)
   is
      use type Interfaces.Unsigned_64;

      --  A 64-bit linear congruential generator (Knuth's MMIX constants);
      --  the top 53 bits of the state give a uniform value in [0, 1).
      State : Interfaces.Unsigned_64 := Interfaces.Unsigned_64 (Seed);
      Scale : constant Real := 2.0 ** (-53);
      Amp   : constant Real := abs Amplitude;

      function Next_Uniform return Real is
      begin
         State := State * 6364136223846793005 + 1442695040888963407;
         return Real (Interfaces.Shift_Right (State, 11)) * Scale;
      end Next_Uniform;
   begin
      Require (Image, "Add_Noise");
      declare
         Row : Grey_8_Row (0 .. Image.Width - 1);
      begin
         for Y in 0 .. Image.Height - 1 loop
            Image.Get_Row (Y, Row);
            for X in Row'Range loop
               Row (X) := To_Grey
                 (Real (Row (X)) + Amp * (2.0 * Next_Uniform - 1.0));
            end loop;
            Image.Set_Row (Y, Row);
         end loop;
      end;
   end Add_Noise;

   procedure Checkerboard
     (Image       : in out AMV.Images.Ks_Image_8_Grey;
      Origin_X    : Real;
      Origin_Y    : Real;
      Square_Size : Real;
      Rotation    : Real := 0.0;
      Dark        : AMV.Images.Grey_8 := 30;
      Light       : AMV.Images.Grey_8 := 220;
      Samples     : Positive := Default_Samples)
   is
      Cos_R : constant Real := Math.Cos (Rotation);
      Sin_R : constant Real := Math.Sin (Rotation);

      procedure Grid (X, Y : Real; U, V : out Real) is
         --  Position in units of squares along DirX and DirY.
         Dx : constant Real := X - Origin_X;
         Dy : constant Real := Y - Origin_Y;
      begin
         U := (Cos_R * Dx + Sin_R * Dy) / Square_Size;
         V := (-Sin_R * Dx + Cos_R * Dy) / Square_Size;
      end Grid;

      function Is_Light (U, V : Real) return Boolean is
         F : constant Real := Real'Floor (U) + Real'Floor (V);
      begin
         return Real'Floor (0.5 * F) * 2.0 = F;
      end Is_Light;

      function Is_Inside (X, Y : Real) return Boolean is
         U, V : Real;
      begin
         Grid (X, Y, U, V);
         return Is_Light (U, V);
      end Is_Inside;

      function Classify (X, Y : Real) return Pixel_Class is
         U, V : Real;
      begin
         Grid (X, Y, U, V);
         if abs (U - Real'Rounding (U)) * Square_Size > Margin
           and then abs (V - Real'Rounding (V)) * Square_Size > Margin
         then
            return (if Is_Light (U, V) then Inside else Outside);
         else
            return Partial;
         end if;
      end Classify;

      procedure Paint_Light is new Paint (Classify, Is_Inside);
   begin
      Require (Image, "Checkerboard");
      if not (Square_Size > 0.0) then
         raise Ks_Bad_Parameter_Exception
           with "Checkerboard: Square_Size must be > 0";
      end if;
      Image.Fill (Dark);
      Paint_Light
        (Image, 0.0, Real (Image.Width - 1), 0.0, Real (Image.Height - 1),
         Light, Samples);
   end Checkerboard;

   ---------------------------------------------------------------------
   --  Measurement
   ---------------------------------------------------------------------

   procedure Map
     (H    : Homography;
      U, V : Real;
      X, Y : out Real)
   is
      W : constant Real := H (7) * U + H (8) * V + 1.0;
   begin
      if not (W > 0.0) then
         raise Ks_Bad_Parameter_Exception
           with "Map: the point lies on or behind the horizon";
      end if;
      X := (H (1) * U + H (2) * V + H (3)) / W;
      Y := (H (4) * U + H (5) * V + H (6)) / W;
   end Map;

   procedure Draw_Board
     (Image            : in out AMV.Images.Ks_Image_8_Grey;
      Pixel_From_Board : Homography;
      Columns, Rows    : Positive;
      Margin           : Real := 0.5;
      Dark             : AMV.Images.Grey_8 := 30;
      Light            : AMV.Images.Grey_8 := 220;
      Samples          : Positive := Default_Samples)
   is
      procedure Quad (U0, V0, U1, V1 : Real; Value : Grey_8) is
         X1, Y1, X2, Y2, X3, Y3, X4, Y4 : Real;
      begin
         Map (Pixel_From_Board, U0, V0, X1, Y1);
         Map (Pixel_From_Board, U1, V0, X2, Y2);
         Map (Pixel_From_Board, U1, V1, X3, Y3);
         Map (Pixel_From_Board, U0, V1, X4, Y4);
         Draw_Polygon (Image, [X1, Y1, X2, Y2, X3, Y3, X4, Y4], Value,
                       Samples);
      end Quad;
   begin
      Require (Image, "Draw_Board");
      Quad (-Margin, -Margin, Real (Columns) + Margin, Real (Rows) + Margin,
            Light);
      for R in 0 .. Rows - 1 loop
         for C in 0 .. Columns - 1 loop
            if (C + R) mod 2 = 0 then
               Quad (Real (C), Real (R), Real (C + 1), Real (R + 1), Dark);
            end if;
         end loop;
      end loop;
   end Draw_Board;

   function Mean_Value
     (Image                       : AMV.Images.Ks_Image_8_Grey;
      X_Min, Y_Min, Width, Height : Natural) return Real
   is
   begin
      Require (Image, "Mean_Value");
      if Width = 0 or else Height = 0 then
         raise Ks_Bad_Parameter_Exception
           with "Mean_Value: the window must not be empty";
      elsif Width > Image.Width or else X_Min > Image.Width - Width
        or else Height > Image.Height or else Y_Min > Image.Height - Height
      then
         raise Ks_Bad_Parameter_Exception
           with "Mean_Value: the window must lie inside the image";
      end if;
      declare
         Row : Grey_8_Row (0 .. Image.Width - 1);
         Sum : Real := 0.0;
      begin
         for Y in Y_Min .. Y_Min + Height - 1 loop
            Image.Get_Row (Y, Row);
            for X in X_Min .. X_Min + Width - 1 loop
               Sum := Sum + Real (Row (X));
            end loop;
         end loop;
         return Sum / (Real (Width) * Real (Height));
      end;
   end Mean_Value;

end AMV_Test_Images;
