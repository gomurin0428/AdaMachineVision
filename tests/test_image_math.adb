--  Tests for AMV.Image_Math (Real_Image, sampling, filters, pyramids,
--  statistics).

with Ada.Exceptions;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Streams.Storage.Unbounded;
with Interfaces;

with AMV;             use AMV;
with AMV.Image_Math;  use AMV.Image_Math;
with AMV.Images;
with AMV.Misc;
with AMV.Transforms;
with AMV_Test_Support; use AMV_Test_Support;

procedure Test_Image_Math is

   package EF renames Ada.Numerics.Long_Elementary_Functions;

   use type AMV.Images.Grey_8;

   Tight : constant := 1.0E-12;

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   function Pattern_Value (X, Y : Natural) return Real is
     (Real ((X * 7 + Y * 13) mod 17) + 0.25 * Real (X) - 0.5 * Real (Y));

   function Pattern (W, H : Natural) return Real_Image is
      Result : Real_Image := Create (W, H);
   begin
      for Y in 0 .. H - 1 loop
         for X in 0 .. W - 1 loop
            Result.Set (X, Y, Pattern_Value (X, Y));
         end loop;
      end loop;
      return Result;
   end Pattern;

   function Grey_Pattern (W, H : Positive) return AMV.Images.Ks_Image_8_Grey
   is
      Result : AMV.Images.Ks_Image_8_Grey := AMV.Images.Create (W, H);
   begin
      for Y in 0 .. H - 1 loop
         for X in 0 .. W - 1 loop
            Result.Set_Pixel
              (X, Y, AMV.Images.Grey_8 ((X * 37 + Y * 101 + X * Y) mod 256));
         end loop;
      end loop;
      return Result;
   end Grey_Pattern;

   function Max_Difference (A, B : Real_Image) return Real is
      Worst : Real := 0.0;
   begin
      if A.Width /= B.Width or else A.Height /= B.Height then
         return Real'Last;
      end if;
      for Y in 0 .. A.Height - 1 loop
         for X in 0 .. A.Width - 1 loop
            Worst := Real'Max (Worst, abs (A.Get (X, Y) - B.Get (X, Y)));
         end loop;
      end loop;
      return Worst;
   end Max_Difference;

   function Clamp_Index (I, Count : Integer) return Natural is
     (if I < 0 then 0 elsif I >= Count then Count - 1 else I);

   function Reference_Gaussian
     (Image : Real_Image; Sigma : Real) return Real_Image
   is
      --  Direct separable convolution with clamped indices.
      W      : constant Natural := Image.Width;
      H      : constant Natural := Image.Height;
      Radius : constant Natural := Natural (Real'Ceiling (3.0 * Sigma));
      Kernel : array (-Radius .. Radius) of Real;
      Sum    : Real := 0.0;
      Temp   : Real_Image := Create (W, H);
      Result : Real_Image := Create (W, H);
   begin
      for K in Kernel'Range loop
         Kernel (K) := EF.Exp (-Real (K * K) / (2.0 * Sigma * Sigma));
         Sum := Sum + Kernel (K);
      end loop;
      for K in Kernel'Range loop
         Kernel (K) := Kernel (K) / Sum;
      end loop;
      for Y in 0 .. H - 1 loop
         for X in 0 .. W - 1 loop
            declare
               V : Real := 0.0;
            begin
               for K in Kernel'Range loop
                  V := V + Kernel (K) * Image.Get (Clamp_Index (X + K, W), Y);
               end loop;
               Temp.Set (X, Y, V);
            end;
         end loop;
      end loop;
      for Y in 0 .. H - 1 loop
         for X in 0 .. W - 1 loop
            declare
               V : Real := 0.0;
            begin
               for K in Kernel'Range loop
                  V := V + Kernel (K) * Temp.Get (X, Clamp_Index (Y + K, H));
               end loop;
               Result.Set (X, Y, V);
            end;
         end loop;
      end loop;
      return Result;
   end Reference_Gaussian;

   function Reference_Box
     (Image : Real_Image; Half_Size : Natural) return Real_Image
   is
      W      : constant Natural := Image.Width;
      H      : constant Natural := Image.Height;
      Result : Real_Image := Create (W, H);
   begin
      for Y in 0 .. H - 1 loop
         for X in 0 .. W - 1 loop
            declare
               V : Real := 0.0;
            begin
               for J in -Half_Size .. Half_Size loop
                  for I in -Half_Size .. Half_Size loop
                     V := V + Image.Get
                       (Clamp_Index (X + I, W), Clamp_Index (Y + J, H));
                  end loop;
               end loop;
               Result.Set (X, Y, V / Real ((2 * Half_Size + 1) ** 2));
            end;
         end loop;
      end loop;
      return Result;
   end Reference_Box;

   ---------------------------------------------------------------------
   --  Basic access and value semantics
   ---------------------------------------------------------------------

   procedure Assign (Target : in out Real_Image; Source : Real_Image) is
   begin
      Target := Source;
   end Assign;
   --  Called with the same object twice to exercise self assignment.

   procedure Test_Basics is
      Empty : Real_Image;
      A     : Real_Image := Create (3, 2, 1.5);
      All_Set : Boolean := True;
   begin
      Section ("Real_Image basics");
      Check (Empty.Width = 0 and then Empty.Height = 0, "default is empty");
      Check (A.Width = 3 and then A.Height = 2, "Create size");
      for Y in 0 .. 1 loop
         for X in 0 .. 2 loop
            All_Set := All_Set and then A.Get (X, Y) = 1.5;
         end loop;
      end loop;
      Check (All_Set, "Create fills with Value");
      Check (Create (2, 2).Get (1, 1) = 0.0, "Create default value 0");

      A.Set (2, 1, -7.25);
      A.Set (0, 0, 3.0);
      Check (A.Get (2, 1) = -7.25 and then A.Get (0, 0) = 3.0,
             "Set / Get round trip");
      Check (A.Get (1, 0) = 1.5, "other pixels unchanged");

      declare
         procedure Get_Outside_X is
            V : constant Real := A.Get (3, 0);
         begin
            Check (V = V, "unreachable");
         end Get_Outside_X;
         procedure Get_Outside_Y is
            V : constant Real := A.Get (0, 2);
         begin
            Check (V = V, "unreachable");
         end Get_Outside_Y;
         procedure Set_Outside is
         begin
            A.Set (0, 2, 1.0);
         end Set_Outside;
         procedure Get_Empty is
            V : constant Real := Empty.Get (0, 0);
         begin
            Check (V = V, "unreachable");
         end Get_Empty;
         procedure Create_Huge is
            V : constant Real_Image := Create (Natural'Last, 3);
         begin
            Check (V.Width = 0, "unreachable");
         end Create_Huge;
         procedure T1 is new Check_Raises_Exactly
           (Get_Outside_X, Constraint_Error'Identity);
         procedure T2 is new Check_Raises_Exactly
           (Get_Outside_Y, Constraint_Error'Identity);
         procedure T3 is new Check_Raises_Exactly
           (Set_Outside, Constraint_Error'Identity);
         procedure T4 is new Check_Raises_Exactly
           (Get_Empty, Constraint_Error'Identity);
         procedure T5 is new Check_Raises_Exactly
           (Create_Huge, Ks_Bad_Parameter_Exception'Identity);
      begin
         T1 ("Get with X = Width");
         T2 ("Get with Y = Height");
         T3 ("Set outside");
         T4 ("Get on empty image");
         T5 ("Create with too many pixels");
      end;

      declare
         Z : constant Real_Image := Create (0, 5);
         Z2 : constant Real_Image := Create (4, 0, 9.0);
      begin
         Check (Z.Width = 0 and then Z.Height = 5, "zero-width keeps size");
         Check (Z2.Width = 4 and then Z2.Height = 0,
                "zero-height keeps size");
      end;

      --  Value semantics.
      declare
         B : Real_Image := A;
         C : Real_Image;
      begin
         B.Set (1, 0, 99.0);
         Check (A.Get (1, 0) = 1.5, "assignment copies pixels");
         Check (B.Get (1, 0) = 99.0, "copy is modified");
         Check (B.Get (2, 1) = -7.25, "copy has the original values");
         C := B;
         Assign (C, C);   --  self assignment keeps the pixels
         Check (C.Get (1, 0) = 99.0 and then C.Width = 3,
                "self assignment");
         C := Empty;
         Check (C.Width = 0 and then C.Height = 0,
                "assigning an empty image");
         B := Empty;
         B := A;
         Check (B.Get (0, 0) = 3.0, "reassignment after empty");
      end;

      --  Every way of copying gives an independent image of the right size
      --  (Adjust lets go of the source's buffer before it allocates its
      --  own; a failing allocation, which would test that, needs fault
      --  injection and is not exercised here).
      declare
         Source  : constant Real_Image := Pattern (4, 3);
         Initial : Real_Image := Source;              --  copy-initialization
         Larger  : Real_Image := Create (7, 7, 1.0);
         Sized   : constant Real_Image := Create (0, 5);
         Other   : Real_Image := Create (2, 2, 8.0);
      begin
         Larger := Source;                             --  over another buffer
         Initial.Set (0, 0, -5.0);
         Larger.Set (1, 1, -6.0);
         Check (Source.Get (0, 0) = Pattern_Value (0, 0)
                and then Source.Get (1, 1) = Pattern_Value (1, 1),
                "copies do not share the source's pixels");
         Check (Larger.Width = 4 and then Larger.Height = 3
                and then Larger.Get (3, 2) = Pattern_Value (3, 2),
                "assignment over a larger image takes the source's size");
         Other := Sized;
         Check (Other.Width = 0 and then Other.Height = 5,
                "an image with a size but no pixels copies its size");
         Other := Pattern (3, 2);                      --  function result
         Check (Other.Width = 3 and then Other.Height = 2
                and then Other.Get (2, 1) = Pattern_Value (2, 1),
                "assignment of a function result");
      end;

      A.Fill (4.0);
      Check (A.Get (0, 0) = 4.0 and then A.Get (2, 1) = 4.0, "Fill");
      Empty.Fill (1.0);
      Check (Empty.Width = 0, "Fill on empty image is harmless");
   end Test_Basics;

   ---------------------------------------------------------------------
   --  Conversion
   ---------------------------------------------------------------------

   procedure Test_From_Grey_8 is
      G    : AMV.Images.Ks_Image_8_Grey := AMV.Images.Create (4, 3);
      None : AMV.Images.Ks_Image_8_Grey;
      Ok   : Boolean := True;
   begin
      Section ("From_Grey_8");
      for Y in 0 .. 2 loop
         for X in 0 .. 3 loop
            G.Set_Pixel (X, Y, AMV.Images.Grey_8 (X + 10 * Y + 200 * (X / 3)));
         end loop;
      end loop;
      declare
         R : constant Real_Image := From_Grey_8 (G);
      begin
         Check (R.Width = 4 and then R.Height = 3, "whole image size");
         for Y in 0 .. 2 loop
            for X in 0 .. 3 loop
               Ok := Ok and then R.Get (X, Y) = Real (G.Get_Pixel (X, Y));
            end loop;
         end loop;
         Check (Ok, "whole image values");
         Check (R.Get (3, 2) = 223.0, "pixel (3, 2)");
      end;

      declare
         R : constant Real_Image := From_Grey_8 (G, 1, 1, 2, 2);
      begin
         Check (R.Width = 2 and then R.Height = 2, "window size");
         Check (R.Get (0, 0) = 11.0 and then R.Get (1, 0) = 12.0
                and then R.Get (0, 1) = 21.0 and then R.Get (1, 1) = 22.0,
                "window values");
      end;
      declare
         R : constant Real_Image := From_Grey_8 (G, 3, 2, 1, 1);
      begin
         Check (R.Width = 1 and then R.Height = 1
                and then R.Get (0, 0) = 223.0, "last pixel window");
      end;
      declare
         R : constant Real_Image := From_Grey_8 (G, 0, 0, 4, 3);
      begin
         Check (Max_Difference (R, From_Grey_8 (G)) = 0.0,
                "full window equals whole image");
      end;

      declare
         procedure Zero_Width is
            R : constant Real_Image := From_Grey_8 (G, 0, 0, 0, 1);
         begin
            Check (R.Width = 99, "unreachable");
         end Zero_Width;
         procedure Zero_Height is
            R : constant Real_Image := From_Grey_8 (G, 0, 0, 1, 0);
         begin
            Check (R.Width = 99, "unreachable");
         end Zero_Height;
         procedure Too_Wide is
            R : constant Real_Image := From_Grey_8 (G, 1, 0, 4, 1);
         begin
            Check (R.Width = 99, "unreachable");
         end Too_Wide;
         procedure Too_High is
            R : constant Real_Image := From_Grey_8 (G, 0, 2, 1, 2);
         begin
            Check (R.Width = 99, "unreachable");
         end Too_High;
         procedure Huge_Origin is
            R : constant Real_Image :=
              From_Grey_8 (G, Natural'Last, 0, 1, 1);
         begin
            Check (R.Width = 99, "unreachable");
         end Huge_Origin;
         procedure Huge_Size is
            R : constant Real_Image :=
              From_Grey_8 (G, 0, 0, 1, Natural'Last);
         begin
            Check (R.Width = 99, "unreachable");
         end Huge_Size;
         procedure Unallocated_Whole is
            R : constant Real_Image := From_Grey_8 (None);
         begin
            Check (R.Width = 99, "unreachable");
         end Unallocated_Whole;
         procedure Unallocated_Window is
            R : constant Real_Image := From_Grey_8 (None, 0, 0, 1, 1);
         begin
            Check (R.Width = 99, "unreachable");
         end Unallocated_Window;
         Bad : constant Ada.Exceptions.Exception_Id :=
           Ks_Bad_Parameter_Exception'Identity;
         No_Pixels : constant Ada.Exceptions.Exception_Id :=
           Ks_Image_No_Pixels_Exception'Identity;
         procedure T1 is new Check_Raises_Exactly (Zero_Width, Bad);
         procedure T2 is new Check_Raises_Exactly (Zero_Height, Bad);
         procedure T3 is new Check_Raises_Exactly (Too_Wide, Bad);
         procedure T4 is new Check_Raises_Exactly (Too_High, Bad);
         procedure T5 is new Check_Raises_Exactly (Huge_Origin, Bad);
         procedure T6 is new Check_Raises_Exactly (Huge_Size, Bad);
         procedure T7 is new Check_Raises_Exactly
           (Unallocated_Whole, No_Pixels);
         procedure T8 is new Check_Raises_Exactly
           (Unallocated_Window, No_Pixels);
      begin
         T1 ("zero-width window");
         T2 ("zero-height window");
         T3 ("window past the right edge");
         T4 ("window past the bottom edge");
         T5 ("window origin Natural'Last");
         T6 ("window height Natural'Last");
         T7 ("whole of an unallocated image");
         T8 ("window of an unallocated image");
      end;
   end Test_From_Grey_8;

   procedure Test_To_Grey_8 is
      Inputs   : constant array (Positive range <>) of Real :=
        [-3.0, 0.0, 0.49, 0.5, 1.5, 2.5, 127.5, 254.4, 254.5, 255.0,
         300.0, 1.0E30, -1.0E30, 99.999];
      Expected : constant array (Inputs'Range) of AMV.Images.Grey_8 :=
        [0, 0, 0, 1, 2, 3, 128, 254, 255, 255, 255, 255, 0, 100];
      R        : Real_Image := Create (Inputs'Length, 2);
   begin
      Section ("To_Grey_8");
      for K in Inputs'Range loop
         R.Set (K - Inputs'First, 0, Inputs (K));
         R.Set (K - Inputs'First, 1, Real (K));
      end loop;
      declare
         G : constant AMV.Images.Ks_Image_8_Grey := To_Grey_8 (R);
      begin
         Check (G.Width = Inputs'Length and then G.Height = 2,
                "size preserved");
         for K in Inputs'Range loop
            Check (G.Get_Pixel (K - Inputs'First, 0) = Expected (K),
                   "rounding/clamping of" & Real'Image (Inputs (K)));
            Check (G.Get_Pixel (K - Inputs'First, 1)
                     = AMV.Images.Grey_8 (K),
                   "second row value" & K'Image);
         end loop;
         Check (G.Selected_Space_Name = "@", "fresh coordinate space tree");
      end;

      --  Round trip for integer-valued images.
      declare
         G  : constant AMV.Images.Ks_Image_8_Grey := Grey_Pattern (9, 7);
         G2 : constant AMV.Images.Ks_Image_8_Grey :=
           To_Grey_8 (From_Grey_8 (G));
         Ok : Boolean := True;
      begin
         for Y in 0 .. 6 loop
            for X in 0 .. 8 loop
               Ok := Ok and then G.Get_Pixel (X, Y) = G2.Get_Pixel (X, Y);
            end loop;
         end loop;
         Check (Ok, "From_Grey_8 / To_Grey_8 round trip");
      end;

      declare
         procedure Empty_Image is
            G : constant AMV.Images.Ks_Image_8_Grey :=
              To_Grey_8 (Create (0, 0));
         begin
            Check (G.Width = 99, "unreachable");
         end Empty_Image;
         procedure Zero_Width is
            G : constant AMV.Images.Ks_Image_8_Grey :=
              To_Grey_8 (Create (0, 3));
         begin
            Check (G.Width = 99, "unreachable");
         end Zero_Width;
         procedure T1 is new Check_Raises_Exactly
           (Empty_Image, Ks_Bad_Parameter_Exception'Identity);
         procedure T2 is new Check_Raises_Exactly
           (Zero_Width, Ks_Bad_Parameter_Exception'Identity);
      begin
         T1 ("To_Grey_8 of an empty image");
         T2 ("To_Grey_8 of a zero-width image");
      end;
   end Test_To_Grey_8;

   ---------------------------------------------------------------------
   --  Sampling
   ---------------------------------------------------------------------

   procedure Test_Bilinear is
      --  3 x 2 image:   0  10  40
      --               100 110 140
      R : Real_Image := Create (3, 2);
      G : AMV.Images.Ks_Image_8_Grey := AMV.Images.Create (3, 2);
      Values : constant array (0 .. 1, 0 .. 2) of Real :=
        [[0.0, 10.0, 40.0], [100.0, 110.0, 140.0]];

      type Probe is record
         X, Y, Expected : Real;
      end record;
      Probes : constant array (Positive range <>) of Probe :=
        [(0.0, 0.0, 0.0), (1.0, 0.0, 10.0), (2.0, 1.0, 140.0),
         (1.0, 1.0, 110.0),
         (0.5, 0.0, 5.0), (1.5, 1.0, 125.0), (0.0, 0.5, 50.0),
         (0.5, 0.5, 55.0), (1.5, 0.5, 75.0), (0.25, 0.75, 77.5),
         (1.75, 0.25, 0.75 * 32.5 + 0.25 * 132.5),
         --  outside: clamped to the border
         (-5.0, -5.0, 0.0), (10.0, 0.5, 90.0), (1.5, 7.0, 125.0),
         (-1.0, 0.5, 50.0), (2.0, -0.25, 40.0), (100.0, 100.0, 140.0),
         (-1.0E9, 1.0E9, 100.0)];
   begin
      Section ("Bilinear");
      for Y in 0 .. 1 loop
         for X in 0 .. 2 loop
            R.Set (X, Y, Values (Y, X));
            G.Set_Pixel (X, Y, AMV.Images.Grey_8 (Values (Y, X)));
         end loop;
      end loop;
      for P of Probes loop
         Check_Near (Bilinear (R, P.X, P.Y), P.Expected, Tight,
                     "Real_Image at" & P.X'Image & "," & P.Y'Image);
         Check_Near (Bilinear (G, P.X, P.Y), P.Expected, Tight,
                     "Grey_8 at" & P.X'Image & "," & P.Y'Image);
      end loop;
      Check (Bilinear (R, 1.0, 1.0) = 110.0, "exact value at a centre");
      Check (Bilinear (R, 0.5, 0.0) = 5.0, "exact value at a midpoint");

      --  Grey and Real sampling agree exactly on a fine grid.
      declare
         GP : constant AMV.Images.Ks_Image_8_Grey := Grey_Pattern (6, 5);
         RP : constant Real_Image := From_Grey_8 (GP);
         Ok : Boolean := True;
         X, Y : Real;
      begin
         for J in -8 .. 50 loop
            for I in -8 .. 60 loop
               X := Real (I) * 0.1 - 0.13;
               Y := Real (J) * 0.1 + 0.07;
               Ok := Ok and then Bilinear (GP, X, Y) = Bilinear (RP, X, Y);
            end loop;
         end loop;
         Check (Ok, "Grey_8 and Real_Image sampling agree");
      end;

      --  One pixel wide / high images.
      declare
         Column : Real_Image := Create (1, 3);
         Row    : Real_Image := Create (3, 1);
         Single : constant Real_Image := Create (1, 1, 7.0);
      begin
         Column.Set (0, 0, 0.0);
         Column.Set (0, 1, 10.0);
         Column.Set (0, 2, 30.0);
         Row.Set (0, 0, 4.0);
         Row.Set (1, 0, 8.0);
         Row.Set (2, 0, 0.0);
         Check_Near (Bilinear (Column, 0.0, 1.5), 20.0, Tight, "column mid");
         Check_Near (Bilinear (Column, 0.7, 0.5), 5.0, Tight,
                     "column constant along x");
         Check_Near (Bilinear (Column, -3.0, 2.5), 30.0, Tight,
                     "column clamped");
         Check_Near (Bilinear (Row, 1.25, 0.0), 6.0, Tight, "row quarter");
         Check_Near (Bilinear (Row, 1.5, -0.4), 4.0, Tight,
                     "row constant along y");
         Check_Near (Bilinear (Single, 0.3, -0.7), 7.0, 0.0, "1 x 1 image");
         Check_Near (Bilinear (Single, 1.0E6, 1.0E6), 7.0, 0.0,
                     "1 x 1 image far away");
      end;

      --  Constant images reproduce the constant exactly.
      declare
         C : constant Real_Image := Create (4, 4, 0.1);
      begin
         Check (Bilinear (C, 1.37, 2.71) = 0.1, "constant reproduced exactly");
      end;

      Section ("Is_Inside");
      Check (Is_Inside (R, 0.0, 0.0), "corner (0, 0)");
      Check (Is_Inside (R, 2.0, 1.0), "corner (W - 1, H - 1)");
      Check (Is_Inside (R, 1.3, 0.6), "interior point");
      Check (not Is_Inside (R, 2.000001, 1.0),
             "just right of the last centre");
      Check (not Is_Inside (R, 1.0, 1.000001), "just below the last centre");
      Check (not Is_Inside (R, -1.0E-9, 0.0), "just left of the first centre");
      Check (not Is_Inside (R, 0.0, -1.0E-9), "just above the first centre");
      Check (not Is_Inside (Create (0, 0), 0.0, 0.0), "empty image");
      Check (Is_Inside (Create (1, 1), 0.0, 0.0), "1 x 1 image centre");
      Check (not Is_Inside (Create (1, 1), 0.1, 0.0),
             "1 x 1 image off centre");

      Section ("Bilinear errors");
      declare
         None : AMV.Images.Ks_Image_8_Grey;
         procedure Empty_Real is
            V : constant Real := Bilinear (Create (0, 0), 0.0, 0.0);
         begin
            Check (V = V, "unreachable");
         end Empty_Real;
         procedure Unallocated is
            V : constant Real := Bilinear (None, 0.0, 0.0);
         begin
            Check (V = V, "unreachable");
         end Unallocated;
         procedure T1 is new Check_Raises_Exactly
           (Empty_Real, Ks_Bad_Parameter_Exception'Identity);
         procedure T2 is new Check_Raises_Exactly
           (Unallocated, Ks_Image_No_Pixels_Exception'Identity);
      begin
         T1 ("Bilinear on an empty Real_Image");
         T2 ("Bilinear on an unallocated Grey_8 image");
      end;
   end Test_Bilinear;

   procedure Test_Resample is
      use AMV.Transforms;
      G   : constant AMV.Images.Ks_Image_8_Grey := Grey_Pattern (4, 3);
      Src : constant Real_Image := From_Grey_8 (G);
   begin
      Section ("Resample");

      declare
         Out_R : constant Real_Image := Resample (Src, Identity, 4, 3);
         Out_G : constant Real_Image := Resample (G, Identity, 4, 3);
      begin
         Check (Out_R.Width = 4 and then Out_R.Height = 3, "output size");
         Check (Max_Difference (Out_R, Src) = 0.0, "identity (Real_Image)");
         Check (Max_Difference (Out_G, Src) = 0.0, "identity (Grey_8)");
      end;

      declare
         T     : constant Ks_Transform_2D_Linear :=
           Create (1.0, 0.0, 0.0, 1.0, 1.0, 2.0);
         Out_R : constant Real_Image := Resample (Src, T, 3, 1);
         Out_G : constant Real_Image := Resample (G, T, 3, 1);
         Ok    : Boolean := True;
      begin
         for I in 0 .. 2 loop
            Ok := Ok and then Out_R.Get (I, 0) = Src.Get (I + 1, 2)
              and then Out_G.Get (I, 0) = Src.Get (I + 1, 2);
         end loop;
         Check (Ok, "integer translation");
      end;

      declare
         T     : constant Ks_Transform_2D_Linear :=
           Create (1.0, 0.0, 0.0, 1.0, 0.5, 0.0);
         Out_R : constant Real_Image := Resample (Src, T, 3, 3);
         Ok    : Boolean := True;
      begin
         for J in 0 .. 2 loop
            for I in 0 .. 2 loop
               Ok := Ok and then abs (Out_R.Get (I, J)
                 - 0.5 * (Src.Get (I, J) + Src.Get (I + 1, J))) <= Tight;
            end loop;
         end loop;
         Check (Ok, "half-pixel translation gives midpoints");
      end;

      declare
         T     : constant Ks_Transform_2D_Linear :=
           Create (2.0, 0.0, 0.0, 2.0, 0.0, 0.0);
         Out_R : constant Real_Image := Resample (Src, T, 2, 2);
      begin
         Check (Out_R.Get (0, 0) = Src.Get (0, 0)
                and then Out_R.Get (1, 0) = Src.Get (2, 0)
                and then Out_R.Get (0, 1) = Src.Get (0, 2)
                and then Out_R.Get (1, 1) = Src.Get (2, 2),
                "scaling by 2 picks every other pixel");
      end;

      declare
         T     : constant Ks_Transform_2D_Linear :=
           Create (0.5, 0.0, 0.0, 0.5, 0.0, 0.0);
         Out_R : constant Real_Image := Resample (Src, T, 7, 5);
         Ok    : Boolean := True;
      begin
         for J in 0 .. 4 loop
            for I in 0 .. 6 loop
               Ok := Ok and then Out_R.Get (I, J)
                 = Bilinear (Src, 0.5 * Real (I), 0.5 * Real (J));
            end loop;
         end loop;
         Check (Ok, "scaling by 0.5 interpolates");
         Check_Near (Out_R.Get (1, 1),
                     0.25 * (Src.Get (0, 0) + Src.Get (1, 0)
                             + Src.Get (0, 1) + Src.Get (1, 1)),
                     Tight, "scaling by 0.5: block centre");
      end;

      --  Rotation by exactly 90 degrees: output (I, J) samples the source
      --  at (3 - J, I), so the output is 3 wide and 4 high.
      declare
         T     : constant Ks_Transform_2D_Linear :=
           Create (0.0, -1.0, 1.0, 0.0, 3.0, 0.0);
         Out_R : constant Real_Image := Resample (Src, T, 3, 4);
         Out_G : constant Real_Image := Resample (G, T, 3, 4);
         Rigid : constant Real_Image :=
           Resample (Src, Create_Rigid (AMV.Misc.Pi / 2.0, 3.0, 0.0), 3, 4);
         Ok, Ok_G, Ok_Rigid : Boolean := True;
      begin
         Check (Out_R.Width = 3 and then Out_R.Height = 4, "rotated size");
         for J in 0 .. 3 loop
            for I in 0 .. 2 loop
               Ok := Ok and then Out_R.Get (I, J) = Src.Get (3 - J, I);
               Ok_G := Ok_G and then Out_G.Get (I, J) = Src.Get (3 - J, I);
               Ok_Rigid := Ok_Rigid
                 and then abs (Rigid.Get (I, J) - Src.Get (3 - J, I))
                            <= 1.0E-9;
            end loop;
         end loop;
         Check (Ok, "exact 90 degree rotation (Real_Image)");
         Check (Ok_G, "exact 90 degree rotation (Grey_8)");
         Check (Ok_Rigid, "Create_Rigid (Pi / 2) rotation");
      end;

      --  Points mapped outside the source are clamped like Bilinear.
      declare
         T     : constant Ks_Transform_2D_Linear :=
           Create (1.0, 0.0, 0.0, 1.0, -2.0, -1.5);
         Out_R : constant Real_Image := Resample (Src, T, 8, 6);
         Ok    : Boolean := True;
      begin
         for J in 0 .. 5 loop
            for I in 0 .. 7 loop
               Ok := Ok and then Out_R.Get (I, J)
                 = Bilinear (Src, Real (I) - 2.0, Real (J) - 1.5);
            end loop;
         end loop;
         Check (Ok, "outside points clamped");
         Check (Out_R.Get (0, 0) = Src.Get (0, 0), "far corner clamped");
         Check (Out_R.Get (7, 5) = Src.Get (3, 2), "far corner clamped (2)");
      end;

      --  A general affine map on a large 8-bit image: the windowed
      --  Grey_8 path must agree exactly with point-wise Bilinear, and
      --  with resampling the converted Real_Image.
      declare
         Big   : constant AMV.Images.Ks_Image_8_Grey := Grey_Pattern (60, 50);
         Big_R : constant Real_Image := From_Grey_8 (Big);
         Maps  : constant array (1 .. 4) of Ks_Transform_2D_Linear :=
           [Create (0.83, -0.41, 0.37, 0.91, 20.3, 11.7),
            Create (-1.3, 0.2, -0.15, -0.9, 40.1, 39.6),
            Create (0.25, 0.0, 0.0, 0.25, 58.9, 48.8),
            Create_Similarity (3.0, 0.4, -5.0, -7.0)];
      begin
         for M in Maps'Range loop
            declare
               Out_G : constant Real_Image := Resample (Big, Maps (M), 17, 13);
               Out_R : constant Real_Image :=
                 Resample (Big_R, Maps (M), 17, 13);
               Ok    : Boolean := True;
               X, Y  : Real;
            begin
               for J in 0 .. 12 loop
                  for I in 0 .. 16 loop
                     Maps (M).Map_Point (Real (I), Real (J), X, Y);
                     Ok := Ok and then Out_G.Get (I, J) = Bilinear (Big, X, Y)
                       and then Out_R.Get (I, J) = Out_G.Get (I, J);
                  end loop;
               end loop;
               Check (Ok, "windowed Grey_8 resampling, map" & M'Image);
            end;
         end loop;
      end;

      declare
         None : AMV.Images.Ks_Image_8_Grey;
         procedure Empty_Real is
            R : constant Real_Image :=
              Resample (Create (0, 0), Identity, 2, 2);
         begin
            Check (R.Width = 99, "unreachable");
         end Empty_Real;
         procedure Unallocated is
            R : constant Real_Image := Resample (None, Identity, 2, 2);
         begin
            Check (R.Width = 99, "unreachable");
         end Unallocated;
         procedure Too_Large is
            R : constant Real_Image :=
              Resample (Src, Identity, Positive'Last, 4);
         begin
            Check (R.Width = 99, "unreachable");
         end Too_Large;
         procedure T1 is new Check_Raises_Exactly
           (Empty_Real, Ks_Bad_Parameter_Exception'Identity);
         procedure T2 is new Check_Raises_Exactly
           (Unallocated, Ks_Image_No_Pixels_Exception'Identity);
         procedure T3 is new Check_Raises_Exactly
           (Too_Large, Ks_Bad_Parameter_Exception'Identity);
      begin
         T1 ("Resample of an empty Real_Image");
         T2 ("Resample of an unallocated Grey_8 image");
         T3 ("Resample to a too large output");
      end;
   end Test_Resample;

   ---------------------------------------------------------------------
   --  Filters
   ---------------------------------------------------------------------

   procedure Test_Gaussian is
   begin
      Section ("Gaussian_Smooth");

      --  A constant image stays constant, also when the kernel is wider
      --  than the image.
      declare
         C : constant Real_Image := Create (7, 5, 42.0);
         Sigmas : constant array (1 .. 6) of Real :=
           [0.3, 0.8, 1.5, 3.0, 10.0, 250.0];
      begin
         for S of Sigmas loop
            declare
               Smoothed : constant Real_Image := Gaussian_Smooth (C, S);
               Worst    : Real := 0.0;
            begin
               Check (Smoothed.Width = 7 and then Smoothed.Height = 5,
                      "size kept, sigma" & S'Image);
               for Y in 0 .. 4 loop
                  for X in 0 .. 6 loop
                     Worst := Real'Max
                       (Worst, abs (Smoothed.Get (X, Y) - 42.0));
                  end loop;
               end loop;
               Check_Near (Worst, 0.0, 1.0E-11,
                           "constant stays constant, sigma" & S'Image);
            end;
         end loop;
      end;

      declare
         C        : constant Real_Image := Create (3, 2, -5.5);
         Smoothed : constant Real_Image := Gaussian_Smooth (C, Max_Sigma);
      begin
         Check_Near (Smoothed.Get (2, 1), -5.5, 1.0E-9,
                     "Max_Sigma on a constant image");
         Check_Near (Smoothed.Get (0, 0), -5.5, 1.0E-9,
                     "Max_Sigma on a constant image (2)");
      end;

      --  Impulse response: the sampled, normalised, truncated Gaussian.
      declare
         Sigma   : constant Real := 1.5;
         Radius  : constant := 5;   --  ceiling (4.5)
         Impulse : Real_Image := Create (21, 21);
         G1      : array (-Radius .. Radius) of Real;
         Norm    : Real := 0.0;
         Total   : Real := 0.0;
         Worst   : Real := 0.0;
         Outside_Zero : Boolean := True;
      begin
         Impulse.Set (10, 10, 1.0);
         for K in G1'Range loop
            G1 (K) := EF.Exp (-Real (K * K) / (2.0 * Sigma * Sigma));
            Norm := Norm + G1 (K);
         end loop;
         declare
            Response : constant Real_Image := Gaussian_Smooth (Impulse, Sigma);
         begin
            for Y in 0 .. 20 loop
               for X in 0 .. 20 loop
                  declare
                     V : constant Real := Response.Get (X, Y);
                  begin
                     Total := Total + V;
                     if abs (X - 10) <= Radius and then abs (Y - 10) <= Radius
                     then
                        Worst := Real'Max
                          (Worst,
                           abs (V - G1 (X - 10) * G1 (Y - 10)
                                      / (Norm * Norm)));
                     else
                        Outside_Zero := Outside_Zero and then V = 0.0;
                     end if;
                  end;
               end loop;
            end loop;
            Check_Near (Total, 1.0, 1.0E-12, "impulse response sums to 1");
            Check_Near (Worst, 0.0, 1.0E-15,
                        "impulse response is the sampled Gaussian");
            Check (Outside_Zero, "impulse response zero beyond the radius");
            Check_Near (Response.Get (10, 10), (1.0 / Norm) ** 2, 1.0E-15,
                        "impulse response peak");
            Check_Near (Response.Get (11, 10), Response.Get (9, 10), 0.0,
                        "impulse response symmetric");
         end;
      end;

      --  Against a direct clamped convolution, including kernels wider
      --  than the image and impulses at the border.
      declare
         P      : constant Real_Image := Pattern (13, 9);
         Small  : constant Real_Image := Pattern (5, 4);
         Line   : constant Real_Image := Pattern (11, 1);
         Column : constant Real_Image := Pattern (1, 8);
         Sigmas : constant array (1 .. 6) of Real :=
           [0.2, 0.5, 1.0, 1.7, 2.3, 4.0];
      begin
         for S of Sigmas loop
            Check_Near (Max_Difference (Gaussian_Smooth (P, S),
                                        Reference_Gaussian (P, S)),
                        0.0, 1.0E-12, "13 x 9 vs direct, sigma" & S'Image);
            Check_Near (Max_Difference (Gaussian_Smooth (Small, S),
                                        Reference_Gaussian (Small, S)),
                        0.0, 1.0E-12, "5 x 4 vs direct, sigma" & S'Image);
            Check_Near (Max_Difference (Gaussian_Smooth (Line, S),
                                        Reference_Gaussian (Line, S)),
                        0.0, 1.0E-12, "11 x 1 vs direct, sigma" & S'Image);
            Check_Near (Max_Difference (Gaussian_Smooth (Column, S),
                                        Reference_Gaussian (Column, S)),
                        0.0, 1.0E-12, "1 x 8 vs direct, sigma" & S'Image);
         end loop;
      end;

      declare
         Corner : Real_Image := Create (6, 6);
      begin
         Corner.Set (0, 0, 100.0);
         Check_Near (Max_Difference (Gaussian_Smooth (Corner, 1.0),
                                     Reference_Gaussian (Corner, 1.0)),
                     0.0, 1.0E-12, "corner impulse vs direct");
      end;

      --  The symmetric kernel keeps a linear ramp unchanged away from the
      --  borders.
      declare
         Ramp     : Real_Image := Create (20, 3);
         Smoothed : Real_Image;
         Worst    : Real := 0.0;
      begin
         for Y in 0 .. 2 loop
            for X in 0 .. 19 loop
               Ramp.Set (X, Y, 2.0 * Real (X) - 3.0);
            end loop;
         end loop;
         Smoothed := Gaussian_Smooth (Ramp, 1.2);   --  radius 4
         for Y in 0 .. 2 loop
            for X in 4 .. 15 loop
               Worst := Real'Max
                 (Worst, abs (Smoothed.Get (X, Y) - (2.0 * Real (X) - 3.0)));
            end loop;
         end loop;
         Check_Near (Worst, 0.0, 1.0E-12, "ramp preserved in the interior");
         Check (Smoothed.Get (0, 1) > -3.0, "ramp lifted at the left border");
      end;

      --  Sigma <= 0 (and a sigma so small that the neighbours get zero
      --  weight) give a copy.
      declare
         P : constant Real_Image := Pattern (6, 4);
      begin
         Check (Max_Difference (Gaussian_Smooth (P, 0.0), P) = 0.0,
                "sigma 0 copies");
         Check (Max_Difference (Gaussian_Smooth (P, -2.0), P) = 0.0,
                "negative sigma copies");
         Check (Max_Difference (Gaussian_Smooth (P, 1.0E-3), P) = 0.0,
                "tiny sigma copies");
         Check (Max_Difference (Gaussian_Smooth (P, 1.0E-200), P) = 0.0,
                "extremely small sigma copies");
      end;

      declare
         E : constant Real_Image := Gaussian_Smooth (Create (0, 3), 2.0);
      begin
         Check (E.Width = 0 and then E.Height = 3, "empty image stays empty");
      end;

      declare
         procedure Too_Large is
            R : constant Real_Image :=
              Gaussian_Smooth (Create (2, 2), Max_Sigma * 1.0001);
         begin
            Check (R.Width = 99, "unreachable");
         end Too_Large;
         procedure T1 is new Check_Raises_Exactly
           (Too_Large, Ks_Bad_Parameter_Exception'Identity);
      begin
         T1 ("sigma above Max_Sigma");
      end;
   end Test_Gaussian;

   procedure Test_Box is
   begin
      Section ("Box_Smooth");
      declare
         P      : constant Real_Image := Pattern (11, 7);
         Line   : constant Real_Image := Pattern (6, 1);
         Column : constant Real_Image := Pattern (1, 5);
      begin
         for H in 1 .. 12 loop
            Check_Near (Max_Difference (Box_Smooth (P, H),
                                        Reference_Box (P, H)),
                        0.0, 1.0E-12, "11 x 7 vs brute force, half size"
                                      & H'Image);
            Check_Near (Max_Difference (Box_Smooth (Line, H),
                                        Reference_Box (Line, H)),
                        0.0, 1.0E-12, "6 x 1 vs brute force, half size"
                                      & H'Image);
            Check_Near (Max_Difference (Box_Smooth (Column, H),
                                        Reference_Box (Column, H)),
                        0.0, 1.0E-12, "1 x 5 vs brute force, half size"
                                      & H'Image);
         end loop;
         Check (Max_Difference (Box_Smooth (P, 0), P) = 0.0,
                "half size 0 copies");
      end;

      declare
         Ramp : Real_Image := Create (9, 9);
         R    : Real_Image;
      begin
         for Y in 0 .. 8 loop
            for X in 0 .. 8 loop
               Ramp.Set (X, Y, Real (X));
            end loop;
         end loop;
         R := Box_Smooth (Ramp, 1);
         Check_Near (R.Get (4, 4), 4.0, Tight, "ramp interior");
         Check_Near (R.Get (0, 4), 1.0 / 3.0, Tight,
                     "ramp left border (0, 0, 1) / 3");
         Check_Near (R.Get (8, 0), 23.0 / 3.0, Tight,
                     "ramp right border (7, 8, 8) / 3");
      end;

      declare
         C : constant Real_Image := Create (4, 3, 2.5);
         R : constant Real_Image := Box_Smooth (C, Natural'Last);
      begin
         Check_Near (R.Get (0, 0), 2.5, 1.0E-9, "huge half size, constant");
         Check_Near (R.Get (3, 2), 2.5, 1.0E-9,
                     "huge half size, constant (2)");
      end;

      declare
         E : constant Real_Image := Box_Smooth (Create (3, 0), 2);
      begin
         Check (E.Width = 3 and then E.Height = 0, "empty image stays empty");
      end;

      --  A huge value must not spoil the means of windows it has left.
      --  With plain running sums the ones added while 1E17 was in the
      --  window were lost to rounding, and every later mean along the row
      --  (or column) came out 1/3.
      declare
         Row    : Real_Image := Create (12, 1, 1.0);
         Column : Real_Image := Create (1, 12, 1.0);
      begin
         Row.Set (2, 0, 1.0E17);
         Column.Set (0, 2, 1.0E17);
         declare
            Row_Mean    : constant Real_Image := Box_Smooth (Row, 1);
            Column_Mean : constant Real_Image := Box_Smooth (Column, 1);
         begin
            for I in 4 .. 11 loop
               Check_Near (Row_Mean.Get (I, 0), 1.0, Tight,
                           "row: 1E17 at 2 has left the window of" & I'Image);
               Check_Near (Column_Mean.Get (0, I), 1.0, Tight,
                           "column: 1E17 at 2 has left the window of"
                           & I'Image);
            end loop;
            Check_Near (Row_Mean.Get (2, 0), 1.0E17 / 3.0, 1.0E2,
                        "row: the window holding 1E17");
         end;
      end;

      --  The same in two dimensions, and for fractional data, where plain
      --  running sums lost precision gradually (0.1 with a 1E10 pixel:
      --  relative error 1.5E-8).
      for Case_Index in 1 .. 2 loop
         declare
            Base  : constant Real := (if Case_Index = 1 then 1.0 else 0.1);
            Spike : constant Real :=
              (if Case_Index = 1 then 1.0E17 else 1.0E10);
            Image : Real_Image := Create (16, 16, Base);
            Worst : Real := 0.0;
         begin
            Image.Set (3, 3, Spike);
            declare
               Mean      : constant Real_Image := Box_Smooth (Image, 2);
               Reference : constant Real_Image := Reference_Box (Image, 2);
            begin
               for Y in 0 .. 15 loop
                  for X in 0 .. 15 loop
                     if abs (X - 3) > 2 or else abs (Y - 3) > 2 then
                        Worst := Real'Max
                          (Worst, abs (Mean.Get (X, Y) - Reference.Get (X, Y)));
                     end if;
                  end loop;
               end loop;
            end;
            Check_Near (Worst / Base, 0.0, 1.0E-13,
                        "16 x 16 of" & Real'Image (Base) & " with"
                        & Real'Image (Spike) & " at (3, 3): windows without it");
         end;
      end loop;
   end Test_Box;

   procedure Test_Sobel is
      W : constant := 6;
      H : constant := 5;

      procedure Check_Gradients
        (Image : Real_Image;
         Ex, Ey : Real;           --  expected interior gradient
         Description : String)
      is
         Gx, Gy : Real_Image;
         Ok     : Boolean := True;
      begin
         Sobel (Image, Gx, Gy);
         Check (Gx.Width = W and then Gx.Height = H
                and then Gy.Width = W and then Gy.Height = H,
                Description & ": sizes");
         for Y in 0 .. H - 1 loop
            for X in 0 .. W - 1 loop
               declare
                  Fx : constant Real :=
                    (if X = 0 or X = W - 1 then 0.5 else 1.0);
                  Fy : constant Real :=
                    (if Y = 0 or Y = H - 1 then 0.5 else 1.0);
               begin
                  Ok := Ok
                    and then abs (Gx.Get (X, Y) - Fx * Ex) <= Tight
                    and then abs (Gy.Get (X, Y) - Fy * Ey) <= Tight;
               end;
            end loop;
         end loop;
         Check (Ok, Description & ": values (half slope at the borders)");
         Check_Near (Gx.Get (2, 2), Ex, Tight, Description & ": Gx interior");
         Check_Near (Gy.Get (2, 2), Ey, Tight, Description & ": Gy interior");
      end Check_Gradients;

      function Plane (A, B, C : Real) return Real_Image is
         Result : Real_Image := Create (W, H);
      begin
         for Y in 0 .. H - 1 loop
            for X in 0 .. W - 1 loop
               Result.Set (X, Y, A * Real (X) + B * Real (Y) + C);
            end loop;
         end loop;
         return Result;
      end Plane;
   begin
      Section ("Sobel");
      Check_Gradients (Plane (1.0, 0.0, 0.0), 1.0, 0.0, "unit ramp in x");
      Check_Gradients (Plane (0.0, 1.0, 0.0), 0.0, 1.0, "unit ramp in y");
      Check_Gradients (Plane (3.0, 0.0, 5.0), 3.0, 0.0, "ramp 3x + 5");
      Check_Gradients (Plane (2.0, -3.0, 7.0), 2.0, -3.0, "plane 2x - 3y");
      Check_Gradients (Create (W, H, 9.0), 0.0, 0.0, "constant");

      --  Impulse of 8 at (2, 2): hand-computed responses.
      declare
         Imp    : Real_Image := Create (5, 5);
         Gx, Gy : Real_Image;
      begin
         Imp.Set (2, 2, 8.0);
         Sobel (Imp, Gx, Gy);
         Check_Near (Gx.Get (1, 2), 2.0, Tight, "impulse Gx left");
         Check_Near (Gx.Get (3, 2), -2.0, Tight, "impulse Gx right");
         Check_Near (Gx.Get (1, 1), 1.0, Tight, "impulse Gx upper left");
         Check_Near (Gx.Get (3, 3), -1.0, Tight, "impulse Gx lower right");
         Check_Near (Gx.Get (2, 2), 0.0, Tight, "impulse Gx centre");
         Check_Near (Gx.Get (2, 1), 0.0, Tight, "impulse Gx above");
         Check_Near (Gy.Get (2, 1), 2.0, Tight, "impulse Gy above");
         Check_Near (Gy.Get (2, 3), -2.0, Tight, "impulse Gy below");
         Check_Near (Gy.Get (1, 1), 1.0, Tight, "impulse Gy upper left");
         Check_Near (Gy.Get (3, 3), -1.0, Tight, "impulse Gy lower right");
         Check_Near (Gy.Get (0, 0), 0.0, Tight, "impulse Gy far corner");
      end;

      declare
         One    : constant Real_Image := Create (1, 1, 5.0);
         Gx, Gy : Real_Image;
      begin
         Sobel (One, Gx, Gy);
         Check (Gx.Width = 1 and then Gx.Get (0, 0) = 0.0
                and then Gy.Get (0, 0) = 0.0, "1 x 1 image");
      end;

      --  The outputs may be the same object as the input.
      declare
         A, B : Real_Image := Plane (1.5, 0.0, 2.0);
      begin
         Sobel (A, A, B);
         Check_Near (A.Get (3, 3), 1.5, Tight, "Gx aliased with input");
         Check_Near (B.Get (3, 3), 0.0, Tight, "Gy beside aliased Gx");
      end;

      declare
         Gx : Real_Image := Create (2, 2, 1.0);
         Gy : Real_Image := Create (3, 3, 1.0);
      begin
         Sobel (Create (0, 0), Gx, Gy);
         Check (Gx.Width = 0 and then Gy.Width = 0,
                "empty input gives empty outputs");
      end;
   end Test_Sobel;

   procedure Test_Downsample is
   begin
      Section ("Downsample_2");
      declare
         --  4 x 4 with value X + 4 Y.
         P : Real_Image := Create (4, 4);
         D : Real_Image;
      begin
         for Y in 0 .. 3 loop
            for X in 0 .. 3 loop
               P.Set (X, Y, Real (X + 4 * Y));
            end loop;
         end loop;
         D := Downsample_2 (P);
         Check (D.Width = 2 and then D.Height = 2, "4 x 4 -> 2 x 2");
         Check_Near (D.Get (0, 0), (0.0 + 1.0 + 4.0 + 5.0) / 4.0, Tight,
                     "block (0, 0)");
         Check_Near (D.Get (1, 0), (2.0 + 3.0 + 6.0 + 7.0) / 4.0, Tight,
                     "block (1, 0)");
         Check_Near (D.Get (0, 1), (8.0 + 9.0 + 12.0 + 13.0) / 4.0, Tight,
                     "block (0, 1)");
         Check_Near (D.Get (1, 1), 12.5, Tight, "block (1, 1)");
         --  The value at output (I, J) equals the input sample at
         --  (2I + 0.5, 2J + 0.5) for this linear image.
         Check_Near (D.Get (1, 1), Bilinear (P, 2.5, 2.5), Tight,
                     "block centre at (2I + 0.5, 2J + 0.5)");
      end;

      declare
         --  5 x 3: the last column and the last row are dropped.
         P : Real_Image := Create (5, 3);
         D : Real_Image;
      begin
         for Y in 0 .. 2 loop
            for X in 0 .. 4 loop
               P.Set (X, Y, Real (X * X + 10 * Y));
            end loop;
         end loop;
         P.Set (4, 0, 1000.0);
         P.Set (0, 2, 1000.0);
         D := Downsample_2 (P);
         Check (D.Width = 2 and then D.Height = 1, "5 x 3 -> 2 x 1");
         Check_Near (D.Get (0, 0), (0.0 + 1.0 + 10.0 + 11.0) / 4.0, Tight,
                     "odd size block (0, 0)");
         Check_Near (D.Get (1, 0), (4.0 + 9.0 + 14.0 + 19.0) / 4.0, Tight,
                     "odd size block (1, 0)");
      end;

      declare
         Single : constant Real_Image := Downsample_2 (Create (1, 1, 3.25));
      begin
         Check (Single.Width = 1 and then Single.Height = 1
                and then Single.Get (0, 0) = 3.25, "1 x 1 -> 1 x 1");
      end;

      declare
         Column : Real_Image := Create (1, 4);
         D      : Real_Image;
      begin
         for Y in 0 .. 3 loop
            Column.Set (0, Y, Real (Y * Y));
         end loop;
         D := Downsample_2 (Column);
         Check (D.Width = 1 and then D.Height = 2, "1 x 4 -> 1 x 2");
         Check_Near (D.Get (0, 0), 0.5, Tight, "column pair (0, 1)");
         Check_Near (D.Get (0, 1), 6.5, Tight, "column pair (4, 9)");
      end;

      declare
         Row : Real_Image := Create (3, 1);
         D   : Real_Image;
      begin
         Row.Set (0, 0, 2.0);
         Row.Set (1, 0, 6.0);
         Row.Set (2, 0, 100.0);
         D := Downsample_2 (Row);
         Check (D.Width = 1 and then D.Height = 1, "3 x 1 -> 1 x 1");
         Check_Near (D.Get (0, 0), 4.0, Tight, "row pair, third dropped");
      end;

      declare
         Two : Real_Image := Create (2, 2);
         D   : Real_Image;
      begin
         Two.Set (0, 0, 1.0);
         Two.Set (1, 0, 2.0);
         Two.Set (0, 1, 3.0);
         Two.Set (1, 1, 6.0);
         D := Downsample_2 (Two);
         Check (D.Width = 1 and then D.Height = 1
                and then D.Get (0, 0) = 3.0, "2 x 2 -> 1 x 1");
      end;

      declare
         D7 : constant Real_Image := Downsample_2 (Pattern (7, 6));
         D2 : constant Real_Image := Downsample_2 (Pattern (2, 9));
         D9 : constant Real_Image := Downsample_2 (Pattern (9, 1));
      begin
         Check (D7.Width = 3 and then D7.Height = 3, "7 x 6 -> 3 x 3");
         Check (D2.Width = 1 and then D2.Height = 4, "2 x 9 -> 1 x 4");
         Check (D9.Width = 4 and then D9.Height = 1, "9 x 1 -> 4 x 1");
         Check_Near (D9.Get (3, 0),
                     0.5 * (Pattern_Value (6, 0) + Pattern_Value (7, 0)),
                     Tight, "9 x 1 last pair");
         Check_Near (D7.Get (2, 2),
                     0.25 * (Pattern_Value (4, 4) + Pattern_Value (5, 4)
                             + Pattern_Value (4, 5) + Pattern_Value (5, 5)),
                     Tight, "7 x 6 last block");
      end;

      declare
         E : constant Real_Image := Downsample_2 (Create (0, 4));
      begin
         Check (E.Width = 0 and then E.Height = 4, "empty image stays empty");
      end;
   end Test_Downsample;

   procedure Test_Statistics is
      Mean, Std, Lo, Hi : Real;
   begin
      Section ("Statistics");
      declare
         P : Real_Image := Create (2, 2);
      begin
         P.Set (0, 0, 4.0);   --  maximum first
         P.Set (1, 0, 2.0);
         P.Set (0, 1, 1.0);
         P.Set (1, 1, 3.0);
         Statistics (P, Mean, Std, Lo, Hi);
         Check_Near (Mean, 2.5, Tight, "mean");
         Check_Near (Std, EF.Sqrt (1.25), Tight, "population std dev");
         Check (Lo = 1.0 and then Hi = 4.0, "minimum and maximum");
      end;

      Statistics (Create (3, 3, -2.0), Mean, Std, Lo, Hi);
      Check (Mean = -2.0 and then Std = 0.0 and then Lo = -2.0
             and then Hi = -2.0, "constant image");

      Statistics (Create (1, 1, 7.0), Mean, Std, Lo, Hi);
      Check (Mean = 7.0 and then Std = 0.0 and then Lo = 7.0
             and then Hi = 7.0, "single pixel");

      declare
         --  Values 1E9 + 0, 1, 2, 3, 4: std dev sqrt (2), no cancellation.
         P : Real_Image := Create (5, 1);
      begin
         for X in 0 .. 4 loop
            P.Set (X, 0, 1.0E9 + Real (X));
         end loop;
         Statistics (P, Mean, Std, Lo, Hi);
         Check_Near (Mean, 1.0E9 + 2.0, 1.0E-6, "large offset mean");
         Check_Near (Std, EF.Sqrt (2.0), 1.0E-6, "large offset std dev");
         Check (Lo = 1.0E9 and then Hi = 1.0E9 + 4.0,
                "large offset minimum and maximum");
      end;

      declare
         procedure Empty_Image is
            M, S, A, B : Real;
         begin
            Statistics (Create (0, 2), M, S, A, B);
            Check (M = S and then A = B, "unreachable");
         end Empty_Image;
         procedure T1 is new Check_Raises_Exactly
           (Empty_Image, Ks_Bad_Parameter_Exception'Identity);
      begin
         T1 ("Statistics of an empty image");
      end;
   end Test_Statistics;

   ---------------------------------------------------------------------
   --  Very wide images in a task with a small stack
   ---------------------------------------------------------------------

   procedure Test_Wide_Images is
      --  An image 3_000_000 pixels wide is legal. From_Grey_8 and
      --  To_Grey_8 used to declare a row buffer as wide as the image on the
      --  stack (Resample reached it through From_Grey_8, even for a tiny
      --  window), which overflows any small stack. The operations run in a
      --  task with a 256 KB stack, so the test means the same on every
      --  platform. Should the defect come back, the stack overflow may kill
      --  the whole process (as it does on macOS) instead of failing a check.
      Wide        : constant := 3_000_000;
      Grey        : AMV.Images.Ks_Image_8_Grey := AMV.Images.Create (Wide, 2, 5);
      Real_Source : constant Real_Image := Create (Wide, 1, 9.4);
      Whole_Ok, Window_Ok, To_Grey_Ok, Resample_Ok : Boolean := False;
      Raised      : Boolean := False;
   begin
      Section ("wide images on a small stack");
      Grey.Set_Pixel (Wide - 1, 1, 42);
      declare
         task Worker with Storage_Size => 256 * 1024;

         task body Worker is
         begin
            declare
               R : constant Real_Image := From_Grey_8 (Grey);
            begin
               Whole_Ok := R.Width = Wide and then R.Height = 2
                 and then R.Get (0, 0) = 5.0
                 and then R.Get (Wide - 1, 1) = 42.0;
            end;
            declare
               R : constant Real_Image := From_Grey_8 (Grey, Wide - 1, 1, 1, 1);
            begin
               Window_Ok := R.Width = 1 and then R.Height = 1
                 and then R.Get (0, 0) = 42.0;
            end;
            declare
               G : constant AMV.Images.Ks_Image_8_Grey :=
                 To_Grey_8 (Real_Source);
            begin
               To_Grey_Ok := G.Width = Wide and then G.Height = 1
                 and then G.Get_Pixel (0, 0) = 9
                 and then G.Get_Pixel (Wide - 1, 0) = 9;
            end;
            declare
               R : constant Real_Image :=
                 Resample (Grey, AMV.Transforms.Identity, 4, 1);
            begin
               Resample_Ok := R.Width = 4 and then R.Get (3, 0) = 5.0;
            end;
         exception
            when others =>
               Raised := True;
         end Worker;
      begin
         null;   --  waits here for Worker to finish
      end;
      Check (not Raised, "no exception (stack overflow) in the task");
      Check (Whole_Ok, "From_Grey_8 of a 3_000_000 x 2 image");
      Check (Window_Ok, "From_Grey_8 of a 1 x 1 window of it");
      Check (To_Grey_Ok, "To_Grey_8 of a 3_000_000 x 1 Real_Image");
      Check (Resample_Ok, "Resample of a 3_000_000 x 2 image to 4 x 1");
   end Test_Wide_Images;

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   procedure Test_Streams is
      package Storage renames Ada.Streams.Storage.Unbounded;
      use type Ada.Streams.Stream_Element_Count;
      use type Interfaces.Unsigned_32;

      type Bits_List is array (Positive range <>) of Interfaces.Unsigned_64;

      function Format_Code return Interfaces.Unsigned_32;
      --  The code a Real_Image starts with, as 'Write produces it.

      function Format_Code return Interfaces.Unsigned_32 is
         S    : aliased Storage.Stream_Type;
         Code : Interfaces.Unsigned_32;
      begin
         Real_Image'Write (S'Access, Create (1, 1));
         Interfaces.Unsigned_32'Read (S'Access, Code);
         return Code;
      end Format_Code;

      procedure Corrupt
        (Description         : String;
         Code, Width, Height : Interfaces.Unsigned_32;
         Values              : Bits_List);
      --  A hand-made stream must be rejected with Ks_Image_File_Exception,
      --  and the target must keep its value.

      procedure Corrupt
        (Description         : String;
         Code, Width, Height : Interfaces.Unsigned_32;
         Values              : Bits_List)
      is
         S      : aliased Storage.Stream_Type;
         Target : Real_Image := Create (2, 1, 3.5);
         procedure Read_Target is
         begin
            Real_Image'Read (S'Access, Target);
         end Read_Target;
         procedure Run is new Check_Raises_Exactly
           (Read_Target, Ks_Image_File_Exception'Identity);
      begin
         Interfaces.Unsigned_32'Write (S'Access, Code);
         Interfaces.Unsigned_32'Write (S'Access, Width);
         Interfaces.Unsigned_32'Write (S'Access, Height);
         for V of Values loop
            Interfaces.Unsigned_64'Write (S'Access, V);
         end loop;
         Run (Description);
         Check (Target.Width = 2 and then Target.Height = 1
                and then Target.Get (0, 0) = 3.5
                and then Target.Get (1, 0) = 3.5,
                Description & ": the target keeps its value");
      end Corrupt;

      One_Bits : constant Interfaces.Unsigned_64 := 16#3FF0_0000_0000_0000#;
   begin
      Section ("Real_Image streams");
      --  By value: the default attributes wrote the buffer's address (16
      --  bytes in all) and read it back as a second owner of the buffer.
      declare
         S : aliased Storage.Stream_Type;
         A : constant Real_Image := Pattern (5, 3);
      begin
         Real_Image'Write (S'Access, A);
         Check (Storage.Element_Count (S) = 3 * 4 + 15 * 8,
                "'Write stores the size and every pixel value");
         declare
            B : Real_Image := Create (2, 2, 7.0);   --  has its own buffer
         begin
            Real_Image'Read (S'Access, B);
            Check (B.Width = 5 and then B.Height = 3
                   and then Max_Difference (A, B) = 0.0,
                   "'Read gives back the same image");
            B.Set (0, 0, -1.0);
            Check (A.Get (0, 0) = Pattern_Value (0, 0),
                   "the image read back does not share the source's pixels");
         end;
         --  The copy read back has been finalized; new allocations must
         --  not land on the source's buffer.
         declare
            Churn : array (1 .. 16) of Real_Image;
         begin
            for C of Churn loop
               C := Create (5, 3, 99.0);
            end loop;
            Check (Max_Difference (A, Pattern (5, 3)) = 0.0,
                   "the source is intact after the copy is finalized");
         end;
      end;

      declare
         S : aliased Storage.Stream_Type;
         A : constant Real_Image := Pattern (4, 2);
      begin
         Real_Image'Output (S'Access, A);
         Real_Image'Class'Output (S'Access, A);
         Real_Image'Output (S'Access, Create (0, 5));
         declare
            B : constant Real_Image := Real_Image'Input (S'Access);
            C : constant Real_Image'Class := Real_Image'Class'Input (S'Access);
            E : constant Real_Image := Real_Image'Input (S'Access);
         begin
            Check (Max_Difference (A, B) = 0.0, "'Output and 'Input");
            Check (Max_Difference (A, Real_Image (C)) = 0.0,
                   "Real_Image'Class'Output and 'Input");
            Check (E.Width = 0 and then E.Height = 5,
                   "an image with a size but no pixels keeps its size");
            Check (Storage.Element_Count (S) = 0, "the stream is used up");
         end;
      end;

      Corrupt ("wrong format code", Format_Code + 1, 1, 1, [1 => One_Bits]);
      Corrupt ("width beyond Natural'Last", Format_Code, 16#8000_0000#, 1,
               [1 => One_Bits]);
      Corrupt ("Width * Height beyond Natural'Last", Format_Code,
               65_536, 65_536, [1 => One_Bits]);
      --  1E9 values promised, 3 present: the buffer only grows as values
      --  arrive, so this does not allocate 8 GB first.
      Corrupt ("stream ends early", Format_Code, 40_000, 25_000,
               [One_Bits, One_Bits, One_Bits]);
      Corrupt ("a NaN value", Format_Code, 2, 1,
               [One_Bits, 16#7FF8_0000_0000_0000#]);
      Corrupt ("an infinite value", Format_Code, 2, 1,
               [16#FFF0_0000_0000_0000#, One_Bits]);
      Corrupt ("no pixels at all", Format_Code, 2, 1, [1 .. 0 => 0]);
   end Test_Streams;

   procedure Run_All is
   begin
      Test_Basics;
      Test_From_Grey_8;
      Test_To_Grey_8;
      Test_Bilinear;
      Test_Resample;
      Test_Gaussian;
      Test_Box;
      Test_Sobel;
      Test_Downsample;
      Test_Statistics;
      Test_Wide_Images;
      Test_Streams;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Image_Math;
