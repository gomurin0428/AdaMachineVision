--  Kernel of AMV.Misc (the counterpart of the CogMisc class): angle
--  conversion and normalisation, and an overflow-free vector length.
--
--  Entry points (C names in include/amv.h). Every argument must be finite;
--  a NaN or an infinity gives Bad_Parameter. Results are as documented in
--  AMV.Misc.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics;

package AMV.Kernels.Misc with SPARK_Mode, Pure is

   Pi      : constant := Ada.Numerics.Pi;
   Half_Pi : constant := Pi / 2.0;

   procedure Deg_To_Rad
     (Degrees : Long_Float;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_misc_deg_to_rad",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  Degrees * Pi / 180. Never fails for a finite argument.

   procedure Rad_To_Deg
     (Radians : Long_Float;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_misc_rad_to_deg",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  Radians * 180 / Pi. Bad_Parameter when the result would exceed the
   --  largest Long_Float (abs Radians above about 3.1E306).

   procedure Norm_Angle
     (Radians : Long_Float;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_misc_norm_angle",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Result > -Pi and then Result <= Pi);
   --  The angle equivalent to Radians in (-Pi, Pi] (Pi here is the
   --  Long_Float nearest to it). An argument already in that range is
   --  returned unchanged.

   procedure Norm_Angle_Pi
     (Radians : Long_Float;
      Result  : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_misc_norm_angle_pi",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Result > -Half_Pi and then Result <= Half_Pi);
   --  The angle equivalent to Radians modulo Pi, in (-Pi/2, Pi/2].

   procedure Angle_Difference
     (A, B   : Long_Float;
      Result : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_misc_angle_difference",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Result > -Pi and then Result <= Pi);
   --  Norm_Angle (A - B). When A or B exceeds half the largest
   --  Long_Float, each is reduced first, so that A - B cannot overflow.

   procedure Hypot
     (X, Y   : Long_Float;
      Result : out Long_Float;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_misc_hypot",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Result >= 0.0);
   --  Sqrt (X**2 + Y**2) without intermediate overflow or underflow.
   --  Bad_Parameter when the result would exceed the largest Long_Float.

end AMV.Kernels.Misc;
