pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;

with AMV.Kernels.Blob.Extrema;
with AMV.Kernels.Blob.Labelling;
with AMV.Kernels.Blob.Measures;
with AMV.Kernels.Blob.Ordering;
with AMV.Kernels.Blob.Segmentation;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Blob with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package N renames AMV.Kernels.Numerics;

   procedure Free is new Ada.Unchecked_Deallocation
     (U8_Matrix, U8_Matrix_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Int32_Matrix, Int32_Matrix_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Int32_Array, Int32_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Int64_Array, Int64_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Result_Array, Result_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Real_Array, Real_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Blob_Results_Data, Ks_Blob_Results);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   --  Each allocates with the defaults of the type (zeros) and gives null
   --  when the allocator raises Storage_Error, which SPARK cannot
   --  express.

   procedure Allocate_U8_Matrix
     (B : Box; Matrix : out U8_Matrix_Access)
     with SPARK_Mode => Off
   is
   begin
      Matrix := new U8_Matrix (B.Y_Min .. B.Y_Max, B.X_Min .. B.X_Max);
   exception
      when Storage_Error =>
         Matrix := null;
   end Allocate_U8_Matrix;

   procedure Allocate_Int32_Matrix
     (B : Box; Matrix : out Int32_Matrix_Access)
     with SPARK_Mode => Off
   is
   begin
      Matrix := new Int32_Matrix (B.Y_Min .. B.Y_Max, B.X_Min .. B.X_Max);
   exception
      when Storage_Error =>
         Matrix := null;
   end Allocate_Int32_Matrix;

   procedure Allocate_Int32_Array
     (Last : Natural; List : out Int32_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      List := new Int32_Array (0 .. Last);
   exception
      when Storage_Error =>
         List := null;
   end Allocate_Int32_Array;

   procedure Allocate_Int64_Array
     (Last : Natural; List : out Int64_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      List := new Int64_Array (0 .. Last);
   exception
      when Storage_Error =>
         List := null;
   end Allocate_Int64_Array;

   procedure Allocate_Results (Results : out Ks_Blob_Results)
     with SPARK_Mode => Off
   is
   begin
      Results := new Ks_Blob_Results_Data;
   exception
      when Storage_Error =>
         Results := null;
   end Allocate_Results;

   procedure Allocate_Result_Array
     (Last : Natural; List : out Result_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      List := new Result_Array (0 .. Last);
   exception
      when Storage_Error =>
         List := null;
   end Allocate_Result_Array;

   procedure Allocate_Real_Array
     (Last : Natural; List : out Real_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      List := new Real_Array (0 .. Last);
   exception
      when Storage_Error =>
         List := null;
   end Allocate_Real_Array;

   ---------------------------------------------------------------------
   --  Messages
   ---------------------------------------------------------------------

   function Image_Of (Value : Int64) return String
   with Pre  => Value > Int64'First,
        Post => Image_Of'Result'First = 1
                and then Image_Of'Result'Length in 1 .. 20;
   --  The decimal digits of Value, with a leading '-' when it is negative.

   function Image_Of (Value : Int64) return String is
      Text  : String (1 .. 20) := [others => '0'];
      Rest  : Int64 := abs Value;
      First : Positive;
   begin
      --  At most 19 digits; the first character is left for the sign.
      for K in reverse 2 .. 20 loop
         Text (K) := Character'Val (Character'Pos ('0') + Rest mod 10);
         Rest := Rest / 10;
         First := K;
         exit when Rest = 0;
         pragma Loop_Invariant (First = K and then Rest >= 1);
      end loop;
      if Value < 0 then
         First := First - 1;
         Text (First) := '-';
      end if;
      declare
         Last   : constant Natural := 21 - First;
         Result : constant String (1 .. Last) := Text (First .. 20);
      begin
         return Result;
      end;
   end Image_Of;

   procedure Bad (Status : out Ks_Status; Message : String)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   ---------------------------------------------------------------------
   --  Measures of a result
   ---------------------------------------------------------------------

   function Measure_Value
     (Result : Ks_Blob_Result; Measure : Int32) return Long_Float is
   begin
      case Measure is
         when Measure_Label => return Long_Float (Result.Label);
         when Measure_Area => return Result.Area;
         when Measure_Perimeter => return Result.Perimeter;
         when Measure_Num_Unfiltered_Children =>
            return Long_Float (Result.Num_Unfiltered_Children);
         when Measure_Center_Mass_X => return Result.Center_Of_Mass_X;
         when Measure_Center_Mass_Y => return Result.Center_Of_Mass_Y;
         when Measure_Inertia_X => return Result.Inertia_X;
         when Measure_Inertia_Y => return Result.Inertia_Y;
         when Measure_Inertia_Min => return Result.Inertia_Min;
         when Measure_Inertia_Max => return Result.Inertia_Max;
         when Measure_Elongation => return Result.Elongation;
         when Measure_Angle => return Result.Angle;
         when Measure_Acircularity => return Result.Acircularity;
         when Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Center_X =>
            return Result.Pixel_Aligned_Center_X;
         when Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Center_Y =>
            return Result.Pixel_Aligned_Center_Y;
         when Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Min_X =>
            return Result.Pixel_Aligned_Min_X;
         when Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Max_X =>
            return Result.Pixel_Aligned_Max_X;
         when Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Min_Y =>
            return Result.Pixel_Aligned_Min_Y;
         when Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Max_Y =>
            return Result.Pixel_Aligned_Max_Y;
         when Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Width =>
            return Result.Pixel_Aligned_Width;
         when Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Height =>
            return Result.Pixel_Aligned_Height;
         when Measure_Bounding_Box_Pixel_Aligned_No_Exclude_Aspect =>
            return Result.Pixel_Aligned_Aspect;
         when Measure_Median_Extrema_Angle_X =>
            return Result.Median_Extrema_Angle_X;
         when Measure_Median_Extrema_Angle_Y =>
            return Result.Median_Extrema_Angle_Y;
         when Measure_Bounding_Box_Extrema_Angle_Center_X =>
            return Result.Extrema_Angle_Center_X;
         when Measure_Bounding_Box_Extrema_Angle_Center_Y =>
            return Result.Extrema_Angle_Center_Y;
         when Measure_Bounding_Box_Extrema_Angle_Min_X =>
            return Result.Extrema_Angle_Min_X;
         when Measure_Bounding_Box_Extrema_Angle_Max_X =>
            return Result.Extrema_Angle_Max_X;
         when Measure_Bounding_Box_Extrema_Angle_Min_Y =>
            return Result.Extrema_Angle_Min_Y;
         when Measure_Bounding_Box_Extrema_Angle_Max_Y =>
            return Result.Extrema_Angle_Max_Y;
         when Measure_Bounding_Box_Extrema_Angle_Width =>
            return Result.Extrema_Angle_Width;
         when Measure_Bounding_Box_Extrema_Angle_Height =>
            return Result.Extrema_Angle_Height;
         when Measure_Bounding_Box_Extrema_Angle_Aspect =>
            return Result.Extrema_Angle_Aspect;
         when Measure_Bounding_Box_Principal_Axis_Min_X =>
            return Result.Principal_Axis_Min_X;
         when Measure_Bounding_Box_Principal_Axis_Max_X =>
            return Result.Principal_Axis_Max_X;
         when Measure_Bounding_Box_Principal_Axis_Min_Y =>
            return Result.Principal_Axis_Min_Y;
         when Measure_Bounding_Box_Principal_Axis_Max_Y =>
            return Result.Principal_Axis_Max_Y;
         when Measure_Bounding_Box_Principal_Axis_Width =>
            return Result.Principal_Axis_Width;
         when Measure_Bounding_Box_Principal_Axis_Height =>
            return Result.Principal_Axis_Height;
         when Measure_Bounding_Box_Principal_Axis_Aspect =>
            return Result.Principal_Axis_Aspect;
         when Measure_Not_Clipped =>
            return Long_Float (Result.Not_Clipped);
         when others => return 0.0;
      end case;
   end Measure_Value;

   ---------------------------------------------------------------------
   --  Run parameters
   ---------------------------------------------------------------------

   procedure Run_Params_Default
     (Params : out Ks_Blob_Run_Params;
      Status : out Ks_Status)
   is
      Defaults : constant Ks_Blob_Run_Params := (others => <>);
   begin
      Params := Defaults;
      Set_Success (Status);
   end Run_Params_Default;

   procedure Add_Measure
     (Collection : in out Ks_Blob_Measure_Collection;
      Measure    : Ks_Blob_Measure;
      Status     : out Ks_Status)
   is
   begin
      if Collection.Count < 0
        or else Collection.Count >= Max_Run_Time_Measures
      then
         Bad (Status, "RunTimeMeasures.Add: the collection must hold 0 .. 63"
                      & " measures before");
         return;
      end if;
      Collection.Items (Integer (Collection.Count)) := Measure;
      Collection.Count := Collection.Count + 1;
      Set_Success (Status);
   end Add_Measure;

   procedure Add_Morphology
     (Collection : in out Ks_Blob_Morphology_Collection;
      Operation  : Int32;
      Status     : out Ks_Status)
   is
   begin
      if Operation not in Morphology_Erode_Horizontal .. Morphology_Open_Square
      then
         Bad (Status, "MorphologyOperations.Add: the operation must be a "
                      & "CogBlobMorphologyConstants value (0 .. 11)");
         return;
      elsif Collection.Count < 0
        or else Collection.Count >= Max_Morphology_Operations
      then
         Bad (Status, "MorphologyOperations.Add: the collection must hold "
                      & "0 .. 31 operations before");
         return;
      end if;
      Collection.Items (Integer (Collection.Count)) := Operation;
      Collection.Count := Collection.Count + 1;
      Set_Success (Status);
   end Add_Morphology;

   ---------------------------------------------------------------------
   --  Segmentation setters
   ---------------------------------------------------------------------

   procedure Check_Polarity
     (Polarity  : Int32;
      Operation : String;
      Status    : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (Succeeded (Status) = Valid_Polarity (Polarity));
   --  "<Operation>: polarity must be DarkBlobs (0) or LightBlobs (1)".

   procedure Check_Polarity
     (Polarity  : Int32;
      Operation : String;
      Status    : out Ks_Status)
   is
   begin
      if Valid_Polarity (Polarity) then
         Set_Success (Status);
      else
         Bad (Status, Operation & ": polarity must be DarkBlobs (0) or "
                      & "LightBlobs (1)");
      end if;
   end Check_Polarity;

   procedure Check_Tails
     (Tail_Low, Tail_High : Int32;
      Operation           : String;
      Status              : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (Succeeded (Status)
                         = (Tail_Low in 0 .. 100 and then Tail_High in 0 .. 100
                            and then Tail_Low + Tail_High <= 100));
   --  The tails of a relative or dynamic setter: each in 0 .. 100, their
   --  sum at most 100.

   procedure Check_Tails
     (Tail_Low, Tail_High : Int32;
      Operation           : String;
      Status              : out Ks_Status)
   is
   begin
      if Tail_Low not in 0 .. 100 then
         Bad (Status, Operation & ": tailLow must be in 0 .. 100");
      elsif Tail_High not in 0 .. 100 then
         Bad (Status, Operation & ": tailHigh must be in 0 .. 100");
      elsif Tail_Low + Tail_High > 100 then
         Bad (Status, Operation & ": tailLow + tailHigh must be <= 100");
      else
         Set_Success (Status);
      end if;
   end Check_Tails;

   procedure Set_Hard_Fixed_Threshold
     (Params    : in out Ks_Blob_Segmentation_Params;
      Threshold : Int32;
      Polarity  : Int32;
      Status    : out Ks_Status)
   is
      Operation : constant String := "SetSegmentationHardFixedThreshold";
   begin
      if Threshold not in 0 .. Max_Fixed_Threshold then
         Bad (Status, Operation & ": hardFixedThreshold must be in "
                      & "0 .. 65535");
         return;
      end if;
      Check_Polarity (Polarity, Operation, Status);
      if Succeeded (Status) then
         Params.Mode := Segmentation_Hard_Fixed_Threshold;
         Params.Hard_Fixed_Threshold := Threshold;
         Params.Polarity := Polarity;
      end if;
   end Set_Hard_Fixed_Threshold;

   procedure Set_Hard_Relative_Threshold
     (Params              : in out Ks_Blob_Segmentation_Params;
      Tail_Low, Tail_High : Int32;
      Threshold           : Int32;
      Polarity            : Int32;
      Status              : out Ks_Status)
   is
      Operation : constant String := "SetSegmentationHardRelativeThreshold";
   begin
      Check_Tails (Tail_Low, Tail_High, Operation, Status);
      if not Succeeded (Status) then
         return;
      elsif Threshold not in 0 .. 100 then
         Bad (Status, Operation & ": hardRelativeThreshold must be in "
                      & "0 .. 100");
         return;
      end if;
      Check_Polarity (Polarity, Operation, Status);
      if Succeeded (Status) then
         Params.Mode := Segmentation_Hard_Relative_Threshold;
         Params.Tail_Low := Tail_Low;
         Params.Tail_High := Tail_High;
         Params.Hard_Relative_Threshold := Threshold;
         Params.Polarity := Polarity;
      end if;
   end Set_Hard_Relative_Threshold;

   procedure Set_Hard_Dynamic_Threshold
     (Params              : in out Ks_Blob_Segmentation_Params;
      Tail_Low, Tail_High : Int32;
      Polarity            : Int32;
      Status              : out Ks_Status)
   is
      Operation : constant String := "SetSegmentationHardDynamicThreshold";
   begin
      Check_Tails (Tail_Low, Tail_High, Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Polarity (Polarity, Operation, Status);
      if Succeeded (Status) then
         Params.Mode := Segmentation_Hard_Dynamic_Threshold;
         Params.Tail_Low := Tail_Low;
         Params.Tail_High := Tail_High;
         Params.Polarity := Polarity;
      end if;
   end Set_Hard_Dynamic_Threshold;

   procedure Set_Soft_Fixed_Threshold
     (Params    : in out Ks_Blob_Segmentation_Params;
      Low, High : Int32;
      Softness  : Int32;
      Polarity  : Int32;
      Status    : out Ks_Status)
   is
      Operation : constant String := "SetSegmentationSoftFixedThreshold";
   begin
      if Low not in 0 .. Max_Fixed_Threshold - 1 then
         Bad (Status, Operation & ": softFixedThresholdLow must be in "
                      & "0 .. 65534");
         return;
      elsif High not in 1 .. Max_Fixed_Threshold then
         Bad (Status, Operation & ": softFixedThresholdHigh must be in "
                      & "1 .. 65535");
         return;
      elsif Low >= High then
         Bad (Status, Operation & ": softFixedThresholdLow must be < "
                      & "softFixedThresholdHigh");
         return;
      elsif Softness not in 0 .. Max_Softness then
         Bad (Status, Operation & ": softness must be in 0 .. 254");
         return;
      end if;
      Check_Polarity (Polarity, Operation, Status);
      if Succeeded (Status) then
         Params.Mode := Segmentation_Soft_Fixed_Threshold;
         Params.Soft_Fixed_Threshold_Low := Low;
         Params.Soft_Fixed_Threshold_High := High;
         Params.Softness := Softness;
         Params.Polarity := Polarity;
      end if;
   end Set_Soft_Fixed_Threshold;

   procedure Set_Soft_Relative_Threshold
     (Params              : in out Ks_Blob_Segmentation_Params;
      Tail_Low, Tail_High : Int32;
      Low, High           : Int32;
      Softness            : Int32;
      Polarity            : Int32;
      Status              : out Ks_Status)
   is
      Operation : constant String := "SetSegmentationSoftRelativeThreshold";
   begin
      Check_Tails (Tail_Low, Tail_High, Operation, Status);
      if not Succeeded (Status) then
         return;
      elsif Low not in 0 .. 100 then
         Bad (Status, Operation & ": softRelativeThresholdLow must be in "
                      & "0 .. 100");
         return;
      elsif High not in 0 .. 100 then
         Bad (Status, Operation & ": softRelativeThresholdHigh must be in "
                      & "0 .. 100");
         return;
      elsif Low > High then
         Bad (Status, Operation & ": softRelativeThresholdLow must be <= "
                      & "softRelativeThresholdHigh");
         return;
      elsif Softness not in 0 .. Max_Softness then
         Bad (Status, Operation & ": softness must be in 0 .. 254");
         return;
      end if;
      Check_Polarity (Polarity, Operation, Status);
      if Succeeded (Status) then
         Params.Mode := Segmentation_Soft_Relative_Threshold;
         Params.Tail_Low := Tail_Low;
         Params.Tail_High := Tail_High;
         Params.Soft_Relative_Threshold_Low := Low;
         Params.Soft_Relative_Threshold_High := High;
         Params.Softness := Softness;
         Params.Polarity := Polarity;
      end if;
   end Set_Soft_Relative_Threshold;

   procedure Check_Measure_Code
     (Measure : Int32;
      Name    : String;
      Status  : out Ks_Status)
   with
     Pre  => Name'First = 1 and then Name'Length <= 60,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (Succeeded (Status) = Measure_Supported (Measure));
   --  "<Name> must be a supported CogBlobMeasureConstants value".

   procedure Check_Measure_Code
     (Measure : Int32;
      Name    : String;
      Status  : out Ks_Status)
   is
   begin
      if Measure_Supported (Measure) then
         Set_Success (Status);
      elsif Measure in 0 .. 42 then
         Bad (Status, Name & ": measure " & Image_Of (Int64 (Measure))
                      & " is not supported");
      else
         Bad (Status, Name & " must be a CogBlobMeasureConstants value "
                      & "(0 .. 42)");
      end if;
   end Check_Measure_Code;

   procedure Check_Params
     (Params : Ks_Blob_Run_Params;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Segmentation (Params.Segmentation_Params)
                            and then Valid_Connectivity (Params)
                            and then Params.Save_Segmented_Image
                                       in False_Value | True_Value
                            and then Params.Save_Segmented_Image_Before_Masking
                                       in False_Value | True_Value
                            and then
                              Params.Save_Segmented_Image_Before_Morphology
                                in False_Value | True_Value
                            and then Params.Extrema_Angle
                                       >= -Max_Extrema_Angle
                            and then Params.Extrema_Angle
                                       <= Max_Extrema_Angle);
   --  Every run parameter, with a message that names it.

   procedure Check_Params
     (Params : Ks_Blob_Run_Params;
      Status : out Ks_Status)
   is
      S : Ks_Blob_Segmentation_Params renames Params.Segmentation_Params;
   begin
      if S.Mode not in Segmentation_None .. Segmentation_Subtraction_Image
      then
         Bad (Status, "RunParams.SegmentationParams.Mode must be a "
                      & "CogBlobSegmentationModeConstants value (0 .. 7)");
         return;
      elsif S.Mode in Segmentation_Map | Segmentation_Subtraction_Image then
         Bad (Status, "RunParams.SegmentationParams.Mode: only None and the "
                      & "hard and soft thresholds are supported");
         return;
      elsif S.Polarity not in Polarity_Dark_Blobs | Polarity_Light_Blobs then
         Bad (Status, "RunParams.SegmentationParams.Polarity must be "
                      & "DarkBlobs (0) or LightBlobs (1)");
         return;
      elsif S.Hard_Fixed_Threshold not in 0 .. Max_Fixed_Threshold then
         Bad (Status, "RunParams.SegmentationParams.HardFixedThreshold must "
                      & "be in 0 .. 65535");
         return;
      elsif S.Hard_Relative_Threshold not in 0 .. 100 then
         Bad (Status, "RunParams.SegmentationParams.HardRelativeThreshold "
                      & "must be in 0 .. 100");
         return;
      elsif S.Tail_Low not in 0 .. 100 then
         Bad (Status, "RunParams.SegmentationParams.TailLow must be in "
                      & "0 .. 100");
         return;
      elsif S.Tail_High not in 0 .. 100 then
         Bad (Status, "RunParams.SegmentationParams.TailHigh must be in "
                      & "0 .. 100");
         return;
      elsif S.Soft_Fixed_Threshold_Low not in 0 .. Max_Fixed_Threshold - 1
      then
         Bad (Status, "RunParams.SegmentationParams.SoftFixedThresholdLow "
                      & "must be in 0 .. 65534");
         return;
      elsif S.Soft_Fixed_Threshold_High not in 1 .. Max_Fixed_Threshold then
         Bad (Status, "RunParams.SegmentationParams.SoftFixedThresholdHigh "
                      & "must be in 1 .. 65535");
         return;
      elsif S.Soft_Fixed_Threshold_Low >= S.Soft_Fixed_Threshold_High then
         Bad (Status, "RunParams.SegmentationParams.SoftFixedThresholdLow "
                      & "must be < SoftFixedThresholdHigh");
         return;
      elsif S.Soft_Relative_Threshold_Low not in 0 .. 100 then
         Bad (Status, "RunParams.SegmentationParams.SoftRelativeThresholdLow"
                      & " must be in 0 .. 100");
         return;
      elsif S.Soft_Relative_Threshold_High not in 0 .. 100 then
         Bad (Status, "RunParams.SegmentationParams."
                      & "SoftRelativeThresholdHigh must be in 0 .. 100");
         return;
      elsif S.Soft_Relative_Threshold_Low > S.Soft_Relative_Threshold_High
      then
         Bad (Status, "RunParams.SegmentationParams.SoftRelativeThresholdLow"
                      & " must be <= SoftRelativeThresholdHigh");
         return;
      elsif S.Softness not in 0 .. Max_Softness then
         Bad (Status, "RunParams.SegmentationParams.Softness must be in "
                      & "0 .. 254");
         return;
      elsif Params.Connectivity_Mode
              not in Connectivity_Grey_Scale | Connectivity_Labeled
                   | Connectivity_Whole_Image_Grey_Scale
      then
         Bad (Status, "RunParams.ConnectivityMode must be GreyScale (0), "
                      & "Labeled (1) or WholeImageGreyScale (2)");
         return;
      elsif Params.Connectivity_Cleanup not in Cleanup_None .. Cleanup_Fill
      then
         Bad (Status, "RunParams.ConnectivityCleanup must be None (0), "
                      & "Prune (1) or Fill (2)");
         return;
      elsif Params.Connectivity_Min_Pixels < 0 then
         Bad (Status, "RunParams.ConnectivityMinPixels must be >= 0");
         return;
      elsif Params.Sort_Enabled not in False_Value | True_Value then
         Bad (Status, "RunParams.SortEnabled must be 0 or 1");
         return;
      elsif Params.Sort_Ascending not in False_Value | True_Value then
         Bad (Status, "RunParams.SortAscending must be 0 or 1");
         return;
      elsif Params.Save_Segmented_Image not in False_Value | True_Value then
         Bad (Status, "RunParams.SaveSegmentedImage must be 0 or 1");
         return;
      elsif Params.Save_Segmented_Image_Before_Masking
              not in False_Value | True_Value
      then
         Bad (Status, "RunParams.SaveSegmentedImageBeforeMasking must be 0 "
                      & "or 1");
         return;
      elsif Params.Save_Segmented_Image_Before_Morphology
              not in False_Value | True_Value
      then
         Bad (Status, "RunParams.SaveSegmentedImageBeforeMorphology must be "
                      & "0 or 1");
         return;
      end if;
      Check_Measure_Code (Params.Sort_Measure, "RunParams.SortMeasure",
                          Status);
      if not Succeeded (Status) then
         return;
      end if;

      if Params.Run_Time_Measures.Count not in 0 .. Max_Run_Time_Measures
      then
         Bad (Status, "RunParams.RunTimeMeasures.Count must be in 0 .. 64");
         return;
      end if;
      for I in 0 .. Params.Run_Time_Measures.Count - 1 loop
         declare
            M    : Ks_Blob_Measure renames
              Params.Run_Time_Measures.Items (Integer (I));
            Name : constant String :=
              "RunParams.RunTimeMeasures(" & Image_Of (Int64 (I)) & ")";
         begin
            Check_Measure_Code (M.Measure, Name & ".Measure", Status);
            if not Succeeded (Status) then
               return;
            elsif M.Mode not in Measure_Mode_None .. Measure_Mode_Filter then
               Bad (Status, Name & ".Mode must be None (0), PreCompute (1) "
                            & "or Filter (2)");
               return;
            elsif M.Filter_Mode
                    not in Filter_Exclude_Blobs_In_Range
                         | Filter_Include_Blobs_In_Range
            then
               Bad (Status, Name & ".FilterMode must be "
                            & "ExcludeBlobsInRange (0) or "
                            & "IncludeBlobsInRange (1)");
               return;
            elsif not N.Is_Finite (M.Filter_Range_Low) then
               Bad (Status, Name & ".FilterRangeLow must be finite");
               return;
            elsif not N.Is_Finite (M.Filter_Range_High) then
               Bad (Status, Name & ".FilterRangeHigh must be finite");
               return;
            elsif M.Mode = Measure_Mode_Filter
              and then M.Filter_Range_Low > M.Filter_Range_High
            then
               Bad (Status, Name & ".FilterRangeLow must be <= "
                            & "FilterRangeHigh");
               return;
            end if;
         end;
      end loop;

      if Params.Morphology_Operations.Count
           not in 0 .. Max_Morphology_Operations
      then
         Bad (Status, "RunParams.MorphologyOperations.Count must be in "
                      & "0 .. 32");
         return;
      end if;
      for I in 0 .. Params.Morphology_Operations.Count - 1 loop
         if Params.Morphology_Operations.Items (Integer (I))
              not in Morphology_Erode_Horizontal .. Morphology_Open_Square
         then
            Bad (Status, "RunParams.MorphologyOperations("
                         & Image_Of (Int64 (I)) & ") must be a "
                         & "CogBlobMorphologyConstants value (0 .. 11)");
            return;
         end if;
      end loop;
      if not N.In_Range (Params.Extrema_Angle, Max_Extrema_Angle) then
         Bad (Status, "RunParams.ExtremaAngle must be finite and within "
                      & "+/-1.0E6");
         return;
      end if;
      Set_Success (Status);
   end Check_Params;

   ---------------------------------------------------------------------
   --  Execute
   ---------------------------------------------------------------------

   procedure Check_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   is
   begin
      if Image = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "InputImage has no pixels");
      else
         Set_Success (Status);
      end if;
   end Check_Image;

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Params              : Ks_Blob_Run_Params;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : out Ks_Blob_Results;
      Status              : out Ks_Status)
   is
      S        : U8_Matrix_Access;
      Levels   : U8_Matrix_Access;
      Full     : Int32 := 1;
      Features : Labelling.Feature_Set;
      Items    : Result_Array_Access;
      Cent_X   : Real_Array_Access;
      Cent_Y   : Real_Array_Access;
      Order    : Int32_Array_Access;
      Filtered : Int32 := 0;
   begin
      Results := null;
      if Image = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "InputImage has no pixels");
         return;
      elsif not KI.Valid_Image (Image) then
         Bad (Status, "InputImage: the image handle is not valid");
         return;
      end if;
      Check_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if not Bounded_Transform (Selected_From_Pixel) then
         Bad (Status, "SelectedFromPixel: the matrix entries must be finite "
                      & "and within +/-2**64, the translation within "
                      & "+/-1.0E140");
         return;
      end if;
      if Region /= null then
         if not KR.Valid_Region (Region) then
            Bad (Status, "Region: the pixel region is not valid");
            return;
         elsif not KR.In_Image (Region, Image.Width, Image.Height) then
            Bad (Status, "Region: the pixel region does not lie in "
                         & "InputImage");
            return;
         elsif Int64 (Region.Width) * Int64 (Region.Height)
                 > Max_Region_Pixels
         then
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Execute: the region is too large");
            return;
         end if;
      end if;

      Allocate_Results (Results);
      if Results = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Execute: out of memory for the results");
         return;
      end if;
      Results.Image_Width := Image.Width;
      Results.Image_Height := Image.Height;
      Results.Transform := Selected_From_Pixel;
      Results.Connectivity := Params.Connectivity_Mode;
      Results.Saved_Final := Params.Save_Segmented_Image;
      Results.Saved_Before_Morphology :=
        Params.Save_Segmented_Image_Before_Morphology;
      Results.Saved_Before_Masking :=
        Params.Save_Segmented_Image_Before_Masking;
      if Is_Soft (Params.Segmentation_Params) then
         Full := Params.Segmentation_Params.Softness + 1;
      end if;
      Results.Full := Full;
      if Region = null then
         Set_Success (Status);
         return;
      end if;

      --  Segmentation: two classes, or for a soft mode the levels too;
      --  the whole bounding rectangle too when the stage BeforeMasking is
      --  saved.
      declare
         B         : constant Box := Box_Of (Region);
         Hist      : Segmentation.Histogram;
         Threshold : Int32;
      begin
         Segmentation.Compute_Histogram (Image, Region, Hist);
         Allocate_U8_Matrix (B, S);
         if S = null then
            Free_Results (Results);
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Execute: out of memory for the segmentation");
            return;
         end if;
         if Params.Save_Segmented_Image_Before_Masking = True_Value then
            Allocate_U8_Matrix (B, Results.Before_Masking);
            if Results.Before_Masking = null then
               Free (S);
               Free_Results (Results);
               Set_Failure (Status, Failure_Out_Of_Memory,
                            "Execute: out of memory for the segmented "
                            & "image");
               return;
            end if;
         end if;
         if Is_Soft (Params.Segmentation_Params) then
            Allocate_U8_Matrix (B, Levels);
            if Levels = null then
               Free (S);
               Free_Results (Results);
               Set_Failure (Status, Failure_Out_Of_Memory,
                            "Execute: out of memory for the segmentation");
               return;
            end if;
            declare
               Low, High : Segmentation.Threshold_Level;
            begin
               Segmentation.Soft_Band
                 (Params.Segmentation_Params, Hist, Low, High);
               Segmentation.Segment_Soft
                 (Image, Region, Params.Segmentation_Params.Polarity, Low,
                  High, Params.Segmentation_Params.Softness, S.all,
                  Levels.all);
               if Results.Before_Masking /= null then
                  Segmentation.Segment_Box_Soft
                    (Image, Params.Segmentation_Params.Polarity, Low, High,
                     Params.Segmentation_Params.Softness,
                     Results.Before_Masking.all);
               end if;
            end;
         else
            Threshold :=
              Segmentation.Compute_Threshold
                (Params.Segmentation_Params, Hist);
            Segmentation.Segment
              (Image, Region, Params.Segmentation_Params.Polarity, Threshold,
               S.all);
            if Results.Before_Masking /= null then
               Segmentation.Segment_Box_Hard
                 (Image, Params.Segmentation_Params.Polarity, Threshold,
                  Results.Before_Masking.all);
            end if;
         end if;

         if Params.Save_Segmented_Image_Before_Morphology = True_Value then
            Allocate_U8_Matrix (B, Results.Before_Morphology);
            if Results.Before_Morphology = null then
               Free (S);
               Free (Levels);
               Free_Results (Results);
               Set_Failure (Status, Failure_Out_Of_Memory,
                            "Execute: out of memory for the segmented "
                            & "image");
               return;
            end if;
            if Levels /= null then
               Results.Before_Morphology.all := Levels.all;
            else
               Segmentation.To_Levels (S.all, Results.Before_Morphology.all);
            end if;
         end if;
      end;
      if Levels /= null then
         Segmentation.Apply_Soft_Morphology
           (Params.Morphology_Operations, S.all, Levels.all, Status);
      else
         Segmentation.Apply_Morphology
           (Params.Morphology_Operations, S.all, Status);
      end if;
      if not Succeeded (Status) then
         Free (S);
         Free (Levels);
         Free_Results (Results);
         return;
      end if;
      if Levels = null
        and then Params.Save_Segmented_Image = True_Value
      then
         Allocate_U8_Matrix (Box_Of (Region), Results.Levels);
         if Results.Levels = null then
            Free (S);
            Free_Results (Results);
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Execute: out of memory for the segmented image");
            return;
         end if;
         Segmentation.To_Levels (S.all, Results.Levels.all);
      end if;

      --  Connectivity. The sides of S are those of the region, whose
      --  product was checked above.
      pragma Assert
        (Int64 (S'Last (1)) - Int64 (S'First (1)) + 1 = Int64 (Region.Height)
         and then Int64 (S'Last (2)) - Int64 (S'First (2)) + 1
                    = Int64 (Region.Width));
      pragma Assert
        (Int64 (Region.Height) * Int64 (Region.Width) <= Max_Region_Pixels);
      Labelling.Find_Features (S.all, Image, Params, Features, Status);
      Free (S);
      if not Succeeded (Status) then
         Free (Levels);
         Free_Results (Results);
         return;
      end if;
      if Features.Count = 0 then
         if Levels /= null then
            Results.Levels := Levels;
         end if;
         Free (Features.Map);
         Free (Features.Kind);
         Free (Features.Label);
         Free (Features.Parent);
         Free (Features.First_X);
         Free (Features.First_Y);
         Free (Features.Area);
         Set_Success (Status);
         return;
      end if;

      --  Measures, filter and order.
      Allocate_Result_Array (Natural (Features.Count) - 1, Items);
      Allocate_Real_Array (Natural (Features.Count) - 1, Cent_X);
      Allocate_Real_Array (Natural (Features.Count) - 1, Cent_Y);
      if Items = null or else Cent_X = null or else Cent_Y = null then
         Free (Levels);
         Free (Features.Map);
         Free (Features.Kind);
         Free (Features.Label);
         Free (Features.Parent);
         Free (Features.First_X);
         Free (Features.First_Y);
         Free (Features.Area);
         Free (Items);
         Free (Cent_X);
         Free (Cent_Y);
         Free_Results (Results);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Execute: out of memory for the results");
         return;
      end if;
      Measures.Compute_Items
        (Region, Features.Map.all, Features.Count, Features.Kind.all,
         Features.Label.all, Features.Parent.all, Features.First_X.all,
         Features.First_Y.all, Features.Area.all, Levels, Full,
         Selected_From_Pixel, Items.all, Cent_X.all, Cent_Y.all, Status);
      if Succeeded (Status) then
         Extrema.Compute_Extrema
           (Features.Map.all, Features.Count, Features.Area.all, Cent_X.all,
            Cent_Y.all, Selected_From_Pixel, Params.Extrema_Angle,
            Items.all, Status);
      end if;
      if Succeeded (Status) then
         Ordering.Filter_And_Sort
           (Items.all, Params, Order, Filtered, Status);
      end if;
      if not Succeeded (Status) then
         Free (Levels);
         Free (Features.Map);
         Free (Features.Kind);
         Free (Features.Label);
         Free (Features.Parent);
         Free (Features.First_X);
         Free (Features.First_Y);
         Free (Features.Area);
         Free (Items);
         Free (Cent_X);
         Free (Cent_Y);
         Free_Results (Results);
         return;
      end if;

      Results.Count := Features.Count;
      Results.Items := Items;
      Results.First_X := Features.First_X;
      Results.First_Y := Features.First_Y;
      Results.Kinds := Features.Kind;
      Results.Map := Features.Map;
      Results.Filtered_Count := Filtered;
      Results.Order := Order;
      Results.Centroid_X := Cent_X;
      Results.Centroid_Y := Cent_Y;
      if Levels /= null then
         Results.Levels := Levels;
      end if;
      Free (Features.Label);
      Free (Features.Parent);
      Free (Features.Area);
      Set_Success (Status);
   end Execute;

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   procedure Destroy
     (Results : in out Ks_Blob_Results;
      Status  : out Ks_Status)
   is
   begin
      Free_Results (Results);
      Set_Success (Status);
   end Destroy;

   procedure Free_Results (Results : in out Ks_Blob_Results) is
   begin
      if Results /= null then
         Free (Results.Items);
         Free (Results.First_X);
         Free (Results.First_Y);
         Free (Results.Kinds);
         Free (Results.Map);
         Free (Results.Order);
         Free (Results.Centroid_X);
         Free (Results.Centroid_Y);
         Free (Results.Levels);
         Free (Results.Before_Morphology);
         Free (Results.Before_Masking);
         Free (Results);
      end if;
   end Free_Results;

   procedure Count
     (Results  : access constant Ks_Blob_Results_Data;
      Filtered : Int32;
      Result   : out Int32;
      Status   : out Ks_Status)
   is
   begin
      Result := 0;
      if Filtered not in False_Value | True_Value then
         Bad (Status, "GetBlobs: Filtered must be 0 or 1");
      elsif Results = null then
         Set_Success (Status);
      elsif not Valid_Results (Results) then
         Bad (Status, "GetBlobs: the results handle is not valid");
      else
         Result := (if Filtered = True_Value then Results.Filtered_Count
                    else Results.Count);
         Set_Success (Status);
      end if;
   end Count;

   procedure Out_Of_Collection
     (Index, Count : Int32;
      Status       : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Index_Out_Of_Range;
   --  "GetBlobs: index <Index> is outside 0 .. <Count - 1>".

   procedure Out_Of_Collection
     (Index, Count : Int32;
      Status       : out Ks_Status)
   is
   begin
      Set_Failure
        (Status, Failure_Index_Out_Of_Range,
         "GetBlobs: index " & Image_Of (Int64 (Index)) & " is outside 0 .. "
         & Image_Of (Int64 (Count) - 1));
   end Out_Of_Collection;

   procedure Item
     (Results  : access constant Ks_Blob_Results_Data;
      Filtered : Int32;
      Index    : Int32;
      Result   : out Ks_Blob_Result;
      Status   : out Ks_Status)
   is
      Empty : constant Ks_Blob_Result := (others => <>);
   begin
      Result := Empty;
      if Filtered not in False_Value | True_Value then
         Bad (Status, "GetBlobs: Filtered must be 0 or 1");
      elsif Results = null then
         Out_Of_Collection (Index, 0, Status);
      elsif not Valid_Results (Results) then
         Bad (Status, "GetBlobs: the results handle is not valid");
      elsif Filtered = True_Value then
         if Index < 0 or else Index >= Results.Filtered_Count then
            Out_Of_Collection (Index, Results.Filtered_Count, Status);
         else
            declare
               ID : constant Int32 := Results.Order (Integer (Index));
            begin
               if ID < 0 or else ID >= Results.Count then
                  Bad (Status, "GetBlobs: the results handle is not valid");
               else
                  Result := Results.Items (Integer (ID));
                  Set_Success (Status);
               end if;
            end;
         end if;
      elsif Index < 0 or else Index >= Results.Count then
         Out_Of_Collection (Index, Results.Count, Status);
      else
         Result := Results.Items (Integer (Index));
         Set_Success (Status);
      end if;
   end Item;

   procedure Check_ID
     (Results   : access constant Ks_Blob_Results_Data;
      ID        : Int32;
      Operation : String;
      Status    : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Results (Results)
                            and then ID in 0 .. Results.Count - 1);
   --  "<Operation>: no blob has ID <ID>" unless ID names a feature.

   procedure Check_ID
     (Results   : access constant Ks_Blob_Results_Data;
      ID        : Int32;
      Operation : String;
      Status    : out Ks_Status)
   is
   begin
      if Results /= null and then not Valid_Results (Results) then
         Bad (Status, Operation & ": the results handle is not valid");
      elsif Results = null or else ID < 0 or else ID >= Results.Count then
         Bad (Status, Operation & ": no blob has ID "
                      & Image_Of (Int64 (ID)));
      else
         Set_Success (Status);
      end if;
   end Check_ID;

   procedure Get_Blob_By_ID
     (Results : access constant Ks_Blob_Results_Data;
      ID      : Int32;
      Result  : out Ks_Blob_Result;
      Status  : out Ks_Status)
   is
      Empty : constant Ks_Blob_Result := (others => <>);
   begin
      Result := Empty;
      Check_ID (Results, ID, "GetBlobByID", Status);
      if Succeeded (Status) then
         Result := Results.Items (Integer (ID));
      end if;
   end Get_Blob_By_ID;

   procedure Get_Parent
     (Results   : access constant Ks_Blob_Results_Data;
      ID        : Int32;
      Parent_ID : out Int32;
      Status    : out Ks_Status)
   is
   begin
      Parent_ID := -1;
      Check_ID (Results, ID, "GetParent", Status);
      if Succeeded (Status) then
         declare
            P : constant Int32 := Results.Items (Integer (ID)).Parent_ID;
         begin
            if P >= 0 and then P < Results.Count then
               Parent_ID := P;
            end if;
         end;
      end if;
   end Get_Parent;

   procedure Get_Measure
     (Result  : Ks_Blob_Result;
      Measure : Int32;
      Value   : out Long_Float;
      Status  : out Ks_Status)
   is
   begin
      Value := 0.0;
      Check_Measure_Code (Measure, "GetMeasure: Measure", Status);
      if Succeeded (Status) then
         Value := Measure_Value (Result, Measure);
      end if;
   end Get_Measure;

   procedure Get_Bounding_Box
     (Result : Ks_Blob_Result;
      Axis   : Int32;
      Box    : out KS.Ks_Rectangle_Affine;
      Status : out Ks_Status)
   is
      Empty : constant KS.Ks_Rectangle_Affine := (others => <>);
   begin
      Box := Empty;
      case Axis is
         when Axis_Principal =>
            Box := Result.Principal_Axis_Box;
            Set_Success (Status);
         when Axis_Selected_Space =>
            Box := Result.Selected_Space_Box;
            Set_Success (Status);
         when Axis_Pixel_Aligned | Axis_Pixel_Aligned_No_Exclude =>
            Box := Result.Pixel_Aligned_Box;
            Set_Success (Status);
         when Axis_Extrema_Angle =>
            Box := Result.Extrema_Angle_Box;
            Set_Success (Status);
         when others =>
            Bad (Status, "GetBoundingBox: Axis must be a "
                         & "CogBlobAxisConstants value (0 .. 4)");
      end case;
   end Get_Bounding_Box;

   ---------------------------------------------------------------------
   --  Boundary
   ---------------------------------------------------------------------

   function Owns
     (Map  : Int32_Matrix;
      Id   : Int32;
      X, Y : Int64) return Boolean
   is
     (Y in Int64 (Map'First (1)) .. Int64 (Map'Last (1))
      and then X in Int64 (Map'First (2)) .. Int64 (Map'Last (2))
      and then Map (Natural (Y), Natural (X)) = Id);
   --  Pixel (X, Y) belongs to the feature numbered Id.

   type Direction is mod 4;
   East  : constant Direction := 0;
   South : constant Direction := 1;
   West  : constant Direction := 2;
   North : constant Direction := 3;

   Step_X : constant array (Direction) of Int64 := [1, 0, -1, 0];
   Step_Y : constant array (Direction) of Int64 := [0, 1, 0, -1];

   procedure Turn
     (Map           : Int32_Matrix;
      Id            : Int32;
      Eight         : Boolean;
      Corner_X      : Int64;
      Corner_Y      : Int64;
      Heading       : in out Direction);
   --  At the pixel corner (Corner_X, Corner_Y) (the point (Corner_X - 0.5,
   --  Corner_Y - 0.5)), reached while heading Heading with the feature on
   --  the right, the direction of the next boundary edge: the pixels
   --  ahead on the left and on the right decide (with 8-connectivity a
   --  pixel ahead on the left always turns the boundary left; with
   --  4-connectivity only when the one on the right belongs too).

   procedure Turn
     (Map           : Int32_Matrix;
      Id            : Int32;
      Eight         : Boolean;
      Corner_X      : Int64;
      Corner_Y      : Int64;
      Heading       : in out Direction)
   is
      Left_X, Left_Y, Right_X, Right_Y : Int64;
   begin
      case Heading is
         when East =>
            Left_X := Corner_X;
            Left_Y := Corner_Y - 1;
            Right_X := Corner_X;
            Right_Y := Corner_Y;
         when South =>
            Left_X := Corner_X;
            Left_Y := Corner_Y;
            Right_X := Corner_X - 1;
            Right_Y := Corner_Y;
         when West =>
            Left_X := Corner_X - 1;
            Left_Y := Corner_Y;
            Right_X := Corner_X - 1;
            Right_Y := Corner_Y - 1;
         when North =>
            Left_X := Corner_X - 1;
            Left_Y := Corner_Y - 1;
            Right_X := Corner_X;
            Right_Y := Corner_Y - 1;
      end case;
      declare
         Left  : constant Boolean := Owns (Map, Id, Left_X, Left_Y);
         Right : constant Boolean := Owns (Map, Id, Right_X, Right_Y);
      begin
         if Eight then
            if Left then
               Heading := Heading - 1;
            elsif not Right then
               Heading := Heading + 1;
            end if;
         elsif not Right then
            Heading := Heading + 1;
         elsif Left then
            Heading := Heading - 1;
         end if;
      end;
   end Turn;

   procedure Get_Boundary
     (Results  : access constant Ks_Blob_Results_Data;
      ID       : Int32;
      Boundary : out KS.Ks_Polygon;
      Status   : out Ks_Status)
   is
   begin
      Boundary := null;
      Check_ID (Results, ID, "GetBoundary", Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Number   : constant Int32 := ID + 1;
         Start_X  : constant Int64 :=
           Int64 (Results.First_X (Integer (ID)));
         Start_Y  : constant Int64 :=
           Int64 (Results.First_Y (Integer (ID)));
         Eight    : constant Boolean :=
           Results.Kinds (Integer (ID)) = Label_Blob;
         T        : constant KT.Ks_Transform_2D_Linear := Results.Transform;
         Map      : Int32_Matrix renames Results.Map.all;
         Pixels   : constant Int64 :=
           (Int64 (Map'Last (1)) - Int64 (Map'First (1)) + 1)
           * (Int64 (Map'Last (2)) - Int64 (Map'First (2)) + 1);
         Bound    : constant Int64 := 4 * Int64'Min (Pixels, 2**40) + 4;
         Corner_X : Int64 := Start_X + 1;
         Corner_Y : Int64 := Start_Y;
         Heading  : Direction := East;
      begin
         if not Owns (Map, Number, Start_X, Start_Y)
           or else not Bounded_Transform (T)
         then
            Bad (Status, "GetBoundary: the results handle is not valid");
            return;
         end if;
         KS.Create (Boundary, Status);
         if not Succeeded (Status) then
            return;
         end if;
         for Steps in 1 .. Bound loop
            pragma Loop_Invariant
              (KS.Valid_Polygon (Boundary)
               and then Corner_X in Start_X - Steps .. Start_X + Steps
               and then Corner_Y in Start_Y - Steps .. Start_Y + Steps);
            declare
               Old_Heading : constant Direction := Heading;
            begin
               Turn (Map, Number, Eight, Corner_X, Corner_Y, Heading);
               if Heading /= Old_Heading then
                  declare
                     PX : constant Long_Float :=
                       N.Clamp (Long_Float (Corner_X) - 0.5, 2.0 ** 33);
                     PY : constant Long_Float :=
                       N.Clamp (Long_Float (Corner_Y) - 0.5, 2.0 ** 33);
                     X  : constant Long_Float :=
                       N.Mul_Within (T.A, PX, Max_Scale, 2.0 ** 33)
                       + N.Mul_Within (T.B, PY, Max_Scale, 2.0 ** 33)
                       + T.Translation_X;
                     Y  : constant Long_Float :=
                       N.Mul_Within (T.C, PX, Max_Scale, 2.0 ** 33)
                       + N.Mul_Within (T.D, PY, Max_Scale, 2.0 ** 33)
                       + T.Translation_Y;
                  begin
                     KS.Add_Vertex (Boundary, X, Y, KS.Append_Index, Status);
                     if not Succeeded (Status) then
                        declare
                           Code   : constant Int32 := Status.Failure;
                           Ignore : Ks_Status;
                        begin
                           KS.Destroy (Boundary, Ignore);
                           if Code = Failure_Out_Of_Memory then
                              Set_Failure
                                (Status, Failure_Out_Of_Memory,
                                 "GetBoundary: out of memory");
                           else
                              Bad (Status, "GetBoundary: the boundary has "
                                           & "too many vertices");
                           end if;
                        end;
                        return;
                     end if;
                  end;
               end if;
               exit when Corner_X = Start_X and then Corner_Y = Start_Y
                 and then Heading = East;
               Corner_X := Corner_X + Step_X (Heading);
               Corner_Y := Corner_Y + Step_Y (Heading);
            end;
         end loop;
         Set_Success (Status);
      end;
   end Get_Boundary;

   ---------------------------------------------------------------------
   --  Boxes at an angle and medians
   ---------------------------------------------------------------------

   procedure Get_Bounding_Box_At_Angle
     (Results : access constant Ks_Blob_Results_Data;
      ID      : Int32;
      Angle   : Long_Float;
      Box     : out KS.Ks_Rectangle_Affine;
      Status  : out Ks_Status)
   is
      Empty : constant KS.Ks_Rectangle_Affine := (others => <>);
      Found : Boolean;
   begin
      Box := Empty;
      Check_ID (Results, ID, "GetBoundingBoxAtAngle", Status);
      if not Succeeded (Status) then
         return;
      elsif not N.In_Range (Angle, Max_Extrema_Angle) then
         Bad (Status, "GetBoundingBoxAtAngle: Angle must be finite and "
                      & "within +/-1.0E6");
         return;
      elsif not Bounded_Transform (Results.Transform) then
         Bad (Status, "GetBoundingBoxAtAngle: the results handle is not "
                      & "valid");
         return;
      end if;
      declare
         K    : constant Natural := Natural (ID);
         Item : Ks_Blob_Result renames Results.Items (K);
      begin
         Extrema.Box_At_Angle
           (Map    => Results.Map.all,
            Id     => ID + 1,
            Cx     => N.Clamp (Results.Centroid_X (K), Extrema.Center_Limit),
            Cy     => N.Clamp (Results.Centroid_Y (K), Extrema.Center_Limit),
            Mass_X => N.Clamp (Item.Center_Of_Mass_X, Extrema.Mass_Limit),
            Mass_Y => N.Clamp (Item.Center_Of_Mass_Y, Extrema.Mass_Limit),
            T      => Results.Transform,
            Angle  => Angle,
            Box    => Box,
            Found  => Found);
      end;
      if not Found then
         Box := Empty;
         Bad (Status, "GetBoundingBoxAtAngle: the results handle is not "
                      & "valid");
      end if;
   end Get_Bounding_Box_At_Angle;

   procedure Get_Median
     (Results   : access constant Ks_Blob_Results_Data;
      ID        : Int32;
      Axis      : Int32;
      Second    : Boolean;
      Operation : String;
      Median    : out Long_Float;
      Status    : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 20,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory;
   --  GetMedianX (Second False) or GetMedianY (Second True) of feature ID
   --  along Axis; the messages name Operation.

   procedure Get_Median
     (Results   : access constant Ks_Blob_Results_Data;
      ID        : Int32;
      Axis      : Int32;
      Second    : Boolean;
      Operation : String;
      Median    : out Long_Float;
      Status    : out Ks_Status)
   is
      P, Q, Offset : Long_Float;
      Relative     : Long_Float;
      Found        : Boolean;
      Memory       : Boolean;
   begin
      Median := 0.0;
      Check_ID (Results, ID, Operation, Status);
      if not Succeeded (Status) then
         return;
      elsif Axis not in Axis_Principal .. Axis_Pixel_Aligned_No_Exclude then
         Bad (Status, Operation & ": Axis must be a CogBlobAxisConstants "
                      & "value (0 .. 4)");
         return;
      elsif not Bounded_Transform (Results.Transform) then
         Bad (Status, Operation & ": the results handle is not valid");
         return;
      end if;
      declare
         K    : constant Natural := Natural (ID);
         Item : Ks_Blob_Result renames Results.Items (K);
         T    : constant KT.Ks_Transform_2D_Linear := Results.Transform;
      begin
         if Axis = Axis_Extrema_Angle then
            --  Computed by Execute along ExtremaAngle.
            Median := (if Second then Item.Median_Extrema_Angle_Y
                       else Item.Median_Extrema_Angle_X);
            Set_Success (Status);
            return;
         elsif Axis = Axis_Principal then
            --  Along the principal axes, from the centre of mass.
            declare
               Cos_A : constant Long_Float := EF.Cos (Item.Angle);
               Sin_A : constant Long_Float := EF.Sin (Item.Angle);
            begin
               if Second then
                  P := Extrema.Turned (T.C, -T.A, Cos_A, Sin_A);
                  Q := Extrema.Turned (T.D, -T.B, Cos_A, Sin_A);
               else
                  P := Extrema.Turned (T.A, T.C, Cos_A, Sin_A);
                  Q := Extrema.Turned (T.B, T.D, Cos_A, Sin_A);
               end if;
            end;
            Offset := 0.0;
         elsif Second then
            --  The selected space's y.
            P := T.C;
            Q := T.D;
            Offset := N.Clamp (Item.Center_Of_Mass_Y, Extrema.Mass_Limit);
         else
            --  The selected space's x.
            P := T.A;
            Q := T.B;
            Offset := N.Clamp (Item.Center_Of_Mass_X, Extrema.Mass_Limit);
         end if;
         Extrema.Median_Along
           (Map    => Results.Map.all,
            Id     => ID + 1,
            Pixels => Item.Pixel_Count,
            Cx     => N.Clamp (Results.Centroid_X (K), Extrema.Center_Limit),
            Cy     => N.Clamp (Results.Centroid_Y (K), Extrema.Center_Limit),
            P      => P,
            Q      => Q,
            Median => Relative,
            Found  => Found,
            Memory => Memory);
      end;
      if not Memory then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      Operation & ": out of memory");
      elsif not Found then
         Bad (Status, Operation & ": the results handle is not valid");
      else
         Median := Offset + Relative;
         Set_Success (Status);
      end if;
   end Get_Median;

   procedure Get_Median_X
     (Results : access constant Ks_Blob_Results_Data;
      ID      : Int32;
      Axis    : Int32;
      Median  : out Long_Float;
      Status  : out Ks_Status)
   is
   begin
      Get_Median (Results, ID, Axis, False, "GetMedianX", Median, Status);
   end Get_Median_X;

   procedure Get_Median_Y
     (Results : access constant Ks_Blob_Results_Data;
      ID      : Int32;
      Axis    : Int32;
      Median  : out Long_Float;
      Status  : out Ks_Status)
   is
   begin
      Get_Median (Results, ID, Axis, True, "GetMedianY", Median, Status);
   end Get_Median_Y;

   ---------------------------------------------------------------------
   --  Blob ID image
   ---------------------------------------------------------------------

   procedure Create_Blob_ID_Image
     (Results  : access constant Ks_Blob_Results_Data;
      Filtered : Int32;
      Image    : out KI.Ks_Image_16_Grey;
      Status   : out Ks_Status)
   is
   begin
      Image := null;
      if Results = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "CreateBlobIDImage: there are no results");
         return;
      elsif not Valid_Results (Results) then
         Bad (Status, "CreateBlobIDImage: the results handle is not valid");
         return;
      elsif Filtered not in False_Value | True_Value then
         Bad (Status, "CreateBlobIDImage: Filtered must be 0 or 1");
         return;
      elsif Results.Count > Max_ID_Image_Blobs then
         Bad (Status, "CreateBlobIDImage: more than 65535 blobs");
         return;
      end if;
      KI.Create (Results.Image_Width, Results.Image_Height, 0, Image,
                 Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Results.Map /= null then
         for Y in Results.Map'Range (1) loop
            for X in Results.Map'Range (2) loop
               pragma Loop_Invariant
                 (KI.Valid_Image (Image)
                  and then Image.Width = Results.Image_Width
                  and then Image.Height = Results.Image_Height);
               declare
                  Id : constant Int32 := Results.Map (Y, X);
               begin
                  if Id >= 1 and then Id <= Results.Count
                    and then (Filtered = False_Value
                              or else Results.Items (Integer (Id) - 1)
                                        .Filtered_Out = False_Value)
                  then
                     Image.Pixels (Y, X) := KI.Grey_16 (Id);
                  end if;
               end;
            end loop;
         end loop;
      end if;
      Set_Success (Status);
   end Create_Blob_ID_Image;

   ---------------------------------------------------------------------
   --  Blob image and segmented images
   ---------------------------------------------------------------------

   procedure Create_Blob_Image
     (Results    : access constant Ks_Blob_Results_Data;
      Filtered   : Int32;
      Viewable   : Int32;
      Background : Int32;
      Image      : out KI.Ks_Image_8_Grey;
      Status     : out Ks_Status)
   is
      Fill : Interfaces.Unsigned_8;
   begin
      Image := null;
      if Results = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "CreateBlobImage: there are no results");
         return;
      elsif not Valid_Results (Results) or else not Valid_Saved (Results)
      then
         Bad (Status, "CreateBlobImage: the results handle is not valid");
         return;
      elsif Filtered not in False_Value | True_Value then
         Bad (Status, "CreateBlobImage: Filtered must be 0 or 1");
         return;
      elsif Viewable not in False_Value | True_Value then
         Bad (Status, "CreateBlobImage: Viewable must be 0 or 1");
         return;
      elsif Viewable = False_Value and then Background not in 0 .. 255 then
         Bad (Status, "CreateBlobImage: Background must be in 0 .. 255");
         return;
      end if;
      Fill := (if Viewable = True_Value then 128
               else Interfaces.Unsigned_8 (Background));
      KI.Create (Results.Image_Width, Results.Image_Height, Fill, Image,
                 Status);
      if not Succeeded (Status) then
         return;
      end if;
      pragma Assert
        (for all Y in Image.Pixels'Range (1) =>
           (for all X in Image.Pixels'Range (2) =>
              (if Owner (Results, X, Y) < 0
               then Blob_Image_Value
                      (Results, Filtered, Viewable, Background, X, Y)
                    = Fill)));
      if Results.Map /= null then
         for Y in Results.Map'Range (1) loop
            for X in Results.Map'Range (2) loop
               Image.Pixels (Y, X) :=
                 Blob_Image_Value
                   (Results, Filtered, Viewable, Background, X, Y);
               pragma Loop_Invariant
                 (KI.Valid_Image (Image)
                  and then Image.Width = Results.Image_Width
                  and then Image.Height = Results.Image_Height);
               pragma Loop_Invariant
                 (for all YY in Image.Pixels'Range (1) =>
                    (for all XX in Image.Pixels'Range (2) =>
                       Image.Pixels (YY, XX)
                         = (if YY in Results.Map'Range (1)
                              and then XX in Results.Map'Range (2)
                              and then (YY < Y
                                        or else (YY = Y and then XX <= X))
                            then Blob_Image_Value
                                   (Results, Filtered, Viewable, Background,
                                    XX, YY)
                            else Fill)));
            end loop;
            pragma Loop_Invariant
              (KI.Valid_Image (Image)
               and then Image.Width = Results.Image_Width
               and then Image.Height = Results.Image_Height);
            pragma Loop_Invariant
              (for all YY in Image.Pixels'Range (1) =>
                 (for all XX in Image.Pixels'Range (2) =>
                    Image.Pixels (YY, XX)
                      = (if YY in Results.Map'First (1) .. Y
                           and then XX in Results.Map'Range (2)
                         then Blob_Image_Value
                                (Results, Filtered, Viewable, Background,
                                 XX, YY)
                         else Fill)));
         end loop;
      end if;
      Set_Success (Status);
   end Create_Blob_Image;

   procedure Make_Segmented
     (M             : access constant U8_Matrix;
      Width, Height : Int32;
      Full, Stretch : Int32;
      Image         : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status)
   with
     Pre  => Full in 1 .. 255 and then Stretch in False_Value | True_Value
             and then Level_Matrix_In_Image (M, Width, Height),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then Image.Width = Width
                     and then Image.Height = Height
                     and then
                       (for all Y in Image.Pixels'Range (1) =>
                          (for all X in Image.Pixels'Range (2) =>
                             Image.Pixels (Y, X)
                               = Stretched (Level_At (M, X, Y), Full,
                                            Stretch)))
                else Image = null);
   --  A new Width x Height image of the values of M, stretched or not
   --  (0 outside M).

   procedure Make_Segmented
     (M             : access constant U8_Matrix;
      Width, Height : Int32;
      Full, Stretch : Int32;
      Image         : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status)
   is
   begin
      KI.Create (Width, Height, 0, Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if M /= null then
         for Y in M'Range (1) loop
            for X in M'Range (2) loop
               Image.Pixels (Y, X) :=
                 Stretched (Int32 (M (Y, X)), Full, Stretch);
               pragma Loop_Invariant
                 (KI.Valid_Image (Image)
                  and then Image.Width = Width
                  and then Image.Height = Height);
               pragma Loop_Invariant
                 (for all YY in Image.Pixels'Range (1) =>
                    (for all XX in Image.Pixels'Range (2) =>
                       Image.Pixels (YY, XX)
                         = (if YY in M'Range (1) and then XX in M'Range (2)
                              and then (YY < Y
                                        or else (YY = Y and then XX <= X))
                            then Stretched (Level_At (M, XX, YY), Full,
                                            Stretch)
                            else 0)));
            end loop;
            pragma Loop_Invariant
              (KI.Valid_Image (Image)
               and then Image.Width = Width
               and then Image.Height = Height);
            pragma Loop_Invariant
              (for all YY in Image.Pixels'Range (1) =>
                 (for all XX in Image.Pixels'Range (2) =>
                    Image.Pixels (YY, XX)
                      = (if YY in M'First (1) .. Y
                           and then XX in M'Range (2)
                         then Stretched (Level_At (M, XX, YY), Full,
                                         Stretch)
                         else 0)));
         end loop;
      end if;
   end Make_Segmented;

   procedure Create_Segmented_Image
     (Results : access constant Ks_Blob_Results_Data;
      Which   : Int32;
      Stretch : Int32;
      Image   : out KI.Ks_Image_8_Grey;
      Status  : out Ks_Status)
   is
   begin
      Image := null;
      if Results = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "CreateSegmentedImage: there are no results");
      elsif not Valid_Results (Results) or else not Valid_Saved (Results)
      then
         Bad (Status, "CreateSegmentedImage: the results handle is not "
                      & "valid");
      elsif Which not in Segmented_Final_Image .. Segmented_Before_Masking
      then
         Bad (Status, "CreateSegmentedImage: WhichImage must be FinalImage "
                      & "(0), BeforeMorphology (1) or BeforeMasking (2)");
      elsif Stretch not in False_Value | True_Value then
         Bad (Status, "CreateSegmentedImage: StretchIt must be 0 or 1");
      elsif Which = Segmented_Final_Image then
         if Results.Saved_Final = False_Value then
            Set_Success (Status);
         else
            Make_Segmented
              (Results.Levels, Results.Image_Width, Results.Image_Height,
               Results.Full, Stretch, Image, Status);
         end if;
      elsif Which = Segmented_Before_Morphology then
         if Results.Saved_Before_Morphology = False_Value then
            Set_Success (Status);
         else
            Make_Segmented
              (Results.Before_Morphology, Results.Image_Width,
               Results.Image_Height, Results.Full, Stretch, Image, Status);
         end if;
      elsif Results.Saved_Before_Masking = False_Value then
         Set_Success (Status);
      else
         Make_Segmented
           (Results.Before_Masking, Results.Image_Width,
            Results.Image_Height, Results.Full, Stretch, Image, Status);
      end if;
   end Create_Segmented_Image;

end AMV.Kernels.Blob;
