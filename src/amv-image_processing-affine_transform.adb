pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Images;
with AMV.Kernels.Transforms;
with AMV.Shapes.Kernel_Shapes;
with AMV.Transforms;

package body AMV.Image_Processing.Affine_Transform is

   package KA renames AMV.Kernels.Affine_Transform;
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

   procedure Release (Handle : in out KI.Ks_Image_8_Grey);
   --  Frees a handle no image could take over.

   procedure Release (Handle : in out KI.Ks_Image_8_Grey) is
      Status : Ks_Status;
   begin
      KI.Destroy (Handle, Status);
   end Release;

   overriding procedure Execute (Tool : in out Ks_Affine_Transform_Tool) is
      Image  : constant access constant KI.Ks_Image_8_Grey_Data :=
        Kernel_Images.Kernel_Handle (Tool.Input_Image);
      Status : Ks_Status;
   begin
      --  The image first, so that an unallocated one is reported as such
      --  before the region's space is looked up.
      KA.Check_Input_Image (Image, Status);
      Check (Status);
      declare
         Pixel_From_Region : constant KT.Ks_Transform_2D_Linear :=
           To_Kernel (Tool.Input_Image.Get_Transform
                        (AMV.Coordinate_Spaces.Pixel_Space_Name,
                         Tool.Region.Selected_Space_Name));
         Output            : KI.Ks_Image_8_Grey;
         Mask              : KI.Ks_Image_8_Grey;
         Output_From_Root  : KT.Ks_Transform_2D_Linear;
      begin
         KA.Execute
           (Image,
            AMV.Shapes.Kernel_Shapes.Kernel_Rectangle_Affine (Tool.Region),
            Pixel_From_Region,
            To_Kernel (Tool.Input_Image.Pixel_From_Root_Transform),
            Tool.Run_Params, Boolean'Pos (Tool.Create_Output_Image_Mask),
            Output, Mask, Output_From_Root, Status);
         Check (Status);
         --  Each Adopt_With_Pixel_From_Root takes over its handle (and
         --  frees it if it fails); the mask is freed here when the output
         --  cannot be made.
         begin
            Tool.Output_Image :=
              Kernel_Images.Adopt_With_Pixel_From_Root
                (Output, Tool.Input_Image, Output_From_Root);
         exception
            when others =>
               Release (Mask);
               raise;
         end;
         Tool.Output_Image_Mask :=
           Kernel_Images.Adopt_With_Pixel_From_Root
             (Mask, Tool.Input_Image, Output_From_Root);
      end;
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Affine_Transform_Tool)
   is
      Unallocated : AMV.Images.Ks_Image_8_Grey;
   begin
      Tool.Output_Image := Unallocated;
      Tool.Output_Image_Mask := Unallocated;
   end Reset_Results;

end AMV.Image_Processing.Affine_Transform;
