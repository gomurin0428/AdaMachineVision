pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package body AMV.Kernels.IP_One_Image.Common with SPARK_Mode is

   function Fold (I : Int64; N : Int64) return Natural is
   begin
      if I >= 0 and then I < N then
         return Natural (I);
      end if;
      declare
         M : constant Int64 := I mod (2 * N);
      begin
         if M < N then
            return Natural (M);
         else
            return Natural (2 * N - 1 - M);
         end if;
      end;
   end Fold;

   procedure New_Image
     (Width, Height : Int32;
      Result        : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status) is
   begin
      KI.Create (Width, Height, 0, Result, Status);
      if not Succeeded (Status) then
         --  The size is valid, so only the allocation can have failed.
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "IPOneImage: not enough memory for an image");
      end if;
   end New_Image;

   procedure Select_Pixels
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Full   : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      New_Image (Source.Width, Source.Height, Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Result.Pixels'Range (1) loop
         for X in Result.Pixels'Range (2) loop
            Result.Pixels (Y, X) :=
              (if Selected (Region, Whole, X, Y) then Full.Pixels (Y, X)
               else Source.Pixels (Y, X));
            pragma Loop_Invariant (Same_Size (Result, Source));
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1 =>
                 (for all I in Result.Pixels'Range (2) =>
                    Result.Pixels (J, I)
                      = (if Selected (Region, Whole, I, J)
                         then Full.Pixels (J, I)
                         else Source.Pixels (J, I))));
            pragma Loop_Invariant
              (for all I in 0 .. X =>
                 Result.Pixels (Y, I)
                   = (if Selected (Region, Whole, I, Y)
                      then Full.Pixels (Y, I)
                      else Source.Pixels (Y, I)));
         end loop;
         pragma Loop_Invariant (Same_Size (Result, Source));
         pragma Loop_Invariant
           (for all J in 0 .. Y =>
              (for all I in Result.Pixels'Range (2) =>
                 Result.Pixels (J, I)
                   = (if Selected (Region, Whole, I, J)
                      then Full.Pixels (J, I)
                      else Source.Pixels (J, I))));
      end loop;
   end Select_Pixels;

end AMV.Kernels.IP_One_Image.Common;
