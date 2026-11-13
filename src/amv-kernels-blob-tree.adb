pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package body AMV.Kernels.Blob.Tree with SPARK_Mode is

   procedure Bad (Status : out Ks_Status; Message : String)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Lemma_Monotone
     (Results  : not null access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      A, B     : Natural)
   with
     Ghost,
     Pre                => A <= B and then B <= Natural (Int32'Last),
     Post               => Matches_Before (Results, Relation, ID, Filtered, A)
                           <= Matches_Before (Results, Relation, ID, Filtered,
                                              B),
     Subprogram_Variant => (Decreases => B - A);
   --  The count of related features never decreases along the collection.

   procedure Lemma_Monotone
     (Results  : not null access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      A, B     : Natural) is
   begin
      if A < B then
         Lemma_Monotone (Results, Relation, ID, Filtered, A, B - 1);
      end if;
   end Lemma_Monotone;

   procedure ID_At
     (List   : access constant Blob_ID_List;
      Index  : Int32;
      ID     : out Int32;
      Status : out Ks_Status) is
   begin
      ID := -1;
      if List = null or else Index not in 0 .. ID_Count (List) - 1 then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "the index is outside the collection");
      else
         ID := Int32 (List (List'First + Integer (Index)));
         Set_Success (Status);
      end if;
   end ID_At;

   procedure Collection_Count
     (Results  : access constant Ks_Blob_Results_Data;
      List     : access constant Blob_ID_List;
      Filtered : Int32;
      Count    : out Int32;
      Status   : out Ks_Status) is
   begin
      if List /= null then
         Count := ID_Count (List);
         Set_Success (Status);
      else
         AMV.Kernels.Blob.Count (Results, Filtered, Count, Status);
      end if;
   end Collection_Count;

   procedure Collection_Item
     (Results  : access constant Ks_Blob_Results_Data;
      List     : access constant Blob_ID_List;
      Filtered : Int32;
      Index    : Int32;
      Result   : out Ks_Blob_Result;
      Status   : out Ks_Status)
   is
      ID : Int32;
   begin
      if List = null then
         AMV.Kernels.Blob.Item (Results, Filtered, Index, Result, Status);
      else
         ID_At (List, Index, ID, Status);
         if Succeeded (Status) then
            Get_Blob_By_ID (Results, ID, Result, Status);
         else
            Result := (others => <>);
         end if;
      end if;
   end Collection_Item;

   procedure Check_Query
     (Results  : not null access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      Status   : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Results (Results)
                            and then Valid_Order (Results)
                            and then Valid_Query (Results, Relation, ID,
                                                  Filtered));
   --  The checks every query of a non-null handle makes first.

   procedure Check_Query
     (Results  : not null access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      Status   : out Ks_Status) is
   begin
      if Relation not in Relation_Code then
         Bad (Status, "the relation must be 0 .. 3 (all, children, siblings,"
                      & " top level)");
         return;
      elsif Filtered not in False_Value | True_Value then
         Bad (Status, "Filtered must be 0 or 1");
         return;
      elsif not Valid_Results (Results) then
         Bad (Status, "the results handle is not valid");
         return;
      elsif Relation in Relation_Children | Relation_Siblings
        and then ID not in 0 .. Results.Count - 1
      then
         Bad (Status, "blobID: no feature has this ID");
         return;
      end if;
      for K in 0 .. Integer (Results.Filtered_Count) - 1 loop
         if Results.Order (K) not in 0 .. Results.Count - 1 then
            Bad (Status, "the results handle is not valid");
            return;
         end if;
         pragma Loop_Invariant
           (for all L in 0 .. K =>
              Results.Order (L) in 0 .. Results.Count - 1);
      end loop;
      Set_Success (Status);
   end Check_Query;

   procedure Count_Matches
     (Results  : not null access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      Count    : out Natural)
   with
     Pre  => Valid_Results (Results),
     Post => Count = Total (Results, Relation, ID, Filtered);
   --  The number of related features.

   procedure Count_Matches
     (Results  : not null access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      Count    : out Natural)
   is
      Length : constant Natural := Base_Length (Results, Filtered);
   begin
      Count := 0;
      for P in 0 .. Length - 1 loop
         if Relates (Results, Relation, ID, Base_ID (Results, Filtered, P))
         then
            Count := Count + 1;
         end if;
         pragma Loop_Invariant
           (Count = Matches_Before (Results, Relation, ID, Filtered, P + 1));
      end loop;
   end Count_Matches;

   procedure Related_Count
     (Results  : access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      Count    : out Int32;
      Status   : out Ks_Status)
   is
      Found : Natural;
   begin
      Count := 0;
      if Results = null then
         if Relation not in Relation_Code then
            Bad (Status, "the relation must be 0 .. 3 (all, children,"
                         & " siblings, top level)");
         elsif Filtered not in False_Value | True_Value then
            Bad (Status, "Filtered must be 0 or 1");
         elsif Relation in Relation_Children | Relation_Siblings then
            Bad (Status, "blobID: no feature has this ID");
         else
            Set_Success (Status);
         end if;
         return;
      end if;
      Check_Query (Results, Relation, ID, Filtered, Status);
      if Succeeded (Status) then
         Count_Matches (Results, Relation, ID, Filtered, Found);
         Count := Int32 (Found);
      end if;
   end Related_Count;

   procedure Related_ID
     (Results  : access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      Index    : Int32;
      Feature  : out Int32;
      Status   : out Ks_Status)
   is
      Count : Int32;
      Seen  : Natural := 0;
   begin
      Feature := -1;
      Related_Count (Results, Relation, ID, Filtered, Count, Status);
      if not Succeeded (Status) then
         return;
      elsif Results = null or else Index not in 0 .. Count - 1 then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "the index is outside the features the query picks");
         return;
      end if;
      for P in 0 .. Base_Length (Results, Filtered) - 1 loop
         if Relates (Results, Relation, ID, Base_ID (Results, Filtered, P))
         then
            if Seen = Natural (Index) then
               Feature := Base_ID (Results, Filtered, P);
               pragma Assert
                 (Relates (Results, Relation, ID,
                           Base_ID (Results, Filtered, P))
                  and then Matches_Before (Results, Relation, ID, Filtered, P)
                           = Natural (Index));
               Set_Success (Status);
               return;
            end if;
            Seen := Seen + 1;
         end if;
         pragma Loop_Invariant
           (Seen = Matches_Before (Results, Relation, ID, Filtered, P + 1));
         pragma Loop_Invariant (Seen <= Natural (Index));
      end loop;
      --  Unreachable: Index is below the number of related features.
      Set_Failure (Status, Failure_Index_Out_Of_Range,
                   "the index is outside the features the query picks");
   end Related_ID;

   procedure Related_IDs
     (Results  : access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      IDs      : out Blob_ID_List;
      Status   : out Ks_Status)
   is
      Count  : Int32;
      Seen   : Natural := 0;
      Length : Natural;
   begin
      IDs := [others => 0];
      Related_Count (Results, Relation, ID, Filtered, Count, Status);
      if not Succeeded (Status) then
         return;
      elsif Int64 (IDs'Length) /= Int64 (Count) then
         Bad (Status, "the array must have one element per feature the"
                      & " query picks");
         return;
      elsif Results = null then
         return;
      end if;
      Length := Base_Length (Results, Filtered);
      for P in 0 .. Length - 1 loop
         if Relates (Results, Relation, ID, Base_ID (Results, Filtered, P))
         then
            Lemma_Monotone (Results, Relation, ID, Filtered, P + 1, Length);
            IDs (IDs'First + Seen) := Integer (Base_ID (Results, Filtered, P));
            Seen := Seen + 1;
         end if;
         pragma Loop_Invariant
           (Seen = Matches_Before (Results, Relation, ID, Filtered, P + 1));
         pragma Loop_Invariant (Int64 (Seen) <= Int64 (IDs'Length));
         pragma Loop_Invariant
           (for all Q in 0 .. P =>
              (if Relates (Results, Relation, ID,
                           Base_ID (Results, Filtered, Q))
               then Matches_Before (Results, Relation, ID, Filtered, Q) < Seen
                    and then IDs (IDs'First
                                  + Matches_Before
                                      (Results, Relation, ID, Filtered, Q))
                             = Integer (Base_ID (Results, Filtered, Q))));
      end loop;
   end Related_IDs;

   procedure Blob_Measure
     (Results : access constant Ks_Blob_Results_Data;
      Measure : Int32;
      ID      : Int32;
      Value   : out Long_Float;
      Status  : out Ks_Status) is
   begin
      Value := 0.0;
      if not Measure_Supported (Measure) then
         Bad (Status, "GetBlobMeasure: the results do not hold this measure");
      elsif Results = null then
         Bad (Status, "GetBlobMeasure: no feature has this ID");
      elsif not Valid_Results (Results) then
         Bad (Status, "GetBlobMeasure: the results handle is not valid");
      elsif ID not in 0 .. Results.Count - 1 then
         Bad (Status, "GetBlobMeasure: no feature has this ID");
      else
         Value := Measure_Value (Results.Items (Integer (ID)), Measure);
         Set_Success (Status);
      end if;
   end Blob_Measure;

   procedure Blob_Measures
     (Results : access constant Ks_Blob_Results_Data;
      Measure : Int32;
      IDs     : Blob_ID_List;
      Values  : out Measure_List;
      Status  : out Ks_Status) is
   begin
      Values := [others => 0.0];
      if not Measure_Supported (Measure) then
         Bad (Status, "GetBlobMeasures: the results do not hold this measure");
         return;
      elsif Values'Length /= IDs'Length then
         Bad (Status, "GetBlobMeasures: the array of values must have one"
                      & " element per ID");
         return;
      elsif IDs'Length = 0 then
         Set_Success (Status);
         return;
      elsif Results = null then
         Bad (Status, "GetBlobMeasures: no feature has this ID");
         return;
      elsif not Valid_Results (Results) then
         Bad (Status, "GetBlobMeasures: the results handle is not valid");
         return;
      end if;
      for K in IDs'Range loop
         if IDs (K) not in 0 .. Integer (Results.Count) - 1 then
            Values := [others => 0.0];
            Bad (Status, "GetBlobMeasures: no feature has this ID");
            return;
         end if;
         Values (Values'First + (K - IDs'First)) :=
           Measure_Value (Results.Items (IDs (K)), Measure);
         pragma Loop_Invariant
           (for all L in IDs'First .. K =>
              IDs (L) in 0 .. Integer (Results.Count) - 1
              and then Values (Values'First + (L - IDs'First))
                       = Measure_Value (Results.Items (IDs (L)), Measure));
      end loop;
      Set_Success (Status);
   end Blob_Measures;

end AMV.Kernels.Blob.Tree;
