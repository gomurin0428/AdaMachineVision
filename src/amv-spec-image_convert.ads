--  The image convert tool (AMV.Image_Processing.Image_Convert), as its
--  documentation defines it (include/amv_ip_geometry.h, "Image convert
--  tool"): "INTENSITY: a copy of an 8-bit image, the high byte of a 16-bit
--  one, (299 R + 587 G + 114 B + 500) / 1000 of a colour one; PLANEn: one
--  plane".
--
--  The mode INTENSITY_FROM_WEIGHTED_RGB is a formula in floating point,
--  which the specifications of floating point will state
--  (docs/PLATINUM.md); until then the kernel's own function stands for it.

pragma Validity_Checks ("F");

with Interfaces;

package AMV.Spec.Image_Convert
  with SPARK_Mode, Ghost
is
   pragma Pure;

   use type Interfaces.Unsigned_16;

   subtype Level is Interfaces.Unsigned_8;
   --  A grey level of an 8-bit image or plane, 0 .. 255.

   subtype Level_16 is Interfaces.Unsigned_16;
   --  A grey level of a 16-bit image, 0 .. 65535.

   function High_Byte (V : Level_16) return Level is (Level (V / 256));
   --  The intensity of a 16-bit pixel: its high byte.

   function Intensity (R, G, B : Level) return Level is
     (Level ((299 * Natural (R) + 587 * Natural (G) + 114 * Natural (B)
              + 500) / 1000));
   --  The intensity of a colour pixel.

   subtype Colour_Mode is Integer
     with Static_Predicate => Colour_Mode in 1 | 6 | 7 | 8;
   --  The run modes INTENSITY (1), PLANE0, PLANE1 and PLANE2 (6 .. 8).

   function Colour (Mode : Colour_Mode; R, G, B : Level) return Level is
     (if Mode = 6 then R
      elsif Mode = 7 then G
      elsif Mode = 8 then B
      else Intensity (R, G, B));
   --  The output pixel of a colour pixel in the mode.

end AMV.Spec.Image_Convert;
