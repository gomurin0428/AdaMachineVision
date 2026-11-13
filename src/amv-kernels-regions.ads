--  Kernel of AMV.Regions: sets of image pixels (Pixel_Region), the
--  rasterisation of a region (AMV.Kernels.Shapes) into the pixels of an
--  image and the restriction of a set of pixels by an image mask. The
--  meaning of every operation is documented in AMV.Regions.
--
--  Handles. A pixel region lives behind an owned handle (Ks_Pixel_Region;
--  C: ks_pixel_region *, opaque) that ks_pixel_region_whole_image,
--  ks_pixel_region_rasterize_*, ks_pixel_region_restrict_to_mask or
--  ks_pixel_region_duplicate returns and ks_pixel_region_destroy frees. A
--  null handle is the empty region: its queries give 0 (Is_Empty gives
--  1), Contains gives 0, Duplicate gives null. A handle that is not null
--  must come from this kernel and not be destroyed yet (C cannot check
--  that); a record that is inconsistent anyway fails with Bad_Parameter
--  (Contains gives 0 for it).
--
--  A handle holds the bounding rectangle X_Min .. X_Min + Width - 1 by
--  Y_Min .. Y_Min + Height - 1 (pixel coordinates, Width and Height at
--  least 1, Width * Height at most Max_Pixels), the number of pixels
--  Count (at least 1) and the pixels: no flags at all when every pixel of
--  the rectangle belongs to the region (Count = Width * Height), otherwise
--  a matrix of flags Flags (Y, X) indexed by the pixel coordinates
--  themselves. The rectangle is always the smallest one around the
--  pixels. Valid_Region states the part of this that is checked at run
--  time; Consistent (ghost) adds that Count is the number of True flags
--  (Count_Of) and that the rectangle is the smallest (Smallest).
--
--  Rasterisation (ks_pixel_region_rasterize_<region type>). The arguments
--  are the size of the image, the transform Pixel_From_Region from the
--  region's selected space to pixel space (AMV.Images.Get_Transform ("#",
--  Region.Selected_Space_Name)) and the region. Pixel (X, Y) is included
--  when Inside holds for it: its centre mapped by Invert
--  (Pixel_From_Region), exactly as ks_transform_2d_linear_map_point maps a
--  point, lies within +/-AMV.Kernels.Shapes.Max_Value and the region's
--  Contains_Point accepts it (a centre that maps beyond that bound cannot
--  be in any region and is not included). Only the pixels of the candidate
--  box (Candidate_Box, documented in AMV.Regions) are tested; the result
--  is the region of the included candidates, with the smallest bounding
--  rectangle around them, or null when there is none. Failures, in this
--  order: Image_No_Pixels for the size 0 x 0, Bad_Parameter for any other
--  size that is not a valid image size or a transform that is not finite
--  and within +/-1.0E150, Transform_Singular when Pixel_From_Region has
--  no inverse within that bound (as ks_transform_2d_linear_invert),
--  Bad_Parameter for a region that is not valid or whose bounding box
--  leaves the bounds of AMV.Kernels.Shapes (the messages of its
--  ks_*_boundary_slack and ks_*_get_bounding_box), Out_Of_Memory.
--
--  Restriction by a mask (ks_pixel_region_restrict_to_mask). A mask is an
--  8-bit image (a handle of AMV.Kernels.Images) laid over the pixels of
--  the image at an offset: mask pixel (U, V) lies over pixel (U +
--  Offset_X, V + Offset_Y). A mask pixel of value 0 makes the pixel under
--  it a "don't care" pixel; a pixel under a mask pixel of any other value,
--  and every pixel that no mask pixel lies over, is a "care" pixel
--  (Cared_For). The result is a new region holding exactly the pixels of
--  the given region that are care pixels, with the smallest bounding
--  rectangle around them, or null when there is none. A null region (the
--  empty region) gives null; a null mask (an image without pixels) lies
--  over no pixel, so the result then holds every pixel of the region.
--  Offsets may be any Int32 values (a mask placed partly or wholly
--  outside the image covers only the pixels it lies over). Failures, in
--  this order: Bad_Parameter for a region handle that is not valid
--  ("Restrict_To_Mask: the region handle is inconsistent") or a mask
--  handle that is not valid ("Restrict_To_Mask: the mask is not a valid
--  image handle"), Out_Of_Memory.
--
--  Memory. Rasterising tests the candidates into a flag matrix of the
--  size of the candidate box, then keeps a matrix of the size of the
--  shrunk bounding rectangle only (the candidate matrix is freed before
--  the call returns; when the shrunk rectangle is the candidate box the
--  matrix is kept as it is), and no matrix at all when every pixel of the
--  rectangle is included. Restricting by a mask does the same with the
--  bounding rectangle of the given region in place of the candidate box.
--  Reading a stream (the Ada-only helpers below) allocates memory as the
--  elements arrive.
--
--  Trusted parts (SPARK_Mode Off bodies, listed in docs/PROOF.md): the
--  allocation helpers, which turn a failed allocation into Out_Of_Memory.
--  Everything else is proved.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Interfaces;

with AMV.Kernels.Images;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;

package AMV.Kernels.Regions with SPARK_Mode, Preelaborate is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  A postcondition refers to the reader on entry after a condition;
   --  contracts are proved, never executed.

   package KI renames AMV.Kernels.Images;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   use type Interfaces.Unsigned_8;

   Max_Pixels : constant := 2**31 - 1;
   --  The largest Width * Height of an image (AMV.Kernels.Images) and so
   --  of a region (C: KS_PIXEL_REGION_MAX_PIXELS).

   type Big is range -2**127 .. 2**127 - 1 with Ghost;
   --  Products of two Int64 values, for contracts that would overflow in
   --  Int64.

   ---------------------------------------------------------------------
   --  Handles
   ---------------------------------------------------------------------

   type Flag_Matrix is array (Natural range <>, Natural range <>) of Boolean
     with Default_Component_Value => False;
   --  Flags (Y, X) for the pixels of a region's bounding rectangle,
   --  indexed by their pixel coordinates.

   type Flag_Matrix_Access is access Flag_Matrix;

   type Ks_Pixel_Region_Data is limited record
      X_Min  : Int32 := 0;
      Y_Min  : Int32 := 0;
      Width  : Int32 := 0;
      Height : Int32 := 0;
      Count  : Int32 := 0;
      Flags  : Flag_Matrix_Access;
   end record;
   --  What a handle designates (opaque for C). Valid_Region states the
   --  invariant.

   type Ks_Pixel_Region is access Ks_Pixel_Region_Data
     with Convention => C;
   --  C: ks_pixel_region *.

   function Valid_Region
     (Region : access constant Ks_Pixel_Region_Data) return Boolean
   is
     (Region /= null
      and then Region.X_Min >= 0 and then Region.Y_Min >= 0
      and then Region.Width >= 1 and then Region.Height >= 1
      and then Int64 (Region.X_Min) + Int64 (Region.Width) - 1
                 <= Int64 (Int32'Last)
      and then Int64 (Region.Y_Min) + Int64 (Region.Height) - 1
                 <= Int64 (Int32'Last)
      and then Int64 (Region.Width) * Int64 (Region.Height) <= Max_Pixels
      and then Region.Count >= 1
      and then
        (if Region.Flags = null
         then Int64 (Region.Count)
                = Int64 (Region.Width) * Int64 (Region.Height)
         else Int64 (Region.Count)
                < Int64 (Region.Width) * Int64 (Region.Height)
              and then Int64 (Region.Flags'First (1)) = Int64 (Region.Y_Min)
              and then Int64 (Region.Flags'Last (1))
                         = Int64 (Region.Y_Min) + Int64 (Region.Height) - 1
              and then Int64 (Region.Flags'First (2)) = Int64 (Region.X_Min)
              and then Int64 (Region.Flags'Last (2))
                         = Int64 (Region.X_Min) + Int64 (Region.Width) - 1));
   --  A handle with its rectangle, its count and its flags in place.

   function Contains
     (Region : access constant Ks_Pixel_Region_Data;
      X, Y   : Int32) return Boolean
   is
     (Region /= null
      and then X >= Region.X_Min and then Y >= Region.Y_Min
      and then Int64 (X) - Int64 (Region.X_Min) < Int64 (Region.Width)
      and then Int64 (Y) - Int64 (Region.Y_Min) < Int64 (Region.Height)
      and then
        (Region.Flags = null
         or else (Integer (Y) in Region.Flags'Range (1)
                  and then Integer (X) in Region.Flags'Range (2)
                  and then Region.Flags (Integer (Y), Integer (X)))))
   with Inline;
   --  Pixel (X, Y) belongs to the region: it lies in the bounding
   --  rectangle and its flag is set (every pixel of the rectangle when
   --  there are no flags). False for null. For a valid handle the range
   --  tests on Flags follow from the rectangle; they keep the function
   --  safe for any handle. Takes constant time and builds no status, for
   --  callers that test every pixel.

   ---------------------------------------------------------------------
   --  Counting and the smallest rectangle (Gold)
   ---------------------------------------------------------------------

   function Length_2 (F : Flag_Matrix) return Int64 is
     (Int64 (F'Last (2)) - Int64 (F'First (2)) + 1)
   with Ghost;
   --  The number of columns.

   function Row_Count
     (F : Flag_Matrix;
      Y : Natural;
      X : Int64) return Int64
   is
     (if X <= Int64 (F'First (2)) then 0
      else Row_Count (F, Y, X - 1)
           + (if F (Y, Natural (X - 1)) then 1 else 0))
   with
     Ghost,
     Pre  => Y in F'Range (1)
             and then X >= Int64 (F'First (2))
             and then X <= Int64 (F'Last (2)) + 1,
     Post => Row_Count'Result in 0 .. X - Int64 (F'First (2)),
     Subprogram_Variant => (Decreases => X);
   --  The number of True flags in row Y left of column X.

   function Rows_Count (F : Flag_Matrix; Y : Int64) return Int64
   is
     (if Y <= Int64 (F'First (1)) then 0
      else Rows_Count (F, Y - 1)
           + Row_Count (F, Natural (Y - 1), Int64 (F'Last (2)) + 1))
   with
     Ghost,
     Pre  => F'First (2) <= F'Last (2)
             and then Y >= Int64 (F'First (1))
             and then Y <= Int64 (F'Last (1)) + 1,
     Post => Rows_Count'Result >= 0
             and then Rows_Count'Result
                        <= (Y - Int64 (F'First (1))) * 2**31
             and then Big (Rows_Count'Result)
                        <= Big (Y - Int64 (F'First (1)))
                           * Big (Length_2 (F)),
     Subprogram_Variant => (Decreases => Y);
   --  The number of True flags in the rows above row Y.

   function Count_Of (F : Flag_Matrix) return Int64 is
     (Rows_Count (F, Int64 (F'Last (1)) + 1))
   with
     Ghost,
     Pre => F'First (1) <= F'Last (1) and then F'First (2) <= F'Last (2);
   --  The number of True flags.

   function Smallest (F : Flag_Matrix) return Boolean is
     ((for some X in F'Range (2) => F (F'First (1), X))
      and then (for some X in F'Range (2) => F (F'Last (1), X))
      and then (for some Y in F'Range (1) => F (Y, F'First (2)))
      and then (for some Y in F'Range (1) => F (Y, F'Last (2))))
   with Pre => F'First (1) <= F'Last (1) and then F'First (2) <= F'Last (2);
   --  Each border row and column of F holds a True flag: no smaller
   --  rectangle holds them all.

   function Consistent
     (Region : access constant Ks_Pixel_Region_Data) return Boolean
   is
     (Region = null
      or else (Valid_Region (Region)
               and then (Region.Flags = null
                         or else (Int64 (Region.Count)
                                    = Count_Of (Region.Flags.all)
                                  and then Smallest (Region.Flags.all)))))
   with Ghost;
   --  Gold: Count is the number of pixels Contains accepts (Width * Height
   --  without flags, the number of True flags otherwise) and the bounding
   --  rectangle is the smallest one around them. Every handle this kernel
   --  returns is consistent.

   function In_Image
     (Region        : access constant Ks_Pixel_Region_Data;
      Width, Height : Int32) return Boolean
   is
     (Region = null
      or else (Valid_Region (Region)
               and then Int64 (Region.X_Min) + Int64 (Region.Width)
                          <= Int64 (Width)
               and then Int64 (Region.Y_Min) + Int64 (Region.Height)
                          <= Int64 (Height)));
   --  Every pixel of the region lies in a Width x Height image.

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   function Rasterize_Status_OK (Status : Ks_Status) return Boolean is
     (Valid (Status)
      and then Status.Failure
                 in Failure_None | Failure_Image_No_Pixels
                  | Failure_Bad_Parameter | Failure_Transform_Singular
                  | Failure_Out_Of_Memory);

   procedure Whole_Image
     (Image_Width, Image_Height : Int32;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_whole_image",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Valid_Region (Region) and then Consistent (Region)
                            and then Region.Flags = null
                            and then Region.X_Min = 0
                            and then Region.Y_Min = 0
                            and then Region.Width = Image_Width
                            and then Region.Height = Image_Height
                       else Region = null);
   --  Every pixel of an Image_Width x Image_Height image. Image_No_Pixels
   --  for 0 x 0 ("Whole_Image: the image has no pixels"), Bad_Parameter
   --  for any other size that is not at least 1 x 1 with at most
   --  Max_Pixels pixels.

   procedure Destroy
     (Region : in out Ks_Pixel_Region;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_destroy",
     Post => Valid (Status) and then Succeeded (Status) and then Region = null;
   --  Frees the region and sets Region to null. Nothing for null. Never
   --  fails.

   procedure Duplicate
     (Region : access constant Ks_Pixel_Region_Data;
      Result : out Ks_Pixel_Region;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_duplicate",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then (if Succeeded (Status) and then Region /= null
                       then Valid_Region (Region)
                            and then Valid_Region (Result)
                            and then Result.X_Min = Region.X_Min
                            and then Result.Y_Min = Region.Y_Min
                            and then Result.Width = Region.Width
                            and then Result.Height = Region.Height
                            and then Result.Count = Region.Count
                            and then (Result.Flags = null)
                                       = (Region.Flags = null)
                            and then (if Region.Flags /= null
                                      then Result.Flags.all
                                             = Region.Flags.all)
                            and then (if Consistent (Region)
                                      then Consistent (Result))
                       else Result = null);
   --  A new region with the same pixels, sharing nothing with Region (Gold:
   --  the same rectangle, count and flags); null for null.

   procedure Bounding_Box
     (Region : access constant Ks_Pixel_Region_Data;
      Result : out Ks_Pixel_Region;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_bounding_box",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then
               (if not Succeeded (Status) or else Region = null
                then Result = null
                else Valid_Region (Region)
                     and then Valid_Region (Result)
                     and then Consistent (Result)
                     and then Result.Flags = null
                     and then Result.X_Min = Region.X_Min
                     and then Result.Y_Min = Region.Y_Min
                     and then Result.Width = Region.Width
                     and then Result.Height = Region.Height);
   --  A new region of every pixel of Region's bounding rectangle (null for
   --  the empty region). Bad_Parameter for a handle that is not valid,
   --  Out_Of_Memory.

   procedure Shift_To_Origin
     (Region : access constant Ks_Pixel_Region_Data;
      Result : out Ks_Pixel_Region;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Valid_Region (Region)
                     and then Valid_Region (Result)
                     and then Result.X_Min = 0
                     and then Result.Y_Min = 0
                     and then Result.Width = Region.Width
                     and then Result.Height = Region.Height
                     and then Result.Count = Region.Count
                     and then (Result.Flags = null) = (Region.Flags = null)
                     and then
                       (for all Y in 0 .. Region.Height - 1 =>
                          (for all X in 0 .. Region.Width - 1 =>
                             Contains (Result, X, Y)
                               = Contains (Region, Region.X_Min + X,
                                           Region.Y_Min + Y)))
                else Result = null);
   --  A new region holding Region's pixels moved by (-X_Min, -Y_Min), so
   --  that its bounding rectangle starts at pixel (0, 0) (Gold: pixel
   --  (X, Y) of the result is pixel (X_Min + X, Y_Min + Y) of Region).
   --  Bad_Parameter for null and for a handle that is not valid,
   --  Out_Of_Memory. Not exported: the IP one-image kernel uses it to run
   --  its operators on the bounding box of a region.

   procedure Is_Empty
     (Region : access constant Ks_Pixel_Region_Data;
      Result : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_is_empty",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then (Region = null or else Valid_Region (Region))
                            and then Result
                                       = (if Region = null then True_Value
                                          else False_Value)
                       else Result = False_Value);
   --  1 for the empty region (null), 0 otherwise.

   procedure Pixel_Count
     (Region : access constant Ks_Pixel_Region_Data;
      Result : out Int32;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_pixel_count",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then Region /= null
                       then Valid_Region (Region)
                            and then Result = Region.Count
                       else Result = 0);
   --  The number of pixels (0 for null). For every handle this kernel
   --  returns it is the number of pixels Contains accepts (Consistent).

   procedure Get_Bounds
     (Region                     : access constant Ks_Pixel_Region_Data;
      X_Min, Y_Min, Width, Height : out Int32;
      Status                     : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_bounds",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) and then Region /= null
                       then Valid_Region (Region)
                            and then X_Min = Region.X_Min
                            and then Y_Min = Region.Y_Min
                            and then Width = Region.Width
                            and then Height = Region.Height
                       else X_Min = 0 and then Y_Min = 0
                            and then Width = 0 and then Height = 0);
   --  The bounding rectangle (all 0 for null).

   function Contains_Pixel
     (Region : access constant Ks_Pixel_Region_Data;
      X, Y   : Int32) return Int32
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_contains",
     Post => Contains_Pixel'Result
               = (if Contains (Region, X, Y) then True_Value
                  else False_Value);
   --  Contains as 1 or 0 (Gold: exactly the stored flag inside the
   --  rectangle, 1 inside a rectangle without flags, 0 outside it and for
   --  null). No status: it is meant to be called once per pixel, and it
   --  cannot fail (an inconsistent handle gives 0 outside the ranges of its
   --  flags).

   procedure Rasterize_Rectangle
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Rectangle                 : KS.Ks_Rectangle;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_rasterize_rectangle",
     Post => Rasterize_Status_OK (Status)
             and then (if Succeeded (Status)
                       then Consistent (Region)
                            and then In_Image
                                       (Region, Image_Width, Image_Height)
                       else Region = null);

   procedure Rasterize_Rectangle_Affine
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Rectangle                 : KS.Ks_Rectangle_Affine;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_rasterize_rectangle_affine",
     Post => Rasterize_Status_OK (Status)
             and then (if Succeeded (Status)
                       then Consistent (Region)
                            and then In_Image
                                       (Region, Image_Width, Image_Height)
                       else Region = null);

   procedure Rasterize_Circle
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Circle                    : KS.Ks_Circle;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_rasterize_circle",
     Post => Rasterize_Status_OK (Status)
             and then (if Succeeded (Status)
                       then Consistent (Region)
                            and then In_Image
                                       (Region, Image_Width, Image_Height)
                       else Region = null);

   procedure Rasterize_Ellipse
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Ellipse                   : KS.Ks_Ellipse;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_rasterize_ellipse",
     Post => Rasterize_Status_OK (Status)
             and then (if Succeeded (Status)
                       then Consistent (Region)
                            and then In_Image
                                       (Region, Image_Width, Image_Height)
                       else Region = null);

   procedure Rasterize_Polygon
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Polygon                   : access constant KS.Ks_Polygon_Data;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_rasterize_polygon",
     Post => Rasterize_Status_OK (Status)
             and then (if Succeeded (Status)
                       then Consistent (Region)
                            and then In_Image
                                       (Region, Image_Width, Image_Height)
                       else Region = null);
   --  A polygon without vertices (null) gives the empty region.

   procedure Rasterize_Circular_Annulus_Section
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Section                   : KS.Ks_Circular_Annulus_Section;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_rasterize_circular_annulus_section",
     Post => Rasterize_Status_OK (Status)
             and then (if Succeeded (Status)
                       then Consistent (Region)
                            and then In_Image
                                       (Region, Image_Width, Image_Height)
                       else Region = null);

   function Cared_For
     (Mask               : access constant KI.Ks_Image_8_Grey_Data;
      Offset_X, Offset_Y : Int32;
      X, Y               : Int32) return Boolean
   is
     (not KI.Valid_Image (Mask)
      or else Int64 (X) - Int64 (Offset_X) not in 0 .. Int64 (Mask.Width) - 1
      or else Int64 (Y) - Int64 (Offset_Y)
                not in 0 .. Int64 (Mask.Height) - 1
      or else Mask.Pixels (Natural (Int64 (Y) - Int64 (Offset_Y)),
                           Natural (Int64 (X) - Int64 (Offset_X))) /= 0)
   with Inline;
   --  Pixel (X, Y) is a care pixel of Mask laid at (Offset_X, Offset_Y):
   --  no mask pixel lies over it (always so for null), or the mask pixel
   --  over it, (X - Offset_X, Y - Offset_Y), is not 0. (A handle that is
   --  not null and not valid lies over no pixel here; the entry point
   --  rejects it.)

   procedure Restrict_To_Mask
     (Region             : access constant Ks_Pixel_Region_Data;
      Mask               : access constant KI.Ks_Image_8_Grey_Data;
      Offset_X, Offset_Y : Int32;
      Result             : out Ks_Pixel_Region;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_pixel_region_restrict_to_mask",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then (Mask = null or else KI.Valid_Image (Mask))
                     and then Consistent (Result)
                     and then
                       (if Region = null then Result = null
                        else Valid_Region (Region)
                             and then
                               (Result = null
                                or else
                                  (Result.X_Min >= Region.X_Min
                                   and then Result.Y_Min >= Region.Y_Min
                                   and then Int64 (Result.X_Min)
                                              + Int64 (Result.Width)
                                              <= Int64 (Region.X_Min)
                                                 + Int64 (Region.Width)
                                   and then Int64 (Result.Y_Min)
                                              + Int64 (Result.Height)
                                              <= Int64 (Region.Y_Min)
                                                 + Int64 (Region.Height)))
                             and then
                               (for all Y in Region.Y_Min
                                             .. Region.Y_Min
                                                + (Region.Height - 1) =>
                                  (for all X in Region.X_Min
                                                .. Region.X_Min
                                                   + (Region.Width - 1) =>
                                     Contains (Result, X, Y)
                                       = (Contains (Region, X, Y)
                                          and then Cared_For
                                                     (Mask, Offset_X,
                                                      Offset_Y, X, Y)))))
                else Result = null);
   --  The care pixels of Region (see "Restriction by a mask" above). Gold:
   --  the result is Consistent; for every pixel of Region's bounding
   --  rectangle, Contains of the result is exactly Contains of Region and
   --  Cared_For; and the result's rectangle lies in Region's, so no pixel
   --  outside it belongs to the result. So the result holds exactly the
   --  pixels P of Region such that the mask does not make P a "don't
   --  care" pixel.

   ---------------------------------------------------------------------
   --  Rasterisation, stated exactly (Ada only; the entry points above
   --  check their arguments, compute the candidate box and call
   --  Rasterize_Box)
   ---------------------------------------------------------------------

   type Shape_Kind is
     (Rectangle_Shape, Rectangle_Affine_Shape, Circle_Shape, Ellipse_Shape,
      Polygon_Shape, Section_Shape);

   type Shape_Data (Kind : Shape_Kind := Rectangle_Shape) is record
      case Kind is
         when Rectangle_Shape =>
            Rectangle : KS.Ks_Rectangle;
         when Rectangle_Affine_Shape =>
            Rectangle_Affine : KS.Ks_Rectangle_Affine;
         when Circle_Shape =>
            Circle : KS.Ks_Circle;
         when Ellipse_Shape =>
            Ellipse : KS.Ks_Ellipse;
         when Polygon_Shape =>
            null;
         when Section_Shape =>
            Section : KS.Ks_Circular_Annulus_Section;
      end case;
   end record;
   --  A region of one of the six types (a polygon's vertices are passed
   --  separately, as its handle).

   function Valid_Shape
     (Shape   : Shape_Data;
      Polygon : access constant KS.Ks_Polygon_Data) return Boolean
   is
     (case Shape.Kind is
         when Rectangle_Shape => KS.Valid_Rectangle (Shape.Rectangle),
         when Rectangle_Affine_Shape =>
            KS.Valid_Rectangle_Affine (Shape.Rectangle_Affine),
         when Circle_Shape => KS.Valid_Circle (Shape.Circle),
         when Ellipse_Shape => KS.Valid_Ellipse (Shape.Ellipse),
         when Polygon_Shape =>
            Polygon = null or else KS.Valid_Polygon (Polygon),
         when Section_Shape =>
            KS.Valid_Circular_Annulus_Section (Shape.Section));

   function Shape_Contains
     (Shape   : Shape_Data;
      Polygon : access constant KS.Ks_Polygon_Data;
      X, Y    : Long_Float) return Boolean
   is
     (case Shape.Kind is
         when Rectangle_Shape =>
            KS.Rectangle_Contains (Shape.Rectangle, X, Y),
         when Rectangle_Affine_Shape =>
            KS.Rectangle_Affine_Contains (Shape.Rectangle_Affine, X, Y),
         when Circle_Shape => KS.Circle_Contains (Shape.Circle, X, Y),
         when Ellipse_Shape => KS.Ellipse_Contains (Shape.Ellipse, X, Y),
         when Polygon_Shape => KS.Polygon_Contains (Polygon, X, Y),
         when Section_Shape => KS.Section_Contains (Shape.Section, X, Y))
   with Pre => Valid_Shape (Shape, Polygon)
               and then KS.Bounded (X) and then KS.Bounded (Y);
   --  The region's Contains_Point: exactly what ks_<type>_contains_point
   --  returns (see the postconditions in AMV.Kernels.Shapes).

   function Map_X
     (Transform : KT.Ks_Transform_2D_Linear;
      X, Y      : Int32) return Long_Float
   with Pre => KT.Bounded (Transform) and then X >= 0 and then Y >= 0;
   --  (A X + B Y) + Translation_X, computed as by
   --  ks_transform_2d_linear_map_point (without its bound check).

   function Map_Y
     (Transform : KT.Ks_Transform_2D_Linear;
      X, Y      : Int32) return Long_Float
   with Pre => KT.Bounded (Transform) and then X >= 0 and then Y >= 0;
   --  (C X + D Y) + Translation_Y, in the same way.

   function Inside
     (Shape             : Shape_Data;
      Polygon           : access constant KS.Ks_Polygon_Data;
      Region_From_Pixel : KT.Ks_Transform_2D_Linear;
      X, Y              : Int32) return Boolean
   with
     Pre  => Valid_Shape (Shape, Polygon)
             and then KT.Bounded (Region_From_Pixel)
             and then X >= 0 and then Y >= 0,
     Post => Inside'Result
               = (KS.Bounded (Map_X (Region_From_Pixel, X, Y))
                  and then KS.Bounded (Map_Y (Region_From_Pixel, X, Y))
                  and then Shape_Contains
                             (Shape, Polygon,
                              Map_X (Region_From_Pixel, X, Y),
                              Map_Y (Region_From_Pixel, X, Y)));
   --  The definition of rasterisation for pixel (X, Y): its centre mapped
   --  into the region's space lies within the coordinate bound and the
   --  region's Contains_Point accepts it. (A function with this
   --  postcondition rather than an expression function, so that the
   --  provers keep Inside (...) as a term in the quantified facts of the
   --  rasteriser.)

   type Pixel_Box is record
      X_First, X_Last, Y_First, Y_Last : Int32 := 0;
   end record;
   --  The pixels X_First .. X_Last by Y_First .. Y_Last.

   function Box_In_Image
     (Box           : Pixel_Box;
      Width, Height : Int32) return Boolean
   is
     (Box.X_First >= 0 and then Box.X_First <= Box.X_Last
      and then Box.X_Last < Width
      and then Box.Y_First >= 0 and then Box.Y_First <= Box.Y_Last
      and then Box.Y_Last < Height);
   --  A box of at least one pixel within a Width x Height image.

   function Valid_Image_Size (Width, Height : Int32) return Boolean is
     (Width >= 1 and then Height >= 1
      and then Int64 (Width) * Int64 (Height) <= Max_Pixels);

   procedure Candidate_Box
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
      Slack                     : Long_Float;
      Box                       : out Pixel_Box;
      Found                     : out Boolean)
   with
     Pre  => Valid_Image_Size (Image_Width, Image_Height)
             and then KT.Bounded (Pixel_From_Region)
             and then KS.Valid_Box (Min_X, Min_Y, Max_X, Max_Y)
             and then Slack in 0.0 .. KS.Max_Slack,
     Post => (if Found then Box_In_Image (Box, Image_Width, Image_Height));
   --  The candidate pixels of a region whose bounding box is (Min_X, Min_Y,
   --  Max_X, Max_Y) and whose boundary slack is Slack (see AMV.Regions):
   --  the four corners of the box mapped by Pixel_From_Region = [A B; C D]
   --  + translation (as by ks_transform_2d_linear_map_point), the
   --  axis-aligned box around them widened by 0.5 + Slack * (abs A + abs
   --  B) in x and 0.5 + Slack * (abs C + abs D) in y, and the pixels
   --  whose centres lie in it, clipped to the image. Found is False when
   --  there is none. Not proved: that every pixel Inside accepts is a
   --  candidate. That holds when Contains_Point accepts only points within
   --  Slack of the box, which AMV.Kernels.Shapes proves for the rectangle
   --  and documents for the other types, and when the half pixel covers
   --  the rounding of the mapping (see AMV.Regions).

   procedure Rasterize_Box
     (Shape             : Shape_Data;
      Polygon           : access constant KS.Ks_Polygon_Data;
      Region_From_Pixel : KT.Ks_Transform_2D_Linear;
      Box               : Pixel_Box;
      Region            : out Ks_Pixel_Region;
      Status            : out Ks_Status)
   with
     Pre  => Valid_Shape (Shape, Polygon)
             and then KT.Bounded (Region_From_Pixel)
             and then Box.X_First >= 0 and then Box.X_First <= Box.X_Last
             and then Box.Y_First >= 0 and then Box.Y_First <= Box.Y_Last
             and then (Int64 (Box.X_Last) - Int64 (Box.X_First) + 1)
                      * (Int64 (Box.Y_Last) - Int64 (Box.Y_First) + 1)
                        <= Max_Pixels,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Consistent (Region)
                     and then (Region = null
                               or else (Region.X_Min >= Box.X_First
                                        and then Region.Y_Min >= Box.Y_First
                                        and then Int64 (Region.X_Min)
                                                   + Int64 (Region.Width) - 1
                                                   <= Int64 (Box.X_Last)
                                        and then Int64 (Region.Y_Min)
                                                   + Int64 (Region.Height) - 1
                                                   <= Int64 (Box.Y_Last)))
                     and then
                       (for all Y in Box.Y_First .. Box.Y_Last =>
                          (for all X in Box.X_First .. Box.X_Last =>
                             Contains (Region, X, Y)
                               = Inside (Shape, Polygon, Region_From_Pixel,
                                         X, Y)))
                else Region = null);
   --  The region of the pixels of Box that Inside accepts (Gold: for every
   --  pixel of Box, Contains is exactly Inside; the rectangle lies in Box,
   --  so no pixel outside Box belongs to the region; Count and the
   --  smallest rectangle by Consistent). Null when Inside accepts none.
   --  Out_Of_Memory when a flag matrix or the handle cannot be allocated.
   --  (It sets one flag per pixel of Box and builds the region from the
   --  flags in the same way as ks_pixel_region_restrict_to_mask.)

   ---------------------------------------------------------------------
   --  For the Ada API only (not exported)
   ---------------------------------------------------------------------

   procedure Check_Rasterize
     (Image_Width, Image_Height : Int32;
      Shape_Type                : Int32;
      Status                    : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Image_Size (Image_Width, Image_Height)
                            and then Shape_Type
                                       in KS.Shape_Rectangle
                                        | KS.Shape_Rectangle_Affine
                                        | KS.Shape_Circle
                                        | KS.Shape_Ellipse
                                        | KS.Shape_Polygon
                                        | KS.Shape_Circular_Annulus_Section);
   --  AMV.Regions.Rasterize checks the image (Image_No_Pixels for 0 x 0,
   --  as the entry points) and the type of the region (a code of
   --  AMV.Kernels.Shapes; Bad_Parameter for any other type, for example 0
   --  for a type derived from Ks_Region outside AMV) before it asks the
   --  image for the transform, so that a missing image is reported before
   --  an unknown space name.

   --  Streams (AMV.Regions.Pixel_Region'Write and 'Read; the layout is
   --  documented there). Numbers are four bytes, least significant first.

   type Byte_Array is array (Positive range <>) of Interfaces.Unsigned_8;

   Header_Length : constant := 24;

   subtype Header_Bytes is Byte_Array (1 .. Header_Length);

   Format_Code : constant := 16#4B53_5247#;
   --  Names a Pixel_Region in that layout ("KSRG").

   procedure Stream_Header
     (Region : access constant Ks_Pixel_Region_Data;
      Header : out Header_Bytes;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter;
   --  The format code, X_Min, Y_Min, Width, Height and Count (all 0 for
   --  null).

   type Flag_Position is record
      Row    : Int32 := 0;
      Column : Int32 := 0;
      Done   : Int64 := 0;
   end record;
   --  The next flag to write: row and column relative to the rectangle,
   --  and the number of flags written before it.

   function Stream_Total
     (Region : access constant Ks_Pixel_Region_Data) return Int64
   is
     (if Valid_Region (Region) and then Region.Flags /= null
      then Int64 (Region.Width) * Int64 (Region.Height)
      else 0)
   with Post => Stream_Total'Result in 0 .. Max_Pixels;
   --  The number of pixel elements stored: Width * Height when the region
   --  has flags (0 < Count < Width * Height), none otherwise.

   procedure Next_Write_Chunk
     (Region   : access constant Ks_Pixel_Region_Data;
      Position : Flag_Position;
      Limit    : Positive;
      Length   : out Natural)
   with Post => Length <= Limit;
   --  The number of elements of the next chunk (at most Limit; 0 at the
   --  end or when there are none).

   procedure Get_Flag_Bytes
     (Region   : access constant Ks_Pixel_Region_Data;
      Position : in out Flag_Position;
      Bytes    : out Byte_Array;
      Status   : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Bad_Parameter;
   --  The next Bytes'Length elements (1 for a pixel of the region, 0 for
   --  another), moving Position on. Bad_Parameter for an inconsistent
   --  handle, a position that is not valid or more elements than are
   --  left.

   type Bool_Array is array (Natural range <>) of Boolean
     with Default_Component_Value => False;
   type Bool_Array_Access is access Bool_Array;

   type Ks_Region_Reader_Data is limited record
      X_Min  : Int32 := 0;
      Y_Min  : Int32 := 0;
      Width  : Int32 := 0;
      Height : Int32 := 0;
      Count  : Int32 := 0;
      Total  : Int64 := 0;
      Filled : Int64 := 0;
      Buffer : Bool_Array_Access;
   end record;
   --  A region being read: the header read so far, the number of pixel
   --  elements expected (Total) and read (Filled), and the elements read
   --  (Buffer, which grows as they arrive; null before the first).

   type Ks_Region_Reader is access Ks_Region_Reader_Data;

   function Valid_Reader
     (Reader : access constant Ks_Region_Reader_Data) return Boolean
   is
     (Reader /= null
      and then Reader.X_Min >= 0 and then Reader.Y_Min >= 0
      and then
        (if Reader.Count = 0
         then Reader.X_Min = 0 and then Reader.Y_Min = 0
              and then Reader.Width = 0 and then Reader.Height = 0
              and then Reader.Total = 0
         else Reader.Count >= 1
              and then Reader.Width >= 1 and then Reader.Height >= 1
              and then Int64 (Reader.Width) * Int64 (Reader.Height)
                         <= Max_Pixels
              and then Int64 (Reader.X_Min) + Int64 (Reader.Width) - 1
                         <= Int64 (Int32'Last)
              and then Int64 (Reader.Y_Min) + Int64 (Reader.Height) - 1
                         <= Int64 (Int32'Last)
              and then Int64 (Reader.Count)
                         <= Int64 (Reader.Width) * Int64 (Reader.Height)
              and then Reader.Total
                         = (if Int64 (Reader.Count)
                                 < Int64 (Reader.Width)
                                   * Int64 (Reader.Height)
                            then Int64 (Reader.Width) * Int64 (Reader.Height)
                            else 0))
      and then Reader.Filled in 0 .. Reader.Total
      and then (if Reader.Buffer = null then Reader.Filled = 0
                else Reader.Buffer'First = 0
                     and then Int64 (Reader.Buffer'Last) < Reader.Total
                     and then Reader.Filled
                                <= Int64 (Reader.Buffer'Last) + 1));
   --  A reader with a header that passed every check (the empty region,
   --  a region without pixel elements, or one expecting Total of them),
   --  Filled elements stored in its buffer.

   procedure Read_Header
     (Header : Header_Bytes;
      Reader : out Ks_Region_Reader;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_File
                            | Failure_Out_Of_Memory
                and then (if Succeeded (Status) then Valid_Reader (Reader)
                          else Reader = null);
   --  Checks every field of the header exactly as AMV.Regions describes
   --  (Image_File, "Pixel_Region'Read: ..." naming the field) and, when
   --  they pass, returns a reader expecting the pixel elements (none
   --  unless 0 < Count < Width * Height).

   procedure Next_Read_Chunk
     (Reader : access constant Ks_Region_Reader_Data;
      Limit  : Positive;
      Length : out Natural)
   with Post => Length <= Limit;
   --  The number of elements of the next chunk to read (at most Limit; 0
   --  when every expected element has been read).

   procedure Put_Read_Bytes
     (Reader : Ks_Region_Reader;
      Bytes  : Byte_Array;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_File
                            | Failure_Bad_Parameter | Failure_Out_Of_Memory
                and then (if Valid_Reader (Reader)'Old
                          then Valid_Reader (Reader));
   --  Stores the next Bytes'Length elements: each must be 0 or 1
   --  (Image_File otherwise). The buffer grows (doubling, never past
   --  Total) only when the elements read so far fill it, so the memory
   --  follows the data actually present. Bad_Parameter for an
   --  inconsistent reader or more elements than are expected.

   procedure Finish_Read
     (Reader : in out Ks_Region_Reader;
      Region : out Ks_Pixel_Region;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_File
                            | Failure_Bad_Parameter | Failure_Out_Of_Memory
                and then Reader = null
                and then (if Succeeded (Status) then Consistent (Region)
                          else Region = null);
   --  The region read, once every expected element is there: the number
   --  of 1s must be Count and the rectangle the smallest one around them
   --  (Image_File otherwise); Bad_Parameter when elements are missing.
   --  Frees the reader in any case.

   procedure Destroy_Reader (Reader : in out Ks_Region_Reader)
   with Post => Reader = null;
   --  Frees the reader (nothing for null).

   procedure Stream_Ended (Status : out Ks_Status)
   with Post => Valid (Status) and then Status.Failure = Failure_Image_File;
   --  "Pixel_Region'Read: the stream ends before the region is complete".

end AMV.Kernels.Regions;
