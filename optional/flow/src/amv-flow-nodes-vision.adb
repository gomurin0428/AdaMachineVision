pragma SPARK_Mode (Off);

with Ada.Exceptions;
with Ada.Numerics;

with AMV.Blob;
with AMV.Calib_Fix;
with AMV.Caliper;
with AMV.Image_File;
with AMV.Images;
with AMV.Shape_Match;
with AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Transforms;
with AMV.Flow.Values;

package body AMV.Flow.Nodes.Vision is

   use AMV.Flow.Values;
   use type AMV.Tools.Ks_Tool_Result_Constants;
   use type AMV.Caliper.Int32;

   Two_Pi : constant := 2.0 * Ada.Numerics.Pi;
   Large  : constant := 1.0E6;

   function U (S : String) return Unbounded_String
     renames To_Unbounded_String;

   function Is_Absolute (Path : String) return Boolean is
     (Path'Length > 0
      and then (Path (Path'First) in '/' | '\'
                or else (Path'Length >= 2
                         and then Path (Path'First + 1) = ':')));

   function Resolve (Base, Path : String) return String is
     (if Is_Absolute (Path) or else Base = "" then Path
      else Base & "/" & Path);

   function Region_Holder (Value : Ks_Flow_Value)
                           return AMV.Shapes.Region_Holders.Holder is
     (if Value.Has_Value
      then AMV.Shapes.Region_Holders.To_Holder
             (AMV.Shapes.Ks_Region'Class (Value.As_Shape))
      else AMV.Shapes.Region_Holders.Empty_Holder);

   procedure Require_Region (Kind, Name : String; Value : Ks_Flow_Value) is
   begin
      if Value.As_Shape not in AMV.Shapes.Ks_Region'Class then
         raise Ks_Flow_Exception with
           Kind & " parameter " & Name & ": a region is needed";
      end if;
   end Require_Region;

   procedure Unknown (Kind, What, Name : String) with No_Return;
   procedure Unknown (Kind, What, Name : String) is
   begin
      raise Ks_Flow_Exception with
        Kind & " has no " & What & " """ & Name & """";
   end Unknown;

   function Real_If (Has : Boolean; X : Real) return Ks_Flow_Value is
     (if Has then From_Real (X) else No_Value);

   ---------------------------------------------------------------------
   --  ShapeMatch
   ---------------------------------------------------------------------

   type Shape_Match_Node is new Ks_Flow_Node with record
      Tool              : AMV.Shape_Match.Ks_Shape_Match_Tool;
      Image_In          : Ks_Flow_Value;
      Train_Image       : Unbounded_String;
      Train_Region      : Ks_Flow_Value;
      Origin_X          : Real := 0.0;
      Origin_Y          : Real := 0.0;
      Origin_Rotation   : Real := 0.0;
      Angle_Low         : Real := 0.0;
      Angle_High        : Real := 0.0;
      Accept_Threshold  : Real := 0.5;
      Contrast          : Real := 10.0;
      Done              : Boolean := False;
      Got               : Boolean := False;
      Pose              : Ks_Flow_Value;
      Found_X, Found_Y  : Real := 0.0;
      Found_Angle       : Real := 0.0;
      Found_Score       : Real := 0.0;
   end record;

   overriding function Kind_Id (Node : Shape_Match_Node) return String;
   overriding function Ports (Node : Shape_Match_Node) return Port_Array;
   overriding function Params (Node : Shape_Match_Node) return Param_Array;
   overriding procedure Set_Param
     (Node : in out Shape_Match_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Shape_Match_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Shape_Match_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Shape_Match_Node);
   overriding procedure Prepare
     (Node : in out Shape_Match_Node; Base_Directory : String);
   overriding function Problem (Node : Shape_Match_Node) return String;
   overriding procedure Execute (Node : in out Shape_Match_Node);
   overriding function Get_Output
     (Node : Shape_Match_Node; Port : String) return Ks_Flow_Value;

   overriding function Kind_Id (Node : Shape_Match_Node) return String is
     ("ShapeMatch");

   overriding function Ports (Node : Shape_Match_Node) return Port_Array is
     [In_Port ("Image", Image_8_Grey_Type),
      Out_Port ("Found", Boolean_Type),
      Out_Port ("Pose", Transform_Type,
                "from the pattern's coordinates to the image's selected space"),
      Out_Port ("X", Real_Type),
      Out_Port ("Y", Real_Type),
      Out_Port ("Angle", Real_Type, "radians"),
      Out_Port ("Score", Real_Type)];

   overriding function Params (Node : Shape_Match_Node) return Param_Array is
     [String_Param_Of ("TrainImage",
                       "the image the pattern is trained on, relative to "
                       & "the flow file"),
      Shape_Param_Of ("TrainRegion",
                      "the region of the train image to train on; none: "
                      & "all of it"),
      Real_Param_Of ("OriginX", -Large, Large, "px",
                     "the pattern's origin in the train image"),
      Real_Param_Of ("OriginY", -Large, Large, "px"),
      Real_Param_Of ("OriginRotation", -Two_Pi, Two_Pi, "rad"),
      Real_Param_Of ("AngleLow", -Two_Pi, Two_Pi, "rad",
                     "the angles searched; AngleLow = AngleHigh: that "
                     & "angle only"),
      Real_Param_Of ("AngleHigh", -Two_Pi, Two_Pi, "rad"),
      Real_Param_Of ("AcceptThreshold", 0.0, 1.0),
      Real_Param_Of ("ContrastThreshold", 0.0, Large, "grey levels/px")];

   overriding procedure Set_Param (Node  : in out Shape_Match_Node;
                                   Name  : String;
                                   Value : Ks_Flow_Value) is
   begin
      if Name = "TrainImage" then
         Node.Train_Image := U (Value.As_String);
      elsif Name = "TrainRegion" then
         Require_Region ("ShapeMatch", Name, Value);
         Node.Train_Region := Value;
      elsif Name = "OriginX" then
         Node.Origin_X := Value.As_Real;
      elsif Name = "OriginY" then
         Node.Origin_Y := Value.As_Real;
      elsif Name = "OriginRotation" then
         Node.Origin_Rotation := Value.As_Real;
      elsif Name = "AngleLow" then
         Node.Angle_Low := Value.As_Real;
      elsif Name = "AngleHigh" then
         Node.Angle_High := Value.As_Real;
      elsif Name = "AcceptThreshold" then
         Node.Accept_Threshold := Value.As_Real;
      elsif Name = "ContrastThreshold" then
         Node.Contrast := Value.As_Real;
      else
         Unknown ("ShapeMatch", "parameter", Name);
      end if;
   end Set_Param;

   overriding function Get_Param (Node : Shape_Match_Node; Name : String)
                                  return Ks_Flow_Value is
   begin
      if Name = "TrainImage" then
         return From_String (To_String (Node.Train_Image));
      elsif Name = "TrainRegion" then
         return Node.Train_Region;
      elsif Name = "OriginX" then
         return From_Real (Node.Origin_X);
      elsif Name = "OriginY" then
         return From_Real (Node.Origin_Y);
      elsif Name = "OriginRotation" then
         return From_Real (Node.Origin_Rotation);
      elsif Name = "AngleLow" then
         return From_Real (Node.Angle_Low);
      elsif Name = "AngleHigh" then
         return From_Real (Node.Angle_High);
      elsif Name = "AcceptThreshold" then
         return From_Real (Node.Accept_Threshold);
      elsif Name = "ContrastThreshold" then
         return From_Real (Node.Contrast);
      end if;
      Unknown ("ShapeMatch", "parameter", Name);
   end Get_Param;

   overriding procedure Set_Input (Node  : in out Shape_Match_Node;
                                   Port  : String;
                                   Value : Ks_Flow_Value) is
   begin
      if Port /= "Image" then
         Unknown ("ShapeMatch", "input", Port);
      end if;
      Node.Image_In := Value;
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Shape_Match_Node) is
   begin
      Node.Image_In := No_Value;
      Node.Done := False;
      Node.Got := False;
      Node.Pose := No_Value;
   end Clear_Inputs;

   overriding procedure Prepare (Node           : in out Shape_Match_Node;
                                 Base_Directory : String)
   is
      Path  : constant String := To_String (Node.Train_Image);
      Image : AMV.Images.Ks_Image_8_Grey;
   begin
      if Path = "" then
         return;
      end if;
      declare
         Full : constant String := Resolve (Base_Directory, Path);
      begin
         Image := AMV.Image_File.Read_Image_8_Grey (Full);
      exception
         when E : others =>
            raise Ks_Flow_Exception with
              "ShapeMatch: cannot read the train image " & Full & ": "
              & Ada.Exceptions.Exception_Message (E);
      end;
      begin
         Node.Tool.Pattern.Set_Train_Image (Image);
         Node.Tool.Pattern.Set_Train_Region
           (Region_Holder (Node.Train_Region));
         Node.Tool.Pattern.Set_Origin
           (AMV.Transforms.Create_Rigid
              (Node.Origin_Rotation, Node.Origin_X, Node.Origin_Y));
         Node.Tool.Pattern.Train;
      exception
         when E : others =>
            raise Ks_Flow_Exception with
              "ShapeMatch: cannot train the pattern: "
              & Ada.Exceptions.Exception_Message (E);
      end;
   end Prepare;

   overriding function Problem (Node : Shape_Match_Node) return String is
     (if Length (Node.Train_Image) = 0 then "no train image (TrainImage)"
      elsif not Node.Tool.Pattern.Trained then "the pattern is not trained"
      else "");

   overriding procedure Execute (Node : in out Shape_Match_Node) is
      use AMV.Shape_Match;
   begin
      Node.Done := True;
      Node.Got := False;
      Node.Pose := No_Value;
      if not Node.Tool.Pattern.Trained then
         Set_Result (Node, AMV.Tools.Error, "the pattern is not trained");
         return;
      end if;
      Node.Tool.Input_Image := Node.Image_In.As_Image;
      Node.Tool.Run_Params.Accept_Threshold := Node.Accept_Threshold;
      Node.Tool.Run_Params.Contrast_Threshold := Node.Contrast;
      if Node.Angle_Low < Node.Angle_High then
         Node.Tool.Run_Params.Zone_Angle.Configuration := Code (Low_High);
         Node.Tool.Run_Params.Zone_Angle.Low := Node.Angle_Low;
         Node.Tool.Run_Params.Zone_Angle.High := Node.Angle_High;
      else
         Node.Tool.Run_Params.Zone_Angle.Configuration := Code (Nominal);
         Node.Tool.Run_Params.Zone_Angle.Nominal := Node.Angle_Low;
      end if;
      Node.Tool.Run;
      Take_Status (Node, Node.Tool.Run_Status);
      if Result (Node) = AMV.Tools.Error then
         return;
      elsif Node.Tool.Results.Count = 0 then
         Set_Result (Node, AMV.Tools.Reject, "the pattern was not found");
         return;
      end if;
      declare
         Best : constant Ks_Shape_Match_Result := Node.Tool.Results.Item (0);
      begin
         Node.Got := True;
         Node.Pose := From_Transform (Get_Pose (Best));
         Node.Found_X := Best.Translation_X;
         Node.Found_Y := Best.Translation_Y;
         Node.Found_Angle := Best.Rotation;
         Node.Found_Score := Best.Score;
      end;
   end Execute;

   overriding function Get_Output (Node : Shape_Match_Node; Port : String)
                                   return Ks_Flow_Value is
   begin
      if Port = "Found" then
         return (if Node.Done then From_Boolean (Node.Got) else No_Value);
      elsif Port = "Pose" then
         return Node.Pose;
      elsif Port = "X" then
         return Real_If (Node.Got, Node.Found_X);
      elsif Port = "Y" then
         return Real_If (Node.Got, Node.Found_Y);
      elsif Port = "Angle" then
         return Real_If (Node.Got, Node.Found_Angle);
      elsif Port = "Score" then
         return Real_If (Node.Got, Node.Found_Score);
      end if;
      Unknown ("ShapeMatch", "output", Port);
   end Get_Output;

   function Create_Shape_Match return Node_Access is
     (new Shape_Match_Node);

   ---------------------------------------------------------------------
   --  Fixture
   ---------------------------------------------------------------------

   type Fixture_Node is new Ks_Flow_Node with record
      Tool         : AMV.Calib_Fix.Ks_Fixture_Tool;
      Image_In     : Ks_Flow_Value;
      Transform_In : Ks_Flow_Value;
      Image_Out    : Ks_Flow_Value;
   end record;

   overriding function Kind_Id (Node : Fixture_Node) return String;
   overriding function Ports (Node : Fixture_Node) return Port_Array;
   overriding function Params (Node : Fixture_Node) return Param_Array;
   overriding procedure Set_Param
     (Node : in out Fixture_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Fixture_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Fixture_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Fixture_Node);
   overriding procedure Execute (Node : in out Fixture_Node);
   overriding function Get_Output
     (Node : Fixture_Node; Port : String) return Ks_Flow_Value;

   overriding function Kind_Id (Node : Fixture_Node) return String is
     ("Fixture");

   overriding function Ports (Node : Fixture_Node) return Port_Array is
     [In_Port ("Image", Image_8_Grey_Type),
      In_Port ("Transform", Transform_Type,
               Help => "from the fixtured space to the image's selected "
                       & "space (a pose)"),
      Out_Port ("Image", Image_8_Grey_Type,
                "the same pixels with the fixtured space selected")];

   overriding function Params (Node : Fixture_Node) return Param_Array is
     [1 => String_Param_Of ("FixturedSpaceName",
                            "the name of the space added (\Fixture)")];

   overriding procedure Set_Param (Node  : in out Fixture_Node;
                                   Name  : String;
                                   Value : Ks_Flow_Value) is
   begin
      if Name /= "FixturedSpaceName" then
         Unknown ("Fixture", "parameter", Name);
      elsif not Valid_Name (Value.As_String) then
         raise Ks_Flow_Exception with
           "Fixture parameter FixturedSpaceName: not a valid name";
      end if;
      Node.Tool.Run_Params.Fixtured_Space_Name := U (Value.As_String);
   end Set_Param;

   overriding function Get_Param (Node : Fixture_Node; Name : String)
                                  return Ks_Flow_Value is
   begin
      if Name /= "FixturedSpaceName" then
         Unknown ("Fixture", "parameter", Name);
      end if;
      return From_String (To_String (Node.Tool.Run_Params.Fixtured_Space_Name));
   end Get_Param;

   overriding procedure Set_Input (Node  : in out Fixture_Node;
                                   Port  : String;
                                   Value : Ks_Flow_Value) is
   begin
      if Port = "Image" then
         Node.Image_In := Value;
      elsif Port = "Transform" then
         Node.Transform_In := Value;
      else
         Unknown ("Fixture", "input", Port);
      end if;
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Fixture_Node) is
   begin
      Node.Image_In := No_Value;
      Node.Transform_In := No_Value;
      Node.Image_Out := No_Value;
   end Clear_Inputs;

   overriding procedure Execute (Node : in out Fixture_Node) is
   begin
      Node.Image_Out := No_Value;
      Node.Tool.Input_Image := Node.Image_In.As_Image;
      Node.Tool.Run_Params.Unfixtured_From_Fixtured_Transform :=
        Node.Transform_In.As_Transform;
      Node.Tool.Run;
      Take_Status (Node, Node.Tool.Run_Status);
      if Result (Node) /= AMV.Tools.Error then
         Node.Image_Out := From_Image (Node.Tool.Output_Image);
      end if;
   end Execute;

   overriding function Get_Output (Node : Fixture_Node; Port : String)
                                   return Ks_Flow_Value is
   begin
      if Port /= "Image" then
         Unknown ("Fixture", "output", Port);
      end if;
      return Node.Image_Out;
   end Get_Output;

   function Create_Fixture return Node_Access is (new Fixture_Node);

   ---------------------------------------------------------------------
   --  Caliper
   ---------------------------------------------------------------------

   type Caliper_Node is new Ks_Flow_Node with record
      Tool       : AMV.Caliper.Ks_Caliper_Tool;
      Image_In   : Ks_Flow_Value;
      Done       : Boolean := False;
      Got        : Boolean := False;
      Width_V    : Real := 0.0;
      Position_V : Real := 0.0;
      X_V, Y_V   : Real := 0.0;
      Score_V    : Real := 0.0;
   end record;

   overriding function Kind_Id (Node : Caliper_Node) return String;
   overriding function Ports (Node : Caliper_Node) return Port_Array;
   overriding function Params (Node : Caliper_Node) return Param_Array;
   overriding procedure Set_Param
     (Node : in out Caliper_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Caliper_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Caliper_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Caliper_Node);
   overriding procedure Execute (Node : in out Caliper_Node);
   overriding function Get_Output
     (Node : Caliper_Node; Port : String) return Ks_Flow_Value;

   Polarities : constant String := "DarkToLight|LightToDark|DontCare";

   function Polarity_Code (Name : String) return AMV.Caliper.Int32 is
     (AMV.Caliper.Code
        (if Name = "DarkToLight" then AMV.Caliper.Dark_To_Light
         elsif Name = "LightToDark" then AMV.Caliper.Light_To_Dark
         else AMV.Caliper.Dont_Care));

   function Polarity_Name (Code : AMV.Caliper.Int32) return String is
     (if Code = AMV.Caliper.Code (AMV.Caliper.Dark_To_Light) then
        "DarkToLight"
      elsif Code = AMV.Caliper.Code (AMV.Caliper.Light_To_Dark) then
        "LightToDark"
      else "DontCare");

   overriding function Kind_Id (Node : Caliper_Node) return String is
     ("Caliper");

   overriding function Ports (Node : Caliper_Node) return Port_Array is
     [In_Port ("Image", Image_8_Grey_Type),
      Out_Port ("Found", Boolean_Type),
      Out_Port ("Width", Real_Type, "between the edges of a pair"),
      Out_Port ("Position", Real_Type, "along the search direction"),
      Out_Port ("X", Real_Type),
      Out_Port ("Y", Real_Type),
      Out_Port ("Score", Real_Type)];

   overriding function Params (Node : Caliper_Node) return Param_Array is
     [Shape_Param_Of ("Region",
                      "a RectangleAffine in the image's selected space; "
                      & "side X is the search direction"),
      Choice_Param_Of ("EdgeMode", "SingleEdge|Pair"),
      Choice_Param_Of ("Edge0Polarity", Polarities),
      Choice_Param_Of ("Edge1Polarity", Polarities),
      Real_Param_Of ("Edge0Position", -Large, Large, "",
                     "Edge1Position - Edge0Position is the expected width"),
      Real_Param_Of ("Edge1Position", -Large, Large),
      Real_Param_Of ("ContrastThreshold", 0.0, Large, "grey levels"),
      Integer_Param_Of ("FilterHalfSize", 1.0, 10_000.0)];

   overriding procedure Set_Param (Node  : in out Caliper_Node;
                                   Name  : String;
                                   Value : Ks_Flow_Value)
   is
      P : AMV.Caliper.Ks_Caliper renames Node.Tool.Run_Params;
   begin
      if Name = "Region" then
         if Value.As_Shape not in AMV.Shapes.Ks_Rectangle_Affine'Class then
            raise Ks_Flow_Exception with
              "Caliper parameter Region: a RectangleAffine is needed";
         end if;
         Node.Tool.Region := AMV.Shapes.Ks_Rectangle_Affine (Value.As_Shape);
      elsif Name = "EdgeMode" then
         P.Edge_Mode := AMV.Caliper.Code
           (if Value.As_String = "Pair" then AMV.Caliper.Pair
            else AMV.Caliper.Single_Edge);
      elsif Name = "Edge0Polarity" then
         P.Edge_0_Polarity := Polarity_Code (Value.As_String);
      elsif Name = "Edge1Polarity" then
         P.Edge_1_Polarity := Polarity_Code (Value.As_String);
      elsif Name = "Edge0Position" then
         P.Edge_0_Position := Value.As_Real;
      elsif Name = "Edge1Position" then
         P.Edge_1_Position := Value.As_Real;
      elsif Name = "ContrastThreshold" then
         P.Contrast_Threshold := Value.As_Real;
      elsif Name = "FilterHalfSize" then
         P.Filter_Half_Size_In_Pixels :=
           AMV.Caliper.Int32 (Value.As_Integer);
      else
         Unknown ("Caliper", "parameter", Name);
      end if;
   end Set_Param;

   overriding function Get_Param (Node : Caliper_Node; Name : String)
                                  return Ks_Flow_Value
   is
      P : AMV.Caliper.Ks_Caliper renames Node.Tool.Run_Params;
   begin
      if Name = "Region" then
         return From_Shape (Node.Tool.Region);
      elsif Name = "EdgeMode" then
         return From_String
           (if P.Edge_Mode = AMV.Caliper.Code (AMV.Caliper.Pair) then "Pair"
            else "SingleEdge");
      elsif Name = "Edge0Polarity" then
         return From_String (Polarity_Name (P.Edge_0_Polarity));
      elsif Name = "Edge1Polarity" then
         return From_String (Polarity_Name (P.Edge_1_Polarity));
      elsif Name = "Edge0Position" then
         return From_Real (P.Edge_0_Position);
      elsif Name = "Edge1Position" then
         return From_Real (P.Edge_1_Position);
      elsif Name = "ContrastThreshold" then
         return From_Real (P.Contrast_Threshold);
      elsif Name = "FilterHalfSize" then
         return From_Integer (Long_Long_Integer (P.Filter_Half_Size_In_Pixels));
      end if;
      Unknown ("Caliper", "parameter", Name);
   end Get_Param;

   overriding procedure Set_Input (Node  : in out Caliper_Node;
                                   Port  : String;
                                   Value : Ks_Flow_Value) is
   begin
      if Port /= "Image" then
         Unknown ("Caliper", "input", Port);
      end if;
      Node.Image_In := Value;
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Caliper_Node) is
   begin
      Node.Image_In := No_Value;
      Node.Done := False;
      Node.Got := False;
   end Clear_Inputs;

   overriding procedure Execute (Node : in out Caliper_Node) is
   begin
      Node.Done := True;
      Node.Got := False;
      Node.Tool.Input_Image := Node.Image_In.As_Image;
      Node.Tool.Run;
      Take_Status (Node, Node.Tool.Run_Status);
      if Result (Node) = AMV.Tools.Error then
         return;
      elsif Node.Tool.Results.Count = 0 then
         Set_Result (Node, AMV.Tools.Reject, "no edge found");
         return;
      end if;
      declare
         Best : constant AMV.Caliper.Ks_Caliper_Result :=
           Node.Tool.Results.Item (0);
      begin
         Node.Got := True;
         Node.Width_V := Best.Width;
         Node.Position_V := Best.Position;
         Node.X_V := Best.Position_X;
         Node.Y_V := Best.Position_Y;
         Node.Score_V := Best.Score;
      end;
   end Execute;

   overriding function Get_Output (Node : Caliper_Node; Port : String)
                                   return Ks_Flow_Value is
   begin
      if Port = "Found" then
         return (if Node.Done then From_Boolean (Node.Got) else No_Value);
      elsif Port = "Width" then
         return Real_If (Node.Got, Node.Width_V);
      elsif Port = "Position" then
         return Real_If (Node.Got, Node.Position_V);
      elsif Port = "X" then
         return Real_If (Node.Got, Node.X_V);
      elsif Port = "Y" then
         return Real_If (Node.Got, Node.Y_V);
      elsif Port = "Score" then
         return Real_If (Node.Got, Node.Score_V);
      end if;
      Unknown ("Caliper", "output", Port);
   end Get_Output;

   function Create_Caliper return Node_Access is (new Caliper_Node);

   ---------------------------------------------------------------------
   --  Blob
   ---------------------------------------------------------------------

   type Blob_Node is new Ks_Flow_Node with record
      Tool      : AMV.Blob.Ks_Blob_Tool;
      Image_In  : Ks_Flow_Value;
      Threshold : Natural := 128;
      Light     : Boolean := True;
      Min_Area  : Real := 10.0;
      Region    : Ks_Flow_Value;
      Done      : Boolean := False;
      Count_V   : Natural := 0;
      Area_V    : Real := 0.0;
      CX, CY    : Real := 0.0;
   end record;

   overriding function Kind_Id (Node : Blob_Node) return String;
   overriding function Ports (Node : Blob_Node) return Port_Array;
   overriding function Params (Node : Blob_Node) return Param_Array;
   overriding procedure Set_Param
     (Node : in out Blob_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Blob_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Blob_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Blob_Node);
   overriding procedure Execute (Node : in out Blob_Node);
   overriding function Get_Output
     (Node : Blob_Node; Port : String) return Ks_Flow_Value;

   overriding function Kind_Id (Node : Blob_Node) return String is ("Blob");

   overriding function Ports (Node : Blob_Node) return Port_Array is
     [In_Port ("Image", Image_8_Grey_Type),
      Out_Port ("Found", Boolean_Type),
      Out_Port ("Count", Integer_Type),
      Out_Port ("Area", Real_Type, "of the largest blob"),
      Out_Port ("CenterX", Real_Type, "of the largest blob"),
      Out_Port ("CenterY", Real_Type)];

   overriding function Params (Node : Blob_Node) return Param_Array is
     [Integer_Param_Of ("Threshold", 0.0, 255.0),
      Choice_Param_Of ("Polarity", "Light|Dark",
                       "Light: blobs are the pixels at or above Threshold"),
      Real_Param_Of ("MinArea", 0.0, 1.0E12, "px"),
      Shape_Param_Of ("Region", "a region; none: the whole image")];

   overriding procedure Set_Param (Node  : in out Blob_Node;
                                   Name  : String;
                                   Value : Ks_Flow_Value) is
   begin
      if Name = "Threshold" then
         Node.Threshold := Natural (Value.As_Integer);
      elsif Name = "Polarity" then
         Node.Light := Value.As_String = "Light";
      elsif Name = "MinArea" then
         Node.Min_Area := Value.As_Real;
      elsif Name = "Region" then
         Require_Region ("Blob", Name, Value);
         Node.Region := Value;
      else
         Unknown ("Blob", "parameter", Name);
      end if;
   end Set_Param;

   overriding function Get_Param (Node : Blob_Node; Name : String)
                                  return Ks_Flow_Value is
   begin
      if Name = "Threshold" then
         return From_Integer (Long_Long_Integer (Node.Threshold));
      elsif Name = "Polarity" then
         return From_String (if Node.Light then "Light" else "Dark");
      elsif Name = "MinArea" then
         return From_Real (Node.Min_Area);
      elsif Name = "Region" then
         return Node.Region;
      end if;
      Unknown ("Blob", "parameter", Name);
   end Get_Param;

   overriding procedure Set_Input (Node  : in out Blob_Node;
                                   Port  : String;
                                   Value : Ks_Flow_Value) is
   begin
      if Port /= "Image" then
         Unknown ("Blob", "input", Port);
      end if;
      Node.Image_In := Value;
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Blob_Node) is
   begin
      Node.Image_In := No_Value;
      Node.Done := False;
      Node.Count_V := 0;
   end Clear_Inputs;

   overriding procedure Execute (Node : in out Blob_Node) is
      use AMV.Blob;
   begin
      Node.Done := True;
      Node.Count_V := 0;
      Set_Segmentation_Hard_Fixed_Threshold
        (Node.Tool.Run_Params.Segmentation_Params, Node.Threshold,
         (if Node.Light then Light_Blobs else Dark_Blobs));
      Node.Tool.Region := Region_Holder (Node.Region);
      Node.Tool.Input_Image := Node.Image_In.As_Image;
      Node.Tool.Run;
      Take_Status (Node, Node.Tool.Run_Status);
      if Result (Node) = AMV.Tools.Error then
         return;
      end if;
      declare
         Features : constant Ks_Blob_Result_Collection'Class :=
           Node.Tool.Results.Get_Blobs (Filtered => False);
      begin
         for I in 0 .. Features.Count - 1 loop
            declare
               Feature : constant Ks_Blob_Result := Features.Item (I);
            begin
               if Feature.Label = Code (Ks_Blob_Label_Constants'(AMV.Blob.Blob))
                 and then Feature.Area >= Node.Min_Area
               then
                  Node.Count_V := Node.Count_V + 1;
                  if Node.Count_V = 1 or else Feature.Area > Node.Area_V then
                     Node.Area_V := Feature.Area;
                     Node.CX := Feature.Center_Of_Mass_X;
                     Node.CY := Feature.Center_Of_Mass_Y;
                  end if;
               end if;
            end;
         end loop;
      end;
   end Execute;

   overriding function Get_Output (Node : Blob_Node; Port : String)
                                   return Ks_Flow_Value
   is
      Got : constant Boolean := Node.Done and then Node.Count_V > 0;
   begin
      if Port = "Found" then
         return (if Node.Done then From_Boolean (Got) else No_Value);
      elsif Port = "Count" then
         return (if Node.Done then From_Integer (Long_Long_Integer (Node.Count_V))
                 else No_Value);
      elsif Port = "Area" then
         return Real_If (Got, Node.Area_V);
      elsif Port = "CenterX" then
         return Real_If (Got, Node.CX);
      elsif Port = "CenterY" then
         return Real_If (Got, Node.CY);
      end if;
      Unknown ("Blob", "output", Port);
   end Get_Output;

   function Create_Blob return Node_Access is (new Blob_Node);

end AMV.Flow.Nodes.Vision;
