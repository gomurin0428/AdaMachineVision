--  Synthetic test images with known geometry.
--
--  Drawing routines blend a foreground value into the image with
--  anti-aliasing: each pixel's coverage by the shape is estimated by
--  supersampling the pixel area [X - 0.5, X + 0.5] x [Y - 0.5, Y + 0.5]
--  on a Samples x Samples grid, and the pixel becomes
--  round (old * (1 - coverage) + Value * coverage). Shape coordinates are in
--  pixel space (the centre of pixel (X, Y) is at (X, Y)).
--
--  Accuracy. The sample points are the centres of the Samples x Samples
--  sub-squares of the pixel square, so the sample points of all pixels
--  together form one square lattice with spacing 1 / Samples. How the
--  sampling errors of neighbouring pixels combine depends on the shape
--  (figures for the default Samples = 8, area and centroid measured as
--  coverage-weighted sums at the pixel centres):
--
--  * A straight edge whose direction (dx, dy) = (q, p) is a ratio of
--    small coprime integers meets the lattice in a regular pattern, so
--    its error does not average out along the edge. Besides axis-aligned
--    (p = 0) and 45 degree (p = q) edges this covers slopes such as 1/2,
--    1/3 or 2/3, which every polygon with integer vertices has. The whole
--    edge is quantised in steps of 1 / (Samples * sqrt (p**2 + q**2))
--    pixel normal to itself and can appear shifted by up to half a step,
--    1 / (2 * Samples * sqrt (p**2 + q**2)): 1/16 pixel for an
--    axis-aligned edge, about 0.044 at 45 degrees, 0.028 for slope 1/2
--    and 0.020 for slope 1/3. The shifts of different edges add up, so
--    the centroid of a rectangle or polygon with such edges can be off by
--    up to sqrt 2 times that bound (about 0.09 pixel for an axis-aligned
--    rectangle; measured worst cases about 0.024 pixel for a rectangle
--    turned by atan (1/2) or atan (1/3), 0.026 for a triangle with
--    integer vertices and 0.036 at 45 degrees), and its area by up to a
--    few tenths of a percent (0.6 percent at 45 degrees). An axis-aligned
--    edge at a multiple of 1 / Samples from a pixel boundary (with the
--    default: any multiple of 1/8) is rendered exactly.
--
--  * An edge with a generic direction (for example turned by 0.3 or 0.9
--    radian) meets the lattice irregularly, so the errors average out: a
--    rectangle with such edges has its area within about 0.01 percent and
--    its centroid within about 0.002 pixel.
--
--  * Curves average out as well, but less so the smaller they are, since
--    near its extreme points a curve runs almost parallel to an axis. A
--    circle of radius 10 pixels or more has its area within about 0.05
--    percent and its centroid within about 0.01 pixel; from radius 5 to 10
--    about 0.2 percent and 0.01 pixel; below radius 5 up to about 1
--    percent and 0.025 pixel (for example 0.66 percent for radius 2.5,
--    and 0.023 pixel for a circle of radius 3.45).
--
--  * Each pixel value is then rounded to an integer, which adds up to
--    0.5 / 255 of a pixel's coverage per partly covered pixel (an
--    axis-aligned edge can appear shifted by up to 1/16 + 0.5/255, about
--    0.0645 pixel).
--
--  The errors shrink roughly in proportion to 1 / Samples. For tight
--  sub-pixel checks turn straight edges by a generic angle (not one whose
--  tangent is a ratio of small integers, which integer vertices give), put
--  axis-aligned edges at multiples of 1 / Samples, use circles of radius
--  10 pixels or more, or raise Samples, and choose tolerances from the
--  figures above.
--
--  Every routine that takes an existing image raises
--  Ks_Image_No_Pixels_Exception when it is unallocated. Shapes with a
--  non-positive width, height or radius draw nothing.

with AMV;
with AMV.Images;

