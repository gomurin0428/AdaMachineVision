--  Tests of AMV Flow: the JSON reader and writer, shapes in flow files,
--  building and checking flows, running them (the align-and-measure chain
--  of examples/align_and_measure.adb as a flow file, blobs), the failure
--  propagation, saving and loading, and malformed flow files. Run from the
--  repository's root (it writes into build/flow-test); exit status 1 on
--  any failure.

with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Numerics;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AMV;
with AMV.Flow;
with AMV.Flow.Graphs;
with AMV.Flow.JSON;
with AMV.Flow.Nodes;
with AMV.Flow.Reports;
with AMV.Flow.Values;
with AMV.Image_File;
with AMV.Images;
with AMV.Misc;
with AMV.Shapes;
with AMV.Tools;
with AMV.Transforms;

procedure Test_Flow is

   use Ada.Text_IO;
   use AMV;
   use AMV.Flow;
   use AMV.Flow.Values;
   use type AMV.Tools.Ks_Tool_Result_Constants;
   use type AMV.Flow.Nodes.Node_State;
   use type AMV.Flow.JSON.Kind_Type;
   use type AMV.Flow.JSON.Node;

   LF : constant Character := ASCII.LF;
   BS : constant Character := Character'Val (92);  --  a backslash
   Pi : constant := Ada.Numerics.Pi;

   Test_Dir : constant String := "build/flow-test";

   type Real_Array is array (Positive range <>) of Real;

   Checks   : Natural := 0;
   Failures : Natural := 0;

   procedure Check (Condition : Boolean; What : String) is
   begin
      Checks := Checks + 1;
      if not Condition then
         Failures := Failures + 1;
         Put_Line ("FAIL: " & What);
      end if;
   end Check;

   procedure Check_Near (Actual, Expected, Tolerance : Real; What : String)
   is
   begin
      Check (abs (Actual - Expected) <= Tolerance,
             What & ": " & AMV.Flow.JSON.Number_Image (Actual)
             & ", expected " & AMV.Flow.JSON.Number_Image (Expected));
   end Check_Near;

   function Contains (Text, Part : String) return Boolean is
     (Ada.Strings.Fixed.Index (Text, Part) > 0);

   procedure Expect_Flow_Error (What          : String;
                                Action        : not null access procedure;
                                Contains_Text : String := "") is
   begin
      Action.all;
      Check (False, What & ": no Ks_Flow_Exception");
   exception
      when E : Ks_Flow_Exception =>
         Check (Contains_Text = ""
                or else Contains (Ada.Exceptions.Exception_Message (E),
                                  Contains_Text),
                What & ": message """ & Ada.Exceptions.Exception_Message (E)
                & """ lacks """ & Contains_Text & """");
      when E : others =>
         Check (False, What & ": raised "
                & Ada.Exceptions.Exception_Name (E) & ": "
                & Ada.Exceptions.Exception_Message (E));
   end Expect_Flow_Error;

   ---------------------------------------------------------------------
   --  JSON
   ---------------------------------------------------------------------

   procedure Test_JSON is
      use AMV.Flow.JSON;
      Doc : Document;

      procedure Rejects (Text : String) is
         procedure Try is
         begin
            Parse (Doc, Text);
         end Try;
      begin
         Expect_Flow_Error ("JSON rejects " & Text, Try'Access, "JSON line");
      end Rejects;
   begin
      Parse (Doc, "{""a"": [1, -1.5e3, 0, 1E2, true, false, null],"
                  & " ""s"": ""x\n" & BS & "u00e9" & BS & "ud83d" & BS & "ude00\""y"", ""o"": {}}");
      declare
         R : constant Node := Root (Doc);
         A : constant Node := Member (Doc, R, "a");
         S : constant String := String_Value (Doc, Member (Doc, R, "s"));
      begin
         Check (Kind (Doc, R) = Object_Kind, "JSON: root is an object");
         Check (Length (Doc, R) = 3 and then Key (Doc, R, 2) = "s",
                "JSON: members in order");
         Check (Length (Doc, A) = 7, "JSON: array length");
         Check (Number_Value (Doc, Element (Doc, A, 2)) = -1500.0,
                "JSON: exponent");
         Check (Number_Value (Doc, Element (Doc, A, 4)) = 100.0,
                "JSON: exponent without a point");
         Check (Boolean_Value (Doc, Element (Doc, A, 5)), "JSON: true");
         Check (Kind (Doc, Element (Doc, A, 7)) = Null_Kind, "JSON: null");
         Check (S = "x" & LF & Character'Val (16#C3#) & Character'Val (16#A9#)
                & Character'Val (16#F0#) & Character'Val (16#9F#)
                & Character'Val (16#98#) & Character'Val (16#80#) & """y",
                "JSON: escapes and surrogate pairs to UTF-8");
         Check (Member (Doc, R, "missing") = No_Node, "JSON: missing member");
         Check (Length (Doc, Member (Doc, R, "o")) = 0, "JSON: empty object");
      end;

      Rejects ("");
      Rejects ("{");
      Rejects ("[1,]");
      Rejects ("{""a"":1,}");
      Rejects ("01");
      Rejects ("1.");
      Rejects (".5");
      Rejects ("""abc");
      Rejects ("""a" & Character'Val (1) & """");
      Rejects ("{""a"":1,""a"":2}");
      Rejects ("[1] x");
      Rejects ("nul");
      Rejects ("""\u0000""");
      Rejects ("""\ud800""");
      Rejects ("1e999");
      Rejects ("NaN");
      Rejects ([1 .. 70 => '[']);

      Check (Number_Image (0.6) = "0.6", "JSON: 0.6 written as 0.6");
      Check (Number_Image (120.0) = "120.0", "JSON: 120.0");
      Check (Number_Image (-7.0) = "-7.0", "JSON: -7.0");
      for X of Real_Array'(Pi, 1.0E-7, 1.5E20, -3.25E-300, 0.1 + 0.2) loop
         Check (Long_Float'Value (Number_Image (X)) = X,
                "JSON: " & Number_Image (X) & " reads back");
      end loop;

      declare
         W : Writer;
      begin
         W.Begin_Object;
         W.Key ("n");
         W.Value (Long_Long_Integer (3));
         W.Key ("list");
         W.Begin_Array (Inline => True);
         W.Value (1.5);
         W.Value ("q""uote");
         W.Value (True);
         W.Null_Value;
         W.End_Array;
         W.End_Object;
         Parse (Doc, W.Text);
         Check (String_Value
                  (Doc, Element (Doc, Member (Doc, Root (Doc), "list"), 2))
                = "q""uote", "JSON: the writer's text reads back");
      end;
   end Test_JSON;

   ---------------------------------------------------------------------
   --  Shapes in flow files
   ---------------------------------------------------------------------

   procedure Test_Shapes is
      use AMV.Flow.JSON;
      Doc : Document;

      function Round_Trip (Shape : AMV.Shapes.Ks_Shape'Class)
                           return AMV.Shapes.Ks_Shape'Class is
         W : Writer;
      begin
         Write_Shape (W, Shape);
         Parse (Doc, W.Text);
         return Read_Shape (Doc, Root (Doc));
      end Round_Trip;

      procedure Rejects (Text, Why : String) is
         procedure Try is
         begin
            Parse (Doc, Text);
            declare
               Ignore : constant AMV.Shapes.Ks_Shape'Class :=
                 Read_Shape (Doc, Root (Doc));
            begin
               null;
            end;
         end Try;
      begin
         Expect_Flow_Error ("shapes reject " & Text, Try'Access, Why);
      end Rejects;

      R  : AMV.Shapes.Ks_Rectangle;
      RA : AMV.Shapes.Ks_Rectangle_Affine;
      C  : AMV.Shapes.Ks_Circle;
      A  : AMV.Shapes.Ks_Circular_Annulus_Section;
   begin
      A.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (3.0, -4.0, 120.0, 2.5, 4.25, 1.25);
      A.Set_Selected_Space_Name ("Cup");
      declare
         A2 : constant AMV.Shapes.Ks_Shape'Class := Round_Trip (A);
         use AMV.Shapes;
      begin
         Check (A2 in Ks_Circular_Annulus_Section'Class
                and then Ks_Circular_Annulus_Section (A2).Center_Y = -4.0
                and then Ks_Circular_Annulus_Section (A2).Radius = 120.0
                and then Ks_Circular_Annulus_Section (A2).Radial_Scale = 1.25
                and then Ks_Circular_Annulus_Section (A2).Angle_Start = 2.5
                and then Ks_Circular_Annulus_Section (A2).Angle_Span = 4.25
                and then A2.Selected_Space_Name = "Cup",
                "shapes: a CircularAnnulusSection reads back");
      end;
      R.Set_Center_Width_Height (10.0, 20.0, 30.0, 40.5);
      R.Set_Selected_Space_Name ("@\Part");
      RA.Set_Center_Lengths_Rotation_Skew (1.0, 2.0, 30.0, 4.0, 0.3, -0.1);
      C.Set_Center_Radius (5.0, 6.0, 7.25);
      declare
         R2 : constant AMV.Shapes.Ks_Shape'Class := Round_Trip (R);
      begin
         Check (R2 in AMV.Shapes.Ks_Rectangle'Class
                and then AMV.Shapes.Ks_Rectangle (R2).Width = 30.0
                and then AMV.Shapes.Ks_Rectangle (R2).Height = 40.5
                and then AMV.Shapes.Ks_Rectangle (R2).Center_X = 10.0
                and then R2.Selected_Space_Name = "@\Part",
                "shapes: a Rectangle reads back");
      end;
      declare
         RA2 : constant AMV.Shapes.Ks_Shape'Class := Round_Trip (RA);
      begin
         Check (RA2 in AMV.Shapes.Ks_Rectangle_Affine'Class
                and then AMV.Shapes.Ks_Rectangle_Affine (RA2).Rotation = 0.3
                and then AMV.Shapes.Ks_Rectangle_Affine (RA2).Skew = -0.1
                and then AMV.Shapes.Ks_Rectangle_Affine (RA2).Side_X_Length
                         = 30.0,
                "shapes: a RectangleAffine reads back");
      end;
      declare
         C2 : constant AMV.Shapes.Ks_Shape'Class := Round_Trip (C);
      begin
         Check (C2 in AMV.Shapes.Ks_Circle'Class
                and then AMV.Shapes.Ks_Circle (C2).Radius = 7.25,
                "shapes: a Circle reads back");
      end;

      Rejects ("{""shape"": ""Star"", ""centerX"": 1}", "unknown shape");
      Rejects ("{""shape"": ""Circle"", ""centerX"": 1, ""centerY"": 2}",
               "radius");
      Rejects ("{""shape"": ""Circle"", ""centerX"": 1, ""centerY"": 2, "
               & """radius"": 3, ""w"": 1}", "members");
      Rejects ("{""shape"": ""Circle"", ""centerX"": ""1"", ""centerY"": 2, "
               & """radius"": 3}", "number");
      Rejects ("[1]", "object");
   end Test_Shapes;

   ---------------------------------------------------------------------
   --  Test images
   ---------------------------------------------------------------------

   --  The part of examples/align_and_measure.adb: a 120 x 64 plate with a
   --  round hole and a slot 14 wide open at the bottom edge, in its own
   --  coordinates (origin at its centre, v down).

   function Part (U, V : Real) return Boolean is
     (abs U <= 60.0 and then abs V <= 32.0
      and then not (U in 20.0 .. 34.0 and then V >= 4.0)
      and then (U + 30.0) ** 2 + (V + 4.0) ** 2 > 9.0 ** 2);

   function Picture (Width, Height : Positive;
                     Pose          : AMV.Transforms.Ks_Transform_2D_Linear;
                     With_Part     : Boolean := True)
                     return AMV.Images.Ks_Image_8_Grey
   is
      Samples : constant := 4;
      Image   : AMV.Images.Ks_Image_8_Grey :=
        AMV.Images.Create (Width, Height, Value => 40);
      Inverse : constant AMV.Transforms.Ks_Transform_2D_Linear := Pose.Invert;
      U, V    : Real;
      Hits    : Natural;
   begin
      if not With_Part then
         return Image;
      end if;
      for Y in 0 .. Height - 1 loop
         for X in 0 .. Width - 1 loop
            Hits := 0;
            for J in 0 .. Samples - 1 loop
               for I in 0 .. Samples - 1 loop
                  Inverse.Map_Point
                    (Real (X) - 0.5 + (Real (I) + 0.5) / Real (Samples),
                     Real (Y) - 0.5 + (Real (J) + 0.5) / Real (Samples), U, V);
                  if Part (U, V) then
                     Hits := Hits + 1;
                  end if;
               end loop;
            end loop;
            if Hits > 0 then
               Image.Set_Pixel
                 (X, Y, AMV.Images.Grey_8
                          (40 + (160 * Hits + Samples * Samples / 2)
                                / (Samples * Samples)));
            end if;
         end loop;
      end loop;
      return Image;
   end Picture;

   function Scene (X, Y, Degrees : Real) return AMV.Images.Ks_Image_8_Grey is
     (Picture (400, 300,
               AMV.Transforms.Create_Rigid (AMV.Misc.Deg_To_Rad (Degrees),
                                            X, Y)));

   ---------------------------------------------------------------------
   --  Building and checking flows
   ---------------------------------------------------------------------

   procedure Test_Building is
      Flow : AMV.Flow.Graphs.Ks_Flow;

      procedure Unknown_Kind is
         Ignore : constant Positive := Flow.Add_Node ("Telescope");
      begin
         null;
      end Unknown_Kind;

      procedure Mismatch is
      begin
         Flow.Link ("9.Width", "1.Image");
      end Mismatch;

      procedure Twice is
      begin
         Flow.Link ("input.Image", "9.Image");
      end Twice;

      procedure Cycle is
      begin
         Flow.Link ("2.Image", "1.Image");
      end Cycle;

      procedure Itself is
      begin
         Flow.Link ("1.Image", "1.Image");
      end Itself;

      procedure No_Port is
      begin
         Flow.Link ("9.Diameter", "output.Width");
      end No_Port;

      procedure Output_As_Source is
      begin
         Flow.Link ("output.Width", "10.Value");
      end Output_As_Source;

      procedure Bad_Endpoint is
      begin
         Flow.Link ("nine.Width", "10.Value");
      end Bad_Endpoint;

      procedure Out_Of_Range is
      begin
         Flow.Set_Param (10, "Low", From_Real (1.0E301));
      end Out_Of_Range;

      procedure Bad_Choice is
      begin
         Flow.Set_Param (9, "EdgeMode", From_String ("Triple"));
      end Bad_Choice;

      procedure Not_A_Rectangle is
         C : AMV.Shapes.Ks_Circle;
      begin
         Flow.Set_Param (9, "Region", From_Shape (C));
      end Not_A_Rectangle;

      procedure Run_Unfinished is
      begin
         Flow.Run;
      end Run_Unfinished;

      A, B, C, D : Positive;
   begin
      Expect_Flow_Error ("unknown kind", Unknown_Kind'Access, "Telescope");
      Flow.Add_Input ("Image", Image_8_Grey_Type);
      Flow.Add_Output ("Width", Real_Type);
      Flow.Add_Output ("Pass", Boolean_Type);
      A := Flow.Add_Node ("Fixture");
      B := Flow.Add_Node ("Fixture");
      C := Flow.Add_Node ("Caliper", Id => 9);
      D := Flow.Add_Node ("RangeCheck");
      Check (A = 1 and then B = 2 and then C = 9 and then D = 10,
             "ids: 1, 2, then 9 as given, then 10");
      Expect_Flow_Error ("a link of different types", Mismatch'Access,
                         "cannot link");
      Flow.Link ("input.Image", "9.Image");
      Expect_Flow_Error ("two links into one input", Twice'Access,
                         "already has a link");
      Flow.Link ("1.Image", "2.Image");
      Expect_Flow_Error ("a cycle", Cycle'Access, "cycle");
      Expect_Flow_Error ("a link to itself", Itself'Access, "itself");
      Expect_Flow_Error ("no such port", No_Port'Access, "no output");
      Expect_Flow_Error ("a flow output as a source",
                         Output_As_Source'Access, "destination");
      Expect_Flow_Error ("a bad endpoint", Bad_Endpoint'Access,
                         "bad link endpoint");
      Expect_Flow_Error ("a parameter out of range", Out_Of_Range'Access,
                         "must be in");
      Expect_Flow_Error ("a bad choice", Bad_Choice'Access, "one of");
      Expect_Flow_Error ("a circle as a caliper region",
                         Not_A_Rectangle'Access, "RectangleAffine");
      Flow.Link ("9.Width", "output.Width");
      Flow.Link ("9.Width", "10.Value");
      Check (Flow.Link_Count = 4, "four links");

      declare
         use Ada.Strings.Unbounded;
         Joined : Unbounded_String;
      begin
         for P of Flow.Problems loop
            Append (Joined, P & "; ");
         end loop;
         Check (Contains (To_String (Joined),
                          "node 1 (Fixture): input Image is not linked")
                and then Contains (To_String (Joined),
                                   "node 1 (Fixture): input Transform is "
                                   & "not linked")
                and then Contains (To_String (Joined),
                                   "output Pass is not linked"),
                "problems listed: " & To_String (Joined));
      end;
      Expect_Flow_Error ("running a flow with problems",
                         Run_Unfinished'Access, "not linked");
      Flow.Remove_Node (1);
      Check (Flow.Node_Count = 3 and then Flow.Link_Count = 3,
             "removing a node removes its links");
   end Test_Building;

   ---------------------------------------------------------------------
   --  Align and measure as a flow file
   ---------------------------------------------------------------------

   Align_Text : constant String :=
     "{" & LF
     & "  ""format"": 1, ""name"": ""align_and_measure""," & LF
     & "  ""inputs"": [{""name"": ""Image"", ""type"": ""Image_8_Grey""}],"
     & LF
     & "  ""outputs"": [{""name"": ""Slot"", ""type"": ""Real""},"
     & " {""name"": ""SlotOK"", ""type"": ""Boolean""}," & LF
     & "              {""name"": ""Plate"", ""type"": ""Real""},"
     & " {""name"": ""PlateOK"", ""type"": ""Boolean""}]," & LF
     & "  ""nodes"": [" & LF
     & "    {""id"": 1, ""kind"": ""ShapeMatch"", ""name"": ""Locate"","
     & " ""ui"": {""x"": 80, ""y"": 120}," & LF
     & "     ""params"": {""TrainImage"": ""align_model.bmp""," & LF
     & "       ""TrainRegion"": {""shape"": ""Rectangle"", ""centerX"": 100,"
     & " ""centerY"": 80, ""width"": 140, ""height"": 84}," & LF
     & "       ""OriginX"": 100, ""OriginY"": 80,"
     & " ""AngleLow"": -3.141592653589793,"
     & " ""AngleHigh"": 3.141592653589793}}," & LF
     & "    {""id"": 2, ""kind"": ""Fixture"","
     & " ""params"": {""FixturedSpaceName"": ""Part""}}," & LF
     & "    {""id"": 3, ""kind"": ""Caliper"", ""name"": ""Slot width"","
     & LF
     & "     ""params"": {""Region"": {""shape"": ""RectangleAffine"","
     & " ""space"": ""."", ""centerX"": 27, ""centerY"": 18, ""sideX"": 40,"
     & " ""sideY"": 16, ""rotation"": 0, ""skew"": 0}," & LF
     & "       ""EdgeMode"": ""Pair"", ""Edge0Polarity"": ""LightToDark"","
     & " ""Edge1Polarity"": ""DarkToLight""," & LF
     & "       ""Edge0Position"": -7, ""Edge1Position"": 7,"
     & " ""ContrastThreshold"": 20}}," & LF
     & "    {""id"": 4, ""kind"": ""Caliper"", ""name"": ""Plate length"","
     & LF
     & "     ""params"": {""Region"": {""shape"": ""RectangleAffine"","
     & " ""centerX"": 0, ""centerY"": -24, ""sideX"": 150, ""sideY"": 10,"
     & " ""rotation"": 0, ""skew"": 0}," & LF
     & "       ""EdgeMode"": ""Pair"", ""Edge0Polarity"": ""DarkToLight"","
     & " ""Edge1Polarity"": ""LightToDark""," & LF
     & "       ""Edge0Position"": -60, ""Edge1Position"": 60,"
     & " ""ContrastThreshold"": 20}}," & LF
     & "    {""id"": 5, ""kind"": ""RangeCheck"","
     & " ""params"": {""Low"": 13.9, ""High"": 14.1}}," & LF
     & "    {""id"": 6, ""kind"": ""RangeCheck"","
     & " ""params"": {""Low"": 119.9, ""High"": 120.1}}" & LF
     & "  ]," & LF
     & "  ""links"": [" & LF
     & "    {""from"": ""input.Image"", ""to"": ""1.Image""},"
     & " {""from"": ""input.Image"", ""to"": ""2.Image""}," & LF
     & "    {""from"": ""1.Pose"", ""to"": ""2.Transform""},"
     & " {""from"": ""2.Image"", ""to"": ""3.Image""}," & LF
     & "    {""from"": ""2.Image"", ""to"": ""4.Image""},"
     & " {""from"": ""3.Width"", ""to"": ""5.Value""}," & LF
     & "    {""from"": ""4.Width"", ""to"": ""6.Value""},"
     & " {""from"": ""3.Width"", ""to"": ""output.Slot""}," & LF
     & "    {""from"": ""5.Pass"", ""to"": ""output.SlotOK""},"
     & " {""from"": ""4.Width"", ""to"": ""output.Plate""}," & LF
     & "    {""from"": ""6.Pass"", ""to"": ""output.PlateOK""}" & LF
     & "  ]" & LF
     & "}" & LF;

   procedure Write_Text (Path, Text : String) is
      File : File_Type;
   begin
      Create (File, Out_File, Path);
      Put (File, Text);
      Close (File);
   end Write_Text;

   function Real_Output (Flow : AMV.Flow.Graphs.Ks_Flow; Name : String)
                         return Real is
      Value : constant Ks_Flow_Value := Flow.Get_Output (Name);
   begin
      return (if Value.Has_Value then Value.As_Real else -1.0);
   end Real_Output;

   function Boolean_Output (Flow : AMV.Flow.Graphs.Ks_Flow; Name : String)
                            return Boolean is
      Value : constant Ks_Flow_Value := Flow.Get_Output (Name);
   begin
      return Value.Has_Value and then Value.As_Boolean;
   end Boolean_Output;

   procedure Test_Align is
      Flow_Path  : constant String := Test_Dir & "/align.amvflow";
      Saved_Path : constant String := Test_Dir & "/align_saved.amvflow";
      Flow       : AMV.Flow.Graphs.Ks_Flow;
      Again      : AMV.Flow.Graphs.Ks_Flow;
      Scenes     : constant array (1 .. 2, 1 .. 3) of Real :=
        [[230.0, 140.0, 25.0], [150.0, 170.0, -110.0]];
   begin
      AMV.Image_File.Write_Image
        (Test_Dir & "/align_model.bmp",
         Picture (200, 160, AMV.Transforms.Create_Rigid (0.0, 100.0, 80.0)));
      Write_Text (Flow_Path, Align_Text);
      Flow.Load (Flow_Path);
      Check (Flow.Node_Count = 6 and then Flow.Link_Count = 11,
             "align: the flow file loads (6 nodes, 11 links)");
      Check (Flow.Problems.Is_Empty, "align: no problems");
      Check (Flow.Node (1).Name = "Locate" and then Flow.Node (1).X = 80.0,
             "align: node name and position");

      for N in Scenes'Range (1) loop
         declare
            Label : constant String := "align scene" & N'Image;
            Image : constant AMV.Images.Ks_Image_8_Grey :=
              Scene (Scenes (N, 1), Scenes (N, 2), Scenes (N, 3));
         begin
            --  Kept for trying amv_flow and the editor on.
            AMV.Image_File.Write_Image
              (Test_Dir & "/align_scene_"
               & Ada.Strings.Fixed.Trim (N'Image, Ada.Strings.Both) & ".bmp",
               Image);
            Flow.Set_Input ("Image", From_Image (Image));
            Flow.Run;
            Check (Flow.Result = AMV.Tools.Accept_Result,
                   Label & ": accepted (" & Flow.Message & ")");
            Check_Near (Real_Output (Flow, "Slot"), 14.0, 0.1,
                        Label & ": slot width");
            Check_Near (Real_Output (Flow, "Plate"), 120.0, 0.1,
                        Label & ": plate length");
            Check (Boolean_Output (Flow, "SlotOK")
                   and then Boolean_Output (Flow, "PlateOK"),
                   Label & ": both in tolerance");
            Check (Flow.Node (4).State = AMV.Flow.Nodes.Ran
                   and then Flow.Node (4).Time_Ms >= 0.0,
                   Label & ": node 4 ran");
         end;
      end loop;

      --  Saving and loading give the same flow and the same measures.
      Flow.Save (Saved_Path);
      Again.Load (Saved_Path);
      Check (Again.To_JSON = Flow.To_JSON, "align: saved and loaded again");
      Again.Set_Input ("Image", From_Image (Scene (230.0, 140.0, 25.0)));
      Again.Run;
      Flow.Set_Input ("Image", From_Image (Scene (230.0, 140.0, 25.0)));
      Flow.Run;
      Check (Real_Output (Again, "Slot") = Real_Output (Flow, "Slot"),
             "align: the loaded copy measures the same");

      --  No part: Shape Match rejects, everything after it is skipped.
      Flow.Set_Input
        ("Image",
         From_Image (Picture (400, 300,
                              AMV.Transforms.Create_Rigid (0.0, 0.0, 0.0),
                              With_Part => False)));
      Flow.Run;
      Check (Flow.Result = AMV.Tools.Reject, "no part: the flow rejects");
      Check (Flow.Node (1).State = AMV.Flow.Nodes.Ran
             and then Flow.Node (1).Result = AMV.Tools.Reject,
             "no part: Shape Match rejects");
      Check (Flow.Node (2).State = AMV.Flow.Nodes.Skipped
             and then Flow.Node (3).State = AMV.Flow.Nodes.Skipped
             and then Flow.Node (6).State = AMV.Flow.Nodes.Skipped,
             "no part: the fixture, the calipers and the checks are skipped");
      Check (not Flow.Get_Output ("Slot").Has_Value
             and then not Flow.Get_Output ("SlotOK").Has_Value,
             "no part: the outputs have no value");
      Check (Contains (Flow.Message, "node 1 (ShapeMatch)"),
             "no part: the message names Shape Match: " & Flow.Message);

      --  A tolerance the slot does not meet.
      Flow.Set_Param (5, "Low", From_Real (10.0));
      Flow.Set_Param (5, "High", From_Real (11.0));
      Flow.Set_Input ("Image", From_Image (Scene (150.0, 170.0, -110.0)));
      Flow.Run;
      Check (Flow.Result = AMV.Tools.Reject
             and then Flow.Get_Output ("SlotOK").Has_Value
             and then not Boolean_Output (Flow, "SlotOK")
             and then Boolean_Output (Flow, "PlateOK"),
             "out of tolerance: SlotOK false, the flow rejects");
      Check (Contains (Flow.Message, "node 5 (RangeCheck)"),
             "out of tolerance: the message names the check: "
             & Flow.Message);
   end Test_Align;

   ---------------------------------------------------------------------
   --  Blobs, built in code
   ---------------------------------------------------------------------

   procedure Test_Blob is
      Flow  : AMV.Flow.Graphs.Ks_Flow;
      Image : AMV.Images.Ks_Image_8_Grey :=
        AMV.Images.Create (200, 150, Value => 30);
      Discs : constant array (1 .. 3, 1 .. 3) of Real :=
        [[40.0, 40.0, 10.0], [100.0, 90.0, 15.0], [160.0, 70.0, 20.0]];
      Blob, Judge : Positive;
   begin
      for Y in 0 .. 149 loop
         for X in 0 .. 199 loop
            for D in Discs'Range (1) loop
               if (Real (X) - Discs (D, 1)) ** 2
                  + (Real (Y) - Discs (D, 2)) ** 2 <= Discs (D, 3) ** 2
               then
                  Image.Set_Pixel (X, Y, 220);
               end if;
            end loop;
         end loop;
      end loop;
      Flow.Add_Input ("Image", Image_8_Grey_Type);
      Flow.Add_Output ("Count", Integer_Type);
      Flow.Add_Output ("Area", Real_Type);
      Flow.Add_Output ("X", Real_Type);
      Flow.Add_Output ("Y", Real_Type);
      Flow.Add_Output ("Three", Boolean_Type);
      Blob := Flow.Add_Node ("Blob");
      Judge := Flow.Add_Node ("RangeCheck");
      Flow.Set_Param (Blob, "MinArea", From_Real (50.0));
      Flow.Set_Param (Judge, "High", From_Integer (3));
      Flow.Set_Param (Judge, "Low", From_Integer (3));
      Flow.Link ("input.Image", "1.Image");
      Flow.Link ("1.Count", "output.Count");
      Flow.Link ("1.Count", "2.Value");  --  an integer into a real
      Flow.Link ("1.Area", "output.Area");
      Flow.Link ("1.CenterX", "output.X");
      Flow.Link ("1.CenterY", "output.Y");
      Flow.Link ("2.Pass", "output.Three");
      Flow.Set_Input ("Image", From_Image (Image));
      Flow.Run;
      Check (Flow.Result = AMV.Tools.Accept_Result,
             "blob: accepted (" & Flow.Message & ")");
      Check (Flow.Get_Output ("Count").Has_Value
             and then Flow.Get_Output ("Count").As_Integer = 3,
             "blob: three blobs");
      Check_Near (Real_Output (Flow, "Area"), Pi * 400.0, Pi * 400.0 * 0.03,
                  "blob: the largest area");
      Check_Near (Real_Output (Flow, "X"), 160.0, 0.2, "blob: its centre x");
      Check_Near (Real_Output (Flow, "Y"), 70.0, 0.2, "blob: its centre y");
      Check (Boolean_Output (Flow, "Three"), "blob: the count checked");
   end Test_Blob;

   ---------------------------------------------------------------------
   --  Circularity, and the graphics the editor draws
   ---------------------------------------------------------------------

   procedure Test_Circularity is
      Flow  : AMV.Flow.Graphs.Ks_Flow;
      Image : AMV.Images.Ks_Image_8_Grey :=
        AMV.Images.Create (640, 480, Value => 30);
      Node  : Positive;
   begin
      --  An ellipse 200 x 160 (radii): roundness 0.80.
      for Y in 0 .. 479 loop
         for X in 0 .. 639 loop
            if ((Real (X) - 320.3) / 200.0) ** 2
               + ((Real (Y) - 240.7) / 160.0) ** 2 <= 1.0
            then
               Image.Set_Pixel (X, Y, 220);
            end if;
         end loop;
      end loop;
      Flow.Add_Input ("Image", Image_8_Grey_Type);
      Flow.Add_Output ("Roundness", Real_Type);
      Flow.Add_Output ("Found", Boolean_Type);
      Node := Flow.Add_Node ("Circularity");
      Flow.Link ("input.Image", "1.Image");
      Flow.Link ("1.Roundness", "output.Roundness");
      Flow.Link ("1.Found", "output.Found");
      Flow.Set_Input ("Image", From_Image (Image));
      Flow.Run;
      Check (Flow.Result = AMV.Tools.Accept_Result,
             "circularity: accepted (" & Flow.Message & ")");
      Check_Near (Real_Output (Flow, "Roundness"), 0.80, 0.01,
                  "circularity: the ellipse's roundness");
      declare
         Graphics : constant String := AMV.Flow.Reports.Graphics_JSON (Flow, Node);
      begin
         Check (Contains (Graphics, """role"": ""found""")
                and then Contains (Graphics, """kind"": ""polygon""")
                and then Contains (Graphics, """kind"": ""point"""),
                "circularity: the editor gets the edge and the centre");
      end;

      Flow.Set_Input
        ("Image", From_Image (AMV.Images.Create (100, 80, Value => 30)));
      Flow.Run;
      Check (Flow.Result = AMV.Tools.Reject
             and then Flow.Get_Output ("Found").Has_Value
             and then not Boolean_Output (Flow, "Found")
             and then not Flow.Get_Output ("Roundness").Has_Value,
             "circularity: nothing found is a reject");
   end Test_Circularity;

   ---------------------------------------------------------------------
   --  A cut in a cup: Circularity, Fixture, PolarUnwrap, Morphology, Blob
   ---------------------------------------------------------------------

   procedure Test_Cut is
      use Ada.Numerics.Long_Elementary_Functions;
      Flow : AMV.Flow.Graphs.Ks_Flow;
      Cut_Angle : constant Real := 200.0 * Pi / 180.0;

      --  A cup seen from above about (CX, CY), cut off by the image's
      --  bottom edge: the bottom (grey 220) to radius 140, the side wall
      --  (150) to 185, the rim (200) to 200; with a cut, a dark line 2 px
      --  wide across the wall and the rim.
      function Cup (CX, CY : Real; With_Cut : Boolean)
                    return AMV.Images.Ks_Image_8_Grey
      is
         Image : AMV.Images.Ks_Image_8_Grey :=
           AMV.Images.Create (640, 480, Value => 30);
         DX, DY, R, Along, Across : Real;
      begin
         for Y in 0 .. 479 loop
            for X in 0 .. 639 loop
               DX := Real (X) - CX;
               DY := Real (Y) - CY;
               R := Sqrt (DX * DX + DY * DY);
               Along := DX * Cos (Cut_Angle) + DY * Sin (Cut_Angle);
               Across := -DX * Sin (Cut_Angle) + DY * Cos (Cut_Angle);
               if With_Cut and then Along > 0.0 and then abs Across <= 1.0
                 and then R in 140.0 .. 200.0
               then
                  Image.Set_Pixel (X, Y, 90);
               elsif R <= 140.0 then
                  Image.Set_Pixel (X, Y, 220);
               elsif R <= 185.0 then
                  Image.Set_Pixel (X, Y, 150);
               elsif R <= 200.0 then
                  Image.Set_Pixel (X, Y, 200);
               end if;
            end loop;
         end loop;
         return Image;
      end Cup;

      --  The wall and the rim (radii 148 to 188 about the cup's centre),
      --  leaving out the part below the image.
      function Wall (Span_Degrees : Real) return Ks_Flow_Value is
         A : AMV.Shapes.Ks_Circular_Annulus_Section;
      begin
         A.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
           (0.0, 0.0, 148.0, 140.0 * Pi / 180.0, Span_Degrees * Pi / 180.0,
            188.0 / 148.0);
         return From_Shape (A);
      end Wall;

      procedure Run_On (CX, CY : Real; With_Cut : Boolean) is
      begin
         Flow.Set_Input ("Image", From_Image (Cup (CX, CY, With_Cut)));
         Flow.Run;
      end Run_On;

      function Cuts_Found return Integer is
        (if Flow.Get_Output ("Cuts").Has_Value
         then Integer (Flow.Get_Output ("Cuts").As_Integer) else -1);

      Unwrap, Lines, Cuts : Positive;
   begin
      Flow.Add_Input ("Image", Image_8_Grey_Type);
      Flow.Add_Output ("X", Real_Type);
      Flow.Add_Output ("Y", Real_Type);
      Flow.Add_Output ("R", Real_Type);
      Flow.Add_Output ("Cuts", Integer_Type);
      Flow.Add_Output ("NoCut", Boolean_Type);
      Check (Flow.Add_Node ("Circularity") = 1, "cut: node 1");
      Check (Flow.Add_Node ("Fixture") = 2, "cut: node 2");
      Unwrap := Flow.Add_Node ("PolarUnwrap");
      Lines := Flow.Add_Node ("Morphology");
      Cuts := Flow.Add_Node ("Blob");
      Check (Flow.Add_Node ("RangeCheck") = 6, "cut: node 6");
      Flow.Set_Param (2, "FixturedSpaceName", From_String ("Cup"));
      Flow.Set_Param (Unwrap, "Region", Wall (260.0));
      Flow.Set_Param (Lines, "Operation", From_String ("CloseMinusOriginal"));
      Flow.Set_Param (Lines, "KernelWidth", From_Integer (15));
      Flow.Set_Param (Lines, "KernelHeight", From_Integer (1));
      Flow.Set_Param (Cuts, "Threshold", From_Integer (14));
      Flow.Set_Param (Cuts, "MinArea", From_Real (50.0));
      Flow.Link ("input.Image", "1.Image");
      Flow.Link ("input.Image", "2.Image");
      Flow.Link ("1.Pose", "2.Transform");
      Flow.Link ("2.Image", "3.Image");
      Flow.Link ("3.Image", "4.Image");
      Flow.Link ("4.Image", "5.Image");
      Flow.Link ("5.Count", "6.Value");
      Flow.Link ("1.CenterX", "output.X");
      Flow.Link ("1.CenterY", "output.Y");
      Flow.Link ("1.Radius", "output.R");
      Flow.Link ("5.Count", "output.Cuts");
      Flow.Link ("6.Pass", "output.NoCut");
      Check (Flow.Problems.Is_Empty, "cut: no problems");

      Run_On (320.3, 340.7, With_Cut => False);
      Check (Flow.Result = AMV.Tools.Warning
             and then Contains (Flow.Message, "touches the image border"),
             "cut: the cup runs out of the image (" & Flow.Message & ")");
      Check_Near (Real_Output (Flow, "X"), 320.3, 0.5,
                  "cut: the rim's centre x, from the edge inside the image");
      Check_Near (Real_Output (Flow, "Y"), 340.7, 0.5, "cut: its centre y");
      Check_Near (Real_Output (Flow, "R"), 200.0, 1.0, "cut: its radius");
      Check (Cuts_Found = 0 and then Boolean_Output (Flow, "NoCut"),
             "cut: none in a whole cup");
      declare
         Graphics : constant String :=
           AMV.Flow.Reports.Graphics_JSON (Flow, Unwrap);
      begin
         Check (Contains (Graphics, """param"": ""Region""")
                and then Contains (Graphics, """role"": ""region"""),
                "cut: the editor gets the annulus as an editable region");
      end;

      --  Where the cut is, back on the camera image.
      Check (Flow.Add_Node ("PolarPoint") = 7, "cut: node 7");
      Flow.Add_Output ("CutAngle", Real_Type);
      Flow.Link ("2.Image", "7.Image");
      Flow.Link ("3.Region", "7.Region");
      Flow.Link ("5.CenterX", "7.X");
      Flow.Link ("5.CenterY", "7.Y");
      Flow.Link ("7.Angle", "output.CutAngle");

      Run_On (320.3, 340.7, With_Cut => True);
      Check_Near (Real_Output (Flow, "CutAngle"), Cut_Angle - 2.0 * Pi, 0.03,
                  "cut: its angle on the cup (200 degrees)");
      Check (Contains (AMV.Flow.Reports.Graphics_JSON (Flow, 7),
                       """kind"": ""point"""),
             "cut: the editor marks it on the image");
      Check (Cuts_Found = 1
             and then not Boolean_Output (Flow, "NoCut")
             and then Flow.Result = AMV.Tools.Reject
             and then Contains (Flow.Message, "node 6 (RangeCheck)"),
             "cut: one found, the flow rejects and says why, not the "
             & "warning before (" & Flow.Message & ")");

      --  The cup elsewhere: the region follows it through the fixture.
      Run_On (290.0, 320.0, With_Cut => True);
      Check (Cuts_Found = 1, "cut: found in a cup moved by (-30, -21)");
      Run_On (290.0, 320.0, With_Cut => False);
      Check (Cuts_Found = 0, "cut: none in the moved cup without one");
      Check (Flow.Result /= AMV.Tools.Reject
             and then Flow.Node (7).State = AMV.Flow.Nodes.Ran
             and then not Flow.Get_Output ("CutAngle").Has_Value,
             "cut: nothing found, PolarPoint gives no point and the part "
             & "passes (" & Flow.Message & ")");
      --  The strip's region is the one it was made with.
      Flow.Set_Param (Unwrap, "Region", Wall (250.0));
      Check_Near
        (AMV.Shapes.Ks_Circular_Annulus_Section
           (Flow.Node (Unwrap).Get_Output ("Region").As_Shape).Angle_Span,
         260.0 * Pi / 180.0, 1.0E-9,
         "cut: PolarUnwrap's Region is the one of the last run");
      Flow.Set_Param (Unwrap, "Region", Wall (260.0));

      --  All round, the annulus leaves the image.
      Flow.Set_Param (Unwrap, "Region", Wall (360.0));
      Run_On (320.3, 340.7, With_Cut => True);
      Check (Flow.Node (Unwrap).Result = AMV.Tools.Error
             and then Flow.Node (Cuts).State = AMV.Flow.Nodes.Skipped,
             "cut: an annulus outside the image is an error ("
             & Flow.Node (Unwrap).Message & ")");
      Flow.Set_Param (Unwrap, "Region", Wall (260.0));
      Flow.Set_Param (Lines, "KernelWidth", From_Integer (4));
      Flow.Run;
      Check (Flow.Node (Lines).Result = AMV.Tools.Error
             and then Contains (Flow.Node (Lines).Message, "KernelWidth"),
             "cut: an even kernel is an error ("
             & Flow.Node (Lines).Message & ")");

      declare
         procedure Not_An_Annulus is
            C : AMV.Shapes.Ks_Circle;
         begin
            Flow.Set_Param (Unwrap, "Region", From_Shape (C));
         end Not_An_Annulus;
      begin
         Expect_Flow_Error ("cut: PolarUnwrap's Region is an annulus",
                            Not_An_Annulus'Access,
                            "CircularAnnulusSection");
      end;
   end Test_Cut;

   ---------------------------------------------------------------------
   --  CsvLog, and inputs of type Any
   ---------------------------------------------------------------------

   procedure Test_Log is
      Path : constant String := Test_Dir & "/log.csv";
      Flow : AMV.Flow.Graphs.Ks_Flow;
      Disc : AMV.Images.Ks_Image_8_Grey :=
        AMV.Images.Create (200, 150, Value => 30);
      Log  : Positive;

      --  The lines of the log file.
      function Lines return AMV.Flow.Graphs.String_Vectors.Vector is
         File   : Ada.Text_IO.File_Type;
         Result : AMV.Flow.Graphs.String_Vectors.Vector;
      begin
         Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Path);
         while not Ada.Text_IO.End_Of_File (File) loop
            Result.Append (Ada.Text_IO.Get_Line (File));
         end loop;
         Ada.Text_IO.Close (File);
         return Result;
      end Lines;

      --  Line without its first cell (the time).
      function After_Time (Line : String) return String is
        (Line (Ada.Strings.Fixed.Index (Line, ",") + 1 .. Line'Last));

      procedure Output_Of_Type_Any is
         Other : AMV.Flow.Graphs.Ks_Flow;
      begin
         Other.Add_Output ("Anything", Any_Type);
      end Output_Of_Type_Any;

      procedure Nine_Columns is
      begin
         Flow.Set_Param (Log, "Columns", From_String ("a,b,c,d,e,f,g,h,i"));
      end Nine_Columns;
   begin
      if Ada.Directories.Exists (Path) then
         Ada.Directories.Delete_File (Path);
      end if;
      for Y in 0 .. 149 loop
         for X in 0 .. 199 loop
            if (Real (X) - 100.0) ** 2 + (Real (Y) - 75.0) ** 2 <= 40.0 ** 2
            then
               Disc.Set_Pixel (X, Y, 220);
            end if;
         end loop;
      end loop;

      --  Circularity, a range check on its roundness, and a log of both.
      Flow.Add_Input ("Image", Image_8_Grey_Type);
      Flow.Add_Output ("Rows", Integer_Type);
      Check (Flow.Add_Node ("Circularity") = 1, "log: node 1");
      Check (Flow.Add_Node ("RangeCheck") = 2, "log: node 2");
      Log := Flow.Add_Node ("CsvLog");
      Flow.Set_Param (2, "Low", From_Real (0.9));
      Flow.Set_Param (2, "High", From_Real (1.0));
      Flow.Set_Param (Log, "Path", From_String (Path));
      Flow.Set_Param (Log, "Columns",
                      From_String ("Found, Roundness, Round, Image"));
      Flow.Link ("input.Image", "1.Image");
      Flow.Link ("1.Roundness", "2.Value");
      --  Any input takes a Boolean, a Real and an image alike.
      Flow.Link ("1.Found", "3.Value1");
      Flow.Link ("1.Roundness", "3.Value2");
      Flow.Link ("2.Pass", "3.Value3");
      Flow.Link ("input.Image", "3.Value4");
      Flow.Link ("3.Rows", "output.Rows");
      Check (Flow.Problems.Is_Empty,
             "log: no problems (its inputs need no links)");

      Flow.Set_Input ("Image", From_Image (Disc));
      Flow.Run;
      Check (Flow.Result = AMV.Tools.Accept_Result,
             "log: a round disc accepted (" & Flow.Message & ")");
      --  Nothing found: the range check is skipped, the log still runs.
      Flow.Set_Input
        ("Image", From_Image (AMV.Images.Create (100, 80, Value => 30)));
      Flow.Run;
      Check (Flow.Node (2).State = AMV.Flow.Nodes.Skipped
             and then Flow.Node (Log).State = AMV.Flow.Nodes.Ran
             and then Flow.Node (Log).Result = AMV.Tools.Accept_Result,
             "log: runs although a source was skipped");
      Check (Flow.Get_Output ("Rows").Has_Value
             and then Flow.Get_Output ("Rows").As_Integer = 2,
             "log: two rows written");
      declare
         L : constant AMV.Flow.Graphs.String_Vectors.Vector := Lines;
      begin
         Check (Natural (L.Length) = 3
                and then L (1) = "time,Found,Roundness,Round,Image",
                "log: the header, then a row a run ("
                & (if L.Is_Empty then "" else L (1)) & ")");
         if Natural (L.Length) = 3 then
            Check (Contains (L (2), ",true,0.9")
                   and then Contains (L (2), ",true,image 200x150"),
                   "log: the first run's values (" & L (2) & ")");
            Check (After_Time (L (3)) = "false,,,image 100x80",
                   "log: empty cells for no value (" & L (3) & ")");
            Check (L (2) (1 .. 2) = "20" and then L (2) (11) = ' ',
                   "log: the row starts with the date and time ("
                   & L (2) & ")");
         end if;
      end;

      Flow.Set_Param (Log, "Enabled", From_Boolean (False));
      Flow.Run;
      Check (Natural (Lines.Length) = 3, "log: nothing written when disabled");
      Flow.Set_Param (Log, "Enabled", From_Boolean (True));
      Flow.Set_Param (Log, "Columns", From_String ("Found, Roundness"));
      Flow.Run;
      Check (Flow.Node (Log).Result = AMV.Tools.Error
             and then Contains (Flow.Node (Log).Message, "other columns")
             and then Natural (Lines.Length) = 3,
             "log: a file with other columns is not appended to ("
             & Flow.Node (Log).Message & ")");
      Flow.Set_Param (Log, "Columns",
                      From_String ("Found, Roundness, Round, Image"));
      Flow.Set_Param (Log, "Enabled", From_Boolean (True));
      --  A folder that is a file: written nowhere, on any system.
      Flow.Set_Param (Log, "Path", From_String (Path & "/x.csv"));
      Flow.Run;
      Check (Flow.Node (Log).Result = AMV.Tools.Error
             and then Contains (Flow.Node (Log).Message, "cannot write"),
             "log: a file that cannot be written is an error ("
             & Flow.Node (Log).Message & ")");

      Expect_Flow_Error ("log: a flow output cannot be of type Any",
                         Output_Of_Type_Any'Access, "type Any");
      Expect_Flow_Error ("log: at most 8 columns", Nine_Columns'Access,
                         "at most");
      Check (Can_Link (Boolean_Type, Any_Type)
             and then Can_Link (Image_8_Grey_Type, Any_Type)
             and then not Can_Link (Any_Type, Real_Type)
             and then not Can_Link (Any_Type, Any_Type),
             "log: anything links into Any, Any into nothing");
   end Test_Log;

   ---------------------------------------------------------------------
   --  A text that is not a flow, a run that cannot start
   ---------------------------------------------------------------------

   procedure Test_Kept is
      Flow : AMV.Flow.Graphs.Ks_Flow;

      procedure Bad_Text is
      begin
         Flow.From_JSON ("{""format"": 1, ""nodes"": [{""id"": 1, "
                         & """kind"": ""NoSuchKind""}]}");
      end Bad_Text;
   begin
      Flow.Add_Input ("Image", Image_8_Grey_Type);
      Flow.Add_Output ("Count", Integer_Type);
      Check (Flow.Add_Node ("Blob") = 1, "kept: node 1");
      Flow.Link ("input.Image", "1.Image");
      Flow.Link ("1.Count", "output.Count");
      Flow.Set_Input ("Image", From_Image
        (AMV.Images.Create (40, 30, Value => 200)));
      Flow.Run;
      Check (Flow.Result = AMV.Tools.Accept_Result
             and then Flow.Get_Output ("Count").Has_Value,
             "kept: a first run");

      Expect_Flow_Error ("kept: an unknown kind", Bad_Text'Access,
                         "NoSuchKind");
      Check (Flow.Node_Count = 1 and then Flow.Link_Count = 2
             and then Flow.Input_Count = 1,
             "kept: a text that is not a flow leaves the flow as it was");

      --  A run that cannot start does not leave the last one's results.
      Flow.Unlink ("1.Image");
      declare
         procedure Run_It is
         begin
            Flow.Run;
         end Run_It;
      begin
         Expect_Flow_Error ("kept: a run of a flow with a problem",
                            Run_It'Access, "not linked");
      end;
      Check (Flow.Result = AMV.Tools.Error
             and then Contains (Flow.Message, "not linked")
             and then not Flow.Get_Output ("Count").Has_Value
             and then Flow.Node (1).State = AMV.Flow.Nodes.Not_Run,
             "kept: a run that cannot start clears the last results ("
             & Flow.Message & ")");

      --  A train image that cannot be read: the parameter keeps its old
      --  value; in a flow file, the flow loads and says what is wrong.
      declare
         Matcher : constant Positive := Flow.Add_Node ("ShapeMatch");
         procedure Bad_Image is
         begin
            Flow.Set_Param (Matcher, "TrainImage",
                            From_String ("no_such_image.bmp"));
         end Bad_Image;
      begin
         Expect_Flow_Error ("kept: a train image that cannot be read",
                            Bad_Image'Access, "train image");
         Check (Flow.Node (Matcher).Get_Param ("TrainImage").As_String = "",
                "kept: the parameter keeps its old value");
      end;
      declare
         Other : AMV.Flow.Graphs.Ks_Flow;
         Found : Boolean := False;
      begin
         Other.From_JSON
           ("{""format"": 1, ""nodes"": [{""id"": 1, ""kind"": "
            & """ShapeMatch"", ""params"": {""TrainImage"": "
            & """no_such_image.bmp""}}]}");
         for P of Other.Problems loop
            Found := Found or else Contains (P, "cannot read the train image");
         end loop;
         Check (Other.Node_Count = 1 and then Found,
                "kept: a flow whose train image is missing loads, with the "
                & "problem");
      end;
   end Test_Kept;

   ---------------------------------------------------------------------
   --  And, Or, Not, and the pass / fail tally
   ---------------------------------------------------------------------

   procedure Test_Logic is
      Flow : AMV.Flow.Graphs.Ks_Flow;
      Disc : AMV.Images.Ks_Image_8_Grey :=
        AMV.Images.Create (200, 150, Value => 30);
      Empty : constant AMV.Images.Ks_Image_8_Grey :=
        AMV.Images.Create (100, 80, Value => 30);

      procedure Run_With (A : Boolean; Image : AMV.Images.Ks_Image_8_Grey) is
      begin
         Flow.Set_Input ("A", From_Boolean (A));
         Flow.Set_Input ("Image", From_Image (Image));
         Flow.Run;
      end Run_With;

      function Output (Name : String) return Boolean is
        (Boolean_Output (Flow, Name));
   begin
      for Y in 0 .. 149 loop
         for X in 0 .. 199 loop
            if (Real (X) - 100.0) ** 2 + (Real (Y) - 75.0) ** 2 <= 40.0 ** 2
            then
               Disc.Set_Pixel (X, Y, 220);
            end if;
         end loop;
      end loop;
      --  A, and whether the image holds something round: And (judging),
      --  Or, Not A.
      Flow.Add_Input ("A", Boolean_Type);
      Flow.Add_Input ("Image", Image_8_Grey_Type);
      Flow.Add_Output ("Both", Boolean_Type);
      Flow.Add_Output ("Either", Boolean_Type);
      Flow.Add_Output ("NotA", Boolean_Type);
      Check (Flow.Add_Node ("Circularity") = 1, "logic: node 1");
      Check (Flow.Add_Node ("RangeCheck") = 2, "logic: node 2");
      Check (Flow.Add_Node ("And") = 3, "logic: node 3");
      Check (Flow.Add_Node ("Or") = 4, "logic: node 4");
      Check (Flow.Add_Node ("Not") = 5, "logic: node 5");
      Flow.Set_Param (2, "Low", From_Real (0.9));
      Flow.Set_Param (2, "High", From_Real (1.0));
      Flow.Set_Param (3, "Judge", From_Boolean (True));
      Flow.Link ("input.Image", "1.Image");
      Flow.Link ("1.Roundness", "2.Value");
      Flow.Link ("input.A", "3.In1");
      Flow.Link ("2.Pass", "3.In2");
      Flow.Link ("input.A", "4.In1");
      Flow.Link ("2.Pass", "4.In3");
      Flow.Link ("input.A", "5.In");
      Flow.Link ("3.Out", "output.Both");
      Flow.Link ("4.Out", "output.Either");
      Flow.Link ("5.Out", "output.NotA");
      Check (Flow.Problems.Is_Empty, "logic: no problems (In3, In4 unlinked)");

      Run_With (True, Disc);
      Check (Output ("Both") and then Output ("Either")
             and then not Output ("NotA")
             and then Flow.Result = AMV.Tools.Accept_Result,
             "logic: A and round: both, accepted (" & Flow.Message & ")");
      Run_With (False, Disc);
      Check (not Output ("Both") and then Output ("Either")
             and then Output ("NotA")
             and then Flow.Result = AMV.Tools.Reject
             and then Contains (Flow.Message, "node 3 (And)"),
             "logic: not A: And judges the run a reject ("
             & Flow.Message & ")");
      --  Nothing round: the range check is skipped; its Pass counts as
      --  False, and And and Or still run.
      Run_With (True, Empty);
      Check (Flow.Node (2).State = AMV.Flow.Nodes.Skipped
             and then Flow.Node (3).State = AMV.Flow.Nodes.Ran
             and then not Output ("Both") and then Output ("Either"),
             "logic: an input with no value is False");
      Run_With (False, Empty);
      Check (not Output ("Either"), "logic: Or of two False");

      declare
         C : constant AMV.Flow.Graphs.Run_Counts := Flow.Counts;
      begin
         Check (C.Runs = 4 and then C.Accepted = 1
                and then C.Rejected = 3 and then C.Failed = 0,
                "logic: the tally of four runs");
      end;
      Flow.Unlink ("3.In1");
      Flow.Unlink ("3.In2");
      Run_With (True, Disc);
      Check (Flow.Node (3).Result = AMV.Tools.Error
             and then Contains (Flow.Node (3).Message, "no input"),
             "logic: And with no input linked is an error");
      Check (Flow.Counts.Runs = 5 and then Flow.Counts.Failed = 1,
             "logic: an error counted");
      Flow.Reset_Counts;
      Check (Flow.Counts.Runs = 0, "logic: the tally reset");
      --  A range check that does not judge: Pass alone says it.
      Flow.Link ("input.A", "3.In1");
      Flow.Link ("2.Pass", "3.In2");
      Flow.Set_Param (2, "Low", From_Real (0.1));
      Flow.Set_Param (2, "High", From_Real (0.5));
      Flow.Set_Param (2, "Judge", From_Boolean (False));
      Run_With (False, Disc);
      Check (Flow.Node (2).Result = AMV.Tools.Accept_Result
             and then not Output ("Either"),
             "logic: a range check with Judge off only says Pass");
   end Test_Logic;

   ---------------------------------------------------------------------
   --  FindCircle, Distance, Histogram
   ---------------------------------------------------------------------

   procedure Test_Measure is
      use Ada.Numerics.Long_Elementary_Functions;
      Disc : AMV.Images.Ks_Image_8_Grey :=
        AMV.Images.Create (200, 150, Value => 30);
      Expected : AMV.Shapes.Ks_Circle;
      Middle   : AMV.Shapes.Ks_Circle;
   begin
      for Y in 0 .. 149 loop
         for X in 0 .. 199 loop
            if (Real (X) - 100.3) ** 2 + (Real (Y) - 74.6) ** 2 <= 40.0 ** 2
            then
               Disc.Set_Pixel (X, Y, 220);
            end if;
         end loop;
      end loop;

      --  FindCircle: a disc of radius 40 looked for from radius 48.
      declare
         Flow : AMV.Flow.Graphs.Ks_Flow;
      begin
         Flow.Add_Input ("Image", Image_8_Grey_Type);
         Flow.Add_Output ("X", Real_Type);
         Flow.Add_Output ("Y", Real_Type);
         Flow.Add_Output ("R", Real_Type);
         Flow.Add_Output ("Found", Boolean_Type);
         Check (Flow.Add_Node ("FindCircle") = 1, "measure: node 1");
         Expected.Set_Center_Radius (98.0, 76.0, 48.0);
         Flow.Set_Param (1, "Expected", From_Shape (Expected));
         Flow.Set_Param (1, "SearchLength", From_Real (30.0));
         Flow.Set_Param (1, "Polarity", From_String ("DarkToLight"));
         Flow.Set_Param (1, "SearchDirection", From_String ("Inward"));
         Flow.Link ("input.Image", "1.Image");
         Flow.Link ("1.CenterX", "output.X");
         Flow.Link ("1.CenterY", "output.Y");
         Flow.Link ("1.Radius", "output.R");
         Flow.Link ("1.Found", "output.Found");
         Flow.Set_Input ("Image", From_Image (Disc));
         Flow.Run;
         Check (Flow.Result = AMV.Tools.Accept_Result
                and then Boolean_Output (Flow, "Found"),
                "measure: the circle found (" & Flow.Message & ")");
         Check_Near (Real_Output (Flow, "X"), 100.3, 0.3, "measure: its x");
         Check_Near (Real_Output (Flow, "Y"), 74.6, 0.3, "measure: its y");
         Check_Near (Real_Output (Flow, "R"), 40.0, 0.6, "measure: its radius");
         Check (Contains (AMV.Flow.Reports.Graphics_JSON (Flow, 1),
                          """role"": ""found"""),
                "measure: the editor gets the circle found");
         Flow.Set_Input ("Image", From_Image
           (AMV.Images.Create (200, 150, Value => 30)));
         Flow.Run;
         Check (Flow.Result = AMV.Tools.Reject
                and then not Boolean_Output (Flow, "Found")
                and then not Flow.Get_Output ("R").Has_Value,
                "measure: no circle is a reject (" & Flow.Message & ")");
         --  Too many outliers to ignore for 12 calipers... a setting the
         --  tool refuses is an Error, not a part that failed.
         Flow.Set_Param (1, "NumToIgnore", From_Integer (10));
         Flow.Set_Input ("Image", From_Image (Disc));
         Flow.Run;
         Check (Flow.Result = AMV.Tools.Error
                and then Contains (Flow.Message, "NumToIgnore"),
                "measure: bad settings are an error that says which ("
                & Flow.Message & ")");
      end;

      --  Distance: a 3-4-5 triangle.
      declare
         Flow : AMV.Flow.Graphs.Ks_Flow;
      begin
         Flow.Add_Input ("A", Real_Type);
         Flow.Add_Input ("B", Real_Type);
         Flow.Add_Output ("D", Real_Type);
         Flow.Add_Output ("Angle", Real_Type);
         Check (Flow.Add_Node ("Distance") = 1, "measure: distance node");
         Flow.Link ("input.A", "1.X1");
         Flow.Link ("input.A", "1.Y1");
         Flow.Link ("input.B", "1.X2");
         Flow.Link ("input.A", "1.Y2");
         Flow.Link ("1.Distance", "output.D");
         Flow.Link ("1.Angle", "output.Angle");
         Flow.Set_Input ("A", From_Real (1.0));
         Flow.Set_Input ("B", From_Real (4.0));
         Flow.Run;
         Check_Near (Real_Output (Flow, "D"), 3.0, 1.0E-9,
                     "measure: the distance");
         Check_Near (Real_Output (Flow, "Angle"), 0.0, 1.0E-9,
                     "measure: its angle");
         Flow.Unlink ("1.Y2");
         Flow.Link ("input.B", "1.Y2");
         Flow.Run;
         Check_Near (Real_Output (Flow, "D"), 3.0 * Sqrt (2.0), 1.0E-9,
                     "measure: a diagonal");
         Check_Near (Real_Output (Flow, "Angle"), Pi / 4.0, 1.0E-9,
                     "measure: at 45 degrees");
      end;

      --  Histogram: the whole image, then inside the disc.
      declare
         Flow : AMV.Flow.Graphs.Ks_Flow;
      begin
         Flow.Add_Input ("Image", Image_8_Grey_Type);
         Flow.Add_Output ("Mean", Real_Type);
         Flow.Add_Output ("Min", Integer_Type);
         Flow.Add_Output ("Max", Integer_Type);
         Flow.Add_Output ("Threshold", Integer_Type);
         Flow.Add_Output ("Samples", Integer_Type);
         Check (Flow.Add_Node ("Histogram") = 1, "measure: histogram node");
         Flow.Link ("input.Image", "1.Image");
         Flow.Link ("1.Mean", "output.Mean");
         Flow.Link ("1.Minimum", "output.Min");
         Flow.Link ("1.Maximum", "output.Max");
         Flow.Link ("1.Threshold", "output.Threshold");
         Flow.Link ("1.Samples", "output.Samples");
         Flow.Set_Input ("Image", From_Image (Disc));
         Flow.Run;
         Check (Flow.Get_Output ("Min").As_Integer = 30
                and then Flow.Get_Output ("Max").As_Integer = 220
                and then Flow.Get_Output ("Samples").As_Integer = 30_000
                and then Flow.Get_Output ("Threshold").As_Integer in 31 .. 220,
                "measure: the whole image's statistics");
         Middle.Set_Center_Radius (100.0, 75.0, 20.0);
         Flow.Set_Param (1, "Region", From_Shape (Middle));
         Flow.Run;
         Check_Near (Real_Output (Flow, "Mean"), 220.0, 1.0E-9,
                     "measure: inside the disc");
         Middle.Set_Center_Radius (-100.0, -100.0, 5.0);
         Flow.Set_Param (1, "Region", From_Shape (Middle));
         Flow.Run;
         Check (Flow.Node (1).Result = AMV.Tools.Reject
                and then not Flow.Get_Output ("Mean").Has_Value,
                "measure: a region off the image is a reject ("
                & Flow.Node (1).Message & ")");
         --  null clears the region: the whole image again.
         Flow.Set_Param_JSON (1, "Region", "null");
         Flow.Run;
         Check (Flow.Get_Output ("Samples").As_Integer = 30_000,
                "measure: the region cleared, the whole image");
      end;
   end Test_Measure;

   ---------------------------------------------------------------------
   --  Malformed flow files
   ---------------------------------------------------------------------

   procedure Test_Malformed is
      Flow : AMV.Flow.Graphs.Ks_Flow;

      procedure Bad (Text, Why : String) is
         procedure Try is
         begin
            Flow.From_JSON (Text, Test_Dir);
         end Try;
      begin
         Expect_Flow_Error ("bad flow " & Text, Try'Access, Why);
         Check (Flow.Node_Count = 0 and then Flow.Input_Count = 0,
                "bad flow leaves the flow as it was (empty): " & Text);
      end Bad;

      Head : constant String := "{""format"": 1, ""inputs"": [{""name"": "
        & """Image"", ""type"": ""Image_8_Grey""}], ";
   begin
      Bad ("[]", "object");
      Bad ("{""format"": 2}", "format");
      Bad ("{""name"": ""x""}", "format");
      Bad ("{""format"": 1, ""extra"": 1}", "unknown member");
      Bad (Head & """nodes"": [{""id"": 1, ""kind"": ""Lens""}]}",
           "unknown node kind");
      Bad (Head & """nodes"": [{""id"": 1, ""kind"": ""Blob"", ""params"": "
           & "{""Thresh"": 3}}]}", "no parameter");
      Bad (Head & """nodes"": [{""id"": 1, ""kind"": ""Blob"", ""params"": "
           & "{""Threshold"": ""high""}}]}", "Threshold");
      Bad (Head & """nodes"": [{""id"": 1, ""kind"": ""Blob"", ""params"": "
           & "{""Threshold"": 300}}]}", "must be in");
      Bad (Head & """nodes"": [{""id"": 1, ""kind"": ""Blob""}, "
           & "{""id"": 1, ""kind"": ""Blob""}]}", "already a node");
      Bad (Head & """nodes"": [{""id"": 1.5, ""kind"": ""Blob""}]}",
           "whole number");
      Bad (Head & """nodes"": [{""id"": 1, ""kind"": ""Blob""}], ""links"": "
           & "[{""from"": ""1.Area"", ""to"": ""1.Image""}]}", "cannot link");
      Bad (Head & """nodes"": [{""id"": 1, ""kind"": ""Blob""}], ""links"": "
           & "[{""from"": ""input.Image"", ""to"": ""1.Image"", ""x"": 1}]}",
           "unknown member");
      Bad ("{""format"": 1, ""inputs"": [{""name"": ""a.b"", ""type"": "
           & """Real""}]}", "not a valid");
      Bad ("{""format"": 1, ""inputs"": [{""name"": ""A"", ""type"": "
           & """Complex""}]}", "unknown type");
   end Test_Malformed;

   ---------------------------------------------------------------------

begin
   Ada.Directories.Create_Path (Test_Dir);
   Test_JSON;
   Test_Shapes;
   Test_Building;
   Test_Align;
   Test_Blob;
   Test_Circularity;
   Test_Cut;
   Test_Log;
   Test_Kept;
   Test_Logic;
   Test_Measure;
   Test_Malformed;
   if Failures = 0 then
      Put_Line ("PASS: AMV Flow," & Checks'Image & " checks");
   else
      Put_Line ("FAIL:" & Failures'Image & " of" & Checks'Image & " checks");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Flow;
