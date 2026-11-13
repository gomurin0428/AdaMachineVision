pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package body AMV.Kernels.IP_One_Image.Flip_Rotate with SPARK_Mode is

   procedure Apply
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Code   : Flip_Rotate_Code;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      W  : constant Int32 := Source.Width;
      H  : constant Int32 := Source.Height;
      OW : constant Int32 := (if Swapping (Code) then H else W);
      OH : constant Int32 := (if Swapping (Code) then W else H);
   begin
      Common.New_Image (OW, OH, Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Result.Pixels'Range (1) loop
         for X in Result.Pixels'Range (2) loop
            Result.Pixels (Y, X) :=
              Source.Pixels (Source_Y (Code, W, H, X, Y),
                             Source_X (Code, W, H, X, Y));
            pragma Loop_Invariant
              (KI.Valid_Image (Result)
               and then Result.Width = OW and then Result.Height = OH);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1 =>
                 (for all I in Result.Pixels'Range (2) =>
                    Result.Pixels (J, I)
                      = Source.Pixels (Source_Y (Code, W, H, I, J),
                                       Source_X (Code, W, H, I, J))));
            pragma Loop_Invariant
              (for all I in 0 .. X =>
                 Result.Pixels (Y, I)
                   = Source.Pixels (Source_Y (Code, W, H, I, Y),
                                    Source_X (Code, W, H, I, Y)));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Result)
            and then Result.Width = OW and then Result.Height = OH);
         pragma Loop_Invariant
           (for all J in 0 .. Y =>
              (for all I in Result.Pixels'Range (2) =>
                 Result.Pixels (J, I)
                   = Source.Pixels (Source_Y (Code, W, H, I, J),
                                    Source_X (Code, W, H, I, J))));
      end loop;
   end Apply;

end AMV.Kernels.IP_One_Image.Flip_Rotate;
