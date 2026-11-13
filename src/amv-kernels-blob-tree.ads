--  The feature tree of AMV.Kernels.Blob's results: the counterparts of
--  CogBlobResults.GetChildren, GetSiblings, GetTopLevelBlobs, GetBlobIDs,
--  GetBlobMeasure and GetBlobMeasures (include/amv_blob.h).
--
--  A query picks features by a relation (AMV's definitions):
--  * Relation_All: every feature (GetBlobs, GetBlobIDs);
--  * Relation_Children: the features whose parent is feature ID (the
--    holes of a blob, the blobs inside a hole);
--  * Relation_Siblings: the features other than feature ID whose parent
--    is the parent of feature ID (for a top-level feature, the other
--    top-level features);
--  * Relation_Top_Level: the features without a parent.
--  With Filtered = 1 they are taken from the filtered collection in its
--  order (the order of GetBlobs (True): the sort order with SortEnabled),
--  with Filtered = 0 from every feature in ID order. ID is read only by
--  Children and Siblings, and must then be the ID of a feature, filtered
--  or not (Bad_Parameter otherwise). A null results handle has no
--  features.
--
--  Gold: Related_IDs gives exactly the features that satisfy the relation,
--  each once and in the order of the collection: the position of a
--  feature in the list is the number of related features before it
--  (Matches_Before), and the length of the list is their number;
--  Related_Count gives that number and Related_ID the feature at a
--  position. The measures are the values Get_Measure gives for the
--  features' results.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package AMV.Kernels.Blob.Tree with SPARK_Mode, Preelaborate is

   Relation_All       : constant Int32 := 0;
   Relation_Children  : constant Int32 := 1;
   Relation_Siblings  : constant Int32 := 2;
   Relation_Top_Level : constant Int32 := 3;

   subtype Relation_Code is Int32 range Relation_All .. Relation_Top_Level;

   type Blob_ID_List is array (Natural range <>) of Integer;
   --  A list of feature IDs (Ada only; the C API reads one ID at a time).

   type Measure_List is array (Natural range <>) of Long_Float;
   --  A list of measure values (Ada only).

   function ID_Count (List : access constant Blob_ID_List) return Int32 is
     (if List = null or else List'Last < List'First then 0
      elsif List'Last - List'First >= Natural (Int32'Last) then Int32'Last
      else Int32 (List'Last - List'First + 1));
   --  The number of IDs of a list (0 for null).

   procedure ID_At
     (List   : access constant Blob_ID_List;
      Index  : Int32;
      ID     : out Int32;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then List /= null
                            and then Index in 0 .. ID_Count (List) - 1
                            and then Integer (ID)
                                       = List (List'First + Integer (Index))
                       else ID = -1);
   --  The ID at position Index (0-based) of a list of a collection.
   --  Index_Out_Of_Range unless Index is in 0 .. ID_Count (List) - 1
   --  (always for null).

   procedure Collection_Count
     (Results  : access constant Ks_Blob_Results_Data;
      List     : access constant Blob_ID_List;
      Filtered : Int32;
      Count    : out Int32;
      Status   : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then List /= null
                       then Count = ID_Count (List));
   --  The number of features of a collection of the Ada API: those of
   --  List when it is not null (the list of a query), otherwise those of
   --  GetBlobs (Filtered), as Count gives them (so that GetBlobs needs no
   --  list).

   procedure Collection_Item
     (Results  : access constant Ks_Blob_Results_Data;
      List     : access constant Blob_ID_List;
      Filtered : Int32;
      Index    : Int32;
      Result   : out Ks_Blob_Result;
      Status   : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range;
   --  Item Index (0-based) of that collection: the result of the ID at
   --  Index of List, or Item (Filtered, Index) when List is null.
   --  Index_Out_Of_Range outside the collection.

   function Valid_Order
     (Results : not null access constant Ks_Blob_Results_Data)
      return Boolean
   is
     (for all K in 0 .. Integer (Results.Filtered_Count) - 1 =>
        Results.Order (K) in 0 .. Results.Count - 1)
   with Pre => Valid_Results (Results);
   --  Every ID of the filtered collection is a feature's.

   function Valid_Query
     (Results  : not null access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32) return Boolean
   is
     (Relation in Relation_Code
      and then Filtered in False_Value | True_Value
      and then (if Relation in Relation_Children | Relation_Siblings
                then ID >= 0 and then ID < Results.Count));

   function Base_Length
     (Results  : not null access constant Ks_Blob_Results_Data;
      Filtered : Int32) return Natural
   is
     (if Filtered = True_Value
      then Natural (Int32'Max (0, Results.Filtered_Count))
      else Natural (Int32'Max (0, Results.Count)));
   --  The length of the collection the features are taken from.

   function Base_ID
     (Results  : not null access constant Ks_Blob_Results_Data;
      Filtered : Int32;
      Position : Natural) return Int32
   is
     (if Filtered /= True_Value then Int32 (Position)
      elsif Results.Order /= null and then Position in Results.Order'Range
      then Results.Order (Position)
      else 0)
   with Pre => Position <= Natural (Int32'Last);
   --  The ID at Position in that collection.

   function Relates
     (Results  : not null access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Feature  : Int32) return Boolean
   is
     (Results.Items /= null
      and then Integer (Feature) in Results.Items'Range
      and then
        (case Relation is
            when Relation_All       => True,
            when Relation_Children  =>
               Results.Items (Integer (Feature)).Parent_ID = ID,
            when Relation_Siblings  =>
               Feature /= ID
               and then Integer (ID) in Results.Items'Range
               and then Results.Items (Integer (Feature)).Parent_ID
                          = Results.Items (Integer (ID)).Parent_ID,
            when Relation_Top_Level =>
               Results.Items (Integer (Feature)).Parent_ID = -1,
            when others             => False));
   --  Whether Feature satisfies the relation.

   function Matches_Before
     (Results  : not null access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      Position : Natural) return Natural
   is
     (if Position = 0 then 0
      else Matches_Before (Results, Relation, ID, Filtered, Position - 1)
           + (if Relates (Results, Relation, ID,
                          Base_ID (Results, Filtered, Position - 1))
              then 1 else 0))
   with
     Ghost,
     Pre                => Position <= Natural (Int32'Last),
     Post               => Matches_Before'Result <= Position,
     Subprogram_Variant => (Decreases => Position);
   --  The number of related features at positions 0 .. Position - 1.

   function Total
     (Results  : not null access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32) return Natural
   is
     (Matches_Before (Results, Relation, ID, Filtered,
                      Base_Length (Results, Filtered)))
   with Ghost;
   --  The number of related features.

   procedure Related_Count
     (Results  : access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      Count    : out Int32;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_related_count",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status) and then Results /= null
                then Valid_Results (Results)
                     and then Valid_Order (Results)
                     and then Valid_Query (Results, Relation, ID, Filtered)
                     and then Count
                                = Int32 (Total (Results, Relation, ID,
                                                Filtered))
                else Count = 0);
   --  The number of features the query picks (0 for null results and
   --  Relation_All or Relation_Top_Level). Bad_Parameter for a relation or
   --  flag code out of range, an ID that no feature has (Children and
   --  Siblings; always for null results), or a results handle that is not
   --  valid.

   procedure Related_ID
     (Results  : access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      Index    : Int32;
      Feature  : out Int32;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_related_id",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then
               (if Succeeded (Status)
                then Results /= null
                     and then Valid_Results (Results)
                     and then Valid_Order (Results)
                     and then Valid_Query (Results, Relation, ID, Filtered)
                     and then Feature in 0 .. Results.Count - 1
                     and then
                       (for some P in 0 .. Base_Length (Results, Filtered) - 1
                        => Relates (Results, Relation, ID,
                                    Base_ID (Results, Filtered, P))
                           and then Matches_Before
                                      (Results, Relation, ID, Filtered, P)
                                    = Natural (Index)
                           and then Feature = Base_ID (Results, Filtered, P))
                else Feature = -1);
   --  The ID of the feature at position Index (0-based) of the query's
   --  list. Index_Out_Of_Range unless Index is in 0 .. Count - 1; the
   --  query's failures as for Related_Count.

   procedure Related_IDs
     (Results  : access constant Ks_Blob_Results_Data;
      Relation : Int32;
      ID       : Int32;
      Filtered : Int32;
      IDs      : out Blob_ID_List;
      Status   : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status) and then Results /= null
                then Valid_Results (Results)
                     and then Valid_Order (Results)
                     and then Valid_Query (Results, Relation, ID, Filtered)
                     and then IDs'Length
                                = Total (Results, Relation, ID, Filtered)
                     and then
                       (for all P in 0 .. Base_Length (Results, Filtered) - 1
                        => (if Relates (Results, Relation, ID,
                                        Base_ID (Results, Filtered, P))
                            then IDs (IDs'First
                                      + Matches_Before
                                          (Results, Relation, ID, Filtered,
                                           P))
                                 = Integer (Base_ID (Results, Filtered, P)))));
   --  The IDs the query picks, in its order, into IDs, which must have
   --  Count elements (Bad_Parameter otherwise, after the query's own
   --  checks as for Related_Count).

   procedure Blob_Measure
     (Results : access constant Ks_Blob_Results_Data;
      Measure : Int32;
      ID      : Int32;
      Value   : out Long_Float;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_blob_results_get_blob_measure",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status)
                then Results /= null
                     and then Valid_Results (Results)
                     and then ID in 0 .. Results.Count - 1
                     and then Measure_Supported (Measure)
                     and then Value
                                = Measure_Value
                                    (Results.Items (Integer (ID)), Measure)
                else Value = 0.0);
   --  GetBlobMeasure: the measure of feature ID, filtered or not, as
   --  Get_Measure gives it for its result. Bad_Parameter for a measure the
   --  results do not hold, an ID that no feature has, or a results handle
   --  that is not valid.

   procedure Blob_Measures
     (Results : access constant Ks_Blob_Results_Data;
      Measure : Int32;
      IDs     : Blob_ID_List;
      Values  : out Measure_List;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then
               (if Succeeded (Status)
                then Measure_Supported (Measure)
                     and then Values'Length = IDs'Length
                     and then
                       (IDs'Length = 0
                        or else
                          (Results /= null
                           and then Valid_Results (Results)
                           and then
                             (for all K in IDs'Range =>
                                IDs (K) in 0 .. Integer (Results.Count) - 1
                                and then
                                  Values (Values'First + (K - IDs'First))
                                  = Measure_Value
                                      (Results.Items (IDs (K)), Measure)))));
   --  GetBlobMeasures: the measure of each feature of IDs, into Values,
   --  which must have as many elements (Bad_Parameter otherwise, and for
   --  the failures of Blob_Measure). An empty list gives an empty list,
   --  also for null results.

end AMV.Kernels.Blob.Tree;
