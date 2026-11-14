--  Counting cell nuclei in a microscope image with a blob tool, and
--  checking the count against the nuclei someone drew by hand.
--
--     nuclei_count [field]
--
--  It reads one field of view of stained nuclei and its hand-drawn masks
--  (BBBC039; see README.md here for where the images come from):
--  bbbc039_<field>.pgm and bbbc039_<field>_labels.pgm (eval_07 unless a
--  field is named). It prints the count and writes a picture into the
--  current directory:
--
--     nuclei_count_result.bmp   the blobs, outlined, and the nuclei of the
--                               masks that have no blob of their own
--
--  The settings are those of the real-image tests (tests/real_images),
--  which chose them on other fields than the ones they are judged on.

with Ada.Command_Line;
with Ada.Exceptions;
with Ada.Text_IO;

with AMV;
with AMV.Blob;
with AMV.Image_File;
with AMV.Images;
with AMV.Tools;

with Example_Draw;
with Example_Support;

procedure Nuclei_Count is

   use Ada.Text_IO;
   use AMV;
   use AMV.Blob;
   use AMV.Images;
   use type AMV.Tools.Ks_Tool_Result_Constants;

   package Draw renames Example_Draw;

   function Number (Value : Natural) return String is
     (Value'Image (2 .. Value'Image'Last));

   Field : constant String :=
     (if Ada.Command_Line.Argument_Count >= 1
      then Ada.Command_Line.Argument (1) else "eval_07");

   function Brighter (Image : Ks_Image_8_Grey) return Ks_Image_8_Grey;
   --  The image with its grey levels multiplied by 3, for the picture
   --  only: the nuclei are dim (the camera's 12 bits are far from used),
   --  and the tool works on the image as it is.

   function Brighter (Image : Ks_Image_8_Grey) return Ks_Image_8_Grey is
      Result : Ks_Image_8_Grey := Create (Image.Width, Image.Height, 0);
   begin
      for Y in 0 .. Image.Height - 1 loop
         for X in 0 .. Image.Width - 1 loop
            Result.Set_Pixel
              (X, Y,
               Grey_8
                 (Integer'Min (255, 3 * Integer (Image.Get_Pixel (X, Y)))));
         end loop;
      end loop;
      return Result;
   end Brighter;

   Tool : Ks_Blob_Tool;

begin
   --  The 16-bit image comes as 8-bit grey (its file's maxval, 4095,
   --  becomes 255).
   Tool.Input_Image :=
     Example_Support.Real_Image ("bbbc039_" & Field & ".pgm");

   --  Light blobs above the threshold computed from the histogram (the
   --  default); connected sets of fewer than 30 pixels are dropped.
   Tool.Run_Params.Segmentation_Params.Polarity := Code (Light_Blobs);
   Tool.Run_Params.Connectivity_Cleanup := Code (Prune);
   Tool.Run_Params.Connectivity_Min_Pixels := 30;
   Tool.Run;
   if Tool.Run_Status.Result /= AMV.Tools.Accept_Result then
      Put_Line
        ("the blob tool failed: " & AMV.Tools.Message (Tool.Run_Status));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      return;
   end if;

   declare
      --  The masks as a label image: 0 for the background, 1, 2, ... for
      --  the pixels of each nucleus.
      Labels : constant Ks_Image_16_Grey :=
        Ks_Image_16_Grey
          (AMV.Image_File.Read_Image
             (Example_Support.Real_Image_File
                ("bbbc039_" & Field & "_labels.pgm")));
      Blobs  : constant Ks_Blob_Result_Collection'Class :=
        Tool.Results.Get_Blobs;
      Shown  : Draw.Picture :=
        Draw.Create (Brighter (Tool.Input_Image), Scale => 1.5);

      type Tally is record
         Pixels : Natural := 0;
         Sum_X  : Real := 0.0;
         Sum_Y  : Real := 0.0;
         Taken  : Boolean := False;
      end record;
      Nuclei : array (1 .. 65535) of Tally;
      Drawn  : Natural := 0;  --  nuclei in the masks
      Found  : Natural := 0;  --  blobs (holes in blobs are not counted)
      Own    : Natural := 0;  --  nuclei with a blob of their own
   begin
      for Y in 0 .. Labels.Height - 1 loop
         for X in 0 .. Labels.Width - 1 loop
            declare
               L : constant Natural := Natural (Labels.Get_Pixel (X, Y));
            begin
               if L > 0 then
                  Nuclei (L).Pixels := Nuclei (L).Pixels + 1;
                  Nuclei (L).Sum_X := Nuclei (L).Sum_X + Real (X);
                  Nuclei (L).Sum_Y := Nuclei (L).Sum_Y + Real (Y);
               end if;
            end;
         end loop;
      end loop;

      --  A blob is taken for the nucleus whose mask lies under its centre
      --  of mass, and a nucleus can be taken once.
      for I in 0 .. Blobs.Count - 1 loop
         declare
            Blob : constant Ks_Blob_Result := Blobs.Item (I);
            X    : constant Integer := Integer (Blob.Center_Of_Mass_X);
            Y    : constant Integer := Integer (Blob.Center_Of_Mass_Y);
            L    : Natural := 0;
         begin
            --  Label 0 is a hole in a blob.
            if Integer (Blob.Label) /= 0 then
               Found := Found + 1;
               if X in 0 .. Labels.Width - 1
                 and then Y in 0 .. Labels.Height - 1
               then
                  L := Natural (Labels.Get_Pixel (X, Y));
               end if;
               if L > 0 and then not Nuclei (L).Taken then
                  Nuclei (L).Taken := True;
                  Own := Own + 1;
               end if;
               Draw.Outline
                 (Shown, Tool.Results.Get_Boundary (Integer (Blob.ID)),
                  Draw.Green);
            end if;
         end;
      end loop;

      for N of Nuclei loop
         if N.Pixels > 0 then
            Drawn := Drawn + 1;
            if not N.Taken then
               Draw.Cross
                 (Shown, N.Sum_X / Real (N.Pixels),
                  N.Sum_Y / Real (N.Pixels), Draw.Orange, Size => 5.0,
                  Width => 2.0);
            end if;
         end if;
      end loop;

      Put_Line ("field " & Field & ": " & Number (Found) & " blobs");
      Put_Line
        ("the hand-drawn masks: " & Number (Drawn) & " nuclei, "
         & Number (Own) & " with a blob of their own, "
         & Number (Drawn - Own) & " without");
      Put_Line
        ("(nuclei that touch come out as one blob: a blob tool does not"
         & " split them)");

      Draw.Caption
        (Shown, 0, "BLOB TOOL: " & Number (Found) & " BLOBS", Draw.Green);
      Draw.Caption
        (Shown, 1, "DRAWN BY HAND: " & Number (Drawn) & " NUCLEI (+: "
         & Number (Drawn - Own) & " WITHOUT A BLOB OF THEIR OWN)",
         Draw.Orange);
      Draw.Write (Shown, "nuclei_count_result.bmp");
      Put_Line ("wrote nuclei_count_result.bmp");
   end;
exception
   when E : Example_Support.Missing_Image =>
      Put_Line (Ada.Exceptions.Exception_Message (E));
      Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
end Nuclei_Count;
