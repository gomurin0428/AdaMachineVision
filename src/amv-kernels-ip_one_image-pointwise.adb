pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Numerics;

package body AMV.Kernels.IP_One_Image.Pointwise with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;

   function Product (V : Grey_8; C : Long_Float) return Long_Float is
      P : constant Long_Float :=
        N.Mul_Within (Long_Float (V), C, 255.0, Max_Multiply_Value);
   begin
      --  Both factors are >= 0, so the product is; the test never acts.
      if P < 0.0 then
         return 0.0;
      end if;
      return P;
   end Product;

   procedure Map_Pixels
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Map    : Table;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      Common.New_Image (Source.Width, Source.Height, Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Result.Pixels'Range (1) loop
         for X in Result.Pixels'Range (2) loop
            Result.Pixels (Y, X) :=
              (if Common.Selected (Region, Whole, X, Y)
               then Map (Source.Pixels (Y, X))
               else Source.Pixels (Y, X));
            pragma Loop_Invariant (Common.Same_Size (Result, Source));
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1 =>
                 (for all I in Result.Pixels'Range (2) =>
                    Result.Pixels (J, I)
                      = (if Common.Selected (Region, Whole, I, J)
                         then Map (Source.Pixels (J, I))
                         else Source.Pixels (J, I))));
            pragma Loop_Invariant
              (for all I in 0 .. X =>
                 Result.Pixels (Y, I)
                   = (if Common.Selected (Region, Whole, I, Y)
                      then Map (Source.Pixels (Y, I))
                      else Source.Pixels (Y, I)));
         end loop;
         pragma Loop_Invariant (Common.Same_Size (Result, Source));
         pragma Loop_Invariant
           (for all J in 0 .. Y =>
              (for all I in Result.Pixels'Range (2) =>
                 Result.Pixels (J, I)
                   = (if Common.Selected (Region, Whole, I, J)
                      then Map (Source.Pixels (J, I))
                      else Source.Pixels (J, I))));
      end loop;
   end Map_Pixels;

   procedure Add_Subtract_Constant
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Add_Subtract_Constant;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Map : constant Table := [for V in Grey_8 => Add_Value (V, Params)];
   begin
      Map_Pixels (Source, Region, Whole, Map, Result, Status);
   end Add_Subtract_Constant;

   procedure Multiply_Constant
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Multiply_Constant;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Map : constant Table :=
        [for V in Grey_8 => Multiply_Value (V, Params)];
   begin
      Map_Pixels (Source, Region, Whole, Map, Result, Status);
   end Multiply_Constant;

   procedure Quantize
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Quantize;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Map : constant Table :=
        [for V in Grey_8 => Quantize_Value (V, Params)];
   begin
      Map_Pixels (Source, Region, Whole, Map, Result, Status);
   end Quantize;

   procedure Threshold
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Threshold;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Map : constant Table :=
        [for V in Grey_8 => Threshold_Value (V, Params)];
   begin
      Map_Pixels (Source, Region, Whole, Map, Result, Status);
   end Threshold;

   ---------------------------------------------------------------------
   --  Equalize
   ---------------------------------------------------------------------

   Count_Limit : constant := 2**40;
   --  A bin stops counting there; a region has fewer than 2**31 pixels,
   --  so the limit never acts.

   type Counts is array (Grey_8) of Int64;

   procedure Count_Selected
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Hist   : out Counts)
   with
     Pre  => Common.Usable (Source),
     Post => (for all V in Grey_8 => Hist (V) in 0 .. Count_Limit);
   --  The histogram of the selected pixels.

   procedure Count_Selected
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Hist   : out Counts) is
   begin
      Hist := [others => 0];
      for Y in Source.Pixels'Range (1) loop
         for X in Source.Pixels'Range (2) loop
            if Common.Selected (Region, Whole, X, Y) then
               declare
                  V : constant Grey_8 := Source.Pixels (Y, X);
               begin
                  if Hist (V) < Count_Limit then
                     Hist (V) := Hist (V) + 1;
                  end if;
               end;
            end if;
            pragma Loop_Invariant
              (for all V in Grey_8 => Hist (V) in 0 .. Count_Limit);
         end loop;
         pragma Loop_Invariant
           (for all V in Grey_8 => Hist (V) in 0 .. Count_Limit);
      end loop;
   end Count_Selected;

   function Equalize_Map (Hist : Counts) return Table
   with Pre => (for all V in Grey_8 => Hist (V) in 0 .. Count_Limit);
   --  The table of Equalize for the histogram Hist (the identity for
   --  fewer than two grey levels).

   function Equalize_Map (Hist : Counts) return Table is
      Total  : Int64 := 0;
      Lowest : Int64 := 0;
      Cdf    : Int64 := 0;
      Map    : Table := KP.Identity_Map;
   begin
      for V in Grey_8 loop
         Total := Total + Hist (V);
         pragma Loop_Invariant
           (Total in 0 .. (Int64 (V) + 1) * Count_Limit);
      end loop;
      for V in Grey_8 loop
         if Hist (V) > 0 then
            Lowest := Hist (V);
            exit;
         end if;
      end loop;
      if Total <= Lowest then
         return Map;
      end if;
      declare
         Span : constant Int64 := Total - Lowest;
      begin
         for V in Grey_8 loop
            Cdf := Cdf + Hist (V);
            Map (V) :=
              Common.Limit_Grey (((Cdf - Lowest) * 510 + Span) / (2 * Span));
            pragma Loop_Invariant
              (Cdf in 0 .. (Int64 (V) + 1) * Count_Limit);
         end loop;
      end;
      return Map;
   end Equalize_Map;

   procedure Equalize
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Hist : Counts;
   begin
      Count_Selected (Source, Region, Whole, Hist);
      Map_Pixels (Source, Region, Whole, Equalize_Map (Hist), Result,
                  Status);
   end Equalize;

   procedure Pel_Set
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Pel_Set;
      Mask   : access constant KI.Ks_Image_8_Grey_Data;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      Common.New_Image (Source.Width, Source.Height, Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Result.Pixels'Range (1) loop
         for X in Result.Pixels'Range (2) loop
            Result.Pixels (Y, X) :=
              Pel_Set_Value (Source, Region, Whole, Params, Mask, X, Y);
            pragma Loop_Invariant (Common.Same_Size (Result, Source));
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1 =>
                 (for all I in Result.Pixels'Range (2) =>
                    Result.Pixels (J, I)
                      = Pel_Set_Value (Source, Region, Whole, Params, Mask,
                                       I, J)));
            pragma Loop_Invariant
              (for all I in 0 .. X =>
                 Result.Pixels (Y, I)
                   = Pel_Set_Value (Source, Region, Whole, Params, Mask,
                                    I, Y));
         end loop;
         pragma Loop_Invariant (Common.Same_Size (Result, Source));
         pragma Loop_Invariant
           (for all J in 0 .. Y =>
              (for all I in Result.Pixels'Range (2) =>
                 Result.Pixels (J, I)
                   = Pel_Set_Value (Source, Region, Whole, Params, Mask,
                                    I, J)));
      end loop;
   end Pel_Set;

end AMV.Kernels.IP_One_Image.Pointwise;
