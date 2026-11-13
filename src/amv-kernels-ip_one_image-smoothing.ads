--  The smoothing operators of AMV.Kernels.IP_One_Image: GaussSampler (a
--  binomial approximation of a Gaussian), BoxFilter (the mean) and
--  UnsharpMask, which subtracts the GaussSampler smoothing. All are
--  separable: a pass along the rows, rounded to grey levels, then a pass
--  along the columns of that result. Integer arithmetic throughout, so
--  the results are exact (see AMV.Kernels.IP_One_Image). Internal.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.IP_One_Image.Common;

private package AMV.Kernels.IP_One_Image.Smoothing
  with SPARK_Mode, Preelaborate
is

   procedure Gauss_Sampler
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Gauss_Sampler;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Params.Smoothness_X in 0 .. Max_Smoothness
             and then Params.Smoothness_Y in 0 .. Max_Smoothness
             and then Params.Magnitude_Shift
                        in -Max_Magnitude_Shift .. Max_Magnitude_Shift,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             (if not Common.Selected (Region, Whole, X, Y)
                              then Result.Pixels (Y, X)
                                     = Source.Pixels (Y, X))))
                else Result = null);
   --  The binomial smoothing (order 2 SmoothnessX along x, then 2
   --  SmoothnessY along y, each pass rounded half up), then the magnitude
   --  shift, for the selected pixels; the input elsewhere.

   procedure Box_Filter
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Box_Filter;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Odd_Size (Params.Kernel_Width, Max_Kernel_Size)
             and then Odd_Size (Params.Kernel_Height, Max_Kernel_Size),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             (if not Common.Selected (Region, Whole, X, Y)
                              then Result.Pixels (Y, X)
                                     = Source.Pixels (Y, X))))
                else Result = null);
   --  The mean of KernelWidth values along x (rounded half up), then of
   --  KernelHeight of those along y, for the selected pixels. Running
   --  sums: the cost does not depend on the kernel's size.

   procedure Unsharp_Mask
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Unsharp_Mask;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Params.Amount >= 0.0
             and then Params.Amount <= Max_Amount
             and then Params.Smoothness_X in 0 .. Max_Smoothness
             and then Params.Smoothness_Y in 0 .. Max_Smoothness,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             (if not Common.Selected (Region, Whole, X, Y)
                              then Result.Pixels (Y, X)
                                     = Source.Pixels (Y, X))))
                else Result = null);
   --  V + Amount * (V - G) for the selected pixels, G being the binomial
   --  smoothing of GaussSampler (without shift), rounded and limited to
   --  0 .. 255.

   procedure High_Pass_Filter
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_High_Pass_Filter;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Params.Processing_Mode
                        in High_Pass_Gauss .. High_Pass_Median
             and then Params.Smoothness_X in 0 .. Max_Smoothness
             and then Params.Smoothness_Y in 0 .. Max_Smoothness
             and then Odd_Size (Params.Kernel_Width, Max_Kernel_Size)
             and then Odd_Size (Params.Kernel_Height, Max_Kernel_Size),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             (if not Common.Selected (Region, Whole, X, Y)
                              then Result.Pixels (Y, X)
                                     = Source.Pixels (Y, X))))
                else Result = null);
   --  V - S + 128 for the selected pixels, limited to 0 .. 255, S being V
   --  smoothed by Params.Processing_Mode: the binomial smoothing of
   --  GaussSampler (without shift), the mean of BoxFilter or the median of
   --  MedianNxM.

end AMV.Kernels.IP_One_Image.Smoothing;
