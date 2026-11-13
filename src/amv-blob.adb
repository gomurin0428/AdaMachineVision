pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.Unchecked_Deallocation;

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Images;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;
with AMV.Regions;
with AMV.Regions.Kernel_Regions;
with AMV.Shapes.Kernel_Shapes;
with AMV.Transforms;

package body AMV.Blob is

   package KB renames AMV.Kernels.Blob;
   package KBT renames AMV.Kernels.Blob.Tree;
   package KI renames AMV.Kernels.Images;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;
   package Kernel_Images renames AMV.Images.Kernel_Images;
   package Kernel_Regions renames AMV.Regions.Kernel_Regions;
   package Kernel_Shapes renames AMV.Shapes.Kernel_Shapes;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;

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

   ---------------------------------------------------------------------
   --  Codes
   ---------------------------------------------------------------------

   function Code (Value : Ks_Blob_Segmentation_Mode_Constants)
                  return Code_Type
   is (Code_Type (Ks_Blob_Segmentation_Mode_Constants'Pos (Value)));

   function Code (Value : Ks_Blob_Segmentation_Polarity_Constants)
                  return Code_Type
   is (Code_Type (Ks_Blob_Segmentation_Polarity_Constants'Pos (Value)));

   function Code (Value : Ks_Blob_Connectivity_Mode_Constants)
                  return Code_Type
   is (Code_Type (Ks_Blob_Connectivity_Mode_Constants'Pos (Value)));

   function Code (Value : Ks_Blob_Connectivity_Cleanup_Constants)
                  return Code_Type
   is (Code_Type (Ks_Blob_Connectivity_Cleanup_Constants'Pos (Value)));

   function Code (Value : Ks_Blob_Measure_Constants) return Code_Type is
     (Code_Type (Ks_Blob_Measure_Constants'Pos (Value)));

   function Code (Value : Ks_Blob_Measure_Mode_Constants) return Code_Type is
     (Code_Type (Ks_Blob_Measure_Mode_Constants'Pos (Value)));

   function Code (Value : Ks_Blob_Filter_Mode_Constants) return Code_Type is
     (Code_Type (Ks_Blob_Filter_Mode_Constants'Pos (Value)));

   function Code (Value : Ks_Blob_Axis_Constants) return Code_Type is
     (Code_Type (Ks_Blob_Axis_Constants'Pos (Value)));

   function Code (Value : Ks_Blob_Morphology_Constants) return Code_Type is
     (Code_Type (Ks_Blob_Morphology_Constants'Pos (Value)));

   function Code (Value : Ks_Blob_Label_Constants) return Code_Type is
     (Code_Type (Ks_Blob_Label_Constants'Pos (Value)));

   function Code (Value : Ks_Blob_Segmented_Image_Constants)
                  return Code_Type
   is (Code_Type (Ks_Blob_Segmented_Image_Constants'Pos (Value)));

   function Code (Value : Boolean) return Code_Type is
     (Code_Type (Boolean'Pos (Value)));

   ---------------------------------------------------------------------
   --  Run parameters
   ---------------------------------------------------------------------

   function Blob_Measure
     (Measure           : Ks_Blob_Measure_Constants;
      Mode              : Ks_Blob_Measure_Mode_Constants := Pre_Compute;
      Filter_Mode       : Ks_Blob_Filter_Mode_Constants :=
        Include_Blobs_In_Range;
      Filter_Range_Low  : Real := 0.0;  --  SHELL: the spec's default
      Filter_Range_High : Real := 0.0)  --  SHELL: the spec's default
      return Ks_Blob_Measure
   is ((Measure           => Code (Measure),
        Mode              => Code (Mode),
        Filter_Mode       => Code (Filter_Mode),
        Filter_Range_Low  => Filter_Range_Low,
        Filter_Range_High => Filter_Range_High));

   procedure Add
     (Measures : in out Ks_Blob_Measure_Collection;
      Measure  : Ks_Blob_Measure)
   is
      Status : Ks_Status;
   begin
      KB.Add_Measure (Measures, Measure, Status);
      Check (Status);
   end Add;

   procedure Add
     (Operations : in out Ks_Blob_Morphology_Collection;
      Operation  : Ks_Blob_Morphology_Constants)
   is
      Status : Ks_Status;
   begin
      KB.Add_Morphology (Operations, Code (Operation), Status);
      Check (Status);
   end Add;

   procedure Clear (Measures : in out Ks_Blob_Measure_Collection) is
   begin
      Measures.Count := 0;
   end Clear;

   procedure Clear (Operations : in out Ks_Blob_Morphology_Collection) is
   begin
      Operations.Count := 0;
   end Clear;

   procedure Set_Segmentation_Hard_Fixed_Threshold
     (Params               : in out Ks_Blob_Segmentation_Params;
      Hard_Fixed_Threshold : Integer;
      Polarity             : Ks_Blob_Segmentation_Polarity_Constants)
   is
      Status : Ks_Status;
   begin
      KB.Set_Hard_Fixed_Threshold
        (Params, Int32 (Hard_Fixed_Threshold), Code (Polarity), Status);
      Check (Status);
   end Set_Segmentation_Hard_Fixed_Threshold;

   procedure Set_Segmentation_Hard_Relative_Threshold
     (Params                  : in out Ks_Blob_Segmentation_Params;
      Tail_Low                : Integer;
      Tail_High               : Integer;
      Hard_Relative_Threshold : Integer;
      Polarity                : Ks_Blob_Segmentation_Polarity_Constants)
   is
      Status : Ks_Status;
   begin
      KB.Set_Hard_Relative_Threshold
        (Params, Int32 (Tail_Low), Int32 (Tail_High),
         Int32 (Hard_Relative_Threshold), Code (Polarity), Status);
      Check (Status);
   end Set_Segmentation_Hard_Relative_Threshold;

   procedure Set_Segmentation_Hard_Dynamic_Threshold
     (Params    : in out Ks_Blob_Segmentation_Params;
      Tail_Low  : Integer;
      Tail_High : Integer;
      Polarity  : Ks_Blob_Segmentation_Polarity_Constants)
   is
      Status : Ks_Status;
   begin
      KB.Set_Hard_Dynamic_Threshold
        (Params, Int32 (Tail_Low), Int32 (Tail_High), Code (Polarity),
         Status);
      Check (Status);
   end Set_Segmentation_Hard_Dynamic_Threshold;

   procedure Set_Segmentation_Soft_Fixed_Threshold
     (Params                    : in out Ks_Blob_Segmentation_Params;
      Soft_Fixed_Threshold_Low  : Integer;
      Soft_Fixed_Threshold_High : Integer;
      Softness                  : Integer;
      Polarity                  : Ks_Blob_Segmentation_Polarity_Constants)
   is
      Status : Ks_Status;
   begin
      KB.Set_Soft_Fixed_Threshold
        (Params, Int32 (Soft_Fixed_Threshold_Low),
         Int32 (Soft_Fixed_Threshold_High), Int32 (Softness),
         Code (Polarity), Status);
      Check (Status);
   end Set_Segmentation_Soft_Fixed_Threshold;

   procedure Set_Segmentation_Soft_Relative_Threshold
     (Params                       : in out Ks_Blob_Segmentation_Params;
      Tail_Low                     : Integer;
      Tail_High                    : Integer;
      Soft_Relative_Threshold_Low  : Integer;
      Soft_Relative_Threshold_High : Integer;
      Softness                     : Integer;
      Polarity : Ks_Blob_Segmentation_Polarity_Constants)
   is
      Status : Ks_Status;
   begin
      KB.Set_Soft_Relative_Threshold
        (Params, Int32 (Tail_Low), Int32 (Tail_High),
         Int32 (Soft_Relative_Threshold_Low),
         Int32 (Soft_Relative_Threshold_High), Int32 (Softness),
         Code (Polarity), Status);
      Check (Status);
   end Set_Segmentation_Soft_Relative_Threshold;

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   procedure Destroy_Results
     (Handle : in out AMV.Kernels.Blob.Ks_Blob_Results)
   is
      Status : Ks_Status;
   begin
      KB.Destroy (Handle, Status);
   end Destroy_Results;

   function Get_Measure
     (Result  : Ks_Blob_Result;
      Measure : Ks_Blob_Measure_Constants) return Real
   is
      Value  : Long_Float;
      Status : Ks_Status;
   begin
      KB.Get_Measure (Result, Code (Measure), Value, Status);
      Check (Status);
      return Value;
   end Get_Measure;

   function Get_Bounding_Box
     (Result : Ks_Blob_Result;
      Axis   : Ks_Blob_Axis_Constants) return AMV.Shapes.Ks_Rectangle_Affine
   is
      Box    : KS.Ks_Rectangle_Affine;
      Status : Ks_Status;
   begin
      KB.Get_Bounding_Box (Result, Code (Axis), Box, Status);
      Check (Status);
      return Rectangle : AMV.Shapes.Ks_Rectangle_Affine do
         Rectangle.Set_Center_Lengths_Rotation_Skew
           (Box.Center_X, Box.Center_Y, Box.Side_X_Length,
            Box.Side_Y_Length, Box.Rotation, Box.Skew);
      end return;
   end Get_Bounding_Box;

   procedure Destroy_IDs (Handle : in out ID_List_Access) is
      procedure Free is new Ada.Unchecked_Deallocation
        (KBT.Blob_ID_List, ID_List_Access);
   begin
      Free (Handle);
   end Destroy_IDs;

   function Collection_Of
     (Results  : Ks_Blob_Results;
      Relation : Int32;
      Blob_ID  : Integer;
      Filtered : Boolean) return Ks_Blob_Result_Collection;
   --  The collection of the features of the query (AMV.Kernels.Blob.Tree).

   function Collection_Of
     (Results  : Ks_Blob_Results;
      Relation : Int32;
      Blob_ID  : Integer;
      Filtered : Boolean) return Ks_Blob_Result_Collection
   is
      Handle : constant KB.Ks_Blob_Results :=
        Results_Holders.Get (Results.Holder);
      Count  : Int32;
      Status : Ks_Status;
   begin
      KBT.Related_Count (Handle, Relation, Int32 (Blob_ID), Code (Filtered),
                        Count, Status);
      Check (Status);
      return Collection : Ks_Blob_Result_Collection do
         Collection.Holder := Results.Holder;
         declare
            List : constant ID_List_Access :=
              new KBT.Blob_ID_List (1 .. Natural (Count));
         begin
            --  The holder owns the list at once, so that a failure below
            --  frees it; nothing else sees it before it is filled.
            ID_Holders.Set (Collection.IDs, List);
            KBT.Related_IDs (Handle, Relation, Int32 (Blob_ID),
                            Code (Filtered), List.all, Status);
            Check (Status);
         end;
      end return;
   end Collection_Of;

   function Get_Blobs
     (Results  : Ks_Blob_Results;
      Filtered : Boolean := True) return Ks_Blob_Result_Collection'Class
   is (Ks_Blob_Result_Collection'
         (Holder   => Results.Holder,
          IDs      => <>,
          Filtered => Code (Filtered)));

   function Get_Children
     (Results  : Ks_Blob_Results;
      Blob_ID  : Integer;
      Filtered : Boolean) return Ks_Blob_Result_Collection'Class
   is (Collection_Of (Results, KBT.Relation_Children, Blob_ID, Filtered));

   function Get_Siblings
     (Results  : Ks_Blob_Results;
      Blob_ID  : Integer;
      Filtered : Boolean) return Ks_Blob_Result_Collection'Class
   is (Collection_Of (Results, KBT.Relation_Siblings, Blob_ID, Filtered));

   function Get_Top_Level_Blobs
     (Results  : Ks_Blob_Results;
      Filtered : Boolean) return Ks_Blob_Result_Collection'Class
   is (Collection_Of (Results, KBT.Relation_Top_Level, 0, Filtered));

   function Count (Collection : Ks_Blob_Result_Collection) return Natural is
      Result : Int32;
      Status : Ks_Status;
   begin
      KBT.Collection_Count
        (Results_Holders.Get (Collection.Holder),
         ID_Holders.Get (Collection.IDs), Collection.Filtered, Result,
         Status);
      Check (Status);
      return Natural (Result);
   end Count;

   function Item
     (Collection : Ks_Blob_Result_Collection;
      Index      : Natural) return Ks_Blob_Result
   is
      Result : Ks_Blob_Result;
      Status : Ks_Status;
   begin
      KBT.Collection_Item
        (Results_Holders.Get (Collection.Holder),
         ID_Holders.Get (Collection.IDs), Collection.Filtered, Int32 (Index),
         Result, Status);
      Check (Status);
      return Result;
   end Item;

   function Get_Blob_IDs
     (Results  : Ks_Blob_Results;
      Filtered : Boolean) return Ks_Blob_ID_Array
   is
      Handle : constant KB.Ks_Blob_Results :=
        Results_Holders.Get (Results.Holder);
      Count  : Int32;
      Status : Ks_Status;
   begin
      KBT.Related_Count (Handle, KBT.Relation_All, 0, Code (Filtered), Count,
                        Status);
      Check (Status);
      return IDs : Ks_Blob_ID_Array (0 .. Integer (Count) - 1) do  --  SHELL: 0-based, as GetBlobIDs
         KBT.Related_IDs (Handle, KBT.Relation_All, 0, Code (Filtered), IDs,
                         Status);
         Check (Status);
      end return;
   end Get_Blob_IDs;

   function Get_Blob_Measure
     (Results : Ks_Blob_Results;
      Measure : Ks_Blob_Measure_Constants;
      Blob_ID : Integer) return Real
   is
      Value  : Long_Float;
      Status : Ks_Status;
   begin
      KBT.Blob_Measure (Results_Holders.Get (Results.Holder), Code (Measure),
                       Int32 (Blob_ID), Value, Status);
      Check (Status);
      return Value;
   end Get_Blob_Measure;

   function Get_Blob_Measures
     (Results  : Ks_Blob_Results;
      Measure  : Ks_Blob_Measure_Constants;
      Blob_IDs : Ks_Blob_ID_Array) return Ks_Blob_Measure_Array
   is
      Status : Ks_Status;
   begin
      return Values : Ks_Blob_Measure_Array (Blob_IDs'Range) do
         KBT.Blob_Measures (Results_Holders.Get (Results.Holder),
                           Code (Measure), Blob_IDs, Values, Status);
         Check (Status);
      end return;
   end Get_Blob_Measures;

   function Get_Blob_By_ID
     (Results : Ks_Blob_Results;
      Blob_ID : Integer) return Ks_Blob_Result
   is
      Result : Ks_Blob_Result;
      Status : Ks_Status;
   begin
      KB.Get_Blob_By_ID
        (Results_Holders.Get (Results.Holder), Int32 (Blob_ID), Result,
         Status);
      Check (Status);
      return Result;
   end Get_Blob_By_ID;

   function Get_Parent
     (Results : Ks_Blob_Results;
      Blob_ID : Integer) return Integer
   is
      Parent : Int32;
      Status : Ks_Status;
   begin
      KB.Get_Parent
        (Results_Holders.Get (Results.Holder), Int32 (Blob_ID), Parent,
         Status);
      Check (Status);
      return Integer (Parent);
   end Get_Parent;

   function Get_Boundary
     (Results : Ks_Blob_Results;
      Blob_ID : Integer) return AMV.Shapes.Ks_Polygon
   is
      Handle : KS.Ks_Polygon;
      Status : Ks_Status;
   begin
      KB.Get_Boundary
        (Results_Holders.Get (Results.Holder), Int32 (Blob_ID), Handle,
         Status);
      Check (Status);
      return Kernel_Shapes.Adopt (Handle);
   end Get_Boundary;

   function Get_Bounding_Box_At_Angle
     (Results : Ks_Blob_Results;
      Blob_ID : Integer;
      Angle   : Real) return AMV.Shapes.Ks_Rectangle_Affine
   is
      Box    : KS.Ks_Rectangle_Affine;
      Status : Ks_Status;
   begin
      KB.Get_Bounding_Box_At_Angle
        (Results_Holders.Get (Results.Holder), Int32 (Blob_ID), Angle, Box,
         Status);
      Check (Status);
      return Rectangle : AMV.Shapes.Ks_Rectangle_Affine do
         Rectangle.Set_Center_Lengths_Rotation_Skew
           (Box.Center_X, Box.Center_Y, Box.Side_X_Length,
            Box.Side_Y_Length, Box.Rotation, Box.Skew);
      end return;
   end Get_Bounding_Box_At_Angle;

   function Get_Median_X
     (Results : Ks_Blob_Results;
      Blob_ID : Integer;
      Axis    : Ks_Blob_Axis_Constants) return Real
   is
      Median : Long_Float;
      Status : Ks_Status;
   begin
      KB.Get_Median_X
        (Results_Holders.Get (Results.Holder), Int32 (Blob_ID), Code (Axis),
         Median, Status);
      Check (Status);
      return Median;
   end Get_Median_X;

   function Get_Median_Y
     (Results : Ks_Blob_Results;
      Blob_ID : Integer;
      Axis    : Ks_Blob_Axis_Constants) return Real
   is
      Median : Long_Float;
      Status : Ks_Status;
   begin
      KB.Get_Median_Y
        (Results_Holders.Get (Results.Holder), Int32 (Blob_ID), Code (Axis),
         Median, Status);
      Check (Status);
      return Median;
   end Get_Median_Y;

   function Create_Blob_ID_Image
     (Results  : Ks_Blob_Results;
      Filtered : Boolean := True) return AMV.Images.Ks_Image_16_Grey
   is
      Handle : KI.Ks_Image_16_Grey;
      Status : Ks_Status;
   begin
      KB.Create_Blob_ID_Image
        (Results_Holders.Get (Results.Holder), Code (Filtered), Handle,
         Status);
      Check (Status);
      return Image : AMV.Images.Ks_Image_16_Grey :=
        Kernel_Images.Adopt (Handle)
      do
         Image.Set_Coordinate_Space_Tree
           (Results.Spaces.Get_Coordinate_Space_Tree);
         Image.Set_Pixel_From_Root_Transform
           (Results.Spaces.Pixel_From_Root_Transform);
         Image.Set_Selected_Space_Name (Results.Spaces.Selected_Space_Name);
      end return;
   end Create_Blob_ID_Image;

   function Create_Blob_Image
     (Results    : Ks_Blob_Results;
      Filtered   : Boolean := True;
      Viewable   : Boolean := True;
      Background : Integer := 0) return AMV.Images.Ks_Image_8_Grey
   is
      Handle : KI.Ks_Image_8_Grey;
      Status : Ks_Status;
   begin
      KB.Create_Blob_Image
        (Results_Holders.Get (Results.Holder), Code (Filtered),
         Code (Viewable), Int32 (Background), Handle, Status);
      Check (Status);
      return Kernel_Images.Adopt (Handle, Results.Spaces);
   end Create_Blob_Image;

   function Create_Segmented_Image
     (Results     : Ks_Blob_Results;
      Which_Image : Ks_Blob_Segmented_Image_Constants := Final_Image;
      Stretch_It  : Boolean := True) return AMV.Images.Ks_Image_8_Grey
   is
      Handle : KI.Ks_Image_8_Grey;
      Status : Ks_Status;
   begin
      KB.Create_Segmented_Image
        (Results_Holders.Get (Results.Holder), Code (Which_Image),
         Code (Stretch_It), Handle, Status);
      Check (Status);
      return Kernel_Images.Adopt (Handle, Results.Spaces);
   end Create_Segmented_Image;

   function Selected_Space_Name (Results : Ks_Blob_Results) return String is
     (Results.Spaces.Selected_Space_Name);

   ---------------------------------------------------------------------
   --  The tool
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_Blob_Tool) is
      Image  : constant access constant KI.Ks_Image_8_Grey_Data :=
        Kernel_Images.Kernel_Handle (Tool.Input_Image);
      Handle : KB.Ks_Blob_Results;
      Status : Ks_Status;
   begin
      --  A missing image first, then the region (AMV.Regions checks the
      --  image and the region's type before its space), then the selected
      --  space.
      KB.Check_Image (Image, Status);
      Check (Status);
      declare
         Region : constant AMV.Regions.Pixel_Region :=
           AMV.Regions.Rasterize (Tool.Input_Image, Tool.Region);
      begin
         KB.Execute
           (Image, Kernel_Regions.Kernel_Handle (Region), Tool.Run_Params,
            To_Kernel
              (Tool.Input_Image.Get_Transform
                 (AMV.Coordinate_Spaces.Selected_Space_Name,
                  AMV.Coordinate_Spaces.Pixel_Space_Name)),
            Handle, Status);
      end;
      Check (Status);
      Results_Holders.Set (Tool.Results.Holder, Handle);
      Tool.Results.Spaces :=
        AMV.Images.Copy (Tool.Input_Image, AMV.Images.No_Pixels);
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Blob_Tool) is
      Empty : AMV.Images.Ks_Image_8_Grey;
   begin
      Results_Holders.Clear (Tool.Results.Holder);
      Tool.Results.Spaces := Empty;
   end Reset_Results;

end AMV.Blob;
