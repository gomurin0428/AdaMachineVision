pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;
with AMV.Shapes.Kernel_Shapes;
with AMV.Transforms;

package body AMV.Dimensioning is

   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   subtype Ks_Status is AMV.Kernels.Ks_Status;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   ---------------------------------------------------------------------
   --  Kernel values
   ---------------------------------------------------------------------

   function To_Kernel
     (Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return KT.Ks_Transform_2D_Linear;

   function To_Kernel
     (Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return KT.Ks_Transform_2D_Linear
   is
      Result : KT.Ks_Transform_2D_Linear;
   begin
      Transform.Get_Matrix_Elements_Translation
        (Result.A, Result.B, Result.C, Result.D, Result.Translation_X,
         Result.Translation_Y);
      return Result;
   end To_Kernel;

   function Selected_From
     (Image : AMV.Images.Ks_Image'Class;
      Shape : AMV.Shapes.Ks_Shape'Class) return KT.Ks_Transform_2D_Linear
   is (To_Kernel (Image.Get_Transform
                    (AMV.Coordinate_Spaces.Selected_Space_Name,
                     Shape.Selected_Space_Name)));
   --  The transform from the shape's selected space to the image's.

   function Kernel_Line (Line : AMV.Shapes.Ks_Line) return KS.Ks_Line is
     ((X => Line.X, Y => Line.Y, Rotation => Line.Rotation));

   function Kernel_Segment
     (Segment : AMV.Shapes.Ks_Line_Segment) return KS.Ks_Line_Segment
   is ((Start_X => Segment.Start_X, Start_Y => Segment.Start_Y,
        End_X   => Segment.End_X, End_Y => Segment.End_Y));

   function Kernel_Circle (Circle : AMV.Shapes.Ks_Circle) return KS.Ks_Circle
   is (AMV.Shapes.Kernel_Shapes.Kernel_Circle (Circle));

   function Kernel_Ellipse
     (Ellipse : AMV.Shapes.Ks_Ellipse) return KS.Ks_Ellipse
   is (AMV.Shapes.Kernel_Shapes.Kernel_Ellipse (Ellipse));

   ---------------------------------------------------------------------
   --  CogDistancePointPointTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Distance_Point_Point_Tool)
   is
      Result : KD.Ks_Distance_Point_Point_Result;
      Status : Ks_Status;
   begin
      KD.Distance_Point_Point
        (Tool.Start_X, Tool.Start_Y, Tool.End_X, Tool.End_Y, Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Point_Point_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Distance (Tool : Ks_Distance_Point_Point_Tool) return Real is
     (Tool.Outputs.Data.Distance);

   function Angle (Tool : Ks_Distance_Point_Point_Tool) return Real is
     (Tool.Outputs.Data.Angle);

   ---------------------------------------------------------------------
   --  CogAnglePointPointTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Angle_Point_Point_Tool)
   is
      Result : Real;
      Status : Ks_Status;
   begin
      KD.Angle_Point_Point
        (Tool.Start_X, Tool.Start_Y, Tool.End_X, Tool.End_Y, Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Angle_Point_Point_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Angle (Tool : Ks_Angle_Point_Point_Tool) return Real is
     (Tool.Outputs.Data);

   ---------------------------------------------------------------------
   --  CogAngleLineLineTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Angle_Line_Line_Tool)
   is
      Result : Real;
      Status : Ks_Status;
   begin
      KD.Angle_Line_Line
        (Kernel_Line (Tool.Line_A), Kernel_Line (Tool.Line_B),
         Selected_From (Tool.Input_Image, Tool.Line_A),
         Selected_From (Tool.Input_Image, Tool.Line_B), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Angle_Line_Line_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Angle (Tool : Ks_Angle_Line_Line_Tool) return Real is
     (Tool.Outputs.Data);

   ---------------------------------------------------------------------
   --  CogDistancePointLineTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Distance_Point_Line_Tool)
   is
      Result : KD.Ks_Distance_Point_Line_Result;
      Status : Ks_Status;
   begin
      KD.Distance_Point_Line
        (Tool.X, Tool.Y, Kernel_Line (Tool.Line),
         Selected_From (Tool.Input_Image, Tool.Line), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Point_Line_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Distance (Tool : Ks_Distance_Point_Line_Tool) return Real is
     (Tool.Outputs.Data.Distance);

   function Line_X (Tool : Ks_Distance_Point_Line_Tool) return Real is
     (Tool.Outputs.Data.Line_X);

   function Line_Y (Tool : Ks_Distance_Point_Line_Tool) return Real is
     (Tool.Outputs.Data.Line_Y);

   ---------------------------------------------------------------------
   --  CogDistancePointSegmentTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Distance_Point_Segment_Tool)
   is
      Result : KD.Ks_Distance_Point_Segment_Result;
      Status : Ks_Status;
   begin
      KD.Distance_Point_Segment
        (Tool.X, Tool.Y, Kernel_Segment (Tool.Segment),
         Selected_From (Tool.Input_Image, Tool.Segment), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Point_Segment_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Distance (Tool : Ks_Distance_Point_Segment_Tool) return Real is
     (Tool.Outputs.Data.Distance);

   function Segment_X (Tool : Ks_Distance_Point_Segment_Tool) return Real is
     (Tool.Outputs.Data.Segment_X);

   function Segment_Y (Tool : Ks_Distance_Point_Segment_Tool) return Real is
     (Tool.Outputs.Data.Segment_Y);

   ---------------------------------------------------------------------
   --  CogDistancePointCircleTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Distance_Point_Circle_Tool)
   is
      Result : KD.Ks_Distance_Point_Circle_Result;
      Status : Ks_Status;
   begin
      KD.Distance_Point_Circle
        (Tool.X, Tool.Y, Kernel_Circle (Tool.Input_Circle),
         Selected_From (Tool.Input_Image, Tool.Input_Circle), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Point_Circle_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Distance (Tool : Ks_Distance_Point_Circle_Tool) return Real is
     (Tool.Outputs.Data.Distance);

   function Circle_X (Tool : Ks_Distance_Point_Circle_Tool) return Real is
     (Tool.Outputs.Data.Circle_X);

   function Circle_Y (Tool : Ks_Distance_Point_Circle_Tool) return Real is
     (Tool.Outputs.Data.Circle_Y);

   ---------------------------------------------------------------------
   --  CogDistancePointEllipseTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Distance_Point_Ellipse_Tool)
   is
      Result : KD.Ks_Distance_Point_Ellipse_Result;
      Status : Ks_Status;
   begin
      KD.Distance_Point_Ellipse
        (Tool.X, Tool.Y, Kernel_Ellipse (Tool.Ellipse),
         Selected_From (Tool.Input_Image, Tool.Ellipse), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Point_Ellipse_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Distance (Tool : Ks_Distance_Point_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Distance);

   function Ellipse_X (Tool : Ks_Distance_Point_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Ellipse_X);

   function Ellipse_Y (Tool : Ks_Distance_Point_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Ellipse_Y);

   ---------------------------------------------------------------------
   --  CogDistanceSegmentSegmentTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Distance_Segment_Segment_Tool)
   is
      Result : KD.Ks_Distance_Segment_Segment_Result;
      Status : Ks_Status;
   begin
      KD.Distance_Segment_Segment
        (Kernel_Segment (Tool.Segment_A), Kernel_Segment (Tool.Segment_B),
         Selected_From (Tool.Input_Image, Tool.Segment_A),
         Selected_From (Tool.Input_Image, Tool.Segment_B), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Segment_Segment_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Distance (Tool : Ks_Distance_Segment_Segment_Tool) return Real is
     (Tool.Outputs.Data.Distance);

   function Segment_A_X (Tool : Ks_Distance_Segment_Segment_Tool)
     return Real is
     (Tool.Outputs.Data.Segment_A_X);

   function Segment_A_Y (Tool : Ks_Distance_Segment_Segment_Tool)
     return Real is
     (Tool.Outputs.Data.Segment_A_Y);

   function Segment_B_X (Tool : Ks_Distance_Segment_Segment_Tool)
     return Real is
     (Tool.Outputs.Data.Segment_B_X);

   function Segment_B_Y (Tool : Ks_Distance_Segment_Segment_Tool)
     return Real is
     (Tool.Outputs.Data.Segment_B_Y);

   ---------------------------------------------------------------------
   --  CogDistanceSegmentLineTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Distance_Segment_Line_Tool)
   is
      Result : KD.Ks_Distance_Segment_Line_Result;
      Status : Ks_Status;
   begin
      KD.Distance_Segment_Line
        (Kernel_Segment (Tool.Segment), Kernel_Line (Tool.Line),
         Selected_From (Tool.Input_Image, Tool.Segment),
         Selected_From (Tool.Input_Image, Tool.Line), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Segment_Line_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Distance (Tool : Ks_Distance_Segment_Line_Tool) return Real is
     (Tool.Outputs.Data.Distance);

   function Segment_X (Tool : Ks_Distance_Segment_Line_Tool) return Real is
     (Tool.Outputs.Data.Segment_X);

   function Segment_Y (Tool : Ks_Distance_Segment_Line_Tool) return Real is
     (Tool.Outputs.Data.Segment_Y);

   function Line_X (Tool : Ks_Distance_Segment_Line_Tool) return Real is
     (Tool.Outputs.Data.Line_X);

   function Line_Y (Tool : Ks_Distance_Segment_Line_Tool) return Real is
     (Tool.Outputs.Data.Line_Y);

   ---------------------------------------------------------------------
   --  CogDistanceLineCircleTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Distance_Line_Circle_Tool)
   is
      Result : KD.Ks_Distance_Line_Circle_Result;
      Status : Ks_Status;
   begin
      KD.Distance_Line_Circle
        (Kernel_Line (Tool.Line), Kernel_Circle (Tool.Input_Circle),
         Selected_From (Tool.Input_Image, Tool.Line),
         Selected_From (Tool.Input_Image, Tool.Input_Circle), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Line_Circle_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Distance (Tool : Ks_Distance_Line_Circle_Tool) return Real is
     (Tool.Outputs.Data.Distance);

   function Line_X (Tool : Ks_Distance_Line_Circle_Tool) return Real is
     (Tool.Outputs.Data.Line_X);

   function Line_Y (Tool : Ks_Distance_Line_Circle_Tool) return Real is
     (Tool.Outputs.Data.Line_Y);

   function Circle_X (Tool : Ks_Distance_Line_Circle_Tool) return Real is
     (Tool.Outputs.Data.Circle_X);

   function Circle_Y (Tool : Ks_Distance_Line_Circle_Tool) return Real is
     (Tool.Outputs.Data.Circle_Y);

   ---------------------------------------------------------------------
   --  CogDistanceSegmentCircleTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Distance_Segment_Circle_Tool)
   is
      Result : KD.Ks_Distance_Segment_Circle_Result;
      Status : Ks_Status;
   begin
      KD.Distance_Segment_Circle
        (Kernel_Segment (Tool.Segment), Kernel_Circle (Tool.Input_Circle),
         Selected_From (Tool.Input_Image, Tool.Segment),
         Selected_From (Tool.Input_Image, Tool.Input_Circle), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Segment_Circle_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Distance (Tool : Ks_Distance_Segment_Circle_Tool) return Real is
     (Tool.Outputs.Data.Distance);

   function Segment_X (Tool : Ks_Distance_Segment_Circle_Tool) return Real is
     (Tool.Outputs.Data.Segment_X);

   function Segment_Y (Tool : Ks_Distance_Segment_Circle_Tool) return Real is
     (Tool.Outputs.Data.Segment_Y);

   function Circle_X (Tool : Ks_Distance_Segment_Circle_Tool) return Real is
     (Tool.Outputs.Data.Circle_X);

   function Circle_Y (Tool : Ks_Distance_Segment_Circle_Tool) return Real is
     (Tool.Outputs.Data.Circle_Y);

   ---------------------------------------------------------------------
   --  CogDistanceCircleCircleTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Distance_Circle_Circle_Tool)
   is
      Result : KD.Ks_Distance_Circle_Circle_Result;
      Status : Ks_Status;
   begin
      KD.Distance_Circle_Circle
        (Kernel_Circle (Tool.Circle_A), Kernel_Circle (Tool.Circle_B),
         Selected_From (Tool.Input_Image, Tool.Circle_A),
         Selected_From (Tool.Input_Image, Tool.Circle_B), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Circle_Circle_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Distance (Tool : Ks_Distance_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.Distance);

   function Circle_A_X (Tool : Ks_Distance_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.Circle_A_X);

   function Circle_A_Y (Tool : Ks_Distance_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.Circle_A_Y);

   function Circle_B_X (Tool : Ks_Distance_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.Circle_B_X);

   function Circle_B_Y (Tool : Ks_Distance_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.Circle_B_Y);

   ---------------------------------------------------------------------
   --  CogDistanceLineEllipseTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Distance_Line_Ellipse_Tool)
   is
      Result : KD.Ks_Distance_Line_Ellipse_Result;
      Status : Ks_Status;
   begin
      KD.Distance_Line_Ellipse
        (Kernel_Line (Tool.Line), Kernel_Ellipse (Tool.Ellipse),
         Selected_From (Tool.Input_Image, Tool.Line),
         Selected_From (Tool.Input_Image, Tool.Ellipse), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Line_Ellipse_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Distance (Tool : Ks_Distance_Line_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Distance);

   function Line_X (Tool : Ks_Distance_Line_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Line_X);

   function Line_Y (Tool : Ks_Distance_Line_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Line_Y);

   function Ellipse_X (Tool : Ks_Distance_Line_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Ellipse_X);

   function Ellipse_Y (Tool : Ks_Distance_Line_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Ellipse_Y);

   ---------------------------------------------------------------------
   --  CogDistanceSegmentEllipseTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Distance_Segment_Ellipse_Tool)
   is
      Result : KD.Ks_Distance_Segment_Ellipse_Result;
      Status : Ks_Status;
   begin
      KD.Distance_Segment_Ellipse
        (Kernel_Segment (Tool.Segment), Kernel_Ellipse (Tool.Ellipse),
         Selected_From (Tool.Input_Image, Tool.Segment),
         Selected_From (Tool.Input_Image, Tool.Ellipse), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Distance_Segment_Ellipse_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Distance (Tool : Ks_Distance_Segment_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Distance);

   function Segment_X (Tool : Ks_Distance_Segment_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Segment_X);

   function Segment_Y (Tool : Ks_Distance_Segment_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Segment_Y);

   function Ellipse_X (Tool : Ks_Distance_Segment_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Ellipse_X);

   function Ellipse_Y (Tool : Ks_Distance_Segment_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Ellipse_Y);

   ---------------------------------------------------------------------
   --  CogIntersectLineLineTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Intersect_Line_Line_Tool)
   is
      Result : KD.Ks_Intersect_Line_Line_Result;
      Status : Ks_Status;
   begin
      KD.Intersect_Line_Line
        (Kernel_Line (Tool.Line_A), Kernel_Line (Tool.Line_B),
         Selected_From (Tool.Input_Image, Tool.Line_A),
         Selected_From (Tool.Input_Image, Tool.Line_B), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Line_Line_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Intersects (Tool : Ks_Intersect_Line_Line_Tool) return Boolean is
     (Boolean'Val (Tool.Outputs.Data.Intersects));

   function Num_Points (Tool : Ks_Intersect_Line_Line_Tool) return Integer is
     (Integer (Tool.Outputs.Data.Num_Points));

   function X (Tool : Ks_Intersect_Line_Line_Tool) return Real is
     (Tool.Outputs.Data.X);

   function Y (Tool : Ks_Intersect_Line_Line_Tool) return Real is
     (Tool.Outputs.Data.Y);

   function Angle (Tool : Ks_Intersect_Line_Line_Tool) return Real is
     (Tool.Outputs.Data.Angle);

   ---------------------------------------------------------------------
   --  CogIntersectSegmentLineTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Intersect_Segment_Line_Tool)
   is
      Result : KD.Ks_Intersect_Segment_Line_Result;
      Status : Ks_Status;
   begin
      KD.Intersect_Segment_Line
        (Kernel_Segment (Tool.Segment), Kernel_Line (Tool.Line),
         Selected_From (Tool.Input_Image, Tool.Segment),
         Selected_From (Tool.Input_Image, Tool.Line), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Segment_Line_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Intersects (Tool : Ks_Intersect_Segment_Line_Tool)
     return Boolean is
     (Boolean'Val (Tool.Outputs.Data.Intersects));

   function Num_Points (Tool : Ks_Intersect_Segment_Line_Tool)
     return Integer is
     (Integer (Tool.Outputs.Data.Num_Points));

   function X (Tool : Ks_Intersect_Segment_Line_Tool) return Real is
     (Tool.Outputs.Data.X);

   function Y (Tool : Ks_Intersect_Segment_Line_Tool) return Real is
     (Tool.Outputs.Data.Y);

   ---------------------------------------------------------------------
   --  CogIntersectSegmentSegmentTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Intersect_Segment_Segment_Tool)
   is
      Result : KD.Ks_Intersect_Segment_Segment_Result;
      Status : Ks_Status;
   begin
      KD.Intersect_Segment_Segment
        (Kernel_Segment (Tool.Segment_A), Kernel_Segment (Tool.Segment_B),
         Selected_From (Tool.Input_Image, Tool.Segment_A),
         Selected_From (Tool.Input_Image, Tool.Segment_B), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Segment_Segment_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Intersects (Tool : Ks_Intersect_Segment_Segment_Tool)
     return Boolean is
     (Boolean'Val (Tool.Outputs.Data.Intersects));

   function Num_Points (Tool : Ks_Intersect_Segment_Segment_Tool)
     return Integer is
     (Integer (Tool.Outputs.Data.Num_Points));

   function X (Tool : Ks_Intersect_Segment_Segment_Tool) return Real is
     (Tool.Outputs.Data.X);

   function Y (Tool : Ks_Intersect_Segment_Segment_Tool) return Real is
     (Tool.Outputs.Data.Y);

   ---------------------------------------------------------------------
   --  CogIntersectLineCircleTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Intersect_Line_Circle_Tool)
   is
      Result : KD.Ks_Intersect_Line_Circle_Result;
      Status : Ks_Status;
   begin
      KD.Intersect_Line_Circle
        (Kernel_Line (Tool.Line), Kernel_Circle (Tool.Input_Circle),
         Selected_From (Tool.Input_Image, Tool.Line),
         Selected_From (Tool.Input_Image, Tool.Input_Circle), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Line_Circle_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Intersects (Tool : Ks_Intersect_Line_Circle_Tool) return Boolean is
     (Boolean'Val (Tool.Outputs.Data.Intersects));

   function Num_Points (Tool : Ks_Intersect_Line_Circle_Tool) return Integer is
     (Integer (Tool.Outputs.Data.Num_Points));

   function X0 (Tool : Ks_Intersect_Line_Circle_Tool) return Real is
     (Tool.Outputs.Data.X0);

   function Y0 (Tool : Ks_Intersect_Line_Circle_Tool) return Real is
     (Tool.Outputs.Data.Y0);

   function X1 (Tool : Ks_Intersect_Line_Circle_Tool) return Real is
     (Tool.Outputs.Data.X1);

   function Y1 (Tool : Ks_Intersect_Line_Circle_Tool) return Real is
     (Tool.Outputs.Data.Y1);

   ---------------------------------------------------------------------
   --  CogIntersectSegmentCircleTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Intersect_Segment_Circle_Tool)
   is
      Result : KD.Ks_Intersect_Segment_Circle_Result;
      Status : Ks_Status;
   begin
      KD.Intersect_Segment_Circle
        (Kernel_Segment (Tool.Segment), Kernel_Circle (Tool.Input_Circle),
         Selected_From (Tool.Input_Image, Tool.Segment),
         Selected_From (Tool.Input_Image, Tool.Input_Circle), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Segment_Circle_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Intersects (Tool : Ks_Intersect_Segment_Circle_Tool)
     return Boolean is
     (Boolean'Val (Tool.Outputs.Data.Intersects));

   function Num_Points (Tool : Ks_Intersect_Segment_Circle_Tool)
     return Integer is
     (Integer (Tool.Outputs.Data.Num_Points));

   function X0 (Tool : Ks_Intersect_Segment_Circle_Tool) return Real is
     (Tool.Outputs.Data.X0);

   function Y0 (Tool : Ks_Intersect_Segment_Circle_Tool) return Real is
     (Tool.Outputs.Data.Y0);

   function X1 (Tool : Ks_Intersect_Segment_Circle_Tool) return Real is
     (Tool.Outputs.Data.X1);

   function Y1 (Tool : Ks_Intersect_Segment_Circle_Tool) return Real is
     (Tool.Outputs.Data.Y1);

   ---------------------------------------------------------------------
   --  CogIntersectCircleCircleTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Intersect_Circle_Circle_Tool)
   is
      Result : KD.Ks_Intersect_Circle_Circle_Result;
      Status : Ks_Status;
   begin
      KD.Intersect_Circle_Circle
        (Kernel_Circle (Tool.Circle_A), Kernel_Circle (Tool.Circle_B),
         Selected_From (Tool.Input_Image, Tool.Circle_A),
         Selected_From (Tool.Input_Image, Tool.Circle_B), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Circle_Circle_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Intersects (Tool : Ks_Intersect_Circle_Circle_Tool)
     return Boolean is
     (Boolean'Val (Tool.Outputs.Data.Intersects));

   function Num_Points (Tool : Ks_Intersect_Circle_Circle_Tool)
     return Integer is
     (Integer (Tool.Outputs.Data.Num_Points));

   function X0 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.X0);

   function Y0 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.Y0);

   function X1 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.X1);

   function Y1 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.Y1);

   function X2 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.X2);

   function Y2 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.Y2);

   function X3 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.X3);

   function Y3 (Tool : Ks_Intersect_Circle_Circle_Tool) return Real is
     (Tool.Outputs.Data.Y3);

   ---------------------------------------------------------------------
   --  CogIntersectLineEllipseTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Intersect_Line_Ellipse_Tool)
   is
      Result : KD.Ks_Intersect_Line_Ellipse_Result;
      Status : Ks_Status;
   begin
      KD.Intersect_Line_Ellipse
        (Kernel_Line (Tool.Line), Kernel_Ellipse (Tool.Ellipse),
         Selected_From (Tool.Input_Image, Tool.Line),
         Selected_From (Tool.Input_Image, Tool.Ellipse), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Line_Ellipse_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Intersects (Tool : Ks_Intersect_Line_Ellipse_Tool)
     return Boolean is
     (Boolean'Val (Tool.Outputs.Data.Intersects));

   function Num_Points (Tool : Ks_Intersect_Line_Ellipse_Tool)
     return Integer is
     (Integer (Tool.Outputs.Data.Num_Points));

   function X0 (Tool : Ks_Intersect_Line_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.X0);

   function Y0 (Tool : Ks_Intersect_Line_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Y0);

   function X1 (Tool : Ks_Intersect_Line_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.X1);

   function Y1 (Tool : Ks_Intersect_Line_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Y1);

   ---------------------------------------------------------------------
   --  CogIntersectSegmentEllipseTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Intersect_Segment_Ellipse_Tool)
   is
      Result : KD.Ks_Intersect_Segment_Ellipse_Result;
      Status : Ks_Status;
   begin
      KD.Intersect_Segment_Ellipse
        (Kernel_Segment (Tool.Segment), Kernel_Ellipse (Tool.Ellipse),
         Selected_From (Tool.Input_Image, Tool.Segment),
         Selected_From (Tool.Input_Image, Tool.Ellipse), Result, Status);
      Check (Status);
      Tool.Outputs := (Data => Result);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Intersect_Segment_Ellipse_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Intersects (Tool : Ks_Intersect_Segment_Ellipse_Tool)
     return Boolean is
     (Boolean'Val (Tool.Outputs.Data.Intersects));

   function Num_Points (Tool : Ks_Intersect_Segment_Ellipse_Tool)
     return Integer is
     (Integer (Tool.Outputs.Data.Num_Points));

   function X0 (Tool : Ks_Intersect_Segment_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.X0);

   function Y0 (Tool : Ks_Intersect_Segment_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Y0);

   function X1 (Tool : Ks_Intersect_Segment_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.X1);

   function Y1 (Tool : Ks_Intersect_Segment_Ellipse_Tool) return Real is
     (Tool.Outputs.Data.Y1);

end AMV.Dimensioning;
