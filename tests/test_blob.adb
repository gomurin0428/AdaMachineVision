--  Tests for AMV.Blob (the blob tool) and its kernel AMV.Kernels.Blob.
--
--  The scenes are drawn with AMV_Test_Images. Rectangles with edges on
--  pixel boundaries (multiples of 1/8 pixel) are rendered exactly, so
--  their areas, centroids, moments and boxes are checked exactly (up to
--  rounding); circles and turned rectangles are checked against analytic
--  values with tolerances from the accuracy notes of AMV_Test_Images
--  (thresholding at mid grey counts a pixel when about half of it is
--  covered, so the area of a disc of radius 15 is within about 1 percent
--  and its centroid within a few hundredths of a pixel).

pragma Validity_Checks ("F");
--  The kernel tests pass NaNs on purpose.

with Ada.Containers.Generic_Array_Sort;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Text_IO;

with Interfaces;

with AMV;                    use AMV;
with AMV.Blob;               use AMV.Blob;
with AMV.Coordinate_Spaces;  use AMV.Coordinate_Spaces;
with AMV.Images;             use AMV.Images;
with AMV.Kernels;
with AMV.Kernels.Blob;
with AMV.Kernels.Images;
with AMV.Kernels.Regions;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;
with AMV.Misc;
with AMV.Shapes;             use AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;              use AMV.Tools;
with AMV.Transforms;         use AMV.Transforms;
with AMV_Test_Images;        use AMV_Test_Images;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_Blob is

   package KB renames AMV.Kernels.Blob;
   package KI renames AMV.Kernels.Images;
   package KR renames AMV.Kernels.Regions;
   package KS renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;
   package RH renames AMV.Shapes.Region_Holders;

   use type AMV.Kernels.Int32;
   use type KB.Ks_Blob_Results;
   use type KI.Ks_Image_8_Grey;
   use type KI.Ks_Image_16_Grey;
   use type KS.Ks_Polygon;
   use type KB.Ks_Blob_Result;
   use type KB.Ks_Blob_Segmentation_Params;
   use type Interfaces.Unsigned_16;

   subtype Int32 is AMV.Kernels.Int32;

   Pi : constant := AMV.Misc.Pi;

   Sqrt_2 : constant := 1.41421_35623_73095_04880;

   function Img (N : Integer) return String is (Integer'Image (N));

   function Light_Tool (Image : Ks_Image_8_Grey) return Ks_Blob_Tool;
   --  A tool for light blobs at the fixed threshold 128, without sorting
   --  and with cleanup at the default 10 pixels.

   function Light_Tool (Image : Ks_Image_8_Grey) return Ks_Blob_Tool is
   begin
      return Tool : Ks_Blob_Tool do
         Tool.Input_Image := Image;
         Tool.Run_Params.Segmentation_Params.Mode :=
           Code (Hard_Fixed_Threshold);
         Tool.Run_Params.Segmentation_Params.Polarity := Code (Light_Blobs);
         Tool.Run_Params.Sort_Enabled := Code (False);
      end return;
   end Light_Tool;

   procedure Check_Accept (Tool : Ks_Blob_Tool'Class; What : String);

   procedure Check_Accept (Tool : Ks_Blob_Tool'Class; What : String) is
   begin
      Check (Tool.Run_Status.Result = Accept_Result,
             What & ": Accept_Result (" & Tool.Run_Status.Message & ")");
   end Check_Accept;

   function Count (Tool : Ks_Blob_Tool; Filtered : Boolean := True)
                   return Natural
   is (Tool.Results.Get_Blobs (Filtered).Count);

   function Blob (Tool : Ks_Blob_Tool; Index : Natural;
                  Filtered : Boolean := True) return Ks_Blob_Result
   is (Tool.Results.Get_Blobs (Filtered).Item (Index));

   ---------------------------------------------------------------------
   --  Defaults and a plain rectangle
   ---------------------------------------------------------------------

   procedure Test_Defaults is
      Params : constant Ks_Blob := (others => <>);
      Tool   : Ks_Blob_Tool;
      Image  : Ks_Image_8_Grey := Blank (100, 80, 200);
   begin
      Section ("Blob: defaults");
      Check (Params.Segmentation_Params.Mode = Code (Hard_Dynamic_Threshold)
             and then Params.Segmentation_Params.Polarity = Code (Dark_Blobs)
             and then Params.Segmentation_Params.Hard_Fixed_Threshold = 128
             and then Params.Segmentation_Params.Hard_Relative_Threshold
                        = 50
             and then Params.Segmentation_Params.Tail_Low = 0
             and then Params.Segmentation_Params.Tail_High = 0,
             "segmentation defaults (VisionPro's)");
      Check (Params.Connectivity_Mode = Code (Grey_Scale)
             and then Params.Connectivity_Cleanup = Code (Fill)
             and then Params.Connectivity_Min_Pixels = 10
             and then Params.Sort_Enabled = Code (True)
             and then Params.Sort_Measure = Code (Area)
             and then Params.Sort_Ascending = Code (False)
             and then Params.Run_Time_Measures.Count = 0
             and then Params.Morphology_Operations.Count = 0,
             "run parameter defaults (VisionPro's)");
      Check (Code (Whole_Image_Grey_Scale) = 2 and then Code (Not_Clipped) = 42
             and then Code (Bounding_Box_Principal_Axis_Width) = 39
             and then Code (Bounding_Box_Pixel_Aligned_No_Exclude_Min_Y) = 19
             and then Code (Exclude_Blobs_In_Range) = 0
             and then Code (Pixel_Aligned) = 3 and then Code (Open_Square) = 11
             and then Code (Pre_Compute) = 1 and then Code (Hole) = 0,
             "codes are VisionPro's values");
      Check (Count (Tool) = 0 and then Count (Tool, False) = 0,
             "no results before the first run");

      --  Dark blob on a light background, every default.
      Draw_Rectangle (Image, 40.5, 30.5, 20.0, 10.0, Value => 40);
      Tool.Input_Image := Image;
      Tool.Run;
      Check_Accept (Tool, "defaults");
      Check (Count (Tool) = 1, "one dark blob with the defaults");
      Check_Near (Blob (Tool, 0).Area, 200.0, 1.0E-9, "its area");
   end Test_Defaults;

   procedure Test_Rectangle is
      Image : Ks_Image_8_Grey := Blank (100, 80);
      Tool  : Ks_Blob_Tool;
      R     : Ks_Blob_Result;
   begin
      Section ("Blob: rectangle measures");
      --  Pixels 31 .. 50 by 26 .. 35, rendered exactly.
      Draw_Rectangle (Image, 40.5, 30.5, 20.0, 10.0);
      Tool := Light_Tool (Image);
      Tool.Run;
      Check_Accept (Tool, "rectangle");
      Check (Count (Tool) = 1 and then Count (Tool, False) = 1,
             "one blob");
      R := Blob (Tool, 0);
      Check (R.ID = 0 and then R.Label = 1 and then R.Parent_ID = -1
             and then R.Pixel_Count = 200 and then R.Num_Children = 0
             and then R.Filtered_Out = 0 and then R.Not_Clipped = 1,
             "ID, Label, Parent_ID, Pixel_Count, flags");
      Check_Near (R.Area, 200.0, 1.0E-9, "Area");
      Check_Near (R.Center_Of_Mass_X, 40.5, 1.0E-9, "Center_Of_Mass_X");
      Check_Near (R.Center_Of_Mass_Y, 30.5, 1.0E-9, "Center_Of_Mass_Y");
      --  Second moments of the pixel squares: w h**3 / 12 and h w**3 / 12.
      Check_Near (R.Inertia_X, 20.0 * 1000.0 / 12.0, 1.0E-6, "Inertia_X");
      Check_Near (R.Inertia_Y, 10.0 * 8000.0 / 12.0, 1.0E-6, "Inertia_Y");
      Check_Near (R.Inertia_Min, R.Inertia_X, 1.0E-6, "Inertia_Min");
      Check_Near (R.Inertia_Max, R.Inertia_Y, 1.0E-6, "Inertia_Max");
      Check_Near (R.Elongation, 4.0, 1.0E-9, "Elongation (w / h)**2");
      Check_Near (R.Angle, 0.0, 1.0E-12, "Angle along the long side");
      --  Marching squares: the straight runs plus four cut corners.
      Check_Near (R.Perimeter, 2.0 * 19.0 + 2.0 * 9.0 + 2.0 * Sqrt_2,
                  1.0E-9, "Perimeter");
      Check_Near (R.Acircularity, R.Perimeter ** 2 / (4.0 * Pi * 200.0),
                  1.0E-9, "Acircularity");
      Check_Near (R.Pixel_Aligned_Min_X, 30.5, 1.0E-9, "box Min_X");
      Check_Near (R.Pixel_Aligned_Max_X, 50.5, 1.0E-9, "box Max_X");
      Check_Near (R.Pixel_Aligned_Min_Y, 25.5, 1.0E-9, "box Min_Y");
      Check_Near (R.Pixel_Aligned_Max_Y, 35.5, 1.0E-9, "box Max_Y");
      Check_Near (R.Pixel_Aligned_Width, 20.0, 1.0E-9, "box Width");
      Check_Near (R.Pixel_Aligned_Height, 10.0, 1.0E-9, "box Height");
      Check_Near (R.Pixel_Aligned_Center_X, 40.5, 1.0E-9, "box Center_X");
      Check_Near (R.Pixel_Aligned_Aspect, 0.5, 1.0E-9, "box Aspect");
      Check_Near (R.Principal_Axis_Width, 20.0, 1.0E-9, "principal Width");
      Check_Near (R.Principal_Axis_Height, 10.0, 1.0E-9, "principal Height");
      Check_Near (R.Principal_Axis_Min_X, -10.0, 1.0E-9, "principal Min_X");
      Check_Near (R.Principal_Axis_Max_Y, 5.0, 1.0E-9, "principal Max_Y");
      Check_Near (Get_Measure (R, Area), R.Area, 0.0, "Get_Measure (Area)");
      Check_Near (Get_Measure (R, Bounding_Box_Principal_Axis_Aspect), 0.5,
                  1.0E-9, "Get_Measure (principal Aspect)");
      Check_Near (Get_Measure (R, Not_Clipped), 1.0, 0.0,
                  "Get_Measure (Not_Clipped)");
      Check_Near (Get_Measure (R, Label), 1.0, 0.0, "Get_Measure (Label)");
      declare
         Box : constant Ks_Rectangle_Affine :=
           Get_Bounding_Box (R, Pixel_Aligned);
         P   : constant Ks_Rectangle_Affine :=
           Get_Bounding_Box (R, Principal);
         S   : constant Ks_Rectangle_Affine :=
           Get_Bounding_Box (R, Selected_Space);
      begin
         Check_Near (Box.Center_X, 40.5, 1.0E-9, "pixel-aligned box centre");
         Check_Near (Box.Side_X_Length, 20.0, 1.0E-9,
                     "pixel-aligned box side X");
         Check_Near (Box.Side_Y_Length, 10.0, 1.0E-9,
                     "pixel-aligned box side Y");
         Check_Near (P.Center_Y, 30.5, 1.0E-9, "principal box centre");
         Check_Near (P.Side_X_Length, 20.0, 1.0E-9, "principal box side X");
         Check_Near (S.Side_Y_Length, 10.0, 1.0E-9, "selected box side Y");
      end;
   end Test_Rectangle;

   ---------------------------------------------------------------------
   --  Circles, polarity and holes
   ---------------------------------------------------------------------

   procedure Test_Circle_And_Polarity is
      Image : Ks_Image_8_Grey := Blank (100, 80);
      Dark  : Ks_Image_8_Grey := Blank (100, 80, 255);
      Tool  : Ks_Blob_Tool;
      R     : Ks_Blob_Result;
   begin
      Section ("Blob: circle and polarity");
      Draw_Circle (Image, 50.3, 40.7, 15.0);
      Tool := Light_Tool (Image);
      Tool.Run;
      Check_Accept (Tool, "circle");
      Check (Count (Tool) = 1, "one disc");
      R := Blob (Tool, 0);
      --  About 1 percent: the pixels at least half covered.
      Check_Near (R.Area, Pi * 225.0, 0.01 * Pi * 225.0, "disc area");
      Check_Near (R.Center_Of_Mass_X, 50.3, 0.05, "disc centre X");
      Check_Near (R.Center_Of_Mass_Y, 40.7, 0.05, "disc centre Y");
      Check (R.Elongation in 1.0 .. 1.05, "disc elongation near 1");
      --  The marching-squares length runs about 5 percent long on curves.
      Check (R.Acircularity in 1.0 .. 1.2,
             "disc acircularity" & R.Acircularity'Image);
      Check_Near (R.Perimeter, 2.0 * Pi * 15.0, 0.1 * 2.0 * Pi * 15.0,
                  "disc perimeter");

      --  The same disc, dark on light.
      Draw_Circle (Dark, 50.3, 40.7, 15.0, Value => 0);
      Tool.Input_Image := Dark;
      Tool.Run_Params.Segmentation_Params.Polarity := Code (Dark_Blobs);
      Tool.Run;
      Check_Accept (Tool, "dark blobs");
      Check (Count (Tool) = 1, "dark blobs: the disc");
      R := Blob (Tool, 0);
      Check_Near (R.Area, Pi * 225.0, 0.01 * Pi * 225.0, "dark disc area");
      Check_Near (R.Center_Of_Mass_X, 50.3, 0.05, "dark disc centre X");
      Tool.Run_Params.Segmentation_Params.Polarity := Code (Light_Blobs);
      Tool.Run;
      Check (Count (Tool) = 2
             and then Tool.Results.Get_Blob_By_ID (0).Pixel_Count
                        = 100 * 80 - R.Pixel_Count,
             "light blobs: the background is the blob");
      Check (Tool.Results.Get_Blob_By_ID (0).Num_Children = 1
             and then Tool.Results.Get_Blob_By_ID (1).Pixel_Count
                        = R.Pixel_Count
             and then Tool.Results.Get_Blob_By_ID (1).Label = 0,
             "the disc is its hole");
      Check (Tool.Results.Get_Blob_By_ID (0).Not_Clipped = 0,
             "the background touches the image edge");
   end Test_Circle_And_Polarity;

   procedure Test_Holes is
      Image : Ks_Image_8_Grey := Blank (100, 80);
      Tool  : Ks_Blob_Tool;
      Ring  : Ks_Blob_Result;
      Hole  : Ks_Blob_Result;
   begin
      Section ("Blob: holes");
      Draw_Annulus (Image, 50.3, 40.7, 8.0, 15.0);
      Tool := Light_Tool (Image);
      Tool.Run;
      Check_Accept (Tool, "ring");
      Check (Count (Tool, False) = 2, "a ring and its hole");
      Ring := Tool.Results.Get_Blob_By_ID (0);
      Hole := Tool.Results.Get_Blob_By_ID (1);
      Check (Ring.Label = Code (AMV.Blob.Blob) and then Hole.Label = 0,
             "labels: blob 1, hole 0");
      Check (Ring.Num_Children = 1 and then Ring.Num_Unfiltered_Children = 1
             and then Hole.Num_Children = 0,
             "the ring has one child");
      Check (Tool.Results.Get_Parent (1) = 0
             and then Tool.Results.Get_Parent (0) = -1
             and then Hole.Parent_ID = 0,
             "the hole's parent is the ring");
      Check_Near (Ring.Area, Pi * (225.0 - 64.0), 0.015 * Pi * 161.0,
                  "annulus area");
      Check_Near (Hole.Area, Pi * 64.0, 0.02 * Pi * 64.0, "hole area");
      Check_Near (Hole.Center_Of_Mass_X, 50.3, 0.05, "hole centre");
      Check (Hole.Not_Clipped = 1, "the hole is not clipped");
      --  Sorted by area, descending: the ring first.
      Tool.Run_Params.Sort_Enabled := Code (True);
      Tool.Run;
      Check (Blob (Tool, 0).ID = 0 and then Blob (Tool, 1).ID = 1,
             "sorted by area");
      --  Boundaries: the hole's outer boundary encloses exactly its
      --  pixels, the ring's encloses the ring and the hole.
      declare
         Ring_Boundary : constant Ks_Polygon := Tool.Results.Get_Boundary (0);
         Hole_Boundary : constant Ks_Polygon := Tool.Results.Get_Boundary (1);
      begin
         Check_Near (Hole_Boundary.Area, Real (Hole.Pixel_Count), 1.0E-9,
                     "hole boundary encloses its pixels");
         Check_Near (Ring_Boundary.Area,
                     Real (Ring.Pixel_Count + Hole.Pixel_Count), 1.0E-9,
                     "ring boundary encloses ring and hole");
         Check (Ring_Boundary.Num_Vertices > 8, "ring boundary vertices");
      end;
      --  Filled away when smaller than the minimum.
      Tool.Run_Params.Connectivity_Min_Pixels := 300;
      Tool.Run;
      Check (Count (Tool, False) = 1
             and then Blob (Tool, 0).Pixel_Count
                        = Ring.Pixel_Count + Hole.Pixel_Count,
             "Fill: the hole joins the ring");
   end Test_Holes;

   ---------------------------------------------------------------------
   --  The feature tree: children, siblings, top level, IDs and measures
   ---------------------------------------------------------------------

   procedure Test_Tree is
      Image : Ks_Image_8_Grey := Blank (170, 100);
      Tool  : Ks_Blob_Tool;

      type Relation is (Children, Siblings, Top_Level);

      function Expected
        (Results  : Ks_Blob_Results;
         Kind     : Relation;
         ID       : Integer;
         Filtered : Boolean) return Ks_Blob_ID_Array;
      --  The IDs a query should give, by a plain search over Get_Blobs.

      function Expected
        (Results  : Ks_Blob_Results;
         Kind     : Relation;
         ID       : Integer;
         Filtered : Boolean) return Ks_Blob_ID_Array
      is
         Blobs  : constant Ks_Blob_Result_Collection'Class :=
           Results.Get_Blobs (Filtered);
         List   : Ks_Blob_ID_Array (0 .. Blobs.Count - 1);
         Found  : Natural := 0;
         Parent : constant Integer :=
           (if Kind = Siblings then Results.Get_Parent (ID) else -1);
      begin
         for I in 0 .. Blobs.Count - 1 loop
            declare
               R : constant Ks_Blob_Result := Blobs.Item (I);
               P : constant Integer := Integer (R.Parent_ID);
            begin
               if (case Kind is
                     when Children  => P = ID,
                     when Siblings  => Integer (R.ID) /= ID and then P = Parent,
                     when Top_Level => P = -1)
               then
                  List (Found) := Integer (R.ID);
                  Found := Found + 1;
               end if;
            end;
         end loop;
         return List (0 .. Found - 1);
      end Expected;

      function IDs_Of
        (Collection : Ks_Blob_Result_Collection'Class) return Ks_Blob_ID_Array
      is
         List : Ks_Blob_ID_Array (0 .. Collection.Count - 1);
      begin
         for I in List'Range loop
            List (I) := Integer (Collection.Item (I).ID);
         end loop;
         return List;
      end IDs_Of;

      function Same (Left, Right : Ks_Blob_ID_Array) return Boolean is
        (Left'Length = Right'Length
         and then (for all I in 0 .. Left'Length - 1 =>
                     Left (Left'First + I) = Right (Right'First + I)));

      procedure Check_All (What : String);
      --  Every query of every feature, filtered and not, against Expected.

      procedure Check_All (What : String) is
         Results : constant Ks_Blob_Results := Tool.Results;
         Total   : constant Natural := Count (Tool, False);
         Good    : Boolean := True;
      begin
         for Filtered in Boolean loop
            Good := Good
              and then Same (IDs_Of (Results.Get_Top_Level_Blobs (Filtered)),
                             Expected (Results, Top_Level, 0, Filtered));
            for ID in 0 .. Total - 1 loop
               Good := Good
                 and then Same
                            (IDs_Of (Results.Get_Children (ID, Filtered)),
                             Expected (Results, Children, ID, Filtered))
                 and then Same
                            (IDs_Of (Results.Get_Siblings (ID, Filtered)),
                             Expected (Results, Siblings, ID, Filtered));
            end loop;
            Good := Good
              and then Same (Results.Get_Blob_IDs (Filtered),
                             IDs_Of (Results.Get_Blobs (Filtered)))
              and then Results.Get_Blob_IDs (Filtered)'First = 0;
         end loop;
         Check (Good, What & ": every query gives the features of a plain"
                & " search, in the collection's order");
      end Check_All;
   begin
      Section ("Blob: the feature tree");
      --  A big ring with a square inside its hole, a smaller ring, and a
      --  small square: top level the two rings and the small square; the
      --  big ring's child its hole, whose child the inner square; the
      --  small ring's child its hole.
      Draw_Annulus (Image, 40.3, 50.7, 14.0, 30.0);
      Draw_Rectangle (Image, 40.5, 50.5, 8.0, 8.0);
      Draw_Annulus (Image, 110.3, 50.7, 8.0, 16.0);
      Draw_Rectangle (Image, 155.5, 15.5, 6.0, 6.0);
      Tool := Light_Tool (Image);
      Tool.Run;
      Check_Accept (Tool, "tree");
      Check (Count (Tool, False) = 6, "six features");
      declare
         Results : constant Ks_Blob_Results := Tool.Results;
         Top     : constant Ks_Blob_Result_Collection'Class :=
           Results.Get_Top_Level_Blobs (False);
         Holes   : Natural := 0;
      begin
         Check (Top.Count = 3, "three top-level features");
         for I in 0 .. Top.Count - 1 loop
            declare
               Children : constant Ks_Blob_Result_Collection'Class :=
                 Results.Get_Children (Integer (Top.Item (I).ID), False);
            begin
               if Children.Count = 1 then
                  Holes := Holes + 1;
                  Check (Children.Item (0).Label = 0
                         and then Results.Get_Siblings
                                    (Integer (Top.Item (I).ID), False).Count
                                  = 2,
                         "a ring's child is its hole; it has two siblings");
               end if;
            end;
         end loop;
         Check (Holes = 2, "two rings with a hole each");
         Check (Results.Get_Siblings (Integer (Top.Item (0).ID), True).Count
                = 2, "filtered siblings without a filter: the other two");
      end;
      Check_All ("unsorted, unfiltered");

      --  Sorted by area and filtered: the holes (Label 0) and the small
      --  square (36 pixels) go.
      Tool.Run_Params.Sort_Enabled := Code (True);
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (Label, Filter, Include_Blobs_In_Range, 0.5, 1.5));
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (Area, Filter, Include_Blobs_In_Range, 50.0,
                         100_000.0));
      Tool.Run;
      Check_All ("sorted and filtered");
      declare
         Results : constant Ks_Blob_Results := Tool.Results;
         Top     : constant Ks_Blob_ID_Array :=
           IDs_Of (Results.Get_Top_Level_Blobs (True));
      begin
         Check (Top'Length = 2
                and then Results.Get_Blob_By_ID (Top (0)).Area
                         > Results.Get_Blob_By_ID (Top (1)).Area,
                "filtered top level: the two rings, larger first");
         Check (Results.Get_Children (Top (0), True).Count = 0
                and then Results.Get_Children (Top (0), False).Count = 1,
                "the hole is filtered out of the children");
      end;

      --  Measures by ID.
      declare
         Results : constant Ks_Blob_Results := Tool.Results;
         IDs     : constant Ks_Blob_ID_Array (5 .. 7) := [3, 0, 5];
         Values  : constant Ks_Blob_Measure_Array :=
           Results.Get_Blob_Measures (Area, IDs);
         Empty   : constant Ks_Blob_ID_Array (1 .. 0) := [others => 0];
      begin
         Check (Values'First = 5 and then Values'Last = 7
                and then (for all K in IDs'Range =>
                            Values (K)
                            = Results.Get_Blob_By_ID (IDs (K)).Area),
                "Get_Blob_Measures: each ID's area, with the bounds of IDs");
         Check (Results.Get_Blob_Measure (Center_Mass_X, 4)
                = Get_Measure (Results.Get_Blob_By_ID (4), Center_Mass_X),
                "Get_Blob_Measure");
         Check (Results.Get_Blob_Measures (Area, Empty)'Length = 0,
                "Get_Blob_Measures of no ID");
      end;

      --  Errors and empty results.
      declare
         Results : constant Ks_Blob_Results := Tool.Results;
         Never   : Ks_Blob_Results;
         Default : Ks_Blob_Result_Collection;
         procedure Bad_Child;
         procedure Bad_Child is
         begin
            Check (Results.Get_Children (6, False).Count = 0, "unreachable");
         end Bad_Child;
         procedure Check_Bad_Child is new Check_Raises_Exactly
           (Bad_Child, AMV.Ks_Bad_Parameter_Exception'Identity);
         procedure Bad_Sibling;
         procedure Bad_Sibling is
         begin
            Check (Never.Get_Siblings (0, False).Count = 0, "unreachable");
         end Bad_Sibling;
         procedure Check_Bad_Sibling is new Check_Raises_Exactly
           (Bad_Sibling, AMV.Ks_Bad_Parameter_Exception'Identity);
         procedure Bad_Item;
         procedure Bad_Item is
            Top : constant Ks_Blob_Result_Collection'Class :=
              Results.Get_Top_Level_Blobs (True);
         begin
            Check (Top.Item (2).ID = 0, "unreachable");
         end Bad_Item;
         procedure Check_Bad_Item is new Check_Raises_Exactly
           (Bad_Item, Constraint_Error'Identity);
         procedure Bad_Measure;
         procedure Bad_Measure is
            IDs : constant Ks_Blob_ID_Array := [0, 9];
         begin
            Check (Results.Get_Blob_Measures (Area, IDs)'Length = 2,
                   "unreachable");
         end Bad_Measure;
         procedure Check_Bad_Measure is new Check_Raises_Exactly
           (Bad_Measure, AMV.Ks_Bad_Parameter_Exception'Identity);
      begin
         Check_Bad_Child ("Get_Children of an unknown ID");
         Check_Bad_Sibling ("Get_Siblings in empty results");
         Check_Bad_Item ("Item beyond the collection: Constraint_Error");
         Check_Bad_Measure ("Get_Blob_Measures of an unknown ID");
         Check (Never.Get_Top_Level_Blobs (True).Count = 0
                and then Never.Get_Blob_IDs (False)'Length = 0
                and then Never.Get_Blobs.Count = 0
                and then Default.Count = 0,
                "empty results and a default collection have no features");
      end;
   end Test_Tree;

   procedure Test_Cleanup is
      Image : Ks_Image_8_Grey := Blank (100, 80);
      Tool  : Ks_Blob_Tool;
   begin
      Section ("Blob: prune and fill");
      --  A 30 x 20 blob (pixels 26 .. 55 by 21 .. 40) with a 3 x 3 hole,
      --  and a separate 2 x 2 blob.
      Draw_Rectangle (Image, 40.5, 30.5, 30.0, 20.0);
      Draw_Rectangle (Image, 40.0, 30.0, 3.0, 3.0, Value => 0);
      Draw_Rectangle (Image, 80.5, 60.5, 2.0, 2.0);
      Tool := Light_Tool (Image);
      Tool.Run_Params.Connectivity_Cleanup :=
        Code (Ks_Blob_Connectivity_Cleanup_Constants'(None));
      Tool.Run;
      Check (Count (Tool, False) = 3, "None: blob, hole and small blob");
      Check (Blob (Tool, 0, False).Pixel_Count = 591
             and then Blob (Tool, 1, False).Pixel_Count = 9
             and then Blob (Tool, 2, False).Pixel_Count = 4,
             "None: areas in ID order");
      Tool.Run_Params.Connectivity_Cleanup := Code (Prune);
      Tool.Run;
      Check (Count (Tool, False) = 1
             and then Blob (Tool, 0).Pixel_Count = 591
             and then Blob (Tool, 0).Num_Unfiltered_Children = 0,
             "Prune: the hole and the small blob are gone, area 591");
      Tool.Run_Params.Connectivity_Cleanup := Code (Fill);
      Tool.Run;
      Check (Count (Tool, False) = 1
             and then Blob (Tool, 0).Pixel_Count = 600,
             "Fill: the hole is filled, area 600");
      Tool.Run_Params.Connectivity_Min_Pixels := 0;
      Tool.Run;
      Check (Count (Tool, False) = 3, "Fill with no minimum keeps all");
      Tool.Run_Params.Connectivity_Min_Pixels := 5;
      Tool.Run;
      Check (Count (Tool, False) = 2
             and then Blob (Tool, 1, False).Label = 0,
             "minimum 5: only the 2 x 2 blob goes");
   end Test_Cleanup;

   ---------------------------------------------------------------------
   --  Filters and sorting
   ---------------------------------------------------------------------

   procedure Test_Filters_And_Sorting is
      Image : Ks_Image_8_Grey := Blank (120, 80);
      Tool  : Ks_Blob_Tool;
   begin
      Section ("Blob: filters and sorting");
      --  A: 10 x 10 (first pixel row 11), C: 30 x 30 (row 26), B: 20 x 20
      --  (row 31), so the IDs are A 0, C 1, B 2.
      Draw_Rectangle (Image, 15.5, 15.5, 10.0, 10.0);
      Draw_Rectangle (Image, 50.5, 40.5, 20.0, 20.0);
      Draw_Rectangle (Image, 95.5, 40.5, 30.0, 30.0);
      Tool := Light_Tool (Image);
      Tool.Run;
      Check (Count (Tool) = 3
             and then Blob (Tool, 0).Pixel_Count = 100
             and then Blob (Tool, 1).Pixel_Count = 900
             and then Blob (Tool, 2).Pixel_Count = 400,
             "unsorted: ID order (raster order of the first pixels)");
      Tool.Run_Params.Sort_Enabled := Code (True);
      Tool.Run;
      Check (Blob (Tool, 0).Pixel_Count = 900
             and then Blob (Tool, 1).Pixel_Count = 400
             and then Blob (Tool, 2).Pixel_Count = 100,
             "sorted by area, descending (the default)");
      Check (Blob (Tool, 0, False).Pixel_Count = 100,
             "the unfiltered collection stays in ID order");
      Tool.Run_Params.Sort_Ascending := Code (True);
      Tool.Run;
      Check (Blob (Tool, 0).Pixel_Count = 100
             and then Blob (Tool, 2).Pixel_Count = 900,
             "ascending");
      Tool.Run_Params.Sort_Measure := Code (Center_Mass_X);
      Tool.Run;
      Check (Blob (Tool, 0).ID = 0 and then Blob (Tool, 1).ID = 2
             and then Blob (Tool, 2).ID = 1,
             "by Center_Mass_X, ascending");

      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (Area, Filter, Include_Blobs_In_Range, 200.0,
                         1000.0));
      Tool.Run;
      Check (Count (Tool) = 2 and then Count (Tool, False) = 3,
             "include 200 .. 1000: two pass");
      Check (Tool.Results.Get_Blob_By_ID (0).Filtered_Out = 1
             and then Tool.Results.Get_Blob_By_ID (1).Filtered_Out = 0,
             "Filtered_Out flags");
      Check (Blob (Tool, 0).ID = 2 and then Blob (Tool, 1).ID = 1,
             "the filtered ones sorted");
      Tool.Run_Params.Run_Time_Measures.Items (0).Filter_Mode :=
        Code (Exclude_Blobs_In_Range);
      Tool.Run;
      Check (Count (Tool) = 1 and then Blob (Tool, 0).ID = 0,
             "exclude 200 .. 1000: one passes");
      Clear (Tool.Run_Params.Run_Time_Measures);
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (Area, Filter, Include_Blobs_In_Range, 50.0,
                         1000.0));
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (Center_Mass_X, Filter, Include_Blobs_In_Range, 0.0,
                         60.0));
      Add (Tool.Run_Params.Run_Time_Measures, Blob_Measure (Perimeter));
      Tool.Run;
      Check (Count (Tool) = 2 and then Blob (Tool, 0).ID = 0
             and then Blob (Tool, 1).ID = 2,
             "two filters (Pre_Compute measures do not filter)");
      Tool.Run_Params.Run_Time_Measures.Items (1).Filter_Range_Low := 200.0;
      Tool.Run_Params.Run_Time_Measures.Items (1).Filter_Range_High :=
        300.0;
      Tool.Run;
      Check (Count (Tool) = 0 and then Count (Tool, False) = 3
             and then Tool.Run_Status.Result = Accept_Result,
             "nothing passes: an empty filtered collection");
   end Test_Filters_And_Sorting;

   ---------------------------------------------------------------------
   --  Angles, regions and connectivity modes
   ---------------------------------------------------------------------

   procedure Test_Angle is
      Image : Ks_Image_8_Grey := Blank (120, 90);
      Tool  : Ks_Blob_Tool;
      R     : Ks_Blob_Result;
   begin
      Section ("Blob: principal angle");
      Draw_Rectangle (Image, 60.3, 45.2, 40.0, 10.0, Rotation => 0.3);
      Tool := Light_Tool (Image);
      Tool.Run;
      Check (Count (Tool) = 1, "one turned rectangle");
      R := Blob (Tool, 0);
      Check_Near (R.Angle, 0.3, 0.01, "Angle");
      Check_Near (R.Area, 400.0, 4.0, "Area");
      Check_Near (R.Center_Of_Mass_X, 60.3, 0.03, "centre X");
      Check_Near (R.Center_Of_Mass_Y, 45.2, 0.03, "centre Y");
      Check_Near (R.Elongation, 16.0, 0.8, "Elongation about (40 / 10)**2");
      --  The box around the pixel squares along the principal axes.
      Check_Near (R.Principal_Axis_Width, 40.0, 1.5, "principal width");
      Check_Near (R.Principal_Axis_Height, 10.0, 1.5, "principal height");
      Check_Near (Get_Bounding_Box (R, Principal).Rotation, R.Angle, 1.0E-12,
                  "principal box turned by Angle");
      --  The other way round.
      Image := Blank (120, 90);
      Draw_Rectangle (Image, 60.3, 45.2, 40.0, 10.0, Rotation => -1.2);
      Tool.Input_Image := Image;
      Tool.Run;
      Check_Near (Blob (Tool, 0).Angle, -1.2, 0.01, "Angle -1.2");
   end Test_Angle;

   procedure Test_Region is
      Image  : Ks_Image_8_Grey := Blank (100, 80);
      Tool   : Ks_Blob_Tool;
      Region : Ks_Rectangle;
   begin
      Section ("Blob: region");
      --  Pixels 31 .. 70 by 31 .. 50; the region keeps x >= 51.
      Draw_Rectangle (Image, 50.5, 40.5, 40.0, 20.0);
      Tool := Light_Tool (Image);
      Region.Set_XY_Width_Height (50.5, 0.0, 100.0, 100.0);
      Tool.Region := RH.To_Holder (Region);
      Tool.Run;
      Check_Accept (Tool, "region");
      Check (Count (Tool) = 1 and then Blob (Tool, 0).Pixel_Count = 400,
             "half the blob is in the region");
      Check_Near (Blob (Tool, 0).Center_Of_Mass_X, 60.5, 1.0E-9,
                  "centre of the part in the region");
      Check (Blob (Tool, 0).Not_Clipped = 0, "cut by the region: clipped");
      --  A region with no blob pixel.
      Region.Set_XY_Width_Height (0.0, 0.0, 10.0, 10.0);
      Tool.Region := RH.To_Holder (Region);
      Tool.Run;
      Check_Accept (Tool, "empty part");
      Check (Count (Tool) = 0, "no blob in that region");
      --  A region outside the image: the empty pixel region.
      Region.Set_XY_Width_Height (500.0, 500.0, 10.0, 10.0);
      Tool.Region := RH.To_Holder (Region);
      Tool.Run;
      Check_Accept (Tool, "region outside the image");
      Check (Count (Tool, False) = 0, "nothing outside the image");
      --  A blob touching the image edge is clipped.
      Image := Blank (100, 80);
      Draw_Rectangle (Image, 4.5, 40.5, 10.0, 10.0);   --  pixels 0 .. 9
      Tool.Input_Image := Image;
      Tool.Region.Clear;
      Tool.Run;
      Check (Count (Tool) = 1 and then Blob (Tool, 0).Not_Clipped = 0,
             "touching the image edge: clipped");
   end Test_Region;

   procedure Test_Connectivity_Modes is
      Image : Ks_Image_8_Grey := Blank (100, 80);
      Tool  : Ks_Blob_Tool;
   begin
      Section ("Blob: whole image and labeled");
      Draw_Rectangle (Image, 15.5, 15.5, 10.0, 10.0);   --  100 pixels
      Draw_Rectangle (Image, 60.5, 50.5, 20.0, 20.0);   --  400 pixels
      Tool := Light_Tool (Image);
      Tool.Run_Params.Connectivity_Mode := Code (Whole_Image_Grey_Scale);
      Tool.Run;
      Check (Count (Tool) = 1 and then Blob (Tool, 0).Pixel_Count = 500,
             "whole image: one blob");
      Check_Near (Blob (Tool, 0).Center_Of_Mass_X,
                  (100.0 * 15.5 + 400.0 * 60.5) / 500.0, 1.0E-9,
                  "whole image: the joint centroid");

      --  A label image: values 1 and 2 side by side, and another 2.
      Image := Blank (100, 80);
      Draw_Rectangle (Image, 15.5, 15.5, 10.0, 10.0, Value => 1);
      Draw_Rectangle (Image, 25.5, 15.5, 10.0, 10.0, Value => 2);
      Draw_Rectangle (Image, 70.5, 50.5, 10.0, 10.0, Value => 2);
      Tool.Input_Image := Image;
      Tool.Run_Params.Segmentation_Params.Mode :=
        Code (Ks_Blob_Segmentation_Mode_Constants'(None));
      Tool.Run_Params.Connectivity_Mode := Code (Labeled);
      Tool.Run;
      Check_Accept (Tool, "labeled");
      Check (Count (Tool) = 3, "labeled: three blobs");
      Check (Blob (Tool, 0).Label = 1 and then Blob (Tool, 1).Label = 2
             and then Blob (Tool, 2).Label = 2
             and then Blob (Tool, 0).Pixel_Count = 100
             and then Blob (Tool, 1).Pixel_Count = 100,
             "labeled: labels are the grey values");
      Tool.Run_Params.Connectivity_Mode := Code (Grey_Scale);
      Tool.Run;
      Check (Count (Tool) = 2 and then Blob (Tool, 0).Pixel_Count = 200,
             "grey scale: the touching labels join");
   end Test_Connectivity_Modes;

   ---------------------------------------------------------------------
   --  Thresholds
   ---------------------------------------------------------------------

   procedure Test_Thresholds is
      Image : Ks_Image_8_Grey := Blank (100, 80, 150);
      Tool  : Ks_Blob_Tool;
   begin
      Section ("Blob: relative and dynamic thresholds");
      Draw_Rectangle (Image, 40.5, 30.5, 20.0, 10.0, Value => 210);
      Tool := Light_Tool (Image);
      Tool.Run;
      Check (Count (Tool) = 1 and then Blob (Tool, 0).Pixel_Count = 8000,
             "fixed 128: the whole image is light");
      Tool.Run_Params.Segmentation_Params.Mode :=
        Code (Hard_Relative_Threshold);
      Tool.Run;
      Check (Count (Tool) = 1 and then Blob (Tool, 0).Pixel_Count = 200,
             "relative 50 percent: the rectangle");
      Tool.Run_Params.Segmentation_Params.Hard_Relative_Threshold := 100;
      Tool.Run;
      Check (Count (Tool) = 1 and then Blob (Tool, 0).Pixel_Count = 200,
             "relative 100 percent: the brightest level");
      Tool.Run_Params.Segmentation_Params.Hard_Relative_Threshold := 0;
      Tool.Run;
      Check (Count (Tool) = 1 and then Blob (Tool, 0).Pixel_Count = 8000,
             "relative 0 percent: every level");
      --  Tails: 5 percent of the darkest pixels set aside are all
      --  background, so nothing changes; 99 percent of them leaves only
      --  the light level.
      Tool.Run_Params.Segmentation_Params.Hard_Relative_Threshold := 0;
      Tool.Run_Params.Segmentation_Params.Tail_Low := 99;
      Tool.Run;
      Check (Count (Tool) = 1 and then Blob (Tool, 0).Pixel_Count = 200,
             "tail low 99 percent: low = high = 210");
      Tool.Run_Params.Segmentation_Params.Tail_Low := 0;
      Tool.Run_Params.Segmentation_Params.Mode :=
        Code (Hard_Dynamic_Threshold);
      Tool.Run;
      Check (Count (Tool) = 1 and then Blob (Tool, 0).Pixel_Count = 200,
             "dynamic (Otsu): the rectangle");
      --  With noise, Otsu's threshold needs a blob that is not too small
      --  a part of the region (it would split the background otherwise).
      Image := Blank (100, 80, 150);
      Draw_Rectangle (Image, 40.5, 30.5, 40.0, 30.0, Value => 210);
      Add_Noise (Image, 25.0, Seed => 7);
      Tool.Input_Image := Image;
      Tool.Run;
      Check (Count (Tool) = 1 and then Blob (Tool, 0).Pixel_Count = 1200,
             "dynamic with noise: the rectangle");
      --  A flat image has no split.
      Tool.Input_Image := Blank (50, 40, 100);
      Tool.Run;
      Check_Accept (Tool, "flat image");
      Check (Count (Tool) = 0, "dynamic on a flat image: no blob");
      Tool.Run_Params.Segmentation_Params.Polarity := Code (Dark_Blobs);
      Tool.Run;
      Check (Count (Tool) = 0, "dark blobs neither");
   end Test_Thresholds;

   ---------------------------------------------------------------------
   --  Selected space
   ---------------------------------------------------------------------

   procedure Test_Fixture_Space is
      Image : Ks_Image_8_Grey := Blank (100, 80);
      Tree  : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
      Pose  : constant Ks_Transform_2D_Linear :=
        Create_Similarity (2.0, 0.5, 10.0, 20.0);
      --  Fixture coordinates to root (= pixel) coordinates.
      Tool  : Ks_Blob_Tool;
      Plain : Ks_Blob_Result;
      R     : Ks_Blob_Result;
      X, Y  : Real;
   begin
      Section ("Blob: fixture space");
      Draw_Rectangle (Image, 40.5, 30.5, 20.0, 10.0);
      Tool := Light_Tool (Image);
      Tool.Run;
      Plain := Blob (Tool, 0);
      Tree.Add_Space ("@", "Fixture", Pose);
      Image.Set_Coordinate_Space_Tree (Tree);
      Image.Set_Selected_Space_Name ("@\Fixture");
      Tool.Input_Image := Image;
      Tool.Run;
      Check_Accept (Tool, "fixture");
      R := Blob (Tool, 0);
      Invert (Pose).Map_Point (40.5, 30.5, X, Y);
      Check_Near (R.Center_Of_Mass_X, X, 1.0E-9, "centre X in the fixture");
      Check_Near (R.Center_Of_Mass_Y, Y, 1.0E-9, "centre Y in the fixture");
      Check_Near (R.Area, 200.0 / 4.0, 1.0E-9, "area scaled by abs det");
      Check_Near (R.Perimeter, Plain.Perimeter / 2.0, 1.0E-9,
                  "perimeter scaled by the length scale");
      Check_Near (R.Inertia_Min, Plain.Inertia_Min / 16.0, 1.0E-6,
                  "inertia scaled by the fourth power");
      Check_Angle_Near (R.Angle, -0.5, 1.0E-9, "angle turned by the pose");
      Check_Near (R.Elongation, 4.0, 1.0E-9, "elongation kept");
      Check_Near (R.Pixel_Aligned_Box.Center_X, X, 1.0E-9,
                  "pixel-aligned box centre mapped");
      Check_Near (R.Pixel_Aligned_Box.Side_X_Length, 10.0, 1.0E-9,
                  "pixel-aligned box side mapped");
      Check_Near (R.Principal_Axis_Width, 10.0, 1.0E-9,
                  "principal box in fixture units");
      Check (Tool.Results.Selected_Space_Name = "@\Fixture",
             "results know their space");
      declare
         Boundary : constant Ks_Polygon := Tool.Results.Get_Boundary (0);
      begin
         Check (Boundary.Num_Vertices = 4, "boundary: four corners");
         Check_Near (Boundary.Area, 50.0, 1.0E-9,
                     "boundary in the fixture space");
      end;

      --  A transform that is not a similarity: x stretched by 2.
      Tree := Image.Get_Coordinate_Space_Tree;
      Tree.Add_Space ("@", "Stretch",
                      Create (0.5, 0.0, 0.0, 1.0, 0.0, 0.0));
      Image.Set_Coordinate_Space_Tree (Tree);
      Image.Set_Selected_Space_Name ("@\Stretch");
      Tool.Input_Image := Image;
      Tool.Run;
      R := Blob (Tool, 0);
      Check_Near (R.Area, 400.0, 1.0E-9, "stretched area");
      Check_Near (R.Center_Of_Mass_X, 81.0, 1.0E-9, "stretched centre");
      Check_Near (R.Inertia_Y, 8.0 * Plain.Inertia_Y, 1.0E-6,
                  "stretched moment about the y axis: det times 4");
      Check_Near (R.Pixel_Aligned_Width, 40.0, 1.0E-9, "stretched box");
   end Test_Fixture_Space;

   ---------------------------------------------------------------------
   --  Extrema angle, boxes at an angle and medians
   ---------------------------------------------------------------------

   --  The references are brute force: every pixel of a feature (from the
   --  blob ID image) is mapped into the selected space, its four corners
   --  give the box and its centre the medians (by sorting).

   type Real_List is array (Positive range <>) of Real;

   procedure Sort is new Ada.Containers.Generic_Array_Sort
     (Index_Type => Positive, Element_Type => Real, Array_Type => Real_List);

   function Median_Of (Values : Real_List) return Real;

   function Median_Of (Values : Real_List) return Real is
      Sorted : Real_List := Values;
      Middle : constant Positive := Sorted'First + Sorted'Length / 2;
   begin
      Sort (Sorted);
      if Sorted'Length mod 2 = 1 then
         return Sorted (Middle);
      else
         return (Sorted (Middle - 1) + Sorted (Middle)) / 2.0;
      end if;
   end Median_Of;

   type Reference is record
      U_Min, U_Max, V_Min, V_Max : Real := 0.0;
      U_Median, V_Median         : Real := 0.0;
      Pixels                     : Natural := 0;
   end record;
   --  Along the axes at an angle A: the extents of the mapped pixel
   --  squares of a feature and the medians of its mapped pixel centres,
   --  in the coordinates u = dx cos A + dy sin A, v = -dx sin A + dy cos A
   --  of (dx, dy) = the selected-space point minus (Origin_X, Origin_Y).

   function Reference_Of
     (IDs      : Ks_Image_16_Grey;
      ID       : Natural;
      T        : Ks_Transform_2D_Linear;
      Angle    : Real;
      Origin_X : Real := 0.0;
      Origin_Y : Real := 0.0) return Reference;

   function Reference_Of
     (IDs      : Ks_Image_16_Grey;
      ID       : Natural;
      T        : Ks_Transform_2D_Linear;
      Angle    : Real;
      Origin_X : Real := 0.0;
      Origin_Y : Real := 0.0) return Reference
   is
      use Ada.Numerics.Long_Elementary_Functions;
      Cos_A   : constant Real := Cos (Angle);
      Sin_A   : constant Real := Sin (Angle);
      Corners : constant array (1 .. 4, 1 .. 2) of Real :=
        [[-0.5, -0.5], [0.5, -0.5], [-0.5, 0.5], [0.5, 0.5]];
      Count   : Natural := 0;
      R       : Reference;
   begin
      for Y in 0 .. IDs.Height - 1 loop
         for X in 0 .. IDs.Width - 1 loop
            if Natural (IDs.Get_Pixel (X, Y)) = ID + 1 then
               Count := Count + 1;
            end if;
         end loop;
      end loop;
      R.Pixels := Count;
      R.U_Min := Real'Last;
      R.V_Min := Real'Last;
      R.U_Max := Real'First;
      R.V_Max := Real'First;
      declare
         U, V : Real_List (1 .. Count);
         K    : Natural := 0;
         MX   : Real;
         MY   : Real;
      begin
         for Y in 0 .. IDs.Height - 1 loop
            for X in 0 .. IDs.Width - 1 loop
               if Natural (IDs.Get_Pixel (X, Y)) = ID + 1 then
                  K := K + 1;
                  T.Map_Point (Real (X), Real (Y), MX, MY);
                  U (K) := (MX - Origin_X) * Cos_A + (MY - Origin_Y) * Sin_A;
                  V (K) := (MY - Origin_Y) * Cos_A - (MX - Origin_X) * Sin_A;
                  for C in Corners'Range (1) loop
                     T.Map_Point (Real (X) + Corners (C, 1),
                                  Real (Y) + Corners (C, 2), MX, MY);
                     declare
                        CU : constant Real :=
                          (MX - Origin_X) * Cos_A + (MY - Origin_Y) * Sin_A;
                        CV : constant Real :=
                          (MY - Origin_Y) * Cos_A - (MX - Origin_X) * Sin_A;
                     begin
                        R.U_Min := Real'Min (R.U_Min, CU);
                        R.U_Max := Real'Max (R.U_Max, CU);
                        R.V_Min := Real'Min (R.V_Min, CV);
                        R.V_Max := Real'Max (R.V_Max, CV);
                     end;
                  end loop;
               end if;
            end loop;
         end loop;
         if Count > 0 then
            R.U_Median := Median_Of (U);
            R.V_Median := Median_Of (V);
         end if;
      end;
      return R;
   end Reference_Of;

   procedure Check_Box
     (Box       : Ks_Rectangle_Affine;
      Ref       : Reference;
      Angle     : Real;
      Tolerance : Real;
      What      : String);
   --  Box is the rectangle along the axes at Angle with the extents of Ref
   --  (taken about the origin of the selected space).

   procedure Check_Box
     (Box       : Ks_Rectangle_Affine;
      Ref       : Reference;
      Angle     : Real;
      Tolerance : Real;
      What      : String)
   is
      use Ada.Numerics.Long_Elementary_Functions;
      U_Mid : constant Real := (Ref.U_Min + Ref.U_Max) / 2.0;
      V_Mid : constant Real := (Ref.V_Min + Ref.V_Max) / 2.0;
   begin
      Check_Near (Box.Center_X, U_Mid * Cos (Angle) - V_Mid * Sin (Angle),
                  Tolerance, What & ": centre X");
      Check_Near (Box.Center_Y, U_Mid * Sin (Angle) + V_Mid * Cos (Angle),
                  Tolerance, What & ": centre Y");
      Check_Near (Box.Side_X_Length, Ref.U_Max - Ref.U_Min, Tolerance,
                  What & ": side X");
      Check_Near (Box.Side_Y_Length, Ref.V_Max - Ref.V_Min, Tolerance,
                  What & ": side Y");
      Check_Angle_Near (Box.Rotation, Angle, 1.0E-12, What & ": rotation");
      Check (Box.Skew = 0.0, What & ": no skew");
   end Check_Box;

   function Same_Box (A, B : Ks_Rectangle_Affine; Tolerance : Real)
                      return Boolean
   is (abs (A.Center_X - B.Center_X) <= Tolerance
       and then abs (A.Center_Y - B.Center_Y) <= Tolerance
       and then abs (A.Side_X_Length - B.Side_X_Length) <= Tolerance
       and then abs (A.Side_Y_Length - B.Side_Y_Length) <= Tolerance
       and then abs (A.Rotation - B.Rotation) <= Tolerance
       and then A.Skew = B.Skew);

   procedure Check_Feature
     (Tool  : Ks_Blob_Tool;
      IDs   : Ks_Image_16_Grey;
      T     : Ks_Transform_2D_Linear;
      ID    : Natural;
      What  : String);
   --  Every extrema-angle measure, box and median of feature ID against
   --  the brute-force references.

   procedure Check_Feature
     (Tool  : Ks_Blob_Tool;
      IDs   : Ks_Image_16_Grey;
      T     : Ks_Transform_2D_Linear;
      ID    : Natural;
      What  : String)
   is
      R     : constant Ks_Blob_Result := Tool.Results.Get_Blob_By_ID (ID);
      Angle : constant Real := Tool.Run_Params.Extrema_Angle;
      Ext   : constant Reference := Reference_Of (IDs, ID, T, Angle);
      Sel   : constant Reference := Reference_Of (IDs, ID, T, 0.0);
      Pri   : constant Reference :=
        Reference_Of (IDs, ID, T, R.Angle, R.Center_Of_Mass_X,
                      R.Center_Of_Mass_Y);
      Other : constant Real := Angle + 0.7;
      Turn  : constant Reference := Reference_Of (IDs, ID, T, Other);
      Tol   : constant Real := 1.0E-9;
      Name  : constant String := What & " ID" & ID'Image;
   begin
      Check (Ext.Pixels = Natural (R.Pixel_Count)
             and then Ext.Pixels > 0, Name & ": pixels of the reference");
      --  The extrema-angle measures.
      Check_Near (R.Extrema_Angle_Min_X, Ext.U_Min, Tol, Name & ": Min_X");
      Check_Near (R.Extrema_Angle_Max_X, Ext.U_Max, Tol, Name & ": Max_X");
      Check_Near (R.Extrema_Angle_Min_Y, Ext.V_Min, Tol, Name & ": Min_Y");
      Check_Near (R.Extrema_Angle_Max_Y, Ext.V_Max, Tol, Name & ": Max_Y");
      Check_Near (R.Extrema_Angle_Center_X, (Ext.U_Min + Ext.U_Max) / 2.0,
                  Tol, Name & ": Center_X");
      Check_Near (R.Extrema_Angle_Center_Y, (Ext.V_Min + Ext.V_Max) / 2.0,
                  Tol, Name & ": Center_Y");
      Check_Near (R.Extrema_Angle_Width, Ext.U_Max - Ext.U_Min, Tol,
                  Name & ": Width");
      Check_Near (R.Extrema_Angle_Height, Ext.V_Max - Ext.V_Min, Tol,
                  Name & ": Height");
      Check_Near (R.Extrema_Angle_Aspect,
                  (Ext.V_Max - Ext.V_Min) / (Ext.U_Max - Ext.U_Min), Tol,
                  Name & ": Aspect");
      Check_Near (R.Median_Extrema_Angle_X, Ext.U_Median, Tol,
                  Name & ": Median_Extrema_Angle_X");
      Check_Near (R.Median_Extrema_Angle_Y, Ext.V_Median, Tol,
                  Name & ": Median_Extrema_Angle_Y");
      Check (R.Extrema_Angle_Min_X <= R.Median_Extrema_Angle_X
             and then R.Median_Extrema_Angle_X <= R.Extrema_Angle_Max_X
             and then R.Extrema_Angle_Min_Y <= R.Median_Extrema_Angle_Y
             and then R.Median_Extrema_Angle_Y <= R.Extrema_Angle_Max_Y,
             Name & ": Min <= Median <= Max");
      Check (Get_Measure (R, Median_Extrema_Angle_X) = R.Median_Extrema_Angle_X
             and then Get_Measure (R, Median_Extrema_Angle_Y)
                        = R.Median_Extrema_Angle_Y
             and then Get_Measure (R, Bounding_Box_Extrema_Angle_Center_X)
                        = R.Extrema_Angle_Center_X
             and then Get_Measure (R, Bounding_Box_Extrema_Angle_Center_Y)
                        = R.Extrema_Angle_Center_Y
             and then Get_Measure (R, Bounding_Box_Extrema_Angle_Min_X)
                        = R.Extrema_Angle_Min_X
             and then Get_Measure (R, Bounding_Box_Extrema_Angle_Max_X)
                        = R.Extrema_Angle_Max_X
             and then Get_Measure (R, Bounding_Box_Extrema_Angle_Min_Y)
                        = R.Extrema_Angle_Min_Y
             and then Get_Measure (R, Bounding_Box_Extrema_Angle_Max_Y)
                        = R.Extrema_Angle_Max_Y
             and then Get_Measure (R, Bounding_Box_Extrema_Angle_Width)
                        = R.Extrema_Angle_Width
             and then Get_Measure (R, Bounding_Box_Extrema_Angle_Height)
                        = R.Extrema_Angle_Height
             and then Get_Measure (R, Bounding_Box_Extrema_Angle_Aspect)
                        = R.Extrema_Angle_Aspect,
             Name & ": Get_Measure of the extrema-angle measures");

      --  The boxes.
      Check_Box (Get_Bounding_Box (R, Extrema_Angle), Ext, Angle, Tol,
                 Name & ": extrema-angle box");
      Check_Box (Tool.Results.Get_Bounding_Box_At_Angle (ID, Angle), Ext,
                 Angle, Tol, Name & ": box at ExtremaAngle");
      Check_Box (Tool.Results.Get_Bounding_Box_At_Angle (ID, Other), Turn,
                 Other, Tol, Name & ": box at another angle");
      Check (Same_Box (Tool.Results.Get_Bounding_Box_At_Angle (ID, Angle),
                       Get_Bounding_Box (R, Extrema_Angle), 0.0),
             Name & ": the box at ExtremaAngle is the extrema-angle box");
      Check (Same_Box (Tool.Results.Get_Bounding_Box_At_Angle (ID, 0.0),
                       Get_Bounding_Box (R, Selected_Space), 0.0),
             Name & ": the box at 0 is the selected-space box");
      Check (Same_Box (Tool.Results.Get_Bounding_Box_At_Angle (ID, R.Angle),
                       Get_Bounding_Box (R, Principal), 0.0),
             Name & ": the box at Angle is the principal-axis box");
      Check_Near (R.Principal_Axis_Min_X, Pri.U_Min, Tol,
                  Name & ": principal Min_X");
      Check_Near (R.Principal_Axis_Max_Y, Pri.V_Max, Tol,
                  Name & ": principal Max_Y");

      --  The medians.
      declare
         MX_P : constant Real := Tool.Results.Get_Median_X (ID, Principal);
         MY_P : constant Real := Tool.Results.Get_Median_Y (ID, Principal);
         MX_S : constant Real :=
           Tool.Results.Get_Median_X (ID, Selected_Space);
         MY_S : constant Real :=
           Tool.Results.Get_Median_Y (ID, Selected_Space);
      begin
         Check_Near (MX_P, Pri.U_Median, Tol, Name & ": GetMedianX principal");
         Check_Near (MY_P, Pri.V_Median, Tol, Name & ": GetMedianY principal");
         Check_Near (MX_S, Sel.U_Median, Tol,
                     Name & ": GetMedianX selected space");
         Check_Near (MY_S, Sel.V_Median, Tol,
                     Name & ": GetMedianY selected space");
         Check (Tool.Results.Get_Median_X (ID, Pixel_Aligned) = MX_S
                and then Tool.Results.Get_Median_Y (ID, Pixel_Aligned) = MY_S
                and then Tool.Results.Get_Median_X
                           (ID, Pixel_Aligned_No_Exclude) = MX_S
                and then Tool.Results.Get_Median_Y
                           (ID, Pixel_Aligned_No_Exclude) = MY_S,
                Name & ": pixel-aligned medians are the selected space's");
         Check (Tool.Results.Get_Median_X (ID, Extrema_Angle)
                  = R.Median_Extrema_Angle_X
                and then Tool.Results.Get_Median_Y (ID, Extrema_Angle)
                           = R.Median_Extrema_Angle_Y,
                Name & ": extrema-angle medians are the measures");
         Check (R.Principal_Axis_Min_X <= MX_P
                and then MX_P <= R.Principal_Axis_Max_X
                and then R.Principal_Axis_Min_Y <= MY_P
                and then MY_P <= R.Principal_Axis_Max_Y,
                Name & ": principal medians within the principal box");
         Check (R.Pixel_Aligned_Min_X <= MX_S
                and then MX_S <= R.Pixel_Aligned_Max_X
                and then R.Pixel_Aligned_Min_Y <= MY_S
                and then MY_S <= R.Pixel_Aligned_Max_Y,
                Name & ": selected medians within the pixel-aligned box");
      end;
   end Check_Feature;

   function Space_Name (S : Positive) return String is
     (case S is
         when 1 => "@",
         when 2 => "@\Fixture",
         when others => "@\Skew");

   procedure Test_Extrema is
      Image  : Ks_Image_8_Grey := Blank (120, 90);
      Tool   : Ks_Blob_Tool;
      Tree   : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
      Angles : constant array (1 .. 3, 1 .. 3) of Real :=
        [[0.0, 0.3, Pi / 2.0], [-1.2, 2.5, 7.0], [-100.0, 1.0, 0.0]];
   begin
      Section ("Blob: extrema angle, boxes at an angle and medians");
      --  An exact rectangle, a turned one, a disc, a ring (a blob and its
      --  hole) and an L, with even and odd pixel counts.
      Draw_Rectangle (Image, 25.5, 15.5, 20.0, 10.0);
      Draw_Rectangle (Image, 80.3, 60.2, 30.0, 8.0, Rotation => 0.4);
      Draw_Circle (Image, 25.3, 65.6, 9.0);
      Draw_Annulus (Image, 90.2, 22.7, 5.0, 11.0);
      Draw_Polygon (Image, [45.5, 35.5, 60.5, 35.5, 60.5, 40.5, 50.5, 40.5,
                            50.5, 55.5, 45.5, 55.5]);
      Tree.Add_Space ("@", "Fixture",
                      Create_Similarity (2.0, 0.5, 10.0, 20.0));
      Tree.Add_Space ("@", "Skew", Create (1.3, 0.4, -0.2, 0.7, 5.0, -3.0));
      Image.Set_Coordinate_Space_Tree (Tree);
      Tool := Light_Tool (Image);
      for S in 1 .. 3 loop
         Image.Set_Selected_Space_Name (Space_Name (S));
         Tool.Input_Image := Image;
         for A in Angles'Range (2) loop
            Tool.Run_Params.Extrema_Angle := Angles (S, A);
            Tool.Run;
            Check_Accept (Tool, "extrema angle" & Angles (S, A)'Image);
            Check (Count (Tool, False) = 6,
                   "six features (the ring's hole included)"
                   & Img (Count (Tool, False)));
            declare
               IDs : constant Ks_Image_16_Grey :=
                 Tool.Results.Create_Blob_ID_Image (Filtered => False);
               T   : constant Ks_Transform_2D_Linear :=
                 Image.Get_Transform (".", "#");
            begin
               for ID in 0 .. Count (Tool, False) - 1 loop
                  Check_Feature
                    (Tool, IDs, T, ID,
                     Space_Name (S) & " at" & Angles (S, A)'Image);
               end loop;
            end;
         end loop;
      end loop;

      --  At ExtremaAngle 0 in pixel space, the extrema-angle measures are
      --  the pixel-aligned ones.
      Image.Set_Selected_Space_Name ("@");
      Tool.Input_Image := Image;
      Tool.Run_Params.Extrema_Angle := 0.0;
      Tool.Run;
      declare
         R : constant Ks_Blob_Result := Blob (Tool, 0);
      begin
         Check (R.Extrema_Angle_Min_X = R.Pixel_Aligned_Min_X
                and then R.Extrema_Angle_Max_X = R.Pixel_Aligned_Max_X
                and then R.Extrema_Angle_Min_Y = R.Pixel_Aligned_Min_Y
                and then R.Extrema_Angle_Max_Y = R.Pixel_Aligned_Max_Y
                and then R.Extrema_Angle_Width = R.Pixel_Aligned_Width
                and then R.Extrema_Angle_Aspect = R.Pixel_Aligned_Aspect,
                "angle 0 in pixel space: the pixel-aligned box");
         Check_Near (R.Extrema_Angle_Min_X, 15.5, 1.0E-12,
                     "the exact rectangle starts at x = 15.5");
         Check_Near (R.Median_Extrema_Angle_X, 25.5, 1.0E-12,
                     "its median x (an even count: the mean of 25 and 26)");
         Check_Near (R.Median_Extrema_Angle_Y, 15.5, 1.0E-12,
                     "its median y");
      end;
   end Test_Extrema;

   procedure Test_Extrema_Filters is
      Image : Ks_Image_8_Grey := Blank (120, 80);
      Tool  : Ks_Blob_Tool;
   begin
      Section ("Blob: filtering and sorting by extrema-angle measures");
      --  A at x 11 .. 20, y 41 .. 50; B at x 41 .. 60, y 11 .. 30; C at
      --  x 81 .. 110, y 51 .. 70 (IDs by raster order: B 0, A 1, C 2).
      Draw_Rectangle (Image, 15.5, 45.5, 10.0, 10.0);
      Draw_Rectangle (Image, 50.5, 20.5, 20.0, 20.0);
      Draw_Rectangle (Image, 95.5, 60.5, 30.0, 20.0);
      Tool := Light_Tool (Image);
      --  At Pi/2, u = y and v = -x.
      Tool.Run_Params.Extrema_Angle := Pi / 2.0;
      Tool.Run_Params.Sort_Enabled := Code (True);
      Tool.Run_Params.Sort_Measure := Code (Bounding_Box_Extrema_Angle_Min_X);
      Tool.Run_Params.Sort_Ascending := Code (True);
      Tool.Run;
      Check_Accept (Tool, "sorted by an extrema-angle measure");
      Check (Count (Tool) = 3 and then Blob (Tool, 0).ID = 0
             and then Blob (Tool, 1).ID = 1 and then Blob (Tool, 2).ID = 2,
             "by the top edge (u = y at Pi/2)");
      Check_Near (Blob (Tool, 0).Extrema_Angle_Min_X, 10.5, 1.0E-9,
                  "B's top edge");
      Check_Near (Blob (Tool, 2).Median_Extrema_Angle_Y, -95.5, 1.0E-9,
                  "C's median v = -x");
      Tool.Run_Params.Sort_Measure := Code (Median_Extrema_Angle_Y);
      Tool.Run;
      Check (Blob (Tool, 0).ID = 2 and then Blob (Tool, 1).ID = 0
             and then Blob (Tool, 2).ID = 1,
             "by the median v = -x: right to left");
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (Median_Extrema_Angle_Y, Filter,
                         Include_Blobs_In_Range, -60.0, -20.0));
      Tool.Run;
      Check (Count (Tool) = 1 and then Blob (Tool, 0).ID = 0,
             "filtered by the median v: only B (x 41 .. 60)");
      Clear (Tool.Run_Params.Run_Time_Measures);
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (Bounding_Box_Extrema_Angle_Width, Filter,
                         Exclude_Blobs_In_Range, 5.0, 15.0));
      Tool.Run;
      Check (Count (Tool) = 2 and then Blob (Tool, 0).ID = 2
             and then Blob (Tool, 1).ID = 0,
             "excluding a width (the extent in y) of 5 .. 15: B and C");
      --  The largest angle accepted, and beyond it.
      Clear (Tool.Run_Params.Run_Time_Measures);
      Tool.Run_Params.Extrema_Angle := 1.0E6;
      Tool.Run;
      Check_Accept (Tool, "ExtremaAngle 1.0E6");
      Tool.Run_Params.Extrema_Angle := -1.000_001E6;
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name
                        = "AMV.KS_BAD_PARAMETER_EXCEPTION"
             and then Tool.Run_Status.Message
                        = "RunParams.ExtremaAngle must be finite and within "
                          & "+/-1.0E6",
             "ExtremaAngle beyond 1.0E6: Ks_Bad_Parameter_Exception");
      Tool.Run_Params.Extrema_Angle := 0.0;
      Tool.Run;
      declare
         procedure Bad_Angle;
         procedure Bad_Angle is
            B : constant Ks_Rectangle_Affine :=
              Tool.Results.Get_Bounding_Box_At_Angle (0, 2.0E6);
         begin
            Check (B.Center_X = 0.0, "unreachable");
         end Bad_Angle;
         procedure Check_Bad_Angle is new Check_Raises_Exactly
           (Bad_Angle, AMV.Ks_Bad_Parameter_Exception'Identity);
         procedure Bad_Box_ID;
         procedure Bad_Box_ID is
            B : constant Ks_Rectangle_Affine :=
              Tool.Results.Get_Bounding_Box_At_Angle (3, 0.0);
         begin
            Check (B.Center_X = 0.0, "unreachable");
         end Bad_Box_ID;
         procedure Check_Bad_Box_ID is new Check_Raises_Exactly
           (Bad_Box_ID, AMV.Ks_Bad_Parameter_Exception'Identity);
         procedure Bad_Median_ID;
         procedure Bad_Median_ID is
            M : constant Real :=
              Tool.Results.Get_Median_Y (-1, Selected_Space);
         begin
            Check (M = 0.0, "unreachable");
         end Bad_Median_ID;
         procedure Check_Bad_Median_ID is new Check_Raises_Exactly
           (Bad_Median_ID, AMV.Ks_Bad_Parameter_Exception'Identity);
      begin
         Check_Bad_Angle ("Get_Bounding_Box_At_Angle beyond 1.0E6");
         Check_Bad_Box_ID ("Get_Bounding_Box_At_Angle of an unknown ID");
         Check_Bad_Median_ID ("Get_Median_Y of an unknown ID");
      end;
   end Test_Extrema_Filters;

   ---------------------------------------------------------------------
   --  Errors and empty results
   ---------------------------------------------------------------------

   procedure Test_Errors is
      Tool  : Ks_Blob_Tool;
      Image : Ks_Image_8_Grey := Blank (60, 40);
   begin
      Section ("Blob: errors");
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name
                        = "AMV.KS_IMAGE_NO_PIXELS_EXCEPTION"
             and then Tool.Run_Status.Message = "InputImage has no pixels",
             "unallocated input: Error, Ks_Image_No_Pixels_Exception");
      Draw_Rectangle (Image, 30.5, 20.5, 10.0, 10.0);
      Tool := Light_Tool (Image);
      Tool.Run;
      Check (Count (Tool) = 1, "a blob before the failing run");
      Tool.Run_Params.Connectivity_Min_Pixels := -1;
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name
                        = "AMV.KS_BAD_PARAMETER_EXCEPTION"
             and then Tool.Run_Status.Message
                        = "RunParams.ConnectivityMinPixels must be >= 0",
             "negative minimum: Ks_Bad_Parameter_Exception");
      Check (Count (Tool) = 0 and then Count (Tool, False) = 0,
             "results reset after a failed run");
      Tool.Run_Params.Connectivity_Min_Pixels := 10;
      Tool.Run_Params.Segmentation_Params.Mode := Code (Map);
      Tool.Run;
      Check (Tool.Run_Status.Exception_Name
               = "AMV.KS_BAD_PARAMETER_EXCEPTION"
             and then Tool.Run_Status.Message
               = "RunParams.SegmentationParams.Mode: only None and the "
                 & "hard and soft thresholds are supported",
             "map segmentation is not supported");
      Tool.Run_Params.Segmentation_Params.Mode := Code (Subtraction_Image);
      Tool.Run;
      Check (Tool.Run_Status.Exception_Name
               = "AMV.KS_BAD_PARAMETER_EXCEPTION",
             "subtraction image segmentation is not supported");
      Tool.Run_Params.Segmentation_Params.Mode := Code (Hard_Fixed_Threshold);
      Tool.Run_Params.Sort_Measure := Code (Acircularity_Rms);
      Tool.Run;
      Check (Tool.Run_Status.Message
               = "RunParams.SortMeasure: measure 14 is not supported",
             "sorting by a measure that is not computed");
      Tool.Run_Params.Sort_Measure := Code (Area);
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (Area, Filter, Include_Blobs_In_Range, 10.0, 5.0));
      Tool.Run;
      Check (Tool.Run_Status.Message
               = "RunParams.RunTimeMeasures(0).FilterRangeLow must be <= "
                 & "FilterRangeHigh",
             "an empty filter range");
      Clear (Tool.Run_Params.Run_Time_Measures);
      Tool.Run_Params.Segmentation_Params.Hard_Fixed_Threshold := 70_000;
      Tool.Run;
      Check (Tool.Run_Status.Exception_Name
               = "AMV.KS_BAD_PARAMETER_EXCEPTION",
             "fixed threshold beyond 65535");
      Tool.Run_Params.Segmentation_Params.Hard_Fixed_Threshold := 128;
      Tool.Run;
      Check_Accept (Tool, "valid again");
      declare
         R : constant Ks_Blob_Result := Blob (Tool, 0);
         procedure Bad_Measure;
         procedure Bad_Measure is
            V : constant Real := Get_Measure (R, Boundary_Pixel_Length);
         begin
            Check (V = 0.0, "unreachable");
         end Bad_Measure;
         procedure Check_Bad_Measure is new Check_Raises_Exactly
           (Bad_Measure, AMV.Ks_Bad_Parameter_Exception'Identity);
         Zero : constant Real := Real'Value ("0.0");
         procedure Bad_Axis;
         procedure Bad_Axis is
            B : constant Ks_Rectangle_Affine :=
              Tool.Results.Get_Bounding_Box_At_Angle (0, Zero / Zero);
         begin
            Check (B.Center_X = 0.0, "unreachable");
         end Bad_Axis;
         procedure Check_Bad_Axis is new Check_Raises_Exactly
           (Bad_Axis, AMV.Ks_Bad_Parameter_Exception'Identity);
         procedure Bad_ID;
         procedure Bad_ID is
            B : constant Ks_Blob_Result := Tool.Results.Get_Blob_By_ID (1);
         begin
            Check (B.ID = 0, "unreachable");
         end Bad_ID;
         procedure Check_Bad_ID is new Check_Raises_Exactly
           (Bad_ID, AMV.Ks_Bad_Parameter_Exception'Identity);
         procedure Bad_Index;
         procedure Bad_Index is
            B : constant Ks_Blob_Result := Blob (Tool, 1);
         begin
            Check (B.ID = 0, "unreachable");
         end Bad_Index;
         procedure Check_Bad_Index is new Check_Raises_Exactly
           (Bad_Index, Constraint_Error'Identity);
         procedure Bad_Parent;
         procedure Bad_Parent is
            P : constant Integer := Tool.Results.Get_Parent (-1);
         begin
            Check (P = 0, "unreachable");
         end Bad_Parent;
         procedure Check_Bad_Parent is new Check_Raises_Exactly
           (Bad_Parent, AMV.Ks_Bad_Parameter_Exception'Identity);
      begin
         Check_Bad_Measure ("Get_Measure (Boundary_Pixel_Length)");
         Check_Bad_Axis ("Get_Bounding_Box_At_Angle of a NaN");
         Check_Bad_ID ("Get_Blob_By_ID of an unknown ID");
         Check_Bad_Index ("Item beyond Count: Constraint_Error");
         Check_Bad_Parent ("Get_Parent of an unknown ID");
      end;
      --  A full collection.
      declare
         Measures : Ks_Blob_Measure_Collection;
         procedure Overfill;
         procedure Overfill is
         begin
            for I in 1 .. 65 loop
               Add (Measures, Blob_Measure (Area));
            end loop;
         end Overfill;
         procedure Check_Overfill is new Check_Raises_Exactly
           (Overfill, AMV.Ks_Bad_Parameter_Exception'Identity);
      begin
         Check_Overfill ("a 65th run-time measure");
         Check (Measures.Count = 64, "the collection holds 64");
      end;
      --  No blob at all.
      Tool.Input_Image := Blank (60, 40);
      Tool.Run;
      Check_Accept (Tool, "blank image");
      Check (Count (Tool) = 0 and then Count (Tool, False) = 0,
             "blank image: no blob");
   end Test_Errors;

   ---------------------------------------------------------------------
   --  Boundaries, ID images and morphology
   ---------------------------------------------------------------------

   procedure Test_Boundary_And_ID_Image is
      Image : Ks_Image_8_Grey := Blank (60, 40);
      Tool  : Ks_Blob_Tool;
   begin
      Section ("Blob: boundary and blob ID image");
      Draw_Rectangle (Image, 20.5, 15.5, 20.0, 10.0);  --  11 .. 30, 11 .. 20
      --  An L: a 4 x 4 square (44 .. 47 by 29 .. 32) with a 4 x 2 foot
      --  (48 .. 51 by 31 .. 32).
      Draw_Rectangle (Image, 45.5, 30.5, 4.0, 4.0);
      Draw_Rectangle (Image, 49.5, 31.5, 4.0, 2.0);
      Tool := Light_Tool (Image);
      Tool.Run_Params.Connectivity_Min_Pixels := 0;
      Tool.Run;
      Check (Count (Tool) = 2, "a rectangle and an L");
      declare
         Rect : constant Ks_Polygon := Tool.Results.Get_Boundary (0);
         L    : constant Ks_Polygon := Tool.Results.Get_Boundary (1);
         Min_X, Min_Y, Max_X, Max_Y : Real;
      begin
         Check (Rect.Num_Vertices = 4, "rectangle: 4 vertices");
         Rect.Get_Bounding_Box (Min_X, Min_Y, Max_X, Max_Y);
         Check (Min_X = 10.5 and then Max_X = 30.5 and then Min_Y = 10.5
                and then Max_Y = 20.5,
                "rectangle boundary along the pixel edges");
         Check_Near (Rect.Area, 200.0, 1.0E-9, "rectangle boundary area");
         Check (L.Num_Vertices = 6, "L: 6 vertices");
         Check_Near (L.Area, 24.0, 1.0E-9, "L boundary area");
         Check (Rect.Get_Vertex_X (0) = 30.5
                and then Rect.Get_Vertex_Y (0) = 10.5,
                "the first vertex is the top right corner");
      end;
      declare
         IDs : constant Ks_Image_16_Grey :=
           Tool.Results.Create_Blob_ID_Image;
      begin
         Check (IDs.Width = 60 and then IDs.Height = 40,
                "ID image of the input size");
         Check (IDs.Get_Pixel (11, 11) = 1 and then IDs.Get_Pixel (45, 30) = 2
                and then IDs.Get_Pixel (0, 0) = 0
                and then IDs.Get_Pixel (10, 11) = 0,
                "ID image: ID + 1 on the blobs, 0 elsewhere");
      end;
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (Area, Filter, Include_Blobs_In_Range, 100.0,
                         1000.0));
      Tool.Run;
      declare
         Filtered : constant Ks_Image_16_Grey :=
           Tool.Results.Create_Blob_ID_Image;
         All_IDs  : constant Ks_Image_16_Grey :=
           Tool.Results.Create_Blob_ID_Image (Filtered => False);
      begin
         Check (Filtered.Get_Pixel (45, 30) = 0
                and then All_IDs.Get_Pixel (45, 30) = 2
                and then Filtered.Get_Pixel (11, 11) = 1,
                "filtered ID image leaves out the filtered blobs");
      end;
   end Test_Boundary_And_ID_Image;


   ---------------------------------------------------------------------
   --  Blob image and segmented images
   ---------------------------------------------------------------------

   procedure Test_Images is
      Image : Ks_Image_8_Grey := Blank (60, 40);
      Tool  : Ks_Blob_Tool;

      function Px (I : Ks_Image_8_Grey; X, Y : Natural) return Integer is
        (Integer (I.Get_Pixel (X, Y)));

      procedure Fill_Block
        (Target         : in out Ks_Image_8_Grey;
         X0, Y0, X1, Y1 : Natural;
         Value          : Grey_8);

      procedure Fill_Block
        (Target         : in out Ks_Image_8_Grey;
         X0, Y0, X1, Y1 : Natural;
         Value          : Grey_8) is
      begin
         for Y in Y0 .. Y1 loop
            for X in X0 .. X1 loop
               Target.Set_Pixel (X, Y, Value);
            end loop;
         end loop;
      end Fill_Block;
   begin
      Section ("Blob: blob image and segmented images");
      --  A: pixels 11 .. 30 by 11 .. 20 with a hole 15 .. 18 by 14 .. 17
      --  (16 pixels) and a small hole 25 .. 26 by 14 .. 15 (4 pixels,
      --  filled into A); B: 41 .. 50 by 26 .. 33 (80 pixels); a speck
      --  55 .. 56 by 5 .. 6 (4 pixels, removed).
      Fill_Block (Image, 11, 11, 30, 20, 255);
      Fill_Block (Image, 15, 14, 18, 17, 0);
      Fill_Block (Image, 25, 14, 26, 15, 0);
      Fill_Block (Image, 41, 26, 50, 33, 255);
      Fill_Block (Image, 55, 5, 56, 6, 255);
      Image.Coordinate_Space_Tree.Add_Space
        ("@", "Part", Create_Rigid (0.3, 2.0, 1.0));
      Image.Set_Selected_Space_Name ("@\Part");
      Tool := Light_Tool (Image);
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (Area, Filter, Include_Blobs_In_Range, 0.5, 1.0E6));
      Tool.Run;
      Check_Accept (Tool, "images: the run");
      Check (Count (Tool, False) = 3, "images: A, its hole and B");

      declare
         Shown : constant Ks_Image_8_Grey := Tool.Results.Create_Blob_Image;
      begin
         Check (Shown.Width = 60 and then Shown.Height = 40,
                "blob image of the input size");
         Check (Shown.Selected_Space_Name = "@\Part",
                "blob image: the input's selected space");
         Check (Px (Shown, 0, 0) = 128 and then Px (Shown, 12, 12) = 255
                and then Px (Shown, 16, 15) = 0
                and then Px (Shown, 45, 29) = 255
                and then Px (Shown, 55, 5) = 128,
                "viewable: background 128, blobs 255, holes 0, the removed "
                & "speck background");
         Check (Px (Shown, 25, 14) = 255,
                "viewable: a hole filled into the blob is blob");
      end;
      declare
         Raw : constant Ks_Image_8_Grey :=
           Tool.Results.Create_Blob_Image
             (Filtered => False, Viewable => False, Background => 7);
      begin
         Check (Px (Raw, 0, 0) = 7 and then Px (Raw, 12, 12) = 1
                and then Px (Raw, 16, 15) = 0 and then Px (Raw, 25, 14) = 1
                and then Px (Raw, 45, 29) = 1,
                "not viewable: Background, segmented values 1, holes 0");
      end;
      --  Filter out B and the hole (area below 100).
      Clear (Tool.Run_Params.Run_Time_Measures);
      Add (Tool.Run_Params.Run_Time_Measures,
           Blob_Measure (Area, Filter, Include_Blobs_In_Range, 100.0,
                         1.0E6));
      Tool.Run;
      declare
         Kept : constant Ks_Image_8_Grey := Tool.Results.Create_Blob_Image;
         All_Features : constant Ks_Image_8_Grey :=
           Tool.Results.Create_Blob_Image (Filtered => False);
      begin
         Check (Px (Kept, 12, 12) = 255 and then Px (Kept, 45, 29) = 128
                and then Px (Kept, 16, 15) = 128,
                "filtered: only the features that passed are painted");
         Check (Px (All_Features, 45, 29) = 255
                and then Px (All_Features, 16, 15) = 0,
                "unfiltered: every feature is painted");
      end;

      --  Segmented images: none unless saved.
      Check (not Tool.Results.Create_Segmented_Image.Allocated
             and then not Tool.Results.Create_Segmented_Image
                            (Before_Masking).Allocated,
             "segmented image: none when not saved (VisionPro: null)");
      Tool.Run_Params.Save_Segmented_Image := Code (True);
      Tool.Run_Params.Save_Segmented_Image_Before_Morphology := Code (True);
      Tool.Run_Params.Save_Segmented_Image_Before_Masking := Code (True);
      Add (Tool.Run_Params.Morphology_Operations, Erode_Square);
      Tool.Run;
      Check_Accept (Tool, "images: saved, with an erosion");
      declare
         Final   : constant Ks_Image_8_Grey :=
           Tool.Results.Create_Segmented_Image;
         Raw     : constant Ks_Image_8_Grey :=
           Tool.Results.Create_Segmented_Image (Final_Image, False);
         Before  : constant Ks_Image_8_Grey :=
           Tool.Results.Create_Segmented_Image (Before_Morphology, False);
         Masking : constant Ks_Image_8_Grey :=
           Tool.Results.Create_Segmented_Image (Before_Masking, False);
      begin
         Check (Final.Width = 60 and then Final.Height = 40
                and then Final.Selected_Space_Name = "@\Part",
                "segmented image of the input size and spaces");
         Check (Px (Final, 12, 12) = 255 and then Px (Final, 0, 0) = 0
                and then Px (Final, 11, 11) = 0,
                "final, stretched: 255 and 0, the eroded corner 0");
         Check (Px (Raw, 12, 12) = 1 and then Px (Raw, 11, 11) = 0
                and then Px (Raw, 55, 5) = 0,
                "final: the levels after the erosion (the speck is gone)");
         Check (Px (Before, 11, 11) = 1 and then Px (Before, 55, 5) = 1
                and then Px (Before, 25, 14) = 0
                and then Px (Before, 16, 15) = 0,
                "before morphology: the corner and the speck (before the "
                & "cleanup too), holes 0");
         Check (Px (Masking, 11, 11) = 1 and then Px (Masking, 30, 20) = 1,
                "before masking: the same for the whole image region");
      end;

      --  A circular region: before masking, the bounding rectangle
      --  whether in the circle or not.
      declare
         Circle : Ks_Circle;
      begin
         Circle.Set_Center_Radius (20.5, 15.5, 8.0);
         Circle.Set_Selected_Space_Name ("#");
         Tool.Region := RH.To_Holder (Circle);
         Clear (Tool.Run_Params.Morphology_Operations);
         Tool.Run;
         Check_Accept (Tool, "images: circular region");
         declare
            Before  : constant Ks_Image_8_Grey :=
              Tool.Results.Create_Segmented_Image (Before_Morphology, False);
            Masking : constant Ks_Image_8_Grey :=
              Tool.Results.Create_Segmented_Image (Before_Masking, False);
            Final   : constant Ks_Image_8_Grey :=
              Tool.Results.Create_Segmented_Image (Final_Image, False);
         begin
            Check (Px (Masking, 13, 11) = 1 and then Px (Before, 13, 11) = 0
                   and then Px (Final, 13, 11) = 0,
                   "outside the circle, inside its box: only before masking");
            Check (Px (Masking, 20, 15) = 1 and then Px (Before, 20, 15) = 1
                   and then Px (Final, 20, 15) = 1,
                   "inside the circle: in every stage");
            Check (Px (Masking, 12, 12) = 0 and then Px (Masking, 45, 29) = 0,
                   "outside the box: 0 in every stage");
         end;
         Tool.Region.Clear;
      end;

      --  Soft segmentation: levels, viewable spacing and stretching.
      declare
         Soft : Ks_Blob_Tool;
         Grey : Ks_Image_8_Grey := Blank (40, 30);
      begin
         Fill_Block (Grey, 5, 5, 14, 14, 150);    --  level 3 of 5
         Fill_Block (Grey, 20, 5, 29, 14, 255);   --  level 5 of 5
         Soft.Input_Image := Grey;
         Set_Segmentation_Soft_Fixed_Threshold
           (Soft.Run_Params.Segmentation_Params, 100, 200, 4, Light_Blobs);
         Soft.Run_Params.Save_Segmented_Image := Code (True);
         Soft.Run;
         Check_Accept (Soft, "images: soft");
         declare
            Raw      : constant Ks_Image_8_Grey :=
              Soft.Results.Create_Blob_Image (Viewable => False);
            Shown    : constant Ks_Image_8_Grey :=
              Soft.Results.Create_Blob_Image;
            Levels   : constant Ks_Image_8_Grey :=
              Soft.Results.Create_Segmented_Image (Final_Image, False);
            Stretched : constant Ks_Image_8_Grey :=
              Soft.Results.Create_Segmented_Image;
         begin
            Check (Px (Raw, 6, 6) = 3 and then Px (Raw, 21, 6) = 5
                   and then Px (Raw, 0, 0) = 0,
                   "soft, not viewable: the levels");
            Check (Px (Shown, 6, 6) = 235 and then Px (Shown, 21, 6) = 255,
                   "soft, viewable: 10 less per level below full weight");
            Check (Px (Levels, 6, 6) = 3 and then Px (Levels, 21, 6) = 5,
                   "soft segmented image: the levels");
            Check (Px (Stretched, 6, 6) = 153
                   and then Px (Stretched, 21, 6) = 255,
                   "soft segmented image, stretched: level * 255 / 5");
         end;
         Fill_Block (Grey, 5, 5, 14, 14, 100);    --  level 1 of 255
         Soft.Input_Image := Grey;
         Set_Segmentation_Soft_Fixed_Threshold
           (Soft.Run_Params.Segmentation_Params, 100, 200, 254, Light_Blobs);
         Soft.Run;
         Check (Px (Soft.Results.Create_Blob_Image, 6, 6) = 192
                and then Px (Soft.Results.Create_Blob_Image, 21, 6) = 255,
                "soft, viewable, Softness 254: levels over 192 .. 255");
      end;

      --  Labeled: the labels.
      declare
         By_Label : Ks_Blob_Tool;
         Grey    : Ks_Image_8_Grey := Blank (40, 30);
      begin
         Fill_Block (Grey, 5, 5, 14, 14, 200);
         Fill_Block (Grey, 20, 5, 29, 14, 250);
         By_Label := Light_Tool (Grey);
         By_Label.Run_Params.Connectivity_Mode := Code (Labeled);
         By_Label.Run;
         Check_Accept (By_Label, "images: labeled");
         Check (Px (By_Label.Results.Create_Blob_Image (Viewable => False),
                    6, 6) = 200
                and then Px (By_Label.Results.Create_Blob_Image
                               (Viewable => False), 21, 6) = 250,
                "labeled, not viewable: the labels");
         Check (Px (By_Label.Results.Create_Blob_Image, 6, 6) = 220
                and then Px (By_Label.Results.Create_Blob_Image, 21, 6) = 251
                and then Px (By_Label.Results.Create_Blob_Image, 0, 0) = 128,
                "labeled, viewable: 96 + label * 159 / 255");
      end;

      --  Errors.
      declare
         Never : Ks_Blob_Results;
         procedure No_Results;
         procedure No_Results is
         begin
            Check (Never.Create_Blob_Image.Width = 0, "unreachable");
         end No_Results;
         procedure Check_No_Results is new Check_Raises_Exactly
           (No_Results, AMV.Ks_Image_No_Pixels_Exception'Identity);
         procedure No_Segmented;
         procedure No_Segmented is
         begin
            Check (Never.Create_Segmented_Image.Width = 0, "unreachable");
         end No_Segmented;
         procedure Check_No_Segmented is new Check_Raises_Exactly
           (No_Segmented, AMV.Ks_Image_No_Pixels_Exception'Identity);
         procedure Bad_Background;
         procedure Bad_Background is
         begin
            Check (Tool.Results.Create_Blob_Image
                     (Viewable => False, Background => 256).Width = 0,
                   "unreachable");
         end Bad_Background;
         procedure Check_Bad_Background is new Check_Raises_Exactly
           (Bad_Background, AMV.Ks_Bad_Parameter_Exception'Identity);
      begin
         Check_No_Results ("CreateBlobImage without results");
         Check_No_Segmented ("CreateSegmentedImage without results");
         Check_Bad_Background ("CreateBlobImage: Background 256");
         Check (Tool.Results.Create_Blob_Image (Background => 300).Width
                  = 60,
                "viewable: Background is not used");
      end;
   end Test_Images;

   procedure Test_Morphology is
      Image : Ks_Image_8_Grey := Blank (60, 40);
      Tool  : Ks_Blob_Tool;
   begin
      Section ("Blob: morphology");
      Draw_Rectangle (Image, 19.5, 19.5, 10.0, 10.0);   --  15 .. 24
      Tool := Light_Tool (Image);
      Add (Tool.Run_Params.Morphology_Operations, Dilate_Square);
      Tool.Run;
      Check (Count (Tool) = 1 and then Blob (Tool, 0).Pixel_Count = 144,
             "dilate square: 12 x 12");
      Clear (Tool.Run_Params.Morphology_Operations);
      Add (Tool.Run_Params.Morphology_Operations, Erode_Square);
      Tool.Run;
      Check (Blob (Tool, 0).Pixel_Count = 64, "erode square: 8 x 8");
      Clear (Tool.Run_Params.Morphology_Operations);
      Add (Tool.Run_Params.Morphology_Operations, Dilate_Horizontal);
      Tool.Run;
      Check (Blob (Tool, 0).Pixel_Count = 120, "dilate horizontal: 12 x 10");
      Clear (Tool.Run_Params.Morphology_Operations);
      Add (Tool.Run_Params.Morphology_Operations, Erode_Vertical);
      Tool.Run;
      Check (Blob (Tool, 0).Pixel_Count = 80, "erode vertical: 10 x 8");
      --  Two squares joined by a one-pixel bridge: opening cuts it.
      Draw_Rectangle (Image, 29.5, 20.0, 10.0, 1.0);   --  bridge 25 .. 34
      Draw_Rectangle (Image, 39.5, 19.5, 10.0, 10.0);  --  35 .. 44
      Tool.Input_Image := Image;
      Clear (Tool.Run_Params.Morphology_Operations);
      Tool.Run;
      Check (Count (Tool) = 1, "joined by the bridge");
      Add (Tool.Run_Params.Morphology_Operations, Open_Square);
      Tool.Run;
      Check (Count (Tool) = 2 and then Blob (Tool, 0).Pixel_Count = 100
             and then Blob (Tool, 1).Pixel_Count = 100,
             "open square: two squares again");
      --  A one-pixel hole closed.
      Image := Blank (60, 40);
      Draw_Rectangle (Image, 19.5, 19.5, 10.0, 10.0);
      Draw_Rectangle (Image, 20.0, 20.0, 1.0, 1.0, Value => 0);
      Tool.Input_Image := Image;
      Tool.Run_Params.Connectivity_Cleanup :=
        Code (Ks_Blob_Connectivity_Cleanup_Constants'(None));
      Clear (Tool.Run_Params.Morphology_Operations);
      Tool.Run;
      Check (Count (Tool, False) = 2, "a blob with a one-pixel hole");
      Add (Tool.Run_Params.Morphology_Operations, Close_Square);
      Tool.Run;
      Check (Count (Tool, False) = 1
             and then Blob (Tool, 0).Pixel_Count = 100,
             "close square fills it");
   end Test_Morphology;

   ---------------------------------------------------------------------
   --  Soft segmentation
   ---------------------------------------------------------------------

   --  An independent reference for the soft modes: the level of a grey
   --  value found by searching the step of the band (the band [Low, High)
   --  split into S steps of equal width, step J starting at Low + J (High
   --  - Low) / S), and the weighted measures summed pixel by pixel in
   --  floating point.

   type Level_Map is array (Natural range <>, Natural range <>) of Integer;
   --  Indexed (Y, X).

   type Integer_Array is array (Positive range <>) of Integer;

   function Ref_Step (G, Low, High, S : Integer) return Integer is
      K : Integer := 0;
   begin
      for J in 1 .. S - 1 loop
         if (G - Low) * S >= J * (High - Low) then
            K := J;
         end if;
      end loop;
      return K;
   end Ref_Step;

   function Ref_Level (Light : Boolean; Low, High, S, G : Integer)
                       return Integer
   is (if G < Low then (if Light then 0 else S + 1)
       elsif G >= High then (if Light then S + 1 else 0)
       elsif S = 0 then 0
       elsif Light then 1 + Ref_Step (G, Low, High, S)
       else S - Ref_Step (G, Low, High, S));

   function Ref_Levels
     (Image           : Ks_Image_8_Grey;
      Light           : Boolean;
      Low, High, S    : Integer) return Level_Map
   is
      Result : Level_Map (0 .. Image.Height - 1, 0 .. Image.Width - 1);
   begin
      for Y in Result'Range (1) loop
         for X in Result'Range (2) loop
            Result (Y, X) :=
              Ref_Level
                (Light, Low, High, S, Integer (Image.Get_Pixel (X, Y)));
         end loop;
      end loop;
      return Result;
   end Ref_Levels;

   type Ref_Measures is record
      Pixels        : Natural := 0;
      Area, Cx, Cy  : Real := 0.0;
      Mxx, Myy, Mxy : Real := 0.0;
   end record;
   --  The number of pixels of level above 0, the sum of their weights,
   --  the weighted centroid and the weighted second moments of their
   --  pixel squares about it (a square of weight W adds W / 12 to Mxx and
   --  Myy).

   function Ref_Measure
     (Levels         : Level_Map;
      S              : Integer;
      X0, Y0, X1, Y1 : Natural) return Ref_Measures
   is
      R          : Ref_Measures;
      Sw, Sx, Sy : Real := 0.0;
      function W (X, Y : Natural) return Real is
        (Real (Levels (Y, X)) / Real (S + 1));
   begin
      for Y in Y0 .. Y1 loop
         for X in X0 .. X1 loop
            if Levels (Y, X) > 0 then
               R.Pixels := R.Pixels + 1;
               Sw := Sw + W (X, Y);
               Sx := Sx + W (X, Y) * Real (X);
               Sy := Sy + W (X, Y) * Real (Y);
            end if;
         end loop;
      end loop;
      R.Area := Sw;
      R.Cx := Sx / Sw;
      R.Cy := Sy / Sw;
      for Y in Y0 .. Y1 loop
         for X in X0 .. X1 loop
            if Levels (Y, X) > 0 then
               R.Mxx := R.Mxx
                 + W (X, Y) * ((Real (X) - R.Cx) ** 2 + 1.0 / 12.0);
               R.Myy := R.Myy
                 + W (X, Y) * ((Real (Y) - R.Cy) ** 2 + 1.0 / 12.0);
               R.Mxy := R.Mxy
                 + W (X, Y) * (Real (X) - R.Cx) * (Real (Y) - R.Cy);
            end if;
         end loop;
      end loop;
      return R;
   end Ref_Measure;

   procedure Check_Weighted
     (R : Ks_Blob_Result; E : Ref_Measures; What : String)
   is
      use Ada.Numerics.Long_Elementary_Functions;
      Half_Sum  : constant Real := (E.Mxx + E.Myy) / 2.0;
      Half_Diff : constant Real := (E.Mxx - E.Myy) / 2.0;
      Radius    : constant Real := Sqrt (Half_Diff ** 2 + E.Mxy ** 2);
      Tol       : constant Real := 1.0E-9 * (E.Mxx + E.Myy);
   begin
      Check (Natural (R.Pixel_Count) = E.Pixels,
             What & ": Pixel_Count counts pixels" & R.Pixel_Count'Image
             & E.Pixels'Image);
      Check_Near (R.Area, E.Area, 1.0E-9 * E.Area,
                  What & ": Area is the sum of the weights");
      Check_Near (R.Center_Of_Mass_X, E.Cx, 1.0E-9,
                  What & ": weighted centre of mass X");
      Check_Near (R.Center_Of_Mass_Y, E.Cy, 1.0E-9,
                  What & ": weighted centre of mass Y");
      Check_Near (R.Inertia_Y, E.Mxx, Tol, What & ": weighted Inertia_Y");
      Check_Near (R.Inertia_X, E.Myy, Tol, What & ": weighted Inertia_X");
      Check_Near (R.Inertia_Max, Half_Sum + Radius, Tol,
                  What & ": weighted Inertia_Max");
      Check_Near (R.Inertia_Min, Half_Sum - Radius, Tol,
                  What & ": weighted Inertia_Min");
      Check_Near (R.Elongation, (Half_Sum + Radius) / (Half_Sum - Radius),
                  1.0E-7 * R.Elongation, What & ": weighted Elongation");
      Check_Angle_Near (2.0 * R.Angle, Arctan (E.Mxy, Half_Diff), 1.0E-7,
                        What & ": the principal angle of the weighted "
                        & "moments");
      Check_Near (R.Acircularity, R.Perimeter ** 2 / (4.0 * Pi * E.Area),
                  1.0E-9 * R.Acircularity,
                  What & ": Acircularity from the weighted Area");
   end Check_Weighted;

   function Ramp_Scene (Light : Boolean) return Ks_Image_8_Grey is
      Image : Ks_Image_8_Grey := Blank (60, 40, (if Light then 0 else 255));
   begin
      for Y in 15 .. 24 loop
         for X in 10 .. 39 loop
            Image.Set_Pixel
              (X, Y, Grey_8 (if Light then 40 + 6 * (X - 10) + (Y - 15)
                             else 215 - 6 * (X - 10) - (Y - 15)));
         end loop;
      end loop;
      return Image;
   end Ramp_Scene;
   --  A 30 x 10 rectangle (x 10 .. 39, y 15 .. 24) whose grey value rises
   --  by 6 a column and 1 a row from 40 on black (light blobs), or falls
   --  the same way from 215 on white (dark blobs): grey values 32 .. 223.

   procedure Test_Soft_Thresholds is
      Tool   : Ks_Blob_Tool;
      Hard   : Ks_Blob_Tool;
      Params : constant Ks_Blob := (others => <>);
   begin
      Section ("Blob: soft thresholds");
      Check (Params.Segmentation_Params.Soft_Fixed_Threshold_Low = 102
             and then Params.Segmentation_Params.Soft_Fixed_Threshold_High
                        = 153
             and then Params.Segmentation_Params.Soft_Relative_Threshold_Low
                        = 40
             and then Params.Segmentation_Params.Soft_Relative_Threshold_High
                        = 60
             and then Params.Segmentation_Params.Softness = 254,
             "soft defaults (VisionPro's; the fixed band AMV's)");

      --  Fixed band [50, 200) on the ramp, both polarities, softness 254,
      --  1 and 0: every measure against the reference, and the
      --  unweighted measures against a hard run with the same pixels.
      for Light in Boolean loop
         for S of Integer_Array'[254, 1, 0] loop
            declare
               Image  : constant Ks_Image_8_Grey := Ramp_Scene (Light);
               Levels : constant Level_Map :=
                 Ref_Levels (Image, Light, 50, 200, S);
               E      : constant Ref_Measures :=
                 Ref_Measure (Levels, S, 0, 0, 59, 39);
               Polar  : constant Ks_Blob_Segmentation_Polarity_Constants :=
                 (if Light then Light_Blobs else Dark_Blobs);
               What   : constant String :=
                 "fixed [50, 200) " & (if Light then "light" else "dark")
                 & " S =" & S'Image;
               --  The pixels of level above 0: from 50 up for light blobs
               --  (from 200 when S = 0), below 200 for dark ones (below
               --  50 when S = 0).
               T      : constant Integer :=
                 (if Light = (S > 0) then 50 else 200);
            begin
               Tool := Light_Tool (Image);
               Set_Segmentation_Soft_Fixed_Threshold
                 (Tool.Run_Params.Segmentation_Params, 50, 200, S, Polar);
               Check (Tool.Run_Params.Segmentation_Params.Mode
                        = Code (Soft_Fixed_Threshold),
                      What & ": the setter sets the mode");
               Tool.Run;
               Check_Accept (Tool, What);
               Check (Count (Tool, False) = 1, What & ": one blob");
               Check_Weighted (Blob (Tool, 0), E, What);
               if S = 0 then
                  Check (Blob (Tool, 0).Area
                           = Real (Blob (Tool, 0).Pixel_Count),
                         What & ": every weight is 1");
               end if;
               Hard := Light_Tool (Image);
               Set_Segmentation_Hard_Fixed_Threshold
                 (Hard.Run_Params.Segmentation_Params, T, Polar);
               Hard.Run;
               declare
                  R  : constant Ks_Blob_Result := Blob (Tool, 0);
                  H  : constant Ks_Blob_Result := Blob (Hard, 0);
                  ID_Soft : constant Ks_Image_16_Grey :=
                    Tool.Results.Create_Blob_ID_Image (False);
                  Same_Support : Boolean := True;
               begin
                  Check (R.Pixel_Count = H.Pixel_Count
                         and then R.Perimeter = H.Perimeter
                         and then R.Pixel_Aligned_Min_X = H.Pixel_Aligned_Min_X
                         and then R.Pixel_Aligned_Max_X = H.Pixel_Aligned_Max_X
                         and then R.Pixel_Aligned_Min_Y = H.Pixel_Aligned_Min_Y
                         and then R.Pixel_Aligned_Max_Y = H.Pixel_Aligned_Max_Y
                         and then R.Not_Clipped = H.Not_Clipped
                         and then R.Label = H.Label,
                         What & ": unweighted measures as the hard run");
                  Check_Near (R.Extrema_Angle_Min_X, H.Extrema_Angle_Min_X,
                              1.0E-9, What & ": extrema box unweighted");
                  Check_Near (R.Extrema_Angle_Max_Y, H.Extrema_Angle_Max_Y,
                              1.0E-9, What & ": extrema box unweighted (y)");
                  Check_Near (R.Median_Extrema_Angle_X,
                              H.Median_Extrema_Angle_X, 1.0E-9,
                              What & ": median unweighted");
                  Check_Near (Tool.Results.Get_Median_Y (0, Selected_Space),
                              Hard.Results.Get_Median_Y (0, Selected_Space),
                              1.0E-9, What & ": GetMedianY unweighted");
                  Check (Tool.Results.Get_Boundary (0).Num_Vertices
                           = Hard.Results.Get_Boundary (0).Num_Vertices,
                         What & ": the same boundary");
                  for Y in Levels'Range (1) loop
                     for X in Levels'Range (2) loop
                        if (ID_Soft.Get_Pixel (X, Y) /= 0)
                          /= (Levels (Y, X) > 0)
                        then
                           Same_Support := False;
                        end if;
                     end loop;
                  end loop;
                  Check (Same_Support,
                         What & ": the blob's pixels are those of level "
                         & "above 0 (the rule, pixel by pixel)");
               end;
            end;
         end loop;
      end loop;

      --  A fixture space scaling by 1/2 (pixels are twice as large):
      --  the weighted area scales by abs det, the centre maps.
      declare
         Image  : Ks_Image_8_Grey := Ramp_Scene (True);
         Tree   : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
         Levels : constant Level_Map := Ref_Levels (Image, True, 50, 200, 7);
         E      : constant Ref_Measures :=
           Ref_Measure (Levels, 7, 0, 0, 59, 39);
         Pose   : constant Ks_Transform_2D_Linear :=
           Create_Similarity (2.0, 0.3, 5.0, -3.0);
         X, Y   : Real;
      begin
         Tree.Add_Space ("@", "Fixture", Pose);
         Image.Set_Coordinate_Space_Tree (Tree);
         Image.Set_Selected_Space_Name ("@\Fixture");
         Tool := Light_Tool (Image);
         Set_Segmentation_Soft_Fixed_Threshold
           (Tool.Run_Params.Segmentation_Params, 50, 200, 7, Light_Blobs);
         Tool.Run;
         Invert (Pose).Map_Point (E.Cx, E.Cy, X, Y);
         Check_Near (Blob (Tool, 0).Area, E.Area / 4.0, 1.0E-9 * E.Area,
                     "fixture: weighted area scaled by abs det");
         Check_Near (Blob (Tool, 0).Center_Of_Mass_X, X, 1.0E-9,
                     "fixture: weighted centre mapped (X)");
         Check_Near (Blob (Tool, 0).Center_Of_Mass_Y, Y, 1.0E-9,
                     "fixture: weighted centre mapped (Y)");
         Check_Near (Blob (Tool, 0).Inertia_Max,
                     ((E.Mxx + E.Myy) / 2.0
                      + Ada.Numerics.Long_Elementary_Functions.Sqrt
                          (((E.Mxx - E.Myy) / 2.0) ** 2 + E.Mxy ** 2))
                     / 16.0,
                     1.0E-9 * (E.Mxx + E.Myy),
                     "fixture: weighted inertia scaled by the fourth power");
         Check_Angle_Near (Blob (Tool, 0).Angle,
                           0.5 * Ada.Numerics.Long_Elementary_Functions
                                   .Arctan (E.Mxy, (E.Mxx - E.Myy) / 2.0)
                           - 0.3,
                           1.0E-7, "fixture: weighted angle turned");
      end;

      --  The relative mode with tails: the tail levels found by sorting
      --  every pixel, the band placed between them, rounded up.
      declare
         Image : Ks_Image_8_Grey := Blank (80, 60, 30);
         type Grey_List is array (Positive range <>) of Integer;
         procedure Sort is new Ada.Containers.Generic_Array_Sort
           (Positive, Integer, Grey_List);
         Greys : Grey_List (1 .. 80 * 60);
         Dots  : constant Integer_Array := [5, 70, 15, 60, 75, 65];
         --  Bright pixels at (P, 5 + P / 2), away from the ramp.
         N     : constant Integer := Greys'Length;
         function Ceiling_Percent (Span, P : Integer) return Integer is
           (Integer (Real'Ceiling (Real (Span) * Real (P) / 100.0)));
      begin
         for Y in 20 .. 29 loop
            for X in 20 .. 49 loop
               Image.Set_Pixel
                 (X, Y, Grey_8 (60 + 5 * (X - 20) + 2 * (Y - 20)));
            end loop;
         end loop;
         --  Bright and dark single pixels in the background: they move
         --  the tail levels unless the tails set them aside.
         for P of Dots loop
            Image.Set_Pixel (P, 5 + P / 2, 250);
         end loop;
         for P of Integer_Array'[10, 30, 66] loop
            Image.Set_Pixel (P, 50, 0);
         end loop;
         for Y in 0 .. 59 loop
            for X in 0 .. 79 loop
               Greys (1 + Y * 80 + X) := Integer (Image.Get_Pixel (X, Y));
            end loop;
         end loop;
         Sort (Greys);
         for Tails of Integer_Array'[0, 1, 3] loop
            for Light in Boolean loop
               declare
                  Tail_Low  : constant Integer := Tails;
                  Tail_High : constant Integer := (Tails + 1) mod 3;
                  Lo_Rank   : constant Integer :=
                    Integer'Min (N * Tail_Low / 100, N - 1);
                  Hi_Rank   : constant Integer :=
                    Integer'Max (Lo_Rank, N - 1 - N * Tail_High / 100);
                  Low_Tail  : constant Integer := Greys (1 + Lo_Rank);
                  High_Tail : constant Integer :=
                    Integer'Max (Low_Tail, Greys (1 + Hi_Rank));
                  L : constant Integer :=
                    Low_Tail + Ceiling_Percent (High_Tail - Low_Tail, 40);
                  H : constant Integer :=
                    Low_Tail + Ceiling_Percent (High_Tail - Low_Tail, 60);
                  S : constant Integer := (if Light then 10 else 254);
                  Levels : constant Level_Map :=
                    Ref_Levels (Image, Light, L, H, S);
                  E : constant Ref_Measures :=
                    Ref_Measure (Levels, S, 20, 20, 49, 29);
                  Polar : constant Ks_Blob_Segmentation_Polarity_Constants :=
                    (if Light then Light_Blobs else Dark_Blobs);
                  What  : constant String :=
                    "relative 40 .. 60 percent, tails" & Tail_Low'Image
                    & Tail_High'Image & (if Light then " light" else " dark")
                    & " (band" & L'Image & H'Image & ")";
                  Fixed : Ks_Blob_Tool;
               begin
                  Tool := Light_Tool (Image);
                  Tool.Run_Params.Sort_Enabled := Code (True);
                  Set_Segmentation_Soft_Relative_Threshold
                    (Tool.Run_Params.Segmentation_Params, Tail_Low,
                     Tail_High, 40, 60, S, Polar);
                  Tool.Run;
                  Check_Accept (Tool, What);
                  if Light then
                     --  The bright dots are blobs of one pixel, filled away.
                     Check (Count (Tool) = 1, What & ": the ramp only");
                     Check_Weighted (Blob (Tool, 0), E, What);
                  else
                     --  Dark blobs: the background (30) is darker than
                     --  the band, so it is the large blob with the ramp's
                     --  dark part; the bright dots are one-pixel holes in
                     --  it that Fill gives to it at full weight.
                     declare
                        Filled : Level_Map := Levels;
                     begin
                        for P of Dots loop
                           Filled (5 + P / 2, P) := S + 1;
                        end loop;
                        Check_Weighted
                          (Blob (Tool, 0),
                           Ref_Measure (Filled, S, 0, 0, 79, 59), What);
                     end;
                  end if;
                  --  The same band given as fixed thresholds gives the
                  --  same results.
                  Fixed := Light_Tool (Image);
                  Fixed.Run_Params.Sort_Enabled := Code (True);
                  Set_Segmentation_Soft_Fixed_Threshold
                    (Fixed.Run_Params.Segmentation_Params, L,
                     Integer'Max (H, L + 1), S, Polar);
                  if H > L then
                     Fixed.Run;
                     Check (Count (Fixed) = Count (Tool)
                            and then Blob (Fixed, 0) = Blob (Tool, 0),
                            What & ": as the fixed band");
                  end if;
               end;
            end loop;
         end loop;

         --  Low = High: an empty band, the hard relative threshold.
         Tool := Light_Tool (Image);
         Set_Segmentation_Soft_Relative_Threshold
           (Tool.Run_Params.Segmentation_Params, 1, 1, 50, 50, 254,
            Light_Blobs);
         Tool.Run;
         Hard := Light_Tool (Image);
         Set_Segmentation_Hard_Relative_Threshold
           (Hard.Run_Params.Segmentation_Params, 1, 1, 50, Light_Blobs);
         Hard.Run;
         Check (Count (Tool) = 1 and then Count (Hard) = 1
                and then Blob (Tool, 0).Pixel_Count
                           = Blob (Hard, 0).Pixel_Count,
                "Low = High: the pixels of the hard relative threshold");
         Check_Near (Blob (Tool, 0).Area, Blob (Hard, 0).Area,
                     1.0E-9 * Blob (Hard, 0).Area,
                     "Low = High: every weight is 1");
         Check_Near (Blob (Tool, 0).Center_Of_Mass_X,
                     Blob (Hard, 0).Center_Of_Mass_X, 1.0E-9,
                     "Low = High: the hard centre of mass");
         Check_Near (Blob (Tool, 0).Inertia_Min, Blob (Hard, 0).Inertia_Min,
                     1.0E-9 * Blob (Hard, 0).Inertia_Min,
                     "Low = High: the hard moments");
      end;

      --  Morphology on the levels: erosion is the least level of the
      --  element's pixels in the region, dilation the greatest.
      declare
         Image  : constant Ks_Image_8_Grey := Ramp_Scene (True);
         Levels : constant Level_Map := Ref_Levels (Image, True, 50, 200, 9);
         type Op_List is array (Positive range <>)
           of Ks_Blob_Morphology_Constants;
         function Morph (L : Level_Map; Op : Ks_Blob_Morphology_Constants)
                         return Level_Map
         is
            Code_Value : constant Natural :=
              Ks_Blob_Morphology_Constants'Pos (Op);
            RX : constant Integer := (if Code_Value mod 3 = 1 then 0 else 1);
            RY : constant Integer := (if Code_Value mod 3 = 0 then 0 else 1);
            Dilate : constant Boolean := Code_Value in 3 .. 5;
            Result : Level_Map (L'Range (1), L'Range (2));
         begin
            for Y in L'Range (1) loop
               for X in L'Range (2) loop
                  Result (Y, X) := L (Y, X);
                  for DY in -RY .. RY loop
                     for DX in -RX .. RX loop
                        if Y + DY in L'Range (1) and then X + DX in L'Range (2)
                        then
                           Result (Y, X) :=
                             (if Dilate
                              then Integer'Max (Result (Y, X),
                                                L (Y + DY, X + DX))
                              else Integer'Min (Result (Y, X),
                                                L (Y + DY, X + DX)));
                        end if;
                     end loop;
                  end loop;
               end loop;
            end loop;
            return Result;
         end Morph;
         procedure Try (Ops : Op_List; Expected : Level_Map; What : String) is
         begin
            Tool := Light_Tool (Image);
            Tool.Run_Params.Connectivity_Cleanup :=
              Code (Ks_Blob_Connectivity_Cleanup_Constants'(None));
            Set_Segmentation_Soft_Fixed_Threshold
              (Tool.Run_Params.Segmentation_Params, 50, 200, 9, Light_Blobs);
            for Op of Ops loop
               Add (Tool.Run_Params.Morphology_Operations, Op);
            end loop;
            Tool.Run;
            Check (Count (Tool) = 1, What & ": one blob");
            Check_Weighted (Blob (Tool, 0),
                            Ref_Measure (Expected, 9, 0, 0, 59, 39), What);
         end Try;
      begin
         Try ([Erode_Horizontal], Morph (Levels, Erode_Horizontal),
              "soft erode horizontal");
         Try ([Erode_Square], Morph (Levels, Erode_Square),
              "soft erode square");
         Try ([Dilate_Vertical], Morph (Levels, Dilate_Vertical),
              "soft dilate vertical");
         Try ([Dilate_Square], Morph (Levels, Dilate_Square),
              "soft dilate square");
         Try ([Close_Horizontal],
              Morph (Morph (Levels, Dilate_Horizontal), Erode_Horizontal),
              "soft close horizontal (dilation, then erosion)");
         Try ([Open_Square, Dilate_Horizontal],
              Morph (Morph (Morph (Levels, Erode_Square), Dilate_Square),
                     Dilate_Horizontal),
              "soft open square, then dilate horizontal");
      end;

      --  Cleanup. A 30 x 20 blob of grey 120 (band [100, 200), S = 4:
      --  level 1, weight 1/5) with a 2 x 2 hole, and a 10 x 8 hole that
      --  holds a 2 x 2 blob of grey 170 (level 3, weight 3/5).
      declare
         Image : Ks_Image_8_Grey := Blank (60, 40);
         procedure Fill_Box (X0, Y0, X1, Y1 : Natural; G : Grey_8) is
         begin
            for Y in Y0 .. Y1 loop
               for X in X0 .. X1 loop
                  Image.Set_Pixel (X, Y, G);
               end loop;
            end loop;
         end Fill_Box;
      begin
         Fill_Box (10, 10, 39, 29, 120);
         Fill_Box (20, 15, 21, 16, 0);
         Fill_Box (26, 14, 35, 21, 0);
         Fill_Box (30, 17, 31, 18, 170);
         declare
            Levels : Level_Map := Ref_Levels (Image, True, 100, 200, 4);
            Outer  : Ref_Measures;
         begin
            --  The blob alone (the inner blob is not part of it).
            for Y in 17 .. 18 loop
               for X in 30 .. 31 loop
                  Levels (Y, X) := 0;
               end loop;
            end loop;
            Outer := Ref_Measure (Levels, 4, 0, 0, 59, 39);
            Tool := Light_Tool (Image);
            Set_Segmentation_Soft_Fixed_Threshold
              (Tool.Run_Params.Segmentation_Params, 100, 200, 4,
               Light_Blobs);
            Tool.Run_Params.Connectivity_Cleanup :=
              Code (Ks_Blob_Connectivity_Cleanup_Constants'(None));
            Tool.Run;
            Check (Count (Tool, False) = 4,
                   "soft, no cleanup: blob, two holes, inner blob");
            Check_Weighted (Blob (Tool, 0, False), Outer,
                            "soft, no cleanup: the outer blob");
            --  IDs in raster order: the large hole (first row 14) before
            --  the small one (row 15).
            Check (Blob (Tool, 1, False).Label = 0
                   and then Blob (Tool, 1, False).Area = 76.0
                   and then Blob (Tool, 2, False).Label = 0
                   and then Blob (Tool, 2, False).Area = 4.0,
                   "soft: holes count every pixel fully");
            Check_Near (Blob (Tool, 3, False).Area, 4.0 * 3.0 / 5.0, 1.0E-12,
                        "soft, no cleanup: the inner blob weighs 3/5 a pixel");
            Check (Blob (Tool, 3, False).Pixel_Count = 4,
                   "soft, no cleanup: the inner blob has 4 pixels");

            Tool.Run_Params.Connectivity_Cleanup := Code (Fill);
            Tool.Run;
            Check (Count (Tool, False) = 2,
                   "soft fill: the small hole and the inner blob are gone");
            --  The small hole is filled into the blob with full weight.
            for Y in 15 .. 16 loop
               for X in 20 .. 21 loop
                  Levels (Y, X) := 5;
               end loop;
            end loop;
            Check_Weighted (Blob (Tool, 0, False),
                            Ref_Measure (Levels, 4, 0, 0, 59, 39),
                            "soft fill: a filled hole weighs fully");
            Check (Blob (Tool, 1, False).Label = 0
                   and then Blob (Tool, 1, False).Pixel_Count = 80
                   and then Blob (Tool, 1, False).Area = 80.0,
                   "soft fill: the inner blob is filled into the hole, "
                   & "which counts its pixels fully");

            Tool.Run_Params.Connectivity_Cleanup := Code (Prune);
            Tool.Run;
            for Y in 15 .. 16 loop
               for X in 20 .. 21 loop
                  Levels (Y, X) := 0;
               end loop;
            end loop;
            Check (Count (Tool, False) = 2
                   and then Blob (Tool, 1, False).Area = 76.0,
                   "soft prune: the blob and the large hole are left");
            Check_Weighted (Blob (Tool, 0, False),
                            Ref_Measure (Levels, 4, 0, 0, 59, 39),
                            "soft prune: the outer blob");
            --  ConnectivityMinPixels counts pixels: the inner blob (4
            --  pixels, weight 2.4) survives a minimum of 3.
            Tool.Run_Params.Connectivity_Min_Pixels := 3;
            Tool.Run;
            Check (Count (Tool, False) = 4,
                   "soft: the minimum counts pixels, not weights");
         end;
      end;

      --  Filters and sorting use the weighted Area. Band [100, 200),
      --  S = 3: A 10 x 10 of grey 100 (weight 1/4, area 25), B 6 x 6 of
      --  255 (area 36), C 8 x 8 of 150 (weight 1/2, area 32).
      declare
         Image : Ks_Image_8_Grey := Blank (80, 40);
      begin
         for Y in 5 .. 14 loop
            for X in 5 .. 14 loop
               Image.Set_Pixel (X, Y, 100);
            end loop;
         end loop;
         for Y in 5 .. 10 loop
            for X in 30 .. 35 loop
               Image.Set_Pixel (X, Y, 255);
            end loop;
         end loop;
         for Y in 20 .. 27 loop
            for X in 50 .. 57 loop
               Image.Set_Pixel (X, Y, 150);
            end loop;
         end loop;
         Tool := Light_Tool (Image);
         Set_Segmentation_Soft_Fixed_Threshold
           (Tool.Run_Params.Segmentation_Params, 100, 200, 3, Light_Blobs);
         Tool.Run_Params.Sort_Enabled := Code (True);
         Tool.Run;
         Check (Count (Tool) = 3
                and then Blob (Tool, 0).Area = 36.0
                and then Blob (Tool, 1).Area = 32.0
                and then Blob (Tool, 2).Area = 25.0
                and then Blob (Tool, 2).Pixel_Count = 100,
                "soft: sorted by the weighted area (B, C, A)");
         Add (Tool.Run_Params.Run_Time_Measures,
              Blob_Measure (Area, Filter, Include_Blobs_In_Range, 24.0,
                            30.0));
         Tool.Run;
         Check (Count (Tool) = 1 and then Blob (Tool, 0).Pixel_Count = 100,
                "soft: a filter on the weighted area keeps A only");
      end;

      --  The setters and the checks of Run.
      declare
         P : Ks_Blob_Segmentation_Params;
         procedure Expect_Bad (Action : not null access procedure;
                               What   : String) is
            Before : constant Ks_Blob_Segmentation_Params := P;
         begin
            Action.all;
            Fail (What & ": no exception");
         exception
            when AMV.Ks_Bad_Parameter_Exception =>
               Check (P = Before,
                      What & ": Ks_Bad_Parameter_Exception, unchanged");
         end Expect_Bad;
         procedure Low_Below is
         begin
            Set_Segmentation_Soft_Fixed_Threshold (P, -1, 10, 5, Light_Blobs);
         end Low_Below;
         procedure Low_Above is
         begin
            Set_Segmentation_Soft_Fixed_Threshold
              (P, 65_535, 65_535, 5, Light_Blobs);
         end Low_Above;
         procedure High_Below is
         begin
            Set_Segmentation_Soft_Fixed_Threshold (P, 0, 0, 5, Light_Blobs);
         end High_Below;
         procedure High_Above is
         begin
            Set_Segmentation_Soft_Fixed_Threshold
              (P, 0, 65_536, 5, Light_Blobs);
         end High_Above;
         procedure Equal is
         begin
            Set_Segmentation_Soft_Fixed_Threshold
              (P, 100, 100, 5, Light_Blobs);
         end Equal;
         procedure Softness_Above is
         begin
            Set_Segmentation_Soft_Fixed_Threshold
              (P, 100, 101, 255, Light_Blobs);
         end Softness_Above;
         procedure Softness_Below is
         begin
            Set_Segmentation_Soft_Relative_Threshold
              (P, 0, 0, 40, 60, -1, Light_Blobs);
         end Softness_Below;
         procedure Tails_Sum is
         begin
            Set_Segmentation_Soft_Relative_Threshold
              (P, 60, 41, 40, 60, 5, Light_Blobs);
         end Tails_Sum;
         procedure Tail_Above is
         begin
            Set_Segmentation_Soft_Relative_Threshold
              (P, 101, 0, 40, 60, 5, Light_Blobs);
         end Tail_Above;
         procedure Relative_Order is
         begin
            Set_Segmentation_Soft_Relative_Threshold
              (P, 0, 0, 61, 60, 5, Light_Blobs);
         end Relative_Order;
         procedure Relative_Above is
         begin
            Set_Segmentation_Soft_Relative_Threshold
              (P, 0, 0, 40, 101, 5, Light_Blobs);
         end Relative_Above;
         procedure Hard_Fixed_Above is
         begin
            Set_Segmentation_Hard_Fixed_Threshold (P, 65_536, Dark_Blobs);
         end Hard_Fixed_Above;
         procedure Hard_Relative_Tails is
         begin
            Set_Segmentation_Hard_Relative_Threshold
              (P, 50, 51, 50, Dark_Blobs);
         end Hard_Relative_Tails;
         procedure Hard_Relative_Above is
         begin
            Set_Segmentation_Hard_Relative_Threshold
              (P, 0, 0, 101, Dark_Blobs);
         end Hard_Relative_Above;
         procedure Dynamic_Tail is
         begin
            Set_Segmentation_Hard_Dynamic_Threshold (P, -1, 0, Dark_Blobs);
         end Dynamic_Tail;
      begin
         Set_Segmentation_Soft_Fixed_Threshold (P, 10, 20, 5, Light_Blobs);
         Check (P.Mode = Code (Soft_Fixed_Threshold)
                and then P.Soft_Fixed_Threshold_Low = 10
                and then P.Soft_Fixed_Threshold_High = 20
                and then P.Softness = 5
                and then P.Polarity = Code (Light_Blobs)
                and then P.Hard_Fixed_Threshold = 128
                and then P.Soft_Relative_Threshold_Low = 40,
                "SetSegmentationSoftFixedThreshold sets its fields only");
         Set_Segmentation_Soft_Relative_Threshold
           (P, 5, 7, 30, 30, 0, Dark_Blobs);
         Check (P.Mode = Code (Soft_Relative_Threshold)
                and then P.Tail_Low = 5 and then P.Tail_High = 7
                and then P.Soft_Relative_Threshold_Low = 30
                and then P.Soft_Relative_Threshold_High = 30
                and then P.Softness = 0
                and then P.Polarity = Code (Dark_Blobs)
                and then P.Soft_Fixed_Threshold_Low = 10,
                "SetSegmentationSoftRelativeThreshold sets its fields only");
         Set_Segmentation_Hard_Fixed_Threshold (P, 65_535, Light_Blobs);
         Check (P.Mode = Code (Hard_Fixed_Threshold)
                and then P.Hard_Fixed_Threshold = 65_535
                and then P.Polarity = Code (Light_Blobs)
                and then P.Tail_Low = 5,
                "SetSegmentationHardFixedThreshold");
         Set_Segmentation_Hard_Relative_Threshold (P, 60, 40, 0, Dark_Blobs);
         Check (P.Mode = Code (Hard_Relative_Threshold)
                and then P.Tail_Low = 60 and then P.Tail_High = 40
                and then P.Hard_Relative_Threshold = 0
                and then P.Polarity = Code (Dark_Blobs),
                "SetSegmentationHardRelativeThreshold");
         Set_Segmentation_Hard_Dynamic_Threshold (P, 1, 2, Light_Blobs);
         Check (P.Mode = Code (Hard_Dynamic_Threshold)
                and then P.Tail_Low = 1 and then P.Tail_High = 2
                and then P.Hard_Relative_Threshold = 0
                and then P.Polarity = Code (Light_Blobs),
                "SetSegmentationHardDynamicThreshold");
         Expect_Bad (Low_Below'Access, "soft fixed: Low -1");
         Expect_Bad (Low_Above'Access, "soft fixed: Low 65535");
         Expect_Bad (High_Below'Access, "soft fixed: High 0");
         Expect_Bad (High_Above'Access, "soft fixed: High 65536");
         Expect_Bad (Equal'Access, "soft fixed: Low = High");
         Expect_Bad (Softness_Above'Access, "soft fixed: Softness 255");
         Expect_Bad (Softness_Below'Access, "soft relative: Softness -1");
         Expect_Bad (Tails_Sum'Access, "soft relative: tails 60 + 41");
         Expect_Bad (Tail_Above'Access, "soft relative: TailLow 101");
         Expect_Bad (Relative_Order'Access, "soft relative: Low > High");
         Expect_Bad (Relative_Above'Access, "soft relative: High 101");
         Expect_Bad (Hard_Fixed_Above'Access, "hard fixed: 65536");
         Expect_Bad (Hard_Relative_Tails'Access, "hard relative: tails 101");
         Expect_Bad (Hard_Relative_Above'Access, "hard relative: 101");
         Expect_Bad (Dynamic_Tail'Access, "hard dynamic: TailLow -1");

         --  Run checks every soft field, whatever the mode.
         Tool := Light_Tool (Ramp_Scene (True));
         Tool.Run_Params.Segmentation_Params.Softness := 255;
         Tool.Run;
         Check (Tool.Run_Status.Exception_Name
                  = "AMV.KS_BAD_PARAMETER_EXCEPTION"
                and then Tool.Run_Status.Message
                  = "RunParams.SegmentationParams.Softness must be in "
                    & "0 .. 254",
                "Run: Softness 255 in a hard mode");
         Tool.Run_Params.Segmentation_Params.Softness := 0;
         Tool.Run_Params.Segmentation_Params.Soft_Fixed_Threshold_Low := 153;
         Tool.Run;
         Check (Tool.Run_Status.Message
                  = "RunParams.SegmentationParams.SoftFixedThresholdLow "
                    & "must be < SoftFixedThresholdHigh",
                "Run: SoftFixedThresholdLow = High");
         Tool.Run_Params.Segmentation_Params.Soft_Fixed_Threshold_Low := 0;
         Tool.Run_Params.Segmentation_Params.Soft_Fixed_Threshold_High :=
           65_536;
         Tool.Run;
         Check (Tool.Run_Status.Message
                  = "RunParams.SegmentationParams.SoftFixedThresholdHigh "
                    & "must be in 1 .. 65535",
                "Run: SoftFixedThresholdHigh 65536");
         Tool.Run_Params.Segmentation_Params.Soft_Fixed_Threshold_High := 1;
         Tool.Run_Params.Segmentation_Params.Soft_Relative_Threshold_Low :=
           61;
         Tool.Run;
         Check (Tool.Run_Status.Message
                  = "RunParams.SegmentationParams.SoftRelativeThresholdLow "
                    & "must be <= SoftRelativeThresholdHigh",
                "Run: SoftRelativeThresholdLow > High");
         Tool.Run_Params.Segmentation_Params.Soft_Relative_Threshold_Low :=
           -1;
         Tool.Run;
         Check (Tool.Run_Status.Message
                  = "RunParams.SegmentationParams.SoftRelativeThresholdLow "
                    & "must be in 0 .. 100",
                "Run: SoftRelativeThresholdLow -1");
         Tool.Run_Params.Segmentation_Params.Soft_Relative_Threshold_Low :=
           0;
         Tool.Run_Params.Segmentation_Params.Mode :=
           Code (Soft_Fixed_Threshold);
         Tool.Run;
         Check_Accept (Tool, "soft fixed [0, 1), softness 0");
         Check (Count (Tool) = 1 and then Blob (Tool, 0).Pixel_Count = 300,
                "soft fixed [0, 1): every pixel of the ramp is full");
      end;
   end Test_Soft_Thresholds;

   ---------------------------------------------------------------------
   --  Noise and speed
   ---------------------------------------------------------------------

   procedure Test_Noise_And_Speed is
      Image    : Ks_Image_8_Grey := Blank (640, 480, 50);
      Tool     : Ks_Blob_Tool;
      Total    : Natural := 0;
      Expected : Real := 0.0;
   begin
      Section ("Blob: noise and a 640 x 480 run");
      for I in 0 .. 4 loop
         for J in 0 .. 3 loop
            Draw_Circle (Image, 60.0 + 125.0 * Real (I) + 0.3,
                         60.0 + 115.0 * Real (J) + 0.6, 20.0 + Real (I + J),
                         Value => 200);
            Expected := Expected + Pi * (20.0 + Real (I + J)) ** 2;
         end loop;
      end loop;
      Add_Noise (Image, 60.0, Seed => 3);
      Tool := Light_Tool (Image);
      Tool.Run_Params.Sort_Enabled := Code (True);
      Tool.Run;
      Check_Accept (Tool, "640 x 480");
      Check (Count (Tool) = 20, "20 discs found through the noise"
             & Img (Count (Tool)));
      for K in 0 .. Count (Tool) - 1 loop
         Total := Total + Natural (Blob (Tool, K).Pixel_Count);
      end loop;
      Check (Count (Tool) = 0 or else Blob (Tool, 0).Pixel_Count
               >= Blob (Tool, Count (Tool) - 1).Pixel_Count,
             "sorted by area");
      Check (abs (Real (Total) - Expected) / Expected < 0.03,
             "total area of the discs within 3 percent");
      Check (Tool.Run_Status.Processing_Time < 1000.0,
             "a 640 x 480 run takes well under a second");
      Ada.Text_IO.Put_Line
        ("  640 x 480 blob run:" & Tool.Run_Status.Processing_Time'Image
         & " ms");
      Tool.Run_Params.Segmentation_Params.Mode :=
        Code (Hard_Dynamic_Threshold);
      Tool.Run;
      Check (Count (Tool) = 20, "dynamic threshold finds them too");
      Ada.Text_IO.Put_Line
        ("  640 x 480 blob run, dynamic threshold:"
         & Tool.Run_Status.Processing_Time'Image & " ms");
   end Test_Noise_And_Speed;

   ---------------------------------------------------------------------
   --  The kernel directly
   ---------------------------------------------------------------------

   procedure Test_Kernel is
      Status  : AMV.Kernels.Ks_Status;
      Params  : KB.Ks_Blob_Run_Params;
      Results : KB.Ks_Blob_Results;
      Count   : Int32;
      Item    : KB.Ks_Blob_Result;
      Value   : Long_Float;
      Image   : KI.Ks_Image_8_Grey;
      Region  : KR.Ks_Pixel_Region;
      Polygon : KS.Ks_Polygon;
      IDs     : KI.Ks_Image_16_Grey;
      Box     : KS.Ks_Rectangle_Affine;
      Parent  : Int32;
      Ident   : constant KT.Ks_Transform_2D_Linear := (others => <>);
      Zero    : constant Long_Float := Long_Float'Value ("0.0");
      Nan     : constant Long_Float := Zero / Zero;

      function Failed (Code : Int32; Message : String) return Boolean is
        (Status.Failure = Code
         and then String (Status.Message (1 .. Natural (Status.Length)))
                  = Message);
   begin
      Section ("Blob: kernel");
      Check (KB.Ks_Blob_Run_Params'Object_Size = 2288 * 8
             and then KB.Ks_Blob_Result'Size = 528 * 8
             and then KB.Ks_Blob_Measure'Size = 32 * 8
             and then KB.Ks_Blob_Segmentation_Params'Size = 44 * 8,
             "record sizes match include/amv_blob.h");
      KB.Run_Params_Default (Params, Status);
      Check (Status.Failure = 0
             and then Params.Segmentation_Params.Mode = 4
             and then Params.Connectivity_Cleanup = 2,
             "run_params_default");

      --  Null handles.
      KB.Execute (null, null, Params, Ident, Results, Status);
      Check (Failed (AMV.Kernels.Failure_Image_No_Pixels,
                     "InputImage has no pixels") and then Results = null,
             "execute: null image");
      KB.Count (null, 1, Count, Status);
      Check (Status.Failure = 0 and then Count = 0, "count: null results");
      KB.Item (null, 0, 0, Item, Status);
      Check (Failed (AMV.Kernels.Failure_Index_Out_Of_Range,
                     "GetBlobs: index 0 is outside 0 .. -1"),
             "item: null results");
      KB.Get_Blob_By_ID (null, 0, Item, Status);
      Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                     "GetBlobByID: no blob has ID 0"),
             "get_blob_by_id: null results");
      KB.Get_Parent (null, 0, Parent, Status);
      Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter
             and then Parent = -1, "get_parent: null results");
      KB.Get_Boundary (null, 0, Polygon, Status);
      Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter
             and then Polygon = null, "get_boundary: null results");
      KB.Create_Blob_ID_Image (null, 1, IDs, Status);
      Check (Status.Failure = AMV.Kernels.Failure_Image_No_Pixels
             and then IDs = null, "create_blob_id_image: null results");
      KB.Destroy (Results, Status);
      Check (Status.Failure = 0 and then Results = null, "destroy null");

      --  An image with a 3 x 2 blob and the empty region.
      KI.Create (8, 6, 0, Image, Status);
      for Y in 2 .. 3 loop
         for X in 1 .. 3 loop
            KI.Set_Pixel (Image, Int32 (X), Int32 (Y), 255, Status);
         end loop;
      end loop;
      Params.Segmentation_Params.Mode := KB.Segmentation_Hard_Fixed_Threshold;
      Params.Segmentation_Params.Polarity := KB.Polarity_Light_Blobs;
      Params.Connectivity_Min_Pixels := 0;
      KB.Execute (Image, null, Params, Ident, Results, Status);
      KB.Count (Results, 0, Count, Status);
      Check (Status.Failure = 0 and then Count = 0,
             "execute: the empty region finds nothing");
      KB.Destroy (Results, Status);

      KR.Whole_Image (8, 6, Region, Status);
      KB.Execute (Image, Region, Params, Ident, Results, Status);
      Check (Status.Failure = 0 and then Results /= null, "execute");
      KB.Count (Results, 1, Count, Status);
      Check (Count = 1, "one blob");
      KB.Count (Results, 2, Count, Status);
      Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                     "GetBlobs: Filtered must be 0 or 1") and then Count = 0,
             "count: a bad Filtered flag");
      KB.Item (Results, 1, 1, Item, Status);
      Check (Failed (AMV.Kernels.Failure_Index_Out_Of_Range,
                     "GetBlobs: index 1 is outside 0 .. 0"),
             "item: index out of range");
      KB.Item (Results, 1, 0, Item, Status);
      Check (Status.Failure = 0 and then Item.Pixel_Count = 6
             and then Item.Area = 6.0, "item 0");
      KB.Get_Measure (Item, KB.Measure_Acircularity_Rms, Value, Status);
      Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                     "GetMeasure: Measure: measure 14 is not supported")
             and then Value = 0.0, "get_measure: not computed");
      KB.Get_Measure (Item, 99, Value, Status);
      Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter,
             "get_measure: not a measure");
      KB.Get_Measure (Item, KB.Measure_Center_Mass_X, Value, Status);
      Check (Status.Failure = 0 and then Value = 2.0, "get_measure");
      KB.Get_Bounding_Box (Item, KB.Axis_Extrema_Angle, Box, Status);
      Check (Status.Failure = 0 and then Box.Side_X_Length = 3.0
             and then Box.Side_Y_Length = 2.0 and then Box.Center_X = 2.0
             and then Box.Center_Y = 2.5 and then Box.Rotation = 0.0,
             "get_bounding_box: extrema angle (0 by default)");
      Check (Item.Extrema_Angle_Min_X = 0.5
             and then Item.Extrema_Angle_Max_Y = 3.5
             and then Item.Extrema_Angle_Width = 3.0
             and then Item.Median_Extrema_Angle_X = 2.0
             and then Item.Median_Extrema_Angle_Y = 2.5,
             "extrema-angle measures of the 3 x 2 blob (even count)");
      KB.Get_Median_X (Results, 0, KB.Axis_Selected_Space, Value, Status);
      Check (Status.Failure = 0 and then Value = 2.0,
             "get_median_x: the mean of 2 and 2");
      KB.Get_Median_Y (Results, 0, KB.Axis_Pixel_Aligned, Value, Status);
      Check (Status.Failure = 0 and then Value = 2.5,
             "get_median_y: the mean of 2 and 3");
      KB.Get_Median_X (Results, 0, KB.Axis_Principal, Value, Status);
      Check (Status.Failure = 0 and then Value = 0.0,
             "get_median_x: principal, from the centre of mass");
      KB.Get_Median_Y (Results, 0, KB.Axis_Extrema_Angle, Value, Status);
      Check (Status.Failure = 0 and then Value = 2.5,
             "get_median_y: extrema angle, the measure");
      KB.Get_Median_X (Results, 0, 5, Value, Status);
      Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                     "GetMedianX: Axis must be a CogBlobAxisConstants "
                     & "value (0 .. 4)") and then Value = 0.0,
             "get_median_x: not an axis");
      KB.Get_Median_Y (Results, 1, 0, Value, Status);
      Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                     "GetMedianY: no blob has ID 1"),
             "get_median_y: an unknown ID");
      KB.Get_Median_X (null, 0, 0, Value, Status);
      Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                     "GetMedianX: no blob has ID 0"),
             "get_median_x: null results");
      KB.Get_Bounding_Box_At_Angle (Results, 0, Pi / 2.0, Box, Status);
      Check (Status.Failure = 0
             and then abs (Box.Side_X_Length - 2.0) < 1.0E-12
             and then abs (Box.Side_Y_Length - 3.0) < 1.0E-12
             and then abs (Box.Center_X - 2.0) < 1.0E-12
             and then abs (Box.Center_Y - 2.5) < 1.0E-12
             and then Box.Rotation = Pi / 2.0,
             "get_bounding_box_at_angle: a quarter turn");
      KB.Get_Bounding_Box_At_Angle (Results, 0, Nan, Box, Status);
      Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                     "GetBoundingBoxAtAngle: Angle must be finite and "
                     & "within +/-1.0E6"),
             "get_bounding_box_at_angle: a NaN angle");
      KB.Get_Bounding_Box_At_Angle (Results, 1, 0.0, Box, Status);
      Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                     "GetBoundingBoxAtAngle: no blob has ID 1"),
             "get_bounding_box_at_angle: an unknown ID");
      KB.Get_Bounding_Box_At_Angle (null, 0, 0.0, Box, Status);
      Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter,
             "get_bounding_box_at_angle: null results");
      KB.Get_Bounding_Box (Item, 5, Box, Status);
      Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter,
             "get_bounding_box: not an axis");
      KB.Get_Bounding_Box (Item, KB.Axis_Pixel_Aligned_No_Exclude, Box,
                           Status);
      Check (Status.Failure = 0 and then Box.Side_X_Length = 3.0
             and then Box.Center_X = 2.0, "get_bounding_box");
      KB.Get_Parent (Results, 0, Parent, Status);
      Check (Status.Failure = 0 and then Parent = -1, "get_parent: none");
      KB.Get_Boundary (Results, 0, Polygon, Status);
      Check (Status.Failure = 0 and then Polygon /= null
             and then Polygon.Count = 4, "get_boundary");
      KS.Destroy (Polygon, Status);
      KB.Create_Blob_ID_Image (Results, 2, IDs, Status);
      Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter
             and then IDs = null, "create_blob_id_image: bad flag");
      KB.Create_Blob_ID_Image (Results, 0, IDs, Status);
      Check (Status.Failure = 0 and then IDs /= null
             and then IDs.Pixels (2, 1) = 1 and then IDs.Pixels (0, 0) = 0,
             "create_blob_id_image");
      KI.Destroy (IDs, Status);
      KB.Destroy (Results, Status);

      --  Bad arguments.
      declare
         Bad_T : KT.Ks_Transform_2D_Linear := (others => <>);
      begin
         Bad_T.A := 1.0E30;
         KB.Execute (Image, Region, Params, Bad_T, Results, Status);
         Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter
                and then Results = null, "a transform beyond 2**64");
         Bad_T.A := Nan;
         KB.Execute (Image, Region, Params, Bad_T, Results, Status);
         Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter
                and then Results = null, "a NaN transform");
      end;
      declare
         P : KB.Ks_Blob_Run_Params := Params;
      begin
         P.Run_Time_Measures.Count := 1;
         P.Run_Time_Measures.Items (0).Filter_Range_High := Nan;
         KB.Execute (Image, Region, P, Ident, Results, Status);
         Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                        "RunParams.RunTimeMeasures(0).FilterRangeHigh must "
                        & "be finite"), "a NaN filter range");
         P := Params;
         P.Run_Time_Measures.Count := 65;
         KB.Execute (Image, Region, P, Ident, Results, Status);
         Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter,
                "a run-time measure count beyond 64");
         P := Params;
         P.Morphology_Operations.Count := 1;
         P.Morphology_Operations.Items (0) := 12;
         KB.Execute (Image, Region, P, Ident, Results, Status);
         Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter,
                "a morphology code beyond 11");
         P := Params;
         P.Sort_Enabled := 2;
         KB.Execute (Image, Region, P, Ident, Results, Status);
         Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                        "RunParams.SortEnabled must be 0 or 1"),
                "a Boolean that is not 0 or 1");
         P := Params;
         P.Connectivity_Mode := 3;
         KB.Execute (Image, Region, P, Ident, Results, Status);
         Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter,
                "a connectivity mode beyond 2");
         P := Params;
         P.Segmentation_Params.Polarity := -1;
         KB.Execute (Image, Region, P, Ident, Results, Status);
         Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter,
                "a polarity beyond 1");
         P := Params;
         P.Extrema_Angle := Nan;
         KB.Execute (Image, Region, P, Ident, Results, Status);
         Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                        "RunParams.ExtremaAngle must be finite and within "
                        & "+/-1.0E6") and then Results = null,
                "a NaN extrema angle");
         P.Extrema_Angle := 2.0E6;
         KB.Execute (Image, Region, P, Ident, Results, Status);
         Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter,
                "an extrema angle beyond 1.0E6");
         P := Params;
         P.Save_Segmented_Image_Before_Masking := 2;
         KB.Execute (Image, Region, P, Ident, Results, Status);
         Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                        "RunParams.SaveSegmentedImageBeforeMasking must be "
                        & "0 or 1") and then Results = null,
                "SaveSegmentedImageBeforeMasking not 0 or 1");
      end;
      declare
         Shown : KI.Ks_Image_8_Grey;
         Run   : KB.Ks_Blob_Results;
      begin
         KB.Create_Blob_Image (null, 1, 1, 0, Shown, Status);
         Check (Failed (AMV.Kernels.Failure_Image_No_Pixels,
                        "CreateBlobImage: there are no results")
                and then Shown = null, "create_blob_image: null results");
         KB.Create_Segmented_Image (null, 0, 1, Shown, Status);
         Check (Failed (AMV.Kernels.Failure_Image_No_Pixels,
                        "CreateSegmentedImage: there are no results")
                and then Shown = null,
                "create_segmented_image: null results");
         KB.Execute (Image, Region, Params, Ident, Run, Status);
         Check (Status.Failure = 0, "a run for the images");
         KB.Create_Blob_Image (Run, 2, 1, 0, Shown, Status);
         Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                        "CreateBlobImage: Filtered must be 0 or 1"),
                "create_blob_image: Filtered 2");
         KB.Create_Blob_Image (Run, 1, -1, 0, Shown, Status);
         Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                        "CreateBlobImage: Viewable must be 0 or 1"),
                "create_blob_image: Viewable -1");
         KB.Create_Blob_Image (Run, 1, 0, -1, Shown, Status);
         Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                        "CreateBlobImage: Background must be in 0 .. 255")
                and then Shown = null,
                "create_blob_image: Background -1");
         KB.Create_Segmented_Image (Run, 3, 1, Shown, Status);
         Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                        "CreateSegmentedImage: WhichImage must be FinalImage "
                        & "(0), BeforeMorphology (1) or BeforeMasking (2)"),
                "create_segmented_image: WhichImage 3");
         KB.Create_Segmented_Image (Run, 0, 2, Shown, Status);
         Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                        "CreateSegmentedImage: StretchIt must be 0 or 1"),
                "create_segmented_image: StretchIt 2");
         KB.Create_Segmented_Image (Run, 0, 1, Shown, Status);
         Check (Status.Failure = 0 and then Shown = null,
                "create_segmented_image: not saved gives null");
         KB.Create_Blob_Image (Run, 1, 1, 0, Shown, Status);
         Check (Status.Failure = 0 and then Shown /= null,
                "create_blob_image");
         KI.Destroy (Shown, Status);
         KB.Destroy (Run, Status);
      end;
      declare
         Big_Region : KR.Ks_Pixel_Region;
      begin
         KR.Whole_Image (9, 6, Big_Region, Status);
         KB.Execute (Image, Big_Region, Params, Ident, Results, Status);
         Check (Failed (AMV.Kernels.Failure_Bad_Parameter,
                        "Region: the pixel region does not lie in "
                        & "InputImage"), "a region larger than the image");
         KR.Destroy (Big_Region, Status);
      end;
      declare
         Measures : KB.Ks_Blob_Measure_Collection;
         Ops      : KB.Ks_Blob_Morphology_Collection;
      begin
         Measures.Count := 64;
         KB.Add_Measure (Measures, (others => <>), Status);
         Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter
                and then Measures.Count = 64, "add to a full collection");
         KB.Add_Morphology (Ops, 12, Status);
         Check (Status.Failure = AMV.Kernels.Failure_Bad_Parameter
                and then Ops.Count = 0, "add a morphology code beyond 11");
         KB.Add_Morphology (Ops, KB.Morphology_Open_Square, Status);
         Check (Status.Failure = 0 and then Ops.Count = 1
                and then Ops.Items (0) = 11, "add a morphology operation");
      end;
      KB.Check_Image (null, Status);
      Check (Failed (AMV.Kernels.Failure_Image_No_Pixels,
                     "InputImage has no pixels"), "check_image");
      KR.Destroy (Region, Status);
      KI.Destroy (Image, Status);
   end Test_Kernel;

   procedure Run_All is
   begin
      Test_Defaults;
      Test_Rectangle;
      Test_Circle_And_Polarity;
      Test_Holes;
      Test_Tree;
      Test_Cleanup;
      Test_Filters_And_Sorting;
      Test_Angle;
      Test_Region;
      Test_Connectivity_Modes;
      Test_Thresholds;
      Test_Fixture_Space;
      Test_Extrema;
      Test_Extrema_Filters;
      Test_Errors;
      Test_Boundary_And_ID_Image;
      Test_Images;
      Test_Morphology;
      Test_Soft_Thresholds;
      Test_Noise_And_Speed;
      Test_Kernel;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Blob;
