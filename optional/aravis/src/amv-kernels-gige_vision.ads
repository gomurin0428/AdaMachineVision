pragma Validity_Checks ("F");

with AMV.GigE_Vision_Native;
with AMV.GigE_Vision_Types;
with AMV.Kernels.Images;
with AMV.Spec.GigE_Vision;

package AMV.Kernels.GigE_Vision with SPARK_Mode is
   package N  renames AMV.GigE_Vision_Native;
   package T  renames AMV.GigE_Vision_Types;
   package KI renames AMV.Kernels.Images;
   use type T.Camera_State;
   use type T.Native_Result;
   use type T.Camera_Status;
   use type T.Frame_Status;
   use type T.Pixel;
   use type T.Byte_Array_Access;
   use type T.Unsigned_32;
   use type T.Unsigned_64;
   use type N.Camera_Handle;
   use type KI.Ks_Image_8_Grey;

   procedure Open
     (State    : in out T.Camera_State;
      Handle   : in out N.Camera_Handle;
      Device_ID : String;
      Status   : out T.Camera_Status;
      Receipt  : out T.Native_Result)
   with
     Pre => (State = T.Closed) = (Handle = N.Null_Handle),
     Global  => (In_Out => N.Device_IO),
     Depends => (State => (State, Device_ID, N.Device_IO),
                 Handle => (Handle, State, Device_ID, N.Device_IO),
                 Status => (State, Device_ID, N.Device_IO),
                 Receipt => (State, Device_ID, N.Device_IO),
                 N.Device_IO => (State, Device_ID, N.Device_IO)),
     Post    =>
       Status = AMV.Spec.GigE_Vision.Open_Status
         (State'Old, Device_ID, Receipt)
       and then State = AMV.Spec.GigE_Vision.Open_State
         (State'Old, Device_ID, Receipt)
       and then ((Receipt = T.Native_Not_Called) =
         (State'Old /= T.Closed or else
          not AMV.Spec.GigE_Vision.Valid_Selector (Device_ID)))
       and then
         (if Receipt = T.Native_Success
          and then State'Old = T.Closed
          and then AMV.Spec.GigE_Vision.Valid_Selector (Device_ID)
          then Handle /= N.Null_Handle
          else Handle = Handle'Old);

   procedure Start
     (State   : in out T.Camera_State;
      Handle  : N.Camera_Handle;
      Status  : out T.Camera_Status;
      Receipt : out T.Native_Result)
   with
     Pre => (State = T.Closed) = (Handle = N.Null_Handle),
     Global  => (In_Out => N.Device_IO),
     Depends => ((State, Status, Receipt) => (State, Handle, N.Device_IO),
                 N.Device_IO => (State, Handle, N.Device_IO)),
     Post    =>
       Status = AMV.Spec.GigE_Vision.Start_Status (State'Old, Receipt)
       and then State = AMV.Spec.GigE_Vision.Start_State
         (State'Old, Receipt)
       and then ((Receipt = T.Native_Not_Called) =
                   (State'Old /= T.Open_Stopped));

   procedure Stop
     (State   : in out T.Camera_State;
      Handle  : N.Camera_Handle;
      Status  : out T.Camera_Status;
      Receipt : out T.Native_Result)
   with
     Pre => (State = T.Closed) = (Handle = N.Null_Handle),
     Global  => (In_Out => N.Device_IO),
     Depends => ((State, Status, Receipt) => (State, Handle, N.Device_IO),
                 N.Device_IO => (State, Handle, N.Device_IO)),
     Post    =>
       Status = AMV.Spec.GigE_Vision.Stop_Status (State'Old, Receipt)
       and then State = AMV.Spec.GigE_Vision.Stop_State
         (State'Old, Receipt)
       and then ((Receipt = T.Native_Not_Called) =
                   (State'Old /= T.Streaming));

   procedure Close
     (State        : in out T.Camera_State;
      Handle       : in out N.Camera_Handle;
      Stop_Receipt : out T.Native_Result)
   with
     Pre => (State = T.Closed) = (Handle = N.Null_Handle),
     Global  => (In_Out => N.Device_IO),
     Depends => (State => null,
                 Handle => (Handle, N.Device_IO),
                 Stop_Receipt => (State, Handle, N.Device_IO),
                 N.Device_IO => (Handle, N.Device_IO)),
     Post    => State = T.Closed and then Handle = N.Null_Handle
       and then (if State'Old = T.Closed
                 then Stop_Receipt = T.Native_Not_Called
                 elsif State'Old = T.Streaming
                 then Stop_Receipt /= T.Native_Not_Called);

   function Is_Open (State : T.Camera_State) return Boolean
   with Post => Is_Open'Result = AMV.Spec.GigE_Vision.Is_Open (State);

   function Is_Streaming (State : T.Camera_State) return Boolean
   with Post => Is_Streaming'Result =
     AMV.Spec.GigE_Vision.Is_Streaming (State);

   procedure Build_Frame
     (State       : T.Camera_State;
      Timeout     : Natural;
      Observation : T.Frame_Observation;
      Image       : out KI.Ks_Image_8_Grey;
      Status      : out T.Frame_Status)
   with
     Global  => null,
     Depends => ((Image, Status) => (State, Timeout, Observation)),
     Post    =>
       (Status = AMV.Spec.GigE_Vision.Grab_Status
          (State, Timeout, Observation)
        or else
          (AMV.Spec.GigE_Vision.Grab_Status
             (State, Timeout, Observation) = T.Frame_Success
           and then Status = T.Frame_Out_Of_Memory))
       and then
         (if Status = T.Frame_Success
          then KI.Valid_Image (Image)
            and then Image.Width = Observation.Width
            and then Image.Height = Observation.Height
            and then
              (for all Y in Image.Pixels'Range (1)
               => (for all X in Image.Pixels'Range (2)
                   => Image.Pixels (Y, X) =
                     AMV.Spec.GigE_Vision.Pixel_At
                       (Observation, Natural (X), Natural (Y))))
          else Image = null);

   procedure Grab
     (State        : T.Camera_State;
      Handle       : N.Camera_Handle;
      Timeout      : Natural;
      Image        : out KI.Ks_Image_8_Grey;
      Status       : out T.Frame_Status;
      Observation  : out T.Frame_Observation)
   with
     Pre => (State = T.Closed) = (Handle = N.Null_Handle),
     Global  => (In_Out => N.Device_IO),
     Depends => ((Image, Status, Observation) =>
                   (State, Handle, Timeout, N.Device_IO),
                 N.Device_IO => (State, Handle, Timeout, N.Device_IO)),
     Post    =>
       T.Valid_Observation (Observation)
       and then
         (Status = AMV.Spec.GigE_Vision.Grab_Status
            (State, Timeout, Observation)
          or else
            (AMV.Spec.GigE_Vision.Grab_Status
               (State, Timeout, Observation) = T.Frame_Success
             and then Status = T.Frame_Out_Of_Memory))
       and then
         (if State /= T.Streaming or else Timeout = 0
          then Observation.Acquisition_Status = T.Native_Not_Called
            and then Observation.Byte_Count = 0
            and then Observation.Bytes = null
            and then Observation.Buffer_Status = -1
            and then Observation.Payload_Type = 0
            and then Observation.Pixel_Format = 0
            and then Observation.Width = 0
            and then Observation.Height = 0
            and then Observation.Source_Size = 0)
       and then
         (if Status = T.Frame_Success
          then KI.Valid_Image (Image)
            and then Image.Width = Observation.Width
            and then Image.Height = Observation.Height
            and then
              (for all Y in Image.Pixels'Range (1)
               => (for all X in Image.Pixels'Range (2)
                   => Image.Pixels (Y, X) =
                     AMV.Spec.GigE_Vision.Pixel_At
                       (Observation, Natural (X), Natural (Y))))
          else Image = null);

end AMV.Kernels.GigE_Vision;
