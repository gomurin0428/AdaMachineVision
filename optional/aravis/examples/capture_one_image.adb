with Ada.Command_Line;
with Ada.Text_IO;
with AMV.GigE_Vision;
with AMV.Image_File;
with AMV.Images;

procedure Capture_One_Image is
   Camera : AMV.GigE_Vision.Ks_GigE_Camera;
   File : AMV.Image_File.Ks_Image_File;
   Image : AMV.Images.Ks_Image_8_Grey;
begin
   if Ada.Command_Line.Argument_Count /= 2 then
      Ada.Text_IO.Put_Line
        (Ada.Text_IO.Standard_Error,
         "Usage: capture_one_image DEVICE_ID OUTPUT.pgm");
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   Camera.Open (Ada.Command_Line.Argument (1));
   Camera.Start;
   Image := Camera.Grab (2_000);
   Camera.Stop;

   File.Open (Ada.Command_Line.Argument (2), AMV.Image_File.Write);
   begin
      File.Append (Image);
      File.Close;
   exception
      when others =>
         File.Close;
         Camera.Close;
         raise;
   end;
   Camera.Close;
   Ada.Text_IO.Put_Line ("Captured one Mono8 image to " &
                         Ada.Command_Line.Argument (2));
end Capture_One_Image;
