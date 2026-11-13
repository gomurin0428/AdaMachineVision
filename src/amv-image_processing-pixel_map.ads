--  The pixel map tool: a lookup table applied to the pixels of a region.
--  VisionPro offers this operation as CogIPOneImagePixelMap, an operator of
--  CogIPOneImageTool; AMV also offers it as a tool of its own,
--  Ks_Pixel_Map_Tool (an AMV name: VisionPro 9.23 has no CogPixelMapTool),
--  whose run parameters are the operator's (Ks_IP_One_Image_Pixel_Map:
--  GetMap / SetMap).
--
--     Tool.Input_Image := Image;
--     Tool.Run_Params.Map (0) := 255;    --  or Set_Map (Tool.Run_Params, M)
--     Tool.Run;
--     Out := Tool.Output_Image;
--
--  Output_Image is a new image of the size of Input_Image with its
--  coordinate space tree, selected space and pixel-from-root transform:
--  every pixel the Region covers (AMV.Regions.Rasterize; an empty Region
--  holder means the whole image) is replaced by Map (its value), every
--  other pixel is copied. A region that covers no pixel centre of the
--  image gives an unchanged copy (no exception).
--
--  The work is done by the SPARK kernel AMV.Kernels.Pixel_Map (C:
--  ks_pixel_map_*, include/amv_image_processing.h), which proves exactly
--  that: every output pixel in the region is Map (input pixel), every
--  other one the input pixel.
--
--  Run fails (Run_Status Error, Output_Image unallocated) with
--  Ks_Image_No_Pixels_Exception for an unallocated Input_Image ("InputImage
--  has no pixels") and Ks_Image_Bad_Selected_Space_Name_Exception for a
--  region in an unknown space.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels.Pixel_Map;
with AMV.Shapes.Region_Holders;
with AMV.Tools;

package AMV.Image_Processing.Pixel_Map is

   subtype Pixel_Map_Table is AMV.Kernels.Pixel_Map.Pixel_Map_Table;
   --  array (AMV.Images.Grey_8) of AMV.Images.Grey_8: the value each grey
   --  level is replaced by.

   Identity_Map : constant Pixel_Map_Table :=
     AMV.Kernels.Pixel_Map.Identity_Map;

   subtype Ks_IP_One_Image_Pixel_Map is
     AMV.Kernels.Pixel_Map.Ks_IP_One_Image_Pixel_Map;
   --  The run parameters (CogIPOneImagePixelMap): a record with the one
   --  component Map (default Identity_Map).

   function Get_Map (Params : Ks_IP_One_Image_Pixel_Map)
      return Pixel_Map_Table;
   --  A copy of the map (VisionPro: GetMap).

   procedure Set_Map
     (Params : in out Ks_IP_One_Image_Pixel_Map;
      Map    : Pixel_Map_Table);
   --  Replaces the map (VisionPro: SetMap).

   type Ks_Pixel_Map_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image  : AMV.Images.Ks_Image_8_Grey;
      Region       : AMV.Shapes.Region_Holders.Holder;
      --  Empty: the whole image.
      Run_Params   : Ks_IP_One_Image_Pixel_Map;
      Output_Image : AMV.Images.Ks_Image_8_Grey;
      --  Set by Run (read-only by convention); unallocated after a run
      --  that failed.
   end record;

   overriding procedure Execute (Tool : in out Ks_Pixel_Map_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Pixel_Map_Tool);

end AMV.Image_Processing.Pixel_Map;
