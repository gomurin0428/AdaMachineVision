--  Kernel of AMV.Tool_Group and AMV.Tool_Block: every decision a tool group
--  (Cognex.VisionPro.ToolGroup.CogToolGroup) and a tool block
--  (Cognex.VisionPro.ToolBlock.CogToolBlock) make, so that the Ada API only
--  dispatches Run on the member tools. The C API is declared in
--  include/amv_tool_group.h.
--
--  Members. A group (C: ks_tool_group *, an owned handle; null is an empty
--  group with the defaults below) holds up to Max_Members members in order.
--  A member is an opaque 64-bit key chosen by the caller (the Ada API uses
--  the address of the tool object; a C caller uses whatever identifies its
--  tool) and a disabled flag (VisionPro's DisabledTools collection: a
--  disabled member is skipped by a run). The group also holds its own key
--  (a member may not be the group itself; 0 unless given to create or
--  set_own_key), AbortRunOnToolFailure (False by default, an AMV choice:
--  the reference does not give the default) and a change counter that
--  every successful change of the members, their flags, the abort flag or
--  the own key advances. The entry points that change a group take it in
--  out and create it when it is null where that makes sense (set_own_key,
--  set_abort_run_on_tool_failure, add, insert, run_begin).
--
--  Proved (Gold, Distinct_Members): no key is a member twice and no member
--  has the group's own key; every entry point keeps this when it held on
--  entry (it holds for a new group), so it holds for every handle the
--  kernel made. Adding a key that is a member already, or the group's own
--  key, fails with Bad_Parameter; so does setting the own key to a
--  member's key. The count stays within Max_Members (its subtype).
--
--  Runs. A run is driven through a cursor (C: ks_tool_group_cursor, a
--  fixed-size record the caller owns):
--
--     run_begin (group, script_result, script_message, run_tools, cursor)
--     loop
--        run_next (group, cursor, index, more); exit when more = 0;
--        run member index, then
--        run_report (group, cursor, index, result, name, message);
--     end loop;
--     run_end (group, cursor, result, first_failure, message);
--
--  run_begin starts a run (Bad_Parameter when the group is running
--  already: a group that contains itself through other groups); the
--  script's result and message (the outcome of a script's GroupRun, or
--  Accept and "" without a script) start the run's result and message, and
--  run_tools = 0 (GroupRun returned false) stops the run before any member.
--  run_next offers the next enabled member after the last one offered
--  (more = 1) or reports that none is left (more = 0); after a member
--  reported Error while AbortRunOnToolFailure is set, nothing more is
--  offered. AMV choice: only Error stops a run (the reference does not say
--  whether Reject counts as a failure). run_report records the offered
--  member's result (CogToolResultConstants codes, VisionPro's values:
--  Accept 0, Warning 1, Reject 2, Error -1), its name and its message.
--  run_end ends the run and returns its result, the index of the first
--  member that did not accept (No_Index when every one accepted) and the
--  message.
--
--  Result and message. The result is the worst of the script's result and
--  the reported ones (Error > Reject > Warning > Accept). The message is
--  the script's message, followed (after "; " when the script's message is
--  not empty) by the first member that did not accept, as "<name>: <its
--  message>", the name being "tool <index>" when the member's name is
--  empty and the message its result ("Warning", "Reject", "Error") when the
--  member's message is empty. Messages longer than Max_Text_Length
--  characters are cut there.
--
--  Proved (Gold), as relations between each call and the cursor it
--  receives: members are offered in order, each at most once (the cursor's
--  Next only grows and every index offered is at least the previous Next);
--  a disabled member is never offered and every member skipped is
--  disabled; when run_next reports that none is left and the run was not
--  stopped, every member from the previous Next on is disabled; nothing is
--  offered once the run stopped, and a member that reports Error while
--  AbortRunOnToolFailure is set stops it; the worst result recorded is the
--  worst of the script's and the reported ones, and run_end returns it;
--  the first failure index is the first member whose report was not Accept
--  (No_Index when none), and run_end returns it.
--
--  Misuse. The cursor holds the group's own key, its change counter and
--  the serial number of the run. A cursor of another group or of a run
--  that has ended, a report for a member that was not the one offered, an
--  offer while a member's report is pending, and any call after the group
--  changed fail with Bad_Parameter. A failed run_next or run_report marks
--  the cursor (Fault), so that every later call of the run fails and
--  run_end reports the failure; run_end always ends a run whose cursor it
--  recognises. Two groups with the same own key, change counter and run
--  serial cannot be told apart (the Ada API uses the groups' addresses as
--  their keys).
--
--  Terminals. A terminal collection (C: ks_tool_block_terminals *, an
--  owned handle; null is the empty collection) holds up to Max_Terminals
--  named terminals in order (CogToolBlockTerminalCollection, the Inputs and
--  Outputs of a tool block). A terminal has a name of 1 to
--  Max_Name_Length characters, unique within its collection (compared
--  case-sensitively), a value type (the Type_* codes, AMV codes for the
--  .NET types: Real (double), Integer (int64), Boolean, String (a byte
--  string of at most Max_Text_Length bytes), Image_8_Grey, Image_16_Grey,
--  Transform (CogTransform2DLinear) and Shape (any ICogShape)) and a value.
--  The kernel stores the values of the four scalar types (a Real must be
--  finite; any finite double is accepted); for the four object types it
--  stores only whether the terminal has a value, and the caller keeps the
--  object itself in step with the terminal's index (the Ada API keeps
--  them in a vector updated with every add, insert, remove and move).
--  A terminal added by type alone gets 0.0, 0, False or "" (scalars) or no
--  value (objects).
--
--  Proved (Gold): names stay unique (Distinct_Names, kept by every entry
--  point as for the members); a set of a scalar stores exactly the value
--  given in the terminal of that name (Holds_Real, Holds_Integer, ...) and
--  changes nothing else, a get returns exactly the value the terminal
--  holds (so a get returns what the last set stored), and a failed set (an
--  unknown name, a value of the wrong type, a value out of range) changes
--  nothing.
--
--  Texts. Names, messages and string values cross the C ABI as
--  Ks_Tool_Text: Length characters in Text. A text argument longer than
--  Max_Text_Length holds its first Max_Text_Length characters; as a
--  message it is cut there, as a name or a string value it is rejected
--  (Bad_Parameter). A negative Length is malformed (Bad_Parameter).
--  Texts the kernel returns have NUL characters after their Length
--  characters.
--
--  No floating-point work: Real values are only checked and stored.
--  Trusted parts (SPARK_Mode Off bodies, listed in docs/PROOF.md): the
--  allocation of a group and of a terminal collection, which turns a
--  failed allocation into Out_Of_Memory. Everything else is proved.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Interfaces;

