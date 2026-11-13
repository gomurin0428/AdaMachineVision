pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Images;

package body AMV.Image_Processing.Image_Convert is

   package KI renames AMV.Kernels.Images;
   package Kernel_Images renames AMV.Images.Kernel_Images;

   subtype Ks_Status is AMV.Kernels.Ks_Status;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   overriding procedure Execute (Tool : in out Ks_Image_Convert_Tool) is
      Handles : constant Kernel_Images.Any_Image_Handles :=
        Kernel_Images.Kernel_Handles (Tool.Input_Image);
      Output  : KI.Ks_Image_8_Grey;
      Status  : Ks_Status;
   begin
      KC.Execute
        (Handles.Grey_8, Handles.Grey_16, Handles.Red, Handles.Green,
         Handles.Blue, Tool.Run_Params, Output, Status);
      Check (Status);
      --  The kernel succeeded, so the holder holds an image.
      Tool.Output_Image :=
        Kernel_Images.Adopt
          (Output, Tool.Input_Image.Constant_Reference.Element.all);
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Image_Convert_Tool) is
      Unallocated : AMV.Images.Ks_Image_8_Grey;
   begin
      Tool.Output_Image := Unallocated;
   end Reset_Results;

end AMV.Image_Processing.Image_Convert;
