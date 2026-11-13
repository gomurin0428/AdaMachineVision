pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;

with AMV.Kernels.Numerics; use AMV.Kernels.Numerics;

package body AMV.Kernels.Misc with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;

   procedure Not_Finite
     (Status : out Ks_Status; Name : String)
   with
     Pre  => Name'First = 1 and then Name'Length <= 40,
     Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Not_Finite
     (Status : out Ks_Status; Name : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Name & " must be finite");
   end Not_Finite;

   procedure Deg_To_Rad
     (Degrees : Long_Float;
      Result  : out Long_Float;
      Status  : out Ks_Status) is
   begin
      Result := 0.0;
      if not Is_Finite (Degrees) then
         Not_Finite (Status, "Degrees");
         return;
      end if;
      --  The factor is a static constant rounded once, so the single
      --  product overflows only when the true result would.
      Result := Degrees * (Pi / 180.0);
      Set_Success (Status);
   end Deg_To_Rad;

   Max_Radians_For_Degrees : constant := 3.1E306;
   --  3.1E306 * 180 / Pi is about 1.78E308, below Long_Float'Last
   --  (about 1.80E308), so the product below cannot overflow.

   procedure Rad_To_Deg
     (Radians : Long_Float;
      Result  : out Long_Float;
      Status  : out Ks_Status) is
   begin
      Result := 0.0;
      if not Is_Finite (Radians) then
         Not_Finite (Status, "Radians");
         return;
      elsif abs Radians > Max_Radians_For_Degrees then
         Set_Failure
           (Status, Failure_Bad_Parameter,
            "Radians is too large to be converted to degrees");
         return;
      end if;
      Result := Radians * (180.0 / Pi);
      Set_Success (Status);
   end Rad_To_Deg;

   --  Norm_Angle and Norm_Angle_Pi reduce with the IEEE remainder (see
   --  AMV.Kernels.Numerics): exact for every finite argument, and a value
   --  already in range comes back unchanged.

   procedure Norm_Angle
     (Radians : Long_Float;
      Result  : out Long_Float;
      Status  : out Ks_Status) is
   begin
      Result := 0.0;
      if not Is_Finite (Radians) then
         Not_Finite (Status, "Radians");
         return;
      end if;
      Result := Reduce_Two_Pi (Radians);
      Set_Success (Status);
   end Norm_Angle;

   procedure Norm_Angle_Pi
     (Radians : Long_Float;
      Result  : out Long_Float;
      Status  : out Ks_Status) is
   begin
      Result := 0.0;
      if not Is_Finite (Radians) then
         Not_Finite (Status, "Radians");
         return;
      end if;
      Result := Reduce_Pi (Radians);
      Set_Success (Status);
   end Norm_Angle_Pi;

   procedure Angle_Difference
     (A, B   : Long_Float;
      Result : out Long_Float;
      Status : out Ks_Status) is
   begin
      Result := 0.0;
      if not Is_Finite (A) then
         Not_Finite (Status, "A");
         return;
      elsif not Is_Finite (B) then
         Not_Finite (Status, "B");
         return;
      end if;
      if abs A <= Long_Float'Last / 2.0 and then abs B <= Long_Float'Last / 2.0
      then
         Result := Reduce_Two_Pi (A - B);
      else
         --  A - B might overflow: reduce each angle first (the same angle
         --  up to rounding; at such magnitudes an angle carries no
         --  geometric meaning anyway).
         Result := Reduce_Two_Pi (Reduce_Two_Pi (A) - Reduce_Two_Pi (B));
      end if;
      Set_Success (Status);
   end Angle_Difference;

   procedure Hypot
     (X, Y   : Long_Float;
      Result : out Long_Float;
      Status : out Ks_Status)
   is
      Limit : constant := 2.0 ** 500;
      Scale : constant := 2.0 ** 600;
   begin
      Result := 0.0;
      if not Is_Finite (X) then
         Not_Finite (Status, "X");
         return;
      elsif not Is_Finite (Y) then
         Not_Finite (Status, "Y");
         return;
      end if;
      declare
         AX    : constant Long_Float := abs X;
         AY    : constant Long_Float := abs Y;
         Big   : constant Long_Float := Long_Float'Max (AX, AY);
         Small : constant Long_Float := Long_Float'Min (AX, AY);
      begin
         if Small = 0.0 then
            Result := Big;
         elsif Big < Limit and then Small > 1.0 / Limit then
            --  Neither square can overflow or lose precision to underflow.
            Result := EF.Sqrt (AX * AX + AY * AY);
         elsif Big >= Limit then
            --  Scale both down by the power of two Scale (exact, apart
            --  from a Small so far below Big that it is negligible), take
            --  the root, and scale back up unless that would overflow.
            --  ('Exponent and 'Scaling are not available in SPARK, so the
            --  scale is a constant.)
            declare
               SB   : constant Long_Float := Big / Scale;
               SS   : constant Long_Float := Small / Scale;
               Root : constant Long_Float := EF.Sqrt (SB * SB + SS * SS);
            begin
               if Root > Long_Float'Last / Scale then
                  Set_Failure
                    (Status, Failure_Bad_Parameter,
                     "the length of (X, Y) exceeds the largest Long_Float");
                  return;
               end if;
               Result := Root * Scale;
            end;
         elsif Big >= 1.0 / Limit then
            --  Small <= 2**(-500) <= 2**(-100) * Big: its square is below
            --  2**(-200) times Big's, so the length is Big to within
            --  rounding (Sqrt (Big * Big) gives back Big exactly).
            Result := Big;
         else
            --  Both tiny: scale up, take the root, scale back down.
            declare
               SB   : constant Long_Float := Big * Scale;
               SS   : constant Long_Float := Small * Scale;
               Root : constant Long_Float := EF.Sqrt (SB * SB + SS * SS);
            begin
               Result := Root / Scale;
            end;
         end if;
      end;
      Set_Success (Status);
   end Hypot;

end AMV.Kernels.Misc;
