pragma Validity_Checks ("F");

with AMV.GigE_Vision_Types;

package AMV.Spec.GigE_Vision
  with SPARK_Mode, Ghost
is
   package T renames AMV.GigE_Vision_Types;
   use type T.Camera_State;
   use type T.Native_Result;
   use type T.Frame_Status;
   use type T.Byte_Array_Access;
   use type T.Int32;
   use type T.Int64;
   use type T.Unsigned_32;
   use type T.Unsigned_64;

   function Valid_Selector (Device_ID : String) return Boolean is
     (Device_ID'Length > 0
      and then
        (for all I in Device_ID'Range => Device_ID (I) /= ASCII.NUL)
      and then
        (for some I in Device_ID'Range => Device_ID (I) /= ' '));

   function Camera_Result (Result : T.Native_Result) return T.Camera_Status
   is
     (case Result is
        when T.Native_Success => T.Camera_Success,
        when T.Native_Bad_Parameter => T.Camera_Bad_Parameter,
        when T.Native_Unsupported => T.Camera_Unsupported,
        when T.Native_Out_Of_Memory => T.Camera_Out_Of_Memory,
        when T.Native_Error | T.Native_Timeout => T.Camera_Error,
        when T.Native_Not_Called => T.Camera_Bad_Parameter)
     with Pre => Result /= T.Native_Not_Called;

   function Open_Status
     (State    : T.Camera_State;
      Device_ID : String;
      Result   : T.Native_Result) return T.Camera_Status
   is
     (if State /= T.Closed or else not Valid_Selector (Device_ID) then
         T.Camera_Bad_Parameter
      elsif Result = T.Native_Not_Called then
         T.Camera_Error
      else
         Camera_Result (Result));

   function Open_State
     (State    : T.Camera_State;
      Device_ID : String;
      Result   : T.Native_Result) return T.Camera_State
   is
     (if State = T.Closed and then Valid_Selector (Device_ID)
        and then Result = T.Native_Success
      then T.Open_Stopped
      else State);

   function Start_Status
     (State  : T.Camera_State;
      Result : T.Native_Result) return T.Camera_Status
   is
     (if State = T.Closed then
         T.Camera_Bad_Parameter
      elsif State = T.Streaming then
         T.Camera_Success
      elsif Result = T.Native_Not_Called then
         T.Camera_Error
      else
         Camera_Result (Result));

   function Start_State
     (State  : T.Camera_State;
      Result : T.Native_Result) return T.Camera_State
   is
     (if State = T.Open_Stopped and then Result = T.Native_Success then
         T.Streaming
      else State);

   function Stop_Status
     (State  : T.Camera_State;
      Result : T.Native_Result) return T.Camera_Status
   is
     (if State /= T.Streaming then
         T.Camera_Success
      elsif Result = T.Native_Not_Called then
         T.Camera_Error
      else
         Camera_Result (Result));

   function Stop_State
     (State  : T.Camera_State;
      Result : T.Native_Result) return T.Camera_State
   is
     (if State = T.Streaming and then Result = T.Native_Success then
         T.Open_Stopped
      else State);

   function Is_Open (State : T.Camera_State) return Boolean is
     (State /= T.Closed);

   function Is_Streaming (State : T.Camera_State) return Boolean is
     (State = T.Streaming);

   function Grab_Status
     (State   : T.Camera_State;
      Timeout : Natural;
      Frame   : T.Frame_Observation) return T.Frame_Status
   is
     (if State /= T.Streaming or else Timeout = 0 then
         T.Frame_Bad_Parameter
      elsif Frame.Acquisition_Status in
        T.Native_Not_Called | T.Native_Bad_Parameter
      then
         T.Frame_Bad_Parameter
      elsif Frame.Acquisition_Status = T.Native_Timeout then
         T.Frame_Timeout
      elsif Frame.Acquisition_Status = T.Native_Out_Of_Memory then
         T.Frame_Out_Of_Memory
      elsif Frame.Acquisition_Status in T.Native_Unsupported | T.Native_Error
      then
         T.Frame_Error
      elsif Frame.Buffer_Status = T.Arv_Buffer_Status_Timeout then
         T.Frame_Timeout
      elsif Frame.Buffer_Status /= T.Arv_Buffer_Status_Success then
         T.Frame_Error
      elsif Frame.Payload_Type /= T.Arv_Payload_Image then
         T.Frame_Unsupported_Payload
      elsif Frame.Pixel_Format /= T.Arv_Pixel_Format_Mono_8 then
         T.Frame_Unsupported_Format
      elsif Frame.Width <= 0 or else Frame.Height <= 0 then
         T.Frame_Invalid_Dimensions
      elsif T.Int64 (Frame.Width) * T.Int64 (Frame.Height)
        > T.Max_Image_Pixels
      then
         T.Frame_Too_Large
      elsif Frame.Source_Size /=
        T.Unsigned_64 (T.Int64 (Frame.Width) * T.Int64 (Frame.Height))
        or else T.Int64 (Frame.Byte_Count) /=
          T.Int64 (Frame.Width) * T.Int64 (Frame.Height)
        or else Frame.Bytes = null
        or else Frame.Bytes.all'First /= 1
        or else T.Int64 (Frame.Bytes.all'Length) /=
          T.Int64 (Frame.Width) * T.Int64 (Frame.Height)
      then
         T.Frame_Invalid_Length
      else
         T.Frame_Success);

   function Pixel_At
     (Frame : T.Frame_Observation;
      X, Y  : Natural) return T.Pixel
   is
     (if Frame.Width <= 0
        or else Frame.Height <= 0
        or else Frame.Byte_Count = 0
        or else Frame.Bytes = null
      then
         0
      elsif Frame.Bytes.all'First /= 1
        or else Frame.Bytes.all'Length /= Frame.Byte_Count
        or else X >= Natural (Frame.Width)
        or else Y >= Natural (Frame.Height)
      then
         0
      elsif T.Int64 (Y) * T.Int64 (Frame.Width)
        + T.Int64 (X) >= T.Int64 (Frame.Byte_Count)
      then
         0
      else
         Frame.Bytes.all
           (Positive
              (Natural
                 (T.Int64 (Y) * T.Int64 (Frame.Width)
                  + T.Int64 (X)) + 1)));

end AMV.Spec.GigE_Vision;
