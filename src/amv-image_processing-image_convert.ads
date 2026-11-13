--  The image convert tool: the counterpart of CogImageConvertTool and its
--  run parameters CogImageConvertRunParams
--  (Cognex.VisionPro.ImageProcessing).
--
--     Tool.Input_Image := AMV.Images.Image_Holders.To_Holder (Colour);
--     Tool.Run_Params.Run_Mode := Intensity;
--     Tool.Run;
--     Grey := Tool.Output_Image;
--
--  Input_Image holds an image of any type (VisionPro: ICogImage; an empty
--  holder is an image without pixels). Output_Image is a new 8-bit image
--  of the same size with the input's coordinate space tree, selected space
--  and pixel-from-root transform. Run_Mode:
--
--  * Intensity (AMV's default): an 8-bit image is copied, a 16-bit image
--    gives its high byte, a colour image round (0.299 R + 0.587 G +
--    0.114 B);
--  * Plane_0, Plane_1, Plane_2: the red, green or blue plane of a colour
--    image;
--  * Intensity_From_Weighted_RGB: round (Wr R + Wg G + Wb B) with the
--    Intensity_From_Weighted_RGB_*_Weight components (0.299, 0.587, 0.114
--    by default), limited to 0 .. 255.
--
--  HSI, Intensity_From_Bayer, RGB_From_Bayer, HSI_From_Bayer, RGB,
--  Pixel_From_Range and Mask_From_Range are not implemented (AMV has no
--  colour output here, nor Bayer or range images), nor is the tool's
--  Region (the whole image is converted).
--
--  The work is done by the SPARK kernel AMV.Kernels.Image_Convert (C:
--  ks_image_convert_*, include/amv_ip_geometry.h), which proves every
--  output pixel equal to the formula of its mode.
--
--  Run fails (Run_Status Error, Output_Image unallocated) with
--  Ks_Image_No_Pixels_Exception for an empty holder or an unallocated
--  image ("InputImage has no pixels") and Ks_Bad_Parameter_Exception for
--  a mode that is not implemented or that needs a colour image ("RunParams
--  .RunMode Plane0 needs a colour InputImage") and run parameters out of
--  range.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Images.Image_Holders;
with AMV.Kernels;
with AMV.Kernels.Image_Convert;
with AMV.Tools;

package AMV.Image_Processing.Image_Convert is

   ---------------------------------------------------------------------
   --  Run parameters (CogImageConvertRunParams)
   ---------------------------------------------------------------------

   package KC renames AMV.Kernels.Image_Convert;

   subtype Ks_Image_Convert_Run_Mode_Constants is
     AMV.Kernels.Int32 range 1 .. 12;
   --  CogImageConvertRunModeConstants, with VisionPro's values.

   Intensity                   : constant Ks_Image_Convert_Run_Mode_Constants
     := KC.Run_Mode_Intensity;
   HSI                         : constant Ks_Image_Convert_Run_Mode_Constants
     := KC.Run_Mode_HSI;
   Intensity_From_Bayer        : constant Ks_Image_Convert_Run_Mode_Constants
     := KC.Run_Mode_Intensity_From_Bayer;
   RGB_From_Bayer              : constant Ks_Image_Convert_Run_Mode_Constants
     := KC.Run_Mode_RGB_From_Bayer;
   HSI_From_Bayer              : constant Ks_Image_Convert_Run_Mode_Constants
     := KC.Run_Mode_HSI_From_Bayer;
   Plane_0                     : constant Ks_Image_Convert_Run_Mode_Constants
     := KC.Run_Mode_Plane_0;
   Plane_1                     : constant Ks_Image_Convert_Run_Mode_Constants
     := KC.Run_Mode_Plane_1;
   Plane_2                     : constant Ks_Image_Convert_Run_Mode_Constants
     := KC.Run_Mode_Plane_2;
   RGB                         : constant Ks_Image_Convert_Run_Mode_Constants
     := KC.Run_Mode_RGB;
   Intensity_From_Weighted_RGB : constant Ks_Image_Convert_Run_Mode_Constants
     := KC.Run_Mode_Intensity_From_Weighted_RGB;
   Pixel_From_Range            : constant Ks_Image_Convert_Run_Mode_Constants
     := KC.Run_Mode_Pixel_From_Range;
   Mask_From_Range             : constant Ks_Image_Convert_Run_Mode_Constants
     := KC.Run_Mode_Mask_From_Range;

   subtype Ks_Image_Convert_Bayer_Type_Constants is
     AMV.Kernels.Int32 range 0 .. 3;
   --  CogImageConvertBayerTypeConstants (Cognex.VisionPro).

   GR : constant Ks_Image_Convert_Bayer_Type_Constants := KC.Bayer_Type_GR;
   RG : constant Ks_Image_Convert_Bayer_Type_Constants := KC.Bayer_Type_RG;
   BG : constant Ks_Image_Convert_Bayer_Type_Constants := KC.Bayer_Type_BG;
   GB : constant Ks_Image_Convert_Bayer_Type_Constants := KC.Bayer_Type_GB;

   subtype Ks_Image_Convert_Run_Params is KC.Ks_Image_Convert_Run_Params;
   --  The run parameters (CogImageConvertRunParams): Run_Mode (Intensity),
   --  Bayer_Type (GR), Share_Pels_If_Possible (0; accepted and ignored),
   --  the Intensity_From_Weighted_RGB_{Red,Green,Blue}_Weight (0.299,
   --  0.587, 0.114), Intensity_From_Bayer_{Red,Green,Blue}_Weight (the
   --  same) and Color_From_Bayer_{Red,Green,Blue}_Scale (1.0) components,
   --  every real within 1.0E150. VisionPro states no defaults; these are
   --  AMV's.

   ---------------------------------------------------------------------
   --  The tool (CogImageConvertTool)
   ---------------------------------------------------------------------

   type Ks_Image_Convert_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image  : AMV.Images.Image_Holders.Holder;
      --  An image of any type; empty: no image.
      Run_Params   : Ks_Image_Convert_Run_Params;
      Output_Image : AMV.Images.Ks_Image_8_Grey;
      --  Set by Run (read-only by convention); unallocated after a run
      --  that failed.
   end record;

   overriding procedure Execute (Tool : in out Ks_Image_Convert_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Image_Convert_Tool);

end AMV.Image_Processing.Image_Convert;
