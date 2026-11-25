with Ada.Numerics;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;
with AMV.Blob;
with AMV.Tools;

package body Circularity_Measure is
   use Ada.Numerics.Long_Elementary_Functions;
   use AMV.Blob;
   use type AMV.Tools.Ks_Tool_Result_Constants;
   use type Code_Type;

   Tool : Ks_Blob_Tool;

   Ray_Count    : constant := 720;              --  one every half degree
   Ray_Step     : constant Long_Float := 0.5;   --  pixels between samples
   Run_Needed   : constant := 3;     --  object samples in a row at the edge
   Median_Half  : constant := 7;     --  rays each side for the median
   Smooth_Half  : constant := 2;     --  rays each side for the average
   Search_Scale : constant Long_Float := 1.3;
   Invalid      : constant Long_Float := -1.0;

   type Radius_Array is array (0 .. Ray_Count - 1) of Long_Float;

   type Matrix_Access is access AMV.Images.Grey_8_Matrix;
   procedure Free is new Ada.Unchecked_Deallocation
     (AMV.Images.Grey_8_Matrix, Matrix_Access);

   Pixels : Matrix_Access;  --  a copy of the image, kept between calls

   procedure Fit_Circle
     (Points : Point_Vectors.Vector;
      X, Y, Radius : out Long_Float;
      Ok : out Boolean);
   --  Kasa's algebraic least-squares circle, on coordinates centred at
   --  the points' mean.

   procedure Fit_Circle
     (Points : Point_Vectors.Vector;
      X, Y, Radius : out Long_Float;
      Ok : out Boolean)
   is
      N : constant Long_Float := Long_Float (Natural (Points.Length));
      Mean_X, Mean_Y : Long_Float := 0.0;
      Suu, Svv, Suv, Suz, Svz, Sz : Long_Float := 0.0;
      U, V, Z, Det, D, E, F, R2 : Long_Float;
   begin
      X := 0.0;
      Y := 0.0;
      Radius := 0.0;
      Ok := False;
      if Natural (Points.Length) < 3 then
         return;
      end if;
      for P of Points loop
         Mean_X := Mean_X + P.X;
         Mean_Y := Mean_Y + P.Y;
      end loop;
      Mean_X := Mean_X / N;
      Mean_Y := Mean_Y / N;
      for P of Points loop
         U := P.X - Mean_X;
         V := P.Y - Mean_Y;
         Z := U * U + V * V;
         Suu := Suu + U * U;
         Svv := Svv + V * V;
         Suv := Suv + U * V;
         Suz := Suz + U * Z;
         Svz := Svz + V * Z;
         Sz := Sz + Z;
      end loop;
      --  With Sum U = Sum V = 0 the normal equations of
      --  U**2 + V**2 + D U + E V + F = 0 split into a 2 x 2 system.
      Det := Suu * Svv - Suv * Suv;
      if abs Det < 1.0E-9 then
         return;
      end if;
      D := -(Suz * Svv - Svz * Suv) / Det;
      E := -(Svz * Suu - Suz * Suv) / Det;
      F := -Sz / N;
      R2 := (D * D + E * E) / 4.0 - F;
      if R2 <= 0.0 then
         return;
      end if;
      X := Mean_X - D / 2.0;
      Y := Mean_Y - E / 2.0;
      Radius := Sqrt (R2);
      Ok := True;
   end Fit_Circle;

   procedure Copy_Pixels (Image : AMV.Images.Ks_Image_8_Grey) is
      Width  : constant Natural := AMV.Images.Width (Image);
      Height : constant Natural := AMV.Images.Height (Image);
      Row    : AMV.Images.Grey_8_Row (0 .. Width - 1);
   begin
      if Pixels = null
        or else Pixels'Length (1) /= Height
        or else Pixels'Length (2) /= Width
      then
         Free (Pixels);
         Pixels := new AMV.Images.Grey_8_Matrix (0 .. Height - 1,
                                                 0 .. Width - 1);
      end if;
      for Y in 0 .. Height - 1 loop
         Image.Get_Row (Y, Row);
         for X in Row'Range loop
            Pixels (Y, X) := Row (X);
         end loop;
      end loop;
   end Copy_Pixels;

   function Otsu_Threshold return Natural is
      Histogram : array (0 .. 255) of Long_Float := [others => 0.0];
      Total, Sum, Sum_Back, Weight_Back, Weight_Fore : Long_Float := 0.0;
      Between, Best : Long_Float := -1.0;
      First_Best, Last_Best : Natural := 128;
   begin
      for Y in Pixels'Range (1) loop
         for X in Pixels'Range (2) loop
            Histogram (Natural (Pixels (Y, X))) :=
              Histogram (Natural (Pixels (Y, X))) + 1.0;
         end loop;
      end loop;
      for I in Histogram'Range loop
         Total := Total + Histogram (I);
         Sum := Sum + Long_Float (I) * Histogram (I);
      end loop;
      for T in 0 .. 254 loop
         Weight_Back := Weight_Back + Histogram (T);
         Sum_Back := Sum_Back + Long_Float (T) * Histogram (T);
         Weight_Fore := Total - Weight_Back;
         exit when Weight_Fore = 0.0;
         if Weight_Back > 0.0 then
            Between := Weight_Back * Weight_Fore
              * (Sum_Back / Weight_Back
                 - (Sum - Sum_Back) / Weight_Fore) ** 2;
            --  Equal maxima span a gap in the histogram: take its middle.
            if Between > Best * (1.0 + 1.0E-12) then
               Best := Between;
               First_Best := T;
               Last_Best := T;
            elsif Between >= Best * (1.0 - 1.0E-12) then
               Last_Best := T;
            end if;
         end if;
      end loop;
      --  Object: grey >= the threshold, so one past the last background
      --  level.
      return (First_Best + Last_Best) / 2 + 1;
   end Otsu_Threshold;

   procedure Measure
     (Image    : AMV.Images.Ks_Image_8_Grey;
      Config   : Settings;
      Outcome  : out Result;
      Boundary : in out Point_Vectors.Vector)
   is
      Light : constant Boolean := Config.Polarity = Light_Object;
      Polarity : constant Ks_Blob_Segmentation_Polarity_Constants :=
        (if Light then Light_Blobs else Dark_Blobs);
      Width, Height  : Natural;
      Threshold      : Natural;
      Level          : Long_Float;
      Best_ID        : Integer := -1;
      Best_Area      : Long_Float := 0.0;
      Best_Unclipped : Boolean := False;
      Box_X0, Box_X1, Box_Y0, Box_Y1 : Long_Float := 0.0;
      Touches        : Boolean := False;

      --  Bilinear grey value at (X, Y); background outside the image.
      function Sample (X, Y : Long_Float) return Long_Float is
         X0, Y0 : Integer;
         FX, FY : Long_Float;
         function P (XX, YY : Integer) return Long_Float is
           (Long_Float (Pixels (YY, XX)));
      begin
         if X < 0.0 or else Y < 0.0
           or else X > Long_Float (Width - 1)
           or else Y > Long_Float (Height - 1)
         then
            return (if Light then 0.0 else 255.0);
         end if;
         X0 := Integer'Min (Integer (Long_Float'Floor (X)), Width - 2);
         Y0 := Integer'Min (Integer (Long_Float'Floor (Y)), Height - 2);
         FX := X - Long_Float (X0);
         FY := Y - Long_Float (Y0);
         return (P (X0, Y0) * (1.0 - FX) + P (X0 + 1, Y0) * FX) * (1.0 - FY)
           + (P (X0, Y0 + 1) * (1.0 - FX) + P (X0 + 1, Y0 + 1) * FX) * FY;
      end Sample;

      function Object (Value : Long_Float) return Boolean is
        (if Light then Value >= Level else Value < Level);

      --  For each ray from (CX, CY), the radius where it first enters the
      --  object coming in from Max_R: the outer edge, whatever lies
      --  inside it (shadows, the cup's inside, a seam). Invalid where no
      --  edge is found or the object reaches Max_R.
      procedure Cast (CX, CY, Max_R : Long_Float; Radii : out Radius_Array)
      is
         Steps : constant Natural := Natural (Max_R / Ray_Step);
         Angle, DX, DY, R, Value, Previous, Edge_R, Edge_Value,
         Outer_Value, Fraction, EX, EY : Long_Float;
         Run : Natural;
      begin
         for K in Radii'Range loop
            Radii (K) := Invalid;
            Angle := 2.0 * Ada.Numerics.Pi * Long_Float (K)
                     / Long_Float (Ray_Count);
            DX := Cos (Angle);
            DY := Sin (Angle);
            Run := 0;
            Previous := (if Light then 0.0 else 255.0);
            Edge_R := 0.0;
            Edge_Value := 0.0;
            Outer_Value := Previous;
            for S in reverse 0 .. Steps loop
               R := Long_Float (S) * Ray_Step;
               Value := Sample (CX + R * DX, CY + R * DY);
               if Object (Value) then
                  if S = Steps then
                     exit;  --  the object reaches the search limit
                  end if;
                  if Run = 0 then
                     Edge_R := R;
                     Edge_Value := Value;
                     Outer_Value := Previous;
                  end if;
                  Run := Run + 1;
                  if Run >= Run_Needed then
                     Fraction :=
                       (if Edge_Value = Outer_Value then 1.0
                        else (Level - Outer_Value)
                             / (Edge_Value - Outer_Value));
                     Fraction := Long_Float'Min (1.0,
                                                 Long_Float'Max (0.0,
                                                                 Fraction));
                     Radii (K) := Edge_R + Ray_Step * (1.0 - Fraction);
                     EX := CX + Radii (K) * DX;
                     EY := CY + Radii (K) * DY;
                     if EX < 1.0 or else EY < 1.0
                       or else EX > Long_Float (Width) - 2.0
                       or else EY > Long_Float (Height) - 2.0
                     then
                        Touches := True;
                     end if;
                     exit;
                  end if;
               else
                  Run := 0;
               end if;
               Previous := Value;
            end loop;
         end loop;
      end Cast;

      --  Replaces each radius that is missing or more than 3 % (at least
      --  4 px) away from the median of its 15 neighbouring rays by that
      --  median: a seam or a gap in the rim lets a few rays run past the
      --  edge. Returns the number of rays it had to replace.
      function Reject_Outliers (Radii : in out Radius_Array) return Natural
      is
         Result   : Radius_Array := Radii;
         Window   : array (1 .. 2 * Median_Half + 1) of Long_Float;
         Count    : Natural;
         Replaced : Natural := 0;
         Median, Swap : Long_Float;
      begin
         for K in Radii'Range loop
            Count := 0;
            for J in -Median_Half .. Median_Half loop
               declare
                  V : constant Long_Float := Radii ((K + J) mod Ray_Count);
               begin
                  if V /= Invalid then
                     Count := Count + 1;
                     Window (Count) := V;
                  end if;
               end;
            end loop;
            if Count < 3 then
               Result (K) := Invalid;
               Replaced := Replaced + 1;
            else
               for I in 2 .. Count loop
                  for J in reverse 2 .. I loop
                     exit when Window (J - 1) <= Window (J);
                     Swap := Window (J);
                     Window (J) := Window (J - 1);
                     Window (J - 1) := Swap;
                  end loop;
               end loop;
               Median := Window ((Count + 1) / 2);
               if Radii (K) = Invalid
                 or else abs (Radii (K) - Median)
                         > Long_Float'Max (4.0, 0.03 * Median)
               then
                  Result (K) := Median;
                  Replaced := Replaced + 1;
               end if;
            end if;
         end loop;
         Radii := Result;
         return Replaced;
      end Reject_Outliers;

      function Points_Of (CX, CY : Long_Float; Radii : Radius_Array)
        return Point_Vectors.Vector
      is
         Points : Point_Vectors.Vector;
         Angle  : Long_Float;
      begin
         for K in Radii'Range loop
            if Radii (K) /= Invalid then
               Angle := 2.0 * Ada.Numerics.Pi * Long_Float (K)
                        / Long_Float (Ray_Count);
               Points.Append (Point'(CX + Radii (K) * Cos (Angle),
                                     CY + Radii (K) * Sin (Angle)));
            end if;
         end loop;
         return Points;
      end Points_Of;

      --  Distance from (CX, CY) to the farthest corner of the blob's box:
      --  the outer edge cannot lie beyond it.
      function Box_Reach (CX, CY : Long_Float) return Long_Float is
        (Sqrt (Long_Float'Max ((Box_X0 - CX) ** 2, (Box_X1 - CX) ** 2)
               + Long_Float'Max ((Box_Y0 - CY) ** 2, (Box_Y1 - CY) ** 2)));

      Radii      : Radius_Array;
      Smoothed   : Radius_Array;
      CX, CY, R  : Long_Float;
      Ok         : Boolean;
      Replaced   : Natural;
   begin
      Outcome := (others => <>);
      Boundary.Clear;

      Copy_Pixels (Image);
      Width := Pixels'Length (2);
      Height := Pixels'Length (1);
      Threshold :=
        (if Config.Auto_Threshold then Otsu_Threshold else Config.Threshold);
      Level := Long_Float (Threshold);

      --  The blob tool finds the object and its extent.
      Tool.Input_Image := Image;
      Set_Segmentation_Hard_Fixed_Threshold
        (Tool.Run_Params.Segmentation_Params, Threshold, Polarity);
      Tool.Run_Params.Sort_Enabled := Code (False);
      Tool.Run;
      if Tool.Run_Status.Result /= AMV.Tools.Accept_Result then
         raise AMV.Ks_Exception with AMV.Tools.Message (Tool.Run_Status);
      end if;
      declare
         Features : constant Ks_Blob_Result_Collection'Class :=
           Tool.Results.Get_Blobs (Filtered => False);
      begin
         for I in 0 .. Features.Count - 1 loop
            declare
               Feature   : constant Ks_Blob_Result := Features.Item (I);
               Unclipped : constant Boolean := Feature.Not_Clipped /= 0;
            begin
               if Feature.Label = Code (Ks_Blob_Label_Constants'(Blob))
                 and then Feature.Area >= Config.Min_Area
                 and then
                   (Best_ID < 0
                    or else (Unclipped and not Best_Unclipped)
                    or else (Unclipped = Best_Unclipped
                             and then Feature.Area > Best_Area))
               then
                  Best_ID := Integer (Feature.ID);
                  Best_Area := Feature.Area;
                  Best_Unclipped := Unclipped;
                  Box_X0 := Feature.Pixel_Aligned_Min_X;
                  Box_X1 := Feature.Pixel_Aligned_Max_X;
                  Box_Y0 := Feature.Pixel_Aligned_Min_Y;
                  Box_Y1 := Feature.Pixel_Aligned_Max_Y;
               end if;
            end;
         end loop;
      end;
      if Best_ID < 0 then
         return;
      end if;

      --  Two passes: from the centre of the blob's box, then from the
      --  centre of the circle fitted to the first pass's edge.
      CX := (Box_X0 + Box_X1) / 2.0;
      CY := (Box_Y0 + Box_Y1) / 2.0;
      R := Long_Float'Max (Box_X1 - Box_X0, Box_Y1 - Box_Y0) / 2.0;
      for Pass in 1 .. 2 loop
         Touches := False;
         Cast (CX, CY,
               Long_Float'Max (Box_Reach (CX, CY), Search_Scale * R) + 4.0,
               Radii);
         Replaced := Reject_Outliers (Radii);
         if Replaced > Ray_Count / 2 then
            return;  --  no clear outer edge
         end if;
         if Pass = 1 then
            Fit_Circle (Points_Of (CX, CY, Radii), CX, CY, R, Ok);
            if not Ok then
               return;
            end if;
         end if;
      end loop;

      --  A light average over 5 rays (2.5 degrees) takes out pixel noise.
      for K in Radii'Range loop
         declare
            Sum   : Long_Float := 0.0;
            Count : Natural := 0;
         begin
            for J in -Smooth_Half .. Smooth_Half loop
               if Radii ((K + J) mod Ray_Count) /= Invalid then
                  Sum := Sum + Radii ((K + J) mod Ray_Count);
                  Count := Count + 1;
               end if;
            end loop;
            Smoothed (K) :=
              (if Radii (K) = Invalid or else Count = 0 then Invalid
               else Sum / Long_Float (Count));
         end;
      end loop;
      Boundary := Points_Of (CX, CY, Smoothed);
      if Natural (Boundary.Length) < Ray_Count / 2 then
         Boundary.Clear;
         return;
      end if;

      declare
         Twice_Area : Long_Float := 0.0;
         Length     : Long_Float := 0.0;
         Count      : constant Positive := Natural (Boundary.Length);
         Distance   : Long_Float;
      begin
         for I in 1 .. Count loop
            declare
               A : constant Point := Boundary (I);
               B : constant Point := Boundary (I mod Count + 1);
            begin
               Twice_Area := Twice_Area + (A.X * B.Y - B.X * A.Y);
               Length := Length + Sqrt ((B.X - A.X) ** 2 + (B.Y - A.Y) ** 2);
            end;
         end loop;
         Outcome.Area := abs Twice_Area / 2.0;
         Outcome.Perimeter := Length;
         Outcome.Circularity :=
           4.0 * Ada.Numerics.Pi * Outcome.Area / (Length * Length);
         Outcome.Clipped := Touches;

         Fit_Circle (Boundary, Outcome.Center_X, Outcome.Center_Y,
                     Outcome.Radius, Ok);
         if not Ok then
            return;
         end if;
         Outcome.Radius_Min := Long_Float'Last;
         Outcome.Radius_Max := 0.0;
         for P of Boundary loop
            Distance := Sqrt ((P.X - Outcome.Center_X) ** 2
                              + (P.Y - Outcome.Center_Y) ** 2);
            Outcome.Radius_Min := Long_Float'Min (Outcome.Radius_Min,
                                                  Distance);
            Outcome.Radius_Max := Long_Float'Max (Outcome.Radius_Max,
                                                  Distance);
         end loop;
         Outcome.Roundness := Outcome.Radius_Min / Outcome.Radius_Max;
         Outcome.Threshold := Threshold;
         Outcome.Found := True;
      end;
   end Measure;

end Circularity_Measure;
