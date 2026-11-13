--  The kernel handles behind the images of AMV.Images, for the packages of
--  the Ada API that pass images to other kernels or get new images from
--  them (AMV.Image_File hands the pixels of an image to the encoders of
--  AMV.Kernels.Image_File and wraps the images its decoder returns) and
--  for programs that mix the Ada API with the C API. Not part of the
--  VisionPro-like API.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images.Image_Holders;
with AMV.Kernels.Images;
with AMV.Kernels.Transforms;

package AMV.Images.Kernel_Images is

   function Adopt
     (Handle : AMV.Kernels.Images.Ks_Image_8_Grey) return Ks_Image_8_Grey;
   --  A new image that takes over Handle, a handle the caller owns (from
   --  an entry point that returns a new handle; null gives an unallocated
   --  image), with the default coordinate space tree, selected space and
   --  pixel-from-root transform. The caller must not use or destroy Handle
   --  afterwards: it is destroyed with the last image that uses it, or at
   --  once when Adopt raises (Storage_Error, or the exception of an
   --  inconsistent handle).

   function Adopt
     (Handle : AMV.Kernels.Images.Ks_Image_16_Grey) return Ks_Image_16_Grey;

   function Adopt
     (Handle    : AMV.Kernels.Images.Ks_Image_8_Grey;
      Spaces_Of : Ks_Image'Class) return Ks_Image_8_Grey;
   --  As Adopt (Handle), with the coordinate space tree, the selected space
   --  name and the pixel-from-root transform of Spaces_Of (as stored, like
   --  Copy (Image, No_Pixels)). The tools use it for an output image that
   --  keeps the coordinate spaces of their input image.

   function Adopt_With_Pixel_From_Root
     (Handle          : AMV.Kernels.Images.Ks_Image_8_Grey;
      Spaces_Of       : Ks_Image'Class;
      Pixel_From_Root : AMV.Kernels.Transforms.Ks_Transform_2D_Linear)
      return Ks_Image_8_Grey;
   --  As Adopt (Handle, Spaces_Of), with the pixel-from-root transform
   --  Pixel_From_Root instead of that of Spaces_Of (checked as
   --  Set_Pixel_From_Root_Transform checks it). The tools that crop or
   --  resample use it for an output image whose root space names the same
   --  places as the input's.

   function Adopt
     (Handle           : AMV.Kernels.Images.Ks_Image_8_Grey;
      Spaces_Of        : Ks_Image'Class;
      Pixel_From_Input : AMV.Kernels.Transforms.Ks_Transform_2D_Linear)
      return Ks_Image_8_Grey;
   --  As Adopt (Handle, Spaces_Of), for an output whose pixel grid is the
   --  grid of Spaces_Of moved by Pixel_From_Input (the transform from the
   --  pixel coordinates of Spaces_Of to those of the new image, as a tool
   --  that turns or mirrors an image reports it): the new image's
   --  pixel-from-root transform is Pixel_From_Input composed with that of
   --  Spaces_Of, so that root coordinates ("@") name the same physical
   --  point in both images. Raises Ks_Bad_Parameter_Exception or
   --  Ks_Transform_Singular_Exception when the composition leaves the
   --  bounds of AMV.Transforms (Set_Pixel_From_Root_Transform); Handle is
   --  destroyed then too.

   function Adopt
     (Red_Handle, Green_Handle, Blue_Handle :
        AMV.Kernels.Images.Ks_Image_8_Grey)
      return Ks_Image_24_Planar_Color;
   --  The same for the three planes of a colour image (three planes of one
   --  size, or three nulls).

   function Kernel_Handle
     (Image : Ks_Image_8_Grey'Class)
      return access constant AMV.Kernels.Images.Ks_Image_8_Grey_Data;
   --  The handle of the image's pixels (C: const ks_image_8_grey *), for
   --  passing to entry points that read pixels; null for an unallocated
   --  image. Valid while the pixels have a user (Image or an image sharing
   --  them).

   function Kernel_Handle
     (Image : Ks_Image_16_Grey'Class)
      return access constant AMV.Kernels.Images.Ks_Image_16_Grey_Data;

   function Kernel_Plane
     (Image : Ks_Image_24_Planar_Color'Class;
      Plane : Ks_Image_Plane_Constants)
      return access constant AMV.Kernels.Images.Ks_Image_8_Grey_Data;
   --  The handle of one plane of a colour image.

   type Any_Image_Handles is record
      Grey_8  : access constant AMV.Kernels.Images.Ks_Image_8_Grey_Data;
      Grey_16 : access constant AMV.Kernels.Images.Ks_Image_16_Grey_Data;
      Red     : access constant AMV.Kernels.Images.Ks_Image_8_Grey_Data;
      Green   : access constant AMV.Kernels.Images.Ks_Image_8_Grey_Data;
      Blue    : access constant AMV.Kernels.Images.Ks_Image_8_Grey_Data;
   end record;
   --  The handles of an image of any type: the one of its type (the three
   --  planes for a colour image), null for the others.

   function Kernel_Handles
     (Image : AMV.Images.Image_Holders.Holder) return Any_Image_Handles;
   --  The handles of the image Image holds, for the entry points that take
   --  an image of any type (C: an ICogImage as five handles); all null
   --  for an empty holder, an unallocated image or a type derived from
   --  Ks_Image outside AMV.Images. Valid while Image holds the image.

end AMV.Images.Kernel_Images;
