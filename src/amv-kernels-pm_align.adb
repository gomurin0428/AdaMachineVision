pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.Filter_Inputs;
with AMV.Kernels.Numerics;
with AMV.Kernels.PM_Align.Masks;
with AMV.Kernels.PM_Align.Overlaps;
with AMV.Kernels.PM_Align.Poses;
with AMV.Kernels.PM_Align.Pyramids;
with AMV.Kernels.PM_Align.Refinement;
with AMV.Kernels.PM_Align.Search;
with AMV.Kernels.PM_Align.Training;

package body AMV.Kernels.PM_Align with SPARK_Mode is

   package FI renames AMV.Kernels.Filter_Inputs;
   package N renames AMV.Kernels.Numerics;
   package P renames AMV.Kernels.PM_Align.Poses;
   package MK renames AMV.Kernels.PM_Align.Masks;
   package OV renames AMV.Kernels.PM_Align.Overlaps;
   use type MK.KM.Ks_Real_Image;
   package PY renames AMV.Kernels.PM_Align.Pyramids;
   package RF renames AMV.Kernels.PM_Align.Refinement;
   package SR renames AMV.Kernels.PM_Align.Search;
   package TR renames AMV.Kernels.PM_Align.Training;

   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_PM_Align_Pattern_Data, Ks_PM_Align_Pattern);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_PM_Align_Results_Data, Ks_PM_Align_Results);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Pattern (Pattern : out Ks_PM_Align_Pattern)
   with
     Global => null,
     Post   => (if Pattern /= null then not Pattern.Trained);
   --  A new pattern with the record's default values (untrained, the
   --  default parameters, every level empty), or null when the memory
   --  cannot be allocated. Trusted: the allocator raises Storage_Error,
   --  which SPARK cannot express.

   procedure Allocate_Pattern (Pattern : out Ks_PM_Align_Pattern)
     with SPARK_Mode => Off
   is
   begin
      Pattern := new Ks_PM_Align_Pattern_Data;
   exception
      when Storage_Error =>
         Pattern := null;
   end Allocate_Pattern;

   procedure Allocate_Results (Results : out Ks_PM_Align_Results)
   with
     Global => null,
     Post   => (if Results /= null then Results.Count = 0);
   --  A new results record with no results, or null. Trusted as above.

   procedure Allocate_Results (Results : out Ks_PM_Align_Results)
     with SPARK_Mode => Off
   is
   begin
      Results := new Ks_PM_Align_Results_Data;
   exception
      when Storage_Error =>
         Results := null;
   end Allocate_Results;

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

   procedure Stream_Failure
     (Status  : out Ks_Status;
      Message : String)
   with Pre  => Message'Length <= 100,
        Post => Valid (Status) and then Status.Failure = Failure_Image_File;

   procedure Stream_Failure
     (Status  : out Ks_Status;
      Message : String) is
   begin
      Set_Failure (Status, Failure_Image_File,
                   "Ks_PM_Align_Pattern'Read: " & Message);
   end Stream_Failure;

   function In_Unit (X : Long_Float) return Boolean is
     (X >= 0.0 and then X <= 1.0);
   --  False for NaN at run time.

   ---------------------------------------------------------------------
   --  Checks of the parameters
   ---------------------------------------------------------------------

   procedure Check_Train_Params
     (Params : Ks_PM_Align_Train_Params;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Valid_Train_Params (Params));

   procedure Check_Train_Params
     (Params : Ks_PM_Align_Train_Params;
      Status : out Ks_Status) is
   begin
      if Params.Train_Algorithm
           not in Train_Algorithm_Pat_Max | Train_Algorithm_Pat_Quick
                | Train_Algorithm_Pat_Max_And_Pat_Quick
      then
         Bad (Status, "Pattern.TrainAlgorithm must be PatMax, PatQuick or"
                      & " PatMaxAndPatQuick (the others are not"
                      & " supported)");
      elsif Params.Grain_Limit_Auto_Select not in False_Value | True_Value
      then
         Bad (Status, "Pattern.GrainLimitAutoSelect must be 0 or 1");
      elsif Params.Ignore_Polarity not in False_Value | True_Value then
         Bad (Status, "Pattern.IgnorePolarity must be 0 or 1");
      elsif not (Params.Grain_Limit_Coarse >= 1.0
                 and then Params.Grain_Limit_Coarse <= Max_Grain_Limit)
      then
         Bad (Status, "Pattern.GrainLimitCoarse must be in [1, 32]");
      elsif not (Params.Grain_Limit_Fine >= 1.0
                 and then Params.Grain_Limit_Fine
                            <= Params.Grain_Limit_Coarse)
      then
         Bad (Status, "Pattern.GrainLimitFine must be in [1,"
                      & " GrainLimitCoarse]");
      else
         Set_Success (Status);
      end if;
   end Check_Train_Params;

   procedure Check_Angle_Zone
     (Zone   : Ks_PM_Align_Zone_Angle;
      Status : in out Ks_Status)
   with Pre  => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter,
        Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old)
                               and then Valid_Angle_Zone (Zone));
   --  The checks of RunParams.ZoneAngle (nothing after a failure).

   procedure Check_Angle_Zone
     (Zone   : Ks_PM_Align_Zone_Angle;
      Status : in out Ks_Status) is
   begin
      if not Succeeded (Status) then
         return;
      elsif Zone.Configuration not in Zone_Nominal | Zone_Low_High then
         Bad (Status, "RunParams.ZoneAngle.Configuration must be Nominal or"
                      & " LowHigh");
      elsif Zone.Configuration = Zone_Nominal
        and then not (Zone.Nominal >= -Max_Zone_Angle
                      and then Zone.Nominal <= Max_Zone_Angle)
      then
         Bad (Status, "RunParams.ZoneAngle.Nominal must be finite and within"
                      & " +/-1.0E4");
      elsif Zone.Configuration = Zone_Low_High
        and then not (Zone.Low >= -Max_Zone_Angle
                      and then Zone.High <= Max_Zone_Angle
                      and then Zone.Low <= Zone.High)
      then
         Bad (Status, "RunParams.ZoneAngle.Low and High must be finite,"
                      & " within +/-1.0E4 and Low <= High");
      end if;
   end Check_Angle_Zone;

   procedure Check_Scale_Zone
     (Zone   : Ks_PM_Align_Zone_Scale;
      Status : in out Ks_Status)
   with Pre  => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter,
        Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old)
                               and then Valid_Scale_Zone (Zone));
   --  The checks of RunParams.ZoneScale (nothing after a failure).

   procedure Check_Scale_Zone
     (Zone   : Ks_PM_Align_Zone_Scale;
      Status : in out Ks_Status) is
   begin
      if not Succeeded (Status) then
         return;
      elsif Zone.Configuration not in Zone_Nominal | Zone_Low_High then
         Bad (Status, "RunParams.ZoneScale.Configuration must be Nominal or"
                      & " LowHigh");
      elsif Zone.Configuration = Zone_Nominal
        and then not (Zone.Nominal >= Min_Zone_Scale
                      and then Zone.Nominal <= Max_Zone_Scale)
      then
         Bad (Status, "RunParams.ZoneScale.Nominal must be in [0.1, 10]");
      elsif Zone.Configuration = Zone_Low_High
        and then not (Zone.Low >= Min_Zone_Scale
                      and then Zone.High <= Max_Zone_Scale
                      and then Zone.Low <= Zone.High)
      then
         Bad (Status, "RunParams.ZoneScale.Low and High must be in [0.1,"
                      & " 10] and Low <= High");
      end if;
   end Check_Scale_Zone;

   procedure Check_Run_Params
     (Params : Ks_PM_Align_Run_Params;
      Status : out Ks_Status) is
   begin
      if not In_Unit (Params.Accept_Threshold) then
         Bad (Status, "RunParams.AcceptThreshold must be in [0, 1]");
      elsif not In_Unit (Params.Coarse_Accept_Threshold) then
         Bad (Status, "RunParams.CoarseAcceptThreshold must be in [0, 1]");
      elsif not (Params.Contrast_Threshold >= 0.0
                 and then Params.Contrast_Threshold <= Max_Contrast_Threshold)
      then
         Bad (Status, "RunParams.ContrastThreshold must be in [0, 1000]");
      elsif not In_Unit (Params.Outside_Region_Threshold) then
         Bad (Status, "RunParams.OutsideRegionThreshold must be in [0, 1]");
      elsif not In_Unit (Params.XY_Overlap) then
         Bad (Status, "RunParams.XYOverlap must be in [0, 1]");
      elsif not (Params.Timeout >= 0.0
                 and then Params.Timeout <= Max_Timeout)
      then
         Bad (Status, "RunParams.Timeout must be in [0, 1.0E9]");
      elsif Params.Approximate_Number_To_Find not in 1 .. Max_Results_Limit
      then
         Bad (Status, "RunParams.ApproximateNumberToFind must be in 1 .."
                      & " 256");
      elsif Params.Run_Algorithm
              not in Run_Algorithm_Pat_Max | Run_Algorithm_Pat_Quick
                   | Run_Algorithm_Best_Trained
      then
         Bad (Status, "RunParams.RunAlgorithm must be PatMax, PatQuick or"
                      & " BestTrained (PatFlex and PatMaxPerspective are"
                      & " not supported)");
      elsif Params.Score_Using_Clutter not in False_Value | True_Value then
         Bad (Status, "RunParams.ScoreUsingClutter must be 0 or 1");
      elsif Params.Timeout_Enabled not in False_Value | True_Value then
         Bad (Status, "RunParams.TimeoutEnabled must be 0 or 1");
      elsif Params.Coarse_Accept_Threshold_Enabled
              not in False_Value | True_Value
      then
         Bad (Status, "RunParams.CoarseAcceptThresholdEnabled must be 0 or"
                      & " 1");
      else
         Set_Success (Status);
         Check_Angle_Zone (Params.Zone_Angle, Status);
         Check_Scale_Zone (Params.Zone_Scale, Status);
      end if;
   end Check_Run_Params;

   procedure Check_Params
     (Params : Ks_PM_Align_Run_Params;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Valid_Run_Params (Params));
   --  Check_Run_Params with the fact it establishes.

   procedure Check_Params
     (Params : Ks_PM_Align_Run_Params;
      Status : out Ks_Status) is
   begin
      Check_Run_Params (Params, Status);
      if Succeeded (Status) and then not Valid_Run_Params (Params) then
         --  Never: the checks above are those of Valid_Run_Params.
         Bad (Status, "RunParams are not valid");
      end if;
   end Check_Params;

   ---------------------------------------------------------------------
   --  Entry points: parameters
   ---------------------------------------------------------------------

   procedure Train_Params_Default
     (Params : out Ks_PM_Align_Train_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Train_Params_Default;

   procedure Run_Params_Default
     (Params : out Ks_PM_Align_Run_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Run_Params_Default;

   ---------------------------------------------------------------------
   --  Entry points: the pattern
   ---------------------------------------------------------------------

   procedure Pattern_Create
     (Pattern : out Ks_PM_Align_Pattern;
      Status  : out Ks_Status) is
   begin
      Allocate_Pattern (Pattern);
      if Pattern = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "PMAlignPattern: out of memory");
      else
         Set_Success (Status);
      end if;
   end Pattern_Create;

   procedure Pattern_Destroy (Pattern : in out Ks_PM_Align_Pattern) is
   begin
      if Pattern /= null then
         Free (Pattern);
      end if;
   end Pattern_Destroy;

   procedure Pattern_Duplicate
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Copy    : out Ks_PM_Align_Pattern;
      Status  : out Ks_Status) is
   begin
      Copy := null;
      if Pattern = null then
         Set_Success (Status);
         return;
      end if;
      Allocate_Pattern (Copy);
      if Copy = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "PMAlignPattern: out of memory");
         return;
      end if;
      Copy.all := Pattern.all;
      Set_Success (Status);
   end Pattern_Duplicate;

   procedure Pattern_Get_Train_Params
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Params  : out Ks_PM_Align_Train_Params;
      Status  : out Ks_Status) is
   begin
      if Pattern = null or else not Valid_Train_Params (Pattern.Params) then
         Params := (others => <>);
      else
         Params := Pattern.Params;
      end if;
      Set_Success (Status);
   end Pattern_Get_Train_Params;

   procedure Pattern_Set_Train_Params
     (Pattern : Ks_PM_Align_Pattern;
      Params  : Ks_PM_Align_Train_Params;
      Status  : out Ks_Status) is
   begin
      if Pattern = null then
         Bad (Status, "Pattern is null");
         return;
      end if;
      Check_Train_Params (Params, Status);
      if Succeeded (Status) then
         Pattern.Params := Params;
         Pattern.Trained := False;
      end if;
   end Pattern_Set_Train_Params;

   procedure Pattern_Trained
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Result  : out Int32;
      Status  : out Ks_Status) is
   begin
      Result := (if Trained_Pattern (Pattern) then True_Value
                 else False_Value);
      Set_Success (Status);
   end Pattern_Trained;

   procedure Pattern_Untrain
     (Pattern : Ks_PM_Align_Pattern;
      Status  : out Ks_Status) is
   begin
      if Pattern /= null then
         Pattern.Trained := False;
      end if;
      Set_Success (Status);
   end Pattern_Untrain;

   procedure Not_Trained (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Operator_Not_Trained;

   procedure Not_Trained (Status : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Operator_Not_Trained,
                   "Pattern is not trained");
   end Not_Trained;

   procedure Pattern_Levels
     (Pattern          : access constant Ks_PM_Align_Pattern_Data;
      Finest, Coarsest : out Int32;
      Status           : out Ks_Status) is
   begin
      Finest := 0;
      Coarsest := 0;
      if not Trained_Pattern (Pattern) then
         Not_Trained (Status);
         return;
      end if;
      Finest := Int32 (Pattern.Finest);
      Coarsest := Int32 (Level_Index'Max (Pattern.Finest, Pattern.Coarsest));
      Set_Success (Status);
   end Pattern_Levels;

   procedure Pattern_Feature_Count
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Level   : Int32;
      Count   : out Int32;
      Status  : out Ks_Status) is
   begin
      Count := 0;
      if not Trained_Pattern (Pattern) then
         Not_Trained (Status);
      elsif Level not in 0 .. Max_Levels - 1 then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "PMAlignPattern: level outside 0 .. 5");
      else
         if Natural (Level) in Pattern.Finest .. Pattern.Coarsest then
            Count := Int32 (Pattern.Levels (Natural (Level)).Count);
         end if;
         Set_Success (Status);
      end if;
   end Pattern_Feature_Count;

   procedure Pattern_Feature
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Level   : Int32;
      Index   : Int32;
      Feature : out Ks_PM_Align_Feature;
      Status  : out Ks_Status) is
   begin
      Feature := (others => 0.0);
      if not Trained_Pattern (Pattern) then
         Not_Trained (Status);
      elsif Level not in 0 .. Max_Levels - 1
        or else Natural (Level) not in Pattern.Finest .. Pattern.Coarsest
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "PMAlignPattern: level outside the model");
      elsif Index < 0
        or else Index >= Int32 (Pattern.Levels (Natural (Level)).Count)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "PMAlignPattern: feature index outside 0 .. Count -"
                      & " 1");
      else
         declare
            F : constant Model_Feature :=
              Pattern.Levels (Natural (Level)).Features (Natural (Index));
         begin
            Feature := (X => F.X, Y => F.Y, Normal_X => F.NX,
                        Normal_Y => F.NY);
         end;
         Set_Success (Status);
      end if;
   end Pattern_Feature;

   ---------------------------------------------------------------------
   --  Training
   ---------------------------------------------------------------------

   function Floor_Log_2 (X : Long_Float) return Level_Index is
     (if X >= 32.0 then 5
      elsif X >= 16.0 then 4
      elsif X >= 8.0 then 3
      elsif X >= 4.0 then 2
      elsif X >= 2.0 then 1
      else 0);
   --  The level whose grain is the largest power of two at most X.

   function Auto_Coarsest (Side : Int32) return Level_Index is
     (if Side >= Min_Coarse_Size * 32 then 5
      elsif Side >= Min_Coarse_Size * 16 then 4
      elsif Side >= Min_Coarse_Size * 8 then 3
      elsif Side >= Min_Coarse_Size * 4 then 2
      elsif Side >= Min_Coarse_Size * 2 then 1
      else 0);
   --  The highest level at which a side of Side pixels still spans
   --  Min_Coarse_Size pixels.

   function Window_Around
     (Region : access constant KR.Ks_Pixel_Region_Data;
      Image  : access constant KI.Ks_Image_8_Grey_Data;
      Margin : Int32) return PY.Window
   with Pre  => KI.Valid_Image (Image) and then Region /= null
                and then KR.In_Image (Region, Image.Width, Image.Height)
                and then Margin in 0 .. 1024,
        Post => PY.Window_In_Image (Window_Around'Result, Image);
   --  The region's bounding box grown by Margin on each side, within the
   --  image.

   function Window_Around
     (Region : access constant KR.Ks_Pixel_Region_Data;
      Image  : access constant KI.Ks_Image_8_Grey_Data;
      Margin : Int32) return PY.Window
   is
      X0 : constant Int64 :=
        Int64'Max (0, Int64 (Region.X_Min) - Int64 (Margin));
      Y0 : constant Int64 :=
        Int64'Max (0, Int64 (Region.Y_Min) - Int64 (Margin));
      X1 : constant Int64 :=
        Int64'Min (Int64 (Image.Width) - 1,
                   Int64 (Region.X_Min) + Int64 (Region.Width) - 1
                   + Int64 (Margin));
      Y1 : constant Int64 :=
        Int64'Min (Int64 (Image.Height) - 1,
                   Int64 (Region.Y_Min) + Int64 (Region.Height) - 1
                   + Int64 (Margin));
   begin
      return (X_Min  => Int32 (X0), Y_Min => Int32 (Y0),
              Width  => Int32 (X1 - X0 + 1),
              Height => Int32 (Y1 - Y0 + 1));
   end Window_Around;

   function Margin_For (Coarsest : Level_Index) return Int32 is
     (case Coarsest is
         when 0 => 4, when 1 => 6, when 2 => 10, when 3 => 18,
         when 4 => 34, when 5 => 66);
   --  The margin of a pyramid's window around its region: two pixels of
   --  the coarsest level, so that smoothing near the region's border sees
   --  the image.

   procedure Clear_Model (Pattern : Ks_PM_Align_Pattern)
   with Pre  => Pattern /= null,
        Post => not Pattern.Trained
                and then Pattern.Params = Pattern.Params'Old;
   --  Untrains the pattern and empties every level.

   procedure Clear_Model (Pattern : Ks_PM_Align_Pattern) is
      Params : constant Ks_PM_Align_Train_Params := Pattern.Params;
   begin
      Pattern.Trained := False;
      Pattern.Finest := 0;
      Pattern.Coarsest := 0;
      for K in Level_Index loop
         Pattern.Levels (K).Count := 0;
         Pattern.Levels (K).Spacing := 1;
         Pattern.Levels (K).Ignored_Count := 0;
         Pattern.Levels (K).Ignored_Spacing := 1;
         pragma Loop_Invariant
           (not Pattern.Trained and then Pattern.Params = Params);
      end loop;
   end Clear_Model;

   procedure Build_Model
     (Pattern            : Ks_PM_Align_Pattern;
      Image              : access constant KI.Ks_Image_8_Grey_Data;
      Region             : access constant KR.Ks_Pixel_Region_Data;
      Mask               : access constant KI.Ks_Image_8_Grey_Data;
      Mask_Offset_X      : Int32;
      Mask_Offset_Y      : Int32;
      Pattern_From_Pixel : KT.Ks_Transform_2D_Linear;
      Pyr                : in out PY.Pyramid;
      Care               : in out MK.Care_Map;
      Status             : out Ks_Status)
   with
     Pre  => Care.Counts = null
             and then Pattern /= null and then not Pattern.Trained
             and then KI.Valid_Image (Image) and then Region /= null
             and then (Mask = null or else KI.Valid_Image (Mask))
             and then KR.In_Image (Region, Image.Width, Image.Height)
             and then KT.Bounded (Pattern_From_Pixel),
     Post => PY.Released (Pyr) and then Care.Counts = null
             and then Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Succeeded (Status) then Pattern.Trained
                       else not Pattern.Trained);
   --  The model of Train (see Pattern_Train_Masked), with Pyr the pyramid
   --  of the train image and Care the care map of the mask (both released
   --  when the call returns).

   procedure Build_Model
     (Pattern            : Ks_PM_Align_Pattern;
      Image              : access constant KI.Ks_Image_8_Grey_Data;
      Region             : access constant KR.Ks_Pixel_Region_Data;
      Mask               : access constant KI.Ks_Image_8_Grey_Data;
      Mask_Offset_X      : Int32;
      Mask_Offset_Y      : Int32;
      Pattern_From_Pixel : KT.Ks_Transform_2D_Linear;
      Pyr                : in out PY.Pyramid;
      Care               : in out MK.Care_Map;
      Status             : out Ks_Status)
   is
      Finest   : Level_Index;
      Top      : Level_Index;
      Coarsest : Level_Index;
      Normals  : constant P.Unit_Linear :=
        P.Normal_Map (P.Linear_Of (Pattern_From_Pixel));
      Far      : Boolean;
   begin
      --  The levels.
      if Pattern.Params.Grain_Limit_Auto_Select = True_Value then
         Finest := 0;
         Top := Auto_Coarsest (Int32'Min (Region.Width, Region.Height));
      else
         Finest := Floor_Log_2 (Pattern.Params.Grain_Limit_Fine);
         Top := Level_Index'Max
           (Finest, Floor_Log_2 (Pattern.Params.Grain_Limit_Coarse));
      end if;

      declare
         Area : constant PY.Window :=
           Window_Around (Region, Image, Margin_For (Top));
      begin
         PY.Build (Image, Region, Area, Top + 1, False, 0.0, Pyr, Status);
         if not Succeeded (Status) then
            PY.Release (Pyr);
            return;
         end if;
         MK.Build (Mask, Mask_Offset_X, Mask_Offset_Y, Area, Care, Status);
         if not Succeeded (Status) then
            PY.Release (Pyr);
            return;
         end if;
         Coarsest := Finest;
         for K in Finest .. Top loop
            pragma Loop_Invariant
              (Pattern /= null and then not Pattern.Trained
               and then Coarsest in Finest .. Top
               and then Succeeded (Status)
               and then MK.Valid_Map (Care));
            if K < Pyr.Count and then PY.Usable (Pyr.Levels (K)) then
               TR.Extract (Pyr.Levels (K), K, Region, Area, Care,
                           Pattern_From_Pixel, Normals, Pattern.Levels (K),
                           Far);
               if not Far then
                  TR.Extract_Ignored (Pyr.Levels (K), K, Region, Area, Care,
                                      Pattern_From_Pixel,
                                      Pattern.Levels (K));
               end if;
            else
               Pattern.Levels (K).Count := 0;
               Pattern.Levels (K).Ignored_Count := 0;
               Far := False;
            end if;
            if Far then
               Bad (Status, "Pattern.Origin places a trained feature beyond"
                            & " +/-1.0E9");
               exit;
            elsif Pattern.Levels (K).Count < Min_Features then
               if K = Finest then
                  Bad (Status, "TrainImage has too few edges in"
                               & " TrainRegion");
               end if;
               exit;
            end if;
            Coarsest := K;
         end loop;
         MK.Release (Care);
      end;
      PY.Release (Pyr);
      if not Succeeded (Status) then
         Clear_Model (Pattern);
         return;
      end if;

      for K in Level_Index loop
         if K < Finest or else K > Coarsest then
            Pattern.Levels (K).Count := 0;
            Pattern.Levels (K).Ignored_Count := 0;
         end if;
         pragma Loop_Invariant (Pattern /= null and then not Pattern.Trained);
      end loop;
      Pattern.Finest := Finest;
      Pattern.Coarsest := Coarsest;
      Pattern.Trained := True;
   end Build_Model;

   procedure Pattern_Train
     (Pattern             : Ks_PM_Align_Pattern;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Origin              : KT.Ks_Transform_2D_Linear;
      Status              : out Ks_Status) is
   begin
      Pattern_Train_Masked (Pattern, Image, Region, Selected_From_Pixel,
                            Origin, null, 0, 0, Status);
   end Pattern_Train;

   procedure Pattern_Train_Masked
     (Pattern             : Ks_PM_Align_Pattern;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Origin              : KT.Ks_Transform_2D_Linear;
      Mask                : access constant KI.Ks_Image_8_Grey_Data;
      Mask_Offset_X       : Int32;
      Mask_Offset_Y       : Int32;
      Status              : out Ks_Status)
   is
      Inverse_Origin     : KT.Ks_Transform_2D_Linear;
      Unused_Inverse     : KT.Ks_Transform_2D_Linear;
      Pattern_From_Pixel : KT.Ks_Transform_2D_Linear;
      S                  : Ks_Status;
      Unused_Pyramid     : PY.Pyramid;
      Unused_Care        : MK.Care_Map;
   begin
      if Pattern = null then
         Bad (Status, "Pattern is null");
         return;
      end if;
      Clear_Model (Pattern);
      if Image = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "TrainImage has no pixels");
         return;
      elsif not FI.Usable_Image (Image) then
         Bad (Status, "TrainImage is not a valid image handle");
         return;
      elsif Region = null then
         Bad (Status, "TrainRegion contains no pixel of TrainImage");
         return;
      elsif not KR.Valid_Region (Region)
        or else not KR.In_Image (Region, Image.Width, Image.Height)
      then
         Bad (Status, "TrainRegion is not a valid pixel region of"
                      & " TrainImage");
         return;
      elsif not KT.Bounded (Selected_From_Pixel) then
         Bad (Status, "TrainImage's selected space transform must be finite"
                      & " and within +/-1.0E150");
         return;
      elsif not KT.Bounded (Origin) then
         Bad (Status, "Pattern.Origin must be finite and within"
                      & " +/-1.0E150");
         return;
      elsif Mask /= null and then not FI.Usable_Image (Mask) then
         Bad (Status, "TrainImageMask is not a valid image handle");
         return;
      end if;
      KT.Invert (Origin, Inverse_Origin, S);
      if not Succeeded (S) then
         Set_Failure (Status, Failure_Transform_Singular,
                      "Pattern.Origin has no inverse within +/-1.0E150");
         return;
      end if;
      KT.Invert (Selected_From_Pixel, Unused_Inverse, S);
      if not Succeeded (S) then
         Set_Failure (Status, Failure_Transform_Singular,
                      "TrainImage's selected space has no inverse within"
                      & " +/-1.0E150");
         return;
      end if;
      KT.Compose (Inverse_Origin, Selected_From_Pixel, Pattern_From_Pixel, S);
      if not Succeeded (S) then
         Bad (Status, "Pattern.Origin and TrainImage's selected space map"
                      & " pixels beyond +/-1.0E150");
         return;
      end if;
      Build_Model (Pattern, Image, Region, Mask, Mask_Offset_X,
                   Mask_Offset_Y, Pattern_From_Pixel, Unused_Pyramid,
                   Unused_Care, Status);
   end Pattern_Train_Masked;

   ---------------------------------------------------------------------
   --  Running
   ---------------------------------------------------------------------

   type Final is record
      X, Y      : P.Position := 0.0;
      Theta     : P.Zone_Angle_Value := 0.0;
      Scale     : P.Scale_Value := 1.0;
      Score     : P.Fraction := 0.0;
      Measures  : RF.Measures;
      Separation : P.Pixel_Radius := 1.0;
      Fine      : Boolean := False;
      Kept      : Boolean := False;
      Level     : Level_Index := 0;
   end record;
   --  A candidate after the last stage: the centroid in level-0 pixels of
   --  the pyramid's window, the pose, the final score and measures, the
   --  distance within which another result is the same instance.

   type Final_Array is array (0 .. Max_Candidates - 1) of Final;

   type Final_List is record
      Count : Natural range 0 .. Max_Candidates := 0;
      Items : Final_Array;
   end record;

   procedure Sort_Finals (List : in out Final_List) is
   begin
      for I in 1 .. List.Count - 1 loop
         declare
            C : constant Final := List.Items (I);
            J : Natural := I;
         begin
            while J > 0 and then List.Items (J - 1).Score < C.Score loop
               pragma Loop_Invariant (J <= I);
               pragma Loop_Variant (Decreases => J);
               List.Items (J) := List.Items (J - 1);
               J := J - 1;
            end loop;
            List.Items (J) := C;
         end;
      end loop;
   end Sort_Finals;
   --  Sorts by score, highest first.

   procedure Select_Finals
     (List    : in out Final_List;
      Pattern : access constant Ks_PM_Align_Pattern_Data;
      F       : P.Frame;
      Params  : Ks_PM_Align_Run_Params)
   with Pre => Trained_Pattern (Pattern) and then Valid_Run_Params (Params);
   --  Marks Kept the finals (sorted by score) that reach AcceptThreshold,
   --  lie inside the region enough (OutsideRegionThreshold), are not
   --  within the separation of a better kept one and do not share more
   --  than XYOverlap of the smaller footprint with a better kept one (the
   --  footprint: the bounding box of the finest level's features, mapped
   --  by the final's pose).

   function Footprint
     (Item                   : Final;
      F                      : P.Frame;
      Min_X, Max_X, Min_Y, Max_Y : P.Relative) return OV.Quad;
   --  The corners of the box (relative to the model's centroid) mapped by
   --  the pose of Item, in level-0 pixels of the window.

   function Footprint
     (Item                   : Final;
      F                      : P.Frame;
      Min_X, Max_X, Min_Y, Max_Y : P.Relative) return OV.Quad
   is
      R      : constant P.Rotation := P.Rotation_Of (Item.Theta);
      Result : OV.Quad;
      type Corner_List is array (0 .. 3) of P.Relative;
      CX : constant Corner_List := [Min_X, Max_X, Max_X, Min_X];
      CY : constant Corner_List := [Min_Y, Min_Y, Max_Y, Max_Y];
      DX, DY : P.Offset;
   begin
      for K in 0 .. 3 loop
         P.Map_Offset (F, R, Item.Scale, 0, CX (K), CY (K), DX, DY);
         --  A position within 2**33 plus an offset within 2**20.
         Result (K) := (X => Item.X + DX, Y => Item.Y + DY);
      end loop;
      return Result;
   end Footprint;

   procedure Select_Finals
     (List    : in out Final_List;
      Pattern : access constant Ks_PM_Align_Pattern_Data;
      F       : P.Frame;
      Params  : Ks_PM_Align_Run_Params)
   is
      Model : Model_Level renames Pattern.Levels (Pattern.Finest);
      Min_X, Max_X, Min_Y, Max_Y : P.Relative := 0.0;
      Boxes : array (0 .. Max_Candidates - 1) of OV.Quad :=
        [others => [others => (others => <>)]];
   begin
      if Model.Count > 0 then
         Min_X := Model.Features (0).X - F.Centroid_X;
         Max_X := Min_X;
         Min_Y := Model.Features (0).Y - F.Centroid_Y;
         Max_Y := Min_Y;
         for I in 1 .. Model.Count - 1 loop
            Min_X := Long_Float'Min (Min_X,
                                     Model.Features (I).X - F.Centroid_X);
            Max_X := Long_Float'Max (Max_X,
                                     Model.Features (I).X - F.Centroid_X);
            Min_Y := Long_Float'Min (Min_Y,
                                     Model.Features (I).Y - F.Centroid_Y);
            Max_Y := Long_Float'Max (Max_Y,
                                     Model.Features (I).Y - F.Centroid_Y);
         end loop;
      end if;
      for I in 0 .. List.Count - 1 loop
         Boxes (I) := Footprint (List.Items (I), F, Min_X, Max_X, Min_Y,
                                 Max_Y);
      end loop;
      for I in 0 .. List.Count - 1 loop
         declare
            Keep : Boolean :=
              List.Items (I).Score >= Params.Accept_Threshold
              and then List.Items (I).Measures.Outside
                         <= Params.Outside_Region_Threshold;
         begin
            if Keep then
               for J in 0 .. I - 1 loop
                  if List.Items (J).Kept
                    and then (N.Hypot
                                (List.Items (I).X - List.Items (J).X,
                                 List.Items (I).Y - List.Items (J).Y)
                              < List.Items (J).Separation
                              or else OV.Overlap_Fraction
                                        (Boxes (I), Boxes (J))
                                      > Params.XY_Overlap)
                  then
                     Keep := False;
                     exit;
                  end if;
               end loop;
            end if;
            List.Items (I).Kept := Keep;
         end;
      end loop;
   end Select_Finals;

   procedure Make_Item
     (Final_Item          : Final;
      Area                : PY.Window;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      F                   : P.Frame;
      Params              : Ks_PM_Align_Run_Params;
      Item                : out Ks_PM_Align_Result;
      Ok                  : out Boolean)
   with Pre  => KT.Bounded (Selected_From_Pixel)
                and then Valid_Run_Params (Params),
        Post => (if Ok then Good_Result (Item, Params));
   --  The result of a final: the pose's translation is the selected-space
   --  point of the centroid minus the rotated and scaled centroid (in
   --  pattern coordinates). Not Ok when the translation leaves 1.0E150 or
   --  the score is below AcceptThreshold.

   procedure Make_Item
     (Final_Item          : Final;
      Area                : PY.Window;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      F                   : P.Frame;
      Params              : Ks_PM_Align_Run_Params;
      Item                : out Ks_PM_Align_Result;
      Ok                  : out Boolean)
   is
      Theta  : constant P.Zone_Angle_Value :=
        P.Angle_In_Zone (Final_Item.Theta, Params.Zone_Angle);
      Scale  : constant P.Scale_Value :=
        P.Scale_In_Zone (Final_Item.Scale, Params.Zone_Scale);
      R      : constant P.Rotation := P.Rotation_Of (Theta);
      CX     : constant Long_Float :=
        N.Times_Unit (F.Centroid_X, R.Cos_T)
        - N.Times_Unit (F.Centroid_Y, R.Sin_T);
      CY     : constant Long_Float :=
        N.Times_Unit (F.Centroid_X, R.Sin_T)
        + N.Times_Unit (F.Centroid_Y, R.Cos_T);
      SX     : constant Long_Float :=
        N.Mul_Within (CX, Scale, 2.0 * Max_Pattern_Coordinate,
                      Max_Zone_Scale);
      SY     : constant Long_Float :=
        N.Mul_Within (CY, Scale, 2.0 * Max_Pattern_Coordinate,
                      Max_Zone_Scale);
      MX, MY : Long_Float;
      S      : Ks_Status;
   begin
      Item := (others => <>);
      Ok := False;
      KT.Map_Point (Selected_From_Pixel,
                    Final_Item.X + Long_Float (Area.X_Min),
                    Final_Item.Y + Long_Float (Area.Y_Min), MX, MY, S);
      if not Succeeded (S) then
         return;
      end if;
      Item :=
        (Score                             => Final_Item.Score,
         Coverage                          => Final_Item.Measures.Coverage,
         Clutter                           => Final_Item.Measures.Clutter,
         Fit_Error                         => Final_Item.Measures.Fit_Error,
         Contrast                          => Final_Item.Measures.Contrast,
         Outside_Region_Feature_Proportion => Final_Item.Measures.Outside,
         Translation_X                     => MX - SX,
         Translation_Y                     => MY - SY,
         Rotation                          => Theta,
         Scaling                           => Scale,
         ID                                => 0,
         Fine_Stage                        =>
           (if Final_Item.Fine then True_Value else False_Value));
      Ok := Good_Result (Item, Params);
   end Make_Item;

   procedure Build_Results
     (List                : Final_List;
      Area                : PY.Window;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      F                   : P.Frame;
      Params              : Ks_PM_Align_Run_Params;
      Results             : Ks_PM_Align_Results)
   with Pre  => Results /= null and then Results.Count = 0
                and then KT.Bounded (Selected_From_Pixel)
                and then Valid_Run_Params (Params),
        Post => Gold_Results (Results, Params);
   --  Appends the kept finals (sorted by score), at most
   --  ApproximateNumberToFind of them, with ID = their index.

   procedure Build_Results
     (List                : Final_List;
      Area                : PY.Window;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      F                   : P.Frame;
      Params              : Ks_PM_Align_Run_Params;
      Results             : Ks_PM_Align_Results)
   is
      Item : Ks_PM_Align_Result;
      Ok   : Boolean;
   begin
      for I in 0 .. List.Count - 1 loop
         pragma Loop_Invariant
           (Results /= null and then Gold_Results (Results, Params));
         if List.Items (I).Kept
           and then Results.Count < Natural (Params.Approximate_Number_To_Find)
         then
            Make_Item (List.Items (I), Area, Selected_From_Pixel, F, Params,
                       Item, Ok);
            --  The finals are sorted by score, so the second test never
            --  fails; it states the order for the proof.
            if Ok
              and then (Results.Count = 0
                        or else Item.Score
                                  <= Results.Items (Results.Count - 1).Score)
            then
               Item.ID := Int32 (Results.Count);
               Results.Items (Results.Count) := Item;
               Results.Count := Results.Count + 1;
            end if;
         end if;
      end loop;
   end Build_Results;

   function Resolved_Algorithm
     (Params  : Ks_PM_Align_Run_Params;
      Pattern : access constant Ks_PM_Align_Pattern_Data) return Int32
   is (if Params.Run_Algorithm = Run_Algorithm_Best_Trained
       then (if Pattern.Params.Train_Algorithm = Train_Algorithm_Pat_Quick
             then Run_Algorithm_Pat_Quick else Run_Algorithm_Pat_Max)
       else Params.Run_Algorithm)
   with Pre => Pattern /= null;
   --  PatMax or PatQuick: BestTrained resolved by TrainAlgorithm.

   function Eligible
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      K       : Level_Index) return Boolean
   is (Pattern.Levels (K).Count >= Min_Result_Features)
   with Pre => Pattern /= null;
   --  With the automatic grain, whether level K may give the results: its
   --  model has at least Min_Result_Features features (see the spec).

   procedure One_Level
     (Finals : in out Final_List;
      Params : Ks_PM_Align_Run_Params)
   with Post => Finals.Count <= Finals.Count'Old;
   --  Keeps only the finals measured at the finest level at which one of
   --  them reaches AcceptThreshold (all of them when none does), so that
   --  the results of a run are measured at one level and compare.

   procedure One_Level
     (Finals : in out Final_List;
      Params : Ks_PM_Align_Run_Params)
   is
      Best : Level_Index := Max_Levels - 1;
      Any  : Boolean := False;
      Kept : Natural range 0 .. Max_Candidates := 0;
   begin
      for I in 0 .. Finals.Count - 1 loop
         if Finals.Items (I).Score >= Params.Accept_Threshold
           and then (not Any or else Finals.Items (I).Level < Best)
         then
            Best := Finals.Items (I).Level;
            Any := True;
         end if;
      end loop;
      if Any then
         for I in 0 .. Finals.Count - 1 loop
            pragma Loop_Invariant (Kept <= I);
            if Finals.Items (I).Level = Best then
               Finals.Items (Kept) := Finals.Items (I);
               Kept := Kept + 1;
            end if;
         end loop;
         Finals.Count := Kept;
      end if;
   end One_Level;

   procedure Finish_PatMax
     (Pattern  : access constant Ks_PM_Align_Pattern_Data;
      F        : P.Frame;
      Pyr      : PY.Pyramid;
      Region   : access constant KR.Ks_Pixel_Region_Data;
      Params   : Ks_PM_Align_Run_Params;
      C        : SR.Candidate;
      Adaptive : Boolean;
      K        : out Level_Index;
      X, Y     : out P.Position;
      Theta    : out P.Zone_Angle_Value;
      Scale    : out P.Scale_Value;
      M        : out RF.Measures;
      Score    : out P.Fraction;
      Done     : out Boolean;
      Status   : out Ks_Status)
   with Pre  => Trained_Pattern (Pattern) and then Valid_Run_Params (Params),
        Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Out_Of_Memory;
   --  PatMax's last stage for the candidate C: the refinement and the
   --  measures at C's level; with the automatic grain (Adaptive), again
   --  one level coarser while the score misses AcceptThreshold and that
   --  level is Eligible. Done when a level was usable (the pose, measures
   --  and score are then those of level K).

   procedure Finish_PatMax
     (Pattern  : access constant Ks_PM_Align_Pattern_Data;
      F        : P.Frame;
      Pyr      : PY.Pyramid;
      Region   : access constant KR.Ks_Pixel_Region_Data;
      Params   : Ks_PM_Align_Run_Params;
      C        : SR.Candidate;
      Adaptive : Boolean;
      K        : out Level_Index;
      X, Y     : out P.Position;
      Theta    : out P.Zone_Angle_Value;
      Scale    : out P.Scale_Value;
      M        : out RF.Measures;
      Score    : out P.Fraction;
      Done     : out Boolean;
      Status   : out Ks_Status)
   is
   begin
      K := C.Level;
      X := C.X;
      Y := C.Y;
      Theta := C.Theta;
      Scale := C.Scale;
      M := (others => <>);
      Score := 0.0;
      Done := False;
      Set_Success (Status);
      loop
         pragma Loop_Invariant (Valid (Status) and then Succeeded (Status));
         exit when K >= Pyr.Count
           or else not PY.Usable (Pyr.Levels (K))
           or else (Adaptive and then not Eligible (Pattern, K));
         X := P.To_Level (P.From_Level (C.X, C.Level), K);
         Y := P.To_Level (P.From_Level (C.Y, C.Level), K);
         Theta := C.Theta;
         Scale := C.Scale;
         RF.Refine (Pattern.Levels (K), F, Pyr.Levels (K), K, Params, X, Y,
                    Theta, Scale);
         RF.Measure (Pattern.Levels (K), F, Pyr.Levels (K), K, Region,
                     Pyr.Area, Params, X, Y, Theta, Scale, M, Status);
         if not Succeeded (Status) then
            Done := False;
            return;
         end if;
         Done := True;
         Score :=
           (if Params.Score_Using_Clutter = True_Value
            then N.Clamp_Unit (N.Times_Unit (M.Coverage, 1.0 - M.Clutter))
            else M.Coverage);
         exit when not Adaptive
           or else Score >= Params.Accept_Threshold
           or else K >= Pattern.Coarsest
           or else K = Level_Index'Last;
         K := K + 1;
      end loop;
   end Finish_PatMax;

   procedure Finish
     (Pattern   : access constant Ks_PM_Align_Pattern_Data;
      F         : P.Frame;
      Pyr       : PY.Pyramid;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Params    : Ks_PM_Align_Run_Params;
      Pat_Max   : Boolean;
      List      : SR.Candidate_List;
      Finals    : out Final_List;
      Status    : out Ks_Status)
   with Pre  => Trained_Pattern (Pattern) and then Valid_Run_Params (Params),
        Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Out_Of_Memory;
   --  The last stage of every candidate (PatMax: refinement and measures;
   --  PatQuick: interpolation), sorted by score and selected.

   procedure Finish
     (Pattern   : access constant Ks_PM_Align_Pattern_Data;
      F         : P.Frame;
      Pyr       : PY.Pyramid;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Params    : Ks_PM_Align_Run_Params;
      Pat_Max   : Boolean;
      List      : SR.Candidate_List;
      Finals    : out Final_List;
      Status    : out Ks_Status)
   is
      Adaptive : constant Boolean :=
        Pattern.Params.Grain_Limit_Auto_Select = True_Value;
   begin
      Finals := (Count => 0, Items => [others => (others => <>)]);
      Set_Success (Status);
      for I in 0 .. List.Count - 1 loop
         pragma Loop_Invariant
           (Finals.Count <= I and then Valid (Status)
            and then Succeeded (Status));
         declare
            C        : SR.Candidate := List.Items (I);
            K        : Level_Index := C.Level;
            X        : P.Position := C.X;
            Y        : P.Position := C.Y;
            Theta    : P.Zone_Angle_Value := C.Theta;
            Scale    : P.Scale_Value := C.Scale;
            M        : RF.Measures;
            Score    : P.Fraction := 0.0;
            Usable   : Boolean := False;
         begin
            if Pat_Max then
               Finish_PatMax (Pattern, F, Pyr, Region, Params, C, Adaptive,
                              K, X, Y, Theta, Scale, M, Score, Usable,
                              Status);
               if not Succeeded (Status) then
                  return;
               end if;
            elsif K < Pyr.Count and then PY.Usable (Pyr.Levels (K)) then
               SR.Interpolate (Pattern, F, Pyr, Params, C);
               X := C.X;
               Y := C.Y;
               Theta := C.Theta;
               Scale := C.Scale;
               RF.Measure (Pattern.Levels (K), F, Pyr.Levels (K), K, Region,
                           Pyr.Area,
                           (Params with delta Score_Using_Clutter =>
                                                False_Value),
                           X, Y, Theta, Scale, M, Status);
               if not Succeeded (Status) then
                  return;
               end if;
               Usable := True;
               M := (Coverage => C.Score, Clutter => 0.0,
                     Outside => M.Outside, Fit_Error => 0.0,
                     Contrast => 0.0);
               Score := C.Score;
            end if;
            if Usable then
               Finals.Items (Finals.Count) :=
                 (X          => P.From_Level (X, K),
                  Y          => P.From_Level (Y, K),
                  Theta      => Theta,
                  Scale      => Scale,
                  Score      => Score,
                  Measures   => M,
                  Separation => P.Pixel_Radius_Of (F, Scale, 0) / 2.0
                                + 0.5,
                  Fine       => Pat_Max,
                  Kept       => False,
                  Level      => K);
               Finals.Count := Finals.Count + 1;
            end if;
         end;
      end loop;
      if Adaptive then
         One_Level (Finals, Params);
      end if;
      Sort_Finals (Finals);
      Select_Finals (Finals, Pattern, F, Params);
   end Finish;

   procedure Locate
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Pixel_From_Selected : KT.Ks_Transform_2D_Linear;
      Pattern             : access constant Ks_PM_Align_Pattern_Data;
      Params              : Ks_PM_Align_Run_Params;
      Pat_Max             : Boolean;
      Results             : Ks_PM_Align_Results;
      Pyr                 : in out PY.Pyramid;
      Status              : out Ks_Status)
   with
     Pre  => Trained_Pattern (Pattern) and then Valid_Run_Params (Params)
             and then KI.Valid_Image (Image) and then Region /= null
             and then KR.In_Image (Region, Image.Width, Image.Height)
             and then KT.Bounded (Selected_From_Pixel)
             and then KT.Bounded (Pixel_From_Selected)
             and then Results /= null and then Results.Count = 0,
     Post => PY.Released (Pyr)
             and then Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Gold_Results (Results, Params));
   --  The search proper (see Execute), with Pyr the pyramid of the input
   --  image (released when the call returns).

   procedure Locate
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Pixel_From_Selected : KT.Ks_Transform_2D_Linear;
      Pattern             : access constant Ks_PM_Align_Pattern_Data;
      Params              : Ks_PM_Align_Run_Params;
      Pat_Max             : Boolean;
      Results             : Ks_PM_Align_Results;
      Pyr                 : in out PY.Pyramid;
      Status              : out Ks_Status)
   is
      Top       : constant Level_Index :=
        Level_Index'Max (Pattern.Finest, Pattern.Coarsest);
      Area      : constant PY.Window :=
        Window_Around (Region, Image, Margin_For (Top));
      Threshold : constant P.Fraction :=
        (if Params.Coarse_Accept_Threshold_Enabled = True_Value
         then Params.Coarse_Accept_Threshold
         else Coarse_Factor * Params.Accept_Threshold);
      F         : P.Frame;
      List      : SR.Candidate_List;
      Finals    : Final_List;
   begin
      --  The frame of the run.
      F.L := P.Linear_Of (Pixel_From_Selected);
      F.N := P.Normal_Map (F.L);
      P.Largest_Stretch (F.L, F.Sigma, F.Lambda);
      P.Centroid (Pattern.Levels (Pattern.Finest), F.Centroid_X,
                  F.Centroid_Y);
      F.Radius := P.Pattern_Radius (Pattern.Levels (Pattern.Finest),
                                    F.Centroid_X, F.Centroid_Y);
      F.Ignore_Polarity := Pattern.Params.Ignore_Polarity = True_Value;

      PY.Build (Image, Region, Area, Top + 1, True,
                Params.Contrast_Threshold, Pyr, Status);
      if Succeeded (Status) then
         SR.Coarse (Pattern, F, Pyr, Params, Threshold, List, Status);
      end if;
      if Succeeded (Status) then
         SR.Track (Pattern, F, Pyr, Params, Threshold,
                   Natural'Min (Max_Candidates,
                                Natural'Max
                                  (Tracked_Candidates,
                                   2 * Natural
                                         (Params
                                            .Approximate_Number_To_Find))),
                   List);
         Finish (Pattern, F, Pyr, Region, Params, Pat_Max, List, Finals,
                 Status);
      end if;
      PY.Release (Pyr);
      if Succeeded (Status) then
         Build_Results (Finals, Area, Selected_From_Pixel, F, Params,
                        Results);
      end if;
   end Locate;

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Pattern             : access constant Ks_PM_Align_Pattern_Data;
      Params              : Ks_PM_Align_Run_Params;
      Results             : out Ks_PM_Align_Results;
      Status              : out Ks_Status)
   is
      Pixel_From_Selected : KT.Ks_Transform_2D_Linear;
      S              : Ks_Status;
      Unused_Pyramid : PY.Pyramid;
   begin
      Results := null;
      if not Trained_Pattern (Pattern) then
         Not_Trained (Status);
         return;
      end if;
      Check_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      elsif Resolved_Algorithm (Params, Pattern) = Run_Algorithm_Pat_Max
        and then Pattern.Params.Train_Algorithm = Train_Algorithm_Pat_Quick
      then
         Set_Failure (Status, Failure_Operator_Not_Trained,
                      "Pattern is not trained for PatMax");
         return;
      elsif Resolved_Algorithm (Params, Pattern) = Run_Algorithm_Pat_Quick
        and then Pattern.Params.Train_Algorithm = Train_Algorithm_Pat_Max
      then
         Set_Failure (Status, Failure_Operator_Not_Trained,
                      "Pattern is not trained for PatQuick");
         return;
      end if;
      FI.Check_Image (Image, Status);
      if not Succeeded (Status) then
         return;
      elsif Region /= null
        and then (not KR.Valid_Region (Region)
                  or else not KR.In_Image (Region, Image.Width, Image.Height))
      then
         Bad (Status, "SearchRegion is not a valid pixel region of"
                      & " InputImage");
         return;
      elsif not KT.Bounded (Selected_From_Pixel) then
         Bad (Status, "InputImage's selected space transform must be finite"
                      & " and within +/-1.0E150");
         return;
      end if;
      KT.Invert (Selected_From_Pixel, Pixel_From_Selected, S);
      if not Succeeded (S) then
         Set_Failure (Status, Failure_Transform_Singular,
                      "InputImage's selected space has no inverse within"
                      & " +/-1.0E150");
         return;
      end if;

      Allocate_Results (Results);
      if Results = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "PMAlign: out of memory");
         return;
      elsif Region = null then
         --  The empty search region: no results.
         Set_Success (Status);
         return;
      end if;
      Locate (Image, Region, Selected_From_Pixel, Pixel_From_Selected,
              Pattern, Params,
              Resolved_Algorithm (Params, Pattern) = Run_Algorithm_Pat_Max,
              Results, Unused_Pyramid, Status);
      if not Succeeded (Status) then
         Results_Destroy (Results);
      end if;
   end Execute;

   procedure Results_Destroy (Results : in out Ks_PM_Align_Results) is
   begin
      if Results /= null then
         Free (Results);
      end if;
   end Results_Destroy;

   procedure Results_Count
     (Results : access constant Ks_PM_Align_Results_Data;
      Count   : out Int32;
      Status  : out Ks_Status) is
   begin
      Count := (if Results = null then 0 else Int32 (Results.Count));
      Set_Success (Status);
   end Results_Count;

   procedure Results_Item
     (Results : access constant Ks_PM_Align_Results_Data;
      Index   : Int32;
      Item    : out Ks_PM_Align_Result;
      Status  : out Ks_Status) is
   begin
      Item := (others => <>);
      if Results = null or else Index < 0
        or else Index >= Int32 (Results.Count)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "PMAlignResults: index outside 0 .. Count - 1");
         return;
      end if;
      Item := Results.Items (Natural (Index));
      Set_Success (Status);
   end Results_Item;

   procedure Result_Get_Pose
     (Item   : Ks_PM_Align_Result;
      Pose   : out KT.Ks_Transform_2D_Linear;
      Status : out Ks_Status) is
   begin
      KT.Create_Similarity (Item.Scaling, Item.Rotation, Item.Translation_X,
                            Item.Translation_Y, Pose, Status);
   end Result_Get_Pose;

   ---------------------------------------------------------------------
   --  Ada-only helpers
   ---------------------------------------------------------------------

   procedure Get_Features
     (Pattern  : access constant Ks_PM_Align_Pattern_Data;
      Level    : Int32;
      Features : out Ks_PM_Align_Feature_Array;
      Status   : out Ks_Status)
   is
      Count : Int32;
   begin
      Features := [others => (others => 0.0)];
      Pattern_Feature_Count (Pattern, Level, Count, Status);
      if not Succeeded (Status) then
         return;
      elsif Int64 (Features'Length) /= Int64 (Count) then
         Bad (Status, "Get_Features: the array must have one element per"
                      & " feature");
         return;
      end if;
      for I in 0 .. Natural (Count) - 1 loop
         declare
            F : constant Model_Feature :=
              Pattern.Levels (Natural (Level)).Features (I);
         begin
            Features (Features'First + I) :=
              (X => F.X, Y => F.Y, Normal_X => F.NX, Normal_Y => F.NY);
         end;
      end loop;
   end Get_Features;

   procedure Check_Train_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      if Image = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "TrainImage has no pixels");
      elsif not FI.Usable_Image (Image) then
         Bad (Status, "TrainImage is not a valid image handle");
      else
         Set_Success (Status);
      end if;
   end Check_Train_Image;

   procedure Check_Inputs
     (Image   : access constant KI.Ks_Image_8_Grey_Data;
      Pattern : access constant Ks_PM_Align_Pattern_Data;
      Params  : Ks_PM_Align_Run_Params;
      Status  : out Ks_Status)
   is
      Algorithm : Int32;
   begin
      if not Trained_Pattern (Pattern) then
         Not_Trained (Status);
         return;
      end if;
      Check_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Algorithm := Resolved_Algorithm (Params, Pattern);
      if Algorithm = Run_Algorithm_Pat_Max
        and then Pattern.Params.Train_Algorithm = Train_Algorithm_Pat_Quick
      then
         Set_Failure (Status, Failure_Operator_Not_Trained,
                      "Pattern is not trained for PatMax");
      elsif Algorithm = Run_Algorithm_Pat_Quick
        and then Pattern.Params.Train_Algorithm = Train_Algorithm_Pat_Max
      then
         Set_Failure (Status, Failure_Operator_Not_Trained,
                      "Pattern is not trained for PatQuick");
      else
         FI.Check_Image (Image, Status);
      end if;
   end Check_Inputs;

   procedure Write_Levels
     (Pattern          : access constant Ks_PM_Align_Pattern_Data;
      Trained          : out Int32;
      Finest, Coarsest : out Int32;
      First, Last      : out Int32;
      Status           : out Ks_Status) is
   begin
      Trained := False_Value;
      Finest := 0;
      Coarsest := 0;
      First := 0;
      Last := -1;
      if Trained_Pattern (Pattern) then
         Trained := True_Value;
         Finest := Int32 (Pattern.Finest);
         Coarsest :=
           Int32 (Level_Index'Max (Pattern.Finest, Pattern.Coarsest));
         First := Finest;
         Last := Coarsest;
      end if;
      Set_Success (Status);
   end Write_Levels;

   procedure Check_Read_Code
     (Code   : Interfaces.Unsigned_32;
      Status : out Ks_Status) is
   begin
      if Code /= Stream_Code and then Code /= Stream_Code_Masked then
         Stream_Failure (Status, "the format code is not that of a"
                                 & " pattern");
      else
         Set_Success (Status);
      end if;
   end Check_Read_Code;

   procedure Read_Start
     (Pattern          : Ks_PM_Align_Pattern;
      Params           : Ks_PM_Align_Train_Params;
      Trained          : Int32;
      Finest, Coarsest : Int32;
      First, Last      : out Int32;
      Status           : out Ks_Status)
   is
      S : Ks_Status;
   begin
      First := 0;
      Last := -1;
      if Pattern = null then
         Stream_Failure (Status, "no pattern handle");
         return;
      end if;
      Clear_Model (Pattern);
      Check_Train_Params (Params, S);
      if not Succeeded (S) then
         Stream_Failure (Status, "the train parameters are not valid");
      elsif Trained not in False_Value | True_Value then
         Stream_Failure (Status, "the trained flag is not 0 or 1");
      elsif Trained = True_Value
        and then (Finest not in 0 .. Max_Levels - 1
                  or else Coarsest not in Finest .. Max_Levels - 1)
      then
         Stream_Failure (Status, "the levels are not valid");
      else
         Pattern.Params := Params;
         if Trained = True_Value then
            Pattern.Finest := Natural (Finest);
            Pattern.Coarsest := Natural (Coarsest);
            First := Finest;
            Last := Coarsest;
         end if;
         Set_Success (Status);
      end if;
   end Read_Start;

   procedure Read_Feature
     (Pattern        : Ks_PM_Align_Pattern;
      Level          : Int32;
      X, Y, NX, NY   : Long_Float;
      Status         : out Ks_Status) is
   begin
      if Pattern = null or else Pattern.Trained then
         Stream_Failure (Status, "no model being read");
      elsif Level not in 0 .. Max_Levels - 1
        or else Natural (Level) not in Pattern.Finest .. Pattern.Coarsest
      then
         Stream_Failure (Status, "a level is not valid");
      elsif Pattern.Levels (Natural (Level)).Count = Max_Features then
         Stream_Failure (Status, "too many features");
      elsif not (X >= -Max_Pattern_Coordinate
                 and then X <= Max_Pattern_Coordinate
                 and then Y >= -Max_Pattern_Coordinate
                 and then Y <= Max_Pattern_Coordinate)
      then
         Stream_Failure (Status, "a feature lies beyond +/-1.0E9");
      elsif not (NX >= -1.0 and then NX <= 1.0
                 and then NY >= -1.0 and then NY <= 1.0)
      then
         Stream_Failure (Status, "a normal is not within [-1, 1]");
      else
         declare
            Model : Model_Level renames Pattern.Levels (Natural (Level));
         begin
            Model.Features (Model.Count) := (X => X, Y => Y, NX => NX,
                                             NY => NY);
            Model.Count := Model.Count + 1;
         end;
         Set_Success (Status);
      end if;
   end Read_Feature;

   procedure Read_Finish
     (Pattern : Ks_PM_Align_Pattern;
      Trained : Int32;
      Status  : out Ks_Status) is
   begin
      if Pattern = null or else Pattern.Trained then
         Stream_Failure (Status, "no model being read");
         return;
      elsif Trained /= True_Value then
         Set_Success (Status);
         return;
      end if;
      for K in Pattern.Finest .. Pattern.Coarsest loop
         if Pattern.Levels (K).Count < Min_Features then
            Stream_Failure (Status, "a level has too few features");
            return;
         end if;
      end loop;
      Pattern.Trained := True;
      Set_Success (Status);
   end Read_Finish;

   procedure Level_Spacing
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Level   : Int32;
      Spacing : out Interfaces.Unsigned_32;
      Status  : out Ks_Status) is
   begin
      Spacing := 1;
      if not Trained_Pattern (Pattern) then
         Not_Trained (Status);
      elsif Level not in 0 .. Max_Levels - 1 then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "PMAlignPattern: level outside 0 .. 5");
      else
         Spacing :=
           Interfaces.Unsigned_32 (Pattern.Levels (Natural (Level)).Spacing);
         Set_Success (Status);
      end if;
   end Level_Spacing;

   procedure Read_Spacing
     (Pattern : Ks_PM_Align_Pattern;
      Level   : Int32;
      Spacing : Interfaces.Unsigned_32;
      Status  : out Ks_Status) is
   begin
      if Pattern = null or else Pattern.Trained then
         Stream_Failure (Status, "no model being read");
      elsif Level not in 0 .. Max_Levels - 1
        or else Natural (Level) not in Pattern.Finest .. Pattern.Coarsest
      then
         Stream_Failure (Status, "a level is not valid");
      elsif Spacing < 1 or else Spacing > Max_Spacing then
         Stream_Failure (Status, "the spacing of a level is not in 1 .. 16");
      else
         Pattern.Levels (Natural (Level)).Spacing := Spacing_Value (Spacing);
         Set_Success (Status);
      end if;
   end Read_Spacing;

   procedure Check_Read_Count
     (Count  : Interfaces.Unsigned_32;
      Status : out Ks_Status) is
   begin
      if Count < Min_Features or else Count > Max_Features then
         Stream_Failure (Status, "the number of features of a level is not"
                                 & " in 8 .. 2048");
      else
         Set_Success (Status);
      end if;
   end Check_Read_Count;

   procedure Level_Ignored
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Level   : Int32;
      Spacing : out Interfaces.Unsigned_32;
      Count   : out Int32;
      Status  : out Ks_Status) is
   begin
      Spacing := 1;
      Count := 0;
      if not Trained_Pattern (Pattern) then
         Not_Trained (Status);
      elsif Level not in 0 .. Max_Levels - 1 then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "PMAlignPattern: level outside 0 .. 5");
      else
         Spacing := Interfaces.Unsigned_32
           (Pattern.Levels (Natural (Level)).Ignored_Spacing);
         Count := Int32 (Pattern.Levels (Natural (Level)).Ignored_Count);
         Set_Success (Status);
      end if;
   end Level_Ignored;

   procedure Pattern_Ignored_Point
     (Pattern : access constant Ks_PM_Align_Pattern_Data;
      Level   : Int32;
      Index   : Int32;
      X, Y    : out Long_Float;
      Status  : out Ks_Status) is
   begin
      X := 0.0;
      Y := 0.0;
      if not Trained_Pattern (Pattern) then
         Not_Trained (Status);
      elsif Level not in 0 .. Max_Levels - 1 then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "PMAlignPattern: level outside 0 .. 5");
      elsif Index < 0
        or else Index >= Int32 (Pattern.Levels (Natural (Level)).Ignored_Count)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "PMAlignPattern: ignored point index out of range");
      else
         X := Pattern.Levels (Natural (Level)).Ignored (Natural (Index)).X;
         Y := Pattern.Levels (Natural (Level)).Ignored (Natural (Index)).Y;
         Set_Success (Status);
      end if;
   end Pattern_Ignored_Point;

   procedure Read_Ignored_Spacing
     (Pattern : Ks_PM_Align_Pattern;
      Level   : Int32;
      Spacing : Interfaces.Unsigned_32;
      Status  : out Ks_Status) is
   begin
      if Pattern = null or else Pattern.Trained then
         Stream_Failure (Status, "no model being read");
      elsif Level not in 0 .. Max_Levels - 1
        or else Natural (Level) not in Pattern.Finest .. Pattern.Coarsest
      then
         Stream_Failure (Status, "a level is not valid");
      elsif Spacing < 1 or else Spacing > Max_Ignored_Spacing then
         Stream_Failure (Status, "the spacing of the ignored points of a"
                                 & " level is not in 1 .. 64");
      else
         Pattern.Levels (Natural (Level)).Ignored_Spacing :=
           Ignored_Spacing_Value (Spacing);
         Set_Success (Status);
      end if;
   end Read_Ignored_Spacing;

   procedure Check_Read_Ignored_Count
     (Count  : Interfaces.Unsigned_32;
      Status : out Ks_Status) is
   begin
      if Count > Max_Features then
         Stream_Failure (Status, "the number of ignored points of a level is"
                                 & " not in 0 .. 2048");
      else
         Set_Success (Status);
      end if;
   end Check_Read_Ignored_Count;

   procedure Read_Ignored
     (Pattern : Ks_PM_Align_Pattern;
      Level   : Int32;
      X, Y    : Long_Float;
      Status  : out Ks_Status) is
   begin
      if Pattern = null or else Pattern.Trained then
         Stream_Failure (Status, "no model being read");
      elsif Level not in 0 .. Max_Levels - 1
        or else Natural (Level) not in Pattern.Finest .. Pattern.Coarsest
      then
         Stream_Failure (Status, "a level is not valid");
      elsif Pattern.Levels (Natural (Level)).Ignored_Count = Max_Features then
         Stream_Failure (Status, "too many ignored points");
      elsif not (X >= -Max_Pattern_Coordinate
                 and then X <= Max_Pattern_Coordinate
                 and then Y >= -Max_Pattern_Coordinate
                 and then Y <= Max_Pattern_Coordinate)
      then
         Stream_Failure (Status, "an ignored point lies beyond +/-1.0E9");
      else
         declare
            Model : Model_Level renames Pattern.Levels (Natural (Level));
         begin
            Model.Ignored (Model.Ignored_Count) := (X => X, Y => Y);
            Model.Ignored_Count := Model.Ignored_Count + 1;
         end;
         Set_Success (Status);
      end if;
   end Read_Ignored;

end AMV.Kernels.PM_Align;
