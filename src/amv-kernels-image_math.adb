pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;

with AMV.Kernels.Numerics;

package body AMV.Kernels.Image_Math with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  As in the spec: the prefixes are total ghost functions.

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package N renames AMV.Kernels.Numerics;

   procedure Free is new Ada.Unchecked_Deallocation
     (Real_Matrix, Real_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Real_Image_Data, Ks_Real_Image);
   procedure Free is new Ada.Unchecked_Deallocation
     (Real_Values, Real_Values_Access);

   Sum_Limit : constant := 1.0E150;
   --  The bound of every running sum of pixel values and of the window
   --  sums of the box filter. The largest true value is about 1.8E119 (a
   --  box window of (2 * 2**31 + 1)**2 values of at most 1.0E100), so the
   --  clamps that keep sums within it never act (docs/PROOF.md). It is
   --  below N.Mul_Limit, so sums may be multiplied by counts.

   Square_Sum_Limit : constant := 2.0 ** 1000;
   --  The bound of the sum of squared deviations of Statistics, at most
   --  2**31 * (2 * 1.0E100)**2 (about 8.6E209), so its clamp never acts.

   Weight_Sum_Limit : constant := 2.0 ** 40;
   --  The bound of the sums of Gaussian weights, at most 3_000_001 (one
   --  weight of at most 1 per offset of the radius), so its clamp never
   --  acts.

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
   --  Multiplication by a number that is not negative keeps the order.

   procedure Lemma_Mul_Le (A, B, K : Int64) is null;

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate
     (Width, Height : Int32;
      Image         : out Ks_Real_Image)
   with
     Global => null,
     Pre    => Width >= 0 and then Height >= 0
               and then Int64 (Width) * Int64 (Height) <= Max_Pixels,
     Post   => (if Image /= null
                then Valid_Image (Image)
                     and then Image.Width = Width
                     and then Image.Height = Height);
   --  A new handle of Width x Height pixels whose values are left for the
   --  caller to write, or null when the memory cannot be allocated.
   --  Trusted: the allocators raise Storage_Error, which SPARK cannot
   --  express; nothing is leaked when the second one fails.

   procedure Allocate
     (Width, Height : Int32;
      Image         : out Ks_Real_Image)
     with SPARK_Mode => Off
   is
      Pixels : Real_Pixels := null;
   begin
      Pixels := new Real_Matrix
        (0 .. Natural (Height) - 1, 0 .. Natural (Width) - 1);
      Image := new Ks_Real_Image_Data'
        (Width => Width, Height => Height, Pixels => Pixels);
   exception
      when Storage_Error =>
         Free (Pixels);
         Image := null;
   end Allocate;

   procedure Allocate_Values
     (Length : Int64;
      Values : out Real_Values_Access)
   with
     Global => null,
     Pre    => Length in 1 .. Max_Pixels,
     Post   => (if Values /= null
                then Values'First = 0
                     and then Int64 (Values'Last) = Length - 1);
   --  A new array of Length values, left for the caller to write, or null
   --  when the memory cannot be allocated. Trusted as Allocate.

   procedure Allocate_Values
     (Length : Int64;
      Values : out Real_Values_Access)
     with SPARK_Mode => Off
   is
   begin
      Values := new Real_Values (0 .. Natural (Length) - 1);
   exception
      when Storage_Error =>
         Values := null;
   end Allocate_Values;

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

   function To_Bits is new Ada.Unchecked_Conversion (Long_Float, U64);

   function Exp_Of_Non_Positive (X : Long_Float) return Long_Float
   with Global => null, Pre => X <= 0.0;
   --  exp (X), which lies in [0, 1] for X <= 0. Trusted: gnatprove checks
   --  every call of Exp for overflow, and the runtime's contract of Exp
   --  gives no bound on its result, so the check cannot be proved; for
   --  X <= 0 the result cannot overflow. No postcondition: the caller
   --  limits the result to [0, 1] itself.

   function Exp_Of_Non_Positive (X : Long_Float) return Long_Float
     with SPARK_Mode => Off
   is
   begin
      return EF.Exp (X);
   end Exp_Of_Non_Positive;

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

   procedure Bad
     (Status  : out Ks_Status;
      Message : String)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad
     (Status  : out Ks_Status;
      Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Bad_Handle
     (Operation : Operation_Name;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;
   --  "<Operation>: Image is not a valid image handle".

   procedure Bad_Handle
     (Operation : Operation_Name;
      Status    : out Ks_Status) is
   begin
      Bad (Status, Operation & ": Image is not a valid image handle");
   end Bad_Handle;

   procedure Bad_Value
     (Operation : Operation_Name;
      Argument  : String;
      Status    : out Ks_Status)
   with Pre  => Argument'Length <= 20,
        Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;
   --  "<Operation>: <Argument> must be finite and within +/-1.0E100".

   procedure Bad_Value
     (Operation : Operation_Name;
      Argument  : String;
      Status    : out Ks_Status) is
   begin
      Bad (Status, Operation & ": " & Argument
                   & " must be finite and within +/-1.0E100");
   end Bad_Value;

   procedure Not_Finite
     (Operation : Operation_Name;
      Argument  : String;
      Status    : out Ks_Status)
   with Pre  => Argument'Length <= 20,
        Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;
   --  "<Operation>: <Argument> must be finite".

   procedure Not_Finite
     (Operation : Operation_Name;
      Argument  : String;
      Status    : out Ks_Status) is
   begin
      Bad (Status, Operation & ": " & Argument & " must be finite");
   end Not_Finite;

   procedure Empty_Image
     (Operation : Operation_Name;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;
   --  "<Operation>: the image is empty".

   procedure Empty_Image
     (Operation : Operation_Name;
      Status    : out Ks_Status) is
   begin
      Bad (Status, Operation & ": the image is empty");
   end Empty_Image;

   procedure Grey_No_Pixels
     (Operation : Operation_Name;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Image_No_Pixels;
   --  "<Operation>: the image has no pixels" (an 8-bit image).

   procedure Grey_No_Pixels
     (Operation : Operation_Name;
      Status    : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Image_No_Pixels,
                   Operation & ": the image has no pixels");
   end Grey_No_Pixels;

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

   procedure Check_Grey
     (Image     : access constant KI.Ks_Image_8_Grey_Data;
      Operation : Operation_Name;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then KI.Valid_Image (Image)
                               and then Int64 (Image.Width)
                                          * Int64 (Image.Height)
                                          <= Max_Pixels);
   --  Image_No_Pixels for null, Bad_Parameter for an inconsistent handle.

   procedure Check_Grey
     (Image     : access constant KI.Ks_Image_8_Grey_Data;
      Operation : Operation_Name;
      Status    : out Ks_Status) is
   begin
      if Image = null then
         Grey_No_Pixels (Operation, Status);
      elsif not KI.Valid_Image (Image)
        or else Int64 (Image.Width) * Int64 (Image.Height) > Max_Pixels
      then
         Bad_Handle (Operation, Status);
      else
         Set_Success (Status);
      end if;
   end Check_Grey;

   ---------------------------------------------------------------------
   --  Values
   ---------------------------------------------------------------------

   function Clamped (X : Long_Float) return Long_Float is
     (N.Clamp (X, Max_Value))
   with Post => In_Bound (Clamped'Result)
                and then (if In_Bound (X) then Clamped'Result = X);
   --  X limited to the bound. Used on values read from a handle (which the
   --  kernel only ever fills with values within it, so nothing changes)
   --  and on averages, which lie within the range of the values averaged
   --  and so can leave the bound only by rounding at its very edge.

   function Sum_Clamped (X : Long_Float) return Long_Float is
     (N.Clamp (X, Sum_Limit))
   with Post => abs Sum_Clamped'Result <= Sum_Limit;
   --  X limited to Sum_Limit (sums, which never reach it).

   function Accumulate (Sum, Term : Long_Float) return Long_Float is
     (Sum_Clamped (Sum_Clamped (Sum) + Term))
   with Pre  => abs Term <= Sum_Limit,
        Post => abs Accumulate'Result <= Sum_Limit;
   --  Sum + Term (Sum read within Sum_Limit, which it never leaves).

   procedure Add
     (Sum, Compensation : in out Long_Float;
      Value             : Long_Float)
   with Pre  => abs Value <= Sum_Limit,
        Post => abs Sum <= Sum_Limit and then abs Compensation <= Sum_Limit;
   --  Neumaier's compensated summation: Sum + Compensation is the running
   --  total, with Compensation collecting what rounding drops from Sum.
   --  Each correction term is the exact rounding error of one addition,
   --  so adding a large value and later its negative restores the small
   --  values added in between instead of losing them. Sum and
   --  Compensation are read within Sum_Limit, which they never leave.

   procedure Add
     (Sum, Compensation : in out Long_Float;
      Value             : Long_Float)
   is
      S     : constant Long_Float := Sum_Clamped (Sum);
      C     : constant Long_Float := Sum_Clamped (Compensation);
      Total : constant Long_Float := S + Value;
   begin
      if abs S >= abs Value then
         Compensation := Sum_Clamped (C + ((S - Total) + Value));
      else
         Compensation := Sum_Clamped (C + ((Value - Total) + S));
      end if;
      Sum := Sum_Clamped (Total);
   end Add;

   ---------------------------------------------------------------------
   --  Handles
   ---------------------------------------------------------------------

   function Handle_OK
     (Image : access constant Ks_Real_Image_Data) return Boolean
   is
     (Image = null or else Valid_Image (Image));
   --  Null or a valid handle.

   procedure Release (Image : in out Ks_Real_Image)
   with Post => Image = null;
   --  Frees Image (if any).

   procedure Release (Image : in out Ks_Real_Image) is
   begin
      if Image /= null then
         Free (Image.Pixels);
         Free (Image);
      end if;
   end Release;

   procedure Fill_All (Image : Ks_Real_Image; Value : Long_Float)
   with
     Pre  => Valid_Image (Image),
     Post => Valid_Image (Image)
             and then Size_Of (Image) = Size_Of (Image)'Old
             and then (for all Y in Image.Pixels'Range (1)
                       => (for all X in Image.Pixels'Range (2)
                           => Image.Pixels (Y, X) = Value));

   procedure Fill_All (Image : Ks_Real_Image; Value : Long_Float) is
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

   procedure Copy_Filtered
     (Image     : access constant Ks_Real_Image_Data;
      Operation : Operation_Name;
      Result    : out Ks_Real_Image;
      Status    : out Ks_Status)
   with
     Pre  => Handle_OK (Image),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status) then Filtered (Image, Result)
                       else Result = null);
   --  What a filter gives when it changes nothing: a copy of Image, null
   --  for null.

   procedure Copy_Filtered
     (Image     : access constant Ks_Real_Image_Data;
      Operation : Operation_Name;
      Result    : out Ks_Real_Image;
      Status    : out Ks_Status) is
   begin
      Result := null;
      if Image = null then
         Set_Success (Status);
         return;
      end if;
      Allocate (Image.Width, Image.Height, Result);
      if Result = null then
         Out_Of_Memory (Operation, Image.Width, Image.Height, Status);
         return;
      end if;
      for Y in Result.Pixels'Range (1) loop
         for X in Result.Pixels'Range (2) loop
            Result.Pixels (Y, X) := Clamped (Image.Pixels (Y, X));
            pragma Loop_Invariant
              (Valid_Image (Result)
               and then Result.Width = Image.Width
               and then Result.Height = Image.Height);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Result.Pixels'Range (2)
                   => In_Bound (Result.Pixels (J, I))));
            pragma Loop_Invariant
              (for all I in 0 .. X => In_Bound (Result.Pixels (Y, I)));
         end loop;
         pragma Loop_Invariant
           (Valid_Image (Result)
            and then Result.Width = Image.Width
            and then Result.Height = Image.Height);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Result.Pixels'Range (2)
                => In_Bound (Result.Pixels (J, I))));
      end loop;
      Set_Success (Status);
   end Copy_Filtered;

   ---------------------------------------------------------------------
   --  Entry points: handles and pixels
   ---------------------------------------------------------------------

   procedure Create
     (Width, Height : Int32;
      Value         : Long_Float;
      Image         : out Ks_Real_Image;
      Status        : out Ks_Status) is
   begin
      Image := null;
      if Width < 0 or else Height < 0 then
         Bad (Status, "Create: Width and Height must be >= 0 ("
                      & Image_Of (Width) & " x " & Image_Of (Height)
                      & " given)");
      elsif Int64 (Width) * Int64 (Height) > Max_Pixels then
         Bad (Status, "Create: Width * Height is too large");
      elsif not In_Bound (Value) then
         Bad_Value ("Create", "Value", Status);
      else
         Allocate (Width, Height, Image);
         if Image = null then
            Out_Of_Memory ("Create", Width, Height, Status);
            return;
         end if;
         Fill_All (Image, Value);
         Set_Success (Status);
      end if;
   end Create;

   procedure Destroy
     (Image  : in out Ks_Real_Image;
      Status : out Ks_Status) is
   begin
      Release (Image);
      Set_Success (Status);
   end Destroy;

   procedure Width
     (Image  : access constant Ks_Real_Image_Data;
      Result : out Int32;
      Status : out Ks_Status) is
   begin
      Result := 0;
      if Image = null then
         Set_Success (Status);
      elsif not Valid_Image (Image) then
         Bad_Handle ("Width", Status);
      else
         Result := Image.Width;
         Set_Success (Status);
      end if;
   end Width;

   procedure Height
     (Image  : access constant Ks_Real_Image_Data;
      Result : out Int32;
      Status : out Ks_Status) is
   begin
      Result := 0;
      if Image = null then
         Set_Success (Status);
      elsif not Valid_Image (Image) then
         Bad_Handle ("Height", Status);
      else
         Result := Image.Height;
         Set_Success (Status);
      end if;
   end Height;

   procedure Check_Pixel
     (Image     : access constant Ks_Real_Image_Data;
      Operation : Operation_Name;
      X, Y      : Int32;
      Status    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Index_Out_Of_Range
                and then (Succeeded (Status) = Pixel_Exists (Image, X, Y));
   --  Bad_Parameter for an inconsistent handle; Index_Out_Of_Range unless
   --  (X, Y) is a pixel of the image (never for an empty one).

   procedure Check_Pixel
     (Image     : access constant Ks_Real_Image_Data;
      Operation : Operation_Name;
      X, Y      : Int32;
      Status    : out Ks_Status)
   is
      W, H : Int32 := 0;
   begin
      if Image /= null then
         if not Valid_Image (Image) then
            Bad_Handle (Operation, Status);
            return;
         end if;
         W := Image.Width;
         H := Image.Height;
      end if;
      if X in 0 .. W - 1 and then Y in 0 .. H - 1 then
         Set_Success (Status);
      else
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      Operation & ": pixel (" & Image_Of (X) & ", "
                      & Image_Of (Y) & ") is outside the "
                      & Image_Of (W) & " x " & Image_Of (H) & " image");
      end if;
   end Check_Pixel;

   procedure Get_Pixel
     (Image  : access constant Ks_Real_Image_Data;
      X, Y   : Int32;
      Value  : out Long_Float;
      Status : out Ks_Status) is
   begin
      Value := 0.0;
      Check_Pixel (Image, "Get", X, Y, Status);
      if Succeeded (Status) then
         Value := Image.Pixels (Natural (Y), Natural (X));
      end if;
   end Get_Pixel;

   procedure Set_Pixel
     (Image  : Ks_Real_Image;
      X, Y   : Int32;
      Value  : Long_Float;
      Status : out Ks_Status) is
   begin
      Check_Pixel (Image, "Set", X, Y, Status);
      if not Succeeded (Status) then
         return;
      elsif not In_Bound (Value) then
         Bad_Value ("Set", "Value", Status);
         return;
      end if;
      Image.Pixels (Natural (Y), Natural (X)) := Value;
   end Set_Pixel;

   procedure Fill
     (Image  : Ks_Real_Image;
      Value  : Long_Float;
      Status : out Ks_Status) is
   begin
      if not In_Bound (Value) then
         Bad_Value ("Fill", "Value", Status);
      elsif Image = null then
         Set_Success (Status);
      elsif not Valid_Image (Image) then
         Bad_Handle ("Fill", Status);
      else
         Fill_All (Image, Value);
         Set_Success (Status);
      end if;
   end Fill;

   procedure Duplicate
     (Image  : access constant Ks_Real_Image_Data;
      Result : out Ks_Real_Image;
      Status : out Ks_Status) is
   begin
      Result := null;
      if Image = null then
         Set_Success (Status);
         return;
      elsif not Valid_Image (Image) then
         Bad_Handle ("Duplicate", Status);
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

   ---------------------------------------------------------------------
   --  Conversion from and to 8-bit images
   ---------------------------------------------------------------------

   procedure Copy_Window
     (Image                       : access constant KI.Ks_Image_8_Grey_Data;
      X_Min, Y_Min, Width, Height : Int32;
      Result                      : out Ks_Real_Image;
      Status                      : out Ks_Status)
   with
     Pre  => KI.Valid_Image (Image)
             and then Width >= 1 and then Height >= 1
             and then X_Min >= 0 and then Y_Min >= 0
             and then Width <= Image.Width
             and then X_Min <= Image.Width - Width
             and then Height <= Image.Height
             and then Y_Min <= Image.Height - Height
             and then Int64 (Width) * Int64 (Height) <= Max_Pixels,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Bounded_Image (Result)
                            and then Result.Width = Width
                            and then Result.Height = Height
                       else Result = null);
   --  The window of Image as a new Real_Image.

   procedure Copy_Window
     (Image                       : access constant KI.Ks_Image_8_Grey_Data;
      X_Min, Y_Min, Width, Height : Int32;
      Result                      : out Ks_Real_Image;
      Status                      : out Ks_Status) is
   begin
      Allocate (Width, Height, Result);
      if Result = null then
         Out_Of_Memory ("From_Grey_8", Width, Height, Status);
         return;
      end if;
      for Y in Result.Pixels'Range (1) loop
         for X in Result.Pixels'Range (2) loop
            Result.Pixels (Y, X) :=
              Long_Float (Image.Pixels (Natural (Y_Min) + Y,
                                        Natural (X_Min) + X));
            pragma Loop_Invariant
              (Valid_Image (Result)
               and then Result.Width = Width
               and then Result.Height = Height);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Result.Pixels'Range (2)
                   => In_Bound (Result.Pixels (J, I))));
            pragma Loop_Invariant
              (for all I in 0 .. X => In_Bound (Result.Pixels (Y, I)));
         end loop;
         pragma Loop_Invariant
           (Valid_Image (Result)
            and then Result.Width = Width
            and then Result.Height = Height);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Result.Pixels'Range (2)
                => In_Bound (Result.Pixels (J, I))));
      end loop;
      Set_Success (Status);
   end Copy_Window;

   procedure From_Grey_8
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Result : out Ks_Real_Image;
      Status : out Ks_Status) is
   begin
      Result := null;
      Check_Grey (Image, "From_Grey_8", Status);
      if Succeeded (Status) then
         Copy_Window (Image, 0, 0, Image.Width, Image.Height, Result,
                      Status);
      end if;
   end From_Grey_8;

   procedure From_Grey_8_Window
     (Image                       : access constant KI.Ks_Image_8_Grey_Data;
      X_Min, Y_Min, Width, Height : Int32;
      Result                      : out Ks_Real_Image;
      Status                      : out Ks_Status) is
   begin
      Result := null;
      Check_Grey (Image, "From_Grey_8", Status);
      if not Succeeded (Status) then
         return;
      elsif Width < 1 or else Height < 1 then
         Bad (Status, "From_Grey_8: the window must not be empty");
      elsif X_Min < 0 or else Y_Min < 0
        or else Width > Image.Width or else X_Min > Image.Width - Width
        or else Height > Image.Height or else Y_Min > Image.Height - Height
      then
         Bad (Status, "From_Grey_8: the window must lie inside the image");
      elsif Int64 (Width) * Int64 (Height) > Max_Pixels then
         Bad (Status, "From_Grey_8: Width * Height is too large");
      else
         Copy_Window (Image, X_Min, Y_Min, Width, Height, Result, Status);
      end if;
   end From_Grey_8_Window;

   function To_Grey (V : Long_Float) return KI.Grey_8 is
     (if not (V > 0.0) then 0
      elsif V >= 255.0 then 255
      else KI.Grey_8 (Int32 (V)));
   --  V rounded to the nearest integer (halves away from zero) and
   --  clamped to 0 .. 255.

   procedure To_Grey_8
     (Image  : access constant Ks_Real_Image_Data;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      Result := null;
      if not Handle_OK (Image) then
         Bad_Handle ("To_Grey_8", Status);
         return;
      elsif not Has_Pixels (Image) then
         Empty_Image ("To_Grey_8", Status);
         return;
      end if;
      KI.Create (Image.Width, Image.Height, 0, Result, Status);
      if not Succeeded (Status) then
         Out_Of_Memory ("To_Grey_8", Image.Width, Image.Height, Status);
         return;
      end if;
      for Y in Image.Pixels'Range (1) loop
         pragma Loop_Invariant
           (KI.Valid_Image (Result)
            and then Result.Width = Image.Width
            and then Result.Height = Image.Height);
         for X in Image.Pixels'Range (2) loop
            pragma Loop_Invariant
              (KI.Valid_Image (Result)
               and then Result.Width = Image.Width
               and then Result.Height = Image.Height);
            Result.Pixels (Y, X) := To_Grey (Clamped (Image.Pixels (Y, X)));
         end loop;
      end loop;
      Set_Success (Status);
   end To_Grey_8;

   ---------------------------------------------------------------------
   --  Sampling
   ---------------------------------------------------------------------

   procedure Locate
     (Value    : Long_Float;
      High     : Natural;
      I0, I1   : out Natural;
      Fraction : out Long_Float)
   with
     Pre  => High < Natural'Last,
     Post => I0 <= High and then I1 <= High
             and then Fraction >= 0.0 and then Fraction <= 1.0;
   --  Clamps Value to [0, High] and splits it into the index of the sample
   --  at or before it (I0), the next sample (I1, never beyond High) and
   --  the fractional position between them.

   procedure Locate
     (Value    : Long_Float;
      High     : Natural;
      I0, I1   : out Natural;
      Fraction : out Long_Float)
   is
      Top : constant Long_Float := Long_Float (High);
      C   : constant Long_Float :=
        (if not (Value > 0.0) then 0.0
         elsif not (Value < Top) then Top
         else Value);
      F   : constant Long_Float := Long_Float'Floor (C);
   begin
      I0 := Natural (F);
      if I0 > High then
         I0 := High;
      end if;
      --  C - I0 lies in [0, 1); the clamp states it for the prover.
      Fraction := N.Clamp_Unit (C - Long_Float (I0));
      I1 := (if I0 < High then I0 + 1 else High);
   end Locate;

   function Interpolate (P00, P10, P01, P11, Fx, Fy : Long_Float)
      return Long_Float
   with
     Pre  => In_Bound (P00) and then In_Bound (P10)
             and then In_Bound (P01) and then In_Bound (P11)
             and then Fx >= 0.0 and then Fx <= 1.0
             and then Fy >= 0.0 and then Fy <= 1.0,
     Post => In_Bound (Interpolate'Result);
   --  P00 at (0, 0), P10 at (1, 0), P01 at (0, 1), P11 at (1, 1). The
   --  "A + F * (B - A)" form reproduces a constant exactly. The result,
   --  within the range of the four values, is clamped to the bound.

   function Interpolate (P00, P10, P01, P11, Fx, Fy : Long_Float)
      return Long_Float
   is
      A : constant Long_Float := P00 + N.Times_Unit (P10 - P00, Fx);
      B : constant Long_Float := P01 + N.Times_Unit (P11 - P01, Fx);
   begin
      return Clamped (A + N.Times_Unit (B - A, Fy));
   end Interpolate;

   function Sample
     (Image : access constant Ks_Real_Image_Data;
      X, Y  : Long_Float) return Long_Float
   with
     Pre  => Has_Pixels (Image),
     Post => In_Bound (Sample'Result);
   --  Bilinear sample of the whole image at (X, Y).

   function Sample
     (Image : access constant Ks_Real_Image_Data;
      X, Y  : Long_Float) return Long_Float
   is
      Ix0, Ix1 : Natural;
      Iy0, Iy1 : Natural;
      Fx, Fy   : Long_Float;
   begin
      Locate (X, Natural (Image.Width) - 1, Ix0, Ix1, Fx);
      Locate (Y, Natural (Image.Height) - 1, Iy0, Iy1, Fy);
      return Interpolate
        (Clamped (Image.Pixels (Iy0, Ix0)), Clamped (Image.Pixels (Iy0, Ix1)),
         Clamped (Image.Pixels (Iy1, Ix0)), Clamped (Image.Pixels (Iy1, Ix1)),
         Fx, Fy);
   end Sample;

   function Sample
     (Image : access constant KI.Ks_Image_8_Grey_Data;
      X, Y  : Long_Float) return Long_Float
   with
     Pre  => KI.Valid_Image (Image),
     Post => In_Bound (Sample'Result);
   --  The same for an 8-bit image.

   function Sample
     (Image : access constant KI.Ks_Image_8_Grey_Data;
      X, Y  : Long_Float) return Long_Float
   is
      Ix0, Ix1 : Natural;
      Iy0, Iy1 : Natural;
      Fx, Fy   : Long_Float;
   begin
      Locate (X, Natural (Image.Width) - 1, Ix0, Ix1, Fx);
      Locate (Y, Natural (Image.Height) - 1, Iy0, Iy1, Fy);
      return Interpolate
        (Long_Float (Image.Pixels (Iy0, Ix0)),
         Long_Float (Image.Pixels (Iy0, Ix1)),
         Long_Float (Image.Pixels (Iy1, Ix0)),
         Long_Float (Image.Pixels (Iy1, Ix1)),
         Fx, Fy);
   end Sample;

   procedure Bilinear
     (Image  : access constant Ks_Real_Image_Data;
      X, Y   : Long_Float;
      Result : out Long_Float;
      Status : out Ks_Status) is
   begin
      Result := 0.0;
      if not Handle_OK (Image) then
         Bad_Handle ("Bilinear", Status);
      elsif not Has_Pixels (Image) then
         Empty_Image ("Bilinear", Status);
      elsif not N.Is_Finite (X) then
         Not_Finite ("Bilinear", "X", Status);
      elsif not N.Is_Finite (Y) then
         Not_Finite ("Bilinear", "Y", Status);
      else
         Result := Sample (Image, X, Y);
         Set_Success (Status);
      end if;
   end Bilinear;

   procedure Bilinear_Grey_8
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      X, Y   : Long_Float;
      Result : out Long_Float;
      Status : out Ks_Status) is
   begin
      Result := 0.0;
      Check_Grey (Image, "Bilinear", Status);
      if not Succeeded (Status) then
         return;
      elsif not N.Is_Finite (X) then
         Not_Finite ("Bilinear", "X", Status);
      elsif not N.Is_Finite (Y) then
         Not_Finite ("Bilinear", "Y", Status);
      else
         Result := Sample (Image, X, Y);
      end if;
   end Bilinear_Grey_8;

   procedure Is_Inside
     (Image  : access constant Ks_Real_Image_Data;
      X, Y   : Long_Float;
      Result : out Int32;
      Status : out Ks_Status) is
   begin
      Result := False_Value;
      if not Handle_OK (Image) then
         Bad_Handle ("Is_Inside", Status);
      elsif not N.Is_Finite (X) then
         Not_Finite ("Is_Inside", "X", Status);
      elsif not N.Is_Finite (Y) then
         Not_Finite ("Is_Inside", "Y", Status);
      else
         if Has_Pixels (Image)
           and then X >= 0.0 and then X <= Long_Float (Image.Width - 1)
           and then Y >= 0.0 and then Y <= Long_Float (Image.Height - 1)
         then
            Result := True_Value;
         end if;
         Set_Success (Status);
      end if;
   end Is_Inside;

   procedure Check_Resample
     (Pixel_From_Output : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      Status            : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status)
                          then KT.Bounded (Pixel_From_Output)
                               and then Width >= 1 and then Height >= 1
                               and then Int64 (Width) * Int64 (Height)
                                          <= Max_Pixels);
   --  The checks of the transform and the size of a resampled image.

   procedure Check_Resample
     (Pixel_From_Output : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      Status            : out Ks_Status) is
   begin
      if not KT.Bounded (Pixel_From_Output) then
         Bad (Status, "Resample: Pixel_From_Output must be finite and "
                      & "within +/-1.0E150");
      elsif Width < 1 or else Height < 1 then
         Bad (Status, "Resample: Width and Height must be at least 1 ("
                      & Image_Of (Width) & " x " & Image_Of (Height)
                      & " given)");
      elsif Int64 (Width) * Int64 (Height) > Max_Pixels then
         Bad (Status, "Resample: Width * Height is too large");
      else
         Set_Success (Status);
      end if;
   end Check_Resample;

   procedure Map
     (T    : KT.Ks_Transform_2D_Linear;
      I, J : Natural;
      X, Y : out Long_Float)
   with Pre => KT.Bounded (T);
   --  The centre of output pixel (I, J) mapped by T, computed as
   --  ks_transform_2d_linear_map_point does (so that a sample matches
   --  Bilinear at the mapped point exactly). At most about 4.3E159.

   procedure Map
     (T    : KT.Ks_Transform_2D_Linear;
      I, J : Natural;
      X, Y : out Long_Float)
   is
      Ri : constant Long_Float := Long_Float (I);
      Rj : constant Long_Float := Long_Float (J);
   begin
      X := N.Mul (T.A, Ri) + N.Mul (T.B, Rj) + T.Translation_X;
      Y := N.Mul (T.C, Ri) + N.Mul (T.D, Rj) + T.Translation_Y;
   end Map;

   procedure Resample
     (Image             : access constant Ks_Real_Image_Data;
      Pixel_From_Output : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      Result            : out Ks_Real_Image;
      Status            : out Ks_Status)
   is
      X, Y : Long_Float;
   begin
      Result := null;
      if not Handle_OK (Image) then
         Bad_Handle ("Resample", Status);
         return;
      elsif not Has_Pixels (Image) then
         Empty_Image ("Resample", Status);
         return;
      end if;
      Check_Resample (Pixel_From_Output, Width, Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Allocate (Width, Height, Result);
      if Result = null then
         Out_Of_Memory ("Resample", Width, Height, Status);
         return;
      end if;
      for J in Result.Pixels'Range (1) loop
         for I in Result.Pixels'Range (2) loop
            Map (Pixel_From_Output, I, J, X, Y);
            Result.Pixels (J, I) := Sample (Image, X, Y);
            pragma Loop_Invariant
              (Valid_Image (Result)
               and then Result.Width = Width
               and then Result.Height = Height);
            pragma Loop_Invariant
              (for all R in 0 .. J - 1
               => (for all C in Result.Pixels'Range (2)
                   => In_Bound (Result.Pixels (R, C))));
            pragma Loop_Invariant
              (for all C in 0 .. I => In_Bound (Result.Pixels (J, C)));
         end loop;
         pragma Loop_Invariant
           (Valid_Image (Result)
            and then Result.Width = Width
            and then Result.Height = Height);
         pragma Loop_Invariant
           (for all R in 0 .. J
            => (for all C in Result.Pixels'Range (2)
                => In_Bound (Result.Pixels (R, C))));
      end loop;
   end Resample;

   procedure Resample_Grey_8
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Pixel_From_Output : KT.Ks_Transform_2D_Linear;
      Width, Height     : Int32;
      Result            : out Ks_Real_Image;
      Status            : out Ks_Status)
   is
      X, Y : Long_Float;
   begin
      Result := null;
      Check_Grey (Image, "Resample", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Resample (Pixel_From_Output, Width, Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Allocate (Width, Height, Result);
      if Result = null then
         Out_Of_Memory ("Resample", Width, Height, Status);
         return;
      end if;
      for J in Result.Pixels'Range (1) loop
         for I in Result.Pixels'Range (2) loop
            Map (Pixel_From_Output, I, J, X, Y);
            Result.Pixels (J, I) := Sample (Image, X, Y);
            pragma Loop_Invariant
              (Valid_Image (Result)
               and then Result.Width = Width
               and then Result.Height = Height);
            pragma Loop_Invariant
              (for all R in 0 .. J - 1
               => (for all C in Result.Pixels'Range (2)
                   => In_Bound (Result.Pixels (R, C))));
            pragma Loop_Invariant
              (for all C in 0 .. I => In_Bound (Result.Pixels (J, C)));
         end loop;
         pragma Loop_Invariant
           (Valid_Image (Result)
            and then Result.Width = Width
            and then Result.Height = Height);
         pragma Loop_Invariant
           (for all R in 0 .. J
            => (for all C in Result.Pixels'Range (2)
                => In_Bound (Result.Pixels (R, C))));
      end loop;
   end Resample_Grey_8;

   ---------------------------------------------------------------------
   --  Gaussian smoothing
   ---------------------------------------------------------------------

   --  With replicated borders, output sample I of a line X (0 .. N - 1)
   --  smoothed by the symmetric kernel H (-R .. R) is
   --
   --     sum over J in max (0, I - R) .. min (N - 1, I + R)
   --        of H (|J - I|) * X (J)
   --     + T (I + 1) * X (0) + T (N - I) * X (N - 1)
   --
   --  where T (M) is the kernel mass H (M) + ... + H (R) that falls off
   --  the respective end (zero for M > R). Only H (0 .. min (R, N)) and
   --  T (1 .. N) are needed, so the tables stay small even for a radius
   --  much larger than the image. Half holds H (0 .. Kt), Tail holds T (M)
   --  at index M - 1. Every weight lies in [0, 1] and is read through
   --  N.Clamp_Unit, which never changes it.

   function Gaussian_Weight (K : Positive; Sigma : Long_Float)
      return Long_Float
   with
     Pre  => Sigma > 0.0 and then Sigma <= Max_Sigma
             and then K <= 4_000_000,
     Post => Gaussian_Weight'Result >= 0.0
             and then Gaussian_Weight'Result <= 1.0;
   --  exp (-(K / Sigma)**2 / 2), taken as zero beyond 37 Sigma (below
   --  1.0E-297 of the centre weight), so that a tiny Sigma cannot overflow
   --  the exponent.

   function Gaussian_Weight (K : Positive; Sigma : Long_Float)
      return Long_Float
   is
      Rk   : constant Long_Float := Long_Float (K);
      Q    : Long_Float;
      Fits : Boolean;
   begin
      if Rk > 37.0 * Sigma then
         return 0.0;
      end if;
      --  Rk / Sigma is at most 37 here (38 allows for rounding).
      N.Ratio_Within (Rk, Sigma, 38.0, Q, Fits);
      if not Fits then
         return 0.0;
      end if;
      --  exp of a value that is not positive lies in [0, 1]; the clamp
      --  states it for the prover.
      --  Q >= 0, so the product is not negative (abs changes nothing).
      return N.Clamp_Unit
        (Exp_Of_Non_Positive
           (-(abs N.Mul_Within (0.5 * Q, Q, 19.0, 38.0))));
   end Gaussian_Weight;

   procedure Gaussian_Tables
     (Sigma      : Long_Float;
      Radius, Kt : Positive;
      N_Max      : Positive;
      Half       : Real_Values_Access;
      Tail       : Real_Values_Access)
   with
     Pre  => Sigma > 0.0 and then Sigma <= Max_Sigma
             and then Radius <= 4_000_000
             and then Kt = Natural'Min (Radius, N_Max)
             and then Half /= null and then Half'First = 0
             and then Half'Last = Kt
             and then Tail /= null and then Tail'First = 0
             and then Tail'Last = N_Max - 1,
     Post => Half'First = 0 and then Half'Last = Kt
             and then Tail'First = 0 and then Tail'Last = N_Max - 1;
   --  Fills Half with the normalised weights H (0 .. Kt) and Tail with the
   --  tail masses T (1 .. N_Max).

   procedure Gaussian_Tables
     (Sigma      : Long_Float;
      Radius, Kt : Positive;
      N_Max      : Positive;
      Half       : Real_Values_Access;
      Tail       : Real_Values_Access)
   is
      Beyond  : Long_Float := 0.0;   --  weights of offsets Kt + 1 .. R
      Sum     : Long_Float;
      Total   : Long_Float;
      Running : Long_Float;
      Wk      : Long_Float;
   begin
      Half (0) := 1.0;
      for K in 1 .. Radius loop
         pragma Loop_Invariant
           (Half'First = 0 and then Half'Last = Kt
            and then Beyond >= 0.0 and then Beyond <= Weight_Sum_Limit);
         Wk := Gaussian_Weight (K, Sigma);
         if K <= Kt then
            Half (K) := Wk;
         else
            Beyond := N.Clamp (Beyond + Wk, Weight_Sum_Limit);
         end if;
      end loop;
      --  Sum from the smallest weights up, for accuracy.
      Sum := Beyond;
      for K in reverse 1 .. Kt loop
         pragma Loop_Invariant
           (Sum >= Beyond and then Sum <= Weight_Sum_Limit);
         Sum := N.Clamp (Sum + N.Clamp_Unit (Half (K)), Weight_Sum_Limit);
      end loop;
      Total := 1.0 + 2.0 * Sum;
      for K in 0 .. Kt loop
         pragma Loop_Invariant (Half'First = 0 and then Half'Last = Kt);
         Half (K) := N.Unit_Ratio (N.Clamp_Unit (Half (K)), Total);
      end loop;
      --  Beyond and Total are positive, so the ratio lies in [0, 1].
      Running := N.Clamp_Unit (N.Unit_Ratio (Beyond, Total));
      for M in reverse 1 .. N_Max loop
         pragma Loop_Invariant
           (Tail'First = 0 and then Tail'Last = N_Max - 1
            and then Running >= 0.0 and then Running <= 1.0);
         if M <= Kt then
            --  The tail masses stay below 1/2; the clamp states that they
            --  stay within 1.
            Running := N.Clamp_Unit (Running + N.Clamp_Unit (Half (M)));
         end if;
         Tail (M - 1) := Running;
      end loop;
   end Gaussian_Tables;

   procedure Add_Weighted_Row
     (Acc    : Real_Values_Access;
      Source : access constant Ks_Real_Image_Data;
      Row    : Natural;
      Weight : Long_Float)
   with
     Pre  => Valid_Image (Source)
             and then Row <= Source.Pixels'Last (1)
             and then Acc /= null and then Acc'First = 0
             and then Acc'Last = Source.Pixels'Last (2)
             and then Weight >= 0.0 and then Weight <= 1.0,
     Post => Acc'First = 0 and then Acc'Last = Acc'Last'Old;
   --  Acc (X) := Acc (X) + Weight * Source (Row, X) for every column X.

   procedure Add_Weighted_Row
     (Acc    : Real_Values_Access;
      Source : access constant Ks_Real_Image_Data;
      Row    : Natural;
      Weight : Long_Float) is
   begin
      for X in Source.Pixels'Range (2) loop
         pragma Loop_Invariant
           (Acc'First = 0 and then Acc'Last = Source.Pixels'Last (2));
         Acc (X) := Accumulate
           (Acc (X), N.Times_Unit (Clamped (Source.Pixels (Row, X)), Weight));
      end loop;
   end Add_Weighted_Row;

   procedure Gaussian_Passes
     (Image  : access constant Ks_Real_Image_Data;
      Radius : Positive;
      Half   : access constant Real_Values;
      Tail   : access constant Real_Values;
      Temp   : Ks_Real_Image;
      Acc    : Real_Values_Access;
      Result : Ks_Real_Image)
   with
     Pre  => Has_Pixels (Image)
             and then Half /= null and then Half'First = 0
             and then Half'Last
                        = Natural'Min (Radius,
                                       Natural'Max (Natural (Image.Width),
                                                    Natural (Image.Height)))
             and then Tail /= null and then Tail'First = 0
             and then Tail'Last
                        = Natural'Max (Natural (Image.Width),
                                       Natural (Image.Height)) - 1
             and then Valid_Image (Temp)
             and then Temp.Width = Image.Width
             and then Temp.Height = Image.Height
             and then Acc /= null and then Acc'First = 0
             and then Acc'Last = Natural (Image.Width) - 1
             and then Valid_Image (Result)
             and then Result.Width = Image.Width
             and then Result.Height = Image.Height,
     Post => Bounded_Image (Result)
             and then Result.Width = Image.Width
             and then Result.Height = Image.Height
             and then Valid_Image (Temp)
             and then Acc'First = 0 and then Acc'Last = Acc'Last'Old;
   --  The horizontal pass (Image to Temp), then the vertical pass (Temp to
   --  Result), accumulating whole rows in Acc so that memory is read
   --  sequentially.

   procedure Gaussian_Passes
     (Image  : access constant Ks_Real_Image_Data;
      Radius : Positive;
      Half   : access constant Real_Values;
      Tail   : access constant Real_Values;
      Temp   : Ks_Real_Image;
      Acc    : Real_Values_Access;
      Result : Ks_Real_Image)
   is
      W : constant Positive := Natural (Image.Width);
      H : constant Positive := Natural (Image.Height);
   begin
      --  Horizontal pass: Image -> Temp.
      for Y in 0 .. H - 1 loop
         pragma Loop_Invariant
           (Valid_Image (Temp)
            and then Temp.Width = Image.Width
            and then Temp.Height = Image.Height);
         for I in 0 .. W - 1 loop
            pragma Loop_Invariant
              (Valid_Image (Temp)
               and then Temp.Width = Image.Width
               and then Temp.Height = Image.Height);
            declare
               Lo  : constant Natural :=
                 (if I > Radius then I - Radius else 0);
               Hi  : constant Natural :=
                 (if Radius < W - 1 - I then I + Radius else W - 1);
               Sum : Long_Float := 0.0;
            begin
               for J in Lo .. Hi loop
                  pragma Loop_Invariant (abs Sum <= Sum_Limit);
                  Sum := Accumulate
                    (Sum, N.Times_Unit (Clamped (Image.Pixels (Y, J)),
                                        N.Clamp_Unit (Half (abs (J - I)))));
               end loop;
               if I + 1 <= Radius then
                  Sum := Accumulate
                    (Sum, N.Times_Unit (Clamped (Image.Pixels (Y, 0)),
                                        N.Clamp_Unit (Tail (I))));
               end if;
               if W - I <= Radius then
                  Sum := Accumulate
                    (Sum, N.Times_Unit (Clamped (Image.Pixels (Y, W - 1)),
                                        N.Clamp_Unit (Tail (W - I - 1))));
               end if;
               Temp.Pixels (Y, I) := Clamped (Sum);
            end;
         end loop;
      end loop;

      --  Vertical pass: Temp -> Result.
      for Y in 0 .. H - 1 loop
         pragma Loop_Invariant
           (Valid_Image (Result)
            and then Result.Width = Image.Width
            and then Result.Height = Image.Height
            and then Acc'First = 0 and then Acc'Last = W - 1);
         pragma Loop_Invariant
           (for all R in 0 .. Y - 1
            => (for all C in Result.Pixels'Range (2)
                => In_Bound (Result.Pixels (R, C))));
         declare
            Lo : constant Natural := (if Y > Radius then Y - Radius else 0);
            Hi : constant Natural :=
              (if Radius < H - 1 - Y then Y + Radius else H - 1);
         begin
            for X in 0 .. W - 1 loop
               pragma Loop_Invariant
                 (Acc'First = 0 and then Acc'Last = W - 1);
               Acc (X) := 0.0;
            end loop;
            for J in Lo .. Hi loop
               pragma Loop_Invariant
                 (Acc'First = 0 and then Acc'Last = W - 1);
               Add_Weighted_Row
                 (Acc, Temp, J, N.Clamp_Unit (Half (abs (J - Y))));
            end loop;
            if Y + 1 <= Radius then
               Add_Weighted_Row (Acc, Temp, 0, N.Clamp_Unit (Tail (Y)));
            end if;
            if H - Y <= Radius then
               Add_Weighted_Row
                 (Acc, Temp, H - 1, N.Clamp_Unit (Tail (H - Y - 1)));
            end if;
            for X in 0 .. W - 1 loop
               Result.Pixels (Y, X) := Clamped (Acc (X));
               pragma Loop_Invariant
                 (Valid_Image (Result)
                  and then Result.Width = Image.Width
                  and then Result.Height = Image.Height);
               pragma Loop_Invariant
                 (for all R in 0 .. Y - 1
                  => (for all C in Result.Pixels'Range (2)
                      => In_Bound (Result.Pixels (R, C))));
               pragma Loop_Invariant
                 (for all C in 0 .. X => In_Bound (Result.Pixels (Y, C)));
            end loop;
         end;
      end loop;
   end Gaussian_Passes;

   procedure Gaussian_Smooth
     (Image  : access constant Ks_Real_Image_Data;
      Sigma  : Long_Float;
      Result : out Ks_Real_Image;
      Status : out Ks_Status) is
   begin
      Result := null;
      if not Handle_OK (Image) then
         Bad_Handle ("Gaussian_Smooth", Status);
         return;
      elsif not N.Is_Finite (Sigma) then
         Not_Finite ("Gaussian_Smooth", "Sigma", Status);
         return;
      elsif not (Sigma > 0.0) or else not Has_Pixels (Image) then
         Copy_Filtered (Image, "Gaussian_Smooth", Result, Status);
         return;
      elsif Sigma > Max_Sigma then
         Bad (Status, "Gaussian_Smooth: Sigma must not exceed Max_Sigma");
         return;
      end if;

      declare
         W      : constant Positive := Natural (Image.Width);
         H      : constant Positive := Natural (Image.Height);
         Radius : constant Positive :=
           Positive'Max (1, Natural (Long_Float'Ceiling (3.0 * Sigma)));
         N_Max  : constant Positive := Positive'Max (W, H);
         Kt     : constant Positive := Natural'Min (Radius, N_Max);
         Half   : Real_Values_Access;
         Tail   : Real_Values_Access;
         Acc    : Real_Values_Access;
         Temp   : Ks_Real_Image;
      begin
         Allocate_Values (Int64 (Kt) + 1, Half);
         Allocate_Values (Int64 (N_Max), Tail);
         Allocate_Values (Int64 (W), Acc);
         Allocate (Image.Width, Image.Height, Temp);
         Allocate (Image.Width, Image.Height, Result);
         if Half = null or else Tail = null or else Acc = null
           or else Temp = null or else Result = null
         then
            Free (Half);
            Free (Tail);
            Free (Acc);
            if Temp /= null then
               Free (Temp.Pixels);
            end if;
            Free (Temp);
            Release (Result);
            Out_Of_Memory ("Gaussian_Smooth", Image.Width, Image.Height,
                           Status);
            return;
         end if;
         Gaussian_Tables (Sigma, Radius, Kt, N_Max, Half, Tail);
         Gaussian_Passes (Image, Radius, Half, Tail, Temp, Acc, Result);
         Free (Half);
         Free (Tail);
         Free (Acc);
         if Temp /= null then
            Free (Temp.Pixels);
         end if;
         Free (Temp);
         Set_Success (Status);
      end;
   end Gaussian_Smooth;

   ---------------------------------------------------------------------
   --  Box smoothing
   ---------------------------------------------------------------------

   --  With replicated borders, the window of output I of a line
   --  X (0 .. N - 1) holds the inner part X (Lo .. Hi), with
   --  Lo = max (0, I - Hs) and Hi = min (N - 1, I + Hs), plus
   --  max (0, Hs - I) copies of X (0) and max (0, I + Hs - (N - 1)) copies
   --  of X (N - 1). Only the inner part is kept as a running sum, in which
   --  every sample is added once and removed once; the border copies are
   --  added afresh for each output, so no product of a count and a sample
   --  is ever carried along (its rounding would not be compensated). The
   --  horizontal sums (Temp) are not divided yet; they and the running
   --  sums stay far below Sum_Limit and are read within it.

   function Copies_Before (I, Hs : Natural) return Natural is
     (if Hs > I then Hs - I else 0);
   --  Copies of sample 0 in the window of output I.

   function Copies_After (I, Hs, Last : Natural) return Natural is
     (if Hs > Last - I then Hs - (Last - I) else 0)
   with Pre => I <= Last;
   --  Copies of sample Last in the window of output I.

   procedure Box_Rows
     (Image : access constant Ks_Real_Image_Data;
      Hs    : Positive;
      Temp  : Ks_Real_Image)
   with
     Pre  => Has_Pixels (Image)
             and then Valid_Image (Temp)
             and then Temp.Width = Image.Width
             and then Temp.Height = Image.Height,
     Post => Valid_Image (Temp)
             and then Temp.Width = Image.Width
             and then Temp.Height = Image.Height;
   --  The horizontal window sums (not yet divided): Image -> Temp.

   procedure Box_Rows
     (Image : access constant Ks_Real_Image_Data;
      Hs    : Positive;
      Temp  : Ks_Real_Image)
   is
      W : constant Positive := Natural (Image.Width);
      H : constant Positive := Natural (Image.Height);
   begin
      for Y in 0 .. H - 1 loop
         pragma Loop_Invariant
           (Valid_Image (Temp)
            and then Temp.Width = Image.Width
            and then Temp.Height = Image.Height);
         declare
            First        : constant Long_Float :=
              Clamped (Image.Pixels (Y, 0));
            Last         : constant Long_Float :=
              Clamped (Image.Pixels (Y, W - 1));
            Sum          : Long_Float := 0.0;
            Compensation : Long_Float := 0.0;
         begin
            --  Inner part of output 0: samples 0 .. min (W - 1, Hs).
            for K in 0 .. Natural'Min (W - 1, Hs) loop
               pragma Loop_Invariant
                 (abs Sum <= Sum_Limit and then abs Compensation <= Sum_Limit);
               Add (Sum, Compensation, Clamped (Image.Pixels (Y, K)));
            end loop;
            for I in 0 .. W - 1 loop
               pragma Loop_Invariant
                 (Valid_Image (Temp)
                  and then Temp.Width = Image.Width
                  and then Temp.Height = Image.Height
                  and then abs Sum <= Sum_Limit
                  and then abs Compensation <= Sum_Limit);
               if I > 0 then
                  if I > Hs then
                     Add (Sum, Compensation,
                          -Clamped (Image.Pixels (Y, I - Hs - 1)));
                  end if;
                  if Hs <= W - 1 - I then
                     Add (Sum, Compensation,
                          Clamped (Image.Pixels (Y, I + Hs)));
                  end if;
               end if;
               Temp.Pixels (Y, I) := Sum_Clamped
                 (((Sum + Compensation)
                   + N.Mul (Long_Float (Copies_Before (I, Hs)), First))
                  + N.Mul (Long_Float (Copies_After (I, Hs, W - 1)), Last));
            end loop;
         end;
      end loop;
   end Box_Rows;

   procedure Add_Box_Row
     (Acc, Comp : Real_Values_Access;
      Temp      : access constant Ks_Real_Image_Data;
      Row       : Natural;
      Subtract  : Boolean)
   with
     Pre  => Valid_Image (Temp)
             and then Row <= Temp.Pixels'Last (1)
             and then Acc /= null and then Acc'First = 0
             and then Acc'Last = Temp.Pixels'Last (2)
             and then Comp /= null and then Comp'First = 0
             and then Comp'Last = Temp.Pixels'Last (2),
     Post => Acc'First = 0 and then Acc'Last = Acc'Last'Old
             and then Comp'First = 0 and then Comp'Last = Comp'Last'Old;
   --  Adds (or subtracts) row Row of Temp to the running column sums.

   procedure Add_Box_Row
     (Acc, Comp : Real_Values_Access;
      Temp      : access constant Ks_Real_Image_Data;
      Row       : Natural;
      Subtract  : Boolean)
   is
      V : Long_Float;
   begin
      for X in Temp.Pixels'Range (2) loop
         pragma Loop_Invariant
           (Acc'First = 0 and then Acc'Last = Temp.Pixels'Last (2)
            and then Comp'First = 0 and then Comp'Last = Temp.Pixels'Last (2));
         V := Sum_Clamped (Temp.Pixels (Row, X));
         Add (Acc (X), Comp (X), (if Subtract then -V else V));
      end loop;
   end Add_Box_Row;

   procedure Box_Columns
     (Temp      : access constant Ks_Real_Image_Data;
      Hs        : Positive;
      Acc, Comp : Real_Values_Access;
      Result    : Ks_Real_Image)
   with
     Pre  => Has_Pixels (Temp)
             and then Acc /= null and then Acc'First = 0
             and then Acc'Last = Temp.Pixels'Last (2)
             and then Comp /= null and then Comp'First = 0
             and then Comp'Last = Temp.Pixels'Last (2)
             and then Valid_Image (Result)
             and then Result.Width = Temp.Width
             and then Result.Height = Temp.Height,
     Post => Bounded_Image (Result)
             and then Result.Width = Temp.Width
             and then Result.Height = Temp.Height
             and then Acc'First = 0 and then Acc'Last = Acc'Last'Old
             and then Comp'First = 0 and then Comp'Last = Comp'Last'Old;
   --  The vertical window sums of Temp over whole rows (so memory is read
   --  sequentially), one compensated running sum per column, divided by
   --  the window area: Temp -> Result.

   procedure Box_Columns
     (Temp      : access constant Ks_Real_Image_Data;
      Hs        : Positive;
      Acc, Comp : Real_Values_Access;
      Result    : Ks_Real_Image)
   is
      W     : constant Positive := Natural (Temp.Width);
      H     : constant Positive := Natural (Temp.Height);
      Size  : constant Long_Float := 2.0 * Long_Float (Hs) + 1.0;
      Area  : constant Long_Float := Size * Size;
      Scale : constant Long_Float := N.Unit_Ratio (1.0, Area);
   begin
      for X in 0 .. W - 1 loop
         pragma Loop_Invariant
           (Acc'First = 0 and then Acc'Last = W - 1
            and then Comp'First = 0 and then Comp'Last = W - 1);
         Acc (X) := 0.0;
         Comp (X) := 0.0;
      end loop;
      for K in 0 .. Natural'Min (H - 1, Hs) loop
         pragma Loop_Invariant
           (Acc'First = 0 and then Acc'Last = W - 1
            and then Comp'First = 0 and then Comp'Last = W - 1);
         Add_Box_Row (Acc, Comp, Temp, K, Subtract => False);
      end loop;
      for Y in 0 .. H - 1 loop
         pragma Loop_Invariant
           (Valid_Image (Result)
            and then Result.Width = Temp.Width
            and then Result.Height = Temp.Height
            and then Acc'First = 0 and then Acc'Last = W - 1
            and then Comp'First = 0 and then Comp'Last = W - 1);
         pragma Loop_Invariant
           (for all R in 0 .. Y - 1
            => (for all C in Result.Pixels'Range (2)
                => In_Bound (Result.Pixels (R, C))));
         if Y > 0 then
            if Y > Hs then
               Add_Box_Row (Acc, Comp, Temp, Y - Hs - 1, Subtract => True);
            end if;
            if Hs <= H - 1 - Y then
               Add_Box_Row (Acc, Comp, Temp, Y + Hs, Subtract => False);
            end if;
         end if;
         declare
            Before : constant Long_Float :=
              Long_Float (Copies_Before (Y, Hs));
            After  : constant Long_Float :=
              Long_Float (Copies_After (Y, Hs, H - 1));
         begin
            for X in 0 .. W - 1 loop
               Result.Pixels (Y, X) := Clamped
                 (N.Times_Unit
                    (((Sum_Clamped (Acc (X)) + Sum_Clamped (Comp (X)))
                      + N.Mul (Before, Sum_Clamped (Temp.Pixels (0, X))))
                     + N.Mul (After, Sum_Clamped (Temp.Pixels (H - 1, X))),
                     Scale));
               pragma Loop_Invariant
                 (Valid_Image (Result)
                  and then Result.Width = Temp.Width
                  and then Result.Height = Temp.Height);
               pragma Loop_Invariant
                 (for all R in 0 .. Y - 1
                  => (for all C in Result.Pixels'Range (2)
                      => In_Bound (Result.Pixels (R, C))));
               pragma Loop_Invariant
                 (for all C in 0 .. X => In_Bound (Result.Pixels (Y, C)));
            end loop;
         end;
      end loop;
   end Box_Columns;

   procedure Box_Smooth
     (Image     : access constant Ks_Real_Image_Data;
      Half_Size : Int32;
      Result    : out Ks_Real_Image;
      Status    : out Ks_Status) is
   begin
      Result := null;
      if not Handle_OK (Image) then
         Bad_Handle ("Box_Smooth", Status);
         return;
      elsif Half_Size < 0 then
         Bad (Status, "Box_Smooth: Half_Size must be >= 0");
         return;
      elsif Half_Size = 0 or else not Has_Pixels (Image) then
         Copy_Filtered (Image, "Box_Smooth", Result, Status);
         return;
      end if;

      declare
         Acc  : Real_Values_Access;
         Comp : Real_Values_Access;
         Temp : Ks_Real_Image;
      begin
         Allocate_Values (Int64 (Image.Width), Acc);
         Allocate_Values (Int64 (Image.Width), Comp);
         Allocate (Image.Width, Image.Height, Temp);
         Allocate (Image.Width, Image.Height, Result);
         if Acc = null or else Comp = null or else Temp = null
           or else Result = null
         then
            Free (Acc);
            Free (Comp);
            if Temp /= null then
               Free (Temp.Pixels);
            end if;
            Free (Temp);
            Release (Result);
            Out_Of_Memory ("Box_Smooth", Image.Width, Image.Height, Status);
            return;
         end if;
         Box_Rows (Image, Natural (Half_Size), Temp);
         Box_Columns (Temp, Natural (Half_Size), Acc, Comp, Result);
         Free (Acc);
         Free (Comp);
         if Temp /= null then
            Free (Temp.Pixels);
         end if;
         Free (Temp);
         Set_Success (Status);
      end;
   end Box_Smooth;

   ---------------------------------------------------------------------
   --  Sobel
   ---------------------------------------------------------------------

   function Sobel_Value
     (Image    : access constant Ks_Real_Image_Data;
      Y, X     : Natural;
      Vertical : Boolean) return Long_Float
   with
     Pre  => Has_Pixels (Image)
             and then Y <= Image.Pixels'Last (1)
             and then X <= Image.Pixels'Last (2),
     Post => In_Bound (Sobel_Value'Result);
   --  The derivative d/dx (d/dy when Vertical) at pixel (X, Y), borders
   --  replicated. Because of the replication, a ramp gives half its slope
   --  in the first and last column (or row).

   function Sobel_Value
     (Image    : access constant Ks_Real_Image_Data;
      Y, X     : Natural;
      Vertical : Boolean) return Long_Float
   is
      Last_Y : constant Natural := Image.Pixels'Last (1);
      Last_X : constant Natural := Image.Pixels'Last (2);
      Up     : constant Natural := (if Y > 0 then Y - 1 else 0);
      Down   : constant Natural := (if Y < Last_Y then Y + 1 else Y);
      L      : constant Natural := (if X > 0 then X - 1 else 0);
      R      : constant Natural := (if X < Last_X then X + 1 else X);

      function P (J, I : Natural) return Long_Float is
        (Clamped (Image.Pixels (J, I)))
      with Pre  => Has_Pixels (Image)
                   and then J <= Image.Pixels'Last (1)
                   and then I <= Image.Pixels'Last (2),
           Post => In_Bound (P'Result);
   begin
      if Vertical then
         return Clamped
           (0.125 * (((P (Down, L) - P (Up, L))
                      + 2.0 * (P (Down, X) - P (Up, X)))
                     + (P (Down, R) - P (Up, R))));
      else
         return Clamped
           (0.125 * (((P (Up, R) - P (Up, L))
                      + 2.0 * (P (Y, R) - P (Y, L)))
                     + (P (Down, R) - P (Down, L))));
      end if;
   end Sobel_Value;

   procedure Sobel_Fill
     (Image    : access constant Ks_Real_Image_Data;
      G        : Ks_Real_Image;
      Vertical : Boolean)
   with
     Pre  => Has_Pixels (Image)
             and then Valid_Image (G)
             and then G.Width = Image.Width
             and then G.Height = Image.Height,
     Post => Bounded_Image (G)
             and then G.Width = Image.Width
             and then G.Height = Image.Height;
   --  The derivative d/dx (d/dy when Vertical) of every pixel.

   procedure Sobel_Fill
     (Image    : access constant Ks_Real_Image_Data;
      G        : Ks_Real_Image;
      Vertical : Boolean) is
   begin
      for Y in G.Pixels'Range (1) loop
         for X in G.Pixels'Range (2) loop
            G.Pixels (Y, X) := Sobel_Value (Image, Y, X, Vertical);
            pragma Loop_Invariant
              (Valid_Image (G)
               and then G.Width = Image.Width
               and then G.Height = Image.Height);
            pragma Loop_Invariant
              (for all R in 0 .. Y - 1
               => (for all C in G.Pixels'Range (2)
                   => In_Bound (G.Pixels (R, C))));
            pragma Loop_Invariant
              (for all C in 0 .. X => In_Bound (G.Pixels (Y, C)));
         end loop;
         pragma Loop_Invariant
           (Valid_Image (G)
            and then G.Width = Image.Width
            and then G.Height = Image.Height);
         pragma Loop_Invariant
           (for all R in 0 .. Y
            => (for all C in G.Pixels'Range (2)
                => In_Bound (G.Pixels (R, C))));
      end loop;
   end Sobel_Fill;

   procedure Sobel
     (Image  : access constant Ks_Real_Image_Data;
      Gx, Gy : out Ks_Real_Image;
      Status : out Ks_Status) is
   begin
      Gx := null;
      Gy := null;
      if not Handle_OK (Image) then
         Bad_Handle ("Sobel", Status);
         return;
      elsif not Has_Pixels (Image) then
         Copy_Filtered (Image, "Sobel", Gx, Status);
         if Succeeded (Status) then
            Copy_Filtered (Image, "Sobel", Gy, Status);
            if not Succeeded (Status) then
               Release (Gx);
            end if;
         end if;
         return;
      end if;
      Allocate (Image.Width, Image.Height, Gx);
      Allocate (Image.Width, Image.Height, Gy);
      if Gx = null or else Gy = null then
         Release (Gx);
         Release (Gy);
         Out_Of_Memory ("Sobel", Image.Width, Image.Height, Status);
         return;
      end if;
      Sobel_Fill (Image, Gx, Vertical => False);
      Sobel_Fill (Image, Gy, Vertical => True);
      Set_Success (Status);
   end Sobel;

   ---------------------------------------------------------------------
   --  Pyramid
   ---------------------------------------------------------------------

   procedure Downsample_Fill
     (Image  : access constant Ks_Real_Image_Data;
      Result : Ks_Real_Image)
   with
     Pre  => Has_Pixels (Image)
             and then Valid_Image (Result)
             and then Result.Width = Int32'Max (1, Image.Width / 2)
             and then Result.Height = Int32'Max (1, Image.Height / 2),
     Post => Bounded_Image (Result)
             and then Result.Width = Result.Width'Old
             and then Result.Height = Result.Height'Old;
   --  The 2 x 2 means.

   procedure Downsample_Fill
     (Image  : access constant Ks_Real_Image_Data;
      Result : Ks_Real_Image)
   is
      W  : constant Positive := Natural (Image.Width);
      H  : constant Positive := Natural (Image.Height);
      W2 : constant Positive := Natural (Result.Width);
      H2 : constant Positive := Natural (Result.Height);
      W0 : constant Int32 := Result.Width with Ghost;
      H0 : constant Int32 := Result.Height with Ghost;

      function P (Y, X : Natural) return Long_Float is
        (Clamped (Image.Pixels (Y, X)))
      with Pre  => Has_Pixels (Image)
                   and then Y <= Image.Pixels'Last (1)
                   and then X <= Image.Pixels'Last (2),
           Post => In_Bound (P'Result);

      V : Long_Float;
   begin
      for J in 0 .. H2 - 1 loop
         pragma Loop_Invariant
           (Valid_Image (Result)
            and then Result.Width = W0 and then Result.Height = H0);
         pragma Loop_Invariant
           (for all R in 0 .. J - 1
            => (for all C in Result.Pixels'Range (2)
                => In_Bound (Result.Pixels (R, C))));
         declare
            Y0 : constant Natural := 2 * J;
            Y1 : constant Natural := Natural'Min (Y0 + 1, H - 1);
         begin
            for I in 0 .. W2 - 1 loop
               declare
                  X0 : constant Natural := 2 * I;
                  X1 : constant Natural := Natural'Min (X0 + 1, W - 1);
               begin
                  if X1 /= X0 and then Y1 /= Y0 then
                     V := 0.25 * ((P (Y0, X0) + P (Y0, X1))
                                  + (P (Y1, X0) + P (Y1, X1)));
                  elsif X1 /= X0 then
                     V := 0.5 * (P (Y0, X0) + P (Y0, X1));
                  elsif Y1 /= Y0 then
                     V := 0.5 * (P (Y0, X0) + P (Y1, X0));
                  else
                     V := P (Y0, X0);
                  end if;
                  Result.Pixels (J, I) := Clamped (V);
               end;
               pragma Loop_Invariant
                 (Valid_Image (Result)
                  and then Result.Width = W0 and then Result.Height = H0);
               pragma Loop_Invariant
                 (for all R in 0 .. J - 1
                  => (for all C in Result.Pixels'Range (2)
                      => In_Bound (Result.Pixels (R, C))));
               pragma Loop_Invariant
                 (for all C in 0 .. I => In_Bound (Result.Pixels (J, C)));
            end loop;
         end;
      end loop;
   end Downsample_Fill;

   procedure Downsample_2
     (Image  : access constant Ks_Real_Image_Data;
      Result : out Ks_Real_Image;
      Status : out Ks_Status) is
   begin
      Result := null;
      if not Handle_OK (Image) then
         Bad_Handle ("Downsample_2", Status);
         return;
      elsif not Has_Pixels (Image) then
         Copy_Filtered (Image, "Downsample_2", Result, Status);
         return;
      end if;
      declare
         W2 : constant Int32 := Int32'Max (1, Image.Width / 2);
         H2 : constant Int32 := Int32'Max (1, Image.Height / 2);
      begin
         Lemma_Mul_Le (Int64 (W2), Int64 (Image.Width), Int64 (H2));
         Lemma_Mul_Le (Int64 (H2), Int64 (Image.Height),
                       Int64 (Image.Width));
         Allocate (W2, H2, Result);
         if Result = null then
            Out_Of_Memory ("Downsample_2", W2, H2, Status);
            return;
         end if;
         Downsample_Fill (Image, Result);
         Set_Success (Status);
      end;
   end Downsample_2;

   ---------------------------------------------------------------------
   --  Statistics
   ---------------------------------------------------------------------

   procedure Statistics
     (Image            : access constant Ks_Real_Image_Data;
      Mean, Std_Dev    : out Long_Float;
      Minimum, Maximum : out Long_Float;
      Status           : out Ks_Status) is
   begin
      Mean := 0.0;
      Std_Dev := 0.0;
      Minimum := 0.0;
      Maximum := 0.0;
      if not Handle_OK (Image) then
         Bad_Handle ("Statistics", Status);
         return;
      elsif not Has_Pixels (Image) then
         Empty_Image ("Statistics", Status);
         return;
      end if;
      declare
         Count : constant Long_Float :=
           Long_Float (Int64 (Image.Width) * Int64 (Image.Height));
         Sum   : Long_Float := 0.0;
         Lo    : Long_Float := Clamped (Image.Pixels (0, 0));
         Hi    : Long_Float := Lo;
         M     : Long_Float;
         Sq    : Long_Float := 0.0;
         V     : Long_Float;
      begin
         for Y in Image.Pixels'Range (1) loop
            pragma Loop_Invariant
              (abs Sum <= Sum_Limit
               and then In_Bound (Lo) and then In_Bound (Hi)
               and then Lo <= Hi);
            for X in Image.Pixels'Range (2) loop
               pragma Loop_Invariant
                 (abs Sum <= Sum_Limit
                  and then In_Bound (Lo) and then In_Bound (Hi)
                  and then Lo <= Hi);
               V := Clamped (Image.Pixels (Y, X));
               Sum := Accumulate (Sum, V);
               if V < Lo then
                  Lo := V;
               elsif V > Hi then
                  Hi := V;
               end if;
            end loop;
         end loop;
         --  The mean of values within [Lo, Hi] lies within it; rounding
         --  could carry it just outside (the mean of three values of 0.1
         --  comes out above 0.1), which the limits correct.
         M := Long_Float'Min (Hi, Long_Float'Max (Lo, Sum / Count));
         --  Second pass about the mean: no cancellation for large means.
         for Y in Image.Pixels'Range (1) loop
            pragma Loop_Invariant (Sq >= 0.0 and then Sq <= Square_Sum_Limit);
            for X in Image.Pixels'Range (2) loop
               pragma Loop_Invariant
                 (Sq >= 0.0 and then Sq <= Square_Sum_Limit);
               Sq := Long_Float'Min
                 (Square_Sum_Limit,
                  Sq + N.Square (Clamped (Image.Pixels (Y, X)) - M));
            end loop;
         end loop;
         Mean := M;
         --  The standard deviation is at most half the range; the limit
         --  states a weaker bound for the prover and never acts.
         Std_Dev := Long_Float'Min (EF.Sqrt (Sq / Count), Hi - Lo);
         Minimum := Lo;
         Maximum := Hi;
         Set_Success (Status);
      end;
   end Statistics;

   ---------------------------------------------------------------------
   --  Lean per-pixel access
   ---------------------------------------------------------------------

   procedure Try_Get_Pixel
     (Image : access constant Ks_Real_Image_Data;
      X, Y  : Int32;
      Value : out Long_Float;
      Done  : out Boolean) is
   begin
      Done := Pixel_Exists (Image, X, Y);
      Value := (if Done then Image.Pixels (Natural (Y), Natural (X))
                else 0.0);
   end Try_Get_Pixel;

   procedure Try_Set_Pixel
     (Image : Ks_Real_Image;
      X, Y  : Int32;
      Value : Long_Float;
      Done  : out Boolean) is
   begin
      Done := Pixel_Exists (Image, X, Y) and then In_Bound (Value);
      if Done then
         Image.Pixels (Natural (Y), Natural (X)) := Value;
      end if;
   end Try_Set_Pixel;

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   function Valid_Position
     (Width, Height : Int32;
      Position      : Pixel_Position) return Boolean
   is
     ((Position.Row in 0 .. Height - 1
       and then Position.Column in 0 .. Width - 1)
      or else (Position.Row = Height and then Position.Column = 0))
   with Pre => Width >= 1 and then Height >= 1;
   --  Position is a pixel of the image, or the end (row Height, column 0).

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

   procedure Next_Write_Chunk
     (Image    : access constant Ks_Real_Image_Data;
      Position : Pixel_Position;
      Limit    : Positive;
      Length   : out Natural) is
   begin
      Length := 0;
      if Has_Pixels (Image)
        and then Valid_Position (Image.Width, Image.Height, Position)
      then
         Length := Natural (Int64'Min (Int64 (Limit),
                                       Pixels_Left (Image.Width,
                                                    Image.Height,
                                                    Position)));
      end if;
   end Next_Write_Chunk;

   procedure Get_Bits
     (Image    : access constant Ks_Real_Image_Data;
      Position : in out Pixel_Position;
      Bits     : out Bits_Array;
      Status   : out Ks_Status)
   is
      Next : Pixel_Position;
   begin
      Bits := [others => 0];
      if not Has_Pixels (Image) then
         Bad (Status, "Get_Bits: the image has no pixels");
         return;
      elsif not Valid_Position (Image.Width, Image.Height, Position) then
         Bad (Status, "Get_Bits: the pixel position is not valid");
         return;
      elsif Int64 (Bits'Length)
              > Pixels_Left (Image.Width, Image.Height, Position)
      then
         Bad (Status, "Get_Bits: the chunk is longer than the pixels left");
         return;
      end if;
      Next := Position;
      for K in Bits'Range loop
         pragma Loop_Invariant
           (Valid_Position (Image.Width, Image.Height, Next)
            and then Pixels_Left (Image.Width, Image.Height, Next)
                       >= Int64 (Bits'Last) - Int64 (K) + 1);
         Bits (K) := To_Bits (Image.Pixels (Natural (Next.Row),
                                            Natural (Next.Column)));
         Advance (Image.Width, Image.Height, Next);
      end loop;
      Position := Next;
      Set_Success (Status);
   end Get_Bits;

   procedure Read_Failure
     (Message : String;
      Status  : out Ks_Status)
   with Pre  => Message'Length <= 80,
        Post => Valid (Status) and then Status.Failure = Failure_Image_File;
   --  "Real_Image'Read: <Message>".

   procedure Read_Failure
     (Message : String;
      Status  : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Image_File, "Real_Image'Read: " & Message);
   end Read_Failure;

   procedure Check_Read_Code
     (Code   : U32;
      Status : out Ks_Status) is
   begin
      if Code = Code_Real_Image then
         Set_Success (Status);
      else
         Read_Failure ("the stream does not hold a Real_Image", Status);
      end if;
   end Check_Read_Code;

   procedure Start_Read
     (Width, Height : U32;
      State         : out Read_State;
      Status        : out Ks_Status) is
   begin
      State := (others => <>);
      if Width > 2**31 - 1 or else Height > 2**31 - 1 then
         Read_Failure ("the size is too large", Status);
         return;
      elsif Int64 (Width) * Int64 (Height) > Max_Pixels then
         Read_Failure ("Width * Height is too large", Status);
         return;
      end if;
      State.Width := Int32 (Width);
      State.Height := Int32 (Height);
      State.Count := Int64 (State.Width) * Int64 (State.Height);
      if State.Count > 0 then
         Allocate_Values
           (Int64'Min (State.Count, Initial_Read_Capacity), State.Values);
         if State.Values = null then
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Real_Image'Read: not enough memory");
            return;
         end if;
      end if;
      Set_Success (Status);
   end Start_Read;

   procedure Next_Read_Chunk
     (State  : in out Read_State;
      Limit  : Positive;
      Length : out Natural;
      Status : out Ks_Status) is
   begin
      Length := 0;
      if not Valid_State (State) then
         Bad (Status, "Next_Read_Chunk: the read state is not valid");
         return;
      elsif State.Filled = State.Count then
         Set_Success (Status);
         return;
      end if;
      if State.Filled = Int64 (State.Values'Last) + 1 then
         --  The stream has delivered every value allocated so far: grow
         --  (doubling, up to the declared count).
         declare
            Capacity     : constant Int64 := State.Filled;
            New_Capacity : constant Int64 :=
              (if Capacity > State.Count - Capacity then State.Count
               else 2 * Capacity);
            Bigger       : Real_Values_Access;
         begin
            Allocate_Values (New_Capacity, Bigger);
            if Bigger = null then
               Set_Failure (Status, Failure_Out_Of_Memory,
                            "Real_Image'Read: not enough memory");
               return;
            end if;
            Bigger (0 .. Natural (Capacity) - 1) :=
              State.Values (0 .. Natural (Capacity) - 1);
            Free (State.Values);
            State.Values := Bigger;
         end;
      end if;
      Length := Natural
        (Int64'Min (Int64 (Limit),
                    Int64 (State.Values'Last) + 1 - State.Filled));
      Set_Success (Status);
   end Next_Read_Chunk;

   procedure Store_Bits
     (State  : in out Read_State;
      Bits   : Bits_Array;
      Status : out Ks_Status)
   is
      V    : Long_Float;
      Last : Natural;
   begin
      if not Valid_State (State) or else State.Count = 0
        or else Int64 (Bits'Length)
                  > Int64 (State.Values'Last) + 1 - State.Filled
      then
         Bad (Status, "Store_Bits: the values do not fit");
         return;
      end if;
      Last := State.Values'Last;
      for K in Bits'Range loop
         pragma Loop_Invariant
           (Valid_State (State) and then State.Count > 0
            and then State.Filled = State.Filled'Loop_Entry
                                      + (Int64 (K) - Int64 (Bits'First))
            and then State.Values'Last = Last);
         if not Finite_Bits (Bits (K)) then
            Read_Failure ("a pixel value is not finite", Status);
            return;
         end if;
         V := To_Long_Float (Bits (K));
         if not In_Bound (V) then
            Read_Failure ("a pixel value is beyond +/-1.0E100", Status);
            return;
         end if;
         State.Values (Natural (State.Filled)) := V;
         State.Filled := State.Filled + 1;
      end loop;
      Set_Success (Status);
   end Store_Bits;

   procedure Finish_Read
     (State  : in out Read_State;
      Image  : out Ks_Real_Image;
      Status : out Ks_Status) is
   begin
      Image := null;
      if not Valid_State (State) or else State.Filled /= State.Count then
         Free (State.Values);
         Bad (Status, "Finish_Read: the image is not complete");
         return;
      end if;
      Allocate (State.Width, State.Height, Image);
      if Image = null then
         Free (State.Values);
         Out_Of_Memory ("Real_Image'Read", State.Width, State.Height,
                        Status);
         return;
      end if;
      if State.Count > 0 then
         declare
            W : constant Int64 := Int64 (State.Width);
            H : constant Int64 := Int64 (State.Height);
            Row_Start : Int64;
         begin
            for Y in Image.Pixels'Range (1) loop
               pragma Loop_Invariant
                 (Valid_Image (Image)
                  and then Image.Width = State.Width
                  and then Image.Height = State.Height);
               pragma Loop_Invariant
                 (for all R in 0 .. Y - 1
                  => (for all C in Image.Pixels'Range (2)
                      => In_Bound (Image.Pixels (R, C))));
               Lemma_Mul_Le (Int64 (Y), H - 1, W);
               pragma Assert (Big (H - 1) * Big (W) + Big (W)
                                = Big (H) * Big (W));
               Row_Start := Int64 (Y) * W;
               for X in Image.Pixels'Range (2) loop
                  Image.Pixels (Y, X) :=
                    Clamped (State.Values (Natural (Row_Start + Int64 (X))));
                  pragma Loop_Invariant
                    (Valid_Image (Image)
                     and then Image.Width = State.Width
                     and then Image.Height = State.Height);
                  pragma Loop_Invariant
                    (for all R in 0 .. Y - 1
                     => (for all C in Image.Pixels'Range (2)
                         => In_Bound (Image.Pixels (R, C))));
                  pragma Loop_Invariant
                    (for all C in 0 .. X => In_Bound (Image.Pixels (Y, C)));
               end loop;
            end loop;
         end;
      end if;
      Free (State.Values);
      Set_Success (Status);
   end Finish_Read;

   procedure Abandon_Read (State : in out Read_State) is
   begin
      Free (State.Values);
   end Abandon_Read;

   procedure Stream_Ended (Status : out Ks_Status) is
   begin
      Read_Failure ("the stream ends before the image does", Status);
   end Stream_Ended;

end AMV.Kernels.Image_Math;
