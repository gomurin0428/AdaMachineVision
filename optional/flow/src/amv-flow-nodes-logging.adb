pragma SPARK_Mode (Off);

with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Calendar.Time_Zones;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings.Fixed;
with Ada.Text_IO;

with AMV.Flow.Values;

package body AMV.Flow.Nodes.Logging is

   use AMV.Flow.Values;
   use type Ada.Directories.File_Size;

   Max_Columns : constant := 8;

   type Value_Array is array (1 .. Max_Columns) of Ks_Flow_Value;
   type Name_Array is array (1 .. Max_Columns) of Unbounded_String;

   procedure Unknown (Kind, What, Name : String) with No_Return;
   procedure Unknown (Kind, What, Name : String) is
   begin
      raise Ks_Flow_Exception with
        Kind & " has no " & What & " """ & Name & """";
   end Unknown;

   function Is_Absolute (Path : String) return Boolean is
     (Path'Length > 0
      and then (Path (Path'First) in '/' | '\'
                or else (Path'Length >= 2
                         and then Path (Path'First + 1) = ':')));

   --  Text as one CSV cell: quoted when it holds a comma, a quote or a
   --  line break, with its quotes doubled.
   function Cell (Text : String) return String is
      Result : Unbounded_String;
      Quote  : Boolean := False;
   begin
      for C of Text loop
         if C in ',' | '"' | ASCII.LF | ASCII.CR then
            Quote := True;
         end if;
         if C = '"' then
            Append (Result, """""");
         else
            Append (Result, C);
         end if;
      end loop;
      return (if Quote then """" & To_String (Result) & """"
              else To_String (Result));
   end Cell;

   function Port_Name (I : Positive) return String is
     ("Value" & Ada.Strings.Fixed.Trim (I'Image, Ada.Strings.Left));

   ---------------------------------------------------------------------
   --  CsvLog
   ---------------------------------------------------------------------

   type Csv_Log_Node is new Ks_Flow_Node with record
      Path     : Unbounded_String := To_Unbounded_String ("log.csv");
      Columns  : Unbounded_String;
      Names    : Name_Array;
      Count    : Positive := Max_Columns;  --  cells after the time
      Enabled  : Boolean := True;
      Base     : Unbounded_String;
      Values   : Value_Array;
      Done     : Boolean := False;
      Rows     : Natural := 0;
   end record;

   overriding function Kind_Id (Node : Csv_Log_Node) return String;
   overriding function Ports (Node : Csv_Log_Node) return Port_Array;
   overriding function Params (Node : Csv_Log_Node) return Param_Array;
   overriding procedure Set_Param
     (Node : in out Csv_Log_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Csv_Log_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Csv_Log_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Csv_Log_Node);
   overriding procedure Prepare
     (Node : in out Csv_Log_Node; Base_Directory : String);
   overriding procedure Execute (Node : in out Csv_Log_Node);
   overriding function Get_Output
     (Node : Csv_Log_Node; Port : String) return Ks_Flow_Value;

   overriding function Kind_Id (Node : Csv_Log_Node) return String is
     ("CsvLog");

   overriding function Ports (Node : Csv_Log_Node) return Port_Array is
      Result : Port_Array (1 .. Max_Columns + 1);
   begin
      for I in 1 .. Max_Columns loop
         Result (I) := In_Port (Port_Name (I), Any_Type, Required => False,
                                Help => "a value to log (any type)");
      end loop;
      Result (Result'Last) :=
        Out_Port ("Rows", Integer_Type,
                  "the rows written since the flow was loaded");
      return Result;
   end Ports;

   overriding function Params (Node : Csv_Log_Node) return Param_Array is
     [String_Param_Of ("Path",
                       "the CSV file, relative to the flow file's folder"),
      String_Param_Of ("Columns",
                       "names for Value1, Value2, ... separated by commas "
                       & "(at most 8); none: Value1 .. Value8"),
      Boolean_Param_Of ("Enabled", "off: the runs are not logged")];

   procedure Set_Columns (Node : in out Csv_Log_Node; Text : String) is
      Names : Name_Array;
      Count : Natural := 0;
      First : Positive := Text'First;
   begin
      if Ada.Strings.Fixed.Trim (Text, Ada.Strings.Both) = "" then
         for I in Names'Range loop
            Names (I) := To_Unbounded_String (Port_Name (I));
         end loop;
         Count := Max_Columns;
      else
         loop
            declare
               Comma : constant Natural :=
                 Ada.Strings.Fixed.Index (Text (First .. Text'Last), ",");
               Last  : constant Natural :=
                 (if Comma = 0 then Text'Last else Comma - 1);
            begin
               Count := Count + 1;
               if Count > Max_Columns then
                  raise Ks_Flow_Exception with
                    "CsvLog parameter Columns: at most"
                    & Max_Columns'Image & " names";
               end if;
               Names (Count) := To_Unbounded_String
                 (Ada.Strings.Fixed.Trim (Text (First .. Last),
                                          Ada.Strings.Both));
               exit when Comma = 0;
               First := Comma + 1;
            end;
         end loop;
      end if;
      Node.Names := Names;
      Node.Count := Count;
      Node.Columns := To_Unbounded_String (Text);
   end Set_Columns;

   overriding procedure Set_Param
     (Node : in out Csv_Log_Node; Name : String; Value : Ks_Flow_Value) is
   begin
      if Name = "Path" then
         if Value.As_String = "" then
            raise Ks_Flow_Exception with "CsvLog parameter Path: a file name "
              & "is needed";
         end if;
         Node.Path := To_Unbounded_String (Value.As_String);
      elsif Name = "Columns" then
         Set_Columns (Node, Value.As_String);
      elsif Name = "Enabled" then
         Node.Enabled := Value.As_Boolean;
      else
         Unknown ("CsvLog", "parameter", Name);
      end if;
   end Set_Param;

   overriding function Get_Param
     (Node : Csv_Log_Node; Name : String) return Ks_Flow_Value is
   begin
      if Name = "Path" then
         return From_String (To_String (Node.Path));
      elsif Name = "Columns" then
         return From_String (To_String (Node.Columns));
      elsif Name = "Enabled" then
         return From_Boolean (Node.Enabled);
      end if;
      Unknown ("CsvLog", "parameter", Name);
   end Get_Param;

   overriding procedure Set_Input
     (Node : in out Csv_Log_Node; Port : String; Value : Ks_Flow_Value) is
   begin
      for I in 1 .. Max_Columns loop
         if Port = Port_Name (I) then
            Node.Values (I) := Value;
            return;
         end if;
      end loop;
      Unknown ("CsvLog", "input", Port);
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Csv_Log_Node) is
   begin
      Node.Values := [others => No_Value];
      Node.Done := False;
   end Clear_Inputs;

   overriding procedure Prepare
     (Node : in out Csv_Log_Node; Base_Directory : String) is
   begin
      Node.Base := To_Unbounded_String (Base_Directory);
   end Prepare;

   overriding procedure Execute (Node : in out Csv_Log_Node) is
      use Ada.Text_IO;
      Name : constant String := To_String (Node.Path);
      Full : constant String :=
        (if Is_Absolute (Name) or else Length (Node.Base) = 0 then Name
         else To_String (Node.Base) & "/" & Name);
      Now  : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      File : File_Type;
      Line : Unbounded_String;
   begin
      Node.Done := True;
      if not Node.Enabled then
         return;
      end if;
      declare
         Folder : constant String := Ada.Directories.Containing_Directory
           (Ada.Directories.Full_Name (Full));
      begin
         if not Ada.Directories.Exists (Folder) then
            Ada.Directories.Create_Path (Folder);
         end if;
      end;
      if Ada.Directories.Exists (Full) then
         Open (File, Append_File, Full);
      else
         Create (File, Out_File, Full);
      end if;
      if Ada.Directories.Size (Full) = 0 then
         Line := To_Unbounded_String ("time");
         for I in 1 .. Node.Count loop
            Append (Line, "," & Cell (To_String (Node.Names (I))));
         end loop;
         Put_Line (File, To_String (Line));
      end if;
      Line := To_Unbounded_String
        (Ada.Calendar.Formatting.Image
           (Now, Include_Time_Fraction => True,
            Time_Zone => Ada.Calendar.Time_Zones.UTC_Time_Offset (Now)));
      for I in 1 .. Node.Count loop
         Append (Line, "," & Cell (Node.Values (I).Image));
      end loop;
      Put_Line (File, To_String (Line));
      Close (File);
      Node.Rows := Node.Rows + 1;
   exception
      when E : Ada.Text_IO.Name_Error | Ada.Text_IO.Use_Error
             | Ada.Directories.Name_Error | Ada.Directories.Use_Error =>
         if Is_Open (File) then
            Close (File);
         end if;
         Set_Result (Node, AMV.Tools.Error,
                     "cannot write " & Full & ": "
                     & Ada.Exceptions.Exception_Message (E));
      when others =>
         --  A full disk, a time zone that cannot be read: the file must not
         --  stay open (Run reports the error).
         if Is_Open (File) then
            Close (File);
         end if;
         raise;
   end Execute;

   overriding function Get_Output
     (Node : Csv_Log_Node; Port : String) return Ks_Flow_Value is
   begin
      if Port = "Rows" then
         return (if Node.Done
                 then From_Integer (Long_Long_Integer (Node.Rows))
                 else No_Value);
      end if;
      Unknown ("CsvLog", "output", Port);
   end Get_Output;

   function Create_Csv_Log return Node_Access is
      Node : constant Node_Access := new Csv_Log_Node;
   begin
      Set_Columns (Csv_Log_Node (Node.all), "");
      return Node;
   end Create_Csv_Log;

end AMV.Flow.Nodes.Logging;
