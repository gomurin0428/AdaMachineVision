--  Coordinate space trees: the counterpart of CogCoordinateSpaceTree.
--
--  A tree always contains the root space "@". Every other space has a
--  parent and a Parent_From_Child transform that maps coordinates
--  expressed in the space to coordinates expressed in its parent, as in
--  VisionPro (AddSpace takes it as parentFromNew). The tree stores it
--  exactly as given.
--
--  Spaces are named by path from the root, components separated by '\':
--  a space "Fixture" added under "@" is called "@\Fixture"; a space "Part"
--  added under it is "@\Fixture\Part". Names are case sensitive. A path
--  component is a non-empty string that contains neither '\' nor is equal
--  to "@", "#" or ".".
--
--  Every space name argument is a full name: "@" or a path that starts
--  with "@\". VisionPro also resolves bare and partial names (a last
--  component that is unique in the tree, a path relative to a space);
--  AMV does not implement that lookup yet (FindNames, LookUpName and
--  ResolvePartialName are not implemented either), so such a name is
--  simply not in the tree.
--
--  The special names "#" (pixel space) and "." (selected space) belong to
--  an image, not to a tree; AMV.Images resolves them. Every subprogram here
--  that takes a space name raises
--  Ks_Image_Bad_Selected_Space_Name_Exception for a name that is not in
--  the tree (VisionPro: CogSpaceTreeNameNotInTreeException, or
--  CogSpaceTreeInvalidNameSyntaxException for a malformed name), except
--  Space_Exists and Verify_Name, which answer False. Space name arguments
--  may have any bounds; they need not start at 1.
--
--  Limits. A tree holds at most 64 spaces, the root included, and a full
--  space name has at most 256 characters. Add_Space raises
--  Ks_Bad_Parameter_Exception when the new space would exceed either
--  limit, and leaves the tree unchanged. A name argument longer than 256
--  characters names no space (Space_Exists and Verify_Name give False;
--  the other subprograms raise Ks_Image_Bad_Selected_Space_Name_Exception).
--
--  Transforms are values (Ks_Transform_2D_Linear), so the copyTransform
--  argument of VisionPro's AddSpace and ChangeTransform has no
--  counterpart: the tree always keeps its own copy.
--
--  The operations are done by the SPARK kernel
--  AMV.Kernels.Coordinate_Spaces (the C functions
--  ks_coordinate_space_tree_*), which keeps the tree in a fixed-size
--  record and proves that every operation leaves it consistent. Every
--  Parent_From_Child transform is bounded as in AMV.Transforms (entries
--  within 1.0E150) and invertible within that bound.
--
--  A tree is a value: assignment copies all spaces. Its stream attributes
--  store it by value: an Integer_32 format code ("KST" followed by 0), the
--  number of spaces including the root (Integer_32), then every space
--  other than the root in Space_Name order as its full name (an
--  Integer_32 length and 256 characters, NUL after the name) and its
--  Parent_From_Child transform (A, B, C, D, Translation_X and
--  Translation_Y as Long_Float). 'Read treats the stream as untrusted: it
--  rebuilds the tree space by space through the kernel and raises
--  Ks_Image_File_Exception, leaving the target unchanged, for a wrong
--  format code or count, for a space whose parent was not read before it,
--  for a repeated or malformed name, for a transform that Add_Space would
--  reject, and when the stream ends early.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Containers.Indefinite_Vectors;
with Ada.Strings.Unbounded;

with AMV.Transforms;

private with Ada.Finalization;
private with Ada.Streams;
private with AMV.Kernels.Coordinate_Spaces;

