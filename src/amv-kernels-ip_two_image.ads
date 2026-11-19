--  Kernel of AMV.Image_Processing.IP_Two_Image: the two-image tools that
--  add two images, subtract one from the other and take their minimum or
--  maximum (run parameters Ks_IP_Two_Image_Add, Ks_IP_Two_Image_Subtract
--  and Ks_IP_Two_Image_Min_Max). The C API is declared in
--  include/amv_ip_geometry.h.
--
--  Each execute entry point combines two 8-bit images of the same size
--  pixel by pixel into a new image of that size: output pixel (X, Y) is
--  the formula of the tool applied to pixel (X, Y) of InputImageA and of
--  InputImageB. The two images are combined whole (a size mismatch fails
--  with Bad_Parameter naming InputImageB). The formulas (A and B the two
--  grey levels):
--
--  * Add, OverflowMode: Bounded (0, the default) min (A + B, 255); Wrap
--    (1) (A + B) mod 256; Shift (2) (A + B) / 2, rounded down.
--  * Subtract (A - B), OverflowMode: Bounded (0, the default)
--    max (A - B, 0); Wrap (1) (A - B) mod 256; Shift (2)
--    (A - B + 256) / 2 rounded down, so that A - B = 0 gives 128;
--    Absolute (3) abs (A - B).
--  * MinMax, Operation: Min (0, the default) min (A, B); Max (1)
--    max (A, B).
--
--  The same handle may be passed as both images (the output is new).
--
--  Proved (docs/PROOF.md): absence of run-time errors for any image
--  handles that are null or came from the image kernel and any codes; no
--  memory leaks; Platinum: the output and the status are exactly those
--  that AMV.Spec.IP_Two_Image (the formulas) and Input_Failure (the order
--  of the checks) give, but for the text of a message and for
--  Out_Of_Memory, which only the allocation decides.

pragma Validity_Checks ("F");

with AMV.Kernels.Images;
with AMV.Spec.IP_Two_Image;

