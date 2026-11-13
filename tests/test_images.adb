--  Tests for AMV.Images: pixel access, reference counted sharing, copies,
--  rows and matrices, the three image types, the coordinate space handling
--  of Get_Transform and the selected space, and the stream attributes.

with Ada.Exceptions;
with Ada.Streams.Storage.Unbounded;
with Ada.Unchecked_Conversion;
with Interfaces;

with AMV;                   use AMV;
with AMV.Coordinate_Spaces; use AMV.Coordinate_Spaces;
with AMV.Images;            use AMV.Images;
with AMV.Misc;
with AMV.Transforms;        use AMV.Transforms;
with AMV_Test_Support;      use AMV_Test_Support;

procedure Test_Images is

   use type Grey_8;
   use type Grey_16;

   Pi  : constant := AMV.Misc.Pi;
   Tol : constant := 1.0E-12;

   Sink : Natural := 0;
   --  Receives values read only to provoke an exception.

   No_Pixels     : constant Ada.Exceptions.Exception_Id :=
     Ks_Image_No_Pixels_Exception'Identity;
   Bad_Name      : constant Ada.Exceptions.Exception_Id :=
     Ks_Image_Bad_Selected_Space_Name_Exception'Identity;
   Bad_Parameter : constant Ada.Exceptions.Exception_Id :=
     Ks_Bad_Parameter_Exception'Identity;
   Singular      : constant Ada.Exceptions.Exception_Id :=
     Ks_Transform_Singular_Exception'Identity;
   Range_Error   : constant Ada.Exceptions.Exception_Id :=
     Constraint_Error'Identity;

   procedure Check_Matrix
     (T                  : Ks_Transform_2D_Linear;
      A, B, C, D, Tx, Ty : Real;
      Tolerance          : Real;
      Description        : String)
   is
      GA, GB, GC, GD, GTx, GTy : Real;
   begin
      T.Get_Matrix_Elements_Translation (GA, GB, GC, GD, GTx, GTy);
      Check_Near (GA, A, Tolerance, Description & " A");
      Check_Near (GB, B, Tolerance, Description & " B");
      Check_Near (GC, C, Tolerance, Description & " C");
      Check_Near (GD, D, Tolerance, Description & " D");
      Check_Near (GTx, Tx, Tolerance, Description & " Tx");
      Check_Near (GTy, Ty, Tolerance, Description & " Ty");
   end Check_Matrix;

   procedure Check_Same_Matrix
     (Actual, Expected : Ks_Transform_2D_Linear;
      Tolerance        : Real;
      Description      : String)
   is
      A, B, C, D, Tx, Ty : Real;
   begin
      Expected.Get_Matrix_Elements_Translation (A, B, C, D, Tx, Ty);
      Check_Matrix (Actual, A, B, C, D, Tx, Ty, Tolerance, Description);
   end Check_Same_Matrix;

   function Pattern (X, Y : Natural) return Grey_8 is
     (Grey_8 ((X * 7 + Y * 13 + 3) mod 256));
   --  A deterministic pixel pattern.

   function Pattern_16 (X, Y : Natural) return Grey_16 is
     (Grey_16 ((X * 1013 + Y * 7919 + 5) mod 65_536));

   function Patterned (Width, Height : Positive) return Ks_Image_8_Grey;

   function Patterned (Width, Height : Positive) return Ks_Image_8_Grey is
   begin
      return Result : Ks_Image_8_Grey := Create (Width, Height) do
         for Y in 0 .. Height - 1 loop
            for X in 0 .. Width - 1 loop
               Result.Set_Pixel (X, Y, Pattern (X, Y));
            end loop;
         end loop;
      end return;
   end Patterned;

   function Has_Pattern (Image : Ks_Image_8_Grey) return Boolean is
     (for all Y in 0 .. Image.Height - 1 =>
        (for all X in 0 .. Image.Width - 1 =>
           Image.Get_Pixel (X, Y) = Pattern (X, Y)));

   function All_Equal (Image : Ks_Image_8_Grey; Value : Grey_8)
      return Boolean is
     (for all Y in 0 .. Image.Height - 1 =>
        (for all X in 0 .. Image.Width - 1 =>
           Image.Get_Pixel (X, Y) = Value));

   --------------------------------------------------------------------

   procedure Test_Defaults is
      Grey   : Ks_Image_8_Grey;
      Grey16 : Ks_Image_16_Grey;
      Colour : Ks_Image_24_Planar_Color;
   begin
      Section ("defaults");
      Check (Grey.Width = 0 and then Grey.Height = 0, "8-bit default size");
      Check (not Grey.Allocated, "8-bit default unallocated");
      Check (not Grey16.Allocated and then Grey16.Width = 0,
             "16-bit default unallocated");
      Check (not Colour.Allocated and then Colour.Height = 0,
             "colour default unallocated");
      Check (Grey.Selected_Space_Name = "@", "default selected space");
      Check (Colour.Selected_Space_Name = "@", "colour selected space");
      Check (Grey.Pixel_From_Root_Transform.Identity (0.0),
             "default pixel-from-root is the identity");
      Check (Grey.Get_Coordinate_Space_Tree.Space_Count = 1,
             "default tree holds only the root");
      Check (not Shares_Pixels (Grey, Grey),
             "an unallocated image shares nothing, not even with itself");
      declare
         Other : constant Ks_Image_8_Grey := Grey;
      begin
         Check (not Other.Allocated, "copy of unallocated is unallocated");
         Check (not Shares_Pixels (Grey, Other),
                "two unallocated images do not share");
      end;
      Check (not Grey.Copy.Allocated, "Copy of unallocated");
      Check (not Grey16.Copy.Allocated, "16-bit Copy of unallocated");
      Check (not Colour.Copy.Allocated, "colour Copy of unallocated");
   end Test_Defaults;

   procedure Test_Create_And_Pixels is
      Image : Ks_Image_8_Grey := Create (5, 3, Value => 42);
   begin
      Section ("8-bit create and pixels");
      Check (Image.Width = 5 and then Image.Height = 3, "size");
      Check (Image.Allocated, "allocated");
      Check (All_Equal (Image, 42), "filled with Value");
      Check (All_Equal (Create (2, 2), 0), "default value 0");
      Image.Set_Pixel (4, 2, 255);
      Image.Set_Pixel (0, 0, 1);
      Image.Set_Pixel (4, 0, 2);
      Image.Set_Pixel (0, 2, 3);
      Check (Image.Get_Pixel (4, 2) = 255, "last pixel");
      Check (Image.Get_Pixel (0, 0) = 1, "first pixel");
      Check (Image.Get_Pixel (4, 0) = 2, "top right pixel");
      Check (Image.Get_Pixel (0, 2) = 3, "bottom left pixel");
      Check (Image.Get_Pixel (1, 1) = 42, "untouched pixel");
      Image.Fill (9);
      Check (All_Equal (Image, 9), "Fill");
      Check (Image.Selected_Space_Name = "@", "created selected space");

      declare
         Single : constant Ks_Image_8_Grey := Create (1, 1, 7);
      begin
         Check (Single.Get_Pixel (0, 0) = 7, "1 x 1 image");
      end;
   end Test_Create_And_Pixels;

   procedure Test_Pixel_Errors is
      Empty   : Ks_Image_8_Grey;
      Image   : Ks_Image_8_Grey := Create (4, 3);
      Empty16 : Ks_Image_16_Grey;
      Image16 : Ks_Image_16_Grey := Create (4, 3);
      EmptyC  : Ks_Image_24_Planar_Color;
      ImageC  : Ks_Image_24_Planar_Color := Create (4, 3);
      Row     : Grey_8_Row (0 .. 3);
      R, G, B : Grey_8;

      procedure Get_Empty is
      begin
         Sink := Sink + Natural (Empty.Get_Pixel (0, 0));
      end Get_Empty;

      procedure Set_Empty is
      begin
         Empty.Set_Pixel (0, 0, 1);
      end Set_Empty;

      procedure Fill_Empty is
      begin
         Empty.Fill (1);
      end Fill_Empty;

      procedure Get_Row_Empty is
      begin
         Empty.Get_Row (0, Row);
      end Get_Row_Empty;

      procedure Set_Row_Empty is
      begin
         Empty.Set_Row (0, Row);
      end Set_Row_Empty;

      procedure Matrix_Empty is
         M : constant Grey_8_Matrix := Empty.To_Matrix;
      begin
         Sink := Sink + Natural (M (M'First (1), M'First (2)));
      end Matrix_Empty;

      procedure Get_X_Equal_Width is
      begin
         --  (4, 0) has flat index 4, which is inside the buffer: only an
         --  explicit column check catches it.
         Sink := Sink + Natural (Image.Get_Pixel (4, 0));
      end Get_X_Equal_Width;

      procedure Set_X_Equal_Width is
      begin
         Image.Set_Pixel (4, 1, 1);
      end Set_X_Equal_Width;

      procedure Get_Y_Equal_Height is
      begin
         Sink := Sink + Natural (Image.Get_Pixel (0, 3));
      end Get_Y_Equal_Height;

      procedure Set_Y_Equal_Height is
      begin
         Image.Set_Pixel (0, 3, 1);
      end Set_Y_Equal_Height;

      procedure Get_Huge is
      begin
         Sink := Sink
           + Natural (Image.Get_Pixel (Natural'Last, Natural'Last));
      end Get_Huge;

      procedure Get16_Empty is
      begin
         Sink := Sink + Natural (Empty16.Get_Pixel (0, 0));
      end Get16_Empty;

      procedure Set16_Empty is
      begin
         Empty16.Set_Pixel (0, 0, 1);
      end Set16_Empty;

      procedure Fill16_Empty is
      begin
         Empty16.Fill (1);
      end Fill16_Empty;

      procedure Get16_X is
      begin
         Sink := Sink + Natural (Image16.Get_Pixel (4, 0));
      end Get16_X;

      procedure Set16_Y is
      begin
         Image16.Set_Pixel (0, 3, 1);
      end Set16_Y;

      procedure GetC_Empty is
      begin
         EmptyC.Get_Pixel (0, 0, R, G, B);
      end GetC_Empty;

      procedure SetC_Empty is
      begin
         EmptyC.Set_Pixel (0, 0, 1, 2, 3);
      end SetC_Empty;

      procedure GetC_X is
      begin
         ImageC.Get_Pixel (4, 2, R, G, B);
      end GetC_X;

      procedure SetC_Y is
      begin
         ImageC.Set_Pixel (3, 3, 1, 2, 3);
      end SetC_Y;

      procedure T1 is new Check_Raises_Exactly (Get_Empty, No_Pixels);
      procedure T2 is new Check_Raises_Exactly (Set_Empty, No_Pixels);
      procedure T3 is new Check_Raises_Exactly (Fill_Empty, No_Pixels);
      procedure T4 is new Check_Raises_Exactly (Get_Row_Empty, No_Pixels);
      procedure T5 is new Check_Raises_Exactly (Set_Row_Empty, No_Pixels);
      procedure T6 is new Check_Raises_Exactly (Matrix_Empty, No_Pixels);
      procedure T7 is new Check_Raises_Exactly
        (Get_X_Equal_Width, Range_Error);
      procedure T8 is new Check_Raises_Exactly
        (Set_X_Equal_Width, Range_Error);
      procedure T9 is new Check_Raises_Exactly
        (Get_Y_Equal_Height, Range_Error);
      procedure T10 is new Check_Raises_Exactly
        (Set_Y_Equal_Height, Range_Error);
      procedure T11 is new Check_Raises_Exactly (Get_Huge, Range_Error);
      procedure T12 is new Check_Raises_Exactly (Get16_Empty, No_Pixels);
      procedure T13 is new Check_Raises_Exactly (Set16_Empty, No_Pixels);
      procedure T14 is new Check_Raises_Exactly (Fill16_Empty, No_Pixels);
      procedure T15 is new Check_Raises_Exactly (Get16_X, Range_Error);
      procedure T16 is new Check_Raises_Exactly (Set16_Y, Range_Error);
      procedure T17 is new Check_Raises_Exactly (GetC_Empty, No_Pixels);
      procedure T18 is new Check_Raises_Exactly (SetC_Empty, No_Pixels);
      procedure T19 is new Check_Raises_Exactly (GetC_X, Range_Error);
      procedure T20 is new Check_Raises_Exactly (SetC_Y, Range_Error);
   begin
      Section ("pixel access errors");
      Row := [others => 0];
      T1 ("Get_Pixel on unallocated");
      T2 ("Set_Pixel on unallocated");
      T3 ("Fill on unallocated");
      T4 ("Get_Row on unallocated");
      T5 ("Set_Row on unallocated");
      T6 ("To_Matrix on unallocated");
      T7 ("Get_Pixel X = Width");
      T8 ("Set_Pixel X = Width");
      T9 ("Get_Pixel Y = Height");
      T10 ("Set_Pixel Y = Height");
      T11 ("Get_Pixel at Natural'Last");
      T12 ("16-bit Get_Pixel on unallocated");
      T13 ("16-bit Set_Pixel on unallocated");
      T14 ("16-bit Fill on unallocated");
      T15 ("16-bit Get_Pixel X = Width");
      T16 ("16-bit Set_Pixel Y = Height");
      T17 ("colour Get_Pixel on unallocated");
      T18 ("colour Set_Pixel on unallocated");
      T19 ("colour Get_Pixel X = Width");
      T20 ("colour Set_Pixel Y = Height");
      Check (All_Equal (Image, 0), "failed Set_Pixel calls changed nothing");
      Check (Image16.Get_Pixel (3, 2) = 0, "16-bit unchanged");
   end Test_Pixel_Errors;

   procedure Test_Rows_And_Matrix is
      Image : Ks_Image_8_Grey := Create (4, 3);
      Row   : Grey_8_Row (0 .. 3);
      Out_Row : Grey_8_Row (0 .. 3);
      Shifted : constant Grey_8_Row (10 .. 13) := [20, 21, 22, 23];
      Wrong   : Grey_8_Row (0 .. 4) := [others => 0];

      procedure Set_Wrong_Length is
      begin
         Image.Set_Row (0, Wrong);
      end Set_Wrong_Length;

      procedure Get_Wrong_Length is
      begin
         Image.Get_Row (0, Wrong);
      end Get_Wrong_Length;

      procedure Set_Bad_Row is
      begin
         Image.Set_Row (3, Row);
      end Set_Bad_Row;

      procedure Get_Bad_Row is
      begin
         Image.Get_Row (3, Out_Row);
      end Get_Bad_Row;

      procedure From_Empty_Rows is
         Empty : Grey_8_Matrix (1 .. 0, 0 .. 3);
         Result : constant Ks_Image_8_Grey := From_Matrix (Empty);
      begin
         Check (not Result.Allocated, "unreachable");
      end From_Empty_Rows;

      procedure From_Empty_Columns is
         Empty : Grey_8_Matrix (0 .. 2, 5 .. 4);
         Result : constant Ks_Image_8_Grey := From_Matrix (Empty);
      begin
         Check (not Result.Allocated, "unreachable");
      end From_Empty_Columns;

      procedure T1 is new Check_Raises_Exactly (Set_Wrong_Length, Range_Error);
      procedure T2 is new Check_Raises_Exactly (Get_Wrong_Length, Range_Error);
      procedure T3 is new Check_Raises_Exactly (Set_Bad_Row, Range_Error);
      procedure T4 is new Check_Raises_Exactly (Get_Bad_Row, Range_Error);
      procedure T5 is new Check_Raises_Exactly
        (From_Empty_Rows, Bad_Parameter);
      procedure T6 is new Check_Raises_Exactly
        (From_Empty_Columns, Bad_Parameter);
   begin
      Section ("rows and matrices");
      for Y in 0 .. 2 loop
         for X in Row'Range loop
            Row (X) := Pattern (X, Y);
         end loop;
         Image.Set_Row (Y, Row);
      end loop;
      Check (Has_Pattern (Image), "Set_Row writes the right pixels");
      for Y in 0 .. 2 loop
         Image.Get_Row (Y, Out_Row);
         Check ((for all X in Out_Row'Range => Out_Row (X) = Pattern (X, Y)),
                "Get_Row" & Y'Image);
      end loop;

      Image.Set_Row (1, Shifted);
      Check (Image.Get_Pixel (0, 1) = 20 and then Image.Get_Pixel (3, 1) = 23,
             "Set_Row slides a row with other bounds");
      Check (Image.Get_Pixel (0, 0) = Pattern (0, 0)
               and then Image.Get_Pixel (0, 2) = Pattern (0, 2),
             "Set_Row leaves other rows alone");
      declare
         Other_Bounds : Grey_8_Row (7 .. 10);
      begin
         Image.Get_Row (1, Other_Bounds);
         Check (Other_Bounds (7) = 20 and then Other_Bounds (10) = 23,
                "Get_Row into a row with other bounds");
      end;

      Wrong := [others => 0];
      T1 ("Set_Row with a row too long");
      T2 ("Get_Row with a row too long");
      T3 ("Set_Row with Y = Height");
      T4 ("Get_Row with Y = Height");

      declare
         Source : constant Ks_Image_8_Grey := Patterned (5, 3);
         M      : constant Grey_8_Matrix := Source.To_Matrix;
      begin
         Check (M'First (1) = 0 and then M'Last (1) = 2,
                "To_Matrix row range");
         Check (M'First (2) = 0 and then M'Last (2) = 4,
                "To_Matrix column range");
         Check ((for all Y in M'Range (1) =>
                   (for all X in M'Range (2) => M (Y, X) = Pattern (X, Y))),
                "To_Matrix values, indexed (Y, X)");
         declare
            Back : constant Ks_Image_8_Grey := From_Matrix (M);
         begin
            Check (Back.Width = 5 and then Back.Height = 3,
                   "From_Matrix size");
            Check (Has_Pattern (Back), "matrix round trip");
            Check (not Shares_Pixels (Back, Source),
                   "From_Matrix makes new pixels");
         end;
      end;

      declare
         Offset_Matrix : constant Grey_8_Matrix (10 .. 11, 3 .. 5) :=
           [[1, 2, 3], [4, 5, 6]];
         Result        : constant Ks_Image_8_Grey :=
           From_Matrix (Offset_Matrix);
      begin
         Check (Result.Width = 3 and then Result.Height = 2,
                "From_Matrix with offset bounds: size");
         Check (Result.Get_Pixel (0, 0) = 1
                  and then Result.Get_Pixel (2, 0) = 3
                  and then Result.Get_Pixel (0, 1) = 4
                  and then Result.Get_Pixel (2, 1) = 6,
                "From_Matrix with offset bounds: values");
      end;

      T5 ("From_Matrix with no rows");
      T6 ("From_Matrix with no columns");
   end Test_Rows_And_Matrix;

   procedure Test_Sharing is
      A : Ks_Image_8_Grey := Patterned (6, 4);
   begin
      Section ("8-bit sharing");
      declare
         B : Ks_Image_8_Grey := A;
      begin
         Check (Shares_Pixels (A, B), "assignment shares pixels");
         Check (Shares_Pixels (B, A), "Shares_Pixels is symmetric");
         Check (Shares_Pixels (A, A), "an allocated image shares with itself");
         B.Set_Pixel (2, 3, 200);
         Check (A.Get_Pixel (2, 3) = 200, "Set_Pixel through B seen in A");
         A.Set_Pixel (5, 0, 17);
         Check (B.Get_Pixel (5, 0) = 17, "Set_Pixel through A seen in B");
         B.Fill (3);
         Check (All_Equal (A, 3), "Fill through B seen in A");
      end;
      Check (All_Equal (A, 3), "A keeps the pixels after B is gone");

      A := Patterned (6, 4);
      declare
         C : Ks_Image_8_Grey := A.Copy;
         S : constant Ks_Image_8_Grey := A.Copy (Share_Pixels);
      begin
         Check (not Shares_Pixels (A, C), "Copy has its own pixels");
         Check (Has_Pattern (C), "Copy has the same values");
         C.Set_Pixel (0, 0, 99);
         Check (A.Get_Pixel (0, 0) = Pattern (0, 0),
                "changing the copy leaves the original");
         A.Set_Pixel (1, 1, 98);
         Check (C.Get_Pixel (1, 1) = Pattern (1, 1),
                "changing the original leaves the copy");
         Check (Shares_Pixels (A, S), "Copy (Share_Pixels) shares");
         Check (S.Get_Pixel (1, 1) = 98, "shared copy sees the change");
         Check (A.Copy (Copy_Pixels).Get_Pixel (1, 1) = 98,
                "explicit Copy_Pixels copies current values");
      end;

      --  Allocate detaches from the other sharers.
      declare
         Original : Ks_Image_8_Grey := Patterned (6, 4);
         Sharer   : Ks_Image_8_Grey := Original;
      begin
         Sharer.Allocate (3, 2);
         Check (Sharer.Width = 3 and then Sharer.Height = 2,
                "Allocate sets the new size");
         Check (All_Equal (Sharer, 0), "Allocate zero-fills");
         Check (not Shares_Pixels (Original, Sharer),
                "Allocate detaches from the old buffer");
         Check (Has_Pattern (Original), "the other sharer keeps its pixels");
         Sharer.Set_Pixel (0, 0, 77);
         Check (Original.Get_Pixel (0, 0) = Pattern (0, 0),
                "detached image writes only its own buffer");
         Original.Allocate (6, 4);
         Check (All_Equal (Original, 0),
                "Allocate of the same size still gives zeros");
      end;

      --  Self assignment and assigning a sharer onto itself.
      declare
         Self  : Ks_Image_8_Grey := Patterned (3, 3);
         Alias : Ks_Image_8_Grey := Self;
         Same  : Ks_Image_8_Grey renames Self;
      begin
         Self := Same;
         Check (Has_Pattern (Self), "self assignment keeps the pixels");
         Check (Shares_Pixels (Self, Alias), "self assignment keeps sharing");
         Self := Alias;
         Alias := Self;
         Check (Has_Pattern (Self) and then Has_Pattern (Alias),
                "assigning sharers onto each other");
         Alias := Create (2, 2, 5);
         Check (Has_Pattern (Self), "reassigning the alias leaves Self");
         Check (All_Equal (Alias, 5), "alias has the new pixels");
         Self := Self.Copy;
         Check (Has_Pattern (Self), "Self := Self.Copy");
      end;

      --  Assigning an unallocated image releases the pixels.
      declare
         Keep  : constant Ks_Image_8_Grey := Patterned (4, 4);
         Other : Ks_Image_8_Grey := Keep;
         Empty : Ks_Image_8_Grey;
      begin
         Other := Empty;
         Check (not Other.Allocated, "assigning an unallocated image");
         Check (Other.Width = 0 and then Other.Height = 0,
                "unallocated size after assignment");
         Check (Has_Pattern (Keep), "the remaining sharer keeps its pixels");
      end;
   end Test_Sharing;

   procedure Test_Spaces_Copied is
      A    : Ks_Image_8_Grey := Create (4, 4);
      Tree : Ks_Coordinate_Space_Tree;
      P    : constant Ks_Transform_2D_Linear :=
        Create_Similarity (2.0, 0.0, 1.0, 1.0);
   begin
      Section ("spaces copied with the image");
      Tree.Add_Space ("@", "Fix", Create_Rigid (0.0, 3.0, 0.0));
      A.Set_Coordinate_Space_Tree (Tree);
      A.Set_Selected_Space_Name ("@\Fix");
      A.Set_Pixel_From_Root_Transform (P);
      declare
         B : Ks_Image_8_Grey := A;
         C : constant Ks_Image_8_Grey := A.Copy;
         D : Ks_Image_8_Grey := A;
      begin
         Check (B.Selected_Space_Name = "@\Fix",
                "assignment copies selection");
         Check (B.Get_Coordinate_Space_Tree.Space_Exists ("@\Fix"),
                "assignment copies the tree");
         Check_Same_Matrix (B.Pixel_From_Root_Transform, P, 0.0,
                            "assignment copies pixel-from-root");
         Check (C.Selected_Space_Name = "@\Fix", "Copy copies selection");
         Check (C.Get_Coordinate_Space_Tree.Space_Count = 2,
                "Copy copies the tree");
         Check_Same_Matrix (C.Pixel_From_Root_Transform, P, 0.0,
                            "Copy copies pixel-from-root");

         --  The tree is a value: changing B's leaves A's alone, although
         --  the pixels are shared.
         B.Coordinate_Space_Tree.Add_Space ("@", "Other", Identity);
         B.Set_Selected_Space_Name ("@\Other");
         B.Set_Pixel_From_Root_Transform (Identity);
         Check (not A.Get_Coordinate_Space_Tree.Space_Exists ("@\Other"),
                "the tree is not shared");
         Check (A.Selected_Space_Name = "@\Fix", "selection is not shared");
         Check_Same_Matrix (A.Pixel_From_Root_Transform, P, 0.0,
                            "pixel-from-root is not shared");
         Check (Shares_Pixels (A, B), "the pixels still are");

         D.Allocate (2, 2);
         Check (D.Selected_Space_Name = "@\Fix", "Allocate keeps selection");
         Check (D.Get_Coordinate_Space_Tree.Space_Exists ("@\Fix"),
                "Allocate keeps the tree");
         Check_Same_Matrix (D.Pixel_From_Root_Transform, P, 0.0,
                            "Allocate keeps pixel-from-root");
      end;
   end Test_Spaces_Copied;

   procedure Test_Copy_No_Pixels is
      --  The literal; No_Pixels alone is the exception identity above.
      None : constant Ks_Image_Copy_Mode_Constants := AMV.Images.No_Pixels;
      Tree : Ks_Coordinate_Space_Tree;
      P    : constant Ks_Transform_2D_Linear :=
        Create_Similarity (2.0, 0.5, 1.0, -1.0);
      Grey : Ks_Image_8_Grey := Patterned (5, 3);
      Deep : Ks_Image_16_Grey := Create (4, 2, Value => 300);
      Rgb  : Ks_Image_24_Planar_Color := Create (3, 2, 10, 20, 30);

      procedure Check_Spaces (Image : Ks_Image'Class; What : String) is
      begin
         Check (Image.Selected_Space_Name = "@\Fix",
                What & ": selection copied");
         Check (Image.Get_Coordinate_Space_Tree.Space_Count = 3
                and then Image.Get_Coordinate_Space_Tree.Space_Exists
                           ("@\Fix\Part"),
                What & ": tree copied");
         Check_Same_Matrix (Image.Pixel_From_Root_Transform, P, 0.0,
                            What & ": pixel-from-root copied");
         Check (not Image.Allocated and then Image.Width = 0
                and then Image.Height = 0,
                What & ": unallocated");
      end Check_Spaces;

      Copy_8 : Ks_Image_8_Grey;

      procedure Get_From_Copy is
      begin
         Sink := Natural (Copy_8.Get_Pixel (0, 0));
      end Get_From_Copy;

      procedure T1 is new Check_Raises_Exactly (Get_From_Copy, No_Pixels);
   begin
      Section ("Copy (No_Pixels)");
      Check (Ks_Image_Copy_Mode_Constants'Pos (None) = 2
             and then Ks_Image_Copy_Mode_Constants'Last = None,
             "No_Pixels is the third copy mode");
      Tree.Add_Space ("@", "Fix", Create_Rigid (0.3, 3.0, 0.0));
      Tree.Add_Space ("@\Fix", "Part", Create_Rigid (0.0, 1.0, 2.0));
      Grey.Set_Coordinate_Space_Tree (Tree);
      Grey.Set_Selected_Space_Name ("@\Fix");
      Grey.Set_Pixel_From_Root_Transform (P);
      Deep.Set_Coordinate_Space_Tree (Tree);
      Deep.Set_Selected_Space_Name ("@\Fix");
      Deep.Set_Pixel_From_Root_Transform (P);
      Rgb.Set_Coordinate_Space_Tree (Tree);
      Rgb.Set_Selected_Space_Name ("@\Fix");
      Rgb.Set_Pixel_From_Root_Transform (P);

      Copy_8 := Grey.Copy (None);
      Check_Spaces (Copy_8, "8-bit");
      Check (not Shares_Pixels (Grey, Copy_8), "8-bit: shares nothing");
      Check (Grey.Allocated and then Grey.Width = 5
             and then Has_Pattern (Grey),
             "8-bit: the original keeps its pixels");
      T1 ("Get_Pixel of a No_Pixels copy");
      --  The copy's state is its own.
      Copy_8.Coordinate_Space_Tree.Add_Space ("@", "Other", Identity);
      Check (not Grey.Get_Coordinate_Space_Tree.Space_Exists ("@\Other"),
             "8-bit: the tree is not shared");
      Copy_8.Allocate (2, 2);
      Check (Copy_8.Width = 2 and then All_Equal (Copy_8, 0)
             and then Copy_8.Selected_Space_Name = "@\Fix",
             "8-bit: Allocate gives pixels and keeps the selection");
      Check (not Shares_Pixels (Grey, Copy_8) and then Has_Pattern (Grey),
             "8-bit: Allocate on the copy leaves the original");

      declare
         Copy_16 : constant Ks_Image_16_Grey := Deep.Copy (None);
      begin
         Check_Spaces (Copy_16, "16-bit");
         Check (not Shares_Pixels (Deep, Copy_16)
                and then Deep.Get_Pixel (3, 1) = 300,
                "16-bit: the original keeps its pixels");
      end;

      declare
         Copy_C : constant Ks_Image_24_Planar_Color := Rgb.Copy (None);
         R, G, B : Grey_8;
      begin
         Check_Spaces (Copy_C, "colour");
         Check (not Copy_C.Get_Plane (Green).Allocated,
                "colour: Get_Plane of the copy is unallocated");
         Rgb.Get_Pixel (2, 1, R, G, B);
         Check (R = 10 and then G = 20 and then B = 30,
                "colour: the original keeps its pixels");
      end;

      --  A removed selection reads "@" in the copy too.
      declare
         Moved : Ks_Image_8_Grey := Create (2, 2);
      begin
         Moved.Set_Coordinate_Space_Tree (Tree);
         Moved.Set_Selected_Space_Name ("@\Fix\Part");
         Moved.Coordinate_Space_Tree.Delete_Subtree ("@\Fix\Part");
         Check (Moved.Copy (None).Selected_Space_Name = "@",
                "a removed selection reads ""@"" in the copy");
      end;

      --  An unallocated image copies to an unallocated image in every mode.
      declare
         Empty : Ks_Image_8_Grey;
      begin
         Empty.Set_Selected_Space_Name ("#");
         for Mode in Ks_Image_Copy_Mode_Constants loop
            Check (not Empty.Copy (Mode).Allocated
                   and then Empty.Copy (Mode).Selected_Space_Name = "#",
                   "unallocated image, Copy ("
                   & Ks_Image_Copy_Mode_Constants'Image (Mode) & ")");
         end loop;
      end;
   end Test_Copy_No_Pixels;

   procedure Test_Space_Names is
      Image : Ks_Image_8_Grey := Create (10, 10);
      Tree  : Ks_Coordinate_Space_Tree;
      Dummy : Ks_Transform_2D_Linear;

      procedure Select_Unknown is
      begin
         Image.Set_Selected_Space_Name ("@\Nope");
      end Select_Unknown;

      procedure Select_Empty is
      begin
         Image.Set_Selected_Space_Name ("");
      end Select_Empty;

      procedure Select_Relative is
      begin
         Image.Set_Selected_Space_Name ("A");
      end Select_Relative;

      procedure Resolve_Unknown is
      begin
         Sink := Sink + Image.Resolve_Space_Name ("@\A\Nope")'Length;
      end Resolve_Unknown;

      procedure Get_To_Unknown is
      begin
         Dummy := Image.Get_Transform ("@\Z", "#");
      end Get_To_Unknown;

      procedure Get_From_Unknown is
      begin
         Dummy := Image.Get_Transform ("#", "@\Z");
      end Get_From_Unknown;

      procedure Set_Singular is
      begin
         Image.Set_Pixel_From_Root_Transform
           (Create (1.0, 2.0, 2.0, 4.0, 0.0, 0.0));
      end Set_Singular;

      procedure T1 is new Check_Raises_Exactly (Select_Unknown, Bad_Name);
      procedure T2 is new Check_Raises_Exactly (Select_Empty, Bad_Name);
      procedure T3 is new Check_Raises_Exactly (Select_Relative, Bad_Name);
      procedure T4 is new Check_Raises_Exactly (Resolve_Unknown, Bad_Name);
      procedure T5 is new Check_Raises_Exactly (Get_To_Unknown, Bad_Name);
      procedure T6 is new Check_Raises_Exactly (Get_From_Unknown, Bad_Name);
      procedure T7 is new Check_Raises_Exactly (Set_Singular, Singular);
   begin
      Section ("space names");
      Tree.Add_Space ("@", "A", Identity);
      Tree.Add_Space ("@\A", "B", Identity);
      Image.Set_Coordinate_Space_Tree (Tree);

      Image.Set_Selected_Space_Name ("#");
      Check (Image.Selected_Space_Name = "#", "select pixel space");
      Image.Set_Selected_Space_Name (".");
      Check (Image.Selected_Space_Name = "#", "\"".\"" leaves the selection");
      Image.Set_Selected_Space_Name ("@\A\B");
      Check (Image.Selected_Space_Name = "@\A\B", "select a nested space");
      Image.Set_Selected_Space_Name ("@");
      Check (Image.Selected_Space_Name = "@", "select the root");

      T1 ("unknown space name");
      T2 ("empty space name");
      T3 ("name without the root prefix");
      Check (Image.Selected_Space_Name = "@",
             "failed selections leave the selection");

      Image.Set_Selected_Space_Name ("@\A");
      Check (Image.Resolve_Space_Name (".") = "@\A", "resolve \"".\""");
      Check (Image.Resolve_Space_Name ("#") = "#", "resolve \""#\""");
      Check (Image.Resolve_Space_Name ("@\A\B") = "@\A\B", "resolve a name");
      Check (Image.Resolve_Space_Name ("@") = "@", "resolve the root");
      T4 ("resolve an unknown name");
      T5 ("Get_Transform to an unknown space");
      T6 ("Get_Transform from an unknown space");

      --  Replacing the tree keeps a selection that still exists ...
      Tree.Add_Space ("@", "C", Identity);
      Image.Set_Coordinate_Space_Tree (Tree);
      Check (Image.Selected_Space_Name = "@\A", "selection kept");
      --  ... and resets one that does not.
      declare
         Smaller : Ks_Coordinate_Space_Tree;
      begin
         Smaller.Add_Space ("@", "C", Identity);
         Image.Set_Coordinate_Space_Tree (Smaller);
         Check (Image.Selected_Space_Name = "@", "selection reset to @");
         Check (not Image.Get_Coordinate_Space_Tree.Space_Exists ("@\A"),
                "new tree in place");
      end;
      --  "#" survives any tree replacement.
      Image.Set_Selected_Space_Name ("#");
      Image.Set_Coordinate_Space_Tree (Tree);
      Check (Image.Selected_Space_Name = "#", "pixel space selection kept");

      --  Setting the tree from the image's own tree (the parameter then
      --  aliases the component being replaced).
      Image.Set_Selected_Space_Name ("@\C");
      Image.Set_Coordinate_Space_Tree (Image.Coordinate_Space_Tree);
      Check (Image.Get_Coordinate_Space_Tree.Space_Count = 4,
             "tree set from itself keeps every space");
      Check (Image.Selected_Space_Name = "@\C",
             "tree set from itself keeps the selection");

      --  Changing the tree in place through the reference.
      Image.Coordinate_Space_Tree.Add_Space ("@\C", "D", Identity);
      Check (Image.Get_Coordinate_Space_Tree.Space_Exists ("@\C\D"),
             "Add_Space through Coordinate_Space_Tree");
      Image.Set_Selected_Space_Name ("@\C\D");
      Image.Coordinate_Space_Tree.Delete_Subtree ("@\C");
      Check (Image.Selected_Space_Name = "@",
             "a removed selected space reads as @");
      Check (Image.Resolve_Space_Name (".") = "@",
             "and resolves as @");
      Check (Image.Get_Transform (".", "@").Identity (0.0),
             "and maps as @");
      --  ... and stays "@" when spaces of the same names come back.
      Image.Coordinate_Space_Tree.Add_Space
        ("@", "C", Create_Rigid (0.0, -7.0, 0.0));
      Image.Coordinate_Space_Tree.Add_Space
        ("@\C", "D", Create_Rigid (0.0, -9.0, 0.0));
      Check (Image.Selected_Space_Name = "@",
             "a removed selection does not come back with its name");
      Check (Image.Resolve_Space_Name (".") = "@",
             "and \"".\"" still resolves as @");
      Check (Image.Get_Transform (".", "@").Identity (0.0),
             "and still maps as @");

      T7 ("singular pixel-from-root transform");
      Check (Image.Pixel_From_Root_Transform.Identity (0.0),
             "a rejected transform is not stored");
   end Test_Space_Names;

   procedure Test_Removed_Selection is
      --  A selected space removed from the tree in place must not come
      --  back as the selection when a space of the same name is added
      --  again: images whose selections read the same behave the same.
      Old_F : constant Ks_Transform_2D_Linear :=
        Create_Rigid (0.0, -5.0, 0.0);
      New_F : constant Ks_Transform_2D_Linear :=
        Create_Rigid (0.0, -9.0, 0.0);

      procedure Check_Root (Image : Ks_Image'Class; Description : String) is
      begin
         Check (Image.Selected_Space_Name = "@"
                  and then Image.Resolve_Space_Name (".") = "@"
                  and then Image.Get_Transform (".", "@").Identity (0.0),
                Description);
      end Check_Root;

      function Removed return Ks_Image_8_Grey;
      --  An image that selected "@\F", whose "@\F" was then removed in
      --  place.

      function Removed return Ks_Image_8_Grey is
      begin
         return Image : Ks_Image_8_Grey := Create (3, 2) do
            Image.Coordinate_Space_Tree.Add_Space ("@", "F", Old_F);
            Image.Set_Selected_Space_Name ("@\F");
            Image.Coordinate_Space_Tree.Delete_Subtree ("@\F");
         end return;
      end Removed;
   begin
      Section ("removed selected space");

      --  The same visible state followed by the same operation gives the
      --  same result, with or without a no-op tree replacement in between.
      declare
         X : Ks_Image_8_Grey := Create (2, 2);
         Y : Ks_Image_8_Grey := X;
      begin
         X.Coordinate_Space_Tree.Add_Space ("@", "F", Old_F);
         Y.Coordinate_Space_Tree.Add_Space ("@", "F", Old_F);
         X.Set_Selected_Space_Name ("@\F");
         X.Coordinate_Space_Tree.Delete_Subtree ("@\F");
         Y.Coordinate_Space_Tree.Delete_Subtree ("@\F");
         Check (X = Y, "removing the selection leaves no hidden state");
         X.Coordinate_Space_Tree.Add_Space ("@", "F", New_F);
         Y.Coordinate_Space_Tree.Add_Space ("@", "F", New_F);
         Check_Root (X, "re-added space not selected");
         Check (X = Y, "and the two images are still equal");
      end;

      declare
         X : Ks_Image_8_Grey := Removed;
      begin
         X.Set_Coordinate_Space_Tree (X.Get_Coordinate_Space_Tree);
         X.Coordinate_Space_Tree.Add_Space ("@", "F", New_F);
         Check_Root (X, "no-op tree replacement, then re-add");
      end;

      --  Copies taken after the removal.
      declare
         Source : constant Ks_Image_8_Grey := Removed;
         By_Assignment : Ks_Image_8_Grey := Source;
         By_Copy       : Ks_Image_8_Grey := Source.Copy;
         Sharing       : Ks_Image_8_Grey := Source.Copy (Share_Pixels);
      begin
         By_Assignment.Coordinate_Space_Tree.Add_Space ("@", "F", New_F);
         By_Copy.Coordinate_Space_Tree.Add_Space ("@", "F", New_F);
         Sharing.Coordinate_Space_Tree.Add_Space ("@", "F", New_F);
         Check_Root (By_Assignment, "assigned copy, then re-add");
         Check_Root (By_Copy, "Copy, then re-add");
         Check_Root (Sharing, "Copy (Share_Pixels), then re-add");
      end;

      --  A new tree that has the removed name does not revive it.
      declare
         X     : Ks_Image_8_Grey := Removed;
         Other : Ks_Coordinate_Space_Tree;
      begin
         Other.Add_Space ("@", "F", New_F);
         X.Set_Coordinate_Space_Tree (Other);
         Check_Root (X, "Set_Coordinate_Space_Tree with the removed name");
         Check (X.Get_Coordinate_Space_Tree.Space_Exists ("@\F"),
                "the new tree is in place");
      end;

      --  Selecting "." keeps the selection as it reads.
      declare
         X : Ks_Image_8_Grey := Removed;
      begin
         X.Set_Selected_Space_Name (".");
         X.Coordinate_Space_Tree.Add_Space ("@", "F", New_F);
         Check_Root (X, "select \"".\"", then re-add");
      end;

      --  Clear, then re-add.
      declare
         X : Ks_Image_8_Grey := Create (2, 2);
      begin
         X.Coordinate_Space_Tree.Add_Space ("@", "F", Old_F);
         X.Set_Selected_Space_Name ("@\F");
         X.Coordinate_Space_Tree.Clear;
         X.Coordinate_Space_Tree.Add_Space ("@", "F", New_F);
         Check_Root (X, "Clear, then re-add");
      end;

      --  Planes of a colour image, and the other image types.
      declare
         Colour : Ks_Image_24_Planar_Color := Create (2, 2);
         Grey16 : Ks_Image_16_Grey := Create (2, 2);
      begin
         Colour.Coordinate_Space_Tree.Add_Space ("@", "F", Old_F);
         Colour.Set_Selected_Space_Name ("@\F");
         Colour.Coordinate_Space_Tree.Delete_Subtree ("@\F");
         declare
            Plane : Ks_Image_8_Grey := Colour.Get_Plane (Green);
         begin
            Plane.Coordinate_Space_Tree.Add_Space ("@", "F", New_F);
            Check_Root (Plane, "Get_Plane, then re-add");
         end;
         Colour.Coordinate_Space_Tree.Add_Space ("@", "F", New_F);
         Check_Root (Colour, "colour image, re-add");
         Grey16.Coordinate_Space_Tree.Add_Space ("@", "F", Old_F);
         Grey16.Set_Selected_Space_Name ("@\F");
         Grey16.Coordinate_Space_Tree.Delete_Subtree ("@\F");
         Grey16.Coordinate_Space_Tree.Add_Space ("@", "F", New_F);
         Check_Root (Grey16, "16-bit image, re-add");
      end;

      --  A selection that was never removed is kept.
      declare
         X : Ks_Image_8_Grey := Create (2, 2);
      begin
         X.Coordinate_Space_Tree.Add_Space ("@", "F", Old_F);
         X.Set_Selected_Space_Name ("@\F");
         X.Coordinate_Space_Tree.Add_Space ("@", "F", New_F);
         X.Coordinate_Space_Tree.Add_Space ("@\F", "G", Identity);
         Check (X.Selected_Space_Name = "@\F",
                "changing the selected space's transform keeps it");
         Check_Same_Matrix (X.Get_Transform ("@", "."), New_F, 0.0,
                            "and \"".\"" uses the new transform");
      end;

      --  The documented exception: a reference that is kept settles the
      --  selection only when it is created and when it ends.
      declare
         X : Ks_Image_8_Grey := Create (2, 2);
      begin
         X.Coordinate_Space_Tree.Add_Space ("@", "F", Old_F);
         X.Set_Selected_Space_Name ("@\F");
         declare
            Kept : constant Ks_Coordinate_Space_Tree_Reference :=
              X.Coordinate_Space_Tree;
         begin
            Kept.Delete_Subtree ("@\F");
            Check (X.Selected_Space_Name = "@",
                   "kept reference: a removed selection reads as @");
            Kept.Add_Space ("@", "F", New_F);
            Check (X.Selected_Space_Name = "@\F",
                   "kept reference: re-added through it, still selected");
         end;
         Check (X.Selected_Space_Name = "@\F",
                "kept reference: and after it ends");
         declare
            Kept : constant Ks_Coordinate_Space_Tree_Reference :=
              X.Coordinate_Space_Tree;
         begin
            Kept.Delete_Subtree ("@\F");
         end;
         X.Coordinate_Space_Tree.Add_Space ("@", "F", Old_F);
         Check_Root (X, "a removal settles when the kept reference ends");
      end;
   end Test_Removed_Selection;

   procedure Test_Get_Transform is
      Image : Ks_Image_8_Grey := Create (8, 8);
      --  Root to pixel: scale 2, then shift (10, 20).
      P     : constant Ks_Transform_2D_Linear :=
        Create (2.0, 0.0, 0.0, 2.0, 10.0, 20.0);
      --  "@\A" from "@": shift by (-5, -5).
      T_A   : constant Ks_Transform_2D_Linear :=
        Create_Rigid (0.0, -5.0, -5.0);
      --  "@\A\B" from "@\A": quarter turn.
      T_B   : constant Ks_Transform_2D_Linear :=
        Create_Rigid (Pi / 2.0, 0.0, 0.0);
      --  "@\C" from "@": a general affine transform.
      T_C   : constant Ks_Transform_2D_Linear :=
        Create (1.5, 0.25, -0.5, 0.75, 3.0, -7.0);
      F_B   : constant Ks_Transform_2D_Linear := T_B.Compose (T_A);
   begin
      Section ("Get_Transform");
      --  The tree takes the transforms into the parents.
      Image.Coordinate_Space_Tree.Add_Space ("@", "A", T_A.Invert);
      Image.Coordinate_Space_Tree.Add_Space ("@\A", "B", T_B.Invert);
      Image.Coordinate_Space_Tree.Add_Space ("@", "C", T_C.Invert);

      --  With the default (identity) pixel-from-root, "#" equals "@".
      Check (Image.Get_Transform ("#", "@").Identity (0.0),
             "default: pixel from root is the identity");
      Check_Same_Matrix (Image.Get_Transform ("#", "@\A"), Invert (T_A), Tol,
                         "default: pixel from A");

      Image.Set_Pixel_From_Root_Transform (P);
      Check_Same_Matrix (Image.Pixel_From_Root_Transform, P, 0.0,
                         "pixel-from-root stored");

      Check (Image.Get_Transform ("#", "#").Identity (0.0),
             "# from # is exactly the identity");
      Check (Image.Get_Transform ("@\A\B", "@\A\B").Identity (0.0),
             "a space from itself is exactly the identity");
      Check_Same_Matrix (Image.Get_Transform ("#", "@"), P, 0.0,
                         "pixel from root");
      Check_Same_Matrix (Image.Get_Transform ("@", "#"), Invert (P), Tol,
                         "root from pixel");
      Check_Matrix (Image.Get_Transform ("@", "#"),
                    0.5, 0.0, 0.0, 0.5, -5.0, -10.0, Tol,
                    "root from pixel, analytic");

      --  Origin of A is (5, 5) in the root, (20, 30) in pixels.
      Check_Matrix (Image.Get_Transform ("#", "@\A"),
                    2.0, 0.0, 0.0, 2.0, 20.0, 30.0, Tol,
                    "pixel from A, analytic");
      Check_Matrix (Image.Get_Transform ("@\A", "#"),
                    0.5, 0.0, 0.0, 0.5, -10.0, -15.0, Tol,
                    "A from pixel, analytic");
      --  B coordinates (u, v) are (v, -u) in A, (v + 5, 5 - u) in the root
      --  and (2 v + 20, 30 - 2 u) in pixels.
      Check_Matrix (Image.Get_Transform ("#", "@\A\B"),
                    0.0, 2.0, -2.0, 0.0, 20.0, 30.0, Tol,
                    "pixel from nested B, analytic");
      Check_Same_Matrix (Image.Get_Transform ("#", "@\A\B"),
                         P.Compose (Invert (F_B)), Tol,
                         "pixel from nested B, composed");
      Check_Same_Matrix (Image.Get_Transform ("@\A\B", "#"),
                         F_B.Compose (Invert (P)), Tol,
                         "nested B from pixel");
      Check_Same_Matrix (Image.Get_Transform ("@\C", "@\A\B"),
                         T_C.Compose (Invert (F_B)), Tol,
                         "C from B between branches");
      Check_Same_Matrix (Image.Get_Transform ("@\A\B", "@\C"),
                         F_B.Compose (Invert (T_C)), Tol,
                         "B from C between branches");
      Check_Same_Matrix (Image.Get_Transform ("@\C", "#"),
                         T_C.Compose (Invert (P)), Tol,
                         "C from pixel");
      Check_Same_Matrix
        (Image.Get_Transform ("@\C", "#").Compose
           (Image.Get_Transform ("#", "@\C")),
         Identity, Tol, "round trip C -> # -> C");

      --  "." follows the selection.
      Image.Set_Selected_Space_Name ("@\A");
      Check_Same_Matrix (Image.Get_Transform (".", "#"),
                         Image.Get_Transform ("@\A", "#"), 0.0,
                         "\"".\"" from pixel = A from pixel");
      Check_Same_Matrix (Image.Get_Transform ("#", "."),
                         Image.Get_Transform ("#", "@\A"), 0.0,
                         "pixel from \"".\"" = pixel from A");
      Check (Image.Get_Transform (".", "@\A").Identity (0.0),
             "\"".\"" from its own space is exactly the identity");
      Check_Same_Matrix (Image.Get_Transform ("@\A\B", "."), T_B, Tol,
                         "B from \"".\"" undoes B's stored transform");
      Check_Same_Matrix (Image.Get_Transform (".", "@\A\B"), T_B.Invert,
                         Tol, "\"".\"" from B is B's stored transform");

      Image.Set_Selected_Space_Name ("#");
      Check (Image.Get_Transform (".", "#").Identity (0.0),
             "\"".\"" = \""#\"": identity");
      Check_Same_Matrix (Image.Get_Transform ("@", "."), Invert (P), Tol,
                         "root from \"".\"" when \"".\"" is \""#\""");

      Image.Set_Selected_Space_Name ("@\A\B");
      Check_Matrix (Image.Get_Transform ("#", "."),
                    0.0, 2.0, -2.0, 0.0, 20.0, 30.0, Tol,
                    "pixel from \"".\"" = nested B");

      --  A point check: the pixel position of the origin of B.
      declare
         X, Y : Real;
      begin
         Image.Get_Transform ("#", ".").Map_Point (1.0, 0.0, X, Y);
         Check_Near (X, 20.0, Tol, "B (1, 0) in pixels x");
         Check_Near (Y, 28.0, Tol, "B (1, 0) in pixels y");
      end;

      --  Copies carry the same mapping.
      declare
         Copy_Image : constant Ks_Image_8_Grey := Image.Copy;
      begin
         Check_Same_Matrix (Copy_Image.Get_Transform ("#", "."),
                            Image.Get_Transform ("#", "."), 0.0,
                            "copy maps the same way");
      end;
   end Test_Get_Transform;

   procedure Test_16_Bit is
      A : Ks_Image_16_Grey := Create (5, 4, Value => 1000);
   begin
      Section ("16-bit images");
      Check (A.Width = 5 and then A.Height = 4, "size");
      Check ((for all Y in 0 .. 3 =>
                (for all X in 0 .. 4 => A.Get_Pixel (X, Y) = 1000)),
             "filled with Value");
      for Y in 0 .. 3 loop
         for X in 0 .. 4 loop
            A.Set_Pixel (X, Y, Pattern_16 (X, Y));
         end loop;
      end loop;
      Check ((for all Y in 0 .. 3 =>
                (for all X in 0 .. 4 =>
                   A.Get_Pixel (X, Y) = Pattern_16 (X, Y))),
             "Set_Pixel / Get_Pixel");
      A.Set_Pixel (4, 3, Grey_16'Last);
      Check (A.Get_Pixel (4, 3) = 65_535, "full 16-bit range");
      declare
         B : Ks_Image_16_Grey := A;
         C : constant Ks_Image_16_Grey := A.Copy;
      begin
         Check (Shares_Pixels (A, B), "assignment shares");
         Check (not Shares_Pixels (A, C), "Copy does not");
         Check (Shares_Pixels (A, A.Copy (Share_Pixels)),
                "Copy (Share_Pixels) shares");
         B.Set_Pixel (0, 0, 12_345);
         Check (A.Get_Pixel (0, 0) = 12_345, "change visible through A");
         Check (C.Get_Pixel (0, 0) = Pattern_16 (0, 0), "copy unaffected");
         B.Allocate (2, 3);
         Check (B.Width = 2 and then B.Height = 3, "Allocate size");
         Check (B.Get_Pixel (1, 2) = 0, "Allocate zero-fills");
         Check (not Shares_Pixels (A, B), "Allocate detaches");
         Check (A.Get_Pixel (0, 0) = 12_345, "A keeps its pixels");
      end;
      A.Fill (7);
      Check (A.Get_Pixel (3, 2) = 7 and then A.Get_Pixel (0, 0) = 7, "Fill");
      declare
         Empty : Ks_Image_16_Grey;
      begin
         Check (not Shares_Pixels (Empty, Empty),
                "unallocated shares nothing");
      end;
   end Test_16_Bit;

   procedure Test_Colour is
      Colour : Ks_Image_24_Planar_Color := Create (4, 3, 10, 20, 30);
      R, G, B : Grey_8;
   begin
      Section ("24-bit planar colour");
      Check (Colour.Width = 4 and then Colour.Height = 3, "size");
      Colour.Get_Pixel (3, 2, R, G, B);
      Check (R = 10 and then G = 20 and then B = 30, "Create values");
      Colour.Set_Pixel (1, 2, 101, 102, 103);
      Colour.Get_Pixel (1, 2, R, G, B);
      Check (R = 101 and then G = 102 and then B = 103, "Set/Get_Pixel");
      Colour.Get_Pixel (0, 0, R, G, B);
      Check (R = 10 and then G = 20 and then B = 30, "other pixel kept");

      declare
         Red_Plane   : Ks_Image_8_Grey := Colour.Get_Plane (Red);
         Green_Plane : constant Ks_Image_8_Grey := Colour.Get_Plane (Green);
         Blue_Plane  : constant Ks_Image_8_Grey := Colour.Get_Plane (Blue);
      begin
         Check (Red_Plane.Width = 4 and then Red_Plane.Height = 3,
                "plane size");
         Check (Red_Plane.Get_Pixel (1, 2) = 101
                  and then Green_Plane.Get_Pixel (1, 2) = 102
                  and then Blue_Plane.Get_Pixel (1, 2) = 103,
                "plane values");
         Check (All_Equal (Colour.Get_Plane (Green), 20) = False,
                "green plane has the changed pixel");
         Red_Plane.Set_Pixel (0, 0, 250);
         Colour.Get_Pixel (0, 0, R, G, B);
         Check (R = 250 and then G = 20, "a plane shares the colour pixels");
         Colour.Set_Pixel (3, 0, 1, 2, 3);
         Check (Red_Plane.Get_Pixel (3, 0) = 1
                  and then Blue_Plane.Get_Pixel (3, 0) = 3,
                "colour changes visible in the planes");
         Check (Shares_Pixels (Red_Plane, Colour.Get_Plane (Red)),
                "two Get_Plane calls share one buffer");
         Check (not Shares_Pixels (Red_Plane, Green_Plane),
                "different planes do not share");
      end;

      --  A plane outlives the colour image it came from.
      declare
         Kept : Ks_Image_8_Grey;
      begin
         declare
            Temporary : constant Ks_Image_24_Planar_Color :=
              Create (3, 2, 5, 6, 7);
         begin
            Kept := Temporary.Get_Plane (Blue);
         end;
         Check (All_Equal (Kept, 7), "plane survives the colour image");
         Kept.Set_Pixel (2, 1, 8);
         Check (Kept.Get_Pixel (2, 1) = 8, "and stays writable");
      end;

      --  Planes carry the spaces of the colour image.
      declare
         Spaced : Ks_Image_24_Planar_Color := Create (2, 2);
         P      : constant Ks_Transform_2D_Linear :=
           Create_Similarity (3.0, 0.5, 1.0, 2.0);
      begin
         Spaced.Coordinate_Space_Tree.Add_Space ("@", "F", Identity);
         Spaced.Set_Selected_Space_Name ("@\F");
         Spaced.Set_Pixel_From_Root_Transform (P);
         declare
            Plane : constant Ks_Image_8_Grey := Spaced.Get_Plane (Green);
         begin
            Check (Plane.Selected_Space_Name = "@\F", "plane selection");
            Check (Plane.Get_Coordinate_Space_Tree.Space_Exists ("@\F"),
                   "plane tree");
            Check_Same_Matrix (Plane.Pixel_From_Root_Transform, P, 0.0,
                               "plane pixel-from-root");
         end;
      end;

      --  Set_Plane copies.
      declare
         Source : Ks_Image_8_Grey := Patterned (4, 3);
      begin
         Colour.Set_Plane (Green, Source);
         Check (Has_Pattern (Colour.Get_Plane (Green)), "Set_Plane copies");
         Check (not Shares_Pixels (Colour.Get_Plane (Green), Source),
                "Set_Plane does not share");
         Source.Fill (0);
         Check (Has_Pattern (Colour.Get_Plane (Green)),
                "later changes of the source do not reach the plane");
         Colour.Get_Pixel (1, 2, R, G, B);
         Check (R = 101 and then G = Pattern (1, 2) and then B = 103,
                "other planes untouched by Set_Plane");
         --  Copying a plane onto itself is harmless.
         Colour.Set_Plane (Green, Colour.Get_Plane (Green));
         Check (Has_Pattern (Colour.Get_Plane (Green)),
                "Set_Plane with its own plane");
      end;

      declare
         Wrong_Size : constant Ks_Image_8_Grey := Create (3, 3);
         Unset      : Ks_Image_8_Grey;
         Empty      : Ks_Image_24_Planar_Color;

         procedure Set_Wrong is
         begin
            Colour.Set_Plane (Red, Wrong_Size);
         end Set_Wrong;

         procedure Set_Unset is
         begin
            Colour.Set_Plane (Red, Unset);
         end Set_Unset;

         procedure Set_On_Empty is
         begin
            Empty.Set_Plane (Red, Wrong_Size);
         end Set_On_Empty;

         procedure T1 is new Check_Raises_Exactly (Set_Wrong, Bad_Parameter);
         procedure T2 is new Check_Raises_Exactly (Set_Unset, No_Pixels);
         procedure T3 is new Check_Raises_Exactly
           (Set_On_Empty, Bad_Parameter);
      begin
         T1 ("Set_Plane with a different size");
         T2 ("Set_Plane with an unallocated image");
         T3 ("Set_Plane on an unallocated colour image");
         Check (not Empty.Get_Plane (Red).Allocated,
                "Get_Plane of an unallocated image is unallocated");
      end;

      --  Copy and Allocate.
      declare
         Shared : Ks_Image_24_Planar_Color := Colour;
         Copied : Ks_Image_24_Planar_Color := Colour.Copy;
         Linked : constant Ks_Image_24_Planar_Color :=
           Colour.Copy (Share_Pixels);
      begin
         Shared.Set_Pixel (0, 1, 11, 12, 13);
         Colour.Get_Pixel (0, 1, R, G, B);
         Check (R = 11 and then G = 12 and then B = 13,
                "assignment shares colour pixels");
         Linked.Get_Pixel (0, 1, R, G, B);
         Check (R = 11, "Copy (Share_Pixels) shares");
         Copied.Get_Pixel (0, 1, R, G, B);
         Check (R = 10 and then G = Pattern (0, 1) and then B = 30,
                "Copy is independent");
         Copied.Set_Pixel (1, 2, 0, 0, 0);
         Colour.Get_Pixel (1, 2, R, G, B);
         Check (R = 101, "changing the copy leaves the original");
         Shared.Allocate (2, 5);
         Check (Shared.Width = 2 and then Shared.Height = 5,
                "Allocate size");
         Shared.Get_Pixel (1, 4, R, G, B);
         Check (R = 0 and then G = 0 and then B = 0, "Allocate zero-fills");
         Colour.Get_Pixel (0, 1, R, G, B);
         Check (R = 11, "Allocate detaches");
         Check (not Shares_Pixels (Shared.Get_Plane (Red),
                                   Colour.Get_Plane (Red)),
                "Allocate gives new planes");
      end;
   end Test_Colour;

   procedure Test_Reference_Count_Stress is
      Original : constant Ks_Image_8_Grey := Patterned (17, 11);

      type Image_Array is array (1 .. 50) of Ks_Image_8_Grey;

      procedure Nest (Image : Ks_Image_8_Grey; Depth : Natural) is
         Local : Ks_Image_8_Grey := Image;
         Many  : Image_Array := [others => Image];
      begin
         if not Shares_Pixels (Local, Original) then
            Fail ("nested copy at depth" & Depth'Image & " does not share");
         end if;
         for I in Many'Range loop
            if I mod 2 = 0 then
               Many (I) := Many (I - 1);
            else
               Many (I) := Local;
            end if;
         end loop;
         if Depth > 0 then
            Nest (Many (Depth mod Many'Length + 1), Depth - 1);
            Nest (Local.Copy (Share_Pixels), Depth - 1);
         end if;
         Local := Many (Many'Last);
      end Nest;

      Colour : constant Ks_Image_24_Planar_Color := Create (9, 7, 1, 2, 3);
   begin
      Section ("reference count stress");
      for Round in 1 .. 20 loop
         Nest (Original, 6);
      end loop;
      Check (Has_Pattern (Original), "pixels intact after nested copies");

      --  Images that only lived in nested scopes are gone: churn through
      --  allocations of the same size so that a buffer freed too early
      --  would very likely be overwritten.
      for Round in 1 .. 200 loop
         declare
            Junk : constant Ks_Image_8_Grey := Create (17, 11, 255);
         begin
            if Junk.Get_Pixel (16, 10) /= 255 then
               Fail ("junk image");
            end if;
         end;
      end loop;
      Check (Has_Pattern (Original), "pixels intact after churn");

      --  A copy made in an inner scope keeps the pixels alive after the
      --  original is replaced.
      declare
         Survivor : Ks_Image_8_Grey;
      begin
         declare
            Inner : constant Ks_Image_8_Grey := Patterned (5, 5);
         begin
            Survivor := Inner;
         end;
         for Round in 1 .. 100 loop
            declare
               Junk : constant Ks_Image_8_Grey := Create (5, 5, 255);
            begin
               if not Junk.Allocated then
                  Fail ("junk image");
               end if;
            end;
         end loop;
         Check (Has_Pattern (Survivor), "inner image survives its scope");
      end;

      --  Planes taken many times.
      for Round in 1 .. 100 loop
         declare
            P1 : constant Ks_Image_8_Grey := Colour.Get_Plane (Red);
            P2 : constant Ks_Image_8_Grey := P1;
            P3 : constant Ks_Image_8_Grey := Colour.Get_Plane (Blue);
         begin
            if P2.Get_Pixel (8, 6) /= 1 or else P3.Get_Pixel (0, 0) /= 3 then
               Fail ("plane values in round" & Round'Image);
            end if;
         end;
      end loop;
      declare
         R, G, B : Grey_8;
      begin
         Colour.Get_Pixel (8, 6, R, G, B);
         Check (R = 1 and then G = 2 and then B = 3,
                "colour pixels intact after plane churn");
      end;

      --  Concurrent copying exercises the atomic counter.
      declare
         Shared_Image : constant Ks_Image_8_Grey := Patterned (13, 9);

         task type Copier;

         task body Copier is
            Hold : Image_Array;
         begin
            for Round in 1 .. 400 loop
               for I in Hold'Range loop
                  Hold (I) := Shared_Image;
               end loop;
               for I in Hold'Range loop
                  Hold (I) := Hold (Hold'Last + 1 - I).Copy (Share_Pixels);
               end loop;
               Hold := [others => <>];
            end loop;
         end Copier;
      begin
         declare
            Copiers : array (1 .. 4) of Copier;
            pragma Unreferenced (Copiers);
         begin
            null;  --  Waits here for the four tasks to finish.
         end;
         for Round in 1 .. 200 loop
            declare
               Junk : constant Ks_Image_8_Grey := Create (13, 9, 255);
            begin
               if not Junk.Allocated then
                  Fail ("junk image");
               end if;
            end;
         end loop;
         Check (Has_Pattern (Shared_Image),
                "pixels intact after concurrent copying");
      end;
   end Test_Reference_Count_Stress;

   procedure Test_Streams is
      --  The stream attributes store images by value. With the predefined
      --  attributes, 'Read installed the written buffer pointer without
      --  counting it, so the image read shared (and later freed) the
      --  original's pixels.

      package Storage renames Ada.Streams.Storage.Unbounded;

      subtype U32 is Interfaces.Unsigned_32;
      subtype U64 is Interfaces.Unsigned_64;

      use type U32;
      use type Ada.Streams.Stream_Element_Count;

      type Real_Six is array (1 .. 6) of Real;

      function Bits_Of is new Ada.Unchecked_Conversion (Real, U64);

      Stream_Error : constant Ada.Exceptions.Exception_Id :=
        Ks_Image_File_Exception'Identity;

      P     : constant Ks_Transform_2D_Linear :=
        Create (2.0, 0.5, -0.25, 1.5, 10.0, -3.0);
      T_Fix : constant Ks_Transform_2D_Linear :=
        Create_Rigid (0.3, 1.0, 2.0);
      T_Sub : constant Ks_Transform_2D_Linear :=
        Create_Similarity (0.5, -1.0, 0.125, 7.0);

      procedure Give_Spaces (Image : in out Ks_Image'Class) is
      begin
         Image.Coordinate_Space_Tree.Add_Space ("@", "Fix", T_Fix);
         Image.Coordinate_Space_Tree.Add_Space ("@\Fix", "Part", T_Sub);
         Image.Coordinate_Space_Tree.Add_Space ("@", "Fix B", Identity);
         Image.Set_Selected_Space_Name ("@\Fix\Part");
         Image.Set_Pixel_From_Root_Transform (P);
      end Give_Spaces;

      procedure Check_Spaces
        (Actual, Expected : Ks_Image'Class; Description : String) is
      begin
         Check (Actual.Selected_Space_Name = Expected.Selected_Space_Name,
                Description & ": selection " & Actual.Selected_Space_Name);
         Check (Actual.Get_Coordinate_Space_Tree
                  = Expected.Get_Coordinate_Space_Tree,
                Description & ": tree");
         Check_Same_Matrix
           (Actual.Pixel_From_Root_Transform,
            Expected.Pixel_From_Root_Transform, 0.0,
            Description & ": pixel-from-root");
         Check_Same_Matrix
           (Actual.Get_Transform ("#", "."),
            Expected.Get_Transform ("#", "."), 0.0,
            Description & ": pixel from \"".\""");
      end Check_Spaces;

      procedure Check_Default (Image : Ks_Image'Class; Description : String)
      is
      begin
         Check (not Image.Allocated
                  and then Image.Width = 0 and then Image.Height = 0,
                Description & ": unallocated");
         Check (Image.Selected_Space_Name = "@"
                  and then Image.Get_Coordinate_Space_Tree.Space_Count = 1
                  and then Image.Pixel_From_Root_Transform.Identity (0.0),
                Description & ": default spaces");
      end Check_Default;

      function Colour_Pattern return Ks_Image_24_Planar_Color is
      begin
         return Result : Ks_Image_24_Planar_Color := Create (5, 3) do
            for Y in 0 .. 2 loop
               for X in 0 .. 4 loop
                  Result.Set_Pixel
                    (X, Y,
                     Red   => Pattern (X, Y),
                     Green => Pattern (X + 3, Y + 5),
                     Blue  => 255 - Pattern (X, Y));
               end loop;
            end loop;
         end return;
      end Colour_Pattern;

      function Same_Colour (A, B : Ks_Image_24_Planar_Color) return Boolean
      is
         RA, GA, BA, RB, GB, BB : Grey_8;
      begin
         if A.Width /= B.Width or else A.Height /= B.Height then
            return False;
         end if;
         for Y in 0 .. A.Height - 1 loop
            for X in 0 .. A.Width - 1 loop
               A.Get_Pixel (X, Y, RA, GA, BA);
               B.Get_Pixel (X, Y, RB, GB, BB);
               if RA /= RB or else GA /= GB or else BA /= BB then
                  return False;
               end if;
            end loop;
         end loop;
         return True;
      end Same_Colour;

      function Shares_A_Plane (A, B : Ks_Image_24_Planar_Color)
         return Boolean is
        (for some Left in Ks_Image_Plane_Constants =>
           (for some Right in Ks_Image_Plane_Constants =>
              Shares_Pixels (A.Get_Plane (Left), B.Get_Plane (Right))));

      function Contents (Stream : in out Storage.Stream_Type)
         return Ada.Streams.Stream_Element_Array
      is
      begin
         return Result : Ada.Streams.Stream_Element_Array
           (1 .. Stream.Element_Count)
         do
            declare
               Last : Ada.Streams.Stream_Element_Offset;
            begin
               Stream.Read (Result, Last);
               Check (Last = Result'Last, "the whole stream is read back");
            end;
         end return;
      end Contents;

      function Code_Of (Image : Ks_Image'Class) return U32 is
         Stream : aliased Storage.Stream_Type;
         Code   : U32;
      begin
         Ks_Image'Class'Write (Stream'Access, Image);
         U32'Read (Stream'Access, Code);
         return Code;
      end Code_Of;
      --  The format code at the start of an image of Image's type.

      procedure Put_Transform
        (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
         A, B, C, D, Tx, Ty : Real) is
      begin
         for Value of Real_Six'(A, B, C, D, Tx, Ty) loop
            U64'Write (Stream, Bits_Of (Value));
         end loop;
      end Put_Transform;

      procedure Put_Name
        (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
         Name   : String) is
      begin
         U32'Write (Stream, U32 (Name'Length));
         String'Write (Stream, Name);
      end Put_Name;

      Code_8 : constant U32 := Code_Of (Ks_Image_8_Grey'(Create (1, 1)));

      procedure Put_Header
        (Stream        : not null access Ada.Streams.Root_Stream_Type'Class;
         Width, Height : U32) is
      begin
         U32'Write (Stream, Code_8);
         U32'Write (Stream, Width);
         U32'Write (Stream, Height);
      end Put_Header;
      --  A Ks_Image_8_Grey header.

      Grey : constant Ks_Image_8_Grey := Patterned (6, 4);
   begin
      Section ("streams");

      --  8-bit round trip through 'Write and 'Read.
      declare
         A      : Ks_Image_8_Grey := Patterned (6, 4);
         Stream : aliased Storage.Stream_Type;
      begin
         Give_Spaces (A);
         Ks_Image_8_Grey'Write (Stream'Access, A);
         declare
            B : Ks_Image_8_Grey;
         begin
            Ks_Image_8_Grey'Read (Stream'Access, B);
            Check (Stream.Element_Count = 0, "8-bit: the image is read whole");
            Check (B.Width = 6 and then B.Height = 4, "8-bit: size");
            Check (Has_Pattern (B), "8-bit: pixels");
            Check (not Shares_Pixels (A, B), "8-bit: pixels not shared");
            Check_Spaces (B, A, "8-bit");
            B.Set_Pixel (0, 0, Pattern (0, 0) + 1);
            Check (A.Get_Pixel (0, 0) = Pattern (0, 0),
                   "8-bit: the image read is independent");
         end;
         --  The image read is gone; churn through allocations of the same
         --  size so that a buffer it freed would be overwritten.
         for Round in 1 .. 100 loop
            declare
               Junk : constant Ks_Image_8_Grey := Create (6, 4, 255);
            begin
               if not Junk.Allocated then
                  Fail ("junk image");
               end if;
            end;
         end loop;
         Check (Has_Pattern (A), "8-bit: the original survives the copy");

         --  'Read into an image that already has pixels.
         declare
            Target : Ks_Image_8_Grey := Create (3, 3, 9);
            Keep   : constant Ks_Image_8_Grey := Target;
         begin
            Ks_Image_8_Grey'Write (Stream'Access, A);
            Ks_Image_8_Grey'Read (Stream'Access, Target);
            Check (Has_Pattern (Target) and then not Shares_Pixels (Target, A),
                   "'Read into an allocated image");
            Check (not Shares_Pixels (Target, Keep) and then All_Equal (Keep, 9)
                     and then Keep.Width = 3,
                   "'Read releases the old pixels to their other users");
         end;

         --  'Output and 'Input.
         Ks_Image_8_Grey'Output (Stream'Access, A);
         declare
            C : constant Ks_Image_8_Grey :=
              Ks_Image_8_Grey'Input (Stream'Access);
         begin
            Check (Has_Pattern (C) and then not Shares_Pixels (A, C),
                   "8-bit 'Output and 'Input");
            Check_Spaces (C, A, "8-bit 'Input");
         end;
      end;

      --  16-bit round trip, class-wide.
      declare
         A      : Ks_Image_16_Grey := Create (5, 4);
         Stream : aliased Storage.Stream_Type;
      begin
         for Y in 0 .. 3 loop
            for X in 0 .. 4 loop
               A.Set_Pixel (X, Y, Pattern_16 (X, Y));
            end loop;
         end loop;
         A.Set_Pixel (0, 0, 16#0100#);
         A.Set_Pixel (1, 0, 16#00FF#);
         A.Set_Pixel (2, 0, 65_535);
         Give_Spaces (A);
         Ks_Image'Class'Output (Stream'Access, Ks_Image'Class (A));
         declare
            R : constant Ks_Image'Class := Ks_Image'Class'Input (Stream'Access);
         begin
            Check (R in Ks_Image_16_Grey, "class-wide 'Input keeps the type");
            if R in Ks_Image_16_Grey then
               declare
                  B : Ks_Image_16_Grey renames Ks_Image_16_Grey (R);
               begin
                  Check (B.Width = 5 and then B.Height = 4, "16-bit: size");
                  Check (B.Get_Pixel (0, 0) = 16#0100#
                           and then B.Get_Pixel (1, 0) = 16#00FF#
                           and then B.Get_Pixel (2, 0) = 65_535
                           and then (for all Y in 1 .. 3 =>
                                       (for all X in 0 .. 4 =>
                                          B.Get_Pixel (X, Y)
                                          = Pattern_16 (X, Y))),
                         "16-bit: pixels");
                  Check (not Shares_Pixels (A, B), "16-bit: not shared");
                  Check_Spaces (B, A, "16-bit");
               end;
            end if;
         end;
         Check (A.Get_Pixel (4, 3) = Pattern_16 (4, 3),
                "16-bit: the original survives");
      end;

      --  Colour round trip, class-wide and specific.
      declare
         A      : Ks_Image_24_Planar_Color := Colour_Pattern;
         Stream : aliased Storage.Stream_Type;
      begin
         Give_Spaces (A);
         Ks_Image'Class'Output (Stream'Access, Ks_Image'Class (A));
         declare
            R : constant Ks_Image'Class := Ks_Image'Class'Input (Stream'Access);
         begin
            Check (R in Ks_Image_24_Planar_Color, "colour: class-wide type");
            if R in Ks_Image_24_Planar_Color then
               Check (Same_Colour (Ks_Image_24_Planar_Color (R), A),
                      "colour: pixels");
               Check (not Shares_A_Plane (Ks_Image_24_Planar_Color (R), A),
                      "colour: no plane shared");
               Check_Spaces (R, A, "colour");
            end if;
         end;
         declare
            Target : Ks_Image_24_Planar_Color := Create (2, 2, 1, 2, 3);
            Keep   : constant Ks_Image_24_Planar_Color := Target;
            R, G, B : Grey_8;
         begin
            Ks_Image_24_Planar_Color'Write (Stream'Access, A);
            Ks_Image_24_Planar_Color'Read (Stream'Access, Target);
            Check (Same_Colour (Target, A)
                     and then not Shares_A_Plane (Target, A)
                     and then not Shares_A_Plane (Target, Keep),
                   "colour: 'Read into an allocated image");
            Keep.Get_Pixel (1, 1, R, G, B);
            Check (R = 1 and then G = 2 and then B = 3,
                   "colour: the old planes stay with their other users");
         end;
      end;

      --  An unallocated image round-trips as unallocated, with its spaces.
      declare
         Empty_8  : Ks_Image_8_Grey;
         Empty_16 : Ks_Image_16_Grey;
         Empty_C  : Ks_Image_24_Planar_Color;
         Stream   : aliased Storage.Stream_Type;
         Target_8 : Ks_Image_8_Grey := Create (2, 2);
         Target_C : Ks_Image_24_Planar_Color := Create (2, 2);
      begin
         Give_Spaces (Empty_8);
         Ks_Image_8_Grey'Write (Stream'Access, Empty_8);
         Ks_Image_8_Grey'Read (Stream'Access, Target_8);
         Check (not Target_8.Allocated and then Target_8.Width = 0,
                "unallocated 8-bit round trip");
         Check_Spaces (Target_8, Empty_8, "unallocated 8-bit");
         Ks_Image'Class'Output (Stream'Access, Ks_Image'Class (Empty_16));
         declare
            R : constant Ks_Image'Class := Ks_Image'Class'Input (Stream'Access);
         begin
            Check (R in Ks_Image_16_Grey and then not R.Allocated,
                   "unallocated 16-bit round trip");
         end;
         Ks_Image_24_Planar_Color'Write (Stream'Access, Empty_C);
         Ks_Image_24_Planar_Color'Read (Stream'Access, Target_C);
         Check (not Target_C.Allocated
                  and then not Target_C.Get_Plane (Red).Allocated,
                "unallocated colour round trip");
         Check (Stream.Element_Count = 0, "unallocated: nothing left over");
      end;

      --  The parent part alone carries only the coordinate space state.
      declare
         A      : Ks_Image_8_Grey := Patterned (2, 2);
         Target : Ks_Image_16_Grey := Create (3, 1, 7);
         Stream : aliased Storage.Stream_Type;
      begin
         Give_Spaces (A);
         Ks_Image'Write (Stream'Access, Ks_Image (A));
         Ks_Image'Read (Stream'Access, Ks_Image (Target));
         Check (Target.Width = 3 and then Target.Get_Pixel (2, 0) = 7,
                "Ks_Image'Read keeps the pixels");
         Check_Spaces (Target, A, "Ks_Image'Read");
      end;

      --  A truncated stream: Ks_Image_File_Exception, and the target is
      --  left as a default image while other users keep the old pixels.
      declare
         A      : Ks_Image_8_Grey := Patterned (6, 4);
         Stream : aliased Storage.Stream_Type;
      begin
         Give_Spaces (A);
         Ks_Image_8_Grey'Write (Stream'Access, A);
         declare
            Full : constant Ada.Streams.Stream_Element_Array :=
              Contents (Stream);

            type Cut_Array is array (Positive range <>) of
              Ada.Streams.Stream_Element_Offset;
         begin
            --  In the header, the pixel-from-root transform, the first
            --  space name, the second space's transform, the selected name
            --  and the pixels.
            for Cut of Cut_Array'[6, 20, 70, 130, 250, Full'Last - 1] loop
               declare
                  Short  : aliased Storage.Stream_Type;
                  Target : Ks_Image_8_Grey := Create (3, 3, 9);
                  Keep   : constant Ks_Image_8_Grey := Target;

                  procedure Read_Short is
                  begin
                     Ks_Image_8_Grey'Read (Short'Access, Target);
                  end Read_Short;

                  procedure T is new Check_Raises_Exactly
                    (Read_Short, Stream_Error);
               begin
                  Target.Coordinate_Space_Tree.Add_Space ("@", "Old", P);
                  Target.Set_Selected_Space_Name ("@\Old");
                  Short.Write (Full (1 .. Cut));
                  T ("stream cut after" & Cut'Image & " elements");
                  Check_Default (Target, "after a cut at" & Cut'Image);
                  Check (All_Equal (Keep, 9) and then Keep.Width = 3,
                         "other users keep the old pixels");
               end;
            end loop;
         end;
         --  Truncated colour data, through 'Input.
         declare
            C      : constant Ks_Image_24_Planar_Color := Colour_Pattern;
            Short  : aliased Storage.Stream_Type;

            procedure Input_Short is
               R : constant Ks_Image'Class := Ks_Image'Class'Input
                 (Short'Access);
            begin
               Check (not R.Allocated, "unreachable");
            end Input_Short;

            procedure T is new Check_Raises_Exactly (Input_Short, Stream_Error);
         begin
            Ks_Image'Class'Output (Stream'Access, Ks_Image'Class (C));
            declare
               Full : constant Ada.Streams.Stream_Element_Array :=
                 Contents (Stream);
            begin
               Short.Write (Full (1 .. Full'Last - 5));
            end;
            T ("class-wide 'Input of a truncated colour image");
         end;
      end;

      --  Malformed headers and spaces.
      declare
         type Case_Kind is
           (Huge, Huge_Width, One_Zero, Wrong_Type, Not_Finite, Singular,
            Orphan, Duplicate, Bad_Component, Bad_Selection);

         procedure Build
           (Kind : Case_Kind;
            Stream : not null access Ada.Streams.Root_Stream_Type'Class) is
            Inf : constant U64 := 16#7FF0_0000_0000_0000#;
         begin
            case Kind is
               when Huge =>
                  Put_Header (Stream, 65_536, 65_536);
                  return;
               when Huge_Width =>
                  Put_Header (Stream, U32 (Natural'Last) + 1, 1);
                  return;
               when One_Zero =>
                  Put_Header (Stream, 0, 5);
                  return;
               when Wrong_Type =>
                  U32'Write
                    (Stream, Code_Of (Ks_Image_16_Grey'(Create (1, 1))));
                  U32'Write (Stream, 1);
                  U32'Write (Stream, 1);
                  return;
               when others =>
                  Put_Header (Stream, 1, 1);
            end case;
            case Kind is
               when Not_Finite =>
                  U64'Write (Stream, Inf);
                  Put_Transform (Stream, 0.0, 0.0, 1.0, 0.0, 0.0, 0.0);
                  return;
               when Singular =>
                  Put_Transform (Stream, 1.0, 2.0, 2.0, 4.0, 0.0, 0.0);
                  return;
               when others =>
                  Put_Transform (Stream, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
            end case;
            case Kind is
               when Orphan =>
                  U32'Write (Stream, 1);
                  Put_Name (Stream, "@\A\B");
               when Duplicate =>
                  U32'Write (Stream, 2);
                  Put_Name (Stream, "@\A");
                  Put_Transform (Stream, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
                  Put_Name (Stream, "@\A");
               when Bad_Component =>
                  U32'Write (Stream, 1);
                  Put_Name (Stream, "@\#");
               when others =>
                  U32'Write (Stream, 1);
                  Put_Name (Stream, "@\A");
            end case;
            Put_Transform (Stream, 1.0, 0.0, 0.0, 1.0, 0.0, 0.0);
            Put_Name (Stream, "@\Z");  --  Bad_Selection
         end Build;
      begin
         for Kind in Case_Kind loop
            declare
               Stream : aliased Storage.Stream_Type;
               Target : Ks_Image_8_Grey := Grey;

               procedure Read_It is
               begin
                  Ks_Image_8_Grey'Read (Stream'Access, Target);
               end Read_It;

               procedure T is new Check_Raises_Exactly (Read_It, Stream_Error);
            begin
               Build (Kind, Stream'Access);
               T ("malformed stream: " & Kind'Image);
               Check_Default (Target, "after " & Kind'Image);
            end;
         end loop;
         Check (Has_Pattern (Grey), "the targets' old pixels are intact");

         --  The size limit is the one of Create, checked before anything
         --  is allocated: 46341 x 46341 exceeds Natural'Last, 46340 x 46340
         --  does not (that stream is then rejected because it ends before
         --  the coordinate spaces, still without allocating pixels).
         declare
            procedure Check_Message
              (Width, Height : U32; Expected : String)
            is
               Stream : aliased Storage.Stream_Type;
               Target : Ks_Image_8_Grey;
            begin
               Put_Header (Stream'Access, Width, Height);
               Ks_Image_8_Grey'Read (Stream'Access, Target);
               Fail ("size accepted:" & Width'Image & " x" & Height'Image);
            exception
               when E : Ks_Image_File_Exception =>
                  declare
                     Message : constant String :=
                       Ada.Exceptions.Exception_Message (E);
                  begin
                     Check (Message = "Ks_Image_8_Grey'Read: " & Expected,
                            "size message: " & Message);
                  end;
            end Check_Message;
         begin
            Check_Message
              (65_536, 65_536, "the image size 65536 x 65536 is too large");
            Check_Message
              (46_341, 46_341, "the image size 46341 x 46341 is too large");
            Check_Message
              (46_340, 46_340,
               "the stream ends before the image is complete");
         end;
      end;
   end Test_Streams;

   procedure Test_Size_Limits is
      procedure Too_Big is
         Image : constant Ks_Image_8_Grey := Create (65_536, 65_536);
      begin
         Check (not Image.Allocated, "unreachable");
      end Too_Big;

      procedure Allocate_Too_Big is
         Image : Ks_Image_16_Grey;
      begin
         Image.Allocate (Positive'Last, 2);
      end Allocate_Too_Big;

      procedure Colour_Too_Big is
         Image : constant Ks_Image_24_Planar_Color :=
           Create (100_000, 100_000);
      begin
         Check (not Image.Allocated, "unreachable");
      end Colour_Too_Big;

      procedure T1 is new Check_Raises_Exactly (Too_Big, Bad_Parameter);
      procedure T2 is new Check_Raises_Exactly
        (Allocate_Too_Big, Bad_Parameter);
      procedure T3 is new Check_Raises_Exactly
        (Colour_Too_Big, Bad_Parameter);
   begin
      Section ("size limits");
      T1 ("Create with Width * Height > Natural'Last");
      T2 ("Allocate with Width * Height > Natural'Last");
      T3 ("colour Create with Width * Height > Natural'Last");
   end Test_Size_Limits;

   procedure Run_All is
   begin
      Test_Defaults;
      Test_Create_And_Pixels;
      Test_Pixel_Errors;
      Test_Rows_And_Matrix;
      Test_Sharing;
      Test_Spaces_Copied;
      Test_Copy_No_Pixels;
      Test_Space_Names;
      Test_Removed_Selection;
      Test_Get_Transform;
      Test_16_Bit;
      Test_Colour;
      Test_Reference_Count_Stress;
      Test_Streams;
      Test_Size_Limits;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Images;
