pragma SPARK_Mode (Off);

with Ada.Numerics;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Strings.Fixed;

with AMV.Caliper;
with AMV.Caliper.Find_Circle;
with AMV.Dimensioning;
with AMV.Flow.Values;
with AMV.Image_Processing.Histogram;
with AMV.Images;
with AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Transforms;

package body AMV.Flow.Nodes.Measure is

   use AMV.Flow.Values;
   use type AMV.Tools.Ks_Tool_Result_Constants;
   use type AMV.Caliper.Int32;

   Large : constant := 1.0E6;

   procedure Unknown (Kind, What, Name : String) with No_Return;
   procedure Unknown (Kind, What, Name : String) is
   begin
      raise Ks_Flow_Exception with
        Kind & " has no " & What & " """ & Name & """";
   end Unknown;

   function Real_If (Has : Boolean; X : Real) return Ks_Flow_Value is
     (if Has then From_Real (X) else No_Value);

   ---------------------------------------------------------------------
   --  FindCircle
   ---------------------------------------------------------------------

   package FC renames AMV.Caliper.Find_Circle;

   Polarities : constant String := "DarkToLight|LightToDark|DontCare";

   type Find_Circle_Node is new Ks_Flow_Node with record
      Tool     : FC.Ks_Find_Circle_Tool;
      Expected : Ks_Flow_Value;
      Image_In : Ks_Flow_Value;
      Done     : Boolean := False;
      Got      : Boolean := False;
      CX, CY   : Real := 0.0;
      R        : Real := 0.0;
      RMS      : Real := 0.0;
      Used     : Natural := 0;
   end record;

   overriding function Kind_Id (Node : Find_Circle_Node) return String;
   overriding function Ports (Node : Find_Circle_Node) return Port_Array;
   overriding function Params (Node : Find_Circle_Node) return Param_Array;
   overriding procedure Set_Param
     (Node : in out Find_Circle_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Find_Circle_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Find_Circle_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Find_Circle_Node);
   overriding procedure Execute (Node : in out Find_Circle_Node);
   overriding function Get_Output
     (Node : Find_Circle_Node; Port : String) return Ks_Flow_Value;
   overriding procedure Add_Pixel_Marks
     (Node : Find_Circle_Node; Marks : in out Mark_Vectors.Vector);

   overriding function Kind_Id (Node : Find_Circle_Node) return String is
     ("FindCircle");

   overriding function Ports (Node : Find_Circle_Node) return Port_Array is
     [In_Port ("Image", Image_8_Grey_Type),
      Out_Port ("Found", Boolean_Type),
      Out_Port ("Pose", Transform_Type,
                "to the circle's centre in the image's selected space: "
                & "for a Fixture"),
      Out_Port ("CenterX", Real_Type),
      Out_Port ("CenterY", Real_Type),
      Out_Port ("Radius", Real_Type),
      Out_Port ("Diameter", Real_Type),
      Out_Port ("RMSError", Real_Type, "of the edge points about the circle"),
      Out_Port ("PointsUsed", Integer_Type)];

   overriding function Params (Node : Find_Circle_Node) return Param_Array is
     [Shape_Param_Of ("Expected",
                      "a Circle in the image's selected space: where the "
                      & "calipers go, all round"),
      Integer_Param_Of ("NumCalipers", 3.0, 1000.0),
      Real_Param_Of ("SearchLength", 1.0E-3, Large, "",
                     "how far each caliper looks across the circle"),
      Real_Param_Of ("ProjectionLength", 1.0E-3, Large, "",
                     "how wide each caliper is, along the circle"),
      Choice_Param_Of ("SearchDirection", "Inward|Outward"),
      Choice_Param_Of ("Polarity", Polarities,
                       "the edge, going along the search direction"),
      Real_Param_Of ("ContrastThreshold", 0.0, Large, "grey levels"),
      Integer_Param_Of ("NumToIgnore", 0.0, 997.0,
                        "edge points left out of the fit as outliers")];

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

   overriding procedure Set_Param
     (Node : in out Find_Circle_Node; Name : String; Value : Ks_Flow_Value)
   is
      P : FC.Ks_Find_Circle renames Node.Tool.Run_Params;
   begin
      if Name = "Expected" then
         if not Value.Has_Value
           or else Value.As_Shape not in AMV.Shapes.Ks_Circle'Class
         then
            raise Ks_Flow_Exception with
              "FindCircle parameter Expected: a Circle is needed";
         end if;
         Node.Expected := Value;
      elsif Name = "NumCalipers" then
         P.Num_Calipers := Integer (Value.As_Integer);
      elsif Name = "SearchLength" then
         P.Caliper_Search_Length := Value.As_Real;
      elsif Name = "ProjectionLength" then
         P.Caliper_Projection_Length := Value.As_Real;
      elsif Name = "SearchDirection" then
         P.Caliper_Search_Direction :=
           (if Value.As_String = "Outward" then FC.Outward else FC.Inward);
      elsif Name = "Polarity" then
         P.Caliper_Run_Params.Edge_0_Polarity :=
           Polarity_Code (Value.As_String);
      elsif Name = "ContrastThreshold" then
         P.Caliper_Run_Params.Contrast_Threshold := Value.As_Real;
      elsif Name = "NumToIgnore" then
         P.Num_To_Ignore := Integer (Value.As_Integer);
      else
         Unknown ("FindCircle", "parameter", Name);
      end if;
   end Set_Param;

   overriding function Get_Param
     (Node : Find_Circle_Node; Name : String) return Ks_Flow_Value
   is
      P : FC.Ks_Find_Circle renames Node.Tool.Run_Params;
      use type FC.Ks_Find_Circle_Search_Direction_Constants;
   begin
      if Name = "Expected" then
         return Node.Expected;
      elsif Name = "NumCalipers" then
         return From_Integer (Long_Long_Integer (P.Num_Calipers));
      elsif Name = "SearchLength" then
         return From_Real (P.Caliper_Search_Length);
      elsif Name = "ProjectionLength" then
         return From_Real (P.Caliper_Projection_Length);
      elsif Name = "SearchDirection" then
         return From_String
           (if P.Caliper_Search_Direction = FC.Outward then "Outward"
            else "Inward");
      elsif Name = "Polarity" then
         return From_String
           (Polarity_Name (P.Caliper_Run_Params.Edge_0_Polarity));
      elsif Name = "ContrastThreshold" then
         return From_Real (P.Caliper_Run_Params.Contrast_Threshold);
      elsif Name = "NumToIgnore" then
         return From_Integer (Long_Long_Integer (P.Num_To_Ignore));
      end if;
      Unknown ("FindCircle", "parameter", Name);
   end Get_Param;

   overriding procedure Set_Input
     (Node : in out Find_Circle_Node; Port : String; Value : Ks_Flow_Value) is
   begin
      if Port /= "Image" then
         Unknown ("FindCircle", "input", Port);
      end if;
      Node.Image_In := Value;
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Find_Circle_Node) is
   begin
      Node.Image_In := No_Value;
      Node.Done := False;
      Node.Got := False;
   end Clear_Inputs;

   overriding procedure Execute (Node : in out Find_Circle_Node) is
   begin
      Node.Done := True;
      Node.Got := False;
      if not Node.Expected.Has_Value then
         raise Ks_Flow_Exception with "set Expected: the circle to look for";
      end if;
      declare
         C : constant AMV.Shapes.Ks_Circle :=
           AMV.Shapes.Ks_Circle (Node.Expected.As_Shape);
         Arc : AMV.Shapes.Ks_Circular_Arc;
      begin
         Arc.Set_Selected_Space_Name (C.Selected_Space_Name);
         Arc.Set_Center_Radius_Angle_Start_Angle_Span
           (C.Center_X, C.Center_Y, C.Radius, 0.0, 2.0 * Ada.Numerics.Pi);
         Node.Tool.Run_Params.Expected_Circular_Arc := Arc;
      end;
      Node.Tool.Input_Image := Node.Image_In.As_Image;
      Node.Tool.Run;
      if Node.Tool.Run_Status.Result = AMV.Tools.Error
        and then
          (AMV.Tools.Exception_Name (Node.Tool.Run_Status) = "AMV.KS_EXCEPTION"
           or else Ada.Strings.Fixed.Index
                     (AMV.Tools.Message (Node.Tool.Run_Status), "collinear")
                   > 0)
      then
         --  Too few edges for a fit, or edges in a line: no circle found,
         --  not a broken flow (bad parameters, a space the image lacks stay
         --  an Error).
         Set_Result (Node, AMV.Tools.Reject,
                     AMV.Tools.Message (Node.Tool.Run_Status));
         return;
      end if;
      Take_Status (Node, Node.Tool.Run_Status);
      if Result (Node) = AMV.Tools.Error then
         return;  --  the tool's own message, not one about its results
      end if;
      declare
         Found : constant AMV.Shapes.Ks_Circle :=
           Node.Tool.Results.Get_Circle;
      begin
         Node.CX := Found.Center_X;
         Node.CY := Found.Center_Y;
         Node.R := Found.Radius;
         Node.RMS := Node.Tool.Results.RMS_Error;
         Node.Used := Node.Tool.Results.Num_Points_Used;
         Node.Got := True;
      end;
   end Execute;

   overriding function Get_Output
     (Node : Find_Circle_Node; Port : String) return Ks_Flow_Value is
   begin
      if Port = "Found" then
         return (if Node.Done then From_Boolean (Node.Got) else No_Value);
      elsif Port = "Pose" then
         return (if Node.Got
                 then From_Transform
                        (AMV.Transforms.Create_Rigid (0.0, Node.CX, Node.CY))
                 else No_Value);
      elsif Port = "CenterX" then
         return Real_If (Node.Got, Node.CX);
      elsif Port = "CenterY" then
         return Real_If (Node.Got, Node.CY);
      elsif Port = "Radius" then
         return Real_If (Node.Got, Node.R);
      elsif Port = "Diameter" then
         return Real_If (Node.Got, 2.0 * Node.R);
      elsif Port = "RMSError" then
         return Real_If (Node.Got, Node.RMS);
      elsif Port = "PointsUsed" then
         return (if Node.Got then From_Integer (Long_Long_Integer (Node.Used))
                 else No_Value);
      end if;
      Unknown ("FindCircle", "output", Port);
   end Get_Output;

   overriding procedure Add_Pixel_Marks
     (Node : Find_Circle_Node; Marks : in out Mark_Vectors.Vector)
   is
      use Ada.Numerics.Long_Elementary_Functions;
      Steps : constant := 72;
   begin
      if not Node.Got then
         return;
      end if;
      declare
         To_Px : constant AMV.Transforms.Ks_Transform_2D_Linear :=
           Node.Image_In.As_Image.Get_Transform ("#", ".");
         Outline : Mark (Steps);
         Centre  : Mark (1);
         A       : Real;
      begin
         for I in 1 .. Steps loop
            A := 2.0 * Ada.Numerics.Pi * Real (I - 1) / Real (Steps);
            To_Px.Map_Point (Node.CX + Node.R * Cos (A),
                             Node.CY + Node.R * Sin (A),
                             Outline.X (I), Outline.Y (I));
         end loop;
         Marks.Append (Outline);
         Centre.Polygon := False;
         To_Px.Map_Point (Node.CX, Node.CY, Centre.X (1), Centre.Y (1));
         Marks.Append (Centre);
      end;
   end Add_Pixel_Marks;

   function Create_Find_Circle return Node_Access is
      Node   : constant Node_Access := new Find_Circle_Node;
      Circle : AMV.Shapes.Ks_Circle;
   begin
      --  Somewhere to start from in the editor, to be dragged into place.
      Circle.Set_Center_Radius (100.0, 100.0, 50.0);
      Find_Circle_Node (Node.all).Expected := From_Shape (Circle);
      Find_Circle_Node (Node.all).Tool.Run_Params.Num_Calipers := 12;
      return Node;
   end Create_Find_Circle;

   ---------------------------------------------------------------------
   --  Distance
   ---------------------------------------------------------------------

   type Distance_Node is new Ks_Flow_Node with record
      Tool           : AMV.Dimensioning.Ks_Distance_Point_Point_Tool;
      X1, Y1, X2, Y2 : Real := 0.0;
      Got            : Boolean := False;
   end record;

   overriding function Kind_Id (Node : Distance_Node) return String is
     ("Distance");
   overriding function Ports (Node : Distance_Node) return Port_Array is
     [In_Port ("X1", Real_Type), In_Port ("Y1", Real_Type),
      In_Port ("X2", Real_Type), In_Port ("Y2", Real_Type),
      Out_Port ("Distance", Real_Type),
      Out_Port ("Angle", Real_Type,
                "of the segment from point 1 to point 2, radians")];
   overriding function Params (Node : Distance_Node) return Param_Array is
     ([]);
   overriding procedure Set_Param
     (Node : in out Distance_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Distance_Node; Name : String) return Ks_Flow_Value is
     (raise Ks_Flow_Exception with
        "Distance has no parameter """ & Name & """");
   overriding procedure Set_Input
     (Node : in out Distance_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Distance_Node);
   overriding procedure Execute (Node : in out Distance_Node);
   overriding function Get_Output
     (Node : Distance_Node; Port : String) return Ks_Flow_Value;

   overriding procedure Set_Param
     (Node : in out Distance_Node; Name : String; Value : Ks_Flow_Value) is
   begin
      Unknown ("Distance", "parameter", Name);
   end Set_Param;

   overriding procedure Set_Input
     (Node : in out Distance_Node; Port : String; Value : Ks_Flow_Value) is
   begin
      if Port = "X1" then
         Node.X1 := Value.As_Real;
      elsif Port = "Y1" then
         Node.Y1 := Value.As_Real;
      elsif Port = "X2" then
         Node.X2 := Value.As_Real;
      elsif Port = "Y2" then
         Node.Y2 := Value.As_Real;
      else
         Unknown ("Distance", "input", Port);
      end if;
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Distance_Node) is
   begin
      Node.X1 := 0.0;
      Node.Y1 := 0.0;
      Node.X2 := 0.0;
      Node.Y2 := 0.0;
      Node.Got := False;
   end Clear_Inputs;

   overriding procedure Execute (Node : in out Distance_Node) is
   begin
      Node.Got := False;
      Node.Tool.Start_X := Node.X1;
      Node.Tool.Start_Y := Node.Y1;
      Node.Tool.End_X := Node.X2;
      Node.Tool.End_Y := Node.Y2;
      Node.Tool.Run;
      Take_Status (Node, Node.Tool.Run_Status);
      Node.Got := Result (Node) /= AMV.Tools.Error;
   end Execute;

   overriding function Get_Output
     (Node : Distance_Node; Port : String) return Ks_Flow_Value is
   begin
      if Port = "Distance" then
         return Real_If (Node.Got, AMV.Dimensioning.Distance (Node.Tool));
      elsif Port = "Angle" then
         return Real_If (Node.Got, AMV.Dimensioning.Angle (Node.Tool));
      end if;
      Unknown ("Distance", "output", Port);
   end Get_Output;

   function Create_Distance return Node_Access is (new Distance_Node);

   ---------------------------------------------------------------------
   --  Histogram
   ---------------------------------------------------------------------

   package HG renames AMV.Image_Processing.Histogram;

   type Histogram_Node is new Ks_Flow_Node with record
      Tool     : HG.Ks_Histogram_Tool;
      Image_In : Ks_Flow_Value;
      Region   : Ks_Flow_Value;
      Got      : Boolean := False;
   end record;

   overriding function Kind_Id (Node : Histogram_Node) return String is
     ("Histogram");
   overriding function Ports (Node : Histogram_Node) return Port_Array is
     [In_Port ("Image", Image_8_Grey_Type),
      Out_Port ("Mean", Real_Type),
      Out_Port ("StdDev", Real_Type),
      Out_Port ("Minimum", Integer_Type),
      Out_Port ("Maximum", Integer_Type),
      Out_Port ("Median", Integer_Type),
      Out_Port ("Samples", Integer_Type, "the pixels counted"),
      Out_Port ("Threshold", Integer_Type,
                "Otsu's, between the dark and the light samples (samples "
                & "of one grey level: that level)")];
   overriding function Params (Node : Histogram_Node) return Param_Array is
     [1 => Shape_Param_Of ("Region", "a region; none: the whole image")];
   overriding procedure Set_Param
     (Node : in out Histogram_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Histogram_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Histogram_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Histogram_Node);
   overriding procedure Execute (Node : in out Histogram_Node);
   overriding function Get_Output
     (Node : Histogram_Node; Port : String) return Ks_Flow_Value;

   overriding procedure Set_Param
     (Node : in out Histogram_Node; Name : String; Value : Ks_Flow_Value) is
   begin
      if Name /= "Region" then
         Unknown ("Histogram", "parameter", Name);
      elsif Value.Has_Value
        and then Value.As_Shape not in AMV.Shapes.Ks_Region'Class
      then
         raise Ks_Flow_Exception with
           "Histogram parameter Region: a region is needed";
      end if;
      Node.Region := Value;
   end Set_Param;

   overriding function Get_Param
     (Node : Histogram_Node; Name : String) return Ks_Flow_Value is
   begin
      if Name /= "Region" then
         Unknown ("Histogram", "parameter", Name);
      end if;
      return Node.Region;
   end Get_Param;

   overriding procedure Set_Input
     (Node : in out Histogram_Node; Port : String; Value : Ks_Flow_Value) is
   begin
      if Port /= "Image" then
         Unknown ("Histogram", "input", Port);
      end if;
      Node.Image_In := Value;
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Histogram_Node) is
   begin
      Node.Image_In := No_Value;
      Node.Got := False;
   end Clear_Inputs;

   overriding procedure Execute (Node : in out Histogram_Node) is
   begin
      Node.Got := False;
      Node.Tool.Input_Image := Node.Image_In.As_Image;
      Node.Tool.Region :=
        (if Node.Region.Has_Value
         then AMV.Shapes.Region_Holders.To_Holder
                (AMV.Shapes.Ks_Region'Class (Node.Region.As_Shape))
         else AMV.Shapes.Region_Holders.Empty_Holder);
      Node.Tool.Run;
      Take_Status (Node, Node.Tool.Run_Status);
      if Result (Node) = AMV.Tools.Error then
         return;
      elsif HG.Num_Samples (Node.Tool.Result) = 0 then
         Set_Result (Node, AMV.Tools.Reject,
                     "the region covers no pixel of the image");
         return;
      end if;
      Node.Got := True;
   end Execute;

   overriding function Get_Output
     (Node : Histogram_Node; Port : String) return Ks_Flow_Value
   is
      R : HG.Ks_Histogram_Result renames Node.Tool.Result;
      function Whole (N : Natural) return Ks_Flow_Value is
        (if Node.Got then From_Integer (Long_Long_Integer (N)) else No_Value);
   begin
      if not Node.Got then
         if Port in "Mean" | "StdDev" | "Minimum" | "Maximum" | "Median"
                  | "Samples" | "Threshold"
         then
            return No_Value;
         end if;
         Unknown ("Histogram", "output", Port);
      elsif Port = "Mean" then
         return From_Real (HG.Mean (R));
      elsif Port = "StdDev" then
         return From_Real (HG.Standard_Deviation (R));
      elsif Port = "Minimum" then
         return Whole (HG.Minimum (R));
      elsif Port = "Maximum" then
         return Whole (HG.Maximum (R));
      elsif Port = "Median" then
         return Whole (HG.Median (R));
      elsif Port = "Samples" then
         return Whole (HG.Num_Samples (R));
      elsif Port = "Threshold" then
         return Whole (HG.Get_Minimum_WGV_Threshold (R));
      end if;
      Unknown ("Histogram", "output", Port);
   end Get_Output;

   function Create_Histogram return Node_Access is (new Histogram_Node);


end AMV.Flow.Nodes.Measure;
