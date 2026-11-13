pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

package body AMV.Kernels.Image_File with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  Postconditions refer to components of a handle on entry ('Old)
   --  after a condition; contracts are proved, never executed.

   use type Interfaces.Unsigned_16;

   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Image_File_Contents_Data, Ks_Image_File_Contents);

   Max_Pixels : constant := KI.Max_Pixels;

   ---------------------------------------------------------------------
   --  Proof helpers
   ---------------------------------------------------------------------

   type Big is range -2**127 .. 2**127 - 1 with Ghost;
   --  Products of two Int64 values, for lemmas whose statement would
   --  overflow in Int64.

   procedure Lemma_Mul_Le (A, B, K : Int64)
   with
     Ghost,
     Global => null,
     Pre    => 0 <= A and then A <= B and then 0 <= K,
     Post   => Big (A) * Big (K) <= Big (B) * Big (K);
   --  Multiplication by a non-negative number keeps the order.

   procedure Lemma_Mul_Le (A, B, K : Int64) is null;

   procedure Lemma_Stride (Width, Height, Stride : Int64)
   with
     Ghost,
     Global => null,
     Pre    => Width in 1 .. 2**31 - 1 and then Height in 1 .. 2**31
               and then Width * Height <= Max_Pixels
               and then Stride in 0 .. 4 * Width + 4,
     Post   => Big (Stride) * Big (Height) <= 8 * Big (Max_Pixels)
               and then Height <= Max_Pixels;
   --  A BMP row of Width pixels has at most 4 * Width + 4 bytes, so the
   --  rows of an image of at most Max_Pixels pixels fit in Int64.

   procedure Lemma_Stride (Width, Height, Stride : Int64) is
   begin
      Lemma_Mul_Le (1, Width, Height);
      Lemma_Mul_Le (Stride, 4 * Width + 4, Height);
   end Lemma_Stride;

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Contents
     (Count    : Int32;
      Contents : out Ks_Image_File_Contents)
   with
     Global => null,
     Pre    => Count in 1 .. Max_Images,
     Post   => (if Contents /= null
                then Contents.Count = Count
                     and then Contents.Kind = 0
                     and then (for all I in Contents.Slots'Range
                               => No_Handles (Contents.Slots (I))
                                  and then Contents.Slots (I).Image_Type
                                             = 0));
   --  A new contents record of Count empty slots, or null when the memory
   --  cannot be allocated. Trusted: the allocator raises Storage_Error,
   --  which SPARK cannot express; the slots get their default values (no
   --  handles).

   procedure Allocate_Contents
     (Count    : Int32;
      Contents : out Ks_Image_File_Contents)
     with SPARK_Mode => Off
   is
   begin
      Contents := new Ks_Image_File_Contents_Data (Count);
   exception
      when Storage_Error =>
         Contents := null;
   end Allocate_Contents;

   ---------------------------------------------------------------------
   --  Messages and failures
   ---------------------------------------------------------------------

   function Image_Of (Value : Int64) return String
   with Pre  => Value > Int64'First,
        Post => Image_Of'Result'First = 1
                and then Image_Of'Result'Length in 1 .. 20;
   --  The decimal digits of Value, with a leading '-' when it is negative.

   function Image_Of (Value : Int64) return String is
      Text  : String (1 .. 20) := [others => '0'];
      Rest  : Int64 := abs Value;
      First : Positive;
   begin
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

   function Describe (Value : Byte) return String is
     (if Value in 33 .. 126
      then "'" & Character'Val (Integer (Value)) & "'"
      else "byte " & Image_Of (Int64 (Value)))
   with Post => Describe'Result'Length <= 25;
   --  A byte in a message: the character when it is printable ASCII.

   procedure Fail (Status : out Ks_Status; Text : String)
   with Post => Valid (Status) and then Status.Failure = Failure_Image_File;
   --  An Image_File failure with this message.

   procedure Fail (Status : out Ks_Status; Text : String) is
   begin
      Set_Failure (Status, Failure_Image_File, Text);
   end Fail;

   procedure Fail_Image
     (Status : out Ks_Status;
      Index  : Int32;
      Text   : String)
   with Pre  => Text'Length <= 1_000,
        Post => Valid (Status) and then Status.Failure = Failure_Image_File;
   --  "image <Index>: <Text>", a failure in image Index of a PNM file.

   procedure Fail_Image
     (Status : out Ks_Status;
      Index  : Int32;
      Text   : String) is
   begin
      Set_Failure (Status, Failure_Image_File,
                   "image " & Image_Of (Index) & ": " & Text);
   end Fail_Image;

   procedure Bad_Parameter (Status : out Ks_Status; Text : String)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad_Parameter (Status : out Ks_Status; Text : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Text);
   end Bad_Parameter;

   procedure Out_Of_Memory
     (Status        : out Ks_Status;
      Width, Height : Int32)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Out_Of_Memory;
   --  "Decode: not enough memory for a <Width> x <Height> image".

   procedure Out_Of_Memory
     (Status        : out Ks_Status;
      Width, Height : Int32) is
   begin
      Set_Failure (Status, Failure_Out_Of_Memory,
                   "Decode: not enough memory for a " & Image_Of (Width)
                   & " x " & Image_Of (Height) & " image");
   end Out_Of_Memory;

   subtype Operation_Name is String
     with Dynamic_Predicate =>
       Operation_Name'First = 1 and then Operation_Name'Length <= 40;
   --  The name of the operation that starts a message (proved at every
   --  call, never executed).

   function Extension_Text (Format : Format_Code) return String is
     (case Format is
         when Format_PGM => ".pgm",
         when Format_PPM => ".ppm",
         when Format_PNM => ".pnm",
         when Format_BMP => ".bmp")
   with Post => Extension_Text'Result'Length = 4;

   ---------------------------------------------------------------------
   --  Images and slots
   ---------------------------------------------------------------------

   procedure Release (Image : in out KI.Ks_Image_8_Grey)
   with Post => Image = null;
   --  Frees Image (if any).

   procedure Release (Image : in out KI.Ks_Image_8_Grey) is
      Ignored : Ks_Status;
   begin
      KI.Destroy (Image, Ignored);
   end Release;

   procedure Release (Image : in out KI.Ks_Image_16_Grey)
   with Post => Image = null;

   procedure Release (Image : in out KI.Ks_Image_16_Grey) is
      Ignored : Ks_Status;
   begin
      KI.Destroy (Image, Ignored);
   end Release;

   procedure Release_Slot (Slot : in out Image_Slot)
   with Post => No_Handles (Slot);
   --  Frees every image of Slot.

   procedure Release_Slot (Slot : in out Image_Slot) is
   begin
      Release (Slot.Grey_8);
      Release (Slot.Grey_16);
      Release (Slot.Green);
      Release (Slot.Blue);
   end Release_Slot;

   procedure Free_Contents (Contents : in out Ks_Image_File_Contents)
   with Post => Contents = null;
   --  Frees every image of Contents and Contents itself, whatever state
   --  its slots are in.

   procedure Free_Contents (Contents : in out Ks_Image_File_Contents) is
   begin
      if Contents = null then
         return;
      end if;
      for I in Contents.Slots'Range loop
         Release_Slot (Contents.Slots (I));
         pragma Loop_Invariant
           (for all J in Contents.Slots'First .. I
            => No_Handles (Contents.Slots (J)));
      end loop;
      Free (Contents);
   end Free_Contents;

   ---------------------------------------------------------------------
   --  PNM decoding
   ---------------------------------------------------------------------

   Code_LF   : constant Byte := 10;
   Code_CR   : constant Byte := 13;
   Code_Hash : constant Byte := Character'Pos ('#');
   Code_Zero : constant Byte := Character'Pos ('0');
   Code_Nine : constant Byte := Character'Pos ('9');
   Code_B    : constant Byte := Character'Pos ('B');
   Code_M    : constant Byte := Character'Pos ('M');
   Code_P    : constant Byte := Character'Pos ('P');

   function Is_Netpbm_Space (Value : Byte) return Boolean is
     (Value in 9 .. 13 | 32);
   --  The Netpbm whitespace: tab, LF, VT, FF, CR and space.

   function Is_Digit (Value : Byte) return Boolean is
     (Value in Code_Zero .. Code_Nine);

   function In_Data (Data : Byte_Array; Pos : Int64) return Boolean is
     (Data'Length >= 1 and then Pos in Data'First .. Data'Last + 1);
   --  Pos is a position in Data or just after its last byte.

   procedure Skip_Comment (Data : Byte_Array; Pos : in out Int64)
   with Pre  => In_Data (Data, Pos),
        Post => Pos in Pos'Old .. Data'Last + 1
                and then (if Pos <= Data'Last
                          then Data (Pos) in Code_LF | Code_CR);
   --  Moves Pos to the end of the line (the LF or CR, or the end of Data).

   procedure Skip_Comment (Data : Byte_Array; Pos : in out Int64) is
   begin
      while Pos <= Data'Last and then Data (Pos) not in Code_LF | Code_CR
      loop
         pragma Loop_Invariant (Pos in Pos'Loop_Entry .. Data'Last);
         Pos := Pos + 1;
      end loop;
   end Skip_Comment;

   procedure Skip_Space_And_Comments (Data : Byte_Array; Pos : in out Int64)
   with Pre  => In_Data (Data, Pos),
        Post => Pos in Pos'Old .. Data'Last + 1;
   --  Skips whitespace and comments ('#' up to the end of the line).

   procedure Skip_Space_And_Comments (Data : Byte_Array; Pos : in out Int64)
   is
   begin
      while Pos <= Data'Last loop
         pragma Loop_Invariant (Pos in Pos'Loop_Entry .. Data'Last);
         if Is_Netpbm_Space (Data (Pos)) then
            Pos := Pos + 1;
         elsif Data (Pos) = Code_Hash then
            Skip_Comment (Data, Pos);
         else
            exit;
         end if;
      end loop;
   end Skip_Space_And_Comments;

   subtype Field_Name is String
     with Dynamic_Predicate =>
       Field_Name'First = 1 and then Field_Name'Length <= 20;
   --  What a number is, in messages ("the width", "a sample").

   procedure Read_Number
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      What   : Field_Name;
      Value  : out Int32;
      Status : out Ks_Status)
   with
     Pre  => In_Data (Data, Pos),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then Pos in Pos'Old .. Data'Last + 1
             and then Value >= 0;
   --  Reads an unsigned decimal number at Pos (at most Int32'Last).

   procedure Read_Number
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      What   : Field_Name;
      Value  : out Int32;
      Status : out Ks_Status)
   is
      Digit : Int32;
   begin
      Value := 0;
      if Pos > Data'Last then
         Fail_Image (Status, Index,
                     "unexpected end of file while reading " & What);
         return;
      elsif not Is_Digit (Data (Pos)) then
         Fail_Image (Status, Index,
                     "expected a decimal number for " & What
                     & " but found " & Describe (Data (Pos)));
         return;
      end if;
      while Pos <= Data'Last and then Is_Digit (Data (Pos)) loop
         pragma Loop_Invariant
           (Pos in Pos'Loop_Entry .. Data'Last and then Value >= 0);
         Digit := Int32 (Data (Pos) - Code_Zero);
         if Value > (Int32'Last - Digit) / 10 then
            Fail_Image (Status, Index, What & " is too large");
            return;
         end if;
         Value := Value * 10 + Digit;
         Pos := Pos + 1;
      end loop;
      Set_Success (Status);
   end Read_Number;

   procedure Require_Separator
     (Data   : Byte_Array;
      Pos    : Int64;
      Index  : Int32;
      After  : Field_Name;
      Status : out Ks_Status)
   with
     Pre  => In_Data (Data, Pos),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File;
   --  The byte at Pos (if any) must be whitespace or start a comment.

   procedure Require_Separator
     (Data   : Byte_Array;
      Pos    : Int64;
      Index  : Int32;
      After  : Field_Name;
      Status : out Ks_Status) is
   begin
      if Pos <= Data'Last
        and then not Is_Netpbm_Space (Data (Pos))
        and then Data (Pos) /= Code_Hash
      then
         Fail_Image (Status, Index,
                     "unexpected " & Describe (Data (Pos)) & " after "
                     & After);
      else
         Set_Success (Status);
      end if;
   end Require_Separator;

   procedure Header_Number
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      What   : Field_Name;
      Value  : out Int32;
      Status : out Ks_Status)
   with
     Pre  => In_Data (Data, Pos),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then Pos in Pos'Old .. Data'Last + 1
             and then Value >= 0;
   --  Skips separators and reads one header field.

   procedure Header_Number
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      What   : Field_Name;
      Value  : out Int32;
      Status : out Ks_Status) is
   begin
      Skip_Space_And_Comments (Data, Pos);
      Read_Number (Data, Pos, Index, What, Value, Status);
   end Header_Number;

   procedure Fail_Sample
     (Status        : out Ks_Status;
      Index         : Int32;
      Value, Maxval : Int32)
   with Post => Valid (Status) and then Status.Failure = Failure_Image_File;
   --  "image <Index>: sample value <Value> exceeds the maxval <Maxval>".

   procedure Fail_Sample
     (Status        : out Ks_Status;
      Index         : Int32;
      Value, Maxval : Int32) is
   begin
      Fail_Image (Status, Index,
                  "sample value " & Image_Of (Value)
                  & " exceeds the maxval " & Image_Of (Maxval));
   end Fail_Sample;

   procedure Plain_Sample
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      Maxval : Int32;
      Value  : out Int32;
      Status : out Ks_Status)
   with
     Pre  => In_Data (Data, Pos),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then Pos in Pos'Old .. Data'Last + 1
             and then (if Succeeded (Status) then Value in 0 .. Maxval);
   --  The next sample of a plain (P2, P3) raster, checked against Maxval.

   procedure Plain_Sample
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      Maxval : Int32;
      Value  : out Int32;
      Status : out Ks_Status) is
   begin
      Skip_Space_And_Comments (Data, Pos);
      Read_Number (Data, Pos, Index, "a sample", Value, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Require_Separator (Data, Pos, Index, "a sample", Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Value > Maxval then
         Fail_Sample (Status, Index, Value, Maxval);
      end if;
   end Plain_Sample;

   type PNM_Info is record
      Colour : Boolean := False;
      Binary : Boolean := False;
      Width  : Int32 := 1;
      Height : Int32 := 1;
      Maxval : Int32 := 1;
   end record;
   --  The header of a PNM image.

   function Valid_PNM (Info : PNM_Info) return Boolean is
     (Info.Width >= 1 and then Info.Height >= 1
      and then Int64 (Info.Width) * Int64 (Info.Height) <= Max_Pixels
      and then Info.Maxval in 1 .. 65_535
      and then (if Info.Colour then Info.Maxval <= 255));

   function Samples_Per_Pixel (Info : PNM_Info) return Int64 is
     (if Info.Colour then 3 else 1);

   function Bytes_Per_Sample (Info : PNM_Info) return Int64 is
     (if Info.Maxval > 255 then 2 else 1);

   function Raster_Fits
     (Data : Byte_Array;
      Pos  : Int64;
      Info : PNM_Info) return Boolean
   is
     (if Info.Binary
      then Data'Last - Pos + 1
             >= Int64 (Info.Width) * Int64 (Info.Height)
                * Samples_Per_Pixel (Info) * Bytes_Per_Sample (Info)
      else Data'Last - Pos + 1
             >= 2 * (Int64 (Info.Width) * Int64 (Info.Height)
                     * Samples_Per_Pixel (Info)) - 1)
   with Pre => In_Data (Data, Pos) and then Valid_PNM (Info);
   --  The bytes from Pos can hold the raster: a binary raster needs every
   --  byte, a plain one at least a digit per sample and a separator
   --  between samples.

   procedure Read_PNM_Header
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      Info   : out PNM_Info;
      Status : out Ks_Status)
   with
     Pre  => Data'Length >= 1 and then Pos in Data'First .. Data'Last,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then Pos in Pos'Old .. Data'Last + 1
             and then (if Succeeded (Status)
                       then Valid_PNM (Info)
                            and then Raster_Fits (Data, Pos, Info));
   --  Reads the header of an image whose 'P' is at Pos, up to and
   --  including the single separator after the maxval, and checks that
   --  the raster can fit in the rest of Data.

   procedure Read_PNM_Header
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      Info   : out PNM_Info;
      Status : out Ks_Status)
   is
      Magic     : Byte;
      Value     : Int32;
      Pixels    : Int64;
      Samples   : Int64;
      Remaining : Int64;
      Needed    : Int64;
   begin
      Info := (others => <>);
      Pos := Pos + 1;
      if Pos > Data'Last then
         Fail_Image (Status, Index, "truncated magic number");
         return;
      end if;
      Magic := Data (Pos);
      Pos := Pos + 1;
      case Magic is
         when Character'Pos ('2') =>
            Info.Colour := False;
            Info.Binary := False;
         when Character'Pos ('3') =>
            Info.Colour := True;
            Info.Binary := False;
         when Character'Pos ('5') =>
            Info.Colour := False;
            Info.Binary := True;
         when Character'Pos ('6') =>
            Info.Colour := True;
            Info.Binary := True;
         when Character'Pos ('1') | Character'Pos ('4') =>
            Fail_Image (Status, Index,
                        "PBM bitmaps (P1, P4) are not supported");
            return;
         when Character'Pos ('7') =>
            Fail_Image (Status, Index, "PAM images (P7) are not supported");
            return;
         when others =>
            Fail_Image (Status, Index,
                        "unknown PNM magic number 'P' followed by "
                        & Describe (Magic));
            return;
      end case;

      if Pos > Data'Last then
         Fail_Image (Status, Index, "truncated header");
         return;
      end if;
      Require_Separator (Data, Pos, Index, "the magic number", Status);
      if not Succeeded (Status) then
         return;
      end if;

      Header_Number (Data, Pos, Index, "the width", Value, Status);
      if not Succeeded (Status) then
         return;
      elsif Value = 0 then
         Fail_Image (Status, Index, "the width is 0");
         return;
      end if;
      Info.Width := Value;
      Require_Separator (Data, Pos, Index, "the width", Status);
      if not Succeeded (Status) then
         return;
      end if;

      Header_Number (Data, Pos, Index, "the height", Value, Status);
      if not Succeeded (Status) then
         return;
      elsif Value = 0 then
         Fail_Image (Status, Index, "the height is 0");
         return;
      end if;
      Info.Height := Value;
      Require_Separator (Data, Pos, Index, "the height", Status);
      if not Succeeded (Status) then
         return;
      end if;

      Header_Number (Data, Pos, Index, "the maxval", Value, Status);
      if not Succeeded (Status) then
         return;
      elsif Value = 0 or else Value > 65_535 then
         Fail_Image (Status, Index,
                     "the maxval " & Image_Of (Value)
                     & " is outside 1 .. 65535");
         return;
      elsif Info.Colour and then Value > 255 then
         Fail_Image (Status, Index,
                     "colour images with a maxval above 255 (16 bits per "
                     & "sample) are not supported");
         return;
      end if;
      Info.Maxval := Value;

      --  Exactly one whitespace character ends the header. A comment
      --  right after the maxval counts as that separator, up to and
      --  including its line end.
      if Pos > Data'Last then
         Fail_Image (Status, Index,
                     "truncated: the file ends after the header");
         return;
      elsif Is_Netpbm_Space (Data (Pos)) then
         Pos := Pos + 1;
      elsif Data (Pos) = Code_Hash then
         Skip_Comment (Data, Pos);
         if Pos > Data'Last then
            Fail_Image (Status, Index,
                        "truncated: the file ends after the header");
            return;
         end if;
         Pos := Pos + 1;
      else
         Fail_Image (Status, Index,
                     "unexpected " & Describe (Data (Pos))
                     & " after the maxval");
         return;
      end if;

      Pixels := Int64 (Info.Width) * Int64 (Info.Height);
      if Pixels > Max_Pixels then
         Fail_Image (Status, Index,
                     "the image size " & Image_Of (Info.Width) & " x "
                     & Image_Of (Info.Height) & " is too large");
         return;
      end if;
      Samples := Pixels * Samples_Per_Pixel (Info);
      Remaining := Data'Last - Pos + 1;
      if Info.Binary then
         Needed := Samples * Bytes_Per_Sample (Info);
         if Remaining < Needed then
            Fail_Image (Status, Index,
                        "truncated pixel data: " & Image_Of (Needed)
                        & " bytes needed but only " & Image_Of (Remaining)
                        & " present");
            return;
         end if;
      elsif Remaining < 2 * Samples - 1 then
         --  Every sample needs a digit and all but the last a separator.
         Fail_Image (Status, Index,
                     "truncated pixel data: " & Image_Of (Samples)
                     & " samples cannot fit in the remaining "
                     & Image_Of (Remaining) & " bytes");
         return;
      end if;
      Set_Success (Status);
   end Read_PNM_Header;

   procedure Raster_8
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      Info   : PNM_Info;
      Store  : Boolean;
      Slot   : in out Image_Slot;
      Status : out Ks_Status)
   with
     Pre  => In_Data (Data, Pos)
             and then Valid_PNM (Info)
             and then not Info.Colour and then Info.Maxval <= 255
             and then Raster_Fits (Data, Pos, Info)
             and then No_Handles (Slot),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory
             and then (if not Store
                       then Status.Failure /= Failure_Out_Of_Memory)
             and then Pos in Pos'Old .. Data'Last + 1
             and then (if Store and then Succeeded (Status)
                       then Valid_Slot (Slot)
                            and then Slot_Pixels (Slot) <= Data'Length
                       else No_Handles (Slot));
   --  The raster of an 8-bit grey image (P2 or P5, maxval at most 255),
   --  stored in Slot when Store is True and only checked otherwise.

   procedure Raster_8
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      Info   : PNM_Info;
      Store  : Boolean;
      Slot   : in out Image_Slot;
      Status : out Ks_Status)
   is
      W     : constant Int32 := Info.Width;
      H     : constant Int32 := Info.Height;
      Value : Int32;
   begin
      if Store then
         KI.Create (W, H, 0, Slot.Grey_8, Status);
         if not Succeeded (Status) then
            Out_Of_Memory (Status, W, H);
            return;
         end if;
      end if;
      if Info.Binary then
         declare
            Start : constant Int64 := Pos;
            Row   : Int64;
         begin
            for Y in 0 .. H - 1 loop
               pragma Loop_Invariant
                 (if Store
                  then KI.Valid_Image (Slot.Grey_8)
                       and then Slot.Grey_8.Width = W
                       and then Slot.Grey_8.Height = H
                  else Slot.Grey_8 = null);
               pragma Loop_Invariant
                 (Slot.Grey_16 = null and then Slot.Green = null
                  and then Slot.Blue = null);
               Lemma_Mul_Le (Int64 (Y), Int64 (H) - 1, Int64 (W));
               Row := Start + Int64 (Y) * Int64 (W);
               for X in 0 .. W - 1 loop
                  pragma Loop_Invariant
                    (if Store
                     then KI.Valid_Image (Slot.Grey_8)
                          and then Slot.Grey_8.Width = W
                          and then Slot.Grey_8.Height = H
                     else Slot.Grey_8 = null);
                  pragma Loop_Invariant
                    (Slot.Grey_16 = null and then Slot.Green = null
                     and then Slot.Blue = null);
                  Value := Int32 (Data (Row + Int64 (X)));
                  if Value > Info.Maxval then
                     Release (Slot.Grey_8);
                     Fail_Sample (Status, Index, Value, Info.Maxval);
                     return;
                  end if;
                  if Store then
                     Slot.Grey_8.Pixels (Natural (Y), Natural (X)) :=
                       Byte (Value);
                  end if;
               end loop;
            end loop;
            Pos := Start + Int64 (W) * Int64 (H);
         end;
      else
         declare
            Start : constant Int64 := Pos;
         begin
            for Y in 0 .. H - 1 loop
               pragma Loop_Invariant (Pos in Start .. Data'Last + 1);
               pragma Loop_Invariant
                 (if Store
                  then KI.Valid_Image (Slot.Grey_8)
                       and then Slot.Grey_8.Width = W
                       and then Slot.Grey_8.Height = H
                  else Slot.Grey_8 = null);
               pragma Loop_Invariant
                 (Slot.Grey_16 = null and then Slot.Green = null
                  and then Slot.Blue = null);
               for X in 0 .. W - 1 loop
                  pragma Loop_Invariant (Pos in Start .. Data'Last + 1);
                  pragma Loop_Invariant
                    (if Store
                     then KI.Valid_Image (Slot.Grey_8)
                          and then Slot.Grey_8.Width = W
                          and then Slot.Grey_8.Height = H
                     else Slot.Grey_8 = null);
                  pragma Loop_Invariant
                    (Slot.Grey_16 = null and then Slot.Green = null
                     and then Slot.Blue = null);
                  Plain_Sample (Data, Pos, Index, Info.Maxval, Value, Status);
                  if not Succeeded (Status) then
                     Release (Slot.Grey_8);
                     return;
                  end if;
                  if Store then
                     Slot.Grey_8.Pixels (Natural (Y), Natural (X)) :=
                       Byte (Value);
                  end if;
               end loop;
            end loop;
         end;
      end if;
      if Store then
         Slot.Image_Type := Image_Type_Grey_8;
         Slot.Maxval := Info.Maxval;
      end if;
      Set_Success (Status);
   end Raster_8;

   procedure Raster_16
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      Info   : PNM_Info;
      Store  : Boolean;
      Slot   : in out Image_Slot;
      Status : out Ks_Status)
   with
     Pre  => In_Data (Data, Pos)
             and then Valid_PNM (Info)
             and then not Info.Colour and then Info.Maxval > 255
             and then Raster_Fits (Data, Pos, Info)
             and then No_Handles (Slot),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory
             and then (if not Store
                       then Status.Failure /= Failure_Out_Of_Memory)
             and then Pos in Pos'Old .. Data'Last + 1
             and then (if Store and then Succeeded (Status)
                       then Valid_Slot (Slot)
                            and then Slot_Pixels (Slot) <= Data'Length
                       else No_Handles (Slot));
   --  The raster of a 16-bit grey image (maxval above 255; binary samples
   --  most significant byte first).

   procedure Raster_16
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      Info   : PNM_Info;
      Store  : Boolean;
      Slot   : in out Image_Slot;
      Status : out Ks_Status)
   is
      W     : constant Int32 := Info.Width;
      H     : constant Int32 := Info.Height;
      Value : Int32;
   begin
      if Store then
         KI.Create (W, H, 0, Slot.Grey_16, Status);
         if not Succeeded (Status) then
            Out_Of_Memory (Status, W, H);
            return;
         end if;
      end if;
      if Info.Binary then
         declare
            Start : constant Int64 := Pos;
            Row   : Int64;
         begin
            for Y in 0 .. H - 1 loop
               pragma Loop_Invariant
                 (if Store
                  then KI.Valid_Image (Slot.Grey_16)
                       and then Slot.Grey_16.Width = W
                       and then Slot.Grey_16.Height = H
                  else Slot.Grey_16 = null);
               pragma Loop_Invariant
                 (Slot.Grey_8 = null and then Slot.Green = null
                  and then Slot.Blue = null);
               Lemma_Mul_Le (Int64 (Y), Int64 (H) - 1, 2 * Int64 (W));
               Row := Start + Int64 (Y) * (2 * Int64 (W));
               for X in 0 .. W - 1 loop
                  pragma Loop_Invariant
                    (if Store
                     then KI.Valid_Image (Slot.Grey_16)
                          and then Slot.Grey_16.Width = W
                          and then Slot.Grey_16.Height = H
                     else Slot.Grey_16 = null);
                  pragma Loop_Invariant
                    (Slot.Grey_8 = null and then Slot.Green = null
                     and then Slot.Blue = null);
                  Value := Int32 (Data (Row + 2 * Int64 (X))) * 256
                    + Int32 (Data (Row + 2 * Int64 (X) + 1));
                  if Value > Info.Maxval then
                     Release (Slot.Grey_16);
                     Fail_Sample (Status, Index, Value, Info.Maxval);
                     return;
                  end if;
                  if Store then
                     Slot.Grey_16.Pixels (Natural (Y), Natural (X)) :=
                       Interfaces.Unsigned_16 (Value);
                  end if;
               end loop;
            end loop;
            Pos := Start + 2 * (Int64 (W) * Int64 (H));
         end;
      else
         declare
            Start : constant Int64 := Pos;
         begin
            for Y in 0 .. H - 1 loop
               pragma Loop_Invariant (Pos in Start .. Data'Last + 1);
               pragma Loop_Invariant
                 (if Store
                  then KI.Valid_Image (Slot.Grey_16)
                       and then Slot.Grey_16.Width = W
                       and then Slot.Grey_16.Height = H
                  else Slot.Grey_16 = null);
               pragma Loop_Invariant
                 (Slot.Grey_8 = null and then Slot.Green = null
                  and then Slot.Blue = null);
               for X in 0 .. W - 1 loop
                  pragma Loop_Invariant (Pos in Start .. Data'Last + 1);
                  pragma Loop_Invariant
                    (if Store
                     then KI.Valid_Image (Slot.Grey_16)
                          and then Slot.Grey_16.Width = W
                          and then Slot.Grey_16.Height = H
                     else Slot.Grey_16 = null);
                  pragma Loop_Invariant
                    (Slot.Grey_8 = null and then Slot.Green = null
                     and then Slot.Blue = null);
                  Plain_Sample (Data, Pos, Index, Info.Maxval, Value, Status);
                  if not Succeeded (Status) then
                     Release (Slot.Grey_16);
                     return;
                  end if;
                  if Store then
                     Slot.Grey_16.Pixels (Natural (Y), Natural (X)) :=
                       Interfaces.Unsigned_16 (Value);
                  end if;
               end loop;
            end loop;
         end;
      end if;
      if Store then
         Slot.Image_Type := Image_Type_Grey_16;
         Slot.Maxval := Info.Maxval;
      end if;
      Set_Success (Status);
   end Raster_16;

   function Valid_Planes
     (Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data;
      Width, Height    : Int32) return Boolean
   is
     (KI.Valid_Image (Red) and then KI.Valid_Image (Green)
      and then KI.Valid_Image (Blue)
      and then Red.Width = Width and then Red.Height = Height
      and then Green.Width = Width and then Green.Height = Height
      and then Blue.Width = Width and then Blue.Height = Height);
   --  Three planes of a Width x Height colour image.

   procedure Release_Planes (Red, Green, Blue : in out KI.Ks_Image_8_Grey)
   with Post => Red = null and then Green = null and then Blue = null;

   procedure Release_Planes (Red, Green, Blue : in out KI.Ks_Image_8_Grey)
   is
   begin
      Release (Red);
      Release (Green);
      Release (Blue);
   end Release_Planes;

   procedure Raster_Color
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      Info   : PNM_Info;
      Store  : Boolean;
      Slot   : in out Image_Slot;
      Status : out Ks_Status)
   with
     Pre  => In_Data (Data, Pos)
             and then Valid_PNM (Info)
             and then Info.Colour
             and then Raster_Fits (Data, Pos, Info)
             and then No_Handles (Slot),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory
             and then (if not Store
                       then Status.Failure /= Failure_Out_Of_Memory)
             and then Pos in Pos'Old .. Data'Last + 1
             and then (if Store and then Succeeded (Status)
                       then Valid_Slot (Slot)
                            and then Slot_Pixels (Slot) <= Data'Length
                       else No_Handles (Slot));
   --  The raster of a colour image (P3 or P6): red, green and blue samples
   --  per pixel.

   procedure Raster_Color
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      Info   : PNM_Info;
      Store  : Boolean;
      Slot   : in out Image_Slot;
      Status : out Ks_Status)
   is
      W       : constant Int32 := Info.Width;
      H       : constant Int32 := Info.Height;
      R, G, B : Int32;
   begin
      if Store then
         KI.Create_Color (W, H, 0, 0, 0, Slot.Grey_8, Slot.Green, Slot.Blue,
                          Status);
         if not Succeeded (Status) then
            Out_Of_Memory (Status, W, H);
            return;
         end if;
      end if;
      if Info.Binary then
         declare
            Start : constant Int64 := Pos;
            Row   : Int64;
            Base  : Int64;
         begin
            for Y in 0 .. H - 1 loop
               pragma Loop_Invariant
                 (if Store
                  then Valid_Planes (Slot.Grey_8, Slot.Green, Slot.Blue, W, H)
                  else Slot.Grey_8 = null and then Slot.Green = null
                       and then Slot.Blue = null);
               pragma Loop_Invariant (Slot.Grey_16 = null);
               Lemma_Mul_Le (Int64 (Y), Int64 (H) - 1, 3 * Int64 (W));
               Row := Start + Int64 (Y) * (3 * Int64 (W));
               for X in 0 .. W - 1 loop
                  pragma Loop_Invariant
                    (if Store
                     then Valid_Planes
                            (Slot.Grey_8, Slot.Green, Slot.Blue, W, H)
                     else Slot.Grey_8 = null and then Slot.Green = null
                          and then Slot.Blue = null);
                  pragma Loop_Invariant (Slot.Grey_16 = null);
                  Base := Row + 3 * Int64 (X);
                  R := Int32 (Data (Base));
                  G := Int32 (Data (Base + 1));
                  B := Int32 (Data (Base + 2));
                  if R > Info.Maxval or else G > Info.Maxval
                    or else B > Info.Maxval
                  then
                     Release_Planes (Slot.Grey_8, Slot.Green, Slot.Blue);
                     Fail_Sample
                       (Status, Index,
                        (if R > Info.Maxval then R
                         elsif G > Info.Maxval then G
                         else B),
                        Info.Maxval);
                     return;
                  end if;
                  if Store then
                     Slot.Grey_8.Pixels (Natural (Y), Natural (X)) := Byte (R);
                     Slot.Green.Pixels (Natural (Y), Natural (X)) := Byte (G);
                     Slot.Blue.Pixels (Natural (Y), Natural (X)) := Byte (B);
                  end if;
               end loop;
            end loop;
            Pos := Start + 3 * (Int64 (W) * Int64 (H));
         end;
      else
         declare
            Start : constant Int64 := Pos;
         begin
            for Y in 0 .. H - 1 loop
               pragma Loop_Invariant (Pos in Start .. Data'Last + 1);
               pragma Loop_Invariant
                 (if Store
                  then Valid_Planes (Slot.Grey_8, Slot.Green, Slot.Blue, W, H)
                  else Slot.Grey_8 = null and then Slot.Green = null
                       and then Slot.Blue = null);
               pragma Loop_Invariant (Slot.Grey_16 = null);
               for X in 0 .. W - 1 loop
                  pragma Loop_Invariant (Pos in Start .. Data'Last + 1);
                  pragma Loop_Invariant
                    (if Store
                     then Valid_Planes
                            (Slot.Grey_8, Slot.Green, Slot.Blue, W, H)
                     else Slot.Grey_8 = null and then Slot.Green = null
                          and then Slot.Blue = null);
                  pragma Loop_Invariant (Slot.Grey_16 = null);
                  G := 0;
                  B := 0;
                  Plain_Sample (Data, Pos, Index, Info.Maxval, R, Status);
                  if Succeeded (Status) then
                     Plain_Sample (Data, Pos, Index, Info.Maxval, G, Status);
                  end if;
                  if Succeeded (Status) then
                     Plain_Sample (Data, Pos, Index, Info.Maxval, B, Status);
                  end if;
                  if not Succeeded (Status) then
                     Release_Planes (Slot.Grey_8, Slot.Green, Slot.Blue);
                     return;
                  end if;
                  if Store then
                     Slot.Grey_8.Pixels (Natural (Y), Natural (X)) := Byte (R);
                     Slot.Green.Pixels (Natural (Y), Natural (X)) := Byte (G);
                     Slot.Blue.Pixels (Natural (Y), Natural (X)) := Byte (B);
                  end if;
               end loop;
            end loop;
         end;
      end if;
      if Store then
         Slot.Image_Type := Image_Type_Color;
         Slot.Maxval := Info.Maxval;
      end if;
      Set_Success (Status);
   end Raster_Color;

   procedure Decode_PNM_Image
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      Store  : Boolean;
      Slot   : in out Image_Slot;
      Status : out Ks_Status)
   with
     Pre  => Data'Length >= 1 and then Pos in Data'First .. Data'Last
             and then No_Handles (Slot),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory
             and then (if not Store
                       then Status.Failure /= Failure_Out_Of_Memory)
             and then Pos in Pos'Old .. Data'Last + 1
             and then (if Store and then Succeeded (Status)
                       then Valid_Slot (Slot)
                            and then Slot_Pixels (Slot) <= Data'Length
                       else No_Handles (Slot));
   --  Decodes the image whose 'P' is at Pos (image Index of the file, for
   --  messages) and leaves Pos just after its last sample. The image is
   --  stored in Slot when Store is True and only checked otherwise.

   procedure Decode_PNM_Image
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      Store  : Boolean;
      Slot   : in out Image_Slot;
      Status : out Ks_Status)
   is
      Info : PNM_Info;
   begin
      Read_PNM_Header (Data, Pos, Index, Info, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Info.Colour then
         Raster_Color (Data, Pos, Index, Info, Store, Slot, Status);
      elsif Info.Maxval > 255 then
         Raster_16 (Data, Pos, Index, Info, Store, Slot, Status);
      else
         Raster_8 (Data, Pos, Index, Info, Store, Slot, Status);
      end if;
   end Decode_PNM_Image;

   procedure Find_Next_Image
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      More   : out Boolean;
      Status : out Ks_Status)
   with
     Pre  => In_Data (Data, Pos),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then Pos in Pos'Old .. Data'Last + 1
             and then (if Succeeded (Status) and then More
                       then Pos <= Data'Last and then Data (Pos) = Code_P);
   --  After image Index: skips whitespace; More is False at the end of
   --  Data, True when another image starts at Pos; anything else is a
   --  failure.

   procedure Find_Next_Image
     (Data   : Byte_Array;
      Pos    : in out Int64;
      Index  : Int32;
      More   : out Boolean;
      Status : out Ks_Status) is
   begin
      More := False;
      while Pos <= Data'Last and then Is_Netpbm_Space (Data (Pos)) loop
         pragma Loop_Invariant (Pos in Pos'Loop_Entry .. Data'Last);
         Pos := Pos + 1;
      end loop;
      if Pos > Data'Last then
         Set_Success (Status);
      elsif Data (Pos) /= Code_P then
         Fail (Status,
               "unexpected " & Describe (Data (Pos)) & " after image "
               & Image_Of (Index) & " at file offset "
               & Image_Of (Pos - Data'First));
      else
         More := True;
         Set_Success (Status);
      end if;
   end Find_Next_Image;

   procedure Scan_PNM
     (Data   : Byte_Array;
      Count  : out Int32;
      Status : out Ks_Status)
   with
     Pre  => Data'Length >= 1 and then Data (Data'First) = Code_P,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status) then Count in 1 .. Max_Images
                       else Count = 0);
   --  The first pass over a PNM file: checks every image and counts them.

   procedure Scan_PNM
     (Data   : Byte_Array;
      Count  : out Int32;
      Status : out Ks_Status)
   is
      Pos   : Int64 := Data'First;
      Index : Int32 := 0;
      More  : Boolean;
      Dummy : Image_Slot;
   begin
      Count := 0;
      loop
         pragma Loop_Invariant
           (Pos in Data'First .. Data'Last
            and then Index in 0 .. Max_Images - 1
            and then No_Handles (Dummy));
         Decode_PNM_Image (Data, Pos, Index, False, Dummy, Status);
         if not Succeeded (Status) then
            return;
         end if;
         Find_Next_Image (Data, Pos, Index, More, Status);
         if not Succeeded (Status) then
            return;
         elsif not More then
            Count := Index + 1;
            return;
         elsif Index = Max_Images - 1 then
            Fail (Status, "the file holds more than 2147483647 images");
            return;
         end if;
         Index := Index + 1;
      end loop;
   end Scan_PNM;

   procedure Load_PNM
     (Data     : Byte_Array;
      Contents : Ks_Image_File_Contents;
      Status   : out Ks_Status)
   with
     Pre  => Data'Length >= 1 and then Data (Data'First) = Code_P
             and then Contents /= null and then Contents.Count >= 1
             and then (for all I in Contents.Slots'Range
                       => No_Handles (Contents.Slots (I))),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory | Failure_Other
             and then Contents.Kind = Contents.Kind'Old
             and then (if Succeeded (Status)
                       then (for all I in Contents.Slots'Range
                             => Valid_Slot (Contents.Slots (I))
                                and then Slot_Pixels (Contents.Slots (I))
                                           <= Data'Length));
   --  The second pass over a PNM file: decodes Contents.Count images into
   --  the slots (the first pass counted them).

   procedure Load_PNM
     (Data     : Byte_Array;
      Contents : Ks_Image_File_Contents;
      Status   : out Ks_Status)
   is
      Pos  : Int64 := Data'First;
      More : Boolean;
   begin
      Set_Success (Status);
      for I in 1 .. Contents.Count loop
         pragma Loop_Invariant
           (Pos in Data'First .. Data'Last and then Data (Pos) = Code_P);
         pragma Loop_Invariant (Contents.Kind = Contents.Kind'Loop_Entry);
         pragma Loop_Invariant
           (for all J in 1 .. I - 1
            => Valid_Slot (Contents.Slots (J))
               and then Slot_Pixels (Contents.Slots (J)) <= Data'Length);
         pragma Loop_Invariant
           (for all J in I .. Contents.Count
            => No_Handles (Contents.Slots (J)));
         Decode_PNM_Image (Data, Pos, I - 1, True, Contents.Slots (I),
                           Status);
         if not Succeeded (Status) then
            return;
         end if;
         if I < Contents.Count then
            Find_Next_Image (Data, Pos, I - 1, More, Status);
            if not Succeeded (Status) then
               return;
            elsif not More then
               Set_Failure (Status, Failure_Other,
                            "Decode: the second pass found fewer images "
                            & "than the first");
               return;
            end if;
         end if;
      end loop;
   end Load_PNM;

   ---------------------------------------------------------------------
   --  BMP decoding (little endian fields at absolute file offsets)
   ---------------------------------------------------------------------

   BMP_File_Header_Size : constant := 14;
   BMP_Info_Header_Size : constant := 40;
   BMP_Core_Header_Size : constant := 12;
   BMP_Pixels_Per_Metre : constant := 2835;  --  72 dots per inch

   function U8 (Data : Byte_Array; Offset : Int64) return Int64 is
     (Int64 (Data (Data'First + Offset)))
   with Pre  => Data'Length >= 1 and then Offset in 0 .. Data'Length - 1,
        Post => U8'Result in 0 .. 255;
   --  The byte at file offset Offset.

   function U16 (Data : Byte_Array; Offset : Int64) return Int64 is
     (U8 (Data, Offset) + 256 * U8 (Data, Offset + 1))
   with Pre  => Data'Length >= 2 and then Offset in 0 .. Data'Length - 2,
        Post => U16'Result in 0 .. 65_535;

   function U32 (Data : Byte_Array; Offset : Int64) return Int64 is
     (U16 (Data, Offset) + 65_536 * U16 (Data, Offset + 2))
   with Pre  => Data'Length >= 4 and then Offset in 0 .. Data'Length - 4,
        Post => U32'Result in 0 .. 2**32 - 1;

   function S32 (Data : Byte_Array; Offset : Int64) return Int64 is
     (if U32 (Data, Offset) >= 2**31
      then U32 (Data, Offset) - 2**32
      else U32 (Data, Offset))
   with Pre  => Data'Length >= 4 and then Offset in 0 .. Data'Length - 4,
        Post => S32'Result in -2**31 .. 2**31 - 1;

   procedure Need
     (Length : Int64;
      Size   : Int64;
      What   : String;
      Status : out Ks_Status)
   with Pre  => Length >= 0 and then Size > Int64'First
                and then What'Length <= 40,
        Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Image_File
                and then (if Succeeded (Status) then Length >= Size);
   --  Fails unless the file has at least Size bytes.

   procedure Need
     (Length : Int64;
      Size   : Int64;
      What   : String;
      Status : out Ks_Status) is
   begin
      if Length < Size then
         Fail (Status,
               "truncated BMP file: " & What & " needs " & Image_Of (Size)
               & " bytes but the file has only " & Image_Of (Length));
      else
         Set_Success (Status);
      end if;
   end Need;

   type Palette_Map is array (Int64 range 0 .. 255) of Byte;

   type BMP_Info is record
      Length       : Int64 := 0;
      Width        : Int64 := 1;
      Height       : Int64 := 1;
      Bits         : Int64 := 24;
      Top_Down     : Boolean := False;
      Pixel_Offset : Int64 := 0;
      Stride       : Int64 := 4;
      Row_Bytes    : Int64 := 3;
      Entries      : Int64 := 0;
      Grey         : Boolean := False;
   end record;
   --  The header of a BMP file (Length is the size of the file).

   function Valid_BMP (Info : BMP_Info) return Boolean is
     (Info.Length in 1 .. Max_Length
      and then Info.Width in 1 .. 2**31 - 1
      and then Info.Height in 1 .. 2**31 - 1
      and then Info.Width * Info.Height <= Max_Pixels
      and then Info.Bits in 1 | 4 | 8 | 24 | 32
      and then Info.Row_Bytes
                 = (case Info.Bits is
                       when 1      => (Info.Width + 7) / 8,
                       when 4      => (Info.Width * 4 + 7) / 8,
                       when 8      => Info.Width,
                       when 24     => Info.Width * 3,
                       when others => Info.Width * 4)
      and then Info.Stride >= Info.Row_Bytes
      and then Info.Stride <= 4 * Info.Width + 4
      and then Info.Pixel_Offset >= 0
      and then Big (Info.Pixel_Offset)
                 + Big (Info.Stride) * Big (Info.Height - 1)
                 + Big (Info.Row_Bytes) <= Big (Info.Length)
      and then Big (Info.Width) * Big (Info.Height) <= 8 * Big (Info.Length)
      and then (if Info.Bits <= 8
                then Info.Entries in 1 .. 256
                else not Info.Grey))
   with Ghost;
   --  A header that Read_BMP_Header accepted: the pixel data, row after
   --  row Stride bytes apart, lies within the file, and the image has at
   --  most 8 pixels per byte of the file.

   procedure Row_Layout
     (Width, Bits : Int64;
      Row_Bytes   : out Int64;
      Stride      : out Int64)
   with
     Pre  => Width in 1 .. 2**31 - 1 and then Bits in 1 | 4 | 8 | 24 | 32,
     Post => Row_Bytes
               = (case Bits is
                     when 1      => (Width + 7) / 8,
                     when 4      => (Width * 4 + 7) / 8,
                     when 8      => Width,
                     when 24     => Width * 3,
                     when others => Width * 4)
             and then Row_Bytes >= 1
             and then Stride in Row_Bytes .. 4 * Width + 4
             and then Width <= 8 * Row_Bytes;
   --  The bytes of the pixels of a row (Row_Bytes) and of a padded row
   --  (Stride, a multiple of 4).

   procedure Row_Layout
     (Width, Bits : Int64;
      Row_Bytes   : out Int64;
      Stride      : out Int64) is
   begin
      case Bits is
         when 1 =>
            Row_Bytes := (Width + 7) / 8;
            Stride := ((Width + 31) / 32) * 4;
         when 4 =>
            Row_Bytes := (Width * 4 + 7) / 8;
            Stride := ((Width * 4 + 31) / 32) * 4;
         when 8 =>
            Row_Bytes := Width;
            Stride := ((Width * 8 + 31) / 32) * 4;
         when 24 =>
            Row_Bytes := Width * 3;
            Stride := ((Width * 24 + 31) / 32) * 4;
         when others =>
            Row_Bytes := Width * 4;
            Stride := Width * 4;
      end case;
   end Row_Layout;

   procedure Lemma_Pixels_Per_Byte
     (Width, Height, Stride, Row_Bytes, Pixel_Offset, Length : Int64)
   with
     Ghost,
     Global => null,
     Pre    => Width in 1 .. 2**31 - 1 and then Height in 1 .. 2**31 - 1
               and then Row_Bytes in 1 .. 2**34
               and then Width <= 8 * Row_Bytes
               and then Stride in Row_Bytes .. 4 * Width + 4
               and then Pixel_Offset >= 0
               and then Big (Pixel_Offset) + Big (Stride) * Big (Height - 1)
                          + Big (Row_Bytes) <= Big (Length),
     Post   => Big (Width) * Big (Height) <= 8 * Big (Length);
   --  Rows of Row_Bytes bytes, each holding at most 8 pixels per byte,
   --  Stride bytes apart within Length bytes.

   procedure Lemma_Pixels_Per_Byte
     (Width, Height, Stride, Row_Bytes, Pixel_Offset, Length : Int64) is
   begin
      Lemma_Mul_Le (Row_Bytes, Stride, Height - 1);
      pragma Assert
        (Big (Row_Bytes) * Big (Height - 1) + Big (Row_Bytes)
           <= Big (Length) - Big (Pixel_Offset));
      Lemma_Mul_Le (Width, 8 * Row_Bytes, Height);
      pragma Assert
        (Big (8 * Row_Bytes) * Big (Height)
           = 8 * (Big (Row_Bytes) * Big (Height - 1) + Big (Row_Bytes)));
   end Lemma_Pixels_Per_Byte;

   subtype Checked_BMP_Info is BMP_Info
     with Ghost_Predicate => Valid_BMP (Checked_BMP_Info);
   --  Proved at every call, never executed.

   procedure Read_BMP_Header
     (Data      : Byte_Array;
      Info      : out BMP_Info;
      Red_Map   : out Palette_Map;
      Green_Map : out Palette_Map;
      Blue_Map  : out Palette_Map;
      Status    : out Ks_Status)
   with
     Pre  => Data'Length >= 2,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status)
                       then Valid_BMP (Info)
                            and then Info.Length = Data'Length);
   --  Reads and checks the headers and the palette of a BMP file.

   procedure Read_BMP_Header
     (Data      : Byte_Array;
      Info      : out BMP_Info;
      Red_Map   : out Palette_Map;
      Green_Map : out Palette_Map;
      Blue_Map  : out Palette_Map;
      Status    : out Ks_Status)
   is
      Length       : constant Int64 := Data'Length;
      Header_Size  : Int64;
      Width        : Int64;
      Height_Field : Int64;
      Height       : Int64;
      Planes       : Int64;
      Bits         : Int64;
      Compression  : Int64;
      Colours_Used : Int64;
      Entry_Size   : Int64;
      Pixel_Offset : Int64;
      Headers_End  : Int64;
      Entries      : Int64 := 0;
      Stride       : Int64;
      Row_Bytes    : Int64;
      Grey         : Boolean := True;
      Base         : Int64;
   begin
      Info := (others => <>);
      Red_Map := [others => 0];
      Green_Map := [others => 0];
      Blue_Map := [others => 0];
      Need (Length, BMP_File_Header_Size + 4, "the file header", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Pixel_Offset := U32 (Data, 10);
      Header_Size := U32 (Data, 14);

      if Header_Size = BMP_Core_Header_Size then
         Need (Length, BMP_File_Header_Size + BMP_Core_Header_Size,
               "the BITMAPCOREHEADER", Status);
         if not Succeeded (Status) then
            return;
         end if;
         Width := U16 (Data, 18);
         Height_Field := U16 (Data, 20);
         Planes := U16 (Data, 22);
         Bits := U16 (Data, 24);
         Compression := 0;
         Colours_Used := 0;
         Entry_Size := 3;
      elsif Header_Size >= BMP_Info_Header_Size then
         Need (Length, BMP_File_Header_Size + Header_Size,
               "the information header", Status);
         if not Succeeded (Status) then
            return;
         end if;
         Width := S32 (Data, 18);
         Height_Field := S32 (Data, 22);
         Planes := U16 (Data, 26);
         Bits := U16 (Data, 28);
         Compression := U32 (Data, 30);
         Colours_Used := U32 (Data, 46);
         Entry_Size := 4;
      else
         Fail (Status, "unsupported BMP information header size "
                       & Image_Of (Header_Size));
         return;
      end if;
      Headers_End := BMP_File_Header_Size + Header_Size;

      if Planes /= 1 then
         Fail (Status, "malformed BMP file: the plane count is "
                       & Image_Of (Planes) & " instead of 1");
         return;
      elsif Width <= 0 then
         Fail (Status, "malformed BMP file: the width is "
                       & Image_Of (Width));
         return;
      elsif Height_Field = 0 then
         Fail (Status, "malformed BMP file: the height is 0");
         return;
      end if;
      Height := abs Height_Field;
      if Width * Height > Max_Pixels then
         Fail (Status, "the image size " & Image_Of (Width) & " x "
                       & Image_Of (Height) & " is too large");
         return;
      end if;
      Lemma_Mul_Le (1, Width, Height);

      case Bits is
         when 1 | 4 | 8 | 24 =>
            if Compression = 1 or else Compression = 2 then
               Fail (Status,
                     "run-length encoded BMP files are not supported");
               return;
            elsif Compression /= 0 then
               Fail (Status, "unsupported BMP compression method "
                             & Image_Of (Compression) & " for "
                             & Image_Of (Bits) & "-bit pixels");
               return;
            end if;
         when 32 =>
            if Compression = 3 then
               --  Bit-field masks follow a 40-byte header, or are part
               --  of a longer one; either way at offset 54.
               Need (Length, 66, "the bit-field masks", Status);
               if not Succeeded (Status) then
                  return;
               end if;
               if U32 (Data, 54) /= 16#00FF_0000#
                 or else U32 (Data, 58) /= 16#0000_FF00#
                 or else U32 (Data, 62) /= 16#0000_00FF#
               then
                  Fail (Status,
                        "unsupported BMP bit-field masks (only 8 bits "
                        & "per channel in the order blue, green, red "
                        & "are supported)");
                  return;
               end if;
               if Header_Size = BMP_Info_Header_Size then
                  Headers_End := Headers_End + 12;
               end if;
            elsif Compression /= 0 then
               Fail (Status, "unsupported BMP compression method "
                             & Image_Of (Compression)
                             & " for 32-bit pixels");
               return;
            end if;
         when 16 =>
            Fail (Status, "16-bit BMP files are not supported");
            return;
         when others =>
            Fail (Status, "unsupported BMP bit depth " & Image_Of (Bits));
            return;
      end case;

      if Bits <= 8 then
         Entries := (case Bits is when 1 => 2, when 4 => 16, when others => 256);
         if Header_Size /= BMP_Core_Header_Size and then Colours_Used > 0
         then
            if Colours_Used > Entries then
               Fail (Status, "malformed BMP file: the palette has "
                             & Image_Of (Colours_Used) & " entries but "
                             & Image_Of (Bits)
                             & "-bit pixels allow at most "
                             & Image_Of (Entries));
               return;
            end if;
            Entries := Colours_Used;
         end if;
         Need (Length, Headers_End + Entries * Entry_Size,
               "the colour palette", Status);
         if not Succeeded (Status) then
            return;
         end if;
         for I in 0 .. Entries - 1 loop
            Lemma_Mul_Le (I, Entries - 1, Entry_Size);
            Base := Headers_End + I * Entry_Size;
            Blue_Map (I) := Byte (U8 (Data, Base));
            Green_Map (I) := Byte (U8 (Data, Base + 1));
            Red_Map (I) := Byte (U8 (Data, Base + 2));
            Grey := Grey
              and then Red_Map (I) = Green_Map (I)
              and then Green_Map (I) = Blue_Map (I);
         end loop;
         Headers_End := Headers_End + Entries * Entry_Size;
      else
         Grey := False;
      end if;

      if Pixel_Offset < Headers_End then
         Fail (Status, "malformed BMP file: the pixel data offset "
                       & Image_Of (Pixel_Offset)
                       & " points into the headers or the palette");
         return;
      end if;
      Row_Layout (Width, Bits, Row_Bytes, Stride);
      Lemma_Stride (Width, Height, Stride);
      --  The padding of the last row is not required to be present.
      Need (Length, Pixel_Offset + Stride * (Height - 1) + Row_Bytes,
            "the pixel data", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Lemma_Pixels_Per_Byte
        (Width, Height, Stride, Row_Bytes, Pixel_Offset, Length);
      Info := (Length       => Length,
               Width        => Width,
               Height       => Height,
               Bits         => Bits,
               Top_Down     => Height_Field < 0,
               Pixel_Offset => Pixel_Offset,
               Stride       => Stride,
               Row_Bytes    => Row_Bytes,
               Entries      => Entries,
               Grey         => Grey);
      pragma Assert_And_Cut
        (Valid (Status) and then Succeeded (Status)
         and then Info.Length = Data'Length
         and then Valid_BMP (Info));
   end Read_BMP_Header;

   function Palette_Index
     (Data : Byte_Array;
      Bits : Int64;
      Row  : Int64;
      X    : Int64) return Int64
   with
     Pre  => Bits in 1 | 4 | 8
             and then Data'Length >= 1
             and then X in 0 .. 2**31
             and then Row in 0 .. Data'Length
             and then Row + (case Bits is
                                when 1      => X / 8,
                                when 4      => X / 2,
                                when others => X) <= Data'Length - 1,
     Post => Palette_Index'Result in 0 .. 255;
   --  The palette index of pixel X of the row at file offset Row.

   function Palette_Index
     (Data : Byte_Array;
      Bits : Int64;
      Row  : Int64;
      X    : Int64) return Int64
   is
      Value : Byte;
   begin
      case Bits is
         when 8 =>
            return U8 (Data, Row + X);
         when 4 =>
            Value := Byte (U8 (Data, Row + X / 2));
            return (if X mod 2 = 0
                    then Int64 (Interfaces.Shift_Right (Value, 4))
                    else Int64 (Value and 16#0F#));
         when others =>
            Value := Byte (U8 (Data, Row + X / 8));
            return Int64 (Interfaces.Shift_Right (Value, Natural (7 - X mod 8))
                          and 1);
      end case;
   end Palette_Index;

   procedure BMP_Indexed
     (Data      : Byte_Array;
      Info      : Checked_BMP_Info;
      Red_Map   : Palette_Map;
      Green_Map : Palette_Map;
      Blue_Map  : Palette_Map;
      Store     : Boolean;
      Slot      : in out Image_Slot;
      Status    : out Ks_Status)
   with
     Pre  => Info.Length = Data'Length and then Info.Bits <= 8
             and then No_Handles (Slot),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory
             and then (if not Store
                       then Status.Failure /= Failure_Out_Of_Memory)
             and then (if Store and then Succeeded (Status)
                       then Valid_Slot (Slot)
                            and then Slot_Pixels (Slot) <= 8 * Data'Length
                       else No_Handles (Slot));
   --  The pixels of a 1-, 4- or 8-bit BMP file: every palette index is
   --  checked; when Store is True, a grey palette gives an 8-bit grey
   --  image of the palette's grey levels, any other palette a colour
   --  image.

   procedure BMP_Indexed
     (Data      : Byte_Array;
      Info      : Checked_BMP_Info;
      Red_Map   : Palette_Map;
      Green_Map : Palette_Map;
      Blue_Map  : Palette_Map;
      Store     : Boolean;
      Slot      : in out Image_Slot;
      Status    : out Ks_Status)
   is
      W      : constant Int64 := Info.Width;
      H      : constant Int64 := Info.Height;
      W32    : constant Int32 := Int32 (W);
      H32    : constant Int32 := Int32 (H);
      Keep_G : constant Boolean := Store and then Info.Grey;
      Keep_C : constant Boolean := Store and then not Info.Grey;
      R      : Int64;
      Row    : Int64;
      Index  : Int64;
   begin
      if Keep_G then
         KI.Create (W32, H32, 0, Slot.Grey_8, Status);
      elsif Keep_C then
         KI.Create_Color (W32, H32, 0, 0, 0, Slot.Grey_8, Slot.Green,
                          Slot.Blue, Status);
      else
         Set_Success (Status);
      end if;
      if not Succeeded (Status) then
         Out_Of_Memory (Status, W32, H32);
         return;
      end if;
      pragma Assert (Int64 (W32) * Int64 (H32) <= 8 * Int64 (Data'Length));
      for Y in 0 .. H - 1 loop
         pragma Loop_Invariant
           (if Keep_G
            then KI.Valid_Image (Slot.Grey_8)
                 and then Slot.Grey_8.Width = W32
                 and then Slot.Grey_8.Height = H32
                 and then Slot.Green = null and then Slot.Blue = null
            elsif Keep_C
            then Valid_Planes (Slot.Grey_8, Slot.Green, Slot.Blue, W32, H32)
            else Slot.Grey_8 = null and then Slot.Green = null
                 and then Slot.Blue = null);
         pragma Loop_Invariant (Slot.Grey_16 = null);
         R := (if Info.Top_Down then Y else H - 1 - Y);
         Lemma_Mul_Le (R, H - 1, Info.Stride);
         Row := Info.Pixel_Offset + Info.Stride * R;
         for X in 0 .. W - 1 loop
            pragma Loop_Invariant
              (if Keep_G
               then KI.Valid_Image (Slot.Grey_8)
                    and then Slot.Grey_8.Width = W32
                    and then Slot.Grey_8.Height = H32
                    and then Slot.Green = null and then Slot.Blue = null
               elsif Keep_C
               then Valid_Planes (Slot.Grey_8, Slot.Green, Slot.Blue, W32,
                                  H32)
               else Slot.Grey_8 = null and then Slot.Green = null
                    and then Slot.Blue = null);
            pragma Loop_Invariant (Slot.Grey_16 = null);
            Index := Palette_Index (Data, Info.Bits, Row, X);
            if Index >= Info.Entries then
               Release_Planes (Slot.Grey_8, Slot.Green, Slot.Blue);
               Fail (Status, "malformed BMP file: a pixel uses palette "
                             & "index " & Image_Of (Index)
                             & " but the palette has "
                             & Image_Of (Info.Entries) & " entries");
               return;
            end if;
            if Keep_G then
               Slot.Grey_8.Pixels (Natural (Y), Natural (X)) :=
                 Red_Map (Index);
            elsif Keep_C then
               Slot.Grey_8.Pixels (Natural (Y), Natural (X)) :=
                 Red_Map (Index);
               Slot.Green.Pixels (Natural (Y), Natural (X)) :=
                 Green_Map (Index);
               Slot.Blue.Pixels (Natural (Y), Natural (X)) :=
                 Blue_Map (Index);
            end if;
         end loop;
      end loop;
      if Keep_G then
         Slot.Image_Type := Image_Type_Grey_8;
         Slot.Maxval := 255;
         pragma Assert (Valid_Slot (Slot));
         pragma Assert (Slot_Pixels (Slot) <= 8 * Data'Length);
      elsif Keep_C then
         Slot.Image_Type := Image_Type_Color;
         Slot.Maxval := 255;
         pragma Assert (Valid_Slot (Slot));
         pragma Assert (Slot_Pixels (Slot) <= 8 * Data'Length);
      end if;
      Set_Success (Status);
   end BMP_Indexed;

   procedure BMP_Direct
     (Data   : Byte_Array;
      Info   : Checked_BMP_Info;
      Slot   : in out Image_Slot;
      Status : out Ks_Status)
   with
     Pre  => Info.Length = Data'Length and then Info.Bits > 8
             and then No_Handles (Slot),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Slot (Slot)
                            and then Slot_Pixels (Slot) <= 8 * Data'Length
                       else No_Handles (Slot));
   --  The pixels of a 24- or 32-bit BMP file (blue, green, red, and an
   --  ignored fourth byte for 32 bits) as a colour image.

   procedure BMP_Direct
     (Data   : Byte_Array;
      Info   : Checked_BMP_Info;
      Slot   : in out Image_Slot;
      Status : out Ks_Status)
   is
      W     : constant Int64 := Info.Width;
      H     : constant Int64 := Info.Height;
      W32   : constant Int32 := Int32 (W);
      H32   : constant Int32 := Int32 (H);
      R     : Int64;
      Row   : Int64;
      Base  : Int64;
   begin
      KI.Create_Color (W32, H32, 0, 0, 0, Slot.Grey_8, Slot.Green, Slot.Blue,
                       Status);
      if not Succeeded (Status) then
         Out_Of_Memory (Status, W32, H32);
         return;
      end if;
      for Y in 0 .. H - 1 loop
         pragma Loop_Invariant
           (Valid_Planes (Slot.Grey_8, Slot.Green, Slot.Blue, W32, H32)
            and then Slot.Grey_16 = null);
         R := (if Info.Top_Down then Y else H - 1 - Y);
         Lemma_Mul_Le (R, H - 1, Info.Stride);
         Row := Info.Pixel_Offset + Info.Stride * R;
         for X in 0 .. W - 1 loop
            pragma Loop_Invariant
              (Valid_Planes (Slot.Grey_8, Slot.Green, Slot.Blue, W32, H32)
               and then Slot.Grey_16 = null);
            Base := (if Info.Bits = 24 then Row + 3 * X else Row + 4 * X);
            Slot.Blue.Pixels (Natural (Y), Natural (X)) :=
              Byte (U8 (Data, Base));
            Slot.Green.Pixels (Natural (Y), Natural (X)) :=
              Byte (U8 (Data, Base + 1));
            Slot.Grey_8.Pixels (Natural (Y), Natural (X)) :=
              Byte (U8 (Data, Base + 2));
         end loop;
      end loop;
      Slot.Image_Type := Image_Type_Color;
      Slot.Maxval := 255;
      Set_Success (Status);
   end BMP_Direct;

   procedure Decode_BMP
     (Data   : Byte_Array;
      Store  : Boolean;
      Slot   : in out Image_Slot;
      Status : out Ks_Status)
   with
     Pre  => Data'Length >= 2 and then No_Handles (Slot),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_File
                         | Failure_Out_Of_Memory
             and then (if not Store
                       then Status.Failure /= Failure_Out_Of_Memory)
             and then (if Store and then Succeeded (Status)
                       then Valid_Slot (Slot)
                            and then Slot_Pixels (Slot) <= 8 * Data'Length
                       else No_Handles (Slot));
   --  Decodes the image of a BMP file, stored in Slot when Store is True
   --  and only checked otherwise.

   procedure Decode_BMP
     (Data   : Byte_Array;
      Store  : Boolean;
      Slot   : in out Image_Slot;
      Status : out Ks_Status)
   is
      Info      : BMP_Info;
      Red_Map   : Palette_Map;
      Green_Map : Palette_Map;
      Blue_Map  : Palette_Map;
   begin
      Read_BMP_Header (Data, Info, Red_Map, Green_Map, Blue_Map, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Info.Bits <= 8 then
         BMP_Indexed (Data, Info, Red_Map, Green_Map, Blue_Map, Store,
                      Slot, Status);
      elsif Store then
         BMP_Direct (Data, Info, Slot, Status);
      end if;
   end Decode_BMP;

   ---------------------------------------------------------------------
   --  Decoding a file
   ---------------------------------------------------------------------

   procedure Scan
     (Data   : Byte_Array;
      Kind   : out Int32;
      Count  : out Int32;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status)
                       then Data'Length >= 2
                            and then Kind in Kind_Code
                            and then Count in 1 .. Max_Images
                            and then (if Kind = Kind_BMP
                                      then Count = 1
                                           and then Data (Data'First)
                                                      = Code_B
                                      else Data (Data'First) = Code_P)
                       else Kind = 0 and then Count = 0);
   --  The first pass: recognises the format, checks every image and counts
   --  them, without allocating any.

   procedure Scan
     (Data   : Byte_Array;
      Kind   : out Int32;
      Count  : out Int32;
      Status : out Ks_Status) is
   begin
      Kind := 0;
      Count := 0;
      if Data'Length = 0 then
         Fail (Status, "the file is empty");
      elsif Data'Length >= 2
        and then Data (Data'First) = Code_B
        and then Data (Data'First + 1) = Code_M
      then
         declare
            Dummy : Image_Slot;
         begin
            Decode_BMP (Data, False, Dummy, Status);
         end;
         if Succeeded (Status) then
            Kind := Kind_BMP;
            Count := 1;
         end if;
      elsif Data'Length >= 2
        and then Data (Data'First) = Code_P
        and then Is_Digit (Data (Data'First + 1))
      then
         Scan_PNM (Data, Count, Status);
         if Succeeded (Status) then
            Kind := Kind_PNM;
         end if;
      else
         Fail (Status, "unknown image file format (not a PNM or BMP file)");
      end if;
   end Scan;

   procedure Decode
     (Bytes    : Byte_Array;
      Contents : out Ks_Image_File_Contents;
      Status   : out Ks_Status)
   is
      Kind  : Int32;
      Count : Int32;
   begin
      Contents := null;
      Scan (Bytes, Kind, Count, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Allocate_Contents (Count, Contents);
      if Contents = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Decode: not enough memory for " & Image_Of (Count)
                      & " images");
         return;
      end if;
      Contents.Kind := Kind;
      if Kind = Kind_BMP then
         Decode_BMP (Bytes, True, Contents.Slots (1), Status);
      else
         Load_PNM (Bytes, Contents, Status);
      end if;
      if not Succeeded (Status) then
         Free_Contents (Contents);
      end if;
   end Decode;

   procedure Check_Bytes_Request
     (Length     : Int64;
      Null_Bytes : Boolean;
      Status     : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Length in 0 .. Max_Length
                               and then (if Length > 0 then not Null_Bytes));
   --  The checks of the C entry points that take bytes in C memory.

   procedure Check_Bytes_Request
     (Length     : Int64;
      Null_Bytes : Boolean;
      Status     : out Ks_Status) is
   begin
      if Length not in 0 .. Max_Length then
         Bad_Parameter (Status, "Bytes: the length must be in "
                                & "0 .. 72057594037927936");
      elsif Length > 0 and then Null_Bytes then
         Bad_Parameter (Status, "Bytes must not be null");
      else
         Set_Success (Status);
      end if;
   end Check_Bytes_Request;

   No_Bytes : constant Byte_Array (1 .. 0) := [others => 0];

   procedure Decode
     (Bytes    : System.Address;
      Length   : Int64;
      Contents : out Ks_Image_File_Contents;
      Status   : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
   begin
      Contents := null;
      Check_Bytes_Request (Length, Bytes = System.Null_Address, Status);
      if not Succeeded (Status) then
         return;
      elsif Length = 0 then
         Decode (No_Bytes, Contents, Status);
      else
         declare
            View : Byte_Array (1 .. Length)
              with Import, Address => Bytes;
         begin
            Decode (View, Contents, Status);
         end;
      end if;
   end Decode;

   procedure Destroy
     (Contents : in out Ks_Image_File_Contents;
      Status   : out Ks_Status) is
   begin
      Free_Contents (Contents);
      Set_Success (Status);
   end Destroy;

   ---------------------------------------------------------------------
   --  Queries and copies
   ---------------------------------------------------------------------

   function Consistent
     (Contents : not null access constant Ks_Image_File_Contents_Data)
      return Boolean
   is
     (Contents.Count >= 1 and then Contents.Kind in Kind_Code);
   --  What the entry points check of the handle itself (each then checks
   --  the slot it uses).

   procedure Bad_Contents (Operation : Operation_Name; Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad_Contents (Operation : Operation_Name; Status : out Ks_Status)
   is
   begin
      Bad_Parameter (Status, Operation & ": Contents is not a valid image "
                             & "file contents handle");
   end Bad_Contents;

   procedure Image_Count
     (Contents : access constant Ks_Image_File_Contents_Data;
      Result   : out Int32;
      Status   : out Ks_Status) is
   begin
      Result := 0;
      if Contents = null then
         Set_Success (Status);
      elsif not Consistent (Contents) then
         Bad_Contents ("Count", Status);
      else
         Result := Contents.Count;
         Set_Success (Status);
      end if;
   end Image_Count;

   procedure Contents_Kind
     (Contents : access constant Ks_Image_File_Contents_Data;
      Result   : out Int32;
      Status   : out Ks_Status) is
   begin
      Result := 0;
      if Contents = null then
         Set_Success (Status);
      elsif not Consistent (Contents) then
         Bad_Contents ("Kind", Status);
      else
         Result := Contents.Kind;
         Set_Success (Status);
      end if;
   end Contents_Kind;

   procedure Check_Slot
     (Contents  : access constant Ks_Image_File_Contents_Data;
      Index     : Int32;
      Operation : Operation_Name;
      Status    : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then (if Succeeded (Status)
                       then Contents /= null
                            and then Index in 0 .. Contents.Count - 1
                            and then Valid_Slot
                                       (Contents.Slots (Index + 1)));
   --  Index_Out_Of_Range unless image Index exists ("Item: index 4 is not
   --  below Count (4)"); Bad_Parameter for an inconsistent handle.

   procedure Check_Slot
     (Contents  : access constant Ks_Image_File_Contents_Data;
      Index     : Int32;
      Operation : Operation_Name;
      Status    : out Ks_Status) is
   begin
      if Contents = null then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Item: index " & Image_Of (Index)
                      & " is not below Count (0)");
      elsif not Consistent (Contents) then
         Bad_Contents (Operation, Status);
      elsif Index < 0 or else Index >= Contents.Count then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Item: index " & Image_Of (Index)
                      & " is not below Count ("
                      & Image_Of (Contents.Count) & ")");
      elsif not Valid_Slot (Contents.Slots (Index + 1)) then
         Bad_Contents (Operation, Status);
      else
         Set_Success (Status);
      end if;
   end Check_Slot;

   procedure Image_Info
     (Contents   : access constant Ks_Image_File_Contents_Data;
      Index      : Int32;
      Image_Type : out Int32;
      Maxval     : out Int32;
      Status     : out Ks_Status) is
   begin
      Image_Type := 0;
      Maxval := 0;
      Check_Slot (Contents, Index, "Image_Info", Status);
      if Succeeded (Status) then
         Image_Type := Contents.Slots (Index + 1).Image_Type;
         Maxval := Contents.Slots (Index + 1).Maxval;
      end if;
   end Image_Info;

   procedure Check_Read_Index
     (Contents : access constant Ks_Image_File_Contents_Data;
      Index    : Int32;
      Status   : out Ks_Status)
   is
      Count : Int32;
   begin
      Image_Count (Contents, Count, Status);
      if not Succeeded (Status) then
         return;
      elsif Contents = null or else Index not in 0 .. Count - 1 then
         Fail (Status, "the file holds " & Image_Of (Count)
                       & " image(s); there is no image with index "
                       & Image_Of (Index));
      end if;
   end Check_Read_Index;

   procedure Wrong_Type
     (Operation : Operation_Name;
      Index     : Int32;
      Expected  : Operation_Name;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;
   --  "<Operation>: image <Index> is not <Expected>".

   procedure Wrong_Type
     (Operation : Operation_Name;
      Index     : Int32;
      Expected  : Operation_Name;
      Status    : out Ks_Status) is
   begin
      Bad_Parameter (Status, Operation & ": image " & Image_Of (Index)
                             & " is not " & Expected);
   end Wrong_Type;

   procedure Get_8_Grey
     (Contents : access constant Ks_Image_File_Contents_Data;
      Index    : Int32;
      Image    : out KI.Ks_Image_8_Grey;
      Status   : out Ks_Status) is
   begin
      Image := null;
      Check_Slot (Contents, Index, "Get_8_Grey", Status);
      if not Succeeded (Status) then
         return;
      elsif Contents.Slots (Index + 1).Image_Type /= Image_Type_Grey_8 then
         Wrong_Type ("Get_8_Grey", Index, "an 8-bit grey image", Status);
         return;
      end if;
      KI.Duplicate (Contents.Slots (Index + 1).Grey_8, Image, Status);
   end Get_8_Grey;

   procedure Get_16_Grey
     (Contents : access constant Ks_Image_File_Contents_Data;
      Index    : Int32;
      Image    : out KI.Ks_Image_16_Grey;
      Status   : out Ks_Status) is
   begin
      Image := null;
      Check_Slot (Contents, Index, "Get_16_Grey", Status);
      if not Succeeded (Status) then
         return;
      elsif Contents.Slots (Index + 1).Image_Type /= Image_Type_Grey_16 then
         Wrong_Type ("Get_16_Grey", Index, "a 16-bit grey image", Status);
         return;
      end if;
      KI.Duplicate (Contents.Slots (Index + 1).Grey_16, Image, Status);
   end Get_16_Grey;

   procedure Get_24_Planar_Color
     (Contents         : access constant Ks_Image_File_Contents_Data;
      Index            : Int32;
      Red, Green, Blue : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status) is
   begin
      Red := null;
      Green := null;
      Blue := null;
      Check_Slot (Contents, Index, "Get_24_Planar_Color", Status);
      if not Succeeded (Status) then
         return;
      elsif Contents.Slots (Index + 1).Image_Type /= Image_Type_Color then
         Wrong_Type ("Get_24_Planar_Color", Index, "a colour image",
                     Status);
         return;
      end if;
      KI.Duplicate_Color
        (Contents.Slots (Index + 1).Grey_8, Contents.Slots (Index + 1).Green,
         Contents.Slots (Index + 1).Blue, Red, Green, Blue, Status);
   end Get_24_Planar_Color;

   procedure Convert_16
     (Source : not null access constant KI.Ks_Image_16_Grey_Data;
      Maxval : Int32;
      Image  : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => KI.Valid_Image (Source) and then Maxval in 1 .. 65_535,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) then KI.Valid_Image (Image)
                       else Image = null);
   --  round (V * 255 / Maxval), half up, exactly, for every sample V.

   procedure Convert_16
     (Source : not null access constant KI.Ks_Image_16_Grey_Data;
      Maxval : Int32;
      Image  : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Value : Int64;
   begin
      KI.Create (Source.Width, Source.Height, 0, Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Image.Pixels'Range (1) loop
         pragma Loop_Invariant
           (KI.Valid_Image (Image)
            and then Image.Width = Source.Width
            and then Image.Height = Source.Height);
         for X in Image.Pixels'Range (2) loop
            pragma Loop_Invariant
              (KI.Valid_Image (Image)
               and then Image.Width = Source.Width
               and then Image.Height = Source.Height);
            Value := (Int64 (Source.Pixels (Y, X)) * 510 + Int64 (Maxval))
                     / (2 * Int64 (Maxval));
            Image.Pixels (Y, X) := Byte (Int64'Min (Value, 255));
         end loop;
      end loop;
   end Convert_16;

   procedure Convert_Color
     (Red, Green, Blue : not null access constant KI.Ks_Image_8_Grey_Data;
      Image            : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status)
   with
     Pre  => Valid_Planes (Red, Green, Blue, Red.Width, Red.Height),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) then KI.Valid_Image (Image)
                       else Image = null);
   --  round (0.299 R + 0.587 G + 0.114 B), half up, exactly.

   procedure Convert_Color
     (Red, Green, Blue : not null access constant KI.Ks_Image_8_Grey_Data;
      Image            : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status)
   is
      Value : Int64;
   begin
      KI.Create (Red.Width, Red.Height, 0, Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Image.Pixels'Range (1) loop
         pragma Loop_Invariant
           (KI.Valid_Image (Image)
            and then Image.Width = Red.Width
            and then Image.Height = Red.Height);
         for X in Image.Pixels'Range (2) loop
            pragma Loop_Invariant
              (KI.Valid_Image (Image)
               and then Image.Width = Red.Width
               and then Image.Height = Red.Height);
            --  At most (255 * 1000 + 500) / 1000 = 255.
            Value := (299 * Int64 (Red.Pixels (Y, X))
                      + 587 * Int64 (Green.Pixels (Y, X))
                      + 114 * Int64 (Blue.Pixels (Y, X)) + 500) / 1000;
            Image.Pixels (Y, X) := Byte (Value);
         end loop;
      end loop;
   end Convert_Color;

   procedure Get_8_Grey_Converted
     (Contents : access constant Ks_Image_File_Contents_Data;
      Index    : Int32;
      Image    : out KI.Ks_Image_8_Grey;
      Status   : out Ks_Status) is
   begin
      Image := null;
      Check_Slot (Contents, Index, "Get_8_Grey_Converted", Status);
      if not Succeeded (Status) then
         return;
      end if;
      case Contents.Slots (Index + 1).Image_Type is
         when Image_Type_Grey_8 =>
            KI.Duplicate (Contents.Slots (Index + 1).Grey_8, Image, Status);
         when Image_Type_Grey_16 =>
            Convert_16 (Contents.Slots (Index + 1).Grey_16,
                        Contents.Slots (Index + 1).Maxval, Image, Status);
         when others =>
            Convert_Color (Contents.Slots (Index + 1).Grey_8,
                           Contents.Slots (Index + 1).Green,
                           Contents.Slots (Index + 1).Blue, Image, Status);
      end case;
   end Get_8_Grey_Converted;

   ---------------------------------------------------------------------
   --  Formats and encodings
   ---------------------------------------------------------------------

   function To_Lower (C : Character) return Character is
     (if C in 'A' .. 'Z'
        or else Character'Pos (C) in 192 .. 214 | 216 .. 222
      then Character'Val (Character'Pos (C) + 32)
      else C);
   --  Ada.Characters.Handling.To_Lower: the Latin-1 upper case letters.

   procedure Format_From_Name
     (Name   : String;
      Format : out Int32;
      Status : out Ks_Status)
   is
      Dot   : Natural := 0;
      Found : Boolean := False;
   begin
      Format := 0;
      for I in reverse Name'Range loop
         pragma Loop_Invariant (not Found);
         if Name (I) = '.' then
            Dot := I;
            Found := True;
            exit;
         end if;
         exit when Name (I) in '/' | '\';
      end loop;
      declare
         Length : constant Natural := (if Found then Name'Last - Dot else 0);
         Shown  : String (1 .. Natural'Min (Length, 100));
      begin
         for I in Shown'Range loop
            Shown (I) := To_Lower (Name (Dot + I));
         end loop;
         if Shown = "pgm" then
            Format := Format_PGM;
         elsif Shown = "ppm" then
            Format := Format_PPM;
         elsif Shown = "pnm" then
            Format := Format_PNM;
         elsif Shown = "bmp" then
            Format := Format_BMP;
         end if;
         if Format /= 0 then
            Set_Success (Status);
         else
            Fail (Status,
                  "cannot choose an image format for writing from the "
                  & "extension """ & Shown
                  & """ (use .pgm, .ppm, .pnm or .bmp)");
         end if;
      end;
   end Format_From_Name;

   procedure Format_From_Name
     (Name   : System.Address;
      Length : Int32;
      Format : out Int32;
      Status : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
   begin
      Format := 0;
      if Length < 0 then
         Bad_Parameter (Status, "Format_From_Name: the length must not be "
                                & "negative");
      elsif Length = 0 then
         Format_From_Name ("", Format, Status);
      elsif Name = System.Null_Address then
         Bad_Parameter (Status, "Format_From_Name: Name must not be null");
      else
         declare
            View : String (1 .. Natural (Length))
              with Import, Address => Name;
         begin
            Format_From_Name (View, Format, Status);
         end;
      end if;
   end Format_From_Name;

   function Is_BMP (Encoding : Encoding_Code) return Boolean is
     (Encoding in Encoding_BMP_8 | Encoding_BMP_24);

   function Bytes_Per_Pixel (Encoding : Encoding_Code) return Int64 is
     (case Encoding is
         when Encoding_P5_8 | Encoding_BMP_8 => 1,
         when Encoding_P5_16                 => 2,
         when others                         => 3);
   --  The bytes of one pixel in the raster.

   function BMP_Stride (Encoding : Encoding_Code; Width : Int64) return Int64
   is
     (if Encoding = Encoding_BMP_8
      then ((Width * 8 + 31) / 32) * 4
      else ((Width * 24 + 31) / 32) * 4)
   with Pre  => Is_BMP (Encoding) and then Width in 1 .. 2**31 - 1,
        Post => BMP_Stride'Result
                  in Width * Bytes_Per_Pixel (Encoding) .. 4 * Width + 4;
   --  The bytes of a padded row.

   function BMP_Data_Offset (Encoding : Encoding_Code) return Int64 is
     (if Encoding = Encoding_BMP_8 then 14 + 40 + 256 * 4 else 14 + 40);
   --  The file header, BITMAPINFOHEADER and (for 8 bits) the palette.

   function PNM_Header_Text
     (Encoding      : Encoding_Code;
      Width, Height : Int32) return String
   with Pre  => not Is_BMP (Encoding),
        Post => PNM_Header_Text'Result'First = 1
                and then PNM_Header_Text'Result'Length in 1 .. 70;
   --  "P5\n<Width> <Height>\n<Maxval>\n" (P6 for the colour encodings).

   function PNM_Header_Text
     (Encoding      : Encoding_Code;
      Width, Height : Int32) return String
   is
      Text : constant String :=
        "P" & (if Encoding in Encoding_P5_8 | Encoding_P5_16 then '5'
               else '6')
        & ASCII.LF & Image_Of (Width) & ' ' & Image_Of (Height) & ASCII.LF
        & (if Encoding = Encoding_P5_16 then "65535" else "255")
        & ASCII.LF;
      Result : constant String (1 .. Text'Length) := Text;
   begin
      return Result;
   end PNM_Header_Text;

   function Valid_Size (Width, Height : Int32) return Boolean is
     (Width >= 1 and then Height >= 1
      and then Int64 (Width) * Int64 (Height) <= Max_Pixels);

   function Encoded_Length
     (Encoding      : Encoding_Code;
      Width, Height : Int32;
      Separator     : Int32) return Int64
   with Pre  => Valid_Size (Width, Height) and then Separator in 0 .. 1,
        Post => Encoded_Length'Result in 1 .. 4 * Max_Pixels + 2_000
                and then
                  (if Is_BMP (Encoding)
                   then Big (Encoded_Length'Result)
                          = Big (Separator) + Big (BMP_Data_Offset (Encoding))
                            + Big (BMP_Stride (Encoding, Int64 (Width)))
                              * Big (Height)
                   else Encoded_Length'Result
                          = Int64 (Separator)
                            + PNM_Header_Text (Encoding, Width, Height)'Length
                            + Int64 (Width) * Int64 (Height)
                              * Bytes_Per_Pixel (Encoding));
   --  The number of bytes Encode writes.

   function Encoded_Length
     (Encoding      : Encoding_Code;
      Width, Height : Int32;
      Separator     : Int32) return Int64
   is
      W : constant Int64 := Int64 (Width);
      H : constant Int64 := Int64 (Height);
   begin
      if Is_BMP (Encoding) then
         Lemma_Stride (W, H, BMP_Stride (Encoding, W));
         return Int64 (Separator) + BMP_Data_Offset (Encoding)
           + BMP_Stride (Encoding, W) * H;
      else
         return Int64 (Separator)
           + PNM_Header_Text (Encoding, Width, Height)'Length
           + W * H * Bytes_Per_Pixel (Encoding);
      end if;
   end Encoded_Length;

   procedure Choose_Encoding
     (Format        : Int32;
      Image_Type    : Int32;
      Width, Height : Int32;
      Encoding      : out Int32;
      Status        : out Ks_Status)
   is
      Kind : Int32;
   begin
      Encoding := 0;
      if Format not in Format_Code then
         Bad_Parameter (Status, "Choose_Encoding: Format must be a format "
                                & "code (1 .. 4)");
         return;
      elsif Width < 0 or else Height < 0 then
         Bad_Parameter (Status, "Choose_Encoding: Width and Height must "
                                & "not be negative");
         return;
      elsif Width = 0 or else Height = 0 then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "the image to write has no pixels");
         return;
      end if;
      case Image_Type is
         when Image_Type_Grey_8 =>
            Kind := (case Format is
                        when Format_PPM => Encoding_P6_From_Grey,
                        when Format_BMP => Encoding_BMP_8,
                        when others     => Encoding_P5_8);
         when Image_Type_Grey_16 =>
            if Format in Format_PPM | Format_BMP then
               Fail (Status, "a " & Extension_Text (Format)
                             & " file cannot hold a 16-bit grey image (use "
                             & ".pgm or .pnm)");
               return;
            end if;
            Kind := Encoding_P5_16;
         when Image_Type_Color =>
            if Format = Format_PGM then
               Fail (Status, "a " & Extension_Text (Format)
                             & " file cannot hold a colour image (use "
                             & ".ppm, .pnm or .bmp)");
               return;
            end if;
            Kind := (if Format = Format_BMP then Encoding_BMP_24
                     else Encoding_P6_Color);
         when others =>
            Fail (Status, "unsupported image type");
            return;
      end case;
      if Int64 (Width) * Int64 (Height) > Max_Pixels then
         Bad_Parameter (Status, "Choose_Encoding: the image size "
                                & Image_Of (Width) & " x "
                                & Image_Of (Height) & " is too large");
         return;
      elsif Is_BMP (Kind)
        and then Encoded_Length (Kind, Width, Height, 0) > Max_BMP_File_Size
      then
         Fail (Status, "the image is too large for a BMP file");
         return;
      end if;
      Encoding := Kind;
      Set_Success (Status);
   end Choose_Encoding;

   procedure Check_Encoding_Request
     (Operation     : Operation_Name;
      Encoding      : Int32;
      Width, Height : Int32;
      Separator     : Int32;
      Status        : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Image_File
                and then (if Succeeded (Status)
                          then Encoding in Encoding_Code
                               and then Valid_Size (Width, Height)
                               and then Separator in 0 .. 1
                               and then (if Is_BMP (Encoding)
                                         then Separator = 0
                                              and then Encoded_Length
                                                         (Encoding, Width,
                                                          Height, Separator)
                                                       <= Max_BMP_File_Size));
   --  The checks of Encoded_Size and Encode on the encoding and the size.

   procedure Check_Encoding_Request
     (Operation     : Operation_Name;
      Encoding      : Int32;
      Width, Height : Int32;
      Separator     : Int32;
      Status        : out Ks_Status) is
   begin
      if Encoding not in Encoding_Code then
         Bad_Parameter (Status, Operation & ": Encoding must be an encoding "
                                & "code (1 .. 6)");
      elsif Separator not in 0 .. 1 then
         Bad_Parameter (Status, Operation & ": Separator must be 0 or 1");
      elsif Is_BMP (Encoding) and then Separator = 1 then
         Bad_Parameter (Status, Operation & ": a BMP encoding takes no "
                                & "separator");
      elsif not Valid_Size (Width, Height) then
         Bad_Parameter (Status, Operation & ": the image size "
                                & Image_Of (Width) & " x "
                                & Image_Of (Height)
                                & " is not between 1 x 1 and 2147483647 "
                                & "pixels");
      elsif Is_BMP (Encoding)
        and then Encoded_Length (Encoding, Width, Height, Separator)
                   > Max_BMP_File_Size
      then
         Fail (Status, "the image is too large for a BMP file");
      else
         Set_Success (Status);
      end if;
   end Check_Encoding_Request;

   procedure Encoded_Size
     (Encoding      : Int32;
      Width, Height : Int32;
      Separator     : Int32;
      Size          : out Int64;
      Status        : out Ks_Status) is
   begin
      Size := 0;
      Check_Encoding_Request ("Encoded_Size", Encoding, Width, Height,
                              Separator, Status);
      if Succeeded (Status) then
         Size := Encoded_Length (Encoding, Width, Height, Separator);
      end if;
   end Encoded_Size;

   procedure Check_Append
     (Encoding   : Int32;
      Count      : Int32;
      Disk_Size  : Int64;
      Final_Byte : Byte;
      Separator  : out Int32;
      New_Count  : out Int32;
      Status     : out Ks_Status) is
   begin
      Separator := 0;
      New_Count := 0;
      if Encoding not in Encoding_Code then
         Bad_Parameter (Status, "Check_Append: Encoding must be an encoding "
                                & "code (1 .. 6)");
      elsif Count < 0 or else Disk_Size < 0 then
         Bad_Parameter (Status, "Check_Append: Count and Disk_Size must "
                                & "not be negative");
      elsif Is_BMP (Encoding) and then Count > 0 then
         Fail (Status, "a BMP file holds only one image and this one "
                       & "already has it");
      elsif Is_BMP (Encoding) and then Disk_Size > 0 then
         Fail (Status, "a BMP file holds only one image and this file is "
                       & "not empty");
      elsif Count = Max_Images then
         Fail (Status, "the file already holds 2147483647 images");
      else
         if not Is_BMP (Encoding) and then Disk_Size > 0
           and then not Is_Netpbm_Space (Final_Byte)
         then
            Separator := 1;
         end if;
         New_Count := Count + 1;
         Set_Success (Status);
      end if;
   end Check_Append;

   ---------------------------------------------------------------------
   --  Encoding
   ---------------------------------------------------------------------

   procedure Put_Text
     (Bytes  : in out Byte_Array;
      Offset : Int64;
      Text   : String)
   with Pre  => Text'First = 1 and then Text'Length <= 100
                and then Offset in 0 .. Bytes'Length
                and then Offset + Text'Length <= Bytes'Length;
   --  The characters of Text at Offset.

   procedure Put_Text
     (Bytes  : in out Byte_Array;
      Offset : Int64;
      Text   : String) is
   begin
      for I in Text'Range loop
         Bytes (Bytes'First + Offset + Int64 (I - 1)) :=
           Character'Pos (Text (I));
      end loop;
   end Put_Text;

   procedure Put_LE
     (Bytes  : in out Byte_Array;
      Offset : Int64;
      Value  : Int64;
      Size   : Int64)
   with Pre => Size in 2 | 4 and then Value in 0 .. 2**32 - 1
               and then (if Size = 2 then Value <= 65_535)
               and then Offset in 0 .. Bytes'Length
               and then Offset + Size <= Bytes'Length;
   --  The low Size bytes of Value at Offset, least significant first.

   procedure Put_LE
     (Bytes  : in out Byte_Array;
      Offset : Int64;
      Value  : Int64;
      Size   : Int64)
   is
      Rest : Int64 := Value;
   begin
      for I in 0 .. Size - 1 loop
         pragma Loop_Invariant (Rest >= 0);
         Bytes (Bytes'First + Offset + I) := Byte (Rest mod 256);
         Rest := Rest / 256;
      end loop;
   end Put_LE;

   procedure Put_BMP_Headers
     (Bytes         : in out Byte_Array;
      Encoding      : Encoding_Code;
      Width, Height : Int64;
      Data_Size     : Int64)
   with Pre => Is_BMP (Encoding)
               and then Width in 1 .. 2**31 - 1
               and then Height in 1 .. 2**31 - 1
               and then Data_Size in 0 .. Max_BMP_File_Size
               and then Bytes'Length = BMP_Data_Offset (Encoding) + Data_Size
               and then Bytes'Length <= Max_BMP_File_Size;
   --  The file header, the BITMAPINFOHEADER and (for 8 bits) the grey
   --  palette of a bottom-up, uncompressed bitmap.

   procedure Put_BMP_Headers
     (Bytes         : in out Byte_Array;
      Encoding      : Encoding_Code;
      Width, Height : Int64;
      Data_Size     : Int64)
   is
      Offset    : constant Int64 := BMP_Data_Offset (Encoding);
      Bits      : constant Int64 :=
        (if Encoding = Encoding_BMP_8 then 8 else 24);
   begin
      --  BITMAPFILEHEADER
      Bytes (Bytes'First) := Character'Pos ('B');
      Bytes (Bytes'First + 1) := Character'Pos ('M');
      Put_LE (Bytes, 2, Offset + Data_Size, 4);
      Put_LE (Bytes, 6, 0, 4);
      Put_LE (Bytes, 10, Offset, 4);
      --  BITMAPINFOHEADER
      Put_LE (Bytes, 14, BMP_Info_Header_Size, 4);
      Put_LE (Bytes, 18, Width, 4);
      Put_LE (Bytes, 22, Height, 4);
      Put_LE (Bytes, 26, 1, 2);
      Put_LE (Bytes, 28, Bits, 2);
      Put_LE (Bytes, 30, 0, 4);
      Put_LE (Bytes, 34, Data_Size, 4);
      Put_LE (Bytes, 38, BMP_Pixels_Per_Metre, 4);
      Put_LE (Bytes, 42, BMP_Pixels_Per_Metre, 4);
      Put_LE (Bytes, 46, (if Encoding = Encoding_BMP_8 then 256 else 0), 4);
      Put_LE (Bytes, 50, 0, 4);
      if Encoding = Encoding_BMP_8 then
         for Level in Int64 range 0 .. 255 loop
            Bytes (Bytes'First + 54 + 4 * Level) := Byte (Level);
            Bytes (Bytes'First + 55 + 4 * Level) := Byte (Level);
            Bytes (Bytes'First + 56 + 4 * Level) := Byte (Level);
            Bytes (Bytes'First + 57 + 4 * Level) := 0;
         end loop;
      end if;
   end Put_BMP_Headers;

   procedure Check_Bytes_Length
     (Operation : Operation_Name;
      Bytes     : Byte_Array;
      Expected  : Int64;
      Status    : out Ks_Status)
   with Pre  => Expected >= 0,
        Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then Bytes'Length = Expected);
   --  Bad_Parameter unless Bytes has the encoded size.

   procedure Check_Bytes_Length
     (Operation : Operation_Name;
      Bytes     : Byte_Array;
      Expected  : Int64;
      Status    : out Ks_Status) is
   begin
      if Bytes'Length /= Expected then
         Bad_Parameter (Status, Operation & ": Bytes has "
                                & Image_Of (Int64 (Bytes'Length))
                                & " bytes but the encoded image needs "
                                & Image_Of (Expected));
      else
         Set_Success (Status);
      end if;
   end Check_Bytes_Length;

   procedure Encode_8_Grey
     (Encoding  : Int32;
      Separator : Int32;
      Image     : access constant KI.Ks_Image_8_Grey_Data;
      Bytes     : in out Byte_Array;
      Status    : out Ks_Status)
   is
      Operation : constant Operation_Name := "Encode_8_Grey";
      W, H      : Int64;
      Start     : Int64;
      Row       : Int64;
      Stride    : Int64;
      Value     : Byte;
   begin
      if Encoding not in Encoding_P5_8 | Encoding_P6_From_Grey
                        | Encoding_BMP_8
      then
         Bad_Parameter (Status, Operation & ": Encoding must be P5_8, "
                                & "P6_From_Grey or BMP_8");
         return;
      elsif Image = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      Operation & ": the image has no pixels");
         return;
      elsif not KI.Valid_Image (Image) then
         Bad_Parameter (Status, Operation & ": Image is not a valid image "
                                & "handle");
         return;
      end if;
      Check_Encoding_Request (Operation, Encoding, Image.Width, Image.Height,
                              Separator, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Bytes_Length
        (Operation, Bytes,
         Encoded_Length (Encoding, Image.Width, Image.Height, Separator),
         Status);
      if not Succeeded (Status) then
         return;
      end if;

      W := Int64 (Image.Width);
      H := Int64 (Image.Height);
      if Encoding = Encoding_BMP_8 then
         Stride := BMP_Stride (Encoding, W);
         Lemma_Stride (W, H, Stride);
         Put_BMP_Headers (Bytes, Encoding, W, H, Stride * H);
         Start := BMP_Data_Offset (Encoding);
         for R in 0 .. H - 1 loop
            Lemma_Mul_Le (R, H - 1, Stride);
            Row := Start + R * Stride;
            for X in 0 .. W - 1 loop
               Bytes (Bytes'First + Row + X) :=
                 Image.Pixels (Natural (H - 1 - R), Natural (X));
            end loop;
            for P in W .. Stride - 1 loop
               Bytes (Bytes'First + Row + P) := 0;
            end loop;
         end loop;
      else
         declare
            Header : constant String :=
              PNM_Header_Text (Encoding, Image.Width, Image.Height);
            Base   : Int64;
         begin
            if Separator = 1 then
               Bytes (Bytes'First) := Character'Pos (ASCII.LF);
            end if;
            Put_Text (Bytes, Int64 (Separator), Header);
            Start := Int64 (Separator) + Header'Length;
            if Encoding = Encoding_P5_8 then
               for Y in 0 .. H - 1 loop
                  Lemma_Mul_Le (Y, H - 1, W);
                  Row := Start + Y * W;
                  for X in 0 .. W - 1 loop
                     Bytes (Bytes'First + Row + X) :=
                       Image.Pixels (Natural (Y), Natural (X));
                  end loop;
               end loop;
            else
               --  P6 with equal red, green and blue.
               for Y in 0 .. H - 1 loop
                  Lemma_Mul_Le (Y, H - 1, W * 3);
                  Row := Start + Y * (W * 3);
                  for X in 0 .. W - 1 loop
                     Value := Image.Pixels (Natural (Y), Natural (X));
                     Base := Bytes'First + Row + 3 * X;
                     Bytes (Base) := Value;
                     Bytes (Base + 1) := Value;
                     Bytes (Base + 2) := Value;
                  end loop;
               end loop;
            end if;
         end;
      end if;
   end Encode_8_Grey;

   procedure Encode_16_Grey
     (Encoding  : Int32;
      Separator : Int32;
      Image     : access constant KI.Ks_Image_16_Grey_Data;
      Bytes     : in out Byte_Array;
      Status    : out Ks_Status)
   is
      Operation : constant Operation_Name := "Encode_16_Grey";
      W, H      : Int64;
      Start     : Int64;
      Row       : Int64;
      Value     : Interfaces.Unsigned_16;
   begin
      if Encoding /= Encoding_P5_16 then
         Bad_Parameter (Status, Operation & ": Encoding must be P5_16");
         return;
      elsif Image = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      Operation & ": the image has no pixels");
         return;
      elsif not KI.Valid_Image (Image) then
         Bad_Parameter (Status, Operation & ": Image is not a valid image "
                                & "handle");
         return;
      end if;
      Check_Encoding_Request (Operation, Encoding, Image.Width, Image.Height,
                              Separator, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Bytes_Length
        (Operation, Bytes,
         Encoded_Length (Encoding, Image.Width, Image.Height, Separator),
         Status);
      if not Succeeded (Status) then
         return;
      end if;

      W := Int64 (Image.Width);
      H := Int64 (Image.Height);
      declare
         Header : constant String :=
           PNM_Header_Text (Encoding, Image.Width, Image.Height);
      begin
         if Separator = 1 then
            Bytes (Bytes'First) := Character'Pos (ASCII.LF);
         end if;
         Put_Text (Bytes, Int64 (Separator), Header);
         Start := Int64 (Separator) + Header'Length;
         for Y in 0 .. H - 1 loop
            Lemma_Mul_Le (Y, H - 1, W * 2);
            Row := Start + Y * (W * 2);
            for X in 0 .. W - 1 loop
               Value := Image.Pixels (Natural (Y), Natural (X));
               Bytes (Bytes'First + Row + X * 2) :=
                 Byte (Interfaces.Shift_Right (Value, 8));
               Bytes (Bytes'First + Row + X * 2 + 1) := Byte (Value and 255);
            end loop;
         end loop;
      end;
   end Encode_16_Grey;

   procedure Encode_24_Planar_Color
     (Encoding         : Int32;
      Separator        : Int32;
      Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data;
      Bytes            : in out Byte_Array;
      Status           : out Ks_Status)
   is
      Operation : constant Operation_Name := "Encode_24_Planar_Color";
      W, H      : Int64;
      Start     : Int64;
      Row       : Int64;
      Base      : Int64;
      Stride    : Int64;
   begin
      if Encoding not in Encoding_P6_Color | Encoding_BMP_24 then
         Bad_Parameter (Status, Operation & ": Encoding must be P6_Color or "
                                & "BMP_24");
         return;
      elsif Red = null and then Green = null and then Blue = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      Operation & ": the image has no pixels");
         return;
      elsif Red = null
        or else not Valid_Planes (Red, Green, Blue, Red.Width, Red.Height)
      then
         Bad_Parameter (Status, Operation & ": Red, Green and Blue must be "
                                & "planes of the same size");
         return;
      end if;
      Check_Encoding_Request (Operation, Encoding, Red.Width, Red.Height,
                              Separator, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Bytes_Length
        (Operation, Bytes,
         Encoded_Length (Encoding, Red.Width, Red.Height, Separator),
         Status);
      if not Succeeded (Status) then
         return;
      end if;

      W := Int64 (Red.Width);
      H := Int64 (Red.Height);
      if Encoding = Encoding_BMP_24 then
         Stride := BMP_Stride (Encoding, W);
         Lemma_Stride (W, H, Stride);
         Put_BMP_Headers (Bytes, Encoding, W, H, Stride * H);
         Start := BMP_Data_Offset (Encoding);
         for R in 0 .. H - 1 loop
            Lemma_Mul_Le (R, H - 1, Stride);
            Row := Start + R * Stride;
            for X in 0 .. W - 1 loop
               Base := Bytes'First + Row + 3 * X;
               Bytes (Base) := Blue.Pixels (Natural (H - 1 - R), Natural (X));
               Bytes (Base + 1) :=
                 Green.Pixels (Natural (H - 1 - R), Natural (X));
               Bytes (Base + 2) :=
                 Red.Pixels (Natural (H - 1 - R), Natural (X));
            end loop;
            for P in 3 * W .. Stride - 1 loop
               Bytes (Bytes'First + Row + P) := 0;
            end loop;
         end loop;
      else
         declare
            Header : constant String :=
              PNM_Header_Text (Encoding, Red.Width, Red.Height);
         begin
            if Separator = 1 then
               Bytes (Bytes'First) := Character'Pos (ASCII.LF);
            end if;
            Put_Text (Bytes, Int64 (Separator), Header);
            Start := Int64 (Separator) + Header'Length;
            for Y in 0 .. H - 1 loop
               Lemma_Mul_Le (Y, H - 1, W * 3);
               Row := Start + Y * (W * 3);
               for X in 0 .. W - 1 loop
                  Base := Bytes'First + Row + 3 * X;
                  Bytes (Base) := Red.Pixels (Natural (Y), Natural (X));
                  Bytes (Base + 1) := Green.Pixels (Natural (Y), Natural (X));
                  Bytes (Base + 2) := Blue.Pixels (Natural (Y), Natural (X));
               end loop;
            end loop;
         end;
      end if;
   end Encode_24_Planar_Color;

   procedure Encode_8_Grey
     (Encoding  : Int32;
      Separator : Int32;
      Image     : access constant KI.Ks_Image_8_Grey_Data;
      Bytes     : System.Address;
      Length    : Int64;
      Status    : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
   begin
      Check_Bytes_Request (Length, Bytes = System.Null_Address, Status);
      if not Succeeded (Status) then
         return;
      elsif Length = 0 then
         declare
            Empty : Byte_Array (1 .. 0);
         begin
            Encode_8_Grey (Encoding, Separator, Image, Empty, Status);
         end;
      else
         declare
            View : Byte_Array (1 .. Length)
              with Import, Address => Bytes;
         begin
            Encode_8_Grey (Encoding, Separator, Image, View, Status);
         end;
      end if;
   end Encode_8_Grey;

   procedure Encode_16_Grey
     (Encoding  : Int32;
      Separator : Int32;
      Image     : access constant KI.Ks_Image_16_Grey_Data;
      Bytes     : System.Address;
      Length    : Int64;
      Status    : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
   begin
      Check_Bytes_Request (Length, Bytes = System.Null_Address, Status);
      if not Succeeded (Status) then
         return;
      elsif Length = 0 then
         declare
            Empty : Byte_Array (1 .. 0);
         begin
            Encode_16_Grey (Encoding, Separator, Image, Empty, Status);
         end;
      else
         declare
            View : Byte_Array (1 .. Length)
              with Import, Address => Bytes;
         begin
            Encode_16_Grey (Encoding, Separator, Image, View, Status);
         end;
      end if;
   end Encode_16_Grey;

   procedure Encode_24_Planar_Color
     (Encoding         : Int32;
      Separator        : Int32;
      Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data;
      Bytes            : System.Address;
      Length           : Int64;
      Status           : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
   begin
      Check_Bytes_Request (Length, Bytes = System.Null_Address, Status);
      if not Succeeded (Status) then
         return;
      elsif Length = 0 then
         declare
            Empty : Byte_Array (1 .. 0);
         begin
            Encode_24_Planar_Color (Encoding, Separator, Red, Green, Blue,
                                    Empty, Status);
         end;
      else
         declare
            View : Byte_Array (1 .. Length)
              with Import, Address => Bytes;
         begin
            Encode_24_Planar_Color (Encoding, Separator, Red, Green, Blue,
                                    View, Status);
         end;
      end if;
   end Encode_24_Planar_Color;

   ---------------------------------------------------------------------
   --  Update mode
   ---------------------------------------------------------------------

   procedure Count_For_Update
     (Format : Int32;
      Bytes  : Byte_Array;
      Count  : out Int32;
      Status : out Ks_Status)
   is
      Kind   : Int32;
      Images : Int32;
   begin
      Count := 0;
      if Format not in Format_Code then
         Bad_Parameter (Status, "Count_For_Update: Format must be a format "
                                & "code (1 .. 4)");
         return;
      elsif Bytes'Length = 0 then
         Set_Success (Status);
         return;
      end if;
      Scan (Bytes, Kind, Images, Status);
      if not Succeeded (Status) then
         return;
      elsif (Kind = Kind_BMP) /= (Format = Format_BMP) then
         Fail (Status, "cannot append: the file holds "
                       & (if Kind = Kind_BMP then "a BMP image"
                          else "PNM images")
                       & ", which does not match the extension "
                       & Extension_Text (Format));
         return;
      end if;
      Count := Images;
   end Count_For_Update;

   procedure Count_For_Update
     (Format : Int32;
      Bytes  : System.Address;
      Length : Int64;
      Count  : out Int32;
      Status : out Ks_Status)
     with SPARK_Mode => Off
   is
      use type System.Address;
   begin
      Count := 0;
      Check_Bytes_Request (Length, Bytes = System.Null_Address, Status);
      if not Succeeded (Status) then
         return;
      elsif Length = 0 then
         Count_For_Update (Format, No_Bytes, Count, Status);
      else
         declare
            View : Byte_Array (1 .. Length)
              with Import, Address => Bytes;
         begin
            Count_For_Update (Format, View, Count, Status);
         end;
      end if;
   end Count_For_Update;

   ---------------------------------------------------------------------
   --  The state rules of CogImageFile and CogImageFileTool
   ---------------------------------------------------------------------

   procedure Check_Open_Mode
     (Mode   : Int32;
      Status : out Ks_Status) is
   begin
      if Mode in Mode_Read .. Mode_Update then
         Set_Success (Status);
      else
         Bad_Parameter (Status, "Open: Mode must be Read, Write or Update "
                                & "(Closed is only reported by "
                                & "Open_Mode)");
      end if;
   end Check_Open_Mode;

   procedure Require_Open
     (Mode      : Int32;
      Operation : Int32;
      Status    : out Ks_Status) is
   begin
      if Operation not in Operation_Code then
         Bad_Parameter (Status, "Require_Open: Operation must be an "
                                & "operation code (1 .. 3)");
      elsif Mode not in Mode_Code then
         Bad_Parameter (Status, "Require_Open: Mode must be a mode code "
                                & "(1 .. 4)");
      elsif Mode = Mode_Closed then
         Fail (Status, (case Operation is
                           when Operation_Item   => "Item",
                           when Operation_Append => "Append",
                           when others           => "Operator")
                       & ": the image file is not open");
      else
         Set_Success (Status);
      end if;
   end Require_Open;

   procedure Require_Mode
     (Mode      : Int32;
      Operation : Int32;
      Status    : out Ks_Status) is
   begin
      Require_Open (Mode, Operation, Status);
      if not Succeeded (Status) then
         return;
      elsif Operation = Operation_Item and then Mode /= Mode_Read then
         Fail (Status, "Item needs Read mode but the file is open in "
                       & (if Mode = Mode_Write then "WRITE" else "UPDATE")
                       & " mode");
      elsif Operation = Operation_Append and then Mode = Mode_Read then
         Fail (Status, "Append needs Write or Update mode but the file is "
                       & "open in Read mode");
      end if;
   end Require_Mode;

   procedure Tool_Next_Index
     (Next_Index     : Int32;
      Count          : Int32;
      Index          : out Int32;
      New_Next_Index : out Int32;
      Status         : out Ks_Status) is
   begin
      Index := 0;
      New_Next_Index := 0;
      if Next_Index < 0 or else Count < 0 then
         Bad_Parameter (Status, "Tool_Next_Index: Next_Index and Count must "
                                & "not be negative");
      elsif Count = 0 then
         Fail (Status, "the file holds no image");
      else
         Index := Next_Index mod Count;
         New_Next_Index := (Index + 1) mod Count;
         Set_Success (Status);
      end if;
   end Tool_Next_Index;

   ---------------------------------------------------------------------
   --  For the Ada API only
   ---------------------------------------------------------------------

   procedure Check_File_Size
     (Size   : Int64;
      Status : out Ks_Status) is
   begin
      if Size < 0 then
         Bad_Parameter (Status, "Check_File_Size: Size must not be "
                                & "negative");
      elsif Size > Max_Length then
         File_Too_Large (Size, Status);
      else
         Set_Success (Status);
      end if;
   end Check_File_Size;

   procedure File_Too_Large
     (Size   : Int64;
      Status : out Ks_Status) is
   begin
      Fail (Status, "the file is too large to read into memory ("
                    & Image_Of (Int64'Max (Size, 0)) & " bytes)");
   end File_Too_Large;

   procedure Check_Whole_Read
     (Size, Read_Count : Int64;
      Status           : out Ks_Status) is
   begin
      if Read_Count /= Size then
         Fail (Status, "could not read the whole file");
      else
         Set_Success (Status);
      end if;
   end Check_Whole_Read;

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   procedure Fail_Read (Status : out Ks_Status; Text : String)
   with Pre  => Text'Length <= 1_000,
        Post => Valid (Status) and then Status.Failure = Failure_Image_File;
   --  "Ks_Image_File'Read: <Text>".

   procedure Fail_Read (Status : out Ks_Status; Text : String) is
   begin
      Fail (Status, "Ks_Image_File'Read: " & Text);
   end Fail_Read;

   procedure Read_Contents_Header
     (Count, Kind : Interfaces.Unsigned_32;
      Contents    : out Ks_Image_File_Contents;
      Status      : out Ks_Status) is
   begin
      Contents := null;
      if Count = 0 then
         if Kind /= 0 then
            Fail_Read (Status, "kind " & Image_Of (Int64 (Kind))
                               & " without images");
         else
            Set_Success (Status);
         end if;
      elsif Count > Max_Images then
         Fail_Read (Status, "the image count " & Image_Of (Int64 (Count))
                            & " is too large");
      elsif Kind not in 1 .. 2 then
         Fail_Read (Status, "unknown kind of file " & Image_Of (Int64 (Kind)));
      elsif Kind = 2 and then Count /= 1 then
         Fail_Read (Status, "a BMP file holds one image, not "
                            & Image_Of (Int64 (Count)));
      else
         Allocate_Contents (Int32 (Count), Contents);
         if Contents = null then
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Ks_Image_File'Read: not enough memory for "
                         & Image_Of (Int64 (Count)) & " images");
            return;
         end if;
         Contents.Kind := Int32 (Kind);
         Set_Success (Status);
      end if;
   end Read_Contents_Header;

   procedure Read_Image_Header
     (Image_Type, Maxval : Interfaces.Unsigned_32;
      Status             : out Ks_Status) is
   begin
      if Image_Type not in 1 .. 3 then
         Fail_Read (Status, "unknown image type "
                            & Image_Of (Int64 (Image_Type)));
      elsif (if Image_Type = 2 then Maxval not in 256 .. 65_535
             else Maxval not in 1 .. 255)
      then
         Fail_Read (Status, "the maxval " & Image_Of (Int64 (Maxval))
                            & " does not suit an image of type "
                            & Image_Of (Int64 (Image_Type)));
      else
         Set_Success (Status);
      end if;
   end Read_Image_Header;

   procedure Check_Store
     (Contents : access constant Ks_Image_File_Contents_Data;
      Index    : Int32;
      Status   : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Image_File
                and then (if Succeeded (Status)
                          then Contents /= null
                               and then Index in 0 .. Contents.Count - 1
                               and then No_Handles
                                          (Contents.Slots (Index + 1))
                               and then Contents.Slots (Index + 1)
                                          .Image_Type = 0);
   --  Image Index has an empty slot.

   procedure Check_Store
     (Contents : access constant Ks_Image_File_Contents_Data;
      Index    : Int32;
      Status   : out Ks_Status) is
   begin
      if Contents = null or else not Consistent (Contents) then
         Fail_Read (Status, "no images to store image "
                            & Image_Of (Index) & " in");
      elsif Index not in 0 .. Contents.Count - 1 then
         Fail_Read (Status, "image " & Image_Of (Index)
                            & " is beyond the image count");
      elsif not No_Handles (Contents.Slots (Index + 1))
        or else Contents.Slots (Index + 1).Image_Type /= 0
      then
         Fail_Read (Status, "image " & Image_Of (Index)
                            & " is stored twice");
      else
         Set_Success (Status);
      end if;
   end Check_Store;

   procedure Check_Samples
     (Image  : not null access constant KI.Ks_Image_8_Grey_Data;
      Index  : Int32;
      Maxval : Int32;
      Status : out Ks_Status)
   with Pre  => KI.Valid_Image (Image),
        Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Image_File;
   --  No pixel of Image is above Maxval.

   procedure Check_Samples
     (Image  : not null access constant KI.Ks_Image_8_Grey_Data;
      Index  : Int32;
      Maxval : Int32;
      Status : out Ks_Status) is
   begin
      for Y in Image.Pixels'Range (1) loop
         for X in Image.Pixels'Range (2) loop
            if Int32 (Image.Pixels (Y, X)) > Maxval then
               Fail_Read (Status, "image " & Image_Of (Index)
                                  & " has a sample above its maxval "
                                  & Image_Of (Maxval));
               return;
            end if;
         end loop;
      end loop;
      Set_Success (Status);
   end Check_Samples;

   procedure Store_8_Grey
     (Contents : Ks_Image_File_Contents;
      Index    : Int32;
      Maxval   : Int32;
      Image    : access constant KI.Ks_Image_8_Grey_Data;
      Status   : out Ks_Status)
   is
      Copy : KI.Ks_Image_8_Grey;
   begin
      Check_Store (Contents, Index, Status);
      if not Succeeded (Status) then
         return;
      elsif Maxval not in 1 .. 255 then
         Fail_Read (Status, "the maxval " & Image_Of (Maxval)
                            & " does not suit image " & Image_Of (Index));
         return;
      elsif not KI.Valid_Image (Image) then
         Fail_Read (Status, "image " & Image_Of (Index)
                            & " has no pixels");
         return;
      end if;
      Check_Samples (Image, Index, Maxval, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KI.Duplicate (Image, Copy, Status);
      if Copy = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Ks_Image_File'Read: not enough memory for image "
                      & Image_Of (Index));
         return;
      end if;
      Contents.Slots (Index + 1).Image_Type := Image_Type_Grey_8;
      Contents.Slots (Index + 1).Maxval := Maxval;
      Contents.Slots (Index + 1).Grey_8 := Copy;
   end Store_8_Grey;

   procedure Store_16_Grey
     (Contents : Ks_Image_File_Contents;
      Index    : Int32;
      Maxval   : Int32;
      Image    : access constant KI.Ks_Image_16_Grey_Data;
      Status   : out Ks_Status)
   is
      Copy : KI.Ks_Image_16_Grey;
   begin
      Check_Store (Contents, Index, Status);
      if not Succeeded (Status) then
         return;
      elsif Maxval not in 256 .. 65_535 then
         Fail_Read (Status, "the maxval " & Image_Of (Maxval)
                            & " does not suit image " & Image_Of (Index));
         return;
      elsif not KI.Valid_Image (Image) then
         Fail_Read (Status, "image " & Image_Of (Index)
                            & " has no pixels");
         return;
      end if;
      for Y in Image.Pixels'Range (1) loop
         for X in Image.Pixels'Range (2) loop
            if Int32 (Image.Pixels (Y, X)) > Maxval then
               Fail_Read (Status, "image " & Image_Of (Index)
                                  & " has a sample above its maxval "
                                  & Image_Of (Maxval));
               return;
            end if;
         end loop;
      end loop;
      KI.Duplicate (Image, Copy, Status);
      if Copy = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Ks_Image_File'Read: not enough memory for image "
                      & Image_Of (Index));
         return;
      end if;
      Contents.Slots (Index + 1).Image_Type := Image_Type_Grey_16;
      Contents.Slots (Index + 1).Maxval := Maxval;
      Contents.Slots (Index + 1).Grey_16 := Copy;
   end Store_16_Grey;

   procedure Store_24_Planar_Color
     (Contents         : Ks_Image_File_Contents;
      Index            : Int32;
      Maxval           : Int32;
      Red, Green, Blue : access constant KI.Ks_Image_8_Grey_Data;
      Status           : out Ks_Status)
   is
   begin
      Check_Store (Contents, Index, Status);
      if not Succeeded (Status) then
         return;
      elsif Maxval not in 1 .. 255 then
         Fail_Read (Status, "the maxval " & Image_Of (Maxval)
                            & " does not suit image " & Image_Of (Index));
         return;
      elsif Red = null
        or else not Valid_Planes (Red, Green, Blue, Red.Width, Red.Height)
      then
         Fail_Read (Status, "image " & Image_Of (Index)
                            & " has no pixels");
         return;
      end if;
      Check_Samples (Red, Index, Maxval, Status);
      if Succeeded (Status) then
         Check_Samples (Green, Index, Maxval, Status);
      end if;
      if Succeeded (Status) then
         Check_Samples (Blue, Index, Maxval, Status);
      end if;
      if not Succeeded (Status) then
         return;
      end if;
      --  Into the empty slot: a failed copy leaves its three planes null.
      KI.Duplicate_Color
        (Red, Green, Blue, Contents.Slots (Index + 1).Grey_8,
         Contents.Slots (Index + 1).Green, Contents.Slots (Index + 1).Blue,
         Status);
      if not Succeeded (Status) then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Ks_Image_File'Read: not enough memory for image "
                      & Image_Of (Index));
         return;
      end if;
      Contents.Slots (Index + 1).Image_Type := Image_Type_Color;
      Contents.Slots (Index + 1).Maxval := Maxval;
   end Store_24_Planar_Color;

end AMV.Kernels.Image_File;
