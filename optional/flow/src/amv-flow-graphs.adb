pragma SPARK_Mode (Off);

with Ada.Containers.Ordered_Sets;
with Ada.Directories;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Unchecked_Deallocation;

with AMV.Flow.JSON;
with AMV.Flow.Kinds;

package body AMV.Flow.Graphs is

   use AMV.Flow.Nodes;
   use AMV.Flow.Values;
   use type AMV.Tools.Ks_Tool_Result_Constants;
   use type Ada.Containers.Count_Type;

   package Id_Vectors is new Ada.Containers.Vectors (Positive, Positive);
   package Id_Sets is new Ada.Containers.Ordered_Sets (Positive);

   subtype J_Node is AMV.Flow.JSON.Node;

   function U (S : String) return Unbounded_String
     renames To_Unbounded_String;

   function Id_Image (Id : Natural) return String is
     (Ada.Strings.Fixed.Trim (Id'Image, Ada.Strings.Both));

   function Describe (Flow : Ks_Flow; Id : Positive) return String is
     ("node " & Id_Image (Id) & " ("
      & Flow.Nodes.Element (Id).Kind_Id & ")");

   function Endpoint_Text (E : Endpoint; Source : Boolean) return String is
     ((if E.Node /= 0 then Id_Image (E.Node)
       elsif Source then "input"
       else "output")
      & "." & To_String (E.Port));

   function Same (Left, Right : Endpoint) return Boolean is
     (Left.Node = Right.Node and then Left.Port = Right.Port);

   function Find_Interface (List : Interface_Vectors.Vector; Name : String)
                            return Natural is
   begin
      for I in 1 .. Natural (List.Length) loop
         if To_String (List (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Interface;

   function Parse_Endpoint (Text : String; Source : Boolean) return Endpoint
   is
      Dot : constant Natural := Ada.Strings.Fixed.Index (Text, ".");

      procedure Bad with No_Return;
      procedure Bad is
      begin
         raise Ks_Flow_Exception with
           "bad link endpoint """ & Text & """ (<node id>.<port>, "
           & "input.<name> or output.<name>)";
      end Bad;
   begin
      if Dot = 0 or else Dot = Text'First or else Dot = Text'Last then
         Bad;
      end if;
      declare
         Left  : constant String := Text (Text'First .. Dot - 1);
         Right : constant String := Text (Dot + 1 .. Text'Last);
      begin
         if not Valid_Name (Right) then
            Bad;
         elsif Left = "input" then
            if not Source then
               raise Ks_Flow_Exception with
                 "a flow input (" & Text & ") can only be the source of "
                 & "a link";
            end if;
            return (Node => 0, Port => U (Right));
         elsif Left = "output" then
            if Source then
               raise Ks_Flow_Exception with
                 "a flow output (" & Text & ") can only be the destination "
                 & "of a link";
            end if;
            return (Node => 0, Port => U (Right));
         elsif Left'Length > 10
           or else (for some C of Left => C not in '0' .. '9')
         then
            Bad;
         end if;
         declare
            Id : constant Long_Long_Integer := Long_Long_Integer'Value (Left);
         begin
            if Id < 1 or else Id > Max_Node_Id then
               Bad;
            end if;
            return (Node => Natural (Id), Port => U (Right));
         end;
      end;
   end Parse_Endpoint;

   ---------------------------------------------------------------------
   --  The flow
   ---------------------------------------------------------------------

   procedure Clear (Flow : in out Ks_Flow) is
   begin
      for C in Flow.Nodes.Iterate loop
         declare
            N : Node_Access := Node_Maps.Element (C);
         begin
            Free (N);
         end;
      end loop;
      Flow.Nodes.Clear;
      Flow.Links.Clear;
      Flow.Inputs.Clear;
      Flow.Outputs.Clear;
      Flow.Flow_Name := Null_Unbounded_String;
      Flow.Base_Dir := Null_Unbounded_String;
      Flow.Outcome := AMV.Tools.Accept_Result;
      Flow.Why := Null_Unbounded_String;
   end Clear;

   overriding procedure Finalize (Flow : in out Ks_Flow) is
   begin
      Clear (Flow);
   end Finalize;

   function Name (Flow : Ks_Flow) return String is
     (To_String (Flow.Flow_Name));

   procedure Set_Name (Flow : in out Ks_Flow; Value : String) is
   begin
      if Value'Length > 256 then
         raise Ks_Flow_Exception with "a flow name has at most 256 characters";
      end if;
      Flow.Flow_Name := U (Value);
   end Set_Name;

   function Base_Directory (Flow : Ks_Flow) return String is
     (To_String (Flow.Base_Dir));

   procedure Set_Base_Directory (Flow : in out Ks_Flow; Value : String) is
   begin
      Flow.Base_Dir := U (Value);
   end Set_Base_Directory;

   ---------------------------------------------------------------------
   --  Flow inputs and outputs
   ---------------------------------------------------------------------

   procedure Add_Interface (List : in out Interface_Vectors.Vector;
                            What, Name : String;
                            Value_Type : Ks_Flow_Value_Type) is
   begin
      if not Valid_Name (Name) then
         raise Ks_Flow_Exception with
           "not a valid " & What & " name: """ & Name & """";
      elsif Find_Interface (List, Name) /= 0 then
         raise Ks_Flow_Exception with
           "the flow already has an " & What & " """ & Name & """";
      end if;
      List.Append (Interface_Port'(Name => U (Name), Value_Type => Value_Type,
                                   Value => No_Value));
   end Add_Interface;

   procedure Add_Input (Flow : in out Ks_Flow; Name : String;
                        Value_Type : Ks_Flow_Value_Type) is
   begin
      Add_Interface (Flow.Inputs, "input", Name, Value_Type);
   end Add_Input;

   procedure Add_Output (Flow : in out Ks_Flow; Name : String;
                         Value_Type : Ks_Flow_Value_Type) is
   begin
      Add_Interface (Flow.Outputs, "output", Name, Value_Type);
   end Add_Output;

   function Input_Count (Flow : Ks_Flow) return Natural is
     (Natural (Flow.Inputs.Length));
   function Input_Name (Flow : Ks_Flow; Index : Positive) return String is
     (To_String (Flow.Inputs (Index).Name));
   function Input_Type (Flow : Ks_Flow; Index : Positive)
                        return Ks_Flow_Value_Type is
     (Flow.Inputs (Index).Value_Type);
   function Output_Count (Flow : Ks_Flow) return Natural is
     (Natural (Flow.Outputs.Length));
   function Output_Name (Flow : Ks_Flow; Index : Positive) return String is
     (To_String (Flow.Outputs (Index).Name));
   function Output_Type (Flow : Ks_Flow; Index : Positive)
                         return Ks_Flow_Value_Type is
     (Flow.Outputs (Index).Value_Type);

   ---------------------------------------------------------------------
   --  Nodes
   ---------------------------------------------------------------------

   function Add_Node (Flow : in out Ks_Flow; Kind : String;
                      Id   : Natural := 0) return Positive
   is
      New_Id : constant Natural :=
        (if Id /= 0 then Id
         elsif Flow.Nodes.Is_Empty then 1
         else Flow.Nodes.Last_Key + 1);
      N      : Node_Access;
   begin
      if New_Id > Max_Node_Id then
         raise Ks_Flow_Exception with
           "a node id must be in 1 .." & Max_Node_Id'Image;
      elsif Flow.Nodes.Contains (New_Id) then
         raise Ks_Flow_Exception with
           "there is already a node " & Id_Image (New_Id);
      end if;
      N := AMV.Flow.Kinds.Create (Kind);
      Flow.Nodes.Insert (New_Id, N);
      return New_Id;
   end Add_Node;

   procedure Remove_Node (Flow : in out Ks_Flow; Id : Positive) is
      N : Node_Access;
   begin
      if not Flow.Nodes.Contains (Id) then
         raise Ks_Flow_Exception with "there is no node " & Id_Image (Id);
      end if;
      for I in reverse 1 .. Natural (Flow.Links.Length) loop
         if Flow.Links (I).From.Node = Id or else Flow.Links (I).To.Node = Id
         then
            Flow.Links.Delete (I);
         end if;
      end loop;
      N := Flow.Nodes.Element (Id);
      Flow.Nodes.Delete (Id);
      Free (N);
   end Remove_Node;

   function Node_Count (Flow : Ks_Flow) return Natural is
     (Natural (Flow.Nodes.Length));

   function Node_Id_At (Flow : Ks_Flow; Index : Positive) return Positive is
      I : Natural := 0;
   begin
      for C in Flow.Nodes.Iterate loop
         I := I + 1;
         if I = Index then
            return Node_Maps.Key (C);
         end if;
      end loop;
      raise Constraint_Error with "no node at index" & Index'Image;
   end Node_Id_At;

   function Contains (Flow : Ks_Flow; Id : Positive) return Boolean is
     (Flow.Nodes.Contains (Id));

   function Node (Flow : Ks_Flow; Id : Positive)
                  return AMV.Flow.Nodes.Node_Access is
   begin
      if not Flow.Nodes.Contains (Id) then
         raise Ks_Flow_Exception with "there is no node " & Id_Image (Id);
      end if;
      return Flow.Nodes.Element (Id);
   end Node;

   procedure Set_Param (Flow  : in out Ks_Flow;
                        Id    : Positive;
                        Name  : String;
                        Value : AMV.Flow.Values.Ks_Flow_Value)
   is
      N : constant Node_Access := Node (Flow, Id);
   begin
      Set_Param_Checked (N.all, Name, Value);
      N.Prepare (Base_Directory (Flow));
   end Set_Param;

   procedure Prepare (Flow : in out Ks_Flow) is
   begin
      for C in Flow.Nodes.Iterate loop
         declare
            Id : constant Positive := Node_Maps.Key (C);
         begin
            Node_Maps.Element (C).Prepare (Base_Directory (Flow));
         exception
            when E : Ks_Flow_Exception =>
               raise Ks_Flow_Exception with
                 Describe (Flow, Id) & ": "
                 & Ada.Exceptions.Exception_Message (E);
         end;
      end loop;
   end Prepare;

   ---------------------------------------------------------------------
   --  Links
   ---------------------------------------------------------------------

   function Endpoint_Problem (Flow   : Ks_Flow;
                              E      : Endpoint;
                              Source : Boolean;
                              T      : out Ks_Flow_Value_Type) return String
   is
      Port : constant String := To_String (E.Port);
   begin
      T := Real_Type;
      if E.Node = 0 then
         declare
            I : constant Natural :=
              (if Source then Find_Interface (Flow.Inputs, Port)
               else Find_Interface (Flow.Outputs, Port));
         begin
            if I = 0 then
               return "the flow has no "
                 & (if Source then "input" else "output") & " """ & Port
                 & """";
            end if;
            T := (if Source then Flow.Inputs (I).Value_Type
                  else Flow.Outputs (I).Value_Type);
            return "";
         end;
      elsif not Flow.Nodes.Contains (E.Node) then
         return "there is no node " & Id_Image (E.Node);
      end if;
      declare
         N         : constant Node_Access := Flow.Nodes.Element (E.Node);
         All_Ports : constant Port_Array := N.Ports;
         I         : constant Natural :=
           Find_Port (N.all, Port, (if Source then Output else Input));
      begin
         if I = 0 then
            return Describe (Flow, E.Node) & " has no "
              & (if Source then "output" else "input") & " """ & Port & """";
         end if;
         T := All_Ports (I).Value_Type;
         return "";
      end;
   end Endpoint_Problem;

   function Link_Problem (Flow : Ks_Flow; L : Link_Record) return String is
      From_Type, To_Type : Ks_Flow_Value_Type;
      From_Problem : constant String :=
        Endpoint_Problem (Flow, L.From, True, From_Type);
   begin
      if From_Problem /= "" then
         return From_Problem;
      end if;
      declare
         To_Problem : constant String :=
           Endpoint_Problem (Flow, L.To, False, To_Type);
      begin
         if To_Problem /= "" then
            return To_Problem;
         elsif not Can_Link (From_Type, To_Type) then
            return "cannot link " & Endpoint_Text (L.From, True) & " ("
              & Type_Name (From_Type) & ") to " & Endpoint_Text (L.To, False)
              & " (" & Type_Name (To_Type) & ")";
         elsif L.From.Node /= 0 and then L.From.Node = L.To.Node then
            return "a link from a node to itself";
         end if;
         return "";
      end;
   end Link_Problem;

   function Link_Into (Flow : Ks_Flow; To : Endpoint) return Natural is
   begin
      for I in 1 .. Natural (Flow.Links.Length) loop
         if Same (Flow.Links (I).To, To) then
            return I;
         end if;
      end loop;
      return 0;
   end Link_Into;

   procedure Order (Flow     : Ks_Flow;
                    Ordered  : out Id_Vectors.Vector;
                    Complete : out Boolean)
   is
      Done     : Id_Sets.Set;
      Progress : Boolean;
      Ready    : Boolean;
   begin
      Ordered.Clear;
      loop
         Progress := False;
         for C in Flow.Nodes.Iterate loop
            declare
               Id : constant Positive := Node_Maps.Key (C);
            begin
               if not Done.Contains (Id) then
                  Ready := True;
                  for L of Flow.Links loop
                     if L.To.Node = Id and then L.From.Node /= 0
                       and then Flow.Nodes.Contains (L.From.Node)
                       and then not Done.Contains (L.From.Node)
                     then
                        Ready := False;
                        exit;
                     end if;
                  end loop;
                  if Ready then
                     --  The smallest ready id first, then look again from
                     --  the start: the order is the same on every run.
                     Ordered.Append (Id);
                     Done.Insert (Id);
                     Progress := True;
                     exit;
                  end if;
               end if;
            end;
         end loop;
         exit when not Progress;
      end loop;
      Complete := Ordered.Length = Flow.Nodes.Length;
   end Order;

   procedure Link (Flow : in out Ks_Flow; From, To : String) is
      L        : constant Link_Record :=
        (From => Parse_Endpoint (From, Source => True),
         To   => Parse_Endpoint (To, Source => False));
      Problem  : constant String := Link_Problem (Flow, L);
      Ordered  : Id_Vectors.Vector;
      Complete : Boolean;
   begin
      if Problem /= "" then
         raise Ks_Flow_Exception with Problem;
      elsif Link_Into (Flow, L.To) /= 0 then
         raise Ks_Flow_Exception with To & " already has a link";
      end if;
      Flow.Links.Append (L);
      Order (Flow, Ordered, Complete);
      if not Complete then
         Flow.Links.Delete_Last;
         raise Ks_Flow_Exception with
           "the link " & From & " -> " & To & " would close a cycle";
      end if;
   end Link;

   procedure Unlink (Flow : in out Ks_Flow; To : String) is
      I : constant Natural :=
        Link_Into (Flow, Parse_Endpoint (To, Source => False));
   begin
      if I /= 0 then
         Flow.Links.Delete (I);
      end if;
   end Unlink;

   function Link_Count (Flow : Ks_Flow) return Natural is
     (Natural (Flow.Links.Length));

   function Link_From (Flow : Ks_Flow; Index : Positive) return String is
     (Endpoint_Text (Flow.Links (Index).From, Source => True));

   function Link_To (Flow : Ks_Flow; Index : Positive) return String is
     (Endpoint_Text (Flow.Links (Index).To, Source => False));

   ---------------------------------------------------------------------
   --  Checking and running
   ---------------------------------------------------------------------

   function Problems (Flow : Ks_Flow) return String_Vectors.Vector is
      Result   : String_Vectors.Vector;
      Ordered  : Id_Vectors.Vector;
      Complete : Boolean;
   begin
      for I in 1 .. Natural (Flow.Links.Length) loop
         declare
            L       : constant Link_Record := Flow.Links (I);
            Problem : constant String := Link_Problem (Flow, L);
         begin
            if Problem /= "" then
               Result.Append ("link " & Endpoint_Text (L.From, True) & " -> "
                              & Endpoint_Text (L.To, False) & ": " & Problem);
            end if;
            for J in 1 .. I - 1 loop
               if Same (Flow.Links (J).To, L.To) then
                  Result.Append ("two links into "
                                 & Endpoint_Text (L.To, False));
               end if;
            end loop;
         end;
      end loop;

      Order (Flow, Ordered, Complete);
      if not Complete then
         declare
            Left_Over : Unbounded_String;
         begin
            for C in Flow.Nodes.Iterate loop
               if not Ordered.Contains (Node_Maps.Key (C)) then
                  Append (Left_Over, " " & Id_Image (Node_Maps.Key (C)));
               end if;
            end loop;
            Result.Append ("the links form a cycle among the nodes"
                           & To_String (Left_Over));
         end;
      end if;

      for C in Flow.Nodes.Iterate loop
         declare
            Id        : constant Positive := Node_Maps.Key (C);
            N         : constant Node_Access := Node_Maps.Element (C);
            All_Ports : constant Port_Array := N.Ports;
            Problem   : constant String := N.Problem;
         begin
            for P of All_Ports loop
               if P.Direction = Input and then P.Required
                 and then Link_Into (Flow, (Node => Id, Port => P.Name)) = 0
               then
                  Result.Append (Describe (Flow, Id) & ": input "
                                 & To_String (P.Name) & " is not linked");
               end if;
            end loop;
            if Problem /= "" then
               Result.Append (Describe (Flow, Id) & ": " & Problem);
            end if;
         end;
      end loop;

      for O of Flow.Outputs loop
         if Link_Into (Flow, (Node => 0, Port => O.Name)) = 0 then
            Result.Append ("output " & To_String (O.Name) & " is not linked");
         end if;
      end loop;
      return Result;
   end Problems;

   procedure Check (Flow : Ks_Flow) is
      All_Problems : constant String_Vectors.Vector := Problems (Flow);
      Text         : Unbounded_String;
   begin
      if All_Problems.Is_Empty then
         return;
      end if;
      for P of All_Problems loop
         if Length (Text) > 0 then
            Append (Text, "; ");
         end if;
         Append (Text, P);
      end loop;
      raise Ks_Flow_Exception with To_String (Text);
   end Check;

   function Converted (Value : Ks_Flow_Value; To : Ks_Flow_Value_Type)
                       return Ks_Flow_Value is
     (if To = Real_Type and then Value.Has_Value
        and then Value.Kind = Integer_Type
      then From_Real (Value.As_Real)
      else Value);

   procedure Set_Input (Flow  : in out Ks_Flow;
                        Name  : String;
                        Value : AMV.Flow.Values.Ks_Flow_Value)
   is
      I : constant Natural := Find_Interface (Flow.Inputs, Name);
   begin
      if I = 0 then
         raise Ks_Flow_Exception with "the flow has no input """ & Name & """";
      elsif not Value.Has_Value then
         Flow.Inputs (I).Value := No_Value;
         return;
      elsif not Can_Link (Value.Kind, Flow.Inputs (I).Value_Type) then
         raise Ks_Flow_Exception with
           "the input " & Name & " takes " & Type_Name (Flow.Inputs (I).Value_Type)
           & ", not " & Type_Name (Value.Kind);
      end if;
      Flow.Inputs (I).Value := Converted (Value, Flow.Inputs (I).Value_Type);
   end Set_Input;

   function Source_Value (Flow   : Ks_Flow;
                          From   : Endpoint;
                          Reason : in out Unbounded_String)
                          return Ks_Flow_Value is
   begin
      if From.Node = 0 then
         return Flow.Inputs (Find_Interface (Flow.Inputs,
                                             To_String (From.Port))).Value;
      end if;
      declare
         Source : constant Node_Access := Flow.Nodes.Element (From.Node);
      begin
         case Source.State is
            when Skipped =>
               Reason := U (Describe (Flow, From.Node) & " was skipped");
               return No_Value;
            when Not_Run =>
               Reason := U (Describe (Flow, From.Node) & " did not run");
               return No_Value;
            when Ran =>
               if Source.Result = AMV.Tools.Error then
                  Reason := U (Describe (Flow, From.Node) & " failed: "
                               & Source.Message);
                  return No_Value;
               end if;
               return Source.Get_Output (To_String (From.Port));
         end case;
      end;
   end Source_Value;

   procedure Run (Flow : in out Ks_Flow) is
      Ordered  : Id_Vectors.Vector;
      Complete : Boolean;

      --  The message of the first node with the worst result so far: a
      --  reject after a warning names the reject.
      Why_Result : AMV.Tools.Ks_Tool_Result_Constants :=
        AMV.Tools.Accept_Result;

      procedure Note (Id     : Positive;
                      Text   : String;
                      Result : AMV.Tools.Ks_Tool_Result_Constants) is
      begin
         if Length (Flow.Why) = 0 or else Result > Why_Result then
            Flow.Why := U (Describe (Flow, Id) & ": " & Text);
            Why_Result := Result;
         end if;
      end Note;
   begin
      Check (Flow);
      for I in 1 .. Natural (Flow.Inputs.Length) loop
         if not Flow.Inputs (I).Value.Has_Value then
            for L of Flow.Links loop
               if L.From.Node = 0 and then L.From.Port = Flow.Inputs (I).Name
               then
                  raise Ks_Flow_Exception with
                    "the flow input " & To_String (Flow.Inputs (I).Name)
                    & " has no value";
               end if;
            end loop;
         end if;
      end loop;

      Order (Flow, Ordered, Complete);
      for C in Flow.Nodes.Iterate loop
         Node_Maps.Element (C).Clear_Inputs;
         Reset_Status (Node_Maps.Element (C).all);
      end loop;
      for I in 1 .. Natural (Flow.Outputs.Length) loop
         Flow.Outputs (I).Value := No_Value;
      end loop;
      Flow.Outcome := AMV.Tools.Accept_Result;
      Flow.Why := Null_Unbounded_String;

      for Id of Ordered loop
         declare
            N         : constant Node_Access := Flow.Nodes.Element (Id);
            All_Ports : constant Port_Array := N.Ports;
            Reason    : Unbounded_String;
         begin
            for L of Flow.Links loop
               exit when Length (Reason) > 0;
               if L.To.Node = Id then
                  declare
                     Value : constant Ks_Flow_Value :=
                       Source_Value (Flow, L.From, Reason);
                     Port  : constant String := To_String (L.To.Port);
                     P     : constant Port_Descriptor :=
                       All_Ports (Find_Port (N.all, Port, Input));
                  begin
                     if Length (Reason) > 0 then
                        null;
                     elsif Value.Has_Value then
                        N.Set_Input (Port, Converted (Value, P.Value_Type));
                     elsif P.Required then
                        Reason := U ("its input " & Port & " got no value from "
                                     & Endpoint_Text (L.From, True));
                     end if;
                  end;
               end if;
            end loop;

            if Length (Reason) > 0 then
               Skip (N.all, To_String (Reason));
               Flow.Outcome := Worse (Flow.Outcome, AMV.Tools.Reject);
               Note (Id, "skipped: " & To_String (Reason), AMV.Tools.Reject);
            else
               Run (N.all);
               if N.Result /= AMV.Tools.Accept_Result then
                  Flow.Outcome := Worse (Flow.Outcome, N.Result);
                  Note (Id, N.Message, N.Result);
               end if;
            end if;
         end;
      end loop;

      for I in 1 .. Natural (Flow.Outputs.Length) loop
         declare
            Into   : constant Natural :=
              Link_Into (Flow, (Node => 0, Port => Flow.Outputs (I).Name));
            Reason : Unbounded_String;
         begin
            if Into /= 0 then
               declare
                  Value : constant Ks_Flow_Value :=
                    Source_Value (Flow, Flow.Links (Into).From, Reason);
               begin
                  if Length (Reason) = 0 then
                     Flow.Outputs (I).Value :=
                       Converted (Value, Flow.Outputs (I).Value_Type);
                  end if;
               end;
            end if;
         end;
      end loop;
   end Run;

   function Result (Flow : Ks_Flow) return AMV.Tools.Ks_Tool_Result_Constants
   is (Flow.Outcome);

   function Message (Flow : Ks_Flow) return String is (To_String (Flow.Why));

   function Get_Output (Flow : Ks_Flow; Name : String)
                        return AMV.Flow.Values.Ks_Flow_Value
   is
      I : constant Natural := Find_Interface (Flow.Outputs, Name);
   begin
      if I = 0 then
         raise Ks_Flow_Exception with
           "the flow has no output """ & Name & """";
      end if;
      return Flow.Outputs (I).Value;
   end Get_Output;

   function Value_Into (Flow : Ks_Flow; Id : Positive; Port : String)
                        return AMV.Flow.Values.Ks_Flow_Value
   is
      Into   : constant Natural :=
        Link_Into (Flow, (Node => Id, Port => U (Port)));
      Reason : Unbounded_String;
   begin
      if Into = 0 or else not Flow.Nodes.Contains (Id) then
         return No_Value;
      end if;
      declare
         Value : constant Ks_Flow_Value :=
           Source_Value (Flow, Flow.Links (Into).From, Reason);
      begin
         return (if Length (Reason) = 0 then Value else No_Value);
      end;
   end Value_Into;

   ---------------------------------------------------------------------
   --  Flow files
   ---------------------------------------------------------------------

   function To_JSON (Flow : Ks_Flow) return String is
      use AMV.Flow.JSON;
      W : Writer;

      procedure Interface_List (Name : String;
                                List : Interface_Vectors.Vector) is
      begin
         W.Key (Name);
         W.Begin_Array;
         for P of List loop
            W.Begin_Object (Inline => True);
            W.Key ("name");
            W.Value (To_String (P.Name));
            W.Key ("type");
            W.Value (Type_Name (P.Value_Type));
            W.End_Object;
         end loop;
         W.End_Array;
      end Interface_List;
   begin
      W.Begin_Object;
      W.Key ("format");
      W.Value (Long_Long_Integer (Format));
      W.Key ("name");
      W.Value (Name (Flow));
      Interface_List ("inputs", Flow.Inputs);
      Interface_List ("outputs", Flow.Outputs);

      W.Key ("nodes");
      W.Begin_Array;
      for C in Flow.Nodes.Iterate loop
         declare
            N          : constant Node_Access := Node_Maps.Element (C);
            All_Params : constant Param_Array := N.Params;
         begin
            W.Begin_Object;
            W.Key ("id");
            W.Value (Long_Long_Integer (Node_Maps.Key (C)));
            W.Key ("kind");
            W.Value (N.Kind_Id);
            if N.Name /= "" then
               W.Key ("name");
               W.Value (N.Name);
            end if;
            W.Key ("ui");
            W.Begin_Object (Inline => True);
            W.Key ("x");
            W.Value (N.X);
            W.Key ("y");
            W.Value (N.Y);
            W.End_Object;
            W.Key ("params");
            W.Begin_Object;
            for P of All_Params loop
               declare
                  Param_Name : constant String := To_String (P.Name);
                  Value      : constant Ks_Flow_Value :=
                    N.Get_Param (Param_Name);
               begin
                  if Value.Has_Value then
                     W.Key (Param_Name);
                     case P.Kind is
                        when Real_Param =>
                           W.Value (Value.As_Real);
                        when Integer_Param =>
                           W.Value (Value.As_Integer);
                        when Boolean_Param =>
                           W.Value (Value.As_Boolean);
                        when Choice_Param | String_Param =>
                           W.Value (Value.As_String);
                        when Shape_Param =>
                           Write_Shape (W, Value.As_Shape);
                     end case;
                  end if;
               end;
            end loop;
            W.End_Object;
            W.End_Object;
         end;
      end loop;
      W.End_Array;

      W.Key ("links");
      W.Begin_Array;
      for L of Flow.Links loop
         W.Begin_Object (Inline => True);
         W.Key ("from");
         W.Value (Endpoint_Text (L.From, Source => True));
         W.Key ("to");
         W.Value (Endpoint_Text (L.To, Source => False));
         W.End_Object;
      end loop;
      W.End_Array;
      W.End_Object;
      return W.Text & ASCII.LF;
   end To_JSON;

   function JSON_Param_Value (Doc : AMV.Flow.JSON.Document;
                              N   : J_Node;
                              P   : Param_Descriptor) return Ks_Flow_Value
   is
      use AMV.Flow.JSON;
   begin
      case P.Kind is
         when Real_Param =>
            return From_Real (Number_Value (Doc, N));
         when Integer_Param =>
            declare
               X : constant Long_Float := Number_Value (Doc, N);
            begin
               if X /= Long_Float'Floor (X) or else abs X > 1.0E15 then
                  raise Ks_Flow_Exception with "a whole number is needed";
               end if;
               return From_Integer (Long_Long_Integer (X));
            end;
         when Boolean_Param =>
            return From_Boolean (Boolean_Value (Doc, N));
         when Choice_Param | String_Param =>
            return From_String (String_Value (Doc, N));
         when Shape_Param =>
            return From_Shape (Read_Shape (Doc, N));
      end case;
   end JSON_Param_Value;
   --  A parameter's value from its JSON, as the descriptor's kind wants.

   procedure Set_Param_JSON (Flow       : in out Ks_Flow;
                             Id         : Positive;
                             Name       : String;
                             Value_JSON : String)
   is
      Doc   : AMV.Flow.JSON.Document;
      N     : constant Node_Access := Node (Flow, Id);
      Index : constant Natural := Find_Param (N.all, Name);
   begin
      if Index = 0 then
         raise Ks_Flow_Exception with
           Describe (Flow, Id) & " has no parameter """ & Name & """";
      end if;
      AMV.Flow.JSON.Parse (Doc, Value_JSON);
      declare
         All_Params : constant Param_Array := N.Params;
      begin
         Set_Param (Flow, Id, Name,
                    JSON_Param_Value (Doc, AMV.Flow.JSON.Root (Doc),
                                      All_Params (Index)));
      end;
   exception
      when E : AMV.Ks_Bad_Parameter_Exception | AMV.Ks_Exception =>
         raise Ks_Flow_Exception with
           Describe (Flow, Id) & " parameter " & Name & ": "
           & Ada.Exceptions.Exception_Message (E);
   end Set_Param_JSON;

   procedure From_JSON (Flow           : in out Ks_Flow;
                        Text           : String;
                        Base_Directory : String := "")
   is
      use AMV.Flow.JSON;
      Doc : Document;

      procedure Only_Keys (N : J_Node; What : String; Keys : String) is
         --  Keys: the allowed keys, each followed by '|'.
      begin
         for I in 1 .. Length (Doc, N) loop
            if Ada.Strings.Fixed.Index ("|" & Keys, "|" & Key (Doc, N, I) & "|")
              = 0
            then
               raise Ks_Flow_Exception with
                 What & " has an unknown member """ & Key (Doc, N, I) & """";
            end if;
         end loop;
      end Only_Keys;

      function Required_Member (N : J_Node; What, Name : String)
                                return J_Node is
         M : constant J_Node := Member (Doc, N, Name);
      begin
         if M = No_Node then
            raise Ks_Flow_Exception with What & " has no """ & Name & """";
         end if;
         return M;
      end Required_Member;

      procedure Require_Kind (N : J_Node; What : String; K : Kind_Type) is
      begin
         if Kind (Doc, N) /= K then
            raise Ks_Flow_Exception with
              What & " must be " & Kind_Name (K) & ", not "
              & Kind_Name (Kind (Doc, N));
         end if;
      end Require_Kind;

      function Whole (N : J_Node; What : String) return Long_Long_Integer is
         X : constant Long_Float := Number_Value (Doc, N);
      begin
         if X /= Long_Float'Floor (X) or else abs X > 1.0E15 then
            raise Ks_Flow_Exception with What & " must be a whole number";
         end if;
         return Long_Long_Integer (X);
      end Whole;

      function Param_Value (N : J_Node; P : Param_Descriptor)
                            return Ks_Flow_Value is
        (JSON_Param_Value (Doc, N, P));

      procedure Read_Interface (List_Name : String; Input : Boolean) is
         List : constant J_Node := Member (Doc, Root (Doc), List_Name);
      begin
         if List = No_Node then
            return;
         end if;
         Require_Kind (List, """" & List_Name & """", Array_Kind);
         for I in 1 .. Length (Doc, List) loop
            declare
               P    : constant J_Node := Element (Doc, List, I);
               What : constant String := List_Name & " entry" & I'Image;
            begin
               Require_Kind (P, What, Object_Kind);
               Only_Keys (P, What, "name|type|");
               declare
                  P_Name : constant String :=
                    String_Value (Doc, Required_Member (P, What, "name"));
                  P_Type : constant Ks_Flow_Value_Type :=
                    Type_Of (String_Value
                               (Doc, Required_Member (P, What, "type")));
               begin
                  if Input then
                     Add_Input (Flow, P_Name, P_Type);
                  else
                     Add_Output (Flow, P_Name, P_Type);
                  end if;
               end;
            end;
         end loop;
      end Read_Interface;

      procedure Read_Node (N : J_Node; Index : Positive) is
         What : constant String := "nodes entry" & Index'Image;
         Id   : Positive;
      begin
         Require_Kind (N, What, Object_Kind);
         Only_Keys (N, What, "id|kind|name|ui|params|");
         declare
            Id_Value : constant Long_Long_Integer :=
              Whole (Required_Member (N, What, "id"), What & ": id");
         begin
            if Id_Value < 1 or else Id_Value > Max_Node_Id then
               raise Ks_Flow_Exception with
                 What & ": id must be in 1 .." & Max_Node_Id'Image;
            end if;
            Id := Add_Node
              (Flow, String_Value (Doc, Required_Member (N, What, "kind")),
               Natural (Id_Value));
         end;
         declare
            Target : constant Node_Access := Flow.Nodes.Element (Id);
            M      : J_Node;
         begin
            M := Member (Doc, N, "name");
            if M /= No_Node then
               Target.Set_Name (String_Value (Doc, M));
            end if;
            M := Member (Doc, N, "ui");
            if M /= No_Node then
               Require_Kind (M, "ui", Object_Kind);
               declare
                  UX : constant J_Node := Member (Doc, M, "x");
                  UY : constant J_Node := Member (Doc, M, "y");
               begin
                  Target.Set_Position
                    ((if UX = No_Node then 0.0 else Number_Value (Doc, UX)),
                     (if UY = No_Node then 0.0 else Number_Value (Doc, UY)));
               end;
            end if;
            M := Member (Doc, N, "params");
            if M /= No_Node then
               Require_Kind (M, "params", Object_Kind);
               for I in 1 .. Length (Doc, M) loop
                  declare
                     Param_Name : constant String := Key (Doc, M, I);
                     Index_Of   : constant Natural :=
                       Find_Param (Target.all, Param_Name);
                     All_Params : constant Param_Array := Target.Params;
                  begin
                     if Index_Of = 0 then
                        raise Ks_Flow_Exception with
                          "no parameter """ & Param_Name & """";
                     end if;
                     Set_Param_Checked
                       (Target.all, Param_Name,
                        Param_Value (Element (Doc, M, I),
                                     All_Params (Index_Of)));
                  exception
                     when E : Ks_Flow_Exception
                       | AMV.Ks_Bad_Parameter_Exception
                       | AMV.Ks_Exception
                     =>
                        raise Ks_Flow_Exception with
                          "parameter " & Param_Name & ": "
                          & Ada.Exceptions.Exception_Message (E);
                  end;
               end loop;
            end if;
         exception
            when E : Ks_Flow_Exception =>
               raise Ks_Flow_Exception with
                 Describe (Flow, Id) & ": "
                 & Ada.Exceptions.Exception_Message (E);
         end;
      end Read_Node;

      R : J_Node;
   begin
      Clear (Flow);
      Parse (Doc, Text);
      R := Root (Doc);
      Require_Kind (R, "the flow", Object_Kind);
      Only_Keys (R, "the flow", "format|name|inputs|outputs|nodes|links|");
      declare
         F : constant J_Node := Required_Member (R, "the flow", "format");
      begin
         if Kind (Doc, F) /= Number_Kind
           or else Number_Value (Doc, F) /= Long_Float (Format)
         then
            raise Ks_Flow_Exception with
              "the flow file format must be" & Format'Image;
         end if;
      end;
      if Member (Doc, R, "name") /= No_Node then
         Set_Name (Flow, String_Value (Doc, Member (Doc, R, "name")));
      end if;
      Read_Interface ("inputs", Input => True);
      Read_Interface ("outputs", Input => False);

      declare
         List : constant J_Node := Member (Doc, R, "nodes");
      begin
         if List /= No_Node then
            Require_Kind (List, """nodes""", Array_Kind);
            for I in 1 .. Length (Doc, List) loop
               Read_Node (Element (Doc, List, I), I);
            end loop;
         end if;
      end;

      declare
         List : constant J_Node := Member (Doc, R, "links");
      begin
         if List /= No_Node then
            Require_Kind (List, """links""", Array_Kind);
            for I in 1 .. Length (Doc, List) loop
               declare
                  L    : constant J_Node := Element (Doc, List, I);
                  What : constant String := "links entry" & I'Image;
               begin
                  Require_Kind (L, What, Object_Kind);
                  Only_Keys (L, What, "from|to|");
                  Link (Flow,
                        String_Value (Doc, Required_Member (L, What, "from")),
                        String_Value (Doc, Required_Member (L, What, "to")));
               exception
                  when E : Ks_Flow_Exception =>
                     raise Ks_Flow_Exception with
                       What & ": " & Ada.Exceptions.Exception_Message (E);
               end;
            end loop;
         end if;
      end;

      Set_Base_Directory (Flow, Base_Directory);
      Prepare (Flow);
   exception
      when Ks_Flow_Exception =>
         Clear (Flow);
         raise;
      when E : AMV.Ks_Exception | AMV.Ks_Bad_Parameter_Exception
             | AMV.Ks_Image_File_Exception | Constraint_Error =>
         Clear (Flow);
         raise Ks_Flow_Exception with Ada.Exceptions.Exception_Message (E);
   end From_JSON;

   procedure Save (Flow : Ks_Flow; Path : String) is
      use Ada.Streams.Stream_IO;
      Text : constant String := To_JSON (Flow);
      File : File_Type;
   begin
      Create (File, Out_File, Path);
      String'Write (Stream (File), Text);
      Close (File);
   exception
      when E : Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error
             | Ada.IO_Exceptions.Device_Error =>
         if Is_Open (File) then
            Close (File);
         end if;
         raise Ks_Flow_Exception with
           "cannot write " & Path & ": " & Ada.Exceptions.Exception_Message (E);
   end Save;

   procedure Load (Flow : in out Ks_Flow; Path : String) is
      use Ada.Streams.Stream_IO;
      use type Ada.Directories.File_Kind;
      use type Ada.Directories.File_Size;
      type String_Access is access String;
      procedure Free is new Ada.Unchecked_Deallocation (String, String_Access);
      File : File_Type;
      Text : String_Access;
   begin
      if not Ada.Directories.Exists (Path)
        or else Ada.Directories.Kind (Path) /= Ada.Directories.Ordinary_File
      then
         raise Ks_Flow_Exception with "no flow file " & Path;
      elsif Ada.Directories.Size (Path)
              > Ada.Directories.File_Size (AMV.Flow.JSON.Max_Text_Length)
      then
         raise Ks_Flow_Exception with "the flow file " & Path & " is too large";
      end if;
      Text := new String (1 .. Natural (Ada.Directories.Size (Path)));
      Open (File, In_File, Path);
      String'Read (Stream (File), Text.all);
      Close (File);
      begin
         From_JSON (Flow, Text.all,
                    Ada.Directories.Containing_Directory
                      (Ada.Directories.Full_Name (Path)));
      exception
         when others =>
            Free (Text);
            raise;
      end;
      Free (Text);
   exception
      when E : Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error
             | Ada.IO_Exceptions.Device_Error | Ada.IO_Exceptions.End_Error =>
         if Is_Open (File) then
            Close (File);
         end if;
         Free (Text);
         raise Ks_Flow_Exception with
           "cannot read " & Path & ": " & Ada.Exceptions.Exception_Message (E);
   end Load;

end AMV.Flow.Graphs;
