pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Histogram.Region_Modes;
with AMV.Kernels.Images;
with AMV.Kernels.Transforms;
with AMV.Regions;
with AMV.Regions.Kernel_Regions;
with AMV.Shapes;
with AMV.Shapes.Kernel_Shapes;
with AMV.Transforms;

package body AMV.Image_Processing.Histogram is

   package KH renames AMV.Kernels.Histogram;
   package KM renames AMV.Kernels.Histogram.Region_Modes;
   package KT renames AMV.Kernels.Transforms;
   package Kernel_Shapes renames AMV.Shapes.Kernel_Shapes;

   use type AMV.Kernels.Int32;

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

   function Flag (Value : Boolean) return AMV.Kernels.Int32 is
     (if Value then AMV.Kernels.True_Value else AMV.Kernels.False_Value);
   package KI renames AMV.Kernels.Images;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   procedure Destroy (Handle : in out KH.Ks_Histogram_Result) is
      Status : Ks_Status;
   begin
      KH.Destroy (Handle, Status);
   end Destroy;

   function Statistics_Of
     (Result : Ks_Histogram_Result) return KH.Ks_Histogram_Statistics;
   --  The scalar properties of the result.

   function Statistics_Of
     (Result : Ks_Histogram_Result) return KH.Ks_Histogram_Statistics
   is
      Statistics : KH.Ks_Histogram_Statistics;
      Status     : Ks_Status;
   begin
      KH.Get_Statistics
        (Result_Holders.Get (Result.Holder), Statistics, Status);
      Check (Status);
      return Statistics;
   end Statistics_Of;

   function Num_Samples (Result : Ks_Histogram_Result) return Natural is
     (Natural (Statistics_Of (Result).Num_Samples));

   function Mean (Result : Ks_Histogram_Result) return Real is
     (Statistics_Of (Result).Mean);

   function Standard_Deviation (Result : Ks_Histogram_Result) return Real is
     (Statistics_Of (Result).Standard_Deviation);

   function Variance (Result : Ks_Histogram_Result) return Real is
     (Statistics_Of (Result).Variance);

   function Minimum (Result : Ks_Histogram_Result) return Natural is
     (Natural (Statistics_Of (Result).Minimum));

   function Maximum (Result : Ks_Histogram_Result) return Natural is
     (Natural (Statistics_Of (Result).Maximum));

   function Median (Result : Ks_Histogram_Result) return Natural is
     (Natural (Statistics_Of (Result).Median));

   function Mode (Result : Ks_Histogram_Result) return Natural is
     (Natural (Statistics_Of (Result).Mode));

   function Get_Histogram (Result : Ks_Histogram_Result)
      return Ks_Histogram_Array
   is
      Handle : constant KH.Ks_Histogram_Result :=
        Result_Holders.Get (Result.Holder);
      Last   : Int32;
      Status : Ks_Status;
   begin
      KH.Last_Bin (Handle, Last, Status);
      Check (Status);
      return Bins : Ks_Histogram_Array (0 .. Natural (Last)) do
         KH.Get_Histogram (Handle, Bins, Status);
         Check (Status);
      end return;
   end Get_Histogram;

   function Get_Inverse_Cumulative_Grey_Level
     (Result  : Ks_Histogram_Result;
      Percent : Integer) return Natural
   is
      Level  : Int32;
      Status : Ks_Status;
   begin
      KH.Inverse_Cumulative_Grey_Level
        (Result_Holders.Get (Result.Holder), Int32 (Percent), Level, Status);
      Check (Status);
      return Natural (Level);
   end Get_Inverse_Cumulative_Grey_Level;

   function Get_Minimum_WGV_Threshold
     (Result : Ks_Histogram_Result) return Natural
   is
      Threshold : Int32;
      Status    : Ks_Status;
   begin
      KH.Minimum_WGV_Threshold
        (Result_Holders.Get (Result.Holder), Threshold, Status);
      Check (Status);
      return Natural (Threshold);
   end Get_Minimum_WGV_Threshold;

   overriding procedure Execute (Tool : in out Ks_Histogram_Tool) is
      Image  : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Tool.Input_Image);
      Status : Ks_Status;

      procedure Count (Samples : AMV.Regions.Pixel_Region);
      --  The histogram of the pixels of Samples, kept as the result.

      procedure Count (Samples : AMV.Regions.Pixel_Region) is
         Handle : KH.Ks_Histogram_Result;
      begin
         KH.Execute
           (Image, AMV.Regions.Kernel_Regions.Kernel_Handle (Samples),
            Tool.Run_Params, Handle, Status);
         Check (Status);
         Result_Holders.Set (Tool.Result.Holder, Handle);
      end Count;
      Has_Region : constant Boolean := not Tool.Region.Is_Empty;
   begin
      --  The image first, so that an unallocated one is reported as such
      --  before the region is rasterised; then the region mode.
      KH.Check_Input_Image (Image, Status);
      Check (Status);
      KM.Check_Region_Mode
        (Tool.Region_Mode, Flag (Has_Region),
         (if Has_Region
          then Kernel_Shapes.Kernel_Type
                 (Tool.Region.Constant_Reference.Element.all)
          else 0),
         Flag (Tool.Input_Image_Mask.Allocated), Status);
      Check (Status);
      if Tool.Region_Mode = Affine_Transform and then Has_Region then
         declare
            Region : AMV.Shapes.Ks_Region'Class renames
              Tool.Region.Constant_Reference.Element.all;
            Handle : KH.Ks_Histogram_Result;
         begin
            KM.Execute_Affine
              (Image,
               Kernel_Shapes.Kernel_Rectangle_Affine
                 (AMV.Shapes.Ks_Rectangle_Affine'Class (Region)),
               To_Kernel (Tool.Input_Image.Get_Transform
                            (AMV.Coordinate_Spaces.Pixel_Space_Name,
                             Region.Selected_Space_Name)),
               Tool.Run_Params, Handle, Status);
            Check (Status);
            Result_Holders.Set (Tool.Result.Holder, Handle);
         end;
         return;
      end if;
      declare
         Covered : constant AMV.Regions.Pixel_Region :=
           AMV.Regions.Rasterize (Tool.Input_Image, Tool.Region);
         Region  : constant AMV.Regions.Pixel_Region :=
           (if Tool.Region_Mode = Pixel_Aligned_Bounding_Box
            then AMV.Regions.Bounding_Box (Covered)
            else Covered);
      begin
         if Tool.Input_Image_Mask.Allocated then
            --  Without the pixels the mask marks "don't care".
            Count (AMV.Regions.Restrict_To_Mask
                     (Region, Tool.Input_Image_Mask,
                      Tool.Input_Image_Mask_Offset_X,
                      Tool.Input_Image_Mask_Offset_Y));
         else
            Count (Region);
         end if;
      end;
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Histogram_Tool) is
   begin
      Result_Holders.Clear (Tool.Result.Holder);
   end Reset_Results;

end AMV.Image_Processing.Histogram;
