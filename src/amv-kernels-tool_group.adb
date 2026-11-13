pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

package body AMV.Kernels.Tool_Group with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);

   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Tool_Group_Data, Ks_Tool_Group);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Tool_Block_Terminals_Data, Ks_Tool_Block_Terminals);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Group (Group : out Ks_Tool_Group)
   with
     Global => null,
     Post   => (if Group /= null
                then Group.Count = 0
                     and then Group.Own_Key = 0
                     and then not Group.Abort_On_Failure
                     and then Group.Change_Count = 0
                     and then Group.Last_Run = 0
                     and then Group.Active_Run = 0);
   --  A new empty group with the record's defaults, or null when the
   --  memory cannot be allocated. Trusted: the allocator raises
   --  Storage_Error, which SPARK cannot express.

   procedure Allocate_Group (Group : out Ks_Tool_Group)
     with SPARK_Mode => Off
   is
   begin
      Group := new Ks_Tool_Group_Data;
   exception
      when Storage_Error =>
         Group := null;
   end Allocate_Group;

   procedure Allocate_Terminals (Terminals : out Ks_Tool_Block_Terminals)
   with
     Global => null,
     Post   => (if Terminals /= null then Terminals.Count = 0);
   --  A new empty collection, or null. Trusted as above.

   procedure Allocate_Terminals (Terminals : out Ks_Tool_Block_Terminals)
     with SPARK_Mode => Off
   is
   begin
      Terminals := new Ks_Tool_Block_Terminals_Data;
   exception
      when Storage_Error =>
         Terminals := null;
   end Allocate_Terminals;

   ---------------------------------------------------------------------
   --  Messages and texts
   ---------------------------------------------------------------------

   procedure Bad (Status : out Ks_Status; Message : String)
   with
     Pre  => Message'Length <= 400,
     Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Out_Of_Range (Status : out Ks_Status; Message : String)
   with
     Pre  => Message'Length <= 400,
     Post => Valid (Status)
             and then Status.Failure = Failure_Index_Out_Of_Range;

   procedure Out_Of_Range (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Index_Out_Of_Range, Message);
   end Out_Of_Range;

   procedure No_Memory (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Out_Of_Memory;

   procedure No_Memory (Status : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Out_Of_Memory,
                   "not enough memory for the tool group or terminals");
   end No_Memory;

   function Image_Of (Value : Int64) return String
   with Pre  => Value >= 0,
        Post => Image_Of'Result'First = 1
                and then Image_Of'Result'Length in 1 .. 20;
   --  The decimal digits of Value.

   function Image_Of (Value : Int64) return String is
      Text  : String (1 .. 20) := [others => '0'];
      Rest  : Int64 := Value;
      First : Positive;
   begin
      for K in reverse 1 .. 20 loop
         Text (K) := Character'Val (Character'Pos ('0') + Rest mod 10);
         Rest := Rest / 10;
         First := K;
         exit when Rest = 0;
         pragma Loop_Invariant (First = K and then Rest >= 1);
      end loop;
      declare
         Last   : constant Natural := 21 - First;
         Result : constant String (1 .. Last) := Text (First .. 20);
      begin
         return Result;
      end;
   end Image_Of;

   function To_Text (Source : String) return Ks_Tool_Text is
      Kept   : constant Natural := Natural'Min (Source'Length,
                                                Max_Text_Length);
      Result : Ks_Tool_Text := (Length => Int32 (Source'Length),
                                Text   => [others => ASCII.NUL]);
   begin
      for J in 1 .. Kept loop
         Result.Text (J) := Source (Source'First + (J - 1));
         pragma Loop_Invariant
           (Result.Length = Int32 (Source'Length)
            and then (for all K in 1 .. J
                      => Result.Text (K) = Source (Source'First + (K - 1))));
      end loop;
      return Result;
   end To_Text;

   function To_String (Text : Ks_Tool_Text) return String is
     (String (Text.Text (1 .. Integer (Text.Length))));

   function Copy_Text (Source : Ks_Tool_Text) return Ks_Tool_Text
   with
     Pre  => Source.Length >= 0,
     Post => Fits (Copy_Text'Result);
   --  The characters of Source that a text holds (the first
   --  Max_Text_Length of a longer one), NUL characters after them.

   function Copy_Text (Source : Ks_Tool_Text) return Ks_Tool_Text is
      Kept : constant Natural :=
        Natural (Int32'Min (Source.Length, Max_Text_Length));
   begin
      return (Length => Int32 (Kept),
              Text   => [for K in 1 .. Max_Text_Length =>
                            (if K <= Kept then Source.Text (K)
                             else ASCII.NUL)]);
   end Copy_Text;

   procedure Append (Text : in out Ks_Tool_Text; Source : String)
   with
     Pre  => Fits (Text),
     Post => Fits (Text);
   --  Appends the characters of Source that still fit.

   procedure Append (Text : in out Ks_Tool_Text; Source : String) is
   begin
      for J in Source'Range loop
         pragma Loop_Invariant (Fits (Text));
         exit when Text.Length = Max_Text_Length;
         Text.Length := Text.Length + 1;
         Text.Text (Positive (Text.Length)) := Source (J);
      end loop;
   end Append;

   procedure Append_Text (Text : in out Ks_Tool_Text; Source : Ks_Tool_Text)
   with
     Pre  => Fits (Text) and then Source.Length >= 0,
     Post => Fits (Text);
   --  Appends the characters Source holds that still fit.

   procedure Append_Text (Text : in out Ks_Tool_Text; Source : Ks_Tool_Text)
   is
      Kept : constant Natural :=
        Natural (Int32'Min (Source.Length, Max_Text_Length));
   begin
      for J in 1 .. Kept loop
         pragma Loop_Invariant (Fits (Text));
         exit when Text.Length = Max_Text_Length;
         Text.Length := Text.Length + 1;
         Text.Text (Positive (Text.Length)) := Source.Text (J);
      end loop;
   end Append_Text;

   function Result_Word (Result : Result_Code) return String
   with Post => Result_Word'Result'First = 1
                and then Result_Word'Result'Length <= 7;
   --  The name of a result (CogToolResultConstants).

   function Result_Word (Result : Result_Code) return String is
     (case Result is
         when Result_Accept  => "Accept",
         when Result_Warning => "Warning",
         when Result_Reject  => "Reject",
         when others         => "Error");

   ---------------------------------------------------------------------
   --  Groups
   ---------------------------------------------------------------------

   function Same_Group (Left, Right : Ks_Tool_Group_Data) return Boolean
   is (Same_Members (Left, Right)
       and then Same_Settings (Left, Right)
       and then Left.Change_Count = Right.Change_Count
       and then Left.Last_Run = Right.Last_Run
       and then Left.Active_Run = Right.Active_Run)
   with Ghost;
   --  Everything but the unused member slots is the same.

   function Is_Null (Group : access constant Ks_Tool_Group_Data)
      return Boolean
   is (Group = null)
   with Ghost;

   procedure Ensure_Group (Group : in out Ks_Tool_Group; Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Same_Group (Group.all,
                                                 Group_Of (Group)'Old)
                       else Group = null and then Is_Null (Group)'Old);
   --  Creates the group when it is null.

   procedure Ensure_Group (Group : in out Ks_Tool_Group; Status : out Ks_Status)
   is
   begin
      if Group = null then
         Allocate_Group (Group);
         if Group = null then
            No_Memory (Status);
            return;
         end if;
      end if;
      Set_Success (Status);
   end Ensure_Group;

   function Find_Member (Group : Ks_Tool_Group_Data; Key : Int64)
      return Int32
   with
     Post => Find_Member'Result in No_Index .. Int32 (Group.Count) - 1
             and then (if Find_Member'Result = No_Index
                       then not Member_Of (Group, Key)
                       else Group.Members (Natural (Find_Member'Result)).Key
                              = Key);
   --  The index of the member Key, No_Index when it is not a member.

   function Find_Member (Group : Ks_Tool_Group_Data; Key : Int64)
      return Int32 is
   begin
      for I in 0 .. Group.Count - 1 loop
         if Group.Members (I).Key = Key then
            return Int32 (I);
         end if;
         pragma Loop_Invariant
           (for all J in 0 .. I => Group.Members (J).Key /= Key);
      end loop;
      return No_Index;
   end Find_Member;

   procedure Advance (Counter : in out Interfaces.Unsigned_64)
   with Post => Counter = Counter'Old + 1;
   --  Counts one change (wrapping around after 2**64 of them).

   procedure Advance (Counter : in out Interfaces.Unsigned_64) is
   begin
      Counter := Counter + 1;
   end Advance;

   procedure Group_Create
     (Own_Key : Int64;
      Group   : out Ks_Tool_Group;
      Status  : out Ks_Status) is
   begin
      Allocate_Group (Group);
      if Group = null then
         No_Memory (Status);
         return;
      end if;
      Group.Own_Key := Own_Key;
      Set_Success (Status);
   end Group_Create;

   procedure Group_Destroy (Group : in out Ks_Tool_Group) is
   begin
      Free (Group);
   end Group_Destroy;

   procedure Group_Duplicate
     (Group  : access constant Ks_Tool_Group_Data;
      Copy   : out Ks_Tool_Group;
      Status : out Ks_Status) is
   begin
      Copy := null;
      if Group = null then
         Set_Success (Status);
         return;
      end if;
      Allocate_Group (Copy);
      if Copy = null then
         No_Memory (Status);
         return;
      end if;
      Copy.all := Group.all;
      Copy.Active_Run := 0;
      Set_Success (Status);
   end Group_Duplicate;

   procedure Group_Own_Key
     (Group  : access constant Ks_Tool_Group_Data;
      Key    : out Int64;
      Status : out Ks_Status) is
   begin
      Key := (if Group = null then 0 else Group.Own_Key);
      Set_Success (Status);
   end Group_Own_Key;

   procedure Group_Set_Own_Key
     (Group  : in out Ks_Tool_Group;
      Key    : Int64;
      Status : out Ks_Status) is
   begin
      if Group /= null and then Key /= Group.Own_Key then
         if Group.Active_Run /= 0 then
            Bad (Status, "Run: the group is running already (a group "
                         & "cannot contain itself, directly or through "
                         & "other groups)");
            return;
         elsif Find_Member (Group.all, Key) /= No_Index then
            Bad (Status, "Tools: a group cannot contain itself");
            return;
         end if;
      end if;
      Ensure_Group (Group, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Group.Own_Key /= Key then
         Group.Own_Key := Key;
         Advance (Group.Change_Count);
      end if;
   end Group_Set_Own_Key;

   procedure Group_Count
     (Group  : access constant Ks_Tool_Group_Data;
      Count  : out Int32;
      Status : out Ks_Status) is
   begin
      Count := Int32 (Count_Of (Group));
      Set_Success (Status);
   end Group_Count;

   procedure Bad_Member_Index
     (Status : out Ks_Status;
      Index  : Int32;
      Count  : Member_Count)
   with
     Post => Valid (Status)
             and then Status.Failure = Failure_Index_Out_Of_Range;
   --  The failure for an index outside 0 .. Count - 1.

   procedure Bad_Member_Index
     (Status : out Ks_Status;
      Index  : Int32;
      Count  : Member_Count) is
   begin
      if Index < 0 then
         Out_Of_Range (Status, "Tools: the index must be >= 0");
      else
         Out_Of_Range (Status, "Tools: the index must be below Count ("
                               & Image_Of (Int64 (Count)) & ")");
      end if;
   end Bad_Member_Index;

   procedure Group_Item
     (Group  : access constant Ks_Tool_Group_Data;
      Index  : Int32;
      Key    : out Int64;
      Status : out Ks_Status) is
   begin
      Key := 0;
      if Index < 0 or else Index >= Int32 (Count_Of (Group)) then
         Bad_Member_Index (Status, Index, Count_Of (Group));
         return;
      end if;
      Key := Group.Members (Natural (Index)).Key;
      Set_Success (Status);
   end Group_Item;

   procedure Group_Index_Of
     (Group  : access constant Ks_Tool_Group_Data;
      Key    : Int64;
      Index  : out Int32;
      Status : out Ks_Status) is
   begin
      Index := (if Group = null then No_Index
                else Find_Member (Group.all, Key));
      Set_Success (Status);
   end Group_Index_Of;

   procedure Check_New_Member
     (Group     : access constant Ks_Tool_Group_Data;
      Key       : Int64;
      Operation : String;
      Status    : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 20,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Count_Of (Group) < Max_Members
                            and then Key
                                       /= (if Group = null then 0
                                           else Group.Own_Key)
                            and then (if Group /= null
                                      then not Member_Of (Group.all, Key)));
   --  Key may join the group: it is neither the own key nor a member, and
   --  the group has room.

   procedure Check_New_Member
     (Group     : access constant Ks_Tool_Group_Data;
      Key       : Int64;
      Operation : String;
      Status    : out Ks_Status) is
   begin
      if Key = (if Group = null then 0 else Group.Own_Key) then
         Bad (Status, Operation & ": a group cannot contain itself");
      elsif Group /= null and then Find_Member (Group.all, Key) /= No_Index
      then
         Bad (Status, Operation & ": the tool is a member of the group "
                      & "already");
      elsif Count_Of (Group) = Max_Members then
         Bad (Status, Operation & ": a group holds at most 256 tools");
      else
         Set_Success (Status);
      end if;
   end Check_New_Member;

   procedure Group_Add
     (Group  : in out Ks_Tool_Group;
      Key    : Int64;
      Status : out Ks_Status) is
   begin
      Check_New_Member (Group, Key, "Tools.Add", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Ensure_Group (Group, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Last : constant Member_Index := Group.Count;
      begin
         Group.Members (Last) :=
           (Key => Key, Disabled => False, Name => No_Name);
         Group.Count := Last + 1;
         Advance (Group.Change_Count);
      end;
   end Group_Add;

   procedure Group_Insert
     (Group  : in out Ks_Tool_Group;
      Index  : Int32;
      Key    : Int64;
      Status : out Ks_Status) is
   begin
      if Index < 0 or else Index > Int32 (Count_Of (Group)) then
         if Index < 0 then
            Out_Of_Range (Status, "Tools.Insert: the index must be >= 0");
         else
            Out_Of_Range (Status, "Tools.Insert: the index must be at most "
                                  & "Count ("
                                  & Image_Of (Int64 (Count_Of (Group)))
                                  & ")");
         end if;
         return;
      end if;
      Check_New_Member (Group, Key, "Tools.Insert", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Ensure_Group (Group, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Position : constant Member_Index := Natural (Index);
         Count    : constant Member_Count := Group.Count;
      begin
         Group.Members :=
           [for J in Member_Index =>
              (if J < Position then Group.Members (J)
               elsif J = Position
               then (Key => Key, Disabled => False, Name => No_Name)
               else Group.Members (J - 1))];
         Group.Count := Count + 1;
         Advance (Group.Change_Count);
      end;
   end Group_Insert;

   procedure Remove_Member
     (Group    : in out Ks_Tool_Group_Data;
      Position : Member_Index)
   with
     Pre  => Position < Group.Count,
     Post => Group.Count = Group.Count'Old - 1
             and then (for all I in 0 .. Group.Count - 1 =>
                         Group.Members (I)
                           = (if I < Position then Group.Members'Old (I)
                              else Group.Members'Old (I + 1)))
             and then Group.Own_Key = Group.Own_Key'Old
             and then Group.Abort_On_Failure = Group.Abort_On_Failure'Old
             and then Group.Change_Count = Group.Change_Count'Old + 1
             and then Group.Last_Run = Group.Last_Run'Old
             and then Group.Active_Run = Group.Active_Run'Old
             and then (if Distinct_Members (Group)'Old
                       then Distinct_Members (Group));
   --  Removes member Position; the later ones move down by one.

   procedure Remove_Member
     (Group    : in out Ks_Tool_Group_Data;
      Position : Member_Index)
   is
      Count : constant Member_Count := Group.Count;
   begin
      Group.Members :=
        [for J in Member_Index =>
           (if J < Position or else J = Member_Index'Last
            then Group.Members (J)
            else Group.Members (J + 1))];
      Group.Count := Count - 1;
      Advance (Group.Change_Count);
   end Remove_Member;

   procedure Group_Remove_At
     (Group  : Ks_Tool_Group;
      Index  : Int32;
      Status : out Ks_Status) is
   begin
      if Index < 0 or else Index >= Int32 (Count_Of (Group)) then
         Bad_Member_Index (Status, Index, Count_Of (Group));
         return;
      end if;
      Remove_Member (Group.all, Natural (Index));
      Set_Success (Status);
   end Group_Remove_At;

   procedure Group_Remove
     (Group  : Ks_Tool_Group;
      Key    : Int64;
      Index  : out Int32;
      Status : out Ks_Status) is
   begin
      Index := (if Group = null then No_Index
                else Find_Member (Group.all, Key));
      if Index = No_Index then
         Bad (Status, "Tools.Remove: the tool is not a member of the group");
         return;
      end if;
      Remove_Member (Group.all, Natural (Index));
      Set_Success (Status);
   end Group_Remove;

   procedure Group_Move
     (Group      : Ks_Tool_Group;
      From_Index : Int32;
      To_Index   : Int32;
      Status     : out Ks_Status) is
   begin
      if From_Index < 0 or else From_Index >= Int32 (Count_Of (Group)) then
         Bad_Member_Index (Status, From_Index, Count_Of (Group));
         return;
      elsif To_Index < 0 or else To_Index >= Int32 (Count_Of (Group)) then
         Bad_Member_Index (Status, To_Index, Count_Of (Group));
         return;
      end if;
      declare
         From  : constant Member_Index := Natural (From_Index);
         To    : constant Member_Index := Natural (To_Index);
         Moved : constant Member := Group.Members (From);
      begin
         Group.Members :=
           [for J in Member_Index =>
              (if J = To then Moved
               elsif From < To and then J >= From and then J < To
               then Group.Members (J + 1)
               elsif To < From and then J > To and then J <= From
               then Group.Members (J - 1)
               else Group.Members (J))];
         Advance (Group.Change_Count);
      end;
      Set_Success (Status);
   end Group_Move;

   procedure Group_Clear
     (Group  : Ks_Tool_Group;
      Status : out Ks_Status) is
   begin
      if Group /= null then
         Group.Count := 0;
         Advance (Group.Change_Count);
      end if;
      Set_Success (Status);
   end Group_Clear;

   procedure Group_Disabled
     (Group    : access constant Ks_Tool_Group_Data;
      Index    : Int32;
      Disabled : out Int32;
      Status   : out Ks_Status) is
   begin
      Disabled := False_Value;
      if Index < 0 or else Index >= Int32 (Count_Of (Group)) then
         Bad_Member_Index (Status, Index, Count_Of (Group));
         return;
      end if;
      if Group.Members (Natural (Index)).Disabled then
         Disabled := True_Value;
      end if;
      Set_Success (Status);
   end Group_Disabled;

   procedure Group_Set_Disabled
     (Group    : Ks_Tool_Group;
      Index    : Int32;
      Disabled : Int32;
      Status   : out Ks_Status) is
   begin
      if Disabled not in False_Value | True_Value then
         Bad (Status, "DisabledTools: the flag must be 0 or 1");
         return;
      elsif Index < 0 or else Index >= Int32 (Count_Of (Group)) then
         Bad_Member_Index (Status, Index, Count_Of (Group));
         return;
      end if;
      Group.Members (Natural (Index)).Disabled := Disabled = True_Value;
      Advance (Group.Change_Count);
      Set_Success (Status);
   end Group_Set_Disabled;

   function Find_Named
     (Group : Ks_Tool_Group_Data;
      Name  : Terminal_Name) return Int32
   with
     Post => Find_Named'Result in No_Index .. Int32 (Group.Count) - 1
             and then
               (if Find_Named'Result = No_Index
                then (for all J in 0 .. Group.Count - 1 =>
                        not Same_Name (Group.Members (J).Name, Name))
                else Same_Name
                       (Group.Members (Natural (Find_Named'Result)).Name,
                        Name)
                     and then (for all J in 0
                                 .. Natural (Find_Named'Result) - 1 =>
                                 not Same_Name (Group.Members (J).Name,
                                                Name)));
   --  The index of the first member named Name, No_Index for none.

   function Find_Named
     (Group : Ks_Tool_Group_Data;
      Name  : Terminal_Name) return Int32 is
   begin
      for I in 0 .. Group.Count - 1 loop
         if Same_Name (Group.Members (I).Name, Name) then
            return Int32 (I);
         end if;
         pragma Loop_Invariant
           (for all J in 0 .. I =>
              not Same_Name (Group.Members (J).Name, Name));
      end loop;
      return No_Index;
   end Find_Named;

   procedure Group_Set_Name
     (Group  : Ks_Tool_Group;
      Index  : Int32;
      Name   : Ks_Tool_Text;
      Status : out Ks_Status) is
   begin
      if not Stored_Name_Fits (Name) then
         Bad (Status, "a tool name must be at most 256 characters");
         return;
      elsif Index < 0 or else Index >= Int32 (Count_Of (Group)) then
         Bad_Member_Index (Status, Index, Count_Of (Group));
         return;
      end if;
      Group.Members (Natural (Index)).Name := To_Name (Name);
      Set_Success (Status);
   end Group_Set_Name;

   procedure Group_Name
     (Group  : access constant Ks_Tool_Group_Data;
      Index  : Int32;
      Name   : out Ks_Tool_Text;
      Status : out Ks_Status) is
   begin
      Name := (others => <>);
      if Index < 0 or else Index >= Int32 (Count_Of (Group)) then
         Bad_Member_Index (Status, Index, Count_Of (Group));
         return;
      end if;
      declare
         Stored : constant Terminal_Name :=
           Group.Members (Natural (Index)).Name;
      begin
         Name :=
           (Length => Int32 (Stored.Length),
            Text   => [for K in 1 .. Max_Text_Length =>
                         (if K <= Stored.Length then Stored.Text (K)
                          else ASCII.NUL)]);
      end;
      Set_Success (Status);
   end Group_Name;

   procedure Group_Index_Of_Name
     (Group  : access constant Ks_Tool_Group_Data;
      Name   : Ks_Tool_Text;
      Index  : out Int32;
      Status : out Ks_Status) is
   begin
      if Group = null or else not Stored_Name_Fits (Name)
        or else Name.Length = 0
      then
         Index := No_Index;
      else
         Index := Find_Named (Group.all, To_Name (Name));
      end if;
      Set_Success (Status);
   end Group_Index_Of_Name;

   procedure Group_Item_By_Name
     (Group  : access constant Ks_Tool_Group_Data;
      Name   : Ks_Tool_Text;
      Key    : out Int64;
      Status : out Ks_Status)
   is
      Index : Int32;
   begin
      Key := 0;
      Group_Index_Of_Name (Group, Name, Index, Status);
      if Index = No_Index then
         if Name.Length in 1 .. 100 then
            Bad (Status, "Tools: no tool named """ & To_String (Name)
                         & """");
         else
            Bad (Status, "Tools: no tool has that name");
         end if;
         return;
      end if;
      Key := Group.Members (Natural (Index)).Key;
      pragma Assert
        (Group.Members (Natural (Index)).Key = Key
         and then Same_Name (Group.Members (Natural (Index)).Name,
                             To_Name (Name)));
   end Group_Item_By_Name;

   procedure Group_Abort_Run_On_Tool_Failure
     (Group  : access constant Ks_Tool_Group_Data;
      Value  : out Int32;
      Status : out Ks_Status) is
   begin
      Value := (if Group /= null and then Group.Abort_On_Failure
                then True_Value else False_Value);
      Set_Success (Status);
   end Group_Abort_Run_On_Tool_Failure;

   procedure Group_Set_Abort_Run_On_Tool_Failure
     (Group  : in out Ks_Tool_Group;
      Value  : Int32;
      Status : out Ks_Status) is
   begin
      if Value not in False_Value | True_Value then
         Bad (Status, "AbortRunOnToolFailure must be 0 or 1");
         return;
      end if;
      Ensure_Group (Group, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Group.Abort_On_Failure := Value = True_Value;
      Advance (Group.Change_Count);
   end Group_Set_Abort_Run_On_Tool_Failure;

   ---------------------------------------------------------------------
   --  Runs
   ---------------------------------------------------------------------

   procedure Run_Begin
     (Group          : in out Ks_Tool_Group;
      Script_Result  : Int32;
      Script_Message : Ks_Tool_Text;
      Run_Tools      : Int32;
      Cursor         : out Ks_Tool_Group_Cursor;
      Status         : out Ks_Status) is
   begin
      Cursor := (Own_Key => 0, Change_Count => 0, Run => 0, Next => 0,
                 Pending => No_Index, Worst => Result_Accept,
                 First_Failure => No_Index, Stopped => False_Value,
                 Fault => Fault_Misuse,
                 Message => (Length => 0, Text => [others => ASCII.NUL]));
      if Script_Result not in Result_Code then
         Bad (Status, "Run: the script's result must be a "
                      & "CogToolResultConstants code (-1 .. 2)");
         return;
      elsif Run_Tools not in False_Value | True_Value then
         Bad (Status, "Run: the script's run_tools flag must be 0 or 1");
         return;
      elsif Script_Message.Length < 0 then
         Bad (Status, "Run: the script's message has a negative length");
         return;
      elsif Group /= null and then Group.Active_Run /= 0 then
         Bad (Status, "Run: the group is running already (a group cannot "
                      & "contain itself, directly or through other "
                      & "groups)");
         return;
      end if;
      Ensure_Group (Group, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Serial : Interfaces.Unsigned_64 := Group.Last_Run + 1;
      begin
         if Serial = 0 then
            Serial := 1;
         end if;
         Group.Last_Run := Serial;
         Group.Active_Run := Serial;
         Cursor :=
           (Own_Key       => Group.Own_Key,
            Change_Count  => Group.Change_Count,
            Run           => Serial,
            Next          => 0,
            Pending       => No_Index,
            Worst         => Script_Result,
            First_Failure => No_Index,
            Stopped       => (if Run_Tools = True_Value then False_Value
                              else True_Value),
            Fault         => Fault_None,
            Message       => Copy_Text (Script_Message));
      end;
   end Run_Begin;

   procedure Check_Cursor
     (Group  : access constant Ks_Tool_Group_Data;
      Cursor : in out Ks_Tool_Group_Cursor;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Group /= null
                            and then Cursor = Cursor'Old
                            and then Cursor_Matches (Group.all, Cursor)
                            and then Cursor_Consistent (Group.all, Cursor)
                            and then Cursor.Change_Count = Group.Change_Count
                            and then Cursor.Fault = Fault_None
                       else Cursor.Fault /= Fault_None);
   --  Cursor may go on with the run in progress of Group; otherwise the
   --  failure, and the cursor marked.

   procedure Check_Cursor
     (Group  : access constant Ks_Tool_Group_Data;
      Cursor : in out Ks_Tool_Group_Cursor;
      Status : out Ks_Status) is
   begin
      if Group = null then
         Cursor.Fault := Fault_Misuse;
         Bad (Status, "Run: the group is null");
      elsif not Cursor_Matches (Group.all, Cursor) then
         Cursor.Fault := Fault_Misuse;
         Bad (Status, "Run: the cursor does not belong to a run in progress "
                      & "of this group");
      elsif Cursor.Change_Count /= Group.Change_Count then
         Cursor.Fault := Fault_Changed;
         Bad (Status, "Run: the group changed while it ran");
      elsif Cursor.Fault /= Fault_None then
         Bad (Status, "Run: an earlier call of this run failed");
      elsif not Cursor_Consistent (Group.all, Cursor) then
         Cursor.Fault := Fault_Misuse;
         Bad (Status, "Run: the cursor is not consistent");
      else
         Set_Success (Status);
      end if;
   end Check_Cursor;

   procedure Run_Next
     (Group  : access constant Ks_Tool_Group_Data;
      Cursor : in out Ks_Tool_Group_Cursor;
      Index  : out Int32;
      More   : out Int32;
      Status : out Ks_Status) is
   begin
      Index := No_Index;
      More := False_Value;
      Check_Cursor (Group, Cursor, Status);
      if not Succeeded (Status) then
         return;
      elsif Cursor.Pending /= No_Index then
         Cursor.Fault := Fault_Misuse;
         Bad (Status, "Run: member " & Image_Of (Int64 (Cursor.Pending))
                      & " was offered and has not reported its result");
         return;
      elsif Cursor.Stopped = True_Value then
         return;
      end if;
      declare
         Count : constant Int32 := Int32 (Group.Count);
         First : constant Int32 := Cursor.Next;
         J     : Int32 := First;
      begin
         while J < Count and then Group.Members (Natural (J)).Disabled loop
            pragma Loop_Invariant (J in First .. Count - 1);
            pragma Loop_Invariant
              (for all K in First .. J =>
                 Group.Members (Natural (K)).Disabled);
            J := J + 1;
         end loop;
         if J < Count then
            Index := J;
            More := True_Value;
            Cursor.Next := J + 1;
            Cursor.Pending := J;
         else
            Cursor.Next := Count;
         end if;
      end;
   end Run_Next;

   procedure Append_Failure
     (Message        : in out Ks_Tool_Text;
      Index          : Int32;
      Result         : Result_Code;
      Name           : Ks_Tool_Text;
      Member_Message : Ks_Tool_Text)
   with
     Pre  => Fits (Message)
             and then Index >= 0
             and then Name.Length >= 0
             and then Member_Message.Length >= 0,
     Post => Fits (Message);
   --  Appends "<name>: <message>" of the first member that did not
   --  accept (see the spec).

   procedure Append_Failure
     (Message        : in out Ks_Tool_Text;
      Index          : Int32;
      Result         : Result_Code;
      Name           : Ks_Tool_Text;
      Member_Message : Ks_Tool_Text) is
   begin
      if Message.Length > 0 then
         Append (Message, "; ");
      end if;
      if Name.Length > 0 then
         Append_Text (Message, Name);
      else
         Append (Message, "tool " & Image_Of (Int64 (Index)));
      end if;
      Append (Message, ": ");
      if Member_Message.Length > 0 then
         Append_Text (Message, Member_Message);
      else
         Append (Message, Result_Word (Result));
      end if;
   end Append_Failure;

   procedure Run_Report
     (Group   : access constant Ks_Tool_Group_Data;
      Cursor  : in out Ks_Tool_Group_Cursor;
      Index   : Int32;
      Result  : Int32;
      Name    : Ks_Tool_Text;
      Message : Ks_Tool_Text;
      Status  : out Ks_Status) is
   begin
      Check_Cursor (Group, Cursor, Status);
      if not Succeeded (Status) then
         return;
      elsif Cursor.Pending = No_Index or else Index /= Cursor.Pending then
         Cursor.Fault := Fault_Misuse;
         Bad (Status, "Run: the result reported is not that of the member "
                      & "offered last");
         return;
      elsif Result not in Result_Code then
         Cursor.Fault := Fault_Misuse;
         Bad (Status, "Run: the result must be a CogToolResultConstants "
                      & "code (-1 .. 2)");
         return;
      elsif Name.Length < 0 or else Message.Length < 0 then
         Cursor.Fault := Fault_Misuse;
         Bad (Status, "Run: the member's name or message has a negative "
                      & "length");
         return;
      end if;
      if Cursor.First_Failure = No_Index and then Result /= Result_Accept
      then
         Cursor.First_Failure := Index;
         Append_Failure (Cursor.Message, Index, Result, Name, Message);
      end if;
      Cursor.Worst := Worse (Cursor.Worst, Result);
      if Group.Abort_On_Failure and then Result = Result_Error then
         Cursor.Stopped := True_Value;
      end if;
      Cursor.Pending := No_Index;
   end Run_Report;

   procedure Run_End
     (Group         : Ks_Tool_Group;
      Cursor        : in out Ks_Tool_Group_Cursor;
      Result        : out Int32;
      First_Failure : out Int32;
      Message       : out Ks_Tool_Text;
      Status        : out Ks_Status) is
   begin
      Result := Result_Error;
      First_Failure := No_Index;
      Message := (Length => 0, Text => [others => ASCII.NUL]);
      if Group = null then
         Bad (Status, "Run: the group is null");
         return;
      elsif not Cursor_Matches (Group.all, Cursor) then
         Bad (Status, "Run: the cursor does not belong to a run in progress "
                      & "of this group");
         return;
      end if;
      Group.Active_Run := 0;
      Cursor.Run := 0;
      if Cursor.Change_Count /= Group.Change_Count
        or else Cursor.Fault = Fault_Changed
      then
         Bad (Status, "Run: the group changed while it ran");
      elsif Cursor.Fault /= Fault_None then
         Bad (Status, "Run: a call of this run failed");
      elsif not Cursor_Consistent (Group.all, Cursor) then
         Bad (Status, "Run: the cursor is not consistent");
      elsif Cursor.Pending /= No_Index then
         Bad (Status, "Run: member " & Image_Of (Int64 (Cursor.Pending))
                      & " was offered and has not reported its result");
      else
         Result := Cursor.Worst;
         First_Failure := Cursor.First_Failure;
         Message := Cursor.Message;
         Set_Success (Status);
      end if;
   end Run_End;

   ---------------------------------------------------------------------
   --  Terminals
   ---------------------------------------------------------------------

   function Same_Name (Left, Right : Terminal_Name) return Boolean is
   begin
      if Left.Length /= Right.Length then
         return False;
      end if;
      for K in 1 .. Left.Length loop
         if Left.Text (K) /= Right.Text (K) then
            return False;
         end if;
         pragma Loop_Invariant
           (for all M in 1 .. K => Left.Text (M) = Right.Text (M));
      end loop;
      return True;
   end Same_Name;

   procedure Lemma_Same_Name (A, B, C : Terminal_Name)
   with
     Ghost,
     Global => null,
     Post   => Same_Name (A, B) = Same_Name (B, A)
               and then (if Same_Name (A, B) and then Same_Name (B, C)
                         then Same_Name (A, C));
   --  Same_Name is symmetric and transitive.

   procedure Lemma_Same_Name (A, B, C : Terminal_Name) is null;

   procedure Lemma_Only_Match
     (Terminals : Ks_Tool_Block_Terminals_Data;
      Index     : Terminal_Index;
      Name      : Terminal_Name)
   with
     Ghost,
     Global => null,
     Post   => (if Distinct_Names (Terminals)
                  and then Index < Terminals.Count
                  and then Same_Name (Terminals.Items (Index).Name, Name)
                then (for all J in 0 .. Terminals.Count - 1 =>
                        (if Same_Name (Terminals.Items (J).Name, Name)
                         then J = Index)));
   --  With distinct names, the terminal Index is the only one named Name.

   procedure Lemma_Only_Match
     (Terminals : Ks_Tool_Block_Terminals_Data;
      Index     : Terminal_Index;
      Name      : Terminal_Name) is
   begin
      for J in 0 .. Terminals.Count - 1 loop
         Lemma_Same_Name (Terminals.Items (J).Name, Name,
                          Terminals.Items (Index).Name);
         Lemma_Same_Name (Terminals.Items (Index).Name, Name, Name);
         pragma Loop_Invariant
           (if Distinct_Names (Terminals)
              and then Index < Terminals.Count
              and then Same_Name (Terminals.Items (Index).Name, Name)
            then (for all K in 0 .. J =>
                    (if Same_Name (Terminals.Items (K).Name, Name)
                     then K = Index)));
      end loop;
   end Lemma_Only_Match;

   function Find
     (Terminals : Ks_Tool_Block_Terminals_Data;
      Name      : Terminal_Name) return Int32 is
   begin
      for J in 0 .. Terminals.Count - 1 loop
         Lemma_Same_Name (Terminals.Items (J).Name, Name, Name);
         if Same_Name (Terminals.Items (J).Name, Name) then
            return Int32 (J);
         end if;
         pragma Loop_Invariant
           (for all K in 0 .. J =>
              not Same_Name (Terminals.Items (K).Name, Name)
              and then not Same_Name (Name, Terminals.Items (K).Name));
      end loop;
      return No_Index;
   end Find;

   function Shown (Name : Ks_Tool_Text) return String
   with Post => Shown'Result'First = 1 and then Shown'Result'Length <= 64;
   --  The first characters of a name, for messages.

   function Shown (Name : Ks_Tool_Text) return String is
      Last : constant Natural :=
        (if Name.Length < 0 then 0
         elsif Name.Length > 64 then 64
         else Natural (Name.Length));
   begin
      return String (Name.Text (1 .. Last));
   end Shown;

   function Type_Name (Value_Type : Value_Type_Code) return String
   with Post => Type_Name'Result'First = 1
                and then Type_Name'Result'Length <= 19;
   --  The name of a value type, for messages.

   function Type_Name (Value_Type : Value_Type_Code) return String is
     (case Value_Type is
         when Type_Real          => "Real",
         when Type_Integer       => "Integer",
         when Type_Boolean       => "Boolean",
         when Type_String        => "String",
         when Type_Image_8_Grey  => "Image_8_Grey",
         when Type_Image_16_Grey => "Image_16_Grey",
         when Type_Transform     => "Transform_2D_Linear",
         when others             => "Shape");

   procedure Check_Name (Name : Ks_Tool_Text; Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Succeeded (Status) = Name_Fits (Name);
   --  Name can name a terminal.

   procedure Check_Name (Name : Ks_Tool_Text; Status : out Ks_Status) is
   begin
      if Name_Fits (Name) then
         Set_Success (Status);
      else
         Bad (Status, "Name must have 1 to 256 characters");
      end if;
   end Check_Name;

   procedure Lookup
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Index     : out Int32;
      Status    : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Name_Fits (Name)
                            and then Index in 0 .. Int32 (Terminals.Count) - 1
                            and then Index
                                       = Find (Terminals.all, To_Name (Name))
                            and then Same_Name
                                       (Terminals.Items (Natural (Index)).Name,
                                        To_Name (Name))
                       else Index = No_Index);
   --  The index of the terminal Name; Bad_Parameter when there is none.

   procedure Lookup
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Index     : out Int32;
      Status    : out Ks_Status) is
   begin
      Index := No_Index;
      Check_Name (Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Terminals /= null then
         Index := Find (Terminals.all, To_Name (Name));
      end if;
      if Index = No_Index then
         Bad (Status, "No terminal is named """ & Shown (Name) & """");
      end if;
   end Lookup;

   procedure Lookup_Typed
     (Terminals  : access constant Ks_Tool_Block_Terminals_Data;
      Name       : Ks_Tool_Text;
      Value_Type : Value_Type_Code;
      Index      : out Int32;
      Status     : out Ks_Status)
   with
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
                       else Index = No_Index);
   --  The index of the terminal Name of Value_Type; Bad_Parameter when
   --  there is none or it has another type.

   procedure Lookup_Typed
     (Terminals  : access constant Ks_Tool_Block_Terminals_Data;
      Name       : Ks_Tool_Text;
      Value_Type : Value_Type_Code;
      Index      : out Int32;
      Status     : out Ks_Status) is
   begin
      Lookup (Terminals, Name, Index, Status);
      if Succeeded (Status)
        and then Terminals.Items (Natural (Index)).Value_Type /= Value_Type
      then
         Bad (Status, "Terminal """ & Shown (Name) & """ is of type "
                      & Type_Name (Terminals.Items (Natural (Index))
                                     .Value_Type)
                      & ", not " & Type_Name (Value_Type));
         Index := No_Index;
      end if;
   end Lookup_Typed;

   function New_Terminal
     (Name       : Terminal_Name;
      Value_Type : Value_Type_Code) return Terminal
   is (Name          => Name,
       Value_Type    => Value_Type,
       Has_Value     => Value_Type not in Object_Type_Code,
       Real_Value    => 0.0,
       Integer_Value => 0,
       Boolean_Value => False,
       String_Value  => (Length => 0, Text => [others => ASCII.NUL]));
   --  A terminal with the default value of its type.

   function Is_Null
     (Terminals : access constant Ks_Tool_Block_Terminals_Data)
      return Boolean
   is (Terminals = null)
   with Ghost;

   procedure Ensure_Terminals
     (Terminals : in out Ks_Tool_Block_Terminals;
      Status    : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Terminals.Count
                                       = Terminal_Count_Of (Terminals)'Old
                            and then (for all J in 0 .. Terminals.Count - 1 =>
                                        Terminals.Items (J)
                                          = Terminals_Of (Terminals)'Old
                                              .Items (J))
                       else Terminals = null and then Is_Null (Terminals)'Old);
   --  Creates the collection when it is null.

   procedure Ensure_Terminals
     (Terminals : in out Ks_Tool_Block_Terminals;
      Status    : out Ks_Status) is
   begin
      if Terminals = null then
         Allocate_Terminals (Terminals);
         if Terminals = null then
            No_Memory (Status);
            return;
         end if;
      end if;
      Set_Success (Status);
   end Ensure_Terminals;

   procedure Check_New_Terminal
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Status    : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Name_Fits (Name)
                            and then Terminal_Count_Of (Terminals)
                                       < Max_Terminals
                            and then (if Terminals /= null
                                      then (for all J in
                                              0 .. Terminals.Count - 1 =>
                                              not Same_Name
                                                    (Terminals.Items (J).Name,
                                                     To_Name (Name))
                                              and then not Same_Name
                                                (To_Name (Name),
                                                 Terminals.Items (J).Name))));
   --  A terminal Name may be added: the name fits, is not taken, and the
   --  collection has room.

   procedure Check_New_Terminal
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Status    : out Ks_Status) is
   begin
      Check_Name (Name, Status);
      if not Succeeded (Status) then
         return;
      elsif Terminals /= null
        and then Find (Terminals.all, To_Name (Name)) /= No_Index
      then
         Bad (Status, "A terminal named """ & Shown (Name)
                      & """ exists already");
      elsif Terminal_Count_Of (Terminals) = Max_Terminals then
         Bad (Status, "A terminal collection holds at most 128 terminals");
      end if;
   end Check_New_Terminal;

   procedure Append_Terminal
     (Terminals : in out Ks_Tool_Block_Terminals_Data;
      Item      : Terminal)
   with
     Pre  => Terminals.Count < Max_Terminals,
     Post => Terminals.Count = Terminals.Count'Old + 1
             and then Terminals.Items (Terminals.Count - 1) = Item
             and then (for all J in 0 .. Terminals.Count - 2 =>
                         Terminals.Items (J) = Terminals.Items'Old (J))
             and then (if Distinct_Names (Terminals)'Old
                         and then (for all J in 0 .. Terminals.Count'Old - 1
                                   => not Same_Name
                                            (Terminals.Items'Old (J).Name,
                                             Item.Name)
                                      and then not Same_Name
                                        (Item.Name,
                                         Terminals.Items'Old (J).Name))
                       then Distinct_Names (Terminals));
   --  Appends Item; the names stay distinct when Item's name is new.

   procedure Append_Terminal
     (Terminals : in out Ks_Tool_Block_Terminals_Data;
      Item      : Terminal)
   is
      Last : constant Terminal_Index := Terminals.Count;
   begin
      Terminals.Items (Last) := Item;
      Terminals.Count := Last + 1;
   end Append_Terminal;

   procedure Add_Terminal
     (Terminals : in out Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Item      : Terminal;
      Status    : out Ks_Status)
   with
     Pre  => Name_Fits (Name) and then Item.Name = To_Name (Name),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Valid_Terminals (Terminals)'Old
                       then Valid_Terminals (Terminals))
             and then (if Succeeded (Status)
                       then Terminals /= null
                            and then Terminals.Count
                                       = Terminal_Count_Of (Terminals)'Old + 1
                            and then Terminals.Items (Terminals.Count - 1)
                                       = Item
                            and then (for all J in 0 .. Terminals.Count - 2 =>
                                        Terminals.Items (J)
                                          = Terminals_Of (Terminals)'Old
                                              .Items (J)
                                        and then not Same_Name
                                          (Terminals.Items (J).Name,
                                           Item.Name))
                       else Terminals_Of (Terminals)
                              = Terminals_Of (Terminals)'Old);
   --  Appends the terminal Item named Name after the checks of a new
   --  terminal; creates the collection when it is null.

   procedure Add_Terminal
     (Terminals : in out Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Item      : Terminal;
      Status    : out Ks_Status) is
   begin
      Check_New_Terminal (Terminals, Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Ensure_Terminals (Terminals, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Append_Terminal (Terminals.all, Item);
   end Add_Terminal;

   procedure Lemma_Holds_Last
     (Terminals : Ks_Tool_Block_Terminals_Data;
      Name      : Terminal_Name)
   with
     Ghost,
     Global => null,
     Pre    => Terminals.Count >= 1,
     Post   => (if Same_Name (Terminals.Items (Terminals.Count - 1).Name, Name)
                  and then (for all J in 0 .. Terminals.Count - 2 =>
                              not Same_Name (Terminals.Items (J).Name, Name))
                then (for all J in 0 .. Terminals.Count - 1 =>
                        (if Same_Name (Terminals.Items (J).Name, Name)
                         then J = Terminals.Count - 1)));
   --  The last terminal is the only one named Name when no other is.

   procedure Lemma_Holds_Last
     (Terminals : Ks_Tool_Block_Terminals_Data;
      Name      : Terminal_Name) is null;

   procedure Terminals_Create
     (Terminals : out Ks_Tool_Block_Terminals;
      Status    : out Ks_Status) is
   begin
      Allocate_Terminals (Terminals);
      if Terminals = null then
         No_Memory (Status);
      else
         Set_Success (Status);
      end if;
   end Terminals_Create;

   procedure Terminals_Destroy (Terminals : in out Ks_Tool_Block_Terminals)
   is
   begin
      Free (Terminals);
   end Terminals_Destroy;

   procedure Terminals_Duplicate
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Copy      : out Ks_Tool_Block_Terminals;
      Status    : out Ks_Status) is
   begin
      Copy := null;
      if Terminals = null then
         Set_Success (Status);
         return;
      end if;
      Allocate_Terminals (Copy);
      if Copy = null then
         No_Memory (Status);
         return;
      end if;
      Copy.all := Terminals.all;
      Set_Success (Status);
   end Terminals_Duplicate;

   procedure Terminals_Count
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Count     : out Int32;
      Status    : out Ks_Status) is
   begin
      Count := Int32 (Terminal_Count_Of (Terminals));
      Set_Success (Status);
   end Terminals_Count;

   procedure Terminals_Clear
     (Terminals : Ks_Tool_Block_Terminals;
      Status    : out Ks_Status) is
   begin
      if Terminals /= null then
         Terminals.Count := 0;
      end if;
      Set_Success (Status);
   end Terminals_Clear;

   procedure Terminals_Add
     (Terminals  : in out Ks_Tool_Block_Terminals;
      Name       : Ks_Tool_Text;
      Value_Type : Int32;
      Status     : out Ks_Status) is
   begin
      if Value_Type not in Value_Type_Code then
         Bad (Status, "ValueType must be a terminal type code (0 .. 7)");
         return;
      end if;
      Check_Name (Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Add_Terminal (Terminals, Name, New_Terminal (To_Name (Name),
                                                   Value_Type), Status);
   end Terminals_Add;

   procedure Terminals_Add_Real
     (Terminals : in out Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Long_Float;
      Status    : out Ks_Status) is
   begin
      if not (Value >= -Long_Float'Last and then Value <= Long_Float'Last)
      then
         Bad (Status, "Value must be finite");
         return;
      end if;
      Check_Name (Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Item : Terminal := New_Terminal (To_Name (Name), Type_Real);
      begin
         Item.Real_Value := Value;
         Add_Terminal (Terminals, Name, Item, Status);
         if Succeeded (Status) then
            Lemma_Holds_Last (Terminals.all, To_Name (Name));
         end if;
      end;
   end Terminals_Add_Real;

   procedure Terminals_Add_Integer
     (Terminals : in out Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Int64;
      Status    : out Ks_Status) is
   begin
      Check_Name (Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Item : Terminal := New_Terminal (To_Name (Name), Type_Integer);
      begin
         Item.Integer_Value := Value;
         Add_Terminal (Terminals, Name, Item, Status);
         if Succeeded (Status) then
            Lemma_Holds_Last (Terminals.all, To_Name (Name));
         end if;
      end;
   end Terminals_Add_Integer;

   procedure Terminals_Add_Boolean
     (Terminals : in out Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Int32;
      Status    : out Ks_Status) is
   begin
      if Value not in False_Value | True_Value then
         Bad (Status, "Value must be 0 or 1");
         return;
      end if;
      Check_Name (Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Item : Terminal := New_Terminal (To_Name (Name), Type_Boolean);
      begin
         Item.Boolean_Value := Value = True_Value;
         Add_Terminal (Terminals, Name, Item, Status);
         if Succeeded (Status) then
            Lemma_Holds_Last (Terminals.all, To_Name (Name));
         end if;
      end;
   end Terminals_Add_Boolean;

   function Stored (Value : Ks_Tool_Text) return Stored_Text
   with
     Pre  => Fits (Value),
     Post => Same_Text (Stored'Result, Value);
   --  The stored form of a string value.

   function Stored (Value : Ks_Tool_Text) return Stored_Text is
     (Length => Natural (Value.Length),
      Text   => [for K in 1 .. Max_Text_Length =>
                   (if K <= Natural (Value.Length) then Value.Text (K)
                    else ASCII.NUL)]);

   procedure Check_String (Value : Ks_Tool_Text; Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Succeeded (Status) = Fits (Value);
   --  Value can be stored as a string value.

   procedure Check_String (Value : Ks_Tool_Text; Status : out Ks_Status) is
   begin
      if Fits (Value) then
         Set_Success (Status);
      else
         Bad (Status, "Value must have 0 to 1024 characters");
      end if;
   end Check_String;

   procedure Terminals_Add_String
     (Terminals : in out Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Ks_Tool_Text;
      Status    : out Ks_Status) is
   begin
      Check_String (Value, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Name (Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Item : Terminal := New_Terminal (To_Name (Name), Type_String);
      begin
         Item.String_Value := Stored (Value);
         Add_Terminal (Terminals, Name, Item, Status);
         if Succeeded (Status) then
            Lemma_Holds_Last (Terminals.all, To_Name (Name));
         end if;
      end;
   end Terminals_Add_String;

   procedure Terminals_Add_Object
     (Terminals  : in out Ks_Tool_Block_Terminals;
      Name       : Ks_Tool_Text;
      Value_Type : Int32;
      Status     : out Ks_Status) is
   begin
      if Value_Type not in Object_Type_Code then
         Bad (Status, "ValueType must be an object type code (4 .. 7)");
         return;
      end if;
      Check_Name (Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         Item : Terminal := New_Terminal (To_Name (Name), Value_Type);
      begin
         Item.Has_Value := True;
         Add_Terminal (Terminals, Name, Item, Status);
      end;
   end Terminals_Add_Object;

   procedure Open_Slot
     (Terminals : in out Ks_Tool_Block_Terminals_Data;
      Position  : Terminal_Index)
   with
     Pre  => Terminals.Count < Max_Terminals
             and then Position <= Terminals.Count,
     Post => Terminals.Count = Terminals.Count'Old + 1
             and then (for all J in 0 .. Terminals.Count - 1 =>
                         (if J < Position
                          then Terminals.Items (J) = Terminals.Items'Old (J)
                          elsif J > Position
                          then Terminals.Items (J)
                                 = Terminals.Items'Old (J - 1)));
   --  Moves the terminals from Position on up by one; the caller fills
   --  Position.

   procedure Open_Slot
     (Terminals : in out Ks_Tool_Block_Terminals_Data;
      Position  : Terminal_Index)
   is
      Last : constant Terminal_Index := Terminals.Count;
   begin
      for J in reverse Position + 1 .. Last loop
         Terminals.Items (J) := Terminals.Items (J - 1);
         pragma Loop_Invariant
           (Terminals.Count = Last
            and then (for all K in 0 .. J - 1 =>
                        Terminals.Items (K)
                          = Terminals.Items'Loop_Entry (K))
            and then (for all K in J .. Last =>
                        Terminals.Items (K)
                          = Terminals.Items'Loop_Entry (K - 1)));
      end loop;
      Terminals.Count := Last + 1;
   end Open_Slot;

   function Old_Position (J, Position : Terminal_Index) return Terminal_Index
   is (if J < Position then J else J - 1)
   with Ghost, Pre => J /= Position;
   --  Where the terminal now at J was before a terminal was inserted at
   --  Position.

   procedure Lemma_Distinct_Insert
     (Old, After : Ks_Tool_Block_Terminals_Data;
      Position : Terminal_Index)
   with
     Ghost,
     Global => null,
     Pre    => After.Count = Old.Count + 1 and then Position < After.Count,
     Post   => (if Distinct_Names (Old)
                  and then (for all J in 0 .. After.Count - 1 =>
                              (if J /= Position
                               then After.Items (J).Name
                                      = Old.Items (Old_Position (J, Position))
                                          .Name))
                  and then (for all J in 0 .. Old.Count - 1 =>
                              not Same_Name (Old.Items (J).Name,
                                             After.Items (Position).Name)
                              and then not Same_Name
                                (After.Items (Position).Name,
                                 Old.Items (J).Name))
                then Distinct_Names (After));
   --  Inserting a terminal whose name is new keeps the names distinct.

   procedure Lemma_Distinct_Insert
     (Old, After : Ks_Tool_Block_Terminals_Data;
      Position : Terminal_Index) is
   begin
      if Distinct_Names (Old)
        and then (for all J in 0 .. After.Count - 1 =>
                    (if J /= Position
                     then After.Items (J).Name
                            = Old.Items (Old_Position (J, Position)).Name))
        and then (for all J in 0 .. Old.Count - 1 =>
                    not Same_Name (Old.Items (J).Name,
                                   After.Items (Position).Name)
                    and then not Same_Name (After.Items (Position).Name,
                                            Old.Items (J).Name))
      then
         for I in 0 .. After.Count - 1 loop
            for J in 0 .. After.Count - 1 loop
               if I /= J and then I /= Position and then J /= Position then
                  pragma Assert
                    (Old_Position (I, Position) /= Old_Position (J, Position));
                  pragma Assert
                    (not Same_Name
                           (Old.Items (Old_Position (I, Position)).Name,
                            Old.Items (Old_Position (J, Position)).Name));
               end if;
               pragma Loop_Invariant
                 (for all K in 0 .. J =>
                    (if I /= K
                     then not Same_Name (After.Items (I).Name,
                                         After.Items (K).Name)));
            end loop;
            pragma Loop_Invariant
              (for all L in 0 .. I =>
                 (for all K in 0 .. After.Count - 1 =>
                    (if L /= K
                     then not Same_Name (After.Items (L).Name,
                                         After.Items (K).Name))));
         end loop;
      end if;
   end Lemma_Distinct_Insert;

   procedure Insert_Terminal
     (Terminals : in out Ks_Tool_Block_Terminals_Data;
      Position  : Terminal_Index;
      Item      : Terminal)
   with
     Pre  => Terminals.Count < Max_Terminals
             and then Position <= Terminals.Count,
     Post => Terminals.Count = Terminals.Count'Old + 1
             and then Terminals.Items (Position) = Item
             and then (for all J in 0 .. Terminals.Count - 1 =>
                         (if J < Position
                          then Terminals.Items (J) = Terminals.Items'Old (J)
                          elsif J > Position
                          then Terminals.Items (J)
                                 = Terminals.Items'Old (J - 1)))
             and then (if Distinct_Names (Terminals)'Old
                         and then (for all J in 0 .. Terminals.Count'Old - 1
                                   => not Same_Name
                                            (Terminals.Items'Old (J).Name,
                                             Item.Name)
                                      and then not Same_Name
                                        (Item.Name,
                                         Terminals.Items'Old (J).Name))
                       then Distinct_Names (Terminals));
   --  Inserts Item at Position; the later terminals move up by one, and
   --  the names stay distinct when Item's name is new.

   procedure Insert_Terminal
     (Terminals : in out Ks_Tool_Block_Terminals_Data;
      Position  : Terminal_Index;
      Item      : Terminal)
   is
      Old : constant Ks_Tool_Block_Terminals_Data := Terminals with Ghost;
   begin
      Open_Slot (Terminals, Position);
      Terminals.Items (Position) := Item;
      Lemma_Distinct_Insert (Old, Terminals, Position);
   end Insert_Terminal;

   function Kept_Position (J : Terminal_Index; Position : Terminal_Index)
      return Terminal_Index
   is (if J < Position then J else J + 1)
   with Ghost, Pre => J < Max_Terminals - 1;
   --  Where the terminal now at J was before the terminal at Position was
   --  removed.

   procedure Lemma_Distinct_Remove
     (Old, After : Ks_Tool_Block_Terminals_Data;
      Position : Terminal_Index)
   with
     Ghost,
     Global => null,
     Pre    => After.Count + 1 = Old.Count and then Position < Old.Count,
     Post   => (if Distinct_Names (Old)
                  and then (for all J in 0 .. After.Count - 1 =>
                              After.Items (J).Name
                                = Old.Items (Kept_Position (J, Position))
                                    .Name)
                then Distinct_Names (After));
   --  Removing a terminal keeps the names distinct.

   procedure Lemma_Distinct_Remove
     (Old, After : Ks_Tool_Block_Terminals_Data;
      Position : Terminal_Index) is
   begin
      if Distinct_Names (Old)
        and then (for all J in 0 .. After.Count - 1 =>
                    After.Items (J).Name
                      = Old.Items (Kept_Position (J, Position)).Name)
      then
         for I in 0 .. After.Count - 1 loop
            for J in 0 .. After.Count - 1 loop
               if I /= J then
                  pragma Assert
                    (Kept_Position (I, Position)
                       /= Kept_Position (J, Position));
                  pragma Assert
                    (not Same_Name
                           (Old.Items (Kept_Position (I, Position)).Name,
                            Old.Items (Kept_Position (J, Position)).Name));
               end if;
               pragma Loop_Invariant
                 (for all K in 0 .. J =>
                    (if I /= K
                     then not Same_Name (After.Items (I).Name,
                                         After.Items (K).Name)));
            end loop;
            pragma Loop_Invariant
              (for all L in 0 .. I =>
                 (for all K in 0 .. After.Count - 1 =>
                    (if L /= K
                     then not Same_Name (After.Items (L).Name,
                                         After.Items (K).Name))));
         end loop;
      end if;
   end Lemma_Distinct_Remove;

   procedure Close_Slot
     (Terminals : in out Ks_Tool_Block_Terminals_Data;
      Position  : Terminal_Index)
   with
     Pre  => Position < Terminals.Count,
     Post => Terminals.Count = Terminals.Count'Old - 1
             and then (for all J in 0 .. Terminals.Count - 1 =>
                         Terminals.Items (J)
                           = (if J < Position then Terminals.Items'Old (J)
                              else Terminals.Items'Old (J + 1)))
             and then (if Distinct_Names (Terminals)'Old
                       then Distinct_Names (Terminals));
   --  Removes the terminal Position; the later ones move down by one.

   procedure Close_Slot
     (Terminals : in out Ks_Tool_Block_Terminals_Data;
      Position  : Terminal_Index)
   is
      Last : constant Terminal_Index := Terminals.Count - 1;
      Old  : constant Ks_Tool_Block_Terminals_Data := Terminals with Ghost;
   begin
      for J in Position .. Last - 1 loop
         Terminals.Items (J) := Terminals.Items (J + 1);
         pragma Loop_Invariant
           (Terminals.Count = Last + 1
            and then (for all K in 0 .. J =>
                        Terminals.Items (K)
                          = (if K < Position
                             then Terminals.Items'Loop_Entry (K)
                             else Terminals.Items'Loop_Entry (K + 1)))
            and then (for all K in J + 1 .. Last =>
                        Terminals.Items (K)
                          = Terminals.Items'Loop_Entry (K)));
      end loop;
      Terminals.Count := Last;
      pragma Assert
        (for all J in 0 .. Terminals.Count - 1 =>
           Terminals.Items (J).Name
             = Old.Items (Kept_Position (J, Position)).Name);
      Lemma_Distinct_Remove (Old, Terminals, Position);
   end Close_Slot;

   procedure Terminals_Insert
     (Terminals  : in out Ks_Tool_Block_Terminals;
      Index      : Int32;
      Name       : Ks_Tool_Text;
      Value_Type : Int32;
      Status     : out Ks_Status) is
   begin
      if Index < 0 or else Index > Int32 (Terminal_Count_Of (Terminals)) then
         if Index < 0 then
            Out_Of_Range (Status, "Insert: the index must be >= 0");
         else
            Out_Of_Range (Status, "Insert: the index must be at most Count ("
                                  & Image_Of (Int64 (Terminal_Count_Of
                                                       (Terminals)))
                                  & ")");
         end if;
         return;
      elsif Value_Type not in Value_Type_Code then
         Bad (Status, "ValueType must be a terminal type code (0 .. 7)");
         return;
      end if;
      Check_New_Terminal (Terminals, Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Ensure_Terminals (Terminals, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Insert_Terminal (Terminals.all, Natural (Index),
                       New_Terminal (To_Name (Name), Value_Type));
   end Terminals_Insert;

   procedure Bad_Terminal_Index
     (Status : out Ks_Status;
      Index  : Int32;
      Count  : Terminal_Count)
   with
     Post => Valid (Status)
             and then Status.Failure = Failure_Index_Out_Of_Range;
   --  The failure for an index outside 0 .. Count - 1.

   procedure Bad_Terminal_Index
     (Status : out Ks_Status;
      Index  : Int32;
      Count  : Terminal_Count) is
   begin
      if Index < 0 then
         Out_Of_Range (Status, "Terminals: the index must be >= 0");
      else
         Out_Of_Range (Status, "Terminals: the index must be below Count ("
                               & Image_Of (Int64 (Count)) & ")");
      end if;
   end Bad_Terminal_Index;

   procedure Terminals_Remove_At
     (Terminals : Ks_Tool_Block_Terminals;
      Index     : Int32;
      Status    : out Ks_Status) is
   begin
      if Index < 0 or else Index >= Int32 (Terminal_Count_Of (Terminals))
      then
         Bad_Terminal_Index (Status, Index, Terminal_Count_Of (Terminals));
         return;
      end if;
      Close_Slot (Terminals.all, Natural (Index));
      Set_Success (Status);
   end Terminals_Remove_At;

   procedure Terminals_Remove
     (Terminals : Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Index     : out Int32;
      Status    : out Ks_Status) is
   begin
      Lookup (Terminals, Name, Index, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Close_Slot (Terminals.all, Natural (Index));
   end Terminals_Remove;

   procedure Terminals_Move
     (Terminals  : Ks_Tool_Block_Terminals;
      From_Index : Int32;
      To_Index   : Int32;
      Status     : out Ks_Status) is
   begin
      if From_Index < 0
        or else From_Index >= Int32 (Terminal_Count_Of (Terminals))
      then
         Bad_Terminal_Index (Status, From_Index,
                             Terminal_Count_Of (Terminals));
         return;
      elsif To_Index < 0
        or else To_Index >= Int32 (Terminal_Count_Of (Terminals))
      then
         Bad_Terminal_Index (Status, To_Index, Terminal_Count_Of (Terminals));
         return;
      end if;
      declare
         From  : constant Terminal_Index := Natural (From_Index);
         To    : constant Terminal_Index := Natural (To_Index);
         Moved : constant Terminal := Terminals.Items (From);
         Old   : constant Ks_Tool_Block_Terminals_Data := Terminals.all
           with Ghost;
      begin
         Close_Slot (Terminals.all, From);
         pragma Assert
           (if Distinct_Names (Old)
            then (for all J in 0 .. Terminals.Count - 1 =>
                    not Same_Name (Terminals.Items (J).Name, Moved.Name)
                    and then not Same_Name (Moved.Name,
                                            Terminals.Items (J).Name)));
         Insert_Terminal (Terminals.all, To, Moved);
      end;
      Set_Success (Status);
   end Terminals_Move;

   procedure Terminals_Index_Of
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Index     : out Int32;
      Status    : out Ks_Status) is
   begin
      Index := No_Index;
      if Terminals /= null and then Name_Fits (Name) then
         Index := Find (Terminals.all, To_Name (Name));
      end if;
      Set_Success (Status);
   end Terminals_Index_Of;

   procedure Terminals_Name
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Index     : Int32;
      Name      : out Ks_Tool_Text;
      Status    : out Ks_Status) is
   begin
      Name := (Length => 0, Text => [others => ASCII.NUL]);
      if Index < 0 or else Index >= Int32 (Terminal_Count_Of (Terminals))
      then
         Bad_Terminal_Index (Status, Index, Terminal_Count_Of (Terminals));
         return;
      end if;
      declare
         Stored_Name : constant Terminal_Name :=
           Terminals.Items (Natural (Index)).Name;
      begin
         Name :=
           (Length => Int32 (Stored_Name.Length),
            Text   => [for K in 1 .. Max_Text_Length =>
                         (if K <= Stored_Name.Length
                          then Stored_Name.Text (K)
                          else ASCII.NUL)]);
      end;
      Set_Success (Status);
   end Terminals_Name;

   procedure Terminals_Value_Type
     (Terminals  : access constant Ks_Tool_Block_Terminals_Data;
      Name       : Ks_Tool_Text;
      Value_Type : out Int32;
      Status     : out Ks_Status)
   is
      Index : Int32;
   begin
      Value_Type := Type_Real;
      Lookup (Terminals, Name, Index, Status);
      if Succeeded (Status) then
         Lemma_Only_Match (Terminals.all, Natural (Index), To_Name (Name));
         Value_Type := Terminals.Items (Natural (Index)).Value_Type;
      end if;
   end Terminals_Value_Type;

   procedure Terminals_Has_Value
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Has_Value : out Int32;
      Status    : out Ks_Status)
   is
      Index : Int32;
   begin
      Has_Value := False_Value;
      Lookup (Terminals, Name, Index, Status);
      if Succeeded (Status)
        and then Terminals.Items (Natural (Index)).Has_Value
      then
         Has_Value := True_Value;
      end if;
   end Terminals_Has_Value;

   procedure Terminals_Set_Real
     (Terminals : Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Long_Float;
      Status    : out Ks_Status)
   is
      Index : Int32;
   begin
      if not (Value >= -Long_Float'Last and then Value <= Long_Float'Last)
      then
         Bad (Status, "Value must be finite");
         return;
      end if;
      Lookup_Typed (Terminals, Name, Type_Real, Index, Status);
      if Succeeded (Status) then
         Lemma_Only_Match (Terminals.all, Natural (Index), To_Name (Name));
         Terminals.Items (Natural (Index)).Real_Value := Value;
      end if;
   end Terminals_Set_Real;

   procedure Terminals_Get_Real
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Value     : out Long_Float;
      Status    : out Ks_Status)
   is
      Index : Int32;
   begin
      Value := 0.0;
      Lookup_Typed (Terminals, Name, Type_Real, Index, Status);
      if Succeeded (Status) then
         Lemma_Only_Match (Terminals.all, Natural (Index), To_Name (Name));
         Value := Terminals.Items (Natural (Index)).Real_Value;
      end if;
   end Terminals_Get_Real;

   procedure Terminals_Set_Integer
     (Terminals : Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Int64;
      Status    : out Ks_Status)
   is
      Index : Int32;
   begin
      Lookup_Typed (Terminals, Name, Type_Integer, Index, Status);
      if Succeeded (Status) then
         Lemma_Only_Match (Terminals.all, Natural (Index), To_Name (Name));
         Terminals.Items (Natural (Index)).Integer_Value := Value;
      end if;
   end Terminals_Set_Integer;

   procedure Terminals_Get_Integer
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Value     : out Int64;
      Status    : out Ks_Status)
   is
      Index : Int32;
   begin
      Value := 0;
      Lookup_Typed (Terminals, Name, Type_Integer, Index, Status);
      if Succeeded (Status) then
         Lemma_Only_Match (Terminals.all, Natural (Index), To_Name (Name));
         Value := Terminals.Items (Natural (Index)).Integer_Value;
      end if;
   end Terminals_Get_Integer;

   procedure Terminals_Set_Boolean
     (Terminals : Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Int32;
      Status    : out Ks_Status)
   is
      Index : Int32;
   begin
      if Value not in False_Value | True_Value then
         Bad (Status, "Value must be 0 or 1");
         return;
      end if;
      Lookup_Typed (Terminals, Name, Type_Boolean, Index, Status);
      if Succeeded (Status) then
         Lemma_Only_Match (Terminals.all, Natural (Index), To_Name (Name));
         Terminals.Items (Natural (Index)).Boolean_Value :=
           Value = True_Value;
      end if;
   end Terminals_Set_Boolean;

   procedure Terminals_Get_Boolean
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Value     : out Int32;
      Status    : out Ks_Status)
   is
      Index : Int32;
   begin
      Value := False_Value;
      Lookup_Typed (Terminals, Name, Type_Boolean, Index, Status);
      if Succeeded (Status) then
         Lemma_Only_Match (Terminals.all, Natural (Index), To_Name (Name));
         if Terminals.Items (Natural (Index)).Boolean_Value then
            Value := True_Value;
         end if;
      end if;
   end Terminals_Get_Boolean;

   procedure Terminals_Set_String
     (Terminals : Ks_Tool_Block_Terminals;
      Name      : Ks_Tool_Text;
      Value     : Ks_Tool_Text;
      Status    : out Ks_Status)
   is
      Index : Int32;
   begin
      Check_String (Value, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Lookup_Typed (Terminals, Name, Type_String, Index, Status);
      if Succeeded (Status) then
         Lemma_Only_Match (Terminals.all, Natural (Index), To_Name (Name));
         Terminals.Items (Natural (Index)).String_Value := Stored (Value);
      end if;
   end Terminals_Set_String;

   procedure Terminals_Get_String
     (Terminals : access constant Ks_Tool_Block_Terminals_Data;
      Name      : Ks_Tool_Text;
      Value     : out Ks_Tool_Text;
      Status    : out Ks_Status)
   is
      Index : Int32;
   begin
      Value := (Length => 0, Text => [others => ASCII.NUL]);
      Lookup_Typed (Terminals, Name, Type_String, Index, Status);
      if Succeeded (Status) then
         Lemma_Only_Match (Terminals.all, Natural (Index), To_Name (Name));
         declare
            Source : constant Stored_Text :=
              Terminals.Items (Natural (Index)).String_Value;
         begin
            Value := (Length => Int32 (Source.Length), Text => Source.Text);
         end;
      end if;
   end Terminals_Get_String;

   procedure Check_Object_Type (Value_Type : Int32; Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Succeeded (Status) = (Value_Type in Object_Type_Code);
   --  Value_Type is an object type code.

   procedure Check_Object_Type (Value_Type : Int32; Status : out Ks_Status)
   is
   begin
      if Value_Type in Object_Type_Code then
         Set_Success (Status);
      else
         Bad (Status, "ValueType must be an object type code (4 .. 7)");
      end if;
   end Check_Object_Type;

   procedure Terminals_Set_Object
     (Terminals  : Ks_Tool_Block_Terminals;
      Name       : Ks_Tool_Text;
      Value_Type : Int32;
      Index      : out Int32;
      Status     : out Ks_Status) is
   begin
      Index := No_Index;
      Check_Object_Type (Value_Type, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Lookup_Typed (Terminals, Name, Value_Type, Index, Status);
      if Succeeded (Status) then
         Lemma_Only_Match (Terminals.all, Natural (Index), To_Name (Name));
         Terminals.Items (Natural (Index)).Has_Value := True;
      end if;
   end Terminals_Set_Object;

   procedure Terminals_Get_Object
     (Terminals  : access constant Ks_Tool_Block_Terminals_Data;
      Name       : Ks_Tool_Text;
      Value_Type : Int32;
      Index      : out Int32;
      Status     : out Ks_Status) is
   begin
      Index := No_Index;
      Check_Object_Type (Value_Type, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Lookup_Typed (Terminals, Name, Value_Type, Index, Status);
      if Succeeded (Status)
        and then not Terminals.Items (Natural (Index)).Has_Value
      then
         Bad (Status, "Terminal """ & Shown (Name) & """ has no value");
         Index := No_Index;
      end if;
   end Terminals_Get_Object;

   ---------------------------------------------------------------------
   --  RunTool
   ---------------------------------------------------------------------

   procedure Run_Tool_Begin
     (Group  : access constant Ks_Tool_Group_Data;
      Key    : Int64;
      Run    : out Int32;
      Status : out Ks_Status)
   is
   begin
      Run := True_Value;
      if Group /= null then
         for I in 0 .. Group.Count - 1 loop
            if Group.Members (I).Key = Key
              and then Group.Members (I).Disabled
            then
               Run := False_Value;
            end if;
            pragma Loop_Invariant (Run in False_Value | True_Value);
            pragma Loop_Invariant
              ((Run = False_Value)
               = (for some J in 0 .. I =>
                    Group.Members (J).Key = Key
                    and then Group.Members (J).Disabled));
         end loop;
      end if;
      Set_Success (Status);
   end Run_Tool_Begin;

   procedure Run_Tool_End
     (Group      : access constant Ks_Tool_Group_Data;
      Sub_Result : Int32;
      Result     : in out Int32;
      Replace    : out Int32;
      Abort_Run  : out Int32;
      Status     : out Ks_Status)
   is
   begin
      Replace := False_Value;
      Abort_Run := False_Value;
      if Sub_Result not in Result_Code then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunTool: the tool's result must be a "
                      & "CogToolResultConstants value (-1 .. 2)");
         return;
      elsif Result not in Result_Code then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "RunTool: result must be a CogToolResultConstants "
                      & "value (-1 .. 2)");
         return;
      end if;
      if Rank (Sub_Result) > Rank (Result) then
         Replace := True_Value;
      end if;
      Result := Worse (Result, Sub_Result);
      if Sub_Result = Result_Error and then Group /= null
        and then Group.Abort_On_Failure
      then
         Abort_Run := True_Value;
      end if;
      Set_Success (Status);
   end Run_Tool_End;

end AMV.Kernels.Tool_Group;
