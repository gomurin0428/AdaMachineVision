pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;
with AMV.Coordinate_Spaces;
with AMV.Images.Kernel_Images;
with AMV.Kernels.Transforms;
with AMV.Regions.Kernel_Regions;
with AMV.Transforms;

package body AMV.Code_Reader is

   package KT renames AMV.Kernels.Transforms;
   package Kernel_Images renames AMV.Images.Kernel_Images;
   package Kernel_Regions renames AMV.Regions.Kernel_Regions;

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

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   function Symbology
     (Result : Ks_Code_Reader_Result)
      return Ks_Code_Reader_Symbology_Constants
   is
      Status : Ks_Status;
   begin
      KC.Check_Result_Symbology (Result, Status);
      Check (Status);
      return Ks_Code_Reader_Symbology_Constants'Enum_Val (Result.Symbology);
   end Symbology;

   function Text (Result : Ks_Code_Reader_Result) return String is
      Status : Ks_Status;
   begin
      KC.Check_Result_Length (Result, Status);
      Check (Status);
      return String
        (Result.Text
           (1 .. Natural (Int32'Min (Result.Length, KC.Max_Text_Length))));
   end Text;

   function Text
     (Results : Ks_Code_Reader_Results;
      Index   : Natural) return String
   is
      Whole  : constant Ks_Code_Reader_Result := Item (Results, Index);
      Result : String (1 .. Natural (Whole.Length));
      Done   : Natural := 0;
      Part   : KC.Code_Text;
      Length : Int32;
      Status : Ks_Status;
   begin
      while Done < Result'Length loop
         KC.Results_Text
           (Results_Holders.Get (Results.Holder), Int32 (Index),
            Int32 (Done), Part, Length, Status);
         Check (Status);
         exit when Length = 0;
         Result (Done + 1 .. Done + Natural (Length)) :=
           String (Part (1 .. Natural (Length)));
         Done := Done + Natural (Length);
      end loop;
      return Result (1 .. Done);
   end Text;

   procedure Destroy (Handle : in out KC.Ks_Code_Reader_Results) is
   begin
      KC.Results_Destroy (Handle);
   end Destroy;

   function Count (Results : Ks_Code_Reader_Results) return Natural is
      Result : Int32;
      Status : Ks_Status;
   begin
      KC.Results_Count (Results_Holders.Get (Results.Holder), Result, Status);
      Check (Status);
      return Natural (Result);
   end Count;

   function Item
     (Results : Ks_Code_Reader_Results;
      Index   : Natural) return Ks_Code_Reader_Result
   is
      Status : Ks_Status;
   begin
      return Result : Ks_Code_Reader_Result do
         KC.Results_Item
           (Results_Holders.Get (Results.Holder), Int32 (Index), Result,
            Status);
         Check (Status);
      end return;
   end Item;

   ---------------------------------------------------------------------
   --  The tool
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_Code_Reader_Tool) is
      Image  : constant access constant KC.KI.Ks_Image_8_Grey_Data :=
        Kernel_Images.Kernel_Handle (Tool.Input_Image);
      Handle : KC.Ks_Code_Reader_Results;
      Status : Ks_Status;
   begin
      --  The image first, so that an unallocated one is reported as such
      --  before the region is rasterised.
      KC.Check_Input_Image (Image, Status);
      Check (Status);
      declare
         Region : constant AMV.Regions.Pixel_Region :=
           AMV.Regions.Rasterize (Tool.Input_Image, Tool.Region);
      begin
         KC.Execute
           (Image, Kernel_Regions.Kernel_Handle (Region), Tool.Run_Params,
            To_Kernel
              (Tool.Input_Image.Get_Transform
                 (AMV.Coordinate_Spaces.Selected_Space_Name,
                  AMV.Coordinate_Spaces.Pixel_Space_Name)),
            Handle, Status);
         Check (Status);
      end;
      Results_Holders.Set (Tool.Results.Holder, Handle);
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Code_Reader_Tool) is
   begin
      Results_Holders.Clear (Tool.Results.Holder);
   end Reset_Results;

end AMV.Code_Reader;
