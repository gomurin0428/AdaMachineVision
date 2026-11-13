--  A first look at AMV: an image, a fixture coordinate space, and a point
--  mapped between pixel space and that fixture. Writes quick_look.pgm in
--  the current directory.

with Ada.Text_IO;

with AMV;
with AMV.Image_File;
with AMV.Images;
with AMV.Misc;
with AMV.Transforms;

procedure Quick_Look is
   Image : AMV.Images.Ks_Image_8_Grey :=
     AMV.Images.Create (Width => 64, Height => 48, Value => 0);
   X, Y  : AMV.Real;
begin
   Image.Set_Pixel (X => 10, Y => 20, Value => 255);

   --  A fixture space under the root: its origin is at (5, 3) in the
   --  root and its axes are turned by 30 degrees. Parent_From_New maps
   --  fixture coordinates into the root (the parent).
   Image.Coordinate_Space_Tree.Add_Space
     (Parent_Space_Name => "@",
      New_Space_Name    => "Fixture",
      Parent_From_New   =>
        AMV.Transforms.Create_Rigid
          (Rotation      => AMV.Misc.Deg_To_Rad (30.0),
           Translation_X => 5.0,
           Translation_Y => 3.0));
   Image.Set_Selected_Space_Name ("@\Fixture");

   --  Where is the centre of pixel (10, 20) in the selected space?
   Image.Get_Transform (".", "#").Map_Point (10.0, 20.0, X, Y);
   Ada.Text_IO.Put_Line
     ("pixel (10, 20) is at" & X'Image & "," & Y'Image & " in "
      & Image.Selected_Space_Name);

   AMV.Image_File.Write_Image ("quick_look.pgm", Image);
   Ada.Text_IO.Put_Line ("wrote quick_look.pgm");
end Quick_Look;
