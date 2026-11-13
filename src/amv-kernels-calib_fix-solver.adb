pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Numerics;

package body AMV.Kernels.Calib_Fix.Solver with SPARK_Mode is

   package Num renames AMV.Kernels.Numerics;

   Sum_Limit : constant := 2.0 ** 210;
   --  A running sum of back substitution: B (K) and at most nine products
   --  of an entry and an unknown (each at most 2**200).

   subtype Sum_Value is Long_Float range -Sum_Limit .. Sum_Limit;

   function Largest (A : Matrix; N : Order) return Entry_Value
   with Post => Largest'Result >= 0.0;
   --  The largest magnitude of the entries of A (1 .. N, 1 .. N).

   function Largest (A : Matrix; N : Order) return Entry_Value is
      Result : Entry_Value := 0.0;
   begin
      for I in 1 .. N loop
         for J in 1 .. N loop
            if abs A (I, J) > Result then
               Result := abs A (I, J);
            end if;
            pragma Loop_Invariant (Result >= 0.0);
         end loop;
         pragma Loop_Invariant (Result >= 0.0);
      end loop;
      return Result;
   end Largest;

   procedure Swap_Rows
     (A    : in out Matrix;
      B    : in out Vector;
      N    : Order;
      P, K : Order)
   with Pre => P <= N and then K <= N;
   --  Exchanges rows P and K of A (1 .. N, 1 .. N) and of B.

   procedure Swap_Rows
     (A    : in out Matrix;
      B    : in out Vector;
      N    : Order;
      P, K : Order)
   is
      T : Entry_Value;
   begin
      for J in 1 .. N loop
         T := A (P, J);
         A (P, J) := A (K, J);
         A (K, J) := T;
      end loop;
      T := B (P);
      B (P) := B (K);
      B (K) := T;
   end Swap_Rows;

   function Pivot_Row (A : Matrix; N : Order; K : Order) return Order
   with
     Pre  => K <= N,
     Post => Pivot_Row'Result in K .. N;
   --  The row in K .. N whose entry in column K has the largest
   --  magnitude (the first such row).

   function Pivot_Row (A : Matrix; N : Order; K : Order) return Order is
      P : Order := K;
   begin
      for I in K + 1 .. N loop
         if abs A (I, K) > abs A (P, K) then
            P := I;
         end if;
         pragma Loop_Invariant (P in K .. I);
      end loop;
      return P;
   end Pivot_Row;

   procedure Eliminate_Row
     (A     : in out Matrix;
      B     : in out Vector;
      N     : Order;
      K, I  : Order;
      Found : out Boolean)
   with Pre => K < I and then I <= N;
   --  Subtracts F times row K from row I, F = A (I, K) / A (K, K), in the
   --  columns after K and in B. Found is False when the pivot is zero or
   --  smaller in magnitude than A (I, K) (neither happens after the pivot
   --  search) or when an entry would leave Entry_Limit.

   procedure Eliminate_Row
     (A     : in out Matrix;
      B     : in out Vector;
      N     : Order;
      K, I  : Order;
      Found : out Boolean)
   is
      Pivot : constant Entry_Value := A (K, K);
      F     : Long_Float;
      V     : Long_Float;
   begin
      Found := False;
      if Pivot = 0.0 or else abs A (I, K) > abs Pivot then
         return;
      end if;
      F := Num.Unit_Ratio (A (I, K), abs Pivot);
      if Pivot < 0.0 then
         F := -F;
      end if;
      for J in K + 1 .. N loop
         V := A (I, J) - Num.Times_Unit (A (K, J), F);
         if not (V >= -Entry_Limit and then V <= Entry_Limit) then
            return;
         end if;
         A (I, J) := V;
      end loop;
      V := B (I) - Num.Times_Unit (B (K), F);
      if not (V >= -Entry_Limit and then V <= Entry_Limit) then
         return;
      end if;
      B (I) := V;
      Found := True;
   end Eliminate_Row;

   procedure Back_Substitute
     (A     : Matrix;
      B     : Vector;
      N     : Order;
      X     : out Solution;
      Found : out Boolean)
   with Post => (if not Found then X = Zero_Solution);
   --  Solves the upper triangle of A (1 .. N, 1 .. N) for B.

   procedure Back_Substitute
     (A     : Matrix;
      B     : Vector;
      N     : Order;
      X     : out Solution;
      Found : out Boolean)
   is
      S    : Sum_Value;
      V    : Long_Float;
      Q    : Long_Float;
      Fits : Boolean;
   begin
      X := Zero_Solution;
      Found := False;
      for K in reverse 1 .. N loop
         S := B (K);
         for J in K + 1 .. N loop
            V := S - Num.Mul_Within (A (K, J), X (J), Entry_Limit,
                                   Solution_Limit);
            if not (V >= -Sum_Limit and then V <= Sum_Limit) then
               X := Zero_Solution;
               return;
            end if;
            S := V;
         end loop;
         if A (K, K) = 0.0 then
            X := Zero_Solution;
            return;
         end if;
         Num.Ratio_Within (abs S, abs A (K, K), Solution_Limit, Q, Fits);
         if not Fits then
            X := Zero_Solution;
            return;
         end if;
         X (K) := (if (S < 0.0) = (A (K, K) < 0.0) then Q else -Q);
      end loop;
      Found := True;
   end Back_Substitute;

   procedure Solve
     (A     : Matrix;
      B     : Vector;
      N     : Order;
      X     : out Solution;
      Found : out Boolean)
   is
      M     : Matrix := A;
      R     : Vector := B;
      Scale : constant Entry_Value := Largest (A, N);
      Tol   : constant Long_Float := Scale * Relative_Pivot;
      P     : Order;
   begin
      X := Zero_Solution;
      Found := False;
      if Scale = 0.0 then
         return;
      end if;
      for K in 1 .. N loop
         P := Pivot_Row (M, N, K);
         if not (abs M (P, K) >= Tol) or else M (P, K) = 0.0 then
            return;
         end if;
         if P /= K then
            Swap_Rows (M, R, N, P, K);
         end if;
         for I in K + 1 .. N loop
            Eliminate_Row (M, R, N, K, I, Found);
            if not Found then
               return;
            end if;
         end loop;
      end loop;
      Back_Substitute (M, R, N, X, Found);
   end Solve;

end AMV.Kernels.Calib_Fix.Solver;
