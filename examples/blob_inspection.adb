--  Blob inspection: find the washers in an image, measure them and check
--  that each has exactly one hole of the right size.
--
--     blob_inspection [image-file]
--
--  Without an argument it inspects a synthetic image (six washers, two of
--  them defective, and a speck of dust) and writes that image to
--  blob_input.pgm in the current directory. With an argument it reads the
--  image from that file (PGM, PPM or BMP; colour is converted to grey).

with Ada.Command_Line;
with Ada.Text_IO;

with AMV;
with AMV.Blob;
with AMV.Image_File;
with AMV.Images;
with AMV.Tools;
with AMV.Transforms;

with Example_Support;

procedure Blob_Inspection is

   use Ada.Text_IO;
   use AMV;
   use AMV.Blob;
   use type Code_Type;
   use type AMV.Tools.Ks_Tool_Result_Constants;

   function Image (Value : Real; Aft : Natural := 1) return String
     renames Example_Support.Image;

   --  The washers: an outer radius of 22 pixels and a hole of radius 8,
   --  so a hole area of about 200 square pixels.

   Outer_Radius  : constant := 22.0;
   Hole_Radius   : constant := 8.0;
   Min_Hole_Area : constant := 150.0;
   Max_Hole_Area : constant := 250.0;

   function Synthetic_Image return AMV.Images.Ks_Image_8_Grey;

   function Synthetic_Image return AMV.Images.Ks_Image_8_Grey is
      Image : AMV.Images.Ks_Image_8_Grey :=
        AMV.Images.Create (Width => 320, Height => 200, Value => 30);

      procedure Disc (X, Y, Outer, Hole : Real);
      --  A light disc of radius Outer centred on (X, Y), with a hole of
      --  radius Hole (none when Hole is 0).

      procedure Disc (X, Y, Outer, Hole : Real) is
         function Inside (U, V : Real) return Boolean is
           (U * U + V * V <= Outer * Outer
            and then (Hole = 0.0 or else U * U + V * V > Hole * Hole));
      begin
         Example_Support.Paint
           (Image, Inside'Access,
            AMV.Transforms.Create_Rigid (0.0, X, Y), Value => 210);
      end Disc;

   begin
      Disc (60.0, 55.0, Outer_Radius, Hole_Radius);
      Disc (160.0, 55.0, Outer_Radius, Hole_Radius);
      Disc (260.0, 55.0, Outer_Radius, Hole_Radius);
      Disc (60.0, 145.0, Outer_Radius, Hole_Radius);
      Disc (160.0, 145.0, Outer_Radius, 4.5);    --  hole too small
      Disc (260.0, 145.0, Outer_Radius, 0.0);    --  no hole
      Disc (112.0, 100.0, 2.0, 0.0);             --  dust
      return Image;
   end Synthetic_Image;

   Input : AMV.Images.Ks_Image_8_Grey;
   Tool  : Ks_Blob_Tool;
   Good  : Natural := 0;
   Bad   : Natural := 0;

begin
   if Ada.Command_Line.Argument_Count >= 1 then
      Input :=
        AMV.Image_File.Read_Image_8_Grey (Ada.Command_Line.Argument (1));
   else
      Input := Synthetic_Image;
      AMV.Image_File.Write_Image ("blob_input.pgm", Input);
      Put_Line ("wrote the synthetic image to blob_input.pgm");
   end if;

   Tool.Input_Image := Input;

   --  Light parts on a dark background. The threshold is computed from
   --  the histogram (Hard_Dynamic_Threshold, the default).
   Tool.Run_Params.Segmentation_Params.Polarity := Code (Light_Blobs);

   --  Keep the features of 500 to 5000 square pixels (washers, not dust
   --  and not holes), in the order in which they are met row by row.
   Add (Tool.Run_Params.Run_Time_Measures,
        Blob_Measure (Area, Filter, Include_Blobs_In_Range, 500.0, 5000.0));
   Tool.Run_Params.Sort_Enabled := Code (False);

   Tool.Run;
   if Tool.Run_Status.Result /= AMV.Tools.Accept_Result then
      Put_Line ("the blob tool failed: "
                & AMV.Tools.Message (Tool.Run_Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      Washers  : constant Ks_Blob_Result_Collection'Class :=
        Tool.Results.Get_Blobs;
      Features : constant Ks_Blob_Result_Collection'Class :=
        Tool.Results.Get_Blobs (Filtered => False);
   begin
      Put_Line ("found" & Washers.Count'Image & " washers among"
                & Features.Count'Image & " features (washers, holes, dust)"
                & " in " & Image (Tool.Run_Status.Processing_Time, 2)
                & " ms");

      for I in 0 .. Washers.Count - 1 loop
         declare
            Washer    : constant Ks_Blob_Result := Washers.Item (I);
            Holes     : Natural := 0;
            Hole_Area : Real := 0.0;
         begin
            --  The holes are the washer's children: features with Label 0
            --  (Hole) whose parent is the washer.
            for J in 0 .. Features.Count - 1 loop
               declare
                  Feature : constant Ks_Blob_Result := Features.Item (J);
               begin
                  if Feature.Parent_ID = Washer.ID
                    and then Feature.Label = Code (Hole)
                  then
                     Holes := Holes + 1;
                     Hole_Area := Feature.Area;
                  end if;
               end;
            end loop;

            Put ("washer at (" & Image (Washer.Center_Of_Mass_X) & ", "
                 & Image (Washer.Center_Of_Mass_Y) & "): area "
                 & Image (Washer.Area) & ", ");
            if Holes = 1
              and then Hole_Area in Min_Hole_Area .. Max_Hole_Area
            then
               Good := Good + 1;
               Put_Line ("hole area " & Image (Hole_Area) & ": OK");
            elsif Holes = 1 then
               Bad := Bad + 1;
               Put_Line
                 ("hole area " & Image (Hole_Area) & ": NG (hole size)");
            elsif Holes = 0 then
               Bad := Bad + 1;
               Put_Line ("no hole: NG");
            else
               Bad := Bad + 1;
               Put_Line ("several holes: NG");
            end if;
         end;
      end loop;
   end;

   Put_Line ("OK:" & Good'Image & ", NG:" & Bad'Image);
end Blob_Inspection;
