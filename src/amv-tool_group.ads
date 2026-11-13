--  The tool group: the counterpart of Cognex.VisionPro.ToolGroup.
--  CogToolGroup, a tool that runs other tools in order.
--
--     Group : AMV.Tool_Group.Ks_Tool_Group;
--     ...
--     Group.Add (Blob_Tool'Access);
--     Group.Add (Caliper_Tool'Access);
--     Group.Set_Abort_Run_On_Tool_Failure (True);
--     Group.Run;
--     if Group.Run_Status.Result /= Accept_Result then ...
--
--  Members. The group refers to its member tools, it does not own them:
--  the user declares them aliased, keeps them alive while they are
--  members, and sets their inputs; a tool may belong to several groups.
--  VisionPro's Tools collection (CogToolCollection) becomes operations on
--  the group itself: Tools.Count -> Count, Tools.Item (I) -> Item, Add,
--  Insert, Remove, Remove_At, Move, Clear, IndexOf -> Index_Of and
--  Contains (members are given by access; the collection's lookups by
--  name are not provided). Indices are 0-based. A tool cannot be a member
--  twice, and a group cannot be a member of itself (Ks_Bad_Parameter_
--  Exception); a group may hold up to Max_Members tools. VisionPro's
--  DisabledTools collection becomes a flag per member (Disabled,
--  Set_Disabled): a disabled member stays in the group and is skipped by
--  Run; the flag moves with the member.
--
--  Run. Execute, called by Run, first calls the Script when one is set,
--  then (unless the script said not to) runs every enabled member in
--  order with its own Run. Each member's Run turns its exceptions into
--  an Error status, so the group sees statuses, never exceptions. With
--  Abort_Run_On_Tool_Failure set, the run stops after the first member
--  whose Run_Status is Error; Warning and Reject do not stop it (AMV's
--  choice: VisionPro does not document which results count as a
--  failure). AbortRunOnToolFailure is False by default (an AMV choice as
--  well).
--
--  Run_Status. The result is the worst of the script's result and those
--  of the members that ran (Error > Reject > Warning > Accept_Result).
--  The message is the script's message followed by the first member that
--  did not accept, "<its name>: <its message>" ("tool <index>" when the
--  member's name is empty, its result when its message is empty), joined
--  by "; ", and cut at 1024 characters. Exception_Name stays empty for a
--  member's failure. The group's own failures are exceptions in Execute,
--  so Run reports Error with their name: a group that changed while it
--  ran (a member added, removed, moved or disabled a member) and a group
--  run again before its run ended (a group that contains itself through
--  other groups: the inner Run fails, and the outer run reports that
--  member's Error) raise Ks_Bad_Parameter_Exception; so may the script.
--  The kernel AMV.Kernels.Tool_Group makes every one of these decisions;
--  Execute only dispatches the members' Run.
--
--  Script (the analogue of a CogToolBlockAdvancedScript or
--  CogToolGroup script that overrides GroupRun). A script is a procedure
--  that receives the group (for a tool block, the block: view it with
--  Ks_Tool_Block (Group)), a message and a result, both in out, starting
--  as "" and Accept_Result, and an out flag Run_Tools, GroupRun's return
--  value: True lets the members run after the script as they would
--  without one, False skips them (the script ran what it wanted itself,
--  for example a member's Run). The script's result and message are
--  combined with the members' as described above. An exception raised by
--  the script makes the group's Run report Error, as for any tool. A
--  script that is not declared at library level needs 'Unrestricted_
--  Access (GNAT) to be stored.
--
--  Copies. Assigning a group copies the member list (the members are
--  shared, as they are references), the flags, the settings and the
--  script. Streams are not provided: a group refers to user-declared
--  tools by access, which a stream cannot keep; 'Write and 'Read raise
--  Program_Error.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Strings.Unbounded;

with AMV.Tools;

private with Ada.Containers.Vectors;
private with Ada.Finalization;
private with Ada.Streams;
private with AMV.Kernels.Tool_Group;

package AMV.Tool_Group is

   Max_Members : constant := 256;
   --  The most members a group holds.

   type Ks_Tool_Access is access all AMV.Tools.Ks_Tool'Class;
   --  A member of a group (non-owning).

   type Ks_Tool_Group is new AMV.Tools.Ks_Tool with private;

   type Ks_Tool_Group_Script is access procedure
     (Group     : in out Ks_Tool_Group'Class;
      Message   : in out Ada.Strings.Unbounded.Unbounded_String;
      Result    : in out AMV.Tools.Ks_Tool_Result_Constants;
      Run_Tools : out Boolean);
   --  A script's GroupRun (see above).

   ---------------------------------------------------------------------
   --  Tools (CogToolCollection)
   ---------------------------------------------------------------------

   function Count (Group : Ks_Tool_Group) return Natural;
   --  Tools.Count.

   function Item (Group : Ks_Tool_Group; Index : Natural)
      return Ks_Tool_Access;
   --  Tools.Item (Index), 0-based (Constraint_Error for Index >= Count).

   function Index_Of
     (Group : Ks_Tool_Group;
      Tool  : not null access constant AMV.Tools.Ks_Tool'Class)
      return Integer;
   --  Tools.IndexOf: the index of Tool, -1 when it is not a member.

   function Contains
     (Group : Ks_Tool_Group;
      Tool  : not null access constant AMV.Tools.Ks_Tool'Class)
      return Boolean;
   --  Tools.Contains.

   procedure Add
     (Group : in out Ks_Tool_Group;
      Tool  : not null access AMV.Tools.Ks_Tool'Class);
   --  Tools.Add: appends Tool, enabled. Ks_Bad_Parameter_Exception when
   --  Tool is a member already, is the group itself, or the group holds
   --  Max_Members tools.

   procedure Insert
     (Group : in out Ks_Tool_Group;
      Index : Natural;
      Tool  : not null access AMV.Tools.Ks_Tool'Class);
   --  Tools.Insert: inserts Tool, enabled, at Index (0 .. Count;
   --  Constraint_Error otherwise); the later members move up by one.
   --  Ks_Bad_Parameter_Exception as for Add.

   procedure Remove
     (Group : in out Ks_Tool_Group;
      Tool  : not null access constant AMV.Tools.Ks_Tool'Class);
   --  Tools.Remove: removes Tool (Ks_Bad_Parameter_Exception when it is
   --  not a member).

   procedure Remove_At (Group : in out Ks_Tool_Group; Index : Natural);
   --  Tools.RemoveAt (Constraint_Error for Index >= Count).

   procedure Move
     (Group      : in out Ks_Tool_Group;
      From_Index : Natural;
      To_Index   : Natural);
   --  Tools.Move: the member at From_Index moves to To_Index (both below
   --  Count, Constraint_Error otherwise), those between move by one.

   procedure Clear (Group : in out Ks_Tool_Group);
   --  Tools.Clear: removes every member.

   function Item (Group : Ks_Tool_Group; Name : String)
      return Ks_Tool_Access;
   --  Tools.Item (String): the first member whose Name is Name
   --  (case-sensitive); Ks_Bad_Parameter_Exception when none is ("Tools:
   --  no tool named ...").

   function Index_Of (Group : Ks_Tool_Group; Name : String) return Integer;
   --  Tools.IndexOf (String): the index of the first member named Name,
   --  -1 when none is (an empty Name never matches).

   function Contains (Group : Ks_Tool_Group; Name : String) return Boolean;
   --  Tools.Contains (String).

   procedure Remove (Group : in out Ks_Tool_Group; Name : String);
   --  Tools.Remove (String): removes the first member named Name
   --  (Ks_Bad_Parameter_Exception when none is).
   --
   --  The lookups by name read the members' current names (AMV.Tools.Name)
   --  and hand them to the kernel (AMV.Kernels.Tool_Group, which compares
   --  them); a member whose name is longer than 256 characters makes them
   --  raise Ks_Bad_Parameter_Exception.

   ---------------------------------------------------------------------
   --  Settings
   ---------------------------------------------------------------------

   function Abort_Run_On_Tool_Failure (Group : Ks_Tool_Group)
      return Boolean;
   procedure Set_Abort_Run_On_Tool_Failure
     (Group : in out Ks_Tool_Group;
      Value : Boolean);
   --  AbortRunOnToolFailure (False by default): stop a run after a member
   --  reports Error.

   function Disabled (Group : Ks_Tool_Group; Index : Natural)
      return Boolean;
   procedure Set_Disabled
     (Group : in out Ks_Tool_Group;
      Index : Natural;
      Value : Boolean);
   --  Whether member Index is in DisabledTools (skipped by Run).
   --  Constraint_Error for Index >= Count.

   function Script (Group : Ks_Tool_Group) return Ks_Tool_Group_Script;
   procedure Set_Script
     (Group  : in out Ks_Tool_Group;
      Script : Ks_Tool_Group_Script);
   --  Script (null, the default: none).

   procedure Run_Tool
     (Group    : in out Ks_Tool_Group;
      Sub_Tool : not null access AMV.Tools.Ks_Tool'Class;
      Message  : in out Ada.Strings.Unbounded.Unbounded_String;
      Result   : in out AMV.Tools.Ks_Tool_Result_Constants);
   --  CogToolGroup.RunTool (subTool, ref message, ref result), for a
   --  script: runs Sub_Tool with its Run unless it is a member of Group
   --  in DisabledTools (then nothing happens). Result and Message carry
   --  the worst result of the script so far: when Sub_Tool's result is
   --  worse (Error > Reject > Warning > Accept_Result), Result becomes it
   --  and Message becomes Sub_Tool's message; otherwise both are left as
   --  they are. When Sub_Tool reports Error and the group has
   --  Abort_Run_On_Tool_Failure, Run_Tool raises Ks_Exception with
   --  Sub_Tool's message (the group's Run then reports Error). A tool
   --  that is not a member runs too (AMV's choice). Usually the script
   --  passes its own Message and Result:
   --
   --     procedure My_Script (Group : in out Ks_Tool_Group'Class;
   --                          Message : in out Unbounded_String;
   --                          Result : in out Ks_Tool_Result_Constants;
   --                          Run_Tools : out Boolean) is
   --     begin
   --        Group.Run_Tool (Blob_Tool'Access, Message, Result);
   --        Run_Tools := False;
   --     end My_Script;

   ---------------------------------------------------------------------
   --  ICogTool
   ---------------------------------------------------------------------

   overriding procedure Execute (Group : in out Ks_Tool_Group);
   --  Runs the script and the members (see above). Users call Run.

private

   package KG renames AMV.Kernels.Tool_Group;

   package Member_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Ks_Tool_Access);

   type Group_Handle is new Ada.Finalization.Controlled with record
      Handle : KG.Ks_Tool_Group;
   end record;
   --  Owns the kernel's group; copies duplicate it.

   overriding procedure Adjust (Item : in out Group_Handle);
   overriding procedure Finalize (Item : in out Group_Handle);

   procedure Write_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Group_Handle);
   procedure Read_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Group_Handle);
   --  Both raise Program_Error (groups are not stored in streams).

   for Group_Handle'Write use Write_Handle;
   for Group_Handle'Read use Read_Handle;

   type Ks_Tool_Group is new AMV.Tools.Ks_Tool with record
      Kernel  : Group_Handle;
      Members : Member_Vectors.Vector;
      --  The members, in the kernel's order.
      Script  : Ks_Tool_Group_Script;
   end record;

end AMV.Tool_Group;
