with Ada.Containers.Vectors;
with AMV.Images;

--  Finds the largest object in a grey image with the AMV blob tool and
--  measures how round its outer boundary is.
package Circularity_Measure is

   type Polarity_Kind is (Light_Object, Dark_Object);

   type Settings is record
      Auto_Threshold : Boolean := True;      --  Otsu's threshold
      Threshold      : Natural range 0 .. 255 := 128;
      Polarity       : Polarity_Kind := Light_Object;
      Min_Area       : Long_Float := 2_000.0;  --  pixels
   end record;

   type Point is record
      X, Y : Long_Float := 0.0;
   end record;

   package Point_Vectors is new Ada.Containers.Vectors (Positive, Point);

   type Result is record
      Found       : Boolean := False;
      Clipped     : Boolean := False;     --  the object touches the border
      Area        : Long_Float := 0.0;    --  inside the outer boundary
      Perimeter   : Long_Float := 0.0;    --  of the outer boundary
      Circularity : Long_Float := 0.0;    --  4 Pi Area / Perimeter**2
      Center_X    : Long_Float := 0.0;    --  least-squares circle
      Center_Y    : Long_Float := 0.0;
      Radius      : Long_Float := 0.0;
      Radius_Min  : Long_Float := 0.0;    --  of the boundary about the
      Radius_Max  : Long_Float := 0.0;    --  circle's centre
      Roundness   : Long_Float := 0.0;    --  Radius_Min / Radius_Max
      Threshold   : Natural := 0;         --  grey level used
   end record;

   procedure Measure
     (Image    : AMV.Images.Ks_Image_8_Grey;
      Config   : Settings;
      Outcome  : out Result;
      Boundary : in out Point_Vectors.Vector);
   --  Segments Image at the threshold (Otsu's, computed here, when
   --  Auto_Threshold; Light_Object: pixels >= the threshold) and takes the
   --  largest blob of at least Min_Area pixels (one that does not touch
   --  the image border if there is one) to find the object.
   --
   --  The outer edge is then found along 720 rays from the object's
   --  centre: on each ray, the radius where it first enters the object
   --  coming in from outside (three object samples in a row, the crossing
   --  of the threshold interpolated between grey values). What lies
   --  inside the edge (a cup's inside, its shadows, a seam that breaks
   --  the blob) does not matter. A radius more than 3 % (at least 4 px)
   --  from the median of its 15 neighbouring rays is replaced by that
   --  median, so features narrower than about 3 degrees are not seen; the
   --  radii are then averaged over 5 rays. The rays start from the centre
   --  of the blob's box and again from the centre of the circle fitted to
   --  that edge. The object must be star-shaped from its centre.
   --
   --  Boundary receives the edge points in pixel coordinates (pixel
   --  centres at whole numbers); Area, Perimeter, the circle and the radii
   --  are taken from them. Raises AMV.Ks_Exception when the blob tool
   --  fails.

end Circularity_Measure;
