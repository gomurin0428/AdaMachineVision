--  Convolve3x3 and ConvolveNxM of AMV.Kernels.IP_One_Image: a kernel of
--  reals applied around each pixel (as written, see the parent package),
--  the sum rounded and limited to 0 .. 255. Both work on a kernel in the
--  layout of ConvolveNxM (cell (Col, Row) at Row * Max_Convolve_Size +
--  Col) whose values carry their bound in their subtype. Internal.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.IP_One_Image.Common;

private package AMV.Kernels.IP_One_Image.Convolution
  with SPARK_Mode, Preelaborate
is

   subtype Kernel_Value is Long_Float
     range -Max_Kernel_Value .. Max_Kernel_Value;

   type Bounded_Kernel is array (0 .. Max_Convolve_Values - 1)
     of Kernel_Value;
   --  A kernel whose values are within the bound (the entry points check
   --  the values the operators use; the others are read through a limit
   --  when the kernel is built).

   Sum_Limit : constant := 2.0**36;
   --  A sum of at most Max_Convolve_Values terms of at most
   --  Max_Kernel_Value * 255 (about 5.7E10) stays below it.

   type Window is record
      Width, Height : Int32;
      Origin_X      : Int32;
      Origin_Y      : Int32;
   end record;
   --  The kernel's size and the cell whose result it is.

   function Valid_Window (Win : Window) return Boolean is
     (Win.Width in 1 .. Max_Convolve_Size
      and then Win.Height in 1 .. Max_Convolve_Size
      and then Win.Origin_X in 0 .. Win.Width - 1
      and then Win.Origin_Y in 0 .. Win.Height - 1);

   function Convolution_Sum
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Kernel : Bounded_Kernel;
      Win    : Window;
      X, Y   : Natural) return Long_Float
   with
     Pre  => Common.Usable (Source) and then Valid_Window (Win)
             and then X < Natural (Source.Width)
             and then Y < Natural (Source.Height),
     Post => Convolution_Sum'Result >= -Sum_Limit
             and then Convolution_Sum'Result <= Sum_Limit;
   --  The sum over the kernel's cells (Col, Row) of Kernel (Row *
   --  Max_Convolve_Size + Col) times the pixel (X + Col - Origin_X, Y +
   --  Row - Origin_Y), reflected at the border.

   function Limit_Value (V : Long_Float) return Kernel_Value is
     (if V >= -Max_Kernel_Value
      then (if V <= Max_Kernel_Value then V else Max_Kernel_Value)
      else -Max_Kernel_Value);
   --  V limited to the bound (-Max_Kernel_Value for a NaN, which the
   --  checks exclude).

   function To_Bounded (Kernel : Convolve_NxM_Kernel) return Bounded_Kernel
   is
     ([for I in Bounded_Kernel'Range => Limit_Value (Kernel (I))]);
   --  The values limited to the bound (they already are within it).

   function From_3x3 (Kernel : Convolve_3x3_Kernel) return Bounded_Kernel
   is
     ([for I in Bounded_Kernel'Range =>
         (if I mod Max_Convolve_Size < 3 and then I / Max_Convolve_Size < 3
          then Limit_Value
                 (Kernel (3 * (I / Max_Convolve_Size)
                          + I mod Max_Convolve_Size))
          else 0.0)]);
   --  The 3 x 3 kernel in the layout of ConvolveNxM, limited likewise.

   procedure Convolve
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Kernel : Bounded_Kernel;
      Win    : Window;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Valid_Window (Win),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X)
                               = (if Common.Selected (Region, Whole, X, Y)
                                  then Common.To_Grey
                                         (Convolution_Sum
                                            (Source, Kernel, Win, X, Y))
                                  else Source.Pixels (Y, X))))
                else Result = null);
   --  Gold: every selected pixel is the convolution sum rounded and
   --  limited to 0 .. 255, every other one the input pixel.

end AMV.Kernels.IP_One_Image.Convolution;
