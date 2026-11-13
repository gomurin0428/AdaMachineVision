pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;

with AMV.Kernels.Dimensioning.Ellipses;
with AMV.Kernels.Dimensioning.Fit_Ellipse;
with AMV.Kernels.Dimensioning.Planar;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Dimensioning.Fitting with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);

   use type KS.Ks_Line;
   use type KS.Ks_Circle;
   use type KS.Ks_Ellipse;

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package EL renames AMV.Kernels.Dimensioning.Ellipses;
   package FE renames AMV.Kernels.Dimensioning.Fit_Ellipse;
   package N renames AMV.Kernels.Numerics;
   package P renames AMV.Kernels.Dimensioning.Planar;

   subtype Coordinate is P.Coordinate;

   procedure Free is new Ada.Unchecked_Deallocation
     (KG.Point_Array, Point_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (KG.Flag_Array, Flag_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Value_Array, Value_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Fit_Result_Data, Ks_Fit_Result);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Points
     (Count  : Positive;
      Points : out Point_Array_Access)
   with
     Global => null,
     Post   => (if Points /= null
                then Points'First = 0 and then Points'Last = Count - 1);
   --  A new array of Count points (0, 0), or null when the memory cannot
   --  be allocated. Trusted: the allocator raises Storage_Error, which
   --  SPARK cannot express.

   procedure Allocate_Points
     (Count  : Positive;
      Points : out Point_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Points := new KG.Point_Array (0 .. Count - 1);
   exception
      when Storage_Error =>
         Points := null;
   end Allocate_Points;

   procedure Allocate_Flags
     (Count : Positive;
      Flags : out Flag_Array_Access)
   with
     Global => null,
     Post   => (if Flags /= null
                then Flags'First = 0 and then Flags'Last = Count - 1);
   --  A new array of Count False flags, or null. Trusted as above.

   procedure Allocate_Flags
     (Count : Positive;
      Flags : out Flag_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Flags := new KG.Flag_Array'(0 .. Count - 1 => False);
   exception
      when Storage_Error =>
         Flags := null;
   end Allocate_Flags;

   procedure Allocate_Values
     (Count  : Positive;
      Values : out Value_Array_Access)
   with
     Global => null,
     Post   => (if Values /= null
                then Values'First = 0 and then Values'Last = Count - 1);
   --  A new array of Count zeros, or null. Trusted as above.

   procedure Allocate_Values
     (Count  : Positive;
      Values : out Value_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Values := new Value_Array'(0 .. Count - 1 => 0.0);
   exception
      when Storage_Error =>
         Values := null;
   end Allocate_Values;

   procedure Allocate_Result (Result : out Ks_Fit_Result)
   with
     Global => null,
     Post   => (if Result /= null
                then Result.Points = null and then Result.Used = null
                     and then Result.Distances = null);
   --  A new result record with the record's default values, or null.
   --  Trusted as above.

   procedure Allocate_Result (Result : out Ks_Fit_Result)
     with SPARK_Mode => Off
   is
   begin
      Result := new Ks_Fit_Result_Data;
   exception
      when Storage_Error =>
         Result := null;
   end Allocate_Result;

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
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad
     (Status  : out Ks_Status;
      Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   function Read (X : Long_Float) return Coordinate is
     (N.Clamp (X, Max_Value));
   --  A coordinate of a stored point, limited to the bound (the points
   --  come from a polygon handle, whose vertices lie within it, so this
   --  never acts).

   function Point_Of (Q : KG.Ks_Point_2D) return P.Point is
     ((Read (Q.X), Read (Q.Y)));

   procedure Check_Handle
     (Points : access constant KS.Ks_Polygon_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Points = null
                               or else KS.Valid_Polygon (Points));

   procedure Check_Handle
     (Points : access constant KS.Ks_Polygon_Data;
      Status : out Ks_Status) is
   begin
      if Points /= null and then not KS.Valid_Polygon (Points) then
         Bad (Status, "Points is not a valid point list handle");
      else
         Set_Success (Status);
      end if;
   end Check_Handle;

   procedure Check_Index
     (Points : access constant KS.Ks_Polygon_Data;
      Index  : Int32;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Index_Out_Of_Range
                and then (if Succeeded (Status)
                          then KS.Valid_Polygon (Points)
                               and then Index
                                          in 0 .. Int32 (Points.Count) - 1);

   procedure Check_Index
     (Points : access constant KS.Ks_Polygon_Data;
      Index  : Int32;
      Status : out Ks_Status) is
   begin
      Check_Handle (Points, Status);
      if Succeeded (Status)
        and then (Points = null
                  or else Index not in 0 .. Int32 (Points.Count) - 1)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Index must be in 0 .. NumPoints - 1");
      end if;
   end Check_Index;

   procedure Check_Coordinate
     (Value  : Long_Float;
      Name   : String;
      Status : out Ks_Status)
   with Pre  => Name'First = 1 and then Name'Length <= 10,
        Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status) then Bounded (Value));

   procedure Check_Coordinate
     (Value  : Long_Float;
      Name   : String;
      Status : out Ks_Status) is
   begin
      if Bounded (Value) then
         Set_Success (Status);
      else
         Bad (Status, Name & " must be finite and within +/-1.0E150");
      end if;
   end Check_Coordinate;

   ---------------------------------------------------------------------
   --  The points
   ---------------------------------------------------------------------

   procedure Points_Num_Points
     (Points : access constant KS.Ks_Polygon_Data;
      Count  : out Int32;
      Status : out Ks_Status) is
   begin
      Count := 0;
      Check_Handle (Points, Status);
      if Succeeded (Status) then
         Count := Int32 (KS.Count_Of (Points));
      end if;
   end Points_Num_Points;

   procedure Points_Set_Num_Points
     (Points : in out KS.Ks_Polygon;
      Count  : Int32;
      Status : out Ks_Status)
   is
      Old_Count : Natural;
      S         : Ks_Status;
   begin
      if Count not in 0 .. Max_Points then
         Bad (Status, "NumPoints must be in 0 .. 1048576");
         return;
      end if;
      Check_Handle (Points, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Old_Count := KS.Count_Of (Points);
      if Natural (Count) <= Old_Count then
         --  Remove points from the end.
         for K in reverse Natural (Count) .. Old_Count - 1 loop
            pragma Loop_Invariant (KS.Count_Of (Points) = K + 1);
            KS.Remove_Vertex (Points, Int32 (K), S);
            if not Succeeded (S) then
               Bad (Status, "NumPoints: the point list could not be"
                            & " shortened");
               return;
            end if;
         end loop;
      else
         --  Append points (0, 0).
         for K in Old_Count .. Natural (Count) - 1 loop
            pragma Loop_Invariant (KS.Count_Of (Points) = K);
            KS.Add_Vertex (Points, 0.0, 0.0, KS.Append_Index, S);
            if not Succeeded (S) then
               Set_Failure (Status, Failure_Out_Of_Memory,
                            "NumPoints: not enough memory");
               --  Remove what was added.
               for J in reverse Old_Count .. K - 1 loop
                  KS.Remove_Vertex (Points, Int32 (J), S);
                  exit when not Succeeded (S);
               end loop;
               return;
            end if;
         end loop;
      end if;
      Set_Success (Status);
   end Points_Set_Num_Points;

   procedure Points_Add_Point
     (Points : in out KS.Ks_Polygon;
      X, Y   : Long_Float;
      Status : out Ks_Status) is
   begin
      Check_Coordinate (X, "X", Status);
      if Succeeded (Status) then
         Check_Coordinate (Y, "Y", Status);
      end if;
      if Succeeded (Status) then
         Check_Handle (Points, Status);
      end if;
      if not Succeeded (Status) then
         return;
      elsif KS.Count_Of (Points) = Max_Points then
         Bad (Status, "AddPoint: the list already holds the maximum number"
                      & " of points (1048576)");
         return;
      end if;
      KS.Add_Vertex (Points, X, Y, KS.Append_Index, Status);
      if Status.Failure = Failure_Index_Out_Of_Range then
         --  Appending is always at a valid index; this guard states it for
         --  the proof and never acts.
         Bad (Status, "AddPoint: the point could not be appended");
      end if;
   end Points_Add_Point;

   procedure Points_Delete_Point
     (Points : KS.Ks_Polygon;
      Index  : Int32;
      Status : out Ks_Status) is
   begin
      Check_Index (Points, Index, Status);
      if Succeeded (Status) then
         KS.Remove_Vertex (Points, Index, Status);
      end if;
   end Points_Delete_Point;

   procedure Points_Get_Point
     (Points : access constant KS.Ks_Polygon_Data;
      Index  : Int32;
      X, Y   : out Long_Float;
      Status : out Ks_Status) is
   begin
      X := 0.0;
      Y := 0.0;
      Check_Index (Points, Index, Status);
      if Succeeded (Status) then
         KS.Get_Vertex (Points, Index, X, Y, Status);
      end if;
   end Points_Get_Point;

   procedure Points_Set_Point
     (Points : KS.Ks_Polygon;
      Index  : Int32;
      X, Y   : Long_Float;
      Status : out Ks_Status) is
   begin
      Check_Index (Points, Index, Status);
      if Succeeded (Status) then
         Check_Coordinate (X, "X", Status);
      end if;
      if Succeeded (Status) then
         Check_Coordinate (Y, "Y", Status);
      end if;
      if Succeeded (Status) then
         KS.Set_Vertex (Points, Index, X, Y, Status);
      end if;
   end Points_Set_Point;

   procedure Points_Set_X
     (Points : KS.Ks_Polygon;
      Index  : Int32;
      Value  : Long_Float;
      Status : out Ks_Status)
   is
      Unused_X, Y : Long_Float;
   begin
      Check_Index (Points, Index, Status);
      if Succeeded (Status) then
         Check_Coordinate (Value, "Value", Status);
      end if;
      if Succeeded (Status) then
         KS.Get_Vertex (Points, Index, Unused_X, Y, Status);
         if Succeeded (Status) then
            KS.Set_Vertex (Points, Index, Value, Y, Status);
         end if;
      end if;
   end Points_Set_X;

   procedure Points_Set_Y
     (Points : KS.Ks_Polygon;
      Index  : Int32;
      Value  : Long_Float;
      Status : out Ks_Status)
   is
      X, Unused_Y : Long_Float;
   begin
      Check_Index (Points, Index, Status);
      if Succeeded (Status) then
         Check_Coordinate (Value, "Value", Status);
      end if;
      if Succeeded (Status) then
         KS.Get_Vertex (Points, Index, X, Unused_Y, Status);
         if Succeeded (Status) then
            KS.Set_Vertex (Points, Index, X, Value, Status);
         end if;
      end if;
   end Points_Set_Y;

   procedure Points_Clear
     (Points : KS.Ks_Polygon;
      Status : out Ks_Status) is
   begin
      Check_Handle (Points, Status);
      if Succeeded (Status) then
         KS.Clear (Points, Status);
      end if;
   end Points_Clear;

   procedure Points_Duplicate
     (Points : access constant KS.Ks_Polygon_Data;
      Copy   : out KS.Ks_Polygon;
      Status : out Ks_Status) is
   begin
      KS.Duplicate (Points, Copy, Status);
   end Points_Duplicate;

   procedure Points_Destroy (Points : in out KS.Ks_Polygon) is
      Unused_Status : Ks_Status;
   begin
      KS.Destroy (Points, Unused_Status);
   end Points_Destroy;

   ---------------------------------------------------------------------
   --  Run parameters
   ---------------------------------------------------------------------

   procedure Line_Run_Params_Default
     (Params : out Ks_Fit_Line_Run_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Line_Run_Params_Default;

   procedure Circle_Run_Params_Default
     (Params : out Ks_Fit_Circle_Run_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Circle_Run_Params_Default;

   procedure Ellipse_Run_Params_Default
     (Params : out Ks_Fit_Ellipse_Run_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Ellipse_Run_Params_Default;

   ---------------------------------------------------------------------
   --  Building a result
   ---------------------------------------------------------------------

   function Arrays_In_Place
     (Result : access constant Ks_Fit_Result_Data;
      Count  : Natural) return Boolean
   is (Result /= null
       and then Result.Points /= null and then Result.Used /= null
       and then Result.Distances /= null
       and then Result.Points'First = 0
       and then Result.Points'Last = Count - 1
       and then Result.Used'First = 0
       and then Result.Used'Last = Count - 1
       and then Result.Distances'First = 0
       and then Result.Distances'Last = Count - 1);
   --  The three arrays of a result with Count points.

   subtype Fit_Name is String
     with Dynamic_Predicate =>
       Fit_Name'First = 1 and then Fit_Name'Length <= 12;

   procedure Prepare
     (Points        : access constant KS.Ks_Polygon_Data;
      Num_To_Ignore : Int32;
      Kind          : Int32;
      Min           : Natural;
      Name          : Fit_Name;
      Result        : out Ks_Fit_Result;
      Status        : out Ks_Status)
   with
     Pre  => Kind in Fit_Line .. Fit_Ellipse
             and then Min >= Min_Points (Kind) and then Min <= 5,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Result (Result)
                            and then Result.Kind = Kind
                            and then Result.Count = KS.Count_Of (Points)
                            and then Num_To_Ignore >= 0
                            and then Int64 (Result.Count)
                                       >= Int64 (Min) + Int64 (Num_To_Ignore)
                            and then Result.Num_Points_Used = 0
                       else Result = null);
   --  Checks the points and NumToIgnore, and allocates the result with a
   --  copy of the points.

   procedure Prepare
     (Points        : access constant KS.Ks_Polygon_Data;
      Num_To_Ignore : Int32;
      Kind          : Int32;
      Min           : Natural;
      Name          : Fit_Name;
      Result        : out Ks_Fit_Result;
      Status        : out Ks_Status)
   is
      Count : Natural;
   begin
      Result := null;
      Check_Handle (Points, Status);
      if not Succeeded (Status) then
         return;
      elsif Num_To_Ignore < 0 then
         Bad (Status, "RunParams.NumToIgnore must be >= 0");
         return;
      end if;
      Count := KS.Count_Of (Points);
      if Int64 (Count) < Int64 (Min) + Int64 (Num_To_Ignore) then
         Bad (Status, Name & ": NumPoints - NumToIgnore must be at least "
                      & Image_Of (Int64 (Min)) & " (NumPoints = "
                      & Image_Of (Int64 (Count)) & ", NumToIgnore = "
                      & Image_Of (Int64 (Num_To_Ignore)) & ")");
         return;
      end if;
      Allocate_Result (Result);
      if Result = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      Name & ": not enough memory");
         return;
      end if;
      Allocate_Points (Count, Result.Points);
      Allocate_Flags (Count, Result.Used);
      Allocate_Values (Count, Result.Distances);
      if Result.Points = null or else Result.Used = null
        or else Result.Distances = null
      then
         Result_Destroy (Result);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      Name & ": not enough memory");
         return;
      end if;
      Result.Kind := Kind;
      Result.Count := Count;
      Result.Num_Points_Used := 0;
      for I in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (Arrays_In_Place (Result, Count)
            and then Result.Kind = Kind and then Result.Count = Count
            and then Result.Num_Points_Used = 0);
         Result.Points (I) := (X => Points.Vertices (I).X,
                               Y => Points.Vertices (I).Y);
      end loop;
      Set_Success (Status);
   end Prepare;

   procedure Distance_To
     (Result : access constant Ks_Fit_Result_Data;
      Q      : P.Point;
      D      : out P.Length)
   with Pre => Result /= null and then Valid_Shape (Result);
   --  The distance from Q to the fitted shape (>= 0).

   procedure Distance_To
     (Result : access constant Ks_Fit_Result_Data;
      Q      : P.Point;
      D      : out P.Length)
   is
      Signed      : P.Signed_Length;
      Unused_Near : P.Point;
      Unused_Fits : Boolean;
   begin
      case Result.Kind is
         when Fit_Line =>
            D := abs P.Offset
              (Q, (P        => (Result.Line.X, Result.Line.Y),
                   C        => EF.Cos (Result.Line.Rotation),
                   S        => EF.Sin (Result.Line.Rotation),
                   Rotation => Result.Line.Rotation));
         when Fit_Circle =>
            D := abs (P.Distance
                        (Q, (Result.Circle.Center_X,
                             Result.Circle.Center_Y))
                      - Result.Circle.Radius);
         when others =>
            EL.Point_Ellipse
              (Q,
               (Center   => (Result.Ellipse.Center_X,
                             Result.Ellipse.Center_Y),
                Radius_X => Result.Ellipse.Radius_X,
                Radius_Y => Result.Ellipse.Radius_Y,
                C        => EF.Cos (Result.Ellipse.Rotation),
                S        => EF.Sin (Result.Ellipse.Rotation)),
               Signed, Unused_Near, Unused_Fits);
            D := abs Signed;
      end case;
   end Distance_To;

   procedure Finish
     (Result : Ks_Fit_Result;
      Status : out Ks_Status)
   with
     Pre  => Valid_Result (Result) and then Valid_Shape (Result),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Other
             and then Valid_Result (Result)
             and then Result.Kind = Result.Kind'Old
             and then Result.Count = Result.Count'Old
             and then Result.Line = Result.Line'Old
             and then Result.Circle = Result.Circle'Old
             and then Result.Ellipse = Result.Ellipse'Old
             and then (if Succeeded (Status) then Gold_Result (Result));
   --  The distances, NumPointsUsed and the RMS error of a result whose
   --  points, used flags and shape are in place.

   procedure Finish
     (Result : Ks_Fit_Result;
      Status : out Ks_Status)
   is
      Count : constant Natural := Result.Count;
      D     : P.Length;
      Used  : Natural := 0;
      Sum   : Long_Float := 0.0;
   begin
      for I in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (Valid_Result (Result) and then Valid_Shape (Result)
            and then Result.Count = Count
            and then Result.Kind = Result.Kind'Loop_Entry
            and then Result.Line = Result.Line'Loop_Entry
            and then Result.Circle = Result.Circle'Loop_Entry
            and then Result.Ellipse = Result.Ellipse'Loop_Entry
            and then (for all J in 0 .. I - 1 =>
                        Result.Distances (J) >= 0.0
                        and then Result.Distances (J) <= Max_Length));
         Distance_To (Result, Point_Of (Result.Points (I)), D);
         Result.Distances (I) := D;
      end loop;

      for I in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (Used = Count_Used (Result.Used.all, I - 1)
            and then Used <= I
            and then Sum >= 0.0 and then Sum <= 2.0 ** 1021);
         if Result.Used (I) then
            Used := Used + 1;
            --  At most 2**20 squares of at most (4.0E150)**2 (about
            --  1.7E307 in all): the limit never acts.
            Sum := Long_Float'Min
              (Sum + N.Square_Within
                       (N.Clamp (Result.Distances (I), Max_Length),
                        Max_Length),
               2.0 ** 1021);
         end if;
      end loop;

      --  The fits mark at least the points they need; this guard states
      --  it for the proof and never acts.
      if Used < Min_Points (Result.Kind) then
         Set_Failure (Status, Failure_Other,
                      "Fit: fewer points were used than the fit needs");
         return;
      end if;
      Result.Num_Points_Used := Used;
      --  The root mean square of distances of at most 4.0E150 is at most
      --  4.0E150; the limit states it (Sqrt has no upper bound in its
      --  contract) and never acts.
      Result.RMS_Error := Long_Float'Min
        (EF.Sqrt (Sum / Long_Float (Used)), Max_Length);
      Set_Success (Status);
   end Finish;

   ---------------------------------------------------------------------
   --  The circle of fixed radius
   ---------------------------------------------------------------------

   Max_Iterations : constant := 100;

   Cost_Limit : constant := 2.0 ** 1021;
   --  At least Max_Points squared residuals of at most 4.0E150 each
   --  (about 1.7E307).

   procedure Fixed_Fit
     (Points           : KG.Point_Array;
      Active           : KG.Flag_Array;
      Radius           : Long_Float;
      Start_X, Start_Y : Coordinate;
      Center_X         : out Coordinate;
      Center_Y         : out Coordinate;
      Cost             : out Long_Float)
   with
     Pre  => Points'First = 0 and then Points'Last < Max_Points
             and then Active'First = 0 and then Active'Last = Points'Last
             and then Radius > 0.0 and then Radius <= Max_Value,
     Post => Cost >= 0.0 and then Cost <= Cost_Limit;
   --  The centre of the circle of the given radius that fits the active
   --  points, from (Start_X, Start_Y): each step moves the centre to the
   --  mean of P - Radius u, u the unit vector from the centre to P (each
   --  step lowers the sum of squared radial residuals), until it moves
   --  less than 1.0E-12 times the radius or 100 steps have run; and that
   --  sum. A centre beyond 1.0E150 is limited to it.

   procedure Fixed_Fit
     (Points           : KG.Point_Array;
      Active           : KG.Flag_Array;
      Radius           : Long_Float;
      Start_X, Start_Y : Coordinate;
      Center_X         : out Coordinate;
      Center_Y         : out Coordinate;
      Cost             : out Long_Float)
   is
      Sum_Limit : constant := 2.0 ** 522;
      --  At least Max_Points terms of at most 2.0E150 (about 2.1E156).
      X, Y      : Coordinate;
      SX, SY    : Long_Float;
      M         : Natural;
      DX, DY, D : Long_Float;
      UX, UY    : Long_Float;
      Q         : P.Point;
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
         for I in Points'Range loop
            pragma Loop_Invariant
              (abs SX <= Sum_Limit and then abs SY <= Sum_Limit
               and then M <= I);
            if Active (I) then
               Q := Point_Of (Points (I));
               DX := Q.X - X;
               DY := Q.Y - Y;
               D := N.Hypot (DX, DY);
               if D > 0.0 then
                  UX := N.Unit_Ratio (N.Clamp (DX, D), D);
                  UY := N.Unit_Ratio (N.Clamp (DY, D), D);
               else
                  UX := 1.0;
                  UY := 0.0;
               end if;
               --  Both sums stay below the limit, which never acts.
               SX := N.Clamp (SX + (Q.X - N.Times_Unit (Radius, UX)),
                              Sum_Limit);
               SY := N.Clamp (SY + (Q.Y - N.Times_Unit (Radius, UY)),
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
      for I in Points'Range loop
         pragma Loop_Invariant (Cost >= 0.0 and then Cost <= Cost_Limit);
         if Active (I) then
            Q := Point_Of (Points (I));
            --  The distance is at most 4.0E150 (Hypot of two differences
            --  of at most 2.0E150), the residual too.
            Residual := Long_Float'Min (N.Hypot (Q.X - X, Q.Y - Y), 4.0E150)
                        - Radius;
            Cost := Long_Float'Min
              (Cost + N.Square_Within (Residual, 4.0E150), Cost_Limit);
         end if;
      end loop;
   end Fixed_Fit;

   procedure Centroid
     (Points : KG.Point_Array;
      CX, CY : out Long_Float)
   with
     Pre  => Points'First = 0 and then Points'Last < Max_Points,
     Post => Bounded (CX) and then Bounded (CY);
   --  The mean of the points (0 for none).

   procedure Centroid
     (Points : KG.Point_Array;
      CX, CY : out Long_Float)
   is
      Sum_Limit : constant := 2.0 ** 521;
      --  At least Max_Points coordinates within 1.0E150.
      SX, SY : Long_Float := 0.0;
   begin
      CX := 0.0;
      CY := 0.0;
      if Points'Last < 0 then
         return;
      end if;
      for I in Points'Range loop
         pragma Loop_Invariant
           (abs SX <= Sum_Limit and then abs SY <= Sum_Limit);
         SX := N.Clamp (SX + Read (Points (I).X), Sum_Limit);
         SY := N.Clamp (SY + Read (Points (I).Y), Sum_Limit);
      end loop;
      CX := N.Clamp (SX / Long_Float (Points'Last + 1), Max_Value);
      CY := N.Clamp (SY / Long_Float (Points'Last + 1), Max_Value);
   end Centroid;

   procedure Fixed_Fit_Robust
     (Points           : KG.Point_Array;
      Num_To_Ignore    : Natural;
      Radius           : Long_Float;
      Start_X, Start_Y : Coordinate;
      Center_X         : out Coordinate;
      Center_Y         : out Coordinate;
      Used             : out KG.Flag_Array)
   with
     Pre  => Points'First = 0 and then Points'Last < Max_Points
             and then Used'First = 0 and then Used'Last = Points'Last
             and then Radius > 0.0 and then Radius <= Max_Value;
   --  Fixed_Fit after discarding Num_To_Ignore points one at a time, each
   --  time the point whose removal gives the smallest cost (ties: the
   --  lowest index), each trial started from the current centre. Used
   --  tells the points kept.

   procedure Fixed_Fit_Robust
     (Points           : KG.Point_Array;
      Num_To_Ignore    : Natural;
      Radius           : Long_Float;
      Start_X, Start_Y : Coordinate;
      Center_X         : out Coordinate;
      Center_Y         : out Coordinate;
      Used             : out KG.Flag_Array)
   is
      Best        : Integer;
      Best_Cost   : Long_Float;
      Best_X      : Coordinate;
      Best_Y      : Coordinate;
      Trial       : Long_Float;
      TX, TY      : Coordinate;
      Unused_Cost : Long_Float;
   begin
      Used := [others => True];
      Fixed_Fit (Points, Used, Radius, Start_X, Start_Y, Center_X,
                 Center_Y, Unused_Cost);
      for Step in 1 .. Num_To_Ignore loop
         Best := -1;
         Best_Cost := 0.0;
         Best_X := Center_X;
         Best_Y := Center_Y;
         for J in Points'Range loop
            pragma Loop_Invariant
              (Best in -1 .. J - 1
               and then Best_Cost >= 0.0 and then Best_Cost <= Cost_Limit);
            if Used (J) then
               Used (J) := False;
               Fixed_Fit (Points, Used, Radius, Center_X, Center_Y,
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
         end if;
      end loop;
   end Fixed_Fit_Robust;

   ---------------------------------------------------------------------
   --  Execution
   ---------------------------------------------------------------------

   procedure Line_Execute
     (Points : access constant KS.Ks_Polygon_Data;
      Params : Ks_Fit_Line_Run_Params;
      Result : out Ks_Fit_Result;
      Status : out Ks_Status)
   is
      Line        : KG.Ks_Line_2D;
      Unused_RMS  : Long_Float;
   begin
      Prepare (Points, Params.Num_To_Ignore, Fit_Line, 2, "FitLine",
               Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KG.Fit_Line_Robust
        (Result.Points.all, Params.Num_To_Ignore, Line, Unused_RMS,
         Result.Used.all, Status);
      if not Succeeded (Status) then
         Result_Destroy (Result);
         return;
      end if;
      Result.Line := (X => Line.X, Y => Line.Y, Rotation => Line.Rotation);
      Finish (Result, Status);
      if not Succeeded (Status) then
         Result_Destroy (Result);
      end if;
   end Line_Execute;

   procedure Circle_Execute
     (Points : access constant KS.Ks_Polygon_Data;
      Params : Ks_Fit_Circle_Run_Params;
      Result : out Ks_Fit_Result;
      Status : out Ks_Status)
   is
      Circle      : KG.Ks_Circle_2D;
      Unused_RMS  : Long_Float;
      CX, CY      : Coordinate;
      Start       : KG.Ks_Circle_2D;
      Start_S     : Ks_Status;
   begin
      Result := null;
      if Params.Radius_Constraint_Enabled not in False_Value | True_Value
      then
         Bad (Status, "RunParams.RadiusConstraintEnabled must be 0 or 1");
         return;
      elsif Params.Radius_Constraint_Enabled = True_Value
        and then not (Params.Radius_Constraint > 0.0
                      and then Params.Radius_Constraint <= Max_Value)
      then
         Bad (Status, "RunParams.RadiusConstraint must be > 0 and within"
                      & " 1.0E150");
         return;
      end if;
      Prepare (Points, Params.Num_To_Ignore, Fit_Circle, 3, "FitCircle",
               Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Params.Radius_Constraint_Enabled = True_Value then
         --  Start from the free fit's centre, or from the centroid when
         --  no free circle fits.
         KG.Fit_Circle (Result.Points.all, Start, Unused_RMS, Start_S);
         if not Succeeded (Start_S) then
            Centroid (Result.Points.all, Start.Center_X, Start.Center_Y);
         end if;
         Fixed_Fit_Robust
           (Result.Points.all, Natural (Params.Num_To_Ignore),
            Params.Radius_Constraint, Read (Start.Center_X),
            Read (Start.Center_Y), CX, CY, Result.Used.all);
         Result.Circle := (Center_X => CX, Center_Y => CY,
                           Radius   => Params.Radius_Constraint);
      else
         KG.Fit_Circle_Robust
           (Result.Points.all, Params.Num_To_Ignore, Circle, Unused_RMS,
            Result.Used.all, Status);
         if not Succeeded (Status) then
            Result_Destroy (Result);
            return;
         end if;
         Result.Circle := (Center_X => Circle.Center_X,
                           Center_Y => Circle.Center_Y,
                           Radius   => Circle.Radius);
      end if;
      Finish (Result, Status);
      if not Succeeded (Status) then
         Result_Destroy (Result);
      end if;
   end Circle_Execute;

   procedure Ellipse_Execute
     (Points : access constant KS.Ks_Polygon_Data;
      Params : Ks_Fit_Ellipse_Run_Params;
      Result : out Ks_Fit_Result;
      Status : out Ks_Status)
   is
      Constrained : Boolean;
      Fitted      : FE.Ellipse_Value;
   begin
      Result := null;
      if Params.Rotation_Constraint_Enabled not in False_Value | True_Value
      then
         Bad (Status, "RunParams.RotationConstraintEnabled must be 0 or 1");
         return;
      elsif not Bounded (Params.Rotation_Constraint) then
         Bad (Status, "RunParams.RotationConstraint must be finite and"
                      & " within +/-1.0E150");
         return;
      end if;
      Constrained := Params.Rotation_Constraint_Enabled = True_Value;
      Prepare (Points, Params.Num_To_Ignore, Fit_Ellipse,
               (if Constrained then 4 else 5), "FitEllipse", Result,
               Status);
      if not Succeeded (Status) then
         return;
      end if;
      FE.Fit (Result.Points.all, Natural (Params.Num_To_Ignore), Constrained,
              Params.Rotation_Constraint, Fitted, Result.Used.all, Status);
      if not Succeeded (Status) then
         Result_Destroy (Result);
         return;
      end if;
      Result.Ellipse := (Center_X => Fitted.Center_X,
                         Center_Y => Fitted.Center_Y,
                         Radius_X => Fitted.Radius_X,
                         Radius_Y => Fitted.Radius_Y,
                         Rotation => Fitted.Rotation);
      Finish (Result, Status);
      if Succeeded (Status) and then not Constrained
        and then Result.Num_Points_Used < 5
      then
         --  The unconstrained fit uses at least 5 points; this guard
         --  states it for the proof and never acts.
         Set_Failure (Status, Failure_Other,
                      "FitEllipse: fewer than 5 points were used");
      end if;
      if not Succeeded (Status) then
         Result_Destroy (Result);
      end if;
   end Ellipse_Execute;

   ---------------------------------------------------------------------
   --  Accessors
   ---------------------------------------------------------------------

   procedure Result_Destroy (Result : in out Ks_Fit_Result) is
   begin
      if Result /= null then
         Free (Result.Points);
         Free (Result.Used);
         Free (Result.Distances);
         Free (Result);
      end if;
   end Result_Destroy;

   procedure Check_Result
     (Result : access constant Ks_Fit_Result_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Result = null or else Valid_Result (Result));

   procedure Check_Result
     (Result : access constant Ks_Fit_Result_Data;
      Status : out Ks_Status) is
   begin
      if Result /= null and then not Valid_Result (Result) then
         Bad (Status, "Result is not a valid fit result handle");
      else
         Set_Success (Status);
      end if;
   end Check_Result;

   procedure Result_Kind
     (Result : access constant Ks_Fit_Result_Data;
      Kind   : out Int32;
      Status : out Ks_Status) is
   begin
      Kind := 0;
      Check_Result (Result, Status);
      if Succeeded (Status) and then Result /= null then
         Kind := Result.Kind;
      end if;
   end Result_Kind;

   procedure Result_Num_Points
     (Result : access constant Ks_Fit_Result_Data;
      Count  : out Int32;
      Status : out Ks_Status) is
   begin
      Count := 0;
      Check_Result (Result, Status);
      if Succeeded (Status) and then Result /= null then
         Count := Int32 (Result.Count);
      end if;
   end Result_Num_Points;

   procedure Result_Num_Points_Used
     (Result : access constant Ks_Fit_Result_Data;
      Count  : out Int32;
      Status : out Ks_Status) is
   begin
      Count := 0;
      Check_Result (Result, Status);
      if Succeeded (Status) and then Result /= null then
         Count := Int32 (Result.Num_Points_Used);
      end if;
   end Result_Num_Points_Used;

   procedure Result_RMS_Error
     (Result    : access constant Ks_Fit_Result_Data;
      RMS_Error : out Long_Float;
      Status    : out Ks_Status) is
   begin
      RMS_Error := 0.0;
      Check_Result (Result, Status);
      if Succeeded (Status) and then Result /= null then
         RMS_Error := Result.RMS_Error;
      end if;
   end Result_RMS_Error;

   procedure Result_Get_XY_Used_Distance
     (Result   : access constant Ks_Fit_Result_Data;
      Index    : Int32;
      X, Y     : out Long_Float;
      Used     : out Int32;
      Distance : out Long_Float;
      Status   : out Ks_Status) is
   begin
      X := 0.0;
      Y := 0.0;
      Used := False_Value;
      Distance := 0.0;
      Check_Result (Result, Status);
      if not Succeeded (Status) then
         return;
      elsif Result = null or else Index not in 0 .. Int32 (Result.Count) - 1
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Index must be in 0 .. NumPoints - 1");
         return;
      end if;
      X := Result.Points (Natural (Index)).X;
      Y := Result.Points (Natural (Index)).Y;
      Used := (if Result.Used (Natural (Index)) then True_Value
               else False_Value);
      Distance := Result.Distances (Natural (Index));
   end Result_Get_XY_Used_Distance;

   procedure Result_Get_Line
     (Result : access constant Ks_Fit_Result_Data;
      Line   : out KS.Ks_Line;
      Status : out Ks_Status) is
   begin
      Line := (others => <>);
      Check_Result (Result, Status);
      if not Succeeded (Status) then
         return;
      elsif Result = null or else Result.Kind /= Fit_Line
        or else not KS.Valid_Line (Result.Line)
      then
         Bad (Status, "Result has no line (not the result of a line fit)");
         return;
      end if;
      Line := Result.Line;
   end Result_Get_Line;

   procedure Result_Get_Circle
     (Result : access constant Ks_Fit_Result_Data;
      Circle : out KS.Ks_Circle;
      Status : out Ks_Status) is
   begin
      Circle := (others => <>);
      Check_Result (Result, Status);
      if not Succeeded (Status) then
         return;
      elsif Result = null or else Result.Kind /= Fit_Circle
        or else not KS.Valid_Circle (Result.Circle)
      then
         Bad (Status, "Result has no circle (not the result of a circle"
                      & " fit)");
         return;
      end if;
      Circle := Result.Circle;
   end Result_Get_Circle;

   procedure Result_Get_Ellipse
     (Result  : access constant Ks_Fit_Result_Data;
      Ellipse : out KS.Ks_Ellipse;
      Status  : out Ks_Status) is
   begin
      Ellipse := (others => <>);
      Check_Result (Result, Status);
      if not Succeeded (Status) then
         return;
      elsif Result = null or else Result.Kind /= Fit_Ellipse
        or else not KS.Valid_Ellipse (Result.Ellipse)
      then
         Bad (Status, "Result has no ellipse (not the result of an ellipse"
                      & " fit)");
         return;
      end if;
      Ellipse := Result.Ellipse;
   end Result_Get_Ellipse;

end AMV.Kernels.Dimensioning.Fitting;
