--  Tests on real images: open camera photos and printed targets, downloaded
--  and converted to BMP by tools/fetch_real_images.sh (make
--  test-real-images). Their sources, licences and checksums are in
--  tests/real_images/images.txt; how each expected value was obtained (most
--  are measured by eye, since the images come without ground truth) is in
--  tests/real_images/README.md.
--
--  The images are read from the directory named by the environment
--  variable AMV_REAL_IMAGES, build/real-images by default. A missing image
--  is a failure that says to run make fetch-real-images.
--
--  JPEG decoders differ slightly between converters (sips, ImageMagick),
--  so every tolerance leaves room for a grey level or so of difference.

pragma Validity_Checks ("F");

with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Exceptions;
with Ada.Numerics;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Text_IO;

with AMV;                                    use AMV;
with AMV.Blob;
with AMV.Calib_Fix;
with AMV.Caliper;
with AMV.Caliper.Find_Circle;
with AMV.Caliper.Find_Line;
with AMV.CNL_Search;
with AMV.Dimensioning;
with AMV.Image_File;
with AMV.Image_Processing.Affine_Transform;
with AMV.Image_Processing.IP_One_Image;
with AMV.Image_Processing.Polar_Unwrap;
with AMV.Image_Processing.Sharpness;
with AMV.Images;                             use AMV.Images;
with AMV.Kernels;
with AMV.Misc;
with AMV.PM_Align;
with AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;                              use AMV.Tools;
with AMV.Transforms;
with AMV_Test_Support;                       use AMV_Test_Support;

