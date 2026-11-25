pragma SPARK_Mode (Off);

--  Node kinds that judge values.
--
--  RangeCheck
--     in   Value : Real
--     out  Pass : Boolean (Low <= Value <= High)
--     params  Low, High
--     Out of range: Pass is False and the result is Reject. Low > High:
--     Error.
--
--  And, Or
--     in   In1 .. In4 : Boolean (optional)
--     out  Out : Boolean (And: every linked input True; Or: one of them)
--     params  Judge (on: Out False is a Reject, so that the node gives the
--             flow's verdict)
--     An input that is not linked does not count; a linked one whose
--     source gave no value (it failed or was skipped) counts as False. No
--     input linked: Error.
--
--  Not
--     in   In : Boolean
--     out  Out : Boolean

package AMV.Flow.Nodes.Logic is

   function Create_Range_Check return Node_Access;
   function Create_And return Node_Access;
   function Create_Or return Node_Access;
   function Create_Not return Node_Access;

end AMV.Flow.Nodes.Logic;
