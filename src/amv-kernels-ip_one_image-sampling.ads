--  SubSampler and Expand of AMV.Kernels.IP_One_Image (also the sampling of
--  GaussSampler): the operators that change the size of the pixel grid by
--  whole factors. Internal.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.IP_One_Image.Common;

private package AMV.Kernels.IP_One_Image.Sampling
  with SPARK_Mode, Preelaborate
is

   function Sampled (I : Natural; Factor : Int32; N : Int32) return Natural
   with
     Pre  => Factor in 1 .. Max_Sample and then N >= 1
             and then Int64 (I) < Shrunk (Int64 (N), Factor),
     Post => Sampled'Result = I * Natural (Factor)
             and then Sampled'Result < Natural (N);
   --  The input coordinate of output coordinate I of a sampling by Factor
   --  of a line of N pixels: I Factor (within the line).

   function Expanded (I : Natural; Factor : Int32; N : Int32) return Natural
   with
     Pre  => Factor in 1 .. Max_Sample and then N >= 1
             and then Int64 (I) < Int64 (N) * Int64 (Factor),
     Post => Expanded'Result = I / Natural (Factor)
             and then Expanded'Result < Natural (N);
   --  The input coordinate of output coordinate I of an expansion by
   --  Factor of a line of N pixels: I / Factor (integer division).

   procedure Sub_Sample
     (Source  : access constant KI.Ks_Image_8_Grey_Data;
      SX, SY  : Int32;
      Average : Boolean;
      Result  : out KI.Ks_Image_8_Grey;
      Status  : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then SX in 1 .. Max_Sample and then SY in 1 .. Max_Sample,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Usable (Result)
                     and then Int64 (Result.Width)
                                = Shrunk (Int64 (Source.Width), SX)
                     and then Int64 (Result.Height)
                                = Shrunk (Int64 (Source.Height), SY)
                     and then
                       (if not Average
                        then
                          (for all Y in Result.Pixels'Range (1) =>
                             (for all X in Result.Pixels'Range (2) =>
                                Result.Pixels (Y, X)
                                  = Source.Pixels
                                      (Sampled (Y, SY, Source.Height),
                                       Sampled (X, SX, Source.Width)))))
                else Result = null);
   --  Every SX-th pixel along x and SY-th along y (Gold: output pixel (X,
   --  Y) is input pixel (X SX, Y SY)), or with Average the mean of each SX
   --  x SY block (rounded half up; the blocks at the right and bottom
   --  borders are cut at the image's border).

   procedure Expand
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      EX, EY : Int32;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then EX in 1 .. Max_Sample and then EY in 1 .. Max_Sample
             and then Fits ((Grown (Int64 (Source.Width), EX),
                             Grown (Int64 (Source.Height), EY))),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Usable (Result)
                     and then Int64 (Result.Width)
                                = Grown (Int64 (Source.Width), EX)
                     and then Int64 (Result.Height)
                                = Grown (Int64 (Source.Height), EY)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X)
                               = Source.Pixels
                                   (Expanded (Y, EY, Source.Height),
                                    Expanded (X, EX, Source.Width))))
                else Result = null);
   --  Each pixel repeated EX times along x and EY times along y (Gold:
   --  output pixel (X, Y) is input pixel (X / EX, Y / EY)).

end AMV.Kernels.IP_One_Image.Sampling;
