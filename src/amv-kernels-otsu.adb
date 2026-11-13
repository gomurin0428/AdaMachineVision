pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Numerics;

package body AMV.Kernels.Otsu with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;

   function Total (Counts : Level_Counts) return Int64 is
      Sum : Int64 := 0;
   begin
      for V in Grey_8 loop
         Sum := Sum + Counts (V);
         pragma Loop_Invariant (Sum in 0 .. (Int64 (V) + 1) * Max_Count);
      end loop;
      return Sum;
   end Total;

   function Weighted_Total (Counts : Level_Counts) return Int64 is
      Sum : Int64 := 0;
   begin
      for V in Grey_8 loop
         Sum := Sum + Times_Level (Counts (V), V);
         pragma Loop_Invariant
           (Sum in 0 .. (Int64 (V) + 1) * (255 * Max_Count));
      end loop;
      return Sum;
   end Weighted_Total;

   function Threshold (Counts : Level_Counts) return Int32 is
      Limit_Count : constant := 2.0 ** 40;
      Limit_Sum   : constant := 2.0 ** 48;
      Limit_Diff  : constant := 2.0 ** 90;
      Count       : constant Int64 := Total (Counts);
      Sum         : constant Int64 := Weighted_Total (Counts);
      Count_0     : Int64 := 0;
      Sum_0       : Int64 := 0;
      Best        : Long_Float := 0.0;
      Best_T      : Int32 := No_Split;
   begin
      for T in Int32 range 1 .. 255 loop
         pragma Loop_Invariant (Count_0 in 0 .. Int64 (T - 1) * Max_Count);
         pragma Loop_Invariant
           (Sum_0 in 0 .. Int64 (T - 1) * (255 * Max_Count));
         pragma Loop_Invariant (Best_T = No_Split or else Best_T in 1 .. T);
         declare
            V : constant Grey_8 := Grey_8 (T - 1);
         begin
            Count_0 := Count_0 + Counts (V);
            Sum_0 := Sum_0 + Times_Level (Counts (V), V);
         end;
         declare
            Count_1 : constant Int64 := Count - Count_0;
            Sum_1   : constant Int64 := Sum - Sum_0;
         begin
            if Count_0 > 0 and then Count_1 > 0 then
               declare
                  N0    : constant Long_Float := Long_Float (Count_0);
                  N1    : constant Long_Float := Long_Float (Count_1);
                  S0    : constant Long_Float := Long_Float (Sum_0);
                  S1    : constant Long_Float := Long_Float (Sum_1);
                  P     : constant Long_Float :=
                    N.Mul_Within (N1, S0, Limit_Count, Limit_Sum);
                  Q     : constant Long_Float :=
                    N.Mul_Within (N0, S1, Limit_Count, Limit_Sum);
                  D     : constant Long_Float := P - Q;
                  D2    : constant Long_Float :=
                    N.Square_Within (D, Limit_Diff);
                  Den   : constant Long_Float :=
                    N.Mul_Within (N0, N1, Limit_Count, Limit_Count);
                  Score : Long_Float;
                  Fits  : Boolean;
               begin
                  if Den > 0.0 then
                     N.Ratio_Within (D2, Den, 2.0 ** 200, Score, Fits);
                     if Fits and then (Best_T = No_Split or else Score > Best)
                     then
                        Best := Score;
                        Best_T := T;
                     end if;
                  end if;
               end;
            end if;
         end;
      end loop;
      return Best_T;
   end Threshold;

end AMV.Kernels.Otsu;
