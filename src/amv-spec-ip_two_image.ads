--  The two-image tools (AMV.Image_Processing.IP_Two_Image), as their
--  documentation defines them (include/amv_ip_geometry.h, "Two-image
--  tools"): each output pixel is the formula of the tool applied to the
--  grey levels A of InputImageA and B of InputImageB at its place.
--
--  * Add, OverflowMode: Bounded (0) min (A + B, 255); Wrap (1)
--    (A + B) mod 256; Shift (2) (A + B) / 2, rounded down.
--  * Subtract, OverflowMode: Bounded (0) max (A - B, 0); Wrap (1)
--    (A - B) mod 256; Shift (2) (A - B + 256) / 2, rounded down;
--    Absolute (3) abs (A - B).
--  * MinMax, Operation: Min (0) min (A, B); Max (1) max (A, B).
--
--  The formulas are written on the integers, as the documentation states
--  them; the levels are 0 .. 255.

pragma Validity_Checks ("F");

with Interfaces;

package AMV.Spec.IP_Two_Image
  with SPARK_Mode, Ghost
is
   pragma Pure;

   subtype Level is Interfaces.Unsigned_8;
   --  A grey level, 0 .. 255.

   subtype Add_Mode is Integer range 0 .. 2;
   subtype Subtract_Mode is Integer range 0 .. 3;
   subtype Min_Max_Operation is Integer range 0 .. 1;
   --  The codes of the run parameters.

   function Add (Mode : Add_Mode; A, B : Level) return Level is
     (case Mode is
         when 0 => Level (Integer'Min (Integer (A) + Integer (B), 255)),
         when 1 => Level ((Integer (A) + Integer (B)) mod 256),
         when 2 => Level ((Integer (A) + Integer (B)) / 2));

   function Subtract (Mode : Subtract_Mode; A, B : Level) return Level is
     (case Mode is
         when 0 => Level (Integer'Max (Integer (A) - Integer (B), 0)),
         when 1 => Level ((Integer (A) - Integer (B)) mod 256),
         when 2 => Level ((Integer (A) - Integer (B) + 256) / 2),
         when 3 => Level (abs (Integer (A) - Integer (B))));

   function Min_Max (Operation : Min_Max_Operation; A, B : Level)
      return Level
   is
     (case Operation is
         when 0 => Level'Min (A, B),
         when 1 => Level'Max (A, B));

end AMV.Spec.IP_Two_Image;
