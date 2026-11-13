pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package body AMV.Kernels.Filter_Inputs with SPARK_Mode is

   procedure Check_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      if Image = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "InputImage has no pixels");
      elsif not Usable_Image (Image) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "InputImage is not a valid image handle");
      else
         Set_Success (Status);
      end if;
   end Check_Image;

   procedure Check_Input
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Status : out Ks_Status) is
   begin
      Check_Image (Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Region /= null and then not KR.Valid_Region (Region) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "Region is not a valid pixel region handle");
      end if;
   end Check_Input;

   function Image_Of (Value : Int64) return String is
      Text  : String (1 .. 20) := [others => '0'];
      Rest  : Int64 := abs Value;
      First : Positive;
   begin
      --  At most 19 digits; the first character is left for the sign.
      for K in reverse 2 .. 20 loop
         Text (K) := Character'Val (Character'Pos ('0') + Rest mod 10);
         Rest := Rest / 10;
         First := K;
         exit when Rest = 0;
         pragma Loop_Invariant (First = K and then Rest >= 1);
      end loop;
      if Value < 0 then
         First := First - 1;
         Text (First) := '-';
      end if;
      declare
         Last   : constant Natural := 21 - First;
         Result : constant String (1 .. Last) := Text (First .. 20);
      begin
         return Result;
      end;
   end Image_Of;

end AMV.Kernels.Filter_Inputs;
