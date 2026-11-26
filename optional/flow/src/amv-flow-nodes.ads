pragma SPARK_Mode (Off);

with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;

with AMV.Flow.Values;
with AMV.Tools;

--  The node interface. A node kind (AMV.Flow.Nodes.Vision, ...) declares
--  its ports and parameters, takes parameter and input values, runs, and
--  gives output values. The flow (AMV.Flow.Graphs) sets the inputs from
--  the links, calls Run and reads the outputs.

package AMV.Flow.Nodes is

   use Ada.Strings.Unbounded;

   type Port_Direction is (Input, Output);

   type Port_Descriptor is record
      Name       : Unbounded_String;
      Direction  : Port_Direction := Input;
      Value_Type : Ks_Flow_Value_Type := Real_Type;
      Required   : Boolean := True;  --  inputs: Run needs a value
      Help       : Unbounded_String;
   end record;

   type Port_Array is array (Positive range <>) of Port_Descriptor;

   type Param_Kind is
     (Real_Param, Integer_Param, Boolean_Param, Choice_Param, String_Param,
      Shape_Param);
   --  Choice: one of the Choices, held as a string. Shape: a region or
   --  another shape (AMV.Flow.Values, "Shapes in flow files").

   type Param_Descriptor is record
      Name    : Unbounded_String;
      Kind    : Param_Kind := Real_Param;
      Low     : Real := Real'First;  --  Real and Integer: the range
      High    : Real := Real'Last;
      Choices : Unbounded_String;    --  Choice: "A|B|C"
      Unit    : Unbounded_String;    --  "px", "rad", "grey levels", ...
      Help    : Unbounded_String;
      Path    : Boolean := False;    --  String: a file, relative to the
                                     --  flow file's folder unless absolute
   end record;

   type Param_Array is array (Positive range <>) of Param_Descriptor;

   function In_Port (Name : String; Value_Type : Ks_Flow_Value_Type;
                     Required : Boolean := True; Help : String := "")
                     return Port_Descriptor;
   function Out_Port (Name : String; Value_Type : Ks_Flow_Value_Type;
                      Help : String := "") return Port_Descriptor;
   function Real_Param_Of (Name : String; Low, High : Real;
                           Unit : String := ""; Help : String := "")
                           return Param_Descriptor;
   function Integer_Param_Of (Name : String; Low, High : Real;
                              Help : String := "") return Param_Descriptor;
   function Boolean_Param_Of (Name : String; Help : String := "")
                              return Param_Descriptor;
   function Choice_Param_Of (Name, Choices : String; Help : String := "")
                             return Param_Descriptor;
   function String_Param_Of (Name : String; Help : String := "";
                             Path : Boolean := False)
                             return Param_Descriptor;
   function Shape_Param_Of (Name : String; Help : String := "")
                            return Param_Descriptor;
   --  Descriptors, for the kinds' tables.

   function Has_Choice (Param : Param_Descriptor; Value : String)
                        return Boolean;
   --  Whether Value is one of the choices of a Choice parameter.

   type Node_State is (Not_Run, Ran, Skipped);
   --  Skipped: an input it needs had no value (its source failed or did
   --  not run). An optional input (Required False) whose source failed
   --  only has no value: the node runs.

   ---------------------------------------------------------------------
   --  Ks_Flow_Node
   ---------------------------------------------------------------------

   type Ks_Flow_Node is abstract tagged limited private;

   function Kind_Id (Node : Ks_Flow_Node) return String is abstract;
   --  The kind's name in flow files ("ShapeMatch").

   function Ports (Node : Ks_Flow_Node) return Port_Array is abstract;
   function Params (Node : Ks_Flow_Node) return Param_Array is abstract;

   procedure Set_Param (Node  : in out Ks_Flow_Node;
                        Name  : String;
                        Value : AMV.Flow.Values.Ks_Flow_Value) is abstract;
   --  Sets a parameter. Callers go through Set_Param_Checked, which
   --  checks the name, the type, the range and the choices first.

   function Get_Param (Node : Ks_Flow_Node; Name : String)
                       return AMV.Flow.Values.Ks_Flow_Value is abstract;

   procedure Set_Input (Node  : in out Ks_Flow_Node;
                        Port  : String;
                        Value : AMV.Flow.Values.Ks_Flow_Value) is abstract;
   --  Port is one of the node's input ports and Value has its type. Run
   --  calls it for each linked input that has a value, and with No_Value
   --  for a linked optional input whose source gave none (an input that
   --  is not linked gets no call).

   procedure Clear_Inputs (Node : in out Ks_Flow_Node) is abstract;
   --  Forgets the input values and the outputs of the last run (before a
   --  run of the flow).

   procedure Execute (Node : in out Ks_Flow_Node) is abstract;
   --  The node's work. It may raise (Run turns that into Error) and may
   --  call Set_Result. Do not call it directly; call Run.

   function Get_Output (Node : Ks_Flow_Node; Port : String)
                        return AMV.Flow.Values.Ks_Flow_Value is abstract;
   --  The value of an output port after a run; No_Value when the run did
   --  not give it one.

   procedure Prepare (Node : in out Ks_Flow_Node; Base_Directory : String)
   is null;
   --  Called once the parameters are set, before the first run: a node
   --  that trains (ShapeMatch) trains here. Relative paths in parameters
   --  are taken from Base_Directory. May raise Ks_Flow_Exception.

   function Problem (Node : Ks_Flow_Node) return String is ("");
   --  What keeps the node from running ("the pattern is not trained"), or
   --  "".

   type Real_List is array (Positive range <>) of Real;

   type Mark (Count : Natural) is record
      Polygon : Boolean := True;  --  a closed polygon, or a point (Count 1)
      X, Y    : Real_List (1 .. Count);
   end record;

   package Mark_Vectors is new Ada.Containers.Indefinite_Vectors
     (Positive, Mark);

   procedure Add_Pixel_Marks (Node  : Ks_Flow_Node;
                              Marks : in out Mark_Vectors.Vector) is null;
   --  What the node found in its last run, in its input image's pixel
   --  coordinates (the centre of pixel (i, j) at (i, j)), for an editor to
   --  draw: an outline, a centre. A node that adds none gets its X, Y (or
   --  CenterX, CenterY) outputs drawn instead (AMV.Flow.Reports).

   --  Class-wide operations

   procedure Set_Param_Checked
     (Node  : in out Ks_Flow_Node'Class;
      Name  : String;
      Value : AMV.Flow.Values.Ks_Flow_Value);
   --  Checks that Name is a parameter of the node, that Value has its
   --  type (an Integer for a Real parameter is taken), its range or one of
   --  its choices, then Set_Param. Ks_Flow_Exception otherwise, naming the
   --  parameter.

   procedure Run (Node : in out Ks_Flow_Node'Class);
   --  Resets the status, calls Execute and records the time. An exception
   --  from Execute makes the result Error with its message. The state
   --  becomes Ran.

   procedure Skip (Node : in out Ks_Flow_Node'Class; Reason : String);
   --  Marks the node Skipped with Reason (as its message).

   procedure Reset_Status (Node : in out Ks_Flow_Node'Class);
   --  Not_Run, Accept_Result, no message.

   procedure Set_Result (Node    : in out Ks_Flow_Node'Class;
                         Result  : AMV.Tools.Ks_Tool_Result_Constants;
                         Message : String := "");
   --  For use in Execute: report Reject, Warning or Error.

   procedure Take_Status (Node   : in out Ks_Flow_Node'Class;
                          Status : AMV.Tools.Ks_Run_Status);
   --  Set_Result with the result and message of a tool's run status.

   function State (Node : Ks_Flow_Node'Class) return Node_State;
   function Result (Node : Ks_Flow_Node'Class)
                    return AMV.Tools.Ks_Tool_Result_Constants;
   function Message (Node : Ks_Flow_Node'Class) return String;
   function Time_Ms (Node : Ks_Flow_Node'Class) return Real;

   function Find_Port (Node : Ks_Flow_Node'Class; Name : String;
                       Direction : Port_Direction) return Natural;
   --  The index of the port in Ports (Node), or 0.

   function Find_Param (Node : Ks_Flow_Node'Class; Name : String)
                        return Natural;
   --  The index of the parameter in Params (Node), or 0.

   function Name (Node : Ks_Flow_Node'Class) return String;
   procedure Set_Name (Node : in out Ks_Flow_Node'Class; Value : String);
   --  A label shown in the editor; "" by default.

   function X (Node : Ks_Flow_Node'Class) return Real;
   function Y (Node : Ks_Flow_Node'Class) return Real;
   procedure Set_Position (Node : in out Ks_Flow_Node'Class; X, Y : Real);
   --  Where the editor draws the node; not used by Run.

   type Node_Access is access all Ks_Flow_Node'Class;

   procedure Free (Node : in out Node_Access);

   function Worse (Left, Right : AMV.Tools.Ks_Tool_Result_Constants)
                   return AMV.Tools.Ks_Tool_Result_Constants;
   --  The worse of two results: Error > Reject > Warning > Accept_Result.

private

   type Ks_Flow_Node is abstract tagged limited record
      Label   : Unbounded_String;
      Pos_X   : Real := 0.0;
      Pos_Y   : Real := 0.0;
      State   : Node_State := Not_Run;
      Result  : AMV.Tools.Ks_Tool_Result_Constants := AMV.Tools.Accept_Result;
      Message : Unbounded_String;
      Time_Ms : Real := 0.0;
   end record;

end AMV.Flow.Nodes;
