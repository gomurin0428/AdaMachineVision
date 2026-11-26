pragma SPARK_Mode (Off);

with AMV.GigE_Vision_Bayer;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Images;
with AMV.Kernels.GigE_Vision;

package body AMV.GigE_Vision is
   package Engine renames AMV.Kernels.GigE_Vision;
   package Bayer renames AMV.GigE_Vision_Bayer;
   package T renames AMV.GigE_Vision_Types;
   use type T.Frame_Status;

   procedure Raise_Camera_Status (Status : T.Camera_Status) is
   begin
      case Status is
         when T.Camera_Success =>
            null;
         when T.Camera_Bad_Parameter =>
            raise AMV.Ks_Bad_Parameter_Exception with "Invalid camera operation";
         when T.Camera_Out_Of_Memory =>
            raise Storage_Error;
         when T.Camera_Unsupported =>
            raise AMV.Ks_Exception with "Unsupported GigE Vision operation";
         when T.Camera_Error =>
            raise AMV.Ks_Exception with "GigE Vision operation failed";
      end case;
   end Raise_Camera_Status;

   procedure Raise_Frame_Status (Status : T.Frame_Status) is
   begin
      case Status is
         when T.Frame_Success =>
            null;
         when T.Frame_Bad_Parameter =>
            raise AMV.Ks_Bad_Parameter_Exception with
              "Camera must be streaming and timeout positive";
         when T.Frame_Timeout =>
            raise Ks_GigE_Vision_Timeout_Exception with
              "Timed out receiving a camera frame";
         when T.Frame_Out_Of_Memory =>
            raise Storage_Error;
         when T.Frame_Unsupported_Payload =>
            raise AMV.Ks_Exception with "Unsupported camera payload";
         when T.Frame_Unsupported_Format =>
            raise AMV.Ks_Exception with
              "Only packed Mono8 and Bayer8 frames are supported";
         when T.Frame_Invalid_Dimensions =>
            raise AMV.Ks_Exception with "Camera frame dimensions are invalid";
         when T.Frame_Too_Large =>
            raise AMV.Ks_Exception with "Camera frame exceeds image size limit";
         when T.Frame_Invalid_Length =>
            raise AMV.Ks_Exception with "Camera frame payload length is invalid";
         when T.Frame_Error =>
            raise AMV.Ks_Exception with "Camera frame acquisition failed";
      end case;
   end Raise_Frame_Status;

   procedure Open (Camera : in out Ks_GigE_Camera; Device_ID : String) is
      Status  : T.Camera_Status;
      Receipt : T.Native_Result;
   begin
      Engine.Open (Camera.State, Camera.Handle, Device_ID, Status, Receipt);
      Raise_Camera_Status (Status);
   end Open;

   procedure Close (Camera : in out Ks_GigE_Camera) is
      Receipt : T.Native_Result;
   begin
      Engine.Close (Camera.State, Camera.Handle, Receipt);
   end Close;

   function Is_Open (Camera : Ks_GigE_Camera) return Boolean is
     (Engine.Is_Open (Camera.State));

   procedure Start (Camera : in out Ks_GigE_Camera) is
      Status  : T.Camera_Status;
      Receipt : T.Native_Result;
   begin
      Engine.Start (Camera.State, Camera.Handle, Status, Receipt);
      Raise_Camera_Status (Status);
   end Start;

   procedure Stop (Camera : in out Ks_GigE_Camera) is
      Status  : T.Camera_Status;
      Receipt : T.Native_Result;
   begin
      Engine.Stop (Camera.State, Camera.Handle, Status, Receipt);
      Raise_Camera_Status (Status);
   end Stop;

   function Is_Streaming (Camera : Ks_GigE_Camera) return Boolean is
     (Engine.Is_Streaming (Camera.State));

   function Grab
     (Camera : in out Ks_GigE_Camera;
      Timeout_Milliseconds : Natural)
      return AMV.Images.Ks_Image_8_Grey
   is
      Kernel_Image : AMV.Kernels.Images.Ks_Image_8_Grey := null;
      Status : T.Frame_Status;
      Observation : T.Frame_Observation;
   begin
      begin
         Engine.Grab
           (Camera.State, Camera.Handle, Timeout_Milliseconds,
            Kernel_Image, Status, Observation);
         --  The engine accepts Mono8 only; a frame it rejected for its
         --  format alone may be Bayer8, which is converted to grey.
         if Status = T.Frame_Unsupported_Format
           and then Bayer.Is_Bayer_8 (Observation.Pixel_Format)
         then
            Bayer.Build_Grey (Observation, Kernel_Image, Status);
         end if;
         Raise_Frame_Status (Status);
         declare
            Result : constant AMV.Images.Ks_Image_8_Grey :=
              AMV.Images.Kernel_Images.Adopt (Kernel_Image);
         begin
            AMV.GigE_Vision_Native.Release_Frame (Observation);
            return Result;
         end;
      exception
         when others =>
            AMV.GigE_Vision_Native.Release_Frame (Observation);
            raise;
      end;
   end Grab;

   overriding procedure Finalize (Camera : in out Ks_GigE_Camera) is
   begin
      Close (Camera);
   end Finalize;

end AMV.GigE_Vision;
