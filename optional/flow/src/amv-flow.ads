pragma SPARK_Mode (Off);

--  AMV Flow: AMV tools as nodes whose ports are linked into a flow that
--  can be checked, run, saved and loaded without writing code
--  (docs/FLOW_EDITOR_DESIGN.md).
--
--     AMV.Flow.JSON    the JSON reader and writer of the flow files
--     AMV.Flow.Values  the values that ports and parameters hold
--     AMV.Flow.Nodes   the node interface: ports, parameters, Run
--     AMV.Flow.Kinds   the node kinds by name (AMV.Flow.Nodes.Vision, ...)
--     AMV.Flow.Graphs  the flow: nodes, links, checks, Run, files
--
--  This layer is outside the proved library: it is plain Ada over the
--  AMV Ada API.

package AMV.Flow is

   Ks_Flow_Exception : exception;
   --  A flow or a flow file that is not valid: malformed JSON, an unknown
   --  node kind, port or parameter, a link between ports of different
   --  types, a cycle, an input without a value. The message says what and
   --  where.

   type Ks_Flow_Value_Type is
     (Real_Type, Integer_Type, Boolean_Type, String_Type,
      Image_8_Grey_Type, Transform_Type, Shape_Type);
   --  The type of a port or of a flow input or output.

   function Type_Name (Value_Type : Ks_Flow_Value_Type) return String;
   --  "Real", "Integer", "Boolean", "String", "Image_8_Grey", "Transform",
   --  "Shape": the names used in flow files.

   function Type_Of (Name : String) return Ks_Flow_Value_Type;
   --  The type named Name (as Type_Name gives it); Ks_Flow_Exception for
   --  another name.

   function Can_Link (From, To : Ks_Flow_Value_Type) return Boolean is
     (From = To or else (From = Integer_Type and then To = Real_Type));
   --  Whether an output of type From may feed an input of type To: the
   --  same type, or an integer into a real.

   Max_Name_Length : constant := 64;
   --  The longest name of a flow, node, port or flow input or output.

   function Valid_Name (Name : String) return Boolean;
   --  1 .. Max_Name_Length characters, none of them '.', a control
   --  character or a quote: names appear in link endpoints ("3.Width").

end AMV.Flow;
