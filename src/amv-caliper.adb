pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Transforms;
with AMV.Shapes.Kernel_Shapes;
with AMV.Transforms;

package body AMV.Caliper is

   package KT renames AMV.Kernels.Transforms;
   package Kernel_Images renames AMV.Images.Kernel_Images;
   package Kernel_Shapes renames AMV.Shapes.Kernel_Shapes;

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
   --  Scorers
   ---------------------------------------------------------------------

   function New_Scorer (Kind : Ks_Caliper_Scorer_Kind)
      return Ks_Caliper_Scorer
   is
      Status : Ks_Status;
   begin
      return Result : Ks_Caliper_Scorer do
         KC.Scorer_Default (Code (Kind), Result, Status);
         Check (Status);
      end return;
   end New_Scorer;

   function Kind (Scorer : Ks_Caliper_Scorer) return Ks_Caliper_Scorer_Kind
   is
      Code   : Int32;
      Status : Ks_Status;
   begin
      KC.Scorer_Get_Kind (Scorer, Code, Status);
      Check (Status);
      return Ks_Caliper_Scorer_Kind'Val (Code);
   end Kind;

   function Enabled (Scorer : Ks_Caliper_Scorer) return Boolean is
      Flag   : Int32;
      Status : Ks_Status;
   begin
      KC.Scorer_Get_Enabled (Scorer, Flag, Status);
      Check (Status);
      return Boolean'Val (Flag);
   end Enabled;

   procedure Set_Enabled (Scorer : in out Ks_Caliper_Scorer; Value : Boolean)
   is
   begin
      Scorer.Enabled := Boolean'Pos (Value);
   end Set_Enabled;

   procedure Set_XY_Parameters
     (Scorer             : in out Ks_Caliper_Scorer;
      X0, X1, XC, Y0, Y1 : Real)
   is
      Result : Ks_Caliper_Scorer;
      Status : Ks_Status;
   begin
      KC.Scorer_Set_XY_Parameters (Scorer, X0, X1, XC, Y0, Y1, Result,
                                   Status);
      Check (Status);
      Scorer := Result;
   end Set_XY_Parameters;

   procedure Get_XY_Parameters
     (Scorer             : Ks_Caliper_Scorer;
      X0, X1, XC, Y0, Y1 : out Real) is
   begin
      X0 := Scorer.X0;
      X1 := Scorer.X1;
      XC := Scorer.XC;
      Y0 := Scorer.Y0;
      Y1 := Scorer.Y1;
   end Get_XY_Parameters;

   function Count (Scorers : Ks_Caliper_Scorers) return Natural is
      Result : Int32;
      Status : Ks_Status;
   begin
      KC.Scorers_Count (Scorers, Result, Status);
      Check (Status);
      return Natural (Result);
   end Count;

   procedure Add
     (Scorers : in out Ks_Caliper_Scorers;
      Scorer  : Ks_Caliper_Scorer)
   is
      Status : Ks_Status;
   begin
      KC.Scorers_Add (Scorers, Scorer, Status);
      Check (Status);
   end Add;

   procedure Remove_At (Scorers : in out Ks_Caliper_Scorers; Index : Natural)
   is
      Status : Ks_Status;
   begin
      KC.Scorers_Remove_At (Scorers, Int32 (Index), Status);
      Check (Status);
   end Remove_At;

   procedure Clear (Scorers : in out Ks_Caliper_Scorers) is
   begin
      Scorers.Count := 0;
   end Clear;

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   procedure Destroy (Handle : in out KC.Ks_Caliper_Results) is
   begin
      KC.Results_Destroy (Handle);
   end Destroy;

   function Count (Results : Ks_Caliper_Results) return Natural is
      Result : Int32;
      Status : Ks_Status;
   begin
      KC.Results_Count (Results_Holders.Get (Results.Holder), Result, Status);
      Check (Status);
      return Natural (Result);
   end Count;

   function Item
     (Results : Ks_Caliper_Results;
      Index   : Natural) return Ks_Caliper_Result
   is
      Status : Ks_Status;
   begin
      return Result : Ks_Caliper_Result do
         KC.Results_Item (Results_Holders.Get (Results.Holder), Int32 (Index),
                          Result, Status);
         Check (Status);
      end return;
   end Item;

   function Profile
     (Results  : Ks_Caliper_Results;
      Filtered : Boolean) return Real_Array;
   --  One of the two profiles.

   function Profile
     (Results  : Ks_Caliper_Results;
      Filtered : Boolean) return Real_Array
   is
      Handle : constant KC.Ks_Caliper_Results :=
        Results_Holders.Get (Results.Holder);
      Length : Int32;
      Status : Ks_Status;
   begin
      KC.Results_Profile_Length (Handle, Length, Status);
      Check (Status);
      return Values : Real_Array (0 .. Integer'Pred (Natural (Length))) do
         KC.Get_Profile (Handle, Filtered, Values, Status);
         Check (Status);
      end return;
   end Profile;

   function Get_Projection_Values
     (Results : Ks_Caliper_Results) return Real_Array is
     (Profile (Results, False));

   function Get_Filtered_Values
     (Results : Ks_Caliper_Results) return Real_Array is
     (Profile (Results, True));

   function Adopt (Handle : KC.Ks_Caliper_Results) return Ks_Caliper_Results
   is
   begin
      return Result : Ks_Caliper_Results do
         Results_Holders.Set (Result.Holder, Handle);
      end return;
   end Adopt;

   ---------------------------------------------------------------------
   --  The tool
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_Caliper_Tool) is
      Pixel_From_Region   : constant KT.Ks_Transform_2D_Linear :=
        To_Kernel (Tool.Input_Image.Get_Transform
                     (AMV.Coordinate_Spaces.Pixel_Space_Name,
                      Tool.Region.Selected_Space_Name));
      Selected_From_Pixel : constant KT.Ks_Transform_2D_Linear :=
        To_Kernel (Tool.Input_Image.Get_Transform
                     (AMV.Coordinate_Spaces.Selected_Space_Name,
                      AMV.Coordinate_Spaces.Pixel_Space_Name));
      Handle              : KC.Ks_Caliper_Results;
      Status              : Ks_Status;
   begin
      KC.Execute
        (Kernel_Images.Kernel_Handle (Tool.Input_Image),
         Kernel_Shapes.Kernel_Rectangle_Affine (Tool.Region),
         Pixel_From_Region, Selected_From_Pixel, Tool.Run_Params, Handle,
         Status);
      Check (Status);
      Results_Holders.Set (Tool.Results.Holder, Handle);
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Caliper_Tool) is
   begin
      Results_Holders.Clear (Tool.Results.Holder);
   end Reset_Results;

end AMV.Caliper;
