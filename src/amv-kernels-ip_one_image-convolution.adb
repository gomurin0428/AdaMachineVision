pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Numerics;

package body AMV.Kernels.IP_One_Image.Convolution with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;

   Term_Limit : constant := Max_Kernel_Value * 255.0;

   function Term (K : Kernel_Value; P : KI.Grey_8) return Long_Float is
     (N.Mul_Within (K, Long_Float (P), Max_Kernel_Value, 255.0))
   with Post => Term'Result >= -Term_Limit and then Term'Result <= Term_Limit;
   --  K * P.

   function Convolution_Sum
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Kernel : Bounded_Kernel;
      Win    : Window;
      X, Y   : Natural) return Long_Float
   is
      W      : constant Int64 := Int64 (Source.Width);
      H      : constant Int64 := Int64 (Source.Height);
      X0     : constant Int64 := Int64 (X) - Int64 (Win.Origin_X);
      Y0     : constant Int64 := Int64 (Y) - Int64 (Win.Origin_Y);
      Inside : constant Boolean :=
        X0 >= 0 and then X0 + Int64 (Win.Width) <= W
        and then Y0 >= 0 and then Y0 + Int64 (Win.Height) <= H;
      --  The window lies in the image: no reflection needed.
      Sum    : Long_Float := 0.0;
   begin
      for Row in 0 .. Natural (Win.Height) - 1 loop
         declare
            Pixel_Y : constant Natural :=
              (if Inside then Natural (Y0 + Int64 (Row))
               else Common.Fold (Y0 + Int64 (Row), H));
         begin
            for Col in 0 .. Natural (Win.Width) - 1 loop
               declare
                  Pixel_X : constant Natural :=
                    (if Inside then Natural (X0 + Int64 (Col))
                     else Common.Fold (X0 + Int64 (Col), W));
               begin
                  --  At most Max_Convolve_Values terms of at most
                  --  Term_Limit: the limit never acts.
                  Sum := N.Clamp
                    (Sum + Term (Kernel (Row * Max_Convolve_Size + Col),
                                 Source.Pixels (Pixel_Y, Pixel_X)),
                     Sum_Limit);
               end;
               pragma Loop_Invariant
                 (Sum >= -Sum_Limit and then Sum <= Sum_Limit);
            end loop;
         end;
         pragma Loop_Invariant (Sum >= -Sum_Limit and then Sum <= Sum_Limit);
      end loop;
      return Sum;
   end Convolution_Sum;

   procedure Convolve
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Kernel : Bounded_Kernel;
      Win    : Window;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      Common.New_Image (Source.Width, Source.Height, Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Result.Pixels'Range (1) loop
         for X in Result.Pixels'Range (2) loop
            Result.Pixels (Y, X) :=
              (if Common.Selected (Region, Whole, X, Y)
               then Common.To_Grey
                      (Convolution_Sum (Source, Kernel, Win, X, Y))
               else Source.Pixels (Y, X));
            pragma Loop_Invariant (Common.Same_Size (Result, Source));
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1 =>
                 (for all I in Result.Pixels'Range (2) =>
                    Result.Pixels (J, I)
                      = (if Common.Selected (Region, Whole, I, J)
                         then Common.To_Grey
                                (Convolution_Sum (Source, Kernel, Win, I, J))
                         else Source.Pixels (J, I))));
            pragma Loop_Invariant
              (for all I in 0 .. X =>
                 Result.Pixels (Y, I)
                   = (if Common.Selected (Region, Whole, I, Y)
                      then Common.To_Grey
                             (Convolution_Sum (Source, Kernel, Win, I, Y))
                      else Source.Pixels (Y, I)));
         end loop;
         pragma Loop_Invariant (Common.Same_Size (Result, Source));
         pragma Loop_Invariant
           (for all J in 0 .. Y =>
              (for all I in Result.Pixels'Range (2) =>
                 Result.Pixels (J, I)
                   = (if Common.Selected (Region, Whole, I, J)
                      then Common.To_Grey
                             (Convolution_Sum (Source, Kernel, Win, I, J))
                      else Source.Pixels (J, I))));
      end loop;
   end Convolve;

end AMV.Kernels.IP_One_Image.Convolution;
