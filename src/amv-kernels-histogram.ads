--  Kernel of AMV.Image_Processing.Histogram: the histogram tool
--  (CogHistogramTool, whose run parameters are a CogHistogram and whose
--  result is a CogHistogramResult). The C API is declared in
--  include/amv_image_processing.h.
--
--  Inputs. The tool counts the pixels of an 8-bit image (a handle of
--  AMV.Kernels.Images; null fails with Image_No_Pixels, "InputImage has no
--  pixels") that lie in a pixel region (a handle of AMV.Kernels.Regions;
--  the Ada API passes the whole image for an empty Region). The samples
--  are the pixels of the image the region contains (KR.Contains); pixels
--  of the region outside the image are ignored, and a null region (the
--  empty region) gives no samples at all. That is not an error: the
--  result then has Num_Samples = 0, every bin 0 and every statistic 0.
--  The input image mask (InputImageMask and its offsets) is applied to
--  the region before this kernel runs (ks_pixel_region_restrict_to_mask,
--  as the Ada API does).
--
--  Bins (CogHistogramBinModeConstants, the C codes are VisionPro's
--  values). A grey level V (0 .. 255) is counted in bin Bin_Of (V):
--
--  * Auto (3, the default): 256 bins, one per grey level (Num_Bins is
--    ignored, but must still be valid);
--  * Compatibility (1): Num_Bins bins (1 .. Max_Bins); V goes into bin V,
--    and every V >= Num_Bins - 1 into the last bin;
--  * Uniform (2): Num_Bins bins (1 .. 256) of equal width over the grey
--    levels 0 .. 255: V goes into bin floor (V * Num_Bins / 256).
--
--  Statistics. They are computed from the counts per grey level (the
--  Auto histogram), whatever the bin mode: Minimum and Maximum are the
--  smallest and largest grey level present; Mean is the mean grey level;
--  Variance the population variance (the mean squared difference from
--  Mean) and Standard_Deviation its square root; Median is
--  Inverse_Cumulative_Grey_Level (50), Mode the most frequent grey level
--  (the smallest one on a tie). Inverse_Cumulative_Grey_Level (P) is the
--  smallest grey level L such that at least P percent of the samples are
--  <= L (VisionPro's GetInverseCumulativeGreyLevel). Without samples every
--  statistic is 0. Minimum_WGV_Threshold (GetMinimumWGVThreshold) is
--  Otsu's threshold on the counts per grey level (AMV.Kernels.Otsu: the T
--  in 1 .. 255 that minimises the within-group variance of the samples <
--  T and >= T, the same threshold as the Blob tool's
--  HardDynamicThreshold); Minimum when the samples hold one grey level,
--  0 without samples.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any handles and
--  parameters; no memory leaks; Gold: every bin of a result holds exactly
--  the number of samples whose grey level falls into it (Bin_Count), the
--  counts per grey level likewise, and Num_Samples is the number of pixels
--  of the image the region contains (Sample_Count); Minimum <= Median,
--  Mode, Mean <= Maximum within 0 .. 255, Variance in [0, 65025] and
--  Standard_Deviation in [0, 255].
--
--  Trusted parts (SPARK_Mode Off bodies, listed in docs/PROOF.md): the
--  allocation of a result and of the counting array.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Images;
with AMV.Kernels.Regions;

