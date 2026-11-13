with Ada.Command_Line;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AMV.Misc;

package body AMV_Test_Support is

   Current_Section : Ada.Strings.Unbounded.Unbounded_String;
   Check_Count     : Natural := 0;
   Failure_Count   : Natural := 0;

   procedure Section (Name : String) is
   begin
      Current_Section := Ada.Strings.Unbounded.To_Unbounded_String (Name);
   end Section;

   procedure Report_Failure (Description : String) is
   begin
      Failure_Count := Failure_Count + 1;
      Ada.Text_IO.Put_Line
        ("FAIL [" & Ada.Strings.Unbounded.To_String (Current_Section) & "] "
         & Description);
   end Report_Failure;

   procedure Check (Condition : Boolean; Description : String) is
   begin
      Check_Count := Check_Count + 1;
      if not Condition then
         Report_Failure (Description);
      end if;
   end Check;

   procedure Check_Near
     (Actual, Expected : AMV.Real;
      Tolerance        : AMV.Real;
      Description      : String) is
   begin
      Check_Count := Check_Count + 1;
      if not (abs (Actual - Expected) <= Tolerance) then
         Report_Failure
           (Description & ": got" & AMV.Real'Image (Actual) & ", expected"
            & AMV.Real'Image (Expected) & " +/-"
            & AMV.Real'Image (Tolerance));
      end if;
   end Check_Near;

   procedure Check_Angle_Near
     (Actual, Expected : AMV.Real;
      Tolerance        : AMV.Real;
      Description      : String) is
   begin
      Check_Count := Check_Count + 1;
      if not (abs (AMV.Misc.Angle_Difference (Actual, Expected)) <= Tolerance)
      then
         Report_Failure
           (Description & ": got angle" & AMV.Real'Image (Actual)
            & ", expected" & AMV.Real'Image (Expected) & " +/-"
            & AMV.Real'Image (Tolerance));
      end if;
   end Check_Angle_Near;

   procedure Check_Raises (Description : String) is
   begin
      Check_Count := Check_Count + 1;
      begin
         Body_Of_Test;
      exception
         when others =>
            return;
      end;
      Report_Failure (Description & ": no exception raised");
   end Check_Raises;

   procedure Check_Raises_Exactly (Description : String) is
      use type Ada.Exceptions.Exception_Id;
   begin
      Check_Count := Check_Count + 1;
      begin
         Action;
      exception
         when E : others =>
            if Ada.Exceptions.Exception_Identity (E) /= Expected then
               Report_Failure
                 (Description & ": raised "
                  & Ada.Exceptions.Exception_Name (E) & " ("
                  & Ada.Exceptions.Exception_Message (E) & ") instead of "
                  & Ada.Exceptions.Exception_Name (Expected));
            end if;
            return;
      end;
      Report_Failure
        (Description & ": no exception raised (expected "
         & Ada.Exceptions.Exception_Name (Expected) & ")");
   end Check_Raises_Exactly;

   procedure Fail (Description : String) is
   begin
      Check_Count := Check_Count + 1;
      Report_Failure (Description);
   end Fail;

   function Failures return Natural is (Failure_Count);
   function Checks return Natural is (Check_Count);

   procedure Finish is
   begin
      Ada.Text_IO.Put_Line
        (Natural'Image (Check_Count) & " checks,"
         & Natural'Image (Failure_Count) & " failures");
      if Failure_Count > 0 then
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Failure);
      else
         Ada.Command_Line.Set_Exit_Status (Ada.Command_Line.Success);
      end if;
   end Finish;

   procedure Standalone is
   begin
      begin
         Test;
      exception
         when E : others =>
            Fail
              ("unexpected exception "
               & Ada.Exceptions.Exception_Name (E) & ": "
               & Ada.Exceptions.Exception_Message (E));
      end;
      Finish;
   end Standalone;

end AMV_Test_Support;
