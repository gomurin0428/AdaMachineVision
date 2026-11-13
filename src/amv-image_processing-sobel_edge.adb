pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Images;
with AMV.Kernels.Sobel_Edge.Region_Modes;
with AMV.Kernels.Transforms;
with AMV.Regions;
with AMV.Regions.Kernel_Regions;
with AMV.Shapes;
with AMV.Shapes.Kernel_Shapes;
with AMV.Transforms;

package body AMV.Image_Processing.Sobel_Edge is

   package KS renames AMV.Kernels.Sobel_Edge;
   package KM renames AMV.Kernels.Sobel_Edge.Region_Modes;
   package KI renames AMV.Kernels.Images;
   package KT renames AMV.Kernels.Transforms;
   package Kernel_Shapes renames AMV.Shapes.Kernel_Shapes;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;

   use type AMV.Kernels.Int32;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

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

   procedure Set_Hysteresis_Thresholds
     (Params                    : in out Ks_Sobel_Edge;
      Hysteresis_Threshold_Low  : Integer;
      Hysteresis_Threshold_High : Integer) is
   begin
      Params.Hysteresis_Threshold_Low := Int32 (Hysteresis_Threshold_Low);
      Params.Hysteresis_Threshold_High := Int32 (Hysteresis_Threshold_High);
   end Set_Hysteresis_Thresholds;

   function Edge_Magnitude_Image
     (Result : Ks_Sobel_Edge_Result) return AMV.Images.Ks_Image_8_Grey is
     (Result.Edge_Magnitude);

   function Edge_Angle_Image
     (Result : Ks_Sobel_Edge_Result) return AMV.Images.Ks_Image_8_Grey is
     (Result.Edge_Angle);

   function Final_Magnitude_Image
     (Result : Ks_Sobel_Edge_Result) return AMV.Images.Ks_Image_8_Grey is
     (Result.Final_Magnitude);

   procedure Release (Handle : in out KI.Ks_Image_8_Grey);
   --  Frees a handle the result could not take over.

   procedure Release (Handle : in out KI.Ks_Image_8_Grey) is
      Status : Ks_Status;
   begin
      KI.Destroy (Handle, Status);
   end Release;

   overriding procedure Execute (Tool : in out Ks_Sobel_Edge_Tool) is
      Image     : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Tool.Input_Image);
      Status    : Ks_Status;
      Magnitude : KI.Ks_Image_8_Grey;
      Angle     : KI.Ks_Image_8_Grey;
      Final     : KI.Ks_Image_8_Grey;
      Transform : KT.Ks_Transform_2D_Linear;
      Affine    : constant Boolean :=
        Tool.Run_Params.Region_Mode = Affine_Transform
        and then not Tool.Region.Is_Empty;

      function Adopt
        (Handle : KI.Ks_Image_8_Grey) return AMV.Images.Ks_Image_8_Grey
      is (if Affine
          then AMV.Images.Kernel_Images.Adopt_With_Pixel_From_Root
                 (Handle, Tool.Input_Image, Transform)
          else AMV.Images.Kernel_Images.Adopt
                 (Handle, Tool.Input_Image, Transform));
      --  An output image: Transform is its pixel-from-root transform
      --  (Affine_Transform) or the shift from the input's pixels.
   begin
      --  The image first, so that an unallocated one is reported as such
      --  before the region is rasterised.
      KS.Check_Input_Image (Image, Status);
      Check (Status);
      if Affine then
         declare
            Region : AMV.Shapes.Ks_Region'Class renames
              Tool.Region.Constant_Reference.Element.all;
         begin
            KM.Check_Affine_Region
              (Kernel_Shapes.Kernel_Type (Region), Status);
            Check (Status);
            KM.Execute_Affine
              (Image,
               Kernel_Shapes.Kernel_Rectangle_Affine
                 (AMV.Shapes.Ks_Rectangle_Affine'Class (Region)),
               To_Kernel (Tool.Input_Image.Get_Transform
                            (AMV.Coordinate_Spaces.Pixel_Space_Name,
                             Region.Selected_Space_Name)),
               To_Kernel (Tool.Input_Image.Pixel_From_Root_Transform),
               Tool.Run_Params, Magnitude, Angle, Final, Transform, Status);
            Check (Status);
         end;
      else
         declare
            Region : constant AMV.Regions.Pixel_Region :=
              AMV.Regions.Rasterize (Tool.Input_Image, Tool.Region);
            Params : Ks_Sobel_Edge := Tool.Run_Params;
         begin
            --  Without a region, Affine_Transform processes the whole
            --  image, as the box of an empty holder does.
            if Params.Region_Mode = Affine_Transform then
               Params.Region_Mode := Pixel_Aligned_Bounding_Box;
            end if;
            KM.Execute_In_Box
              (Image, AMV.Regions.Kernel_Regions.Kernel_Handle (Region),
               Params, Magnitude, Angle, Final, Transform, Status);
            Check (Status);
         end;
      end if;
      --  Each Adopt takes over its handle (and frees it if it fails); the
      --  handles not taken over yet are freed here.
      begin
         Tool.Result.Edge_Magnitude := Adopt (Magnitude);
      exception
         when others =>
            Release (Angle);
            Release (Final);
            raise;
      end;
      begin
         Tool.Result.Edge_Angle := Adopt (Angle);
      exception
         when others =>
            Release (Final);
            raise;
      end;
      Tool.Result.Final_Magnitude := Adopt (Final);
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Sobel_Edge_Tool) is
      No_Result : Ks_Sobel_Edge_Result;
   begin
      Tool.Result := No_Result;
   end Reset_Results;

end AMV.Image_Processing.Sobel_Edge;
