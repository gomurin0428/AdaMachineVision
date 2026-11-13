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

package body AMV.Kernels.Calib_Fix.Checkerboard with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);

   package KM renames AMV.Kernels.Image_Math;
   package N renames AMV.Kernels.Numerics;

   use type KM.Ks_Real_Image;

   ---------------------------------------------------------------------
   --  Types
   ---------------------------------------------------------------------

   type Index_Matrix is array (Natural range <>, Natural range <>) of Int32
     with Default_Component_Value => 0;
   --  Three uses, each allocated by Allocate_Map: the corner map (at the
   --  pixel nearest to candidate K, K + 1; 0 elsewhere), the grid table
   --  (at row J + Span and column I + Span, K + 1 while candidate K holds
   --  the grid indices (I, J); 0 elsewhere) and the queue of a growth (one
   --  row: the candidates in the order they joined the grid). Every value
   --  read from them is range-tested before use.

   type Index_Map is access Index_Matrix;

   subtype Grey is Long_Float range 0.0 .. 255.0;

   Coordinate_Limit : constant := 2.0 ** 31;
   --  Pixel positions lie in [0, 2**31], so their differences within
   --  2**31.

   subtype Step_Coordinate is Long_Float
     range -Coordinate_Limit .. Coordinate_Limit;

   subtype Span_Index is Integer range -Max_Span .. Max_Span;

   subtype Attempt_Number is Natural range 0 .. Max_Seeds;

   type Candidate is record
      X, Y     : Pixel_Position := 0.0;
      Mid      : Grey := 0.0;
      Contrast : Grey := 0.0;
      Owner    : Attempt_Number := 0;
      Tried    : Boolean := False;
      I, J     : Span_Index := 0;
      Ux, Uy   : Step_Coordinate := 0.0;
      Vx, Vy   : Step_Coordinate := 0.0;
   end record;
   --  A corner that passed the X-junction test: its position, the mid
   --  level and contrast of its ring; the seed attempt whose grid holds it
   --  (0: free) and whether it was tried as a seed; its grid indices and
   --  the steps along the grid's I and J axes it was found with (valid
   --  while Owner is not 0).

   type Candidate_Array is array (Natural range <>) of Candidate;

   type Candidate_Access is access Candidate_Array;

   procedure Free is new Ada.Unchecked_Deallocation
     (Index_Matrix, Index_Map);
   procedure Free is new Ada.Unchecked_Deallocation
     (Corner_Array, Corner_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Candidate_Array, Candidate_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (KM.Real_Matrix, KM.Real_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KM.Ks_Real_Image_Data, KM.Ks_Real_Image);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Map
     (Width, Height : Positive;
      Map           : out Index_Map)
   with
     Global => null,
     Post   => (if Map /= null
                then Map'First (1) = 0 and then Map'Last (1) = Height - 1
                     and then Map'First (2) = 0
                     and then Map'Last (2) = Width - 1);
   --  A new map of Height rows of Width zeros, or null when the memory
   --  cannot be allocated. Trusted: the allocator raises Storage_Error,
   --  which SPARK cannot express.

   procedure Allocate_Map
     (Width, Height : Positive;
      Map           : out Index_Map)
     with SPARK_Mode => Off
   is
   begin
      Map := new Index_Matrix (0 .. Height - 1, 0 .. Width - 1);
   exception
      when Storage_Error =>
         Map := null;
   end Allocate_Map;

   procedure Allocate_Corners
     (Capacity : Positive;
      Corners  : out Corner_Array_Access)
   with
     Global => null,
     Pre    => Capacity <= Max_Corners,
     Post   => (if Corners /= null
                then Corners'First = 0
                     and then Corners'Last = Capacity - 1);
   --  A new array of Capacity corners (the record's defaults), or null.
   --  Trusted as above.

   procedure Allocate_Corners
     (Capacity : Positive;
      Corners  : out Corner_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Corners := new Corner_Array (0 .. Capacity - 1);
   exception
      when Storage_Error =>
         Corners := null;
   end Allocate_Corners;

   procedure Allocate_Candidates
     (Capacity : Positive;
      Cand     : out Candidate_Access)
   with
     Global => null,
     Pre    => Capacity <= Max_Corners,
     Post   => (if Cand /= null
                then Cand'First = 0 and then Cand'Last = Capacity - 1);
   --  A new array of Capacity candidates (the record's defaults), or null.
   --  Trusted as above.

   procedure Allocate_Candidates
     (Capacity : Positive;
      Cand     : out Candidate_Access)
     with SPARK_Mode => Off
   is
   begin
      Cand := new Candidate_Array (0 .. Capacity - 1);
   exception
      when Storage_Error =>
         Cand := null;
   end Allocate_Candidates;

   ---------------------------------------------------------------------
   --  Images
   ---------------------------------------------------------------------

   Max_Side : constant := 2**24;
   --  The longest side of an image the detector takes (its index
   --  arithmetic stays far from Integer'Last).

   function Usable
     (Image         : access constant KM.Ks_Real_Image_Data;
      Width, Height : Positive) return Boolean
   is (KM.Valid_Image (Image)
       and then Image.Pixels'Last (2) = Width - 1
       and then Image.Pixels'Last (1) = Height - 1);
   --  A real image of Height rows of Width pixels.

   function Smoothed
     (S    : access constant KM.Ks_Real_Image_Data;
      X, Y : Natural) return Grey
   is (Long_Float'Max (0.0, Long_Float'Min (255.0, S.Pixels (Y, X))))
   with Pre => KM.Valid_Image (S)
               and then X <= S.Pixels'Last (2)
               and then Y <= S.Pixels'Last (1);
   --  A pixel of the smoothed image, read through a limit to [0, 255]
   --  (a weighted mean of grey levels lies there; the limit acts only by
   --  rounding at its ends).

   Response_Limit : constant := 2.0 ** 19;

   function Response
     (S    : access constant KM.Ks_Real_Image_Data;
      X, Y : Natural) return Long_Float
   with
     Pre  => KM.Valid_Image (S)
             and then X >= 1 and then Y >= 1
             and then X < S.Pixels'Last (2)
             and then Y < S.Pixels'Last (1),
     Post => abs Response'Result <= Response_Limit;
   --  Ixy**2 - Ixx * Iyy from second differences (at most 127.5**2 +
   --  510**2 in magnitude).

   function Response
     (S    : access constant KM.Ks_Real_Image_Data;
      X, Y : Natural) return Long_Float
   is
      C   : constant Grey := Smoothed (S, X, Y);
      Ixx : constant Long_Float :=
        (Smoothed (S, X - 1, Y) - 2.0 * C) + Smoothed (S, X + 1, Y);
      Iyy : constant Long_Float :=
        (Smoothed (S, X, Y - 1) - 2.0 * C) + Smoothed (S, X, Y + 1);
      Ixy : constant Long_Float :=
        0.25 * ((Smoothed (S, X + 1, Y + 1) - Smoothed (S, X + 1, Y - 1))
                - (Smoothed (S, X - 1, Y + 1)
                   - Smoothed (S, X - 1, Y - 1)));
   begin
      return N.Square_Within (Ixy, 127.5)
             - N.Mul_Within (Ixx, Iyy, 510.0, 510.0);
   end Response;

   function Read
     (R    : access constant KM.Ks_Real_Image_Data;
      X, Y : Natural) return Long_Float
   is (N.Clamp (R.Pixels (Y, X), Response_Limit))
   with Pre  => KM.Valid_Image (R)
                and then X <= R.Pixels'Last (2)
                and then Y <= R.Pixels'Last (1),
        Post => abs Read'Result <= Response_Limit;
   --  A stored response (the limit never acts: every stored value is a
   --  Response or 0).

   procedure Fill_Response
     (S      : access constant KM.Ks_Real_Image_Data;
      R      : KM.Ks_Real_Image;
      Width  : Positive;
      Height : Positive)
   with
     Pre  => Usable (S, Width, Height) and then Usable (R, Width, Height)
             and then Width >= 3 and then Height >= 3,
     Post => Usable (R, Width, Height);
   --  The response at every pixel that is not on the border.

   procedure Fill_Response
     (S      : access constant KM.Ks_Real_Image_Data;
      R      : KM.Ks_Real_Image;
      Width  : Positive;
      Height : Positive) is
   begin
      for Y in 1 .. Height - 2 loop
         pragma Loop_Invariant (Usable (R, Width, Height));
         for X in 1 .. Width - 2 loop
            pragma Loop_Invariant (Usable (R, Width, Height));
            R.Pixels (Y, X) := Response (S, X, Y);
         end loop;
      end loop;
   end Fill_Response;

   function Strongest
     (R      : access constant KM.Ks_Real_Image_Data;
      Width  : Positive;
      Height : Positive) return Long_Float
   with
     Pre  => Usable (R, Width, Height)
             and then Width > 2 * Margin and then Height > 2 * Margin,
     Post => abs Strongest'Result <= Response_Limit;
   --  The largest response at least Margin pixels from the border.

   function Strongest
     (R      : access constant KM.Ks_Real_Image_Data;
      Width  : Positive;
      Height : Positive) return Long_Float
   is
      Best : Long_Float range -Response_Limit .. Response_Limit :=
        -Response_Limit;
   begin
      for Y in Margin .. Height - 1 - Margin loop
         for X in Margin .. Width - 1 - Margin loop
            Best := Long_Float'Max (Best, Read (R, X, Y));
         end loop;
      end loop;
      return Best;
   end Strongest;

   function Is_Peak
     (R      : access constant KM.Ks_Real_Image_Data;
      Width  : Positive;
      Height : Positive;
      X, Y   : Natural) return Boolean
   with
     Pre  => Usable (R, Width, Height)
             and then X >= NMS_Radius and then Y >= NMS_Radius
             and then X <= Width - 1 - NMS_Radius
             and then Y <= Height - 1 - NMS_Radius;
   --  The response at (X, Y) is the largest within NMS_Radius (a tie goes
   --  to the pixel first in raster order).

   function Is_Peak
     (R      : access constant KM.Ks_Real_Image_Data;
      Width  : Positive;
      Height : Positive;
      X, Y   : Natural) return Boolean
   is
      V : constant Long_Float := Read (R, X, Y);
   begin
      for Yy in Y - NMS_Radius .. Y + NMS_Radius loop
         pragma Loop_Invariant (True);
         for Xx in X - NMS_Radius .. X + NMS_Radius loop
            pragma Loop_Invariant (True);
            if Yy /= Y or else Xx /= X then
               declare
                  W : constant Long_Float := Read (R, Xx, Yy);
               begin
                  if W > V
                    or else (W = V
                             and then (Yy < Y or else (Yy = Y and then Xx < X)))
                  then
                     return False;
                  end if;
               end;
            end if;
         end loop;
      end loop;
      return True;
   end Is_Peak;

   ---------------------------------------------------------------------
   --  Sub-pixel refinement
   ---------------------------------------------------------------------

   Gradient_Limit : constant := 127.5;
   Product_Limit  : constant := Gradient_Limit * Gradient_Limit;
   Energy_Limit   : constant := 2.0 ** 22;
   Moment_Limit   : constant := 2.0 ** 26;
   --  A window has (2 Window + 1)**2 = 121 pixels: the sums of squared
   --  gradients stay below 121 * 127.5**2 (about 2.0E6, below 2**21), the
   --  moments below 121 * 2 * 127.5**2 * Window (about 2.0E7, below
   --  2**25).

   Min_Energy   : constant := 1000.0;
   Min_Isotropy : constant := 0.05;
   --  A window must hold gradient energy (the trace of the gradient
   --  scatter) of at least Min_Energy, and gradients in two directions:
   --  a determinant of the scatter of at least Min_Isotropy times its
   --  squared trace.

   function Gradient_X
     (S    : access constant KM.Ks_Real_Image_Data;
      X, Y : Natural) return Long_Float
   is (0.5 * (Smoothed (S, X + 1, Y) - Smoothed (S, X - 1, Y)))
   with Pre  => KM.Valid_Image (S) and then X >= 1
                and then X < S.Pixels'Last (2) and then Y <= S.Pixels'Last (1),
        Post => abs Gradient_X'Result <= Gradient_Limit;

   function Gradient_Y
     (S    : access constant KM.Ks_Real_Image_Data;
      X, Y : Natural) return Long_Float
   is (0.5 * (Smoothed (S, X, Y + 1) - Smoothed (S, X, Y - 1)))
   with Pre  => KM.Valid_Image (S) and then Y >= 1
                and then Y < S.Pixels'Last (1) and then X <= S.Pixels'Last (2),
        Post => abs Gradient_Y'Result <= Gradient_Limit;

   type Gradient_Sums is record
      Gxx : Long_Float range 0.0 .. Energy_Limit := 0.0;
      Gyy : Long_Float range 0.0 .. Energy_Limit := 0.0;
      Gxy : Long_Float range -Energy_Limit .. Energy_Limit := 0.0;
      Bx  : Long_Float range -Moment_Limit .. Moment_Limit := 0.0;
      By  : Long_Float range -Moment_Limit .. Moment_Limit := 0.0;
   end record;
   --  Over the window, with g the gradient and q the offset of a pixel
   --  from the window's centre: the sums of g g^T and of g g^T q.

   function Window_Sums
     (S      : access constant KM.Ks_Real_Image_Data;
      Cx, Cy : Natural) return Gradient_Sums
   with Pre => KM.Valid_Image (S)
               and then Cx >= Window + 1 and then Cy >= Window + 1
               and then Cx <= S.Pixels'Last (2) - Window - 1
               and then Cy <= S.Pixels'Last (1) - Window - 1;

   function Window_Sums
     (S      : access constant KM.Ks_Real_Image_Data;
      Cx, Cy : Natural) return Gradient_Sums
   is
      R : Gradient_Sums;
   begin
      --  The invariants (True) keep gnatprove from unrolling the loops.
      for Dy in -Window .. Window loop
         pragma Loop_Invariant (True);
         for Dx in -Window .. Window loop
            pragma Loop_Invariant (True);
            declare
               Gx  : constant Long_Float := Gradient_X (S, Cx + Dx, Cy + Dy);
               Gy  : constant Long_Float := Gradient_Y (S, Cx + Dx, Cy + Dy);
               Pxx : constant Long_Float :=
                 N.Square_Within (Gx, Gradient_Limit);
               Pyy : constant Long_Float :=
                 N.Square_Within (Gy, Gradient_Limit);
               Pxy : constant Long_Float :=
                 N.Mul_Within (Gx, Gy, Gradient_Limit, Gradient_Limit);
               Fx  : constant Long_Float := Long_Float (Dx);
               Fy  : constant Long_Float := Long_Float (Dy);
               Mx  : constant Long_Float :=
                 N.Mul_Within (Pxx, Fx, Product_Limit, 5.0)
                 + N.Mul_Within (Pxy, Fy, Product_Limit, 5.0);
               My  : constant Long_Float :=
                 N.Mul_Within (Pxy, Fx, Product_Limit, 5.0)
                 + N.Mul_Within (Pyy, Fy, Product_Limit, 5.0);
            begin
               R.Gxx := Long_Float'Min (R.Gxx + Pxx, Energy_Limit);
               R.Gyy := Long_Float'Min (R.Gyy + Pyy, Energy_Limit);
               R.Gxy := N.Clamp (R.Gxy + Pxy, Energy_Limit);
               R.Bx := N.Clamp (R.Bx + Mx, Moment_Limit);
               R.By := N.Clamp (R.By + My, Moment_Limit);
            end;
         end loop;
      end loop;
      return R;
   end Window_Sums;

   function Ratio (X, Y, Limit : Long_Float) return Long_Float
   with
     Pre  => abs X <= N.Mul_Limit and then Y > 0.0
             and then Y <= N.Mul_Limit
             and then Limit >= 1.0 and then Limit <= N.Mul_Limit,
     Post => abs Ratio'Result <= Limit;
   --  X / Y, saturated at +/-Limit.

   function Ratio (X, Y, Limit : Long_Float) return Long_Float is
      R    : Long_Float;
      Fits : Boolean;
   begin
      N.Ratio_Within (abs X, Y, Limit, R, Fits);
      if not Fits then
         R := Limit;
      end if;
      return (if X < 0.0 then -R else R);
   end Ratio;

   procedure Solve
     (G      : Gradient_Sums;
      Ox, Oy : out Long_Float;
      Found  : out Boolean)
   with Post => (if Found then abs Ox <= Long_Float (Window)
                               and then abs Oy <= Long_Float (Window)
                 else Ox = 0.0 and then Oy = 0.0);
   --  The offset of the corner from the window's centre, when the window
   --  is well conditioned and the offset lies within it.

   procedure Solve
     (G      : Gradient_Sums;
      Ox, Oy : out Long_Float;
      Found  : out Boolean)
   is
      Trace : constant Long_Float := G.Gxx + G.Gyy;
      Det   : constant Long_Float :=
        N.Mul_Within (G.Gxx, G.Gyy, Energy_Limit, Energy_Limit)
        - N.Square_Within (G.Gxy, Energy_Limit);
      Num_X : constant Long_Float :=
        N.Mul_Within (G.Gyy, G.Bx, Energy_Limit, Moment_Limit)
        - N.Mul_Within (G.Gxy, G.By, Energy_Limit, Moment_Limit);
      Num_Y : constant Long_Float :=
        N.Mul_Within (G.Gxx, G.By, Energy_Limit, Moment_Limit)
        - N.Mul_Within (G.Gxy, G.Bx, Energy_Limit, Moment_Limit);
   begin
      Ox := 0.0;
      Oy := 0.0;
      Found := Trace >= Min_Energy and then Det >= 1.0
               and then Det >= Min_Isotropy
                               * N.Square_Within (Trace, 2.0 * Energy_Limit);
      if not Found then
         return;
      end if;
      Ox := Ratio (Num_X, Det, 2.0 ** 60);
      Oy := Ratio (Num_Y, Det, 2.0 ** 60);
      if abs Ox > Long_Float (Window) or else abs Oy > Long_Float (Window) then
         Found := False;
         Ox := 0.0;
         Oy := 0.0;
      end if;
   end Solve;

   function Step (V : Long_Float) return Integer is
     (Integer'Max (-Window, Integer'Min (Window, Integer (V))))
   with Pre  => abs V <= Long_Float (Window),
        Post => Step'Result in -Window .. Window;
   --  V rounded to the nearest integer.

   procedure Refine
     (S      : access constant KM.Ks_Real_Image_Data;
      X0, Y0 : Natural;
      X, Y   : out Long_Float;
      Found  : out Boolean)
   with
     Pre  => KM.Valid_Image (S)
             and then X0 >= Window + 1 and then Y0 >= Window + 1
             and then X0 <= S.Pixels'Last (2) - Window - 1
             and then Y0 <= S.Pixels'Last (1) - Window - 1,
     Post => (if Found
              then X >= 0.0 and then X <= Long_Float (S.Pixels'Last (2))
                   and then Y >= 0.0
                   and then Y <= Long_Float (S.Pixels'Last (1)));
   --  The sub-pixel corner near the pixel (X0, Y0); Found is False when
   --  the window is not usable (see the spec).

   procedure Refine
     (S      : access constant KM.Ks_Real_Image_Data;
      X0, Y0 : Natural;
      X, Y   : out Long_Float;
      Found  : out Boolean)
   is
      Last_X : constant Natural := S.Pixels'Last (2);
      Last_Y : constant Natural := S.Pixels'Last (1);
      Cx     : Natural := X0;
      Cy     : Natural := Y0;
      Ox, Oy : Long_Float;
   begin
      X := 0.0;
      Y := 0.0;
      Found := False;
      for Iteration in 1 .. 3 loop
         pragma Loop_Invariant
           (Cx >= Window + 1 and then Cy >= Window + 1
            and then Cx <= Last_X - Window - 1
            and then Cy <= Last_Y - Window - 1
            and then not Found);
         Solve (Window_Sums (S, Cx, Cy), Ox, Oy, Found);
         if not Found then
            return;
         end if;
         if (abs Ox <= 0.5 and then abs Oy <= 0.5) or else Iteration = 3 then
            X := Long_Float (Cx) + Ox;
            Y := Long_Float (Cy) + Oy;
            Found := X >= 0.0 and then X <= Long_Float (Last_X)
                     and then Y >= 0.0 and then Y <= Long_Float (Last_Y);
            if not Found then
               X := 0.0;
               Y := 0.0;
            end if;
            return;
         end if;
         declare
            Nx : constant Integer := Cx + Step (Ox);
            Ny : constant Integer := Cy + Step (Oy);
         begin
            if Nx < Window + 1 or else Ny < Window + 1
              or else Nx > Last_X - Window - 1
              or else Ny > Last_Y - Window - 1
            then
               Found := False;
               return;
            end if;
            Cx := Nx;
            Cy := Ny;
            Found := False;
         end;
      end loop;
   end Refine;


   ---------------------------------------------------------------------
   --  Bilinear samples of the smoothed image
   ---------------------------------------------------------------------

   procedure Locate
     (V    : Long_Float;
      Last : Positive;
      I0   : out Natural;
      F    : out Long_Float)
   with
     Pre  => V >= 0.0 and then V <= Long_Float (Last),
     Post => I0 < Last and then F >= 0.0 and then F <= 1.0;
   --  The pixel at or before V (at most Last - 1) and the position of V
   --  between it and the next one.

   procedure Locate
     (V    : Long_Float;
      Last : Positive;
      I0   : out Natural;
      F    : out Long_Float)
   is
      Fl : constant Long_Float := Long_Float'Floor (V);
   begin
      I0 := Natural (Fl);
      if I0 > Last - 1 then
         I0 := Last - 1;
      end if;
      --  V - I0 lies in [0, 1]; the limit states it for the prover.
      F := N.Clamp_Unit (V - Long_Float (I0));
   end Locate;

   function Sample
     (S    : access constant KM.Ks_Real_Image_Data;
      X, Y : Long_Float) return Grey
   with
     Pre => KM.Valid_Image (S)
            and then S.Pixels'Last (2) >= 1 and then S.Pixels'Last (1) >= 1
            and then X >= 0.0 and then X <= Long_Float (S.Pixels'Last (2))
            and then Y >= 0.0 and then Y <= Long_Float (S.Pixels'Last (1));
   --  The smoothed image at (X, Y), interpolated bilinearly between pixel
   --  centres, read through a limit to [0, 255] (a weighted mean of grey
   --  levels lies there; the limit acts only by rounding at its ends).

   function Sample
     (S    : access constant KM.Ks_Real_Image_Data;
      X, Y : Long_Float) return Grey
   is
      X0, Y0 : Natural;
      Fx, Fy : Long_Float;
   begin
      Locate (X, S.Pixels'Last (2), X0, Fx);
      Locate (Y, S.Pixels'Last (1), Y0, Fy);
      declare
         P00 : constant Grey := Smoothed (S, X0, Y0);
         P10 : constant Grey := Smoothed (S, X0 + 1, Y0);
         P01 : constant Grey := Smoothed (S, X0, Y0 + 1);
         P11 : constant Grey := Smoothed (S, X0 + 1, Y0 + 1);
         A   : constant Long_Float := P00 + N.Times_Unit (P10 - P00, Fx);
         B   : constant Long_Float := P01 + N.Times_Unit (P11 - P01, Fx);
         V   : constant Long_Float := A + N.Times_Unit (B - A, Fy);
      begin
         return Long_Float'Max (0.0, Long_Float'Min (255.0, V));
      end;
   end Sample;

   function Inside
     (S    : access constant KM.Ks_Real_Image_Data;
      X, Y : Long_Float) return Boolean
   is (X >= 0.0 and then X <= Long_Float (S.Pixels'Last (2))
       and then Y >= 0.0 and then Y <= Long_Float (S.Pixels'Last (1)))
   with Pre => KM.Valid_Image (S);
   --  (X, Y) lies between the centres of the image's border pixels.

   ---------------------------------------------------------------------
   --  The X-junction test
   ---------------------------------------------------------------------

   subtype Unit is Long_Float range -1.0 .. 1.0;

   subtype Ring_Position is Natural range 0 .. Ring_Size - 1;

   type Unit_Table is array (Ring_Position) of Unit;

   C1 : constant := 0.923_879_532_511_286_756;   --  cos (Pi / 8)
   C2 : constant := 0.707_106_781_186_547_524;   --  cos (Pi / 4)
   C3 : constant := 0.382_683_432_365_089_772;   --  cos (3 Pi / 8)

   Ring_Cos : constant Unit_Table :=
     [1.0, C1, C2, C3, 0.0, -C3, -C2, -C1,
      -1.0, -C1, -C2, -C3, 0.0, C3, C2, C1];
   Ring_Sin : constant Unit_Table :=
     [0.0, C3, C2, C1, 1.0, C1, C2, C3,
      0.0, -C3, -C2, -C1, -1.0, -C1, -C2, -C3];
   --  Ring point K lies at the angle K * Pi / 8 (in a y-down image,
   --  clockwise from +x).

   type Ring_Array is array (Ring_Position) of Grey;

   function Next (K : Ring_Position) return Ring_Position is
     (if K = Ring_Size - 1 then 0 else K + 1);

   function In_Ring_Range
     (S    : access constant KM.Ks_Real_Image_Data;
      X, Y : Long_Float) return Boolean
   is (X >= Ring_Radius and then Y >= Ring_Radius
       and then X <= Long_Float (S.Pixels'Last (2)) - Ring_Radius
       and then Y <= Long_Float (S.Pixels'Last (1)) - Ring_Radius)
   with Pre => KM.Valid_Image (S);
   --  The ring about (X, Y) lies inside the image.

   procedure Read_Ring
     (S    : access constant KM.Ks_Real_Image_Data;
      X, Y : Long_Float;
      V    : out Ring_Array)
   with Pre => KM.Valid_Image (S) and then In_Ring_Range (S, X, Y);
   --  The smoothed image at the Ring_Size points of the ring about (X, Y).

   procedure Read_Ring
     (S    : access constant KM.Ks_Real_Image_Data;
      X, Y : Long_Float;
      V    : out Ring_Array) is
   begin
      --  The invariant (True) keeps gnatprove from unrolling the loop.
      for K in Ring_Position loop
         pragma Loop_Invariant (True);
         V (K) := Sample (S, X + N.Times_Unit (Ring_Radius, Ring_Cos (K)),
                             Y + N.Times_Unit (Ring_Radius, Ring_Sin (K)));
      end loop;
   end Read_Ring;

   procedure X_Test
     (S        : access constant KM.Ks_Real_Image_Data;
      X, Y     : Long_Float;
      Ok       : out Boolean;
      Mid      : out Grey;
      Contrast : out Grey)
   with Pre => KM.Valid_Image (S) and then In_Ring_Range (S, X, Y);
   --  The X-junction test of the corner at (X, Y) (see the spec), with the
   --  mid level and the contrast of its ring.

   procedure X_Test
     (S        : access constant KM.Ks_Real_Image_Data;
      X, Y     : Long_Float;
      Ok       : out Boolean;
      Mid      : out Grey;
      Contrast : out Grey)
   is
      Half    : constant := Ring_Size / 2;
      V       : Ring_Array;
      Lo      : Grey := 255.0;
      Hi      : Grey := 0.0;
      Changes : Natural := 0;
      Spread  : Long_Float range 0.0 .. 255.0 * Long_Float (Half) := 0.0;
   begin
      Read_Ring (S, X, Y, V);
      for K in Ring_Position loop
         pragma Loop_Invariant (True);
         Lo := Long_Float'Min (Lo, V (K));
         Hi := Long_Float'Max (Hi, V (K));
      end loop;
      Mid := 0.5 * (Lo + Hi);
      Contrast := Long_Float'Max (0.0, Hi - Lo);
      for K in Ring_Position loop
         pragma Loop_Invariant (Changes <= K);
         if (V (K) > Mid) /= (V (Next (K)) > Mid) then
            Changes := Changes + 1;
         end if;
      end loop;
      --  Half differences of at most 255 each: the limit never acts.
      for K in 0 .. Half - 1 loop
         pragma Loop_Invariant (True);
         Spread := Long_Float'Min
           (255.0 * Long_Float (Half), Spread + abs (V (K) - V (K + Half)));
      end loop;
      Ok := Contrast >= Min_Contrast and then Changes = 4
            and then Spread <= Long_Float (Half) * Max_Asymmetry * Contrast;
   end X_Test;

   procedure Unit_Direction
     (Dx, Dy  : Long_Float;
      Min_Len : Long_Float;
      Ex, Ey  : out Unit;
      Found   : out Boolean)
   with
     Pre  => abs Dx <= 2.0 ** 32 and then abs Dy <= 2.0 ** 32
             and then Min_Len > 0.0,
     Post => (if not Found then Ex = 1.0 and then Ey = 0.0);
   --  The unit vector along (Dx, Dy) when that vector is at least Min_Len
   --  long.

   procedure Unit_Direction
     (Dx, Dy  : Long_Float;
      Min_Len : Long_Float;
      Ex, Ey  : out Unit;
      Found   : out Boolean)
   is
      Len : constant Long_Float := N.Hypot (Dx, Dy);
      --  The length is at least abs Dx and abs Dy; the maximum states it
      --  for the prover (it never acts).
      Div : constant Long_Float :=
        Long_Float'Max (Len, Long_Float'Max (abs Dx, abs Dy));
   begin
      Ex := 1.0;
      Ey := 0.0;
      Found := Len >= Min_Len;
      if Found then
         Ex := N.Unit_Ratio (Dx, Div);
         Ey := N.Unit_Ratio (Dy, Div);
      end if;
   end Unit_Direction;

   procedure Edge_Lines
     (S        : access constant KM.Ks_Real_Image_Data;
      X, Y     : Long_Float;
      Mid      : Grey;
      E1x, E1y : out Unit;
      E2x, E2y : out Unit;
      Found    : out Boolean)
   with Pre => KM.Valid_Image (S) and then In_Ring_Range (S, X, Y);
   --  The directions of the two edge lines through the corner at (X, Y):
   --  the points where the ring crosses Mid, interpolated linearly between
   --  ring points, joined in opposite pairs. Found is False unless the
   --  ring crosses Mid exactly four times (or more: the first four count)
   --  and each pair is at least one radius apart.

   procedure Edge_Lines
     (S        : access constant KM.Ks_Real_Image_Data;
      X, Y     : Long_Float;
      Mid      : Grey;
      E1x, E1y : out Unit;
      E2x, E2y : out Unit;
      Found    : out Boolean)
   is
      type Point_List is array (1 .. 4) of Unit;
      V      : Ring_Array;
      Qx, Qy : Point_List := [others => 0.0];
      Count  : Natural := 0;
      Ok_1   : Boolean;
      Ok_2   : Boolean;
   begin
      E1x := 1.0;
      E1y := 0.0;
      E2x := 1.0;
      E2y := 0.0;
      Found := False;
      Read_Ring (S, X, Y, V);
      for K in Ring_Position loop
         pragma Loop_Invariant (Count <= 4);
         declare
            A : constant Long_Float := V (K) - Mid;
            B : constant Long_Float := V (Next (K)) - Mid;
         begin
            if (A > 0.0) /= (B > 0.0) and then Count < 4 then
               declare
                  --  The crossing lies at A / (A - B) of the way from point
                  --  K to the next one; as A and B differ in sign that is
                  --  abs A / (abs A + abs B), in [0, 1].
                  F  : constant Long_Float :=
                    N.Unit_Ratio (abs A, abs A + abs B);
                  Px : constant Long_Float :=
                    Ring_Cos (K)
                    + N.Times_Unit (Ring_Cos (Next (K)) - Ring_Cos (K), F);
                  Py : constant Long_Float :=
                    Ring_Sin (K)
                    + N.Times_Unit (Ring_Sin (Next (K)) - Ring_Sin (K), F);
               begin
                  Count := Count + 1;
                  --  A point of a chord of the unit circle: the limits
                  --  never act.
                  Qx (Count) := N.Clamp (Px, 1.0);
                  Qy (Count) := N.Clamp (Py, 1.0);
               end;
            end if;
         end;
      end loop;
      if Count = 4 then
         Unit_Direction (Qx (1) - Qx (3), Qy (1) - Qy (3), 1.0,
                         E1x, E1y, Ok_1);
         Unit_Direction (Qx (2) - Qx (4), Qy (2) - Qy (4), 1.0,
                         E2x, E2y, Ok_2);
         Found := Ok_1 and then Ok_2;
      end if;
   end Edge_Lines;

   ---------------------------------------------------------------------
   --  Candidates
   ---------------------------------------------------------------------

   function Count_Peaks
     (R         : access constant KM.Ks_Real_Image_Data;
      Width     : Positive;
      Height    : Positive;
      Threshold : Long_Float) return Natural
   with
     Pre  => Usable (R, Width, Height)
             and then Width > 2 * Margin and then Height > 2 * Margin,
     Post => Count_Peaks'Result <= Max_Corners;
   --  The pixels at least Margin pixels from the border whose response is
   --  at least Threshold and a peak (at most Max_Corners are counted).

   function Count_Peaks
     (R         : access constant KM.Ks_Real_Image_Data;
      Width     : Positive;
      Height    : Positive;
      Threshold : Long_Float) return Natural
   is
      Count : Natural := 0;
   begin
      for Y in Margin .. Height - 1 - Margin loop
         pragma Loop_Invariant (Count <= Max_Corners);
         for X in Margin .. Width - 1 - Margin loop
            pragma Loop_Invariant (Count <= Max_Corners);
            if Count < Max_Corners
              and then Read (R, X, Y) >= Threshold
              and then Is_Peak (R, Width, Height, X, Y)
            then
               Count := Count + 1;
            end if;
         end loop;
      end loop;
      return Count;
   end Count_Peaks;

   function Nearest (V : Long_Float; Last : Natural) return Natural is
     (Natural'Min (Last, Natural'Max (0, Integer (V))))
   with Pre  => V >= 0.0 and then V <= Long_Float (Last),
        Post => Nearest'Result <= Last;
   --  The pixel index nearest to V (the limits only spare the prover the
   --  rounding of the conversion).

   function Square_Distance (Ax, Ay, Bx, By : Long_Float) return Long_Float
   is (N.Square_Within (Ax - Bx, 2.0 ** 33)
       + N.Square_Within (Ay - By, 2.0 ** 33))
   with Pre  => abs Ax <= 2.0 ** 32 and then abs Ay <= 2.0 ** 32
                and then abs Bx <= 2.0 ** 32 and then abs By <= 2.0 ** 32,
        Post => Square_Distance'Result >= 0.0
                and then Square_Distance'Result <= 2.0 ** 67;

   function Near_Corner
     (Map   : access constant Index_Matrix;
      Cand  : access constant Candidate_Array;
      Count : Natural;
      X, Y  : Long_Float) return Boolean
   with Pre => Map /= null and then Cand /= null
               and then Map'First (1) = 0 and then Map'First (2) = 0
               and then Map'Last (1) < Max_Side
               and then Map'Last (2) < Max_Side
               and then X >= 0.0 and then X <= Long_Float (Map'Last (2))
               and then Y >= 0.0 and then Y <= Long_Float (Map'Last (1));
   --  A corner kept before lies within 2 pixels of (X, Y).

   function Near_Corner
     (Map   : access constant Index_Matrix;
      Cand  : access constant Candidate_Array;
      Count : Natural;
      X, Y  : Long_Float) return Boolean
   is
      Rx : constant Natural := Nearest (X, Map'Last (2));
      Ry : constant Natural := Nearest (Y, Map'Last (1));
   begin
      --  Stated once here, so that the precondition of Square_Distance in
      --  the loop need not derive it from the map's bounds (that took up
      --  to 30 seconds there).
      pragma Assert (abs X <= 2.0 ** 32 and then abs Y <= 2.0 ** 32);
      for Yy in Natural'Max (0, Ry - 3) .. Natural'Min (Map'Last (1), Ry + 3)
      loop
         for Xx in Natural'Max (0, Rx - 3)
                .. Natural'Min (Map'Last (2), Rx + 3)
         loop
            declare
               V : constant Int32 := Map (Yy, Xx);
            begin
               if V >= 1 and then Natural (V) <= Count
                 and then Natural (V) - 1 <= Cand'Last
                 and then Natural (V) - 1 >= Cand'First
                 and then Square_Distance
                            (Cand (Natural (V) - 1).X,
                             Cand (Natural (V) - 1).Y, X, Y) <= 4.0
               then
                  return True;
               end if;
            end;
         end loop;
      end loop;
      return False;
   end Near_Corner;

   procedure Find_Candidates
     (S         : access constant KM.Ks_Real_Image_Data;
      R         : access constant KM.Ks_Real_Image_Data;
      Width     : Positive;
      Height    : Positive;
      Threshold : Long_Float;
      Map       : Index_Map;
      Cand      : Candidate_Access;
      Count     : out Natural)
   with
     Pre  => Usable (S, Width, Height) and then Usable (R, Width, Height)
             and then Width > 2 * Margin and then Height > 2 * Margin
             and then Width <= Max_Side and then Height <= Max_Side
             and then Map /= null
             and then Map'First (1) = 0 and then Map'Last (1) = Height - 1
             and then Map'First (2) = 0 and then Map'Last (2) = Width - 1
             and then Cand /= null and then Cand'First = 0
             and then Cand'Last in 0 .. Max_Corners - 1,
     Post => Count <= Cand'Last + 1;
   --  The refined corners that pass the X-junction test, in raster order
   --  of their candidate pixels, at most as many as Cand holds; each
   --  entered in Map.

   procedure Find_Candidates
     (S         : access constant KM.Ks_Real_Image_Data;
      R         : access constant KM.Ks_Real_Image_Data;
      Width     : Positive;
      Height    : Positive;
      Threshold : Long_Float;
      Map       : Index_Map;
      Cand      : Candidate_Access;
      Count     : out Natural)
   is
      Last     : constant Integer := Cand'Last;
      Px       : Long_Float;
      Py       : Long_Float;
      Ok       : Boolean;
      Mid      : Grey;
      Contrast : Grey;
   begin
      Count := 0;
      for Y in Margin .. Height - 1 - Margin loop
         pragma Loop_Invariant (Count <= Last + 1);
         for X in Margin .. Width - 1 - Margin loop
            pragma Loop_Invariant (Count <= Last + 1);
            if Count <= Last
              and then Read (R, X, Y) >= Threshold
              and then Is_Peak (R, Width, Height, X, Y)
            then
               Refine (S, X, Y, Px, Py, Ok);
               if Ok
                 and then In_Ring_Range (S, Px, Py)
                 and then not Near_Corner (Map, Cand, Count, Px, Py)
               then
                  X_Test (S, Px, Py, Ok, Mid, Contrast);
                  if Ok then
                     Cand (Count) :=
                       (X => Px, Y => Py, Mid => Mid, Contrast => Contrast,
                        others => <>);
                     Map (Nearest (Py, Height - 1), Nearest (Px, Width - 1))
                       := Int32 (Count + 1);
                     Count := Count + 1;
                  end if;
               end if;
            end if;
         end loop;
      end loop;
   end Find_Candidates;

   ---------------------------------------------------------------------
   --  The grid
   ---------------------------------------------------------------------

   Min_Step : constant := 4.0;
   --  The shortest grid step (pixels).

   Line_Tolerance_2 : constant := 0.0676;
   --  The squared sine of 15 degrees: a seed's neighbour lies within 15
   --  degrees of one of its edge lines.

   Min_Sine_2 : constant := 0.09;
   --  The squared sine of about 17.5 degrees: a seed's two steps are at
   --  least that far from parallel.

   function Table_OK
     (Table : access constant Index_Matrix;
      Span  : Positive) return Boolean
   is (Table /= null and then Span <= Max_Span
       and then Table'First (1) = 0 and then Table'First (2) = 0
       and then Table'Last (1) = 2 * Span
       and then Table'Last (2) = 2 * Span);
   --  A grid table for the indices -Span .. Span.

   function Held
     (Table : access constant Index_Matrix;
      Span  : Positive;
      Count : Natural;
      I, J  : Integer) return Integer
   with
     Pre  => Table_OK (Table, Span)
             and then I in -2 * Max_Span .. 2 * Max_Span
             and then J in -2 * Max_Span .. 2 * Max_Span,
     Post => Held'Result in -1 .. Count - 1;
   --  The candidate that holds the grid indices (I, J), or -1.

   function Held
     (Table : access constant Index_Matrix;
      Span  : Positive;
      Count : Natural;
      I, J  : Integer) return Integer is
   begin
      if I < -Span or else I > Span or else J < -Span or else J > Span then
         return -1;
      end if;
      declare
         V : constant Int32 := Table (J + Span, I + Span);
      begin
         if V >= 1 and then Int64 (V) <= Int64 (Count) then
            return Integer (V) - 1;
         end if;
         return -1;
      end;
   end Held;

   procedure Lookup
     (Map    : access constant Index_Matrix;
      Cand   : access constant Candidate_Array;
      Count  : Natural;
      Qx, Qy : Long_Float;
      Radius : Long_Float;
      Found  : out Integer)
   with
     Pre  => Map /= null and then Map'First (1) = 0 and then Map'First (2) = 0
             and then Map'Last (1) in 0 .. Max_Side - 1
             and then Map'Last (2) in 0 .. Max_Side - 1
             and then Cand /= null and then Cand'First = 0
             and then Count - 1 <= Cand'Last
             and then abs Qx <= 2.0 ** 32 and then abs Qy <= 2.0 ** 32
             and then Radius >= 0.0 and then Radius <= 2.0 ** 32,
     Post => Found in -1 .. Count - 1 and then Found <= Cand'Last;
   --  The free candidate nearest to (Qx, Qy) within Radius (and within 65
   --  pixels along each axis), or -1.

   procedure Lookup
     (Map    : access constant Index_Matrix;
      Cand   : access constant Candidate_Array;
      Count  : Natural;
      Qx, Qy : Long_Float;
      Radius : Long_Float;
      Found  : out Integer)
   is
      Last_X : constant Natural := Map'Last (2);
      Last_Y : constant Natural := Map'Last (1);
      Reach  : constant Natural := Natural (N.Clamp (Radius, 64.0)) + 1;
      Best_D : Long_Float := N.Square_Within (Radius, 2.0 ** 32);
   begin
      Found := -1;
      if Qx < -Long_Float (Reach) or else Qy < -Long_Float (Reach)
        or else Qx > Long_Float (Last_X) + Long_Float (Reach)
        or else Qy > Long_Float (Last_Y) + Long_Float (Reach)
      then
         return;
      end if;
      declare
         Rx : constant Integer := Integer (Qx);
         Ry : constant Integer := Integer (Qy);
      begin
         for Yy in Integer'Max (0, Ry - Reach)
                .. Integer'Min (Last_Y, Ry + Reach)
         loop
            pragma Loop_Invariant (Found in -1 .. Count - 1);
            for Xx in Integer'Max (0, Rx - Reach)
                   .. Integer'Min (Last_X, Rx + Reach)
            loop
               pragma Loop_Invariant (Found in -1 .. Count - 1);
               declare
                  V : constant Int32 := Map (Yy, Xx);
               begin
                  if V >= 1 and then Int64 (V) <= Int64 (Count)
                    and then Natural (V) - 1 <= Cand'Last
                  then
                     declare
                        K : constant Natural := Natural (V) - 1;
                     begin
                        if Cand (K).Owner = 0 then
                           declare
                              D : constant Long_Float :=
                                Square_Distance
                                  (Cand (K).X, Cand (K).Y, Qx, Qy);
                           begin
                              if D <= Best_D then
                                 Found := K;
                                 Best_D := D;
                              end if;
                           end;
                        end if;
                     end;
                  end if;
               end;
            end loop;
         end loop;
      end;
   end Lookup;

   procedure Local_Step
     (Table   : access constant Index_Matrix;
      Span    : Positive;
      Cand    : access constant Candidate_Array;
      Count   : Positive;
      P       : Natural;
      Along_I : Boolean;
      Forward : Boolean;
      Sx, Sy  : out Step_Coordinate)
   with
     Pre => Table_OK (Table, Span)
            and then Cand /= null and then Cand'First = 0
            and then Count - 1 <= Cand'Last and then P < Count;
   --  The step from the grid corner P to its neighbour along the I axis
   --  (Along_I) or the J axis, forward (+1) or backward: P minus the
   --  neighbour behind it when that is in the grid, else the step between
   --  the corners of an adjacent row (or column) when both are in the
   --  grid, else the step P was found with.

   procedure Local_Step
     (Table   : access constant Index_Matrix;
      Span    : Positive;
      Cand    : access constant Candidate_Array;
      Count   : Positive;
      P       : Natural;
      Along_I : Boolean;
      Forward : Boolean;
      Sx, Sy  : out Step_Coordinate)
   is
      Pi   : constant Span_Index := Cand (P).I;
      Pj   : constant Span_Index := Cand (P).J;
      Sign : constant Integer := (if Forward then 1 else -1);
      Di   : constant Integer := (if Along_I then Sign else 0);
      Dj   : constant Integer := (if Along_I then 0 else Sign);
      Back : constant Integer := Held (Table, Span, Count, Pi - Di, Pj - Dj);
   begin
      if Back >= 0 then
         Sx := Cand (P).X - Cand (Back).X;
         Sy := Cand (P).Y - Cand (Back).Y;
         return;
      end if;
      for Side in Boolean loop
         declare
            Offset : constant Integer := (if Side then 1 else -1);
            Oi     : constant Integer := (if Along_I then 0 else Offset);
            Oj     : constant Integer := (if Along_I then Offset else 0);
            R1     : constant Integer :=
              Held (Table, Span, Count, Pi + Oi, Pj + Oj);
            R2     : constant Integer :=
              Held (Table, Span, Count, Pi + Oi + Di, Pj + Oj + Dj);
         begin
            if R1 >= 0 and then R2 >= 0 then
               Sx := Cand (R2).X - Cand (R1).X;
               Sy := Cand (R2).Y - Cand (R1).Y;
               return;
            end if;
         end;
      end loop;
      if Along_I then
         Sx := (if Forward then Cand (P).Ux else -Cand (P).Ux);
         Sy := (if Forward then Cand (P).Uy else -Cand (P).Uy);
      else
         Sx := (if Forward then Cand (P).Vx else -Cand (P).Vx);
         Sy := (if Forward then Cand (P).Vy else -Cand (P).Vy);
      end if;
   end Local_Step;

   function Cells_Ok
     (S      : access constant KM.Ks_Real_Image_Data;
      C      : Candidate;
      Ux, Uy : Step_Coordinate;
      Vx, Vy : Step_Coordinate;
      I, J   : Span_Index;
      Dark00 : Boolean) return Boolean
   with Pre => KM.Valid_Image (S)
               and then S.Pixels'Last (2) >= 1
               and then S.Pixels'Last (1) >= 1;
   --  The tile test (see the spec) of the corner C at the grid indices
   --  (I, J), with the steps U (along I) and V (along J); Dark00 tells
   --  whether the tile (0, 0) is dark.

   function Cells_Ok
     (S      : access constant KM.Ks_Real_Image_Data;
      C      : Candidate;
      Ux, Uy : Step_Coordinate;
      Vx, Vy : Step_Coordinate;
      I, J   : Span_Index;
      Dark00 : Boolean) return Boolean
   is
      Shade     : constant Long_Float := Cell_Margin * C.Contrast;
      Tolerance : constant Long_Float := Edge_Tolerance * C.Contrast;
      Fux       : constant Long_Float := Cell_Fraction * Ux;
      Fuy       : constant Long_Float := Cell_Fraction * Uy;
      Fvx       : constant Long_Float := Cell_Fraction * Vx;
      Fvy       : constant Long_Float := Cell_Fraction * Vy;
      Ex, Ey    : Unit;
      Fx, Fy    : Unit;
      Ok_U      : Boolean;
      Ok_V      : Boolean;
   begin
      --  The four tiles: (I, J) towards +U +V, (I - 1, J) towards -U +V,
      --  (I, J - 1) towards +U -V and (I - 1, J - 1) towards -U -V.
      for Tile in 0 .. 3 loop
         declare
            Plus_U : constant Boolean := Tile mod 2 = 0;
            Plus_V : constant Boolean := Tile < 2;
            Px     : constant Long_Float :=
              C.X + (if Plus_U then Fux else -Fux)
                  + (if Plus_V then Fvx else -Fvx);
            Py     : constant Long_Float :=
              C.Y + (if Plus_U then Fuy else -Fuy)
                  + (if Plus_V then Fvy else -Fvy);
            Ti     : constant Integer := (if Plus_U then I else I - 1);
            Tj     : constant Integer := (if Plus_V then J else J - 1);
            Dark   : constant Boolean := Dark00 = ((Ti + Tj) mod 2 = 0);
         begin
            if not Inside (S, Px, Py) then
               return False;
            end if;
            declare
               G : constant Grey := Sample (S, Px, Py);
            begin
               if (if Dark then G > C.Mid - Shade else G < C.Mid + Shade)
               then
                  return False;
               end if;
            end;
         end;
      end loop;

      --  The four edge points.
      Unit_Direction (Ux, Uy, Min_Step, Ex, Ey, Ok_U);
      Unit_Direction (Vx, Vy, Min_Step, Fx, Fy, Ok_V);
      if not Ok_U or else not Ok_V then
         return False;
      end if;
      for Edge in 0 .. 3 loop
         declare
            Dx : constant Unit :=
              (case Edge is
                  when 0      => Ex,
                  when 1      => -Ex,
                  when 2      => Fx,
                  when others => -Fx);
            Dy : constant Unit :=
              (case Edge is
                  when 0      => Ey,
                  when 1      => -Ey,
                  when 2      => Fy,
                  when others => -Fy);
            Px : constant Long_Float := C.X + Edge_Distance * Dx;
            Py : constant Long_Float := C.Y + Edge_Distance * Dy;
         begin
            if not Inside (S, Px, Py)
              or else abs (Sample (S, Px, Py) - C.Mid) > Tolerance
            then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Cells_Ok;

   procedure Seed_Steps
     (S              : access constant KM.Ks_Real_Image_Data;
      Cand           : access constant Candidate_Array;
      Count          : Positive;
      Seed           : Natural;
      Ux, Uy, Vx, Vy : out Step_Coordinate;
      Found          : out Boolean)
   with
     Pre => KM.Valid_Image (S)
            and then Cand /= null and then Cand'First = 0
            and then Count - 1 <= Cand'Last and then Seed < Count;
   --  The grid steps U and V of the seed (see the spec).

   procedure Seed_Steps
     (S              : access constant KM.Ks_Real_Image_Data;
      Cand           : access constant Candidate_Array;
      Count          : Positive;
      Seed           : Natural;
      Ux, Uy, Vx, Vy : out Step_Coordinate;
      Found          : out Boolean)
   is
      Sx       : constant Pixel_Position := Cand (Seed).X;
      Sy       : constant Pixel_Position := Cand (Seed).Y;
      E1x, E1y : Unit;
      E2x, E2y : Unit;
      Lines    : Boolean;
      Best_U   : Long_Float := 2.0 ** 64;
      Best_V   : Long_Float := 2.0 ** 64;
      U, V     : Integer := -1;
   begin
      Ux := 0.0;
      Uy := 0.0;
      Vx := 0.0;
      Vy := 0.0;
      Found := False;
      if not In_Ring_Range (S, Sx, Sy) then
         return;
      end if;
      Edge_Lines (S, Sx, Sy, Cand (Seed).Mid, E1x, E1y, E2x, E2y, Lines);
      if not Lines then
         return;
      end if;
      for K in 0 .. Count - 1 loop
         pragma Loop_Invariant (U in -1 .. Count - 1 and then V in -1 .. Count - 1);
         if K /= Seed and then Cand (K).Owner = 0 then
            declare
               Dx : constant Step_Coordinate := Cand (K).X - Sx;
               Dy : constant Step_Coordinate := Cand (K).Y - Sy;
               D2 : constant Long_Float :=
                 N.Square_Within (Dx, Coordinate_Limit)
                 + N.Square_Within (Dy, Coordinate_Limit);
               C1 : constant Long_Float :=
                 N.Times_Unit (Dx, E1y) - N.Times_Unit (Dy, E1x);
               C2 : constant Long_Float :=
                 N.Times_Unit (Dx, E2y) - N.Times_Unit (Dy, E2x);
            begin
               if D2 >= Min_Step * Min_Step then
                  if D2 < Best_U
                    and then N.Square_Within (C1, 2.0 ** 32)
                               <= Line_Tolerance_2 * D2
                  then
                     Best_U := D2;
                     U := K;
                  end if;
                  if D2 < Best_V
                    and then N.Square_Within (C2, 2.0 ** 32)
                               <= Line_Tolerance_2 * D2
                  then
                     Best_V := D2;
                     V := K;
                  end if;
               end if;
            end;
         end if;
      end loop;
      if U < 0 or else V < 0 then
         return;
      end if;
      Ux := Cand (U).X - Sx;
      Uy := Cand (U).Y - Sy;
      Vx := Cand (V).X - Sx;
      Vy := Cand (V).Y - Sy;
      declare
         Cross : constant Long_Float :=
           N.Mul_Within (Ux, Vy, Coordinate_Limit, Coordinate_Limit)
           - N.Mul_Within (Uy, Vx, Coordinate_Limit, Coordinate_Limit);
         Lu_2  : constant Long_Float :=
           N.Square_Within (Ux, Coordinate_Limit)
           + N.Square_Within (Uy, Coordinate_Limit);
         Lv_2  : constant Long_Float :=
           N.Square_Within (Vx, Coordinate_Limit)
           + N.Square_Within (Vy, Coordinate_Limit);
      begin
         Found := N.Square_Within (Cross, 2.0 ** 63)
                    >= Min_Sine_2 * N.Mul_Within (Lu_2, Lv_2, 2.0 ** 63,
                                                  2.0 ** 63);
      end;
      if not Found then
         Ux := 0.0;
         Uy := 0.0;
         Vx := 0.0;
         Vy := 0.0;
      end if;
   end Seed_Steps;

   function Grid_OK
     (S     : access constant KM.Ks_Real_Image_Data;
      Map   : access constant Index_Matrix;
      Table : access constant Index_Matrix;
      Queue : access constant Index_Matrix;
      Cand  : access constant Candidate_Array;
      Count : Positive;
      Span  : Positive) return Boolean
   is (KM.Valid_Image (S)
       and then S.Pixels'Last (2) >= 1 and then S.Pixels'Last (1) >= 1
       and then S.Pixels'Last (2) < Max_Side
       and then S.Pixels'Last (1) < Max_Side
       and then Map /= null
       and then Map'First (1) = 0 and then Map'First (2) = 0
       and then Map'Last (1) in 0 .. Max_Side - 1
       and then Map'Last (2) in 0 .. Max_Side - 1
       and then Table_OK (Table, Span)
       and then Queue /= null
       and then Queue'First (1) = 0 and then Queue'Last (1) = 0
       and then Queue'First (2) = 0 and then Queue'Last (2) = Count - 1
       and then Cand /= null and then Cand'First = 0
       and then Count - 1 <= Cand'Last and then Count <= Max_Corners);
   --  The work arrays of the grid search fit together.

   procedure Grow
     (S              : access constant KM.Ks_Real_Image_Data;
      Map            : access constant Index_Matrix;
      Table          : Index_Map;
      Queue          : Index_Map;
      Cand           : Candidate_Access;
      Count          : Positive;
      Span           : Positive;
      Seed           : Natural;
      Ux, Uy, Vx, Vy : Step_Coordinate;
      Dark00         : Boolean;
      Attempt        : Attempt_Number;
      Tail           : out Natural)
   with
     Pre  => Grid_OK (S, Map, Table, Queue, Cand, Count, Span)
             and then Seed < Count and then Attempt > 0,
     Post => Grid_OK (S, Map, Table, Queue, Cand, Count, Span)
             and then Tail in 1 .. Count;
   --  Grows the grid of the seed breadth first (see the spec): the corners
   --  that join it get Owner Attempt, their indices and steps, and their
   --  entries in Table, and Queue (0, 0 .. Tail - 1) lists them.

   procedure Grow
     (S              : access constant KM.Ks_Real_Image_Data;
      Map            : access constant Index_Matrix;
      Table          : Index_Map;
      Queue          : Index_Map;
      Cand           : Candidate_Access;
      Count          : Positive;
      Span           : Positive;
      Seed           : Natural;
      Ux, Uy, Vx, Vy : Step_Coordinate;
      Dark00         : Boolean;
      Attempt        : Attempt_Number;
      Tail           : out Natural)
   is
      Head : Natural := 0;
   begin
      Cand (Seed).Owner := Attempt;
      Cand (Seed).I := 0;
      Cand (Seed).J := 0;
      Cand (Seed).Ux := Ux;
      Cand (Seed).Uy := Uy;
      Cand (Seed).Vx := Vx;
      Cand (Seed).Vy := Vy;
      Table (Span, Span) := Int32 (Seed + 1);
      Queue (0, 0) := Int32 (Seed);
      Tail := 1;
      while Head < Tail loop
         pragma Loop_Invariant
           (Grid_OK (S, Map, Table, Queue, Cand, Count, Span)
            and then Head < Tail and then Tail <= Count);
         declare
            Q : constant Int32 := Queue (0, Head);
         begin
            if Q >= 0 and then Int64 (Q) < Int64 (Count) then
               for Dir in 0 .. 3 loop
                  pragma Loop_Invariant
                    (Grid_OK (S, Map, Table, Queue, Cand, Count, Span)
                     and then Head < Tail and then Tail <= Count);
                  declare
                     P       : constant Natural := Natural (Q);
                     Along_I : constant Boolean := Dir < 2;
                     Forward : constant Boolean := Dir mod 2 = 0;
                     Sign    : constant Integer := (if Forward then 1 else -1);
                     Ti      : constant Integer :=
                       Cand (P).I + (if Along_I then Sign else 0);
                     Tj      : constant Integer :=
                       Cand (P).J + (if Along_I then 0 else Sign);
                     Sx, Sy  : Step_Coordinate;
                     Ox, Oy  : Step_Coordinate;
                  begin
                     if Tail < Count
                       and then Ti in -Span .. Span
                       and then Tj in -Span .. Span
                       and then Held (Table, Span, Count, Ti, Tj) < 0
                     then
                        Local_Step (Table, Span, Cand, Count, P, Along_I,
                                    Forward, Sx, Sy);
                        Local_Step (Table, Span, Cand, Count, P, not Along_I,
                                    True, Ox, Oy);
                        declare
                           Ls : constant Long_Float := N.Hypot (Sx, Sy);
                           Lo : constant Long_Float := N.Hypot (Ox, Oy);
                           C  : Integer;
                        begin
                           if Ls >= Min_Step and then Lo >= Min_Step then
                              Lookup (Map, Cand, Count,
                                      Cand (P).X + Sx, Cand (P).Y + Sy,
                                      Search_Radius
                                        * Long_Float'Min (Ls, Lo),
                                      C);
                              if C >= 0 then
                                 declare
                                    Dx  : constant Step_Coordinate :=
                                      (if Forward
                                       then Cand (C).X - Cand (P).X
                                       else Cand (P).X - Cand (C).X);
                                    Dy  : constant Step_Coordinate :=
                                      (if Forward
                                       then Cand (C).Y - Cand (P).Y
                                       else Cand (P).Y - Cand (C).Y);
                                    Cux : constant Step_Coordinate :=
                                      (if Along_I then Dx else Ox);
                                    Cuy : constant Step_Coordinate :=
                                      (if Along_I then Dy else Oy);
                                    Cvx : constant Step_Coordinate :=
                                      (if Along_I then Ox else Dx);
                                    Cvy : constant Step_Coordinate :=
                                      (if Along_I then Oy else Dy);
                                 begin
                                    if Cells_Ok (S, Cand (C), Cux, Cuy,
                                                 Cvx, Cvy, Ti, Tj, Dark00)
                                    then
                                       Cand (C).Owner := Attempt;
                                       Cand (C).I := Ti;
                                       Cand (C).J := Tj;
                                       Cand (C).Ux := Cux;
                                       Cand (C).Uy := Cuy;
                                       Cand (C).Vx := Cvx;
                                       Cand (C).Vy := Cvy;
                                       Table (Tj + Span, Ti + Span) :=
                                         Int32 (C + 1);
                                       Queue (0, Tail) := Int32 (C);
                                       Tail := Tail + 1;
                                    end if;
                                 end;
                              end if;
                           end if;
                        end;
                     end if;
                  end;
               end loop;
            end if;
         end;
         Head := Head + 1;
      end loop;
   end Grow;

   procedure Release
     (Table : Index_Map;
      Queue : access constant Index_Matrix;
      Cand  : Candidate_Access;
      Count : Positive;
      Span  : Positive;
      Tail  : Natural;
      Keep  : Boolean)
   with
     Pre  => Table_OK (Table, Span)
             and then Queue /= null
             and then Queue'First (1) = 0 and then Queue'Last (1) = 0
             and then Queue'First (2) = 0 and then Queue'Last (2) = Count - 1
             and then Cand /= null and then Cand'First = 0
             and then Count - 1 <= Cand'Last and then Tail <= Count,
     Post => Table_OK (Table, Span);
   --  Clears the table entries of the corners of Queue (0, 0 .. Tail - 1)
   --  and, unless Keep, makes those corners free again.

   procedure Release
     (Table : Index_Map;
      Queue : access constant Index_Matrix;
      Cand  : Candidate_Access;
      Count : Positive;
      Span  : Positive;
      Tail  : Natural;
      Keep  : Boolean) is
   begin
      for K in 0 .. Tail - 1 loop
         pragma Loop_Invariant (Table_OK (Table, Span));
         declare
            Q : constant Int32 := Queue (0, K);
         begin
            if Q >= 0 and then Int64 (Q) < Int64 (Count) then
               declare
                  C : constant Natural := Natural (Q);
                  I : constant Span_Index := Cand (C).I;
                  J : constant Span_Index := Cand (C).J;
               begin
                  if I in -Span .. Span and then J in -Span .. Span then
                     Table (J + Span, I + Span) := 0;
                  end if;
                  if not Keep then
                     Cand (C).Owner := 0;
                  end if;
               end;
            end if;
         end;
      end loop;
   end Release;

   function Next_Seed
     (Cand   : access constant Candidate_Array;
      Count  : Positive;
      Cx, Cy : Long_Float) return Integer
   with
     Pre  => Cand /= null and then Cand'First = 0
             and then Count - 1 <= Cand'Last
             and then Cx in 0.0 .. 2.0 ** 31 and then Cy in 0.0 .. 2.0 ** 31,
     Post => Next_Seed'Result in -1 .. Count - 1;
   --  The free candidate not tried yet that is nearest to (Cx, Cy) (the
   --  first of equals), or -1.

   function Next_Seed
     (Cand   : access constant Candidate_Array;
      Count  : Positive;
      Cx, Cy : Long_Float) return Integer
   is
      Best   : Integer := -1;
      Best_D : Long_Float := 2.0 ** 67;
   begin
      for K in 0 .. Count - 1 loop
         pragma Loop_Invariant (Best in -1 .. Count - 1);
         if Cand (K).Owner = 0 and then not Cand (K).Tried then
            declare
               D : constant Long_Float :=
                 Square_Distance (Cand (K).X, Cand (K).Y, Cx, Cy);
            begin
               if Best < 0 or else D < Best_D then
                  Best := K;
                  Best_D := D;
               end if;
            end;
         end if;
      end loop;
      return Best;
   end Next_Seed;

   procedure Build_Grid
     (S                  : access constant KM.Ks_Real_Image_Data;
      Map                : access constant Index_Matrix;
      Table              : Index_Map;
      Queue              : Index_Map;
      Cand               : Candidate_Access;
      Count              : Positive;
      Span               : Positive;
      Best               : out Attempt_Number;
      Size               : out Natural;
      Bux, Buy, Bvx, Bvy : out Step_Coordinate)
   with
     Pre  => Grid_OK (S, Map, Table, Queue, Cand, Count, Span),
     Post => Grid_OK (S, Map, Table, Queue, Cand, Count, Span)
             and then Size <= Count;
   --  Tries seeds and grows their grids (see the spec). The largest grid
   --  has Size corners, those whose Owner is Best, and its seed's steps
   --  are Bu and Bv (Size 0 and Best 0 when no grid was grown).

   procedure Build_Grid
     (S                  : access constant KM.Ks_Real_Image_Data;
      Map                : access constant Index_Matrix;
      Table              : Index_Map;
      Queue              : Index_Map;
      Cand               : Candidate_Access;
      Count              : Positive;
      Span               : Positive;
      Best               : out Attempt_Number;
      Size               : out Natural;
      Bux, Buy, Bvx, Bvy : out Step_Coordinate)
   is
      Cx         : constant Long_Float :=
        0.5 * Long_Float (S.Pixels'Last (2));
      Cy         : constant Long_Float :=
        0.5 * Long_Float (S.Pixels'Last (1));
      Free_Count : Natural := Count;
      Seed       : Integer;
      Ux, Uy     : Step_Coordinate;
      Vx, Vy     : Step_Coordinate;
      Found      : Boolean;
      Tail       : Natural;
   begin
      Best := 0;
      Size := 0;
      Bux := 0.0;
      Buy := 0.0;
      Bvx := 0.0;
      Bvy := 0.0;
      for Try in 1 .. Max_Seeds loop
         pragma Loop_Invariant
           (Grid_OK (S, Map, Table, Queue, Cand, Count, Span)
            and then Size <= Count and then Free_Count <= Count);
         exit when Size >= Free_Count;
         Seed := Next_Seed (Cand, Count, Cx, Cy);
         exit when Seed < 0;
         Cand (Seed).Tried := True;
         Seed_Steps (S, Cand, Count, Seed, Ux, Uy, Vx, Vy, Found);
         if Found then
            declare
               C  : constant Candidate := Cand (Seed);
               Px : constant Long_Float :=
                 C.X + Cell_Fraction * Ux + Cell_Fraction * Vx;
               Py : constant Long_Float :=
                 C.Y + Cell_Fraction * Uy + Cell_Fraction * Vy;
            begin
               if Inside (S, Px, Py) then
                  declare
                     Dark00 : constant Boolean := Sample (S, Px, Py) < C.Mid;
                  begin
                     if Cells_Ok (S, C, Ux, Uy, Vx, Vy, 0, 0, Dark00) then
                        Grow (S, Map, Table, Queue, Cand, Count, Span, Seed,
                              Ux, Uy, Vx, Vy, Dark00, Try, Tail);
                        if Tail > Size then
                           Size := Tail;
                           Best := Try;
                           Bux := Ux;
                           Buy := Uy;
                           Bvx := Vx;
                           Bvy := Vy;
                        end if;
                        Release (Table, Queue, Cand, Count, Span, Tail,
                                 Keep => Tail >= Min_Corners);
                        if Tail >= Min_Corners then
                           Free_Count :=
                             Free_Count - Natural'Min (Free_Count, Tail);
                        end if;
                     end if;
                  end;
               end if;
            end;
         end if;
      end loop;
   end Build_Grid;

   ---------------------------------------------------------------------
   --  The result
   ---------------------------------------------------------------------

   procedure Emit
     (Table              : Index_Map;
      Cand               : access constant Candidate_Array;
      Count              : Positive;
      Span               : Positive;
      Best               : Attempt_Number;
      Bux, Buy, Bvx, Bvy : Step_Coordinate;
      Width, Height      : Positive;
      Corners            : out Corner_Array_Access;
      Size               : out Natural;
      Status             : out Ks_Status)
   with
     Pre  => Table_OK (Table, Span)
             and then Cand /= null and then Cand'First = 0
             and then Count - 1 <= Cand'Last and then Count <= Max_Corners
             and then Width <= Max_Side and then Height <= Max_Side,
     Post => Table_OK (Table, Span)
             and then Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Corners /= null
                            and then Size in Min_Corners .. Max_Corners
                            and then Corners'First = 0
                            and then Corners'Last = Size - 1
                            and then (for all K in Corners'Range
                                      => Corners (K).Pixel_X
                                           <= Long_Float (Width - 1)
                                         and then Corners (K).Pixel_Y
                                                    <= Long_Float
                                                         (Height - 1))
                            and then (for all K in 1 .. Size - 1
                                      => Row_Major_Less
                                           (Corners (K - 1), Corners (K)))
                       else Corners = null and then Size = 0);
   --  The corners of the grid of attempt Best (see the spec, step 7).
   --  Table is all zeros on entry; it holds the grid on return.

   procedure Too_Few (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Too_Few (Status : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter,
                   "CalibrationImage: fewer than 9 checkerboard corners "
                   & "were found");
   end Too_Few;

   procedure Out_Of_Memory (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Out_Of_Memory;

   procedure Out_Of_Memory (Status : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Out_Of_Memory,
                   "Calibrate: not enough memory");
   end Out_Of_Memory;

   procedure Emit
     (Table              : Index_Map;
      Cand               : access constant Candidate_Array;
      Count              : Positive;
      Span               : Positive;
      Best               : Attempt_Number;
      Bux, Buy, Bvx, Bvy : Step_Coordinate;
      Width, Height      : Positive;
      Corners            : out Corner_Array_Access;
      Size               : out Natural;
      Status             : out Ks_Status)
   is
      --  The grid's I axis is the step closest to +x: U unless V has the
      --  larger x component; Sign_I and Sign_J turn the I axis to +x and
      --  the J axis to +y.
      Swap    : constant Boolean := abs Bux < abs Bvx;
      Sign_I  : constant Integer :=
        (if (if Swap then Bvx else Bux) >= 0.0 then 1 else -1);
      Sign_J  : constant Integer :=
        (if (if Swap then Buy else Bvy) >= 0.0 then 1 else -1);
      Cx      : constant Long_Float := 0.5 * Long_Float (Width - 1);
      Cy      : constant Long_Float := 0.5 * Long_Float (Height - 1);
      Origin  : Integer := -1;
      Best_D  : Long_Float := 2.0 ** 67;
      Members : Natural := 0;
      Filled  : Natural := 0;
      Shift_I : Integer;
      Shift_J : Integer;
   begin
      Corners := null;
      Size := 0;

      --  Enter the grid in the table and find the corner nearest the image
      --  centre.
      for K in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (Table_OK (Table, Span) and then Members <= K
            and then Origin in -1 .. Count - 1);
         if Best > 0 and then Cand (K).Owner = Best
           and then Cand (K).I in -Span .. Span
           and then Cand (K).J in -Span .. Span
           and then Table (Cand (K).J + Span, Cand (K).I + Span) = 0
         then
            Table (Cand (K).J + Span, Cand (K).I + Span) := Int32 (K + 1);
            Members := Members + 1;
            declare
               D : constant Long_Float :=
                 Square_Distance (Cand (K).X, Cand (K).Y, Cx, Cy);
            begin
               if Origin < 0 or else D < Best_D then
                  Origin := K;
                  Best_D := D;
               end if;
            end;
         end if;
      end loop;

      if Members < Min_Corners or else Origin < 0 then
         Too_Few (Status);
         return;
      end if;

      --  The indices after turning are (Sign_I * A, Sign_J * B), with
      --  (A, B) = (I, J), or (J, I) when Swap; the origin's are subtracted.
      Shift_I := Sign_I * (if Swap then Cand (Origin).J else Cand (Origin).I);
      Shift_J := Sign_J * (if Swap then Cand (Origin).I else Cand (Origin).J);

      Allocate_Corners (Members, Corners);
      if Corners = null then
         Out_Of_Memory (Status);
         return;
      end if;

      --  Rows R and columns C of the turned grid in increasing order.
      for R in -Span .. Span loop
         pragma Loop_Invariant
           (Table_OK (Table, Span)
            and then Corners /= null and then Corners'First = 0
            and then Corners'Last = Members - 1
            and then Filled <= Members);
         pragma Loop_Invariant
           (for all K in 0 .. Filled - 1
            => Corners (K).Pixel_X <= Long_Float (Width - 1)
               and then Corners (K).Pixel_Y <= Long_Float (Height - 1));
         pragma Loop_Invariant
           (for all K in 1 .. Filled - 1
            => Row_Major_Less (Corners (K - 1), Corners (K)));
         pragma Loop_Invariant
           (if Filled > 0
            then Integer (Corners (Filled - 1).Grid_J) < R - Shift_J);
         for C in -Span .. Span loop
            pragma Loop_Invariant
              (Table_OK (Table, Span)
               and then Corners /= null and then Corners'First = 0
               and then Corners'Last = Members - 1
               and then Filled <= Members);
            pragma Loop_Invariant
              (for all K in 0 .. Filled - 1
               => Corners (K).Pixel_X <= Long_Float (Width - 1)
                  and then Corners (K).Pixel_Y <= Long_Float (Height - 1));
            pragma Loop_Invariant
              (for all K in 1 .. Filled - 1
               => Row_Major_Less (Corners (K - 1), Corners (K)));
            pragma Loop_Invariant
              (if Filled > 0
               then Integer (Corners (Filled - 1).Grid_J) < R - Shift_J
                    or else (Integer (Corners (Filled - 1).Grid_J)
                               = R - Shift_J
                             and then Integer (Corners (Filled - 1).Grid_I)
                                        < C - Shift_I));
            declare
               A : constant Integer := Sign_I * C;
               B : constant Integer := Sign_J * R;
               K : constant Integer :=
                 (if Swap then Held (Table, Span, Count, B, A)
                  else Held (Table, Span, Count, A, B));
            begin
               if K >= 0 and then Filled < Members
                 and then Cand (K).Owner = Best
               then
                  --  The limits to the image never act: every corner was
                  --  found inside it.
                  Corners (Filled) :=
                    (Pixel_X => Long_Float'Min (Cand (K).X,
                                                Long_Float (Width - 1)),
                     Pixel_Y => Long_Float'Min (Cand (K).Y,
                                                Long_Float (Height - 1)),
                     Grid_I  => Int32 (C - Shift_I),
                     Grid_J  => Int32 (R - Shift_J));
                  Filled := Filled + 1;
               end if;
            end;
         end loop;
      end loop;

      --  Filled counts the grid's entries of the table, as Members does:
      --  the check never fails.
      if Filled /= Members then
         Free (Corners);
         Too_Few (Status);
         return;
      end if;
      Size := Members;
      Set_Success (Status);
   end Emit;

   ---------------------------------------------------------------------
   --  Detect
   ---------------------------------------------------------------------

   procedure Smooth_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Result : out KM.Ks_Real_Image;
      Status : out Ks_Status)
   with
     Pre  => KI.Valid_Image (Image),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Usable (Result, Natural (Image.Width),
                                    Natural (Image.Height))
                       else Result = null);
   --  The image in floating point, smoothed.

   procedure Smooth_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Result : out KM.Ks_Real_Image;
      Status : out Ks_Status)
   is
      Plain : KM.Ks_Real_Image;
   begin
      Result := null;
      KM.From_Grey_8 (Image, Plain, Status);
      if not Succeeded (Status) then
         if Status.Failure /= Failure_Out_Of_Memory then
            Set_Failure (Status, Failure_Bad_Parameter,
                         "CalibrationImage cannot be converted");
         end if;
         return;
      end if;
      KM.Gaussian_Smooth (Plain, Sigma, Result, Status);
      Free (Plain.Pixels);
      Free (Plain);
      if not Succeeded (Status) then
         Result := null;
         return;
      end if;
   end Smooth_Image;

   procedure Detect
     (Image   : access constant KI.Ks_Image_8_Grey_Data;
      Corners : out Corner_Array_Access;
      Count   : out Natural;
      Status  : out Ks_Status)
   is
      Width     : constant Positive := Positive (Image.Width);
      Height    : constant Positive := Positive (Image.Height);
      Smooth    : KM.Ks_Real_Image;
      Resp      : KM.Ks_Real_Image;
      Map       : Index_Map;
      Table     : Index_Map;
      Queue     : Index_Map;
      Cand      : Candidate_Access;
      Peaks     : Natural;
      Found     : Natural;
      Span      : Positive;
      Best      : Attempt_Number;
      Size      : Natural;
      Bux, Buy  : Step_Coordinate;
      Bvx, Bvy  : Step_Coordinate;
      Threshold : Long_Float;
   begin
      Corners := null;
      Count := 0;
      if Width <= 2 * Margin or else Height <= 2 * Margin then
         Too_Few (Status);
         return;
      elsif Width > Max_Side or else Height > Max_Side then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "CalibrationImage: a side longer than 16777216 "
                      & "pixels");
         return;
      end if;

      Smooth_Image (Image, Smooth, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KM.Create (Int32 (Width), Int32 (Height), 0.0, Resp, Status);
      if not Succeeded (Status) then
         Free (Smooth.Pixels);
         Free (Smooth);
         if Status.Failure /= Failure_Out_Of_Memory then
            Too_Few (Status);
         end if;
         return;
      end if;
      Fill_Response (Smooth, Resp, Width, Height);
      Threshold := Long_Float'Max
        (Min_Response, Relative_Threshold * Strongest (Resp, Width, Height));

      --  The candidates.
      Peaks := Count_Peaks (Resp, Width, Height, Threshold);
      if Peaks < Min_Corners then
         Free (Resp.Pixels);
         Free (Resp);
         Free (Smooth.Pixels);
         Free (Smooth);
         Too_Few (Status);
         return;
      end if;
      Allocate_Map (Width, Height, Map);
      Allocate_Candidates (Peaks, Cand);
      if Map = null or else Cand = null then
         Free (Map);
         Free (Cand);
         Free (Resp.Pixels);
         Free (Resp);
         Free (Smooth.Pixels);
         Free (Smooth);
         Out_Of_Memory (Status);
         return;
      end if;
      Find_Candidates
        (Smooth, Resp, Width, Height, Threshold, Map, Cand, Found);
      Free (Resp.Pixels);
      Free (Resp);
      if Found < Min_Corners then
         Free (Map);
         Free (Cand);
         Free (Smooth.Pixels);
         Free (Smooth);
         Too_Few (Status);
         return;
      end if;

      --  The grid.
      Span := Natural'Min (Max_Span, Found);
      Allocate_Map (2 * Span + 1, 2 * Span + 1, Table);
      Allocate_Map (Found, 1, Queue);
      if Table = null or else Queue = null then
         Free (Table);
         Free (Queue);
         Free (Map);
         Free (Cand);
         Free (Smooth.Pixels);
         Free (Smooth);
         Out_Of_Memory (Status);
         return;
      end if;
      Build_Grid (Smooth, Map, Table, Queue, Cand, Found, Span,
                  Best, Size, Bux, Buy, Bvx, Bvy);
      Free (Queue);
      Free (Map);
      Free (Smooth.Pixels);
      Free (Smooth);
      if Size < Min_Corners then
         Free (Table);
         Free (Cand);
         Too_Few (Status);
         return;
      end if;

      --  The result.
      Emit (Table, Cand, Found, Span, Best, Bux, Buy, Bvx, Bvy,
            Width, Height, Corners, Count, Status);
      Free (Table);
      Free (Cand);
   end Detect;

end AMV.Kernels.Calib_Fix.Checkerboard;
