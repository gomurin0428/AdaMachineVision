pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Unchecked_Deallocation;
with Interfaces.C;
with Interfaces.C.Strings;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;

package body AMV.GigE_Vision_Native is
   use type Interfaces.C.int;
   use type Interfaces.C.size_t;
   use System.Storage_Elements;

   procedure Free_Bytes is new Ada.Unchecked_Deallocation
     (T.Byte_Array, T.Byte_Array_Access);

   Error_Buffer_Size : constant Interfaces.C.size_t := 512;
   type Error_Buffer is
     array (Interfaces.C.size_t range 0 .. Error_Buffer_Size - 1)
       of aliased Interfaces.C.char;

   function C_Open
     (Device_ID : Interfaces.C.Strings.chars_ptr;
      Handle : access System.Address;
      Error : System.Address;
      Error_Size : Interfaces.C.size_t) return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_aravis_open";

   function C_Start
     (Handle : System.Address; Error : System.Address;
      Error_Size : Interfaces.C.size_t) return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_aravis_start";

   function C_Stop
     (Handle : System.Address; Error : System.Address;
      Error_Size : Interfaces.C.size_t) return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_aravis_stop";

   function C_Close (Handle : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_aravis_close";

   function C_Grab
     (Handle : System.Address;
      Timeout_Milliseconds : Interfaces.C.unsigned_long_long;
      Buffer_Status : access Interfaces.C.int;
      Payload_Type : access Interfaces.C.unsigned;
      Pixel_Format : access Interfaces.C.unsigned;
      Width : access Interfaces.C.int;
      Height : access Interfaces.C.int;
      Pixels : access System.Address;
      Pixel_Size : access Interfaces.C.size_t;
      Error : System.Address;
      Error_Size : Interfaces.C.size_t) return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_aravis_grab";

   procedure C_Free_Pixels (Pixels : System.Address)
     with Import, Convention => C, External_Name => "amv_aravis_free_pixels";

   package Byte_Addresses is new System.Address_To_Access_Conversions
     (Interfaces.C.unsigned_char);

   function Map_Result (Code : Interfaces.C.int) return T.Native_Result is
   begin
      case Code is
         when 0 => return T.Native_Success;
         when 1 => return T.Native_Timeout;
         when 2 => return T.Native_Unsupported;
         when 3 => return T.Native_Bad_Parameter;
         when 5 => return T.Native_Out_Of_Memory;
         when 6 => return T.Native_Not_Called;
         when others => return T.Native_Error;
      end case;
   end Map_Result;

   function Map_Dispatched_Result
     (Code : Interfaces.C.int) return T.Native_Result
   is
      Result : constant T.Native_Result := Map_Result (Code);
   begin
      if Result = T.Native_Not_Called then
         return T.Native_Error;
      end if;
      return Result;
   end Map_Dispatched_Result;

   procedure Open
     (Device_ID : String;
      Handle    : out Camera_Handle;
      Result    : out T.Native_Result)
   is
      C_ID : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      C_Handle : aliased System.Address := System.Null_Address;
      Error : aliased Error_Buffer := [others => Interfaces.C.nul];
      Code : Interfaces.C.int;
   begin
      Handle := Null_Handle;
      C_ID := Interfaces.C.Strings.New_String (Device_ID);
      begin
         Code := C_Open (C_ID, C_Handle'Access, Error'Address,
                         Error_Buffer_Size);
      exception
         when others =>
            Interfaces.C.Strings.Free (C_ID);
            raise;
      end;
      Interfaces.C.Strings.Free (C_ID);
      Result := Map_Dispatched_Result (Code);
      if Result = T.Native_Success then
         Handle := C_Handle;
      end if;
   end Open;

   procedure Start
     (Handle : Camera_Handle; Result : out T.Native_Result)
   is
      Error : aliased Error_Buffer := [others => Interfaces.C.nul];
   begin
      Result := Map_Dispatched_Result
        (C_Start (Handle, Error'Address, Error_Buffer_Size));
   end Start;

   procedure Stop
     (Handle : Camera_Handle; Result : out T.Native_Result)
   is
      Error : aliased Error_Buffer := [others => Interfaces.C.nul];
   begin
      Result := Map_Dispatched_Result
        (C_Stop (Handle, Error'Address, Error_Buffer_Size));
   end Stop;

   procedure Close
     (Handle      : in out Camera_Handle;
      Stop_Expected : Boolean;
      Stop_Result : out T.Native_Result)
   is
   begin
      if Handle = Null_Handle then
         Stop_Result := T.Native_Not_Called;
      else
         Stop_Result := Map_Result (C_Close (Handle));
         if Stop_Expected and then Stop_Result = T.Native_Not_Called then
            Stop_Result := T.Native_Error;
         end if;
      end if;
      Handle := Null_Handle;
   end Close;

   procedure Acquire
     (Handle : Camera_Handle;
      Timeout_Milliseconds : Positive;
      Observation : out T.Frame_Observation)
   is
      C_Buffer_Status : aliased Interfaces.C.int := -1;
      C_Payload_Type : aliased Interfaces.C.unsigned := 0;
      C_Pixel_Format : aliased Interfaces.C.unsigned := 0;
      C_Width : aliased Interfaces.C.int := 0;
      C_Height : aliased Interfaces.C.int := 0;
      C_Pixels : aliased System.Address := System.Null_Address;
      C_Pixel_Size : aliased Interfaces.C.size_t := 0;
      Error : aliased Error_Buffer := [others => Interfaces.C.nul];
      Code : Interfaces.C.int;
      Count : Natural := 0;
      Data : T.Byte_Array_Access := null;

      procedure Free_C_Pixels is
      begin
         if C_Pixels /= System.Null_Address then
            C_Free_Pixels (C_Pixels);
            C_Pixels := System.Null_Address;
         end if;
      end Free_C_Pixels;
   begin
      Code := C_Grab
        (Handle,
         Interfaces.C.unsigned_long_long (Timeout_Milliseconds),
         C_Buffer_Status'Access, C_Payload_Type'Access,
         C_Pixel_Format'Access, C_Width'Access, C_Height'Access,
         C_Pixels'Access, C_Pixel_Size'Access, Error'Address,
         Error_Buffer_Size);

      if C_Pixels /= System.Null_Address
        and then C_Pixel_Size <= Interfaces.C.size_t (T.Max_Image_Pixels)
      then
         Count := Natural (C_Pixel_Size);
      end if;

      begin
         if Count > 0 then
            begin
               Data := new T.Byte_Array (1 .. Count);
            exception
               when Storage_Error =>
                  Count := 0;
                  Code := 5;
            end;
         end if;
         if Count > 0 then
            for I in 0 .. Count - 1 loop
               Data (I + 1) := T.Pixel
                 (Byte_Addresses.To_Pointer
                    (C_Pixels + Storage_Offset (I)).all);
            end loop;
         end if;
         Observation :=
           (Acquisition_Status => Map_Dispatched_Result (Code),
            Byte_Count         => Count,
            Bytes              => Data,
            Buffer_Status      => T.Int32 (C_Buffer_Status),
            Payload_Type       => T.Unsigned_32 (C_Payload_Type),
            Pixel_Format       => T.Unsigned_32 (C_Pixel_Format),
            Width              => T.Int32 (C_Width),
            Height             => T.Int32 (C_Height),
            Source_Size        => T.Unsigned_64 (C_Pixel_Size));
         Data := null;
         Free_C_Pixels;
      exception
         when others =>
            Free_Bytes (Data);
            Free_C_Pixels;
            raise;
      end;
   end Acquire;

   procedure Release_Frame (Observation : in out T.Frame_Observation) is
   begin
      Free_Bytes (Observation.Bytes);
      Observation :=
        (Acquisition_Status => T.Native_Not_Called,
         Byte_Count         => 0,
         Bytes              => null,
         Buffer_Status      => -1,
         Payload_Type       => 0,
         Pixel_Format       => 0,
         Width              => 0,
         Height             => 0,
         Source_Size        => 0);
   end Release_Frame;

end AMV.GigE_Vision_Native;
