--  amv_flow: runs AMV flow files (docs/FLOW_EDITOR_DESIGN.md) without a
--  GUI.
--
--     amv_flow kinds                 the node kinds, their ports and
--                                    parameters
--     amv_flow check FLOW            the flow's problems (none: exit 0)
--     amv_flow run FLOW IMAGE...     runs the flow on each image and
--                                    prints one CSV line per image
--     amv_flow run --images DIR FLOW IMAGE...
--                                    also writes the image each node
--                                    made into DIR, as
--                                    <image name>_node<id>.bmp
--
--  For run, the flow has exactly one input of type Image_8_Grey; the CSV
--  columns are the image, the result (accept, warning, reject, error),
--  the message and the flow's outputs. Exit status: 0 when every image
--  was accepted (or warned), 1 when one was rejected or failed, 2 for a
--  usage error or a flow that cannot be loaded or run.

with Ada.Command_Line;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Strings;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AMV;
with AMV.Flow;
with AMV.Flow.Graphs;
with AMV.Flow.Kinds;
with AMV.Flow.Nodes;
with AMV.Flow.Values;
with AMV.Image_File;
with AMV.Tools;

procedure AMV_Flow is

   use Ada.Text_IO;
   use type AMV.Tools.Ks_Tool_Result_Constants;
   use type AMV.Flow.Ks_Flow_Value_Type;

   package CL renames Ada.Command_Line;

   Usage_Status : constant CL.Exit_Status := 2;

   procedure Usage is
   begin
      Put_Line (Standard_Error, "usage: amv_flow kinds");
      Put_Line (Standard_Error, "       amv_flow check FLOW");
      Put_Line (Standard_Error, "       amv_flow run [--images DIR] FLOW IMAGE...");
      CL.Set_Exit_Status (Usage_Status);
   end Usage;

   function CSV (Text : String) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
      Quote  : Boolean := False;
   begin
      for C of Text loop
         if C in ',' | '"' | ASCII.LF | ASCII.CR then
            Quote := True;
         end if;
         if C = '"' then
            Ada.Strings.Unbounded.Append (Result, """""");
         else
            Ada.Strings.Unbounded.Append (Result, C);
         end if;
      end loop;
      return (if Quote then """" & Ada.Strings.Unbounded.To_String (Result)
                            & """"
              else Ada.Strings.Unbounded.To_String (Result));
   end CSV;

   function Result_Name (R : AMV.Tools.Ks_Tool_Result_Constants)
                         return String is
     (case R is
         when AMV.Tools.Accept_Result => "accept",
         when AMV.Tools.Warning       => "warning",
         when AMV.Tools.Reject        => "reject",
         when AMV.Tools.Error         => "error");

   procedure List_Kinds is
      use AMV.Flow.Nodes;
      use Ada.Strings.Unbounded;
   begin
      for K in 1 .. AMV.Flow.Kinds.Count loop
         declare
            N : Node_Access := AMV.Flow.Kinds.Create (AMV.Flow.Kinds.Kind_Id (K));
         begin
            Put_Line (N.Kind_Id);
            for P of N.Ports loop
               Put_Line ("  " & (if P.Direction = Input then "in   " else "out  ")
                         & To_String (P.Name) & " : "
                         & AMV.Flow.Type_Name (P.Value_Type)
                         & (if P.Direction = Input and then not P.Required
                            then " (optional)" else "")
                         & (if Length (P.Help) > 0
                            then "  -- " & To_String (P.Help) else ""));
            end loop;
            for P of N.Params loop
               Put_Line ("  param " & To_String (P.Name) & " : "
                         & (case P.Kind is
                              when Real_Param    => "Real",
                              when Integer_Param => "Integer",
                              when Boolean_Param => "Boolean",
                              when Choice_Param  => To_String (P.Choices),
                              when String_Param  => "String",
                              when Shape_Param   => "Shape")
                         & (if Length (P.Unit) > 0
                            then " [" & To_String (P.Unit) & "]" else "")
                         & (if Length (P.Help) > 0
                            then "  -- " & To_String (P.Help) else ""));
            end loop;
            Free (N);
         end;
      end loop;
   end List_Kinds;

   procedure Check (Path : String) is
      Flow : AMV.Flow.Graphs.Ks_Flow;
   begin
      Flow.Load (Path);
      declare
         Problems : constant AMV.Flow.Graphs.String_Vectors.Vector :=
           Flow.Problems;
      begin
         for P of Problems loop
            Put_Line (P);
         end loop;
         if not Problems.Is_Empty then
            CL.Set_Exit_Status (CL.Failure);
         else
            Put_Line (Path & ": no problems (" & Flow.Node_Count'Image
                      & " nodes," & Flow.Link_Count'Image & " links)");
         end if;
      end;
   end Check;

   --  The output Image of each node that made one, into Dir.
   procedure Write_Node_Images (Flow : AMV.Flow.Graphs.Ks_Flow;
                                Dir, Stem : String) is
      use AMV.Flow.Nodes;
   begin
      for I in 1 .. Flow.Node_Count loop
         declare
            Id   : constant Positive := Flow.Node_Id_At (I);
            Node : constant Node_Access := Flow.Node (Id);
         begin
            if Find_Port (Node.all, "Image", Output) /= 0
              and then Node.State = Ran
            then
               declare
                  Value : constant AMV.Flow.Values.Ks_Flow_Value :=
                    Node.Get_Output ("Image");
               begin
                  if Value.Has_Value then
                     AMV.Image_File.Write_Image
                       (Dir & "/" & Stem & "_node"
                        & Ada.Strings.Fixed.Trim (Id'Image, Ada.Strings.Left)
                        & ".bmp",
                        Value.As_Image);
                  end if;
               end;
            end if;
         end;
      end loop;
   end Write_Node_Images;

   procedure Run (Path : String; First_Image : Positive;
                  Image_Dir : String := "") is
      Flow       : AMV.Flow.Graphs.Ks_Flow;
      Image_Port : Natural := 0;
      All_Good   : Boolean := True;
   begin
      Flow.Load (Path);
      for I in 1 .. Flow.Input_Count loop
         if Flow.Input_Type (I) = AMV.Flow.Image_8_Grey_Type then
            if Image_Port /= 0 then
               raise AMV.Flow.Ks_Flow_Exception with
                 "the flow has more than one image input";
            end if;
            Image_Port := I;
         end if;
      end loop;
      if Image_Port = 0 or else Flow.Input_Count /= 1 then
         raise AMV.Flow.Ks_Flow_Exception with
           "run needs a flow with exactly one input, of type Image_8_Grey";
      end if;
      Flow.Check;

      Put ("image,result,message");
      for O in 1 .. Flow.Output_Count loop
         Put ("," & CSV (Flow.Output_Name (O)));
      end loop;
      New_Line;

      for A in First_Image .. CL.Argument_Count loop
         declare
            Image_Path : constant String := CL.Argument (A);
         begin
            Flow.Set_Input
              (Flow.Input_Name (Image_Port),
               AMV.Flow.Values.From_Image
                 (AMV.Image_File.Read_Image_8_Grey (Image_Path)));
            Flow.Run;
            if Image_Dir /= "" then
               Write_Node_Images (Flow, Image_Dir,
                                  Ada.Directories.Base_Name (Image_Path));
            end if;
            Put (CSV (Image_Path) & "," & Result_Name (Flow.Result) & ","
                 & CSV (Flow.Message));
            for O in 1 .. Flow.Output_Count loop
               Put ("," & CSV (Flow.Get_Output (Flow.Output_Name (O)).Image));
            end loop;
            New_Line;
            if Flow.Result > AMV.Tools.Warning then
               All_Good := False;
            end if;
         exception
            when E : AMV.Ks_Image_File_Exception | AMV.Ks_Exception
                   | AMV.Ks_Bad_Parameter_Exception =>
               Put_Line (CSV (Image_Path) & ",error,"
                         & CSV ("cannot read the image: "
                                & Ada.Exceptions.Exception_Message (E)));
               All_Good := False;
         end;
      end loop;
      if not All_Good then
         CL.Set_Exit_Status (CL.Failure);
      end if;
   end Run;

begin
   if CL.Argument_Count = 1 and then CL.Argument (1) = "kinds" then
      List_Kinds;
   elsif CL.Argument_Count = 2 and then CL.Argument (1) = "check" then
      Check (CL.Argument (2));
   elsif CL.Argument_Count >= 5 and then CL.Argument (1) = "run"
     and then CL.Argument (2) = "--images"
   then
      Run (CL.Argument (4), First_Image => 5, Image_Dir => CL.Argument (3));
   elsif CL.Argument_Count >= 3 and then CL.Argument (1) = "run" then
      Run (CL.Argument (2), First_Image => 3);
   else
      Usage;
   end if;
exception
   when E : AMV.Flow.Ks_Flow_Exception =>
      Put_Line (Standard_Error, "amv_flow: " & Ada.Exceptions.Exception_Message (E));
      CL.Set_Exit_Status (Usage_Status);
end AMV_Flow;
