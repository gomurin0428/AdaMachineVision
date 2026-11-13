--  Tests for AMV.Tools: the Run framework, Run_Status, Set_Result and the
--  tool name; and for AMV.Shared_Handles, the holder of tool results.

with Ada.Exceptions;
with Ada.Streams.Storage.Unbounded;
with Ada.Strings.Fixed;
with Ada.Text_IO;
with Ada.Unchecked_Deallocation;

with AMV;
with AMV.Shared_Handles;
with AMV.Tools;
with AMV_Test_Support;

procedure Test_Tools is

   use AMV;
   use AMV.Tools;
   use AMV_Test_Support;

   ---------------------------------------------------------------------
   --  Tool types used by the tests
   ---------------------------------------------------------------------

   package Fake_Tools is

      Custom_Error : exception;

      type Counting_Tool is new Ks_Tool with record
         Results        : Integer := 0;
         --  Stands in for a tool's Results; Execute sets it.
         Reset_Calls    : Natural := 0;
         Execute_Calls  : Natural := 0;
         Seen_At_Start  : Integer := -1;
         --  Results as Execute found it (shows Reset_Results ran first).
         Status_At_Start : Ks_Tool_Result_Constants := Error;
         --  Run_Status.Result as Execute found it.
         Fail_Reset_On  : Natural := 0;
         --  When non-zero, Reset_Results raises Program_Error on that
         --  call number (counted over the tool's lifetime).
         Delay_Seconds  : Duration := 0.0;
      end record;
      --  Succeeds with Accept_Result and Results = 42, and records every
      --  call to Reset_Results.

      overriding procedure Execute (Tool : in out Counting_Tool);
      overriding procedure Reset_Results (Tool : in out Counting_Tool);

      procedure Begin_Execute (Tool : in out Counting_Tool'Class);
      --  Bookkeeping shared by every Execute below.

      type Warning_Tool is new Counting_Tool with null record;
      --  Succeeds, but reports Warning through Set_Result.
      overriding procedure Execute (Tool : in out Warning_Tool);

      type Last_Wins_Tool is new Counting_Tool with null record;
      --  Calls Set_Result twice; Run must keep the second value.
      overriding procedure Execute (Tool : in out Last_Wins_Tool);

      type Note_Tool is new Counting_Tool with null record;
      --  Accept_Result with a note, then Accept_Result with no message.
      overriding procedure Execute (Tool : in out Note_Tool);

      type AMV_Failure_Tool is new Counting_Tool with null record;
      --  Writes partial results and a Warning, then raises an AMV
      --  exception.
      overriding procedure Execute (Tool : in out AMV_Failure_Tool);

      type Constraint_Failure_Tool is new Counting_Tool with record
         Index : Integer := 11;
      end record;
      --  Fails with a genuine index check (Constraint_Error).
      overriding procedure Execute (Tool : in out Constraint_Failure_Tool);

      type Empty_Message_Tool is new Counting_Tool with null record;
      --  Raises Constraint_Error with an empty message.
      overriding procedure Execute (Tool : in out Empty_Message_Tool);

      type Custom_Failure_Tool is new Counting_Tool with null record;
      --  Raises an exception declared outside AMV.
      overriding procedure Execute (Tool : in out Custom_Failure_Tool);

      type No_Pixels_Tool is new Counting_Tool with null record;
      --  Fails as a tool does whose kernel finds no pixels in its
      --  "InputImage".
      overriding procedure Execute (Tool : in out No_Pixels_Tool);

   end Fake_Tools;

   package body Fake_Tools is

      procedure Begin_Execute (Tool : in out Counting_Tool'Class) is
      begin
         Tool.Execute_Calls := Tool.Execute_Calls + 1;
         Tool.Seen_At_Start := Tool.Results;
         Tool.Status_At_Start := Result (Tool.Run_Status);
         if Tool.Delay_Seconds > 0.0 then
            delay Tool.Delay_Seconds;
         end if;
      end Begin_Execute;

      overriding procedure Execute (Tool : in out Counting_Tool) is
      begin
         Begin_Execute (Tool);
         Tool.Results := 42;
      end Execute;

      overriding procedure Reset_Results (Tool : in out Counting_Tool) is
      begin
         Tool.Reset_Calls := Tool.Reset_Calls + 1;
         Tool.Results := 0;
         if Tool.Reset_Calls = Tool.Fail_Reset_On then
            raise Program_Error with "reset failed";
         end if;
      end Reset_Results;

      overriding procedure Execute (Tool : in out Warning_Tool) is
      begin
         Begin_Execute (Tool);
         Tool.Results := 7;
         Tool.Set_Result (Warning, "contrast is low");
      end Execute;

      overriding procedure Execute (Tool : in out Last_Wins_Tool) is
      begin
         Begin_Execute (Tool);
         Tool.Results := 3;
         Tool.Set_Result (Warning, "first");
         Tool.Set_Result (Reject, "second");
      end Execute;

      overriding procedure Execute (Tool : in out Note_Tool) is
      begin
         Begin_Execute (Tool);
         Tool.Results := 5;
         Tool.Set_Result (Accept_Result, "just a note");
         if Message (Tool.Run_Status) /= "just a note" then
            raise Program_Error with "note not visible inside Execute";
         end if;
         Tool.Set_Result (Accept_Result);
      end Execute;

      overriding procedure Execute (Tool : in out AMV_Failure_Tool) is
      begin
         Begin_Execute (Tool);
         Tool.Results := 99;
         Tool.Set_Result (Warning, "partial");
         raise AMV.Ks_Bad_Parameter_Exception with
           "RunParams.Threshold must be >= 0";
      end Execute;

      overriding procedure Execute (Tool : in out Constraint_Failure_Tool)
      is
         Table : constant array (1 .. 10) of Integer := [others => 1];
      begin
         Begin_Execute (Tool);
         Tool.Results := 17;
         Tool.Results := Table (Tool.Index);
      end Execute;

      overriding procedure Execute (Tool : in out Empty_Message_Tool) is
      begin
         Begin_Execute (Tool);
         Tool.Results := 8;
         raise Constraint_Error with "";
      end Execute;

      overriding procedure Execute (Tool : in out Custom_Failure_Tool) is
      begin
         Begin_Execute (Tool);
         Tool.Results := 9;
         raise Custom_Error with "custom failure";
      end Execute;

      overriding procedure Execute (Tool : in out No_Pixels_Tool) is
      begin
         Begin_Execute (Tool);
         Tool.Results := 10;
         raise Ks_Image_No_Pixels_Exception with "InputImage has no pixels";
      end Execute;

   end Fake_Tools;

   use Fake_Tools;

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   procedure Run_Safely (Tool : in out Ks_Tool'Class; Description : String);
   --  Runs Tool and checks that Run did not propagate an exception.

   procedure Run_Safely (Tool : in out Ks_Tool'Class; Description : String)
   is
   begin
      Tool.Run;
      Check (True, Description & ": Run returned normally");
   exception
      when E : others =>
         Fail (Description & ": Run propagated "
               & Ada.Exceptions.Exception_Name (E) & ": "
               & Ada.Exceptions.Exception_Message (E));
   end Run_Safely;

   procedure Check_Status
     (Status         : Ks_Run_Status;
      Expected       : Ks_Tool_Result_Constants;
      Message_Text   : String;
      Exception_Text : String;
      Description    : String);
   --  Checks Result, Message and Exception_Name, and that the processing
   --  time is a plausible non-negative number of milliseconds.

   procedure Check_Status
     (Status         : Ks_Run_Status;
      Expected       : Ks_Tool_Result_Constants;
      Message_Text   : String;
      Exception_Text : String;
      Description    : String) is
   begin
      Check (Result (Status) = Expected,
             Description & ": Result = " & Expected'Image
             & " (got " & Result (Status)'Image & ")");
      Check (Message (Status) = Message_Text,
             Description & ": Message = """ & Message_Text & """ (got """
             & Message (Status) & """)");
      Check (Exception_Name (Status) = Exception_Text,
             Description & ": Exception_Name = """ & Exception_Text
             & """ (got """ & Exception_Name (Status) & """)");
      Check (Processing_Time (Status) >= 0.0
             and then Processing_Time (Status) < 10_000.0,
             Description & ": Processing_Time in [0, 10 s)");
   end Check_Status;

   ---------------------------------------------------------------------
   --  Tests
   ---------------------------------------------------------------------

   procedure Test_Defaults is
      Tool   : Counting_Tool;
      Status : Ks_Run_Status;
   begin
      Section ("defaults");
      Check (Result (Status) = Accept_Result, "default status Accept_Result");
      Check (Message (Status) = "", "default status message empty");
      Check (Exception_Name (Status) = "", "default exception name empty");
      Check_Near (Processing_Time (Status), 0.0, 0.0,
                  "default processing time");

      Check (Result (Tool.Run_Status) = Accept_Result,
             "never-run tool reports Accept_Result");
      Check (Message (Tool.Run_Status) = "", "never-run tool: no message");
      Check (Exception_Name (Tool.Run_Status) = "",
             "never-run tool: no exception name");
      Check_Near (Processing_Time (Tool.Run_Status), 0.0, 0.0,
                  "never-run tool: zero time");
      Check (Tool.Name = "", "default name is empty");
      Check (Tool.Reset_Calls = 0 and then Tool.Execute_Calls = 0,
             "nothing called before Run");
   end Test_Defaults;

   procedure Test_Name is
      Tool : Counting_Tool;
   begin
      Section ("name");
      Tool.Set_Name ("Blob tool 1");
      Check (Tool.Name = "Blob tool 1", "Set_Name / Name round trip");
      Run_Safely (Tool, "run named tool");
      Check (Tool.Name = "Blob tool 1", "Run keeps the name");
      Tool.Set_Name ("");
      Check (Tool.Name = "", "name can be cleared");
   end Test_Name;

   procedure Test_Success is
      Tool : Counting_Tool;
   begin
      Section ("successful run");
      Tool.Results := 1234;   --  stale results from an imaginary earlier run
      Run_Safely (Tool, "counting tool");
      Check (Tool.Reset_Calls = 1, "Reset_Results called once");
      Check (Tool.Execute_Calls = 1, "Execute called once");
      Check (Tool.Seen_At_Start = 0, "results reset before Execute");
      Check (Tool.Results = 42, "results kept after success");
      Check_Status (Tool.Run_Status, Accept_Result, "", "", "counting tool");

      Run_Safely (Tool, "counting tool again");
      Check (Tool.Reset_Calls = 2 and then Tool.Execute_Calls = 2,
             "second run calls Reset_Results and Execute once more");
      Check (Tool.Results = 42, "results after second run");
   end Test_Success;

   procedure Test_Warning is
      Tool  : Warning_Tool;
      Last  : Last_Wins_Tool;
      Note  : Note_Tool;
   begin
      Section ("Set_Result");
      Run_Safely (Tool, "warning tool");
      Check_Status (Tool.Run_Status, Warning, "contrast is low", "",
                    "warning tool");
      Check (Tool.Results = 7, "warning tool keeps its results");
      Check (Tool.Reset_Calls = 1, "warning tool: one Reset_Results");
      Check (Tool.Status_At_Start = Accept_Result,
             "status is Accept_Result when Execute starts");

      --  The next run starts from a clean status again.
      Run_Safely (Tool, "warning tool rerun");
      Check (Tool.Status_At_Start = Accept_Result,
             "previous Warning cleared before Execute");
      Check_Status (Tool.Run_Status, Warning, "contrast is low", "",
                    "warning tool rerun");

      Run_Safely (Last, "last wins tool");
      Check_Status (Last.Run_Status, Reject, "second", "", "last wins tool");

      Run_Safely (Note, "note tool");
      Check_Status (Note.Run_Status, Accept_Result, "", "",
                    "note tool (default message is empty)");
      Check (Note.Results = 5, "note tool results");

      --  Set_Result outside Run simply records the value and clears any
      --  exception name.
      declare
         Failing : AMV_Failure_Tool;
      begin
         Run_Safely (Failing, "failing tool before Set_Result");
         Failing.Set_Result (Reject, "manual");
         Check_Status (Failing.Run_Status, Reject, "manual", "",
                       "Set_Result clears Exception_Name");
      end;
   end Test_Warning;

   procedure Test_AMV_Failure is
      Tool : AMV_Failure_Tool;
   begin
      Section ("AMV exception in Execute");
      Run_Safely (Tool, "AMV failure tool");
      Check_Status (Tool.Run_Status, Error,
                    "RunParams.Threshold must be >= 0",
                    "AMV.KS_BAD_PARAMETER_EXCEPTION", "AMV failure tool");
      Check (Tool.Execute_Calls = 1, "Execute called once");
      Check (Tool.Reset_Calls = 2,
             "Reset_Results called before and after the failure");
      Check (Tool.Results = 0, "partial results cleared after failure");

      --  Running the failing tool again gives the same, freshly recorded
      --  failure (not a doubled message or stale counts).
      Run_Safely (Tool, "AMV failure tool rerun");
      Check_Status (Tool.Run_Status, Error,
                    "RunParams.Threshold must be >= 0",
                    "AMV.KS_BAD_PARAMETER_EXCEPTION",
                    "AMV failure tool rerun");
      Check (Tool.Reset_Calls = 4 and then Tool.Execute_Calls = 2,
             "rerun: two more Reset_Results calls, one more Execute");
   end Test_AMV_Failure;

   procedure Test_Constraint_Failure is
      Tool  : Constraint_Failure_Tool;
      Empty : Empty_Message_Tool;
      Other : Custom_Failure_Tool;
   begin
      Section ("Constraint_Error in Execute");
      Run_Safely (Tool, "index check failure");
      Check (Result (Tool.Run_Status) = Error, "index failure: Error");
      Check (Exception_Name (Tool.Run_Status) = "CONSTRAINT_ERROR",
             "index failure: Exception_Name = CONSTRAINT_ERROR (got """
             & Exception_Name (Tool.Run_Status) & """)");
      Check (Message (Tool.Run_Status) /= "",
             "index failure: Message carries the runtime's text");
      Check (Ada.Strings.Fixed.Index (Message (Tool.Run_Status), "index")
             > 0,
             "index failure: Message mentions the index check (got """
             & Message (Tool.Run_Status) & """)");
      Check (Tool.Results = 0, "index failure: results cleared");
      Check (Tool.Reset_Calls = 2, "index failure: two Reset_Results calls");

      --  The same tool succeeds once the index is valid, and the earlier
      --  failure leaves no trace in the status.
      Tool.Index := 3;
      Run_Safely (Tool, "index now valid");
      Check_Status (Tool.Run_Status, Accept_Result, "", "", "index valid");
      Check (Tool.Results = 1, "index valid: results kept");

      Run_Safely (Empty, "empty message failure");
      Check_Status (Empty.Run_Status, Error, "CONSTRAINT_ERROR",
                    "CONSTRAINT_ERROR",
                    "empty message falls back to the exception name");
      Check (Empty.Results = 0, "empty message failure: results cleared");

      Run_Safely (Other, "custom exception");
      Check (Result (Other.Run_Status) = Error, "custom exception: Error");
      Check (Message (Other.Run_Status) = "custom failure",
             "custom exception: message");
      Check (Ada.Strings.Fixed.Tail (Exception_Name (Other.Run_Status), 13)
             = ".CUSTOM_ERROR",
             "custom exception: fully qualified name (got """
             & Exception_Name (Other.Run_Status) & """)");
   end Test_Constraint_Failure;

   procedure Test_Reset_Failures is
      After  : AMV_Failure_Tool;
      Before : Counting_Tool;
      Only   : Counting_Tool;
   begin
      Section ("Reset_Results failures");

      --  Execute fails, then the clean-up Reset_Results fails too: the
      --  status still describes the Execute failure.
      After.Fail_Reset_On := 2;
      Run_Safely (After, "second Reset_Results raises");
      Check_Status (After.Run_Status, Error,
                    "RunParams.Threshold must be >= 0",
                    "AMV.KS_BAD_PARAMETER_EXCEPTION",
                    "second Reset_Results raises");
      Check (After.Reset_Calls = 2, "both Reset_Results calls happened");

      --  The first Reset_Results fails: Execute is skipped and the reset
      --  failure is reported; the clean-up call is still attempted.
      Before.Fail_Reset_On := 1;
      Before.Results := 55;
      Run_Safely (Before, "first Reset_Results raises");
      Check_Status (Before.Run_Status, Error, "reset failed",
                    "PROGRAM_ERROR", "first Reset_Results raises");
      Check (Before.Execute_Calls = 0, "Execute skipped");
      Check (Before.Reset_Calls = 2, "clean-up Reset_Results attempted");
      Check (Before.Results = 0, "results cleared by the clean-up call");

      --  Reset_Results fails on a successful tool's clean-up call number:
      --  irrelevant, since a successful run calls it only once.
      Only.Fail_Reset_On := 2;
      Run_Safely (Only, "success with later failing reset");
      Check_Status (Only.Run_Status, Accept_Result, "", "",
                    "success with later failing reset");
      --  Its second run hits the failing call before Execute.
      Run_Safely (Only, "second run, reset raises");
      Check_Status (Only.Run_Status, Error, "reset failed", "PROGRAM_ERROR",
                    "second run, reset raises");
      Check (Only.Execute_Calls = 1, "second run skipped Execute");
      Check (Only.Reset_Calls = 3, "three Reset_Results calls in total");
   end Test_Reset_Failures;

   procedure Test_No_Pixels is
      Tool : No_Pixels_Tool;
   begin
      Section ("a tool without pixels");
      Run_Safely (Tool, "tool without input image");
      Check_Status (Tool.Run_Status, Error, "InputImage has no pixels",
                    "AMV.KS_IMAGE_NO_PIXELS_EXCEPTION",
                    "tool without input image");
      Check (Tool.Results = 0, "no results without input image");
   end Test_No_Pixels;

   procedure Test_Timing is
      Slow        : Counting_Tool;
      Slow_Failed : AMV_Failure_Tool;
   begin
      Section ("processing time");
      Slow.Delay_Seconds := 0.03;
      Run_Safely (Slow, "slow tool");
      Check (Processing_Time (Slow.Run_Status) >= 27.0,
             "slow tool: at least about 30 ms (got"
             & Real'Image (Processing_Time (Slow.Run_Status)) & ")");
      Check (Processing_Time (Slow.Run_Status) < 5_000.0,
             "slow tool: under 5 s");

      Slow_Failed.Delay_Seconds := 0.03;
      Run_Safely (Slow_Failed, "slow failing tool");
      Check (Result (Slow_Failed.Run_Status) = Error,
             "slow failing tool: Error");
      Check (Processing_Time (Slow_Failed.Run_Status) >= 27.0,
             "time is recorded on failure too (got"
             & Real'Image (Processing_Time (Slow_Failed.Run_Status)) & ")");

      --  A fast run afterwards reports a fresh (small) time.
      Slow.Delay_Seconds := 0.0;
      Run_Safely (Slow, "fast rerun");
      Check (Processing_Time (Slow.Run_Status) < 27.0,
             "fast rerun reports its own time (got"
             & Real'Image (Processing_Time (Slow.Run_Status)) & ")");
   end Test_Timing;

   procedure Test_Class_Wide is
      type Tool_Access is access all Ks_Tool'Class;
      Warn : aliased Warning_Tool;
      Fail_Tool : aliased AMV_Failure_Tool;
      Tools : constant array (1 .. 2) of Tool_Access :=
        [Warn'Access, Fail_Tool'Access];
      Expected : constant array (1 .. 2) of Ks_Tool_Result_Constants :=
        [Warning, Error];
   begin
      Section ("dispatching through Ks_Tool'Class");
      for I in Tools'Range loop
         Run_Safely (Tools (I).all, "class-wide run" & I'Image);
         Check (Result (Tools (I).Run_Status) = Expected (I),
                "class-wide run" & I'Image & " result");
      end loop;
      Check (Warn.Results = 7 and then Fail_Tool.Results = 0,
             "class-wide runs dispatched to the right Execute");
   end Test_Class_Wide;

   procedure Test_Shared_Handles is
      type Cell is record
         Value : Integer := 0;
      end record;
      type Cell_Access is access Cell;

      Destroyed : Natural := 0;

      procedure Destroy (Handle : in out Cell_Access);
      procedure Destroy (Handle : in out Cell_Access) is
         procedure Free is new Ada.Unchecked_Deallocation
           (Cell, Cell_Access);
      begin
         if Handle /= null then
            Destroyed := Destroyed + 1;
            Free (Handle);
         end if;
      end Destroy;

      package Holders is new AMV.Shared_Handles (Cell_Access, null, Destroy);
      use Holders;
   begin
      Section ("AMV.Shared_Handles");
      declare
         Empty : Holder;
      begin
         Check (Is_Empty (Empty) and then Get (Empty) = null,
                "a holder is empty by default");
      end;

      declare
         First  : Holder;
         Handle : constant Cell_Access := new Cell'(Value => 7);
      begin
         Set (First, Handle);
         Check (not Is_Empty (First) and then Get (First) = Handle,
                "Set: the holder gives the handle back");
         declare
            Second : constant Holder := First;
         begin
            Check (Get (Second) = Handle and then Get (Second).Value = 7,
                   "a copy shares the handle");
         end;
         Check (Destroyed = 0 and then Get (First).Value = 7,
                "the handle outlives a copy");
         Clear (First);
         Check (Is_Empty (First) and then Destroyed = 1,
                "Clear frees the handle of its last holder");
         Clear (First);
         Check (Destroyed = 1, "Clear on an empty holder frees nothing");
      end;

      Destroyed := 0;
      declare
         First : Holder;
      begin
         Set (First, new Cell'(Value => 1));
         declare
            Second : Holder := First;
         begin
            Set (Second, new Cell'(Value => 2));
            Check (Destroyed = 0 and then Get (First).Value = 1
                   and then Get (Second).Value = 2,
                   "Set on a copy leaves the shared handle to the other");
            Set (Second, null);
            Check (Is_Empty (Second) and then Destroyed = 1,
                   "Set (null) frees the sole handle and empties");
         end;
      end;
      Check (Destroyed = 2, "the last holder going frees the handle");

      Destroyed := 0;
      declare
         Buffer : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Source : Holder;
         Target : Holder;
      begin
         Set (Source, new Cell'(Value => 3));
         Set (Target, new Cell'(Value => 4));
         Holder'Write (Buffer'Access, Source);
         Holder'Read (Buffer'Access, Target);
         Check (Is_Empty (Target) and then Destroyed = 1
                and then Get (Source).Value = 3,
                "a holder reads back from a stream as empty");
      end;
      Check (Destroyed = 2, "streams leak nothing");
   end Test_Shared_Handles;

   procedure Run_All is
   begin
      Test_Defaults;
      Test_Name;
      Test_Success;
      Test_Warning;
      Test_AMV_Failure;
      Test_Constraint_Failure;
      Test_Reset_Failures;
      Test_No_Pixels;
      Test_Timing;
      Test_Class_Wide;
      Test_Shared_Handles;
      Ada.Text_IO.Put_Line ("Test_Tools done");
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Tools;
