--  The two-image tools: the counterparts of CogIPTwoImageAddTool,
--  CogIPTwoImageSubtractTool and CogIPTwoImageMinMaxTool and their run
--  parameters CogIPTwoImageAdd, CogIPTwoImageSubtract and
--  CogIPTwoImageMinMax (Cognex.VisionPro.ImageProcessing).
--
--     Tool.Input_Image_A := Image;
--     Tool.Input_Image_B := Background;
--     Tool.Run_Params.Overflow_Mode := Absolute;
--     Tool.Run;
--     Difference := Tool.Output_Image;
--
--  Output_Image is a new image of the size of the two inputs whose pixel
--  (X, Y) is the tool's formula applied to pixel (X, Y) of Input_Image_A
--  and of Input_Image_B (A and B below):
--
--  * add, Overflow_Mode: Bounded (the default) min (A + B, 255), Wrap
--    (A + B) mod 256, Shift (A + B) / 2 rounded down;
--  * subtract (A - B), Overflow_Mode: Bounded (the default) max (A - B, 0),
--    Wrap (A - B) mod 256, Shift (A - B + 256) / 2 rounded down (128 for
--    equal pixels), Absolute abs (A - B);
--  * min/max, Operation: Min (the default) or Max of A and B.
--
--  The output keeps Input_Image_A's coordinate space tree, selected space
--  and pixel-from-root transform. VisionPro also takes regions (RegionA,
--  RegionB), an alignment of the images and images of different sizes,
--  and works on their overlap; AMV combines two whole images of one size.
--
--  The work is done by the SPARK kernel AMV.Kernels.IP_Two_Image (C:
--  ks_ip_two_image_*, include/amv_ip_geometry.h), which proves that every
--  output pixel is exactly the formula.
--
--  Run fails (Run_Status Error, Output_Image unallocated) with
--  Ks_Image_No_Pixels_Exception for an unallocated input ("InputImageA has
--  no pixels", "InputImageB has no pixels") and Ks_Bad_Parameter_Exception
--  for images of different sizes ("InputImageB is 5 x 4 pixels but
--  InputImageA is 6 x 4") and run parameters out of range.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels;
with AMV.Kernels.IP_Two_Image;
with AMV.Tools;

package AMV.Image_Processing.IP_Two_Image is

   ---------------------------------------------------------------------
   --  Run parameters
   ---------------------------------------------------------------------

   subtype Ks_IP_Two_Image_Add_Overflow_Mode_Constants is
     AMV.Kernels.Int32 range 0 .. 2;
   --  CogIPTwoImageAddOverflowModeConstants (Bounded, Wrap, Shift).
   subtype Ks_IP_Two_Image_Subtract_Overflow_Mode_Constants is
     AMV.Kernels.Int32 range 0 .. 3;
   --  CogIPTwoImageSubtractOverflowModeConstants (Bounded, Wrap, Shift,
   --  Absolute).

   Bounded  : constant AMV.Kernels.Int32 :=
     AMV.Kernels.IP_Two_Image.Add_Overflow_Mode_Bounded;
   Wrap     : constant AMV.Kernels.Int32 :=
     AMV.Kernels.IP_Two_Image.Add_Overflow_Mode_Wrap;
   Shift    : constant AMV.Kernels.Int32 :=
     AMV.Kernels.IP_Two_Image.Add_Overflow_Mode_Shift;
   Absolute : constant AMV.Kernels.Int32 :=
     AMV.Kernels.IP_Two_Image.Subtract_Overflow_Mode_Absolute;
   --  The literals of both enumerations (Bounded, Wrap and Shift have the
   --  same values in both; Absolute is the subtract tool's only).

   subtype Ks_IP_Two_Image_Min_Max_Operation_Constants is
     AMV.Kernels.Int32 range 0 .. 1;
   --  CogIPTwoImageMinMaxOperationConstants.

   Min : constant Ks_IP_Two_Image_Min_Max_Operation_Constants :=
     AMV.Kernels.IP_Two_Image.Min_Max_Operation_Min;
   Max : constant Ks_IP_Two_Image_Min_Max_Operation_Constants :=
     AMV.Kernels.IP_Two_Image.Min_Max_Operation_Max;

   subtype Ks_IP_Two_Image_Add is AMV.Kernels.IP_Two_Image.Ks_IP_Two_Image_Add;
   --  CogIPTwoImageAdd: Overflow_Mode (Bounded).
   subtype Ks_IP_Two_Image_Subtract is
     AMV.Kernels.IP_Two_Image.Ks_IP_Two_Image_Subtract;
   --  CogIPTwoImageSubtract: Overflow_Mode (Bounded).
   subtype Ks_IP_Two_Image_Min_Max is
     AMV.Kernels.IP_Two_Image.Ks_IP_Two_Image_Min_Max;
   --  CogIPTwoImageMinMax: Operation (Min).

   ---------------------------------------------------------------------
   --  The tools
   ---------------------------------------------------------------------

   type Ks_IP_Two_Image_Add_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image_A : AMV.Images.Ks_Image_8_Grey;
      Input_Image_B : AMV.Images.Ks_Image_8_Grey;
      Run_Params    : Ks_IP_Two_Image_Add;
      Output_Image  : AMV.Images.Ks_Image_8_Grey;
      --  Set by Run (read-only by convention); unallocated after a run
      --  that failed.
   end record;

   overriding procedure Execute (Tool : in out Ks_IP_Two_Image_Add_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_IP_Two_Image_Add_Tool);

   type Ks_IP_Two_Image_Subtract_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image_A : AMV.Images.Ks_Image_8_Grey;
      Input_Image_B : AMV.Images.Ks_Image_8_Grey;
      Run_Params    : Ks_IP_Two_Image_Subtract;
      Output_Image  : AMV.Images.Ks_Image_8_Grey;
   end record;

   overriding procedure Execute (Tool : in out Ks_IP_Two_Image_Subtract_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_IP_Two_Image_Subtract_Tool);

   type Ks_IP_Two_Image_Min_Max_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image_A : AMV.Images.Ks_Image_8_Grey;
      Input_Image_B : AMV.Images.Ks_Image_8_Grey;
      Run_Params    : Ks_IP_Two_Image_Min_Max;
      Output_Image  : AMV.Images.Ks_Image_8_Grey;
   end record;

   overriding procedure Execute (Tool : in out Ks_IP_Two_Image_Min_Max_Tool);
   overriding procedure Reset_Results
     (Tool : in out Ks_IP_Two_Image_Min_Max_Tool);

end AMV.Image_Processing.IP_Two_Image;
