--  Helpers shared by the examples: synthetic images, so that the first
--  examples run without image files, the loading of the real images of
--  examples/real_images, and number formatting for the reports.

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

   Missing_Image : exception;

   function Real_Image_File (Name : String) return String;
   --  The path of the image file Name ("coins.bmp") of the real-image
   --  examples: in the directory named by the environment variable
   --  AMV_REAL_IMAGES, build/real-images by default (make
   --  fetch-real-images puts the images there). Raises Missing_Image,
   --  with a message that says so, when the file is not there.

   function Real_Image (Name : String) return AMV.Images.Ks_Image_8_Grey;
   --  That file as 8-bit grey.

   function Image (Value : Real; Aft : Natural := 1) return String;
   --  Value in fixed-point notation with Aft decimals, without leading
   --  spaces ("12.5", "-0.25").

end Example_Support;
