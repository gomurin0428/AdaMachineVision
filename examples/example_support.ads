--  Helpers shared by the examples: synthetic images, so that the examples
--  run without image files, and number formatting for their reports.

with AMV;
with AMV.Images;
with AMV.Transforms;

package Example_Support is

   use AMV;

   procedure Paint
     (Image  : in out AMV.Images.Ks_Image_8_Grey;
      Inside : not null access function (U, V : Real) return Boolean;
      Pose   : AMV.Transforms.Ks_Transform_2D_Linear;
      Value  : AMV.Images.Grey_8);
   --  Paints the set of points (U, V) for which Inside is True, placed in
   --  the image by Pose (part coordinates to pixel space). Each pixel is
   --  sampled 4 x 4 times over its square (pixel (X, Y) covers
   --  [X - 0.5, X + 0.5] x [Y - 0.5, Y + 0.5]) and moves towards Value by
   --  the fraction of the samples that fall inside, so edges are
   --  anti-aliased as in a camera image.

   function Image (Value : Real; Aft : Natural := 1) return String;
   --  Value in fixed-point notation with Aft decimals, without leading
   --  spaces ("12.5", "-0.25").

end Example_Support;
