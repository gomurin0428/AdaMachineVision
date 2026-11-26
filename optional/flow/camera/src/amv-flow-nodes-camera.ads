pragma SPARK_Mode (Off);

--  The Camera node: the newest frame of a GigE Vision camera
--  (AMV.GigE_Vision, optional/aravis) at each run of the flow. It is
--  built apart from the engine (optional/flow/camera, amv_flow_camera.gpr)
--  because it needs Aravis; Register adds it to AMV.Flow.Kinds.
--
--  Camera
--     out  Image : Image_8_Grey (Mono8, or Bayer8 converted to grey);
--          ExposureUs, Gain : Real (as read back from the camera)
--     params  CameraId (an IPv4 address or an Aravis device ID),
--             ExposureUs (0: leave the camera's), Gain (negative: leave
--             the camera's), AutoExposure, TimeoutMs
--
--  The camera is opened at the first run and stays open, streaming,
--  until the node is removed or CameraId changes; changed settings are
--  sent at the next run. Each run takes the newest complete frame (frames
--  queued since the last run are dropped). No frame within TimeoutMs, or
--  a camera that cannot be opened, is an Error with the reason; a setting
--  the camera refuses is a Warning.

package AMV.Flow.Nodes.Camera is

   function Create_Camera return Node_Access;

   procedure Register;
   --  Adds the kind "Camera" to AMV.Flow.Kinds (once; later calls do
   --  nothing).

end AMV.Flow.Nodes.Camera;