package AMV_Test_Images is

   use AMV;

   Default_Samples : constant := 8;

   function Blank
     (Width, Height : Positive;
      Value         : AMV.Images.Grey_8 := 0)
      return AMV.Images.Ks_Image_8_Grey;

   procedure Draw_Rectangle
     (Image                   : in out AMV.Images.Ks_Image_8_Grey;
      Center_X, Center_Y      : Real;
      Width, Height           : Real;
      Rotation                : Real := 0.0;
      Value                   : AMV.Images.Grey_8 := 255;
      Samples                 : Positive := Default_Samples);
   --  A filled rectangle with the given centre and side lengths, rotated by
   --  Rotation radians about its centre.

   procedure Draw_Circle
     (Image              : in out AMV.Images.Ks_Image_8_Grey;
      Center_X, Center_Y : Real;
      Radius             : Real;
      Value              : AMV.Images.Grey_8 := 255;
      Samples            : Positive := Default_Samples);

   procedure Draw_Ellipse
     (Image              : in out AMV.Images.Ks_Image_8_Grey;
      Center_X, Center_Y : Real;
      Radius_X, Radius_Y : Real;
      Rotation           : Real := 0.0;
      Value              : AMV.Images.Grey_8 := 255;
      Samples            : Positive := Default_Samples);

   type Vertex_List is array (Positive range <>) of Real;
   --  X1, Y1, X2, Y2, ... (even length).

   procedure Draw_Polygon
     (Image    : in out AMV.Images.Ks_Image_8_Grey;
      Vertices : Vertex_List;
      Value    : AMV.Images.Grey_8 := 255;
      Samples  : Positive := Default_Samples);
   --  Even-odd fill. Raises Ks_Bad_Parameter_Exception when Vertices has
   --  odd length; fewer than three vertices draw nothing.

   procedure Draw_Half_Plane
     (Image    : in out AMV.Images.Ks_Image_8_Grey;
      X, Y     : Real;
      Rotation : Real;
      Value    : AMV.Images.Grey_8 := 255;
      Samples  : Positive := Default_Samples);
   --  Fills the side of the line through (X, Y) with direction Rotation
   --  that lies on its left normal (-sin R, cos R). Produces a straight
   --  edge at a known position, e.g. for caliper and find-line tests.

   procedure Draw_Annulus
     (Image              : in out AMV.Images.Ks_Image_8_Grey;
      Center_X, Center_Y : Real;
      Inner_Radius       : Real;
      Outer_Radius       : Real;
      Value              : AMV.Images.Grey_8 := 255;
      Samples            : Positive := Default_Samples);
   --  The ring Inner_Radius <= distance <= Outer_Radius (a disc when
   --  Inner_Radius <= 0; nothing when Outer_Radius <= Inner_Radius).

   function Horizontal_Ramp
     (Width, Height : Positive;
      Low, High     : Real) return AMV.Images.Ks_Image_8_Grey;
   --  Pixel (X, Y) = round (Low + (High - Low) * X / (Width - 1)), clamped
   --  to 0 .. 255 (Low everywhere when Width = 1).

   procedure Add_Noise
     (Image     : in out AMV.Images.Ks_Image_8_Grey;
      Amplitude : Real;
      Seed      : Natural := 1);
   --  Adds deterministic uniform noise in [-Amplitude, Amplitude] (a simple
   --  linear congruential generator seeded by Seed), rounding and clamping
   --  to 0 .. 255. Pixels are visited row by row, so the same image size,
   --  Amplitude and Seed always add the same noise. A negative Amplitude
   --  acts like its magnitude.

   procedure Checkerboard
     (Image       : in out AMV.Images.Ks_Image_8_Grey;
      Origin_X    : Real;
      Origin_Y    : Real;
      Square_Size : Real;
      Rotation    : Real := 0.0;
      Dark        : AMV.Images.Grey_8 := 30;
      Light       : AMV.Images.Grey_8 := 220;
      Samples     : Positive := Default_Samples);
   --  Overwrites the whole image with an anti-aliased checkerboard whose
   --  square corners lie at Origin + (I * S * DirX + J * S * DirY) for all
   --  integers I, J, with DirX = (cos R, sin R), DirY = (-sin R, cos R).
   --  The square with corner Origin and extending along +DirX and +DirY is
   --  Light. Raises Ks_Bad_Parameter_Exception unless Square_Size > 0.

   type Homography is array (1 .. 8) of Real;
   --  The plane projective map (U, V) -> ((H1 U + H2 V + H3) / W,
   --  (H4 U + H5 V + H6) / W) with W = H7 U + H8 V + 1. H7 = H8 = 0 gives
   --  an affine map.

   procedure Map
     (H    : Homography;
      U, V : Real;
      X, Y : out Real);
   --  The image of (U, V) under H. Raises Ks_Bad_Parameter_Exception when
   --  W is not positive (the point lies on or behind the horizon).

   procedure Draw_Board
     (Image            : in out AMV.Images.Ks_Image_8_Grey;
      Pixel_From_Board : Homography;
      Columns, Rows    : Positive;
      Margin           : Real := 0.5;
      Dark             : AMV.Images.Grey_8 := 30;
      Light            : AMV.Images.Grey_8 := 220;
      Samples          : Positive := Default_Samples);
   --  A finite checkerboard of Columns x Rows tiles, drawn through
   --  Pixel_From_Board from board coordinates in tiles: tile (C, R) covers
   --  [C, C + 1] x [R, R + 1] and is Dark when C + R is even. The board and
   --  a margin of Margin tiles around it are first filled with Light, so
   --  the tile corners on the board's outline are L-corners against a
   --  plain margin and the inner corners (I, J), I in 1 .. Columns - 1 and
   --  J in 1 .. Rows - 1, lie at Map (Pixel_From_Board, I, J). The rest of
   --  the image is left as it was. Each quadrilateral is anti-aliased as
   --  by Draw_Polygon.

   function Mean_Value
     (Image                       : AMV.Images.Ks_Image_8_Grey;
      X_Min, Y_Min, Width, Height : Natural) return Real;
   --  Mean grey value over a window (for checking processing results). The
   --  window must be non-empty and lie inside the image
   --  (Ks_Bad_Parameter_Exception otherwise).

end AMV_Test_Images;
