--  Kernel of AMV.Image_Processing.IP_Two_Image: the two-image tools
--  CogIPTwoImageAddTool, CogIPTwoImageSubtractTool and
--  CogIPTwoImageMinMaxTool (run parameters CogIPTwoImageAdd,
--  CogIPTwoImageSubtract and CogIPTwoImageMinMax). The C API is declared
--  in include/amv_ip_geometry.h.
--
--  Each execute entry point combines two 8-bit images of the same size
--  pixel by pixel into a new image of that size: output pixel (X, Y) is
--  the formula of the tool applied to pixel (X, Y) of InputImageA and of
--  InputImageB. VisionPro also accepts images of different sizes, regions
--  and an alignment of the two images, and works on their overlap; AMV
--  requires two images of one size and combines them whole (a size
--  mismatch fails with Bad_Parameter naming InputImageB). The formulas
--  (A and B the two grey levels, the codes VisionPro's values):
--
--  * Add, OverflowMode (CogIPTwoImageAddOverflowModeConstants): Bounded
--    (0, the default) min (A + B, 255); Wrap (1) (A + B) mod 256; Shift
--    (2) (A + B) / 2, rounded down.
--  * Subtract (A - B), OverflowMode
--    (CogIPTwoImageSubtractOverflowModeConstants): Bounded (0, the
--    default) max (A - B, 0); Wrap (1) (A - B) mod 256; Shift (2)
--    (A - B + 256) / 2 rounded down, so that A - B = 0 gives 128 (AMV's
--    choice of offset); Absolute (3) abs (A - B).
--  * MinMax, Operation (CogIPTwoImageMinMaxOperationConstants): Min (0,
--    the default) min (A, B); Max (1) max (A, B).
--
--  The same handle may be passed as both images (the output is new).
--
--  Proved (docs/PROOF.md): absence of run-time errors for any image
--  handles that are null or came from the image kernel and any codes; no
--  memory leaks; Gold: every output pixel is exactly the formula of the
--  tool applied to the two input pixels at its position, as
--  AMV.Kernels.Images proves its fills.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Images;

package AMV.Kernels.IP_Two_Image with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;

   use type KI.Grey_8;
   use type KI.Ks_Image_8_Grey;

   ---------------------------------------------------------------------
   --  Run parameters
   ---------------------------------------------------------------------

   Add_Overflow_Mode_Bounded : constant Int32 := 0;
   Add_Overflow_Mode_Wrap    : constant Int32 := 1;
   Add_Overflow_Mode_Shift   : constant Int32 := 2;
   --  CogIPTwoImageAddOverflowModeConstants (C:
   --  KS_IP_TWO_IMAGE_ADD_OVERFLOW_MODE_*).

   Subtract_Overflow_Mode_Bounded  : constant Int32 := 0;
   Subtract_Overflow_Mode_Wrap     : constant Int32 := 1;
   Subtract_Overflow_Mode_Shift    : constant Int32 := 2;
   Subtract_Overflow_Mode_Absolute : constant Int32 := 3;
   --  CogIPTwoImageSubtractOverflowModeConstants (C:
   --  KS_IP_TWO_IMAGE_SUBTRACT_OVERFLOW_MODE_*).

   Min_Max_Operation_Min : constant Int32 := 0;
   Min_Max_Operation_Max : constant Int32 := 1;
   --  CogIPTwoImageMinMaxOperationConstants (C:
   --  KS_IP_TWO_IMAGE_MIN_MAX_OPERATION_*).

   type Ks_IP_Two_Image_Add is record
      Overflow_Mode : Int32 := Add_Overflow_Mode_Bounded;
   end record
     with Convention => C;
   --  C: ks_ip_two_image_add (CogIPTwoImageAdd.OverflowMode).

   type Ks_IP_Two_Image_Subtract is record
      Overflow_Mode : Int32 := Subtract_Overflow_Mode_Bounded;
   end record
     with Convention => C;
   --  C: ks_ip_two_image_subtract (CogIPTwoImageSubtract.OverflowMode).

   type Ks_IP_Two_Image_Min_Max is record
      Operation : Int32 := Min_Max_Operation_Min;
   end record
     with Convention => C;
   --  C: ks_ip_two_image_min_max (CogIPTwoImageMinMax.Operation).

   procedure Add_Run_Params_Default (Params : out Ks_IP_Two_Image_Add)
   with
     Export, Convention => C,
     External_Name => "ks_ip_two_image_add_run_params_default",
     Post => Params = (others => <>);

   procedure Subtract_Run_Params_Default
     (Params : out Ks_IP_Two_Image_Subtract)
   with
     Export, Convention => C,
     External_Name => "ks_ip_two_image_subtract_run_params_default",
     Post => Params = (others => <>);

   procedure Min_Max_Run_Params_Default
     (Params : out Ks_IP_Two_Image_Min_Max)
   with
     Export, Convention => C,
     External_Name => "ks_ip_two_image_min_max_run_params_default",
     Post => Params = (others => <>);
   --  The default run parameters (VisionPro's). Cannot fail.

   ---------------------------------------------------------------------
   --  The formulas (Gold)
   ---------------------------------------------------------------------

   function Add_Pixel (Mode : Int32; A, B : KI.Grey_8) return KI.Grey_8 is
     (case Mode is
         when Add_Overflow_Mode_Wrap =>
            KI.Grey_8 ((Natural (A) + Natural (B)) mod 256),
         when Add_Overflow_Mode_Shift =>
            KI.Grey_8 ((Natural (A) + Natural (B)) / 2),
         when others =>
            KI.Grey_8 (Natural'Min (Natural (A) + Natural (B), 255)));
   --  The output pixel of the add tool (Bounded for any other code).

   function Subtract_Pixel (Mode : Int32; A, B : KI.Grey_8) return KI.Grey_8
   is
     (case Mode is
         when Subtract_Overflow_Mode_Wrap =>
            KI.Grey_8 ((Integer (A) - Integer (B)) mod 256),
         when Subtract_Overflow_Mode_Shift =>
            KI.Grey_8 ((Integer (A) - Integer (B) + 256) / 2),
         when Subtract_Overflow_Mode_Absolute =>
            KI.Grey_8 (abs (Integer (A) - Integer (B))),
         when others =>
            KI.Grey_8 (Integer'Max (Integer (A) - Integer (B), 0)));
   --  The output pixel of the subtract tool, A - B.

   function Min_Max_Pixel (Operation : Int32; A, B : KI.Grey_8)
      return KI.Grey_8
   is
     (if Operation = Min_Max_Operation_Max then KI.Grey_8'Max (A, B)
      else KI.Grey_8'Min (A, B));
   --  The output pixel of the min/max tool.

   function Same_Size
     (Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data)
      return Boolean
   is
     (KI.Valid_Image (Image_A) and then KI.Valid_Image (Image_B)
      and then Image_A.Width = Image_B.Width
      and then Image_A.Height = Image_B.Height);
   --  Two valid handles of one size.

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   --  The checks, in order: InputImageA and InputImageB (Image_No_Pixels
   --  "InputImageA has no pixels", Bad_Parameter "InputImageB is not a
   --  valid image handle"), their sizes (Bad_Parameter "InputImageB is
   --  5 x 4 pixels but InputImageA is 6 x 4"), the run parameters
   --  (Bad_Parameter "RunParams.OverflowMode must be Bounded (0), Wrap (1)
   --  or Shift (2)"), then Out_Of_Memory. Output is a new handle the caller
   --  owns, null when the call fails.

   procedure Add_Execute
     (Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data;
      Params           : Ks_IP_Two_Image_Add;
      Output           : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_two_image_add_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Same_Size (Image_A, Image_B)
                     and then KI.Valid_Image (Output)
                     and then Output.Width = Image_A.Width
                     and then Output.Height = Image_A.Height
                     and then
                       (for all Y in Output.Pixels'Range (1)
                        => (for all X in Output.Pixels'Range (2)
                            => Output.Pixels (Y, X)
                                 = Add_Pixel (Params.Overflow_Mode,
                                              Image_A.Pixels (Y, X),
                                              Image_B.Pixels (Y, X))))
                else Output = null);

   procedure Subtract_Execute
     (Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data;
      Params           : Ks_IP_Two_Image_Subtract;
      Output           : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_two_image_subtract_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Same_Size (Image_A, Image_B)
                     and then KI.Valid_Image (Output)
                     and then Output.Width = Image_A.Width
                     and then Output.Height = Image_A.Height
                     and then
                       (for all Y in Output.Pixels'Range (1)
                        => (for all X in Output.Pixels'Range (2)
                            => Output.Pixels (Y, X)
                                 = Subtract_Pixel (Params.Overflow_Mode,
                                                   Image_A.Pixels (Y, X),
                                                   Image_B.Pixels (Y, X))))
                else Output = null);

   procedure Min_Max_Execute
     (Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data;
      Params           : Ks_IP_Two_Image_Min_Max;
      Output           : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_ip_two_image_min_max_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Same_Size (Image_A, Image_B)
                     and then KI.Valid_Image (Output)
                     and then Output.Width = Image_A.Width
                     and then Output.Height = Image_A.Height
                     and then
                       (for all Y in Output.Pixels'Range (1)
                        => (for all X in Output.Pixels'Range (2)
                            => Output.Pixels (Y, X)
                                 = Min_Max_Pixel (Params.Operation,
                                                  Image_A.Pixels (Y, X),
                                                  Image_B.Pixels (Y, X))))
                else Output = null);

end AMV.Kernels.IP_Two_Image;
