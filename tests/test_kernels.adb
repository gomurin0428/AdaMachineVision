--  Tests of the SPARK kernel layer: the status record and its C layout,
--  the ABI version, the conversion of a status into an exception, the
--  Misc kernel's handling of non-finite and extreme arguments (through the
--  Ada API and through the entry points themselves), the transform
--  kernel's argument checks, the coordinate space kernel's tree
--  invariant, limits and names, and the image kernel's handles, pixel
--  access, colour planes, coordinate space state and stream helpers, and
--  the image file kernel's decoding of malformed bytes, its encoders and
--  its stream helpers, the shape kernel's argument checks and bounds
--  (also through AMV.Shapes), its polygon handles and the value semantics
--  and streams of AMV.Shapes.Ks_Polygon, the pixel region kernel's
--  handles, rasterisation, memory and stream helpers (also through
--  AMV.Regions), the real image kernel's value bound, lean pixel access
--  and stream helpers, and the geometry kernel's argument and result
--  bounds and fits.

pragma Validity_Checks ("F");
--  This test builds NaNs and infinities on purpose.

with Ada.Exceptions;
with Ada.Streams.Storage.Unbounded;
with Ada.Strings.Unbounded;
with Ada.Unchecked_Conversion;
with Interfaces;
with System;

with AMV;              use AMV;
with AMV.Kernels;
with AMV.Kernels.Coordinate_Spaces;
with AMV.Kernels.Geometry;
with AMV.Kernels.Image_File;
with AMV.Kernels.Image_Math;
with AMV.Kernels.Images;
with AMV.Kernels.Misc;
with AMV.Kernels.Regions;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;
with AMV.Images;
with AMV.Misc;
with AMV.Regions;
with AMV.Shapes;
with AMV.Transforms;
with AMV.Test_Check_Mapping;
with AMV_Test_Support; use AMV_Test_Support;

