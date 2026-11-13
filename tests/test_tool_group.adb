--  Tests for AMV.Tool_Group (the tool group), AMV.Tool_Block (the tool
--  block and its terminals) and their kernel AMV.Kernels.Tool_Group.
--
--  The groups run small tools declared here (they accept, warn, reject or
--  raise, and record the order they ran in) and, in the block's script, a
--  real tool (the histogram tool). The scripts are nested in this test
--  procedure, so they are stored with 'Unrestricted_Access; a script at
--  library level would use 'Access.

pragma Validity_Checks ("F");
--  The kernel tests pass NaNs on purpose.

with Ada.Calendar;
with Ada.Exceptions;
with Ada.Streams.Storage.Unbounded;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;  use Ada.Strings.Unbounded;
with Ada.Text_IO;

with Interfaces;

with AMV;                    use AMV;
with AMV.Image_Processing.Histogram;
with AMV.Images;             use AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Tool_Group;
with AMV.Shapes;             use AMV.Shapes;
with AMV.Tool_Block;         use AMV.Tool_Block;
with AMV.Tool_Group;         use AMV.Tool_Group;
with AMV.Tools;              use AMV.Tools;
with AMV.Transforms;         use AMV.Transforms;
with AMV_Test_Images;        use AMV_Test_Images;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Tool_Group is

   package KG renames AMV.Kernels.Tool_Group;
   package H renames AMV.Image_Processing.Histogram;

   use type AMV.Kernels.Int32;
   use type AMV.Kernels.Int64;
   use type Interfaces.Unsigned_8;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_64;

   subtype Int32 is AMV.Kernels.Int32;

   ---------------------------------------------------------------------
   --  Test tools
   ---------------------------------------------------------------------

   package Fakes is

      type Tag_Array is array (1 .. 64) of Integer;

      type Journal_Type is record
         Tags   : Tag_Array := [others => 0];
         Length : Natural := 0;
      end record;
      --  The tags of the tools in the order they ran.

      type Journal_Access is access all Journal_Type;

      type Fake_Tool is new Ks_Tool with record
         Journal : Journal_Access;
         Tag     : Integer := 0;
         Outcome : Ks_Tool_Result_Constants := Accept_Result;
         Note    : Unbounded_String;
         Raises  : Boolean := False;
      end record;
      --  Records its tag in Journal, then reports Outcome with Note, or
      --  raises Program_Error with Note. The tools reach the journal
      --  through a component rather than an up-level reference.

      overriding procedure Execute (Tool : in out Fake_Tool);

      type Group_Access is access all Ks_Tool_Group'Class;

      type Mutating_Tool is new Ks_Tool with record
         Target : Group_Access;
      end record;
      --  Disables member 0 of Target (changes the group while it runs).

      overriding procedure Execute (Tool : in out Mutating_Tool);

   end Fakes;

   package body Fakes is

      overriding procedure Execute (Tool : in out Fake_Tool) is
         Journal : Journal_Type renames Tool.Journal.all;
      begin
         if Journal.Length < Journal.Tags'Last then
            Journal.Length := Journal.Length + 1;
            Journal.Tags (Journal.Length) := Tool.Tag;
         end if;
         if Tool.Raises then
            raise Program_Error with To_String (Tool.Note);
         end if;
         Set_Result (Tool, Tool.Outcome, To_String (Tool.Note));
      end Execute;

      overriding procedure Execute (Tool : in out Mutating_Tool) is
      begin
         Tool.Target.Set_Disabled (0, True);
      end Execute;

   end Fakes;

   use Fakes;

   Journal : aliased Journal_Type;

   procedure Clear_Log is
   begin
      Journal.Length := 0;
   end Clear_Log;

   function Log_Length return Natural is (Journal.Length);

   function Logged (Expected : String) return Boolean;
   --  The journal as a list of tags ("1 2 4") equals Expected.

   function Logged (Expected : String) return Boolean is
      Text : Unbounded_String;
   begin
      for I in 1 .. Journal.Length loop
         if I > 1 then
            Append (Text, " ");
         end if;
         Append (Text, Ada.Strings.Fixed.Trim (Journal.Tags (I)'Image,
                                               Ada.Strings.Left));
      end loop;
      if To_String (Text) /= Expected then
         Ada.Text_IO.Put_Line ("  log: """ & To_String (Text)
                               & """, expected """ & Expected & """");
      end if;
      return To_String (Text) = Expected;
   end Logged;

   function Make
     (Tag     : Integer;
      Name    : String;
      Outcome : Ks_Tool_Result_Constants := Accept_Result;
      Note    : String := "";
      Raises  : Boolean := False) return Fake_Tool;

   function Make
     (Tag     : Integer;
      Name    : String;
      Outcome : Ks_Tool_Result_Constants := Accept_Result;
      Note    : String := "";
      Raises  : Boolean := False) return Fake_Tool is
   begin
      return Tool : Fake_Tool do
         Tool.Journal := Journal'Unchecked_Access;
         Tool.Tag := Tag;
         Tool.Outcome := Outcome;
         Tool.Note := To_Unbounded_String (Note);
         Tool.Raises := Raises;
         Tool.Set_Name (Name);
      end return;
   end Make;

   function Raises_Bad_Parameter (Action : access procedure) return Boolean;
   --  Action raises Ks_Bad_Parameter_Exception.

   function Raises_Bad_Parameter (Action : access procedure) return Boolean
   is
   begin
      Action.all;
      return False;
   exception
      when Ks_Bad_Parameter_Exception =>
         return True;
      when others =>
         return False;
   end Raises_Bad_Parameter;

   function Raises_Index_Error (Action : access procedure) return Boolean;
   --  Action raises Constraint_Error.

   function Raises_Index_Error (Action : access procedure) return Boolean is
   begin
      Action.all;
      return False;
   exception
      when Constraint_Error =>
         return True;
      when others =>
         return False;
   end Raises_Index_Error;

   function Contains_Text (Source, Pattern : String) return Boolean is
     (Ada.Strings.Fixed.Index (Source, Pattern) > 0);

   function Repeat (Count : Natural; Item : Character) return String is
     (String'(1 .. Count => Item));

   ---------------------------------------------------------------------
   --  Groups
   ---------------------------------------------------------------------

   procedure Test_Members is
      A     : aliased Fake_Tool := Make (1, "A");
      W     : aliased Fake_Tool := Make (2, "W", Warning, "careful");
      R     : aliased Fake_Tool := Make (3, "R", Reject, "too small");
      X     : aliased Fake_Tool := Make (4, "X", Raises => True,
                                         Note => "boom");
      B     : aliased Fake_Tool := Make (5, "B");
      Group : aliased Ks_Tool_Group;

      procedure Add_A_Again is
      begin
         Group.Add (A'Access);
      end Add_A_Again;

      procedure Add_Itself is
      begin
         Group.Add (Group'Access);
      end Add_Itself;

      procedure Insert_Far is
      begin
         Group.Insert (9, B'Access);
      end Insert_Far;

      procedure Remove_B is
      begin
         Group.Remove (B'Access);
      end Remove_B;

      procedure Item_Far is
         Unused : constant Ks_Tool_Access := Group.Item (7);
      begin
         null;
      end Item_Far;

      procedure Item_Nobody is
         Unused : constant Ks_Tool_Access := Group.Item ("nobody");
      begin
         null;
      end Item_Nobody;

      procedure Remove_Nobody is
      begin
         Group.Remove ("nobody");
      end Remove_Nobody;

      procedure Index_Of_W is
         Unused : constant Integer := Group.Index_Of ("W");
      begin
         null;
      end Index_Of_W;

   begin
      Section ("Tool group: members");
      Check (Group.Count = 0 and then not Group.Abort_Run_On_Tool_Failure,
             "a new group is empty and does not abort");
      Group.Run;
      Check (Group.Run_Status.Result = Accept_Result
             and then Group.Run_Status.Message = "",
             "an empty group accepts");

      Group.Add (A'Access);
      Group.Add (R'Access);
      Group.Insert (1, W'Access);
      Group.Add (X'Access);
      Check (Group.Count = 4, "Count after Add and Insert");
      Check (Group.Item (0) = A'Unchecked_Access
             and then Group.Item (1) = W'Unchecked_Access
             and then Group.Item (2) = R'Unchecked_Access
             and then Group.Item (3) = X'Unchecked_Access,
             "Item follows Add and Insert");
      Check (Group.Index_Of (R'Access) = 2
             and then Group.Index_Of (B'Access) = -1
             and then Group.Contains (X'Access)
             and then not Group.Contains (B'Access),
             "Index_Of and Contains");
      Check (Group.Item ("R") = R'Unchecked_Access
             and then Group.Index_Of ("W") = 1
             and then Group.Index_Of ("B") = -1
             and then Group.Index_Of ("") = -1
             and then Group.Contains ("X")
             and then not Group.Contains ("x"),
             "Item, Index_Of and Contains by name (case-sensitive)");
      W.Set_Name ("Renamed");
      Check (Group.Index_Of ("Renamed") = 1
             and then Group.Index_Of ("W") = -1,
             "a lookup by name reads the members' current names");
      W.Set_Name ("W");
      Check (Raises_Bad_Parameter (Item_Nobody'Access),
             "Item of an unknown name raises Ks_Bad_Parameter_Exception");
      Check (Raises_Bad_Parameter (Remove_Nobody'Access),
             "Remove of an unknown name raises Ks_Bad_Parameter_Exception");
      X.Set_Name ([1 .. 257 => 'x']);
      Check (Raises_Bad_Parameter (Index_Of_W'Access),
             "a member name over 256 characters makes a lookup raise");
      X.Set_Name ("X");
      Check (Raises_Bad_Parameter (Add_A_Again'Access),
             "a tool cannot be added twice");
      Check (Raises_Bad_Parameter (Add_Itself'Access),
             "a group cannot contain itself");
      Check (Raises_Index_Error (Insert_Far'Access),
             "Insert beyond Count raises Constraint_Error");
      Check (Raises_Bad_Parameter (Remove_B'Access),
             "Remove of a tool that is not a member");
      Check (Raises_Index_Error (Item_Far'Access),
             "Item beyond Count raises Constraint_Error");
      Check (Group.Count = 4, "failed changes leave the members");

      --  Every member runs in order; the worst result and the message of
      --  the first member that did not accept.
      Clear_Log;
      Group.Run;
      Check (Logged ("1 2 3 4"), "the members run in order");
      Check (Group.Run_Status.Result = Error,
             "the group reports the worst result (a member raised)");
      Check (Group.Run_Status.Message = "W: careful",
             "the message names the first member that did not accept");
      Check (Group.Run_Status.Exception_Name = "",
             "a member's failure is not the group's exception");
      Check (X.Run_Status.Result = Error
             and then X.Run_Status.Message = "boom",
             "the member that raised has its own Error status");

      --  Abort on failure.
      Group.Add (B'Access);
      Group.Set_Abort_Run_On_Tool_Failure (True);
      Check (Group.Abort_Run_On_Tool_Failure, "Abort_Run_On_Tool_Failure");
      Clear_Log;
      Group.Run;
      Check (Logged ("1 2 3 4"), "abort: the run stops after the error");
      Group.Set_Abort_Run_On_Tool_Failure (False);
      Clear_Log;
      Group.Run;
      Check (Logged ("1 2 3 4 5"), "no abort: every member runs");

      --  Disabled members.
      Group.Set_Disabled (1, True);
      Group.Set_Disabled (3, True);
      Check (Group.Disabled (1) and then not Group.Disabled (2),
             "Disabled");
      Clear_Log;
      Group.Run;
      Check (Logged ("1 3 5"), "disabled members are skipped");
      Check (Group.Run_Status.Result = Reject
             and then Group.Run_Status.Message = "R: too small",
             "the worst of the members that ran");

      --  Move keeps the flag with the member; Remove and Remove_At.
      Group.Move (1, 4);
      Check (Group.Item (4) = W'Unchecked_Access and then Group.Disabled (4)
             and then Group.Item (1) = R'Unchecked_Access
             and then not Group.Disabled (1),
             "Move takes the disabled flag along");
      Group.Move (4, 0);
      Clear_Log;
      Group.Run;
      Check (Logged ("1 3 5"), "the order after Move");
      Group.Remove (R'Access);
      Group.Remove_At (0);
      Check (Group.Count = 3
             and then Group.Item (0) = A'Unchecked_Access
             and then Group.Item (1) = X'Unchecked_Access
             and then Group.Item (2) = B'Unchecked_Access,
             "Remove and Remove_At");
      Check (Group.Disabled (1) and then not Group.Disabled (0),
             "the flags follow the members");
      Group.Set_Disabled (1, False);
      Clear_Log;
      Group.Run;
      Check (Logged ("1 4 5")
             and then Group.Run_Status.Result = Error
             and then Group.Run_Status.Message = "X: boom",
             "the run after the removals");

      Group.Clear;
      Check (Group.Count = 0, "Clear");
   end Test_Members;

   procedure Test_Remove_By_Name is
      P     : aliased Fake_Tool := Make (1, "Same");
      Q     : aliased Fake_Tool := Make (2, "Same");
      S     : aliased Fake_Tool := Make (3, "Other");
      Group : Ks_Tool_Group;
   begin
      Section ("Tool group: members by name");
      Group.Add (P'Access);
      Group.Add (Q'Access);
      Group.Add (S'Access);
      Check (Group.Item ("Same") = P'Unchecked_Access
             and then Group.Index_Of ("Same") = 0,
             "the first of two members with the same name");
      Group.Remove ("Same");
      Check (Group.Count = 2
             and then Group.Item (0) = Q'Unchecked_Access
             and then Group.Item ("Same") = Q'Unchecked_Access,
             "Remove by name removes the first one");
      Group.Move (1, 0);
      Check (Group.Index_Of ("Other") = 0 and then Group.Index_Of ("Same") = 1,
             "names follow the members when they move");
      Group.Remove ("Other");
      Group.Remove ("Same");
      Check (Group.Count = 0 and then not Group.Contains ("Same"),
             "every member removed by name");
   end Test_Remove_By_Name;

   procedure Test_Results_And_Names is
      A     : aliased Fake_Tool := Make (1, "");
      W     : aliased Fake_Tool := Make (2, "", Warning);
      R     : aliased Fake_Tool := Make (3, "R", Reject);
      Group : Ks_Tool_Group;
   begin
      Section ("Tool group: results and messages");
      Group.Add (A'Access);
      Group.Run;
      Check (Group.Run_Status.Result = Accept_Result, "Accept");
      Group.Add (W'Access);
      Group.Run;
      Check (Group.Run_Status.Result = Warning
             and then Group.Run_Status.Message = "tool 1: Warning",
             "a member without a name or message");
      Group.Add (R'Access);
      Group.Run;
      Check (Group.Run_Status.Result = Reject
             and then Group.Run_Status.Message = "tool 1: Warning",
             "Reject is worse than Warning; the first failure is named");
      Group.Set_Disabled (1, True);
      Group.Run;
      Check (Group.Run_Status.Result = Reject
             and then Group.Run_Status.Message = "R: Reject",
             "a member with a name and no message");

      --  A long message is cut at 1024 characters.
      R.Note := 2000 * 'm';
      Group.Run;
      Check (Group.Run_Status.Message'Length = 1024,
             "the message is cut at 1024 characters");
   end Test_Results_And_Names;

   --  The scripts use only their parameters (no up-level references), so
   --  that 'Unrestricted_Access needs no trampoline.

   procedure Note_Script
     (Group     : in out Ks_Tool_Group'Class;
      Message   : in out Unbounded_String;
      Result    : in out Ks_Tool_Result_Constants;
      Run_Tools : out Boolean) is
   begin
      --  The group's name tells the script whether the members run.
      Message := To_Unbounded_String ("script");
      Result := Warning;
      Run_Tools := Group.Name /= "skip";
   end Note_Script;

   procedure Raising_Script
     (Group     : in out Ks_Tool_Group'Class;
      Message   : in out Unbounded_String;
      Result    : in out Ks_Tool_Result_Constants;
      Run_Tools : out Boolean)
   is
      pragma Unreferenced (Message, Result);
   begin
      if Group.Name /= "" then
         raise Ks_Bad_Parameter_Exception with "the script failed";
      end if;
      Run_Tools := True;
   end Raising_Script;

   procedure Test_Group_Script is
      A     : aliased Fake_Tool := Make (1, "A");
      R     : aliased Fake_Tool := Make (2, "R", Reject, "low");
      Group : Ks_Tool_Group;
   begin
      Section ("Tool group: script");
      Group.Add (A'Access);
      Group.Add (R'Access);
      Group.Set_Script (Note_Script'Unrestricted_Access);
      Check (Group.Script /= null, "Script");
      Clear_Log;
      Group.Run;
      Check (Logged ("1 2"),
             "Run_Tools True: the members run after the script");
      Check (Group.Run_Status.Result = Reject
             and then Group.Run_Status.Message = "script; R: low",
             "the script's result and message come first");
      Group.Set_Name ("skip");
      Clear_Log;
      Group.Run;
      Check (Log_Length = 0, "Run_Tools False: no member runs");
      Check (Group.Run_Status.Result = Warning
             and then Group.Run_Status.Message = "script",
             "the script's result alone");
      Group.Set_Script (Raising_Script'Unrestricted_Access);
      Clear_Log;
      Group.Run;
      Check (Group.Run_Status.Result = Error
             and then Group.Run_Status.Message = "the script failed"
             and then Group.Run_Status.Exception_Name
                        = "AMV.KS_BAD_PARAMETER_EXCEPTION"
             and then Log_Length = 0,
             "a script that raises: Error, no member runs");
      Group.Set_Script (null);
      Clear_Log;
      Group.Run;
      Check (Logged ("1 2"), "without the script again");
   end Test_Group_Script;

   procedure Run_Tool_Script
     (Group     : in out Ks_Tool_Group'Class;
      Message   : in out Unbounded_String;
      Result    : in out Ks_Tool_Result_Constants;
      Run_Tools : out Boolean) is
   begin
      --  The members in reverse order, each through RunTool.
      for I in reverse 0 .. Group.Count - 1 loop
         Group.Run_Tool (Group.Item (I), Message, Result);
      end loop;
      Run_Tools := False;
   end Run_Tool_Script;

   procedure Test_Run_Tool is
      A     : aliased Fake_Tool := Make (1, "A");
      W     : aliased Fake_Tool := Make (2, "W", Warning, "so so");
      R     : aliased Fake_Tool := Make (3, "R", Reject, "low");
      E     : aliased Fake_Tool := Make (4, "E", Error, "broken");
      Group : Ks_Tool_Group;
   begin
      Section ("Tool group: RunTool");
      Group.Add (A'Access);
      Group.Add (W'Access);
      Group.Add (R'Access);
      Group.Set_Script (Run_Tool_Script'Unrestricted_Access);
      Clear_Log;
      Group.Run;
      Check (Logged ("3 2 1"), "RunTool runs the tools the script names");
      Check (Group.Run_Status.Result = Reject
             and then Group.Run_Status.Message = "low",
             "the worst result and its message (a better one does not "
             & "replace it)");
      Group.Set_Disabled (2, True);
      Clear_Log;
      Group.Run;
      Check (Logged ("2 1"), "RunTool does not run a disabled member");
      Check (Group.Run_Status.Result = Warning
             and then Group.Run_Status.Message = "so so",
             "the result of the tools that ran");
      Group.Set_Disabled (2, False);
      Group.Add (E'Access);
      Clear_Log;
      Group.Run;
      Check (Logged ("4 3 2 1")
             and then Group.Run_Status.Result = Error
             and then Group.Run_Status.Message = "broken",
             "an Error without AbortRunOnToolFailure: the script goes on");
      Group.Set_Abort_Run_On_Tool_Failure (True);
      Clear_Log;
      Group.Run;
      Check (Logged ("4") and then Group.Run_Status.Result = Error
             and then Group.Run_Status.Message = "broken"
             and then Group.Run_Status.Exception_Name = "AMV.KS_EXCEPTION",
             "an Error with AbortRunOnToolFailure: RunTool raises");
      declare
         Message : Unbounded_String := To_Unbounded_String ("before");
         Result  : Ks_Tool_Result_Constants := Warning;
         Outside : aliased Fake_Tool := Make (5, "O", Reject, "outside");
      begin
         Clear_Log;
         Group.Run_Tool (Outside'Access, Message, Result);
         Check (Logged ("5") and then Result = Reject
                and then To_String (Message) = "outside",
                "RunTool runs a tool that is not a member too");
         Group.Run_Tool (A'Access, Message, Result);
         Check (Result = Reject and then To_String (Message) = "outside",
                "RunTool outside a script: an Accept changes nothing");
      end;
   end Test_Run_Tool;

   procedure Test_Copies_And_Cycles is
      A      : aliased Fake_Tool := Make (1, "A");
      B      : aliased Fake_Tool := Make (2, "B");
      Group  : aliased Ks_Tool_Group;
      Copy   : aliased Ks_Tool_Group;
      Inner  : aliased Ks_Tool_Group;
      Outer  : aliased Ks_Tool_Group;
      Mutate : aliased Mutating_Tool;

      procedure Copy_Adds_Itself is
      begin
         Copy.Add (Copy'Access);
      end Copy_Adds_Itself;

      procedure Write_Group is
         Stream : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
      begin
         Ks_Tool_Group'Write (Stream'Access, Group);
      end Write_Group;

      Write_Raised : Boolean := False;
   begin
      Section ("Tool group: copies, cycles, changes while running");
      Group.Add (A'Access);
      Group.Add (B'Access);
      Group.Set_Disabled (1, True);
      Group.Set_Name ("G");
      Copy := Group;
      Check (Copy.Count = 2 and then Copy.Item (0) = A'Unchecked_Access
             and then Copy.Disabled (1) and then Copy.Name = "G",
             "a copy has the members, flags and name");
      Copy.Remove_At (0);
      Check (Copy.Count = 1 and then Group.Count = 2,
             "the copy's members are its own list");
      Check (Raises_Bad_Parameter (Copy_Adds_Itself'Access),
             "a copy is itself, not the original, for self-membership");
      Copy.Add (Group'Access);
      Clear_Log;
      Copy.Run;
      Check (Logged ("1") and then Copy.Run_Status.Result = Accept_Result,
             "a group in a group (the original in the copy)");

      --  A cycle: Inner contains Outer, Outer contains Inner.
      Inner.Set_Name ("Inner");
      Outer.Set_Name ("Outer");
      Inner.Add (A'Access);
      Inner.Add (Outer'Access);
      Outer.Add (Inner'Access);
      Clear_Log;
      Outer.Run;
      Check (Outer.Run_Status.Result = Error
             and then Contains_Text (Outer.Run_Status.Message,
                                     "running already"),
             "a cycle of groups ends with Error");
      Check (Logged ("1"), "the members before the cycle ran once");
      Clear_Log;
      Outer.Remove (Inner'Access);
      Outer.Run;
      Check (Outer.Run_Status.Result = Accept_Result,
             "the group runs again after the cycle");

      --  A member that changes the group while it runs.
      Mutate.Target := Group'Unchecked_Access;
      Group.Insert (0, Mutate'Access);
      Group.Run;
      Check (Group.Run_Status.Result = Error
             and then Group.Run_Status.Message
                        = "Run: the group changed while it ran"
             and then Group.Run_Status.Exception_Name
                        = "AMV.KS_BAD_PARAMETER_EXCEPTION",
             "a change while the group runs ends the run with Error");
      Group.Remove (Mutate'Access);
      Group.Set_Disabled (0, False);
      Clear_Log;
      Group.Run;
      Check (Logged ("1") and then Group.Run_Status.Result = Accept_Result,
             "the group runs again afterwards");

      --  Streams.
      begin
         Write_Group;
      exception
         when Program_Error =>
            Write_Raised := True;
      end;
      Check (Write_Raised, "groups are not written to streams");
   end Test_Copies_And_Cycles;

   procedure Test_Speed is
      type Tool_Array is array (1 .. KG.Max_Members) of aliased Fake_Tool;
      Tools : Tool_Array := [others => Make (0, "")];
      Group : Ks_Tool_Group;
      Runs  : constant := 200;
      Start : Ada.Calendar.Time;
      use type Ada.Calendar.Time;
   begin
      Section ("Tool group: a run over 256 members");
      for I in Tools'Range loop
         Tools (I).Tag := I;
         Group.Add (Tools (I)'Access);
      end loop;
      Tools (200).Outcome := Warning;
      Start := Ada.Calendar.Clock;
      for R in 1 .. Runs loop
         Clear_Log;
         Group.Run;
      end loop;
      Ada.Text_IO.Put_Line
        ("  group run over 256 trivial members:"
         & Duration'Image ((Ada.Calendar.Clock - Start) / Runs) & " s");
      Check (Group.Count = KG.Max_Members
             and then Group.Run_Status.Result = Warning
             and then Group.Run_Status.Message = "tool 199: Warning",
             "256 members run; the 200th warns");
   end Test_Speed;

   ---------------------------------------------------------------------
   --  Blocks
   ---------------------------------------------------------------------

   function Same_Image (Left, Right : Ks_Image_8_Grey) return Boolean is
     (Left.Width = Right.Width and then Left.Height = Right.Height
      and then (for all Y in 0 .. Left.Height - 1 =>
                  (for all X in 0 .. Left.Width - 1 =>
                     Left.Get_Pixel (X, Y) = Right.Get_Pixel (X, Y))));

   procedure Test_Terminals is
      Block   : Ks_Tool_Block;
      Image   : constant Ks_Image_8_Grey := Create (8, 6, 17);
      Deep    : constant Ks_Image_16_Grey := Create (4, 3, 4000);
      Pose    : constant Ks_Transform_2D_Linear :=
        Create_Similarity (2.0, 0.25, 10.0, -3.0);
      Circle  : Ks_Circle;
      Long    : constant String (1 .. 257) := [others => 'n'];
      Zero    : constant Real := Real'Value ("0.0");
      NaN     : constant Real := Zero / Zero;

      procedure Get_Integer_Of_Real is
         Unused : constant Long_Long_Integer :=
           Block.Inputs.Get_Integer ("Gain");
      begin
         null;
      end Get_Integer_Of_Real;

      procedure Set_Integer_On_Real is
      begin
         Block.Inputs.Set ("Gain", 3);
      end Set_Integer_On_Real;

      procedure Get_Unknown is
         Unused : constant Real := Block.Inputs.Get_Real ("gain");
      begin
         null;
      end Get_Unknown;

      procedure Set_NaN is
      begin
         Block.Inputs.Set ("Gain", NaN);
      end Set_NaN;

      procedure Add_Duplicate is
      begin
         Block.Inputs.Add ("Gain", 1.0);
      end Add_Duplicate;

      procedure Add_Empty_Name is
      begin
         Block.Inputs.Add ("", 1.0);
      end Add_Empty_Name;

      procedure Add_Long_Name is
      begin
         Block.Inputs.Add (Long, 1.0);
      end Add_Long_Name;

      procedure Set_Long_String is
      begin
         Block.Inputs.Set ("Code", Repeat (1025, 's'));
      end Set_Long_String;

      procedure Get_Shape_Without_Value is
         Unused : constant Ks_Shape'Class := Block.Outputs.Get_Shape ("Roi");
      begin
         null;
      end Get_Shape_Without_Value;

      procedure Set_Image_On_Shape is
      begin
         Block.Outputs.Set ("Roi", Image);
      end Set_Image_On_Shape;

      procedure Name_Far is
         Unused : constant String := Block.Inputs.Name_Of (99);
      begin
         null;
      end Name_Far;

      Message : Unbounded_String;
   begin
      Section ("Tool block: terminals of every type");
      Circle.Set_Center_Radius (5.0, 6.0, 7.0);
      Block.Inputs.Add ("Gain", 2.5);
      Block.Inputs.Add ("Count", 42);
      Block.Inputs.Add ("Pass", True);
      Block.Inputs.Add ("Code", "abc");
      Block.Inputs.Add ("Image", Image);
      Block.Inputs.Add ("Deep", Deep);
      Block.Inputs.Add ("Pose", Pose);
      Block.Inputs.Add ("Circle", Circle);
      Check (Block.Inputs.Count = 8, "eight terminals");
      Check (Block.Inputs.Get_Real ("Gain") = 2.5
             and then Block.Inputs.Get_Integer ("Count") = 42
             and then Block.Inputs.Get_Boolean ("Pass")
             and then Block.Inputs.Get_String ("Code") = "abc",
             "the scalar values added");
      Check (Same_Image (Block.Inputs.Get_Image_8_Grey ("Image"), Image),
             "the 8-bit image added");
      Check (Block.Inputs.Get_Image_16_Grey ("Deep").Get_Pixel (3, 2) = 4000,
             "the 16-bit image added");
      Check (Block.Inputs.Get_Transform ("Pose") = Pose,
             "the transform added");
      Check (Ks_Circle (Block.Inputs.Get_Shape ("Circle")).Radius = 7.0,
             "the shape added");
      Check (Block.Inputs.Value_Type ("Gain") = Real_Type
             and then Block.Inputs.Value_Type ("Count") = Integer_Type
             and then Block.Inputs.Value_Type ("Pass") = Boolean_Type
             and then Block.Inputs.Value_Type ("Code") = String_Type
             and then Block.Inputs.Value_Type ("Image") = Image_8_Grey_Type
             and then Block.Inputs.Value_Type ("Deep") = Image_16_Grey_Type
             and then Block.Inputs.Value_Type ("Pose") = Transform_Type
             and then Block.Inputs.Value_Type ("Circle") = Shape_Type,
             "Value_Type");
      Check (Block.Inputs.Name_Of (0) = "Gain"
             and then Block.Inputs.Name_Of (7) = "Circle"
             and then Block.Inputs.Index_Of ("Code") = 3
             and then Block.Inputs.Index_Of ("code") = -1
             and then Block.Inputs.Contains ("Pose")
             and then not Block.Inputs.Contains (""),
             "Name_Of, Index_Of, Contains (case-sensitive)");

      Block.Inputs.Set ("Gain", -1.0E300);
      Block.Inputs.Set ("Count", Long_Long_Integer'First);
      Block.Inputs.Set ("Pass", False);
      Block.Inputs.Set ("Code", "");
      Block.Inputs.Set ("Image", Ks_Image_8_Grey'(Create (2, 2, 9)));
      Block.Inputs.Set ("Pose", Create_Rigid (0.5, 1.0, 2.0));
      Circle.Set_Radius (1.5);
      Block.Inputs.Set ("Circle", Circle);
      Check (Block.Inputs.Get_Real ("Gain") = -1.0E300
             and then Block.Inputs.Get_Integer ("Count")
                        = Long_Long_Integer'First
             and then not Block.Inputs.Get_Boolean ("Pass")
             and then Block.Inputs.Get_String ("Code") = ""
             and then Block.Inputs.Get_Image_8_Grey ("Image").Width = 2
             and then Block.Inputs.Get_Transform ("Pose").Rotation = 0.5
             and then Ks_Circle (Block.Inputs.Get_Shape ("Circle")).Radius
                        = 1.5,
             "Set and Get of every type");
      Block.Inputs.Set ("Code", Repeat (1024, 'q'));
      Check (Block.Inputs.Get_String ("Code") = Repeat (1024, 'q'),
             "a string of 1024 characters");

      Section ("Tool block: type mismatches and unknown names");
      Check (Raises_Bad_Parameter (Get_Integer_Of_Real'Access),
             "Get_Integer of a Real terminal");
      Check (Raises_Bad_Parameter (Set_Integer_On_Real'Access)
             and then Block.Inputs.Get_Real ("Gain") = -1.0E300,
             "Set of an Integer on a Real terminal changes nothing");
      begin
         Get_Integer_Of_Real;
      exception
         when E : Ks_Bad_Parameter_Exception =>
            Message := To_Unbounded_String
                         (Ada.Exceptions.Exception_Message (E));
      end;
      Check (To_String (Message)
               = "Terminal ""Gain"" is of type Real, not Integer",
             "the message names the terminal and the types");
      Check (Raises_Bad_Parameter (Get_Unknown'Access),
             "an unknown name (names are case-sensitive)");
      Check (Raises_Bad_Parameter (Set_NaN'Access)
             and then Block.Inputs.Get_Real ("Gain") = -1.0E300,
             "a NaN is rejected");
      Check (Raises_Bad_Parameter (Add_Duplicate'Access)
             and then Raises_Bad_Parameter (Add_Empty_Name'Access)
             and then Raises_Bad_Parameter (Add_Long_Name'Access)
             and then Raises_Bad_Parameter (Set_Long_String'Access)
             and then Block.Inputs.Count = 8,
             "bad names and a long string are rejected");
      Check (Raises_Index_Error (Name_Far'Access), "Name_Of beyond Count");

      Block.Outputs.Add ("Roi", Shape_Type);
      Check (not Block.Outputs.Has_Value ("Roi")
             and then Block.Inputs.Has_Value ("Gain")
             and then Raises_Bad_Parameter (Get_Shape_Without_Value'Access),
             "an object terminal added by type has no value");
      Check (Raises_Bad_Parameter (Set_Image_On_Shape'Access)
             and then not Block.Outputs.Has_Value ("Roi"),
             "an image on a shape terminal changes nothing");
      Block.Outputs.Set ("Roi", Circle);
      Check (Block.Outputs.Has_Value ("Roi")
             and then Ks_Circle (Block.Outputs.Get_Shape ("Roi")).Radius
                        = 1.5,
             "Set gives it a value");
   end Test_Terminals;

   procedure Test_Terminal_Order is
      T       : Ks_Tool_Block_Terminal_Collection;
      One     : constant Ks_Image_8_Grey := Create (3, 3, 1);
      Two     : constant Ks_Image_8_Grey := Create (3, 3, 2);
      Three   : constant Ks_Image_8_Grey := Create (3, 3, 3);
      Box     : Ks_Rectangle;
      Copy    : Ks_Tool_Block_Terminal_Collection;

      function Pixel (Name : String) return Grey_8 is
        (T.Get_Image_8_Grey (Name).Get_Pixel (0, 0));
   begin
      Section ("Tool block: removals keep the object values aligned");
      Box.Set_Center_Width_Height (1.0, 2.0, 3.0, 4.0);
      T.Add ("One", One);
      T.Add ("X", 1.0);
      T.Add ("Two", Two);
      T.Add ("Box", Box);
      T.Add ("Three", Three);
      T.Remove ("X");
      Check (Pixel ("One") = 1 and then Pixel ("Two") = 2
             and then Pixel ("Three") = 3
             and then Ks_Rectangle (T.Get_Shape ("Box")).Width = 3.0,
             "Remove (name)");
      T.Remove_At (0);
      Check (T.Name_Of (0) = "Two" and then Pixel ("Two") = 2
             and then Pixel ("Three") = 3,
             "Remove_At");
      T.Insert (0, "New", Image_8_Grey_Type);
      T.Set ("New", One);
      Check (T.Count = 4 and then T.Name_Of (0) = "New"
             and then Pixel ("New") = 1 and then Pixel ("Two") = 2
             and then Pixel ("Three") = 3,
             "Insert");
      T.Move (0, 3);
      Check (T.Name_Of (3) = "New" and then T.Name_Of (0) = "Two"
             and then Pixel ("New") = 1 and then Pixel ("Two") = 2
             and then Pixel ("Three") = 3
             and then Ks_Rectangle (T.Get_Shape ("Box")).Height = 4.0,
             "Move");
      T.Move (3, 1);
      Check (T.Name_Of (1) = "New" and then T.Name_Of (2) = "Box"
             and then Pixel ("New") = 1 and then Pixel ("Three") = 3,
             "Move back");

      --  A copy has its own terminals; images keep sharing pixels.
      Copy := T;
      Copy.Set ("New", Three);
      Copy.Remove ("Two");
      Check (Pixel ("New") = 1 and then T.Count = 4 and then Copy.Count = 3,
             "a copy of a collection is independent");
      Check (Copy.Get_Image_8_Grey ("Three").Get_Pixel (0, 0) = 3,
             "the copy keeps the values");

      T.Clear;
      Check (T.Count = 0 and then Copy.Count = 3, "Clear");
   end Test_Terminal_Order;

   procedure Wire_Histogram
     (Group     : in out Ks_Tool_Group'Class;
      Message   : in out Unbounded_String;
      Result    : in out Ks_Tool_Result_Constants;
      Run_Tools : out Boolean)
   is
      Block : Ks_Tool_Block renames Ks_Tool_Block (Group);
      Tool  : H.Ks_Histogram_Tool renames
        H.Ks_Histogram_Tool (Block.Item (0).all);
   begin
      --  Wire the input into the contained tool, run it, publish.
      Tool.Input_Image := Block.Inputs.Get_Image_8_Grey ("InputImage");
      Tool.Run;
      if Tool.Run_Status.Result = Accept_Result then
         Block.Outputs.Set ("Mean", H.Mean (Tool.Result));
         Block.Outputs.Set ("Samples",
                            Long_Long_Integer (H.Num_Samples (Tool.Result)));
      else
         Result := Tool.Run_Status.Result;
         Message := To_Unbounded_String (Tool.Run_Status.Message);
      end if;
      Run_Tools := False;
   end Wire_Histogram;

   procedure Test_Block_Script is
      Histogram : aliased H.Ks_Histogram_Tool;
      Block     : Ks_Tool_Block;
      Image     : Ks_Image_8_Grey := Blank (40, 30, 100);
      Copy      : Ks_Tool_Block;
      No_Pixels : Ks_Image_8_Grey;
      Start     : Ada.Calendar.Time;
      use type Ada.Calendar.Time;
   begin
      Section ("Tool block: a script wires a real tool");
      --  Mean of 100 with a 10 x 10 square of 200: 100 + 100 * 100 / 1200.
      Draw_Rectangle (Image, 19.5, 14.5, 10.0, 10.0, Value => 200);
      Block.Set_Name ("Measure");
      Block.Add (Histogram'Access);
      Block.Inputs.Add ("InputImage", Image);
      Block.Outputs.Add ("Mean", Real_Type);
      Block.Outputs.Add ("Samples", Integer_Type);
      Block.Set_Script (Wire_Histogram'Unrestricted_Access);
      Start := Ada.Calendar.Clock;
      Block.Run;
      Ada.Text_IO.Put_Line
        ("  block run with the histogram tool:"
         & Duration'Image (Ada.Calendar.Clock - Start) & " s");
      Check (Block.Run_Status.Result = Accept_Result,
             "the block accepts");
      Check_Near (Block.Outputs.Get_Real ("Mean"),
                  100.0 + 100.0 * 100.0 / 1200.0, 1.0E-9,
                  "the script published the histogram's mean");
      Check (Block.Outputs.Get_Integer ("Samples") = 1200,
             "the script published the number of samples");

      --  A failing contained tool: an image without pixels.
      Copy := Block;
      Check (Copy.Item (0) = Block.Item (0)
             and then Copy.Inputs.Count = 1
             and then Copy.Outputs.Get_Integer ("Samples") = 1200,
             "a copy of a block shares the members and copies terminals");
      Copy.Inputs.Set ("InputImage", No_Pixels);
      Copy.Run;
      Check (Copy.Run_Status.Result = Error
             and then Contains_Text (Copy.Run_Status.Message, "InputImage"),
             "the script passes on the tool's failure");
      Check (Block.Inputs.Get_Image_8_Grey ("InputImage").Width = 40,
             "the original's input is unchanged");
   end Test_Block_Script;

   ---------------------------------------------------------------------
   --  Kernel
   ---------------------------------------------------------------------

   procedure Test_Kernel is
      use AMV.Kernels;
      use type KG.Ks_Tool_Group;
      use type KG.Ks_Tool_Block_Terminals;
      Status   : Ks_Status;
      Group    : KG.Ks_Tool_Group;
      Cursor   : KG.Ks_Tool_Group_Cursor;
      Count    : Int32;
      Index    : Int32;
      More     : Int32;
      Result   : Int32;
      First    : Int32;
      Key      : Int64;
      Text     : KG.Ks_Tool_Text;
      Empty    : constant KG.Ks_Tool_Text := KG.To_Text ("");
      T        : KG.Ks_Tool_Block_Terminals;
      Real_V   : Long_Float;
      Start    : Ada.Calendar.Time;
      use type Ada.Calendar.Time;
   begin
      Section ("Kernel: null handles");
      KG.Group_Count (null, Count, Status);
      Check (Succeeded (Status) and then Count = 0, "count of null");
      KG.Group_Item (null, 0, Key, Status);
      Check (Status.Failure = Failure_Index_Out_Of_Range, "item of null");
      KG.Group_Remove_At (null, 0, Status);
      Check (Status.Failure = Failure_Index_Out_Of_Range,
             "remove_at of null");
      KG.Group_Clear (null, Status);
      Check (Succeeded (Status), "clear of null");
      KG.Run_Next (null, Cursor, Index, More, Status);
      Check (Status.Failure = Failure_Bad_Parameter and then More = 0
             and then Cursor.Fault = KG.Fault_Misuse,
             "run_next on null");
      KG.Run_End (null, Cursor, Result, First, Text, Status);
      Check (Status.Failure = Failure_Bad_Parameter
             and then Result = KG.Result_Error, "run_end on null");
      KG.Terminals_Count (null, Count, Status);
      Check (Succeeded (Status) and then Count = 0, "terminals of null");
      KG.Terminals_Get_Real (null, KG.To_Text ("A"), Real_V, Status);
      Check (Status.Failure = Failure_Bad_Parameter,
             "get from a null collection");
      KG.Terminals_Name (null, 0, Text, Status);
      Check (Status.Failure = Failure_Index_Out_Of_Range
             and then Text.Length = 0, "name in a null collection");

      Section ("Kernel: codes and texts");
      KG.Group_Set_Abort_Run_On_Tool_Failure (Group, 2, Status);
      Check (Status.Failure = Failure_Bad_Parameter and then Group = null,
             "a bad flag does not create the group");
      KG.Run_Begin (Group, -2, Empty, 1, Cursor, Status);
      Check (Status.Failure = Failure_Bad_Parameter and then Group = null,
             "a bad result code");
      Text := Empty;
      Text.Length := -1;
      KG.Run_Begin (Group, 0, Text, 1, Cursor, Status);
      Check (Status.Failure = Failure_Bad_Parameter,
             "a negative message length");
      KG.Terminals_Add (T, KG.To_Text ("A"), 8, Status);
      Check (Status.Failure = Failure_Bad_Parameter and then T = null,
             "a bad type code");
      KG.Terminals_Add_Object (T, KG.To_Text ("A"), KG.Type_Real, Status);
      Check (Status.Failure = Failure_Bad_Parameter,
             "add_object of a scalar type");
      KG.Terminals_Add_Boolean (T, KG.To_Text ("A"), 2, Status);
      Check (Status.Failure = Failure_Bad_Parameter, "a bad Boolean");
      Text := KG.To_Text ("ab");
      Text.Length := 300;
      KG.Terminals_Add (T, Text, KG.Type_Real, Status);
      Check (Status.Failure = Failure_Bad_Parameter,
             "a name longer than 256");
      Check (KG.To_Text (Repeat (2000, 'x')).Length = 2000
             and then KG.To_String (KG.To_Text ("abc")) = "abc",
             "To_Text and To_String");

      Section ("Kernel: stale and foreign cursors");
      KG.Group_Create (7, Group, Status);
      KG.Group_Add (Group, 1, Status);
      KG.Group_Add (Group, 2, Status);
      KG.Run_Begin (Group, 0, Empty, 1, Cursor, Status);
      Check (Succeeded (Status) and then Cursor.Run /= 0, "run_begin");
      declare
         Other  : KG.Ks_Tool_Group;
         Second : KG.Ks_Tool_Group_Cursor;
         Saved  : constant KG.Ks_Tool_Group_Cursor := Cursor;
      begin
         KG.Group_Create (8, Other, Status);
         KG.Run_Begin (Other, 0, Empty, 1, Second, Status);
         KG.Run_Next (Other, Cursor, Index, More, Status);
         Check (Status.Failure = Failure_Bad_Parameter and then More = 0,
                "a cursor of another group");
         Cursor := Saved;
         KG.Run_End (Other, Second, Result, First, Text, Status);
         Check (Succeeded (Status) and then Result = KG.Result_Accept,
                "the other group's run ends");
         KG.Group_Destroy (Other);
      end;
      Cursor.Next := 5;
      KG.Run_Next (Group, Cursor, Index, More, Status);
      Check (Status.Failure = Failure_Bad_Parameter
             and then Cursor.Fault = KG.Fault_Misuse,
             "an inconsistent cursor");
      KG.Run_End (Group, Cursor, Result, First, Text, Status);
      Check (Status.Failure = Failure_Bad_Parameter, "run_end reports it");
      KG.Run_Next (Group, Cursor, Index, More, Status);
      Check (Status.Failure = Failure_Bad_Parameter,
             "the cursor of an ended run");
      KG.Group_Set_Own_Key (Group, 2, Status);
      Check (Status.Failure = Failure_Bad_Parameter,
             "the own key cannot be a member's");
      KG.Run_Begin (Group, 0, Empty, 1, Cursor, Status);
      KG.Group_Set_Own_Key (Group, 9, Status);
      Check (Status.Failure = Failure_Bad_Parameter,
             "the own key does not change while the group runs");
      KG.Group_Set_Own_Key (Group, 7, Status);
      Check (Succeeded (Status), "setting the same own key while running");
      KG.Run_End (Group, Cursor, Result, First, Text, Status);
      Check (Succeeded (Status), "a run without run_next");

      Section ("Kernel: limits");
      KG.Group_Clear (Group, Status);
      for K in 1 .. KG.Max_Members loop
         KG.Group_Add (Group, Int64 (K) * 3, Status);
      end loop;
      KG.Group_Count (Group, Count, Status);
      Check (Count = KG.Max_Members, "256 members");
      KG.Group_Add (Group, 1, Status);
      Check (Status.Failure = Failure_Bad_Parameter,
             "no member beyond the limit");
      KG.Group_Insert (Group, 0, 1, Status);
      Check (Status.Failure = Failure_Bad_Parameter,
             "no insert beyond the limit");
      --  A run over 256 members (every other one disabled).
      for K in 0 .. KG.Max_Members - 1 loop
         if K mod 2 = 1 then
            KG.Group_Set_Disabled (Group, Int32 (K), 1, Status);
         end if;
      end loop;
      Start := Ada.Calendar.Clock;
      KG.Run_Begin (Group, 0, Empty, 1, Cursor, Status);
      Count := 0;
      loop
         KG.Run_Next (Group, Cursor, Index, More, Status);
         exit when More = 0;
         Count := Count + 1;
         KG.Run_Report (Group, Cursor, Index,
                        (if Index = 200 then KG.Result_Reject
                         else KG.Result_Accept),
                        Empty, Empty, Status);
      end loop;
      KG.Run_End (Group, Cursor, Result, First, Text, Status);
      Ada.Text_IO.Put_Line
        ("  kernel run over 256 members:"
         & Duration'Image (Ada.Calendar.Clock - Start) & " s");
      Check (Succeeded (Status) and then Count = 128
             and then Result = KG.Result_Reject and then First = 200
             and then KG.To_String (Text) = "tool 200: Reject",
             "a run over 256 members");
      KG.Group_Destroy (Group);

      for K in 1 .. KG.Max_Terminals loop
         KG.Terminals_Add_Integer
           (T, KG.To_Text ("T" & Ada.Strings.Fixed.Trim (K'Image,
                                                         Ada.Strings.Left)),
            Int64 (K), Status);
      end loop;
      KG.Terminals_Count (T, Count, Status);
      Check (Count = KG.Max_Terminals, "128 terminals");
      KG.Terminals_Add_Integer (T, KG.To_Text ("More"), 0, Status);
      Check (Status.Failure = Failure_Bad_Parameter,
             "no terminal beyond the limit");
      KG.Terminals_Move (T, 0, KG.Max_Terminals - 1, Status);
      KG.Terminals_Index_Of (T, KG.To_Text ("T1"), Index, Status);
      declare
         Value : Int64;
      begin
         KG.Terminals_Get_Integer (T, KG.To_Text ("T128"), Value, Status);
         Check (Index = KG.Max_Terminals - 1 and then Value = 128,
                "move in a full collection");
      end;
      KG.Terminals_Destroy (T);
      Check (T = null, "destroy");

      --  RunTool.
      KG.Group_Create (7, Group, Status);
      KG.Group_Add (Group, 70, Status);
      KG.Group_Add (Group, 71, Status);
      KG.Group_Set_Disabled (Group, 1, True_Value, Status);
      KG.Run_Tool_Begin (Group, 70, Index, Status);
      Check (Status.Failure = 0 and then Index = True_Value,
             "run_tool_begin: an enabled member runs");
      KG.Run_Tool_Begin (Group, 71, Index, Status);
      Check (Index = False_Value, "run_tool_begin: a disabled member does not");
      KG.Run_Tool_Begin (Group, 99, Index, Status);
      Check (Index = True_Value, "run_tool_begin: a non-member runs");
      KG.Run_Tool_Begin (null, 99, Index, Status);
      Check (Index = True_Value, "run_tool_begin: null group");
      declare
         Worst     : Int32 := KG.Result_Warning;
         Replace   : Int32;
         Abort_Run : Int32;
      begin
         KG.Run_Tool_End (Group, KG.Result_Reject, Worst, Replace,
                          Abort_Run, Status);
         Check (Status.Failure = 0 and then Worst = KG.Result_Reject
                and then Replace = True_Value and then Abort_Run = False_Value,
                "run_tool_end: a worse result replaces");
         KG.Run_Tool_End (Group, KG.Result_Accept, Worst, Replace,
                          Abort_Run, Status);
         Check (Worst = KG.Result_Reject and then Replace = False_Value,
                "run_tool_end: a better result does not");
         KG.Run_Tool_End (Group, KG.Result_Reject, Worst, Replace,
                          Abort_Run, Status);
         Check (Replace = False_Value, "run_tool_end: an equal one does not");
         KG.Run_Tool_End (Group, KG.Result_Error, Worst, Replace,
                          Abort_Run, Status);
         Check (Worst = KG.Result_Error and then Replace = True_Value
                and then Abort_Run = False_Value,
                "run_tool_end: Error without AbortRunOnToolFailure");
         KG.Group_Set_Abort_Run_On_Tool_Failure (Group, True_Value, Status);
         KG.Run_Tool_End (Group, KG.Result_Error, Worst, Replace,
                          Abort_Run, Status);
         Check (Abort_Run = True_Value and then Replace = False_Value,
                "run_tool_end: Error with AbortRunOnToolFailure aborts");
         KG.Run_Tool_End (Group, 3, Worst, Replace, Abort_Run, Status);
         Check (Status.Failure = Failure_Bad_Parameter
                and then String (Status.Message (1 .. Natural (Status.Length)))
                           = "RunTool: the tool's result must be a "
                             & "CogToolResultConstants value (-1 .. 2)"
                and then Worst = KG.Result_Error,
                "run_tool_end: a bad tool result");
         Worst := -2;
         KG.Run_Tool_End (Group, 0, Worst, Replace, Abort_Run, Status);
         Check (Status.Failure = Failure_Bad_Parameter and then Worst = -2,
                "run_tool_end: a bad result so far");
      end;
      KG.Group_Destroy (Group);
   end Test_Kernel;

   procedure Run_All is
   begin
      Test_Members;
      Test_Remove_By_Name;
      Test_Results_And_Names;
      Test_Group_Script;
      Test_Run_Tool;
      Test_Copies_And_Cycles;
      Test_Speed;
      Test_Terminals;
      Test_Terminal_Order;
      Test_Block_Script;
      Test_Kernel;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Tool_Group;
