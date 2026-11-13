pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.IP_One_Image.Median;
with AMV.Kernels.Numerics;

package body AMV.Kernels.IP_One_Image.Smoothing with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;

   subtype Grey_8 is KI.Grey_8;

   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Grey_8_Matrix, KI.Grey_8_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Ks_Image_8_Grey_Data, KI.Ks_Image_8_Grey);

   ---------------------------------------------------------------------
   --  Binomial weights
   ---------------------------------------------------------------------

   Max_Order  : constant := 2 * Max_Smoothness;
   Coef_Limit : constant := 2**Max_Order;
   --  A binomial coefficient of order at most Max_Order is at most
   --  2**Max_Order (their sum).

   type Coefficients is array (0 .. Max_Order) of Int64;

   function Binomial (Order : Natural) return Coefficients
   with
     Pre  => Order <= Max_Order,
     Post => (for all K in Coefficients'Range =>
                Binomial'Result (K) in 0 .. Coef_Limit);
   --  C (Order, K) for K in 0 .. Order (Pascal's triangle; the limit to
   --  Coef_Limit never acts), 0 beyond.

   function Binomial (Order : Natural) return Coefficients is
      C : Coefficients := [0 => 1, others => 0];
   begin
      for M in 1 .. Order loop
         for K in reverse 1 .. M loop
            C (K) := Int64'Min (C (K) + C (K - 1), Coef_Limit);
            pragma Loop_Invariant
              (for all J in Coefficients'Range => C (J) in 0 .. Coef_Limit);
         end loop;
         pragma Loop_Invariant
           (for all J in Coefficients'Range => C (J) in 0 .. Coef_Limit);
      end loop;
      return C;
   end Binomial;

   function Power_Of_Two (Order : Natural) return Int64
   with
     Pre  => Order <= Max_Order,
     Post => Power_Of_Two'Result in 1 .. Coef_Limit;
   --  2**Order, the sum of the weights of that order (the limit never
   --  acts).

   function Power_Of_Two (Order : Natural) return Int64 is
      P : Int64 := 1;
   begin
      for I in 1 .. Order loop
         P := Int64'Min (P * 2, Coef_Limit);
         pragma Loop_Invariant (P in 1 .. Coef_Limit);
      end loop;
      return P;
   end Power_Of_Two;

   Term_Limit : constant := 255 * Coef_Limit;

   function Weighted (C : Int64; P : Grey_8) return Int64 is
     (C * Int64 (P))
   with
     Pre  => C in 0 .. Coef_Limit,
     Post => Weighted'Result in 0 .. Term_Limit;
   --  One term of a weighted sum.

   function Rounded (Sum, Den : Int64) return Grey_8 is
     (Common.Limit_Grey ((Sum + Den / 2) / Den))
   with Pre => Sum in 0 .. (Max_Order + 1) * Term_Limit
               and then Den in 1 .. Coef_Limit;
   --  Sum / Den rounded half up (at most 255, the limit never acting, the
   --  weights summing to Den).

   procedure Binomial_Rows
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Order  : Natural;
      Target : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Order <= Max_Order
             and then Order mod 2 = 0,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Common.Usable (Target)
                            and then Common.Same_Size (Target, Source)
                       else Target = null);
   --  Target (Y, X): the binomial weights of Order applied along row Y,
   --  centred on X (reflected at the ends), rounded.

   procedure Binomial_Rows
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Order  : Natural;
      Target : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      C   : constant Coefficients := Binomial (Order);
      Den : constant Int64 := Power_Of_Two (Order);
      W   : constant Int64 := Int64 (Source.Width);
      R   : constant Int64 := Int64 (Order / 2);
   begin
      Common.New_Image (Source.Width, Source.Height, Target, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Target.Pixels'Range (1) loop
         for X in Target.Pixels'Range (2) loop
            declare
               Sum : Int64 := 0;
            begin
               for K in 0 .. Order loop
                  Sum := Sum
                    + Weighted
                        (C (K),
                         Source.Pixels
                           (Y, Common.Fold (Int64 (X) + Int64 (K) - R, W)));
                  pragma Loop_Invariant
                    (Sum in 0 .. (Int64 (K) + 1) * Term_Limit);
               end loop;
               Target.Pixels (Y, X) := Rounded (Sum, Den);
            end;
            pragma Loop_Invariant (Common.Same_Size (Target, Source));
         end loop;
         pragma Loop_Invariant (Common.Same_Size (Target, Source));
      end loop;
   end Binomial_Rows;

   procedure Binomial_Columns
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Order  : Natural;
      Target : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Order <= Max_Order
             and then Order mod 2 = 0,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Common.Usable (Target)
                            and then Common.Same_Size (Target, Source)
                       else Target = null);
   --  The same along the columns.

   procedure Binomial_Columns
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Order  : Natural;
      Target : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      C   : constant Coefficients := Binomial (Order);
      Den : constant Int64 := Power_Of_Two (Order);
      H   : constant Int64 := Int64 (Source.Height);
      R   : constant Int64 := Int64 (Order / 2);
   begin
      Common.New_Image (Source.Width, Source.Height, Target, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Target.Pixels'Range (1) loop
         for X in Target.Pixels'Range (2) loop
            declare
               Sum : Int64 := 0;
            begin
               for K in 0 .. Order loop
                  Sum := Sum
                    + Weighted
                        (C (K),
                         Source.Pixels
                           (Common.Fold (Int64 (Y) + Int64 (K) - R, H), X));
                  pragma Loop_Invariant
                    (Sum in 0 .. (Int64 (K) + 1) * Term_Limit);
               end loop;
               Target.Pixels (Y, X) := Rounded (Sum, Den);
            end;
            pragma Loop_Invariant (Common.Same_Size (Target, Source));
         end loop;
         pragma Loop_Invariant (Common.Same_Size (Target, Source));
      end loop;
   end Binomial_Columns;

   procedure Smooth
     (Source       : access constant KI.Ks_Image_8_Grey_Data;
      Smoothness_X : Int32;
      Smoothness_Y : Int32;
      Result       : out KI.Ks_Image_8_Grey;
      Status       : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Smoothness_X in 0 .. Max_Smoothness
             and then Smoothness_Y in 0 .. Max_Smoothness,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Common.Same_Size (Result, Source)
                       else Result = null);
   --  The binomial smoothing of the whole image.

   procedure Smooth
     (Source       : access constant KI.Ks_Image_8_Grey_Data;
      Smoothness_X : Int32;
      Smoothness_Y : Int32;
      Result       : out KI.Ks_Image_8_Grey;
      Status       : out Ks_Status)
   is
      Rows : KI.Ks_Image_8_Grey;
   begin
      Result := null;
      Binomial_Rows (Source, 2 * Natural (Smoothness_X), Rows, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Binomial_Columns (Rows, 2 * Natural (Smoothness_Y), Result, Status);
      Free (Rows.Pixels);
      Free (Rows);
   end Smooth;

   ---------------------------------------------------------------------
   --  GaussSampler and UnsharpMask
   ---------------------------------------------------------------------

   function Shifted (V : Grey_8; Shift : Int32) return Grey_8
   with Pre => Shift in -Max_Magnitude_Shift .. Max_Magnitude_Shift;
   --  V shifted left by Shift bits (limited to 255), or right by -Shift.

   function Shifted (V : Grey_8; Shift : Int32) return Grey_8 is
      R : Int64 := Int64 (V);
   begin
      if Shift >= 0 then
         for I in 1 .. Shift loop
            R := Int64'Min (2 * R, 255);
            pragma Loop_Invariant (R in 0 .. 255);
         end loop;
      else
         for I in 1 .. -Shift loop
            R := R / 2;
            pragma Loop_Invariant (R in 0 .. 255);
         end loop;
      end if;
      return Grey_8 (R);
   end Shifted;

   function Sharpened
     (V, G   : Grey_8;
      Amount : Long_Float) return Grey_8
   is
     (Common.To_Grey
        (Long_Float (V)
         + N.Mul_Within (Amount, Long_Float (Int32 (V) - Int32 (G)),
                         Max_Amount, 255.0)))
   with Pre => Amount >= 0.0 and then Amount <= Max_Amount;
   --  V + Amount * (V - G), rounded and limited to 0 .. 255.

   procedure Gauss_Sampler
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Gauss_Sampler;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Smoothed : KI.Ks_Image_8_Grey;
   begin
      Result := null;
      Smooth (Source, Params.Smoothness_X, Params.Smoothness_Y, Smoothed,
              Status);
      if not Succeeded (Status) then
         return;
      end if;
      Common.New_Image (Source.Width, Source.Height, Result, Status);
      if Succeeded (Status) then
         for Y in Result.Pixels'Range (1) loop
            for X in Result.Pixels'Range (2) loop
               Result.Pixels (Y, X) :=
                 (if Common.Selected (Region, Whole, X, Y)
                  then Shifted (Smoothed.Pixels (Y, X),
                                Params.Magnitude_Shift)
                  else Source.Pixels (Y, X));
               pragma Loop_Invariant (Common.Same_Size (Result, Source));
               pragma Loop_Invariant
                 (for all J in 0 .. Y - 1 =>
                    (for all I in Result.Pixels'Range (2) =>
                       (if not Common.Selected (Region, Whole, I, J)
                        then Result.Pixels (J, I) = Source.Pixels (J, I))));
               pragma Loop_Invariant
                 (for all I in 0 .. X =>
                    (if not Common.Selected (Region, Whole, I, Y)
                     then Result.Pixels (Y, I) = Source.Pixels (Y, I)));
            end loop;
            pragma Loop_Invariant (Common.Same_Size (Result, Source));
            pragma Loop_Invariant
              (for all J in 0 .. Y =>
                 (for all I in Result.Pixels'Range (2) =>
                    (if not Common.Selected (Region, Whole, I, J)
                     then Result.Pixels (J, I) = Source.Pixels (J, I))));
         end loop;
      end if;
      Free (Smoothed.Pixels);
      Free (Smoothed);
   end Gauss_Sampler;

   procedure Unsharp_Mask
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Unsharp_Mask;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Smoothed : KI.Ks_Image_8_Grey;
   begin
      Result := null;
      Smooth (Source, Params.Smoothness_X, Params.Smoothness_Y, Smoothed,
              Status);
      if not Succeeded (Status) then
         return;
      end if;
      Common.New_Image (Source.Width, Source.Height, Result, Status);
      if Succeeded (Status) then
         for Y in Result.Pixels'Range (1) loop
            for X in Result.Pixels'Range (2) loop
               Result.Pixels (Y, X) :=
                 (if Common.Selected (Region, Whole, X, Y)
                  then Sharpened (Source.Pixels (Y, X),
                                  Smoothed.Pixels (Y, X), Params.Amount)
                  else Source.Pixels (Y, X));
               pragma Loop_Invariant (Common.Same_Size (Result, Source));
               pragma Loop_Invariant
                 (for all J in 0 .. Y - 1 =>
                    (for all I in Result.Pixels'Range (2) =>
                       (if not Common.Selected (Region, Whole, I, J)
                        then Result.Pixels (J, I) = Source.Pixels (J, I))));
               pragma Loop_Invariant
                 (for all I in 0 .. X =>
                    (if not Common.Selected (Region, Whole, I, Y)
                     then Result.Pixels (Y, I) = Source.Pixels (Y, I)));
            end loop;
            pragma Loop_Invariant (Common.Same_Size (Result, Source));
            pragma Loop_Invariant
              (for all J in 0 .. Y =>
                 (for all I in Result.Pixels'Range (2) =>
                    (if not Common.Selected (Region, Whole, I, J)
                     then Result.Pixels (J, I) = Source.Pixels (J, I))));
         end loop;
      end if;
      Free (Smoothed.Pixels);
      Free (Smoothed);
   end Unsharp_Mask;

   ---------------------------------------------------------------------
   --  BoxFilter
   ---------------------------------------------------------------------

   procedure Box_Rows
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Size   : Int32;
      Target : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Odd_Size (Size, Max_Kernel_Size),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Common.Usable (Target)
                            and then Common.Same_Size (Target, Source)
                       else Target = null);
   --  Target (Y, X): the mean of row Y over X - R .. X + R (reflected),
   --  rounded half up. A running sum (the limit to 255 Size never acts,
   --  the sum being one of Size grey levels).

   procedure Box_Rows
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Size   : Int32;
      Target : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      W : constant Int64 := Int64 (Source.Width);
      K : constant Int64 := Int64 (Size);
      R : constant Int64 := (K - 1) / 2;
   begin
      Common.New_Image (Source.Width, Source.Height, Target, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Target.Pixels'Range (1) loop
         declare
            Sum : Int64 := 0;
         begin
            for J in 0 .. K - 1 loop
               Sum := Sum + Int64 (Source.Pixels (Y, Common.Fold (J - R, W)));
               pragma Loop_Invariant (Sum in 0 .. (J + 1) * 255);
            end loop;
            for X in Target.Pixels'Range (2) loop
               Target.Pixels (Y, X) :=
                 Common.Limit_Grey ((2 * Sum + K) / (2 * K));
               if Int64 (X) < W - 1 then
                  Sum := Sum
                    + Int64 (Source.Pixels
                               (Y, Common.Fold (Int64 (X) + 1 + R, W)))
                    - Int64 (Source.Pixels
                               (Y, Common.Fold (Int64 (X) - R, W)));
                  Sum := Int64'Max (0, Int64'Min (Sum, 255 * K));
               end if;
               pragma Loop_Invariant (Common.Same_Size (Target, Source));
               pragma Loop_Invariant (Sum in 0 .. 255 * K);
            end loop;
         end;
         pragma Loop_Invariant (Common.Same_Size (Target, Source));
      end loop;
   end Box_Rows;

   procedure Box_Columns
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Size   : Int32;
      Target : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Odd_Size (Size, Max_Kernel_Size),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Common.Same_Size (Target, Source)
                       else Target = null);
   --  The same along the columns.

   procedure Box_Columns
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Size   : Int32;
      Target : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      H : constant Int64 := Int64 (Source.Height);
      K : constant Int64 := Int64 (Size);
      R : constant Int64 := (K - 1) / 2;
   begin
      Common.New_Image (Source.Width, Source.Height, Target, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for X in Target.Pixels'Range (2) loop
         declare
            Sum : Int64 := 0;
         begin
            for J in 0 .. K - 1 loop
               Sum := Sum + Int64 (Source.Pixels (Common.Fold (J - R, H), X));
               pragma Loop_Invariant (Sum in 0 .. (J + 1) * 255);
            end loop;
            for Y in Target.Pixels'Range (1) loop
               Target.Pixels (Y, X) :=
                 Common.Limit_Grey ((2 * Sum + K) / (2 * K));
               if Int64 (Y) < H - 1 then
                  Sum := Sum
                    + Int64 (Source.Pixels
                               (Common.Fold (Int64 (Y) + 1 + R, H), X))
                    - Int64 (Source.Pixels
                               (Common.Fold (Int64 (Y) - R, H), X));
                  Sum := Int64'Max (0, Int64'Min (Sum, 255 * K));
               end if;
               pragma Loop_Invariant (Common.Same_Size (Target, Source));
               pragma Loop_Invariant (Sum in 0 .. 255 * K);
            end loop;
         end;
         pragma Loop_Invariant (Common.Same_Size (Target, Source));
      end loop;
   end Box_Columns;

   procedure Box_Filter
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Box_Filter;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Rows, Full : KI.Ks_Image_8_Grey;
   begin
      Result := null;
      Box_Rows (Source, Params.Kernel_Width, Rows, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Box_Columns (Rows, Params.Kernel_Height, Full, Status);
      Free (Rows.Pixels);
      Free (Rows);
      if not Succeeded (Status) then
         return;
      end if;
      Common.Select_Pixels (Source, Full, Region, Whole, Result, Status);
      Free (Full.Pixels);
      Free (Full);
   end Box_Filter;

   ---------------------------------------------------------------------
   --  HighPassFilter
   ---------------------------------------------------------------------

   function High_Passed (V, S : Grey_8) return Grey_8 is
     (Common.Limit_Grey (Int64 (V) - Int64 (S) + 128));
   --  V - S + 128, limited to 0 .. 255.

   procedure Low_Pass
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_High_Pass_Filter;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Params.Processing_Mode
                        in High_Pass_Gauss .. High_Pass_Median
             and then Params.Smoothness_X in 0 .. Max_Smoothness
             and then Params.Smoothness_Y in 0 .. Max_Smoothness
             and then Odd_Size (Params.Kernel_Width, Max_Kernel_Size)
             and then Odd_Size (Params.Kernel_Height, Max_Kernel_Size),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Common.Same_Size (Result, Source)
                       else Result = null);
   --  The smoothed image S of HighPassFilter (the median only for the
   --  selected pixels; the others are not used).

   procedure Low_Pass
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_High_Pass_Filter;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Rows : KI.Ks_Image_8_Grey;
   begin
      Result := null;
      case Params.Processing_Mode is
         when High_Pass_Gauss =>
            Smooth (Source, Params.Smoothness_X, Params.Smoothness_Y, Result,
                    Status);
         when High_Pass_Mean =>
            Box_Rows (Source, Params.Kernel_Width, Rows, Status);
            if not Succeeded (Status) then
               return;
            end if;
            Box_Columns (Rows, Params.Kernel_Height, Result, Status);
            Free (Rows.Pixels);
            Free (Rows);
         when others =>
            AMV.Kernels.IP_One_Image.Median.Median_Filter
              (Source, Region, Whole, Params.Kernel_Width,
               Params.Kernel_Height, Result, Status);
      end case;
   end Low_Pass;

   procedure High_Pass_Filter
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_High_Pass_Filter;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Low : KI.Ks_Image_8_Grey;
   begin
      Result := null;
      Low_Pass (Source, Region, Whole, Params, Low, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Common.New_Image (Source.Width, Source.Height, Result, Status);
      if Succeeded (Status) then
         for Y in Result.Pixels'Range (1) loop
            for X in Result.Pixels'Range (2) loop
               Result.Pixels (Y, X) :=
                 (if Common.Selected (Region, Whole, X, Y)
                  then High_Passed (Source.Pixels (Y, X), Low.Pixels (Y, X))
                  else Source.Pixels (Y, X));
               pragma Loop_Invariant (Common.Same_Size (Result, Source));
               pragma Loop_Invariant
                 (for all J in 0 .. Y - 1 =>
                    (for all I in Result.Pixels'Range (2) =>
                       (if not Common.Selected (Region, Whole, I, J)
                        then Result.Pixels (J, I) = Source.Pixels (J, I))));
               pragma Loop_Invariant
                 (for all I in 0 .. X =>
                    (if not Common.Selected (Region, Whole, I, Y)
                     then Result.Pixels (Y, I) = Source.Pixels (Y, I)));
            end loop;
            pragma Loop_Invariant (Common.Same_Size (Result, Source));
            pragma Loop_Invariant
              (for all J in 0 .. Y =>
                 (for all I in Result.Pixels'Range (2) =>
                    (if not Common.Selected (Region, Whole, I, J)
                     then Result.Pixels (J, I) = Source.Pixels (J, I))));
         end loop;
      end if;
      Free (Low.Pixels);
      Free (Low);
   end High_Pass_Filter;

end AMV.Kernels.IP_One_Image.Smoothing;
