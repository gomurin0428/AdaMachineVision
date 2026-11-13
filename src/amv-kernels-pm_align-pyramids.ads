--  The gradient pyramids of AMV.Kernels.PM_Align: a window of an 8-bit
--  image smoothed and reduced level by level, with the gradient of each
--  level and, for the search, the quantised gradient directions of the
--  pixels that belong to the search region.
--
--  Every image of a pyramid comes from the proved entry points of
--  AMV.Kernels.Image_Math (the gradients) and AMV.Kernels.Images (the
--  directions), so this package needs no allocation of its own. Values
--  read from them go through limits that never act (docs/PROOF.md).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Image_Math;
with AMV.Kernels.PM_Align.Poses;

private package AMV.Kernels.PM_Align.Pyramids
  with SPARK_Mode, Preelaborate
is

   package KM renames AMV.Kernels.Image_Math;
   package P renames AMV.Kernels.PM_Align.Poses;

   use type KM.Ks_Real_Image;
   use type KI.Ks_Image_8_Grey;

   Smoothing_Sigma : constant := 1.0;
   --  The Gaussian applied to the window and before every reduction.

   Grad_Limit : constant := 256.0;
   --  The limit of every gradient value read: a Sobel derivative divided
   --  by 8 of grey levels (and of their smoothed and averaged values) is
   --  at most 127.5 in magnitude, so the limit never acts.

   Neutral : constant := 127;
   --  The value of a direction image for "no direction".

   subtype Grad_Value is Long_Float range -Grad_Limit .. Grad_Limit;

   type Level_Data is record
      GX, GY : KM.Ks_Real_Image;
      DX, DY : KI.Ks_Image_8_Grey;
   end record;
   --  One level: the gradient (GX, GY, grey levels per pixel of the
   --  level) and, for the search, the directions: Neutral + 127 times the
   --  unit gradient, rounded, for a pixel whose gradient magnitude reaches
   --  the threshold and whose centre lies in the region, Neutral (0 after
   --  the subtraction) otherwise.

   function Usable (L : Level_Data) return Boolean is
     (KM.Has_Pixels (L.GX) and then KM.Has_Pixels (L.GY)
      and then L.GY.Width = L.GX.Width and then L.GY.Height = L.GX.Height);
   --  The gradient images exist and have one size.

   function Has_Directions (L : Level_Data) return Boolean is
     (Usable (L)
      and then KI.Valid_Image (L.DX) and then KI.Valid_Image (L.DY)
      and then L.DX.Width = L.GX.Width and then L.DX.Height = L.GX.Height
      and then L.DY.Width = L.GX.Width
      and then L.DY.Height = L.GX.Height);
   --  The direction images exist too, with the same size.

   type Level_Data_Array is array (Level_Index) of Level_Data;

   type Window is record
      X_Min, Y_Min  : Int32 := 0;
      Width, Height : Int32 := 0;
   end record;
   --  The part of the image a pyramid covers: level-0 pixel (0, 0) is
   --  image pixel (X_Min, Y_Min).

   function Window_In_Image
     (Area  : Window;
      Image : access constant KI.Ks_Image_8_Grey_Data) return Boolean
   is (KI.Valid_Image (Image)
       and then Area.X_Min >= 0 and then Area.Y_Min >= 0
       and then Area.Width >= 1 and then Area.Height >= 1
       and then Int64 (Area.X_Min) + Int64 (Area.Width)
                  <= Int64 (Image.Width)
       and then Int64 (Area.Y_Min) + Int64 (Area.Height)
                  <= Int64 (Image.Height));

   type Pyramid is record
      Count  : Natural range 0 .. Max_Levels := 0;
      Area   : Window;
      Levels : Level_Data_Array;
      Work_A : KM.Ks_Real_Image;
      Work_B : KM.Ks_Real_Image;
   end record;
   --  Levels 0 .. Count - 1 of a window, and two work images that Build
   --  uses (null after it).

   function Released (Pyr : Pyramid) return Boolean is
     (Pyr.Work_A = null and then Pyr.Work_B = null
      and then
      (for all K in Level_Index =>
        Pyr.Levels (K).GX = null and then Pyr.Levels (K).GY = null
        and then Pyr.Levels (K).DX = null
        and then Pyr.Levels (K).DY = null));

   procedure Release (Pyr : in out Pyramid)
   with Post => Released (Pyr) and then Pyr.Count = 0;
   --  Frees every image of the pyramid.

   procedure Build
     (Image      : access constant KI.Ks_Image_8_Grey_Data;
      Region     : access constant KR.Ks_Pixel_Region_Data;
      Area       : Window;
      Count      : Positive;
      Directions : Boolean;
      Threshold  : Long_Float;
      Pyr        : in out Pyramid;
      Status     : out Ks_Status)
   with
     Pre  => Window_In_Image (Area, Image) and then Count <= Max_Levels
             and then Threshold >= 0.0
             and then Threshold <= Max_Contrast_Threshold,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then Pyr.Count <= Count;
   --  Frees what Pyr held, then builds levels 0 .. Count - 1 of Area of
   --  Image: level 0 is the window smoothed with Smoothing_Sigma, level
   --  K + 1 is level K smoothed again and averaged over 2 x 2 blocks
   --  (ks_real_image_downsample_2), and each level's gradient is
   --  ks_real_image_sobel of it. With Directions, each level also gets its
   --  direction images (magnitude at least Threshold and the pixel's
   --  centre in Region; see Level_Data). Pyr.Count is the number of levels
   --  built (fewer when the call fails; the caller releases Pyr).

   function Level_Pixel_In_Region
     (Region : access constant KR.Ks_Pixel_Region_Data;
      Area   : Window;
      Level  : Level_Index;
      I, J   : Natural) return Boolean;
   --  The image pixel nearest to the centre of pixel (I, J) of Level
   --  belongs to Region (False for null).

   function Clamp_Grad (X : Long_Float) return Grad_Value is
     (if X >= -Grad_Limit then (if X <= Grad_Limit then X else Grad_Limit)
      else -Grad_Limit);
   --  X limited to Grad_Limit.

   function Read
     (Img  : access constant KM.Ks_Real_Image_Data;
      X, Y : Natural) return Grad_Value
   is (Clamp_Grad (Img.Pixels (Y, X)))
   with Pre => KM.Valid_Image (Img)
               and then Y <= Img.Pixels'Last (1)
               and then X <= Img.Pixels'Last (2);
   --  The value of pixel (X, Y), limited to Grad_Limit.

   Max_Magnitude_Squared : constant := 2.0 * Grad_Limit * Grad_Limit;

   function Magnitude_Squared
     (L    : Level_Data;
      I, J : Natural) return Long_Float
   with Pre  => Usable (L)
                and then I <= Natural (L.GX.Width) - 1
                and then J <= Natural (L.GX.Height) - 1,
        Post => Magnitude_Squared'Result >= 0.0
                and then Magnitude_Squared'Result <= Max_Magnitude_Squared;
   --  The squared gradient magnitude of pixel (I, J).

   function Is_Edge
     (L                 : Level_Data;
      I, J              : Natural;
      Threshold_Squared : Long_Float) return Boolean
   with Pre => Usable (L)
               and then I in 1 .. Natural (L.GX.Width) - 2
               and then J in 1 .. Natural (L.GX.Height) - 2;
   --  Pixel (I, J) is an edge pixel: its squared gradient magnitude is
   --  positive and at least Threshold_Squared, at least that of its
   --  neighbour ahead along the gradient direction (rounded to a multiple
   --  of 45 degrees) and above that of its neighbour behind.

   function Bilinear
     (Img  : access constant KM.Ks_Real_Image_Data;
      X, Y : P.Position) return Grad_Value
   with Pre => KM.Has_Pixels (Img);
   --  The bilinear interpolation of Img at (X, Y) (pixel centres at whole
   --  coordinates), the point first moved to the nearest point of
   --  [0, Width - 1] x [0, Height - 1].

   Max_Projection : constant := 2.0 * Grad_Limit;

   function Projected
     (L      : Level_Data;
      X, Y   : Long_Float;
      UX, UY : P.Unit;
      T      : Long_Float) return Long_Float
   with Pre  => Usable (L)
                and then abs X <= 2.0 ** 32 and then abs Y <= 2.0 ** 32
                and then abs T <= 4.0,
        Post => abs Projected'Result <= Max_Projection;
   --  The gradient of L at (X, Y) + T (UX, UY) (bilinear) projected on
   --  (UX, UY).

   function Parabola_Peak (H_Minus, H_0, H_Plus : Long_Float)
      return Long_Float
   with Pre  => abs H_Minus <= Max_Projection
                and then abs H_0 <= Max_Projection
                and then abs H_Plus <= Max_Projection,
        Post => Parabola_Peak'Result >= -0.5
                and then Parabola_Peak'Result <= 0.5;
   --  The position, relative to the middle sample, of the vertex of the
   --  parabola through (-1, H_Minus), (0, H_0), (1, H_Plus) when it opens
   --  downwards, limited to [-0.5, 0.5]; 0 otherwise.

end AMV.Kernels.PM_Align.Pyramids;
