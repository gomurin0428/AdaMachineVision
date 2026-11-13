--  The tool framework: the counterparts of ICogTool, ICogRunStatus and
--  CogToolResultConstants.
--
--  A concrete tool is a public record extension of Ks_Tool that declares
--  its inputs (Input_Image, Region, Run_Params, ...) and its Results as
--  components, and overrides Execute and Reset_Results:
--
--     type Ks_Blob_Tool is new AMV.Tools.Ks_Tool with record
--        Input_Image : AMV.Images.Ks_Image_8_Grey;
--        ...
--        Results     : Ks_Blob_Results;
--     end record;
--
--     overriding procedure Execute (Tool : in out Ks_Blob_Tool);
--     overriding procedure Reset_Results (Tool : in out Ks_Blob_Tool);
--
--  Execute calls the tool's kernel (AMV.Kernels.<tool>, which holds all of
--  the tool's logic and checks its inputs, docs/handoff/TOOLS_PLAN.md) and
--  AMV.Checks.Check on its status. Users call Run (class-wide), never
--  Execute:
--
--     Tool.Input_Image := Image;
--     Tool.Run;
--     if Tool.Run_Status.Result = Accept_Result then ...

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

private with Ada.Strings.Unbounded;

package AMV.Tools is

   type Ks_Tool_Result_Constants is (Accept_Result, Warning, Reject, Error);
   --  Accept_Result is VisionPro's "Accept" ("accept" is an Ada reserved
   --  word). Error means the tool could not run; Reject and Warning are
   --  set by tools that judge their own results.

   ---------------------------------------------------------------------
   --  ICogRunStatus
   ---------------------------------------------------------------------

   type Ks_Run_Status is tagged private;
   --  Default: Accept_Result, empty message, zero time. A tool that never
   --  ran reports this default.

   function Result (Status : Ks_Run_Status) return Ks_Tool_Result_Constants;
   function Message (Status : Ks_Run_Status) return String;
   --  Why the result is not Accept_Result, or the note that Execute gave
   --  to Set_Result together with Accept_Result; "" when there is neither.
   function Exception_Name (Status : Ks_Run_Status) return String;
   --  Fully qualified name of the exception that made the run fail (for
   --  example "AMV.KS_BAD_PARAMETER_EXCEPTION"); "" when none.
   function Processing_Time (Status : Ks_Run_Status) return Real;
   --  Duration of the last Run in milliseconds.

   ---------------------------------------------------------------------
   --  ICogTool
   ---------------------------------------------------------------------

   type Ks_Tool is abstract tagged private;

   function Name (Tool : Ks_Tool) return String;
   procedure Set_Name (Tool : in out Ks_Tool; Value : String);
   --  A user label; "" by default. Not interpreted.

   function Run_Status (Tool : Ks_Tool'Class) return Ks_Run_Status;

   procedure Run (Tool : in out Ks_Tool'Class);
   --  Runs the tool: resets the run status, calls Reset_Results, then
   --  Execute, and records the elapsed time. Any exception raised by
   --  Execute is caught: Run_Status becomes Error with the exception's
   --  message (its name when the message is empty) and name, and
   --  Reset_Results is called again so that no partial results remain.
   --  An exception from the first Reset_Results call is reported the same
   --  way (Execute is then skipped); one from the second call is ignored,
   --  so the status keeps describing the original failure. The elapsed
   --  time is recorded on success and on failure. Run never propagates an
   --  exception.

   procedure Execute (Tool : in out Ks_Tool) is abstract;
   --  The tool's work, implemented by each tool: it passes the inputs to
   --  the tool's kernel, which validates them and reports unusable ones
   --  with a failure that names the property (AMV.Checks turns it into
   --  the AMV exception). Do not call it directly; call Run.

   procedure Reset_Results (Tool : in out Ks_Tool) is null;
   --  Clears the tool's results. Called by Run before Execute and again
   --  when Execute raises an exception.

   procedure Set_Result
     (Tool    : in out Ks_Tool'Class;
      Result  : Ks_Tool_Result_Constants;
      Message : String := "");
   --  For use inside Execute: report Warning or Reject (or Accept_Result
   --  with a note). Run keeps the last value set; Error is normally set by
   --  raising an exception instead. Sets Result and Message and clears
   --  Exception_Name. Run clears the results only when Execute raises, so
   --  an Execute that reports Error through Set_Result keeps whatever
   --  results it left: it must clear them itself (or raise instead).

private

   type Ks_Run_Status is tagged record
      Result          : Ks_Tool_Result_Constants := Accept_Result;
      Message         : Ada.Strings.Unbounded.Unbounded_String;
      Exception_Name  : Ada.Strings.Unbounded.Unbounded_String;
      Processing_Time : Real := 0.0;
   end record;

   type Ks_Tool is abstract tagged record
      Name   : Ada.Strings.Unbounded.Unbounded_String;
      Status : Ks_Run_Status;
   end record;

end AMV.Tools;