package AMV.Kernels.IP_Two_Image with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package Spec renames AMV.Spec.IP_Two_Image;

   use type KI.Grey_8;
   use type KI.Ks_Image_8_Grey;

   ---------------------------------------------------------------------
   --  Run parameters
   ---------------------------------------------------------------------

   Add_Overflow_Mode_Bounded : constant Int32 := 0;
   Add_Overflow_Mode_Wrap    : constant Int32 := 1;
   Add_Overflow_Mode_Shift   : constant Int32 := 2;
   --  The OverflowMode of the add tool (C:
   --  KS_IP_TWO_IMAGE_ADD_OVERFLOW_MODE_*).

   Subtract_Overflow_Mode_Bounded  : constant Int32 := 0;
   Subtract_Overflow_Mode_Wrap     : constant Int32 := 1;
   Subtract_Overflow_Mode_Shift    : constant Int32 := 2;
   Subtract_Overflow_Mode_Absolute : constant Int32 := 3;
   --  The OverflowMode of the subtract tool (C:
   --  KS_IP_TWO_IMAGE_SUBTRACT_OVERFLOW_MODE_*).

   Min_Max_Operation_Min : constant Int32 := 0;
   Min_Max_Operation_Max : constant Int32 := 1;
   --  The Operation of the min/max tool (C:
   --  KS_IP_TWO_IMAGE_MIN_MAX_OPERATION_*).

   subtype Add_Overflow_Mode is Int32
     range Add_Overflow_Mode_Bounded .. Add_Overflow_Mode_Shift;
   subtype Subtract_Overflow_Mode is Int32
     range Subtract_Overflow_Mode_Bounded .. Subtract_Overflow_Mode_Absolute;
   subtype Min_Max_Operation is Int32
     range Min_Max_Operation_Min .. Min_Max_Operation_Max;
   --  The codes that the tools take.

   type Ks_IP_Two_Image_Add is record
      Overflow_Mode : Int32 := Add_Overflow_Mode_Bounded;
   end record
     with Convention => C;
   --  C: ks_ip_two_image_add.

   type Ks_IP_Two_Image_Subtract is record
      Overflow_Mode : Int32 := Subtract_Overflow_Mode_Bounded;
   end record
     with Convention => C;
   --  C: ks_ip_two_image_subtract.

   type Ks_IP_Two_Image_Min_Max is record
      Operation : Int32 := Min_Max_Operation_Min;
   end record
     with Convention => C;
   --  C: ks_ip_two_image_min_max.

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
   --  The default run parameters. Cannot fail.

   ---------------------------------------------------------------------
   --  The checks
   ---------------------------------------------------------------------

   function Input_Failure
     (Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data)
      return Failure_Code
   is
     (if KI.Input_Image_Failure (Image_A) /= Failure_None
      then KI.Input_Image_Failure (Image_A)
      elsif KI.Input_Image_Failure (Image_B) /= Failure_None
      then KI.Input_Image_Failure (Image_B)
      elsif Image_A.Width /= Image_B.Width
        or else Image_A.Height /= Image_B.Height
      then Failure_Bad_Parameter
      else Failure_None);
   --  The failure of the checks of the two images, in the order of the
   --  documentation below: InputImageA, InputImageB, their sizes.

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
     Post =>
       Valid (Status)
       and then
         (if Input_Failure (Image_A, Image_B) /= Failure_None
          then Status.Failure = Input_Failure (Image_A, Image_B)
          elsif Params.Overflow_Mode not in Add_Overflow_Mode
          then Status.Failure = Failure_Bad_Parameter
          else Status.Failure in Failure_None | Failure_Out_Of_Memory)
       and then
         (if Succeeded (Status)
          then Same_Size (Image_A, Image_B)
               and then Params.Overflow_Mode in Add_Overflow_Mode
               and then KI.Valid_Image (Output)
               and then Output.Width = Image_A.Width
               and then Output.Height = Image_A.Height
               and then
                 (for all Y in Output.Pixels'Range (1)
                  => (for all X in Output.Pixels'Range (2)
                      => Output.Pixels (Y, X)
                           = Spec.Add (Integer (Params.Overflow_Mode),
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
     Post =>
       Valid (Status)
       and then
         (if Input_Failure (Image_A, Image_B) /= Failure_None
          then Status.Failure = Input_Failure (Image_A, Image_B)
          elsif Params.Overflow_Mode not in Subtract_Overflow_Mode
          then Status.Failure = Failure_Bad_Parameter
          else Status.Failure in Failure_None | Failure_Out_Of_Memory)
       and then
         (if Succeeded (Status)
          then Same_Size (Image_A, Image_B)
               and then Params.Overflow_Mode in Subtract_Overflow_Mode
               and then KI.Valid_Image (Output)
               and then Output.Width = Image_A.Width
               and then Output.Height = Image_A.Height
               and then
                 (for all Y in Output.Pixels'Range (1)
                  => (for all X in Output.Pixels'Range (2)
                      => Output.Pixels (Y, X)
                           = Spec.Subtract (Integer (Params.Overflow_Mode),
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
     Post =>
       Valid (Status)
       and then
         (if Input_Failure (Image_A, Image_B) /= Failure_None
          then Status.Failure = Input_Failure (Image_A, Image_B)
          elsif Params.Operation not in Min_Max_Operation
          then Status.Failure = Failure_Bad_Parameter
          else Status.Failure in Failure_None | Failure_Out_Of_Memory)
       and then
         (if Succeeded (Status)
          then Same_Size (Image_A, Image_B)
               and then Params.Operation in Min_Max_Operation
               and then KI.Valid_Image (Output)
               and then Output.Width = Image_A.Width
               and then Output.Height = Image_A.Height
               and then
                 (for all Y in Output.Pixels'Range (1)
                  => (for all X in Output.Pixels'Range (2)
                      => Output.Pixels (Y, X)
                           = Spec.Min_Max (Integer (Params.Operation),
                                        Image_A.Pixels (Y, X),
                                        Image_B.Pixels (Y, X))))
          else Output = null);

end AMV.Kernels.IP_Two_Image;
