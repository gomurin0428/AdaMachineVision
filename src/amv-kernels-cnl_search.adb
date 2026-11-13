pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.CNL_Search.Correlation;
with AMV.Kernels.CNL_Search.Levels;
with AMV.Kernels.CNL_Search.Search;

package body AMV.Kernels.CNL_Search with SPARK_Mode is

   use type KR.Flag_Matrix_Access;

   package KL renames AMV.Kernels.CNL_Search.Levels;
   package KC renames AMV.Kernels.CNL_Search.Correlation;
   package KS renames AMV.Kernels.CNL_Search.Search;

   use type KL.Sum_Matrix_Access;
   use type KS.Candidate_Array_Access;
   use type KS.Score_Rows_Access;
   use type KS.Match_Array_Access;

   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Grey_8_Matrix, KI.Grey_8_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Ks_Image_8_Grey_Data, KI.Ks_Image_8_Grey);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_CNL_Search_Pattern_Data, Ks_CNL_Search_Pattern);
   procedure Free is new Ada.Unchecked_Deallocation
     (Found_Array, Found_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_CNL_Search_Results_Data, Ks_CNL_Search_Results);
   procedure Free is new Ada.Unchecked_Deallocation
     (KL.Sum_Matrix, KL.Sum_Matrix_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (KS.Candidate_Array, KS.Candidate_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (KS.Score_Rows, KS.Score_Rows_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (KS.Match_Array, KS.Match_Array_Access);

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   Default_Train_Params : constant Ks_CNL_Search_Train_Params :=
     (others => <>);

   procedure Allocate_Pattern (Pattern : out Ks_CNL_Search_Pattern)
   with
     Global => null,
     Post   => (if Pattern /= null
                then Pattern.Params = Default_Train_Params
                     and then not Pattern.Trained
                     and then Pattern.Levels = 0
                     and then Pattern.Pixels = null
                     and then Pattern.Care = null);
   --  A new pattern record with the record's default values, or null when
   --  the memory cannot be allocated. Trusted: the allocator raises
   --  Storage_Error, which SPARK cannot express.

   procedure Allocate_Pattern (Pattern : out Ks_CNL_Search_Pattern)
     with SPARK_Mode => Off
   is
   begin
      Pattern := new Ks_CNL_Search_Pattern_Data;
   exception
      when Storage_Error =>
         Pattern := null;
   end Allocate_Pattern;

   procedure Allocate_Results (Results : out Ks_CNL_Search_Results)
   with
     Global => null,
     Post   => (if Results /= null
                then Results.Count = 0 and then Results.Items = null);
   --  A new results record with the record's default values, or null.
   --  Trusted as above.

   procedure Allocate_Results (Results : out Ks_CNL_Search_Results)
     with SPARK_Mode => Off
   is
   begin
      Results := new Ks_CNL_Search_Results_Data;
   exception
      when Storage_Error =>
         Results := null;
   end Allocate_Results;

   procedure Allocate_Found
     (Count : Positive;
      Items : out Found_Array_Access)
   with
     Global => null,
     Post   => (if Items /= null
                then Items'First = 0 and then Items'Last = Count - 1);
   --  A new array of Count results (the record's defaults), or null.
   --  Trusted as above.

   procedure Allocate_Found
     (Count : Positive;
      Items : out Found_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Items := new Found_Array (0 .. Count - 1);
   exception
      when Storage_Error =>
         Items := null;
   end Allocate_Found;

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   function Placed
     (Item                             : Found;
      X_First, X_Last, Y_First, Y_Last : Int32;
      Left, Right, Up, Down            : Natural) return Boolean
   is
   begin
      return Placed_Facts (Item, X_First, X_Last, Y_First, Y_Last, Left,
                           Right, Up, Down);
   end Placed;

   procedure Bad (Status : out Ks_Status; Message : String)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Out_Of_Memory (Status : out Ks_Status)
   with Post => Valid (Status) and then Status.Failure = Failure_Out_Of_Memory;

   procedure Out_Of_Memory (Status : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Out_Of_Memory, "CNL search: out of memory");
   end Out_Of_Memory;

   function In_Bound (X : Long_Float) return Boolean is
     (X >= -Max_Value and then X <= Max_Value);

   function Has_Flag (Mask, Flag : Int32) return Boolean is
     ((Mask / Flag) mod 2 = 1)
   with Pre => Mask >= 0 and then Flag in 1 | 2 | 4;
   --  Flag is one of the flags of Mask.

   procedure Release_Pixels (Pixels : in out KI.Ks_Image_8_Grey)
   with Post => Pixels = null;
   --  Frees an image (nothing for null).

   procedure Release_Pixels (Pixels : in out KI.Ks_Image_8_Grey) is
   begin
      if Pixels /= null then
         Free (Pixels.Pixels);
         Free (Pixels);
      end if;
   end Release_Pixels;

   procedure Untrain_Data (Pattern : in out Ks_CNL_Search_Pattern_Data)
   with
     Pre  => Valid_Train_Params (Pattern.Params),
     Post => Valid_Data (Pattern) and then not Pattern.Trained
             and then Pattern.Params = Pattern.Params'Old;
   --  Frees the trained data and keeps the training parameters.

   procedure Untrain_Data (Pattern : in out Ks_CNL_Search_Pattern_Data) is
   begin
      Release_Pixels (Pattern.Pixels);
      Release_Pixels (Pattern.Care);
      Pattern.Trained := False;
      Pattern.Levels := 0;
      Pattern.Info := [others => <>];
      Pattern.Origin_X := 0.0;
      Pattern.Origin_Y := 0.0;
   end Untrain_Data;

   procedure Check_Image
     (Image    : access constant KI.Ks_Image_8_Grey_Data;
      Property : String;
      Status   : out Ks_Status)
   with
     Pre  => Property'First = 1 and then Property'Length <= 20,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Image_No_Pixels
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then KI.Valid_Image (Image)
                            and then Image.Width <= KI.Max_Pixels
                            and then Image.Height <= KI.Max_Pixels);
   --  Image_No_Pixels for null, Bad_Parameter for an inconsistent handle.

   procedure Check_Image
     (Image    : access constant KI.Ks_Image_8_Grey_Data;
      Property : String;
      Status   : out Ks_Status)
   is
   begin
      if Image = null then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      Property & " has no pixels");
      elsif not KI.Valid_Image (Image) then
         Bad (Status, Property & " is not a valid image");
      else
         Set_Success (Status);
      end if;
   end Check_Image;

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   is
   begin
      Check_Image (Image, "InputImage", Status);
   end Check_Input_Image;

   procedure Check_Train_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status)
   is
   begin
      Check_Image (Image, "TrainImage", Status);
   end Check_Train_Image;

   ---------------------------------------------------------------------
   --  Training parameters
   ---------------------------------------------------------------------

   procedure Check_Train_Params
     (Params : Ks_CNL_Search_Train_Params;
      Status : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Train_Params (Params));

   procedure Check_Train_Params
     (Params : Ks_CNL_Search_Train_Params;
      Status : out Ks_Status)
   is
   begin
      if Params.Algorithms not in 1 .. 7 then
         Bad (Status, "Pattern.Algorithms must be a combination of "
              & "LinearSearch, LinearCNLPAS and NonLinearCNLPAS");
      elsif Params.Algorithms >= Algorithm_Non_Linear_CNLPAS then
         Bad (Status, "Pattern.Algorithms NonLinearCNLPAS is not supported");
      elsif Params.Accuracies not in 1 .. 7 then
         Bad (Status, "Pattern.Accuracies must be a combination of "
              & "VeryFine, Fine and Coarse");
      elsif Params.Ignore_Polarity not in False_Value | True_Value then
         Bad (Status, "Pattern.IgnorePolarity must be 0 or 1");
      elsif not In_Bound (Params.Origin_X) then
         Bad (Status, "Pattern.OriginX must be finite and within 1.0E150");
      elsif not In_Bound (Params.Origin_Y) then
         Bad (Status, "Pattern.OriginY must be finite and within 1.0E150");
      elsif Params.Train_Region_Mode
              not in Region_Mode_Pixel_Aligned_Bounding_Box_Adjust_Mask
                   | Region_Mode_Pixel_Aligned_Bounding_Box
                   | Region_Mode_Affine_Transform
      then
         Bad (Status, "Pattern.TrainRegionMode must be "
              & "PixelAlignedBoundingBoxAdjustMask (0), "
              & "PixelAlignedBoundingBox (1) or AffineTransform (2)");
      else
         Set_Success (Status);
      end if;
   end Check_Train_Params;

   procedure Train_Params_Default
     (Params : out Ks_CNL_Search_Train_Params;
      Status : out Ks_Status)
   is
   begin
      Params := Default_Train_Params;
      Set_Success (Status);
   end Train_Params_Default;

   ---------------------------------------------------------------------
   --  Patterns
   ---------------------------------------------------------------------

   procedure Pattern_Create
     (Pattern : out Ks_CNL_Search_Pattern;
      Status  : out Ks_Status)
   is
   begin
      Allocate_Pattern (Pattern);
      if Pattern = null then
         Out_Of_Memory (Status);
      else
         Set_Success (Status);
      end if;
   end Pattern_Create;

   procedure Pattern_Destroy
     (Pattern : in out Ks_CNL_Search_Pattern;
      Status  : out Ks_Status)
   is
   begin
      if Pattern /= null then
         Release_Pixels (Pattern.Pixels);
         Release_Pixels (Pattern.Care);
         Free (Pattern);
      end if;
      Set_Success (Status);
   end Pattern_Destroy;

   procedure Pattern_Duplicate
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Copy    : out Ks_CNL_Search_Pattern;
      Status  : out Ks_Status)
   is
   begin
      Copy := null;
      if Pattern = null then
         Set_Success (Status);
         return;
      elsif not Valid_Pattern (Pattern) then
         Bad (Status, "Pattern is not a valid CNL search pattern");
         return;
      end if;
      Allocate_Pattern (Copy);
      if Copy = null then
         Out_Of_Memory (Status);
         return;
      end if;
      Copy.Params := Pattern.Params;
      if Pattern.Trained then
         KI.Duplicate (Pattern.Pixels, Copy.Pixels, Status);
         if Succeeded (Status) and then Pattern.Care /= null then
            KI.Duplicate (Pattern.Care, Copy.Care, Status);
         end if;
         if not Succeeded (Status) then
            Release_Pixels (Copy.Pixels);
            Release_Pixels (Copy.Care);
            Free (Copy);
            Out_Of_Memory (Status);
            return;
         end if;
         Copy.Levels := Pattern.Levels;
         Copy.Info := Pattern.Info;
         Copy.Origin_X := Pattern.Origin_X;
         Copy.Origin_Y := Pattern.Origin_Y;
         Copy.Trained := True;
      end if;
      Set_Success (Status);
   end Pattern_Duplicate;

   procedure Pattern_Get_Train_Params
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Params  : out Ks_CNL_Search_Train_Params;
      Status  : out Ks_Status)
   is
   begin
      Params := Default_Train_Params;
      if Pattern = null then
         Set_Success (Status);
      elsif not Valid_Train_Params (Pattern.Params) then
         Bad (Status, "Pattern is not a valid CNL search pattern");
      else
         Params := Pattern.Params;
         Set_Success (Status);
      end if;
   end Pattern_Get_Train_Params;

   procedure Pattern_Set_Train_Params
     (Pattern : in out Ks_CNL_Search_Pattern;
      Params  : Ks_CNL_Search_Train_Params;
      Status  : out Ks_Status)
   is
   begin
      Check_Train_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      end if;
      if Pattern = null then
         Allocate_Pattern (Pattern);
         if Pattern = null then
            Out_Of_Memory (Status);
            return;
         end if;
      elsif not Valid_Pattern (Pattern) then
         Bad (Status, "Pattern is not a valid CNL search pattern");
         return;
      end if;
      Untrain_Data (Pattern.all);
      Pattern.Params := Params;
      Set_Success (Status);
   end Pattern_Set_Train_Params;

   procedure Restrict_Care
     (Care   : in out KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data;
      X0, Y0 : Natural;
      G      : Level_Geometry)
   with
     Pre => KL.Indexed_From_Zero (Care)
            and then KL.Stacked (G, KL.Rows_Of (Care), KL.Columns_Of (Care));
   --  Clears the flag of every pixel (X, Y) of level G whose train image
   --  pixel (X0 + X, Y0 + Y) Region does not contain (the train region
   --  mode PixelAlignedBoundingBoxAdjustMask).

   procedure Restrict_Care
     (Care   : in out KI.Grey_8_Matrix;
      Region : access constant KR.Ks_Pixel_Region_Data;
      X0, Y0 : Natural;
      G      : Level_Geometry)
   is
   begin
      for Y in 0 .. G.Height - 1 loop
         for X in 0 .. G.Width - 1 loop
            declare
               PX : constant Int64 := Int64 (X0) + Int64 (X);
               PY : constant Int64 := Int64 (Y0) + Int64 (Y);
            begin
               if PX > Int64 (Int32'Last) or else PY > Int64 (Int32'Last)
                 or else not KR.Contains (Region, Int32 (PX), Int32 (PY))
               then
                  Care (G.Row + Y, X) := 0;
               end if;
            end;
         end loop;
      end loop;
   end Restrict_Care;

   procedure Build_Care
     (Mask             : access constant KI.Ks_Image_8_Grey_Data;
      Shift_X, Shift_Y : Int64;
      Region           : access constant KR.Ks_Pixel_Region_Data;
      X0, Y0           : Natural;
      Table            : KL.Geometry_Table;
      Levels           : Positive;
      Columns          : KL.Side;
      Rows             : Positive;
      Care             : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status)
   with
     Pre  => (Mask = null or else KI.Valid_Image (Mask))
             and then Shift_X in -KL.Max_Shift .. KL.Max_Shift
             and then Shift_Y in -KL.Max_Shift .. KL.Max_Shift
             and then Levels <= Max_Levels
             and then Rows <= 2 * Max_Pattern_Side
             and then (for all L in 0 .. Levels - 1 =>
                         KL.Stacked (Table (L), Rows, Columns))
             and then (for all L in 1 .. Levels - 1 =>
                         Table (L).Width = Table (L - 1).Width / 2
                         and then Table (L).Height
                                    = Table (L - 1).Height / 2),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then KI.Valid_Image (Care)
                            and then Care.Width = Int32 (Columns)
                            and then Care.Height = Int32 (Rows)
                       else Care = null);
   --  The care flags of the levels of Table, stacked as the pixels are in
   --  a new Columns x Rows image, from a train image mask (null: none):
   --  pixel (X, Y) of level 0 lies under mask pixel (X + Shift_X, Y +
   --  Shift_Y); and, with a Region (null: none), cleared for the pixels
   --  (X, Y) of level 0 whose train image pixel (X0 + X, Y0 + Y) the
   --  region does not contain.

   procedure Build_Care
     (Mask             : access constant KI.Ks_Image_8_Grey_Data;
      Shift_X, Shift_Y : Int64;
      Region           : access constant KR.Ks_Pixel_Region_Data;
      X0, Y0           : Natural;
      Table            : KL.Geometry_Table;
      Levels           : Positive;
      Columns          : KL.Side;
      Rows             : Positive;
      Care             : out KI.Ks_Image_8_Grey;
      Status           : out Ks_Status)
   is
   begin
      KI.Create (Int32 (Columns), Int32 (Rows), 1, Care, Status);
      if not Succeeded (Status) then
         Out_Of_Memory (Status);
         return;
      end if;
      if Mask /= null then
         KL.Copy_Care (Mask, Shift_X, Shift_Y, Care.Pixels.all, Table (0));
      end if;
      if Region /= null then
         Restrict_Care (Care.Pixels.all, Region, X0, Y0, Table (0));
      end if;
      for L in 1 .. Levels - 1 loop
         pragma Loop_Invariant
           (KI.Valid_Image (Care)
            and then Care.Width = Int32 (Columns)
            and then Care.Height = Int32 (Rows));
         KL.Downsample_Care (Care.Pixels.all, Table (L - 1), Table (L));
      end loop;
   end Build_Care;

   function Care_Fits
     (Care   : access constant KI.Ks_Image_8_Grey_Data;
      Pixels : KI.Grey_8_Matrix) return Boolean
   is
     (Care = null
      or else (KI.Valid_Image (Care)
               and then KL.Same_Shape (Care.Pixels.all, Pixels)));
   --  No care flags, or flags of the size of the stacked pixels.

   procedure Level_Statistics
     (Pixels : KI.Grey_8_Matrix;
      Care   : access constant KI.Ks_Image_8_Grey_Data;
      G      : Level_Geometry;
      Count  : out KL.Cared_Count;
      Sum    : out KL.Grey_Sum;
      Spread : out KL.Spread_Value)
   with
     Pre => KL.Indexed_From_Zero (Pixels)
            and then KL.Stacked (G, KL.Rows_Of (Pixels),
                                 KL.Columns_Of (Pixels))
            and then G.Width <= Max_Pattern_Side
            and then G.Height <= Max_Pattern_Side
            and then Care_Fits (Care, Pixels);
   --  The number of cared-for pixels of level G (every pixel without care
   --  flags), the sum of their grey levels and their spread (0 when there
   --  are none).

   procedure Level_Statistics
     (Pixels : KI.Grey_8_Matrix;
      Care   : access constant KI.Ks_Image_8_Grey_Data;
      G      : Level_Geometry;
      Count  : out KL.Cared_Count;
      Sum    : out KL.Grey_Sum;
      Spread : out KL.Spread_Value)
   is
      Square : KL.Square_Sum;
   begin
      if Care = null then
         KL.Statistics (Pixels, G, Sum, Square);
         Count := KL.Pixel_Count (G.Width, G.Height);
      else
         KL.Masked_Statistics (Pixels, Care.Pixels.all, G, Count, Sum,
                               Square);
      end if;
      Spread := (if Count >= 1 then KL.Spread_Of (Count, Sum, Square)
                 else 0);
   end Level_Statistics;

   procedure Measure_Levels
     (Pixels      : KI.Grey_8_Matrix;
      Care        : access constant KI.Ks_Image_8_Grey_Data;
      Table       : KL.Geometry_Table;
      Levels      : Positive;
      Width       : KL.Side;
      Rows        : Positive;
      Info        : out Level_Table;
      Used        : out Natural;
      First_Count : out KL.Cared_Count)
   with
     Pre  => KL.Indexed_From_Zero (Pixels)
             and then KL.Rows_Of (Pixels) = Rows
             and then KL.Columns_Of (Pixels) = Width
             and then Rows <= 2 * Max_Pattern_Side
             and then Levels <= Max_Levels
             and then (for all L in 0 .. Levels - 1 =>
                         Table (L).Width in 1 .. Width
                         and then Table (L).Height in 1 .. Max_Pattern_Side
                         and then KL.Stacked (Table (L), Rows, Width))
             and then Care_Fits (Care, Pixels),
     Post => Used <= Levels
             and then (for all K in 0 .. Used - 1 =>
                         Valid_Level (Info (K), Int32 (Width), Int32 (Rows))
                         and then Info (K).Geometry = Table (K));
   --  The statistics of the levels of Table (see Level_Statistics), up to
   --  the first that has fewer than Min_Cared_Pixels cared-for pixels or
   --  is flat: Info (0 .. Used - 1). First_Count is the number of
   --  cared-for pixels of level 0.

   procedure Measure_Levels
     (Pixels      : KI.Grey_8_Matrix;
      Care        : access constant KI.Ks_Image_8_Grey_Data;
      Table       : KL.Geometry_Table;
      Levels      : Positive;
      Width       : KL.Side;
      Rows        : Positive;
      Info        : out Level_Table;
      Used        : out Natural;
      First_Count : out KL.Cared_Count)
   is
   begin
      Info := [others => <>];
      Used := 0;
      First_Count := 0;
      for L in 0 .. Levels - 1 loop
         pragma Loop_Invariant (Used = L);
         pragma Loop_Invariant
           (for all K in 0 .. L - 1 =>
              Valid_Level (Info (K), Int32 (Width), Int32 (Rows))
              and then Info (K).Geometry = Table (K));
         declare
            G      : constant Level_Geometry := Table (L);
            Count  : KL.Cared_Count;
            Sum    : KL.Grey_Sum;
            Spread : KL.Spread_Value;
         begin
            Level_Statistics (Pixels, Care, G, Count, Sum, Spread);
            if L = 0 then
               First_Count := Count;
            end if;
            exit when Count < Min_Cared_Pixels or else Spread <= 0;
            Info (L) := (Geometry => G, Count => Count, Sum => Sum,
                         Spread => Spread);
            Used := L + 1;
         end;
      end loop;
   end Measure_Levels;

   procedure Build_Trained
     (Pattern       : in out Ks_CNL_Search_Pattern_Data;
      Source        : KI.Grey_8_Matrix;
      X0, Y0        : Natural;
      Width, Height : KL.Side;
      Mask          : access constant KI.Ks_Image_8_Grey_Data;
      Mask_Offset_X : Int32;
      Mask_Offset_Y : Int32;
      Region        : access constant KR.Ks_Pixel_Region_Data;
      Origin_X      : Long_Float;
      Origin_Y      : Long_Float;
      Status        : out Ks_Status)
   with
     Pre  => Valid_Data (Pattern) and then not Pattern.Trained
             and then KL.Indexed_From_Zero (Source)
             and then X0 <= Source'Last (2)
             and then Width - 1 <= Source'Last (2) - X0
             and then Y0 <= Source'Last (1)
             and then Height - 1 <= Source'Last (1) - Y0
             and then Width >= Min_Pattern_Side
             and then Height >= Min_Pattern_Side
             and then (Mask = null or else KI.Valid_Image (Mask))
             and then Origin_X >= -Max_Origin and then Origin_X <= Max_Origin
             and then Origin_Y >= -Max_Origin and then Origin_Y <= Max_Origin,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then Valid_Data (Pattern)
             and then Pattern.Params = Pattern.Params'Old
             and then Pattern.Trained = Succeeded (Status)
             and then (if Pattern.Trained
                       then Pattern.Pixels.Width = Int32 (Width)
                            and then Pattern.Info (0).Geometry
                                       = (Row    => 0,
                                          Width  => Width,
                                          Height => Height)
                            and then Pattern.Origin_X = Origin_X
                            and then Pattern.Origin_Y = Origin_Y
                            and then (if Mask = null and then Region = null
                                      then Pattern.Care = null));
   --  Trains Pattern on the Width x Height pixels of Source from (X0, Y0)
   --  with the given origin (pixels, relative to the first pixel): the
   --  levels (see AMV.Kernels.CNL_Search), their pixels stacked in a new
   --  image, with Mask (null: none; mask pixel (U, V) covers Source pixel
   --  (U + Mask_Offset_X, V + Mask_Offset_Y)) their care flags stacked in
   --  another, and their statistics. Bad_Parameter for fewer than
   --  Min_Cared_Pixels cared-for pixels and for a flat pattern.

   procedure Build_Trained
     (Pattern       : in out Ks_CNL_Search_Pattern_Data;
      Source        : KI.Grey_8_Matrix;
      X0, Y0        : Natural;
      Width, Height : KL.Side;
      Mask          : access constant KI.Ks_Image_8_Grey_Data;
      Mask_Offset_X : Int32;
      Mask_Offset_Y : Int32;
      Region        : access constant KR.Ks_Pixel_Region_Data;
      Origin_X      : Long_Float;
      Origin_Y      : Long_Float;
      Status        : out Ks_Status)
   is
      Wanted      : constant Positive :=
        (if Has_Flag (Pattern.Params.Algorithms, Algorithm_Linear_CNLPAS)
         then Max_Levels else 1);
      Table       : KL.Geometry_Table;
      Levels      : Positive;
      Rows        : Positive;
      Stack       : KI.Ks_Image_8_Grey;
      Care        : KI.Ks_Image_8_Grey;
      Info        : Level_Table;
      Used        : Natural;
      First_Count : KL.Cared_Count;
   begin
      KL.Plan_Levels (Width, Height, Wanted, Min_Coarse_Side, Table, Levels,
                      Rows);
      KI.Create (Int32 (Width), Int32 (Rows), 0, Stack, Status);
      if not Succeeded (Status) then
         Out_Of_Memory (Status);
         return;
      end if;
      KL.Copy_Box (Source, X0, Y0, Stack.Pixels.all, Table (0));
      for L in 1 .. Levels - 1 loop
         KL.Downsample (Stack.Pixels.all, Table (L - 1), Table (L));
      end loop;
      if Mask /= null or else Region /= null then
         Build_Care (Mask, Int64 (X0) - Int64 (Mask_Offset_X),
                     Int64 (Y0) - Int64 (Mask_Offset_Y), Region, X0, Y0,
                     Table, Levels, Width, Rows, Care, Status);
         if not Succeeded (Status) then
            Free (Stack.Pixels);
            Free (Stack);
            return;
         end if;
      end if;
      Measure_Levels (Stack.Pixels.all, Care, Table, Levels, Width, Rows,
                      Info, Used, First_Count);
      if Used = 0 then
         Free (Stack.Pixels);
         Free (Stack);
         if Care /= null then
            Free (Care.Pixels);
         end if;
         Free (Care);
         if First_Count < Min_Cared_Pixels and then Region /= null then
            Bad (Status, "TrainRegion (TrainRegionMode "
                 & "PixelAlignedBoundingBoxAdjustMask) and TrainImageMask "
                 & "leave fewer than 64 pixels of the pattern cared for");
         elsif First_Count < Min_Cared_Pixels then
            Bad (Status, "TrainImageMask leaves fewer than 64 pixels of the "
                 & "pattern cared for");
         elsif Mask = null and then Region = null then
            Bad (Status, "Pattern cannot be trained: every pixel of "
                 & "TrainRegion has the same grey level");
         else
            Bad (Status, "Pattern cannot be trained: every cared-for pixel "
                 & "of TrainRegion has the same grey level");
         end if;
         return;
      end if;
      Pattern.Pixels := Stack;
      Pattern.Care := Care;
      Pattern.Levels := Used;
      Pattern.Info := Info;
      Pattern.Origin_X := Origin_X;
      Pattern.Origin_Y := Origin_Y;
      Pattern.Trained := True;
      Set_Success (Status);
   end Build_Trained;

   procedure Pattern_Train
     (Pattern             : in out Ks_CNL_Search_Pattern;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Pixel_From_Selected : KT.Ks_Transform_2D_Linear;
      Status              : out Ks_Status)
   is
   begin
      Pattern_Train_Masked (Pattern, Image, Region, Pixel_From_Selected,
                            null, 0, 0, Status);
   end Pattern_Train;

   procedure Pattern_Train_Masked
     (Pattern             : in out Ks_CNL_Search_Pattern;
      Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Pixel_From_Selected : KT.Ks_Transform_2D_Linear;
      Mask                : access constant KI.Ks_Image_8_Grey_Data;
      Mask_Offset_X       : Int32;
      Mask_Offset_Y       : Int32;
      Status              : out Ks_Status)
   is
      PX, PY : Long_Float;
   begin
      if Pattern = null then
         Allocate_Pattern (Pattern);
         if Pattern = null then
            Out_Of_Memory (Status);
            return;
         end if;
      elsif not Valid_Pattern (Pattern) then
         --  Reset to the default pattern, which is valid.
         Release_Pixels (Pattern.Pixels);
         Pattern.Params := Default_Train_Params;
         Untrain_Data (Pattern.all);
         Bad (Status, "Pattern is not a valid CNL search pattern");
         return;
      end if;
      Untrain_Data (Pattern.all);
      if Pattern.Params.Train_Region_Mode = Region_Mode_Affine_Transform then
         Bad (Status, "Pattern.TrainRegionMode AffineTransform needs an "
              & "affine rectangle TrainRegion "
              & "(ks_cnl_search_pattern_train_affine)");
         return;
      end if;
      Check_Image (Image, "TrainImage", Status);
      if not Succeeded (Status) then
         return;
      elsif Region = null then
         Bad (Status, "TrainRegion lies entirely outside TrainImage");
         return;
      elsif not KR.Valid_Region (Region)
        or else not KR.In_Image (Region, Image.Width, Image.Height)
      then
         Bad (Status, "TrainRegion does not lie in TrainImage");
         return;
      elsif Region.Width < Min_Pattern_Side
        or else Region.Height < Min_Pattern_Side
      then
         Bad (Status, "TrainRegion must span at least 8 x 8 pixels");
         return;
      elsif Region.Width > Max_Pattern_Side
        or else Region.Height > Max_Pattern_Side
      then
         Bad (Status, "TrainRegion must span at most 1024 x 1024 pixels");
         return;
      elsif not KT.Bounded (Pixel_From_Selected) then
         Bad (Status, "Pixel_From_Selected must be finite and within "
              & "1.0E150");
         return;
      elsif Mask /= null and then not KI.Valid_Image (Mask) then
         Bad (Status, "TrainImageMask is not a valid image handle");
         return;
      end if;
      KT.Map_Point (Pixel_From_Selected, Pattern.Params.Origin_X,
                    Pattern.Params.Origin_Y, PX, PY, Status);
      if not Succeeded (Status) then
         Bad (Status, "Pattern.OriginX, OriginY lie beyond 1.0E150 in "
              & "pixel space");
         return;
      end if;
      declare
         OX : constant Long_Float := PX - Long_Float (Region.X_Min);
         OY : constant Long_Float := PY - Long_Float (Region.Y_Min);
      begin
         if OX < -Max_Origin or else OX > Max_Origin
           or else OY < -Max_Origin or else OY > Max_Origin
         then
            Bad (Status, "Pattern.OriginX, OriginY lie more than 1.0E140 "
                 & "pixels from TrainRegion");
            return;
         end if;
         --  The region masks the box only when it does not fill it.
         if Masks_Region (Pattern.Params) and then Region.Flags /= null then
            Build_Trained (Pattern.all, Image.Pixels.all,
                           Natural (Region.X_Min), Natural (Region.Y_Min),
                           Natural (Region.Width), Natural (Region.Height),
                           Mask, Mask_Offset_X, Mask_Offset_Y, Region,
                           OX, OY, Status);
         else
            Build_Trained (Pattern.all, Image.Pixels.all,
                           Natural (Region.X_Min), Natural (Region.Y_Min),
                           Natural (Region.Width), Natural (Region.Height),
                           Mask, Mask_Offset_X, Mask_Offset_Y, null,
                           OX, OY, Status);
         end if;
      end;
   end Pattern_Train_Masked;

   procedure Restore_Trained
     (Pattern          : in out Ks_CNL_Search_Pattern;
      Pattern_Image    : access constant KI.Ks_Image_8_Grey_Data;
      Care_Image       : access constant KI.Ks_Image_8_Grey_Data;
      Origin_X         : Long_Float;
      Origin_Y         : Long_Float;
      Status           : out Ks_Status)
   is
   begin
      if Pattern = null then
         Allocate_Pattern (Pattern);
         if Pattern = null then
            Out_Of_Memory (Status);
            return;
         end if;
      elsif not Valid_Pattern (Pattern) then
         Release_Pixels (Pattern.Pixels);
         Pattern.Params := Default_Train_Params;
         Untrain_Data (Pattern.all);
         Bad (Status, "Pattern is not a valid CNL search pattern");
         return;
      end if;
      Untrain_Data (Pattern.all);
      Check_Image (Pattern_Image, "TrainedPatternImage", Status);
      if not Succeeded (Status) then
         return;
      elsif Pattern_Image.Width < Min_Pattern_Side
        or else Pattern_Image.Height < Min_Pattern_Side
        or else Pattern_Image.Width > Max_Pattern_Side
        or else Pattern_Image.Height > Max_Pattern_Side
      then
         Bad (Status, "TrainedPatternImage must have 8 .. 1024 pixels along "
              & "each side");
         return;
      elsif Care_Image /= null
        and then not (KI.Valid_Image (Care_Image)
                      and then Care_Image.Width = Pattern_Image.Width
                      and then Care_Image.Height = Pattern_Image.Height)
      then
         Bad (Status, "the trained care flags must be an image of the size "
              & "of TrainedPatternImage");
         return;
      elsif not (Origin_X >= -Max_Origin and then Origin_X <= Max_Origin
                 and then Origin_Y >= -Max_Origin
                 and then Origin_Y <= Max_Origin)
      then
         Bad (Status, "the trained origin must be finite and within 1.0E140");
         return;
      end if;
      Build_Trained (Pattern.all, Pattern_Image.Pixels.all, 0, 0,
                     Natural (Pattern_Image.Width),
                     Natural (Pattern_Image.Height), Care_Image, 0, 0,
                     null, Origin_X, Origin_Y, Status);
   end Restore_Trained;

   procedure Pattern_Trained
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Result  : out Int32;
      Status  : out Ks_Status)
   is
   begin
      Result := False_Value;
      if Pattern = null then
         Set_Success (Status);
      elsif not Valid_Pattern (Pattern) then
         Bad (Status, "Pattern is not a valid CNL search pattern");
      else
         Result := (if Pattern.Trained then True_Value else False_Value);
         Set_Success (Status);
      end if;
   end Pattern_Trained;

   procedure Pattern_Untrain
     (Pattern : Ks_CNL_Search_Pattern;
      Status  : out Ks_Status)
   is
   begin
      if Pattern = null then
         Set_Success (Status);
      elsif not Valid_Pattern (Pattern) then
         Release_Pixels (Pattern.Pixels);
         Pattern.Params := Default_Train_Params;
         Untrain_Data (Pattern.all);
         Bad (Status, "Pattern is not a valid CNL search pattern");
      else
         Untrain_Data (Pattern.all);
         Set_Success (Status);
      end if;
   end Pattern_Untrain;

   procedure Check_Trained
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Status  : out Ks_Status)
   with
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Operator_Not_Trained
                         | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Valid_Pattern (Pattern)
                            and then Is_Trained (Pattern));
   --  Operator_Not_Trained for a null or untrained pattern, Bad_Parameter
   --  for an inconsistent one.

   procedure Check_Trained
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Status  : out Ks_Status)
   is
   begin
      if not Is_Trained (Pattern) then
         Set_Failure (Status, Failure_Operator_Not_Trained,
                      "Pattern is not trained");
      elsif not Valid_Pattern (Pattern) then
         Bad (Status, "Pattern is not a valid CNL search pattern");
      else
         Set_Success (Status);
      end if;
   end Check_Trained;

   procedure Pattern_Trained_Size
     (Pattern       : access constant Ks_CNL_Search_Pattern_Data;
      Width, Height : out Int32;
      Status        : out Ks_Status)
   is
   begin
      Width := 0;
      Height := 0;
      Check_Trained (Pattern, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         G : constant Level_Geometry := Pattern.Info (0).Geometry;
      begin
         if G.Width < Min_Pattern_Side or else G.Height < Min_Pattern_Side
         then
            Bad (Status, "Pattern is not a valid CNL search pattern");
            return;
         end if;
         Width := Int32 (G.Width);
         Height := Int32 (G.Height);
      end;
   end Pattern_Trained_Size;

   procedure Pattern_Trained_Origin
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      X, Y    : out Long_Float;
      Status  : out Ks_Status)
   is
   begin
      X := 0.0;
      Y := 0.0;
      Check_Trained (Pattern, Status);
      if Succeeded (Status) then
         X := Pattern.Origin_X;
         Y := Pattern.Origin_Y;
      end if;
   end Pattern_Trained_Origin;

   procedure Pattern_Get_Trained_Pattern_Image
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Image   : out KI.Ks_Image_8_Grey;
      Status  : out Ks_Status)
   is
   begin
      Image := null;
      Check_Trained (Pattern, Status);
      if not Succeeded (Status) then
         return;
      end if;
      declare
         G : constant Level_Geometry := Pattern.Info (0).Geometry;
      begin
         if G.Width < Min_Pattern_Side or else G.Height < Min_Pattern_Side
         then
            Bad (Status, "Pattern is not a valid CNL search pattern");
            return;
         end if;
         KI.Create (Int32 (G.Width), Int32 (G.Height), 0, Image, Status);
         if not Succeeded (Status) then
            Out_Of_Memory (Status);
            return;
         end if;
         KL.Copy_Box (Pattern.Pixels.Pixels.all, 0, G.Row, Image.Pixels.all,
                      (Row => 0, Width => G.Width, Height => G.Height));
      end;
   end Pattern_Get_Trained_Pattern_Image;

   procedure Pattern_Get_Trained_Care_Image
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Image   : out KI.Ks_Image_8_Grey;
      Status  : out Ks_Status)
   is
   begin
      Image := null;
      Check_Trained (Pattern, Status);
      if not Succeeded (Status) or else Pattern.Care = null then
         return;
      end if;
      declare
         G : constant Level_Geometry := Pattern.Info (0).Geometry;
      begin
         if G.Width < Min_Pattern_Side or else G.Height < Min_Pattern_Side
         then
            Bad (Status, "Pattern is not a valid CNL search pattern");
            return;
         end if;
         KI.Create (Int32 (G.Width), Int32 (G.Height), 0, Image, Status);
         if not Succeeded (Status) then
            Out_Of_Memory (Status);
            return;
         end if;
         KL.Copy_Box (Pattern.Care.Pixels.all, 0, G.Row, Image.Pixels.all,
                      (Row => 0, Width => G.Width, Height => G.Height));
      end;
   end Pattern_Get_Trained_Care_Image;

   ---------------------------------------------------------------------
   --  Running
   ---------------------------------------------------------------------

   procedure Run_Params_Default
     (Params : out Ks_CNL_Search_Run_Params;
      Status : out Ks_Status)
   is
   begin
      Params := (others => <>);
      Set_Success (Status);
   end Run_Params_Default;

   function Run_Params_OK
     (Params : Ks_CNL_Search_Run_Params;
      Train  : Ks_CNL_Search_Train_Params) return Boolean
   is
     (Params.Algorithm in Algorithm_Linear_Search | Algorithm_Linear_CNLPAS
      and then Train.Algorithms >= 0
      and then Has_Flag (Train.Algorithms, Params.Algorithm)
      and then Params.Accuracy
                 in Accuracy_Very_Fine | Accuracy_Fine | Accuracy_Coarse
      and then Train.Accuracies >= 0
      and then Has_Flag (Train.Accuracies, Params.Accuracy)
      and then Params.Max_Results in 1 .. Max_Results_Limit
      and then Params.Accept_Threshold >= 0.0
      and then Params.Accept_Threshold <= 1.0
      and then Params.Confusion_Threshold >= Params.Accept_Threshold
      and then Params.Confusion_Threshold <= 1.0
      and then Params.XY_Overlap >= 0.0
      and then Params.XY_Overlap <= 1.0
      and then Params.Search_Region_Mode
                 in Region_Mode_Pixel_Aligned_Bounding_Box
                  | Region_Mode_Affine_Transform);

   procedure Check_Run_Params
     (Params : Ks_CNL_Search_Run_Params;
      Train  : Ks_CNL_Search_Train_Params;
      Status : out Ks_Status)
   with
     Pre  => Valid_Train_Params (Train),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Run_Params_OK (Params, Train));

   procedure Check_Run_Params
     (Params : Ks_CNL_Search_Run_Params;
      Train  : Ks_CNL_Search_Train_Params;
      Status : out Ks_Status)
   is
   begin
      if Params.Algorithm = Algorithm_Non_Linear_CNLPAS then
         Bad (Status, "RunParams.Algorithm NonLinearCNLPAS is not supported");
      elsif Params.Algorithm
              not in Algorithm_Linear_Search | Algorithm_Linear_CNLPAS
      then
         Bad (Status, "RunParams.Algorithm must be LinearSearch, "
              & "LinearCNLPAS or NonLinearCNLPAS");
      elsif not Has_Flag (Train.Algorithms, Params.Algorithm) then
         Bad (Status, "RunParams.Algorithm must be one of the pattern's "
              & "trained Algorithms");
      elsif Params.Accuracy
              not in Accuracy_Very_Fine | Accuracy_Fine | Accuracy_Coarse
      then
         Bad (Status, "RunParams.Accuracy must be VeryFine, Fine or Coarse");
      elsif not Has_Flag (Train.Accuracies, Params.Accuracy) then
         Bad (Status, "RunParams.Accuracy must be one of the pattern's "
              & "trained Accuracies");
      elsif Params.Max_Results not in 1 .. Max_Results_Limit then
         Bad (Status, "RunParams.MaxResults must be in 1 .. 1000");
      elsif not (Params.Accept_Threshold >= 0.0
                 and then Params.Accept_Threshold <= 1.0)
      then
         Bad (Status, "RunParams.AcceptThreshold must be in 0 .. 1");
      elsif not (Params.Confusion_Threshold >= 0.0
                 and then Params.Confusion_Threshold <= 1.0)
      then
         Bad (Status, "RunParams.ConfusionThreshold must be in 0 .. 1");
      elsif Params.Confusion_Threshold < Params.Accept_Threshold then
         Bad (Status, "RunParams.ConfusionThreshold must be >= "
              & "RunParams.AcceptThreshold");
      elsif not (Params.XY_Overlap >= 0.0 and then Params.XY_Overlap <= 1.0)
      then
         Bad (Status, "RunParams.XYOverlap must be in 0 .. 1");
      elsif Params.Search_Region_Mode
              not in Region_Mode_Pixel_Aligned_Bounding_Box
                   | Region_Mode_Affine_Transform
      then
         Bad (Status, "RunParams.SearchRegionMode must be "
              & "PixelAlignedBoundingBox or AffineTransform");
      else
         Set_Success (Status);
      end if;
   end Check_Run_Params;

   procedure Check_Partial
     (Params        : Ks_CNL_Search_Run_Params;
      Width, Height : Natural;
      Status        : out Ks_Status)
   with
     Pre  => Width <= Max_Pattern_Side and then Height <= Max_Pattern_Side,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Partial_OK (Params, Width, Height));
   --  The partial match parameters of a run with a trained pattern of
   --  Width x Height pixels.

   procedure Check_Partial
     (Params        : Ks_CNL_Search_Run_Params;
      Width, Height : Natural;
      Status        : out Ks_Status)
   is
      Half_Width  : constant Int32 := Int32 (Width / 2);
      Half_Height : constant Int32 := Int32 (Height / 2);
   begin
      if Params.Partial_Match_Limit_Left not in 0 .. Half_Width then
         Bad (Status, "RunParams.PartialMatchLimitLeft must be in 0 .. "
              & "TrainedPatternWidth / 2");
      elsif Params.Partial_Match_Limit_Right not in 0 .. Half_Width then
         Bad (Status, "RunParams.PartialMatchLimitRight must be in 0 .. "
              & "TrainedPatternWidth / 2");
      elsif Params.Partial_Match_Limit_Up not in 0 .. Half_Height then
         Bad (Status, "RunParams.PartialMatchLimitUp must be in 0 .. "
              & "TrainedPatternHeight / 2");
      elsif Params.Partial_Match_Limit_Down not in 0 .. Half_Height then
         Bad (Status, "RunParams.PartialMatchLimitDown must be in 0 .. "
              & "TrainedPatternHeight / 2");
      elsif Params.Partial_Match_Reduce_Score not in False_Value | True_Value
      then
         Bad (Status, "RunParams.PartialMatchReduceScore must be 0 or 1");
      elsif Params.Algorithm /= Algorithm_Linear_Search
        and then (Params.Partial_Match_Limit_Left /= 0
                  or else Params.Partial_Match_Limit_Right /= 0
                  or else Params.Partial_Match_Limit_Up /= 0
                  or else Params.Partial_Match_Limit_Down /= 0)
      then
         Bad (Status, "RunParams.PartialMatchLimitLeft, Right, Up and Down "
              & "must be 0 with LinearCNLPAS");
      else
         Set_Success (Status);
      end if;
   end Check_Partial;

   procedure Check_Search
     (Pattern : access constant Ks_CNL_Search_Pattern_Data;
      Params  : Ks_CNL_Search_Run_Params;
      Status  : out Ks_Status)
   is
   begin
      Check_Trained (Pattern, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Run_Params (Params, Pattern.Params, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Partial (Params, Pattern.Info (0).Geometry.Width,
                     Pattern.Info (0).Geometry.Height, Status);
   end Check_Search;

   subtype Trained_Data is Ks_CNL_Search_Pattern_Data
     with Dynamic_Predicate =>
       Valid_Data (Trained_Data) and then Trained_Data.Trained;
   --  A trained pattern (proved at each call, not executed).

   No_Care : constant KI.Grey_8_Matrix (0 .. 0, 0 .. 0) :=
     [others => [others => 1]];
   --  The care flags the search takes for a pattern without a mask (a
   --  plan that is not Masked never reads them).

   procedure Make_Plan
     (Pattern       : Trained_Data;
      Box_W, Box_H  : Positive;
      Pyramid       : Boolean;
      Left, Right   : KL.Margin;
      Up, Down      : KL.Margin;
      Reduce        : Boolean;
      Plan          : out KL.Search_Plan)
   with
     Pre  => Box_W <= Max_Search_Pixels and then Box_H <= Max_Search_Pixels
             and then Pattern.Info (0).Geometry.Width <= Box_W
             and then Pattern.Info (0).Geometry.Height <= Box_H
             and then 2 * Left <= Pattern.Info (0).Geometry.Width
             and then 2 * Right <= Pattern.Info (0).Geometry.Width
             and then 2 * Up <= Pattern.Info (0).Geometry.Height
             and then 2 * Down <= Pattern.Info (0).Geometry.Height
             and then (if Pyramid
                       then Left = 0 and then Right = 0 and then Up = 0
                            and then Down = 0),
     Post => KL.Valid_Plan (Plan)
             and then Plan.Image (0) = (Row => 0, Width => Box_W,
                                        Height => Box_H)
             and then Plan.Pattern (0).Geometry = Pattern.Info (0).Geometry
             and then Plan.Stack_Columns = Box_W
             and then Plan.Stack_Rows <= 2 * Box_H
             and then Plan.Sum_Columns = Box_W + 1
             and then Plan.Pattern_Rows = Natural (Pattern.Pixels.Height)
             and then Plan.Pattern_Columns = Natural (Pattern.Pixels.Width)
             and then Plan.Masked = (Pattern.Care /= null)
             and then Plan.Left = Left and then Plan.Right = Right
             and then Plan.Up = Up and then Plan.Down = Down
             and then Plan.Reduce = Reduce
             and then (for all L in 1 .. Plan.Levels - 1 =>
                         Plan.Image (L).Width = Plan.Image (L - 1).Width / 2
                         and then Plan.Image (L).Height
                                    = Plan.Image (L - 1).Height / 2);
   --  The plan of a search of a Box_W x Box_H box: one level, or with
   --  Pyramid as many as the pattern has and the box allows; with the
   --  partial match limits Left, Right, Up, Down (0 for a pyramid) and
   --  PartialMatchReduceScore (Reduce).

   procedure Make_Plan
     (Pattern       : Trained_Data;
      Box_W, Box_H  : Positive;
      Pyramid       : Boolean;
      Left, Right   : KL.Margin;
      Up, Down      : KL.Margin;
      Reduce        : Boolean;
      Plan          : out KL.Search_Plan)
   is
      Wanted : constant Positive := (if Pyramid then Pattern.Levels else 1);
      Table  : KL.Geometry_Table;
      Levels : Positive;
      Rows   : Positive;
      Used   : Positive := 1;
      Next   : Natural;
      Base   : KL.Base_Table := [others => 0];
      Levels_Of_Pattern : KL.Pattern_Table :=
        [others => ((0, 0, 0), 1, 0, 1)];
   begin
      KL.Plan_Levels (Box_W, Box_H, Wanted, 1, Table, Levels, Rows);
      Levels_Of_Pattern (0) :=
        (Geometry => Pattern.Info (0).Geometry,
         Count    => Pattern.Info (0).Count,
         Sum      => Pattern.Info (0).Sum,
         Spread   => Pattern.Info (0).Spread);
      Next := Box_H + 1;
      for L in 1 .. Levels - 1 loop
         pragma Loop_Invariant (Used = L and then L < Wanted and then Pyramid);
         pragma Loop_Invariant (Next <= L * (Max_Search_Pixels + 1));
         pragma Loop_Invariant
           (for all K in 0 .. L - 1 =>
              Base (K) < Next
              and then Table (K).Height < Next - Base (K)
              and then Levels_Of_Pattern (K).Geometry
                         = Pattern.Info (K).Geometry
              and then Levels_Of_Pattern (K).Geometry.Width
                         <= Table (K).Width
              and then Levels_Of_Pattern (K).Geometry.Height
                         <= Table (K).Height);
         declare
            G : constant Level_Geometry := Pattern.Info (L).Geometry;
         begin
            exit when G.Width > Table (L).Width
              or else G.Height > Table (L).Height;
            Base (L) := Next;
            Levels_Of_Pattern (L) :=
              (Geometry => G,
               Count    => Pattern.Info (L).Count,
               Sum      => Pattern.Info (L).Sum,
               Spread   => Pattern.Info (L).Spread);
            Next := Next + Table (L).Height + 1;
            Used := L + 1;
         end;
      end loop;
      pragma Assert (if Used > 1 then Pyramid);
      Plan := (Levels          => Used,
               Masked          => Pattern.Care /= null,
               Stack_Rows      => Rows,
               Stack_Columns   => Box_W,
               Sum_Rows        => Next,
               Sum_Columns     => Box_W + 1,
               Pattern_Rows    => Natural (Pattern.Pixels.Height),
               Pattern_Columns => Natural (Pattern.Pixels.Width),
               Image           => Table,
               Base            => Base,
               Pattern         => Levels_Of_Pattern,
               Left            => Left,
               Right           => Right,
               Up              => Up,
               Down            => Down,
               Reduce          => Reduce);
      pragma Assert (for all K in 0 .. Used - 1 =>
                       KL.Stacked (Table (K), Rows, Box_W)
                       and then Valid_Level (Pattern.Info (K),
                                             Pattern.Pixels.Width,
                                             Pattern.Pixels.Height));
      pragma Assert (for all K in 0 .. Used - 1 =>
                       2 * Plan.Left <= Plan.Pattern (K).Geometry.Width
                       and then 2 * Plan.Right
                                  <= Plan.Pattern (K).Geometry.Width
                       and then 2 * Plan.Up
                                  <= Plan.Pattern (K).Geometry.Height
                       and then 2 * Plan.Down
                                  <= Plan.Pattern (K).Geometry.Height);
      pragma Assert (for all K in 0 .. Used - 1 => KL.Level_Facts (Plan, K));
   end Make_Plan;

   function No_Margins (Plan : KL.Search_Plan) return Boolean is
     (Plan.Left = 0 and then Plan.Right = 0 and then Plan.Up = 0
      and then Plan.Down = 0);
   --  A search without partial matches.

   function Window_Coordinate
     (First, Last : Int32;
      P           : KS.Position;
      O           : KC.Offset) return Long_Float
   with
     Pre  => Last >= First,
     Post => Window_Coordinate'Result >= Long_Float (First)
             and then Window_Coordinate'Result <= Long_Float (Last);
   --  First + P + O, limited to First .. Last, which it never leaves: a
   --  refined position is a position of the level (the search area
   --  extended by the partial match limits), and an offset along an axis
   --  (at most one pixel) is found only when both neighbours along that
   --  axis are positions too.

   function Window_Coordinate
     (First, Last : Int32;
      P           : KS.Position;
      O           : KC.Offset) return Long_Float
   is
      Value : constant Long_Float :=
        Long_Float (First) + (Long_Float (P) + O);
   begin
      if Value < Long_Float (First) then
         return Long_Float (First);
      elsif Value > Long_Float (Last) then
         return Long_Float (Last);
      else
         return Value;
      end if;
   end Window_Coordinate;

   procedure Make_Item
     (Plan                : KL.Valid_Search_Plan;
      Image               : KL.Grey_8_Matrix;
      Sums                : KL.Sum_Matrix;
      Pattern             : KL.Grey_8_Matrix;
      Care                : KL.Grey_8_Matrix;
      Accuracy            : Int32;
      Ignore              : Boolean;
      M                   : KS.Match;
      ID                  : Int32;
      X_First, X_Last     : Int32;
      Y_First, Y_Last     : Int32;
      Origin_X, Origin_Y  : Long_Float;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Item                : out Found;
      Status              : out Ks_Status)
   with
     Pre  => KL.Matches (Plan, Image, Sums, Pattern, Care)
             and then X_First >= -Max_Pattern_Side
             and then Y_First >= -Max_Pattern_Side
             and then Int64 (X_Last)
                        = Int64 (X_First) + Int64 (KL.Last_X (Plan, 0))
             and then Int64 (Y_Last)
                        = Int64 (Y_First) + Int64 (KL.Last_Y (Plan, 0))
             and then Origin_X >= -Max_Origin and then Origin_X <= Max_Origin
             and then Origin_Y >= -Max_Origin and then Origin_Y <= Max_Origin,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Item_OK (Item.Item)
                            and then Item.Item.ID = ID
                            and then Item.Item.Score = M.Score
                            and then Placed (Item, X_First, X_Last, Y_First,
                                             Y_Last, Plan.Left, Plan.Right,
                                             Plan.Up, Plan.Down)
                            and then (if No_Margins (Plan)
                                      then Item.Item.Edge_Hit
                                             = Edge_Hit_None));
   --  The result for the chosen match M: its sub-pixel window position in
   --  the image (the box's first position at X_First, Y_First: the box's
   --  first pixel minus the limits Left and Up), its EdgeHit, its contrast
   --  and its location, the origin mapped with Selected_From_Pixel.
   --  Bad_Parameter when the location lies beyond 1.0E150.

   procedure Make_Item
     (Plan                : KL.Valid_Search_Plan;
      Image               : KL.Grey_8_Matrix;
      Sums                : KL.Sum_Matrix;
      Pattern             : KL.Grey_8_Matrix;
      Care                : KL.Grey_8_Matrix;
      Accuracy            : Int32;
      Ignore              : Boolean;
      M                   : KS.Match;
      ID                  : Int32;
      X_First, X_Last     : Int32;
      Y_First, Y_Last     : Int32;
      Origin_X, Origin_Y  : Long_Float;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Item                : out Found;
      Status              : out Ks_Status)
   is
      X       : constant KS.Position :=
        Natural'Min (M.X, KL.Last_X (Plan, 0));
      Y       : constant KS.Position :=
        Natural'Min (M.Y, KL.Last_Y (Plan, 0));
      --  M.X and M.Y are positions of level 0 (KS.Refine); the limits
      --  never act.
      Scores  : KC.Neighbourhood;
      Present : KC.Presence;
      OX, OY  : KC.Offset;
      WX, WY  : Long_Float;
      LX, LY  : Long_Float;
   begin
      Item := (others => <>);
      KS.Neighbours (Plan, Image, Sums, Pattern, Care, Ignore, X, Y, Scores,
                     Present);
      KC.Peak_Offset (Scores, Present, Accuracy, OX, OY);
      WX := Window_Coordinate (X_First, X_Last, X, OX);
      WY := Window_Coordinate (Y_First, Y_Last, Y, OY);
      KT.Map_Point (Selected_From_Pixel, WX + Origin_X, WY + Origin_Y, LX, LY,
                    Status);
      if not Succeeded (Status) then
         Bad (Status, "a result's location lies beyond 1.0E150");
         return;
      end if;
      pragma Assert
        (if No_Margins (Plan)
         then Edge_Hit_Within
                (WX, WY,
                 Int64 (X_First) + Int64 (Plan.Left),
                 Int64 (X_Last) - Int64 (Plan.Right),
                 Int64 (Y_First) + Int64 (Plan.Up),
                 Int64 (Y_Last) - Int64 (Plan.Down))
                = Edge_Hit_Within
                    (WX, WY, Int64 (X_First), Int64 (X_Last),
                     Int64 (Y_First), Int64 (Y_Last)));
      pragma Assert
        (Long_Float (Int64 (X_First)) = Long_Float (X_First)
         and then Long_Float (Int64 (X_Last)) = Long_Float (X_Last)
         and then Long_Float (Int64 (Y_First)) = Long_Float (Y_First)
         and then Long_Float (Int64 (Y_Last)) = Long_Float (Y_Last));
      pragma Assert
        (Edge_Hit_Within
           (WX, WY, Int64 (X_First), Int64 (X_Last), Int64 (Y_First),
            Int64 (Y_Last)) = Edge_Hit_None);
      Item :=
        (Item     => (ID                => ID,
                      Accepted          => True_Value,
                      Contrast_Computed => True_Value,
                      Edge_Hit          =>
                        Edge_Hit_Within
                          (WX, WY,
                           Int64 (X_First) + Int64 (Plan.Left),
                           Int64 (X_Last) - Int64 (Plan.Right),
                           Int64 (Y_First) + Int64 (Plan.Up),
                           Int64 (Y_Last) - Int64 (Plan.Down)),
                      Score             => M.Score,
                      Location_X        => LX,
                      Location_Y        => LY,
                      Contrast          =>
                        KC.Contrast_At (Plan, Image, Sums, Pattern, Care, 0,
                                        X, Y)),
         Window_X => WX,
         Window_Y => WY);
      pragma Assert (Placed_Facts (Item, X_First, X_Last, Y_First, Y_Last,
                                   Plan.Left, Plan.Right, Plan.Up,
                                   Plan.Down));
   end Make_Item;

   procedure Find
     (Plan                : KL.Valid_Search_Plan;
      Image               : KL.Grey_8_Matrix;
      Sums                : KL.Sum_Matrix;
      Pattern             : KL.Grey_8_Matrix;
      Care                : KL.Grey_8_Matrix;
      Params              : Ks_CNL_Search_Run_Params;
      Ignore              : Boolean;
      Origin_X            : Long_Float;
      Origin_Y            : Long_Float;
      X_Min, Y_Min        : Natural;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : Ks_CNL_Search_Results;
      Status              : out Ks_Status)
   with
     Pre  => KL.Matches (Plan, Image, Sums, Pattern, Care)
             and then Params.Max_Results in 1 .. Max_Results_Limit
             and then Params.Accept_Threshold >= 0.0
             and then Params.Accept_Threshold <= 1.0
             and then Params.Confusion_Threshold >= 0.0
             and then Params.Confusion_Threshold <= 1.0
             and then Params.XY_Overlap >= 0.0
             and then Params.XY_Overlap <= 1.0
             and then Origin_X >= -Max_Origin and then Origin_X <= Max_Origin
             and then Origin_Y >= -Max_Origin and then Origin_Y <= Max_Origin
             and then X_Min <= Natural (Int32'Last)
             and then Y_Min <= Natural (Int32'Last)
             and then Int64 (X_Min) + Int64 (KL.Last_X (Plan, 0))
                        <= Int64 (Int32'Last)
             and then Int64 (Y_Min) + Int64 (KL.Last_Y (Plan, 0))
                        <= Int64 (Int32'Last)
             and then KT.Bounded (Selected_From_Pixel)
             and then Results /= null and then Results.Items = null,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Gold_Results (Results)
                     and then Results.Count <= Natural (Params.Max_Results)
                     and then (for all I in 0 .. Results.Count - 1 =>
                                 Results.Items (I).Item.Score
                                   >= Params.Accept_Threshold)
                     and then Int64 (Results.Area_X_First)
                                = Int64 (X_Min) - Int64 (Plan.Left)
                     and then Int64 (Results.Area_Y_First)
                                = Int64 (Y_Min) - Int64 (Plan.Up)
                     and then Int64 (Results.Area_X_Last)
                                = Int64 (X_Min) - Int64 (Plan.Left)
                                  + Int64 (KL.Last_X (Plan, 0))
                     and then Int64 (Results.Area_Y_Last)
                                = Int64 (Y_Min) - Int64 (Plan.Up)
                                  + Int64 (KL.Last_Y (Plan, 0))
                     and then Results.Pattern_Width
                                = Int32 (Plan.Pattern (0).Geometry.Width)
                     and then Results.Pattern_Height
                                = Int32 (Plan.Pattern (0).Geometry.Height)
                     and then Results.Margin_Left = Plan.Left
                     and then Results.Margin_Right = Plan.Right
                     and then Results.Margin_Up = Plan.Up
                     and then Results.Margin_Down = Plan.Down
                     and then (if No_Margins (Plan)
                               then (for all I in 0 .. Results.Count - 1 =>
                                       Results.Items (I).Item.Edge_Hit
                                         = Edge_Hit_None)));
   --  The search on the prepared levels: the candidates of the coarsest
   --  level, followed down to level 0, the matches, and the results
   --  chosen among them, stored in Results (whose window positions are
   --  offset by X_Min - Left, Y_Min - Up: X_Min, Y_Min is the place of the
   --  box in the image, and the positions of level 0 start Left and Up
   --  before it).

   procedure Find
     (Plan                : KL.Valid_Search_Plan;
      Image               : KL.Grey_8_Matrix;
      Sums                : KL.Sum_Matrix;
      Pattern             : KL.Grey_8_Matrix;
      Care                : KL.Grey_8_Matrix;
      Params              : Ks_CNL_Search_Run_Params;
      Ignore              : Boolean;
      Origin_X            : Long_Float;
      Origin_Y            : Long_Float;
      X_Min, Y_Min        : Natural;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : Ks_CNL_Search_Results;
      Status              : out Ks_Status)
   is
      Coarsest   : constant Natural := Plan.Levels - 1;
      Capacity   : constant Positive :=
        (if Coarsest = 0 then Max_Candidates
         else Candidate_Limit (Params.Max_Results));
      Accept_At  : constant KC.Score_Value := Params.Accept_Threshold;
      Threshold  : constant KC.Score_Value :=
        (if Coarsest = 0 then Accept_At else Coarse_Factor * Accept_At);
      Max_Found  : constant Positive := Positive (Params.Max_Results);
      Width      : constant KL.Side := Plan.Pattern (0).Geometry.Width;
      Height     : constant KL.Side := Plan.Pattern (0).Geometry.Height;
      X_First    : constant Int32 := Int32 (X_Min) - Int32 (Plan.Left);
      Y_First    : constant Int32 := Int32 (Y_Min) - Int32 (Plan.Up);
      X_Last     : constant Int32 :=
        Int32 (Int64 (X_First) + Int64 (KL.Last_X (Plan, 0)));
      Y_Last     : constant Int32 :=
        Int32 (Int64 (Y_First) + Int64 (KL.Last_Y (Plan, 0)));
      Candidates : KS.Candidate_Array_Access;
      Rows       : KS.Score_Rows_Access;
      Matches    : KS.Match_Array_Access;
      Sure       : KS.Match_Array_Access;
      Chosen     : KS.Match_Array_Access;
      Kept       : Natural := 0;
      Count      : Natural;
      Taken      : Natural;
   begin
      --  The candidates.
      KS.Allocate_Candidates (Capacity, Candidates);
      if Candidates = null then
         Out_Of_Memory (Status);
         return;
      end if;
      KS.Allocate_Score_Rows (KL.Last_X (Plan, Coarsest) + 1, Rows);
      if Rows = null then
         Free (Candidates);
         Out_Of_Memory (Status);
         return;
      end if;
      KS.Scan (Plan, Image, Sums, Pattern, Care, Coarsest, Ignore, Threshold,
               Rows.all, Candidates.all, Kept);
      Free (Rows);

      --  The matches.
      KS.Allocate_Matches (Capacity, Matches);
      KS.Allocate_Matches (Max_Found, Sure);
      if Matches = null or else Sure = null then
         Free (Candidates);
         Free (Matches);
         Free (Sure);
         Out_Of_Memory (Status);
         return;
      end if;
      KS.Collect (Plan, Image, Sums, Pattern, Care, Ignore,
                  Accept_At, Params.Confusion_Threshold, Max_Found,
                  Params.XY_Overlap, Candidates.all, Kept, Matches.all,
                  Count, Sure.all);
      Free (Candidates);
      Free (Sure);

      --  The results.
      KS.Allocate_Matches (Max_Found, Chosen);
      if Chosen = null then
         Free (Matches);
         Out_Of_Memory (Status);
         return;
      end if;
      KS.Choose (Matches.all, Count, Max_Found, Accept_At, Params.XY_Overlap,
                 Width, Height, Chosen.all, Taken);
      Free (Matches);

      Results.Area_X_First := X_First;
      Results.Area_X_Last := X_Last;
      Results.Area_Y_First := Y_First;
      Results.Area_Y_Last := Y_Last;
      Results.Pattern_Width := Int32 (Width);
      Results.Pattern_Height := Int32 (Height);
      Results.Margin_Left := Plan.Left;
      Results.Margin_Right := Plan.Right;
      Results.Margin_Up := Plan.Up;
      Results.Margin_Down := Plan.Down;
      if Taken = 0 then
         Free (Chosen);
         Results.Count := 0;
         Set_Success (Status);
         return;
      end if;
      Allocate_Found (Taken, Results.Items);
      if Results.Items = null then
         Free (Chosen);
         Out_Of_Memory (Status);
         return;
      end if;
      Results.Count := Taken;
      for I in 0 .. Taken - 1 loop
         pragma Loop_Invariant
           (Results.Area_X_First = X_First
            and then Results.Area_X_Last = X_Last
            and then Results.Area_Y_First = Y_First
            and then Results.Area_Y_Last = Y_Last
            and then Results.Pattern_Width = Int32 (Width)
            and then Results.Pattern_Height = Int32 (Height)
            and then Results.Margin_Left = Plan.Left
            and then Results.Margin_Right = Plan.Right
            and then Results.Margin_Up = Plan.Up
            and then Results.Margin_Down = Plan.Down
            and then Results.Count = Taken
            and then Results.Items /= null
            and then Results.Items'First = 0
            and then Results.Items'Last = Taken - 1);
         pragma Loop_Invariant
           (for all K in 0 .. I - 1 =>
              Item_OK (Results.Items (K).Item)
              and then Results.Items (K).Item.ID = Int32 (K)
              and then Results.Items (K).Item.Score = Chosen (K).Score
              and then Placed (Results.Items (K), X_First, X_Last, Y_First,
                               Y_Last, Plan.Left, Plan.Right, Plan.Up,
                               Plan.Down)
              and then (if No_Margins (Plan)
                        then Results.Items (K).Item.Edge_Hit
                               = Edge_Hit_None));
         pragma Loop_Invariant
           (for all K in 0 .. I - 2 =>
              Results.Items (K).Item.Score
                >= Results.Items (K + 1).Item.Score);
         pragma Assert
           (I = 0 or else Chosen (I - 1).Score >= Chosen (I).Score);
         declare
            Item : Found;
         begin
            Make_Item (Plan, Image, Sums, Pattern, Care, Params.Accuracy,
                       Ignore, Chosen (I), Int32 (I), X_First, X_Last,
                       Y_First, Y_Last, Origin_X, Origin_Y,
                       Selected_From_Pixel, Item, Status);
            if not Succeeded (Status) then
               Free (Chosen);
               return;
            end if;
            Results.Items (I) := Item;
         end;
      end loop;
      pragma Assert
        (for all K in 0 .. Taken - 2 =>
           Results.Items (K).Item.Score >= Results.Items (K + 1).Item.Score);
      pragma Assert
        (for all K in 0 .. Results.Count - 1 =>
           Item_OK (Results.Items (K).Item)
           and then Results.Items (K).Item.ID = Int32 (K)
           and then Placed (Results.Items (K), Results.Area_X_First,
                            Results.Area_X_Last, Results.Area_Y_First,
                            Results.Area_Y_Last, Results.Margin_Left,
                            Results.Margin_Right, Results.Margin_Up,
                            Results.Margin_Down));
      Free (Chosen);
      Set_Success (Status);
   end Find;

   procedure Search_Box
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      X_Min, Y_Min        : Natural;
      Box_W, Box_H        : Positive;
      Pattern             : Trained_Data;
      Params              : Ks_CNL_Search_Run_Params;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : Ks_CNL_Search_Results;
      Status              : out Ks_Status)
   with
     Pre  => KI.Valid_Image (Image)
             and then Run_Params_OK (Params, Pattern.Params)
             and then Partial_OK (Params, Pattern.Info (0).Geometry.Width,
                                  Pattern.Info (0).Geometry.Height)
             and then Box_W <= Max_Search_Pixels
             and then Box_H <= Max_Search_Pixels
             and then Int64 (X_Min) + Int64 (Box_W) <= Int64 (Image.Width)
             and then Int64 (Y_Min) + Int64 (Box_H) <= Int64 (Image.Height)
             and then Pattern.Info (0).Geometry.Width <= Box_W
             and then Pattern.Info (0).Geometry.Height <= Box_H
             and then KT.Bounded (Selected_From_Pixel)
             and then Results /= null and then Results.Items = null,
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Gold_Results (Results)
                     and then Results.Count <= Natural (Params.Max_Results)
                     and then (for all I in 0 .. Results.Count - 1 =>
                                 Results.Items (I).Item.Score
                                   >= Params.Accept_Threshold)
                     and then Int64 (Results.Area_X_First)
                                + Int64 (Results.Margin_Left) = Int64 (X_Min)
                     and then Int64 (Results.Area_Y_First)
                                + Int64 (Results.Margin_Up) = Int64 (Y_Min)
                     and then Int64 (Results.Area_X_Last)
                                - Int64 (Results.Margin_Right)
                                + Int64 (Results.Pattern_Width)
                                = Int64 (X_Min) + Int64 (Box_W)
                     and then Int64 (Results.Area_Y_Last)
                                - Int64 (Results.Margin_Down)
                                + Int64 (Results.Pattern_Height)
                                = Int64 (Y_Min) + Int64 (Box_H)
                     and then Results.Pattern_Width >= 1
                     and then Results.Pattern_Height >= 1
                     and then Margins_OK (Results)
                     and then Int64 (Results.Margin_Left)
                                = Int64 (Params.Partial_Match_Limit_Left)
                     and then Int64 (Results.Margin_Right)
                                = Int64 (Params.Partial_Match_Limit_Right)
                     and then Int64 (Results.Margin_Up)
                                = Int64 (Params.Partial_Match_Limit_Up)
                     and then Int64 (Results.Margin_Down)
                                = Int64 (Params.Partial_Match_Limit_Down)
                     and then
                       (if Params.Partial_Match_Limit_Left = 0
                          and then Params.Partial_Match_Limit_Right = 0
                          and then Params.Partial_Match_Limit_Up = 0
                          and then Params.Partial_Match_Limit_Down = 0
                        then (for all I in 0 .. Results.Count - 1 =>
                                Results.Items (I).Item.Edge_Hit
                                  = Edge_Hit_None)));
   --  Searches the Box_W x Box_H box of Image at (X_Min, Y_Min): stacks
   --  the box's levels, builds their integral images and finds the
   --  results (Find), with the partial match limits of Params. Frees
   --  everything it allocates.

   procedure Search_Box
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      X_Min, Y_Min        : Natural;
      Box_W, Box_H        : Positive;
      Pattern             : Trained_Data;
      Params              : Ks_CNL_Search_Run_Params;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : Ks_CNL_Search_Results;
      Status              : out Ks_Status)
   is
      Ignore : constant Boolean :=
        Pattern.Params.Ignore_Polarity = True_Value
        and then Params.Algorithm = Algorithm_Linear_Search;
      Plan   : KL.Search_Plan;
      Stack  : KI.Ks_Image_8_Grey;
      Sums   : KL.Sum_Matrix_Access;
   begin
      Make_Plan (Pattern, Box_W, Box_H,
                 Params.Algorithm = Algorithm_Linear_CNLPAS,
                 KL.Margin (Params.Partial_Match_Limit_Left),
                 KL.Margin (Params.Partial_Match_Limit_Right),
                 KL.Margin (Params.Partial_Match_Limit_Up),
                 KL.Margin (Params.Partial_Match_Limit_Down),
                 Params.Partial_Match_Reduce_Score = True_Value, Plan);
      KI.Create (Int32 (Plan.Stack_Columns), Int32 (Plan.Stack_Rows), 0,
                 Stack, Status);
      if not Succeeded (Status) then
         Out_Of_Memory (Status);
         return;
      end if;
      KL.Copy_Box (Image.Pixels.all, X_Min, Y_Min, Stack.Pixels.all,
                   Plan.Image (0));
      for L in 1 .. Plan.Levels - 1 loop
         pragma Loop_Invariant
           (KI.Valid_Image (Stack)
            and then Stack.Width = Int32 (Plan.Stack_Columns)
            and then Stack.Height = Int32 (Plan.Stack_Rows));
         pragma Assert (KL.Level_OK (Plan, L - 1)
                        and then KL.Level_OK (Plan, L));
         KL.Downsample (Stack.Pixels.all, Plan.Image (L - 1), Plan.Image (L));
      end loop;
      KL.Allocate_Sums (Plan.Sum_Rows, Plan.Sum_Columns, Sums);
      if Sums = null then
         Free (Stack.Pixels);
         Free (Stack);
         Out_Of_Memory (Status);
         return;
      end if;
      for L in 0 .. Plan.Levels - 1 loop
         pragma Loop_Invariant
           (Sums /= null and then Sums'First (1) = 0
            and then Sums'Last (1) = Plan.Sum_Rows - 1
            and then Sums'First (2) = 0
            and then Sums'Last (2) = Plan.Sum_Columns - 1);
         pragma Assert (KL.Level_OK (Plan, L));
         KL.Build_Sums (Stack.Pixels.all, Plan.Image (L), Plan.Base (L),
                        Sums.all);
      end loop;
      if Pattern.Care = null then
         Find (Plan, Stack.Pixels.all, Sums.all, Pattern.Pixels.Pixels.all,
               No_Care, Params, Ignore, Pattern.Origin_X, Pattern.Origin_Y,
               X_Min, Y_Min, Selected_From_Pixel, Results, Status);
      else
         Find (Plan, Stack.Pixels.all, Sums.all, Pattern.Pixels.Pixels.all,
               Pattern.Care.Pixels.all, Params, Ignore, Pattern.Origin_X,
               Pattern.Origin_Y, X_Min, Y_Min, Selected_From_Pixel, Results,
               Status);
      end if;
      Free (Stack.Pixels);
      Free (Stack);
      Free (Sums);
   end Search_Box;

   procedure Execute
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Pattern             : access constant Ks_CNL_Search_Pattern_Data;
      Params              : Ks_CNL_Search_Run_Params;
      Selected_From_Pixel : KT.Ks_Transform_2D_Linear;
      Results             : out Ks_CNL_Search_Results;
      Status              : out Ks_Status)
   is
   begin
      Results := null;
      Check_Image (Image, "InputImage", Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Trained (Pattern, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Run_Params (Params, Pattern.Params, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Partial (Params, Pattern.Info (0).Geometry.Width,
                     Pattern.Info (0).Geometry.Height, Status);
      if not Succeeded (Status) then
         return;
      elsif Region /= null
        and then not (KR.Valid_Region (Region)
                      and then KR.In_Image (Region, Image.Width,
                                            Image.Height))
      then
         Bad (Status, "SearchRegion does not lie in InputImage");
         return;
      elsif not KT.Bounded (Selected_From_Pixel) then
         Bad (Status, "Selected_From_Pixel must be finite and within "
              & "1.0E150");
         return;
      end if;
      declare
         P : constant Level_Geometry := Pattern.Info (0).Geometry;
      begin
         if Region /= null
           and then (Region.Width > Max_Search_Pixels
                     or else Region.Height > Max_Search_Pixels
                     or else Int64 (Region.Width) * Int64 (Region.Height)
                               > Max_Search_Pixels)
         then
            Bad (Status, "SearchRegion: the search box must have at most "
                 & "16777216 pixels");
            return;
         end if;
         Allocate_Results (Results);
         if Results = null then
            Out_Of_Memory (Status);
            return;
         end if;
         if Region = null
           or else Natural (Region.Width) < P.Width
           or else Natural (Region.Height) < P.Height
         then
            --  No position: no results.
            Set_Success (Status);
            return;
         end if;
         Search_Box (Image, Natural (Region.X_Min), Natural (Region.Y_Min),
                     Natural (Region.Width), Natural (Region.Height),
                     Pattern.all, Params, Selected_From_Pixel, Results,
                     Status);
         if not Succeeded (Status) then
            Results_Destroy (Results);
         end if;
      end;
   end Execute;

   procedure Results_Destroy (Results : in out Ks_CNL_Search_Results) is
   begin
      if Results /= null then
         Free (Results.Items);
         Free (Results);
      end if;
   end Results_Destroy;

   procedure Results_Count
     (Results : access constant Ks_CNL_Search_Results_Data;
      Count   : out Int32;
      Status  : out Ks_Status)
   is
   begin
      Count := 0;
      if Results = null then
         Set_Success (Status);
      elsif not Valid_Results (Results) then
         Bad (Status, "Results is not a valid CNL search results handle");
      else
         Count := Int32 (Results.Count);
         Set_Success (Status);
      end if;
   end Results_Count;

   procedure Results_Item
     (Results : access constant Ks_CNL_Search_Results_Data;
      Index   : Int32;
      Item    : out Ks_CNL_Search_Result;
      Status  : out Ks_Status)
   is
   begin
      Item := (others => <>);
      if Results /= null and then not Valid_Results (Results) then
         Bad (Status, "Results is not a valid CNL search results handle");
      elsif Results = null or else Index < 0
        or else Index >= Int32 (Results.Count)
      then
         Set_Failure (Status, Failure_Index_Out_Of_Range,
                      "Item: the index is outside 0 .. Count - 1");
      else
         Item := Results.Items (Natural (Index)).Item;
         Set_Success (Status);
      end if;
   end Results_Item;

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   procedure Check_Stream_Code
     (Code        : U32;
      Masked      : out Boolean;
      Region_Mode : out Boolean;
      Status      : out Ks_Status) is
   begin
      Masked := Code in Stream_Code_Masked | Stream_Code_Region_Mode;
      Region_Mode := Code = Stream_Code_Region_Mode;
      if Code in Stream_Code | Stream_Code_Masked | Stream_Code_Region_Mode
      then
         Set_Success (Status);
      else
         Set_Failure (Status, Failure_Image_File,
                      "Ks_CNL_Search_Pattern'Read: not a CNL search pattern");
      end if;
   end Check_Stream_Code;

   procedure Check_Stream_Flag
     (Value  : U32;
      Flag   : out Boolean;
      Status : out Ks_Status)
   is
   begin
      Flag := Value = 1;
      if Value <= 1 then
         Set_Success (Status);
      else
         Set_Failure (Status, Failure_Image_File,
                      "Ks_CNL_Search_Pattern'Read: a flag must be 0 or 1");
      end if;
   end Check_Stream_Flag;

end AMV.Kernels.CNL_Search;
