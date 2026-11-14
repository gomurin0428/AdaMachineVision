--  Gauging a circuit board wherever it lies: PMAlign finds the board, and
--  the pose it reports places Find Circle on the four mounting holes, Find
--  Line on two outlines and a Caliper across the board's width.
--
--     pcb_gauging
--
--  It reads photographs of one kind of board (VisA, category pcb1; see
--  README.md here for where the images come from): visa_pcb1_0000.bmp, on
--  which the pattern is trained and the holes and outlines were taught,
--  and six others, in which the board is shifted and turned (in one of
--  them, 0700, upside down). It prints what it measures and writes
--  pictures into the current directory:
--
--     pcb_gauging_1_train.bmp     the taught board: the train region, the
--                                 trained features, the taught holes and
--                                 outlines
--     pcb_gauging_2_found.bmp     board 0700: where PMAlign found the
--                                 pattern
--     pcb_gauging_3_measured.bmp  the same board: the holes, the outlines
--                                 and the width
--     pcb_gauging_4_hole.bmp      one hole, enlarged: the calipers of Find
--                                 Circle, their edge points and the circle
--     pcb_gauging_5_outline.bmp   a stretch of an outline, enlarged: the
--                                 calipers of Find Line and the line
--     pcb_gauging_boards.bmp      the six boards with their results
--
--  The settings are those of the real-image tests (tests/real_images),
--  which chose them on other boards than the ones they are judged on.

with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Numerics.Generic_Elementary_Functions;
with Ada.Text_IO;

with AMV;
with AMV.Caliper;
with AMV.Caliper.Find_Circle;
with AMV.Caliper.Find_Line;
with AMV.Images;
with AMV.PM_Align;
with AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;
with AMV.Transforms;

with Example_Draw;
with Example_Support;

