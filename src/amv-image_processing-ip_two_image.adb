pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Images;

package body AMV.Image_Processing.IP_Two_Image is

   package K2 renames AMV.Kernels.IP_Two_Image;
   package KI renames AMV.Kernels.Images;
   package Kernel_Images renames AMV.Images.Kernel_Images;

   subtype Ks_Status is AMV.Kernels.Ks_Status;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   overriding procedure Execute (Tool : in out Ks_IP_Two_Image_Add_Tool) is
      Output : KI.Ks_Image_8_Grey;
      Status : Ks_Status;
   begin
      K2.Add_Execute
        (Kernel_Images.Kernel_Handle (Tool.Input_Image_A),
         Kernel_Images.Kernel_Handle (Tool.Input_Image_B),
         Tool.Run_Params, Output, Status);
      Check (Status);
      Tool.Output_Image := Kernel_Images.Adopt (Output, Tool.Input_Image_A);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_IP_Two_Image_Add_Tool)
   is
      Unallocated : AMV.Images.Ks_Image_8_Grey;
   begin
      Tool.Output_Image := Unallocated;
   end Reset_Results;

   overriding procedure Execute (Tool : in out Ks_IP_Two_Image_Subtract_Tool)
   is
      Output : KI.Ks_Image_8_Grey;
      Status : Ks_Status;
   begin
      K2.Subtract_Execute
        (Kernel_Images.Kernel_Handle (Tool.Input_Image_A),
         Kernel_Images.Kernel_Handle (Tool.Input_Image_B),
         Tool.Run_Params, Output, Status);
      Check (Status);
      Tool.Output_Image := Kernel_Images.Adopt (Output, Tool.Input_Image_A);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_IP_Two_Image_Subtract_Tool)
   is
      Unallocated : AMV.Images.Ks_Image_8_Grey;
   begin
      Tool.Output_Image := Unallocated;
   end Reset_Results;

   overriding procedure Execute (Tool : in out Ks_IP_Two_Image_Min_Max_Tool)
   is
      Output : KI.Ks_Image_8_Grey;
      Status : Ks_Status;
   begin
      K2.Min_Max_Execute
        (Kernel_Images.Kernel_Handle (Tool.Input_Image_A),
         Kernel_Images.Kernel_Handle (Tool.Input_Image_B),
         Tool.Run_Params, Output, Status);
      Check (Status);
      Tool.Output_Image := Kernel_Images.Adopt (Output, Tool.Input_Image_A);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_IP_Two_Image_Min_Max_Tool)
   is
      Unallocated : AMV.Images.Ks_Image_8_Grey;
   begin
      Tool.Output_Image := Unallocated;
   end Reset_Results;

end AMV.Image_Processing.IP_Two_Image;
