pragma SPARK_Mode (Off);

--  Node kinds that record a flow's results. Each Create function
--  returns a new node of its kind (AMV.Flow.Kinds lists them by name).
--
--  CsvLog
--     in   Value1 .. Value8 : Any (optional: link what is to be logged)
--     out  Rows : Integer (the rows it has written since the flow was
--          loaded)
--     params  Path (the CSV file; relative to the flow file's folder),
--             Columns (the names of Value1, Value2, ..., separated by
--             commas: the row has a cell for each; none: Value1 ..
--             Value8), Enabled
--     Each run appends one row: the local time, then each value as the
--     CLI prints it (an empty cell for an input with no value: its
--     source failed or did not run, which does not keep the log from
--     running). A new or empty file gets the header line first; an
--     existing one is appended to as it is. A file that cannot be
--     written is an Error.

package AMV.Flow.Nodes.Logging is

   function Create_Csv_Log return Node_Access;

end AMV.Flow.Nodes.Logging;
