pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

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

package body AMV.Image_Processing.IP_One_Image is

   package KI renames AMV.Kernels.Images;
   package KM renames AMV.Kernels.IP_One_Image.Region_Modes;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;
   package Kernel_Shapes renames AMV.Shapes.Kernel_Shapes;

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

   function Affine_Region
     (Region : AMV.Shapes.Ks_Region'Class) return KS.Ks_Rectangle_Affine;
   --  Region as the affine rectangle of the Affine_Transform mode
   --  (Ks_Bad_Parameter_Exception for a region that is not a rectangle).

   function Affine_Region
     (Region : AMV.Shapes.Ks_Region'Class) return KS.Ks_Rectangle_Affine
   is
      Kind      : constant Int32 := Kernel_Shapes.Kernel_Type (Region);
      Rectangle : KS.Ks_Rectangle;
      Affine    : KS.Ks_Rectangle_Affine;
      Status    : Ks_Status;
   begin
      if Region in AMV.Shapes.Ks_Rectangle'Class then
         Rectangle := Kernel_Shapes.Kernel_Rectangle
           (AMV.Shapes.Ks_Rectangle'Class (Region));
      elsif Region in AMV.Shapes.Ks_Rectangle_Affine'Class then
         Affine := Kernel_Shapes.Kernel_Rectangle_Affine
           (AMV.Shapes.Ks_Rectangle_Affine'Class (Region));
      end if;
      return Result : KS.Ks_Rectangle_Affine do
         KM.Affine_Region (Kind, Rectangle, Affine, Result, Status);
         Check (Status);
      end return;
   end Affine_Region;

   ---------------------------------------------------------------------
   --  Operators
   ---------------------------------------------------------------------

   function New_Operator (Kind : Ks_IP_One_Image_Operator_Kind)
      return Ks_IP_One_Image_Operator
   is
      Status : Ks_Status;
   begin
      return Result : Ks_IP_One_Image_Operator do
         KO.Operator_Default (Code (Kind), Result, Status);
         Check (Status);
      end return;
   end New_Operator;

   function Kind (Operator : Ks_IP_One_Image_Operator)
      return Ks_IP_One_Image_Operator_Kind
   is
      Code   : Int32;
      Status : Ks_Status;
   begin
      KO.Operator_Get_Kind (Operator, Code, Status);
      Check (Status);
      return Ks_IP_One_Image_Operator_Kind'Val (Code);
   end Kind;

   function Enabled (Operator : Ks_IP_One_Image_Operator) return Boolean is
      Flag   : Int32;
      Status : Ks_Status;
   begin
      KO.Operator_Get_Enabled (Operator, Flag, Status);
      Check (Status);
      return Boolean'Val (Flag);
   end Enabled;

   procedure Set_Enabled
     (Operator : in out Ks_IP_One_Image_Operator;
      Value    : Boolean) is
   begin
      Operator.Enabled := Boolean'Pos (Value);
   end Set_Enabled;

   function Get_Kernel_Value
     (Params   : Ks_IP_One_Image_Convolve_NxM;
      Col, Row : Natural) return Real
   is
      Value  : Real;
      Status : Ks_Status;
   begin
      KO.Convolve_NxM_Get_Kernel_Value
        (Params, Int32 (Col), Int32 (Row), Value, Status);
      Check (Status);
      return Value;
   end Get_Kernel_Value;

   procedure Set_Kernel_Value
     (Params    : in out Ks_IP_One_Image_Convolve_NxM;
      Col, Row  : Natural;
      New_Value : Real)
   is
      Status : Ks_Status;
   begin
      KO.Convolve_NxM_Set_Kernel_Value
        (Params, Int32 (Col), Int32 (Row), New_Value, Status);
      Check (Status);
   end Set_Kernel_Value;

   procedure Set_Kernel
     (Params : in out Ks_IP_One_Image_Convolve_3x3;
      Kernel : Convolve_3x3_Kernel) is
   begin
      Params.Kernel := Kernel;
   end Set_Kernel;

   function Get_Kernel_Value
     (Params   : Ks_IP_One_Image_Convolve_3x3;
      Position : Ks_IP_One_Image_Convolve_3x3_Position_Constants)
      return Real
   is
      Value  : Real;
      Status : Ks_Status;
   begin
      KO.Convolve_3x3_Get_Kernel_Value (Params, Code (Position), Value,
                                        Status);
      Check (Status);
      return Value;
   end Get_Kernel_Value;

   procedure Set_Kernel_Value
     (Params   : in out Ks_IP_One_Image_Convolve_3x3;
      Position : Ks_IP_One_Image_Convolve_3x3_Position_Constants;
      Value    : Real)
   is
      Status : Ks_Status;
   begin
      KO.Convolve_3x3_Set_Kernel_Value (Params, Code (Position), Value,
                                        Status);
      Check (Status);
   end Set_Kernel_Value;

   ---------------------------------------------------------------------
   --  The operator list
   ---------------------------------------------------------------------

   function Count (Operators : Ks_IP_One_Image_Operators) return Natural is
      Result : Int32;
      Status : Ks_Status;
   begin
      KO.Operators_Count (Operators, Result, Status);
      Check (Status);
      return Natural (Result);
   end Count;

   function Item
     (Operators : Ks_IP_One_Image_Operators;
      Index     : Natural) return Ks_IP_One_Image_Operator
   is
      Status : Ks_Status;
   begin
      return Result : Ks_IP_One_Image_Operator do
         KO.Operators_Item (Operators, Int32 (Index), Result, Status);
         Check (Status);
      end return;
   end Item;

   procedure Set_Item
     (Operators : in out Ks_IP_One_Image_Operators;
      Index     : Natural;
      Operator  : Ks_IP_One_Image_Operator)
   is
      Status : Ks_Status;
   begin
      KO.Operators_Set_Item (Operators, Int32 (Index), Operator, Status);
      Check (Status);
   end Set_Item;

   procedure Add
     (Operators : in out Ks_IP_One_Image_Operators;
      Operator  : Ks_IP_One_Image_Operator)
   is
      Status : Ks_Status;
   begin
      KO.Operators_Add (Operators, Operator, Status);
      Check (Status);
   end Add;

   procedure Insert
     (Operators : in out Ks_IP_One_Image_Operators;
      Operator  : Ks_IP_One_Image_Operator;
      Index     : Natural)
   is
      Status : Ks_Status;
   begin
      KO.Operators_Insert (Operators, Operator, Int32 (Index), Status);
      Check (Status);
   end Insert;

   procedure Remove_At
     (Operators : in out Ks_IP_One_Image_Operators;
      Index     : Natural)
   is
      Status : Ks_Status;
   begin
      KO.Operators_Remove_At (Operators, Int32 (Index), Status);
      Check (Status);
   end Remove_At;

   procedure Move
     (Operators  : in out Ks_IP_One_Image_Operators;
      From_Index : Natural;
      To_Index   : Natural)
   is
      Status : Ks_Status;
   begin
      KO.Operators_Move (Operators, Int32 (From_Index), Int32 (To_Index),
                         Status);
      Check (Status);
   end Move;

   procedure Clear (Operators : in out Ks_IP_One_Image_Operators) is
   begin
      Operators.Count := 0;
   end Clear;

   ---------------------------------------------------------------------
   --  The tool
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_IP_One_Image_Tool) is
      Image  : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Tool.Input_Image);
      Status : Ks_Status;
   begin
      --  The image first, so that an unallocated one is reported as such
      --  before the region is looked at.
      KO.Check_Input_Image (Image, Status);
      Check (Status);
      declare
         Output    : KI.Ks_Image_8_Grey;
         Transform : KT.Ks_Transform_2D_Linear;
         Masks     : aliased constant KO.Operator_Masks :=
           [for I in KO.Operator_Masks'Range =>
              KO.Mask_Ref (AMV.Images.Kernel_Images.Kernel_Handle
                             (Tool.Input_Image_Masks (I)))];
      begin
         if Tool.Region_Mode = Affine_Transform
           and then not Tool.Region.Is_Empty
         then
            declare
               Region : AMV.Shapes.Ks_Region'Class renames
                 Tool.Region.Constant_Reference.Element.all;
               Affine : constant KS.Ks_Rectangle_Affine :=
                 Affine_Region (Region);
            begin
               KM.Execute_Affine
                 (Image, Affine,
                  To_Kernel (Tool.Input_Image.Get_Transform
                               (AMV.Coordinate_Spaces.Pixel_Space_Name,
                                Region.Selected_Space_Name)),
                  To_Kernel (Tool.Input_Image.Pixel_From_Root_Transform),
                  Tool.Operators, Masks'Access, Output, Transform, Status);
               Check (Status);
               Tool.Output_Image :=
                 AMV.Images.Kernel_Images.Adopt_With_Pixel_From_Root
                   (Output, Tool.Input_Image, Transform);
            end;
         else
            declare
               Region : constant AMV.Regions.Pixel_Region :=
                 AMV.Regions.Rasterize (Tool.Input_Image, Tool.Region);
               --  Without a region, Affine_Transform processes the whole
               --  image, as the box of an empty holder does.
               Mode   : constant Int32 :=
                 (if Tool.Region_Mode = Affine_Transform
                  then Pixel_Aligned_Bounding_Box else Tool.Region_Mode);
            begin
               KM.Execute_In_Box
                 (Image, AMV.Regions.Kernel_Regions.Kernel_Handle (Region),
                  Mode, Tool.Operators, Masks'Access, Output, Transform,
                  Status);
               Check (Status);
               Tool.Output_Image :=
                 AMV.Images.Kernel_Images.Adopt
                   (Output, Tool.Input_Image, Transform);
            end;
         end if;
      end;
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_IP_One_Image_Tool)
   is
      Unallocated : AMV.Images.Ks_Image_8_Grey;
   begin
      Tool.Output_Image := Unallocated;
   end Reset_Results;

end AMV.Image_Processing.IP_One_Image;
