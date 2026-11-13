--  Filtering and sorting for AMV.Kernels.Blob: the filter of the
--  run-time measures, the counts of children, and the filtered collection
--  in ID order or sorted by a measure (Gold: sorted when sorting is
--  enabled; a stable merge sort).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.Blob.Ordering
  with SPARK_Mode, Preelaborate
is

   pragma Unevaluated_Use_Of_Old (Allow);

   function Key
     (Items   : Result_Array;
      ID      : Int32;
      Measure : Int32) return Long_Float
   is
     (if Integer (ID) in Items'Range
      then Measure_Value (Items (Integer (ID)), Measure)
      else 0.0);
   --  The value of Measure for the feature ID (0.0 for an ID out of
   --  range).

   function Sorted_On
     (Items     : Result_Array;
      Order     : Int32_Array;
      Ascending : Boolean;
      Measure   : Int32;
      Lo, Hi    : Integer) return Boolean
   is
     (for all J in Lo .. Hi - 1 =>
        In_Order (Ascending, Key (Items, Order (J), Measure),
                  Key (Items, Order (J + 1), Measure)))
   with Pre => Lo >= 0 and then Lo >= Order'First
               and then Hi <= Order'Last and then Hi >= Lo - 1;
   --  Order (Lo .. Hi) lists features in the order of Measure.

   procedure Filter_And_Sort
     (Items          : in out Result_Array;
      Params         : Ks_Blob_Run_Params;
      Order          : out Int32_Array_Access;
      Filtered_Count : out Int32;
      Status         : out Ks_Status)
   with
     Pre  => Items'First = 0 and then Items'Last >= 0
             and then Int64 (Items'Last) < Int64 (Int32'Last),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Filtered_Count >= 0
                     and then Int64 (Filtered_Count)
                                <= Int64 (Items'Last) + 1
                     and then
                       (if Filtered_Count = 0 then Order = null
                        else Order /= null and then Order'First = 0
                             and then Order'Last
                                        = Integer (Filtered_Count) - 1
                             and then
                               (if Params.Sort_Enabled = True_Value
                                then Sorted_On
                                       (Items, Order.all,
                                        Params.Sort_Ascending = True_Value,
                                        Params.Sort_Measure, 0,
                                        Order'Last)))
                else Order = null);
   --  Sets Filtered_Out of every item by the filter of the run-time
   --  measures (Mode = Filter), counts the children of every item
   --  (Num_Unfiltered_Children, and Num_Children for those that passed),
   --  then lists the IDs that passed in Order: in ID order, or stably
   --  sorted by SortMeasure when SortEnabled (Gold). Out_Of_Memory when
   --  the list cannot be allocated.

end AMV.Kernels.Blob.Ordering;
