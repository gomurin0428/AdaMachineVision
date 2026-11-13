pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

package body AMV.Shapes.Kernel_Shapes is

   package K renames AMV.Kernels.Shapes;

   function Kernel_Type (Region : Ks_Region'Class) return AMV.Kernels.Int32
   is
     (if Region in Ks_Rectangle'Class then K.Shape_Rectangle
      elsif Region in Ks_Rectangle_Affine'Class
      then K.Shape_Rectangle_Affine
      elsif Region in Ks_Circle'Class then K.Shape_Circle
      elsif Region in Ks_Ellipse'Class then K.Shape_Ellipse
      elsif Region in Ks_Polygon'Class then K.Shape_Polygon
      elsif Region in Ks_Circular_Annulus_Section'Class
      then K.Shape_Circular_Annulus_Section
      else 0);

   function Kernel_Rectangle
     (Rectangle : Ks_Rectangle'Class) return K.Ks_Rectangle is
     (Rectangle.Data);

   function Kernel_Rectangle_Affine
     (Rectangle : Ks_Rectangle_Affine'Class) return K.Ks_Rectangle_Affine is
     (Rectangle.Data);

   function Kernel_Circle (Circle : Ks_Circle'Class) return K.Ks_Circle is
     (Circle.Data);

   function Kernel_Ellipse (Ellipse : Ks_Ellipse'Class) return K.Ks_Ellipse
   is (Ellipse.Data);

   function Kernel_Circular_Annulus_Section
     (Section : Ks_Circular_Annulus_Section'Class)
      return K.Ks_Circular_Annulus_Section is
     (Section.Data);

   function Kernel_Polygon
     (Polygon : Ks_Polygon'Class)
      return access constant K.Ks_Polygon_Data is
     (Polygon.Vertices.Handle);

   function Adopt (Handle : AMV.Kernels.Shapes.Ks_Polygon) return Ks_Polygon
   is
   begin
      return Result : Ks_Polygon do
         Result.Vertices.Handle := Handle;
      end return;
   end Adopt;

end AMV.Shapes.Kernel_Shapes;
