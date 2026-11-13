pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Deallocation;

with AMV.Kernels.Filter_Inputs;
with AMV.Kernels.IP_One_Image.Common;
with AMV.Kernels.IP_One_Image.Convolution;
with AMV.Kernels.IP_One_Image.Flip_Rotate;
with AMV.Kernels.IP_One_Image.Median;
with AMV.Kernels.IP_One_Image.Morphology;
with AMV.Kernels.IP_One_Image.Pointwise;
with AMV.Kernels.IP_One_Image.Sampling;
with AMV.Kernels.IP_One_Image.Smoothing;

package body AMV.Kernels.IP_One_Image with SPARK_Mode is

   package FI renames AMV.Kernels.Filter_Inputs;
   package CV renames AMV.Kernels.IP_One_Image.Convolution;
   package FR renames AMV.Kernels.IP_One_Image.Flip_Rotate;
   package ME renames AMV.Kernels.IP_One_Image.Median;
   package MO renames AMV.Kernels.IP_One_Image.Morphology;
   package PW renames AMV.Kernels.IP_One_Image.Pointwise;
   package SA renames AMV.Kernels.IP_One_Image.Sampling;
   package SM renames AMV.Kernels.IP_One_Image.Smoothing;

   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Grey_8_Matrix, KI.Grey_8_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Ks_Image_8_Grey_Data, KI.Ks_Image_8_Grey);

   subtype Short_Text is String
     with Dynamic_Predicate =>
       Short_Text'First = 1 and then Short_Text'Length <= 80;
   --  A part of a message.

   procedure Bad
     (Status  : out Ks_Status;
      Message : String)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad
     (Status  : out Ks_Status;
      Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Index_Fault
     (Status    : out Ks_Status;
      Operation : Short_Text;
      Index     : Int32;
      Last      : Short_Text)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Index_Out_Of_Range;
   --  "Operation: index I is outside 0 .. Last".

   procedure Index_Fault
     (Status    : out Ks_Status;
      Operation : Short_Text;
      Index     : Int32;
      Last      : Short_Text) is
   begin
      Set_Failure (Status, Failure_Index_Out_Of_Range,
                   Operation & ": index " & FI.Image_Of (Int64 (Index))
                   & " is outside 0 .. " & Last);
   end Index_Fault;

   Count_Message : constant String := "Operators.Count must be in 0 .. 16";

   ---------------------------------------------------------------------
   --  Checks of an operator
   ---------------------------------------------------------------------

   type Fault is
     (No_Fault, Bad_Kind, Bad_Enabled, Bad_Overflow_Mode, Bad_Kernel_Origin,
      Bad_Convolve_Width, Bad_Convolve_Height, Clipped_Mode,
      Bad_Boundary_Mode, Bad_Kernel_Value, Bad_Operation_In_Pixel_Space,
      Bad_Smoothness_X, Bad_Smoothness_Y, Bad_Magnitude_Shift,
      Bad_Operation, Bad_Kernel_Width, Bad_Kernel_Height,
      Bad_Multiply_Value, Bad_Levels, Bad_Threshold, Bad_Low_Value,
      Bad_High_Value, Bad_Amount, Bad_Sample_X, Bad_Sample_Y,
      Bad_Expansion_X, Bad_Expansion_Y, Bad_Processing_Mode,
      Bad_Spatial_Average, Bad_Pel_Set_Operation, Bad_Pel_Value);

   function Kernel_Value_OK (V : Long_Float) return Boolean is
     (V >= -Max_Kernel_Value and then V <= Max_Kernel_Value);
   --  Finite and within the bound (False for a NaN).

   function Values_3x3_OK (Kernel : Convolve_3x3_Kernel) return Boolean is
     (for all I in Kernel'Range => Kernel_Value_OK (Kernel (I)));

   function Values_NxM_OK (Params : Ks_IP_One_Image_Convolve_NxM)
      return Boolean
   with Pre => Params.Kernel_Width in 1 .. Max_Convolve_Size
               and then Params.Kernel_Height in 1 .. Max_Convolve_Size;
   --  The values of the cells the kernel's size uses.

   function Values_NxM_OK (Params : Ks_IP_One_Image_Convolve_NxM)
      return Boolean is
   begin
      for Row in 0 .. Natural (Params.Kernel_Height) - 1 loop
         for Col in 0 .. Natural (Params.Kernel_Width) - 1 loop
            if not Kernel_Value_OK
                     (Params.Kernel (Row * Max_Convolve_Size + Col))
            then
               return False;
            end if;
         end loop;
      end loop;
      return True;
   end Values_NxM_OK;

   function Fault_Of (Op : Ks_IP_One_Image_Operator) return Fault
   with Post => (if Fault_Of'Result = No_Fault then Valid_Operator (Op));
   --  The first check the operator fails (No_Fault when none).

   function Fault_Of (Op : Ks_IP_One_Image_Operator) return Fault is
   begin
      if Op.Kind not in Operator_Kind then
         return Bad_Kind;
      elsif Op.Enabled not in False_Value | True_Value then
         return Bad_Enabled;
      end if;
      case Op.Kind is
         when Kind_Add_Subtract_Constant =>
            if Op.Add_Subtract_Constant.Overflow_Mode
                 not in Overflow_Mode_Bounded | Overflow_Mode_Wrap
            then
               return Bad_Overflow_Mode;
            end if;
         when Kind_Convolve_3x3 =>
            if Op.Convolve_3x3.Kernel_Origin
                 not in Position_North_West .. Position_South_East
            then
               return Bad_Kernel_Origin;
            elsif not Values_3x3_OK (Op.Convolve_3x3.Kernel) then
               return Bad_Kernel_Value;
            end if;
         when Kind_Convolve_NxM =>
            if not Odd_Size (Op.Convolve_NxM.Kernel_Width, Max_Convolve_Size)
            then
               return Bad_Convolve_Width;
            elsif not Odd_Size (Op.Convolve_NxM.Kernel_Height,
                                Max_Convolve_Size)
            then
               return Bad_Convolve_Height;
            elsif Op.Convolve_NxM.Boundary_Mode = Boundary_Mode_Clipped then
               return Clipped_Mode;
            elsif Op.Convolve_NxM.Boundary_Mode /= Boundary_Mode_Reflected
            then
               return Bad_Boundary_Mode;
            elsif not Values_NxM_OK (Op.Convolve_NxM) then
               return Bad_Kernel_Value;
            end if;
         when Kind_Equalize | Kind_Median_3x3 | Kind_Pixel_Map =>
            null;
         when Kind_Flip_Rotate =>
            if Op.Flip_Rotate.Operation_In_Pixel_Space
                 not in Flip_Rotate_Code
            then
               return Bad_Operation_In_Pixel_Space;
            end if;
         when Kind_Gauss_Sampler =>
            if Op.Gauss_Sampler.Smoothness_X not in 0 .. Max_Smoothness then
               return Bad_Smoothness_X;
            elsif Op.Gauss_Sampler.Smoothness_Y not in 0 .. Max_Smoothness
            then
               return Bad_Smoothness_Y;
            elsif Op.Gauss_Sampler.Magnitude_Shift
                    not in -Max_Magnitude_Shift .. Max_Magnitude_Shift
            then
               return Bad_Magnitude_Shift;
            elsif Op.Gauss_Sampler.Sample_X not in 1 .. Max_Sample then
               return Bad_Sample_X;
            elsif Op.Gauss_Sampler.Sample_Y not in 1 .. Max_Sample then
               return Bad_Sample_Y;
            end if;
         when Kind_Grey_Morphology_NxM =>
            if Op.Grey_Morphology_NxM.Operation not in Morphology_Code then
               return Bad_Operation;
            elsif not Odd_Size (Op.Grey_Morphology_NxM.Kernel_Width,
                                Max_Kernel_Size)
            then
               return Bad_Kernel_Width;
            elsif not Odd_Size (Op.Grey_Morphology_NxM.Kernel_Height,
                                Max_Kernel_Size)
            then
               return Bad_Kernel_Height;
            end if;
         when Kind_Median_NxM =>
            if not Odd_Size (Op.Median_NxM.Kernel_Width, Max_Kernel_Size) then
               return Bad_Kernel_Width;
            elsif not Odd_Size (Op.Median_NxM.Kernel_Height, Max_Kernel_Size)
            then
               return Bad_Kernel_Height;
            end if;
         when Kind_Multiply_Constant =>
            if not (Op.Multiply_Constant.Constant_Value >= 0.0
                    and then Op.Multiply_Constant.Constant_Value
                               <= Max_Multiply_Value)
            then
               return Bad_Multiply_Value;
            elsif Op.Multiply_Constant.Overflow_Mode
                    not in Overflow_Mode_Bounded | Overflow_Mode_Wrap
            then
               return Bad_Overflow_Mode;
            end if;
         when Kind_Quantize =>
            if Op.Quantize.Levels
                 not in Quantize_Level_S2 .. Quantize_Level_S128
            then
               return Bad_Levels;
            end if;
         when Kind_Box_Filter =>
            if not Odd_Size (Op.Box_Filter.Kernel_Width, Max_Kernel_Size) then
               return Bad_Kernel_Width;
            elsif not Odd_Size (Op.Box_Filter.Kernel_Height, Max_Kernel_Size)
            then
               return Bad_Kernel_Height;
            end if;
         when Kind_Threshold =>
            if Op.Threshold.Threshold not in 0 .. 256 then
               return Bad_Threshold;
            elsif Op.Threshold.Low_Value not in 0 .. 255 then
               return Bad_Low_Value;
            elsif Op.Threshold.High_Value not in 0 .. 255 then
               return Bad_High_Value;
            end if;
         when Kind_Unsharp_Mask =>
            if not (Op.Unsharp_Mask.Amount >= 0.0
                    and then Op.Unsharp_Mask.Amount <= Max_Amount)
            then
               return Bad_Amount;
            elsif Op.Unsharp_Mask.Smoothness_X not in 0 .. Max_Smoothness then
               return Bad_Smoothness_X;
            elsif Op.Unsharp_Mask.Smoothness_Y not in 0 .. Max_Smoothness then
               return Bad_Smoothness_Y;
            end if;
         when Kind_Expand =>
            if Op.Expand.Expansion_X not in 1 .. Max_Sample then
               return Bad_Expansion_X;
            elsif Op.Expand.Expansion_Y not in 1 .. Max_Sample then
               return Bad_Expansion_Y;
            end if;
         when Kind_High_Pass_Filter =>
            if Op.High_Pass_Filter.Processing_Mode
                 not in High_Pass_Gauss .. High_Pass_Median
            then
               return Bad_Processing_Mode;
            elsif Op.High_Pass_Filter.Smoothness_X not in 0 .. Max_Smoothness
            then
               return Bad_Smoothness_X;
            elsif Op.High_Pass_Filter.Smoothness_Y not in 0 .. Max_Smoothness
            then
               return Bad_Smoothness_Y;
            elsif not Odd_Size (Op.High_Pass_Filter.Kernel_Width,
                                Max_Kernel_Size)
            then
               return Bad_Kernel_Width;
            elsif not Odd_Size (Op.High_Pass_Filter.Kernel_Height,
                                Max_Kernel_Size)
            then
               return Bad_Kernel_Height;
            end if;
         when Kind_Sub_Sampler =>
            if Op.Sub_Sampler.Sample_X not in 1 .. Max_Sample then
               return Bad_Sample_X;
            elsif Op.Sub_Sampler.Sample_Y not in 1 .. Max_Sample then
               return Bad_Sample_Y;
            elsif Op.Sub_Sampler.Spatial_Average
                    not in False_Value | True_Value
            then
               return Bad_Spatial_Average;
            end if;
         when Kind_Pel_Set =>
            if Op.Pel_Set.Operation
                 not in Pel_Set_Care_Pels | Pel_Set_Dont_Care_Pels
            then
               return Bad_Pel_Set_Operation;
            elsif Op.Pel_Set.Pel_Value not in 0 .. 255 then
               return Bad_Pel_Value;
            end if;
         when others =>
            return Bad_Kind;
      end case;
      return No_Fault;
   end Fault_Of;

   function Fault_Text (F : Fault) return Short_Text is
     (case F is
         when No_Fault          => "",
         when Bad_Kind          => "Kind is not a known operator kind",
         when Bad_Enabled       => "Enabled must be 0 or 1",
         when Bad_Overflow_Mode =>
           "OverflowMode must be Bounded (0) or Wrap (1)",
         when Bad_Kernel_Origin =>
           "KernelOrigin must be a position code in 0 .. 8",
         when Bad_Convolve_Width =>
           "KernelWidth must be an odd number in 1 .. 15",
         when Bad_Convolve_Height =>
           "KernelHeight must be an odd number in 1 .. 15",
         when Clipped_Mode      =>
           "BoundaryMode Clipped is not supported (use Reflected)",
         when Bad_Boundary_Mode =>
           "BoundaryMode must be Clipped (1) or Reflected (2)",
         when Bad_Kernel_Value  =>
           "kernel values must be finite and within +/-1.0E6",
         when Bad_Operation_In_Pixel_Space =>
           "OperationInPixelSpace must be in 0 .. 7",
         when Bad_Smoothness_X  => "SmoothnessX must be in 0 .. 24",
         when Bad_Smoothness_Y  => "SmoothnessY must be in 0 .. 24",
         when Bad_Magnitude_Shift => "MagnitudeShift must be in -7 .. 7",
         when Bad_Operation     => "Operation must be in 1 .. 7",
         when Bad_Kernel_Width  =>
           "KernelWidth must be an odd number in 1 .. 1001",
         when Bad_Kernel_Height =>
           "KernelHeight must be an odd number in 1 .. 1001",
         when Bad_Multiply_Value =>
           "ConstantValue must be finite, >= 0 and <= 1.0E6",
         when Bad_Levels        => "Levels must be in 0 .. 6",
         when Bad_Threshold     => "Threshold must be in 0 .. 256",
         when Bad_Low_Value     => "LowValue must be in 0 .. 255",
         when Bad_High_Value    => "HighValue must be in 0 .. 255",
         when Bad_Amount        =>
           "Amount must be finite, >= 0 and <= 1000",
         when Bad_Sample_X      => "SampleX must be in 1 .. 256",
         when Bad_Sample_Y      => "SampleY must be in 1 .. 256",
         when Bad_Expansion_X   => "ExpansionX must be in 1 .. 256",
         when Bad_Expansion_Y   => "ExpansionY must be in 1 .. 256",
         when Bad_Processing_Mode =>
           "ProcessingMode must be Gauss (0), Mean (1) or Median (2)",
         when Bad_Spatial_Average => "SpatialAverage must be 0 or 1",
         when Bad_Pel_Set_Operation =>
           "Operation must be SetCarePels (1) or SetDontCarePels (2)",
         when Bad_Pel_Value     => "PelValue must be in 0 .. 255");

   ---------------------------------------------------------------------
   --  Entry points: operators and the operator list
   ---------------------------------------------------------------------

   procedure Operators_Default (Operators : out Ks_IP_One_Image_Operators)
   is
   begin
      Operators := (Count => 0, Items => [others => (others => <>)]);
   end Operators_Default;

   procedure Operator_Default
     (Kind     : Int32;
      Operator : out Ks_IP_One_Image_Operator;
      Status   : out Ks_Status) is
   begin
      Operator := (others => <>);
      if Kind not in Operator_Kind then
         Bad (Status, "Kind " & FI.Image_Of (Int64 (Kind))
                      & " is not a known operator kind");
         return;
      end if;
      Operator.Kind := Kind;
      Set_Success (Status);
   end Operator_Default;

   procedure Operators_Item
     (Operators : Ks_IP_One_Image_Operators;
      Index     : Int32;
      Operator  : out Ks_IP_One_Image_Operator;
      Status    : out Ks_Status) is
   begin
      Operator := (others => <>);
      if Operators.Count not in 0 .. Max_Operators then
         Bad (Status, Count_Message);
      elsif Index not in 0 .. Operators.Count - 1 then
         Index_Fault (Status, "Item", Index, "Count - 1");
      else
         Operator := Operators.Items (Integer (Index));
         Set_Success (Status);
      end if;
   end Operators_Item;

   procedure Operators_Count
     (Operators : Ks_IP_One_Image_Operators;
      Count     : out Int32;
      Status    : out Ks_Status) is
   begin
      Count := 0;
      if Operators.Count not in 0 .. Max_Operators then
         Bad (Status, Count_Message);
      else
         Count := Operators.Count;
         Set_Success (Status);
      end if;
   end Operators_Count;

   procedure Operator_Get_Kind
     (Operator : Ks_IP_One_Image_Operator;
      Kind     : out Int32;
      Status   : out Ks_Status) is
   begin
      Kind := Kind_Add_Subtract_Constant;
      if Operator.Kind not in Operator_Kind then
         Bad (Status, "Operator.Kind must be an operator kind code (0 .. 18)");
      else
         Kind := Operator.Kind;
         Set_Success (Status);
      end if;
   end Operator_Get_Kind;

   procedure Operator_Get_Enabled
     (Operator : Ks_IP_One_Image_Operator;
      Enabled  : out Int32;
      Status   : out Ks_Status) is
   begin
      Enabled := False_Value;
      if Operator.Enabled not in False_Value | True_Value then
         Bad (Status, "Operator.Enabled must be 0 or 1");
      else
         Enabled := Operator.Enabled;
         Set_Success (Status);
      end if;
   end Operator_Get_Enabled;

   procedure Operators_Set_Item
     (Operators : in out Ks_IP_One_Image_Operators;
      Index     : Int32;
      Operator  : Ks_IP_One_Image_Operator;
      Status    : out Ks_Status) is
   begin
      if Operators.Count not in 0 .. Max_Operators then
         Bad (Status, Count_Message);
      elsif Index not in 0 .. Operators.Count - 1 then
         Index_Fault (Status, "Item", Index, "Count - 1");
      else
         Operators.Items (Integer (Index)) := Operator;
         Set_Success (Status);
      end if;
   end Operators_Set_Item;

   procedure Operators_Add
     (Operators : in out Ks_IP_One_Image_Operators;
      Operator  : Ks_IP_One_Image_Operator;
      Status    : out Ks_Status) is
   begin
      if Operators.Count not in 0 .. Max_Operators then
         Bad (Status, Count_Message);
      elsif Operators.Count = Max_Operators then
         Bad (Status, "Add: the operator list is full (16 operators)");
      else
         Operators.Items (Integer (Operators.Count)) := Operator;
         Operators.Count := Operators.Count + 1;
         Set_Success (Status);
      end if;
   end Operators_Add;

   procedure Operators_Insert
     (Operators : in out Ks_IP_One_Image_Operators;
      Operator  : Ks_IP_One_Image_Operator;
      Index     : Int32;
      Status    : out Ks_Status) is
   begin
      if Operators.Count not in 0 .. Max_Operators then
         Bad (Status, Count_Message);
         return;
      elsif Operators.Count = Max_Operators then
         Bad (Status, "Insert: the operator list is full (16 operators)");
         return;
      elsif Index not in 0 .. Operators.Count then
         Index_Fault (Status, "Insert", Index, "Count");
         return;
      end if;
      declare
         Last : constant Natural := Natural (Operators.Count);
         Old  : constant Operator_Array := Operators.Items with Ghost;
      begin
         for J in reverse Natural (Index) + 1 .. Last loop
            Operators.Items (J) := Operators.Items (J - 1);
            pragma Loop_Invariant
              (Operators.Count = Operators.Count'Loop_Entry);
            pragma Loop_Invariant
              (for all K in 0 .. J - 1 => Operators.Items (K) = Old (K));
            pragma Loop_Invariant
              (for all K in J .. Last => Operators.Items (K) = Old (K - 1));
         end loop;
      end;
      Operators.Items (Integer (Index)) := Operator;
      Operators.Count := Operators.Count + 1;
      Set_Success (Status);
   end Operators_Insert;

   procedure Operators_Remove_At
     (Operators : in out Ks_IP_One_Image_Operators;
      Index     : Int32;
      Status    : out Ks_Status) is
   begin
      if Operators.Count not in 0 .. Max_Operators then
         Bad (Status, Count_Message);
         return;
      elsif Index not in 0 .. Operators.Count - 1 then
         Index_Fault (Status, "RemoveAt", Index, "Count - 1");
         return;
      end if;
      declare
         Old : constant Operator_Array := Operators.Items with Ghost;
      begin
         for J in Natural (Index) .. Natural (Operators.Count) - 2 loop
            Operators.Items (J) := Operators.Items (J + 1);
            pragma Loop_Invariant
              (Operators.Count = Operators.Count'Loop_Entry);
            pragma Loop_Invariant
              (for all K in 0 .. Natural (Index) - 1 =>
                 Operators.Items (K) = Old (K));
            pragma Loop_Invariant
              (for all K in Natural (Index) .. J =>
                 Operators.Items (K) = Old (K + 1));
            pragma Loop_Invariant
              (for all K in J + 1 .. Operator_Array'Last =>
                 Operators.Items (K) = Old (K));
         end loop;
      end;
      Operators.Count := Operators.Count - 1;
      Set_Success (Status);
   end Operators_Remove_At;

   procedure Operators_Move
     (Operators  : in out Ks_IP_One_Image_Operators;
      From_Index : Int32;
      To_Index   : Int32;
      Status     : out Ks_Status) is
   begin
      if Operators.Count not in 0 .. Max_Operators then
         Bad (Status, Count_Message);
         return;
      elsif From_Index not in 0 .. Operators.Count - 1 then
         Index_Fault (Status, "Move", From_Index, "Count - 1");
         return;
      elsif To_Index not in 0 .. Operators.Count - 1 then
         Index_Fault (Status, "Move", To_Index, "Count - 1");
         return;
      end if;
      declare
         Moved : constant Ks_IP_One_Image_Operator :=
           Operators.Items (Integer (From_Index));
      begin
         if From_Index < To_Index then
            for J in Natural (From_Index) .. Natural (To_Index) - 1 loop
               Operators.Items (J) := Operators.Items (J + 1);
               pragma Loop_Invariant
                 (Operators.Count = Operators.Count'Loop_Entry);
            end loop;
         else
            for J in reverse Natural (To_Index) + 1 .. Natural (From_Index)
            loop
               Operators.Items (J) := Operators.Items (J - 1);
               pragma Loop_Invariant
                 (Operators.Count = Operators.Count'Loop_Entry);
            end loop;
         end if;
         Operators.Items (Integer (To_Index)) := Moved;
      end;
      Set_Success (Status);
   end Operators_Move;

   procedure Convolve_NxM_Get_Kernel_Value
     (Params : Ks_IP_One_Image_Convolve_NxM;
      Col    : Int32;
      Row    : Int32;
      Value  : out Long_Float;
      Status : out Ks_Status) is
   begin
      Value := 0.0;
      if Params.Kernel_Width not in 1 .. Max_Convolve_Size
        or else Col not in 0 .. Params.Kernel_Width - 1
      then
         Bad (Status, "GetKernelValue: Col must be in 0 .. KernelWidth - 1"
                      & " (KernelWidth in 1 .. 15)");
      elsif Params.Kernel_Height not in 1 .. Max_Convolve_Size
        or else Row not in 0 .. Params.Kernel_Height - 1
      then
         Bad (Status, "GetKernelValue: Row must be in 0 .. KernelHeight - 1"
                      & " (KernelHeight in 1 .. 15)");
      else
         Value :=
           Params.Kernel (Integer (Row) * Max_Convolve_Size + Integer (Col));
         Set_Success (Status);
      end if;
   end Convolve_NxM_Get_Kernel_Value;

   procedure Convolve_NxM_Set_Kernel_Value
     (Params    : in out Ks_IP_One_Image_Convolve_NxM;
      Col       : Int32;
      Row       : Int32;
      New_Value : Long_Float;
      Status    : out Ks_Status) is
   begin
      if Params.Kernel_Width not in 1 .. Max_Convolve_Size
        or else Col not in 0 .. Params.Kernel_Width - 1
      then
         Bad (Status, "SetKernelValue: Col must be in 0 .. KernelWidth - 1"
                      & " (KernelWidth in 1 .. 15)");
      elsif Params.Kernel_Height not in 1 .. Max_Convolve_Size
        or else Row not in 0 .. Params.Kernel_Height - 1
      then
         Bad (Status, "SetKernelValue: Row must be in 0 .. KernelHeight - 1"
                      & " (KernelHeight in 1 .. 15)");
      elsif not Kernel_Value_OK (New_Value) then
         Bad (Status, "SetKernelValue: NewValue must be finite and within"
                      & " +/-1.0E6");
      else
         Params.Kernel (Integer (Row) * Max_Convolve_Size + Integer (Col)) :=
           New_Value;
         Set_Success (Status);
      end if;
   end Convolve_NxM_Set_Kernel_Value;

   procedure Convolve_3x3_Get_Kernel_Value
     (Params   : Ks_IP_One_Image_Convolve_3x3;
      Position : Int32;
      Value    : out Long_Float;
      Status   : out Ks_Status) is
   begin
      Value := 0.0;
      if Position not in 0 .. 8 then
         Bad (Status, "GetKernelValue: position must be a code in 0 .. 8");
      else
         Value := Params.Kernel (Integer (Position));
         Set_Success (Status);
      end if;
   end Convolve_3x3_Get_Kernel_Value;

   procedure Convolve_3x3_Set_Kernel_Value
     (Params   : in out Ks_IP_One_Image_Convolve_3x3;
      Position : Int32;
      Value    : Long_Float;
      Status   : out Ks_Status) is
   begin
      if Position not in 0 .. 8 then
         Bad (Status, "SetKernelValue: position must be a code in 0 .. 8");
      elsif not Kernel_Value_OK (Value) then
         Bad (Status, "SetKernelValue: value must be finite and within"
                      & " +/-1.0E6");
      else
         Params.Kernel (Integer (Position)) := Value;
         Set_Success (Status);
      end if;
   end Convolve_3x3_Set_Kernel_Value;

   function Sigma (Smoothness : Int32) return Long_Float is
   begin
      if Smoothness not in 0 .. Max_Smoothness then
         return 0.0;
      end if;
      declare
         Half : constant Long_Float range 0.0 .. 12.0 :=
           Long_Float (Smoothness) / 2.0;
         Root : constant Long_Float :=
           Ada.Numerics.Long_Elementary_Functions.Sqrt (Half);
      begin
         return Long_Float'Max (0.0, Long_Float'Min (Root, 4.0));
      end;
   end Sigma;

   procedure Check_Operators
     (Operators : Ks_IP_One_Image_Operators;
      Status    : out Ks_Status) is
   begin
      if Operators.Count not in 0 .. Max_Operators then
         Bad (Status, Count_Message);
         return;
      end if;
      for I in 0 .. Integer (Operators.Count) - 1 loop
         declare
            F : constant Fault := Fault_Of (Operators.Items (I));
         begin
            if F /= No_Fault then
               Bad (Status, "Operators(" & FI.Image_Of (Int64 (I)) & ")."
                            & Fault_Text (F));
               return;
            end if;
         end;
         pragma Loop_Invariant
           (for all J in 0 .. I => Valid_Operator (Operators.Items (J)));
      end loop;
      Set_Success (Status);
   end Check_Operators;

   ---------------------------------------------------------------------
   --  Running
   ---------------------------------------------------------------------

   function Grid_Kind (Kind : Int32) return Boolean is
     (Kind in Kind_Flip_Rotate | Kind_Gauss_Sampler | Kind_Expand
            | Kind_Sub_Sampler);
   --  The kinds that can change the pixel grid (Is_Geometric).

   procedure Apply_Pixels
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Op     : Ks_IP_One_Image_Operator;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Valid_Operator (Op)
             and then Op.Enabled = True_Value
             and then not Grid_Kind (Op.Kind)
             and then Op.Kind /= Kind_Pel_Set,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             (if not Common.Selected (Region, Whole, X, Y)
                              then Result.Pixels (Y, X)
                                     = Source.Pixels (Y, X))))
                else Result = null);
   --  One operator that keeps the pixel grid.

   procedure Apply_Pixels
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Op     : Ks_IP_One_Image_Operator;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      case Op.Kind is
         when Kind_Add_Subtract_Constant =>
            PW.Add_Subtract_Constant
              (Source, Region, Whole, Op.Add_Subtract_Constant, Result,
               Status);
         when Kind_Convolve_3x3 =>
            CV.Convolve
              (Source, Region, Whole, CV.From_3x3 (Op.Convolve_3x3.Kernel),
               (Width    => 3,
                Height   => 3,
                Origin_X => Op.Convolve_3x3.Kernel_Origin mod 3,
                Origin_Y => Op.Convolve_3x3.Kernel_Origin / 3),
               Result, Status);
         when Kind_Convolve_NxM =>
            CV.Convolve
              (Source, Region, Whole, CV.To_Bounded (Op.Convolve_NxM.Kernel),
               (Width    => Op.Convolve_NxM.Kernel_Width,
                Height   => Op.Convolve_NxM.Kernel_Height,
                Origin_X => (Op.Convolve_NxM.Kernel_Width - 1) / 2,
                Origin_Y => (Op.Convolve_NxM.Kernel_Height - 1) / 2),
               Result, Status);
         when Kind_Equalize =>
            PW.Equalize (Source, Region, Whole, Result, Status);
         when Kind_Grey_Morphology_NxM =>
            MO.Grey_Morphology
              (Source, Region, Whole, Op.Grey_Morphology_NxM, Result,
               Status);
         when Kind_Median_3x3 =>
            ME.Median_Filter (Source, Region, Whole, 3, 3, Result, Status);
         when Kind_Median_NxM =>
            ME.Median_Filter
              (Source, Region, Whole, Op.Median_NxM.Kernel_Width,
               Op.Median_NxM.Kernel_Height, Result, Status);
         when Kind_Multiply_Constant =>
            PW.Multiply_Constant
              (Source, Region, Whole, Op.Multiply_Constant, Result, Status);
         when Kind_Pixel_Map =>
            PW.Map_Pixels
              (Source, Region, Whole, Op.Pixel_Map.Map, Result, Status);
         when Kind_Quantize =>
            PW.Quantize (Source, Region, Whole, Op.Quantize, Result, Status);
         when Kind_Box_Filter =>
            SM.Box_Filter
              (Source, Region, Whole, Op.Box_Filter, Result, Status);
         when Kind_Threshold =>
            PW.Threshold
              (Source, Region, Whole, Op.Threshold, Result, Status);
         when Kind_Unsharp_Mask =>
            SM.Unsharp_Mask
              (Source, Region, Whole, Op.Unsharp_Mask, Result, Status);
         when Kind_High_Pass_Filter =>
            SM.High_Pass_Filter
              (Source, Region, Whole, Op.High_Pass_Filter, Result, Status);
         when others =>
            --  Excluded by the precondition.
            Result := null;
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "IPOneImage: unknown operator kind");
      end case;
   end Apply_Pixels;

   procedure Apply_Flip_Rotate
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Op     : Ks_IP_One_Image_Operator;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Valid_Operator (Op)
             and then Op.Enabled = True_Value
             and then Op.Kind = Kind_Flip_Rotate,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Usable (Result)
                     and then Size_Of (Result)
                                = Step_Size (Op, Size_Of (Source))
                     and then
                       (if not Is_Geometric (Op)
                        then
                          (for all Y in Result.Pixels'Range (1) =>
                             (for all X in Result.Pixels'Range (2) =>
                                Result.Pixels (Y, X) = Source.Pixels (Y, X))))
                else Result = null);
   --  FlipRotate (None copies the image).

   procedure Apply_Flip_Rotate
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Op     : Ks_IP_One_Image_Operator;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Code : constant Flip_Rotate_Code :=
        Op.Flip_Rotate.Operation_In_Pixel_Space;
   begin
      pragma Assert (Transposes (Op) = FR.Swapping (Code));
      FR.Apply (Source, Code, Result, Status);
      pragma Assert
        (if Succeeded (Status)
         then Int64 (Result.Width) * Int64 (Result.Height)
                = Int64 (Source.Width) * Int64 (Source.Height));
   end Apply_Flip_Rotate;

   procedure Apply_Gauss_Sampler
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Op     : Ks_IP_One_Image_Operator;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Valid_Operator (Op)
             and then Op.Enabled = True_Value
             and then Op.Kind = Kind_Gauss_Sampler,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Usable (Result)
                     and then Size_Of (Result)
                                = Step_Size (Op, Size_Of (Source))
                     and then
                       (if not Is_Geometric (Op)
                        then
                          (for all Y in Result.Pixels'Range (1) =>
                             (for all X in Result.Pixels'Range (2) =>
                                (if not Common.Selected (Region, Whole, X, Y)
                                 then Result.Pixels (Y, X)
                                        = Source.Pixels (Y, X)))))
                else Result = null);
   --  GaussSampler, then its sampling (when SampleX or SampleY is above
   --  1).

   procedure Apply_Gauss_Sampler
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Op     : Ks_IP_One_Image_Operator;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Smoothed : KI.Ks_Image_8_Grey;
   begin
      if Op.Gauss_Sampler.Sample_X = 1 and then Op.Gauss_Sampler.Sample_Y = 1
      then
         SM.Gauss_Sampler
           (Source, Region, Whole, Op.Gauss_Sampler, Result, Status);
         pragma Assert
           (Step_Size (Op, Size_Of (Source)) = Size_Of (Source));
         return;
      end if;
      SM.Gauss_Sampler
        (Source, Region, Whole, Op.Gauss_Sampler, Smoothed, Status);
      if not Succeeded (Status) then
         Result := null;
         return;
      end if;
      pragma Assert (Size_Of (Smoothed) = Size_Of (Source));
      SA.Sub_Sample
        (Smoothed, Op.Gauss_Sampler.Sample_X, Op.Gauss_Sampler.Sample_Y,
         False, Result, Status);
      Free (Smoothed.Pixels);
      Free (Smoothed);
   end Apply_Gauss_Sampler;

   procedure Copy_Image
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Usable (Result)
                     and then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X) = Source.Pixels (Y, X)))
                else Result = null);
   --  A copy of the image (a sampling or an expansion by 1 x 1).

   procedure Copy_Image
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      KI.Duplicate (Source, Result, Status);
      if not Succeeded (Status) then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "IPOneImage: not enough memory for an image");
      end if;
   end Copy_Image;

   procedure Apply_Expand
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Op     : Ks_IP_One_Image_Operator;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Valid_Operator (Op)
             and then Op.Enabled = True_Value
             and then Op.Kind = Kind_Expand
             and then Fits (Step_Size (Op, Size_Of (Source))),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Usable (Result)
                     and then Size_Of (Result)
                                = Step_Size (Op, Size_Of (Source))
                     and then
                       (if not Is_Geometric (Op)
                        then
                          (for all Y in Result.Pixels'Range (1) =>
                             (for all X in Result.Pixels'Range (2) =>
                                Result.Pixels (Y, X) = Source.Pixels (Y, X))))
                else Result = null);
   --  Expand (1 x 1 copies the image).

   procedure Apply_Expand
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Op     : Ks_IP_One_Image_Operator;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      if Is_Geometric (Op) then
         SA.Expand (Source, Op.Expand.Expansion_X, Op.Expand.Expansion_Y,
                    Result, Status);
      else
         Copy_Image (Source, Result, Status);
      end if;
   end Apply_Expand;

   procedure Apply_Sub_Sampler
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Op     : Ks_IP_One_Image_Operator;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Valid_Operator (Op)
             and then Op.Enabled = True_Value
             and then Op.Kind = Kind_Sub_Sampler,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Usable (Result)
                     and then Size_Of (Result)
                                = Step_Size (Op, Size_Of (Source))
                     and then
                       (if not Is_Geometric (Op)
                        then
                          (for all Y in Result.Pixels'Range (1) =>
                             (for all X in Result.Pixels'Range (2) =>
                                Result.Pixels (Y, X) = Source.Pixels (Y, X))))
                else Result = null);
   --  SubSampler (1 x 1 copies the image: a block of one pixel is that
   --  pixel).

   procedure Apply_Sub_Sampler
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Op     : Ks_IP_One_Image_Operator;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      if Is_Geometric (Op) then
         SA.Sub_Sample
           (Source, Op.Sub_Sampler.Sample_X, Op.Sub_Sampler.Sample_Y,
            Op.Sub_Sampler.Spatial_Average = True_Value, Result, Status);
      else
         Copy_Image (Source, Result, Status);
      end if;
   end Apply_Sub_Sampler;

   procedure Apply
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Op     : Ks_IP_One_Image_Operator;
      Mask   : access constant KI.Ks_Image_8_Grey_Data;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Valid_Operator (Op)
             and then Op.Enabled = True_Value
             and then Fits (Step_Size (Op, Size_Of (Source)))
             and then (if Needs_Mask (Op) then KI.Valid_Image (Mask)),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Usable (Result)
                     and then Size_Of (Result)
                                = Step_Size (Op, Size_Of (Source))
                     and then
                       (if not Is_Geometric (Op)
                        then
                          (for all Y in Result.Pixels'Range (1) =>
                             (for all X in Result.Pixels'Range (2) =>
                                (if not Common.Selected (Region, Whole, X, Y)
                                 then Result.Pixels (Y, X)
                                        = Source.Pixels (Y, X)))))
                else Result = null);
   --  One operator.

   procedure Apply
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Op     : Ks_IP_One_Image_Operator;
      Mask   : access constant KI.Ks_Image_8_Grey_Data;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      case Op.Kind is
         when Kind_Pel_Set =>
            PW.Pel_Set (Source, Region, Whole, Op.Pel_Set, Mask, Result,
                        Status);
            pragma Assert
              (Step_Size (Op, Size_Of (Source)) = Size_Of (Source)
               and then not Is_Geometric (Op));
         when Kind_Flip_Rotate =>
            Apply_Flip_Rotate (Source, Op, Result, Status);
         when Kind_Gauss_Sampler =>
            Apply_Gauss_Sampler (Source, Region, Whole, Op, Result, Status);
         when Kind_Expand =>
            Apply_Expand (Source, Op, Result, Status);
         when Kind_Sub_Sampler =>
            Apply_Sub_Sampler (Source, Op, Result, Status);
         when others =>
            Apply_Pixels (Source, Region, Whole, Op, Result, Status);
            pragma Assert
              (Step_Size (Op, Size_Of (Source)) = Size_Of (Source)
               and then not Is_Geometric (Op));
      end case;
   end Apply;

   function Covers
     (Region        : access constant KR.Ks_Pixel_Region_Data;
      Width, Height : Int32) return Boolean
   is
     (Region /= null and then Region.Flags = null
      and then Region.X_Min = 0 and then Region.Y_Min = 0
      and then Region.Width >= Width and then Region.Height >= Height);
   --  The region contains every pixel of a Width x Height image.

   Map_Limit : constant := 1.0E100;
   --  The entries of a Grid_Map stay within this bound (the limit never
   --  acts: at most Max_Operators factors of at most Max_Sample, and
   --  translations of at most an image's size each).

   subtype Map_Value is Long_Float range -Map_Limit .. Map_Limit;

   type Grid_Map is record
      Swap   : Boolean := False;
      SX, SY : Map_Value := 1.0;
      TX, TY : Map_Value := 0.0;
   end record;
   --  The map from input to output pixel coordinates of the operators
   --  run so far: without Swap, (x, y) goes to (SX x + TX, SY y + TY);
   --  with Swap, to (SX y + TX, SY x + TY). The default is the identity.

   Identity_Map : constant Grid_Map := (others => <>);

   function Limited_Value (V : Long_Float) return Map_Value is
     (Long_Float'Max (-Map_Limit, Long_Float'Min (V, Map_Limit)));

   subtype Factor_Value is Long_Float range -256.0 .. 256.0;
   subtype Offset_Value is Long_Float range -1.0E12 .. 1.0E12;

   function Then_Step
     (Map    : Grid_Map;
      Swap   : Boolean;
      FX, FY : Factor_Value;
      CX, CY : Offset_Value) return Grid_Map
   is
     (if Swap
      then (Swap => not Map.Swap,
            SX   => Limited_Value (FX * Map.SY),
            SY   => Limited_Value (FY * Map.SX),
            TX   => Limited_Value (FX * Map.TY + CX),
            TY   => Limited_Value (FY * Map.TX + CY))
      else (Swap => Map.Swap,
            SX   => Limited_Value (FX * Map.SX),
            SY   => Limited_Value (FY * Map.SY),
            TX   => Limited_Value (FX * Map.TX + CX),
            TY   => Limited_Value (FY * Map.TY + CY)));
   --  Map, then the step (x, y) -> (FX x + CX, FY y + CY), or (FX y +
   --  CX, FY x + CY) with Swap.

   function Sign (Flip : Boolean) return Factor_Value is
     (if Flip then -1.0 else 1.0);

   function Reduction (Factor : Int32) return Factor_Value is
     (1.0 / Long_Float (Factor))
   with Pre => Factor in 1 .. Max_Sample;

   function Block_Offset (Factor : Int32) return Offset_Value is
     (Long_Float (Factor - 1) / 2.0)
   with Pre => Factor in 1 .. Max_Sample;
   --  The centre of a block of Factor pixels, from its first pixel.

   function Step_Map
     (Map  : Grid_Map;
      Op   : Ks_IP_One_Image_Operator;
      W, H : Int32) return Grid_Map
   with
     Pre => Valid_Operator (Op) and then Is_Geometric (Op)
            and then W >= 1 and then H >= 1;
   --  Map, then the map of Op on a W x H image.

   function Step_Map
     (Map  : Grid_Map;
      Op   : Ks_IP_One_Image_Operator;
      W, H : Int32) return Grid_Map is
   begin
      case Op.Kind is
         when Kind_Flip_Rotate =>
            declare
               G : constant FR.Grid_Map :=
                 FR.Step_Map (Op.Flip_Rotate.Operation_In_Pixel_Space, W, H);
            begin
               return Then_Step
                 (Map, G.Swap, Sign (G.Flip_X), Sign (G.Flip_Y),
                  Long_Float (G.TX), Long_Float (G.TY));
            end;
         when Kind_Gauss_Sampler =>
            return Then_Step
              (Map, False, Reduction (Op.Gauss_Sampler.Sample_X),
               Reduction (Op.Gauss_Sampler.Sample_Y), 0.0, 0.0);
         when Kind_Expand =>
            return Then_Step
              (Map, False, Long_Float (Op.Expand.Expansion_X),
               Long_Float (Op.Expand.Expansion_Y),
               Block_Offset (Op.Expand.Expansion_X),
               Block_Offset (Op.Expand.Expansion_Y));
         when Kind_Sub_Sampler =>
            if Op.Sub_Sampler.Spatial_Average = True_Value then
               return Then_Step
                 (Map, False, Reduction (Op.Sub_Sampler.Sample_X),
                  Reduction (Op.Sub_Sampler.Sample_Y),
                  -(Block_Offset (Op.Sub_Sampler.Sample_X)
                    * Reduction (Op.Sub_Sampler.Sample_X)),
                  -(Block_Offset (Op.Sub_Sampler.Sample_Y)
                    * Reduction (Op.Sub_Sampler.Sample_Y)));
            else
               return Then_Step
                 (Map, False, Reduction (Op.Sub_Sampler.Sample_X),
                  Reduction (Op.Sub_Sampler.Sample_Y), 0.0, 0.0);
            end if;
         when others =>
            return Map;
      end case;
   end Step_Map;

   function To_Transform (Map : Grid_Map) return KT.Ks_Transform_2D_Linear
   is
     (if Map.Swap
      then (A             => 0.0,
            B             => Map.SX,
            C             => Map.SY,
            D             => 0.0,
            Translation_X => Map.TX,
            Translation_Y => Map.TY)
      else (A             => Map.SX,
            B             => 0.0,
            C             => 0.0,
            D             => Map.SY,
            Translation_X => Map.TX,
            Translation_Y => Map.TY))
   with
     Post => KT.Bounded (To_Transform'Result)
             and then (if Map = Identity_Map
                       then To_Transform'Result
                              = KT.Ks_Transform_2D_Linear'(others => <>));
   --  The transform of the map.

   procedure Check_Sizes
     (Image     : access constant KI.Ks_Image_8_Grey_Data;
      Operators : Ks_IP_One_Image_Operators;
      Status    : out Ks_Status)
   with
     Pre  => KI.Valid_Image (Image) and then Valid_Operators (Operators),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status)
                then (for all N in 1 .. Operators.Count =>
                        Fits (Size_After (Operators, N, Size_Of (Image)))));
   --  Every image of the list within Max_Pixels pixels: Bad_Parameter
   --  naming the first operator that makes a larger one.

   procedure Check_Sizes
     (Image     : access constant KI.Ks_Image_8_Grey_Data;
      Operators : Ks_IP_One_Image_Operators;
      Status    : out Ks_Status)
   is
      S : Image_Size := Size_Of (Image);
   begin
      for I in 0 .. Integer (Operators.Count) - 1 loop
         S := Step_Size (Operators.Items (I), S);
         pragma Assert
           (S = Size_After (Operators, Int32 (I) + 1, Size_Of (Image)));
         if not Fits (S) then
            Bad (Status, "Operators(" & FI.Image_Of (Int64 (I)) & ") makes"
                         & " an image of more than 2147483647 pixels");
            return;
         end if;
         pragma Loop_Invariant
           (S = Size_After (Operators, Int32 (I) + 1, Size_Of (Image)));
         pragma Loop_Invariant
           (for all N in 1 .. Int32 (I) + 1 =>
              Fits (Size_After (Operators, N, Size_Of (Image))));
      end loop;
      Set_Success (Status);
   end Check_Sizes;

   function Mask_Of
     (Masks : access constant Operator_Masks;
      I     : Natural) return Mask_Ref
   is
     (if Masks = null then null else Masks (I))
   with Pre => I <= Max_Operators - 1;
   --  The mask of the operator at index I (null without masks).

   procedure Check_Masks
     (Operators : Ks_IP_One_Image_Operators;
      Masks     : access constant Operator_Masks;
      Status    : out Ks_Status)
   with
     Pre  => Valid_Operators (Operators),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status)
                then (for all I in 0 .. Integer (Operators.Count) - 1 =>
                        (if Needs_Mask (Operators.Items (I))
                         then KI.Valid_Image (Mask_Of (Masks, I)))));
   --  Every enabled PelSet has a valid mask: Bad_Parameter naming the
   --  first that has none.

   procedure Check_Masks
     (Operators : Ks_IP_One_Image_Operators;
      Masks     : access constant Operator_Masks;
      Status    : out Ks_Status) is
   begin
      for I in 0 .. Integer (Operators.Count) - 1 loop
         if Needs_Mask (Operators.Items (I))
           and then not KI.Valid_Image (Mask_Of (Masks, I))
         then
            Bad (Status, "Operators(" & FI.Image_Of (Int64 (I))
                         & ").InputImageMask is not set");
            return;
         end if;
         pragma Loop_Invariant
           (for all J in 0 .. I =>
              (if Needs_Mask (Operators.Items (J))
               then KI.Valid_Image (Mask_Of (Masks, J))));
      end loop;
      Set_Success (Status);
   end Check_Masks;

   procedure Execute_Masked
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Region            : access constant KR.Ks_Pixel_Region_Data;
      Operators         : Ks_IP_One_Image_Operators;
      Masks             : access constant Operator_Masks;
      Output            : out KI.Ks_Image_8_Grey;
      Output_From_Input : out KT.Ks_Transform_2D_Linear;
      Status            : out Ks_Status)
   is
      Current : KI.Ks_Image_8_Grey;
      Next    : KI.Ks_Image_8_Grey;
      Whole   : Boolean;
      Map     : Grid_Map := Identity_Map;
   begin
      Output := null;
      Output_From_Input := (others => <>);
      FI.Check_Input (Image, Region, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Operators (Operators, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Masks (Operators, Masks, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Whole := Has_Geometric (Operators);
      if Whole and then not Covers (Region, Image.Width, Image.Height) then
         Bad (Status, "Region must contain the whole image (an empty"
                      & " Region) when Operators holds an operator that"
                      & " changes the pixel grid");
         return;
      end if;
      Check_Sizes (Image, Operators, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KI.Duplicate (Image, Current, Status);
      if not Succeeded (Status) then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "IPOneImage: not enough memory for an image");
         return;
      end if;
      for I in 0 .. Integer (Operators.Count) - 1 loop
         if Operators.Items (I).Enabled = True_Value then
            pragma Assert
              (Size_After (Operators, Int32 (I) + 1, Size_Of (Image))
                 = Step_Size (Operators.Items (I),
                              Size_After (Operators, Int32 (I),
                                          Size_Of (Image))));
            pragma Assert
              (Fits (Size_After (Operators, Int32 (I) + 1, Size_Of (Image))));
            pragma Assert
              (Fits (Step_Size (Operators.Items (I), Size_Of (Current))));
            Apply (Current, Region, Whole, Operators.Items (I),
                   Mask_Of (Masks, I), Next, Status);
            if not Succeeded (Status) then
               Free (Current.Pixels);
               Free (Current);
               return;
            end if;
            if Is_Geometric (Operators.Items (I)) then
               Map := Step_Map
                 (Map, Operators.Items (I), Current.Width, Current.Height);
            end if;
            pragma Assert
              (if not Whole
               then (for all Y in Next.Pixels'Range (1) =>
                       (for all X in Next.Pixels'Range (2) =>
                          (if not KR.Contains (Region, Int32 (X), Int32 (Y))
                           then Next.Pixels (Y, X) = Image.Pixels (Y, X)))));
            Free (Current.Pixels);
            Free (Current);
            Current := Next;
            Next := null;
         end if;
         pragma Loop_Invariant (Next = null);
         pragma Loop_Invariant (Common.Usable (Current));
         pragma Loop_Invariant
           (Size_Of (Current)
              = Size_After (Operators, Int32 (I) + 1, Size_Of (Image)));
         pragma Loop_Invariant
           (for all N in 1 .. Operators.Count =>
              Fits (Size_After (Operators, N, Size_Of (Image))));
         pragma Loop_Invariant
           (for all J in 0 .. Integer (Operators.Count) - 1 =>
              (if Needs_Mask (Operators.Items (J))
               then KI.Valid_Image (Mask_Of (Masks, J))));
         pragma Loop_Invariant
           (if not Whole
            then Size_Of (Current) = Size_Of (Image)
                 and then Map = Identity_Map
                 and then
                   (for all Y in Current.Pixels'Range (1) =>
                      (for all X in Current.Pixels'Range (2) =>
                         (if not KR.Contains (Region, Int32 (X), Int32 (Y))
                          then Current.Pixels (Y, X)
                                 = Image.Pixels (Y, X)))));
      end loop;
      Output := Current;
      Output_From_Input := To_Transform (Map);
      Set_Success (Status);
   end Execute_Masked;

   procedure Execute
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Region            : access constant KR.Ks_Pixel_Region_Data;
      Operators         : Ks_IP_One_Image_Operators;
      Output            : out KI.Ks_Image_8_Grey;
      Output_From_Input : out KT.Ks_Transform_2D_Linear;
      Status            : out Ks_Status) is
   begin
      Execute_Masked (Image, Region, Operators, null, Output,
                      Output_From_Input, Status);
   end Execute;

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      FI.Check_Image (Image, Status);
   end Check_Input_Image;

end AMV.Kernels.IP_One_Image;
