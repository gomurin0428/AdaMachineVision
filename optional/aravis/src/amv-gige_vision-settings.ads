pragma SPARK_Mode (Off);

--  Exposure and gain of an open camera, through Aravis's standard features
--  (ExposureTime or ExposureTimeAbs, ExposureAuto, Gain). They may be
--  changed while the camera is streaming. Not part of the SPARK proof.
--
--  Every operation raises AMV.Ks_Bad_Parameter_Exception for a closed
--  camera or a value that is not finite, and AMV.Ks_Exception with
--  Aravis's message when the camera refuses or lacks the feature.
package AMV.GigE_Vision.Settings is

   procedure Set_Exposure_Time
     (Camera : in out Ks_GigE_Camera; Microseconds : Long_Float);
   --  The camera clamps or rounds the value to what it supports.

   procedure Get_Exposure_Time
     (Camera                          : in out Ks_GigE_Camera;
      Microseconds, Minimum, Maximum : out Long_Float);

   procedure Set_Auto_Exposure
     (Camera : in out Ks_GigE_Camera; Enabled : Boolean);
   --  ExposureAuto Continuous when Enabled, Off otherwise.

   procedure Set_Gain (Camera : in out Ks_GigE_Camera; Gain : Long_Float);

   procedure Get_Gain
     (Camera                 : in out Ks_GigE_Camera;
      Gain, Minimum, Maximum : out Long_Float);

end AMV.GigE_Vision.Settings;
