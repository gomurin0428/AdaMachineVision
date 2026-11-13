pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Images;
with AMV.Regions;
with AMV.Regions.Kernel_Regions;

package body AMV.Image_Processing.Sharpness is

   package KS renames AMV.Kernels.Image_Sharpness;
   package KI renames AMV.Kernels.Images;

   subtype Ks_Status is AMV.Kernels.Ks_Status;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   overriding procedure Execute (Tool : in out Ks_Image_Sharpness_Tool) is
      Image  : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Tool.Input_Image);
      Status : Ks_Status;
   begin
      --  The image first, so that an unallocated one is reported as such
      --  before the region is rasterised.
      KS.Check_Input_Image (Image, Status);
      Check (Status);
      declare
         Region : constant AMV.Regions.Pixel_Region :=
           AMV.Regions.Rasterize (Tool.Input_Image, Tool.Region);
      begin
         KS.Execute
           (Image, AMV.Regions.Kernel_Regions.Kernel_Handle (Region),
            Tool.Run_Params, Tool.Score, Status);
         Check (Status);
      end;
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Image_Sharpness_Tool) is
   begin
      Tool.Score := No_Score;
   end Reset_Results;

end AMV.Image_Processing.Sharpness;
