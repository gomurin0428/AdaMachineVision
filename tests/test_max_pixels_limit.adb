with Ada.Command_Line;
with Ada.Environment_Variables;
with Ada.Text_IO;

with AMV.Kernels;
with AMV.Kernels.Images;

procedure Test_Max_Pixels_Limit is
   package K renames AMV.Kernels;
   package KI renames AMV.Kernels.Images;

   use type K.Int32;
   use type KI.Ks_Image_8_Grey;

   Image  : KI.Ks_Image_8_Grey;
   Status : K.Ks_Status;
begin
   if not Ada.Environment_Variables.Exists ("AMV_BOUNDED_PROBE_RLIMIT_AS")
     or else Ada.Environment_Variables.Value
       ("AMV_BOUNDED_PROBE_RLIMIT_AS") /= "268435456"
   then
      Ada.Text_IO.Put_Line ("FAIL: run through the bounded probe launcher");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   KI.Create (K.Int32'Last, 1, 0, Image, Status);
   if Status.Failure = K.Failure_Out_Of_Memory and then Image = null then
      Ada.Text_IO.Put_Line ("PASS: Out_Of_Memory and null");
   else
      Ada.Text_IO.Put_Line
        ("FAIL: unexpected status " & K.Int32'Image (Status.Failure));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
   end if;
end Test_Max_Pixels_Limit;
