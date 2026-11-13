--  The search of the CNL search (private to the kernel): the candidates
--  of a level (local maxima of the scores), their refinement down the
--  pyramid, the matches at full resolution and the choice of the results
--  among them (see AMV.Kernels.CNL_Search).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.CNL_Search.Correlation;
with AMV.Kernels.CNL_Search.Levels;

private package AMV.Kernels.CNL_Search.Search
  with SPARK_Mode, Preelaborate
is

   package KL renames AMV.Kernels.CNL_Search.Levels;
   package KC renames AMV.Kernels.CNL_Search.Correlation;

   subtype Position is Natural range 0 .. Max_Search_Pixels;
   --  A window position along one axis of a level.

   ---------------------------------------------------------------------
   --  Candidates
   ---------------------------------------------------------------------

   type Candidate is record
      X, Y  : Position := 0;
      Score : KC.Score_Value := 0.0;
   end record;

   type Candidate_Array is array (Natural range <>) of Candidate;
   type Candidate_Array_Access is access Candidate_Array;

   procedure Allocate_Candidates
     (Count : Positive;
      Items : out Candidate_Array_Access)
   with
     Global => null,
     Post   => (if Items /= null
                then Items'First = 0 and then Items'Last = Count - 1);
   --  A new array of Count candidates (the record's defaults), or null
   --  when the memory cannot be allocated. Trusted: the allocator raises
   --  Storage_Error, which SPARK cannot express.

   type Score_Rows is array (Natural range <>, Natural range <>)
     of KC.Score_Value
     with Default_Component_Value => 0.0;
   type Score_Rows_Access is access Score_Rows;

   procedure Allocate_Score_Rows
     (Columns : Positive;
      Rows    : out Score_Rows_Access)
   with
     Global => null,
     Post   => (if Rows /= null
                then Rows'First (1) = 0 and then Rows'Last (1) = 2
                     and then Rows'First (2) = 0
                     and then Rows'Last (2) = Columns - 1);
   --  Three rows of Columns scores (all 0), or null. Trusted as above.

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
   with
     Pre  => KL.Matches (Plan, Image, Sums, Pattern, Care)
             and then L < Plan.Levels
             and then Rows'First (1) = 0 and then Rows'Last (1) = 2
             and then Rows'First (2) = 0
             and then Rows'Last (2) >= KL.Last_X (Plan, L)
             and then Items'First = 0 and then Items'Last >= 0
             and then Items'Last < Natural'Last
             and then Count <= Items'Last + 1,
     Post => Count <= Items'Last + 1;
   --  Scores every position of level L (three rows at a time in Rows) and
   --  keeps in Items (0 .. Count - 1), best first, the local maxima that
   --  score at least Threshold (the best Items'Length of them).

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
   with
     Pre  => KL.Matches (Plan, Image, Sums, Pattern, Care)
             and then From < Plan.Levels,
     Post => X <= KL.Last_X (Plan, 0) and then Y <= KL.Last_Y (Plan, 0);
   --  Follows a candidate at (X, Y) of level From down to level 0 (the
   --  best of the 5 x 5 positions around twice the position on each finer
   --  level, then uphill on level 0 when From > 0) and gives its score
   --  there.

   ---------------------------------------------------------------------
   --  Matches
   ---------------------------------------------------------------------

   type Match is record
      X, Y     : Position := 0;
      Offset_X : KC.Offset := 0.0;
      Offset_Y : KC.Offset := 0.0;
      Score    : KC.Score_Value := 0.0;
      Contrast : KC.Contrast_Value := 0.0;
   end record;
   --  A match at full resolution: its whole-pixel position, its sub-pixel
   --  offset, its score and its contrast.

   type Match_Array is array (Natural range <>) of Match;
   type Match_Array_Access is access Match_Array;

   procedure Allocate_Matches
     (Count : Positive;
      Items : out Match_Array_Access)
   with
     Global => null,
     Post   => (if Items /= null
                then Items'First = 0 and then Items'Last = Count - 1);
   --  A new array of Count matches (the record's defaults), or null.
   --  Trusted as above.

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
   with
     Pre  => KL.Matches (Plan, Image, Sums, Pattern, Care)
             and then Candidates'First = 0
             and then Candidates'Last < Natural'Last
             and then Found <= Candidates'Last + 1
             and then Matches'First = 0 and then Matches'Last >= 0
             and then Matches'Last < Natural'Last
             and then Sure'First = 0 and then Sure'Last = Max_Results - 1,
     Post => Count <= Matches'Last + 1;
   --  Follows Candidates (0 .. Found - 1) in their order down to level 0
   --  and keeps in Matches (0 .. Count - 1), best first, those scoring at
   --  least Accept_At (at whole-pixel positions: offsets and contrasts
   --  0); stops once Max_Results matches that do not overlap each other
   --  score at least Confident (kept in Sure).

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
   with
     Pre => KL.Matches (Plan, Image, Sums, Pattern, Care)
            and then X <= KL.Last_X (Plan, 0)
            and then Y <= KL.Last_Y (Plan, 0);
   --  The scores of (X, Y) and of the positions up to two away on level
   --  0, and which of them are positions (the others score 0).

   function Overlaps
     (A, B          : Match;
      Width, Height : KL.Side;
      Limit         : KC.Score_Value) return Boolean;
   --  The windows of A and B (Width x Height at their sub-pixel
   --  positions) share more than Limit of the window's area, or A and B
   --  lie at the same whole-pixel position.

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
   with
     Pre  => Matches'First = 0 and then Matches'Last < Natural'Last
             and then Count <= Matches'Last + 1
             and then Chosen'First = 0
             and then Chosen'Last = Max_Results - 1,
     Post => Taken <= Max_Results
             and then (for all I in 0 .. Taken - 1 =>
                         Chosen (I).Score >= Accept_At)
             and then (for all I in 0 .. Taken - 2 =>
                         Chosen (I).Score >= Chosen (I + 1).Score);
   --  The results among Matches (0 .. Count - 1), best first: each match
   --  in turn unless it overlaps one already chosen (Overlaps with
   --  XY_Overlap), until Max_Results are chosen (Chosen (0 .. Taken - 1)).

end AMV.Kernels.CNL_Search.Search;
