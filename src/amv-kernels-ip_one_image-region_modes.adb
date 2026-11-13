pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.Copy_Region;

package body AMV.Kernels.IP_One_Image.Region_Modes with SPARK_Mode is

   package KC renames AMV.Kernels.Copy_Region;

   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Grey_8_Matrix, KI.Grey_8_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Ks_Image_8_Grey_Data, KI.Ks_Image_8_Grey);
   procedure Free is new Ada.Unchecked_Deallocation
     (KR.Flag_Matrix, KR.Flag_Matrix_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (KR.Ks_Pixel_Region_Data, KR.Ks_Pixel_Region);

   Identity : constant KT.Ks_Transform_2D_Linear := (others => <>);

   procedure Bad
     (Status  : out Ks_Status;
      Message : String)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad
     (Status  : out Ks_Status;
      Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   function First_Enabled (Ops : Ks_IP_One_Image_Operators) return Integer
   is
   begin
      for I in 0 .. Integer (Ops.Count) - 1 loop
         if Ops.Items (I).Enabled = True_Value then
            return I;
         end if;
         pragma Loop_Invariant
           (for all J in 0 .. I => Ops.Items (J).Enabled /= True_Value);
      end loop;
      return -1;
   end First_Enabled;

   function Up_To
     (Ops : Ks_IP_One_Image_Operators;
      F   : Natural) return Ks_IP_One_Image_Operators
   is
     ((Ops with delta Count => Int32 (F) + 1))
   with
     Pre  => Ops.Count in 0 .. Max_Operators
             and then F < Natural (Ops.Count),
     Post => Up_To'Result.Count = Int32 (F) + 1
             and then Up_To'Result.Items = Ops.Items
             and then (if not Has_Geometric (Ops)
                       then not Has_Geometric (Up_To'Result));
   --  The operators 0 .. F of the list.

   function After
     (Ops : Ks_IP_One_Image_Operators;
      F   : Natural) return Ks_IP_One_Image_Operators
   with
     Pre  => Ops.Count in 0 .. Max_Operators
             and then F < Natural (Ops.Count),
     Post => After'Result.Count = Ops.Count
             and then
               (for all I in 0 .. Max_Operators - 1 =>
                  (if I > F then After'Result.Items (I) = Ops.Items (I)))
             and then
               (for all I in 0 .. F =>
                  After'Result.Items (I).Enabled = False_Value)
             and then (if not Has_Geometric (Ops)
                       then not Has_Geometric (After'Result));
   --  The list with the operators 0 .. F disabled.

   function After
     (Ops : Ks_IP_One_Image_Operators;
      F   : Natural) return Ks_IP_One_Image_Operators
   is
      Result : Ks_IP_One_Image_Operators := Ops;
   begin
      for I in 0 .. F loop
         Result.Items (I).Enabled := False_Value;
         pragma Loop_Invariant (Result.Count = Ops.Count);
         pragma Loop_Invariant
           (for all J in 0 .. Max_Operators - 1 =>
              (if J > I then Result.Items (J) = Ops.Items (J)));
         pragma Loop_Invariant
           (for all J in 0 .. I => Result.Items (J).Enabled = False_Value);
      end loop;
      return Result;
   end After;

   procedure Affine_Region
     (Kind      : Int32;
      Rectangle : KS.Ks_Rectangle;
      Affine    : KS.Ks_Rectangle_Affine;
      Result    : out KS.Ks_Rectangle_Affine;
      Status    : out Ks_Status)
   is
      Message : constant String :=
        "Region must be a rectangle or an affine rectangle for RegionMode"
        & " AffineTransform";
   begin
      Result := (others => <>);
      if Kind = KS.Shape_Rectangle_Affine
        and then KS.Valid_Rectangle_Affine (Affine)
      then
         Result := Affine;
         Set_Success (Status);
      elsif Kind = KS.Shape_Rectangle
        and then KS.Valid_Rectangle (Rectangle)
      then
         KS.Set_Origin_Lengths_Rotation_Skew
           (Rectangle.X, Rectangle.Y, Rectangle.Width, Rectangle.Height,
            0.0, 0.0, Result, Status);
         if not Succeeded (Status) then
            Result := (others => <>);
            Bad (Status, Message);
         end if;
      else
         Bad (Status, Message);
      end if;
   end Affine_Region;

   procedure Execute_In_Box
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Region            : access constant KR.Ks_Pixel_Region_Data;
      Region_Mode       : Int32;
      Operators         : Ks_IP_One_Image_Operators;
      Masks             : access constant Operator_Masks;
      Output            : out KI.Ks_Image_8_Grey;
      Output_From_Input : out KT.Ks_Transform_2D_Linear;
      Status            : out Ks_Status)
   is
      Box     : KI.Ks_Image_8_Grey;
      Mid     : KI.Ks_Image_8_Grey;
      Local   : KR.Ks_Pixel_Region;
      Unused  : KT.Ks_Transform_2D_Linear;
      Inner   : KT.Ks_Transform_2D_Linear;
      F       : Integer;
   begin
      Output := null;
      Output_From_Input := Identity;
      Check_Input_Image (Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Region_Mode
           not in Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask
                | Region_Mode_Pixel_Aligned_Bounding_Box
      then
         Bad (Status, "RegionMode must be PixelAlignedBoundingBoxAdjustMask"
                      & " (0) or PixelAlignedBoundingBox (1)");
         return;
      end if;
      if Region = null then
         Bad (Status, "Region covers no pixel of InputImage");
         return;
      elsif not KR.Valid_Region (Region) then
         Bad (Status, "Region is not a valid pixel region handle");
         return;
      elsif not KR.In_Image (Region, Image.Width, Image.Height) then
         Bad (Status, "Region does not lie in InputImage");
         return;
      end if;
      Check_Operators (Operators, Status);
      if not Succeeded (Status) then
         return;
      end if;
      F := First_Enabled (Operators);
      if Region_Mode = Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask
        and then Region.Flags /= null
        and then F >= 0
        and then Is_Geometric (Operators.Items (F))
      then
         Bad (Status, "RegionMode PixelAlignedBoundingBoxAdjustMask needs a"
                      & " Region that fills its bounding box when the first"
                      & " operator changes the pixel grid");
         return;
      end if;

      --  The box is the whole image: no copy of it.
      if Fills_Whole_Image (Image, Region) then
         Execute_Masked
           (Image, Region, Operators, Masks, Output, Inner, Status);
         if not Succeeded (Status) then
            return;
         end if;
         pragma Assert (KI.Valid_Image (Output));
         pragma Assert
           (if not Has_Geometric (Operators)
            then Output.Width = Region.Width
                 and then Output.Height = Region.Height);
         if Has_Geometric (Operators) then
            Output_From_Input := Inner;
         else
            Output_From_Input := Box_Transform (Region);
         end if;
         pragma Assert (KT.Bounded (Output_From_Input));
         return;
      end if;

      --  The box as an image of its own.
      KC.Execute
        (Image, Region, Identity,
         (Fill_Bounding_Box => False_Value,
          Fill_Region       => False_Value,
          Region_Mode       => KC.Region_Mode_Pixel_Aligned_Bounding_Box,
          others            => <>),
         Box, Unused, Status);
      if not Succeeded (Status) then
         return;
      end if;
      pragma Assert (Box.Width = Region.Width
                     and then Box.Height = Region.Height);

      if Region_Mode = Region_Mode_Pixel_Aligned_Bounding_Box
        or else Region.Flags = null
        or else F < 0
      then
         --  Every pixel of the box is processed.
         KR.Whole_Image (Box.Width, Box.Height, Local, Status);
         if not Succeeded (Status) then
            Free (Box.Pixels);
            Free (Box);
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "IPOneImage: not enough memory for a region");
            return;
         end if;
         Execute_Masked (Box, Local, Operators, Masks, Output, Inner, Status);
         pragma Assert
           (if Succeeded (Status) and then not Has_Geometric (Operators)
            then Output.Width = Region.Width
                 and then Output.Height = Region.Height);
         Free (Local.Flags);
         Free (Local);
         Free (Box.Pixels);
         Free (Box);
         if not Succeeded (Status) then
            return;
         end if;
      else
         --  The first enabled operator on the region's pixels, the others
         --  on the whole box. The first one keeps the pixel grid (checked
         --  above), so Mid has the size of the box.
         KR.Shift_To_Origin (Region, Local, Status);
         if not Succeeded (Status) then
            Free (Box.Pixels);
            Free (Box);
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "IPOneImage: not enough memory for a region");
            return;
         end if;
         pragma Assert (not Has_Geometric (Up_To (Operators, F)));
         Execute_Masked
           (Box, Local, Up_To (Operators, F), Masks, Mid, Unused, Status);
         Free (Local.Flags);
         Free (Local);
         Free (Box.Pixels);
         Free (Box);
         if not Succeeded (Status) then
            return;
         end if;
         pragma Assert (Mid.Width = Region.Width
                        and then Mid.Height = Region.Height);
         KR.Whole_Image (Mid.Width, Mid.Height, Local, Status);
         if not Succeeded (Status) then
            Free (Mid.Pixels);
            Free (Mid);
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "IPOneImage: not enough memory for a region");
            return;
         end if;
         Execute_Masked
           (Mid, Local, After (Operators, F), Masks, Output, Inner, Status);
         pragma Assert
           (if Succeeded (Status) and then not Has_Geometric (Operators)
            then Output.Width = Region.Width
                 and then Output.Height = Region.Height);
         Free (Local.Flags);
         Free (Local);
         Free (Mid.Pixels);
         Free (Mid);
         if not Succeeded (Status) then
            return;
         end if;
      end if;

      pragma Assert (KI.Valid_Image (Output));
      pragma Assert
        (if not Has_Geometric (Operators)
         then Output.Width = Region.Width
              and then Output.Height = Region.Height);
      pragma Assert (KT.Bounded (Box_Transform (Region)));
      if Has_Geometric (Operators) then
         KT.Compose (Inner, Box_Transform (Region), Output_From_Input,
                     Status);
         if not Succeeded (Status) then
            Free (Output.Pixels);
            Free (Output);
            Output_From_Input := Identity;
            return;
         end if;
      else
         Output_From_Input := Box_Transform (Region);
      end if;
      Set_Success (Status);
   end Execute_In_Box;

   procedure Execute_Affine
     (Image                  : access constant KI.Ks_Image_8_Grey_Data;
      Region                 : KS.Ks_Rectangle_Affine;
      Pixel_From_Region      : KT.Ks_Transform_2D_Linear;
      Pixel_From_Root        : KT.Ks_Transform_2D_Linear;
      Operators              : Ks_IP_One_Image_Operators;
      Masks                  : access constant Operator_Masks;
      Output                 : out KI.Ks_Image_8_Grey;
      Output_Pixel_From_Root : out KT.Ks_Transform_2D_Linear;
      Status                 : out Ks_Status)
   is
      Sampled     : KI.Ks_Image_8_Grey;
      Sampled_Map : KI.Ks_Image_8_Grey;
      Sampled_PFR : KT.Ks_Transform_2D_Linear;
      Whole       : KR.Ks_Pixel_Region;
      Inner       : KT.Ks_Transform_2D_Linear;
      F           : Integer;
   begin
      Output := null;
      Output_Pixel_From_Root := Identity;
      Check_Input_Image (Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Operators (Operators, Status);
      if not Succeeded (Status) then
         return;
      end if;
      F := First_Enabled (Operators);
      if F >= 0 and then Operators.Items (F).Kind = Kind_Pel_Set then
         Bad (Status, "RegionMode AffineTransform does not support a PelSet"
                      & " as the first operator");
         return;
      end if;
      KA.Execute
        (Image, Region, Pixel_From_Region, Pixel_From_Root,
         (others => <>), False_Value, Sampled, Sampled_Map, Sampled_PFR,
         Status);
      if not Succeeded (Status) then
         return;
      end if;
      pragma Assert (Sampled_Map = null);
      KR.Whole_Image (Sampled.Width, Sampled.Height, Whole, Status);
      if not Succeeded (Status) then
         Free (Sampled.Pixels);
         Free (Sampled);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "IPOneImage: not enough memory for a region");
         return;
      end if;
      Execute_Masked (Sampled, Whole, Operators, Masks, Output, Inner, Status);
      Free (Whole.Flags);
      Free (Whole);
      Free (Sampled.Pixels);
      Free (Sampled);
      if not Succeeded (Status) then
         return;
      end if;
      KT.Compose (Inner, Sampled_PFR, Output_Pixel_From_Root, Status);
      if not Succeeded (Status) then
         Free (Output.Pixels);
         Free (Output);
         Output_Pixel_From_Root := Identity;
         return;
      end if;
   end Execute_Affine;

end AMV.Kernels.IP_One_Image.Region_Modes;
