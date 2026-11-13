--  Kernel of AMV.Image_Processing.Pixel_Map: a lookup table applied to the
--  pixels of a region (the operation of VisionPro's CogIPOneImagePixelMap,
--  offered as a tool of its own). The C API is declared in
--  include/amv_image_processing.h.
--
--  Execute makes a new 8-bit image of the size of the input image: every
--  pixel the region contains is replaced by Map (its value), every other
--  pixel is copied unchanged. The region is a pixel region handle of
--  AMV.Kernels.Regions (the Ada API passes the whole image for an empty
--  Region); a null region (the empty region) gives an unchanged copy of
--  the input, and pixels of the region outside the image are ignored.
--
--  Proved (docs/PROOF.md): absence of run-time errors for any handles; no
--  memory leaks; Gold: every output pixel inside the region is Map (input
--  pixel) and every other output pixel is the input pixel.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Images;
with AMV.Kernels.Regions;

package AMV.Kernels.Pixel_Map with SPARK_Mode, Preelaborate is

   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;

   use type KI.Grey_8;
   use type KI.Ks_Image_8_Grey;

   ---------------------------------------------------------------------
   --  Run parameters (CogIPOneImagePixelMap; C: ks_ip_one_image_pixel_map)
   ---------------------------------------------------------------------

   type Pixel_Map_Table is array (KI.Grey_8) of KI.Grey_8
     with Convention => C;
   --  The value each grey level is replaced by (VisionPro: GetMap /
   --  SetMap, a byte array of 256 entries). C: uint8_t map[256].

   Identity_Map : constant Pixel_Map_Table := [for V in KI.Grey_8 => V];
   --  Every grey level maps to itself (the default).

   type Ks_IP_One_Image_Pixel_Map is record
      Map : Pixel_Map_Table := Identity_Map;
   end record
     with Convention => C, Size => 256 * 8;
   --  C: ks_ip_one_image_pixel_map.

   procedure Run_Params_Default (Params : out Ks_IP_One_Image_Pixel_Map)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_map_run_params_default",
     Post => Params.Map = Identity_Map;
   --  The default run parameters (the identity map). Cannot fail.

   function Map_Pixel
     (Map    : Pixel_Map_Table;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Value  : KI.Grey_8;
      X, Y   : Natural) return KI.Grey_8
   is
     (if KR.Contains (Region, Int32 (X), Int32 (Y)) then Map (Value)
      else Value);
   --  The output pixel at (X, Y) for the input value Value.

   ---------------------------------------------------------------------
   --  Entry point
   ---------------------------------------------------------------------

   procedure Execute
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Params : Ks_IP_One_Image_Pixel_Map;
      Output : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Export, Convention => C, External_Name => "ks_pixel_map_execute",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Image)
                     and then KI.Valid_Image (Output)
                     and then Output.Width = Image.Width
                     and then Output.Height = Image.Height
                     and then
                       (for all Y in Output.Pixels'Range (1)
                        => (for all X in Output.Pixels'Range (2)
                            => Output.Pixels (Y, X)
                                 = Map_Pixel (Params.Map, Region,
                                              Image.Pixels (Y, X), X, Y)))
                else Output = null);
   --  The mapped image (Gold, see above). The checks, in order: the image
   --  (Image_No_Pixels "InputImage has no pixels", Bad_Parameter "InputImage
   --  is not a valid image handle"), the region (Bad_Parameter "Region is
   --  not a valid pixel region handle"), then Out_Of_Memory. Output is a
   --  new handle the caller owns, null when the call fails.

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter;
   --  The image check of Execute, made by the Ada API before it
   --  rasterises the region.

end AMV.Kernels.Pixel_Map;
