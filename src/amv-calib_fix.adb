pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.IO_Exceptions;

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Coordinate_Spaces.Kernel_Trees;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Coordinate_Spaces;
with AMV.Kernels.Images;
with AMV.Kernels.Transforms;

package body AMV.Calib_Fix is

   use Ada.Strings.Unbounded;

   use type AMV.Kernels.Int32;

   package KC renames AMV.Kernels.Coordinate_Spaces;
   package KI renames AMV.Kernels.Images;
   package KT renames AMV.Kernels.Transforms;
   package Kernel_Images renames AMV.Images.Kernel_Images;
   package Kernel_Trees renames AMV.Coordinate_Spaces.Kernel_Trees;

   use type KI.Ks_Image_8_Grey;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   ---------------------------------------------------------------------
   --  Conversions
   ---------------------------------------------------------------------

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

   function To_Ada
     (Transform : KT.Ks_Transform_2D_Linear)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is (AMV.Transforms.Create
         (Transform.A, Transform.B, Transform.C, Transform.D,
          Transform.Translation_X, Transform.Translation_Y));

   function Name_Of (Name : Unbounded_String) return KC.Ks_Space_Name is
     (KC.To_Space_Name (To_String (Name)));

   function DOF_Code (Value : Ks_N_Point_To_N_Point_DOF_Constants)
      return Int32
   is (Ks_N_Point_To_N_Point_DOF_Constants'Pos (Value));

   function To_DOF (Code : Int32) return Ks_N_Point_To_N_Point_DOF_Constants
   is (Ks_N_Point_To_N_Point_DOF_Constants'Val (Code));

   function Pixel_From_Root
     (Image : AMV.Images.Ks_Image_8_Grey) return KT.Ks_Transform_2D_Linear
   is (To_Kernel (Image.Pixel_From_Root_Transform));

   function Selection_Of
     (Image : AMV.Images.Ks_Image_8_Grey) return KC.Ks_Space_Name
   is (KC.To_Space_Name (Image.Selected_Space_Name));

   function With_Spaces
     (Image    : AMV.Images.Ks_Image_8_Grey;
      Tree     : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
      Selected : KC.Ks_Space_Name) return AMV.Images.Ks_Image_8_Grey;
   --  Image (its pixels shared) with the tree and the selection the kernel
   --  computed.

   function With_Spaces
     (Image    : AMV.Images.Ks_Image_8_Grey;
      Tree     : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
      Selected : KC.Ks_Space_Name) return AMV.Images.Ks_Image_8_Grey is
   begin
      return Output : AMV.Images.Ks_Image_8_Grey := Image do
         Output.Set_Coordinate_Space_Tree (Tree);
         Output.Set_Selected_Space_Name (KC.To_String (Selected));
      end return;
   end With_Spaces;

   type Point is record
      X, Y : Real;
   end record;

   ---------------------------------------------------------------------
   --  Point pairs
   ---------------------------------------------------------------------

   overriding procedure Adjust (Pairs : in out Point_Pairs) is
      Source : constant KF.Ks_Point_Pairs := Pairs.Handle;
      Status : Ks_Status;
   begin
      --  The copy shares the source's handle until it has its own; it
      --  must not keep it if the duplicate cannot be made.
      Pairs.Handle := null;
      KF.Pairs_Duplicate (Source, Pairs.Handle, Status);
      Check (Status);
   end Adjust;

   overriding procedure Finalize (Pairs : in out Point_Pairs) is
   begin
      KF.Pairs_Destroy (Pairs.Handle);
   end Finalize;

   procedure Write_Pairs
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Point_Pairs)
   is
      Count  : Int32;
      A, B   : Point;
      Status : Ks_Status;
   begin
      KF.Pairs_Num_Points (Item.Handle, Count, Status);
      Check (Status);
      Int32'Write (Stream, KF.Pairs_Stream_Code);
      Int32'Write (Stream, Count);
      for Index in 0 .. Count - 1 loop  --  SHELL: stream I/O, every pair
         KF.Pairs_Get_Point (Item.Handle, Index, KF.Group_A, A.X, A.Y, Status);
         Check (Status);
         KF.Pairs_Get_Point (Item.Handle, Index, KF.Group_B, B.X, B.Y, Status);
         Check (Status);
         Point'Write (Stream, A);
         Point'Write (Stream, B);
      end loop;  --  SHELL: (the loop above)
   end Write_Pairs;

   procedure Swap (Left, Right : in out Point_Pairs);

   procedure Swap (Left, Right : in out Point_Pairs) is
      Left_Handle : constant KF.Ks_Point_Pairs := Left.Handle;
   begin
      Left.Handle := Right.Handle;
      Right.Handle := Left_Handle;
   end Swap;

   procedure Read_Pairs
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Point_Pairs)
   is
      Fresh       : Point_Pairs;
      Code, Count : Int32;
      A, B        : Point;
      Status      : Ks_Status;
   begin
      Int32'Read (Stream, Code);
      Int32'Read (Stream, Count);
      KF.Check_Pairs_Header (Code, Count, Status);
      Check (Status);
      --  Fresh owns the pairs read so far, so that a failure frees them
      --  and leaves Item unchanged.
      for Index in 1 .. Count loop  --  SHELL: stream I/O, every pair
         Point'Read (Stream, A);
         Point'Read (Stream, B);
         KF.Read_Pair (Fresh.Handle, A.X, A.Y, B.X, B.Y, Status);
         Check (Status);
      end loop;  --  SHELL: (the loop above)
      Swap (Item, Fresh);
   end Read_Pairs;

   function Count_Of (Pairs : Point_Pairs) return Natural is
      Count  : Int32;
      Status : Ks_Status;
   begin
      KF.Pairs_Num_Points (Pairs.Handle, Count, Status);
      Check (Status);
      return Natural (Count);
   end Count_Of;

   procedure Add
     (Pairs              : in out Point_Pairs;
      A_X, A_Y, B_X, B_Y : Real)
   is
      Status : Ks_Status;
   begin
      KF.Pairs_Add_Point_Pair (Pairs.Handle, A_X, A_Y, B_X, B_Y, Status);
      Check (Status);
   end Add;

   procedure Delete (Pairs : in out Point_Pairs; Index : Natural) is
      Status : Ks_Status;
   begin
      KF.Pairs_Delete_Point_Pair (Pairs.Handle, Int32 (Index), Status);
      Check (Status);
   end Delete;

   function Get
     (Pairs : Point_Pairs;
      Index : Natural;
      Group : Int32) return Point
   is
      Result : Point;
      Status : Ks_Status;
   begin
      KF.Pairs_Get_Point
        (Pairs.Handle, Int32 (Index), Group, Result.X, Result.Y, Status);
      Check (Status);
      return Result;
   end Get;

   procedure Set
     (Pairs : in out Point_Pairs;
      Index : Natural;
      Group : Int32;
      X, Y  : Real)
   is
      Status : Ks_Status;
   begin
      KF.Pairs_Set_Point (Pairs.Handle, Int32 (Index), Group, X, Y, Status);
      Check (Status);
   end Set;

   ---------------------------------------------------------------------
   --  CogNPointToNPoint
   ---------------------------------------------------------------------

   function Num_Points (Params : Ks_N_Point_To_N_Point) return Natural is
     (Count_Of (Params.Pairs));

   procedure Add_Point_Pair
     (Params               : in out Ks_N_Point_To_N_Point;
      Group_A_X, Group_A_Y : Real;
      Group_B_X, Group_B_Y : Real) is
   begin
      Add (Params.Pairs, Group_A_X, Group_A_Y, Group_B_X, Group_B_Y);
   end Add_Point_Pair;

   procedure Delete_Point_Pair
     (Params : in out Ks_N_Point_To_N_Point;
      Index  : Natural) is
   begin
      Delete (Params.Pairs, Index);
   end Delete_Point_Pair;

   procedure Get_Group_A_Point
     (Params : Ks_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : out Real)
   is
      P : constant Point := Get (Params.Pairs, Index, KF.Group_A);
   begin
      X := P.X;
      Y := P.Y;
   end Get_Group_A_Point;

   function Get_Group_A_Point_X
     (Params : Ks_N_Point_To_N_Point; Index : Natural) return Real
   is (Get (Params.Pairs, Index, KF.Group_A).X);

   function Get_Group_A_Point_Y
     (Params : Ks_N_Point_To_N_Point; Index : Natural) return Real
   is (Get (Params.Pairs, Index, KF.Group_A).Y);

   procedure Set_Group_A_Point
     (Params : in out Ks_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : Real) is
   begin
      Set (Params.Pairs, Index, KF.Group_A, X, Y);
   end Set_Group_A_Point;

   procedure Get_Group_B_Point
     (Params : Ks_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : out Real)
   is
      P : constant Point := Get (Params.Pairs, Index, KF.Group_B);
   begin
      X := P.X;
      Y := P.Y;
   end Get_Group_B_Point;

   function Get_Group_B_Point_X
     (Params : Ks_N_Point_To_N_Point; Index : Natural) return Real
   is (Get (Params.Pairs, Index, KF.Group_B).X);

   function Get_Group_B_Point_Y
     (Params : Ks_N_Point_To_N_Point; Index : Natural) return Real
   is (Get (Params.Pairs, Index, KF.Group_B).Y);

   procedure Set_Group_B_Point
     (Params : in out Ks_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : Real) is
   begin
      Set (Params.Pairs, Index, KF.Group_B, X, Y);
   end Set_Group_B_Point;

   function DOFs_To_Compute
     (Params : Ks_N_Point_To_N_Point)
      return Ks_N_Point_To_N_Point_DOF_Constants
   is (Params.DOFs_To_Compute);

   procedure Set_DOFs_To_Compute
     (Params : in out Ks_N_Point_To_N_Point;
      Value  : Ks_N_Point_To_N_Point_DOF_Constants) is
   begin
      Params.DOFs_To_Compute := Value;
   end Set_DOFs_To_Compute;

   function Compute_Group_A_From_Group_B_Transform
     (Params    : Ks_N_Point_To_N_Point;
      RMS_Error : out Real) return AMV.Transforms.Ks_Transform_2D_Linear
   is
      Fit    : KF.Ks_N_Point_To_N_Point_Fit;
      Status : Ks_Status;
   begin
      KF.N_Point_To_N_Point_Compute
        (Params.Pairs.Handle, DOF_Code (Params.DOFs_To_Compute), Fit,
         Status);
      Check (Status);
      RMS_Error := Fit.RMS_Error;
      return To_Ada (Fit.Transform);
   end Compute_Group_A_From_Group_B_Transform;

   function Compute_Group_A_From_Group_B_Transform
     (Params : Ks_N_Point_To_N_Point)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is
      RMS : Real;
   begin
      return Params.Compute_Group_A_From_Group_B_Transform (RMS);
   end Compute_Group_A_From_Group_B_Transform;

   ---------------------------------------------------------------------
   --  CogFixture and CogFixtureTool
   ---------------------------------------------------------------------

   function Execute
     (Params      : Ks_Fixture;
      Input_Image : AMV.Images.Ks_Image_8_Grey)
      return AMV.Images.Ks_Image_8_Grey
   is
      Tree     : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree :=
        Input_Image.Get_Coordinate_Space_Tree;
      Selected : KC.Ks_Space_Name := Selection_Of (Input_Image);
      Status   : Ks_Status;
   begin
      KF.Fixture_Execute
        (Kernel_Images.Kernel_Handle (Input_Image),
         (Unfixtured_From_Fixtured_Transform =>
            To_Kernel (Params.Unfixtured_From_Fixtured_Transform),
          Fixtured_Space_Name                    =>
            Name_Of (Params.Fixtured_Space_Name),
          Space_To_Output                        =>
            Ks_Fixture_Space_To_Output_Constants'Pos (Params.Space_To_Output),
          Fixtured_Space_Name_Duplicate_Handling =>
            Ks_Fixtured_Space_Name_Duplicate_Handling_Constants'Enum_Rep
              (Params.Fixtured_Space_Name_Duplicate_Handling)),
         Kernel_Trees.Variable_View (Tree).all, Selected,
         Pixel_From_Root (Input_Image), Status);
      Check (Status);
      return With_Spaces (Input_Image, Tree, Selected);
   end Execute;

   overriding procedure Execute (Tool : in out Ks_Fixture_Tool) is
   begin
      Tool.Output_Image := Execute (Tool.Run_Params, Tool.Input_Image);
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Fixture_Tool) is
      Unallocated : AMV.Images.Ks_Image_8_Grey;
   begin
      Tool.Output_Image := Unallocated;
   end Reset_Results;

   ---------------------------------------------------------------------
   --  CogFixtureNPointToNPoint
   ---------------------------------------------------------------------

   function Num_Points (Params : Ks_Fixture_N_Point_To_N_Point) return Natural
   is (Count_Of (Params.Pairs));

   procedure Add_Point_Pair
     (Params                         : in out Ks_Fixture_N_Point_To_N_Point;
      Unfixtured_X, Unfixtured_Y     : Real;
      Raw_Fixtured_X, Raw_Fixtured_Y : Real) is
   begin
      Add (Params.Pairs, Unfixtured_X, Unfixtured_Y, Raw_Fixtured_X,
           Raw_Fixtured_Y);
   end Add_Point_Pair;

   procedure Delete_Point_Pair
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Index  : Natural) is
   begin
      Delete (Params.Pairs, Index);
   end Delete_Point_Pair;

   procedure Get_Unfixtured_Point
     (Params : Ks_Fixture_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : out Real)
   is
      P : constant Point := Get (Params.Pairs, Index, KF.Group_A);
   begin
      X := P.X;
      Y := P.Y;
   end Get_Unfixtured_Point;

   function Get_Unfixtured_Point_X
     (Params : Ks_Fixture_N_Point_To_N_Point; Index : Natural) return Real
   is (Get (Params.Pairs, Index, KF.Group_A).X);

   function Get_Unfixtured_Point_Y
     (Params : Ks_Fixture_N_Point_To_N_Point; Index : Natural) return Real
   is (Get (Params.Pairs, Index, KF.Group_A).Y);

   procedure Set_Unfixtured_Point
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : Real) is
   begin
      Set (Params.Pairs, Index, KF.Group_A, X, Y);
   end Set_Unfixtured_Point;

   procedure Get_Raw_Fixtured_Point
     (Params : Ks_Fixture_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : out Real)
   is
      P : constant Point := Get (Params.Pairs, Index, KF.Group_B);
   begin
      X := P.X;
      Y := P.Y;
   end Get_Raw_Fixtured_Point;

   function Get_Raw_Fixtured_Point_X
     (Params : Ks_Fixture_N_Point_To_N_Point; Index : Natural) return Real
   is (Get (Params.Pairs, Index, KF.Group_B).X);

   function Get_Raw_Fixtured_Point_Y
     (Params : Ks_Fixture_N_Point_To_N_Point; Index : Natural) return Real
   is (Get (Params.Pairs, Index, KF.Group_B).Y);

   procedure Set_Raw_Fixtured_Point
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Index  : Natural;
      X, Y   : Real) is
   begin
      Set (Params.Pairs, Index, KF.Group_B, X, Y);
   end Set_Raw_Fixtured_Point;

   function DOFs_To_Compute
     (Params : Ks_Fixture_N_Point_To_N_Point)
      return Ks_N_Point_To_N_Point_DOF_Constants
   is (Params.DOFs_To_Compute);

   procedure Set_DOFs_To_Compute
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Value  : Ks_N_Point_To_N_Point_DOF_Constants) is
   begin
      Params.DOFs_To_Compute := Value;
   end Set_DOFs_To_Compute;

   function Fixtured_Space_Name
     (Params : Ks_Fixture_N_Point_To_N_Point) return String
   is (To_String (Params.Fixtured_Space_Name));

   procedure Set_Fixtured_Space_Name
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Value  : String) is
   begin
      Params.Fixtured_Space_Name := To_Unbounded_String (Value);
   end Set_Fixtured_Space_Name;

   function Space_To_Output
     (Params : Ks_Fixture_N_Point_To_N_Point)
      return Ks_Fixture_Space_To_Output_Constants
   is (Params.Space_To_Output);

   procedure Set_Space_To_Output
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Value  : Ks_Fixture_Space_To_Output_Constants) is
   begin
      Params.Space_To_Output := Value;
   end Set_Space_To_Output;

   function Fixtured_Space_Name_Duplicate_Handling
     (Params : Ks_Fixture_N_Point_To_N_Point)
      return Ks_Fixtured_Space_Name_Duplicate_Handling_Constants
   is (Params.Fixtured_Space_Name_Duplicate_Handling);

   procedure Set_Fixtured_Space_Name_Duplicate_Handling
     (Params : in out Ks_Fixture_N_Point_To_N_Point;
      Value  : Ks_Fixtured_Space_Name_Duplicate_Handling_Constants) is
   begin
      Params.Fixtured_Space_Name_Duplicate_Handling := Value;
   end Set_Fixtured_Space_Name_Duplicate_Handling;

   function Output_Image
     (Result : Ks_Fixture_N_Point_To_N_Point_Result)
      return AMV.Images.Ks_Image_8_Grey
   is (Result.Output_Image);

   function RMS_Error
     (Result : Ks_Fixture_N_Point_To_N_Point_Result) return Real
   is (Result.RMS_Error);

   function Get_Unfixtured_From_Fixtured_Transform
     (Result : Ks_Fixture_N_Point_To_N_Point_Result)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is (Result.Transform);

   function Execute
     (Params      : Ks_Fixture_N_Point_To_N_Point'Class;
      Input_Image : AMV.Images.Ks_Image_8_Grey)
      return Ks_Fixture_N_Point_To_N_Point_Result
   is
      Tree     : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree :=
        Input_Image.Get_Coordinate_Space_Tree;
      Selected : KC.Ks_Space_Name := Selection_Of (Input_Image);
      Fit      : KF.Ks_N_Point_To_N_Point_Fit;
      Status   : Ks_Status;
   begin
      KF.Fixture_N_Point_To_N_Point_Execute
        (Kernel_Images.Kernel_Handle (Input_Image), Params.Pairs.Handle,
         (DOFs_To_Compute                        =>
            DOF_Code (Params.DOFs_To_Compute),
          Fixtured_Space_Name                    =>
            Name_Of (Params.Fixtured_Space_Name),
          Space_To_Output                        =>
            Ks_Fixture_Space_To_Output_Constants'Pos (Params.Space_To_Output),
          Fixtured_Space_Name_Duplicate_Handling =>
            Ks_Fixtured_Space_Name_Duplicate_Handling_Constants'Enum_Rep
              (Params.Fixtured_Space_Name_Duplicate_Handling)),
         Kernel_Trees.Variable_View (Tree).all, Selected,
         Pixel_From_Root (Input_Image), Fit, Status);
      Check (Status);
      return (Output_Image => With_Spaces (Input_Image, Tree, Selected),
              Transform    => To_Ada (Fit.Transform),
              RMS_Error    => Fit.RMS_Error);
   end Execute;

   overriding procedure Execute
     (Tool : in out Ks_Fixture_N_Point_To_N_Point_Tool) is
   begin
      Tool.Result := Execute (Tool.Run_Params, Tool.Input_Image);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Fixture_N_Point_To_N_Point_Tool)
   is
      Empty : Ks_Fixture_N_Point_To_N_Point_Result;
   begin
      Tool.Result := Empty;
   end Reset_Results;

   ---------------------------------------------------------------------
   --  Calibration handles
   ---------------------------------------------------------------------

   overriding procedure Initialize (Item : in out Calibration_Handle) is
      Status : Ks_Status;
   begin
      KF.Calibration_Create (Item.Kind, Item.Handle, Status);
      Check (Status);
   end Initialize;

   overriding procedure Adjust (Item : in out Calibration_Handle) is
      Source : constant KF.Ks_Calibration := Item.Handle;
      Status : Ks_Status;
   begin
      Item.Handle := null;
      KF.Calibration_Duplicate (Source, Item.Handle, Status);
      Check (Status);
   end Adjust;

   overriding procedure Finalize (Item : in out Calibration_Handle) is
   begin
      KF.Calibration_Destroy (Item.Handle);
   end Finalize;

   function Fit_Of (Item : Calibration_Handle)
      return KF.Ks_N_Point_To_N_Point_Fit
   is
      Fit    : KF.Ks_N_Point_To_N_Point_Fit;
      Status : Ks_Status;
   begin
      KF.Calibration_Computed_Fit (Item.Handle, Fit, Status);
      Check (Status);
      return Fit;
   end Fit_Of;

   function Model_Of (Item : Calibration_Handle)
      return KF.Ks_Radial_Warp_Model
   is
      Model  : KF.Ks_Radial_Warp_Model;
      Status : Ks_Status;
   begin
      KF.Calibration_Computed_Warp_Model (Item.Handle, Model, Status);
      Check (Status);
      return Model;
   end Model_Of;

   function Mode_Of (Item : Calibration_Handle) return Int32 is
      Mode   : Int32;
      Status : Ks_Status;
   begin
      KF.Calibration_Computation_Mode (Item.Handle, Mode, Status);
      Check (Status);
      return Mode;
   end Mode_Of;

   procedure Set_Mode
     (Item  : in out Calibration_Handle;
      Value : Ks_Calib_Fix_Computation_Mode_Constants);

   procedure Set_Mode
     (Item  : in out Calibration_Handle;
      Value : Ks_Calib_Fix_Computation_Mode_Constants)
   is
      Status : Ks_Status;
   begin
      KF.Calibration_Set_Computation_Mode
        (Item.Handle, Ks_Calib_Fix_Computation_Mode_Constants'Enum_Rep (Value),
         Status);
      Check (Status);
   end Set_Mode;

   procedure Calibrate_With
     (Item  : in out Calibration_Handle;
      Image : AMV.Images.Ks_Image_8_Grey);
   --  Calibrate with Image and the transform from its pixels to its
   --  selected space.

   procedure Calibrate_With
     (Item  : in out Calibration_Handle;
      Image : AMV.Images.Ks_Image_8_Grey)
   is
      Status : Ks_Status;
   begin
      KF.Calibration_Calibrate
        (Item.Handle, Kernel_Images.Kernel_Handle (Image),
         To_Kernel (Image.Get_Transform (".", "#")), Status);
      Check (Status);
   end Calibrate_With;

   procedure Map_Output
     (Item             : Calibration_Handle;
      Output_X         : Real;
      Output_Y         : Real;
      Input_X, Input_Y : out Real;
      Inside           : out Boolean);

   procedure Map_Output
     (Item             : Calibration_Handle;
      Output_X         : Real;
      Output_Y         : Real;
      Input_X, Input_Y : out Real;
      Inside           : out Boolean)
   is
      Flag   : Int32;
      Status : Ks_Status;
   begin
      KF.Calibration_Map_Output_Pixel
        (Item.Handle, Output_X, Output_Y, Input_X, Input_Y, Flag, Status);
      Check (Status);
      Inside := Boolean'Val (Flag);
   end Map_Output;

   procedure Map_Input
     (Item               : Calibration_Handle;
      Input_X            : Real;
      Input_Y            : Real;
      Output_X, Output_Y : out Real;
      Inside             : out Boolean);

   procedure Map_Input
     (Item               : Calibration_Handle;
      Input_X            : Real;
      Input_Y            : Real;
      Output_X, Output_Y : out Real;
      Inside             : out Boolean)
   is
      Flag   : Int32;
      Status : Ks_Status;
   begin
      KF.Calibration_Map_Input_Pixel
        (Item.Handle, Input_X, Input_Y, Output_X, Output_Y, Flag, Status);
      Check (Status);
      Inside := Boolean'Val (Flag);
   end Map_Input;

   function Adjustment_Of (Item : Calibration_Handle)
      return KF.Ks_Calibration_Adjustment
   is
      Adjustment : KF.Ks_Calibration_Adjustment;
      Status     : Ks_Status;
   begin
      KF.Calibration_Get_Adjustment (Item.Handle, Adjustment, Status);
      Check (Status);
      return Adjustment;
   end Adjustment_Of;

   procedure Set_Adjustment
     (Item       : in out Calibration_Handle;
      Adjustment : KF.Ks_Calibration_Adjustment)
   is
      Status : Ks_Status;
   begin
      KF.Calibration_Set_Adjustment (Item.Handle, Adjustment, Status);
      Check (Status);
   end Set_Adjustment;

   function Adjusted_Of (Item : Calibration_Handle)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is
      Transform : KT.Ks_Transform_2D_Linear;
      Status    : Ks_Status;
   begin
      KF.Calibration_Computed_Uncalibrated_From_Calibrated
        (Item.Handle, Transform, Status);
      Check (Status);
      return To_Ada (Transform);
   end Adjusted_Of;

   function Space_Code (Value : Ks_Calib_N_Point_Adjustment_Space_Constants)
      return Int32
   is (Ks_Calib_N_Point_Adjustment_Space_Constants'Pos (Value));

   function To_Space (Code : Int32)
      return Ks_Calib_N_Point_Adjustment_Space_Constants
   is (Ks_Calib_N_Point_Adjustment_Space_Constants'Val (Code));

   --  The setters of the origin adjustment: each changes one property of
   --  the adjustment as it is and sets it again (the kernel checks it).

   procedure Set_Origin_X (Item : in out Calibration_Handle; Value : Real) is
      Adjustment : KF.Ks_Calibration_Adjustment := Adjustment_Of (Item);
   begin
      Adjustment.Calibrated_Origin_X := Value;
      Set_Adjustment (Item, Adjustment);
   end Set_Origin_X;

   procedure Set_Origin_Y (Item : in out Calibration_Handle; Value : Real) is
      Adjustment : KF.Ks_Calibration_Adjustment := Adjustment_Of (Item);
   begin
      Adjustment.Calibrated_Origin_Y := Value;
      Set_Adjustment (Item, Adjustment);
   end Set_Origin_Y;

   procedure Set_Origin_Space
     (Item  : in out Calibration_Handle;
      Value : Ks_Calib_N_Point_Adjustment_Space_Constants)
   is
      Adjustment : KF.Ks_Calibration_Adjustment := Adjustment_Of (Item);
   begin
      Adjustment.Calibrated_Origin_Space := Space_Code (Value);
      Set_Adjustment (Item, Adjustment);
   end Set_Origin_Space;

   procedure Set_Rotation (Item : in out Calibration_Handle; Value : Real) is
      Adjustment : KF.Ks_Calibration_Adjustment := Adjustment_Of (Item);
   begin
      Adjustment.Calibrated_X_Axis_Rotation := Value;
      Set_Adjustment (Item, Adjustment);
   end Set_Rotation;

   procedure Set_Rotation_Space
     (Item  : in out Calibration_Handle;
      Value : Ks_Calib_N_Point_Adjustment_Space_Constants)
   is
      Adjustment : KF.Ks_Calibration_Adjustment := Adjustment_Of (Item);
   begin
      Adjustment.Calibrated_X_Axis_Rotation_Space := Space_Code (Value);
      Set_Adjustment (Item, Adjustment);
   end Set_Rotation_Space;

   procedure Set_Swap (Item : in out Calibration_Handle; Value : Boolean) is
      Adjustment : KF.Ks_Calibration_Adjustment := Adjustment_Of (Item);
   begin
      Adjustment.Swap_Calibrated_Handedness := Boolean'Pos (Value);
      Set_Adjustment (Item, Adjustment);
   end Set_Swap;

   procedure Write_Fit
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Fit    : KF.Ks_N_Point_To_N_Point_Fit);

   procedure Write_Fit
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Fit    : KF.Ks_N_Point_To_N_Point_Fit) is
   begin
      Real'Write (Stream, Fit.Transform.A);
      Real'Write (Stream, Fit.Transform.B);
      Real'Write (Stream, Fit.Transform.C);
      Real'Write (Stream, Fit.Transform.D);
      Real'Write (Stream, Fit.Transform.Translation_X);
      Real'Write (Stream, Fit.Transform.Translation_Y);
      Real'Write (Stream, Fit.RMS_Error);
      Real'Write (Stream, Fit.Scaling_X);
      Real'Write (Stream, Fit.Scaling_Y);
      Real'Write (Stream, Fit.Rotation);
      Real'Write (Stream, Fit.Skew);
   end Write_Fit;

   procedure Read_Fit
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Fit    : out KF.Ks_N_Point_To_N_Point_Fit);

   procedure Read_Fit
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Fit    : out KF.Ks_N_Point_To_N_Point_Fit) is
   begin
      Real'Read (Stream, Fit.Transform.A);
      Real'Read (Stream, Fit.Transform.B);
      Real'Read (Stream, Fit.Transform.C);
      Real'Read (Stream, Fit.Transform.D);
      Real'Read (Stream, Fit.Transform.Translation_X);
      Real'Read (Stream, Fit.Transform.Translation_Y);
      Real'Read (Stream, Fit.RMS_Error);
      Real'Read (Stream, Fit.Scaling_X);
      Real'Read (Stream, Fit.Scaling_Y);
      Real'Read (Stream, Fit.Rotation);
      Real'Read (Stream, Fit.Skew);
   end Read_Fit;

   --  The stream form of a calibration: the stream code, the kind, the
   --  number of points, the calibrated flag, (layouts 1 and 2) the
   --  computation mode, (layout 2) the origin adjustment, DOFsToCompute
   --  and the tile sizes; then the points (an N-point calibration: four
   --  coordinates per pair; a checkerboard calibration with corners: the
   --  image size, then per corner its pixel position, grid indices and
   --  uncalibrated point); then, when calibrated, the computed fit and
   --  (layout 1, and layout 2 in a mode other than the linear one) the
   --  nonlinear model. A calibration is written in the oldest layout that
   --  holds it (KF.Stream_Code: 0 in the linear mode, the form before the
   --  computation modes, 1 in the warp mode, 2 with an origin adjustment
   --  other than the defaults), so that all of them read back; the older
   --  layouts give the default adjustment.

   procedure Write_Calibration
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Calibration_Handle)
   is
      Count, Flag, DOF : Int32;
      Tile_X, Tile_Y   : Real;
      Width, Height    : Int32;
      A, B, Pixel      : Point;
      I, J             : Int32;
      Mode             : constant Int32 := Mode_Of (Item);
      Adjustment       : constant KF.Ks_Calibration_Adjustment :=
        Adjustment_Of (Item);
      Code             : constant Int32 := KF.Stream_Code (Mode, Adjustment);
      Status           : Ks_Status;
   begin
      KF.Calibration_Num_Points (Item.Handle, Count, Status);
      Check (Status);
      KF.Calibration_Calibrated (Item.Handle, Flag, Status);
      Check (Status);
      KF.Calibration_DOFs_To_Compute (Item.Handle, DOF, Status);
      Check (Status);
      KF.Calibration_Physical_Tile_Size (Item.Handle, Tile_X, Tile_Y, Status);
      Check (Status);
      KF.Calibration_Corner_Image_Size (Item.Handle, Width, Height, Status);
      Check (Status);
      Int32'Write (Stream, Code);
      Int32'Write (Stream, Item.Kind);
      Int32'Write (Stream, Count);
      Int32'Write (Stream, Flag);
      if Code /= KF.Calibration_Stream_Code then
         Int32'Write (Stream, Mode);
      end if;
      if Code = KF.Calibration_Stream_Code_2 then
         KF.Ks_Calibration_Adjustment'Write (Stream, Adjustment);
      end if;
      Int32'Write (Stream, DOF);
      Real'Write (Stream, Tile_X);
      Real'Write (Stream, Tile_Y);
      if Item.Kind = KF.Kind_N_Point_To_N_Point then
         for Index in 0 .. Count - 1 loop  --  SHELL: stream I/O
            KF.Calibration_Get_Point
              (Item.Handle, Index, KF.Group_A, A.X, A.Y, Status);
            Check (Status);
            KF.Calibration_Get_Point
              (Item.Handle, Index, KF.Group_B, B.X, B.Y, Status);
            Check (Status);
            Point'Write (Stream, A);
            Point'Write (Stream, B);
         end loop;  --  SHELL: (the loop above)
      elsif Count > 0 then
         Int32'Write (Stream, Width);
         Int32'Write (Stream, Height);
         for Index in 0 .. Count - 1 loop  --  SHELL: stream I/O
            KF.Calibration_Get_Corner
              (Item.Handle, Index, Pixel.X, Pixel.Y, I, J, Status);
            Check (Status);
            KF.Calibration_Get_Point
              (Item.Handle, Index, KF.Group_A, A.X, A.Y, Status);
            Check (Status);
            Point'Write (Stream, Pixel);
            Int32'Write (Stream, I);
            Int32'Write (Stream, J);
            Point'Write (Stream, A);
         end loop;  --  SHELL: (the loop above)
      end if;
      if Flag = AMV.Kernels.True_Value then
         Write_Fit (Stream, Fit_Of (Item));
         if KF.Stream_Has_Model (Code, Mode) then
            KF.Ks_Radial_Warp_Model'Write (Stream, Model_Of (Item));
         end if;
      end if;
   end Write_Calibration;

   procedure Swap (Left, Right : in out Calibration_Handle);

   procedure Swap (Left, Right : in out Calibration_Handle) is
      Left_Handle : constant KF.Ks_Calibration := Left.Handle;
   begin
      Left.Handle := Right.Handle;
      Right.Handle := Left_Handle;
   end Swap;

   procedure Read_Calibration
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Calibration_Handle)
   is
      Fresh                   : Calibration_Handle (Item.Kind);
      Code, Kind, Count, Flag : Int32;
      Mode                    : Int32 := KF.Mode_Linear;
      DOF                     : Int32;
      Tile_X, Tile_Y          : Real;
      Width, Height           : Int32;
      A, B, Pixel             : Point;
      I, J                    : Int32;
      Fit                     : KF.Ks_N_Point_To_N_Point_Fit;
      Model                   : KF.Ks_Radial_Warp_Model;
      Adjustment              : KF.Ks_Calibration_Adjustment :=
        KF.Default_Adjustment;
      Status                  : Ks_Status;
   begin
      Int32'Read (Stream, Code);
      Int32'Read (Stream, Kind);
      Int32'Read (Stream, Count);
      Int32'Read (Stream, Flag);
      KF.Check_Calibration_Header (Code, Kind, Item.Kind, Count, Flag, Status);
      Check (Status);
      if Code /= KF.Calibration_Stream_Code then
         Int32'Read (Stream, Mode);
      end if;
      if Code = KF.Calibration_Stream_Code_2 then
         KF.Ks_Calibration_Adjustment'Read (Stream, Adjustment);
      end if;
      Int32'Read (Stream, DOF);
      Real'Read (Stream, Tile_X);
      Real'Read (Stream, Tile_Y);
      KF.Restore_Settings (Fresh.Handle, DOF, Tile_X, Tile_Y, Status);
      Check (Status);
      KF.Restore_Mode (Fresh.Handle, Mode, Status);
      Check (Status);
      KF.Restore_Adjustment (Fresh.Handle, Adjustment, Status);
      Check (Status);
      --  Fresh owns what has been read, so that a failure frees it and
      --  leaves Item unchanged.
      if Kind = KF.Kind_N_Point_To_N_Point then
         for Index in 1 .. Count loop  --  SHELL: stream I/O
            Point'Read (Stream, A);
            Point'Read (Stream, B);
            KF.Restore_Pair (Fresh.Handle, A.X, A.Y, B.X, B.Y, Status);
            Check (Status);
         end loop;  --  SHELL: (the loop above)
      elsif Count > 0 then
         Int32'Read (Stream, Width);
         Int32'Read (Stream, Height);
         for Index in 1 .. Count loop  --  SHELL: stream I/O
            Point'Read (Stream, Pixel);
            Int32'Read (Stream, I);
            Int32'Read (Stream, J);
            Point'Read (Stream, A);
            KF.Restore_Corner
              (Fresh.Handle, Width, Height, Count, Pixel.X, Pixel.Y, I, J,
               A.X, A.Y, Status);
            Check (Status);
         end loop;  --  SHELL: (the loop above)
      end if;
      if Flag = AMV.Kernels.True_Value then
         Read_Fit (Stream, Fit);
         if KF.Stream_Has_Model (Code, Mode) then
            KF.Ks_Radial_Warp_Model'Read (Stream, Model);
            KF.Restore_Model (Fresh.Handle, Fit, Model, Status);
         else
            KF.Restore_Fit (Fresh.Handle, Fit, Status);
         end if;
         Check (Status);
      end if;
      Swap (Item, Fresh);
   end Read_Calibration;

   function Num_Points (Item : Calibration_Handle) return Natural is
      Count  : Int32;
      Status : Ks_Status;
   begin
      KF.Calibration_Num_Points (Item.Handle, Count, Status);
      Check (Status);
      return Natural (Count);
   end Num_Points;

   function Get
     (Item  : Calibration_Handle;
      Index : Natural;
      Group : Int32) return Point
   is
      Result : Point;
      Status : Ks_Status;
   begin
      KF.Calibration_Get_Point
        (Item.Handle, Int32 (Index), Group, Result.X, Result.Y, Status);
      Check (Status);
      return Result;
   end Get;

   function DOF_Of (Item : Calibration_Handle)
      return Ks_N_Point_To_N_Point_DOF_Constants
   is
      DOF    : Int32;
      Status : Ks_Status;
   begin
      KF.Calibration_DOFs_To_Compute (Item.Handle, DOF, Status);
      Check (Status);
      return To_DOF (DOF);
   end DOF_Of;

   procedure Set_DOF
     (Item  : in out Calibration_Handle;
      Value : Ks_N_Point_To_N_Point_DOF_Constants)
   is
      Status : Ks_Status;
   begin
      KF.Calibration_Set_DOFs_To_Compute (Item.Handle, DOF_Code (Value),
                                          Status);
      Check (Status);
   end Set_DOF;

   function Is_Calibrated (Item : Calibration_Handle) return Boolean is
      Flag   : Int32;
      Status : Ks_Status;
   begin
      KF.Calibration_Calibrated (Item.Handle, Flag, Status);
      Check (Status);
      return Boolean'Val (Flag);
   end Is_Calibrated;

   procedure Forget (Item : in out Calibration_Handle) is
      Status : Ks_Status;
   begin
      KF.Calibration_Uncalibrate (Item.Handle, Status);
      Check (Status);
   end Forget;

   procedure Output_Of
     (Input_Image  : AMV.Images.Ks_Image_8_Grey;
      Output       : KI.Ks_Image_8_Grey;
      Tree         : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
      Selected     : KC.Ks_Space_Name;
      Output_Image : out AMV.Images.Ks_Image_8_Grey);
   --  The output image of a calibration tool's run: the input's pixels
   --  (the linear mode, Output null) or the warped image Output (adopted),
   --  with the new tree and selection.

   procedure Output_Of
     (Input_Image  : AMV.Images.Ks_Image_8_Grey;
      Output       : KI.Ks_Image_8_Grey;
      Tree         : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
      Selected     : KC.Ks_Space_Name;
      Output_Image : out AMV.Images.Ks_Image_8_Grey) is
   begin
      if Output = null then
         Output_Image := With_Spaces (Input_Image, Tree, Selected);
      else
         Output_Image :=
           With_Spaces (Kernel_Images.Adopt (Output, Input_Image), Tree,
                        Selected);
      end if;
   end Output_Of;

   ---------------------------------------------------------------------
   --  CogCalibNPointToNPoint and its tool
   ---------------------------------------------------------------------

   function Num_Points (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Natural
   is (Num_Points (Calibration.Handle));

   procedure Add_Point_Pair
     (Calibration                        : in out Ks_Calib_N_Point_To_N_Point;
      Uncalibrated_X, Uncalibrated_Y     : Real;
      Raw_Calibrated_X, Raw_Calibrated_Y : Real)
   is
      Status : Ks_Status;
   begin
      KF.Calibration_Add_Point_Pair
        (Calibration.Handle.Handle, Uncalibrated_X, Uncalibrated_Y,
         Raw_Calibrated_X, Raw_Calibrated_Y, Status);
      Check (Status);
   end Add_Point_Pair;

   procedure Delete_Point_Pair
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Index       : Natural)
   is
      Status : Ks_Status;
   begin
      KF.Calibration_Delete_Point_Pair
        (Calibration.Handle.Handle, Int32 (Index), Status);
      Check (Status);
   end Delete_Point_Pair;

   procedure Get_Uncalibrated_Point
     (Calibration : Ks_Calib_N_Point_To_N_Point;
      Index       : Natural;
      X, Y        : out Real)
   is
      P : constant Point := Get (Calibration.Handle, Index, KF.Group_A);
   begin
      X := P.X;
      Y := P.Y;
   end Get_Uncalibrated_Point;

   function Get_Uncalibrated_Point_X
     (Calibration : Ks_Calib_N_Point_To_N_Point; Index : Natural) return Real
   is (Get (Calibration.Handle, Index, KF.Group_A).X);

   function Get_Uncalibrated_Point_Y
     (Calibration : Ks_Calib_N_Point_To_N_Point; Index : Natural) return Real
   is (Get (Calibration.Handle, Index, KF.Group_A).Y);

   procedure Set_Point
     (Item  : in out Calibration_Handle;
      Index : Natural;
      Group : Int32;
      X, Y  : Real)
   is
      Status : Ks_Status;
   begin
      KF.Calibration_Set_Point (Item.Handle, Int32 (Index), Group, X, Y,
                                Status);
      Check (Status);
   end Set_Point;

   procedure Set_Uncalibrated_Point
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Index       : Natural;
      X, Y        : Real) is
   begin
      Set_Point (Calibration.Handle, Index, KF.Group_A, X, Y);
   end Set_Uncalibrated_Point;

   procedure Get_Raw_Calibrated_Point
     (Calibration : Ks_Calib_N_Point_To_N_Point;
      Index       : Natural;
      X, Y        : out Real)
   is
      P : constant Point := Get (Calibration.Handle, Index, KF.Group_B);
   begin
      X := P.X;
      Y := P.Y;
   end Get_Raw_Calibrated_Point;

   function Get_Raw_Calibrated_Point_X
     (Calibration : Ks_Calib_N_Point_To_N_Point; Index : Natural) return Real
   is (Get (Calibration.Handle, Index, KF.Group_B).X);

   function Get_Raw_Calibrated_Point_Y
     (Calibration : Ks_Calib_N_Point_To_N_Point; Index : Natural) return Real
   is (Get (Calibration.Handle, Index, KF.Group_B).Y);

   procedure Set_Raw_Calibrated_Point
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Index       : Natural;
      X, Y        : Real) is
   begin
      Set_Point (Calibration.Handle, Index, KF.Group_B, X, Y);
   end Set_Raw_Calibrated_Point;

   function DOFs_To_Compute
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Ks_N_Point_To_N_Point_DOF_Constants
   is (DOF_Of (Calibration.Handle));

   procedure Set_DOFs_To_Compute
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Ks_N_Point_To_N_Point_DOF_Constants) is
   begin
      Set_DOF (Calibration.Handle, Value);
   end Set_DOFs_To_Compute;

   function Computation_Mode (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Ks_Calib_Fix_Computation_Mode_Constants
   is (Ks_Calib_Fix_Computation_Mode_Constants'Enum_Val
         (Mode_Of (Calibration.Handle)));

   procedure Set_Computation_Mode
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Ks_Calib_Fix_Computation_Mode_Constants) is
   begin
      Set_Mode (Calibration.Handle, Value);
   end Set_Computation_Mode;

   procedure Calibrate (Calibration : in out Ks_Calib_N_Point_To_N_Point) is
      Status : Ks_Status;
   begin
      KF.Calibration_Calibrate
        (Calibration.Handle.Handle, null, (others => <>), Status);
      Check (Status);
   end Calibrate;

   procedure Calibrate
     (Calibration       : in out Ks_Calib_N_Point_To_N_Point;
      Calibration_Image : AMV.Images.Ks_Image_8_Grey) is
   begin
      Calibrate_With (Calibration.Handle, Calibration_Image);
   end Calibrate;

   function Calibrated (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Boolean
   is (Is_Calibrated (Calibration.Handle));

   procedure Uncalibrate (Calibration : in out Ks_Calib_N_Point_To_N_Point)
   is
   begin
      Forget (Calibration.Handle);
   end Uncalibrate;

   function Get_Computed_Uncalibrated_From_Calibrated_Transform
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is (Adjusted_Of (Calibration.Handle));

   function Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is (To_Ada (Fit_Of (Calibration.Handle).Transform));

   function Computed_RMS_Error (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Real
   is (Fit_Of (Calibration.Handle).RMS_Error);

   function Calibrated_Origin_X (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Real
   is (Adjustment_Of (Calibration.Handle).Calibrated_Origin_X);

   procedure Set_Calibrated_Origin_X
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Real) is
   begin
      Set_Origin_X (Calibration.Handle, Value);
   end Set_Calibrated_Origin_X;

   function Calibrated_Origin_Y (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Real
   is (Adjustment_Of (Calibration.Handle).Calibrated_Origin_Y);

   procedure Set_Calibrated_Origin_Y
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Real) is
   begin
      Set_Origin_Y (Calibration.Handle, Value);
   end Set_Calibrated_Origin_Y;

   function Calibrated_Origin_Space
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Ks_Calib_N_Point_Adjustment_Space_Constants
   is (To_Space (Adjustment_Of (Calibration.Handle).Calibrated_Origin_Space));

   procedure Set_Calibrated_Origin_Space
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Ks_Calib_N_Point_Adjustment_Space_Constants) is
   begin
      Set_Origin_Space (Calibration.Handle, Value);
   end Set_Calibrated_Origin_Space;

   function Calibrated_X_Axis_Rotation
     (Calibration : Ks_Calib_N_Point_To_N_Point) return Real
   is (Adjustment_Of (Calibration.Handle).Calibrated_X_Axis_Rotation);

   procedure Set_Calibrated_X_Axis_Rotation
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Real) is
   begin
      Set_Rotation (Calibration.Handle, Value);
   end Set_Calibrated_X_Axis_Rotation;

   function Calibrated_X_Axis_Rotation_Space
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Ks_Calib_N_Point_Adjustment_Space_Constants
   is (To_Space (Adjustment_Of (Calibration.Handle)
                   .Calibrated_X_Axis_Rotation_Space));

   procedure Set_Calibrated_X_Axis_Rotation_Space
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Ks_Calib_N_Point_Adjustment_Space_Constants) is
   begin
      Set_Rotation_Space (Calibration.Handle, Value);
   end Set_Calibrated_X_Axis_Rotation_Space;

   function Swap_Calibrated_Handedness
     (Calibration : Ks_Calib_N_Point_To_N_Point) return Boolean
   is (Boolean'Val (Adjustment_Of (Calibration.Handle)
                      .Swap_Calibrated_Handedness));

   procedure Set_Swap_Calibrated_Handedness
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      Value       : Boolean) is
   begin
      Set_Swap (Calibration.Handle, Value);
   end Set_Swap_Calibrated_Handedness;

   function Get_Computed_Warp_Model
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return Ks_Calib_N_Point_To_N_Point_Warp_Model
   is (Model_Of (Calibration.Handle));

   function Get_Output_Pixel_From_Calibrated_Transform
     (Calibration : Ks_Calib_N_Point_To_N_Point)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is (To_Ada (Model_Of (Calibration.Handle).Output_Pixel_From_Calibrated));

   procedure Map_Output_Pixel
     (Calibration      : Ks_Calib_N_Point_To_N_Point;
      Output_X         : Real;
      Output_Y         : Real;
      Input_X, Input_Y : out Real;
      Inside           : out Boolean) is
   begin
      Map_Output (Calibration.Handle, Output_X, Output_Y, Input_X, Input_Y,
                  Inside);
   end Map_Output_Pixel;

   procedure Map_Input_Pixel
     (Calibration        : Ks_Calib_N_Point_To_N_Point;
      Input_X            : Real;
      Input_Y            : Real;
      Output_X, Output_Y : out Real;
      Inside             : out Boolean) is
   begin
      Map_Input (Calibration.Handle, Input_X, Input_Y, Output_X, Output_Y,
                 Inside);
   end Map_Input_Pixel;

   overriding procedure Execute
     (Tool : in out Ks_Calib_N_Point_To_N_Point_Tool)
   is
      Tree     : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree :=
        Tool.Input_Image.Get_Coordinate_Space_Tree;
      Selected : KC.Ks_Space_Name := Selection_Of (Tool.Input_Image);
      Output   : KI.Ks_Image_8_Grey;
      Status   : Ks_Status;
   begin
      KF.Calibration_N_Point_Tool_Execute
        (Kernel_Images.Kernel_Handle (Tool.Input_Image),
         Tool.Calibration.Handle.Handle,
         (Calibrated_Space_Name =>
            Name_Of (Tool.Run_Params.Calibrated_Space_Name),
          Space_To_Output       =>
            Ks_Calib_Space_To_Output_Constants'Pos
              (Tool.Run_Params.Space_To_Output)),
         Kernel_Trees.Variable_View (Tree).all, Selected,
         Pixel_From_Root (Tool.Input_Image), Output, Status);
      Check (Status);
      Output_Of (Tool.Input_Image, Output, Tree, Selected, Tool.Output_Image);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Calib_N_Point_To_N_Point_Tool)
   is
      Unallocated : AMV.Images.Ks_Image_8_Grey;
   begin
      Tool.Output_Image := Unallocated;
   end Reset_Results;

   ---------------------------------------------------------------------
   --  CogCalibCheckerboard and its tool
   ---------------------------------------------------------------------

   function Calibration_Image (Calibration : Ks_Calib_Checkerboard)
      return AMV.Images.Ks_Image_8_Grey
   is (Calibration.Image);

   procedure Set_Calibration_Image
     (Calibration : in out Ks_Calib_Checkerboard;
      Image       : AMV.Images.Ks_Image_8_Grey) is
   begin
      Forget (Calibration.Handle);
      Calibration.Image := Image;
   end Set_Calibration_Image;

   procedure Tile_Sizes
     (Calibration : Ks_Calib_Checkerboard;
      X, Y        : out Real);

   procedure Tile_Sizes
     (Calibration : Ks_Calib_Checkerboard;
      X, Y        : out Real)
   is
      Status : Ks_Status;
   begin
      KF.Calibration_Physical_Tile_Size
        (Calibration.Handle.Handle, X, Y, Status);
      Check (Status);
   end Tile_Sizes;

   function Physical_Tile_Size_X (Calibration : Ks_Calib_Checkerboard)
      return Real
   is
      X, Y : Real;
   begin
      Tile_Sizes (Calibration, X, Y);
      return X;
   end Physical_Tile_Size_X;

   function Physical_Tile_Size_Y (Calibration : Ks_Calib_Checkerboard)
      return Real
   is
      X, Y : Real;
   begin
      Tile_Sizes (Calibration, X, Y);
      return Y;
   end Physical_Tile_Size_Y;

   procedure Set_Physical_Tile_Size_X
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Real)
   is
      Status : Ks_Status;
   begin
      KF.Calibration_Set_Physical_Tile_Size
        (Calibration.Handle.Handle, Value,
         Physical_Tile_Size_Y (Calibration), Status);
      Check (Status);
   end Set_Physical_Tile_Size_X;

   procedure Set_Physical_Tile_Size_Y
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Real)
   is
      Status : Ks_Status;
   begin
      KF.Calibration_Set_Physical_Tile_Size
        (Calibration.Handle.Handle, Physical_Tile_Size_X (Calibration),
         Value, Status);
      Check (Status);
   end Set_Physical_Tile_Size_Y;

   function DOFs_To_Compute (Calibration : Ks_Calib_Checkerboard)
      return Ks_Calib_Checkerboard_DOF_Constants
   is (DOF_Of (Calibration.Handle));

   procedure Set_DOFs_To_Compute
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Ks_Calib_Checkerboard_DOF_Constants) is
   begin
      Set_DOF (Calibration.Handle, Value);
   end Set_DOFs_To_Compute;

   function Computation_Mode (Calibration : Ks_Calib_Checkerboard)
      return Ks_Calib_Fix_Computation_Mode_Constants
   is (Ks_Calib_Fix_Computation_Mode_Constants'Enum_Val
         (Mode_Of (Calibration.Handle)));

   procedure Set_Computation_Mode
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Ks_Calib_Fix_Computation_Mode_Constants) is
   begin
      Set_Mode (Calibration.Handle, Value);
   end Set_Computation_Mode;

   procedure Calibrate (Calibration : in out Ks_Calib_Checkerboard) is
   begin
      Calibrate_With (Calibration.Handle, Calibration.Image);
   end Calibrate;

   function Calibrated (Calibration : Ks_Calib_Checkerboard) return Boolean
   is (Is_Calibrated (Calibration.Handle));

   procedure Uncalibrate (Calibration : in out Ks_Calib_Checkerboard) is
   begin
      Forget (Calibration.Handle);
   end Uncalibrate;

   function Num_Points (Calibration : Ks_Calib_Checkerboard) return Natural
   is (Num_Points (Calibration.Handle));

   procedure Get_Uncalibrated_Point
     (Calibration : Ks_Calib_Checkerboard;
      Index       : Natural;
      X, Y        : out Real)
   is
      P : constant Point := Get (Calibration.Handle, Index, KF.Group_A);
   begin
      X := P.X;
      Y := P.Y;
   end Get_Uncalibrated_Point;

   function Get_Uncalibrated_Point_X
     (Calibration : Ks_Calib_Checkerboard; Index : Natural) return Real
   is (Get (Calibration.Handle, Index, KF.Group_A).X);

   function Get_Uncalibrated_Point_Y
     (Calibration : Ks_Calib_Checkerboard; Index : Natural) return Real
   is (Get (Calibration.Handle, Index, KF.Group_A).Y);

   procedure Get_Raw_Calibrated_Point
     (Calibration : Ks_Calib_Checkerboard;
      Index       : Natural;
      X, Y        : out Real)
   is
      P : constant Point := Get (Calibration.Handle, Index, KF.Group_B);
   begin
      X := P.X;
      Y := P.Y;
   end Get_Raw_Calibrated_Point;

   function Get_Raw_Calibrated_Point_X
     (Calibration : Ks_Calib_Checkerboard; Index : Natural) return Real
   is (Get (Calibration.Handle, Index, KF.Group_B).X);

   function Get_Raw_Calibrated_Point_Y
     (Calibration : Ks_Calib_Checkerboard; Index : Natural) return Real
   is (Get (Calibration.Handle, Index, KF.Group_B).Y);

   procedure Get_Corner
     (Calibration      : Ks_Calib_Checkerboard;
      Index            : Natural;
      Pixel_X, Pixel_Y : out Real;
      Grid_I, Grid_J   : out Integer)
   is
      I, J   : Int32;
      Status : Ks_Status;
   begin
      KF.Calibration_Get_Corner
        (Calibration.Handle.Handle, Int32 (Index), Pixel_X, Pixel_Y, I, J,
         Status);
      Check (Status);
      Grid_I := Integer (I);
      Grid_J := Integer (J);
   end Get_Corner;

   function Get_Computed_Uncalibrated_From_Calibrated_Transform
     (Calibration : Ks_Calib_Checkerboard)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is (Adjusted_Of (Calibration.Handle));

   function Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform
     (Calibration : Ks_Calib_Checkerboard)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is (To_Ada (Fit_Of (Calibration.Handle).Transform));

   function Computed_RMS_Error (Calibration : Ks_Calib_Checkerboard)
      return Real
   is (Fit_Of (Calibration.Handle).RMS_Error);

   function Calibrated_Origin_X (Calibration : Ks_Calib_Checkerboard)
      return Real
   is (Adjustment_Of (Calibration.Handle).Calibrated_Origin_X);

   procedure Set_Calibrated_Origin_X
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Real) is
   begin
      Set_Origin_X (Calibration.Handle, Value);
   end Set_Calibrated_Origin_X;

   function Calibrated_Origin_Y (Calibration : Ks_Calib_Checkerboard)
      return Real
   is (Adjustment_Of (Calibration.Handle).Calibrated_Origin_Y);

   procedure Set_Calibrated_Origin_Y
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Real) is
   begin
      Set_Origin_Y (Calibration.Handle, Value);
   end Set_Calibrated_Origin_Y;

   function Calibrated_Origin_Space
     (Calibration : Ks_Calib_Checkerboard)
      return Ks_Calib_Checkerboard_Adjustment_Space_Constants
   is (To_Space (Adjustment_Of (Calibration.Handle).Calibrated_Origin_Space));

   procedure Set_Calibrated_Origin_Space
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Ks_Calib_Checkerboard_Adjustment_Space_Constants) is
   begin
      Set_Origin_Space (Calibration.Handle, Value);
   end Set_Calibrated_Origin_Space;

   function Calibrated_X_Axis_Rotation
     (Calibration : Ks_Calib_Checkerboard) return Real
   is (Adjustment_Of (Calibration.Handle).Calibrated_X_Axis_Rotation);

   procedure Set_Calibrated_X_Axis_Rotation
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Real) is
   begin
      Set_Rotation (Calibration.Handle, Value);
   end Set_Calibrated_X_Axis_Rotation;

   function Calibrated_X_Axis_Rotation_Space
     (Calibration : Ks_Calib_Checkerboard)
      return Ks_Calib_Checkerboard_Adjustment_Space_Constants
   is (To_Space (Adjustment_Of (Calibration.Handle)
                   .Calibrated_X_Axis_Rotation_Space));

   procedure Set_Calibrated_X_Axis_Rotation_Space
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Ks_Calib_Checkerboard_Adjustment_Space_Constants) is
   begin
      Set_Rotation_Space (Calibration.Handle, Value);
   end Set_Calibrated_X_Axis_Rotation_Space;

   function Swap_Calibrated_Handedness
     (Calibration : Ks_Calib_Checkerboard) return Boolean
   is (Boolean'Val (Adjustment_Of (Calibration.Handle)
                      .Swap_Calibrated_Handedness));

   procedure Set_Swap_Calibrated_Handedness
     (Calibration : in out Ks_Calib_Checkerboard;
      Value       : Boolean) is
   begin
      Set_Swap (Calibration.Handle, Value);
   end Set_Swap_Calibrated_Handedness;

   function Get_Computed_Warp_Model (Calibration : Ks_Calib_Checkerboard)
      return Ks_Calib_Checkerboard_Warp_Model
   is (Model_Of (Calibration.Handle));

   function Get_Output_Pixel_From_Calibrated_Transform
     (Calibration : Ks_Calib_Checkerboard)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is (To_Ada (Model_Of (Calibration.Handle).Output_Pixel_From_Calibrated));

   procedure Map_Output_Pixel
     (Calibration      : Ks_Calib_Checkerboard;
      Output_X         : Real;
      Output_Y         : Real;
      Input_X, Input_Y : out Real;
      Inside           : out Boolean) is
   begin
      Map_Output (Calibration.Handle, Output_X, Output_Y, Input_X, Input_Y,
                  Inside);
   end Map_Output_Pixel;

   procedure Map_Input_Pixel
     (Calibration        : Ks_Calib_Checkerboard;
      Input_X            : Real;
      Input_Y            : Real;
      Output_X, Output_Y : out Real;
      Inside             : out Boolean) is
   begin
      Map_Input (Calibration.Handle, Input_X, Input_Y, Output_X, Output_Y,
                 Inside);
   end Map_Input_Pixel;

   overriding procedure Execute (Tool : in out Ks_Calib_Checkerboard_Tool) is
      Tree     : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree :=
        Tool.Input_Image.Get_Coordinate_Space_Tree;
      Selected : KC.Ks_Space_Name := Selection_Of (Tool.Input_Image);
      Output   : KI.Ks_Image_8_Grey;
      Status   : Ks_Status;
   begin
      KF.Calibration_Checkerboard_Tool_Execute
        (Kernel_Images.Kernel_Handle (Tool.Input_Image),
         Tool.Calibration.Handle.Handle,
         (Calibrated_Space_Name      =>
            Name_Of (Tool.Run_Params.Calibrated_Space_Name),
          Space_To_Output            =>
            Ks_Calib_Space_To_Output_Constants'Pos
              (Tool.Run_Params.Space_To_Output),
          Unfilled_Pel_Value         =>
            Int32 (Tool.Run_Params.Unfilled_Pel_Value),
          Unfilled_Pel_Value_Enabled =>
            Boolean'Pos (Tool.Run_Params.Unfilled_Pel_Value_Enabled)),
         Kernel_Trees.Variable_View (Tree).all, Selected,
         Pixel_From_Root (Tool.Input_Image), Output, Status);
      Check (Status);
      Output_Of (Tool.Input_Image, Output, Tree, Selected, Tool.Output_Image);
   end Execute;

   overriding procedure Reset_Results
     (Tool : in out Ks_Calib_Checkerboard_Tool)
   is
      Unallocated : AMV.Images.Ks_Image_8_Grey;
   begin
      Tool.Output_Image := Unallocated;
   end Reset_Results;


   ---------------------------------------------------------------------
   --  Stream attributes of the public records (see the private part)
   ---------------------------------------------------------------------

   procedure Read_N_Point
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_N_Point_To_N_Point)
   is
      Fresh : Ks_N_Point_To_N_Point;
   begin
      Point_Pairs'Read (Stream, Fresh.Pairs);
      Ks_N_Point_To_N_Point_DOF_Constants'Read
        (Stream, Fresh.DOFs_To_Compute);
      AMV.Checks.Check_Read (Fresh.DOFs_To_Compute'Valid,
                             "Ks_N_Point_To_N_Point'Read");
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_N_Point_To_N_Point'Read");
   end Read_N_Point;

   procedure Read_Fixture
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Fixture_N_Point_To_N_Point)
   is
      Fresh : Ks_Fixture_N_Point_To_N_Point;
   begin
      Point_Pairs'Read (Stream, Fresh.Pairs);
      Ks_N_Point_To_N_Point_DOF_Constants'Read
        (Stream, Fresh.DOFs_To_Compute);
      Ada.Strings.Unbounded.Unbounded_String'Read
        (Stream, Fresh.Fixtured_Space_Name);
      Ks_Fixture_Space_To_Output_Constants'Read
        (Stream, Fresh.Space_To_Output);
      Ks_Fixtured_Space_Name_Duplicate_Handling_Constants'Read
        (Stream, Fresh.Fixtured_Space_Name_Duplicate_Handling);
      AMV.Checks.Check_Read
        (Fresh.DOFs_To_Compute'Valid
         and then Fresh.Space_To_Output'Valid
         and then Fresh.Fixtured_Space_Name_Duplicate_Handling'Valid,
         "Ks_Fixture_N_Point_To_N_Point'Read");
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Fixture_N_Point_To_N_Point'Read");
   end Read_Fixture;

   procedure Read_Fixture_Result
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Fixture_N_Point_To_N_Point_Result)
   is
      Fresh : Ks_Fixture_N_Point_To_N_Point_Result;
   begin
      AMV.Images.Ks_Image_8_Grey'Read (Stream, Fresh.Output_Image);
      AMV.Transforms.Ks_Transform_2D_Linear'Read (Stream, Fresh.Transform);
      Real'Read (Stream, Fresh.RMS_Error);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Fixture_N_Point_To_N_Point_Result'Read");
   end Read_Fixture_Result;

   procedure Read_Calib_N_Point
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Calib_N_Point_To_N_Point)
   is
      Fresh : Ks_Calib_N_Point_To_N_Point;
   begin
      Calibration_Handle'Read (Stream, Fresh.Handle);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Calib_N_Point_To_N_Point'Read");
   end Read_Calib_N_Point;

   procedure Read_Calib_Checkerboard
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Calib_Checkerboard)
   is
      Fresh : Ks_Calib_Checkerboard;
   begin
      AMV.Images.Ks_Image_8_Grey'Read (Stream, Fresh.Image);
      Calibration_Handle'Read (Stream, Fresh.Handle);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Calib_Checkerboard'Read");
   end Read_Calib_Checkerboard;

end AMV.Calib_Fix;
