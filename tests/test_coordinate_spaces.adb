--  Tests for AMV.Coordinate_Spaces (Ks_Coordinate_Space_Tree).

with Ada.Exceptions;
with Ada.Streams.Storage.Unbounded;
with Ada.Strings.Unbounded; use Ada.Strings.Unbounded;
with Interfaces;

with AMV;                   use AMV;
with AMV.Coordinate_Spaces; use AMV.Coordinate_Spaces;
with AMV.Misc;
with AMV.Transforms;        use AMV.Transforms;
with AMV_Test_Support;      use AMV_Test_Support;

procedure Test_Coordinate_Spaces is

   Pi  : constant := AMV.Misc.Pi;
   Tol : constant := 1.0E-9;

   procedure Check_Same_Matrix
     (Actual, Expected : Ks_Transform_2D_Linear;
      Tolerance        : Real;
      Description      : String)
   is
      A1, B1, C1, D1, X1, Y1 : Real;
      A2, B2, C2, D2, X2, Y2 : Real;
   begin
      Actual.Get_Matrix_Elements_Translation (A1, B1, C1, D1, X1, Y1);
      Expected.Get_Matrix_Elements_Translation (A2, B2, C2, D2, X2, Y2);
      Check_Near (A1, A2, Tolerance, Description & " A");
      Check_Near (B1, B2, Tolerance, Description & " B");
      Check_Near (C1, C2, Tolerance, Description & " C");
      Check_Near (D1, D2, Tolerance, Description & " D");
      Check_Near (X1, X2, Tolerance, Description & " Tx");
      Check_Near (Y1, Y2, Tolerance, Description & " Ty");
   end Check_Same_Matrix;

   procedure Check_Point
     (T           : Ks_Transform_2D_Linear;
      X, Y        : Real;
      EX, EY      : Real;
      Tolerance   : Real;
      Description : String)
   is
      MX, MY : Real;
   begin
      T.Map_Point (X, Y, MX, MY);
      Check_Near (MX, EX, Tolerance, Description & " x");
      Check_Near (MY, EY, Tolerance, Description & " y");
   end Check_Point;

   procedure Check_Relative_Point
     (T           : Ks_Transform_2D_Linear;
      X, Y        : Real;
      EX, EY      : Real;
      Description : String);
   --  Maps (X, Y) and checks each coordinate against a non-zero expected
   --  value within a relative 1.0E-14.

   procedure Check_Relative_Point
     (T           : Ks_Transform_2D_Linear;
      X, Y        : Real;
      EX, EY      : Real;
      Description : String)
   is
      MX, MY : Real;
   begin
      T.Map_Point (X, Y, MX, MY);
      Check (abs (MX / EX - 1.0) <= 1.0E-14,
             Description & " x: got" & Real'Image (MX) & ", expected"
             & Real'Image (EX));
      Check (abs (MY / EY - 1.0) <= 1.0E-14,
             Description & " y: got" & Real'Image (MY) & ", expected"
             & Real'Image (EY));
   end Check_Relative_Point;

   --  The test tree. Each T_X maps the parent's coordinates to the
   --  child's (the ground truth below maps points down with them); the
   --  tree is given P_X = T_X.Invert, which maps the child's coordinates
   --  into the parent's (Parent_From_New).
   --
   --     @
   --     +-- @\A            rigid, 0.5 rad, (10, 20)
   --     |   +-- @\A\B      similarity, scale 2, -0.3 rad, (1, -2)
   --     |   |   +-- @\A\B\D   scale 1.5, aspect 0.8, rot 0.2, skew 0.1
   --     |   +-- @\A\C      rigid, 1.2 rad, (-5, 0)
   --     |       +-- @\A\C\G   scale 0.5, mirrored y, (7, -3)
   --     +-- @\E            x scale 2, y mirror, (0, 7)
   --         +-- @\E\F      rigid, -0.8 rad, (2, 2)

   T_A : constant Ks_Transform_2D_Linear := Create_Rigid (0.5, 10.0, 20.0);
   T_B : constant Ks_Transform_2D_Linear :=
     Create_Similarity (2.0, -0.3, 1.0, -2.0);
   T_D : constant Ks_Transform_2D_Linear :=
     Create_Scaling_Aspect_Rotation_Skew_Translation
       (1.5, 0.8, 0.2, 0.1, 3.0, 4.0);
   T_C : constant Ks_Transform_2D_Linear := Create_Rigid (1.2, -5.0, 0.0);
   T_G : constant Ks_Transform_2D_Linear :=
     Create (0.5, 0.0, 0.0, -0.5, 7.0, -3.0);
   T_E : constant Ks_Transform_2D_Linear :=
     Create (2.0, 0.0, 0.0, -1.0, 0.0, 7.0);
   T_F : constant Ks_Transform_2D_Linear := Create_Rigid (-0.8, 2.0, 2.0);

   P_A : constant Ks_Transform_2D_Linear := T_A.Invert;
   P_B : constant Ks_Transform_2D_Linear := T_B.Invert;
   P_D : constant Ks_Transform_2D_Linear := T_D.Invert;
   P_C : constant Ks_Transform_2D_Linear := T_C.Invert;
   P_G : constant Ks_Transform_2D_Linear := T_G.Invert;
   P_E : constant Ks_Transform_2D_Linear := T_E.Invert;
   P_F : constant Ks_Transform_2D_Linear := T_F.Invert;

   procedure Build (Tree : in out Ks_Coordinate_Space_Tree) is
   begin
      Tree.Add_Space ("@", "A", P_A);
      Tree.Add_Space ("@\A", "B", P_B);
      Tree.Add_Space ("@\A\B", "D", P_D);
      Tree.Add_Space ("@\A", "C", P_C);
      Tree.Add_Space ("@\A\C", "G", P_G);
      Tree.Add_Space ("@", "E", P_E);
      Tree.Add_Space ("@\E", "F", P_F);
   end Build;

   --  Coordinates of one root point in every space of the test tree,
   --  computed only with Map_Point down each path (no inversion, no
   --  composition), as independent ground truth.
   type Space_Id is (Root, A, B, C, D, E, F, G);
   type Coordinates is array (Space_Id) of Real;

   function "+" (S : String) return Unbounded_String
     renames To_Unbounded_String;

   Space_Names : constant array (Space_Id) of Unbounded_String :=
     [Root => +"@",
      A    => +"@\A",
      B    => +"@\A\B",
      C    => +"@\A\C",
      D    => +"@\A\B\D",
      E    => +"@\E",
      F    => +"@\E\F",
      G    => +"@\A\C\G"];

   function Name_Of (Id : Space_Id) return String is
     (To_String (Space_Names (Id)));

   procedure Ground_Truth
     (Root_X, Root_Y : Real;
      X, Y           : out Coordinates;
      Use_T_B        : Ks_Transform_2D_Linear := T_B) is
   begin
      X := [others => 0.0];
      Y := [others => 0.0];
      X (Root) := Root_X;
      Y (Root) := Root_Y;
      T_A.Map_Point (X (Root), Y (Root), X (A), Y (A));
      Use_T_B.Map_Point (X (A), Y (A), X (B), Y (B));
      T_D.Map_Point (X (B), Y (B), X (D), Y (D));
      T_C.Map_Point (X (A), Y (A), X (C), Y (C));
      T_G.Map_Point (X (C), Y (C), X (G), Y (G));
      T_E.Map_Point (X (Root), Y (Root), X (E), Y (E));
      T_F.Map_Point (X (E), Y (E), X (F), Y (F));
   end Ground_Truth;

   procedure Check_All_Pairs
     (Tree        : Ks_Coordinate_Space_Tree;
      Description : String;
      Use_T_B     : Ks_Transform_2D_Linear := T_B)
   is
      Root_Points : constant array (1 .. 3, 1 .. 2) of Real :=
        [[0.0, 0.0], [13.5, -4.25], [-100.0, 37.0]];
      X, Y : Coordinates;
   begin
      for P in Root_Points'Range (1) loop
         Ground_Truth (Root_Points (P, 1), Root_Points (P, 2), X, Y,
                       Use_T_B);
         for To in Space_Id loop
            for From in Space_Id loop
               Check_Point
                 (Tree.Get_Transform (Name_Of (To), Name_Of (From)),
                  X (From), Y (From), X (To), Y (To), Tol,
                  Description & ": " & Name_Of (To) & " from "
                  & Name_Of (From) & ", point" & Integer'Image (P));
            end loop;
         end loop;
      end loop;
   end Check_All_Pairs;

   --------------------------------------------------------------------

   procedure Test_Default_Tree is
      Tree : Ks_Coordinate_Space_Tree;
   begin
      Section ("default tree");
      Check (Tree.Space_Count = 1, "only the root");
      Check (Tree.Space_Name (0) = "@", "index 0 is the root");
      Check (Tree.Space_Exists ("@"), "root exists");
      Check (not Tree.Space_Exists ("@\A"), "nothing else exists");
      Check (Tree.Parent_Name ("@") = "", "root has no parent");
      Check (Tree.Parent_Name ("@", None) = ""
             and then Tree.Parent_Name ("@", Partial) = "",
             "root has no parent in any format");
      Check (Tree.Root_Name = "@", "Root_Name");
      Check (Tree.Parent_From_Child_Transform ("@").Identity (0.0),
             "root transform is the identity");
      Check (Tree.Get_Transform ("@", "@").Identity (0.0),
             "root to root is the identity");
      Check (Tree.Child_Names ("@").Count = 0, "the root has no children");
      Check (Tree.All_Child_Names ("@").Count = 0,
             "the root has no descendants");
      Check (Tree.All_Child_Names ("@", Children_Only => False).Count = 1
             and then Tree.All_Child_Names
                        ("@", Children_Only => False).Item (0) = "@",
             "with the space itself, only the root");
      Check (Full_Space_Name ("@\A", "B") = "@\A\B", "Full_Space_Name");
      Check (Full_Space_Name ("x", "") = "x\", "Full_Space_Name no check");
   end Test_Default_Tree;

   procedure Test_Simple_Analytic is
      Tree : Ks_Coordinate_Space_Tree;
   begin
      Section ("simple analytic transforms");
      --  T1 is the root moved by -5 along x, T2 by -3 along y; R is turned
      --  a quarter turn back; S is T1 scaled down by 2.
      Tree.Add_Space ("@", "T1", Create (1.0, 0.0, 0.0, 1.0, -5.0, 0.0));
      Tree.Add_Space ("@", "T2", Create (1.0, 0.0, 0.0, 1.0, 0.0, -3.0));
      Tree.Add_Space ("@", "R", Create_Rigid (-Pi / 2.0, 0.0, 0.0));
      Tree.Add_Space ("@\T1", "S", Create (0.5, 0.0, 0.0, 0.5, 0.0, 0.0));
      Check_Same_Matrix (Tree.Get_Transform ("@", "@\T1"),
                         Create (1.0, 0.0, 0.0, 1.0, -5.0, 0.0), 0.0,
                         "root from child is the stored transform");
      Check_Same_Matrix (Tree.Get_Transform ("@\T1", "@"),
                         Create (1.0, 0.0, 0.0, 1.0, 5.0, 0.0), 0.0,
                         "child from root is the inverse");
      Check_Same_Matrix (Tree.Get_Transform ("@\T2", "@\T1"),
                         Create (1.0, 0.0, 0.0, 1.0, -5.0, 3.0), 0.0,
                         "sibling translations");
      Check_Point (Tree.Get_Transform ("@\R", "@"), 1.0, 0.0, 0.0, 1.0,
                   1.0E-15, "quarter turn child");
      Check_Point (Tree.Get_Transform ("@", "@\R"), 0.0, 1.0, 1.0, 0.0,
                   1.0E-15, "quarter turn back to root");
      --  Root = S / 2 - (5, 0).
      Check_Point (Tree.Get_Transform ("@", "@\T1\S"), 4.0, 6.0,
                   -3.0, 3.0, 0.0, "grandchild to root");
      Check_Point (Tree.Get_Transform ("@\T1\S", "@\T2"), 1.0, 4.0,
                   12.0, 2.0, 0.0, "cousin of a grandchild");
      Check (Tree.Get_Transform ("@\T1\S", "@\T1\S").Identity (0.0),
             "same space is exactly the identity");
   end Test_Simple_Analytic;

   procedure Test_Three_Levels is
      Tree : Ks_Coordinate_Space_Tree;
      X, Y : Coordinates;
   begin
      Section ("three level tree");
      Build (Tree);
      Check (Tree.Space_Count = 8, "eight spaces");
      for Id in Space_Id loop
         Check (Tree.Space_Exists (Name_Of (Id)),
                Name_Of (Id) & " exists");
      end loop;

      Check (Tree.Parent_Name ("@\A") = "@", "parent of A");
      Check (Tree.Parent_Name ("@\A\B") = "@\A", "parent of B");
      Check (Tree.Parent_Name ("@\A\B\D") = "@\A\B", "parent of D");
      Check (Tree.Parent_Name ("@\E\F") = "@\E", "parent of F");
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A\B\D"), P_D,
                         0.0, "stored transform of D");
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\E"), P_E,
                         0.0, "stored transform of E");

      Section ("three level tree, lexical order");
      declare
         Expected : constant array (Natural range <>) of Space_Id :=
           [Root, A, B, D, C, G, E, F];
      begin
         for I in Expected'Range loop
            Check (Tree.Space_Name (I) = Name_Of (Expected (I)),
                   "Space_Name (" & Natural'Image (I) & ") = "
                   & Name_Of (Expected (I)) & ", got " & Tree.Space_Name (I));
         end loop;
      end;

      Section ("three level tree, every pair");
      Check_All_Pairs (Tree, "pairs");

      Section ("three level tree, named relations");
      Ground_Truth (3.0, -7.0, X, Y);
      Check_Point (Tree.Get_Transform ("@\A\C", "@\A\B"), X (B), Y (B),
                   X (C), Y (C), Tol, "siblings C from B");
      Check_Point (Tree.Get_Transform ("@\A\B\D", "@\A\C\G"), X (G), Y (G),
                   X (D), Y (D), Tol, "cousins D from G");
      Check_Point (Tree.Get_Transform ("@\A\C\G", "@\A\B\D"), X (D), Y (D),
                   X (G), Y (G), Tol, "cousins G from D");
      Check_Point (Tree.Get_Transform ("@\A\B\D", "@\A"), X (A), Y (A),
                   X (D), Y (D), Tol, "descendant from ancestor");
      Check_Point (Tree.Get_Transform ("@\A", "@\A\B\D"), X (D), Y (D),
                   X (A), Y (A), Tol, "ancestor from descendant");
      Check_Point (Tree.Get_Transform ("@\E\F", "@\A\B\D"), X (D), Y (D),
                   X (F), Y (F), Tol, "different branches");

      --  Descending one level undoes the stored transform; climbing to the
      --  root is exactly the stored transforms composed from D up.
      Check_Same_Matrix (Tree.Get_Transform ("@\A\B", "@\A"), T_B, Tol,
                         "child from parent");
      Check_Same_Matrix (Tree.Get_Transform ("@\A", "@\A\B"), P_B, Tol,
                         "parent from child");
      Check_Same_Matrix (Tree.Get_Transform ("@\A\B\D", "@"),
                         T_D * T_B * T_A, Tol, "D from root");
      Check_Same_Matrix (Tree.Get_Transform ("@", "@\A\B\D"),
                         P_A * (P_B * (P_D * Identity)), 0.0,
                         "root from D, exactly");

      --  Chaining through an intermediate space.
      Check_Same_Matrix
        (Tree.Get_Transform ("@\E\F", "@\A\C")
         * Tree.Get_Transform ("@\A\C", "@\A\B\D"),
         Tree.Get_Transform ("@\E\F", "@\A\B\D"), Tol,
         "Get (F, C) * Get (C, D) = Get (F, D)");
      Check
        (Identity
           (Tree.Get_Transform ("@\A\C\G", "@\E\F")
            * Tree.Get_Transform ("@\E\F", "@\A\C\G"), Tol),
         "Get (G, F) * Get (F, G) = identity");
      for Id in Space_Id loop
         Check (Tree.Get_Transform (Name_Of (Id), Name_Of (Id))
                  .Identity (0.0),
                Name_Of (Id) & " to itself is the identity");
      end loop;

      Section ("names given as slices");
      declare
         Padded : constant String := "xx@\A\B\Dyy";
         Name_D : String renames Padded (3 .. 9);
         Name_B : String renames Padded (3 .. 7);
      begin
         Check (Name_D = "@\A\B\D", "slice sanity");
         Check (Tree.Space_Exists (Name_D), "slice exists");
         Check (Tree.Parent_Name (Name_D) = "@\A\B", "slice parent");
         Check_Point (Tree.Get_Transform (Name_D, Name_B), X (B), Y (B),
                      X (D), Y (D), Tol, "slice Get_Transform");
         Check (Tree.Child_Names (Name_B).Count = 1
                and then Tree.Child_Names (Name_B).Item (0) = "@\A\B\D",
                "slice Child_Names");
         declare
            Copy : Ks_Coordinate_Space_Tree := Tree;
         begin
            Copy.Add_Space (Name_B, "H", P_C);
            Check (Copy.Space_Exists ("@\A\B\H"), "Add_Space under slice");
            Check (Copy.Parent_Name ("@\A\B\H") = "@\A\B",
                   "parent of a space added under a slice");
            Check_Same_Matrix (Copy.Get_Transform ("@\A\B\H", "@\A\B"), T_C,
                               Tol, "transform under slice");
         end;
      end;
   end Test_Three_Levels;

   procedure Test_Replace_And_Remove is
      Tree  : Ks_Coordinate_Space_Tree;
      New_B : constant Ks_Transform_2D_Linear :=
        Create_Scaling_Aspect_Rotation_Skew_Translation
          (0.75, 1.25, 2.0, -0.4, -6.0, 9.0);
      New_P_B : constant Ks_Transform_2D_Linear := New_B.Invert;
   begin
      Section ("replace an existing space");
      Build (Tree);
      Tree.Add_Space ("@\A", "B", New_P_B);
      Check (Tree.Space_Count = 8, "replacement adds nothing");
      Check (Tree.Space_Exists ("@\A\B\D"), "descendant kept");
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A\B"), New_P_B,
                         0.0, "new transform stored");
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A\B\D"), P_D,
                         0.0, "descendant transform kept");
      Check (Tree.Parent_Name ("@\A\B\D") = "@\A\B",
             "descendant parent kept");
      Check_All_Pairs (Tree, "after Add_Space replacement", New_B);

      Build (Tree);  --  Re-adding everything restores the originals.
      Check (Tree.Space_Count = 8, "rebuild adds nothing");
      Check_All_Pairs (Tree, "after rebuild");

      Tree.Change_Transform ("@\A\B", New_P_B);
      Check (Tree.Space_Count = 8, "Change_Transform keeps count");
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A\B"), New_P_B,
                         0.0, "Change_Transform stores the transform");
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A\B\D"), P_D,
                         0.0, "Change_Transform keeps the descendants'");
      Check_All_Pairs (Tree, "after Change_Transform", New_B);

      Section ("delete a subtree");
      Build (Tree);
      Tree.Delete_Subtree ("@\A\B");
      Check (Tree.Space_Count = 6, "B and D removed");
      Check (not Tree.Space_Exists ("@\A\B"), "B gone");
      Check (not Tree.Space_Exists ("@\A\B\D"), "D gone");
      Check (Tree.Space_Exists ("@\A") and then Tree.Space_Exists ("@\A\C")
             and then Tree.Space_Exists ("@\A\C\G")
             and then Tree.Space_Exists ("@\E")
             and then Tree.Space_Exists ("@\E\F"),
             "the rest survives");
      declare
         X, Y : Coordinates;
      begin
         Ground_Truth (-2.0, 5.0, X, Y);
         Check_Point (Tree.Get_Transform ("@\A\C\G", "@\E\F"), X (F), Y (F),
                      X (G), Y (G), Tol, "survivors still map correctly");
      end;

      Tree.Delete_Subtree ("@\A");
      Check (Tree.Space_Count = 3, "deleting A takes C and G");
      Check (Tree.Space_Name (1) = "@\E"
             and then Tree.Space_Name (2) = "@\E\F",
             "E branch left");
      Check (Tree.Child_Names ("@").Count = 1
             and then Tree.Child_Names ("@").Item (0) = "@\E",
             "the root's children after the deletion");
      Tree.Delete_Subtree ("@\E\F");
      Check (Tree.Space_Count = 2, "leaf deleted");
      Check (Tree.Space_Exists ("@\E"), "leaf parent kept");
      Check (Tree.Child_Names ("@\E").Count = 0, "the parent has no child");

      Section ("delete with look-alike names");
      Tree.Clear;
      Check (Tree.Space_Count = 1, "Clear leaves only the root");
      Check (Tree.Space_Name (0) = "@", "Clear keeps the root");
      Tree.Add_Space ("@", "A", T_A);
      Tree.Add_Space ("@", "A B", T_B);   --  ' ' sorts before '\'
      Tree.Add_Space ("@", "AB", T_C);
      Tree.Add_Space ("@", "A!", T_C);
      Tree.Add_Space ("@\A", "x", T_D);
      Tree.Add_Space ("@\A\x", "y", T_E);
      Tree.Add_Space ("@\A B", "z", T_F);
      Check (Tree.Space_Count = 8, "look-alike tree size");
      Check (Tree.Space_Name (1) = "@\A" and then Tree.Space_Name (2) = "@\A B"
             and then Tree.Space_Name (3) = "@\A B\z"
             and then Tree.Space_Name (4) = "@\A!"
             and then Tree.Space_Name (5) = "@\AB"
             and then Tree.Space_Name (6) = "@\A\x"
             and then Tree.Space_Name (7) = "@\A\x\y",
             "lexical order of look-alikes");
      Tree.Delete_Subtree ("@\A");
      Check (Tree.Space_Count = 5, "only A, x and y deleted");
      Check (Tree.Space_Exists ("@\A B") and then Tree.Space_Exists ("@\AB")
             and then Tree.Space_Exists ("@\A!")
             and then Tree.Space_Exists ("@\A B\z"),
             "look-alike names survive");
      Check (not Tree.Space_Exists ("@\A\x\y"), "grandchild deleted");

      Section ("value semantics");
      Tree.Clear;
      Build (Tree);
      declare
         Copy : Ks_Coordinate_Space_Tree := Tree;
      begin
         Copy.Delete_Subtree ("@\A");
         Copy.Change_Transform ("@\E", P_A);
         Check (Tree.Space_Exists ("@\A\B\D"), "original keeps its spaces");
         Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\E"), P_E,
                            0.0, "original keeps its transforms");
         Check (Copy.Space_Count = 3, "copy changed");
      end;
   end Test_Replace_And_Remove;

   procedure Test_Errors is
      Tree      : Ks_Coordinate_Space_Tree;
      Name      : Unbounded_String;
      Parent    : Unbounded_String := +"@";
      Transform : Ks_Transform_2D_Linear;
      Index     : Natural := 0;
      Sink_T    : Ks_Transform_2D_Linear;

      procedure Do_Add is
      begin
         Tree.Add_Space (To_String (Parent), To_String (Name), Transform);
      end Do_Add;

      procedure Do_Delete is
      begin
         Tree.Delete_Subtree (To_String (Name));
      end Do_Delete;

      procedure Do_Change is
      begin
         Tree.Change_Transform (To_String (Name), Transform);
      end Do_Change;

      procedure Do_Get_To is
      begin
         Sink_T := Tree.Get_Transform (To_String (Name), "@");
      end Do_Get_To;

      procedure Do_Get_From is
      begin
         Sink_T := Tree.Get_Transform ("@", To_String (Name));
      end Do_Get_From;

      procedure Do_Parent is
      begin
         if Tree.Parent_Name (To_String (Name)) = "never" then
            Fail ("impossible parent");
         end if;
      end Do_Parent;

      procedure Do_Children is
      begin
         if Tree.Child_Names (To_String (Name)).Count = Natural'Last then
            Fail ("impossible children");
         end if;
      end Do_Children;

      procedure Do_All_Children is
      begin
         if Tree.All_Child_Names (To_String (Name), None, False).Count
              = Natural'Last
         then
            Fail ("impossible descendants");
         end if;
      end Do_All_Children;

      procedure Do_Parent_From_Child is
      begin
         Sink_T := Tree.Parent_From_Child_Transform (To_String (Name));
      end Do_Parent_From_Child;

      procedure Do_Space_Name is
      begin
         if Tree.Space_Name (Index) = "never" then
            Fail ("impossible name");
         end if;
      end Do_Space_Name;

      Bad_Name : constant Ada.Exceptions.Exception_Id :=
        Ks_Image_Bad_Selected_Space_Name_Exception'Identity;
      Singular : constant Ada.Exceptions.Exception_Id :=
        Ks_Transform_Singular_Exception'Identity;
      Bad_Parameter : constant Ada.Exceptions.Exception_Id :=
        Ks_Bad_Parameter_Exception'Identity;

      function Tiny return Real is (1.0E-160);
      --  A function, so products with it are not static (a static
      --  subnormal value draws a warning).

      procedure Add_Bad_Name is new Check_Raises_Exactly (Do_Add, Bad_Name);
      procedure Add_Singular is new Check_Raises_Exactly (Do_Add, Singular);
      procedure Delete_Bad_Name is new Check_Raises_Exactly
        (Do_Delete, Bad_Name);
      procedure Delete_Bad_Parameter is new Check_Raises_Exactly
        (Do_Delete, Bad_Parameter);
      procedure Change_Bad_Name is new Check_Raises_Exactly
        (Do_Change, Bad_Name);
      procedure Change_Bad_Parameter is new Check_Raises_Exactly
        (Do_Change, Bad_Parameter);
      procedure Change_Singular is new Check_Raises_Exactly
        (Do_Change, Singular);
      procedure Get_To_Bad_Name is new Check_Raises_Exactly
        (Do_Get_To, Bad_Name);
      procedure Get_From_Bad_Name is new Check_Raises_Exactly
        (Do_Get_From, Bad_Name);
      procedure Get_To_Singular is new Check_Raises_Exactly
        (Do_Get_To, Singular);
      procedure Parent_Bad_Name is new Check_Raises_Exactly
        (Do_Parent, Bad_Name);
      procedure Children_Bad_Name is new Check_Raises_Exactly
        (Do_Children, Bad_Name);
      procedure All_Children_Bad_Name is new Check_Raises_Exactly
        (Do_All_Children, Bad_Name);
      procedure Parent_From_Child_Bad_Name is new Check_Raises_Exactly
        (Do_Parent_From_Child, Bad_Name);
      procedure Space_Name_Out_Of_Range is new Check_Raises_Exactly
        (Do_Space_Name, Constraint_Error'Identity);

      Bad_Components : constant array (1 .. 7) of Unbounded_String :=
        [+"", +"a\b", +"\",
         +"@", +"#", +".",
         +"Part\"];
      Good_Components : constant array (1 .. 6) of Unbounded_String :=
        [+"..", +"@@", +"#1",
         +"a.b", +" ", +"Fixture 2"];
      Bad_Names : constant array (1 .. 12) of Unbounded_String :=
        [+"", +"#", +".",
         +"A", +"@\", +"@\\A",
         +"@\A\", +"@A", +"\A",
         +"@\Nope", +"@\A\Nope",
         +"@\a"];
   begin
      Section ("errors: bad components");
      Build (Tree);
      Transform := T_B;
      Parent := +"@\A";
      for Component of Bad_Components loop
         Name := Component;
         Add_Bad_Name
           ("Add_Space component """ & To_String (Component) & """");
      end loop;
      Check (Tree.Space_Count = 8, "failed adds change nothing");
      for Component of Good_Components loop
         Name := Component;
         Do_Add;
         Check (Tree.Space_Exists ("@\A\" & To_String (Component)),
                "component """ & To_String (Component) & """ is accepted");
      end loop;
      Check (Tree.Space_Count = 8 + Good_Components'Length,
             "good components added");

      Section ("errors: bad names");
      Tree.Clear;
      Build (Tree);
      for Bad of Bad_Names loop
         Name := Bad;
         Check (not Tree.Space_Exists (To_String (Bad)),
                "Space_Exists """ & To_String (Bad) & """ is False");
         declare
            Found : Unbounded_String := +"stale";
         begin
            Check (not Tree.Verify_Name (To_String (Bad), Full, Found)
                   and then Found = "",
                   "Verify_Name """ & To_String (Bad) & """ is False");
         end;
         Delete_Bad_Name ("Delete_Subtree """ & To_String (Bad) & """");
         Change_Bad_Name ("Change_Transform """ & To_String (Bad) & """");
         Get_To_Bad_Name ("Get_Transform to """ & To_String (Bad) & """");
         Get_From_Bad_Name ("Get_Transform from """ & To_String (Bad) & """");
         Parent_Bad_Name ("Parent_Name """ & To_String (Bad) & """");
         Children_Bad_Name ("Child_Names """ & To_String (Bad) & """");
         All_Children_Bad_Name
           ("All_Child_Names """ & To_String (Bad) & """");
         Parent_From_Child_Bad_Name
           ("Parent_From_Child_Transform """ & To_String (Bad) & """");
         Parent := Bad;
         Name := +"Fine";
         Add_Bad_Name ("Add_Space under """ & To_String (Bad) & """");
      end loop;
      Check (Tree.Space_Count = 8, "failed calls change nothing");

      Section ("errors: root");
      Name := +"@";
      Transform := T_A;
      Delete_Bad_Parameter ("Delete_Subtree root");
      Change_Bad_Parameter ("Change_Transform root");
      Check (Tree.Space_Count = 8, "root errors change nothing");

      Section ("errors: singular transforms");
      Parent := +"@\A";
      Name := +"New";
      Transform := Create (1.0, 2.0, 2.0, 4.0, 0.0, 0.0);
      Add_Singular ("Add_Space with a rank one transform");
      Check (not Tree.Space_Exists ("@\A\New"), "singular add not stored");
      Name := +"B";
      Add_Singular ("Add_Space replacing with a singular transform");
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A\B"), P_B,
                         0.0, "failed replacement keeps the transform");
      Name := +"@\A\B";
      Transform := Create (0.0, 0.0, 0.0, 0.0, 1.0, 1.0);
      Change_Singular ("Change_Transform with a zero matrix");
      --  An inverse beyond Real'Last (2.0E308), built at run time since
      --  subnormal literals draw a warning.
      Transform := Create (Tiny * 5.0E-149, 0.0, 0.0, Tiny * 5.0E-149,
                           0.0, 0.0);
      Change_Singular ("Change_Transform with an inverse that overflows");
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A\B"), P_B,
                         0.0, "failed change keeps the transform");
      Name := +"New";
      Transform := Create (1.0, 1.0, 1.0, 1.0, 0.0, 0.0);
      Add_Singular ("Add_Space with a rank one transform");
      Check (not Tree.Space_Exists ("@\A\New"),
             "singular add not stored");
      Name := +"@\A\B";
      --  Entries up to 1.0E150 are accepted (AMV.Transforms).
      Transform := Create (1.0E140, 0.0, 0.0, 1.0E140, 0.0, 0.0);
      begin
         Do_Change;
         Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A\B"),
                            Transform, 0.0,
                            "Change_Transform accepts diag (1.0E140)");
         Check_Point (Tree.Get_Transform ("@\A\B", "@\A"), 3.0E139,
                      -4.0E139, 0.3, -0.4, 1.0E-12,
                      "Get_Transform inverts diag (1.0E140)");
      exception
         when E : others =>
            Fail ("Change_Transform with diag (1.0E140) raised "
                  & Ada.Exceptions.Exception_Name (E));
      end;
      Tree.Change_Transform ("@\A\B", P_B);
      --  Beyond that bound a transform is a bad parameter.
      declare
         procedure Change_Huge is
         begin
            Tree.Change_Transform
              ("@\A\B", Create (1.0E200, 0.0, 0.0, 1.0E200, 0.0, 0.0));
         end Change_Huge;
         procedure Check_Huge is new Check_Raises_Exactly
           (Change_Huge, Ks_Bad_Parameter_Exception'Identity);
      begin
         Check_Huge ("Change_Transform with diag (1.0E200)");
         Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A\B"),
                            P_B, 0.0, "rejected change keeps the transform");
      end;

      --  Each transform alone is invertible, the inverse of their
      --  product (1.0E160) is beyond the bound of 1.0E150: Get_Transform
      --  inverts the transform to the root from its To space.
      Tree.Clear;
      Tree.Add_Space ("@", "S1", Create (1.0E-80, 0.0, 0.0, 1.0E-80,
                                         0.0, 0.0));
      Tree.Add_Space ("@\S1", "S2", Create (1.0E-80, 0.0, 0.0, 1.0E-80,
                                            0.0, 0.0));
      Name := +"@\S1\S2";
      Get_To_Singular ("inverse of the composed transform too large");
      --  As the From space it needs no inverse, and one level is fine.
      begin
         Check_Relative_Point
           (Tree.Get_Transform ("@", "@\S1\S2"), 1.0E140, 3.0E140,
            1.0E-20, 3.0E-20, "root from two levels of diag (1.0E-80)");
         Check_Relative_Point
           (Tree.Get_Transform ("@\S1", "@"), 1.0, 1.0, 1.0E80, 1.0E80,
            "diag (1.0E-80) child from root");
      exception
         when E : others =>
            Fail ("Get_Transform with diag (1.0E-80) spaces raised "
                  & Ada.Exceptions.Exception_Name (E));
      end;

      Section ("errors: Space_Name index");
      Tree.Clear;
      Build (Tree);
      Index := 8;
      Space_Name_Out_Of_Range ("Space_Name (Space_Count)");
      Index := Natural'Last;
      Space_Name_Out_Of_Range ("Space_Name (Natural'Last)");
      Index := 7;
      Do_Space_Name;
      Check (Tree.Space_Name (7) = "@\E\F", "last valid index");

      --  The harness procedures work on valid names too.
      Name := +"@\E";
      Do_Get_From;
      Check_Same_Matrix (Sink_T, P_E, 0.0, "Get_Transform (root, E)");
      Do_Parent_From_Child;
      Check_Same_Matrix (Sink_T, P_E, 0.0, "Parent_From_Child (E)");
   end Test_Errors;

   procedure Test_Extreme_Chains is
      Tree : Ks_Coordinate_Space_Tree;
      To   : Unbounded_String;
      From : Unbounded_String;

      procedure Do_Get is
      begin
         if Tree.Get_Transform (To_String (To), To_String (From))
              .Translation_X = Real'Last
         then
            Fail ("impossible transform");
         end if;
      end Do_Get;

      procedure Get_Overflows is new Check_Raises_Exactly
        (Do_Get, Ks_Bad_Parameter_Exception'Identity);
      procedure Get_Singular is new Check_Raises_Exactly
        (Do_Get, Ks_Transform_Singular_Exception'Identity);

      Up   : constant Ks_Transform_2D_Linear :=
        Create (1.0E49, 0.0, 0.0, 1.0E49, 0.0, 0.0);
      Down : constant Ks_Transform_2D_Linear :=
        Create (1.0E-49, 0.0, 0.0, 1.0E-49, 0.0, 0.0);
   begin
      Section ("extreme scalings along a path");
      --  Coordinates grow by 1.0E49 at each level of S (whose spaces map
      --  into their parents with Down) and shrink by 1.0E49 at each level
      --  of U and in M1 (which map with Up).
      Tree.Add_Space ("@", "S1", Down);
      Tree.Add_Space ("@\S1", "S2", Down);
      Tree.Add_Space ("@\S1\S2", "S3", Down);
      Tree.Add_Space ("@\S1\S2\S3", "S4", Down);
      Tree.Add_Space ("@", "U1", Up);
      Tree.Add_Space ("@\U1", "U2", Up);
      Tree.Add_Space ("@\U1\U2", "U3", Up);
      Tree.Add_Space ("@\U1\U2\U3", "U4", Up);
      Tree.Add_Space ("@", "M1", Up);
      --  Two and three levels: the composed scalings 1.0E98 and 1.0E147
      --  (near the bound of 1.0E150 of AMV.Transforms) invert.
      begin
         Check_Relative_Point
           (Tree.Get_Transform ("@", "@\S1\S2"), 1.0E98, -2.0E98,
            1.0, -2.0, "root from two levels of 1.0E49");
         Check_Relative_Point
           (Tree.Get_Transform ("@", "@\S1\S2\S3"), 1.0E147, 3.0E147,
            1.0, 3.0, "root from three levels of 1.0E49");
         Check_Relative_Point
           (Tree.Get_Transform ("@\S1\S2\S3", "@"), 1.0, 3.0,
            1.0E147, 3.0E147, "three levels of 1.0E49 from root");
         Check_Relative_Point
           (Tree.Get_Transform ("@\U1\U2\U3", "@"), 1.0E147, 3.0E147,
            1.0, 3.0, "three levels of 1.0E-49 from root");
         --  Four levels down need no inverse as the From side.
         Check_Relative_Point
           (Tree.Get_Transform ("@", "@\S1\S2\S3\S4"), 1.0E140, 2.0E140,
            1.0E-56, 2.0E-56, "root from four levels of 1.0E49");
      exception
         when E : others =>
            Fail ("extreme but representable chain raised "
                  & Ada.Exceptions.Exception_Name (E));
      end;
      --  Composing past the bound of 1.0E150 is a bad parameter, on
      --  either side of the path and in the final composition.
      To := +"@";
      From := +"@\U1\U2\U3\U4";
      Get_Overflows ("From side composes to 1.0E196");
      To := +"@\U1\U2\U3\U4";
      From := +"@";
      Get_Overflows ("To side composes to 1.0E196");
      To := +"@\S1\S2\S3";
      From := +"@\M1";
      Get_Overflows ("final composition 1.0E147 * 1.0E49");
      --  A To side within the bound whose inverse is not.
      To := +"@\S1\S2\S3\S4";
      From := +"@";
      Get_Singular ("To side 1.0E-196 cannot be inverted");
   end Test_Extreme_Chains;

   procedure Test_Deep_Trees is

      --  Makes Tree the chain @\C\C\...\C of Depth spaces, each mapped
      --  into its parent by Step, and returns the deepest name.
      --  Get_Transform between the deepest space and the root is checked
      --  against a walk that maps one point of the deepest space up the
      --  chain with Map_Point, level by level.
      procedure Check_Chain
        (Tree        : in out Ks_Coordinate_Space_Tree;
         Depth       : Positive;
         Component   : String;
         Step        : Ks_Transform_2D_Linear;
         Description : String;
         Deepest     : out Unbounded_String)
      is
         Name   : Unbounded_String := +"@";
         Deep_X : constant Real := 1.5;
         Deep_Y : constant Real := -2.5;
         X      : Real := Deep_X;
         Y      : Real := Deep_Y;
         NX, NY : Real;
      begin
         Tree.Clear;
         for Level in 1 .. Depth loop
            Tree.Add_Space (To_String (Name), Component, Step);
            Append (Name, Space_Separator & Component);
            Step.Map_Point (X, Y, NX, NY);
            X := NX;
            Y := NY;
         end loop;
         --  (X, Y) is now (Deep_X, Deep_Y) of the deepest space in root
         --  coordinates.
         Deepest := Name;
         Check (Tree.Space_Count = Depth + 1, Description & ": size");
         Check (Length (Name) = 1 + Depth * (1 + Component'Length),
                Description & ": name length");
         Check (Tree.Parent_Name (To_String (Name))'Length
                  = Length (Name) - 1 - Component'Length,
                Description & ": parent of the deepest space");
         Check (Tree.Parent_Name (To_String (Name), None) = Component,
                Description & ": its last component");
         Check (Tree.All_Child_Names ("@").Count = Depth,
                Description & ": the root's descendants");
         begin
            Check_Point (Tree.Get_Transform ("@", To_String (Name)),
                         Deep_X, Deep_Y, X, Y, 1.0E-9,
                         Description & ": root from deepest");
            Check_Point (Tree.Get_Transform (To_String (Name), "@"),
                         X, Y, Deep_X, Deep_Y, 1.0E-9,
                         Description & ": deepest from root");
         exception
            when E : others =>
               Fail (Description & ": Get_Transform raised "
                     & Ada.Exceptions.Exception_Name (E) & ": "
                     & Ada.Exceptions.Exception_Message (E));
         end;
      end Check_Chain;

      Tree    : Ks_Coordinate_Space_Tree;
      Deepest : Unbounded_String;
      Parent  : Unbounded_String;
      Child   : Unbounded_String;

      procedure Do_Add is
      begin
         Tree.Add_Space (To_String (Parent), To_String (Child), T_A);
      end Do_Add;

      procedure Add_Too_Much is new Check_Raises_Exactly
        (Do_Add, Ks_Bad_Parameter_Exception'Identity);

      procedure Check_Rejected (Description : String) is
         Before : constant Ks_Coordinate_Space_Tree := Tree;
      begin
         Add_Too_Much (Description & " raises Ks_Bad_Parameter_Exception");
         Check (Tree = Before, Description & ": the tree is unchanged");
         Check (not Tree.Space_Exists
                       (Full_Space_Name (To_String (Parent),
                                         To_String (Child))),
                Description & ": no such space");
      end Check_Rejected;

      C   : constant array (1 .. 5) of Ks_Transform_2D_Linear :=
        [Create_Rigid (0.3, 1.0, -2.0),
         Create_Scaling_Aspect_Rotation_Skew_Translation
           (1.7, 0.6, -1.1, 0.25, 0.5, 4.0),
         Create_Similarity (0.37, 2.9, -7.0, 3.0),
         Create (0.9, -0.3, 0.45, 1.3, 2.0, 2.5),
         Create_Rigid (-2.2, -0.125, 6.0)];
      C50 : constant String (1 .. 50) := [others => 'n'];
   begin
      Section ("trees at the limits: 64 spaces");
      --  The longest chain: the root and 63 levels fill the tree.
      Check_Chain (Tree, 63, "x", Create_Rigid (0.001, 0.01, -0.02),
                   "63 levels", Deepest);
      Check (Tree.Space_Count = 64, "a full tree holds 64 spaces");
      Parent := +"@";
      Child := +"y";
      Check_Rejected ("a 65th space beside the chain");
      Parent := Deepest;
      Child := +"x";
      Check_Rejected ("a 65th space below the deepest");
      --  Replacing the transform of an existing space needs no room, and
      --  neither does ignoring a duplicate.
      Tree.Add_Space ("@", "x", T_B);
      Check (Tree.Space_Count = 64, "replacing in a full tree keeps 64");
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\x"), T_B, 0.0,
                         "replacing in a full tree");
      Tree.Add_Space ("@", "x", T_C, Ignore_Duplicate);
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\x"), T_B, 0.0,
                         "ignoring a duplicate in a full tree");
      Tree.Change_Transform ("@\x", T_D);
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\x"), T_D, 0.0,
                         "Change_Transform in a full tree");
      Tree.Delete_Subtree (To_String (Deepest));
      Tree.Add_Space ("@", "y", T_C);
      Check (Tree.Space_Count = 64 and then Tree.Space_Exists ("@\y"),
             "a space fits again after a deletion");

      Section ("trees at the limits: 256-character names");
      --  The longest names: five levels of 50 characters make 256.
      Check_Chain (Tree, 5, C50, Create_Rigid (-0.002, 0.03, 0.01),
                   "5 levels of 50 characters", Deepest);
      Check (Length (Deepest) = 256, "the deepest name has 256 characters");
      Check (Tree.Space_Exists (To_String (Deepest)),
             "a 256-character name exists");
      Parent := Deepest;
      Child := +"z";
      Check_Rejected ("a child of a 256-character name");
      Parent := +"@";
      Child := +[1 .. 254 => 'w'];
      Do_Add;
      Check (Tree.Space_Exists ("@\" & To_String (Child)),
             "a 254-character component under the root fits");
      Child := +[1 .. 255 => 'v'];
      Check_Rejected ("a 255-character component under the root");
      Child := +[1 .. 300 => 'u'];
      Check_Rejected ("a 300-character component under the root");
      declare
         Long_Name : constant String := To_String (Deepest) & "x";

         procedure Get_Long is
         begin
            if Tree.Get_Transform (Long_Name, "@").Translation_X = Real'Last
            then
               Fail ("impossible transform");
            end if;
         end Get_Long;

         procedure Get_Long_Bad_Name is new Check_Raises_Exactly
           (Get_Long, Ks_Image_Bad_Selected_Space_Name_Exception'Identity);
      begin
         Check (not Tree.Space_Exists (Long_Name),
                "Space_Exists of a 257-character name is False");
         Get_Long_Bad_Name ("Get_Transform of a 257-character name");
      end;

      Section ("composition order along a path");
      Tree.Clear;
      --  Space to root is C1 * (C2 * (C3 * (C4 * (C5 * Identity)))),
      --  grouped from the space up, exactly.
      Tree.Add_Space ("@", "P1", C (1));
      Tree.Add_Space ("@\P1", "P2", C (2));
      Tree.Add_Space ("@\P1\P2", "P3", C (3));
      Tree.Add_Space ("@\P1\P2\P3", "P4", C (4));
      Tree.Add_Space ("@\P1\P2\P3\P4", "P5", C (5));
      Check_Same_Matrix
        (Tree.Get_Transform ("@", "@\P1\P2\P3\P4\P5"),
         C (1) * (C (2) * (C (3) * (C (4) * (C (5) * Identity)))), 0.0,
         "grouped from the space up");
      --  The grouping keeps the partial products in range here, where
      --  grouping from the root down would reach 1.0E300.
      Tree.Clear;
      Tree.Add_Space ("@", "Q1", Create (1.0E150, 0.0, 0.0, 1.0E150,
                                         0.0, 0.0));
      Tree.Add_Space ("@\Q1", "Q2", Create (1.0E150, 0.0, 0.0, 1.0E150,
                                            0.0, 0.0));
      Tree.Add_Space ("@\Q1\Q2", "Q3", Create (1.0E150, 0.0, 0.0, 1.0E150,
                                               0.0, 0.0));
      Tree.Add_Space ("@\Q1\Q2\Q3", "Q4",
                      Create (1.0E-150, 0.0, 0.0, 1.0E-150, 0.0, 0.0));
      Tree.Add_Space ("@\Q1\Q2\Q3\Q4", "Q5",
                      Create (1.0E-150, 0.0, 0.0, 1.0E-150, 0.0, 0.0));
      begin
         Check_Relative_Point
           (Tree.Get_Transform ("@", "@\Q1\Q2\Q3\Q4\Q5"), 0.5, -0.25,
            5.0E149, -2.5E149, "scales 1E150 x 3, 1E-150, 1E-150");
      exception
         when E : others =>
            Fail ("scales 1E150 x 3, 1E-150, 1E-150 raised "
                  & Ada.Exceptions.Exception_Name (E));
      end;
   end Test_Deep_Trees;

   procedure Test_High_Bounds is
      --  Names are ordinary Strings, so their bounds may end at (or next
      --  to) Integer'Last. Index arithmetic past 'Last used to overflow.
      Tree : Ks_Coordinate_Space_Tree;

      A1_Last : constant String (Integer'Last - 3 .. Integer'Last) := "@\A1";
      A1_Next : constant String (Integer'Last - 4 .. Integer'Last - 1) :=
        "@\A1";
      B2_Last : constant String (Integer'Last - 6 .. Integer'Last) :=
        "@\A1\B2";
      A1_Ten  : constant String (Integer'Last - 13 .. Integer'Last - 10) :=
        "@\A1";
      Trailing_Last : constant String (Integer'Last - 4 .. Integer'Last) :=
        "@\A1\";
      Trailing_Next : constant String
        (Integer'Last - 5 .. Integer'Last - 1) := "@\A1\";
      Pixel_Last : constant String (Integer'Last - 2 .. Integer'Last) :=
        "@\#";
      Empty_Last : constant String (Integer'Last - 4 .. Integer'Last) :=
        "@\\A1";

      New_A1 : constant Ks_Transform_2D_Linear := Create_Rigid (0.7, 1.0, 2.0);
      Long_Component : constant String := "A_Child_Name_Of_23_Chars";

      Bad   : Unbounded_String;
      Which : Natural := 0;

      --  Each bad-name action works on a copy with the bounds of the
      --  malformed name selected by Which.
      function Bad_Name return String is
        (case Which is
            when 1 => Trailing_Last,
            when 2 => Trailing_Next,
            when 3 => Pixel_Last,
            when others => Empty_Last);

      procedure Do_Get_To is
      begin
         if Tree.Get_Transform (Bad_Name, "@").Translation_X = Real'Last
         then
            Fail ("impossible transform");
         end if;
      end Do_Get_To;

      procedure Do_Get_From is
      begin
         if Tree.Get_Transform ("@", Bad_Name).Translation_X = Real'Last
         then
            Fail ("impossible transform");
         end if;
      end Do_Get_From;

      procedure Do_Parent is
      begin
         if Tree.Parent_Name (Bad_Name) = "never" then
            Fail ("impossible parent");
         end if;
      end Do_Parent;

      procedure Do_Add_Under is
      begin
         Tree.Add_Space (Bad_Name, "X", New_A1);
      end Do_Add_Under;

      procedure Do_Delete is
      begin
         Tree.Delete_Subtree (Bad_Name);
      end Do_Delete;

      Bad_Name_Id : constant Ada.Exceptions.Exception_Id :=
        Ks_Image_Bad_Selected_Space_Name_Exception'Identity;

      procedure Get_To_Bad is new Check_Raises_Exactly
        (Do_Get_To, Bad_Name_Id);
      procedure Get_From_Bad is new Check_Raises_Exactly
        (Do_Get_From, Bad_Name_Id);
      procedure Parent_Bad is new Check_Raises_Exactly
        (Do_Parent, Bad_Name_Id);
      procedure Add_Under_Bad is new Check_Raises_Exactly
        (Do_Add_Under, Bad_Name_Id);
      procedure Delete_Bad is new Check_Raises_Exactly
        (Do_Delete, Bad_Name_Id);

      procedure Check_Name (Name : String; Description : String) is
      begin
         Check (Tree.Space_Exists (Name), Description & ": Space_Exists");
         Check (Tree.Parent_Name (Name) = "@",
                Description & ": Parent_Name");
         Check (Tree.Child_Names (Name).Count = 1
                and then Tree.Child_Names (Name, Partial).Item (0) = "B2",
                Description & ": Child_Names");
         Check (Tree.All_Child_Names (Name, Partial, False).Item (0)
                  = "@\A1",
                Description & ": All_Child_Names");
         declare
            Found : Unbounded_String;
         begin
            Check (Tree.Verify_Name (Name, None, Found)
                   and then Found = "A1",
                   Description & ": Verify_Name");
         end;
         Check_Same_Matrix (Tree.Parent_From_Child_Transform (Name), T_A,
                            0.0, Description & ": Parent_From_Child");
         Check_Same_Matrix (Tree.Get_Transform ("@", Name), T_A, 0.0,
                            Description & ": Get_Transform (root, name)");
         Check_Same_Matrix (Tree.Get_Transform (Name, "@"), T_A.Invert,
                            0.0, Description & ": Get_Transform (name, root)");
         Check (Tree.Get_Transform (Name, Name).Identity (0.0),
                Description & ": Get_Transform (name, name)");
         Check_Same_Matrix (Tree.Get_Transform (Name, B2_Last), T_B, Tol,
                            Description & ": Get_Transform (name, child)");
         Tree.Change_Transform (Name, New_A1);
         Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A1"),
                            New_A1, 0.0,
                            Description & ": Change_Transform");
         Tree.Change_Transform (Name, T_A);
      exception
         when E : others =>
            Fail (Description & ": raised "
                  & Ada.Exceptions.Exception_Name (E) & ": "
                  & Ada.Exceptions.Exception_Message (E));
      end Check_Name;
   begin
      Section ("names ending at Integer'Last");
      Tree.Add_Space ("@", "A1", T_A);
      Tree.Add_Space ("@\A1", "B2", T_B);
      Check_Name (A1_Last, "bounds end at Integer'Last");
      Check_Name (A1_Next, "bounds end at Integer'Last - 1");
      Check_Name (A1_Ten, "bounds end at Integer'Last - 10");
      begin
         Check (Tree.Parent_Name (B2_Last) = "@\A1",
                "parent of a two-level name ending at Integer'Last");
         Check (Full_Space_Name (A1_Last, "B") = "@\A1\B",
                "Full_Space_Name of a parent ending at Integer'Last");
         Check (Full_Space_Name (A1_Last, "B")'First = 1,
                "Full_Space_Name result starts at 1");
         Tree.Add_Space (A1_Last, "C", T_C);
         Check (Tree.Space_Exists ("@\A1\C"),
                "Add_Space under a parent ending at Integer'Last");
         Check (Tree.Parent_Name ("@\A1\C") = "@\A1",
                "parent of the space added there");
         Tree.Add_Space (A1_Ten, Long_Component, T_D);
         Check (Tree.Space_Exists ("@\A1\" & Long_Component),
                "Add_Space whose full name would pass Integer'Last");
         Tree.Add_Space (A1_Next, "C", T_E);
         Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A1\C"),
                            T_E, 0.0,
                            "Add_Space replacing, parent at 'Last - 1");
         Check (Tree.Space_Count = 5, "five spaces before deletion");
         Tree.Delete_Subtree (A1_Last);
         Check (Tree.Space_Count = 1,
                "Delete_Subtree of a name ending at Integer'Last");
         Tree.Add_Space ("@", "A1", T_A);
         Tree.Add_Space ("@\A1", "B2", T_B);
         Tree.Delete_Subtree (B2_Last);
         Check (Tree.Space_Count = 2 and then Tree.Space_Exists ("@\A1"),
                "Delete_Subtree of a two-level name ending at Integer'Last");
         Tree.Add_Space ("@\A1", "B2", T_B);
      exception
         when E : others =>
            Fail ("operations on names ending at Integer'Last raised "
                  & Ada.Exceptions.Exception_Name (E) & ": "
                  & Ada.Exceptions.Exception_Message (E));
      end;

      Section ("malformed names ending at Integer'Last");
      for W in 1 .. 4 loop
         Which := W;
         Bad := +Bad_Name;
         Check (not Tree.Space_Exists (Bad_Name),
                "Space_Exists """ & To_String (Bad) & """ is False");
         Get_To_Bad ("Get_Transform to """ & To_String (Bad) & """");
         Get_From_Bad ("Get_Transform from """ & To_String (Bad) & """");
         Parent_Bad ("Parent_Name """ & To_String (Bad) & """");
         Add_Under_Bad ("Add_Space under """ & To_String (Bad) & """");
         Delete_Bad ("Delete_Subtree """ & To_String (Bad) & """");
      end loop;
      Check (Tree.Space_Count = 3, "failed calls change nothing");
   end Test_High_Bounds;


   procedure Test_Streams is
      package Storage renames Ada.Streams.Storage.Unbounded;

      subtype I32 is Interfaces.Integer_32;
      use type I32;
      type Entries is array (1 .. 6) of Real;

      Tree   : Ks_Coordinate_Space_Tree;
      Target : Ks_Coordinate_Space_Tree;
      Before : Ks_Coordinate_Space_Tree;
      Stream : aliased Storage.Stream_Type;

      procedure Put_Space
        (Name : String; A, B, C, D, Tx, Ty : Real; Length : I32 := -1)
      is
         Text : String (1 .. 256) := [others => ASCII.NUL];
      begin
         Text (1 .. Name'Length) := Name;
         I32'Write (Stream'Access,
                    (if Length >= 0 then Length else I32 (Name'Length)));
         String'Write (Stream'Access, Text);
         for Value of Entries'[A, B, C, D, Tx, Ty] loop
            Real'Write (Stream'Access, Value);
         end loop;
      end Put_Space;

      procedure Put_Header (Count : I32; Code : I32 := 16#4B53_5400#) is
      begin
         I32'Write (Stream'Access, Code);
         I32'Write (Stream'Access, Count);
      end Put_Header;

      procedure Read_Target is
      begin
         Ks_Coordinate_Space_Tree'Read (Stream'Access, Target);
      end Read_Target;

      procedure Read_Rejected is new Check_Raises_Exactly
        (Read_Target, Ks_Image_File_Exception'Identity);

      procedure Expect_Rejected (Description : String) is
      begin
         Read_Rejected (Description & " raises Ks_Image_File_Exception");
         Check (Target = Before, Description & ": the target is unchanged");
         Stream.Clear;
      end Expect_Rejected;
   begin
      Section ("streams: round trip");
      Build (Tree);
      Tree.Add_Space ("@\A", "A B", T_E);
      Ks_Coordinate_Space_Tree'Write (Stream'Access, Tree);
      Ks_Coordinate_Space_Tree'Read (Stream'Access, Target);
      Check (Target = Tree, "a tree read back equals the one written");
      Check (Target.Space_Count = 9 and then Target.Space_Name (3) = "@\A\B",
             "the spaces read back");
      Check_All_Pairs (Target, "after a round trip");
      Check (Integer (Stream.Element_Count) = 0, "the whole stream is read");
      declare
         Empty : Ks_Coordinate_Space_Tree;
      begin
         Ks_Coordinate_Space_Tree'Output (Stream'Access, Empty);
         Target := Ks_Coordinate_Space_Tree'Input (Stream'Access);
         Check (Target = Empty and then Target.Space_Count = 1,
                "the root-only tree through 'Output and 'Input");
      end;
      Check (Tree /= Target, "trees with different spaces differ");

      Section ("streams: malformed input");
      Target := Tree;
      Before := Tree;
      Put_Header (2, Code => 99);
      Expect_Rejected ("a wrong format code");
      Put_Header (0);
      Expect_Rejected ("a count of 0");
      Put_Header (65);
      Expect_Rejected ("a count of 65");
      Put_Header (I32'Last);
      Expect_Rejected ("a huge count");
      Put_Header (2);
      Put_Space ("@\X\Y", 1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
      Expect_Rejected ("a space before its parent");
      Put_Header (3);
      Put_Space ("@\X", 1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
      Put_Space ("@\X", 1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
      Expect_Rejected ("a repeated space");
      Put_Header (2);
      Put_Space ("@\X", 1.0, 2.0, 2.0, 4.0, 0.0, 0.0);
      Expect_Rejected ("a singular transform");
      Put_Header (2);
      Put_Space ("@\X", 1.0E200, 0.0, 0.0, 1.0, 0.0, 0.0);
      Expect_Rejected ("a transform beyond 1.0E150");
      Put_Header (2);
      Put_Space ("@\X", 1.0, 0.0, 0.0, 1.0, 0.0, 0.0, Length => 1_000_000);
      Expect_Rejected ("a name length of a million");
      Put_Header (2);
      Put_Space ("@\#", 1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
      Expect_Rejected ("an invalid component");
      Put_Header (3);
      Put_Space ("@\X", 1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
      Expect_Rejected ("a stream that ends early");
      Check (Target.Space_Count = 9, "the target kept its spaces");
   end Test_Streams;

   procedure Test_Direction is
      Tree    : Ks_Coordinate_Space_Tree;
      Shifted : constant Ks_Transform_2D_Linear :=
        Create (1.0, 0.0, 0.0, 1.0, 10.0, 0.0);
   begin
      Section ("direction of Parent_From_New");
      --  Parent_From_New maps the new space into its parent: the origin
      --  of a space added with the translation (10, 0) is (10, 0) in the
      --  parent.
      Tree.Add_Space ("@", "New", Shifted);
      Check_Point (Tree.Get_Transform ("@", "@\New"), 0.0, 0.0, 10.0, 0.0,
                   0.0, "(0, 0) of the new space is (10, 0) in the parent");
      Check_Point (Tree.Get_Transform ("@\New", "@"), 10.0, 0.0, 0.0, 0.0,
                   0.0, "(10, 0) of the parent is (0, 0) of the new space");
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\New"), Shifted,
                         0.0, "the transform is stored as given");
      Check_Same_Matrix (Tree.Get_Transform ("@", "@\New"), Shifted, 0.0,
                         "Get_Transform (parent, new) is that transform");
      --  One level further, under a parent other than the root: Sub is
      --  turned a quarter turn within New, so its (1, 0) is New's (0, 1)
      --  and the root's (10, 1).
      Tree.Add_Space ("@\New", "Sub", Create_Rigid (Pi / 2.0, 0.0, 0.0));
      Check_Point (Tree.Get_Transform ("@\New", "@\New\Sub"), 1.0, 0.0,
                   0.0, 1.0, 1.0E-15, "Sub (1, 0) in New");
      Check_Point (Tree.Get_Transform ("@", "@\New\Sub"), 1.0, 0.0,
                   10.0, 1.0, 1.0E-15, "Sub (1, 0) in the root");
      Check_Point (Tree.Get_Transform ("@\New\Sub", "@"), 10.0, 1.0,
                   1.0, 0.0, 1.0E-15, "the root's (10, 1) in Sub");
   end Test_Direction;

   procedure Test_Duplicate_Handling is
      Tree   : Ks_Coordinate_Space_Tree;
      First  : constant Ks_Transform_2D_Linear :=
        Create_Rigid (0.25, 1.0, 2.0);
      Second : constant Ks_Transform_2D_Linear :=
        Create_Similarity (2.0, -0.5, 3.0, -4.0);
      Again  : Ks_Transform_2D_Linear := Second;
      Parent : Unbounded_String := +"@";
      Handling : Ks_Add_Space_Constants := Duplicate_Is_Error;

      procedure Add_Again is
      begin
         Tree.Add_Space (To_String (Parent), "F", Again, Handling);
      end Add_Again;

      procedure Again_Bad_Parameter is new Check_Raises_Exactly
        (Add_Again, Ks_Bad_Parameter_Exception'Identity);
      procedure Again_Singular is new Check_Raises_Exactly
        (Add_Again, Ks_Transform_Singular_Exception'Identity);
      procedure Again_Bad_Name is new Check_Raises_Exactly
        (Add_Again, Ks_Image_Bad_Selected_Space_Name_Exception'Identity);

      procedure Check_Kept (Expected : Ks_Transform_2D_Linear;
                            Description : String) is
      begin
         Check (Tree.Space_Count = 3, Description & ": no space added");
         Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\F"),
                            Expected, 0.0, Description & ": transform");
         Check (Tree.Space_Exists ("@\F\G")
                and then Tree.Parent_Name ("@\F\G") = "@\F",
                Description & ": descendant kept");
         Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\F\G"),
                            Identity, 0.0,
                            Description & ": descendant transform kept");
      end Check_Kept;
   begin
      Section ("Add_Space: duplicate handling");
      Tree.Add_Space ("@", "F", First);
      Tree.Add_Space ("@\F", "G", Identity);

      Handling := Duplicate_Is_Error;
      Again_Bad_Parameter ("Duplicate_Is_Error raises "
                           & "Ks_Bad_Parameter_Exception");
      Check_Kept (First, "Duplicate_Is_Error");
      begin
         Add_Again;
      exception
         when E : Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E)
                     = "Add_Space: the space ""@\F"" already exists",
                   "Duplicate_Is_Error names the space: "
                   & Ada.Exceptions.Exception_Message (E));
      end;

      Tree.Add_Space ("@", "F", Second, Ignore_Duplicate);
      Check_Kept (First, "Ignore_Duplicate");

      Tree.Add_Space ("@", "F", Second, Replace_Duplicate);
      Check_Kept (Second, "Replace_Duplicate");

      Tree.Add_Space ("@", "F", First);
      Check_Kept (First, "the default replaces");

      --  Every mode adds a space that does not exist yet.
      for Mode in Ks_Add_Space_Constants loop
         Tree.Add_Space ("@\F\G", Ks_Add_Space_Constants'Image (Mode),
                         Second, Mode);
         Check (Tree.Space_Exists
                  ("@\F\G\" & Ks_Add_Space_Constants'Image (Mode)),
                Ks_Add_Space_Constants'Image (Mode) & " adds a new space");
      end loop;
      Check (Tree.Space_Count = 6, "three spaces added");
      Check_Same_Matrix
        (Tree.Parent_From_Child_Transform ("@\F\G\IGNORE_DUPLICATE"),
         Second, 0.0, "a space added with Ignore_Duplicate");

      Section ("Add_Space: duplicate handling still checks its arguments");
      Tree.Delete_Subtree ("@\F\G");
      for Mode in Ks_Add_Space_Constants loop
         Handling := Mode;
         Again := Create (1.0, 2.0, 2.0, 4.0, 0.0, 0.0);
         Again_Singular (Ks_Add_Space_Constants'Image (Mode)
                         & " with a singular transform");
         Again := Create (1.0E200, 0.0, 0.0, 1.0, 0.0, 0.0);
         Again_Bad_Parameter (Ks_Add_Space_Constants'Image (Mode)
                              & " with a transform beyond the bound");
         Again := Second;
         Parent := +"@\Nope";
         Again_Bad_Name (Ks_Add_Space_Constants'Image (Mode)
                         & " under an unknown parent");
         Parent := +"@";
         Check (Tree.Space_Count = 2, "failed calls change nothing");
         Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\F"), First,
                            0.0, "failed calls keep the transform");
      end loop;
   end Test_Duplicate_Handling;

   procedure Test_Change_Transform is
      Tree : Ks_Coordinate_Space_Tree;
      X, Y : Coordinates;
   begin
      Section ("Change_Transform");
      Build (Tree);
      --  Changing A moves its whole subtree; the transforms below A stay.
      Tree.Change_Transform ("@\A", P_E);
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A"), P_E, 0.0,
                         "the new transform is stored as given");
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A\B"), P_B,
                         0.0, "the child keeps its transform");
      Check (Tree.Space_Count = 8, "no space added or removed");
      Check_Same_Matrix (Tree.Get_Transform ("@", "@\A\B"),
                         P_E * (P_B * Identity), 0.0,
                         "the subtree follows the new transform");
      Tree.Change_Transform ("@\A", P_A);
      Ground_Truth (4.0, -1.0, X, Y);
      Check_Point (Tree.Get_Transform ("@\A\C\G", "@\E\F"), X (F), Y (F),
                   X (G), Y (G), Tol, "changing back restores the mapping");
      Check_Same_Matrix (Tree.Parent_From_Child_Transform ("@\A"), P_A, 0.0,
                         "and the stored transform");
      --  The errors (root, singular, beyond the bound, unknown and
      --  malformed names) are in Test_Errors.
   end Test_Change_Transform;

   procedure Test_Names is
      type Name_List is array (Positive range <>) of Unbounded_String;

      No_Names : constant Name_List (1 .. 0) := [others => <>];

      procedure Check_Names
        (Actual      : Ks_String_Collection;
         Expected    : Name_List;
         Description : String) is
      begin
         Check (Actual.Count = Expected'Length,
                Description & ": count" & Natural'Image (Actual.Count));
         if Actual.Count = Expected'Length then
            for I in Expected'Range loop
               Check (Actual.Item (I - Expected'First)
                        = To_String (Expected (I)),
                      Description & ": item" & Integer'Image (I - 1)
                      & " is """ & Actual.Item (I - Expected'First)
                      & """, expected """ & To_String (Expected (I))
                      & """");
            end loop;
         end if;
      end Check_Names;

      Tree  : Ks_Coordinate_Space_Tree;
      Found : Unbounded_String;
   begin
      Build (Tree);
      Tree.Add_Space ("@", "A B", P_C);   --  ' ' sorts before '\'

      Section ("Root_Name");
      Check (Tree.Root_Name = "@", "Root_Name of a built tree");

      Section ("Parent_Name in each format");
      Check (Tree.Parent_Name ("@\A\B\D", Full) = "@\A\B", "Full");
      Check (Tree.Parent_Name ("@\A\B\D", None) = "B", "None");
      Check (Tree.Parent_Name ("@\A\B\D", Partial) = "@\A\B",
             "Partial gives the full name");
      Check (Tree.Parent_Name ("@\A\B\D") = "@\A\B", "Full by default");
      Check (Tree.Parent_Name ("@\A", Full) = "@"
             and then Tree.Parent_Name ("@\A", None) = "@"
             and then Tree.Parent_Name ("@\A", Partial) = "@",
             "the root as a parent in every format");
      Check (Tree.Parent_Name ("@\A B", None) = "@",
             "parent of a look-alike name");

      Section ("Child_Names in each format");
      Check_Names (Tree.Child_Names ("@"),
                   [+"@\A", +"@\A B", +"@\E"], "children of the root");
      Check_Names (Tree.Child_Names ("@", None),
                   [+"A", +"A B", +"E"], "children of the root, None");
      Check_Names (Tree.Child_Names ("@", Partial),
                   [+"A", +"A B", +"E"], "children of the root, Partial");
      Check_Names (Tree.Child_Names ("@\A", Full),
                   [+"@\A\B", +"@\A\C"],
                   "children of A (not the look-alike A B)");
      Check_Names (Tree.Child_Names ("@\A\B", Partial), [1 => +"D"],
                   "child of B, Partial");
      Check_Names (Tree.Child_Names ("@\A\B\D"), No_Names,
                   "a leaf has no children");

      Section ("All_Child_Names in each format");
      Check_Names (Tree.All_Child_Names ("@\A"),
                   [+"@\A\B", +"@\A\B\D", +"@\A\C", +"@\A\C\G"],
                   "descendants of A (defaults: Full, Children_Only)");
      Check_Names (Tree.All_Child_Names ("@\A", Partial),
                   [+"B", +"B\D", +"C", +"C\G"],
                   "descendants of A, Partial");
      Check_Names (Tree.All_Child_Names ("@\A", None),
                   [+"B", +"D", +"C", +"G"], "descendants of A, None");
      Check_Names (Tree.All_Child_Names ("@\A", Full, False),
                   [+"@\A", +"@\A\B", +"@\A\B\D", +"@\A\C", +"@\A\C\G"],
                   "A and its descendants");
      Check_Names (Tree.All_Child_Names ("@\A", Partial, False),
                   [+"@\A", +"B", +"B\D", +"C", +"C\G"],
                   "A and its descendants, Partial");
      Check_Names (Tree.All_Child_Names ("@\A", None, False),
                   [+"A", +"B", +"D", +"C", +"G"],
                   "A and its descendants, None");
      Check_Names (Tree.All_Child_Names ("@", Partial),
                   [+"A", +"A B", +"A\B", +"A\B\D", +"A\C", +"A\C\G", +"E",
                    +"E\F"],
                   "descendants of the root, Partial");
      declare
         Everything : constant Ks_String_Collection :=
           Tree.All_Child_Names ("@", Full, Children_Only => False);
      begin
         Check (Everything.Count = Tree.Space_Count,
                "the root and its descendants are every space");
         for I in 0 .. Everything.Count - 1 loop
            Check (Everything.Item (I) = Tree.Space_Name (I),
                   "in Space_Name order:" & Integer'Image (I));
         end loop;
      end;
      Check_Names (Tree.All_Child_Names ("@\E\F"), No_Names,
                   "a leaf has no descendants");
      Check_Names (Tree.All_Child_Names ("@\E\F", Partial, False),
                   [1 => +"@\E\F"], "a leaf with itself");

      Section ("Verify_Name");
      Check (Tree.Verify_Name ("@\A\B\D", Full, Found)
             and then Found = "@\A\B\D", "Full");
      Check (Tree.Verify_Name ("@\A\B\D", None, Found)
             and then Found = "D", "None");
      Check (Tree.Verify_Name ("@\A\B\D", Partial, Found)
             and then Found = "@\A\B\D", "Partial gives the full name");
      Check (Tree.Verify_Name ("@", None, Found) and then Found = "@",
             "the root");
      Check (Tree.Verify_Name ("@\A B", None, Found) and then Found = "A B",
             "a component with a blank");
      for Bad of Name_List'[+"@\Nope", +"D", +"A\B", +"", +"@\\A", +"#",
                            +".", +"@\A\"]
      loop
         Found := +"stale";
         Check (not Tree.Verify_Name (To_String (Bad), Full, Found)
                and then Found = "",
                "Verify_Name """ & To_String (Bad) & """ is False");
      end loop;
      Found := +"stale";
      Check (not Tree.Verify_Name ([1 .. 300 => 'x'], Full, Found)
             and then Found = "",
             "Verify_Name of a 300-character name is False");
   end Test_Names;

   procedure Test_String_Collection is
      Tree  : Ks_Coordinate_Space_Tree;
      Empty : Ks_String_Collection;
   begin
      Section ("Ks_String_Collection");
      Check (Empty.Count = 0 and then Count (Empty) = 0,
             "the default collection is empty");
      Tree.Add_Space ("@", "A", Identity);
      Tree.Add_Space ("@", "B", Identity);
      declare
         Names : constant Ks_String_Collection := Tree.Child_Names ("@");
         Copy  : Ks_String_Collection := Names;

         procedure Item_Beyond is
         begin
            if Names.Item (2) = "never" then
               Fail ("impossible item");
            end if;
         end Item_Beyond;

         procedure Check_Beyond is new Check_Raises_Exactly
           (Item_Beyond, Constraint_Error'Identity);
      begin
         Check (Count (Names) = 2 and then Item (Names, 1) = "@\B",
                "Count and Item called without prefix notation");
         Check (Names.Item (0)'First = 1, "an item is indexed from 1");
         Check_Beyond ("Item (Count) raises Constraint_Error");
         Copy.Append ("@\C");
         Check (Copy.Count = 3 and then Copy.Item (2) = "@\C"
                and then Names.Count = 2,
                "a collection is a value: the copy changes alone");
         declare
            Padded : constant String := "xx@\Dyy";
         begin
            Copy.Append (Padded (3 .. 5));
            Check (Copy.Item (3) = "@\D" and then Copy.Item (3)'First = 1,
                   "an appended slice is indexed from 1");
         end;
         Tree.Delete_Subtree ("@\A");
         Check (Names.Count = 2 and then Names.Item (0) = "@\A",
                "a collection does not follow later changes of the tree");
      end;
   end Test_String_Collection;

   procedure Run_All is
   begin
      Test_Default_Tree;
      Test_Simple_Analytic;
      Test_Direction;
      Test_Three_Levels;
      Test_Replace_And_Remove;
      Test_Duplicate_Handling;
      Test_Change_Transform;
      Test_Names;
      Test_String_Collection;
      Test_Errors;
      Test_Extreme_Chains;
      Test_Deep_Trees;
      Test_High_Bounds;
      Test_Streams;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Coordinate_Spaces;
