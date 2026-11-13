pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

package body AMV.Kernels.Blob.Labelling with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);

   subtype Grey_8 is Interfaces.Unsigned_8;

   procedure Free is new Ada.Unchecked_Deallocation
     (Int32_Matrix, Int32_Matrix_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Int32_Array, Int32_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Int64_Array, Int64_Array_Access);

   Max_Area_Count : constant := 2**31;
   --  A component never has more pixels than the region (at most
   --  2**31 - 3); the counting stops here so that the sums stay small.

   ---------------------------------------------------------------------
   --  Reads that are safe for any argument
   ---------------------------------------------------------------------

   function Pixel_At
     (Image : access constant KI.Ks_Image_8_Grey_Data;
      Y, X  : Int64) return Grey_8
   is
     (if Image /= null and then Image.Pixels /= null
        and then Y in Int64 (Image.Pixels'First (1))
                   .. Int64 (Image.Pixels'Last (1))
        and then X in Int64 (Image.Pixels'First (2))
                   .. Int64 (Image.Pixels'Last (2))
      then Image.Pixels (Natural (Y), Natural (X))
      else 0);
   --  The grey value of pixel (X, Y), 0 outside the image.

   function Class_At (S : U8_Matrix; Y, X : Int64) return Grey_8 is
     (if Y in Int64 (S'First (1)) .. Int64 (S'Last (1))
        and then X in Int64 (S'First (2)) .. Int64 (S'Last (2))
      then S (Natural (Y), Natural (X))
      else Seg_Outside);
   --  The class of pixel (X, Y), outside beyond the rectangle.

   function Label_At (L : Int32_Matrix; Y, X : Int64) return Int32 is
     (if Y in Int64 (L'First (1)) .. Int64 (L'Last (1))
        and then X in Int64 (L'First (2)) .. Int64 (L'Last (2))
      then L (Natural (Y), Natural (X))
      else 0);
   --  The provisional label of pixel (X, Y), 0 beyond the rectangle.

   ---------------------------------------------------------------------
   --  Union-find over the provisional labels
   ---------------------------------------------------------------------

   --  EP (Label) is the label's parent in its equivalence tree, always a
   --  smaller label (a root is its own parent); the root of a class is
   --  its smallest label. The searches below follow the parents while
   --  they decrease, so they end even for a table that broke that rule.

   procedure Find
     (EP    : in out Int32_Array;
      Label : Int32;
      Root  : out Int32)
   with
     Pre  => EP'First = 0 and then Label >= 1
             and then Int64 (Label) <= Int64 (EP'Last),
     Post => Root in 1 .. Label;
   --  The root of Label's class, with path compression.

   procedure Find
     (EP    : in out Int32_Array;
      Label : Int32;
      Root  : out Int32)
   is
      Current : Int32 := Label;
   begin
      for Step in 1 .. Label loop
         pragma Loop_Invariant (Current in 1 .. Label);
         declare
            Parent : constant Int32 := EP (Natural (Current));
         begin
            exit when Parent >= Current or else Parent < 1;
            Current := Parent;
         end;
      end loop;
      Root := Current;
      Current := Label;
      for Step in 1 .. Label loop
         pragma Loop_Invariant (Current in 1 .. Label);
         exit when Current <= Root;
         declare
            Parent : constant Int32 := EP (Natural (Current));
         begin
            EP (Natural (Current)) := Root;
            exit when Parent >= Current or else Parent < 1;
            Current := Parent;
         end;
      end loop;
   end Find;

   procedure Union
     (EP   : in out Int32_Array;
      A, B : Int32;
      Root : out Int32)
   with
     Pre  => EP'First = 0 and then A >= 1 and then B >= 1
             and then Int64 (A) <= Int64 (EP'Last)
             and then Int64 (B) <= Int64 (EP'Last),
     Post => Root >= 1 and then Root <= Int32'Max (A, B);
   --  Joins the classes of A and B under the smaller root, which it
   --  returns.

   procedure Union
     (EP   : in out Int32_Array;
      A, B : Int32;
      Root : out Int32)
   is
      Root_A : Int32;
      Root_B : Int32;
   begin
      Find (EP, A, Root_A);
      Find (EP, B, Root_B);
      if Root_A < Root_B then
         EP (Natural (Root_B)) := Root_A;
         Root := Root_A;
      elsif Root_B < Root_A then
         EP (Natural (Root_A)) := Root_B;
         Root := Root_B;
      else
         Root := Root_A;
      end if;
   end Union;

   function Label_Tables (EP, Up, Kind, Value : Int32_Array) return Boolean
   is
     (EP'First = 0 and then Up'First = 0 and then Kind'First = 0
      and then Value'First = 0 and then Up'Last = EP'Last
      and then Kind'Last = EP'Last and then Value'Last = EP'Last
      and then EP'Last >= 1 and then Int64 (EP'Last) < Int64 (Int32'Last));
   --  The tables of the provisional labels 0 .. EP'Last: the parent, the
   --  label above the first pixel, the kind and the label value.

   procedure Join
     (S          : U8_Matrix;
      L          : Int32_Matrix;
      Image      : access constant KI.Ks_Image_8_Grey_Data;
      EP         : in out Int32_Array;
      Class      : Grey_8;
      Same_Value : Boolean;
      Value      : Grey_8;
      NY, NX     : Int64;
      Next       : Int32;
      Label      : in out Int32)
   with
     Pre  => EP'First = 0 and then Class /= Seg_Outside
             and then Next >= 2
             and then Int64 (Next) <= Int64 (EP'Last) + 1
             and then Label in 0 .. Next - 1,
     Post => Label in 0 .. Next - 1;
   --  When the neighbour (NX, NY) has the class Class (and, with
   --  Same_Value, the grey value Value) and a label, Label joins its class
   --  (or takes its label when Label is 0).

   procedure Join
     (S          : U8_Matrix;
      L          : Int32_Matrix;
      Image      : access constant KI.Ks_Image_8_Grey_Data;
      EP         : in out Int32_Array;
      Class      : Grey_8;
      Same_Value : Boolean;
      Value      : Grey_8;
      NY, NX     : Int64;
      Next       : Int32;
      Label      : in out Int32)
   is
   begin
      if Class_At (S, NY, NX) = Class
        and then (not Same_Value or else Pixel_At (Image, NY, NX) = Value)
      then
         declare
            Neighbour : constant Int32 := Label_At (L, NY, NX);
            Root      : Int32;
         begin
            if Neighbour >= 1 and then Neighbour < Next then
               if Label = 0 then
                  Label := Neighbour;
               elsif Label /= Neighbour then
                  Union (EP, Label, Neighbour, Root);
                  Label := Root;
               end if;
            end if;
         end;
      end if;
   end Join;

   procedure New_Label
     (EP, Up, Kind, Value : in out Int32_Array;
      Next                : in out Int32;
      Of_Kind, Of_Value   : Int32;
      Above               : Int32;
      Label               : out Int32;
      Ok                  : out Boolean)
   with
     Pre  => Label_Tables (EP, Up, Kind, Value)
             and then Next >= 2
             and then Int64 (Next) <= Int64 (EP'Last) + 1,
     Post => Next >= 2 and then Int64 (Next) <= Int64 (EP'Last) + 1
             and then Next >= Next'Old
             and then Label in 0 .. Next - 1
             and then (if Ok then Label >= 1);
   --  A new label (a root) with these properties; Ok is False when the
   --  tables are full (which the size of the tables rules out).

   procedure New_Label
     (EP, Up, Kind, Value : in out Int32_Array;
      Next                : in out Int32;
      Of_Kind, Of_Value   : Int32;
      Above               : Int32;
      Label               : out Int32;
      Ok                  : out Boolean)
   is
   begin
      if Int64 (Next) > Int64 (EP'Last) then
         Label := 0;
         Ok := False;
         return;
      end if;
      Label := Next;
      EP (Natural (Next)) := Next;
      Up (Natural (Next)) := Above;
      Kind (Natural (Next)) := Of_Kind;
      Value (Natural (Next)) := Of_Value;
      Next := Next + 1;
      Ok := True;
   end New_Label;

   function Touches_Outside (S : U8_Matrix; Y, X : Natural) return Boolean
   is
     (Y = S'First (1) or else Y = S'Last (1)
      or else X = S'First (2) or else X = S'Last (2)
      or else Class_At (S, Int64 (Y) - 1, Int64 (X)) = Seg_Outside
      or else Class_At (S, Int64 (Y) + 1, Int64 (X)) = Seg_Outside
      or else Class_At (S, Int64 (Y), Int64 (X) - 1) = Seg_Outside
      or else Class_At (S, Int64 (Y), Int64 (X) + 1) = Seg_Outside);
   --  A background pixel on the border of the rectangle or next to a
   --  pixel outside the region belongs to the outer background.

   Exterior : constant Int32 := 1;
   --  The label of the outer background (a root, kind Label_Hole, never
   --  a feature).

   procedure Provisional_Labels
     (S                   : U8_Matrix;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Mode                : Int32;
      L                   : in out Int32_Matrix;
      EP, Up, Kind, Value : in out Int32_Array;
      Next                : out Int32;
      Ok                  : out Boolean)
   with
     Pre  => L'First (1) = S'First (1) and then L'Last (1) = S'Last (1)
             and then L'First (2) = S'First (2)
             and then L'Last (2) = S'Last (2)
             and then Label_Tables (EP, Up, Kind, Value),
     Post => Next >= 2 and then Int64 (Next) <= Int64 (EP'Last) + 1;
   --  One raster pass: every pixel gets a provisional label (0 outside
   --  the region, Exterior for the outer background), joined with the
   --  labels of its earlier neighbours of the same connectivity: for
   --  foreground the left, upper-left, upper and upper-right ones (8-
   --  connected; in the Labeled mode only those of equal grey value), for
   --  background (GreyScale) the left and upper ones (4-connected). In
   --  WholeImageGreyScale every foreground pixel gets one label. Up keeps
   --  the label of the pixel above a new label's pixel (Exterior when
   --  there is none), which gives the parent of its feature.

   procedure Provisional_Labels
     (S                   : U8_Matrix;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Mode                : Int32;
      L                   : in out Int32_Matrix;
      EP, Up, Kind, Value : in out Int32_Array;
      Next                : out Int32;
      Ok                  : out Boolean)
   is
      Whole : Int32 := 0;
   begin
      Next := 2;
      Ok := True;
      EP (0) := 0;
      EP (1) := Exterior;
      Up (1) := 0;
      Kind (1) := Label_Hole;
      Value (1) := 0;
      for Y in S'Range (1) loop
         for X in S'Range (2) loop
            pragma Loop_Invariant
              (Next >= 2 and then Int64 (Next) <= Int64 (EP'Last) + 1
               and then Whole in 0 .. Next - 1);
            declare
               YI    : constant Int64 := Int64 (Y);
               XI    : constant Int64 := Int64 (X);
               C     : constant Grey_8 := S (Y, X);
               Label : Int32 := 0;
            begin
               if C = Seg_Outside then
                  Label := 0;
               elsif C = Seg_Foreground then
                  if Mode = Connectivity_Whole_Image_Grey_Scale then
                     if Whole = 0 then
                        New_Label (EP, Up, Kind, Value, Next, Label_Blob, 1,
                                   Exterior, Whole, Ok);
                        if not Ok then
                           return;
                        end if;
                     end if;
                     Label := Whole;
                  else
                     declare
                        Same : constant Boolean :=
                          Mode = Connectivity_Labeled;
                        V    : constant Grey_8 := Pixel_At (Image, YI, XI);
                     begin
                        Join (S, L, Image, EP, Seg_Foreground, Same, V,
                              YI, XI - 1, Next, Label);
                        Join (S, L, Image, EP, Seg_Foreground, Same, V,
                              YI - 1, XI - 1, Next, Label);
                        Join (S, L, Image, EP, Seg_Foreground, Same, V,
                              YI - 1, XI, Next, Label);
                        Join (S, L, Image, EP, Seg_Foreground, Same, V,
                              YI - 1, XI + 1, Next, Label);
                        if Label = 0 then
                           declare
                              Above : Int32 := Label_At (L, YI - 1, XI);
                           begin
                              if Same or else Above < 1 or else Above >= Next
                              then
                                 Above := Exterior;
                              end if;
                              New_Label
                                (EP, Up, Kind, Value, Next, Label_Blob,
                                 (if Same then Int32 (V) else 1), Above,
                                 Label, Ok);
                              if not Ok then
                                 return;
                              end if;
                           end;
                        end if;
                     end;
                  end if;
               elsif Mode /= Connectivity_Grey_Scale then
                  Label := Exterior;
               else
                  if Touches_Outside (S, Y, X) then
                     Label := Exterior;
                  end if;
                  Join (S, L, Image, EP, Seg_Background, False, 0,
                        YI, XI - 1, Next, Label);
                  Join (S, L, Image, EP, Seg_Background, False, 0,
                        YI - 1, XI, Next, Label);
                  if Label = 0 then
                     declare
                        Above : Int32 := Label_At (L, YI - 1, XI);
                     begin
                        if Above < 1 or else Above >= Next then
                           Above := Exterior;
                        end if;
                        New_Label (EP, Up, Kind, Value, Next, Label_Hole, 0,
                                   Above, Label, Ok);
                        if not Ok then
                           return;
                        end if;
                     end;
                  end if;
               end if;
               L (Y, X) := Label;
            end;
         end loop;
         pragma Loop_Invariant
           (Next >= 2 and then Int64 (Next) <= Int64 (EP'Last) + 1
            and then Whole in 0 .. Next - 1);
      end loop;
   end Provisional_Labels;

   ---------------------------------------------------------------------
   --  Components, parents and cleanup
   ---------------------------------------------------------------------

   procedure Resolve
     (EP                              : in out Int32_Array;
      Up, Kind, Value                 : Int32_Array;
      Next                            : Int32;
      Comp_Kind, Comp_Value, Comp_Up  : in out Int32_Array;
      M                               : out Int32)
   with
     Pre  => Label_Tables (EP, Up, Kind, Value)
             and then Next >= 2
             and then Int64 (Next) <= Int64 (EP'Last) + 1
             and then Comp_Kind'First = 0 and then Comp_Value'First = 0
             and then Comp_Up'First = 0
             and then Int64 (Comp_Kind'Last) = Int64 (Next) - 1
             and then Int64 (Comp_Value'Last) = Int64 (Next) - 1
             and then Int64 (Comp_Up'Last) = Int64 (Next) - 1,
     Post => M in 0 .. Next - 2;
   --  Numbers the classes in increasing order of their roots (the order
   --  of their first pixels), the outer background 0, and replaces every
   --  EP (Label) by the number of its class. Comp_Kind, Comp_Value and
   --  Comp_Up (the class of the pixel above the first pixel) describe
   --  each class 1 .. M.

   procedure Resolve
     (EP                              : in out Int32_Array;
      Up, Kind, Value                 : Int32_Array;
      Next                            : Int32;
      Comp_Kind, Comp_Value, Comp_Up  : in out Int32_Array;
      M                               : out Int32)
   is
   begin
      M := 0;
      EP (0) := 0;
      EP (1) := 0;
      for Label in 2 .. Next - 1 loop
         pragma Loop_Invariant (M in 0 .. Label - 2);
         declare
            Parent : constant Int32 := EP (Natural (Label));
         begin
            if Parent >= Label or else Parent < 0 then
               M := M + 1;
               EP (Natural (Label)) := M;
               Comp_Kind (Natural (M)) := Kind (Natural (Label));
               Comp_Value (Natural (M)) := Value (Natural (Label));
               declare
                  Above : constant Int32 := Up (Natural (Label));
               begin
                  Comp_Up (Natural (M)) :=
                    (if Above in 0 .. Label - 1 then EP (Natural (Above))
                     else 0);
               end;
            else
               --  Parent < Label already holds the number of its class.
               EP (Natural (Label)) := EP (Natural (Parent));
            end if;
         end;
      end loop;
   end Resolve;

   procedure Count_Components
     (L         : Int32_Matrix;
      EP        : Int32_Array;
      Next, M   : Int32;
      Comp_Area : in out Int64_Array)
   with
     Pre => EP'First = 0 and then Next >= 2
            and then Int64 (Next) <= Int64 (EP'Last) + 1
            and then Comp_Area'First = 0 and then M >= 0
            and then Int64 (Comp_Area'Last) >= Int64 (M);
   --  The number of pixels of each class 1 .. M.

   procedure Count_Components
     (L         : Int32_Matrix;
      EP        : Int32_Array;
      Next, M   : Int32;
      Comp_Area : in out Int64_Array)
   is
   begin
      for Y in L'Range (1) loop
         for X in L'Range (2) loop
            declare
               Label : constant Int32 := L (Y, X);
            begin
               if Label >= 0 and then Label < Next then
                  declare
                     C : constant Int32 := EP (Natural (Label));
                  begin
                     if C >= 1 and then C <= M
                       and then Comp_Area (Natural (C)) < Max_Area_Count
                     then
                        Comp_Area (Natural (C)) := Comp_Area (Natural (C)) + 1;
                     end if;
                  end;
               end if;
            end;
         end loop;
      end loop;
   end Count_Components;

   procedure Clean_Up
     (Params    : Ks_Blob_Run_Params;
      Comp_Up   : Int32_Array;
      Comp_Area : Int64_Array;
      M         : Int32;
      Target    : in out Int32_Array)
   with
     Pre => Comp_Up'First = 0 and then Comp_Area'First = 0
            and then Target'First = 0 and then M >= 0
            and then Int64 (Comp_Up'Last) >= Int64 (M)
            and then Int64 (Comp_Area'Last) >= Int64 (M)
            and then Int64 (Target'Last) >= Int64 (M);
   --  Target (C): the class whose feature class C's pixels end up in
   --  after the cleanup (C itself when C stays, 0 when its pixels belong
   --  to no feature), decided in increasing order so that the parent's
   --  target is known (see "Cleanup" in AMV.Kernels.Blob).

   procedure Clean_Up
     (Params    : Ks_Blob_Run_Params;
      Comp_Up   : Int32_Array;
      Comp_Area : Int64_Array;
      M         : Int32;
      Target    : in out Int32_Array)
   is
      Min_Pixels : constant Int64 := Int64 (Params.Connectivity_Min_Pixels);
      Fill       : constant Boolean :=
        Params.Connectivity_Cleanup = Cleanup_Fill
        and then Params.Connectivity_Mode = Connectivity_Grey_Scale;
   begin
      Target (0) := 0;
      for C in 1 .. M loop
         declare
            Parent : Int32 := Comp_Up (Natural (C));
            Small  : constant Boolean := Comp_Area (Natural (C)) < Min_Pixels;
         begin
            if Parent < 0 or else Parent >= C then
               Parent := 0;
            end if;
            if Params.Connectivity_Cleanup = Cleanup_None then
               Target (Natural (C)) := C;
            elsif Fill then
               if Small
                 or else (Parent /= 0
                          and then Comp_Area (Natural (Parent)) < Min_Pixels)
               then
                  Target (Natural (C)) := Target (Natural (Parent));
               else
                  Target (Natural (C)) := C;
               end if;
            elsif Small
              or else (Parent /= 0 and then Target (Natural (Parent)) = 0)
            then
               Target (Natural (C)) := 0;
            else
               Target (Natural (C)) := C;
            end if;
         end;
      end loop;
   end Clean_Up;

   ---------------------------------------------------------------------
   --  Numbering and counting (Gold)
   ---------------------------------------------------------------------

   function Surviving
     (Label  : Int32;
      EP     : Int32_Array;
      Next   : Int32;
      Target : Int32_Array;
      M      : Int32) return Int32
   with
     Pre  => EP'First = 0 and then Target'First = 0 and then M >= 0
             and then Int64 (Next) <= Int64 (EP'Last) + 1
             and then Int64 (Target'Last) >= Int64 (M),
     Post => Surviving'Result in 0 .. M;
   --  The class whose feature the pixel with this provisional label
   --  belongs to after the cleanup, 0 for none.

   function Surviving
     (Label  : Int32;
      EP     : Int32_Array;
      Next   : Int32;
      Target : Int32_Array;
      M      : Int32) return Int32
   is
   begin
      if Label < 0 or else Label >= Next then
         return 0;
      end if;
      declare
         C : constant Int32 := EP (Natural (Label));
      begin
         if C < 1 or else C > M then
            return 0;
         end if;
         declare
            T : constant Int32 := Target (Natural (C));
         begin
            return (if T >= 1 and then T <= M then T else 0);
         end;
      end;
   end Surviving;

   procedure Lemma_Sum_Increment
     (Old_Area, New_Area : Int64_Array;
      Kind               : Int32_Array;
      N, J               : Natural)
   with
     Ghost,
     Global => null,
     Pre  => Old_Area'First = 0 and then New_Area'First = 0
             and then Old_Area'Last = New_Area'Last and then Kind'First = 0
             and then (N = 0 or else (N - 1 <= Old_Area'Last
                                      and then N - 1 <= Kind'Last))
             and then J in Old_Area'Range
             and then Old_Area (J) < Int64'Last
             and then New_Area (J) = Old_Area (J) + 1
             and then (for all I in Old_Area'Range =>
                         (if I /= J then New_Area (I) = Old_Area (I))),
     Post => Sum_Blob (New_Area, Kind, N)
               = Sum_Blob (Old_Area, Kind, N)
                 + (if J < N and then Kind (J) = Label_Blob then 1 else 0),
     Subprogram_Variant => (Decreases => N);
   --  Adding 1 to one area adds 1 to the sum when that feature is a blob
   --  among the first N.

   procedure Lemma_Sum_Increment
     (Old_Area, New_Area : Int64_Array;
      Kind               : Int32_Array;
      N, J               : Natural)
   is
   begin
      if N > 0 then
         Lemma_Sum_Increment (Old_Area, New_Area, Kind, N - 1, J);
      end if;
   end Lemma_Sum_Increment;

   procedure Increment_Area
     (Area : in out Int64_Array;
      Kind : Int32_Array;
      N, K : Natural)
   with
     Pre  => Area'First = 0 and then Kind'First = 0
             and then (N = 0 or else (N - 1 <= Area'Last
                                      and then N - 1 <= Kind'Last))
             and then K in Area'Range
             and then Area (K) < Int64'Last,
     Post => Area (K) = Area'Old (K) + 1
             and then (for all I in Area'Range =>
                         (if I /= K then Area (I) = Area'Old (I)))
             and then Sum_Blob (Area, Kind, N)
                        = Sum_Blob (Area'Old, Kind, N)
                          + (if K < N and then Kind (K) = Label_Blob then 1
                             else 0);
   --  Adds the pixel of feature K to its area, and to the sum of the
   --  blob areas when it is a blob.

   procedure Increment_Area
     (Area : in out Int64_Array;
      Kind : Int32_Array;
      N, K : Natural)
   is
      Old : constant Int64_Array := Area with Ghost;
   begin
      Area (K) := Area (K) + 1;
      Lemma_Sum_Increment (Old, Area, Kind, N, K);
   end Increment_Area;

   procedure Lemma_Sum_Zero
     (Area : Int64_Array;
      Kind : Int32_Array;
      N    : Natural)
   with
     Ghost,
     Global => null,
     Pre  => Area'First = 0 and then Kind'First = 0
             and then (N = 0 or else (N - 1 <= Area'Last
                                      and then N - 1 <= Kind'Last))
             and then (for all I in Area'Range => Area (I) = 0),
     Post => Sum_Blob (Area, Kind, N) = 0,
     Subprogram_Variant => (Decreases => N);
   --  No area, no sum.

   procedure Lemma_Sum_Zero
     (Area : Int64_Array;
      Kind : Int32_Array;
      N    : Natural)
   is
   begin
      if N > 0 then
         Lemma_Sum_Zero (Area, Kind, N - 1);
      end if;
   end Lemma_Sum_Zero;

   procedure Count_Areas
     (Map            : Int32_Matrix;
      Kind           : Int32_Array;
      First_X        : Int32_Array;
      First_Y        : Int32_Array;
      Count          : Int32;
      Area           : out Int64_Array)
   with
     Pre  => Map'First (1) <= Map'Last (1)
             and then Map'First (2) <= Map'Last (2)
             and then Count >= 1
             and then Kind'First = 0
             and then Int64 (Kind'Last) = Int64 (Count) - 1
             and then First_X'First = 0 and then First_X'Last = Kind'Last
             and then First_Y'First = 0 and then First_Y'Last = Kind'Last
             and then Area'First = 0 and then Area'Last = Kind'Last,
     Post => Sum_Blob (Area, Kind, Natural (Count))
               = Big (Blob_Pixel_Count (Map, Kind))
             and then
               (for all K in Area'Range =>
                  (if Integer (First_Y (K)) in Map'Range (1)
                     and then Integer (First_X (K)) in Map'Range (2)
                     and then Map (Integer (First_Y (K)),
                                   Integer (First_X (K)))
                              = Int32 (K) + 1
                   then Area (K) >= 1));
   --  The number of pixels of each feature (Gold): the areas of the blobs
   --  add up to Blob_Pixel_Count, and a feature whose first pixel holds
   --  its number has at least one pixel.

   procedure Count_Areas
     (Map            : Int32_Matrix;
      Kind           : Int32_Array;
      First_X        : Int32_Array;
      First_Y        : Int32_Array;
      Count          : Int32;
      Area           : out Int64_Array)
   is
      Done : Int64 := 0;
   begin
      Area := [others => 0];
      Lemma_Sum_Zero (Area, Kind, Natural (Count));
      for Y in Map'Range (1) loop
         for X in Map'Range (2) loop
            declare
               Id : constant Int32 := Map (Y, X);
            begin
               if Id >= 1 and then Id <= Count then
                  Increment_Area
                    (Area, Kind, Natural (Count), Natural (Id - 1));
               end if;
            end;
            Done := Done + 1;
            pragma Loop_Invariant
              (Done <= Int64 (Y - Map'First (1)) * 2**31
                       + Int64 (X - Map'First (2)) + 1);
            pragma Loop_Invariant
              (for all I in Area'Range => Area (I) in 0 .. Done);
            pragma Loop_Invariant
              (Sum_Blob (Area, Kind, Natural (Count))
                 = Big (Rows_Count (Map, Kind, Int64 (Y))
                        + Row_Count (Map, Kind, Y, Int64 (X) + 1)));
            pragma Loop_Invariant
              (for all K in Area'Range =>
                 (if Integer (First_Y (K)) in Map'Range (1)
                    and then Integer (First_X (K)) in Map'Range (2)
                    and then Map (Integer (First_Y (K)),
                                  Integer (First_X (K)))
                             = Int32 (K) + 1
                    and then (Integer (First_Y (K)) < Y
                              or else (Integer (First_Y (K)) = Y
                                       and then Integer (First_X (K)) <= X))
                  then Area (K) >= 1));
         end loop;
         pragma Loop_Invariant
           (Done <= (Int64 (Y) - Int64 (Map'First (1)) + 1) * 2**31);
         pragma Loop_Invariant
           (for all I in Area'Range => Area (I) in 0 .. Done);
         pragma Loop_Invariant
           (Sum_Blob (Area, Kind, Natural (Count))
              = Big (Rows_Count (Map, Kind, Int64 (Y) + 1)));
         pragma Loop_Invariant
           (for all K in Area'Range =>
              (if Integer (First_Y (K)) in Map'Range (1)
                 and then Integer (First_X (K)) in Map'Range (2)
                 and then Map (Integer (First_Y (K)), Integer (First_X (K)))
                          = Int32 (K) + 1
                 and then Integer (First_Y (K)) <= Y
               then Area (K) >= 1));
      end loop;
   end Count_Areas;

   procedure Number_Features
     (L          : Int32_Matrix;
      EP         : Int32_Array;
      Next, M    : Int32;
      Target     : Int32_Array;
      Comp_Kind  : Int32_Array;
      Comp_Value : Int32_Array;
      Comp_Up    : Int32_Array;
      Features   : out Feature_Set;
      Status     : out Ks_Status)
   with
     Pre  => L'First (1) <= L'Last (1) and then L'First (2) <= L'Last (2)
             and then EP'First = 0 and then Next >= 2
             and then Int64 (Next) <= Int64 (EP'Last) + 1
             and then M in 0 .. Next - 2
             and then Target'First = 0 and then Comp_Kind'First = 0
             and then Comp_Value'First = 0 and then Comp_Up'First = 0
             and then Int64 (Target'Last) >= Int64 (M)
             and then Int64 (Comp_Kind'Last) >= Int64 (M)
             and then Int64 (Comp_Value'Last) >= Int64 (M)
             and then Int64 (Comp_Up'Last) >= Int64 (M),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Valid_Features
                       (Features,
                        (X_Min => L'First (2), Y_Min => L'First (1),
                         X_Max => L'Last (2), Y_Max => L'Last (1)))
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
   --  The final feature map: each pixel gets the number (ID + 1) of the
   --  feature its class ends up in, the features numbered in the order in
   --  which their first pixels appear; then the tables of the features
   --  and their areas.

   procedure Number_Features
     (L          : Int32_Matrix;
      EP         : Int32_Array;
      Next, M    : Int32;
      Target     : Int32_Array;
      Comp_Kind  : Int32_Array;
      Comp_Value : Int32_Array;
      Comp_Up    : Int32_Array;
      Features   : out Feature_Set;
      Status     : out Ks_Status)
   is
      B       : constant Box :=
        (X_Min => L'First (2), Y_Min => L'First (1),
         X_Max => L'Last (2), Y_Max => L'Last (1));
      Map     : Int32_Matrix_Access;
      New_Id  : Int32_Array_Access;
      Old_Of  : Int32_Array_Access;
      Wit_X   : Int32_Array_Access;
      Wit_Y   : Int32_Array_Access;
      Kind    : Int32_Array_Access;
      Label   : Int32_Array_Access;
      Parent  : Int32_Array_Access;
      First_X : Int32_Array_Access;
      First_Y : Int32_Array_Access;
      Area    : Int64_Array_Access;
      Count   : Int32 := 0;
   begin
      Features := (Count => 0, others => <>);
      Allocate_Int32_Matrix (B, Map);
      if Map = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Execute: out of memory for the feature map");
         return;
      end if;
      if M = 0 then
         Features := (Count => 0, Map => Map, others => <>);
         Set_Success (Status);
         return;
      end if;

      Allocate_Int32_Array (Natural (M), New_Id);
      Allocate_Int32_Array (Natural (M) - 1, Old_Of);
      Allocate_Int32_Array (Natural (M) - 1, Wit_X);
      Allocate_Int32_Array (Natural (M) - 1, Wit_Y);
      if New_Id = null or else Old_Of = null or else Wit_X = null
        or else Wit_Y = null
      then
         Free (Map);
         Free (New_Id);
         Free (Old_Of);
         Free (Wit_X);
         Free (Wit_Y);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Execute: out of memory for the feature tables");
         return;
      end if;

      --  The map, numbering the features as their first pixels appear.
      for Y in L'Range (1) loop
         for X in L'Range (2) loop
            declare
               T  : constant Int32 :=
                 Surviving (L (Y, X), EP, Next, Target, M);
               Id : Int32 := 0;
            begin
               if T >= 1 then
                  Id := New_Id (Natural (T));
                  if Id < 1 or else Id > Count then
                     if Count < M then
                        Count := Count + 1;
                        New_Id (Natural (T)) := Count;
                        Old_Of (Natural (Count - 1)) := T;
                        Wit_X (Natural (Count - 1)) := Int32 (X);
                        Wit_Y (Natural (Count - 1)) := Int32 (Y);
                        Id := Count;
                     else
                        Id := 0;
                     end if;
                  end if;
               end if;
               Map (Y, X) := Id;
            end;
            pragma Loop_Invariant
              (Matrix_On_Box (Map.all, B));
            pragma Loop_Invariant
              (New_Id /= null and then Old_Of /= null and then Wit_X /= null
               and then Wit_Y /= null
               and then New_Id'First = 0
               and then Int64 (New_Id'Last) = Int64 (M)
               and then Old_Of'First = 0
               and then Int64 (Old_Of'Last) = Int64 (M) - 1
               and then Wit_X'First = 0 and then Wit_X'Last = Old_Of'Last
               and then Wit_Y'First = 0 and then Wit_Y'Last = Old_Of'Last);
            pragma Loop_Invariant (Count in 0 .. M);
            pragma Loop_Invariant
              (for all K in 0 .. Integer (Count) - 1 =>
                 Integer (Wit_Y (K)) in L'First (1) .. Y
                 and then Integer (Wit_X (K)) in L'Range (2)
                 and then (Integer (Wit_Y (K)) < Y
                           or else Integer (Wit_X (K)) <= X)
                 and then Map (Integer (Wit_Y (K)), Integer (Wit_X (K)))
                            = Int32 (K) + 1);
         end loop;
         pragma Loop_Invariant
           (Matrix_On_Box (Map.all, B));
         pragma Loop_Invariant
           (New_Id /= null and then Old_Of /= null and then Wit_X /= null
            and then Wit_Y /= null
            and then New_Id'First = 0
            and then Int64 (New_Id'Last) = Int64 (M)
            and then Old_Of'First = 0
            and then Int64 (Old_Of'Last) = Int64 (M) - 1
            and then Wit_X'First = 0 and then Wit_X'Last = Old_Of'Last
            and then Wit_Y'First = 0 and then Wit_Y'Last = Old_Of'Last);
         pragma Loop_Invariant (Count in 0 .. M);
         pragma Loop_Invariant
           (for all K in 0 .. Integer (Count) - 1 =>
              Integer (Wit_Y (K)) in L'First (1) .. Y
              and then Integer (Wit_X (K)) in L'Range (2)
              and then Map (Integer (Wit_Y (K)), Integer (Wit_X (K)))
                         = Int32 (K) + 1);
      end loop;

      if Count = 0 then
         Free (New_Id);
         Free (Old_Of);
         Free (Wit_X);
         Free (Wit_Y);
         Features := (Count => 0, Map => Map, others => <>);
         Set_Success (Status);
         return;
      end if;

      --  The tables of the features.
      Allocate_Int32_Array (Natural (Count) - 1, Kind);
      Allocate_Int32_Array (Natural (Count) - 1, Label);
      Allocate_Int32_Array (Natural (Count) - 1, Parent);
      Allocate_Int32_Array (Natural (Count) - 1, First_X);
      Allocate_Int32_Array (Natural (Count) - 1, First_Y);
      Allocate_Int64_Array (Natural (Count) - 1, Area);
      if Kind = null or else Label = null or else Parent = null
        or else First_X = null or else First_Y = null or else Area = null
      then
         Free (Map);
         Free (New_Id);
         Free (Old_Of);
         Free (Wit_X);
         Free (Wit_Y);
         Free (Kind);
         Free (Label);
         Free (Parent);
         Free (First_X);
         Free (First_Y);
         Free (Area);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Execute: out of memory for the feature tables");
         return;
      end if;

      for K in 0 .. Integer (Count) - 1 loop
         declare
            T : Int32 := Old_Of (K);
         begin
            if T < 1 or else T > M then
               T := 0;
            end if;
            Kind (K) :=
              (if T >= 1 and then Comp_Kind (Natural (T)) = Label_Blob
               then Label_Blob else Label_Hole);
            Label (K) := (if T >= 1 then Comp_Value (Natural (T)) else 0);
            declare
               Up_Class : Int32 :=
                 (if T >= 1 then Comp_Up (Natural (T)) else 0);
               Up_Id    : Int32 := 0;
            begin
               if Up_Class < 1 or else Up_Class > M then
                  Up_Class := 0;
               else
                  Up_Class := Target (Natural (Up_Class));
                  if Up_Class < 1 or else Up_Class > M then
                     Up_Class := 0;
                  end if;
               end if;
               if Up_Class >= 1 then
                  Up_Id := New_Id (Natural (Up_Class));
               end if;
               Parent (K) := (if Up_Id in 1 .. Count then Up_Id - 1 else -1);
            end;
            First_X (K) := Wit_X (K);
            First_Y (K) := Wit_Y (K);
         end;
         pragma Loop_Invariant
           (for all J in 0 .. K =>
              First_X (J) = Wit_X (J) and then First_Y (J) = Wit_Y (J));
      end loop;

      pragma Assert
        (for all K in First_X'Range =>
           Integer (First_Y (K)) in Map'Range (1)
           and then Integer (First_X (K)) in Map'Range (2)
           and then Map (Integer (First_Y (K)), Integer (First_X (K)))
                      = Int32 (K) + 1);

      Free (New_Id);
      Free (Old_Of);
      Free (Wit_X);
      Free (Wit_Y);

      Count_Areas (Map.all, Kind.all, First_X.all, First_Y.all, Count,
                   Area.all);

      Features :=
        (Count   => Count,
         Map     => Map,
         Kind    => Kind,
         Label   => Label,
         Parent  => Parent,
         First_X => First_X,
         First_Y => First_Y,
         Area    => Area);
      Set_Success (Status);
   end Number_Features;

   ---------------------------------------------------------------------
   --  Finding the features
   ---------------------------------------------------------------------

   procedure Find_Features
     (S        : U8_Matrix;
      Image    : access constant KI.Ks_Image_8_Grey_Data;
      Params   : Ks_Blob_Run_Params;
      Features : out Feature_Set;
      Status   : out Ks_Status)
   is
      B          : constant Box :=
        (X_Min => S'First (2), Y_Min => S'First (1),
         X_Max => S'Last (2), Y_Max => S'Last (1));
      Pixels     : constant Int64 :=
        (Int64 (S'Last (1)) - Int64 (S'First (1)) + 1)
        * (Int64 (S'Last (2)) - Int64 (S'First (2)) + 1);
      Last_Label : constant Natural := Natural (Pixels + 1);
      L          : Int32_Matrix_Access;
      EP         : Int32_Array_Access;
      Up         : Int32_Array_Access;
      Kind       : Int32_Array_Access;
      Value      : Int32_Array_Access;
      Comp_Kind  : Int32_Array_Access;
      Comp_Value : Int32_Array_Access;
      Comp_Up    : Int32_Array_Access;
      Target     : Int32_Array_Access;
      Comp_Area  : Int64_Array_Access;
      Next       : Int32;
      M          : Int32;
      Ok         : Boolean;
   begin
      Features := (Count => 0, others => <>);
      Allocate_Int32_Matrix (B, L);
      Allocate_Int32_Array (Last_Label, EP);
      Allocate_Int32_Array (Last_Label, Up);
      Allocate_Int32_Array (Last_Label, Kind);
      Allocate_Int32_Array (Last_Label, Value);
      if L = null or else EP = null or else Up = null or else Kind = null
        or else Value = null
      then
         Free (L);
         Free (EP);
         Free (Up);
         Free (Kind);
         Free (Value);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Execute: out of memory for the label tables");
         return;
      end if;

      Provisional_Labels
        (S, Image, Params.Connectivity_Mode, L.all, EP.all, Up.all,
         Kind.all, Value.all, Next, Ok);
      if Ok then
         Allocate_Int32_Array (Natural (Next) - 1, Comp_Kind);
         Allocate_Int32_Array (Natural (Next) - 1, Comp_Value);
         Allocate_Int32_Array (Natural (Next) - 1, Comp_Up);
         Allocate_Int32_Array (Natural (Next) - 1, Target);
         Allocate_Int64_Array (Natural (Next) - 1, Comp_Area);
      end if;
      if not Ok or else Comp_Kind = null or else Comp_Value = null
        or else Comp_Up = null or else Target = null or else Comp_Area = null
      then
         Free (L);
         Free (EP);
         Free (Up);
         Free (Kind);
         Free (Value);
         Free (Comp_Kind);
         Free (Comp_Value);
         Free (Comp_Up);
         Free (Target);
         Free (Comp_Area);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Execute: out of memory for the label tables");
         return;
      end if;

      Resolve (EP.all, Up.all, Kind.all, Value.all, Next, Comp_Kind.all,
               Comp_Value.all, Comp_Up.all, M);
      Free (Up);
      Free (Kind);
      Free (Value);
      Count_Components (L.all, EP.all, Next, M, Comp_Area.all);
      Clean_Up (Params, Comp_Up.all, Comp_Area.all, M, Target.all);
      Free (Comp_Area);

      Number_Features
        (L.all, EP.all, Next, M, Target.all, Comp_Kind.all, Comp_Value.all,
         Comp_Up.all, Features, Status);

      Free (L);
      Free (EP);
      Free (Comp_Kind);
      Free (Comp_Value);
      Free (Comp_Up);
      Free (Target);
   end Find_Features;

end AMV.Kernels.Blob.Labelling;
