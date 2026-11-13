--  Small numeric helpers (the counterpart of the CogMisc class).
--
--  The computations are done by the SPARK kernel AMV.Kernels.Misc (the C
--  functions ks_misc_*). Every argument must be finite: a NaN or an
--  infinity raises Ks_Bad_Parameter_Exception.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Numerics;

package AMV.Misc is
   pragma Preelaborate;

   Pi : constant := Ada.Numerics.Pi;

   function Deg_To_Rad (Degrees : Real) return Real;
   --  Converts an angle in degrees to radians: Degrees times the constant
   --  Pi / 180 (rounded once), so it never overflows.

   function Rad_To_Deg (Radians : Real) return Real;
   --  Converts an angle in radians to degrees: Radians times the constant
   --  180 / Pi (rounded once). Raises Ks_Bad_Parameter_Exception when
   --  abs Radians exceeds 3.1E306 (the result would come close to or
   --  exceed Real'Last).

   function Norm_Angle (Radians : Real) return Real;
   --  Returns the angle equivalent to Radians in the range (-Pi, Pi]: a
   --  value already in that range is returned unchanged; any other finite
   --  value is reduced exactly (IEEE remainder) by the machine value of
   --  2 Pi, -Pi going to +Pi and a non-zero multiple of 2 Pi to +0.0. The
   --  range holds for every finite argument, but beyond about 3.6E16
   --  (2**55) adjacent Real values are more than a turn apart, so the
   --  reduced angle of such an argument carries no geometric meaning.

   function Norm_Angle_Pi (Radians : Real) return Real;
   --  Returns the angle equivalent to Radians modulo Pi, in (-Pi/2, Pi/2],
   --  reduced in the same way as Norm_Angle (-Pi/2 goes to +Pi/2, a
   --  non-zero multiple of Pi to +0.0). Use it for undirected quantities
   --  such as the orientation of a line.

   function Angle_Difference (A, B : Real) return Real;
   --  Norm_Angle (A - B): the signed smallest rotation that turns B into A.
   --  When A or B exceeds Real'Last / 2 in magnitude, each is reduced
   --  first, so that A - B cannot overflow.

   function Hypot (X, Y : Real) return Real;
   --  Sqrt (X**2 + Y**2) without intermediate overflow or underflow: the
   --  result is finite and accurate whenever the true value is
   --  representable. Inputs whose magnitudes lie between 2**(-500) and
   --  2**500 take the direct formula (so results there are the same as
   --  Sqrt (X * X + Y * Y)); others are first scaled by an exact power of
   --  two. Raises Ks_Bad_Parameter_Exception when the result would exceed
   --  Real'Last.

end AMV.Misc;
