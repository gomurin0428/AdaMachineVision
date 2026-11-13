pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

package body AMV.Kernels.Blob.Ordering with SPARK_Mode is

   procedure Free is new Ada.Unchecked_Deallocation
     (Int32_Array, Int32_Array_Access);

   ---------------------------------------------------------------------
   --  Filter
   ---------------------------------------------------------------------

   function Passes
     (Item   : Ks_Blob_Result;
      Params : Ks_Blob_Run_Params) return Boolean;
   --  Every run-time measure with Mode = Filter accepts Item.

   function Passes
     (Item   : Ks_Blob_Result;
      Params : Ks_Blob_Run_Params) return Boolean
   is
      Last : constant Int32 :=
        Int32'Max (0, Int32'Min (Params.Run_Time_Measures.Count,
                                 Max_Run_Time_Measures)) - 1;
   begin
      for I in 0 .. Last loop
         declare
            M : Ks_Blob_Measure renames
              Params.Run_Time_Measures.Items (Integer (I));
         begin
            if M.Mode = Measure_Mode_Filter then
               declare
                  Value    : constant Long_Float :=
                    Measure_Value (Item, M.Measure);
                  In_Range : constant Boolean :=
                    Value >= M.Filter_Range_Low
                    and then Value <= M.Filter_Range_High;
               begin
                  if In_Range
                    = (M.Filter_Mode = Filter_Exclude_Blobs_In_Range)
                  then
                     return False;
                  end if;
               end;
            end if;
         end;
      end loop;
      return True;
   end Passes;

   procedure Count_Children (Items : in out Result_Array)
   with Pre => Items'First = 0;
   --  Num_Unfiltered_Children and Num_Children of every item from the
   --  Parent_ID and Filtered_Out of the others.

   procedure Count_Children (Items : in out Result_Array) is
   begin
      for I in Items'Range loop
         Items (I).Num_Children := 0;
         Items (I).Num_Unfiltered_Children := 0;
      end loop;
      for I in Items'Range loop
         declare
            P : constant Int32 := Items (I).Parent_ID;
         begin
            if P >= 0 and then Integer (P) <= Items'Last then
               if Items (Integer (P)).Num_Unfiltered_Children
                    in 0 .. Int32'Last - 1
               then
                  Items (Integer (P)).Num_Unfiltered_Children :=
                    Items (Integer (P)).Num_Unfiltered_Children + 1;
               end if;
               if Items (I).Filtered_Out = False_Value
                 and then Items (Integer (P)).Num_Children
                            in 0 .. Int32'Last - 1
               then
                  Items (Integer (P)).Num_Children :=
                    Items (Integer (P)).Num_Children + 1;
               end if;
            end if;
         end;
      end loop;
   end Count_Children;

   function Count_Passed (Items : Result_Array) return Int32
   with
     Pre  => Items'First = 0 and then Items'Last >= 0
             and then Int64 (Items'Last) < Int64 (Int32'Last),
     Post => Count_Passed'Result >= 0
             and then Int64 (Count_Passed'Result) <= Int64 (Items'Last) + 1;
   --  The number of items with Filtered_Out = 0.

   function Count_Passed (Items : Result_Array) return Int32 is
      Passed : Int32 := 0;
   begin
      for I in Items'Range loop
         pragma Loop_Invariant (Passed in 0 .. Int32 (I));
         if Items (I).Filtered_Out = False_Value then
            Passed := Passed + 1;
         end if;
      end loop;
      return Passed;
   end Count_Passed;

   ---------------------------------------------------------------------
   --  Merge sort (Gold)
   ---------------------------------------------------------------------

   procedure Merge
     (Items     : Result_Array;
      A, Tmp    : in out Int32_Array;
      Lo, Mid   : Integer;
      Hi        : Integer;
      Ascending : Boolean;
      Measure   : Int32)
   with
     Pre  => A'First = Tmp'First and then A'Last = Tmp'Last
             and then Lo >= A'First and then Lo < Mid and then Mid <= Hi
             and then Hi <= A'Last and then Hi < Integer'Last,
     Post => (if Sorted_On (Items, A'Old, Ascending, Measure, Lo, Mid - 1)
                and then Sorted_On (Items, A'Old, Ascending, Measure, Mid, Hi)
              then Sorted_On (Items, A, Ascending, Measure, Lo, Hi))
             and then (for all J in A'Range =>
                         (if J < Lo or else J > Hi then A (J) = A'Old (J)));
   --  Merges the runs A (Lo .. Mid - 1) and A (Mid .. Hi) through Tmp,
   --  taking from the first run on ties (stable).

   procedure Merge
     (Items     : Result_Array;
      A, Tmp    : in out Int32_Array;
      Lo, Mid   : Integer;
      Hi        : Integer;
      Ascending : Boolean;
      Measure   : Int32)
   is
      Halves : constant Boolean :=
        Sorted_On (Items, A, Ascending, Measure, Lo, Mid - 1)
        and then Sorted_On (Items, A, Ascending, Measure, Mid, Hi)
      with Ghost;
      I : Integer := Lo;
      J : Integer := Mid;
   begin
      for P in Lo .. Hi loop
         pragma Loop_Invariant (I in Lo .. Mid and then J in Mid .. Hi + 1);
         pragma Loop_Invariant (P - Lo = (I - Lo) + (J - Mid));
         pragma Loop_Invariant
           (if Halves and then P > Lo
            then Sorted_On (Items, Tmp, Ascending, Measure, Lo, P - 1)
                 and then
                   (if I < Mid
                    then In_Order (Ascending,
                                   Key (Items, Tmp (P - 1), Measure),
                                   Key (Items, A (I), Measure)))
                 and then
                   (if J <= Hi
                    then In_Order (Ascending,
                                   Key (Items, Tmp (P - 1), Measure),
                                   Key (Items, A (J), Measure))));
         if I < Mid
           and then (J > Hi
                     or else In_Order (Ascending, Key (Items, A (I), Measure),
                                       Key (Items, A (J), Measure)))
         then
            Tmp (P) := A (I);
            I := I + 1;
         else
            Tmp (P) := A (J);
            J := J + 1;
         end if;
      end loop;
      pragma Assert
        (if Halves then Sorted_On (Items, Tmp, Ascending, Measure, Lo, Hi));
      A (Lo .. Hi) := Tmp (Lo .. Hi);
   end Merge;

   procedure Merge_Sort
     (Items     : Result_Array;
      A, Tmp    : in out Int32_Array;
      Lo, Hi    : Integer;
      Ascending : Boolean;
      Measure   : Int32)
   with
     Pre  => A'First = Tmp'First and then A'Last = Tmp'Last
             and then Lo >= A'First and then Lo <= Hi
             and then Hi <= A'Last and then Hi < Integer'Last,
     Post => Sorted_On (Items, A, Ascending, Measure, Lo, Hi)
             and then (for all J in A'Range =>
                         (if J < Lo or else J > Hi then A (J) = A'Old (J))),
     Subprogram_Variant => (Decreases => Hi - Lo);
   --  Sorts A (Lo .. Hi) by Measure, stably.

   procedure Merge_Sort
     (Items     : Result_Array;
      A, Tmp    : in out Int32_Array;
      Lo, Hi    : Integer;
      Ascending : Boolean;
      Measure   : Int32)
   is
      Mid : Integer;
   begin
      if Hi = Lo then
         return;
      end if;
      Mid := Lo + (Hi - Lo + 1) / 2;
      Merge_Sort (Items, A, Tmp, Lo, Mid - 1, Ascending, Measure);
      Merge_Sort (Items, A, Tmp, Mid, Hi, Ascending, Measure);
      Merge (Items, A, Tmp, Lo, Mid, Hi, Ascending, Measure);
   end Merge_Sort;

   ---------------------------------------------------------------------
   --  Filter and sort
   ---------------------------------------------------------------------

   procedure Filter_And_Sort
     (Items          : in out Result_Array;
      Params         : Ks_Blob_Run_Params;
      Order          : out Int32_Array_Access;
      Filtered_Count : out Int32;
      Status         : out Ks_Status)
   is
      Passed : Int32;
      Tmp    : Int32_Array_Access;
   begin
      Order := null;
      Filtered_Count := 0;
      for I in Items'Range loop
         Items (I).Filtered_Out :=
           (if Passes (Items (I), Params) then False_Value else True_Value);
      end loop;
      Count_Children (Items);
      Passed := Count_Passed (Items);
      if Passed = 0 then
         Set_Success (Status);
         return;
      end if;

      Allocate_Int32_Array (Natural (Passed) - 1, Order);
      if Order = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Execute: out of memory for the filtered blobs");
         return;
      end if;
      declare
         Next : Natural := 0;
      begin
         for I in Items'Range loop
            pragma Loop_Invariant
              (Order /= null and then Order'First = 0
               and then Order'Last = Integer (Passed) - 1);
            pragma Loop_Invariant (Next <= Order'Last + 1);
            if Items (I).Filtered_Out = False_Value
              and then Next <= Order'Last
            then
               Order (Next) := Int32 (I);
               Next := Next + 1;
            end if;
         end loop;
      end;

      if Params.Sort_Enabled = True_Value and then Order'Last > 0 then
         Allocate_Int32_Array (Order'Last, Tmp);
         if Tmp = null then
            Free (Order);
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Execute: out of memory for sorting the blobs");
            return;
         end if;
         Merge_Sort
           (Items, Order.all, Tmp.all, 0, Order'Last,
            Params.Sort_Ascending = True_Value, Params.Sort_Measure);
         Free (Tmp);
      end if;
      Filtered_Count := Passed;
      Set_Success (Status);
   end Filter_And_Sort;

end AMV.Kernels.Blob.Ordering;
