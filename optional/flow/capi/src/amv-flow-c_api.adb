pragma SPARK_Mode (Off);

with Ada.Exceptions;
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;

with AMV.Flow.C_API.Extensions;
with AMV.Flow.Graphs;
with AMV.Flow.Reports;
with AMV.Flow.Values;
with AMV.Image_File;
with AMV.Images;

package body AMV.Flow.C_API is

   use type System.Address;

   Bad_Argument : exception;
   --  Raised inside for a NULL pointer, a bad size or a small buffer.

   type Flow_Access is access AMV.Flow.Graphs.Ks_Flow;

   function To_Flow is new Ada.Unchecked_Conversion
     (System.Address, Flow_Access);
   function To_Address is new Ada.Unchecked_Conversion
     (Flow_Access, System.Address);
   procedure Free is new Ada.Unchecked_Deallocation
     (AMV.Flow.Graphs.Ks_Flow, Flow_Access);

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   procedure Set (Status  : out Amvf_Status;
                  Failure : Integer_32;
                  Message : String)
   is
      Length : Natural := Natural'Min (Message'Length, Max_Message_Length);
   begin
      --  Do not cut a UTF-8 sequence in the middle.
      while Length > 0 and then Length < Message'Length
        and then Character'Pos (Message (Message'First + Length))
                 in 16#80# .. 16#BF#
      loop
         Length := Length - 1;
      end loop;
      Status.Failure := Failure;
      Status.Length := Integer_32 (Length);
      Status.Message := [others => nul];
      for I in 0 .. Length - 1 loop
         Status.Message (size_t (I)) := To_C (Message (Message'First + I));
      end loop;
   end Set;

   procedure OK (Status : out Amvf_Status) is
   begin
      Set (Status, Failure_None, "");
   end OK;

   procedure Fail_From (Status : out Amvf_Status;
                        E      : Ada.Exceptions.Exception_Occurrence)
   is
      use Ada.Exceptions;
      Id      : constant Exception_Id := Exception_Identity (E);
      Message : constant String := Exception_Message (E);
   begin
      if Id = Ks_Flow_Exception'Identity then
         Set (Status, Failure_Flow, Message);
      elsif Id = Bad_Argument'Identity then
         Set (Status, Failure_Bad_Argument, Message);
      elsif Id = AMV.Ks_Exception'Identity
        or else Id = AMV.Ks_Image_No_Pixels_Exception'Identity
        or else Id = AMV.Ks_Image_Bad_Selected_Space_Name_Exception'Identity
        or else Id = AMV.Ks_Operator_Not_Trained_Exception'Identity
        or else Id = AMV.Ks_Transform_Singular_Exception'Identity
        or else Id = AMV.Ks_Image_File_Exception'Identity
        or else Id = AMV.Ks_Bad_Parameter_Exception'Identity
      then
         Set (Status, Failure_AMV, Message);
      elsif Id = Storage_Error'Identity then
         Set (Status, Failure_Out_Of_Memory, "out of memory");
      else
         Set (Status, Failure_Internal, Exception_Name (E) & ": " & Message);
      end if;
   end Fail_From;

   function Get (Flow : System.Address) return Flow_Access is
   begin
      if Flow = System.Null_Address then
         raise Bad_Argument with "the flow handle is NULL";
      end if;
      return To_Flow (Flow);
   end Get;

   function Text (P : chars_ptr; What : String) return String is
   begin
      if P = Null_Ptr then
         raise Bad_Argument with What & " is NULL";
      end if;
      return Value (P);
   end Text;

   function Node_Id (Node : Integer_64) return Positive is
   begin
      if Node < 1 or else Node > AMV.Flow.Graphs.Max_Node_Id then
         raise Bad_Argument with "no node" & Node'Image;
      end if;
      return Positive (Node);
   end Node_Id;

   procedure Put_Text (Text     : String;
                       Buffer   : System.Address;
                       Capacity : Integer_64)
   is
      Size : constant Integer_64 := Integer_64 (Text'Length) + 1;
   begin
      if Capacity = 0 then
         return;  --  only the size was asked for
      elsif Capacity < 0 then
         raise Bad_Argument with "the capacity is negative";
      elsif Buffer = System.Null_Address then
         raise Bad_Argument with "the buffer is NULL";
      elsif Capacity < Size then
         raise Bad_Argument with
           "the buffer holds" & Capacity'Image & " bytes;" & Size'Image
           & " are needed";
      end if;
      declare
         Target : char_array (0 .. size_t (Text'Length))
           with Import, Address => Buffer;
      begin
         for I in Text'Range loop
            Target (size_t (I - Text'First)) := To_C (Text (I));
         end loop;
         Target (size_t (Text'Length)) := nul;
      end;
   end Put_Text;

   --  The procedures that return text keep the size needed in a local
   --  variable and copy it to Needed also when Put_Text raises, so that a
   --  caller with a small buffer learns the size.

   ---------------------------------------------------------------------
   --  The API
   ---------------------------------------------------------------------

   function Abi_Version return Integer_32 is (C_ABI_Version);

   procedure Kinds_JSON
     (Buffer : System.Address; Capacity : Integer_64;
      Needed : out Integer_64; Status : out Amvf_Status)
   is
      Size : Integer_64 := 0;
   begin
      OK (Status);
      declare
         Text_Out : constant String := AMV.Flow.Reports.Kinds_JSON;
      begin
         Size := Integer_64 (Text_Out'Length) + 1;
         Put_Text (Text_Out, Buffer, Capacity);
      end;
      Needed := Size;
   exception
      when E : others =>
         Needed := Size;
         Fail_From (Status, E);
   end Kinds_JSON;

   function Flow_Create (Status : out Amvf_Status) return System.Address is
   begin
      OK (Status);
      return To_Address (new AMV.Flow.Graphs.Ks_Flow);
   exception
      when E : others =>
         Fail_From (Status, E);
         return System.Null_Address;
   end Flow_Create;

   procedure Flow_Destroy (Flow : System.Address) is
      F : Flow_Access := To_Flow (Flow);
   begin
      if Flow /= System.Null_Address then
         Free (F);
      end if;
   exception
      when others =>
         null;  --  nothing can be reported
   end Flow_Destroy;

   procedure Flow_Load
     (Flow : System.Address; Path : chars_ptr; Status : out Amvf_Status) is
   begin
      OK (Status);
      Get (Flow).Load (Text (Path, "the path"));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Load;

   procedure Flow_Save
     (Flow : System.Address; Path : chars_ptr; Status : out Amvf_Status) is
   begin
      OK (Status);
      Get (Flow).Save (Text (Path, "the path"));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Save;

   procedure Flow_To_JSON
     (Flow   : System.Address; Buffer : System.Address;
      Capacity : Integer_64; Needed : out Integer_64;
      Status : out Amvf_Status)
   is
      Size : Integer_64 := 0;
   begin
      OK (Status);
      declare
         Text_Out : constant String := Get (Flow).To_JSON;
      begin
         Size := Integer_64 (Text_Out'Length) + 1;
         Put_Text (Text_Out, Buffer, Capacity);
      end;
      Needed := Size;
   exception
      when E : others =>
         Needed := Size;
         Fail_From (Status, E);
   end Flow_To_JSON;

   procedure Flow_From_JSON
     (Flow   : System.Address; Text : chars_ptr; Base_Directory : chars_ptr;
      Status : out Amvf_Status) is
   begin
      OK (Status);
      Get (Flow).From_JSON
        (C_API.Text (Text, "the JSON"),
         (if Base_Directory = Null_Ptr then "" else Value (Base_Directory)));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_From_JSON;

   procedure Flow_Set_Base_Directory
     (Flow : System.Address; Directory : chars_ptr; Status : out Amvf_Status)
   is
   begin
      OK (Status);
      Get (Flow).Set_Base_Directory (Text (Directory, "the directory"));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Set_Base_Directory;

   function Flow_Add_Node
     (Flow : System.Address; Kind : chars_ptr; X, Y : double;
      Status : out Amvf_Status) return Integer_64
   is
      F  : Flow_Access;
      Id : Positive;
   begin
      OK (Status);
      F := Get (Flow);
      Id := F.Add_Node (Text (Kind, "the kind"));
      begin
         F.Node (Id).Set_Position (Real (X), Real (Y));
      exception
         when others =>
            F.Remove_Node (Id);
            raise;
      end;
      return Integer_64 (Id);
   exception
      when E : others =>
         Fail_From (Status, E);
         return 0;
   end Flow_Add_Node;

   procedure Flow_Remove_Node
     (Flow : System.Address; Node : Integer_64; Status : out Amvf_Status) is
   begin
      OK (Status);
      Get (Flow).Remove_Node (Node_Id (Node));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Remove_Node;

   procedure Flow_Set_Node_Position
     (Flow : System.Address; Node : Integer_64; X, Y : double;
      Status : out Amvf_Status) is
   begin
      OK (Status);
      Get (Flow).Node (Node_Id (Node)).Set_Position (Real (X), Real (Y));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Set_Node_Position;

   procedure Flow_Set_Node_Name
     (Flow : System.Address; Node : Integer_64; Name : chars_ptr;
      Status : out Amvf_Status) is
   begin
      OK (Status);
      Get (Flow).Node (Node_Id (Node)).Set_Name (Text (Name, "the name"));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Set_Node_Name;

   procedure Flow_Link
     (Flow : System.Address; From, To : chars_ptr; Status : out Amvf_Status)
   is
   begin
      OK (Status);
      Get (Flow).Link (Text (From, "from"), Text (To, "to"));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Link;

   procedure Flow_Unlink
     (Flow : System.Address; To : chars_ptr; Status : out Amvf_Status) is
   begin
      OK (Status);
      Get (Flow).Unlink (Text (To, "to"));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Unlink;

   procedure Flow_Set_Param_JSON
     (Flow : System.Address; Node : Integer_64; Name, Value_JSON : chars_ptr;
      Status : out Amvf_Status) is
   begin
      OK (Status);
      Get (Flow).Set_Param_JSON
        (Node_Id (Node), Text (Name, "the name"),
         Text (Value_JSON, "the value"));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Set_Param_JSON;

   procedure Flow_Add_Input
     (Flow : System.Address; Name, Type_Name : chars_ptr;
      Status : out Amvf_Status) is
   begin
      OK (Status);
      Get (Flow).Add_Input
        (Text (Name, "the name"), Type_Of (Text (Type_Name, "the type")));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Add_Input;

   procedure Flow_Add_Output
     (Flow : System.Address; Name, Type_Name : chars_ptr;
      Status : out Amvf_Status) is
   begin
      OK (Status);
      Get (Flow).Add_Output
        (Text (Name, "the name"), Type_Of (Text (Type_Name, "the type")));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Add_Output;

   procedure Flow_Problems_JSON
     (Flow   : System.Address; Buffer : System.Address;
      Capacity : Integer_64; Needed : out Integer_64;
      Status : out Amvf_Status)
   is
      Size : Integer_64 := 0;
   begin
      OK (Status);
      declare
         Text_Out : constant String :=
           AMV.Flow.Reports.Problems_JSON (Get (Flow).all);
      begin
         Size := Integer_64 (Text_Out'Length) + 1;
         Put_Text (Text_Out, Buffer, Capacity);
      end;
      Needed := Size;
   exception
      when E : others =>
         Needed := Size;
         Fail_From (Status, E);
   end Flow_Problems_JSON;

   procedure Flow_Set_Input_Image_8
     (Flow   : System.Address; Input : chars_ptr;
      Width, Height, Stride : Integer_32; Pixels : System.Address;
      Status : out Amvf_Status)
   is
      Max_Side : constant := 100_000;
   begin
      OK (Status);
      if Width < 1 or else Height < 1 or else Width > Max_Side
        or else Height > Max_Side
        or else Integer_64 (Width) * Integer_64 (Height) > 2**30
      then
         raise Bad_Argument with "the image size must be 1 .. 100000 a side";
      elsif Stride < Width then
         raise Bad_Argument with "the stride is less than the width";
      elsif Integer_64 (Stride) * Integer_64 (Height - 1) + Integer_64 (Width)
              > Integer_64 (Integer'Last)
      then
         raise Bad_Argument with "the stride is too large for the height";
      elsif Pixels = System.Null_Address then
         raise Bad_Argument with "the pixels are NULL";
      end if;
      declare
         W      : constant Natural := Natural (Width);
         H      : constant Natural := Natural (Height);
         S      : constant Natural := Natural (Stride);
         type Bytes is array (0 .. S * (H - 1) + W - 1) of Unsigned_8
           with Convention => C;
         Source : Bytes with Import, Address => Pixels;
         Image  : AMV.Images.Ks_Image_8_Grey := AMV.Images.Create (W, H);
         Row    : AMV.Images.Grey_8_Row (0 .. W - 1);
      begin
         for Y in 0 .. H - 1 loop
            for X in 0 .. W - 1 loop
               Row (X) := Source (Y * S + X);
            end loop;
            Image.Set_Row (Y, Row);
         end loop;
         Get (Flow).Set_Input (Text (Input, "the input"),
                               AMV.Flow.Values.From_Image (Image));
      end;
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Set_Input_Image_8;

   procedure Flow_Set_Input_Image_File
     (Flow : System.Address; Input, Path : chars_ptr;
      Status : out Amvf_Status) is
   begin
      OK (Status);
      Get (Flow).Set_Input
        (Text (Input, "the input"),
         AMV.Flow.Values.From_Image
           (AMV.Image_File.Read_Image_8_Grey (Text (Path, "the path"))));
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Set_Input_Image_File;

   procedure Flow_Run (Flow : System.Address; Status : out Amvf_Status) is
   begin
      OK (Status);
      Get (Flow).Run;
   exception
      when E : others =>
         Fail_From (Status, E);
   end Flow_Run;

   procedure Flow_Results_JSON
     (Flow   : System.Address; Buffer : System.Address;
      Capacity : Integer_64; Needed : out Integer_64;
      Status : out Amvf_Status)
   is
      Size : Integer_64 := 0;
   begin
      OK (Status);
      declare
         Text_Out : constant String :=
           AMV.Flow.Reports.Results_JSON (Get (Flow).all);
      begin
         Size := Integer_64 (Text_Out'Length) + 1;
         Put_Text (Text_Out, Buffer, Capacity);
      end;
      Needed := Size;
   exception
      when E : others =>
         Needed := Size;
         Fail_From (Status, E);
   end Flow_Results_JSON;

   procedure Node_Graphics_JSON
     (Flow   : System.Address; Node : Integer_64; Buffer : System.Address;
      Capacity : Integer_64; Needed : out Integer_64;
      Status : out Amvf_Status)
   is
      Size : Integer_64 := 0;
      F    : Flow_Access;
   begin
      OK (Status);
      F := Get (Flow);
      if not F.Contains (Node_Id (Node)) then
         raise Bad_Argument with "no node" & Node'Image;
      end if;
      declare
         Text_Out : constant String :=
           AMV.Flow.Reports.Graphics_JSON (F.all, Node_Id (Node));
      begin
         Size := Integer_64 (Text_Out'Length) + 1;
         Put_Text (Text_Out, Buffer, Capacity);
      end;
      Needed := Size;
   exception
      when E : others =>
         Needed := Size;
         Fail_From (Status, E);
   end Node_Graphics_JSON;

   procedure Node_Image_BGRA
     (Flow   : System.Address; Node : Integer_64; Buffer : System.Address;
      Capacity : Integer_64; Width, Height : out Integer_32;
      Status : out Amvf_Status)
   is
      F : Flow_Access;
   begin
      Width := 0;
      Height := 0;
      OK (Status);
      F := Get (Flow);
      if not F.Contains (Node_Id (Node)) then
         raise Bad_Argument with "no node" & Node'Image;
      end if;
      declare
         Value : constant AMV.Flow.Values.Ks_Flow_Value :=
           AMV.Flow.Reports.Node_Image (F.all, Node_Id (Node));
      begin
         if not Value.Has_Value then
            return;
         end if;
         declare
            Image : constant AMV.Images.Ks_Image_8_Grey := Value.As_Image;
            W     : constant Natural := Image.Width;
            H     : constant Natural := Image.Height;
            Need  : constant Integer_64 := Integer_64 (W) * Integer_64 (H) * 4;
         begin
            Width := Integer_32 (W);
            Height := Integer_32 (H);
            if Capacity = 0 or else Need = 0 then
               return;
            elsif Buffer = System.Null_Address or else Capacity < Need then
               raise Bad_Argument with
                 "the buffer holds" & Capacity'Image & " bytes;"
                 & Need'Image & " are needed";
            end if;
            declare
               type Bytes is array (0 .. Need - 1) of Unsigned_8
                 with Convention => C;
               Target : Bytes with Import, Address => Buffer;
               Row    : AMV.Images.Grey_8_Row (0 .. W - 1);
               K      : Integer_64;
            begin
               for Y in 0 .. H - 1 loop
                  Image.Get_Row (Y, Row);
                  K := Integer_64 (Y) * Integer_64 (W) * 4;
                  for X in 0 .. W - 1 loop
                     Target (K) := Row (X);
                     Target (K + 1) := Row (X);
                     Target (K + 2) := Row (X);
                     Target (K + 3) := 255;
                     K := K + 4;
                  end loop;
               end loop;
            end;
         end;
      end;
   exception
      when E : others =>
         Fail_From (Status, E);
   end Node_Image_BGRA;

begin
   Extensions.Register;
end AMV.Flow.C_API;
