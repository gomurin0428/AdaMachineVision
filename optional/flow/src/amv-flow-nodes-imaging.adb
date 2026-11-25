pragma SPARK_Mode (Off);

with Ada.Numerics;
with Ada.Numerics.Long_Elementary_Functions;

with AMV.Flow.Values;
with AMV.Image_Processing.IP_One_Image;
with AMV.Image_Processing.Polar_Unwrap;

package body AMV.Flow.Nodes.Imaging is

   use AMV.Flow.Values;
   use type AMV.Tools.Ks_Tool_Result_Constants;

   Degree : constant := Ada.Numerics.Pi / 180.0;

   procedure Unknown (Kind, What, Name : String) with No_Return;
   procedure Unknown (Kind, What, Name : String) is
   begin
      raise Ks_Flow_Exception with
        Kind & " has no " & What & " """ & Name & """";
   end Unknown;

   ---------------------------------------------------------------------
   --  PolarUnwrap
   ---------------------------------------------------------------------

   package PU renames AMV.Image_Processing.Polar_Unwrap;

   type Polar_Unwrap_Node is new Ks_Flow_Node with record
      Tool        : PU.Ks_Polar_Unwrap_Tool;
      Image_In    : Ks_Flow_Value;
      CX, CY, R   : Real := 0.0;
      Inner_Ratio : Real := 0.7;
      Outer_Ratio : Real := 0.95;
      Start_Deg   : Real := 0.0;
      Span_Deg    : Real := 360.0;
      Done        : Boolean := False;
      Got         : Boolean := False;
   end record;

   overriding function Kind_Id (Node : Polar_Unwrap_Node) return String;
   overriding function Ports (Node : Polar_Unwrap_Node) return Port_Array;
   overriding function Params (Node : Polar_Unwrap_Node) return Param_Array;
   overriding procedure Set_Param
     (Node : in out Polar_Unwrap_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Polar_Unwrap_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Polar_Unwrap_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Polar_Unwrap_Node);
   overriding procedure Execute (Node : in out Polar_Unwrap_Node);
   overriding function Get_Output
     (Node : Polar_Unwrap_Node; Port : String) return Ks_Flow_Value;
   overriding procedure Add_Pixel_Marks
     (Node : Polar_Unwrap_Node; Marks : in out Mark_Vectors.Vector);

   overriding function Kind_Id (Node : Polar_Unwrap_Node) return String is
     ("PolarUnwrap");

   overriding function Ports (Node : Polar_Unwrap_Node) return Port_Array is
     [In_Port ("Image", Image_8_Grey_Type),
      In_Port ("CenterX", Real_Type, Help => "pixels"),
      In_Port ("CenterY", Real_Type, Help => "pixels"),
      In_Port ("Radius", Real_Type,
               Help => "pixels; the annulus' radii are fractions of it"),
      Out_Port ("Image", Image_8_Grey_Type,
                "the annulus unwrapped: x along the angle, y outwards")];

   overriding function Params (Node : Polar_Unwrap_Node) return Param_Array is
     [Real_Param_Of ("InnerRatio", 0.0, 100.0, "",
                     "the inner radius, as a fraction of Radius"),
      Real_Param_Of ("OuterRatio", 0.0, 100.0, "",
                     "the outer radius, as a fraction of Radius"),
      Real_Param_Of ("AngleStart", -360.0, 360.0, "deg",
                     "where the annulus starts, clockwise from +x"),
      Real_Param_Of ("AngleSpan", -360.0, 360.0, "deg",
                     "360: all round; less to leave out a part outside "
                     & "the image")];

   overriding procedure Set_Param
     (Node : in out Polar_Unwrap_Node; Name : String; Value : Ks_Flow_Value) is
   begin
      if Name = "InnerRatio" then
         Node.Inner_Ratio := Value.As_Real;
      elsif Name = "OuterRatio" then
         Node.Outer_Ratio := Value.As_Real;
      elsif Name = "AngleStart" then
         Node.Start_Deg := Value.As_Real;
      elsif Name = "AngleSpan" then
         Node.Span_Deg := Value.As_Real;
      else
         Unknown ("PolarUnwrap", "parameter", Name);
      end if;
   end Set_Param;

   overriding function Get_Param
     (Node : Polar_Unwrap_Node; Name : String) return Ks_Flow_Value is
   begin
      if Name = "InnerRatio" then
         return From_Real (Node.Inner_Ratio);
      elsif Name = "OuterRatio" then
         return From_Real (Node.Outer_Ratio);
      elsif Name = "AngleStart" then
         return From_Real (Node.Start_Deg);
      elsif Name = "AngleSpan" then
         return From_Real (Node.Span_Deg);
      end if;
      Unknown ("PolarUnwrap", "parameter", Name);
   end Get_Param;

   overriding procedure Set_Input
     (Node : in out Polar_Unwrap_Node; Port : String; Value : Ks_Flow_Value) is
   begin
      if Port = "Image" then
         Node.Image_In := Value;
      elsif Port = "CenterX" then
         Node.CX := Value.As_Real;
      elsif Port = "CenterY" then
         Node.CY := Value.As_Real;
      elsif Port = "Radius" then
         Node.R := Value.As_Real;
      else
         Unknown ("PolarUnwrap", "input", Port);
      end if;
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Polar_Unwrap_Node) is
   begin
      Node.Image_In := No_Value;
      Node.Done := False;
      Node.Got := False;
   end Clear_Inputs;

   overriding procedure Execute (Node : in out Polar_Unwrap_Node) is
   begin
      Node.Done := True;
      Node.Got := False;
      if Node.R <= 0.0 then
         raise Ks_Flow_Exception with "Radius must be above 0";
      elsif Node.Inner_Ratio <= 0.0
        or else Node.Outer_Ratio <= Node.Inner_Ratio
      then
         raise Ks_Flow_Exception with
           "InnerRatio must be above 0 and OuterRatio above InnerRatio";
      elsif Node.Span_Deg = 0.0 then
         raise Ks_Flow_Exception with "AngleSpan must not be 0";
      end if;
      Node.Tool.Input_Image := Node.Image_In.As_Image;
      Node.Tool.Region.Set_Selected_Space_Name ("#");
      Node.Tool.Region.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (Center_X     => Node.CX,
         Center_Y     => Node.CY,
         Radius       => Node.Inner_Ratio * Node.R,
         Angle_Start  => Node.Start_Deg * Degree,
         Angle_Span   => Node.Span_Deg * Degree,
         Radial_Scale => Node.Outer_Ratio / Node.Inner_Ratio);
      Node.Tool.Run;
      Take_Status (Node, Node.Tool.Run_Status);
      Node.Got := Result (Node) /= AMV.Tools.Error;
   end Execute;

   overriding function Get_Output
     (Node : Polar_Unwrap_Node; Port : String) return Ks_Flow_Value is
   begin
      if Port = "Image" then
         return (if Node.Got then From_Image (Node.Tool.Output_Image)
                 else No_Value);
      end if;
      Unknown ("PolarUnwrap", "output", Port);
   end Get_Output;

   overriding procedure Add_Pixel_Marks
     (Node : Polar_Unwrap_Node; Marks : in out Mark_Vectors.Vector)
   is
      use Ada.Numerics.Long_Elementary_Functions;
      Steps : constant := 90;
      Outline : Mark (2 * (Steps + 1));
      Angle : Real;
   begin
      if not Node.Done or else Node.R <= 0.0 then
         return;
      end if;
      --  The inner arc from the start, then the outer arc back.
      for I in 0 .. Steps loop
         Angle := (Node.Start_Deg
                   + Node.Span_Deg * Real (I) / Real (Steps)) * Degree;
         Outline.X (I + 1) := Node.CX + Node.Inner_Ratio * Node.R * Cos (Angle);
         Outline.Y (I + 1) := Node.CY + Node.Inner_Ratio * Node.R * Sin (Angle);
         Outline.X (2 * (Steps + 1) - I) :=
           Node.CX + Node.Outer_Ratio * Node.R * Cos (Angle);
         Outline.Y (2 * (Steps + 1) - I) :=
           Node.CY + Node.Outer_Ratio * Node.R * Sin (Angle);
      end loop;
      Marks.Append (Outline);
   end Add_Pixel_Marks;

   function Create_Polar_Unwrap return Node_Access is
     (new Polar_Unwrap_Node);

   ---------------------------------------------------------------------
   --  Morphology
   ---------------------------------------------------------------------

   package IP renames AMV.Image_Processing.IP_One_Image;

   subtype Operation_Kind is IP.Ks_IP_One_Image_Morphology_Operation_Constants;

   Operation_Names : constant String :=
     "Erode|Dilate|Open|Close|DilateMinusErode|CloseMinusOriginal|"
     & "OriginalMinusOpen";

   function Name_Of (Operation : Operation_Kind) return String is
     (case Operation is
         when IP.Erode                => "Erode",
         when IP.Dilate               => "Dilate",
         when IP.Open                 => "Open",
         when IP.Close                => "Close",
         when IP.Dilate_Minus_Erode   => "DilateMinusErode",
         when IP.Close_Minus_Original => "CloseMinusOriginal",
         when IP.Original_Minus_Open  => "OriginalMinusOpen");

   type Morphology_Node is new Ks_Flow_Node with record
      Tool      : IP.Ks_IP_One_Image_Tool;
      Image_In  : Ks_Flow_Value;
      Operation : Operation_Kind := IP.Close_Minus_Original;
      Width     : Positive := 15;
      Height    : Positive := 1;
      Got       : Boolean := False;
   end record;

   overriding function Kind_Id (Node : Morphology_Node) return String;
   overriding function Ports (Node : Morphology_Node) return Port_Array;
   overriding function Params (Node : Morphology_Node) return Param_Array;
   overriding procedure Set_Param
     (Node : in out Morphology_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Morphology_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Morphology_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Morphology_Node);
   overriding procedure Execute (Node : in out Morphology_Node);
   overriding function Get_Output
     (Node : Morphology_Node; Port : String) return Ks_Flow_Value;

   overriding function Kind_Id (Node : Morphology_Node) return String is
     ("Morphology");

   overriding function Ports (Node : Morphology_Node) return Port_Array is
     [In_Port ("Image", Image_8_Grey_Type),
      Out_Port ("Image", Image_8_Grey_Type)];

   overriding function Params (Node : Morphology_Node) return Param_Array is
     [Choice_Param_Of
        ("Operation", Operation_Names,
         "CloseMinusOriginal: dark features narrower than the kernel "
         & "become light on black; OriginalMinusOpen: light ones"),
      Integer_Param_Of ("KernelWidth", 1.0, 1001.0, "odd, pixels"),
      Integer_Param_Of ("KernelHeight", 1.0, 1001.0, "odd, pixels")];

   overriding procedure Set_Param
     (Node : in out Morphology_Node; Name : String; Value : Ks_Flow_Value) is
   begin
      if Name = "Operation" then
         for Operation in Operation_Kind loop
            if Name_Of (Operation) = Value.As_String then
               Node.Operation := Operation;
            end if;
         end loop;
      elsif Name = "KernelWidth" then
         Node.Width := Positive (Value.As_Integer);
      elsif Name = "KernelHeight" then
         Node.Height := Positive (Value.As_Integer);
      else
         Unknown ("Morphology", "parameter", Name);
      end if;
   end Set_Param;

   overriding function Get_Param
     (Node : Morphology_Node; Name : String) return Ks_Flow_Value is
   begin
      if Name = "Operation" then
         return From_String (Name_Of (Node.Operation));
      elsif Name = "KernelWidth" then
         return From_Integer (Long_Long_Integer (Node.Width));
      elsif Name = "KernelHeight" then
         return From_Integer (Long_Long_Integer (Node.Height));
      end if;
      Unknown ("Morphology", "parameter", Name);
   end Get_Param;

   overriding procedure Set_Input
     (Node : in out Morphology_Node; Port : String; Value : Ks_Flow_Value) is
   begin
      if Port /= "Image" then
         Unknown ("Morphology", "input", Port);
      end if;
      Node.Image_In := Value;
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Morphology_Node) is
   begin
      Node.Image_In := No_Value;
      Node.Got := False;
   end Clear_Inputs;

   overriding procedure Execute (Node : in out Morphology_Node) is
      Op : IP.Ks_IP_One_Image_Operator :=
        IP.New_Operator (IP.Grey_Morphology_NxM);
   begin
      Node.Got := False;
      Op.Grey_Morphology_NxM.Operation := IP.Code (Node.Operation);
      Op.Grey_Morphology_NxM.Kernel_Width := IP.Int32 (Node.Width);
      Op.Grey_Morphology_NxM.Kernel_Height := IP.Int32 (Node.Height);
      IP.Clear (Node.Tool.Operators);
      IP.Add (Node.Tool.Operators, Op);
      Node.Tool.Input_Image := Node.Image_In.As_Image;
      Node.Tool.Run;
      Take_Status (Node, Node.Tool.Run_Status);
      Node.Got := Result (Node) /= AMV.Tools.Error;
   end Execute;

   overriding function Get_Output
     (Node : Morphology_Node; Port : String) return Ks_Flow_Value is
   begin
      if Port = "Image" then
         return (if Node.Got then From_Image (Node.Tool.Output_Image)
                 else No_Value);
      end if;
      Unknown ("Morphology", "output", Port);
   end Get_Output;

   function Create_Morphology return Node_Access is (new Morphology_Node);


end AMV.Flow.Nodes.Imaging;
