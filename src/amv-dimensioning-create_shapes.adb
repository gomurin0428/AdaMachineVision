pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Kernels.Create_Shapes;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;
with AMV.Shapes.Kernel_Shapes;
with AMV.Transforms;

package body AMV.Dimensioning.Create_Shapes is

   package KC renames AMV.Kernels.Create_Shapes;
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

   --  The created shapes, in the image's selected space.

   function New_Circle
     (Data  : KS.Ks_Circle;
      Image : AMV.Images.Ks_Image'Class) return AMV.Shapes.Ks_Circle is
   begin
      return Circle : AMV.Shapes.Ks_Circle do
         Circle.Set_Center_Radius (Data.Center_X, Data.Center_Y, Data.Radius);
         Circle.Set_Selected_Space_Name (Image.Selected_Space_Name);
      end return;
   end New_Circle;

   function New_Ellipse
     (Data  : KS.Ks_Ellipse;
      Image : AMV.Images.Ks_Image'Class) return AMV.Shapes.Ks_Ellipse is
   begin
      return Ellipse : AMV.Shapes.Ks_Ellipse do
         Ellipse.Set_Center_XY_Radius_XY_Rotation
           (Data.Center_X, Data.Center_Y, Data.Radius_X, Data.Radius_Y,
            Data.Rotation);
         Ellipse.Set_Selected_Space_Name (Image.Selected_Space_Name);
      end return;
   end New_Ellipse;

   function New_Line
     (Data  : KS.Ks_Line;
      Image : AMV.Images.Ks_Image'Class) return AMV.Shapes.Ks_Line is
   begin
      return Line : AMV.Shapes.Ks_Line do
         Line.Set_XY_Rotation (Data.X, Data.Y, Data.Rotation);
         Line.Set_Selected_Space_Name (Image.Selected_Space_Name);
      end return;
   end New_Line;

   function New_Segment
     (Data  : KS.Ks_Line_Segment;
      Image : AMV.Images.Ks_Image'Class) return AMV.Shapes.Ks_Line_Segment is
   begin
      return Segment : AMV.Shapes.Ks_Line_Segment do
         Segment.Set_Start_End
           (Data.Start_X, Data.Start_Y, Data.End_X, Data.End_Y);
         Segment.Set_Selected_Space_Name (Image.Selected_Space_Name);
      end return;
   end New_Segment;

   ---------------------------------------------------------------------
   --  CogCreateCircleTool
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_Create_Circle_Tool) is
      Result : KS.Ks_Circle;
      Status : Ks_Status;
   begin
      KC.Create_Circle
        (AMV.Shapes.Kernel_Shapes.Kernel_Circle (Tool.Input_Circle),
         Selected_From (Tool.Input_Image, Tool.Input_Circle), Result,
         Status);
      Check (Status);
      Tool.Outputs := (Circle => New_Circle (Result, Tool.Input_Image));
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Create_Circle_Tool)
   is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Get_Output_Circle
     (Tool : Ks_Create_Circle_Tool) return AMV.Shapes.Ks_Circle is
     (Tool.Outputs.Circle);

   ---------------------------------------------------------------------
   --  CogCreateEllipseTool
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_Create_Ellipse_Tool) is
      Result : KS.Ks_Ellipse;
      Status : Ks_Status;
   begin
      KC.Create_Ellipse
        (AMV.Shapes.Kernel_Shapes.Kernel_Ellipse (Tool.Ellipse),
         Selected_From (Tool.Input_Image, Tool.Ellipse), Result, Status);
      Check (Status);
      Tool.Outputs := (Ellipse => New_Ellipse (Result, Tool.Input_Image));
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Create_Ellipse_Tool)
   is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Get_Output_Ellipse
     (Tool : Ks_Create_Ellipse_Tool) return AMV.Shapes.Ks_Ellipse is
     (Tool.Outputs.Ellipse);

   ---------------------------------------------------------------------
   --  CogCreateLineTool
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_Create_Line_Tool) is
      Result : KS.Ks_Line;
      Status : Ks_Status;
   begin
      KC.Create_Line
        (Kernel_Line (Tool.Line), Selected_From (Tool.Input_Image, Tool.Line),
         Result, Status);
      Check (Status);
      Tool.Outputs := (Line => New_Line (Result, Tool.Input_Image));
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Create_Line_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Get_Output_Line
     (Tool : Ks_Create_Line_Tool) return AMV.Shapes.Ks_Line is
     (Tool.Outputs.Line);

   ---------------------------------------------------------------------
   --  CogCreateSegmentTool
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_Create_Segment_Tool) is
      Result : KS.Ks_Line_Segment;
      Status : Ks_Status;
   begin
      KC.Create_Segment
        (Kernel_Segment (Tool.Segment),
         Selected_From (Tool.Input_Image, Tool.Segment), Result, Status);
      Check (Status);
      Tool.Outputs := (Segment => New_Segment (Result, Tool.Input_Image));
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Create_Segment_Tool)
   is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Get_Output_Segment
     (Tool : Ks_Create_Segment_Tool) return AMV.Shapes.Ks_Line_Segment is
     (Tool.Outputs.Segment);

   ---------------------------------------------------------------------
   --  CogCreateLineBisectPointsTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Create_Line_Bisect_Points_Tool)
   is
      Result : KS.Ks_Line;
      Status : Ks_Status;
   begin
      KC.Create_Line_Bisect_Points
        (Tool.Start_X, Tool.Start_Y, Tool.End_X, Tool.End_Y, Result, Status);
      Check (Status);
      Tool.Outputs := (Line => New_Line (Result, Tool.Input_Image));
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Create_Line_Bisect_Points_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Get_Output_Line
     (Tool : Ks_Create_Line_Bisect_Points_Tool) return AMV.Shapes.Ks_Line is
     (Tool.Outputs.Line);

   ---------------------------------------------------------------------
   --  CogCreateLineParallelTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Create_Line_Parallel_Tool)
   is
      Result : KS.Ks_Line;
      Status : Ks_Status;
   begin
      KC.Create_Line_Parallel
        (Tool.X, Tool.Y, Kernel_Line (Tool.Line),
         Selected_From (Tool.Input_Image, Tool.Line), Result, Status);
      Check (Status);
      Tool.Outputs := (Line => New_Line (Result, Tool.Input_Image));
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Create_Line_Parallel_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Get_Output_Line
     (Tool : Ks_Create_Line_Parallel_Tool) return AMV.Shapes.Ks_Line is
     (Tool.Outputs.Line);

   ---------------------------------------------------------------------
   --  CogCreateLinePerpendicularTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Create_Line_Perpendicular_Tool)
   is
      Result : KS.Ks_Line;
      Status : Ks_Status;
   begin
      KC.Create_Line_Perpendicular
        (Tool.X, Tool.Y, Kernel_Line (Tool.Line),
         Selected_From (Tool.Input_Image, Tool.Line), Result, Status);
      Check (Status);
      Tool.Outputs := (Line => New_Line (Result, Tool.Input_Image));
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Create_Line_Perpendicular_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Get_Output_Line
     (Tool : Ks_Create_Line_Perpendicular_Tool) return AMV.Shapes.Ks_Line is
     (Tool.Outputs.Line);

   ---------------------------------------------------------------------
   --  CogCreateSegmentAvgSegsTool
   ---------------------------------------------------------------------

   overriding procedure Execute
     (Tool : in out Ks_Create_Segment_Avg_Segs_Tool)
   is
      Result : KS.Ks_Line_Segment;
      Status : Ks_Status;
   begin
      KC.Create_Segment_Avg_Segs
        (Kernel_Segment (Tool.Segment_A), Kernel_Segment (Tool.Segment_B),
         Selected_From (Tool.Input_Image, Tool.Segment_A),
         Selected_From (Tool.Input_Image, Tool.Segment_B), Result, Status);
      Check (Status);
      Tool.Outputs := (Segment => New_Segment (Result, Tool.Input_Image));
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Create_Segment_Avg_Segs_Tool) is
   begin
      Tool.Outputs := (others => <>);
   end Reset_Results;

   function Get_Output_Segment
     (Tool : Ks_Create_Segment_Avg_Segs_Tool)
      return AMV.Shapes.Ks_Line_Segment is
     (Tool.Outputs.Segment);

end AMV.Dimensioning.Create_Shapes;
