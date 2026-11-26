pragma SPARK_Mode (Off);

with Ada.Finalization;
with AMV.GigE_Vision_Native;
with AMV.GigE_Vision_Types;
with AMV.Images;

package AMV.GigE_Vision is

   Ks_GigE_Vision_Timeout_Exception : exception;

   type Ks_GigE_Camera is new Ada.Finalization.Limited_Controlled with private;

   procedure Open (Camera : in out Ks_GigE_Camera; Device_ID : String);
   --  Opens the explicitly named device. A non-empty IPv4 address connects
   --  directly; other identifiers are resolved by Aravis when Open is called.

   procedure Close (Camera : in out Ks_GigE_Camera);
   --  Releases local camera resources; repeated calls are safe.

   function Is_Open (Camera : Ks_GigE_Camera) return Boolean;

   procedure Start (Camera : in out Ks_GigE_Camera);
   --  Starts acquisition; calling Start while streaming is a no-op.

   procedure Stop (Camera : in out Ks_GigE_Camera);
   --  Stops acquisition; calling Stop while closed or stopped is a no-op.

   function Is_Streaming (Camera : Ks_GigE_Camera) return Boolean;

   function Grab
     (Camera : in out Ks_GigE_Camera;
      Timeout_Milliseconds : Natural)
      return AMV.Images.Ks_Image_8_Grey;
   --  Requires a streaming camera and a positive finite timeout. A Mono8
   --  frame is returned as is; a Bayer8 frame (BayerGR8, BayerRG8, BayerGB8
   --  or BayerBG8) is converted to grey (AMV.GigE_Vision_Bayer). The
   --  returned image owns its pixels independently of the camera stream.

private
   type Ks_GigE_Camera is new Ada.Finalization.Limited_Controlled with record
      Handle : AMV.GigE_Vision_Native.Camera_Handle :=
        AMV.GigE_Vision_Native.Null_Handle;
      State : AMV.GigE_Vision_Types.Camera_State :=
        AMV.GigE_Vision_Types.Closed;
   end record;

   overriding procedure Finalize (Camera : in out Ks_GigE_Camera);

end AMV.GigE_Vision;
