pragma SPARK_Mode (Off);

with AMV.Kernels;

package body AMV.GigE_Vision_Bayer is
   package KI renames AMV.Kernels.Images;
   use type T.Native_Result;
   use type T.Frame_Status;
   use type T.Byte_Array_Access;
   use type T.Int32;
   use type T.Int64;
   use type T.Unsigned_32;
   use type T.Unsigned_64;

   --  The colour layout of a 2x2 window: 0 RGGB, 1 GRBG, 2 GBRG, 3 BGGR.
   --  Bit 0 is a shift of one column of RGGB, bit 1 a shift of one row.
   subtype Window_Layout is Natural range 0 .. 3;

   function Is_Bayer_8 (Pixel_Format : T.Unsigned_32) return Boolean is
     (Pixel_Format in Arv_Pixel_Format_Bayer_GR_8
                    | Arv_Pixel_Format_Bayer_RG_8
                    | Arv_Pixel_Format_Bayer_GB_8
                    | Arv_Pixel_Format_Bayer_BG_8);

   function Format_Layout (Pixel_Format : T.Unsigned_32) return Window_Layout
     with Pre => Is_Bayer_8 (Pixel_Format)
   is
   begin
      if Pixel_Format = Arv_Pixel_Format_Bayer_RG_8 then
         return 0;
      elsif Pixel_Format = Arv_Pixel_Format_Bayer_GR_8 then
         return 1;
      elsif Pixel_Format = Arv_Pixel_Format_Bayer_GB_8 then
         return 2;
      else
         return 3;
      end if;
   end Format_Layout;

   function Frame_Status (Frame : T.Frame_Observation) return T.Frame_Status
   is
      Pixel_Count : T.Int64;
   begin
      if Frame.Acquisition_Status /= T.Native_Success
        or else Frame.Buffer_Status /= T.Arv_Buffer_Status_Success
      then
         return T.Frame_Error;
      elsif Frame.Payload_Type /= T.Arv_Payload_Image then
         return T.Frame_Unsupported_Payload;
      elsif not Is_Bayer_8 (Frame.Pixel_Format) then
         return T.Frame_Unsupported_Format;
      elsif Frame.Width < 2 or else Frame.Height < 2 then
         return T.Frame_Invalid_Dimensions;
      end if;

      Pixel_Count := T.Int64 (Frame.Width) * T.Int64 (Frame.Height);
      if Pixel_Count > T.Max_Image_Pixels then
         return T.Frame_Too_Large;
      elsif Frame.Source_Size /= T.Unsigned_64 (Pixel_Count)
        or else T.Int64 (Frame.Byte_Count) /= Pixel_Count
        or else Frame.Bytes = null
        or else Frame.Bytes.all'First /= 1
        or else T.Int64 (Frame.Bytes.all'Length) /= Pixel_Count
      then
         return T.Frame_Invalid_Length;
      else
         return T.Frame_Success;
      end if;
   end Frame_Status;

   procedure Build_Grey
     (Frame  : T.Frame_Observation;
      Image  : out AMV.Kernels.Images.Ks_Image_8_Grey;
      Status : out T.Frame_Status)
   is
      Image_Status : AMV.Kernels.Ks_Status;
   begin
      Image := null;
      Status := Frame_Status (Frame);
      if Status /= T.Frame_Success then
         return;
      end if;

      KI.Create (Frame.Width, Frame.Height, 0, Image, Image_Status);
      if not AMV.Kernels.Succeeded (Image_Status) then
         Image := null;
         Status := T.Frame_Out_Of_Memory;
         return;
      end if;

      declare
         Width  : constant Positive := Positive (Frame.Width);
         Height : constant Positive := Positive (Frame.Height);
         Bytes  : T.Byte_Array renames Frame.Bytes.all;
         Base   : constant Window_Layout := Format_Layout (Frame.Pixel_Format);

         --  Width * Height <= Max_Image_Pixels, so Y * Width + X + 1 fits.
         function Sample (X, Y : Natural) return Natural is
           (Natural (Bytes (Y * Width + X + 1)));

         X0, Y0       : Natural;
         A, B, C, D   : Natural;
         Red, Blue    : Natural;
         Green_Sum    : Natural;
      begin
         for Y in 0 .. Height - 1 loop
            Y0 := (if Y + 1 < Height then Y else Y - 1);
            for X in 0 .. Width - 1 loop
               X0 := (if X + 1 < Width then X else X - 1);
               A := Sample (X0, Y0);
               B := Sample (X0 + 1, Y0);
               C := Sample (X0, Y0 + 1);
               D := Sample (X0 + 1, Y0 + 1);
               case Window_Layout
                 ((Base mod 2 + X0 mod 2) mod 2
                  + 2 * ((Base / 2 + Y0 mod 2) mod 2))
               is
                  when 0 =>  --  R G / G B
                     Red := A; Green_Sum := B + C; Blue := D;
                  when 1 =>  --  G R / B G
                     Red := B; Green_Sum := A + D; Blue := C;
                  when 2 =>  --  G B / R G
                     Red := C; Green_Sum := A + D; Blue := B;
                  when 3 =>  --  B G / G R
                     Red := D; Green_Sum := B + C; Blue := A;
               end case;
               Image.Pixels (Y, X) := KI.Grey_8
                 ((77 * Red + 75 * Green_Sum + 29 * Blue + 128) / 256);
            end loop;
         end loop;
      end;
   end Build_Grey;

end AMV.GigE_Vision_Bayer;
