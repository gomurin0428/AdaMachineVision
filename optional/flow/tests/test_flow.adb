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
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AMV;
with AMV.Flow;
with AMV.Flow.Graphs;
with AMV.Flow.JSON;
with AMV.Flow.Nodes;
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
   begin
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
                "bad flow leaves the flow empty: " & Text);
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
      Bad (Head & """nodes"": [{""id"": 1, ""kind"": ""ShapeMatch"", "
           & """params"": {""TrainImage"": ""missing.bmp""}}]}",
           "cannot read the train image");
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
   Test_Malformed;
   if Failures = 0 then
      Put_Line ("PASS: AMV Flow," & Checks'Image & " checks");
   else
      Put_Line ("FAIL:" & Failures'Image & " of" & Checks'Image & " checks");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Flow;