procedure PCB_Gauging is

   use Ada.Text_IO;
   use AMV;
   use type AMV.Tools.Ks_Tool_Result_Constants;

   package EF is new Ada.Numerics.Generic_Elementary_Functions (Real);
   package Draw renames Example_Draw;

   Pi : constant := Ada.Numerics.Pi;

   function Image (Value : Real; Aft : Natural := 1) return String
     renames Example_Support.Image;

   function Number (Value : Natural) return String is
     (Value'Image (2 .. Value'Image'Last));

   type Point is record
      X, Y : Real;
   end record;

   function Distance (A, B : Point) return Real is
     (EF.Sqrt ((A.X - B.X) ** 2 + (A.Y - B.Y) ** 2));

   ---------------------------------------------------------------------
   --  What was taught on board 0000
   ---------------------------------------------------------------------

   --  The centres of the four mounting holes (top left, top right, bottom
   --  left, bottom right) and a stretch of the left and of the right
   --  outline, in the pixels of visa_pcb1_0000.bmp. The tools below start
   --  from these, moved to where PMAlign finds the board.

   Taught_Holes : constant array (1 .. 4) of Point :=
     [(218.690, 351.971), (1112.845, 348.926),
      (223.109, 710.890), (1109.149, 707.508)];

   Hole_Radius : constant := 17.3;

   type Stretch is record
      From, To : Point;
   end record;

   Taught_Outlines : constant array (1 .. 2) of Stretch :=
     [((186.346, 391.971), (189.904, 670.890)),
      ((1143.843, 388.926), (1140.718, 667.508))];

   Nominal_Width : constant := 952.0;
   --  The board's width in pixels, roughly.

   --  The train region: the holes' bounding box and 60 pixels around it.
   Region_X0 : constant Real := Taught_Holes (1).X - 60.0;
   Region_X1 : constant Real := Taught_Holes (2).X + 60.0;
   Region_Y0 : constant Real := Taught_Holes (2).Y - 60.0;
   Region_Y1 : constant Real := Taught_Holes (3).Y + 60.0;

   ---------------------------------------------------------------------
   --  The results for one board
   ---------------------------------------------------------------------

   type Hole_Result is record
      Found  : Boolean := False;
      Circle : AMV.Shapes.Ks_Circle;
      Used   : Natural := 0;
      RMS    : Real := 0.0;
   end record;

   type Outline_Result is record
      Found   : Boolean := False;
      Line    : AMV.Shapes.Ks_Line;
      Segment : AMV.Shapes.Ks_Line_Segment;
      Used    : Natural := 0;
      RMS     : Real := 0.0;
   end record;

   type Hole_Results is array (1 .. 4) of Hole_Result;
   type Outline_Results is array (1 .. 2) of Outline_Result;

   type Board_Result is record
      Found        : Boolean := False;
      Match        : AMV.PM_Align.Ks_PM_Align_Result;
      Pose         : AMV.Transforms.Ks_Transform_2D_Linear;
      Holes        : Hole_Results;
      Outlines     : Outline_Results;
      Width_Found  : Boolean := False;
      Width        : AMV.Caliper.Ks_Caliper_Result;
      Width_Region : AMV.Shapes.Ks_Rectangle_Affine;
   end record;

   function Mapped
     (Pose : AMV.Transforms.Ks_Transform_2D_Linear; P : Point) return Point;
   --  P, a point of board 0000, where Pose puts it.

   function Mapped
     (Pose : AMV.Transforms.Ks_Transform_2D_Linear; P : Point) return Point
   is
      X, Y : Real;
   begin
      Pose.Map_Point (P.X, P.Y, X, Y);
      return (X, Y);
   end Mapped;

   ---------------------------------------------------------------------
   --  PMAlign: where is the board?
   ---------------------------------------------------------------------

   Finder : AMV.PM_Align.Ks_PM_Align_Tool;

   procedure Train (Board : AMV.Images.Ks_Image_8_Grey);

   procedure Train (Board : AMV.Images.Ks_Image_8_Grey) is
      use AMV.PM_Align;
      Region : AMV.Shapes.Ks_Rectangle;
   begin
      Region.Set_XY_Width_Height
        (Region_X0, Region_Y0, Region_X1 - Region_X0,
         Region_Y1 - Region_Y0);
      Finder.Pattern.Set_Train_Image (Board);
      Finder.Pattern.Set_Train_Region
        (AMV.Shapes.Region_Holders.To_Holder (Region));
      --  The pattern's origin stays the identity, so that a result's pose
      --  maps the pixels of board 0000 to the pixels of the image
      --  searched.
      --
      --  Features 4 to 32 pixels apart: with the automatic choice the
      --  fine texture of the board (the mesh of the transducers, the
      --  lettering) keeps PMAlign from finding most boards.
      Finder.Pattern.Set_Grain_Limit_Auto_Select (False);
      Finder.Pattern.Set_Grain_Limit_Fine (4.0);
      Finder.Pattern.Set_Grain_Limit_Coarse (32.0);
      Finder.Pattern.Train;

      --  Any angle, and 5 % of scale either way.
      Finder.Run_Params.Zone_Angle.Configuration := Code (Low_High);
      Finder.Run_Params.Zone_Angle.Low := -Pi;
      Finder.Run_Params.Zone_Angle.High := Pi;
      Finder.Run_Params.Zone_Scale.Configuration := Code (Low_High);
      Finder.Run_Params.Zone_Scale.Low := 0.95;
      Finder.Run_Params.Zone_Scale.High := 1.05;
      Finder.Run_Params.Accept_Threshold := 0.3;
   end Train;

   ---------------------------------------------------------------------
   --  Find Circle: a mounting hole
   ---------------------------------------------------------------------

   procedure Find_Hole
     (Board        : AMV.Images.Ks_Image_8_Grey;
      Start        : Point;
      Result       : out Hole_Result;
      Picture_Name : String := "");
   --  The hole whose centre the pose puts at Start. Two runs, the second
   --  from the first circle's centre: the pose is off by a few pixels at
   --  the holes, and the calipers are short. With a Picture_Name, writes
   --  the enlarged picture of the second run.

   procedure Find_Hole
     (Board        : AMV.Images.Ks_Image_8_Grey;
      Start        : Point;
      Result       : out Hole_Result;
      Picture_Name : String := "")
   is
      use AMV.Caliper;
      use AMV.Caliper.Find_Circle;
      Centre : Point := Start;
   begin
      Result := (others => <>);
      for Pass in 1 .. 2 loop
         declare
            Tool : Ks_Find_Circle_Tool;
         begin
            Tool.Input_Image := Board;
            --  48 calipers around the expected circle, each 10 pixels
            --  long across it and 3 wide, looking outwards for the step
            --  from the dark hole to the light pad around it. The 7
            --  points farthest from the circle are left out of the fit.
            Tool.Run_Params.Expected_Circular_Arc
              .Set_Center_Radius_Angle_Start_Angle_Span
                (Centre.X, Centre.Y, Hole_Radius, 0.0, 2.0 * Pi);
            Tool.Run_Params.Num_Calipers := 48;
            Tool.Run_Params.Caliper_Search_Length := 10.0;
            Tool.Run_Params.Caliper_Projection_Length := 3.0;
            Tool.Run_Params.Caliper_Search_Direction := Outward;
            Tool.Run_Params.Num_To_Ignore := 7;
            Tool.Run_Params.Caliper_Run_Params.Edge_0_Polarity :=
              Code (Dark_To_Light);
            Tool.Run_Params.Caliper_Run_Params.Contrast_Threshold := 20.0;
            Tool.Run_Params.Caliper_Run_Params.Filter_Half_Size_In_Pixels :=
              1;
            Tool.Run;
            Result.Found := Tool.Run_Status.Result = AMV.Tools.Accept_Result;
            exit when not Result.Found;
            Result.Circle := Tool.Results.Get_Circle;
            Result.Used := Tool.Results.Num_Points_Used;
            Result.RMS := Tool.Results.RMS_Error;

            if Pass = 2 and then Picture_Name /= "" then
               declare
                  Zoom : Draw.Picture :=
                    Draw.Create
                      (Board,
                       Integer (Result.Circle.Center_X) - 30,
                       Integer (Result.Circle.Center_Y) - 30,
                       60, 60, Scale => 9.0);
               begin
                  for K in 0 .. Tool.Results.Count - 1 loop
                     Draw.Outline
                       (Zoom, Get_Caliper_Region (Tool.Run_Params, K),
                        Draw.Cyan, Width => 1.0);
                  end loop;
                  Draw.Circle
                    (Zoom, Start.X, Start.Y, Hole_Radius, Draw.Yellow);
                  Draw.Cross (Zoom, Start.X, Start.Y, Draw.Yellow);
                  Draw.Outline
                    (Zoom, Result.Circle, Draw.Green, Width => 2.5);
                  Draw.Cross
                    (Zoom, Result.Circle.Center_X, Result.Circle.Center_Y,
                     Draw.Green, Size => 9.0, Width => 2.5);
                  for K in 0 .. Tool.Results.Count - 1 loop
                     if Tool.Results.Item (K).Found then
                        Draw.Dot
                          (Zoom, Tool.Results.Item (K).X,
                           Tool.Results.Item (K).Y,
                           (if Tool.Results.Item (K).Used then Draw.Green
                            else Draw.Red),
                           Size => 3.5);
                     end if;
                  end loop;
                  Draw.Caption (Zoom, 0, "FIND CIRCLE ON A HOLE");
                  Draw.Caption
                    (Zoom, 1, "START, FROM THE POSE", Draw.Yellow);
                  Draw.Caption
                    (Zoom, 2, "CALIPERS (" & Number (Tool.Results.Count)
                     & ")", Draw.Cyan);
                  Draw.Caption
                    (Zoom, 3, "POINTS USED (" & Number (Result.Used)
                     & "), CIRCLE", Draw.Green);
                  Draw.Caption (Zoom, 4, "POINTS LEFT OUT", Draw.Red);
                  Draw.Write (Zoom, Picture_Name);
               end;
            end if;

            Centre := (Result.Circle.Center_X, Result.Circle.Center_Y);
         end;
      end loop;
   end Find_Hole;

   ---------------------------------------------------------------------
   --  Find Line: an outline
   ---------------------------------------------------------------------

   procedure Find_Outline
     (Board        : AMV.Images.Ks_Image_8_Grey;
      Pose         : AMV.Transforms.Ks_Transform_2D_Linear;
      Side         : Positive;
      Result       : out Outline_Result;
      Picture_Name : String := "");
   --  The outline taught as Taught_Outlines (Side). Two runs: the first
   --  with calipers 20 pixels long, enough for the pose's error, the
   --  second along the line found, with calipers of 12 pixels that stay
   --  clear of the white rings just inside the outline.

   procedure Find_Outline
     (Board        : AMV.Images.Ks_Image_8_Grey;
      Pose         : AMV.Transforms.Ks_Transform_2D_Linear;
      Side         : Positive;
      Result       : out Outline_Result;
      Picture_Name : String := "")
   is
      use AMV.Caliper;
      use AMV.Caliper.Find_Line;
      Start : constant Stretch :=
        (Mapped (Pose, Taught_Outlines (Side).From),
         Mapped (Pose, Taught_Outlines (Side).To));
      P0    : Point := Start.From;
      P1    : Point := Start.To;

      function Onto (P : Point; L : AMV.Shapes.Ks_Line) return Point is
        (declare
           DX : constant Real := EF.Cos (L.Rotation);
           DY : constant Real := EF.Sin (L.Rotation);
           T  : constant Real := (P.X - L.X) * DX + (P.Y - L.Y) * DY;
         begin (L.X + T * DX, L.Y + T * DY));
      --  P projected onto L.
   begin
      Result := (others => <>);
      for Pass in 1 .. 2 loop
         declare
            Tool : Ks_Find_Line_Tool;
         begin
            Tool.Input_Image := Board;
            --  40 calipers along the expected stretch. On board 0000 both
            --  stretches run downwards, and a caliper searches to the
            --  left of its stretch's direction: outwards on the left
            --  outline (from the light board to the dark background),
            --  inwards on the right one. The pose keeps this for a board
            --  that is turned. The 6 points farthest from the line are
            --  left out of the fit.
            Tool.Run_Params.Expected_Line_Segment.Set_Start_End
              (P0.X, P0.Y, P1.X, P1.Y);
            Tool.Run_Params.Num_Calipers := 40;
            Tool.Run_Params.Caliper_Search_Length :=
              (if Pass = 1 then 20.0 else 12.0);
            Tool.Run_Params.Num_To_Ignore := 6;
            Tool.Run_Params.Caliper_Run_Params.Contrast_Threshold := 20.0;
            Tool.Run_Params.Caliper_Run_Params.Filter_Half_Size_In_Pixels :=
              1;
            Tool.Run_Params.Caliper_Run_Params.Edge_0_Polarity :=
              (if Side = 1 then Code (Light_To_Dark)
               else Code (Dark_To_Light));
            Tool.Run;
            Result.Found := Tool.Run_Status.Result = AMV.Tools.Accept_Result;
            exit when not Result.Found;
            Result.Line := Tool.Results.Get_Line;
            Result.Segment := Tool.Results.Get_Line_Segment;
            Result.Used := Tool.Results.Num_Points_Used;
            Result.RMS := Tool.Results.RMS_Error;

            if Pass = 2 and then Picture_Name /= "" then
               declare
                  Middle : constant Point :=
                    ((P0.X + P1.X) / 2.0, (P0.Y + P1.Y) / 2.0);
                  Zoom   : Draw.Picture :=
                    Draw.Create
                      (Board, Integer (Middle.X) - 36,
                       Integer (Middle.Y) - 45, 72, 90, Scale => 7.0);
               begin
                  for K in 0 .. Tool.Results.Count - 1 loop
                     Draw.Outline
                       (Zoom, Get_Caliper_Region (Tool.Run_Params, K),
                        Draw.Cyan, Width => 1.0);
                  end loop;
                  Draw.Line
                    (Zoom, Start.From.X, Start.From.Y, Start.To.X,
                     Start.To.Y, Draw.Yellow);
                  Draw.Line
                    (Zoom, Result.Segment.Start_X, Result.Segment.Start_Y,
                     Result.Segment.End_X, Result.Segment.End_Y,
                     Draw.Green, Width => 2.5);
                  for K in 0 .. Tool.Results.Count - 1 loop
                     if Tool.Results.Item (K).Found then
                        Draw.Dot
                          (Zoom, Tool.Results.Item (K).X,
                           Tool.Results.Item (K).Y,
                           (if Tool.Results.Item (K).Used then Draw.Green
                            else Draw.Red),
                           Size => 3.5);
                     end if;
                  end loop;
                  Draw.Caption (Zoom, 0, "FIND LINE ON AN OUTLINE");
                  Draw.Caption
                    (Zoom, 1, "START, FROM THE POSE", Draw.Yellow);
                  Draw.Caption (Zoom, 2, "CALIPERS", Draw.Cyan);
                  Draw.Caption (Zoom, 3, "POINTS USED, LINE", Draw.Green);
                  Draw.Caption (Zoom, 4, "POINTS LEFT OUT", Draw.Red);
                  Draw.Write (Zoom, Picture_Name);
               end;
            end if;

            --  The next run along this line, over the same stretch.
            P0 := Onto (P0, Result.Line);
            P1 := Onto (P1, Result.Line);
         end;
      end loop;
   end Find_Outline;

   ---------------------------------------------------------------------
   --  Caliper: the width
   ---------------------------------------------------------------------

   procedure Measure_Width
     (Board  : AMV.Images.Ks_Image_8_Grey;
      Result : in out Board_Result);
   --  One caliper across the board, through the middle of the four holes
   --  as the pose places them and along the rows of holes: the pair of
   --  edges, dark to light and then light to dark, whose distance is
   --  nearest the nominal width.

   procedure Measure_Width
     (Board  : AMV.Images.Ks_Image_8_Grey;
      Result : in out Board_Result)
   is
      use AMV.Caliper;
      H      : constant array (1 .. 4) of Point :=
        [for J in 1 .. 4 => Mapped (Result.Pose, Taught_Holes (J))];
      Centre : constant Point :=
        ((H (1).X + H (2).X + H (3).X + H (4).X) / 4.0,
         (H (1).Y + H (2).Y + H (3).Y + H (4).Y) / 4.0);
      Tool   : Ks_Caliper_Tool;
   begin
      Tool.Input_Image := Board;
      Tool.Region.Set_Center_Lengths_Rotation_Skew
        (Centre.X, Centre.Y, Nominal_Width + 48.0, 20.0,
         EF.Arctan ((H (2).Y - H (1).Y) + (H (4).Y - H (3).Y),
                    (H (2).X - H (1).X) + (H (4).X - H (3).X)),
         0.0);
      Tool.Run_Params.Edge_Mode := Code (Pair);
      Tool.Run_Params.Edge_0_Polarity := Code (Dark_To_Light);
      Tool.Run_Params.Edge_1_Polarity := Code (Light_To_Dark);
      Tool.Run_Params.Edge_0_Position := -Nominal_Width / 2.0;
      Tool.Run_Params.Edge_1_Position := Nominal_Width / 2.0;
      Tool.Run_Params.Contrast_Threshold := 20.0;
      Tool.Run_Params.Filter_Half_Size_In_Pixels := 1;
      Tool.Run;
      Result.Width_Region := Tool.Region;
      Result.Width_Found :=
        Tool.Run_Status.Result = AMV.Tools.Accept_Result
        and then Tool.Results.Count = 1;
      if Result.Width_Found then
         Result.Width := Tool.Results.Item (0);
      end if;
   end Measure_Width;

   ---------------------------------------------------------------------
   --  Drawing
   ---------------------------------------------------------------------

   procedure Draw_Pattern
     (Onto     : in out Draw.Picture;
      Pose     : AMV.Transforms.Ks_Transform_2D_Linear;
      Features : Boolean);
   --  The train region and, with Features, the trained features, where
   --  Pose puts them.

   procedure Draw_Pattern
     (Onto     : in out Draw.Picture;
      Pose     : AMV.Transforms.Ks_Transform_2D_Linear;
      Features : Boolean)
   is
      Corners : constant array (0 .. 3) of Point :=
        [Mapped (Pose, (Region_X0, Region_Y0)),
         Mapped (Pose, (Region_X1, Region_Y0)),
         Mapped (Pose, (Region_X1, Region_Y1)),
         Mapped (Pose, (Region_X0, Region_Y1))];
   begin
      if Features then
         for F of Finder.Pattern.Get_Trained_Features loop
            declare
               P : constant Point := Mapped (Pose, (F.X, F.Y));
            begin
               Draw.Dot (Onto, P.X, P.Y, Draw.Yellow, Size => 1.0);
            end;
         end loop;
      end if;
      for K in Corners'Range loop
         Draw.Line
           (Onto, Corners (K).X, Corners (K).Y,
            Corners ((K + 1) mod 4).X, Corners ((K + 1) mod 4).Y,
            Draw.Cyan, Width => (if Features then 2.0 else 1.5));
      end loop;
   end Draw_Pattern;

   procedure Draw_Measures
     (Onto   : in out Draw.Picture;
      Result : Board_Result;
      Labels : Boolean);
   --  The holes, the outlines and the width; with Labels, their numbers
   --  and values too.

   procedure Draw_Measures
     (Onto   : in out Draw.Picture;
      Result : Board_Result;
      Labels : Boolean)
   is
      Thick : constant Real := (if Labels then 2.5 else 2.0);
   begin
      for Side in Result.Outlines'Range loop
         if Result.Outlines (Side).Found then
            declare
               S : AMV.Shapes.Ks_Line_Segment renames
                 Result.Outlines (Side).Segment;
            begin
               Draw.Line
                 (Onto, S.Start_X, S.Start_Y, S.End_X, S.End_Y,
                  Draw.Orange, Width => Thick);
               if Labels then
                  Draw.Text
                    (Onto, (S.Start_X + S.End_X) / 2.0,
                     (S.Start_Y + S.End_Y) / 2.0 - 60.0,
                     "OUTLINE " & Number (Side), Draw.Orange,
                     DX => -54, DY => -9);
               end if;
            end;
         end if;
      end loop;

      if Result.Width_Found then
         declare
            E0 : constant Point :=
              (Result.Width.Edge_0.Position_X,
               Result.Width.Edge_0.Position_Y);
            E1 : constant Point :=
              (Result.Width.Edge_1.Position_X,
               Result.Width.Edge_1.Position_Y);
            --  Across the caliper: along its side Y.
            R  : AMV.Shapes.Ks_Rectangle_Affine renames Result.Width_Region;
            VX : constant Real :=
              (R.Corner_Y_X - R.Corner_Origin_X) / R.Side_Y_Length;
            VY : constant Real :=
              (R.Corner_Y_Y - R.Corner_Origin_Y) / R.Side_Y_Length;
         begin
            Draw.Outline (Onto, R, Draw.Magenta, Width => 1.0);
            Draw.Line
              (Onto, E0.X - 30.0 * VX, E0.Y - 30.0 * VY, E0.X + 30.0 * VX,
               E0.Y + 30.0 * VY, Draw.Magenta, Width => Thick);
            Draw.Line
              (Onto, E1.X - 30.0 * VX, E1.Y - 30.0 * VY, E1.X + 30.0 * VX,
               E1.Y + 30.0 * VY, Draw.Magenta, Width => Thick);
            if Labels then
               Draw.Text
                 (Onto, (E0.X + E1.X) / 2.0, (E0.Y + E1.Y) / 2.0,
                  "WIDTH " & Image (Result.Width.Width), Draw.Magenta,
                  DX => -66, DY => 12);
            end if;
         end;
      end if;

      for J in Result.Holes'Range loop
         if Result.Holes (J).Found then
            declare
               C : AMV.Shapes.Ks_Circle renames Result.Holes (J).Circle;
            begin
               Draw.Outline (Onto, C, Draw.Green, Width => Thick);
               Draw.Cross
                 (Onto, C.Center_X, C.Center_Y, Draw.Green,
                  Size => (if Labels then 14.0 else 7.0), Width => 1.5);
               if Labels then
                  Draw.Text
                    (Onto, C.Center_X, C.Center_Y,
                     "HOLE " & Number (J), Draw.Green, DX => -36,
                     DY => -40);
               end if;
            end;
         end if;
      end loop;
   end Draw_Measures;

   ---------------------------------------------------------------------
   --  One board
   ---------------------------------------------------------------------

   function Gauge (Name : String; Detail : Boolean) return Draw.Picture;
   --  Finds and measures the board of visa_pcb1_<Name>.bmp, prints the
   --  results and returns a small picture of them; with Detail, writes
   --  the pictures 2 to 5 as well.

   function Gauge (Name : String; Detail : Boolean) return Draw.Picture is
      use AMV.PM_Align;
      Board  : constant AMV.Images.Ks_Image_8_Grey :=
        Example_Support.Real_Image ("visa_pcb1_" & Name & ".bmp");
      Result : Board_Result;
      Small  : Draw.Picture := Draw.Create (Board, Scale => 0.25);
   begin
      Finder.Input_Image := Board;
      Finder.Run;
      Result.Found :=
        Finder.Run_Status.Result = AMV.Tools.Accept_Result
        and then Finder.Results.Count = 1;
      if not Result.Found then
         Put_Line ("board " & Name & ": not found");
         Draw.Caption (Small, 0, Name & ": NOT FOUND", Draw.Red);
         return Small;
      end if;
      Result.Match := Finder.Results.Item (0);
      Result.Pose := Get_Pose (Result.Match);
      Put_Line
        ("board " & Name & ": found with score "
         & Image (Result.Match.Score, 2) & ", turned by "
         & Image (Result.Match.Rotation * 180.0 / Pi) & " degrees, scale "
         & Image (Result.Match.Scaling, 3));

      for J in Result.Holes'Range loop
         Find_Hole
           (Board, Mapped (Result.Pose, Taught_Holes (J)), Result.Holes (J),
            (if Detail and then J = 1 then "pcb_gauging_4_hole.bmp"
             else ""));
         if Result.Holes (J).Found then
            Put_Line
              ("  hole " & Number (J) & ": centre ("
               & Image (Result.Holes (J).Circle.Center_X, 2) & ", "
               & Image (Result.Holes (J).Circle.Center_Y, 2) & "), radius "
               & Image (Result.Holes (J).Circle.Radius, 2) & " ("
               & Number (Result.Holes (J).Used) & " points, rms "
               & Image (Result.Holes (J).RMS, 2) & ")");
         else
            Put_Line ("  hole " & Number (J) & ": not found");
         end if;
      end loop;
      if (for all H of Result.Holes => H.Found) then
         declare
            function Centre (J : Positive) return Point is
              ((Result.Holes (J).Circle.Center_X,
                Result.Holes (J).Circle.Center_Y));
         begin
            Put_Line
              ("  hole spacing: " & Image (Distance (Centre (1), Centre (2)))
               & " and " & Image (Distance (Centre (3), Centre (4)))
               & " along the board, "
               & Image (Distance (Centre (1), Centre (3))) & " and "
               & Image (Distance (Centre (2), Centre (4))) & " across");
         end;
      end if;

      for Side in Result.Outlines'Range loop
         Find_Outline
           (Board, Result.Pose, Side, Result.Outlines (Side),
            (if Detail and then Side = 1 then "pcb_gauging_5_outline.bmp"
             else ""));
         if Result.Outlines (Side).Found then
            Put_Line
              ("  outline " & Number (Side) & ": at "
               & Image (Result.Outlines (Side).Line.Rotation * 180.0 / Pi, 2)
               & " degrees (" & Number (Result.Outlines (Side).Used)
               & " points, rms " & Image (Result.Outlines (Side).RMS, 2)
               & ")");
         else
            Put_Line ("  outline " & Number (Side) & ": not found");
         end if;
      end loop;

      Measure_Width (Board, Result);
      if Result.Width_Found then
         Put_Line ("  width: " & Image (Result.Width.Width, 2));
      else
         Put_Line ("  width: not found");
      end if;

      if Detail then
         declare
            Found    : Draw.Picture := Draw.Create (Board, Scale => 0.5);
            Measured : Draw.Picture := Draw.Create (Board, Scale => 0.5);
         begin
            Draw_Pattern (Found, Result.Pose, Features => True);
            Draw.Caption (Found, 0, "PMALIGN: THE BOARD OF " & Name);
            Draw.Caption
              (Found, 1, "SCORE " & Image (Result.Match.Score, 2)
               & ", TURNED BY "
               & Image (Result.Match.Rotation * 180.0 / Pi) & " DEG",
               Draw.Yellow);
            Draw.Write (Found, "pcb_gauging_2_found.bmp");

            Draw_Pattern (Measured, Result.Pose, Features => False);
            Draw_Measures (Measured, Result, Labels => True);
            Draw.Caption
              (Measured, 0, "FIND CIRCLE, FIND LINE AND CALIPER");
            Draw.Write (Measured, "pcb_gauging_3_measured.bmp");
         end;
      end if;

      Draw_Pattern (Small, Result.Pose, Features => False);
      Draw_Measures (Small, Result, Labels => False);
      Draw.Caption
        (Small, 0, Name & ": WIDTH "
         & (if Result.Width_Found then Image (Result.Width.Width)
            else "-"));
      return Small;
   end Gauge;

   Identity : AMV.Transforms.Ks_Transform_2D_Linear;

begin
   declare
      Taught : constant AMV.Images.Ks_Image_8_Grey :=
        Example_Support.Real_Image ("visa_pcb1_0000.bmp");
      Shown  : Draw.Picture := Draw.Create (Taught, Scale => 0.5);
   begin
      Train (Taught);
      Put_Line
        ("trained on board 0000:"
         & Natural'Image (Finder.Pattern.Get_Trained_Features'Length)
         & " fine features");
      Draw_Pattern (Shown, Identity, Features => True);
      for H of Taught_Holes loop
         Draw.Circle (Shown, H.X, H.Y, Hole_Radius, Draw.Green, 2.0);
      end loop;
      for S of Taught_Outlines loop
         Draw.Line
           (Shown, S.From.X, S.From.Y, S.To.X, S.To.Y, Draw.Orange, 2.5);
      end loop;
      Draw.Caption (Shown, 0, "TAUGHT ON BOARD 0000");
      Draw.Caption (Shown, 1, "TRAIN REGION", Draw.Cyan);
      Draw.Caption (Shown, 2, "TRAINED FEATURES", Draw.Yellow);
      Draw.Caption (Shown, 3, "HOLES", Draw.Green);
      Draw.Caption (Shown, 4, "OUTLINES", Draw.Orange);
      Draw.Write (Shown, "pcb_gauging_1_train.bmp");
   end;

   declare
      Row_1 : constant Draw.Picture :=
        Draw.Beside
          (Draw.Beside (Gauge ("0100", Detail => False),
                        Gauge ("0250", Detail => False)),
           Gauge ("0400", Detail => False));
      Row_2 : constant Draw.Picture :=
        Draw.Beside
          (Draw.Beside (Gauge ("0550", Detail => False),
                        Gauge ("0700", Detail => True)),
           Gauge ("0900", Detail => False));
   begin
      Draw.Write (Draw.Above (Row_1, Row_2), "pcb_gauging_boards.bmp");
   end;
   Put_Line ("wrote pcb_gauging_1_train.bmp to pcb_gauging_5_outline.bmp"
             & " and pcb_gauging_boards.bmp");
exception
   when E : Example_Support.Missing_Image =>
      Put_Line (Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end PCB_Gauging;
