pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.IO_Exceptions;
with Ada.Tags;
with Interfaces;

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Images;
with AMV.Kernels.Transforms;
with AMV.Regions;
with AMV.Regions.Kernel_Regions;

package body AMV.PM_Align is

   package KI renames AMV.Kernels.Images;
   package KT renames AMV.Kernels.Transforms;
   package Kernel_Images renames AMV.Images.Kernel_Images;
   package Kernel_Regions renames AMV.Regions.Kernel_Regions;

   subtype Ks_Status is AMV.Kernels.Ks_Status;
   subtype U32 is Interfaces.Unsigned_32;

   use type AMV.Kernels.Int32;
   use type KP.Ks_PM_Align_Pattern;

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
   --  The kernel's pattern handle
   ---------------------------------------------------------------------

   overriding procedure Adjust (Item : in out Pattern_Handle) is
      Source : constant KP.Ks_PM_Align_Pattern := Item.Handle;
      Status : Ks_Status;
   begin
      --  The copy shares the source's handle until it has its own; it
      --  must not keep it if the duplicate cannot be made.
      Item.Handle := null;
      KP.Pattern_Duplicate (Source, Item.Handle, Status);
      Check (Status);
   end Adjust;

   overriding procedure Finalize (Item : in out Pattern_Handle) is
   begin
      KP.Pattern_Destroy (Item.Handle);
   end Finalize;

   procedure Ensure (Item : in out Pattern_Handle);
   --  Gives Item a handle of its own when it has none yet.

   procedure Ensure (Item : in out Pattern_Handle) is
      Status : Ks_Status;
   begin
      if Item.Handle = null then
         KP.Pattern_Create (Item.Handle, Status);
         Check (Status);
      end if;
   end Ensure;

   procedure Swap (Left, Right : in out Pattern_Handle);
   --  Exchanges the handles, masks and mask offsets of Left and Right.

   procedure Swap (Left, Right : in out Pattern_Handle) is
      Left_Handle : constant KP.Ks_PM_Align_Pattern := Left.Handle;
      Left_Mask   : constant AMV.Images.Ks_Image_8_Grey := Left.Mask;
      Left_X      : constant Integer := Left.Mask_Offset_X;
      Left_Y      : constant Integer := Left.Mask_Offset_Y;
   begin
      Left.Handle := Right.Handle;
      Right.Handle := Left_Handle;
      Left.Mask := Right.Mask;
      Right.Mask := Left_Mask;
      Left.Mask_Offset_X := Right.Mask_Offset_X;
      Right.Mask_Offset_X := Left_X;
      Left.Mask_Offset_Y := Right.Mask_Offset_Y;
      Right.Mask_Offset_Y := Left_Y;
   end Swap;

   procedure Write_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Pattern_Handle)
   is
      Params           : KP.Ks_PM_Align_Train_Params;
      Trained          : Int32;
      Finest, Coarsest : Int32;
      First, Last      : Int32;
      Count            : Int32;
      Spacing          : U32;
      Feature          : KP.Ks_PM_Align_Feature;
      X, Y             : Real;
      Status           : Ks_Status;
   begin
      KP.Pattern_Get_Train_Params (Item.Handle, Params, Status);
      Check (Status);
      KP.Write_Levels (Item.Handle, Trained, Finest, Coarsest, First, Last,
                       Status);
      Check (Status);
      U32'Write (Stream, KP.Stream_Code_Masked);
      Int32'Write (Stream, Params.Train_Algorithm);
      Int32'Write (Stream, Params.Grain_Limit_Auto_Select);
      Int32'Write (Stream, Params.Ignore_Polarity);
      Real'Write (Stream, Params.Grain_Limit_Coarse);
      Real'Write (Stream, Params.Grain_Limit_Fine);
      Int32'Write (Stream, Trained);
      Int32'Write (Stream, Finest);
      Int32'Write (Stream, Coarsest);
      for Level in First .. Last loop  --  SHELL: stream I/O, every level
         KP.Level_Spacing (Item.Handle, Level, Spacing, Status);
         Check (Status);
         U32'Write (Stream, Spacing);
         KP.Pattern_Feature_Count (Item.Handle, Level, Count, Status);
         Check (Status);
         U32'Write (Stream, U32 (Count));
         for Index in 1 .. Count loop  --  SHELL: stream I/O, every feature
            KP.Pattern_Feature
              (Item.Handle, Level,
               Index - 1,  --  SHELL: 0-based index
               Feature, Status);
            Check (Status);
            Real'Write (Stream, Feature.X);
            Real'Write (Stream, Feature.Y);
            Real'Write (Stream, Feature.Normal_X);
            Real'Write (Stream, Feature.Normal_Y);
         end loop;  --  SHELL: (the loop above)
         KP.Level_Ignored (Item.Handle, Level, Spacing, Count, Status);
         Check (Status);
         U32'Write (Stream, Spacing);
         U32'Write (Stream, U32 (Count));
         for Index in 1 .. Count loop  --  SHELL: stream I/O, every point
            KP.Pattern_Ignored_Point
              (Item.Handle, Level,
               Index - 1,  --  SHELL: 0-based index
               X, Y, Status);
            Check (Status);
            Real'Write (Stream, X);
            Real'Write (Stream, Y);
         end loop;  --  SHELL: (the loop above)
      end loop;  --  SHELL: (the loop above)
      AMV.Images.Ks_Image_8_Grey'Write (Stream, Item.Mask);
      Integer'Write (Stream, Item.Mask_Offset_X);
      Integer'Write (Stream, Item.Mask_Offset_Y);
   end Write_Handle;

   procedure Read_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Pattern_Handle)
   is
      Fresh            : Pattern_Handle;
      Code             : U32;
      Params           : KP.Ks_PM_Align_Train_Params;
      Trained          : Int32;
      Finest, Coarsest : Int32;
      First, Last      : Int32;
      Count            : U32;
      Spacing          : U32;
      X, Y, NX, NY     : Real;
      Masked           : Boolean;
      Status           : Ks_Status;
   begin
      U32'Read (Stream, Code);
      KP.Check_Read_Code (Code, Status);
      Check (Status);
      Masked := Interfaces."=" (Code, KP.Stream_Code_Masked);
      Int32'Read (Stream, Params.Train_Algorithm);
      Int32'Read (Stream, Params.Grain_Limit_Auto_Select);
      Int32'Read (Stream, Params.Ignore_Polarity);
      Real'Read (Stream, Params.Grain_Limit_Coarse);
      Real'Read (Stream, Params.Grain_Limit_Fine);
      Int32'Read (Stream, Trained);
      Int32'Read (Stream, Finest);
      Int32'Read (Stream, Coarsest);
      --  Fresh owns the model read so far, so that a failure frees it and
      --  leaves Item as it was.
      Ensure (Fresh);
      KP.Read_Start (Fresh.Handle, Params, Trained, Finest, Coarsest, First,
                     Last, Status);
      Check (Status);
      for Level in First .. Last loop  --  SHELL: stream I/O, every level
         U32'Read (Stream, Spacing);
         KP.Read_Spacing (Fresh.Handle, Level, Spacing, Status);
         Check (Status);
         U32'Read (Stream, Count);
         KP.Check_Read_Count (Count, Status);
         Check (Status);
         for Index in 1 .. Count loop  --  SHELL: stream I/O, every feature
            Real'Read (Stream, X);
            Real'Read (Stream, Y);
            Real'Read (Stream, NX);
            Real'Read (Stream, NY);
            KP.Read_Feature (Fresh.Handle, Level, X, Y, NX, NY, Status);
            Check (Status);
         end loop;  --  SHELL: (the loop above)
         if Masked then
            U32'Read (Stream, Spacing);
            KP.Read_Ignored_Spacing (Fresh.Handle, Level, Spacing, Status);
            Check (Status);
            U32'Read (Stream, Count);
            KP.Check_Read_Ignored_Count (Count, Status);
            Check (Status);
            for Index in 1 .. Count loop  --  SHELL: stream I/O, every point
               Real'Read (Stream, X);
               Real'Read (Stream, Y);
               KP.Read_Ignored (Fresh.Handle, Level, X, Y, Status);
               Check (Status);
            end loop;  --  SHELL: (the loop above)
         end if;
      end loop;  --  SHELL: (the loop above)
      KP.Read_Finish (Fresh.Handle, Trained, Status);
      Check (Status);
      if Masked then
         AMV.Images.Ks_Image_8_Grey'Read (Stream, Fresh.Mask);
         Integer'Read (Stream, Fresh.Mask_Offset_X);
         Integer'Read (Stream, Fresh.Mask_Offset_Y);
      end if;
      --  Item takes the pattern read; Fresh frees the old one.
      Swap (Item, Fresh);
   exception
      when others =>
         --  Read_Pattern discards the fresh pattern this handle belongs
         --  to; untraining it keeps the handle consistent all the same.
         KP.Pattern_Untrain (Item.Handle, Status);
         raise;
   end Read_Handle;

   ---------------------------------------------------------------------
   --  The pattern
   ---------------------------------------------------------------------

   procedure Read_Pattern
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_PM_Align_Pattern)
   is
      Fresh : Ks_PM_Align_Pattern;
   begin
      AMV.Images.Ks_Image_8_Grey'Read (Stream, Fresh.Train_Image);
      AMV.Shapes.Region_Holders.Holder'Read (Stream, Fresh.Train_Region);
      AMV.Transforms.Ks_Transform_2D_Linear'Read (Stream, Fresh.Origin);
      Pattern_Handle'Read (Stream, Fresh.Model);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Ada.Tags.Tag_Error
         | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_PM_Align_Pattern'Read");
   end Read_Pattern;

   function Params_Of
     (Pattern : Ks_PM_Align_Pattern) return KP.Ks_PM_Align_Train_Params;
   --  The pattern's train parameters.

   function Params_Of
     (Pattern : Ks_PM_Align_Pattern) return KP.Ks_PM_Align_Train_Params
   is
      Status : Ks_Status;
   begin
      return Params : KP.Ks_PM_Align_Train_Params do
         KP.Pattern_Get_Train_Params (Pattern.Model.Handle, Params, Status);
         Check (Status);
      end return;
   end Params_Of;

   procedure Set_Params
     (Pattern : in out Ks_PM_Align_Pattern;
      Params  : KP.Ks_PM_Align_Train_Params);
   --  Stores the train parameters (checked by the kernel) and untrains.

   procedure Set_Params
     (Pattern : in out Ks_PM_Align_Pattern;
      Params  : KP.Ks_PM_Align_Train_Params)
   is
      Status : Ks_Status;
   begin
      Ensure (Pattern.Model);
      KP.Pattern_Set_Train_Params (Pattern.Model.Handle, Params, Status);
      Check (Status);
   end Set_Params;

   function Train_Image
     (Pattern : Ks_PM_Align_Pattern) return AMV.Images.Ks_Image_8_Grey
   is (Pattern.Train_Image);

   procedure Set_Train_Image
     (Pattern : in out Ks_PM_Align_Pattern;
      Image   : AMV.Images.Ks_Image_8_Grey) is
   begin
      Pattern.Train_Image := Image;
      Pattern.Untrain;
   end Set_Train_Image;

   function Train_Image_Mask
     (Pattern : Ks_PM_Align_Pattern) return AMV.Images.Ks_Image_8_Grey
   is (Pattern.Model.Mask);

   procedure Set_Train_Image_Mask
     (Pattern : in out Ks_PM_Align_Pattern;
      Mask    : AMV.Images.Ks_Image_8_Grey) is
   begin
      Pattern.Model.Mask := Mask;
      Pattern.Untrain;
   end Set_Train_Image_Mask;

   function Train_Image_Mask_Offset_X
     (Pattern : Ks_PM_Align_Pattern) return Integer
   is (Pattern.Model.Mask_Offset_X);

   procedure Set_Train_Image_Mask_Offset_X
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Integer) is
   begin
      Pattern.Model.Mask_Offset_X := Value;
      Pattern.Untrain;
   end Set_Train_Image_Mask_Offset_X;

   function Train_Image_Mask_Offset_Y
     (Pattern : Ks_PM_Align_Pattern) return Integer
   is (Pattern.Model.Mask_Offset_Y);

   procedure Set_Train_Image_Mask_Offset_Y
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Integer) is
   begin
      Pattern.Model.Mask_Offset_Y := Value;
      Pattern.Untrain;
   end Set_Train_Image_Mask_Offset_Y;

   function Train_Region
     (Pattern : Ks_PM_Align_Pattern)
      return AMV.Shapes.Region_Holders.Holder
   is (Pattern.Train_Region);

   procedure Set_Train_Region
     (Pattern : in out Ks_PM_Align_Pattern;
      Region  : AMV.Shapes.Region_Holders.Holder) is
   begin
      Pattern.Train_Region := Region;
      Pattern.Untrain;
   end Set_Train_Region;

   function Origin
     (Pattern : Ks_PM_Align_Pattern)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is (Pattern.Origin);

   procedure Set_Origin
     (Pattern : in out Ks_PM_Align_Pattern;
      Origin  : AMV.Transforms.Ks_Transform_2D_Linear) is
   begin
      Pattern.Origin := Origin;
      Pattern.Untrain;
   end Set_Origin;

   function Train_Algorithm
     (Pattern : Ks_PM_Align_Pattern)
      return Ks_PM_Align_Train_Algorithm_Constants
   is (Train_Algorithm (Params_Of (Pattern).Train_Algorithm));

   procedure Set_Train_Algorithm
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Ks_PM_Align_Train_Algorithm_Constants) is
   begin
      Set_Params (Pattern, (Params_Of (Pattern) with delta
                              Train_Algorithm => Code (Value)));
   end Set_Train_Algorithm;

   function Grain_Limit_Auto_Select
     (Pattern : Ks_PM_Align_Pattern) return Boolean
   is (Params_Of (Pattern).Grain_Limit_Auto_Select = AMV.Kernels.True_Value);

   procedure Set_Grain_Limit_Auto_Select
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Boolean) is
   begin
      Set_Params (Pattern, (Params_Of (Pattern) with delta
                              Grain_Limit_Auto_Select => Boolean'Pos (Value)));
   end Set_Grain_Limit_Auto_Select;

   function Grain_Limit_Coarse (Pattern : Ks_PM_Align_Pattern) return Real is
     (Params_Of (Pattern).Grain_Limit_Coarse);

   procedure Set_Grain_Limit_Coarse
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Real) is
   begin
      Set_Params (Pattern, (Params_Of (Pattern) with delta
                              Grain_Limit_Coarse => Value));
   end Set_Grain_Limit_Coarse;

   function Grain_Limit_Fine (Pattern : Ks_PM_Align_Pattern) return Real is
     (Params_Of (Pattern).Grain_Limit_Fine);

   procedure Set_Grain_Limit_Fine
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Real) is
   begin
      Set_Params (Pattern, (Params_Of (Pattern) with delta
                              Grain_Limit_Fine => Value));
   end Set_Grain_Limit_Fine;

   function Ignore_Polarity (Pattern : Ks_PM_Align_Pattern) return Boolean
   is (Params_Of (Pattern).Ignore_Polarity = AMV.Kernels.True_Value);

   procedure Set_Ignore_Polarity
     (Pattern : in out Ks_PM_Align_Pattern;
      Value   : Boolean) is
   begin
      Set_Params (Pattern, (Params_Of (Pattern) with delta
                              Ignore_Polarity => Boolean'Pos (Value)));
   end Set_Ignore_Polarity;

   procedure Train (Pattern : in out Ks_PM_Align_Pattern) is
      Image  : constant access constant KI.Ks_Image_8_Grey_Data :=
        Kernel_Images.Kernel_Handle (Pattern.Train_Image);
      Status : Ks_Status;
   begin
      Ensure (Pattern.Model);
      KP.Pattern_Untrain (Pattern.Model.Handle, Status);
      Check (Status);
      --  A missing image first, then the region (AMV.Regions checks it in
      --  the image's spaces), then the kernel's checks.
      KP.Check_Train_Image (Image, Status);
      Check (Status);
      declare
         Region : constant AMV.Regions.Pixel_Region :=
           AMV.Regions.Rasterize (Pattern.Train_Image, Pattern.Train_Region);
      begin
         KP.Pattern_Train_Masked
           (Pattern.Model.Handle, Image, Kernel_Regions.Kernel_Handle (Region),
            To_Kernel
              (Pattern.Train_Image.Get_Transform
                 (AMV.Coordinate_Spaces.Selected_Space_Name,
                  AMV.Coordinate_Spaces.Pixel_Space_Name)),
            To_Kernel (Pattern.Origin),
            Kernel_Images.Kernel_Handle (Pattern.Model.Mask),
            Int32 (Pattern.Model.Mask_Offset_X),
            Int32 (Pattern.Model.Mask_Offset_Y), Status);
      end;
      Check (Status);
   end Train;

   function Trained (Pattern : Ks_PM_Align_Pattern) return Boolean is
      Result : Int32;
      Status : Ks_Status;
   begin
      KP.Pattern_Trained (Pattern.Model.Handle, Result, Status);
      Check (Status);
      return Result = AMV.Kernels.True_Value;
   end Trained;

   procedure Untrain (Pattern : in out Ks_PM_Align_Pattern) is
      Status : Ks_Status;
   begin
      KP.Pattern_Untrain (Pattern.Model.Handle, Status);
      Check (Status);
   end Untrain;

   function Get_Trained_Features
     (Pattern : Ks_PM_Align_Pattern;
      Fine    : Boolean := True) return Ks_PM_Align_Feature_Array
   is
      Finest, Coarsest : Int32;
      Count            : Int32;
      Status           : Ks_Status;
   begin
      KP.Pattern_Levels (Pattern.Model.Handle, Finest, Coarsest, Status);
      Check (Status);
      declare
         Level : constant Int32 := (if Fine then Finest else Coarsest);
      begin
         KP.Pattern_Feature_Count (Pattern.Model.Handle, Level, Count,
                                   Status);
         Check (Status);
         return Result : Ks_PM_Align_Feature_Array
           (0 .. Natural (Count) - 1)  --  SHELL: 0-based bounds
         do
            KP.Get_Features (Pattern.Model.Handle, Level, Result, Status);
            Check (Status);
         end return;
      end;
   end Get_Trained_Features;

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   procedure Destroy (Handle : in out KP.Ks_PM_Align_Results) is
   begin
      KP.Results_Destroy (Handle);
   end Destroy;

   function Get_Pose
     (Result : Ks_PM_Align_Result)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is
      Pose   : KT.Ks_Transform_2D_Linear;
      Status : Ks_Status;
   begin
      KP.Result_Get_Pose (Result, Pose, Status);
      Check (Status);
      return AMV.Transforms.Create
        (Pose.A, Pose.B, Pose.C, Pose.D, Pose.Translation_X,
         Pose.Translation_Y);
   end Get_Pose;

   function Count (Results : Ks_PM_Align_Results) return Natural is
      Result : Int32;
      Status : Ks_Status;
   begin
      KP.Results_Count (Results_Holders.Get (Results.Holder), Result, Status);
      Check (Status);
      return Natural (Result);
   end Count;

   function Item
     (Results : Ks_PM_Align_Results;
      Index   : Natural) return Ks_PM_Align_Result
   is
      Status : Ks_Status;
   begin
      return Result : Ks_PM_Align_Result do
         KP.Results_Item (Results_Holders.Get (Results.Holder), Int32 (Index),
                          Result, Status);
         Check (Status);
      end return;
   end Item;

   ---------------------------------------------------------------------
   --  The tool
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_PM_Align_Tool) is
      Image  : constant access constant KI.Ks_Image_8_Grey_Data :=
        Kernel_Images.Kernel_Handle (Tool.Input_Image);
      Handle : KP.Ks_PM_Align_Results;
      Status : Ks_Status;
   begin
      --  The pattern, the run parameters and a missing image first, then
      --  the region (AMV.Regions checks it in the image's spaces), then
      --  the search.
      KP.Check_Inputs (Image, Tool.Pattern.Model.Handle, Tool.Run_Params,
                       Status);
      Check (Status);
      declare
         Rasterized : constant AMV.Regions.Pixel_Region :=
           AMV.Regions.Rasterize (Tool.Input_Image, Tool.Search_Region);
         --  Without the pixels the search mask marks "don't care".
         Region     : constant AMV.Regions.Pixel_Region :=
           (if Tool.Search_Image_Mask.Allocated
            then AMV.Regions.Restrict_To_Mask
                   (Rasterized, Tool.Search_Image_Mask,
                    Tool.Search_Image_Mask_Offset_X,
                    Tool.Search_Image_Mask_Offset_Y)
            else Rasterized);
      begin
         KP.Execute
           (Image, Kernel_Regions.Kernel_Handle (Region),
            To_Kernel
              (Tool.Input_Image.Get_Transform
                 (AMV.Coordinate_Spaces.Selected_Space_Name,
                  AMV.Coordinate_Spaces.Pixel_Space_Name)),
            Tool.Pattern.Model.Handle, Tool.Run_Params, Handle, Status);
      end;
      Check (Status);
      Results_Holders.Set (Tool.Results.Holder, Handle);
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_PM_Align_Tool) is
   begin
      Results_Holders.Clear (Tool.Results.Holder);
   end Reset_Results;

end AMV.PM_Align;
