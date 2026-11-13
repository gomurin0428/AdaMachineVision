--  Kernel of AMV.Coordinate_Spaces: coordinate space trees, the
--  counterpart of CogCoordinateSpaceTree.
--
--  A tree holds the root space "@" and up to Max_Spaces - 1 other spaces.
--  Every space other than the root has a parent and a Parent_From_Child
--  transform that maps coordinates expressed in the space to coordinates
--  expressed in its parent (the direction of VisionPro's AddSpace
--  argument parentFromNew). Spaces are named by path from the root,
--  components separated by '\': a space "Fixture" added under "@" is
--  called "@\Fixture". A component is a non-empty string without '\' that
--  is not "@", "#" or "."; names are case sensitive. The meaning of every
--  operation is documented in AMV.Coordinate_Spaces.
--
--  Representation. A tree is a C-compatible record without pointers (C:
--  ks_coordinate_space_tree, 19,976 bytes): the number of spaces Count and
--  an array of Max_Spaces entries, of which entries 0 .. Count - 1 are in
--  use. Entry 0 is the root (name "@", no parent, identity transform).
--  The entries are kept sorted by full name in lexical order (that of
--  Ada's String "<"); since a parent's name is a prefix of its children's
--  names, every parent comes before its children. Valid_Tree states this
--  invariant. A C caller may hand any record to an entry point, so every
--  entry point checks Valid_Tree on its tree first and fails with
--  Bad_Parameter ("Tree is not a valid coordinate space tree") otherwise;
--  an entry point that changes a tree leaves it valid when it succeeds and
--  unchanged when it fails.
--
--  Names cross the C ABI as Ks_Space_Name: Length characters in Text. A
--  name argument whose Length exceeds Max_Name_Length (256) is accepted,
--  holds its first 256 characters in Text, and names no space; a negative
--  Length is a malformed name. Names returned by the kernel always fit and
--  have NUL characters after their Length characters.
--
--  Enumerations cross the C ABI as Int32 codes (the Add_Space_* and
--  Pathname_* constants below), Booleans as False_Value / True_Value;
--  every entry point checks its codes before anything else but the tree
--  and fails with Bad_Parameter, naming the argument, for any other value.
--
--  Failures. A malformed or unknown space name gives
--  Image_Bad_Selected_Space_Name with a message that names the operation
--  and the name ("Get_Transform: no space named ""@\X"""); Space_Exists
--  and Verify_Name never fail on a name. Transforms are bounded as in
--  AMV.Kernels.Transforms (every entry within 1.0E150).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Transforms;

package AMV.Kernels.Coordinate_Spaces with SPARK_Mode, Pure is

   package KT renames AMV.Kernels.Transforms;

   ---------------------------------------------------------------------
   --  Limits and names
   ---------------------------------------------------------------------

   Max_Spaces : constant := 64;
   --  Spaces in a tree, the root included. VisionPro trees are small; a
   --  fixed bound keeps the tree a plain C record.

   Max_Name_Length : constant := 256;
   --  Characters in a full space name.

   No_Parent : constant := -1;
   --  The parent index of the root.

   Root_Character     : constant Character := '@';
   Pixel_Character    : constant Character := '#';
   Selected_Character : constant Character := '.';
   Separator          : constant Character := '\';

   type Name_Text is array (1 .. Max_Name_Length) of Character
     with Convention => C;

   type Ks_Space_Name is record
      Length : Int32     := 0;
      Text   : Name_Text := [others => ASCII.NUL];
   end record
     with Convention => C, Size => 260 * 8;

   for Ks_Space_Name use record
      Length at 0 range 0 .. 31;
      Text   at 4 range 0 .. 8 * Max_Name_Length - 1;
   end record;
   --  A space name: Text (1 .. Length). C: ks_space_name (260 bytes). The
   --  text is not NUL-terminated when it has 256 characters.

   function Fits (Name : Ks_Space_Name) return Boolean is
     (Name.Length in 0 .. Max_Name_Length);
   --  Name holds all its characters (False for a name longer than
   --  Max_Name_Length, as To_Space_Name makes them, and for a negative
   --  Length).

   ---------------------------------------------------------------------
   --  Codes
   ---------------------------------------------------------------------

   Add_Space_Duplicate_Is_Error : constant Int32 := 0;
   Add_Space_Replace_Duplicate  : constant Int32 := 1;
   Add_Space_Ignore_Duplicate   : constant Int32 := 2;
   --  Duplicate_Handling of Add_Space (C: KS_ADD_SPACE_*), the positions
   --  of AMV.Coordinate_Spaces.Ks_Add_Space_Constants (VisionPro's
   --  CogAddSpaceConstants has the same values).

   subtype Add_Space_Code is Int32
     range Add_Space_Duplicate_Is_Error .. Add_Space_Ignore_Duplicate;

   Pathname_None    : constant Int32 := 0;
   Pathname_Full    : constant Int32 := 1;
   Pathname_Partial : constant Int32 := 2;
   --  Pathname_Format (C: KS_SPACE_TREE_PATHNAME_*), the positions of
   --  AMV.Coordinate_Spaces.Ks_Space_Tree_Pathname_Constants (VisionPro's
   --  CogSpaceTreePathnameConstants has the same values). A name is given
   --  as its last component (None; "@" for the root), as its full name
   --  (Full), or (Partial), when it is below the space named by the
   --  operation's Space_Name argument, as its path relative to that space
   --  ("B\C" for "@\A\B\C" below "@\A"), and otherwise (the space itself,
   --  its parent) as its full name.

   subtype Pathname_Code is Int32 range Pathname_None .. Pathname_Partial;

   ---------------------------------------------------------------------
   --  The tree
   ---------------------------------------------------------------------

   type Ks_Coordinate_Space is record
      Name              : Ks_Space_Name;
      Parent            : Int32 := No_Parent;
      Parent_From_Child : KT.Ks_Transform_2D_Linear;
   end record
     with Convention => C, Size => 312 * 8;

   for Ks_Coordinate_Space use record
      Name              at 0   range 0 .. 260 * 8 - 1;
      Parent            at 260 range 0 .. 31;
      Parent_From_Child at 264 range 0 .. 48 * 8 - 1;
   end record;
   --  One space: its full name, the index of its parent and the transform
   --  from its coordinates to its parent's, exactly as it was given. C:
   --  ks_coordinate_space (312 bytes).

   subtype Space_Index is Int32 range 0 .. Max_Spaces - 1;

   type Space_Array is array (Space_Index) of Ks_Coordinate_Space
     with Convention => C;

   type Ks_Coordinate_Space_Tree is record
      Count  : Int32 := 1;
      Spaces : Space_Array :=
        [0      => (Name              =>
                      (Length => 1,
                       Text   => [Root_Character, others => ASCII.NUL]),
                    Parent            => No_Parent,
                    Parent_From_Child => <>),
         others => <>];
   end record
     with Convention => C, Size => 19_976 * 8;

   for Ks_Coordinate_Space_Tree use record
      Count  at 0 range 0 .. 31;
      Spaces at 8 range 0 .. 19_968 * 8 - 1;
   end record;
   --  C: ks_coordinate_space_tree (19,976 bytes). The default value is the
   --  tree that holds only the root.

   function Valid_Tree (Tree : Ks_Coordinate_Space_Tree) return Boolean;
   --  The invariant of a tree:
   --
   --  * Count is in 1 .. Max_Spaces;
   --  * entry 0 is the root: name "@", parent No_Parent, identity
   --    transform;
   --  * every other entry I below Count has a parent index in 0 .. I - 1,
   --    a name equal to its parent's name followed by '\' and a valid
   --    component (so at most Max_Name_Length characters), a name greater
   --    than the name of entry I - 1 in lexical order, and a transform
   --    within the bound of AMV.Kernels.Transforms.
   --
   --  Entries from Count on are ignored. An expression function (completed
   --  in the private part), usable in contracts.

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   --  Every entry point first checks Valid_Tree (Tree) and fails with
   --  Bad_Parameter otherwise. Space names are checked as described above
   --  and in AMV.Coordinate_Spaces.

   procedure Init
     (Tree   : out Ks_Coordinate_Space_Tree;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_init",
     Post => Valid (Status) and then Succeeded (Status)
             and then Valid_Tree (Tree) and then Tree.Count = 1;
   --  The tree that holds only the root "@". Never fails.

   procedure Add_Space
     (Tree               : in out Ks_Coordinate_Space_Tree;
      Parent_Space_Name  : Ks_Space_Name;
      New_Space_Name     : Ks_Space_Name;
      Parent_From_New    : KT.Ks_Transform_2D_Linear;
      Duplicate_Handling : Int32;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_add_space",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Transform_Singular
             and then (if Succeeded (Status) then Valid_Tree (Tree)
                       else Tree = Tree'Old);
   --  Adds the space Parent_Space_Name & '\' & New_Space_Name, whose
   --  coordinates Parent_From_New maps into the parent's; it is stored
   --  exactly as given. When that space exists already, Duplicate_Handling
   --  decides: Add_Space_Duplicate_Is_Error fails (Bad_Parameter),
   --  Add_Space_Replace_Duplicate replaces only its transform (keeping its
   --  descendants), Add_Space_Ignore_Duplicate changes nothing (and
   --  succeeds). Failures, in the order checked: Duplicate_Handling is not
   --  one of the codes (Bad_Parameter); the parent does not exist
   --  (Image_Bad_Selected_Space_Name); New_Space_Name is not a valid
   --  component (Image_Bad_Selected_Space_Name; for a component longer
   --  than 256 characters only its first 256 are checked); Parent_From_New
   --  is not within the bound (Bad_Parameter) or not invertible within it
   --  (Transform_Singular); the full name would be longer than
   --  Max_Name_Length (Bad_Parameter); the space exists and
   --  Duplicate_Handling is Add_Space_Duplicate_Is_Error (Bad_Parameter);
   --  the space is new and the tree already holds Max_Spaces spaces
   --  (Bad_Parameter).

   procedure Change_Transform
     (Tree                  : in out Ks_Coordinate_Space_Tree;
      Child_Space_Name      : Ks_Space_Name;
      New_Parent_From_Child : KT.Ks_Transform_2D_Linear;
      Status                : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_change_transform",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Transform_Singular
             and then (if Succeeded (Status)
                       then Valid_Tree (Tree)
                            and then Tree.Count = Tree.Count'Old
                       else Tree = Tree'Old);
   --  Replaces the transform of the space, stored exactly as given.
   --  Bad_Parameter for the root and for a transform beyond the bound;
   --  Transform_Singular when it is not invertible within the bound.

   procedure Delete_Subtree
     (Tree       : in out Ks_Coordinate_Space_Tree;
      Space_Name : Ks_Space_Name;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_delete_subtree",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
             and then (if Succeeded (Status)
                       then Valid_Tree (Tree)
                            and then Tree.Count < Tree.Count'Old
                       else Tree = Tree'Old);
   --  Removes the space and all its descendants. Bad_Parameter for the
   --  root.

   procedure Clear
     (Tree   : in out Ks_Coordinate_Space_Tree;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_clear",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Tree (Tree) and then Tree.Count = 1
                       else Tree = Tree'Old);
   --  Removes every space except the root.

   procedure Space_Exists
     (Tree       : Ks_Coordinate_Space_Tree;
      Space_Name : Ks_Space_Name;
      Result     : out Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_space_exists",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result in False_Value | True_Value;
   --  True_Value for "@" and every space of the tree, False_Value for any
   --  other name (malformed ones included).

   procedure Space_Count
     (Tree   : Ks_Coordinate_Space_Tree;
      Result : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_space_count",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Result in 1 .. Max_Spaces else Result = 0);
   --  The number of spaces, the root included.

   procedure Space_Name
     (Tree   : Ks_Coordinate_Space_Tree;
      Index  : Int32;
      Result : out Ks_Space_Name;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_space_name",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Index_Out_Of_Range
             and then Fits (Result);
   --  The full name of the Index-th space (0-based) in lexical order;
   --  index 0 is "@". Index_Out_Of_Range unless Index is in
   --  0 .. Count - 1. The name is empty when the call fails.

   procedure Root_Name
     (Tree   : Ks_Coordinate_Space_Tree;
      Result : out Ks_Space_Name;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_root_name",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Fits (Result)
             and then (if Succeeded (Status) then Result.Length = 1);
   --  The name of the root, "@". The name is empty when the call fails.

   procedure Parent_Name
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : Ks_Space_Name;
      Pathname_Format : Int32;
      Result          : out Ks_Space_Name;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_parent_name",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
             and then Fits (Result);
   --  The name of the parent in Pathname_Format (Partial gives the full
   --  name, since the parent is not below the space); the empty name for
   --  the root, and when the call fails.

   procedure Child_Names_Count
     (Tree       : Ks_Coordinate_Space_Tree;
      Space_Name : Ks_Space_Name;
      Result     : out Int32;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_child_names_count",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
             and then Result in 0 .. Max_Spaces
             and then (if not Succeeded (Status) then Result = 0);
   --  The number of children (immediate descendants) of the space.

   procedure Child_Name
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : Ks_Space_Name;
      Pathname_Format : Int32;
      Index           : Int32;
      Result          : out Ks_Space_Name;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_child_name",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Index_Out_Of_Range
             and then Fits (Result);
   --  The name of the Index-th child (0-based, in lexical order of the
   --  full names) of the space, in Pathname_Format (Partial: the
   --  component). Index_Out_Of_Range unless Index is in
   --  0 .. Child_Names_Count - 1. The name is empty when the call fails.

   procedure All_Child_Names_Count
     (Tree          : Ks_Coordinate_Space_Tree;
      Space_Name    : Ks_Space_Name;
      Children_Only : Int32;
      Result        : out Int32;
      Status        : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_all_child_names_count",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
             and then Result in 0 .. Max_Spaces
             and then (if not Succeeded (Status) then Result = 0);
   --  The number of descendants of the space at any depth, plus one for
   --  the space itself when Children_Only is False_Value. Bad_Parameter
   --  unless Children_Only is False_Value or True_Value.

   procedure All_Child_Name
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : Ks_Space_Name;
      Pathname_Format : Int32;
      Children_Only   : Int32;
      Index           : Int32;
      Result          : out Ks_Space_Name;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_all_child_name",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Index_Out_Of_Range
             and then Fits (Result);
   --  The name of the Index-th of those spaces (0-based, in lexical order
   --  of the full names, so the space itself, when it is included, comes
   --  first) in Pathname_Format. Index_Out_Of_Range unless Index is in
   --  0 .. All_Child_Names_Count - 1. The name is empty when the call
   --  fails.

   procedure Verify_Name
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : Ks_Space_Name;
      Pathname_Format : Int32;
      Result          : out Int32;
      Found_Name      : out Ks_Space_Name;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_verify_name",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result in False_Value | True_Value
             and then Fits (Found_Name)
             and then (if Result = False_Value
                       then Found_Name.Length = 0);
   --  True_Value and the space's name in Pathname_Format (Partial gives
   --  the full name) when Space_Name is the full name of a space of the
   --  tree; False_Value and the empty name for any other name (malformed
   --  ones included), as for Space_Exists.

   procedure Parent_From_Child_Transform
     (Tree       : Ks_Coordinate_Space_Tree;
      Space_Name : Ks_Space_Name;
      Result     : out KT.Ks_Transform_2D_Linear;
      Status     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_parent_from_child_transform",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
             and then (if Succeeded (Status) then KT.Bounded (Result));
   --  The transform stored for the space, exactly as it was given; the
   --  identity for the root.

   procedure Get_Transform
     (Tree            : Ks_Coordinate_Space_Tree;
      To_Space_Name   : Ks_Space_Name;
      From_Space_Name : Ks_Space_Name;
      Result          : out KT.Ks_Transform_2D_Linear;
      Status          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_coordinate_space_tree_get_transform",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Transform_Singular
             and then (if Succeeded (Status) then KT.Bounded (Result));
   --  The transform that maps coordinates in From_Space_Name to coordinates
   --  in To_Space_Name: the inverse of Root_From_To composed with
   --  Root_From_From (Root_From_From itself when To_Space_Name is "@"),
   --  where Root_From_X composes the Parent_From_Child transforms on the
   --  path from X up to the root, grouped from X up:
   --  P_Top * (... * (P_Parent * (P_X * Identity))), P_Top being the
   --  transform of the space just below the root on that path and each
   --  product computed as by ks_transform_2d_linear_compose. The same name
   --  twice gives exactly the identity. Transform_Singular when Root_From_To
   --  is not invertible within the bound; Bad_Parameter when a composition
   --  would leave it. Result is the identity when the call fails.

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   function To_Space_Name (Source : String) return Ks_Space_Name
   with
     Post => To_Space_Name'Result.Length = Int32 (Source'Length)
             and then (for all J in 1 .. Integer'Min (Source'Length,
                                                      Max_Name_Length)
                       => To_Space_Name'Result.Text (J)
                            = Source (Source'First + (J - 1)));
   --  Source as a space name, whatever its bounds (they may end at
   --  Integer'Last). A Source longer than Max_Name_Length does not fit
   --  (Fits is False): its first 256 characters are kept and its length
   --  tells the entry points that it names no space.

   function To_String (Name : Ks_Space_Name) return String
   with
     Pre  => Fits (Name),
     Post => To_String'Result'First = 1
             and then To_String'Result'Length = Integer (Name.Length)
             and then (for all J in 1 .. Integer (Name.Length)
                       => To_String'Result (J) = Name.Text (J));
   --  The characters of Name, indexed from 1.

   function Same_Tree (Left, Right : Ks_Coordinate_Space_Tree) return Boolean
   with
     Pre  => Left.Count in 1 .. Max_Spaces
             and then Right.Count in 1 .. Max_Spaces,
     Post => (if Same_Tree'Result then Left.Count = Right.Count);
   --  The trees hold the same spaces (names, parents and transforms, the
   --  transforms compared entry by entry with "=").

   --  Stream support. The Ada API stores a tree as Stream_Code, the number
   --  of spaces (the root included), and every space other than the root
   --  in Space_Name order (its name, then its Parent_From_Child
   --  transform); see AMV.Coordinate_Spaces. Reading rebuilds the tree
   --  through Add_Read_Space.

   Stream_Code : constant Int32 := 16#4B53_5400#;
   --  "KST" followed by the layout version 0.

   procedure Check_Read_Header
     (Code, Count : Int32;
      Status      : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status)
                       then Code = Stream_Code
                            and then Count in 1 .. Max_Spaces);
   --  Image_File unless Code is Stream_Code and Count can be the number of
   --  spaces of a tree.

   procedure Add_Read_Space
     (Tree              : in out Ks_Coordinate_Space_Tree;
      Name              : Ks_Space_Name;
      Parent_From_Child : KT.Ks_Transform_2D_Linear;
      Status            : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status) then Valid_Tree (Tree)
                       else Tree = Tree'Old);
   --  Adds the space with the full name Name, read from a stream: its
   --  parent must be in Tree already and the space must not be. Any
   --  problem (a malformed name, a missing parent, a repeated name, a
   --  bad transform, a full tree, an invalid Tree) gives Image_File with a
   --  message that says what is wrong.

   procedure Add_Read_Space
     (Operation         : String;
      Tree              : in out Ks_Coordinate_Space_Tree;
      Name              : Ks_Space_Name;
      Parent_From_Child : KT.Ks_Transform_2D_Linear;
      Status            : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Image_File
             and then (if Succeeded (Status) then Valid_Tree (Tree)
                       else Tree = Tree'Old);
   --  The same, with messages that start with Operation (the stream
   --  attribute reading the tree, such as "Ks_Image_8_Grey'Read"); the
   --  procedure above uses "Ks_Coordinate_Space_Tree'Read".

private

   function Valid_Component
     (Name        : Ks_Space_Name;
      First, Last : Integer) return Boolean
   is
     (First <= Last
      and then (for all J in First .. Last => Name.Text (J) /= Separator)
      and then (if First = Last
                then Name.Text (First)
                       not in Root_Character | Pixel_Character
                            | Selected_Character))
   with Pre => First in 1 .. Max_Name_Length
               and then Last <= Max_Name_Length;
   --  Name.Text (First .. Last) is a valid path component.

   function Has_Prefix
     (Name, Prefix : Ks_Space_Name;
      Length       : Integer) return Boolean
   is
     (for all J in 1 .. Length => Name.Text (J) = Prefix.Text (J))
   with Pre => Length <= Max_Name_Length;
   --  The first Length characters of the texts agree.

   function Extends (Name, Parent : Ks_Space_Name) return Boolean is
     (Parent.Length in 1 .. Max_Name_Length - 2
      and then Name.Length in Parent.Length + 2 .. Max_Name_Length
      and then Has_Prefix (Name, Parent, Integer (Parent.Length))
      and then Name.Text (Integer (Parent.Length) + 1) = Separator
      and then Valid_Component
                 (Name, Integer (Parent.Length) + 2, Integer (Name.Length)));
   --  Name is Parent followed by '\' and a valid component.

   function Is_Below (Name, Base : Ks_Space_Name) return Boolean is
     (Base.Length in 1 .. Max_Name_Length - 2
      and then Name.Length in Base.Length + 2 .. Max_Name_Length
      and then Has_Prefix (Name, Base, Integer (Base.Length))
      and then Name.Text (Integer (Base.Length) + 1) = Separator);
   --  Name starts with Base followed by '\' and at least one more
   --  character: in a valid tree, Name is a descendant of Base.

   function Shorter_Length (Left, Right : Ks_Space_Name) return Natural is
     (Natural (Int32'Min (Left.Length, Right.Length)))
   with Pre  => Fits (Left) and then Fits (Right),
        Post => Shorter_Length'Result <= Max_Name_Length;

   function First_Difference (Left, Right : Ks_Space_Name) return Positive
   with
     Pre  => Fits (Left) and then Fits (Right),
     Post => First_Difference'Result <= Shorter_Length (Left, Right) + 1
             and then Has_Prefix (Left, Right, First_Difference'Result - 1)
             and then (if First_Difference'Result
                            <= Shorter_Length (Left, Right)
                       then Left.Text (First_Difference'Result)
                              /= Right.Text (First_Difference'Result));
   --  The first position at which the names differ, or one past the
   --  shorter name when it is a prefix of the other.

   function Less_At
     (Left, Right : Ks_Space_Name;
      K           : Positive) return Boolean
   is
     (if K <= Shorter_Length (Left, Right)
      then Left.Text (K) < Right.Text (K)
      else K = Shorter_Length (Left, Right) + 1
           and then Left.Length < Right.Length)
   with Pre => Fits (Left) and then Fits (Right);
   --  The comparison at K, the first difference, that decides Left < Right.

   function Less (Left, Right : Ks_Space_Name) return Boolean is
     (Fits (Left) and then Fits (Right)
      and then Less_At (Left, Right, First_Difference (Left, Right)));
   --  Both names fit and Left < Right in lexical order (Ada's String "<"
   --  on the names). Total (no precondition): the provers cannot use the
   --  definition of Valid_Tree when it calls a function that has one.

   function Same_Name (Left, Right : Ks_Space_Name) return Boolean is
     (Left.Length = Right.Length
      and then Fits (Left)
      and then Has_Prefix (Left, Right, Integer (Left.Length)));

   function Is_Root_Name (Name : Ks_Space_Name) return Boolean is
     (Name.Length = 1 and then Name.Text (1) = Root_Character);

   function Is_Identity (T : KT.Ks_Transform_2D_Linear) return Boolean is
     (T.A = 1.0 and then T.B = 0.0 and then T.C = 0.0 and then T.D = 1.0
      and then T.Translation_X = 0.0 and then T.Translation_Y = 0.0);

   function Valid_Root (Tree : Ks_Coordinate_Space_Tree) return Boolean is
     (Is_Root_Name (Tree.Spaces (0).Name)
      and then Tree.Spaces (0).Parent = No_Parent
      and then Is_Identity (Tree.Spaces (0).Parent_From_Child));

   function Valid_Link
     (Space, Previous, Parent : Ks_Coordinate_Space) return Boolean
   is
     (Extends (Space.Name, Parent.Name)
      and then Less (Previous.Name, Space.Name)
      and then KT.Bounded (Space.Parent_From_Child));
   --  A space other than the root is consistent with its parent and with
   --  the entry before it.

   function Valid_Tree (Tree : Ks_Coordinate_Space_Tree) return Boolean is
     (Tree.Count in 1 .. Max_Spaces
      and then Valid_Root (Tree)
      and then (for all I in 1 .. Tree.Count - 1
                => Tree.Spaces (I).Parent in 0 .. I - 1
                   and then Valid_Link
                              (Tree.Spaces (I), Tree.Spaces (I - 1),
                               Tree.Spaces (Tree.Spaces (I).Parent))));
   --  The quantified property is stated on the entries, not through a
   --  function of the whole tree, so that the provers can instantiate it
   --  for any entry mentioned and carry it across updates of other entries.

end AMV.Kernels.Coordinate_Spaces;
