pragma SPARK_Mode (Off);

with AMV.Flow.Nodes.Camera;

package body AMV.Flow.C_API.Extensions is

   procedure Register is
   begin
      AMV.Flow.Nodes.Camera.Register;
   end Register;

end AMV.Flow.C_API.Extensions;
