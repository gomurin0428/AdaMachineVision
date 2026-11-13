pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Unchecked_Conversion;

with System;

with AMV.Checks;
with AMV.Kernels;

package body AMV.Tool_Group is

   use Ada.Strings.Unbounded;
   use AMV.Tools;

   use type AMV.Kernels.Int32;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   function Key_Of is new Ada.Unchecked_Conversion
     (System.Address, AMV.Kernels.Int64);
   --  A tool's key in the kernel: its address.

   Result_Codes : constant array (Ks_Tool_Result_Constants) of Int32 :=
     [Accept_Result => KG.Result_Accept,
      Warning       => KG.Result_Warning,
      Reject        => KG.Result_Reject,
      Error         => KG.Result_Error];
   --  CogToolResultConstants as the kernel codes them (VisionPro's
   --  values).

   Results : constant array (KG.Result_Code) of Ks_Tool_Result_Constants :=
     [KG.Result_Error   => Error,
      KG.Result_Accept  => Accept_Result,
      KG.Result_Warning => Warning,
      KG.Result_Reject  => Reject];

   Flags : constant array (Boolean) of Int32 :=
     [False => AMV.Kernels.False_Value, True => AMV.Kernels.True_Value];

   ---------------------------------------------------------------------
   --  The kernel handle
   ---------------------------------------------------------------------

   overriding procedure Adjust (Item : in out Group_Handle) is
      Source : constant KG.Ks_Tool_Group := Item.Handle;
      Status : Ks_Status;
   begin
      --  The copy shares the source's handle until it has its own; it
      --  must not keep it if the duplicate cannot be made.
      Item.Handle := null;
      KG.Group_Duplicate (Source, Item.Handle, Status);
      Check (Status);
   end Adjust;

   overriding procedure Finalize (Item : in out Group_Handle) is
   begin
      KG.Group_Destroy (Item.Handle);
   end Finalize;

   procedure Write_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Group_Handle) is
   begin
      raise Program_Error
        with "AMV.Tool_Group: tool groups and blocks are not stored in "
             & "streams";
   end Write_Handle;

   procedure Read_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Group_Handle) is
   begin
      raise Program_Error
        with "AMV.Tool_Group: tool groups and blocks are not stored in "
             & "streams";
   end Read_Handle;

   procedure Set_Own_Key (Group : in out Ks_Tool_Group);
   --  Gives the kernel the group's own key (its address, which a copy
   --  does not share).

   procedure Set_Own_Key (Group : in out Ks_Tool_Group) is
      Status : Ks_Status;
   begin
      KG.Group_Set_Own_Key (Group.Kernel.Handle, Key_Of (Group'Address),
                            Status);
      Check (Status);
   end Set_Own_Key;

   ---------------------------------------------------------------------
   --  Tools
   ---------------------------------------------------------------------

   function Count (Group : Ks_Tool_Group) return Natural is
      Value  : Int32;
      Status : Ks_Status;
   begin
      KG.Group_Count (Group.Kernel.Handle, Value, Status);
      Check (Status);
      return Natural (Value);
   end Count;

   function Item (Group : Ks_Tool_Group; Index : Natural)
      return Ks_Tool_Access
   is
      Unused_Key : AMV.Kernels.Int64;
      Status     : Ks_Status;
   begin
      KG.Group_Item (Group.Kernel.Handle, Int32 (Index), Unused_Key, Status);
      Check (Status);
      return Group.Members.Element (Index);
   end Item;

   function Index_Of
     (Group : Ks_Tool_Group;
      Tool  : not null access constant AMV.Tools.Ks_Tool'Class)
      return Integer
   is
      Index  : Int32;
      Status : Ks_Status;
   begin
      KG.Group_Index_Of (Group.Kernel.Handle, Key_Of (Tool.all'Address),
                         Index, Status);
      Check (Status);
      return Integer (Index);
   end Index_Of;

   function Contains
     (Group : Ks_Tool_Group;
      Tool  : not null access constant AMV.Tools.Ks_Tool'Class)
      return Boolean
   is (Index_Of (Group, Tool) /= KG.No_Index);

   procedure Add
     (Group : in out Ks_Tool_Group;
      Tool  : not null access AMV.Tools.Ks_Tool'Class)
   is
      Status : Ks_Status;
   begin
      Set_Own_Key (Group);
      KG.Group_Add (Group.Kernel.Handle, Key_Of (Tool.all'Address), Status);
      Check (Status);
      Group.Members.Append (Tool.all'Unchecked_Access);
   end Add;

   procedure Insert
     (Group : in out Ks_Tool_Group;
      Index : Natural;
      Tool  : not null access AMV.Tools.Ks_Tool'Class)
   is
      Status : Ks_Status;
   begin
      Set_Own_Key (Group);
      KG.Group_Insert (Group.Kernel.Handle, Int32 (Index),
                       Key_Of (Tool.all'Address), Status);
      Check (Status);
      Group.Members.Insert (Index, Tool.all'Unchecked_Access);
   end Insert;

   procedure Remove
     (Group : in out Ks_Tool_Group;
      Tool  : not null access constant AMV.Tools.Ks_Tool'Class)
   is
      Index  : Int32;
      Status : Ks_Status;
   begin
      KG.Group_Remove (Group.Kernel.Handle, Key_Of (Tool.all'Address),
                       Index, Status);
      Check (Status);
      Group.Members.Delete (Natural (Index));
   end Remove;

   procedure Sync_Names (Group : Ks_Tool_Group);
   --  Hands every member's current Name to the kernel, for a lookup by
   --  name.

   procedure Sync_Names (Group : Ks_Tool_Group) is
      Status : Ks_Status;
   begin
      for I in 0 .. Natural (Group.Members.Length) - 1 loop  --  SHELL: reads each member tool's Name (Ada objects the kernel cannot read)
         KG.Group_Set_Name
           (Group.Kernel.Handle, Int32 (I),
            KG.To_Text (Group.Members.Element (I).Name), Status);
         Check (Status);
      end loop;  --  SHELL: reads each member tool's Name (the loop above)
   end Sync_Names;

   function Item (Group : Ks_Tool_Group; Name : String)
      return Ks_Tool_Access
   is
      Key    : AMV.Kernels.Int64;
      Index  : Int32;
      Status : Ks_Status;
   begin
      Sync_Names (Group);
      KG.Group_Item_By_Name
        (Group.Kernel.Handle, KG.To_Text (Name), Key, Status);
      Check (Status);
      KG.Group_Index_Of (Group.Kernel.Handle, Key, Index, Status);
      Check (Status);
      return Group.Members.Element (Natural (Index));
   end Item;

   function Index_Of (Group : Ks_Tool_Group; Name : String) return Integer
   is
      Index  : Int32;
      Status : Ks_Status;
   begin
      Sync_Names (Group);
      KG.Group_Index_Of_Name
        (Group.Kernel.Handle, KG.To_Text (Name), Index, Status);
      Check (Status);
      return Integer (Index);
   end Index_Of;

   function Contains (Group : Ks_Tool_Group; Name : String) return Boolean
   is (Index_Of (Group, Name) /= KG.No_Index);

   procedure Remove (Group : in out Ks_Tool_Group; Name : String) is
      Key    : AMV.Kernels.Int64;
      Index  : Int32;
      Status : Ks_Status;
   begin
      Sync_Names (Group);
      KG.Group_Item_By_Name
        (Group.Kernel.Handle, KG.To_Text (Name), Key, Status);
      Check (Status);
      KG.Group_Remove (Group.Kernel.Handle, Key, Index, Status);
      Check (Status);
      Group.Members.Delete (Natural (Index));
   end Remove;

   procedure Remove_At (Group : in out Ks_Tool_Group; Index : Natural) is
      Status : Ks_Status;
   begin
      KG.Group_Remove_At (Group.Kernel.Handle, Int32 (Index), Status);
      Check (Status);
      Group.Members.Delete (Index);
   end Remove_At;

   procedure Move
     (Group      : in out Ks_Tool_Group;
      From_Index : Natural;
      To_Index   : Natural)
   is
      Status : Ks_Status;
   begin
      KG.Group_Move (Group.Kernel.Handle, Int32 (From_Index),
                     Int32 (To_Index), Status);
      Check (Status);
      declare
         Moved : constant Ks_Tool_Access := Group.Members.Element (From_Index);
      begin
         Group.Members.Delete (From_Index);
         Group.Members.Insert (To_Index, Moved);
      end;
   end Move;

   procedure Clear (Group : in out Ks_Tool_Group) is
      Status : Ks_Status;
   begin
      KG.Group_Clear (Group.Kernel.Handle, Status);
      Check (Status);
      Group.Members.Clear;
   end Clear;

   ---------------------------------------------------------------------
   --  Settings
   ---------------------------------------------------------------------

   function Abort_Run_On_Tool_Failure (Group : Ks_Tool_Group)
      return Boolean
   is
      Value  : Int32;
      Status : Ks_Status;
   begin
      KG.Group_Abort_Run_On_Tool_Failure (Group.Kernel.Handle, Value, Status);
      Check (Status);
      return Value = AMV.Kernels.True_Value;
   end Abort_Run_On_Tool_Failure;

   procedure Set_Abort_Run_On_Tool_Failure
     (Group : in out Ks_Tool_Group;
      Value : Boolean)
   is
      Status : Ks_Status;
   begin
      KG.Group_Set_Abort_Run_On_Tool_Failure
        (Group.Kernel.Handle, Flags (Value), Status);
      Check (Status);
   end Set_Abort_Run_On_Tool_Failure;

   function Disabled (Group : Ks_Tool_Group; Index : Natural)
      return Boolean
   is
      Value  : Int32;
      Status : Ks_Status;
   begin
      KG.Group_Disabled (Group.Kernel.Handle, Int32 (Index), Value, Status);
      Check (Status);
      return Value = AMV.Kernels.True_Value;
   end Disabled;

   procedure Set_Disabled
     (Group : in out Ks_Tool_Group;
      Index : Natural;
      Value : Boolean)
   is
      Status : Ks_Status;
   begin
      KG.Group_Set_Disabled (Group.Kernel.Handle, Int32 (Index),
                             Flags (Value), Status);
      Check (Status);
   end Set_Disabled;

   function Script (Group : Ks_Tool_Group) return Ks_Tool_Group_Script is
     (Group.Script);

   procedure Set_Script
     (Group  : in out Ks_Tool_Group;
      Script : Ks_Tool_Group_Script) is
   begin
      Group.Script := Script;
   end Set_Script;

   procedure Run_Tool
     (Group    : in out Ks_Tool_Group;
      Sub_Tool : not null access AMV.Tools.Ks_Tool'Class;
      Message  : in out Unbounded_String;
      Result   : in out Ks_Tool_Result_Constants)
   is
      Run       : Int32;
      Code      : Int32 := Result_Codes (Result);
      Replace   : Int32;
      Abort_Run : Int32;
      Status    : Ks_Status;
   begin
      KG.Run_Tool_Begin (Group.Kernel.Handle, Key_Of (Sub_Tool.all'Address),
                         Run, Status);
      Check (Status);
      if Run = AMV.Kernels.False_Value then
         return;
      end if;
      Sub_Tool.Run;
      KG.Run_Tool_End
        (Group.Kernel.Handle, Result_Codes (Sub_Tool.Run_Status.Result),
         Code, Replace, Abort_Run, Status);
      Check (Status);
      Result := Results (Code);
      if Replace = AMV.Kernels.True_Value then
         Message := To_Unbounded_String (Sub_Tool.Run_Status.Message);
      end if;
      if Abort_Run = AMV.Kernels.True_Value then
         raise Ks_Exception with Sub_Tool.Run_Status.Message;
      end if;
   end Run_Tool;

   ---------------------------------------------------------------------
   --  Run
   ---------------------------------------------------------------------

   overriding procedure Execute (Group : in out Ks_Tool_Group) is
      Script_Message : Unbounded_String;
      Script_Result  : Ks_Tool_Result_Constants := Accept_Result;
      Run_Tools      : Boolean := True;
      Cursor         : KG.Ks_Tool_Group_Cursor;
      Index          : Int32;
      More           : Int32;
      Code           : Int32;
      Unused_First   : Int32;
      Text           : KG.Ks_Tool_Text;
      Status         : Ks_Status;
      Ignored        : Ks_Status;
      Started        : Boolean := False;
   begin
      if Group.Script /= null then
         Group.Script (Ks_Tool_Group'Class (Group), Script_Message,
                       Script_Result, Run_Tools);
      end if;
      KG.Run_Begin (Group.Kernel.Handle, Result_Codes (Script_Result),
                    KG.To_Text (To_String (Script_Message)),
                    Flags (Run_Tools), Cursor, Status);
      Check (Status);
      Started := True;
      --  The kernel offers the members in turn and decides when the run
      --  stops; a failed call marks the cursor, ends the loop and makes
      --  Run_End report the failure.
      loop  --  SHELL: dispatching Run of each member (cannot live in the kernel)
         KG.Run_Next (Group.Kernel.Handle, Cursor, Index, More, Ignored);
         exit when More = AMV.Kernels.False_Value;
         declare
            Member : constant Ks_Tool_Access :=
              Group.Members.Element (Natural (Index));
         begin
            Member.Run;  --  SHELL: dispatching Run of each member (cannot live in the kernel)
            KG.Run_Report
              (Group.Kernel.Handle, Cursor, Index,
               Result_Codes (Member.Run_Status.Result),
               KG.To_Text (Member.Name),
               KG.To_Text (Member.Run_Status.Message), Ignored);
         end;
      end loop;  --  SHELL: dispatching Run of each member (the loop above)
      Started := False;
      KG.Run_End (Group.Kernel.Handle, Cursor, Code, Unused_First, Text,
                  Status);
      Check (Status);
      Set_Result (Group, Results (Code), KG.To_String (Text));
   exception
      when others =>
         --  End a run that an exception interrupted, so that the group
         --  is not left running (every later Run would fail); Run turns
         --  the exception into an Error status.
         if Started then
            KG.Run_End (Group.Kernel.Handle, Cursor, Code, Unused_First,
                        Text, Ignored);
         end if;
         raise;
   end Execute;

end AMV.Tool_Group;
