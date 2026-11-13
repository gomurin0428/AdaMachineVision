pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.IO_Exceptions;
with Ada.Tags;
with Interfaces;

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Images.Kernel_Images;
with AMV.Kernels.CNL_Search.Region_Modes;
with AMV.Kernels.Images;
with AMV.Kernels.Transforms;
with AMV.Regions;
with AMV.Regions.Kernel_Regions;
with AMV.Shapes.Kernel_Shapes;
with AMV.Transforms;

package body AMV.CNL_Search is

   package KI renames AMV.Kernels.Images;
   package KM renames AMV.Kernels.CNL_Search.Region_Modes;
   package KT renames AMV.Kernels.Transforms;
   package Kernel_Shapes renames AMV.Shapes.Kernel_Shapes;
   package Kernel_Images renames AMV.Images.Kernel_Images;
   package Kernel_Regions renames AMV.Regions.Kernel_Regions;

   subtype Int32 is AMV.Kernels.Int32;
   subtype U32 is Interfaces.Unsigned_32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;

   use type Int32;

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

   procedure Destroy (Handle : in out KC.Ks_CNL_Search_Results) is
   begin
      KC.Results_Destroy (Handle);
   end Destroy;

   ---------------------------------------------------------------------
   --  The pattern handle
   ---------------------------------------------------------------------

   overriding procedure Adjust (Item : in out Pattern_Handle) is
      Source : constant KC.Ks_CNL_Search_Pattern := Item.Handle;
      Status : Ks_Status;
   begin
      --  The copy shares the source's handle until it has its own; it
      --  must not keep it if the duplicate cannot be made.
      Item.Handle := null;
      KC.Pattern_Duplicate (Source, Item.Handle, Status);
      Check (Status);
   end Adjust;

   overriding procedure Finalize (Item : in out Pattern_Handle) is
      Status : Ks_Status;
   begin
      KC.Pattern_Destroy (Item.Handle, Status);
   end Finalize;

   procedure Write_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Pattern_Handle)
   is
      pragma Unreferenced (Stream, Item);
   begin
      null;
   end Write_Handle;

   procedure Read_Handle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Pattern_Handle)
   is
      pragma Unreferenced (Stream);
      Status : Ks_Status;
   begin
      KC.Pattern_Destroy (Item.Handle, Status);
   end Read_Handle;

   ---------------------------------------------------------------------
   --  The pattern
   ---------------------------------------------------------------------

   function Params_Of (Pattern : Ks_CNL_Search_Pattern)
      return KC.Ks_CNL_Search_Train_Params;
   --  The training parameters.

   function Params_Of (Pattern : Ks_CNL_Search_Pattern)
      return KC.Ks_CNL_Search_Train_Params
   is
      Params : KC.Ks_CNL_Search_Train_Params;
      Status : Ks_Status;
   begin
      KC.Pattern_Get_Train_Params (Pattern.Kernel.Handle, Params, Status);
      Check (Status);
      return Params;
   end Params_Of;

   procedure Set_Params
     (Pattern : in out Ks_CNL_Search_Pattern;
      Params  : KC.Ks_CNL_Search_Train_Params);
   --  Stores the training parameters (which untrains the pattern).

   procedure Set_Params
     (Pattern : in out Ks_CNL_Search_Pattern;
      Params  : KC.Ks_CNL_Search_Train_Params)
   is
      Status : Ks_Status;
   begin
      KC.Pattern_Set_Train_Params (Pattern.Kernel.Handle, Params, Status);
      Check (Status);
   end Set_Params;

   function Train_Image (Pattern : Ks_CNL_Search_Pattern)
      return AMV.Images.Ks_Image_8_Grey
   is (Pattern.Train_Image);

   procedure Set_Train_Image
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : AMV.Images.Ks_Image_8_Grey) is
   begin
      Pattern.Train_Image := Value;
      Untrain (Pattern);
   end Set_Train_Image;

   function Train_Region (Pattern : Ks_CNL_Search_Pattern)
      return AMV.Shapes.Region_Holders.Holder
   is (Pattern.Train_Region);

   procedure Set_Train_Region
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : AMV.Shapes.Region_Holders.Holder) is
   begin
      Pattern.Train_Region := Value;
      Untrain (Pattern);
   end Set_Train_Region;

   function Train_Image_Mask (Pattern : Ks_CNL_Search_Pattern)
      return AMV.Images.Ks_Image_8_Grey
   is (Pattern.Mask);

   procedure Set_Train_Image_Mask
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : AMV.Images.Ks_Image_8_Grey) is
   begin
      Pattern.Mask := Value;
      Untrain (Pattern);
   end Set_Train_Image_Mask;

   function Train_Image_Mask_Offset_X (Pattern : Ks_CNL_Search_Pattern)
      return Integer
   is (Pattern.Mask_Offset_X);

   procedure Set_Train_Image_Mask_Offset_X
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : Integer) is
   begin
      Pattern.Mask_Offset_X := Value;
      Untrain (Pattern);
   end Set_Train_Image_Mask_Offset_X;

   function Train_Image_Mask_Offset_Y (Pattern : Ks_CNL_Search_Pattern)
      return Integer
   is (Pattern.Mask_Offset_Y);

   procedure Set_Train_Image_Mask_Offset_Y
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : Integer) is
   begin
      Pattern.Mask_Offset_Y := Value;
      Untrain (Pattern);
   end Set_Train_Image_Mask_Offset_Y;

   function Origin_X (Pattern : Ks_CNL_Search_Pattern) return Real is
     (Params_Of (Pattern).Origin_X);

   function Origin_Y (Pattern : Ks_CNL_Search_Pattern) return Real is
     (Params_Of (Pattern).Origin_Y);

   procedure Set_Origin_X (Pattern : in out Ks_CNL_Search_Pattern;
                           Value   : Real)
   is
      Params : KC.Ks_CNL_Search_Train_Params := Params_Of (Pattern);
   begin
      Params.Origin_X := Value;
      Set_Params (Pattern, Params);
   end Set_Origin_X;

   procedure Set_Origin_Y (Pattern : in out Ks_CNL_Search_Pattern;
                           Value   : Real)
   is
      Params : KC.Ks_CNL_Search_Train_Params := Params_Of (Pattern);
   begin
      Params.Origin_Y := Value;
      Set_Params (Pattern, Params);
   end Set_Origin_Y;

   function Algorithms (Pattern : Ks_CNL_Search_Pattern)
      return Ks_CNL_Search_Algorithm_Constants
   is (Params_Of (Pattern).Algorithms);

   procedure Set_Algorithms
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : Ks_CNL_Search_Algorithm_Constants)
   is
      Params : KC.Ks_CNL_Search_Train_Params := Params_Of (Pattern);
   begin
      Params.Algorithms := Value;
      Set_Params (Pattern, Params);
   end Set_Algorithms;

   function Accuracies (Pattern : Ks_CNL_Search_Pattern)
      return Ks_CNL_Search_Accuracy_Constants
   is (Params_Of (Pattern).Accuracies);

   procedure Set_Accuracies
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : Ks_CNL_Search_Accuracy_Constants)
   is
      Params : KC.Ks_CNL_Search_Train_Params := Params_Of (Pattern);
   begin
      Params.Accuracies := Value;
      Set_Params (Pattern, Params);
   end Set_Accuracies;

   function Ignore_Polarity (Pattern : Ks_CNL_Search_Pattern)
      return Boolean
   is (Boolean'Val (Params_Of (Pattern).Ignore_Polarity));

   procedure Set_Ignore_Polarity
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : Boolean)
   is
      Params : KC.Ks_CNL_Search_Train_Params := Params_Of (Pattern);
   begin
      Params.Ignore_Polarity := Boolean'Pos (Value);
      Set_Params (Pattern, Params);
   end Set_Ignore_Polarity;

   function Train_Region_Mode (Pattern : Ks_CNL_Search_Pattern)
      return Ks_Region_Mode_Constants
   is (Ks_Region_Mode_Constants (Params_Of (Pattern).Train_Region_Mode));

   procedure Set_Train_Region_Mode
     (Pattern : in out Ks_CNL_Search_Pattern;
      Value   : AMV.Kernels.Int32)
   is
      Params : KC.Ks_CNL_Search_Train_Params := Params_Of (Pattern);
   begin
      Params.Train_Region_Mode := Value;
      Set_Params (Pattern, Params);
   end Set_Train_Region_Mode;

   procedure Train (Pattern : in out Ks_CNL_Search_Pattern) is
      Image  : constant access constant KI.Ks_Image_8_Grey_Data :=
        Kernel_Images.Kernel_Handle (Pattern.Train_Image);
      Status : Ks_Status;
   begin
      --  Untrained first, so that a failure before the kernel's training
      --  (an image or a region space that cannot be used) leaves the
      --  pattern untrained too.
      Untrain (Pattern);
      KC.Check_Train_Image (Image, Status);
      Check (Status);
      if Train_Region_Mode (Pattern) = Affine_Transform then
         --  The train region must be an affine rectangle (an empty holder
         --  is none); it is resampled by the kernel.
         KM.Check_Affine_Train_Region
           ((if Pattern.Train_Region.Is_Empty then 0
             else Kernel_Shapes.Kernel_Type (Pattern.Train_Region.Element)),
            Status);
         Check (Status);
         declare
            Region : AMV.Shapes.Ks_Region'Class renames
              Pattern.Train_Region.Constant_Reference.Element.all;
         begin
            KM.Train_Affine
              (Pattern.Kernel.Handle, Image,
               Kernel_Shapes.Kernel_Rectangle_Affine
                 (AMV.Shapes.Ks_Rectangle_Affine'Class (Region)),
               To_Kernel
                 (Pattern.Train_Image.Get_Transform
                    (AMV.Coordinate_Spaces.Pixel_Space_Name,
                     Region.Selected_Space_Name)),
               To_Kernel
                 (Pattern.Train_Image.Get_Transform
                    (AMV.Coordinate_Spaces.Pixel_Space_Name,
                     AMV.Coordinate_Spaces.Selected_Space_Name)),
               Kernel_Images.Kernel_Handle (Pattern.Mask),
               Int32 (Pattern.Mask_Offset_X), Int32 (Pattern.Mask_Offset_Y),
               Status);
         end;
         Check (Status);
         return;
      end if;
      declare
         Region : constant AMV.Regions.Pixel_Region :=
           AMV.Regions.Rasterize (Pattern.Train_Image, Pattern.Train_Region);
      begin
         KC.Pattern_Train_Masked
           (Pattern.Kernel.Handle, Image,
            Kernel_Regions.Kernel_Handle (Region),
            To_Kernel
              (Pattern.Train_Image.Get_Transform
                 (AMV.Coordinate_Spaces.Pixel_Space_Name,
                  AMV.Coordinate_Spaces.Selected_Space_Name)),
            Kernel_Images.Kernel_Handle (Pattern.Mask),
            Int32 (Pattern.Mask_Offset_X), Int32 (Pattern.Mask_Offset_Y),
            Status);
      end;
      Check (Status);
   end Train;

   function Trained (Pattern : Ks_CNL_Search_Pattern) return Boolean is
      Result : Int32;
      Status : Ks_Status;
   begin
      KC.Pattern_Trained (Pattern.Kernel.Handle, Result, Status);
      Check (Status);
      return Result = AMV.Kernels.True_Value;
   end Trained;

   procedure Untrain (Pattern : in out Ks_CNL_Search_Pattern) is
      Status : Ks_Status;
   begin
      KC.Pattern_Untrain (Pattern.Kernel.Handle, Status);
      Check (Status);
   end Untrain;

   function Trained_Pattern_Width (Pattern : Ks_CNL_Search_Pattern)
      return Natural
   is
      Width, Height : Int32;
      Status        : Ks_Status;
   begin
      KC.Pattern_Trained_Size (Pattern.Kernel.Handle, Width, Height, Status);
      Check (Status);
      return Natural (Width);
   end Trained_Pattern_Width;

   function Trained_Pattern_Height (Pattern : Ks_CNL_Search_Pattern)
      return Natural
   is
      Width, Height : Int32;
      Status        : Ks_Status;
   begin
      KC.Pattern_Trained_Size (Pattern.Kernel.Handle, Width, Height, Status);
      Check (Status);
      return Natural (Height);
   end Trained_Pattern_Height;

   function Get_Trained_Pattern_Image (Pattern : Ks_CNL_Search_Pattern)
      return AMV.Images.Ks_Image_8_Grey
   is
      Handle : KI.Ks_Image_8_Grey;
      Status : Ks_Status;
   begin
      KC.Pattern_Get_Trained_Pattern_Image
        (Pattern.Kernel.Handle, Handle, Status);
      Check (Status);
      return Kernel_Images.Adopt (Handle);
   end Get_Trained_Pattern_Image;

   procedure Write_Pattern
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Ks_CNL_Search_Pattern)
   is
      Params : constant KC.Ks_CNL_Search_Train_Params := Params_Of (Item);
   begin
      U32'Write (Stream, KC.Stream_Code_Region_Mode);
      Int32'Write (Stream, Params.Algorithms);
      Int32'Write (Stream, Params.Accuracies);
      Int32'Write (Stream, Params.Ignore_Polarity);
      Real'Write (Stream, Params.Origin_X);
      Real'Write (Stream, Params.Origin_Y);
      Int32'Write (Stream, Params.Train_Region_Mode);
      AMV.Images.Ks_Image_8_Grey'Write (Stream, Item.Train_Image);
      AMV.Shapes.Region_Holders.Holder'Write (Stream, Item.Train_Region);
      AMV.Images.Ks_Image_8_Grey'Write (Stream, Item.Mask);
      Int32'Write (Stream, Int32 (Item.Mask_Offset_X));
      Int32'Write (Stream, Int32 (Item.Mask_Offset_Y));
      if Trained (Item) then
         declare
            X, Y   : Real;
            Care   : KI.Ks_Image_8_Grey;
            Status : Ks_Status;
         begin
            KC.Pattern_Trained_Origin (Item.Kernel.Handle, X, Y, Status);
            Check (Status);
            U32'Write (Stream, 1);
            Real'Write (Stream, X);
            Real'Write (Stream, Y);
            AMV.Images.Ks_Image_8_Grey'Write
              (Stream, Get_Trained_Pattern_Image (Item));
            KC.Pattern_Get_Trained_Care_Image
              (Item.Kernel.Handle, Care, Status);
            Check (Status);
            AMV.Images.Ks_Image_8_Grey'Write
              (Stream, Kernel_Images.Adopt (Care));
         end;
      else
         U32'Write (Stream, 0);
      end if;
   end Write_Pattern;

   procedure Read_Pattern
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_CNL_Search_Pattern)
   is
      Fresh   : Ks_CNL_Search_Pattern;
      Code    : U32;
      Masked  : Boolean;
      Moded   : Boolean;
      Params  : KC.Ks_CNL_Search_Train_Params;
      Value   : U32;
      Is_Set  : Boolean;
      Status  : Ks_Status;
   begin
      --  Everything is read into Fresh, so that a failure leaves Item as
      --  it was.
      U32'Read (Stream, Code);
      KC.Check_Stream_Code (Code, Masked, Moded, Status);
      Check (Status);
      Int32'Read (Stream, Params.Algorithms);
      Int32'Read (Stream, Params.Accuracies);
      Int32'Read (Stream, Params.Ignore_Polarity);
      Real'Read (Stream, Params.Origin_X);
      Real'Read (Stream, Params.Origin_Y);
      --  A pattern written before the train region mode was trained on
      --  its whole box.
      Params.Train_Region_Mode := Pixel_Aligned_Bounding_Box;
      if Moded then
         Int32'Read (Stream, Params.Train_Region_Mode);
      end if;
      KC.Pattern_Set_Train_Params (Fresh.Kernel.Handle, Params, Status);
      Check (Status);
      AMV.Images.Ks_Image_8_Grey'Read (Stream, Fresh.Train_Image);
      AMV.Shapes.Region_Holders.Holder'Read (Stream, Fresh.Train_Region);
      if Masked then
         declare
            Offset_X, Offset_Y : Int32;
         begin
            AMV.Images.Ks_Image_8_Grey'Read (Stream, Fresh.Mask);
            Int32'Read (Stream, Offset_X);
            Int32'Read (Stream, Offset_Y);
            Fresh.Mask_Offset_X := Integer (Offset_X);
            Fresh.Mask_Offset_Y := Integer (Offset_Y);
         end;
      end if;
      U32'Read (Stream, Value);
      KC.Check_Stream_Flag (Value, Is_Set, Status);
      Check (Status);
      if Is_Set then
         declare
            X, Y   : Real;
            Pixels : AMV.Images.Ks_Image_8_Grey;
            Care   : AMV.Images.Ks_Image_8_Grey;
         begin
            Real'Read (Stream, X);
            Real'Read (Stream, Y);
            AMV.Images.Ks_Image_8_Grey'Read (Stream, Pixels);
            if Masked then
               AMV.Images.Ks_Image_8_Grey'Read (Stream, Care);
            end if;
            KC.Restore_Trained
              (Fresh.Kernel.Handle, Kernel_Images.Kernel_Handle (Pixels),
               Kernel_Images.Kernel_Handle (Care), X, Y, Status);
            Check (Status);
         end;
      end if;
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Ada.Tags.Tag_Error
         | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_CNL_Search_Pattern'Read");
   end Read_Pattern;

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   function Count (Results : Ks_CNL_Search_Results) return Natural is
      Value  : Int32;
      Status : Ks_Status;
   begin
      KC.Results_Count (Results_Holders.Get (Results.Holder), Value, Status);
      Check (Status);
      return Natural (Value);
   end Count;

   function Item
     (Results : Ks_CNL_Search_Results;
      Index   : Natural) return Ks_CNL_Search_Result
   is
      Result : Ks_CNL_Search_Result;
      Status : Ks_Status;
   begin
      KC.Results_Item (Results_Holders.Get (Results.Holder), Int32 (Index),
                       Result, Status);
      Check (Status);
      return Result;
   end Item;

   ---------------------------------------------------------------------
   --  The tool
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_CNL_Search_Tool) is
      Image  : constant access constant KI.Ks_Image_8_Grey_Data :=
        Kernel_Images.Kernel_Handle (Tool.Input_Image);
      Handle : KC.Ks_CNL_Search_Results;
      Status : Ks_Status;
   begin
      --  A missing image first, then the region (AMV.Regions checks the
      --  region's space), then the kernel's checks.
      KC.Check_Input_Image (Image, Status);
      Check (Status);
      if Tool.Run_Params.Search_Region_Mode = Affine_Transform
        and then not Tool.Search_Region.Is_Empty
        and then Tool.Search_Region.Element
                   in AMV.Shapes.Ks_Rectangle_Affine'Class
      then
         --  An affine rectangle in the mode AffineTransform: resampled by
         --  the kernel. Any other region is searched in its bounding box
         --  in both modes (below), as VisionPro documents.
         declare
            Region : AMV.Shapes.Ks_Region'Class renames
              Tool.Search_Region.Constant_Reference.Element.all;
         begin
            KM.Execute_Affine
              (Image,
               Kernel_Shapes.Kernel_Rectangle_Affine
                 (AMV.Shapes.Ks_Rectangle_Affine'Class (Region)),
               To_Kernel
                 (Tool.Input_Image.Get_Transform
                    (AMV.Coordinate_Spaces.Pixel_Space_Name,
                     Region.Selected_Space_Name)),
               Tool.Pattern.Kernel.Handle, Tool.Run_Params,
               To_Kernel
                 (Tool.Input_Image.Get_Transform
                    (AMV.Coordinate_Spaces.Selected_Space_Name,
                     AMV.Coordinate_Spaces.Pixel_Space_Name)),
               Handle, Status);
         end;
         Check (Status);
         Results_Holders.Set (Tool.Results.Holder, Handle);
         return;
      end if;
      declare
         Region : constant AMV.Regions.Pixel_Region :=
           AMV.Regions.Rasterize (Tool.Input_Image, Tool.Search_Region);
      begin
         KC.Execute
           (Image, Kernel_Regions.Kernel_Handle (Region),
            Tool.Pattern.Kernel.Handle, Tool.Run_Params,
            To_Kernel
              (Tool.Input_Image.Get_Transform
                 (AMV.Coordinate_Spaces.Selected_Space_Name,
                  AMV.Coordinate_Spaces.Pixel_Space_Name)),
            Handle, Status);
      end;
      Check (Status);
      Results_Holders.Set (Tool.Results.Holder, Handle);
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_CNL_Search_Tool) is
   begin
      Results_Holders.Clear (Tool.Results.Holder);
   end Reset_Results;

end AMV.CNL_Search;
