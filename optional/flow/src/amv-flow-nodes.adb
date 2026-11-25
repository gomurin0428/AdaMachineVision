pragma SPARK_Mode (Off);

with Ada.Exceptions;
with Ada.Real_Time;
with Ada.Unchecked_Deallocation;

with AMV.Flow.JSON;

package body AMV.Flow.Nodes is

   use type AMV.Tools.Ks_Tool_Result_Constants;

   function U (S : String) return Unbounded_String
     renames To_Unbounded_String;

   function In_Port (Name : String; Value_Type : Ks_Flow_Value_Type;
                     Required : Boolean := True; Help : String := "")
                     return Port_Descriptor is
     ((Name => U (Name), Direction => Input, Value_Type => Value_Type,
       Required => Required, Help => U (Help)));

   function Out_Port (Name : String; Value_Type : Ks_Flow_Value_Type;
                      Help : String := "") return Port_Descriptor is
     ((Name => U (Name), Direction => Output, Value_Type => Value_Type,
       Required => False, Help => U (Help)));

   function Real_Param_Of (Name : String; Low, High : Real;
                           Unit : String := ""; Help : String := "")
                           return Param_Descriptor is
     ((Name => U (Name), Kind => Real_Param, Low => Low, High => High,
       Unit => U (Unit), Help => U (Help), others => <>));

   function Integer_Param_Of (Name : String; Low, High : Real;
                              Help : String := "") return Param_Descriptor is
     ((Name => U (Name), Kind => Integer_Param, Low => Low, High => High,
       Help => U (Help), others => <>));

   function Boolean_Param_Of (Name : String; Help : String := "")
                              return Param_Descriptor is
     ((Name => U (Name), Kind => Boolean_Param, Help => U (Help),
       others => <>));

   function Choice_Param_Of (Name, Choices : String; Help : String := "")
                             return Param_Descriptor is
     ((Name => U (Name), Kind => Choice_Param, Choices => U (Choices),
       Help => U (Help), others => <>));

   function String_Param_Of (Name : String; Help : String := "")
                             return Param_Descriptor is
     ((Name => U (Name), Kind => String_Param, Help => U (Help),
       others => <>));

   function Shape_Param_Of (Name : String; Help : String := "")
                            return Param_Descriptor is
     ((Name => U (Name), Kind => Shape_Param, Help => U (Help),
       others => <>));

   function Has_Choice (Param : Param_Descriptor; Value : String)
                        return Boolean
   is
      Choices : constant String := To_String (Param.Choices);
      Start   : Positive := Choices'First;
   begin
      for I in Choices'Range loop
         if Choices (I) = '|' then
            if Choices (Start .. I - 1) = Value then
               return True;
            end if;
            Start := I + 1;
         end if;
      end loop;
      return Choices (Start .. Choices'Last) = Value;
   end Has_Choice;

   function Find_Port (Node : Ks_Flow_Node'Class; Name : String;
                       Direction : Port_Direction) return Natural
   is
      All_Ports : constant Port_Array := Node.Ports;
   begin
      for I in All_Ports'Range loop
         if To_String (All_Ports (I).Name) = Name
           and then All_Ports (I).Direction = Direction
         then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Port;

   function Find_Param (Node : Ks_Flow_Node'Class; Name : String)
                        return Natural
   is
      All_Params : constant Param_Array := Node.Params;
   begin
      for I in All_Params'Range loop
         if To_String (All_Params (I).Name) = Name then
            return I;
         end if;
      end loop;
      return 0;
   end Find_Param;

   function Range_Text (Param : Param_Descriptor) return String is
     ("[" & AMV.Flow.JSON.Number_Image (Param.Low) & ", "
      & AMV.Flow.JSON.Number_Image (Param.High) & "]");

   procedure Set_Param_Checked
     (Node  : in out Ks_Flow_Node'Class;
      Name  : String;
      Value : AMV.Flow.Values.Ks_Flow_Value)
   is
      use AMV.Flow.Values;
      Index : constant Natural := Find_Param (Node, Name);

      procedure Fail (Why : String) with No_Return;
      procedure Fail (Why : String) is
      begin
         raise Ks_Flow_Exception with
           Node.Kind_Id & " parameter " & Name & ": " & Why;
      end Fail;
   begin
      if Index = 0 then
         raise Ks_Flow_Exception with
           Node.Kind_Id & " has no parameter """ & Name & """";
      end if;
      if not Value.Has_Value then
         Fail ("no value");
      end if;
      declare
         Param : constant Param_Descriptor := Node.Params (Index);
      begin
         case Param.Kind is
            when Real_Param =>
               if Value.Kind not in Real_Type | Integer_Type then
                  Fail ("a number is needed");
               elsif Value.As_Real not in Param.Low .. Param.High then
                  Fail ("must be in " & Range_Text (Param));
               end if;
               Node.Set_Param (Name, From_Real (Value.As_Real));
               return;
            when Integer_Param =>
               if Value.Kind = Real_Type then
                  declare
                     X : constant Real := Value.As_Real;
                  begin
                     if X /= Real'Floor (X) or else abs X > 1.0E15 then
                        Fail ("a whole number is needed");
                     end if;
                     if X not in Param.Low .. Param.High then
                        Fail ("must be in " & Range_Text (Param));
                     end if;
                     Node.Set_Param
                       (Name, From_Integer (Long_Long_Integer (X)));
                     return;
                  end;
               elsif Value.Kind /= Integer_Type then
                  Fail ("a whole number is needed");
               elsif Real (Value.As_Integer) not in Param.Low .. Param.High
               then
                  Fail ("must be in " & Range_Text (Param));
               end if;
            when Boolean_Param =>
               if Value.Kind /= Boolean_Type then
                  Fail ("true or false is needed");
               end if;
            when Choice_Param =>
               if Value.Kind /= String_Type
                 or else not Has_Choice (Param, Value.As_String)
               then
                  Fail ("must be one of " & To_String (Param.Choices));
               end if;
            when String_Param =>
               if Value.Kind /= String_Type then
                  Fail ("a string is needed");
               end if;
            when Shape_Param =>
               if Value.Kind /= Shape_Type then
                  Fail ("a shape is needed");
               end if;
         end case;
      end;
      Node.Set_Param (Name, Value);
   end Set_Param_Checked;

   procedure Reset_Status (Node : in out Ks_Flow_Node'Class) is
   begin
      Node.State := Not_Run;
      Node.Result := AMV.Tools.Accept_Result;
      Node.Message := Null_Unbounded_String;
      Node.Time_Ms := 0.0;
   end Reset_Status;

   procedure Run (Node : in out Ks_Flow_Node'Class) is
      use Ada.Real_Time;
      Start : constant Time := Clock;
   begin
      Reset_Status (Node);
      begin
         Node.Execute;
      exception
         when E : others =>
            Node.Result := AMV.Tools.Error;
            Node.Message := U
              (if Ada.Exceptions.Exception_Message (E) = ""
               then Ada.Exceptions.Exception_Name (E)
               else Ada.Exceptions.Exception_Message (E));
      end;
      Node.State := Ran;
      Node.Time_Ms := Real (To_Duration (Clock - Start)) * 1000.0;
   end Run;

   procedure Skip (Node : in out Ks_Flow_Node'Class; Reason : String) is
   begin
      Reset_Status (Node);
      Node.State := Skipped;
      Node.Message := U (Reason);
   end Skip;

   procedure Set_Result (Node    : in out Ks_Flow_Node'Class;
                         Result  : AMV.Tools.Ks_Tool_Result_Constants;
                         Message : String := "") is
   begin
      Node.Result := Result;
      Node.Message := U (Message);
   end Set_Result;

   procedure Take_Status (Node   : in out Ks_Flow_Node'Class;
                          Status : AMV.Tools.Ks_Run_Status) is
   begin
      Set_Result (Node, AMV.Tools.Result (Status), AMV.Tools.Message (Status));
   end Take_Status;

   function State (Node : Ks_Flow_Node'Class) return Node_State is
     (Node.State);

   function Result (Node : Ks_Flow_Node'Class)
                    return AMV.Tools.Ks_Tool_Result_Constants is
     (Node.Result);

   function Message (Node : Ks_Flow_Node'Class) return String is
     (To_String (Node.Message));

   function Time_Ms (Node : Ks_Flow_Node'Class) return Real is
     (Node.Time_Ms);

   function Name (Node : Ks_Flow_Node'Class) return String is
     (To_String (Node.Label));

   procedure Set_Name (Node : in out Ks_Flow_Node'Class; Value : String) is
   begin
      if Value'Length > Max_Name_Length then
         raise Ks_Flow_Exception with
           "a node name has at most" & Max_Name_Length'Image
           & " characters";
      end if;
      Node.Label := U (Value);
   end Set_Name;

   function X (Node : Ks_Flow_Node'Class) return Real is (Node.Pos_X);
   function Y (Node : Ks_Flow_Node'Class) return Real is (Node.Pos_Y);

   procedure Set_Position (Node : in out Ks_Flow_Node'Class; X, Y : Real) is
   begin
      if not X'Valid or else not Y'Valid
        or else abs X > 1.0E9 or else abs Y > 1.0E9
      then
         raise Ks_Flow_Exception with
           "a node position must be finite and within 1.0E9";
      end if;
      Node.Pos_X := X;
      Node.Pos_Y := Y;
   end Set_Position;

   procedure Deallocate is new Ada.Unchecked_Deallocation
     (Ks_Flow_Node'Class, Node_Access);

   procedure Free (Node : in out Node_Access) is
   begin
      Deallocate (Node);
   end Free;

   function Worse (Left, Right : AMV.Tools.Ks_Tool_Result_Constants)
                   return AMV.Tools.Ks_Tool_Result_Constants is
     (if Left > Right then Left else Right);

end AMV.Flow.Nodes;
