pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.Image_Math;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Caliper with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;
   package KM renames AMV.Kernels.Image_Math;

   procedure Free is new Ada.Unchecked_Deallocation
     (Result_Array, Result_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Value_Array, Value_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Caliper_Results_Data, Ks_Caliper_Results);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Values
     (Length : Positive;
      Values : out Value_Array_Access)
   with
     Global => null,
     Post   => (if Values /= null
                then Values'First = 0 and then Values'Last = Length - 1);
   --  A new array of Length values indexed from 0 (unspecified values,
   --  every caller writes all of them), or null when the memory cannot be
   --  allocated. Trusted: the allocator raises Storage_Error, which SPARK
   --  cannot express.

   procedure Allocate_Values
     (Length : Positive;
      Values : out Value_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Values := new Value_Array (0 .. Length - 1);
   exception
      when Storage_Error =>
         Values := null;
   end Allocate_Values;

   procedure Allocate_Items
     (Count : Positive;
      Items : out Result_Array_Access)
   with
     Global => null,
     Post   => (if Items /= null
                then Items'First = 0 and then Items'Last = Count - 1);
   --  A new array of Count results indexed from 0 (the record's default
   --  values), or null. Trusted as above.

   procedure Allocate_Items
     (Count : Positive;
      Items : out Result_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Items := new Result_Array (0 .. Count - 1);
   exception
      when Storage_Error =>
         Items := null;
   end Allocate_Items;

   procedure Allocate_Results (Results : out Ks_Caliper_Results)
   with
     Global => null,
     Post   => (if Results /= null
                then Results.Count = 0 and then Results.Items = null
                     and then Results.Projection = null
                     and then Results.Filtered = null
                     and then Results.Half_Length = 0.0);
   --  A new results record with the record's default values, or null.
   --  Trusted as above.

   procedure Allocate_Results (Results : out Ks_Caliper_Results)
     with SPARK_Mode => Off
   is
   begin
      Results := new Ks_Caliper_Results_Data;
   exception
      when Storage_Error =>
         Results := null;
   end Allocate_Results;

   ---------------------------------------------------------------------
   --  Messages
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

   subtype Short_Text is String
     with Dynamic_Predicate =>
       Short_Text'First = 1 and then Short_Text'Length <= 60;
   --  A part of a message.

   function Prefix (Nested : Boolean) return Short_Text is
     (if Nested then "RunParams.CaliperRunParams." else "RunParams.");
   --  How messages name the run parameters: those of the caliper tool, or
   --  the caliper run parameters of a find tool.

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

   function Checkable (Status : Ks_Status) return Boolean is
     (Valid (Status)
      and then Status.Failure in Failure_None | Failure_Bad_Parameter);

   ---------------------------------------------------------------------
   --  Values
   ---------------------------------------------------------------------

   subtype Grey is Long_Float range 0.0 .. 255.0;
   subtype Signed_Grey is Long_Float range -255.0 .. 255.0;
   subtype Unit is Long_Float range 0.0 .. 1.0;
   subtype Sample_Coordinate is Long_Float
     range 0.0 .. Long_Float (Max_Search_Samples);
   subtype Coordinate is Long_Float range -Max_Value .. Max_Value;
   subtype Step is Long_Float range -2.0 .. 2.0;
   subtype Scale is Long_Float range 0.0 .. 2.0 ** 503;

   subtype Sample_Count is Integer range 1 .. Max_Search_Samples;
   subtype Filter_Size is Integer range 1 .. Max_Filter_Half_Size;

   function In_Bound (X : Long_Float) return Boolean is
     (X >= -Max_Value and then X <= Max_Value);

   function Read_Grey (X : Long_Float) return Grey is
     (if X >= 0.0 then (if X <= 255.0 then X else 255.0) else 0.0);
   --  X limited to [0, 255]. Every value the kernel stores in a profile,
   --  and every bilinear sample of an 8-bit image, lies in that range, so
   --  the limit never changes a value; it keeps the proofs free of facts
   --  about the values of heap arrays (docs/PROOF.md).

   function Read_Signed (X : Long_Float) return Signed_Grey is
     (if X >= -255.0 then (if X <= 255.0 then X else 255.0) else -255.0);
   --  X limited to [-255, 255], in the same way (filter values).

   ---------------------------------------------------------------------
   --  Run parameters
   ---------------------------------------------------------------------

   function Valid_Scorer (S : Ks_Caliper_Scorer) return Boolean is
     (S.Kind in Scorer_Kind
      and then S.Enabled in False_Value | True_Value
      and then S.X0 >= 0.0 and then S.X0 <= Max_Value
      and then S.X1 >= 0.0 and then S.X1 <= Max_Value
      and then In_Bound (S.XC)
      and then S.Y0 >= 0.0 and then S.Y0 <= 1.0
      and then S.Y1 >= 0.0 and then S.Y1 <= 1.0);

   function Valid_List (L : Ks_Caliper_Scorers) return Boolean is
     (L.Count in 0 .. Max_Scorers
      and then (for all I in 0 .. Integer (L.Count) - 1 =>
                  Valid_Scorer (L.Items (I))));

   function Valid_Params (P : Ks_Caliper_Run_Params) return Boolean is
     (P.Edge_Mode in Edge_Mode_Single_Edge | Edge_Mode_Pair
      and then P.Edge_0_Polarity
                 in Polarity_Dark_To_Light .. Polarity_Dont_Care
      and then P.Edge_1_Polarity
                 in Polarity_Dark_To_Light .. Polarity_Dont_Care
      and then P.Filter_Half_Size_In_Pixels in 1 .. Max_Filter_Half_Size
      and then P.Max_Results in 1 .. Max_Results_Limit
      and then In_Bound (P.Edge_0_Position)
      and then In_Bound (P.Edge_1_Position)
      and then P.Contrast_Threshold >= 0.0
      and then P.Contrast_Threshold <= Max_Value
      and then Valid_List (P.Single_Edge_Scorers)
      and then Valid_List (P.Two_Edge_Scorers));
   --  What Check_Params establishes (the remaining checks, the pair-only
   --  kinds and the expected width, need no fact later on).

   procedure Check_Scorer
     (Nested : Boolean;
      List   : Short_Text;
      Index  : Natural;
      S      : Ks_Caliper_Scorer;
      Single : Boolean;
      Status : in out Ks_Status)
   with
     Pre  => Checkable (Status) and then Index < Max_Scorers,
     Post => Checkable (Status)
             and then (if Succeeded (Status)
                       then Succeeded (Status'Old) and then Valid_Scorer (S));
   --  The checks of one scorer of a list ("RunParams.SingleEdgeScorers(0)
   --  .X0 must be ..."); Single rejects the pair-only kinds.

   type Scorer_Fault is
     (No_Fault, Bad_Kind, Pair_Kind, Bad_Enabled, Bad_X0, Bad_X1, Bad_XC,
      Bad_Y0, Bad_Y1);

   function Fault_Of (S : Ks_Caliper_Scorer; Single : Boolean)
      return Scorer_Fault
   is (if S.Kind not in Scorer_Kind then Bad_Kind
       elsif Single and then S.Kind in Pair_Scorer_Kind then Pair_Kind
       elsif S.Enabled not in False_Value | True_Value then Bad_Enabled
       elsif not (S.X0 >= 0.0 and then S.X0 <= Max_Value) then Bad_X0
       elsif not (S.X1 >= 0.0 and then S.X1 <= Max_Value) then Bad_X1
       elsif not In_Bound (S.XC) then Bad_XC
       elsif not (S.Y0 >= 0.0 and then S.Y0 <= 1.0) then Bad_Y0
       elsif not (S.Y1 >= 0.0 and then S.Y1 <= 1.0) then Bad_Y1
       else No_Fault)
   with Post => (if Fault_Of'Result = No_Fault then Valid_Scorer (S));
   --  The first check a scorer fails (No_Fault when it passes them all).

   function Fault_Text (F : Scorer_Fault) return Short_Text is
     (case F is
         when No_Fault    => "",
         when Bad_Kind    => "Kind is not a known scorer kind",
         when Pair_Kind   =>
           "Kind measures pairs: it does not belong to SingleEdgeScorers",
         when Bad_Enabled => "Enabled must be 0 or 1",
         when Bad_X0      => "X0 must be finite, >= 0 and <= 1.0E150",
         when Bad_X1      => "X1 must be finite, >= 0 and <= 1.0E150",
         when Bad_XC      => "XC must be finite and within +/-1.0E150",
         when Bad_Y0      => "Y0 must be within [0, 1]",
         when Bad_Y1      => "Y1 must be within [0, 1]");

   procedure Check_Scorer
     (Nested : Boolean;
      List   : Short_Text;
      Index  : Natural;
      S      : Ks_Caliper_Scorer;
      Single : Boolean;
      Status : in out Ks_Status)
   is
      Fault : constant Scorer_Fault := Fault_Of (S, Single);
   begin
      if Succeeded (Status) and then Fault /= No_Fault then
         Bad (Status, Prefix (Nested) & List & "("
                      & Image_Of (Int64 (Index)) & ")." & Fault_Text (Fault));
      end if;
   end Check_Scorer;

   procedure Check_List
     (Nested : Boolean;
      List   : Short_Text;
      L      : Ks_Caliper_Scorers;
      Single : Boolean;
      Status : in out Ks_Status)
   with
     Pre  => Checkable (Status),
     Post => Checkable (Status)
             and then (if Succeeded (Status)
                       then Succeeded (Status'Old) and then Valid_List (L));

   procedure Check_List
     (Nested : Boolean;
      List   : Short_Text;
      L      : Ks_Caliper_Scorers;
      Single : Boolean;
      Status : in out Ks_Status) is
   begin
      if not Succeeded (Status) then
         return;
      elsif L.Count not in 0 .. Max_Scorers then
         Bad (Status, Prefix (Nested) & List & ".Count must be in 0 .. 8");
         return;
      end if;
      for I in 0 .. Integer (L.Count) - 1 loop
         Check_Scorer (Nested, List, I, L.Items (I), Single, Status);
         if not Succeeded (Status) then
            return;
         end if;
         pragma Loop_Invariant
           (Checkable (Status) and then Succeeded (Status)
            and then (for all J in 0 .. I => Valid_Scorer (L.Items (J))));
      end loop;
   end Check_List;

   function Needs_Width (L : Ks_Caliper_Scorers) return Boolean is
     (for some I in 0 .. Integer (L.Count) - 1 =>
        L.Items (I).Enabled = True_Value
        and then L.Items (I).Kind in Scorer_Size_Norm
                                   .. Scorer_Size_Diff_Norm_Asym)
   with Pre => L.Count in 0 .. Max_Scorers;
   --  An enabled size scorer is in the list.

   procedure Check_Params
     (Params : Ks_Caliper_Run_Params;
      Nested : Boolean;
      Status : out Ks_Status)
   with
     Post => Checkable (Status)
             and then (if Succeeded (Status) then Valid_Params (Params));
   --  Every check of the run parameters, the first failing one reported.

   procedure Check_Params
     (Params : Ks_Caliper_Run_Params;
      Nested : Boolean;
      Status : out Ks_Status)
   is
      P : constant Short_Text := Prefix (Nested);
   begin
      Set_Success (Status);
      if Params.Edge_Mode not in Edge_Mode_Single_Edge | Edge_Mode_Pair then
         Bad (Status, P & "EdgeMode must be SingleEdge (1) or Pair (2)");
      elsif Params.Edge_0_Polarity
              not in Polarity_Dark_To_Light .. Polarity_Dont_Care
      then
         Bad (Status, P & "Edge0Polarity must be DarkToLight (1),"
                      & " LightToDark (2) or DontCare (3)");
      elsif Params.Edge_1_Polarity
              not in Polarity_Dark_To_Light .. Polarity_Dont_Care
      then
         Bad (Status, P & "Edge1Polarity must be DarkToLight (1),"
                      & " LightToDark (2) or DontCare (3)");
      elsif not In_Bound (Params.Edge_0_Position) then
         Bad (Status, P & "Edge0Position must be finite and within"
                      & " +/-1.0E150");
      elsif not In_Bound (Params.Edge_1_Position) then
         Bad (Status, P & "Edge1Position must be finite and within"
                      & " +/-1.0E150");
      elsif not (Params.Contrast_Threshold >= 0.0) then
         Bad (Status, P & "ContrastThreshold must be >= 0");
      elsif not (Params.Contrast_Threshold <= Max_Value) then
         Bad (Status, P & "ContrastThreshold must be finite and"
                      & " <= 1.0E150");
      elsif Params.Filter_Half_Size_In_Pixels
              not in 1 .. Max_Filter_Half_Size
      then
         Bad (Status, P & "FilterHalfSizeInPixels must be in 1 .. 1000");
      elsif Params.Max_Results not in 1 .. Max_Results_Limit then
         Bad (Status, P & "MaxResults must be in 1 .. 1000");
      elsif Params.Sampling_Mode
              not in Sampling_Mode_Bilinear_Interpolation
                   | Sampling_Mode_Bilinear_Accurate
      then
         Bad (Status, P & "SamplingMode must be BilinearInterpolation (2)"
                      & " or BilinearAccurate (4)");
      end if;
      Check_List (Nested, "SingleEdgeScorers", Params.Single_Edge_Scorers,
                  True, Status);
      Check_List (Nested, "TwoEdgeScorers", Params.Two_Edge_Scorers, False,
                  Status);
      if Succeeded (Status)
        and then Params.Edge_Mode = Edge_Mode_Pair
        and then Needs_Width (Params.Two_Edge_Scorers)
        and then not (Params.Edge_1_Position > Params.Edge_0_Position)
      then
         Bad (Status, P & "Edge1Position must be greater than Edge0Position"
                      & " for the size scorers");
      end if;
   end Check_Params;

   ---------------------------------------------------------------------
   --  Scorers
   ---------------------------------------------------------------------

   function Tent (S : Ks_Caliper_Scorer; M : Long_Float) return Unit
   with Pre => Valid_Scorer (S) and then In_Bound (M);
   --  The output of scorer S for the measure M (see the spec).

   function Tent (S : Ks_Caliper_Scorer; M : Long_Float) return Unit is
      D    : constant Long_Float := M - S.XC;
      A    : constant Long_Float := abs D;
      Half : constant Long_Float := (if D >= 0.0 then S.X1 else S.X0);
      R    : Long_Float;
   begin
      if A = 0.0 then
         R := 0.0;
      elsif Half <= 0.0 or else A >= Half then
         R := 1.0;
      else
         R := N.Unit_Ratio (A, Half);
      end if;
      return N.Clamp_Unit (S.Y1 + N.Times_Unit (S.Y0 - S.Y1, R));
   end Tent;

   ---------------------------------------------------------------------
   --  Sampling geometry
   ---------------------------------------------------------------------

   type Geometry is record
      Nx, Ny       : Sample_Count := 1;
      O_X, O_Y     : Coordinate := 0.0;
      Dx_X, Dx_Y   : Step := 0.0;
      Dy_X, Dy_Y   : Step := 0.0;
      K            : Scale := 0.0;
      C            : Long_Float := 0.5;
      Half         : Long_Float := 0.0;
   end record;
   --  The sample grid in pixel space: sample (I, J) is the centre of cell
   --  (I, J), at O + (I + 0.5) Dx + (J + 0.5) Dy; O is the region's corner
   --  origin, Dx and Dy the steps along side X and side Y (at most about
   --  1.5 pixels long). K is the selected-space length of one step along
   --  side X, C = Nx / 2 the centre along side X (in steps) and Half =
   --  C * K half the search length in the selected space.

   function Valid_Geometry (G : Geometry) return Boolean is
     (Int64 (G.Nx) * Int64 (G.Ny) <= Max_Samples
      and then G.C = Long_Float (G.Nx) / 2.0
      and then G.Half = G.C * G.K
      and then G.Half >= 0.0 and then G.Half <= Max_Value);

   function Times (C, K : Long_Float) return Long_Float is (C * K)
   with Pre => C >= 0.0 and then C <= 2.0 ** 14
               and then K >= 0.0 and then K <= 2.0 ** 503;
   --  C * K, in a context small enough for the provers to bound it.

   function Unit_Quotient (X, L : Long_Float) return Long_Float
   with Pre  => L > 0.0 and then abs X <= 2.0 ** 1000,
        Post => abs Unit_Quotient'Result <= 1.0;
   --  X / L for a vector component X of length L (abs X <= L, which the
   --  test states for the prover; it never acts).

   function Unit_Quotient (X, L : Long_Float) return Long_Float is
   begin
      if X >= L then
         return 1.0;
      elsif X <= -L then
         return -1.0;
      else
         return N.Unit_Ratio (X, L);
      end if;
   end Unit_Quotient;

   procedure Samples_Along
     (Length_In_Pixels : Long_Float;
      Limit            : Positive;
      Count            : out Sample_Count;
      Spacing          : out Long_Float;
      Fits             : out Boolean)
   with
     Pre  => Length_In_Pixels >= 0.0
             and then Length_In_Pixels <= 2.0 ** 1020
             and then Limit <= Max_Search_Samples,
     Post => (if Fits then Count <= Limit) and then Spacing in 0.0 .. 2.0;
   --  The number of samples along a side Length_In_Pixels long (the
   --  length rounded, at least 1) and their spacing in pixels (the length
   --  over the count, at most 1.5; the limit of 2 never acts). Fits is
   --  False when the count would exceed Limit.

   procedure Samples_Along
     (Length_In_Pixels : Long_Float;
      Limit            : Positive;
      Count            : out Sample_Count;
      Spacing          : out Long_Float;
      Fits             : out Boolean) is
   begin
      Count := 1;
      Spacing := 0.0;
      Fits := Length_In_Pixels < Long_Float (Limit) + 0.5;
      if not Fits then
         return;
      end if;
      declare
         Rounded : constant Integer := Integer (Length_In_Pixels);
      begin
         --  Rounded is at most Limit (the length is below Limit + 0.5);
         --  the limit states it for the prover and never acts.
         Count := Integer'Max (1, Integer'Min (Rounded, Limit));
      end;
      Spacing := Long_Float'Min (Length_In_Pixels / Long_Float (Count), 2.0);
   end Samples_Along;

   procedure Finish_Geometry
     (G      : in out Geometry;
      S      : KT.Ks_Transform_2D_Linear;
      Status : out Ks_Status)
   with
     Pre  => KT.Bounded (S)
             and then Int64 (G.Nx) * Int64 (G.Ny) <= Max_Samples,
     Post => Checkable (Status)
             and then (if Succeeded (Status) then Valid_Geometry (G));
   --  K, C and Half of a grid whose sizes and steps are set (S is
   --  Selected_From_Pixel); Bad_Parameter when Half exceeds Max_Value.

   procedure Finish_Geometry
     (G      : in out Geometry;
      S      : KT.Ks_Transform_2D_Linear;
      Status : out Ks_Status)
   is
      --  The selected-space step along side X: each product is at most
      --  2.0E150, each sum 4.0E150, the length 8.0E150 (below 2**503).
      U : constant Long_Float :=
        N.Mul_Within (S.A, G.Dx_X, Max_Value, 2.0)
        + N.Mul_Within (S.B, G.Dx_Y, Max_Value, 2.0);
      V : constant Long_Float :=
        N.Mul_Within (S.C, G.Dx_X, Max_Value, 2.0)
        + N.Mul_Within (S.D, G.Dx_Y, Max_Value, 2.0);
   begin
      G.K := N.Hypot (U, V);
      G.C := Long_Float (G.Nx) / 2.0;
      pragma Assert (G.C >= 0.5 and then G.C <= 2.0 ** 14);
      G.Half := Times (G.C, G.K);
      pragma Assert (G.Half >= 0.0);
      if G.Half > Max_Value then
         Bad (Status, "Region: the search length exceeds 2.0E150 in the"
                      & " selected space");
      else
         Set_Success (Status);
      end if;
   end Finish_Geometry;

   procedure Prepare_Geometry
     (Region              : KS.Ks_Rectangle_Affine;
      Pixel_From_Region   : KT.Ks_Transform_2D_Linear;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      G                   : out Geometry;
      Status              : out Ks_Status)
   with
     Pre  => KS.Valid_Rectangle_Affine (Region)
             and then KT.Bounded (Pixel_From_Region)
             and then KT.Bounded (Selected_From_Pixel),
     Post => Checkable (Status)
             and then (if Succeeded (Status) then Valid_Geometry (G));
   --  The sample grid of Region, or Bad_Parameter (see the spec).

   procedure Prepare_Geometry
     (Region              : KS.Ks_Rectangle_Affine;
      Pixel_From_Region   : KT.Ks_Transform_2D_Linear;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      G                   : out Geometry;
      Status              : out Ks_Status)
   is
      Child_To_Region : KT.Ks_Transform_2D_Linear;
      T               : KT.Ks_Transform_2D_Linear;
      S               : KT.Ks_Transform_2D_Linear renames Selected_From_Pixel;
      Lx, Ly          : Long_Float;
      Px, Py          : Long_Float;
      Sx, Sy          : Long_Float;
      Fits            : Boolean;
      Nx, Ny          : Sample_Count;
   begin
      G := (others => <>);
      if not (Region.Side_X_Length > 0.0) then
         Bad (Status, "Region.SideXLength must be > 0");
         return;
      elsif not (Region.Side_Y_Length > 0.0) then
         Bad (Status, "Region.SideYLength must be > 0");
         return;
      end if;
      KS.Get_Parent_From_Child_Transform (Region, Child_To_Region, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KT.Compose (Pixel_From_Region, Child_To_Region, T, Status);
      if not Succeeded (Status) then
         return;
      end if;

      --  Pixels per unit of the region's own frame along each side.
      Lx := N.Hypot (T.A, T.C);
      Ly := N.Hypot (T.B, T.D);
      if not (Lx > 0.0) then
         Bad (Status, "Region: side X maps to a point in pixel space");
         return;
      elsif not (Ly > 0.0) then
         Bad (Status, "Region: side Y maps to a point in pixel space");
         return;
      end if;
      Px := N.Mul (Region.Side_X_Length, Lx);
      Py := N.Mul (Region.Side_Y_Length, Ly);

      Samples_Along (Px, Max_Search_Samples, Nx, Sx, Fits);
      if not Fits then
         Bad (Status, "Region: side X is longer than 32768 pixels");
         return;
      end if;
      Samples_Along (Py, Max_Projection_Samples, Ny, Sy, Fits);
      if not Fits then
         Bad (Status, "Region: side Y is longer than 32768 pixels");
         return;
      elsif Int64 (Nx) * Int64 (Ny) > Max_Samples then
         Bad (Status, "Region covers more than 16777216 samples");
         return;
      end if;

      G.Nx := Nx;
      G.Ny := Ny;
      G.O_X := T.Translation_X;
      G.O_Y := T.Translation_Y;
      G.Dx_X := N.Times_Unit (Sx, Unit_Quotient (T.A, Lx));
      G.Dx_Y := N.Times_Unit (Sx, Unit_Quotient (T.C, Lx));
      G.Dy_X := N.Times_Unit (Sy, Unit_Quotient (T.B, Ly));
      G.Dy_Y := N.Times_Unit (Sy, Unit_Quotient (T.D, Ly));
      Finish_Geometry (G, S, Status);
   end Prepare_Geometry;

   ---------------------------------------------------------------------
   --  Profiles
   ---------------------------------------------------------------------

   function Coordinate_Of
     (O : Coordinate; I, J : Long_Float; Dx, Dy : Step) return Long_Float
   is (O + N.Mul_Within (I, Dx, Long_Float (Max_Search_Samples), 2.0)
         + N.Mul_Within (J, Dy, Long_Float (Max_Search_Samples), 2.0))
   with Pre  => I in 0.0 .. Long_Float (Max_Search_Samples)
                and then J in 0.0 .. Long_Float (Max_Search_Samples),
        Post => abs Coordinate_Of'Result <= Max_Value + 2.0 ** 18;
   --  O + I Dx + J Dy, one coordinate of a point of the grid (I and J in
   --  steps).

   procedure Project
     (Image      : access constant KI.Ks_Image_8_Grey_Data;
      G          : Geometry;
      Projection : in out Value_Array)
   with
     Pre  => KI.Valid_Image (Image) and then Valid_Geometry (G)
             and then Projection'First = 0
             and then Projection'Last = G.Nx - 1;
   --  The projection profile: the mean of the samples of each column of
   --  the grid, within [0, 255].

   procedure Project
     (Image      : access constant KI.Ks_Image_8_Grey_Data;
      G          : Geometry;
      Projection : in out Value_Array)
   is
      Sum_Limit : constant := 2.0 ** 23;
      --  At least 255 * Max_Projection_Samples (about 8.4E6).
      Sum       : Long_Float;
      Value     : Long_Float;
      S         : Ks_Status;
      I_Pos     : Long_Float;
      J_Pos     : Long_Float;
   begin
      for I in 0 .. G.Nx - 1 loop
         Sum := 0.0;
         I_Pos := Long_Float (I) + 0.5;
         for J in 0 .. G.Ny - 1 loop
            pragma Loop_Invariant (Sum >= 0.0 and then Sum <= Sum_Limit);
            J_Pos := Long_Float (J) + 0.5;
            KM.Bilinear_Grey_8
              (Image,
               Coordinate_Of (G.O_X, I_Pos, J_Pos, G.Dx_X, G.Dy_X),
               Coordinate_Of (G.O_Y, I_Pos, J_Pos, G.Dx_Y, G.Dy_Y),
               Value, S);
            --  The sum of at most Max_Projection_Samples values of at
            --  most 255 stays below the limit, which never acts.
            if Succeeded (S) then
               Sum := Long_Float'Min (Sum + Read_Grey (Value), Sum_Limit);
            end if;
         end loop;
         Projection (I) := Read_Grey (Sum / Long_Float (G.Ny));
      end loop;
   end Project;

   function Window_Mean
     (Projection : Value_Array;
      First      : Integer;
      Size       : Filter_Size) return Grey
   with Pre => Projection'First = 0 and then Projection'Last >= 0
               and then Projection'Last < Max_Search_Samples
               and then First >= -Max_Filter_Half_Size
               and then First <= Max_Search_Samples;
   --  The mean of the Size profile values from index First on, an index
   --  beyond either end reading the end value.

   function Window_Mean
     (Projection : Value_Array;
      First      : Integer;
      Size       : Filter_Size) return Grey
   is
      Sum_Limit : constant := 2.0 ** 18;
      --  At least 255 * Max_Filter_Half_Size (255_000).
      Last      : constant Natural := Projection'Last;
      Sum       : Long_Float := 0.0;
      Index     : Integer;
   begin
      for K in 0 .. Size - 1 loop
         pragma Loop_Invariant (Sum >= 0.0 and then Sum <= Sum_Limit);
         Index := First + K;
         if Index < 0 then
            Index := 0;
         elsif Index > Last then
            Index := Last;
         end if;
         Sum := Long_Float'Min (Sum + Read_Grey (Projection (Index)),
                                Sum_Limit);
      end loop;
      return Read_Grey (Sum / Long_Float (Size));
   end Window_Mean;

   procedure Filter
     (Projection : Value_Array;
      Size       : Filter_Size;
      Filtered   : in out Value_Array)
   with
     Pre => Projection'First = 0 and then Projection'Last >= 0
            and then Projection'Last < Max_Search_Samples
            and then Filtered'First = 0
            and then Filtered'Last = Projection'Last;
   --  The edge filter of half size Size at each boundary (the last value
   --  0), within [-255, 255].

   procedure Filter
     (Projection : Value_Array;
      Size       : Filter_Size;
      Filtered   : in out Value_Array) is
   begin
      for B in 0 .. Projection'Last loop
         if B < Projection'Last then
            Filtered (B) :=
              Window_Mean (Projection, B + 1, Size)
              - Window_Mean (Projection, B - Size + 1, Size);
         else
            Filtered (B) := 0.0;
         end if;
      end loop;
   end Filter;

   ---------------------------------------------------------------------
   --  Candidates and their ordering
   ---------------------------------------------------------------------

   subtype Key_Value is Long_Float range 0.0 .. 255.0;

   type Candidate is record
      Key : Key_Value := 0.0;
      T0  : Sample_Coordinate := 0.0;
      C0  : Signed_Grey := 0.0;
      T1  : Sample_Coordinate := 0.0;
      C1  : Signed_Grey := 0.0;
   end record;
   --  An edge (T1 = T0, C1 = C0, Key = its contrast magnitude) or a
   --  scored result (Key = the score): the positions of its edges along
   --  side X in steps from the corner origin, and their contrasts.

   type Candidate_Array is array (Natural range <>) of Candidate;

   function Inside (C : Candidate; Limit : Long_Float) return Boolean is
     (C.T0 <= C.T1 and then C.T1 <= Limit);
   --  Both edges within [0, Limit], edge 0 first.

   function Fits (C : Candidate; Limit, Top : Long_Float) return Boolean is
     (Inside (C, Limit) and then C.Key <= Top);
   --  Also the key at most Top.

   function Sorted (B : Candidate_Array; Count : Natural) return Boolean is
     (for all I in 0 .. Count - 2 => B (I).Key >= B (I + 1).Key)
   with Pre => B'First = 0 and then Count - 1 <= B'Last;

   function All_Fit
     (B : Candidate_Array; Count : Natural; Limit, Top : Long_Float)
      return Boolean
   is (for all I in 0 .. Count - 1 => Fits (B (I), Limit, Top))
   with Pre => B'First = 0 and then Count - 1 <= B'Last;

   procedure Insert
     (Buffer   : in out Candidate_Array;
      Count    : in out Natural;
      Capacity : Positive;
      Limit    : Long_Float;
      Top      : Long_Float;
      Item     : Candidate)
   with
     Pre  => Buffer'First = 0 and then Capacity - 1 <= Buffer'Last
             and then Count <= Capacity
             and then Sorted (Buffer, Count)
             and then All_Fit (Buffer, Count, Limit, Top)
             and then Fits (Item, Limit, Top),
     Post => Count >= Count'Old and then Count <= Capacity
             and then Sorted (Buffer, Count)
             and then All_Fit (Buffer, Count, Limit, Top);
   --  Keeps the Capacity candidates with the largest keys, sorted by key
   --  (largest first): Item goes after every candidate whose key is at
   --  least its own, and the last one drops out when the buffer is full
   --  and Item's key is larger; otherwise Item is not kept.

   procedure Insert
     (Buffer   : in out Candidate_Array;
      Count    : in out Natural;
      Capacity : Positive;
      Limit    : Long_Float;
      Top      : Long_Float;
      Item     : Candidate)
   is
      Pos : Natural;
   begin
      if Count < Capacity then
         Pos := Count;
         Count := Count + 1;
      elsif Item.Key > Buffer (Count - 1).Key then
         Pos := Count - 1;
      else
         return;
      end if;
      --  Buffer (Pos) is free; move the candidates with smaller keys up.
      while Pos > 0 and then Buffer (Pos - 1).Key < Item.Key loop
         pragma Loop_Invariant (Pos < Count and then Count <= Capacity);
         pragma Loop_Invariant
           (for all I in 0 .. Pos - 2 => Buffer (I).Key >= Buffer (I + 1).Key);
         pragma Loop_Invariant
           (for all I in Pos + 1 .. Count - 2 =>
              Buffer (I).Key >= Buffer (I + 1).Key);
         pragma Loop_Invariant
           (if Pos + 1 <= Count - 1 then Buffer (Pos + 1).Key < Item.Key);
         pragma Loop_Invariant
           (if Pos + 1 <= Count - 1
            then Buffer (Pos - 1).Key >= Buffer (Pos + 1).Key);
         pragma Loop_Invariant
           (for all I in 0 .. Count - 1 =>
              (if I /= Pos then Fits (Buffer (I), Limit, Top)));
         Buffer (Pos) := Buffer (Pos - 1);
         Pos := Pos - 1;
      end loop;
      Buffer (Pos) := Item;
   end Insert;

   ---------------------------------------------------------------------
   --  Edges
   ---------------------------------------------------------------------

   function Matches (Polarity : Int32; Contrast : Long_Float) return Boolean
   is (Polarity = Polarity_Dont_Care
       or else (Polarity = Polarity_Dark_To_Light and then Contrast > 0.0)
       or else (Polarity = Polarity_Light_To_Dark and then Contrast < 0.0));

   function Centroid
     (Num, Den : Long_Float;
      Size     : Filter_Size) return Long_Float
   with Post => abs Centroid'Result <= Long_Float (Max_Filter_Half_Size);
   --  Num / Den when Den > 0 and the quotient is within Size, else 0.

   function Centroid
     (Num, Den : Long_Float;
      Size     : Filter_Size) return Long_Float is
   begin
      if Den > 0.0 and then Den <= 2.0 ** 20 then
         declare
            Scale : constant Long_Float := Long_Float (Size) * Den;
         begin
            if Scale > 0.0 and then abs Num <= Scale then
               return N.Mul_Within
                 (N.Unit_Ratio (Num, Scale), Long_Float (Size), 1.0,
                  Long_Float (Max_Filter_Half_Size));
            end if;
         end;
      end if;
      return 0.0;
   end Centroid;

   function Refined
     (Projection : Value_Array;
      B          : Natural;
      Rising     : Boolean;
      Size       : Filter_Size) return Long_Float
   with
     Pre  => Projection'First = 0
             and then Projection'Last < Max_Search_Samples
             and then B < Projection'Last,
     Post => Refined'Result >= 0.0
             and then Refined'Result <= Long_Float (Projection'Last + 1);
   --  The position (in steps from the corner origin) of the edge whose
   --  filter extremum is at boundary B: B + 1 plus the centroid of the
   --  profile differences P (K + 1) - P (K) (negated for a falling edge)
   --  over the boundaries K within Size of B, relative to B. The centroid
   --  is used when the differences add up to a positive total and lies
   --  within Size of B; otherwise B + 1. Limited to [0, Nx].

   function Refined
     (Projection : Value_Array;
      B          : Natural;
      Rising     : Boolean;
      Size       : Filter_Size) return Long_Float
   is
      Den_Limit : constant := 2.0 ** 19;
      --  At least 255 * (2 * Max_Filter_Half_Size + 1) (510_255).
      Num_Limit : constant := 2.0 ** 29;
      --  At least 255 * Max_Filter_Half_Size * (2 * Max_Filter_Half_Size
      --  + 1) (about 5.1E8).
      Last      : constant Natural := Projection'Last - 1;
      First_K   : constant Natural := (if B >= Size then B - Size else 0);
      Last_K    : constant Natural :=
        (if B + Size <= Last then B + Size else Last);
      Num       : Long_Float := 0.0;
      Den       : Long_Float := 0.0;
      D         : Long_Float;
      Offset    : Long_Float;
      Result    : Long_Float;
   begin
      for K in First_K .. Last_K loop
         pragma Loop_Invariant
           (abs Num <= Num_Limit and then abs Den <= Den_Limit);
         D := Read_Grey (Projection (K + 1)) - Read_Grey (Projection (K));
         if not Rising then
            D := -D;
         end if;
         --  Both sums stay below their limits (above), which never act.
         Den := N.Clamp (Den + D, Den_Limit);
         Num := N.Clamp
           (Num + N.Mul_Within (D, Long_Float (K - B), 255.0,
                                Long_Float (Max_Filter_Half_Size)),
            Num_Limit);
      end loop;
      Offset := Centroid (Num, Den, Size);
      Result := Long_Float (B) + 1.0 + Offset;
      if Result < 0.0 then
         Result := 0.0;
      elsif Result > Long_Float (Projection'Last + 1) then
         Result := Long_Float (Projection'Last + 1);
      end if;
      return Result;
   end Refined;

   procedure Find_Edges
     (Projection : Value_Array;
      Filtered   : Value_Array;
      Params     : Ks_Caliper_Run_Params;
      Edges      : in out Candidate_Array;
      Count      : out Natural)
   with
     Pre  => Valid_Params (Params)
             and then Projection'First = 0
             and then Projection'Last < Max_Search_Samples
             and then Filtered'First = 0
             and then Filtered'Last = Projection'Last
             and then Projection'Last >= 0
             and then Edges'First = 0 and then Edges'Last = Max_Edges - 1,
     Post => Count <= Max_Edges
             and then Sorted (Edges, Count)
             and then All_Fit
                        (Edges, Count, Long_Float (Projection'Last + 1),
                         255.0);
   --  The strongest Max_Edges edges (see the spec) whose polarity matches
   --  Edge0Polarity (single edge) or either polarity (pair), strongest
   --  first.

   procedure Find_Edges
     (Projection : Value_Array;
      Filtered   : Value_Array;
      Params     : Ks_Caliper_Run_Params;
      Edges      : in out Candidate_Array;
      Count      : out Natural)
   is
      Last      : constant Natural := Projection'Last;
      Limit     : constant Long_Float := Long_Float (Last + 1);
      Size      : constant Filter_Size :=
        Filter_Size (Params.Filter_Half_Size_In_Pixels);
      Threshold : constant Long_Float := Params.Contrast_Threshold;
      G, Prev, Next : Signed_Grey;
      Peak      : Boolean;
      Wanted    : Boolean;
      T         : Long_Float;
   begin
      Count := 0;
      --  Boundaries 0 .. Last - 1 (the last filter value belongs to no
      --  boundary).
      for B in 0 .. Last - 1 loop
         pragma Loop_Invariant
           (Count <= Max_Edges
            and then Sorted (Edges, Count)
            and then All_Fit (Edges, Count, Limit, 255.0));
         G := Read_Signed (Filtered (B));
         Prev := (if B > 0 then Read_Signed (Filtered (B - 1)) else 0.0);
         Next := (if B + 1 < Last then Read_Signed (Filtered (B + 1))
                  else 0.0);
         if G > 0.0 then
            Peak := (B = 0 or else G >= Prev)
                    and then (B + 1 = Last or else G > Next);
         elsif G < 0.0 then
            Peak := (B = 0 or else G <= Prev)
                    and then (B + 1 = Last or else G < Next);
         else
            Peak := False;
         end if;
         if Params.Edge_Mode = Edge_Mode_Single_Edge then
            Wanted := Matches (Params.Edge_0_Polarity, G);
         else
            Wanted := Matches (Params.Edge_0_Polarity, G)
                      or else Matches (Params.Edge_1_Polarity, G);
         end if;
         if Peak and then Wanted and then abs G >= Threshold then
            T := Refined (Projection, B, G > 0.0, Size);
            Insert (Edges, Count, Max_Edges, Limit, 255.0,
                    (Key => abs G, T0 => T, C0 => G, T1 => T, C1 => G));
         end if;
      end loop;
   end Find_Edges;

   ---------------------------------------------------------------------
   --  Scoring
   ---------------------------------------------------------------------

   function Midpoint (A, B : Long_Float) return Long_Float is
     (Long_Float'Min (Long_Float'Max ((A + B) / 2.0, A), B))
   with Pre  => A >= 0.0 and then A <= B
                and then B <= Long_Float (Max_Search_Samples),
        Post => Midpoint'Result >= A and then Midpoint'Result <= B;
   --  (A + B) / 2, which lies between A and B (the limits state it for
   --  the prover and never act).

   function Position_Of (G : Geometry; T : Long_Float) return Long_Float
   is (N.Mul_Within (T - G.C, G.K, G.C, G.K))
   with Pre  => Valid_Geometry (G)
                and then T >= 0.0 and then T <= Long_Float (G.Nx),
        Post => abs Position_Of'Result <= G.Half;
   --  The selected-space position of the point T steps from the corner
   --  origin along side X, measured from the region's centre.

   function Width_Of (G : Geometry; D : Long_Float) return Long_Float
   is (abs (2.0 * N.Mul_Within (D / 2.0, G.K, G.C, G.K)))
   with Pre  => Valid_Geometry (G)
                and then D >= 0.0 and then D <= Long_Float (G.Nx),
        Post => Width_Of'Result >= 0.0
                and then Width_Of'Result / 2.0 <= G.Half;
   --  The selected-space length of D steps along side X.

   function Ratio (X, Y : Long_Float) return Long_Float
   with Pre  => abs X <= 4.0 * Max_Value and then Y > 0.0
                and then Y <= 2.0 * Max_Value,
        Post => In_Bound (Ratio'Result);
   --  X / Y, saturated at +/-Max_Value.

   function Ratio (X, Y : Long_Float) return Long_Float is
      Q    : Long_Float;
      Fits : Boolean;
   begin
      N.Ratio_Within (abs X, Y, Max_Value, Q, Fits);
      if not Fits then
         Q := Max_Value;
      end if;
      return (if X < 0.0 then -Q else Q);
   end Ratio;

   function Measure
     (S        : Ks_Caliper_Scorer;
      C        : Candidate;
      G        : Geometry;
      Expected : Long_Float) return Long_Float
   with Pre  => Valid_Scorer (S) and then Valid_Geometry (G)
                and then Inside (C, Long_Float (G.Nx))
                and then Expected >= 0.0 and then Expected <= 2.0 * Max_Value,
        Post => In_Bound (Measure'Result);
   --  The measure of scorer S for candidate C; Expected is the expected
   --  width (Edge1Position - Edge0Position, used only when positive).

   function Measure
     (S        : Ks_Caliper_Scorer;
      C        : Candidate;
      G        : Geometry;
      Expected : Long_Float) return Long_Float
   is
      Mid   : constant Long_Float := Midpoint (C.T0, C.T1);
      Width : constant Long_Float := Width_Of (G, C.T1 - C.T0);
   begin
      case S.Kind is
         when Scorer_Contrast =>
            return (abs C.C0 + abs C.C1) / 2.0;
         when Scorer_Position =>
            return Position_Of (G, Mid);
         when Scorer_Position_Neg =>
            return -Position_Of (G, Mid);
         when Scorer_Position_Norm =>
            return N.Unit_Ratio (Mid - G.C, G.C);
         when Scorer_Position_Norm_Neg =>
            return -N.Unit_Ratio (Mid - G.C, G.C);
         when Scorer_Size_Norm =>
            return (if Expected > 0.0 then Ratio (Width, Expected)
                    else 0.0);
         when Scorer_Size_Diff_Norm =>
            return (if Expected > 0.0
                    then Ratio (abs (Width - Expected), Expected)
                    else 0.0);
         when Scorer_Size_Diff_Norm_Asym =>
            return (if Expected > 0.0 then Ratio (Width - Expected, Expected)
                    else 0.0);
         when others =>
            return (if C.T0 <= G.C and then G.C <= C.T1 then 1.0 else 0.0);
      end case;
   end Measure;

   function Score
     (L        : Ks_Caliper_Scorers;
      C        : Candidate;
      G        : Geometry;
      Expected : Long_Float) return Unit
   with Pre => Valid_List (L) and then Valid_Geometry (G)
               and then Inside (C, Long_Float (G.Nx))
               and then Expected >= 0.0
               and then Expected <= 2.0 * Max_Value;
   --  The product of the outputs of the enabled scorers of L (1 when none
   --  is enabled).

   function Score
     (L        : Ks_Caliper_Scorers;
      C        : Candidate;
      G        : Geometry;
      Expected : Long_Float) return Unit
   is
      Result : Unit := 1.0;
   begin
      for I in 0 .. Integer (L.Count) - 1 loop
         if L.Items (I).Enabled = True_Value then
            Result := N.Times_Unit
              (Result, Tent (L.Items (I), Measure (L.Items (I), C, G,
                                                   Expected)));
         end if;
      end loop;
      return Result;
   end Score;

   procedure Score_Candidates
     (Edges      : Candidate_Array;
      Edge_Count : Natural;
      Params     : Ks_Caliper_Run_Params;
      G          : Geometry;
      Best       : in out Candidate_Array;
      Count      : out Natural)
   with
     Pre  => Valid_Params (Params) and then Valid_Geometry (G)
             and then Edges'First = 0 and then Edge_Count - 1 <= Edges'Last
             and then All_Fit (Edges, Edge_Count, Long_Float (G.Nx), 255.0)
             and then Best'First = 0
             and then Best'Last = Max_Results_Limit - 1,
     Post => Count <= Natural (Params.Max_Results)
             and then Sorted (Best, Count)
             and then All_Fit (Best, Count, Long_Float (G.Nx), 1.0);
   --  The MaxResults best candidates (single edges or pairs), best
   --  first, with their scores as keys.

   procedure Score_Candidates
     (Edges      : Candidate_Array;
      Edge_Count : Natural;
      Params     : Ks_Caliper_Run_Params;
      G          : Geometry;
      Best       : in out Candidate_Array;
      Count      : out Natural)
   is
      Limit    : constant Long_Float := Long_Float (G.Nx);
      Capacity : constant Positive := Positive (Params.Max_Results);
      Expected : constant Long_Float :=
        (if Params.Edge_1_Position > Params.Edge_0_Position
         then Params.Edge_1_Position - Params.Edge_0_Position else 0.0);
      Item     : Candidate;
   begin
      Count := 0;
      if Params.Edge_Mode = Edge_Mode_Single_Edge then
         for A in 0 .. Edge_Count - 1 loop
            pragma Loop_Invariant
              (Count <= Capacity
               and then Sorted (Best, Count)
               and then All_Fit (Best, Count, Limit, 1.0));
            Item := Edges (A);
            Item.Key := Score (Params.Single_Edge_Scorers, Item, G,
                               Expected);
            Insert (Best, Count, Capacity, Limit, 1.0, Item);
         end loop;
      else
         for A in 0 .. Edge_Count - 1 loop
            pragma Loop_Invariant
              (Count <= Capacity
               and then Sorted (Best, Count)
               and then All_Fit (Best, Count, Limit, 1.0));
            if Matches (Params.Edge_0_Polarity, Edges (A).C0) then
               for B in 0 .. Edge_Count - 1 loop
                  pragma Loop_Invariant
                    (Count <= Capacity
                     and then Sorted (Best, Count)
                     and then All_Fit (Best, Count, Limit, 1.0));
                  if Edges (B).T0 > Edges (A).T0
                    and then Matches (Params.Edge_1_Polarity, Edges (B).C0)
                  then
                     Item := (Key => 0.0,
                              T0  => Edges (A).T0, C0 => Edges (A).C0,
                              T1  => Edges (B).T0, C1 => Edges (B).C0);
                     Item.Key := Score (Params.Two_Edge_Scorers, Item, G,
                                        Expected);
                     Insert (Best, Count, Capacity, Limit, 1.0, Item);
                  end if;
               end loop;
            end if;
         end loop;
      end if;
   end Score_Candidates;

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   procedure Map_Edge
     (G                   : Geometry;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      T                   : Long_Float;
      X, Y                : out Long_Float;
      Status              : out Ks_Status)
   with
     Pre  => Valid_Geometry (G) and then KT.Bounded (Selected_From_Pixel)
             and then T >= 0.0 and then T <= Long_Float (G.Nx),
     Post => Checkable (Status)
             and then (if Succeeded (Status)
                       then In_Bound (X) and then In_Bound (Y));
   --  The selected-space point T steps along side X on the region's centre
   --  line. Bad_Parameter when it would exceed 1.0E150.

   procedure Map_Edge
     (G                   : Geometry;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      T                   : Long_Float;
      X, Y                : out Long_Float;
      Status              : out Ks_Status)
   is
      J : constant Long_Float := Long_Float (G.Ny) / 2.0;
   begin
      KT.Map_Point
        (Selected_From_Pixel,
         Coordinate_Of (G.O_X, T, J, G.Dx_X, G.Dy_X),
         Coordinate_Of (G.O_Y, T, J, G.Dx_Y, G.Dy_Y),
         X, Y, Status);
      if not Succeeded (Status) then
         X := 0.0;
         Y := 0.0;
         Bad (Status, "Caliper: a result point would exceed +/-1.0E150");
      end if;
   end Map_Edge;

   procedure Fill_Item
     (C                   : Candidate;
      Single              : Boolean;
      G                   : Geometry;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Item                : out Ks_Caliper_Result;
      Status              : out Ks_Status)
   with
     Pre  => Valid_Geometry (G) and then KT.Bounded (Selected_From_Pixel)
             and then Fits (C, Long_Float (G.Nx), 1.0),
     Post => Checkable (Status)
             and then (if Succeeded (Status)
                       then Item.Score = C.Key
                            and then Score_In_Range (Item)
                            and then Within (Item, G.Half)
                            and then Coordinates_In_Bound (Item));
   --  The result for candidate C.

   procedure Fill_Item
     (C                   : Candidate;
      Single              : Boolean;
      G                   : Geometry;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Item                : out Ks_Caliper_Result;
      Status              : out Ks_Status)
   is
      Mid : constant Long_Float := Midpoint (C.T0, C.T1);
   begin
      Item := (others => <>);
      Item.Score := C.Key;
      Item.Edge_0.Position := Position_Of (G, C.T0);
      Item.Edge_0.Contrast := C.C0;
      Map_Edge (G, Selected_From_Pixel, C.T0, Item.Edge_0.Position_X,
                Item.Edge_0.Position_Y, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Single then
         Item.Edge_1 := Item.Edge_0;
         Item.Position := Item.Edge_0.Position;
         Item.Position_X := Item.Edge_0.Position_X;
         Item.Position_Y := Item.Edge_0.Position_Y;
         Item.Width := 0.0;
      else
         Item.Edge_1.Position := Position_Of (G, C.T1);
         Item.Edge_1.Contrast := C.C1;
         Map_Edge (G, Selected_From_Pixel, C.T1, Item.Edge_1.Position_X,
                   Item.Edge_1.Position_Y, Status);
         if not Succeeded (Status) then
            return;
         end if;
         Item.Position := Position_Of (G, Mid);
         Map_Edge (G, Selected_From_Pixel, Mid, Item.Position_X,
                   Item.Position_Y, Status);
         if not Succeeded (Status) then
            return;
         end if;
         Item.Width := Width_Of (G, C.T1 - C.T0);
      end if;
   end Fill_Item;

   procedure Check_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status) then KI.Valid_Image (Image));

   procedure Check_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      if Image = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "InputImage has no pixels");
      elsif not KI.Valid_Image (Image) then
         Bad (Status, "InputImage is not a valid image handle");
      else
         Set_Success (Status);
      end if;
   end Check_Image;

   ---------------------------------------------------------------------
   --  Entry points: run parameters and scorers
   ---------------------------------------------------------------------

   procedure Run_Params_Default
     (Params : out Ks_Caliper_Run_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Run_Params_Default;

   procedure Scorer_Default
     (Kind   : Int32;
      Scorer : out Ks_Caliper_Scorer;
      Status : out Ks_Status) is
   begin
      Scorer := (others => <>);
      case Kind is
         when Scorer_Contrast =>
            null;
         when Scorer_Position | Scorer_Position_Neg =>
            Scorer := (Kind, True_Value, 10.0, 10.0, 0.0, 0.0, 1.0);
         when Scorer_Position_Norm | Scorer_Position_Norm_Neg =>
            Scorer := (Kind, True_Value, 1.0, 1.0, 0.0, 0.0, 1.0);
         when Scorer_Size_Norm =>
            Scorer := (Kind, True_Value, 1.0, 1.0, 1.0, 0.0, 1.0);
         when Scorer_Size_Diff_Norm | Scorer_Size_Diff_Norm_Asym =>
            Scorer := (Kind, True_Value, 1.0, 1.0, 0.0, 0.0, 1.0);
         when Scorer_Straddle =>
            Scorer := (Kind, True_Value, 1.0, 0.0, 1.0, 0.0, 1.0);
         when others =>
            Bad (Status, "Scorer kind must be in 0 .. 8");
            return;
      end case;
      Set_Success (Status);
   end Scorer_Default;

   procedure Scorer_Set_XY_Parameters
     (Scorer             : Ks_Caliper_Scorer;
      X0, X1, XC, Y0, Y1 : Long_Float;
      Result             : out Ks_Caliper_Scorer;
      Status             : out Ks_Status) is
   begin
      Result := Scorer;
      if not (X0 >= 0.0 and then X0 <= Max_Value) then
         Bad (Status, "SetXYParameters: x0 must be finite, >= 0 and"
                      & " <= 1.0E150");
      elsif not (X1 >= 0.0 and then X1 <= Max_Value) then
         Bad (Status, "SetXYParameters: x1 must be finite, >= 0 and"
                      & " <= 1.0E150");
      elsif not In_Bound (XC) then
         Bad (Status, "SetXYParameters: xc must be finite and within"
                      & " +/-1.0E150");
      elsif not (Y0 >= 0.0 and then Y0 <= 1.0) then
         Bad (Status, "SetXYParameters: y0 must be within [0, 1]");
      elsif not (Y1 >= 0.0 and then Y1 <= 1.0) then
         Bad (Status, "SetXYParameters: y1 must be within [0, 1]");
      else
         Result := (Scorer.Kind, Scorer.Enabled, X0, X1, XC, Y0, Y1);
         Set_Success (Status);
      end if;
   end Scorer_Set_XY_Parameters;

   procedure Scorers_Add
     (Scorers : in out Ks_Caliper_Scorers;
      Scorer  : Ks_Caliper_Scorer;
      Status  : out Ks_Status) is
   begin
      if Scorers.Count not in 0 .. Max_Scorers then
         Bad (Status, "Scorers.Count must be in 0 .. 8");
      elsif Scorers.Count = Max_Scorers then
         Bad (Status, "Add: the list already holds 8 scorers");
      else
         Scorers.Items (Integer (Scorers.Count)) := Scorer;
         Scorers.Count := Scorers.Count + 1;
         Set_Success (Status);
      end if;
   end Scorers_Add;

   procedure Scorers_Count
     (Scorers : Ks_Caliper_Scorers;
      Count   : out Int32;
      Status  : out Ks_Status) is
   begin
      Count := 0;
      if Scorers.Count not in 0 .. Max_Scorers then
         Bad (Status, "Scorers.Count must be in 0 .. 8");
      else
         Count := Scorers.Count;
         Set_Success (Status);
      end if;
   end Scorers_Count;

   procedure Scorer_Get_Kind
     (Scorer : Ks_Caliper_Scorer;
      Kind   : out Int32;
      Status : out Ks_Status) is
   begin
      Kind := Scorer_Contrast;
      if Scorer.Kind not in Scorer_Kind then
         Bad (Status, "Scorer.Kind must be a scorer kind code (0 .. 8)");
      else
         Kind := Scorer.Kind;
         Set_Success (Status);
      end if;
   end Scorer_Get_Kind;

   procedure Scorer_Get_Enabled
     (Scorer  : Ks_Caliper_Scorer;
      Enabled : out Int32;
      Status  : out Ks_Status) is
   begin
      Enabled := False_Value;
      if Scorer.Enabled not in False_Value | True_Value then
         Bad (Status, "Scorer.Enabled must be 0 or 1");
      else
         Enabled := Scorer.Enabled;
         Set_Success (Status);
      end if;
   end Scorer_Get_Enabled;

   procedure Scorers_Remove_At
     (Scorers : in out Ks_Caliper_Scorers;
      Index   : Int32;
      Status  : out Ks_Status) is
   begin
      if Scorers.Count not in 0 .. Max_Scorers then
         Bad (Status, "Scorers.Count must be in 0 .. 8");
      elsif Index not in 0 .. Scorers.Count - 1 then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "RemoveAt: index outside the list");
      else
         for I in Integer (Index) .. Integer (Scorers.Count) - 2 loop
            pragma Loop_Invariant
              (Scorers.Count = Scorers.Count'Loop_Entry);
            Scorers.Items (I) := Scorers.Items (I + 1);
         end loop;
         Scorers.Count := Scorers.Count - 1;
         Set_Success (Status);
      end if;
   end Scorers_Remove_At;

   procedure Check_Run_Params
     (Params : Ks_Caliper_Run_Params;
      Status : out Ks_Status) is
   begin
      Check_Params (Params, False, Status);
   end Check_Run_Params;

   procedure Check_Nested_Run_Params
     (Params : Ks_Caliper_Run_Params;
      Status : out Ks_Status) is
   begin
      Check_Params (Params, True, Status);
   end Check_Nested_Run_Params;

   ---------------------------------------------------------------------
   --  Entry points: running
   ---------------------------------------------------------------------

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : KS.Ks_Rectangle_Affine;
      Pixel_From_Region   : KT.Ks_Transform_2D_Linear;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Params              : Ks_Caliper_Run_Params;
      Results             : out Ks_Caliper_Results;
      Status              : out Ks_Status)
   is
      G          : Geometry;
      Projection : Value_Array_Access;
      Filtered   : Value_Array_Access;
      Edges      : Candidate_Array (0 .. Max_Edges - 1);
      Edge_Count : Natural;
      Best       : Candidate_Array (0 .. Max_Results_Limit - 1);
      Count      : Natural;
      Items      : Result_Array_Access;
      Single     : Boolean;
   begin
      Results := null;
      Check_Image (Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Params (Params, False, Status);
      if not Succeeded (Status) then
         return;
      elsif not KS.Valid_Rectangle_Affine (Region) then
         Bad (Status, "Region: every property must be finite and within"
                      & " its bound (1.0E150, side lengths 4.0E150, >= 0)");
         return;
      elsif not KT.Bounded (Pixel_From_Region) then
         Bad (Status, "Pixel_From_Region must be finite and within"
                      & " +/-1.0E150");
         return;
      elsif not KT.Bounded (Selected_From_Pixel) then
         Bad (Status, "Selected_From_Pixel must be finite and within"
                      & " +/-1.0E150");
         return;
      end if;
      Prepare_Geometry (Region, Pixel_From_Region, Selected_From_Pixel, G,
                        Status);
      if not Succeeded (Status) then
         return;
      end if;

      --  The profiles.
      Allocate_Values (G.Nx, Projection);
      if Projection = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Caliper: out of memory");
         return;
      end if;
      Allocate_Values (G.Nx, Filtered);
      if Filtered = null then
         Free (Projection);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Caliper: out of memory");
         return;
      end if;
      Project (Image, G, Projection.all);
      Filter (Projection.all, Filter_Size (Params.Filter_Half_Size_In_Pixels),
              Filtered.all);

      --  Edges and candidates.
      Find_Edges (Projection.all, Filtered.all, Params, Edges, Edge_Count);
      Score_Candidates (Edges, Edge_Count, Params, G, Best, Count);

      --  The results.
      Single := Params.Edge_Mode = Edge_Mode_Single_Edge;
      Items := null;
      if Count > 0 then
         Allocate_Items (Count, Items);
         if Items = null then
            Free (Projection);
            Free (Filtered);
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Caliper: out of memory");
            return;
         end if;
         for I in 0 .. Count - 1 loop
            pragma Loop_Invariant
              (Items /= null and then Items'First = 0
               and then Items'Last = Count - 1
               and then (for all J in 0 .. I - 1 =>
                           Score_In_Range (Items (J))
                           and then Within (Items (J), G.Half)
                           and then Coordinates_In_Bound (Items (J))
                           and then Items (J).Score = Best (J).Key));
            Fill_Item (Best (I), Single, G, Selected_From_Pixel, Items (I),
                       Status);
            if not Succeeded (Status) then
               Free (Items);
               Free (Projection);
               Free (Filtered);
               return;
            end if;
         end loop;
      end if;

      Allocate_Results (Results);
      if Results = null then
         Free (Items);
         Free (Projection);
         Free (Filtered);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Caliper: out of memory");
         return;
      end if;
      Results.Count := Count;
      Results.Items := Items;
      Results.Projection := Projection;
      Results.Filtered := Filtered;
      Results.Half_Length := G.Half;
      Set_Success (Status);
   end Execute;

   procedure Results_Destroy (Results : in out Ks_Caliper_Results) is
   begin
      if Results /= null then
         Free (Results.Items);
         Free (Results.Projection);
         Free (Results.Filtered);
         Free (Results);
      end if;
   end Results_Destroy;

   procedure Results_Duplicate
     (Results : access constant Ks_Caliper_Results_Data;
      Copy    : out Ks_Caliper_Results;
      Status  : out Ks_Status)
   is
      Items      : Result_Array_Access := null;
      Projection : Value_Array_Access;
      Filtered   : Value_Array_Access;
   begin
      Copy := null;
      if Results = null then
         Set_Success (Status);
         return;
      elsif not Valid_Results (Results) then
         Bad (Status, "Results is not a valid caliper results handle");
         return;
      end if;
      Allocate_Values (Results.Projection'Length, Projection);
      if Projection = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Duplicate: out of memory");
         return;
      end if;
      Projection.all := Results.Projection.all;
      Allocate_Values (Results.Filtered'Length, Filtered);
      if Filtered = null then
         Free (Projection);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Duplicate: out of memory");
         return;
      end if;
      Filtered.all := Results.Filtered.all;
      if Results.Count > 0 then
         Allocate_Items (Results.Count, Items);
         if Items = null then
            Free (Projection);
            Free (Filtered);
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Duplicate: out of memory");
            return;
         end if;
         Items.all := Results.Items.all;
      end if;
      Allocate_Results (Copy);
      if Copy = null then
         Free (Items);
         Free (Projection);
         Free (Filtered);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Duplicate: out of memory");
         return;
      end if;
      Copy.Count := Results.Count;
      Copy.Items := Items;
      Copy.Projection := Projection;
      Copy.Filtered := Filtered;
      Copy.Half_Length := Results.Half_Length;
      Set_Success (Status);
   end Results_Duplicate;

   procedure Results_Count
     (Results : access constant Ks_Caliper_Results_Data;
      Count   : out Int32;
      Status  : out Ks_Status) is
   begin
      Count := 0;
      if Results = null then
         Set_Success (Status);
      elsif not Valid_Results (Results) then
         Bad (Status, "Results is not a valid caliper results handle");
      else
         Count := Int32 (Results.Count);
         Set_Success (Status);
      end if;
   end Results_Count;

   procedure Results_Item
     (Results : access constant Ks_Caliper_Results_Data;
      Index   : Int32;
      Item    : out Ks_Caliper_Result;
      Status  : out Ks_Status) is
   begin
      Item := (others => <>);
      if Results /= null and then not Valid_Results (Results) then
         Bad (Status, "Results is not a valid caliper results handle");
      elsif Results = null or else Index < 0
        or else Index >= Int32 (Results.Count)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Item: index outside the results");
      else
         Item := Results.Items (Natural (Index));
         Set_Success (Status);
      end if;
   end Results_Item;

   procedure Results_Profile_Length
     (Results : access constant Ks_Caliper_Results_Data;
      Length  : out Int32;
      Status  : out Ks_Status) is
   begin
      Length := 0;
      if Results = null then
         Set_Success (Status);
      elsif not Valid_Results (Results) then
         Bad (Status, "Results is not a valid caliper results handle");
      else
         Length := Int32 (Results.Projection'Length);
         Set_Success (Status);
      end if;
   end Results_Profile_Length;

   procedure Profile_Value
     (Results  : access constant Ks_Caliper_Results_Data;
      Filtered : Boolean;
      Index    : Int32;
      Value    : out Long_Float;
      Status   : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then Value >= -255.0 and then Value <= 255.0;

   procedure Profile_Value
     (Results  : access constant Ks_Caliper_Results_Data;
      Filtered : Boolean;
      Index    : Int32;
      Value    : out Long_Float;
      Status   : out Ks_Status) is
   begin
      Value := 0.0;
      if Results /= null and then not Valid_Results (Results) then
         Bad (Status, "Results is not a valid caliper results handle");
      elsif Results = null or else Index < 0
        or else Index > Int32 (Results.Projection'Last)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Profile: index outside the profile");
      else
         Value := (if Filtered
                   then Read_Signed (Results.Filtered (Natural (Index)))
                   else Read_Grey (Results.Projection (Natural (Index))));
         Set_Success (Status);
      end if;
   end Profile_Value;

   procedure Results_Projection_Value
     (Results : access constant Ks_Caliper_Results_Data;
      Index   : Int32;
      Value   : out Long_Float;
      Status  : out Ks_Status) is
   begin
      Profile_Value (Results, False, Index, Value, Status);
   end Results_Projection_Value;

   procedure Results_Filtered_Value
     (Results : access constant Ks_Caliper_Results_Data;
      Index   : Int32;
      Value   : out Long_Float;
      Status  : out Ks_Status) is
   begin
      Profile_Value (Results, True, Index, Value, Status);
   end Results_Filtered_Value;

   procedure Get_Profile
     (Results  : access constant Ks_Caliper_Results_Data;
      Filtered : Boolean;
      Values   : out Value_Array;
      Status   : out Ks_Status) is
   begin
      Values := [others => 0.0];
      if Results = null then
         if Values'Length = 0 then
            Set_Success (Status);
         else
            Bad (Status, "Get_Profile: Values must be empty for no results");
         end if;
      elsif not Valid_Results (Results) then
         Bad (Status, "Results is not a valid caliper results handle");
      elsif Values'Length /= Results.Projection'Length then
         Bad (Status, "Get_Profile: Values must have the length of the"
                      & " profile");
      else
         for I in Values'Range loop
            Values (I) :=
              (if Filtered
               then Read_Signed (Results.Filtered (I - Values'First))
               else Read_Grey (Results.Projection (I - Values'First)));
         end loop;
         Set_Success (Status);
      end if;
   end Get_Profile;

end AMV.Kernels.Caliper;