package AMV.Coordinate_Spaces is
   pragma Preelaborate;

   Root_Space_Name     : constant String := "@";
   Pixel_Space_Name    : constant String := "#";
   Selected_Space_Name : constant String := ".";
   Space_Separator     : constant Character := '\';

   type Ks_Add_Space_Constants is
     (Duplicate_Is_Error, Replace_Duplicate, Ignore_Duplicate);
   --  What Add_Space does when the space exists already (VisionPro:
   --  CogAddSpaceConstants, same positions): raise
   --  Ks_Bad_Parameter_Exception (VisionPro:
   --  CogSpaceTreeDuplicateChildNameException), replace its transform
   --  (keeping its descendants), or change nothing.

   type Ks_Space_Tree_Pathname_Constants is (None, Full, Partial);
   --  How a space name is returned (VisionPro:
   --  CogSpaceTreePathnameConstants, same positions): None gives its last
   --  component ("Part" for "@\Fixture\Part"; "@" for the root), Full its
   --  full name, and Partial, for a space below the space named by the
   --  operation's Space_Name argument, its path relative to that space
   --  ("B\C" for "@\A\B\C" below "@\A"). Partial gives the full name of
   --  a space that is not below it (the space itself, its parent).

   ---------------------------------------------------------------------
   --  CogStringCollection
   ---------------------------------------------------------------------

   package String_Collections is

      type Ks_String_Collection is tagged private;
      --  A list of strings, the counterpart of CogStringCollection (of its
      --  members only Count and Item so far, plus the AMV addition
      --  Append). A value: assignment copies the strings. The default
      --  value is empty.

      function Count (Collection : Ks_String_Collection) return Natural;

      function Item
        (Collection : Ks_String_Collection; Index : Natural) return String;
      --  The Index-th string, 0-based; the result is indexed from 1.
      --  Raises Constraint_Error when Index >= Count.

      procedure Append
        (Collection : in out Ks_String_Collection; Value : String);
      --  Adds Value at the end (an AMV addition; the tree builds its
      --  results with it).

   private

      package String_Vectors is new Ada.Containers.Indefinite_Vectors
        (Index_Type => Natural, Element_Type => String);

      type Ks_String_Collection is tagged record
         Items : String_Vectors.Vector;
      end record;

   end String_Collections;
   --  A nested package, so that the operations of the tree that return a
   --  collection are primitive of the tree only.

   subtype Ks_String_Collection is String_Collections.Ks_String_Collection;

   function Count (Collection : Ks_String_Collection) return Natural
     renames String_Collections.Count;

   function Item
     (Collection : Ks_String_Collection; Index : Natural) return String
     renames String_Collections.Item;

   ---------------------------------------------------------------------
   --  CogCoordinateSpaceTree
   ---------------------------------------------------------------------

   type Ks_Coordinate_Space_Tree is tagged private;
   --  Default value: a tree that contains only the root space "@".

   function Root_Name (Tree : Ks_Coordinate_Space_Tree) return String;
   --  The name of the root space, always "@" (VisionPro's RootName can
   --  also be set; AMV does not implement the setter).

   procedure Add_Space
     (Tree               : in out Ks_Coordinate_Space_Tree;
      Parent_Space_Name  : String;
      New_Space_Name     : String;
      Parent_From_New    : AMV.Transforms.Ks_Transform_2D_Linear;
      Duplicate_Handling : Ks_Add_Space_Constants := Replace_Duplicate);
   --  Adds the space Parent_Space_Name & '\' & New_Space_Name, whose
   --  coordinates Parent_From_New maps into the parent's. When that space
   --  exists already, Duplicate_Handling decides (see
   --  Ks_Add_Space_Constants); its default, Replace_Duplicate, is an AMV
   --  choice (VisionPro's default is not documented) that makes re-adding
   --  a space, as a fixture tool does on every run, replace its transform.
   --  The checks, in this order: Parent_Space_Name must be in the tree and
   --  New_Space_Name must be a valid path component (see above; of a
   --  component longer than 256 characters only the first 256 are
   --  checked), otherwise Ks_Image_Bad_Selected_Space_Name_Exception is
   --  raised; Parent_From_New must be finite and within 1.0E150
   --  (Ks_Bad_Parameter_Exception) and invertible within that bound
   --  (Ks_Transform_Singular_Exception); the full name must have at most
   --  256 characters (Ks_Bad_Parameter_Exception); an existing space with
   --  Duplicate_Is_Error raises Ks_Bad_Parameter_Exception; a new space
   --  must fit in the tree (64 spaces), otherwise
   --  Ks_Bad_Parameter_Exception is raised. So Ignore_Duplicate still
   --  checks its arguments. A failed call leaves the tree unchanged.

   procedure Change_Transform
     (Tree                  : in out Ks_Coordinate_Space_Tree;
      Child_Space_Name      : String;
      New_Parent_From_Child : AMV.Transforms.Ks_Transform_2D_Linear);
   --  Replaces the transform of the space (its descendants keep theirs).
   --  Not allowed for the root (Ks_Bad_Parameter_Exception). The
   --  transform must be finite and within 1.0E150
   --  (Ks_Bad_Parameter_Exception) and invertible within that bound
   --  (Ks_Transform_Singular_Exception).

   procedure Delete_Subtree
     (Tree : in out Ks_Coordinate_Space_Tree; Space_Name : String);
   --  Removes the space and all its descendants. The root cannot be
   --  removed (Ks_Bad_Parameter_Exception).

   function Get_Transform
     (Tree            : Ks_Coordinate_Space_Tree;
      To_Space_Name   : String;
      From_Space_Name : String) return AMV.Transforms.Ks_Transform_2D_Linear;
   --  The transform that maps coordinates expressed in From_Space_Name to
   --  coordinates expressed in To_Space_Name, via the root:
   --  Root_From_To.Invert.Compose (Root_From_From), and Root_From_From
   --  alone when To_Space_Name is "@". Root_From_X composes the
   --  Parent_From_Child transforms on the path from X up to "@", grouped
   --  from X up: P_Top * (... * (P_Parent * (P_X * Identity))), where P_X
   --  is the transform of X and P_Top that of the space just below the
   --  root. So Get_Transform ("@", "@\A") is exactly the transform given
   --  for "@\A", and the same name twice gives exactly the identity.
   --  Raises Ks_Transform_Singular_Exception if Root_From_To cannot be
   --  inverted within the bounds of AMV.Transforms (possible only for
   --  extreme scalings, since every single transform is invertible; see
   --  AMV.Transforms.Invert), and Ks_Bad_Parameter_Exception when a
   --  transform composed along either path, or the final result, would
   --  have an entry beyond 1.0E150 (see AMV.Transforms.Compose).

   function Parent_Name
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : String;
      Pathname_Format : Ks_Space_Tree_Pathname_Constants := Full)
      return String;
   --  The name of the parent in Pathname_Format (Partial gives the full
   --  name, since the parent is not below the space); "" for the root.

   function Child_Names
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : String;
      Pathname_Format : Ks_Space_Tree_Pathname_Constants := Full)
      return Ks_String_Collection;
   --  The names of the children (immediate descendants) of the space, in
   --  lexical order of their full names, in Pathname_Format (None and
   --  Partial both give the last component).

   function All_Child_Names
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : String;
      Pathname_Format : Ks_Space_Tree_Pathname_Constants := Full;
      Children_Only   : Boolean := True) return Ks_String_Collection;
   --  The names of all descendants of the space at any depth, and of the
   --  space itself unless Children_Only, in lexical order of their full
   --  names (so the space itself comes first), in Pathname_Format. With
   --  Partial, a descendant is named by its path below Space_Name and the
   --  space itself by its full name.

   function Verify_Name
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : String;
      Pathname_Format : Ks_Space_Tree_Pathname_Constants;
      Found_Name      : out Ada.Strings.Unbounded.Unbounded_String)
      return Boolean;
   --  True when Space_Name is the full name of a space of the tree;
   --  Found_Name is then its name in Pathname_Format (Partial gives the
   --  full name). False, with Found_Name "", for any other name (malformed
   --  ones included; never raises). VisionPro also accepts bare and
   --  partial names here; AMV does not (see above).

   ---------------------------------------------------------------------
   --  AMV additions
   ---------------------------------------------------------------------

   function Full_Space_Name
     (Parent_Space_Name, New_Space_Name : String) return String;
   --  Parent_Space_Name & '\' & New_Space_Name (no check). The result is
   --  indexed from 1, whatever the bounds of the arguments.

   procedure Clear (Tree : in out Ks_Coordinate_Space_Tree);
   --  Removes every space except the root.

   function Space_Exists
     (Tree : Ks_Coordinate_Space_Tree; Space_Name : String) return Boolean;
   --  True for "@" and for every space added to the tree. Never raises:
   --  a malformed or unknown name simply gives False.

   function Space_Count (Tree : Ks_Coordinate_Space_Tree) return Positive;
   --  Number of spaces, including the root.

   function Space_Name
     (Tree : Ks_Coordinate_Space_Tree; Index : Natural) return String;
   --  The Index-th space name (0-based) in lexical order (that of String
   --  "<"); index 0 is "@". Raises Constraint_Error when Index >=
   --  Space_Count.

   function Parent_From_Child_Transform
     (Tree : Ks_Coordinate_Space_Tree; Space_Name : String)
      return AMV.Transforms.Ks_Transform_2D_Linear;
   --  The transform stored for the space, exactly as it was given to
   --  Add_Space or Change_Transform; the identity for the root.

private

   type Tree_Access is
     access AMV.Kernels.Coordinate_Spaces.Ks_Coordinate_Space_Tree;

   type Ks_Coordinate_Space_Tree is new Ada.Finalization.Controlled with
   record
      Box : Tree_Access;
      --  The kernel's tree, owned by this object; null for the tree that
      --  holds only the root (the default value). The first change
      --  allocates it, and Adjust copies it, so trees are values.
   end record;

   overriding procedure Adjust (Tree : in out Ks_Coordinate_Space_Tree);
   overriding procedure Finalize (Tree : in out Ks_Coordinate_Space_Tree);

   overriding function "=" (Left, Right : Ks_Coordinate_Space_Tree)
      return Boolean;
   --  The same spaces with the same parents and transforms (compared entry
   --  by entry), whether or not a tree has allocated its box.

   procedure Write_Tree
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Ks_Coordinate_Space_Tree);
   procedure Read_Tree
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Coordinate_Space_Tree);

   for Ks_Coordinate_Space_Tree'Write use Write_Tree;
   for Ks_Coordinate_Space_Tree'Read use Read_Tree;
   --  The predefined attributes would store the box pointer itself.

end AMV.Coordinate_Spaces;
