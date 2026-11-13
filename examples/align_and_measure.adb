--  Locate, fixture, measure: the usual chain of a gauging application.
--  PMAlign finds the part (its position and angle), the fixture tool puts
--  a coordinate space on the part at that pose, and calipers placed in
--  that space measure the part wherever it lies in the image.
--
--     align_and_measure
--
--  The images are synthetic: a model image of the part, on which the
--  pattern is trained, and two scenes with the part moved and turned. The
--  scenes are written to align_scene_1.pgm and align_scene_2.pgm in the
--  current directory. Each measure is checked against the drawn size
--  within a tolerance of 0.1 pixel; the exit status is a failure when a
--  part is not found or a measure is out of tolerance.

with Ada.Command_Line;
with Ada.Numerics;
with Ada.Text_IO;

with AMV;
with AMV.Calib_Fix;
with AMV.Caliper;
with AMV.Image_File;
with AMV.Images;
with AMV.Misc;
with AMV.PM_Align;
with AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;
with AMV.Transforms;

with Example_Support;

procedure Align_And_Measure is

   use Ada.Text_IO;
   use AMV;
   use AMV.Images;
   use AMV.Transforms;
   use type AMV.Tools.Ks_Tool_Result_Constants;

   function Image (Value : Real; Aft : Natural := 1) return String
     renames Example_Support.Image;

   ---------------------------------------------------------------------
   --  The part and the images
   ---------------------------------------------------------------------

   --  The part in its own coordinates (origin at its centre, u to the
   --  right, v down): a 120 x 64 plate with a round hole and a slot 14
   --  wide that is open at the bottom edge.

   Slot_Width   : constant := 14.0;
   Plate_Length : constant := 120.0;
   Tolerance    : constant := 0.1;

   All_Good : Boolean := True;
   --  False once a part is not found or a measure is out of tolerance.

   function Part (U, V : Real) return Boolean is
     (abs U <= Plate_Length / 2.0 and then abs V <= 32.0
      and then not (U in 20.0 .. 20.0 + Slot_Width and then V >= 4.0)
      and then (U + 30.0) ** 2 + (V + 4.0) ** 2 > 9.0 ** 2);

   function Picture
     (Width, Height : Positive;
      Pose          : Ks_Transform_2D_Linear) return Ks_Image_8_Grey;
   --  The part, placed by Pose, light on a dark background.

   function Picture
     (Width, Height : Positive;
      Pose          : Ks_Transform_2D_Linear) return Ks_Image_8_Grey
   is
      Result : Ks_Image_8_Grey := Create (Width, Height, Value => 40);
   begin
      Example_Support.Paint (Result, Part'Access, Pose, Value => 200);
      return Result;
   end Picture;

   ---------------------------------------------------------------------
   --  Training
   ---------------------------------------------------------------------

   procedure Train (Pattern : in out AMV.PM_Align.Ks_PM_Align_Pattern);
   --  Trains Pattern on a model image with the part at (100, 80), not
   --  turned.

   procedure Train (Pattern : in out AMV.PM_Align.Ks_PM_Align_Pattern) is
      Model_Pose : constant Ks_Transform_2D_Linear :=
        Create_Rigid (Rotation => 0.0, Translation_X => 100.0,
                      Translation_Y => 80.0);
      Region     : AMV.Shapes.Ks_Rectangle;
   begin
      Pattern.Set_Train_Image (Picture (200, 160, Model_Pose));
      Region.Set_Center_Width_Height (100.0, 80.0, 140.0, 84.0);
      Pattern.Set_Train_Region (AMV.Shapes.Region_Holders.To_Holder (Region));
      --  The pattern's coordinates are the part's: its origin is the
      --  part's centre in the model image. The pose of a result then maps
      --  part coordinates into the scene.
      Pattern.Set_Origin (Model_Pose);
      Pattern.Train;
   end Train;

   ---------------------------------------------------------------------
   --  Measuring
   ---------------------------------------------------------------------

   procedure Measure
     (Fixtured               : Ks_Image_8_Grey;
      Name                   : String;
      Center_U, Center_V     : Real;
      Length, Across         : Real;
      Polarity_0, Polarity_1 : AMV.Caliper.Ks_Caliper_Polarity_Constants;
      Expected               : Real);
   --  Runs a caliper for a pair of edges Expected apart along the part's
   --  u axis, in a Length x Across rectangle centred on (Center_U,
   --  Center_V) in part coordinates, prints the distance found and checks
   --  it against Expected (All_Good becomes False when it is out of
   --  tolerance or not found).

   procedure Measure
     (Fixtured               : Ks_Image_8_Grey;
      Name                   : String;
      Center_U, Center_V     : Real;
      Length, Across         : Real;
      Polarity_0, Polarity_1 : AMV.Caliper.Ks_Caliper_Polarity_Constants;
      Expected               : Real)
   is
      use AMV.Caliper;
      Tool : Ks_Caliper_Tool;
      X, Y : Real;
   begin
      Tool.Input_Image := Fixtured;
      --  The region's selected space is "." (the default): the image's
      --  selected space, which the fixture tool made the part's space.
      --  Side X, the search direction, runs along u.
      Tool.Region.Set_Center_Lengths_Rotation_Skew
        (Center_U, Center_V, Length, Across, 0.0, 0.0);
      Tool.Run_Params.Edge_Mode := Code (Pair);
      Tool.Run_Params.Edge_0_Polarity := Code (Polarity_0);
      Tool.Run_Params.Edge_1_Polarity := Code (Polarity_1);
      Tool.Run_Params.Edge_0_Position := -Expected / 2.0;
      Tool.Run_Params.Edge_1_Position := Expected / 2.0;
      Tool.Run_Params.Contrast_Threshold := 20.0;
      Tool.Run;

      if Tool.Run_Status.Result /= AMV.Tools.Accept_Result then
         Put_Line ("  " & Name & ": the caliper failed: "
                   & AMV.Tools.Message (Tool.Run_Status));
         All_Good := False;
      elsif Tool.Results.Count = 0 then
         Put_Line ("  " & Name & ": no pair of edges found");
         All_Good := False;
      else
         declare
            Found : constant Ks_Caliper_Result := Tool.Results.Item (0);
         begin
            --  Positions are in the selected space (part coordinates);
            --  map the centre of the pair back to pixels to show where it
            --  is in the scene.
            Fixtured.Get_Transform ("#", ".").Map_Point
              (Found.Position_X, Found.Position_Y, X, Y);
            Put ("  " & Name & ": " & Image (Found.Width, 2) & ", centred at ("
                 & Image (X) & ", " & Image (Y) & ") in the image: ");
            if abs (Found.Width - Expected) <= Tolerance then
               Put_Line ("OK");
            else
               Put_Line ("out of tolerance (" & Image (Expected, 2) & " +/- "
                         & Image (Tolerance, 2) & ")");
               All_Good := False;
            end if;
         end;
      end if;
   end Measure;

   ---------------------------------------------------------------------

   type Placement is record
      X, Y, Degrees : Real;
   end record;

   Scenes : constant array (1 .. 2) of Placement :=
     [(230.0, 140.0, 25.0), (150.0, 170.0, -110.0)];

   Align   : AMV.PM_Align.Ks_PM_Align_Tool;
   Fixture : AMV.Calib_Fix.Ks_Fixture_Tool;

begin
   Train (Align.Pattern);

   --  Look for the part at any angle.
   Align.Run_Params.Zone_Angle.Configuration :=
     AMV.PM_Align.Code (AMV.PM_Align.Low_High);
   Align.Run_Params.Zone_Angle.Low := -Ada.Numerics.Pi;
   Align.Run_Params.Zone_Angle.High := Ada.Numerics.Pi;

   for N in Scenes'Range loop
      declare
         P         : Placement renames Scenes (N);
         Scene     : constant Ks_Image_8_Grey :=
           Picture (400, 300,
                    Create_Rigid (AMV.Misc.Deg_To_Rad (P.Degrees), P.X, P.Y));
         File_Name : constant String :=
           "align_scene_" & Character'Val (Character'Pos ('0') + N) & ".pgm";
      begin
         AMV.Image_File.Write_Image (File_Name, Scene);
         Put_Line (File_Name & ": the part drawn at (" & Image (P.X) & ", "
                   & Image (P.Y) & "), turned by " & Image (P.Degrees)
                   & " degrees");

         --  1. Locate the part.
         Align.Input_Image := Scene;
         Align.Run;
         if Align.Run_Status.Result /= AMV.Tools.Accept_Result then
            Put_Line ("  PMAlign failed: "
                      & AMV.Tools.Message (Align.Run_Status));
            All_Good := False;
         elsif Align.Results.Count = 0 then
            Put_Line ("  PMAlign did not find the part");
            All_Good := False;
         else
            declare
               Found : constant AMV.PM_Align.Ks_PM_Align_Result :=
                 Align.Results.Item (0);
            begin
               Put_Line ("  PMAlign: found at ("
                         & Image (Found.Translation_X, 2)
                         & ", " & Image (Found.Translation_Y, 2)
                         & "), turned by "
                         & Image (AMV.Misc.Rad_To_Deg (Found.Rotation), 2)
                         & " degrees, score " & Image (Found.Score, 3));

               --  2. Put the part's coordinate space on the image: the
               --  output image has the same pixels, with "@\Fixture"
               --  added at the pose and selected.
               Fixture.Input_Image := Scene;
               Fixture.Run_Params.Unfixtured_From_Fixtured_Transform :=
                 AMV.PM_Align.Get_Pose (Found);
               Fixture.Run;
            end;

            if Fixture.Run_Status.Result /= AMV.Tools.Accept_Result then
               Put_Line ("  the fixture tool failed: "
                         & AMV.Tools.Message (Fixture.Run_Status));
               All_Good := False;
            else
               --  3. Measure in part coordinates: the same regions serve
               --  for every scene.
               Measure (Fixture.Output_Image, "slot width",
                        Center_U   => 20.0 + Slot_Width / 2.0,
                        Center_V   => 18.0,
                        Length     => 40.0,
                        Across     => 16.0,
                        Polarity_0 => AMV.Caliper.Light_To_Dark,
                        Polarity_1 => AMV.Caliper.Dark_To_Light,
                        Expected   => Slot_Width);
               Measure (Fixture.Output_Image, "plate length",
                        Center_U   => 0.0,
                        Center_V   => -24.0,
                        Length     => Plate_Length + 30.0,
                        Across     => 10.0,
                        Polarity_0 => AMV.Caliper.Dark_To_Light,
                        Polarity_1 => AMV.Caliper.Light_To_Dark,
                        Expected   => Plate_Length);
            end if;
         end if;
      end;
   end loop;

   if not All_Good then
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Align_And_Measure;
