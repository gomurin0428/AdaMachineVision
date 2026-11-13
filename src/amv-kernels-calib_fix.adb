pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.Calib_Fix.Checkerboard;
with AMV.Kernels.Calib_Fix.DOF_Fits;
with AMV.Kernels.Calib_Fix.Radial;
with AMV.Kernels.Calib_Fix.Warp;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Calib_Fix with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);

   package N renames AMV.Kernels.Numerics;

   use type KT.Ks_Transform_2D_Linear;
   use type Radial.Observation_Array_Access;

   procedure Free is new Ada.Unchecked_Deallocation
     (Pair_Array, Pair_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Point_Pairs_Data, Ks_Point_Pairs);
   procedure Free is new Ada.Unchecked_Deallocation
     (Corner_Array, Corner_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Calibration_Data, Ks_Calibration);
   procedure Free is new Ada.Unchecked_Deallocation
     (Radial.Observation_Array, Radial.Observation_Array_Access);

   Identity_Fit : constant Ks_N_Point_To_N_Point_Fit := (others => <>);

   No_Model : constant Ks_Radial_Warp_Model := (others => <>);

   No_Pairs : constant Pair_Array (0 .. -1) := [others => (others => <>)];

   Initial_Capacity : constant := 8;

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Pairs (Pairs : out Ks_Point_Pairs)
   with
     Global => null,
     Post   => (if Pairs /= null
                then Pairs.Count = 0 and then Pairs.Pairs = null);
   --  A new list without pairs, or null when the memory cannot be
   --  allocated. Trusted: the allocator raises Storage_Error, which SPARK
   --  cannot express.

   procedure Allocate_Pairs (Pairs : out Ks_Point_Pairs)
     with SPARK_Mode => Off
   is
   begin
      Pairs := new Ks_Point_Pairs_Data;
   exception
      when Storage_Error =>
         Pairs := null;
   end Allocate_Pairs;

   procedure Allocate_Pair_Array
     (Capacity : Positive;
      Pairs    : out Pair_Array_Access)
   with
     Global => null,
     Pre    => Capacity <= Max_Pairs,
     Post   => (if Pairs /= null
                then Pairs'First = 0 and then Pairs'Last = Capacity - 1);
   --  A new array of Capacity pairs (all 0), or null. Trusted as above.

   procedure Allocate_Pair_Array
     (Capacity : Positive;
      Pairs    : out Pair_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Pairs := new Pair_Array (0 .. Capacity - 1);
   exception
      when Storage_Error =>
         Pairs := null;
   end Allocate_Pair_Array;

   procedure Allocate_Corners
     (Capacity : Positive;
      Corners  : out Corner_Array_Access)
   with
     Global => null,
     Pre    => Capacity <= Max_Corners,
     Post   => (if Corners /= null
                then Corners'First = 0
                     and then Corners'Last = Capacity - 1);
   --  A new array of Capacity corners (the record's defaults), or null.
   --  Trusted as above.

   procedure Allocate_Corners
     (Capacity : Positive;
      Corners  : out Corner_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Corners := new Corner_Array (0 .. Capacity - 1);
   exception
      when Storage_Error =>
         Corners := null;
   end Allocate_Corners;

   procedure Allocate_Observations
     (Count  : Positive;
      Points : out Radial.Observation_Array_Access)
   with
     Global => null,
     Pre    => Count <= Max_Warp_Points,
     Post   => (if Points /= null
                then Points'First = 0 and then Points'Last = Count - 1);
   --  A new array of Count points for the nonlinear fit (the record's
   --  defaults), or null. Trusted as above.

   procedure Allocate_Observations
     (Count  : Positive;
      Points : out Radial.Observation_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Points := new Radial.Observation_Array (0 .. Count - 1);
   exception
      when Storage_Error =>
         Points := null;
   end Allocate_Observations;

   procedure Allocate_Calibration (Calibration : out Ks_Calibration)
   with
     Global => null,
     Post   => (if Calibration /= null
                then Calibration.Kind = Kind_N_Point_To_N_Point
                     and then Calibration.DOF
                                = DOF_Scaling_Aspect_Rotation_Skew_And_Translation
                     and then Calibration.Tile_X = 1.0
                     and then Calibration.Tile_Y = 1.0
                     and then Calibration.Pairs = null
                     and then Calibration.Corners = null
                     and then Calibration.Image_Width = 0
                     and then Calibration.Image_Height = 0
                     and then Calibration.Calibrated = False_Value
                     and then Calibration.Fit = Identity_Fit
                     and then Calibration.Mode = Mode_Linear
                     and then Calibration.Model = No_Model
                     and then Calibration.Adjustment = Default_Adjustment);
   --  A new calibration record with the record's defaults, or null.
   --  Trusted as above.

   procedure Allocate_Calibration (Calibration : out Ks_Calibration)
     with SPARK_Mode => Off
   is
   begin
      Calibration := new Ks_Calibration_Data;
   exception
      when Storage_Error =>
         Calibration := null;
   end Allocate_Calibration;

   ---------------------------------------------------------------------
   --  Messages
   ---------------------------------------------------------------------

   procedure Bad (Status : out Ks_Status; Message : String)
   with
     Pre  => Message'Length <= 160,
     Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   function Image_Of (Value : Int64) return String
   with Pre  => Value >= 0,
        Post => Image_Of'Result'First = 1
                and then Image_Of'Result'Length in 1 .. 20;
   --  The decimal digits of Value.

   function Image_Of (Value : Int64) return String is
      Text  : String (1 .. 20) := [others => '0'];
      Rest  : Int64 := Value;
      First : Positive;
   begin
      for K in reverse 1 .. 20 loop
         Text (K) := Character'Val (Character'Pos ('0') + Rest mod 10);
         Rest := Rest / 10;
         First := K;
         exit when Rest = 0;
         pragma Loop_Invariant (First = K and then Rest >= 1);
      end loop;
      declare
         Last   : constant Natural := 21 - First;
         Result : constant String (1 .. Last) := Text (First .. 20);
      begin
         return Result;
      end;
   end Image_Of;

   procedure Bad_Index
     (Status : out Ks_Status;
      Index  : Int32;
      Count  : Natural)
   with
     Pre  => Count <= Max_Pairs,
     Post => Valid (Status)
             and then Status.Failure = Failure_Index_Out_Of_Range;

   procedure Bad_Index
     (Status : out Ks_Status;
      Index  : Int32;
      Count  : Natural) is
   begin
      if Index < 0 then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Index must be >= 0");
      else
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Index must be below NumPoints ("
                      & Image_Of (Int64 (Count)) & ")");
      end if;
   end Bad_Index;

   function Bounded (X : Long_Float) return Boolean is
     (X >= -Max_Value and then X <= Max_Value);
   --  X is finite and within Max_Value (False for NaN at run time).

   ---------------------------------------------------------------------
   --  Point pairs
   ---------------------------------------------------------------------

   procedure Release (Pairs : in out Ks_Point_Pairs)
   with Post => Pairs = null;

   procedure Release (Pairs : in out Ks_Point_Pairs) is
   begin
      if Pairs /= null then
         Free (Pairs.Pairs);
         Free (Pairs);
      end if;
   end Release;

   procedure Check_Pairs
     (Pairs  : access constant Ks_Point_Pairs_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then Succeeded (Status)
                           = (Pairs = null or else Valid_Pairs (Pairs));

   procedure Check_Pairs
     (Pairs  : access constant Ks_Point_Pairs_Data;
      Status : out Ks_Status) is
   begin
      if Pairs = null or else Valid_Pairs (Pairs) then
         Set_Success (Status);
      else
         Bad (Status, "Point pairs: the handle is not consistent");
      end if;
   end Check_Pairs;

   procedure Grow
     (Pairs  : Ks_Point_Pairs;
      Status : out Ks_Status)
   with
     Pre  => Valid_Pairs (Pairs) and then Pairs.Count < Max_Pairs,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then Valid_Pairs (Pairs)
             and then Pairs.Count = Pairs.Count'Old
             and then (if Succeeded (Status)
                       then Pairs.Pairs /= null
                            and then Pairs.Count <= Pairs.Pairs'Last);
   --  Makes room for one more pair (doubling the room when it is full).

   procedure Grow
     (Pairs  : Ks_Point_Pairs;
      Status : out Ks_Status)
   is
      Count    : constant Natural := Pairs.Count;
      Capacity : Positive;
      Fresh    : Pair_Array_Access;
   begin
      if Pairs.Pairs /= null and then Count <= Pairs.Pairs'Last then
         Set_Success (Status);
         return;
      end if;
      Capacity := Natural'Min
        (Natural'Max (2 * Count, Initial_Capacity), Max_Pairs);
      Allocate_Pair_Array (Capacity, Fresh);
      if Fresh = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "AddPointPair: not enough memory");
         return;
      end if;
      for J in 0 .. Count - 1 loop
         Fresh (J) := Pairs.Pairs (J);
         pragma Loop_Invariant
           (Fresh'First = 0 and then Fresh'Last = Capacity - 1);
      end loop;
      Free (Pairs.Pairs);
      Pairs.Pairs := Fresh;
      Set_Success (Status);
   end Grow;

   procedure Pairs_Num_Points
     (Pairs  : access constant Ks_Point_Pairs_Data;
      Count  : out Int32;
      Status : out Ks_Status) is
   begin
      Count := 0;
      Check_Pairs (Pairs, Status);
      if Succeeded (Status) then
         Count := Int32 (Count_Of (Pairs));
      end if;
   end Pairs_Num_Points;

   procedure Pairs_Add_Point_Pair
     (Pairs              : in out Ks_Point_Pairs;
      A_X, A_Y, B_X, B_Y : Long_Float;
      Status             : out Ks_Status)
   is
      Created : Boolean := False;
   begin
      if not (Bounded (A_X) and then Bounded (A_Y) and then Bounded (B_X)
              and then Bounded (B_Y))
      then
         Bad (Status, "AddPointPair: every coordinate must be finite and "
                      & "within +/-1.0E150");
         return;
      end if;
      Check_Pairs (Pairs, Status);
      if not Succeeded (Status) then
         return;
      elsif Count_Of (Pairs) = Max_Pairs then
         Bad (Status, "AddPointPair: the list already holds the most pairs "
                      & "(524288)");
         return;
      end if;
      if Pairs = null then
         Allocate_Pairs (Pairs);
         if Pairs = null then
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "AddPointPair: not enough memory");
            return;
         end if;
         Created := True;
      end if;
      Grow (Pairs, Status);
      if not Succeeded (Status) then
         if Created then
            Release (Pairs);
         end if;
         return;
      end if;
      Pairs.Pairs (Pairs.Count) := (A_X, A_Y, B_X, B_Y);
      Pairs.Count := Pairs.Count + 1;
   end Pairs_Add_Point_Pair;

   procedure Pairs_Delete_Point_Pair
     (Pairs  : Ks_Point_Pairs;
      Index  : Int32;
      Status : out Ks_Status) is
   begin
      Check_Pairs (Pairs, Status);
      if not Succeeded (Status) then
         return;
      elsif Index < 0 or else Index >= Int32 (Count_Of (Pairs)) then
         Bad_Index (Status, Index, Count_Of (Pairs));
         return;
      end if;
      declare
         Count    : constant Natural := Pairs.Count;
         Position : constant Natural := Natural (Index);
      begin
         for J in Position .. Count - 2 loop
            Pairs.Pairs (J) := Pairs.Pairs (J + 1);
            pragma Loop_Invariant
              (Pairs.Count = Count and then Valid_Pairs (Pairs));
         end loop;
         Pairs.Count := Count - 1;
      end;
   end Pairs_Delete_Point_Pair;

   procedure Check_Pair_Index
     (Pairs  : access constant Ks_Point_Pairs_Data;
      Index  : Int32;
      Group  : Int32;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter
                            | Failure_Index_Out_Of_Range
                and then (if Succeeded (Status)
                          then Valid_Pairs (Pairs)
                               and then Group in Group_A | Group_B
                               and then Index in 0 .. Int32 (Pairs.Count) - 1);

   procedure Check_Pair_Index
     (Pairs  : access constant Ks_Point_Pairs_Data;
      Index  : Int32;
      Group  : Int32;
      Status : out Ks_Status) is
   begin
      Check_Pairs (Pairs, Status);
      if not Succeeded (Status) then
         return;
      elsif Group not in Group_A | Group_B then
         Bad (Status, "Group must be KS_POINT_GROUP_A (0) or "
                      & "KS_POINT_GROUP_B (1)");
      elsif Index < 0 or else Index >= Int32 (Count_Of (Pairs)) then
         Bad_Index (Status, Index, Count_Of (Pairs));
      end if;
   end Check_Pair_Index;

   procedure Pairs_Get_Point
     (Pairs  : access constant Ks_Point_Pairs_Data;
      Index  : Int32;
      Group  : Int32;
      X, Y   : out Long_Float;
      Status : out Ks_Status) is
   begin
      X := 0.0;
      Y := 0.0;
      Check_Pair_Index (Pairs, Index, Group, Status);
      if Succeeded (Status) then
         declare
            P : constant Ks_Point_Pair := Pairs.Pairs (Natural (Index));
         begin
            X := (if Group = Group_A then P.A_X else P.B_X);
            Y := (if Group = Group_A then P.A_Y else P.B_Y);
         end;
      end if;
   end Pairs_Get_Point;

   procedure Pairs_Set_Point
     (Pairs  : Ks_Point_Pairs;
      Index  : Int32;
      Group  : Int32;
      X, Y   : Long_Float;
      Status : out Ks_Status) is
   begin
      if not (Bounded (X) and then Bounded (Y)) then
         Bad (Status, "SetPoint: the coordinates must be finite and within "
                      & "+/-1.0E150");
         return;
      end if;
      Check_Pair_Index (Pairs, Index, Group, Status);
      if Succeeded (Status) then
         if Group = Group_A then
            Pairs.Pairs (Natural (Index)).A_X := X;
            Pairs.Pairs (Natural (Index)).A_Y := Y;
         else
            Pairs.Pairs (Natural (Index)).B_X := X;
            Pairs.Pairs (Natural (Index)).B_Y := Y;
         end if;
      end if;
   end Pairs_Set_Point;

   procedure Pairs_Clear
     (Pairs  : Ks_Point_Pairs;
      Status : out Ks_Status) is
   begin
      Check_Pairs (Pairs, Status);
      if Succeeded (Status) and then Pairs /= null then
         Free (Pairs.Pairs);
         Pairs.Count := 0;
      end if;
   end Pairs_Clear;

   procedure Copy_Pairs
     (Pairs  : access constant Ks_Point_Pairs_Data;
      Copy   : out Ks_Point_Pairs;
      Status : out Ks_Status)
   with
     Pre  => Valid_Pairs (Pairs),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Pairs (Copy)
                            and then Copy.Count = Pairs.Count
                       else Copy = null);
   --  A new list with the pairs of a valid list.

   procedure Copy_Pairs
     (Pairs  : access constant Ks_Point_Pairs_Data;
      Copy   : out Ks_Point_Pairs;
      Status : out Ks_Status) is
   begin
      Allocate_Pairs (Copy);
      if Copy = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Point pairs: not enough memory");
         return;
      end if;
      Set_Success (Status);
      if Pairs.Count = 0 then
         return;
      end if;
      Allocate_Pair_Array (Pairs.Count, Copy.Pairs);
      if Copy.Pairs = null then
         Release (Copy);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Point pairs: not enough memory");
         return;
      end if;
      for J in 0 .. Pairs.Count - 1 loop
         Copy.Pairs (J) := Pairs.Pairs (J);
         pragma Loop_Invariant
           (Copy /= null and then Copy.Pairs /= null
            and then Copy.Count = 0
            and then Copy.Pairs'First = 0
            and then Copy.Pairs'Last = Pairs.Count - 1);
      end loop;
      Copy.Count := Pairs.Count;
   end Copy_Pairs;

   procedure Pairs_Duplicate
     (Pairs  : access constant Ks_Point_Pairs_Data;
      Copy   : out Ks_Point_Pairs;
      Status : out Ks_Status) is
   begin
      Copy := null;
      Check_Pairs (Pairs, Status);
      if not Succeeded (Status) or else Pairs = null then
         return;
      end if;
      Copy_Pairs (Pairs, Copy, Status);
   end Pairs_Duplicate;

   procedure Pairs_Destroy (Pairs : in out Ks_Point_Pairs) is
   begin
      Release (Pairs);
   end Pairs_Destroy;

   ---------------------------------------------------------------------
   --  The fit
   ---------------------------------------------------------------------

   procedure Fit_Pairs
     (Pairs  : access constant Ks_Point_Pairs_Data;
      DOF    : Int32;
      Prefix : String;
      Fit    : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status)
   with
     Pre  => Prefix'First = 1 and then Prefix'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if DOF in DOF_Code
                         and then Count_Of (Pairs) < Min_Points (DOF)
                       then Status.Failure = Failure_Bad_Parameter)
             and then (if Succeeded (Status)
                       then DOF in DOF_Code
                            and then Count_Of (Pairs) >= Min_Points (DOF)
                            and then Gold_Fit (Fit, DOF)
                       else Fit = Identity_Fit);
   --  The checks of the fit (the DOF code first, the handle, the minimum
   --  count), then the fit. Prefix names the property holding the DOF
   --  ("" or "RunParams.").

   procedure Fit_Pairs
     (Pairs  : access constant Ks_Point_Pairs_Data;
      DOF    : Int32;
      Prefix : String;
      Fit    : out Ks_N_Point_To_N_Point_Fit;
      Status : out Ks_Status) is
   begin
      Fit := Identity_Fit;
      if DOF not in DOF_Code then
         Bad (Status, Prefix & "DOFsToCompute must be a "
                      & "CogNPointToNPointDOFConstants value (0 .. 7)");
         return;
      end if;
      Check_Pairs (Pairs, Status);
      if not Succeeded (Status) then
         return;
      elsif Count_Of (Pairs) < Min_Points (DOF) then
         Bad (Status, Prefix & "NumPoints must be at least "
                      & Image_Of (Int64 (Min_Points (DOF)))
                      & " for these DOFsToCompute");
         return;
      end if;
      if Pairs = null or else Pairs.Pairs = null then
         DOF_Fits.Fit (No_Pairs, 0, DOF, Fit, Status);
      else
         DOF_Fits.Fit (Pairs.Pairs.all, Pairs.Count, DOF, Fit, Status);
      end if;
   end Fit_Pairs;

   procedure N_Point_To_N_Point_Compute
     (Pairs           : access constant Ks_Point_Pairs_Data;
      DOFs_To_Compute : Int32;
      Fit             : out Ks_N_Point_To_N_Point_Fit;
      Status          : out Ks_Status) is
   begin
      Fit_Pairs (Pairs, DOFs_To_Compute, "", Fit, Status);
   end N_Point_To_N_Point_Compute;

   ---------------------------------------------------------------------
   --  The output space
   ---------------------------------------------------------------------

   function Valid_Component (Name : KC.Ks_Space_Name) return Boolean is
     (Name.Length in 1 .. KC.Max_Name_Length
      and then (for all J in 1 .. Integer (Name.Length)
                => Name.Text (J) /= KC.Separator)
      and then (if Name.Length = 1
                then Name.Text (1)
                       not in KC.Root_Character | KC.Pixel_Character
                            | KC.Selected_Character));
   --  Name is a valid path component (as AMV.Kernels.Coordinate_Spaces
   --  requires of a new space's name).

   procedure Join
     (Parent, Name : KC.Ks_Space_Name;
      Full         : out KC.Ks_Space_Name;
      Fits         : out Boolean)
   with
     Pre  => KC.Fits (Parent) and then KC.Fits (Name),
     Post => KC.Fits (Full);
   --  Parent & '\' & Name; Fits is False (and Full empty) when that is
   --  longer than Max_Name_Length.

   procedure Join
     (Parent, Name : KC.Ks_Space_Name;
      Full         : out KC.Ks_Space_Name;
      Fits         : out Boolean)
   is
      P : constant Integer := Integer (Parent.Length);
      L : constant Integer := Integer (Name.Length);
   begin
      Full := (Length => 0, Text => [others => ASCII.NUL]);
      Fits := P + 1 + L <= KC.Max_Name_Length;
      if not Fits then
         return;
      end if;
      for J in 1 .. P loop
         Full.Text (J) := Parent.Text (J);
      end loop;
      Full.Text (P + 1) := KC.Separator;
      for J in 1 .. L loop
         Full.Text (P + 1 + J) := Name.Text (J);
      end loop;
      Full.Length := Int32 (P + 1 + L);
   end Join;

   procedure Add_Output_Space
     (Tree               : in out KC.Ks_Coordinate_Space_Tree;
      Selected           : in out KC.Ks_Space_Name;
      Pixel_From_Root    : KT.Ks_Transform_2D_Linear;
      Old_From_New       : KT.Ks_Transform_2D_Linear;
      Name               : KC.Ks_Space_Name;
      Space_To_Output    : Int32;
      Duplicate_Handling : Int32;
      Name_Property      : String;
      Transform_Property : String;
      Status             : out Ks_Status)
   with
     Pre  => Name_Property'First = 1 and then Name_Property'Length <= 60
             and then Transform_Property'First = 1
             and then Transform_Property'Length <= 60,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Image_Bad_Selected_Space_Name
                         | Failure_Transform_Singular | Failure_Other
             and then (if Succeeded (Status)
                       then KC.Valid_Tree (Tree) and then KC.Fits (Selected));
   --  Adds the space Name under the input's selected space (under "@" by
   --  the pixel space rule) with Old_From_New and updates the selection,
   --  as described in the spec.

   procedure Add_Output_Space
     (Tree               : in out KC.Ks_Coordinate_Space_Tree;
      Selected           : in out KC.Ks_Space_Name;
      Pixel_From_Root    : KT.Ks_Transform_2D_Linear;
      Old_From_New       : KT.Ks_Transform_2D_Linear;
      Name               : KC.Ks_Space_Name;
      Space_To_Output    : Int32;
      Duplicate_Handling : Int32;
      Name_Property      : String;
      Transform_Property : String;
      Status             : out Ks_Status)
   is
      Current         : KC.Ks_Space_Name;
      Parent          : KC.Ks_Space_Name;
      Full            : KC.Ks_Space_Name;
      Fits            : Boolean;
      Inverse         : KT.Ks_Transform_2D_Linear;
      Root_From_Pixel : KT.Ks_Transform_2D_Linear;
      Parent_From_New : KT.Ks_Transform_2D_Linear;
      Exists          : Int32;
   begin
      if Space_To_Output not in Space_To_Output_New | Space_To_Output_Old
      then
         Bad (Status, "RunParams.SpaceToOutput must be 0 (the new space) "
                      & "or 1 (the input's space)");
         return;
      elsif Duplicate_Handling
              not in Duplicate_Compatibility | Duplicate_Enhanced
      then
         Bad (Status, "RunParams.FixturedSpaceNameDuplicateHandling must be "
                      & "1 (Compatibility) or 2 (Enhanced)");
         return;
      elsif not Valid_Component (Name) then
         Bad (Status, Name_Property & " must be a valid space name (not "
                      & "empty, without '\', not ""@"", ""#"" or ""."")");
         return;
      elsif not KT.Bounded (Old_From_New) then
         Bad (Status, Transform_Property
                      & " must be finite and within +/-1.0E150");
         return;
      end if;
      KT.Invert (Old_From_New, Inverse, Status);
      if not Succeeded (Status) or else not KT.Bounded (Inverse) then
         Set_Failure (Status, Failure_Transform_Singular,
                      Transform_Property & " is not invertible");
         return;
      end if;

      --  The selection as it reads: "#" or a space of the tree.
      KI.Selected_Space_Name (Tree, Selected, Current, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Current.Length = 1 and then Current.Text (1) = KC.Pixel_Character
      then
         Parent := KI.Root_Space_Name;
         KI.Get_Transform
           (Tree, Selected, Pixel_From_Root, KI.Root_Space_Name,
            KI.Pixel_Space_Name, Root_From_Pixel, Status);
         if not Succeeded (Status) then
            return;
         end if;
         KT.Compose (Root_From_Pixel, Old_From_New, Parent_From_New, Status);
         if not Succeeded (Status) then
            return;
         end if;
      else
         Parent := Current;
         Parent_From_New := Old_From_New;
      end if;

      Join (Parent, Name, Full, Fits);
      if not Fits then
         Bad (Status, Name_Property & ": the full name of the new space "
                      & "would exceed 256 characters");
         return;
      end if;
      if Duplicate_Handling = Duplicate_Enhanced then
         KC.Space_Exists (Tree, Full, Exists, Status);
         if not Succeeded (Status) then
            return;
         elsif Exists = True_Value then
            Bad (Status, Name_Property & ": the space exists already "
                         & "(Enhanced duplicate handling)");
            return;
         end if;
      end if;
      KC.Add_Space
        (Tree, Parent, Name, Parent_From_New,
         KC.Add_Space_Replace_Duplicate, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Space_To_Output = Space_To_Output_New then
         KI.Set_Selected_Space_Name (Tree, Selected, Full, Status);
         if not Succeeded (Status) then
            --  A guard: the space has just been added.
            Set_Failure (Status, Failure_Other,
                         Name_Property & ": the new space cannot be "
                         & "selected");
            return;
         end if;
      else
         Selected := Current;
      end if;
      Set_Success (Status);
   end Add_Output_Space;

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                and then (Status.Failure = Failure_Image_No_Pixels)
                           = (Image = null)
                and then (if Succeeded (Status)
                          then KI.Valid_Image (Image));

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      if Image = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "InputImage has no pixels");
      elsif not KI.Valid_Image (Image) then
         Bad (Status, "InputImage is not a valid image");
      else
         Set_Success (Status);
      end if;
   end Check_Input_Image;

   ---------------------------------------------------------------------
   --  The fixture tools
   ---------------------------------------------------------------------

   procedure Fixture_Run_Params_Default
     (Params : out Ks_Fixture_Run_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Fixture_Run_Params_Default;

   procedure Fixture_Execute
     (Input_Image     : access constant KI.Ks_Image_8_Grey_Data;
      Params          : Ks_Fixture_Run_Params;
      Tree            : in out KC.Ks_Coordinate_Space_Tree;
      Selected        : in out KC.Ks_Space_Name;
      Pixel_From_Root : KT.Ks_Transform_2D_Linear;
      Status          : out Ks_Status) is
   begin
      Check_Input_Image (Input_Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Add_Output_Space
        (Tree, Selected, Pixel_From_Root,
         Params.Unfixtured_From_Fixtured_Transform,
         Params.Fixtured_Space_Name, Params.Space_To_Output,
         Params.Fixtured_Space_Name_Duplicate_Handling,
         "RunParams.FixturedSpaceName",
         "RunParams.UnfixturedFromFixturedTransform", Status);
   end Fixture_Execute;

   procedure Fixture_N_Point_To_N_Point_Run_Params_Default
     (Params : out Ks_Fixture_N_Point_To_N_Point_Run_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Fixture_N_Point_To_N_Point_Run_Params_Default;

   procedure Fixture_N_Point_To_N_Point_Execute
     (Input_Image     : access constant KI.Ks_Image_8_Grey_Data;
      Pairs           : access constant Ks_Point_Pairs_Data;
      Params          : Ks_Fixture_N_Point_To_N_Point_Run_Params;
      Tree            : in out KC.Ks_Coordinate_Space_Tree;
      Selected        : in out KC.Ks_Space_Name;
      Pixel_From_Root : KT.Ks_Transform_2D_Linear;
      Fit             : out Ks_N_Point_To_N_Point_Fit;
      Status          : out Ks_Status) is
   begin
      Fit := Identity_Fit;
      Check_Input_Image (Input_Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Fit_Pairs (Pairs, Params.DOFs_To_Compute, "RunParams.", Fit, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Add_Output_Space
        (Tree, Selected, Pixel_From_Root, Fit.Transform,
         Params.Fixtured_Space_Name, Params.Space_To_Output,
         Params.Fixtured_Space_Name_Duplicate_Handling,
         "RunParams.FixturedSpaceName", "The fitted transform", Status);
      if not Succeeded (Status) then
         Fit := Identity_Fit;
      end if;
   end Fixture_N_Point_To_N_Point_Execute;

   ---------------------------------------------------------------------
   --  Calibrations
   ---------------------------------------------------------------------

   procedure Release (Calibration : in out Ks_Calibration)
   with Post => Calibration = null;

   procedure Release (Calibration : in out Ks_Calibration) is
   begin
      if Calibration /= null then
         Release (Calibration.Pairs);
         Free (Calibration.Corners);
         Free (Calibration);
      end if;
   end Release;

   procedure Check_Calibration
     (Calibration : access constant Ks_Calibration_Data;
      Operation   : String;
      Status      : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Succeeded (Status) = Valid_Calibration (Calibration);
   --  Bad_Parameter for null and for an inconsistent handle.

   procedure Check_Calibration
     (Calibration : access constant Ks_Calibration_Data;
      Operation   : String;
      Status      : out Ks_Status) is
   begin
      if Calibration = null then
         Bad (Status, Operation & ": the calibration is null");
      elsif not Valid_Calibration (Calibration) then
         Bad (Status, Operation & ": the calibration handle is not "
                      & "consistent");
      else
         Set_Success (Status);
      end if;
   end Check_Calibration;

   procedure Uncalibrate (Calibration : Ks_Calibration)
   with
     Pre  => Valid_Calibration (Calibration),
     Post => Valid_Calibration (Calibration)
             and then Calibration.Calibrated = False_Value
             and then Calibration.Kind = Calibration.Kind'Old
             and then Calibration.DOF = Calibration.DOF'Old
             and then Calibration.Tile_X = Calibration.Tile_X'Old
             and then Calibration.Tile_Y = Calibration.Tile_Y'Old
             and then Calibration.Mode = Calibration.Mode'Old
             and then Calibration.Adjustment = Calibration.Adjustment'Old
             and then (if Calibration.Kind = Kind_N_Point_To_N_Point
                       then Count_Of (Calibration) = Count_Of (Calibration)'Old
                       else Count_Of (Calibration) = 0
                            and then Calibration.Pairs = null
                            and then Calibration.Corners = null);
   --  Forgets the computed state (and the corners of a checkerboard).

   procedure Uncalibrate (Calibration : Ks_Calibration) is
   begin
      Calibration.Calibrated := False_Value;
      Calibration.Fit := Identity_Fit;
      Calibration.Model := No_Model;
      Calibration.Image_Width := 0;
      Calibration.Image_Height := 0;
      if Calibration.Kind = Kind_Checkerboard then
         Release (Calibration.Pairs);
         Free (Calibration.Corners);
      end if;
   end Uncalibrate;

   procedure Calibration_Create
     (Kind        : Int32;
      Calibration : out Ks_Calibration;
      Status      : out Ks_Status) is
   begin
      Calibration := null;
      if Kind not in Kind_Code then
         Bad (Status, "Kind must be KS_CALIBRATION_N_POINT_TO_N_POINT (0) "
                      & "or KS_CALIBRATION_CHECKERBOARD (1)");
         return;
      end if;
      Allocate_Calibration (Calibration);
      if Calibration = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Calibration: not enough memory");
         return;
      end if;
      Calibration.Kind := Kind;
      Set_Success (Status);
   end Calibration_Create;

   procedure Calibration_Destroy (Calibration : in out Ks_Calibration) is
   begin
      Release (Calibration);
   end Calibration_Destroy;

   procedure Calibration_Duplicate
     (Calibration : access constant Ks_Calibration_Data;
      Copy        : out Ks_Calibration;
      Status      : out Ks_Status) is
   begin
      Copy := null;
      if Calibration = null then
         Set_Success (Status);
         return;
      end if;
      Check_Calibration (Calibration, "Duplicate", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Allocate_Calibration (Copy);
      if Copy = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Calibration: not enough memory");
         return;
      end if;
      Copy.Kind := Calibration.Kind;
      Copy.Mode := Calibration.Mode;
      Copy.DOF := Calibration.DOF;
      Copy.Tile_X := Calibration.Tile_X;
      Copy.Tile_Y := Calibration.Tile_Y;
      Copy.Image_Width := Calibration.Image_Width;
      Copy.Image_Height := Calibration.Image_Height;
      if Calibration.Pairs /= null then
         Copy_Pairs (Calibration.Pairs, Copy.Pairs, Status);
         if not Succeeded (Status) then
            Release (Copy);
            return;
         end if;
      end if;
      if Calibration.Corners /= null and then Calibration.Corners'Last >= 0
      then
         declare
            Last : constant Natural := Calibration.Corners'Last;
         begin
            Allocate_Corners (Last + 1, Copy.Corners);
            if Copy.Corners = null then
               Release (Copy);
               Set_Failure (Status, Failure_Out_Of_Memory,
                            "Calibration: not enough memory");
               return;
            end if;
            for J in 0 .. Last loop
               Copy.Corners (J) := Calibration.Corners (J);
               pragma Loop_Invariant
                 (Copy /= null and then Copy.Corners /= null
                  and then Copy.Corners'First = 0
                  and then Copy.Corners'Last = Last);
            end loop;
         end;
      end if;
      Copy.Fit := Calibration.Fit;
      Copy.Model := Calibration.Model;
      Copy.Adjustment := Calibration.Adjustment;
      Copy.Calibrated := Calibration.Calibrated;
      Set_Success (Status);
   end Calibration_Duplicate;

   procedure Calibration_Kind
     (Calibration : access constant Ks_Calibration_Data;
      Kind        : out Int32;
      Status      : out Ks_Status) is
   begin
      Kind := 0;
      Check_Calibration (Calibration, "Kind", Status);
      if Succeeded (Status) then
         Kind := Calibration.Kind;
      end if;
   end Calibration_Kind;

   procedure Calibration_Num_Points
     (Calibration : access constant Ks_Calibration_Data;
      Count       : out Int32;
      Status      : out Ks_Status) is
   begin
      Count := 0;
      Check_Calibration (Calibration, "NumPoints", Status);
      if Succeeded (Status) then
         Count := Int32 (Count_Of (Calibration));
      end if;
   end Calibration_Num_Points;

   procedure Calibration_Get_Point
     (Calibration : access constant Ks_Calibration_Data;
      Index       : Int32;
      Group       : Int32;
      X, Y        : out Long_Float;
      Status      : out Ks_Status) is
   begin
      X := 0.0;
      Y := 0.0;
      Check_Calibration (Calibration, "GetPoint", Status);
      if Succeeded (Status) then
         Pairs_Get_Point (Calibration.Pairs, Index, Group, X, Y, Status);
      end if;
   end Calibration_Get_Point;

   procedure Check_N_Point
     (Calibration : access constant Ks_Calibration_Data;
      Operation   : String;
      Status      : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Kind
                                       = Kind_N_Point_To_N_Point);
   --  The checks of the operations that change the points of an N-point
   --  calibration.

   procedure Check_N_Point
     (Calibration : access constant Ks_Calibration_Data;
      Operation   : String;
      Status      : out Ks_Status) is
   begin
      Check_Calibration (Calibration, Operation, Status);
      if Succeeded (Status)
        and then Calibration.Kind /= Kind_N_Point_To_N_Point
      then
         Bad (Status, Operation & ": a checkerboard calibration takes its "
                      & "points from its CalibrationImage");
      end if;
   end Check_N_Point;

   procedure Calibration_Add_Point_Pair
     (Calibration                        : Ks_Calibration;
      Uncalibrated_X, Uncalibrated_Y     : Long_Float;
      Raw_Calibrated_X, Raw_Calibrated_Y : Long_Float;
      Status                             : out Ks_Status) is
   begin
      Check_N_Point (Calibration, "AddPointPair", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Pairs_Add_Point_Pair
        (Calibration.Pairs, Uncalibrated_X, Uncalibrated_Y,
         Raw_Calibrated_X, Raw_Calibrated_Y, Status);
      if Succeeded (Status) then
         Uncalibrate (Calibration);
      end if;
   end Calibration_Add_Point_Pair;

   procedure Calibration_Delete_Point_Pair
     (Calibration : Ks_Calibration;
      Index       : Int32;
      Status      : out Ks_Status) is
   begin
      Check_N_Point (Calibration, "DeletePointPair", Status);
      if not Succeeded (Status) then
         return;
      elsif Index < 0 or else Index >= Int32 (Count_Of (Calibration)) then
         Bad_Index (Status, Index, Count_Of (Calibration));
         return;
      end if;
      --  Uncalibrate first: a calibrated handle must keep the points its
      --  DOF needs.
      Uncalibrate (Calibration);
      Pairs_Delete_Point_Pair (Calibration.Pairs, Index, Status);
   end Calibration_Delete_Point_Pair;

   procedure Calibration_Set_Point
     (Calibration : Ks_Calibration;
      Index       : Int32;
      Group       : Int32;
      X, Y        : Long_Float;
      Status      : out Ks_Status) is
   begin
      Check_N_Point (Calibration, "SetPoint", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Pairs_Set_Point (Calibration.Pairs, Index, Group, X, Y, Status);
      if Succeeded (Status) then
         Uncalibrate (Calibration);
      end if;
   end Calibration_Set_Point;

   procedure Calibration_DOFs_To_Compute
     (Calibration : access constant Ks_Calibration_Data;
      DOF         : out Int32;
      Status      : out Ks_Status) is
   begin
      DOF := 0;
      Check_Calibration (Calibration, "DOFsToCompute", Status);
      if Succeeded (Status) then
         DOF := Calibration.DOF;
      end if;
   end Calibration_DOFs_To_Compute;

   procedure Calibration_Set_DOFs_To_Compute
     (Calibration : Ks_Calibration;
      DOF         : Int32;
      Status      : out Ks_Status) is
   begin
      Check_Calibration (Calibration, "DOFsToCompute", Status);
      if not Succeeded (Status) then
         return;
      elsif DOF not in DOF_Code then
         Bad (Status, "DOFsToCompute must be a DOF constant (0 .. 7)");
         return;
      end if;
      Uncalibrate (Calibration);
      Calibration.DOF := DOF;
   end Calibration_Set_DOFs_To_Compute;

   procedure Calibration_Physical_Tile_Size
     (Calibration              : access constant Ks_Calibration_Data;
      Tile_Size_X, Tile_Size_Y : out Long_Float;
      Status                   : out Ks_Status) is
   begin
      Tile_Size_X := 1.0;
      Tile_Size_Y := 1.0;
      Check_Calibration (Calibration, "PhysicalTileSize", Status);
      if Succeeded (Status) then
         Tile_Size_X := Calibration.Tile_X;
         Tile_Size_Y := Calibration.Tile_Y;
      end if;
   end Calibration_Physical_Tile_Size;

   procedure Calibration_Set_Physical_Tile_Size
     (Calibration              : Ks_Calibration;
      Tile_Size_X, Tile_Size_Y : Long_Float;
      Status                   : out Ks_Status) is
   begin
      Check_Calibration (Calibration, "PhysicalTileSize", Status);
      if not Succeeded (Status) then
         return;
      elsif Calibration.Kind /= Kind_Checkerboard then
         Bad (Status, "PhysicalTileSize: only a checkerboard calibration "
                      & "has tile sizes");
         return;
      elsif not Valid_Tile (Tile_Size_X) then
         Bad (Status, "PhysicalTileSizeX must be > 0 and at most 1.0E140");
         return;
      elsif not Valid_Tile (Tile_Size_Y) then
         Bad (Status, "PhysicalTileSizeY must be > 0 and at most 1.0E140");
         return;
      end if;
      Uncalibrate (Calibration);
      Calibration.Tile_X := Tile_Size_X;
      Calibration.Tile_Y := Tile_Size_Y;
   end Calibration_Set_Physical_Tile_Size;

   function Raw_Coordinate (Index : Grid_Index; Tile : Long_Float)
      return Coordinate
   is (N.Mul_Within (Long_Float (Index), Tile, Long_Float (Max_Grid_Index),
                     Max_Tile_Size))
   with Pre => Valid_Tile (Tile);
   --  Index * Tile, at most 65536 * 1.0E140 in magnitude.

   procedure Warp_Fit
     (Model               : Ks_Radial_Warp_Model;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Fit                 : out Ks_N_Point_To_N_Point_Fit;
      Status              : out Ks_Status)
   with
     Pre  => Valid_Model (Model) and then KT.Bounded (Selected_From_Pixel),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Valid_Fit (Fit));
   --  The fit record of a calibration in PerspectiveAndRadialWarp mode:
   --  the transform Selected_From_Pixel composed with the model's
   --  Output_Pixel_From_Calibrated (the output's UncalibratedFrom-
   --  Calibrated), its decomposition and the model's RMS error.
   --  Bad_Parameter when it exceeds the bounds or is not invertible
   --  within them.

   procedure Warp_Fit
     (Model               : Ks_Radial_Warp_Model;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Fit                 : out Ks_N_Point_To_N_Point_Fit;
      Status              : out Ks_Status)
   is
      T       : KT.Ks_Transform_2D_Linear;
      Inverse : KT.Ks_Transform_2D_Linear;
      Parts   : KT.Ks_Decomposition;
   begin
      Fit := Identity_Fit;
      KT.Compose (Selected_From_Pixel, Model.Output_Pixel_From_Calibrated,
                  T, Status);
      if not Succeeded (Status) then
         Bad (Status, "Calibrate: the calibrated space's transform exceeds "
                      & "1.0E150 (PerspectiveAndRadialWarp)");
         return;
      elsif Det_Of (T) = 0.0 then
         Bad (Status, "Calibrate: the calibrated space's transform is "
                      & "singular (PerspectiveAndRadialWarp)");
         return;
      end if;
      --  The tool adds the space with T, which must be invertible within
      --  the bounds (as Add_Output_Space checks).
      KT.Invert (T, Inverse, Status);
      if not Succeeded (Status) or else not KT.Bounded (Inverse) then
         Bad (Status, "Calibrate: the calibrated space's transform is "
                      & "singular (PerspectiveAndRadialWarp)");
         return;
      end if;
      KT.Decompose (T, Parts, Status);
      if not Succeeded (Status) then
         Bad (Status, "Calibrate: the calibrated space's transform cannot "
                      & "be decomposed (PerspectiveAndRadialWarp)");
         return;
      end if;
      Fit := (Transform => T,
              RMS_Error => Model.RMS_Error,
              Scaling_X => Parts.Scaling_X,
              Scaling_Y => Parts.Scaling_Y,
              Rotation  => Parts.Rotation_X,
              Skew      => Parts.Skew);
   end Warp_Fit;

   procedure Fit_Model
     (Points              : Radial.Observation_Array;
      Count               : Natural;
      Width, Height       : Int32;
      Tile_X, Tile_Y      : Long_Float;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Model               : out Ks_Radial_Warp_Model;
      Fit                 : out Ks_N_Point_To_N_Point_Fit;
      Status              : out Ks_Status)
   with
     Pre  => Points'First = 0
             and then Count in Min_Warp_Points .. Max_Warp_Points
             and then Count - 1 <= Points'Last
             and then Width >= 1 and then Height >= 1
             and then Valid_Tile (Tile_X) and then Valid_Tile (Tile_Y)
             and then KT.Bounded (Selected_From_Pixel),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Model (Model)
                            and then Model.Image_Width = Width
                            and then Model.Image_Height = Height
                            and then Valid_Fit (Fit));
   --  The nonlinear model of the observed points (pixel positions in an
   --  image of Width x Height pixels; plate points whose calibrated
   --  coordinates are (X * Tile_X, Y * Tile_Y)) and the fit record of the
   --  calibration.

   procedure Fit_Model
     (Points              : Radial.Observation_Array;
      Count               : Natural;
      Width, Height       : Int32;
      Tile_X, Tile_Y      : Long_Float;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Model               : out Ks_Radial_Warp_Model;
      Fit                 : out Ks_N_Point_To_N_Point_Fit;
      Status              : out Ks_Status)
   is
      P          : Radial.Params;
      F          : Radial.Frame;
      RMS        : Long_Float;
      Iterations : Natural;
   begin
      Model := No_Model;
      Fit := Identity_Fit;
      if Width > Max_Model_Side or else Height > Max_Model_Side then
         Bad (Status, "CalibrationImage must be at most 16777216 pixels "
                      & "wide and high (PerspectiveAndRadialWarp)");
         return;
      end if;
      Radial.Fit (Points, Count, Width, Height, P, F, RMS, Iterations,
                  Status);
      if not Succeeded (Status) then
         return;
      end if;
      Warp.Build_Model (P, F, RMS, Iterations, Width, Height, Tile_X, Tile_Y,
                        Model, Status);
      if not Succeeded (Status) then
         Model := No_Model;
         return;
      end if;
      Warp_Fit (Model, Selected_From_Pixel, Fit, Status);
      if not Succeeded (Status) then
         Model := No_Model;
      end if;
   end Fit_Model;

   procedure Fit_Corners
     (Corners             : Corner_Array;
      Count               : Natural;
      Width, Height       : Int32;
      Tile_X, Tile_Y      : Long_Float;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Model               : out Ks_Radial_Warp_Model;
      Fit                 : out Ks_N_Point_To_N_Point_Fit;
      Status              : out Ks_Status)
   with
     Pre  => Corners'First = 0
             and then Count in Min_Corners .. Max_Corners
             and then Count - 1 <= Corners'Last
             and then Width >= 1 and then Height >= 1
             and then Valid_Tile (Tile_X) and then Valid_Tile (Tile_Y)
             and then KT.Bounded (Selected_From_Pixel),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Model (Model)
                            and then Model.Image_Width = Width
                            and then Model.Image_Height = Height
                            and then Valid_Fit (Fit));
   --  Fit_Model of a checkerboard's corners: their pixel positions and,
   --  as plate points, their grid indices (tiles of Tile_X x Tile_Y).

   procedure Fit_Corners
     (Corners             : Corner_Array;
      Count               : Natural;
      Width, Height       : Int32;
      Tile_X, Tile_Y      : Long_Float;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Model               : out Ks_Radial_Warp_Model;
      Fit                 : out Ks_N_Point_To_N_Point_Fit;
      Status              : out Ks_Status)
   is
      Points : Radial.Observation_Array_Access;
   begin
      Model := No_Model;
      Fit := Identity_Fit;
      Allocate_Observations (Count, Points);
      if Points = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Calibrate: not enough memory");
         return;
      end if;
      for K in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (Points /= null
            and then Points'First = 0 and then Points'Last = Count - 1);
         Points (K) :=
           (Pixel_X => Corners (K).Pixel_X,
            Pixel_Y => Corners (K).Pixel_Y,
            Plate_X => Long_Float (Corners (K).Grid_I),
            Plate_Y => Long_Float (Corners (K).Grid_J));
      end loop;
      Fit_Model (Points.all, Count, Width, Height, Tile_X, Tile_Y,
                 Selected_From_Pixel, Model, Fit, Status);
      Free (Points);
   end Fit_Corners;

   procedure Calibrate_Checkerboard
     (Calibration         : Ks_Calibration;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Status              : out Ks_Status)
   with
     Pre  => Valid_Calibration (Calibration)
             and then Calibration.Kind = Kind_Checkerboard
             and then Calibration.Calibrated = False_Value
             and then Calibration.Pairs = null
             and then Calibration.Corners = null
             and then KI.Valid_Image (Image)
             and then KT.Bounded (Selected_From_Pixel),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then Valid_Calibration (Calibration)
             and then Calibration.Kind = Kind_Checkerboard
             and then Calibration.DOF = Calibration.DOF'Old
             and then Calibration.Mode = Calibration.Mode'Old
             and then (if Succeeded (Status)
                       then Calibration.Calibrated = True_Value
                            and then Corners_Inside (Calibration)
                            and then Calibration.Image_Width = Image.Width
                            and then Calibration.Image_Height = Image.Height
                       else Calibration.Calibrated = False_Value);
   --  The checkerboard part of Calibrate.

   procedure Calibrate_Checkerboard
     (Calibration         : Ks_Calibration;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Status              : out Ks_Status)
   is
      Corners : Corner_Array_Access;
      Count   : Natural;
      Pairs   : Ks_Point_Pairs;
      Fit     : Ks_N_Point_To_N_Point_Fit;
      Model   : Ks_Radial_Warp_Model := No_Model;
      X, Y    : Long_Float;
      Width   : constant Int32 := Image.Width;
      Height  : constant Int32 := Image.Height;
   begin
      Checkerboard.Detect (Image, Corners, Count, Status);
      if not Succeeded (Status) then
         return;
      end if;

      --  The pairs: the corners in the selected space, and on the grid.
      Allocate_Pairs (Pairs);
      if Pairs = null then
         Free (Corners);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Calibrate: not enough memory");
         return;
      end if;
      Allocate_Pair_Array (Count, Pairs.Pairs);
      if Pairs.Pairs = null then
         Free (Pairs);
         Free (Corners);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Calibrate: not enough memory");
         return;
      end if;
      for K in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (Pairs /= null and then Pairs.Pairs /= null
            and then Pairs.Count = 0
            and then Pairs.Pairs'First = 0
            and then Pairs.Pairs'Last = Count - 1
            and then Corners /= null
            and then Corners'First = 0 and then Corners'Last = Count - 1);
         KT.Map_Point
           (Selected_From_Pixel, Corners (K).Pixel_X, Corners (K).Pixel_Y,
            X, Y, Status);
         if not Succeeded (Status) then
            Free (Pairs.Pairs);
            Free (Pairs);
            Free (Corners);
            Bad (Status, "Calibrate: a corner mapped to the selected space "
                         & "of CalibrationImage exceeds +/-1.0E150");
            return;
         end if;
         Pairs.Pairs (K) :=
           (A_X => X, A_Y => Y,
            B_X => Raw_Coordinate (Corners (K).Grid_I, Calibration.Tile_X),
            B_Y => Raw_Coordinate (Corners (K).Grid_J, Calibration.Tile_Y));
      end loop;
      Pairs.Count := Count;
      pragma Assert
        (for all K in 0 .. Count - 1
         => Corners (K).Pixel_X <= Long_Float (Width - 1)
            and then Corners (K).Pixel_Y <= Long_Float (Height - 1));

      if Calibration.Mode = Mode_Linear then
         DOF_Fits.Fit (Pairs.Pairs.all, Count, Calibration.DOF, Fit, Status);
      else
         Fit_Corners (Corners.all, Count, Width, Height, Calibration.Tile_X,
                      Calibration.Tile_Y, Selected_From_Pixel, Model, Fit,
                      Status);
      end if;
      if not Succeeded (Status) then
         Free (Pairs.Pairs);
         Free (Pairs);
         Free (Corners);
         return;
      end if;
      Calibration.Model := Model;
      Calibration.Pairs := Pairs;
      Calibration.Corners := Corners;
      Calibration.Image_Width := Width;
      Calibration.Image_Height := Height;
      Calibration.Fit := Fit;
      Calibration.Calibrated := True_Value;
      pragma Assert (Count_Of (Calibration.Pairs) = Count);
      pragma Assert
        (for all K in 0 .. Count - 1
         => Calibration.Corners (K).Pixel_X
              <= Long_Float (Calibration.Image_Width - 1)
            and then Calibration.Corners (K).Pixel_Y
                       <= Long_Float (Calibration.Image_Height - 1));
   end Calibrate_Checkerboard;

   procedure Calibrate_N_Point_Warp
     (Calibration         : Ks_Calibration;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Status              : out Ks_Status)
   with
     Pre  => Valid_Calibration (Calibration)
             and then Calibration.Kind = Kind_N_Point_To_N_Point
             and then Calibration.Mode = Mode_Perspective_And_Radial_Warp
             and then Calibration.Calibrated = False_Value
             and then Count_Of (Calibration.Pairs)
                        in Min_Warp_Points .. Max_Warp_Points
             and then KI.Valid_Image (Image)
             and then KT.Bounded (Selected_From_Pixel),
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then Valid_Calibration (Calibration)
             and then Calibration.Kind = Kind_N_Point_To_N_Point
             and then Calibration.DOF = Calibration.DOF'Old
             and then Calibration.Mode = Calibration.Mode'Old
             and then Count_Of (Calibration.Pairs)
                        = Count_Of (Calibration.Pairs)'Old
             and then (if Succeeded (Status)
                       then Calibration.Calibrated = True_Value
                            and then Calibration.Image_Width = Image.Width
                            and then Calibration.Image_Height = Image.Height
                       else Calibration.Calibrated = False_Value);
   --  The N-point part of Calibrate in PerspectiveAndRadialWarp mode: the
   --  pairs' uncalibrated points mapped to pixel space (each on the image)
   --  and their raw calibrated points, fitted with tiles of size 1.

   procedure Calibrate_N_Point_Warp
     (Calibration         : Ks_Calibration;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Status              : out Ks_Status)
   is
      Count               : constant Natural := Calibration.Pairs.Count;
      Width               : constant Int32 := Image.Width;
      Height              : constant Int32 := Image.Height;
      Right               : constant Radial.Pixel_Value :=
        Long_Float (Width) - 0.5;
      Bottom              : constant Radial.Pixel_Value :=
        Long_Float (Height) - 0.5;
      --  The image's pixel area is [-0.5, Right] x [-0.5, Bottom].
      Pixel_From_Selected : KT.Ks_Transform_2D_Linear;
      Points              : Radial.Observation_Array_Access;
      Model               : Ks_Radial_Warp_Model;
      Fit                 : Ks_N_Point_To_N_Point_Fit;
      X, Y                : Long_Float;
   begin
      KT.Invert (Selected_From_Pixel, Pixel_From_Selected, Status);
      if not Succeeded (Status) then
         Bad (Status, "Calibrate: the transform from pixel space to the "
                      & "selected space of CalibrationImage is singular");
         return;
      end if;
      Allocate_Observations (Count, Points);
      if Points = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Calibrate: not enough memory");
         return;
      end if;
      for K in 0 .. Count - 1 loop
         pragma Loop_Invariant
           (Points /= null
            and then Points'First = 0 and then Points'Last = Count - 1);
         KT.Map_Point
           (Pixel_From_Selected, Calibration.Pairs.Pairs (K).A_X,
            Calibration.Pairs.Pairs (K).A_Y, X, Y, Status);
         if not Succeeded (Status)
           or else not (X >= -0.5 and then X <= Right
                        and then Y >= -0.5 and then Y <= Bottom)
         then
            Free (Points);
            Bad (Status, "Calibrate: an uncalibrated point lies outside "
                         & "CalibrationImage (PerspectiveAndRadialWarp)");
            return;
         end if;
         Points (K) :=
           (Pixel_X => X,
            Pixel_Y => Y,
            Plate_X => Calibration.Pairs.Pairs (K).B_X,
            Plate_Y => Calibration.Pairs.Pairs (K).B_Y);
      end loop;
      Fit_Model (Points.all, Count, Width, Height, 1.0, 1.0,
                 Selected_From_Pixel, Model, Fit, Status);
      Free (Points);
      if not Succeeded (Status) then
         return;
      end if;
      Calibration.Model := Model;
      Calibration.Fit := Fit;
      Calibration.Image_Width := Width;
      Calibration.Image_Height := Height;
      Calibration.Calibrated := True_Value;
   end Calibrate_N_Point_Warp;

   procedure Calibration_Calibrate
     (Calibration         : Ks_Calibration;
      Calibration_Image   : access constant KI.Ks_Image_8_Grey_Data;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Status              : out Ks_Status)
   is
      Fit : Ks_N_Point_To_N_Point_Fit;
   begin
      Check_Calibration (Calibration, "Calibrate", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Uncalibrate (Calibration);
      if Calibration.Kind = Kind_N_Point_To_N_Point then
         if Calibration.Mode = Mode_Linear then
            Fit_Pairs (Calibration.Pairs, Calibration.DOF, "", Fit, Status);
            if Succeeded (Status) then
               Calibration.Fit := Fit;
               Calibration.Calibrated := True_Value;
            end if;
            return;
         elsif Count_Of (Calibration.Pairs) < Min_Warp_Points then
            Bad (Status, "Calibrate: PerspectiveAndRadialWarp needs at "
                         & "least 8 point pairs");
            return;
         elsif Count_Of (Calibration.Pairs) > Max_Warp_Points then
            Bad (Status, "Calibrate: PerspectiveAndRadialWarp takes at "
                         & "most 65536 point pairs");
            return;
         end if;
      end if;
      if Calibration_Image = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      "CalibrationImage has no pixels");
         return;
      elsif not KI.Valid_Image (Calibration_Image) then
         Bad (Status, "CalibrationImage is not a valid image");
         return;
      elsif not KT.Bounded (Selected_From_Pixel) then
         Bad (Status, "Calibrate: the transform from pixel space to the "
                      & "selected space must be within +/-1.0E150");
         return;
      end if;
      if Calibration.Kind = Kind_N_Point_To_N_Point then
         Calibrate_N_Point_Warp
           (Calibration, Calibration_Image, Selected_From_Pixel, Status);
      else
         Calibrate_Checkerboard
           (Calibration, Calibration_Image, Selected_From_Pixel, Status);
      end if;
   end Calibration_Calibrate;

   procedure Calibration_Calibrated
     (Calibration : access constant Ks_Calibration_Data;
      Result      : out Int32;
      Status      : out Ks_Status) is
   begin
      Result := False_Value;
      if Calibration = null then
         Set_Success (Status);
         return;
      end if;
      Check_Calibration (Calibration, "Calibrated", Status);
      if Succeeded (Status) then
         Result := Calibration.Calibrated;
      end if;
   end Calibration_Calibrated;

   procedure Calibration_Uncalibrate
     (Calibration : Ks_Calibration;
      Status      : out Ks_Status) is
   begin
      if Calibration = null then
         Set_Success (Status);
         return;
      end if;
      Check_Calibration (Calibration, "Uncalibrate", Status);
      if Succeeded (Status) then
         Uncalibrate (Calibration);
      end if;
   end Calibration_Uncalibrate;

   procedure Calibration_Computed_Fit
     (Calibration : access constant Ks_Calibration_Data;
      Fit         : out Ks_N_Point_To_N_Point_Fit;
      Status      : out Ks_Status) is
   begin
      Fit := Identity_Fit;
      Check_Calibration (Calibration, "GetComputedFit", Status);
      if not Succeeded (Status) then
         return;
      elsif Calibration.Calibrated /= True_Value then
         Set_Failure (Status, Failure_Operator_Not_Trained,
                      "The calibration is not calibrated");
         return;
      end if;
      Fit := Calibration.Fit;
   end Calibration_Computed_Fit;

   procedure Calibration_Get_Corner
     (Calibration      : access constant Ks_Calibration_Data;
      Index            : Int32;
      Pixel_X, Pixel_Y : out Long_Float;
      Grid_I, Grid_J   : out Int32;
      Status           : out Ks_Status) is
   begin
      Pixel_X := 0.0;
      Pixel_Y := 0.0;
      Grid_I := 0;
      Grid_J := 0;
      Check_Calibration (Calibration, "GetCorner", Status);
      if not Succeeded (Status) then
         return;
      elsif Calibration.Kind /= Kind_Checkerboard then
         Bad (Status, "GetCorner: only a checkerboard calibration has "
                      & "corners");
         return;
      elsif Index < 0 or else Index >= Int32 (Count_Of (Calibration)) then
         Bad_Index (Status, Index, Count_Of (Calibration));
         return;
      end if;
      declare
         C : constant Ks_Corner := Calibration.Corners (Natural (Index));
      begin
         if C.Pixel_X > Long_Float (Calibration.Image_Width - 1)
           or else C.Pixel_Y > Long_Float (Calibration.Image_Height - 1)
         then
            Bad (Status, "GetCorner: the corner lies outside the image");
            return;
         end if;
         Pixel_X := C.Pixel_X;
         Pixel_Y := C.Pixel_Y;
         Grid_I := C.Grid_I;
         Grid_J := C.Grid_J;
      end;
   end Calibration_Get_Corner;

   procedure Calibration_Corner_Image_Size
     (Calibration   : access constant Ks_Calibration_Data;
      Width, Height : out Int32;
      Status        : out Ks_Status) is
   begin
      Width := 0;
      Height := 0;
      Check_Calibration (Calibration, "CornerImageSize", Status);
      if Succeeded (Status) and then Calibration.Corners /= null then
         Width := Calibration.Image_Width;
         Height := Calibration.Image_Height;
      end if;
   end Calibration_Corner_Image_Size;

   ---------------------------------------------------------------------
   --  The origin adjustment
   ---------------------------------------------------------------------

   procedure Adjusted_Transform
     (Raw        : KT.Ks_Transform_2D_Linear;
      Adjustment : Ks_Calibration_Adjustment;
      Linear     : Boolean;
      Result     : out KT.Ks_Transform_2D_Linear;
      Status     : out Ks_Status)
   with
     Pre  => KT.Bounded (Raw) and then Det_Of (Raw) /= 0.0
             and then Valid_Adjustment (Adjustment),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Is_Identity_Adjustment (Adjustment)
                       then Succeeded (Status) and then Result = Raw)
             and then (if Succeeded (Status)
                       then KT.Bounded (Result)
                            and then Det_Of (Result) /= 0.0
                            and then (if not Linear
                                      then In_Raw_Calibrated_Space
                                             (Adjustment))
                       else Result = (others => <>));
   --  UncalibratedFromCalibrated = F * R for the fit's transform Raw (F)
   --  and Adjustment, as the spec describes. Linear is False in
   --  PerspectiveAndRadialWarp mode, which does not support the
   --  Uncalibrated spaces.

   procedure Adjusted_Transform
     (Raw        : KT.Ks_Transform_2D_Linear;
      Adjustment : Ks_Calibration_Adjustment;
      Linear     : Boolean;
      Result     : out KT.Ks_Transform_2D_Linear;
      Status     : out Ks_Status)
   is
      Identity : constant KT.Ks_Transform_2D_Linear := (others => <>);
      Inverse  : KT.Ks_Transform_2D_Linear := Identity;
      Back     : KT.Ks_Transform_2D_Linear;
      Origin_X : Long_Float := Adjustment.Calibrated_Origin_X;
      Origin_Y : Long_Float := Adjustment.Calibrated_Origin_Y;
      Phi      : Long_Float := Adjustment.Calibrated_X_Axis_Rotation;
      Cos_Phi  : Long_Float;
      Sin_Phi  : Long_Float;
      Swap     : constant Boolean :=
        Adjustment.Swap_Calibrated_Handedness = True_Value;
      Moved    : KT.Ks_Transform_2D_Linear;
   begin
      Result := Identity;
      if Is_Identity_Adjustment (Adjustment) then
         Result := Raw;
         Set_Success (Status);
         return;
      end if;

      --  The origin and the axis given in the uncalibrated space are
      --  mapped back through F**(-1).
      if not In_Raw_Calibrated_Space (Adjustment) then
         if not Linear then
            Bad (Status, "CalibratedOriginSpace and CalibratedXAxisRotation"
                         & "Space must be RawCalibrated in ComputationMode "
                         & "PerspectiveAndRadialWarp");
            return;
         end if;
         KT.Invert (Raw, Inverse, Status);
         if not Succeeded (Status) then
            Bad (Status, "The calibration's transform is not invertible "
                         & "within +/-1.0E150 (origin adjustment)");
            return;
         end if;
      end if;
      if Adjustment.Calibrated_Origin_Space = Adjustment_Space_Uncalibrated
      then
         KT.Map_Point
           (Inverse, Adjustment.Calibrated_Origin_X,
            Adjustment.Calibrated_Origin_Y, Origin_X, Origin_Y, Status);
         if not Succeeded (Status) then
            Bad (Status, "CalibratedOriginX/Y mapped to the raw calibrated "
                         & "space exceed +/-1.0E150");
            return;
         end if;
      end if;
      if Adjustment.Calibrated_X_Axis_Rotation_Space
           = Adjustment_Space_Uncalibrated
      then
         KT.Map_Angle
           (Inverse, Adjustment.Calibrated_X_Axis_Rotation, Phi, Status);
         if not Succeeded (Status) then
            Bad (Status, "CalibratedXAxisRotation cannot be mapped to the raw "
                         & "calibrated space");
            return;
         end if;
      end if;

      --  R = Translate (O) * Rotate (Phi) * (Swap ? diag (1, -1) : I).
      Cos_Phi := EF.Cos (Phi);
      Sin_Phi := EF.Sin (Phi);
      Moved := (A             => Cos_Phi,
                B             => (if Swap then Sin_Phi else -Sin_Phi),
                C             => Sin_Phi,
                D             => (if Swap then -Cos_Phi else Cos_Phi),
                Translation_X => Origin_X,
                Translation_Y => Origin_Y);
      KT.Compose (Raw, Moved, Result, Status);
      if not Succeeded (Status) then
         Result := Identity;
         Bad (Status, "UncalibratedFromCalibrated (with the origin "
                      & "adjustment) exceeds +/-1.0E150");
         return;
      end if;
      if Det_Of (Result) = 0.0 then
         Result := Identity;
         Bad (Status, "UncalibratedFromCalibrated (with the origin "
                      & "adjustment) is singular");
         return;
      end if;
      --  The tools add the space with it, which must be invertible within
      --  the bounds (as Add_Output_Space checks).
      KT.Invert (Result, Back, Status);
      if not Succeeded (Status) or else not KT.Bounded (Back) then
         Result := Identity;
         Bad (Status, "UncalibratedFromCalibrated (with the origin "
                      & "adjustment) is not invertible within +/-1.0E150");
         return;
      end if;
   end Adjusted_Transform;

   procedure Calibration_Adjustment_Default
     (Adjustment : out Ks_Calibration_Adjustment;
      Status     : out Ks_Status) is
   begin
      Adjustment := Default_Adjustment;
      Set_Success (Status);
   end Calibration_Adjustment_Default;

   procedure Calibration_Get_Adjustment
     (Calibration : access constant Ks_Calibration_Data;
      Adjustment  : out Ks_Calibration_Adjustment;
      Status      : out Ks_Status) is
   begin
      Adjustment := Default_Adjustment;
      Check_Calibration (Calibration, "GetAdjustment", Status);
      if Succeeded (Status) then
         Adjustment := Calibration.Adjustment;
      end if;
   end Calibration_Get_Adjustment;

   procedure Calibration_Set_Adjustment
     (Calibration : Ks_Calibration;
      Adjustment  : Ks_Calibration_Adjustment;
      Status      : out Ks_Status)
   is
      Rotation : Long_Float := Adjustment.Calibrated_X_Axis_Rotation;
   begin
      Check_Calibration (Calibration, "SetAdjustment", Status);
      if not Succeeded (Status) then
         return;
      elsif Adjustment.Calibrated_Origin_Space not in Adjustment_Space_Code
      then
         Bad (Status, "CalibratedOriginSpace must be 0 (RawCalibrated) or 1 "
                      & "(Uncalibrated)");
         return;
      elsif Adjustment.Calibrated_X_Axis_Rotation_Space
              not in Adjustment_Space_Code
      then
         Bad (Status, "CalibratedXAxisRotationSpace must be 0 "
                      & "(RawCalibrated) or 1 (Uncalibrated)");
         return;
      elsif Adjustment.Swap_Calibrated_Handedness
              not in False_Value | True_Value
      then
         Bad (Status, "SwapCalibratedHandedness must be 0 or 1");
         return;
      elsif not Bounded (Adjustment.Calibrated_Origin_X) then
         Bad (Status, "CalibratedOriginX must be finite and within "
                      & "+/-1.0E150");
         return;
      elsif not Bounded (Adjustment.Calibrated_Origin_Y) then
         Bad (Status, "CalibratedOriginY must be finite and within "
                      & "+/-1.0E150");
         return;
      elsif not N.Is_Finite (Rotation) then
         Bad (Status, "CalibratedXAxisRotation must be finite");
         return;
      end if;
      if not (Rotation > -Pi and then Rotation <= Pi) then
         Rotation := N.Reduce_Two_Pi (Rotation);
      end if;
      Calibration.Adjustment :=
        (Adjustment with delta Calibrated_X_Axis_Rotation => Rotation);
   end Calibration_Set_Adjustment;

   procedure Calibration_Computed_Uncalibrated_From_Calibrated
     (Calibration : access constant Ks_Calibration_Data;
      Transform   : out KT.Ks_Transform_2D_Linear;
      Status      : out Ks_Status) is
   begin
      Transform := (others => <>);
      Check_Calibration
        (Calibration, "GetComputedUncalibratedFromCalibrated", Status);
      if not Succeeded (Status) then
         return;
      elsif Calibration.Calibrated /= True_Value then
         Set_Failure (Status, Failure_Operator_Not_Trained,
                      "The calibration is not calibrated");
         return;
      end if;
      Adjusted_Transform
        (Calibration.Fit.Transform, Calibration.Adjustment,
         Calibration.Mode = Mode_Linear, Transform, Status);
   end Calibration_Computed_Uncalibrated_From_Calibrated;

   procedure Calibration_Run_Params_Default
     (Kind   : Int32;
      Params : out Ks_Calibration_Run_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      if Kind not in Kind_Code then
         Bad (Status, "Kind must be KS_CALIBRATION_N_POINT_TO_N_POINT (0) "
                      & "or KS_CALIBRATION_CHECKERBOARD (1)");
         return;
      end if;
      if Kind = Kind_Checkerboard then
         Params.Calibrated_Space_Name := Default_Checkerboard_Calibration_Name;
      end if;
      Set_Success (Status);
   end Calibration_Run_Params_Default;

   procedure Calibration_Tool_Execute
     (Input_Image     : access constant KI.Ks_Image_8_Grey_Data;
      Calibration     : access constant Ks_Calibration_Data;
      Params          : Ks_Calibration_Run_Params;
      Tree            : in out KC.Ks_Coordinate_Space_Tree;
      Selected        : in out KC.Ks_Space_Name;
      Pixel_From_Root : KT.Ks_Transform_2D_Linear;
      Status          : out Ks_Status)
   is
      Transform : KT.Ks_Transform_2D_Linear;
   begin
      Check_Input_Image (Input_Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Calibration = null then
         Bad (Status, "Calibration is null");
         return;
      end if;
      Check_Calibration (Calibration, "Calibration", Status);
      if not Succeeded (Status) then
         return;
      elsif Calibration.Calibrated /= True_Value then
         Set_Failure (Status, Failure_Operator_Not_Trained,
                      "Calibration is not calibrated");
         return;
      elsif Calibration.Mode /= Mode_Linear then
         Bad (Status, "Calibration: ComputationMode PerspectiveAndRadialWarp "
                      & "warps the image (use "
                      & "ks_calibration_n_point_tool_execute or "
                      & "ks_calibration_checkerboard_tool_execute)");
         return;
      end if;
      Adjusted_Transform
        (Calibration.Fit.Transform, Calibration.Adjustment, True, Transform,
         Status);
      if not Succeeded (Status) then
         return;
      end if;
      Add_Output_Space
        (Tree, Selected, Pixel_From_Root, Transform,
         Params.Calibrated_Space_Name, Params.Space_To_Output,
         Duplicate_Compatibility, "RunParams.CalibratedSpaceName",
         "The calibration's transform", Status);
   end Calibration_Tool_Execute;

   ---------------------------------------------------------------------
   --  The computation mode and the nonlinear model
   ---------------------------------------------------------------------

   procedure Calibration_Computation_Mode
     (Calibration : access constant Ks_Calibration_Data;
      Mode        : out Int32;
      Status      : out Ks_Status) is
   begin
      Mode := Mode_Linear;
      Check_Calibration (Calibration, "ComputationMode", Status);
      if Succeeded (Status) then
         Mode := Calibration.Mode;
      end if;
   end Calibration_Computation_Mode;

   procedure Calibration_Set_Computation_Mode
     (Calibration : Ks_Calibration;
      Mode        : Int32;
      Status      : out Ks_Status) is
   begin
      Check_Calibration (Calibration, "ComputationMode", Status);
      if not Succeeded (Status) then
         return;
      end if;
      case Mode is
         when Mode_Linear =>
            null;
         when Mode_Perspective_And_Radial_Warp =>
            null;
         when Mode_Linescan_Warp =>
            Bad (Status, "ComputationMode LinescanWarp is not supported");
            return;
         when Mode_Linescan_2D_Warp =>
            Bad (Status, "ComputationMode Linescan2DWarp is not supported");
            return;
         when Mode_Sine_Tan_Law_Projection_Warp =>
            Bad (Status, "ComputationMode SineTanLawProjectionWarp is not "
                         & "supported");
            return;
         when Mode_Three_Param_Radial_Warp =>
            Bad (Status, "ComputationMode ThreeParamRadialWarp is not "
                         & "supported");
            return;
         when Mode_No_Distortion_Warp =>
            Bad (Status, "ComputationMode NoDistortionWarp is not "
                         & "supported");
            return;
         when others =>
            Bad (Status, "ComputationMode must be a "
                         & "CogCalibFixComputationModeConstants value "
                         & "(1 .. 7)");
            return;
      end case;
      Uncalibrate (Calibration);
      Calibration.Mode := Mode;
   end Calibration_Set_Computation_Mode;

   procedure Check_Warp_Model
     (Calibration : access constant Ks_Calibration_Data;
      Operation   : String;
      Status      : out Ks_Status)
   with
     Pre  => Operation'First = 1 and then Operation'Length <= 40,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Operator_Not_Trained
             and then (if Succeeded (Status)
                       then Valid_Calibration (Calibration)
                            and then Calibration.Calibrated = True_Value
                            and then Calibration.Mode
                                       = Mode_Perspective_And_Radial_Warp
                            and then Valid_Model (Calibration.Model));
   --  The checks of the operations on the nonlinear model.

   procedure Check_Warp_Model
     (Calibration : access constant Ks_Calibration_Data;
      Operation   : String;
      Status      : out Ks_Status) is
   begin
      Check_Calibration (Calibration, Operation, Status);
      if not Succeeded (Status) then
         return;
      elsif Calibration.Mode /= Mode_Perspective_And_Radial_Warp then
         Bad (Status, Operation & ": ComputationMode is Linear (no "
                      & "nonlinear model)");
      elsif Calibration.Calibrated /= True_Value then
         Set_Failure (Status, Failure_Operator_Not_Trained,
                      "The calibration is not calibrated");
      end if;
   end Check_Warp_Model;

   procedure Calibration_Computed_Warp_Model
     (Calibration : access constant Ks_Calibration_Data;
      Model       : out Ks_Radial_Warp_Model;
      Status      : out Ks_Status) is
   begin
      Model := No_Model;
      Check_Warp_Model (Calibration, "GetComputedWarpModel", Status);
      if Succeeded (Status) then
         Model := Calibration.Model;
      end if;
   end Calibration_Computed_Warp_Model;

   procedure Calibration_Map_Output_Pixel
     (Calibration      : access constant Ks_Calibration_Data;
      Output_X         : Long_Float;
      Output_Y         : Long_Float;
      Input_X, Input_Y : out Long_Float;
      Inside           : out Int32;
      Status           : out Ks_Status)
   is
      Found : Boolean;
   begin
      Input_X := 0.0;
      Input_Y := 0.0;
      Inside := False_Value;
      Check_Warp_Model (Calibration, "MapOutputPixel", Status);
      if not Succeeded (Status) then
         return;
      elsif not (abs Output_X <= Max_Output_Coordinate
                 and then abs Output_Y <= Max_Output_Coordinate)
      then
         Bad (Status, "MapOutputPixel: the output pixel must be finite and "
                      & "within +/-2**32");
         return;
      end if;
      Warp.Input_From_Output
        (Calibration.Model, Output_X, Output_Y, Input_X, Input_Y, Found);
      if Found then
         Inside := True_Value;
      end if;
   end Calibration_Map_Output_Pixel;

   procedure Calibration_Map_Input_Pixel
     (Calibration        : access constant Ks_Calibration_Data;
      Input_X            : Long_Float;
      Input_Y            : Long_Float;
      Output_X, Output_Y : out Long_Float;
      Inside             : out Int32;
      Status             : out Ks_Status)
   is
      Found : Boolean;
   begin
      Output_X := 0.0;
      Output_Y := 0.0;
      Inside := False_Value;
      Check_Warp_Model (Calibration, "MapInputPixel", Status);
      if not Succeeded (Status) then
         return;
      elsif not (abs Input_X <= Max_Output_Coordinate
                 and then abs Input_Y <= Max_Output_Coordinate)
      then
         Bad (Status, "MapInputPixel: the input pixel must be finite and "
                      & "within +/-2**32");
         return;
      end if;
      Warp.Output_From_Input
        (Calibration.Model, Input_X, Input_Y, Output_X, Output_Y, Found);
      if Found then
         Inside := True_Value;
      end if;
   end Calibration_Map_Input_Pixel;

   ---------------------------------------------------------------------
   --  The checkerboard calibration tool in every mode
   ---------------------------------------------------------------------

   procedure Calibration_Checkerboard_Run_Params_Default
     (Params : out Ks_Calibration_Checkerboard_Run_Params;
      Status : out Ks_Status) is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Calibration_Checkerboard_Run_Params_Default;

   procedure Warp_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Model  : Ks_Radial_Warp_Model;
      Fill   : KI.Grey_8;
      Output : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => KI.Valid_Image (Image) and then Valid_Model (Model)
             and then Image.Width = Model.Image_Width
             and then Image.Height = Model.Image_Height,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then KI.Valid_Image (Output)
                            and then Output.Width = Image.Width
                            and then Output.Height = Image.Height
                       else Output = null);
   --  The warped image (see the spec).

   procedure Warp_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Model  : Ks_Radial_Warp_Model;
      Fill   : KI.Grey_8;
      Output : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      KI.Create (Image.Width, Image.Height, Fill, Output, Status);
      if not Succeeded (Status) then
         Output := null;
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "Calibration tool: not enough memory for the output "
                      & "image");
         return;
      end if;
      Warp.Resample (Image, Model, Fill, Output);
   end Warp_Image;

   procedure Calibration_Checkerboard_Tool_Execute
     (Input_Image     : access constant KI.Ks_Image_8_Grey_Data;
      Calibration     : access constant Ks_Calibration_Data;
      Params          : Ks_Calibration_Checkerboard_Run_Params;
      Tree            : in out KC.Ks_Coordinate_Space_Tree;
      Selected        : in out KC.Ks_Space_Name;
      Pixel_From_Root : KT.Ks_Transform_2D_Linear;
      Output          : out KI.Ks_Image_8_Grey;
      Status          : out Ks_Status)
   is
      Fill      : KI.Grey_8 := 0;
      Transform : KT.Ks_Transform_2D_Linear;
      Ignored   : Ks_Status;
   begin
      Output := null;
      Check_Input_Image (Input_Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Calibration = null then
         Bad (Status, "Calibration is null");
         return;
      end if;
      Check_Calibration (Calibration, "Calibration", Status);
      if not Succeeded (Status) then
         return;
      elsif Calibration.Calibrated /= True_Value then
         Set_Failure (Status, Failure_Operator_Not_Trained,
                      "Calibration is not calibrated");
         return;
      elsif Params.Unfilled_Pel_Value not in 0 .. 255 then
         Bad (Status, "RunParams.UnfilledPelValue must be in 0 .. 255");
         return;
      elsif Params.Unfilled_Pel_Value_Enabled
              not in False_Value | True_Value
      then
         Bad (Status, "RunParams.UnfilledPelValueEnabled must be 0 or 1");
         return;
      end if;
      if Params.Unfilled_Pel_Value_Enabled = True_Value then
         Fill := KI.Grey_8 (Params.Unfilled_Pel_Value);
      end if;

      if Calibration.Mode /= Mode_Linear then
         if Input_Image.Width /= Calibration.Model.Image_Width
           or else Input_Image.Height /= Calibration.Model.Image_Height
         then
            Bad (Status, "InputImage must have the size of the calibration "
                         & "image (ComputationMode "
                         & "PerspectiveAndRadialWarp)");
            return;
         end if;
      end if;
      --  The calibrated space's transform, before anything is warped.
      Adjusted_Transform
        (Calibration.Fit.Transform, Calibration.Adjustment,
         Calibration.Mode = Mode_Linear, Transform, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Calibration.Mode /= Mode_Linear then
         Warp_Image (Input_Image, Calibration.Model, Fill, Output, Status);
         if not Succeeded (Status) then
            return;
         end if;
      end if;
      Add_Output_Space
        (Tree, Selected, Pixel_From_Root, Transform,
         Params.Calibrated_Space_Name, Params.Space_To_Output,
         Duplicate_Compatibility, "RunParams.CalibratedSpaceName",
         "The calibration's transform", Status);
      if not Succeeded (Status) then
         KI.Destroy (Output, Ignored);
      end if;
   end Calibration_Checkerboard_Tool_Execute;

   ---------------------------------------------------------------------
   --  The N-point calibration tool in every mode
   ---------------------------------------------------------------------

   procedure Calibration_N_Point_Tool_Execute
     (Input_Image     : access constant KI.Ks_Image_8_Grey_Data;
      Calibration     : access constant Ks_Calibration_Data;
      Params          : Ks_Calibration_Run_Params;
      Tree            : in out KC.Ks_Coordinate_Space_Tree;
      Selected        : in out KC.Ks_Space_Name;
      Pixel_From_Root : KT.Ks_Transform_2D_Linear;
      Output          : out KI.Ks_Image_8_Grey;
      Status          : out Ks_Status) is
   begin
      Calibration_Checkerboard_Tool_Execute
        (Input_Image, Calibration,
         (Calibrated_Space_Name      => Params.Calibrated_Space_Name,
          Space_To_Output            => Params.Space_To_Output,
          Unfilled_Pel_Value         => 0,
          Unfilled_Pel_Value_Enabled => False_Value),
         Tree, Selected, Pixel_From_Root, Output, Status);
   end Calibration_N_Point_Tool_Execute;

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   procedure Check_Pairs_Header
     (Code, Count : Int32;
      Status      : out Ks_Status) is
   begin
      if Code /= Pairs_Stream_Code then
         Set_Failure (Status, Failure_Image_File,
                      "Point pairs'Read: not a list of point pairs");
      elsif Count not in 0 .. Max_Pairs then
         Set_Failure (Status, Failure_Image_File,
                      "Point pairs'Read: bad number of pairs");
      else
         Set_Success (Status);
      end if;
   end Check_Pairs_Header;

   procedure Check_Calibration_Header
     (Code, Kind, Expected_Kind, Count, Calibrated : Int32;
      Status                                     : out Ks_Status) is
   begin
      if Code not in Calibration_Stream_Code | Calibration_Stream_Code_1
                   | Calibration_Stream_Code_2
      then
         Set_Failure (Status, Failure_Image_File,
                      "Calibration'Read: not a calibration");
      elsif Kind /= Expected_Kind then
         Set_Failure (Status, Failure_Image_File,
                      "Calibration'Read: a calibration of another kind");
      elsif Count not in 0 .. Max_Pairs then
         Set_Failure (Status, Failure_Image_File,
                      "Calibration'Read: bad number of points");
      elsif Calibrated not in False_Value | True_Value then
         Set_Failure (Status, Failure_Image_File,
                      "Calibration'Read: bad calibrated flag");
      else
         Set_Success (Status);
      end if;
   end Check_Calibration_Header;

   procedure To_Image_File (Status : in out Ks_Status; Message : String)
   with
     Pre  => Valid (Status) and then Message'Length <= 80,
     Post => Valid (Status)
             and then (if Status.Failure'Old = Failure_None
                       then Succeeded (Status)
                       elsif Status.Failure'Old = Failure_Out_Of_Memory
                       then Status.Failure = Failure_Out_Of_Memory
                       else Status.Failure = Failure_Image_File);
   --  A failure other than Out_Of_Memory becomes Image_File with Message.

   procedure To_Image_File (Status : in out Ks_Status; Message : String) is
   begin
      if Status.Failure /= Failure_None
        and then Status.Failure /= Failure_Out_Of_Memory
      then
         Set_Failure (Status, Failure_Image_File, Message);
      end if;
   end To_Image_File;

   procedure Read_Pair
     (Pairs              : in out Ks_Point_Pairs;
      A_X, A_Y, B_X, B_Y : Long_Float;
      Status             : out Ks_Status) is
   begin
      Pairs_Add_Point_Pair (Pairs, A_X, A_Y, B_X, B_Y, Status);
      To_Image_File (Status, "Point pairs'Read: malformed pair");
   end Read_Pair;

   procedure Restore_Settings
     (Calibration          : Ks_Calibration;
      DOF                  : Int32;
      Tile_Size_X          : Long_Float;
      Tile_Size_Y          : Long_Float;
      Status               : out Ks_Status) is
   begin
      Calibration_Set_DOFs_To_Compute (Calibration, DOF, Status);
      if Succeeded (Status) and then Calibration.Kind = Kind_Checkerboard
      then
         Calibration_Set_Physical_Tile_Size
           (Calibration, Tile_Size_X, Tile_Size_Y, Status);
      end if;
      To_Image_File (Status, "Calibration'Read: malformed settings");
   end Restore_Settings;

   procedure Restore_Pair
     (Calibration        : Ks_Calibration;
      A_X, A_Y, B_X, B_Y : Long_Float;
      Status             : out Ks_Status) is
   begin
      Calibration_Add_Point_Pair (Calibration, A_X, A_Y, B_X, B_Y, Status);
      To_Image_File (Status, "Calibration'Read: malformed point pair");
   end Restore_Pair;

   procedure Restore_Corner
     (Calibration          : Ks_Calibration;
      Image_Width          : Int32;
      Image_Height         : Int32;
      Capacity             : Int32;
      Pixel_X, Pixel_Y     : Long_Float;
      Grid_I, Grid_J       : Int32;
      Uncalibrated_X       : Long_Float;
      Uncalibrated_Y       : Long_Float;
      Status               : out Ks_Status)
   is
      procedure Malformed (Status : out Ks_Status)
      with Post => Valid (Status)
                   and then Status.Failure = Failure_Image_File;

      procedure Malformed (Status : out Ks_Status) is
      begin
         Set_Failure (Status, Failure_Image_File,
                      "Ks_Calib_Checkerboard'Read: malformed corner");
      end Malformed;
   begin
      if Calibration = null
        or else not Valid_Calibration (Calibration)
        or else Calibration.Kind /= Kind_Checkerboard
        or else Calibration.Calibrated /= False_Value
        or else Image_Width not in 1 .. Max_Image_Side
        or else Image_Height not in 1 .. Max_Image_Side
        or else not (Pixel_X >= 0.0
                     and then Pixel_X <= Long_Float (Image_Width - 1))
        or else not (Pixel_Y >= 0.0
                     and then Pixel_Y <= Long_Float (Image_Height - 1))
        or else Grid_I not in Grid_Index or else Grid_J not in Grid_Index
        or else not Bounded (Uncalibrated_X)
        or else not Bounded (Uncalibrated_Y)
      then
         Malformed (Status);
         return;
      end if;
      if Calibration.Corners = null then
         if Capacity not in 1 .. Max_Corners
           or else Calibration.Pairs /= null
         then
            Malformed (Status);
            return;
         end if;
         Allocate_Corners (Natural (Capacity), Calibration.Corners);
         if Calibration.Corners = null then
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Ks_Calib_Checkerboard'Read: not enough memory");
            return;
         end if;
         Allocate_Pairs (Calibration.Pairs);
         if Calibration.Pairs = null then
            Free (Calibration.Corners);
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Ks_Calib_Checkerboard'Read: not enough memory");
            return;
         end if;
         Allocate_Pair_Array (Natural (Capacity), Calibration.Pairs.Pairs);
         if Calibration.Pairs.Pairs = null then
            Release (Calibration.Pairs);
            Free (Calibration.Corners);
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "Ks_Calib_Checkerboard'Read: not enough memory");
            return;
         end if;
         Calibration.Image_Width := Image_Width;
         Calibration.Image_Height := Image_Height;
      end if;
      if Calibration.Image_Width /= Image_Width
        or else Calibration.Image_Height /= Image_Height
        or else Calibration.Pairs = null
        or else Calibration.Pairs.Pairs = null
        or else Calibration.Pairs.Count > Calibration.Corners'Last
        or else Calibration.Pairs.Count > Calibration.Pairs.Pairs'Last
      then
         Malformed (Status);
         return;
      end if;
      declare
         K : constant Natural := Calibration.Pairs.Count;
      begin
         Calibration.Corners (K) :=
           (Pixel_X => Pixel_X, Pixel_Y => Pixel_Y,
            Grid_I => Grid_I, Grid_J => Grid_J);
         Calibration.Pairs.Pairs (K) :=
           (A_X => Uncalibrated_X, A_Y => Uncalibrated_Y,
            B_X => Raw_Coordinate (Grid_I, Calibration.Tile_X),
            B_Y => Raw_Coordinate (Grid_J, Calibration.Tile_Y));
         Calibration.Pairs.Count := K + 1;
      end;
      Set_Success (Status);
   end Restore_Corner;

   procedure Restore_Fit
     (Calibration : Ks_Calibration;
      Fit         : Ks_N_Point_To_N_Point_Fit;
      Status      : out Ks_Status) is
   begin
      if Calibration = null
        or else not Valid_Calibration (Calibration)
        or else Calibration.Calibrated /= False_Value
        or else Calibration.Mode /= Mode_Linear
        or else Count_Of (Calibration) < Min_Points (Calibration.DOF)
        or else (Calibration.Kind = Kind_Checkerboard
                 and then Count_Of (Calibration) < Min_Corners)
        or else not Valid_Fit (Fit)
        or else not Has_DOF_Structure (Fit, Calibration.DOF)
      then
         Set_Failure (Status, Failure_Image_File,
                      "Calibration'Read: malformed computed state");
         return;
      end if;
      Calibration.Fit := Fit;
      Calibration.Calibrated := True_Value;
      Set_Success (Status);
   end Restore_Fit;

   procedure Restore_Mode
     (Calibration : Ks_Calibration;
      Mode        : Int32;
      Status      : out Ks_Status) is
   begin
      Calibration_Set_Computation_Mode (Calibration, Mode, Status);
      To_Image_File (Status, "Calibration'Read: malformed computation mode");
   end Restore_Mode;

   procedure Restore_Adjustment
     (Calibration : Ks_Calibration;
      Adjustment  : Ks_Calibration_Adjustment;
      Status      : out Ks_Status) is
   begin
      if Calibration = null
        or else not Valid_Calibration (Calibration)
        or else not Valid_Adjustment (Adjustment)
      then
         Set_Failure (Status, Failure_Image_File,
                      "Calibration'Read: malformed origin adjustment");
         return;
      end if;
      Calibration.Adjustment := Adjustment;
      Set_Success (Status);
   end Restore_Adjustment;

   procedure Restore_Model
     (Calibration : Ks_Calibration;
      Fit         : Ks_N_Point_To_N_Point_Fit;
      Model       : Ks_Radial_Warp_Model;
      Status      : out Ks_Status) is
   begin
      if Calibration = null
        or else not Valid_Calibration (Calibration)
        or else Calibration.Calibrated /= False_Value
        or else Calibration.Mode /= Mode_Perspective_And_Radial_Warp
        or else Count_Of (Calibration) < Min_Warp_Points
        or else (Calibration.Kind = Kind_Checkerboard
                 and then (Calibration.Corners = null
                           or else Count_Of (Calibration) < Min_Corners
                           or else Model.Image_Width
                                     /= Calibration.Image_Width
                           or else Model.Image_Height
                                     /= Calibration.Image_Height))
        or else not Valid_Fit (Fit)
        or else not Valid_Model (Model)
        or else Model.Center_X /= Long_Float (Model.Image_Width - 1) * 0.5
        or else Model.Center_Y /= Long_Float (Model.Image_Height - 1) * 0.5
        or else Model.Normalizer
                  /= Radial.Normaliser (Model.Image_Width, Model.Image_Height)
        or else Model.Valid_Radius_Squared
                  /= Radial.Valid_Radius (Model.K1, Model.K2)
      then
         Set_Failure (Status, Failure_Image_File,
                      "Calibration'Read: malformed computed state");
         return;
      end if;
      Calibration.Fit := Fit;
      Calibration.Model := Model;
      Calibration.Image_Width := Model.Image_Width;
      Calibration.Image_Height := Model.Image_Height;
      Calibration.Calibrated := True_Value;
      Set_Success (Status);
   end Restore_Model;

end AMV.Kernels.Calib_Fix;
