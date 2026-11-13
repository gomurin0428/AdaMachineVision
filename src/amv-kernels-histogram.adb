pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;

with AMV.Kernels.Filter_Inputs;
with AMV.Kernels.Numerics;

with AMV.Kernels.Otsu;

package body AMV.Kernels.Histogram with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package FI renames AMV.Kernels.Filter_Inputs;
   package N renames AMV.Kernels.Numerics;

   type Int64_Counts is array (Natural range <>) of Int64;
   type Int64_Counts_Access is access Int64_Counts;
   --  Counts while they are being made (each bin of a row of at most
   --  2**31 pixels adds at most 2**31, so no partial count overflows).

   procedure Free is new Ada.Unchecked_Deallocation
     (Bin_Counts, Bin_Counts_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Histogram_Result_Data, Ks_Histogram_Result);
   procedure Free is new Ada.Unchecked_Deallocation
     (Int64_Counts, Int64_Counts_Access);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Result
     (Last_Bin : Natural;
      Result   : out Ks_Histogram_Result)
   with
     Global => null,
     Pre    => Last_Bin < Max_Bins,
     Post   => (if Result /= null
                then Result.Bins /= null
                     and then Result.Bins'First = 0
                     and then Result.Bins'Last = Last_Bin
                     and then Result.Num_Samples = 0
                     and then Result.Minimum = 0
                     and then Result.Maximum = 0
                     and then Result.Median = 0
                     and then Result.Mode = 0
                     and then Result.Mean = 0.0
                     and then Result.Variance = 0.0
                     and then Result.Standard_Deviation = 0.0);
   --  A new result with Last_Bin + 1 bins (all 0) and the record's
   --  default values, or null when the memory cannot be allocated (the
   --  bins are freed when the record cannot be allocated). Trusted: the
   --  allocator raises Storage_Error, which SPARK cannot express.

   procedure Allocate_Result
     (Last_Bin : Natural;
      Result   : out Ks_Histogram_Result)
     with SPARK_Mode => Off
   is
      Bins : Bin_Counts_Access;
   begin
      Result := null;
      Bins := new Bin_Counts'(0 .. Last_Bin => 0);
      Result := new Ks_Histogram_Result_Data;
      Result.Bins := Bins;
   exception
      when Storage_Error =>
         Free (Bins);
         Result := null;
   end Allocate_Result;

   procedure Allocate_Counts
     (Last   : Natural;
      Counts : out Int64_Counts_Access)
   with
     Global => null,
     Post   => (if Counts /= null
                then Counts'First = 0 and then Counts'Last = Last);
   --  A new counting array indexed 0 .. Last (every count 0), or null
   --  when the memory cannot be allocated. Trusted as above.

   procedure Allocate_Counts
     (Last   : Natural;
      Counts : out Int64_Counts_Access)
     with SPARK_Mode => Off
   is
   begin
      Counts := new Int64_Counts'(0 .. Last => 0);
   exception
      when Storage_Error =>
         Counts := null;
   end Allocate_Counts;

   ---------------------------------------------------------------------
   --  Proof helpers
   ---------------------------------------------------------------------

   procedure Lemma_Uniform (V, Bins : Natural)
   with
     Ghost,
     Global => null,
     Pre    => V <= Grey_Levels - 1 and then Bins in 1 .. Grey_Levels,
     Post   => V * Bins <= (Grey_Levels - 1) * Bins
               and then V * Bins / Grey_Levels < Bins;
   --  The uniform bin of V lies below Bins.

   procedure Lemma_Uniform (V, Bins : Natural) is null;

   procedure Lemma_Product (A, B : Int64)
   with
     Ghost,
     Global => null,
     Pre    => A in 0 .. Grey_Levels - 1 and then B in 0 .. 2**31 - 1,
     Post   => A * B in 0 .. 2**39;
   --  The weight of a grey level in the sum of grey levels.

   procedure Lemma_Product (A, B : Int64) is null;

   procedure Lemma_Total_Bound (H, W, Count : Int64)
   with
     Ghost,
     Global => null,
     Pre    => H in 1 .. 2**31 and then W in 1 .. 2**31
               and then H * W <= KI.Max_Pixels
               and then Count >= 0
               and then Big (Count) <= Big (H) * Big (W),
     Post   => Count <= KI.Max_Pixels;
   --  A count bounded by the product of the image's sides fits in a
   --  Count_32.

   procedure Lemma_Total_Bound (H, W, Count : Int64) is null;

   ---------------------------------------------------------------------
   --  Messages
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

   procedure Out_Of_Memory (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Out_Of_Memory;

   procedure Out_Of_Memory (Status : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Out_Of_Memory,
                   "Histogram: not enough memory for the result");
   end Out_Of_Memory;

   ---------------------------------------------------------------------
   --  Parameters and bins
   ---------------------------------------------------------------------

   procedure Check_Params
     (Params : Ks_Histogram;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status) then Valid_Params (Params));

   procedure Check_Params
     (Params : Ks_Histogram;
      Status : out Ks_Status) is
   begin
      if Params.Num_Bins not in 1 .. Max_Bins then
         Bad (Status, "RunParams.NumBins must be in 1 .. 65536");
      elsif Params.Bin_Mode /= Bin_Mode_Compatibility
        and then Params.Bin_Mode /= Bin_Mode_Uniform
        and then Params.Bin_Mode /= Bin_Mode_Auto
      then
         Bad (Status, "RunParams.BinMode must be Compatibility (1), "
                      & "Uniform (2) or Auto (3)");
      elsif Params.Bin_Mode = Bin_Mode_Uniform
        and then Params.Num_Bins > Grey_Levels
      then
         Bad (Status, "RunParams.NumBins must be at most 256 in Uniform "
                      & "mode");
      else
         Set_Success (Status);
      end if;
   end Check_Params;

   function Bin_Of (Params : Ks_Histogram; Value : KI.Grey_8) return Natural
   is
      V : constant Natural := Natural (Value);
   begin
      if Params.Bin_Mode = Bin_Mode_Auto then
         return V;
      elsif Params.Bin_Mode = Bin_Mode_Compatibility then
         return Natural'Min (V, Natural (Params.Num_Bins) - 1);
      else
         Lemma_Uniform (V, Natural (Params.Num_Bins));
         return V * Natural (Params.Num_Bins) / Grey_Levels;
      end if;
   end Bin_Of;

   procedure Run_Params_Default (Params : out Ks_Histogram) is
   begin
      Params := (Bin_Mode => Bin_Mode_Auto, Num_Bins => Grey_Levels);
   end Run_Params_Default;

   ---------------------------------------------------------------------
   --  Counting
   ---------------------------------------------------------------------

   function Count_Samples
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data) return Int64
   with
     Pre  => Pixels'First (1) = 0 and then Pixels'First (2) = 0
             and then Pixels'Last (1) >= 0 and then Pixels'Last (2) >= 0
             and then (Int64 (Pixels'Last (1)) + 1)
                        * (Int64 (Pixels'Last (2)) + 1) <= KI.Max_Pixels,
     Post => Count_Samples'Result = Sample_Count (Pixels, Region)
             and then Count_Samples'Result in 0 .. KI.Max_Pixels;
   --  The number of pixels the region contains.

   function Count_Samples
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data) return Int64
   is
      Count : Int64 := 0;
   begin
      for Y in Pixels'Range (1) loop
         pragma Loop_Invariant
           (Count = Rows_Samples (Pixels, Region, Int64 (Y)));
         for X in Pixels'Range (2) loop
            if KR.Contains (Region, Int32 (X), Int32 (Y)) then
               Count := Count + 1;
            end if;
            pragma Loop_Invariant
              (Count = Rows_Samples (Pixels, Region, Int64 (Y))
                       + Row_Samples (Pixels, Region, Y, Int64 (X) + 1));
         end loop;
      end loop;
      Lemma_Total_Bound
        (Int64 (Pixels'Last (1)) + 1, Int64 (Pixels'Last (2)) + 1, Count);
      return Count;
   end Count_Samples;

   procedure Count_Into
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Histogram;
      Counts : out Int64_Counts)
   with
     Pre  => Valid_Params (Params)
             and then Pixels'First (1) = 0 and then Pixels'First (2) = 0
             and then Pixels'Last (1) >= 0 and then Pixels'Last (2) >= 0
             and then Counts'First = 0
             and then Int64 (Counts'Last) = Int64 (Bin_Total (Params)) - 1,
     Post => (for all B in Counts'Range
              => Counts (B) = Bin_Count (Pixels, Region, Params, B));
   --  Counts (B) := the number of samples in bin B.

   procedure Count_Into
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Histogram;
      Counts : out Int64_Counts) is
   begin
      Counts := [others => 0];
      for Y in Pixels'Range (1) loop
         pragma Loop_Invariant
           (for all B in Counts'Range
            => Counts (B) = Rows_Count (Pixels, Region, Params, B,
                                        Int64 (Y)));
         for X in Pixels'Range (2) loop
            if KR.Contains (Region, Int32 (X), Int32 (Y)) then
               declare
                  B : constant Natural := Bin_Of (Params, Pixels (Y, X));
               begin
                  Counts (B) := Counts (B) + 1;
               end;
            end if;
            pragma Loop_Invariant
              (for all B in Counts'Range
               => Counts (B)
                    = Rows_Count (Pixels, Region, Params, B, Int64 (Y))
                      + Row_Count (Pixels, Region, Params, B, Y,
                                   Int64 (X) + 1));
         end loop;
      end loop;
   end Count_Into;

   procedure Count_Bins
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Histogram;
      Bins   : out Bin_Counts;
      Done   : out Boolean)
   with
     Pre  => Valid_Params (Params)
             and then Pixels'First (1) = 0 and then Pixels'First (2) = 0
             and then Pixels'Last (1) >= 0 and then Pixels'Last (2) >= 0
             and then (Int64 (Pixels'Last (1)) + 1)
                        * (Int64 (Pixels'Last (2)) + 1) <= KI.Max_Pixels
             and then Bins'First = 0
             and then Int64 (Bins'Last) = Int64 (Bin_Total (Params)) - 1,
     Post => (if Done
              then (for all B in Bins'Range
                    => Int64 (Bins (B))
                         = Bin_Count (Pixels, Region, Params, B)));
   --  Bins (B) := the number of samples in bin B. Done is False (and Bins
   --  unspecified) when the counting array cannot be allocated.

   procedure Count_Bins
     (Pixels : KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Histogram;
      Bins   : out Bin_Counts;
      Done   : out Boolean)
   is
      Counts : Int64_Counts_Access;
      H      : constant Int64 := Int64 (Pixels'Last (1)) + 1;
      W      : constant Int64 := Int64 (Pixels'Last (2)) + 1;
   begin
      Bins := [others => 0];
      Allocate_Counts (Bins'Last, Counts);
      if Counts = null then
         Done := False;
         return;
      end if;
      Count_Into (Pixels, Region, Params, Counts.all);
      for B in Bins'Range loop
         pragma Assert
           (Counts (B) = Bin_Count (Pixels, Region, Params, B));
         Lemma_Total_Bound (H, W, Counts (B));
         Bins (B) := Count_32 (Counts (B));
         pragma Loop_Invariant
           (Counts'First = 0 and then Counts'Last = Bins'Last);
         pragma Loop_Invariant
           (for all K in Counts'Range
            => Counts (K) = Bin_Count (Pixels, Region, Params, K));
         pragma Loop_Invariant
           (for all K in 0 .. B
            => Int64 (Bins (K)) = Bin_Count (Pixels, Region, Params, K));
      end loop;
      Free (Counts);
      Done := True;
   end Count_Bins;

   ---------------------------------------------------------------------
   --  Statistics
   ---------------------------------------------------------------------

   subtype Grey_Level is Int32 range 0 .. Grey_Levels - 1;

   function Inverse_Level
     (Levels           : Bin_Counts;
      Minimum, Maximum : Grey_Level;
      Total            : Int64;
      Percent          : Int32) return Grey_Level
   with
     Pre  => Levels'First = 0 and then Levels'Last = Grey_Levels - 1
             and then Minimum <= Maximum
             and then Total in 0 .. 2**39
             and then Percent in 0 .. 100,
     Post => Inverse_Level'Result in Minimum .. Maximum;
   --  The smallest grey level L in Minimum .. Maximum with 100 * (the
   --  number of samples <= L) >= Percent * Total (Maximum when there is
   --  none).

   function Inverse_Level
     (Levels           : Bin_Counts;
      Minimum, Maximum : Grey_Level;
      Total            : Int64;
      Percent          : Int32) return Grey_Level
   is
      Wanted     : constant Int64 := Int64 (Percent) * Total;
      Cumulative : Int64 := 0;
   begin
      for L in Natural (Minimum) .. Natural (Maximum) loop
         Cumulative := Cumulative + Int64 (Levels (L));
         if 100 * Cumulative >= Wanted then
            return Grey_Level (L);
         end if;
         pragma Loop_Invariant
           (Cumulative in 0 .. Int64 (L - Natural (Minimum) + 1) * 2**31);
      end loop;
      return Maximum;
   end Inverse_Level;

   function Mean_Of
     (Sum, Total : Int64;
      Low, High  : Grey_Level) return Long_Float
   with
     Pre  => Sum in 0 .. 2**47 and then Total in 1 .. 2**39
             and then Low <= High,
     Post => Mean_Of'Result >= Long_Float (Low)
             and then Mean_Of'Result <= Long_Float (High);
   --  Sum / Total, kept within [Low, High] (the mean of grey levels in
   --  Low .. High lies there, but the rounded quotient of equal values may
   --  not).

   function Mean_Of
     (Sum, Total : Int64;
      Low, High  : Grey_Level) return Long_Float
   is
      Ratio : Long_Float;
      Fits  : Boolean;
   begin
      N.Ratio_Within
        (Long_Float (Sum), Long_Float (Total), 256.0, Ratio, Fits);
      if not Fits or else Ratio < Long_Float (Low) then
         return Long_Float (Low);
      elsif Ratio > Long_Float (High) then
         return Long_Float (High);
      else
         return Ratio;
      end if;
   end Mean_Of;

   procedure Compute_Statistics
     (Levels                         : Bin_Counts;
      Minimum, Maximum, Median, Mode : out Int32;
      Mean, Variance, Deviation      : out Long_Float)
   with
     Pre  => Levels'First = 0 and then Levels'Last = Grey_Levels - 1,
     Post => Minimum in 0 .. Grey_Levels - 1
             and then Maximum in Minimum .. Grey_Levels - 1
             and then Median in Minimum .. Maximum
             and then Mode in Minimum .. Maximum
             and then Mean >= Long_Float (Minimum)
             and then Mean <= Long_Float (Maximum)
             and then Variance >= 0.0 and then Variance <= Max_Variance
             and then Deviation >= 0.0 and then Deviation <= 255.0;
   --  The statistics of the counts per grey level (see the spec); all 0
   --  when every count is 0.

   procedure Compute_Statistics
     (Levels                         : Bin_Counts;
      Minimum, Maximum, Median, Mode : out Int32;
      Mean, Variance, Deviation      : out Long_Float)
   is
      Found   : Boolean := False;
      Low     : Grey_Level := 0;
      High    : Grey_Level;
      Total   : Int64 := 0;
      Sum     : Int64 := 0;
      Best    : Count_32;
      Squares : Long_Float := 0.0;
      Ratio   : Long_Float;
      Fits    : Boolean;
   begin
      Minimum := 0;
      Maximum := 0;
      Median := 0;
      Mode := 0;
      Mean := 0.0;
      Variance := 0.0;
      Deviation := 0.0;

      --  The smallest and the largest grey level present.
      for L in Levels'Range loop
         if Levels (L) > 0 then
            Low := Grey_Level (L);
            Found := True;
            exit;
         end if;
      end loop;
      if not Found then
         return;
      end if;
      pragma Assert (Levels (Natural (Low)) >= 1);
      High := Low;
      for L in reverse Levels'Range loop
         exit when Int32 (L) <= Low;
         if Levels (L) > 0 then
            High := Grey_Level (L);
            exit;
         end if;
         pragma Loop_Invariant (High = Low);
      end loop;

      --  The number of samples and the sum of their grey levels.
      for L in Natural (Low) .. Natural (High) loop
         Lemma_Product (Int64 (L), Int64 (Levels (L)));
         Total := Total + Int64 (Levels (L));
         Sum := Sum + Int64 (L) * Int64 (Levels (L));
         pragma Loop_Invariant
           (Total in Int64 (Levels (Natural (Low)))
                     .. Int64 (L - Natural (Low) + 1) * 2**31);
         pragma Loop_Invariant
           (Sum in 0 .. Int64 (L - Natural (Low) + 1) * 2**39);
      end loop;
      pragma Assert (Total >= 1 and then Total <= 2**39);
      pragma Assert (Sum in 0 .. 2**47);

      --  The most frequent grey level (the first one on a tie).
      Mode := Low;
      Best := Levels (Natural (Low));
      for L in Natural (Low) + 1 .. Natural (High) loop
         if Levels (L) > Best then
            Best := Levels (L);
            Mode := Int32 (L);
         end if;
         pragma Loop_Invariant (Mode in Low .. Int32 (L));
      end loop;

      Median := Inverse_Level (Levels, Low, High, Total, 50);
      Minimum := Low;
      Maximum := High;

      Mean := Mean_Of (Sum, Total, Low, High);

      --  The population variance about the mean. Every squared difference
      --  is at most 255**2, so the sum is at most 255**2 * 2**31 (below
      --  2**47): the clamp to [0, 2**60] never acts.
      for L in Natural (Low) .. Natural (High) loop
         declare
            D      : constant Long_Float := Long_Float (L) - Mean;
            Square : constant Long_Float := N.Square_Within (D, 255.0);
            Term   : constant Long_Float :=
              N.Mul_Within
                (Square, Long_Float (Levels (L)), Max_Variance, 2.0**31);
         begin
            Squares :=
              Long_Float'Max (0.0, N.Clamp (Squares + Term, 2.0**60));
         end;
         pragma Loop_Invariant (Squares >= 0.0 and then Squares <= 2.0**60);
      end loop;
      N.Ratio_Within
        (Squares, Long_Float (Total), Max_Variance, Ratio, Fits);
      --  The variance of grey levels is at most 127.5**2, far below the
      --  limit, so Fits always holds.
      Variance := (if Fits then Ratio else Max_Variance);
      Deviation := Long_Float'Min (EF.Sqrt (Variance), 255.0);
   end Compute_Statistics;

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Execute
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_Histogram;
      Result : out Ks_Histogram_Result;
      Status : out Ks_Status)
   is
      Done : Boolean;
   begin
      Result := null;
      FI.Check_Input (Image, Region, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Allocate_Result (Natural (Bin_Total (Params)) - 1, Result);
      if Result = null then
         Out_Of_Memory (Status);
         return;
      end if;
      Count_Bins (Image.Pixels.all, Region, Auto_Params, Result.Levels,
                  Done);
      if Done then
         Count_Bins (Image.Pixels.all, Region, Params, Result.Bins.all,
                     Done);
      end if;
      if not Done then
         Free (Result.Bins);
         Free (Result);
         Out_Of_Memory (Status);
         return;
      end if;
      Result.Num_Samples :=
        Int32 (Count_Samples (Image.Pixels.all, Region));
      Compute_Statistics
        (Result.Levels, Result.Minimum, Result.Maximum, Result.Median,
         Result.Mode, Result.Mean, Result.Variance,
         Result.Standard_Deviation);
      Set_Success (Status);
   end Execute;

   procedure Destroy
     (Result : in out Ks_Histogram_Result;
      Status : out Ks_Status) is
   begin
      if Result /= null then
         Free (Result.Bins);
         Free (Result);
      end if;
      Set_Success (Status);
   end Destroy;

   procedure Check_Result
     (Result : access constant Ks_Histogram_Result_Data;
      Status : out Ks_Status) is
   begin
      if Result = null then
         Set_Failure (Status, Failure_Other,
                      "Result: the histogram tool has no result");
      elsif not Valid_Result (Result) then
         Bad (Status, "Result is not a valid histogram result handle");
      else
         Set_Success (Status);
      end if;
   end Check_Result;

   procedure Get_Statistics
     (Result     : access constant Ks_Histogram_Result_Data;
      Statistics : out Ks_Histogram_Statistics;
      Status     : out Ks_Status) is
   begin
      Statistics := (others => <>);
      Check_Result (Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Count : constant Int32 := Int32 (Result.Bins'Last) + 1;
      begin
         Statistics.Num_Bins := Count;
      end;
      Statistics.Mean := Result.Mean;
      Statistics.Standard_Deviation := Result.Standard_Deviation;
      Statistics.Variance := Result.Variance;
      Statistics.Minimum := Result.Minimum;
      Statistics.Maximum := Result.Maximum;
      Statistics.Median := Result.Median;
      Statistics.Mode := Result.Mode;
      Statistics.Num_Samples := Result.Num_Samples;
   end Get_Statistics;

   procedure Get_Bin
     (Result : access constant Ks_Histogram_Result_Data;
      Index  : Int32;
      Count  : out Int32;
      Status : out Ks_Status) is
   begin
      Count := 0;
      Check_Result (Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Index < 0 or else Integer (Index) > Result.Bins'Last then
         Set_Failure
           (Status, Failure_Index_Out_Of_Range,
            "GetHistogram: index " & FI.Image_Of (Int64 (Index))
            & " is outside 0 .. " & FI.Image_Of (Int64 (Result.Bins'Last)));
         return;
      end if;
      Count := Result.Bins (Integer (Index));
   end Get_Bin;

   procedure Inverse_Cumulative_Grey_Level
     (Result  : access constant Ks_Histogram_Result_Data;
      Percent : Int32;
      Level   : out Int32;
      Status  : out Ks_Status)
   is
      Total : Int64 := 0;
   begin
      Level := 0;
      Check_Result (Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Percent not in 0 .. 100 then
         Bad (Status, "GetInverseCumulativeGreyLevel: percent must be in "
                      & "0 .. 100");
         return;
      end if;
      for L in Result.Levels'Range loop
         Total := Total + Int64 (Result.Levels (L));
         pragma Loop_Invariant (Total in 0 .. Int64 (L + 1) * 2**31);
      end loop;
      Level := Inverse_Level
        (Result.Levels, Result.Minimum, Result.Maximum, Total, Percent);
   end Inverse_Cumulative_Grey_Level;

   procedure Minimum_WGV_Threshold
     (Result    : access constant Ks_Histogram_Result_Data;
      Threshold : out Int32;
      Status    : out Ks_Status)
   is
   begin
      Threshold := 0;
      Check_Result (Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Counts : constant AMV.Kernels.Otsu.Level_Counts :=
           [for V in AMV.Kernels.Otsu.Grey_8 =>
              Int64 (Result.Levels (Natural (V)))];
         T      : constant Int32 := AMV.Kernels.Otsu.Threshold (Counts);
      begin
         Threshold := (if T = AMV.Kernels.Otsu.No_Split then Result.Minimum
                       else T);
      end;
   end Minimum_WGV_Threshold;

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      FI.Check_Image (Image, Status);
   end Check_Input_Image;

   procedure Last_Bin
     (Result : access constant Ks_Histogram_Result_Data;
      Last   : out Int32;
      Status : out Ks_Status) is
   begin
      Last := 0;
      Check_Result (Result, Status);
      if Succeeded (Status) then
         if Result.Bins'Last < 0 then
            Bad (Status, "Result is not a valid histogram result handle");
         else
            Last := Int32 (Result.Bins'Last);
         end if;
      end if;
   end Last_Bin;

   procedure Get_Histogram
     (Result : access constant Ks_Histogram_Result_Data;
      Bins   : out Histogram_Counts;
      Status : out Ks_Status) is
   begin
      Bins := [others => 0];
      Check_Result (Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Bins'First /= 0 or else Bins'Last /= Result.Bins'Last then
         Bad (Status, "GetHistogram: the array must be indexed 0 .. "
                      & FI.Image_Of (Int64 (Result.Bins'Last)));
         return;
      end if;
      for B in Bins'Range loop
         Bins (B) := Natural (Result.Bins (B));
         pragma Loop_Invariant
           (for all K in 0 .. B => Bins (K) = Natural (Result.Bins (K)));
      end loop;
   end Get_Histogram;

end AMV.Kernels.Histogram;
