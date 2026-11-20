pragma Validity_Checks ("F");

with System;
with AMV.GigE_Vision_Types;

package AMV.GigE_Vision_Native
  with SPARK_Mode, Abstract_State => Device_IO
is
   package T renames AMV.GigE_Vision_Types;
   use type T.Native_Result;
   use type T.Byte_Array_Access;
   use type T.Int32;
   use type T.Unsigned_32;
   use type T.Unsigned_64;
   use type System.Address;

   subtype Camera_Handle is System.Address;
   Null_Handle : constant Camera_Handle := System.Null_Address;

   procedure Open
     (Device_ID : String;
      Handle    : out Camera_Handle;
      Result    : out T.Native_Result)
   with
     Global  => (In_Out => Device_IO),
     Depends => (Handle    => (Device_IO, Device_ID),
                 Result    => (Device_IO, Device_ID),
                 Device_IO => (Device_IO, Device_ID)),
     Post    => Result /= T.Native_Not_Called
       and then (if Result = T.Native_Success
                 then Handle /= Null_Handle
                 else Handle = Null_Handle);

   procedure Start
     (Handle : Camera_Handle;
      Result : out T.Native_Result)
   with
     Global  => (In_Out => Device_IO),
     Depends => (Result    => (Device_IO, Handle),
                 Device_IO => (Device_IO, Handle)),
     Post    => Result /= T.Native_Not_Called;

   procedure Stop
     (Handle : Camera_Handle;
      Result : out T.Native_Result)
   with
     Global  => (In_Out => Device_IO),
     Depends => (Result    => (Device_IO, Handle),
                 Device_IO => (Device_IO, Handle)),
     Post    => Result /= T.Native_Not_Called;

   procedure Close
     (Handle      : in out Camera_Handle;
      Stop_Expected : Boolean;
      Stop_Result : out T.Native_Result)
   with
     Pre => Handle /= Null_Handle,
     Global  => (In_Out => Device_IO),
     Depends => (Handle      => (Device_IO, Handle),
                 Stop_Result => (Device_IO, Handle, Stop_Expected),
                 Device_IO   => (Device_IO, Handle)),
     Post    => Handle = Null_Handle
       and then (if Stop_Expected
                 then Stop_Result /= T.Native_Not_Called);

   procedure Acquire
     (Handle : Camera_Handle;
      Timeout_Milliseconds : Positive;
      Observation : out T.Frame_Observation)
   with
     Global  => (In_Out => Device_IO),
     Depends => (Observation => (Device_IO, Handle, Timeout_Milliseconds),
                 Device_IO   => (Device_IO, Handle, Timeout_Milliseconds)),
     Post    => T.Valid_Observation (Observation)
       and then Observation.Acquisition_Status /= T.Native_Not_Called;

   procedure Release_Frame (Observation : in out T.Frame_Observation)
   with
     Global  => null,
     Depends => (Observation => Observation),
     Post    => Observation.Acquisition_Status = T.Native_Not_Called
       and then Observation.Byte_Count = 0
       and then Observation.Bytes = null
       and then Observation.Buffer_Status = -1
       and then Observation.Payload_Type = 0
       and then Observation.Pixel_Format = 0
       and then Observation.Width = 0
       and then Observation.Height = 0
       and then Observation.Source_Size = 0;

end AMV.GigE_Vision_Native;