procedure Test_Real_Images is

   package EF renames Ada.Numerics.Long_Elementary_Functions;

   use type AMV.Kernels.Int32;

   ---------------------------------------------------------------------
   --  Loading
   ---------------------------------------------------------------------

   function Directory return String is
     (if Ada.Environment_Variables.Exists ("AMV_REAL_IMAGES")
      then Ada.Environment_Variables.Value ("AMV_REAL_IMAGES")
      else "build/real-images");

   Missing : exception;

   function Load (Name : String) return Ks_Image_8_Grey;
   --  The image Name (without extension) as 8-bit grey. Raises Missing,
   --  after a failure that names the file, when it is not there.

   function Load (Name : String) return Ks_Image_8_Grey is
      File_Name : constant String := Directory & "/" & Name & ".bmp";
   begin
      if not Ada.Directories.Exists (File_Name) then
         Fail (File_Name & " is missing: run make fetch-real-images");
         raise Missing;
      end if;
      return AMV.Image_File.Read_Image_8_Grey (File_Name);
   end Load;

   type Point is record
      X, Y : Real;
   end record;

   function Distance (A, B : Point) return Real is
     (EF.Sqrt ((A.X - B.X) ** 2 + (A.Y - B.Y) ** 2));

   ---------------------------------------------------------------------
   --  Reading: every image, with its size
   ---------------------------------------------------------------------

   procedure Test_Reading is
      procedure Size (Name : String; Width, Height : Positive) is
         Image : constant Ks_Image_8_Grey := Load (Name);
      begin
         Check (Image.Width = Width and then Image.Height = Height,
                Name & ": size" & Width'Image & " x" & Height'Image);
      end Size;
   begin
      Section ("Reading the converted images");
      for N in 1 .. 14 loop
         if N /= 10 then
            Size ("left" & (if N < 10 then "0" else "")
                  & Integer'Image (N) (2 .. Integer'Image (N)'Last),
                  640, 480);
         end if;
      end loop;
      Size ("chessboard", 1754, 1240);
      Size ("box", 324, 223);
      Size ("box_in_scene", 512, 384);
      Size ("smarties", 413, 356);
      Size ("gauge-1", 269, 267);
      Size ("coins", 384, 303);
   end Test_Reading;

   ---------------------------------------------------------------------
   --  Blob: the 24 coins of coins.png
   ---------------------------------------------------------------------

   --  The centres of the 24 coins, row by row, measured by eye (+/- 3
   --  pixels).
   Coin_Centres : constant array (1 .. 24) of Point :=
     [(45.0, 53.0), (100.0, 56.0), (155.0, 51.0), (215.0, 51.0),
      (276.0, 52.0), (335.0, 44.0),
      (45.0, 124.0), (102.0, 126.0), (154.0, 127.0), (205.0, 124.0),
      (271.0, 119.0), (336.0, 125.0),
      (43.0, 197.0), (102.0, 196.0), (154.0, 198.0), (212.0, 193.0),
      (274.0, 193.0), (347.0, 186.0),
      (46.0, 260.0), (114.0, 266.0), (172.0, 261.0), (244.0, 263.0),
      (301.0, 263.0), (358.0, 268.0)];

   procedure Test_Coins is
      use AMV.Blob;
      use AMV.Image_Processing.IP_One_Image;
      IP   : Ks_IP_One_Image_Tool;
      Hat  : Ks_IP_One_Image_Operator := New_Operator (Grey_Morphology_NxM);
      Tool : Ks_Blob_Tool;
   begin
      Section ("Blob: coins.png (top-hat, then a fixed threshold)");

      --  The background is brighter at the top than at the bottom, so a
      --  single threshold of the raw image merges a coin with it. A
      --  top-hat (the image minus its grey opening by a square larger than
      --  any coin) flattens the background first.
      IP.Input_Image := Load ("coins");
      Hat.Grey_Morphology_NxM.Operation := Code (Original_Minus_Open);
      Hat.Grey_Morphology_NxM.Kernel_Width := 75;
      Hat.Grey_Morphology_NxM.Kernel_Height := 75;
      Add (IP.Operators, Hat);
      IP.Run;
      Check (IP.Run_Status.Result = Accept_Result, "top-hat accepted");

      Tool.Input_Image := IP.Output_Image;
      Tool.Run_Params.Segmentation_Params.Polarity := Code (Light_Blobs);
      Tool.Run_Params.Segmentation_Params.Mode := Code (Hard_Fixed_Threshold);
      Tool.Run_Params.Segmentation_Params.Hard_Fixed_Threshold := 60;
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (AMV.Blob.Area, Filter, Include_Blobs_In_Range,
                         600.0, 6000.0));
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (Elongation, Filter, Include_Blobs_In_Range,
                         1.0, 1.6));
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "blob accepted");

      declare
         Coins : constant Ks_Blob_Result_Collection'Class :=
           Tool.Results.Get_Blobs;
         Hits  : Natural;
      begin
         Check (Coins.Count = 24, "24 coins (found" & Coins.Count'Image & ")");
         for C of Coin_Centres loop
            Hits := 0;
            for I in 0 .. Coins.Count - 1 loop
               if Distance ((Coins.Item (I).Center_Of_Mass_X,
                             Coins.Item (I).Center_Of_Mass_Y), C) <= 6.0
               then
                  Hits := Hits + 1;
               end if;
            end loop;
            Check (Hits = 1,
                   "one coin at" & Integer (C.X)'Image & ","
                   & Integer (C.Y)'Image);
         end loop;
      end;
   end Test_Coins;

   ---------------------------------------------------------------------
   --  Blob: smarties.png
   ---------------------------------------------------------------------

   procedure Test_Smarties is
      use AMV.Blob;
      Tool : Ks_Blob_Tool;
   begin
      Section ("Blob: smarties.png (dark sweets on white)");

      --  14 sweets: two touch each other (one blob), and four touch the
      --  border of the image (two of them are only partly in it); the
      --  other eight are single round blobs.
      Tool.Input_Image := Load ("smarties");
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (AMV.Blob.Area, Filter, Include_Blobs_In_Range,
                         300.0, 1.0E9));
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "blob accepted");

      declare
         Blobs   : constant Ks_Blob_Result_Collection'Class :=
           Tool.Results.Get_Blobs;
         Pairs   : Natural := 0;
         Clipped : Natural := 0;
         Round   : Natural := 0;
      begin
         Check (Blobs.Count = 13, "13 blobs (found" & Blobs.Count'Image & ")");
         for I in 0 .. Blobs.Count - 1 loop
            declare
               B : constant Ks_Blob_Result := Blobs.Item (I);
            begin
               if B.Not_Clipped = 0 then
                  Clipped := Clipped + 1;
               elsif B.Area > 4000.0 then
                  Pairs := Pairs + 1;
                  Check (Distance ((B.Center_Of_Mass_X, B.Center_Of_Mass_Y),
                                   (125.0, 265.0)) <= 8.0,
                         "the touching pair at (125, 265)");
               elsif B.Area in 1900.0 .. 2700.0 and then B.Elongation < 1.4
               then
                  Round := Round + 1;
               end if;
            end;
         end loop;
         Check (Clipped = 4, "four sweets touch the border (found"
                & Clipped'Image & ")");
         Check (Pairs = 1, "one touching pair (found" & Pairs'Image & ")");
         Check (Round = 8, "eight single round sweets (found"
                & Round'Image & ")");
      end;
   end Test_Smarties;

   ---------------------------------------------------------------------
   --  Find Circle: the dial of gauge-1.jpg
   ---------------------------------------------------------------------

   procedure Test_Gauge is
      use AMV.Caliper;
      use AMV.Caliper.Find_Circle;

      --  The edge of the white dial face, measured from its extent (x
      --  28.5 .. 222.5, y 39.5 .. 229.5; the photo is not quite square on,
      --  so the dial is a slightly flattened circle).
      Centre : constant Point := (125.5, 134.5);
      Radius : constant := 96.0;

      Found  : array (1 .. 3) of AMV.Shapes.Ks_Circle;
      Starts : constant array (1 .. 3) of Point :=
        [(125.0, 140.0), (120.0, 135.0), (130.0, 145.0)];
      Start_Radius : constant array (1 .. 3) of Real := [100.0, 95.0, 105.0];
   begin
      Section ("Find Circle: gauge-1.jpg (the dial face)");
      for N in Starts'Range loop
         declare
            Tool : Ks_Find_Circle_Tool;
         begin
            Tool.Input_Image := Load ("gauge-1");
            Tool.Run_Params.Expected_Circular_Arc
              .Set_Center_Radius_Angle_Start_Angle_Span
                (Starts (N).X, Starts (N).Y, Start_Radius (N), 0.0,
                 2.0 * Ada.Numerics.Pi);
            Tool.Run_Params.Num_Calipers := 36;
            Tool.Run_Params.Caliper_Search_Length := 40.0;
            Tool.Run_Params.Caliper_Search_Direction := Outward;
            Tool.Run_Params.Num_To_Ignore := 6;
            Tool.Run_Params.Caliper_Run_Params.Edge_0_Polarity :=
              Code (Light_To_Dark);
            Tool.Run_Params.Caliper_Run_Params.Contrast_Threshold := 20.0;
            Tool.Run;
            Check (Tool.Run_Status.Result = Accept_Result,
                   "start" & N'Image & ": accepted");
            Found (N) := Tool.Results.Get_Circle;
            Check (Distance ((Found (N).Center_X, Found (N).Center_Y),
                             Centre) <= 2.0,
                   "start" & N'Image & ": centre");
            Check_Near (Found (N).Radius, Radius, 2.0,
                        "start" & N'Image & ": radius");
            Check (Tool.Results.Num_Points_Found = 36,
                   "start" & N'Image & ": every caliper found the edge");
         end;
      end loop;
      --  The dial, photographed slightly obliquely, is a little elliptical:
      --  calipers placed from another start meet other parts of its edge,
      --  which moves the fitted circle by up to about 1 px (0.8 px with
      --  sips's JPEG decoder, a little more with ImageMagick's).
      for N in 2 .. 3 loop
         Check (Distance ((Found (N).Center_X, Found (N).Center_Y),
                          (Found (1).Center_X, Found (1).Center_Y)) <= 1.5
                and then abs (Found (N).Radius - Found (1).Radius) <= 1.0,
                "start" & N'Image & ": the same circle as start 1");
      end loop;
   end Test_Gauge;

   ---------------------------------------------------------------------
   --  PMAlign: box.png
   ---------------------------------------------------------------------

   function Trained_Box return AMV.PM_Align.Ks_PM_Align_Pattern;
   --  A pattern trained on the whole of box.png, its origin at the centre
   --  of the image.

   function Trained_Box return AMV.PM_Align.Ks_PM_Align_Pattern is
      Model : constant Ks_Image_8_Grey := Load ("box");
   begin
      return Pattern : AMV.PM_Align.Ks_PM_Align_Pattern do
         Pattern.Set_Train_Image (Model);
         Pattern.Set_Origin
           (AMV.Transforms.Create_Rigid
              (0.0, Real (Model.Width - 1) / 2.0,
               Real (Model.Height - 1) / 2.0));
         Pattern.Train;
      end return;
   end Trained_Box;

   procedure Test_Box_Self is
      use AMV.PM_Align;
      Tool : Ks_PM_Align_Tool;
   begin
      Section ("PMAlign: box.png in itself");

      --  A pattern found in its own train image should score close to 1:
      --  every trained feature is there, and nothing else is.
      Tool.Pattern := Trained_Box;
      Tool.Input_Image := Load ("box");
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "accepted");
      Check (Tool.Results.Count = 1, "found");
      if Tool.Results.Count = 1 then
         declare
            R : constant Ks_PM_Align_Result := Tool.Results.Item (0);
         begin
            Check_Near (R.Translation_X, 161.5, 0.05, "x");
            Check_Near (R.Translation_Y, 111.0, 0.05, "y");
            Check_Near (R.Coverage, 1.0, 0.02, "coverage");
            Check (R.Score >= 0.9, "score >= 0.9 (score"
                   & Integer (R.Score * 1000.0)'Image & "e-3, clutter"
                   & Integer (R.Clutter * 1000.0)'Image & "e-3)");
         end;
      end if;
   end Test_Box_Self;

   procedure Test_Box_In_Scene is
      use AMV.PM_Align;
      Tool : Ks_PM_Align_Tool;
   begin
      Section ("PMAlign: box.png in box_in_scene.png");

      --  The box lies among other packets, about half its size, turned by
      --  a few degrees and seen in perspective (which a similarity pose
      --  cannot follow, hence the low threshold). Its centre, measured by
      --  eye from its corners, is near (184, 225).
      Tool.Pattern := Trained_Box;
      Tool.Input_Image := Load ("box_in_scene");
      Tool.Run_Params.Zone_Angle.Configuration := Code (Low_High);
      Tool.Run_Params.Zone_Angle.Low := -Ada.Numerics.Pi;
      Tool.Run_Params.Zone_Angle.High := Ada.Numerics.Pi;
      Tool.Run_Params.Zone_Scale.Configuration := Code (Low_High);
      Tool.Run_Params.Zone_Scale.Low := 0.4;
      Tool.Run_Params.Zone_Scale.High := 1.0;
      Tool.Run_Params.Accept_Threshold := 0.15;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "accepted");
      Check (Tool.Results.Count = 1, "found");
      if Tool.Results.Count = 1 then
         declare
            R : constant Ks_PM_Align_Result := Tool.Results.Item (0);
         begin
            Check (Distance ((R.Translation_X, R.Translation_Y),
                             (184.0, 225.0)) <= 6.0, "position");
            Check_Near (AMV.Misc.Rad_To_Deg (R.Rotation), 8.0, 5.0, "angle");
            Check_Near (R.Scaling, 0.54, 0.05, "scale");
         end;
      end if;
   end Test_Box_In_Scene;

   ---------------------------------------------------------------------
   --  Checkerboard calibration: OpenCV's left01 .. left14 and chessboard
   ---------------------------------------------------------------------

   type Corner_List is array (Positive range <>) of Point;
   type Index_List is array (Positive range <>) of Integer;

   function Homography_RMS
     (Pixel  : Corner_List;
      I, J   : Index_List;
      Scale  : Real) return Real;
   --  The RMS distance (pixels) between the corners and the best
   --  homography of their grid indices (8 parameters, the algebraic least
   --  squares fit on pixel coordinates divided by Scale).

   function Affine_RMS (Pixel : Corner_List; I, J : Index_List) return Real;
   --  The RMS distance (pixels) between the corners and the least squares
   --  affine map of their grid indices.

   function Affine_RMS (Pixel : Corner_List; I, J : Index_List) return Real
   is
      type M3 is array (1 .. 3, 1 .. 3) of Real;
      type V3 is array (1 .. 3) of Real;

      function Det (A : M3) return Real is
        (A (1, 1) * (A (2, 2) * A (3, 3) - A (2, 3) * A (3, 2))
         - A (1, 2) * (A (2, 1) * A (3, 3) - A (2, 3) * A (3, 1))
         + A (1, 3) * (A (2, 1) * A (3, 2) - A (2, 2) * A (3, 1)));

      function Solve (A : M3; B : V3) return V3 is
         D : constant Real := Det (A);
         R : V3;
      begin
         for K in 1 .. 3 loop
            declare
               T : M3 := A;
            begin
               for Row in 1 .. 3 loop
                  T (Row, K) := B (Row);
               end loop;
               R (K) := Det (T) / D;
            end;
         end loop;
         return R;
      end Solve;

      A      : M3 := [others => [others => 0.0]];
      BX, BY : V3 := [others => 0.0];
      Sum    : Real := 0.0;
   begin
      for K in Pixel'Range loop
         declare
            G : constant V3 := [Real (I (K)), Real (J (K)), 1.0];
         begin
            for Row in 1 .. 3 loop
               for Col in 1 .. 3 loop
                  A (Row, Col) := A (Row, Col) + G (Row) * G (Col);
               end loop;
               BX (Row) := BX (Row) + G (Row) * Pixel (K).X;
               BY (Row) := BY (Row) + G (Row) * Pixel (K).Y;
            end loop;
         end;
      end loop;
      declare
         FX : constant V3 := Solve (A, BX);
         FY : constant V3 := Solve (A, BY);
      begin
         for K in Pixel'Range loop
            Sum := Sum
              + (FX (1) * Real (I (K)) + FX (2) * Real (J (K)) + FX (3)
                 - Pixel (K).X) ** 2
              + (FY (1) * Real (I (K)) + FY (2) * Real (J (K)) + FY (3)
                 - Pixel (K).Y) ** 2;
         end loop;
      end;
      return EF.Sqrt (Sum / Real (Pixel'Length));
   end Affine_RMS;

   function Distorted_Homography_RMS
     (Pixel  : Corner_List;
      I, J   : Index_List;
      CX, CY : Real) return Real;
   --  The same after removing one radial lens distortion term about
   --  (CX, CY): a pixel at normalised radius r (pixels / 500) from the
   --  centre is moved by the factor 1 / (1 + K1 * r**2) of its undistorted
   --  radius; the K1 in [-0.6, 0.2] that gives the smallest RMS is used.

   function Homography_RMS
     (Pixel  : Corner_List;
      I, J   : Index_List;
      Scale  : Real) return Real
   is
      subtype R8 is Integer range 1 .. 8;
      A    : array (R8, R8) of Real := [others => [others => 0.0]];
      B    : array (R8) of Real := [others => 0.0];
      H    : array (R8) of Real;
      Row  : array (R8) of Real;
      Sum  : Real := 0.0;

      procedure Accumulate (Value : Real) is
      begin
         for P in R8 loop
            for Q in R8 loop
               A (P, Q) := A (P, Q) + Row (P) * Row (Q);
            end loop;
            B (P) := B (P) + Row (P) * Value;
         end loop;
      end Accumulate;
   begin
      for K in Pixel'Range loop
         declare
            X : constant Real := Real (I (K));
            Y : constant Real := Real (J (K));
            U : constant Real := Pixel (K).X / Scale;
            V : constant Real := Pixel (K).Y / Scale;
         begin
            Row := [X, Y, 1.0, 0.0, 0.0, 0.0, -X * U, -Y * U];
            Accumulate (U);
            Row := [0.0, 0.0, 0.0, X, Y, 1.0, -X * V, -Y * V];
            Accumulate (V);
         end;
      end loop;

      --  Gaussian elimination with partial pivoting.
      for C in R8 loop
         declare
            Best : R8 := C;
         begin
            for P in C + 1 .. 8 loop
               if abs A (P, C) > abs A (Best, C) then
                  Best := P;
               end if;
            end loop;
            for Q in R8 loop
               declare
                  T : constant Real := A (C, Q);
               begin
                  A (C, Q) := A (Best, Q);
                  A (Best, Q) := T;
               end;
            end loop;
            declare
               T : constant Real := B (C);
            begin
               B (C) := B (Best);
               B (Best) := T;
            end;
         end;
         for P in C + 1 .. 8 loop
            declare
               F : constant Real := A (P, C) / A (C, C);
            begin
               for Q in C .. 8 loop
                  A (P, Q) := A (P, Q) - F * A (C, Q);
               end loop;
               B (P) := B (P) - F * B (C);
            end;
         end loop;
      end loop;
      for C in reverse R8 loop
         H (C) := B (C);
         for Q in C + 1 .. 8 loop
            H (C) := H (C) - A (C, Q) * H (Q);
         end loop;
         H (C) := H (C) / A (C, C);
      end loop;

      for K in Pixel'Range loop
         declare
            X : constant Real := Real (I (K));
            Y : constant Real := Real (J (K));
            W : constant Real := H (7) * X + H (8) * Y + 1.0;
            U : constant Real := Scale * (H (1) * X + H (2) * Y + H (3)) / W;
            V : constant Real := Scale * (H (4) * X + H (5) * Y + H (6)) / W;
         begin
            Sum := Sum + (U - Pixel (K).X) ** 2 + (V - Pixel (K).Y) ** 2;
         end;
      end loop;
      return EF.Sqrt (Sum / Real (Pixel'Length));
   end Homography_RMS;

   function Distorted_Homography_RMS
     (Pixel  : Corner_List;
      I, J   : Index_List;
      CX, CY : Real) return Real
   is
      F : constant := 500.0;

      function RMS_For (K1 : Real) return Real is
         Undistorted : Corner_List (Pixel'Range);
      begin
         for K in Pixel'Range loop
            declare
               DX : constant Real := (Pixel (K).X - CX) / F;
               DY : constant Real := (Pixel (K).Y - CY) / F;
               UX : Real := DX;
               UY : Real := DY;
            begin
               --  Undistort by fixed-point iteration of d = u (1 + K1 |u|^2).
               for Unused in 1 .. 20 loop
                  UX := DX / (1.0 + K1 * (UX * UX + UY * UY));
                  UY := DY / (1.0 + K1 * (UX * UX + UY * UY));
               end loop;
               Undistorted (K) := (CX + F * UX, CY + F * UY);
            end;
         end loop;
         return Homography_RMS (Undistorted, I, J, 1000.0);
      end RMS_For;

      --  Golden-section search for the smallest RMS.
      G      : constant Real := (EF.Sqrt (5.0) - 1.0) / 2.0;
      Low    : Real := -0.6;
      High   : Real := 0.2;
      A      : Real := High - G * (High - Low);
      B      : Real := Low + G * (High - Low);
      FA     : Real := RMS_For (A);
      FB     : Real := RMS_For (B);
   begin
      for Unused in 1 .. 40 loop
         if FA < FB then
            High := B;
            B := A;
            FB := FA;
            A := High - G * (High - Low);
            FA := RMS_For (A);
         else
            Low := A;
            A := B;
            FA := FB;
            B := Low + G * (High - Low);
            FB := RMS_For (B);
         end if;
      end loop;
      return Real'Min (FA, FB);
   end Distorted_Homography_RMS;

   procedure Check_Board
     (Name       : String;
      Max_RMS    : Real;
      Distortion : Boolean)
   is
      use AMV.Calib_Fix;
      Calibration : Ks_Calib_Checkerboard;
      Image       : constant Ks_Image_8_Grey := Load (Name);
   begin
      Calibration.Set_Calibration_Image (Image);
      Calibration.Calibrate;
      Check (Calibration.Num_Points = 54,
             Name & ": 54 corners (found" & Calibration.Num_Points'Image
             & ")");
      if Calibration.Num_Points < 9 then
         return;
      end if;
      declare
         N     : constant Positive := Calibration.Num_Points;
         Pixel : Corner_List (1 .. N);
         I, J  : Index_List (1 .. N);
         Min_I, Min_J : Integer := Integer'Last;
         Max_I, Max_J : Integer := Integer'First;
         Twice : Boolean := False;
      begin
         for K in 1 .. N loop
            Calibration.Get_Corner
              (K - 1, Pixel (K).X, Pixel (K).Y, I (K), J (K));
            Min_I := Integer'Min (Min_I, I (K));
            Max_I := Integer'Max (Max_I, I (K));
            Min_J := Integer'Min (Min_J, J (K));
            Max_J := Integer'Max (Max_J, J (K));
            for L in 1 .. K - 1 loop
               Twice := Twice or else (I (L) = I (K) and then J (L) = J (K));
            end loop;
         end loop;
         Check ((Max_I - Min_I = 8 and then Max_J - Min_J = 5)
                or else (Max_I - Min_I = 5 and then Max_J - Min_J = 8),
                Name & ": a 9 x 6 grid (found"
                & Integer'Image (Max_I - Min_I + 1) & " x"
                & Integer'Image (Max_J - Min_J + 1) & ")");
         Check (not Twice, Name & ": no grid index given twice");
         declare
            RMS : constant Real :=
              (if Distortion
               then Distorted_Homography_RMS
                      (Pixel, I, J, Real (Image.Width - 1) / 2.0,
                       Real (Image.Height - 1) / 2.0)
               else Homography_RMS (Pixel, I, J, 1000.0));
         begin
            Check (RMS <= Max_RMS,
                   Name & ": corners on a homography of the grid"
                   & (if Distortion then ", one radial distortion term"
                      else "")
                   & " (RMS" & Integer (RMS * 1000.0)'Image & "e-3 px)");
         end;
      end;
   exception
      when E : AMV.Ks_Bad_Parameter_Exception =>
         Fail (Name & ": " & Ada.Exceptions.Exception_Message (E));
   end Check_Board;

   --  The same boards calibrated in Perspective_And_Radial_Warp mode (a
   --  homography and two radial terms, fitted by AMV itself, and the image
   --  warped so that the board is seen undistorted and square on): the
   --  model fits the corners within Max_RMS, and in the warped output the
   --  detector finds at least Min_Again corners again, on an affine map of
   --  their grid indices within Max_Output_RMS.

   procedure Check_Warp
     (Name           : String;
      Max_RMS        : Real;
      Min_Again      : Natural;
      Max_Output_RMS : Real;
      Max_Mapped_RMS : Real;
      Max_K          : Real := Real'Last)
   is
      use AMV.Calib_Fix;
      Tool  : Ks_Calib_Checkerboard_Tool;
      Again : Ks_Calib_Checkerboard;
      Image : constant Ks_Image_8_Grey := Load (Name);
   begin
      Tool.Calibration.Set_Calibration_Image (Image);
      Tool.Calibration.Set_Computation_Mode (Perspective_And_Radial_Warp);
      Tool.Calibration.Calibrate;
      Check (Tool.Calibration.Calibrated
             and then Tool.Calibration.Computed_RMS_Error <= Max_RMS,
             Name & " warp mode: the model fits the corners (RMS"
             & Integer (Tool.Calibration.Computed_RMS_Error * 1000.0)'Image
             & "e-3 px)");
      if Max_K < Real'Last then
         declare
            M : constant Ks_Calib_Checkerboard_Warp_Model :=
              Tool.Calibration.Get_Computed_Warp_Model;
         begin
            Check (abs M.K1 <= Max_K and then abs M.K2 <= Max_K,
                   Name & " warp mode: no distortion found (K1"
                   & Integer (M.K1 * 1000.0)'Image & "e-3, K2"
                   & Integer (M.K2 * 1000.0)'Image & "e-3)");
         end;
      end if;
      --  The corners found in the distorted input, mapped into the output
      --  by Map_Input_Pixel (without warping): on an affine grid.
      declare
         N       : constant Natural := Tool.Calibration.Num_Points;
         Mapped  : Corner_List (1 .. N);
         I, J    : Index_List (1 .. N);
         PX, PY  : Real;
         Inside  : Boolean;
         Outside : Natural := 0;
         RMS     : Real;
      begin
         for K in 1 .. N loop
            Tool.Calibration.Get_Corner (K - 1, PX, PY, I (K), J (K));
            Tool.Calibration.Map_Input_Pixel
              (PX, PY, Mapped (K).X, Mapped (K).Y, Inside);
            if not Inside then
               Outside := Outside + 1;
            end if;
         end loop;
         Check (Outside = 0,
                Name & " warp mode: every input corner maps into the output"
                & " (" & Outside'Image & " not)");
         if N >= 9 then
            RMS := Affine_RMS (Mapped, I, J);
            Check (RMS <= Max_Mapped_RMS,
                   Name & " warp mode: input corners mapped on an affine"
                   & " grid (RMS" & Integer (RMS * 1000.0)'Image
                   & "e-3 px)");
         end if;
      end;
      --  The same corners given as N-point pairs (pixel position, grid
      --  index times the tile size) to an N-point calibration in the same
      --  mode, with the same image: the two calibrations share the fit, so
      --  they must give the same model (an exact property, no reference):
      --  the same RMS error and the same map of input pixels.
      declare
         NP     : Ks_Calib_N_Point_To_N_Point;
         TX     : constant Real := Tool.Calibration.Physical_Tile_Size_X;
         TY     : constant Real := Tool.Calibration.Physical_Tile_Size_Y;
         PX, PY : Real;
         I, J   : Integer;
         Worst  : Real := 0.0;
      begin
         for K in 0 .. Tool.Calibration.Num_Points - 1 loop
            Tool.Calibration.Get_Corner (K, PX, PY, I, J);
            NP.Add_Point_Pair (PX, PY, Real (I) * TX, Real (J) * TY);
         end loop;
         NP.Set_Computation_Mode (Perspective_And_Radial_Warp);
         NP.Calibrate (Image);
         Check (NP.Calibrated
                and then abs (NP.Computed_RMS_Error
                              - Tool.Calibration.Computed_RMS_Error)
                           <= 1.0E-9,
                Name & " warp mode: the corners as N-point pairs give the"
                & " same RMS error");
         if NP.Calibrated then
            for Y in 0 .. Image.Height / 40 loop
               for X in 0 .. Image.Width / 40 loop
                  declare
                     AX, AY, BX, BY : Real;
                     A_In, B_In     : Boolean;
                  begin
                     Tool.Calibration.Map_Input_Pixel
                       (Real (X * 40), Real (Y * 40), AX, AY, A_In);
                     NP.Map_Input_Pixel
                       (Real (X * 40), Real (Y * 40), BX, BY, B_In);
                     if A_In /= B_In then
                        Worst := Real'Last;
                     elsif A_In then
                        Worst := Real'Max
                          (Worst, Distance ((AX, AY), (BX, BY)));
                     end if;
                  end;
               end loop;
            end loop;
            Ada.Text_IO.Put_Line
              ("  " & Name & " N-point warp: RMS difference"
               & Real'Image (abs (NP.Computed_RMS_Error
                                  - Tool.Calibration.Computed_RMS_Error))
               & ", largest map difference" & Real'Image (Worst) & " px");
            Check (Worst <= 1.0E-6,
                   Name & " warp mode: the N-point calibration maps the"
                   & " input pixels as the checkerboard does ("
                   & (if Worst = Real'Last then "inside differs"
                      else Integer (Worst * 1.0E9)'Image & "e-9 px")
                   & ")");
         end if;
      end;
      Tool.Input_Image := Image;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result,
             Name & " warp mode: warped");
      if Tool.Run_Status.Result /= Accept_Result then
         return;
      end if;
      Again.Set_Calibration_Image (Tool.Output_Image);
      Again.Calibrate;
      Check (Again.Num_Points >= Min_Again,
             Name & " warp mode: corners found again in the output"
             & Again.Num_Points'Image);
      if Again.Num_Points >= 9 then
         declare
            N     : constant Positive := Again.Num_Points;
            Pixel : Corner_List (1 .. N);
            I, J  : Index_List (1 .. N);
            RMS   : Real;
         begin
            for K in 1 .. N loop
               Again.Get_Corner
                 (K - 1, Pixel (K).X, Pixel (K).Y, I (K), J (K));
            end loop;
            RMS := Affine_RMS (Pixel, I, J);
            Check (RMS <= Max_Output_RMS,
                   Name & " warp mode: output corners on an affine grid"
                   & " (RMS" & Integer (RMS * 1000.0)'Image & "e-3 px)");
         end;
      end if;
   exception
      when E : AMV.Ks_Bad_Parameter_Exception
             | AMV.Ks_Operator_Not_Trained_Exception =>
         Fail (Name & " warp mode: " & Ada.Exceptions.Exception_Message (E));
   end Check_Warp;

   procedure Test_Checkerboards is
   begin
      Section ("Checkerboard calibration: OpenCV's left01 .. left14");
      --  A hand-held board of 10 x 7 tiles (9 x 6 inner corners) filmed by
      --  a camera with barrel distortion (OpenCV's calibration of it: k1
      --  about -0.28 at f 536 px), in front of a cluttered office. A
      --  homography alone leaves 0.8 .. 1.9 px of distortion; with one
      --  radial term the corners fit to 0.15 .. 0.41 px.
      --  Tuning: left01 .. left14 (the detector was developed on them);
      --  their largest RMS is 0.41 px, so the tolerance is 0.65 px (1.5
      --  times, rounded up). Evaluation: right01 .. right14, the stereo
      --  partner's images of the same board, run only after.
      for N in 1 .. 14 loop
         if N /= 10 then
            Check_Board ("left" & (if N < 10 then "0" else "")
                         & Integer'Image (N) (2 .. Integer'Image (N)'Last),
                         Max_RMS => 0.65, Distortion => True);
         end if;
      end loop;

      Section ("Checkerboard calibration: OpenCV's right01 .. right14"
               & " (evaluation)");
      for N in 1 .. 14 loop
         if N /= 10 then
            Check_Board ("right" & (if N < 10 then "0" else "")
                         & Integer'Image (N) (2 .. Integer'Image (N)'Last),
                         Max_RMS => 0.65, Distortion => True);
         end if;
      end loop;

      Section ("Checkerboard calibration: OpenCV's printable chessboard");
      --  A rendered 9 x 6 board (tiles of 148 pixels, a white margin).
      Check_Board ("chessboard", Max_RMS => 0.05, Distortion => False);

      Section ("Checkerboard calibration with lens distortion"
               & " (Perspective_And_Radial_Warp)");
      --  Tuning: left01 .. left14. The model fits the corners to 0.14 ..
      --  0.40 px (tolerance 0.6 px, 1.5 times rounded up); in the warped
      --  output 54 corners are found again on every image but left05 (52),
      --  on an affine grid to 0.15 .. 0.41 px (tolerance 0.65 px). K1 comes
      --  out between -0.19 and -0.13 (K2, small, varies in sign), which is
      --  reported, not checked. Evaluation: right01 .. right14, run only
      --  after these were frozen. The input corners mapped into the output
      --  by Map_Input_Pixel (no warp) lie on an affine grid to 0.15 ..
      --  0.40 px on the tuning images (tolerance 0.65 px, 1.5 times rounded
      --  up; evaluated on the right images afterwards, once).
      for N in 1 .. 14 loop
         if N /= 10 then
            Check_Warp ("left" & (if N < 10 then "0" else "")
                        & Integer'Image (N) (2 .. Integer'Image (N)'Last),
                        Max_RMS => 0.6, Min_Again => 52,
                        Max_Output_RMS => 0.65, Max_Mapped_RMS => 0.65);
         end if;
      end loop;
      for N in 1 .. 14 loop
         if N /= 10 then
            Check_Warp ("right" & (if N < 10 then "0" else "")
                        & Integer'Image (N) (2 .. Integer'Image (N)'Last),
                        Max_RMS => 0.6, Min_Again => 52,
                        Max_Output_RMS => 0.65, Max_Mapped_RMS => 0.65);
         end if;
      end loop;
      --  The rendered board has no distortion: the model must find none
      --  (a tuned regression example: K1 and K2 came out below 0.0005, the
      --  mapped corners on a grid to 0.010 px).
      Check_Warp ("chessboard", Max_RMS => 0.05, Min_Again => 54,
                  Max_Output_RMS => 0.05, Max_Mapped_RMS => 0.05,
                  Max_K => 0.005);
   end Test_Checkerboards;

   ---------------------------------------------------------------------

   ---------------------------------------------------------------------
   --  Gauging: VisA pcb1 (Find Circle, Dimensioning, Find Line, Caliper)
   ---------------------------------------------------------------------

   --  Ground truth measured independently of AMV (a separate plain-Python
   --  tool, tests/real_images/README.md), before AMV was run on the image:
   --  each mounting hole's edge (dark hole to light pad) found on 72 rays
   --  and fitted with a geometric least-squares circle; each outline edge
   --  of the board found on 60 profiles and fitted with a total
   --  least-squares line. The outline is the outer boundary of the board,
   --  where the grey level rises towards the board's inside (the board's
   --  light rim has an inner edge too, and the side lit obliquely shows a
   --  blurred band outside it); S is the line fit's RMS.
   --
   --  One set of tool parameters for the whole series, and tolerances
   --  fixed before the evaluation boards were measured, chosen on the ten
   --  tuning boards only, with the tools placed by the fixture (below):
   --  * holes: 1.5 times the largest error, rounded up to 0.05 px
   --    (references fitting with an RMS above 0.85 px would not be used;
   --    none is);
   --  * edges and widths: a base plus the reference's own uncertainty, so
   --    that blurred edges are kept, with a wider tolerance, rather than
   --    left out: position 0.15 px + S, direction 0.06 deg + 2 S / span,
   --    width (between the two outlines) 0.3 px + S (left) + S (right).
   --    The largest errors beyond S on the tuning boards are below these
   --    bases, except on the known failure below (0150's right outline).

   Hole_Tolerance      : constant := 0.95;  --  centre (tuning max 0.60)
   Radius_Tolerance    : constant := 0.5;   --  (tuning max 0.33)
   Distance_Tolerance  : constant := 0.8;   --  (tuning max 0.53)
   Direction_Base      : constant := 0.06;  --  degrees
   Offset_Base         : constant := 0.15;
   Width_Base          : constant := 0.3;

   Known_Bad_Outline : constant String := "0150";
   --  The known failure of the tuning set: the right outline of 0150. The
   --  board's light rim there has small bumps (burrs, reflections) just
   --  outside it near the top; the reference takes the outermost edge, so
   --  its line follows the bumps, while Find Line and the caliper take the
   --  rim's edge (the strongest one), about 1 degree apart in direction
   --  and 2.3 px apart in width (the reference's S there is 1.6 px). No
   --  setting tried on the tuning boards (search lengths 12 .. 24 px,
   --  thresholds 20 .. 40, a scorer preferring the outermost edge) brings
   --  the two together, and the earlier version of this test passed only
   --  because it started 3 px outside the reference line. Checked to still
   --  fail, so that a change shows up here.

   type Hole is record
      X, Y, R : Real;
   end record;

   type Hole_Set is array (1 .. 4) of Hole;
   --  Top left, top right, bottom left, bottom right, as seen.

   type Edge is record
      X, Y, Degrees : Real;
      --  A point on the edge and its direction.
      S             : Real;
      --  The reference fit's RMS.
   end record;

   type Board is record
      Name        : String (1 .. 4);
      Evaluation  : Boolean;
      Holes       : Hole_Set;
      Left, Right : Edge;
   end record;

   Boards : constant array (1 .. 15) of Board :=
     [("0000", False,
       [(218.690, 351.971, 17.469), (1112.845, 348.926, 17.468),
        (223.109, 710.890, 17.408), (1109.149, 707.508, 17.244)],
       (188.140, 532.592, 89.2691, 0.381),
       (1142.288, 527.548, -89.3572, 0.292)),
      ("0150", False,
       [(218.998, 354.071, 17.383), (1114.901, 347.480, 17.454),
        (224.319, 714.348, 17.296), (1113.272, 707.579, 17.157)],
       (193.335, 534.209, 89.1124, 0.158),
       (1148.664, 527.533, -88.8273, 1.579)),
      ("0450", False,
       [(244.971, 361.190, 17.475), (1139.871, 357.202, 17.361),
        (248.404, 721.161, 17.267), (1135.871, 716.098, 17.047)],
       (211.336, 541.180, 89.4808, 1.704),
       (1166.751, 538.648, -89.3543, 0.201)),
      ("0600", False,
       [(221.873, 340.236, 17.427), (1116.924, 335.248, 17.394),
        (226.510, 700.466, 17.231), (1114.616, 694.508, 16.959)],
       (195.559, 519.684, 89.2338, 0.735),
       (1144.742, 518.238, -89.5486, 0.210)),
      ("0750", False,
       [(182.951, 356.976, 17.100), (1064.434, 354.931, 17.313),
        (181.637, 717.429, 16.794), (1067.037, 715.344, 16.512)],
       (151.431, 539.786, -89.8284, 0.403),
       (1095.349, 535.415, 89.4706, 0.169)),
      ("0050", False,
       [(226.326, 351.896, 17.462), (1120.896, 355.513, 17.384),
        (229.124, 711.120, 17.312), (1115.785, 714.692, 17.261)],
       (198.631, 534.010, 89.5093, 0.495),
       (1149.781, 535.103, -89.2194, 0.199)),
      ("0200", False,
       [(218.561, 348.506, 17.294), (1113.625, 356.520, 17.440),
        (218.082, 708.238, 17.328), (1105.855, 715.639, 17.139)],
       (192.026, 527.077, -89.9071, 0.534),
       (1140.564, 539.140, -88.7085, 0.180)),
      ("0350", False,
       [(226.705, 368.029, 17.183), (1122.078, 345.815, 16.875),
        (238.182, 727.634, 17.050), (1125.451, 704.728, 16.281)],
       (204.541, 547.546, 88.2128, 0.189),
       (1152.074, 525.272, 88.9595, 0.948)),
      ("0500", False,
       [(250.671, 329.868, 17.106), (1144.840, 341.522, 17.278),
        (247.093, 690.804, 17.374), (1135.297, 701.228, 17.161)],
       (216.407, 503.833, -89.3111, 0.563),
       (1173.175, 517.245, -88.4222, 0.670)),
      ("0900", False,
       [(255.332, 345.798, 17.267), (1148.881, 341.988, 17.303),
        (257.498, 706.899, 17.255), (1145.251, 701.398, 17.273)],
       (228.680, 526.349, 89.6676, 0.720),
       (1177.818, 524.512, -89.3546, 0.135)),
      ("0100", True,
       [(198.743, 363.335, 17.487), (1094.045, 368.336, 17.596),
        (199.860, 722.231, 17.420), (1087.911, 727.471, 17.345)],
       (167.818, 541.089, 89.6449, 0.170),
       (1118.345, 547.503, -88.9955, 0.872)),
      ("0250", True,
       [(225.682, 365.950, 16.957), (1120.355, 355.638, 16.873),
        (232.255, 725.773, 16.821), (1120.279, 714.038, 16.689)],
       (192.419, 545.863, 88.9045, 0.765),
       (1149.605, 534.838, 89.8965, 1.610)),
      ("0400", True,
       [(164.107, 360.056, 17.381), (1059.359, 336.093, 17.386),
        (177.202, 720.664, 17.348), (1066.039, 696.725, 17.022)],
       (138.244, 540.360, 87.8575, 1.231),
       (1094.638, 522.195, 88.9876, 0.454)),
      ("0550", True,
       [(202.259, 350.998, 17.161), (1097.383, 345.585, 16.794),
        (207.873, 710.121, 17.116), (1095.219, 705.304, 16.947)],
       (171.302, 530.557, 89.2113, 1.586),
       (1128.636, 519.892, -89.7853, 0.541)),
      ("0700", True,
       [(254.035, 362.724, 17.221), (1134.991, 356.272, 17.242),
        (254.608, 722.468, 17.269), (1140.965, 714.706, 17.367)],
       (223.285, 539.139, 89.7993, 0.580),
       (1168.338, 536.551, 89.0063, 0.174))];

   function Set_Name (B : Board) return String is
     ((if B.Evaluation then "evaluation " else "tuning ") & B.Name);

   function X_At (E : Edge; Y : Real) return Real is
     (E.X + (Y - E.Y) * EF.Cos (AMV.Misc.Deg_To_Rad (E.Degrees))
                      / EF.Sin (AMV.Misc.Deg_To_Rad (E.Degrees)));

   ---------------------------------------------------------------------
   --  The fixture: where the gauging tools are placed
   ---------------------------------------------------------------------

   --  The gauging tools are placed as a recipe would place them: board
   --  0000's reference holes and outlines, taught once on that board,
   --  mapped into each board by the board's pose from PMAlign (a pattern
   --  trained on 0000: the board's area, origin the identity, so that a
   --  pose maps 0000's coordinates into the other image's). No tool starts
   --  from the board's own references, which only judge the results (and
   --  name the hole or edge a result belongs to). The pose is off by up to
   --  about 6 px at the holes (see the PMAlign test below), which the
   --  tools must absorb.

   Fixture_Trained : Boolean := False;
   Fixture_Tool    : AMV.PM_Align.Ks_PM_Align_Tool;
   Fixture_Known   : array (Boards'Range) of Boolean := [others => False];
   Fixture_Found   : array (Boards'Range) of Boolean := [others => False];
   Fixture_Poses   : array (Boards'Range) of
                       AMV.Transforms.Ks_Transform_2D_Linear;

   procedure Find_Fixture
     (I     : Positive;
      Found : out Boolean;
      Pose  : out AMV.Transforms.Ks_Transform_2D_Linear);
   --  The pose of board I (Found False unless PMAlign finds exactly one
   --  board), computed once.

   procedure Find_Fixture
     (I     : Positive;
      Found : out Boolean;
      Pose  : out AMV.Transforms.Ks_Transform_2D_Linear)
   is
      use AMV.PM_Align;
   begin
      if not Fixture_Trained then
         declare
            Train  : constant Board := Boards (1);
            Image  : constant Ks_Image_8_Grey :=
              Load ("visa_pcb1_" & Train.Name);
            Region : AMV.Shapes.Ks_Rectangle;
            X0     : constant Real :=
              Real'Min (Train.Holes (1).X, Train.Holes (3).X) - 60.0;
            X1     : constant Real :=
              Real'Max (Train.Holes (2).X, Train.Holes (4).X) + 60.0;
            Y0     : constant Real :=
              Real'Min (Train.Holes (1).Y, Train.Holes (2).Y) - 60.0;
            Y1     : constant Real :=
              Real'Max (Train.Holes (3).Y, Train.Holes (4).Y) + 60.0;
         begin
            Region.Set_XY_Width_Height (X0, Y0, X1 - X0, Y1 - Y0);
            Fixture_Tool.Pattern.Set_Train_Image (Image);
            Fixture_Tool.Pattern.Set_Train_Region
              (AMV.Shapes.Region_Holders.To_Holder (Region));
            --  Grain 4 .. 32 (chosen on the tuning boards): with the
            --  automatic choice the fine texture (the transducers' mesh,
            --  the lettering) keeps PMAlign from finding 8 of the 10
            --  boards; grain 8 scores higher but places the holes less
            --  accurately.
            Fixture_Tool.Pattern.Set_Grain_Limit_Auto_Select (False);
            Fixture_Tool.Pattern.Set_Grain_Limit_Fine (4.0);
            Fixture_Tool.Pattern.Set_Grain_Limit_Coarse (32.0);
            Fixture_Tool.Pattern.Train;
            Fixture_Tool.Run_Params.Zone_Angle.Configuration :=
              Code (Low_High);
            Fixture_Tool.Run_Params.Zone_Angle.Low := -Ada.Numerics.Pi;
            Fixture_Tool.Run_Params.Zone_Angle.High := Ada.Numerics.Pi;
            Fixture_Tool.Run_Params.Zone_Scale.Configuration :=
              Code (Low_High);
            Fixture_Tool.Run_Params.Zone_Scale.Low := 0.95;
            Fixture_Tool.Run_Params.Zone_Scale.High := 1.05;
            Fixture_Tool.Run_Params.Accept_Threshold := 0.3;
         end;
         Fixture_Trained := True;
      end if;
      if not Fixture_Known (I) then
         Fixture_Tool.Input_Image := Load ("visa_pcb1_" & Boards (I).Name);
         Fixture_Tool.Run;
         Fixture_Found (I) :=
           Fixture_Tool.Run_Status.Result = Accept_Result
           and then Fixture_Tool.Results.Count = 1;
         if Fixture_Found (I) then
            Fixture_Poses (I) := Get_Pose (Fixture_Tool.Results.Item (0));
         end if;
         Fixture_Known (I) := True;
      end if;
      Found := Fixture_Found (I);
      Pose := Fixture_Poses (I);
   end Find_Fixture;

   function Mapped
     (Pose : AMV.Transforms.Ks_Transform_2D_Linear; P : Point) return Point;
   --  P (a point of board 0000) mapped by Pose.

   function Mapped
     (Pose : AMV.Transforms.Ks_Transform_2D_Linear; P : Point) return Point
   is
      X, Y : Real;
   begin
      Pose.Map_Point (P.X, P.Y, X, Y);
      return (X, Y);
   end Mapped;

   function Taught_Hole
     (Pose : AMV.Transforms.Ks_Transform_2D_Linear; J : Positive)
      return Point
   is (Mapped (Pose, (Boards (1).Holes (J).X, Boards (1).Holes (J).Y)));
   --  Board 0000's hole J, mapped by Pose.

   function Nearest_Hole (B : Board; P : Point) return Positive;
   --  The index of B's reference hole nearest P.

   function Nearest_Hole (B : Board; P : Point) return Positive is
      Best : Positive := 1;
   begin
      for K in Hole_Set'Range loop
         if Distance (P, (B.Holes (K).X, B.Holes (K).Y))
           < Distance (P, (B.Holes (Best).X, B.Holes (Best).Y))
         then
            Best := K;
         end if;
      end loop;
      return Best;
   end Nearest_Hole;

   procedure Find_Hole
     (Image  : Ks_Image_8_Grey;
      Start  : Point;
      Found  : out Boolean;
      Circle : out AMV.Shapes.Ks_Circle);
   --  Find Circle on the hole whose centre the fixture puts at Start: run
   --  twice, the second time from the first circle's centre (from the
   --  fixture's start, up to about 6 px off, the first run lands within
   --  about 1.5 px; chosen on the tuning boards). The edge is the dark
   --  hole's boundary with the light pad around it, searched outwards.

   procedure Find_Hole
     (Image  : Ks_Image_8_Grey;
      Start  : Point;
      Found  : out Boolean;
      Circle : out AMV.Shapes.Ks_Circle)
   is
      use AMV.Caliper;
      use AMV.Caliper.Find_Circle;
      Centre : Point := Start;
   begin
      Found := False;
      for Pass in 1 .. 2 loop
         declare
            Tool : Ks_Find_Circle_Tool;
         begin
            Tool.Input_Image := Image;
            Tool.Run_Params.Expected_Circular_Arc
              .Set_Center_Radius_Angle_Start_Angle_Span
                (Centre.X, Centre.Y, 17.3, 0.0, 2.0 * Ada.Numerics.Pi);
            Tool.Run_Params.Num_Calipers := 48;
            Tool.Run_Params.Caliper_Search_Length := 10.0;
            Tool.Run_Params.Caliper_Projection_Length := 3.0;
            Tool.Run_Params.Caliper_Search_Direction := Outward;
            Tool.Run_Params.Num_To_Ignore := 7;
            Tool.Run_Params.Caliper_Run_Params.Edge_0_Polarity :=
              Code (Dark_To_Light);
            Tool.Run_Params.Caliper_Run_Params.Contrast_Threshold := 20.0;
            --  A narrow edge filter: the light pad around each hole is
            --  only about 4 px wide, and a wider filter is pulled towards
            --  the pad's outer edge.
            Tool.Run_Params.Caliper_Run_Params.Filter_Half_Size_In_Pixels :=
              1;
            Tool.Run;
            Found := Tool.Run_Status.Result = Accept_Result;
            exit when not Found;
            Circle := Tool.Results.Get_Circle;
            Centre := (Circle.Center_X, Circle.Center_Y);
         end;
      end loop;
   end Find_Hole;

   procedure Test_PCB_Holes is
      Centre : array (Hole_Set'Range) of Point;
   begin
      Section ("Gauging: VisA pcb1 mounting holes (Find Circle,"
               & " Dimensioning)");
      for I in Boards'Range loop
         declare
            B     : Board renames Boards (I);
            Image : constant Ks_Image_8_Grey := Load ("visa_pcb1_" & B.Name);
            Found : Boolean;
            Pose  : AMV.Transforms.Ks_Transform_2D_Linear;
         begin
            Centre := [others => (0.0, 0.0)];
            Find_Fixture (I, Found, Pose);
            if not Found then
               Fail (Set_Name (B) & " holes: no fixture");
            end if;
            for J in Hole_Set'Range loop
               exit when not Found;
               declare
                  Start : constant Point := Taught_Hole (Pose, J);
                  K     : constant Positive := Nearest_Hole (B, Start);
                  H     : Hole renames B.Holes (K);
                  Label : constant String :=
                    Set_Name (B) & " hole" & K'Image & ": ";
                  Ok    : Boolean;
                  C     : AMV.Shapes.Ks_Circle;
               begin
                  Find_Hole (Image, Start, Ok, C);
                  --  (0550's hole 1, a known failure of the evaluation set
                  --  when the search started 3 px off the reference, is
                  --  found within the tolerance from the fixture.)
                  Check (Ok, Label & "Find Circle accepted");
                  if Ok then
                     declare
                        D : constant Real :=
                          Distance ((C.Center_X, C.Center_Y), (H.X, H.Y));
                     begin
                        Centre (K) := (C.Center_X, C.Center_Y);
                        Check (D <= Hole_Tolerance,
                               Label & "centre ("
                               & Integer (D * 1000.0)'Image & "e-3 px)");
                        Check_Near (C.Radius, H.R, Radius_Tolerance,
                                    Label & "radius");
                     end;
                  end if;
               end;
            end loop;

            --  Distances between the holes, from the circles found.
            declare
               use AMV.Dimensioning;
               procedure Span (From, To : Positive; What : String) is
                  Tool  : Ks_Distance_Point_Point_Tool;
                  Truth : constant Real :=
                    Distance ((B.Holes (From).X, B.Holes (From).Y),
                              (B.Holes (To).X, B.Holes (To).Y));
               begin
                  if B.Holes (From).R = 0.0 or else B.Holes (To).R = 0.0
                    or else Centre (From).X = 0.0 or else Centre (To).X = 0.0
                  then
                     return;
                  end if;
                  Tool.Input_Image := Image;
                  Tool.Start_X := Centre (From).X;
                  Tool.Start_Y := Centre (From).Y;
                  Tool.End_X := Centre (To).X;
                  Tool.End_Y := Centre (To).Y;
                  Tool.Run;
                  Check (Tool.Run_Status.Result = Accept_Result,
                         Set_Name (B) & " " & What & ": accepted");
                  Check_Near (AMV.Dimensioning.Distance (Tool), Truth,
                              Distance_Tolerance,
                              Set_Name (B) & " " & What & " distance");
               end Span;
            begin
               Span (1, 2, "top left to top right");
               Span (1, 3, "top left to bottom left");
               Span (2, 4, "top right to bottom right");
            end;
         end;
      end loop;
   end Test_PCB_Holes;

   --  An outline found with Find Line from the fixture: board 0000's
   --  reference outline on one side (Taught_Left: its left one), between
   --  40 px below the upper hole and 40 px above the lower hole on that
   --  side, mapped by the pose. On 0000 that segment runs downwards, so
   --  the calipers search outwards (towards -x on the left): the outline
   --  (grey level rising towards the inside) is light to dark on the left
   --  and dark to light on the right; the pose keeps "outwards" even for
   --  the boards turned by 180 degrees. Left is True when the outline
   --  found is the board's left one as seen (left of the taught holes'
   --  centre), Span the segment's length.
   --
   --  Two runs, as for the holes (chosen on the tuning boards): the first
   --  with calipers Outline_Reach px long, enough for the fixture's error
   --  at the outlines (up to about 7 px), the second along the first line
   --  found with 12 px calipers, short of the white transducer rings just
   --  inside some edges and of the light band outside the obliquely lit
   --  ones. A single run with any length from 12 to 20 px loses an edge or
   --  takes a wrong one on some tuning board.

   Outline_Reach : constant := 20.0;

   procedure Find_Outline
     (Image       : Ks_Image_8_Grey;
      Pose        : AMV.Transforms.Ks_Transform_2D_Linear;
      Taught_Left : Boolean;
      Found       : out Boolean;
      Line        : out AMV.Shapes.Ks_Line;
      Left        : out Boolean;
      Span        : out Real);

   procedure Find_Outline
     (Image       : Ks_Image_8_Grey;
      Pose        : AMV.Transforms.Ks_Transform_2D_Linear;
      Taught_Left : Boolean;
      Found       : out Boolean;
      Line        : out AMV.Shapes.Ks_Line;
      Left        : out Boolean;
      Span        : out Real)
   is
      use AMV.Caliper;
      use AMV.Caliper.Find_Line;
      T      : Board renames Boards (1);
      E      : constant Edge := (if Taught_Left then T.Left else T.Right);
      Top    : constant Hole := T.Holes (if Taught_Left then 1 else 2);
      Bottom : constant Hole := T.Holes (if Taught_Left then 3 else 4);
      From_Y : constant Real := Top.Y + 40.0;
      To_Y   : constant Real := Bottom.Y - 40.0;
      P0     : Point := Mapped (Pose, (X_At (E, From_Y), From_Y));
      P1     : Point := Mapped (Pose, (X_At (E, To_Y), To_Y));
      Middle : Point := (0.0, 0.0);

      function Onto (P : Point; L : AMV.Shapes.Ks_Line) return Point is
        (declare
           DX : constant Real := EF.Cos (L.Rotation);
           DY : constant Real := EF.Sin (L.Rotation);
           T  : constant Real := (P.X - L.X) * DX + (P.Y - L.Y) * DY;
         begin (L.X + T * DX, L.Y + T * DY));
      --  P projected onto L.
   begin
      for J in Hole_Set'Range loop
         Middle := (Middle.X + Taught_Hole (Pose, J).X / 4.0,
                    Middle.Y + Taught_Hole (Pose, J).Y / 4.0);
      end loop;
      Left := (P0.X + P1.X) / 2.0 < Middle.X;
      Span := Distance (P0, P1);
      Found := False;
      for Pass in 1 .. 2 loop
         declare
            Tool : Ks_Find_Line_Tool;
         begin
            Tool.Input_Image := Image;
            Tool.Run_Params.Expected_Line_Segment.Set_Start_End
              (P0.X, P0.Y, P1.X, P1.Y);
            Tool.Run_Params.Num_Calipers := 40;
            Tool.Run_Params.Caliper_Search_Length :=
              (if Pass = 1 then Outline_Reach else 12.0);
            Tool.Run_Params.Num_To_Ignore := 6;
            Tool.Run_Params.Caliper_Run_Params.Contrast_Threshold := 20.0;
            Tool.Run_Params.Caliper_Run_Params.Filter_Half_Size_In_Pixels :=
              1;
            Tool.Run_Params.Caliper_Run_Params.Edge_0_Polarity :=
              (if Taught_Left then Code (Light_To_Dark)
               else Code (Dark_To_Light));
            Tool.Run;
            Found := Tool.Run_Status.Result = Accept_Result;
            exit when not Found;
            Line := Tool.Results.Get_Line;
            --  The next run along this line, over the same stretch and in
            --  the same direction.
            P0 := Onto (P0, Line);
            P1 := Onto (P1, Line);
         end;
      end loop;
   end Find_Outline;

   procedure Test_PCB_Edges is
   begin
      Section ("Gauging: VisA pcb1 board edges (Find Line)");
      for I in Boards'Range loop
         declare
            B     : Board renames Boards (I);
            Image : constant Ks_Image_8_Grey := Load ("visa_pcb1_" & B.Name);
            Found : Boolean;
            Pose  : AMV.Transforms.Ks_Transform_2D_Linear;
         begin
            Find_Fixture (I, Found, Pose);
            if not Found then
               Fail (Set_Name (B) & " edges: no fixture");
            else
               for Taught_Left in Boolean loop
                  declare
                     Ok   : Boolean;
                     L    : AMV.Shapes.Ks_Line;
                     Left : Boolean;
                     Span : Real;
                  begin
                     Find_Outline (Image, Pose, Taught_Left, Ok, L, Left,
                                   Span);
                     declare
                        E     : constant Edge :=
                          (if Left then B.Left else B.Right);
                        Label : constant String :=
                          Set_Name (B) & " edge at x" & Integer (E.X)'Image
                          & ": ";
                     begin
                        Check (Ok, Label & "accepted");
                        if Ok then
                           declare
                              A    : constant Real :=
                                AMV.Misc.Deg_To_Rad (E.Degrees);
                              Turn : constant Real :=
                                abs EF.Arctan
                                      (EF.Sin (2.0 * (L.Rotation - A)),
                                       EF.Cos (2.0 * (L.Rotation - A)))
                                / 2.0;
                              Off  : constant Real :=
                                abs (-(E.X - L.X) * EF.Sin (L.Rotation)
                                     + (E.Y - L.Y) * EF.Cos (L.Rotation));
                           begin
                              if B.Name = Known_Bad_Outline and then not Left
                              then
                                 Check (AMV.Misc.Rad_To_Deg (Turn)
                                          > Direction_Base
                                            + AMV.Misc.Rad_To_Deg
                                                (2.0 * E.S / Span),
                                        Label & "direction: known failure"
                                        & " still fails");
                              else
                                 Check (AMV.Misc.Rad_To_Deg (Turn)
                                          <= Direction_Base
                                             + AMV.Misc.Rad_To_Deg
                                                 (2.0 * E.S / Span),
                                        Label & "direction ("
                                        & Integer (AMV.Misc.Rad_To_Deg (Turn)
                                                   * 1000.0)'Image
                                        & "e-3 deg)");
                              end if;
                              Check (Off <= Offset_Base + E.S,
                                     Label & "position ("
                                     & Integer (Off * 1000.0)'Image
                                     & "e-3 px)");
                           end;
                        end if;
                     end;
                  end;
               end loop;
            end if;
         end;
      end loop;
   end Test_PCB_Edges;

   procedure Test_PCB_Width is
   begin
      Section ("Gauging: VisA pcb1 board width (Find Line, Dimensioning)");
      --  The width: from the left outline found, at the height halfway
      --  between the two taught holes on the left (as mapped by the
      --  fixture), to the right outline found, perpendicular to it. The
      --  reference is the same construction on the reference lines.
      for I in Boards'Range loop
         declare
            B      : Board renames Boards (I);
            Image  : constant Ks_Image_8_Grey :=
              Load ("visa_pcb1_" & B.Name);
            Found  : Boolean;
            Pose   : AMV.Transforms.Ks_Transform_2D_Linear;
            Lines  : array (Boolean) of AMV.Shapes.Ks_Line;
            Got    : array (Boolean) of Boolean := [others => False];
         begin
            Find_Fixture (I, Found, Pose);
            if Found then
               for Taught_Left in Boolean loop
                  declare
                     Ok   : Boolean;
                     L    : AMV.Shapes.Ks_Line;
                     Left : Boolean;
                     Unused_Span : Real;
                  begin
                     Find_Outline (Image, Pose, Taught_Left, Ok, L, Left,
                                   Unused_Span);
                     if Ok then
                        Lines (Left) := L;
                        Got (Left) := True;
                     end if;
                  end;
               end loop;
            end if;
            if Got (True) and then Got (False) then
               declare
                  use AMV.Dimensioning;
                  --  The two taught holes on the left as seen.
                  Y     : Real := 0.0;
                  Mid   : Real := 0.0;
                  Tool  : Ks_Distance_Point_Line_Tool;
                  RA    : constant Real :=
                    AMV.Misc.Deg_To_Rad (B.Right.Degrees);
                  Left  : AMV.Shapes.Ks_Line renames Lines (True);
                  LA    : constant Real := Left.Rotation;
               begin
                  for J in Hole_Set'Range loop
                     Mid := Mid + Taught_Hole (Pose, J).X / 4.0;
                  end loop;
                  for J in Hole_Set'Range loop
                     if Taught_Hole (Pose, J).X < Mid then
                        Y := Y + Taught_Hole (Pose, J).Y / 2.0;
                     end if;
                  end loop;
                  declare
                     XL    : constant Real := X_At (B.Left, Y);
                     Truth : constant Real :=
                       abs (-(XL - B.Right.X) * EF.Sin (RA)
                            + (Y - B.Right.Y) * EF.Cos (RA));
                  begin
                     Tool.Input_Image := Image;
                     Tool.X := Left.X
                       + (Y - Left.Y) * EF.Cos (LA) / EF.Sin (LA);
                     Tool.Y := Y;
                     Tool.Line := Lines (False);
                     Tool.Run;
                     Check (Tool.Run_Status.Result = Accept_Result,
                            Set_Name (B) & " width: accepted");
                     Check_Near (AMV.Dimensioning.Distance (Tool), Truth,
                                 Width_Base + B.Left.S + B.Right.S,
                                 Set_Name (B) & " width");
                  end;
               end;
            else
               Fail (Set_Name (B) & " width: an outline was not found");
            end if;
         end;
      end loop;
   end Test_PCB_Width;

   --  The width again, with one caliper in pair mode: the caliper crosses
   --  the whole board through the centre of the taught holes, along their
   --  rows (both as mapped by the fixture), 24 px beyond the nominal width
   --  (952 px) on each side. It must pick the outline among the other
   --  edges of the right polarities (the felt outside, the transducer
   --  rings inside, the light band outside the obliquely lit edge). The
   --  reference is the distance between the two reference lines along the
   --  caliper's axis, the tolerance that of the width above (Width_Base +
   --  S + S).
   --
   --  Parameters chosen on the tuning boards, then run once on the
   --  evaluation boards: the default pair scorer (the width nearest the
   --  expected one), the contrast threshold and filter of Find Line above
   --  (20, half size 1) and a projection 20 px long. They are close to
   --  the limits: the outline facing away from the light has a contrast
   --  of only 20 .. 30 grey levels on some boards, so a threshold of 30 or
   --  a 10 px projection loses it there; a scorer that prefers the widest
   --  pair takes the light band outside the outline (up to 10 px out).

   procedure Test_PCB_Caliper_Width is
      use AMV.Caliper;
      Nominal : constant := 952.0;
      T       : Board renames Boards (1);
   begin
      Section ("Gauging: VisA pcb1 board width (one Caliper, edge pair)");
      for I in Boards'Range loop
         declare
            B     : Board renames Boards (I);
            Found : Boolean;
            Pose  : AMV.Transforms.Ks_Transform_2D_Linear;
            Label : constant String := Set_Name (B) & " caliper width";
         begin
            Find_Fixture (I, Found, Pose);
            if not Found then
               Fail (Label & ": no fixture");
            else
               declare
                  H     : Hole_Set renames T.Holes;
                  C     : Point := (0.0, 0.0);
                  VX, VY : Real;
                  Norm  : Real;
                  UX, UY : Real;
                  Tool  : Ks_Caliper_Tool;

                  function Crossing (E : Edge) return Real;
                  --  The position along the caliper's axis (from its
                  --  centre) where the axis meets the reference line E.

                  function Crossing (E : Edge) return Real is
                     A  : constant Real := AMV.Misc.Deg_To_Rad (E.Degrees);
                     EX : constant Real := EF.Cos (A);
                     EY : constant Real := EF.Sin (A);
                  begin
                     return ((E.X - C.X) * EY - (E.Y - C.Y) * EX)
                       / (UX * EY - UY * EX);
                  end Crossing;
               begin
                  for J in Hole_Set'Range loop
                     C := (C.X + Taught_Hole (Pose, J).X / 4.0,
                           C.Y + Taught_Hole (Pose, J).Y / 4.0);
                  end loop;
                  Pose.Map_Vector ((H (2).X - H (1).X) + (H (4).X - H (3).X),
                                   (H (2).Y - H (1).Y) + (H (4).Y - H (3).Y),
                                   VX, VY);
                  Norm := EF.Sqrt (VX ** 2 + VY ** 2);
                  UX := VX / Norm;
                  UY := VY / Norm;
                  Tool.Input_Image := Load ("visa_pcb1_" & B.Name);
                  Tool.Region.Set_Center_Lengths_Rotation_Skew
                    (C.X, C.Y, Nominal + 48.0, 20.0, EF.Arctan (UY, UX), 0.0);
                  Tool.Run_Params.Edge_Mode := Code (Pair);
                  Tool.Run_Params.Edge_0_Polarity := Code (Dark_To_Light);
                  Tool.Run_Params.Edge_1_Polarity := Code (Light_To_Dark);
                  Tool.Run_Params.Edge_0_Position := -Nominal / 2.0;
                  Tool.Run_Params.Edge_1_Position := Nominal / 2.0;
                  Tool.Run_Params.Contrast_Threshold := 20.0;
                  Tool.Run_Params.Filter_Half_Size_In_Pixels := 1;
                  Tool.Run;
                  Check (Tool.Run_Status.Result = Accept_Result
                         and then Tool.Results.Count = 1, Label & ": found");
                  if Tool.Results.Count = 1 then
                     if B.Name = Known_Bad_Outline then
                        Check (abs (Tool.Results.Item (0).Width
                                    - abs (Crossing (B.Right)
                                           - Crossing (B.Left)))
                                 > Width_Base + B.Left.S + B.Right.S,
                               Label & ": known failure still fails");
                     else
                        Check_Near
                          (Tool.Results.Item (0).Width,
                           abs (Crossing (B.Right) - Crossing (B.Left)),
                           Width_Base + B.Left.S + B.Right.S, Label);
                     end if;
                  end if;
               end;
            end if;
         end;
      end loop;
   end Test_PCB_Caliper_Width;

   ---------------------------------------------------------------------
   --  PMAlign: the pose of VisA pcb1 boards, judged by their holes
   ---------------------------------------------------------------------

   --  The fixture's pattern (above) finds every board at any angle (some
   --  are turned by 180 degrees) and scale 0.95 .. 1.05. The four
   --  reference holes of 0000, mapped by the pose, must land on the
   --  board's reference holes.

   PCB_Pose_Tolerance : constant := 9.5;
   --  1.5 times the largest error on the tuning boards (6.14 px), rounded
   --  up. Coarse: the pose follows the components (the tall transducer
   --  rings above all) and the routed outline, the reference is the
   --  board's holes; on each physical board these sit differently: the
   --  outline's width varies by up to 0.8 % against the holes' spacing
   --  (947.8 .. 957.4 px for about 891 px), and the transducers turn by
   --  about 0.1 degree against the board. PMAlign's own error on a rigid
   --  scene is what the resampling test below measures.

   procedure Test_PCB_Pose is
   begin
      Section ("PMAlign: VisA pcb1 board poses (holes as ground truth)");
      for I in Boards'Range loop
         declare
            B     : Board renames Boards (I);
            Found : Boolean;
            Pose  : AMV.Transforms.Ks_Transform_2D_Linear;
            Worst : Real := 0.0;
         begin
            Find_Fixture (I, Found, Pose);
            Check (Found, Set_Name (B) & " pose: found");
            if Found then
               for J in Hole_Set'Range loop
                  declare
                     P : constant Point := Taught_Hole (Pose, J);
                     K : constant Positive := Nearest_Hole (B, P);
                  begin
                     Worst := Real'Max
                       (Worst, Distance (P, (B.Holes (K).X, B.Holes (K).Y)));
                  end;
               end loop;
               Check (Worst <= PCB_Pose_Tolerance,
                      Set_Name (B) & " pose: holes predicted within"
                      & " tolerance (worst" & Integer (Worst * 1000.0)'Image
                      & "e-3 px)");
            end if;
         end;
      end loop;
   end Test_PCB_Pose;

   ---------------------------------------------------------------------
   --  Polar Unwrap: the mounting holes, unwrapped about the circles found
   ---------------------------------------------------------------------

   --  Each hole found as above (fixture, Find Circle twice) is unwrapped
   --  about the circle found, radii r - 8 .. r + 8, into a 120 x 16 strip
   --  (angle 0 at +x, growing clockwise as displayed). At 12 angles a
   --  caliper (5 columns, 15 degrees, searching outwards) finds the hole's
   --  edge in the strip, and the same caliper finds it in the original
   --  image along the ray at that angle (a 4.5 px projection, the 15
   --  degree arc at that radius). The two radii must agree: the strip's
   --  row, through the documented mapping (radius R0 + row + 1/2), must
   --  be where the edge is. Both sides use AMV's caliper, so this checks
   --  the unwrap against a direct measurement of the same real edge; the
   --  arc against its chord differs by about 0.05 px. (Against the
   --  reference circle the edge differs by up to 3 px at some angles: real
   --  holes are not round to that precision, which says nothing about the
   --  unwrap.)

   Unwrap_Tolerance : constant := 0.1;
   --  The median difference (tuning max 0.044 px), 1.5 times rounded up.
   Unwrap_Angles    : constant := 8;
   --  Angles with the edge found both ways, at least (tuning: 10 .. 12).  --  set from the tuning boards

   procedure Test_PCB_Hole_Unwrap is
      use AMV.Caliper;
      use AMV.Image_Processing.Polar_Unwrap;
      Strip_Width : constant := 120;
      Angles      : constant := 12;

      procedure Measure (Tool : in out Ks_Caliper_Tool) is
      begin
         Tool.Run_Params.Edge_0_Polarity := Code (Dark_To_Light);
         Tool.Run_Params.Contrast_Threshold := 20.0;
         Tool.Run_Params.Filter_Half_Size_In_Pixels := 1;
         Tool.Run;
      end Measure;
      --  The hole's edge (dark to light outwards), with the hole finder's
      --  edge settings.
   begin
      Section ("Polar Unwrap: VisA pcb1 mounting holes");
      for I in Boards'Range loop
         declare
            B     : Board renames Boards (I);
            Image : constant Ks_Image_8_Grey := Load ("visa_pcb1_" & B.Name);
            Found : Boolean;
            Pose  : AMV.Transforms.Ks_Transform_2D_Linear;
         begin
            Find_Fixture (I, Found, Pose);
            if not Found then
               Fail (Set_Name (B) & " hole unwrap: no fixture");
            end if;
            for J in Hole_Set'Range loop
               exit when not Found;
               declare
                  Start : constant Point := Taught_Hole (Pose, J);
                  K     : constant Positive := Nearest_Hole (B, Start);
                  Label : constant String :=
                    Set_Name (B) & " hole" & K'Image & " unwrapped: ";
                  Ok    : Boolean;
                  C     : AMV.Shapes.Ks_Circle;
               begin
                  Find_Hole (Image, Start, Ok, C);
                  if Ok then
                     declare
                        R0      : constant Real := C.Radius - 8.0;
                        R1      : constant Real := C.Radius + 8.0;
                        Tool    : Ks_Polar_Unwrap_Tool;
                        Diffs   : array (1 .. Angles) of Real;
                        Count   : Natural := 0;
                     begin
                        Tool.Input_Image := Image;
                        Tool.Region
                          .Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
                            (C.Center_X, C.Center_Y, R0, 0.0,
                             2.0 * Ada.Numerics.Pi, R1 / R0);
                        Tool.Run_Params.Scaling_X :=
                          Real (Strip_Width) / (Ada.Numerics.Pi * (R0 + R1));
                        Tool.Run;
                        Check (Tool.Run_Status.Result = Accept_Result
                               and then Tool.Output_Image.Width = Strip_Width
                               and then Tool.Output_Image.Height = 16,
                               Label & "120 x 16 strip");
                        if Tool.Run_Status.Result = Accept_Result then
                           for N in 0 .. Angles - 1 loop
                              declare
                                 Step  : constant Real :=
                                   Real (Strip_Width / Angles);
                                 X     : constant Real :=
                                   (Real (N) + 0.5) * Step - 0.5;
                                 Theta : constant Real :=
                                   2.0 * Ada.Numerics.Pi * (Real (N) + 0.5)
                                   / Real (Angles);
                                 Cal   : Ks_Caliper_Tool;
                                 Ray   : Ks_Caliper_Tool;
                              begin
                                 Cal.Input_Image := Tool.Output_Image;
                                 Cal.Region.Set_Center_Lengths_Rotation_Skew
                                   (X, 7.5, 8.0, 5.0, Ada.Numerics.Pi / 2.0,
                                    0.0);
                                 Ray.Input_Image := Image;
                                 Ray.Region.Set_Center_Lengths_Rotation_Skew
                                   (C.Center_X + C.Radius * EF.Cos (Theta),
                                    C.Center_Y + C.Radius * EF.Sin (Theta),
                                    8.0, C.Radius * Ada.Numerics.Pi / 12.0,
                                    Theta, 0.0);
                                 Measure (Cal);
                                 Measure (Ray);
                                 if Cal.Results.Count = 1
                                   and then Ray.Results.Count = 1
                                 then
                                    Count := Count + 1;
                                    Diffs (Count) :=
                                      abs ((R0 + 7.5 + 0.5
                                            + Cal.Results.Item (0).Position)
                                           - (C.Radius
                                              + Ray.Results.Item (0)
                                                  .Position));
                                 end if;
                              end;
                           end loop;
                           --  The median of the differences: where the
                           --  edge is faint or doubled the two calipers can
                           --  take different edges at an angle, while an
                           --  error of the mapping would move them all.
                           for A in 2 .. Count loop
                              for Z in reverse 2 .. A loop
                                 exit when Diffs (Z - 1) <= Diffs (Z);
                                 declare
                                    Swap : constant Real := Diffs (Z);
                                 begin
                                    Diffs (Z) := Diffs (Z - 1);
                                    Diffs (Z - 1) := Swap;
                                 end;
                              end loop;
                           end loop;
                           Check (Count >= Unwrap_Angles,
                                  Label & "edge found in the strip and"
                                  & " directly at" & Count'Image & " of"
                                  & Angles'Image & " angles");
                           if Count >= 1 then
                              Check (Diffs ((Count + 1) / 2)
                                       <= Unwrap_Tolerance,
                                     Label & "radius as measured directly"
                                     & " (median difference"
                                     & Integer (Diffs ((Count + 1) / 2)
                                                * 1000.0)'Image
                                     & "e-3 px)");
                           end if;
                        end if;
                     end;
                  end if;
               end;
            end loop;
         end;
      end loop;
   end Test_PCB_Hole_Unwrap;

   --  PMAlign's own accuracy: a board image resampled (affine transform
   --  tool) turned, scaled and moved by known amounts. The output keeps
   --  the input's coordinate tree, so a pattern trained on the original
   --  must be found with the identity pose in the output's selected space;
   --  the holes, mapped by the pose, must stay where they are. The
   --  tolerance is 1.5 times the largest error on the tuning transforms
   --  (board 0000), rounded up; the evaluation boards and transforms were
   --  run only after.

   PM_Resampled_Tolerance : constant := 0.15;  --  (tuning max 0.075 px)

   type Similarity is record
      Degrees, Scale : Real;
   end record;

   type Similarity_List is array (Positive range <>) of Similarity;

   procedure PM_Resampled
     (Set_Name : String; B : Board; Transforms : Similarity_List)
   is
      use AMV.PM_Align;
      Image  : constant Ks_Image_8_Grey := Load ("visa_pcb1_" & B.Name);
      Tool   : Ks_PM_Align_Tool;
      Region : AMV.Shapes.Ks_Rectangle;
      CX     : constant Real :=
        (B.Holes (1).X + B.Holes (2).X + B.Holes (3).X + B.Holes (4).X)
        / 4.0;
      CY     : constant Real :=
        (B.Holes (1).Y + B.Holes (2).Y + B.Holes (3).Y + B.Holes (4).Y)
        / 4.0;
   begin
      Region.Set_Center_Width_Height (CX, CY, 1030.0, 480.0);
      Tool.Pattern.Set_Train_Image (Image);
      Tool.Pattern.Set_Train_Region
        (AMV.Shapes.Region_Holders.To_Holder (Region));
      Tool.Pattern.Set_Grain_Limit_Auto_Select (False);
      Tool.Pattern.Set_Grain_Limit_Fine (4.0);
      Tool.Pattern.Set_Grain_Limit_Coarse (32.0);
      Tool.Pattern.Train;
      Tool.Run_Params.Zone_Angle.Configuration := Code (Low_High);
      Tool.Run_Params.Zone_Angle.Low := -Ada.Numerics.Pi;
      Tool.Run_Params.Zone_Angle.High := Ada.Numerics.Pi;
      Tool.Run_Params.Zone_Scale.Configuration := Code (Low_High);
      Tool.Run_Params.Zone_Scale.Low := 0.9;
      Tool.Run_Params.Zone_Scale.High := 1.1;
      Tool.Run_Params.Accept_Threshold := 0.3;
      for T of Transforms loop
         declare
            Affine : AMV.Image_Processing.Affine_Transform
                       .Ks_Affine_Transform_Tool;
            Label  : constant String :=
              Set_Name & " " & B.Name & " turned" & Integer (T.Degrees)'Image
              & " deg, scaled" & Integer (T.Scale * 100.0)'Image & "%: ";
         begin
            Affine.Input_Image := Image;
            Affine.Region.Set_Center_Lengths_Rotation_Skew
              (CX + 0.37, CY - 0.61, 1200.0, 900.0,
               AMV.Misc.Deg_To_Rad (T.Degrees), 0.0);
            Affine.Run_Params.Scaling_X := T.Scale;
            Affine.Run_Params.Scaling_Y := T.Scale;
            Affine.Run;
            Check (Affine.Run_Status.Result = Accept_Result,
                   Label & "resampled");
            Tool.Input_Image := Affine.Output_Image;
            Tool.Run;
            Check (Tool.Run_Status.Result = Accept_Result
                   and then Tool.Results.Count = 1, Label & "found");
            if Tool.Results.Count = 1 then
               declare
                  Pose   : constant AMV.Transforms.Ks_Transform_2D_Linear :=
                    Get_Pose (Tool.Results.Item (0));
                  Worst  : Real := 0.0;
                  PX, PY : Real;
               begin
                  for H of B.Holes loop
                     Pose.Map_Point (H.X, H.Y, PX, PY);
                     Worst := Real'Max (Worst, Distance ((PX, PY), (H.X, H.Y)));
                  end loop;
                  Check (Worst <= PM_Resampled_Tolerance,
                         Label & "holes stay (worst"
                         & Integer (Worst * 1000.0)'Image & "e-3 px)");
               end;
            end if;
         end;
      end loop;
   end PM_Resampled;

   procedure Test_PM_Resampled is
   begin
      Section ("PMAlign: resampled VisA pcb1 boards (known poses)");
      PM_Resampled ("tuning", Boards (1),
                    [(30.0, 1.0), (-90.0, 0.97), (180.0, 1.03)]);
      PM_Resampled ("evaluation", Boards (11),
                    [(-47.0, 1.02), (123.0, 0.98)]);
      PM_Resampled ("evaluation", Boards (15),
                    [(-47.0, 1.02), (123.0, 0.98)]);
   end Test_PM_Resampled;

   ---------------------------------------------------------------------
   --  PMAlign with its default settings (the grain chosen at run time)
   ---------------------------------------------------------------------

   --  With GrainLimitAutoSelect (the default) PMAlign chooses the level at
   --  which it measures its results per run (see AMV.Kernels.PM_Align).
   --  Before, with the defaults it found 2 of the 10 tuning boards of pcb1
   --  (the fine mesh and the lettering differ from board to board), which
   --  is why the fixture above sets its grain limits by hand. Here the
   --  same series with the defaults, the same tuning / evaluation split:
   --  the fixture's pattern and run parameters but no grain limits: every
   --  board found, 0000's holes mapped by the pose within
   --  PCB_Default_Tolerance of the board's holes.

   PCB_Default_Tolerance : constant := 11.5;
   --  1.5 times the largest error on the tuning boards (7.49 px, board
   --  0750), rounded up; with grains 4 .. 32 by hand the fixture's pose
   --  reaches 6.14 px there.

   procedure Test_PM_Defaults is
      use AMV.PM_Align;
   begin
      Section ("PMAlign with its default settings (grain chosen at run"
               & " time)");
      declare
         Train  : constant Board := Boards (1);
         Image  : constant Ks_Image_8_Grey := Load ("visa_pcb1_" & Train.Name);
         Tool   : Ks_PM_Align_Tool;
         Region : AMV.Shapes.Ks_Rectangle;
         X0     : constant Real :=
           Real'Min (Train.Holes (1).X, Train.Holes (3).X) - 60.0;
         X1     : constant Real :=
           Real'Max (Train.Holes (2).X, Train.Holes (4).X) + 60.0;
         Y0     : constant Real :=
           Real'Min (Train.Holes (1).Y, Train.Holes (2).Y) - 60.0;
         Y1     : constant Real :=
           Real'Max (Train.Holes (3).Y, Train.Holes (4).Y) + 60.0;
      begin
         Region.Set_XY_Width_Height (X0, Y0, X1 - X0, Y1 - Y0);
         Tool.Pattern.Set_Train_Image (Image);
         Tool.Pattern.Set_Train_Region
           (AMV.Shapes.Region_Holders.To_Holder (Region));
         Tool.Pattern.Train;
         Tool.Run_Params.Zone_Angle.Configuration := Code (Low_High);
         Tool.Run_Params.Zone_Angle.Low := -Ada.Numerics.Pi;
         Tool.Run_Params.Zone_Angle.High := Ada.Numerics.Pi;
         Tool.Run_Params.Zone_Scale.Configuration := Code (Low_High);
         Tool.Run_Params.Zone_Scale.Low := 0.95;
         Tool.Run_Params.Zone_Scale.High := 1.05;
         Tool.Run_Params.Accept_Threshold := 0.3;
         for B of Boards loop
            Tool.Input_Image := Load ("visa_pcb1_" & B.Name);
            Tool.Run;
            Check (Tool.Run_Status.Result = Accept_Result
                   and then Tool.Results.Count = 1,
                   Set_Name (B) & " default grain: found");
            if Tool.Results.Count = 1 then
               declare
                  Pose  : constant AMV.Transforms.Ks_Transform_2D_Linear :=
                    Get_Pose (Tool.Results.Item (0));
                  Worst : Real := 0.0;
               begin
                  for H of Train.Holes loop
                     declare
                        P : constant Point := Mapped (Pose, (H.X, H.Y));
                        K : constant Positive := Nearest_Hole (B, P);
                     begin
                        Worst := Real'Max
                          (Worst,
                           Distance (P, (B.Holes (K).X, B.Holes (K).Y)));
                     end;
                  end loop;
                  Check (Worst <= PCB_Default_Tolerance,
                         Set_Name (B) & " default grain: holes predicted"
                         & " within tolerance (worst"
                         & Integer (Worst * 1000.0)'Image & "e-3 px)");
               end;
            end if;
         end loop;
      end;
   end Test_PM_Defaults;

   ---------------------------------------------------------------------
   --  CNL Search: sub-pixel shifts of real images
   ---------------------------------------------------------------------

   --  A real image is resampled (affine transform tool, bilinear) on a
   --  grid moved by a known shift. The output keeps the input's coordinate
   --  tree, so the pattern must be found at its own origin in the output's
   --  selected space, whatever the shift. Tolerances chosen on the tuning
   --  shifts of box.png (largest location error 0.136 px, lowest score
   --  0.70 at half-pixel shifts, where bilinear resampling blurs most):
   --  1.5 times the error, rounded up, and 0.75 times the score. The
   --  evaluation shifts of a VisA board were run only after.

   CNL_Location_Tolerance : constant := 0.2;
   CNL_Min_Score          : constant := 0.5;

   type Shift is record
      DX, DY : Real;
   end record;

   type Shift_List is array (Positive range <>) of Shift;

   procedure CNL_Shifts
     (Set_Name         : String;
      Image_Name       : String;
      CX, CY           : Real;
      --  The centre of the image (pixel space).
      Width, Height    : Real;
      --  The resampled area.
      PX, PY           : Real;
      PW, PH           : Real;
      --  The pattern: centre (its origin) and size.
      Shifts           : Shift_List)
   is
      use AMV.CNL_Search;
      Image   : constant Ks_Image_8_Grey := Load (Image_Name);
      Pattern : Ks_CNL_Search_Pattern;
      Region  : AMV.Shapes.Ks_Rectangle;
   begin
      Region.Set_Center_Width_Height (PX, PY, PW, PH);
      Pattern.Set_Train_Image (Image);
      Pattern.Set_Train_Region
        (AMV.Shapes.Region_Holders.To_Holder (Region));
      Pattern.Set_Origin_X (PX);
      Pattern.Set_Origin_Y (PY);
      Pattern.Train;

      for S of Shifts loop
         declare
            Affine : AMV.Image_Processing.Affine_Transform
                       .Ks_Affine_Transform_Tool;
            Tool   : Ks_CNL_Search_Tool;
            Label  : constant String :=
              Set_Name & " shift" & Integer (S.DX * 100.0)'Image & "e-2,"
              & Integer (S.DY * 100.0)'Image & "e-2: ";
         begin
            Affine.Input_Image := Image;
            Affine.Region.Set_Center_Lengths_Rotation_Skew
              (CX + S.DX, CY + S.DY, Width, Height, 0.0, 0.0);
            Affine.Run;
            Check (Affine.Run_Status.Result = Accept_Result,
                   Label & "resampled");
            Tool.Pattern := Pattern;
            Tool.Input_Image := Affine.Output_Image;
            Tool.Run;
            Check (Tool.Run_Status.Result = Accept_Result
                   and then Tool.Results.Count = 1, Label & "found");
            if Tool.Results.Count = 1 then
               declare
                  R : constant Ks_CNL_Search_Result := Tool.Results.Item (0);
                  E : constant Real :=
                    Distance ((R.Location_X, R.Location_Y), (PX, PY));
               begin
                  Check (E <= CNL_Location_Tolerance,
                         Label & "location (" & Integer (E * 1000.0)'Image
                         & "e-3 px)");
                  Check (R.Score >= CNL_Min_Score,
                         Label & "score (" & Integer (R.Score * 1000.0)'Image
                         & "e-3)");
               end;
            end if;
         end;
      end loop;
   end CNL_Shifts;


   CNL_Partial_Tolerance : constant := 0.3;
   --  1.5 times the largest location error of the tuning cuts (0.178 px),
   --  rounded up to 0.05 px; the score of the whole-window shifts
   --  (CNL_Min_Score) still applies (tuning: at least 0.696).

   --  Partial matches: the same patterns in crops whose border cuts
   --  through them, so that part of the pattern lies outside the search
   --  area (the whole crop). The crop is resampled as above (the affine
   --  transform tool, bilinear, on a grid moved by a sub-pixel shift), and
   --  keeps the input's coordinate tree, so the pattern must again be
   --  found at its own origin, with EdgeHit naming the side the crop cuts.
   --  The limit of that side is half the pattern's size there (the
   --  largest allowed), the other limits 0. With PartialMatchReduceScore
   --  the score must not exceed the fraction of the pattern inside the
   --  crop.

   type Cut is record
      Side    : AMV.CNL_Search.Ks_CNL_Search_Edge_Hit_Constants;
      Outside : Real;
      --  The pattern's columns (Left, Right) or rows (Top, Bottom) the
      --  crop leaves out.
      DX, DY  : Real;
      --  The sub-pixel shift of the crop's grid.
   end record;

   type Cut_List is array (Positive range <>) of Cut;

   procedure CNL_Partial
     (Set_Name   : String;
      Image_Name : String;
      PX, PY     : Real;
      PW, PH     : Real;
      --  The pattern: centre (its origin) and size.
      Cuts       : Cut_List);

   procedure CNL_Partial
     (Set_Name   : String;
      Image_Name : String;
      PX, PY     : Real;
      PW, PH     : Real;
      Cuts       : Cut_List)
   is
      use AMV.CNL_Search;
      Image   : constant Ks_Image_8_Grey := Load (Image_Name);
      Pattern : Ks_CNL_Search_Pattern;
      Region  : AMV.Shapes.Ks_Rectangle;
      Margin  : constant Real := Real'Max (PW, PH) / 2.0 + 10.0;
      --  The crop reaches this far beyond the pattern on the sides it
      --  does not cut, so that it stays larger than the pattern (a search
      --  area smaller than the pattern gives no result, whatever the
      --  limits).
   begin
      Region.Set_Center_Width_Height (PX, PY, PW, PH);
      Pattern.Set_Train_Image (Image);
      Pattern.Set_Train_Region
        (AMV.Shapes.Region_Holders.To_Holder (Region));
      Pattern.Set_Origin_X (PX);
      Pattern.Set_Origin_Y (PY);
      Pattern.Train;

      for C of Cuts loop
         declare
            --  The crop: the pattern's box widened by Margin, then cut by
            --  Outside on side C.Side.
            X0 : Real := PX - PW / 2.0 - Margin;
            X1 : Real := PX + PW / 2.0 + Margin;
            Y0 : Real := PY - PH / 2.0 - Margin;
            Y1 : Real := PY + PH / 2.0 + Margin;
            Inside : Real;
            Label  : constant String :=
              Set_Name & " cut" & C.Side'Image & " by"
              & Integer (C.Outside)'Image & " px, shift"
              & Integer (C.DX * 100.0)'Image & "e-2,"
              & Integer (C.DY * 100.0)'Image & "e-2: ";
         begin
            if C.Side = Left then
               X0 := PX - PW / 2.0 + C.Outside;
               Inside := 1.0 - C.Outside / PW;
            elsif C.Side = Right then
               X1 := PX + PW / 2.0 - C.Outside;
               Inside := 1.0 - C.Outside / PW;
            elsif C.Side = Top then
               Y0 := PY - PH / 2.0 + C.Outside;
               Inside := 1.0 - C.Outside / PH;
            else
               Y1 := PY + PH / 2.0 - C.Outside;
               Inside := 1.0 - C.Outside / PH;
            end if;
            for Reduce in Boolean loop
               declare
                  Affine : AMV.Image_Processing.Affine_Transform
                             .Ks_Affine_Transform_Tool;
                  Tool   : Ks_CNL_Search_Tool;
                  Name   : constant String :=
                    Label & (if Reduce then "reduced score: " else "");
               begin
                  Affine.Input_Image := Image;
                  Affine.Region.Set_Center_Lengths_Rotation_Skew
                    ((X0 + X1) / 2.0 + C.DX, (Y0 + Y1) / 2.0 + C.DY,
                     X1 - X0, Y1 - Y0, 0.0, 0.0);
                  Affine.Run;
                  Check (Affine.Run_Status.Result = Accept_Result,
                         Name & "cropped");
                  Tool.Pattern := Pattern;
                  Tool.Input_Image := Affine.Output_Image;
                  if C.Side = Left then
                     Tool.Run_Params.Partial_Match_Limit_Left :=
                       AMV.Kernels.Int32 (Pattern.Trained_Pattern_Width / 2);
                  elsif C.Side = Right then
                     Tool.Run_Params.Partial_Match_Limit_Right :=
                       AMV.Kernels.Int32 (Pattern.Trained_Pattern_Width / 2);
                  elsif C.Side = Top then
                     Tool.Run_Params.Partial_Match_Limit_Up :=
                       AMV.Kernels.Int32 (Pattern.Trained_Pattern_Height / 2);
                  else
                     Tool.Run_Params.Partial_Match_Limit_Down :=
                       AMV.Kernels.Int32 (Pattern.Trained_Pattern_Height / 2);
                  end if;
                  Tool.Run_Params.Partial_Match_Reduce_Score :=
                    (if Reduce then 1 else 0);
                  Tool.Run;
                  Check (Tool.Run_Status.Result = Accept_Result
                         and then Tool.Results.Count = 1,
                         Name & "found (" & Tool.Run_Status.Message & ")");
                  if Tool.Results.Count = 1 then
                     declare
                        R : constant Ks_CNL_Search_Result :=
                          Tool.Results.Item (0);
                        E : constant Real :=
                          Distance ((R.Location_X, R.Location_Y), (PX, PY));
                     begin
                        Ada.Text_IO.Put_Line
                          ("  cnl partial " & Name & "location"
                           & Integer (E * 1000.0)'Image & "e-3 px, score"
                           & Integer (R.Score * 1000.0)'Image
                           & "e-3, inside"
                           & Integer (Inside * 1000.0)'Image & "e-3");
                        Check (R.Edge_Hit = C.Side,
                               Name & "EdgeHit" & R.Edge_Hit'Image);
                        Check (E <= CNL_Partial_Tolerance,
                               Name & "location ("
                               & Integer (E * 1000.0)'Image & "e-3 px)");
                        if Reduce then
                           Check (R.Score <= Inside + 0.02,
                                  Name & "score within the fraction"
                                  & " inside");
                        else
                           Check (R.Score >= CNL_Min_Score,
                                  Name & "score ("
                                  & Integer (R.Score * 1000.0)'Image
                                  & "e-3)");
                        end if;
                     end;
                  end if;
               end;
            end loop;
         end;
      end loop;
   end CNL_Partial;

   procedure Test_CNL_Partial is
      use AMV.CNL_Search;
   begin
      Section ("CNL Search: partial matches in real images cut by the crop");
      --  Tuning: box.png, the pattern of the shift test above.
      CNL_Partial ("tuning box", "box", 110.0, 120.0, 96.0, 64.0,
                   [(Left, 20.0, 0.0, 0.0), (Left, 40.0, 0.25, 0.5),
                    (Right, 30.0, 0.5, 0.0), (Right, 45.0, 0.0, 0.25),
                    (Top, 16.0, 0.75, 0.0), (Top, 28.0, 0.0, 0.5),
                    (Bottom, 12.0, 0.5, 0.5), (Bottom, 30.0, 0.25, 0.75)]);
      --  Evaluation: VisA pcb1 0000, the "HC-SR04" lettering of the shift
      --  test (160 x 60 about (655, 593)).
      CNL_Partial ("evaluation pcb1 0000", "visa_pcb1_0000",
                   655.0, 593.0, 160.0, 60.0,
                   [(Left, 50.0, 0.3, 0.7), (Right, 70.0, -0.6, 0.2),
                    (Top, 20.0, 0.45, -0.15), (Bottom, 25.0, -0.8, 0.55)]);
   end Test_CNL_Partial;

   procedure Test_CNL_Shift is
   begin
      Section ("CNL Search: real images resampled at sub-pixel shifts");
      --  Tuning: box.png, the "BASTONCINI" lettering and the photo's
      --  corner (96 x 64 about (110, 120)). The image's centre is
      --  (161.5, 111); 111.5 puts the unshifted grid on whole pixels.
      CNL_Shifts ("tuning box", "box", 161.5, 111.5, 300.0, 200.0,
                  110.0, 120.0, 96.0, 64.0,
                  [(0.0, 0.0), (0.25, 0.0), (0.5, 0.0), (0.75, 0.0),
                   (0.0, 0.25), (0.5, -0.5), (12.3, -7.6), (-5.75, 3.4)]);
      --  Evaluation: VisA pcb1 0000, the "HC-SR04" lettering
      --  (160 x 60 about (655, 593)).
      CNL_Shifts ("evaluation pcb1 0000", "visa_pcb1_0000",
                  701.5, 535.0, 1300.0, 1000.0, 655.0, 593.0, 160.0, 60.0,
                  [(0.3, 0.7), (-0.6, 0.2), (7.45, -3.15), (-11.8, 5.55),
                   (0.9, -0.35)]);
   end Test_CNL_Shift;

   ---------------------------------------------------------------------
   --  Sharpness: BBBC006 focus stacks
   ---------------------------------------------------------------------

   --  Five fields of view of BBBC006 (nuclei, Hoechst), each at 17 focal
   --  planes z = 0, 2, .. 32 (2 um apart). The ground truth is the
   --  collection's: z = 11 .. 23 are in focus. The 16-bit images are read
   --  as 8-bit with the same gain for all (maxval 4095, the 12-bit
   --  camera's range), so scores of one field compare.
   --
   --  Chosen on the tuning fields (a01_s1, d04_s1), then run once on the
   --  evaluation fields (g07_s1, j10_s1, m13_s1):
   --  * GradientEnergy without smoothing (the default): the sharpest plane
   --    lies in the in-focus range, the scores rise strictly up to it and
   --    fall strictly after it, and it scores at least 1.9 times as much
   --    as either end of the stack (half the smallest tuning ratio, 3.8 on
   --    a01, whose peak at z = 22 is nearer the z = 32 end). Smoothing
   --    (1, 2 or 4) moves the peak of the sparse field a01 to z = 24, out
   --    of the range.
   --  * AbsDiff at distance 2: only the sharpest plane in the in-focus
   --    range; on a sparse field its scores are nearly flat (43 .. 52 at
   --    distance 1), so the order of the other planes is not checked.

   procedure Test_Focus_Stacks is
      use AMV.Image_Processing.Sharpness;
      type Score_List is array (0 .. 16) of Real;

      function Scores (Field : String; Gradient : Boolean) return Score_List
      is
         Result : Score_List := [others => 0.0];
      begin
         for K in Score_List'Range loop
            declare
               Z     : constant String := Integer'Image (100 + 2 * K);
               File  : constant String :=
                 Directory & "/bbbc006_" & Field & "_z" & Z (3 .. 4) & ".pgm";
               Tool  : Ks_Image_Sharpness_Tool;
            begin
               if not Ada.Directories.Exists (File) then
                  Fail (File & " is missing: run make fetch-real-images");
                  raise Missing;
               end if;
               Tool.Input_Image := AMV.Image_File.Read_Image_8_Grey (File);
               if Gradient then
                  Tool.Run_Params.Mode := Gradient_Energy;
               else
                  Tool.Run_Params.Mode := Abs_Diff;
                  Tool.Run_Params.Abs_Diff_Distance_X := 2;
                  Tool.Run_Params.Abs_Diff_Distance_Y := 2;
               end if;
               Tool.Run;
               Check (Tool.Run_Status.Result = Accept_Result,
                      Field & " z" & Z (3 .. 4) & ": sharpness accepted");
               Result (K) := Tool.Score;
            end;
         end loop;
         return Result;
      end Scores;

      procedure Stack (Set_Name, Field : String) is
         Label : constant String := Set_Name & " " & Field & ": ";
         G     : constant Score_List := Scores (Field, True);
         A     : constant Score_List := Scores (Field, False);
         Peak  : Natural := 0;
         Best  : Natural := 0;
         Rises : Boolean := True;
      begin
         for K in Score_List'Range loop
            if G (K) > G (Peak) then
               Peak := K;
            end if;
            if A (K) > A (Best) then
               Best := K;
            end if;
         end loop;
         for K in 1 .. Score_List'Last loop
            if (K <= Peak and then G (K) <= G (K - 1))
              or else (K > Peak and then G (K) >= G (K - 1))
            then
               Rises := False;
            end if;
         end loop;
         Check (2 * Peak in 11 .. 23,
                Label & "gradient energy: sharpest plane z"
                & Natural'Image (2 * Peak) & " in focus (11 .. 23)");
         Check (Rises, Label & "gradient energy: one peak, strictly falling"
                & " on both sides");
         Check (G (Peak) >= 1.9 * Real'Max (G (0), G (Score_List'Last)),
                Label & "gradient energy: peak at least 1.9 times the ends ("
                & Integer (10.0 * G (Peak)
                           / Real'Max (G (0), G (Score_List'Last)))'Image
                & "e-1)");
         Check (2 * Best in 11 .. 23,
                Label & "abs diff: sharpest plane z" & Natural'Image (2 * Best)
                & " in focus (11 .. 23)");
      end Stack;
   begin
      Section ("Sharpness: BBBC006 focus stacks");
      Stack ("tuning", "a01_s1");
      Stack ("tuning", "d04_s1");
      Stack ("evaluation", "g07_s1");
      Stack ("evaluation", "j10_s1");
      Stack ("evaluation", "m13_s1");
   end Test_Focus_Stacks;

   --  Blob on BBBC039: nuclei of U2OS cells (Hoechst), each drawn by hand
   --  in the dataset's masks (tests/real_images/bbbc039.txt; the masks
   --  become label images, one label per nucleus, tools/zip_png_labels.py).
   --  One parameter set for the series, chosen on the 10 tuning images:
   --  Otsu's threshold (Hard_Dynamic_Threshold, the default), Light_Blobs,
   --  Prune below 30 pixels, no morphology (of Prune 30 or 100, an opening,
   --  and fixed thresholds 20 and 25, this did best on the tuning images).
   --  A blob matches the nucleus whose label lies under its centre of mass
   --  (one blob per nucleus). Per image: the missed fraction (nuclei
   --  without a blob) and the false fraction (blobs on no nucleus, or on
   --  a nucleus already taken). Tuning maxima 0.277 and 0.021 (touching
   --  nuclei merge into one blob: Blob does not split them); tolerances
   --  1.5 times those, rounded up to 0.05.

   Nuclei_Miss_Tolerance  : constant := 0.45;
   Nuclei_False_Tolerance : constant := 0.05;

   Known_Bad_Nuclei : constant String := "eval 02";
   --  The one evaluation failure (the first and only evaluation run:
   --  missed 0.768, false 0.111): a field of small, dim nuclei (median
   --  area 131 pixels against about 650 in the tuning images, mean grey
   --  about 27 against the Otsu threshold 23), most of whose pixels fall
   --  below the threshold, so that what remains is pruned. A global
   --  threshold cannot find them; it stays a known failure, checked to
   --  still fail.

   procedure Test_Nuclei is
      procedure Field (Set_Name : String; N : Positive) is
         Two    : constant String := Integer'Image (100 + N);
         Stem   : constant String :=
           Directory & "/bbbc039_" & Set_Name & "_" & Two (3 .. 4);
         Label  : constant String := Set_Name & " " & Two (3 .. 4) & ": ";
      begin
         if not Ada.Directories.Exists (Stem & ".pgm")
           or else not Ada.Directories.Exists (Stem & "_labels.pgm")
         then
            Fail (Stem & " is missing: run make fetch-real-images");
            raise Missing;
         end if;
         declare
            use AMV.Blob;
            Labels : constant Ks_Image_16_Grey :=
              Ks_Image_16_Grey
                (AMV.Image_File.Read_Image (Stem & "_labels.pgm"));
            Tool   : Ks_Blob_Tool;
            Nuclei : Natural := 0;
            Blobs  : Natural := 0;
            Taken  : array (1 .. 65535) of Boolean := [others => False];
            Found  : Natural := 0;
         begin
            for Y in 0 .. Labels.Height - 1 loop
               for X in 0 .. Labels.Width - 1 loop
                  Nuclei :=
                    Natural'Max (Nuclei, Natural (Labels.Get_Pixel (X, Y)));
               end loop;
            end loop;
            Tool.Input_Image :=
              AMV.Image_File.Read_Image_8_Grey (Stem & ".pgm");
            Tool.Run_Params.Segmentation_Params.Polarity :=
              Code (Light_Blobs);
            Tool.Run_Params.Connectivity_Cleanup := Code (Prune);
            Tool.Run_Params.Connectivity_Min_Pixels := 30;
            Tool.Run;
            Check (Tool.Run_Status.Result = Accept_Result,
                   Label & "blob accepted");
            if Tool.Run_Status.Result /= Accept_Result or else Nuclei = 0
            then
               return;
            end if;
            declare
               C : constant Ks_Blob_Result_Collection'Class :=
                 Tool.Results.Get_Blobs;
            begin
               for I in 0 .. C.Count - 1 loop
                  declare
                     B : constant Ks_Blob_Result := C.Item (I);
                     X : constant Integer := Integer (B.Center_Of_Mass_X);
                     Y : constant Integer := Integer (B.Center_Of_Mass_Y);
                     L : Natural := 0;
                  begin
                     if B.Label /= 0 then
                        Blobs := Blobs + 1;
                        if X in 0 .. Labels.Width - 1
                          and then Y in 0 .. Labels.Height - 1
                        then
                           L := Natural (Labels.Get_Pixel (X, Y));
                        end if;
                        if L > 0 and then not Taken (L) then
                           Taken (L) := True;
                           Found := Found + 1;
                        end if;
                     end if;
                  end;
               end loop;
            end;
            declare
               Missed : constant Real := 1.0 - Real (Found) / Real (Nuclei);
               False_Part : constant Real :=
                 (if Blobs = 0 then 0.0
                  else 1.0 - Real (Found) / Real (Blobs));
            begin
               Ada.Text_IO.Put_Line
                 ("  " & Label & Nuclei'Image & " nuclei," & Blobs'Image
                  & " blobs," & Found'Image & " matched: missed"
                  & Integer (1000.0 * Missed)'Image & "e-3, false"
                  & Integer (1000.0 * False_Part)'Image & "e-3");
               if Set_Name & " " & Two (3 .. 4) = Known_Bad_Nuclei then
                  Check (Missed > Nuclei_Miss_Tolerance,
                         Label & "known failure: still misses more than"
                         & " the tolerance ("
                         & Integer (1000.0 * Missed)'Image & "e-3)");
               else
                  Check (Missed <= Nuclei_Miss_Tolerance,
                         Label & "missed fraction"
                         & Integer (1000.0 * Missed)'Image & "e-3");
                  Check (False_Part <= Nuclei_False_Tolerance,
                         Label & "false fraction"
                         & Integer (1000.0 * False_Part)'Image & "e-3");
               end if;
            end;
         end;
      end Field;
   begin
      Section ("Blob: BBBC039 nuclei");
      for N in 1 .. 10 loop
         Field ("tune", N);
      end loop;
      for N in 1 .. 10 loop
         Field ("eval", N);
      end loop;
   end Test_Nuclei;

   ---------------------------------------------------------------------
   --  Gauging: VisA candle (PMAlign fixture, Find Circle)
   ---------------------------------------------------------------------

   --  Four tea lights in a tray (VisA's candle category): the outer rim of
   --  each light's metal cup, a light rim on the dark tray (the shadow on
   --  one side is darker still). Ground truth measured independently of
   --  AMV, before AMV was run on the images (tools/real_image_reference.py
   --  circle_outer): on 120 rays, the outermost edge whose grey level rises
   --  towards the centre (the rim's outer boundary, not the weaker edge
   --  between the wax and the rim inside it), fitted with a geometric
   --  least-squares circle; S is that fit's RMS (0.5 .. 2.0 px: the cups
   --  are seen slightly from the side and their rims are not perfectly
   --  round).
   --
   --  Tuning images (parameters and tolerances chosen on them only):
   --  0000, 0050, 0150, 0200, 0300, 0350; evaluation images, run once with
   --  the frozen settings: 0450, 0500, 0600, 0650, 0750, 0800.
   --
   --  The tools are placed as a recipe would place them: image 0000's top
   --  left light, taught once (its reference circle), is mapped into each
   --  image by the pose of each light PMAlign finds there (a pattern
   --  trained on that light: the light's area, origin the identity, so a
   --  pose maps 0000's coordinates into the other image's). No tool starts
   --  from an image's own references, which only judge the results (and
   --  name the light a result belongs to).

   type Rim is record
      X, Y, R, S : Real;
   end record;

   type Rim_Set is array (1 .. 4) of Rim;
   --  Top left, top right, bottom left, bottom right, as seen.

   type Candle_Image is record
      Name       : String (1 .. 4);
      Evaluation : Boolean;
      Rims       : Rim_Set;
   end record;

   Candle_Images : constant array (1 .. 12) of Candle_Image :=
     [("0000", False,
       [(338.631, 279.243, 207.979, 1.213), (929.268, 270.551, 207.096, 1.292),
        (343.956, 823.411, 205.063, 1.273), (936.973, 827.459, 204.366, 1.366)]),
      ("0050", False,
       [(330.276, 304.219, 208.265, 1.312), (936.642, 298.403, 207.346, 1.446),
        (358.498, 865.919, 205.070, 1.300), (937.236, 859.711, 204.119, 1.162)]),
      ("0150", False,
       [(349.470, 304.530, 207.470, 1.452), (939.435, 291.964, 207.090, 1.312),
        (345.166, 868.936, 204.638, 1.737), (938.239, 867.494, 203.051, 1.381)]),
      ("0200", False,
       [(343.129, 289.032, 207.870, 1.207), (938.164, 274.950, 207.133, 0.687),
        (354.436, 865.629, 204.966, 0.929), (944.969, 872.767, 203.915, 1.576)]),
      ("0300", False,
       [(347.171, 301.436, 207.968, 0.539), (922.695, 303.290, 207.346, 1.208),
        (331.995, 880.912, 205.277, 1.287), (938.000, 888.627, 204.358, 1.948)]),
      ("0350", False,
       [(340.458, 274.820, 208.967, 1.030), (937.729, 278.072, 207.448, 1.322),
        (344.251, 848.963, 205.580, 1.645), (937.504, 845.083, 204.816, 1.776)]),
      ("0450", True,
       [(344.584, 302.791, 208.537, 0.747), (923.040, 302.388, 208.167, 1.982),
        (345.760, 859.404, 205.646, 1.439), (924.758, 858.952, 204.660, 1.195)]),
      ("0500", True,
       [(349.665, 289.483, 208.681, 1.103), (941.738, 284.505, 207.744, 1.596),
        (339.082, 847.266, 205.670, 1.841), (941.669, 844.384, 205.105, 1.687)]),
      ("0600", True,
       [(338.986, 297.390, 209.523, 1.792), (939.956, 281.648, 208.446, 1.043),
        (368.949, 859.879, 206.271, 1.212), (929.443, 854.409, 205.477, 0.904)]),
      ("0650", True,
       [(345.311, 295.296, 209.187, 1.513), (935.024, 286.644, 208.664, 1.723),
        (342.001, 883.291, 205.944, 1.332), (924.811, 890.940, 205.307, 1.914)]),
      ("0750", True,
       [(341.242, 298.300, 209.101, 1.275), (933.938, 283.172, 208.520, 1.697),
        (344.942, 873.155, 206.135, 1.601), (925.644, 864.323, 206.089, 1.824)]),
      ("0800", True,
       [(348.413, 297.562, 209.692, 1.246), (932.870, 302.859, 208.419, 1.617),
        (342.652, 861.351, 206.521, 1.203), (944.819, 857.041, 205.431, 1.445)])];

   function Candle_Set_Name (C : Candle_Image) return String is
     ((if C.Evaluation then "evaluation " else "tuning ") & C.Name);

   Taught_Rim : constant Rim := Candle_Images (1).Rims (1);
   --  The light the pattern is trained on (0000, top left).

   procedure Find_Rim
     (Image  : Ks_Image_8_Grey;
      Start  : Point;
      Radius : Real;
      Found  : out Boolean;
      Circle : out AMV.Shapes.Ks_Circle);
   --  Find Circle on the rim whose centre the fixture puts at Start, run
   --  twice, the second time from the first circle. The edge is the light
   --  rim's boundary with the dark tray, searched outwards.

   procedure Find_Rim
     (Image  : Ks_Image_8_Grey;
      Start  : Point;
      Radius : Real;
      Found  : out Boolean;
      Circle : out AMV.Shapes.Ks_Circle)
   is
      use AMV.Caliper;
      use AMV.Caliper.Find_Circle;
      Centre : Point := Start;
      R      : Real := Radius;
   begin
      Found := False;
      for Pass in 1 .. 2 loop
         declare
            Tool : Ks_Find_Circle_Tool;
         begin
            Tool.Input_Image := Image;
            Tool.Run_Params.Expected_Circular_Arc
              .Set_Center_Radius_Angle_Start_Angle_Span
                (Centre.X, Centre.Y, R, 0.0, 2.0 * Ada.Numerics.Pi);
            Tool.Run_Params.Num_Calipers := 64;
            Tool.Run_Params.Caliper_Search_Length := 16.0;
            Tool.Run_Params.Caliper_Projection_Length := 6.0;
            Tool.Run_Params.Caliper_Search_Direction := Outward;
            --  No caliper ignored: the rims are not perfectly round, and
            --  leaving out the farthest points pulls the circle towards
            --  one side (chosen on the tuning images: with 10 ignored the
            --  median centre error was 0.8 px, with none 0.04 px).
            Tool.Run_Params.Num_To_Ignore := 0;
            Tool.Run_Params.Caliper_Run_Params.Edge_0_Polarity :=
              Code (Light_To_Dark);
            Tool.Run_Params.Caliper_Run_Params.Contrast_Threshold := 20.0;
            Tool.Run_Params.Caliper_Run_Params.Filter_Half_Size_In_Pixels :=
              1;
            Tool.Run;
            Found := Tool.Run_Status.Result = Accept_Result;
            exit when not Found;
            Circle := Tool.Results.Get_Circle;
            Centre := (Circle.Center_X, Circle.Center_Y);
            R := Circle.Radius;
         end;
      end loop;
   end Find_Rim;

   Rim_Centre_Tolerance : constant := 0.45;  --  (tuning max 0.28)
   Rim_Radius_Tolerance : constant := 0.3;   --  (tuning max 0.19)
   --  1.5 times the largest tuning error, rounded up to 0.05 px, without
   --  the known failure below.

   function Known_Bad_Rim (Name : String; Light : Positive) return Boolean
   is ((Name = "0150" and then Light = 4)
       or else (Name = "0600" and then Light = 2));
   --  The known failures. Tuning set: 0150's bottom right light. Its
   --  cup is seen from the side, and its outer outline bulges up to 3 px
   --  beyond a circle on the side where the cup's wall shows. The
   --  reference's fit drops those rays as outliers (3 robust sigmas);
   --  Find Circle, which ignores no caliper here, keeps them, and its
   --  circle moves 1.4 px towards that side (radius 0.7 px larger).
   --  Ignoring calipers moves every other light instead (above).
   --  Evaluation set (the one run with the frozen settings): 0600's top
   --  right light, centre 0.46 px off (radius 0.26 px), just beyond the
   --  tolerance; its reference fit too dropped 8 of its 120 rays as
   --  outliers, the same kind of difference. Both are checked to still
   --  fail, so that a change shows up here.

   procedure Test_Candles is
      use AMV.PM_Align;
      Fixture : Ks_PM_Align_Tool;
   begin
      Section ("Gauging: VisA candle rims (PMAlign fixture, Find Circle)");
      declare
         Train  : constant Ks_Image_8_Grey :=
           Load ("visa_candle_" & Candle_Images (1).Name);
         Region : AMV.Shapes.Ks_Rectangle;
         Half   : constant Real := Taught_Rim.R + 15.0;
      begin
         Region.Set_XY_Width_Height
           (Taught_Rim.X - Half, Taught_Rim.Y - Half, 2.0 * Half, 2.0 * Half);
         Fixture.Pattern.Set_Train_Image (Train);
         Fixture.Pattern.Set_Train_Region
           (AMV.Shapes.Region_Holders.To_Holder (Region));
         Fixture.Pattern.Train;
         Fixture.Run_Params.Approximate_Number_To_Find := 4;
         Fixture.Run_Params.Zone_Angle.Configuration := Code (Low_High);
         Fixture.Run_Params.Zone_Angle.Low := -Ada.Numerics.Pi;
         Fixture.Run_Params.Zone_Angle.High := Ada.Numerics.Pi;
         Fixture.Run_Params.Zone_Scale.Configuration := Code (Low_High);
         Fixture.Run_Params.Zone_Scale.Low := 0.95;
         Fixture.Run_Params.Zone_Scale.High := 1.05;
         --  The tuning lights score 0.40 .. 0.70 (the trained one 0.99):
         --  their wicks point in other directions and their shadows fall
         --  on other parts of the tray.
         Fixture.Run_Params.Accept_Threshold := 0.3;
      end;
      for C of Candle_Images loop
         begin
            declare
               Image : constant Ks_Image_8_Grey :=
                 Load ("visa_candle_" & C.Name);
               Seen  : array (Rim_Set'Range) of Boolean := [others => False];
            begin
               Fixture.Input_Image := Image;
               Fixture.Run;
               Check (Fixture.Run_Status.Result = Accept_Result
                      and then Fixture.Results.Count = 4,
                      Candle_Set_Name (C) & ": PMAlign finds the 4 lights ("
                      & Natural'Image (Fixture.Results.Count) & ")");
               for N in 0 .. Fixture.Results.Count - 1 loop
                  declare
                     Pose  : constant AMV.Transforms.Ks_Transform_2D_Linear :=
                       Get_Pose (Fixture.Results.Item (N));
                     Start : Point;
                     K     : Positive := 1;
                     Ok    : Boolean;
                     Found : AMV.Shapes.Ks_Circle;
                  begin
                     Pose.Map_Point
                       (Taught_Rim.X, Taught_Rim.Y, Start.X, Start.Y);
                     for J in Rim_Set'Range loop
                        if Distance (Start, (C.Rims (J).X, C.Rims (J).Y))
                          < Distance (Start, (C.Rims (K).X, C.Rims (K).Y))
                        then
                           K := J;
                        end if;
                     end loop;
                     Check (not Seen (K),
                            Candle_Set_Name (C) & " light" & K'Image
                            & ": found once");
                     Seen (K) := True;
                     Find_Rim (Image, Start, Taught_Rim.R, Ok, Found);
                     Check (Ok, Candle_Set_Name (C) & " light" & K'Image
                                & ": Find Circle accepted");
                     if Ok then
                        declare
                           Ref   : Rim renames C.Rims (K);
                           D     : constant Real :=
                             Distance ((Found.Center_X, Found.Center_Y),
                                       (Ref.X, Ref.Y));
                           DR    : constant Real := Found.Radius - Ref.R;
                           Label : constant String :=
                             Candle_Set_Name (C) & " light" & K'Image;
                           Good  : constant Boolean :=
                             D <= Rim_Centre_Tolerance
                             and then abs DR <= Rim_Radius_Tolerance;
                        begin
                           Ada.Text_IO.Put_Line
                             ("  candle " & Label & ": centre"
                              & Integer (D * 1000.0)'Image & "e-3 px, radius"
                              & Integer (DR * 1000.0)'Image & "e-3 px");
                           if Known_Bad_Rim (C.Name, K) then
                              Check (not Good,
                                     Label & ": the known failure still"
                                     & " fails (centre"
                                     & Integer (D * 1000.0)'Image
                                     & "e-3 px)");
                           else
                              Check (D <= Rim_Centre_Tolerance,
                                     Label & ": centre ("
                                     & Integer (D * 1000.0)'Image
                                     & "e-3 px)");
                              Check (abs DR <= Rim_Radius_Tolerance,
                                     Label & ": radius ("
                                     & Integer (DR * 1000.0)'Image
                                     & "e-3 px)");
                           end if;
                        end;
                     end if;
                  end;
               end loop;
            end;
         end;
      end loop;
   end Test_Candles;

   procedure Run_All is
      procedure Run (Test : not null access procedure) is
      begin
         Test.all;
      exception
         when Missing =>
            null;
         when E : others =>
            Fail ("unexpected exception "
                  & Ada.Exceptions.Exception_Information (E));
      end Run;
   begin
      Run (Test_Reading'Access);
      Run (Test_Coins'Access);
      Run (Test_Smarties'Access);
      Run (Test_Gauge'Access);
      Run (Test_Box_Self'Access);
      Run (Test_Box_In_Scene'Access);
      Run (Test_Checkerboards'Access);
      Run (Test_PCB_Holes'Access);
      Run (Test_PCB_Hole_Unwrap'Access);
      Run (Test_PCB_Edges'Access);
      Run (Test_PCB_Width'Access);
      Run (Test_PCB_Caliper_Width'Access);
      Run (Test_PCB_Pose'Access);
      Run (Test_PM_Resampled'Access);
      Run (Test_PM_Defaults'Access);
      Run (Test_CNL_Shift'Access);
      Run (Test_CNL_Partial'Access);
      Run (Test_Focus_Stacks'Access);
      Run (Test_Nuclei'Access);
      Run (Test_Candles'Access);
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Real_Images;
