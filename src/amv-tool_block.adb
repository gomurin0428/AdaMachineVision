pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Kernels;

package body AMV.Tool_Block is

   use type AMV.Kernels.Int32;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   function Code (Value_Type : Ks_Tool_Block_Terminal_Type) return Int32 is
     (Int32 (Ks_Tool_Block_Terminal_Type'Pos (Value_Type)));
   --  The kernel's type code (the declaration order).

   Flags : constant array (Boolean) of Int32 :=
     [False => AMV.Kernels.False_Value, True => AMV.Kernels.True_Value];

   function No_Object return Object_Value;
   --  A value with no object (every component at its default). A function
   --  with a default-initialized object rather than a constant aggregate:
   --  gnatprove 16.1 stops with a bug box (Storage_Error) on a library-level
   --  constant initialized with a box aggregate (others => <>) of a record
   --  with an indefinite holder component (AdaCore/spark2014#84).

   function No_Object return Object_Value is
      Empty : Object_Value;
   begin
      return Empty;
   end No_Object;

   ---------------------------------------------------------------------
   --  The kernel handle
   ---------------------------------------------------------------------

   overriding procedure Adjust (Item : in out Terminals_Handle) is
      Source : constant KG.Ks_Tool_Block_Terminals := Item.Handle;
      Status : Ks_Status;
   begin
      --  The copy shares the source's handle until it has its own; it
      --  must not keep it if the duplicate cannot be made.
      Item.Handle := null;
      KG.Terminals_Duplicate (Source, Item.Handle, Status);
      Check (Status);
   end Adjust;

   overriding procedure Finalize (Item : in out Terminals_Handle) is
   begin
      KG.Terminals_Destroy (Item.Handle);
   end Finalize;

   procedure Write_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Terminals_Handle) is
   begin
      raise Program_Error
        with "AMV.Tool_Block: terminals are not stored in streams";
   end Write_Handle;

   procedure Read_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Terminals_Handle) is
   begin
      raise Program_Error
        with "AMV.Tool_Block: terminals are not stored in streams";
   end Read_Handle;

   ---------------------------------------------------------------------
   --  Queries
   ---------------------------------------------------------------------

   function Count (Terminals : Ks_Tool_Block_Terminal_Collection)
      return Natural
   is
      Value  : Int32;
      Status : Ks_Status;
   begin
      KG.Terminals_Count (Terminals.Kernel.Handle, Value, Status);
      Check (Status);
      return Natural (Value);
   end Count;

   function Index_Of
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Integer
   is
      Index  : Int32;
      Status : Ks_Status;
   begin
      KG.Terminals_Index_Of (Terminals.Kernel.Handle, KG.To_Text (Name),
                             Index, Status);
      Check (Status);
      return Integer (Index);
   end Index_Of;

   function Contains
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Boolean
   is (Index_Of (Terminals, Name) /= KG.No_Index);

   function Name_Of
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Index     : Natural) return String
   is
      Text   : KG.Ks_Tool_Text;
      Status : Ks_Status;
   begin
      KG.Terminals_Name (Terminals.Kernel.Handle, Int32 (Index), Text,
                         Status);
      Check (Status);
      return KG.To_String (Text);
   end Name_Of;

   function Value_Type
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Ks_Tool_Block_Terminal_Type
   is
      Value  : Int32;
      Status : Ks_Status;
   begin
      KG.Terminals_Value_Type (Terminals.Kernel.Handle, KG.To_Text (Name),
                               Value, Status);
      Check (Status);
      return Ks_Tool_Block_Terminal_Type'Val (Value);
   end Value_Type;

   function Has_Value
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Boolean
   is
      Value  : Int32;
      Status : Ks_Status;
   begin
      KG.Terminals_Has_Value (Terminals.Kernel.Handle, KG.To_Text (Name),
                              Value, Status);
      Check (Status);
      return Value = AMV.Kernels.True_Value;
   end Has_Value;

   ---------------------------------------------------------------------
   --  Adding and removing
   ---------------------------------------------------------------------

   procedure Add
     (Terminals  : in out Ks_Tool_Block_Terminal_Collection;
      Name       : String;
      Value_Type : Ks_Tool_Block_Terminal_Type)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Add (Terminals.Kernel.Handle, KG.To_Text (Name),
                        Code (Value_Type), Status);
      Check (Status);
      Terminals.Objects.Append (No_Object);
   end Add;

   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : Real)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Add_Real (Terminals.Kernel.Handle, KG.To_Text (Name),
                             Value, Status);
      Check (Status);
      Terminals.Objects.Append (No_Object);
   end Add;

   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : Long_Long_Integer)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Add_Integer (Terminals.Kernel.Handle, KG.To_Text (Name),
                                AMV.Kernels.Int64 (Value), Status);
      Check (Status);
      Terminals.Objects.Append (No_Object);
   end Add;

   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : Boolean)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Add_Boolean (Terminals.Kernel.Handle, KG.To_Text (Name),
                                Flags (Value), Status);
      Check (Status);
      Terminals.Objects.Append (No_Object);
   end Add;

   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : String)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Add_String (Terminals.Kernel.Handle, KG.To_Text (Name),
                               KG.To_Text (Value), Status);
      Check (Status);
      Terminals.Objects.Append (No_Object);
   end Add;

   procedure Add_Object
     (Terminals  : in out Ks_Tool_Block_Terminal_Collection;
      Name       : String;
      Value_Type : Ks_Tool_Block_Terminal_Type;
      Value      : Object_Value);
   --  Appends an object terminal holding Value.

   procedure Add_Object
     (Terminals  : in out Ks_Tool_Block_Terminal_Collection;
      Name       : String;
      Value_Type : Ks_Tool_Block_Terminal_Type;
      Value      : Object_Value)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Add_Object (Terminals.Kernel.Handle, KG.To_Text (Name),
                               Code (Value_Type), Status);
      Check (Status);
      Terminals.Objects.Append (Value);
   end Add_Object;

   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Images.Ks_Image_8_Grey)
   is
      Object : Object_Value;
   begin
      Object.Image := AMV.Images.Image_Holders.To_Holder (Value);
      Add_Object (Terminals, Name, Image_8_Grey_Type, Object);
   end Add;

   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Images.Ks_Image_16_Grey)
   is
      Object : Object_Value;
   begin
      Object.Image := AMV.Images.Image_Holders.To_Holder (Value);
      Add_Object (Terminals, Name, Image_16_Grey_Type, Object);
   end Add;

   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Transforms.Ks_Transform_2D_Linear)
   is
      Object : Object_Value;
   begin
      Object.Transform := Value;
      Add_Object (Terminals, Name, Transform_Type, Object);
   end Add;

   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Shapes.Ks_Shape'Class)
   is
      Object : Object_Value;
   begin
      Object.Shape := Shape_Holders.To_Holder (Value);
      Add_Object (Terminals, Name, Shape_Type, Object);
   end Add;

   procedure Insert
     (Terminals  : in out Ks_Tool_Block_Terminal_Collection;
      Index      : Natural;
      Name       : String;
      Value_Type : Ks_Tool_Block_Terminal_Type)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Insert (Terminals.Kernel.Handle, Int32 (Index),
                           KG.To_Text (Name), Code (Value_Type), Status);
      Check (Status);
      Terminals.Objects.Insert (Index, No_Object);
   end Insert;

   procedure Remove
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String)
   is
      Index  : Int32;
      Status : Ks_Status;
   begin
      KG.Terminals_Remove (Terminals.Kernel.Handle, KG.To_Text (Name), Index,
                           Status);
      Check (Status);
      Terminals.Objects.Delete (Natural (Index));
   end Remove;

   procedure Remove_At
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Index     : Natural)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Remove_At (Terminals.Kernel.Handle, Int32 (Index),
                              Status);
      Check (Status);
      Terminals.Objects.Delete (Index);
   end Remove_At;

   procedure Move
     (Terminals  : in out Ks_Tool_Block_Terminal_Collection;
      From_Index : Natural;
      To_Index   : Natural)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Move (Terminals.Kernel.Handle, Int32 (From_Index),
                         Int32 (To_Index), Status);
      Check (Status);
      declare
         Moved : constant Object_Value :=
           Terminals.Objects.Element (From_Index);
      begin
         Terminals.Objects.Delete (From_Index);
         Terminals.Objects.Insert (To_Index, Moved);
      end;
   end Move;

   procedure Clear (Terminals : in out Ks_Tool_Block_Terminal_Collection) is
      Status : Ks_Status;
   begin
      KG.Terminals_Clear (Terminals.Kernel.Handle, Status);
      Check (Status);
      Terminals.Objects.Clear;
   end Clear;

   ---------------------------------------------------------------------
   --  Values
   ---------------------------------------------------------------------

   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : Real)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Set_Real (Terminals.Kernel.Handle, KG.To_Text (Name),
                             Value, Status);
      Check (Status);
   end Set;

   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : Long_Long_Integer)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Set_Integer (Terminals.Kernel.Handle, KG.To_Text (Name),
                                AMV.Kernels.Int64 (Value), Status);
      Check (Status);
   end Set;

   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : Boolean)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Set_Boolean (Terminals.Kernel.Handle, KG.To_Text (Name),
                                Flags (Value), Status);
      Check (Status);
   end Set;

   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : String)
   is
      Status : Ks_Status;
   begin
      KG.Terminals_Set_String (Terminals.Kernel.Handle, KG.To_Text (Name),
                               KG.To_Text (Value), Status);
      Check (Status);
   end Set;

   function Set_Index
     (Terminals  : in out Ks_Tool_Block_Terminal_Collection;
      Name       : String;
      Value_Type : Ks_Tool_Block_Terminal_Type) return Natural;
   --  The kernel's check before an object value of the terminal Name is
   --  stored (which marks the terminal as having a value): the index
   --  where the value is kept.

   function Set_Index
     (Terminals  : in out Ks_Tool_Block_Terminal_Collection;
      Name       : String;
      Value_Type : Ks_Tool_Block_Terminal_Type) return Natural
   is
      Index  : Int32;
      Status : Ks_Status;
   begin
      KG.Terminals_Set_Object (Terminals.Kernel.Handle, KG.To_Text (Name),
                               Code (Value_Type), Index, Status);
      Check (Status);
      return Natural (Index);
   end Set_Index;

   function Get_Index
     (Terminals  : Ks_Tool_Block_Terminal_Collection;
      Name       : String;
      Value_Type : Ks_Tool_Block_Terminal_Type) return Natural;
   --  The kernel's check before an object value of the terminal Name is
   --  read: the index where the value is kept.

   function Get_Index
     (Terminals  : Ks_Tool_Block_Terminal_Collection;
      Name       : String;
      Value_Type : Ks_Tool_Block_Terminal_Type) return Natural
   is
      Index  : Int32;
      Status : Ks_Status;
   begin
      KG.Terminals_Get_Object (Terminals.Kernel.Handle, KG.To_Text (Name),
                               Code (Value_Type), Index, Status);
      Check (Status);
      return Natural (Index);
   end Get_Index;

   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Images.Ks_Image_8_Grey)
   is
      Index : constant Natural :=
        Set_Index (Terminals, Name, Image_8_Grey_Type);
   begin
      Terminals.Objects (Index).Image :=
        AMV.Images.Image_Holders.To_Holder (Value);
   end Set;

   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Images.Ks_Image_16_Grey)
   is
      Index : constant Natural :=
        Set_Index (Terminals, Name, Image_16_Grey_Type);
   begin
      Terminals.Objects (Index).Image :=
        AMV.Images.Image_Holders.To_Holder (Value);
   end Set;

   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Transforms.Ks_Transform_2D_Linear)
   is
      Index : constant Natural :=
        Set_Index (Terminals, Name, Transform_Type);
   begin
      Terminals.Objects (Index).Transform := Value;
   end Set;

   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Shapes.Ks_Shape'Class)
   is
      Index : constant Natural :=
        Set_Index (Terminals, Name, Shape_Type);
   begin
      Terminals.Objects (Index).Shape := Shape_Holders.To_Holder (Value);
   end Set;

   function Get_Real
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Real
   is
      Value  : Real;
      Status : Ks_Status;
   begin
      KG.Terminals_Get_Real (Terminals.Kernel.Handle, KG.To_Text (Name),
                             Value, Status);
      Check (Status);
      return Value;
   end Get_Real;

   function Get_Integer
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Long_Long_Integer
   is
      Value  : AMV.Kernels.Int64;
      Status : Ks_Status;
   begin
      KG.Terminals_Get_Integer (Terminals.Kernel.Handle, KG.To_Text (Name),
                                Value, Status);
      Check (Status);
      return Long_Long_Integer (Value);
   end Get_Integer;

   function Get_Boolean
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Boolean
   is
      Value  : Int32;
      Status : Ks_Status;
   begin
      KG.Terminals_Get_Boolean (Terminals.Kernel.Handle, KG.To_Text (Name),
                                Value, Status);
      Check (Status);
      return Value = AMV.Kernels.True_Value;
   end Get_Boolean;

   function Get_String
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return String
   is
      Value  : KG.Ks_Tool_Text;
      Status : Ks_Status;
   begin
      KG.Terminals_Get_String (Terminals.Kernel.Handle, KG.To_Text (Name),
                               Value, Status);
      Check (Status);
      return KG.To_String (Value);
   end Get_String;

   function Get_Image_8_Grey
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return AMV.Images.Ks_Image_8_Grey
   is
      Index : constant Natural :=
        Get_Index (Terminals, Name, Image_8_Grey_Type);
   begin
      return AMV.Images.Ks_Image_8_Grey
               (Terminals.Objects (Index).Image.Element);
   end Get_Image_8_Grey;

   function Get_Image_16_Grey
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return AMV.Images.Ks_Image_16_Grey
   is
      Index : constant Natural :=
        Get_Index (Terminals, Name, Image_16_Grey_Type);
   begin
      return AMV.Images.Ks_Image_16_Grey
               (Terminals.Objects (Index).Image.Element);
   end Get_Image_16_Grey;

   function Get_Transform
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return AMV.Transforms.Ks_Transform_2D_Linear
   is
      Index : constant Natural :=
        Get_Index (Terminals, Name, Transform_Type);
   begin
      return Terminals.Objects (Index).Transform;
   end Get_Transform;

   function Get_Shape
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return AMV.Shapes.Ks_Shape'Class
   is
      Index : constant Natural :=
        Get_Index (Terminals, Name, Shape_Type);
   begin
      return Terminals.Objects (Index).Shape.Element;
   end Get_Shape;

end AMV.Tool_Block;
