pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package body AMV.Kernels.Coordinate_Spaces with SPARK_Mode is

   Identity : constant KT.Ks_Transform_2D_Linear := (others => <>);

   Empty_Name : constant Ks_Space_Name := (others => <>);

   subtype Valid_Tree_Type is Ks_Coordinate_Space_Tree
     with Dynamic_Predicate => Valid_Tree (Valid_Tree_Type);
   --  A tree known to be valid. The predicate is proved where a tree is
   --  passed as this subtype and assumed inside; it is not checked at run
   --  time (the entry points check Valid_Tree themselves).

   ---------------------------------------------------------------------
   --  Lexical order
   ---------------------------------------------------------------------

   function First_Difference (Left, Right : Ks_Space_Name) return Positive
   is
      Shorter : constant Natural := Shorter_Length (Left, Right);
   begin
      for J in 1 .. Shorter loop
         if Left.Text (J) /= Right.Text (J) then
            return J;
         end if;
         pragma Loop_Invariant (Has_Prefix (Left, Right, J));
      end loop;
      return Shorter + 1;
   end First_Difference;

   procedure Lemma_First_Difference
     (Left, Right : Ks_Space_Name;
      K           : Positive)
   with
     Ghost,
     Pre  => Fits (Left) and then Fits (Right)
             and then K <= Shorter_Length (Left, Right) + 1
             and then Has_Prefix (Left, Right, K - 1)
             and then (if K <= Shorter_Length (Left, Right)
                       then Left.Text (K) /= Right.Text (K)),
     Post => First_Difference (Left, Right) = K;
   --  The first difference is the only position with these properties.

   procedure Lemma_First_Difference
     (Left, Right : Ks_Space_Name;
      K           : Positive) is null;

   procedure Lemma_Less_Transitive (A, B, C : Ks_Space_Name)
   with
     Ghost,
     Pre  => Fits (A) and then Fits (B) and then Fits (C)
             and then Less (A, B) and then Less (B, C),
     Post => Less (A, C);

   procedure Lemma_Less_Transitive (A, B, C : Ks_Space_Name) is
      K1 : constant Positive := First_Difference (A, B);
      K2 : constant Positive := First_Difference (B, C);
      M  : constant Positive := Positive'Min (K1, K2);
   begin
      --  A, B and C agree before M; at M, A is below C or ends first.
      pragma Assert (Has_Prefix (A, C, M - 1));
      if K1 < K2 then
         pragma Assert (M <= Shorter_Length (B, C));
         pragma Assert (B.Text (M) = C.Text (M));
      elsif K2 < K1 then
         pragma Assert (M <= Shorter_Length (A, B));
         pragma Assert (A.Text (M) = B.Text (M));
      end if;
      pragma Assert (M <= Shorter_Length (A, C) + 1);
      pragma Assert (Less_At (A, C, M));
      Lemma_First_Difference (A, C, M);
   end Lemma_Less_Transitive;

   procedure Lemma_Less_Total (A, B : Ks_Space_Name)
   with
     Ghost,
     Pre  => Fits (A) and then Fits (B)
             and then not Same_Name (A, B) and then not Less (A, B),
     Post => Less (B, A);
   --  Two different names are ordered one way or the other.

   procedure Lemma_Less_Total (A, B : Ks_Space_Name) is
      K : constant Positive := First_Difference (A, B);
   begin
      pragma Assert (Shorter_Length (B, A) = Shorter_Length (A, B));
      pragma Assert (Has_Prefix (B, A, K - 1));
      Lemma_First_Difference (B, A, K);
      pragma Assert (Less_At (B, A, K));
   end Lemma_Less_Total;

   procedure Lemma_Parent_Less (Parent, Name : Ks_Space_Name)
   with
     Ghost,
     Pre  => Extends (Name, Parent),
     Post => Fits (Parent) and then Fits (Name) and then Less (Parent, Name);
   --  A parent's name sorts before the names of its children.

   procedure Lemma_Parent_Less (Parent, Name : Ks_Space_Name) is
   begin
      Lemma_First_Difference (Parent, Name, Integer (Parent.Length) + 1);
   end Lemma_Parent_Less;

   ---------------------------------------------------------------------
   --  Names
   ---------------------------------------------------------------------

   function To_Space_Name (Source : String) return Ks_Space_Name is
      Kept   : constant Natural := Natural'Min (Source'Length,
                                                Max_Name_Length);
      Result : Ks_Space_Name := (Length => Int32 (Source'Length),
                                 Text   => [others => ASCII.NUL]);
   begin
      for J in 1 .. Kept loop
         Result.Text (J) := Source (Source'First + (J - 1));
         pragma Loop_Invariant
           (Result.Length = Int32 (Source'Length)
            and then (for all K in 1 .. J
                      => Result.Text (K) = Source (Source'First + (K - 1))));
      end loop;
      return Result;
   end To_Space_Name;

   function To_String (Name : Ks_Space_Name) return String is
     (String (Name.Text (1 .. Integer (Name.Length))));

   function Shown (Name : Ks_Space_Name) return String
   with Post => Shown'Result'First = 1
                and then Shown'Result'Length <= Max_Name_Length;
   --  The characters of Name that it holds, for messages.

   function Shown (Name : Ks_Space_Name) return String is
      Last : constant Natural :=
        (if Name.Length < 0 then 0
         elsif Name.Length > Max_Name_Length then Max_Name_Length
         else Natural (Name.Length));
   begin
      return String (Name.Text (1 .. Last));
   end Shown;

   function Sub_Name
     (Name        : Ks_Space_Name;
      First, Last : Integer) return Ks_Space_Name
   with Pre  => First in 1 .. Max_Name_Length + 1
                and then Last in First - 1 .. Max_Name_Length,
        Post => Fits (Sub_Name'Result)
                and then Sub_Name'Result.Length = Int32 (Last - First + 1);
   --  Name.Text (First .. Last) as a name, with NUL characters after it.

   function Sub_Name
     (Name        : Ks_Space_Name;
      First, Last : Integer) return Ks_Space_Name
   is
      Length : constant Natural := Last - First + 1;
      Result : Ks_Space_Name := (Length => Int32 (Length),
                                 Text   => [others => ASCII.NUL]);
   begin
      Result.Text (1 .. Length) := Name.Text (First .. Last);
      return Result;
   end Sub_Name;

   function Clean (Name : Ks_Space_Name) return Ks_Space_Name is
     (Sub_Name (Name, 1, Integer (Name.Length)))
   with Pre  => Fits (Name),
        Post => Fits (Clean'Result);
   --  Name with NUL characters after its text.

   function Well_Formed (Name : Ks_Space_Name) return Boolean
   with Pre  => Fits (Name),
        Post => (if Well_Formed'Result then Name.Length >= 1);
   --  Name is "@" or "@" followed by one or more '\'-component pairs.

   function Well_Formed (Name : Ks_Space_Name) return Boolean is
      Last  : constant Natural := Natural (Name.Length);
      Start : Positive := 3;
   begin
      if Is_Root_Name (Name) then
         return True;
      elsif Last < 3
        or else Name.Text (1) /= Root_Character
        or else Name.Text (2) /= Separator
        or else Name.Text (Last) = Separator
      then
         return False;
      end if;
      --  Every component that ends at a separator, then the last one.
      for I in 3 .. Last loop
         if Name.Text (I) = Separator then
            if not Valid_Component (Name, Start, I - 1) then
               return False;
            end if;
            Start := I + 1;
         end if;
         pragma Loop_Invariant
           (Start in 3 .. I + 1
            and then (if Start = I + 1 then Name.Text (I) = Separator));
      end loop;
      return Valid_Component (Name, Start, Last);
   end Well_Formed;

   function Valid_New_Component (Name : Ks_Space_Name) return Boolean
   with Post => (if Valid_New_Component'Result
                 then Name.Length >= 1
                      and then (if Fits (Name)
                                then Valid_Component
                                       (Name, 1, Integer (Name.Length))));
   --  Name is a valid path component, judged on the characters it holds
   --  (all of them unless it is longer than Max_Name_Length).

   function Valid_New_Component (Name : Ks_Space_Name) return Boolean is
     (Name.Length >= 1
      and then Valid_Component
                 (Name, 1, Integer (Int32'Min (Name.Length,
                                               Max_Name_Length))));

   procedure Make_Child_Name
     (Parent    : Ks_Space_Name;
      Component : Ks_Space_Name;
      Result    : out Ks_Space_Name)
   with
     Pre  => Parent.Length in 1 .. Max_Name_Length
             and then Component.Length >= 1
             and then Component.Length <= Max_Name_Length - 1 - Parent.Length,
     Post => Result.Length = Parent.Length + 1 + Component.Length
             and then (if Valid_Component
                            (Component, 1, Integer (Component.Length))
                       then Extends (Result, Parent));
   --  Parent & '\' & Component.

   procedure Make_Child_Name
     (Parent    : Ks_Space_Name;
      Component : Ks_Space_Name;
      Result    : out Ks_Space_Name)
   is
      LP : constant Natural := Natural (Parent.Length);
      LC : constant Natural := Natural (Component.Length);
   begin
      Result := (Length => Parent.Length + 1 + Component.Length,
                 Text   => [others => ASCII.NUL]);
      Result.Text (1 .. LP) := Parent.Text (1 .. LP);
      Result.Text (LP + 1) := Separator;
      Result.Text (LP + 2 .. LP + 1 + LC) := Component.Text (1 .. LC);
      pragma Assert
        (for all J in LP + 2 .. LP + 1 + LC
         => Result.Text (J) = Component.Text (J - LP - 1));
   end Make_Child_Name;

   ---------------------------------------------------------------------
   --  Failures
   ---------------------------------------------------------------------

   procedure Fail_Bad_Tree (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Fail_Bad_Tree (Status : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter,
                   "Tree is not a valid coordinate space tree");
   end Fail_Bad_Tree;

   procedure Name_Failure
     (Status    : out Ks_Status;
      Operation : String;
      Problem   : String;
      Name      : Ks_Space_Name)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40
             and then Problem'Length <= 60,
     Post => Valid (Status)
             and then Status.Failure = Failure_Image_Bad_Selected_Space_Name;
   --  "<Operation>: <Problem> "<Name>"".

   procedure Name_Failure
     (Status    : out Ks_Status;
      Operation : String;
      Problem   : String;
      Name      : Ks_Space_Name) is
   begin
      Set_Failure
        (Status, Failure_Image_Bad_Selected_Space_Name,
         Operation & ": " & Problem & " """ & Shown (Name) & """");
   end Name_Failure;

   procedure Check_Transform
     (Transform : KT.Ks_Transform_2D_Linear;
      Operation : String;
      Argument  : String;
      Status    : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40
             and then Argument'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Transform_Singular
             and then (if Succeeded (Status) then KT.Bounded (Transform));
   --  Bad_Parameter unless Transform is finite and within the bound,
   --  Transform_Singular unless it is invertible within it. Argument names
   --  the transform in the messages.

   procedure Check_Transform
     (Transform : KT.Ks_Transform_2D_Linear;
      Operation : String;
      Argument  : String;
      Status    : out Ks_Status)
   is
      Inverse : KT.Ks_Transform_2D_Linear;
   begin
      --  KT.Bounded is False for a NaN or an infinity at run time.
      if not KT.Bounded (Transform) then
         Set_Failure
           (Status, Failure_Bad_Parameter,
            Operation & ": the " & Argument & " transform must be finite "
            & "and within +/-1.0E150");
         return;
      end if;
      --  Only whether the inverse exists matters here.
      KT.Invert (Transform, Inverse, Status);
      if not Succeeded (Status) then
         Set_Failure
           (Status, Failure_Transform_Singular,
            Operation & ": the " & Argument & " transform is singular");
         return;
      end if;
      pragma Assert (KT.Bounded (Inverse));
   end Check_Transform;

   procedure Check_Pathname_Format
     (Format    : Int32;
      Operation : String;
      Status    : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Format in Pathname_Code);
   --  Bad_Parameter unless Format is one of the Pathname_* codes.

   procedure Check_Pathname_Format
     (Format    : Int32;
      Operation : String;
      Status    : out Ks_Status) is
   begin
      if Format in Pathname_Code then
         Set_Success (Status);
      else
         Set_Failure
           (Status, Failure_Bad_Parameter,
            Operation & ": Pathname_Format must be 0 (None), 1 (Full) or "
            & "2 (Partial)");
      end if;
   end Check_Pathname_Format;

   procedure Index_Failure
     (Status    : out Ks_Status;
      Operation : String;
      Index     : Int32;
      Count     : Int32)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40
             and then Count in 0 .. Max_Spaces,
     Post => Valid (Status)
             and then Status.Failure = Failure_Index_Out_Of_Range;
   --  "<Operation>: index <Index> is not in 0 .. <Count - 1>".

   procedure Index_Failure
     (Status    : out Ks_Status;
      Operation : String;
      Index     : Int32;
      Count     : Int32) is
   begin
      if Count = 0 then
         Set_Failure
           (Status, Failure_Index_Out_Of_Range,
            Operation & ": index" & Int32'Image (Index)
            & " is out of range (there are no names)");
      else
         Set_Failure
           (Status, Failure_Index_Out_Of_Range,
            Operation & ": index" & Int32'Image (Index) & " is not in 0 .."
            & Int32'Image (Count - 1));
      end if;
   end Index_Failure;

   ---------------------------------------------------------------------
   --  Looking up spaces
   ---------------------------------------------------------------------

   procedure Find
     (Tree  : Ks_Coordinate_Space_Tree;
      Name  : Ks_Space_Name;
      Index : out Int32)
   with
     Pre  => Tree.Count in 1 .. Max_Spaces,
     Post => Index in -1 .. Tree.Count - 1
             and then (if Index >= 0
                       then Same_Name (Tree.Spaces (Index).Name, Name));
   --  The index of the space named Name, or -1.

   procedure Find
     (Tree  : Ks_Coordinate_Space_Tree;
      Name  : Ks_Space_Name;
      Index : out Int32) is
   begin
      Index := -1;
      for I in 0 .. Tree.Count - 1 loop
         if Same_Name (Tree.Spaces (I).Name, Name) then
            Index := I;
            return;
         end if;
         pragma Loop_Invariant (Index = -1);
      end loop;
   end Find;

   procedure Lookup
     (Tree      : Ks_Coordinate_Space_Tree;
      Name      : Ks_Space_Name;
      Operation : String;
      Index     : out Int32;
      Status    : out Ks_Status)
   with
     Pre  => Tree.Count in 1 .. Max_Spaces
             and then Operation'First = 1 and then Operation'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None
                         | Failure_Image_Bad_Selected_Space_Name
             and then (if Succeeded (Status)
                       then Index in 0 .. Tree.Count - 1
                            and then Same_Name (Tree.Spaces (Index).Name,
                                                Name)
                       else Index = -1);
   --  The index of the space named Name. Image_Bad_Selected_Space_Name,
   --  naming Operation, when Name is malformed or not in the tree.

   procedure Lookup
     (Tree      : Ks_Coordinate_Space_Tree;
      Name      : Ks_Space_Name;
      Operation : String;
      Index     : out Int32;
      Status    : out Ks_Status) is
   begin
      Index := -1;
      if Name.Length > Max_Name_Length then
         Name_Failure (Status, Operation, "no space named", Name);
      elsif not Fits (Name) or else not Well_Formed (Name) then
         Name_Failure (Status, Operation, "malformed space name", Name);
      else
         Find (Tree, Name, Index);
         if Index < 0 then
            Name_Failure (Status, Operation, "no space named", Name);
         else
            Set_Success (Status);
         end if;
      end if;
   end Lookup;

   procedure Lemma_Not_Root
     (Tree  : Ks_Coordinate_Space_Tree;
      Name  : Ks_Space_Name;
      Index : Int32)
   with
     Ghost,
     Pre  => Valid_Tree (Tree) and then Index in 0 .. Tree.Count - 1
             and then Same_Name (Tree.Spaces (Index).Name, Name)
             and then not Is_Root_Name (Name),
     Post => Index >= 1;
   --  Only the root has the name "@".

   procedure Lemma_Not_Root
     (Tree  : Ks_Coordinate_Space_Tree;
      Name  : Ks_Space_Name;
      Index : Int32) is null;

   procedure Lemma_Name_Fits
     (Tree  : Ks_Coordinate_Space_Tree;
      Index : Int32)
   with
     Ghost,
     Pre  => Valid_Tree (Tree) and then Index in 0 .. Tree.Count - 1,
     Post => Fits (Tree.Spaces (Index).Name)
             and then Tree.Spaces (Index).Name.Length >= 1;
   --  Every name in a valid tree fits.

   procedure Lemma_Name_Fits
     (Tree  : Ks_Coordinate_Space_Tree;
      Index : Int32) is null;

   ---------------------------------------------------------------------
   --  Names in a pathname format
   ---------------------------------------------------------------------

   function Component_Start (Name : Ks_Space_Name) return Positive
   with Pre  => Fits (Name),
        Post => Component_Start'Result <= Integer (Name.Length) + 1;
   --  The position after the last '\' of Name, or 1 when it has none.

   function Component_Start (Name : Ks_Space_Name) return Positive is
   begin
      for I in reverse 1 .. Integer (Name.Length) loop
         if Name.Text (I) = Separator then
            return I + 1;
         end if;
      end loop;
      return 1;
   end Component_Start;

   function Format_Name
     (Name, Base : Ks_Space_Name;
      Format     : Int32) return Ks_Space_Name
   with Pre  => Fits (Name) and then Format in Pathname_Code,
        Post => Fits (Format_Name'Result);
   --  The full name Name in Format (see Pathname_None), Partial relative
   --  to the full name Base.

   function Format_Name
     (Name, Base : Ks_Space_Name;
      Format     : Int32) return Ks_Space_Name
   is
      Last : constant Natural := Natural (Name.Length);
   begin
      if Format = Pathname_None then
         return Sub_Name (Name, Component_Start (Name), Last);
      elsif Format = Pathname_Partial and then Is_Below (Name, Base) then
         return Sub_Name (Name, Integer (Base.Length) + 2, Last);
      else
         return Clean (Name);
      end if;
   end Format_Name;

   ---------------------------------------------------------------------
   --  Children and descendants
   ---------------------------------------------------------------------

   type Member_Kind is (Children, Descendants, Space_And_Descendants);
   --  The spaces listed for a space Base: its children (Child_Names), its
   --  descendants at any depth (All_Child_Names with Children_Only), or
   --  Base and its descendants.

   function Is_Member
     (Tree        : Ks_Coordinate_Space_Tree;
      Base, Index : Space_Index;
      Kind        : Member_Kind) return Boolean
   is
     (case Kind is
         when Children    => Tree.Spaces (Index).Parent = Base,
         when Descendants =>
            Is_Below (Tree.Spaces (Index).Name, Tree.Spaces (Base).Name),
         when Space_And_Descendants =>
            Index = Base
            or else Is_Below (Tree.Spaces (Index).Name,
                              Tree.Spaces (Base).Name));
   --  Entry Index is listed for Base. In a valid tree a name is below
   --  Base's exactly when its space descends from Base.

   function Count_Members
     (Tree : Ks_Coordinate_Space_Tree;
      Base : Space_Index;
      Kind : Member_Kind) return Int32
   with Pre  => Tree.Count in 1 .. Max_Spaces,
        Post => Count_Members'Result in 0 .. Tree.Count;
   --  The number of entries listed for Base.

   function Count_Members
     (Tree : Ks_Coordinate_Space_Tree;
      Base : Space_Index;
      Kind : Member_Kind) return Int32
   is
      Result : Int32 := 0;
   begin
      for I in 0 .. Tree.Count - 1 loop
         if Is_Member (Tree, Base, I, Kind) then
            Result := Result + 1;
         end if;
         pragma Loop_Invariant (Result in 0 .. I + 1);
      end loop;
      return Result;
   end Count_Members;

   procedure Find_Member
     (Tree     : Ks_Coordinate_Space_Tree;
      Base     : Space_Index;
      Kind     : Member_Kind;
      Position : Int32;
      Index    : out Int32)
   with Pre  => Tree.Count in 1 .. Max_Spaces,
        Post => Index in -1 .. Tree.Count - 1;
   --  The index of the entry listed for Base at Position (0-based, in
   --  entry order, which is the lexical order of the names), or -1.

   procedure Find_Member
     (Tree     : Ks_Coordinate_Space_Tree;
      Base     : Space_Index;
      Kind     : Member_Kind;
      Position : Int32;
      Index    : out Int32)
   is
      Seen : Int32 := 0;
   begin
      Index := -1;
      for I in 0 .. Tree.Count - 1 loop
         if Is_Member (Tree, Base, I, Kind) then
            if Seen = Position then
               Index := I;
               return;
            end if;
            Seen := Seen + 1;
         end if;
         pragma Loop_Invariant (Index = -1 and then Seen in 0 .. I + 1);
      end loop;
   end Find_Member;

   procedure Member_Count
     (Tree       : Valid_Tree_Type;
      Space_Name : Ks_Space_Name;
      Kind       : Member_Kind;
      Operation  : String;
      Result     : out Int32;
      Status     : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None
                         | Failure_Image_Bad_Selected_Space_Name
             and then Result in 0 .. Max_Spaces
             and then (if not Succeeded (Status) then Result = 0);
   --  The number of entries listed for the space Space_Name.

   procedure Member_Count
     (Tree       : Valid_Tree_Type;
      Space_Name : Ks_Space_Name;
      Kind       : Member_Kind;
      Operation  : String;
      Result     : out Int32;
      Status     : out Ks_Status)
   is
      Base : Int32;
   begin
      Result := 0;
      Lookup (Tree, Space_Name, Operation, Base, Status);
      if Succeeded (Status) then
         Result := Count_Members (Tree, Base, Kind);
      end if;
   end Member_Count;

   procedure Member_Name
     (Tree            : Valid_Tree_Type;
      Space_Name      : Ks_Space_Name;
      Pathname_Format : Int32;
      Kind            : Member_Kind;
      Index           : Int32;
      Operation       : String;
      Result          : out Ks_Space_Name;
      Status          : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Index_Out_Of_Range
             and then Fits (Result);
   --  The name of the Index-th entry listed for the space Space_Name, in
   --  Pathname_Format; the empty name when the call fails.

   procedure Member_Name
     (Tree            : Valid_Tree_Type;
      Space_Name      : Ks_Space_Name;
      Pathname_Format : Int32;
      Kind            : Member_Kind;
      Index           : Int32;
      Operation       : String;
      Result          : out Ks_Space_Name;
      Status          : out Ks_Status)
   is
      Base  : Int32;
      Found : Int32;
   begin
      Result := Empty_Name;
      Check_Pathname_Format (Pathname_Format, Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Lookup (Tree, Space_Name, Operation, Base, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Find_Member (Tree, Base, Kind, Index, Found);
      if Found < 0 then
         Index_Failure (Status, Operation, Index,
                        Count_Members (Tree, Base, Kind));
         return;
      end if;
      Lemma_Name_Fits (Tree, Found);
      Result := Format_Name (Tree.Spaces (Found).Name,
                             Tree.Spaces (Base).Name, Pathname_Format);
   end Member_Name;

   function Kind_Of (Children_Only : Int32) return Member_Kind is
     (if Children_Only = True_Value then Descendants
      else Space_And_Descendants);
   --  The entries All_Child_Names lists.

   procedure Check_Children_Only
     (Children_Only : Int32;
      Status        : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter;
   --  Bad_Parameter unless Children_Only is False_Value or True_Value.

   procedure Check_Children_Only
     (Children_Only : Int32;
      Status        : out Ks_Status) is
   begin
      if Children_Only in False_Value | True_Value then
         Set_Success (Status);
      else
         Set_Failure (Status, Failure_Bad_Parameter,
                      "All_Child_Names: Children_Only must be 0 or 1");
      end if;
   end Check_Children_Only;

   ---------------------------------------------------------------------
   --  Transforms along a path
   ---------------------------------------------------------------------

   procedure Root_From
     (Tree   : Valid_Tree_Type;
      Index  : Int32;
      Result : out KT.Ks_Transform_2D_Linear;
      Status : out Ks_Status)
   with
     Pre  => Index in 0 .. Tree.Count - 1,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then KT.Bounded (Result));
   --  The transform from the coordinates of space Index to root
   --  coordinates: the Parent_From_Child transforms from the space up to
   --  the root, P_Top * (... * (P_Parent * (P_Index * Identity))), each
   --  product computed from the space up. Bad_Parameter when a product
   --  leaves the bound.

   procedure Root_From
     (Tree   : Valid_Tree_Type;
      Index  : Int32;
      Result : out KT.Ks_Transform_2D_Linear;
      Status : out Ks_Status)
   is
      Node : Int32 := Index;
      Next : KT.Ks_Transform_2D_Linear;
   begin
      Result := Identity;
      Set_Success (Status);
      --  Parent indices decrease, so the walk up ends at the root.
      while Node > 0 loop
         pragma Loop_Invariant (Node in 1 .. Index);
         pragma Loop_Invariant
           (Valid (Status) and then Succeeded (Status)
            and then KT.Bounded (Result));
         pragma Loop_Variant (Decreases => Node);
         KT.Compose
           (Tree.Spaces (Node).Parent_From_Child, Result, Next, Status);
         if not Succeeded (Status) then
            return;
         end if;
         Result := Next;
         Node := Tree.Spaces (Node).Parent;
      end loop;
   end Root_From;

   ---------------------------------------------------------------------
   --  Inserting an entry
   ---------------------------------------------------------------------

   function Moved (Index, Place : Int32) return Int32 is
     (if Index >= Place then Index + 1 else Index)
   with Pre => Index < Int32'Last;
   --  Where entry Index goes when an entry is inserted at Place.

   procedure Lemma_Moved_Links
     (Tree  : Ks_Coordinate_Space_Tree;
      R     : Ks_Coordinate_Space_Tree;
      Place : Int32)
   with
     Ghost,
     Pre  => Valid_Tree (Tree)
             and then Tree.Count < Max_Spaces
             and then Place in 1 .. Tree.Count
             and then (for all I in 0 .. Place - 1
                       => R.Spaces (I).Name = Tree.Spaces (I).Name)
             and then (for all I in Place + 1 .. Tree.Count
                       => R.Spaces (I).Name = Tree.Spaces (I - 1).Name
                          and then R.Spaces (I).Parent
                                     = Moved (Tree.Spaces (I - 1).Parent,
                                              Place)),
     Post => (for all I in Place + 1 .. Tree.Count
              => R.Spaces (I).Parent in 0 .. I - 1
                 and then R.Spaces (I).Parent /= Place
                 and then Extends (R.Spaces (I).Name,
                                   R.Spaces (R.Spaces (I).Parent).Name));
   --  After the insertion at Place, every moved entry still extends the
   --  name of its (renumbered) parent.

   procedure Lemma_Moved_Links
     (Tree  : Ks_Coordinate_Space_Tree;
      R     : Ks_Coordinate_Space_Tree;
      Place : Int32) is
   begin
      for I in Place + 1 .. Tree.Count loop
         --  The parent is below Place, where R is Tree, or above it, where
         --  R is Tree moved up by one.
         pragma Assert
           (R.Spaces (R.Spaces (I).Parent).Name
              = Tree.Spaces (Tree.Spaces (I - 1).Parent).Name);
         pragma Loop_Invariant
           (for all J in Place + 1 .. I
            => R.Spaces (J).Parent in 0 .. J - 1
               and then R.Spaces (J).Parent /= Place
               and then Extends (R.Spaces (J).Name,
                                 R.Spaces (R.Spaces (J).Parent).Name));
      end loop;
   end Lemma_Moved_Links;

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Init
     (Tree   : out Ks_Coordinate_Space_Tree;
      Status : out Ks_Status) is
   begin
      Tree := (others => <>);
      Set_Success (Status);
   end Init;

   procedure Add_Space
     (Tree               : in out Ks_Coordinate_Space_Tree;
      Parent_Space_Name  : Ks_Space_Name;
      New_Space_Name     : Ks_Space_Name;
      Parent_From_New    : KT.Ks_Transform_2D_Linear;
      Duplicate_Handling : Int32;
      Status             : out Ks_Status)
   is
      Operation : constant String := "Add_Space";
      Parent    : Int32;
   begin
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      elsif Duplicate_Handling not in Add_Space_Code then
         Set_Failure
           (Status, Failure_Bad_Parameter,
            Operation & ": Duplicate_Handling must be 0 (Duplicate_Is_Error),"
            & " 1 (Replace_Duplicate) or 2 (Ignore_Duplicate)");
         return;
      end if;
      Lookup (Tree, Parent_Space_Name, Operation, Parent, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if not Valid_New_Component (New_Space_Name) then
         Name_Failure (Status, Operation, "invalid space name component",
                       New_Space_Name);
         return;
      end if;
      Check_Transform (Parent_From_New, Operation, "Parent_From_New", Status);
      if not Succeeded (Status) then
         return;
      end if;
      pragma Assert (Fits (Tree.Spaces (Parent).Name));
      if New_Space_Name.Length
           > Max_Name_Length - 1 - Tree.Spaces (Parent).Name.Length
      then
         Set_Failure
           (Status, Failure_Bad_Parameter,
            Operation & ": the space name would be longer than 256 "
            & "characters");
         return;
      end if;

      declare
         Name  : Ks_Space_Name;
         Place : Int32 := Tree.Count;
         Found : Int32 := -1;
      begin
         Make_Child_Name (Tree.Spaces (Parent).Name, New_Space_Name, Name);
         pragma Assert (Extends (Name, Tree.Spaces (Parent).Name));
         Lemma_Parent_Less (Tree.Spaces (Parent).Name, Name);

         --  Children sort after their parent: search from there for the
         --  space itself or for the first name above it.
         for I in Parent + 1 .. Tree.Count - 1 loop
            if Same_Name (Tree.Spaces (I).Name, Name) then
               Found := I;
               exit;
            elsif not Less (Tree.Spaces (I).Name, Name) then
               Lemma_Less_Total (Tree.Spaces (I).Name, Name);
               Place := I;
               exit;
            end if;
            pragma Loop_Invariant (Found = -1 and then Place = Tree.Count);
            pragma Loop_Invariant
              (for all J in Parent + 1 .. I
               => Less (Tree.Spaces (J).Name, Name));
         end loop;

         if Found >= 0 then
            --  The space exists: keep it (and so its descendants).
            if Duplicate_Handling = Add_Space_Duplicate_Is_Error then
               Set_Failure
                 (Status, Failure_Bad_Parameter,
                  Operation & ": the space """ & Shown (Name)
                  & """ already exists");
            elsif Duplicate_Handling = Add_Space_Replace_Duplicate then
               Tree.Spaces (Found).Parent_From_Child := Parent_From_New;
            end if;
            return;
         elsif Tree.Count = Max_Spaces then
            Set_Failure
              (Status, Failure_Bad_Parameter,
               Operation & ": the tree already holds the maximum of 64 "
               & "spaces");
            return;
         end if;

         pragma Assert (Place in Parent + 1 .. Tree.Count);
         pragma Assert (Less (Tree.Spaces (Place - 1).Name, Name));
         pragma Assert
           (if Place < Tree.Count
            then Less (Name, Tree.Spaces (Place).Name));

         --  Insert the new space at Place: the entries from Place on move
         --  up by one, and so do parent indices that point to them.
         declare
            R : Ks_Coordinate_Space_Tree := Tree;
         begin
            for K in Place + 1 .. Tree.Count loop
               R.Spaces (K) :=
                 (Name              => Tree.Spaces (K - 1).Name,
                  Parent            =>
                    Moved (Tree.Spaces (K - 1).Parent, Place),
                  Parent_From_Child => Tree.Spaces (K - 1).Parent_From_Child);
               pragma Loop_Invariant (R.Count = Tree.Count);
               pragma Loop_Invariant (Valid_Root (R));
               --  Below Place, R is Tree.
               pragma Loop_Invariant
                 (for all I in 1 .. Place - 1
                  => R.Spaces (I).Parent in 0 .. I - 1
                     and then Valid_Link
                                (R.Spaces (I), R.Spaces (I - 1),
                                 R.Spaces (R.Spaces (I).Parent)));
               pragma Loop_Invariant
                 (Less (R.Spaces (Place - 1).Name, Name));
               pragma Loop_Invariant
                 (for all I in 0 .. Place - 1
                  => R.Spaces (I).Name = Tree.Spaces (I).Name);
               --  From Place + 1 to K, R is Tree moved up by one (stated
               --  field by field, which keeps each proof short).
               pragma Loop_Invariant
                 (for all I in Place + 1 .. K
                  => R.Spaces (I).Name = Tree.Spaces (I - 1).Name);
               pragma Loop_Invariant
                 (for all I in Place + 1 .. K
                  => R.Spaces (I).Parent
                       = Moved (Tree.Spaces (I - 1).Parent, Place));
               pragma Loop_Invariant
                 (for all I in Place + 1 .. K
                  => KT.Bounded (R.Spaces (I).Parent_From_Child));
               pragma Loop_Invariant (Less (Name, R.Spaces (Place + 1).Name));
               pragma Loop_Invariant
                 (for all I in Place + 2 .. K
                  => Less (R.Spaces (I - 1).Name, R.Spaces (I).Name));
               pragma Loop_Invariant
                 (if K < Tree.Count
                  then Less (R.Spaces (K).Name, Tree.Spaces (K).Name));
            end loop;
            R.Spaces (Place) :=
              (Name              => Name,
               Parent            => Parent,
               Parent_From_Child => Parent_From_New);
            R.Count := Tree.Count + 1;
            Lemma_Moved_Links (Tree, R, Place);
            --  Each region in turn: below Place, Place, the moved entries.
            pragma Assert
              (for all I in 1 .. Place - 1
               => R.Spaces (I).Parent in 0 .. I - 1
                  and then Valid_Link
                             (R.Spaces (I), R.Spaces (I - 1),
                              R.Spaces (R.Spaces (I).Parent)));
            pragma Assert
              (R.Spaces (Place).Parent in 0 .. Place - 1
               and then Valid_Link
                          (R.Spaces (Place), R.Spaces (Place - 1),
                           R.Spaces (R.Spaces (Place).Parent)));
            pragma Assert
              (for all I in Place + 1 .. R.Count - 1
               => KT.Bounded (R.Spaces (I).Parent_From_Child)
                  and then Less (R.Spaces (I - 1).Name, R.Spaces (I).Name));
            pragma Assert
              (for all I in 1 .. R.Count - 1
               => R.Spaces (I).Parent in 0 .. I - 1
                  and then Valid_Link
                             (R.Spaces (I), R.Spaces (I - 1),
                              R.Spaces (R.Spaces (I).Parent)));
            Tree := R;
         end;
      end;
   end Add_Space;

   procedure Change_Transform
     (Tree                  : in out Ks_Coordinate_Space_Tree;
      Child_Space_Name      : Ks_Space_Name;
      New_Parent_From_Child : KT.Ks_Transform_2D_Linear;
      Status                : out Ks_Status)
   is
      Operation : constant String := "Change_Transform";
      Index     : Int32;
   begin
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      elsif Is_Root_Name (Child_Space_Name) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": the root space ""@"" has no parent");
         return;
      end if;
      Lookup (Tree, Child_Space_Name, Operation, Index, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Lemma_Not_Root (Tree, Child_Space_Name, Index);
      Check_Transform
        (New_Parent_From_Child, Operation, "New_Parent_From_Child", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Tree.Spaces (Index).Parent_From_Child := New_Parent_From_Child;
   end Change_Transform;

   procedure Delete_Subtree
     (Tree       : in out Ks_Coordinate_Space_Tree;
      Space_Name : Ks_Space_Name;
      Status     : out Ks_Status)
   is
      Operation : constant String := "Delete_Subtree";
      Target    : Int32;
   begin
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      elsif Is_Root_Name (Space_Name) then
         Set_Failure (Status, Failure_Bad_Parameter,
                      Operation & ": the root space ""@"" cannot be deleted");
         return;
      end if;
      Lookup (Tree, Space_Name, Operation, Target, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Lemma_Not_Root (Tree, Space_Name, Target);

      --  Copy every entry that is neither the target nor one of its
      --  descendants (an entry after the target whose parent goes) into
      --  R, in order, renumbering the parent indices.
      declare
         type Flag_Array is array (Space_Index) of Boolean;
         type Map_Array is array (Space_Index) of Space_Index;
         Keep : Flag_Array := [others => False];
         Map  : Map_Array := [others => 0];
         R    : Ks_Coordinate_Space_Tree;
         W    : Int32 := 1;
      begin
         R.Spaces (0) := Tree.Spaces (0);
         Keep (0) := True;
         for I in 1 .. Tree.Count - 1 loop
            if I = Target
              or else (I > Target and then not Keep (Tree.Spaces (I).Parent))
            then
               if I + 1 < Tree.Count then
                  Lemma_Less_Transitive
                    (R.Spaces (W - 1).Name, Tree.Spaces (I).Name,
                     Tree.Spaces (I + 1).Name);
               end if;
            else
               --  The parent is kept (below the target every entry is,
               --  above it the test says so), and copied already.
               pragma Assert (Keep (Tree.Spaces (I).Parent));
               pragma Assert
                 (Extends (Tree.Spaces (I).Name,
                           R.Spaces (Map (Tree.Spaces (I).Parent)).Name));
               Keep (I) := True;
               Map (I) := W;
               R.Spaces (W) :=
                 (Name              => Tree.Spaces (I).Name,
                  Parent            => Map (Tree.Spaces (I).Parent),
                  Parent_From_Child => Tree.Spaces (I).Parent_From_Child);
               W := W + 1;
            end if;
            pragma Loop_Invariant
              (for all J in I + 1 .. Space_Index'Last => not Keep (J));
            pragma Loop_Invariant (W in 1 .. I + 1);
            pragma Loop_Invariant (if I >= Target then W <= I);
            pragma Loop_Invariant (Keep (0) and then Map (0) = 0);
            pragma Loop_Invariant (Valid_Root (R));
            pragma Loop_Invariant
              (for all J in 1 .. I => (if J < Target then Keep (J)));
            pragma Loop_Invariant
              (for all J in 0 .. I
               => (if Keep (J)
                   then Map (J) in 0 .. W - 1
                        and then R.Spaces (Map (J)).Name
                                   = Tree.Spaces (J).Name));
            pragma Loop_Invariant
              (for all K in 1 .. W - 1
               => R.Spaces (K).Parent in 0 .. K - 1
                  and then Valid_Link
                             (R.Spaces (K), R.Spaces (K - 1),
                              R.Spaces (R.Spaces (K).Parent)));
            pragma Loop_Invariant (Fits (R.Spaces (W - 1).Name));
            pragma Loop_Invariant
              (if I + 1 < Tree.Count
               then Less (R.Spaces (W - 1).Name, Tree.Spaces (I + 1).Name));
         end loop;
         R.Count := W;
         Tree := R;
      end;
   end Delete_Subtree;

   procedure Clear
     (Tree   : in out Ks_Coordinate_Space_Tree;
      Status : out Ks_Status) is
   begin
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Tree := (others => <>);
      Set_Success (Status);
   end Clear;

   procedure Space_Exists
     (Tree       : Ks_Coordinate_Space_Tree;
      Space_Name : Ks_Space_Name;
      Result     : out Int32;
      Status     : out Ks_Status)
   is
      Index : Int32 := -1;
   begin
      Result := False_Value;
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      if Fits (Space_Name) then
         Find (Tree, Space_Name, Index);
      end if;
      if Index >= 0 then
         Result := True_Value;
      end if;
      Set_Success (Status);
   end Space_Exists;

   procedure Space_Count
     (Tree   : Ks_Coordinate_Space_Tree;
      Result : out Int32;
      Status : out Ks_Status) is
   begin
      Result := 0;
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Result := Tree.Count;
      Set_Success (Status);
   end Space_Count;

   procedure Space_Name
     (Tree   : Ks_Coordinate_Space_Tree;
      Index  : Int32;
      Result : out Ks_Space_Name;
      Status : out Ks_Status) is
   begin
      Result := Empty_Name;
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      elsif Index not in 0 .. Tree.Count - 1 then
         Index_Failure (Status, "Space_Name", Index, Tree.Count);
         return;
      end if;
      Lemma_Name_Fits (Tree, Index);
      Result := Clean (Tree.Spaces (Index).Name);
      Set_Success (Status);
   end Space_Name;

   procedure Root_Name
     (Tree   : Ks_Coordinate_Space_Tree;
      Result : out Ks_Space_Name;
      Status : out Ks_Status) is
   begin
      Result := Empty_Name;
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Result := (Length => 1,
                 Text   => [1 => Root_Character, others => ASCII.NUL]);
      Set_Success (Status);
   end Root_Name;

   procedure Parent_Name
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : Ks_Space_Name;
      Pathname_Format : Int32;
      Result          : out Ks_Space_Name;
      Status          : out Ks_Status)
   is
      Operation : constant String := "Parent_Name";
      Index     : Int32;
   begin
      Result := Empty_Name;
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Check_Pathname_Format (Pathname_Format, Operation, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Lookup (Tree, Space_Name, Operation, Index, Status);
      if Succeeded (Status) and then Index >= 1 then
         Lemma_Name_Fits (Tree, Tree.Spaces (Index).Parent);
         --  The parent is not below the space: Partial gives its full
         --  name.
         Result := Format_Name
           (Tree.Spaces (Tree.Spaces (Index).Parent).Name,
            Tree.Spaces (Index).Name, Pathname_Format);
      end if;
   end Parent_Name;

   procedure Child_Names_Count
     (Tree       : Ks_Coordinate_Space_Tree;
      Space_Name : Ks_Space_Name;
      Result     : out Int32;
      Status     : out Ks_Status) is
   begin
      Result := 0;
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Member_Count (Tree, Space_Name, Children, "Child_Names", Result,
                    Status);
   end Child_Names_Count;

   procedure Child_Name
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : Ks_Space_Name;
      Pathname_Format : Int32;
      Index           : Int32;
      Result          : out Ks_Space_Name;
      Status          : out Ks_Status) is
   begin
      Result := Empty_Name;
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Member_Name (Tree, Space_Name, Pathname_Format, Children, Index,
                   "Child_Names", Result, Status);
   end Child_Name;

   procedure All_Child_Names_Count
     (Tree          : Ks_Coordinate_Space_Tree;
      Space_Name    : Ks_Space_Name;
      Children_Only : Int32;
      Result        : out Int32;
      Status        : out Ks_Status) is
   begin
      Result := 0;
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Check_Children_Only (Children_Only, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Member_Count (Tree, Space_Name, Kind_Of (Children_Only),
                    "All_Child_Names", Result, Status);
   end All_Child_Names_Count;

   procedure All_Child_Name
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : Ks_Space_Name;
      Pathname_Format : Int32;
      Children_Only   : Int32;
      Index           : Int32;
      Result          : out Ks_Space_Name;
      Status          : out Ks_Status) is
   begin
      Result := Empty_Name;
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Check_Children_Only (Children_Only, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Member_Name (Tree, Space_Name, Pathname_Format, Kind_Of (Children_Only),
                   Index, "All_Child_Names", Result, Status);
   end All_Child_Name;

   procedure Verify_Name
     (Tree            : Ks_Coordinate_Space_Tree;
      Space_Name      : Ks_Space_Name;
      Pathname_Format : Int32;
      Result          : out Int32;
      Found_Name      : out Ks_Space_Name;
      Status          : out Ks_Status)
   is
      Index : Int32 := -1;
   begin
      Result := False_Value;
      Found_Name := Empty_Name;
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Check_Pathname_Format (Pathname_Format, "Verify_Name", Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Fits (Space_Name) then
         Find (Tree, Space_Name, Index);
      end if;
      if Index >= 0 then
         Lemma_Name_Fits (Tree, Index);
         Result := True_Value;
         --  A space is not below itself: Partial gives its full name.
         Found_Name := Format_Name
           (Tree.Spaces (Index).Name, Tree.Spaces (Index).Name,
            Pathname_Format);
      end if;
   end Verify_Name;

   procedure Parent_From_Child_Transform
     (Tree       : Ks_Coordinate_Space_Tree;
      Space_Name : Ks_Space_Name;
      Result     : out KT.Ks_Transform_2D_Linear;
      Status     : out Ks_Status)
   is
      Index : Int32;
   begin
      Result := Identity;
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Lookup (Tree, Space_Name, "Parent_From_Child_Transform", Index,
              Status);
      if Succeeded (Status) and then Index >= 1 then
         Result := Tree.Spaces (Index).Parent_From_Child;
      end if;
   end Parent_From_Child_Transform;

   procedure Get_Transform
     (Tree            : Ks_Coordinate_Space_Tree;
      To_Space_Name   : Ks_Space_Name;
      From_Space_Name : Ks_Space_Name;
      Result          : out KT.Ks_Transform_2D_Linear;
      Status          : out Ks_Status)
   is
      Operation      : constant String := "Get_Transform";
      To_Index       : Int32;
      From_Index     : Int32;
      Root_From_From : KT.Ks_Transform_2D_Linear;
      Root_From_To   : KT.Ks_Transform_2D_Linear;
      To_From_Root   : KT.Ks_Transform_2D_Linear;
   begin
      Result := Identity;
      if not Valid_Tree (Tree) then
         Fail_Bad_Tree (Status);
         return;
      end if;
      Lookup (Tree, To_Space_Name, Operation, To_Index, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Lookup (Tree, From_Space_Name, Operation, From_Index, Status);
      if not Succeeded (Status) or else To_Index = From_Index then
         return;
      end if;
      Root_From (Tree, From_Index, Root_From_From, Status);
      if not Succeeded (Status) then
         return;
      elsif To_Index = 0 then
         --  The root needs no inverse.
         Result := Root_From_From;
         return;
      end if;
      Root_From (Tree, To_Index, Root_From_To, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KT.Invert (Root_From_To, To_From_Root, Status);
      if not Succeeded (Status) then
         Set_Failure
           (Status, Failure_Transform_Singular,
            Operation & ": the transform from """ & Shown (To_Space_Name)
            & """ to the root is not invertible");
         return;
      end if;
      KT.Compose (To_From_Root, Root_From_From, Result, Status);
   end Get_Transform;

   ---------------------------------------------------------------------
   --  For the Ada API
   ---------------------------------------------------------------------

   function Same_Tree (Left, Right : Ks_Coordinate_Space_Tree) return Boolean
   is
      use type KT.Ks_Transform_2D_Linear;
   begin
      if Left.Count /= Right.Count then
         return False;
      end if;
      for I in 0 .. Left.Count - 1 loop
         if not Same_Name (Left.Spaces (I).Name, Right.Spaces (I).Name)
           or else Left.Spaces (I).Parent /= Right.Spaces (I).Parent
           or else Left.Spaces (I).Parent_From_Child
                     /= Right.Spaces (I).Parent_From_Child
         then
            return False;
         end if;
      end loop;
      return True;
   end Same_Tree;

   procedure Check_Read_Header
     (Code, Count : Int32;
      Status      : out Ks_Status) is
   begin
      if Code /= Stream_Code then
         Set_Failure
           (Status, Failure_Image_File,
            "Ks_Coordinate_Space_Tree'Read: the stream does not hold a "
            & "coordinate space tree");
      elsif Count not in 1 .. Max_Spaces then
         Set_Failure
           (Status, Failure_Image_File,
            "Ks_Coordinate_Space_Tree'Read: a tree cannot hold"
            & Int32'Image (Count) & " spaces");
      else
         Set_Success (Status);
      end if;
   end Check_Read_Header;

   procedure Add_Read_Space
     (Tree              : in out Ks_Coordinate_Space_Tree;
      Name              : Ks_Space_Name;
      Parent_From_Child : KT.Ks_Transform_2D_Linear;
      Status            : out Ks_Status) is
   begin
      Add_Read_Space ("Ks_Coordinate_Space_Tree'Read", Tree, Name,
                      Parent_From_Child, Status);
   end Add_Read_Space;

   procedure Add_Read_Space
     (Operation         : String;
      Tree              : in out Ks_Coordinate_Space_Tree;
      Name              : Ks_Space_Name;
      Parent_From_Child : KT.Ks_Transform_2D_Linear;
      Status            : out Ks_Status)
   is
      Existing  : Int32;
      Split     : Natural := 0;
   begin
      if not Valid_Tree (Tree) then
         Set_Failure (Status, Failure_Image_File,
                      Operation & ": the tree being read is not valid");
         return;
      elsif not Fits (Name)
        or else Is_Root_Name (Name)
        or else not Well_Formed (Name)
      then
         Set_Failure
           (Status, Failure_Image_File,
            Operation & ": the space name """ & Shown (Name)
            & """ is not a path below ""@""");
         return;
      end if;
      Find (Tree, Name, Existing);
      if Existing >= 0 then
         Set_Failure
           (Status, Failure_Image_File,
            Operation & ": the space """ & Shown (Name)
            & """ appears twice");
         return;
      end if;
      --  The parent's name ends before the last separator.
      for I in reverse 2 .. Natural (Name.Length) loop
         if Name.Text (I) = Separator then
            Split := I;
            exit;
         end if;
         pragma Loop_Invariant (Split = 0);
      end loop;
      if Split = 0 then
         Set_Failure
           (Status, Failure_Image_File,
            Operation & ": the space name """ & Shown (Name)
            & """ is not a path below ""@""");
         return;
      end if;
      declare
         Last      : constant Natural := Natural (Name.Length);
         Parent    : Ks_Space_Name := (Length => Int32 (Split - 1),
                                       Text   => [others => ASCII.NUL]);
         Component : Ks_Space_Name := (Length => Int32 (Last - Split),
                                       Text   => [others => ASCII.NUL]);
         Inner     : Ks_Status;
      begin
         Parent.Text (1 .. Split - 1) := Name.Text (1 .. Split - 1);
         Component.Text (1 .. Last - Split) := Name.Text (Split + 1 .. Last);
         Add_Space (Tree, Parent, Component, Parent_From_Child,
                    Add_Space_Duplicate_Is_Error, Inner);
         if Succeeded (Inner) then
            Set_Success (Status);
         else
            Set_Failure
              (Status, Failure_Image_File,
               Operation & ": the space """ & Shown (Name)
               & """ cannot be added ("
               & String (Inner.Message (1 .. Natural (Inner.Length)))
               & ")");
         end if;
      end;
   end Add_Read_Space;

end AMV.Kernels.Coordinate_Spaces;
