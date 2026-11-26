pragma SPARK_Mode (Off);

--  Node kinds beyond the engine's own, registered when the library loads.
--  The body comes from no_camera/ (amv_flow_c.gpr: nothing) or camera/
--  (amv_flow_c_camera.gpr: the Camera node, which needs Aravis).
private package AMV.Flow.C_API.Extensions is

   procedure Register;

end AMV.Flow.C_API.Extensions;
