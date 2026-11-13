pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Filter_Inputs;
with AMV.Kernels.Image_Sampling;

package body AMV.Kernels.IP_Two_Image with SPARK_Mode is

   package FI renames AMV.Kernels.Filter_Inputs;
   package SM renames AMV.Kernels.Image_Sampling;

   type Operation is (Add, Subtract, Min_Max);
   --  The tool an internal call works for.

   function Combined (Op : Operation; Mode : Int32; A, B : KI.Grey_8)
      return KI.Grey_8
   is
     (case Op is
         when Add      => Add_Pixel (Mode, A, B),
         when Subtract => Subtract_Pixel (Mode, A, B),
         when Min_Max  => Min_Max_Pixel (Mode, A, B));
   --  The output pixel of tool Op, Mode its overflow mode or operation.

   function Combined_At
     (Op               : Operation;
      Mode             : Int32;
      Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data;
      X, Y             : Natural) return KI.Grey_8
   with Pre  => Same_Size (Image_A, Image_B)
                and then Y <= Image_A.Pixels'Last (1)
                and then X <= Image_A.Pixels'Last (2),
        Post => Combined_At'Result
                  = Combined (Op, Mode, Image_A.Pixels (Y, X),
                              Image_B.Pixels (Y, X));
   --  The output pixel (X, Y). An ordinary function, so that the loop
   --  invariants of Run mention one call per pixel (with the formula and
   --  the reads of both images in them, a check took up to 10 seconds).

   function Combined_At
     (Op               : Operation;
      Mode             : Int32;
      Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data;
      X, Y             : Natural) return KI.Grey_8 is
   begin
      return Combined (Op, Mode, Image_A.Pixels (Y, X), Image_B.Pixels (Y, X));
   end Combined_At;

   procedure Add_Run_Params_Default (Params : out Ks_IP_Two_Image_Add) is
   begin
      Params := (others => <>);
   end Add_Run_Params_Default;

   procedure Subtract_Run_Params_Default
     (Params : out Ks_IP_Two_Image_Subtract) is
   begin
      Params := (others => <>);
   end Subtract_Run_Params_Default;

   procedure Min_Max_Run_Params_Default
     (Params : out Ks_IP_Two_Image_Min_Max) is
   begin
      Params := (others => <>);
   end Min_Max_Run_Params_Default;

   procedure Check_Inputs
     (Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data;
      Status           : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Same_Size (Image_A, Image_B)
                            and then SM.Usable_Image (Image_A));
   --  Both images usable and of one size.

   procedure Check_Inputs
     (Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data;
      Status           : out Ks_Status) is
   begin
      SM.Check_Image (Image_A, SM.Input_Image_A, Status);
      if not Succeeded (Status) then
         return;
      end if;
      SM.Check_Image (Image_B, SM.Input_Image_B, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Image_A.Width /= Image_B.Width or else Image_A.Height /= Image_B.Height
      then
         Set_Failure
           (Status, Failure_Bad_Parameter,
            "InputImageB is " & FI.Image_Of (Int64 (Image_B.Width)) & " x "
            & FI.Image_Of (Int64 (Image_B.Height))
            & " pixels but InputImageA is "
            & FI.Image_Of (Int64 (Image_A.Width)) & " x "
            & FI.Image_Of (Int64 (Image_A.Height)));
      end if;
   end Check_Inputs;

   procedure Run
     (Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data;
      Op               : Operation;
      Mode             : Int32;
      Output           : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status)
   with
     Pre  => Same_Size (Image_A, Image_B)
             and then SM.Usable_Image (Image_A),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Output)
                     and then Output.Width = Image_A.Width
                     and then Output.Height = Image_A.Height
                     and then
                       (for all Y in Output.Pixels'Range (1)
                        => (for all X in Output.Pixels'Range (2)
                            => Output.Pixels (Y, X)
                                 = Combined (Op, Mode,
                                             Image_A.Pixels (Y, X),
                                             Image_B.Pixels (Y, X))))
                else Output = null);
   --  The output of tool Op for two checked images.

   procedure Run
     (Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data;
      Op               : Operation;
      Mode             : Int32;
      Output           : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status) is
   begin
      KI.Create (Image_A.Width, Image_A.Height, 0, Output, Status);
      if not Succeeded (Status) then
         --  The size is valid, so only the allocation can fail.
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "IPTwoImage: not enough memory for the output image");
         return;
      end if;
      for Y in Output.Pixels'Range (1) loop
         for X in Output.Pixels'Range (2) loop
            Output.Pixels (Y, X) :=
              Combined_At (Op, Mode, Image_A, Image_B, X, Y);
            pragma Loop_Invariant
              (KI.Valid_Image (Output)
               and then Output.Width = Image_A.Width
               and then Output.Height = Image_A.Height);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Output.Pixels'Range (2)
                   => Output.Pixels (J, I)
                        = Combined_At (Op, Mode, Image_A, Image_B, I, J)));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => Output.Pixels (Y, I)
                    = Combined_At (Op, Mode, Image_A, Image_B, I, Y));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Output)
            and then Output.Width = Image_A.Width
            and then Output.Height = Image_A.Height);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Output.Pixels'Range (2)
                => Output.Pixels (J, I)
                     = Combined_At (Op, Mode, Image_A, Image_B, I, J)));
      end loop;
      Set_Success (Status);
   end Run;

   procedure Add_Execute
     (Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data;
      Params           : Ks_IP_Two_Image_Add;
      Output           : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status) is
   begin
      Output := null;
      Check_Inputs (Image_A, Image_B, Status);
      if not Succeeded (Status) then
         return;
      elsif Params.Overflow_Mode
              not in Add_Overflow_Mode_Bounded .. Add_Overflow_Mode_Shift
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.OverflowMode must be Bounded (0), Wrap (1) "
                      & "or Shift (2)");
         return;
      end if;
      Run (Image_A, Image_B, Add, Params.Overflow_Mode, Output, Status);
   end Add_Execute;

   procedure Subtract_Execute
     (Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data;
      Params           : Ks_IP_Two_Image_Subtract;
      Output           : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status) is
   begin
      Output := null;
      Check_Inputs (Image_A, Image_B, Status);
      if not Succeeded (Status) then
         return;
      elsif Params.Overflow_Mode
              not in Subtract_Overflow_Mode_Bounded
                   .. Subtract_Overflow_Mode_Absolute
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.OverflowMode must be Bounded (0), Wrap (1), "
                      & "Shift (2) or Absolute (3)");
         return;
      end if;
      Run (Image_A, Image_B, Subtract, Params.Overflow_Mode, Output, Status);
   end Subtract_Execute;

   procedure Min_Max_Execute
     (Image_A, Image_B : access constant KI.Ks_Image_8_Grey_Data;
      Params           : Ks_IP_Two_Image_Min_Max;
      Output           : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status) is
   begin
      Output := null;
      Check_Inputs (Image_A, Image_B, Status);
      if not Succeeded (Status) then
         return;
      elsif Params.Operation
              not in Min_Max_Operation_Min .. Min_Max_Operation_Max
      then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunParams.Operation must be Min (0) or Max (1)");
         return;
      end if;
      Run (Image_A, Image_B, Min_Max, Params.Operation, Output, Status);
   end Min_Max_Execute;

end AMV.Kernels.IP_Two_Image;
