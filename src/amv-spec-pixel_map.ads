--  The pixel map tool (AMV.Image_Processing.Pixel_Map), as its
--  documentation defines it (include/amv_image_processing.h, "Pixel map
--  tool"): "A new image of the size of image: map[value] for the pixels
--  of the region, the input value elsewhere."

pragma Validity_Checks ("F");

with Interfaces;

package AMV.Spec.Pixel_Map
  with SPARK_Mode, Ghost
is
   pragma Pure;

   subtype Level is Interfaces.Unsigned_8;
   --  A grey level, 0 .. 255.

   type Table is array (Level) of Level;
   --  The run parameter map: the value each grey level is replaced by.

   function Mapped
     (Map    : Table;
      Inside : Boolean;
      Value  : Level) return Level
   is
     (if Inside then Map (Value) else Value);
   --  The output pixel of an input pixel of level Value, Inside: the
   --  pixel is one of the region.

end AMV.Spec.Pixel_Map;