package AMV.Kernels.Histogram with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;

   type Big is range -2**127 .. 2**127 - 1 with Ghost;
   --  Products of two Int64 values, for contracts.

   ---------------------------------------------------------------------
   --  Run parameters (CogHistogram; C: ks_histogram)
   ---------------------------------------------------------------------

   Bin_Mode_Compatibility : constant Int32 := 1;
   Bin_Mode_Uniform       : constant Int32 := 2;
   Bin_Mode_Auto          : constant Int32 := 3;
   --  CogHistogramBinModeConstants (C: KS_HISTOGRAM_BIN_MODE_*).

   Grey_Levels : constant := 256;
   --  The number of grey levels of an 8-bit image.

   Max_Bins : constant := 65_536;
   --  The largest Num_Bins (C: KS_HISTOGRAM_MAX_BINS).

   type Ks_Histogram is record
      Bin_Mode : Int32 := Bin_Mode_Auto;
      Num_Bins : Int32 := Grey_Levels;
   end record
     with Convention => C;
   --  C: ks_histogram. VisionPro's NumBins (default 256) and BinMode
   --  (default Auto).

   for Ks_Histogram use record
      Bin_Mode at 0 range 0 .. 31;
      Num_Bins at 4 range 0 .. 31;
   end record;

   Auto_Params : constant Ks_Histogram :=
     (Bin_Mode => Bin_Mode_Auto, Num_Bins => Grey_Levels);
   --  The parameters of the counts per grey level.

   function Valid_Params (Params : Ks_Histogram) return Boolean is
     (Params.Num_Bins in 1 .. Max_Bins
      and then (Params.Bin_Mode = Bin_Mode_Compatibility
                or else Params.Bin_Mode = Bin_Mode_Auto
                or else (Params.Bin_Mode = Bin_Mode_Uniform
                         and then Params.Num_Bins <= Grey_Levels)));
   --  Parameters Execute accepts.

   function Bin_Total (Params : Ks_Histogram) return Int32 is
     (if Params.Bin_Mode = Bin_Mode_Auto then Grey_Levels
      else Params.Num_Bins)
   with Pre  => Valid_Params (Params),
        Post => Bin_Total'Result in 1 .. Max_Bins;
   --  The number of bins of a result.

   function Bin_Of (Params : Ks_Histogram; Value : KI.Grey_8) return Natural
   with
     Pre  => Valid_Params (Params),
     Post => Bin_Of'Result < Natural (Bin_Total (Params))
             and then
               (if Params.Bin_Mode = Bin_Mode_Auto
                then Bin_Of'Result = Natural (Value)
                elsif Params.Bin_Mode = Bin_Mode_Compatibility
                then Bin_Of'Result
                       = Natural'Min (Natural (Value),
                                      Natural (Params.Num_Bins) - 1)
                else Bin_Of'Result
                       = Natural (Value) * Natural (Params.Num_Bins)
                         / Grey_Levels);
   --  The bin of grey level Value (see the bin modes above).

   procedure Run_Params_Default (Params : out Ks_Histogram)
   with
     Export, Convention => C,
     External_Name => "ks_histogram_run_params_default",
     Post => Params = (Bin_Mode => Bin_Mode_Auto, Num_Bins => Grey_Levels);
   --  The default run parameters. Cannot fail.

   ---------------------------------------------------------------------
   --  Counting (Gold, ghost)
   ---------------------------------------------------------------------

   --  The pixels of the image are Pixels (Y, X); a sample is a pixel the
   --  region contains. Row_* count along row Y left of column X, Rows_*
   --  the rows above row Y.

   function In_Bin
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Histogram;
      Bin    : Natural;
      Y, X   : Natural) return Boolean
   is
     (KR.Contains (Region, Int32 (X), Int32 (Y))
      and then Bin_Of (Params, Pixels (Y, X)) = Bin)
   with
     Ghost,
     Pre => Valid_Params (Params)
            and then Y in Pixels'Range (1) and then X in Pixels'Range (2);
   --  Pixel (X, Y) is a sample counted in Bin.

   function Row_Count
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Histogram;
      Bin    : Natural;
      Y      : Natural;
      X      : Int64) return Int64
   is
     (if X <= Int64 (Pixels'First (2)) then 0
      else Row_Count (Pixels, Region, Params, Bin, Y, X - 1)
           + (if In_Bin (Pixels, Region, Params, Bin, Y, Natural (X - 1))
              then 1 else 0))
   with
     Ghost,
     Pre  => Valid_Params (Params)
             and then Y in Pixels'Range (1)
             and then X >= Int64 (Pixels'First (2))
             and then X <= Int64 (Pixels'Last (2)) + 1,
     Post => Row_Count'Result in 0 .. X - Int64 (Pixels'First (2)),
     Subprogram_Variant => (Decreases => X);

   function Length_2 (Pixels : KI.Grey_8_Matrix) return Int64 is
     (Int64 (Pixels'Last (2)) - Int64 (Pixels'First (2)) + 1)
   with Ghost;
   --  The number of columns.

   function Rows_Count
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Histogram;
      Bin    : Natural;
      Y      : Int64) return Int64
   is
     (if Y <= Int64 (Pixels'First (1)) then 0
      else Rows_Count (Pixels, Region, Params, Bin, Y - 1)
           + Row_Count (Pixels, Region, Params, Bin, Natural (Y - 1),
                        Int64 (Pixels'Last (2)) + 1))
   with
     Ghost,
     Pre  => Valid_Params (Params)
             and then Pixels'First (2) <= Pixels'Last (2)
             and then Y >= Int64 (Pixels'First (1))
             and then Y <= Int64 (Pixels'Last (1)) + 1,
     Post => Rows_Count'Result >= 0
             and then Rows_Count'Result
                        <= (Y - Int64 (Pixels'First (1))) * 2**31
             and then Big (Rows_Count'Result)
                        <= Big (Y - Int64 (Pixels'First (1)))
                           * Big (Length_2 (Pixels)),
     Subprogram_Variant => (Decreases => Y);

   function Bin_Count
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Histogram;
      Bin    : Natural) return Int64
   is
     (Rows_Count (Pixels, Region, Params, Bin, Int64 (Pixels'Last (1)) + 1))
   with
     Ghost,
     Pre => Valid_Params (Params)
            and then Pixels'First (1) <= Pixels'Last (1)
            and then Pixels'First (2) <= Pixels'Last (2);
   --  Gold: the number of samples counted in Bin.

   function Row_Samples
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Y      : Natural;
      X      : Int64) return Int64
   is
     (if X <= Int64 (Pixels'First (2)) then 0
      else Row_Samples (Pixels, Region, Y, X - 1)
           + (if KR.Contains (Region, Int32 (X - 1), Int32 (Y)) then 1
              else 0))
   with
     Ghost,
     Pre  => Y in Pixels'Range (1)
             and then X >= Int64 (Pixels'First (2))
             and then X <= Int64 (Pixels'Last (2)) + 1,
     Post => Row_Samples'Result in 0 .. X - Int64 (Pixels'First (2)),
     Subprogram_Variant => (Decreases => X);

   function Rows_Samples
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Y      : Int64) return Int64
   is
     (if Y <= Int64 (Pixels'First (1)) then 0
      else Rows_Samples (Pixels, Region, Y - 1)
           + Row_Samples (Pixels, Region, Natural (Y - 1),
                          Int64 (Pixels'Last (2)) + 1))
   with
     Ghost,
     Pre  => Pixels'First (2) <= Pixels'Last (2)
             and then Y >= Int64 (Pixels'First (1))
             and then Y <= Int64 (Pixels'Last (1)) + 1,
     Post => Rows_Samples'Result >= 0
             and then Rows_Samples'Result
                        <= (Y - Int64 (Pixels'First (1))) * 2**31
             and then Big (Rows_Samples'Result)
                        <= Big (Y - Int64 (Pixels'First (1)))
                           * Big (Length_2 (Pixels)),
     Subprogram_Variant => (Decreases => Y);

   function Sample_Count
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data) return Int64
   is
     (Rows_Samples (Pixels, Region, Int64 (Pixels'Last (1)) + 1))
   with
     Ghost,
     Pre => Pixels'First (1) <= Pixels'Last (1)
            and then Pixels'First (2) <= Pixels'Last (2);
   --  Gold: the number of pixels of the image the region contains.

   ---------------------------------------------------------------------
   --  Results (CogHistogramResult; C: ks_histogram_result *, opaque)
   ---------------------------------------------------------------------

   subtype Count_32 is Int32 range 0 .. Int32'Last;
   --  A number of samples.

   type Bin_Counts is array (Natural range <>) of Count_32;
   type Bin_Counts_Access is access Bin_Counts;

   type Ks_Histogram_Result_Data is limited record
      Num_Samples        : Int32 := 0;
      Minimum            : Int32 := 0;
      Maximum            : Int32 := 0;
      Median             : Int32 := 0;
      Mode               : Int32 := 0;
      Mean               : Long_Float := 0.0;
      Variance           : Long_Float := 0.0;
      Standard_Deviation : Long_Float := 0.0;
      Levels             : Bin_Counts (0 .. Grey_Levels - 1) :=
        [others => 0];
      --  The number of samples per grey level.
      Bins               : Bin_Counts_Access;
   end record;
   --  What a result handle designates (opaque for C). Valid_Result states
   --  the part of its invariant that is checked at run time.

   type Ks_Histogram_Result is access Ks_Histogram_Result_Data
     with Convention => C;
   --  C: ks_histogram_result *. Owned: ks_histogram_execute returns it,
   --  ks_histogram_result_destroy frees it.

   Max_Variance : constant := 65_025.0;
   --  255**2, above any variance of grey levels.

   function Valid_Result
     (Result : access constant Ks_Histogram_Result_Data) return Boolean
   is
     (Result /= null
      and then Result.Bins /= null
      and then Result.Bins'First = 0
      and then Result.Bins'Last < Max_Bins
      and then Result.Num_Samples >= 0
      and then Result.Minimum in 0 .. Grey_Levels - 1
      and then Result.Maximum in Result.Minimum .. Grey_Levels - 1
      and then Result.Median in Result.Minimum .. Result.Maximum
      and then Result.Mode in Result.Minimum .. Result.Maximum
      and then Result.Mean >= Long_Float (Result.Minimum)
      and then Result.Mean <= Long_Float (Result.Maximum)
      and then Result.Variance >= 0.0
      and then Result.Variance <= Max_Variance
      and then Result.Standard_Deviation >= 0.0
      and then Result.Standard_Deviation <= 255.0);
   --  Gold where Execute makes it: Minimum <= Median, Mode, Mean <=
   --  Maximum, all within the grey levels.

   type Ks_Histogram_Statistics is record
      Mean               : Long_Float := 0.0;
      Standard_Deviation : Long_Float := 0.0;
      Variance           : Long_Float := 0.0;
      Minimum            : Int32 := 0;
      Maximum            : Int32 := 0;
      Median             : Int32 := 0;
      Mode               : Int32 := 0;
      Num_Samples        : Int32 := 0;
      Num_Bins           : Int32 := 0;
   end record
     with Convention => C;
   --  C: ks_histogram_statistics, the scalar properties of a result.

   for Ks_Histogram_Statistics use record
      Mean               at 0 range 0 .. 63;
      Standard_Deviation at 8 range 0 .. 63;
      Variance           at 16 range 0 .. 63;
      Minimum            at 24 range 0 .. 31;
      Maximum            at 28 range 0 .. 31;
      Median             at 32 range 0 .. 31;
      Mode               at 36 range 0 .. 31;
      Num_Samples        at 40 range 0 .. 31;
      Num_Bins           at 44 range 0 .. 31;
   end record;

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Execute
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Histogram;
      Result : out Ks_Histogram_Result;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_histogram_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then Valid_Params (Params)
                     and then Valid_Result (Result)
                     and then Int64 (Result.Bins'Length)
                                = Int64 (Bin_Total (Params))
                     and then Int64 (Result.Num_Samples)
                                = Sample_Count (Image.Pixels.all, Region)
                     and then
                       (for all L in Result.Levels'Range
                        => Int64 (Result.Levels (L))
                             = Bin_Count (Image.Pixels.all, Region,
                                          Auto_Params, L))
                     and then
                       (for all B in Result.Bins'Range
                        => Int64 (Result.Bins (B))
                             = Bin_Count (Image.Pixels.all, Region, Params,
                                          B))
                else Result = null);
   --  The histogram of the samples (see above). The checks, in order:
   --  the image (Image_No_Pixels, Bad_Parameter), the region (Bad_Parameter,
   --  "Region is not a valid pixel region handle"), the parameters
   --  (Bad_Parameter: "RunParams.NumBins must be in 1 .. 65536",
   --  "RunParams.BinMode must be Compatibility (1), Uniform (2) or Auto
   --  (3)", "RunParams.NumBins must be at most 256 in Uniform mode"), then
   --  Out_Of_Memory. Result is null when the call fails.

   procedure Destroy
     (Result : in out Ks_Histogram_Result;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_histogram_result_destroy",
     Post => Valid (Status) and then Succeeded (Status) and then Result = null;
   --  Frees the result and sets Result to null. Nothing for null. Never
   --  fails.

   procedure Get_Statistics
     (Result     : access constant Ks_Histogram_Result_Data;
      Statistics : out Ks_Histogram_Statistics;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_histogram_result_statistics",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Other
             and then
               (if Succeeded (Status)
                then Valid_Result (Result)
                     and then Statistics.Num_Samples = Result.Num_Samples
                     and then Statistics.Minimum = Result.Minimum
                     and then Statistics.Maximum = Result.Maximum
                     and then Statistics.Median = Result.Median
                     and then Statistics.Mode = Result.Mode
                     and then Statistics.Mean = Result.Mean
                     and then Statistics.Variance = Result.Variance
                     and then Statistics.Standard_Deviation
                                = Result.Standard_Deviation
                     and then Int64 (Statistics.Num_Bins)
                                = Int64 (Result.Bins'Last) + 1
                else Statistics = (others => <>));
   --  The scalar properties of the result (Mean, StandardDeviation,
   --  Variance, Minimum, Maximum, Median, Mode, NumSamples) and the number
   --  of bins. Failures of every accessor: Other for null ("Result: the
   --  histogram tool has no result"), Bad_Parameter for a record that is
   --  not valid ("Result is not a valid histogram result handle").

   procedure Get_Bin
     (Result : access constant Ks_Histogram_Result_Data;
      Index  : Int32;
      Count  : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_histogram_result_bin",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Other | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Valid_Result (Result)
                            and then Index >= 0
                            and then Integer (Index) in Result.Bins'Range
                            and then Count = Result.Bins (Integer (Index))
                       else Count = 0);
   --  The count of bin Index (an element of GetHistogram). Index_Out_Of_Range
   --  unless Index is in 0 .. number of bins - 1 ("GetHistogram: index 300
   --  is outside 0 .. 255").

   procedure Inverse_Cumulative_Grey_Level
     (Result  : access constant Ks_Histogram_Result_Data;
      Percent : Int32;
      Level   : out Int32;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_histogram_result_inverse_cumulative_grey_level",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Other
             and then (if Succeeded (Status)
                       then Valid_Result (Result)
                            and then Percent in 0 .. 100
                            and then Level in Result.Minimum .. Result.Maximum
                       else Level = 0);
   --  GetInverseCumulativeGreyLevel: the smallest grey level L in Minimum ..
   --  Maximum such that 100 * (the number of samples <= L) >= Percent *
   --  Num_Samples; 0 without samples. Bad_Parameter unless Percent is in
   --  0 .. 100 ("GetInverseCumulativeGreyLevel: percent must be in 0 ..
   --  100").

   procedure Minimum_WGV_Threshold
     (Result    : access constant Ks_Histogram_Result_Data;
      Threshold : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_histogram_result_minimum_wgv_threshold",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Other
             and then (if Succeeded (Status)
                       then Valid_Result (Result)
                            and then Threshold in 0 .. Grey_Levels - 1
                       else Threshold = 0);
   --  GetMinimumWGVThreshold: Otsu's threshold T (see above). The samples
   --  < T and >= T are the two groups; Minimum when there is only one
   --  grey level, 0 without samples.

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter;
   --  The image check of Execute, which the Ada API makes before it
   --  rasterises the region, so that an unallocated InputImage is reported
   --  as such ("InputImage has no pixels").

   procedure Check_Result
     (Result : access constant Ks_Histogram_Result_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Other
                and then (if Succeeded (Status) then Valid_Result (Result));
   --  The handle check of the accessors ("GetHistogram: ...").

   procedure Last_Bin
     (Result : access constant Ks_Histogram_Result_Data;
      Last   : out Int32;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Other
                and then (if Succeeded (Status)
                          then Valid_Result (Result)
                               and then Last in 0 .. Max_Bins - 1
                               and then Int64 (Last)
                                          = Int64 (Result.Bins'Last)
                          else Last = 0);
   --  The index of the last bin (the number of bins - 1), for the bounds
   --  of GetHistogram's array. Bad_Parameter for a result without bins
   --  (Execute always makes at least one).

   type Histogram_Counts is array (Natural range <>) of Natural;
   --  GetHistogram as an Ada array.

   procedure Get_Histogram
     (Result : access constant Ks_Histogram_Result_Data;
      Bins   : out Histogram_Counts;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Other
                and then (if Succeeded (Status)
                          then Valid_Result (Result)
                               and then Bins'First = 0
                               and then Bins'Last = Result.Bins'Last
                               and then (for all B in Bins'Range
                                         => Bins (B)
                                              = Natural (Result.Bins (B))));
   --  Copies every bin into Bins, which must be indexed 0 .. Last_Bin
   --  (Bad_Parameter otherwise, "GetHistogram: the array must be indexed
   --  0 .. 255").

end AMV.Kernels.Histogram;
