pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Numerics;

package body AMV.Kernels.PM_Align.Training with SPARK_Mode is

   use type MK.KM.Ks_Real_Image;

   package N renames AMV.Kernels.Numerics;

   procedure Add_Feature
     (L                  : PY.Level_Data;
      Level              : Level_Index;
      Area               : PY.Window;
      I, J               : Natural;
      Pattern_From_Pixel : KT.Ks_Transform_2D_Linear;
      Normals            : P.Unit_Linear;
      Model              : in out Model_Level;
      Too_Far            : out Boolean)
   with
     Pre  => PY.Usable (L)
             and then I in 1 .. Natural (L.GX.Width) - 2
             and then J in 1 .. Natural (L.GX.Height) - 2
             and then Model.Count < Max_Features
             and then KT.Bounded (Pattern_From_Pixel),
     Post => Model.Count in Model.Count'Old .. Model.Count'Old + 1
             and then Model.Spacing = Model.Spacing'Old;
   --  Appends the feature of the edge pixel (I, J) (see Extract), unless
   --  its gradient or its mapped normal vanishes. Too_Far when its
   --  position is beyond Max_Pattern_Coordinate (nothing appended then).

   procedure Add_Feature
     (L                  : PY.Level_Data;
      Level              : Level_Index;
      Area               : PY.Window;
      I, J               : Natural;
      Pattern_From_Pixel : KT.Ks_Transform_2D_Linear;
      Normals            : P.Unit_Linear;
      Model              : in out Model_Level;
      Too_Far            : out Boolean)
   is
      GX     : constant PY.Grad_Value := PY.Read (L.GX, I, J);
      GY     : constant PY.Grad_Value := PY.Read (L.GY, I, J);
      UX, UY : P.Unit;
      NX, NY : P.Unit;
      Status : Ks_Status;
      PX, PY_Coordinate : Long_Float;
   begin
      Too_Far := False;
      P.Normalise (GX / 16.0, GY / 16.0, UX, UY);
      if UX = 0.0 and then UY = 0.0 then
         return;
      end if;
      declare
         XI : constant Long_Float := Long_Float (I);
         YJ : constant Long_Float := Long_Float (J);
         T  : constant Long_Float :=
           PY.Parabola_Peak (PY.Projected (L, XI, YJ, UX, UY, -1.0),
                             PY.Projected (L, XI, YJ, UX, UY, 0.0),
                             PY.Projected (L, XI, YJ, UX, UY, 1.0));
         QX : constant P.Position := XI + N.Times_Unit (T, UX);
         QY : constant P.Position := YJ + N.Times_Unit (T, UY);
         X0 : constant Long_Float :=
           P.From_Level (QX, Level) + Long_Float (Area.X_Min);
         Y0 : constant Long_Float :=
           P.From_Level (QY, Level) + Long_Float (Area.Y_Min);
      begin
         KT.Map_Point (Pattern_From_Pixel, X0, Y0, PX, PY_Coordinate,
                       Status);
         if not Succeeded (Status)
           or else abs PX > Max_Pattern_Coordinate
           or else abs PY_Coordinate > Max_Pattern_Coordinate
         then
            Too_Far := True;
            return;
         end if;
      end;
      P.Normalise
        (N.Times_Unit (UX, Normals.A) + N.Times_Unit (UY, Normals.B),
         N.Times_Unit (UX, Normals.C) + N.Times_Unit (UY, Normals.D),
         NX, NY);
      if NX = 0.0 and then NY = 0.0 then
         return;
      end if;
      Model.Features (Model.Count) :=
        (X => PX, Y => PY_Coordinate, NX => NX, NY => NY);
      Model.Count := Model.Count + 1;
   end Add_Feature;

   function Used_Pixel
     (Region : access constant KR.Ks_Pixel_Region_Data;
      Area   : PY.Window;
      Care   : MK.Care_Map;
      Level  : Level_Index;
      I, J   : Natural) return Boolean
   is (PY.Level_Pixel_In_Region (Region, Area, Level, I, J)
       and then MK.Cared (Care, Level, I, J))
   with Pre => MK.Valid_Map (Care);
   --  Pixel (I, J) of Level lies in the region and is cared for.

   function Occupied_Cells
     (L         : PY.Level_Data;
      Level     : Level_Index;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Area      : PY.Window;
      Care      : MK.Care_Map;
      Threshold : Long_Float;
      Size      : Spacing_Value) return Natural
   with Pre => PY.Usable (L) and then MK.Valid_Map (Care);
   --  The number of Size x Size cells of the level (from pixel (1, 1))
   --  that hold at least one edge pixel of the region that Care cares for
   --  (PY.Is_Edge at Threshold, off the level's border), counted up to
   --  Max_Features + 1.

   function Occupied_Cells
     (L         : PY.Level_Data;
      Level     : Level_Index;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Area      : PY.Window;
      Care      : MK.Care_Map;
      Threshold : Long_Float;
      Size      : Spacing_Value) return Natural
   is
      W      : constant Natural := Natural (L.GX.Width);
      H      : constant Natural := Natural (L.GX.Height);
      Result : Natural := 0;
      Found  : Boolean;
   begin
      if W < 3 or else H < 3 then
         return 0;
      end if;
      for CY in 0 .. (H - 3) / Size loop
         pragma Loop_Invariant (Result <= Max_Features + 1);
         for CX in 0 .. (W - 3) / Size loop
            pragma Loop_Invariant (Result <= Max_Features + 1);
            Found := False;
            for J in 1 + CY * Size .. Natural'Min (H - 2, CY * Size + Size)
            loop
               for I in 1 + CX * Size
                 .. Natural'Min (W - 2, CX * Size + Size)
               loop
                  if Used_Pixel (Region, Area, Care, Level, I, J)
                    and then PY.Is_Edge (L, I, J, Threshold)
                  then
                     Found := True;
                  end if;
               end loop;
            end loop;
            if Found then
               Result := Result + 1;
               if Result > Max_Features then
                  return Result;
               end if;
            end if;
         end loop;
      end loop;
      return Result;
   end Occupied_Cells;

   procedure Extract
     (L                  : PY.Level_Data;
      Level              : Level_Index;
      Region             : access constant KR.Ks_Pixel_Region_Data;
      Area               : PY.Window;
      Care               : MK.Care_Map;
      Pattern_From_Pixel : KT.Ks_Transform_2D_Linear;
      Normals            : P.Unit_Linear;
      Model              : out Model_Level;
      Too_Far            : out Boolean)
   is
      W         : constant Natural := Natural (L.GX.Width);
      H         : constant Natural := Natural (L.GX.Height);
      Largest   : Long_Float range 0.0 .. PY.Max_Magnitude_Squared := 0.0;
      Threshold : Long_Float;
      Size      : Spacing_Value := 1;
      Far       : Boolean;
   begin
      Model := (Count => 0, Spacing => 1,
                Features => [others => (others => <>)],
                Ignored_Count => 0, Ignored_Spacing => 1,
                Ignored => [others => (others => <>)]);
      Too_Far := False;
      if W < 3 or else H < 3 then
         return;
      end if;

      --  The train threshold: the larger of Min_Train_Contrast and
      --  Train_Contrast_Fraction times the largest magnitude in the
      --  region (compared as squares).
      for J in 1 .. H - 2 loop
         for I in 1 .. W - 2 loop
            if Used_Pixel (Region, Area, Care, Level, I, J) then
               Largest :=
                 Long_Float'Max (Largest, PY.Magnitude_Squared (L, I, J));
            end if;
         end loop;
      end loop;
      Threshold :=
        Long_Float'Max (Min_Train_Contrast * Min_Train_Contrast,
                        Train_Contrast_Fraction * Train_Contrast_Fraction
                        * Largest);

      --  The spacing: the smallest cell size at which the edge pixels
      --  occupy at most Max_Features cells (Max_Spacing at most).
      while Size < Max_Spacing
        and then Occupied_Cells (L, Level, Region, Area, Care, Threshold,
                                 Size)
                   > Max_Features
      loop
         pragma Loop_Invariant (Size < Max_Spacing);
         pragma Loop_Variant (Increases => Size);
         Size := Size + 1;
      end loop;
      Model.Spacing := Size;

      --  One feature per occupied cell, in raster order of the cells: the
      --  cell's edge pixel of largest gradient magnitude (the first in
      --  raster order among equals).
      for CY in 0 .. (H - 3) / Size loop
         pragma Loop_Invariant (Model.Count <= Max_Features
                                and then Model.Spacing = Size);
         for CX in 0 .. (W - 3) / Size loop
            pragma Loop_Invariant (Model.Count <= Max_Features
                                   and then Model.Spacing = Size);
            exit when Model.Count = Max_Features;
            declare
               Best_I, Best_J : Natural := 0;
               Best           : Long_Float := -1.0;
            begin
               for J in 1 + CY * Size
                 .. Natural'Min (H - 2, CY * Size + Size)
               loop
                  pragma Loop_Invariant
                    (if Best >= 0.0
                     then Best_I in 1 .. W - 2 and then Best_J in 1 .. H - 2);
                  for I in 1 + CX * Size
                    .. Natural'Min (W - 2, CX * Size + Size)
                  loop
                     pragma Loop_Invariant
                       (if Best >= 0.0
                        then Best_I in 1 .. W - 2
                             and then Best_J in 1 .. H - 2);
                     if Used_Pixel (Region, Area, Care, Level, I, J)
                       and then PY.Is_Edge (L, I, J, Threshold)
                       and then PY.Magnitude_Squared (L, I, J) > Best
                     then
                        Best := PY.Magnitude_Squared (L, I, J);
                        Best_I := I;
                        Best_J := J;
                     end if;
                  end loop;
               end loop;
               if Best >= 0.0 then
                  Add_Feature (L, Level, Area, Best_I, Best_J,
                               Pattern_From_Pixel, Normals, Model, Far);
                  if Far then
                     Too_Far := True;
                     return;
                  end if;
               end if;
            end;
         end loop;
      end loop;
   end Extract;

   function Left_Out_Cells
     (W, H   : Natural;
      Level  : Level_Index;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Area   : PY.Window;
      Care   : MK.Care_Map;
      Size   : Ignored_Spacing_Value) return Natural
   with Pre => MK.Valid_Map (Care);
   --  The number of Size x Size cells of a W x H level that hold a pixel
   --  of the region that Care does not care for, counted up to
   --  Max_Features + 1.

   function Left_Out
     (Region : access constant KR.Ks_Pixel_Region_Data;
      Area   : PY.Window;
      Care   : MK.Care_Map;
      Level  : Level_Index;
      I, J   : Natural) return Boolean
   is (PY.Level_Pixel_In_Region (Region, Area, Level, I, J)
       and then not MK.Cared (Care, Level, I, J))
   with Pre => MK.Valid_Map (Care);
   --  Pixel (I, J) of Level lies in the region and is not cared for.

   function Left_Out_Cells
     (W, H   : Natural;
      Level  : Level_Index;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Area   : PY.Window;
      Care   : MK.Care_Map;
      Size   : Ignored_Spacing_Value) return Natural
   is
      Result : Natural := 0;
      Found  : Boolean;
   begin
      if W = 0 or else H = 0 then
         return 0;
      end if;
      for CY in 0 .. (H - 1) / Size loop
         pragma Loop_Invariant (Result <= Max_Features + 1);
         for CX in 0 .. (W - 1) / Size loop
            pragma Loop_Invariant (Result <= Max_Features + 1);
            Found := False;
            --  CY * Size <= H - 1 and CX * Size <= W - 1 (the loop
            --  ranges), so the cell's last row and column stay within the
            --  level.
            for J in CY * Size
              .. CY * Size + Natural'Min (Size - 1, H - 1 - CY * Size)
            loop
               for I in CX * Size
                 .. CX * Size + Natural'Min (Size - 1, W - 1 - CX * Size)
               loop
                  if Left_Out (Region, Area, Care, Level, I, J) then
                     Found := True;
                  end if;
               end loop;
            end loop;
            if Found then
               Result := Result + 1;
               if Result > Max_Features then
                  return Result;
               end if;
            end if;
         end loop;
      end loop;
      return Result;
   end Left_Out_Cells;

   procedure Extract_Ignored
     (L                  : PY.Level_Data;
      Level              : Level_Index;
      Region             : access constant KR.Ks_Pixel_Region_Data;
      Area               : PY.Window;
      Care               : MK.Care_Map;
      Pattern_From_Pixel : KT.Ks_Transform_2D_Linear;
      Model              : in out Model_Level)
   is
      W    : constant Natural := Natural (L.GX.Width);
      H    : constant Natural := Natural (L.GX.Height);
      Size : Ignored_Spacing_Value := 1;
   begin
      Model.Ignored_Count := 0;
      Model.Ignored_Spacing := 1;
      if Care.Counts = null or else W = 0 or else H = 0 then
         return;
      end if;
      while Size < Max_Ignored_Spacing
        and then Left_Out_Cells (W, H, Level, Region, Area, Care, Size)
                   > Max_Features
      loop
         pragma Loop_Invariant
           (Model.Count = Model.Count'Loop_Entry
            and then Model.Spacing = Model.Spacing'Loop_Entry
            and then Model.Features = Model.Features'Loop_Entry);
         pragma Loop_Variant (Increases => Size);
         Size := Size + 1;
      end loop;
      Model.Ignored_Spacing := Size;

      for CY in 0 .. (H - 1) / Size loop
         pragma Loop_Invariant
           (Model.Ignored_Count <= Max_Features
            and then Model.Count = Model.Count'Loop_Entry
            and then Model.Spacing = Model.Spacing'Loop_Entry
            and then Model.Features = Model.Features'Loop_Entry);
         for CX in 0 .. (W - 1) / Size loop
            pragma Loop_Invariant
              (Model.Ignored_Count <= Max_Features
               and then Model.Count = Model.Count'Loop_Entry
               and then Model.Spacing = Model.Spacing'Loop_Entry
               and then Model.Features = Model.Features'Loop_Entry);
            exit when Model.Ignored_Count = Max_Features;
            declare
               I_Last : constant Natural :=
                 CX * Size + Natural'Min (Size - 1, W - 1 - CX * Size);
               J_Last : constant Natural :=
                 CY * Size + Natural'Min (Size - 1, H - 1 - CY * Size);
               Found  : Boolean := False;
            begin
               for J in CY * Size .. J_Last loop
                  for I in CX * Size .. I_Last loop
                     if Left_Out (Region, Area, Care, Level, I, J) then
                        Found := True;
                     end if;
                  end loop;
               end loop;
               if Found then
                  declare
                     --  The cell's centre, in level pixels (at most
                     --  2**31), then in image pixels.
                     XL : constant P.Position :=
                       (Long_Float (CX * Size) + Long_Float (I_Last)) / 2.0;
                     YL : constant P.Position :=
                       (Long_Float (CY * Size) + Long_Float (J_Last)) / 2.0;
                     X0 : constant Long_Float :=
                       P.From_Level (XL, Level) + Long_Float (Area.X_Min);
                     Y0 : constant Long_Float :=
                       P.From_Level (YL, Level) + Long_Float (Area.Y_Min);
                     PX, PY_Coordinate : Long_Float;
                     Status : Ks_Status;
                  begin
                     KT.Map_Point (Pattern_From_Pixel, X0, Y0, PX,
                                   PY_Coordinate, Status);
                     if Succeeded (Status)
                       and then abs PX <= Max_Pattern_Coordinate
                       and then abs PY_Coordinate <= Max_Pattern_Coordinate
                     then
                        Model.Ignored (Model.Ignored_Count) :=
                          (X => PX, Y => PY_Coordinate);
                        Model.Ignored_Count := Model.Ignored_Count + 1;
                     end if;
                  end;
               end if;
            end;
         end loop;
      end loop;
   end Extract_Ignored;

end AMV.Kernels.PM_Align.Training;
