with Ada.Directories;
with Ada.Environment_Variables;
with Ada.Text_IO;

with AMV.Image_File;

package body Example_Support is

   use AMV.Images;

   Samples : constant := 4;

   procedure Paint
     (Image  : in out AMV.Images.Ks_Image_8_Grey;
      Inside : not null access function (U, V : Real) return Boolean;
      Pose   : AMV.Transforms.Ks_Transform_2D_Linear;
      Value  : AMV.Images.Grey_8)
   is
      Part_From_Pixel : constant AMV.Transforms.Ks_Transform_2D_Linear :=
        Pose.Invert;
      Step            : constant Real := 1.0 / Real (Samples);
      U, V            : Real;
      Hits            : Natural;
      Old             : Real;
   begin
      for Y in 0 .. Image.Height - 1 loop
         for X in 0 .. Image.Width - 1 loop
            Hits := 0;
            for J in 0 .. Samples - 1 loop
               for I in 0 .. Samples - 1 loop
                  Part_From_Pixel.Map_Point
                    (Real (X) - 0.5 + (Real (I) + 0.5) * Step,
                     Real (Y) - 0.5 + (Real (J) + 0.5) * Step, U, V);
                  if Inside (U, V) then
                     Hits := Hits + 1;
                  end if;
               end loop;
            end loop;
            if Hits > 0 then
               Old := Real (Image.Get_Pixel (X, Y));
               Image.Set_Pixel
                 (X, Y,
                  Grey_8
                    (Old + (Real (Value) - Old) * Real (Hits)
                             / Real (Samples * Samples)));
            end if;
         end loop;
      end loop;
   end Paint;

   function Real_Image_File (Name : String) return String is
      Directory : constant String :=
        (if Ada.Environment_Variables.Exists ("AMV_REAL_IMAGES")
         then Ada.Environment_Variables.Value ("AMV_REAL_IMAGES")
         else "build/real-images");
      File_Name : constant String := Directory & "/" & Name;
   begin
      if not Ada.Directories.Exists (File_Name) then
         raise Missing_Image with
           File_Name & " is missing: run make fetch-real-images, and set"
           & " AMV_REAL_IMAGES to the directory when it is not"
           & " build/real-images";
      end if;
      return File_Name;
   end Real_Image_File;

   function Real_Image (Name : String) return AMV.Images.Ks_Image_8_Grey is
     (AMV.Image_File.Read_Image_8_Grey (Real_Image_File (Name)));

   package Real_IO is new Ada.Text_IO.Float_IO (Real);

   function Image (Value : Real; Aft : Natural := 1) return String is
      Text : String (1 .. 40);
   begin
      Real_IO.Put (Text, Value, Aft => Aft, Exp => 0);
      for I in Text'Range loop
         if Text (I) /= ' ' then
            return Text (I .. Text'Last);
         end if;
      end loop;
      return Text;
   end Image;

end Example_Support;
