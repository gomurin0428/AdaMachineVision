pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.IO_Exceptions;
with Ada.Unchecked_Conversion;

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;
with AMV.Shapes.Kernel_Shapes;
with AMV.Transforms;

package body AMV.Regions is

   package KR renames AMV.Kernels.Regions;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;
   package Kernel_Shapes renames AMV.Shapes.Kernel_Shapes;

   use type AMV.Kernels.Int32;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

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
   --  Construction
   ---------------------------------------------------------------------

   function Whole_Image
     (Image : AMV.Images.Ks_Image'Class) return Pixel_Region
   is
      Status : Ks_Status;
   begin
      return Result : Pixel_Region do
         KR.Whole_Image
           (Int32 (Image.Width), Int32 (Image.Height), Result.Handle, Status);
         Check (Status);
      end return;
   end Whole_Image;

   function Rasterize
     (Image  : AMV.Images.Ks_Image'Class;
      Region : AMV.Shapes.Ks_Region'Class) return Pixel_Region
   is
      Width  : constant Int32 := Int32 (Image.Width);
      Height : constant Int32 := Int32 (Image.Height);
      Kind   : constant Int32 := Kernel_Shapes.Kernel_Type (Region);
      Status : Ks_Status;
   begin
      --  The image and the region's type first, then the space name.
      KR.Check_Rasterize (Width, Height, Kind, Status);
      Check (Status);
      declare
         Pixel_From_Region : constant KT.Ks_Transform_2D_Linear :=
           To_Kernel
             (Image.Get_Transform
                (AMV.Coordinate_Spaces.Pixel_Space_Name,
                 Region.Selected_Space_Name));
      begin
         return Result : Pixel_Region do
            case Kind is
               when KS.Shape_Rectangle =>
                  KR.Rasterize_Rectangle
                    (Width, Height, Pixel_From_Region,
                     Kernel_Shapes.Kernel_Rectangle
                       (AMV.Shapes.Ks_Rectangle'Class (Region)),
                     Result.Handle, Status);
               when KS.Shape_Rectangle_Affine =>
                  KR.Rasterize_Rectangle_Affine
                    (Width, Height, Pixel_From_Region,
                     Kernel_Shapes.Kernel_Rectangle_Affine
                       (AMV.Shapes.Ks_Rectangle_Affine'Class (Region)),
                     Result.Handle, Status);
               when KS.Shape_Circle =>
                  KR.Rasterize_Circle
                    (Width, Height, Pixel_From_Region,
                     Kernel_Shapes.Kernel_Circle
                       (AMV.Shapes.Ks_Circle'Class (Region)),
                     Result.Handle, Status);
               when KS.Shape_Ellipse =>
                  KR.Rasterize_Ellipse
                    (Width, Height, Pixel_From_Region,
                     Kernel_Shapes.Kernel_Ellipse
                       (AMV.Shapes.Ks_Ellipse'Class (Region)),
                     Result.Handle, Status);
               when KS.Shape_Polygon =>
                  KR.Rasterize_Polygon
                    (Width, Height, Pixel_From_Region,
                     Kernel_Shapes.Kernel_Polygon
                       (AMV.Shapes.Ks_Polygon'Class (Region)),
                     Result.Handle, Status);
               when others =>
                  --  Check_Rasterize admits no other type.
                  KR.Rasterize_Circular_Annulus_Section
                    (Width, Height, Pixel_From_Region,
                     Kernel_Shapes.Kernel_Circular_Annulus_Section
                       (AMV.Shapes.Ks_Circular_Annulus_Section'Class
                          (Region)),
                     Result.Handle, Status);
            end case;
            Check (Status);
         end return;
      end;
   end Rasterize;

   function Rasterize
     (Image  : AMV.Images.Ks_Image'Class;
      Region : AMV.Shapes.Region_Holders.Holder) return Pixel_Region is
   begin
      if Region.Is_Empty then
         return Whole_Image (Image);
      else
         return Rasterize (Image, Region.Constant_Reference.Element.all);
      end if;
   end Rasterize;

   function Bounding_Box (Region : Pixel_Region) return Pixel_Region is
      Status : Ks_Status;
   begin
      return Result : Pixel_Region do
         KR.Bounding_Box (Region.Handle, Result.Handle, Status);
         Check (Status);
      end return;
   end Bounding_Box;

   function Restrict_To_Mask
     (Region   : Pixel_Region;
      Mask     : AMV.Images.Ks_Image_8_Grey'Class;
      Offset_X : Integer := 0;
      Offset_Y : Integer := 0) return Pixel_Region
   is
      Status : Ks_Status;
   begin
      return Result : Pixel_Region do
         KR.Restrict_To_Mask
           (Region.Handle, AMV.Images.Kernel_Images.Kernel_Handle (Mask),
            Int32 (Offset_X), Int32 (Offset_Y), Result.Handle, Status);
         Check (Status);
      end return;
   end Restrict_To_Mask;

   ---------------------------------------------------------------------
   --  Queries
   ---------------------------------------------------------------------

   function Is_Empty (Region : Pixel_Region) return Boolean is
      Result : Int32;
      Status : Ks_Status;
   begin
      KR.Is_Empty (Region.Handle, Result, Status);
      Check (Status);
      return Result = AMV.Kernels.True_Value;
   end Is_Empty;

   function Pixel_Count (Region : Pixel_Region) return Natural is
      Result : Int32;
      Status : Ks_Status;
   begin
      KR.Pixel_Count (Region.Handle, Result, Status);
      Check (Status);
      return Natural (Result);
   end Pixel_Count;

   type Bounds is record
      X_Min, Y_Min, Width, Height : Int32;
   end record;

   function Bounds_Of (Region : Pixel_Region) return Bounds;
   --  The bounding rectangle as the kernel reports it.

   function Bounds_Of (Region : Pixel_Region) return Bounds is
      Result : Bounds;
      Status : Ks_Status;
   begin
      KR.Get_Bounds
        (Region.Handle, Result.X_Min, Result.Y_Min, Result.Width,
         Result.Height, Status);
      Check (Status);
      return Result;
   end Bounds_Of;

   function X_Min (Region : Pixel_Region) return Natural is
     (Natural (Bounds_Of (Region).X_Min));
   function Y_Min (Region : Pixel_Region) return Natural is
     (Natural (Bounds_Of (Region).Y_Min));
   function Width (Region : Pixel_Region) return Natural is
     (Natural (Bounds_Of (Region).Width));
   function Height (Region : Pixel_Region) return Natural is
     (Natural (Bounds_Of (Region).Height));

   function Contains (Region : Pixel_Region; X, Y : Integer) return Boolean
   is (KR.Contains (Region.Handle, Int32 (X), Int32 (Y)));
   --  The kernel's status-free test (Integer and Int32 have the same
   --  range).

   ---------------------------------------------------------------------
   --  Controlled operations
   ---------------------------------------------------------------------

   overriding procedure Adjust (Region : in out Pixel_Region) is
      Shared : constant KR.Ks_Pixel_Region := Region.Handle;
      Status : Ks_Status;
   begin
      --  The handle is still the source's: drop it first, so that a
      --  failed duplicate leaves the copy empty instead of sharing it.
      Region.Handle := null;
      KR.Duplicate (Shared, Region.Handle, Status);
      Check (Status);
   end Adjust;

   overriding procedure Finalize (Region : in out Pixel_Region) is
      Status : Ks_Status;
   begin
      KR.Destroy (Region.Handle, Status);
   end Finalize;

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   use Ada.Streams;

   Chunk_Length : constant := 4096;
   --  Pixel elements are moved through a chunk of this many stream
   --  elements.

   subtype Chunk_Elements is Stream_Element_Array (1 .. Chunk_Length);
   subtype Chunk_Bytes is KR.Byte_Array (1 .. Chunk_Length);
   subtype Header_Elements is
     Stream_Element_Array (1 .. KR.Header_Length);

   function To_Elements is new Ada.Unchecked_Conversion
     (Chunk_Bytes, Chunk_Elements);
   function To_Bytes is new Ada.Unchecked_Conversion
     (Chunk_Elements, Chunk_Bytes);
   function To_Header_Elements is new Ada.Unchecked_Conversion
     (KR.Header_Bytes, Header_Elements);
   function To_Header is new Ada.Unchecked_Conversion
     (Header_Elements, KR.Header_Bytes);
   --  A stream element is a byte (GNAT); the arrays have the same
   --  representation.

   procedure Write
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Pixel_Region)
   is
      Header   : KR.Header_Bytes;
      Position : KR.Flag_Position;
      Bytes    : Chunk_Bytes := [others => 0];
      Length   : Natural;
      Status   : Ks_Status;
   begin
      KR.Stream_Header (Item.Handle, Header, Status);
      Check (Status);
      Header_Elements'Write (Stream, To_Header_Elements (Header));
      loop  --  SHELL: stream I/O, one chunk of pixel elements at a time
         KR.Next_Write_Chunk (Item.Handle, Position, Chunk_Length, Length);
         exit when Length = 0;
         KR.Get_Flag_Bytes (Item.Handle, Position, Bytes (1 .. Length),
                            Status);
         Check (Status);
         Stream_Element_Array'Write
           (Stream, To_Elements (Bytes) (1 .. Stream_Element_Offset (Length)));
      end loop;  --  SHELL: (the loop above)
   end Write;

   type Reader_Holder is new Ada.Finalization.Limited_Controlled with record
      Reader : KR.Ks_Region_Reader;
   end record;
   --  Owns a kernel reader while a region is read, so that it is freed on
   --  every path out of Read, exceptions included.

   overriding procedure Finalize (Holder : in out Reader_Holder);

   overriding procedure Finalize (Holder : in out Reader_Holder) is
   begin
      KR.Destroy_Reader (Holder.Reader);
   end Finalize;

   procedure Stream_Ended with No_Return;
   --  Raises Ks_Image_File_Exception for a stream that ends before the
   --  region is complete.

   procedure Stream_Ended is
      Status : Ks_Status;
   begin
      KR.Stream_Ended (Status);
      Check (Status);
      raise Program_Error with "a kernel failure was not reported";
   end Stream_Ended;

   procedure Read
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Pixel_Region)
   is
      Holder   : Reader_Holder;
      Header   : Header_Elements;
      Elements : Chunk_Elements := [others => 0];
      Length   : Natural;
      Fresh    : KR.Ks_Pixel_Region;
      Status   : Ks_Status;
   begin
      --  The kernel checks every field before anything is allocated for
      --  the pixels, and the elements as they arrive.
      Header_Elements'Read (Stream, Header);
      KR.Read_Header (To_Header (Header), Holder.Reader, Status);
      Check (Status);
      loop  --  SHELL: stream I/O, one chunk of pixel elements at a time
         KR.Next_Read_Chunk (Holder.Reader, Chunk_Length, Length);
         exit when Length = 0;
         Stream_Element_Array'Read
           (Stream, Elements (1 .. Stream_Element_Offset (Length)));
         KR.Put_Read_Bytes
           (Holder.Reader, To_Bytes (Elements) (1 .. Length), Status);
         Check (Status);
      end loop;  --  SHELL: (the loop above)
      KR.Finish_Read (Holder.Reader, Fresh, Status);
      Check (Status);
      --  Every check passed: only now is Item changed.
      KR.Destroy (Item.Handle, Status);
      Item.Handle := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error =>
         Stream_Ended;
   end Read;

end AMV.Regions;
