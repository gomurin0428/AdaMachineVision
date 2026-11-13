pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Images.Kernel_Images;
with AMV.Kernels;
with AMV.Kernels.Images;
with AMV.Regions;
with AMV.Regions.Kernel_Regions;

package body AMV.Image_Processing.Pixel_Map is

   package KP renames AMV.Kernels.Pixel_Map;
   package KI renames AMV.Kernels.Images;

   subtype Ks_Status is AMV.Kernels.Ks_Status;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   function Get_Map (Params : Ks_IP_One_Image_Pixel_Map)
      return Pixel_Map_Table is
     (Params.Map);

   procedure Set_Map
     (Params : in out Ks_IP_One_Image_Pixel_Map;
      Map    : Pixel_Map_Table) is
   begin
      Params.Map := Map;
   end Set_Map;

   overriding procedure Execute (Tool : in out Ks_Pixel_Map_Tool) is
      Image  : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Tool.Input_Image);
      Status : Ks_Status;
   begin
      --  The image first, so that an unallocated one is reported as such
      --  before the region is rasterised.
      KP.Check_Input_Image (Image, Status);
      Check (Status);
      declare
         Region : constant AMV.Regions.Pixel_Region :=
           AMV.Regions.Rasterize (Tool.Input_Image, Tool.Region);
         Output : KI.Ks_Image_8_Grey;
      begin
         KP.Execute
           (Image, AMV.Regions.Kernel_Regions.Kernel_Handle (Region),
            Tool.Run_Params, Output, Status);
         Check (Status);
         Tool.Output_Image :=
           AMV.Images.Kernel_Images.Adopt (Output, Tool.Input_Image);
      end;
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Pixel_Map_Tool) is
      Unallocated : AMV.Images.Ks_Image_8_Grey;
   begin
      Tool.Output_Image := Unallocated;
   end Reset_Results;

end AMV.Image_Processing.Pixel_Map;
