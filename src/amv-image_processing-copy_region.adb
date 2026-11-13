pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Images;
with AMV.Kernels.Transforms;
with AMV.Regions;
with AMV.Regions.Kernel_Regions;
with AMV.Transforms;

package body AMV.Image_Processing.Copy_Region is

   package KC renames AMV.Kernels.Copy_Region;
   package KI renames AMV.Kernels.Images;
   package KT renames AMV.Kernels.Transforms;
   package Kernel_Images renames AMV.Images.Kernel_Images;

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

   procedure Set_Fill_Bounding_Box
     (Params : in out Ks_Copy_Region; Value : Boolean) is
   begin
      Params.Fill_Bounding_Box := Boolean'Pos (Value);
   end Set_Fill_Bounding_Box;

   procedure Set_Fill_Region (Params : in out Ks_Copy_Region; Value : Boolean)
   is
   begin
      Params.Fill_Region := Boolean'Pos (Value);
   end Set_Fill_Region;

   overriding procedure Execute (Tool : in out Ks_Copy_Region_Tool) is
      Image  : constant access constant KI.Ks_Image_8_Grey_Data :=
        Kernel_Images.Kernel_Handle (Tool.Input_Image);
      Status : Ks_Status;
   begin
      --  The image first, so that an unallocated one is reported as such
      --  before the region is rasterised.
      KC.Check_Input_Image (Image, Status);
      Check (Status);
      declare
         Region           : constant AMV.Regions.Pixel_Region :=
           AMV.Regions.Rasterize (Tool.Input_Image, Tool.Region);
         Output           : KI.Ks_Image_8_Grey;
         Output_From_Root : KT.Ks_Transform_2D_Linear;
      begin
         KC.Execute
           (Image, AMV.Regions.Kernel_Regions.Kernel_Handle (Region),
            To_Kernel (Tool.Input_Image.Pixel_From_Root_Transform),
            Tool.Run_Params, Output, Output_From_Root, Status);
         Check (Status);
         Tool.Output_Image :=
           Kernel_Images.Adopt_With_Pixel_From_Root
             (Output, Tool.Input_Image, Output_From_Root);
      end;
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Copy_Region_Tool) is
      Unallocated : AMV.Images.Ks_Image_8_Grey;
   begin
      Tool.Output_Image := Unallocated;
   end Reset_Results;

end AMV.Image_Processing.Copy_Region;
