pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Kernels.Misc;

package body AMV.Misc is

   package Kernel renames AMV.Kernels.Misc;

   function Deg_To_Rad (Degrees : Real) return Real is
      Result : Real;
      Status : AMV.Kernels.Ks_Status;
   begin
      Kernel.Deg_To_Rad (Degrees, Result, Status);
      AMV.Checks.Check (Status);
      return Result;
   end Deg_To_Rad;

   function Rad_To_Deg (Radians : Real) return Real is
      Result : Real;
      Status : AMV.Kernels.Ks_Status;
   begin
      Kernel.Rad_To_Deg (Radians, Result, Status);
      AMV.Checks.Check (Status);
      return Result;
   end Rad_To_Deg;

   function Norm_Angle (Radians : Real) return Real is
      Result : Real;
      Status : AMV.Kernels.Ks_Status;
   begin
      Kernel.Norm_Angle (Radians, Result, Status);
      AMV.Checks.Check (Status);
      return Result;
   end Norm_Angle;

   function Norm_Angle_Pi (Radians : Real) return Real is
      Result : Real;
      Status : AMV.Kernels.Ks_Status;
   begin
      Kernel.Norm_Angle_Pi (Radians, Result, Status);
      AMV.Checks.Check (Status);
      return Result;
   end Norm_Angle_Pi;

   function Angle_Difference (A, B : Real) return Real is
      Result : Real;
      Status : AMV.Kernels.Ks_Status;
   begin
      Kernel.Angle_Difference (A, B, Result, Status);
      AMV.Checks.Check (Status);
      return Result;
   end Angle_Difference;

   function Hypot (X, Y : Real) return Real is
      Result : Real;
      Status : AMV.Kernels.Ks_Status;
   begin
      Kernel.Hypot (X, Y, Result, Status);
      AMV.Checks.Check (Status);
      return Result;
   end Hypot;

end AMV.Misc;
