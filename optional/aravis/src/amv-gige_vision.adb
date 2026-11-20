with Ada.Characters.Latin_1;
with Ada.Strings;
with Ada.Strings.Fixed;
with Interfaces.C;
with Interfaces.C.Strings;
with System.Address_To_Access_Conversions;
with System.Storage_Elements;

package body AMV.GigE_Vision is

   use type Interfaces.C.int;
   use type Interfaces.C.char;
   use type Interfaces.C.size_t;
   use type Interfaces.C.unsigned;
   use type System.Address;
   use System.Storage_Elements;

   Success_Status     : constant Interfaces.C.int := 0;
   Timeout_Status     : constant Interfaces.C.int := 1;
   Bad_Parameter      : constant Interfaces.C.int := 3;

   Error_Buffer_Size : constant Interfaces.C.size_t := 512;

   type Error_Buffer_Type is
     array (Interfaces.C.size_t range 0 .. Error_Buffer_Size - 1)
       of aliased Interfaces.C.char;

   function C_Open
     (Device_ID : Interfaces.C.Strings.chars_ptr;
      Camera    : access System.Address;
      Error     : System.Address;
      Error_Size : Interfaces.C.size_t) return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_aravis_open";

   procedure C_Close (Camera : System.Address)
     with Import, Convention => C, External_Name => "amv_aravis_close";

   function C_Start
     (Camera : System.Address;
      Error : System.Address;
      Error_Size : Interfaces.C.size_t) return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_aravis_start";

   function C_Stop
     (Camera : System.Address;
      Error : System.Address;
      Error_Size : Interfaces.C.size_t) return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_aravis_stop";

   function C_Is_Streaming (Camera : System.Address) return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_aravis_is_streaming";

   function C_Grab
     (Camera : System.Address;
      Timeout_Milliseconds : Interfaces.C.unsigned_long_long;
      Width : access Interfaces.C.unsigned;
      Height : access Interfaces.C.unsigned;
      Pixels : access System.Address;
      Pixel_Size : access Interfaces.C.size_t;
      Error : System.Address;
      Error_Size : Interfaces.C.size_t) return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_aravis_grab";

   procedure C_Free_Pixels (Pixels : System.Address)
     with Import, Convention => C, External_Name => "amv_aravis_free_pixels";

   package Byte_Addresses is new System.Address_To_Access_Conversions
     (Interfaces.C.unsigned_char);

   function To_Message (Error : Error_Buffer_Type) return String is
      Last : Interfaces.C.size_t := 0;
   begin
      while Last < Error_Buffer_Size and then Error (Last) /= Interfaces.C.nul loop
         Last := Last + 1;
      end loop;

      declare
         Message : String (1 .. Natural (Last));
      begin
         for Index in Message'Range loop
            Message (Index) := Character'Val
              (Interfaces.C.char'Pos
                 (Error (Interfaces.C.size_t (Index - 1))));
         end loop;
         return Message;
      end;
   end To_Message;

   procedure Raise_Status
     (Status : Interfaces.C.int; Error : Error_Buffer_Type)
   is
      Message : constant String := To_Message (Error);
   begin
      if Status = Success_Status then
         return;
      elsif Status = Timeout_Status then
         raise Ks_GigE_Vision_Timeout_Exception with Message;
      elsif Status = Bad_Parameter then
         raise AMV.Ks_Bad_Parameter_Exception with Message;
      else
         raise AMV.Ks_Exception with Message;
      end if;
   end Raise_Status;

   procedure Open (Camera : in out Ks_GigE_Camera; Device_ID : String) is
      C_ID : Interfaces.C.Strings.chars_ptr := Interfaces.C.Strings.Null_Ptr;
      C_Handle : aliased System.Address := System.Null_Address;
      Status : Interfaces.C.int;
      Error : aliased Error_Buffer_Type := [others => Interfaces.C.nul];
   begin
      if Camera.Handle /= System.Null_Address then
         raise AMV.Ks_Bad_Parameter_Exception with "Camera is already open";
      end if;
      if Ada.Strings.Fixed.Trim (Device_ID, Ada.Strings.Both)'Length = 0 or else
        (for some Character of Device_ID =>
           Character = Ada.Characters.Latin_1.NUL)
      then
         raise AMV.Ks_Bad_Parameter_Exception with
           "Device ID must be non-empty and contain no NUL character";
      end if;

      C_ID := Interfaces.C.Strings.New_String (Device_ID);
      begin
         Status := C_Open
           (C_ID, C_Handle'Access, Error'Address,
            Error_Buffer_Size);
      exception
         when others =>
            Interfaces.C.Strings.Free (C_ID);
            raise;
      end;
      Interfaces.C.Strings.Free (C_ID);
      if Status = Success_Status then
         Camera.Handle := C_Handle;
      end if;
      Raise_Status (Status, Error);
   end Open;

   procedure Close (Camera : in out Ks_GigE_Camera) is
   begin
      if Camera.Handle /= System.Null_Address then
         C_Close (Camera.Handle);
         Camera.Handle := System.Null_Address;
      end if;
   end Close;

   function Is_Open (Camera : Ks_GigE_Camera) return Boolean is
   begin
      return Camera.Handle /= System.Null_Address;
   end Is_Open;

   procedure Start (Camera : in out Ks_GigE_Camera) is
      Error : aliased Error_Buffer_Type := [others => Interfaces.C.nul];
   begin
      if not Is_Open (Camera) then
         raise AMV.Ks_Bad_Parameter_Exception with "Camera is not open";
      end if;
      Raise_Status
        (C_Start (Camera.Handle, Error'Address, Error_Buffer_Size), Error);
   end Start;

   procedure Stop (Camera : in out Ks_GigE_Camera) is
      Error : aliased Error_Buffer_Type := [others => Interfaces.C.nul];
   begin
      Raise_Status
        (C_Stop (Camera.Handle, Error'Address, Error_Buffer_Size), Error);
   end Stop;

   function Is_Streaming (Camera : Ks_GigE_Camera) return Boolean is
   begin
      return C_Is_Streaming (Camera.Handle) /= 0;
   end Is_Streaming;

   function Grab
     (Camera : in out Ks_GigE_Camera;
      Timeout_Milliseconds : Natural)
      return AMV.Images.Ks_Image_8_Grey
   is
      Error : aliased Error_Buffer_Type := [others => Interfaces.C.nul];
      Width : aliased Interfaces.C.unsigned := 0;
      Height : aliased Interfaces.C.unsigned := 0;
      Pixels : aliased System.Address := System.Null_Address;
      Pixel_Size : aliased Interfaces.C.size_t := 0;
      Status : Interfaces.C.int;
      Image_Width : Natural;
      Image_Height : Natural;
      Expected_Size : Natural;
      Image : AMV.Images.Ks_Image_8_Grey;
   begin
      if not Is_Open (Camera) or else not Is_Streaming (Camera) then
         raise AMV.Ks_Bad_Parameter_Exception with
           "Camera must be open and streaming before Grab";
      end if;
      if Timeout_Milliseconds = 0 then
         raise AMV.Ks_Bad_Parameter_Exception with
           "Timeout must be positive";
      end if;

      Status := C_Grab
        (Camera.Handle,
         Interfaces.C.unsigned_long_long (Timeout_Milliseconds),
         Width'Access, Height'Access, Pixels'Access, Pixel_Size'Access,
         Error'Address, Error_Buffer_Size);
      Raise_Status (Status, Error);

      begin
         if Width = 0 or else Height = 0 or else
           Width > Interfaces.C.unsigned (Natural'Last) or else
           Height > Interfaces.C.unsigned (Natural'Last)
         then
            raise AMV.Ks_Exception with
              "Camera frame dimensions exceed AMV image limits";
         end if;
         Image_Width := Natural (Width);
         Image_Height := Natural (Height);
         if Image_Width > Natural'Last / Image_Height then
            raise AMV.Ks_Exception with "Camera frame size overflows";
         end if;
         Expected_Size := Image_Width * Image_Height;
         if Pixel_Size < Interfaces.C.size_t (Expected_Size) or else
           Pixels = System.Null_Address
         then
            raise AMV.Ks_Exception with "Camera frame data is truncated";
         end if;

         Image := AMV.Images.Create (Image_Width, Image_Height);
         declare
            Row : AMV.Images.Grey_8_Row (0 .. Image_Width - 1);
         begin
            for Y in 0 .. Image_Height - 1 loop
               for X in 0 .. Image_Width - 1 loop
                  Row (X) := AMV.Images.Grey_8
                    (Byte_Addresses.To_Pointer
                       (Pixels + System.Storage_Elements.Storage_Offset
                          (Y * Image_Width + X)).all);
               end loop;
               Image.Set_Row (Y, Row);
            end loop;
         end;
      exception
         when others =>
            if Pixels /= System.Null_Address then
               C_Free_Pixels (Pixels);
            end if;
            raise;
      end;

      C_Free_Pixels (Pixels);
      return Image;
   end Grab;

   procedure Finalize (Camera : in out Ks_GigE_Camera) is
   begin
      Close (Camera);
   exception
      when others =>
         Camera.Handle := System.Null_Address;
   end Finalize;

end AMV.GigE_Vision;
