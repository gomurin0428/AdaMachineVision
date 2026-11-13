pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Numerics;

package body AMV.Kernels.CNL_Search.Search with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Candidates
     (Count : Positive;
      Items : out Candidate_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Items := new Candidate_Array (0 .. Count - 1);
   exception
      when Storage_Error =>
         Items := null;
   end Allocate_Candidates;

   procedure Allocate_Score_Rows
     (Columns : Positive;
      Rows    : out Score_Rows_Access)
     with SPARK_Mode => Off
   is
   begin
      Rows := new Score_Rows (0 .. 2, 0 .. Columns - 1);
   exception
      when Storage_Error =>
         Rows := null;
   end Allocate_Score_Rows;

   procedure Allocate_Matches
     (Count : Positive;
      Items : out Match_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Items := new Match_Array (0 .. Count - 1);
   exception
      when Storage_Error =>
         Items := null;
   end Allocate_Matches;

   ---------------------------------------------------------------------
   --  Candidates
   ---------------------------------------------------------------------

   procedure Insert
     (Items : in out Candidate_Array;
      Count : in out Natural;
      Item  : Candidate)
   with
     Pre  => Items'First = 0 and then Items'Last >= 0
             and then Items'Last < Natural'Last
             and then Count <= Items'Last + 1,
     Post => Count <= Items'Last + 1 and then Count >= Count'Old;
   --  Inserts Item into Items (0 .. Count - 1), which is kept best first
   --  (after the items of equal score); when the array is full the worst
   --  item drops out, or Item when it is no better than the worst.

   procedure Insert
     (Items : in out Candidate_Array;
      Count : in out Natural;
      Item  : Candidate)
   is
      Slot : Natural;
   begin
      if Count = Items'Last + 1 then
         if Item.Score <= Items (Items'Last).Score then
            return;
         end if;
         Slot := Items'Last;
      else
         Slot := Count;
         Count := Count + 1;
      end if;
      while Slot > 0 and then Items (Slot - 1).Score < Item.Score loop
         pragma Loop_Invariant (Slot <= Items'Last);
         pragma Loop_Invariant (Count <= Items'Last + 1
                                and then Count >= Count'Loop_Entry);
         Items (Slot) := Items (Slot - 1);
         Slot := Slot - 1;
      end loop;
      Items (Slot) := Item;
   end Insert;

   function Ring (Y : Natural) return Natural is (Y mod 3)
   with Post => Ring'Result <= 2;
   --  The row of the ring of three score rows that holds row Y.

   function Is_Peak
     (Rows           : Score_Rows;
      X, Y           : Natural;
      Last_X, Last_Y : Natural) return Boolean
   with
     Pre => Rows'First (1) = 0 and then Rows'Last (1) = 2
            and then Rows'First (2) = 0 and then Last_X <= Rows'Last (2)
            and then X <= Last_X and then Y <= Last_Y;
   --  The score at (X, Y) is above those of its neighbours before it in
   --  raster order and at least those after it (neighbours within
   --  0 .. Last_X by 0 .. Last_Y; the ring holds rows Y - 1 .. Y + 1).

   function Is_Peak
     (Rows           : Score_Rows;
      X, Y           : Natural;
      Last_X, Last_Y : Natural) return Boolean
   is
      Centre : constant KC.Score_Value := Rows (Ring (Y), X);
   begin
      for DY in -1 .. 1 loop
         for DX in -1 .. 1 loop
            if (DY /= 0 or else DX /= 0)
              and then (DY >= 0 or else Y >= 1)
              and then (DY <= 0 or else Y < Last_Y)
              and then (DX >= 0 or else X >= 1)
              and then (DX <= 0 or else X < Last_X)
            then
               declare
                  Other : constant KC.Score_Value :=
                    Rows (Ring (Y + DY), X + DX);
               begin
                  if DY < 0 or else (DY = 0 and then DX < 0) then
                     if Centre <= Other then
                        return False;
                     end if;
                  elsif Centre < Other then
                     return False;
                  end if;
               end;
            end if;
         end loop;
      end loop;
      return True;
   end Is_Peak;

   procedure Scan
     (Plan      : KL.Valid_Search_Plan;
      Image     : KL.Grey_8_Matrix;
      Sums      : KL.Sum_Matrix;
      Pattern   : KL.Grey_8_Matrix;
      Care      : KL.Grey_8_Matrix;
      L         : Natural;
      Ignore    : Boolean;
      Threshold : KC.Score_Value;
      Rows      : in out Score_Rows;
      Items     : in out Candidate_Array;
      Count     : in out Natural)
   is
      Last_X : constant Natural := KL.Last_X (Plan, L);
      Last_Y : constant Natural := KL.Last_Y (Plan, L);
   begin
      for Y in 0 .. Last_Y + 1 loop
         pragma Loop_Invariant (Count <= Items'Last + 1);
         if Y <= Last_Y then
            for X in 0 .. Last_X loop
               Rows (Ring (Y), X) :=
                 KC.Score_At (Plan, Image, Sums, Pattern, Care, L, Ignore,
                              X, Y);
            end loop;
         end if;
         if Y >= 1 then
            for X in 0 .. Last_X loop
               pragma Loop_Invariant (Count <= Items'Last + 1);
               declare
                  Score : constant KC.Score_Value := Rows (Ring (Y - 1), X);
               begin
                  if Score >= Threshold
                    and then Is_Peak (Rows, X, Y - 1, Last_X, Last_Y)
                  then
                     Insert (Items, Count, (X => X, Y => Y - 1,
                                            Score => Score));
                  end if;
               end;
            end loop;
         end if;
      end loop;
   end Scan;

   ---------------------------------------------------------------------
   --  Refinement
   ---------------------------------------------------------------------

   procedure Best_Around
     (Plan    : KL.Valid_Search_Plan;
      Image   : KL.Grey_8_Matrix;
      Sums    : KL.Sum_Matrix;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      L       : Natural;
      Ignore  : Boolean;
      X, Y    : in out Position)
   with
     Pre  => KL.Matches (Plan, Image, Sums, Pattern, Care)
             and then L < Plan.Levels,
     Post => X <= KL.Last_X (Plan, L) and then Y <= KL.Last_Y (Plan, L);
   --  From a position (X, Y) of level L + 1: the best of the positions of
   --  level L within 2 of (2 X, 2 Y) (the nearest position of level L
   --  when none is).

   procedure Best_Around
     (Plan    : KL.Valid_Search_Plan;
      Image   : KL.Grey_8_Matrix;
      Sums    : KL.Sum_Matrix;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      L       : Natural;
      Ignore  : Boolean;
      X, Y    : in out Position)
   is
      Last_X : constant Natural := KL.Last_X (Plan, L);
      Last_Y : constant Natural := KL.Last_Y (Plan, L);
      X_High : constant Natural := Natural'Min (2 * X + 2, Last_X);
      Y_High : constant Natural := Natural'Min (2 * Y + 2, Last_Y);
      X_Low  : constant Natural :=
        Natural'Min ((if X >= 1 then 2 * X - 2 else 0), X_High);
      Y_Low  : constant Natural :=
        Natural'Min ((if Y >= 1 then 2 * Y - 2 else 0), Y_High);
      Best   : Long_Float := -1.0;
      Best_X : Natural := X_Low;
      Best_Y : Natural := Y_Low;
   begin
      for YY in Y_Low .. Y_High loop
         pragma Loop_Invariant (Best_X in X_Low .. X_High
                                and then Best_Y in Y_Low .. Y_High);
         for XX in X_Low .. X_High loop
            pragma Loop_Invariant (Best_X in X_Low .. X_High
                                   and then Best_Y in Y_Low .. Y_High);
            declare
               Score : constant KC.Score_Value :=
                 KC.Score_At (Plan, Image, Sums, Pattern, Care, L, Ignore,
                              XX, YY);
            begin
               if Score > Best then
                  Best := Score;
                  Best_X := XX;
                  Best_Y := YY;
               end if;
            end;
         end loop;
      end loop;
      X := Best_X;
      Y := Best_Y;
   end Best_Around;

   procedure Climb
     (Plan    : KL.Valid_Search_Plan;
      Image   : KL.Grey_8_Matrix;
      Sums    : KL.Sum_Matrix;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      L       : Natural;
      Ignore  : Boolean;
      X, Y    : in out Position)
   with
     Pre  => KL.Matches (Plan, Image, Sums, Pattern, Care)
             and then L < Plan.Levels
             and then X <= KL.Last_X (Plan, L)
             and then Y <= KL.Last_Y (Plan, L),
     Post => X <= KL.Last_X (Plan, L) and then Y <= KL.Last_Y (Plan, L);
   --  Moves (X, Y) to its best neighbour on level L while that scores
   --  higher, at most Max_Climb_Steps times.

   procedure Climb
     (Plan    : KL.Valid_Search_Plan;
      Image   : KL.Grey_8_Matrix;
      Sums    : KL.Sum_Matrix;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      L       : Natural;
      Ignore  : Boolean;
      X, Y    : in out Position)
   is
      Last_X  : constant Natural := KL.Last_X (Plan, L);
      Last_Y  : constant Natural := KL.Last_Y (Plan, L);
      Current : KC.Score_Value :=
        KC.Score_At (Plan, Image, Sums, Pattern, Care, L, Ignore, X, Y);
   begin
      for Step in 1 .. Max_Climb_Steps loop
         pragma Loop_Invariant (X <= Last_X and then Y <= Last_Y);
         declare
            Best   : KC.Score_Value := Current;
            Best_X : Natural := X;
            Best_Y : Natural := Y;
         begin
            for DY in -1 .. 1 loop
               pragma Loop_Invariant (Best_X <= Last_X
                                      and then Best_Y <= Last_Y);
               for DX in -1 .. 1 loop
                  pragma Loop_Invariant (Best_X <= Last_X
                                         and then Best_Y <= Last_Y);
                  if (DY /= 0 or else DX /= 0)
                    and then (DY >= 0 or else Y >= 1)
                    and then (DY <= 0 or else Y < Last_Y)
                    and then (DX >= 0 or else X >= 1)
                    and then (DX <= 0 or else X < Last_X)
                  then
                     declare
                        Score : constant KC.Score_Value :=
                          KC.Score_At (Plan, Image, Sums, Pattern, Care, L,
                                       Ignore, X + DX, Y + DY);
                     begin
                        if Score > Best then
                           Best := Score;
                           Best_X := X + DX;
                           Best_Y := Y + DY;
                        end if;
                     end;
                  end if;
               end loop;
            end loop;
            exit when Best_X = X and then Best_Y = Y;
            X := Best_X;
            Y := Best_Y;
            Current := Best;
         end;
      end loop;
   end Climb;

   procedure Refine
     (Plan    : KL.Valid_Search_Plan;
      Image   : KL.Grey_8_Matrix;
      Sums    : KL.Sum_Matrix;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      From    : Natural;
      Ignore  : Boolean;
      X, Y    : in out Position;
      Score   : out KC.Score_Value)
   is
   begin
      X := Natural'Min (X, KL.Last_X (Plan, From));
      Y := Natural'Min (Y, KL.Last_Y (Plan, From));
      for L in reverse 0 .. From - 1 loop
         Best_Around (Plan, Image, Sums, Pattern, Care, L, Ignore, X, Y);
         pragma Loop_Invariant (X <= KL.Last_X (Plan, L)
                                and then Y <= KL.Last_Y (Plan, L));
      end loop;
      if From > 0 then
         Climb (Plan, Image, Sums, Pattern, Care, 0, Ignore, X, Y);
      end if;
      Score := KC.Score_At (Plan, Image, Sums, Pattern, Care, 0, Ignore, X, Y);
   end Refine;

   ---------------------------------------------------------------------
   --  Matches
   ---------------------------------------------------------------------

   procedure Insert_Match
     (Items : in out Match_Array;
      Count : in out Natural;
      Item  : Match)
   with
     Pre  => Items'First = 0 and then Items'Last >= 0
             and then Items'Last < Natural'Last
             and then Count <= Items'Last + 1,
     Post => Count <= Items'Last + 1;
   --  As Insert, for matches.

   procedure Insert_Match
     (Items : in out Match_Array;
      Count : in out Natural;
      Item  : Match)
   is
      Slot : Natural;
   begin
      if Count = Items'Last + 1 then
         if Item.Score <= Items (Items'Last).Score then
            return;
         end if;
         Slot := Items'Last;
      else
         Slot := Count;
         Count := Count + 1;
      end if;
      while Slot > 0 and then Items (Slot - 1).Score < Item.Score loop
         pragma Loop_Invariant (Slot <= Items'Last);
         pragma Loop_Invariant (Count <= Items'Last + 1);
         Items (Slot) := Items (Slot - 1);
         Slot := Slot - 1;
      end loop;
      Items (Slot) := Item;
   end Insert_Match;

   procedure Neighbours
     (Plan    : KL.Valid_Search_Plan;
      Image   : KL.Grey_8_Matrix;
      Sums    : KL.Sum_Matrix;
      Pattern : KL.Grey_8_Matrix;
      Care    : KL.Grey_8_Matrix;
      Ignore  : Boolean;
      X, Y    : Natural;
      Scores  : out KC.Neighbourhood;
      Present : out KC.Presence)
   is
      Last_X : constant Natural := KL.Last_X (Plan, 0);
      Last_Y : constant Natural := KL.Last_Y (Plan, 0);
   begin
      Scores := [others => [others => 0.0]];
      Present := [others => [others => False]];
      for DY in -2 .. 2 loop
         for DX in -2 .. 2 loop
            if Y + DY in 0 .. Last_Y and then X + DX in 0 .. Last_X then
               Scores (DY, DX) :=
                 KC.Score_At (Plan, Image, Sums, Pattern, Care, 0, Ignore,
                              X + DX, Y + DY);
               Present (DY, DX) := True;
            end if;
         end loop;
      end loop;
   end Neighbours;

   function Overlap_Along (Distance : Long_Float; Size : KL.Side)
      return KC.Score_Value
   is
     (if Distance >= Long_Float (Size) then 0.0
      else N.Clamp_Unit (N.Unit_Ratio (Long_Float (Size) - Distance,
                                       Long_Float (Size))))
   with Pre => Distance >= 0.0 and then Distance <= 2.0 ** 26;
   --  The fraction of a window's side that two windows Distance apart
   --  along that side share.

   function Coordinate (P : Position; O : KC.Offset) return Long_Float is
     (Long_Float (P) + O)
   with Post => Coordinate'Result in -1.0 .. Long_Float (Max_Search_Pixels)
                                              + 1.0;

   function Overlaps
     (A, B          : Match;
      Width, Height : KL.Side;
      Limit         : KC.Score_Value) return Boolean
   is
      DX : constant Long_Float :=
        abs (Coordinate (A.X, A.Offset_X) - Coordinate (B.X, B.Offset_X));
      DY : constant Long_Float :=
        abs (Coordinate (A.Y, A.Offset_Y) - Coordinate (B.Y, B.Offset_Y));
   begin
      if A.X = B.X and then A.Y = B.Y then
         return True;
      end if;
      return N.Times_Unit (Overlap_Along (DX, Width),
                           Overlap_Along (DY, Height)) > Limit;
   end Overlaps;

   procedure Collect
     (Plan        : KL.Valid_Search_Plan;
      Image       : KL.Grey_8_Matrix;
      Sums        : KL.Sum_Matrix;
      Pattern     : KL.Grey_8_Matrix;
      Care        : KL.Grey_8_Matrix;
      Ignore      : Boolean;
      Accept_At   : KC.Score_Value;
      Confident   : KC.Score_Value;
      Max_Results : Positive;
      XY_Overlap  : KC.Score_Value;
      Candidates  : Candidate_Array;
      Found       : Natural;
      Matches     : in out Match_Array;
      Count       : out Natural;
      Sure        : in out Match_Array)
   is
      Width  : constant KL.Side := Plan.Pattern (0).Geometry.Width;
      Height : constant KL.Side := Plan.Pattern (0).Geometry.Height;
      Sure_Count : Natural := 0;
   begin
      Count := 0;
      for I in 0 .. Found - 1 loop
         pragma Loop_Invariant (Count <= Matches'Last + 1);
         pragma Loop_Invariant (Sure_Count < Max_Results);
         declare
            X     : Position := Candidates (I).X;
            Y     : Position := Candidates (I).Y;
            Score : KC.Score_Value;
         begin
            Refine (Plan, Image, Sums, Pattern, Care, Plan.Levels - 1, Ignore,
                    X, Y, Score);
            if Score >= Accept_At then
               declare
                  Item : constant Match :=
                    (X        => X,
                     Y        => Y,
                     Offset_X => 0.0,
                     Offset_Y => 0.0,
                     Score    => Score,
                     Contrast => 0.0);
               begin
                  Insert_Match (Matches, Count, Item);
                  if Score >= Confident then
                     declare
                        Apart : Boolean := True;
                     begin
                        for K in 0 .. Sure_Count - 1 loop
                           if Overlaps (Sure (K), Item, Width, Height,
                                        XY_Overlap)
                           then
                              Apart := False;
                           end if;
                        end loop;
                        if Apart then
                           Sure (Sure_Count) := Item;
                           Sure_Count := Sure_Count + 1;
                        end if;
                     end;
                  end if;
               end;
            end if;
         end;
         exit when Sure_Count = Max_Results;
      end loop;
   end Collect;

   procedure Choose
     (Matches     : Match_Array;
      Count       : Natural;
      Max_Results : Positive;
      Accept_At   : KC.Score_Value;
      XY_Overlap  : KC.Score_Value;
      Width       : KL.Side;
      Height      : KL.Side;
      Chosen      : in out Match_Array;
      Taken       : out Natural)
   is
   begin
      Taken := 0;
      for I in 0 .. Count - 1 loop
         pragma Loop_Invariant (Taken < Max_Results);
         pragma Loop_Invariant
           (for all K in 0 .. Taken - 1 => Chosen (K).Score >= Accept_At);
         pragma Loop_Invariant
           (for all K in 0 .. Taken - 2 =>
              Chosen (K).Score >= Chosen (K + 1).Score);
         declare
            Item  : constant Match := Matches (I);
            Apart : Boolean := True;
         begin
            for K in 0 .. Taken - 1 loop
               if Overlaps (Chosen (K), Item, Width, Height, XY_Overlap) then
                  Apart := False;
               end if;
            end loop;
            --  The tests of the score always pass (every match scores at
            --  least Accept_At and Matches is best first); they state the
            --  proved facts of the results.
            if Apart and then Item.Score >= Accept_At
              and then (Taken = 0
                        or else Item.Score <= Chosen (Taken - 1).Score)
            then
               Chosen (Taken) := Item;
               Taken := Taken + 1;
            end if;
         end;
         exit when Taken = Max_Results;
      end loop;
   end Choose;

end AMV.Kernels.CNL_Search.Search;
