pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Interfaces;

with AMV.Kernels.Numerics;

package body AMV.Kernels.PM_Align.Masks with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;

   use type Interfaces.Unsigned_8;
   use type PY.Window;

   Count_Limit : constant := 2.0 ** 31;
   --  Above every count of pixels (KM.Max_Pixels is 2**31 - 1).

   function Read
     (Counts : access constant KM.Ks_Real_Image_Data;
      X, Y   : Int64) return Long_Float
   is (N.Clamp (Counts.Pixels (Natural (Y), Natural (X)), Count_Limit))
   with Pre  => KM.Valid_Image (Counts)
                and then X in 0 .. Int64 (Counts.Width) - 1
                and then Y in 0 .. Int64 (Counts.Height) - 1,
        Post => abs Read'Result <= Count_Limit;
   --  Entry (X, Y) of a table, limited to Count_Limit (never acts).

   function Dont_Care
     (Mask     : access constant KI.Ks_Image_8_Grey_Data;
      Offset_X : Int32;
      Offset_Y : Int32;
      X, Y     : Int64) return Boolean
   with Pre => KI.Valid_Image (Mask)
               and then X in 0 .. 2 ** 32 and then Y in 0 .. 2 ** 32;
   --  Train image pixel (X, Y) is covered by a mask pixel of value 0.

   function Dont_Care
     (Mask     : access constant KI.Ks_Image_8_Grey_Data;
      Offset_X : Int32;
      Offset_Y : Int32;
      X, Y     : Int64) return Boolean
   is
      U : constant Int64 := X - Int64 (Offset_X);
      V : constant Int64 := Y - Int64 (Offset_Y);
   begin
      return U >= 0 and then U < Int64 (Mask.Width)
        and then V >= 0 and then V < Int64 (Mask.Height)
        and then Mask.Pixels (Natural (V), Natural (U)) = 0;
   end Dont_Care;

   procedure Build
     (Mask     : access constant KI.Ks_Image_8_Grey_Data;
      Offset_X : Int32;
      Offset_Y : Int32;
      Area     : PY.Window;
      Map      : out Care_Map;
      Status   : out Ks_Status)
   is
      W : constant Int64 := Int64 (Area.Width);
      H : constant Int64 := Int64 (Area.Height);
   begin
      Map := (Counts => null, Area => Area);
      Set_Success (Status);
      if Mask = null then
         return;
      elsif (W + 1) * (H + 1) > KM.Max_Pixels then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "TrainImageMask: the train window is too large for"
                      & " a mask");
         return;
      end if;
      KM.Create (Int32 (W + 1), Int32 (H + 1), 0.0, Map.Counts, Status);
      if not Succeeded (Status) then
         return;
      end if;
      --  Counts (Y + 1, X + 1) = Counts (Y, X + 1) + Counts (Y + 1, X)
      --  - Counts (Y, X) + (1 for a don't-care pixel (X, Y)): a count of
      --  pixels, which the limit never changes.
      for Y in 0 .. H - 1 loop
         pragma Loop_Invariant
           (KM.Valid_Image (Map.Counts)
            and then Int64 (Map.Counts.Width) = W + 1
            and then Int64 (Map.Counts.Height) = H + 1
            and then Map.Area = Area);
         for X in 0 .. W - 1 loop
            pragma Loop_Invariant
              (KM.Valid_Image (Map.Counts)
               and then Int64 (Map.Counts.Width) = W + 1
               and then Int64 (Map.Counts.Height) = H + 1
               and then Map.Area = Area);
            Map.Counts.Pixels (Natural (Y + 1), Natural (X + 1)) :=
              N.Clamp
                (Read (Map.Counts, X + 1, Y) + Read (Map.Counts, X, Y + 1)
                 - Read (Map.Counts, X, Y)
                 + (if Dont_Care (Mask, Offset_X, Offset_Y,
                                  Int64 (Area.X_Min) + X,
                                  Int64 (Area.Y_Min) + Y)
                    then 1.0 else 0.0),
                 Count_Limit);
         end loop;
      end loop;
   end Build;

   function Cared
     (Map   : Care_Map;
      Level : Level_Index;
      I, J  : Natural) return Boolean
   is
      Size : constant Int64 :=
        (case Level is
            when 0 => 1, when 1 => 2, when 2 => 4, when 3 => 8,
            when 4 => 16, when 5 => 32);
      Reach : constant Int64 := Size + 1;
      CX    : constant Int64 := Int64 (I) * Size + Size / 2;
      CY    : constant Int64 := Int64 (J) * Size + Size / 2;
      X0, X1, Y0, Y1 : Int64;
   begin
      if Map.Counts = null then
         return True;
      end if;
      X0 := Int64'Max (0, CX - Reach);
      X1 := Int64'Min (Int64 (Map.Counts.Width) - 2, CX + Reach);
      Y0 := Int64'Max (0, CY - Reach);
      Y1 := Int64'Min (Int64 (Map.Counts.Height) - 2, CY + Reach);
      if X0 > X1 or else Y0 > Y1 then
         return True;
      end if;
      --  The don't-care pixels of columns X0 .. X1 and rows Y0 .. Y1.
      return Read (Map.Counts, X1 + 1, Y1 + 1) - Read (Map.Counts, X0, Y1 + 1)
             - Read (Map.Counts, X1 + 1, Y0) + Read (Map.Counts, X0, Y0)
             < 0.5;
   end Cared;

   procedure Release (Map : in out Care_Map) is
      S : Ks_Status;
   begin
      KM.Destroy (Map.Counts, S);
      pragma Unreferenced (S);
   end Release;

end AMV.Kernels.PM_Align.Masks;
