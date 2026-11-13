pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Images;
with AMV.Kernels.Transforms;
with AMV.Shapes.Kernel_Shapes;
with AMV.Transforms;

package body AMV.Image_Processing.Polar_Unwrap is

   package KP renames AMV.Kernels.Polar_Unwrap;
   package KI renames AMV.Kernels.Images;
   package KT renames AMV.Kernels.Transforms;
   package Kernel_Images renames AMV.Images.Kernel_Images;
   package Kernel_Shapes renames AMV.Shapes.Kernel_Shapes;

   subtype Ks_Status is AMV.Kernels.Ks_Status;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

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

   function Pixel_From_Region
     (Image  : AMV.Images.Ks_Image'Class;
      Region : AMV.Shapes.Ks_Circular_Annulus_Section)
      return KT.Ks_Transform_2D_Linear
   is
     (To_Kernel (Image.Get_Transform (AMV.Coordinate_Spaces.Pixel_Space_Name,
                                      Region.Selected_Space_Name)));

   procedure Get_Input_Point_From_Output_Point
     (Params         : Ks_Polar_Unwrap;
      Input_Image    : AMV.Images.Ks_Image'Class;
      Annular_Region : AMV.Shapes.Ks_Circular_Annulus_Section;
      Output_Point_X : Real;
      Output_Point_Y : Real;
      Input_Point_X  : out Real;
      Input_Point_Y  : out Real)
   is
      Status : Ks_Status;
   begin
      KP.Get_Input_Point_From_Output_Point
        (Kernel_Shapes.Kernel_Circular_Annulus_Section (Annular_Region),
         Pixel_From_Region (Input_Image, Annular_Region),
         To_Kernel (Input_Image.Get_Transform
                      (AMV.Coordinate_Spaces.Selected_Space_Name,
                       Annular_Region.Selected_Space_Name)),
         Params, Output_Point_X, Output_Point_Y, Input_Point_X,
         Input_Point_Y, Status);
      Check (Status);
   end Get_Input_Point_From_Output_Point;

   procedure Get_Output_Point_From_Input_Point
     (Params         : Ks_Polar_Unwrap;
      Input_Image    : AMV.Images.Ks_Image'Class;
      Annular_Region : AMV.Shapes.Ks_Circular_Annulus_Section;
      Input_Point_X  : Real;
      Input_Point_Y  : Real;
      Output_Point_X : out Real;
      Output_Point_Y : out Real;
      Revolution     : Integer := 0)
   is
      Status : Ks_Status;
   begin
      KP.Get_Output_Point_From_Input_Point
        (Kernel_Shapes.Kernel_Circular_Annulus_Section (Annular_Region),
         Pixel_From_Region (Input_Image, Annular_Region),
         To_Kernel (Input_Image.Get_Transform
                      (Annular_Region.Selected_Space_Name,
                       AMV.Coordinate_Spaces.Selected_Space_Name)),
         Params, Input_Point_X, Input_Point_Y, AMV.Kernels.Int32 (Revolution),
         Output_Point_X, Output_Point_Y, Status);
      Check (Status);
   end Get_Output_Point_From_Input_Point;

   overriding procedure Execute (Tool : in out Ks_Polar_Unwrap_Tool) is
      Image  : constant access constant KI.Ks_Image_8_Grey_Data :=
        Kernel_Images.Kernel_Handle (Tool.Input_Image);
      Status : Ks_Status;
   begin
      --  The image first, so that an unallocated one is reported as such
      --  before the region's space is looked up.
      KP.Check_Input_Image (Image, Status);
      Check (Status);
      declare
         Output : KI.Ks_Image_8_Grey;
      begin
         KP.Execute
           (Image, Kernel_Shapes.Kernel_Circular_Annulus_Section (Tool.Region),
            Pixel_From_Region (Tool.Input_Image, Tool.Region),
            Tool.Run_Params, Output, Status);
         Check (Status);
         --  A fresh coordinate space tree: the default state.
         Tool.Output_Image := Kernel_Images.Adopt (Output);
      end;
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Polar_Unwrap_Tool) is
      Unallocated : AMV.Images.Ks_Image_8_Grey;
   begin
      Tool.Output_Image := Unallocated;
   end Reset_Results;

end AMV.Image_Processing.Polar_Unwrap;
