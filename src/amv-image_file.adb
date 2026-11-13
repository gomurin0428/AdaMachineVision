pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Directories;
with Ada.Exceptions;
with Ada.IO_Exceptions;
with Ada.Streams.Stream_IO;
with Ada.Unchecked_Deallocation;
with Interfaces;
with System.Atomic_Operations.Integer_Arithmetic;

with AMV.Checks;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Images;

package body AMV.Image_File is

   use Ada.Streams;
   use Ada.Strings.Unbounded;
   use AMV.Images;

   package SIO renames Ada.Streams.Stream_IO;
   package KF renames AMV.Kernels.Image_File;
   package KI renames AMV.Kernels.Images;
   package Kernel_Images renames AMV.Images.Kernel_Images;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Int64 is AMV.Kernels.Int64;
   subtype Ks_Status is AMV.Kernels.Ks_Status;
   subtype U32 is Interfaces.Unsigned_32;

   use type Int32;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;
   procedure Check (Status : Ks_Status; Context : String)
     renames AMV.Checks.Check;

   Mode_Code : constant array (Ks_Image_File_Mode_Constants) of Int32 :=
     [Closed => KF.Mode_Closed,
      Read   => KF.Mode_Read,
      Write  => KF.Mode_Write,
      Update => KF.Mode_Update];
   --  The mode codes of the kernel.

   ---------------------------------------------------------------------
   --  Errors of the operating system's files
   ---------------------------------------------------------------------

   procedure Raise_File_Error (File_Name, Reason : String)
   with No_Return;
   --  Raises Ks_Image_File_Exception with File_Name & ": " & Reason.

   procedure Raise_File_Error (File_Name, Reason : String) is
   begin
      raise Ks_Image_File_Exception with File_Name & ": " & Reason;
   end Raise_File_Error;

   function IO_Message (E : Ada.Exceptions.Exception_Occurrence)
      return String;
   --  The exception message, or its name when the message is empty.

   function IO_Message (E : Ada.Exceptions.Exception_Occurrence)
      return String
   is
      Message : constant String := Ada.Exceptions.Exception_Message (E);
   begin
      if Message = "" then
         return Ada.Exceptions.Exception_Name (E);
      else
         return Message;
      end if;
   end IO_Message;

   procedure Close_Quietly (File : in out SIO.File_Type);
   --  Closes File if it is open, ignoring any error (used on paths that
   --  already report a failure).

   procedure Close_Quietly (File : in out SIO.File_Type) is
   begin
      if SIO.Is_Open (File) then
         SIO.Close (File);
      end if;
   exception
      when Ada.IO_Exceptions.Status_Error
         | Ada.IO_Exceptions.Use_Error
         | Ada.IO_Exceptions.Device_Error =>
         null;
   end Close_Quietly;

   ---------------------------------------------------------------------
   --  Bytes in memory
   ---------------------------------------------------------------------

   type Byte_Array_Access is access KF.Byte_Array;

   procedure Free is new Ada.Unchecked_Deallocation
     (KF.Byte_Array, Byte_Array_Access);

   type Byte_Buffer is new Ada.Finalization.Limited_Controlled with record
      Data : Byte_Array_Access;
   end record;
   --  The contents of a file, read or to be written; freed with the
   --  buffer.

   overriding procedure Finalize (Buffer : in out Byte_Buffer);

   overriding procedure Finalize (Buffer : in out Byte_Buffer) is
   begin
      Free (Buffer.Data);
   end Finalize;

   ---------------------------------------------------------------------
   --  Reading and writing files
   ---------------------------------------------------------------------

   function Exists_As_File (File_Name : String) return Boolean;
   --  Whether File_Name exists. Raises Ks_Image_File_Exception when it
   --  names something other than an ordinary file or cannot be examined.

   function Exists_As_File (File_Name : String) return Boolean is
      use Ada.Directories;
   begin
      if not Exists (File_Name) then
         return False;
      elsif Kind (File_Name) /= Ordinary_File then
         Raise_File_Error (File_Name, "not an ordinary file");
      end if;
      return True;
   exception
      when E : Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Raise_File_Error
           (File_Name, "cannot examine the file (" & IO_Message (E) & ")");
   end Exists_As_File;

   procedure Create_Empty (File_Name : String);
   --  Creates File_Name, or truncates it if it exists.

   procedure Create_Empty (File_Name : String) is
      File : SIO.File_Type;
   begin
      SIO.Create (File, SIO.Out_File, File_Name);
      SIO.Close (File);
   exception
      when E : Ada.IO_Exceptions.Name_Error
             | Ada.IO_Exceptions.Use_Error
             | Ada.IO_Exceptions.Device_Error
             | Ada.IO_Exceptions.Status_Error =>
         Close_Quietly (File);
         Raise_File_Error
           (File_Name, "cannot create the file (" & IO_Message (E) & ")");
      when others =>
         Close_Quietly (File);
         raise;
   end Create_Empty;

   procedure Load (File_Name : String; Buffer : in out Byte_Buffer);
   --  Reads the whole file into Buffer. A file too large for its contents
   --  to be allocated is an error. The file is closed again whatever
   --  happens.

   procedure Load (File_Name : String; Buffer : in out Byte_Buffer) is
      File   : SIO.File_Type;
      Size   : Int64;
      Last   : Stream_Element_Offset;
      Status : Ks_Status;
   begin
      SIO.Open (File, SIO.In_File, File_Name);
      Size := Int64 (SIO.Size (File));
      KF.Check_File_Size (Size, Status);
      Check (Status, File_Name);
      --  Only this allocation is guarded: a Storage_Error from anywhere
      --  else (a stack overflow, say) is not a property of the file.
      begin
         Buffer.Data := new KF.Byte_Array (1 .. Size);
      exception
         when Storage_Error =>
            KF.File_Too_Large (Size, Status);
            Check (Status, File_Name);
      end;
      declare
         Raw : Stream_Element_Array
                 (Stream_Element_Offset (Buffer.Data'First)
                  .. Stream_Element_Offset (Buffer.Data'Last))
           with Import, Address => Buffer.Data.all'Address;
      begin
         SIO.Read (File, Raw, Last);
      end;
      KF.Check_Whole_Read (Size, Int64 (Last), Status);
      Check (Status, File_Name);
      SIO.Close (File);
   exception
      when Ks_Image_File_Exception =>
         Close_Quietly (File);
         raise;
      when Ada.IO_Exceptions.Name_Error =>
         Close_Quietly (File);
         Raise_File_Error
           (File_Name,
            "cannot open the file (it does not exist or the name is not "
            & "valid)");
      when E : Ada.IO_Exceptions.Use_Error
             | Ada.IO_Exceptions.Device_Error
             | Ada.IO_Exceptions.End_Error
             | Ada.IO_Exceptions.Data_Error
             | Ada.IO_Exceptions.Status_Error
             | Ada.IO_Exceptions.Mode_Error =>
         Close_Quietly (File);
         Raise_File_Error
           (File_Name, "cannot read the file (" & IO_Message (E) & ")");
      when others =>
         --  Not expected; the file is closed all the same, so that a later
         --  open of the same name is not refused.
         Close_Quietly (File);
         raise;
   end Load;

   type Disk_State is record
      Exists : Boolean := False;
      Size   : Int64 := 0;
      Final  : KF.Byte := 0;
   end record;
   --  What an existing disk file is like before an image is appended: its
   --  size and its last byte (0 when it has none).

   function Final_Byte (File_Name : String) return KF.Byte;
   --  The last byte of the existing file File_Name; 0 for an empty file.

   function Final_Byte (File_Name : String) return KF.Byte is
      File  : SIO.File_Type;
      Final : Stream_Element_Array (1 .. 1) := [0];
      Last  : Stream_Element_Offset;
   begin
      SIO.Open (File, SIO.In_File, File_Name);
      SIO.Set_Index (File, SIO.Positive_Count'Max (SIO.Size (File), 1));
      SIO.Read (File, Final, Last);
      SIO.Close (File);
      return KF.Byte (Final (1));
   exception
      when E : Ada.IO_Exceptions.Name_Error
             | Ada.IO_Exceptions.Use_Error
             | Ada.IO_Exceptions.Device_Error
             | Ada.IO_Exceptions.End_Error
             | Ada.IO_Exceptions.Status_Error
             | Ada.IO_Exceptions.Mode_Error =>
         Close_Quietly (File);
         Raise_File_Error
           (File_Name, "cannot read the end of the file ("
            & IO_Message (E) & ")");
      when others =>
         Close_Quietly (File);
         raise;
   end Final_Byte;

   procedure Examine (File_Name : String; Disk : out Disk_State);
   --  The state of File_Name now (a copy of the file object, or another
   --  program, may have written to it since it was opened).

   procedure Examine (File_Name : String; Disk : out Disk_State) is
   begin
      Disk := (others => <>);
      Disk.Exists := Exists_As_File (File_Name);
      if Disk.Exists then
         Disk.Size := Int64 (Ada.Directories.Size (File_Name));
         Disk.Final := Final_Byte (File_Name);
      end if;
   exception
      when E : Ada.IO_Exceptions.Name_Error | Ada.IO_Exceptions.Use_Error =>
         Raise_File_Error
           (File_Name, "cannot examine the file (" & IO_Message (E) & ")");
   end Examine;

   procedure Write_Bytes
     (File_Name : String;
      Exists    : Boolean;
      Bytes     : KF.Byte_Array);
   --  Appends Bytes to File_Name, or creates it with them when it does not
   --  exist. The file is closed again whatever happens.

   procedure Write_Bytes
     (File_Name : String;
      Exists    : Boolean;
      Bytes     : KF.Byte_Array)
   is
      Output : SIO.File_Type;
      Raw    : Stream_Element_Array
                 (Stream_Element_Offset (Bytes'First)
                  .. Stream_Element_Offset (Bytes'Last))
        with Import, Address => Bytes'Address;
   begin
      if Exists then
         SIO.Open (Output, SIO.Append_File, File_Name);
      else
         SIO.Create (Output, SIO.Out_File, File_Name);
      end if;
      SIO.Write (Output, Raw);
      SIO.Close (Output);
   exception
      when E : Ada.IO_Exceptions.Name_Error
             | Ada.IO_Exceptions.Use_Error
             | Ada.IO_Exceptions.Device_Error
             | Ada.IO_Exceptions.Status_Error
             | Ada.IO_Exceptions.Mode_Error =>
         Close_Quietly (Output);
         Raise_File_Error
           (File_Name, "cannot write the file (" & IO_Message (E) & ")");
      when others =>
         Close_Quietly (Output);
         raise;
   end Write_Bytes;

   ---------------------------------------------------------------------
   --  Decoded images
   ---------------------------------------------------------------------

   package Counters is new System.Atomic_Operations.Integer_Arithmetic
     (Atomic_Type => Reference_Count);

   procedure Free is new Ada.Unchecked_Deallocation
     (Contents_Record, Contents_Record_Access);

   overriding procedure Adjust (Box : in out Contents_Box) is
   begin
      if Box.Shared /= null then
         Counters.Atomic_Add (Box.Shared.References, 1);
      end if;
   end Adjust;

   overriding procedure Finalize (Box : in out Contents_Box) is
      Status : Ks_Status;
   begin
      if Box.Shared /= null then
         if Counters.Atomic_Fetch_And_Subtract (Box.Shared.References, 1) = 1
         then
            KF.Destroy (Box.Shared.Handle, Status);
            Free (Box.Shared);
         end if;
         Box.Shared := null;
      end if;
   end Finalize;

   function Contents_Of
     (Box : Contents_Box)
      return access constant KF.Ks_Image_File_Contents_Data is
     (if Box.Shared = null then null else Box.Shared.Handle);
   --  The kernel's handle; null (no images) without a record.

   procedure Decode_File (File_Name : String; Box : in out Contents_Box);
   --  Loads and decodes File_Name into Box (a box without images).

   procedure Decode_File (File_Name : String; Box : in out Contents_Box) is
      Buffer : Byte_Buffer;
      Status : Ks_Status;
   begin
      Load (File_Name, Buffer);
      --  Owned by Box at once, so that a failure frees it.
      Box.Shared := new Contents_Record;
      KF.Decode (Buffer.Data.all, Box.Shared.Handle, Status);
      Check (Status, File_Name);
   end Decode_File;

   function Image_Count (Box : Contents_Box) return Natural;
   --  The number of decoded images.

   function Image_Count (Box : Contents_Box) return Natural is
      Count  : Int32;
      Status : Ks_Status;
   begin
      KF.Image_Count (Contents_Of (Box), Count, Status);
      Check (Status);
      return Natural (Count);
   end Image_Count;

   function Image_At
     (Contents : access constant KF.Ks_Image_File_Contents_Data;
      Index    : Natural) return Ks_Image'Class;
   --  A copy of decoded image Index, of the type the file gives it.

   function Image_At
     (Contents : access constant KF.Ks_Image_File_Contents_Data;
      Index    : Natural) return Ks_Image'Class
   is
      Image_Type, Maxval : Int32;
      Status             : Ks_Status;
   begin
      KF.Image_Info (Contents, Int32 (Index), Image_Type, Maxval, Status);
      Check (Status);
      case Image_Type is
         when KF.Image_Type_Grey_8 =>
            declare
               Handle : KI.Ks_Image_8_Grey;
            begin
               KF.Get_8_Grey (Contents, Int32 (Index), Handle, Status);
               Check (Status);
               return Kernel_Images.Adopt (Handle);
            end;
         when KF.Image_Type_Grey_16 =>
            declare
               Handle : KI.Ks_Image_16_Grey;
            begin
               KF.Get_16_Grey (Contents, Int32 (Index), Handle, Status);
               Check (Status);
               return Kernel_Images.Adopt (Handle);
            end;
         when others =>
            declare
               Red, Green, Blue : KI.Ks_Image_8_Grey;
            begin
               KF.Get_24_Planar_Color
                 (Contents, Int32 (Index), Red, Green, Blue, Status);
               Check (Status);
               return Kernel_Images.Adopt (Red, Green, Blue);
            end;
      end case;
   end Image_At;

   function Grey_8_At
     (Contents : access constant KF.Ks_Image_File_Contents_Data;
      Index    : Int32) return Ks_Image_8_Grey;
   --  Decoded image Index converted to 8-bit grey (Read_Image_8_Grey).

   function Grey_8_At
     (Contents : access constant KF.Ks_Image_File_Contents_Data;
      Index    : Int32) return Ks_Image_8_Grey
   is
      Handle : KI.Ks_Image_8_Grey;
      Status : Ks_Status;
   begin
      KF.Get_8_Grey_Converted (Contents, Index, Handle, Status);
      Check (Status);
      return Kernel_Images.Adopt (Handle);
   end Grey_8_At;

   --  Streams

   procedure Write_Contents
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Contents_Box)
   is
      Contents : constant access constant KF.Ks_Image_File_Contents_Data :=
        Contents_Of (Item);
      Count, Kind, Image_Type, Maxval : Int32;
      Status   : Ks_Status;
   begin
      KF.Image_Count (Contents, Count, Status);
      Check (Status);
      KF.Contents_Kind (Contents, Kind, Status);
      Check (Status);
      U32'Write (Stream, U32 (Count));
      U32'Write (Stream, U32 (Kind));
      for Index in 0 .. Count - 1 loop  --  SHELL: stream I/O, every image
         KF.Image_Info (Contents, Index, Image_Type, Maxval, Status);
         Check (Status);
         U32'Write (Stream, U32 (Image_Type));
         U32'Write (Stream, U32 (Maxval));
         Ks_Image'Class'Write (Stream, Image_At (Contents, Natural (Index)));
      end loop;  --  SHELL: (the loop above)
   end Write_Contents;

   procedure Read_Stored_Image
     (Stream   : not null access Ada.Streams.Root_Stream_Type'Class;
      Contents : KF.Ks_Image_File_Contents;
      Index    : Int32);
   --  Reads image Index and stores it in Contents.

   procedure Read_Stored_Image
     (Stream   : not null access Ada.Streams.Root_Stream_Type'Class;
      Contents : KF.Ks_Image_File_Contents;
      Index    : Int32)
   is
      Image_Type, Maxval : U32;
      Status             : Ks_Status;
   begin
      U32'Read (Stream, Image_Type);
      U32'Read (Stream, Maxval);
      KF.Read_Image_Header (Image_Type, Maxval, Status);
      Check (Status);
      case Int32 (Image_Type) is
         when KF.Image_Type_Grey_8 =>
            declare
               Image : Ks_Image_8_Grey;
            begin
               Ks_Image_8_Grey'Read (Stream, Image);
               KF.Store_8_Grey (Contents, Index, Int32 (Maxval),
                                Kernel_Images.Kernel_Handle (Image), Status);
            end;
         when KF.Image_Type_Grey_16 =>
            declare
               Image : Ks_Image_16_Grey;
            begin
               Ks_Image_16_Grey'Read (Stream, Image);
               KF.Store_16_Grey (Contents, Index, Int32 (Maxval),
                                 Kernel_Images.Kernel_Handle (Image),
                                 Status);
            end;
         when others =>
            declare
               Image : Ks_Image_24_Planar_Color;
            begin
               Ks_Image_24_Planar_Color'Read (Stream, Image);
               KF.Store_24_Planar_Color
                 (Contents, Index, Int32 (Maxval),
                  Kernel_Images.Kernel_Plane (Image, Red),
                  Kernel_Images.Kernel_Plane (Image, Green),
                  Kernel_Images.Kernel_Plane (Image, Blue), Status);
            end;
      end case;
      Check (Status);
   end Read_Stored_Image;

   procedure Read_Contents
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Contents_Box)
   is
      Empty       : Contents_Box;
      Fresh       : Contents_Box;
      Count, Kind : U32;
      Status      : Ks_Status;
   begin
      Item := Empty;
      U32'Read (Stream, Count);
      U32'Read (Stream, Kind);
      --  Owned by Fresh at once, so that a failure frees it.
      Fresh.Shared := new Contents_Record;
      KF.Read_Contents_Header (Count, Kind, Fresh.Shared.Handle, Status);
      Check (Status);
      for Index in 0 .. Int32 (Count) - 1 loop  --  SHELL: stream I/O
         Read_Stored_Image (Stream, Fresh.Shared.Handle, Index);
      end loop;  --  SHELL: (the loop above)
      Item := Fresh;
   end Read_Contents;

   ---------------------------------------------------------------------
   --  Writing an image
   ---------------------------------------------------------------------

   function Image_Type_Of (Image : Ks_Image'Class) return Int32 is
     (if Image in Ks_Image_8_Grey'Class then KF.Image_Type_Grey_8
      elsif Image in Ks_Image_16_Grey'Class then KF.Image_Type_Grey_16
      elsif Image in Ks_Image_24_Planar_Color'Class
      then KF.Image_Type_Color
      else 0);
   --  The kernel's code for the type of Image (0 for another type).

   procedure Encode
     (Image     : Ks_Image'Class;
      Encoding  : Int32;
      Separator : Int32;
      Bytes     : in out KF.Byte_Array);
   --  The bytes of Image (an image type the kernel accepted) as the
   --  kernel encodes them.

   procedure Encode
     (Image     : Ks_Image'Class;
      Encoding  : Int32;
      Separator : Int32;
      Bytes     : in out KF.Byte_Array)
   is
      Status : Ks_Status;
   begin
      case Image_Type_Of (Image) is
         when KF.Image_Type_Grey_8 =>
            KF.Encode_8_Grey
              (Encoding, Separator,
               Kernel_Images.Kernel_Handle (Ks_Image_8_Grey'Class (Image)),
               Bytes, Status);
         when KF.Image_Type_Grey_16 =>
            KF.Encode_16_Grey
              (Encoding, Separator,
               Kernel_Images.Kernel_Handle (Ks_Image_16_Grey'Class (Image)),
               Bytes, Status);
         when others =>
            KF.Encode_24_Planar_Color
              (Encoding, Separator,
               Kernel_Images.Kernel_Plane
                 (Ks_Image_24_Planar_Color'Class (Image), Red),
               Kernel_Images.Kernel_Plane
                 (Ks_Image_24_Planar_Color'Class (Image), Green),
               Kernel_Images.Kernel_Plane
                 (Ks_Image_24_Planar_Color'Class (Image), Blue),
               Bytes, Status);
      end case;
      Check (Status);
   end Encode;

   function Format_Of (File_Name : String) return Int32;
   --  The write format chosen by the extension of File_Name.

   function Format_Of (File_Name : String) return Int32 is
      Format : Int32;
      Status : Ks_Status;
   begin
      KF.Format_From_Name (File_Name, Format, Status);
      Check (Status, File_Name);
      return Format;
   end Format_Of;

   ---------------------------------------------------------------------
   --  Ks_Image_File
   ---------------------------------------------------------------------

   function Count_For_Update
     (File_Name : String; Format : Int32) return Natural;
   --  Update mode: the number of images File_Name holds, after checking
   --  that they are in Format; a missing file is created.

   function Count_For_Update
     (File_Name : String; Format : Int32) return Natural
   is
      Buffer : Byte_Buffer;
      Count  : Int32;
      Status : Ks_Status;
   begin
      if not Exists_As_File (File_Name) then
         Create_Empty (File_Name);
         return 0;
      end if;
      Load (File_Name, Buffer);
      KF.Count_For_Update (Format, Buffer.Data.all, Count, Status);
      Check (Status, File_Name);
      return Natural (Count);
   end Count_For_Update;

   procedure Open
     (File      : in out Ks_Image_File;
      File_Name : String;
      Mode      : Ks_Image_File_Mode_Constants)
   is
      Fresh  : Ks_Image_File;
      Status : Ks_Status;
   begin
      KF.Check_Open_Mode (Mode_Code (Mode), Status);
      Check (Status);
      Close (File);
      Fresh.Name := To_Unbounded_String (File_Name);
      case Mode is
         when Closed =>
            null;  --  Rejected above.

         when Read =>
            Decode_File (File_Name, Fresh.Contents);
            Fresh.Count := Image_Count (Fresh.Contents);

         when Write =>
            Fresh.Format := Format_Of (File_Name);
            Create_Empty (File_Name);

         when Update =>
            Fresh.Format := Format_Of (File_Name);
            Fresh.Count := Count_For_Update (File_Name, Fresh.Format);
      end case;
      Fresh.Current := Mode;
      File := Fresh;
   end Open;

   procedure Close (File : in out Ks_Image_File) is
      Default : Ks_Image_File;
   begin
      File := Default;
   end Close;

   function Is_Open (File : Ks_Image_File) return Boolean is
     (File.Current /= Closed);

   function File_Name (File : Ks_Image_File) return String is
     (To_String (File.Name));

   function Open_Mode
     (File : Ks_Image_File) return Ks_Image_File_Mode_Constants is
     (File.Current);

   function Count (File : Ks_Image_File) return Natural is (File.Count);

   function Item
     (File  : Ks_Image_File;
      Index : Natural) return AMV.Images.Ks_Image'Class
   is
      Status : Ks_Status;
   begin
      KF.Require_Open (Mode_Code (File.Current), KF.Operation_Item, Status);
      Check (Status);
      KF.Require_Mode (Mode_Code (File.Current), KF.Operation_Item, Status);
      Check (Status, To_String (File.Name));
      return Image_At (Contents_Of (File.Contents), Index);
   end Item;

   procedure Append
     (File : in out Ks_Image_File; Image : AMV.Images.Ks_Image'Class)
   is
      Name      : constant String := To_String (File.Name);
      Encoding  : Int32;
      Separator : Int32;
      New_Count : Int32;
      Size      : Int64;
      Disk      : Disk_State;
      Buffer    : Byte_Buffer;
      Status    : Ks_Status;
   begin
      KF.Require_Open (Mode_Code (File.Current), KF.Operation_Append,
                       Status);
      Check (Status);
      KF.Require_Mode (Mode_Code (File.Current), KF.Operation_Append,
                       Status);
      Check (Status, Name);
      --  Every check is made before the file is changed.
      KF.Choose_Encoding
        (File.Format, Image_Type_Of (Image), Int32 (Image.Width),
         Int32 (Image.Height), Encoding, Status);
      Check (Status, Name);
      Examine (Name, Disk);
      KF.Check_Append
        (Encoding, Int32 (File.Count), Disk.Size, Disk.Final, Separator,
         New_Count, Status);
      Check (Status, Name);
      KF.Encoded_Size
        (Encoding, Int32 (Image.Width), Int32 (Image.Height), Separator,
         Size, Status);
      Check (Status, Name);
      Buffer.Data := new KF.Byte_Array (1 .. Size);
      Encode (Image, Encoding, Separator, Buffer.Data.all);
      Write_Bytes (Name, Disk.Exists, Buffer.Data.all);
      File.Count := Natural (New_Count);
   end Append;

   function Read_Image
     (File_Name : String; Index : Natural := 0)
      return AMV.Images.Ks_Image'Class
   is
      Box    : Contents_Box;
      Status : Ks_Status;
   begin
      Decode_File (File_Name, Box);
      KF.Check_Read_Index (Contents_Of (Box), Int32 (Index), Status);
      Check (Status, File_Name);
      return Image_At (Contents_Of (Box), Index);
   end Read_Image;

   function Read_Image_8_Grey
     (File_Name : String; Index : Natural := 0)
      return AMV.Images.Ks_Image_8_Grey
   is
      Box    : Contents_Box;
      Status : Ks_Status;
   begin
      Decode_File (File_Name, Box);
      KF.Check_Read_Index (Contents_Of (Box), Int32 (Index), Status);
      Check (Status, File_Name);
      return Grey_8_At (Contents_Of (Box), Int32 (Index));
   end Read_Image_8_Grey;

   procedure Write_Image
     (File_Name : String; Image : AMV.Images.Ks_Image'Class)
   is
      File     : Ks_Image_File;
      Encoding : Int32;
      Status   : Ks_Status;
   begin
      --  Checked first so that an unsuitable image leaves an existing file
      --  untouched.
      KF.Choose_Encoding
        (Format_Of (File_Name), Image_Type_Of (Image), Int32 (Image.Width),
         Int32 (Image.Height), Encoding, Status);
      Check (Status, File_Name);
      Open (File, File_Name, Write);
      Append (File, Image);
      Close (File);
   end Write_Image;

   ---------------------------------------------------------------------
   --  Ks_Image_File_Tool
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_Image_File_Tool) is
      Status : Ks_Status;
   begin
      KF.Require_Open (Mode_Code (Tool.Operator.Current), KF.Operation_Run,
                       Status);
      Check (Status);
      case Tool.Operator.Current is
         when Closed =>
            null;  --  Rejected above.
         when Read =>
            declare
               Index, Next : Int32;
            begin
               KF.Tool_Next_Index
                 (Int32 (Tool.Next_Index), Int32 (Tool.Operator.Count),
                  Index, Next, Status);
               Check (Status, To_String (Tool.Operator.Name));
               Tool.Output_Image :=
                 Grey_8_At (Contents_Of (Tool.Operator.Contents), Index);
               Tool.Next_Index := Natural (Next);
            end;
         when Write | Update =>
            --  The kernel rejects an image without pixels
            --  (Ks_Image_No_Pixels_Exception).
            Tool.Operator.Append (Tool.Input_Image);
      end case;
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Image_File_Tool) is
      Empty : AMV.Images.Ks_Image_8_Grey;
   begin
      if Tool.Operator.Current = Read then
         Tool.Output_Image := Empty;
      end if;
   end Reset_Results;

end AMV.Image_File;
