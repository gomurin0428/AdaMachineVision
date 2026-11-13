pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.Copy_Region;

package body AMV.Kernels.Sobel_Edge.Region_Modes with SPARK_Mode is

   package KC renames AMV.Kernels.Copy_Region;

   use type KR.Flag_Matrix_Access;

   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Grey_8_Matrix, KI.Grey_8_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Ks_Image_8_Grey_Data, KI.Ks_Image_8_Grey);
   procedure Free is new Ada.Unchecked_Deallocation
     (KR.Flag_Matrix, KR.Flag_Matrix_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (KR.Ks_Pixel_Region_Data, KR.Ks_Pixel_Region);

   Identity : constant KT.Ks_Transform_2D_Linear := (others => <>);

   Mode_Message : constant String :=
     "RunParams.RegionMode must be PixelAlignedBoundingBox (1) or"
     & " AffineTransform (2)";

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

   procedure Check_Affine_Region (Kind : Int32; Status : out Ks_Status) is
   begin
      if Kind = KS.Shape_Rectangle_Affine then
         Set_Success (Status);
      else
         Bad (Status, "Region must be an affine rectangle for RegionMode"
                      & " AffineTransform");
      end if;
   end Check_Affine_Region;

   procedure Execute_In_Box
     (Image                 : access constant KI.Ks_Image_8_Grey_Data;
      Region                : access constant KR.Ks_Pixel_Region_Data;
      Params                : Ks_Sobel_Edge;
      Edge_Magnitude_Image  : out KI.Ks_Image_8_Grey;
      Edge_Angle_Image      : out KI.Ks_Image_8_Grey;
      Final_Magnitude_Image : out KI.Ks_Image_8_Grey;
      Output_From_Input     : out KT.Ks_Transform_2D_Linear;
      Status                : out Ks_Status)
   is
      Box    : KI.Ks_Image_8_Grey;
      Whole  : KR.Ks_Pixel_Region;
      Unused : KT.Ks_Transform_2D_Linear;
   begin
      Edge_Magnitude_Image := null;
      Edge_Angle_Image := null;
      Final_Magnitude_Image := null;
      Output_From_Input := Identity;
      Check_Input_Image (Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Run_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Params.Region_Mode = Region_Mode_Affine_Transform then
         Bad (Status, "RunParams.RegionMode AffineTransform needs an affine"
                      & " rectangle (ks_sobel_edge_execute_affine)");
         return;
      elsif Params.Region_Mode /= Region_Mode_Pixel_Aligned_Bounding_Box then
         Bad (Status, Mode_Message);
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

      --  The box is the whole image: no copy of it.
      if Region.Flags = null
        and then Region.X_Min = 0 and then Region.Y_Min = 0
        and then Region.Width = Image.Width
        and then Region.Height = Image.Height
      then
         Execute (Image, Region, Params, Edge_Magnitude_Image,
                  Edge_Angle_Image, Final_Magnitude_Image, Status);
         if Succeeded (Status) then
            pragma Assert (Box_Size (Region, Edge_Magnitude_Image));
            pragma Assert (Box_Size (Region, Edge_Angle_Image));
            pragma Assert (Box_Size (Region, Final_Magnitude_Image));
            Output_From_Input := Box_Transform (Region);
            pragma Assert (KT.Bounded (Output_From_Input));
         end if;
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
      KR.Whole_Image (Box.Width, Box.Height, Whole, Status);
      if not Succeeded (Status) then
         Free (Box.Pixels);
         Free (Box);
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "SobelEdge: not enough memory for a region");
         return;
      end if;
      Execute (Box, Whole, Params, Edge_Magnitude_Image, Edge_Angle_Image,
               Final_Magnitude_Image, Status);
      pragma Assert
        (if Succeeded (Status)
         then Box_Size (Region, Edge_Magnitude_Image)
              and then Box_Size (Region, Edge_Angle_Image)
              and then Box_Size (Region, Final_Magnitude_Image));
      pragma Assert
        (if Succeeded (Status)
            and then Params.Post_Process_Mode = Post_Process_None
         then Final_Magnitude_Image.Pixels.all
                = Edge_Magnitude_Image.Pixels.all);
      Free (Whole.Flags);
      Free (Whole);
      Free (Box.Pixels);
      Free (Box);
      if Succeeded (Status) then
         Output_From_Input := Box_Transform (Region);
         pragma Assert (KT.Bounded (Output_From_Input));
      end if;
   end Execute_In_Box;

   procedure Execute_Affine
     (Image                  : access constant KI.Ks_Image_8_Grey_Data;
      Region                 : KS.Ks_Rectangle_Affine;
      Pixel_From_Region      : KT.Ks_Transform_2D_Linear;
      Pixel_From_Root        : KT.Ks_Transform_2D_Linear;
      Params                 : Ks_Sobel_Edge;
      Edge_Magnitude_Image   : out KI.Ks_Image_8_Grey;
      Edge_Angle_Image       : out KI.Ks_Image_8_Grey;
      Final_Magnitude_Image  : out KI.Ks_Image_8_Grey;
      Output_Pixel_From_Root : out KT.Ks_Transform_2D_Linear;
      Status                 : out Ks_Status)
   is
      Sampled     : KI.Ks_Image_8_Grey;
      Sampled_Map : KI.Ks_Image_8_Grey;
      Sampled_PFR : KT.Ks_Transform_2D_Linear;
      Whole       : KR.Ks_Pixel_Region;
   begin
      Edge_Magnitude_Image := null;
      Edge_Angle_Image := null;
      Final_Magnitude_Image := null;
      Output_Pixel_From_Root := Identity;
      Check_Input_Image (Image, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Run_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Params.Region_Mode = Region_Mode_Pixel_Aligned_Bounding_Box then
         Bad (Status, "RunParams.RegionMode PixelAlignedBoundingBox needs a"
                      & " pixel region (ks_sobel_edge_execute_in_box)");
         return;
      elsif Params.Region_Mode /= Region_Mode_Affine_Transform then
         Bad (Status, Mode_Message);
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
                      "SobelEdge: not enough memory for a region");
         return;
      end if;
      Execute (Sampled, Whole, Params, Edge_Magnitude_Image,
               Edge_Angle_Image, Final_Magnitude_Image, Status);
      pragma Assert
        (if Succeeded (Status)
         then Edge_Magnitude_Image.Width = Sampled.Width
              and then Edge_Magnitude_Image.Height = Sampled.Height);
      Free (Whole.Flags);
      Free (Whole);
      Free (Sampled.Pixels);
      Free (Sampled);
      if Succeeded (Status) then
         Output_Pixel_From_Root := Sampled_PFR;
      end if;
   end Execute_Affine;

end AMV.Kernels.Sobel_Edge.Region_Modes;
