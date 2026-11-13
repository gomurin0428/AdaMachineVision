--  The kernel values behind the regions of AMV.Shapes, for the packages of
--  the Ada API that pass regions to other kernels (AMV.Regions hands them
--  to the rasteriser of AMV.Kernels.Regions) and for programs that mix the
--  Ada API with the C API. Not part of the VisionPro-like API.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Kernels.Shapes;

package AMV.Shapes.Kernel_Shapes is

   function Kernel_Type (Region : Ks_Region'Class) return AMV.Kernels.Int32;
   --  The kernel's shape code of Region's type (AMV.Kernels.Shapes:
   --  Shape_Rectangle, ...; C: KS_SHAPE_*), also for a type derived from
   --  one of the region types of AMV.Shapes; 0 for any other type derived
   --  from Ks_Region.

   function Kernel_Rectangle
     (Rectangle : Ks_Rectangle'Class) return AMV.Kernels.Shapes.Ks_Rectangle;
   --  The geometry of the region as the kernel's record (C: ks_rectangle).

   function Kernel_Rectangle_Affine
     (Rectangle : Ks_Rectangle_Affine'Class)
      return AMV.Kernels.Shapes.Ks_Rectangle_Affine;

   function Kernel_Circle
     (Circle : Ks_Circle'Class) return AMV.Kernels.Shapes.Ks_Circle;

   function Kernel_Ellipse
     (Ellipse : Ks_Ellipse'Class) return AMV.Kernels.Shapes.Ks_Ellipse;

   function Kernel_Circular_Annulus_Section
     (Section : Ks_Circular_Annulus_Section'Class)
      return AMV.Kernels.Shapes.Ks_Circular_Annulus_Section;

   function Kernel_Polygon
     (Polygon : Ks_Polygon'Class)
      return access constant AMV.Kernels.Shapes.Ks_Polygon_Data;
   --  The handle of the polygon's vertices (C: const ks_polygon *), for
   --  passing to entry points that read them; null for a polygon without
   --  vertices. Valid while Polygon exists and is not changed.

   function Adopt (Handle : AMV.Kernels.Shapes.Ks_Polygon) return Ks_Polygon;
   --  A new polygon (selected space ".") that takes over Handle, a handle
   --  the caller owns (from an entry point that returns a new polygon,
   --  such as ks_blob_results_get_boundary; null gives a polygon without
   --  vertices). The caller must not use or destroy Handle afterwards.

end AMV.Shapes.Kernel_Shapes;
