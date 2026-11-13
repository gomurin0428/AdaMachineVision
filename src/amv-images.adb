pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.IO_Exceptions;
with Ada.Unchecked_Conversion;
with Ada.Unchecked_Deallocation;
with System.Atomic_Operations.Integer_Arithmetic;

with AMV.Checks;
with AMV.Coordinate_Spaces.Kernel_Trees;

package body AMV.Images is

   package KI renames AMV.Kernels.Images;
   package KC renames AMV.Kernels.Coordinate_Spaces;
   package KT renames AMV.Kernels.Transforms;
   package Trees renames AMV.Coordinate_Spaces.Kernel_Trees;

   use type KI.Ks_Image_8_Grey;
   use type KI.Ks_Image_16_Grey;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;
   subtype U32 is Interfaces.Unsigned_32;

   procedure Check (Status : AMV.Kernels.Ks_Status) renames AMV.Checks.Check;

   package Counters is new System.Atomic_Operations.Integer_Arithmetic
     (Atomic_Type => Atomic_Count);

   procedure Free is new Ada.Unchecked_Deallocation
     (Pixel_Box_8, Pixel_Box_8_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Pixel_Box_16, Pixel_Box_16_Access);

   ---------------------------------------------------------------------
   --  Values passed to the kernel
   ---------------------------------------------------------------------

   function Name (Text : String) return KC.Ks_Space_Name
     renames KC.To_Space_Name;

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

   function From_Kernel
     (Transform : KT.Ks_Transform_2D_Linear)
      return AMV.Transforms.Ks_Transform_2D_Linear is
     (AMV.Transforms.Create
        (Transform.A, Transform.B, Transform.C, Transform.D,
         Transform.Translation_X, Transform.Translation_Y));

   ---------------------------------------------------------------------
   --  Pixel boxes
   ---------------------------------------------------------------------

   function Handle (Box : Pixel_Box_8_Access) return KI.Ks_Image_8_Grey is
     (if Box = null then null else Box.Handle);
   --  The kernel's handle; null (no pixels) without a box.

   function Handle (Box : Pixel_Box_16_Access) return KI.Ks_Image_16_Grey is
     (if Box = null then null else Box.Handle);

   function Boxed (Owned : KI.Ks_Image_8_Grey) return Pixel_Box_8_Access;
   --  A box that takes over a handle the caller owns; none for null. The
   --  handle is destroyed if the box cannot be allocated.

   function Boxed (Owned : KI.Ks_Image_8_Grey) return Pixel_Box_8_Access is
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
   end Boxed;

   function Boxed (Owned : KI.Ks_Image_16_Grey) return Pixel_Box_16_Access;

   function Boxed (Owned : KI.Ks_Image_16_Grey) return Pixel_Box_16_Access
   is
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
   end Boxed;

   procedure Retain (Box : Pixel_Box_8_Access);
   --  Counts one more user of Box (no effect for null).

   procedure Retain (Box : Pixel_Box_8_Access) is
   begin
      if Box /= null then
         Counters.Atomic_Add (Box.References, 1);
      end if;
   end Retain;

   procedure Retain (Box : Pixel_Box_16_Access);

   procedure Retain (Box : Pixel_Box_16_Access) is
   begin
      if Box /= null then
         Counters.Atomic_Add (Box.References, 1);
      end if;
   end Retain;

   procedure Release (Box : in out Pixel_Box_8_Access);
   --  Counts one user less, destroys the handle and frees the box with its
   --  last user, and sets Box to null. No effect for null, so releasing
   --  twice is harmless.

   procedure Release (Box : in out Pixel_Box_8_Access) is
      Status : Ks_Status;
   begin
      if Box /= null then
         if Counters.Atomic_Fetch_And_Subtract (Box.References, 1) = 1 then
            KI.Destroy (Box.Handle, Status);
            Free (Box);
            Check (Status);
         end if;
         Box := null;
      end if;
   end Release;

   procedure Release (Box : in out Pixel_Box_16_Access);

   procedure Release (Box : in out Pixel_Box_16_Access) is
      Status : Ks_Status;
   begin
      if Box /= null then
         if Counters.Atomic_Fetch_And_Subtract (Box.References, 1) = 1 then
            KI.Destroy (Box.Handle, Status);
            Free (Box);
            Check (Status);
         end if;
         Box := null;
      end if;
   end Release;

   procedure Release (Planes : in out Plane_Buffers);
   --  Releases every plane.

   procedure Release (Planes : in out Plane_Buffers) is
   begin
      Release (Planes (Red));
      Release (Planes (Green));
      Release (Planes (Blue));
   end Release;

   procedure Raise_Failure (Status : Ks_Status)
   with No_Return;
   --  Raises the exception for Status, the failure of an entry point
   --  called because its lean variant (KI.Try_*) reported one.

   procedure Raise_Failure (Status : Ks_Status) is
   begin
      Check (Status);
      raise Program_Error with "the kernel reported no failure";
   end Raise_Failure;

   ---------------------------------------------------------------------
   --  ICogImage
   ---------------------------------------------------------------------

   function Effective_Selection (Spaces : Space_State)
      return KC.Ks_Space_Name;
   --  The stored selection as it reads: "@" when it names a space that has
   --  since been removed from the tree.

   function Effective_Selection (Spaces : Space_State)
      return KC.Ks_Space_Name
   is
      Result : KC.Ks_Space_Name;
      Status : Ks_Status;
   begin
      KI.Selected_Space_Name
        (Trees.View (Spaces.Tree).all, Spaces.Selected, Result, Status);
      Check (Status);
      return Result;
   end Effective_Selection;

   procedure Settle_Selection (Spaces : in out Space_State);
   --  Stores Effective_Selection: a stored name whose space has left the
   --  tree becomes "@", so that it cannot come back when a space of the
   --  same name is added later. Called wherever the package has write
   --  access to an image whose tree may have changed in place.

   procedure Settle_Selection (Spaces : in out Space_State) is
   begin
      Spaces.Selected := Effective_Selection (Spaces);
   end Settle_Selection;

   overriding procedure Finalize (Guard : in out Selection_Guard) is
   begin
      if Guard.Spaces /= null then
         Settle_Selection (Guard.Spaces.all);
         Guard.Spaces := null;
      end if;
   end Finalize;

   function Width (Image : Ks_Image) return Natural is (Image.Width);

   function Height (Image : Ks_Image) return Natural is (Image.Height);

   function Allocated (Image : Ks_Image) return Boolean is
     (Image.Width > 0 and then Image.Height > 0);

   function Selected_Space_Name (Image : Ks_Image) return String is
     (KC.To_String (Effective_Selection (Image.Spaces)));

   procedure Set_Selected_Space_Name
     (Image : in out Ks_Image; Space_Name : String)
   is
      Status : Ks_Status;
   begin
      KI.Set_Selected_Space_Name
        (Trees.View (Image.Spaces.Tree).all, Image.Spaces.Selected,
         Name (Space_Name), Status);
      Check (Status);
   end Set_Selected_Space_Name;

   function Pixel_From_Root_Transform
     (Image : Ks_Image) return AMV.Transforms.Ks_Transform_2D_Linear is
     (From_Kernel (Image.Spaces.Pixel_From_Root));

   procedure Set_Pixel_From_Root_Transform
     (Image     : in out Ks_Image;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
   is
      Status : Ks_Status;
   begin
      KI.Set_Pixel_From_Root_Transform
        (Image.Spaces.Pixel_From_Root, To_Kernel (Transform), Status);
      Check (Status);
   end Set_Pixel_From_Root_Transform;

   function Coordinate_Space_Tree
     (Image : aliased in out Ks_Image)
      return Ks_Coordinate_Space_Tree_Reference is
   begin
      --  Settle a removal made through an earlier reference before the
      --  tree can change again, and once more when this reference ends.
      Settle_Selection (Image.Spaces);
      return
        (Element => Image.Spaces.Tree'Access,
         Guard   =>
           (Ada.Finalization.Limited_Controlled with
            Spaces => Image.Spaces'Unchecked_Access));
   end Coordinate_Space_Tree;

   function Get_Coordinate_Space_Tree
     (Image : Ks_Image) return AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree
   is (Image.Spaces.Tree);

   procedure Set_Coordinate_Space_Tree
     (Image : in out Ks_Image;
      Tree  : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree)
   is
      Status : Ks_Status;
   begin
      --  The selection is settled against the old tree before Tree (which
      --  may be the image's own tree) replaces it, so that a stored name
      --  whose space was removed in place is not revived by a new tree
      --  that has it.
      KI.Selection_For_New_Tree
        (Trees.View (Image.Spaces.Tree).all, Image.Spaces.Selected,
         Trees.View (Tree).all, Status);
      Check (Status);
      Image.Spaces.Tree := Tree;
   end Set_Coordinate_Space_Tree;

   function Resolve_Space_Name
     (Image : Ks_Image; Space_Name : String) return String
   is
      Result : KC.Ks_Space_Name;
      Status : Ks_Status;
   begin
      KI.Resolve_Space_Name
        (Trees.View (Image.Spaces.Tree).all, Image.Spaces.Selected,
         Name (Space_Name), Result, Status);
      Check (Status);
      return KC.To_String (Result);
   end Resolve_Space_Name;

   function Get_Transform
     (Image           : Ks_Image;
      To_Space_Name   : String;
      From_Space_Name : String) return AMV.Transforms.Ks_Transform_2D_Linear
   is
      Result : KT.Ks_Transform_2D_Linear;
      Status : Ks_Status;
   begin
      KI.Get_Transform
        (Trees.View (Image.Spaces.Tree).all, Image.Spaces.Selected,
         Image.Spaces.Pixel_From_Root, Name (To_Space_Name),
         Name (From_Space_Name), Result, Status);
      Check (Status);
      return From_Kernel (Result);
   end Get_Transform;

   ---------------------------------------------------------------------
   --  CogImage8Grey
   ---------------------------------------------------------------------

   overriding procedure Adjust (Image : in out Ks_Image_8_Grey) is
   begin
      Retain (Image.Buffer);
      Settle_Selection (Image.Spaces);
   end Adjust;

   overriding procedure Finalize (Image : in out Ks_Image_8_Grey) is
   begin
      Release (Image.Buffer);
      Image.Width := 0;
      Image.Height := 0;
   end Finalize;

   function Create
     (Width, Height : Positive; Value : Grey_8 := 0) return Ks_Image_8_Grey
   is
      Status : Ks_Status;
   begin
      return Result : Ks_Image_8_Grey do
         --  Owned by Result at once, so that a failure frees it.
         Result.Buffer := new Pixel_Box_8;
         KI.Create (Int32 (Width), Int32 (Height), Value,
                    Result.Buffer.Handle, Status);
         Check (Status);
         Result.Width := Width;
         Result.Height := Height;
      end return;
   end Create;

   procedure Allocate
     (Image : in out Ks_Image_8_Grey; Width, Height : Positive)
   is
      Fresh : constant Ks_Image_8_Grey := Create (Width, Height);
   begin
      --  Image becomes one more user of Fresh's buffer, which Image keeps
      --  alone when Fresh ends.
      Retain (Fresh.Buffer);
      Release (Image.Buffer);
      Image.Buffer := Fresh.Buffer;
      Image.Width := Width;
      Image.Height := Height;
   end Allocate;

   --  Get_Pixel and Set_Pixel are called once per pixel by the packages
   --  built on this one, so they use the kernel's lean variants, which
   --  build no status, and call the entry point only to report a failure.

   procedure Get_Pixel_Failed (Image : KI.Ks_Image_8_Grey; X, Y : Natural)
   with No_Return;

   procedure Get_Pixel_Failed (Image : KI.Ks_Image_8_Grey; X, Y : Natural)
   is
      Value  : Grey_8;
      Status : Ks_Status;
   begin
      KI.Get_Pixel (Image, Int32 (X), Int32 (Y), Value, Status);
      Raise_Failure (Status);
   end Get_Pixel_Failed;

   procedure Set_Pixel_Failed
     (Image : KI.Ks_Image_8_Grey; X, Y : Natural; Value : Grey_8)
   with No_Return;

   procedure Set_Pixel_Failed
     (Image : KI.Ks_Image_8_Grey; X, Y : Natural; Value : Grey_8)
   is
      Status : Ks_Status;
   begin
      KI.Set_Pixel (Image, Int32 (X), Int32 (Y), Value, Status);
      Raise_Failure (Status);
   end Set_Pixel_Failed;

   function Get_Pixel
     (Image : Ks_Image_8_Grey; X, Y : Natural) return Grey_8
   is
      Value : Grey_8;
      Done  : Boolean;
   begin
      KI.Try_Get_Pixel (Handle (Image.Buffer), Int32 (X), Int32 (Y), Value,
                        Done);
      if not Done then
         Get_Pixel_Failed (Handle (Image.Buffer), X, Y);
      end if;
      return Value;
   end Get_Pixel;

   procedure Set_Pixel
     (Image : in out Ks_Image_8_Grey; X, Y : Natural; Value : Grey_8)
   is
      Done : Boolean;
   begin
      KI.Try_Set_Pixel (Handle (Image.Buffer), Int32 (X), Int32 (Y), Value,
                        Done);
      if not Done then
         Set_Pixel_Failed (Handle (Image.Buffer), X, Y, Value);
      end if;
   end Set_Pixel;

   procedure Fill (Image : in out Ks_Image_8_Grey; Value : Grey_8) is
      Status : Ks_Status;
   begin
      KI.Fill (Handle (Image.Buffer), Value, Status);
      Check (Status);
   end Fill;

   procedure Get_Row
     (Image : Ks_Image_8_Grey; Y : Natural; Row : out Grey_8_Row)
   is
      Status : Ks_Status;
   begin
      KI.Get_Row (Handle (Image.Buffer), Int32 (Y), KI.Grey_8_Row (Row),
                  Status);
      Check (Status);
   end Get_Row;

   procedure Set_Row
     (Image : in out Ks_Image_8_Grey; Y : Natural; Row : Grey_8_Row)
   is
      Status : Ks_Status;
   begin
      KI.Set_Row (Handle (Image.Buffer), Int32 (Y), KI.Grey_8_Row (Row),
                  Status);
      Check (Status);
   end Set_Row;

   function To_Matrix (Image : Ks_Image_8_Grey) return Grey_8_Matrix is
      Last_Row, Last_Column : Natural;
      Status                : Ks_Status;
   begin
      KI.Matrix_Bounds (Handle (Image.Buffer), Last_Row, Last_Column,
                        Status);
      Check (Status);
      return Result : Grey_8_Matrix (0 .. Last_Row, 0 .. Last_Column) do
         KI.Get_Matrix (Handle (Image.Buffer), KI.Grey_8_Matrix (Result),
                        Status);
         Check (Status);
      end return;
   end To_Matrix;

   function From_Matrix (Pixels : Grey_8_Matrix) return Ks_Image_8_Grey is
      Status : Ks_Status;
   begin
      return Result : Ks_Image_8_Grey do
         Result.Buffer := new Pixel_Box_8;
         KI.Create_From_Matrix
           (KI.Grey_8_Matrix (Pixels), Result.Buffer.Handle, Status);
         Check (Status);
         Result.Width := Pixels'Length (2);
         Result.Height := Pixels'Length (1);
      end return;
   end From_Matrix;

   function Copy
     (Image : Ks_Image_8_Grey;
      Mode  : Ks_Image_Copy_Mode_Constants := Copy_Pixels)
      return Ks_Image_8_Grey
   is
      Status : Ks_Status;
   begin
      case Mode is
         when Share_Pixels =>
            return Image;
         when Copy_Pixels =>
            return Result : Ks_Image_8_Grey do
               Result.Spaces := Image.Spaces;
               Settle_Selection (Result.Spaces);
               if Image.Buffer /= null then
                  Result.Buffer := new Pixel_Box_8;
                  KI.Duplicate (Image.Buffer.Handle, Result.Buffer.Handle,
                                Status);
                  Check (Status);
                  Result.Width := Image.Width;
                  Result.Height := Image.Height;
               end if;
            end return;
         when No_Pixels =>
            return Result : Ks_Image_8_Grey do
               Result.Spaces := Image.Spaces;
               Settle_Selection (Result.Spaces);
            end return;
      end case;
   end Copy;

   function Shares_Pixels (Left, Right : Ks_Image_8_Grey) return Boolean is
     (Left.Buffer /= null and then Left.Buffer = Right.Buffer);

   ---------------------------------------------------------------------
   --  CogImage16Grey
   ---------------------------------------------------------------------

   overriding procedure Adjust (Image : in out Ks_Image_16_Grey) is
   begin
      Retain (Image.Buffer);
      Settle_Selection (Image.Spaces);
   end Adjust;

   overriding procedure Finalize (Image : in out Ks_Image_16_Grey) is
   begin
      Release (Image.Buffer);
      Image.Width := 0;
      Image.Height := 0;
   end Finalize;

   function Create
     (Width, Height : Positive; Value : Grey_16 := 0)
      return Ks_Image_16_Grey
   is
      Status : Ks_Status;
   begin
      return Result : Ks_Image_16_Grey do
         Result.Buffer := new Pixel_Box_16;
         KI.Create (Int32 (Width), Int32 (Height), Value,
                    Result.Buffer.Handle, Status);
         Check (Status);
         Result.Width := Width;
         Result.Height := Height;
      end return;
   end Create;

   procedure Allocate
     (Image : in out Ks_Image_16_Grey; Width, Height : Positive)
   is
      Fresh : constant Ks_Image_16_Grey := Create (Width, Height);
   begin
      Retain (Fresh.Buffer);
      Release (Image.Buffer);
      Image.Buffer := Fresh.Buffer;
      Image.Width := Width;
      Image.Height := Height;
   end Allocate;

   procedure Get_Pixel_Failed (Image : KI.Ks_Image_16_Grey; X, Y : Natural)
   with No_Return;

   procedure Get_Pixel_Failed (Image : KI.Ks_Image_16_Grey; X, Y : Natural)
   is
      Value  : Grey_16;
      Status : Ks_Status;
   begin
      KI.Get_Pixel (Image, Int32 (X), Int32 (Y), Value, Status);
      Raise_Failure (Status);
   end Get_Pixel_Failed;

   procedure Set_Pixel_Failed
     (Image : KI.Ks_Image_16_Grey; X, Y : Natural; Value : Grey_16)
   with No_Return;

   procedure Set_Pixel_Failed
     (Image : KI.Ks_Image_16_Grey; X, Y : Natural; Value : Grey_16)
   is
      Status : Ks_Status;
   begin
      KI.Set_Pixel (Image, Int32 (X), Int32 (Y), Value, Status);
      Raise_Failure (Status);
   end Set_Pixel_Failed;

   function Get_Pixel
     (Image : Ks_Image_16_Grey; X, Y : Natural) return Grey_16
   is
      Value : Grey_16;
      Done  : Boolean;
   begin
      KI.Try_Get_Pixel (Handle (Image.Buffer), Int32 (X), Int32 (Y), Value,
                        Done);
      if not Done then
         Get_Pixel_Failed (Handle (Image.Buffer), X, Y);
      end if;
      return Value;
   end Get_Pixel;

   procedure Set_Pixel
     (Image : in out Ks_Image_16_Grey; X, Y : Natural; Value : Grey_16)
   is
      Done : Boolean;
   begin
      KI.Try_Set_Pixel (Handle (Image.Buffer), Int32 (X), Int32 (Y), Value,
                        Done);
      if not Done then
         Set_Pixel_Failed (Handle (Image.Buffer), X, Y, Value);
      end if;
   end Set_Pixel;

   procedure Fill (Image : in out Ks_Image_16_Grey; Value : Grey_16) is
      Status : Ks_Status;
   begin
      KI.Fill (Handle (Image.Buffer), Value, Status);
      Check (Status);
   end Fill;

   function Copy
     (Image : Ks_Image_16_Grey;
      Mode  : Ks_Image_Copy_Mode_Constants := Copy_Pixels)
      return Ks_Image_16_Grey
   is
      Status : Ks_Status;
   begin
      case Mode is
         when Share_Pixels =>
            return Image;
         when Copy_Pixels =>
            return Result : Ks_Image_16_Grey do
               Result.Spaces := Image.Spaces;
               Settle_Selection (Result.Spaces);
               if Image.Buffer /= null then
                  Result.Buffer := new Pixel_Box_16;
                  KI.Duplicate (Image.Buffer.Handle, Result.Buffer.Handle,
                                Status);
                  Check (Status);
                  Result.Width := Image.Width;
                  Result.Height := Image.Height;
               end if;
            end return;
         when No_Pixels =>
            return Result : Ks_Image_16_Grey do
               Result.Spaces := Image.Spaces;
               Settle_Selection (Result.Spaces);
            end return;
      end case;
   end Copy;

   function Shares_Pixels (Left, Right : Ks_Image_16_Grey) return Boolean is
     (Left.Buffer /= null and then Left.Buffer = Right.Buffer);

   ---------------------------------------------------------------------
   --  CogImage24PlanarColor
   ---------------------------------------------------------------------

   overriding procedure Adjust (Image : in out Ks_Image_24_Planar_Color) is
   begin
      Retain (Image.Planes (Red));
      Retain (Image.Planes (Green));
      Retain (Image.Planes (Blue));
      Settle_Selection (Image.Spaces);
   end Adjust;

   overriding procedure Finalize
     (Image : in out Ks_Image_24_Planar_Color) is
   begin
      Release (Image.Planes);
      Image.Width := 0;
      Image.Height := 0;
   end Finalize;

   procedure New_Boxes (Planes : out Plane_Buffers);
   --  Three boxes for the handles the kernel is about to create.

   procedure New_Boxes (Planes : out Plane_Buffers) is
   begin
      Planes := [others => null];
      Planes (Red) := new Pixel_Box_8;
      Planes (Green) := new Pixel_Box_8;
      Planes (Blue) := new Pixel_Box_8;
   end New_Boxes;

   function Create
     (Width, Height : Positive; Red, Green, Blue : Grey_8 := 0)
      return Ks_Image_24_Planar_Color
   is
      Status : Ks_Status;
   begin
      return Result : Ks_Image_24_Planar_Color do
         --  Owned by Result at once, so that a failure frees them.
         New_Boxes (Result.Planes);
         KI.Create_Color
           (Int32 (Width), Int32 (Height), Red, Green, Blue,
            Result.Planes (AMV.Images.Red).Handle,
            Result.Planes (AMV.Images.Green).Handle,
            Result.Planes (AMV.Images.Blue).Handle, Status);
         Check (Status);
         Result.Width := Width;
         Result.Height := Height;
      end return;
   end Create;

   procedure Allocate
     (Image : in out Ks_Image_24_Planar_Color; Width, Height : Positive)
   is
      Fresh : constant Ks_Image_24_Planar_Color := Create (Width, Height);
   begin
      Retain (Fresh.Planes (Red));
      Retain (Fresh.Planes (Green));
      Retain (Fresh.Planes (Blue));
      Release (Image.Planes);
      Image.Planes := Fresh.Planes;
      Image.Width := Width;
      Image.Height := Height;
   end Allocate;

   procedure Get_Pixel_Failed (Planes : Plane_Buffers; X, Y : Natural)
   with No_Return;

   procedure Get_Pixel_Failed (Planes : Plane_Buffers; X, Y : Natural) is
      Red, Green, Blue : Grey_8;
      Status           : Ks_Status;
   begin
      KI.Get_Pixel_Color
        (Handle (Planes (AMV.Images.Red)),
         Handle (Planes (AMV.Images.Green)),
         Handle (Planes (AMV.Images.Blue)),
         Int32 (X), Int32 (Y), Red, Green, Blue, Status);
      Raise_Failure (Status);
   end Get_Pixel_Failed;

   procedure Set_Pixel_Failed
     (Planes           : Plane_Buffers;
      X, Y             : Natural;
      Red, Green, Blue : Grey_8)
   with No_Return;

   procedure Set_Pixel_Failed
     (Planes           : Plane_Buffers;
      X, Y             : Natural;
      Red, Green, Blue : Grey_8)
   is
      Status : Ks_Status;
   begin
      KI.Set_Pixel_Color
        (Handle (Planes (AMV.Images.Red)),
         Handle (Planes (AMV.Images.Green)),
         Handle (Planes (AMV.Images.Blue)),
         Int32 (X), Int32 (Y), Red, Green, Blue, Status);
      Raise_Failure (Status);
   end Set_Pixel_Failed;

   procedure Get_Pixel
     (Image            : Ks_Image_24_Planar_Color;
      X, Y             : Natural;
      Red, Green, Blue : out Grey_8)
   is
      Done : Boolean;
   begin
      KI.Try_Get_Pixel_Color
        (Handle (Image.Planes (AMV.Images.Red)),
         Handle (Image.Planes (AMV.Images.Green)),
         Handle (Image.Planes (AMV.Images.Blue)),
         Int32 (X), Int32 (Y), Red, Green, Blue, Done);
      if not Done then
         Get_Pixel_Failed (Image.Planes, X, Y);
      end if;
   end Get_Pixel;

   procedure Set_Pixel
     (Image            : in out Ks_Image_24_Planar_Color;
      X, Y             : Natural;
      Red, Green, Blue : Grey_8)
   is
      Done : Boolean;
   begin
      KI.Try_Set_Pixel_Color
        (Handle (Image.Planes (AMV.Images.Red)),
         Handle (Image.Planes (AMV.Images.Green)),
         Handle (Image.Planes (AMV.Images.Blue)),
         Int32 (X), Int32 (Y), Red, Green, Blue, Done);
      if not Done then
         Set_Pixel_Failed (Image.Planes, X, Y, Red, Green, Blue);
      end if;
   end Set_Pixel;

   function Get_Plane
     (Image : Ks_Image_24_Planar_Color'Class;
      Plane : Ks_Image_Plane_Constants) return Ks_Image_8_Grey is
   begin
      return Result : Ks_Image_8_Grey do
         Result.Spaces := Image.Spaces;
         Settle_Selection (Result.Spaces);
         if Image.Planes (Plane) /= null then
            --  The result becomes one more user of the plane's box.
            Retain (Image.Planes (Plane));
            Result.Buffer := Image.Planes (Plane);
            Result.Width := Image.Width;
            Result.Height := Image.Height;
         end if;
      end return;
   end Get_Plane;

   procedure Set_Plane
     (Image  : in out Ks_Image_24_Planar_Color'Class;
      Plane  : Ks_Image_Plane_Constants;
      Pixels : Ks_Image_8_Grey'Class)
   is
      Status : Ks_Status;
   begin
      --  The pixels are copied into the plane's handle, so the change is
      --  visible through every image sharing that plane.
      KI.Set_Plane
        (Handle (Image.Planes (Plane)), Handle (Pixels.Buffer), Status);
      Check (Status);
   end Set_Plane;

   function Copy
     (Image : Ks_Image_24_Planar_Color;
      Mode  : Ks_Image_Copy_Mode_Constants := Copy_Pixels)
      return Ks_Image_24_Planar_Color
   is
      Status : Ks_Status;
   begin
      case Mode is
         when Share_Pixels =>
            return Image;
         when Copy_Pixels =>
            return Result : Ks_Image_24_Planar_Color do
               Result.Spaces := Image.Spaces;
               Settle_Selection (Result.Spaces);
               if Image.Planes (Red) /= null then
                  New_Boxes (Result.Planes);
                  KI.Duplicate_Color
                    (Handle (Image.Planes (Red)),
                     Handle (Image.Planes (Green)),
                     Handle (Image.Planes (Blue)),
                     Result.Planes (Red).Handle,
                     Result.Planes (Green).Handle,
                     Result.Planes (Blue).Handle, Status);
                  Check (Status);
                  Result.Width := Image.Width;
                  Result.Height := Image.Height;
               end if;
            end return;
         when No_Pixels =>
            return Result : Ks_Image_24_Planar_Color do
               Result.Spaces := Image.Spaces;
               Settle_Selection (Result.Spaces);
            end return;
      end case;
   end Copy;

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   --  The kernel checks every field read and converts transforms and
   --  pixels to and from their stream form; this part only moves values
   --  and bytes between the stream and the kernel.

   use Ada.Streams;

   Chunk_Length : constant := 4096;
   --  Pixels are moved through a chunk of this many stream elements.

   subtype Chunk_Elements is Stream_Element_Array (1 .. Chunk_Length);
   subtype Chunk_Bytes is KI.Grey_8_Row (1 .. Chunk_Length);

   function To_Elements is new Ada.Unchecked_Conversion
     (Chunk_Bytes, Chunk_Elements);
   function To_Bytes is new Ada.Unchecked_Conversion
     (Chunk_Elements, Chunk_Bytes);
   --  A stream element is a byte (GNAT); the two arrays have the same
   --  representation.

   procedure Reset_To_Default (Image : in out Ks_Image'Class);
   --  Gives Image (whose pixels are already released) the size and the
   --  coordinate space state of a default image.

   procedure Reset_To_Default (Image : in out Ks_Image'Class) is
      Default : Space_State;
   begin
      Image.Width := 0;
      Image.Height := 0;
      Image.Spaces := Default;
   end Reset_To_Default;

   --  Writing

   procedure Write_Name
     (Stream : not null access Root_Stream_Type'Class;
      Space  : KC.Ks_Space_Name);

   procedure Write_Name
     (Stream : not null access Root_Stream_Type'Class;
      Space  : KC.Ks_Space_Name) is
   begin
      U32'Write (Stream, U32 (Space.Length));
      String'Write (Stream, KC.To_String (Space));
   end Write_Name;

   procedure Write_Transform
     (Stream    : not null access Root_Stream_Type'Class;
      Transform : KT.Ks_Transform_2D_Linear);

   procedure Write_Transform
     (Stream    : not null access Root_Stream_Type'Class;
      Transform : KT.Ks_Transform_2D_Linear) is
   begin
      KI.Transform_Bits'Write (Stream, KI.To_Bits (Transform));
   end Write_Transform;

   procedure Write_Spaces
     (Stream : not null access Root_Stream_Type'Class;
      Spaces : Space_State);
   --  Items 3 to 5 of the layout described in the spec.

   procedure Write_Spaces
     (Stream : not null access Root_Stream_Type'Class;
      Spaces : Space_State)
   is
      Tree      : KC.Ks_Coordinate_Space_Tree renames
        Trees.View (Spaces.Tree).all;
      Count     : U32;
      Space     : KC.Ks_Space_Name;
      Transform : KT.Ks_Transform_2D_Linear;
      Status    : Ks_Status;
   begin
      Write_Transform (Stream, Spaces.Pixel_From_Root);
      KI.Stream_Space_Count (Tree, Count, Status);
      Check (Status);
      U32'Write (Stream, Count);
      --  Space_Name order puts every parent before its children.
      for Index in 1 .. Int32 (Count) loop  --  SHELL: stream I/O, spaces
         KC.Space_Name (Tree, Index, Space, Status);
         Check (Status);
         KC.Parent_From_Child_Transform (Tree, Space, Transform, Status);
         Check (Status);
         Write_Name (Stream, Space);
         Write_Transform (Stream, Transform);
      end loop;  --  SHELL: (the loop above)
      Write_Name (Stream, Effective_Selection (Spaces));
   end Write_Spaces;

   procedure Write_Size
     (Stream        : not null access Root_Stream_Type'Class;
      Code          : U32;
      Width, Height : Natural);

   procedure Write_Size
     (Stream        : not null access Root_Stream_Type'Class;
      Code          : U32;
      Width, Height : Natural) is
   begin
      U32'Write (Stream, Code);
      U32'Write (Stream, U32 (Width));
      U32'Write (Stream, U32 (Height));
   end Write_Size;

   procedure Write_Pixels
     (Stream : not null access Root_Stream_Type'Class;
      Image  : KI.Ks_Image_8_Grey);
   --  Item 6 for an 8-bit image or plane (nothing for null).

   procedure Write_Pixels
     (Stream : not null access Root_Stream_Type'Class;
      Image  : KI.Ks_Image_8_Grey)
   is
      Position : KI.Pixel_Position;
      Bytes    : Chunk_Bytes := [others => 0];
      Length   : Natural;
      Status   : Ks_Status;
   begin
      loop  --  SHELL: stream I/O, one chunk of pixels at a time
         KI.Next_Chunk (Image, Position, Chunk_Length, Length);
         exit when Length = 0;
         KI.Get_Bytes (Image, Position, Bytes (1 .. Length), Status);
         Check (Status);
         Stream_Element_Array'Write
           (Stream, To_Elements (Bytes) (1 .. Stream_Element_Offset (Length)));
      end loop;  --  SHELL: (the loop above)
   end Write_Pixels;

   procedure Write_Pixels
     (Stream : not null access Root_Stream_Type'Class;
      Image  : KI.Ks_Image_16_Grey);
   --  Item 6 for a 16-bit image: two bytes per pixel, the least
   --  significant first (the kernel orders them).

   procedure Write_Pixels
     (Stream : not null access Root_Stream_Type'Class;
      Image  : KI.Ks_Image_16_Grey)
   is
      Position : KI.Pixel_Position;
      Bytes    : Chunk_Bytes := [others => 0];
      Length   : Natural;
      Status   : Ks_Status;
   begin
      loop  --  SHELL: stream I/O, one chunk of pixels at a time
         KI.Next_Chunk (Image, Position, Chunk_Length, Length);
         exit when Length = 0;
         KI.Get_Bytes (Image, Position, Bytes (1 .. Length), Status);
         Check (Status);
         Stream_Element_Array'Write
           (Stream, To_Elements (Bytes) (1 .. Stream_Element_Offset (Length)));
      end loop;  --  SHELL: (the loop above)
   end Write_Pixels;

   --  Reading. A field that fails a kernel check raises
   --  Ks_Image_File_Exception through Check.

   procedure Read_Name
     (Stream : not null access Root_Stream_Type'Class;
      Code   : KI.Stream_Code;
      Space  : out KC.Ks_Space_Name);
   --  A name as Write_Name stores it; its length is checked before the
   --  characters are read.

   procedure Read_Name
     (Stream : not null access Root_Stream_Type'Class;
      Code   : KI.Stream_Code;
      Space  : out KC.Ks_Space_Name)
   is
      Length : U32;
      Count  : Natural;
      Text   : String (1 .. KC.Max_Name_Length) := [others => ' '];
      Status : Ks_Status;
   begin
      U32'Read (Stream, Length);
      KI.Check_Read_Name_Length (Code, Length, Count, Status);
      Check (Status);
      String'Read (Stream, Text (1 .. Count));
      Space := Name (Text (1 .. Count));
   end Read_Name;

   procedure Read_Spaces
     (Stream : not null access Root_Stream_Type'Class;
      Code   : KI.Stream_Code;
      Spaces : in out Space_State);
   --  Items 3 to 5 of the layout into Spaces, which must be a default
   --  Space_State.

   procedure Read_Spaces
     (Stream : not null access Root_Stream_Type'Class;
      Code   : KI.Stream_Code;
      Spaces : in out Space_State)
   is
      Bits   : KI.Transform_Bits;
      Count  : U32;
      Space  : KC.Ks_Space_Name;
      Status : Ks_Status;
   begin
      KI.Transform_Bits'Read (Stream, Bits);
      KI.Read_Pixel_From_Root (Code, Bits, Spaces.Pixel_From_Root, Status);
      Check (Status);
      U32'Read (Stream, Count);
      KI.Check_Read_Space_Count (Code, Count, Status);
      Check (Status);
      for Index in 1 .. Count loop  --  SHELL: stream I/O, every space
         Read_Name (Stream, Code, Space);
         KI.Transform_Bits'Read (Stream, Bits);
         KI.Read_Space
           (Code, Trees.Variable_View (Spaces.Tree).all, Space, Bits,
            Status);
         Check (Status);
      end loop;  --  SHELL: (the loop above)
      Read_Name (Stream, Code, Space);
      KI.Read_Selection
        (Code, Trees.View (Spaces.Tree).all, Space, Spaces.Selected, Status);
      Check (Status);
   end Read_Spaces;

   procedure Read_Size
     (Stream        : not null access Root_Stream_Type'Class;
      Code          : KI.Stream_Code;
      Width, Height : out Int32);
   --  Items 1 (which must be Code) and 2, checked against the limits of
   --  Create before anything is allocated.

   procedure Read_Size
     (Stream        : not null access Root_Stream_Type'Class;
      Code          : KI.Stream_Code;
      Width, Height : out Int32)
   is
      Format, W, H : U32;
      Status       : Ks_Status;
   begin
      U32'Read (Stream, Format);
      KI.Check_Read_Code (Code, Format, Status);
      Check (Status);
      U32'Read (Stream, W);
      U32'Read (Stream, H);
      KI.Check_Read_Size (Code, W, H, Width, Height, Status);
      Check (Status);
   end Read_Size;

   procedure Read_Pixels
     (Stream : not null access Root_Stream_Type'Class;
      Image  : KI.Ks_Image_8_Grey);
   --  Item 6 into an 8-bit image or plane (nothing for null).

   procedure Read_Pixels
     (Stream : not null access Root_Stream_Type'Class;
      Image  : KI.Ks_Image_8_Grey)
   is
      Position : KI.Pixel_Position;
      Elements : Chunk_Elements := [others => 0];
      Length   : Natural;
      Status   : Ks_Status;
   begin
      loop  --  SHELL: stream I/O, one chunk of pixels at a time
         KI.Next_Chunk (Image, Position, Chunk_Length, Length);
         exit when Length = 0;
         Stream_Element_Array'Read
           (Stream, Elements (1 .. Stream_Element_Offset (Length)));
         KI.Put_Bytes
           (Image, Position, To_Bytes (Elements) (1 .. Length), Status);
         Check (Status);
      end loop;  --  SHELL: (the loop above)
   end Read_Pixels;

   procedure Read_Pixels
     (Stream : not null access Root_Stream_Type'Class;
      Image  : KI.Ks_Image_16_Grey);

   procedure Read_Pixels
     (Stream : not null access Root_Stream_Type'Class;
      Image  : KI.Ks_Image_16_Grey)
   is
      Position : KI.Pixel_Position;
      Elements : Chunk_Elements := [others => 0];
      Length   : Natural;
      Status   : Ks_Status;
   begin
      loop  --  SHELL: stream I/O, one chunk of pixels at a time
         KI.Next_Chunk (Image, Position, Chunk_Length, Length);
         exit when Length = 0;
         Stream_Element_Array'Read
           (Stream, Elements (1 .. Stream_Element_Offset (Length)));
         KI.Put_Bytes
           (Image, Position, To_Bytes (Elements) (1 .. Length), Status);
         Check (Status);
      end loop;  --  SHELL: (the loop above)
   end Read_Pixels;

   procedure Stream_Ended (Code : KI.Stream_Code)
   with No_Return;
   --  Raises Ks_Image_File_Exception for a stream that ends before the
   --  image is complete.

   procedure Stream_Ended (Code : KI.Stream_Code) is
      Status : Ks_Status;
   begin
      KI.Stream_Ended (Code, Status);
      Check (Status);
      raise Program_Error with "a kernel failure was not reported";
   end Stream_Ended;

   --  Ks_Image (the coordinate space state only)

   procedure Write_Spaces_Part
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Ks_Image) is
   begin
      U32'Write (Stream, KI.Code_Spaces_Part);
      Write_Spaces (Stream, Item.Spaces);
   end Write_Spaces_Part;

   procedure Read_Spaces_Part
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Image)
   is
      Code   : constant KI.Stream_Code := KI.Code_Spaces_Part;
      Format : U32;
      Spaces : Space_State;
      Status : Ks_Status;
   begin
      U32'Read (Stream, Format);
      KI.Check_Read_Code (Code, Format, Status);
      Check (Status);
      Read_Spaces (Stream, Code, Spaces);
      Item.Spaces := Spaces;
   exception
      when Ada.IO_Exceptions.End_Error =>
         Stream_Ended (Code);
   end Read_Spaces_Part;

   --  Ks_Image_8_Grey

   procedure Write_Grey_8
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Ks_Image_8_Grey) is
   begin
      Write_Size (Stream, KI.Code_Grey_8, Item.Width, Item.Height);
      Write_Spaces (Stream, Item.Spaces);
      Write_Pixels (Stream, Handle (Item.Buffer));
   end Write_Grey_8;

   procedure Read_Grey_8
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Image_8_Grey)
   is
      Code          : constant KI.Stream_Code := KI.Code_Grey_8;
      Width, Height : Int32;
      Spaces        : Space_State;
      Fresh         : KI.Ks_Image_8_Grey;
      Status        : Ks_Status;
   begin
      Release (Item.Buffer);
      Reset_To_Default (Item);
      Read_Size (Stream, Code, Width, Height);
      Read_Spaces (Stream, Code, Spaces);
      --  Only now are the pixels allocated, owned by Item at once so that
      --  a failure below releases them.
      KI.Create_For_Read (Width, Height, Fresh, Status);
      Check (Status);
      Item.Buffer := Boxed (Fresh);
      Read_Pixels (Stream, Handle (Item.Buffer));
      Item.Spaces := Spaces;
      Item.Width := Natural (Width);
      Item.Height := Natural (Height);
   exception
      when Ada.IO_Exceptions.End_Error =>
         Release (Item.Buffer);
         Reset_To_Default (Item);
         Stream_Ended (Code);
      when others =>
         Release (Item.Buffer);
         Reset_To_Default (Item);
         raise;
   end Read_Grey_8;

   --  Ks_Image_16_Grey

   procedure Write_Grey_16
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Ks_Image_16_Grey) is
   begin
      Write_Size (Stream, KI.Code_Grey_16, Item.Width, Item.Height);
      Write_Spaces (Stream, Item.Spaces);
      Write_Pixels (Stream, Handle (Item.Buffer));
   end Write_Grey_16;

   procedure Read_Grey_16
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Image_16_Grey)
   is
      Code          : constant KI.Stream_Code := KI.Code_Grey_16;
      Width, Height : Int32;
      Spaces        : Space_State;
      Fresh         : KI.Ks_Image_16_Grey;
      Status        : Ks_Status;
   begin
      Release (Item.Buffer);
      Reset_To_Default (Item);
      Read_Size (Stream, Code, Width, Height);
      Read_Spaces (Stream, Code, Spaces);
      KI.Create_For_Read (Width, Height, Fresh, Status);
      Check (Status);
      Item.Buffer := Boxed (Fresh);
      Read_Pixels (Stream, Handle (Item.Buffer));
      Item.Spaces := Spaces;
      Item.Width := Natural (Width);
      Item.Height := Natural (Height);
   exception
      when Ada.IO_Exceptions.End_Error =>
         Release (Item.Buffer);
         Reset_To_Default (Item);
         Stream_Ended (Code);
      when others =>
         Release (Item.Buffer);
         Reset_To_Default (Item);
         raise;
   end Read_Grey_16;

   --  Ks_Image_24_Planar_Color

   procedure Write_Colour
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Ks_Image_24_Planar_Color) is
   begin
      Write_Size (Stream, KI.Code_Colour, Item.Width, Item.Height);
      Write_Spaces (Stream, Item.Spaces);
      Write_Pixels (Stream, Handle (Item.Planes (Red)));
      Write_Pixels (Stream, Handle (Item.Planes (Green)));
      Write_Pixels (Stream, Handle (Item.Planes (Blue)));
   end Write_Colour;

   procedure Read_Colour
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Image_24_Planar_Color)
   is
      Code                      : constant KI.Stream_Code := KI.Code_Colour;
      Width, Height             : Int32;
      Spaces                    : Space_State;
      Fresh_R, Fresh_G, Fresh_B : KI.Ks_Image_8_Grey;
      Status                    : Ks_Status;
   begin
      Release (Item.Planes);
      Reset_To_Default (Item);
      Read_Size (Stream, Code, Width, Height);
      Read_Spaces (Stream, Code, Spaces);
      KI.Create_Color_For_Read
        (Width, Height, Fresh_R, Fresh_G, Fresh_B, Status);
      Check (Status);
      Item.Planes := [Boxed (Fresh_R), Boxed (Fresh_G), Boxed (Fresh_B)];
      Read_Pixels (Stream, Handle (Item.Planes (Red)));
      Read_Pixels (Stream, Handle (Item.Planes (Green)));
      Read_Pixels (Stream, Handle (Item.Planes (Blue)));
      Item.Spaces := Spaces;
      Item.Width := Natural (Width);
      Item.Height := Natural (Height);
   exception
      when Ada.IO_Exceptions.End_Error =>
         Release (Item.Planes);
         Reset_To_Default (Item);
         Stream_Ended (Code);
      when others =>
         Release (Item.Planes);
         Reset_To_Default (Item);
         raise;
   end Read_Colour;

end AMV.Images;
