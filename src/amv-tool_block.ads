--  The tool block: the counterpart of Cognex.VisionPro.ToolBlock.
--  CogToolBlock, a tool group with named input and output terminals.
--
--     Block : AMV.Tool_Block.Ks_Tool_Block;
--     ...
--     Block.Inputs.Add ("Image", Image);         --  an initial value
--     Block.Outputs.Add ("Mean", Real_Type);      --  a type, no value
--     Block.Add (Histogram_Tool'Access);
--     Block.Set_Script (Wire_And_Publish'Access);
--     Block.Run;
--     Mean := Block.Outputs.Get_Real ("Mean");
--
--  Ks_Tool_Block extends AMV.Tool_Group.Ks_Tool_Group (CogToolBlock
--  derives from CogToolGroup's base), so the members (VisionPro's Tools),
--  AbortRunOnToolFailure, the disabled flags, the Script and Run are those
--  of the group and behave as described in AMV.Tool_Group. A block's
--  script receives the block as a Ks_Tool_Group'Class; it views it as the
--  block with Ks_Tool_Block (Group):
--
--     procedure Wire_And_Publish
--       (Group     : in out AMV.Tool_Group.Ks_Tool_Group'Class;
--        Message   : in out Unbounded_String;
--        Result    : in out Ks_Tool_Result_Constants;
--        Run_Tools : out Boolean)
--     is
--        Block : Ks_Tool_Block renames Ks_Tool_Block (Group);
--     begin
--        Histogram_Tool.Input_Image := Block.Inputs.Get_Image_8_Grey
--                                        ("Image");
--        Histogram_Tool.Run;
--        Block.Outputs.Set ("Mean", Mean (Histogram_Tool.Result));
--        Run_Tools := False;
--     end Wire_And_Publish;
--
--  This is what a CogToolBlockAdvancedScript does by overriding GroupRun
--  (ref message, ref result, returning whether the tools still run).
--
--  Terminals. Inputs and Outputs are terminal collections
--  (CogToolBlockTerminalCollection). A terminal (CogToolBlockTerminal)
--  has a name, unique within its collection (1 to Max_Name_Length
--  characters, compared case-sensitively), a value type
--  (Ks_Tool_Block_Terminal_Type, the AMV form of ValueType) and a value.
--  The collection's operations map to VisionPro's as follows:
--
--     Add (new CogToolBlockTerminal (name, value))  Add (Name, Value)
--     Add (new CogToolBlockTerminal (name, type))   Add (Name, Value_Type)
--     Insert (index, terminal)          Insert (Index, Name, Value_Type)
--     Remove (name), RemoveAt, Move, Clear, Count, IndexOf (name),
--     Contains (name)                   the same names
--     Item [index].Name                 Name_Of (Index)
--     Item [name].ValueType             Value_Type (Name)
--     Item [name].Value = v             Set (Name, v)
--     (T) Item [name].Value             Get_Real (Name), Get_Integer,
--                                       Get_Boolean, Get_String,
--                                       Get_Image_8_Grey, Get_Image_16_Grey,
--                                       Get_Transform, Get_Shape
--
--  A terminal added by type alone holds 0.0, 0, False or "" (scalar
--  types) or no value (images, transforms and shapes): Has_Value is False
--  and its Get raises Ks_Bad_Parameter_Exception until a Set gives it one.
--  Get and Set check the type: a terminal of another type or an unknown
--  name raises Ks_Bad_Parameter_Exception with a message naming the
--  terminal, and a failed Set changes nothing. Indices are 0-based;
--  Constraint_Error for one out of range. Ks_Bad_Parameter_Exception for
--  a name that is empty, longer than Max_Name_Length or taken, for a
--  string longer than Max_String_Length, a Real that is not finite, and
--  beyond Max_Terminals terminals.
--
--  Values. Reals, integers (64-bit), Booleans and strings are kept by the
--  kernel (AMV.Kernels.Tool_Group); images (8-bit and 16-bit grey),
--  transforms and shapes (any Ks_Shape'Class) are kept here, next to the
--  kernel's terminal of the same index, after the kernel has accepted the
--  name and the type. Images keep sharing their pixels with the image
--  given (assignment semantics); shapes and transforms are copied.
--
--  Copies. Assigning a block copies its terminals (the image values keep
--  sharing pixels) and shares its members, as AMV.Tool_Group describes.
--  Streams are not provided (a block refers to its tools by access);
--  'Write and 'Read of a block or a terminal collection raise
--  Program_Error.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Containers.Indefinite_Holders;

with AMV.Images;
with AMV.Shapes;
with AMV.Tool_Group;
with AMV.Transforms;

private with Ada.Containers.Vectors;
private with Ada.Finalization;
private with Ada.Streams;
private with AMV.Images.Image_Holders;
private with AMV.Kernels.Tool_Group;

package AMV.Tool_Block is

   Max_Terminals     : constant := 128;
   --  The most terminals a collection holds.
   Max_Name_Length   : constant := 256;
   --  The longest terminal name (characters).
   Max_String_Length : constant := 1024;
   --  The longest string value (characters).

   type Ks_Tool_Block_Terminal_Type is
     (Real_Type, Integer_Type, Boolean_Type, String_Type,
      Image_8_Grey_Type, Image_16_Grey_Type, Transform_Type, Shape_Type);
   --  The value type of a terminal (AMV's form of the .NET types of
   --  ValueType: Double, Int64, Boolean, String, CogImage8Grey,
   --  CogImage16Grey, CogTransform2DLinear, ICogShape).

   package Shape_Holders is new Ada.Containers.Indefinite_Holders
     (AMV.Shapes.Ks_Shape'Class, AMV.Shapes."=");
   --  An optional shape of any type.

   ---------------------------------------------------------------------
   --  CogToolBlockTerminalCollection
   ---------------------------------------------------------------------

   type Ks_Tool_Block_Terminal_Collection is tagged private;
   --  Empty by default.

   function Count (Terminals : Ks_Tool_Block_Terminal_Collection)
      return Natural;

   function Index_Of
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Integer;
   --  The index of the terminal Name, -1 when there is none.

   function Contains
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Boolean;

   function Name_Of
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Index     : Natural) return String;
   --  Item [Index].Name.

   function Value_Type
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Ks_Tool_Block_Terminal_Type;
   --  Item [Name].ValueType.

   function Has_Value
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Boolean;
   --  False for an image, transform or shape terminal that was never
   --  given a value; True otherwise.

   procedure Add
     (Terminals  : in out Ks_Tool_Block_Terminal_Collection;
      Name       : String;
      Value_Type : Ks_Tool_Block_Terminal_Type);
   --  Appends a terminal of Value_Type with the default value (see above).

   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : Real);
   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : Long_Long_Integer);
   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : Boolean);
   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : String);
   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Images.Ks_Image_8_Grey);
   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Images.Ks_Image_16_Grey);
   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Transforms.Ks_Transform_2D_Linear);
   procedure Add
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Shapes.Ks_Shape'Class);
   --  Appends a terminal whose type is that of Value, holding Value.

   procedure Insert
     (Terminals  : in out Ks_Tool_Block_Terminal_Collection;
      Index      : Natural;
      Name       : String;
      Value_Type : Ks_Tool_Block_Terminal_Type);
   --  Inserts a terminal of Value_Type with the default value at Index
   --  (0 .. Count); the later ones move up by one.

   procedure Remove
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String);
   --  Removes the terminal Name (Ks_Bad_Parameter_Exception when there is
   --  none).

   procedure Remove_At
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Index     : Natural);

   procedure Move
     (Terminals  : in out Ks_Tool_Block_Terminal_Collection;
      From_Index : Natural;
      To_Index   : Natural);
   --  The terminal at From_Index moves to To_Index (both below Count),
   --  those between move by one.

   procedure Clear (Terminals : in out Ks_Tool_Block_Terminal_Collection);

   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : Real);
   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : Long_Long_Integer);
   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : Boolean);
   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : String);
   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Images.Ks_Image_8_Grey);
   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Images.Ks_Image_16_Grey);
   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Transforms.Ks_Transform_2D_Linear);
   procedure Set
     (Terminals : in out Ks_Tool_Block_Terminal_Collection;
      Name      : String;
      Value     : AMV.Shapes.Ks_Shape'Class);
   --  Item [Name].Value := Value. The terminal must have the type of
   --  Value.

   function Get_Real
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Real;
   function Get_Integer
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Long_Long_Integer;
   function Get_Boolean
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return Boolean;
   function Get_String
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return String;
   function Get_Image_8_Grey
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return AMV.Images.Ks_Image_8_Grey;
   function Get_Image_16_Grey
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return AMV.Images.Ks_Image_16_Grey;
   function Get_Transform
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return AMV.Transforms.Ks_Transform_2D_Linear;
   function Get_Shape
     (Terminals : Ks_Tool_Block_Terminal_Collection;
      Name      : String) return AMV.Shapes.Ks_Shape'Class;
   --  Item [Name].Value: the value of the terminal Name, which must have
   --  the type in the function's name (and, for an object type, a value).
   --  An image shares its pixels with the terminal's.

   ---------------------------------------------------------------------
   --  CogToolBlock
   ---------------------------------------------------------------------

   type Ks_Tool_Block is new AMV.Tool_Group.Ks_Tool_Group with record
      Inputs  : Ks_Tool_Block_Terminal_Collection;
      Outputs : Ks_Tool_Block_Terminal_Collection;
   end record;
   --  Inputs and Outputs are for the user and the script; Run neither
   --  reads nor clears them.

   subtype Ks_Tool_Block_Script is AMV.Tool_Group.Ks_Tool_Group_Script;
   --  A block's script (see above).

private

   package KG renames AMV.Kernels.Tool_Group;

   type Object_Value is record
      Image     : AMV.Images.Image_Holders.Holder;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear;
      Shape     : Shape_Holders.Holder;
   end record;
   --  The value of an image, transform or shape terminal (only the
   --  component of the terminal's type is used).

   package Object_Vectors is new Ada.Containers.Vectors
     (Index_Type => Natural, Element_Type => Object_Value);

   type Terminals_Handle is new Ada.Finalization.Controlled with record
      Handle : KG.Ks_Tool_Block_Terminals;
   end record;
   --  Owns the kernel's collection; copies duplicate it.

   overriding procedure Adjust (Item : in out Terminals_Handle);
   overriding procedure Finalize (Item : in out Terminals_Handle);

   procedure Write_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Terminals_Handle);
   procedure Read_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Terminals_Handle);
   --  Both raise Program_Error (terminals are not stored in streams).

   for Terminals_Handle'Write use Write_Handle;
   for Terminals_Handle'Read use Read_Handle;

   type Ks_Tool_Block_Terminal_Collection is tagged record
      Kernel  : Terminals_Handle;
      Objects : Object_Vectors.Vector;
      --  One entry per terminal, at the kernel's index.
   end record;

end AMV.Tool_Block;
