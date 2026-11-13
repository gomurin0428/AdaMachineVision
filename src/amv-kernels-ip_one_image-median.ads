--  Median3x3 and MedianNxM of AMV.Kernels.IP_One_Image: the median of the
--  KernelWidth x KernelHeight neighbourhood (an odd number of values, so
--  the middle one). Huang's running histogram: along a row the window
--  moves by one column at a time, its histogram loses one column and
--  gains one (2 KernelHeight updates), and the median moves from the
--  previous one, keeping the count of values below it. Each row starts
--  with a new histogram of KernelWidth x KernelHeight values. Internal.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.IP_One_Image.Common;

private package AMV.Kernels.IP_One_Image.Median
  with SPARK_Mode, Preelaborate
is

   procedure Median_Filter
     (Source        : access constant KI.Ks_Image_8_Grey_Data;
      Region        : access constant KR.Ks_Pixel_Region_Data;
      Whole         : Boolean;
      Width, Height : Int32;
      Result        : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Odd_Size (Width, Max_Kernel_Size)
             and then Odd_Size (Height, Max_Kernel_Size),
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
   --  The median of the Width x Height neighbourhood (reflected at the
   --  border) for the selected pixels, the input elsewhere.

end AMV.Kernels.IP_One_Image.Median;
