--  The warp of the perspective and radial distortion model of
--  AMV.Kernels.Calib_Fix (ComputationMode PerspectiveAndRadialWarp): the
--  choice of the output's calibrated space, the map from an output pixel
--  to the input pixel that it shows, and the resampling of an image. The
--  model and the choice are described in the parent's spec.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Calib_Fix.Radial;

private package AMV.Kernels.Calib_Fix.Warp
  with SPARK_Mode, Preelaborate
is

   pragma Unevaluated_Use_Of_Old (Allow);

   package R renames AMV.Kernels.Calib_Fix.Radial;

   procedure Build_Model
     (P             : R.Params;
      F             : R.Frame;
      RMS           : Long_Float;
      Iterations    : Natural;
      Width, Height : Int32;
      Tile_X        : Long_Float;
      Tile_Y        : Long_Float;
      Model         : out Ks_Radial_Warp_Model;
      Status        : out Ks_Status)
   with
     Pre  => RMS >= 0.0 and then RMS <= Max_RMS
             and then Iterations <= Max_Fit_Iterations
             and then Width in 1 .. Max_Model_Side
             and then Height in 1 .. Max_Model_Side
             and then Valid_Tile (Tile_X) and then Valid_Tile (Tile_Y),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Model (Model)
                            and then Model.Image_Width = Width
                            and then Model.Image_Height = Height);
   --  The model record of the fitted model P (normalisation F, RMS error
   --  in pixels, Iterations) with the warp's map and the transform from
   --  calibrated coordinates (X * Tile_X, Y * Tile_Y for the plate point
   --  (X, Y): a checkerboard's tile sizes, 1.0 and 1.0 for the raw
   --  calibrated points of an N-point calibration) to output pixels.
   --  Bad_Parameter when the plate's image is degenerate at its centre,
   --  when the tile sizes differ by more than a factor of
   --  Max_Tile_Aspect, and when a transform leaves the bound of
   --  AMV.Kernels.Transforms.

   function Params_Of (Model : Ks_Radial_Warp_Model) return R.Params
   with Pre => Valid_Model (Model);
   --  The parameters of the model (Rho_Max its valid radius).

   Max_Input_Coordinate : constant := 2.0 ** 38;

   procedure Input_From_Output
     (Model  : Ks_Radial_Warp_Model;
      X, Y   : Long_Float;
      PX, PY : out Long_Float;
      Inside : out Boolean)
   with
     Pre  => Valid_Model (Model)
             and then abs X <= Max_Output_Coordinate
             and then abs Y <= Max_Output_Coordinate,
     Post => (if Inside
              then abs PX <= Max_Input_Coordinate
                   and then abs PY <= Max_Input_Coordinate
              else PX = 0.0 and then PY = 0.0);
   --  The input pixel (PX, PY) that the output pixel (X, Y) shows: the
   --  normalised grid point Grid_From_Output (X, Y), its ideal point and
   --  its observed point, in pixels. Inside is False (and the point 0)
   --  when the grid point has no image under the model (behind the
   --  camera, or beyond the valid radius).

   procedure Output_From_Input
     (Model  : Ks_Radial_Warp_Model;
      X, Y   : Long_Float;
      UX, UY : out Long_Float;
      Inside : out Boolean)
   with
     Pre  => Valid_Model (Model)
             and then abs X <= Max_Output_Coordinate
             and then abs Y <= Max_Output_Coordinate,
     Post => (if Inside
              then abs UX <= Max_Output_Coordinate
                   and then abs UY <= Max_Output_Coordinate
              else UX = 0.0 and then UY = 0.0);
   --  The inverse of Input_From_Output: the output pixel (UX, UY) that
   --  shows the input pixel (X, Y). The radial map is inverted along the
   --  pixel's direction from the centre: the normalised distance r of the
   --  ideal point, r (1 + K1 r**2 + K2 r**4) = |m|, is found by bisection
   --  (Bisection_Steps halvings) on [0, Sqrt (valid radius)], where the
   --  map rises; the homography by solving its two linear equations for
   --  the grid point (Cramer's rule); the output pixel is then the inverse
   --  of Grid_From_Output at that grid point. Inside is False (and the
   --  point 0) when the pixel lies beyond the image of the valid radius,
   --  when the equations are singular (|det| < 1.0E-12) or put the grid
   --  point behind the camera (denominator below Min_Denominator) or
   --  beyond the bounds, and when the output pixel lies beyond
   --  Max_Output_Coordinate.

   Bisection_Steps : constant := 64;

   procedure Resample
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Model  : Ks_Radial_Warp_Model;
      Fill   : KI.Grey_8;
      Output : KI.Ks_Image_8_Grey)
   with
     Pre  => KI.Valid_Image (Image) and then Valid_Model (Model)
             and then KI.Valid_Image (Output)
             and then Output.Width <= Max_Model_Side
             and then Output.Height <= Max_Model_Side,
     Post => KI.Valid_Image (Output)
             and then Output.Width = Output.Width'Old
             and then Output.Height = Output.Height'Old;
   --  Sets every pixel of Output to the bilinear sample of Image at the
   --  input pixel it shows, or to Fill when it shows none or a point
   --  outside Image (AMV.Kernels.Image_Sampling, which never indexes
   --  outside the image).

end AMV.Kernels.Calib_Fix.Warp;
