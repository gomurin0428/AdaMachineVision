pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;

package body AMV.Kernels.Numerics with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;

   function Mul (X, Y : Long_Float) return Long_Float is
   begin
      return X * Y;
   end Mul;

   function Mul_Small (X, Y : Long_Float) return Long_Float is
   begin
      return X * Y;
   end Mul_Small;

   function Times_Unit (X, U : Long_Float) return Long_Float is
      R : constant Long_Float := X * U;
   begin
      --  abs (X * U) <= abs X exactly, and rounding keeps it so; the
      --  tests below state it for the prover and are never true.
      if R > abs X then
         return abs X;
      elsif R < -abs X then
         return -abs X;
      end if;
      return R;
   end Times_Unit;

   function Times_Small (X, S : Long_Float) return Long_Float is
      R     : constant Long_Float := X * S;
      Limit : constant Long_Float := 4.0 * abs X;
   begin
      --  abs (X * S) <= 4 abs X exactly for abs S <= 4, and rounding keeps
      --  it so (4 abs X is exact); the tests below state it for the prover
      --  and are never true.
      if R > Limit then
         return Limit;
      elsif R < -Limit then
         return -Limit;
      end if;
      return R;
   end Times_Small;

   function Unit_Ratio (X, Y : Long_Float) return Long_Float is
      R : constant Long_Float := X / Y;
   begin
      --  As above: abs (X / Y) <= 1 exactly, and so after rounding.
      if R > 1.0 then
         return 1.0;
      elsif R < -1.0 then
         return -1.0;
      end if;
      return R;
   end Unit_Ratio;

   procedure Ratio_Within
     (X, Y   : Long_Float;
      Limit  : Long_Float;
      Result : out Long_Float;
      Fits   : out Boolean) is
   begin
      Result := 0.0;
      Fits := False;
      --  With Y >= 1 the quotient is at most X; below 1, Limit * Y cannot
      --  overflow, and the test keeps the quotient near Limit at most.
      if Y >= 1.0 or else X <= Limit * Y then
         declare
            Q : constant Long_Float := X / Y;
         begin
            if Q <= Limit then
               Result := Q;
               Fits := True;
            end if;
         end;
      end if;
   end Ratio_Within;

   function Root_Sum_Of_Squares (Big, Small : Long_Float) return Long_Float
   with Pre => Big in 0.0 .. Hypot_Limit and then Small in 0.0 .. Big;
   --  Sqrt (Big**2 + Small**2): the direct formula when both lie between
   --  2**(-500) and 2**500, otherwise the same after an exact scaling by
   --  2**600 or 2**(-600). No postcondition: Hypot clamps the result, so
   --  that its own proof stays short.

   function Root_Sum_Of_Squares (Big, Small : Long_Float) return Long_Float
   is
      Limit  : constant := 2.0 ** 500;
      Scale  : constant := 2.0 ** 600;
      Result : Long_Float;
   begin
      if Small = 0.0 then
         return Big;
      elsif Big < Limit and then Small > 1.0 / Limit then
         --  Neither square can overflow or lose precision to underflow.
         return EF.Sqrt (Big * Big + Small * Small);
      elsif Big >= Limit then
         --  Scale down (exact, apart from a Small so far below Big that
         --  it is negligible), take the root, scale back up.
         declare
            SB : constant Long_Float := Big / Scale;
            SS : constant Long_Float := Small / Scale;
         begin
            Result := EF.Sqrt (SB * SB + SS * SS);
            --  The root is at most Sqrt (2) * SB; Sqrt has no upper bound
            --  in its contract, so state it (never true at run time).
            if Result > 2.0 * SB then
               Result := 2.0 * SB;
            end if;
            return Result * Scale;
         end;
      elsif Big >= 1.0 / Limit then
         --  Small <= 2**(-500) <= 2**(-100) * Big: its square is below
         --  2**(-200) times Big's, so the length is Big to within
         --  rounding (Sqrt (Big * Big) gives back Big exactly).
         return Big;
      else
         --  Both tiny: scale up, take the root, scale back down.
         declare
            SB : constant Long_Float := Big * Scale;
            SS : constant Long_Float := Small * Scale;
         begin
            return EF.Sqrt (SB * SB + SS * SS) / Scale;
         end;
      end if;
   end Root_Sum_Of_Squares;

   function Hypot (X, Y : Long_Float) return Long_Float is
      Big   : constant Long_Float := Long_Float'Max (abs X, abs Y);
      Small : constant Long_Float := Long_Float'Min (abs X, abs Y);
   begin
      --  The length lies in [0, Sqrt (2) * Big]; stating it as a clamp,
      --  which never changes the value, keeps the proof short on every
      --  machine.
      return Long_Float'Min
               (Long_Float'Max (Root_Sum_Of_Squares (Big, Small), 0.0),
                2.0 * Big);
   end Hypot;

   --  Reduce_Two_Pi and Reduce_Pi use the IEEE remainder, which is exact
   --  for every finite argument however large: the result is the argument
   --  minus the nearest multiple of the period P (the machine value of
   --  2 Pi, or of Pi), so it lies in [-P/2, P/2]. The machine 2 Pi is
   --  exactly twice the machine Pi (and the machine Pi twice the machine
   --  Pi / 2), so the closed lower end -P/2 is the same angle as P/2,
   --  which is what it becomes. The fold also catches values outside
   --  [-P/2, P/2], which the IEEE remainder never produces: provers can
   --  show the exact range of 'Remainder only at high proof levels and not
   --  reliably, so the proof does not depend on it (docs/PROOF.md).

   function IEEE_Remainder (X, Period : Long_Float) return Long_Float
   with Pre => Period > 0.0;
   --  Long_Float'Remainder (X, Period). Kept in a function without a
   --  postcondition, so that its callers' proofs rest only on their own
   --  range tests (the provers' model of 'Remainder slows them down).

   function IEEE_Remainder (X, Period : Long_Float) return Long_Float is
   begin
      return Long_Float'Remainder (X, Period);
   end IEEE_Remainder;

   function Reduce_Two_Pi (X : Long_Float) return Long_Float is
      R : Long_Float;
   begin
      if X > -Pi and then X <= Pi then
         return X;
      end if;
      R := IEEE_Remainder (X, Two_Pi);
      if R <= -Pi or else R > Pi then
         return Pi;
      elsif R = 0.0 then
         return 0.0;  --  The remainder of a negative multiple is -0.0.
      else
         return R;
      end if;
   end Reduce_Two_Pi;

   function Reduce_Pi (X : Long_Float) return Long_Float is
      R : Long_Float;
   begin
      if X > -Half_Pi and then X <= Half_Pi then
         return X;
      end if;
      R := IEEE_Remainder (X, Pi);
      if R <= -Half_Pi or else R > Half_Pi then
         return Half_Pi;
      elsif R = 0.0 then
         return 0.0;  --  The remainder of a negative multiple is -0.0.
      else
         return R;
      end if;
   end Reduce_Pi;

   function Direction (Y, X : Long_Float) return Long_Float is
   begin
      if Y = 0.0 then
         return (if X >= 0.0 then 0.0 else Pi);
      end if;
      return Reduce_Two_Pi (EF.Arctan (Y, X));
   end Direction;

   function Square (X : Long_Float) return Long_Float is
   begin
      return X * X;
   end Square;

   function Mul_Within (X, Y, Limit_X, Limit_Y : Long_Float) return Long_Float
   is
   begin
      --  abs (X * Y) <= Limit_X * Limit_Y exactly, and rounding keeps it
      --  so; the clamp states it for the prover and never acts.
      return Clamp (X * Y, Limit_X * Limit_Y);
   end Mul_Within;

   function Square_Within (X, Limit : Long_Float) return Long_Float is
   begin
      --  As above; X * X is never negative.
      return Long_Float'Max (0.0, Clamp (X * X, Limit * Limit));
   end Square_Within;

   procedure Quotient_Within
     (X, Y   : Long_Float;
      Limit  : Long_Float;
      Result : out Long_Float;
      Fits   : out Boolean) is
   begin
      Result := 0.0;
      Fits := False;
      --  With Y >= 1 the quotient is at most X; below 1, Limit * Y cannot
      --  overflow, and the test keeps the quotient near Limit at most.
      if Y >= 1.0 or else X <= Limit * Y then
         declare
            Q : constant Long_Float := X / Y;
         begin
            if Q <= Limit then
               Result := Q;
               Fits := True;
            end if;
         end;
      end if;
   end Quotient_Within;

end AMV.Kernels.Numerics;
