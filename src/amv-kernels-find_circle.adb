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

package body AMV.Kernels.Find_Circle with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;
   package KG renames AMV.Kernels.Geometry;
   package EF renames Ada.Numerics.Long_Elementary_Functions;

   procedure Free is new Ada.Unchecked_Deallocation
     (Item_Array, Item_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Caliper_Array, Caliper_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Find_Circle_Results_Data, Ks_Find_Circle_Results);

   No_Item : constant Ks_Find_Circle_Result := (others => <>);

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

   procedure Allocate_Results (Results : out Ks_Find_Circle_Results)
   with
     Global => null,
     Post   => (if Results /= null
                then Results.Items = null and then Results.Calipers = null);
   --  A new results record with the record's default values, or null.
   --  Trusted as above.

   procedure Allocate_Results (Results : out Ks_Find_Circle_Results)
     with SPARK_Mode => Off
   is
   begin
      Results := new Ks_Find_Circle_Results_Data;
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

   function Needed (P : Ks_Find_Circle_Run_Params) return Natural is
     (if P.Radius_Constraint_Enabled = True_Value then 2 else 3);
   --  The points the fit needs.

   function Valid_Params (P : Ks_Find_Circle_Run_Params) return Boolean is
     (P.Num_Calipers in 3 .. Max_Calipers
      and then P.Radius_Constraint_Enabled in False_Value | True_Value
      and then P.Num_To_Ignore in 0 .. P.Num_Calipers - Int32 (Needed (P))
      and then P.Decrement_Num_To_Ignore in False_Value | True_Value
      and then P.Caliper_Search_Direction
                 in Search_Direction_Inward | Search_Direction_Outward
      and then KS.Valid_Circular_Arc (P.Expected_Circular_Arc)
      and then P.Expected_Circular_Arc.Radius > 0.0
      and then P.Caliper_Search_Length > 0.0
      and then P.Caliper_Search_Length <= KS.Max_Length
      and then P.Caliper_Projection_Length > 0.0
      and then P.Caliper_Projection_Length <= KS.Max_Length
      and then (if P.Radius_Constraint_Enabled = True_Value
                then P.Radius_Constraint > 0.0
                     and then P.Radius_Constraint <= Max_Value));

   procedure Check_Params
     (Params : Ks_Find_Circle_Run_Params;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Valid_Params (Params));

   procedure Check_Params
     (Params : Ks_Find_Circle_Run_Params;
      Status : out Ks_Status) is
   begin
      if Params.Num_Calipers not in 3 .. Max_Calipers then
         Bad (Status, "RunParams.NumCalipers must be in 3 .. 1000");
      elsif Params.Radius_Constraint_Enabled not in False_Value | True_Value
      then
         Bad (Status, "RunParams.RadiusConstraintEnabled must be 0 or 1");
      elsif Params.Num_To_Ignore
              not in 0 .. Params.Num_Calipers - Int32 (Needed (Params))
      then
         Bad (Status, "RunParams.NumToIgnore must be in 0 .. NumCalipers - "
                      & (if Params.Radius_Constraint_Enabled = True_Value
                         then "2" else "3"));
      elsif Params.Decrement_Num_To_Ignore not in False_Value | True_Value
      then
         Bad (Status, "RunParams.DecrementNumToIgnore must be 0 or 1");
      elsif Params.Caliper_Search_Direction
              not in Search_Direction_Inward | Search_Direction_Outward
      then
         Bad (Status, "RunParams.CaliperSearchDirection must be Inward (0)"
                      & " or Outward (1)");
      elsif not KS.Valid_Circular_Arc (Params.Expected_Circular_Arc) then
         Bad (Status, "RunParams.ExpectedCircularArc: every property must"
                      & " be finite and within its bound");
      elsif not (Params.Expected_Circular_Arc.Radius > 0.0) then
         Bad (Status, "RunParams.ExpectedCircularArc.Radius must be > 0");
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
      elsif Params.Radius_Constraint_Enabled = True_Value
        and then not (Params.Radius_Constraint > 0.0
                      and then Params.Radius_Constraint <= Max_Value)
      then
         Bad (Status, "RunParams.RadiusConstraint must be > 0 and"
                      & " <= 1.0E150");
      else
         KC.Check_Nested_Run_Params (Params.Caliper_Run_Params, Status);
      end if;
   end Check_Params;

   function Unit_Cos (A : Long_Float) return Long_Float is
     (N.Clamp (EF.Cos (A), 1.0))
   with Post => abs Unit_Cos'Result <= 1.0;

   function Unit_Sin (A : Long_Float) return Long_Float is
     (N.Clamp (EF.Sin (A), 1.0))
   with Post => abs Unit_Sin'Result <= 1.0;

   procedure Region_Of
     (Params : Ks_Find_Circle_Run_Params;
      K      : Natural;
      Region : out KS.Ks_Rectangle_Affine;
      Status : out Ks_Status)
   with
     Pre  => Valid_Params (Params)
             and then K < Natural (Params.Num_Calipers),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then KS.Valid_Rectangle_Affine (Region));
   --  The region of caliper K; Bad_Parameter when its centre would lie
   --  beyond 1.0E150.

   procedure Region_Of
     (Params : Ks_Find_Circle_Run_Params;
      K      : Natural;
      Region : out KS.Ks_Rectangle_Affine;
      Status : out Ks_Status)
   is
      A      : KS.Ks_Circular_Arc renames Params.Expected_Circular_Arc;
      Count  : constant Long_Float := Long_Float (Params.Num_Calipers);
      Offset : Long_Float;
      Theta  : Long_Float;
      X, Y   : Long_Float;
   begin
      Region := (others => <>);
      if A.Angle_Span >= N.Two_Pi or else A.Angle_Span <= -N.Two_Pi then
         --  A full circle: NumCalipers steps of 2 Pi / NumCalipers.
         Offset := N.Times_Unit
           (N.Two_Pi, N.Unit_Ratio (Long_Float (K), Count));
         if A.Angle_Span < 0.0 then
            Offset := -Offset;
         end if;
      else
         Offset := N.Times_Unit
           (A.Angle_Span,
            N.Unit_Ratio (Long_Float (K),
                          Long_Float (Params.Num_Calipers - 1)));
      end if;
      Theta := N.Reduce_Two_Pi (N.Reduce_Two_Pi (A.Angle_Start) + Offset);
      X := A.Center_X + N.Times_Unit (A.Radius, Unit_Cos (Theta));
      Y := A.Center_Y + N.Times_Unit (A.Radius, Unit_Sin (Theta));
      if not (In_Bound (X) and then In_Bound (Y)) then
         Bad (Status, "RunParams.ExpectedCircularArc: caliper"
                      & " " & Image_Of (Int64 (K))
                      & " would lie beyond +/-1.0E150");
         return;
      end if;
      Region :=
        (Center_X      => X,
         Center_Y      => Y,
         Side_X_Length => Params.Caliper_Search_Length,
         Side_Y_Length => Params.Caliper_Projection_Length,
         Rotation      =>
           (if Params.Caliper_Search_Direction = Search_Direction_Outward
            then Theta else N.Reduce_Two_Pi (Theta + N.Pi)),
         Skew          => 0.0);
      Set_Success (Status);
   end Region_Of;

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
   --  The fixed-radius fit
   ---------------------------------------------------------------------

   subtype Point_Index is Integer range 0 .. Max_Calipers - 1;

   subtype Point_Buffer is KG.Point_Array (Point_Index);
   subtype Flag_Buffer is KG.Flag_Array (Point_Index);

   Cost_Limit : constant := 2.0 ** 1013;
   --  At least Max_Calipers squared residuals of at most 4.0E150 each
   --  (about 1.6E304).

   procedure Fixed_Fit
     (Points           : Point_Buffer;
      Count            : Natural;
      Active           : Flag_Buffer;
      Radius           : Long_Float;
      Start_X, Start_Y : Coordinate;
      Center_X         : out Coordinate;
      Center_Y         : out Coordinate;
      Cost             : out Long_Float)
   with
     Pre  => Count <= Max_Calipers
             and then Radius > 0.0 and then Radius <= Max_Value,
     Post => Cost >= 0.0 and then Cost <= Cost_Limit;
   --  The centre of the circle of the given radius that fits the active
   --  points among Points (0 .. Count - 1), starting from (Start_X,
   --  Start_Y) (see the spec), and the sum of the squared radial
   --  residuals. A centre beyond 1.0E150 is limited to it.

   procedure Fixed_Fit
     (Points           : Point_Buffer;
      Count            : Natural;
      Active           : Flag_Buffer;
      Radius           : Long_Float;
      Start_X, Start_Y : Coordinate;
      Center_X         : out Coordinate;
      Center_Y         : out Coordinate;
      Cost             : out Long_Float)
   is
      Sum_Limit : constant := 2.0 ** 520;
      --  At least Max_Calipers terms of at most 2.0E150 (2.0E153).
      X, Y      : Coordinate;
      SX, SY    : Long_Float;
      M         : Natural;
      DX, DY, D : Long_Float;
      UX, UY    : Long_Float;
      PX, PY    : Coordinate;
      New_X     : Coordinate;
      New_Y     : Coordinate;
      Move      : Long_Float;
      Residual  : Long_Float;
   begin
      X := Start_X;
      Y := Start_Y;
      for Iteration in 1 .. Max_Iterations loop
         SX := 0.0;
         SY := 0.0;
         M := 0;
         for I in 0 .. Count - 1 loop
            pragma Loop_Invariant
              (abs SX <= Sum_Limit and then abs SY <= Sum_Limit
               and then M <= I);
            if Active (I) then
               PX := Read (Points (I).X);
               PY := Read (Points (I).Y);
               DX := PX - X;
               DY := PY - Y;
               D := N.Hypot (DX, DY);
               if D > 0.0 then
                  UX := N.Unit_Ratio (N.Clamp (DX, D), D);
                  UY := N.Unit_Ratio (N.Clamp (DY, D), D);
               else
                  UX := 1.0;
                  UY := 0.0;
               end if;
               --  Both sums stay below the limit, which never acts.
               SX := N.Clamp (SX + (PX - N.Times_Unit (Radius, UX)),
                              Sum_Limit);
               SY := N.Clamp (SY + (PY - N.Times_Unit (Radius, UY)),
                              Sum_Limit);
               M := M + 1;
            end if;
         end loop;
         exit when M = 0;
         New_X := N.Clamp (SX / Long_Float (M), Max_Value);
         New_Y := N.Clamp (SY / Long_Float (M), Max_Value);
         Move := N.Hypot (New_X - X, New_Y - Y);
         X := New_X;
         Y := New_Y;
         exit when Move <= 1.0E-12 * Radius;
      end loop;
      Center_X := X;
      Center_Y := Y;

      Cost := 0.0;
      for I in 0 .. Count - 1 loop
         pragma Loop_Invariant (Cost >= 0.0 and then Cost <= Cost_Limit);
         if Active (I) then
            PX := Read (Points (I).X);
            PY := Read (Points (I).Y);
            --  The distance is at most 4.0E150 (Hypot of two differences
            --  of at most 2.0E150), the residual too.
            Residual := Long_Float'Min (N.Hypot (PX - X, PY - Y), 4.0E150)
                        - Radius;
            Cost := Long_Float'Min
              (Cost + N.Square_Within (Residual, 4.0E150), Cost_Limit);
         end if;
      end loop;
   end Fixed_Fit;

   procedure Fixed_Fit_Robust
     (Points           : Point_Buffer;
      Count            : Natural;
      Num_To_Ignore    : Natural;
      Radius           : Long_Float;
      Start_X, Start_Y : Coordinate;
      Center_X         : out Coordinate;
      Center_Y         : out Coordinate;
      Cost             : out Long_Float;
      Used             : out Flag_Buffer)
   with
     Pre  => Count <= Max_Calipers and then Num_To_Ignore <= Count
             and then Radius > 0.0 and then Radius <= Max_Value,
     Post => Cost >= 0.0 and then Cost <= Cost_Limit
             and then (for all I in Point_Index =>
                         (if Used (I) then I < Count));
   --  Fixed_Fit after discarding Num_To_Ignore points one at a time, each
   --  time the point whose removal gives the smallest cost (ties: the
   --  lowest index). Used tells the points kept.

   procedure Fixed_Fit_Robust
     (Points           : Point_Buffer;
      Count            : Natural;
      Num_To_Ignore    : Natural;
      Radius           : Long_Float;
      Start_X, Start_Y : Coordinate;
      Center_X         : out Coordinate;
      Center_Y         : out Coordinate;
      Cost             : out Long_Float;
      Used             : out Flag_Buffer)
   is
      Best      : Integer;
      Best_Cost : Long_Float;
      Best_X    : Coordinate;
      Best_Y    : Coordinate;
      Trial     : Long_Float;
      TX, TY    : Coordinate;
   begin
      Used := [others => False];
      for I in 0 .. Count - 1 loop
         Used (I) := True;
         pragma Loop_Invariant
           (for all J in Point_Index => (if Used (J) then J <= I));
      end loop;
      Fixed_Fit (Points, Count, Used, Radius, Start_X, Start_Y, Center_X,
                 Center_Y, Cost);
      --  Each step tries the fit without each point in turn (from the
      --  current centre) and keeps the best of those fits.
      for Step in 1 .. Num_To_Ignore loop
         pragma Loop_Invariant
           (Cost >= 0.0 and then Cost <= Cost_Limit
            and then (for all J in Point_Index =>
                        (if Used (J) then J < Count)));
         Best := -1;
         Best_Cost := 0.0;
         Best_X := Center_X;
         Best_Y := Center_Y;
         for J in 0 .. Count - 1 loop
            pragma Loop_Invariant
              (Best in -1 .. J - 1
               and then Best_Cost >= 0.0 and then Best_Cost <= Cost_Limit
               and then (for all I in Point_Index =>
                           (if Used (I) then I < Count)));
            if Used (J) then
               Used (J) := False;
               Fixed_Fit (Points, Count, Used, Radius, Center_X, Center_Y,
                          TX, TY, Trial);
               Used (J) := True;
               if Best = -1 or else Trial < Best_Cost then
                  Best := J;
                  Best_Cost := Trial;
                  Best_X := TX;
                  Best_Y := TY;
               end if;
            end if;
         end loop;
         if Best >= 0 then
            Used (Best) := False;
            Center_X := Best_X;
            Center_Y := Best_Y;
            Cost := Best_Cost;
         end if;
      end loop;
   end Fixed_Fit_Robust;

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Run_Params_Default
     (Params : out Ks_Find_Circle_Run_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Run_Params_Default;

   procedure Caliper_Region
     (Params : Ks_Find_Circle_Run_Params;
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
      Region_Of (Params, Natural (Index), Region, Status);
   end Caliper_Region;

   function Arc_Of
     (Circle : KS.Ks_Circle;
      Points : Point_Buffer;
      Used   : Flag_Buffer;
      Found  : Natural) return KS.Ks_Circular_Arc
   with
     Pre  => KS.Valid_Circle (Circle) and then Circle.Radius <= Max_Value
             and then Found <= Max_Calipers,
     Post => KS.Valid_Circular_Arc (Arc_Of'Result);
   --  Circle from the angle of the first used point (in caliper order)
   --  through the sum of the angle steps between consecutive used points.

   function Arc_Of
     (Circle : KS.Ks_Circle;
      Points : Point_Buffer;
      Used   : Flag_Buffer;
      Found  : Natural) return KS.Ks_Circular_Arc
   is
      Have     : Boolean := False;
      Start    : Long_Float := 0.0;
      Previous : Long_Float := 0.0;
      Span     : Long_Float := 0.0;
      Angle    : Long_Float;
      DX, DY   : Long_Float;
   begin
      for J in 0 .. Found - 1 loop
         pragma Loop_Invariant
           (Start > -N.Pi and then Start <= N.Pi
            and then Previous > -N.Pi and then Previous <= N.Pi
            and then abs Span <= 4000.0);
         if Used (J) then
            DX := Read (Points (J).X) - Circle.Center_X;
            DY := Read (Points (J).Y) - Circle.Center_Y;
            Angle := (if DX /= 0.0 or else DY /= 0.0
                      then N.Direction (DY, DX) else Previous);
            if Have then
               --  At most Max_Calipers steps of at most Pi: the limit never
               --  acts.
               Span := N.Clamp
                 (Span + N.Reduce_Two_Pi (Angle - Previous), 4000.0);
            else
               Start := Angle;
               Have := True;
            end if;
            Previous := Angle;
         end if;
      end loop;
      return (Circle.Center_X, Circle.Center_Y, Circle.Radius, Start, Span);
   end Arc_Of;

   procedure Expected_Centre
     (Params              : Ks_Find_Circle_Run_Params;
      Pixel_From_Arc      : KT.Ks_Transform_2D_Linear;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Points              : Point_Buffer;
      Count               : Natural;
      X, Y                : out Coordinate)
   with Pre => Count in 1 .. Max_Calipers;
   --  The expected arc's centre in the selected space, or the centroid of
   --  Points (0 .. Count - 1) when it cannot be mapped.

   procedure Expected_Centre
     (Params              : Ks_Find_Circle_Run_Params;
      Pixel_From_Arc      : KT.Ks_Transform_2D_Linear;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Points              : Point_Buffer;
      Count               : Natural;
      X, Y                : out Coordinate)
   is
      PX, PY, SX, SY : Long_Float;
      S              : Ks_Status;
   begin
      KT.Map_Point (Pixel_From_Arc, Params.Expected_Circular_Arc.Center_X,
                    Params.Expected_Circular_Arc.Center_Y, PX, PY, S);
      if Succeeded (S) then
         KT.Map_Point (Selected_From_Pixel, PX, PY, SX, SY, S);
         if Succeeded (S) then
            X := SX;
            Y := SY;
            return;
         end if;
      end if;
      --  The centroid; the sums of at most 1000 coordinates of at most
      --  1.0E150 stay below 2**510, which never acts.
      SX := 0.0;
      SY := 0.0;
      for I in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (abs SX <= 2.0 ** 510 and then abs SY <= 2.0 ** 510);
         SX := N.Clamp (SX + Read (Points (I).X), 2.0 ** 510);
         SY := N.Clamp (SY + Read (Points (I).Y), 2.0 ** 510);
      end loop;
      X := N.Clamp (SX / Long_Float (Count), Max_Value);
      Y := N.Clamp (SY / Long_Float (Count), Max_Value);
   end Expected_Centre;

   ---------------------------------------------------------------------
   --  The curvature correction
   ---------------------------------------------------------------------

   procedure Sag_Of
     (Params              : Ks_Find_Circle_Run_Params;
      Pixel_From_Arc      : KT.Ks_Transform_2D_Linear;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Radius              : Long_Float;
      Sag                 : out Long_Float)
   with
     Pre  => Valid_Params (Params)
             and then Radius >= 0.0 and then Radius <= Max_Value,
     Post => Sag >= 0.0 and then Sag <= Max_Value;
   --  How far, on average, a circle of the given radius (in the selected
   --  space) bends towards its centre across a caliper:
   --  L**2 / (24 Radius), L the projection length mapped into the
   --  selected space (its square is the area MapArea gives the square of
   --  the projection length in the arc's space, through Selected_From_Pixel
   --  after Pixel_From_Arc). At most Radius / 6 (L = 2 Radius); 0 for a
   --  radius below 1.0E-100, a projection length above 1.0E70 or a
   --  composition or area beyond the bounds.

   procedure Sag_Of
     (Params              : Ks_Find_Circle_Run_Params;
      Pixel_From_Arc      : KT.Ks_Transform_2D_Linear;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Radius              : Long_Float;
      Sag                 : out Long_Float)
   is
      L     : constant Long_Float := Params.Caliper_Projection_Length;
      T     : KT.Ks_Transform_2D_Linear;
      Area  : Long_Float;
      Limit : Long_Float;
      S     : Ks_Status;
   begin
      Sag := 0.0;
      if Radius < 1.0E-100 or else L > 1.0E70 then
         return;
      end if;
      KT.Compose (Selected_From_Pixel, Pixel_From_Arc, T, S);
      if not Succeeded (S) then
         return;
      end if;
      KT.Map_Area (T, L * L, Area, S);
      if not Succeeded (S) then
         return;
      end if;
      --  4 Radius**2 is in [4.0E-200, 4.0E300]; the area is limited to it
      --  (L = 2 Radius), so the ratio is in [0, 1].
      Limit := 4.0 * (Radius * Radius);
      Sag := N.Times_Unit
        (Radius / 6.0,
         N.Clamp_Unit (N.Unit_Ratio (Long_Float'Min (abs Area, Limit),
                                     Limit)));
   end Sag_Of;

   procedure Shift
     (Points           : in out Point_Buffer;
      Count            : Natural;
      Center_X         : Coordinate;
      Center_Y         : Coordinate;
      Distance         : Long_Float)
   with
     Pre => Count <= Max_Calipers
            and then Distance >= 0.0 and then Distance <= Max_Value;
   --  Moves each of Points (0 .. Count - 1) by Distance away from the
   --  centre (a point at the centre stays), within +/-1.0E150.

   procedure Shift
     (Points           : in out Point_Buffer;
      Count            : Natural;
      Center_X         : Coordinate;
      Center_Y         : Coordinate;
      Distance         : Long_Float)
   is
      PX, PY : Coordinate;
      DX, DY : Long_Float;
      D      : Long_Float;
   begin
      for I in 0 .. Count - 1 loop
         PX := Read (Points (I).X);
         PY := Read (Points (I).Y);
         DX := PX - Center_X;
         DY := PY - Center_Y;
         D := N.Hypot (DX, DY);
         if D > 0.0 then
            Points (I) :=
              (Read (PX + N.Times_Unit
                            (Distance, N.Unit_Ratio (N.Clamp (DX, D), D))),
               Read (PY + N.Times_Unit
                            (Distance, N.Unit_Ratio (N.Clamp (DY, D), D))));
         end if;
      end loop;
   end Shift;

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Params              : Ks_Find_Circle_Run_Params;
      Pixel_From_Arc      : KT.Ks_Transform_2D_Linear;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : out Ks_Find_Circle_Results;
      Status              : out Ks_Status)
   is
      Count     : Natural;
      Points    : Point_Buffer := [others => (0.0, 0.0)];
      Index_Of  : array (Point_Index) of Natural := [others => 0];
      Used      : Flag_Buffer := [others => False];
      Found     : Natural := 0;
      Ignore    : Natural;
      Region    : KS.Ks_Rectangle_Affine;
      Caliper   : KC.Ks_Caliper_Results;
      Circle    : KS.Ks_Circle;
      Arc       : KS.Ks_Circular_Arc;
      RMS       : Long_Float;
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
      elsif not KT.Bounded (Pixel_From_Arc) then
         Bad (Status, "Pixel_From_Arc must be finite and within"
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
                      "FindCircle: out of memory");
         return;
      end if;
      Allocate_Items (Count, Results.Items);
      Allocate_Calipers (Count, Results.Calipers);
      if Results.Items = null or else Results.Calipers = null then
         Results_Destroy (Results);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "FindCircle: out of memory");
         return;
      end if;
      Results.Count := Count;

      --  Run the calipers.
      for K in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (Results /= null and then Results.Count = Count
            and then Results.Items /= null and then Results.Calipers /= null
            and then Results.Items'First = 0
            and then Results.Items'Last = Count - 1
            and then Results.Calipers'First = 0
            and then Results.Calipers'Last = Count - 1
            and then Found <= K and then Caliper = null
            and then (for all I in 0 .. K - 1 => Results.Calipers (I) /= null)
            and then (for all I in K .. Count - 1 =>
                        Results.Calipers (I) = null)
            and then (for all I in K .. Count - 1 =>
                        Results.Items (I) = No_Item)
            and then (for all I in 0 .. Count - 1 =>
                        Results.Items (I).Used = False_Value
                        and then Results.Items (I).Found
                                   in False_Value | True_Value
                        and then Results.Items (I).Distance_To_Circle = 0.0)
            and then (for all J in 0 .. Found - 1 =>
                        Index_Of (J) < K
                        and then Results.Items (Index_Of (J)).Found
                                   = True_Value));
         Region_Of (Params, K, Region, Status);
         if Succeeded (Status) then
            KC.Execute (Image, Region, Pixel_From_Arc, Selected_From_Pixel,
                        Params.Caliper_Run_Params, Caliper, Status);
         else
            Caliper := null;
         end if;
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

      --  Fit the circle.
      Ignore := Natural (Params.Num_To_Ignore);
      if Found < Ignore + Needed (Params) then
         if Params.Decrement_Num_To_Ignore = True_Value
           and then Found >= Needed (Params)
         then
            Ignore := Found - Needed (Params);
         else
            Results_Destroy (Results);
            Set_Failure
              (Status, Failure_Other,
               "FindCircle: fewer than " & Image_Of (Int64 (Needed (Params)))
               & " points remain to fit (NumPointsFound = "
               & Image_Of (Int64 (Found)) & ", NumToIgnore = "
               & Image_Of (Int64 (Params.Num_To_Ignore)) & ")");
            return;
         end if;
      end if;

      --  Each fit runs twice: the second on the points moved away from the
      --  first fit's centre by the curvature correction (see the spec).
      if Params.Radius_Constraint_Enabled = True_Value then
         declare
            Start_X, Start_Y : Coordinate;
            CX, CY           : Coordinate;
            Cost             : Long_Float;
            Mean             : Long_Float;
            Sag              : Long_Float;
         begin
            Expected_Centre (Params, Pixel_From_Arc, Selected_From_Pixel,
                             Points, Found, Start_X, Start_Y);
            Fixed_Fit_Robust (Points, Found, Ignore,
                              Params.Radius_Constraint, Start_X, Start_Y,
                              CX, CY, Cost, Used);
            Sag_Of (Params, Pixel_From_Arc, Selected_From_Pixel,
                    Params.Radius_Constraint, Sag);
            if Sag > 0.0 then
               Shift (Points, Found, CX, CY, Sag);
               Start_X := CX;
               Start_Y := CY;
               Fixed_Fit_Robust (Points, Found, Ignore,
                                 Params.Radius_Constraint, Start_X, Start_Y,
                                 CX, CY, Cost, Used);
            end if;
            Circle := (CX, CY, Params.Radius_Constraint);
            pragma Assert (KS.Valid_Circle (Circle)
                           and then Circle.Radius <= Max_Value);
            Mean := Cost / Long_Float (Found - Ignore);
            --  The mean squared residual is at most 1.6E301; its root
            --  at most 4.0E150 (the limit never acts).
            RMS := Long_Float'Min
              (Long_Float'Max (EF.Sqrt (Mean), 0.0), 4.0E150);
         end;
      else
         declare
            Fitted : KG.Ks_Circle_2D;
            Sag    : Long_Float;
         begin
            KG.Fit_Circle_Robust
              (Points (0 .. Found - 1), Int32 (Ignore), Fitted, RMS,
               Used (0 .. Found - 1), Status);
            if not Succeeded (Status) then
               Results_Destroy (Results);
               return;
            end if;
            Sag_Of (Params, Pixel_From_Arc, Selected_From_Pixel,
                    Fitted.Radius, Sag);
            if Sag > 0.0 then
               Shift (Points, Found, Fitted.Center_X, Fitted.Center_Y, Sag);
               KG.Fit_Circle_Robust
                 (Points (0 .. Found - 1), Int32 (Ignore), Fitted, RMS,
                  Used (0 .. Found - 1), Status);
               if not Succeeded (Status) then
                  Results_Destroy (Results);
                  return;
               end if;
            end if;
            Circle := (Fitted.Center_X, Fitted.Center_Y, Fitted.Radius);
            pragma Assert (KS.Valid_Circle (Circle)
                           and then Circle.Radius <= Max_Value);
         end;
      end if;
      if RMS > Max_Value then
         Results_Destroy (Results);
         Bad (Status, "FindCircle: the RMS error would exceed 1.0E150");
         return;
      end if;

      --  Mark the used items; every found item takes its corrected point.
      for J in 0 .. Found - 1 loop
         pragma Loop_Invariant
           (Results /= null and then Results.Count = Count
            and then Results.Calipers /= null
            and then Results.Calipers'First = 0
            and then Results.Calipers'Last = Count - 1
            and then (for all I in 0 .. Count - 1 =>
                        Results.Calipers (I) /= null)
            and then Results.Items /= null
            and then Results.Items'First = 0
            and then Results.Items'Last = Count - 1
            and then (for all I in 0 .. Count - 1 =>
                        Results.Items (I).Found in False_Value | True_Value
                        and then Results.Items (I).Used
                                   in False_Value | True_Value
                        and then (if Results.Items (I).Used = True_Value
                                  then Results.Items (I).Found = True_Value)
                        and then Results.Items (I).Distance_To_Circle = 0.0)
            and then (for all J2 in 0 .. Found - 1 =>
                        Index_Of (J2) < Count
                        and then Results.Items (Index_Of (J2)).Found
                                   = True_Value));
         Results.Items (Index_Of (J)).X := Points (J).X;
         Results.Items (Index_Of (J)).Y := Points (J).Y;
         if Used (J) then
            Results.Items (Index_Of (J)).Used := True_Value;
         end if;
      end loop;

      --  Distances from the circle.
      declare
         C2D      : constant KG.Ks_Circle_2D :=
           (Circle.Center_X, Circle.Center_Y, Circle.Radius);
         Distance : Long_Float;
         S        : Ks_Status;
      begin
         for J in 0 .. Found - 1 loop
            pragma Loop_Invariant
              (Results /= null and then Results.Count = Count
               and then Results.Calipers /= null
               and then Results.Calipers'First = 0
               and then Results.Calipers'Last = Count - 1
               and then (for all I in 0 .. Count - 1 =>
                           Results.Calipers (I) /= null)
               and then Results.Items /= null
               and then Results.Items'First = 0
               and then Results.Items'Last = Count - 1
               and then (for all I in 0 .. Count - 1 =>
                           Results.Items (I).Found
                             in False_Value | True_Value
                           and then Results.Items (I).Used
                                      in False_Value | True_Value
                           and then (if Results.Items (I).Used = True_Value
                                     then Results.Items (I).Found
                                            = True_Value)
                           and then Results.Items (I).Distance_To_Circle
                                      >= 0.0
                           and then Results.Items (I).Distance_To_Circle
                                      <= Max_Value)
               and then (for all J2 in 0 .. Found - 1 =>
                           Index_Of (J2) < Count));
            KG.Circle_Distance
              ((Read (Points (J).X), Read (Points (J).Y)), C2D, Distance, S);
            Results.Items (Index_Of (J)).Distance_To_Circle :=
              (if Succeeded (S) then Distance else 0.0);
         end loop;
      end;
      Arc := Arc_Of (Circle, Points, Used, Found);

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

      Results.Circle := Circle;
      Results.Arc := Arc;
      Results.RMS_Error := RMS;
      Results.Num_Points_Found := Num_Found;
      Results.Num_Points_Used := Num_Used;
      Set_Success (Status);
   end Execute;

   procedure Results_Destroy (Results : in out Ks_Find_Circle_Results) is
   begin
      if Results /= null then
         Free (Results.Items);
         Free_Calipers (Results.Calipers);
         Free (Results);
      end if;
   end Results_Destroy;

   procedure Results_Count
     (Results : access constant Ks_Find_Circle_Results_Data;
      Count   : out Int32;
      Status  : out Ks_Status) is
   begin
      Count := 0;
      if Results = null then
         Set_Success (Status);
      elsif not Valid_Results (Results) then
         Bad (Status, "Results is not a valid find circle results handle");
      else
         Count := Int32 (Results.Count);
         Set_Success (Status);
      end if;
   end Results_Count;

   procedure Results_Item
     (Results : access constant Ks_Find_Circle_Results_Data;
      Index   : Int32;
      Item    : out Ks_Find_Circle_Result;
      Status  : out Ks_Status) is
   begin
      Item := No_Item;
      if Results /= null and then not Valid_Results (Results) then
         Bad (Status, "Results is not a valid find circle results handle");
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
         Bad (Status, "Results is not a valid find circle results handle");
      else
         Item := Results.Items (Natural (Index));
         Set_Success (Status);
      end if;
   end Results_Item;

   procedure Results_Caliper_Results
     (Results : access constant Ks_Find_Circle_Results_Data;
      Index   : Int32;
      Copy    : out KC.Ks_Caliper_Results;
      Status  : out Ks_Status) is
   begin
      Copy := null;
      if Results /= null and then not Valid_Results (Results) then
         Bad (Status, "Results is not a valid find circle results handle");
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

   procedure Results_Circle
     (Results : access constant Ks_Find_Circle_Results_Data;
      Circle  : out KS.Ks_Circle;
      Arc     : out KS.Ks_Circular_Arc;
      Status  : out Ks_Status) is
   begin
      Circle := (others => <>);
      Arc := (others => <>);
      if Results = null then
         Bad (Status, "Results has no circle");
      elsif not Valid_Results (Results)
        or else not KS.Valid_Circle (Results.Circle)
        or else not KS.Valid_Circular_Arc (Results.Arc)
      then
         Bad (Status, "Results is not a valid find circle results handle");
      else
         Circle := Results.Circle;
         Arc := Results.Arc;
         Set_Success (Status);
      end if;
   end Results_Circle;

   procedure Results_Fit
     (Results          : access constant Ks_Find_Circle_Results_Data;
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
         Bad (Status, "Results is not a valid find circle results handle");
      else
         RMS_Error := Results.RMS_Error;
         Num_Points_Found := Int32 (Results.Num_Points_Found);
         Num_Points_Used := Int32 (Results.Num_Points_Used);
         Set_Success (Status);
      end if;
   end Results_Fit;

end AMV.Kernels.Find_Circle;
