pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;

package body AMV.Images.Kernel_Images is

   package KI renames AMV.Kernels.Images;

   use type KI.Ks_Image_8_Grey;
   use type KI.Ks_Image_16_Grey;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   function Box (Owned : KI.Ks_Image_8_Grey) return Pixel_Box_8_Access;
   --  A box that takes over Owned (none for null). Owned is destroyed when
   --  the box cannot be allocated.

   function Box (Owned : KI.Ks_Image_8_Grey) return Pixel_Box_8_Access is
      Orphan : KI.Ks_Image_8_Grey := Owned;
      Status : Ks_Status;
   begin
      if Owned = null then
         return null;
      end if;
      return new Pixel_Box_8'(References => 1, Handle => Owned);
   exception
      when Storage_Error =>
         KI.Destroy (Orphan, Status);
         raise;
   end Box;

   function Box (Owned : KI.Ks_Image_16_Grey) return Pixel_Box_16_Access;

   function Box (Owned : KI.Ks_Image_16_Grey) return Pixel_Box_16_Access is
      Orphan : KI.Ks_Image_16_Grey := Owned;
      Status : Ks_Status;
   begin
      if Owned = null then
         return null;
      end if;
      return new Pixel_Box_16'(References => 1, Handle => Owned);
   exception
      when Storage_Error =>
         KI.Destroy (Orphan, Status);
         raise;
   end Box;

   procedure Take
     (Target         : out Pixel_Box_8_Access;
      Owned          : KI.Ks_Image_8_Grey;
      Later_1        : KI.Ks_Image_8_Grey;
      Later_2        : KI.Ks_Image_8_Grey);
   --  Target := Box (Owned). When that raises, the planes not taken over
   --  yet (Later_1 and Later_2) are destroyed too.

   procedure Take
     (Target         : out Pixel_Box_8_Access;
      Owned          : KI.Ks_Image_8_Grey;
      Later_1        : KI.Ks_Image_8_Grey;
      Later_2        : KI.Ks_Image_8_Grey)
   is
      Orphan_1 : KI.Ks_Image_8_Grey := Later_1;
      Orphan_2 : KI.Ks_Image_8_Grey := Later_2;
      Status   : Ks_Status;
   begin
      Target := Box (Owned);
   exception
      when others =>
         KI.Destroy (Orphan_1, Status);
         KI.Destroy (Orphan_2, Status);
         raise;
   end Take;

   function Adopt (Handle : KI.Ks_Image_8_Grey) return Ks_Image_8_Grey is
      Width, Height : Int32;
      Status        : Ks_Status;
   begin
      return Result : Ks_Image_8_Grey do
         --  Owned by Result at once, so that a failure below frees it.
         Result.Buffer := Box (Handle);
         KI.Width (Handle, Width, Status);
         Check (Status);
         KI.Height (Handle, Height, Status);
         Check (Status);
         Result.Width := Natural (Width);
         Result.Height := Natural (Height);
      end return;
   end Adopt;

   function Adopt (Handle : KI.Ks_Image_16_Grey) return Ks_Image_16_Grey is
      Width, Height : Int32;
      Status        : Ks_Status;
   begin
      return Result : Ks_Image_16_Grey do
         Result.Buffer := Box (Handle);
         KI.Width (Handle, Width, Status);
         Check (Status);
         KI.Height (Handle, Height, Status);
         Check (Status);
         Result.Width := Natural (Width);
         Result.Height := Natural (Height);
      end return;
   end Adopt;

   function Adopt
     (Handle    : KI.Ks_Image_8_Grey;
      Spaces_Of : Ks_Image'Class) return Ks_Image_8_Grey is
   begin
      return Result : Ks_Image_8_Grey := Adopt (Handle) do
         Result.Spaces := Spaces_Of.Spaces;
      end return;
   end Adopt;

   function Adopt_With_Pixel_From_Root
     (Handle          : KI.Ks_Image_8_Grey;
      Spaces_Of       : Ks_Image'Class;
      Pixel_From_Root : AMV.Kernels.Transforms.Ks_Transform_2D_Linear)
      return Ks_Image_8_Grey
   is
      Status : Ks_Status;
   begin
      return Result : Ks_Image_8_Grey := Adopt (Handle, Spaces_Of) do
         KI.Set_Pixel_From_Root_Transform
           (Result.Spaces.Pixel_From_Root, Pixel_From_Root, Status);
         Check (Status);
      end return;
   end Adopt_With_Pixel_From_Root;

   function Adopt
     (Handle           : KI.Ks_Image_8_Grey;
      Spaces_Of        : Ks_Image'Class;
      Pixel_From_Input : AMV.Kernels.Transforms.Ks_Transform_2D_Linear)
      return Ks_Image_8_Grey
   is
      Composed : AMV.Kernels.Transforms.Ks_Transform_2D_Linear;
      Status   : Ks_Status;
   begin
      return Result : Ks_Image_8_Grey := Adopt (Handle, Spaces_Of) do
         AMV.Kernels.Transforms.Compose
           (Pixel_From_Input, Spaces_Of.Spaces.Pixel_From_Root, Composed,
            Status);
         Check (Status);
         KI.Set_Pixel_From_Root_Transform
           (Result.Spaces.Pixel_From_Root, Composed, Status);
         Check (Status);
      end return;
   end Adopt;

   function Adopt
     (Red_Handle, Green_Handle, Blue_Handle : KI.Ks_Image_8_Grey)
      return Ks_Image_24_Planar_Color
   is
      Width, Height : Int32;
      Status        : Ks_Status;
   begin
      return Result : Ks_Image_24_Planar_Color do
         Take (Result.Planes (AMV.Images.Red), Red_Handle, Green_Handle,
               Blue_Handle);
         Take (Result.Planes (AMV.Images.Green), Green_Handle, Blue_Handle,
               null);
         Take (Result.Planes (AMV.Images.Blue), Blue_Handle, null, null);
         KI.Width (Red_Handle, Width, Status);
         Check (Status);
         KI.Height (Red_Handle, Height, Status);
         Check (Status);
         Result.Width := Natural (Width);
         Result.Height := Natural (Height);
      end return;
   end Adopt;

   function Kernel_Handle
     (Image : Ks_Image_8_Grey'Class)
      return access constant KI.Ks_Image_8_Grey_Data is
     (if Image.Buffer = null then null else Image.Buffer.Handle);

   function Kernel_Handle
     (Image : Ks_Image_16_Grey'Class)
      return access constant KI.Ks_Image_16_Grey_Data is
     (if Image.Buffer = null then null else Image.Buffer.Handle);

   function Kernel_Plane
     (Image : Ks_Image_24_Planar_Color'Class;
      Plane : Ks_Image_Plane_Constants)
      return access constant KI.Ks_Image_8_Grey_Data is
     (if Image.Planes (Plane) = null then null
      else Image.Planes (Plane).Handle);

   function Kernel_Handles
     (Image : AMV.Images.Image_Holders.Holder) return Any_Image_Handles is
   begin
      if Image.Is_Empty then
         return (Grey_8 => null, Grey_16 => null, Red => null,
                 Green => null, Blue => null);
      end if;
      declare
         Element : Ks_Image'Class renames Image.Constant_Reference.Element.all;
      begin
         if Element in Ks_Image_8_Grey'Class then
            return (Grey_8  => Kernel_Handle (Ks_Image_8_Grey'Class (Element)),
                    Grey_16 => null, Red => null, Green => null,
                    Blue    => null);
         elsif Element in Ks_Image_16_Grey'Class then
            return (Grey_8  => null,
                    Grey_16 =>
                      Kernel_Handle (Ks_Image_16_Grey'Class (Element)),
                    Red     => null, Green => null, Blue => null);
         elsif Element in Ks_Image_24_Planar_Color'Class then
            return (Grey_8  => null, Grey_16 => null,
                    Red     =>
                      Kernel_Plane (Ks_Image_24_Planar_Color'Class (Element),
                                    AMV.Images.Red),
                    Green   =>
                      Kernel_Plane (Ks_Image_24_Planar_Color'Class (Element),
                                    AMV.Images.Green),
                    Blue    =>
                      Kernel_Plane (Ks_Image_24_Planar_Color'Class (Element),
                                    AMV.Images.Blue));
         else
            return (Grey_8 => null, Grey_16 => null, Red => null,
                    Green => null, Blue => null);
         end if;
      end;
   end Kernel_Handles;

end AMV.Images.Kernel_Images;
