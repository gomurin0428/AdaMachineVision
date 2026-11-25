pragma SPARK_Mode (Off);

with Ada.Numerics;

with AMV.Flow.Values;
with AMV.Image_Processing.IP_One_Image;
with AMV.Image_Processing.Polar_Unwrap;
with AMV.Shapes;

package body AMV.Flow.Nodes.Imaging is

   use AMV.Flow.Values;
   use type AMV.Tools.Ks_Tool_Result_Constants;

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
      Tool     : PU.Ks_Polar_Unwrap_Tool;
      Image_In : Ks_Flow_Value;
      Region   : Ks_Flow_Value;
      Got      : Boolean := False;
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

   overriding function Kind_Id (Node : Polar_Unwrap_Node) return String is
     ("PolarUnwrap");

   overriding function Ports (Node : Polar_Unwrap_Node) return Port_Array is
     [In_Port ("Image", Image_8_Grey_Type),
      Out_Port ("Image", Image_8_Grey_Type,
                "the annulus unwrapped: x along the angle, y along the "
                & "radius")];

   overriding function Params (Node : Polar_Unwrap_Node) return Param_Array is
     [1 => Shape_Param_Of
        ("Region",
         "a CircularAnnulusSection in the image's selected space (after "
         & "a Fixture, the part's)")];

   overriding procedure Set_Param
     (Node : in out Polar_Unwrap_Node; Name : String; Value : Ks_Flow_Value) is
   begin
      if Name /= "Region" then
         Unknown ("PolarUnwrap", "parameter", Name);
      elsif Value.Has_Value
        and then Value.As_Shape
                 not in AMV.Shapes.Ks_Circular_Annulus_Section'Class
      then
         raise Ks_Flow_Exception with
           "PolarUnwrap parameter Region: a CircularAnnulusSection is needed";
      end if;
      Node.Region := Value;
   end Set_Param;

   overriding function Get_Param
     (Node : Polar_Unwrap_Node; Name : String) return Ks_Flow_Value is
   begin
      if Name /= "Region" then
         Unknown ("PolarUnwrap", "parameter", Name);
      end if;
      return Node.Region;
   end Get_Param;

   overriding procedure Set_Input
     (Node : in out Polar_Unwrap_Node; Port : String; Value : Ks_Flow_Value) is
   begin
      if Port /= "Image" then
         Unknown ("PolarUnwrap", "input", Port);
      end if;
      Node.Image_In := Value;
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Polar_Unwrap_Node) is
   begin
      Node.Image_In := No_Value;
      Node.Got := False;
   end Clear_Inputs;

   overriding procedure Execute (Node : in out Polar_Unwrap_Node) is
   begin
      Node.Got := False;
      if not Node.Region.Has_Value then
         raise Ks_Flow_Exception with "set Region: the annulus to unwrap";
      end if;
      Node.Tool.Input_Image := Node.Image_In.As_Image;
      Node.Tool.Region :=
        AMV.Shapes.Ks_Circular_Annulus_Section (Node.Region.As_Shape);
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

   function Create_Polar_Unwrap return Node_Access is
      Node    : constant Node_Access := new Polar_Unwrap_Node;
      Annulus : AMV.Shapes.Ks_Circular_Annulus_Section;
   begin
      --  Somewhere to start from in the editor: an annulus inside any
      --  image of at least 200 x 200 pixels, to be dragged into place.
      Annulus.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (Center_X => 100.0, Center_Y => 100.0, Radius => 50.0,
         Angle_Start => 0.0, Angle_Span => 2.0 * Ada.Numerics.Pi,
         Radial_Scale => 1.8);
      Polar_Unwrap_Node (Node.all).Region := From_Shape (Annulus);
      return Node;
   end Create_Polar_Unwrap;

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
