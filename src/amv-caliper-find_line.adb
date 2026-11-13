pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;
with AMV.Transforms;

package body AMV.Caliper.Find_Line is

   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;
   package Kernel_Images renames AMV.Images.Kernel_Images;

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

   function To_Kernel (Params : Ks_Find_Line) return KF.Ks_Find_Line_Run_Params
   is
      Result : KF.Ks_Find_Line_Run_Params;
   begin
      Result.Num_Calipers := Int32 (Params.Num_Calipers);
      Result.Num_To_Ignore := Int32 (Params.Num_To_Ignore);
      Result.Decrement_Num_To_Ignore :=
        Boolean'Pos (Params.Decrement_Num_To_Ignore);
      Params.Expected_Line_Segment.Get_Start_End
        (Result.Expected_Line_Segment.Start_X,
         Result.Expected_Line_Segment.Start_Y,
         Result.Expected_Line_Segment.End_X,
         Result.Expected_Line_Segment.End_Y);
      Result.Caliper_Search_Length := Params.Caliper_Search_Length;
      Result.Caliper_Projection_Length := Params.Caliper_Projection_Length;
      Result.Caliper_Search_Direction := Params.Caliper_Search_Direction;
      Result.Caliper_Run_Params := Params.Caliper_Run_Params;
      return Result;
   end To_Kernel;

   function Get_Caliper_Region
     (Params : Ks_Find_Line;
      Index  : Natural) return AMV.Shapes.Ks_Rectangle_Affine
   is
      Region : KS.Ks_Rectangle_Affine;
      Status : Ks_Status;
   begin
      KF.Caliper_Region (To_Kernel (Params), Int32 (Index), Region, Status);
      Check (Status);
      return Result : AMV.Shapes.Ks_Rectangle_Affine do
         Result.Set_Center_Lengths_Rotation_Skew
           (Region.Center_X, Region.Center_Y, Region.Side_X_Length,
            Region.Side_Y_Length, Region.Rotation, Region.Skew);
         Result.Set_Selected_Space_Name
           (Params.Expected_Line_Segment.Selected_Space_Name);
      end return;
   end Get_Caliper_Region;

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   procedure Destroy (Handle : in out KF.Ks_Find_Line_Results) is
   begin
      KF.Results_Destroy (Handle);
   end Destroy;

   function Handle_Of (Results : Ks_Find_Line_Results)
      return KF.Ks_Find_Line_Results is
     (Results_Holders.Get (Results.Holder));

   function Count (Results : Ks_Find_Line_Results) return Natural is
      Result : Int32;
      Status : Ks_Status;
   begin
      KF.Results_Count (Handle_Of (Results), Result, Status);
      Check (Status);
      return Natural (Result);
   end Count;

   function Item
     (Results : Ks_Find_Line_Results;
      Index   : Natural) return Ks_Find_Line_Result
   is
      Data    : KF.Ks_Find_Line_Result;
      Caliper : KC.Ks_Caliper_Results;
      Status  : Ks_Status;
   begin
      KF.Results_Item (Handle_Of (Results), Int32 (Index), Data, Status);
      Check (Status);
      KF.Results_Caliper_Results (Handle_Of (Results), Int32 (Index),
                                  Caliper, Status);
      Check (Status);
      return (Found            => Boolean'Val (Data.Found),
              Used             => Boolean'Val (Data.Used),
              X                => Data.X,
              Y                => Data.Y,
              Distance_To_Line => Data.Distance_To_Line,
              Caliper_Results  => AMV.Caliper.Adopt (Caliper));
   end Item;

   function Get_Line
     (Results : Ks_Find_Line_Results) return AMV.Shapes.Ks_Line
   is
      Line    : KS.Ks_Line;
      Segment : KS.Ks_Line_Segment;
      Status  : Ks_Status;
   begin
      KF.Results_Line (Handle_Of (Results), Line, Segment, Status);
      Check (Status);
      return Result : AMV.Shapes.Ks_Line do
         Result.Set_XY_Rotation (Line.X, Line.Y, Line.Rotation);
      end return;
   end Get_Line;

   function Get_Line_Segment
     (Results : Ks_Find_Line_Results) return AMV.Shapes.Ks_Line_Segment
   is
      Line    : KS.Ks_Line;
      Segment : KS.Ks_Line_Segment;
      Status  : Ks_Status;
   begin
      KF.Results_Line (Handle_Of (Results), Line, Segment, Status);
      Check (Status);
      return Result : AMV.Shapes.Ks_Line_Segment do
         Result.Set_Start_End (Segment.Start_X, Segment.Start_Y,
                               Segment.End_X, Segment.End_Y);
      end return;
   end Get_Line_Segment;

   type Fit is record
      RMS_Error              : Real;
      Num_Found, Num_Used    : Int32;
   end record;

   function Fit_Of (Results : Ks_Find_Line_Results) return Fit is
      Status : Ks_Status;
   begin
      return Result : Fit do
         KF.Results_Fit (Handle_Of (Results), Result.RMS_Error,
                         Result.Num_Found, Result.Num_Used, Status);
         Check (Status);
      end return;
   end Fit_Of;

   function RMS_Error (Results : Ks_Find_Line_Results) return Real is
     (Fit_Of (Results).RMS_Error);

   function Num_Points_Found (Results : Ks_Find_Line_Results) return Natural
   is (Natural (Fit_Of (Results).Num_Found));

   function Num_Points_Used (Results : Ks_Find_Line_Results) return Natural
   is (Natural (Fit_Of (Results).Num_Used));

   ---------------------------------------------------------------------
   --  The tool
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_Find_Line_Tool) is
      Pixel_From_Segment  : constant KT.Ks_Transform_2D_Linear :=
        To_Kernel (Tool.Input_Image.Get_Transform
                     (AMV.Coordinate_Spaces.Pixel_Space_Name,
                      Tool.Run_Params.Expected_Line_Segment
                        .Selected_Space_Name));
      Selected_From_Pixel : constant KT.Ks_Transform_2D_Linear :=
        To_Kernel (Tool.Input_Image.Get_Transform
                     (AMV.Coordinate_Spaces.Selected_Space_Name,
                      AMV.Coordinate_Spaces.Pixel_Space_Name));
      Handle              : KF.Ks_Find_Line_Results;
      Status              : Ks_Status;
   begin
      KF.Execute
        (Kernel_Images.Kernel_Handle (Tool.Input_Image),
         To_Kernel (Tool.Run_Params), Pixel_From_Segment,
         Selected_From_Pixel, Handle, Status);
      Check (Status);
      Results_Holders.Set (Tool.Results.Holder, Handle);
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Find_Line_Tool) is
   begin
      Results_Holders.Clear (Tool.Results.Holder);
   end Reset_Results;

end AMV.Caliper.Find_Line;
