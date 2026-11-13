--  The kernel handles behind the pixel regions of AMV.Regions, for the
--  packages of the Ada API that pass a rasterised region to other kernels
--  (the vision tools pass it to their execute entry points, which take a
--  const ks_pixel_region *) and for programs that mix the Ada API with the
--  C API. Not part of the VisionPro-like API.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Kernels.Regions;

package AMV.Regions.Kernel_Regions is

   function Kernel_Handle
     (Region : Pixel_Region'Class)
      return access constant AMV.Kernels.Regions.Ks_Pixel_Region_Data;
   --  The handle of the region's pixels (C: const ks_pixel_region *); null
   --  for the empty region. Valid while Region exists and is not changed.

end AMV.Regions.Kernel_Regions;
