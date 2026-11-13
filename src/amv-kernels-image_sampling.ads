--  Helpers shared by the kernels of the image processing geometry tools
--  (AMV.Kernels.Affine_Transform, Copy_Region, IP_Two_Image,
--  Image_Convert and Polar_Unwrap): the checks of their input images, the
--  mapping of output pixel centres into an input image, nearest-neighbour
--  and bilinear sampling with a fill value, and the conversions of real
--  values to grey levels. Internal: not an entry point (no export), so
--  the package is private to the kernels.
--
--  Sampling. A sample point (PX, PY) in pixel space lies inside an image
--  of Width x Height pixels when it lies in the area the pixels cover,
--  [-0.5, Width - 0.5] x [-0.5, Height - 0.5] (borders included). A point
--  outside gets the fill value in every sampling mode, so both modes fill
--  the same output pixels. Inside, nearest-neighbour sampling takes the
--  pixel whose square holds the point (Floor (P + 0.5) per axis, the last
--  pixel for a point on the far border), and bilinear sampling
--  interpolates between the four nearest pixel centres after limiting the
--  point to [0, Width - 1] x [0, Height - 1] (so the border pixels are
--  repeated within the outer half pixel), rounded to the nearest grey
--  level. No index is ever formed for a point outside the image.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Images;
with AMV.Kernels.Numerics;
with AMV.Kernels.Transforms;

private package AMV.Kernels.Image_Sampling with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KT renames AMV.Kernels.Transforms;
   package N renames AMV.Kernels.Numerics;

   use type KI.Grey_8;

   ---------------------------------------------------------------------
   --  Input images
   ---------------------------------------------------------------------

   function Usable_Image
     (Image : access constant KI.Ks_Image_8_Grey_Data) return Boolean
   is
     (KI.Valid_Image (Image)
      and then Int64 (Image.Width) * Int64 (Image.Height) <= KI.Max_Pixels);
   --  A valid handle whose size is within the limit of the image kernel
   --  (every handle ks_image_8_grey_create returns).

   function Usable_Image
     (Image : access constant KI.Ks_Image_16_Grey_Data) return Boolean
   is
     (KI.Valid_Image (Image)
      and then Int64 (Image.Width) * Int64 (Image.Height) <= KI.Max_Pixels);

   type Image_Role is
     (Input_Image, Input_Image_A, Input_Image_B);
   --  The property an image argument stands for, named in the messages
   --  ("InputImageA has no pixels").

   procedure Check_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Role   : Image_Role;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Usable_Image (Image));
   --  Image_No_Pixels for null ("InputImage has no pixels"), Bad_Parameter
   --  for a record that is not a usable handle ("InputImage is not a valid
   --  image handle"), with the property Role names.

   ---------------------------------------------------------------------
   --  Mapping output pixels into an input image
   ---------------------------------------------------------------------

   Point_Limit : constant := 2.0 ** 1022;
   --  A bound of every mapped point: a transform within 1.0E150 applied
   --  to coordinates within Numerics.Mul_Limit (about 3.4E153).

   function Map_X
     (T    : KT.Ks_Transform_2D_Linear;
      X, Y : Long_Float) return Long_Float
   with
     Pre  => KT.Bounded (T)
             and then abs X <= N.Mul_Limit and then abs Y <= N.Mul_Limit,
     Post => abs Map_X'Result <= Point_Limit;
   --  T.A * X + T.B * Y + T.Translation_X, as
   --  ks_transform_2d_linear_map_point computes it.

   function Map_Y
     (T    : KT.Ks_Transform_2D_Linear;
      X, Y : Long_Float) return Long_Float
   with
     Pre  => KT.Bounded (T)
             and then abs X <= N.Mul_Limit and then abs Y <= N.Mul_Limit,
     Post => abs Map_Y'Result <= Point_Limit;
   --  T.C * X + T.D * Y + T.Translation_Y.

   ---------------------------------------------------------------------
   --  Sampling (see the head of this package)
   ---------------------------------------------------------------------

   function Inside_Area
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      PX, PY : Long_Float) return Boolean
   is
     (PX >= -0.5 and then PX <= Long_Float (Image.Width) - 0.5
      and then PY >= -0.5 and then PY <= Long_Float (Image.Height) - 0.5)
   with Pre => KI.Valid_Image (Image);
   --  (PX, PY) lies in the area the pixels of Image cover.

   function Nearest_Index (P : Long_Float; Size : Int32) return Natural
   with
     Pre  => Size >= 1
             and then P >= -0.5 and then P <= Long_Float (Size) - 0.5,
     Post => Nearest_Index'Result <= Natural (Size - 1);
   --  The pixel whose square holds P along one axis: Floor (P + 0.5),
   --  limited to Size - 1 (a point on the far border).

   function Nearest_Sample
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      PX, PY : Long_Float;
      Fill   : KI.Grey_8) return KI.Grey_8
   is
     (if Inside_Area (Image, PX, PY)
      then Image.Pixels (Nearest_Index (PY, Image.Height),
                         Nearest_Index (PX, Image.Width))
      else Fill)
   with Pre => KI.Valid_Image (Image);
   --  Nearest-neighbour sampling (Gold: an input pixel or the fill value,
   --  by its very definition).

   function Bilinear_Sample
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      PX, PY : Long_Float;
      Fill   : KI.Grey_8) return KI.Grey_8
   with
     Pre  => KI.Valid_Image (Image),
     Post => (if not Inside_Area (Image, PX, PY)
              then Bilinear_Sample'Result = Fill);
   --  Bilinear sampling, rounded to the nearest grey level (halves up).

   ---------------------------------------------------------------------
   --  Grey levels
   ---------------------------------------------------------------------

   function To_Grey (V : Long_Float) return KI.Grey_8 is
     (if not (V > 0.0) then 0
      elsif V >= 255.0 then 255
      else KI.Grey_8 (Int32 (V)));
   --  V rounded to the nearest integer (halves away from zero) and
   --  limited to 0 .. 255 (0 for a NaN at run time).

end AMV.Kernels.Image_Sampling;
