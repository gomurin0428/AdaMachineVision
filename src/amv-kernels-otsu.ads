--  Otsu's threshold on a histogram of grey levels (the counts of the 256
--  levels of an 8-bit image), shared by the Blob tool's
--  HardDynamicThreshold and the histogram result's
--  GetMinimumWGVThreshold. Internal: no entry points of its own.
--
--  Definition (Otsu 1979; the method of the public literature, not a
--  VisionPro algorithm): the threshold T in 1 .. 255 splits the samples
--  into the classes "< T" (n0 samples, sum of grey levels s0) and ">= T"
--  (n1, s1); T maximises the between-class variance n0 n1 (m0 - m1)**2 =
--  (n1 s0 - n0 s1)**2 / (n0 n1), which is the same as minimising the
--  within-group variance (the sum of the squared differences from each
--  class's mean), the total variance being fixed. The smallest such T
--  wins a tie. When no T makes both classes non-empty (fewer than two grey
--  levels present) there is no threshold (No_Split).
--
--  Proved (docs/PROOF.md): absence of run-time errors for any counts, and
--  that the result is No_Split or in 1 .. 255. Not proved (tested against
--  a brute-force search): that T maximises the criterion.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Interfaces;

package AMV.Kernels.Otsu with SPARK_Mode, Preelaborate is

   subtype Grey_8 is Interfaces.Unsigned_8;

   Max_Count : constant := 2**31;
   --  A count never exceeds the pixels of an image (at most 2**31 - 1);
   --  this bound keeps every sum provably small.

   subtype Level_Count is Int64 range 0 .. Max_Count;
   type Level_Counts is array (Grey_8) of Level_Count;
   --  The number of samples of each grey level.

   function Total (Counts : Level_Counts) return Int64
   with Post => Total'Result in 0 .. 256 * Max_Count;
   --  The number of samples.

   function Times_Level (Count : Level_Count; Level : Grey_8) return Int64 is
     (Count * Int64 (Level))
   with Post => Times_Level'Result in 0 .. 255 * Max_Count;
   --  Count * Level.

   function Weighted_Total (Counts : Level_Counts) return Int64
   with Post => Weighted_Total'Result in 0 .. 256 * 255 * Max_Count;
   --  The sum of the grey levels of the samples.

   No_Split : constant Int32 := -1;

   function Threshold (Counts : Level_Counts) return Int32
   with Post => Threshold'Result = No_Split
                or else Threshold'Result in 1 .. 255;
   --  Otsu's threshold (see above), or No_Split.

end AMV.Kernels.Otsu;
