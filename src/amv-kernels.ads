--  The root of the SPARK kernels.
--
--  All of the library's logic lives in the kernels (AMV.Kernels and its
--  children), which are written in SPARK and proved free of run-time
--  errors with gnatprove. A kernel's entry points (the subprograms declared
--  in the visible part of a kernel package with Export and Convention C)
--  are at the same time the library's C API, declared in include/amv.h.
--  The Ada API (AMV.Misc, AMV.Transforms, ...) only calls the entry points
--  and turns a failed status into the corresponding Ks_ exception. See
--  docs/DESIGN.md section 9 for the rules every kernel follows.
--
--  Every entry point:
--
--  * uses only C-compatible types: Long_Float (C double), Int32 / Int64,
--    the unsigned types of Interfaces, records with Convention C, and
--    owned access types for handles. No Boolean (0 and 1 in an Int32) and
--    no enumeration (an Int32 code, checked before it is converted);
--  * has no precondition and checks every input itself, including that a
--    Long_Float is finite and within the bounds the kernel documents;
--  * reports success or failure through an out parameter of type
--    Ks_Status and never raises (apart from Storage_Error when memory or
--    stack runs out, which the trusted allocation helpers turn into
--    Out_Of_Memory where they are used).

pragma Validity_Checks ("F");
--  Floating-point validity checks stay off in the kernels, so that a NaN
--  or an infinity reaches the range checks of an entry point (and becomes
--  Bad_Parameter) instead of raising Constraint_Error at the call.

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);
--  Contracts other than preconditions are proved by gnatprove rather than
--  executed, even in the test build (-gnata). Preconditions of internal
--  subprograms stay checked as a cheap second line of defence.

package AMV.Kernels with SPARK_Mode, Pure is

   type Int32 is range -2**31 .. 2**31 - 1 with Size => 32;
   --  C int32_t.

   type Int64 is range -2**63 .. 2**63 - 1 with Size => 64;
   --  C int64_t.

   False_Value : constant Int32 := 0;
   True_Value  : constant Int32 := 1;
   --  How a Boolean crosses the C API. An entry point that receives a
   --  flag rejects any other value with Bad_Parameter.

   ---------------------------------------------------------------------
   --  Status
   ---------------------------------------------------------------------

   --  Failure codes, one per Ks_ exception of the Ada API (see AMV), plus
   --  Out_Of_Memory and Index_Out_Of_Range. C: the KS_FAILURE_* constants
   --  of include/amv.h.

   Failure_None                          : constant Int32 := 0;
   Failure_Image_No_Pixels               : constant Int32 := 1;
   Failure_Image_Bad_Selected_Space_Name : constant Int32 := 2;
   Failure_Operator_Not_Trained          : constant Int32 := 3;
   Failure_Transform_Singular            : constant Int32 := 4;
   Failure_Image_File                    : constant Int32 := 5;
   Failure_Bad_Parameter                 : constant Int32 := 6;
   Failure_Out_Of_Memory                 : constant Int32 := 7;
   Failure_Other                         : constant Int32 := 8;
   Failure_Index_Out_Of_Range            : constant Int32 := 9;
   --  Failure_Other corresponds to Ks_Exception. Failure_Index_Out_Of_Range
   --  is an index beyond a collection (Space_Name (Index), ...), which the
   --  Ada API reports with Constraint_Error, as .NET does with
   --  ArgumentOutOfRangeException.

   subtype Failure_Code is Int32
     range Failure_None .. Failure_Index_Out_Of_Range;

   Max_Message_Length : constant := 200;

   type Message_Text is array (1 .. Max_Message_Length + 1) of Character
     with Convention => C;
   --  A message of Length characters followed by NUL characters, so that
   --  C code may also read it as a NUL-terminated string.

   type Ks_Status is record
      Failure : Int32 := Failure_None;
      Length  : Int32 := 0;
      Message : Message_Text := [others => ASCII.NUL];
   end record
     with Convention => C, Size => 212 * 8;

   for Ks_Status use record
      Failure at 0 range 0 .. 31;
      Length  at 4 range 0 .. 31;
      Message at 8 range 0 .. 8 * (Max_Message_Length + 1) - 1;
   end record;
   --  The layout of ks_status in include/amv.h (212 bytes with the
   --  padding after Message).

   --  The outcome of an entry point. Failure is one of the codes above;
   --  when it is not Failure_None, Message (1 .. Length) says what went
   --  wrong in the VisionPro style, naming the property or argument at
   --  fault (for example "RunParams.ContrastThreshold must be >= 0").
   --  Length is always in 0 .. Max_Message_Length. C: ks_status.

   function Valid (Status : Ks_Status) return Boolean is
     (Status.Failure in Failure_Code
      and then Status.Length in 0 .. Max_Message_Length);
   --  What every entry point guarantees about the status it returns.

   function Succeeded (Status : Ks_Status) return Boolean is
     (Status.Failure = Failure_None);

   procedure Set_Success (Status : out Ks_Status)
   with
     Post => Valid (Status) and then Succeeded (Status)
             and then Status.Length = 0;
   --  The status of a successful call.

   procedure Set_Failure
     (Status  : out Ks_Status;
      Failure : Failure_Code;
      Message : String)
   with
     Pre  => Failure /= Failure_None,
     Post => Valid (Status) and then Status.Failure = Failure;
   --  The status of a failed call. Message is truncated to
   --  Max_Message_Length characters.

   ---------------------------------------------------------------------
   --  Version of the C ABI
   ---------------------------------------------------------------------

   ABI_Version : constant := 3;
   --  Raised whenever a change makes existing C callers incompatible: a
   --  changed record layout, a changed parameter list, or a changed
   --  meaning. Records only ever grow at their end between versions that
   --  stay compatible.

   function Get_ABI_Version return Int32
   with
     Export, Convention => C, External_Name => "ks_abi_version",
     Post => Get_ABI_Version'Result = ABI_Version;
   --  C: int32_t ks_abi_version (void).

end AMV.Kernels;
