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

package body AMV.Kernels.Blob.Measures with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package N renames AMV.Kernels.Numerics;

   --  Bounds of the quantities below. Pixel coordinates and counts are
   --  below 2**31, so an offset from a feature's first pixel is below
   --  2**32 in magnitude, a sum of offsets below 2**63, a sum of squared
   --  offsets below 2**94. The sums are read and written through clamps
   --  at these bounds, which never act (docs/PROOF.md), so that every
   --  bound below holds without a quantified invariant over the tables.

   Pixel_Limit  : constant := 2.0 ** 31;
   Offset_Limit : constant := 2.0 ** 32;
   Center_Limit : constant := 2.0 ** 33;
   Delta_Limit  : constant := 2.0 ** 34;
   Sum_1_Limit  : constant := 2.0 ** 63;
   Sum_2_Limit  : constant := 2.0 ** 94;
   Moment_Limit : constant := 2.0 ** 97;
   Square_Limit : constant := 2.0 ** 128;
   Cross_Limit  : constant := 2.0 ** 129;
   Shape_Limit  : constant := 2.0 ** 229;
   Proj_Limit   : constant := 2.0 ** 65;
   Extent_Limit : constant := 2.0 ** 101;
   Count_Limit  : constant := 2**40;
   Ratio_Limit  : constant := 1.0E150;

   --  The weighted sums of a soft segmentation are sums of levels (at most
   --  Max_Softness + 1 = 255 < 2**8) times the terms above: a level sum
   --  below 2**39, a sum of weighted offsets below 2**71, of weighted
   --  squared offsets below 2**103. They are read and written through
   --  clamps at these bounds (which never act) as the plain sums are.

   Level_Limit         : constant := 2.0 ** 8;
   Offset_Square_Limit : constant := 2.0 ** 64;
   Weight_Limit        : constant := 2**40;
   W_Sum_1_Limit       : constant := 2.0 ** 71;
   W_Sum_2_Limit       : constant := 2.0 ** 103;

   type Accumulator is record
      Sx, Sy, Sxx, Sxy, Syy : Long_Float := 0.0;
      X_Min   : Int32 := Int32'Last;
      X_Max   : Int32 := -1;
      Y_Min   : Int32 := Int32'Last;
      Y_Max   : Int32 := -1;
      Clipped : Boolean := False;
      H, V, D, A : Int64 := 0;
      Cx, Cy  : Long_Float := 0.0;
      Angle   : Long_Float := 0.0;
      Cos_A   : Long_Float := 1.0;
      Sin_A   : Long_Float := 0.0;
      Pu, Qu, Pv, Qv : Long_Float := 0.0;
      U_Min, V_Min, S_Min, R_Min : Long_Float := Extent_Limit;
      U_Max, V_Max, S_Max, R_Max : Long_Float := -Extent_Limit;
      W                     : Int64 := 0;
      Wx, Wy, Wxx, Wxy, Wyy : Long_Float := 0.0;
   end record;
   --  The running sums of one feature: offsets of its pixels from its
   --  first pixel (Sx .. Syy), for a blob of a soft segmentation also the
   --  sum W of its pixels' levels and the sums of the offsets times the
   --  levels (Wx .. Wyy), its pixel bounding box, whether it touches
   --  the outside, its boundary segments of marching squares (H
   --  horizontal, V vertical, D along (1, 1), A along (1, -1)), and after
   --  the moments: its centroid in pixel space, its principal angle in
   --  the selected space, the projections Pu, Qu (Pv, Qv) of a pixel
   --  offset onto the principal axis (its normal), and the extents of its
   --  pixel centres along the principal axes (U, V) and the selected
   --  space's axes (S, R).

   type Accumulator_Array is array (Natural range <>) of Accumulator;
   type Accumulator_Array_Access is access Accumulator_Array;

   procedure Free is new Ada.Unchecked_Deallocation
     (Accumulator_Array, Accumulator_Array_Access);

   procedure Allocate_Accumulators
     (Last : Natural;
      List : out Accumulator_Array_Access)
   with
     Global => null,
     Post   => (if List /= null
                then List'First = 0 and then List'Last = Last);
   --  A new table of Last + 1 accumulators with the record's defaults, or
   --  null when the memory cannot be allocated. Trusted: the allocator
   --  raises Storage_Error, which SPARK cannot express.

   procedure Allocate_Accumulators
     (Last : Natural;
      List : out Accumulator_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      List := new Accumulator_Array (0 .. Last);
   exception
      when Storage_Error =>
         List := null;
   end Allocate_Accumulators;

   ---------------------------------------------------------------------
   --  Bounded arithmetic
   ---------------------------------------------------------------------

   function Add_Clamped (Sum, Term, Limit : Long_Float) return Long_Float
   with
     Pre  => Limit >= 1.0 and then Limit <= 2.0 ** 1000
             and then abs Term <= Limit,
     Post => abs Add_Clamped'Result <= Limit;
   --  Sum + Term, Sum read and the result kept within +/-Limit.

   function Add_Clamped (Sum, Term, Limit : Long_Float) return Long_Float is
     (N.Clamp (N.Clamp (Sum, Limit) + Term, Limit));

   function Non_Negative (X, Limit : Long_Float) return Long_Float
   with
     Pre  => Limit >= 0.0,
     Post => Non_Negative'Result in 0.0 .. Limit;
   --  X limited to [0, Limit].

   function Non_Negative (X, Limit : Long_Float) return Long_Float is
     (if X >= 0.0 then (if X <= Limit then X else Limit) else 0.0);

   function Quotient (X, Y, Limit : Long_Float) return Long_Float
   with
     Pre  => abs X <= N.Mul_Limit and then Y > 0.0
             and then Y <= N.Mul_Limit
             and then Limit >= 1.0 and then Limit <= N.Mul_Limit,
     Post => abs Quotient'Result <= Limit;
   --  X / Y when its magnitude is at most Limit, otherwise 0.0.

   function Quotient (X, Y, Limit : Long_Float) return Long_Float is
      Result : Long_Float;
      Fits   : Boolean;
   begin
      if X >= 0.0 then
         N.Ratio_Within (X, Y, Limit, Result, Fits);
         return (if Fits then Result else 0.0);
      else
         N.Ratio_Within (-X, Y, Limit, Result, Fits);
         return (if Fits then -Result else 0.0);
      end if;
   end Quotient;

   function Count_Value (Count : Int64) return Long_Float
   with Post => Count_Value'Result in 0.0 .. Long_Float (Count_Limit);
   --  A segment count as a real, read through a clamp.

   function Count_Value (Count : Int64) return Long_Float is
     (Long_Float (Int64'Max (0, Int64'Min (Count, Count_Limit))));

   procedure Bump (Count : in out Int64; By : Int64)
   with Pre => By in 1 .. 2;
   --  Count + By, up to Count_Limit.

   procedure Bump (Count : in out Int64; By : Int64) is
   begin
      if Count >= 0 and then Count < Count_Limit then
         Count := Count + By;
      end if;
   end Bump;

   function Inside (Region : access constant KR.Ks_Pixel_Region_Data;
                    X, Y   : Int64) return Boolean
   is
     (X in Int64 (Int32'First) .. Int64 (Int32'Last)
      and then Y in Int64 (Int32'First) .. Int64 (Int32'Last)
      and then KR.Contains (Region, Int32 (X), Int32 (Y)));
   --  Pixel (X, Y) belongs to the region.

   function Id_At
     (Map   : Int32_Matrix;
      Count : Int32;
      Y, X  : Int64) return Int32
   with Post => Id_At'Result = 0 or else Id_At'Result in 1 .. Count;
   --  The feature number (ID + 1) of pixel (X, Y), 0 for none or beyond
   --  the map.

   function Id_At
     (Map   : Int32_Matrix;
      Count : Int32;
      Y, X  : Int64) return Int32
   is
   begin
      if Y in Int64 (Map'First (1)) .. Int64 (Map'Last (1))
        and then X in Int64 (Map'First (2)) .. Int64 (Map'Last (2))
      then
         declare
            Id : constant Int32 := Map (Natural (Y), Natural (X));
         begin
            return (if Id >= 1 and then Id <= Count then Id else 0);
         end;
      end if;
      return 0;
   end Id_At;

   ---------------------------------------------------------------------
   --  Passes over the pixels
   ---------------------------------------------------------------------

   procedure Sum_Pass
     (Region  : access constant KR.Ks_Pixel_Region_Data;
      Map     : Int32_Matrix;
      Count   : Int32;
      First_X : Int32_Array;
      First_Y : Int32_Array;
      Acc     : in out Accumulator_Array)
   with
     Pre => Count >= 1 and then Acc'First = 0
            and then Int64 (Acc'Last) = Int64 (Count) - 1
            and then First_X'First = 0 and then First_X'Last = Acc'Last
            and then First_Y'First = 0 and then First_Y'Last = Acc'Last;
   --  The sums of offsets, the pixel boxes and the clipping flags.

   procedure Sum_Pass
     (Region  : access constant KR.Ks_Pixel_Region_Data;
      Map     : Int32_Matrix;
      Count   : Int32;
      First_X : Int32_Array;
      First_Y : Int32_Array;
      Acc     : in out Accumulator_Array)
   is
   begin
      for Y in Map'Range (1) loop
         for X in Map'Range (2) loop
            declare
               Id : constant Int32 := Map (Y, X);
            begin
               if Id >= 1 and then Id <= Count then
                  declare
                     K  : constant Natural := Natural (Id - 1);
                     DX : constant Long_Float :=
                       N.Clamp (Long_Float (Int64 (X) - Int64 (First_X (K))),
                                Offset_Limit);
                     DY : constant Long_Float :=
                       N.Clamp (Long_Float (Int64 (Y) - Int64 (First_Y (K))),
                                Offset_Limit);
                     XI : constant Int64 := Int64 (X);
                     YI : constant Int64 := Int64 (Y);
                  begin
                     Acc (K).Sx := Add_Clamped (Acc (K).Sx, DX, Sum_1_Limit);
                     Acc (K).Sy := Add_Clamped (Acc (K).Sy, DY, Sum_1_Limit);
                     Acc (K).Sxx :=
                       Add_Clamped
                         (Acc (K).Sxx, N.Square_Within (DX, Offset_Limit),
                          Sum_2_Limit);
                     Acc (K).Sxy :=
                       Add_Clamped
                         (Acc (K).Sxy,
                          N.Mul_Within (DX, DY, Offset_Limit, Offset_Limit),
                          Sum_2_Limit);
                     Acc (K).Syy :=
                       Add_Clamped
                         (Acc (K).Syy, N.Square_Within (DY, Offset_Limit),
                          Sum_2_Limit);
                     Acc (K).X_Min := Int32'Min (Acc (K).X_Min, Int32 (X));
                     Acc (K).X_Max := Int32'Max (Acc (K).X_Max, Int32 (X));
                     Acc (K).Y_Min := Int32'Min (Acc (K).Y_Min, Int32 (Y));
                     Acc (K).Y_Max := Int32'Max (Acc (K).Y_Max, Int32 (Y));
                     if not Inside (Region, XI - 1, YI)
                       or else not Inside (Region, XI + 1, YI)
                       or else not Inside (Region, XI, YI - 1)
                       or else not Inside (Region, XI, YI + 1)
                     then
                        Acc (K).Clipped := True;
                     end if;
                  end;
               end if;
            end;
         end loop;
      end loop;
   end Sum_Pass;

   function Pixel_Weight (Level, Full : Int32) return Int32
   with
     Pre  => Full in 1 .. Max_Softness + 1,
     Post => Pixel_Weight'Result in 1 .. Full;
   --  The weight, in levels, of a pixel of a blob: its level, or Full for
   --  a pixel of level 0 (a hole that the cleanup filled into the blob).
   --  (A level above Full cannot occur; it is read as Full.)

   function Pixel_Weight (Level, Full : Int32) return Int32 is
     (if Level >= 1 and then Level <= Full then Level else Full);

   procedure Weight_Pass
     (Map     : Int32_Matrix;
      Count   : Int32;
      Kind    : Int32_Array;
      First_X : Int32_Array;
      First_Y : Int32_Array;
      Levels  : U8_Matrix;
      Full    : Int32;
      Acc     : in out Accumulator_Array)
   with
     Pre => Count >= 1 and then Acc'First = 0
            and then Int64 (Acc'Last) = Int64 (Count) - 1
            and then Kind'First = 0 and then Kind'Last = Acc'Last
            and then First_X'First = 0 and then First_X'Last = Acc'Last
            and then First_Y'First = 0 and then First_Y'Last = Acc'Last
            and then Levels'First (1) = Map'First (1)
            and then Levels'Last (1) = Map'Last (1)
            and then Levels'First (2) = Map'First (2)
            and then Levels'Last (2) = Map'Last (2)
            and then Full in 1 .. Max_Softness + 1;
   --  The level sums of the blobs of a soft segmentation: W and the
   --  offsets from the first pixel times the weights (Wx .. Wyy).

   procedure Weight_Pass
     (Map     : Int32_Matrix;
      Count   : Int32;
      Kind    : Int32_Array;
      First_X : Int32_Array;
      First_Y : Int32_Array;
      Levels  : U8_Matrix;
      Full    : Int32;
      Acc     : in out Accumulator_Array)
   is
   begin
      for Y in Map'Range (1) loop
         for X in Map'Range (2) loop
            declare
               Id : constant Int32 := Map (Y, X);
            begin
               if Id >= 1 and then Id <= Count
                 and then Kind (Natural (Id - 1)) = Label_Blob
               then
                  declare
                     K  : constant Natural := Natural (Id - 1);
                     Wt : constant Int32 :=
                       Pixel_Weight (Int32 (Levels (Y, X)), Full);
                     WL : constant Long_Float := Long_Float (Wt);
                     DX : constant Long_Float :=
                       N.Clamp (Long_Float (Int64 (X) - Int64 (First_X (K))),
                                Offset_Limit);
                     DY : constant Long_Float :=
                       N.Clamp (Long_Float (Int64 (Y) - Int64 (First_Y (K))),
                                Offset_Limit);
                  begin
                     if Acc (K).W >= 0 and then Acc (K).W < Weight_Limit then
                        Acc (K).W := Acc (K).W + Int64 (Wt);
                     end if;
                     Acc (K).Wx :=
                       Add_Clamped
                         (Acc (K).Wx,
                          N.Mul_Within (WL, DX, Level_Limit, Offset_Limit),
                          W_Sum_1_Limit);
                     Acc (K).Wy :=
                       Add_Clamped
                         (Acc (K).Wy,
                          N.Mul_Within (WL, DY, Level_Limit, Offset_Limit),
                          W_Sum_1_Limit);
                     Acc (K).Wxx :=
                       Add_Clamped
                         (Acc (K).Wxx,
                          N.Mul_Within
                            (WL, N.Square_Within (DX, Offset_Limit),
                             Level_Limit, Offset_Square_Limit),
                          W_Sum_2_Limit);
                     Acc (K).Wxy :=
                       Add_Clamped
                         (Acc (K).Wxy,
                          N.Mul_Within
                            (WL,
                             N.Mul_Within (DX, DY, Offset_Limit,
                                           Offset_Limit),
                             Level_Limit, Offset_Square_Limit),
                          W_Sum_2_Limit);
                     Acc (K).Wyy :=
                       Add_Clamped
                         (Acc (K).Wyy,
                          N.Mul_Within
                            (WL, N.Square_Within (DY, Offset_Limit),
                             Level_Limit, Offset_Square_Limit),
                          W_Sum_2_Limit);
                  end;
               end if;
            end;
         end loop;
      end loop;
   end Weight_Pass;

   procedure Add_Cell
     (E                  : in out Accumulator;
      TL, TR, BL, BR     : Boolean;
      Is_Blob            : Boolean)
   with Global => null;
   --  The boundary segments of one feature in one 2 x 2 cell of pixel
   --  centres (TL top left, ..., BR bottom right: the corners that belong
   --  to the feature). A corner alone (or alone outside) is cut by a
   --  diagonal of half a pixel's diagonal, two corners on a side by a
   --  straight segment of one pixel, two opposite corners by two
   --  diagonals that join them for a blob (8-connected) and separate them
   --  for a hole (4-connected).

   procedure Add_Cell
     (E                  : in out Accumulator;
      TL, TR, BL, BR     : Boolean;
      Is_Blob            : Boolean)
   is
      Corners : constant Natural :=
        Boolean'Pos (TL) + Boolean'Pos (TR) + Boolean'Pos (BL)
        + Boolean'Pos (BR);
   begin
      case Corners is
         when 1 =>
            if TL or else BR then
               Bump (E.A, 1);
            else
               Bump (E.D, 1);
            end if;
         when 3 =>
            if not TL or else not BR then
               Bump (E.A, 1);
            else
               Bump (E.D, 1);
            end if;
         when 2 =>
            if TL = TR then
               Bump (E.H, 1);
            elsif TL = BL then
               Bump (E.V, 1);
            elsif TL = Is_Blob then
               Bump (E.D, 2);
            else
               Bump (E.A, 2);
            end if;
         when others =>
            null;
      end case;
   end Add_Cell;

   procedure Cell_Pass
     (Map   : Int32_Matrix;
      Count : Int32;
      Kind  : Int32_Array;
      Acc   : in out Accumulator_Array)
   with
     Pre => Count >= 1 and then Acc'First = 0
            and then Int64 (Acc'Last) = Int64 (Count) - 1
            and then Kind'First = 0 and then Kind'Last = Acc'Last;
   --  The boundary segments of every feature (marching squares over the
   --  cells of the map, one row and column beyond it on each side).

   procedure Cell_Pass
     (Map   : Int32_Matrix;
      Count : Int32;
      Kind  : Int32_Array;
      Acc   : in out Accumulator_Array)
   is
      procedure Add (Id, A, B, C, D : Int32)
      with Pre => Id in 1 .. Count and then Acc'First = 0
                  and then Int64 (Acc'Last) = Int64 (Count) - 1
                  and then Kind'First = 0 and then Kind'Last = Acc'Last;
      --  The cell's segments of feature Id.

      procedure Add (Id, A, B, C, D : Int32) is
         K : constant Natural := Natural (Id - 1);
      begin
         Add_Cell (Acc (K), A = Id, B = Id, C = Id, D = Id,
                   Kind (K) = Label_Blob);
      end Add;
   begin
      for CY in Int64 (Map'First (1)) - 1 .. Int64 (Map'Last (1)) loop
         for CX in Int64 (Map'First (2)) - 1 .. Int64 (Map'Last (2)) loop
            declare
               A : constant Int32 := Id_At (Map, Count, CY, CX);
               B : constant Int32 := Id_At (Map, Count, CY, CX + 1);
               C : constant Int32 := Id_At (Map, Count, CY + 1, CX);
               D : constant Int32 := Id_At (Map, Count, CY + 1, CX + 1);
            begin
               if A /= 0 then
                  Add (A, A, B, C, D);
               end if;
               if B /= 0 and then B /= A then
                  Add (B, A, B, C, D);
               end if;
               if C /= 0 and then C /= A and then C /= B then
                  Add (C, A, B, C, D);
               end if;
               if D /= 0 and then D /= A and then D /= B and then D /= C then
                  Add (D, A, B, C, D);
               end if;
            end;
         end loop;
      end loop;
   end Cell_Pass;

   procedure Projection_Pass
     (Map   : Int32_Matrix;
      Count : Int32;
      T     : KT.Ks_Transform_2D_Linear;
      Acc   : in out Accumulator_Array)
   with
     Pre => Count >= 1 and then Acc'First = 0
            and then Int64 (Acc'Last) = Int64 (Count) - 1
            and then Bounded_Transform (T);
   --  The extents of the pixel centres of every feature along its
   --  principal axes and along the axes of the selected space, measured
   --  from its centre of mass.

   procedure Projection_Pass
     (Map   : Int32_Matrix;
      Count : Int32;
      T     : KT.Ks_Transform_2D_Linear;
      Acc   : in out Accumulator_Array)
   is
      function Project (P, Q, DX, DY : Long_Float) return Long_Float
      with
        Pre  => abs DX <= Delta_Limit and then abs DY <= Delta_Limit,
        Post => abs Project'Result <= Extent_Limit;
      --  P DX + Q DY, P and Q read through a clamp at Proj_Limit.

      function Project (P, Q, DX, DY : Long_Float) return Long_Float is
        (N.Mul_Within (N.Clamp (P, Proj_Limit), DX, Proj_Limit, Delta_Limit)
         + N.Mul_Within (N.Clamp (Q, Proj_Limit), DY, Proj_Limit,
                         Delta_Limit));

      procedure Extend (Low, High : in out Long_Float; Value : Long_Float)
      with Pre => abs Value <= Extent_Limit;

      procedure Extend (Low, High : in out Long_Float; Value : Long_Float)
      is
      begin
         Low := Long_Float'Min (N.Clamp (Low, Extent_Limit), Value);
         High := Long_Float'Max (N.Clamp (High, Extent_Limit), Value);
      end Extend;
   begin
      for Y in Map'Range (1) loop
         for X in Map'Range (2) loop
            declare
               Id : constant Int32 := Map (Y, X);
            begin
               if Id >= 1 and then Id <= Count then
                  declare
                     K  : constant Natural := Natural (Id - 1);
                     DX : constant Long_Float :=
                       Long_Float (X) - N.Clamp (Acc (K).Cx, Center_Limit);
                     DY : constant Long_Float :=
                       Long_Float (Y) - N.Clamp (Acc (K).Cy, Center_Limit);
                  begin
                     Extend (Acc (K).U_Min, Acc (K).U_Max,
                             Project (Acc (K).Pu, Acc (K).Qu, DX, DY));
                     Extend (Acc (K).V_Min, Acc (K).V_Max,
                             Project (Acc (K).Pv, Acc (K).Qv, DX, DY));
                     Extend (Acc (K).S_Min, Acc (K).S_Max,
                             Project (T.A, T.B, DX, DY));
                     Extend (Acc (K).R_Min, Acc (K).R_Max,
                             Project (T.C, T.D, DX, DY));
                  end;
               end if;
            end;
         end loop;
      end loop;
   end Projection_Pass;

   ---------------------------------------------------------------------
   --  Measures of one feature
   ---------------------------------------------------------------------

   function Quadratic
     (P, Q, Cxx, Cxy, Cyy : Long_Float) return Long_Float
   with
     Pre  => abs P <= Max_Scale and then abs Q <= Max_Scale
             and then Cxx in 0.0 .. Moment_Limit
             and then abs Cxy <= Moment_Limit
             and then Cyy in 0.0 .. Moment_Limit,
     Post => abs Quadratic'Result <= Shape_Limit;
   --  P**2 Cxx + 2 P Q Cxy + Q**2 Cyy: the second moment of the mapped
   --  pixels along the row (P, Q) of the transform.

   function Quadratic
     (P, Q, Cxx, Cxy, Cyy : Long_Float) return Long_Float
   is
      PP : constant Long_Float := N.Square_Within (P, Max_Scale);
      PQ : constant Long_Float := N.Mul_Within (P, Q, Max_Scale, Max_Scale);
      QQ : constant Long_Float := N.Square_Within (Q, Max_Scale);
   begin
      return N.Mul_Within (PP, Cxx, Square_Limit, Moment_Limit)
        + 2.0 * N.Mul_Within (PQ, Cxy, Square_Limit, Moment_Limit)
        + N.Mul_Within (QQ, Cyy, Square_Limit, Moment_Limit);
   end Quadratic;

   function Bilinear
     (P, Q, R, S, Cxx, Cxy, Cyy : Long_Float) return Long_Float
   with
     Pre  => abs P <= Max_Scale and then abs Q <= Max_Scale
             and then abs R <= Max_Scale and then abs S <= Max_Scale
             and then Cxx in 0.0 .. Moment_Limit
             and then abs Cxy <= Moment_Limit
             and then Cyy in 0.0 .. Moment_Limit,
     Post => abs Bilinear'Result <= Shape_Limit;
   --  P R Cxx + (P S + Q R) Cxy + Q S Cyy: the mixed second moment of the
   --  mapped pixels along the rows (P, Q) and (R, S).

   function Bilinear
     (P, Q, R, S, Cxx, Cxy, Cyy : Long_Float) return Long_Float
   is
      PR : constant Long_Float := N.Mul_Within (P, R, Max_Scale, Max_Scale);
      QS : constant Long_Float := N.Mul_Within (Q, S, Max_Scale, Max_Scale);
      PS : constant Long_Float := N.Mul_Within (P, S, Max_Scale, Max_Scale);
      QR : constant Long_Float := N.Mul_Within (Q, R, Max_Scale, Max_Scale);
   begin
      return N.Mul_Within (PR, Cxx, Square_Limit, Moment_Limit)
        + N.Mul_Within (PS + QR, Cxy, Cross_Limit, Moment_Limit)
        + N.Mul_Within (QS, Cyy, Square_Limit, Moment_Limit);
   end Bilinear;

   function Map_Coordinate
     (P, Q, Translation, X, Y : Long_Float) return Long_Float
   with
     Pre  => abs P <= Max_Scale and then abs Q <= Max_Scale
             and then abs Translation <= Max_Translation
             and then abs X <= Center_Limit and then abs Y <= Center_Limit,
     Post => abs Map_Coordinate'Result <= Max_Translation + 2.0 ** 98;
   --  P X + Q Y + Translation: one coordinate of a mapped point.

   function Map_Coordinate
     (P, Q, Translation, X, Y : Long_Float) return Long_Float
   is
     (N.Mul_Within (P, X, Max_Scale, Center_Limit)
      + N.Mul_Within (Q, Y, Max_Scale, Center_Limit) + Translation);

   function Length_Of (DX, DY, Count : Long_Float) return Long_Float
   with
     Pre  => abs DX <= Max_Scale and then abs DY <= Max_Scale
             and then Count in 0.0 .. Long_Float (Count_Limit),
     Post => Length_Of'Result in 0.0 .. 2.0 ** 106;
   --  Count segments of the mapped vector (DX, DY).

   function Length_Of (DX, DY, Count : Long_Float) return Long_Float is
     (Non_Negative
        (N.Mul_Within
           (N.Hypot (DX, DY), Count, 2.0 * Max_Scale,
            Long_Float (Count_Limit)),
         2.0 ** 106));

   procedure Central_Moments
     (E                  : Accumulator;
      Area               : Int64;
      FX, FY             : Int32;
      Nf, Cx, Cy         : out Long_Float;
      Cxx, Cxy, Cyy      : out Long_Float)
   with
     Post => Nf in 1.0 .. Pixel_Limit
             and then abs Cx <= Center_Limit and then abs Cy <= Center_Limit
             and then Cxx in 0.0 .. Moment_Limit
             and then Cyy in 0.0 .. Moment_Limit
             and then abs Cxy <= Moment_Limit;
   --  The number of pixels, the centroid in pixel space and the second
   --  moments of the pixel squares about it (each square adds 1/12).

   procedure Central_Moments
     (E                  : Accumulator;
      Area               : Int64;
      FX, FY             : Int32;
      Nf, Cx, Cy         : out Long_Float;
      Cxx, Cxy, Cyy      : out Long_Float)
   is
      Sx  : constant Long_Float := N.Clamp (E.Sx, Sum_1_Limit);
      Sy  : constant Long_Float := N.Clamp (E.Sy, Sum_1_Limit);
      Sxx : constant Long_Float := N.Clamp (E.Sxx, Sum_2_Limit);
      Sxy : constant Long_Float := N.Clamp (E.Sxy, Sum_2_Limit);
      Syy : constant Long_Float := N.Clamp (E.Syy, Sum_2_Limit);
      Mx  : Long_Float;
      My  : Long_Float;
      Square : Long_Float;
   begin
      Nf := Long_Float (Int64'Max (1, Int64'Min (Area, 2**31)));
      Mx := Quotient (Sx, Nf, Offset_Limit);
      My := Quotient (Sy, Nf, Offset_Limit);
      Cx := N.Clamp (Long_Float (FX) + Mx, Center_Limit);
      Cy := N.Clamp (Long_Float (FY) + My, Center_Limit);
      Square := Non_Negative (Nf / 12.0, 2.0 ** 28);
      Cxx := Non_Negative
               (Sxx - N.Mul_Within (Sx, Mx, Sum_1_Limit, Offset_Limit),
                Moment_Limit / 2.0) + Square;
      Cyy := Non_Negative
               (Syy - N.Mul_Within (Sy, My, Sum_1_Limit, Offset_Limit),
                Moment_Limit / 2.0) + Square;
      Cxy := N.Clamp
               (Sxy - N.Mul_Within (Sx, My, Sum_1_Limit, Offset_Limit),
                Moment_Limit);
   end Central_Moments;

   W_Moment_Limit : constant := 2.0 ** 105;
   --  A bound of a weighted second moment about the centroid before the
   --  division by Full (a sum below 2**103 less a product below 2**103).

   function Per_Level (X, F : Long_Float) return Long_Float
   with
     Pre  => abs X <= W_Moment_Limit and then F >= 1.0 and then F <= 256.0,
     Post => abs Per_Level'Result <= W_Moment_Limit;
   --  X / F: a sum in levels turned into one in pixels.

   function Per_Level (X, F : Long_Float) return Long_Float is (X / F);

   function Central_Term (S2, S1, M, F : Long_Float) return Long_Float
   with
     Pre  => abs S2 <= W_Sum_2_Limit and then abs S1 <= W_Sum_1_Limit
             and then abs M <= Offset_Limit
             and then F >= 1.0 and then F <= 256.0,
     Post => abs Central_Term'Result <= W_Moment_Limit;
   --  (S2 - S1 M) / F: a weighted second moment about the centroid (S2
   --  the sum of the products of the offsets times the levels, S1 the
   --  sum of one offset times the levels, M the mean of the other
   --  offset), in pixels.

   function Central_Term (S2, S1, M, F : Long_Float) return Long_Float is
     (Per_Level (S2 - N.Mul_Within (S1, M, W_Sum_1_Limit, Offset_Limit), F));

   function Centroid_Of (First : Int32; Mean : Long_Float) return Long_Float
   with
     Pre  => abs Mean <= Offset_Limit,
     Post => abs Centroid_Of'Result <= Center_Limit;
   --  First + Mean (a pixel coordinate plus a mean offset from it), read
   --  through a clamp at Center_Limit that never acts.

   function Centroid_Of (First : Int32; Mean : Long_Float) return Long_Float
   is (N.Clamp (Long_Float (First) + Mean, Center_Limit));

   procedure Weighted_Central_Moments
     (E                  : Accumulator;
      Full               : Int32;
      FX, FY             : Int32;
      Nf, Cx, Cy         : out Long_Float;
      Cxx, Cxy, Cyy      : out Long_Float)
   with
     Pre  => Full in 1 .. Max_Softness + 1,
     Post => Nf in 0.0 .. Pixel_Limit
             and then abs Cx <= Center_Limit and then abs Cy <= Center_Limit
             and then Cxx in 0.0 .. Moment_Limit
             and then Cyy in 0.0 .. Moment_Limit
             and then abs Cxy <= Moment_Limit;
   --  Central_Moments with each pixel weighted by its level / Full: the
   --  sum of the weights (the area in pixels), the weighted centroid and
   --  the weighted second moments of the pixel squares about it (each
   --  square adds its weight / 12). The level sums are divided by Full
   --  once, at the end.

   procedure Weighted_Central_Moments
     (E                  : Accumulator;
      Full               : Int32;
      FX, FY             : Int32;
      Nf, Cx, Cy         : out Long_Float;
      Cxx, Cxy, Cyy      : out Long_Float)
   is
      W   : constant Long_Float :=
        Long_Float (Int64'Max (1, Int64'Min (E.W, Weight_Limit)));
      F   : constant Long_Float := Long_Float (Full);
      Sx  : constant Long_Float := N.Clamp (E.Wx, W_Sum_1_Limit);
      Sy  : constant Long_Float := N.Clamp (E.Wy, W_Sum_1_Limit);
      Sxx : constant Long_Float := N.Clamp (E.Wxx, W_Sum_2_Limit);
      Sxy : constant Long_Float := N.Clamp (E.Wxy, W_Sum_2_Limit);
      Syy : constant Long_Float := N.Clamp (E.Wyy, W_Sum_2_Limit);
      Mx  : Long_Float;
      My  : Long_Float;
      Square : Long_Float;
   begin
      Mx := Quotient (Sx, W, Offset_Limit);
      My := Quotient (Sy, W, Offset_Limit);
      Cx := Centroid_Of (FX, Mx);
      Cy := Centroid_Of (FY, My);
      Nf := Non_Negative (W / F, Pixel_Limit);
      Square := Non_Negative (Nf / 12.0, 2.0 ** 28);
      Cxx := Non_Negative (Central_Term (Sxx, Sx, Mx, F), Moment_Limit / 2.0)
               + Square;
      Cyy := Non_Negative (Central_Term (Syy, Sy, My, F), Moment_Limit / 2.0)
               + Square;
      Cxy := N.Clamp (Central_Term (Sxy, Sx, My, F), Moment_Limit);
   end Weighted_Central_Moments;

   function Abs_Determinant (T : KT.Ks_Transform_2D_Linear) return Long_Float
   with
     Pre  => Bounded_Transform (T),
     Post => Abs_Determinant'Result in 0.0 .. Cross_Limit;
   --  abs (A D - B C).

   function Abs_Determinant (T : KT.Ks_Transform_2D_Linear) return Long_Float
   is (abs (N.Mul_Within (T.A, T.D, Max_Scale, Max_Scale)
            - N.Mul_Within (T.B, T.C, Max_Scale, Max_Scale)));

   procedure Principal
     (Pxx, Pyy, Pxy         : Long_Float;
      Big_Axis, Small_Axis : out Long_Float;
      Angle                : out Long_Float)
   with
     Pre  => abs Pxx <= Shape_Limit and then abs Pyy <= Shape_Limit
             and then abs Pxy <= Shape_Limit,
     Post => Big_Axis in 0.0 .. 2.0 ** 231
             and then Small_Axis in 0.0 .. 2.0 ** 231
             and then Angle > -N.Half_Pi and then Angle <= N.Half_Pi;
   --  The second moments along the principal axes of the moment matrix
   --  [Pxx Pxy; Pxy Pyy] (largest and smallest) and the direction of the
   --  axis along which the pixels spread most (the axis of least
   --  inertia), in (-Pi/2, Pi/2].

   procedure Principal
     (Pxx, Pyy, Pxy         : Long_Float;
      Big_Axis, Small_Axis : out Long_Float;
      Angle                : out Long_Float)
   is
      Half_Sum  : constant Long_Float := Pxx / 2.0 + Pyy / 2.0;
      Half_Diff : constant Long_Float := Pxx / 2.0 - Pyy / 2.0;
      Radius    : constant Long_Float := N.Hypot (Half_Diff, Pxy);
   begin
      Big_Axis := Non_Negative (Half_Sum + Radius, 2.0 ** 231);
      Small_Axis := Non_Negative (Half_Sum - Radius, 2.0 ** 231);
      if Half_Diff = 0.0 and then Pxy = 0.0 then
         Angle := 0.0;
      else
         Angle := N.Direction (Pxy, Half_Diff) / 2.0;
      end if;
   end Principal;

   function Perimeter_Of
     (E : Accumulator;
      T : KT.Ks_Transform_2D_Linear) return Long_Float
   with
     Pre  => Bounded_Transform (T),
     Post => Perimeter_Of'Result in 0.0 .. 2.0 ** 108;
   --  The boundary segments of E, each mapped by the linear part of T.

   function Perimeter_Of
     (E : Accumulator;
      T : KT.Ks_Transform_2D_Linear) return Long_Float
   is
      Straight_X : constant Long_Float :=
        Length_Of (T.A, T.C, Count_Value (E.H));
      Straight_Y : constant Long_Float :=
        Length_Of (T.B, T.D, Count_Value (E.V));
      Diagonal   : constant Long_Float :=
        Length_Of (T.A / 2.0 + T.B / 2.0, T.C / 2.0 + T.D / 2.0,
                   Count_Value (E.D));
      Anti       : constant Long_Float :=
        Length_Of (T.A / 2.0 - T.B / 2.0, T.C / 2.0 - T.D / 2.0,
                   Count_Value (E.A));
   begin
      return Straight_X + Straight_Y + Diagonal + Anti;
   end Perimeter_Of;

   function Rotated (P, Q, Cos_A, Sin_A : Long_Float) return Long_Float
   with
     Pre  => abs P <= Max_Scale and then abs Q <= Max_Scale
             and then abs Cos_A <= 1.0 and then abs Sin_A <= 1.0,
     Post => abs Rotated'Result <= 2.0 * Max_Scale;
   --  P Cos_A + Q Sin_A.

   function Rotated (P, Q, Cos_A, Sin_A : Long_Float) return Long_Float is
     (N.Times_Unit (P, Cos_A) + N.Times_Unit (Q, Sin_A));

   procedure Moments
     (E        : in out Accumulator;
      Area     : Int64;
      Weighted : Boolean;
      Full     : Int32;
      FX, FY   : Int32;
      T        : KT.Ks_Transform_2D_Linear;
      Item     : in out Ks_Blob_Result)
   with Pre => Bounded_Transform (T) and then Full in 1 .. Max_Softness + 1;
   --  Centre of mass, area, inertia, angle, elongation, perimeter and
   --  acircularity in the selected space (from the weighted sums when
   --  Weighted, see Weighted_Central_Moments); the centroid, angle and
   --  projections the boxes need go to E.

   procedure Moments
     (E        : in out Accumulator;
      Area     : Int64;
      Weighted : Boolean;
      Full     : Int32;
      FX, FY   : Int32;
      T        : KT.Ks_Transform_2D_Linear;
      Item     : in out Ks_Blob_Result)
   is
      Nf, Cx, Cy, Cxx, Cxy, Cyy : Long_Float;
      Big_Axis, Small_Axis      : Long_Float;
      Angle                     : Long_Float;
   begin
      if Weighted then
         Weighted_Central_Moments (E, Full, FX, FY, Nf, Cx, Cy, Cxx, Cxy,
                                   Cyy);
      else
         Central_Moments (E, Area, FX, FY, Nf, Cx, Cy, Cxx, Cxy, Cyy);
      end if;
      declare
         Pxx     : constant Long_Float := Quadratic (T.A, T.B, Cxx, Cxy, Cyy);
         Pyy     : constant Long_Float := Quadratic (T.C, T.D, Cxx, Cxy, Cyy);
         Pxy     : constant Long_Float :=
           Bilinear (T.A, T.B, T.C, T.D, Cxx, Cxy, Cyy);
         Abs_Det : constant Long_Float := Abs_Determinant (T);
      begin
         Principal (Pxx, Pyy, Pxy, Big_Axis, Small_Axis, Angle);
         Item.Inertia_X :=
           N.Mul_Within (Abs_Det, Non_Negative (Pyy, Shape_Limit),
                         Cross_Limit, Shape_Limit);
         Item.Inertia_Y :=
           N.Mul_Within (Abs_Det, Non_Negative (Pxx, Shape_Limit),
                         Cross_Limit, Shape_Limit);
         Item.Inertia_Max :=
           N.Mul_Within (Abs_Det, Big_Axis, Cross_Limit, 2.0 ** 231);
         Item.Inertia_Min :=
           N.Mul_Within (Abs_Det, Small_Axis, Cross_Limit, 2.0 ** 231);
         Item.Area := N.Mul_Within (Abs_Det, Nf, Cross_Limit, Pixel_Limit);
      end;
      Item.Elongation :=
        (if Item.Inertia_Min > 0.0
         then Quotient (Item.Inertia_Max, Item.Inertia_Min, Ratio_Limit)
         else 0.0);
      Item.Perimeter := Perimeter_Of (E, T);
      declare
         Den : constant Long_Float := 4.0 * N.Pi * Item.Area;
      begin
         Item.Acircularity :=
           (if Den > 0.0
            then Quotient (N.Square_Within (Item.Perimeter, 2.0 ** 108), Den,
                           Ratio_Limit)
            else 0.0);
      end;
      Item.Center_Of_Mass_X :=
        Map_Coordinate (T.A, T.B, T.Translation_X, Cx, Cy);
      Item.Center_Of_Mass_Y :=
        Map_Coordinate (T.C, T.D, T.Translation_Y, Cx, Cy);
      Item.Angle := Angle;
      E.Cx := Cx;
      E.Cy := Cy;
      E.Angle := Angle;
      declare
         Cos_A : constant Long_Float := EF.Cos (Angle);
         Sin_A : constant Long_Float := EF.Sin (Angle);
      begin
         E.Cos_A := Cos_A;
         E.Sin_A := Sin_A;
         E.Pu := Rotated (T.A, T.C, Cos_A, Sin_A);
         E.Qu := Rotated (T.B, T.D, Cos_A, Sin_A);
         E.Pv := Rotated (T.C, -T.A, Cos_A, Sin_A);
         E.Qv := Rotated (T.D, -T.B, Cos_A, Sin_A);
      end;
   end Moments;

   procedure Boxes
     (E      : Accumulator;
      T      : KT.Ks_Transform_2D_Linear;
      Item   : in out Ks_Blob_Result;
      Status : out Ks_Status)
   with
     Pre  => Bounded_Transform (T),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  The pixel-aligned box (mapped by the shape kernel), the box along
   --  the principal axes and the box along the selected space's axes,
   --  each around the mapped pixel squares, and their measures.

   procedure Boxes
     (E      : Accumulator;
      T      : KT.Ks_Transform_2D_Linear;
      Item   : in out Ks_Blob_Result;
      Status : out Ks_Status)
   is
      X_Min : constant Int32 := Int32'Max (0, E.X_Min);
      X_Max : constant Int32 := Int32'Max (X_Min, E.X_Max);
      Y_Min : constant Int32 := Int32'Max (0, E.Y_Min);
      Y_Max : constant Int32 := Int32'Max (Y_Min, E.Y_Max);
      Pixel_Box : constant KS.Ks_Rectangle_Affine :=
        (Center_X      => (Long_Float (X_Min) + Long_Float (X_Max)) / 2.0,
         Center_Y      => (Long_Float (Y_Min) + Long_Float (Y_Max)) / 2.0,
         Side_X_Length => Long_Float (X_Max) - Long_Float (X_Min) + 1.0,
         Side_Y_Length => Long_Float (Y_Max) - Long_Float (Y_Min) + 1.0,
         Rotation      => 0.0,
         Skew          => 0.0);
      Mapped : KS.Ks_Rectangle_Affine;
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
      Cx    : constant Long_Float := N.Clamp (E.Cx, Center_Limit);
      Cy    : constant Long_Float := N.Clamp (E.Cy, Center_Limit);
      Cos_A : constant Long_Float := N.Clamp (E.Cos_A, 1.0);
      Sin_A : constant Long_Float := N.Clamp (E.Sin_A, 1.0);
      Mass_X : constant Long_Float :=
        Map_Coordinate (T.A, T.B, T.Translation_X, Cx, Cy);
      Mass_Y : constant Long_Float :=
        Map_Coordinate (T.C, T.D, T.Translation_Y, Cx, Cy);

      procedure Extent
        (Low, High : Long_Float;
         P, Q      : Long_Float;
         Lo, Hi    : out Long_Float)
      with
        Post => Lo >= -2.0 ** 102 and then Lo <= 2.0 ** 102
                and then Hi >= Lo and then Hi <= 2.0 ** 102;
      --  The extent [Low, High] of the pixel centres along an axis,
      --  widened by half the extent (abs P + abs Q) / 2 of a mapped
      --  pixel square along it.

      procedure Extent
        (Low, High : Long_Float;
         P, Q      : Long_Float;
         Lo, Hi    : out Long_Float)
      is
         Half : constant Long_Float :=
           (abs N.Clamp (P, Proj_Limit) + abs N.Clamp (Q, Proj_Limit)) / 2.0;
      begin
         Lo := N.Clamp (Low, Extent_Limit) - Half;
         Hi := Long_Float'Max (Lo, N.Clamp (High, Extent_Limit) + Half);
      end Extent;

      U_Lo, U_Hi, V_Lo, V_Hi, S_Lo, S_Hi, R_Lo, R_Hi : Long_Float;
   begin
      KS.Map (Pixel_Box, T, Mapped, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Get_Bounding_Box (Mapped, Min_X, Min_Y, Max_X, Max_Y, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Item.Pixel_Aligned_Box := Mapped;
      Item.Pixel_Aligned_Min_X := Min_X;
      Item.Pixel_Aligned_Max_X := Max_X;
      Item.Pixel_Aligned_Min_Y := Min_Y;
      Item.Pixel_Aligned_Max_Y := Max_Y;
      Item.Pixel_Aligned_Center_X := Min_X / 2.0 + Max_X / 2.0;
      Item.Pixel_Aligned_Center_Y := Min_Y / 2.0 + Max_Y / 2.0;
      Item.Pixel_Aligned_Width := Max_X - Min_X;
      Item.Pixel_Aligned_Height := Max_Y - Min_Y;
      Item.Pixel_Aligned_Aspect :=
        (if Max_X - Min_X > 0.0
         then Quotient (Max_Y - Min_Y, Max_X - Min_X, Ratio_Limit)
         else 0.0);

      Extent (E.U_Min, E.U_Max, E.Pu, E.Qu, U_Lo, U_Hi);
      Extent (E.V_Min, E.V_Max, E.Pv, E.Qv, V_Lo, V_Hi);
      Item.Principal_Axis_Min_X := U_Lo;
      Item.Principal_Axis_Max_X := U_Hi;
      Item.Principal_Axis_Min_Y := V_Lo;
      Item.Principal_Axis_Max_Y := V_Hi;
      Item.Principal_Axis_Width := U_Hi - U_Lo;
      Item.Principal_Axis_Height := V_Hi - V_Lo;
      Item.Principal_Axis_Aspect :=
        (if U_Hi - U_Lo > 0.0
         then Quotient (V_Hi - V_Lo, U_Hi - U_Lo, Ratio_Limit)
         else 0.0);
      declare
         U_Mid : constant Long_Float := U_Lo / 2.0 + U_Hi / 2.0;
         V_Mid : constant Long_Float := V_Lo / 2.0 + V_Hi / 2.0;
      begin
         Item.Principal_Axis_Box :=
           (Center_X      => Mass_X + N.Times_Unit (U_Mid, Cos_A)
                             - N.Times_Unit (V_Mid, Sin_A),
            Center_Y      => Mass_Y + N.Times_Unit (U_Mid, Sin_A)
                             + N.Times_Unit (V_Mid, Cos_A),
            Side_X_Length => U_Hi - U_Lo,
            Side_Y_Length => V_Hi - V_Lo,
            Rotation      => N.Clamp (E.Angle, 2.0),
            Skew          => 0.0);
      end;

      Extent (E.S_Min, E.S_Max, T.A, T.B, S_Lo, S_Hi);
      Extent (E.R_Min, E.R_Max, T.C, T.D, R_Lo, R_Hi);
      Item.Selected_Space_Box :=
        (Center_X      => Mass_X + (S_Lo / 2.0 + S_Hi / 2.0),
         Center_Y      => Mass_Y + (R_Lo / 2.0 + R_Hi / 2.0),
         Side_X_Length => S_Hi - S_Lo,
         Side_Y_Length => R_Hi - R_Lo,
         Rotation      => 0.0,
         Skew          => 0.0);
      Set_Success (Status);
   end Boxes;

   ---------------------------------------------------------------------
   --  All measures
   ---------------------------------------------------------------------

   procedure Compute_Items
     (Region  : access constant KR.Ks_Pixel_Region_Data;
      Map     : Int32_Matrix;
      Count   : Int32;
      Kind    : Int32_Array;
      Label   : Int32_Array;
      Parent  : Int32_Array;
      First_X : Int32_Array;
      First_Y : Int32_Array;
      Area    : Int64_Array;
      Levels  : access constant U8_Matrix;
      Full    : Int32;
      T       : KT.Ks_Transform_2D_Linear;
      Items   : in out Result_Array;
      Cx, Cy  : in out Real_Array;
      Status  : out Ks_Status)
   is
      Acc  : Accumulator_Array_Access;
      Soft : constant Boolean := Levels /= null;
   begin
      Allocate_Accumulators (Natural (Count) - 1, Acc);
      if Acc = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Execute: out of memory for the measures");
         return;
      end if;
      Sum_Pass (Region, Map, Count, First_X, First_Y, Acc.all);
      if Levels /= null then
         Weight_Pass (Map, Count, Kind, First_X, First_Y, Levels.all, Full,
                      Acc.all);
      end if;
      Cell_Pass (Map, Count, Kind, Acc.all);
      for K in Items'Range loop
         pragma Loop_Invariant
           (Acc /= null and then Acc'First = 0 and then Acc'Last = Items'Last);
         Moments (Acc (K), Area (K), Soft and then Kind (K) = Label_Blob,
                  Full, First_X (K), First_Y (K), T, Items (K));
      end loop;
      Projection_Pass (Map, Count, T, Acc.all);
      for K in Items'Range loop
         pragma Loop_Invariant
           (Acc /= null and then Acc'First = 0 and then Acc'Last = Items'Last);
         Boxes (Acc (K), T, Items (K), Status);
         if not Succeeded (Status) then
            Free (Acc);
            return;
         end if;
         Cx (K) := N.Clamp (Acc (K).Cx, Center_Limit);
         Cy (K) := N.Clamp (Acc (K).Cy, Center_Limit);
         Items (K).ID := Int32 (K);
         Items (K).Label := Label (K);
         Items (K).Parent_ID := Parent (K);
         Items (K).Pixel_Count :=
           Int32 (Int64'Max (0, Int64'Min (Area (K), Int64 (Int32'Last))));
         Items (K).Not_Clipped :=
           (if Acc (K).Clipped then False_Value else True_Value);
         Items (K).Num_Children := 0;
         Items (K).Num_Unfiltered_Children := 0;
         Items (K).Filtered_Out := False_Value;
      end loop;
      Free (Acc);
      Set_Success (Status);
   end Compute_Items;

end AMV.Kernels.Blob.Measures;
