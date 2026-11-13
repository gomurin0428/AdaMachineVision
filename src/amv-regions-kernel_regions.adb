pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

package body AMV.Regions.Kernel_Regions is

   function Kernel_Handle
     (Region : Pixel_Region'Class)
      return access constant AMV.Kernels.Regions.Ks_Pixel_Region_Data is
     (Region.Handle);

end AMV.Regions.Kernel_Regions;
