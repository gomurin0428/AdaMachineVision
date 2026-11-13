--  Numeric helpers shared by the kernels' bodies: finiteness, an
--  overflow-free length, angle reduction and the direction of a vector.
--  Internal: these are not entry points (they have preconditions and no
--  status), so the package is private to the kernels.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics;

private package AMV.Kernels.Numerics with SPARK_Mode, Pure is

   Pi      : constant := Ada.Numerics.Pi;
   Two_Pi  : constant := 2.0 * Pi;
   Half_Pi : constant := Pi / 2.0;

   function Is_Finite (X : Long_Float) return Boolean is
     (X >= -Long_Float'Last and then X <= Long_Float'Last);
   --  False for NaN and the infinities. The prover assumes every
   --  Long_Float is finite and so sees this as always True; at run time
   --  the kernels are compiled without floating-point validity checks
   --  (pragma Validity_Checks ("F")), so a NaN or an infinity coming from
   --  C or from the Ada API reaches this test and fails it.

   function In_Range (X : Long_Float; Limit : Long_Float) return Boolean is
     (Is_Finite (X) and then X >= -Limit and then X <= Limit);
   --  X is finite and within [-Limit, Limit].

   --  Bounded arithmetic. These are ordinary functions (their bodies are
   --  hidden from callers), so a caller's proof uses only the bound in
   --  the postcondition, which keeps the provers' work linear. They
   --  compute exactly what the plain operators compute.

   Mul_Limit : constant := 2.0 ** 510;
   --  About 3.4E153. The product of two such values is at most 2**1020
   --  (about 1.1E307), and the sum of two such products still fits.

   function Mul (X, Y : Long_Float) return Long_Float
   with
     Pre  => abs X <= Mul_Limit and then abs Y <= Mul_Limit,
     Post => abs Mul'Result <= 2.0 ** 1020
             and then (if X >= 0.0 and then Y >= 0.0
                       then Mul'Result >= 0.0);
   --  X * Y.

   Small_Limit : constant := 2.0 ** 501;
   --  About 6.5E150. The product of two such values is at most 2**1002,
   --  so 2**20 such products (a polygon's shoelace sum) still fit.

   function Mul_Small (X, Y : Long_Float) return Long_Float
   with
     Pre  => abs X <= Small_Limit and then abs Y <= Small_Limit,
     Post => abs Mul_Small'Result <= 2.0 ** 1002;
   --  X * Y, with a tighter bound than Mul.

   function Times_Unit (X, U : Long_Float) return Long_Float
   with
     Pre  => abs U <= 1.0,
     Post => abs Times_Unit'Result <= abs X
             and then (if X >= 0.0 and then U >= 0.0
                       then Times_Unit'Result >= 0.0);
   --  X * U for abs U <= 1 (a cosine or a sine, say).

   function Times_Small (X, S : Long_Float) return Long_Float
   with
     Pre  => abs S <= 4.0 and then abs X <= 2.0 ** 1000,
     Post => abs Times_Small'Result <= 4.0 * abs X
             and then (if X >= 0.0 and then S >= 0.0
                       then Times_Small'Result >= 0.0);
   --  X * S for abs S <= 4 (a sum of two products of sines and cosines,
   --  or an angle of at most Pi, say).

   function Unit_Ratio (X, Y : Long_Float) return Long_Float
   with
     Pre  => Y > 0.0 and then abs X <= Y,
     Post => abs Unit_Ratio'Result <= 1.0;
   --  X / Y for abs X <= Y.

   procedure Ratio_Within
     (X, Y   : Long_Float;
      Limit  : Long_Float;
      Result : out Long_Float;
      Fits   : out Boolean)
   with
     Pre  => X in 0.0 .. Mul_Limit and then Y > 0.0
             and then Y <= Mul_Limit and then Limit in 1.0 .. Mul_Limit,
     Post => (if Fits then Result in 0.0 .. Limit else Result = 0.0);
   --  Result := X / Y and Fits := True when that is at most Limit;
   --  otherwise Fits := False and Result := 0.0. Nothing overflows.

   Hypot_Limit : constant := 2.0 ** 1000;

   function Hypot (X, Y : Long_Float) return Long_Float
   with
     Pre  => abs X <= Hypot_Limit and then abs Y <= Hypot_Limit,
     Post => Hypot'Result >= 0.0
             and then Hypot'Result <= 2.0 * Long_Float'Max (abs X, abs Y)
             and then (if X = 0.0 and then Y = 0.0
                       then Hypot'Result = 0.0);
   --  Sqrt (X**2 + Y**2) without intermediate overflow or underflow:
   --  the direct formula when both magnitudes lie between 2**(-500) and
   --  2**500, otherwise the same after scaling by 2**600 or 2**(-600)
   --  (exact). The same algorithm as ks_misc_hypot.

   function Reduce_Two_Pi (X : Long_Float) return Long_Float
   with Post => Reduce_Two_Pi'Result > -Pi
                and then Reduce_Two_Pi'Result <= Pi;
   --  X modulo 2 Pi in (-Pi, Pi] (Pi here is the Long_Float nearest to
   --  it): X itself when already in that range, otherwise the exact IEEE
   --  remainder, with -Pi folded to +Pi and -0.0 to +0.0.

   function Reduce_Pi (X : Long_Float) return Long_Float
   with Post => Reduce_Pi'Result > -Half_Pi
                and then Reduce_Pi'Result <= Half_Pi;
   --  X modulo Pi in (-Pi/2, Pi/2], in the same way.

   function Direction (Y, X : Long_Float) return Long_Float
   with
     Pre  => X /= 0.0 or else Y /= 0.0,
     Post => Direction'Result > -Pi and then Direction'Result <= Pi;
   --  The angle of the non-zero vector (X, Y) in (-Pi, Pi]. A vector along
   --  the negative x axis gives +Pi whatever the sign of a zero Y.

   ---------------------------------------------------------------------
   --  Clamps and squares (AMV.Kernels.Image_Math, AMV.Kernels.Geometry)
   ---------------------------------------------------------------------

   function Clamp (X, Limit : Long_Float) return Long_Float is
     (if X >= -Limit then (if X <= Limit then X else Limit) else -Limit)
   with
     Pre  => Limit >= 0.0,
     Post => Clamp'Result >= -Limit and then Clamp'Result <= Limit
             and then (if X >= -Limit and then X <= Limit
                       then Clamp'Result = X);
   --  X limited to [-Limit, Limit] (-Limit for a NaN at run time). The
   --  kernels use it where a bound always holds mathematically, so that
   --  the bound is provable without a quantified fact, and on results that
   --  must stay within a documented bound (docs/PROOF.md lists each use).

   function Clamp_Unit (X : Long_Float) return Long_Float is
     (if X >= 0.0 then (if X <= 1.0 then X else 1.0) else 0.0)
   with
     Post => Clamp_Unit'Result >= 0.0 and then Clamp_Unit'Result <= 1.0
             and then (if X >= 0.0 and then X <= 1.0
                       then Clamp_Unit'Result = X);
   --  X limited to [0, 1] (0 for a NaN at run time).

   function Square (X : Long_Float) return Long_Float
   with
     Pre  => abs X <= Mul_Limit,
     Post => Square'Result >= 0.0 and then Square'Result <= 2.0 ** 1020;
   --  X * X.

   function Mul_Within (X, Y, Limit_X, Limit_Y : Long_Float) return Long_Float
   with
     Pre  => Limit_X >= 0.0 and then Limit_X <= Mul_Limit
             and then Limit_Y >= 0.0 and then Limit_Y <= Mul_Limit
             and then abs X <= Limit_X and then abs Y <= Limit_Y,
     Post => abs Mul_Within'Result <= Limit_X * Limit_Y;
   --  X * Y for X and Y within known bounds (constants at the call), so
   --  that the caller's proof gets the bound of the product. The body
   --  states the bound as a clamp, which never acts: rounding is
   --  monotonic, so the rounded product of X and Y stays within the
   --  rounded product of the bounds (docs/PROOF.md).

   function Square_Within (X, Limit : Long_Float) return Long_Float
   with
     Pre  => Limit >= 0.0 and then Limit <= Mul_Limit
             and then abs X <= Limit,
     Post => Square_Within'Result >= 0.0
             and then Square_Within'Result <= Limit * Limit;
   --  X * X, in the same way.

   procedure Quotient_Within
     (X, Y   : Long_Float;
      Limit  : Long_Float;
      Result : out Long_Float;
      Fits   : out Boolean)
   with
     Pre  => X >= 0.0 and then X <= 2.0 ** 1022 and then Y > 0.0
             and then Y <= Mul_Limit and then Limit >= 1.0
             and then Limit <= Mul_Limit,
     Post => (if Fits then Result >= 0.0 and then Result <= Limit
              else Result = 0.0);
   --  As Ratio_Within, for a dividend up to 2**1022 (a sum of two
   --  products of bounded values).

end AMV.Kernels.Numerics;
