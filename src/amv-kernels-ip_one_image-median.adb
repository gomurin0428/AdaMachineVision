pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

package body AMV.Kernels.IP_One_Image.Median with SPARK_Mode is

   subtype Grey_8 is KI.Grey_8;

   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Grey_8_Matrix, KI.Grey_8_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Ks_Image_8_Grey_Data, KI.Ks_Image_8_Grey);

   type Counts is array (Grey_8) of Int64;

   Max_Area : constant := Max_Kernel_Size * Max_Kernel_Size;

   procedure Row_Medians
     (Source        : access constant KI.Ks_Image_8_Grey_Data;
      Y             : Natural;
      Width, Height : Int32;
      Full          : KI.Ks_Image_8_Grey)
   with
     Pre  => Common.Usable (Source) and then Common.Same_Size (Full, Source)
             and then Y < Natural (Source.Height)
             and then Odd_Size (Width, Max_Kernel_Size)
             and then Odd_Size (Height, Max_Kernel_Size),
     Post => Common.Same_Size (Full, Source);
   --  Full (Y, X) for every X: the median of the window around (X, Y).

   procedure Row_Medians
     (Source        : access constant KI.Ks_Image_8_Grey_Data;
      Y             : Natural;
      Width, Height : Int32;
      Full          : KI.Ks_Image_8_Grey)
   is
      W    : constant Int64 := Int64 (Source.Width);
      H    : constant Int64 := Int64 (Source.Height);
      KW   : constant Int64 := Int64 (Width);
      KH   : constant Int64 := Int64 (Height);
      A    : constant Int64 := KW * KH;
      Half : constant Int64 := (A + 1) / 2;
      RX   : constant Int64 := (KW - 1) / 2;
      RY   : constant Int64 := (KH - 1) / 2;
      Hist : Counts := [others => 0];
      M    : Grey_8 := 0;
      Lt   : Int64 := 0;
      --  M is the median of the window, Lt the number of its values below
      --  M; Hist counts the window's values (a count never leaves 0 .. A,
      --  and Lt never leaves 0 .. A: the tests that keep them there never
      --  act, the window always holding A values).
   begin
      pragma Assert (A in 1 .. Max_Area);
      --  The window around (0, Y).
      for DY in 0 .. KH - 1 loop
         declare
            Row : constant Natural :=
              Common.Fold (Int64 (Y) + DY - RY, H);
         begin
            for DX in 0 .. KW - 1 loop
               declare
                  V : constant Grey_8 :=
                    Source.Pixels (Row, Common.Fold (DX - RX, W));
               begin
                  if Hist (V) < A then
                     Hist (V) := Hist (V) + 1;
                  end if;
               end;
               pragma Loop_Invariant
                 (for all V in Grey_8 => Hist (V) in 0 .. A);
            end loop;
         end;
         pragma Loop_Invariant (for all V in Grey_8 => Hist (V) in 0 .. A);
      end loop;
      --  Its median: the smallest M with more than half the values <= M.
      while M < 255 and then Lt + Hist (M) < Half loop
         pragma Loop_Invariant (Lt in 0 .. A);
         pragma Loop_Variant (Increases => M);
         Lt := Lt + Hist (M);
         M := M + 1;
      end loop;
      Full.Pixels (Y, 0) := M;

      for X in 1 .. Natural (W - 1) loop
         declare
            Out_Column : constant Natural :=
              Common.Fold (Int64 (X) - 1 - RX, W);
            In_Column  : constant Natural := Common.Fold (Int64 (X) + RX, W);
         begin
            for DY in 0 .. KH - 1 loop
               declare
                  Row : constant Natural :=
                    Common.Fold (Int64 (Y) + DY - RY, H);
                  Old_Value : constant Grey_8 :=
                    Source.Pixels (Row, Out_Column);
                  New_Value : constant Grey_8 :=
                    Source.Pixels (Row, In_Column);
               begin
                  if Hist (Old_Value) > 0 then
                     Hist (Old_Value) := Hist (Old_Value) - 1;
                     if Old_Value < M and then Lt > 0 then
                        Lt := Lt - 1;
                     end if;
                  end if;
                  if Hist (New_Value) < A then
                     Hist (New_Value) := Hist (New_Value) + 1;
                     if New_Value < M and then Lt < A then
                        Lt := Lt + 1;
                     end if;
                  end if;
               end;
               pragma Loop_Invariant
                 (for all V in Grey_8 => Hist (V) in 0 .. A);
               pragma Loop_Invariant (Lt in 0 .. A);
            end loop;
         end;
         --  Down while at least half the values lie below M, then up while
         --  too few lie at or below it.
         while M > 0 and then Lt >= Half loop
            pragma Loop_Invariant (Lt in 0 .. A);
            pragma Loop_Variant (Decreases => M);
            M := M - 1;
            Lt := Int64'Max (0, Lt - Hist (M));
         end loop;
         while M < 255 and then Lt + Hist (M) < Half loop
            pragma Loop_Invariant (Lt in 0 .. A);
            pragma Loop_Variant (Increases => M);
            Lt := Lt + Hist (M);
            M := M + 1;
         end loop;
         Full.Pixels (Y, X) := M;
         pragma Loop_Invariant (Common.Same_Size (Full, Source));
         pragma Loop_Invariant (for all V in Grey_8 => Hist (V) in 0 .. A);
         pragma Loop_Invariant (Lt in 0 .. A);
      end loop;
   end Row_Medians;

   procedure Median_Filter
     (Source        : access constant KI.Ks_Image_8_Grey_Data;
      Region        : access constant KR.Ks_Pixel_Region_Data;
      Whole         : Boolean;
      Width, Height : Int32;
      Result        : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status)
   is
      Full : KI.Ks_Image_8_Grey;
   begin
      Result := null;
      Common.New_Image (Source.Width, Source.Height, Full, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Source.Pixels'Range (1) loop
         Row_Medians (Source, Y, Width, Height, Full);
         pragma Loop_Invariant (Common.Same_Size (Full, Source));
      end loop;
      Common.Select_Pixels (Source, Full, Region, Whole, Result, Status);
      Free (Full.Pixels);
      Free (Full);
   end Median_Filter;

end AMV.Kernels.IP_One_Image.Median;
