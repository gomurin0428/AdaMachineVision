pragma SPARK_Mode (Off);

--  Node kinds that judge values.
--
--  RangeCheck
--     in   Value : Real
--     out  Pass : Boolean (Low <= Value <= High)
--     params  Low, High
--     Out of range: Pass is False and the result is Reject. Low > High:
--     Error.

package AMV.Flow.Nodes.Logic is

   function Create_Range_Check return Node_Access;

end AMV.Flow.Nodes.Logic;
