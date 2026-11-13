pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;

with AMV.Kernels.Geometry;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Find_Line with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;
   package KG renames AMV.Kernels.Geometry;
   package EF renames Ada.Numerics.Long_Elementary_Functions;

   procedure Free is new Ada.Unchecked_Deallocation
     (Item_Array, Item_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Caliper_Array, Caliper_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Find_Line_Results_Data, Ks_Find_Line_Results);

   No_Item : constant Ks_Find_Line_Result := (others => <>);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Items
     (Count : Positive;
      Items : out Item_Array_Access)
   with
     Global => null,
     Post   => (if Items /= null
                then Items'First = 0 and then Items'Last = Count - 1
                     and then (for all I in Items'Range =>
                                 Items (I) = No_Item));
   --  A new array of Count items with the record's default values, or
   --  null when the memory cannot be allocated. Trusted: the allocator
   --  raises Storage_Error, which SPARK cannot express.

   procedure Allocate_Items
     (Count : Positive;
      Items : out Item_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Items := new Item_Array (0 .. Count - 1);
   exception
      when Storage_Error =>
         Items := null;
   end Allocate_Items;

   procedure Allocate_Calipers
     (Count    : Positive;
      Calipers : out Caliper_Array_Access)
   with
     Global => null,
     Post   => (if Calipers /= null
                then Calipers'First = 0 and then Calipers'Last = Count - 1
                     and then (for all I in Calipers'Range =>
                                 Calipers (I) = null));
   --  A new array of Count null handles, or null. Trusted as above.

   procedure Allocate_Calipers
     (Count    : Positive;
      Calipers : out Caliper_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Calipers := new Caliper_Array (0 .. Count - 1);
   exception
      when Storage_Error =>
         Calipers := null;
   end Allocate_Calipers;

   procedure Allocate_Results (Results : out Ks_Find_Line_Results)
   with
     Global => null,
     Post   => (if Results /= null
                then Results.Items = null and then Results.Calipers = null);
   --  A new results record with the record's default values, or null.
   --  Trusted as above.

   procedure Allocate_Results (Results : out Ks_Find_Line_Results)
     with SPARK_Mode => Off
   is
   begin
      Results := new Ks_Find_Line_Results_Data;
   exception
      when Storage_Error =>
         Results := null;
   end Allocate_Results;

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   function Image_Of (Value : Int64) return String
   with Pre  => Value >= 0,
        Post => Image_Of'Result'First = 1
                and then Image_Of'Result'Length in 1 .. 20;
   --  The decimal digits of Value.

   function Image_Of (Value : Int64) return String is
      Text  : String (1 .. 20) := [others => '0'];
      Rest  : Int64 := Value;
      First : Positive;
   begin
      for K in reverse 1 .. 20 loop
         Text (K) := Character'Val (Character'Pos ('0') + Rest mod 10);
         Rest := Rest / 10;
         First := K;
         exit when Rest = 0;
         pragma Loop_Invariant (First = K and then Rest >= 1);
      end loop;
      declare
         Last   : constant Natural := 21 - First;
         Result : constant String (1 .. Last) := Text (First .. 20);
      begin
         return Result;
      end;
   end Image_Of;

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

   function In_Bound (X : Long_Float) return Boolean is
     (X >= -Max_Value and then X <= Max_Value);

   subtype Coordinate is Long_Float range -Max_Value .. Max_Value;

   function Read (X : Long_Float) return Coordinate is
     (N.Clamp (X, Max_Value));
   --  A point coordinate limited to the bound: every point the kernel
   --  stores comes from a caliper result, which is within it, so the limit
   --  never changes a value (docs/PROOF.md).

   function Segment_DX (P : Ks_Find_Line_Run_Params) return Long_Float is
     (P.Expected_Line_Segment.End_X - P.Expected_Line_Segment.Start_X)
   with Pre => KS.Valid_Line_Segment (P.Expected_Line_Segment);

   function Segment_DY (P : Ks_Find_Line_Run_Params) return Long_Float is
     (P.Expected_Line_Segment.End_Y - P.Expected_Line_Segment.Start_Y)
   with Pre => KS.Valid_Line_Segment (P.Expected_Line_Segment);

   function Valid_Params (P : Ks_Find_Line_Run_Params) return Boolean is
     (P.Num_Calipers in 2 .. Max_Calipers
      and then P.Num_To_Ignore in 0 .. P.Num_Calipers - 2
      and then P.Decrement_Num_To_Ignore in False_Value | True_Value
      and then KS.Valid_Line_Segment (P.Expected_Line_Segment)
      and then (Segment_DX (P) /= 0.0 or else Segment_DY (P) /= 0.0)
      and then P.Caliper_Search_Length > 0.0
      and then P.Caliper_Search_Length <= KS.Max_Length
      and then P.Caliper_Projection_Length > 0.0
      and then P.Caliper_Projection_Length <= KS.Max_Length
      and then In_Bound (P.Caliper_Search_Direction));

   procedure Check_Params
     (Params : Ks_Find_Line_Run_Params;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Valid_Params (Params));

   procedure Check_Params
     (Params : Ks_Find_Line_Run_Params;
      Status : out Ks_Status) is
   begin
      if Params.Num_Calipers not in 2 .. Max_Calipers then
         Bad (Status, "RunParams.NumCalipers must be in 2 .. 1000");
      elsif Params.Num_To_Ignore not in 0 .. Params.Num_Calipers - 2 then
         Bad (Status, "RunParams.NumToIgnore must be in 0 .."
                      & " NumCalipers - 2");
      elsif Params.Decrement_Num_To_Ignore not in False_Value | True_Value
      then
         Bad (Status, "RunParams.DecrementNumToIgnore must be 0 or 1");
      elsif not KS.Valid_Line_Segment (Params.Expected_Line_Segment) then
         Bad (Status, "RunParams.ExpectedLineSegment: the end points must be"
                      & " finite and within +/-1.0E150");
      elsif Segment_DX (Params) = 0.0 and then Segment_DY (Params) = 0.0
      then
         Bad (Status, "RunParams.ExpectedLineSegment must have a length"
                      & " > 0");
      elsif not (Params.Caliper_Search_Length > 0.0
                 and then Params.Caliper_Search_Length <= KS.Max_Length)
      then
         Bad (Status, "RunParams.CaliperSearchLength must be > 0 and"
                      & " <= 4.0E150");
      elsif not (Params.Caliper_Projection_Length > 0.0
                 and then Params.Caliper_Projection_Length <= KS.Max_Length)
      then
         Bad (Status, "RunParams.CaliperProjectionLength must be > 0 and"
                      & " <= 4.0E150");
      elsif not In_Bound (Params.Caliper_Search_Direction) then
         Bad (Status, "RunParams.CaliperSearchDirection must be finite and"
                      & " within +/-1.0E150");
      else
         KC.Check_Nested_Run_Params (Params.Caliper_Run_Params, Status);
      end if;
   end Check_Params;

   procedure Region_Of
     (Params : Ks_Find_Line_Run_Params;
      K      : Natural;
      Region : out KS.Ks_Rectangle_Affine)
   with
     Pre  => Valid_Params (Params)
             and then K < Natural (Params.Num_Calipers),
     Post => KS.Valid_Rectangle_Affine (Region);
   --  The region of caliper K.

   procedure Region_Of
     (Params : Ks_Find_Line_Run_Params;
      K      : Natural;
      Region : out KS.Ks_Rectangle_Affine)
   is
      S   : KS.Ks_Line_Segment renames Params.Expected_Line_Segment;
      DX  : constant Long_Float := Segment_DX (Params);
      DY  : constant Long_Float := Segment_DY (Params);
      F   : constant Long_Float :=
        N.Unit_Ratio (Long_Float (K), Long_Float (Params.Num_Calipers - 1));
      Phi : constant Long_Float := N.Direction (DY, DX);
   begin
      --  The centre lies on the segment, so within the bound; the limit
      --  can act only by rounding at the very bound.
      Region :=
        (Center_X      => N.Clamp (S.Start_X + N.Times_Unit (DX, F),
                                   Max_Value),
         Center_Y      => N.Clamp (S.Start_Y + N.Times_Unit (DY, F),
                                   Max_Value),
         Side_X_Length => Params.Caliper_Search_Length,
         Side_Y_Length => Params.Caliper_Projection_Length,
         Rotation      =>
           N.Reduce_Two_Pi (Phi + Params.Caliper_Search_Direction),
         Skew          => 0.0);
   end Region_Of;

   function Directed_Line
     (Fitted : KG.Ks_Line_2D;
      Points : KG.Point_Array;
      Used   : KG.Flag_Array;
      Found  : Natural) return KS.Ks_Line
   with
     Pre  => KG.Bounded (Fitted.X) and then KG.Bounded (Fitted.Y)
             and then Fitted.Rotation > -N.Pi
             and then Fitted.Rotation <= N.Pi
             and then Points'First = 0 and then Used'First = 0
             and then Found <= Max_Calipers
             and then Found - 1 <= Points'Last
             and then Found - 1 <= Used'Last,
     Post => KS.Valid_Line (Directed_Line'Result);
   --  The fitted line, turned by Pi when its direction points against the
   --  direction from the first to the last used point (in caliper order).

   function Directed_Line
     (Fitted : KG.Ks_Line_2D;
      Points : KG.Point_Array;
      Used   : KG.Flag_Array;
      Found  : Natural) return KS.Ks_Line
   is
      First, Last : Integer := -1;
      Dir_X       : Long_Float;
      Dir_Y       : Long_Float;
      Rotation    : Long_Float := Fitted.Rotation;
   begin
      for J in 0 .. Found - 1 loop
         pragma Loop_Invariant
           (First in -1 .. J - 1 and then Last in -1 .. J - 1
            and then (if First = -1 then Last = -1));
         if Used (J) then
            if First = -1 then
               First := J;
            end if;
            Last := J;
         end if;
      end loop;
      if First >= 0 and then Last >= 0 then
         Dir_X := Read (Points (Last).X) - Read (Points (First).X);
         Dir_Y := Read (Points (Last).Y) - Read (Points (First).Y);
         if N.Times_Unit (Dir_X, N.Clamp (EF.Cos (Rotation), 1.0))
            + N.Times_Unit (Dir_Y, N.Clamp (EF.Sin (Rotation), 1.0)) < 0.0
         then
            Rotation := Rotation + N.Pi;
         end if;
      end if;
      return (X => Fitted.X, Y => Fitted.Y,
              Rotation => N.Reduce_Two_Pi (Rotation));
   end Directed_Line;

   procedure Extreme_Segment
     (Line    : KS.Ks_Line;
      Points  : KG.Point_Array;
      Used    : KG.Flag_Array;
      Found   : Natural;
      Segment : out KS.Ks_Line_Segment;
      Fits    : out Boolean)
   with
     Pre  => KS.Valid_Line (Line)
             and then Points'First = 0 and then Used'First = 0
             and then Found <= Max_Calipers
             and then Found - 1 <= Points'Last
             and then Found - 1 <= Used'Last,
     Post => KS.Valid_Line_Segment (Segment);
   --  The part of Line between the projections of the used points that lie
   --  furthest back and furthest ahead along it; Fits is False when a
   --  projection would exceed 1.0E150 (Segment is then all 0).

   procedure Extreme_Segment
     (Line    : KS.Ks_Line;
      Points  : KG.Point_Array;
      Used    : KG.Flag_Array;
      Found   : Natural;
      Segment : out KS.Ks_Line_Segment;
      Fits    : out Boolean)
   is
      Line_2D   : constant KG.Ks_Line_2D :=
        (X => Line.X, Y => Line.Y, Rotation => Line.Rotation);
      Along     : Long_Float;
      Low, High : Long_Float := 0.0;
      Low_J     : Integer := -1;
      High_J    : Integer := -1;
      S         : Ks_Status;
      P, Q      : KG.Ks_Point_2D;
   begin
      Segment := (others => 0.0);
      Fits := True;
      for J in 0 .. Found - 1 loop
         pragma Loop_Invariant
           (Low_J in -1 .. J - 1 and then High_J in -1 .. J - 1
            and then (Low_J = -1) = (High_J = -1));
         if Used (J) then
            KG.Position_Along
              ((Read (Points (J).X), Read (Points (J).Y)), Line_2D, Along, S);
            if Succeeded (S) then
               if Low_J = -1 or else Along < Low then
                  Low := Along;
                  Low_J := J;
               end if;
               if High_J = -1 or else Along > High then
                  High := Along;
                  High_J := J;
               end if;
            end if;
         end if;
      end loop;
      if Low_J >= 0 and then High_J >= 0 then
         KG.Project
           ((Read (Points (Low_J).X), Read (Points (Low_J).Y)), Line_2D, P,
            S);
         if Succeeded (S) then
            KG.Project
              ((Read (Points (High_J).X), Read (Points (High_J).Y)), Line_2D,
               Q, S);
         end if;
         if Succeeded (S) then
            Segment := (P.X, P.Y, Q.X, Q.Y);
         else
            Fits := False;
         end if;
      end if;
   end Extreme_Segment;

   procedure Free_Calipers (Calipers : in out Caliper_Array_Access)
   with Post => Calipers = null;
   --  Frees every caliper's results and the array.

   procedure Free_Calipers (Calipers : in out Caliper_Array_Access) is
   begin
      if Calipers /= null then
         for I in Calipers'Range loop
            KC.Results_Destroy (Calipers (I));
            pragma Loop_Invariant
              (for all J in Calipers'First .. I => Calipers (J) = null);
         end loop;
         Free (Calipers);
      end if;
   end Free_Calipers;

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Run_Params_Default
     (Params : out Ks_Find_Line_Run_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Run_Params_Default;

   procedure Caliper_Region
     (Params : Ks_Find_Line_Run_Params;
      Index  : Int32;
      Region : out KS.Ks_Rectangle_Affine;
      Status : out Ks_Status) is
   begin
      Region := (others => <>);
      Check_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      elsif Index not in 0 .. Params.Num_Calipers - 1 then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "CaliperRegion: index outside 0 .. NumCalipers - 1");
         return;
      end if;
      Region_Of (Params, Natural (Index), Region);
   end Caliper_Region;

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Params              : Ks_Find_Line_Run_Params;
      Pixel_From_Segment  : KT.Ks_Transform_2D_Linear;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : out Ks_Find_Line_Results;
      Status              : out Ks_Status)
   is
      Count     : Natural;
      Points    : KG.Point_Array (0 .. Max_Calipers - 1) :=
        [others => (0.0, 0.0)];
      Index_Of  : array (0 .. Max_Calipers - 1) of Natural := [others => 0];
      Used      : KG.Flag_Array (0 .. Max_Calipers - 1) := [others => False];
      Found     : Natural := 0;
      Ignore    : Natural;
      Region    : KS.Ks_Rectangle_Affine;
      Caliper   : KC.Ks_Caliper_Results;
      Fitted    : KG.Ks_Line_2D;
      RMS       : Long_Float;
      Line      : KS.Ks_Line;
      Segment   : KS.Ks_Line_Segment;
      Num_Found : Natural;
      Num_Used  : Natural;
   begin
      Results := null;
      if Image = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "InputImage has no pixels");
         return;
      elsif not KI.Valid_Image (Image) then
         Bad (Status, "InputImage is not a valid image handle");
         return;
      end if;
      Check_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Pixel_From_Segment) then
         Bad (Status, "Pixel_From_Segment must be finite and within"
                      & " +/-1.0E150");
         return;
      elsif not KT.Bounded (Selected_From_Pixel) then
         Bad (Status, "Selected_From_Pixel must be finite and within"
                      & " +/-1.0E150");
         return;
      end if;
      Count := Natural (Params.Num_Calipers);

      --  The results are built in place; every failure below destroys
      --  them (and the calipers' results they hold).
      Allocate_Results (Results);
      if Results = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "FindLine: out of memory");
         return;
      end if;
      Allocate_Items (Count, Results.Items);
      Allocate_Calipers (Count, Results.Calipers);
      if Results.Items = null or else Results.Calipers = null then
         Results_Destroy (Results);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "FindLine: out of memory");
         return;
      end if;
      Results.Count := Count;

      --  Run the calipers.
      for K in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (Results /= null
            and then Results.Items /= null and then Results.Calipers /= null
            and then Results.Count = Count
            and then Results.Items'First = 0
            and then Results.Items'Last = Count - 1
            and then Results.Calipers'First = 0
            and then Results.Calipers'Last = Count - 1
            and then Found <= K and then Caliper = null
            and then (for all I in 0 .. K - 1 =>
                        Results.Calipers (I) /= null)
            and then (for all I in K .. Count - 1 =>
                        Results.Calipers (I) = null)
            and then (for all I in K .. Count - 1 =>
                        Results.Items (I) = No_Item)
            and then (for all I in 0 .. Count - 1 =>
                        Results.Items (I).Used = False_Value
                        and then Results.Items (I).Found
                                   in False_Value | True_Value
                        and then Results.Items (I).Distance_To_Line = 0.0)
            and then (for all J in 0 .. Found - 1 =>
                        Index_Of (J) < K
                        and then Results.Items (Index_Of (J)).Found
                                   = True_Value));
         Region_Of (Params, K, Region);
         KC.Execute (Image, Region, Pixel_From_Segment, Selected_From_Pixel,
                     Params.Caliper_Run_Params, Caliper, Status);
         if not Succeeded (Status) then
            Results_Destroy (Results);
            return;
         end if;
         if Caliper.Count > 0 then
            Results.Items (K).Found := True_Value;
            Results.Items (K).X := Caliper.Items (0).Position_X;
            Results.Items (K).Y := Caliper.Items (0).Position_Y;
            Points (Found) := (Caliper.Items (0).Position_X,
                               Caliper.Items (0).Position_Y);
            Index_Of (Found) := K;
            Found := Found + 1;
         end if;
         Results.Calipers (K) := Caliper;
         Caliper := null;
      end loop;

      --  Fit the line.
      Ignore := Natural (Params.Num_To_Ignore);
      if Found < Ignore + 2 then
         if Params.Decrement_Num_To_Ignore = True_Value and then Found >= 2
         then
            Ignore := Found - 2;
         else
            Results_Destroy (Results);
            Set_Failure
              (Status, Failure_Other,
               "FindLine: fewer than 2 points remain to fit (NumPointsFound"
               & " =" & " " & Image_Of (Int64 (Found)) & ", NumToIgnore ="
               & " " & Image_Of (Int64 (Params.Num_To_Ignore)) & ")");
            return;
         end if;
      end if;
      KG.Fit_Line_Robust
        (Points (0 .. Found - 1), Int32 (Ignore), Fitted, RMS,
         Used (0 .. Found - 1), Status);
      if not Succeeded (Status) then
         Results_Destroy (Results);
         return;
      end if;

      --  Mark the used items.
      for J in 0 .. Found - 1 loop
         pragma Loop_Invariant
           (Results /= null and then Results.Items /= null
            and then Results.Calipers /= null
            and then Results.Count = Count
            and then Results.Items'First = 0
            and then Results.Items'Last = Count - 1
            and then Results.Calipers'First = 0
            and then Results.Calipers'Last = Count - 1
            and then (for all I in 0 .. Count - 1 =>
                        Results.Calipers (I) /= null)
            and then (for all I in 0 .. Count - 1 =>
                        Results.Items (I).Found in False_Value | True_Value
                        and then Results.Items (I).Used
                                   in False_Value | True_Value
                        and then (if Results.Items (I).Used = True_Value
                                  then Results.Items (I).Found = True_Value)
                        and then Results.Items (I).Distance_To_Line = 0.0)
            and then (for all J2 in 0 .. Found - 1 =>
                        Index_Of (J2) < Count
                        and then Results.Items (Index_Of (J2)).Found
                                   = True_Value));
         if Used (J) then
            Results.Items (Index_Of (J)).Used := True_Value;
         end if;
      end loop;

      Line := Directed_Line (Fitted, Points, Used, Found);

      --  Distances from the line.
      declare
         Line_2D  : constant KG.Ks_Line_2D :=
           (X => Line.X, Y => Line.Y, Rotation => Line.Rotation);
         Distance : Long_Float;
         S        : Ks_Status;
      begin
         for J in 0 .. Found - 1 loop
            pragma Loop_Invariant
              (Results /= null and then Results.Items /= null
               and then Results.Calipers /= null
               and then Results.Count = Count
               and then Results.Items'First = 0
               and then Results.Items'Last = Count - 1
               and then Results.Calipers'First = 0
               and then Results.Calipers'Last = Count - 1
               and then (for all I in 0 .. Count - 1 =>
                           Results.Calipers (I) /= null)
               and then (for all I in 0 .. Count - 1 =>
                           Results.Items (I).Found
                             in False_Value | True_Value
                           and then Results.Items (I).Used
                                      in False_Value | True_Value
                           and then (if Results.Items (I).Used = True_Value
                                     then Results.Items (I).Found
                                            = True_Value)
                           and then Results.Items (I).Distance_To_Line
                                      >= 0.0
                           and then Results.Items (I).Distance_To_Line
                                      <= Max_Value)
               and then (for all J2 in 0 .. Found - 1 =>
                           Index_Of (J2) < Count));
            KG.Line_Distance
              ((Read (Points (J).X), Read (Points (J).Y)), Line_2D, Distance,
               S);
            Results.Items (Index_Of (J)).Distance_To_Line :=
              (if Succeeded (S) then Distance else 0.0);
         end loop;
      end;

      --  The segment between the extreme used points.
      declare
         Fits : Boolean;
      begin
         Extreme_Segment (Line, Points, Used, Found, Segment, Fits);
         if not Fits then
            Results_Destroy (Results);
            Bad (Status, "FindLine: the line segment would exceed"
                         & " +/-1.0E150");
            return;
         end if;
      end;

      --  The counts.
      Num_Found := 0;
      Num_Used := 0;
      for K in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (Num_Found = Count_Found (Results.Items.all, K - 1)
            and then Num_Used = Count_Used (Results.Items.all, K - 1)
            and then Num_Used <= Num_Found and then Num_Found <= K);
         if Results.Items (K).Found = True_Value then
            Num_Found := Num_Found + 1;
         end if;
         if Results.Items (K).Used = True_Value then
            Num_Used := Num_Used + 1;
         end if;
      end loop;

      Results.Line := Line;
      Results.Segment := Segment;
      Results.RMS_Error := RMS;
      Results.Num_Points_Found := Num_Found;
      Results.Num_Points_Used := Num_Used;
      Set_Success (Status);
   end Execute;

   procedure Results_Destroy (Results : in out Ks_Find_Line_Results) is
   begin
      if Results /= null then
         Free (Results.Items);
         Free_Calipers (Results.Calipers);
         Free (Results);
      end if;
   end Results_Destroy;

   procedure Results_Count
     (Results : access constant Ks_Find_Line_Results_Data;
      Count   : out Int32;
      Status  : out Ks_Status) is
   begin
      Count := 0;
      if Results = null then
         Set_Success (Status);
      elsif not Valid_Results (Results) then
         Bad (Status, "Results is not a valid find line results handle");
      else
         Count := Int32 (Results.Count);
         Set_Success (Status);
      end if;
   end Results_Count;

   procedure Results_Item
     (Results : access constant Ks_Find_Line_Results_Data;
      Index   : Int32;
      Item    : out Ks_Find_Line_Result;
      Status  : out Ks_Status) is
   begin
      Item := No_Item;
      if Results /= null and then not Valid_Results (Results) then
         Bad (Status, "Results is not a valid find line results handle");
      elsif Results = null or else Index < 0
        or else Index >= Int32 (Results.Count)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Item: index outside the results");
      elsif Results.Items (Natural (Index)).Found
              not in False_Value | True_Value
        or else Results.Items (Natural (Index)).Used
                  not in False_Value | True_Value
      then
         Bad (Status, "Results is not a valid find line results handle");
      else
         Item := Results.Items (Natural (Index));
         Set_Success (Status);
      end if;
   end Results_Item;

   procedure Results_Caliper_Results
     (Results : access constant Ks_Find_Line_Results_Data;
      Index   : Int32;
      Copy    : out KC.Ks_Caliper_Results;
      Status  : out Ks_Status) is
   begin
      Copy := null;
      if Results /= null and then not Valid_Results (Results) then
         Bad (Status, "Results is not a valid find line results handle");
      elsif Results = null or else Index < 0
        or else Index >= Int32 (Results.Count)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "CaliperResults: index outside the results");
      else
         KC.Results_Duplicate (Results.Calipers (Natural (Index)), Copy,
                               Status);
      end if;
   end Results_Caliper_Results;

   procedure Results_Line
     (Results : access constant Ks_Find_Line_Results_Data;
      Line    : out KS.Ks_Line;
      Segment : out KS.Ks_Line_Segment;
      Status  : out Ks_Status) is
   begin
      Line := (others => <>);
      Segment := (others => <>);
      if Results = null then
         Bad (Status, "Results has no line");
      elsif not Valid_Results (Results)
        or else not KS.Valid_Line (Results.Line)
        or else not KS.Valid_Line_Segment (Results.Segment)
      then
         Bad (Status, "Results is not a valid find line results handle");
      else
         Line := Results.Line;
         Segment := Results.Segment;
         Set_Success (Status);
      end if;
   end Results_Line;

   procedure Results_Fit
     (Results          : access constant Ks_Find_Line_Results_Data;
      RMS_Error        : out Long_Float;
      Num_Points_Found : out Int32;
      Num_Points_Used  : out Int32;
      Status           : out Ks_Status) is
   begin
      RMS_Error := 0.0;
      Num_Points_Found := 0;
      Num_Points_Used := 0;
      if Results = null then
         Set_Success (Status);
      elsif not Valid_Results (Results) then
         Bad (Status, "Results is not a valid find line results handle");
      else
         RMS_Error := Results.RMS_Error;
         Num_Points_Found := Int32 (Results.Num_Points_Found);
         Num_Points_Used := Int32 (Results.Num_Points_Used);
         Set_Success (Status);
      end if;
   end Results_Fit;

end AMV.Kernels.Find_Line;
