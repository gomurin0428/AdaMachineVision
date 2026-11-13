--  The polar unwrap tool: the counterpart of CogPolarUnwrapTool and its run
--  parameters CogPolarUnwrap (Cognex.VisionPro.ImageProcessing).
--
--     Tool.Input_Image := Image;
--     Tool.Region.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
--       (320.0, 240.0, 100.0, 0.0, 2.0 * Pi, 1.5);
--     Tool.Run;
--     Strip := Tool.Output_Image;
--
--  Output_Image is the annulus section Region of Input_Image unwrapped
--  into an upright image: output x runs along the angle (from Angle_Start
--  through Angle_Start + Angle_Span), output y along the radius (from
--  Radius to Radius * Radial_Scale). Its width is round (Scaling_X times
--  the middle arc in input pixels) and its height round (Scaling_Y times
--  the radial extent in input pixels), so the defaults (1.0) give about one
--  output pixel per input pixel. The mapping is not affine, so the output
--  gets a fresh coordinate space tree (its root is its pixel space);
--  Get_Input_Point_From_Output_Point and Get_Output_Point_From_Input_Point
--  relate output points to the input image's selected space.
--
--  The work is done by the SPARK kernel AMV.Kernels.Polar_Unwrap (C:
--  ks_polar_unwrap_*, include/amv_ip_geometry.h), whose spec gives the
--  formulas.
--
--  Run fails (Run_Status Error, Output_Image unallocated) with
--  Ks_Image_No_Pixels_Exception for an unallocated Input_Image ("InputImage
--  has no pixels"), Ks_Image_Bad_Selected_Space_Name_Exception for a region
--  in an unknown space, and Ks_Bad_Parameter_Exception for an invalid
--  section (Radius > 0, Radial_Scale > 0 and not 1, Angle_Span not 0),
--  run parameters out of range, an output below 1 or above 32767 pixels
--  along an axis, and a section that reaches outside the image ("Region
--  lies partly outside InputImage", as VisionPro).

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Polar_Unwrap;
with AMV.Shapes;
with AMV.Tools;

package AMV.Image_Processing.Polar_Unwrap is

   ---------------------------------------------------------------------
   --  Run parameters (CogPolarUnwrap)
   ---------------------------------------------------------------------

   subtype Ks_Polar_Unwrap_Sampling_Mode_Constants is
     AMV.Kernels.Int32 range 0 .. 1;
   --  CogPolarUnwrapSamplingModeConstants, with VisionPro's values.

   Bilinear_Interpolation : constant Ks_Polar_Unwrap_Sampling_Mode_Constants
     := AMV.Kernels.Polar_Unwrap.Sampling_Mode_Bilinear_Interpolation;
   --  The default.
   Nearest_Neighbor       : constant Ks_Polar_Unwrap_Sampling_Mode_Constants
     := AMV.Kernels.Polar_Unwrap.Sampling_Mode_Nearest_Neighbor;

   subtype Ks_Polar_Unwrap is AMV.Kernels.Polar_Unwrap.Ks_Polar_Unwrap;
   --  The run parameters (CogPolarUnwrap), a record with VisionPro's
   --  defaults: Scaling_X and Scaling_Y (1.0, AMV range 0.001 .. 1000) and
   --  Sampling_Mode (Bilinear_Interpolation).

   procedure Get_Input_Point_From_Output_Point
     (Params         : Ks_Polar_Unwrap;
      Input_Image    : AMV.Images.Ks_Image'Class;
      Annular_Region : AMV.Shapes.Ks_Circular_Annulus_Section;
      Output_Point_X : Real;
      Output_Point_Y : Real;
      Input_Point_X  : out Real;
      Input_Point_Y  : out Real);
   --  GetInputPointFromOutputPoint: the point of Input_Image's selected
   --  space that the output point (output root or pixel coordinates, within
   --  the output image's area) samples, for the output Run makes from
   --  Input_Image and Annular_Region with Params. Raises
   --  Ks_Bad_Parameter_Exception as Run does, and for a point outside the
   --  output image.

   procedure Get_Output_Point_From_Input_Point
     (Params         : Ks_Polar_Unwrap;
      Input_Image    : AMV.Images.Ks_Image'Class;
      Annular_Region : AMV.Shapes.Ks_Circular_Annulus_Section;
      Input_Point_X  : Real;
      Input_Point_Y  : Real;
      Output_Point_X : out Real;
      Output_Point_Y : out Real;
      Revolution     : Integer := 0);
   --  GetOutputPointFromInputPoint: the output point that samples the point
   --  of Input_Image's selected space, its angle taken from Angle_Start in
   --  the sense of Angle_Span in [0, 2 Pi) plus Revolution whole turns.
   --  Points outside the section give points outside the output image.
   --  Raises Ks_Bad_Parameter_Exception as Run does, and for the centre of
   --  the section.

   ---------------------------------------------------------------------
   --  The tool (CogPolarUnwrapTool)
   ---------------------------------------------------------------------

   type Ks_Polar_Unwrap_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image  : AMV.Images.Ks_Image_8_Grey;
      Region       : AMV.Shapes.Ks_Circular_Annulus_Section;
      --  In its selected space (default "."). VisionPro's Region is an
      --  ICogRegion that must be a circular or elliptical annulus section;
      --  AMV takes the circular one.
      Run_Params   : Ks_Polar_Unwrap;
      Output_Image : AMV.Images.Ks_Image_8_Grey;
      --  Set by Run (read-only by convention); unallocated after a run
      --  that failed.
   end record;

   overriding procedure Execute (Tool : in out Ks_Polar_Unwrap_Tool);
   overriding procedure Reset_Results (Tool : in out Ks_Polar_Unwrap_Tool);

end AMV.Image_Processing.Polar_Unwrap;
