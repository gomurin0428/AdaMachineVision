pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;

with AMV.Kernels.Numerics;

package body AMV.Kernels.Blob.Extrema with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package N renames AMV.Kernels.Numerics;

   Offset_Limit : constant := 2.0 ** 34;
   --  The bound of the offset of a pixel centre (below 2**31) from a
   --  centre of mass (within Center_Limit).

   Extent_Limit : constant := 2.0 ** 102;
   --  The bound of an extent widened by half a mapped pixel square.

   Ratio_Limit : constant := 1.0E150;
   --  The bound of an aspect ratio (as in AMV.Kernels.Blob.Measures).

   subtype Coordinate is Long_Float
     range -Projection_Limit .. Projection_Limit;

   type Coordinate_Array is array (Natural range <>) of Coordinate
     with Default_Component_Value => 0.0;
   type Coordinate_Array_Access is access Coordinate_Array;
   --  The coordinates of the pixel centres of the features along one row,
   --  the pixels of each feature together.

   type Axis_Stat is record
      Lo, Median, Hi : Coordinate := 0.0;
   end record
     with Dynamic_Predicate =>
       Axis_Stat.Lo <= Axis_Stat.Median
       and then Axis_Stat.Median <= Axis_Stat.Hi;
   --  The least, median and greatest coordinate of a feature along a row
   --  (proved at each assignment, not executed).

   type Stat_Array is array (Natural range <>) of Axis_Stat;
   type Stat_Array_Access is access Stat_Array;

   procedure Free is new Ada.Unchecked_Deallocation
     (Coordinate_Array, Coordinate_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Stat_Array, Stat_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Int64_Array, Int64_Array_Access);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Coordinates
     (Last : Natural;
      List : out Coordinate_Array_Access)
   with
     Global => null,
     Post   => (if List /= null
                then List'First = 0 and then List'Last = Last);
   --  A new table of Last + 1 zeros, or null when the memory cannot be
   --  allocated (the allocator raises Storage_Error, which SPARK cannot
   --  express).

   procedure Allocate_Coordinates
     (Last : Natural;
      List : out Coordinate_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      List := new Coordinate_Array (0 .. Last);
   exception
      when Storage_Error =>
         List := null;
   end Allocate_Coordinates;

   procedure Allocate_Stats
     (Last : Natural;
      List : out Stat_Array_Access)
   with
     Global => null,
     Post   => (if List /= null
                then List'First = 0 and then List'Last = Last);
   --  A new table of Last + 1 records of zeros, or null in the same way.

   procedure Allocate_Stats
     (Last : Natural;
      List : out Stat_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      List := new Stat_Array (0 .. Last);
   exception
      when Storage_Error =>
         List := null;
   end Allocate_Stats;

   ---------------------------------------------------------------------
   --  Rows and coordinates
   ---------------------------------------------------------------------

   function Turned (P, Q, Cos_A, Sin_A : Long_Float) return Long_Float is
     (N.Times_Unit (P, Cos_A) + N.Times_Unit (Q, Sin_A));

   function Projection
     (P, Q   : Long_Float;
      Cx, Cy : Long_Float;
      X, Y   : Natural) return Long_Float
   with
     Pre  => Valid_Row (P, Q)
             and then abs Cx <= Center_Limit and then abs Cy <= Center_Limit,
     Post => abs Projection'Result <= Projection_Limit;
   --  P (X - Cx) + Q (Y - Cy): the coordinate of the centre of pixel
   --  (X, Y) along the row (P, Q), measured from the centre of mass (the
   --  arithmetic of AMV.Kernels.Blob.Measures, so that both give the same
   --  bits).

   function Projection
     (P, Q   : Long_Float;
      Cx, Cy : Long_Float;
      X, Y   : Natural) return Long_Float
   is
   begin
      return N.Mul_Within (P, Long_Float (X) - Cx, Coefficient_Limit,
                           Offset_Limit)
        + N.Mul_Within (Q, Long_Float (Y) - Cy, Coefficient_Limit,
                        Offset_Limit);
   end Projection;

   function Half_Square (P, Q : Long_Float) return Long_Float
   with
     Pre  => Valid_Row (P, Q),
     Post => Half_Square'Result >= 0.0
             and then Half_Square'Result <= Coefficient_Limit;
   --  (abs P + abs Q) / 2: half the extent of a mapped pixel square along
   --  the row (P, Q).

   function Half_Square (P, Q : Long_Float) return Long_Float is
     ((abs P + abs Q) / 2.0);

   ---------------------------------------------------------------------
   --  Extents (Gold) and medians
   ---------------------------------------------------------------------

   function Covers
     (Map    : Int32_Matrix;
      Id     : Int32;
      P, Q   : Long_Float;
      Cx, Cy : Long_Float;
      Lo, Hi : Long_Float;
      X, Y   : Natural) return Boolean
   is
     (if Map (Y, X) = Id
      then Projection (P, Q, Cx, Cy, X, Y) >= Lo
           and then Projection (P, Q, Cx, Cy, X, Y) <= Hi)
   with
     Ghost,
     Pre => Y in Map'Range (1) and then X in Map'Range (2)
            and then Valid_Row (P, Q)
            and then abs Cx <= Center_Limit and then abs Cy <= Center_Limit;
   --  Pixel (X, Y) does not belong to the feature numbered Id, or the
   --  coordinate of its centre lies within [Lo, Hi].

   procedure Row_Extent
     (Map    : Int32_Matrix;
      Id     : Int32;
      Y      : Natural;
      P, Q   : Long_Float;
      Cx, Cy : Long_Float;
      Lo, Hi : out Long_Float)
   with
     Pre  => Y in Map'Range (1) and then Valid_Row (P, Q)
             and then abs Cx <= Center_Limit and then abs Cy <= Center_Limit,
     Post => Lo >= -Projection_Limit and then Lo <= Projection_Limit
             and then Hi >= -Projection_Limit and then Hi <= Projection_Limit
             and then (for all X in Map'Range (2) =>
                         Covers (Map, Id, P, Q, Cx, Cy, Lo, Hi, X, Y));
   --  The least and greatest coordinate of the pixel centres of the
   --  feature in row Y (Lo = Projection_Limit and Hi = -Projection_Limit
   --  when the row has none).

   procedure Row_Extent
     (Map    : Int32_Matrix;
      Id     : Int32;
      Y      : Natural;
      P, Q   : Long_Float;
      Cx, Cy : Long_Float;
      Lo, Hi : out Long_Float)
   is
   begin
      Lo := Projection_Limit;
      Hi := -Projection_Limit;
      for X in Map'Range (2) loop
         if Map (Y, X) = Id then
            declare
               Value : constant Long_Float :=
                 Projection (P, Q, Cx, Cy, X, Y);
            begin
               Lo := Long_Float'Min (Lo, Value);
               Hi := Long_Float'Max (Hi, Value);
            end;
         end if;
         pragma Loop_Invariant
           (Lo >= -Projection_Limit and then Lo <= Projection_Limit
            and then Hi >= -Projection_Limit and then Hi <= Projection_Limit);
         pragma Loop_Invariant
           (for all X2 in Map'First (2) .. X =>
              Covers (Map, Id, P, Q, Cx, Cy, Lo, Hi, X2, Y));
      end loop;
   end Row_Extent;

   procedure Feature_Extent
     (Map    : Int32_Matrix;
      Id     : Int32;
      P, Q   : Long_Float;
      Cx, Cy : Long_Float;
      Lo, Hi : out Long_Float;
      Found  : out Boolean)
   with
     Pre  => Valid_Row (P, Q)
             and then abs Cx <= Center_Limit and then abs Cy <= Center_Limit,
     Post => Lo >= -Projection_Limit and then Lo <= Projection_Limit
             and then Hi >= -Projection_Limit and then Hi <= Projection_Limit
             and then Found = (Lo <= Hi)
             and then
               (for all Y in Map'Range (1) =>
                  (for all X in Map'Range (2) =>
                     Covers (Map, Id, P, Q, Cx, Cy, Lo, Hi, X, Y)));
   --  The least and greatest coordinate along the row (P, Q) of the pixel
   --  centres of the feature numbered Id; Found is False (Lo > Hi) when no
   --  pixel has the number. Gold: the coordinate of every pixel centre of
   --  the feature lies within [Lo, Hi].

   procedure Feature_Extent
     (Map    : Int32_Matrix;
      Id     : Int32;
      P, Q   : Long_Float;
      Cx, Cy : Long_Float;
      Lo, Hi : out Long_Float;
      Found  : out Boolean)
   is
      Row_Lo, Row_Hi : Long_Float;
   begin
      Lo := Projection_Limit;
      Hi := -Projection_Limit;
      for Y in Map'Range (1) loop
         Row_Extent (Map, Id, Y, P, Q, Cx, Cy, Row_Lo, Row_Hi);
         Lo := Long_Float'Min (Lo, Row_Lo);
         Hi := Long_Float'Max (Hi, Row_Hi);
         pragma Loop_Invariant
           (Lo >= -Projection_Limit and then Lo <= Projection_Limit
            and then Hi >= -Projection_Limit and then Hi <= Projection_Limit);
         pragma Loop_Invariant
           (for all Y2 in Map'First (1) .. Y =>
              (for all X2 in Map'Range (2) =>
                 Covers (Map, Id, P, Q, Cx, Cy, Lo, Hi, X2, Y2)));
      end loop;
      Found := Lo <= Hi;
   end Feature_Extent;

   function In_Bounds
     (V      : Coordinate_Array;
      First  : Natural;
      Last   : Natural;
      Lo, Hi : Long_Float) return Boolean
   is (for all I in First .. Last => V (I) >= Lo and then V (I) <= Hi)
   with Ghost, Pre => First >= V'First and then Last <= V'Last;
   --  Every value of V (First .. Last) lies within [Lo, Hi].

   procedure Swap
     (V           : in out Coordinate_Array;
      I, J        : Natural;
      First, Last : Natural;
      Lo, Hi      : Long_Float)
   with
     Pre  => First >= V'First and then Last <= V'Last
             and then I in First .. Last and then J in First .. Last,
     Post => V (I) = V'Old (J) and then V (J) = V'Old (I)
             and then (for all K in V'Range =>
                         (if K /= I and then K /= J then V (K) = V'Old (K)))
             and then (if In_Bounds (V'Old, First, Last, Lo, Hi)
                       then In_Bounds (V, First, Last, Lo, Hi));
   --  Exchanges V (I) and V (J). First, Last, Lo and Hi only state that a
   --  range bound of V (First .. Last) is kept (a conditional
   --  postcondition, so that no quantified precondition is needed).

   procedure Swap
     (V           : in out Coordinate_Array;
      I, J        : Natural;
      First, Last : Natural;
      Lo, Hi      : Long_Float)
   is
      pragma Unreferenced (First, Last, Lo, Hi);
      Temp : constant Coordinate := V (I);
   begin
      V (I) := V (J);
      V (J) := Temp;
   end Swap;

   procedure Bounds_Of
     (V      : Coordinate_Array;
      First  : Natural;
      Last   : Natural;
      Lo, Hi : out Coordinate)
   with
     Pre  => First <= Last and then First >= V'First
             and then Last <= V'Last and then Last < Natural'Last,
     Post => Lo <= Hi and then In_Bounds (V, First, Last, Lo, Hi);
   --  The least and the greatest value of V (First .. Last).

   procedure Bounds_Of
     (V      : Coordinate_Array;
      First  : Natural;
      Last   : Natural;
      Lo, Hi : out Coordinate)
   is
   begin
      Lo := V (First);
      Hi := V (First);
      for J in First + 1 .. Last loop
         Lo := Coordinate'Min (Lo, V (J));
         Hi := Coordinate'Max (Hi, V (J));
         pragma Loop_Invariant
           (Lo <= Hi and then In_Bounds (V, First, J, Lo, Hi));
      end loop;
   end Bounds_Of;

   procedure Partition_Step
     (V           : in out Coordinate_Array;
      Pivot       : Coordinate;
      Lt, I, Gt   : in out Natural;
      Lw, Hw      : Natural;
      First, Last : Natural;
      Lo, Hi      : Coordinate)
   with
     Pre  => First >= V'First and then Last <= V'Last
             and then Last < Natural'Last
             and then First <= Lw and then Hw <= Last
             and then Lw <= Lt and then Lt < I and then I <= Gt
             and then Gt <= Hw,
     Post => Lw <= Lt and then Lt < I and then I <= Gt + 1 and then Gt <= Hw
             and then Gt - I < Gt'Old - I'Old
             and then (if In_Bounds (V'Old, First, Last, Lo, Hi)
                       then In_Bounds (V, First, Last, Lo, Hi));
   --  One step of the three-way partition of V (Lw .. Hw) around Pivot,
   --  with V (Lw .. Lt - 1) < Pivot, V (Lt .. I - 1) = Pivot and
   --  V (Gt + 1 .. Hw) > Pivot: V (I) joins the first part (exchanged with
   --  V (Lt)), the last part (exchanged with V (Gt)) or the middle one.

   procedure Partition_Step
     (V           : in out Coordinate_Array;
      Pivot       : Coordinate;
      Lt, I, Gt   : in out Natural;
      Lw, Hw      : Natural;
      First, Last : Natural;
      Lo, Hi      : Coordinate)
   is
      pragma Unreferenced (Lw, Hw);
   begin
      if V (I) < Pivot then
         Swap (V, Lt, I, First, Last, Lo, Hi);
         Lt := Lt + 1;
         I := I + 1;
      elsif V (I) > Pivot then
         Swap (V, I, Gt, First, Last, Lo, Hi);
         Gt := Gt - 1;
      else
         I := I + 1;
      end if;
   end Partition_Step;

   Seed_Modulus : constant := 2_147_483_647;
   --  The prime modulus of the pseudo-random pivots (Park and Miller's
   --  generator, multiplier 48271).

   procedure Select_Rank
     (V      : in out Coordinate_Array;
      First  : Natural;
      Last   : Natural;
      K      : Natural;
      Lo, Hi : Coordinate;
      Value  : out Coordinate)
   with
     Pre  => First <= K and then K <= Last and then First >= V'First
             and then Last <= V'Last and then Last < Natural'Last,
     Post => (if In_Bounds (V'Old, First, Last, Lo, Hi)
              then In_Bounds (V, First, Last, Lo, Hi)
                   and then Value >= Lo and then Value <= Hi);
   --  The value of rank K - First (from 0) of V (First .. Last) in
   --  increasing order, V (First .. Last) reordered so that no value after
   --  position K is smaller: three-way partitions (values below, equal to
   --  and above a pivot drawn pseudo-randomly from the window that holds
   --  position K), each of which removes at least the pivot from the
   --  window, so the loop ends (the variant). Every comparison is exact.
   --  Gold (conditional, so that no quantified precondition is needed):
   --  the values stay within a range that held them, and Value lies in
   --  it.

   procedure Select_Rank
     (V      : in out Coordinate_Array;
      First  : Natural;
      Last   : Natural;
      K      : Natural;
      Lo, Hi : Coordinate;
      Value  : out Coordinate)
   is
      Lw   : Natural := First;
      Hw   : Natural := Last;
      Seed : Int64 := 16_807;
      Held : constant Boolean := In_Bounds (V, First, Last, Lo, Hi)
        with Ghost;
   begin
      while Lw < Hw loop
         pragma Loop_Invariant
           (First <= Lw and then Lw <= K and then K <= Hw
            and then Hw <= Last);
         pragma Loop_Invariant (Seed in 0 .. Seed_Modulus - 1);
         pragma Loop_Invariant
           (if Held then In_Bounds (V, First, Last, Lo, Hi));
         pragma Loop_Variant (Decreases => Hw - Lw);
         Seed := Seed * 48_271 mod Seed_Modulus;
         declare
            Pick  : constant Natural :=
              Lw + Natural (Seed mod (Int64 (Hw) - Int64 (Lw) + 1));
            Pivot : constant Coordinate := V (Pick);
            Lt    : Natural := Lw;
            I     : Natural := Lw + 1;
            Gt    : Natural := Hw;
         begin
            --  V (Lw .. Lt - 1) < Pivot, V (Lt .. I - 1) = Pivot (never
            --  empty: it starts with the pivot), V (Gt + 1 .. Hw) > Pivot.
            Swap (V, Lw, Pick, First, Last, Lo, Hi);
            while I <= Gt loop
               pragma Loop_Invariant
                 (Lw <= Lt and then Lt < I and then I <= Gt + 1
                  and then Gt <= Hw);
               pragma Loop_Invariant
                 (if Held then In_Bounds (V, First, Last, Lo, Hi));
               pragma Loop_Variant (Decreases => Gt - I);
               Partition_Step
                 (V, Pivot, Lt, I, Gt, Lw, Hw, First, Last, Lo, Hi);
            end loop;
            if K < Lt then
               Hw := Lt - 1;
            elsif K > Gt then
               Lw := Gt + 1;
            else
               --  V (K) is the pivot's value.
               Lw := K;
               Hw := K;
            end if;
         end;
      end loop;
      pragma Assert (if Held then In_Bounds (V, First, Last, Lo, Hi));
      Value := V (K);
      pragma Assert (if Held then Value >= Lo and then Value <= Hi);
   end Select_Rank;

   procedure Least_After
     (V      : Coordinate_Array;
      First  : Natural;
      Last   : Natural;
      Lo, Hi : Coordinate;
      Value  : out Coordinate)
   with
     Pre  => First <= Last and then First >= V'First
             and then Last <= V'Last and then Last < Natural'Last,
     Post => (if In_Bounds (V, First, Last, Lo, Hi)
              then Value >= Lo and then Value <= Hi);
   --  The least value of V (First .. Last).

   procedure Least_After
     (V      : Coordinate_Array;
      First  : Natural;
      Last   : Natural;
      Lo, Hi : Coordinate;
      Value  : out Coordinate)
   is
      Held : constant Boolean := In_Bounds (V, First, Last, Lo, Hi)
        with Ghost;
   begin
      Value := V (First);
      for J in First + 1 .. Last loop
         Value := Coordinate'Min (Value, V (J));
         pragma Loop_Invariant
           (if Held then Value >= Lo and then Value <= Hi);
      end loop;
   end Least_After;

   procedure Select_Median
     (V      : in out Coordinate_Array;
      First  : Natural;
      Last   : Natural;
      Lo, Hi : out Coordinate;
      Median : out Coordinate)
   with
     Pre  => First <= Last and then First >= V'First
             and then Last <= V'Last and then Last < Natural'Last,
     Post => Lo <= Median and then Median <= Hi;
   --  The least and the greatest value of V (First .. Last) and their
   --  median: the value of rank K = (Last - First) / 2 from First in
   --  increasing order for an odd count, the mean of the values of ranks
   --  K and K + 1 for an even count (the value of rank K + 1 is the least
   --  value after position K once Select_Rank has placed rank K). Every
   --  comparison is exact, so the result is the exact median of the
   --  values; only the mean of the two middle values is rounded. Gold: the
   --  median lies within [Lo, Hi] (the mean is limited to [Lo, Hi], which
   --  acts only when halving a subnormal value loses its last bit).
   --  V (First .. Last) is reordered.

   procedure Select_Median
     (V      : in out Coordinate_Array;
      First  : Natural;
      Last   : Natural;
      Lo, Hi : out Coordinate;
      Median : out Coordinate)
   is
      K     : constant Natural := First + (Last - First) / 2;
      Lower : Coordinate;
      Upper : Coordinate;
   begin
      Bounds_Of (V, First, Last, Lo, Hi);
      Select_Rank (V, First, Last, K, Lo, Hi, Lower);
      if (Last - First) mod 2 = 0 then
         Median := Lower;
      else
         Least_After (V, K + 1, Last, Lo, Hi, Upper);
         Median :=
           Coordinate'Max (Lo, Coordinate'Min (Hi, Lower / 2.0 + Upper / 2.0));
      end if;
   end Select_Median;

   ---------------------------------------------------------------------
   --  Boxes
   ---------------------------------------------------------------------

   subtype Extent is Long_Float range -Extent_Limit .. Extent_Limit;

   subtype Mass is Long_Float range -Mass_Limit .. Mass_Limit;

   function Widened_Low (Value, Half : Long_Float) return Extent
   with
     Pre  => abs Value <= Projection_Limit
             and then Half >= 0.0 and then Half <= Coefficient_Limit,
     Post => Widened_Low'Result <= Value;
   --  Value - Half.

   function Widened_Low (Value, Half : Long_Float) return Extent is
     (Value - Half);

   function Widened_High (Value, Half : Long_Float) return Extent
   with
     Pre  => abs Value <= Projection_Limit
             and then Half >= 0.0 and then Half <= Coefficient_Limit,
     Post => Widened_High'Result >= Value;
   --  Value + Half.

   function Widened_High (Value, Half : Long_Float) return Extent is
     (Value + Half);

   function Middle (Lo, Hi : Extent) return Extent is
     (Lo / 2.0 + Hi / 2.0);
   --  The midpoint of [Lo, Hi].

   function Length (Lo, Hi : Extent) return Long_Float
   with
     Pre  => Lo <= Hi,
     Post => Length'Result >= 0.0
             and then Length'Result <= 2.0 * Extent_Limit;
   --  Hi - Lo.

   function Length (Lo, Hi : Extent) return Long_Float is (Hi - Lo);

   function Center_Coordinate (Origin : Mass; A, B : Extent) return Long_Float
   with Post => abs Center_Coordinate'Result
                  <= Mass_Limit + 2.0 * Extent_Limit;
   --  Origin + A + B: a coordinate of a box's centre.

   function Center_Coordinate (Origin : Mass; A, B : Extent)
                               return Long_Float
   is (Origin + A + B);

   function Box_Along
     (Mass_X, Mass_Y : Mass;
      U_Lo, U_Hi     : Extent;
      V_Lo, V_Hi     : Extent;
      Cos_A, Sin_A   : Long_Float;
      Rotation       : Long_Float) return KS.Ks_Rectangle_Affine
   with
     Pre  => U_Lo <= U_Hi and then V_Lo <= V_Hi
             and then abs Cos_A <= 1.0 and then abs Sin_A <= 1.0
             and then abs Rotation <= Max_Extrema_Angle,
     Post => KS.Valid_Rectangle_Affine (Box_Along'Result);
   --  The rectangle with the extents [U_Lo, U_Hi] along (Cos_A, Sin_A)
   --  and [V_Lo, V_Hi] along (-Sin_A, Cos_A), measured from the centre of
   --  mass (Mass_X, Mass_Y), turned by Rotation (the arithmetic of the
   --  principal-axis box of AMV.Kernels.Blob.Measures: Mass + a - b is
   --  Mass + a + (-b), exactly).

   function Box_Along
     (Mass_X, Mass_Y : Mass;
      U_Lo, U_Hi     : Extent;
      V_Lo, V_Hi     : Extent;
      Cos_A, Sin_A   : Long_Float;
      Rotation       : Long_Float) return KS.Ks_Rectangle_Affine
   is
      U_Mid : constant Extent := Middle (U_Lo, U_Hi);
      V_Mid : constant Extent := Middle (V_Lo, V_Hi);
   begin
      return (Center_X      =>
                Center_Coordinate (Mass_X, N.Times_Unit (U_Mid, Cos_A),
                                   -N.Times_Unit (V_Mid, Sin_A)),
              Center_Y      =>
                Center_Coordinate (Mass_Y, N.Times_Unit (U_Mid, Sin_A),
                                   N.Times_Unit (V_Mid, Cos_A)),
              Side_X_Length => Length (U_Lo, U_Hi),
              Side_Y_Length => Length (V_Lo, V_Hi),
              Rotation      => Rotation,
              Skew          => 0.0);
   end Box_Along;

   function Aspect (Width, Height : Long_Float) return Long_Float
   with
     Pre  => Width in 0.0 .. 2.0 * Extent_Limit
             and then Height in 0.0 .. 2.0 * Extent_Limit,
     Post => Aspect'Result in 0.0 .. Ratio_Limit;
   --  Height / Width, 0 when Width is 0 or the ratio exceeds Ratio_Limit.

   function Aspect (Width, Height : Long_Float) return Long_Float is
      Result : Long_Float;
      Fits   : Boolean;
   begin
      if Width > 0.0 then
         N.Ratio_Within (Height, Width, Ratio_Limit, Result, Fits);
         return (if Fits then Result else 0.0);
      end if;
      return 0.0;
   end Aspect;

   ---------------------------------------------------------------------
   --  The extrema-angle measures of every feature
   ---------------------------------------------------------------------

   subtype Position is Long_Float
     range -(3.0 * Mass_Limit) .. 3.0 * Mass_Limit;

   function Origin_Along
     (Mass_X, Mass_Y : Mass;
      Cos_A, Sin_A   : Long_Float) return Long_Float
   with
     Pre  => abs Cos_A <= 1.0 and then abs Sin_A <= 1.0,
     Post => abs Origin_Along'Result <= 2.0 * Mass_Limit;
   --  Mass_X Cos_A + Mass_Y Sin_A: the coordinate of the centre of mass
   --  along the axis (Cos_A, Sin_A).

   function Origin_Along
     (Mass_X, Mass_Y : Mass;
      Cos_A, Sin_A   : Long_Float) return Long_Float
   is (N.Times_Unit (Mass_X, Cos_A) + N.Times_Unit (Mass_Y, Sin_A));

   procedure Place
     (Origin             : Long_Float;
      Lo, Middle, Hi     : Extent;
      At_Lo, At_Mid      : out Position;
      At_Hi              : out Position)
   with
     Pre  => abs Origin <= 2.0 * Mass_Limit
             and then Lo <= Middle and then Middle <= Hi,
     Post => At_Lo <= At_Mid and then At_Mid <= At_Hi;
   --  Origin + Lo, Origin + Middle and Origin + Hi (in this order, since
   --  rounding is monotonic).

   procedure Place
     (Origin             : Long_Float;
      Lo, Middle, Hi     : Extent;
      At_Lo, At_Mid      : out Position;
      At_Hi              : out Position)
   is
   begin
      At_Lo := Origin + Lo;
      At_Mid := Origin + Middle;
      At_Hi := Origin + Hi;
   end Place;

   procedure Axis_Measures
     (Origin      : Long_Float;
      Stat        : Axis_Stat;
      Half        : Long_Float;
      Lo, Hi      : out Extent;
      Min, Median : out Position;
      Max, Center : out Position;
      Size        : out Long_Float)
   with
     Pre  => abs Origin <= 2.0 * Mass_Limit
             and then Half >= 0.0 and then Half <= Coefficient_Limit,
     Post => Lo <= Hi and then Min <= Median and then Median <= Max
             and then Size >= 0.0 and then Size <= 2.0 * Extent_Limit;
   --  Along one axis: the extent [Lo, Hi] of the mapped pixel squares
   --  (the extent of the pixel centres in Stat widened by Half), measured
   --  from the centre of mass, and the positions Min, Median, Max, Center
   --  and the length Size = Hi - Lo, with the centre of mass at Origin.

   procedure Axis_Measures
     (Origin      : Long_Float;
      Stat        : Axis_Stat;
      Half        : Long_Float;
      Lo, Hi      : out Extent;
      Min, Median : out Position;
      Max, Center : out Position;
      Size        : out Long_Float)
   is
   begin
      Lo := Widened_Low (Stat.Lo, Half);
      Hi := Widened_High (Stat.Hi, Half);
      Place (Origin, Lo, Stat.Median, Hi, Min, Median, Max);
      Center := Origin + Middle (Lo, Hi);
      Size := Length (Lo, Hi);
   end Axis_Measures;

   procedure Finish_Item
     (U, V           : Axis_Stat;
      Half_U, Half_V : Long_Float;
      Cos_A, Sin_A   : Long_Float;
      Angle          : Long_Float;
      Item           : in out Ks_Blob_Result)
   with
     Pre  => Half_U >= 0.0 and then Half_U <= Coefficient_Limit
             and then Half_V >= 0.0 and then Half_V <= Coefficient_Limit
             and then abs Cos_A <= 1.0 and then abs Sin_A <= 1.0
             and then abs Angle <= Max_Extrema_Angle,
     Post => Item.Extrema_Angle_Min_X <= Item.Median_Extrema_Angle_X
             and then Item.Median_Extrema_Angle_X <= Item.Extrema_Angle_Max_X
             and then Item.Extrema_Angle_Min_Y <= Item.Median_Extrema_Angle_Y
             and then Item.Median_Extrema_Angle_Y
                        <= Item.Extrema_Angle_Max_Y;
   --  The extrema-angle box and measures of one item from the statistics
   --  U and V of its pixel centres along the two axes (measured from the
   --  centre of mass) and the half extents Half_U, Half_V of a mapped
   --  pixel square along them. Gold: Min <= Median <= Max on both axes.

   procedure Finish_Item
     (U, V           : Axis_Stat;
      Half_U, Half_V : Long_Float;
      Cos_A, Sin_A   : Long_Float;
      Angle          : Long_Float;
      Item           : in out Ks_Blob_Result)
   is
      Mass_X : constant Mass := N.Clamp (Item.Center_Of_Mass_X, Mass_Limit);
      Mass_Y : constant Mass := N.Clamp (Item.Center_Of_Mass_Y, Mass_Limit);
      U_Lo, U_Hi, V_Lo, V_Hi                 : Extent;
      Min_X, Median_X, Max_X, Center_X       : Position;
      Min_Y, Median_Y, Max_Y, Center_Y       : Position;
      Width, Height                          : Long_Float;
   begin
      Axis_Measures (Origin_Along (Mass_X, Mass_Y, Cos_A, Sin_A), U, Half_U,
                     U_Lo, U_Hi, Min_X, Median_X, Max_X, Center_X, Width);
      Axis_Measures (Origin_Along (Mass_Y, -Mass_X, Cos_A, Sin_A), V, Half_V,
                     V_Lo, V_Hi, Min_Y, Median_Y, Max_Y, Center_Y, Height);
      Item.Extrema_Angle_Min_X := Min_X;
      Item.Extrema_Angle_Max_X := Max_X;
      Item.Median_Extrema_Angle_X := Median_X;
      Item.Extrema_Angle_Center_X := Center_X;
      Item.Extrema_Angle_Width := Width;
      Item.Extrema_Angle_Min_Y := Min_Y;
      Item.Extrema_Angle_Max_Y := Max_Y;
      Item.Median_Extrema_Angle_Y := Median_Y;
      Item.Extrema_Angle_Center_Y := Center_Y;
      Item.Extrema_Angle_Height := Height;
      Item.Extrema_Angle_Aspect := Aspect (Width, Height);
      Item.Extrema_Angle_Box :=
        Box_Along (Mass_X, Mass_Y, U_Lo, U_Hi, V_Lo, V_Hi, Cos_A, Sin_A,
                   Angle);
   end Finish_Item;

   procedure Scatter
     (Map    : Int32_Matrix;
      Count  : Int32;
      Area   : Int64_Array;
      Cx, Cy : Real_Array;
      P, Q   : Long_Float;
      Start  : Int64_Array;
      Fill   : in out Int64_Array;
      Values : in out Coordinate_Array)
   with
     Pre => Count >= 1 and then Area'First = 0
            and then Int64 (Area'Last) = Int64 (Count) - 1
            and then Cx'First = 0 and then Cx'Last = Area'Last
            and then Cy'First = 0 and then Cy'Last = Area'Last
            and then Start'First = 0 and then Start'Last = Area'Last
            and then Fill'First = 0 and then Fill'Last = Area'Last
            and then Values'First = 0
            and then Valid_Row (P, Q);
   --  The coordinates along the row (P, Q) of the pixel centres of every
   --  feature K, written to Values (Start (K) + Fill (K) ..) in raster
   --  order while Fill (K) (zero on entry) is below Area (K); Fill (K)
   --  counts them.

   procedure Scatter
     (Map    : Int32_Matrix;
      Count  : Int32;
      Area   : Int64_Array;
      Cx, Cy : Real_Array;
      P, Q   : Long_Float;
      Start  : Int64_Array;
      Fill   : in out Int64_Array;
      Values : in out Coordinate_Array)
   is
   begin
      for Y in Map'Range (1) loop
         for X in Map'Range (2) loop
            declare
               Id : constant Int32 := Map (Y, X);
            begin
               if Id >= 1 and then Id <= Count then
                  declare
                     K : constant Natural := Natural (Id - 1);
                     S : constant Int64 := Start (K);
                     F : constant Int64 := Fill (K);
                  begin
                     if S >= 0 and then F >= 0 and then F < Area (K)
                       and then S <= Int64 (Values'Last)
                       and then F <= Int64 (Values'Last) - S
                     then
                        Values (Natural (S + F)) :=
                          Projection (P, Q, N.Clamp (Cx (K), Center_Limit),
                                      N.Clamp (Cy (K), Center_Limit), X, Y);
                        Fill (K) := F + 1;
                     end if;
                  end;
               end if;
            end;
         end loop;
      end loop;
   end Scatter;

   procedure Feature_Stats
     (Start  : Int64_Array;
      Fill   : Int64_Array;
      Values : in out Coordinate_Array;
      Stats  : in out Stat_Array)
   with
     Pre => Start'First = 0 and then Fill'First = 0
            and then Stats'First = 0
            and then Start'Last = Stats'Last and then Fill'Last = Stats'Last
            and then Values'First = 0 and then Values'Last < Natural'Last;
   --  The statistics of every feature K from its coordinates
   --  Values (Start (K) .. Start (K) + Fill (K) - 1) (unchanged for none).

   procedure Feature_Stats
     (Start  : Int64_Array;
      Fill   : Int64_Array;
      Values : in out Coordinate_Array;
      Stats  : in out Stat_Array)
   is
   begin
      for K in Stats'Range loop
         declare
            S  : constant Int64 := Start (K);
            F  : constant Int64 := Fill (K);
            Lo, Hi, Median : Coordinate;
         begin
            if S >= 0 and then S <= Int64 (Values'Last)
              and then F >= 1 and then F <= Int64 (Values'Last) - S + 1
            then
               Select_Median
                 (Values, Natural (S), Natural (S + F - 1), Lo, Hi, Median);
               Stats (K) := (Lo => Lo, Median => Median, Hi => Hi);
            end if;
         end;
      end loop;
   end Feature_Stats;

   procedure Compute_Extrema
     (Map     : Int32_Matrix;
      Count   : Int32;
      Area    : Int64_Array;
      Cx, Cy  : Real_Array;
      T       : KT.Ks_Transform_2D_Linear;
      Angle   : Long_Float;
      Items   : in out Result_Array;
      Status  : out Ks_Status)
   is
      Cos_A  : constant Long_Float := EF.Cos (Angle);
      Sin_A  : constant Long_Float := EF.Sin (Angle);
      Pu     : constant Long_Float := Turned (T.A, T.C, Cos_A, Sin_A);
      Qu     : constant Long_Float := Turned (T.B, T.D, Cos_A, Sin_A);
      Pv     : constant Long_Float := Turned (T.C, -T.A, Cos_A, Sin_A);
      Qv     : constant Long_Float := Turned (T.D, -T.B, Cos_A, Sin_A);
      Half_U : constant Long_Float := Half_Square (Pu, Qu);
      Half_V : constant Long_Float := Half_Square (Pv, Qv);
      Last   : constant Natural := Natural (Count) - 1;
      Start  : Int64_Array_Access;
      Fill   : Int64_Array_Access;
      U      : Stat_Array_Access;
      V      : Stat_Array_Access;
      Values : Coordinate_Array_Access;
      Total  : Int64 := 0;
   begin
      Allocate_Int64_Array (Last, Start);
      Allocate_Int64_Array (Last, Fill);
      Allocate_Stats (Last, U);
      Allocate_Stats (Last, V);
      if Start = null or else Fill = null or else U = null or else V = null
      then
         Free (Start);
         Free (Fill);
         Free (U);
         Free (V);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Execute: out of memory for the extrema-angle "
                      & "measures");
         return;
      end if;

      --  Each feature's coordinates start after those of the features
      --  before it.
      for K in Start'Range loop
         Start (K) := Total;
         Total := Int64'Min
           (Total + Int64'Max (0, Int64'Min (Area (K), Max_Region_Pixels)),
            Max_Region_Pixels);
         pragma Loop_Invariant (Total in 0 .. Max_Region_Pixels);
      end loop;

      if Total >= 1 then
         Allocate_Coordinates (Natural (Total) - 1, Values);
         if Values = null then
            Free (Start);
            Free (Fill);
            Free (U);
            Free (V);
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Execute: out of memory for the extrema-angle "
                         & "medians");
            return;
         end if;
         Scatter (Map, Count, Area, Cx, Cy, Pu, Qu, Start.all, Fill.all,
                  Values.all);
         Feature_Stats (Start.all, Fill.all, Values.all, U.all);
         for K in Fill'Range loop
            Fill (K) := 0;
         end loop;
         Scatter (Map, Count, Area, Cx, Cy, Pv, Qv, Start.all, Fill.all,
                  Values.all);
         Feature_Stats (Start.all, Fill.all, Values.all, V.all);
         Free (Values);
      end if;

      for K in Items'Range loop
         pragma Loop_Invariant
           (U /= null and then V /= null
            and then U'First = 0 and then U'Last = Last
            and then V'First = 0 and then V'Last = Last);
         Finish_Item (U (K), V (K), Half_U, Half_V, Cos_A, Sin_A, Angle,
                      Items (K));
      end loop;
      Free (Start);
      Free (Fill);
      Free (U);
      Free (V);
      Set_Success (Status);
   end Compute_Extrema;

   ---------------------------------------------------------------------
   --  On demand
   ---------------------------------------------------------------------

   procedure Box_At_Angle
     (Map    : Int32_Matrix;
      Id     : Int32;
      Cx, Cy : Long_Float;
      Mass_X : Long_Float;
      Mass_Y : Long_Float;
      T      : KT.Ks_Transform_2D_Linear;
      Angle  : Long_Float;
      Box    : out KS.Ks_Rectangle_Affine;
      Found  : out Boolean)
   is
      Cos_A   : constant Long_Float := EF.Cos (Angle);
      Sin_A   : constant Long_Float := EF.Sin (Angle);
      Pu      : constant Long_Float := Turned (T.A, T.C, Cos_A, Sin_A);
      Qu      : constant Long_Float := Turned (T.B, T.D, Cos_A, Sin_A);
      Pv      : constant Long_Float := Turned (T.C, -T.A, Cos_A, Sin_A);
      Qv      : constant Long_Float := Turned (T.D, -T.B, Cos_A, Sin_A);
      Half_U  : constant Long_Float := Half_Square (Pu, Qu);
      Half_V  : constant Long_Float := Half_Square (Pv, Qv);
      U_Lo, U_Hi, V_Lo, V_Hi : Long_Float;
      Found_U : Boolean;
      Found_V : Boolean;
   begin
      Feature_Extent (Map, Id, Pu, Qu, Cx, Cy, U_Lo, U_Hi, Found_U);
      Feature_Extent (Map, Id, Pv, Qv, Cx, Cy, V_Lo, V_Hi, Found_V);
      Found := Found_U and then Found_V;
      if Found then
         Box := Box_Along (Mass_X, Mass_Y, Widened_Low (U_Lo, Half_U),
                           Widened_High (U_Hi, Half_U),
                           Widened_Low (V_Lo, Half_V),
                           Widened_High (V_Hi, Half_V), Cos_A, Sin_A, Angle);
      else
         Box := (others => <>);
      end if;
   end Box_At_Angle;

   procedure Median_Along
     (Map    : Int32_Matrix;
      Id     : Int32;
      Pixels : Int32;
      Cx, Cy : Long_Float;
      P, Q   : Long_Float;
      Median : out Long_Float;
      Found  : out Boolean;
      Memory : out Boolean)
   is
      Values : Coordinate_Array_Access;
      Used   : Natural := 0;
      Unused_Lo, Unused_Hi, Value : Coordinate;
   begin
      Median := 0.0;
      Found := False;
      Memory := True;
      if Pixels < 1 then
         return;
      end if;
      Allocate_Coordinates (Natural (Pixels) - 1, Values);
      if Values = null then
         Memory := False;
         return;
      end if;
      for Y in Map'Range (1) loop
         for X in Map'Range (2) loop
            pragma Loop_Invariant
              (Values /= null and then Values'First = 0
               and then Values'Last = Natural (Pixels) - 1
               and then Used <= Values'Last + 1);
            if Map (Y, X) = Id and then Used <= Values'Last then
               Values (Used) := Projection (P, Q, Cx, Cy, X, Y);
               Used := Used + 1;
            end if;
         end loop;
         pragma Loop_Invariant
           (Values /= null and then Values'First = 0
            and then Values'Last = Natural (Pixels) - 1
            and then Used <= Values'Last + 1);
      end loop;
      if Used >= 1 then
         Select_Median
           (Values.all, 0, Used - 1, Unused_Lo, Unused_Hi, Value);
         Median := Value;
         Found := True;
      end if;
      Free (Values);
   end Median_Along;

end AMV.Kernels.Blob.Extrema;
