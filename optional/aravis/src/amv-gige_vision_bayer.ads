pragma SPARK_Mode (Off);

with AMV.GigE_Vision_Types;
with AMV.Kernels.Images;

--  Bayer8 to grey conversion for the optional GigE Vision adapter. It runs
--  after the proved Mono8 engine has rejected a frame only for its pixel
--  format; it is tested, not part of the SPARK proof.
package AMV.GigE_Vision_Bayer is
   package T renames AMV.GigE_Vision_Types;

   Arv_Pixel_Format_Bayer_GR_8 : constant T.Unsigned_32 := 16#0108_0008#;
   Arv_Pixel_Format_Bayer_RG_8 : constant T.Unsigned_32 := 16#0108_0009#;
   Arv_Pixel_Format_Bayer_GB_8 : constant T.Unsigned_32 := 16#0108_000A#;
   Arv_Pixel_Format_Bayer_BG_8 : constant T.Unsigned_32 := 16#0108_000B#;

   function Is_Bayer_8 (Pixel_Format : T.Unsigned_32) return Boolean;
   --  True for the four packed 8-bit Bayer formats.

   function Frame_Status (Frame : T.Frame_Observation) return T.Frame_Status;
   --  Frame_Success for a successfully acquired image payload in a Bayer8
   --  format, at least 2x2, at most Max_Image_Pixels, whose bytes are
   --  exactly Width * Height packed samples; otherwise the first failing
   --  check, in the order of the Mono8 engine.

   procedure Build_Grey
     (Frame  : T.Frame_Observation;
      Image  : out AMV.Kernels.Images.Ks_Image_8_Grey;
      Status : out T.Frame_Status);
   --  Converts a Bayer8 frame to a grey image of the same size. The output
   --  pixel (X, Y) is the BT.601 luma of the 2x2 window whose top-left
   --  sample is (X, Y), moved one sample left at the last column and one
   --  up at the last row: (77 R + 75 (G1 + G2) + 29 B + 128) / 256. Each
   --  window holds one red, two green and one blue sample. Image is null
   --  unless Status is Frame_Success.

end AMV.GigE_Vision_Bayer;
