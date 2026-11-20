pragma Validity_Checks ("F");

with Interfaces;
with AMV.Kernels;

package AMV.GigE_Vision_Types with SPARK_Mode is
   use type AMV.Kernels.Int32;
   use type Interfaces.Unsigned_64;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Int64 is AMV.Kernels.Int64;
   subtype Unsigned_32 is Interfaces.Unsigned_32;
   subtype Unsigned_64 is Interfaces.Unsigned_64;
   subtype Pixel is Interfaces.Unsigned_8;

   type Byte_Array is array (Positive range <>) of Pixel;
   type Byte_Array_Access is access all Byte_Array;

   type Camera_State is (Closed, Open_Stopped, Streaming);

   type Native_Result is
     (Native_Not_Called,
      Native_Success,
      Native_Timeout,
      Native_Bad_Parameter,
      Native_Unsupported,
      Native_Out_Of_Memory,
      Native_Error);

   type Camera_Status is
     (Camera_Success,
      Camera_Bad_Parameter,
      Camera_Unsupported,
      Camera_Out_Of_Memory,
      Camera_Error);

   type Frame_Status is
     (Frame_Success,
      Frame_Bad_Parameter,
      Frame_Timeout,
      Frame_Unsupported_Payload,
      Frame_Unsupported_Format,
      Frame_Invalid_Dimensions,
      Frame_Too_Large,
      Frame_Invalid_Length,
      Frame_Out_Of_Memory,
      Frame_Error);

   type Lifecycle_Operation is (Open_Operation, Start_Operation, Stop_Operation);

   Max_Image_Pixels : constant := 2**31 - 1;

   Arv_Buffer_Status_Success : constant Int32 := 0;
   Arv_Buffer_Status_Timeout : constant Int32 := 2;
   Arv_Payload_Image : constant Unsigned_32 := 16#0001#;
   Arv_Payload_Image_Extended_Chunk : constant Unsigned_32 := 16#4001#;
   Arv_Pixel_Format_Mono_8 : constant Unsigned_32 := 16#0108_0001#;

   type Frame_Observation is record
      Acquisition_Status : Native_Result := Native_Error;
      Byte_Count         : Natural := 0;
      Bytes              : Byte_Array_Access := null;
      Buffer_Status      : Int32 := -1;
      Payload_Type       : Unsigned_32 := 0;
      Pixel_Format       : Unsigned_32 := 0;
      Width              : Int32 := 0;
      Height             : Int32 := 0;
      Source_Size        : Unsigned_64 := 0;
   end record;

   function Valid_Observation (Frame : Frame_Observation) return Boolean is
     ((if Frame.Byte_Count = 0 then Frame.Bytes = null
       else Frame.Bytes /= null
         and then Frame.Bytes.all'First = 1
         and then Frame.Bytes.all'Length = Frame.Byte_Count
         and then Unsigned_64 (Frame.Byte_Count) = Frame.Source_Size));

end AMV.GigE_Vision_Types;
