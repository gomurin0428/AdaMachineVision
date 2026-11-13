--  Connectivity for AMV.Kernels.Blob: provisional labels with union-find
--  in one raster pass, the components and their parents, the cleanup,
--  and the final numbering of the features in raster order of their
--  first pixel, with their areas (Gold: the areas of the blobs add up to
--  the number of pixels the feature map gives to blobs, and every feature
--  has at least one pixel).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.Blob.Labelling
  with SPARK_Mode, Preelaborate
is

   type Big is range -2**127 .. 2**127 - 1 with Ghost;
   --  Sums of up to 2**31 values of Int64, for contracts.

   type Feature_Set is record
      Count   : Int32 := 0;
      Map     : Int32_Matrix_Access;
      Kind    : Int32_Array_Access;
      Label   : Int32_Array_Access;
      Parent  : Int32_Array_Access;
      First_X : Int32_Array_Access;
      First_Y : Int32_Array_Access;
      Area    : Int64_Array_Access;
   end record;
   --  The features found: Count of them; the feature map over the
   --  region's bounding rectangle (ID + 1 of the owning feature, 0 for
   --  none); per feature (indexed by ID from 0): Kind (Label_Blob or
   --  Label_Hole: how its pixels are connected), Label (the Label it
   --  reports), Parent (the parent's ID, -1 for none), its first pixel
   --  in raster order, and Area (its number of pixels).

   function Sized
     (List : access constant Int32_Array; Count : Int32) return Boolean
   is
     (if Count = 0 then List = null
      else List /= null and then List'First = 0
           and then Int64 (List'Last) = Int64 (Count) - 1);

   function Sized_64
     (List : access constant Int64_Array; Count : Int32) return Boolean
   is
     (if Count = 0 then List = null
      else List /= null and then List'First = 0
           and then Int64 (List'Last) = Int64 (Count) - 1);

   function Valid_Features (F : Feature_Set; B : Box) return Boolean is
     (F.Count >= 0 and then F.Map /= null
      and then Matrix_On_Box (F.Map.all, B)
      and then Sized (F.Kind, F.Count) and then Sized (F.Label, F.Count)
      and then Sized (F.Parent, F.Count)
      and then Sized (F.First_X, F.Count)
      and then Sized (F.First_Y, F.Count)
      and then Sized_64 (F.Area, F.Count));

   function Is_Null (F : Feature_Set) return Boolean is
     (F.Map = null and then F.Kind = null and then F.Label = null
      and then F.Parent = null and then F.First_X = null
      and then F.First_Y = null and then F.Area = null);

   ---------------------------------------------------------------------
   --  Counting (Gold)
   ---------------------------------------------------------------------

   function Is_Blob_Pixel
     (Map  : Int32_Matrix;
      Kind : Int32_Array;
      Y, X : Natural) return Boolean
   is
     (Map (Y, X) >= 1
      and then Int64 (Map (Y, X)) - 1 >= Int64 (Kind'First)
      and then Int64 (Map (Y, X)) - 1 <= Int64 (Kind'Last)
      and then Kind (Natural (Map (Y, X) - 1)) = Label_Blob)
   with
     Ghost,
     Pre => Y in Map'Range (1) and then X in Map'Range (2);
   --  Pixel (X, Y) belongs to a feature whose pixels are foreground.

   function Row_Count
     (Map  : Int32_Matrix;
      Kind : Int32_Array;
      Y    : Natural;
      X    : Int64) return Int64
   is
     (if X <= Int64 (Map'First (2)) then 0
      else Row_Count (Map, Kind, Y, X - 1)
           + (if Is_Blob_Pixel (Map, Kind, Y, Natural (X - 1)) then 1
              else 0))
   with
     Ghost,
     Pre  => Y in Map'Range (1)
             and then X >= Int64 (Map'First (2))
             and then X <= Int64 (Map'Last (2)) + 1,
     Post => Row_Count'Result in 0 .. X - Int64 (Map'First (2)),
     Subprogram_Variant => (Decreases => X);
   --  The number of blob pixels in row Y left of column X.

   function Rows_Count
     (Map  : Int32_Matrix;
      Kind : Int32_Array;
      Y    : Int64) return Int64
   is
     (if Y <= Int64 (Map'First (1)) then 0
      else Rows_Count (Map, Kind, Y - 1)
           + Row_Count (Map, Kind, Natural (Y - 1),
                        Int64 (Map'Last (2)) + 1))
   with
     Ghost,
     Pre  => Map'First (2) <= Map'Last (2)
             and then Y >= Int64 (Map'First (1))
             and then Y <= Int64 (Map'Last (1)) + 1,
     Post => Rows_Count'Result >= 0
             and then Rows_Count'Result
                        <= (Y - Int64 (Map'First (1))) * 2**31,
     Subprogram_Variant => (Decreases => Y);
   --  The number of blob pixels in the rows above row Y.

   function Blob_Pixel_Count
     (Map  : Int32_Matrix;
      Kind : Int32_Array) return Int64
   is
     (Rows_Count (Map, Kind, Int64 (Map'Last (1)) + 1))
   with
     Ghost,
     Pre => Map'First (1) <= Map'Last (1)
            and then Map'First (2) <= Map'Last (2);
   --  The number of pixels the map gives to blobs: the foreground pixels
   --  after the cleanup.

   function Sum_Blob
     (Area : Int64_Array;
      Kind : Int32_Array;
      N    : Natural) return Big
   is
     (if N = 0 then 0
      else Sum_Blob (Area, Kind, N - 1)
           + (if Kind (N - 1) = Label_Blob then Big (Area (N - 1)) else 0))
   with
     Ghost,
     Pre  => Area'First = 0 and then Kind'First = 0
             and then (N = 0 or else (N - 1 <= Area'Last
                                      and then N - 1 <= Kind'Last)),
     Post => abs Sum_Blob'Result <= Big (N) * 2**63,
     Subprogram_Variant => (Decreases => N);
   --  The sum of the areas of the blobs among the first N features.

   ---------------------------------------------------------------------
   --  Finding the features
   ---------------------------------------------------------------------

   procedure Find_Features
     (S        : U8_Matrix;
      Image    : access constant KI.Ks_Image_8_Grey_Data;
      Params   : Ks_Blob_Run_Params;
      Features : out Feature_Set;
      Status   : out Ks_Status)
   with
     Pre  => S'First (1) <= S'Last (1) and then S'First (2) <= S'Last (2)
             and then (Int64 (S'Last (1)) - Int64 (S'First (1)) + 1)
                      * (Int64 (S'Last (2)) - Int64 (S'First (2)) + 1)
                        <= Max_Region_Pixels
             and then Valid_Connectivity (Params),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Valid_Features
                       (Features,
                        (X_Min => S'First (2), Y_Min => S'First (1),
                         X_Max => S'Last (2), Y_Max => S'Last (1)))
                     and then
                       (if Features.Count > 0
                        then (for all K in Features.Area'Range =>
                                Features.Area (K) >= 1)
                             and then
                               Sum_Blob (Features.Area.all,
                                         Features.Kind.all,
                                         Natural (Features.Count))
                                 = Big (Blob_Pixel_Count
                                          (Features.Map.all,
                                           Features.Kind.all))
                             and then
                               (for all K in Features.First_X'Range =>
                                  Integer (Features.First_Y (K))
                                    in Features.Map'Range (1)
                                  and then Integer (Features.First_X (K))
                                             in Features.Map'Range (2)))
                else Is_Null (Features));
   --  Labels the classified pixels S (Seg_*) by the connectivity mode,
   --  cleans up, numbers the features left and counts their pixels.
   --  Image gives the grey values that tell the blobs of the Labeled mode
   --  apart. Gold: every feature has at least one pixel, and the areas of
   --  the blobs add up to the number of pixels the map gives to blobs.
   --  Out_Of_Memory when a table cannot be allocated.

end AMV.Kernels.Blob.Labelling;