package AMV.Kernels.Tool_Group with SPARK_Mode, Preelaborate is

   pragma Unevaluated_Use_Of_Old (Allow);

   use type Interfaces.Unsigned_64;

   ---------------------------------------------------------------------
   --  Limits and codes
   ---------------------------------------------------------------------

   Max_Members : constant := 256;
   --  Members of a group (C: KS_TOOL_GROUP_MAX_MEMBERS).

   Max_Terminals : constant := 128;
   --  Terminals of a collection (C: KS_TOOL_BLOCK_MAX_TERMINALS).

   Max_Name_Length : constant := 256;
   --  Characters of a terminal name (C: KS_TOOL_BLOCK_MAX_NAME_LENGTH).

   Max_Text_Length : constant := 1024;
   --  Characters of a text: a message, a name passed in, a string value
   --  (C: KS_TOOL_TEXT_MAX_LENGTH).

   No_Index : constant := -1;
   --  "None" for an index (C: KS_TOOL_GROUP_NO_INDEX).

   --  CogToolResultConstants (VisionPro's values).

   Result_Error   : constant Int32 := -1;
   Result_Accept  : constant Int32 := 0;
   Result_Warning : constant Int32 := 1;
   Result_Reject  : constant Int32 := 2;

   subtype Result_Code is Int32 range Result_Error .. Result_Reject;

   function Rank (Code : Result_Code) return Int32 is
     (if Code = Result_Error then 3 else Code);
   --  How bad a result is: Accept 0, Warning 1, Reject 2, Error 3.

   function Worse (Left, Right : Result_Code) return Result_Code is
     (if Rank (Right) > Rank (Left) then Right else Left);
   --  The worse of two results.

   --  Terminal value types (AMV codes).

   Type_Real          : constant Int32 := 0;
   Type_Integer       : constant Int32 := 1;
   Type_Boolean       : constant Int32 := 2;
   Type_String        : constant Int32 := 3;
   Type_Image_8_Grey  : constant Int32 := 4;
   Type_Image_16_Grey : constant Int32 := 5;
   Type_Transform     : constant Int32 := 6;
   Type_Shape         : constant Int32 := 7;

   subtype Value_Type_Code is Int32 range Type_Real .. Type_Shape;
   subtype Object_Type_Code is Int32
     range Type_Image_8_Grey .. Type_Shape;

   --  Why a cursor failed (Ks_Tool_Group_Cursor.Fault).

   Fault_None    : constant Int32 := 0;
   Fault_Changed : constant Int32 := 1;
   --  The group changed after the run began.
   Fault_Misuse  : constant Int32 := 2;
   --  A call out of order or with bad arguments.

   subtype Fault_Code is Int32 range Fault_None .. Fault_Misuse;

   ---------------------------------------------------------------------
   --  Texts
   ---------------------------------------------------------------------

   type Text_Array is array (1 .. Max_Text_Length) of Character
     with Convention => C;

   type Ks_Tool_Text is record
      Length : Int32      := 0;
      Text   : Text_Array := [others => ASCII.NUL];
   end record
     with Convention => C;
   --  A text: Text (1 .. Length). C: ks_tool_text (1028 bytes).

   function Fits (Text : Ks_Tool_Text) return Boolean is
     (Text.Length in 0 .. Max_Text_Length);
   --  Text holds all its characters.

   function To_Text (Source : String) return Ks_Tool_Text
   with
     Post => To_Text'Result.Length = Int32 (Source'Length)
             and then (for all J in 1 .. Integer'Min (Source'Length,
                                                      Max_Text_Length)
                       => To_Text'Result.Text (J)
                            = Source (Source'First + (J - 1)));
   --  For the Ada API (not exported): Source as a text, whatever its
   --  bounds. A Source longer than Max_Text_Length keeps its first
   --  characters and its length (it does not fit).

   function To_String (Text : Ks_Tool_Text) return String
   with
     Pre  => Fits (Text),
     Post => To_String'Result'First = 1
             and then To_String'Result'Length = Integer (Text.Length)
             and then (for all J in 1 .. Integer (Text.Length)
                       => To_String'Result (J) = Text.Text (J));
   --  For the Ada API (not exported): the characters of Text.

   ---------------------------------------------------------------------
   --  Names (of terminals, and of a group's members)
   ---------------------------------------------------------------------

   subtype Name_Length is Natural range 0 .. Max_Name_Length;

   type Name_Array is array (1 .. Max_Name_Length) of Character;

   type Terminal_Name is record
      Length : Name_Length := 0;
      Text   : Name_Array  := [others => ASCII.NUL];
   end record;
   --  A stored name: Text (1 .. Length), NUL characters after it.

   No_Name : constant Terminal_Name := (others => <>);
   --  The empty name.

   function Same_Name (Left, Right : Terminal_Name) return Boolean
   with
     Post => Same_Name'Result
               = (Left.Length = Right.Length
                  and then (for all K in 1 .. Left.Length =>
                              Left.Text (K) = Right.Text (K)));
   --  The names are equal (case-sensitive).

   function Stored_Name_Fits (Name : Ks_Tool_Text) return Boolean is
     (Name.Length in 0 .. Max_Name_Length);
   --  Name can be stored (the empty name included).

   function To_Name (Name : Ks_Tool_Text) return Terminal_Name is
     (Length => Natural (Name.Length),
      Text   => [for K in 1 .. Max_Name_Length =>
                   (if K <= Natural (Name.Length) then Name.Text (K)
                    else ASCII.NUL)])
   with Pre => Stored_Name_Fits (Name);
   --  The stored form of a name.

   ---------------------------------------------------------------------
   --  Groups (C: ks_tool_group)
   ---------------------------------------------------------------------

   subtype Member_Count is Natural range 0 .. Max_Members;
   subtype Member_Index is Natural range 0 .. Max_Members - 1;

   type Member is record
      Key      : Int64   := 0;
      Disabled : Boolean := False;
      Name     : Terminal_Name;
   end record;
   --  A member: its key, whether it is disabled, and its name (empty
   --  until set; the Ada API sets every member's name from its tool's
   --  Name before a lookup by name).

   type Member_Array is array (Member_Index) of Member;

   type Ks_Tool_Group_Data is record
      Count            : Member_Count := 0;
      Members          : Member_Array := [others => (others => <>)];
      Own_Key          : Int64 := 0;
      Abort_On_Failure : Boolean := False;
      Change_Count     : Interfaces.Unsigned_64 := 0;
      Last_Run         : Interfaces.Unsigned_64 := 0;
      Active_Run       : Interfaces.Unsigned_64 := 0;
   end record;
   --  What a group handle designates (opaque for C): the members
   --  Members (0 .. Count - 1), the own key, AbortRunOnToolFailure, the
   --  change counter, the serial of the last run begun and that of the
   --  run in progress (0: none).

   type Ks_Tool_Group is access Ks_Tool_Group_Data
     with Convention => C;
   --  C: ks_tool_group *.

   Empty_Group : constant Ks_Tool_Group_Data := (others => <>)
     with Ghost;

   function Group_Of
     (Group : access constant Ks_Tool_Group_Data) return Ks_Tool_Group_Data
   is (if Group = null then Empty_Group else Group.all)
   with Ghost;
   --  The contents of a handle (those of an empty group for null).

   function Count_Of
     (Group : access constant Ks_Tool_Group_Data) return Member_Count
   is (if Group = null then 0 else Group.Count);

   function Member_Of
     (Group : Ks_Tool_Group_Data; Key : Int64) return Boolean
   is (for some I in 0 .. Group.Count - 1 => Group.Members (I).Key = Key)
   with Ghost;

   function Distinct_Members (Group : Ks_Tool_Group_Data) return Boolean is
     (for all I in 0 .. Group.Count - 1 =>
        Group.Members (I).Key /= Group.Own_Key
        and then (for all J in 0 .. Group.Count - 1 =>
                    (if I /= J
                     then Group.Members (I).Key /= Group.Members (J).Key)))
   with Ghost;
   --  No key twice and never the own key (Gold).

   function Valid_Group
     (Group : access constant Ks_Tool_Group_Data) return Boolean
   is (Group = null or else Distinct_Members (Group.all))
   with Ghost;

   function Same_Settings (Left, Right : Ks_Tool_Group_Data) return Boolean
   is (Left.Own_Key = Right.Own_Key
       and then Left.Abort_On_Failure = Right.Abort_On_Failure)
   with Ghost;

   function Same_Members (Left, Right : Ks_Tool_Group_Data) return Boolean
   is (Left.Count = Right.Count
       and then (for all I in 0 .. Left.Count - 1 =>
                   Left.Members (I) = Right.Members (I)))
   with Ghost;
   --  The same members in the same order, with the same flags.

   procedure Group_Create
     (Own_Key : Int64;
      Group   : out Ks_Tool_Group;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_create",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Group.Count = 0
                            and then Group.Own_Key = Own_Key
                            and then not Group.Abort_On_Failure
                            and then Group.Active_Run = 0
                            and then Valid_Group (Group)
                       else Group = null);
   --  A new empty group whose own key is Own_Key.

   procedure Group_Destroy (Group : in out Ks_Tool_Group)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_destroy",
     Post => Group = null;
   --  Frees the group (nothing for null). The member tools are not
   --  touched: the group never owns them.

   procedure Group_Duplicate
     (Group  : access constant Ks_Tool_Group_Data;
      Copy   : out Ks_Tool_Group;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_duplicate",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status) and then Group /= null
                       then Copy /= null
                            and then Same_Members (Copy.all, Group.all)
                            and then Same_Settings (Copy.all, Group.all)
                            and then Copy.Active_Run = 0
                            and then (if Valid_Group (Group)
                                      then Valid_Group (Copy))
                       else Copy = null);
   --  A new group with the same members, flags and settings and no run in
   --  progress (null for null). The members are shared: they are keys.

   procedure Group_Own_Key
     (Group  : access constant Ks_Tool_Group_Data;
      Key    : out Int64;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_own_key",
     Post => Valid (Status) and then Succeeded (Status)
             and then Key = (if Group = null then 0 else Group.Own_Key);
   --  The group's own key (0 for null).

   procedure Group_Set_Own_Key
     (Group  : in out Ks_Tool_Group;
      Key    : Int64;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_set_own_key",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Valid_Group (Group)'Old then Valid_Group (Group))
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Group.Own_Key = Key
                            and then Same_Members (Group.all,
                                                   Group_Of (Group)'Old)
                       else Group_Of (Group) = Group_Of (Group)'Old);
   --  Sets the own key; creates the group when it is null. Bad_Parameter
   --  when Key is a member's key, or when the group is running and Key is
   --  not its own key already (a run recognises its cursor by the key).

   procedure Group_Count
     (Group  : access constant Ks_Tool_Group_Data;
      Count  : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_count",
     Post => Valid (Status) and then Succeeded (Status)
             and then Count = Int32 (Count_Of (Group));
   --  Tools.Count (0 for null).

   procedure Group_Item
     (Group  : access constant Ks_Tool_Group_Data;
      Index  : Int32;
      Key    : out Int64;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_item",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Index in 0 .. Int32 (Group.Count) - 1
                            and then Key
                                       = Group.Members (Natural (Index)).Key
                       else Key = 0);
   --  The key of Tools.Item (Index) (0-based). Index_Out_Of_Range
   --  unless Index is in 0 .. Count - 1.

   procedure Group_Index_Of
     (Group  : access constant Ks_Tool_Group_Data;
      Key    : Int64;
      Index  : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_index_of",
     Post => Valid (Status) and then Succeeded (Status)
             and then Index in No_Index .. Int32 (Count_Of (Group)) - 1
             and then (if Index = No_Index
                       then Group = null
                            or else not Member_Of (Group.all, Key)
                       else Group /= null
                            and then Group.Members (Natural (Index)).Key
                                       = Key);
   --  Tools.IndexOf: the index of the member Key, No_Index when it is not
   --  a member.

   procedure Group_Add
     (Group  : in out Ks_Tool_Group;
      Key    : Int64;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_add",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Valid_Group (Group)'Old then Valid_Group (Group))
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Group.Count = Count_Of (Group)'Old + 1
                            and then Group.Members (Group.Count - 1)
                                       = (Key      => Key,
                                          Disabled => False,
                                          Name     => No_Name)
                            and then (for all I in 0 .. Group.Count - 2 =>
                                        Group.Members (I)
                                          = Group_Of (Group)'Old.Members (I))
                            and then Same_Settings (Group.all,
                                                    Group_Of (Group)'Old)
                       else Group_Of (Group) = Group_Of (Group)'Old);
   --  Tools.Add: appends the member Key, enabled; creates the group when
   --  it is null. Bad_Parameter when Key is a member already, is the own
   --  key, or the group holds Max_Members members.

   procedure Group_Insert
     (Group  : in out Ks_Tool_Group;
      Index  : Int32;
      Key    : Int64;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_insert",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
                         | Failure_Out_Of_Memory
             and then (if Valid_Group (Group)'Old then Valid_Group (Group))
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Index in 0 .. Int32 (Group.Count) - 1
                            and then Group.Count = Count_Of (Group)'Old + 1
                            and then Group.Members (Natural (Index))
                                       = (Key      => Key,
                                          Disabled => False,
                                          Name     => No_Name)
                            and then (for all I in 0 .. Group.Count - 1 =>
                                        (if I < Natural (Index)
                                         then Group.Members (I)
                                                = Group_Of (Group)'Old
                                                    .Members (I)
                                         elsif I > Natural (Index)
                                         then Group.Members (I)
                                                = Group_Of (Group)'Old
                                                    .Members (I - 1)))
                            and then Same_Settings (Group.all,
                                                    Group_Of (Group)'Old)
                       else Group_Of (Group) = Group_Of (Group)'Old);
   --  Tools.Insert: inserts the member Key, enabled, at Index (0 .. Count;
   --  Index_Out_Of_Range otherwise); the later members move up by one.
   --  Creates the group when it is null. Bad_Parameter as for Add.

   procedure Group_Remove_At
     (Group  : Ks_Tool_Group;
      Index  : Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_remove_at",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Index_Out_Of_Range
             and then (if Valid_Group (Group)'Old then Valid_Group (Group))
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Index >= 0
                            and then Natural (Index) <= Count_Of (Group)'Old - 1
                            and then Group.Count = Count_Of (Group)'Old - 1
                            and then (for all I in 0 .. Group.Count - 1 =>
                                        Group.Members (I)
                                          = (if I < Natural (Index)
                                             then Group_Of (Group)'Old
                                                    .Members (I)
                                             else Group_Of (Group)'Old
                                                    .Members (I + 1)))
                            and then Same_Settings (Group.all,
                                                    Group_Of (Group)'Old)
                       else Group_Of (Group) = Group_Of (Group)'Old);
   --  Tools.RemoveAt: removes member Index (0 .. Count - 1,
   --  Index_Out_Of_Range otherwise); the later members move down by one.

   procedure Group_Remove
     (Group  : Ks_Tool_Group;
      Key    : Int64;
      Index  : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_remove",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Valid_Group (Group)'Old then Valid_Group (Group))
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Index >= 0
                            and then Natural (Index) <= Count_Of (Group)'Old - 1
                            and then Group_Of (Group)'Old
                                       .Members (Natural (Index)).Key = Key
                            and then Group.Count = Count_Of (Group)'Old - 1
                            and then (for all I in 0 .. Group.Count - 1 =>
                                        Group.Members (I)
                                          = (if I < Natural (Index)
                                             then Group_Of (Group)'Old
                                                    .Members (I)
                                             else Group_Of (Group)'Old
                                                    .Members (I + 1)))
                            and then Same_Settings (Group.all,
                                                    Group_Of (Group)'Old)
                       else Index = No_Index
                            and then Group_Of (Group) = Group_Of (Group)'Old);
   --  Tools.Remove: removes the member Key and returns the index it had.
   --  Bad_Parameter when Key is not a member.

   procedure Group_Move
     (Group      : Ks_Tool_Group;
      From_Index : Int32;
      To_Index   : Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_move",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Index_Out_Of_Range
             and then (if Valid_Group (Group)'Old then Valid_Group (Group))
             and then (if Succeeded (Status)
                       then Group /= null
                            and then From_Index in 0 .. Int32 (Group.Count) - 1
                            and then To_Index in 0 .. Int32 (Group.Count) - 1
                            and then Group.Count = Count_Of (Group)'Old
                            and then Group.Members (Natural (To_Index))
                                       = Group_Of (Group)'Old.Members
                                           (Natural (From_Index))
                            and then Same_Settings (Group.all,
                                                    Group_Of (Group)'Old)
                       else Group_Of (Group) = Group_Of (Group)'Old);
   --  Tools.Move: the member at From_Index moves to To_Index (both in
   --  0 .. Count - 1, Index_Out_Of_Range otherwise); the members between
   --  move by one to make room. Its disabled flag goes with it.

   procedure Group_Clear
     (Group  : Ks_Tool_Group;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_clear",
     Post => Valid (Status) and then Succeeded (Status)
             and then Count_Of (Group) = 0
             and then (if Valid_Group (Group)'Old then Valid_Group (Group))
             and then (if Group /= null
                       then Same_Settings (Group.all, Group_Of (Group)'Old));
   --  Tools.Clear: removes every member (nothing for null).

   procedure Group_Disabled
     (Group    : access constant Ks_Tool_Group_Data;
      Index    : Int32;
      Disabled : out Int32;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_disabled",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Index_Out_Of_Range
             and then Disabled in False_Value | True_Value
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Index in 0 .. Int32 (Group.Count) - 1
                            and then (Disabled = True_Value)
                                       = Group.Members (Natural (Index))
                                           .Disabled
                       else Disabled = False_Value);
   --  1 when member Index is in VisionPro's DisabledTools (skipped by a
   --  run), 0 otherwise. Index_Out_Of_Range outside 0 .. Count - 1.

   procedure Group_Set_Disabled
     (Group    : Ks_Tool_Group;
      Index    : Int32;
      Disabled : Int32;
      Status   : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_set_disabled",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Valid_Group (Group)'Old then Valid_Group (Group))
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Index in 0 .. Int32 (Group.Count) - 1
                            and then Group.Count = Count_Of (Group)'Old
                            and then Group.Members (Natural (Index))
                                       = (Key      => Group_Of (Group)'Old
                                                       .Members
                                                         (Natural (Index))
                                                       .Key,
                                          Disabled => Disabled = True_Value,
                                          Name     => Group_Of (Group)'Old
                                                       .Members
                                                         (Natural (Index))
                                                       .Name)
                            and then (for all I in 0 .. Group.Count - 1 =>
                                        (if I /= Natural (Index)
                                         then Group.Members (I)
                                                = Group_Of (Group)'Old
                                                    .Members (I)))
                            and then Same_Settings (Group.all,
                                                    Group_Of (Group)'Old)
                       else Group_Of (Group) = Group_Of (Group)'Old);
   --  Adds member Index to DisabledTools (Disabled = 1) or takes it out
   --  (0); Bad_Parameter for another flag value.

   procedure Group_Set_Name
     (Group  : Ks_Tool_Group;
      Index  : Int32;
      Name   : Ks_Tool_Text;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_set_name",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Valid_Group (Group)'Old then Valid_Group (Group))
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Index in 0 .. Int32 (Group.Count) - 1
                            and then Group.Count = Count_Of (Group)'Old
                            and then Group.Members (Natural (Index))
                                       = (Key      => Group_Of (Group)'Old
                                                       .Members
                                                         (Natural (Index))
                                                       .Key,
                                          Disabled => Group_Of (Group)'Old
                                                       .Members
                                                         (Natural (Index))
                                                       .Disabled,
                                          Name     => To_Name (Name))
                            and then (for all I in 0 .. Group.Count - 1 =>
                                        (if I /= Natural (Index)
                                         then Group.Members (I)
                                                = Group_Of (Group)'Old
                                                    .Members (I)))
                            and then Same_Settings (Group.all,
                                                    Group_Of (Group)'Old)
                            and then Group.Change_Count
                                       = Group_Of (Group)'Old.Change_Count
                            and then Group.Active_Run
                                       = Group_Of (Group)'Old.Active_Run
                       else Group_Of (Group) = Group_Of (Group)'Old);
   --  The name of member Index (the Name of its tool; up to
   --  Max_Name_Length characters, the empty name allowed). Bad_Parameter
   --  for a longer name ("a tool name must be at most 256 characters"),
   --  Index_Out_Of_Range outside 0 .. Count - 1. Setting a name is not a
   --  change of the group: a run in progress goes on.

   procedure Group_Name
     (Group  : access constant Ks_Tool_Group_Data;
      Index  : Int32;
      Name   : out Ks_Tool_Text;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_name",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Index in 0 .. Int32 (Group.Count) - 1
                            and then Name.Length
                                       = Int32 (Group.Members
                                                  (Natural (Index)).Name
                                                  .Length)
                            and then (for all K in 1 .. Integer (Name.Length)
                                      => Name.Text (K)
                                           = Group.Members (Natural (Index))
                                               .Name.Text (K))
                       else Name.Length = 0);
   --  The name stored for member Index (empty until set).

   procedure Group_Index_Of_Name
     (Group  : access constant Ks_Tool_Group_Data;
      Name   : Ks_Tool_Text;
      Index  : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_index_of_name",
     Post => Valid (Status) and then Succeeded (Status)
             and then Index in No_Index .. Int32 (Count_Of (Group)) - 1
             and then
               (if Index = No_Index
                then Group = null
                     or else not Stored_Name_Fits (Name)
                     or else Name.Length = 0
                     or else (for all J in 0 .. Group.Count - 1 =>
                                not Same_Name (Group.Members (J).Name,
                                               To_Name (Name)))
                else Group /= null
                     and then Stored_Name_Fits (Name)
                     and then Name.Length > 0
                     and then Same_Name
                                (Group.Members (Natural (Index)).Name,
                                 To_Name (Name))
                     and then (for all J in 0 .. Natural (Index) - 1 =>
                                 not Same_Name (Group.Members (J).Name,
                                                To_Name (Name))));
   --  Tools.IndexOf (String) on the stored names: the first member named
   --  Name (case-sensitive), No_Index when there is none (an empty name
   --  never matches, nor a name longer than Max_Name_Length).

   procedure Group_Item_By_Name
     (Group  : access constant Ks_Tool_Group_Data;
      Name   : Ks_Tool_Text;
      Key    : out Int64;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_item_by_name",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Stored_Name_Fits (Name)
                            and then
                              (for some I in 0 .. Group.Count - 1 =>
                                 Group.Members (I).Key = Key
                                 and then Same_Name (Group.Members (I).Name,
                                                     To_Name (Name)))
                       else Key = 0);
   --  Tools.Item (String): the key of the first member named Name;
   --  Bad_Parameter ("Tools: no tool named X") when there is none.

   procedure Group_Abort_Run_On_Tool_Failure
     (Group  : access constant Ks_Tool_Group_Data;
      Value  : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_abort_run_on_tool_failure",
     Post => Valid (Status) and then Succeeded (Status)
             and then Value in False_Value | True_Value
             and then (Value = True_Value)
                        = (Group /= null and then Group.Abort_On_Failure);
   --  AbortRunOnToolFailure (0 for null).

   procedure Group_Set_Abort_Run_On_Tool_Failure
     (Group  : in out Ks_Tool_Group;
      Value  : Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_set_abort_run_on_tool_failure",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Valid_Group (Group)'Old then Valid_Group (Group))
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Group.Abort_On_Failure
                                       = (Value = True_Value)
                            and then Group.Own_Key
                                       = Group_Of (Group)'Old.Own_Key
                            and then Same_Members (Group.all,
                                                   Group_Of (Group)'Old)
                       else Group_Of (Group) = Group_Of (Group)'Old);
   --  Sets AbortRunOnToolFailure (0 or 1, Bad_Parameter otherwise);
   --  creates the group when it is null.

   ---------------------------------------------------------------------
   --  RunTool (a script runs one tool)
   ---------------------------------------------------------------------

   function Disabled_Member
     (Group : access constant Ks_Tool_Group_Data;
      Key   : Int64) return Boolean
   is (Group /= null
       and then (for some I in 0 .. Group.Count - 1 =>
                   Group.Members (I).Key = Key
                   and then Group.Members (I).Disabled));
   --  Key is a member of Group that is in DisabledTools.

   procedure Run_Tool_Begin
     (Group  : access constant Ks_Tool_Group_Data;
      Key    : Int64;
      Run    : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_run_tool_begin",
     Post => Valid (Status) and then Succeeded (Status)
             and then Run in False_Value | True_Value
             and then (Run = False_Value) = Disabled_Member (Group, Key);
   --  RunTool, first step: whether the tool with key Key runs (Run = 1)
   --  or not (0: it is a member of Group in DisabledTools). A tool that
   --  is not a member runs (AMV's choice: VisionPro only says a disabled
   --  tool does not run).

   procedure Run_Tool_End
     (Group      : access constant Ks_Tool_Group_Data;
      Sub_Result : Int32;
      Result     : in out Int32;
      Replace    : out Int32;
      Abort_Run  : out Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_run_tool_end",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Replace in False_Value | True_Value
             and then Abort_Run in False_Value | True_Value
             and then
               (if Succeeded (Status)
                then Sub_Result in Result_Code
                     and then Result'Old in Result_Code
                     and then (Replace = True_Value)
                                = (Rank (Sub_Result) > Rank (Result'Old))
                     and then Result = Worse (Result'Old, Sub_Result)
                     and then (Abort_Run = True_Value)
                                = (Sub_Result = Result_Error
                                   and then Group /= null
                                   and then Group.Abort_On_Failure)
                else Result = Result'Old and then Replace = False_Value
                     and then Abort_Run = False_Value);
   --  RunTool, second step, after the tool ran with result Sub_Result:
   --  Result (the worst result of the script so far) becomes the worse of
   --  the two, and Replace = 1 tells the caller to take the tool's message
   --  too, when the tool's result is strictly worse (Error > Reject >
   --  Warning > Accept). Abort_Run = 1 when the tool reported Error and
   --  the group has AbortRunOnToolFailure: RunTool then raises.
   --  Bad_Parameter for a result code outside CogToolResultConstants.

   ---------------------------------------------------------------------
   --  Runs (C: ks_tool_group_cursor)
   ---------------------------------------------------------------------

   type Ks_Tool_Group_Cursor is record
      Own_Key       : Int64 := 0;
      Change_Count  : Interfaces.Unsigned_64 := 0;
      Run           : Interfaces.Unsigned_64 := 0;
      Next          : Int32 := 0;
      Pending       : Int32 := No_Index;
      Worst         : Int32 := Result_Accept;
      First_Failure : Int32 := No_Index;
      Stopped       : Int32 := False_Value;
      Fault         : Int32 := Fault_None;
      Message       : Ks_Tool_Text;
   end record
     with Convention => C;
   --  The state of a run (C: ks_tool_group_cursor, 1080 bytes): the
   --  group's own key, change counter and run serial at run_begin, the
   --  first member not yet considered (Next), the member offered and not
   --  yet reported (Pending, No_Index for none), the worst result so far,
   --  the first member that did not accept (No_Index for none), whether
   --  the run stopped (abort on failure, or the script's run_tools = 0),
   --  why a call of the run failed (Fault) and the message so far. The
   --  caller passes it from call to call and never changes it.

   function Cursor_Matches
     (Group  : Ks_Tool_Group_Data;
      Cursor : Ks_Tool_Group_Cursor) return Boolean
   is (Group.Active_Run /= 0
       and then Cursor.Run = Group.Active_Run
       and then Cursor.Own_Key = Group.Own_Key);
   --  Cursor belongs to the run in progress on Group.

   function Cursor_Consistent
     (Group  : Ks_Tool_Group_Data;
      Cursor : Ks_Tool_Group_Cursor) return Boolean
   is (Cursor.Next in 0 .. Int32 (Group.Count)
       and then (Cursor.Pending = No_Index
                 or else (Cursor.Pending in 0 .. Int32 (Group.Count) - 1
                          and then Cursor.Pending = Cursor.Next - 1))
       and then Cursor.Worst in Result_Code
       and then (Cursor.First_Failure = No_Index
                 or else Cursor.First_Failure in 0 .. Cursor.Next - 1)
       and then Cursor.Stopped in False_Value | True_Value
       and then Cursor.Fault in Fault_Code
       and then Fits (Cursor.Message));
   --  The fields of Cursor are within their ranges for Group.

   procedure Run_Begin
     (Group          : in out Ks_Tool_Group;
      Script_Result  : Int32;
      Script_Message : Ks_Tool_Text;
      Run_Tools      : Int32;
      Cursor         : out Ks_Tool_Group_Cursor;
      Status         : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_run_begin",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Valid_Group (Group)'Old then Valid_Group (Group))
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Same_Members (Group.all,
                                                   Group_Of (Group)'Old)
                            and then Same_Settings (Group.all,
                                                    Group_Of (Group)'Old)
                            and then Cursor_Matches (Group.all, Cursor)
                            and then Cursor_Consistent (Group.all, Cursor)
                            and then Cursor.Change_Count
                                       = Group.Change_Count
                            and then Cursor.Next = 0
                            and then Cursor.Pending = No_Index
                            and then Cursor.Worst = Script_Result
                            and then Cursor.First_Failure = No_Index
                            and then Cursor.Stopped
                                       = (if Run_Tools = True_Value
                                          then False_Value
                                          else True_Value)
                            and then Cursor.Fault = Fault_None
                       else Group_Of (Group) = Group_Of (Group)'Old);
   --  Begins a run (the group is running until run_end); creates the
   --  group when it is null. Script_Result (a result code) and
   --  Script_Message start the run's result and message; Run_Tools = 0
   --  stops the run before its first member (1 lets the members run).
   --  Bad_Parameter for a bad code or flag, a negative message length, or
   --  a group that is running already.

   procedure Run_Next
     (Group  : access constant Ks_Tool_Group_Data;
      Cursor : in out Ks_Tool_Group_Cursor;
      Index  : out Int32;
      More   : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_run_next",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then More in False_Value | True_Value
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Cursor_Matches (Group.all, Cursor)
                            and then Cursor_Consistent (Group.all, Cursor)
                            and then Cursor.Change_Count = Group.Change_Count
                            and then Cursor.Own_Key = Cursor.Own_Key'Old
                            and then Cursor.Run = Cursor.Run'Old
                            and then Cursor.Worst = Cursor.Worst'Old
                            and then Cursor.First_Failure
                                       = Cursor.First_Failure'Old
                            and then Cursor.Stopped = Cursor.Stopped'Old
                            and then Cursor.Fault = Fault_None
                            and then Cursor.Message = Cursor.Message'Old
                            and then Cursor.Pending'Old = No_Index
                            and then Cursor.Next'Old in 0 .. Int32 (Group.Count)
                            and then Cursor.Next >= Cursor.Next'Old
                            and then (if Cursor.Stopped'Old = True_Value
                                      then More = False_Value
                                           and then Cursor.Next
                                                      = Cursor.Next'Old)
                            and then (if More = True_Value
                                      then Index in Cursor.Next'Old
                                                    .. Int32 (Group.Count) - 1
                                           and then not Group.Members
                                                          (Natural (Index))
                                                          .Disabled
                                           and then (for all J in
                                                       Cursor.Next'Old
                                                       .. Index - 1 =>
                                                       Group.Members
                                                         (Natural (J))
                                                         .Disabled)
                                           and then Cursor.Next = Index + 1
                                           and then Cursor.Pending = Index
                                      else Index = No_Index
                                           and then Cursor.Pending = No_Index)
                            and then (if More = False_Value
                                        and then Cursor.Stopped'Old
                                                   = False_Value
                                      then Cursor.Next = Int32 (Group.Count)
                                           and then (for all J in
                                                       Cursor.Next'Old
                                                       .. Int32 (Group.Count)
                                                          - 1 =>
                                                       Group.Members
                                                         (Natural (J))
                                                         .Disabled))
                       else More = False_Value
                            and then Index = No_Index
                            and then Cursor.Fault /= Fault_None);
   --  The next member to run: the first enabled member from the cursor's
   --  Next on (Index, More = 1; Next becomes Index + 1), or none (More =
   --  0) when every one left is disabled or the run has stopped.
   --  Bad_Parameter (and the cursor marked) for a null group, a cursor
   --  that does not belong to the group's run in progress, a group that
   --  changed after run_begin, a cursor that was marked before or is not
   --  consistent, and while the member offered last has not reported.

   procedure Run_Report
     (Group   : access constant Ks_Tool_Group_Data;
      Cursor  : in out Ks_Tool_Group_Cursor;
      Index   : Int32;
      Result  : Int32;
      Name    : Ks_Tool_Text;
      Message : Ks_Tool_Text;
      Status  : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_run_report",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Cursor_Matches (Group.all, Cursor)
                            and then Cursor_Consistent (Group.all, Cursor)
                            and then Cursor.Change_Count = Group.Change_Count
                            and then Cursor.Own_Key = Cursor.Own_Key'Old
                            and then Cursor.Run = Cursor.Run'Old
                            and then Cursor.Next = Cursor.Next'Old
                            and then Cursor.Fault = Fault_None
                            and then Index >= 0
                            and then Index = Cursor.Pending'Old
                            and then Cursor.Pending = No_Index
                            and then Result in Result_Code
                            and then Cursor.Worst'Old in Result_Code
                            and then Cursor.Worst
                                       = Worse (Cursor.Worst'Old, Result)
                            and then Cursor.First_Failure
                                       = (if Cursor.First_Failure'Old
                                               = No_Index
                                            and then Result /= Result_Accept
                                          then Index
                                          else Cursor.First_Failure'Old)
                            and then Cursor.Stopped
                                       = (if Group.Abort_On_Failure
                                            and then Result = Result_Error
                                          then True_Value
                                          else Cursor.Stopped'Old)
                       else Cursor.Fault /= Fault_None);
   --  Records the result (a code), name and message of the member that
   --  run_next offered last (Index). Bad_Parameter (and the cursor
   --  marked) as for run_next, for an Index that is not the member
   --  offered, a bad result code and a text of negative length.

   procedure Run_End
     (Group         : Ks_Tool_Group;
      Cursor        : in out Ks_Tool_Group_Cursor;
      Result        : out Int32;
      First_Failure : out Int32;
      Message       : out Ks_Tool_Text;
      Status        : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_group_run_end",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result in Result_Code
             and then First_Failure >= No_Index
             and then Fits (Message)
             and then (if Valid_Group (Group)'Old then Valid_Group (Group))
             and then (if Group /= null
                       then Same_Members (Group.all, Group_Of (Group)'Old)
                            and then Same_Settings (Group.all,
                                                    Group_Of (Group)'Old)
                            and then Group.Change_Count
                                       = Group_Of (Group)'Old.Change_Count)
             and then (if Group /= null
                         and then Cursor_Matches (Group_Of (Group)'Old,
                                                  Cursor'Old)
                       then Group.Active_Run = 0)
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Group.Active_Run = 0
                            and then Result = Cursor.Worst'Old
                            and then First_Failure
                                       = Cursor.First_Failure'Old
                            and then Message = Cursor.Message'Old
                       else Result = Result_Error
                            and then First_Failure = No_Index
                            and then Message.Length = 0);
   --  Ends the run and returns its result, the index of the first member
   --  that did not accept (No_Index for none) and its message. A cursor
   --  that belongs to the run in progress always ends it; Bad_Parameter
   --  for any other cursor, and (the run ended anyway) when the group
   --  changed during the run, a call of the run failed, the cursor is not
   --  consistent, or the member offered last has not reported.

   ---------------------------------------------------------------------
   --  Terminals (C: ks_tool_block_terminals)
   ---------------------------------------------------------------------

   subtype Terminal_Count is Natural range 0 .. Max_Terminals;
   subtype Terminal_Index is Natural range 0 .. Max_Terminals - 1;

   subtype Value_Length is Natural range 0 .. Max_Text_Length;

   type Stored_Text is record
      Length : Value_Length := 0;
      Text   : Text_Array   := [others => ASCII.NUL];
   end record;
   --  A stored string value: Text (1 .. Length), NUL characters after it.

   type Terminal is record
      Name          : Terminal_Name;
      Value_Type    : Value_Type_Code := Type_Real;
      Has_Value     : Boolean := True;
      Real_Value    : Long_Float := 0.0;
      Integer_Value : Int64 := 0;
      Boolean_Value : Boolean := False;
      String_Value  : Stored_Text;
   end record;
   --  One terminal. Only the value of its type is meaningful; Has_Value
   --  is True for the scalar types.

   type Terminal_Array is array (Terminal_Index) of Terminal;

   type Ks_Tool_Block_Terminals_Data is record
      Count : Terminal_Count := 0;
      Items : Terminal_Array;
   end record;
   --  What a collection handle designates (opaque for C): the terminals
   --  Items (0 .. Count - 1).

   type Ks_Tool_Block_Terminals is access Ks_Tool_Block_Terminals_Data
     with Convention => C;
   --  C: ks_tool_block_terminals *.

   Empty_Terminals : constant Ks_Tool_Block_Terminals_Data :=
     (others => <>)
     with Ghost;

   function Terminals_Of
     (Terminals : access constant Ks_Tool_Block_Terminals_Data)
      return Ks_Tool_Block_Terminals_Data
   is (if Terminals = null then Empty_Terminals else Terminals.all)
   with Ghost;
   --  The contents of a handle (an empty collection for null).

   function Terminal_Count_Of
     (Terminals : access constant Ks_Tool_Block_Terminals_Data)
      return Terminal_Count
   is (if Terminals = null then 0 else Terminals.Count);

   function Distinct_Names (Terminals : Ks_Tool_Block_Terminals_Data)
      return Boolean
   is (for all I in 0 .. Terminals.Count - 1 =>
         (for all J in 0 .. Terminals.Count - 1 =>
            (if I /= J
             then not Same_Name (Terminals.Items (I).Name,
                                 Terminals.Items (J).Name))))
   with Ghost;
   --  No two terminals have the same name (Gold).

   function Valid_Terminals
     (Terminals : access constant Ks_Tool_Block_Terminals_Data)
      return Boolean
   is (Terminals = null or else Distinct_Names (Terminals.all))
   with Ghost;

   function Name_Fits (Name : Ks_Tool_Text) return Boolean is
     (Name.Length in 1 .. Max_Name_Length);
   --  Name can name a terminal.


   function Find
     (Terminals : Ks_Tool_Block_Terminals_Data;
      Name      : Terminal_Name) return Int32
   with
     Post => Find'Result in No_Index .. Int32 (Terminals.Count) - 1
             and then (if Find'Result = No_Index
                       then (for all J in 0 .. Terminals.Count - 1 =>
                               not Same_Name (Terminals.Items (J).Name, Name)
                               and then not Same_Name
                                              (Name, Terminals.Items (J).Name))
                       else Same_Name
                              (Terminals.Items (Natural (Find'Result)).Name,
                               Name));
   --  The index of the terminal named Name, No_Index when there is none.

   function Holds
     (Terminals  : Ks_Tool_Block_Terminals_Data;
      Name       : Terminal_Name;
      Value_Type : Value_Type_Code) return Boolean
   is ((for some J in 0 .. Terminals.Count - 1 =>
          Same_Name (Terminals.Items (J).Name, Name))
       and then (for all J in 0 .. Terminals.Count - 1 =>
                   (if Same_Name (Terminals.Items (J).Name, Name)
                    then Terminals.Items (J).Value_Type = Value_Type)))
   with Ghost;
   --  A terminal is named Name, and the one so named is of Value_Type.

   function Holds_Real
     (Terminals : Ks_Tool_Block_Terminals_Data;
      Name      : Terminal_Name;
      Value     : Long_Float) return Boolean
   is (Holds (Terminals, Name, Type_Real)
       and then (for all J in 0 .. Terminals.Count - 1 =>
                   (if Same_Name (Terminals.Items (J).Name, Name)
                    then Terminals.Items (J).Real_Value = Value)))
   with Ghost;

   function Holds_Integer
     (Terminals : Ks_Tool_Block_Terminals_Data;
      Name      : Terminal_Name;
      Value     : Int64) return Boolean
   is (Holds (Terminals, Name, Type_Integer)
       and then (for all J in 0 .. Terminals.Count - 1 =>
                   (if Same_Name (Terminals.Items (J).Name, Name)
                    then Terminals.Items (J).Integer_Value = Value)))
   with Ghost;

   function Holds_Boolean
     (Terminals : Ks_Tool_Block_Terminals_Data;
      Name      : Terminal_Name;
      Value     : Boolean) return Boolean
   is (Holds (Terminals, Name, Type_Boolean)
       and then (for all J in 0 .. Terminals.Count - 1 =>
                   (if Same_Name (Terminals.Items (J).Name, Name)
                    then Terminals.Items (J).Boolean_Value = Value)))
   with Ghost;

   function Same_Text (Stored : Stored_Text; Text : Ks_Tool_Text)
      return Boolean
   is (Text.Length = Int32 (Stored.Length)
       and then (for all K in 1 .. Stored.Length =>
                   Stored.Text (K) = Text.Text (K)))
   with Ghost;
   --  Stored holds the characters of Text.

   function Holds_String
     (Terminals : Ks_Tool_Block_Terminals_Data;
      Name      : Terminal_Name;
      Value     : Ks_Tool_Text) return Boolean
   is (Holds (Terminals, Name, Type_String)
       and then (for all J in 0 .. Terminals.Count - 1 =>
                   (if Same_Name (Terminals.Items (J).Name, Name)
                    then Same_Text (Terminals.Items (J).String_Value,
                                    Value))))
   with Ghost;

   function Only_Value_Changed
     (Before, After : Ks_Tool_Block_Terminals_Data;
      Name          : Terminal_Name) return Boolean
   is (After.Count = Before.Count
       and then (for all J in 0 .. After.Count - 1 =>
                   After.Items (J).Name = Before.Items (J).Name
                   and then After.Items (J).Value_Type
                              = Before.Items (J).Value_Type
                   and then (if not Same_Name (After.Items (J).Name, Name)
                             then After.Items (J) = Before.Items (J))))
   with Ghost;
   --  After differs from Before at most in the value of the terminal
   --  named Name.

   procedure Terminals_Create
     (Terminals : out Ks_Tool_Block_Terminals;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_create",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Terminals /= null and then Terminals.Count = 0
                       else Terminals = null);
   --  A new empty collection.

   procedure Terminals_Destroy (Terminals : in out Ks_Tool_Block_Terminals)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_destroy",
     Post => Terminals = null;
   --  Frees the collection (nothing for null).

   procedure Terminals_Duplicate
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Copy      : out Ks_Tool_Block_Terminals;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_duplicate",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status) and then Terminals /= null
                       then Copy /= null and then Copy.all = Terminals.all
                       else Copy = null);
   --  A new collection with the same terminals (null for null). The
   --  caller copies the object values it keeps.

   procedure Terminals_Count
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Count     : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_count",
     Post => Valid (Status) and then Succeeded (Status)
             and then Count = Int32 (Terminal_Count_Of (Terminals));
   --  Count (0 for null).

   procedure Terminals_Clear
     (Terminals : Ks_Tool_Block_Terminals;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_clear",
     Post => Valid (Status) and then Succeeded (Status)
             and then Terminal_Count_Of (Terminals) = 0;
   --  Clear: removes every terminal (nothing for null).

   procedure Terminals_Add
     (Terminals  : in out Ks_Tool_Block_Terminals;
      Name       : Ks_Tool_Text;
      Value_Type : Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_add",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Value_Type in Value_Type_Code
                            and then Terminals.Count
                                       = Terminal_Count_Of (Terminals)'Old + 1
                            and then Terminals.Items (Terminals.Count - 1).Name
                                       = To_Name (Name)
                            and then Terminals.Items (Terminals.Count - 1)
                                       .Value_Type = Value_Type
                            and then (for all J in 0 .. Terminals.Count - 2 =>
                                        Terminals.Items (J)
                                          = Terminals_Of (Terminals)'Old
                                              .Items (J))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  Add: appends a terminal Name of Value_Type with the default value
   --  (0.0, 0, False, "", none for an object type); creates the
   --  collection when it is null. Bad_Parameter for a name that is not 1
   --  to Max_Name_Length characters long or names a terminal already, a
   --  bad type code, and when the collection holds Max_Terminals.

   procedure Terminals_Add_Real
     (Terminals : in out Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_add_real",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Terminals.Count
                                       = Terminal_Count_Of (Terminals)'Old + 1
                            and then (if Valid_Terminals (Terminals)'Old
                                      then Holds_Real (Terminals.all,
                                                       To_Name (Name), Value))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  Add with an initial Real value (finite; Bad_Parameter otherwise).
   --  Bad_Parameter for the name and the count as for Add.

   procedure Terminals_Add_Integer
     (Terminals : in out Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Int64;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_add_integer",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Terminals.Count
                                       = Terminal_Count_Of (Terminals)'Old + 1
                            and then (if Valid_Terminals (Terminals)'Old
                                      then Holds_Integer
                                             (Terminals.all, To_Name (Name),
                                              Value))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  Add with an initial Integer value.

   procedure Terminals_Add_Boolean
     (Terminals : in out Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_add_boolean",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Value in False_Value | True_Value
                            and then Terminals.Count
                                       = Terminal_Count_Of (Terminals)'Old + 1
                            and then (if Valid_Terminals (Terminals)'Old
                                      then Holds_Boolean
                                             (Terminals.all, To_Name (Name),
                                              Value = True_Value))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  Add with an initial Boolean value (0 or 1, Bad_Parameter otherwise).

   procedure Terminals_Add_String
     (Terminals : in out Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Ks_Tool_Text;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_add_string",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Fits (Value)
                            and then Terminals.Count
                                       = Terminal_Count_Of (Terminals)'Old + 1
                            and then (if Valid_Terminals (Terminals)'Old
                                      then Holds_String
                                             (Terminals.all, To_Name (Name),
                                              Value))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  Add with an initial String value (0 to Max_Text_Length characters,
   --  Bad_Parameter otherwise).

   procedure Terminals_Add_Object
     (Terminals  : in out Ks_Tool_Block_Terminals;
      Name       : Ks_Tool_Text;
      Value_Type : Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_add_object",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Value_Type in Object_Type_Code
                            and then Terminals.Count
                                       = Terminal_Count_Of (Terminals)'Old + 1
                            and then Terminals.Items (Terminals.Count - 1).Name
                                       = To_Name (Name)
                            and then Terminals.Items (Terminals.Count - 1)
                                       .Value_Type = Value_Type
                            and then Terminals.Items (Terminals.Count - 1)
                                       .Has_Value
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  Add of an object terminal (Image_8_Grey, Image_16_Grey, Transform or
   --  Shape; Bad_Parameter for another code) that has a value: the caller
   --  stores the object at the new last index.

   procedure Terminals_Insert
     (Terminals  : in out Ks_Tool_Block_Terminals;
      Index      : Int32;
      Name       : Ks_Tool_Text;
      Value_Type : Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_insert",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
                         | Failure_Out_Of_Memory
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Index in 0 .. Int32 (Terminals.Count) - 1
                            and then Terminals.Count
                                       = Terminal_Count_Of (Terminals)'Old + 1
                            and then Terminals.Items (Natural (Index)).Name
                                       = To_Name (Name)
                            and then Terminals.Items (Natural (Index))
                                       .Value_Type = Value_Type
                            and then (for all J in 0 .. Terminals.Count - 1 =>
                                        (if J < Natural (Index)
                                         then Terminals.Items (J)
                                                = Terminals_Of (Terminals)'Old
                                                    .Items (J)
                                         elsif J > Natural (Index)
                                         then Terminals.Items (J)
                                                = Terminals_Of (Terminals)'Old
                                                    .Items (J - 1)))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  Insert: inserts a terminal Name of Value_Type with the default value
   --  at Index (0 .. Count; Index_Out_Of_Range otherwise); the later
   --  terminals move up by one. Creates the collection when it is null.
   --  Bad_Parameter as for Add.

   procedure Terminals_Remove_At
     (Terminals : Ks_Tool_Block_Terminals;
      Index     : Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_remove_at",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Index_Out_Of_Range
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Index >= 0
                            and then Natural (Index)
                                       <= Terminal_Count_Of (Terminals)'Old - 1
                            and then Terminals.Count
                                       = Terminal_Count_Of (Terminals)'Old - 1
                            and then (for all J in 0 .. Terminals.Count - 1 =>
                                        Terminals.Items (J)
                                          = (if J < Natural (Index)
                                             then Terminals_Of (Terminals)'Old
                                                    .Items (J)
                                             else Terminals_Of (Terminals)'Old
                                                    .Items (J + 1)))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  RemoveAt: removes terminal Index (0 .. Count - 1,
   --  Index_Out_Of_Range otherwise); the later ones move down by one.

   procedure Terminals_Remove
     (Terminals : Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Index     : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_remove",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Index >= 0
                            and then Natural (Index)
                                       <= Terminal_Count_Of (Terminals)'Old - 1
                            and then Same_Name
                                       (Terminals_Of (Terminals)'Old.Items
                                          (Natural (Index)).Name,
                                        To_Name (Name))
                            and then Terminals.Count
                                       = Terminal_Count_Of (Terminals)'Old - 1
                            and then (for all J in 0 .. Terminals.Count - 1 =>
                                        Terminals.Items (J)
                                          = (if J < Natural (Index)
                                             then Terminals_Of (Terminals)'Old
                                                    .Items (J)
                                             else Terminals_Of (Terminals)'Old
                                                    .Items (J + 1)))
                       else Index = No_Index
                            and then Terminals_Of (Terminals)
                                       = Terminals_Of (Terminals)'Old);
   --  Remove (name): removes the terminal Name and returns the index it
   --  had. Bad_Parameter when no terminal is so named.

   procedure Terminals_Move
     (Terminals  : Ks_Tool_Block_Terminals;
      From_Index : Int32;
      To_Index   : Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_move",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Index_Out_Of_Range
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then From_Index
                                       in 0 .. Int32 (Terminals.Count) - 1
                            and then To_Index
                                       in 0 .. Int32 (Terminals.Count) - 1
                            and then Terminals.Count
                                       = Terminal_Count_Of (Terminals)'Old
                            and then Terminals.Items (Natural (To_Index))
                                       = Terminals_Of (Terminals)'Old.Items
                                           (Natural (From_Index))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  Move: the terminal at From_Index moves to To_Index (both in
   --  0 .. Count - 1, Index_Out_Of_Range otherwise); those between move by
   --  one to make room.

   procedure Terminals_Index_Of
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Index     : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_index_of",
     Post => Valid (Status) and then Succeeded (Status)
             and then Index
                        in No_Index .. Int32 (Terminal_Count_Of (Terminals)) - 1
             and then (if Index /= No_Index
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Same_Name
                                       (Terminals.Items (Natural (Index)).Name,
                                        To_Name (Name))
                       elsif Terminals /= null and then Name_Fits (Name)
                       then (for all J in 0 .. Terminals.Count - 1 =>
                               not Same_Name (Terminals.Items (J).Name,
                                              To_Name (Name))));
   --  IndexOf (name) / Contains (name): the index of the terminal Name,
   --  No_Index when there is none (also for a name no terminal can have).

   procedure Terminals_Name
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Index     : Int32;
      Name      : out Ks_Tool_Text;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_name",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Index_Out_Of_Range
             and then Fits (Name)
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Index in 0 .. Int32 (Terminals.Count) - 1
                            and then Name.Length
                                       = Int32 (Terminals.Items
                                                  (Natural (Index))
                                                  .Name.Length)
                            and then (for all K in 1 .. Natural (Name.Length)
                                      => Name.Text (K)
                                           = Terminals.Items (Natural (Index))
                                               .Name.Text (K))
                       else Name.Length = 0);
   --  Item (Index).Name. Index_Out_Of_Range outside 0 .. Count - 1.

   procedure Terminals_Value_Type
     (Terminals  : access constant Ks_Tool_Block_Terminals_Data;
      Name       : Ks_Tool_Text;
      Value_Type : out Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_value_type",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Value_Type in Value_Type_Code
                            and then (if Distinct_Names (Terminals.all)
                                      then Holds (Terminals.all,
                                                  To_Name (Name),
                                                  Value_Type))
                       else Value_Type = Type_Real);
   --  Item (Name).ValueType. Bad_Parameter when no terminal is so named.

   procedure Terminals_Has_Value
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Has_Value : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_has_value",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Has_Value in False_Value | True_Value;
   --  1 when the terminal Name has a value (always for a scalar type; for
   --  an object type once one was given), 0 otherwise. Bad_Parameter when
   --  no terminal is so named.

   procedure Terminals_Set_Real
     (Terminals : Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_set_real",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Only_Value_Changed
                                       (Terminals_Of (Terminals)'Old,
                                        Terminals.all, To_Name (Name))
                            and then (if Valid_Terminals (Terminals)'Old
                                      then Holds_Real (Terminals.all,
                                                       To_Name (Name), Value))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  Item (Name).Value := Value for a Real terminal. Bad_Parameter for an
   --  unknown name, a terminal of another type and a value that is not
   --  finite; a failed set changes nothing.

   procedure Terminals_Get_Real
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Value     : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_get_real",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then (if Distinct_Names (Terminals.all)
                                      then Holds_Real (Terminals.all,
                                                       To_Name (Name), Value))
                       else Value = 0.0);
   --  The value of the Real terminal Name. Bad_Parameter for an unknown
   --  name and a terminal of another type.

   procedure Terminals_Set_Integer
     (Terminals : Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Int64;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_set_integer",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Only_Value_Changed
                                       (Terminals_Of (Terminals)'Old,
                                        Terminals.all, To_Name (Name))
                            and then (if Valid_Terminals (Terminals)'Old
                                      then Holds_Integer
                                             (Terminals.all, To_Name (Name),
                                              Value))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  As Set_Real for an Integer terminal.

   procedure Terminals_Get_Integer
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Value     : out Int64;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_get_integer",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then (if Distinct_Names (Terminals.all)
                                      then Holds_Integer
                                             (Terminals.all, To_Name (Name),
                                              Value))
                       else Value = 0);
   --  As Get_Real for an Integer terminal.

   procedure Terminals_Set_Boolean
     (Terminals : Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_set_boolean",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Value in False_Value | True_Value
                            and then Only_Value_Changed
                                       (Terminals_Of (Terminals)'Old,
                                        Terminals.all, To_Name (Name))
                            and then (if Valid_Terminals (Terminals)'Old
                                      then Holds_Boolean
                                             (Terminals.all, To_Name (Name),
                                              Value = True_Value))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  As Set_Real for a Boolean terminal (0 or 1, Bad_Parameter
   --  otherwise).

   procedure Terminals_Get_Boolean
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Value     : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_get_boolean",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Value in False_Value | True_Value
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then (if Distinct_Names (Terminals.all)
                                      then Holds_Boolean
                                             (Terminals.all, To_Name (Name),
                                              Value = True_Value))
                       else Value = False_Value);
   --  As Get_Real for a Boolean terminal (0 or 1).

   procedure Terminals_Set_String
     (Terminals : Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Ks_Tool_Text;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_set_string",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Fits (Value)
                            and then Only_Value_Changed
                                       (Terminals_Of (Terminals)'Old,
                                        Terminals.all, To_Name (Name))
                            and then (if Valid_Terminals (Terminals)'Old
                                      then Holds_String
                                             (Terminals.all, To_Name (Name),
                                              Value))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  As Set_Real for a String terminal (0 to Max_Text_Length characters,
   --  Bad_Parameter otherwise).

   procedure Terminals_Get_String
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Value     : out Ks_Tool_Text;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_get_string",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Fits (Value)
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then (if Distinct_Names (Terminals.all)
                                      then Holds_String
                                             (Terminals.all, To_Name (Name),
                                              Value))
                       else Value.Length = 0);
   --  As Get_Real for a String terminal.

   procedure Terminals_Set_Object
     (Terminals  : Ks_Tool_Block_Terminals;
      Name       : Ks_Tool_Text;
      Value_Type : Int32;
      Index      : out Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_set_object",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Value_Type in Object_Type_Code
                            and then Index in 0 .. Int32 (Terminals.Count) - 1
                            and then Same_Name
                                       (Terminals.Items (Natural (Index)).Name,
                                        To_Name (Name))
                            and then Terminals.Items (Natural (Index))
                                       .Value_Type = Value_Type
                            and then Terminals.Items (Natural (Index))
                                       .Has_Value
                            and then Only_Value_Changed
                                       (Terminals_Of (Terminals)'Old,
                                        Terminals.all, To_Name (Name))
                       else Index = No_Index
                            and then Terminals_Of (Terminals)
                                       = Terminals_Of (Terminals)'Old);
   --  The check before the caller stores an object as the value of the
   --  terminal Name: the terminal exists and has the object type
   --  Value_Type (Bad_Parameter otherwise, nothing changed); it is marked
   --  as having a value, and Index is where the caller stores the object.

   procedure Terminals_Get_Object
     (Terminals  : access constant Ks_Tool_Block_Terminals_Data;
      Name       : Ks_Tool_Text;
      Value_Type : Int32;
      Index      : out Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_tool_block_terminals_get_object",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Index in 0 .. Int32 (Terminals.Count) - 1
                            and then Same_Name
                                       (Terminals.Items (Natural (Index)).Name,
                                        To_Name (Name))
                            and then Terminals.Items (Natural (Index))
                                       .Value_Type = Value_Type
                            and then Terminals.Items (Natural (Index))
                                       .Has_Value
                       else Index = No_Index);
   --  The check before the caller reads the object value of the terminal
   --  Name: it exists, has the object type Value_Type and has a value
   --  (Bad_Parameter otherwise); Index is where the caller keeps the
   --  object.

end AMV.Kernels.Tool_Group;