procedure Test_Kernels is

   package K renames AMV.Kernels;
   use type K.Int32;

   Zero : constant Real := Real'Value ("0.0");
   --  Read at run time, so that Zero / Zero is not folded at compile time.

   --  The size of the status and the failure codes, as include/amv.h
   --  declares them, checked when this test is compiled.

   pragma Compile_Time_Error
     (K.Ks_Status'Max_Size_In_Storage_Elements /= 212,
      "Ks_Status must occupy 212 bytes, as ks_status in amv.h");
   pragma Compile_Time_Error
     (AMV.Kernels.Transforms.Ks_Transform_2D_Linear'
        Max_Size_In_Storage_Elements /= 48
      or else AMV.Kernels.Transforms.Ks_Decomposition'
                Max_Size_In_Storage_Elements /= 40,
      "transform records must match amv.h (48 and 40 bytes)");
   pragma Compile_Time_Error
     (AMV.Kernels.Coordinate_Spaces.Ks_Space_Name'
        Max_Size_In_Storage_Elements /= 260
      or else AMV.Kernels.Coordinate_Spaces.Ks_Coordinate_Space'
                Max_Size_In_Storage_Elements /= 312
      or else AMV.Kernels.Coordinate_Spaces.Ks_Coordinate_Space_Tree'
                Max_Size_In_Storage_Elements /= 19_976,
      "coordinate space records must match amv.h (260, 312, 19976 bytes)");
   pragma Compile_Time_Error
     (AMV.Kernels.Coordinate_Spaces.Max_Spaces /= 64
      or else AMV.Kernels.Coordinate_Spaces.Max_Name_Length /= 256,
      "tree limits must match KS_MAX_SPACES and KS_MAX_SPACE_NAME_LENGTH");
   pragma Compile_Time_Error
     (AMV.Kernels.Coordinate_Spaces.Add_Space_Duplicate_Is_Error /= 0
      or else AMV.Kernels.Coordinate_Spaces.Add_Space_Replace_Duplicate /= 1
      or else AMV.Kernels.Coordinate_Spaces.Add_Space_Ignore_Duplicate /= 2
      or else AMV.Kernels.Coordinate_Spaces.Pathname_None /= 0
      or else AMV.Kernels.Coordinate_Spaces.Pathname_Full /= 1
      or else AMV.Kernels.Coordinate_Spaces.Pathname_Partial /= 2,
      "tree codes must match KS_ADD_SPACE_* and KS_SPACE_TREE_PATHNAME_*");
   pragma Compile_Time_Error
     (AMV.Kernels.Geometry.Ks_Point_2D'Max_Size_In_Storage_Elements /= 16
      or else AMV.Kernels.Geometry.Ks_Line_2D'Max_Size_In_Storage_Elements
                /= 24
      or else AMV.Kernels.Geometry.Ks_Circle_2D'Max_Size_In_Storage_Elements
                /= 24,
      "geometry records must match amv.h (16, 24 and 24 bytes)");
   pragma Compile_Time_Error
     (AMV.Kernels.Images.Max_Pixels /= 2_147_483_647,
      "the image size limit must match KS_IMAGE_MAX_PIXELS");
   pragma Compile_Time_Error
     (AMV.Kernels.Image_File.Max_Length /= 2**56
      or else AMV.Kernels.Image_File.Max_Images /= 2_147_483_647
      or else AMV.Kernels.Image_File.Max_BMP_File_Size /= 4_294_967_295
      or else AMV.Kernels.Image_File.Mode_Closed /= 1
      or else AMV.Kernels.Image_File.Mode_Read /= 2
      or else AMV.Kernels.Image_File.Mode_Write /= 3
      or else AMV.Kernels.Image_File.Mode_Update /= 4
      or else AMV.Kernels.Image_File.Format_PGM /= 1
      or else AMV.Kernels.Image_File.Format_PPM /= 2
      or else AMV.Kernels.Image_File.Format_PNM /= 3
      or else AMV.Kernels.Image_File.Format_BMP /= 4
      or else AMV.Kernels.Image_File.Kind_PNM /= 1
      or else AMV.Kernels.Image_File.Kind_BMP /= 2
      or else AMV.Kernels.Image_File.Image_Type_Grey_8 /= 1
      or else AMV.Kernels.Image_File.Image_Type_Grey_16 /= 2
      or else AMV.Kernels.Image_File.Image_Type_Color /= 3
      or else AMV.Kernels.Image_File.Encoding_P5_8 /= 1
      or else AMV.Kernels.Image_File.Encoding_P5_16 /= 2
      or else AMV.Kernels.Image_File.Encoding_P6_From_Grey /= 3
      or else AMV.Kernels.Image_File.Encoding_P6_Color /= 4
      or else AMV.Kernels.Image_File.Encoding_BMP_8 /= 5
      or else AMV.Kernels.Image_File.Encoding_BMP_24 /= 6
      or else AMV.Kernels.Image_File.Operation_Item /= 1
      or else AMV.Kernels.Image_File.Operation_Append /= 2
      or else AMV.Kernels.Image_File.Operation_Run /= 3,
      "image file limits and codes must match the KS_IMAGE_FILE_* of amv.h");
   pragma Compile_Time_Error
     (AMV.Kernels.Shapes.Ks_Rectangle'Max_Size_In_Storage_Elements /= 32
      or else AMV.Kernels.Shapes.Ks_Rectangle_Affine'
                Max_Size_In_Storage_Elements /= 48
      or else AMV.Kernels.Shapes.Ks_Rectangle_Affine_Corners'
                Max_Size_In_Storage_Elements /= 64
      or else AMV.Kernels.Shapes.Ks_Circle'Max_Size_In_Storage_Elements /= 24
      or else AMV.Kernels.Shapes.Ks_Ellipse'Max_Size_In_Storage_Elements
                /= 40
      or else AMV.Kernels.Shapes.Ks_Circular_Annulus_Section'
                Max_Size_In_Storage_Elements /= 48
      or else AMV.Kernels.Shapes.Ks_Line'Max_Size_In_Storage_Elements /= 24
      or else AMV.Kernels.Shapes.Ks_Line_Segment'
                Max_Size_In_Storage_Elements /= 32
      or else AMV.Kernels.Shapes.Ks_Point_Marker'
                Max_Size_In_Storage_Elements /= 24
      or else AMV.Kernels.Shapes.Ks_Circular_Arc'
                Max_Size_In_Storage_Elements /= 40,
      "shape records must match amv.h (32, 48, 64, 24, 40, 48, 24, 32, 24 "
      & "and 40 bytes)");
   pragma Compile_Time_Error
     (AMV.Kernels.Shapes.Max_Vertices /= 1_048_576
      or else AMV.Kernels.Shapes.Append_Index /= -1
      or else AMV.Kernels.Shapes.Max_Value /= 1.0E150
      or else AMV.Kernels.Shapes.Max_Length /= 4.0E150
      or else AMV.Kernels.Shapes.Max_Area /= 2.0 ** 1022
      or else AMV.Kernels.Shapes.Max_Perimeter /= 2.0 ** 522
      or else AMV.Kernels.Shapes.Max_Slack /= 1.0E145
      or else AMV.Kernels.Shapes.Shape_Rectangle /= 1
      or else AMV.Kernels.Shapes.Shape_Rectangle_Affine /= 2
      or else AMV.Kernels.Shapes.Shape_Circle /= 3
      or else AMV.Kernels.Shapes.Shape_Ellipse /= 4
      or else AMV.Kernels.Shapes.Shape_Polygon /= 5
      or else AMV.Kernels.Shapes.Shape_Circular_Annulus_Section /= 6
      or else AMV.Kernels.Shapes.Shape_Line /= 7
      or else AMV.Kernels.Shapes.Shape_Line_Segment /= 8
      or else AMV.Kernels.Shapes.Shape_Point_Marker /= 9
      or else AMV.Kernels.Shapes.Shape_Circular_Arc /= 10,
      "shape limits and codes must match the KS_SHAPE_* and KS_POLYGON_* "
      & "of amv.h");
   --  The field offsets are fixed by the representation clauses of
   --  Ks_Status in AMV.Kernels and of the records of
   --  AMV.Kernels.Coordinate_Spaces.
   pragma Compile_Time_Error
     (K.Failure_None /= 0 or else K.Failure_Image_No_Pixels /= 1
      or else K.Failure_Image_Bad_Selected_Space_Name /= 2
      or else K.Failure_Operator_Not_Trained /= 3
      or else K.Failure_Transform_Singular /= 4
      or else K.Failure_Image_File /= 5
      or else K.Failure_Bad_Parameter /= 6
      or else K.Failure_Out_Of_Memory /= 7
      or else K.Failure_Other /= 8
      or else K.Failure_Index_Out_Of_Range /= 9 or else K.ABI_Version /= 3,
      "failure codes and ABI version must match amv.h");

   procedure Test_Status is
      Status : K.Ks_Status;
      Long   : constant String (1 .. 250) := [others => 'x'];
   begin
      Section ("kernel status");
      Check (K.Get_ABI_Version = 3, "ks_abi_version returns 3");

      K.Set_Failure (Status, K.Failure_Bad_Parameter, Long);
      Check (Status.Failure = K.Failure_Bad_Parameter, "failure code kept");
      Check (Status.Length = K.Max_Message_Length,
             "a long message is truncated to Max_Message_Length");
      Check (Status.Message (K.Max_Message_Length) = 'x'
             and then Status.Message (K.Max_Message_Length + 1)
                        = ASCII.NUL,
             "the message is NUL-terminated after truncation");
      K.Set_Failure (Status, K.Failure_Other, Long (51 .. 53));
      Check (Status.Length = 3 and then String (Status.Message (1 .. 3)) = "xxx"
             and then Status.Message (4) = ASCII.NUL,
             "a message slice with other bounds is copied from 1");
      K.Set_Success (Status);
      Check (Status.Failure = K.Failure_None and then Status.Length = 0
             and then Status.Message (1) = ASCII.NUL,
             "Set_Success clears the status");
   end Test_Status;

   procedure Test_Misc_Non_Finite is
      NaN     : constant Real := Zero / Zero;
      Plus    : constant Real := 1.0 / Zero;
      Minus   : constant Real := -1.0 / Zero;
      Values  : constant array (1 .. 3) of Real := [NaN, Plus, Minus];
      Names   : constant array (1 .. 3) of String (1 .. 4) :=
        ["NaN ", "+Inf", "-Inf"];

      type Operation is access function (X : Real) return Real;

      procedure Expect_Bad
        (Op : Operation; X : Real; Argument, What : String)
      is
         Ignored : Real;
      begin
         Ignored := Op (X);
         Fail (What & ": no exception");
      exception
         when E : Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E)
                     = Argument & " must be finite",
                   What & ": Ks_Bad_Parameter_Exception naming "
                   & Argument);
         when E : others =>
            Fail (What & ": raised " & Ada.Exceptions.Exception_Name (E));
      end Expect_Bad;

      function Hypot_X (X : Real) return Real is (AMV.Misc.Hypot (X, 1.0));
      function Hypot_Y (Y : Real) return Real is (AMV.Misc.Hypot (1.0, Y));
      function Diff_A (A : Real) return Real is
        (AMV.Misc.Angle_Difference (A, 1.0));
      function Diff_B (B : Real) return Real is
        (AMV.Misc.Angle_Difference (1.0, B));
   begin
      Section ("misc kernel: non-finite arguments");
      for I in Values'Range loop
         declare
            V : constant Real := Values (I);
            N : constant String := Names (I);
         begin
            Expect_Bad (AMV.Misc.Deg_To_Rad'Access, V, "Degrees",
                        "Deg_To_Rad (" & N & ")");
            Expect_Bad (AMV.Misc.Rad_To_Deg'Access, V, "Radians",
                        "Rad_To_Deg (" & N & ")");
            Expect_Bad (AMV.Misc.Norm_Angle'Access, V, "Radians",
                        "Norm_Angle (" & N & ")");
            Expect_Bad (AMV.Misc.Norm_Angle_Pi'Access, V, "Radians",
                        "Norm_Angle_Pi (" & N & ")");
            Expect_Bad (Hypot_X'Unrestricted_Access, V, "X",
                        "Hypot (" & N & ", 1)");
            Expect_Bad (Hypot_Y'Unrestricted_Access, V, "Y",
                        "Hypot (1, " & N & ")");
            Expect_Bad (Diff_A'Unrestricted_Access, V, "A",
                        "Angle_Difference (" & N & ", 1)");
            Expect_Bad (Diff_B'Unrestricted_Access, V, "B",
                        "Angle_Difference (1, " & N & ")");
         end;
      end loop;
   end Test_Misc_Non_Finite;

   procedure Test_Misc_Extremes is
      R : Real;
   begin
      Section ("misc kernel: extreme finite arguments");
      Check (AMV.Misc.Hypot (Real'Last, 0.0) = Real'Last,
             "Hypot (Real'Last, 0) = Real'Last");
      Check (AMV.Misc.Hypot (Real'Last, 1.0) = Real'Last,
             "Hypot (Real'Last, 1) = Real'Last");
      Check (abs (AMV.Misc.Hypot (3.0E300, 4.0E300) / 5.0E300 - 1.0)
               <= 1.0E-15,
             "Hypot (3E300, 4E300)");
      Check (abs (AMV.Misc.Hypot (3.0E-300, 4.0E-300) / 5.0E-300 - 1.0)
               <= 1.0E-15,
             "Hypot (3E-300, 4E-300)");
      declare
         --  Around 2**(-500), where the direct formula ends: a component
         --  below it is negligible only next to one that is 2**100 times
         --  larger. The triangles are exact in binary.
         U : constant Real := 2.0 ** (-503);
      begin
         Check (AMV.Misc.Hypot (6.0 * U, 8.0 * U) = 10.0 * U,
                "Hypot (0.75 * 2**(-500), 2**(-500))");
         Check (AMV.Misc.Hypot (8.0 * U, 6.0 * U) = 10.0 * U,
                "Hypot (2**(-500), 0.75 * 2**(-500))");
         Check (AMV.Misc.Hypot (5.0 * U, 12.0 * U) = 13.0 * U,
                "Hypot (0.625 * 2**(-500), 1.5 * 2**(-500))");
         Check (abs (AMV.Misc.Hypot (8.0 * U, 8.0 * U) / (8.0 * U)
                     - 1.4142135623730951) <= 1.0E-15,
                "Hypot (2**(-500), 2**(-500))");
         Check (abs (AMV.Misc.Hypot (2.0 ** (-401), 8.0 * U) / 2.0 ** (-401)
                     - 1.0) <= 1.0E-15,
                "Hypot (2**(-401), 2**(-500))");
         Check (AMV.Misc.Hypot (2.0 ** (-400), 8.0 * U) = 2.0 ** (-400),
                "Hypot (2**(-400), 2**(-500)): the smaller is negligible");
      end;
      begin
         R := AMV.Misc.Hypot (Real'Last, Real'Last);
         Fail ("Hypot (Real'Last, Real'Last): no exception, got"
               & R'Image);
      exception
         when Ks_Bad_Parameter_Exception =>
            Check (True, "Hypot (Real'Last, Real'Last) is rejected");
      end;
      R := AMV.Misc.Angle_Difference (Real'Last, -Real'Last);
      Check (R > -AMV.Misc.Pi and then R <= AMV.Misc.Pi,
             "Angle_Difference (Real'Last, -Real'Last) is in range");
      R := AMV.Misc.Angle_Difference (-Real'Last, 1.0E300);
      Check (R > -AMV.Misc.Pi and then R <= AMV.Misc.Pi,
             "Angle_Difference (-Real'Last, 1E300) is in range");
   end Test_Misc_Extremes;

   procedure Test_Entry_Points is
      Status : K.Ks_Status;
      R      : Real := 123.0;
   begin
      Section ("misc kernel: entry points called directly");
      Status.Failure := 42;
      Status.Length := 7;
      AMV.Kernels.Misc.Norm_Angle (4.0, R, Status);
      Check (Status.Failure = K.Failure_None and then Status.Length = 0,
             "a stale status is overwritten on success");
      Check (abs (R - (4.0 - 2.0 * AMV.Misc.Pi)) <= 1.0E-15,
             "ks_misc_norm_angle (4)");
      AMV.Kernels.Misc.Norm_Angle (Zero / Zero, R, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then String (Status.Message (1 .. Natural (Status.Length)))
                        = "Radians must be finite",
             "ks_misc_norm_angle (NaN) fails with Bad_Parameter");
      Check (R = 0.0, "the result of a failed call is 0.0");
   end Test_Entry_Points;

   procedure Test_Transforms_Kernel is
      package KT renames AMV.Kernels.Transforms;
      use type KT.Ks_Transform_2D_Linear;
      NaN    : constant Real := Zero / Zero;
      Status : K.Ks_Status;
      T      : KT.Ks_Transform_2D_Linear;
      R      : KT.Ks_Transform_2D_Linear;
      X, Y   : Real;
      Flag   : K.Int32;

      function Message return String is
        (String (Status.Message (1 .. Natural (Status.Length))));
   begin
      Section ("transforms kernel: arguments");
      T := (A => NaN, others => <>);
      KT.Map_Point (T, 1.0, 1.0, X, Y, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Transform must be finite and within "
                                & "+/-1.0E150",
             "a NaN entry is rejected");
      T := (others => <>);
      KT.Map_Point (T, 1.0, NaN, X, Y, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Y must be finite and within +/-1.0E150",
             "a NaN coordinate is rejected, naming Y");
      KT.Map_Point (T, 1.0E150, -1.0E150, X, Y, Status);
      Check (Status.Failure = K.Failure_None and then X = 1.0E150
             and then Y = -1.0E150, "coordinates at the bound map");
      T := (A => 2.0, others => <>);
      KT.Map_Point (T, 1.0E150, 0.0, X, Y, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "the mapped point would exceed the "
                                & "supported range",
             "a mapped point beyond the bound is rejected");
      KT.Set_Property (T, 8, 1.0, R, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "Set_Property rejects an unknown property code");
      KT.Identity (T, -1.0, Flag, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Flag = K.False_Value,
             "a negative tolerance is rejected");
      KT.Identity (T, 1.5, Flag, Status);
      Check (Status.Failure = K.Failure_None and then Flag = K.True_Value,
             "Identity within a large tolerance");

      Section ("transforms kernel: matrix elements");
      declare
         G : constant KT.Ks_Transform_2D_Linear :=
           (A => 2.0, B => 3.0, C => 5.0, D => 7.0, Translation_X => 11.0,
            Translation_Y => 13.0);
         V : Real := 99.0;
      begin
         KT.Get_Matrix_Element (G, 0, 0, V, Status);
         Check (Status.Failure = K.Failure_None and then V = 2.0,
                "ks_transform_2d_linear_get_matrix_element (0, 0) is a");
         KT.Get_Matrix_Element (G, 0, 1, V, Status);
         Check (Status.Failure = K.Failure_None and then V = 3.0,
                "get_matrix_element (0, 1) is b");
         KT.Get_Matrix_Element (G, 1, 0, V, Status);
         Check (Status.Failure = K.Failure_None and then V = 5.0,
                "get_matrix_element (1, 0) is c");
         KT.Get_Matrix_Element (G, 1, 1, V, Status);
         Check (Status.Failure = K.Failure_None and then V = 7.0,
                "get_matrix_element (1, 1) is d");
         KT.Get_Matrix_Element (G, 2, 0, V, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message = "Row must be 0 or 1" and then V = 0.0,
                "get_matrix_element rejects row 2");
         KT.Get_Matrix_Element (G, 0, -1, V, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message = "Column must be 0 or 1",
                "get_matrix_element rejects column -1");
         KT.Get_Matrix_Element (G, K.Int32'First, K.Int32'Last, V, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message = "Row must be 0 or 1",
                "get_matrix_element checks the row first");
         KT.Get_Matrix_Element ((A => NaN, others => <>), 5, 0, V, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message = "Transform must be finite and within "
                                   & "+/-1.0E150",
                "get_matrix_element checks the transform before the row");

         KT.Set_Matrix_Element (G, 0, 1, -4.5, R, Status);
         Check (Status.Failure = K.Failure_None
                and then R = (G with delta B => -4.5),
                "set_matrix_element (0, 1) replaces b only");
         KT.Set_Matrix_Element (G, 1, 0, 1.0E150, R, Status);
         Check (Status.Failure = K.Failure_None
                and then R = (G with delta C => 1.0E150),
                "set_matrix_element (1, 0) up to the bound");
         KT.Set_Matrix_Element (G, 1, 1, 1.0E151, R, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message = "Value must be finite and within "
                                   & "+/-1.0E150"
                and then R = (others => <>),
                "set_matrix_element rejects a value beyond the bound");
         KT.Set_Matrix_Element (G, 0, 0, NaN, R, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message = "Value must be finite and within "
                                   & "+/-1.0E150",
                "set_matrix_element rejects a NaN value");
         KT.Set_Matrix_Element (G, 0, 3, 1.0, R, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message = "Column must be 0 or 1",
                "set_matrix_element rejects column 3");
      end;

      Section ("transforms kernel: determinant, area and tests");
      declare
         Diag : constant KT.Ks_Transform_2D_Linear :=
           (A => 2.0, D => 3.0, Translation_X => 100.0, others => <>);
         Huge : constant KT.Ks_Transform_2D_Linear :=
           (A => 1.0E150, D => 1.0E150, others => <>);
         Flat : constant KT.Ks_Transform_2D_Linear :=
           (A => 1.0, B => 2.0, C => 2.0, D => 4.0, others => <>);
         V    : Real := 99.0;
      begin
         KT.Matrix_Determinant (Diag, V, Status);
         Check (Status.Failure = K.Failure_None and then V = 6.0,
                "ks_transform_2d_linear_matrix_determinant");
         KT.Map_Area (Diag, 1.5, V, Status);
         Check (Status.Failure = K.Failure_None and then V = 9.0,
                "ks_transform_2d_linear_map_area of diag (2, 3)");
         KT.Map_Area ((A => 0.0, B => 2.0, C => 3.0, D => 0.0,
                       others => <>), -2.0, V, Status);
         Check (Status.Failure = K.Failure_None and then V = -12.0,
                "map_area uses abs det and keeps the sign of the area");
         KT.Map_Area (Huge, 1.0E-200, V, Status);
         Check (Status.Failure = K.Failure_None
                and then abs (V / 1.0E100 - 1.0) <= 1.0E-15,
                "map_area with det 1.0E300 and a tiny area");
         KT.Map_Area (Huge, 2.0, V, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message = "the mapped area would exceed the "
                                   & "supported range"
                and then V = 0.0,
                "map_area beyond the bound (det 1.0E300, area 2)");
         KT.Map_Area (Huge, 1.0E-140, V, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter,
                "map_area beyond the bound (det 1.0E300, area 1.0E-140)");
         KT.Map_Area ((A => 1.0E75, D => 1.0E75, others => <>), 1.0E150, V,
                      Status);
         Check (Status.Failure = K.Failure_Bad_Parameter,
                "map_area beyond the bound (det 1.0E150, area 1.0E150)");
         KT.Map_Area ((A => 1.0E70, D => 1.0E70, others => <>), 1.0E10, V,
                      Status);
         Check (Status.Failure = K.Failure_None
                and then abs (V / 1.0E150 - 1.0) <= 1.0E-15,
                "map_area at the bound (det 1.0E140, area 1.0E10)");
         KT.Map_Area (Diag, NaN, V, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message = "Area must be finite and within "
                                   & "+/-1.0E150",
                "map_area rejects a NaN area, naming Area");
         KT.Map_Area (Diag, 1.0E151, V, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message = "Area must be finite and within "
                                   & "+/-1.0E150",
                "map_area rejects an area beyond the bound");

         KT.Singular (Flat, 0.0, Flag, Status);
         Check (Status.Failure = K.Failure_None and then Flag = K.True_Value,
                "ks_transform_2d_linear_singular of a rank one matrix");
         KT.Singular (Diag, 5.9, Flag, Status);
         Check (Status.Failure = K.Failure_None and then Flag = K.False_Value,
                "singular: det 6 > tolerance 5.9");
         KT.Singular (Diag, 6.0, Flag, Status);
         Check (Status.Failure = K.Failure_None and then Flag = K.True_Value,
                "singular: det 6 <= tolerance 6 (absolute)");
         KT.Singular (Diag, -1.0, Flag, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Flag = K.False_Value,
                "singular rejects a negative tolerance");

         KT.Matrix_Identity ((Translation_X => 5.0, others => <>), 0.0,
                             Flag, Status);
         Check (Status.Failure = K.Failure_None and then Flag = K.True_Value,
                "ks_transform_2d_linear_matrix_identity ignores the "
                & "translation");
         KT.Identity ((Translation_X => 5.0, others => <>), 0.0, Flag,
                      Status);
         Check (Status.Failure = K.Failure_None and then Flag = K.False_Value,
                "ks_transform_2d_linear_identity looks at the translation");
         KT.Matrix_Identity ((B => 1.0E-3, others => <>), 1.0E-4, Flag,
                             Status);
         Check (Status.Failure = K.Failure_None and then Flag = K.False_Value,
                "matrix_identity: b outside the tolerance");
         KT.Matrix_Identity ((B => NaN, others => <>), 1.0, Flag, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Flag = K.False_Value,
                "matrix_identity rejects a NaN entry");
         KT.Matrix_Identity (Diag, NaN, Flag, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter,
                "matrix_identity rejects a NaN tolerance");
      end;

      Section ("transforms kernel: through the Ada API");
      declare
         procedure Map_NaN is
            MX, MY : Real;
         begin
            AMV.Transforms.Identity.Map_Point (NaN, 0.0, MX, MY);
         end Map_NaN;
         procedure Check_Map_NaN is new Check_Raises_Exactly
           (Map_NaN, Ks_Bad_Parameter_Exception'Identity);
         procedure Set_NaN_Rotation is
            Turned : AMV.Transforms.Ks_Transform_2D_Linear;
         begin
            Turned.Set_Rotation (NaN);
         end Set_NaN_Rotation;
         procedure Check_Set_NaN is new Check_Raises_Exactly
           (Set_NaN_Rotation, Ks_Bad_Parameter_Exception'Identity);
      begin
         Check_Map_NaN ("Map_Point (NaN) raises Ks_Bad_Parameter_Exception");
         Check_Set_NaN ("Set_Rotation (NaN) raises "
                        & "Ks_Bad_Parameter_Exception");
      end;
   end Test_Transforms_Kernel;


   procedure Test_Coordinate_Spaces_Kernel is
      package KC renames AMV.Kernels.Coordinate_Spaces;
      package KT renames AMV.Kernels.Transforms;
      use type KC.Ks_Coordinate_Space_Tree;
      use type KT.Ks_Transform_2D_Linear;

      NaN    : constant Real := Zero / Zero;
      Status : K.Ks_Status;
      Tree   : KC.Ks_Coordinate_Space_Tree;
      Flag   : K.Int32;
      Count  : K.Int32;
      Name   : KC.Ks_Space_Name;
      T      : KT.Ks_Transform_2D_Linear;
      Shift  : constant KT.Ks_Transform_2D_Linear :=
        (Translation_X => 5.0, others => <>);
      Double : constant KT.Ks_Transform_2D_Linear :=
        (A => 2.0, D => 2.0, others => <>);

      Replace : constant K.Int32 := KC.Add_Space_Replace_Duplicate;
      Full    : constant K.Int32 := KC.Pathname_Full;
      None    : constant K.Int32 := KC.Pathname_None;
      Partial : constant K.Int32 := KC.Pathname_Partial;

      function N (Text : String) return KC.Ks_Space_Name
        renames KC.To_Space_Name;

      function Message return String is
        (String (Status.Message (1 .. Natural (Status.Length))));

      function Succeeded return Boolean is
        (Status.Failure = K.Failure_None);

      function Text_Of (Space : K.Int32) return String is
        (KC.To_String (Tree.Spaces (Space).Name));

      type Tree_Bytes is array (1 .. 19_976) of Interfaces.Unsigned_8;

      function Bytes is new Ada.Unchecked_Conversion
        (KC.Ks_Coordinate_Space_Tree, Tree_Bytes);

      function Same_Bits (Left, Right : KC.Ks_Coordinate_Space_Tree)
         return Boolean is (Bytes (Left) = Bytes (Right));
      --  Unchanged, also for trees that hold a NaN.

      procedure Expect_Invalid (Bad : KC.Ks_Coordinate_Space_Tree;
                                What : String)
      is
         Copy : KC.Ks_Coordinate_Space_Tree := Bad;

         procedure Expect_Failure (Operation : String) is
         begin
            Check (Status.Failure = K.Failure_Bad_Parameter
                   and then Message = "Tree is not a valid coordinate space "
                                      & "tree",
                   What & ": " & Operation & " fails with Bad_Parameter");
         end Expect_Failure;

         procedure Expect_Unchanged (Operation : String) is
         begin
            Expect_Failure (Operation);
            Check (Same_Bits (Copy, Bad),
                   What & ": " & Operation & " changes nothing");
         end Expect_Unchanged;
      begin
         Check (not KC.Valid_Tree (Bad), What & ": Valid_Tree is False");
         KC.Space_Count (Bad, Count, Status);
         Expect_Failure ("Space_Count");
         Check (Count = 0, What & ": Space_Count gives 0");
         KC.Space_Exists (Bad, N ("@"), Flag, Status);
         Expect_Failure ("Space_Exists");
         Check (Flag = K.False_Value, What & ": Space_Exists gives False");
         KC.Get_Transform (Bad, N ("@"), N ("@"), T, Status);
         Expect_Failure ("Get_Transform");
         KC.Root_Name (Bad, Name, Status);
         Expect_Failure ("Root_Name");
         Check (Name.Length = 0, What & ": Root_Name gives the empty name");
         KC.Parent_Name (Bad, N ("@\A"), Full, Name, Status);
         Expect_Failure ("Parent_Name");
         KC.Child_Names_Count (Bad, N ("@"), Count, Status);
         Expect_Failure ("Child_Names_Count");
         KC.Child_Name (Bad, N ("@"), Full, 0, Name, Status);
         Expect_Failure ("Child_Name");
         KC.All_Child_Names_Count (Bad, N ("@"), K.True_Value, Count, Status);
         Expect_Failure ("All_Child_Names_Count");
         KC.All_Child_Name (Bad, N ("@"), Full, K.True_Value, 0, Name,
                            Status);
         Expect_Failure ("All_Child_Name");
         KC.Verify_Name (Bad, N ("@"), Full, Flag, Name, Status);
         Expect_Failure ("Verify_Name");
         Check (Flag = K.False_Value and then Name.Length = 0,
                What & ": Verify_Name gives False and the empty name");
         KC.Parent_From_Child_Transform (Bad, N ("@"), T, Status);
         Expect_Failure ("Parent_From_Child_Transform");
         KC.Add_Space (Copy, N ("@"), N ("New"), Shift, Replace, Status);
         Expect_Unchanged ("Add_Space");
         KC.Change_Transform (Copy, N ("@\A"), Shift, Status);
         Expect_Unchanged ("Change_Transform");
         KC.Delete_Subtree (Copy, N ("@\A"), Status);
         Expect_Unchanged ("Delete_Subtree");
         KC.Clear (Copy, Status);
         Expect_Unchanged ("Clear");
      end Expect_Invalid;

      Valid : KC.Ks_Coordinate_Space_Tree;
      Bad   : KC.Ks_Coordinate_Space_Tree;
   begin
      Section ("coordinate spaces kernel: operations keep the tree valid");
      Tree.Count := 0;
      KC.Init (Tree, Status);
      Check (Succeeded and then KC.Valid_Tree (Tree) and then Tree.Count = 1
             and then Text_Of (0) = "@",
             "Init gives the tree with only the root");
      Check (KC.Valid_Tree (KC.Ks_Coordinate_Space_Tree'(others => <>)),
             "the default record is the root-only tree");
      KC.Add_Space (Tree, N ("@"), N ("A"), Shift, Replace, Status);
      KC.Add_Space (Tree, N ("@\A"), N ("B"), Double, Replace, Status);
      KC.Add_Space (Tree, N ("@"), N ("A B"), Shift, Replace, Status);
      Check (Succeeded and then KC.Valid_Tree (Tree)
             and then Tree.Count = 4,
             "three spaces added");
      Check (Text_Of (1) = "@\A" and then Text_Of (2) = "@\A B"
             and then Text_Of (3) = "@\A\B",
             "entries sorted by name ("" "" before ""\"")");
      Check (Tree.Spaces (1).Parent = 0 and then Tree.Spaces (2).Parent = 0
             and then Tree.Spaces (3).Parent = 1,
             "parent indices follow the insertion");
      Check (Tree.Spaces (3).Parent_From_Child = Double,
             "the transform is stored as given");
      --  Root from B: (x, y) -> (2 x + 5, 2 y).
      KC.Get_Transform (Tree, N ("@"), N ("@\A\B"), T, Status);
      Check (Succeeded and then T.A = 2.0 and then T.D = 2.0
             and then T.Translation_X = 5.0,
             "Get_Transform composes up the path");
      KC.Get_Transform (Tree, N ("@\A\B"), N ("@"), T, Status);
      Check (Succeeded and then T.A = 0.5 and then T.D = 0.5
             and then T.Translation_X = -2.5,
             "Get_Transform inverts the path to the To space");
      KC.Get_Transform (Tree, N ("@\A B"), N ("@\A\B"), T, Status);
      Check (Succeeded and then T.A = 2.0 and then T.Translation_X = 0.0,
             "Get_Transform between branches");
      KC.Space_Name (Tree, 2, Name, Status);
      Check (Succeeded and then KC.To_String (Name) = "@\A B"
             and then Name.Text (6) = ASCII.NUL,
             "Space_Name gives the name followed by NUL characters");
      KC.Parent_Name (Tree, N ("@\A\B"), Full, Name, Status);
      Check (Succeeded and then KC.To_String (Name) = "@\A",
             "Parent_Name");
      KC.Parent_Name (Tree, N ("@\A\B"), None, Name, Status);
      Check (Succeeded and then KC.To_String (Name) = "A"
             and then Name.Text (2) = ASCII.NUL,
             "Parent_Name, None");
      KC.Parent_Name (Tree, N ("@"), Partial, Name, Status);
      Check (Succeeded and then Name.Length = 0,
             "the root's parent name is empty");
      KC.Change_Transform (Tree, N ("@\A B"), Double, Status);
      Check (Succeeded and then KC.Valid_Tree (Tree)
             and then Tree.Spaces (2).Parent_From_Child = Double,
             "Change_Transform");
      KC.Add_Space (Tree, N ("@"), N ("A"), Double, Replace, Status);
      Check (Succeeded and then Tree.Count = 4
             and then Tree.Spaces (1).Parent_From_Child = Double
             and then Tree.Spaces (3).Parent = 1,
             "Replace_Duplicate replaces only the transform");
      Valid := Tree;
      KC.Add_Space (Tree, N ("@"), N ("A"), Shift,
                    KC.Add_Space_Ignore_Duplicate, Status);
      Check (Succeeded and then Tree = Valid,
             "Ignore_Duplicate succeeds and changes nothing");
      KC.Add_Space (Tree, N ("@"), N ("A"), Shift,
                    KC.Add_Space_Duplicate_Is_Error, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Add_Space: the space ""@\A"" already "
                                & "exists"
             and then Tree = Valid,
             "Duplicate_Is_Error fails and changes nothing");
      KC.Delete_Subtree (Tree, N ("@\A"), Status);
      Check (Succeeded and then KC.Valid_Tree (Tree)
             and then Tree.Count = 2 and then Text_Of (1) = "@\A B"
             and then Tree.Spaces (1).Parent = 0,
             "Delete_Subtree takes the subtree and renumbers the rest");
      KC.Clear (Tree, Status);
      Check (Succeeded and then KC.Valid_Tree (Tree) and then Tree.Count = 1,
             "Clear");

      Section ("coordinate spaces kernel: children and names");
      Tree := Valid;
      KC.Root_Name (Tree, Name, Status);
      Check (Succeeded and then KC.To_String (Name) = "@"
             and then Name.Text (2) = ASCII.NUL, "Root_Name");
      KC.Child_Names_Count (Tree, N ("@"), Count, Status);
      Check (Succeeded and then Count = 2, "Child_Names_Count of the root");
      KC.Child_Name (Tree, N ("@"), Full, 1, Name, Status);
      Check (Succeeded and then KC.To_String (Name) = "@\A B",
             "Child_Name in lexical order");
      KC.Child_Name (Tree, N ("@"), Partial, 0, Name, Status);
      Check (Succeeded and then KC.To_String (Name) = "A"
             and then Name.Text (2) = ASCII.NUL,
             "Child_Name, Partial, followed by NUL characters");
      KC.Child_Name (Tree, N ("@"), Full, 2, Name, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range
             and then Message = "Child_Names: index 2 is not in 0 .. 1"
             and then Name.Length = 0,
             "Child_Name beyond the count");
      KC.Child_Name (Tree, N ("@\A\B"), Full, 0, Name, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range
             and then Message = "Child_Names: index 0 is out of range "
                                & "(there are no names)",
             "Child_Name of a leaf");
      KC.Child_Name (Tree, N ("@\Nope"), Full, 0, Name, Status);
      Check (Status.Failure = K.Failure_Image_Bad_Selected_Space_Name
             and then Message = "Child_Names: no space named ""@\Nope""",
             "Child_Name of an unknown space");
      KC.All_Child_Names_Count (Tree, N ("@"), K.True_Value, Count, Status);
      Check (Succeeded and then Count = 3, "All_Child_Names_Count");
      KC.All_Child_Names_Count (Tree, N ("@\A"), K.False_Value, Count,
                                Status);
      Check (Succeeded and then Count = 2,
             "All_Child_Names_Count with the space itself");
      KC.All_Child_Name (Tree, N ("@"), Partial, K.True_Value, 2, Name,
                         Status);
      Check (Succeeded and then KC.To_String (Name) = "A\B",
             "All_Child_Name, Partial");
      KC.All_Child_Name (Tree, N ("@\A"), Partial, K.False_Value, 0, Name,
                         Status);
      Check (Succeeded and then KC.To_String (Name) = "@\A",
             "All_Child_Name: the space itself first, by its full name");
      KC.All_Child_Name (Tree, N ("@\A"), None, K.False_Value, 1, Name,
                         Status);
      Check (Succeeded and then KC.To_String (Name) = "B",
             "All_Child_Name, None");
      KC.All_Child_Name (Tree, N ("@\A"), Full, K.True_Value, 1, Name,
                         Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range
             and then Message = "All_Child_Names: index 1 is not in 0 .. 0",
             "All_Child_Name beyond the count");
      KC.Verify_Name (Tree, N ("@\A\B"), None, Flag, Name, Status);
      Check (Succeeded and then Flag = K.True_Value
             and then KC.To_String (Name) = "B",
             "Verify_Name, None");
      KC.Verify_Name (Tree, N ("@\A\B"), Partial, Flag, Name, Status);
      Check (Succeeded and then Flag = K.True_Value
             and then KC.To_String (Name) = "@\A\B",
             "Verify_Name, Partial gives the full name");
      KC.Verify_Name (Tree, N ("@\B"), Full, Flag, Name, Status);
      Check (Succeeded and then Flag = K.False_Value
             and then Name.Length = 0,
             "Verify_Name of an unknown name");
      KC.Parent_From_Child_Transform (Tree, N ("@\A\B"), T, Status);
      Check (Succeeded and then T = Double,
             "Parent_From_Child_Transform gives the transform as given");

      Section ("coordinate spaces kernel: codes");
      KC.Add_Space (Tree, N ("@"), N ("C"), Shift, 3, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Add_Space: Duplicate_Handling must be 0 "
                                & "(Duplicate_Is_Error), 1 "
                                & "(Replace_Duplicate) or 2 "
                                & "(Ignore_Duplicate)"
             and then Tree = Valid,
             "Add_Space rejects the code 3");
      KC.Add_Space (Tree, N ("@"), N ("A"), Shift, -1, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Tree = Valid,
             "Add_Space rejects the code -1, even for a duplicate");
      KC.Parent_Name (Tree, N ("@\A"), 3, Name, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Parent_Name: Pathname_Format must be 0 "
                                & "(None), 1 (Full) or 2 (Partial)"
             and then Name.Length = 0,
             "Parent_Name rejects the format 3");
      KC.Child_Name (Tree, N ("@"), -1, 0, Name, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "Child_Name rejects the format -1");
      KC.All_Child_Name (Tree, N ("@"), 7, K.True_Value, 0, Name, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "All_Child_Name rejects the format 7");
      KC.All_Child_Names_Count (Tree, N ("@"), 2, Count, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "All_Child_Names: Children_Only must be 0 "
                                & "or 1"
             and then Count = 0,
             "All_Child_Names_Count rejects Children_Only 2");
      KC.All_Child_Name (Tree, N ("@"), Full, -1, 0, Name, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "All_Child_Name rejects Children_Only -1");
      KC.Verify_Name (Tree, N ("@"), 3, Flag, Name, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Flag = K.False_Value and then Name.Length = 0,
             "Verify_Name rejects the format 3");

      Section ("coordinate spaces kernel: invalid trees");
      Bad := Valid;
      Bad.Count := 0;
      Expect_Invalid (Bad, "Count 0");
      Bad.Count := 65;
      Expect_Invalid (Bad, "Count 65");
      Bad.Count := -3;
      Expect_Invalid (Bad, "Count -3");
      Bad := Valid;
      Bad.Spaces (0).Name := N ("#");
      Expect_Invalid (Bad, "a root not named @");
      Bad := Valid;
      Bad.Spaces (0).Parent := 0;
      Expect_Invalid (Bad, "a root with a parent");
      Bad := Valid;
      Bad.Spaces (0).Parent_From_Child.A := 2.0;
      Expect_Invalid (Bad, "a root transform other than the identity");
      Bad := Valid;
      Bad.Spaces (1).Parent := 1;
      Expect_Invalid (Bad, "a space that is its own parent");
      Bad := Valid;
      Bad.Spaces (1).Parent := 3;
      Expect_Invalid (Bad, "a parent after the space");
      Bad := Valid;
      Bad.Spaces (2).Parent := -1;
      Expect_Invalid (Bad, "a negative parent index");
      Bad := Valid;
      Bad.Spaces (2) := Valid.Spaces (3);
      Bad.Spaces (3) := Valid.Spaces (2);
      Expect_Invalid (Bad, "names out of order");
      Bad := Valid;
      Bad.Spaces (2).Name := Bad.Spaces (1).Name;
      Expect_Invalid (Bad, "a repeated name");
      Bad := Valid;
      Bad.Spaces (3).Name := N ("@\X\B");
      Expect_Invalid (Bad, "a name that does not extend its parent's");
      Bad := Valid;
      Bad.Spaces (1).Name := N ("@\");
      Expect_Invalid (Bad, "an empty component");
      Bad := Valid;
      Bad.Spaces (2).Name := N ("@\.");
      Bad.Spaces (2).Parent := 0;
      Expect_Invalid (Bad, "the component "".""");
      Bad := Valid;
      Bad.Spaces (1).Name.Length := 300;
      Expect_Invalid (Bad, "a name length of 300");
      Bad := Valid;
      Bad.Spaces (1).Name.Length := -1;
      Expect_Invalid (Bad, "a negative name length");
      Bad := Valid;
      Bad.Spaces (1).Parent_From_Child.D := NaN;
      Expect_Invalid (Bad, "a NaN transform entry");
      Bad := Valid;
      Bad.Spaces (1).Parent_From_Child.A := 1.0E200;
      Expect_Invalid (Bad, "a transform entry beyond 1.0E150");
      Check (KC.Valid_Tree (Valid), "the original tree is still valid");

      Section ("coordinate spaces kernel: limits");
      KC.Init (Tree, Status);
      for I in 1 .. 63 loop
         declare
            Digits_Of : constant String := Integer'Image (100 + I);
         begin
            KC.Add_Space (Tree, N ("@"), N ("S" & Digits_Of (2 .. 4)),
                          Shift, Replace, Status);
         end;
      end loop;
      Check (Succeeded and then KC.Valid_Tree (Tree)
             and then Tree.Count = 64, "63 spaces under the root fill it");
      KC.Child_Names_Count (Tree, N ("@"), Count, Status);
      Check (Succeeded and then Count = 63, "the root of a full tree has 63 "
             & "children");
      Valid := Tree;
      KC.Add_Space (Tree, N ("@"), N ("T"), Shift, Replace, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Add_Space: the tree already holds the "
                                & "maximum of 64 spaces"
             and then Tree = Valid,
             "a 65th space is rejected and the tree is unchanged");
      KC.Add_Space (Tree, N ("@"), N ("S150"), Double, Replace, Status);
      Check (Succeeded and then KC.Valid_Tree (Tree)
             and then Tree.Count = 64,
             "an existing space of a full tree can be replaced");
      KC.Init (Tree, Status);
      KC.Add_Space (Tree, N ("@"), N ([1 .. 254 => 'w']), Shift, Replace,
                    Status);
      Check (Succeeded and then KC.Valid_Tree (Tree)
             and then Tree.Spaces (1).Name.Length = 256,
             "a 256-character name");
      KC.Child_Name (Tree, N ("@"), None, 0, Name, Status);
      Check (Succeeded and then Name.Length = 254,
             "the last component of a 256-character name");
      Valid := Tree;
      KC.Add_Space (Tree, N ("@"), N ([1 .. 255 => 'v']), Shift, Replace,
                    Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Add_Space: the space name would be longer "
                                & "than 256 characters"
             and then Tree = Valid,
             "a 257-character name is rejected");
      KC.Add_Space (Tree, N ("@"), N ([1 .. 400 => 'v']), Shift, Replace,
                    Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Tree = Valid,
             "a 400-character component is rejected");
      KC.Add_Space (Tree, N ("@"), N ([1 .. 300 => '\']), Shift, Replace,
                    Status);
      Check (Status.Failure = K.Failure_Image_Bad_Selected_Space_Name
             and then Tree = Valid,
             "a long component with a separator is an invalid component");
      KC.Space_Exists (Tree, N ([1 .. 300 => 'w']), Flag, Status);
      Check (Succeeded and then Flag = K.False_Value,
             "Space_Exists of a 300-character name");
      KC.Verify_Name (Tree, N ([1 .. 300 => 'w']), Full, Flag, Name, Status);
      Check (Succeeded and then Flag = K.False_Value
             and then Name.Length = 0,
             "Verify_Name of a 300-character name");
      Name := N ("@");
      Name.Length := -3;
      KC.Space_Exists (Tree, Name, Flag, Status);
      Check (Succeeded and then Flag = K.False_Value,
             "Space_Exists of a negative length");
      KC.Get_Transform (Tree, Name, N ("@"), T, Status);
      Check (Status.Failure = K.Failure_Image_Bad_Selected_Space_Name
             and then Message = "Get_Transform: malformed space name """"",
             "a negative length is a malformed name");
      KC.Space_Name (Tree, 2, Name, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range
             and then Message = "Space_Name: index 2 is not in 0 .. 1"
             and then Name.Length = 0,
             "Space_Name beyond the count");
      KC.Space_Name (Tree, -1, Name, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "Space_Name of a negative index");

      Section ("coordinate spaces kernel: names and messages");
      declare
         High : constant String (Integer'Last - 3 .. Integer'Last) := "@\A1";
      begin
         Name := N (High);
         Check (Name.Length = 4 and then KC.Fits (Name)
                and then KC.To_String (Name) = "@\A1"
                and then KC.To_String (Name)'First = 1,
                "To_Space_Name of a string ending at Integer'Last");
      end;
      Name := N ([1 .. 300 => 'x']);
      Check (Name.Length = 300 and then not KC.Fits (Name)
             and then Name.Text (256) = 'x',
             "To_Space_Name of 300 characters keeps 256 and the length");
      KC.Init (Tree, Status);
      KC.Add_Space (Tree, N ("@"), N ("A"), Shift, Replace, Status);
      KC.Get_Transform (Tree, N ("@\Nope"), N ("@"), T, Status);
      Check (Status.Failure = K.Failure_Image_Bad_Selected_Space_Name
             and then Message = "Get_Transform: no space named ""@\Nope""",
             "an unknown name");
      KC.Parent_From_Child_Transform (Tree, N ("@\\A"), T, Status);
      Check (Status.Failure = K.Failure_Image_Bad_Selected_Space_Name
             and then Message = "Parent_From_Child_Transform: malformed "
                                & "space name ""@\\A""",
             "a malformed name");
      KC.Add_Space (Tree, N ("@"), N ("#"), Shift, Replace, Status);
      Check (Status.Failure = K.Failure_Image_Bad_Selected_Space_Name
             and then Message = "Add_Space: invalid space name component "
                                & """#""",
             "an invalid component");
      KC.Add_Space (Tree, N ("@"), N ("C"), (A => NaN, others => <>),
                    Replace, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Add_Space: the Parent_From_New transform "
                                & "must be finite and within +/-1.0E150",
             "a NaN transform is rejected");
      KC.Add_Space (Tree, N ("@"), N ("C"), (A => 0.0, D => 0.0, others => <>),
                    Replace, Status);
      Check (Status.Failure = K.Failure_Transform_Singular
             and then Message = "Add_Space: the Parent_From_New transform "
                                & "is singular",
             "a singular transform");
      KC.Change_Transform (Tree, N ("@\A"), (A => 0.0, D => 0.0,
                                             others => <>), Status);
      Check (Status.Failure = K.Failure_Transform_Singular
             and then Message = "Change_Transform: the "
                                & "New_Parent_From_Child transform is "
                                & "singular",
             "a singular transform for Change_Transform");
      KC.Delete_Subtree (Tree, N ("@"), Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Delete_Subtree: the root space ""@"" "
                                & "cannot be deleted",
             "the root cannot be deleted");
      KC.Change_Transform (Tree, N ("@"), Shift, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message = "Change_Transform: the root space ""@"" "
                                & "has no parent",
             "the root transform cannot be changed");
      KC.Parent_From_Child_Transform (Tree, N ("@"), T, Status);
      Check (Succeeded and then T = KT.Ks_Transform_2D_Linear'(others => <>),
             "the root transform is the identity");
      KC.Space_Count (Tree, Count, Status);
      Check (Succeeded and then Count = 2, "Space_Count");
      --  A To side whose transform to the root cannot be inverted.
      KC.Add_Space (Tree, N ("@\A"), N ("S1"),
                    (A => 1.0E-80, D => 1.0E-80, others => <>), Replace,
                    Status);
      KC.Add_Space (Tree, N ("@\A\S1"), N ("S2"),
                    (A => 1.0E-80, D => 1.0E-80, others => <>), Replace,
                    Status);
      KC.Get_Transform (Tree, N ("@\A\S1\S2"), N ("@"), T, Status);
      Check (Status.Failure = K.Failure_Transform_Singular
             and then Message = "Get_Transform: the transform from "
                                & """@\A\S1\S2"" to the root is not "
                                & "invertible"
             and then T = KT.Ks_Transform_2D_Linear'(others => <>),
             "a To side that cannot be inverted");

      Section ("coordinate spaces kernel: stream reading");
      KC.Check_Read_Header (KC.Stream_Code, 1, Status);
      Check (Succeeded, "a header for the root-only tree");
      KC.Check_Read_Header (KC.Stream_Code + 1, 1, Status);
      Check (Status.Failure = K.Failure_Image_File, "a wrong format code");
      KC.Check_Read_Header (KC.Stream_Code, 0, Status);
      Check (Status.Failure = K.Failure_Image_File, "a count of 0");
      KC.Check_Read_Header (KC.Stream_Code, 65, Status);
      Check (Status.Failure = K.Failure_Image_File, "a count of 65");
      KC.Init (Tree, Status);
      KC.Add_Read_Space (Tree, N ("@\A"), Shift, Status);
      KC.Add_Read_Space (Tree, N ("@\A\B"), Double, Status);
      Check (Succeeded and then KC.Valid_Tree (Tree)
             and then Tree.Count = 3
             and then Tree.Spaces (2).Parent_From_Child = Double,
             "spaces read in order");
      Valid := Tree;
      KC.Add_Read_Space (Tree, N ("@\A"), Shift, Status);
      Check (Status.Failure = K.Failure_Image_File and then Tree = Valid,
             "a repeated space");
      KC.Add_Read_Space (Tree, N ("@\X\Y"), Shift, Status);
      Check (Status.Failure = K.Failure_Image_File and then Tree = Valid,
             "a space before its parent");
      KC.Add_Read_Space (Tree, N ("@"), Shift, Status);
      Check (Status.Failure = K.Failure_Image_File and then Tree = Valid,
             "the root");
      KC.Add_Read_Space (Tree, N ("@\A\"), Shift, Status);
      Check (Status.Failure = K.Failure_Image_File and then Tree = Valid,
             "a malformed name");
      KC.Add_Read_Space (Tree, N ("@\C"), (A => 1.0E200, others => <>),
                         Status);
      Check (Status.Failure = K.Failure_Image_File and then Tree = Valid,
             "a transform beyond the bound");
   end Test_Coordinate_Spaces_Kernel;

   procedure Test_Images_Kernel is
      package KI renames AMV.Kernels.Images;
      package KC renames AMV.Kernels.Coordinate_Spaces;
      package KT renames AMV.Kernels.Transforms;
      use type KI.Ks_Image_8_Grey;
      use type KI.Ks_Image_16_Grey;
      use type KI.Grey_8;
      use type KI.Grey_16;
      use type KI.Grey_8_Row;
      use type KI.Grey_8_Matrix;
      use type KI.Transform_Bits;
      use type KI.Pixel_Position;
      use type KT.Ks_Transform_2D_Linear;

      NaN    : constant Real := Zero / Zero;
      Status : K.Ks_Status;
      Image  : KI.Ks_Image_8_Grey;
      Other  : KI.Ks_Image_8_Grey;
      Deep   : KI.Ks_Image_16_Grey;
      Value  : KI.Grey_8;
      Value_16 : KI.Grey_16;
      Size   : K.Int32;
      Done   : Boolean;

      No_Image : constant KI.Ks_Image_8_Grey := null;
      --  A typed null: the entry points are overloaded for 8 and 16 bits.

      function Message return String is
        (String (Status.Message (1 .. Natural (Status.Length))));

      function Succeeded return Boolean is
        (Status.Failure = K.Failure_None);

      function Failed (Code : K.Int32; Text : String) return Boolean is
        (Status.Failure = Code and then Message = Text);

      function N (Text : String) return KC.Ks_Space_Name
        renames KC.To_Space_Name;

      function Pixel (Of_Image : KI.Ks_Image_8_Grey; X, Y : K.Int32)
         return KI.Grey_8
      is
         Result : KI.Grey_8;
         Inner  : K.Ks_Status;
      begin
         KI.Get_Pixel (Of_Image, X, Y, Result, Inner);
         return Result;
      end Pixel;
   begin
      Section ("images kernel: handles and pixels");
      KI.Create (4, 3, 7, Image, Status);
      Check (Succeeded and then Image /= null and then KI.Valid_Image (Image)
             and then Image.Width = 4 and then Image.Height = 3,
             "Create gives a valid 4 x 3 handle");
      Check (Image.Pixels'First (1) = 0 and then Image.Pixels'Last (1) = 2
             and then Image.Pixels'First (2) = 0
             and then Image.Pixels'Last (2) = 3,
             "the pixels are indexed (Y, X) from 0");
      Check ((for all Y in 0 .. 2 =>
                (for all X in 0 .. 3 => Image.Pixels (Y, X) = 7)),
             "Create fills with Value");
      KI.Width (Image, Size, Status);
      Check (Succeeded and then Size = 4, "Width");
      KI.Height (Image, Size, Status);
      Check (Succeeded and then Size = 3, "Height");
      KI.Width (No_Image, Size, Status);
      Check (Succeeded and then Size = 0, "Width of null is 0");
      KI.Set_Pixel (Image, 3, 2, 99, Status);
      Check (Succeeded and then Pixel (Image, 3, 2) = 99
             and then Pixel (Image, 2, 2) = 7 and then Pixel (Image, 3, 1) = 7,
             "Set_Pixel changes one pixel");
      KI.Get_Pixel (Image, 4, 0, Value, Status);
      Check (Failed (K.Failure_Index_Out_Of_Range,
                     "Get_Pixel: pixel (4, 0) is outside the 4 x 3 image")
             and then Value = 0,
             "Get_Pixel at X = Width");
      KI.Set_Pixel (Image, -1, 0, 1, Status);
      Check (Failed (K.Failure_Index_Out_Of_Range,
                     "Set_Pixel: pixel (-1, 0) is outside the 4 x 3 image"),
             "Set_Pixel at X = -1");
      KI.Get_Pixel (Image, 0, K.Int32'Last, Value, Status);
      Check (Failed (K.Failure_Index_Out_Of_Range,
                     "Get_Pixel: pixel (0, 2147483647) is outside the 4 x 3 "
                     & "image"),
             "Get_Pixel at Y = Int32'Last");
      KI.Get_Pixel (No_Image, 0, 0, Value, Status);
      Check (Failed (K.Failure_Image_No_Pixels,
                     "Get_Pixel: the image has no pixels"),
             "Get_Pixel of null");
      KI.Fill (No_Image, 1, Status);
      Check (Failed (K.Failure_Image_No_Pixels,
                     "Fill: the image has no pixels"),
             "Fill of null");
      KI.Fill (Image, 5, Status);
      Check (Succeeded and then
               (for all Y in 0 .. 2 =>
                  (for all X in 0 .. 3 => Image.Pixels (Y, X) = 5)),
             "Fill");

      KI.Duplicate (Image, Other, Status);
      Check (Succeeded and then KI.Valid_Image (Other)
             and then Other.Pixels.all = Image.Pixels.all,
             "Duplicate copies the pixels");
      KI.Set_Pixel (Other, 0, 0, 1, Status);
      Check (Pixel (Image, 0, 0) = 5, "Duplicate is independent");
      KI.Destroy (Other, Status);
      Check (Succeeded and then Other = null, "Destroy sets the handle to null");
      KI.Destroy (Other, Status);
      Check (Succeeded and then Other = null, "Destroy of null");
      KI.Duplicate (No_Image, Other, Status);
      Check (Succeeded and then Other = null, "Duplicate of null is null");

      KI.Create (0, 5, 0, Other, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Other = null,
             "Create with Width 0");
      KI.Create (65_536, 32_768, 0, Other, Status);
      Check (Failed (K.Failure_Bad_Parameter,
                     "Create: the image size 65536 x 32768 is too large")
             and then Other = null,
             "Create beyond Max_Pixels");

      --  An inconsistent record (C cannot build one, Ada can).
      Other := new KI.Ks_Image_8_Grey_Data'
        (Width => 5, Height => 2, Pixels => new KI.Grey_8_Matrix (0 .. 1,
                                                                  0 .. 1));
      Check (not KI.Valid_Image (Other), "an inconsistent handle is not valid");
      KI.Get_Pixel (Other, 0, 0, Value, Status);
      Check (Failed (K.Failure_Bad_Parameter,
                     "Get_Pixel: Image is not a valid image handle"),
             "Get_Pixel of an inconsistent handle");
      KI.Width (Other, Size, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Size = 0,
             "Width of an inconsistent handle");
      KI.Destroy (Other, Status);

      Section ("images kernel: lean pixel access");
      KI.Try_Get_Pixel (Image, 3, 2, Value, Done);
      Check (Done and then Value = 5, "Try_Get_Pixel");
      KI.Try_Get_Pixel (Image, 4, 2, Value, Done);
      Check (not Done and then Value = 0, "Try_Get_Pixel outside");
      KI.Try_Get_Pixel (No_Image, 0, 0, Value, Done);
      Check (not Done, "Try_Get_Pixel of null");
      KI.Try_Set_Pixel (Image, 1, 1, 42, Done);
      Check (Done and then Pixel (Image, 1, 1) = 42, "Try_Set_Pixel");
      KI.Try_Set_Pixel (Image, 1, 3, 43, Done);
      Check (not Done and then Pixel (Image, 1, 1) = 42,
             "Try_Set_Pixel outside changes nothing");

      Section ("images kernel: rows and matrices");
      declare
         Row  : KI.Grey_8_Row (10 .. 13) := [1, 2, 3, 4];
         Back : KI.Grey_8_Row (100 .. 103);
         Long : KI.Grey_8_Row (0 .. 4) := [others => 9];
      begin
         KI.Set_Row (Image, 1, Row, Status);
         Check (Succeeded and then Pixel (Image, 0, 1) = 1
                and then Pixel (Image, 3, 1) = 4
                and then Pixel (Image, 0, 0) = 5,
                "Set_Row with other bounds changes row 1 only");
         KI.Get_Row (Image, 1, Back, Status);
         Check (Succeeded and then Back = Row, "Get_Row");
         KI.Get_Row (Image, 1, Long, Status);
         Check (Failed (K.Failure_Index_Out_Of_Range,
                        "Get_Row: the row array has 5 elements but the "
                        & "image is 4 pixels wide"),
                "Get_Row with a row too long");
         KI.Set_Row (Image, 3, Row, Status);
         Check (Failed (K.Failure_Index_Out_Of_Range,
                        "Set_Row: row 3 is outside the 4 x 3 image"),
                "Set_Row below the last row");
         Row := [others => 0];
         KI.Set_Row (No_Image, 0, Row, Status);
         Check (Status.Failure = K.Failure_Image_No_Pixels,
                "Set_Row of null");
      end;
      declare
         M     : KI.Grey_8_Matrix (5 .. 6, 7 .. 9) := [[1, 2, 3], [4, 5, 6]];
         Last_Row, Last_Column : Natural;
         Wrong : KI.Grey_8_Matrix (0 .. 1, 0 .. 1);
      begin
         KI.Create_From_Matrix (M, Other, Status);
         Check (Succeeded and then Other.Width = 3 and then Other.Height = 2
                and then Pixel (Other, 0, 0) = 1
                and then Pixel (Other, 2, 1) = 6,
                "Create_From_Matrix with other bounds");
         KI.Matrix_Bounds (Other, Last_Row, Last_Column, Status);
         Check (Succeeded and then Last_Row = 1 and then Last_Column = 2,
                "Matrix_Bounds");
         M := [others => [others => 0]];
         KI.Get_Matrix (Other, M, Status);
         Check (Succeeded and then M (5, 7) = 1 and then M (6, 9) = 6,
                "Get_Matrix into other bounds");
         KI.Get_Matrix (Other, Wrong, Status);
         Check (Status.Failure = K.Failure_Index_Out_Of_Range,
                "Get_Matrix with the wrong size");
         KI.Matrix_Bounds (No_Image, Last_Row, Last_Column, Status);
         Check (Failed (K.Failure_Image_No_Pixels,
                        "To_Matrix: the image has no pixels"),
                "Matrix_Bounds of null");
         KI.Destroy (Other, Status);
      end;
      declare
         Empty : KI.Grey_8_Matrix (1 .. 0, 1 .. 3);
      begin
         KI.Create_From_Matrix (Empty, Other, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter and then Other = null,
                "Create_From_Matrix of an empty matrix");
      end;

      Section ("images kernel: 16-bit images");
      KI.Create (3, 2, 1000, Deep, Status);
      Check (Succeeded and then KI.Valid_Image (Deep)
             and then Deep.Pixels (1, 2) = 1000, "16-bit Create");
      KI.Set_Pixel (Deep, 2, 1, 65_535, Status);
      KI.Get_Pixel (Deep, 2, 1, Value_16, Status);
      Check (Succeeded and then Value_16 = 65_535, "16-bit Set/Get_Pixel");
      KI.Get_Pixel (Deep, 3, 0, Value_16, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range,
             "16-bit Get_Pixel outside");

      Section ("images kernel: colour planes");
      declare
         R, G, B    : KI.Ks_Image_8_Grey;
         R2, G2, B2 : KI.Ks_Image_8_Grey;
         V1, V2, V3 : KI.Grey_8;
      begin
         KI.Create_Color (2, 2, 10, 20, 30, R, G, B, Status);
         Check (Succeeded and then KI.Valid_Image (R) and then KI.Valid_Image (G)
                and then KI.Valid_Image (B) and then G.Pixels (1, 1) = 20,
                "Create_Color");
         KI.Set_Pixel_Color (R, G, B, 1, 0, 1, 2, 3, Status);
         KI.Get_Pixel_Color (R, G, B, 1, 0, V1, V2, V3, Status);
         Check (Succeeded and then V1 = 1 and then V2 = 2 and then V3 = 3,
                "Set/Get_Pixel_Color");
         KI.Get_Pixel_Color (R, No_Image, B, 0, 0, V1, V2, V3, Status);
         Check (Failed (K.Failure_Bad_Parameter,
                        "Get_Pixel: Red, Green and Blue must be planes of "
                        & "the same size"),
                "Get_Pixel_Color with one plane missing");
         KI.Get_Pixel_Color (No_Image, No_Image, No_Image, 0, 0, V1, V2, V3, Status);
         Check (Status.Failure = K.Failure_Image_No_Pixels,
                "Get_Pixel_Color without planes");
         KI.Try_Get_Pixel_Color (R, G, B, 1, 0, V1, V2, V3, Done);
         Check (Done and then V3 = 3, "Try_Get_Pixel_Color");
         KI.Try_Set_Pixel_Color (R, G, B, 2, 0, 0, 0, 0, Done);
         Check (not Done, "Try_Set_Pixel_Color outside");
         KI.Duplicate_Color (R, G, B, R2, G2, B2, Status);
         Check (Succeeded and then R2.Pixels.all = R.Pixels.all
                and then B2.Pixels.all = B.Pixels.all, "Duplicate_Color");
         KI.Create (2, 2, 77, Other, Status);
         KI.Set_Plane (G2, Other, Status);
         Check (Succeeded and then G2.Pixels (0, 0) = 77
                and then G.Pixels (0, 0) = 20, "Set_Plane copies");
         KI.Set_Plane (G2, G2, Status);
         Check (Succeeded and then G2.Pixels (0, 0) = 77,
                "Set_Plane of a plane onto itself");
         KI.Set_Plane (No_Image, Other, Status);
         Check (Failed (K.Failure_Bad_Parameter,
                        "Set_Plane: Pixels is 2 x 2 but the colour image "
                        & "is 0 x 0"),
                "Set_Plane into a colour image without pixels");
         KI.Set_Plane (G2, No_Image, Status);
         Check (Failed (K.Failure_Image_No_Pixels,
                        "Set_Plane: Pixels has no pixels"),
                "Set_Plane from null");
         KI.Destroy (Other, Status);
         KI.Create (3, 2, 0, Other, Status);
         KI.Set_Plane (G2, Other, Status);
         Check (Failed (K.Failure_Bad_Parameter,
                        "Set_Plane: Pixels is 3 x 2 but the colour image "
                        & "is 2 x 2"),
                "Set_Plane with another size");
         KI.Destroy (Other, Status);
         KI.Destroy (R2, Status);
         KI.Destroy (G2, Status);
         KI.Destroy (B2, Status);
         KI.Duplicate_Color (No_Image, No_Image, No_Image, R2, G2, B2, Status);
         Check (Succeeded and then R2 = null and then G2 = null
                and then B2 = null,
                "Duplicate_Color of three nulls");
         KI.Destroy (R, Status);
         KI.Destroy (G, Status);
         KI.Destroy (B, Status);
      end;

      Section ("images kernel: coordinate space state");
      declare
         Tree     : KC.Ks_Coordinate_Space_Tree;
         Bad      : KC.Ks_Coordinate_Space_Tree;
         Selected : KC.Ks_Space_Name := KI.Root_Space_Name;
         Name     : KC.Ks_Space_Name;
         P        : KT.Ks_Transform_2D_Linear;
         T        : KT.Ks_Transform_2D_Linear;
         Shift    : constant KT.Ks_Transform_2D_Linear :=
           (Translation_X => 3.0, others => <>);
         Double   : constant KT.Ks_Transform_2D_Linear :=
           (A => 2.0, D => 2.0, others => <>);
      begin
         KC.Add_Space (Tree, N ("@"), N ("F"), Shift,
                       KC.Add_Space_Duplicate_Is_Error, Status);
         KI.Set_Selected_Space_Name (Tree, Selected, N ("@\F"), Status);
         Check (Succeeded and then KC.To_String (Selected) = "@\F",
                "select a space of the tree");
         KI.Set_Selected_Space_Name (Tree, Selected, N ("@\G"), Status);
         Check (Failed (K.Failure_Image_Bad_Selected_Space_Name,
                        "Selected_Space_Name: no space named ""@\G"" in the "
                        & "image's coordinate space tree")
                and then KC.To_String (Selected) = "@\F",
                "an unknown name leaves the selection");
         KI.Set_Selected_Space_Name (Tree, Selected, N ("."), Status);
         Check (Succeeded and then KC.To_String (Selected) = "@\F",
                """."" keeps the selection");
         KI.Resolve_Space_Name (Tree, Selected, N ("."), Name, Status);
         Check (Succeeded and then KC.To_String (Name) = "@\F",
                "resolve ""."" ");
         KI.Resolve_Space_Name (Tree, Selected, N ("#"), Name, Status);
         Check (Succeeded and then KC.To_String (Name) = "#",
                "resolve ""#""");

         P := Double;
         KI.Get_Transform (Tree, Selected, P, N ("#"), N ("."), T, Status);
         Check (Succeeded and then T = (A => 2.0, D => 2.0,
                                        Translation_X => 6.0, others => <>),
                "Get_Transform into ""#"" composes P after the path");
         KI.Get_Transform (Tree, Selected, P, N ("."), N ("#"), T, Status);
         Check (Succeeded and then T = (A => 0.5, D => 0.5,
                                        Translation_X => -3.0, others => <>),
                "Get_Transform out of ""#""");
         KI.Get_Transform (Tree, Selected, P, N ("@\F"), N ("."), T, Status);
         Check (Succeeded and then T = KT.Ks_Transform_2D_Linear'(others => <>),
                "the same space twice is exactly the identity");
         KI.Get_Transform (Tree, Selected, (A => NaN, others => <>), N ("#"),
                           N ("@"), T, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter,
                "Get_Transform with a NaN in Pixel_From_Root");

         KI.Set_Pixel_From_Root_Transform
           (P, (A => 1.0, B => 2.0, C => 2.0, D => 4.0, others => <>),
            Status);
         Check (Failed (K.Failure_Transform_Singular,
                        "Pixel_From_Root_Transform: the transform is singular")
                and then P = Double,
                "a singular pixel-from-root transform is rejected");
         KI.Set_Pixel_From_Root_Transform
           (P, (A => 1.0E200, others => <>), Status);
         Check (Status.Failure = K.Failure_Bad_Parameter and then P = Double,
                "a transform beyond the bound is rejected");
         KI.Set_Pixel_From_Root_Transform (P, Shift, Status);
         Check (Succeeded and then P = Shift, "a transform is stored");

         KC.Init (Bad, Status);
         KI.Selection_For_New_Tree (Tree, Selected, Bad, Status);
         Check (Succeeded and then KC.To_String (Selected) = "@",
                "a new tree without the selected space selects ""@""");
         Selected := N ("#");
         KI.Selection_For_New_Tree (Tree, Selected, Bad, Status);
         Check (Succeeded and then KC.To_String (Selected) = "#",
                """#"" survives a new tree");

         Selected := N ("@\F");
         KC.Delete_Subtree (Tree, N ("@\F"), Status);
         KI.Selected_Space_Name (Tree, Selected, Name, Status);
         Check (Succeeded and then KC.To_String (Name) = "@",
                "a removed selected space reads as ""@""");

         Bad.Count := 0;
         KI.Selected_Space_Name (Bad, Selected, Name, Status);
         Check (Failed (K.Failure_Bad_Parameter,
                        "Tree is not a valid coordinate space tree")
                and then Name.Length = 0,
                "an invalid tree is rejected");
      end;

      Section ("images kernel: stream helpers");
      declare
         Tree : KC.Ks_Coordinate_Space_Tree;
         W, H : K.Int32;
         T    : KT.Ks_Transform_2D_Linear;
         Name : KC.Ks_Space_Name;
         Count : Natural;
         Inf  : constant KI.U64 := 16#7FF0_0000_0000_0000#;
         One  : constant KI.U64 := 16#3FF0_0000_0000_0000#;
         Zero_Bits : constant KI.U64 := 0;
         Identity_Bits : constant KI.Transform_Bits :=
           [One, Zero_Bits, Zero_Bits, One, Zero_Bits, Zero_Bits];
      begin
         Check (KI.To_Bits (KT.Ks_Transform_2D_Linear'(others => <>))
                  = Identity_Bits,
                "To_Bits gives the IEEE 754 bits");
         KI.Check_Read_Code (KI.Code_Grey_8, KI.Code_Grey_16, Status);
         Check (Status.Failure = K.Failure_Image_File, "a wrong format code");
         KI.Check_Read_Size (KI.Code_Grey_8, 0, 0, W, H, Status);
         Check (Succeeded and then W = 0 and then H = 0, "a size of 0 x 0");
         KI.Check_Read_Size (KI.Code_Grey_8, 0, 5, W, H, Status);
         Check (Failed (K.Failure_Image_File,
                        "Ks_Image_8_Grey'Read: the image size 0 x 5 has one "
                        & "zero dimension"),
                "a size with one zero dimension");
         KI.Check_Read_Size (KI.Code_Grey_16, 46_341, 46_341, W, H, Status);
         Check (Failed (K.Failure_Image_File,
                        "Ks_Image_16_Grey'Read: the image size 46341 x 46341 "
                        & "is too large"),
                "a size beyond Max_Pixels");
         KI.Check_Read_Size (KI.Code_Colour, 2_147_483_647, 1, W, H, Status);
         Check (Succeeded and then W = K.Int32'Last and then H = 1,
                "the largest size");
         KI.Read_Pixel_From_Root
           (KI.Code_Grey_8, [Inf, Zero_Bits, Zero_Bits, One, Zero_Bits,
                             Zero_Bits], T, Status);
         Check (Status.Failure = K.Failure_Image_File
                and then T = KT.Ks_Transform_2D_Linear'(others => <>),
                "a pixel-from-root transform with an infinity");
         KI.Read_Pixel_From_Root (KI.Code_Grey_8, Identity_Bits, T, Status);
         Check (Succeeded and then T = KT.Ks_Transform_2D_Linear'(others => <>),
                "the identity read from its bits");
         KI.Check_Read_Space_Count (KI.Code_Grey_8, 63, Status);
         Check (Succeeded, "63 spaces besides the root");
         KI.Check_Read_Space_Count (KI.Code_Grey_8, 64, Status);
         Check (Status.Failure = K.Failure_Image_File, "64 spaces besides");
         KI.Check_Read_Name_Length (KI.Code_Grey_8, 256, Count, Status);
         Check (Succeeded and then Count = 256, "a name of 256 characters");
         KI.Check_Read_Name_Length (KI.Code_Grey_8, 257, Count, Status);
         Check (Status.Failure = K.Failure_Image_File and then Count = 0,
                "a name of 257 characters");
         KI.Read_Space (KI.Code_Grey_8, Tree, N ("@\A"), Identity_Bits, Status);
         Check (Succeeded and then Tree.Count = 2, "a space read");
         KI.Read_Space (KI.Code_Grey_8, Tree, N ("@\B"),
                        [Inf, Inf, Inf, Inf, Inf, Inf], Status);
         Check (Status.Failure = K.Failure_Image_File and then Tree.Count = 2,
                "a space with infinite entries");
         KI.Read_Space (KI.Code_Grey_8, Tree, N ("@\C\D"), Identity_Bits,
                        Status);
         Check (Status.Failure = K.Failure_Image_File
                and then Message (1 .. 22) = "Ks_Image_8_Grey'Read: ",
                "a space before its parent, named in the message");
         KI.Read_Selection (KI.Code_Grey_8, Tree, N ("@\A"), Name, Status);
         Check (Succeeded and then KC.To_String (Name) = "@\A",
                "a selection in the tree");
         KI.Read_Selection (KI.Code_Grey_8, Tree, N ("@\Z"), Name, Status);
         Check (Status.Failure = K.Failure_Image_File
                and then KC.To_String (Name) = "@",
                "a selection not in the tree");
         KI.Stream_Ended (KI.Code_Spaces_Part, Status);
         Check (Failed (K.Failure_Image_File,
                        "Ks_Image'Read: the stream ends before the image is "
                        & "complete"),
                "Stream_Ended");
      end;

      Section ("images kernel: pixels in stream form");
      declare
         Position : KI.Pixel_Position;
         Length   : Natural;
         Bytes    : KI.Grey_8_Row (1 .. 5);
         Pair     : KI.Grey_8_Row (1 .. 4);
      begin
         --  Image is 4 x 3: row 0 is 5 5 5 5, row 1 is 1 2 3 4.
         KI.Next_Chunk (Image, Position, 5, Length);
         Check (Length = 5, "Next_Chunk limited by the chunk");
         KI.Get_Bytes (Image, Position, Bytes, Status);
         Check (Succeeded and then Bytes = [5, 5, 5, 5, 1]
                and then Position = (Row => 1, Column => 1),
                "Get_Bytes across a row end");
         Position := (Row => 2, Column => 2);
         KI.Next_Chunk (Image, Position, 5, Length);
         Check (Length = 2, "Next_Chunk limited by the pixels left");
         KI.Get_Bytes (Image, Position, Bytes, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter,
                "Get_Bytes beyond the end");
         Position := (Row => 3, Column => 0);
         KI.Next_Chunk (Image, Position, 5, Length);
         Check (Length = 0, "Next_Chunk at the end");
         Position := (Row => 0, Column => 0);
         KI.Put_Bytes (Image, Position, [9, 8, 7, 6, 5], Status);
         Check (Succeeded and then Pixel (Image, 3, 0) = 6
                and then Pixel (Image, 0, 1) = 5
                and then Pixel (Image, 1, 1) = 2,
                "Put_Bytes across a row end");
         KI.Next_Chunk (Deep, (Row => 0, Column => 0), 5, Length);
         Check (Length = 4, "16-bit Next_Chunk: whole pixels");
         Position := (Row => 1, Column => 1);
         KI.Get_Bytes (Deep, Position, Pair, Status);
         Check (Succeeded and then Pair = [16#E8#, 16#03#, 16#FF#, 16#FF#],
                "16-bit Get_Bytes: least significant byte first");
         Position := (Row => 0, Column => 0);
         KI.Put_Bytes (Deep, Position, [16#34#, 16#12#], Status);
         KI.Get_Pixel (Deep, 0, 0, Value_16, Status);
         Check (Succeeded and then Value_16 = 16#1234#, "16-bit Put_Bytes");
         KI.Put_Bytes (Deep, Position, [1, 2, 3], Status);
         Check (Status.Failure = K.Failure_Bad_Parameter,
                "16-bit Put_Bytes of an odd length");
         Position := (Row => 5, Column => 0);
         KI.Put_Bytes (Image, Position, [1], Status);
         Check (Status.Failure = K.Failure_Bad_Parameter,
                "Put_Bytes at an invalid position");
      end;

      KI.Destroy (Image, Status);
      KI.Destroy (Deep, Status);
      Check (Image = null and then Deep = null, "handles destroyed");
   end Test_Images_Kernel;


   procedure Test_Image_File_Kernel is
      package KF renames AMV.Kernels.Image_File;
      package KI renames AMV.Kernels.Images;
      use type K.Int64;
      use type KF.Ks_Image_File_Contents;
      use type KF.Byte_Array;
      use type KI.Ks_Image_8_Grey;
      use type KI.Grey_8;
      use type KI.Grey_16;
      use type Interfaces.Unsigned_32;

      Status   : K.Ks_Status;
      Contents : KF.Ks_Image_File_Contents;
      Count    : K.Int32;

      function Message return String is
        (String (Status.Message (1 .. Natural (Status.Length))));

      function Succeeded return Boolean is
        (Status.Failure = K.Failure_None);

      function Failed (Code : K.Int32; Text : String) return Boolean is
        (Status.Failure = Code and then Message = Text);

      function Bytes (Text : String; First : K.Int64 := 1)
         return KF.Byte_Array
      is
         Result : KF.Byte_Array (First .. First + Text'Length - 1);
      begin
         for I in Result'Range loop
            Result (I) := Character'Pos (Text (Text'First
                                               + Integer (I - First)));
         end loop;
         return Result;
      end Bytes;

      function LE (Value : K.Int64; Size : Positive) return KF.Byte_Array is
         Rest : K.Int64 := Value mod 2 ** (8 * Size);
      begin
         return Result : KF.Byte_Array (1 .. K.Int64 (Size)) do
            for I in Result'Range loop
               Result (I) := KF.Byte (Rest mod 256);
               Rest := Rest / 256;
            end loop;
         end return;
      end LE;

      function BMP_Header
        (Offset, Width, Height, Bits : K.Int64;
         Header_Size                 : K.Int64 := 40;
         Colours_Used                : K.Int64 := 0) return KF.Byte_Array
      is
        (Bytes ("BM") & LE (0, 4) & LE (0, 4) & LE (Offset, 4)
         & LE (Header_Size, 4) & LE (Width, 4) & LE (Height, 4)
         & LE (1, 2) & LE (Bits, 2) & LE (0, 4) & LE (0, 4) & LE (0, 4)
         & LE (0, 4) & LE (Colours_Used, 4) & LE (0, 4));

      procedure Decode_Fails (Data : KF.Byte_Array; Text, Description : String)
      is
      begin
         KF.Decode (Data, Contents, Status);
         Check (Failed (K.Failure_Image_File, Text) and then Contents = null,
                Description & ": " & Message);
      end Decode_Fails;

      Grey    : KI.Ks_Image_8_Grey;
      Grey_16 : KI.Ks_Image_16_Grey;
      Red, Green, Blue : KI.Ks_Image_8_Grey;
      Value   : KI.Grey_8;
      Value_16 : KI.Grey_16;
      Encoding, Image_Type, Maxval : K.Int32;
      Size    : K.Int64;
   begin
      Section ("image file kernel: malformed and malicious bytes");
      Decode_Fails (Bytes (""), "the file is empty", "no bytes");
      Decode_Fails (Bytes ("P5 40000 40000 255" & ASCII.LF) & [1 .. 10 => 0],
                    "image 0: truncated pixel data: 1600000000 bytes "
                    & "needed but only 10 present",
                    "huge PNM header, tiny raster");
      Decode_Fails (Bytes ("P2 70000 70000 255 1"),
                    "image 0: the image size 70000 x 70000 is too large",
                    "PNM size above the pixel limit");
      Decode_Fails (Bytes ("P5 99999999999 1 255"),
                    "image 0: the width is too large",
                    "PNM width above Int32");
      Decode_Fails (BMP_Header (54, 30_000, 30_000, 24) & [1 .. 4 => 0],
                    "truncated BMP file: the pixel data needs 2700000054 "
                    & "bytes but the file has only 58",
                    "huge BMP header, tiny pixel data");
      Decode_Fails (BMP_Header (54, 1, 1, 24, Header_Size => 2**32 - 1),
                    "truncated BMP file: the information header needs "
                    & "4294967309 bytes but the file has only 54",
                    "BMP header size near 2**32");
      Decode_Fails (BMP_Header (54, -2**31, 1, 24) & [1 .. 4 => 0],
                    "malformed BMP file: the width is -2147483648",
                    "BMP width -2**31");
      Decode_Fails (BMP_Header (54, 1, -2**31, 24) & [1 .. 4 => 0],
                    "the image size 1 x 2147483648 is too large",
                    "BMP height -2**31");
      Decode_Fails (BMP_Header (2**32 - 1, 1, 1, 24) & [1 .. 4 => 0],
                    "truncated BMP file: the pixel data needs 4294967298 "
                    & "bytes but the file has only 58",
                    "BMP pixel offset near 2**32");
      KF.Decode (BMP_Header (62, 9, 1, 1, Colours_Used => 2)
                 & [0, 0, 0, 0, 255, 255, 255, 0] & [255, 128, 0, 0],
                 Contents, Status);
      Check (Succeeded and then Contents /= null,
             "a 1-bit BMP of 9 pixels in 2 bytes decodes");
      KF.Destroy (Contents, Status);
      Decode_Fails (BMP_Header (58, 4, 1, 8, Colours_Used => 1)
                    & [7, 7, 7, 0] & [0, 0, 1, 0],
                    "malformed BMP file: a pixel uses palette index 1 but "
                    & "the palette has 1 entries",
                    "palette index beyond a one-entry palette");
      Decode_Fails (Bytes ("P5 1 1 255" & ASCII.LF & 'A' & "  Px"),
                    "image 1: unknown PNM magic number 'P' followed by 'x'",
                    "garbage second image");
      Decode_Fails (Bytes ("P5 1 1 255" & ASCII.LF & "AB", First => 1_000),
                    "unexpected 'B' after image 0 at file offset 12",
                    "offsets in messages count from the first byte");
      KF.Decode (Bytes ("P5 1 1 255" & ASCII.LF & "A",
                        First => KF.Max_Length - 11),
                 Contents, Status);
      Check (Succeeded and then Contents /= null,
             "an array at the end of Byte_Index decodes");
      KF.Destroy (Contents, Status);

      Section ("image file kernel: encoders and decoder agree");
      KI.Create (5, 3, 0, Grey, Status);
      for Y in 0 .. 2 loop
         for X in 0 .. 4 loop
            KI.Set_Pixel (Grey, K.Int32 (X), K.Int32 (Y),
                          KI.Grey_8 ((X * 37 + Y * 11 + 5) mod 256), Status);
         end loop;
      end loop;
      for Format in KF.Format_PGM .. KF.Format_BMP loop
         KF.Choose_Encoding (Format, KF.Image_Type_Grey_8, 5, 3, Encoding,
                             Status);
         KF.Encoded_Size (Encoding, 5, 3, 0, Size, Status);
         declare
            Data : KF.Byte_Array (1 .. Size);
            Back : KI.Ks_Image_8_Grey;
            Same : Boolean := True;
         begin
            KF.Encode_8_Grey (Encoding, 0, Grey, Data, Status);
            Check (Succeeded, "encode 8-bit, format" & Format'Image);
            KF.Decode (Data, Contents, Status);
            KF.Get_8_Grey_Converted (Contents, 0, Back, Status);
            for Y in 0 .. 2 loop
               for X in 0 .. 4 loop
                  KI.Get_Pixel (Back, K.Int32 (X), K.Int32 (Y), Value,
                                Status);
                  Same := Same
                    and then Value = KI.Grey_8 ((X * 37 + Y * 11 + 5)
                                                 mod 256);
               end loop;
            end loop;
            Check (Same, "8-bit round trip, format" & Format'Image);
            KI.Destroy (Back, Status);
            KF.Destroy (Contents, Status);
         end;
      end loop;
      KI.Destroy (Grey, Status);

      KI.Create (2, 1, 0, Grey_16, Status);
      KI.Set_Pixel (Grey_16, 1, 0, 65_535, Status);
      KF.Encoded_Size (KF.Encoding_P5_16, 2, 1, 1, Size, Status);
      declare
         Data : KF.Byte_Array (1 .. Size);
      begin
         KF.Encode_16_Grey (KF.Encoding_P5_16, 1, Grey_16, Data, Status);
         Check (Succeeded
                and then Data = Bytes (ASCII.LF & "P5" & ASCII.LF & "2 1"
                                       & ASCII.LF & "65535" & ASCII.LF)
                                & [0, 0, 255, 255],
                "16-bit P5 bytes with a leading separator");
         KF.Encode_16_Grey (KF.Encoding_P5_16, 2, Grey_16, Data, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter,
                "a separator of 2 is rejected");
         KF.Decode (Data (2 .. Data'Last), Contents, Status);
         KF.Image_Info (Contents, 0, Image_Type, Maxval, Status);
         Check (Succeeded and then Image_Type = KF.Image_Type_Grey_16
                and then Maxval = 65_535, "16-bit image read back");
         KF.Get_16_Grey (Contents, 0, Grey_16, Status);
         KI.Get_Pixel (Grey_16, 1, 0, Value_16, Status);
         Check (Value_16 = 65_535, "16-bit sample read back");
         KI.Destroy (Grey_16, Status);
         KF.Destroy (Contents, Status);
      end;

      KF.Choose_Encoding (KF.Format_BMP, KF.Image_Type_Color, 70_000,
                          70_000, Encoding, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "Choose_Encoding: a size above the pixel limit");
      KF.Choose_Encoding (KF.Format_BMP, KF.Image_Type_Color, 40_000,
                          40_000, Encoding, Status);
      Check (Failed (K.Failure_Image_File,
                     "the image is too large for a BMP file"),
             "Choose_Encoding: BMP above 4 GB");
      KF.Choose_Encoding (KF.Format_PPM, 9, 1, 1, Encoding, Status);
      Check (Failed (K.Failure_Image_File, "unsupported image type"),
             "Choose_Encoding: unknown image type");

      Section ("image file kernel: stream helpers");
      KF.Read_Contents_Header (0, 0, Contents, Status);
      Check (Succeeded and then Contents = null, "no images: null");
      KF.Read_Contents_Header (3, 2, Contents, Status);
      Check (Failed (K.Failure_Image_File,
                     "Ks_Image_File'Read: a BMP file holds one image, "
                     & "not 3"), "three BMP images");
      KF.Read_Contents_Header (2**31, 1, Contents, Status);
      Check (Status.Failure = K.Failure_Image_File and then Contents = null,
             "too many images");
      KF.Read_Image_Header (2, 255, Status);
      Check (Status.Failure = K.Failure_Image_File,
             "a 16-bit image needs a maxval above 255");
      KF.Read_Contents_Header (2, 1, Contents, Status);
      KF.Image_Count (Contents, Count, Status);
      Check (Succeeded and then Count = 2, "two empty slots");
      KF.Get_8_Grey (Contents, 0, Grey, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Grey = null,
             "an empty slot cannot be read");
      KI.Create (2, 2, 200, Grey, Status);
      KF.Store_8_Grey (Contents, 0, 100, Grey, Status);
      Check (Failed (K.Failure_Image_File,
                     "Ks_Image_File'Read: image 0 has a sample above its "
                     & "maxval 100"), "a sample above the maxval");
      KF.Store_8_Grey (Contents, 0, 255, Grey, Status);
      Check (Succeeded, "store an 8-bit image");
      KF.Store_8_Grey (Contents, 0, 255, Grey, Status);
      Check (Failed (K.Failure_Image_File,
                     "Ks_Image_File'Read: image 0 is stored twice"),
             "a slot is filled once");
      KF.Store_8_Grey (Contents, 2, 255, Grey, Status);
      Check (Status.Failure = K.Failure_Image_File,
             "a slot beyond the count");
      KI.Destroy (Grey, Status);
      KI.Create_Color (1, 1, 1, 2, 3, Red, Green, Blue, Status);
      KF.Store_24_Planar_Color (Contents, 1, 255, Red, Green, Blue, Status);
      KI.Destroy (Red, Status);
      KI.Destroy (Green, Status);
      KI.Destroy (Blue, Status);
      KF.Get_8_Grey_Converted (Contents, 1, Grey, Status);
      KI.Get_Pixel (Grey, 0, 0, Value, Status);
      Check (Succeeded and then Value = 2, "converted colour (1, 2, 3)");
      KI.Destroy (Grey, Status);
      KF.Destroy (Contents, Status);
      Check (Contents = null, "contents destroyed");
   end Test_Image_File_Kernel;

   procedure Test_Shapes_Kernel is
      package KS renames AMV.Kernels.Shapes;
      package SU renames Ada.Streams.Storage.Unbounded;
      use type KS.Ks_Polygon;
      use type AMV.Shapes.Ks_Polygon;
      use type Interfaces.Unsigned_32;

      NaN    : constant Real := Zero / Zero;
      Plus   : constant Real := 1.0 / Zero;
      Minus  : constant Real := -1.0 / Zero;
      Values : constant array (1 .. 3) of Real := [NaN, Plus, Minus];
      Names  : constant array (1 .. 3) of String (1 .. 4) :=
        ["NaN ", "+Inf", "-Inf"];
      Status : K.Ks_Status;

      function Message (S : K.Ks_Status) return String is
        (String (S.Message (1 .. Natural (S.Length))));

      procedure Expect_Bad
        (Action : not null access procedure; Text, What : String) is
      begin
         Action.all;
         Fail (What & ": no exception");
      exception
         when E : Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E) = Text,
                   What & ": Ks_Bad_Parameter_Exception """
                   & Ada.Exceptions.Exception_Message (E) & """");
         when E : others =>
            Fail (What & ": raised " & Ada.Exceptions.Exception_Name (E));
      end Expect_Bad;

      Polygon : KS.Ks_Polygon;
      Copy    : KS.Ks_Polygon;
      Count   : K.Int32;
      X, Y    : Real;
      Value   : Real;
   begin
      Section ("shapes kernel: non-finite arguments through the Ada API");
      for I in Values'Range loop
         declare
            V    : constant Real := Values (I);
            Name : constant String := Names (I);

            procedure Rect_X is
               R : AMV.Shapes.Ks_Rectangle;
            begin
               R.Set_X (V);
            end Rect_X;

            procedure Circle_Radius is
               C : AMV.Shapes.Ks_Circle;
            begin
               C.Set_Radius (V);
            end Circle_Radius;

            procedure Ellipse_Rotation is
               E : AMV.Shapes.Ks_Ellipse;
            begin
               E.Set_Rotation (V);
            end Ellipse_Rotation;

            procedure Affine_Skew is
               A : AMV.Shapes.Ks_Rectangle_Affine;
            begin
               A.Set_Skew (V);
            end Affine_Skew;

            procedure Polygon_X is
               P : AMV.Shapes.Ks_Polygon;
            begin
               P.Add_Vertex (V, 0.0);
            end Polygon_X;

            procedure Line_Rotation is
               L : AMV.Shapes.Ks_Line;
            begin
               L.Set_Rotation (V);
            end Line_Rotation;

            procedure Segment_End is
               S : AMV.Shapes.Ks_Line_Segment;
            begin
               S.Set_End_Y (V);
            end Segment_End;

            procedure Marker_X is
               M : AMV.Shapes.Ks_Point_Marker;
            begin
               M.Set_X (V);
            end Marker_X;

            procedure Arc_Span is
               A : AMV.Shapes.Ks_Circular_Arc;
            begin
               A.Set_Angle_Span (V);
            end Arc_Span;

            procedure Contains_X is
               R : AMV.Shapes.Ks_Rectangle;
            begin
               Check (R.Contains_Point (V, 0.0), "unreachable");
            end Contains_X;

            procedure Map_Entry is
               C : AMV.Shapes.Ks_Circle;
            begin
               Check (C.Map (AMV.Transforms.Create (V, 0.0, 0.0, 1.0, 0.0,
                                                    0.0))
                        in AMV.Shapes.Ks_Shape'Class,
                      "unreachable");
            end Map_Entry;
         begin
            Expect_Bad (Rect_X'Access,
                        "Ks_Rectangle.X must be finite and within +/-1.0E150",
                        "Ks_Rectangle.Set_X (" & Name & ")");
            Expect_Bad (Circle_Radius'Access,
                        (if V < 0.0 then "Ks_Circle.Radius must be >= 0"
                         else "Ks_Circle.Radius must be finite and at most "
                              & "4.0E150"),
                        "Ks_Circle.Set_Radius (" & Name & ")");
            Expect_Bad (Ellipse_Rotation'Access,
                        "Ks_Ellipse.Rotation must be finite and within "
                        & "+/-1.0E150",
                        "Ks_Ellipse.Set_Rotation (" & Name & ")");
            Expect_Bad (Affine_Skew'Access,
                        "Ks_Rectangle_Affine.Skew must be finite and within "
                        & "+/-1.0E150",
                        "Ks_Rectangle_Affine.Set_Skew (" & Name & ")");
            Expect_Bad (Polygon_X'Access,
                        "Ks_Polygon.Add_Vertex: X must be finite and within "
                        & "+/-1.0E150",
                        "Ks_Polygon.Add_Vertex (" & Name & ", 0)");
            Expect_Bad (Line_Rotation'Access,
                        "Ks_Line.Rotation must be finite and within "
                        & "+/-1.0E150",
                        "Ks_Line.Set_Rotation (" & Name & ")");
            Expect_Bad (Segment_End'Access,
                        "Ks_Line_Segment.End_Y must be finite and within "
                        & "+/-1.0E150",
                        "Ks_Line_Segment.Set_End_Y (" & Name & ")");
            Expect_Bad (Marker_X'Access,
                        "Ks_Point_Marker.X must be finite and within "
                        & "+/-1.0E150",
                        "Ks_Point_Marker.Set_X (" & Name & ")");
            Expect_Bad (Arc_Span'Access,
                        "Ks_Circular_Arc.Angle_Span must be finite and "
                        & "within +/-1.0E150",
                        "Ks_Circular_Arc.Set_Angle_Span (" & Name & ")");
            Expect_Bad (Contains_X'Access,
                        "X must be finite and within +/-1.0E150",
                        "Contains_Point (" & Name & ", 0)");
            Expect_Bad (Map_Entry'Access,
                        "Transform must be finite and within +/-1.0E150",
                        "Ks_Circle.Map (A = " & Name & ")");
         end;
      end loop;

      Section ("shapes kernel: bounds");
      declare
         procedure Far_Corner is
            R : AMV.Shapes.Ks_Rectangle;
            Min_X, Min_Y, Max_X, Max_Y : Real;
         begin
            R.Set_XY_Width_Height (1.0E150, 0.0, 4.0E150, 0.0);
            R.Get_Bounding_Box (Min_X, Min_Y, Max_X, Max_Y);
         end Far_Corner;

         procedure Beyond_X is
            R : AMV.Shapes.Ks_Rectangle;
         begin
            R.Set_X (1.1E150);
         end Beyond_X;

         procedure Long_Width is
            R : AMV.Shapes.Ks_Rectangle;
         begin
            R.Set_Width (4.1E150);
         end Long_Width;

         procedure Outer_Radius is
            S : AMV.Shapes.Ks_Circular_Annulus_Section;
         begin
            S.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
              (0.0, 0.0, 4.0E150, 0.0, 1.0, 2.0);
         end Outer_Radius;

         procedure Far_Line is
            L : AMV.Shapes.Ks_Line;
         begin
            L.Set_Distance_Rotation (2.0E150, 0.0);
         end Far_Line;

         R : AMV.Shapes.Ks_Rectangle;
         C : AMV.Shapes.Ks_Circle;
         S : AMV.Shapes.Ks_Line_Segment;
      begin
         Expect_Bad (Far_Corner'Access,
                     "Ks_Rectangle.Get_Bounding_Box: the far corner would "
                     & "exceed the supported range",
                     "a bounding box beyond 1.0E150");
         Expect_Bad (Beyond_X'Access,
                     "Ks_Rectangle.X must be finite and within +/-1.0E150",
                     "X = 1.1E150");
         Expect_Bad (Long_Width'Access,
                     "Ks_Rectangle.Width must be finite and at most 4.0E150",
                     "Width = 4.1E150");
         Expect_Bad (Outer_Radius'Access,
                     "Ks_Circular_Annulus_Section.Radius * Radial_Scale "
                     & "would exceed the supported range",
                     "a second radius beyond 4.0E150");
         Expect_Bad (Far_Line'Access,
                     "Ks_Line.X or Y would exceed the supported range",
                     "a line 2.0E150 from the origin");
         R.Set_XY_Width_Height (-1.0E150, -1.0E150, 2.0E150, 2.0E150);
         Check (abs (R.Area - 4.0E300) <= 1.0E286,
                "the largest square has area 4.0E300");
         C.Set_Center_Radius (0.0, 0.0, 1.0E150);
         R := AMV.Shapes.Enclosing_Rectangle (C);
         Check (R.X = -1.0E150 and then R.Width = 2.0E150,
                "the box of a circle of radius 1.0E150 is a valid rectangle");
         S.Set_Start_End (-1.0E150, -1.0E150, 1.0E150, 1.0E150);
         Check (abs (S.Length - 2.828_427_124_746_190_1E150) <= 1.0E137,
                "the longest segment has a valid length");
      end;

      Section ("shapes kernel: the rectangle's covering property");
      declare
         Rect   : constant KS.Ks_Rectangle := (-3.0, 4.0, 100.0, 50.0);
         Inside : K.Int32;
         Slack, Min_X, Min_Y, Max_X, Max_Y : Real;
         Covered : Boolean := True;
      begin
         KS.Boundary_Slack (Rect, Slack, Status);
         KS.Get_Bounding_Box (Rect, Min_X, Min_Y, Max_X, Max_Y, Status);
         for I in -10 .. 10 loop
            declare
               PX : constant Real := Min_X - Slack * Real (I) / 5.0;
               PY : constant Real := Max_Y + Slack * Real (I) / 5.0;
            begin
               KS.Contains_Point (Rect, PX, PY, Inside, Status);
               if Inside = K.True_Value then
                  Covered := Covered and then PX >= Min_X - Slack
                    and then PY <= Max_Y + Slack;
               end if;
            end;
         end loop;
         Check (Covered, "accepted points lie within the slack of the box");
      end;

      Section ("shapes kernel: polygon handles");
      KS.Num_Vertices (null, Count, Status);
      Check (Status.Failure = K.Failure_None and then Count = 0,
             "a null handle has no vertices");
      KS.Get_Vertex (null, 0, X, Y, Status);
      Check (Status.Failure = K.Failure_Index_Out_Of_Range
             and then Message (Status)
                        = "Ks_Polygon.Get_Vertex: vertex index 0 is out of "
                          & "range (the polygon has 0 vertices)",
             "get_vertex of a null handle");
      KS.Duplicate (null, Copy, Status);
      Check (Status.Failure = K.Failure_None and then Copy = null,
             "the duplicate of null is null");
      KS.Add_Vertex (Polygon, 1.0, 1.0, KS.Append_Index, Status);
      KS.Add_Vertex (Polygon, 3.0, 3.0, KS.Append_Index, Status);
      KS.Add_Vertex (Polygon, 2.0, 2.0, 1, Status);
      KS.Add_Vertex (Polygon, 0.0, 0.0, 0, Status);
      KS.Num_Vertices (Polygon, Count, Status);
      Check (Count = 4, "four vertices added");
      for I in 0 .. 3 loop
         KS.Get_Vertex (Polygon, K.Int32 (I), X, Y, Status);
         Check (X = Real (I) and then Y = Real (I),
                "vertex" & I'Image & " is in its place");
      end loop;
      KS.Duplicate (Polygon, Copy, Status);
      Check (KS.Same_Vertices (Polygon, Copy), "a duplicate is the same");
      KS.Remove_Vertex (Copy, 1, Status);
      KS.Get_Vertex (Copy, 1, X, Y, Status);
      Check (X = 2.0 and then not KS.Same_Vertices (Polygon, Copy),
             "remove_vertex moves the later vertices down");
      KS.Clear (Copy, Status);
      Check (KS.Same_Vertices (Copy, null),
             "a cleared polygon has the vertices of null");
      KS.Destroy (Copy, Status);
      KS.Destroy (Copy, Status);
      Check (Status.Failure = K.Failure_None and then Copy = null,
             "destroy twice is harmless");
      KS.Check_Stream_Count (2**20, Status);
      Check (Status.Failure = K.Failure_None, "2**20 vertices may be read");
      KS.Check_Stream_Count (2**20 + 1, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter,
             "a stream with more vertices is rejected");
      declare
         Broken : KS.Ks_Polygon := new KS.Ks_Polygon_Data'(Count    => 5,
                                                          Vertices => null);
      begin
         KS.Area (Broken, Value, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Message (Status)
                           = "Ks_Polygon.Area: the handle is inconsistent",
                "an inconsistent handle is rejected");
         KS.Destroy (Broken, Status);
      end;

      Section ("shapes kernel: the polygon size limit");
      KS.Clear (Polygon, Status);
      for I in 1 .. KS.Max_Vertices loop
         KS.Add_Vertex (Polygon, Real (I), 0.0, KS.Append_Index, Status);
         exit when Status.Failure /= K.Failure_None;
      end loop;
      KS.Num_Vertices (Polygon, Count, Status);
      Check (Count = 2**20, "2**20 vertices can be added");
      KS.Add_Vertex (Polygon, 0.0, 1.0, KS.Append_Index, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message (Status)
                        = "Ks_Polygon.Add_Vertex: the polygon already has "
                          & "the maximum number of vertices (1048576)",
             "the next one is rejected");
      KS.Area (Polygon, Value, Status);
      Check (Status.Failure = K.Failure_None and then Value = 0.0,
             "the area of 2**20 collinear vertices");
      KS.Perimeter (Polygon, Value, Status);
      Check (Status.Failure = K.Failure_None
             and then Value = 2.0 * Real (2**20 - 1),
             "the perimeter of 2**20 collinear vertices");
      KS.Destroy (Polygon, Status);

      Section ("shapes kernel: Ks_Polygon values and streams");
      declare
         P, Q, Back : AMV.Shapes.Ks_Polygon;
         S          : aliased SU.Stream_Type;
      begin
         P.Add_Vertex (0.0, 0.0);
         P.Add_Vertex (10.0, 0.0);
         P.Add_Vertex (5.0, 8.0);
         P.Set_Selected_Space_Name ("@\Fixture");
         Q := P;
         Check (Q = P, "a copy compares equal");
         Q.Set_Vertex (2, 5.0, 9.0);
         Check (P.Get_Vertex_Y (2) = 8.0 and then Q /= P,
                "a copy is independent");
         AMV.Shapes.Ks_Polygon'Write (S'Access, P);
         Back.Add_Vertex (1.0, 1.0);
         AMV.Shapes.Ks_Polygon'Read (S'Access, Back);
         Check (Back = P and then Back.Selected_Space_Name = "@\Fixture",
                "'Write then 'Read gives the same polygon");
         Ada.Strings.Unbounded.Unbounded_String'Write
           (S'Access,
            Ada.Strings.Unbounded.To_Unbounded_String ("@\Fixture"));
         Interfaces.Unsigned_32'Write (S'Access, 16#0010_0001#);
         begin
            AMV.Shapes.Ks_Polygon'Read (S'Access, Back);
            Fail ("a count above 2**20: no exception");
         exception
            when Ks_Bad_Parameter_Exception =>
               Check (Back = P, "a count above 2**20 is rejected and the "
                                & "polygon left unchanged");
         end;
         Ada.Strings.Unbounded.Unbounded_String'Write
           (S'Access,
            Ada.Strings.Unbounded.To_Unbounded_String ("@\Fixture"));
         Interfaces.Unsigned_32'Write (S'Access, 2);
         Real'Write (S'Access, 1.0);
         Real'Write (S'Access, 2.0);
         Real'Write (S'Access, NaN);
         Real'Write (S'Access, 0.0);
         begin
            AMV.Shapes.Ks_Polygon'Read (S'Access, Back);
            Fail ("a NaN vertex in a stream: no exception");
         exception
            when E : Ks_Bad_Parameter_Exception =>
               Check (Back = P
                      and then Ada.Exceptions.Exception_Message (E)
                                 = "Ks_Polygon.Add_Vertex: X must be finite "
                                   & "and within +/-1.0E150",
                      "a NaN vertex in a stream is rejected and the polygon "
                      & "left unchanged");
            when E : others =>
               Fail ("a NaN vertex in a stream: raised "
                     & Ada.Exceptions.Exception_Name (E));
         end;
      end;
   end Test_Shapes_Kernel;

   ---------------------------------------------------------------------
   --  The pixel region kernel (AMV.Kernels.Regions) and AMV.Regions
   ---------------------------------------------------------------------

   package Odd_Regions is

      type Odd_Region is new AMV.Shapes.Ks_Region with null record;
      --  A region type derived outside AMV.Shapes, which the kernel does
      --  not know.

      overriding function Map
        (Shape     : Odd_Region;
         Transform : AMV.Transforms.Ks_Transform_2D_Linear)
         return AMV.Shapes.Ks_Shape'Class is (Shape);

      overriding function Contains_Point
        (Region : Odd_Region; X, Y : Real) return Boolean is (True);

      overriding function Boundary_Slack (Region : Odd_Region) return Real
      is (0.0);

      overriding procedure Get_Bounding_Box
        (Region                     : Odd_Region;
         Min_X, Min_Y, Max_X, Max_Y : out Real);

      overriding function Area (Region : Odd_Region) return Real is (1.0);

      type Plain_Circle is new AMV.Shapes.Ks_Circle with null record;
      --  A type derived from one of AMV.Shapes: rasterised as a circle.

   end Odd_Regions;

   package body Odd_Regions is

      overriding procedure Get_Bounding_Box
        (Region                     : Odd_Region;
         Min_X, Min_Y, Max_X, Max_Y : out Real) is
      begin
         Min_X := 0.0;
         Min_Y := 0.0;
         Max_X := 1.0;
         Max_Y := 1.0;
      end Get_Bounding_Box;

   end Odd_Regions;

   procedure Test_Regions_Kernel is
      package KR renames AMV.Kernels.Regions;
      package KS renames AMV.Kernels.Shapes;
      package KT renames AMV.Kernels.Transforms;
      use type KR.Ks_Pixel_Region;
      use type KR.Ks_Region_Reader;
      use type KR.Byte_Array;
      use type KR.Flag_Matrix_Access;
      use type KR.Bool_Array_Access;
      use type K.Int64;

      NaN      : constant Real := Zero / Zero;
      Identity : constant KT.Ks_Transform_2D_Linear := (others => <>);
      Status   : K.Ks_Status;
      Region   : KR.Ks_Pixel_Region;
      Copy     : KR.Ks_Pixel_Region;
      Value    : K.Int32;
      Circle   : KS.Ks_Circle;

      function Message (S : K.Ks_Status) return String is
        (String (S.Message (1 .. Natural (S.Length))));

      function Count_Of (R : KR.Ks_Pixel_Region) return K.Int32 is
         Result : K.Int32;
         S      : K.Ks_Status;
      begin
         KR.Pixel_Count (R, Result, S);
         return Result;
      end Count_Of;

      function Header
        (X_Min, Y_Min, Width, Height, Count : Interfaces.Unsigned_32)
         return KR.Header_Bytes
      is
         use type Interfaces.Unsigned_32;
         Numbers : constant array (1 .. 6) of Interfaces.Unsigned_32 :=
           [KR.Format_Code, X_Min, Y_Min, Width, Height, Count];
         Result  : KR.Header_Bytes;
      begin
         for N in Numbers'Range loop
            for B in 0 .. 3 loop
               Result (4 * (N - 1) + B + 1) :=
                 Interfaces.Unsigned_8
                   (Interfaces.Shift_Right (Numbers (N), 8 * B) and 16#FF#);
            end loop;
         end loop;
         return Result;
      end Header;
   begin
      Section ("regions kernel: handles and argument checks");
      KR.Whole_Image (0, 0, Region, Status);
      Check (Status.Failure = K.Failure_Image_No_Pixels and then Region = null
             and then Message (Status)
                        = "Whole_Image: the image has no pixels",
             "whole image without pixels");
      KR.Whole_Image (46_341, 46_341, Region, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Region = null,
             "whole image beyond Max_Pixels");
      KR.Whole_Image (5, 0, Region, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Region = null,
             "whole image of width 5 and height 0");
      KR.Whole_Image (7, 3, Region, Status);
      Check (K.Succeeded (Status) and then Count_Of (Region) = 21
             and then KR.Contains_Pixel (Region, 6, 2) = K.True_Value
             and then KR.Contains_Pixel (Region, 7, 2) = K.False_Value
             and then KR.Contains_Pixel (Region, K.Int32'First, 0)
                        = K.False_Value
             and then KR.Contains_Pixel (Region, K.Int32'Last, 0)
                        = K.False_Value,
             "whole image: count and contains at the extremes");
      KR.Duplicate (Region, Copy, Status);
      KR.Destroy (Region, Status);
      Check (Region = null and then Count_Of (Copy) = 21,
             "a duplicate outlives the original");
      KR.Destroy (Copy, Status);
      KR.Destroy (Copy, Status);
      Check (K.Succeeded (Status) and then Copy = null,
             "destroying null does nothing");

      --  A record no entry point would make: every query rejects it,
      --  Contains stays safe.
      Region := new KR.Ks_Pixel_Region_Data'
        (X_Min => 5, Y_Min => 5, Width => 3, Height => 3, Count => 4,
         Flags => new KR.Flag_Matrix (0 .. 1, 0 .. 1));
      KR.Is_Empty (Region, Value, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter
             and then Message (Status)
                        = "Is_Empty: the region handle is inconsistent",
             "an inconsistent handle is rejected");
      KR.Duplicate (Region, Copy, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Copy = null,
             "an inconsistent handle is not duplicated");
      Check (KR.Contains_Pixel (Region, 6, 6) = K.False_Value
             and then KR.Contains_Pixel (Region, 1, 1) = K.False_Value,
             "Contains is safe for an inconsistent handle");
      KR.Destroy (Region, Status);

      Section ("regions kernel: rasterisation through the entry points");
      KS.Set_Center_Radius (5.0, 5.0, 2.0, Circle, Status);
      KR.Rasterize_Circle
        (11, 11, (A => NaN, others => <>), Circle, Region, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Region = null,
             "a NaN transform is rejected");
      KR.Rasterize_Circle
        (11, 11, (A => 1.0E151, others => <>), Circle, Region, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Region = null,
             "a transform beyond 1.0E150 is rejected");
      KR.Rasterize_Circle
        (11, 11, (A => 0.0, D => 0.0, others => <>), Circle, Region, Status);
      Check (Status.Failure = K.Failure_Transform_Singular
             and then Region = null, "a singular transform is rejected");
      KR.Rasterize_Circle (11, 11, Identity, Circle, Region, Status);
      Check (K.Succeeded (Status) and then Count_Of (Region) = 13
             and then Region.Flags /= null
             and then Region.Flags'Length (1) = 5
             and then Region.Flags'Length (2) = 5,
             "a disc keeps flags of the shrunk rectangle only");
      KR.Destroy (Region, Status);

      --  A single pixel in a 2000 x 2000 image: the candidate flags are
      --  freed, and the pixel fills its rectangle, so none are kept.
      declare
         Thin : KS.Ks_Rectangle;
      begin
         KS.Set_XY_Width_Height (999.75, 999.75, 0.5, 0.5, Thin, Status);
         KR.Rasterize_Rectangle (2000, 2000, Identity, Thin, Region, Status);
         Check (K.Succeeded (Status) and then Count_Of (Region) = 1
                and then Region.Flags = null
                and then Region.X_Min = 1000 and then Region.Y_Min = 1000,
                "a one-pixel rectangle keeps no flags");
         KR.Destroy (Region, Status);
      end;

      Section ("regions kernel: restriction by a mask");
      declare
         package KI renames AMV.Kernels.Images;
         Mask   : KI.Ks_Image_8_Grey;
         Result : KR.Ks_Pixel_Region;
         S      : K.Ks_Status;
      begin
         --  A record no entry point would make, for the region and for
         --  the mask.
         Region := new KR.Ks_Pixel_Region_Data'
           (X_Min => 5, Y_Min => 5, Width => 3, Height => 3, Count => 4,
            Flags => new KR.Flag_Matrix (0 .. 1, 0 .. 1));
         KR.Restrict_To_Mask (Region, null, 0, 0, Result, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Result = null
                and then Message (Status)
                           = "Restrict_To_Mask: the region handle is "
                             & "inconsistent",
                "restrict: an inconsistent region is rejected");
         KR.Destroy (Region, Status);
         Mask := new KI.Ks_Image_8_Grey_Data'
           (Width => 3, Height => 3,
            Pixels => new KI.Grey_8_Matrix'(0 .. 1 => [0 .. 1 => 0]));
         KR.Whole_Image (7, 5, Region, Status);
         KR.Restrict_To_Mask (Region, Mask, 0, 0, Result, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Result = null
                and then Message (Status)
                           = "Restrict_To_Mask: the mask is not a valid "
                             & "image handle",
                "restrict: an inconsistent mask is rejected");
         KR.Restrict_To_Mask (null, Mask, 0, 0, Result, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Result = null,
                "restrict: an inconsistent mask is rejected with the empty "
                & "region too");
         KI.Destroy (Mask, S);

         KR.Restrict_To_Mask (null, null, 0, 0, Result, Status);
         Check (K.Succeeded (Status) and then Result = null,
                "restrict: the empty region gives the empty region");
         KR.Restrict_To_Mask (Region, null, 0, 0, Result, Status);
         Check (K.Succeeded (Status) and then Result /= null
                and then Result.Flags = null and then Count_Of (Result) = 35
                and then Result.X_Min = 0 and then Result.Width = 7
                and then Result.Y_Min = 0 and then Result.Height = 5,
                "restrict: a null mask keeps every pixel");
         KR.Destroy (Result, Status);

         --  A hole in the middle: the rectangle stays, with flags.
         KI.Create (3, 3, 1, Mask, S);
         KI.Set_Pixel (Mask, 1, 1, 0, S);
         KR.Restrict_To_Mask (Region, Mask, 2, 1, Result, Status);
         Check (K.Succeeded (Status) and then Count_Of (Result) = 34
                and then Result.Flags /= null
                and then Result.Flags'First (1) = 0
                and then Result.Flags'Last (1) = 4
                and then Result.Flags'First (2) = 0
                and then Result.Flags'Last (2) = 6
                and then KR.Contains_Pixel (Result, 3, 2) = K.False_Value
                and then KR.Contains_Pixel (Result, 2, 2) = K.True_Value,
                "restrict: a hole keeps the rectangle and needs flags");
         KR.Destroy (Result, Status);
         KI.Destroy (Mask, S);

         --  The first column removed: a smaller full rectangle, no flags.
         KI.Create (1, 9, 0, Mask, S);
         KR.Restrict_To_Mask (Region, Mask, 0, -2, Result, Status);
         Check (K.Succeeded (Status) and then Count_Of (Result) = 30
                and then Result.Flags = null
                and then Result.X_Min = 1 and then Result.Width = 6
                and then Result.Y_Min = 0 and then Result.Height = 5,
                "restrict: a removed border shrinks the rectangle");
         KR.Destroy (Result, Status);

         --  Offsets at the ends of Int32 lay the mask over no pixel.
         KR.Restrict_To_Mask
           (Region, Mask, K.Int32'Last, K.Int32'First, Result, Status);
         Check (K.Succeeded (Status) and then Count_Of (Result) = 35
                and then Result.Flags = null,
                "restrict: extreme offsets cover nothing");
         KR.Destroy (Result, Status);
         KR.Restrict_To_Mask
           (Region, Mask, K.Int32'First, K.Int32'Last, Result, Status);
         Check (K.Succeeded (Status) and then Count_Of (Result) = 35,
                "restrict: extreme offsets the other way cover nothing");
         KR.Destroy (Result, Status);
         KI.Destroy (Mask, S);

         --  A mask of 0 over every pixel: the empty region.
         KI.Create (7, 5, 0, Mask, S);
         KR.Restrict_To_Mask (Region, Mask, 0, 0, Result, Status);
         Check (K.Succeeded (Status) and then Result = null,
                "restrict: nothing kept gives null");
         KI.Destroy (Mask, S);
         KR.Destroy (Region, Status);
      end;

      Section ("regions kernel: stream helpers");
      declare
         Reader : KR.Ks_Region_Reader;
         Bytes  : constant KR.Byte_Array (1 .. 10) := [others => 1];
      begin
         --  About 2.1E9 pixels announced: the reader allocates only for
         --  the elements that arrive.
         KR.Read_Header
           (Header (0, 0, 46_000, 46_000, 1), Reader, Status);
         Check (K.Succeeded (Status) and then Reader /= null
                and then Reader.Total = 46_000 * 46_000
                and then Reader.Buffer = null, "a huge header");
         KR.Put_Read_Bytes (Reader, Bytes, Status);
         Check (K.Succeeded (Status) and then Reader.Filled = 10
                and then Reader.Buffer'Length = 65_536,
                "the buffer grows with the elements read");
         KR.Finish_Read (Reader, Region, Status);
         Check (Status.Failure = K.Failure_Bad_Parameter
                and then Reader = null and then Region = null,
                "finishing before every element arrived fails");

         KR.Read_Header (Header (2, 3, 2, 2, 3), Reader, Status);
         KR.Put_Read_Bytes (Reader, [1, 2, 0, 1], Status);
         Check (Status.Failure = K.Failure_Image_File
                and then Message (Status)
                           = "Pixel_Region'Read: a pixel element is neither "
                             & "0 nor 1", "an element other than 0 and 1");
         KR.Destroy_Reader (Reader);
         Check (Reader = null, "the reader is freed");

         KR.Read_Header (Header (2, 3, 2, 2, 3), Reader, Status);
         KR.Put_Read_Bytes (Reader, [1, 1, 0, 1], Status);
         KR.Finish_Read (Reader, Region, Status);
         Check (K.Succeeded (Status) and then Count_Of (Region) = 3
                and then KR.Contains (Region, 2, 3)
                and then not KR.Contains (Region, 2, 4)
                and then KR.Contains (Region, 3, 4),
                "a region read back from its elements");
         declare
            Head     : KR.Header_Bytes;
            Position : KR.Flag_Position;
            Length   : Natural;
            Out_4    : KR.Byte_Array (1 .. 4);
         begin
            KR.Stream_Header (Region, Head, Status);
            Check (Head = Header (2, 3, 2, 2, 3), "the header written");
            KR.Next_Write_Chunk (Region, Position, 3, Length);
            Check (Length = 3, "the first chunk");
            KR.Get_Flag_Bytes (Region, Position, Out_4, Status);
            Check (K.Succeeded (Status) and then Out_4 = [1, 1, 0, 1],
                   "the elements written");
            KR.Get_Flag_Bytes (Region, Position, Out_4 (1 .. 1), Status);
            Check (Status.Failure = K.Failure_Bad_Parameter,
                   "no element past the end");
         end;
         KR.Destroy (Region, Status);
      end;

      Section ("regions kernel: AMV.Regions and region types");
      declare
         Image : constant AMV.Images.Ks_Image_8_Grey :=
           AMV.Images.Create (12, 12);
         Odd   : Odd_Regions.Odd_Region;
         Plain : Odd_Regions.Plain_Circle;
         Disc  : AMV.Shapes.Ks_Circle;
      begin
         Disc.Set_Center_Radius (6.0, 6.0, 3.0);
         Plain.Set_Center_Radius (6.0, 6.0, 3.0);
         Check (AMV.Regions.Rasterize (Image, Plain).Pixel_Count
                  = AMV.Regions.Rasterize (Image, Disc).Pixel_Count
                and then AMV.Regions.Rasterize (Image, Disc).Pixel_Count = 29,
                "a type derived from Ks_Circle is rasterised as a circle");
         begin
            declare
               R : constant AMV.Regions.Pixel_Region :=
                 AMV.Regions.Rasterize (Image, Odd);
            begin
               Fail ("a foreign region type: no exception ("
                     & Natural'Image (R.Pixel_Count) & " pixels)");
            end;
         exception
            when E : Ks_Bad_Parameter_Exception =>
               Check (Ada.Exceptions.Exception_Message (E)
                        = "Rasterize: the region must be a Ks_Rectangle, "
                          & "Ks_Rectangle_Affine, Ks_Circle, Ks_Ellipse, "
                          & "Ks_Polygon or Ks_Circular_Annulus_Section",
                      "a foreign region type is rejected");
         end;
      end;
   end Test_Regions_Kernel;

   ---------------------------------------------------------------------
   --  Real images (AMV.Kernels.Image_Math)
   ---------------------------------------------------------------------

   procedure Test_Image_Math_Kernel is
      package KR renames AMV.Kernels.Image_Math;
      use type KR.Ks_Real_Image;
      use type KR.Real_Values_Access;
      use type KR.U32;
      use type KR.U64;
      use type K.Int64;

      NaN      : constant Real := Zero / Zero;
      Infinity : constant Real := 1.0 / Zero;
      Status   : K.Ks_Status;
      Image    : KR.Ks_Real_Image;
      Result   : KR.Ks_Real_Image;
      Value    : Real;
      Flag     : K.Int32;
      Done     : Boolean;

      function Message return String is
        (String (Status.Message (1 .. Natural (Status.Length))));

      function Succeeded return Boolean is
        (Status.Failure = K.Failure_None);

      function Failed (Code : K.Int32; Text : String) return Boolean is
        (Status.Failure = Code and then Message = Text);

      function To_Bits is new Ada.Unchecked_Conversion (Real, KR.U64);
   begin
      Section ("image math kernel: values and coordinates");
      KR.Create (2, 2, NaN, Image, Status);
      Check (Failed (K.Failure_Bad_Parameter,
                     "Create: Value must be finite and within +/-1.0E100")
             and then Image = null,
             "Create rejects a NaN value");
      KR.Create (2, 2, Infinity, Image, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Image = null,
             "Create rejects an infinite value");
      KR.Create (-1, 2, 0.0, Image, Status);
      Check (Failed (K.Failure_Bad_Parameter,
                     "Create: Width and Height must be >= 0 (-1 x 2 given)"),
             "Create rejects a negative width");
      KR.Create (3, 2, 1.0E100, Image, Status);
      Check (Succeeded and then KR.Valid_Image (Image),
             "Create accepts the bound itself");
      KR.Fill (Image, -NaN, Status);
      Check (Failed (K.Failure_Bad_Parameter,
                     "Fill: Value must be finite and within +/-1.0E100"),
             "Fill rejects NaN");
      KR.Bilinear (Image, 0.5, Infinity, Value, Status);
      Check (Failed (K.Failure_Bad_Parameter, "Bilinear: Y must be finite")
             and then Value = 0.0,
             "Bilinear rejects an infinite coordinate");
      KR.Bilinear (Image, -1.0E300, 1.0E300, Value, Status);
      Check (Succeeded and then Value = 1.0E100,
             "Bilinear clamps any finite coordinate to the image");
      KR.Is_Inside (Image, NaN, 0.0, Flag, Status);
      Check (Failed (K.Failure_Bad_Parameter, "Is_Inside: X must be finite")
             and then Flag = K.False_Value,
             "Is_Inside rejects NaN");
      KR.Gaussian_Smooth (Image, -Infinity, Result, Status);
      Check (Status.Failure = K.Failure_Bad_Parameter and then Result = null,
             "Gaussian_Smooth rejects an infinite Sigma");
      KR.Gaussian_Smooth (Image, 2.0E6, Result, Status);
      Check (Failed (K.Failure_Bad_Parameter,
                     "Gaussian_Smooth: Sigma must not exceed Max_Sigma"),
             "Gaussian_Smooth rejects Sigma above Max_Sigma");
      KR.Box_Smooth (Image, 1, Result, Status);
      KR.Get_Pixel (Result, 1, 1, Value, Status);
      Check (Succeeded and then Value = 1.0E100,
             "a filter of values at the bound stays within it");
      KR.Destroy (Result, Status);

      Section ("image math kernel: lean pixel access");
      KR.Try_Set_Pixel (Image, 1, 0, 2.5, Done);
      KR.Try_Get_Pixel (Image, 1, 0, Value, Done);
      Check (Done and then Value = 2.5, "Try_Set_Pixel then Try_Get_Pixel");
      KR.Try_Set_Pixel (Image, 1, 0, NaN, Done);
      KR.Try_Get_Pixel (Image, 1, 0, Value, Done);
      Check (Done and then Value = 2.5,
             "Try_Set_Pixel of NaN does nothing");
      KR.Try_Get_Pixel (Image, 3, 0, Value, Done);
      Check (not Done and then Value = 0.0, "Try_Get_Pixel outside");
      KR.Try_Get_Pixel (null, 0, 0, Value, Done);
      Check (not Done, "Try_Get_Pixel of the empty image");
      KR.Set_Pixel (Image, 1, 0, 1.0E101, Status);
      Check (Failed (K.Failure_Bad_Parameter,
                     "Set: Value must be finite and within +/-1.0E100"),
             "Set_Pixel beyond the bound");
      KR.Set_Pixel (null, 0, 0, 1.0, Status);
      Check (Failed (K.Failure_Index_Out_Of_Range,
                     "Set: pixel (0, 0) is outside the 0 x 0 image"),
             "Set_Pixel of the empty image");
      KR.Destroy (Image, Status);
      Check (Succeeded and then Image = null, "Destroy sets null");

      Section ("image math kernel: stream helpers");
      declare
         State  : KR.Read_State;
         Length : Natural;
         Bits   : KR.Bits_Array (1 .. 3);
         Chunks : Natural := 0;
      begin
         KR.Check_Read_Code (KR.Code_Real_Image + 1, Status);
         Check (Failed (K.Failure_Image_File, "Real_Image'Read: the stream "
                                              & "does not hold a Real_Image"),
                "a wrong format code");
         KR.Start_Read (16#8000_0000#, 1, State, Status);
         Check (Failed (K.Failure_Image_File,
                        "Real_Image'Read: the size is too large"),
                "a width beyond Natural'Last");
         KR.Start_Read (65_536, 65_536, State, Status);
         Check (Failed (K.Failure_Image_File,
                        "Real_Image'Read: Width * Height is too large"),
                "a size beyond Max_Pixels");
         KR.Start_Read (3, 1, State, Status);
         KR.Next_Read_Chunk (State, 1024, Length, Status);
         Check (Succeeded and then Length = 3, "the first chunk");
         Bits := [To_Bits (1.0), To_Bits (NaN), To_Bits (2.0)];
         KR.Store_Bits (State, Bits, Status);
         Check (Failed (K.Failure_Image_File,
                        "Real_Image'Read: a pixel value is not finite"),
                "a NaN value read");
         KR.Abandon_Read (State);
         Check (State.Values = null, "Abandon_Read frees the values");
         KR.Start_Read (3, 1, State, Status);
         KR.Next_Read_Chunk (State, 1024, Length, Status);
         Bits := [To_Bits (1.0), To_Bits (1.0E200), To_Bits (2.0)];
         KR.Store_Bits (State, Bits, Status);
         Check (Failed (K.Failure_Image_File, "Real_Image'Read: a pixel "
                                              & "value is beyond +/-1.0E100"),
                "a value beyond the bound read");
         KR.Abandon_Read (State);
         --  More values than the first allocation: the room doubles as
         --  the values arrive.
         KR.Start_Read (100_000, 1, State, Status);
         Check (Succeeded and then State.Values'Length = 65_536,
                "the first allocation is limited");
         Bits := [To_Bits (1.0), To_Bits (1.0), To_Bits (2.0)];
         loop
            KR.Next_Read_Chunk (State, 3, Length, Status);
            exit when not Succeeded or else Length = 0;
            KR.Store_Bits (State, Bits (1 .. Length), Status);
            exit when not Succeeded;
            Chunks := Chunks + 1;
            Bits := [To_Bits (Real (Chunks)), To_Bits (1.0), To_Bits (2.0)];
         end loop;
         Check (Succeeded and then State.Filled = 100_000
                and then State.Values'Length = 100_000,
                "the room grows to the size read");
         KR.Finish_Read (State, Image, Status);
         KR.Get_Pixel (Image, 3, 0, Value, Status);
         Check (Succeeded and then Value = 1.0 and then State.Values = null,
                "Finish_Read builds the image");
         KR.Destroy (Image, Status);
         KR.Start_Read (2, 2, State, Status);
         KR.Finish_Read (State, Image, Status);
         Check (Failed (K.Failure_Bad_Parameter,
                        "Finish_Read: the image is not complete")
                and then Image = null and then State.Values = null,
                "Finish_Read of an incomplete image");
      end;
      declare
         Position : KR.Pixel_Position;
         Bits     : KR.Bits_Array (1 .. 3);
      begin
         KR.Create (2, 1, 0.5, Image, Status);
         KR.Get_Bits (Image, Position, Bits, Status);
         Check (Failed (K.Failure_Bad_Parameter,
                        "Get_Bits: the chunk is longer than the pixels left"),
                "Get_Bits beyond the end");
         KR.Get_Bits (Image, Position, Bits (1 .. 2), Status);
         Check (Succeeded and then Bits (2) = To_Bits (0.5)
                and then Position.Row = 1 and then Position.Column = 0,
                "Get_Bits of the whole image");
         KR.Destroy (Image, Status);
      end;
   end Test_Image_Math_Kernel;

   ---------------------------------------------------------------------
   --  Geometry (AMV.Kernels.Geometry)
   ---------------------------------------------------------------------

   procedure Test_Geometry_Kernel is
      package KG renames AMV.Kernels.Geometry;

      NaN      : constant Real := Zero / Zero;
      Infinity : constant Real := 1.0 / Zero;
      Status   : K.Ks_Status;
      Result   : Real;
      Point    : KG.Ks_Point_2D;
      Flag     : K.Int32;
      Line     : KG.Ks_Line_2D;
      Circle   : KG.Ks_Circle_2D;
      RMS      : Real;

      function Message return String is
        (String (Status.Message (1 .. Natural (Status.Length))));

      function Succeeded return Boolean is
        (Status.Failure = K.Failure_None);

      function Failed (Code : K.Int32; Text : String) return Boolean is
        (Status.Failure = Code and then Message = Text);
   begin
      Section ("geometry kernel: arguments and results");
      KG.Distance ((0.0, NaN), (0.0, 0.0), Result, Status);
      Check (Failed (K.Failure_Bad_Parameter,
                     "Distance: P.Y must be finite and within +/-1.0E150")
             and then Result = 0.0,
             "Distance rejects NaN");
      KG.Signed_Distance ((1.0, 2.0), (0.0, 0.0, Infinity), Result, Status);
      Check (Failed (K.Failure_Bad_Parameter,
                     "Signed_Distance: Line.Rotation must be finite"),
             "Signed_Distance rejects an infinite rotation");
      KG.Signed_Distance ((1.0, 2.0), (0.0, 0.0, 1.0E300), Result, Status);
      Check (Succeeded and then abs Result <= 3.0,
             "any finite rotation is accepted");
      KG.Angle_Between ((0.0, 0.0, 1.0E308), (0.0, 0.0, -1.0E308), Result,
                        Status);
      Check (Succeeded and then Result > -AMV.Misc.Pi
             and then Result <= AMV.Misc.Pi,
             "Angle_Between of huge rotations does not overflow");
      KG.Circle_Distance ((0.0, 0.0), (0.0, 0.0, 2.0E150), Result, Status);
      Check (Failed (K.Failure_Bad_Parameter,
                     "Distance: Circle.Radius must be finite and within "
                     & "+/-1.0E150"),
             "a radius beyond the bound");
      --  Nearly parallel lines far from the origin meet beyond the bound.
      KG.Intersect_Lines ((1.0E149, 0.0, 0.0), (-1.0E149, 1.0E149, 1.0E-11),
                          Point, Flag, Status);
      Check (Failed (K.Failure_Bad_Parameter,
                     "Intersect: the result would exceed +/-1.0E150")
             and then Point.X = 0.0 and then Flag = K.False_Value,
             "an intersection beyond the bound");
      KG.Intersect_Lines ((0.0, 0.0, 0.0), (0.0, 1.0, 1.0E-13), Point, Flag,
                          Status);
      Check (Succeeded and then Flag = K.True_Value,
             "nearly parallel lines");

      Section ("geometry kernel: fits");
      declare
         Points : KG.Point_Array (5 .. 7) :=
           [(0.0, 0.0), (1.0, 0.5), (2.0, NaN)];
         Used   : KG.Flag_Array (5 .. 7);
         Wrong  : KG.Flag_Array (0 .. 2);
      begin
         KG.Fit_Line (Points, Line, RMS, Status);
         Check (Failed (K.Failure_Bad_Parameter,
                        "Fit_Line: Points (7) must be finite and within "
                        & "+/-1.0E150")
                and then RMS = 0.0,
                "Fit_Line names the point that is not finite");
         Points (7) := (2.0, 1.0);
         KG.Fit_Line_Robust (Points, -1, Line, RMS, Used, Status);
         Check (Failed (K.Failure_Bad_Parameter,
                        "Fit_Line: Num_To_Ignore must be >= 0"),
                "a negative Num_To_Ignore");
         KG.Fit_Line_Robust (Points, 0, Line, RMS, Wrong, Status);
         Check (Failed (K.Failure_Bad_Parameter,
                        "Fit_Line: Used must have the same index range as "
                        & "Points"),
                "Used with other bounds");
         KG.Fit_Line_Robust (Points, 1, Line, RMS, Used, Status);
         Check (Succeeded and then not Used (5) and then Used (6)
                and then Used (7) and then RMS <= 1.0E-15,
                "a robust line fit of three collinear points (a tie: the "
                & "lowest index is dropped)");
         KG.Fit_Circle (Points, Circle, RMS, Status);
         Check (Failed (K.Failure_Bad_Parameter,
                        "Fit_Circle: the points are collinear"),
                "Fit_Circle of collinear points");
      end;
      --  Subnormal coordinates: the scaling by powers of two still finds
      --  the direction.
      declare
         Tiny   : constant Real := Real'Value ("1.0E-310");
         --  Read at run time: a subnormal literal draws a warning.
         Points : constant KG.Point_Array :=
           [(0.0, 0.0), (2.0 * Tiny, Tiny), (4.0 * Tiny, 2.0 * Tiny)];
      begin
         KG.Fit_Line (Points, Line, RMS, Status);
         Check (Succeeded
                and then abs (Line.Rotation - 0.463_647_609) <= 1.0E-3,
                "a line through subnormal points");
      end;
      KG.Fit_Line_C (System.Null_Address, 3, Line, RMS, Status);
      Check (Failed (K.Failure_Bad_Parameter,
                     "Fit_Line: Points must not be null"),
             "the C fit checks its pointer");
      KG.Fit_Circle_C (System.Null_Address, -1, Circle, RMS, Status);
      Check (Failed (K.Failure_Bad_Parameter, "Fit_Circle: Count must be >= 0"),
             "the C fit checks its count");
   end Test_Geometry_Kernel;

   procedure Run_All is
   begin
      Test_Status;
      AMV.Test_Check_Mapping;
      Test_Misc_Non_Finite;
      Test_Misc_Extremes;
      Test_Entry_Points;
      Test_Transforms_Kernel;
      Test_Coordinate_Spaces_Kernel;
      Test_Images_Kernel;
      Test_Image_File_Kernel;
      Test_Shapes_Kernel;
      Test_Regions_Kernel;
      Test_Image_Math_Kernel;
      Test_Geometry_Kernel;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Kernels;
