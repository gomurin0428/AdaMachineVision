pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.Filter_Inputs;
with AMV.Kernels.Image_Math;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Image_Sharpness with SPARK_Mode is

   package FI renames AMV.Kernels.Filter_Inputs;
   package KM renames AMV.Kernels.Image_Math;
   package N renames AMV.Kernels.Numerics;

   use type KM.Ks_Real_Image;

   procedure Free is new Ada.Unchecked_Deallocation
     (KM.Real_Matrix, KM.Real_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KM.Ks_Real_Image_Data, KM.Ks_Real_Image);

   Max_Derivative : constant := 127.5;
   --  The largest derivative ks_real_image_sobel gives for values in
   --  0 .. 255 (smoothing keeps them there). Reading through this clamp
   --  never changes such a derivative.

   Sum_Limit : constant := 2.0**60;
   --  Above every sum of the scores: at most 2**31 terms of at most
   --  32512.5 (below 2**47). The clamps at this limit never act.

   ---------------------------------------------------------------------
   --  Messages and parameters
   ---------------------------------------------------------------------

   procedure Bad
     (Status  : out Ks_Status;
      Message : String)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad
     (Status  : out Ks_Status;
      Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   function Frequency_OK (F : Long_Float) return Boolean is
     (F >= 0.0 and then F <= 0.5);
   --  False for a NaN at run time.

   procedure Check_Params
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Params : Ks_Image_Sharpness;
      Status : out Ks_Status)
   with
     Pre  => FI.Usable_Image (Image),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Params.Mode
                              in Mode_Abs_Diff | Mode_Gradient_Energy
                            and then (if Params.Mode = Mode_Abs_Diff
                                      then Params.Abs_Diff_Distance_X
                                             in 0 .. Image.Width - 1
                                           and then Params.Abs_Diff_Distance_Y
                                                      in 0 .. Image.Height - 1)
                            and then Params.Gradient_Energy_Low_Pass_Smoothing
                                       in 0 .. Max_Low_Pass_Smoothing);

   procedure Check_Params
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Params : Ks_Image_Sharpness;
      Status : out Ks_Status) is
   begin
      if Params.Mode /= Mode_Auto_Correlation
        and then Params.Mode /= Mode_Abs_Diff
        and then Params.Mode /= Mode_Band_Pass
        and then Params.Mode /= Mode_Gradient_Energy
      then
         Bad (Status, "RunParams.Mode must be AutoCorrelation (1), AbsDiff "
                      & "(2), BandPass (4) or GradientEnergy (8)");
      elsif Params.Abs_Diff_Distance_X < 0 then
         Bad (Status, "RunParams.AbsDiffDistanceX must be >= 0");
      elsif Params.Abs_Diff_Distance_Y < 0 then
         Bad (Status, "RunParams.AbsDiffDistanceY must be >= 0");
      elsif Params.Gradient_Energy_Low_Pass_Smoothing
              not in 0 .. Max_Low_Pass_Smoothing
      then
         Bad (Status, "RunParams.GradientEnergyLowPassSmoothing must be in "
                      & "0 .. 100");
      elsif not (Params.Auto_Correlation_Noise_Level >= 0.0
                 and then Params.Auto_Correlation_Noise_Level
                            <= Max_Noise_Level)
      then
         Bad (Status, "RunParams.AutoCorrelationNoiseLevel must be in "
                      & "0 .. 255");
      elsif not Frequency_OK (Params.Band_Pass_Max_Frequency) then
         Bad (Status, "RunParams.BandPassMaxFrequency must be in 0 .. 0.5");
      elsif not Frequency_OK (Params.Band_Pass_Min_Frequency) then
         Bad (Status, "RunParams.BandPassMinFrequency must be in 0 .. 0.5");
      elsif Params.Band_Pass_Min_Frequency > Params.Band_Pass_Max_Frequency
      then
         Bad (Status, "RunParams.BandPassMinFrequency must not exceed "
                      & "BandPassMaxFrequency");
      elsif Params.Mode = Mode_Auto_Correlation then
         Bad (Status, "RunParams.Mode: AutoCorrelation is not implemented");
      elsif Params.Mode = Mode_Band_Pass then
         Bad (Status, "RunParams.Mode: BandPass is not implemented");
      elsif Params.Mode = Mode_Abs_Diff
        and then Params.Abs_Diff_Distance_X >= Image.Width
      then
         Bad (Status, "RunParams.AbsDiffDistanceX must be less than the "
                      & "width of InputImage");
      elsif Params.Mode = Mode_Abs_Diff
        and then Params.Abs_Diff_Distance_Y >= Image.Height
      then
         Bad (Status, "RunParams.AbsDiffDistanceY must be less than the "
                      & "height of InputImage");
      else
         --  GradientEnergy does not use the distances; only AbsDiff
         --  requires them to fit the image.
         Set_Success (Status);
      end if;
   end Check_Params;

   procedure Run_Params_Default (Params : out Ks_Image_Sharpness) is
   begin
      Params := (others => <>);
   end Run_Params_Default;

   ---------------------------------------------------------------------
   --  Scores
   ---------------------------------------------------------------------

   function Mean_Within
     (Sum   : Long_Float;
      Count : Int64;
      Limit : Long_Float) return Long_Float
   with
     Pre  => Sum >= 0.0 and then Sum <= Sum_Limit
             and then Count in 0 .. 2**63 - 2**32
             and then Limit >= 1.0 and then Limit <= Max_Gradient_Energy,
     Post => Mean_Within'Result >= 0.0 and then Mean_Within'Result <= Limit;
   --  Sum / Count (0 for no samples). Every term of Sum is at most Limit,
   --  so the quotient is at most Limit; the result is kept there anyway.

   function Mean_Within
     (Sum   : Long_Float;
      Count : Int64;
      Limit : Long_Float) return Long_Float
   is
      Ratio : Long_Float;
      Fits  : Boolean;
   begin
      if Count = 0 then
         return 0.0;
      end if;
      N.Ratio_Within (Sum, Long_Float (Count), Limit, Ratio, Fits);
      return (if Fits then Ratio else Limit);
   end Mean_Within;

   function Accumulate (Sum, Term : Long_Float) return Long_Float
   with
     Pre  => Sum >= 0.0 and then Sum <= Sum_Limit
             and then Term >= 0.0 and then Term <= Max_Gradient_Energy,
     Post => Accumulate'Result >= 0.0 and then Accumulate'Result <= Sum_Limit;
   --  Sum + Term, kept at most Sum_Limit (which it never reaches).

   function Accumulate (Sum, Term : Long_Float) return Long_Float is
     (Long_Float'Min (Sum + Term, Sum_Limit));

   function Abs_Difference (A, B : KI.Grey_8) return Long_Float
   with Post => Abs_Difference'Result >= 0.0
                and then Abs_Difference'Result <= 255.0;
   --  abs (B - A) as a Long_Float.

   function Abs_Difference (A, B : KI.Grey_8) return Long_Float is
      D : constant Natural := abs (Integer (B) - Integer (A));
   begin
      return Long_Float (D);
   end Abs_Difference;

   function Energy (Dx, Dy : Long_Float) return Long_Float
   with Post => Energy'Result >= 0.0
                and then Energy'Result <= Max_Gradient_Energy;
   --  Dx**2 + Dy**2 for derivatives of grey levels.

   function Energy (Dx, Dy : Long_Float) return Long_Float is
     (N.Square_Within (N.Clamp (Dx, Max_Derivative), Max_Derivative)
      + N.Square_Within (N.Clamp (Dy, Max_Derivative), Max_Derivative));

   function Energy_Mean
     (Gx, Gy : access constant KM.Ks_Real_Image_Data;
      Region : access constant KR.Ks_Pixel_Region_Data) return Long_Float
   with
     Pre  => KM.Valid_Image (Gx) and then KM.Valid_Image (Gy)
             and then Gy.Width = Gx.Width and then Gy.Height = Gx.Height,
     Post => Energy_Mean'Result >= 0.0
             and then Energy_Mean'Result <= Max_Gradient_Energy;
   --  The mean of Energy over the pixels the region contains.

   function Energy_Mean
     (Gx, Gy : access constant KM.Ks_Real_Image_Data;
      Region : access constant KR.Ks_Pixel_Region_Data) return Long_Float
   is
      Sum   : Long_Float := 0.0;
      Count : Int64 := 0;
   begin
      for Y in Gx.Pixels'Range (1) loop
         for X in Gx.Pixels'Range (2) loop
            if KR.Contains (Region, Int32 (X), Int32 (Y)) then
               Sum := Accumulate
                 (Sum, Energy (Gx.Pixels (Y, X), Gy.Pixels (Y, X)));
               Count := Count + 1;
            end if;
            pragma Loop_Invariant (Sum >= 0.0 and then Sum <= Sum_Limit);
            pragma Loop_Invariant
              (Count in 0 .. Int64 (Y) * 2**31 + Int64 (X) + 1);
         end loop;
         pragma Loop_Invariant (Sum >= 0.0 and then Sum <= Sum_Limit);
         pragma Loop_Invariant (Count in 0 .. (Int64 (Y) + 1) * 2**31);
      end loop;
      return Mean_Within (Sum, Count, Max_Gradient_Energy);
   end Energy_Mean;

   function Abs_Diff_Mean
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      DX, DY : Int32) return Long_Float
   with
     Pre  => KI.Valid_Image (Image)
             and then DX in 0 .. Image.Width - 1
             and then DY in 0 .. Image.Height - 1,
     Post => Abs_Diff_Mean'Result >= 0.0
             and then Abs_Diff_Mean'Result <= 255.0;
   --  The AbsDiff score. The sum of at most 2**31 differences of at most
   --  255 is an integer below 2**39, which a Long_Float holds exactly.

   function Abs_Diff_Mean
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      DX, DY : Int32) return Long_Float
   is
      Last_X : constant Natural := Natural (Image.Width - 1 - DX);
      Last_Y : constant Natural := Natural (Image.Height - 1 - DY);
      Sum    : Long_Float := 0.0;
      Count  : Int64 := 0;
   begin
      for Y in 0 .. Last_Y loop
         for X in 0 .. Last_X loop
            if KR.Contains (Region, Int32 (X), Int32 (Y)) then
               Sum := Accumulate
                 (Sum,
                  Abs_Difference
                    (Image.Pixels (Y, X),
                     Image.Pixels (Y + Natural (DY), X + Natural (DX))));
               Count := Count + 1;
            end if;
            pragma Loop_Invariant (Sum >= 0.0 and then Sum <= Sum_Limit);
            pragma Loop_Invariant
              (Count in 0 .. Int64 (Y) * 2**31 + Int64 (X) + 1);
         end loop;
         pragma Loop_Invariant (Sum >= 0.0 and then Sum <= Sum_Limit);
         pragma Loop_Invariant (Count in 0 .. (Int64 (Y) + 1) * 2**31);
      end loop;
      return Mean_Within (Sum, Count, 255.0);
   end Abs_Diff_Mean;

   procedure Gradient_Energy
     (Image     : access constant KI.Ks_Image_8_Grey_Data;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Smoothing : Int32;
      Score     : out Long_Float;
      Done      : out Boolean)
   with
     Pre  => FI.Usable_Image (Image)
             and then Smoothing in 0 .. Max_Low_Pass_Smoothing,
     Post => Score >= 0.0 and then Score <= Max_Gradient_Energy
             and then (if not Done then Score = 0.0);
   --  The GradientEnergy score. Done is False when the memory for the
   --  floating-point images cannot be allocated.

   procedure Gradient_Energy
     (Image     : access constant KI.Ks_Image_8_Grey_Data;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Smoothing : Int32;
      Score     : out Long_Float;
      Done      : out Boolean)
   is
      Real, Smooth, Gx, Gy : KM.Ks_Real_Image;
      Status               : Ks_Status;
   begin
      Score := 0.0;
      Done := False;
      KM.From_Grey_8 (Image, Real, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Smoothing > 0 then
         KM.Gaussian_Smooth (Real, Long_Float (Smoothing), Smooth, Status);
         Free (Real.Pixels);
         Free (Real);
         if not Succeeded (Status) then
            return;
         end if;
         Real := Smooth;
      end if;
      KM.Sobel (Real, Gx, Gy, Status);
      Free (Real.Pixels);
      Free (Real);
      if not Succeeded (Status) then
         return;
      end if;
      Score := Energy_Mean (Gx, Gy, Region);
      Free (Gx.Pixels);
      Free (Gx);
      Free (Gy.Pixels);
      Free (Gy);
      Done := True;
   end Gradient_Energy;

   ---------------------------------------------------------------------
   --  Entry point
   ---------------------------------------------------------------------

   procedure Execute
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Image_Sharpness;
      Score  : out Long_Float;
      Status : out Ks_Status)
   is
      Done : Boolean;
   begin
      Score := 0.0;
      FI.Check_Input (Image, Region, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Params (Image, Params, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Params.Mode = Mode_Abs_Diff then
         Score := Abs_Diff_Mean
           (Image, Region, Params.Abs_Diff_Distance_X,
            Params.Abs_Diff_Distance_Y);
      else
         Gradient_Energy
           (Image, Region, Params.Gradient_Energy_Low_Pass_Smoothing, Score,
            Done);
         if not Done then
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "ImageSharpness: not enough memory for the "
                         & "gradients");
         end if;
      end if;
   end Execute;

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      FI.Check_Image (Image, Status);
   end Check_Input_Image;

end AMV.Kernels.Image_Sharpness;
