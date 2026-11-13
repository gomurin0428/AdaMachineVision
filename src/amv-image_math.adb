pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.IO_Exceptions;

with AMV.Checks;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Images;
with AMV.Kernels.Transforms;

package body AMV.Image_Math is

   package KR renames AMV.Kernels.Image_Math;
   package KI renames AMV.Kernels.Images;
   package KT renames AMV.Kernels.Transforms;
   package Kernel_Images renames AMV.Images.Kernel_Images;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;

   use type Int32;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   procedure Raise_Failure (Status : Ks_Status)
   with No_Return;
   --  Raises the exception for Status, the failure of an entry point
   --  called because its lean variant (KR.Try_*) reported one.

   procedure Raise_Failure (Status : Ks_Status) is
   begin
      Check (Status);
      raise Program_Error with "the kernel reported no failure";
   end Raise_Failure;

   procedure Replace (Image : in out Real_Image; Handle : KR.Ks_Real_Image);
   --  Image takes over Handle (a new handle the caller owns); its previous
   --  handle is destroyed afterwards, so Handle may have been computed
   --  from it.

   procedure Replace (Image : in out Real_Image; Handle : KR.Ks_Real_Image)
   is
      Old    : KR.Ks_Real_Image := Image.Handle;
      Status : Ks_Status;
   begin
      Image.Handle := Handle;
      KR.Destroy (Old, Status);
   end Replace;

   function To_Kernel
     (Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return KT.Ks_Transform_2D_Linear;

   function To_Kernel
     (Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return KT.Ks_Transform_2D_Linear
   is
      Result : KT.Ks_Transform_2D_Linear;
   begin
      Transform.Get_Matrix_Elements_Translation
        (Result.A, Result.B, Result.C, Result.D, Result.Translation_X,
         Result.Translation_Y);
      return Result;
   end To_Kernel;

   ---------------------------------------------------------------------
   --  Controlled operations
   ---------------------------------------------------------------------

   overriding procedure Adjust (Image : in out Real_Image) is
      --  On entry Image is a bitwise copy of the source and still holds the
      --  source's handle. It lets go of that handle before the copy that
      --  can fail, so that a failed copy leaves Image empty (0 x 0) rather
      --  than sharing the source's pixels.
      Source : constant KR.Ks_Real_Image := Image.Handle;
      Status : Ks_Status;
   begin
      Image.Handle := null;
      KR.Duplicate (Source, Image.Handle, Status);
      Check (Status);
   end Adjust;

   overriding procedure Finalize (Image : in out Real_Image) is
      Status : Ks_Status;
   begin
      KR.Destroy (Image.Handle, Status);
   end Finalize;

   ---------------------------------------------------------------------
   --  Basic access
   ---------------------------------------------------------------------

   function Create
     (Width, Height : Natural; Value : Real := 0.0)  --  SHELL: default
      return Real_Image
   is
      Status : Ks_Status;
   begin
      return Result : Real_Image do
         KR.Create (Int32 (Width), Int32 (Height), Value, Result.Handle,
                    Status);
         Check (Status);
      end return;
   end Create;

   function Width (Image : Real_Image) return Natural is
      Result : Int32;
      Status : Ks_Status;
   begin
      KR.Width (Image.Handle, Result, Status);
      Check (Status);
      return Natural (Result);
   end Width;

   function Height (Image : Real_Image) return Natural is
      Result : Int32;
      Status : Ks_Status;
   begin
      KR.Height (Image.Handle, Result, Status);
      Check (Status);
      return Natural (Result);
   end Height;

   --  Get and Set are called once per pixel, so they use the kernel's lean
   --  variants, which build no status, and call the entry point only to
   --  report a failure.

   procedure Get_Failed (Image : KR.Ks_Real_Image; X, Y : Natural)
   with No_Return;

   procedure Get_Failed (Image : KR.Ks_Real_Image; X, Y : Natural) is
      Value  : Real;
      Status : Ks_Status;
   begin
      KR.Get_Pixel (Image, Int32 (X), Int32 (Y), Value, Status);
      Raise_Failure (Status);
   end Get_Failed;

   procedure Set_Failed
     (Image : KR.Ks_Real_Image; X, Y : Natural; Value : Real)
   with No_Return;

   procedure Set_Failed
     (Image : KR.Ks_Real_Image; X, Y : Natural; Value : Real)
   is
      Status : Ks_Status;
   begin
      KR.Set_Pixel (Image, Int32 (X), Int32 (Y), Value, Status);
      Raise_Failure (Status);
   end Set_Failed;

   function Get (Image : Real_Image; X, Y : Natural) return Real is
      Value : Real;
      Done  : Boolean;
   begin
      KR.Try_Get_Pixel (Image.Handle, Int32 (X), Int32 (Y), Value, Done);
      if not Done then
         Get_Failed (Image.Handle, X, Y);
      end if;
      return Value;
   end Get;

   procedure Set (Image : in out Real_Image; X, Y : Natural; Value : Real)
   is
      Done : Boolean;
   begin
      KR.Try_Set_Pixel (Image.Handle, Int32 (X), Int32 (Y), Value, Done);
      if not Done then
         Set_Failed (Image.Handle, X, Y, Value);
      end if;
   end Set;

   procedure Fill (Image : in out Real_Image; Value : Real) is
      Status : Ks_Status;
   begin
      KR.Fill (Image.Handle, Value, Status);
      Check (Status);
   end Fill;

   ---------------------------------------------------------------------
   --  Conversion
   ---------------------------------------------------------------------

   function From_Grey_8
     (Image : AMV.Images.Ks_Image_8_Grey) return Real_Image
   is
      Status : Ks_Status;
   begin
      return Result : Real_Image do
         KR.From_Grey_8 (Kernel_Images.Kernel_Handle (Image), Result.Handle,
                         Status);
         Check (Status);
      end return;
   end From_Grey_8;

   function From_Grey_8
     (Image                       : AMV.Images.Ks_Image_8_Grey;
      X_Min, Y_Min, Width, Height : Natural) return Real_Image
   is
      Status : Ks_Status;
   begin
      return Result : Real_Image do
         KR.From_Grey_8_Window
           (Kernel_Images.Kernel_Handle (Image), Int32 (X_Min),
            Int32 (Y_Min), Int32 (Width), Int32 (Height), Result.Handle,
            Status);
         Check (Status);
      end return;
   end From_Grey_8;

   function To_Grey_8 (Image : Real_Image) return AMV.Images.Ks_Image_8_Grey
   is
      Handle : KI.Ks_Image_8_Grey;
      Status : Ks_Status;
   begin
      KR.To_Grey_8 (Image.Handle, Handle, Status);
      Check (Status);
      return Kernel_Images.Adopt (Handle);
   end To_Grey_8;

   ---------------------------------------------------------------------
   --  Sampling
   ---------------------------------------------------------------------

   function Bilinear (Image : Real_Image; X, Y : Real) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      KR.Bilinear (Image.Handle, X, Y, Result, Status);
      Check (Status);
      return Result;
   end Bilinear;

   function Bilinear
     (Image : AMV.Images.Ks_Image_8_Grey; X, Y : Real) return Real
   is
      Result : Real;
      Status : Ks_Status;
   begin
      KR.Bilinear_Grey_8 (Kernel_Images.Kernel_Handle (Image), X, Y, Result,
                          Status);
      Check (Status);
      return Result;
   end Bilinear;

   function Is_Inside (Image : Real_Image; X, Y : Real) return Boolean is
      Result : Int32;
      Status : Ks_Status;
   begin
      KR.Is_Inside (Image.Handle, X, Y, Result, Status);
      Check (Status);
      return Result = AMV.Kernels.True_Value;
   end Is_Inside;

   function Resample
     (Image             : AMV.Images.Ks_Image_8_Grey;
      Pixel_From_Output : AMV.Transforms.Ks_Transform_2D_Linear;
      Width, Height     : Positive) return Real_Image
   is
      Status : Ks_Status;
   begin
      return Result : Real_Image do
         KR.Resample_Grey_8
           (Kernel_Images.Kernel_Handle (Image), To_Kernel (Pixel_From_Output),
            Int32 (Width), Int32 (Height), Result.Handle, Status);
         Check (Status);
      end return;
   end Resample;

   function Resample
     (Image             : Real_Image;
      Pixel_From_Output : AMV.Transforms.Ks_Transform_2D_Linear;
      Width, Height     : Positive) return Real_Image
   is
      Status : Ks_Status;
   begin
      return Result : Real_Image do
         KR.Resample
           (Image.Handle, To_Kernel (Pixel_From_Output), Int32 (Width),
            Int32 (Height), Result.Handle, Status);
         Check (Status);
      end return;
   end Resample;

   ---------------------------------------------------------------------
   --  Filters and statistics
   ---------------------------------------------------------------------

   function Gaussian_Smooth
     (Image : Real_Image; Sigma : Real) return Real_Image
   is
      Status : Ks_Status;
   begin
      return Result : Real_Image do
         KR.Gaussian_Smooth (Image.Handle, Sigma, Result.Handle, Status);
         Check (Status);
      end return;
   end Gaussian_Smooth;

   function Box_Smooth
     (Image : Real_Image; Half_Size : Natural) return Real_Image
   is
      Status : Ks_Status;
   begin
      return Result : Real_Image do
         KR.Box_Smooth (Image.Handle, Int32 (Half_Size), Result.Handle,
                        Status);
         Check (Status);
      end return;
   end Box_Smooth;

   procedure Sobel (Image : Real_Image; Gx, Gy : out Real_Image) is
      New_X, New_Y : KR.Ks_Real_Image;
      Status       : Ks_Status;
   begin
      KR.Sobel (Image.Handle, New_X, New_Y, Status);
      Check (Status);
      --  Gx or Gy may be the same object as Image, so they are only
      --  replaced once the work is done.
      Replace (Gx, New_X);
      Replace (Gy, New_Y);
   end Sobel;

   function Downsample_2 (Image : Real_Image) return Real_Image is
      Status : Ks_Status;
   begin
      return Result : Real_Image do
         KR.Downsample_2 (Image.Handle, Result.Handle, Status);
         Check (Status);
      end return;
   end Downsample_2;

   procedure Statistics
     (Image          : Real_Image;
      Mean, Std_Dev  : out Real;
      Minimum, Maximum : out Real)
   is
      Status : Ks_Status;
   begin
      KR.Statistics (Image.Handle, Mean, Std_Dev, Minimum, Maximum, Status);
      Check (Status);
   end Statistics;

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   Chunk_Length : constant := 1024;
   --  Values per chunk (8 KB on the stack).

   procedure Write_Image
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Real_Image)
   is
      Position : KR.Pixel_Position;
      Bits     : KR.Bits_Array (1 .. Chunk_Length) := [others => 0];
      Length   : Natural;
      Status   : Ks_Status;
   begin
      KR.U32'Write (Stream, KR.Code_Real_Image);
      KR.U32'Write (Stream, KR.U32 (Item.Width));
      KR.U32'Write (Stream, KR.U32 (Item.Height));
      loop  --  SHELL: stream I/O, one chunk of values at a time
         KR.Next_Write_Chunk (Item.Handle, Position, Chunk_Length, Length);
         exit when Length = 0;
         KR.Get_Bits (Item.Handle, Position, Bits (1 .. Length), Status);
         Check (Status);
         KR.Bits_Array'Write (Stream, Bits (1 .. Length));
      end loop;  --  SHELL: (the loop above)
   end Write_Image;

   procedure Read_Image
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Real_Image)
   is
      Code, W, H : KR.U32;
      State      : KR.Read_State;
      Bits       : KR.Bits_Array (1 .. Chunk_Length) := [others => 0];
      Length     : Natural;
      Handle     : KR.Ks_Real_Image;
      Status     : Ks_Status;
   begin
      KR.U32'Read (Stream, Code);
      KR.Check_Read_Code (Code, Status);
      Check (Status);
      KR.U32'Read (Stream, W);
      KR.U32'Read (Stream, H);
      KR.Start_Read (W, H, State, Status);
      Check (Status);
      loop  --  SHELL: stream I/O, one chunk of values at a time
         KR.Next_Read_Chunk (State, Chunk_Length, Length, Status);
         Check (Status);
         exit when Length = 0;
         KR.Bits_Array'Read (Stream, Bits (1 .. Length));
         KR.Store_Bits (State, Bits (1 .. Length), Status);
         Check (Status);
      end loop;  --  SHELL: (the loop above)
      KR.Finish_Read (State, Handle, Status);
      Check (Status);
      Replace (Item, Handle);
   exception
      when Ada.IO_Exceptions.End_Error =>
         KR.Abandon_Read (State);
         KR.Stream_Ended (Status);
         Raise_Failure (Status);
      when others =>
         KR.Abandon_Read (State);
         raise;
   end Read_Image;

end AMV.Image_Math;
