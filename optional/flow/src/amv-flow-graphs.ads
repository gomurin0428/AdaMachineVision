pragma SPARK_Mode (Off);

with Ada.Containers.Indefinite_Vectors;
with Ada.Finalization;

with AMV.Flow.Nodes;
with AMV.Flow.Values;
with AMV.Tools;

private with Ada.Containers.Ordered_Maps;
private with Ada.Containers.Vectors;
private with Ada.Strings.Unbounded;

--  The flow: nodes (by id), links from output ports to input ports, and
--  the flow's own inputs and outputs (docs/FLOW_EDITOR_DESIGN.md 3 and 4).
--
--  Links are written as endpoints "<node id>.<port>", "input.<name>" (a
--  flow input, as a source) and "output.<name>" (a flow output, as a
--  destination). An output port may feed any number of inputs; an input
--  port or a flow output takes one link.
--
--  Run sets the flow inputs on the nodes they feed, then runs the nodes in
--  topological order (among nodes that do not depend on one another, by
--  ascending id). A node whose source did not run or failed with Error,
--  or whose required input got no value, is skipped. The flow's result is
--  the worst result of the nodes that ran (Error > Reject > Warning >
--  Accept), and at least Reject when a node was skipped.

package AMV.Flow.Graphs is

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Positive, String);

   type Ks_Flow is new Ada.Finalization.Limited_Controlled with private;
   --  An empty flow; it owns its nodes.

   procedure Clear (Flow : in out Ks_Flow);

   function Name (Flow : Ks_Flow) return String;
   procedure Set_Name (Flow : in out Ks_Flow; Value : String);

   function Base_Directory (Flow : Ks_Flow) return String;
   procedure Set_Base_Directory (Flow : in out Ks_Flow; Value : String);
   --  Where relative paths in parameters are taken from ("" by default,
   --  the current directory; Load sets the flow file's directory).

   ---------------------------------------------------------------------
   --  Flow inputs and outputs
   ---------------------------------------------------------------------

   procedure Add_Input (Flow : in out Ks_Flow; Name : String;
                        Value_Type : Ks_Flow_Value_Type);
   procedure Add_Output (Flow : in out Ks_Flow; Name : String;
                         Value_Type : Ks_Flow_Value_Type);
   --  Ks_Flow_Exception for a name that is not valid or already taken.

   function Input_Count (Flow : Ks_Flow) return Natural;
   function Input_Name (Flow : Ks_Flow; Index : Positive) return String;
   function Input_Type (Flow : Ks_Flow; Index : Positive)
                        return Ks_Flow_Value_Type;
   function Output_Count (Flow : Ks_Flow) return Natural;
   function Output_Name (Flow : Ks_Flow; Index : Positive) return String;
   function Output_Type (Flow : Ks_Flow; Index : Positive)
                         return Ks_Flow_Value_Type;

   ---------------------------------------------------------------------
   --  Nodes
   ---------------------------------------------------------------------

   Max_Node_Id : constant := 1_000_000_000;

   function Add_Node (Flow : in out Ks_Flow; Kind : String;
                      Id   : Natural := 0) return Positive;
   --  Adds a node of the kind (AMV.Flow.Kinds) with the id (0: one more
   --  than the largest id) and returns its id. Ks_Flow_Exception for an
   --  unknown kind, an id taken or above Max_Node_Id.

   procedure Remove_Node (Flow : in out Ks_Flow; Id : Positive);
   --  Removes the node and its links.

   function Node_Count (Flow : Ks_Flow) return Natural;
   function Node_Id_At (Flow : Ks_Flow; Index : Positive) return Positive;
   --  The ids in ascending order.

   function Contains (Flow : Ks_Flow; Id : Positive) return Boolean;

   function Node (Flow : Ks_Flow; Id : Positive)
                  return AMV.Flow.Nodes.Node_Access;
   --  The node itself, owned by the flow (for its status, name and
   --  position; set parameters with Set_Param). Ks_Flow_Exception for an
   --  unknown id.

   procedure Set_Param (Flow  : in out Ks_Flow;
                        Id    : Positive;
                        Name  : String;
                        Value : AMV.Flow.Values.Ks_Flow_Value);
   --  Sets a parameter (AMV.Flow.Nodes.Set_Param_Checked) and prepares the
   --  node again (a ShapeMatch retrains). When the node cannot be prepared
   --  with the new value, the old one is put back and the exception goes
   --  on.

   procedure Set_Param_JSON (Flow       : in out Ks_Flow;
                             Id         : Positive;
                             Name       : String;
                             Value_JSON : String);
   --  Set_Param with the value written in JSON as in a flow file (a
   --  number, true / false, a string or a shape object).

   procedure Prepare (Flow : in out Ks_Flow);
   --  Prepares every node (AMV.Flow.Nodes.Prepare) with Base_Directory. A
   --  node that cannot be prepared (a train image that cannot be read)
   --  does not raise: why is one of the flow's Problems until a parameter
   --  of the node is set again.

   ---------------------------------------------------------------------
   --  Links
   ---------------------------------------------------------------------

   procedure Link (Flow : in out Ks_Flow; From, To : String);
   --  Links the endpoint From to the endpoint To. Ks_Flow_Exception for an
   --  endpoint that does not exist, ports whose types cannot be linked
   --  (AMV.Flow.Can_Link), a destination that already has a link, or a
   --  link that would close a cycle.

   procedure Unlink (Flow : in out Ks_Flow; To : String);
   --  Removes the link into To (nothing when there is none).

   function Link_Count (Flow : Ks_Flow) return Natural;
   function Link_From (Flow : Ks_Flow; Index : Positive) return String;
   function Link_To (Flow : Ks_Flow; Index : Positive) return String;

   ---------------------------------------------------------------------
   --  Checking and running
   ---------------------------------------------------------------------

   function Problems (Flow : Ks_Flow) return String_Vectors.Vector;
   --  What keeps the flow from running: bad links, a cycle, a required
   --  input or a flow output without a link, a node's own problem
   --  ("node 1 (ShapeMatch): the pattern is not trained"). Empty when it
   --  can run.

   procedure Check (Flow : Ks_Flow);
   --  Ks_Flow_Exception with the problems (joined by "; ") when there are
   --  any.

   procedure Set_Input (Flow  : in out Ks_Flow;
                        Name  : String;
                        Value : AMV.Flow.Values.Ks_Flow_Value);
   --  Ks_Flow_Exception for an unknown input or a value of another type.

   procedure Run (Flow : in out Ks_Flow);
   --  Check, then runs the nodes (see the top of this package).
   --  Ks_Flow_Exception for a flow that does not pass Check or a linked
   --  flow input without a value; the last run's results are then gone,
   --  Result is Error and Message says why. Node failures are not
   --  exceptions: they are in the nodes' statuses, Result and Message.

   type Run_Counts is record
      Runs     : Natural := 0;
      Accepted : Natural := 0;
      Warned   : Natural := 0;
      Rejected : Natural := 0;
      Failed   : Natural := 0;  --  Error, or a run that could not start
   end record;

   function Counts (Flow : Ks_Flow) return Run_Counts;
   procedure Reset_Counts (Flow : in out Ks_Flow);
   --  The runs since the flow was made, loaded from a file or its counts
   --  reset, by result: a pass / fail tally. From_JSON keeps them (an
   --  editor's undo is not a new flow); Load starts again from zero.

   function Result (Flow : Ks_Flow) return AMV.Tools.Ks_Tool_Result_Constants;
   function Message (Flow : Ks_Flow) return String;
   --  After Run: the first node, in run order, with the flow's result
   --  (the worst of the nodes', a skip counting as a reject), "node 3
   --  (Caliper): no edge found"; "" when all accepted.

   function Get_Output (Flow : Ks_Flow; Name : String)
                        return AMV.Flow.Values.Ks_Flow_Value;
   --  After Run: the value of a flow output (No_Value when its source did
   --  not give one).

   function Value_Into (Flow : Ks_Flow; Id : Positive; Port : String)
                        return AMV.Flow.Values.Ks_Flow_Value;
   --  What the link into the node's input port carries now: after a run,
   --  what the node took. No_Value when the port has no link or its source
   --  gave nothing.

   ---------------------------------------------------------------------
   --  Flow files (docs/FLOW_EDITOR_DESIGN.md 5)
   ---------------------------------------------------------------------

   Format : constant := 1;

   function To_JSON (Flow : Ks_Flow) return String;
   --  The flow as the text of a flow file.

   procedure From_JSON (Flow           : in out Ks_Flow;
                        Text           : String;
                        Base_Directory : String := "");
   --  Replaces the flow with the one in Text and prepares its nodes.
   --  Ks_Flow_Exception for anything that is not a valid flow (the message
   --  says where); the flow is then left as it was.

   function Recipe_JSON (Flow : Ks_Flow; Name : String) return String;
   --  A recipe: the value of every parameter of every node, to switch the
   --  flow from one product to another without changing its nodes:
   --  {"format": 1, "recipe": Name, "flow": the flow's name,
   --   "params": {"<node id>.<parameter>": value, ...}}, null for a
   --  parameter without a value (a region: none). A file parameter (a
   --  train image, a log) is written as an absolute path, so that the
   --  recipe names the same file after the flow is saved elsewhere.

   procedure Apply_Recipe (Flow : in out Ks_Flow; Text : String);
   --  Sets the parameters a recipe names (others keep their values), on a
   --  copy of the flow whose nodes are prepared once, the touched ones
   --  with all their new values; the flow is replaced only when all of that works
   --  (its inputs keep their values, its counts stay, the last run's
   --  results are gone). Otherwise Ks_Flow_Exception, and the flow is as
   --  it was: a recipe for another flow (by name), a node or parameter
   --  the flow does not have, a value a node cannot take or prepare with,
   --  a node it did not touch that worked and cannot be prepared again.

   procedure Save (Flow : Ks_Flow; Path : String);
   procedure Load (Flow : in out Ks_Flow; Path : String);
   --  Load sets Base_Directory to the file's directory. Ks_Flow_Exception
   --  for a file that cannot be read or written.

private

   use Ada.Strings.Unbounded;

   type Endpoint is record
      Node : Natural := 0;  --  0: the flow's input (source) or output
      Port : Unbounded_String;
   end record;

   type Link_Record is record
      From, To : Endpoint;
   end record;

   package Link_Vectors is new Ada.Containers.Vectors (Positive, Link_Record);

   package Node_Maps is new Ada.Containers.Ordered_Maps
     (Positive, AMV.Flow.Nodes.Node_Access, "=" => AMV.Flow.Nodes."=");

   type Interface_Port is record
      Name       : Unbounded_String;
      Value_Type : Ks_Flow_Value_Type := Real_Type;
      Value      : AMV.Flow.Values.Ks_Flow_Value;
   end record;

   package Interface_Vectors is new Ada.Containers.Vectors
     (Positive, Interface_Port);

   package Message_Maps is new Ada.Containers.Ordered_Maps
     (Positive, Unbounded_String);
   --  By node id: why the node could not be prepared.

   type Ks_Flow is new Ada.Finalization.Limited_Controlled with record
      Flow_Name : Unbounded_String;
      Base_Dir  : Unbounded_String;
      Nodes     : Node_Maps.Map;
      Links     : Link_Vectors.Vector;
      Inputs    : Interface_Vectors.Vector;
      Outputs   : Interface_Vectors.Vector;
      Outcome   : AMV.Tools.Ks_Tool_Result_Constants := AMV.Tools.Accept_Result;
      Why       : Unbounded_String;
      Unprepared : Message_Maps.Map;
      Tally     : Run_Counts;
   end record;

   overriding procedure Finalize (Flow : in out Ks_Flow);

end AMV.Flow.Graphs;
