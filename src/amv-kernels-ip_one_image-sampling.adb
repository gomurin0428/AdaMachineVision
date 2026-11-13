pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package body AMV.Kernels.IP_One_Image.Sampling with SPARK_Mode is

   subtype Grey_8 is KI.Grey_8;

   function Sampled (I : Natural; Factor : Int32; N : Int32) return Natural
   is
      F : constant Int64 := Int64 (Factor);
      Q : constant Int64 := (Int64 (N) + F - 1) / F;
   begin
      pragma Assert (Q * F <= Int64 (N) + F - 1);
      pragma Assert (Int64 (I) <= Q - 1);
      pragma Assert (Int64 (I) * F <= (Q - 1) * F);
      pragma Assert (Int64 (I) * F <= Int64 (N) - 1);
      return I * Natural (Factor);
   end Sampled;

   function Expanded (I : Natural; Factor : Int32; N : Int32) return Natural
   is
   begin
      pragma Assert (Int64 (I) / Int64 (Factor) < Int64 (N));
      return I / Natural (Factor);
   end Expanded;

   Sum_Limit : constant := 2**40;

   function Block_Mean
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      X0, Y0 : Natural;
      SX, SY : Int32) return Grey_8
   with
     Pre => Common.Usable (Source)
            and then SX in 1 .. Max_Sample and then SY in 1 .. Max_Sample
            and then X0 < Natural (Source.Width)
            and then Y0 < Natural (Source.Height);
   --  The mean (rounded half up) of the pixels X0 .. X0 + SX - 1 by Y0 ..
   --  Y0 + SY - 1 that lie in the image (the limit on the sum never acts:
   --  a block holds at most Max_Sample**2 pixels).

   function Block_Mean
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      X0, Y0 : Natural;
      SX, SY : Int32) return Grey_8
   is
      X1    : constant Natural :=
        Natural (Int64'Min (Int64 (X0) + Int64 (SX) - 1,
                            Int64 (Source.Width) - 1));
      Y1    : constant Natural :=
        Natural (Int64'Min (Int64 (Y0) + Int64 (SY) - 1,
                            Int64 (Source.Height) - 1));
      Count : constant Int64 := Int64 (X1 - X0 + 1) * Int64 (Y1 - Y0 + 1);
      Sum   : Int64 := 0;
   begin
      for J in Y0 .. Y1 loop
         for I in X0 .. X1 loop
            Sum := Int64'Min (Sum + Int64 (Source.Pixels (J, I)), Sum_Limit);
            pragma Loop_Invariant (Sum in 0 .. Sum_Limit);
         end loop;
         pragma Loop_Invariant (Sum in 0 .. Sum_Limit);
      end loop;
      return Common.Limit_Grey ((2 * Sum + Count) / (2 * Count));
   end Block_Mean;

   procedure Sub_Sample
     (Source  : access constant KI.Ks_Image_8_Grey_Data;
      SX, SY  : Int32;
      Average : Boolean;
      Result  : out KI.Ks_Image_8_Grey;
      Status  : out Ks_Status)
   is
      W  : constant Int32 := Source.Width;
      H  : constant Int32 := Source.Height;
      OW : constant Int64 := Shrunk (Int64 (W), SX);
      OH : constant Int64 := Shrunk (Int64 (H), SY);
   begin
      pragma Assert (OW <= Int64 (W) and then OH <= Int64 (H));
      pragma Assert (OW * OH <= OW * Int64 (H));
      pragma Assert (OW * Int64 (H) <= Int64 (W) * Int64 (H));
      Common.New_Image (Int32 (OW), Int32 (OH), Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Result.Pixels'Range (1) loop
         for X in Result.Pixels'Range (2) loop
            Result.Pixels (Y, X) :=
              (if Average
               then Block_Mean (Source, Sampled (X, SX, W),
                                Sampled (Y, SY, H), SX, SY)
               else Source.Pixels (Sampled (Y, SY, H), Sampled (X, SX, W)));
            pragma Loop_Invariant
              (KI.Valid_Image (Result)
               and then Int64 (Result.Width) = OW
               and then Int64 (Result.Height) = OH);
            pragma Loop_Invariant
              (if not Average
               then
                 (for all J in 0 .. Y - 1 =>
                    (for all I in Result.Pixels'Range (2) =>
                       Result.Pixels (J, I)
                         = Source.Pixels (Sampled (J, SY, H),
                                          Sampled (I, SX, W)))));
            pragma Loop_Invariant
              (if not Average
               then
                 (for all I in 0 .. X =>
                    Result.Pixels (Y, I)
                      = Source.Pixels (Sampled (Y, SY, H),
                                       Sampled (I, SX, W))));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Result)
            and then Int64 (Result.Width) = OW
            and then Int64 (Result.Height) = OH);
         pragma Loop_Invariant
           (if not Average
            then
              (for all J in 0 .. Y =>
                 (for all I in Result.Pixels'Range (2) =>
                    Result.Pixels (J, I)
                      = Source.Pixels (Sampled (J, SY, H),
                                       Sampled (I, SX, W)))));
      end loop;
   end Sub_Sample;

   procedure Expand
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      EX, EY : Int32;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      W  : constant Int32 := Source.Width;
      H  : constant Int32 := Source.Height;
      OW : constant Int64 := Int64 (W) * Int64 (EX);
      OH : constant Int64 := Int64 (H) * Int64 (EY);
   begin
      pragma Assert (OW = Grown (Int64 (W), EX));
      pragma Assert (OH = Grown (Int64 (H), EY));
      Common.New_Image (Int32 (OW), Int32 (OH), Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Result.Pixels'Range (1) loop
         for X in Result.Pixels'Range (2) loop
            Result.Pixels (Y, X) :=
              Source.Pixels (Expanded (Y, EY, H), Expanded (X, EX, W));
            pragma Loop_Invariant
              (KI.Valid_Image (Result)
               and then Int64 (Result.Width) = OW
               and then Int64 (Result.Height) = OH);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1 =>
                 (for all I in Result.Pixels'Range (2) =>
                    Result.Pixels (J, I)
                      = Source.Pixels (Expanded (J, EY, H),
                                       Expanded (I, EX, W))));
            pragma Loop_Invariant
              (for all I in 0 .. X =>
                 Result.Pixels (Y, I)
                   = Source.Pixels (Expanded (Y, EY, H),
                                    Expanded (I, EX, W)));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Result)
            and then Int64 (Result.Width) = OW
            and then Int64 (Result.Height) = OH);
         pragma Loop_Invariant
           (for all J in 0 .. Y =>
              (for all I in Result.Pixels'Range (2) =>
                 Result.Pixels (J, I)
                   = Source.Pixels (Expanded (J, EY, H),
                                    Expanded (I, EX, W))));
      end loop;
   end Expand;

end AMV.Kernels.IP_One_Image.Sampling;
