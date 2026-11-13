pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Exceptions;
with Ada.Real_Time;

package body AMV.Tools is

   use Ada.Strings.Unbounded;

   ---------------------------------------------------------------------
   --  Ks_Run_Status
   ---------------------------------------------------------------------

   function Result (Status : Ks_Run_Status) return Ks_Tool_Result_Constants
   is (Status.Result);

   function Message (Status : Ks_Run_Status) return String is
     (To_String (Status.Message));

   function Exception_Name (Status : Ks_Run_Status) return String is
     (To_String (Status.Exception_Name));

   function Processing_Time (Status : Ks_Run_Status) return Real is
     (Status.Processing_Time);

   ---------------------------------------------------------------------
   --  Ks_Tool
   ---------------------------------------------------------------------

   function Name (Tool : Ks_Tool) return String is (To_String (Tool.Name));

   procedure Set_Name (Tool : in out Ks_Tool; Value : String) is
   begin
      Tool.Name := To_Unbounded_String (Value);
   end Set_Name;

   function Run_Status (Tool : Ks_Tool'Class) return Ks_Run_Status is
     (Tool.Status);

   procedure Record_Failure
     (Tool       : in out Ks_Tool'Class;
      Occurrence : Ada.Exceptions.Exception_Occurrence);
   --  Turns an exception that escaped the tool into an Error status.

   procedure Record_Failure
     (Tool       : in out Ks_Tool'Class;
      Occurrence : Ada.Exceptions.Exception_Occurrence)
   is
      Id_Name : constant String := Ada.Exceptions.Exception_Name (Occurrence);
      Text    : constant String :=
        Ada.Exceptions.Exception_Message (Occurrence);
   begin
      Tool.Status.Result := Error;
      Tool.Status.Exception_Name := To_Unbounded_String (Id_Name);
      if Text = "" then
         Tool.Status.Message := To_Unbounded_String (Id_Name);
      else
         Tool.Status.Message := To_Unbounded_String (Text);
      end if;
   end Record_Failure;

   function Milliseconds_Since (Start : Ada.Real_Time.Time) return Real;

   function Milliseconds_Since (Start : Ada.Real_Time.Time) return Real is
      use type Ada.Real_Time.Time;
      --  Run records the elapsed time itself (docs/DESIGN.md 9.3).
      Now     : constant Ada.Real_Time.Time := Ada.Real_Time.Clock;
      Elapsed : constant Duration :=
        Ada.Real_Time.To_Duration (Now - Start);  --  SHELL: run time
   begin
      return Real (Elapsed) * 1000.0;  --  SHELL: run time in milliseconds
   end Milliseconds_Since;

   procedure Run (Tool : in out Ks_Tool'Class) is
      Start : Ada.Real_Time.Time := Ada.Real_Time.Time_First;
   begin
      Tool.Status := (others => <>);
      Start := Ada.Real_Time.Clock;

      begin
         Tool.Reset_Results;
         Tool.Execute;
      exception
         when Occurrence : others =>
            Record_Failure (Tool, Occurrence);
            --  Leave no partial results behind. A failure here must not
            --  hide the original one, nor escape Run.
            begin
               Tool.Reset_Results;
            exception
               when others =>
                  null;
            end;
      end;

      Tool.Status.Processing_Time := Milliseconds_Since (Start);

   exception
      when others =>
         --  Last line of defence (for example Storage_Error while recording
         --  the failure): report Error with whatever could be recorded and
         --  never propagate.
         Tool.Status.Result := Error;
         begin
            Tool.Status.Processing_Time := Milliseconds_Since (Start);
         exception
            when others =>
               null;
         end;
   end Run;

   procedure Set_Result
     (Tool    : in out Ks_Tool'Class;
      Result  : Ks_Tool_Result_Constants;
      Message : String := "") is
   begin
      Tool.Status.Result := Result;
      Tool.Status.Message := To_Unbounded_String (Message);
      Tool.Status.Exception_Name := Null_Unbounded_String;
   end Set_Result;

end AMV.Tools;
