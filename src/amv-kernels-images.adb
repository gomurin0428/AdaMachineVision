pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;

package body AMV.Kernels.Images with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  As in the spec: the prefixes are total ghost functions.

   Identity : constant KT.Ks_Transform_2D_Linear := (others => <>);

   Empty_Name : constant KC.Ks_Space_Name := (others => <>);

   procedure Free is new Ada.Unchecked_Deallocation
     (Grey_8_Matrix, Grey_8_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Image_8_Grey_Data, Ks_Image_8_Grey);
   procedure Free is new Ada.Unchecked_Deallocation
     (Grey_16_Matrix, Grey_16_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Image_16_Grey_Data, Ks_Image_16_Grey);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate
     (Width, Height : Int32;
      Image         : out Ks_Image_8_Grey)
   with
     Global => null,
     Pre    => Width >= 1 and then Height >= 1,
     Post   => (if Image /= null
                then Valid_Image (Image)
                     and then Image.Width = Width
                     and then Image.Height = Height);
   --  A new handle of Width x Height pixels whose values are unspecified
   --  (any Grey_8 value is valid), or null when the memory cannot be
   --  allocated. Trusted: the allocators raise Storage_Error, which SPARK
   --  cannot express; nothing is leaked when the second one fails.

   procedure Allocate
     (Width, Height : Int32;
      Image         : out Ks_Image_8_Grey)
     with SPARK_Mode => Off
   is
      Pixels : Grey_8_Pixels := null;
   begin
      Pixels := new Grey_8_Matrix
        (0 .. Natural (Height) - 1, 0 .. Natural (Width) - 1);
      Image := new Ks_Image_8_Grey_Data'
        (Width => Width, Height => Height, Pixels => Pixels);
   exception
      when Storage_Error =>
         Free (Pixels);
         Image := null;
   end Allocate;

   procedure Allocate
     (Width, Height : Int32;
      Image         : out Ks_Image_16_Grey)
   with
     Global => null,
     Pre    => Width >= 1 and then Height >= 1,
     Post   => (if Image /= null
                then Valid_Image (Image)
                     and then Image.Width = Width
                     and then Image.Height = Height);

   procedure Allocate
     (Width, Height : Int32;
      Image         : out Ks_Image_16_Grey)
     with SPARK_Mode => Off
   is
      Pixels : Grey_16_Pixels := null;
   begin
      Pixels := new Grey_16_Matrix
        (0 .. Natural (Height) - 1, 0 .. Natural (Width) - 1);
      Image := new Ks_Image_16_Grey_Data'
        (Width => Width, Height => Height, Pixels => Pixels);
   exception
      when Storage_Error =>
         Free (Pixels);
         Image := null;
   end Allocate;

   function Finite_Bits (Bits : U64) return Boolean is
     ((Interfaces.Shift_Right (Bits, 52) and 16#7FF#) /= 16#7FF#);
   --  False for the IEEE 754 binary64 infinities and NaNs, whose exponent
   --  bits are all ones.

   function To_Long_Float (Bits : U64) return Long_Float
   with Global => null, Pre => Finite_Bits (Bits);
   --  The binary64 value with these bits. Trusted: SPARK does not allow an
   --  unchecked conversion to a floating-point type, since some bit
   --  patterns are not finite numbers; the precondition (checked at run
   --  time too) excludes exactly those.

   function To_Long_Float (Bits : U64) return Long_Float
     with SPARK_Mode => Off
   is
      function Convert is new Ada.Unchecked_Conversion (U64, Long_Float);
   begin
      return Convert (Bits);
   end To_Long_Float;

   ---------------------------------------------------------------------
   --  Messages and failures
   ---------------------------------------------------------------------

   function Image_Of (Value : Int64) return String
   with Pre  => Value > Int64'First,
        Post => Image_Of'Result'First = 1
                and then Image_Of'Result'Length in 1 .. 20;
   --  The decimal digits of Value, with a leading '-' when it is negative
   --  (Value'Image without the blank of a non-negative number).

   function Image_Of (Value : Int64) return String is
      Text  : String (1 .. 20) := [others => '0'];
      Rest  : Int64 := abs Value;
      First : Positive;
   begin
      --  At most 19 digits; the first character is left for the sign.
      for K in reverse 2 .. 20 loop
         Text (K) := Character'Val (Character'Pos ('0') + Rest mod 10);
         Rest := Rest / 10;
         First := K;
         exit when Rest = 0;
         pragma Loop_Invariant (First = K and then Rest >= 1);
      end loop;
      if Value < 0 then
         First := First - 1;
         Text (First) := '-';
      end if;
      declare
         Last   : constant Natural := 21 - First;
         Result : constant String (1 .. Last) := Text (First .. 20);
      begin
         return Result;
      end;
   end Image_Of;

   function Image_Of (Value : Int32) return String is
     (Image_Of (Int64 (Value)))
   with Post => Image_Of'Result'First = 1
                and then Image_Of'Result'Length in 1 .. 20;

   subtype Operation_Name is String
     with Dynamic_Predicate =>
       Operation_Name'First = 1 and then Operation_Name'Length <= 40;
   --  The name of the operation that starts a message.

   procedure No_Pixels
     (Operation : Operation_Name;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Image_No_Pixels;
   --  "<Operation>: the image has no pixels".

   procedure No_Pixels
     (Operation : Operation_Name;
      Status    : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Image_No_Pixels,
                   Operation & ": the image has no pixels");
   end No_Pixels;

   procedure Bad_Handle
     (Operation : Operation_Name;
      Argument  : String;
      Status    : out Ks_Status)
   with Pre  => Argument'Length <= 20,
        Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;
   --  "<Operation>: <Argument> is not a valid image handle".

   procedure Bad_Handle
     (Operation : Operation_Name;
      Argument  : String;
      Status    : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter,
                   Operation & ": " & Argument
                   & " is not a valid image handle");
   end Bad_Handle;

   procedure Out_Of_Memory
     (Operation     : Operation_Name;
      Width, Height : Int32;
      Status        : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Out_Of_Memory;

   procedure Out_Of_Memory
     (Operation     : Operation_Name;
      Width, Height : Int32;
      Status        : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Out_Of_Memory,
                   Operation & ": not enough memory for a "
                   & Image_Of (Width) & " x " & Image_Of (Height)
                   & " image");
   end Out_Of_Memory;

   procedure Check_Size
     (Operation     : Operation_Name;
      Width, Height : Int32;
      Status        : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Width >= 1 and then Height >= 1
                               and then Int64 (Width) * Int64 (Height)
                                          <= Max_Pixels);
   --  Bad_Parameter unless the size can be allocated.

   procedure Check_Size
     (Operation     : Operation_Name;
      Width, Height : Int32;
      Status        : out Ks_Status) is
   begin
      if Width < 1 or else Height < 1 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": Width and Height must be at least 1 ("
                      & Image_Of (Width) & " x " & Image_Of (Height)
                      & " given)");
      elsif Int64 (Width) * Int64 (Height) > Max_Pixels then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": the image size " & Image_Of (Width)
                      & " x " & Image_Of (Height) & " is too large");
      else
         Set_Success (Status);
      end if;
   end Check_Size;

   procedure Check_Pixel
     (Operation           : Operation_Name;
      X, Y, Width, Height : Int32;
      Status              : out Ks_Status)
   with Pre  => Width >= 1 and then Height >= 1,
        Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Index_Out_Of_Range
                and then (if Succeeded (Status)
                          then X in 0 .. Width - 1
                               and then Y in 0 .. Height - 1);
   --  Index_Out_Of_Range unless (X, Y) is a pixel of a Width x Height
   --  image.

   procedure Check_Pixel
     (Operation           : Operation_Name;
      X, Y, Width, Height : Int32;
      Status              : out Ks_Status) is
   begin
      if X in 0 .. Width - 1 and then Y in 0 .. Height - 1 then
         Set_Success (Status);
      else
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      Operation & ": pixel (" & Image_Of (X) & ", "
                      & Image_Of (Y) & ") is outside the "
                      & Image_Of (Width) & " x " & Image_Of (Height)
                      & " image");
      end if;
   end Check_Pixel;

   procedure Check_Row
     (Operation     : Operation_Name;
      Y             : Int32;
      Length        : Int64;
      Width, Height : Int32;
      Status        : out Ks_Status)
   with Pre  => Width >= 1 and then Height >= 1
                and then Length >= Int64 (Int32'First),
        Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Index_Out_Of_Range
                and then (if Succeeded (Status)
                          then Y in 0 .. Height - 1
                               and then Length = Int64 (Width));
   --  Index_Out_Of_Range unless Y is a row of a Width x Height image and
   --  the row array has Width elements.

   procedure Check_Row
     (Operation     : Operation_Name;
      Y             : Int32;
      Length        : Int64;
      Width, Height : Int32;
      Status        : out Ks_Status) is
   begin
      if Y not in 0 .. Height - 1 then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      Operation & ": row " & Image_Of (Y)
                      & " is outside the " & Image_Of (Width) & " x "
                      & Image_Of (Height) & " image");
      elsif Length /= Int64 (Width) then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      Operation & ": the row array has "
                      & Image_Of (Length) & " elements but the image is "
                      & Image_Of (Width) & " pixels wide");
      else
         Set_Success (Status);
      end if;
   end Check_Row;

   procedure Check_Image
     (Image     : access constant Ks_Image_8_Grey_Data;
      Operation : Operation_Name;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                and then (if Succeeded (Status) then Valid_Image (Image));
   --  Image_No_Pixels for null, Bad_Parameter for an inconsistent handle.

   procedure Check_Image
     (Image     : access constant Ks_Image_8_Grey_Data;
      Operation : Operation_Name;
      Status    : out Ks_Status) is
   begin
      if Image = null then
         No_Pixels (Operation, Status);
      elsif not Valid_Image (Image) then
         Bad_Handle (Operation, "Image", Status);
      else
         Set_Success (Status);
      end if;
   end Check_Image;

   procedure Check_Image
     (Image     : access constant Ks_Image_16_Grey_Data;
      Operation : Operation_Name;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                and then (if Succeeded (Status) then Valid_Image (Image));

   procedure Check_Image
     (Image     : access constant Ks_Image_16_Grey_Data;
      Operation : Operation_Name;
      Status    : out Ks_Status) is
   begin
      if Image = null then
         No_Pixels (Operation, Status);
      elsif not Valid_Image (Image) then
         Bad_Handle (Operation, "Image", Status);
      else
         Set_Success (Status);
      end if;
   end Check_Image;

   ---------------------------------------------------------------------
   --  Pixel helpers
   ---------------------------------------------------------------------

   procedure Fill_All (Image : Ks_Image_8_Grey; Value : Grey_8)
   with
     Pre  => Valid_Image (Image),
     Post => Valid_Image (Image)
             and then Size_Of (Image) = Size_Of (Image)'Old
             and then (for all Y in Image.Pixels'Range (1)
                       => (for all X in Image.Pixels'Range (2)
                           => Image.Pixels (Y, X) = Value));

   procedure Fill_All (Image : Ks_Image_8_Grey; Value : Grey_8) is
   begin
      for Y in Image.Pixels'Range (1) loop
         for X in Image.Pixels'Range (2) loop
            Image.Pixels (Y, X) := Value;
            pragma Loop_Invariant
              (Valid_Image (Image)
               and then Size_Of (Image) = Size_Of (Image)'Loop_Entry);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Image.Pixels'Range (2)
                   => Image.Pixels (J, I) = Value));
            pragma Loop_Invariant
              (for all I in 0 .. X => Image.Pixels (Y, I) = Value);
         end loop;
         pragma Loop_Invariant
           (Valid_Image (Image)
            and then Size_Of (Image) = Size_Of (Image)'Loop_Entry);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Image.Pixels'Range (2)
                => Image.Pixels (J, I) = Value));
      end loop;
   end Fill_All;

   procedure Fill_All (Image : Ks_Image_16_Grey; Value : Grey_16)
   with
     Pre  => Valid_Image (Image),
     Post => Valid_Image (Image)
             and then Size_Of (Image) = Size_Of (Image)'Old
             and then (for all Y in Image.Pixels'Range (1)
                       => (for all X in Image.Pixels'Range (2)
                           => Image.Pixels (Y, X) = Value));

   procedure Fill_All (Image : Ks_Image_16_Grey; Value : Grey_16) is
   begin
      for Y in Image.Pixels'Range (1) loop
         for X in Image.Pixels'Range (2) loop
            Image.Pixels (Y, X) := Value;
            pragma Loop_Invariant
              (Valid_Image (Image)
               and then Size_Of (Image) = Size_Of (Image)'Loop_Entry);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Image.Pixels'Range (2)
                   => Image.Pixels (J, I) = Value));
            pragma Loop_Invariant
              (for all I in 0 .. X => Image.Pixels (Y, I) = Value);
         end loop;
         pragma Loop_Invariant
           (Valid_Image (Image)
            and then Size_Of (Image) = Size_Of (Image)'Loop_Entry);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Image.Pixels'Range (2)
                => Image.Pixels (J, I) = Value));
      end loop;
   end Fill_All;

   procedure Release (Image : in out Ks_Image_8_Grey)
   with Post => Image = null;
   --  Frees Image (if any).

   procedure Release (Image : in out Ks_Image_8_Grey) is
   begin
      if Image /= null then
         Free (Image.Pixels);
         Free (Image);
      end if;
   end Release;

   procedure Release (Image : in out Ks_Image_16_Grey)
   with Post => Image = null;

   procedure Release (Image : in out Ks_Image_16_Grey) is
   begin
      if Image /= null then
         Free (Image.Pixels);
         Free (Image);
      end if;
   end Release;

   ---------------------------------------------------------------------
   --  8-bit grey images
   ---------------------------------------------------------------------

   procedure Create
     (Width, Height : Int32;
      Value         : Grey_8;
      Image         : out Ks_Image_8_Grey;
      Status        : out Ks_Status) is
   begin
      Image := null;
      Check_Size ("Create", Width, Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Allocate (Width, Height, Image);
      if Image = null then
         Out_Of_Memory ("Create", Width, Height, Status);
         return;
      end if;
      Fill_All (Image, Value);
   end Create;

   procedure Destroy
     (Image  : in out Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      Release (Image);
      Set_Success (Status);
   end Destroy;

   procedure Width
     (Image  : access constant Ks_Image_8_Grey_Data;
      Result : out Int32;
      Status : out Ks_Status) is
   begin
      Result := 0;
      if Image = null then
         Set_Success (Status);
      elsif not Valid_Image (Image) then
         Bad_Handle ("Width", "Image", Status);
      else
         Result := Image.Width;
         Set_Success (Status);
      end if;
   end Width;

   procedure Height
     (Image  : access constant Ks_Image_8_Grey_Data;
      Result : out Int32;
      Status : out Ks_Status) is
   begin
      Result := 0;
      if Image = null then
         Set_Success (Status);
      elsif not Valid_Image (Image) then
         Bad_Handle ("Height", "Image", Status);
      else
         Result := Image.Height;
         Set_Success (Status);
      end if;
   end Height;

   procedure Get_Pixel
     (Image  : access constant Ks_Image_8_Grey_Data;
      X, Y   : Int32;
      Value  : out Grey_8;
      Status : out Ks_Status) is
   begin
      Value := 0;
      Check_Image (Image, "Get_Pixel", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Pixel ("Get_Pixel", X, Y, Image.Width, Image.Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Value := Image.Pixels (Natural (Y), Natural (X));
   end Get_Pixel;

   procedure Set_Pixel
     (Image  : Ks_Image_8_Grey;
      X, Y   : Int32;
      Value  : Grey_8;
      Status : out Ks_Status) is
   begin
      Check_Image (Image, "Set_Pixel", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Pixel ("Set_Pixel", X, Y, Image.Width, Image.Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Image.Pixels (Natural (Y), Natural (X)) := Value;
   end Set_Pixel;

   procedure Fill
     (Image  : Ks_Image_8_Grey;
      Value  : Grey_8;
      Status : out Ks_Status) is
   begin
      Check_Image (Image, "Fill", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Fill_All (Image, Value);
   end Fill;

   procedure Duplicate
     (Image  : access constant Ks_Image_8_Grey_Data;
      Result : out Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      Result := null;
      if Image = null then
         Set_Success (Status);
         return;
      elsif not Valid_Image (Image) then
         Bad_Handle ("Duplicate", "Image", Status);
         return;
      end if;
      Allocate (Image.Width, Image.Height, Result);
      if Result = null then
         Out_Of_Memory ("Duplicate", Image.Width, Image.Height, Status);
         return;
      end if;
      Result.Pixels.all := Image.Pixels.all;
      Set_Success (Status);
   end Duplicate;

   procedure Check_Row_Request
     (Image     : access constant Ks_Image_8_Grey_Data;
      Operation : Operation_Name;
      Y         : Int32;
      Length    : Int32;
      Null_Row  : Boolean;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                            | Failure_Index_Out_Of_Range
                and then (if Succeeded (Status)
                          then Valid_Image (Image)
                               and then Y in 0 .. Image.Height - 1
                               and then Length = Image.Width
                               and then not Null_Row);
   --  The checks of the C row functions, in their documented order.

   procedure Check_Row_Request
     (Image     : access constant Ks_Image_8_Grey_Data;
      Operation : Operation_Name;
      Y         : Int32;
      Length    : Int32;
      Null_Row  : Boolean;
      Status    : out Ks_Status) is
   begin
      Check_Image (Image, Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Row (Operation, Y, Int64 (Length), Image.Width, Image.Height,
                 Status);
      if Succeeded (Status) and then Null_Row then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": Row must not be null");
      end if;
   end Check_Row_Request;

   procedure Get_Row
     (Image  : access constant Ks_Image_8_Grey_Data;
      Y      : Int32;
      Row    : System.Address;
      Length : Int32;
      Status : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
   begin
      Check_Row_Request (Image, "Get_Row", Y, Length,
                         Row = System.Null_Address, Status);
      if Succeeded (Status) then
         declare
            Target : Grey_8_Row (0 .. Natural (Length) - 1)
              with Import, Address => Row;
         begin
            Get_Row (Image, Y, Target, Status);
         end;
      end if;
   end Get_Row;

   procedure Set_Row
     (Image  : Ks_Image_8_Grey;
      Y      : Int32;
      Row    : System.Address;
      Length : Int32;
      Status : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
   begin
      Check_Row_Request (Image, "Set_Row", Y, Length,
                         Row = System.Null_Address, Status);
      if Succeeded (Status) then
         declare
            Source : Grey_8_Row (0 .. Natural (Length) - 1)
              with Import, Address => Row;
         begin
            Set_Row (Image, Y, Source, Status);
         end;
      end if;
   end Set_Row;

   ---------------------------------------------------------------------
   --  16-bit grey images
   ---------------------------------------------------------------------

   procedure Create
     (Width, Height : Int32;
      Value         : Grey_16;
      Image         : out Ks_Image_16_Grey;
      Status        : out Ks_Status) is
   begin
      Image := null;
      Check_Size ("Create", Width, Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Allocate (Width, Height, Image);
      if Image = null then
         Out_Of_Memory ("Create", Width, Height, Status);
         return;
      end if;
      Fill_All (Image, Value);
   end Create;

   procedure Destroy
     (Image  : in out Ks_Image_16_Grey;
      Status : out Ks_Status) is
   begin
      Release (Image);
      Set_Success (Status);
   end Destroy;

   procedure Width
     (Image  : access constant Ks_Image_16_Grey_Data;
      Result : out Int32;
      Status : out Ks_Status) is
   begin
      Result := 0;
      if Image = null then
         Set_Success (Status);
      elsif not Valid_Image (Image) then
         Bad_Handle ("Width", "Image", Status);
      else
         Result := Image.Width;
         Set_Success (Status);
      end if;
   end Width;

   procedure Height
     (Image  : access constant Ks_Image_16_Grey_Data;
      Result : out Int32;
      Status : out Ks_Status) is
   begin
      Result := 0;
      if Image = null then
         Set_Success (Status);
      elsif not Valid_Image (Image) then
         Bad_Handle ("Height", "Image", Status);
      else
         Result := Image.Height;
         Set_Success (Status);
      end if;
   end Height;

   procedure Get_Pixel
     (Image  : access constant Ks_Image_16_Grey_Data;
      X, Y   : Int32;
      Value  : out Grey_16;
      Status : out Ks_Status) is
   begin
      Value := 0;
      Check_Image (Image, "Get_Pixel", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Pixel ("Get_Pixel", X, Y, Image.Width, Image.Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Value := Image.Pixels (Natural (Y), Natural (X));
   end Get_Pixel;

   procedure Set_Pixel
     (Image  : Ks_Image_16_Grey;
      X, Y   : Int32;
      Value  : Grey_16;
      Status : out Ks_Status) is
   begin
      Check_Image (Image, "Set_Pixel", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Pixel ("Set_Pixel", X, Y, Image.Width, Image.Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Image.Pixels (Natural (Y), Natural (X)) := Value;
   end Set_Pixel;

   procedure Fill
     (Image  : Ks_Image_16_Grey;
      Value  : Grey_16;
      Status : out Ks_Status) is
   begin
      Check_Image (Image, "Fill", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Fill_All (Image, Value);
   end Fill;

   procedure Duplicate
     (Image  : access constant Ks_Image_16_Grey_Data;
      Result : out Ks_Image_16_Grey;
      Status : out Ks_Status) is
   begin
      Result := null;
      if Image = null then
         Set_Success (Status);
         return;
      elsif not Valid_Image (Image) then
         Bad_Handle ("Duplicate", "Image", Status);
         return;
      end if;
      Allocate (Image.Width, Image.Height, Result);
      if Result = null then
         Out_Of_Memory ("Duplicate", Image.Width, Image.Height, Status);
         return;
      end if;
      Result.Pixels.all := Image.Pixels.all;
      Set_Success (Status);
   end Duplicate;

   procedure Check_Row_Request
     (Image     : access constant Ks_Image_16_Grey_Data;
      Operation : Operation_Name;
      Y         : Int32;
      Length    : Int32;
      Null_Row  : Boolean;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                            | Failure_Index_Out_Of_Range
                and then (if Succeeded (Status)
                          then Valid_Image (Image)
                               and then Y in 0 .. Image.Height - 1
                               and then Length = Image.Width
                               and then not Null_Row);

   procedure Check_Row_Request
     (Image     : access constant Ks_Image_16_Grey_Data;
      Operation : Operation_Name;
      Y         : Int32;
      Length    : Int32;
      Null_Row  : Boolean;
      Status    : out Ks_Status) is
   begin
      Check_Image (Image, Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Row (Operation, Y, Int64 (Length), Image.Width, Image.Height,
                 Status);
      if Succeeded (Status) and then Null_Row then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": Row must not be null");
      end if;
   end Check_Row_Request;

   procedure Get_Row
     (Image  : access constant Ks_Image_16_Grey_Data;
      Y      : Int32;
      Row    : System.Address;
      Length : Int32;
      Status : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
   begin
      Check_Row_Request (Image, "Get_Row", Y, Length,
                         Row = System.Null_Address, Status);
      if Succeeded (Status) then
         declare
            Target : Grey_16_Row (0 .. Natural (Length) - 1)
              with Import, Address => Row;
         begin
            Get_Row (Image, Y, Target, Status);
         end;
      end if;
   end Get_Row;

   procedure Set_Row
     (Image  : Ks_Image_16_Grey;
      Y      : Int32;
      Row    : System.Address;
      Length : Int32;
      Status : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
   begin
      Check_Row_Request (Image, "Set_Row", Y, Length,
                         Row = System.Null_Address, Status);
      if Succeeded (Status) then
         declare
            Source : Grey_16_Row (0 .. Natural (Length) - 1)
              with Import, Address => Row;
         begin
            Set_Row (Image, Y, Source, Status);
         end;
      end if;
   end Set_Row;

   ---------------------------------------------------------------------
   --  24-bit planar colour images
   ---------------------------------------------------------------------

   procedure Check_Planes
     (Red, Green, Blue : access constant Ks_Image_8_Grey_Data;
      Operation        : Operation_Name;
      Status           : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Valid_Image (Red) and then Valid_Image (Green)
                               and then Valid_Image (Blue)
                               and then Green.Width = Red.Width
                               and then Green.Height = Red.Height
                               and then Blue.Width = Red.Width
                               and then Blue.Height = Red.Height)
                and then (if Status.Failure = Failure_Image_No_Pixels
                          then Red = null and then Green = null
                               and then Blue = null);
   --  Image_No_Pixels when all three are null; Bad_Parameter unless all
   --  three are valid planes of one size.

   procedure Check_Planes
     (Red, Green, Blue : access constant Ks_Image_8_Grey_Data;
      Operation        : Operation_Name;
      Status           : out Ks_Status) is
   begin
      if Red = null and then Green = null and then Blue = null then
         No_Pixels (Operation, Status);
      elsif Valid_Image (Red) and then Valid_Image (Green)
        and then Valid_Image (Blue)
        and then Green.Width = Red.Width
        and then Green.Height = Red.Height
        and then Blue.Width = Red.Width
        and then Blue.Height = Red.Height
      then
         Set_Success (Status);
      else
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": Red, Green and Blue must be planes of "
                      & "the same size");
      end if;
   end Check_Planes;

   procedure Create_Color
     (Width, Height                         : Int32;
      Red_Value, Green_Value, Blue_Value    : Grey_8;
      Red, Green, Blue                      : out Ks_Image_8_Grey;
      Status                                : out Ks_Status) is
   begin
      Red := null;
      Green := null;
      Blue := null;
      Check_Size ("Create", Width, Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Allocate (Width, Height, Red);
      if Red /= null then
         Allocate (Width, Height, Green);
         if Green /= null then
            Allocate (Width, Height, Blue);
         end if;
      end if;
      if Red = null or else Green = null or else Blue = null then
         Release (Red);
         Release (Green);
         Release (Blue);
         Out_Of_Memory ("Create", Width, Height, Status);
         return;
      end if;
      Fill_All (Red, Red_Value);
      Fill_All (Green, Green_Value);
      Fill_All (Blue, Blue_Value);
   end Create_Color;

   procedure Get_Pixel_Color
     (Red, Green, Blue                   : access constant
                                             Ks_Image_8_Grey_Data;
      X, Y                               : Int32;
      Red_Value, Green_Value, Blue_Value : out Grey_8;
      Status                             : out Ks_Status) is
   begin
      Red_Value := 0;
      Green_Value := 0;
      Blue_Value := 0;
      Check_Planes (Red, Green, Blue, "Get_Pixel", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Pixel ("Get_Pixel", X, Y, Red.Width, Red.Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Red_Value := Red.Pixels (Natural (Y), Natural (X));
      Green_Value := Green.Pixels (Natural (Y), Natural (X));
      Blue_Value := Blue.Pixels (Natural (Y), Natural (X));
   end Get_Pixel_Color;

   procedure Set_Pixel_Color
     (Red, Green, Blue                   : Ks_Image_8_Grey;
      X, Y                               : Int32;
      Red_Value, Green_Value, Blue_Value : Grey_8;
      Status                             : out Ks_Status) is
   begin
      Check_Planes (Red, Green, Blue, "Set_Pixel", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Pixel ("Set_Pixel", X, Y, Red.Width, Red.Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Red.Pixels (Natural (Y), Natural (X)) := Red_Value;
      Green.Pixels (Natural (Y), Natural (X)) := Green_Value;
      Blue.Pixels (Natural (Y), Natural (X)) := Blue_Value;
   end Set_Pixel_Color;

   procedure Set_Plane
     (Plane  : Ks_Image_8_Grey;
      Pixels : access constant Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   is
      Operation : constant String := "Set_Plane";
   begin
      if Pixels = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      Operation & ": Pixels has no pixels");
      elsif not Valid_Image (Pixels) then
         Bad_Handle (Operation, "Pixels", Status);
      elsif Plane /= null and then not Valid_Image (Plane) then
         Bad_Handle (Operation, "Plane", Status);
      elsif Plane = null
        or else Plane.Width /= Pixels.Width
        or else Plane.Height /= Pixels.Height
      then
         Set_Failure
           (Status, Failure_Bad_Parameter,
            Operation & ": Pixels is " & Image_Of (Pixels.Width) & " x "
            & Image_Of (Pixels.Height) & " but the colour image is "
            & (if Plane = null then "0 x 0"
               else Image_Of (Plane.Width) & " x "
                    & Image_Of (Plane.Height)));
      else
         Plane.Pixels.all := Pixels.Pixels.all;
         Set_Success (Status);
      end if;
   end Set_Plane;

   procedure Duplicate_Color
     (Red, Green, Blue             : access constant Ks_Image_8_Grey_Data;
      New_Red, New_Green, New_Blue : out Ks_Image_8_Grey;
      Status                       : out Ks_Status) is
   begin
      New_Red := null;
      New_Green := null;
      New_Blue := null;
      if Red = null and then Green = null and then Blue = null then
         Set_Success (Status);
         return;
      end if;
      Check_Planes (Red, Green, Blue, "Duplicate", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Allocate (Red.Width, Red.Height, New_Red);
      if New_Red /= null then
         Allocate (Red.Width, Red.Height, New_Green);
         if New_Green /= null then
            Allocate (Red.Width, Red.Height, New_Blue);
         end if;
      end if;
      if New_Red = null or else New_Green = null or else New_Blue = null
      then
         Release (New_Red);
         Release (New_Green);
         Release (New_Blue);
         Out_Of_Memory ("Duplicate", Red.Width, Red.Height, Status);
         return;
      end if;
      New_Red.Pixels.all := Red.Pixels.all;
      New_Green.Pixels.all := Green.Pixels.all;
      New_Blue.Pixels.all := Blue.Pixels.all;
   end Duplicate_Color;

   ---------------------------------------------------------------------
   --  Space names
   ---------------------------------------------------------------------

   function Is_Single (Name : KC.Ks_Space_Name; C : Character) return Boolean
   is (Name.Length = 1 and then Name.Text (1) = C);
   --  Name is the one-character name C ("@", "#" or ".").

   function Same_Name (Left, Right : KC.Ks_Space_Name) return Boolean is
     (KC.Fits (Left) and then Left.Length = Right.Length
      and then (for all J in 1 .. Integer (Left.Length)
                => Left.Text (J) = Right.Text (J)));

   function Clean (Name : KC.Ks_Space_Name) return KC.Ks_Space_Name is
     (KC.To_Space_Name (KC.To_String (Name)))
   with Pre  => KC.Fits (Name),
        Post => KC.Fits (Clean'Result)
                and then Clean'Result.Length = Name.Length;
   --  Name with NUL characters after its text.

   function Shown (Name : KC.Ks_Space_Name) return String
   with Post => Shown'Result'Length <= KC.Max_Name_Length;
   --  The characters of Name that it holds, for messages.

   function Shown (Name : KC.Ks_Space_Name) return String is
      Last : constant Natural :=
        (if Name.Length < 0 then 0
         elsif Name.Length > KC.Max_Name_Length then KC.Max_Name_Length
         else Natural (Name.Length));
   begin
      return String (Name.Text (1 .. Last));
   end Shown;

   procedure Fail_Bad_Tree (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Fail_Bad_Tree (Status : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter,
                   "Tree is not a valid coordinate space tree");
   end Fail_Bad_Tree;

   procedure Unknown_Name
     (Operation : Operation_Name;
      Name      : KC.Ks_Space_Name;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           = Failure_Image_Bad_Selected_Space_Name;
   --  "<Operation>: no space named "<Name>" in the image's coordinate
   --  space tree".

   procedure Unknown_Name
     (Operation : Operation_Name;
      Name      : KC.Ks_Space_Name;
      Status    : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Image_Bad_Selected_Space_Name,
                   Operation & ": no space named """ & Shown (Name)
                   & """ in the image's coordinate space tree");
   end Unknown_Name;

   function In_Tree
     (Tree : KC.Ks_Coordinate_Space_Tree;
      Name : KC.Ks_Space_Name) return Boolean
   with Post => (if In_Tree'Result then KC.Fits (Name));
   --  Name is a space of Tree ("@" included).

   function In_Tree
     (Tree : KC.Ks_Coordinate_Space_Tree;
      Name : KC.Ks_Space_Name) return Boolean
   is
      Result : Int32;
      Inner  : Ks_Status;
   begin
      if not KC.Fits (Name) then
         return False;
      end if;
      KC.Space_Exists (Tree, Name, Result, Inner);
      return Succeeded (Inner) and then Result = True_Value;
   end In_Tree;

   function Effective
     (Tree     : KC.Ks_Coordinate_Space_Tree;
      Selected : KC.Ks_Space_Name) return KC.Ks_Space_Name
   is
     (if Is_Single (Selected, KC.Pixel_Character) then Pixel_Space_Name
      elsif In_Tree (Tree, Selected) then Clean (Selected)
      else Root_Space_Name)
   with Post => KC.Fits (Effective'Result);
   --  The selection as it reads.

   procedure Resolve
     (Tree       : KC.Ks_Coordinate_Space_Tree;
      Selected   : KC.Ks_Space_Name;
      Space_Name : KC.Ks_Space_Name;
      Operation  : Operation_Name;
      Result     : out KC.Ks_Space_Name;
      Status     : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None
                            | Failure_Image_Bad_Selected_Space_Name
                and then KC.Fits (Result)
                and then (if not Succeeded (Status) then Result.Length = 0);
   --  "." as the selection reads, "#" and tree names as they are.

   procedure Resolve
     (Tree       : KC.Ks_Coordinate_Space_Tree;
      Selected   : KC.Ks_Space_Name;
      Space_Name : KC.Ks_Space_Name;
      Operation  : Operation_Name;
      Result     : out KC.Ks_Space_Name;
      Status     : out Ks_Status) is
   begin
      Result := Empty_Name;
      if Is_Single (Space_Name, KC.Selected_Character) then
         Result := Effective (Tree, Selected);
      elsif Is_Single (Space_Name, KC.Pixel_Character) then
         Result := Pixel_Space_Name;
      elsif In_Tree (Tree, Space_Name) then
         Result := Clean (Space_Name);
      else
         Unknown_Name (Operation, Space_Name, Status);
         return;
      end if;
      Set_Success (Status);
   end Resolve;

   ---------------------------------------------------------------------
   --  The coordinate space state
   ---------------------------------------------------------------------

   procedure Selected_Space_Name
     (Tree     : KC.Ks_Coordinate_Space_Tree;
      Selected : KC.Ks_Space_Name;
      Result   : out KC.Ks_Space_Name;
      Status   : out Ks_Status) is
   begin
      Result := Empty_Name;
      if not KC.Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Result := Effective (Tree, Selected);
      Set_Success (Status);
   end Selected_Space_Name;

   procedure Set_Selected_Space_Name
     (Tree       : KC.Ks_Coordinate_Space_Tree;
      Selected   : in out KC.Ks_Space_Name;
      Space_Name : KC.Ks_Space_Name;
      Status     : out Ks_Status) is
   begin
      if not KC.Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
      elsif Is_Single (Space_Name, KC.Selected_Character) then
         Selected := Effective (Tree, Selected);
         Set_Success (Status);
      elsif Is_Single (Space_Name, KC.Pixel_Character) then
         Selected := Pixel_Space_Name;
         Set_Success (Status);
      elsif In_Tree (Tree, Space_Name) then
         Selected := Clean (Space_Name);
         Set_Success (Status);
      else
         Unknown_Name ("Selected_Space_Name", Space_Name, Status);
      end if;
   end Set_Selected_Space_Name;

   procedure Resolve_Space_Name
     (Tree       : KC.Ks_Coordinate_Space_Tree;
      Selected   : KC.Ks_Space_Name;
      Space_Name : KC.Ks_Space_Name;
      Result     : out KC.Ks_Space_Name;
      Status     : out Ks_Status) is
   begin
      Result := Empty_Name;
      if not KC.Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Resolve (Tree, Selected, Space_Name, "Resolve_Space_Name", Result,
               Status);
   end Resolve_Space_Name;

   procedure Get_Transform
     (Tree            : KC.Ks_Coordinate_Space_Tree;
      Selected        : KC.Ks_Space_Name;
      Pixel_From_Root : KT.Ks_Transform_2D_Linear;
      To_Space_Name   : KC.Ks_Space_Name;
      From_Space_Name : KC.Ks_Space_Name;
      Result          : out KT.Ks_Transform_2D_Linear;
      Status          : out Ks_Status)
   is
      Operation : constant String := "Get_Transform";
      To, From  : KC.Ks_Space_Name;
      Path      : KT.Ks_Transform_2D_Linear;
      Inverse   : KT.Ks_Transform_2D_Linear;
   begin
      Result := Identity;
      if not KC.Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      elsif not KT.Bounded (Pixel_From_Root) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": Pixel_From_Root_Transform must be "
                      & "finite and within +/-1.0E150");
         return;
      end if;
      Resolve (Tree, Selected, To_Space_Name, Operation, To, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Resolve (Tree, Selected, From_Space_Name, Operation, From, Status);
      if not Succeeded (Status) or else Same_Name (To, From) then
         return;
      end if;
      --  With F (X) the transform from the root "@" to space X, where
      --  F ("#") is Pixel_From_Root, the result is F (To) composed with
      --  the inverse of F (From).
      if not Is_Single (To, KC.Pixel_Character)
        and then not Is_Single (From, KC.Pixel_Character)
      then
         KC.Get_Transform (Tree, To, From, Result, Status);
      elsif Is_Single (To, KC.Pixel_Character) then
         KC.Get_Transform (Tree, Root_Space_Name, From, Path, Status);
         if Succeeded (Status) then
            KT.Compose (Pixel_From_Root, Path, Result, Status);
         end if;
      else
         KC.Get_Transform (Tree, To, Root_Space_Name, Path, Status);
         if not Succeeded (Status) then
            return;
         end if;
         KT.Invert (Pixel_From_Root, Inverse, Status);
         if not Succeeded (Status) then
            Set_Failure (Status, Failure_Transform_Singular,
                         Operation & ": Pixel_From_Root_Transform is not "
                         & "invertible");
            return;
         end if;
         KT.Compose (Path, Inverse, Result, Status);
      end if;
      if not Succeeded (Status) then
         Result := Identity;
      end if;
   end Get_Transform;

   procedure Selection_For_New_Tree
     (Tree     : KC.Ks_Coordinate_Space_Tree;
      Selected : in out KC.Ks_Space_Name;
      New_Tree : KC.Ks_Coordinate_Space_Tree;
      Status   : out Ks_Status)
   is
      Current : KC.Ks_Space_Name;
   begin
      if not KC.Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      elsif not KC.Valid_Tree (New_Tree) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      "New_Tree is not a valid coordinate space tree");
         return;
      end if;
      Current := Effective (Tree, Selected);
      if Is_Single (Current, KC.Pixel_Character)
        or else In_Tree (New_Tree, Current)
      then
         Selected := Current;
      else
         Selected := Root_Space_Name;
      end if;
      Set_Success (Status);
   end Selection_For_New_Tree;

   procedure Set_Pixel_From_Root_Transform
     (Pixel_From_Root : in out KT.Ks_Transform_2D_Linear;
      Transform       : KT.Ks_Transform_2D_Linear;
      Status          : out Ks_Status)
   is
      Operation : constant String := "Pixel_From_Root_Transform";
      Inverse   : KT.Ks_Transform_2D_Linear;
   begin
      --  KT.Bounded is False for a NaN or an infinity at run time.
      if not KT.Bounded (Transform) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": the transform must be finite and "
                      & "within +/-1.0E150");
         return;
      end if;
      --  Only whether the inverse exists matters here.
      KT.Invert (Transform, Inverse, Status);
      if not Succeeded (Status) then
         Set_Failure (Status, Failure_Transform_Singular,
                      Operation & ": the transform is singular");
         return;
      end if;
      pragma Assert (KT.Bounded (Inverse));
      Pixel_From_Root := Transform;
   end Set_Pixel_From_Root_Transform;

   ---------------------------------------------------------------------
   --  Lean per-pixel access
   ---------------------------------------------------------------------

   procedure Try_Get_Pixel
     (Image : access constant Ks_Image_8_Grey_Data;
      X, Y  : Int32;
      Value : out Grey_8;
      Done  : out Boolean) is
   begin
      Done := Pixel_Exists (Image, X, Y);
      Value := (if Done then Image.Pixels (Natural (Y), Natural (X))
                else 0);
   end Try_Get_Pixel;

   procedure Try_Set_Pixel
     (Image : Ks_Image_8_Grey;
      X, Y  : Int32;
      Value : Grey_8;
      Done  : out Boolean) is
   begin
      Done := Pixel_Exists (Image, X, Y);
      if Done then
         Image.Pixels (Natural (Y), Natural (X)) := Value;
      end if;
   end Try_Set_Pixel;

   procedure Try_Get_Pixel
     (Image : access constant Ks_Image_16_Grey_Data;
      X, Y  : Int32;
      Value : out Grey_16;
      Done  : out Boolean) is
   begin
      Done := Pixel_Exists (Image, X, Y);
      Value := (if Done then Image.Pixels (Natural (Y), Natural (X))
                else 0);
   end Try_Get_Pixel;

   procedure Try_Set_Pixel
     (Image : Ks_Image_16_Grey;
      X, Y  : Int32;
      Value : Grey_16;
      Done  : out Boolean) is
   begin
      Done := Pixel_Exists (Image, X, Y);
      if Done then
         Image.Pixels (Natural (Y), Natural (X)) := Value;
      end if;
   end Try_Set_Pixel;

   procedure Try_Get_Pixel_Color
     (Red, Green, Blue                   : access constant
                                             Ks_Image_8_Grey_Data;
      X, Y                               : Int32;
      Red_Value, Green_Value, Blue_Value : out Grey_8;
      Done                               : out Boolean) is
   begin
      Done := Pixel_Exists (Red, Green, Blue, X, Y);
      if Done then
         Red_Value := Red.Pixels (Natural (Y), Natural (X));
         Green_Value := Green.Pixels (Natural (Y), Natural (X));
         Blue_Value := Blue.Pixels (Natural (Y), Natural (X));
      else
         Red_Value := 0;
         Green_Value := 0;
         Blue_Value := 0;
      end if;
   end Try_Get_Pixel_Color;

   procedure Try_Set_Pixel_Color
     (Red, Green, Blue                   : Ks_Image_8_Grey;
      X, Y                               : Int32;
      Red_Value, Green_Value, Blue_Value : Grey_8;
      Done                               : out Boolean) is
   begin
      Done := Pixel_Exists (Red, Green, Blue, X, Y);
      if Done then
         Red.Pixels (Natural (Y), Natural (X)) := Red_Value;
         Green.Pixels (Natural (Y), Natural (X)) := Green_Value;
         Blue.Pixels (Natural (Y), Natural (X)) := Blue_Value;
      end if;
   end Try_Set_Pixel_Color;

   ---------------------------------------------------------------------
   --  Rows and matrices
   ---------------------------------------------------------------------

   procedure Get_Row
     (Image  : access constant Ks_Image_8_Grey_Data;
      Y      : Int32;
      Row    : out Grey_8_Row;
      Status : out Ks_Status) is
   begin
      Row := [others => 0];
      Check_Image (Image, "Get_Row", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Row ("Get_Row", Y, Int64 (Row'Length), Image.Width,
                 Image.Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for I in Row'Range loop
         Row (I) := Image.Pixels (Natural (Y), I - Row'First);
         pragma Loop_Invariant
           (for all K in Row'First .. I
            => Row (K) = Image.Pixels (Natural (Y), K - Row'First));
      end loop;
   end Get_Row;

   procedure Set_Row
     (Image  : Ks_Image_8_Grey;
      Y      : Int32;
      Row    : Grey_8_Row;
      Status : out Ks_Status) is
   begin
      Check_Image (Image, "Set_Row", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Row ("Set_Row", Y, Int64 (Row'Length), Image.Width,
                 Image.Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for I in Row'Range loop
         Image.Pixels (Natural (Y), I - Row'First) := Row (I);
         pragma Loop_Invariant
           (Valid_Image (Image)
            and then Size_Of (Image) = Size_Of (Image)'Loop_Entry);
         pragma Loop_Invariant
           (for all J in Image.Pixels'Range (1)
            => (for all C in Image.Pixels'Range (2)
                => Image.Pixels (J, C)
                     = (if J = Natural (Y) and then C <= I - Row'First
                        then Row (Row'First + C)
                        else Pixels_Of (Image)'Loop_Entry (J, C))));
      end loop;
   end Set_Row;

   procedure Get_Row
     (Image  : access constant Ks_Image_16_Grey_Data;
      Y      : Int32;
      Row    : out Grey_16_Row;
      Status : out Ks_Status) is
   begin
      Row := [others => 0];
      Check_Image (Image, "Get_Row", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Row ("Get_Row", Y, Int64 (Row'Length), Image.Width,
                 Image.Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for I in Row'Range loop
         Row (I) := Image.Pixels (Natural (Y), I - Row'First);
         pragma Loop_Invariant
           (for all K in Row'First .. I
            => Row (K) = Image.Pixels (Natural (Y), K - Row'First));
      end loop;
   end Get_Row;

   procedure Set_Row
     (Image  : Ks_Image_16_Grey;
      Y      : Int32;
      Row    : Grey_16_Row;
      Status : out Ks_Status) is
   begin
      Check_Image (Image, "Set_Row", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Row ("Set_Row", Y, Int64 (Row'Length), Image.Width,
                 Image.Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for I in Row'Range loop
         Image.Pixels (Natural (Y), I - Row'First) := Row (I);
         pragma Loop_Invariant
           (Valid_Image (Image)
            and then Size_Of (Image) = Size_Of (Image)'Loop_Entry);
         pragma Loop_Invariant
           (for all J in Image.Pixels'Range (1)
            => (for all C in Image.Pixels'Range (2)
                => Image.Pixels (J, C)
                     = (if J = Natural (Y) and then C <= I - Row'First
                        then Row (Row'First + C)
                        else Pixels_Of (Image)'Loop_Entry (J, C))));
      end loop;
   end Set_Row;

   procedure Matrix_Bounds
     (Image                 : access constant Ks_Image_8_Grey_Data;
      Last_Row, Last_Column : out Natural;
      Status                : out Ks_Status) is
   begin
      Last_Row := 0;
      Last_Column := 0;
      Check_Image (Image, "To_Matrix", Status);
      if Succeeded (Status) then
         Last_Row := Image.Pixels'Last (1);
         Last_Column := Image.Pixels'Last (2);
      end if;
   end Matrix_Bounds;

   procedure Get_Matrix
     (Image  : access constant Ks_Image_8_Grey_Data;
      Matrix : out Grey_8_Matrix;
      Status : out Ks_Status) is
   begin
      Matrix := [others => [others => 0]];
      Check_Image (Image, "To_Matrix", Status);
      if not Succeeded (Status) then
         return;
      elsif Int64 (Matrix'Length (1)) /= Int64 (Image.Height)
        or else Int64 (Matrix'Length (2)) /= Int64 (Image.Width)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "To_Matrix: the matrix must have "
                      & Image_Of (Image.Height) & " rows and "
                      & Image_Of (Image.Width) & " columns");
         return;
      end if;
      for Y in Image.Pixels'Range (1) loop
         for X in Image.Pixels'Range (2) loop
            Matrix (Matrix'First (1) + Y, Matrix'First (2) + X) :=
              Image.Pixels (Y, X);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Image.Pixels'Range (2)
                   => Matrix (Matrix'First (1) + J, Matrix'First (2) + I)
                        = Image.Pixels (J, I)));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => Matrix (Matrix'First (1) + Y, Matrix'First (2) + I)
                    = Image.Pixels (Y, I));
         end loop;
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Image.Pixels'Range (2)
                => Matrix (Matrix'First (1) + J, Matrix'First (2) + I)
                     = Image.Pixels (J, I)));
      end loop;
   end Get_Matrix;

   procedure Create_From_Matrix
     (Matrix : Grey_8_Matrix;
      Image  : out Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Operation : constant String := "From_Matrix";
      Rows      : constant Int64 := Int64 (Matrix'Length (1));
      Columns   : constant Int64 := Int64 (Matrix'Length (2));
   begin
      Image := null;
      if Rows = 0 or else Columns = 0 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": the matrix must have at least one row "
                      & "and one column");
         return;
      elsif Rows * Columns > Max_Pixels then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": the matrix has more than 2147483647 "
                      & "pixels");
         return;
      end if;
      Allocate (Int32 (Columns), Int32 (Rows), Image);
      if Image = null then
         Out_Of_Memory (Operation, Int32 (Columns), Int32 (Rows), Status);
         return;
      end if;
      Set_Success (Status);
      for Y in Image.Pixels'Range (1) loop
         for X in Image.Pixels'Range (2) loop
            Image.Pixels (Y, X) :=
              Matrix (Matrix'First (1) + Y, Matrix'First (2) + X);
            pragma Loop_Invariant
              (Valid_Image (Image)
               and then Image.Width = Int32 (Columns)
               and then Image.Height = Int32 (Rows));
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Image.Pixels'Range (2)
                   => Image.Pixels (J, I)
                        = Matrix (Matrix'First (1) + J,
                                  Matrix'First (2) + I)));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => Image.Pixels (Y, I)
                    = Matrix (Matrix'First (1) + Y, Matrix'First (2) + I));
         end loop;
         pragma Loop_Invariant
           (Valid_Image (Image)
            and then Image.Width = Int32 (Columns)
            and then Image.Height = Int32 (Rows));
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Image.Pixels'Range (2)
                => Image.Pixels (J, I)
                     = Matrix (Matrix'First (1) + J, Matrix'First (2) + I)));
      end loop;
   end Create_From_Matrix;

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   function Read_Operation (Code : Stream_Code) return String
   with Post => Read_Operation'Result'First = 1
                and then Read_Operation'Result'Length <= 40;
   --  The attribute that reads data of format Code.

   function Read_Operation (Code : Stream_Code) return String is
   begin
      case Code is
         when Code_Spaces_Part =>
            return "Ks_Image'Read";
         when Code_Grey_8 =>
            return "Ks_Image_8_Grey'Read";
         when Code_Grey_16 =>
            return "Ks_Image_16_Grey'Read";
         when Code_Colour =>
            return "Ks_Image_24_Planar_Color'Read";
      end case;
   end Read_Operation;

   procedure Stream_Failure
     (Code   : Stream_Code;
      Reason : String;
      Status : out Ks_Status)
   with Pre  => Reason'Length <= 400,
        Post => Valid (Status) and then Status.Failure = Failure_Image_File;
   --  "<attribute>: <Reason>".

   procedure Stream_Failure
     (Code   : Stream_Code;
      Reason : String;
      Status : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Image_File,
                   Read_Operation (Code) & ": " & Reason);
   end Stream_Failure;

   function To_Bits (Transform : KT.Ks_Transform_2D_Linear)
      return Transform_Bits
   is
      function Convert is new Ada.Unchecked_Conversion (Long_Float, U64);
   begin
      return [Convert (Transform.A), Convert (Transform.B),
              Convert (Transform.C), Convert (Transform.D),
              Convert (Transform.Translation_X),
              Convert (Transform.Translation_Y)];
   end To_Bits;

   function All_Finite (Bits : Transform_Bits) return Boolean is
     (for all I in Bits'Range => Finite_Bits (Bits (I)));

   function From_Bits (Bits : Transform_Bits) return KT.Ks_Transform_2D_Linear
   is
     (A             => To_Long_Float (Bits (1)),
      B             => To_Long_Float (Bits (2)),
      C             => To_Long_Float (Bits (3)),
      D             => To_Long_Float (Bits (4)),
      Translation_X => To_Long_Float (Bits (5)),
      Translation_Y => To_Long_Float (Bits (6)))
   with Pre => All_Finite (Bits);

   procedure Check_Read_Code
     (Expected : Stream_Code;
      Code     : U32;
      Status   : out Ks_Status) is
   begin
      if Code = Expected then
         Set_Success (Status);
      elsif Expected = Code_Spaces_Part then
         Stream_Failure
           (Expected, "the stream does not hold a coordinate space state "
            & "(format code" & U32'Image (Code) & " instead of"
            & U32'Image (Expected) & ")", Status);
      else
         Stream_Failure
           (Expected, "the stream does not hold an image of this type "
            & "(format code" & U32'Image (Code) & " instead of"
            & U32'Image (Expected) & ")", Status);
      end if;
   end Check_Read_Code;

   procedure Check_Read_Size
     (Code                  : Stream_Code;
      Width, Height         : U32;
      Image_Width           : out Int32;
      Image_Height          : out Int32;
      Status                : out Ks_Status) is
   begin
      Image_Width := 0;
      Image_Height := 0;
      if Width = 0 and then Height = 0 then
         Set_Success (Status);
      elsif Width = 0 or else Height = 0 then
         Stream_Failure
           (Code, "the image size" & U32'Image (Width) & " x"
            & U32'Image (Height) & " has one zero dimension", Status);
      elsif Width > Max_Pixels or else Height > Max_Pixels
        or else Int64 (Width) * Int64 (Height) > Max_Pixels
      then
         Stream_Failure
           (Code, "the image size" & U32'Image (Width) & " x"
            & U32'Image (Height) & " is too large", Status);
      else
         Image_Width := Int32 (Width);
         Image_Height := Int32 (Height);
         Set_Success (Status);
      end if;
   end Check_Read_Size;

   procedure Read_Pixel_From_Root
     (Code   : Stream_Code;
      Bits   : Transform_Bits;
      Result : out KT.Ks_Transform_2D_Linear;
      Status : out Ks_Status)
   is
      What      : constant String := "the pixel-from-root transform";
      Transform : KT.Ks_Transform_2D_Linear;
      Inverse   : KT.Ks_Transform_2D_Linear;
   begin
      Result := Identity;
      if not All_Finite (Bits) then
         Stream_Failure
           (Code, What & " has an entry that is not a finite number",
            Status);
         return;
      end if;
      Transform := From_Bits (Bits);
      if not KT.Bounded (Transform) then
         Stream_Failure (Code, What & " is not within +/-1.0E150", Status);
         return;
      end if;
      KT.Invert (Transform, Inverse, Status);
      if not Succeeded (Status) then
         Stream_Failure (Code, What & " is not invertible", Status);
         return;
      end if;
      pragma Assert (KT.Bounded (Inverse));
      Result := Transform;
   end Read_Pixel_From_Root;

   procedure Check_Read_Space_Count
     (Code   : Stream_Code;
      Count  : U32;
      Status : out Ks_Status) is
   begin
      if Count <= KC.Max_Spaces - 1 then
         Set_Success (Status);
      else
         Stream_Failure
           (Code, "a coordinate space tree cannot hold" & U32'Image (Count)
            & " spaces besides ""@""", Status);
      end if;
   end Check_Read_Space_Count;

   procedure Check_Read_Name_Length
     (Code   : Stream_Code;
      Length : U32;
      Count  : out Natural;
      Status : out Ks_Status) is
   begin
      Count := 0;
      if Length <= KC.Max_Name_Length then
         Count := Natural (Length);
         Set_Success (Status);
      else
         Stream_Failure
           (Code, "a space name of" & U32'Image (Length)
            & " characters is too long", Status);
      end if;
   end Check_Read_Name_Length;

   procedure Read_Space
     (Code   : Stream_Code;
      Tree   : in out KC.Ks_Coordinate_Space_Tree;
      Name   : KC.Ks_Space_Name;
      Bits   : Transform_Bits;
      Status : out Ks_Status) is
   begin
      if not All_Finite (Bits) then
         Stream_Failure
           (Code, "the transform of the space """ & Shown (Name)
            & """ has an entry that is not a finite number", Status);
         return;
      end if;
      KC.Add_Read_Space (Read_Operation (Code), Tree, Name, From_Bits (Bits),
                         Status);
   end Read_Space;

   procedure Read_Selection
     (Code     : Stream_Code;
      Tree     : KC.Ks_Coordinate_Space_Tree;
      Name     : KC.Ks_Space_Name;
      Selected : out KC.Ks_Space_Name;
      Status   : out Ks_Status) is
   begin
      Selected := Root_Space_Name;
      if not KC.Valid_Tree (Tree) then
         Stream_Failure (Code, "the tree read is not valid", Status);
      elsif Is_Single (Name, KC.Pixel_Character) then
         Selected := Pixel_Space_Name;
         Set_Success (Status);
      elsif In_Tree (Tree, Name) then
         Selected := Clean (Name);
         Set_Success (Status);
      else
         Stream_Failure
           (Code, "the selected space """ & Shown (Name)
            & """ is not in the tree", Status);
      end if;
   end Read_Selection;

   procedure Stream_Ended
     (Code   : Stream_Code;
      Status : out Ks_Status) is
   begin
      Stream_Failure
        (Code, "the stream ends before the image is complete", Status);
   end Stream_Ended;

   procedure Stream_Space_Count
     (Tree   : KC.Ks_Coordinate_Space_Tree;
      Count  : out U32;
      Status : out Ks_Status) is
   begin
      Count := 0;
      if not KC.Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Count := U32 (Tree.Count - 1);
      Set_Success (Status);
   end Stream_Space_Count;

   procedure Create_For_Read
     (Width, Height : Int32;
      Image         : out Ks_Image_8_Grey;
      Status        : out Ks_Status) is
   begin
      if Width = 0 and then Height = 0 then
         Image := null;
         Set_Success (Status);
      else
         Create (Width, Height, 0, Image, Status);
      end if;
   end Create_For_Read;

   procedure Create_For_Read
     (Width, Height : Int32;
      Image         : out Ks_Image_16_Grey;
      Status        : out Ks_Status) is
   begin
      if Width = 0 and then Height = 0 then
         Image := null;
         Set_Success (Status);
      else
         Create (Width, Height, 0, Image, Status);
      end if;
   end Create_For_Read;

   procedure Create_Color_For_Read
     (Width, Height    : Int32;
      Red, Green, Blue : out Ks_Image_8_Grey;
      Status           : out Ks_Status) is
   begin
      if Width = 0 and then Height = 0 then
         Red := null;
         Green := null;
         Blue := null;
         Set_Success (Status);
      else
         Create_Color (Width, Height, 0, 0, 0, Red, Green, Blue, Status);
      end if;
   end Create_Color_For_Read;

   --  Pixels in stream form

   function Pixels_Left
     (Width, Height : Int32;
      Position      : Pixel_Position) return Int64
   is
     (if Position.Row = Height then 0
      else Int64 (Height - 1 - Position.Row) * Int64 (Width)
           + Int64 (Width - Position.Column))
   with Pre  => Width >= 1 and then Height >= 1
                and then Valid_Position (Width, Height, Position),
        Post => Pixels_Left'Result >= 0
                and then (Pixels_Left'Result = 0) = (Position.Row = Height);
   --  The pixels from Position to the end of the image.

   procedure Advance
     (Width, Height : Int32;
      Position      : in out Pixel_Position)
   with Pre  => Width >= 1 and then Height >= 1
                and then Valid_Position (Width, Height, Position)
                and then Position.Row < Height,
        Post => Valid_Position (Width, Height, Position)
                and then Pixels_Left (Width, Height, Position)
                           = Pixels_Left (Width, Height, Position'Old) - 1;
   --  The next pixel, row after row.

   procedure Advance
     (Width, Height : Int32;
      Position      : in out Pixel_Position) is
   begin
      if Position.Column = Width - 1 then
         pragma Assert
           (Int64 (Height - 1 - Position.Row) * Int64 (Width)
              = Int64 (Height - 2 - Position.Row) * Int64 (Width)
                + Int64 (Width));
         Position := (Row => Position.Row + 1, Column => 0);
      else
         Position.Column := Position.Column + 1;
      end if;
   end Advance;

   procedure Next_Chunk
     (Image    : access constant Ks_Image_8_Grey_Data;
      Position : Pixel_Position;
      Limit    : Positive;
      Length   : out Natural) is
   begin
      Length := 0;
      if Valid_Image (Image)
        and then Valid_Position (Image.Width, Image.Height, Position)
      then
         Length := Natural (Int64'Min (Int64 (Limit),
                                       Pixels_Left (Image.Width,
                                                    Image.Height,
                                                    Position)));
      end if;
   end Next_Chunk;

   procedure Next_Chunk
     (Image    : access constant Ks_Image_16_Grey_Data;
      Position : Pixel_Position;
      Limit    : Positive;
      Length   : out Natural)
   is
      Pixels : Natural;
   begin
      Length := 0;
      if Valid_Image (Image)
        and then Valid_Position (Image.Width, Image.Height, Position)
      then
         Pixels := Natural (Int64'Min (Int64 (Limit / 2),
                                       Pixels_Left (Image.Width,
                                                    Image.Height,
                                                    Position)));
         Length := 2 * Pixels;
      end if;
   end Next_Chunk;

   procedure Check_Chunk
     (Width, Height : Int32;
      Position      : Pixel_Position;
      Pixels        : Int64;
      Operation     : Operation_Name;
      Status        : out Ks_Status)
   with Pre  => Width >= 1 and then Height >= 1,
        Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Valid_Position (Width, Height, Position)
                               and then Pixels
                                          <= Pixels_Left (Width, Height,
                                                          Position));
   --  Bad_Parameter unless Position is valid and Pixels pixels are left.

   procedure Check_Chunk
     (Width, Height : Int32;
      Position      : Pixel_Position;
      Pixels        : Int64;
      Operation     : Operation_Name;
      Status        : out Ks_Status) is
   begin
      if not Valid_Position (Width, Height, Position) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": the pixel position is not valid");
      elsif Pixels > Pixels_Left (Width, Height, Position) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": the chunk is longer than the pixels "
                      & "left");
      else
         Set_Success (Status);
      end if;
   end Check_Chunk;

   procedure Get_Bytes
     (Image    : access constant Ks_Image_8_Grey_Data;
      Position : in out Pixel_Position;
      Bytes    : out Grey_8_Row;
      Status   : out Ks_Status)
   is
      Operation : constant String := "Get_Bytes";
      Next      : Pixel_Position;
   begin
      Bytes := [others => 0];
      Check_Image (Image, Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Chunk (Image.Width, Image.Height, Position, Int64 (Bytes'Length),
                   Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Next := Position;
      for K in Bytes'Range loop
         pragma Loop_Invariant
           (Valid_Position (Image.Width, Image.Height, Next)
            and then Pixels_Left (Image.Width, Image.Height, Next)
                       >= Int64 (Bytes'Last) - Int64 (K) + 1);
         Bytes (K) := Image.Pixels (Natural (Next.Row),
                                    Natural (Next.Column));
         Advance (Image.Width, Image.Height, Next);
      end loop;
      Position := Next;
   end Get_Bytes;

   procedure Put_Bytes
     (Image    : Ks_Image_8_Grey;
      Position : in out Pixel_Position;
      Bytes    : Grey_8_Row;
      Status   : out Ks_Status)
   is
      Operation : constant String := "Put_Bytes";
      Next      : Pixel_Position;
   begin
      Check_Image (Image, Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Chunk (Image.Width, Image.Height, Position, Int64 (Bytes'Length),
                   Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Next := Position;
      for K in Bytes'Range loop
         pragma Loop_Invariant
           (Valid_Image (Image)
            and then Size_Of (Image) = Size_Of (Image)'Loop_Entry);
         pragma Loop_Invariant
           (Valid_Position (Image.Width, Image.Height, Next)
            and then Pixels_Left (Image.Width, Image.Height, Next)
                       >= Int64 (Bytes'Last) - Int64 (K) + 1);
         Image.Pixels (Natural (Next.Row), Natural (Next.Column)) :=
           Bytes (K);
         Advance (Image.Width, Image.Height, Next);
      end loop;
      Position := Next;
   end Put_Bytes;

   procedure Get_Bytes
     (Image    : access constant Ks_Image_16_Grey_Data;
      Position : in out Pixel_Position;
      Bytes    : out Grey_8_Row;
      Status   : out Ks_Status)
   is
      Operation : constant String := "Get_Bytes";
      Next      : Pixel_Position;
      Value     : Grey_16;
   begin
      Bytes := [others => 0];
      Check_Image (Image, Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Int64 (Bytes'Length) mod 2 /= 0 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": a chunk of 16-bit pixels must have an "
                      & "even length");
         return;
      end if;
      Check_Chunk (Image.Width, Image.Height, Position,
                   Int64 (Bytes'Length) / 2, Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Next := Position;
      for P in 0 .. Natural (Int64 (Bytes'Length) / 2) - 1 loop
         pragma Loop_Invariant
           (Valid_Position (Image.Width, Image.Height, Next)
            and then Pixels_Left (Image.Width, Image.Height, Next)
                       >= Int64 (Bytes'Length) / 2 - Int64 (P));
         Value := Image.Pixels (Natural (Next.Row), Natural (Next.Column));
         Bytes (Bytes'First + 2 * P) := Grey_8 (Value mod 256);
         Bytes (Bytes'First + 2 * P + 1) := Grey_8 (Value / 256);
         Advance (Image.Width, Image.Height, Next);
      end loop;
      Position := Next;
   end Get_Bytes;

   procedure Put_Bytes
     (Image    : Ks_Image_16_Grey;
      Position : in out Pixel_Position;
      Bytes    : Grey_8_Row;
      Status   : out Ks_Status)
   is
      Operation : constant String := "Put_Bytes";
      Next      : Pixel_Position;
   begin
      Check_Image (Image, Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Int64 (Bytes'Length) mod 2 /= 0 then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": a chunk of 16-bit pixels must have an "
                      & "even length");
         return;
      end if;
      Check_Chunk (Image.Width, Image.Height, Position,
                   Int64 (Bytes'Length) / 2, Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Next := Position;
      for P in 0 .. Natural (Int64 (Bytes'Length) / 2) - 1 loop
         pragma Loop_Invariant
           (Valid_Image (Image)
            and then Size_Of (Image) = Size_Of (Image)'Loop_Entry);
         pragma Loop_Invariant
           (Valid_Position (Image.Width, Image.Height, Next)
            and then Pixels_Left (Image.Width, Image.Height, Next)
                       >= Int64 (Bytes'Length) / 2 - Int64 (P));
         Image.Pixels (Natural (Next.Row), Natural (Next.Column)) :=
           Grey_16 (Bytes (Bytes'First + 2 * P))
           + 256 * Grey_16 (Bytes (Bytes'First + 2 * P + 1));
         Advance (Image.Width, Image.Height, Next);
      end loop;
      Position := Next;
   end Put_Bytes;

end AMV.Kernels.Images;
