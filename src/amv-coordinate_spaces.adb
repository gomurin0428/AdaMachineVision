pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.IO_Exceptions;
with Ada.Unchecked_Deallocation;

with AMV.Checks;
with AMV.Kernels;

package body AMV.Coordinate_Spaces is

   package K renames AMV.Kernels.Coordinate_Spaces;
   package KT renames AMV.Kernels.Coordinate_Spaces.KT;

   use type AMV.Kernels.Int32;

   procedure Check (Status : AMV.Kernels.Ks_Status) renames AMV.Checks.Check;

   procedure Free is new Ada.Unchecked_Deallocation
     (K.Ks_Coordinate_Space_Tree, Tree_Access);

   Root_Only : aliased constant K.Ks_Coordinate_Space_Tree := (others => <>);
   --  The value of every tree without a box.

   function View
     (Tree : Ks_Coordinate_Space_Tree)
      return not null access constant K.Ks_Coordinate_Space_Tree
   is
     (if Tree.Box = null then Root_Only'Access else Tree.Box);
   --  The kernel's tree, for reading.

   procedure Prepare_Change (Tree : in out Ks_Coordinate_Space_Tree);
   --  Gives Tree its own box, for writing.

   procedure Prepare_Change (Tree : in out Ks_Coordinate_Space_Tree) is
   begin
      if Tree.Box = null then
         Tree.Box := new K.Ks_Coordinate_Space_Tree'(Root_Only);
      end if;
   end Prepare_Change;

   function Name (Text : String) return K.Ks_Space_Name
     renames K.To_Space_Name;

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

   function Format_Code
     (Format : Ks_Space_Tree_Pathname_Constants) return AMV.Kernels.Int32 is
     (AMV.Kernels.Int32 (Ks_Space_Tree_Pathname_Constants'Pos (Format)));
   --  The kernel's Pathname_* code.

   --  The kernel codes are the positions of the enumerations.
   pragma Compile_Time_Error
     (Ks_Add_Space_Constants'Pos (Duplicate_Is_Error)
        /= K.Add_Space_Duplicate_Is_Error
      or else Ks_Add_Space_Constants'Pos (Replace_Duplicate)
                /= K.Add_Space_Replace_Duplicate
      or else Ks_Add_Space_Constants'Pos (Ignore_Duplicate)
                /= K.Add_Space_Ignore_Duplicate
      or else Ks_Space_Tree_Pathname_Constants'Pos (None) /= K.Pathname_None
      or else Ks_Space_Tree_Pathname_Constants'Pos (Full) /= K.Pathname_Full
      or else Ks_Space_Tree_Pathname_Constants'Pos (Partial)
                /= K.Pathname_Partial
      or else Boolean'Pos (False) /= AMV.Kernels.False_Value
      or else Boolean'Pos (True) /= AMV.Kernels.True_Value,
      "the enumerations must match the kernel's codes");

   --  Value semantics

   overriding procedure Adjust (Tree : in out Ks_Coordinate_Space_Tree) is
   begin
      if Tree.Box /= null then
         Tree.Box := new K.Ks_Coordinate_Space_Tree'(Tree.Box.all);
      end if;
   end Adjust;

   overriding procedure Finalize (Tree : in out Ks_Coordinate_Space_Tree) is
   begin
      Free (Tree.Box);
   end Finalize;

   overriding function "=" (Left, Right : Ks_Coordinate_Space_Tree)
      return Boolean is
     (K.Same_Tree (View (Left).all, View (Right).all));

   package body String_Collections is

      function Count (Collection : Ks_String_Collection) return Natural is
        (Natural (Collection.Items.Length));

      function Item
        (Collection : Ks_String_Collection; Index : Natural) return String
      is (Collection.Items.Element (Index));

      procedure Append
        (Collection : in out Ks_String_Collection; Value : String)
      is
         --  Value slid to bounds 1 .. N, so that Item starts at 1.
         subtype Text is String (1 .. Value'Length);
      begin
         Collection.Items.Append (Text (Value));
      end Append;

   end String_Collections;

   --  Public operations

   function Root_Name (Tree : Ks_Coordinate_Space_Tree) return String is
      Result : K.Ks_Space_Name;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Root_Name (View (Tree).all, Result, Status);
      Check (Status);
      return K.To_String (Result);
   end Root_Name;

   procedure Add_Space
     (Tree               : in out Ks_Coordinate_Space_Tree;
      Parent_Space_Name  : String;
      New_Space_Name     : String;
      Parent_From_New    : AMV.Transforms.Ks_Transform_2D_Linear;
      Duplicate_Handling : Ks_Add_Space_Constants := Replace_Duplicate)
   is
      Status : AMV.Kernels.Ks_Status;
   begin
      Prepare_Change (Tree);
      K.Add_Space
        (Tree.Box.all, Name (Parent_Space_Name), Name (New_Space_Name),
         To_Kernel (Parent_From_New),
         AMV.Kernels.Int32 (Ks_Add_Space_Constants'Pos (Duplicate_Handling)),
         Status);
      Check (Status);
   end Add_Space;

   procedure Change_Transform
     (Tree                  : in out Ks_Coordinate_Space_Tree;
      Child_Space_Name      : String;
      New_Parent_From_Child : AMV.Transforms.Ks_Transform_2D_Linear)
   is
      Status : AMV.Kernels.Ks_Status;
   begin
      Prepare_Change (Tree);
      K.Change_Transform
        (Tree.Box.all, Name (Child_Space_Name),
         To_Kernel (New_Parent_From_Child), Status);
      Check (Status);
   end Change_Transform;

   procedure Delete_Subtree
     (Tree : in out Ks_Coordinate_Space_Tree; Space_Name : String)
   is
      Status : AMV.Kernels.Ks_Status;
   begin
      Prepare_Change (Tree);
      K.Delete_Subtree (Tree.Box.all, Name (Space_Name), Status);
      Check (Status);
   end Delete_Subtree;

   function Get_Transform
     (Tree            : Ks_Coordinate_Space_Tree;
      To_Space_Name   : String;
      From_Space_Name : String) return AMV.Transforms.Ks_Transform_2D_Linear
   is
      Result : KT.Ks_Transform_2D_Linear;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Get_Transform
        (View (Tree).all, Name (To_Space_Name), Name (From_Space_Name),
         Result, Status);
      Check (Status);
      return From_Kernel (Result);
   end Get_Transform;

   function Parent_Name
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : String;
      Pathname_Format : Ks_Space_Tree_Pathname_Constants := Full)
      return String
   is
      Result : K.Ks_Space_Name;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Parent_Name
        (View (Tree).all, Name (Space_Name), Format_Code (Pathname_Format),
         Result, Status);
      Check (Status);
      return K.To_String (Result);
   end Parent_Name;

   function Child_Names
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : String;
      Pathname_Format : Ks_Space_Tree_Pathname_Constants := Full)
      return Ks_String_Collection
   is
      Space  : constant K.Ks_Space_Name := Name (Space_Name);
      Format : constant AMV.Kernels.Int32 := Format_Code (Pathname_Format);
      Count  : AMV.Kernels.Int32;
      Child  : K.Ks_Space_Name;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Child_Names_Count (View (Tree).all, Space, Count, Status);
      Check (Status);
      return Result : Ks_String_Collection do
         for Index in 0 .. Count - 1 loop  --  SHELL: one entry per child
            K.Child_Name (View (Tree).all, Space, Format, Index, Child,
                          Status);
            Check (Status);
            Result.Append (K.To_String (Child));
         end loop;  --  SHELL: (the loop above)
      end return;
   end Child_Names;

   function All_Child_Names
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : String;
      Pathname_Format : Ks_Space_Tree_Pathname_Constants := Full;
      Children_Only   : Boolean := True) return Ks_String_Collection
   is
      Space  : constant K.Ks_Space_Name := Name (Space_Name);
      Format : constant AMV.Kernels.Int32 := Format_Code (Pathname_Format);
      Only   : constant AMV.Kernels.Int32 :=
        AMV.Kernels.Int32 (Boolean'Pos (Children_Only));
      Count  : AMV.Kernels.Int32;
      Child  : K.Ks_Space_Name;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.All_Child_Names_Count (View (Tree).all, Space, Only, Count, Status);
      Check (Status);
      return Result : Ks_String_Collection do
         for Index in 0 .. Count - 1 loop  --  SHELL: one entry per space
            K.All_Child_Name (View (Tree).all, Space, Format, Only, Index,
                              Child, Status);
            Check (Status);
            Result.Append (K.To_String (Child));
         end loop;  --  SHELL: (the loop above)
      end return;
   end All_Child_Names;

   function Verify_Name
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : String;
      Pathname_Format : Ks_Space_Tree_Pathname_Constants;
      Found_Name      : out Ada.Strings.Unbounded.Unbounded_String)
      return Boolean
   is
      Result : AMV.Kernels.Int32;
      Found  : K.Ks_Space_Name;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Verify_Name
        (View (Tree).all, Name (Space_Name), Format_Code (Pathname_Format),
         Result, Found, Status);
      Check (Status);
      Found_Name :=
        Ada.Strings.Unbounded.To_Unbounded_String (K.To_String (Found));
      return Result = AMV.Kernels.True_Value;
   end Verify_Name;

   --  AMV additions

   function Full_Space_Name
     (Parent_Space_Name, New_Space_Name : String) return String
   is
      --  The parent slid to bounds 1 .. N, so that the result starts at 1
      --  and "&" cannot run past Integer'Last because of high bounds.
      subtype Parent_Text is String (1 .. Parent_Space_Name'Length);
   begin
      return Parent_Text (Parent_Space_Name) & Space_Separator
             & New_Space_Name;
   end Full_Space_Name;

   procedure Clear (Tree : in out Ks_Coordinate_Space_Tree) is
   begin
      --  A tree without a box holds only the root.
      Free (Tree.Box);
   end Clear;

   function Space_Exists
     (Tree : Ks_Coordinate_Space_Tree; Space_Name : String) return Boolean
   is
      Result : AMV.Kernels.Int32;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Space_Exists (View (Tree).all, Name (Space_Name), Result, Status);
      Check (Status);
      return Result = AMV.Kernels.True_Value;
   end Space_Exists;

   function Space_Count (Tree : Ks_Coordinate_Space_Tree) return Positive is
      Result : AMV.Kernels.Int32;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Space_Count (View (Tree).all, Result, Status);
      Check (Status);
      return Positive (Result);
   end Space_Count;

   function Space_Name
     (Tree : Ks_Coordinate_Space_Tree; Index : Natural) return String
   is
      Result : K.Ks_Space_Name;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Space_Name
        (View (Tree).all, AMV.Kernels.Int32 (Index), Result, Status);
      Check (Status);
      return K.To_String (Result);
   end Space_Name;

   function Parent_From_Child_Transform
     (Tree : Ks_Coordinate_Space_Tree; Space_Name : String)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is
      Result : KT.Ks_Transform_2D_Linear;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Parent_From_Child_Transform
        (View (Tree).all, Name (Space_Name), Result, Status);
      Check (Status);
      return From_Kernel (Result);
   end Parent_From_Child_Transform;

   --  Streams

   procedure Write_Tree
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Ks_Coordinate_Space_Tree)
   is
      Tree      : K.Ks_Coordinate_Space_Tree renames View (Item).all;
      Count     : AMV.Kernels.Int32;
      Space     : K.Ks_Space_Name;
      Transform : KT.Ks_Transform_2D_Linear;
      Status    : AMV.Kernels.Ks_Status;
   begin
      K.Space_Count (Tree, Count, Status);
      Check (Status);
      AMV.Kernels.Int32'Write (Stream, K.Stream_Code);
      AMV.Kernels.Int32'Write (Stream, Count);
      for Index in 1 .. Count - 1 loop  --  SHELL: stream I/O, every space
         K.Space_Name (Tree, Index, Space, Status);
         Check (Status);
         K.Parent_From_Child_Transform (Tree, Space, Transform, Status);
         Check (Status);
         K.Ks_Space_Name'Write (Stream, Space);
         KT.Ks_Transform_2D_Linear'Write (Stream, Transform);
      end loop;  --  SHELL: (the loop above)
   end Write_Tree;

   procedure Read_Tree
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Coordinate_Space_Tree)
   is
      Code      : AMV.Kernels.Int32;
      Count     : AMV.Kernels.Int32;
      Space     : K.Ks_Space_Name;
      Transform : KT.Ks_Transform_2D_Linear;
      Status    : AMV.Kernels.Ks_Status;
      Result    : Ks_Coordinate_Space_Tree;
   begin
      AMV.Kernels.Int32'Read (Stream, Code);
      AMV.Kernels.Int32'Read (Stream, Count);
      K.Check_Read_Header (Code, Count, Status);
      Check (Status);
      Prepare_Change (Result);
      for Index in 2 .. Count loop  --  SHELL: stream I/O, every space
         K.Ks_Space_Name'Read (Stream, Space);
         KT.Ks_Transform_2D_Linear'Read (Stream, Transform);
         K.Add_Read_Space (Result.Box.all, Space, Transform, Status);
         Check (Status);
      end loop;  --  SHELL: (the loop above)
      Item := Result;
   exception
      when Ada.IO_Exceptions.End_Error =>
         raise Ks_Image_File_Exception
           with "Ks_Coordinate_Space_Tree'Read: the stream ends before the "
                & "tree is complete";
   end Read_Tree;

end AMV.Coordinate_Spaces;
