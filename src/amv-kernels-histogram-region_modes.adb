pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.Affine_Transform;

package body AMV.Kernels.Histogram.Region_Modes with SPARK_Mode is

   package KA renames AMV.Kernels.Affine_Transform;

   use type KI.Ks_Image_8_Grey;
   use type KR.Flag_Matrix_Access;

   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Grey_8_Matrix, KI.Grey_8_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Ks_Image_8_Grey_Data, KI.Ks_Image_8_Grey);
   procedure Free is new Ada.Unchecked_Deallocation
     (KR.Flag_Matrix, KR.Flag_Matrix_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (KR.Ks_Pixel_Region_Data, KR.Ks_Pixel_Region);

   procedure Check_Region_Mode
     (Mode       : Int32;
      Has_Region : Int32;
      Kind       : Int32;
      Masked     : Int32;
      Status     : out Ks_Status) is
   begin
      if Mode not in Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask
                   .. Region_Mode_Affine_Transform
      then
         Set_Failure
           (Status, Failure_Bad_Parameter,
            "RegionMode must be PixelAlignedBoundingBoxAdjustMask (0), "
            & "PixelAlignedBoundingBox (1) or AffineTransform (2)");
      elsif Mode = Region_Mode_Affine_Transform
        and then Has_Region = True_Value
        and then Kind /= KS.Shape_Rectangle_Affine
      then
         Set_Failure
           (Status, Failure_Bad_Parameter,
            "Region must be an affine rectangle for RegionMode "
            & "AffineTransform");
      elsif Mode = Region_Mode_Affine_Transform
        and then Has_Region = True_Value
        and then Masked /= False_Value
      then
         Set_Failure
           (Status, Failure_Bad_Parameter,
            "InputImageMask is not supported with RegionMode "
            & "AffineTransform");
      else
         Set_Success (Status);
      end if;
   end Check_Region_Mode;

   procedure Execute_Affine
     (Image             : access constant KI.Ks_Image_8_Grey_Data;
      Region            : KS.Ks_Rectangle_Affine;
      Pixel_From_Region : KT.Ks_Transform_2D_Linear;
      Params            : Ks_Histogram;
      Result            : out Ks_Histogram_Result;
      Status            : out Ks_Status)
   is
      Sampled     : KI.Ks_Image_8_Grey;
      Sampled_Map : KI.Ks_Image_8_Grey;
      Unused_PFR : KT.Ks_Transform_2D_Linear;
      Whole       : KR.Ks_Pixel_Region;
   begin
      Result := null;
      Check_Input_Image (Image, Status);
      if not Succeeded (Status) then
         return;
      elsif not Valid_Params (Params) then
         --  Execute reports the parameter at fault (the region is not
         --  looked at).
         Execute (Image, null, Params, Result, Status);
         return;
      end if;
      KA.Execute
        (Image, Region, Pixel_From_Region, (others => <>),
         (others => <>), False_Value, Sampled, Sampled_Map, Unused_PFR,
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
                      "Histogram: not enough memory for a region");
         return;
      end if;
      Execute (Sampled, Whole, Params, Result, Status);
      Free (Whole.Flags);
      Free (Whole);
      Free (Sampled.Pixels);
      Free (Sampled);
   end Execute_Affine;

end AMV.Kernels.Histogram.Region_Modes;
