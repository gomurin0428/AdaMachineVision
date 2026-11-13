--  The copy region tool: the counterpart of CogCopyRegionTool and its run
--  parameters CogCopyRegion (Cognex.VisionPro.ImageProcessing).
--
--     Tool.Input_Image := Image;
--     Tool.Region := AMV.Shapes.Region_Holders.To_Holder (Circle);
--     Tool.Run;
--     Out := Tool.Output_Image;   --  the circle's bounding box, 0 outside
--
--  Output_Image is a new image of the size of the region's pixel-aligned
--  bounding box (the pixels AMV.Regions.Rasterize gives for Region; an
--  empty holder means the whole image): the pixels of the region are
--  copied from Input_Image (or set to Fill_Region_Value when Fill_Region
--  is on), the other pixels of the box are set to Fill_Bounding_Box_Value
--  when Fill_Bounding_Box is on (the default) and copied otherwise.
--  Region_Mode Pixel_Aligned_Bounding_Box counts every pixel of the box as
--  the region's. The output keeps the input's coordinate space tree and
--  selected space and gets a pixel-from-root transform shifted by the
--  corner of the box, so every space names the same physical places in
--  both images.
--
--  VisionPro can copy into an existing DestinationImage with an alignment
--  of the two images; AMV always makes a new image (no Destination_Image,
--  no alignment, no SourceClipped / DestinationClipped / DestinationRegion).
--
--  The work is done by the SPARK kernel AMV.Kernels.Copy_Region (C:
--  ks_copy_region_*, include/amv_ip_geometry.h), which proves that every
--  output pixel is the input pixel at its place or the documented fill.
--
--  Run fails (Run_Status Error, Output_Image unallocated) with
--  Ks_Image_No_Pixels_Exception for an unallocated Input_Image ("InputImage
--  has no pixels"), Ks_Image_Bad_Selected_Space_Name_Exception for a region
--  in an unknown space, and Ks_Bad_Parameter_Exception for a region that
--  covers no pixel centre of the image ("Region covers no pixel of
--  InputImage") and for run parameters out of range.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Copy_Region;
with AMV.Shapes.Region_Holders;
with AMV.Tools;

package AMV.Image_Processing.Copy_Region is

   ---------------------------------------------------------------------
   --  Run parameters (CogCopyRegion)
   ---------------------------------------------------------------------

   subtype Ks_Region_Mode_Constants is AMV.Kernels.Int32 range 0 .. 2;
   --  CogRegionModeConstants (Cognex.VisionPro), with VisionPro's values.

   Pixel_Aligned_Bounding_Box_Adjust_Mask :
     constant Ks_Region_Mode_Constants :=
       AMV.Kernels.Copy_Region
         .Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask;
   --  The default: only the region's pixels count as the region.
   Pixel_Aligned_Bounding_Box : constant Ks_Region_Mode_Constants :=
     AMV.Kernels.Copy_Region.Region_Mode_Pixel_Aligned_Bounding_Box;
   --  Every pixel of the bounding box counts as the region.
   Affine_Transform : constant Ks_Region_Mode_Constants :=
     AMV.Kernels.Copy_Region.Region_Mode_Affine_Transform;
   --  Not implemented (Run fails with Ks_Bad_Parameter_Exception).

   subtype Ks_Copy_Region is AMV.Kernels.Copy_Region.Ks_Copy_Region;
   --  The run parameters (CogCopyRegion), a record with VisionPro's
   --  defaults: Fill_Bounding_Box (1), Fill_Bounding_Box_Value (0),
   --  Fill_Region (0), Fill_Region_Value (255) and Region_Mode
   --  (Pixel_Aligned_Bounding_Box_Adjust_Mask). The flags are Int32 codes
   --  0 or 1 (use the setters below); the values lie in 0 .. 255. Values
   --  are checked when the tool runs.

   procedure Set_Fill_Bounding_Box
     (Params : in out Ks_Copy_Region; Value : Boolean);
   --  FillBoundingBox.

   procedure Set_Fill_Region (Params : in out Ks_Copy_Region; Value : Boolean);
   --  FillRegion.

   ---------------------------------------------------------------------
   --  The tool (CogCopyRegionTool)
   ---------------------------------------------------------------------

   type Ks_Copy_Region_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image  : AMV.Images.Ks_Image_8_Grey;
      Region       : AMV.Shapes.Region_Holders.Holder;
      --  Empty: the whole image.
      Run_Params   : Ks_Copy_Region;
      Output_Image : AMV.Images.Ks_Image_8_Grey;
      --  Set by Run (read-only by convention); unallocated after a run
      --  that failed.
   end record;

   overriding procedure Execute (Tool : in out Ks_Copy_Region_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Copy_Region_Tool);

end AMV.Image_Processing.Copy_Region;
