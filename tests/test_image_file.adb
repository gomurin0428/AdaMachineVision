--  Tests for AMV.Image_File: PNM and BMP reading and writing, multi-image
--  files, the Ks_Image_File object, conversions to 8-bit grey, malformed
--  files, the image file tool, and closing files after failures. Files
--  are written to tests/output/.

with Ada.Directories;
with Ada.Exceptions;
with Ada.Streams;            use Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;
with GNAT.OS_Lib;

with AMV;                    use AMV;
with AMV.Image_File;         use AMV.Image_File;
with AMV.Images;             use AMV.Images;
with AMV.Tools;              use AMV.Tools;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Image_File is

   use type Grey_8;
   use type Grey_16;

   package SIO renames Ada.Streams.Stream_IO;

   subtype Big is Long_Long_Integer;

   Output_Dir : constant String := "tests/output/";

   LF : constant Character := ASCII.LF;
   CR : constant Character := ASCII.CR;

   File_Error : constant Ada.Exceptions.Exception_Id :=
     Ks_Image_File_Exception'Identity;
   No_Pixels  : constant Ada.Exceptions.Exception_Id :=
     Ks_Image_No_Pixels_Exception'Identity;
   Range_Error : constant Ada.Exceptions.Exception_Id :=
     Constraint_Error'Identity;

   function Path (Name : String) return String is (Output_Dir & Name);

   --------------------------------------------------------------------
   --  Byte helpers
   --------------------------------------------------------------------

   function To_Bytes (Text : String) return Stream_Element_Array is
   begin
      return Result : Stream_Element_Array (1 .. Text'Length) do
         for I in Text'Range loop
            Result (Stream_Element_Offset (I - Text'First + 1)) :=
              Character'Pos (Text (I));
         end loop;
      end return;
   end To_Bytes;

   function LE (Value : Big; Size : Positive) return Stream_Element_Array is
      Rest : Big := Value mod 2 ** (8 * Size);
   begin
      return Result : Stream_Element_Array (1 .. Stream_Element_Offset (Size))
      do
         for I in Result'Range loop
            Result (I) := Stream_Element (Rest mod 256);
            Rest := Rest / 256;
         end loop;
      end return;
   end LE;

   function LE32 (Value : Big) return Stream_Element_Array is (LE (Value, 4));
   function LE16 (Value : Big) return Stream_Element_Array is (LE (Value, 2));

   function Zeros (Count : Natural) return Stream_Element_Array is
     [1 .. Stream_Element_Offset (Count) => 0];

   procedure Write_File (Name : String; Content : Stream_Element_Array) is
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, Name);
      SIO.Write (File, Content);
      SIO.Close (File);
   end Write_File;

   function Read_File (Name : String) return Stream_Element_Array is
      File : SIO.File_Type;
   begin
      SIO.Open (File, SIO.In_File, Name);
      declare
         Result : Stream_Element_Array
           (1 .. Stream_Element_Offset (SIO.Size (File)));
         Last   : Stream_Element_Offset;
      begin
         SIO.Read (File, Result, Last);
         SIO.Close (File);
         return Result (1 .. Last);
      end;
   end Read_File;

   function File_Size (Name : String) return Big is
     (Big (Ada.Directories.Size (Name)));

   function Starts_With
     (Content : Stream_Element_Array; Prefix : String) return Boolean is
     (Content'Length >= Prefix'Length
      and then Content (Content'First ..
                        Content'First + Prefix'Length - 1)
               = To_Bytes (Prefix));

   function U32_At (Content : Stream_Element_Array; Offset : Natural)
      return Big is
     (Big (Content (Content'First + Stream_Element_Offset (Offset)))
      + 256
        * Big (Content (Content'First + Stream_Element_Offset (Offset + 1)))
      + 65_536
        * Big (Content (Content'First + Stream_Element_Offset (Offset + 2)))
      + 16_777_216
        * Big (Content (Content'First + Stream_Element_Offset (Offset + 3))));

   function U16_At (Content : Stream_Element_Array; Offset : Natural)
      return Big is
     (Big (Content (Content'First + Stream_Element_Offset (Offset)))
      + 256
        * Big (Content (Content'First + Stream_Element_Offset (Offset + 1))));

   --------------------------------------------------------------------
   --  Image helpers
   --------------------------------------------------------------------

   function Grey_Pattern (Width, Height : Positive) return Ks_Image_8_Grey is
   begin
      return Result : Ks_Image_8_Grey := Create (Width, Height) do
         for Y in 0 .. Height - 1 loop
            for X in 0 .. Width - 1 loop
               Result.Set_Pixel (X, Y, Grey_8 ((X * 37 + Y * 11 + 5) mod 256));
            end loop;
         end loop;
      end return;
   end Grey_Pattern;

   function Grey_16_Pattern (Width, Height : Positive)
      return Ks_Image_16_Grey is
   begin
      return Result : Ks_Image_16_Grey := Create (Width, Height) do
         for Y in 0 .. Height - 1 loop
            for X in 0 .. Width - 1 loop
               Result.Set_Pixel
                 (X, Y, Grey_16 ((X * 4099 + Y * 21_011 + 7) mod 65_536));
            end loop;
         end loop;
         Result.Set_Pixel (0, 0, 0);
         Result.Set_Pixel (Width - 1, Height - 1, 65_535);
      end return;
   end Grey_16_Pattern;

   function Colour_Pattern (Width, Height : Positive)
      return Ks_Image_24_Planar_Color is
   begin
      return Result : Ks_Image_24_Planar_Color := Create (Width, Height) do
         for Y in 0 .. Height - 1 loop
            for X in 0 .. Width - 1 loop
               Result.Set_Pixel
                 (X, Y,
                  Red   => Grey_8 ((X * 31 + Y * 7) mod 256),
                  Green => Grey_8 ((X * 3 + Y * 101 + 50) mod 256),
                  Blue  => Grey_8 ((X * X + Y) mod 256));
            end loop;
         end loop;
      end return;
   end Colour_Pattern;

   function Same (A, B : Ks_Image_8_Grey) return Boolean is
     (A.Width = B.Width and then A.Height = B.Height
      and then (for all Y in 0 .. A.Height - 1 =>
                  (for all X in 0 .. A.Width - 1 =>
                     A.Get_Pixel (X, Y) = B.Get_Pixel (X, Y))));

   function Same (A, B : Ks_Image_16_Grey) return Boolean is
     (A.Width = B.Width and then A.Height = B.Height
      and then (for all Y in 0 .. A.Height - 1 =>
                  (for all X in 0 .. A.Width - 1 =>
                     A.Get_Pixel (X, Y) = B.Get_Pixel (X, Y))));

   function Same (A, B : Ks_Image_24_Planar_Color) return Boolean is
     (A.Width = B.Width and then A.Height = B.Height
      and then Same (A.Get_Plane (Red), B.Get_Plane (Red))
      and then Same (A.Get_Plane (Green), B.Get_Plane (Green))
      and then Same (A.Get_Plane (Blue), B.Get_Plane (Blue)));

   function Same_Image (A : Ks_Image'Class; B : Ks_Image'Class)
      return Boolean;
   --  Same type, size and pixels.

   function Same_Image (A : Ks_Image'Class; B : Ks_Image'Class)
      return Boolean is
   begin
      if A in Ks_Image_8_Grey and then B in Ks_Image_8_Grey then
         return Same (Ks_Image_8_Grey (A), Ks_Image_8_Grey (B));
      elsif A in Ks_Image_16_Grey and then B in Ks_Image_16_Grey then
         return Same (Ks_Image_16_Grey (A), Ks_Image_16_Grey (B));
      elsif A in Ks_Image_24_Planar_Color
        and then B in Ks_Image_24_Planar_Color
      then
         return Same (Ks_Image_24_Planar_Color (A),
                      Ks_Image_24_Planar_Color (B));
      else
         return False;
      end if;
   end Same_Image;

   procedure Check_Grey_Row
     (Image       : Ks_Image'Class;
      Y           : Natural;
      Expected    : Stream_Element_Array;
      Description : String);
   --  Image must be 8-bit grey and its row Y must equal Expected.

   procedure Check_Grey_Row
     (Image       : Ks_Image'Class;
      Y           : Natural;
      Expected    : Stream_Element_Array;
      Description : String) is
   begin
      if Image not in Ks_Image_8_Grey then
         Fail (Description & ": not an 8-bit grey image");
         return;
      end if;
      declare
         Grey : Ks_Image_8_Grey renames Ks_Image_8_Grey (Image);
         Good : Boolean := Grey.Width = Expected'Length;
      begin
         if Good then
            for X in 0 .. Grey.Width - 1 loop
               Good := Good
                 and then Natural (Grey.Get_Pixel (X, Y))
                          = Natural (Expected (Expected'First
                                     + Stream_Element_Offset (X)));
            end loop;
         end if;
         Check (Good, Description);
      end;
   end Check_Grey_Row;

   procedure Check_Colour_Pixel
     (Image       : Ks_Image'Class;
      X, Y        : Natural;
      R, G, B     : Grey_8;
      Description : String);

   procedure Check_Colour_Pixel
     (Image       : Ks_Image'Class;
      X, Y        : Natural;
      R, G, B     : Grey_8;
      Description : String) is
   begin
      if Image not in Ks_Image_24_Planar_Color then
         Fail (Description & ": not a colour image");
         return;
      end if;
      declare
         Colour     : Ks_Image_24_Planar_Color renames
           Ks_Image_24_Planar_Color (Image);
         GR, GG, GB : Grey_8;
      begin
         Colour.Get_Pixel (X, Y, GR, GG, GB);
         Check (GR = R and then GG = G and then GB = B,
                Description & ": got" & GR'Image & GG'Image & GB'Image);
      end;
   end Check_Colour_Pixel;

   function Contains (Text, Part : String) return Boolean is
     (for some I in Text'First .. Text'Last - Part'Length + 1 =>
        Text (I .. I + Part'Length - 1) = Part);

   procedure Check_Read_Fails
     (Name        : String;
      Content     : Stream_Element_Array;
      Description : String;
      Reason      : String := "");
   --  Writes Content to tests/output/Name and checks that reading it, both
   --  with Read_Image and with Open in Read mode, raises
   --  Ks_Image_File_Exception with a message that starts with the file
   --  name. The message must not come from the decoder's safety net for
   --  an unexpected Constraint_Error ("malformed image file ("): every
   --  input here must be caught by a check of its own. A non-empty Reason
   --  must appear in the message, which pins the check that rejects it.

   procedure Check_Read_Fails
     (Name        : String;
      Content     : Stream_Element_Array;
      Description : String;
      Reason      : String := "")
   is
      Full : constant String := Path (Name);

      procedure Read_It is
         Image : constant Ks_Image'Class := Read_Image (Full);
      begin
         Check (not Image.Allocated, "unreachable");
      end Read_It;

      procedure Open_It is
         File : Ks_Image_File;
      begin
         File.Open (Full, Read);
      end Open_It;

      procedure Check_Read is new Check_Raises_Exactly (Read_It, File_Error);
      procedure Check_Open is new Check_Raises_Exactly (Open_It, File_Error);
   begin
      Write_File (Full, Content);
      Check_Read (Description & " (Read_Image)");
      Check_Open (Description & " (Open)");
      begin
         Read_It;
      exception
         when E : Ks_Image_File_Exception =>
            declare
               Message : constant String :=
                 Ada.Exceptions.Exception_Message (E);
            begin
               Check (Message'Length > Full'Length + 2
                        and then Message (Message'First ..
                                          Message'First + Full'Length + 1)
                                 = Full & ": ",
                      Description & ": message names the file: " & Message);
               Check (not Contains (Message, ": malformed image file ("),
                      Description & ": rejected by a check of its own: "
                      & Message);
               if Reason /= "" then
                  Check (Contains (Message, Reason),
                         Description & ": the reason is '" & Reason
                         & "': " & Message);
               end if;
            end;
         when others =>
            null;  --  Already reported by Check_Read.
      end;
   end Check_Read_Fails;

   --------------------------------------------------------------------
   --  Tests
   --------------------------------------------------------------------

   procedure Test_PGM_Round_Trip is
      Grey   : constant Ks_Image_8_Grey := Grey_Pattern (7, 5);
      Grey16 : constant Ks_Image_16_Grey := Grey_16_Pattern (4, 3);
      Name   : constant String := Path ("img_grey8.pgm");
      Name16 : constant String := Path ("img_grey16.pgm");
   begin
      Section ("PGM round trip");
      Write_Image (Name, Grey);
      declare
         Content : constant Stream_Element_Array := Read_File (Name);
         Header  : constant String := "P5" & LF & "7 5" & LF & "255" & LF;
      begin
         Check (Starts_With (Content, Header), "8-bit P5 header");
         Check (Content'Length = Header'Length + 35, "8-bit P5 file size");
         Check (Natural (Content (Header'Length + 1))
                  = Natural (Grey.Get_Pixel (0, 0))
                and then Natural (Content (Header'Length + 8))
                  = Natural (Grey.Get_Pixel (0, 1)),
                "8-bit raster in row order");
      end;
      declare
         Back : constant Ks_Image'Class := Read_Image (Name);
      begin
         Check (Back in Ks_Image_8_Grey, "8-bit PGM reads as 8-bit grey");
         Check (Same_Image (Back, Grey), "8-bit PGM pixels");
         Check (Back.Selected_Space_Name = "@", "read image has defaults");
      end;
      Check (Same (Read_Image_8_Grey (Name), Grey), "Read_Image_8_Grey 8-bit");

      Write_Image (Name16, Grey16);
      declare
         Content : constant Stream_Element_Array := Read_File (Name16);
         Header  : constant String := "P5" & LF & "4 3" & LF & "65535" & LF;
         First   : constant Stream_Element_Offset := Header'Length + 1;
         Second  : constant Natural := Natural (Grey16.Get_Pixel (1, 0));
      begin
         Check (Starts_With (Content, Header), "16-bit P5 header");
         Check (Content'Length = Header'Length + 24, "16-bit P5 file size");
         Check (Content (First) = 0 and then Content (First + 1) = 0,
                "first 16-bit sample");
         Check (Natural (Content (First + 2)) = Second / 256
                  and then Natural (Content (First + 3)) = Second mod 256,
                "16-bit samples are big-endian");
         Check (Content (Content'Last) = 255
                  and then Content (Content'Last - 1) = 255,
                "last 16-bit sample is 65535");
      end;
      declare
         Back : constant Ks_Image'Class := Read_Image (Name16);
      begin
         Check (Back in Ks_Image_16_Grey, "16-bit PGM reads as 16-bit grey");
         Check (Same_Image (Back, Grey16), "16-bit PGM pixels");
      end;
   end Test_PGM_Round_Trip;

   procedure Test_PPM_And_PNM is
      Colour : constant Ks_Image_24_Planar_Color := Colour_Pattern (6, 4);
      Grey   : constant Ks_Image_8_Grey := Grey_Pattern (3, 2);
      Grey16 : constant Ks_Image_16_Grey := Grey_16_Pattern (5, 2);
   begin
      Section ("PPM and PNM round trip");
      Write_Image (Path ("img_colour.ppm"), Colour);
      Check (Starts_With (Read_File (Path ("img_colour.ppm")),
                          "P6" & LF & "6 4" & LF & "255" & LF),
             "P6 header");
      Check (File_Size (Path ("img_colour.ppm")) = 11 + 6 * 4 * 3,
             "P6 file size");
      declare
         Back : constant Ks_Image'Class :=
           Read_Image (Path ("img_colour.ppm"));
      begin
         Check (Back in Ks_Image_24_Planar_Color, "PPM reads as colour");
         Check (Same_Image (Back, Colour), "PPM pixels");
      end;

      Write_Image (Path ("img_grey_as_colour.ppm"), Grey);
      declare
         Back : constant Ks_Image'Class :=
           Read_Image (Path ("img_grey_as_colour.ppm"));
      begin
         Check (Back in Ks_Image_24_Planar_Color,
                "grey written to .ppm reads back as colour");
         if Back in Ks_Image_24_Planar_Color then
            declare
               C : Ks_Image_24_Planar_Color renames
                 Ks_Image_24_Planar_Color (Back);
            begin
               Check (Same (C.Get_Plane (Red), Grey)
                        and then Same (C.Get_Plane (Green), Grey)
                        and then Same (C.Get_Plane (Blue), Grey),
                      "grey written with R = G = B");
            end;
         end if;
      end;
      Check (Same (Read_Image_8_Grey (Path ("img_grey_as_colour.ppm")), Grey),
             "luma of R = G = B gives the grey value back");

      Write_Image (Path ("img_grey8.pnm"), Grey);
      Write_Image (Path ("img_grey16.pnm"), Grey16);
      Write_Image (Path ("img_colour.pnm"), Colour);
      Check (Starts_With (Read_File (Path ("img_grey8.pnm")), "P5" & LF),
             ".pnm grey 8-bit is P5");
      Check (Starts_With (Read_File (Path ("img_grey16.pnm")),
                          "P5" & LF & "5 2" & LF & "65535" & LF),
             ".pnm grey 16-bit is P5 with maxval 65535");
      Check (Starts_With (Read_File (Path ("img_colour.pnm")), "P6" & LF),
             ".pnm colour is P6");
      Check (Same_Image (Read_Image (Path ("img_grey8.pnm")), Grey),
             ".pnm 8-bit round trip");
      Check (Same_Image (Read_Image (Path ("img_grey16.pnm")), Grey16),
             ".pnm 16-bit round trip");
      Check (Same_Image (Read_Image (Path ("img_colour.pnm")), Colour),
             ".pnm colour round trip");

      --  Extensions are matched without regard to case.
      Write_Image (Path ("img_upper.PGM"), Grey);
      Check (Same_Image (Read_Image (Path ("img_upper.PGM")), Grey),
             "upper case .PGM");
      Write_Image (Path ("img_mixed.Bmp"), Colour);
      Check (Same_Image (Read_Image (Path ("img_mixed.Bmp")), Colour),
             "mixed case .Bmp");
      --  Reading ignores the extension: a PNM stored under .bmp.
      Write_File (Path ("img_pnm_named.bmp"),
                  To_Bytes ("P5" & LF & "1 1" & LF & "255" & LF & 'A'));
      Check_Grey_Row (Read_Image (Path ("img_pnm_named.bmp")), 0,
                      [Character'Pos ('A')],
                      "format detected from content, not name");
   end Test_PPM_And_PNM;

   procedure Test_BMP_Round_Trip is
      Grey    : constant Ks_Image_8_Grey := Grey_Pattern (5, 3);
      Grey4   : constant Ks_Image_8_Grey := Grey_Pattern (4, 2);
      Colour  : constant Ks_Image_24_Planar_Color := Colour_Pattern (5, 3);
      Colour4 : constant Ks_Image_24_Planar_Color := Colour_Pattern (4, 1);
      Name    : constant String := Path ("img_grey8.bmp");
      NameC   : constant String := Path ("img_colour.bmp");
   begin
      Section ("BMP round trip");
      Write_Image (Name, Grey);
      declare
         Content : constant Stream_Element_Array := Read_File (Name);
      begin
         --  Stride of a 5 pixel 8-bit row: 8 bytes.
         Check (Starts_With (Content, "BM"), "8-bit BMP signature");
         Check (Content'Length = 14 + 40 + 1024 + 8 * 3, "8-bit BMP size");
         Check (U32_At (Content, 2) = Content'Length, "file size field");
         Check (U32_At (Content, 10) = 1078, "pixel data offset");
         Check (U32_At (Content, 14) = 40, "info header size");
         Check (U32_At (Content, 18) = 5 and then U32_At (Content, 22) = 3,
                "width and height (bottom-up)");
         Check (U16_At (Content, 28) = 8, "8 bits per pixel");
         Check (U32_At (Content, 30) = 0, "uncompressed");
         Check (U32_At (Content, 46) = 256, "256 palette entries");
         Check (U32_At (Content, 54 + 4 * 200) = 200 * 65_793,
                "grey palette entry 200");
         --  The first stored row is the bottom row; padding is zero.
         Check (Natural (Content (1079)) = Natural (Grey.Get_Pixel (0, 2)),
                "first stored row is the bottom row");
         Check (Content (1079 + 5) = 0 and then Content (1079 + 7) = 0,
                "row padding is zero");
      end;
      declare
         Back : constant Ks_Image'Class := Read_Image (Name);
      begin
         Check (Back in Ks_Image_8_Grey, "8-bit BMP reads as 8-bit grey");
         Check (Same_Image (Back, Grey), "8-bit BMP pixels");
      end;
      Write_Image (Path ("img_grey8_w4.bmp"), Grey4);
      Check (File_Size (Path ("img_grey8_w4.bmp")) = 1078 + 8,
             "no padding for a width of 4");
      Check (Same_Image (Read_Image (Path ("img_grey8_w4.bmp")), Grey4),
             "8-bit BMP width 4");

      Write_Image (NameC, Colour);
      declare
         Content : constant Stream_Element_Array := Read_File (NameC);
      begin
         --  Stride of a 5 pixel 24-bit row: 16 bytes.
         Check (Content'Length = 54 + 16 * 3, "24-bit BMP size");
         Check (U32_At (Content, 10) = 54, "24-bit pixel data offset");
         Check (U16_At (Content, 28) = 24, "24 bits per pixel");
         Check (U32_At (Content, 46) = 0, "no palette");
         declare
            R, G, B : Grey_8;
         begin
            Colour.Get_Pixel (0, 2, R, G, B);
            Check (Natural (Content (55)) = Natural (B)
                     and then Natural (Content (56)) = Natural (G)
                     and then Natural (Content (57)) = Natural (R),
                   "pixels stored blue, green, red, bottom row first");
         end;
      end;
      declare
         Back : constant Ks_Image'Class := Read_Image (NameC);
      begin
         Check (Back in Ks_Image_24_Planar_Color,
                "24-bit BMP reads as colour");
         Check (Same_Image (Back, Colour), "24-bit BMP pixels");
      end;
      Write_Image (Path ("img_colour_w4.bmp"), Colour4);
      Check (File_Size (Path ("img_colour_w4.bmp")) = 54 + 12,
             "no padding for 4 x 3 bytes");
      Check (Same_Image (Read_Image (Path ("img_colour_w4.bmp")), Colour4),
             "24-bit BMP width 4");
      Check (Same (Read_Image_8_Grey (Name), Grey),
             "Read_Image_8_Grey on an 8-bit BMP");
   end Test_BMP_Round_Trip;

   procedure Test_Multi_Image is
      Name   : constant String := Path ("img_multi.pnm");
      Grey   : constant Ks_Image_8_Grey := Grey_Pattern (3, 4);
      Grey16 : constant Ks_Image_16_Grey := Grey_16_Pattern (2, 2);
      Colour : constant Ks_Image_24_Planar_Color := Colour_Pattern (4, 2);
      Other  : constant Ks_Image_8_Grey := Create (1, 1, 99);
      File   : Ks_Image_File;
   begin
      Section ("multi-image PNM");
      File.Open (Name, Write);
      Check (File.Is_Open, "open for writing");
      Check (File.Open_Mode = Write, "Write mode");
      Check (File.File_Name = Name, "File_Name");
      Check (File.Count = 0, "nothing written yet");
      Check (Ada.Directories.Exists (Name) and then File_Size (Name) = 0,
             "Write mode creates an empty file at once");
      File.Append (Grey);
      Check (File.Count = 1, "Count after one Append");
      --  Append writes at once: the file is readable before Close.
      Check (Same_Image (Read_Image (Name), Grey), "written immediately");
      File.Append (Grey16);
      File.Append (Colour);
      File.Append (Other);
      Check (File.Count = 4, "Count after four Appends");
      File.Close;
      Check (not File.Is_Open and then File.Count = 0, "closed");

      File.Open (Name, Read);
      Check (File.Open_Mode = Read and then File.Count = 4,
             "four images read");
      Check (Same_Image (File.Item (0), Grey), "image 0 (8-bit)");
      Check (Same_Image (File.Item (1), Grey16), "image 1 (16-bit)");
      Check (Same_Image (File.Item (2), Colour), "image 2 (colour)");
      Check (Same_Image (File.Item (3), Other), "image 3 (8-bit)");
      Check (Same_Image (Read_Image (Name, 2), Colour), "Read_Image index 2");
      Check (Same_Image (Read_Image (Name), Grey), "Read_Image default 0");
      Check (Read_Image_8_Grey (Name, 3).Get_Pixel (0, 0) = 99,
             "Read_Image_8_Grey index 3");

      --  Item gives independent images.
      declare
         First : Ks_Image'Class := File.Item (0);
         Again : constant Ks_Image'Class := File.Item (0);
      begin
         Ks_Image_8_Grey (First).Fill (0);
         Check (Same_Image (Again, Grey), "Item copies are independent");
         Check (Same_Image (File.Item (0), Grey),
                "the file's image is not changed through Item");
      end;

      --  A copy of the file object has its own state.
      declare
         Copy_Of_File : constant Ks_Image_File := File;
      begin
         File.Close;
         Check (Copy_Of_File.Is_Open and then Copy_Of_File.Count = 4,
                "a copy stays open when the original is closed");
         Check (Same_Image (Copy_Of_File.Item (2), Colour),
                "the copy still reads");
      end;

      declare
         procedure Item_Past_End is
            Reader : Ks_Image_File;
         begin
            Reader.Open (Name, Read);
            Check (not Reader.Item (4).Allocated, "unreachable");
         end Item_Past_End;

         procedure Read_Past_End is
            Image : constant Ks_Image'Class := Read_Image (Name, 4);
         begin
            Check (not Image.Allocated, "unreachable");
         end Read_Past_End;

         procedure Grey_Past_End is
            Image : constant Ks_Image_8_Grey := Read_Image_8_Grey (Name, 9);
         begin
            Check (not Image.Allocated, "unreachable");
         end Grey_Past_End;

         procedure T1 is new Check_Raises_Exactly (Item_Past_End, Range_Error);
         procedure T2 is new Check_Raises_Exactly (Read_Past_End, File_Error);
         procedure T3 is new Check_Raises_Exactly (Grey_Past_End, File_Error);
      begin
         T1 ("Item with Index = Count");
         T2 ("Read_Image with an index past the last image");
         T3 ("Read_Image_8_Grey with an index past the last image");
      end;

      --  Update mode adds to the existing images.
      File.Open (Name, Update);
      Check (File.Open_Mode = Update, "Update mode");
      Check (File.Count = 4, "Update mode counts the existing images");
      File.Append (Grey16);
      Check (File.Count = 5, "Count after appending");
      File.Close;
      File.Open (Name, Read);
      Check (File.Count = 5, "five images after appending");
      Check (Same_Image (File.Item (4), Grey16), "appended image");
      Check (Same_Image (File.Item (0), Grey), "earlier images kept");
      File.Close;

      --  Update mode on a missing file creates it.
      if Ada.Directories.Exists (Path ("img_append_new.pgm")) then
         Ada.Directories.Delete_File (Path ("img_append_new.pgm"));
      end if;
      File.Open (Path ("img_append_new.pgm"), Update);
      Check (File.Count = 0, "Update mode on a missing file: Count 0");
      Check (Ada.Directories.Exists (Path ("img_append_new.pgm")),
             "Update mode creates a missing file");
      File.Append (Grey);
      File.Append (Grey);
      Check (File.Count = 2, "two appended to a new file");
      File.Close;
      Check (Read_Image (Path ("img_append_new.pgm"), 1).Width = 3,
             "second image of the new file");

      --  Update mode on an empty file.
      Write_File (Path ("img_append_empty.pnm"), Zeros (0));
      File.Open (Path ("img_append_empty.pnm"), Update);
      Check (File.Count = 0, "Update mode on an empty file");
      File.Append (Colour);
      File.Close;
      Check (Same_Image (Read_Image (Path ("img_append_empty.pnm")), Colour),
             "appended to an empty file");

      --  Write mode truncates.
      File.Open (Name, Write);
      File.Close;
      Check (File_Size (Name) = 0, "Write mode empties an existing file");

      --  Whitespace between concatenated images is allowed.
      Write_File
        (Path ("img_multi_spaced.pgm"),
         To_Bytes ("P5 1 1 255" & LF & 'A' & LF & LF & "  P2 2 1 9 1 2"
                   & LF & "   " & CR & LF));
      File.Open (Path ("img_multi_spaced.pgm"), Read);
      Check (File.Count = 2, "two images separated by whitespace");
      Check_Grey_Row (File.Item (0), 0, [65], "first spaced image");
      Check_Grey_Row (File.Item (1), 0, [1, 2], "second spaced image");
      File.Close;

      --  Appending after a plain image whose last sample ends the file:
      --  the reader needs a separator after that sample, so Append writes
      --  a line feed first and the file stays readable.
      declare
         Plain  : constant String := Path ("img_append_plain.pgm");
         Plain3 : constant String := Path ("img_append_plain.ppm");
         Ended  : constant String := Path ("img_append_ended.pgm");
         Binary : constant String := Path ("img_append_binary.pgm");
         Added  : constant Ks_Image_8_Grey := Create (2, 1, 65);
         Before : Big;
      begin
         Write_File (Plain, To_Bytes ("P2 1 1 9 9"));
         File.Open (Plain, Update);
         Check (File.Count = 1, "plain P2 without a final newline: Count 1");
         File.Append (Added);
         Check (File.Count = 2, "appended to the plain P2 file");
         File.Close;
         Check (Starts_With (Read_File (Plain), "P2 1 1 9 9" & LF & "P5"),
                "a line feed separates the plain image from the new one");
         File.Open (Plain, Read);
         Check (File.Count = 2, "the plain P2 file reads with two images");
         Check_Grey_Row (File.Item (0), 0, [9], "the plain image is intact");
         Check (Same_Image (File.Item (1), Added), "the appended image");
         File.Close;

         Write_File (Plain3, To_Bytes ("P3 1 1 9 1 2 3"));
         File.Open (Plain3, Update);
         File.Append (Colour);
         File.Close;
         File.Open (Plain3, Read);
         Check (File.Count = 2, "the plain P3 file reads with two images");
         Check_Colour_Pixel (File.Item (0), 0, 0, 1, 2, 3,
                             "the plain colour image is intact");
         Check (Same_Image (File.Item (1), Colour),
                "the appended colour image");
         File.Close;

         --  A file that already ends in whitespace gets nothing extra.
         Write_File (Ended, To_Bytes ("P2 1 1 9 9" & LF));
         Before := File_Size (Ended);
         File.Open (Ended, Update);
         File.Append (Added);
         File.Close;
         Check (File_Size (Ended) = Before + 13,
                "no separator after a final newline: size"
                & File_Size (Ended)'Image);
         Check (Read_Image (Ended, 1).Width = 2, "and it reads");

         --  After a binary raster whose last byte is not whitespace a line
         --  feed is written too; whitespace between images is allowed.
         Write_File (Binary, To_Bytes ("P5 1 1 255" & LF & 'A'));
         File.Open (Binary, Update);
         File.Append (Added);
         File.Close;
         File.Open (Binary, Read);
         Check (File.Count = 2, "binary raster ending in 'A', then Append");
         Check_Grey_Row (File.Item (0), 0, [65], "the binary image is intact");
         File.Close;

         --  The image file tool appends the same way.
         declare
            Tool : Ks_Image_File_Tool;
         begin
            Write_File (Plain, To_Bytes ("P2 1 1 9 9"));
            Tool.Operator.Open (Plain, Update);
            Tool.Input_Image := Added;
            Tool.Run;
            Check (Tool.Run_Status.Result = Accept_Result,
                   "tool Append on a plain P2 file");
            Tool.Operator.Close;
            File.Open (Plain, Read);
            Check (File.Count = 2, "the tool's file reads with two images");
            File.Close;
         end;
      end;
   end Test_Multi_Image;

   procedure Test_BMP_Single_Image is
      Name  : constant String := Path ("img_single.bmp");
      Grey  : constant Ks_Image_8_Grey := Grey_Pattern (3, 3);
      File  : Ks_Image_File;

      procedure Second_Append is
      begin
         File.Append (Grey);
      end Second_Append;

      procedure T1 is new Check_Raises_Exactly (Second_Append, File_Error);
   begin
      Section ("BMP holds one image");
      File.Open (Name, Write);
      File.Append (Grey);
      T1 ("second Append to a BMP file");
      Check (File.Count = 1, "Count stays 1");
      File.Close;
      Check (Same_Image (Read_Image (Name), Grey),
             "the first image is intact");

      File.Open (Name, Update);
      Check (File.Count = 1, "Update mode on a BMP file counts its image");
      T1 ("Append to an existing BMP file");
      File.Close;
      Check (Same_Image (Read_Image (Name), Grey), "still intact");

      --  The rule is about the disk file: a copy of the file object, or a
      --  second object opened on the same file, cannot add an image that
      --  the reader would never see.
      declare
         Other  : constant Ks_Image_8_Grey := Grey_Pattern (7, 6);
         Copied : Ks_Image_File;
         Second : Ks_Image_File;
         Size   : Big;

         procedure Append_Copied is
         begin
            Copied.Append (Other);
         end Append_Copied;

         procedure Append_Second is
         begin
            Second.Append (Other);
         end Append_Second;

         procedure T2 is new Check_Raises_Exactly (Append_Copied, File_Error);
         procedure T3 is new Check_Raises_Exactly (Append_Second, File_Error);
      begin
         File.Open (Name, Write);
         Copied := File;
         File.Append (Grey);
         Size := File_Size (Name);
         T2 ("Append through a copy after the original wrote the image");
         Check (Copied.Count = 0, "the copy's Count is unchanged");
         Check (File_Size (Name) = Size, "the file is unchanged");
         Check (Same_Image (Read_Image (Name), Grey),
                "the original's image is intact");
         File.Close;
         Copied.Close;

         File.Open (Name, Write);
         Second.Open (Name, Update);
         Check (Second.Count = 0, "a second object on the empty file");
         File.Append (Grey);
         T3 ("Append through a second object after the first wrote");
         Check (File_Size (Name) = Size, "the file is unchanged again");
         Check (Same_Image (Read_Image (Name), Grey),
                "the first object's image is intact");
         File.Close;
         Second.Close;
      end;
   end Test_BMP_Single_Image;

   procedure Test_Write_Errors is
      Colour : constant Ks_Image_24_Planar_Color := Colour_Pattern (2, 2);
      Grey16 : constant Ks_Image_16_Grey := Grey_16_Pattern (2, 2);
      Grey   : constant Ks_Image_8_Grey := Grey_Pattern (2, 2);
      Empty  : Ks_Image_8_Grey;
      Keep   : constant String := Path ("img_keep.pgm");

      procedure Colour_To_PGM is
      begin
         Write_Image (Keep, Colour);
      end Colour_To_PGM;

      procedure Grey16_To_PPM is
      begin
         Write_Image (Path ("img_bad16.ppm"), Grey16);
      end Grey16_To_PPM;

      procedure Grey16_To_BMP is
      begin
         Write_Image (Path ("img_bad16.bmp"), Grey16);
      end Grey16_To_BMP;

      procedure Unknown_Extension is
      begin
         Write_Image (Path ("img_bad.png"), Grey);
      end Unknown_Extension;

      procedure No_Extension is
      begin
         Write_Image (Path ("img_no_extension"), Grey);
      end No_Extension;

      procedure Dot_In_Directory is
      begin
         Write_Image ("tests/output.d/img_none", Grey);
      end Dot_In_Directory;

      procedure Open_Unknown_Extension is
         File : Ks_Image_File;
      begin
         File.Open (Path ("img_bad.txt"), Write);
      end Open_Unknown_Extension;

      procedure Append_Unknown_Extension is
         File : Ks_Image_File;
      begin
         File.Open (Path ("img_bad.jpg"), Update);
      end Append_Unknown_Extension;

      procedure Write_Unallocated is
      begin
         Write_Image (Path ("img_empty.pgm"), Empty);
      end Write_Unallocated;

      procedure Append_Unallocated is
         File : Ks_Image_File;
      begin
         File.Open (Path ("img_empty2.pgm"), Write);
         File.Append (Empty);
      end Append_Unallocated;

      procedure Missing_Directory is
      begin
         Write_Image (Path ("no_such_dir/img.pgm"), Grey);
      end Missing_Directory;

      procedure Append_Missing_Directory is
         File : Ks_Image_File;
      begin
         File.Open (Path ("no_such_dir/img.pgm"), Update);
      end Append_Missing_Directory;

      procedure T1 is new Check_Raises_Exactly (Colour_To_PGM, File_Error);
      procedure T2 is new Check_Raises_Exactly (Grey16_To_PPM, File_Error);
      procedure T3 is new Check_Raises_Exactly (Grey16_To_BMP, File_Error);
      procedure T4 is new Check_Raises_Exactly (Unknown_Extension, File_Error);
      procedure T5 is new Check_Raises_Exactly (No_Extension, File_Error);
      procedure T6 is new Check_Raises_Exactly (Dot_In_Directory, File_Error);
      procedure T7 is new Check_Raises_Exactly
        (Open_Unknown_Extension, File_Error);
      procedure T8 is new Check_Raises_Exactly
        (Append_Unknown_Extension, File_Error);
      procedure T9 is new Check_Raises_Exactly (Write_Unallocated, No_Pixels);
      procedure T10 is new Check_Raises_Exactly
        (Append_Unallocated, No_Pixels);
      procedure T11 is new Check_Raises_Exactly
        (Missing_Directory, File_Error);
      procedure T12 is new Check_Raises_Exactly
        (Append_Missing_Directory, File_Error);
   begin
      Section ("write errors");
      Write_Image (Keep, Grey);
      T1 ("colour image to .pgm");
      Check (Same_Image (Read_Image (Keep), Grey),
             "a rejected Write_Image leaves the existing file alone");
      T2 ("16-bit image to .ppm");
      T3 ("16-bit image to .bmp");
      T4 ("unknown extension .png");
      T5 ("no extension");
      T6 ("a dot in a directory name is not an extension");
      T7 ("Open in Write mode with extension .txt");
      T8 ("Open in Update mode with extension .jpg");
      T9 ("Write_Image of an unallocated image");
      T10 ("Append of an unallocated image");
      Check (File_Size (Path ("img_empty2.pgm")) = 0,
             "a rejected Append writes nothing");
      T11 ("writing into a missing directory");
      T12 ("Update mode in a missing directory");

      --  A directory whose name has an image extension.
      Ada.Directories.Create_Path (Path ("img_dir.pgm"));
      declare
         procedure Append_To_Directory is
            File : Ks_Image_File;
         begin
            File.Open (Path ("img_dir.pgm"), Update);
         end Append_To_Directory;

         procedure Write_To_Directory is
         begin
            Write_Image (Path ("img_dir.pgm"), Grey);
         end Write_To_Directory;

         procedure D1 is new Check_Raises_Exactly
           (Append_To_Directory, File_Error);
         procedure D2 is new Check_Raises_Exactly
           (Write_To_Directory, File_Error);
      begin
         D1 ("Update mode on a directory");
         D2 ("Write_Image onto a directory");
      end;

      --  Update mode on a file whose content does not match the extension.
      Write_Image (Path ("img_really_pnm.pgm"), Grey);
      Ada.Directories.Copy_File
        (Path ("img_really_pnm.pgm"), Path ("img_really_pnm.bmp"));
      Write_Image (Path ("img_really_bmp.bmp"), Grey);
      Ada.Directories.Copy_File
        (Path ("img_really_bmp.bmp"), Path ("img_really_bmp.pgm"));
      declare
         procedure PNM_As_BMP is
            File : Ks_Image_File;
         begin
            File.Open (Path ("img_really_pnm.bmp"), Update);
         end PNM_As_BMP;

         procedure BMP_As_PGM is
            File : Ks_Image_File;
         begin
            File.Open (Path ("img_really_bmp.pgm"), Update);
         end BMP_As_PGM;

         procedure Append_To_Garbage is
            File : Ks_Image_File;
         begin
            Write_File (Path ("img_garbage.pgm"), To_Bytes ("garbage"));
            File.Open (Path ("img_garbage.pgm"), Update);
         end Append_To_Garbage;

         procedure U1 is new Check_Raises_Exactly (PNM_As_BMP, File_Error);
         procedure U2 is new Check_Raises_Exactly (BMP_As_PGM, File_Error);
         procedure U3 is new Check_Raises_Exactly
           (Append_To_Garbage, File_Error);
      begin
         U1 ("Update mode: PNM content under .bmp");
         U2 ("Update mode: BMP content under .pgm");
         U3 ("Update mode: undecodable existing file");
      end;
   end Test_Write_Errors;

   procedure Test_File_Object_States is
      File  : Ks_Image_File;
      Grey  : constant Ks_Image_8_Grey := Grey_Pattern (2, 3);

      procedure Item_Closed is
      begin
         Check (not File.Item (0).Allocated, "unreachable");
      end Item_Closed;

      procedure Append_Closed is
      begin
         File.Append (Grey);
      end Append_Closed;

      procedure Item_In_Write_Mode is
         Writer : Ks_Image_File;
      begin
         Writer.Open (Path ("img_state.pgm"), Write);
         Check (not Writer.Item (0).Allocated, "unreachable");
      end Item_In_Write_Mode;

      procedure Append_In_Read_Mode is
         Reader : Ks_Image_File;
      begin
         Reader.Open (Path ("img_state_read.pgm"), Read);
         Reader.Append (Grey);
      end Append_In_Read_Mode;

      procedure Open_Missing is
      begin
         File.Open (Path ("img_does_not_exist.pgm"), Read);
      end Open_Missing;

      procedure Open_Directory is
      begin
         File.Open ("tests/output", Read);
      end Open_Directory;

      procedure Read_Empty_Name is
         Image : constant Ks_Image'Class := Read_Image ("");
      begin
         Check (not Image.Allocated, "unreachable");
      end Read_Empty_Name;

      procedure Open_Closed_Mode is
      begin
         File.Open (Path ("img_state_closed.pgm"), Closed);
      end Open_Closed_Mode;

      procedure T1 is new Check_Raises_Exactly (Item_Closed, File_Error);
      procedure T2 is new Check_Raises_Exactly (Append_Closed, File_Error);
      procedure T3 is new Check_Raises_Exactly
        (Item_In_Write_Mode, File_Error);
      procedure T4 is new Check_Raises_Exactly
        (Append_In_Read_Mode, File_Error);
      procedure T5 is new Check_Raises_Exactly (Open_Missing, File_Error);
      procedure T6 is new Check_Raises_Exactly (Open_Directory, File_Error);
      procedure T7 is new Check_Raises_Exactly (Read_Empty_Name, File_Error);
      procedure T8 is new Check_Raises_Exactly
        (Open_Closed_Mode, Ks_Bad_Parameter_Exception'Identity);
   begin
      Section ("file object states");
      Check (not File.Is_Open, "default closed");
      Check (File.Count = 0, "default Count");
      Check (File.File_Name = "", "default File_Name");
      Check (File.Open_Mode = Closed, "default Open_Mode is Closed");
      Check (Ks_Image_File_Mode_Constants'Pos (Closed) = 0
             and then Ks_Image_File_Mode_Constants'Pos (Read) = 1
             and then Ks_Image_File_Mode_Constants'Pos (Write) = 2
             and then Ks_Image_File_Mode_Constants'Pos (Update) = 3,
             "mode literals in the order Closed, Read, Write, Update");
      T8 ("Open with mode Closed, on a closed file");
      Check (not File.Is_Open and then File.Open_Mode = Closed
             and then not Ada.Directories.Exists
                            (Path ("img_state_closed.pgm")),
             "a rejected Closed mode opens and creates nothing");
      File.Close;
      Check (not File.Is_Open, "closing a closed file");
      T1 ("Item on a closed file");
      T2 ("Append on a closed file");
      Write_Image (Path ("img_state_read.pgm"), Grey);
      T3 ("Item in Write mode");
      T4 ("Append in Read mode");

      File.Open (Path ("img_state_read.pgm"), Read);
      Check (File.Is_Open and then File.Count = 1, "open for reading");
      T8 ("Open with mode Closed, on an open file");
      Check (File.Open_Mode = Read and then File.Count = 1
             and then File.File_Name = Path ("img_state_read.pgm"),
             "a rejected Closed mode leaves an open file as it was");
      --  Opening again closes first; a failed Open leaves it closed.
      T5 ("Open of a missing file");
      Check (not File.Is_Open and then File.Open_Mode = Closed,
             "a failed Open leaves the file closed");
      Check (File.Count = 0 and then File.File_Name = "",
             "and in its default state");
      T6 ("Open of a directory");
      T7 ("Read_Image of an empty name");

      File.Open (Path ("img_state_read.pgm"), Read);
      File.Open (Path ("img_state2.ppm"), Write);
      Check (File.Open_Mode = Write and then File.Count = 0,
             "Open on an open file switches to the new file");
      File.Append (Grey);
      File.Close;
      Check (File.File_Name = "" and then File.Open_Mode = Closed,
             "Close returns to the defaults");
      Check (Read_Image (Path ("img_state2.ppm"))
               in Ks_Image_24_Planar_Color,
             "the second file was written");
   end Test_File_Object_States;

   procedure Test_Conversions is
      Name16 : constant String := Path ("img_maxval1000.pgm");
      NameC  : constant String := Path ("img_luma.ppm");
      Colour : Ks_Image_24_Planar_Color := Create (6, 1);
      Grey16 : Ks_Image_16_Grey := Create (5, 1);
   begin
      Section ("conversion to 8-bit grey");
      --  16-bit samples with maxval 1000: round (V * 255 / 1000).
      Write_File
        (Name16,
         To_Bytes ("P5" & LF & "5 1" & LF & "1000" & LF)
         & [0, 0, 16#03#, 16#E8#, 16#01#, 16#F4#, 0, 2, 0, 1]);
      declare
         Raw : constant Ks_Image'Class := Read_Image (Name16);
      begin
         Check (Raw in Ks_Image_16_Grey, "maxval 1000 gives 16-bit");
         if Raw in Ks_Image_16_Grey then
            Check (Ks_Image_16_Grey (Raw).Get_Pixel (1, 0) = 1000
                     and then Ks_Image_16_Grey (Raw).Get_Pixel (2, 0) = 500,
                   "16-bit samples stored as read");
         end if;
      end;
      Check_Grey_Row (Read_Image_8_Grey (Name16), 0, [0, 255, 128, 1, 0],
                      "16-bit scaled by 255 / maxval, rounded half up");

      --  Written 16-bit images use maxval 65535.
      Grey16.Set_Pixel (0, 0, 65_535);
      Grey16.Set_Pixel (1, 0, 257);
      Grey16.Set_Pixel (2, 0, 128);
      Grey16.Set_Pixel (3, 0, 129);
      Grey16.Set_Pixel (4, 0, 32_768);
      Write_Image (Path ("img_scale16.pgm"), Grey16);
      Check_Grey_Row (Read_Image_8_Grey (Path ("img_scale16.pgm")), 0,
                      [255, 1, 0, 1, 128],
                      "16-bit with maxval 65535");

      --  Colour: round (0.299 R + 0.587 G + 0.114 B).
      Colour.Set_Pixel (0, 0, 255, 0, 0);
      Colour.Set_Pixel (1, 0, 0, 255, 0);
      Colour.Set_Pixel (2, 0, 0, 0, 255);
      Colour.Set_Pixel (3, 0, 255, 255, 255);
      Colour.Set_Pixel (4, 0, 10, 20, 30);
      Colour.Set_Pixel (5, 0, 0, 0, 250);
      Write_Image (NameC, Colour);
      Check_Grey_Row (Read_Image_8_Grey (NameC), 0, [76, 150, 29, 255, 18, 29],
                      "colour to luma (28.5 rounds up to 29)");

      --  8-bit samples with a small maxval are kept as stored.
      Write_File (Path ("img_maxval15.pgm"),
                  To_Bytes ("P5" & LF & "3 1" & LF & "15" & LF) & [0, 7, 15]);
      Check (Read_Image (Path ("img_maxval15.pgm")) in Ks_Image_8_Grey,
             "maxval 15 gives 8-bit");
      Check_Grey_Row (Read_Image (Path ("img_maxval15.pgm")), 0, [0, 7, 15],
                      "maxval 15: samples not rescaled");
      Check_Grey_Row (Read_Image_8_Grey (Path ("img_maxval15.pgm")), 0,
                      [0, 7, 15], "Read_Image_8_Grey keeps 8-bit samples");

      --  Maxval 255 vs 256: the boundary between 8 and 16 bits.
      Write_File (Path ("img_maxval256.pgm"),
                  To_Bytes ("P5" & LF & "1 1" & LF & "256" & LF) & [1, 0]);
      Check (Read_Image (Path ("img_maxval256.pgm")) in Ks_Image_16_Grey,
             "maxval 256 gives 16-bit");
      Check_Grey_Row (Read_Image_8_Grey (Path ("img_maxval256.pgm")), 0,
                      [255], "256 of 256 scales to 255");
      Write_File (Path ("img_maxval65535.pgm"),
                  To_Bytes ("P2" & LF & "2 1" & LF & "65535" & LF
                            & "65535 0" & LF));
      Check (Read_Image (Path ("img_maxval65535.pgm")) in Ks_Image_16_Grey,
             "ASCII maxval 65535 gives 16-bit");
      Check_Grey_Row (Read_Image_8_Grey (Path ("img_maxval65535.pgm")), 0,
                      [255, 0], "ASCII 16-bit scaled");
   end Test_Conversions;

   procedure Test_PNM_Syntax is
      Name : constant String := Path ("img_syntax.pnm");
   begin
      Section ("PNM header syntax");
      Write_File
        (Name,
         To_Bytes ("P2" & LF & "# a comment line" & LF & "3 # width" & LF
                   & "2" & LF & "# maxval next" & LF & "255" & LF
                   & "0 1 2" & LF & "# a comment in the raster" & LF
                   & "3" & ASCII.HT & "4   255" & LF));
      declare
         Image : constant Ks_Image'Class := Read_Image (Name);
      begin
         Check_Grey_Row (Image, 0, [0, 1, 2], "P2 with comments, row 0");
         Check_Grey_Row (Image, 1, [3, 4, 255], "P2 with comments, row 1");
      end;

      --  A comment directly after the maxval ends the header with its line.
      Write_File (Name,
                  To_Bytes ("P5 #c" & LF & "2 2 255#comment" & LF & "ABCD"));
      Check_Grey_Row (Read_Image (Name), 0, [65, 66],
                      "comment right after the maxval, row 0");
      Check_Grey_Row (Read_Image (Name), 1, [67, 68],
                      "comment right after the maxval, row 1");

      --  CR LF line ends: the single byte after the maxval is the CR, so
      --  the LF is the first sample of a binary raster.
      Write_File (Name, To_Bytes ("P2" & CR & LF & "2 1" & CR & LF & "255"
                                  & CR & LF & "7 8" & CR & LF));
      Check_Grey_Row (Read_Image (Name), 0, [7, 8], "P2 with CR LF");
      Write_File (Name, To_Bytes ("P5" & CR & LF & "2 1" & CR & LF & "255"
                                  & CR & LF & 'Z'));
      Check_Grey_Row (Read_Image (Name), 0, [10, 90],
                      "P5: one whitespace byte after the maxval");

      --  Binary sample bytes that look like whitespace or '#'.
      Write_File (Name, To_Bytes ("P5 3 1 255 ") & [32, 35, 10]);
      Check_Grey_Row (Read_Image (Name), 0, [32, 35, 10],
                      "binary raster bytes are not parsed as text");

      --  P3 ASCII colour.
      Write_File (Name, To_Bytes ("P3 2 1 255" & LF & "1 2 3  250 251 252"));
      declare
         Image : constant Ks_Image'Class := Read_Image (Name);
      begin
         Check (Image in Ks_Image_24_Planar_Color, "P3 reads as colour");
         Check_Colour_Pixel (Image, 0, 0, 1, 2, 3, "P3 pixel 0");
         Check_Colour_Pixel (Image, 1, 0, 250, 251, 252, "P3 pixel 1");
      end;
      --  P6 with maxval below 255 keeps the samples.
      Write_File (Name, To_Bytes ("P6 1 1 100" & LF) & [100, 0, 50]);
      Check_Colour_Pixel (Read_Image (Name), 0, 0, 100, 0, 50,
                          "P6 with maxval 100");
      --  A file with nothing after the last ASCII sample.
      Write_File (Name, To_Bytes ("P2 1 1 9 9"));
      Check_Grey_Row (Read_Image (Name), 0, [9], "P2 ending without newline");
      --  Leading zeros in numbers.
      Write_File (Name, To_Bytes ("P2 0002 01 0255 007 0"));
      Check_Grey_Row (Read_Image (Name), 0, [7, 0], "leading zeros");
   end Test_PNM_Syntax;

   procedure Test_BMP_Variants is
      Name : constant String := Path ("img_crafted.bmp");

      function Info_Header
        (Offset, Width, Height : Big;
         Bits                  : Big;
         Data_Size             : Big;
         Compression           : Big := 0;
         Colours_Used          : Big := 0) return Stream_Element_Array is
        (To_Bytes ("BM") & LE32 (Offset + Data_Size) & LE32 (0)
         & LE32 (Offset) & LE32 (40) & LE32 (Width) & LE32 (Height)
         & LE16 (1) & LE16 (Bits) & LE32 (Compression) & LE32 (Data_Size)
         & LE32 (2835) & LE32 (2835) & LE32 (Colours_Used) & LE32 (0));
   begin
      Section ("BMP variants");

      --  Top-down 24-bit: rows stored from the top.
      Write_File
        (Name,
         Info_Header (54, 2, -2, 24, 16)
         & [3, 2, 1, 6, 5, 4, 0, 0, 9, 8, 7, 12, 11, 10, 0, 0]);
      declare
         Image : constant Ks_Image'Class := Read_Image (Name);
      begin
         Check (Image.Width = 2 and then Image.Height = 2,
                "top-down size");
         Check_Colour_Pixel (Image, 0, 0, 1, 2, 3, "top-down (0, 0)");
         Check_Colour_Pixel (Image, 1, 0, 4, 5, 6, "top-down (1, 0)");
         Check_Colour_Pixel (Image, 0, 1, 7, 8, 9, "top-down (0, 1)");
         Check_Colour_Pixel (Image, 1, 1, 10, 11, 12, "top-down (1, 1)");
      end;

      --  The same pixels bottom-up.
      Write_File
        (Name,
         Info_Header (54, 2, 2, 24, 16)
         & [9, 8, 7, 12, 11, 10, 0, 0, 3, 2, 1, 6, 5, 4, 0, 0]);
      Check_Colour_Pixel (Read_Image (Name), 0, 0, 1, 2, 3,
                          "bottom-up (0, 0)");
      Check_Colour_Pixel (Read_Image (Name), 1, 1, 10, 11, 12,
                          "bottom-up (1, 1)");

      --  The last row's padding may be missing.
      Write_File
        (Name,
         Info_Header (54, 1, 2, 24, 7) & [3, 2, 1, 0, 6, 5, 4]);
      Check_Colour_Pixel (Read_Image (Name), 0, 0, 4, 5, 6,
                          "missing final padding accepted");

      --  32-bit BI_RGB, bottom-up; the fourth byte is ignored.
      Write_File
        (Name,
         Info_Header (54, 2, 2, 32, 16)
         & [30, 20, 10, 255, 60, 50, 40, 0, 3, 2, 1, 9, 6, 5, 4, 9]);
      Check_Colour_Pixel (Read_Image (Name), 0, 0, 1, 2, 3, "32-bit (0, 0)");
      Check_Colour_Pixel (Read_Image (Name), 1, 0, 4, 5, 6, "32-bit (1, 0)");
      Check_Colour_Pixel (Read_Image (Name), 0, 1, 10, 20, 30,
                          "32-bit (0, 1)");
      Check_Colour_Pixel (Read_Image (Name), 1, 1, 40, 50, 60,
                          "32-bit (1, 1)");

      --  32-bit BI_BITFIELDS with the standard masks after a 40-byte
      --  header, top-down.
      Write_File
        (Name,
         Info_Header (66, 1, -1, 32, 4, Compression => 3)
         & LE32 (16#00FF_0000#) & LE32 (16#0000_FF00#) & LE32 (16#0000_00FF#)
         & [7, 8, 9, 0]);
      Check_Colour_Pixel (Read_Image (Name), 0, 0, 9, 8, 7,
                          "32-bit bit fields");

      --  8-bit indexed with a colour palette of three entries gives colour.
      Write_File
        (Name,
         Info_Header (66, 3, 1, 8, 4, Colours_Used => 3)
         & [0, 0, 255, 0, 0, 255, 0, 0, 255, 0, 0, 0]
         & [2, 0, 1, 0]);
      declare
         Image : constant Ks_Image'Class := Read_Image (Name);
      begin
         Check (Image in Ks_Image_24_Planar_Color,
                "colour palette gives a colour image");
         Check_Colour_Pixel (Image, 0, 0, 0, 0, 255, "palette index 2");
         Check_Colour_Pixel (Image, 1, 0, 255, 0, 0, "palette index 0");
         Check_Colour_Pixel (Image, 2, 0, 0, 255, 0, "palette index 1");
      end;
      Check_Grey_Row (Read_Image_8_Grey (Name), 0, [29, 76, 150],
                      "indexed colour to luma");

      --  8-bit, 256 entry palette mapping index I to grey 255 - I,
      --  top-down: the grey image holds palette values, not indices.
      declare
         Palette : Stream_Element_Array (1 .. 1024);
      begin
         for I in 0 .. 255 loop
            Palette (Stream_Element_Offset (4 * I + 1)) :=
              Stream_Element (255 - I);
            Palette (Stream_Element_Offset (4 * I + 2)) :=
              Stream_Element (255 - I);
            Palette (Stream_Element_Offset (4 * I + 3)) :=
              Stream_Element (255 - I);
            Palette (Stream_Element_Offset (4 * I + 4)) := 0;
         end loop;
         Write_File
           (Name,
            Info_Header (1078, 2, -2, 8, 8)
            & Palette & [0, 10, 0, 0, 255, 128, 0, 0]);
      end;
      declare
         Image : constant Ks_Image'Class := Read_Image (Name);
      begin
         Check (Image in Ks_Image_8_Grey, "grey palette gives 8-bit grey");
         Check_Grey_Row (Image, 0, [255, 245], "inverted palette, row 0");
         Check_Grey_Row (Image, 1, [0, 127], "inverted palette, row 1");
      end;

      --  4-bit grey palette (16 levels I * 17).
      declare
         Palette : Stream_Element_Array (1 .. 64);
      begin
         for I in 0 .. 15 loop
            Palette (Stream_Element_Offset (4 * I + 1)) :=
              Stream_Element (17 * I);
            Palette (Stream_Element_Offset (4 * I + 2)) :=
              Stream_Element (17 * I);
            Palette (Stream_Element_Offset (4 * I + 3)) :=
              Stream_Element (17 * I);
            Palette (Stream_Element_Offset (4 * I + 4)) := 0;
         end loop;
         Write_File
           (Name,
            Info_Header (54 + 64, 3, 2, 4, 8)
            & Palette & [16#F0#, 16#70#, 0, 0, 16#12#, 16#30#, 0, 0]);
      end;
      declare
         Image : constant Ks_Image'Class := Read_Image (Name);
      begin
         Check_Grey_Row (Image, 0, [17, 34, 51], "4-bit row 0");
         Check_Grey_Row (Image, 1, [255, 0, 119], "4-bit row 1");
      end;

      --  1-bit black and white.
      Write_File
        (Name,
         Info_Header (62, 10, 1, 1, 4, Colours_Used => 2)
         & [0, 0, 0, 0, 255, 255, 255, 0]
         & [16#B3#, 16#80#, 0, 0]);
      Check_Grey_Row (Read_Image (Name), 0,
                      [255, 0, 255, 255, 0, 0, 255, 255, 255, 0],
                      "1-bit pixels, most significant bit first");

      --  OS/2 style BITMAPCOREHEADER, 24-bit, bottom-up.
      Write_File
        (Name,
         To_Bytes ("BM") & LE32 (26 + 8) & LE32 (0) & LE32 (26)
         & LE32 (12) & LE16 (1) & LE16 (2) & LE16 (1) & LE16 (24)
         & [30, 20, 10, 0, 3, 2, 1, 0]);
      Check_Colour_Pixel (Read_Image (Name), 0, 0, 1, 2, 3,
                          "core header (0, 0)");
      Check_Colour_Pixel (Read_Image (Name), 0, 1, 10, 20, 30,
                          "core header (0, 1)");

      --  BITMAPCOREHEADER, 8-bit with a 3-byte-per-entry grey palette.
      declare
         Palette : Stream_Element_Array (1 .. 768);
      begin
         for I in 0 .. 255 loop
            Palette (Stream_Element_Offset (3 * I + 1)) := Stream_Element (I);
            Palette (Stream_Element_Offset (3 * I + 2)) := Stream_Element (I);
            Palette (Stream_Element_Offset (3 * I + 3)) := Stream_Element (I);
         end loop;
         Write_File
           (Name,
            To_Bytes ("BM") & LE32 (26 + 768 + 4) & LE32 (0)
            & LE32 (26 + 768) & LE32 (12) & LE16 (3) & LE16 (1) & LE16 (1)
            & LE16 (8) & Palette & [5, 6, 7, 0]);
      end;
      Check_Grey_Row (Read_Image (Name), 0, [5, 6, 7],
                      "core header 8-bit grey palette");

      --  A V5 header (124 bytes) with 24-bit pixels.
      Write_File
        (Name,
         To_Bytes ("BM") & LE32 (138 + 4) & LE32 (0) & LE32 (138)
         & LE32 (124) & LE32 (1) & LE32 (1) & LE16 (1) & LE16 (24)
         & LE32 (0) & LE32 (4) & LE32 (0) & LE32 (0) & LE32 (0) & LE32 (0)
         & Zeros (124 - 40) & [3, 2, 1, 0]);
      Check_Colour_Pixel (Read_Image (Name), 0, 0, 1, 2, 3, "V5 header");
   end Test_BMP_Variants;

   procedure Test_Malformed_PNM is
      Huge_Header : constant String := "P5 40000 40000 255" & LF;
   begin
      Section ("malformed PNM files");
      Check_Read_Fails ("img_bad_empty.pgm", Zeros (0), "empty file");
      Check_Read_Fails ("img_bad_magic.pgm", To_Bytes ("GIF89a"),
                        "unknown format");
      Check_Read_Fails ("img_bad_p.pgm", To_Bytes ("P"), "only 'P'");
      Check_Read_Fails ("img_bad_p5.pgm", To_Bytes ("P5"), "only magic");
      Check_Read_Fails ("img_bad_p5lf.pgm", To_Bytes ("P5" & LF),
                        "magic and newline");
      Check_Read_Fails ("img_bad_w.pgm", To_Bytes ("P5" & LF & "3"),
                        "width only");
      Check_Read_Fails ("img_bad_noeol.pgm", To_Bytes ("P5 3 2 255"),
                        "no whitespace after the maxval");
      Check_Read_Fails ("img_bad_comment.pgm", To_Bytes ("P5 3 2 255#x"),
                        "unterminated comment after the maxval");
      Check_Read_Fails ("img_bad_short.pgm",
                        To_Bytes ("P5 3 2 255" & LF) & [1, 2, 3, 4, 5],
                        "binary raster one byte short",
                        Reason => "truncated pixel data");
      Check_Read_Fails ("img_bad_short16.pgm",
                        To_Bytes ("P5 2 1 1000" & LF) & [1, 2, 3],
                        "16-bit raster one byte short",
                        Reason => "truncated pixel data");
      Check_Read_Fails ("img_bad_w0.pgm",
                        To_Bytes ("P5 0 2 255" & LF), "zero width");
      Check_Read_Fails ("img_bad_h0.pgm",
                        To_Bytes ("P5 2 0 255" & LF), "zero height");
      Check_Read_Fails ("img_bad_max0.pgm",
                        To_Bytes ("P5 1 1 0" & LF) & [0], "maxval 0");
      Check_Read_Fails ("img_bad_max65536.pgm",
                        To_Bytes ("P5 1 1 65536" & LF) & [0, 0],
                        "maxval 65536");
      Check_Read_Fails ("img_bad_colour16.ppm",
                        To_Bytes ("P6 1 1 65535" & LF) & Zeros (6),
                        "16-bit colour");
      Check_Read_Fails ("img_bad_x.pgm", To_Bytes ("P5 3x2 255" & LF),
                        "junk after the width");
      Check_Read_Fails ("img_bad_neg.pgm", To_Bytes ("P5 -3 2 255" & LF),
                        "negative width");
      Check_Read_Fails ("img_bad_magicsep.pgm", To_Bytes ("P53 2 255" & LF),
                        "no separator after the magic number");
      Check_Read_Fails ("img_bad_big.pgm",
                        To_Bytes ("P5 99999999999 1 255" & LF),
                        "width overflows");
      Check_Read_Fails ("img_bad_area.pgm",
                        To_Bytes ("P5 70000 70000 255" & LF) & Zeros (10),
                        "width * height too large");
      Check_Read_Fails ("img_bad_huge.pgm",
                        To_Bytes (Huge_Header) & Zeros (10),
                        "large size, tiny file (no huge allocation)",
                        Reason => "truncated pixel data: 1600000000 bytes");
      Check_Read_Fails ("img_bad_sample.pgm",
                        To_Bytes ("P2 2 1 255 1 300"),
                        "ASCII sample above the maxval");
      Check_Read_Fails ("img_bad_binsample.pgm",
                        To_Bytes ("P5 2 1 10" & LF) & [5, 20],
                        "binary sample above the maxval");
      Check_Read_Fails ("img_bad_bin16sample.pgm",
                        To_Bytes ("P5 1 1 1000" & LF) & [16#03#, 16#E9#],
                        "16-bit sample above the maxval");
      Check_Read_Fails ("img_bad_letter.pgm",
                        To_Bytes ("P2 2 1 255 1 a"),
                        "letter in an ASCII raster");
      Check_Read_Fails ("img_bad_glued.pgm",
                        To_Bytes ("P2 2 1 255 1 2x"),
                        "junk glued to an ASCII sample");
      Check_Read_Fails ("img_bad_ascii_short.pgm",
                        To_Bytes ("P2 3 1 255 1 2"),
                        "ASCII raster one sample short");
      Check_Read_Fails ("img_bad_ascii_short2.pgm",
                        To_Bytes ("P2 2 2 255 1 2 3 # 4"),
                        "ASCII raster ending in a comment");
      Check_Read_Fails ("img_bad_p1.pbm", To_Bytes ("P1 1 1 1"),
                        "P1 unsupported");
      Check_Read_Fails ("img_bad_p4.pbm", To_Bytes ("P4 8 1" & LF) & [0],
                        "P4 unsupported");
      Check_Read_Fails ("img_bad_p7.pam", To_Bytes ("P7" & LF & "WIDTH 1"),
                        "P7 unsupported");
      Check_Read_Fails ("img_bad_p9.pgm", To_Bytes ("P9 1 1 255" & LF & 'a'),
                        "unknown magic digit");
      Check_Read_Fails ("img_bad_trailing.pgm",
                        To_Bytes ("P5 1 1 255" & LF & 'A' & LF & "xyz"),
                        "garbage after the last image");
      Check_Read_Fails ("img_bad_second.pgm",
                        To_Bytes ("P5 1 1 255" & LF & 'A' & "P5 1 1"),
                        "truncated second image");
      Check_Read_Fails ("img_bad_second_zero.pgm",
                        To_Bytes ("P5 1 1 255" & LF & 'A' & "P5 0 1 255"
                                  & LF),
                        "bad second image");
   end Test_Malformed_PNM;

   procedure Test_Malformed_BMP is
      function Header
        (Offset, Width, Height : Big;
         Bits                  : Big;
         Compression           : Big := 0;
         Colours_Used          : Big := 0;
         Planes                : Big := 1;
         Header_Size           : Big := 40) return Stream_Element_Array is
        (To_Bytes ("BM") & LE32 (0) & LE32 (0) & LE32 (Offset)
         & LE32 (Header_Size) & LE32 (Width) & LE32 (Height)
         & LE16 (Planes) & LE16 (Bits) & LE32 (Compression) & LE32 (0)
         & LE32 (0) & LE32 (0) & LE32 (Colours_Used) & LE32 (0));
   begin
      Section ("malformed BMP files");
      Check_Read_Fails ("img_bad_bm.bmp", To_Bytes ("BM"), "only 'BM'");
      Check_Read_Fails ("img_bad_bmhdr.bmp",
                        To_Bytes ("BM") & Zeros (20), "truncated header");
      Check_Read_Fails ("img_bad_hsize.bmp",
                        Header (54, 1, 1, 24, Header_Size => 20) & Zeros (4),
                        "unsupported header size 20");
      Check_Read_Fails ("img_bad_hsize_big.bmp",
                        Header (54, 1, 1, 24, Header_Size => 1_000_000)
                        & Zeros (4),
                        "header size beyond the file");
      Check_Read_Fails ("img_bad_palette.bmp",
                        Header (1078, 2, 2, 8) & Zeros (100),
                        "truncated palette");
      Check_Read_Fails ("img_bad_pixels.bmp",
                        Header (54, 4, 4, 24) & Zeros (10),
                        "truncated pixel data",
                        Reason => "truncated BMP file: the pixel data");
      Check_Read_Fails ("img_bad_topdown.bmp",
                        Header (54, 4, -4, 24) & Zeros (47),
                        "truncated top-down pixel data",
                        Reason => "truncated BMP file: the pixel data");
      Check_Read_Fails ("img_bad_rle.bmp",
                        Header (54 + 1024, 2, 2, 8, Compression => 1)
                        & Zeros (1024 + 8),
                        "RLE compression");
      Check_Read_Fails ("img_bad_16bit.bmp",
                        Header (54, 2, 2, 16) & Zeros (8), "16-bit pixels");
      Check_Read_Fails ("img_bad_2bit.bmp",
                        Header (54 + 16, 2, 2, 2) & Zeros (32),
                        "2-bit pixels");
      Check_Read_Fails ("img_bad_bf24.bmp",
                        Header (66, 1, 1, 24, Compression => 3) & Zeros (16),
                        "bit fields with 24-bit pixels");
      Check_Read_Fails ("img_bad_masks.bmp",
                        Header (66, 1, 1, 32, Compression => 3)
                        & LE32 (16#0000_00FF#) & LE32 (16#0000_FF00#)
                        & LE32 (16#00FF_0000#) & Zeros (4),
                        "non-standard bit-field masks");
      Check_Read_Fails ("img_bad_width0.bmp",
                        Header (54, 0, 1, 24) & Zeros (4), "zero width");
      Check_Read_Fails ("img_bad_widthneg.bmp",
                        Header (54, -3, 1, 24) & Zeros (12), "negative width");
      Check_Read_Fails ("img_bad_height0.bmp",
                        Header (54, 1, 0, 24) & Zeros (4), "zero height");
      Check_Read_Fails ("img_bad_planes.bmp",
                        Header (54, 1, 1, 24, Planes => 2) & Zeros (4),
                        "two planes");
      Check_Read_Fails ("img_bad_index.bmp",
                        Header (62, 4, 1, 8, Colours_Used => 2)
                        & Zeros (8) & [0, 1, 5, 0],
                        "palette index beyond the palette");
      Check_Read_Fails ("img_bad_colours.bmp",
                        Header (54 + 1200, 1, 1, 8, Colours_Used => 300)
                        & Zeros (1200 + 4),
                        "more palette entries than 2 ** bits");
      Check_Read_Fails ("img_bad_offset.bmp",
                        Header (20, 1, 1, 24) & Zeros (4),
                        "pixel offset inside the header");
      Check_Read_Fails ("img_bad_offset_far.bmp",
                        Header (5000, 1, 1, 24) & Zeros (4),
                        "pixel offset beyond the file",
                        Reason => "truncated BMP file: the pixel data");
      Check_Read_Fails ("img_bad_area.bmp",
                        Header (54, 100_000, 100_000, 24) & Zeros (4),
                        "width * height too large");
      --  24 bits per pixel, so that no palette is needed and the size
      --  guard of the pixel data is what rejects the file (an 8-bit file
      --  this small fails earlier, at the palette). Without that guard the
      --  decoder would allocate 2.7 GB before failing.
      Check_Read_Fails ("img_bad_tiny.bmp",
                        Header (54, 30_000, 30_000, 24) & Zeros (4),
                        "large size, tiny file (no huge allocation)",
                        Reason => "truncated BMP file: the pixel data needs "
                                  & "2700000054 bytes");
      Check_Read_Fails ("img_bad_minint.bmp",
                        Header (54, 1, -2 ** 31, 24) & Zeros (4),
                        "height -2**31");
   end Test_Malformed_BMP;

   procedure Test_Tool is
      Name   : constant String := Path ("img_tool.pnm");
      Grey   : constant Ks_Image_8_Grey := Grey_Pattern (4, 3);
      Colour : Ks_Image_24_Planar_Color := Create (2, 1);
      Grey16 : Ks_Image_16_Grey := Create (2, 1);
      Tool   : Ks_Image_File_Tool;
   begin
      Section ("image file tool");
      Colour.Set_Pixel (0, 0, 255, 0, 0);
      Colour.Set_Pixel (1, 0, 0, 0, 250);
      Grey16.Set_Pixel (0, 0, 65_535);
      Grey16.Set_Pixel (1, 0, 257);

      --  Not open.
      Tool.Run;
      Check (Tool.Run_Status.Result = Error, "closed Operator: Error");
      Check (Tool.Run_Status.Exception_Name = "AMV.KS_IMAGE_FILE_EXCEPTION",
             "closed Operator: Ks_Image_File_Exception, got "
             & Tool.Run_Status.Exception_Name);

      --  Write mode appends Input_Image.
      Tool.Operator.Open (Name, Write);
      Tool.Input_Image := Grey;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "write run accepted");
      Check (Tool.Operator.Count = 1, "write run appended one image");
      Tool.Run;
      Check (Tool.Operator.Count = 2, "second write run");
      Check (not Tool.Output_Image.Allocated,
             "write mode does not set Output_Image");
      Tool.Operator.Append (Grey16);
      Tool.Operator.Append (Colour);
      declare
         Empty : Ks_Image_8_Grey;
      begin
         Tool.Input_Image := Empty;
      end;
      Tool.Run;
      Check (Tool.Run_Status.Result = Error,
             "write run without Input_Image fails");
      Check (Tool.Run_Status.Exception_Name
               = "AMV.KS_IMAGE_NO_PIXELS_EXCEPTION",
             "write run without Input_Image: no pixels, got "
             & Tool.Run_Status.Exception_Name);
      Check (Tool.Operator.Count = 4, "a failed run appends nothing");
      Tool.Operator.Close;

      --  Read mode cycles through the images, converted to 8-bit grey.
      Tool.Operator.Open (Name, Read);
      Check (Tool.Operator.Count = 4, "four images to read");
      Check (Tool.Next_Index = 0, "Next_Index starts at 0");
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "read run accepted");
      Check (Same (Tool.Output_Image, Grey), "run 1 outputs image 0");
      Check (Tool.Next_Index = 1, "Next_Index advanced to 1");
      Tool.Run;
      Check (Same (Tool.Output_Image, Grey), "run 2 outputs image 1");
      Tool.Run;
      Check_Grey_Row (Tool.Output_Image, 0, [255, 1],
                      "run 3 outputs the 16-bit image scaled");
      Tool.Run;
      Check_Grey_Row (Tool.Output_Image, 0, [76, 29],
                      "run 4 outputs the colour image as luma");
      Check (Tool.Next_Index = 0, "Next_Index wraps to 0");
      Tool.Run;
      Check (Same (Tool.Output_Image, Grey), "run 5 outputs image 0 again");
      Tool.Next_Index := 7;
      Tool.Run;
      Check_Grey_Row (Tool.Output_Image, 0, [76, 29],
                      "Next_Index 7 is taken modulo 4");
      Check (Tool.Next_Index = 0, "and wraps");

      --  The output is independent of the file's images.
      Tool.Next_Index := 0;
      Tool.Run;
      Tool.Output_Image.Fill (0);
      Tool.Next_Index := 0;
      Tool.Run;
      Check (Same (Tool.Output_Image, Grey),
             "changing an output does not change the file's image");

      --  Reset_Results clears Output_Image in Read mode only.
      Tool.Reset_Results;
      Check (not Tool.Output_Image.Allocated,
             "Reset_Results in Read mode clears Output_Image");
      Tool.Run;
      Tool.Operator.Open (Path ("img_tool_write.pgm"), Write);
      Tool.Reset_Results;
      Check (Tool.Output_Image.Allocated,
             "Reset_Results in Write mode keeps Output_Image");
      Tool.Input_Image := Grey;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "write run");
      Check (Tool.Output_Image.Allocated,
             "a write run keeps Output_Image");
      Tool.Operator.Close;
      Check (Same (Read_Image_8_Grey (Path ("img_tool_write.pgm")), Grey),
             "the tool wrote the image");
      Tool.Reset_Results;
      Check (Tool.Output_Image.Allocated,
             "Reset_Results with a closed Operator keeps Output_Image");

      --  Update mode on a BMP: the second run fails.
      Tool.Operator.Open (Path ("img_tool.bmp"), Write);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "first BMP run");
      Tool.Run;
      Check (Tool.Run_Status.Result = Error, "second BMP run fails");
      Check (Tool.Run_Status.Exception_Name = "AMV.KS_IMAGE_FILE_EXCEPTION",
             "second BMP run: file exception");
      Tool.Operator.Close;
      Tool.Operator.Open (Path ("img_tool.bmp"), Update);
      Tool.Run;
      Check (Tool.Run_Status.Result = Error,
             "Update mode run on a full BMP fails");
      Tool.Operator.Close;

      --  Copying a tool copies its file object.
      Tool.Operator.Open (Name, Read);
      Tool.Next_Index := 2;
      declare
         Copy_Of_Tool : Ks_Image_File_Tool := Tool;
      begin
         Tool.Operator.Close;
         Copy_Of_Tool.Run;
         Check (Copy_Of_Tool.Run_Status.Result = Accept_Result,
                "a copied tool still reads");
         Check_Grey_Row (Copy_Of_Tool.Output_Image, 0, [255, 1],
                         "copied tool outputs image 2");
         Check (Tool.Next_Index = 2, "the original's index is unchanged");
      end;
   end Test_Tool;

   --  An 8-bit image whose Width, an overridable primitive, raises while
   --  the trap is armed: the encoder asks for it after opening the file.

   Trap_Error : exception;
   Trap_Armed : Boolean := False;

   type Trap_Image is new Ks_Image_8_Grey with null record;

   overriding function Width (Image : Trap_Image) return Natural;

   overriding function Width (Image : Trap_Image) return Natural is
   begin
      if Trap_Armed then
         raise Trap_Error with "trap";
      end if;
      return Ks_Image_8_Grey (Image).Width;
   end Width;

   procedure Test_Files_Closed is
      --  Every failure must close the file again: GNAT refuses to open a
      --  name that is still open, so a file left open by a failed
      --  operation made every later read or write of that name fail.

      Grey : constant Ks_Image_8_Grey := Grey_Pattern (3, 2);
   begin
      Section ("files closed after a failure");

      --  Writing: an exception from the image itself, raised while the
      --  file is open, propagates unchanged and the file is closed.
      declare
         Name : constant String := Path ("img_closed_write.pgm");
         Trap : constant Trap_Image := (Grey_Pattern (4, 1) with null record);
         File : Ks_Image_File;
         Size : Big;

         procedure Append_Trap is
         begin
            File.Append (Trap);
         end Append_Trap;

         procedure T1 is new Check_Raises_Exactly
           (Append_Trap, Trap_Error'Identity);
      begin
         File.Open (Name, Write);
         Trap_Armed := True;
         T1 ("an exception raised by the image while writing (empty file)");
         Trap_Armed := False;
         Check (File.Count = 0, "Count unchanged after the exception");
         File.Append (Grey);
         Size := File_Size (Name);
         Trap_Armed := True;
         T1 ("an exception raised by the image while appending");
         Trap_Armed := False;
         Check (File.Count = 1 and then File_Size (Name) = Size,
                "Count and file unchanged after the exception");
         File.Close;
         Check (Same_Image (Read_Image (Name), Grey),
                "the file is closed: it can be read");
         Write_Image (Name, Grey_Pattern (5, 5));
         Check (Read_Image (Name).Width = 5,
                "the file is closed: it can be written again");
      exception
         when others =>
            Trap_Armed := False;
            raise;
      end;

      --  Reading: a file too large to be held in memory is reported as a
      --  file error, and the file is closed. The only portable way to get
      --  such a file is a sparse one, so this part runs only where one can
      --  be created and an allocation of its size really fails; elsewhere
      --  (Windows, whose file systems do not make files sparse by default,
      --  or a file system that limits the file size) it is skipped.
      declare
         Name   : constant String := Path ("img_closed_huge.pgm");
         Length : constant := 2 ** 48;
         Usable : Boolean := GNAT.OS_Lib.Directory_Separator = '/';

         procedure Remove is
         begin
            if Ada.Directories.Exists (Name) then
               Ada.Directories.Delete_File (Name);
            end if;
         end Remove;

         procedure Read_Huge is
            Image : constant Ks_Image'Class := Read_Image (Name);
         begin
            Check (not Image.Allocated, "unreachable");
         end Read_Huge;

         procedure T2 is new Check_Raises_Exactly (Read_Huge, File_Error);
      begin
         if Usable then
            declare
               File : SIO.File_Type;
            begin
               SIO.Create (File, SIO.Out_File, Name);
               SIO.Write (File, To_Bytes ("P5" & LF & "1 1" & LF & "255" & LF));
               SIO.Set_Index (File, Length);
               SIO.Write (File, [0]);
               SIO.Close (File);
            exception
               when others =>
                  if SIO.Is_Open (File) then
                     SIO.Close (File);
                  end if;
                  Usable := False;
            end;
         end if;
         if Usable then
            --  Make sure the library's allocation will fail: if it could
            --  succeed, the test would read the whole sparse file.
            declare
               type Unset_Bytes is array (Big range <>) of Stream_Element;
               pragma Suppress_Initialization (Unset_Bytes);
               type Unset_Access is access Unset_Bytes;
               procedure Free is new Ada.Unchecked_Deallocation
                 (Unset_Bytes, Unset_Access);
               Probe : Unset_Access;
            begin
               Probe := new Unset_Bytes (1 .. Length);
               Free (Probe);
               Usable := False;
            exception
               when Storage_Error =>
                  null;
            end;
         end if;
         if not Usable then
            Ada.Text_IO.Put_Line
              ("  (skipped: no sparse file of 2**48 bytes whose contents "
               & "cannot be allocated)");
         else
            T2 ("a file too large to read into memory");
            begin
               Read_Huge;
            exception
               when E : Ks_Image_File_Exception =>
                  Check (Contains (Ada.Exceptions.Exception_Message (E),
                                   ": the file is too large to read into "
                                   & "memory (281474976710656 bytes)"),
                         "the message gives the size: "
                         & Ada.Exceptions.Exception_Message (E));
               when others =>
                  null;  --  Already reported by T2.
            end;
            Write_Image (Name, Grey);
            Check (Same_Image (Read_Image (Name), Grey),
                   "the huge file was closed: its name can be written");
         end if;
         Remove;
      exception
         when others =>
            Remove;
            raise;
      end;
   end Test_Files_Closed;


   procedure Test_Streams is
      --  The stream attributes of a file object store its decoded images
      --  by value.

      Name     : constant String := Path ("img_stream.pnm");
      Name_16  : constant String := Path ("img_stream16.pgm");
      Saved    : constant String := Path ("img_file_object.bin");
      Grey     : constant Ks_Image_8_Grey := Grey_Pattern (3, 2);
      Colour   : constant Ks_Image_24_Planar_Color := Colour_Pattern (2, 2);
      File     : Ks_Image_File;
      Back     : Ks_Image_File;
      Store    : SIO.File_Type;
      Tool     : Ks_Image_File_Tool;
   begin
      Section ("file object streams");
      Write_Image (Name, Grey);
      File.Open (Name, Update);
      File.Append (Colour);
      File.Close;
      File.Open (Name, Read);
      SIO.Create (Store, SIO.Out_File, Saved);
      Ks_Image_File'Write (SIO.Stream (Store), File);
      SIO.Close (Store);
      File.Close;
      SIO.Open (Store, SIO.In_File, Saved);
      Ks_Image_File'Read (SIO.Stream (Store), Back);
      SIO.Close (Store);
      Check (Back.Open_Mode = Read and then Back.Count = 2
             and then Back.File_Name = Name, "the state is read back");
      Check (Same_Image (Back.Item (0), Grey)
             and then Same_Image (Back.Item (1), Colour),
             "the decoded images are read back");

      --  The maxval of a 16-bit image is kept: the tool converts with it.
      Write_File (Name_16,
                  To_Bytes ("P5 2 1 1000" & LF) & [3, 232, 1, 244]);
      Tool.Operator.Open (Name_16, Read);
      SIO.Create (Store, SIO.Out_File, Saved);
      Ks_Image_File'Write (SIO.Stream (Store), Tool.Operator);
      SIO.Close (Store);
      Tool.Operator.Close;
      SIO.Open (Store, SIO.In_File, Saved);
      Ks_Image_File'Read (SIO.Stream (Store), Tool.Operator);
      SIO.Close (Store);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result,
             "a tool runs on a file object read from a stream");
      Check_Grey_Row (Tool.Output_Image, 0, [255, 128],
                      "the maxval 1000 is read back");

      --  A closed file object reads back closed.
      File.Close;
      SIO.Create (Store, SIO.Out_File, Saved);
      Ks_Image_File'Write (SIO.Stream (Store), File);
      SIO.Close (Store);
      SIO.Open (Store, SIO.In_File, Saved);
      Ks_Image_File'Read (SIO.Stream (Store), Back);
      SIO.Close (Store);
      Check (not Back.Is_Open and then Back.Count = 0,
             "a closed file object reads back closed");
   end Test_Streams;

   procedure Run_All is
   begin
      Ada.Directories.Create_Path (Output_Dir);
      Test_PGM_Round_Trip;
      Test_PPM_And_PNM;
      Test_BMP_Round_Trip;
      Test_Multi_Image;
      Test_BMP_Single_Image;
      Test_Write_Errors;
      Test_File_Object_States;
      Test_Conversions;
      Test_PNM_Syntax;
      Test_BMP_Variants;
      Test_Malformed_PNM;
      Test_Malformed_BMP;
      Test_Tool;
      Test_Files_Closed;
      Test_Streams;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Image_File;
