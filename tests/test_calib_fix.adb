--  Tests for AMV.Calib_Fix (the fixture tools and the calibrations of
--  Cognex.VisionPro.CalibFix) and its kernel AMV.Kernels.Calib_Fix.
--
--  The fits are checked on points made from known transforms of every
--  DOF (exact recovery without noise, an RMS error of the order of the
--  noise with it), the fixture tools on the trees and selections of their
--  output images and on a point measured before and after, the
--  calibrations on known pixel sizes, rotations and aspects, the
--  checkerboard calibration on AMV_Test_Images.Checkerboard renders whose
--  corners are known exactly and on finite boards (Draw_Board) with plain
--  margins, under perspective and beside clutter, where every corner must
--  be an inner corner of the board, each once. The nonlinear mode
--  (Perspective_And_Radial_Warp) is checked on boards rendered through a
--  known homography and known barrel or pincushion distortion (the
--  recovered coefficients, the RMS error, the model against the true
--  corners), on its warped output (the corners found again there lie on
--  a regular grid and on the calibrated lattice), and on its streams (both
--  layouts, an old one written by hand). The same mode of an N-point
--  calibration is checked on pairs made from a known homography and lens
--  (exact recovery of the model and of its maps without noise, the RMS
--  error of the noise with it, the warped output, the selected space of
--  the calibration image, the origin adjustment, the mode, too few and
--  degenerate points, streams), on the corners of a checkerboard (the
--  checkerboard's model exactly) and against the checkerboard's model
--  before the fit was generalised. The origin adjustment is checked
--  on the geometry of the calibrated space (the origin and the x axis
--  where they are asked to be, in raw calibrated space and in the
--  uncalibrated space under a fit with an aspect and a skew, a rigid map
--  from the raw calibrated space, a mirrored one when swapped), on the
--  tools' output spaces, on its streams and on its restriction in the
--  warp mode. The kernel is called directly for what the Ada API cannot
--  reach (null handles, bad codes, non-finite values, limits).

pragma Validity_Checks ("F");

with Ada.Calendar;
with Ada.Exceptions;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Streams.Storage.Unbounded;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;

with AMV;                          use AMV;
with AMV.Calib_Fix;                use AMV.Calib_Fix;
with AMV.Coordinate_Spaces;        use AMV.Coordinate_Spaces;
with AMV.Images;                   use AMV.Images;
with AMV.Images.Kernel_Images;
with AMV.Kernels;
with AMV.Kernels.Calib_Fix;
with AMV.Kernels.Coordinate_Spaces;
with AMV.Kernels.Images;
with AMV.Kernels.Transforms;
with AMV.Tools;                    use AMV.Tools;
with AMV.Transforms;               use AMV.Transforms;
with AMV_Test_Images;
with AMV_Test_Support;             use AMV_Test_Support;

procedure Test_Calib_Fix is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package K renames AMV.Kernels;
   package KF renames AMV.Kernels.Calib_Fix;
   package KC renames AMV.Kernels.Coordinate_Spaces;
   package KI renames AMV.Kernels.Images;
   package KT renames AMV.Kernels.Transforms;

   use type K.Int32;
   use type KF.Ks_Point_Pairs;
   use type KF.Ks_Calibration;
   use type KF.Ks_Radial_Warp_Model;
   use type KF.Ks_Calibration_Adjustment;
   use type KI.Ks_Image_8_Grey;
   use type Ada.Streams.Stream_Element_Offset;
   use type KT.Ks_Transform_2D_Linear;
   use type K.Message_Text;
   use type Interfaces.Unsigned_8;

   Pi : constant := Ada.Numerics.Pi;

   Zero : constant Real := Real'Value ("0.0");
   NaN  : constant Real := Zero / Zero;
   Inf  : constant Real := 1.0 / Zero;

   Id : constant KT.Ks_Transform_2D_Linear := (others => <>);

   ---------------------------------------------------------------------
   --  Helpers
   ---------------------------------------------------------------------

   function Deg (Degrees : Real) return Real is (Degrees * Pi / 180.0);

   function Kernel_Of (T : AMV.Transforms.Ks_Transform_2D_Linear)
      return KT.Ks_Transform_2D_Linear
   is
      R : KT.Ks_Transform_2D_Linear;
   begin
      T.Get_Matrix_Elements_Translation
        (R.A, R.B, R.C, R.D, R.Translation_X, R.Translation_Y);
      return R;
   end Kernel_Of;

   procedure Check_Transform
     (Actual    : AMV.Transforms.Ks_Transform_2D_Linear;
      Expected  : KT.Ks_Transform_2D_Linear;
      Tolerance : Real;
      What      : String)
   is
      R : constant KT.Ks_Transform_2D_Linear := Kernel_Of (Actual);
   begin
      Check_Near (R.A, Expected.A, Tolerance, What & ": A");
      Check_Near (R.B, Expected.B, Tolerance, What & ": B");
      Check_Near (R.C, Expected.C, Tolerance, What & ": C");
      Check_Near (R.D, Expected.D, Tolerance, What & ": D");
      Check_Near (R.Translation_X, Expected.Translation_X,
                  Tolerance * 100.0, What & ": translation X");
      Check_Near (R.Translation_Y, Expected.Translation_Y,
                  Tolerance * 100.0, What & ": translation Y");
   end Check_Transform;

   function Make
     (Scaling_X, Scaling_Y, Rotation, Skew, Tx, Ty : Real)
      return KT.Ks_Transform_2D_Linear
   is
      --  Columns Sx (cos R, sin R) and Sy (-sin (R + Skew), cos (R +
      --  Skew)).
   begin
      return (A => Scaling_X * EF.Cos (Rotation),
              B => -Scaling_Y * EF.Sin (Rotation + Skew),
              C => Scaling_X * EF.Sin (Rotation),
              D => Scaling_Y * EF.Cos (Rotation + Skew),
              Translation_X => Tx, Translation_Y => Ty);
   end Make;

   procedure Map
     (T    : KT.Ks_Transform_2D_Linear;
      X, Y : Real;
      U, V : out Real) is
   begin
      U := T.A * X + T.B * Y + T.Translation_X;
      V := T.C * X + T.D * Y + T.Translation_Y;
   end Map;

   Seed : Interfaces.Unsigned_32 := 12345;

   function Noise (Amplitude : Real) return Real is
      --  A deterministic value in [-Amplitude, Amplitude].
      use type Interfaces.Unsigned_32;
   begin
      Seed := Seed * 1103515245 + 12345;
      return Amplitude * (2.0 * Real (Seed) / 4294967296.0 - 1.0);
   end Noise;

   procedure Noisy_Point (X, Y, Amplitude : Real; Nx, Ny : out Real) is
   begin
      Nx := X + Noise (Amplitude);
      Ny := Y + Noise (Amplitude);
   end Noisy_Point;
   --  (X, Y) with noise, drawn for X first. The language leaves the order
   --  of two calls of Noise in one parameter list to the compiler, and it
   --  differs between targets: the data of the tests would differ with it.

   --  Twelve group B points spread over a plane (not collinear).
   type Point_List is array (Positive range <>) of Real;
   B_X : constant Point_List :=
     [-40.0, -10.0, 25.0, 60.0, -55.0, 5.0, 33.0, 71.0, -20.0, 12.0, 47.0,
      -3.0];
   B_Y : constant Point_List :=
     [-30.0, -45.0, -25.0, -40.0, 10.0, 0.0, 15.0, 5.0, 40.0, 55.0, 35.0,
      22.0];

   function Pairs_For
     (T           : KT.Ks_Transform_2D_Linear;
      Count       : Positive := 12;
      Noise_Level : Real := 0.0) return Ks_N_Point_To_N_Point
   is
      U, V, Nu, Nv : Real;
   begin
      return P : Ks_N_Point_To_N_Point do
         for I in 1 .. Count loop
            Map (T, B_X (I), B_Y (I), U, V);
            Noisy_Point (U, V, Noise_Level, Nu, Nv);
            P.Add_Point_Pair (Nu, Nv, B_X (I), B_Y (I));
         end loop;
      end return;
   end Pairs_For;

   function Has_Space (Image : Ks_Image'Class; Name : String) return Boolean
   is (Image.Get_Coordinate_Space_Tree.Space_Exists (Name));

   ---------------------------------------------------------------------
   --  The fits
   ---------------------------------------------------------------------

   procedure Test_Fits is
      RMS : Real;
      F   : AMV.Transforms.Ks_Transform_2D_Linear;

      procedure Exact
        (DOF  : Ks_N_Point_To_N_Point_DOF_Constants;
         T    : KT.Ks_Transform_2D_Linear;
         What : String)
      is
         P : Ks_N_Point_To_N_Point := Pairs_For (T);
      begin
         P.Set_DOFs_To_Compute (DOF);
         F := P.Compute_Group_A_From_Group_B_Transform (RMS);
         Check_Transform (F, T, 1.0E-10, What);
         Check (RMS >= 0.0 and then RMS < 1.0E-9, What & ": RMS 0");
      end Exact;

      procedure Noisy
        (DOF  : Ks_N_Point_To_N_Point_DOF_Constants;
         T    : KT.Ks_Transform_2D_Linear;
         What : String)
      is
         P : Ks_N_Point_To_N_Point := Pairs_For (T, Noise_Level => 0.05);
      begin
         P.Set_DOFs_To_Compute (DOF);
         F := P.Compute_Group_A_From_Group_B_Transform (RMS);
         Check_Transform (F, T, 2.0E-3, What & " with noise");
         --  Uniform noise of +/-0.05 per coordinate has an RMS distance of
         --  about 0.05 * sqrt (2/3) = 0.041, a little less after the fit.
         Check (RMS > 0.015 and then RMS < 0.06,
                What & " with noise: RMS of the order of the noise"
                & RMS'Image);
      end Noisy;

      Rigid      : constant KT.Ks_Transform_2D_Linear :=
        Make (1.0, 1.0, 0.7, 0.0, 12.5, -7.25);
      Similarity : constant KT.Ks_Transform_2D_Linear :=
        Make (2.5, 2.5, -2.2, 0.0, -100.0, 40.0);
      Aspect     : constant KT.Ks_Transform_2D_Linear :=
        Make (1.5, 3.0, 0.4, 0.0, 5.0, 6.0);
      Mirror     : constant KT.Ks_Transform_2D_Linear :=
        Make (2.0, -0.5, 2.9, 0.0, 1.0, 2.0);
      Affine     : constant KT.Ks_Transform_2D_Linear :=
        Make (1.2, 0.8, 0.3, 0.25, 30.0, -20.0);
   begin
      Section ("Fits: exact recovery");
      Exact (Translation, (Translation_X => 3.5, Translation_Y => -2.0,
                           others => <>), "translation");
      Exact (Rotation_And_Translation, Rigid, "rigid");
      Exact (Scaling_Rotation_And_Translation, Similarity, "similarity");
      Exact (Scaling_Aspect_Rotation_And_Translation, Aspect, "aspect");
      Exact (Scaling_Aspect_Rotation_And_Translation, Mirror,
             "aspect, mirrored");
      Exact (Scaling_Aspect_Rotation_Skew_And_Translation, Affine, "affine");
      Exact (Scaling_Aspect_Rotation_Skew_And_Translation, Mirror,
             "affine, mirrored");

      Section ("Fits: noise");
      Noisy (Rotation_And_Translation, Rigid, "rigid");
      Noisy (Scaling_Rotation_And_Translation, Similarity, "similarity");
      Noisy (Scaling_Aspect_Rotation_And_Translation, Aspect, "aspect");
      Noisy (Scaling_Aspect_Rotation_Skew_And_Translation, Affine, "affine");

      Section ("Fits: translations along one axis and none");
      declare
         T : constant KT.Ks_Transform_2D_Linear :=
           (Translation_X => 4.0, Translation_Y => 9.0, others => <>);
         P : Ks_N_Point_To_N_Point := Pairs_For (T);
      begin
         P.Set_DOFs_To_Compute (Translation_X);
         F := P.Compute_Group_A_From_Group_B_Transform (RMS);
         Check_Transform
           (F, (Translation_X => 4.0, others => <>), 1.0E-12, "x only");
         Check_Near (RMS, 9.0, 1.0E-9, "x only: RMS is the y shift");
         P.Set_DOFs_To_Compute (Translation_Y);
         F := P.Compute_Group_A_From_Group_B_Transform (RMS);
         Check_Transform
           (F, (Translation_Y => 9.0, others => <>), 1.0E-12, "y only");
         Check_Near (RMS, 4.0, 1.0E-9, "y only: RMS is the x shift");
         P.Set_DOFs_To_Compute (None);
         F := P.Compute_Group_A_From_Group_B_Transform (RMS);
         Check (Kernel_Of (F) = Id, "none: the identity");
         Check_Near (RMS, EF.Sqrt (97.0), 1.0E-9, "none: RMS of the shifts");
      end;

      Section ("Fits: structure of each DOF");
      declare
         P : Ks_N_Point_To_N_Point := Pairs_For (Affine, Noise_Level => 0.5);
         R : KT.Ks_Transform_2D_Linear;
      begin
         P.Set_DOFs_To_Compute (Translation);
         R := Kernel_Of (P.Compute_Group_A_From_Group_B_Transform);
         Check (R.A = 1.0 and then R.B = 0.0 and then R.C = 0.0
                and then R.D = 1.0, "translation: unit matrix");
         P.Set_DOFs_To_Compute (Rotation_And_Translation);
         R := Kernel_Of (P.Compute_Group_A_From_Group_B_Transform);
         Check (R.A = R.D and then R.B = -R.C
                and then abs (R.A * R.A + R.C * R.C - 1.0) < 1.0E-15,
                "rigid: rotation matrix");
         P.Set_DOFs_To_Compute (Scaling_Rotation_And_Translation);
         R := Kernel_Of (P.Compute_Group_A_From_Group_B_Transform);
         Check (R.A = R.D and then R.B = -R.C, "similarity: equal scales");
         P.Set_DOFs_To_Compute (Scaling_Aspect_Rotation_And_Translation);
         R := Kernel_Of (P.Compute_Group_A_From_Group_B_Transform);
         Check (abs (R.A * R.B + R.C * R.D) < 1.0E-12,
                "aspect: orthogonal columns");
      end;

      Section ("Fits: the aspect fit is a least squares optimum");
      declare
         P     : Ks_N_Point_To_N_Point := Pairs_For (Affine);
         Best  : Real;
         Other : Real;
         Fit   : KT.Ks_Transform_2D_Linear;

         function Cost (T : KT.Ks_Transform_2D_Linear) return Real is
            U, V, A_X, A_Y : Real;
            Sum            : Real := 0.0;
         begin
            for I in 1 .. 12 loop
               Map (T, B_X (I), B_Y (I), U, V);
               P.Get_Group_A_Point (I - 1, A_X, A_Y);
               Sum := Sum + (U - A_X) ** 2 + (V - A_Y) ** 2;
            end loop;
            return Sum;
         end Cost;

         Sx, Sy, R, Tx, Ty : Real;
      begin
         P.Set_DOFs_To_Compute (Scaling_Aspect_Rotation_And_Translation);
         Fit := Kernel_Of (P.Compute_Group_A_From_Group_B_Transform);
         Best := Cost (Fit);
         Sx := EF.Sqrt (Fit.A ** 2 + Fit.C ** 2);
         Sy := EF.Sqrt (Fit.B ** 2 + Fit.D ** 2);
         R := EF.Arctan (Fit.C, Fit.A);
         Tx := Fit.Translation_X;
         Ty := Fit.Translation_Y;
         --  Small changes of each parameter do not lower the cost.
         for Delta_Value of Point_List'[1.0E-3, -1.0E-3] loop
            Other := Real'Min
              (Real'Min (Cost (Make (Sx + Delta_Value, Sy, R, 0.0, Tx, Ty)),
                         Cost (Make (Sx, Sy + Delta_Value, R, 0.0, Tx, Ty))),
               Real'Min (Cost (Make (Sx, Sy, R + Delta_Value, 0.0, Tx, Ty)),
                         Cost (Make (Sx, Sy, R, 0.0, Tx + Delta_Value, Ty))));
            Check (Other >= Best - 1.0E-6, "no better aspect fit nearby");
         end loop;
      end;

      Section ("Fits: scale invariance");
      declare
         Big   : constant KT.Ks_Transform_2D_Linear :=
           Make (3.0E120, 2.0E120, 0.5, 0.0, 1.0E122, -2.0E122);
         Tiny  : constant KT.Ks_Transform_2D_Linear :=
           Make (1.0E-80, 1.0E-80, -1.0, 0.0, 1.0E-75, 0.0);
         P     : Ks_N_Point_To_N_Point := Pairs_For (Big);
         R     : KT.Ks_Transform_2D_Linear;
      begin
         P.Set_DOFs_To_Compute (Scaling_Aspect_Rotation_Skew_And_Translation);
         R := Kernel_Of (P.Compute_Group_A_From_Group_B_Transform (RMS));
         Check (abs (R.A / Big.A - 1.0) < 1.0E-9
                and then abs (R.D / Big.D - 1.0) < 1.0E-9,
                "huge scale recovered");
         P := Pairs_For (Tiny);
         P.Set_DOFs_To_Compute (Scaling_Rotation_And_Translation);
         R := Kernel_Of (P.Compute_Group_A_From_Group_B_Transform (RMS));
         Check (abs (R.A / Tiny.A - 1.0) < 1.0E-9
                and then abs (R.C / Tiny.C - 1.0) < 1.0E-9,
                "tiny scale recovered");
      end;
   end Test_Fits;

   procedure Test_Fit_Failures is
      procedure Expect_Bad
        (P    : Ks_N_Point_To_N_Point;
         What : String)
      is
      begin
         declare
            F : constant AMV.Transforms.Ks_Transform_2D_Linear :=
              P.Compute_Group_A_From_Group_B_Transform;
         begin
            Fail (What & ": no exception" & F.Rotation'Image);
         end;
      exception
         when AMV.Ks_Bad_Parameter_Exception =>
            Check (True, What);
         when E : others =>
            Fail (What & ": " & Ada.Exceptions.Exception_Name (E));
      end Expect_Bad;

      Rigid : constant KT.Ks_Transform_2D_Linear :=
        Make (1.0, 1.0, 0.7, 0.0, 12.5, -7.25);
      P     : Ks_N_Point_To_N_Point;
   begin
      Section ("Fits: minimum point counts");
      P.Set_DOFs_To_Compute (Translation);
      Expect_Bad (P, "translation without points");
      P := Pairs_For (Rigid, 1);
      P.Set_DOFs_To_Compute (Translation);
      Check (P.Num_Points = 1, "one pair");
      Check_Near (Kernel_Of (P.Compute_Group_A_From_Group_B_Transform)
                    .Translation_X,
                  Rigid.Translation_X + Rigid.A * B_X (1) + Rigid.B * B_Y (1)
                  - B_X (1), 1.0E-9, "translation from one pair");
      P.Set_DOFs_To_Compute (Rotation_And_Translation);
      Expect_Bad (P, "rigid with one pair");
      P.Set_DOFs_To_Compute (Scaling_Rotation_And_Translation);
      Expect_Bad (P, "similarity with one pair");
      P := Pairs_For (Rigid, 2);
      P.Set_DOFs_To_Compute (Rotation_And_Translation);
      Check_Transform (P.Compute_Group_A_From_Group_B_Transform, Rigid,
                       1.0E-10, "rigid from two pairs");
      P.Set_DOFs_To_Compute (Scaling_Aspect_Rotation_And_Translation);
      Expect_Bad (P, "aspect with two pairs");
      P.Set_DOFs_To_Compute (Scaling_Aspect_Rotation_Skew_And_Translation);
      Expect_Bad (P, "affine with two pairs");
      P := Pairs_For (Rigid, 3);
      Check_Transform (P.Compute_Group_A_From_Group_B_Transform, Rigid,
                       1.0E-9, "affine from three pairs");

      Section ("Fits: degenerate points");
      P := Pairs_For (Rigid, 0 + 1);
      P.Add_Point_Pair (1.0, 1.0, B_X (1), B_Y (1));
      P.Set_DOFs_To_Compute (Rotation_And_Translation);
      Expect_Bad (P, "rigid: coincident B points");
      declare
         Line : Ks_N_Point_To_N_Point;
      begin
         for I in 1 .. 5 loop
            Line.Add_Point_Pair (Real (I), 2.0 * Real (I), Real (I),
                                 3.0 * Real (I));
         end loop;
         Line.Set_DOFs_To_Compute (Scaling_Aspect_Rotation_And_Translation);
         Expect_Bad (Line, "aspect: collinear B points");
         Line.Set_DOFs_To_Compute
           (Scaling_Aspect_Rotation_Skew_And_Translation);
         Expect_Bad (Line, "affine: collinear B points");
         Line.Set_DOFs_To_Compute (Scaling_Rotation_And_Translation);
         Check (Line.Compute_Group_A_From_Group_B_Transform.Scaling > 0.0,
                "similarity: collinear B points are enough");
      end;
      declare
         Same_A : Ks_N_Point_To_N_Point;
      begin
         for I in 1 .. 5 loop
            Same_A.Add_Point_Pair (7.0, 7.0, B_X (I), B_Y (I));
         end loop;
         Same_A.Set_DOFs_To_Compute (Scaling_Rotation_And_Translation);
         Expect_Bad (Same_A, "similarity: coincident A points (scale 0)");
         Same_A.Set_DOFs_To_Compute (Rotation_And_Translation);
         Check_Near (Same_A.Compute_Group_A_From_Group_B_Transform.Rotation,
                     0.0, 0.0, "rigid: coincident A points, rotation 0");
      end;

      Section ("Point pairs: access");
      P := Pairs_For (Rigid, 4);
      P.Set_Group_A_Point (1, 5.0, 6.0);
      Check (P.Get_Group_A_Point_X (1) = 5.0
             and then P.Get_Group_A_Point_Y (1) = 6.0, "set group A point");
      P.Set_Group_B_Point (2, -5.0, -6.0);
      Check (P.Get_Group_B_Point_X (2) = -5.0
             and then P.Get_Group_B_Point_Y (2) = -6.0, "set group B point");
      P.Delete_Point_Pair (0);
      Check (P.Num_Points = 3 and then P.Get_Group_A_Point_X (0) = 5.0,
             "delete moves the later pairs down");
      declare
         Copy : Ks_N_Point_To_N_Point := P;
      begin
         Copy.Delete_Point_Pair (0);
         Check (Copy.Num_Points = 2 and then P.Num_Points = 3,
                "copies are independent");
      end;
      begin
         P.Delete_Point_Pair (3);
         Fail ("delete beyond the end");
      exception
         when Constraint_Error =>
            Check (True, "delete beyond the end: Constraint_Error");
      end;
      begin
         P.Add_Point_Pair (NaN, 0.0, 0.0, 0.0);
         Fail ("NaN point");
      exception
         when AMV.Ks_Bad_Parameter_Exception =>
            Check (P.Num_Points = 3, "NaN point rejected, nothing added");
      end;

      Section ("Point pairs: streams");
      declare
         S    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Back : Ks_N_Point_To_N_Point;
      begin
         Ks_N_Point_To_N_Point'Write (S'Access, P);
         Ks_N_Point_To_N_Point'Read (S'Access, Back);
         Check (Back.Num_Points = 3
                and then Back.Get_Group_A_Point_X (0) = 5.0
                and then Back.Get_Group_B_Point_Y (1) = -6.0
                and then Back.DOFs_To_Compute = P.DOFs_To_Compute,
                "pairs read back");
      end;
   end Test_Fit_Failures;

   ---------------------------------------------------------------------
   --  The fixture tools
   ---------------------------------------------------------------------

   procedure Test_Fixture is
      Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (100, 80, 7);
      Tool  : Ks_Fixture_Tool;
      Pose  : constant AMV.Transforms.Ks_Transform_2D_Linear :=
        Create_Rigid (0.5, 20.0, 10.0);
      X, Y  : Real;
   begin
      Section ("Fixture: output tree and selection");
      Tool.Input_Image := Image;
      Tool.Run_Params.Unfixtured_From_Fixtured_Transform := Pose;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "run accepted");
      Check (Tool.Output_Image.Selected_Space_Name = "@\Fixture",
             "the fixtured space is selected");
      Check (Kernel_Of (Tool.Output_Image.Get_Coordinate_Space_Tree
                          .Parent_From_Child_Transform ("@\Fixture"))
             = Kernel_Of (Pose), "Parent_From_New is the pose, unchanged");
      Check (Tool.Input_Image.Selected_Space_Name = "@"
             and then not Has_Space (Tool.Input_Image, "@\Fixture"),
             "the input is unchanged");
      Image.Set_Pixel (3, 4, 200);
      Check (Tool.Output_Image.Get_Pixel (3, 4) = 200,
             "the output shares the input's pixels");

      Section ("Fixture: a point measured before and after");
      --  A feature at (5, -2) in the fixture's frame lies at Pose (5, -2)
      --  in the input's selected space (and pixel space, the identity).
      Map_Point (Tool.Output_Image.Get_Transform ("#", "."), 5.0, -2.0, X, Y);
      declare
         U, V : Real;
      begin
         Map (Kernel_Of (Pose), 5.0, -2.0, U, V);
         Check_Near (X, U, 1.0E-12, "fixtured point in pixels: X");
         Check_Near (Y, V, 1.0E-12, "fixtured point in pixels: Y");
      end;

      Section ("Fixture: under a selected space");
      Image.Coordinate_Space_Tree.Add_Space
        ("@", "Stage", Create_Similarity (2.0, 0.1, 3.0, 4.0));
      Image.Set_Selected_Space_Name ("@\Stage");
      Tool.Input_Image := Image;
      Tool.Run;
      Check (Tool.Output_Image.Selected_Space_Name = "@\Stage\Fixture",
             "added under the selected space");
      Check_Transform
        (Tool.Output_Image.Get_Transform ("@\Stage", "."), Kernel_Of (Pose),
         1.0E-12, "stage from fixture is the pose");

      Section ("Fixture: re-running replaces the space");
      Tool.Input_Image := Tool.Output_Image;
      Tool.Input_Image.Set_Selected_Space_Name ("@\Stage");
      Tool.Run_Params.Unfixtured_From_Fixtured_Transform :=
        Create_Rigid (-0.2, 1.0, 2.0);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Output_Image.Get_Coordinate_Space_Tree.Space_Count
                        = 3, "replaced, not added twice");
      Check_Transform
        (Tool.Output_Image.Get_Transform ("@\Stage", "@\Stage\Fixture"),
         Kernel_Of (Create_Rigid (-0.2, 1.0, 2.0)), 1.0E-12,
         "the new transform");
      Tool.Run_Params.Fixtured_Space_Name_Duplicate_Handling := Enhanced;
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name
                        = "AMV.KS_BAD_PARAMETER_EXCEPTION"
             and then not Tool.Output_Image.Allocated,
             "Enhanced: an existing space is an error");
      Tool.Run_Params.Fixtured_Space_Name_Duplicate_Handling := Compatibility;

      Section ("Fixture: SpaceToOutput unfixtured");
      Tool.Input_Image := Image;
      Tool.Run_Params.Space_To_Output := Unfixtured_Space;
      Tool.Run;
      Check (Tool.Output_Image.Selected_Space_Name = "@\Stage"
             and then Has_Space (Tool.Output_Image, "@\Stage\Fixture"),
             "added, selection kept");
      Tool.Run_Params.Space_To_Output := Fixtured_Space;

      Section ("Fixture: the input in pixel space");
      declare
         Pixel_Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (50, 40);
         Out_Image   : Ks_Image_8_Grey;
      begin
         Pixel_Image.Set_Pixel_From_Root_Transform
           (Create_Similarity (0.5, 0.3, 7.0, -1.0));
         Pixel_Image.Set_Selected_Space_Name ("#");
         Out_Image := Execute (Tool.Run_Params, Pixel_Image);
         Check (Out_Image.Selected_Space_Name = "@\Fixture",
                "pixel space: added under the root");
         Check_Transform
           (Out_Image.Get_Transform ("#", "."),
            Kernel_Of (Tool.Run_Params.Unfixtured_From_Fixtured_Transform),
            1.0E-9, "pixel from fixtured is the given transform");
         Tool.Run_Params.Space_To_Output := Unfixtured_Space;
         Out_Image := Execute (Tool.Run_Params, Pixel_Image);
         Check (Out_Image.Selected_Space_Name = "#",
                "pixel space with SpaceToOutput unfixtured stays #");
         Tool.Run_Params.Space_To_Output := Fixtured_Space;
      end;

      Section ("Fixture: failures");
      Tool.Run_Params.Fixtured_Space_Name :=
        Ada.Strings.Unbounded.To_Unbounded_String ("A\B");
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name
                        = "AMV.KS_BAD_PARAMETER_EXCEPTION"
             and then not Tool.Output_Image.Allocated, "a path is no name");
      Tool.Run_Params.Fixtured_Space_Name :=
        Ada.Strings.Unbounded.To_Unbounded_String ("");
      Tool.Run;
      Check (Tool.Run_Status.Result = Error, "an empty name");
      Tool.Run_Params.Fixtured_Space_Name :=
        Ada.Strings.Unbounded.To_Unbounded_String ("Fixture");
      Tool.Run_Params.Unfixtured_From_Fixtured_Transform :=
        AMV.Transforms.Create (1.0, 2.0, 2.0, 4.0, 0.0, 0.0);
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name
                        = "AMV.KS_TRANSFORM_SINGULAR_EXCEPTION",
             "a singular transform");
      Tool.Run_Params.Unfixtured_From_Fixtured_Transform :=
        AMV.Transforms.Create (1.0, 0.0, 0.0, 1.0, NaN, 0.0);
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name
                        = "AMV.KS_BAD_PARAMETER_EXCEPTION",
             "a NaN translation");
      Tool.Run_Params.Unfixtured_From_Fixtured_Transform := Pose;
      declare
         Unallocated : Ks_Image_8_Grey;
      begin
         Tool.Input_Image := Unallocated;
      end;
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name
                        = "AMV.KS_IMAGE_NO_PIXELS_EXCEPTION"
             and then Tool.Run_Status.Message = "InputImage has no pixels",
             "an unallocated input");
   end Test_Fixture;

   procedure Test_Fixture_N_Point is
      Tool : Ks_Fixture_N_Point_To_N_Point_Tool;
      Pose : constant KT.Ks_Transform_2D_Linear :=
        Make (1.0, 1.0, -0.4, 0.0, 33.0, 21.0);
      U, V : Real;
   begin
      Section ("N-point fixture");
      Check (Tool.Run_Params.DOFs_To_Compute = Rotation_And_Translation
             and then Tool.Run_Params.Fixtured_Space_Name = "N-Point Fixture",
             "VisionPro's defaults");
      Tool.Input_Image := AMV_Test_Images.Blank (64, 48);
      for I in 1 .. 4 loop
         Map (Pose, B_X (I), B_Y (I), U, V);
         Tool.Run_Params.Add_Point_Pair (U, V, B_X (I), B_Y (I));
      end loop;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "run accepted");
      Check_Transform
        (Tool.Result.Get_Unfixtured_From_Fixtured_Transform, Pose, 1.0E-12,
         "the fitted pose");
      Check (Tool.Result.RMS_Error < 1.0E-10, "RMS error 0");
      Check (Tool.Result.Output_Image.Selected_Space_Name
             = "@\N-Point Fixture", "the fixtured space is selected");
      Check_Transform
        (Tool.Result.Output_Image.Get_Transform ("@", "."), Pose, 1.0E-12,
         "root from fixtured is the pose");
      Check (Tool.Run_Params.Get_Unfixtured_Point_X (0) = Tool.Run_Params
               .Get_Unfixtured_Point_X (0)
             and then Tool.Run_Params.Get_Raw_Fixtured_Point_Y (3) = B_Y (4),
             "the points");
      Tool.Run_Params.Set_DOFs_To_Compute
        (Scaling_Aspect_Rotation_Skew_And_Translation);
      Tool.Run_Params.Delete_Point_Pair (0);
      Tool.Run_Params.Delete_Point_Pair (0);
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name
                        = "AMV.KS_BAD_PARAMETER_EXCEPTION"
             and then not Tool.Result.Output_Image.Allocated
             and then Tool.Result.RMS_Error = 0.0,
             "too few pairs: Error, empty result");
   end Test_Fixture_N_Point;

   ---------------------------------------------------------------------
   --  The N-point calibration
   ---------------------------------------------------------------------

   procedure Test_Calib_N_Point is
      --  A camera seeing a plate turned by 10 degrees with pixels of
      --  0.05 mm along x and 0.049 mm along y: uncalibrated (pixels) from
      --  calibrated (mm) scales by 20 and 20 / 0.98.
      Truth : constant KT.Ks_Transform_2D_Linear :=
        Make (20.0, 20.0 / 0.98, Deg (10.0), 0.0, 320.0, 240.0);
      Tool  : Ks_Calib_N_Point_To_N_Point_Tool;
      U, V  : Real;
   begin
      Section ("N-point calibration: calibrate");
      Check (not Tool.Calibration.Calibrated, "not calibrated at first");
      for I in 1 .. 9 loop
         Map (Truth, B_X (I) / 10.0, B_Y (I) / 10.0, U, V);
         Tool.Calibration.Add_Point_Pair (U, V, B_X (I) / 10.0,
                                          B_Y (I) / 10.0);
      end loop;
      Tool.Calibration.Set_DOFs_To_Compute
        (Scaling_Aspect_Rotation_And_Translation);
      Tool.Calibration.Calibrate;
      Check (Tool.Calibration.Calibrated, "calibrated");
      declare
         T : constant AMV.Transforms.Ks_Transform_2D_Linear :=
           Tool.Calibration.Get_Computed_Uncalibrated_From_Calibrated_Transform;
      begin
         Check_Near (T.Scaling_X, 20.0, 1.0E-9, "pixels per mm along x");
         Check_Near (T.Scaling_Y, 20.0 / 0.98, 1.0E-9,
                     "pixels per mm along y (aspect)");
         Check_Near (T.Rotation, Deg (10.0), 1.0E-12, "rotation");
         Check_Near (T.Skew, 0.0, 1.0E-12, "no skew");
         Check (Kernel_Of (T) = Kernel_Of (Tool.Calibration
                  .Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform),
                "raw calibrated is calibrated (no origin adjustment)");
      end;
      Check (Tool.Calibration.Computed_RMS_Error < 1.0E-9, "RMS error 0");

      Section ("N-point calibration: the tool");
      Tool.Input_Image := AMV_Test_Images.Blank (640, 480);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "run accepted");
      Check (Tool.Output_Image.Selected_Space_Name = "@\N-Point Calibration",
             "the calibrated space is selected");
      --  1 mm along calibrated x is 20 pixels along the plate's x axis.
      Map_Point (Tool.Output_Image.Get_Transform ("#", "."), 1.0, 0.0, U, V);
      Check_Near (U, 320.0 + 20.0 * EF.Cos (Deg (10.0)), 1.0E-9,
                  "1 mm in pixels: X");
      Check_Near (V, 240.0 + 20.0 * EF.Sin (Deg (10.0)), 1.0E-9,
                  "1 mm in pixels: Y");

      Section ("N-point calibration: streams");
      declare
         S    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Back : Ks_Calib_N_Point_To_N_Point;
      begin
         Ks_Calib_N_Point_To_N_Point'Write (S'Access, Tool.Calibration);
         Ks_Calib_N_Point_To_N_Point'Read (S'Access, Back);
         Check (Back.Calibrated and then Back.Num_Points = 9
                and then Back.DOFs_To_Compute
                           = Scaling_Aspect_Rotation_And_Translation
                and then Back.Get_Raw_Calibrated_Point_X (8) = B_X (9) / 10.0,
                "read back calibrated with its points");
         Check (Kernel_Of (Back
                  .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                = Kernel_Of (Tool.Calibration
                  .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                and then Back.Computed_RMS_Error
                           = Tool.Calibration.Computed_RMS_Error,
                "the computed state read back exactly");
      end;
      declare
         S    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Back : Ks_Calib_N_Point_To_N_Point;
      begin
         K.Int32'Write (S'Access, KF.Calibration_Stream_Code);
         K.Int32'Write (S'Access, KF.Kind_N_Point_To_N_Point);
         K.Int32'Write (S'Access, 1);
         K.Int32'Write (S'Access, K.True_Value);
         K.Int32'Write (S'Access, KF.DOF_Translation);
         Real'Write (S'Access, 1.0);
         Real'Write (S'Access, 1.0);
         for I in 1 .. 4 loop
            Real'Write (S'Access, 1.0);
         end loop;
         --  A fit that is not of its DOF's structure (a rotation).
         for V of Point_List'[0.0, -1.0, 1.0, 0.0, 0.0, 0.0, 0.0, 1.0, 1.0,
                              0.0, 0.0]
         loop
            Real'Write (S'Access, V);
         end loop;
         Ks_Calib_N_Point_To_N_Point'Read (S'Access, Back);
         Fail ("a forged fit is accepted");
      exception
         when AMV.Ks_Image_File_Exception =>
            Check (not Back.Calibrated and then Back.Num_Points = 0,
                   "a forged fit: Ks_Image_File_Exception, target kept");
      end;

      Section ("N-point calibration: changes uncalibrate");
      Tool.Calibration.Set_Uncalibrated_Point (0, 1.0, 2.0);
      Check (not Tool.Calibration.Calibrated, "a moved point uncalibrates");
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name
                        = "AMV.KS_OPERATOR_NOT_TRAINED_EXCEPTION"
             and then not Tool.Output_Image.Allocated,
             "uncalibrated tool run: Error");
      begin
         U := Tool.Calibration.Computed_RMS_Error;
         Fail ("RMS of an uncalibrated calibration" & U'Image);
      exception
         when AMV.Ks_Operator_Not_Trained_Exception =>
            Check (True, "RMS of an uncalibrated calibration raises");
      end;
      Tool.Calibration.Calibrate;
      Tool.Calibration.Set_DOFs_To_Compute (Rotation_And_Translation);
      Check (not Tool.Calibration.Calibrated, "a new DOF uncalibrates");
      Tool.Calibration.Calibrate;
      Tool.Calibration.Delete_Point_Pair (0);
      Check (not Tool.Calibration.Calibrated, "a deleted pair uncalibrates");
      Tool.Calibration.Calibrate;
      Tool.Calibration.Uncalibrate;
      Check (not Tool.Calibration.Calibrated
             and then Tool.Calibration.Num_Points = 8, "Uncalibrate");
   end Test_Calib_N_Point;

   ---------------------------------------------------------------------
   --  The checkerboard calibration
   ---------------------------------------------------------------------

   procedure Test_Checkerboard is

      procedure One
        (Square   : Real;
         Rotation : Real;
         Noise_Amplitude : Real;
         DOF      : Ks_Calib_Checkerboard_DOF_Constants;
         What     : String)
      is
         Image  : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480);
         Calib  : Ks_Calib_Checkerboard;
         Tile   : constant Real := 2.5;   --  mm
         Ox     : constant Real := 317.3;
         Oy     : constant Real := 243.6;
         T      : AMV.Transforms.Ks_Transform_2D_Linear;
         Worst  : Real := 0.0;
         Px, Py : Real;
         I, J   : Integer;
         Start  : constant Ada.Calendar.Time := Ada.Calendar.Clock;
         Spent  : Duration;
      begin
         AMV_Test_Images.Checkerboard (Image, Ox, Oy, Square, Rotation);
         if Noise_Amplitude > 0.0 then
            AMV_Test_Images.Add_Noise (Image, Noise_Amplitude, 7);
         end if;
         Calib.Set_Calibration_Image (Image);
         Calib.Set_Physical_Tile_Size_X (Tile);
         Calib.Set_Physical_Tile_Size_Y (Tile);
         Calib.Set_DOFs_To_Compute (DOF);
         Calib.Calibrate;
         Spent := Ada.Calendar."-" (Ada.Calendar.Clock, Start);
         T := Calib.Get_Computed_Uncalibrated_From_Calibrated_Transform;
         --  The pixel size is Tile / Square mm: the transform scales by
         --  Square / Tile pixels per mm.
         Check (abs (T.Scaling_X / (Square / Tile) - 1.0) < 0.002
                and then abs (T.Scaling_Y / (Square / Tile) - 1.0) < 0.002,
                What & ": pixel size within 0.2%" & T.Scaling_X'Image
                & T.Scaling_Y'Image);
         Check (abs (T.Rotation - Rotation) < Deg (0.05),
                What & ": rotation within 0.05 degree"
                & Real'Image (T.Rotation * 180.0 / Pi));
         Check (Calib.Num_Points >= 9, What & ": corners found"
                & Calib.Num_Points'Image);
         --  Every corner lies on the drawn lattice: corner (I, J) of the
         --  grid is a lattice point, and its grid neighbour one step
         --  further along the rotated axes.
         for K in 0 .. Calib.Num_Points - 1 loop
            Calib.Get_Corner (K, Px, Py, I, J);
            declare
               Dx : constant Real := Px - Ox;
               Dy : constant Real := Py - Oy;
               U  : constant Real :=
                 (EF.Cos (Rotation) * Dx + EF.Sin (Rotation) * Dy) / Square;
               V  : constant Real :=
                 (-EF.Sin (Rotation) * Dx + EF.Cos (Rotation) * Dy) / Square;
            begin
               Worst := Real'Max
                 (Worst, Square * Real'Max (abs (U - Real'Rounding (U)),
                                            abs (V - Real'Rounding (V))));
               Check (Px >= 0.0 and then Px <= 639.0 and then Py >= 0.0
                      and then Py <= 479.0, What & ": corner in the image");
            end;
            Check (Calib.Get_Raw_Calibrated_Point_X (K) = Real (I) * Tile
                   and then Calib.Get_Raw_Calibrated_Point_Y (K)
                              = Real (J) * Tile,
                   What & ": raw calibrated point of the grid");
         end loop;
         Check (Worst < (if Noise_Amplitude > 0.0 then 0.15 else 0.05),
                What & ": corners within" & Worst'Image & " px");
         Check (Calib.Computed_RMS_Error
                < (if Noise_Amplitude > 0.0 then 0.1 else 0.05),
                What & ": RMS error" & Calib.Computed_RMS_Error'Image);
         Ada.Text_IO.Put_Line
           ("  " & What & ":" & Calib.Num_Points'Image & " corners,"
            & Integer'Image (Integer (Spent * 1000.0)) & " ms, scale error"
            & Integer'Image
                (Integer (1.0E6 * abs (T.Scaling_X / (Square / Tile) - 1.0)))
            & " ppm, rotation error"
            & Integer'Image
                (Integer (1.0E6 * abs (T.Rotation - Rotation) * 180.0 / Pi))
            & " micro-degrees, worst corner"
            & Integer'Image (Integer (1000.0 * Worst)) & " mpx");
      end One;

   begin
      Section ("Checkerboard: pixel size and rotation");
      for Square of Point_List'[20.0, 25.0, 33.0, 40.0] loop
         One (Square, 0.0, 0.0, Scaling_Aspect_Rotation_Skew_And_Translation,
              "square" & Integer'Image (Integer (Square)) & ", 0 degrees");
         One (Square, Deg (17.0), 0.0,
              Scaling_Aspect_Rotation_Skew_And_Translation,
              "square" & Integer'Image (Integer (Square)) & ", 17 degrees");
      end loop;
      One (25.0, Deg (17.0), 0.0, Scaling_Rotation_And_Translation,
           "similarity DOF");
      One (30.0, Deg (-8.0), 0.0, Scaling_Aspect_Rotation_And_Translation,
           "aspect DOF, -8 degrees");

      Section ("Checkerboard: noise");
      One (25.0, Deg (17.0), 12.0,
           Scaling_Aspect_Rotation_Skew_And_Translation, "noise 12");
      One (40.0, 0.0, 12.0, Scaling_Aspect_Rotation_Skew_And_Translation,
           "noise 12, square 40");
   end Test_Checkerboard;

   procedure Test_Checkerboard_Boards is
      --  Regression tests for what failed on camera images: a finite board
      --  whose border tiles meet a plain margin (L-corners), a thin margin
      --  against a dark background, a board under perspective, and clutter
      --  beside the board (stripes, dots and a second, smaller board).

      subtype Homography is AMV_Test_Images.Homography;

      function Board
        (Tile, Rotation, Tx, Ty : Real;
         P, Q                   : Real := 0.0) return Homography
      is
        [Tile * EF.Cos (Rotation), -Tile * EF.Sin (Rotation), Tx,
         Tile * EF.Sin (Rotation), Tile * EF.Cos (Rotation), Ty, P, Q];
      --  Board coordinates (in tiles) to pixels: a turned and scaled board
      --  at (Tx, Ty), seen in perspective when P or Q is not zero.

      procedure Check_Board
        (Image         : Ks_Image_8_Grey;
         H             : Homography;
         Columns, Rows : Positive;
         Tolerance     : Real;
         What          : String)
      is
         Calib    : Ks_Calib_Checkerboard;
         Expected : constant Natural := (Columns - 1) * (Rows - 1);
      begin
         Calib.Set_Calibration_Image (Image);
         Calib.Calibrate;
         Check (Calib.Num_Points = Expected,
                What & ":" & Expected'Image & " corners (found"
                & Calib.Num_Points'Image & ")");
         declare
            N         : constant Natural := Calib.Num_Points;
            type Reals is array (0 .. N - 1) of Real;
            type Integers is array (0 .. N - 1) of Integer;
            Px, Py    : Reals;
            Gi, Gj    : Integers;
            Li, Lj    : Integers;
            Seen      : array (1 .. Columns - 1, 1 .. Rows - 1) of Boolean :=
              [others => [others => False]];
            Worst     : Real := 0.0;
            Twice     : Boolean := False;
            Sorted    : Boolean := True;
            Axes      : Boolean := True;
            Cx        : constant Real := 0.5 * Real (Image.Width - 1);
            Cy        : constant Real := 0.5 * Real (Image.Height - 1);
            Nearest   : Natural := 0;
            Nearest_D : Real := Real'Last;
            Mapped    : Boolean := False;
         begin
            for K in 0 .. N - 1 loop
               Calib.Get_Corner (K, Px (K), Py (K), Gi (K), Gj (K));
               --  The inner lattice point nearest to the corner.
               declare
                  Best : Real := Real'Last;
                  X, Y : Real;
               begin
                  Li (K) := 1;
                  Lj (K) := 1;
                  for J in 1 .. Rows - 1 loop
                     for I in 1 .. Columns - 1 loop
                        AMV_Test_Images.Map (H, Real (I), Real (J), X, Y);
                        if (X - Px (K)) ** 2 + (Y - Py (K)) ** 2 < Best then
                           Best := (X - Px (K)) ** 2 + (Y - Py (K)) ** 2;
                           Li (K) := I;
                           Lj (K) := J;
                        end if;
                     end loop;
                  end loop;
                  Worst := Real'Max (Worst, EF.Sqrt (Best));
               end;
               Twice := Twice or else Seen (Li (K), Lj (K));
               Seen (Li (K), Lj (K)) := True;
               if K > 0 then
                  Sorted := Sorted
                    and then (Gj (K - 1) < Gj (K)
                              or else (Gj (K - 1) = Gj (K)
                                       and then Gi (K - 1) < Gi (K)));
               end if;
               if (Px (K) - Cx) ** 2 + (Py (K) - Cy) ** 2 < Nearest_D then
                  Nearest_D := (Px (K) - Cx) ** 2 + (Py (K) - Cy) ** 2;
                  Nearest := K;
               end if;
            end loop;
            Check (Worst <= Tolerance,
                   What & ": every corner on an inner lattice point (worst"
                   & Integer'Image (Integer (Worst * 1000.0)) & " mpx)");
            Check (not Twice, What & ": no lattice point twice");
            Check (Sorted,
                   What & ": corners in rows of increasing J and I, so no "
                   & "grid index twice");
            Check (N > 0 and then Gi (Nearest) = 0 and then Gj (Nearest) = 0,
                   What & ": the corner nearest the image centre is (0, 0)");

            --  One signed permutation of the axes maps every step of the
            --  grid indices to the same step of the lattice.
            for Swap in Boolean loop
               for Si in -1 .. 1 loop
                  for Sj in -1 .. 1 loop
                     if Si /= 0 and then Sj /= 0 then
                        declare
                           All_Match : Boolean := N > 0;
                        begin
                           for K in 0 .. N - 1 loop
                              declare
                                 A : constant Integer := Gi (K) - Gi (0);
                                 B : constant Integer := Gj (K) - Gj (0);
                                 U : constant Integer :=
                                   (if Swap then B else A);
                                 V : constant Integer :=
                                   (if Swap then A else B);
                              begin
                                 All_Match := All_Match
                                   and then Si * U = Li (K) - Li (0)
                                   and then Sj * V = Lj (K) - Lj (0);
                              end;
                           end loop;
                           Mapped := Mapped or else All_Match;
                        end;
                     end if;
                  end loop;
               end loop;
            end loop;
            Check (Mapped,
                   What & ": the grid indices are the lattice's, up to the "
                   & "axes");

            --  The I axis runs to +x and the J axis to +y.
            for K in 0 .. N - 1 loop
               for L in 0 .. N - 1 loop
                  if Gi (L) = Gi (K) + 1 and then Gj (L) = Gj (K) then
                     Axes := Axes and then Px (L) > Px (K);
                  elsif Gi (L) = Gi (K) and then Gj (L) = Gj (K) + 1 then
                     Axes := Axes and then Py (L) > Py (K);
                  end if;
               end loop;
            end loop;
            Check (Axes, What & ": the I axis runs to +x, the J axis to +y");
         end;
      exception
         when E : Ks_Bad_Parameter_Exception =>
            Fail (What & ": " & Ada.Exceptions.Exception_Message (E));
      end Check_Board;

   begin
      Section ("Checkerboard: a finite board with a margin");
      declare
         Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 70);
         H     : constant Homography :=
           Board (32.0, Deg (7.0), 190.3, 95.6);
      begin
         --  The tile corners on the board's outline are L-corners.
         AMV_Test_Images.Draw_Board (Image, H, 10, 7, Margin => 0.5);
         Check_Board (Image, H, 10, 7, 0.06, "margin");
      end;
      declare
         Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 10);
         H     : constant Homography :=
           Board (30.0, Deg (-12.0), 150.4, 170.2);
      begin
         --  A margin of 4.5 pixels against a dark background: the ring of
         --  an L-corner there also sees the background, so the outline's
         --  corners pass for X-junctions; the tile test rejects them.
         AMV_Test_Images.Draw_Board (Image, H, 10, 7, Margin => 0.15);
         Check_Board (Image, H, 10, 7, 0.06, "thin margin");
      end;

      Section ("Checkerboard: perspective");
      declare
         Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
         H     : constant Homography :=
           Board (40.0, Deg (10.0), 250.0, 140.0, P => 0.04, Q => 0.03);
      begin
         --  The tiles shrink from about 40 pixels to 16 across the board,
         --  and the tile edges meet at up to 130 degrees instead of 90.
         --  The refinement's square window of whole pixels is not
         --  symmetric about such a skewed junction: measured errors are up
         --  to about 0.1 pixel (0.03 pixel RMS), against about 0.04 for
         --  square tiles.
         AMV_Test_Images.Draw_Board (Image, H, 10, 7, Margin => 0.4);
         Check_Board (Image, H, 10, 7, 0.15, "perspective");
      end;
      declare
         Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
         H     : constant Homography :=
           Board (34.0, Deg (-25.0), 160.0, 260.0, P => -0.03, Q => 0.05);
      begin
         AMV_Test_Images.Draw_Board (Image, H, 10, 7, Margin => 0.4);
         Check_Board (Image, H, 10, 7, 0.15, "perspective, turned");
      end;

      Section ("Checkerboard: clutter beside the board");
      declare
         Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 150);
         H     : constant Homography :=
           Board (26.0, Deg (4.0), 330.2, 150.7, P => 0.01, Q => -0.01);
      begin
         --  Stripes, as on a shirt.
         for K in 0 .. 9 loop
            AMV_Test_Images.Draw_Rectangle
              (Image, 150.0 + 6.0 * Real (K), 360.0 + 9.0 * Real (K),
               300.0, 3.5, Deg (-20.0), 40);
         end loop;
         --  Dots and bars, as on a keyboard.
         for K in 0 .. 11 loop
            AMV_Test_Images.Draw_Circle
              (Image, 40.0 + 22.0 * Real (K mod 6),
               40.0 + 24.0 * Real (K / 6), 6.0, 30);
            AMV_Test_Images.Draw_Rectangle
              (Image, 45.0 + 21.0 * Real (K mod 6),
               110.0 + 18.0 * Real (K / 6), 14.0, 9.0, Deg (8.0), 230);
         end loop;
         --  A smaller board of 4 x 4 tiles of 12 pixels, as on a monitor:
         --  a grid of its own with 9 corners, which must not win.
         AMV_Test_Images.Draw_Board
           (Image, Board (12.0, Deg (-6.0), 60.0, 190.0), 4, 4,
            Margin => 0.3);
         --  The board itself.
         AMV_Test_Images.Draw_Board (Image, H, 10, 7, Margin => 0.4);
         AMV_Test_Images.Add_Noise (Image, 6.0, 11);
         Check_Board (Image, H, 10, 7, 0.15, "clutter");
      end;
   end Test_Checkerboard_Boards;

   procedure Test_Checkerboard_Tool is
      Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (320, 240);
      Tool  : Ks_Calib_Checkerboard_Tool;
      U, V  : Real;
   begin
      Section ("Checkerboard tool");
      AMV_Test_Images.Checkerboard (Image, 160.4, 119.7, 24.0, Deg (5.0));
      Tool.Calibration.Set_Calibration_Image (Image);
      Tool.Calibration.Set_Physical_Tile_Size_X (3.0);
      Tool.Calibration.Set_Physical_Tile_Size_Y (3.0);
      Tool.Input_Image := Image;
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name
                        = "AMV.KS_OPERATOR_NOT_TRAINED_EXCEPTION",
             "uncalibrated: Error");
      Tool.Calibration.Calibrate;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Output_Image.Selected_Space_Name
                        = "@\Checkerboard Calibration", "run accepted");
      --  The calibrated origin is the corner nearest the image centre,
      --  (160.4, 119.7); 3 mm along the grid's x is one square (24 px)
      --  along (cos 5, sin 5).
      Map_Point (Tool.Output_Image.Get_Transform ("#", "."), 3.0, 0.0, U, V);
      Check_Near (U, 160.4 + 24.0 * EF.Cos (Deg (5.0)), 0.05,
                  "3 mm in pixels: X");
      Check_Near (V, 119.7 + 24.0 * EF.Sin (Deg (5.0)), 0.05,
                  "3 mm in pixels: Y");

      Section ("Checkerboard: a selected space on the images");
      declare
         Staged : Ks_Image_8_Grey := Image;
         Stage  : constant AMV.Transforms.Ks_Transform_2D_Linear :=
           Create_Similarity (0.5, -0.3, 40.0, 25.0);
         Px, Py : Real;
         I, J   : Integer;
         Su, Sv : Real;
      begin
         Staged.Coordinate_Space_Tree.Add_Space ("@", "Stage", Stage);
         Staged.Set_Selected_Space_Name ("@\Stage");
         Tool.Calibration.Set_Calibration_Image (Staged);
         Tool.Calibration.Calibrate;
         --  The uncalibrated points are the corners in the stage's frame.
         Tool.Calibration.Get_Corner (0, Px, Py, I, J);
         Map_Point (Staged.Get_Transform ("@\Stage", "#"), Px, Py, Su, Sv);
         Check_Near (Tool.Calibration.Get_Uncalibrated_Point_X (0), Su,
                     1.0E-9, "uncalibrated point in the selected space: X");
         Check_Near (Tool.Calibration.Get_Uncalibrated_Point_Y (0), Sv,
                     1.0E-9, "uncalibrated point in the selected space: Y");
         Tool.Input_Image := Staged;
         Tool.Run;
         Check (Tool.Output_Image.Selected_Space_Name
                = "@\Stage\Checkerboard Calibration",
                "the calibrated space under the stage");
         --  3 mm along the grid's x still lands one square from the origin
         --  in pixels.
         Map_Point (Tool.Output_Image.Get_Transform ("#", "."), 3.0, 0.0,
                    U, V);
         Check_Near (U, 160.4 + 24.0 * EF.Cos (Deg (5.0)), 0.05,
                     "3 mm in pixels through the stage: X");
         Check_Near (V, 119.7 + 24.0 * EF.Sin (Deg (5.0)), 0.05,
                     "3 mm in pixels through the stage: Y");
         Tool.Calibration.Set_Calibration_Image (Image);
         Tool.Calibration.Calibrate;
         Tool.Input_Image := Image;
      end;

      Section ("Checkerboard: streams");
      declare
         S    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Back : Ks_Calib_Checkerboard;
         Px, Py, Qx, Qy : Real;
         I, J, I2, J2   : Integer;
      begin
         Ks_Calib_Checkerboard'Write (S'Access, Tool.Calibration);
         Ks_Calib_Checkerboard'Read (S'Access, Back);
         Check (Back.Calibrated
                and then Back.Num_Points = Tool.Calibration.Num_Points
                and then Back.Physical_Tile_Size_X = 3.0
                and then Back.Calibration_Image.Width = 320,
                "read back calibrated with its image");
         Back.Get_Corner (5, Px, Py, I, J);
         Tool.Calibration.Get_Corner (5, Qx, Qy, I2, J2);
         Check (Px = Qx and then Py = Qy and then I = I2 and then J = J2
                and then Back.Get_Uncalibrated_Point_X (5)
                           = Tool.Calibration.Get_Uncalibrated_Point_X (5),
                "a corner read back");
         Check (Kernel_Of (Back
                  .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                = Kernel_Of (Tool.Calibration
                  .Get_Computed_Uncalibrated_From_Calibrated_Transform),
                "the transform read back");
      end;

      Section ("Checkerboard: changes uncalibrate");
      Tool.Calibration.Set_Physical_Tile_Size_X (4.0);
      Check (not Tool.Calibration.Calibrated
             and then Tool.Calibration.Num_Points = 0,
             "a new tile size uncalibrates and forgets the corners");
      begin
         Tool.Calibration.Set_Physical_Tile_Size_Y (-1.0);
         Fail ("a negative tile size");
      exception
         when AMV.Ks_Bad_Parameter_Exception =>
            Check (Tool.Calibration.Physical_Tile_Size_Y = 3.0,
                   "a negative tile size is rejected");
      end;

      Section ("Checkerboard: failures");
      declare
         Calib : Ks_Calib_Checkerboard;
      begin
         Calib.Calibrate;
         Fail ("no calibration image");
      exception
         when AMV.Ks_Image_No_Pixels_Exception =>
            Check (True, "no calibration image: Ks_Image_No_Pixels");
      end;
      declare
         Calib : Ks_Calib_Checkerboard;
      begin
         Calib.Set_Calibration_Image (AMV_Test_Images.Blank (100, 100, 90));
         Calib.Calibrate;
         Fail ("a blank image");
      exception
         when E : AMV.Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E)
                   = "CalibrationImage: fewer than 9 checkerboard corners "
                     & "were found", "a blank image: too few corners");
      end;
   end Test_Checkerboard_Tool;

   ---------------------------------------------------------------------
   --  The origin adjustment
   ---------------------------------------------------------------------

   function Raw_From_Calibrated
     (Raw, Adjusted : AMV.Transforms.Ks_Transform_2D_Linear)
      return KT.Ks_Transform_2D_Linear
   is (Kernel_Of (Invert (Raw) * Adjusted));
   --  R = F**(-1) * (F * R): raw calibrated from calibrated.

   procedure Check_Rigid
     (R       : KT.Ks_Transform_2D_Linear;
      Phi     : Real;
      Swapped : Boolean;
      Ox, Oy  : Real;
      What    : String)
   is
      S : constant Real := (if Swapped then -1.0 else 1.0);
   begin
      Check_Near (R.A, EF.Cos (Phi), 1.0E-12, What & ": cos of the x axis");
      Check_Near (R.C, EF.Sin (Phi), 1.0E-12, What & ": sin of the x axis");
      Check_Near (R.B, -S * EF.Sin (Phi), 1.0E-12, What & ": the y axis, x");
      Check_Near (R.D, S * EF.Cos (Phi), 1.0E-12, What & ": the y axis, y");
      Check_Near (R.Translation_X, Ox, 1.0E-9, What & ": origin X");
      Check_Near (R.Translation_Y, Oy, 1.0E-9, What & ": origin Y");
   end Check_Rigid;
   --  R is the rigid map Translate (Ox, Oy) * Rotate (Phi), mirrored along
   --  the calibrated y axis when Swapped.

   function Direction_Of (T : KT.Ks_Transform_2D_Linear) return Real is
     (EF.Arctan (T.C, T.A));
   --  The direction of the image of the x axis under T.

   procedure Test_Origin_Adjustment is
      --  A fit with an aspect and a skew, so that a direction of the
      --  uncalibrated space is another direction in raw calibrated space.
      Truth  : constant KT.Ks_Transform_2D_Linear :=
        Make (20.0, 20.0 / 0.98, Deg (10.0), Deg (4.0), 320.0, 240.0);
      Tool   : Ks_Calib_N_Point_To_N_Point_Tool;
      Raw    : AMV.Transforms.Ks_Transform_2D_Linear;
      T      : AMV.Transforms.Ks_Transform_2D_Linear;
      R      : KT.Ks_Transform_2D_Linear;
      U, V   : Real;
      X, Y   : Real;
      Ox, Oy : Real;

      function Adjusted return AMV.Transforms.Ks_Transform_2D_Linear is
        (Tool.Calibration.Get_Computed_Uncalibrated_From_Calibrated_Transform);
   begin
      Section ("Origin adjustment: the defaults");
      for I in 1 .. 9 loop
         Map (Truth, B_X (I) / 10.0, B_Y (I) / 10.0, U, V);
         Tool.Calibration.Add_Point_Pair (U, V, B_X (I) / 10.0,
                                          B_Y (I) / 10.0);
      end loop;
      Check (Tool.Calibration.Calibrated_Origin_X = 0.0
             and then Tool.Calibration.Calibrated_Origin_Y = 0.0
             and then Tool.Calibration.Calibrated_Origin_Space
                        = Raw_Calibrated
             and then Tool.Calibration.Calibrated_X_Axis_Rotation = 0.0
             and then Tool.Calibration.Calibrated_X_Axis_Rotation_Space
                        = Raw_Calibrated
             and then not Tool.Calibration.Swap_Calibrated_Handedness,
             "the defaults: origin (0, 0), rotation 0, raw calibrated, not "
             & "swapped");
      Tool.Calibration.Calibrate;
      Raw := Tool.Calibration
               .Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform;
      Check_Transform (Raw, Truth, 1.0E-9, "the fit");
      Check (Kernel_Of (Adjusted) = Kernel_Of (Raw),
             "the defaults: calibrated is raw calibrated, exactly");
      Tool.Input_Image := AMV_Test_Images.Blank (640, 480);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Kernel_Of (Tool.Output_Image.Get_Coordinate_Space_Tree
                                   .Parent_From_Child_Transform
                                      ("@\N-Point Calibration"))
                      = Kernel_Of (Raw),
             "the defaults: the tool adds the fit itself");

      Section ("Origin adjustment: in raw calibrated space");
      Tool.Calibration.Set_Calibrated_Origin_X (3.0);
      Tool.Calibration.Set_Calibrated_Origin_Y (-2.0);
      Check (Tool.Calibration.Calibrated
             and then Tool.Calibration.Calibrated_Origin_X = 3.0
             and then Tool.Calibration.Calibrated_Origin_Y = -2.0,
             "setting the origin keeps the calibration calibrated");
      T := Adjusted;
      Check (Kernel_Of (Tool.Calibration
               .Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform)
             = Kernel_Of (Raw), "the raw calibrated transform stays the fit");
      Check_Rigid (Raw_From_Calibrated (Raw, T), 0.0, False, 3.0, -2.0,
                   "raw origin");
      --  The raw calibrated point (3, -2), seen at Raw (3, -2), is the
      --  calibrated origin.
      Map_Point (Raw, 3.0, -2.0, U, V);
      Map_Point (Invert (T), U, V, X, Y);
      Check (abs X < 1.0E-10 and then abs Y < 1.0E-10,
             "the raw calibrated point (3, -2) is calibrated (0, 0)");
      Check (Kernel_Of (Raw).A = Kernel_Of (T).A
             and then Kernel_Of (Raw).D = Kernel_Of (T).D,
             "a raw origin alone keeps the linear part");

      Tool.Calibration.Set_Calibrated_X_Axis_Rotation (Deg (30.0));
      T := Adjusted;
      Check_Rigid (Raw_From_Calibrated (Raw, T), Deg (30.0), False, 3.0,
                   -2.0, "raw rotation 30 degrees");

      Tool.Calibration.Set_Swap_Calibrated_Handedness (True);
      Check (Tool.Calibration.Calibrated
             and then Tool.Calibration.Swap_Calibrated_Handedness,
             "setting the handedness keeps the calibration calibrated");
      T := Adjusted;
      R := Raw_From_Calibrated (Raw, T);
      Check_Rigid (R, Deg (30.0), True, 3.0, -2.0, "swapped");
      Check_Near (T.Matrix_Determinant / Raw.Matrix_Determinant, -1.0,
                  1.0E-12, "swap: the determinant changes sign");
      declare
         --  Two calibrated points 5 apart are 5 apart in raw calibrated
         --  space.
         P1x, P1y, P2x, P2y : Real;
      begin
         Map (R, 1.0, 2.0, P1x, P1y);
         Map (R, 4.0, 6.0, P2x, P2y);
         Check_Near (EF.Sqrt ((P2x - P1x) ** 2 + (P2y - P1y) ** 2), 5.0,
                     1.0E-12, "swap: distances are kept");
         Check_Near (P1x,
                     3.0 + EF.Cos (Deg (30.0)) + 2.0 * EF.Sin (Deg (30.0)),
                     1.0E-12, "swap: calibrated (1, 2) in raw space: X");
         Check_Near (P1y,
                     -2.0 + EF.Sin (Deg (30.0)) - 2.0 * EF.Cos (Deg (30.0)),
                     1.0E-12, "swap: calibrated (1, 2) in raw space: Y");
      end;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "swapped: the tool runs");
      Check_Transform (Tool.Output_Image.Get_Transform ("#", "."),
                       Kernel_Of (T), 1.0E-12,
                       "the tool's calibrated space is F * R");

      Section ("Origin adjustment: in the uncalibrated space");
      Tool.Calibration.Set_Swap_Calibrated_Handedness (False);
      Tool.Calibration.Set_Calibrated_X_Axis_Rotation (0.0);
      Tool.Calibration.Set_Calibrated_Origin_Space (Uncalibrated);
      Tool.Calibration.Set_Calibrated_Origin_X (412.0);
      Tool.Calibration.Set_Calibrated_Origin_Y (305.0);
      Check (Tool.Calibration.Calibrated
             and then Tool.Calibration.Calibrated_Origin_Space = Uncalibrated,
             "setting the origin space keeps the calibration calibrated");
      T := Adjusted;
      Map_Point (T, 0.0, 0.0, U, V);
      Check_Near (U, 412.0, 1.0E-9, "the pixel (412, 305) is the origin: X");
      Check_Near (V, 305.0, 1.0E-9, "the pixel (412, 305) is the origin: Y");
      Map_Point (Invert (Raw), 412.0, 305.0, Ox, Oy);
      Check_Rigid (Raw_From_Calibrated (Raw, T), 0.0, False, Ox, Oy,
                   "uncalibrated origin: raw axes");
      Tool.Run;
      Map_Point (Tool.Output_Image.Get_Transform (".", "#"), 412.0, 305.0,
                 X, Y);
      Check (Tool.Run_Status.Result = Accept_Result
             and then abs X < 1.0E-9 and then abs Y < 1.0E-9,
             "the tool: the pixel (412, 305) is calibrated (0, 0)");

      Tool.Calibration.Set_Calibrated_X_Axis_Rotation_Space (Uncalibrated);
      Tool.Calibration.Set_Calibrated_X_Axis_Rotation (Deg (-20.0));
      Check (Tool.Calibration.Calibrated
             and then Tool.Calibration.Calibrated_X_Axis_Rotation_Space
                        = Uncalibrated,
             "setting the rotation space keeps the calibration calibrated");
      T := Adjusted;
      Check_Near (Direction_Of (Kernel_Of (T)), Deg (-20.0), 1.0E-12,
                  "the calibrated x axis runs along -20 degrees in pixels");
      Map_Point (T, 0.0, 0.0, U, V);
      Check (abs (U - 412.0) < 1.0E-9 and then abs (V - 305.0) < 1.0E-9,
             "the origin stays at the pixel (412, 305)");
      declare
         --  The raw calibrated direction that the fit maps onto -20
         --  degrees: Lin (F)**(-1) (cos, sin), by the 2 x 2 inverse.
         F    : constant KT.Ks_Transform_2D_Linear := Kernel_Of (Raw);
         C    : constant Real := EF.Cos (Deg (-20.0));
         S    : constant Real := EF.Sin (Deg (-20.0));
         Phi  : constant Real :=
           EF.Arctan (-F.C * C + F.A * S, F.D * C - F.B * S);
         --  (The determinant, positive here, does not change the angle.)
      begin
         R := Raw_From_Calibrated (Raw, T);
         Check_Rigid (R, Phi, False, Ox, Oy, "uncalibrated rotation");
         Check (abs (Phi - Deg (-30.0)) > Deg (0.1),
                "the aspect and the skew turn the raw axis away from "
                & "-20 - 10 degrees" & Real'Image (Phi * 180.0 / Pi));
         Tool.Calibration.Set_Swap_Calibrated_Handedness (True);
         T := Adjusted;
         Check_Near (Direction_Of (Kernel_Of (T)), Deg (-20.0), 1.0E-12,
                     "swapped: the x axis still along -20 degrees");
         Check_Rigid (Raw_From_Calibrated (Raw, T), Phi, True, Ox, Oy,
                      "uncalibrated rotation, swapped");
         Check (T.Matrix_Determinant < 0.0
                and then Raw.Matrix_Determinant > 0.0,
                "swapped: the determinant changes sign");
      end;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "the tool runs");
      Check_Transform (Tool.Output_Image.Get_Transform ("#", "."),
                       Kernel_Of (T), 1.0E-12,
                       "the tool's calibrated space is F * R (uncalibrated)");

      Section ("Origin adjustment: the rotation and bad values");
      Tool.Calibration.Set_Calibrated_X_Axis_Rotation (Deg (370.0));
      Check_Near (Tool.Calibration.Calibrated_X_Axis_Rotation, Deg (10.0),
                  1.0E-12, "a rotation of 370 degrees reads back as 10");
      Tool.Calibration.Set_Calibrated_X_Axis_Rotation (-Pi);
      Check (Tool.Calibration.Calibrated_X_Axis_Rotation = Pi,
             "-Pi reads back as Pi");
      Tool.Calibration.Set_Calibrated_X_Axis_Rotation (Pi);
      Check (Tool.Calibration.Calibrated_X_Axis_Rotation = Pi,
             "Pi stays Pi");
      Tool.Calibration.Set_Calibrated_X_Axis_Rotation (Deg (-20.0));
      begin
         Tool.Calibration.Set_Calibrated_Origin_X (NaN);
         Fail ("a NaN origin");
      exception
         when E : AMV.Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E)
                   = "CalibratedOriginX must be finite and within +/-1.0E150"
                   and then Tool.Calibration.Calibrated_Origin_X = 412.0
                   and then Tool.Calibration.Calibrated,
                   "a NaN origin: Ks_Bad_Parameter_Exception, nothing "
                   & "changed");
      end;
      begin
         Tool.Calibration.Set_Calibrated_Origin_Y (2.0E150);
         Fail ("an origin beyond 1.0E150");
      exception
         when E : AMV.Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E)
                   = "CalibratedOriginY must be finite and within +/-1.0E150"
                   and then Tool.Calibration.Calibrated_Origin_Y = 305.0,
                   "an origin beyond 1.0E150");
      end;
      begin
         Tool.Calibration.Set_Calibrated_X_Axis_Rotation (Inf);
         Fail ("an infinite rotation");
      exception
         when E : AMV.Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E)
                   = "CalibratedXAxisRotation must be finite"
                   and then Tool.Calibration.Calibrated_X_Axis_Rotation
                              = Deg (-20.0),
                   "an infinite rotation");
      end;

      Section ("Origin adjustment: beyond the bounds");
      declare
         Far : Ks_Calib_N_Point_To_N_Point := Tool.Calibration;
      begin
         Far.Set_Calibrated_Origin_Space (Raw_Calibrated);
         Far.Set_Calibrated_Origin_X (1.0E150);
         Check (Far.Calibrated, "a far origin is accepted");
         begin
            T := Far.Get_Computed_Uncalibrated_From_Calibrated_Transform;
            Fail ("an origin 1.0E150 mm away in pixels");
         exception
            when AMV.Ks_Bad_Parameter_Exception =>
               Check (Kernel_Of (Far
                        .Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform)
                      = Kernel_Of (Raw),
                      "an origin beyond the bound in pixels: "
                      & "Ks_Bad_Parameter_Exception, the fit still there");
         end;
         Tool.Calibration := Far;
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Exception_Name
                           = "AMV.KS_BAD_PARAMETER_EXCEPTION"
                and then not Tool.Output_Image.Allocated,
                "the tool fails with that origin");
      end;

      Section ("Origin adjustment: kept by copies and new fits");
      Tool.Calibration.Set_Calibrated_Origin_Space (Uncalibrated);
      Tool.Calibration.Set_Calibrated_Origin_X (412.0);
      declare
         Copy : constant Ks_Calib_N_Point_To_N_Point := Tool.Calibration;
      begin
         Check (Copy.Calibrated_Origin_Space = Uncalibrated
                and then Copy.Calibrated_Origin_X = 412.0
                and then Copy.Calibrated_X_Axis_Rotation = Deg (-20.0)
                and then Copy.Swap_Calibrated_Handedness
                and then Kernel_Of (Copy
                           .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                         = Kernel_Of (Adjusted),
                "a copy has the adjustment");
      end;
      Tool.Calibration.Set_DOFs_To_Compute
        (Scaling_Aspect_Rotation_And_Translation);
      Check (not Tool.Calibration.Calibrated
             and then Tool.Calibration.Calibrated_Origin_X = 412.0,
             "a new DOF uncalibrates and keeps the adjustment");
      Tool.Calibration.Set_DOFs_To_Compute
        (Scaling_Aspect_Rotation_Skew_And_Translation);
      Tool.Calibration.Calibrate;
      Check (Kernel_Of (Adjusted) = Kernel_Of (T),
             "calibrated again: the same transform");

      Section ("Origin adjustment: streams");
      declare
         S    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Back : Ks_Calib_N_Point_To_N_Point;
         Code : K.Int32;
      begin
         Ks_Calib_N_Point_To_N_Point'Write (S'Access, Tool.Calibration);
         K.Int32'Read (S'Access, Code);
         Check (Code = KF.Calibration_Stream_Code_2,
                "an adjustment is written in layout 2");
         S.Clear;
         Ks_Calib_N_Point_To_N_Point'Write (S'Access, Tool.Calibration);
         Ks_Calib_N_Point_To_N_Point'Read (S'Access, Back);
         Check (Back.Calibrated and then Back.Num_Points = 9
                and then Back.Calibrated_Origin_Space = Uncalibrated
                and then Back.Calibrated_Origin_X = 412.0
                and then Back.Calibrated_Origin_Y = 305.0
                and then Back.Calibrated_X_Axis_Rotation_Space = Uncalibrated
                and then Back.Calibrated_X_Axis_Rotation = Deg (-20.0)
                and then Back.Swap_Calibrated_Handedness
                and then Kernel_Of
                           (Back
                            .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                         = Kernel_Of (T)
                and then Kernel_Of
                           (Back
                            .Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform)
                         = Kernel_Of (Raw),
                "read back with its adjustment and transforms");

         --  The previous layout gives the defaults: Back, adjusted, reads
         --  a calibration without adjustment (layout 0).
         S.Clear;
         declare
            Plain : Ks_Calib_N_Point_To_N_Point := Tool.Calibration;
         begin
            Plain.Set_Calibrated_Origin_Space (Raw_Calibrated);
            Plain.Set_Calibrated_Origin_X (0.0);
            Plain.Set_Calibrated_Origin_Y (0.0);
            Plain.Set_Calibrated_X_Axis_Rotation_Space (Raw_Calibrated);
            Plain.Set_Calibrated_X_Axis_Rotation (0.0);
            Plain.Set_Swap_Calibrated_Handedness (False);
            Ks_Calib_N_Point_To_N_Point'Write (S'Access, Plain);
            K.Int32'Read (S'Access, Code);
            Check (Code = KF.Calibration_Stream_Code,
                   "the default adjustment is written in layout 0");
            S.Clear;
            Ks_Calib_N_Point_To_N_Point'Write (S'Access, Plain);
            Ks_Calib_N_Point_To_N_Point'Read (S'Access, Back);
            Check (Back.Calibrated
                   and then Back.Calibrated_Origin_Space = Raw_Calibrated
                   and then Back.Calibrated_Origin_X = 0.0
                   and then Back.Calibrated_Origin_Y = 0.0
                   and then Back.Calibrated_X_Axis_Rotation_Space
                              = Raw_Calibrated
                   and then Back.Calibrated_X_Axis_Rotation = 0.0
                   and then not Back.Swap_Calibrated_Handedness
                   and then Kernel_Of
                              (Back
                               .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                            = Kernel_Of (Raw),
                   "layout 0 reads back with the default adjustment");
         end;
      end;
      declare
         --  Layout 2 written by hand: an uncalibrated N-point calibration
         --  without points and the adjustment A.
         procedure Write_Layout_2
           (S : not null access Ada.Streams.Root_Stream_Type'Class;
            A : KF.Ks_Calibration_Adjustment) is
         begin
            K.Int32'Write (S, 16#4B43_4C02#);
            K.Int32'Write (S, KF.Kind_N_Point_To_N_Point);
            K.Int32'Write (S, 0);              --  points
            K.Int32'Write (S, K.False_Value);  --  not calibrated
            K.Int32'Write (S, KF.Mode_Linear);
            KF.Ks_Calibration_Adjustment'Write (S, A);
            K.Int32'Write (S, KF.DOF_Translation);
            Real'Write (S, 1.0);
            Real'Write (S, 1.0);
         end Write_Layout_2;

         type Adjustment_List is
           array (Positive range <>) of KF.Ks_Calibration_Adjustment;

         S    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Back : Ks_Calib_N_Point_To_N_Point;
         Good : constant KF.Ks_Calibration_Adjustment :=
           (Calibrated_Origin_X              => -7.5,
            Calibrated_Origin_Y              => 2.25,
            Calibrated_X_Axis_Rotation       => 1.0,
            Calibrated_Origin_Space          => 1,
            Calibrated_X_Axis_Rotation_Space => 0,
            Swap_Calibrated_Handedness       => 1);
      begin
         Write_Layout_2 (S'Access, Good);
         Ks_Calib_N_Point_To_N_Point'Read (S'Access, Back);
         Check (not Back.Calibrated and then Back.Num_Points = 0
                and then Back.DOFs_To_Compute = Translation
                and then Back.Calibrated_Origin_X = -7.5
                and then Back.Calibrated_Origin_Y = 2.25
                and then Back.Calibrated_X_Axis_Rotation = 1.0
                and then Back.Calibrated_Origin_Space = Uncalibrated
                and then Back.Calibrated_X_Axis_Rotation_Space
                           = Raw_Calibrated
                and then Back.Swap_Calibrated_Handedness,
                "a layout 2 stream written by hand reads back");
         for Bad of Adjustment_List'[
           (Good with delta Calibrated_X_Axis_Rotation => 4.0),
           (Good with delta Calibrated_X_Axis_Rotation => NaN),
           (Good with delta Calibrated_Origin_X => Inf),
           (Good with delta Calibrated_Origin_Space => 2),
           (Good with delta Calibrated_X_Axis_Rotation_Space => -1),
           (Good with delta Swap_Calibrated_Handedness => 2)]
         loop
            S.Clear;
            Write_Layout_2 (S'Access, Bad);
            begin
               Ks_Calib_N_Point_To_N_Point'Read (S'Access, Back);
               Fail ("a malformed adjustment is accepted");
            exception
               when AMV.Ks_Image_File_Exception =>
                  Check (Back.Calibrated_Origin_X = -7.5,
                         "a malformed adjustment: Ks_Image_File_Exception, "
                         & "target kept");
            end;
         end loop;
      end;
   end Test_Origin_Adjustment;

   procedure Test_Checkerboard_Adjustment is
      Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (320, 240);
      Tool  : Ks_Calib_Checkerboard_Tool;
      X, Y  : Real;
   begin
      Section ("Origin adjustment: the checkerboard tool");
      --  Squares of 24 pixels turned by 5 degrees, tiles of 3 mm: 8 pixels
      --  per mm, square pixels.
      AMV_Test_Images.Checkerboard (Image, 160.4, 119.7, 24.0, Deg (5.0));
      Tool.Calibration.Set_Calibration_Image (Image);
      Tool.Calibration.Set_Physical_Tile_Size_X (3.0);
      Tool.Calibration.Set_Physical_Tile_Size_Y (3.0);
      Tool.Calibration.Calibrate;
      --  The calibrated origin at the pixel (100, 80), the x axis along
      --  the pixels' x axis.
      Tool.Calibration.Set_Calibrated_Origin_Space (Uncalibrated);
      Tool.Calibration.Set_Calibrated_Origin_X (100.0);
      Tool.Calibration.Set_Calibrated_Origin_Y (80.0);
      Tool.Calibration.Set_Calibrated_X_Axis_Rotation_Space (Uncalibrated);
      Check (Tool.Calibration.Calibrated, "the setters keep it calibrated");
      Tool.Input_Image := Image;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result, "the tool runs");
      Map_Point (Tool.Output_Image.Get_Transform (".", "#"), 100.0, 80.0,
                 X, Y);
      Check (abs X < 1.0E-9 and then abs Y < 1.0E-9,
             "the pixel (100, 80) is the calibrated origin");
      Map_Point (Tool.Output_Image.Get_Transform (".", "#"), 124.0, 80.0,
                 X, Y);
      Check (abs (X - 3.0) < 0.01 and then abs Y < 1.0E-9,
             "24 pixels along x are 3 mm along the calibrated x axis");
      Map_Point (Tool.Output_Image.Get_Transform (".", "#"), 100.0, 104.0,
                 X, Y);
      Check (abs X < 0.01 and then abs (Y - 3.0) < 0.01,
             "24 pixels along y are 3 mm along the calibrated y axis");
      Tool.Calibration.Set_Swap_Calibrated_Handedness (True);
      Tool.Run;
      Map_Point (Tool.Output_Image.Get_Transform (".", "#"), 100.0, 104.0,
                 X, Y);
      Check (abs X < 0.01 and then abs (Y + 3.0) < 0.01,
             "swapped: 24 pixels along y are -3 mm");
      Map_Point (Tool.Output_Image.Get_Transform (".", "#"), 124.0, 80.0,
                 X, Y);
      Check (abs (X - 3.0) < 0.01 and then abs Y < 1.0E-9,
             "swapped: the x axis stays");
   end Test_Checkerboard_Adjustment;

   ---------------------------------------------------------------------
   --  Lens distortion: the computation mode Perspective_And_Radial_Warp
   ---------------------------------------------------------------------

   --  Boards rendered through a known homography (board coordinates in
   --  tiles to ideal pixels) and a known radial distortion in AMV's
   --  normalisation: the observed pixel of the ideal pixel h is
   --  c + (h - c) (1 + K1 r**2 + K2 r**4), r = |h - c| / s, c the image
   --  centre and s half the image diagonal. Each pixel averages Samples**2
   --  sub-pixel samples; a sample's ideal point is found by Newton's
   --  method on the radius.

   subtype Homography is AMV_Test_Images.Homography;

   function Board
     (Tile, Rotation, Tx, Ty : Real;
      P, Q                   : Real := 0.0) return Homography
   is
     [Tile * EF.Cos (Rotation), -Tile * EF.Sin (Rotation), Tx,
      Tile * EF.Sin (Rotation), Tile * EF.Cos (Rotation), Ty, P, Q];
   --  Board coordinates (in tiles) to ideal pixels.

   type Lens is record
      K1, K2 : Real := 0.0;
   end record;

   procedure Distort
     (Width, Height : Natural;
      L             : Lens;
      HX, HY        : Real;
      PX, PY        : out Real)
   is
      CX : constant Real := Real (Width - 1) / 2.0;
      CY : constant Real := Real (Height - 1) / 2.0;
      S  : constant Real :=
        EF.Sqrt (Real (Width) ** 2 + Real (Height) ** 2) / 2.0;
      R2 : constant Real := ((HX - CX) ** 2 + (HY - CY) ** 2) / S ** 2;
      F  : constant Real := 1.0 + L.K1 * R2 + L.K2 * R2 ** 2;
   begin
      PX := CX + (HX - CX) * F;
      PY := CY + (HY - CY) * F;
   end Distort;
   --  The observed pixel of the ideal pixel (HX, HY).

   procedure True_Corner
     (Width, Height : Natural;
      H             : Homography;
      L             : Lens;
      I, J          : Real;
      PX, PY        : out Real)
   is
      HX, HY : Real;
   begin
      AMV_Test_Images.Map (H, I, J, HX, HY);
      Distort (Width, Height, L, HX, HY, PX, PY);
   end True_Corner;
   --  Where the board point (I, J) (tiles) is seen.

   procedure Draw_Distorted_Board
     (Image         : in out Ks_Image_8_Grey;
      H             : Homography;
      L             : Lens;
      Columns, Rows : Positive;
      Margin        : Real := 0.4;
      Dark          : Grey_8 := 30;
      Light         : Grey_8 := 220;
      Background    : Grey_8 := 90;
      Samples       : Positive := 4)
   is
      W   : constant Natural := Image.Width;
      Hh  : constant Natural := Image.Height;
      CX  : constant Real := Real (W - 1) / 2.0;
      CY  : constant Real := Real (Hh - 1) / 2.0;
      S   : constant Real := EF.Sqrt (Real (W) ** 2 + Real (Hh) ** 2) / 2.0;
      --  The inverse of H (the adjugate of [H1 H2 H3; H4 H5 H6; H7 H8 1]).
      I11 : constant Real := H (5) - H (6) * H (8);
      I12 : constant Real := H (3) * H (8) - H (2);
      I13 : constant Real := H (2) * H (6) - H (3) * H (5);
      I21 : constant Real := H (6) * H (7) - H (4);
      I22 : constant Real := H (1) - H (3) * H (7);
      I23 : constant Real := H (3) * H (4) - H (1) * H (6);
      I31 : constant Real := H (4) * H (8) - H (5) * H (7);
      I32 : constant Real := H (2) * H (7) - H (1) * H (8);
      I33 : constant Real := H (1) * H (5) - H (2) * H (4);
      Row : Grey_8_Row (0 .. W - 1);

      function Value (PX, PY : Real) return Real is
         DX : constant Real := (PX - CX) / S;
         DY : constant Real := (PY - CY) / S;
         RD : constant Real := EF.Sqrt (DX * DX + DY * DY);
         R  : Real := RD;
         HX, HY, U, V, Den : Real;
      begin
         --  The ideal radius R with R (1 + K1 R**2 + K2 R**4) = RD.
         for Unused in 1 .. 12 loop
            R := R - (R * (1.0 + L.K1 * R ** 2 + L.K2 * R ** 4) - RD)
                     / (1.0 + 3.0 * L.K1 * R ** 2 + 5.0 * L.K2 * R ** 4);
         end loop;
         if not (R >= 0.0 and then R < 10.0) then
            return Real (Background);
         end if;
         if RD > 0.0 then
            HX := CX + (PX - CX) * R / RD;
            HY := CY + (PY - CY) * R / RD;
         else
            HX := PX;
            HY := PY;
         end if;
         Den := I31 * HX + I32 * HY + I33;
         U := (I11 * HX + I12 * HY + I13) / Den;
         V := (I21 * HX + I22 * HY + I23) / Den;
         if Den * I33 <= 0.0 then
            return Real (Background);
         elsif U >= 0.0 and then U < Real (Columns) and then V >= 0.0
           and then V < Real (Rows)
         then
            return (if (Integer (Real'Floor (U)) + Integer (Real'Floor (V)))
                         mod 2 = 0
                    then Real (Dark) else Real (Light));
         elsif U >= -Margin and then U < Real (Columns) + Margin
           and then V >= -Margin and then V < Real (Rows) + Margin
         then
            return Real (Light);
         end if;
         return Real (Background);
      end Value;
   begin
      for Y in 0 .. Hh - 1 loop
         for X in 0 .. W - 1 loop
            declare
               Sum : Real := 0.0;
            begin
               for SY in 0 .. Samples - 1 loop
                  for SX in 0 .. Samples - 1 loop
                     Sum := Sum
                       + Value (Real (X) - 0.5
                                  + (Real (SX) + 0.5) / Real (Samples),
                                Real (Y) - 0.5
                                  + (Real (SY) + 0.5) / Real (Samples));
                  end loop;
               end loop;
               Row (X) := Grey_8 (Sum / Real (Samples * Samples));
            end;
         end loop;
         Image.Set_Row (Y, Row);
      end loop;
   end Draw_Distorted_Board;

   procedure Model_Pixel
     (M    : Ks_Calib_Checkerboard_Warp_Model;
      I, J : Real;
      X, Y : out Real)
   is
      GX  : constant Real := (I - M.Grid_Center_X) / M.Grid_Scale;
      GY  : constant Real := (J - M.Grid_Center_Y) / M.Grid_Scale;
      W   : constant Real := 1.0 + M.H31 * GX + M.H32 * GY;
      A   : constant Real := (M.H11 * GX + M.H12 * GY + M.H13) / W;
      B   : constant Real := (M.H21 * GX + M.H22 * GY + M.H23) / W;
      Rho : constant Real := A * A + B * B;
      F   : constant Real := 1.0 + M.K1 * Rho + M.K2 * Rho * Rho;
   begin
      X := M.Center_X + M.Normalizer * F * A;
      Y := M.Center_Y + M.Normalizer * F * B;
   end Model_Pixel;
   --  The model's pixel of the grid point (I, J), by the formulas of the
   --  kernel's spec.

   procedure Lattice_Of
     (Width, Height : Natural;
      H             : Homography;
      L             : Lens;
      Columns, Rows : Positive;
      PX, PY        : Real;
      I, J          : out Integer;
      Distance      : out Real)
   is
      X, Y : Real;
      Best : Real := Real'Last;
   begin
      I := 1;
      J := 1;
      for B in 1 .. Rows - 1 loop
         for A in 1 .. Columns - 1 loop
            True_Corner (Width, Height, H, L, Real (A), Real (B), X, Y);
            if (X - PX) ** 2 + (Y - PY) ** 2 < Best then
               Best := (X - PX) ** 2 + (Y - PY) ** 2;
               I := A;
               J := B;
            end if;
         end loop;
      end loop;
      Distance := EF.Sqrt (Best);
   end Lattice_Of;
   --  The inner corner of the board nearest to the pixel (PX, PY).

   procedure Check_Warp_Fit
     (H               : Homography;
      L               : Lens;
      Noise_Level     : Real;
      K1_Tolerance    : Real;
      K2_Tolerance    : Real;
      RMS_Tolerance   : Real;
      Model_Tolerance : Real;
      What            : String)
   is
      Image   : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
      Calib   : Ks_Calib_Checkerboard;
      Linear  : Ks_Calib_Checkerboard;
      Model   : Ks_Calib_Checkerboard_Warp_Model;
      Worst   : Real := 0.0;
      Px, Py  : Real;
      Mx, My  : Real;
      Tx, Ty  : Real;
      Gi, Gj  : Integer;
      Li, Lj  : Integer;
      Off     : Real;
      Start   : Ada.Calendar.Time;
      Spent   : Duration;
   begin
      Draw_Distorted_Board (Image, H, L, 10, 7);
      if Noise_Level > 0.0 then
         AMV_Test_Images.Add_Noise (Image, Noise_Level, 5);
      end if;
      Calib.Set_Calibration_Image (Image);
      Calib.Set_Computation_Mode (Perspective_And_Radial_Warp);
      Start := Ada.Calendar.Clock;
      Calib.Calibrate;
      Spent := Ada.Calendar."-" (Ada.Calendar.Clock, Start);
      Model := Calib.Get_Computed_Warp_Model;
      Check (Calib.Num_Points = 54,
             What & ": 54 corners (found" & Calib.Num_Points'Image & ")");
      Check (abs (Model.K1 - L.K1) <= K1_Tolerance,
             What & ": K1 within" & K1_Tolerance'Image & " (K1"
             & Model.K1'Image & ")");
      Check (abs (Model.K2 - L.K2) <= K2_Tolerance,
             What & ": K2 within" & K2_Tolerance'Image & " (K2"
             & Model.K2'Image & ")");
      Check (Calib.Computed_RMS_Error <= RMS_Tolerance
             and then Calib.Computed_RMS_Error = Model.RMS_Error,
             What & ": RMS error" & Calib.Computed_RMS_Error'Image);
      --  The model against the true corners: each detected corner's grid
      --  point, through the model, lands on the board's corner the
      --  corner belongs to.
      for K in 0 .. Calib.Num_Points - 1 loop
         Calib.Get_Corner (K, Px, Py, Gi, Gj);
         Lattice_Of (640, 480, H, L, 10, 7, Px, Py, Li, Lj, Off);
         Model_Pixel (Model, Real (Gi), Real (Gj), Mx, My);
         True_Corner (640, 480, H, L, Real (Li), Real (Lj), Tx, Ty);
         Worst := Real'Max (Worst, EF.Sqrt ((Mx - Tx) ** 2 + (My - Ty) ** 2));
      end loop;
      Check (Worst <= Model_Tolerance,
             What & ": the model within" & Model_Tolerance'Image
             & " px of every true corner (worst"
             & Integer'Image (Integer (Worst * 1000.0)) & " mpx)");
      --  The linear model leaves the distortion (and the perspective).
      Linear.Set_Calibration_Image (Image);
      Linear.Calibrate;
      if L.K1 /= 0.0 then
         Check (Linear.Computed_RMS_Error > 10.0 * Model.RMS_Error,
                What & ": the linear model leaves ten times the error");
      end if;
      Ada.Text_IO.Put_Line
        ("  " & What & ": K1" & Model.K1'Image & " K2" & Model.K2'Image
         & ", RMS" & Integer'Image (Integer (Model.RMS_Error * 1000.0))
         & " mpx (linear"
         & Integer'Image (Integer (Linear.Computed_RMS_Error * 1000.0))
         & "), model error" & Integer'Image (Integer (Worst * 1000.0))
         & " mpx," & Model.Iterations'Image & " steps,"
         & Integer'Image (Integer (Spent * 1000.0)) & " ms");
   exception
      when E : others =>
         Fail (What & ": " & Ada.Exceptions.Exception_Name (E) & " "
               & Ada.Exceptions.Exception_Message (E));
   end Check_Warp_Fit;

   --  The tolerances. The corners are found to about 0.05 pixel (0.1
   --  under strong perspective, Test_Checkerboard_Boards), so the RMS
   --  distance between them and the fitted model is of that order (the
   --  noise of 12 grey levels roughly doubles it), and so is the distance
   --  between the model and the true corners. The board's inner corners
   --  reach about 0.6 of the half diagonal from the centre (r**2 <= 0.36,
   --  r**4 <= 0.13), where K2 is hard to tell from K1 and the scale of the
   --  homography: a change of K2 by 0.02 is matched by K1 and the
   --  homography to within a few hundredths of a pixel at every corner.
   --  K1 itself is held to 0.01 (4 pixels at the image's corner, 0.9 at
   --  the farthest corner of the board, where most of it is matched by
   --  K2 too), K2 to 0.02.

   procedure Test_Radial_Fit is
      Barrel     : constant Lens := (K1 => -0.15, K2 => 0.03);
      Pincushion : constant Lens := (K1 => 0.08, K2 => 0.0);
   begin
      Section ("Lens distortion: the fit on rendered boards");
      Check_Warp_Fit (Board (45.0, Deg (4.0), 95.0, 85.0), Barrel, 0.0,
                      0.01, 0.02, 0.06, 0.08, "barrel, frontal");
      Check_Warp_Fit (Board (45.0, Deg (-6.0), 100.0, 110.0), Pincushion,
                      0.0, 0.01, 0.02, 0.06, 0.08, "pincushion, frontal");
      Check_Warp_Fit
        (Board (46.0, Deg (8.0), 120.0, 80.0, P => 0.012, Q => 0.008),
         Barrel, 0.0, 0.01, 0.02, 0.06, 0.15, "barrel, tilted");
      Check_Warp_Fit
        (Board (48.0, Deg (-10.0), 110.0, 140.0, P => -0.01, Q => 0.015),
         Pincushion, 0.0, 0.01, 0.02, 0.06, 0.15, "pincushion, tilted");
      Check_Warp_Fit
        (Board (44.0, Deg (3.0), 105.0, 90.0, P => 0.006, Q => 0.004),
         (K1 => -0.25, K2 => 0.05), 0.0, 0.01, 0.02, 0.06, 0.15,
         "strong barrel, tilted");
      Check_Warp_Fit (Board (45.0, Deg (4.0), 95.0, 85.0), (others => 0.0),
                      0.0, 0.01, 0.02, 0.06, 0.08, "no distortion");

      Section ("Lens distortion: the fit with noise");
      Check_Warp_Fit (Board (45.0, Deg (4.0), 95.0, 85.0), Barrel, 12.0,
                      0.015, 0.03, 0.1, 0.15, "barrel, noise 12");
      Check_Warp_Fit
        (Board (48.0, Deg (-10.0), 110.0, 140.0, P => -0.01, Q => 0.015),
         Pincushion, 12.0, 0.015, 0.03, 0.1, 0.25,
         "pincushion, tilted, noise 12");
   end Test_Radial_Fit;

   procedure Check_Warp_Output
     (H              : Homography;
      L              : Lens;
      Tile_X, Tile_Y : Real;
      What           : String)
   is
      Image   : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
      Tool    : Ks_Calib_Checkerboard_Tool;
      Again   : Ks_Calib_Checkerboard;
      Input   : Ks_Calib_Checkerboard;
      Output  : Ks_Image_8_Grey;
      Px, Py  : Real;
      Cx, Cy  : Real;
      Ux, Uy  : Real;
      Ix, Iy  : Real;
      Gi, Gj  : Integer;
      Li, Lj  : Integer;
      Off     : Real;
      Inside  : Boolean;
      Worst_Lattice : Real := 0.0;
      Worst_Map     : Real := 0.0;
      Worst_Back    : Real := 0.0;
      Start   : Ada.Calendar.Time;
      Spent   : Duration;
   begin
      Draw_Distorted_Board (Image, H, L, 10, 7);
      Tool.Calibration.Set_Calibration_Image (Image);
      Tool.Calibration.Set_Physical_Tile_Size_X (Tile_X);
      Tool.Calibration.Set_Physical_Tile_Size_Y (Tile_Y);
      Tool.Calibration.Set_Computation_Mode (Perspective_And_Radial_Warp);
      Tool.Calibration.Calibrate;
      Tool.Input_Image := Image;
      Start := Ada.Calendar.Clock;
      Tool.Run;
      Spent := Ada.Calendar."-" (Ada.Calendar.Clock, Start);
      Check (Tool.Run_Status.Result = Accept_Result,
             What & ": the tool runs (" & Tool.Run_Status.Message
             & ")");
      if Tool.Run_Status.Result /= Accept_Result then
         return;
      end if;
      Check (Tool.Output_Image.Width = 640
             and then Tool.Output_Image.Height = 480,
             What & ": the output has the input's size");
      Check (Tool.Output_Image.Selected_Space_Name
             = "@\Checkerboard Calibration",
             What & ": the calibrated space selected");

      --  The corners found again in the output, in its pixels, lie on a
      --  regular grid: an affine fit leaves little.
      Output := Tool.Output_Image;
      Output.Set_Selected_Space_Name ("#");
      Again.Set_Calibration_Image (Output);
      Again.Calibrate;
      Input.Set_Calibration_Image (Image);
      Input.Calibrate;
      Check (Again.Num_Points = 54,
             What & ": 54 corners in the output (found"
             & Again.Num_Points'Image & ")");
      Check (Again.Computed_RMS_Error <= 0.1,
             What & ": the output's corners on an affine grid (RMS"
             & Integer'Image (Integer (Again.Computed_RMS_Error * 1000.0))
             & " mpx, the input's"
             & Integer'Image (Integer (Input.Computed_RMS_Error * 1000.0))
             & " mpx)");

      --  Each of them, in the output's calibrated space, lies on a
      --  multiple of the tile sizes; and the input pixel it shows is the
      --  true corner.
      for K in 0 .. Again.Num_Points - 1 loop
         Again.Get_Corner (K, Px, Py, Gi, Gj);
         Map_Point (Tool.Output_Image.Get_Transform (".", "#"), Px, Py,
                    Cx, Cy);
         Map_Point (Tool.Output_Image.Get_Transform ("#", "."),
                    Tile_X * Real'Rounding (Cx / Tile_X),
                    Tile_Y * Real'Rounding (Cy / Tile_Y), Ux, Uy);
         Worst_Lattice := Real'Max
           (Worst_Lattice, EF.Sqrt ((Ux - Px) ** 2 + (Uy - Py) ** 2));
         Tool.Calibration.Map_Output_Pixel (Px, Py, Ix, Iy, Inside);
         Lattice_Of (640, 480, H, L, 10, 7, Ix, Iy, Li, Lj, Off);
         Worst_Map := Real'Max (Worst_Map, (if Inside then Off else 1.0E9));
         --  And back: the input pixel maps to the output pixel again.
         if Inside then
            declare
               Bx, By  : Real;
               Back_In : Boolean;
            begin
               Tool.Calibration.Map_Input_Pixel (Ix, Iy, Bx, By, Back_In);
               Worst_Back := Real'Max
                 (Worst_Back,
                  (if Back_In then EF.Sqrt ((Bx - Px) ** 2 + (By - Py) ** 2)
                   else 1.0E9));
            end;
         end if;
      end loop;
      Check (Worst_Back <= 1.0E-6,
             What & ": Map_Input_Pixel inverts Map_Output_Pixel (worst"
             & Worst_Back'Image & " px)");
      --  Both add the error of finding the corners again in the resampled
      --  output (about 0.05 pixel, 0.1 under perspective) to the model's
      --  (Test_Radial_Fit: up to 0.15 pixel under perspective); the map
      --  back to the input adds both, the lattice in the output only the
      --  first and the model's error scaled into the output.
      Check (Worst_Lattice <= 0.15,
             What & ": the output's corners on the calibrated lattice (worst"
             & Integer'Image (Integer (Worst_Lattice * 1000.0)) & " mpx)");
      Check (Worst_Map <= 0.25,
             What & ": the output's corners show the true corners (worst"
             & Integer'Image (Integer (Worst_Map * 1000.0)) & " mpx)");
      Ada.Text_IO.Put_Line
        ("  " & What & ": warp of 640 x 480 in"
         & Integer'Image (Integer (Spent * 1000.0)) & " ms; output grid RMS"
         & Integer'Image (Integer (Again.Computed_RMS_Error * 1000.0))
         & " mpx (input"
         & Integer'Image (Integer (Input.Computed_RMS_Error * 1000.0))
         & "), lattice" & Integer'Image (Integer (Worst_Lattice * 1000.0))
         & " mpx, map" & Integer'Image (Integer (Worst_Map * 1000.0))
         & " mpx");
   exception
      when E : others =>
         Fail (What & ": " & Ada.Exceptions.Exception_Name (E) & " "
               & Ada.Exceptions.Exception_Message (E));
   end Check_Warp_Output;

   procedure Test_Radial_Tool is
   begin
      Section ("Lens distortion: the warped output image");
      Check_Warp_Output (Board (45.0, Deg (4.0), 95.0, 85.0),
                         (K1 => -0.15, K2 => 0.03), 2.5, 2.5,
                         "barrel, frontal");
      Check_Warp_Output
        (Board (48.0, Deg (-10.0), 110.0, 140.0, P => -0.01, Q => 0.015),
         (K1 => 0.08, K2 => 0.0), 3.0, 3.0, "pincushion, tilted");
      Check_Warp_Output
        (Board (46.0, Deg (8.0), 120.0, 80.0, P => 0.012, Q => 0.008),
         (K1 => -0.15, K2 => 0.03), 2.0, 3.0, "barrel, tilted, tiles 2 x 3");

      Section ("Lens distortion: the tool's spaces and unfilled pixels");
      declare
         Image  : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
         Tool   : Ks_Calib_Checkerboard_Tool;
         Staged : Ks_Image_8_Grey;
         Stage  : constant AMV.Transforms.Ks_Transform_2D_Linear :=
           Create_Similarity (0.5, -0.3, 40.0, 25.0);
         Ix, Iy : Real;
         Inside : Boolean;
         Pixel_From_Calibrated : AMV.Transforms.Ks_Transform_2D_Linear;
      begin
         Draw_Distorted_Board
           (Image, Board (45.0, Deg (-6.0), 100.0, 110.0),
            (K1 => 0.08, K2 => 0.0), 10, 7);
         Tool.Calibration.Set_Calibration_Image (Image);
         Tool.Calibration.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Tool.Calibration.Calibrate;
         Tool.Input_Image := Image;
         Tool.Run_Params.Unfilled_Pel_Value := 77;
         Tool.Run_Params.Unfilled_Pel_Value_Enabled := True;
         Tool.Run;
         Check (Tool.Run_Status.Result = Accept_Result, "pincushion: runs");
         --  Pincushion distortion moves the image's corners outward: the
         --  output's corner shows a point outside the input.
         Tool.Calibration.Map_Output_Pixel (0.0, 0.0, Ix, Iy, Inside);
         Check (not Inside or else Ix < -0.5 or else Iy < -0.5,
                "pincushion: the output's corner shows nothing");
         Check (Tool.Output_Image.Get_Pixel (0, 0) = 77,
                "pincushion: an unfilled pixel gets UnfilledPelValue");
         Tool.Run_Params.Unfilled_Pel_Value_Enabled := False;
         Tool.Run;
         Check (Tool.Output_Image.Get_Pixel (0, 0) = 0,
                "pincushion: 0 when UnfilledPelValueEnabled is False");
         --  The output pixels from calibrated coordinates are the model's
         --  similarity, here through pixel space.
         Pixel_From_Calibrated :=
           Tool.Calibration.Get_Output_Pixel_From_Calibrated_Transform;
         Check_Transform (Tool.Output_Image.Get_Transform ("#", "."),
                          Kernel_Of (Pixel_From_Calibrated), 1.0E-9,
                          "pixels from calibrated coordinates");
         Check (abs (Pixel_From_Calibrated.Scaling_X
                     - Pixel_From_Calibrated.Scaling_Y) < 1.0E-9
                and then abs Pixel_From_Calibrated.Skew < 1.0E-9,
                "the output's calibrated space is a similarity of its pixels");
         --  A selected space on the images: the calibrated space is added
         --  under it, and still maps to the output's pixels exactly.
         Staged := Image;
         Staged.Coordinate_Space_Tree.Add_Space ("@", "Stage", Stage);
         Staged.Set_Selected_Space_Name ("@\Stage");
         Tool.Calibration.Set_Calibration_Image (Staged);
         Tool.Calibration.Calibrate;
         Tool.Input_Image := Staged;
         Tool.Run;
         Check (Tool.Output_Image.Selected_Space_Name
                = "@\Stage\Checkerboard Calibration",
                "warp: the calibrated space under the stage");
         Check_Transform
           (Tool.Output_Image.Get_Transform ("#", "."),
            Kernel_Of (Tool.Calibration
                         .Get_Output_Pixel_From_Calibrated_Transform),
            1.0E-9, "warp: pixels from calibrated through the stage");
         --  A different input size.
         Tool.Input_Image := AMV_Test_Images.Blank (320, 240);
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Exception_Name
                           = "AMV.KS_BAD_PARAMETER_EXCEPTION"
                and then not Tool.Output_Image.Allocated,
                "warp: an input of another size");
         Tool.Input_Image := Staged;
         Tool.Run_Params.Unfilled_Pel_Value := 300;
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Message
                           = "RunParams.UnfilledPelValue must be in 0 .. 255",
                "warp: UnfilledPelValue 300");
      end;
   end Test_Radial_Tool;

   procedure Test_Radial_Modes_And_Streams is
      Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
      H     : constant Homography :=
        Board (46.0, Deg (8.0), 120.0, 80.0, P => 0.012, Q => 0.008);
      Calib : Ks_Calib_Checkerboard;
   begin
      Draw_Distorted_Board (Image, H, (K1 => -0.15, K2 => 0.03), 10, 7);

      Section ("Lens distortion: the computation mode");
      Check (Calib.Computation_Mode = Linear, "the default mode is Linear");
      Calib.Set_Calibration_Image (Image);
      Calib.Calibrate;
      declare
         Linear_T   : constant KT.Ks_Transform_2D_Linear :=
           Kernel_Of (Calib.Get_Computed_Uncalibrated_From_Calibrated_Transform);
         Linear_RMS : constant Real := Calib.Computed_RMS_Error;
      begin
         Calib.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Check (not Calib.Calibrated and then Calib.Num_Points = 0,
                "setting the mode uncalibrates");
         Calib.Calibrate;
         Check (Calib.Calibrated
                and then Calib.Computed_RMS_Error < Linear_RMS / 10.0,
                "the warp mode fits the distortion");
         Calib.Set_Computation_Mode (Linear);
         Calib.Calibrate;
         Check (Kernel_Of (Calib
                  .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                = Linear_T and then Calib.Computed_RMS_Error = Linear_RMS,
                "back in the linear mode, the same fit as before");
         begin
            declare
               Unused : constant Ks_Calib_Checkerboard_Warp_Model :=
                 Calib.Get_Computed_Warp_Model;
            begin
               Fail ("the linear mode has no warp model");
            end;
         exception
            when AMV.Ks_Bad_Parameter_Exception =>
               Check (True, "the linear mode has no warp model");
         end;
      end;
      for Mode in Linescan_Warp .. No_Distortion_Warp loop
         begin
            Calib.Set_Computation_Mode (Mode);
            Fail ("the mode " & Mode'Image & " is not supported");
         exception
            when E : AMV.Ks_Bad_Parameter_Exception =>
               Check (Calib.Computation_Mode = Linear
                      and then Ada.Exceptions.Exception_Message (E)'Length
                                 > 20
                      and then Ada.Exceptions.Exception_Message (E)
                                 (1 .. 16) = "ComputationMode ",
                      "the mode " & Mode'Image & " is not supported ("
                      & Ada.Exceptions.Exception_Message (E) & ")");
         end;
      end loop;

      Section ("Lens distortion: failures");
      declare
         Blank : Ks_Calib_Checkerboard;
      begin
         Blank.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Blank.Set_Calibration_Image (AMV_Test_Images.Blank (100, 100, 90));
         Blank.Calibrate;
         Fail ("a blank image");
      exception
         when E : AMV.Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E)
                   = "CalibrationImage: fewer than 9 checkerboard corners "
                     & "were found", "warp: a blank image");
      end;
      declare
         Row   : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
         Lined : Ks_Calib_Checkerboard;
      begin
         --  A board of one row of inner corners: no grid of 9 corners.
         AMV_Test_Images.Draw_Board
           (Row, Board (40.0, 0.0, 120.0, 200.0), 11, 2);
         Lined.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Lined.Set_Calibration_Image (Row);
         Lined.Calibrate;
         Fail ("corners on one line");
      exception
         when AMV.Ks_Bad_Parameter_Exception =>
            Check (True, "warp: corners on one line");
      end;
      declare
         Uneven : Ks_Calib_Checkerboard;
      begin
         Uneven.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Uneven.Set_Calibration_Image (Image);
         Uneven.Set_Physical_Tile_Size_X (1.0);
         Uneven.Set_Physical_Tile_Size_Y (2000.0);
         Uneven.Calibrate;
         Fail ("tile sizes 1 and 2000");
      exception
         when E : AMV.Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E)
                   = "PhysicalTileSizeX and PhysicalTileSizeY must be "
                     & "within a factor of 1024 of each other "
                     & "(PerspectiveAndRadialWarp)",
                   "warp: tile sizes 1 and 2000");
      end;
      declare
         Fresh : Ks_Calib_Checkerboard;
         X, Y  : Real;
         In_It : Boolean;
      begin
         Fresh.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Fresh.Map_Output_Pixel (1.0, 1.0, X, Y, In_It);
         Fail ("an uncalibrated model");
      exception
         when AMV.Ks_Operator_Not_Trained_Exception =>
            Check (True, "warp: no model before Calibrate");
      end;
      declare
         Warped : Ks_Calib_Checkerboard;
         X, Y   : Real;
         In_It  : Boolean;
      begin
         Warped.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Warped.Set_Calibration_Image (Image);
         Warped.Calibrate;
         Warped.Map_Output_Pixel (NaN, 1.0, X, Y, In_It);
         Fail ("a NaN output pixel");
      exception
         when AMV.Ks_Bad_Parameter_Exception =>
            Check (True, "warp: a NaN output pixel");
      end;
      declare
         Warped : Ks_Calib_Checkerboard;
         X, Y   : Real;
         In_It  : Boolean;
      begin
         Warped.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Warped.Set_Calibration_Image (Image);
         Warped.Calibrate;
         --  Far beyond the image: beyond the model's valid radius.
         Warped.Map_Input_Pixel (1.0E8, -1.0E8, X, Y, In_It);
         Check (not In_It and then X = 0.0 and then Y = 0.0,
                "warp: an input pixel far beyond the image shows nowhere");
         Warped.Map_Input_Pixel (NaN, 1.0, X, Y, In_It);
         Fail ("a NaN input pixel");
      exception
         when AMV.Ks_Bad_Parameter_Exception =>
            Check (True, "warp: a NaN input pixel");
      end;

      Section ("Lens distortion: streams");
      declare
         S     : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Back  : Ks_Calib_Checkerboard;
         Code  : K.Int32;
         Tool  : Ks_Calib_Checkerboard_Tool;
         First, Second : Ks_Image_8_Grey;
         Same  : Boolean := True;
      begin
         Calib.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Calib.Calibrate;
         Ks_Calib_Checkerboard'Write (S'Access, Calib);
         Ks_Image_8_Grey'Read (S'Access, First);
         K.Int32'Read (S'Access, Code);
         Check (Code = KF.Calibration_Stream_Code_1,
                "the warp mode writes layout 1");
         S.Clear;
         Ks_Calib_Checkerboard'Write (S'Access, Calib);
         Ks_Calib_Checkerboard'Read (S'Access, Back);
         Check (Back.Calibrated
                and then Back.Computation_Mode = Perspective_And_Radial_Warp
                and then Back.Num_Points = Calib.Num_Points
                and then Back.Get_Computed_Warp_Model
                           = Calib.Get_Computed_Warp_Model
                and then Kernel_Of
                           (Back
                            .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                         = Kernel_Of
                             (Calib
                              .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                and then Back.Computed_RMS_Error = Calib.Computed_RMS_Error,
                "a warp calibration reads back");
         Tool.Input_Image := Image;
         Tool.Calibration := Calib;
         Tool.Run;
         First := Tool.Output_Image;
         Tool.Calibration := Back;
         Tool.Run;
         Second := Tool.Output_Image;
         for Y in 0 .. 479 loop
            for X in 0 .. 639 loop
               Same := Same and then First.Get_Pixel (X, Y)
                                       = Second.Get_Pixel (X, Y);
            end loop;
         end loop;
         Check (Same, "the calibration read back warps the same");

         --  An uncalibrated calibration in the warp mode.
         S.Clear;
         Calib.Uncalibrate;
         Ks_Calib_Checkerboard'Write (S'Access, Calib);
         Ks_Calib_Checkerboard'Read (S'Access, Back);
         Check (not Back.Calibrated
                and then Back.Computation_Mode = Perspective_And_Radial_Warp,
                "an uncalibrated warp calibration reads back");

         --  The linear mode still writes layout 0.
         S.Clear;
         Calib.Set_Computation_Mode (Linear);
         Calib.Calibrate;
         Ks_Calib_Checkerboard'Write (S'Access, Calib);
         Ks_Image_8_Grey'Read (S'Access, First);
         K.Int32'Read (S'Access, Code);
         Check (Code = KF.Calibration_Stream_Code,
                "the linear mode writes layout 0");
         S.Clear;
         Ks_Calib_Checkerboard'Write (S'Access, Calib);
         Ks_Calib_Checkerboard'Read (S'Access, Back);
         Check (Back.Calibrated and then Back.Computation_Mode = Linear
                and then Kernel_Of
                           (Back
                            .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                         = Kernel_Of
                             (Calib
                              .Get_Computed_Uncalibrated_From_Calibrated_Transform),
                "a linear calibration reads back");
      end;
      declare
         --  A stream in layout 0 as AMV wrote it before the computation
         --  modes: a calibrated checkerboard calibration of nine corners
         --  (DOF Translation, tiles 2 x 3), written field by field.
         S    : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Back : Ks_Calib_Checkerboard;
         T    : AMV.Transforms.Ks_Transform_2D_Linear;
         Px, Py : Real;
         I, J   : Integer;
         No_Image : Ks_Image_8_Grey;
      begin
         --  The calibration image (none), then the calibration.
         Ks_Image_8_Grey'Write (S'Access, No_Image);
         K.Int32'Write (S'Access, 16#4B43_4C00#);
         K.Int32'Write (S'Access, 1);   --  checkerboard
         K.Int32'Write (S'Access, 9);   --  corners
         K.Int32'Write (S'Access, 1);   --  calibrated
         K.Int32'Write (S'Access, 3);   --  DOF Translation
         Real'Write (S'Access, 2.0);
         Real'Write (S'Access, 3.0);
         K.Int32'Write (S'Access, 100);
         K.Int32'Write (S'Access, 80);
         for Row in -1 .. 1 loop
            for Column in -1 .. 1 loop
               Real'Write (S'Access, 50.0 + 2.0 * Real (Column));
               Real'Write (S'Access, 40.0 + 3.0 * Real (Row));
               K.Int32'Write (S'Access, K.Int32 (Column));
               K.Int32'Write (S'Access, K.Int32 (Row));
               Real'Write (S'Access, 50.0 + 2.0 * Real (Column));
               Real'Write (S'Access, 40.0 + 3.0 * Real (Row));
            end loop;
         end loop;
         for V of Point_List'[1.0, 0.0, 0.0, 1.0, 50.0, 40.0,   --  transform
                              0.0, 1.0, 1.0, 0.0, 0.0]          --  RMS ...
         loop
            Real'Write (S'Access, V);
         end loop;
         Ks_Calib_Checkerboard'Read (S'Access, Back);
         T := Back.Get_Computed_Uncalibrated_From_Calibrated_Transform;
         Back.Get_Corner (4, Px, Py, I, J);
         Check (Back.Calibrated and then Back.Computation_Mode = Linear
                and then Back.Num_Points = 9
                and then Back.DOFs_To_Compute = Translation
                and then Back.Physical_Tile_Size_Y = 3.0
                and then T.Translation_X = 50.0 and then T.Translation_Y = 40.0
                and then Px = 50.0 and then Py = 40.0 and then I = 0
                and then J = 0
                and then Back.Get_Raw_Calibrated_Point_Y (8) = 3.0,
                "an old (layout 0) stream reads back");
      end;
      declare
         --  A layout 1 stream whose model is not the one its coefficients
         --  give (a valid radius changed by hand).
         S     : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Back  : Ks_Calib_Checkerboard;
         Bytes : Ada.Streams.Stream_Element_Array (1 .. 100_000);
         Last  : Ada.Streams.Stream_Element_Offset;
         Model : Ks_Calib_Checkerboard_Warp_Model;
      begin
         Calib.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Calib.Calibrate;
         Ks_Calib_Checkerboard'Write (S'Access, Calib);
         --  Everything up to the model, then a changed model.
         S.Read (Bytes, Last);
         Model := Calib.Get_Computed_Warp_Model;
         Model.Valid_Radius_Squared := Model.Valid_Radius_Squared / 2.0;
         S.Clear;
         declare
            Probe : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
            Probe_Bytes : Ada.Streams.Stream_Element_Array (1 .. 4_096);
            Probe_Last  : Ada.Streams.Stream_Element_Offset;
         begin
            Ks_Calib_Checkerboard_Warp_Model'Write (Probe'Access, Model);
            Probe.Read (Probe_Bytes, Probe_Last);
            S.Write (Bytes (1 .. Last - Probe_Last));
            S.Write (Probe_Bytes (1 .. Probe_Last));
         end;
         Ks_Calib_Checkerboard'Read (S'Access, Back);
         Fail ("a model that does not fit its coefficients");
      exception
         when AMV.Ks_Image_File_Exception =>
            Check (True, "a model that does not fit its coefficients is "
                         & "rejected");
      end;
   end Test_Radial_Modes_And_Streams;

   procedure Test_Radial_Kernel is
      Status   : K.Ks_Status;
      Calib    : KF.Ks_Calibration;
      Copy     : KF.Ks_Calibration;
      Mode     : K.Int32;
      Model    : KF.Ks_Radial_Warp_Model;
      Other    : KF.Ks_Radial_Warp_Model;
      Fit      : KF.Ks_N_Point_To_N_Point_Fit;
      X, Y     : Real;
      Inside   : K.Int32;
      Run      : KF.Ks_Calibration_Checkerboard_Run_Params;
      Tree     : KC.Ks_Coordinate_Space_Tree;
      Selected : KC.Ks_Space_Name := KI.Root_Space_Name;
      Output   : KI.Ks_Image_8_Grey;
      Image    : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
      Handle   : access constant KI.Ks_Image_8_Grey_Data;
      Ignored  : K.Ks_Status;
      Default  : constant KF.Ks_Radial_Warp_Model := (others => <>);
      type Code_List is array (Positive range <>) of K.Int32;

      function Failed (Code : K.Int32) return Boolean is
        (K.Valid (Status) and then Status.Failure = Code);
   begin
      Section ("Kernel: the computation mode and the model");
      KF.Calibration_Set_Computation_Mode (null, 2, Status);
      Check (Failed (K.Failure_Bad_Parameter), "mode: null");
      KF.Calibration_Computation_Mode (null, Mode, Status);
      Check (Failed (K.Failure_Bad_Parameter) and then Mode = 1,
             "mode of null");
      KF.Calibration_Computed_Warp_Model (null, Model, Status);
      Check (Failed (K.Failure_Bad_Parameter) and then Model = Default,
             "model: null");
      KF.Calibration_Map_Output_Pixel (null, 0.0, 0.0, X, Y, Inside, Status);
      Check (Failed (K.Failure_Bad_Parameter) and then Inside = 0
             and then X = 0.0 and then Y = 0.0, "map: null");

      KF.Calibration_Create (KF.Kind_Checkerboard, Calib, Status);
      for Code of Code_List'[-1, 0, 3, 4, 5, 6, 7, 8, K.Int32'Last] loop
         KF.Calibration_Set_Computation_Mode (Calib, Code, Status);
         Check (Failed (K.Failure_Bad_Parameter),
                "mode" & Code'Image & " is rejected");
      end loop;
      KF.Calibration_Computation_Mode (Calib, Mode, Status);
      Check (Mode = KF.Mode_Linear, "a rejected mode changes nothing");
      KF.Calibration_Set_Computation_Mode
        (Calib, KF.Mode_Perspective_And_Radial_Warp, Status);
      KF.Calibration_Computation_Mode (Calib, Mode, Status);
      Check (Failed (K.Failure_None)
             and then Mode = KF.Mode_Perspective_And_Radial_Warp,
             "the warp mode set");
      KF.Calibration_Map_Output_Pixel (Calib, 0.0, 0.0, X, Y, Inside, Status);
      Check (Failed (K.Failure_Operator_Not_Trained), "map: not calibrated");

      KF.Calibration_Checkerboard_Run_Params_Default (Run, Status);
      Check (Failed (K.Failure_None)
             and then KC.To_String (Run.Calibrated_Space_Name)
                        = "Checkerboard Calibration"
             and then Run.Unfilled_Pel_Value = 0
             and then Run.Unfilled_Pel_Value_Enabled = 0,
             "checkerboard tool defaults");
      KF.Calibration_Checkerboard_Tool_Execute
        (null, Calib, Run, Tree, Selected, Id, Output, Status);
      Check (Failed (K.Failure_Image_No_Pixels) and then Output = null,
             "tool: null image");
      Draw_Distorted_Board
        (Image, Board (45.0, Deg (4.0), 95.0, 85.0),
         (K1 => -0.15, K2 => 0.03), 10, 7);
      Handle := AMV.Images.Kernel_Images.Kernel_Handle (Image);
      KF.Calibration_Checkerboard_Tool_Execute
        (Handle, null, Run, Tree, Selected, Id, Output, Status);
      Check (Failed (K.Failure_Bad_Parameter) and then Output = null,
             "tool: null calibration");
      KF.Calibration_Checkerboard_Tool_Execute
        (Handle, Calib, Run, Tree, Selected, Id, Output, Status);
      Check (Failed (K.Failure_Operator_Not_Trained) and then Output = null,
             "tool: not calibrated");

      KF.Calibration_Calibrate (Calib, Handle, Id, Status);
      Check (Failed (K.Failure_None), "the warp calibrated");
      KF.Calibration_Computed_Warp_Model (Calib, Model, Status);
      KF.Calibration_Computed_Fit (Calib, Fit, Status);
      Check (Failed (K.Failure_None)
             and then Fit.Transform = Model.Output_Pixel_From_Calibrated,
             "with the identity from pixels, the fit's transform is the "
             & "output's");
      for Bad of Point_List'[NaN, Inf, -Inf, 2.0 ** 33] loop
         KF.Calibration_Map_Output_Pixel (Calib, Bad, 0.0, X, Y, Inside,
                                          Status);
         Check (Failed (K.Failure_Bad_Parameter) and then Inside = 0,
                "map: a bad X" & Bad'Image);
         KF.Calibration_Map_Output_Pixel (Calib, 0.0, Bad, X, Y, Inside,
                                          Status);
         Check (Failed (K.Failure_Bad_Parameter) and then Inside = 0,
                "map: a bad Y" & Bad'Image);
      end loop;
      --  Far outside the board the output shows nothing (behind the
      --  camera or beyond the valid radius), or a point far outside.
      KF.Calibration_Map_Output_Pixel (Calib, -1.0E9, 3.0E9, X, Y, Inside,
                                       Status);
      Check (Failed (K.Failure_None)
             and then (Inside = 0 or else abs X > 1.0E4
                       or else abs Y > 1.0E4),
             "map: a pixel far away");
      Run.Unfilled_Pel_Value := -1;
      KF.Calibration_Checkerboard_Tool_Execute
        (Handle, Calib, Run, Tree, Selected, Id, Output, Status);
      Check (Failed (K.Failure_Bad_Parameter) and then Output = null,
             "tool: UnfilledPelValue -1");
      Run.Unfilled_Pel_Value := 0;
      Run.Space_To_Output := 5;
      KF.Calibration_Checkerboard_Tool_Execute
        (Handle, Calib, Run, Tree, Selected, Id, Output, Status);
      Check (Failed (K.Failure_Bad_Parameter) and then Output = null,
             "tool: a bad SpaceToOutput frees the warped image");
      Run.Space_To_Output := 0;
      KF.Calibration_Checkerboard_Tool_Execute
        (Handle, Calib, Run, Tree, Selected, Id, Output, Status);
      Check (Failed (K.Failure_None) and then Output /= null
             and then Output.Width = 640 and then Output.Height = 480,
             "tool: the warped image");
      KI.Destroy (Output, Ignored);

      KF.Calibration_Duplicate (Calib, Copy, Status);
      KF.Calibration_Computed_Warp_Model (Copy, Other, Status);
      Check (Failed (K.Failure_None) and then Other = Model,
             "a duplicate keeps the model");
      KF.Calibration_Set_DOFs_To_Compute (Copy, 3, Status);
      KF.Calibration_Computed_Warp_Model (Copy, Other, Status);
      Check (Failed (K.Failure_Operator_Not_Trained) and then Other = Default,
             "a change uncalibrates and forgets the model");
      KF.Calibration_Calibrate (Copy, Handle, Id, Status);
      KF.Calibration_Computed_Fit (Copy, Fit, Status);
      Check (Failed (K.Failure_None),
             "the warp ignores DOFsToCompute (Translation here)");

      Section ("Kernel: restoring the model");
      KF.Restore_Mode (Copy, 9, Status);
      Check (Failed (K.Failure_Image_File), "restore: a bad mode");
      KF.Calibration_Uncalibrate (Copy, Status);
      KF.Restore_Model (Copy, Fit, Model, Status);
      Check (Failed (K.Failure_Image_File),
             "restore: a model without corners");
      KF.Restore_Model (null, Fit, Model, Status);
      Check (Failed (K.Failure_Image_File), "restore: null");
      KF.Calibration_Destroy (Copy);
      KF.Calibration_Destroy (Calib);
   end Test_Radial_Kernel;

   procedure Test_Radial_Adjustment is
      Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
      Tool  : Ks_Calib_Checkerboard_Tool;
      Raw   : AMV.Transforms.Ks_Transform_2D_Linear;
      T     : AMV.Transforms.Ks_Transform_2D_Linear;
      U, V  : Real;
      X, Y  : Real;
      Warp_Only : constant String :=
        "CalibratedOriginSpace and CalibratedXAxisRotationSpace must be "
        & "RawCalibrated in ComputationMode PerspectiveAndRadialWarp";
   begin
      Section ("Lens distortion: the origin adjustment");
      Draw_Distorted_Board
        (Image, Board (45.0, Deg (-6.0), 100.0, 110.0),
         (K1 => 0.08, K2 => 0.0), 10, 7);
      Tool.Calibration.Set_Calibration_Image (Image);
      Tool.Calibration.Set_Computation_Mode (Perspective_And_Radial_Warp);
      Tool.Calibration.Set_Physical_Tile_Size_X (2.0);
      Tool.Calibration.Set_Physical_Tile_Size_Y (2.0);
      Tool.Calibration.Calibrate;
      Raw := Tool.Calibration
               .Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform;
      Check (Kernel_Of (Tool.Calibration
               .Get_Computed_Uncalibrated_From_Calibrated_Transform)
             = Kernel_Of (Raw),
             "warp: the defaults give the output's transform itself");
      Tool.Calibration.Set_Calibrated_Origin_X (4.0);
      Tool.Calibration.Set_Calibrated_Origin_Y (6.0);
      Tool.Calibration.Set_Calibrated_X_Axis_Rotation (Deg (90.0));
      Tool.Calibration.Set_Swap_Calibrated_Handedness (True);
      Check (Tool.Calibration.Calibrated
             and then Tool.Calibration.Computation_Mode
                        = Perspective_And_Radial_Warp,
             "warp: the setters keep it calibrated");
      T := Tool.Calibration
             .Get_Computed_Uncalibrated_From_Calibrated_Transform;
      Check_Rigid (Raw_From_Calibrated (Raw, T), Deg (90.0), True, 4.0, 6.0,
                   "warp: an adjustment in raw calibrated space");
      Tool.Input_Image := Image;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Output_Image.Allocated,
             "warp: the tool runs with the adjustment");
      Check_Transform (Tool.Output_Image.Get_Transform ("#", "."),
                       Kernel_Of (T), 1.0E-12,
                       "warp: the output's calibrated space is F * R");
      --  The calibrated origin is the output pixel of the raw calibrated
      --  point (4, 6).
      Map_Point (Tool.Calibration.Get_Output_Pixel_From_Calibrated_Transform,
                 4.0, 6.0, U, V);
      Map_Point (Tool.Output_Image.Get_Transform (".", "#"), U, V, X, Y);
      Check (abs X < 1.0E-9 and then abs Y < 1.0E-9,
             "warp: the raw calibrated point (4, 6) is calibrated (0, 0)");

      Section ("Lens distortion: streams with an adjustment");
      declare
         S     : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Back  : Ks_Calib_Checkerboard;
         First : Ks_Image_8_Grey;
         Code  : K.Int32;
      begin
         Ks_Calib_Checkerboard'Write (S'Access, Tool.Calibration);
         Ks_Image_8_Grey'Read (S'Access, First);
         K.Int32'Read (S'Access, Code);
         Check (Code = KF.Calibration_Stream_Code_2,
                "warp with an adjustment: layout 2");
         S.Clear;
         Ks_Calib_Checkerboard'Write (S'Access, Tool.Calibration);
         Ks_Calib_Checkerboard'Read (S'Access, Back);
         Check (Back.Calibrated
                and then Back.Computation_Mode = Perspective_And_Radial_Warp
                and then Back.Get_Computed_Warp_Model
                           = Tool.Calibration.Get_Computed_Warp_Model
                and then Back.Calibrated_Origin_X = 4.0
                and then Back.Swap_Calibrated_Handedness
                and then Kernel_Of
                           (Back
                            .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                         = Kernel_Of (T),
                "warp with an adjustment: read back with its model");
      end;

      Section ("Lens distortion: no adjustment in the uncalibrated space");
      Tool.Calibration.Set_Calibrated_Origin_Space (Uncalibrated);
      Check (Tool.Calibration.Calibrated
             and then Tool.Calibration.Calibrated_Origin_Space = Uncalibrated,
             "warp: an uncalibrated origin space can be set");
      begin
         T := Tool.Calibration
                .Get_Computed_Uncalibrated_From_Calibrated_Transform;
         Fail ("warp: an uncalibrated origin space gives a transform");
      exception
         when E : AMV.Ks_Bad_Parameter_Exception =>
            Check (Ada.Exceptions.Exception_Message (E) = Warp_Only,
                   "warp: an uncalibrated origin space is refused ("
                   & Ada.Exceptions.Exception_Message (E) & ")");
      end;
      Check (Kernel_Of (Tool.Calibration
               .Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform)
             = Kernel_Of (Raw), "warp: the raw calibrated transform stays");
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Exception_Name
                        = "AMV.KS_BAD_PARAMETER_EXCEPTION"
             and then Tool.Run_Status.Message = Warp_Only
             and then not Tool.Output_Image.Allocated,
             "warp: the tool refuses an uncalibrated origin space");
      Tool.Calibration.Set_Calibrated_Origin_Space (Raw_Calibrated);
      Tool.Calibration.Set_Calibrated_X_Axis_Rotation_Space (Uncalibrated);
      Tool.Run;
      Check (Tool.Run_Status.Result = Error
             and then Tool.Run_Status.Message = Warp_Only
             and then not Tool.Output_Image.Allocated,
             "warp: the tool refuses an uncalibrated rotation space");
      --  The same calibration in the linear mode takes it.
      Tool.Calibration.Set_Computation_Mode (Linear);
      Tool.Calibration.Calibrate;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Calibration.Calibrated_X_Axis_Rotation_Space
                        = Uncalibrated,
             "linear: the uncalibrated rotation space is supported");
      Map_Point (Tool.Output_Image.Get_Transform ("#", "."), 0.0, 0.0, U, V);
      Map_Point (Tool.Output_Image.Get_Transform ("#", "."), 1.0, 0.0, X, Y);
      Check_Near (EF.Arctan (Y - V, X - U), Deg (90.0), 1.0E-9,
                  "linear: the calibrated x axis along 90 degrees in pixels");
   end Test_Radial_Adjustment;

   procedure Test_Adjustment_Kernel is
      Status : K.Ks_Status;
      Calib  : KF.Ks_Calibration;
      Copy   : KF.Ks_Calibration;
      A      : KF.Ks_Calibration_Adjustment;
      Got    : KF.Ks_Calibration_Adjustment;
      T      : KT.Ks_Transform_2D_Linear;
      Fit    : KF.Ks_N_Point_To_N_Point_Fit;
      Flag   : K.Int32;
      type Code_List is array (Positive range <>) of K.Int32;

      function Failed (Code : K.Int32) return Boolean is
        (K.Valid (Status) and then Status.Failure = Code);

      function Message_Is (Text : String) return Boolean is
        (Integer (Status.Length) = Text'Length
         and then String (Status.Message (1 .. Text'Length)) = Text);
   begin
      Section ("Kernel: the origin adjustment");
      Check (KF.Ks_Calibration_Adjustment'Object_Size = 40 * 8,
             "ks_calibration_adjustment is 40 bytes");
      KF.Calibration_Adjustment_Default (A, Status);
      Check (Failed (K.Failure_None) and then A = KF.Default_Adjustment
             and then A.Calibrated_Origin_X = 0.0
             and then A.Calibrated_Origin_Y = 0.0
             and then A.Calibrated_X_Axis_Rotation = 0.0
             and then A.Calibrated_Origin_Space
                        = KF.Adjustment_Space_Raw_Calibrated
             and then A.Calibrated_X_Axis_Rotation_Space
                        = KF.Adjustment_Space_Raw_Calibrated
             and then A.Swap_Calibrated_Handedness = K.False_Value,
             "the default adjustment");
      KF.Calibration_Get_Adjustment (null, Got, Status);
      Check (Failed (K.Failure_Bad_Parameter)
             and then Got = KF.Default_Adjustment, "get: null");
      KF.Calibration_Set_Adjustment (null, A, Status);
      Check (Failed (K.Failure_Bad_Parameter), "set: null");
      KF.Calibration_Computed_Uncalibrated_From_Calibrated (null, T, Status);
      Check (Failed (K.Failure_Bad_Parameter) and then T = Id,
             "the adjusted transform of null");

      --  An N-point calibration of one pair with DOF Translation: F is
      --  the shift (10, 20).
      KF.Calibration_Create (KF.Kind_N_Point_To_N_Point, Calib, Status);
      KF.Calibration_Get_Adjustment (Calib, Got, Status);
      Check (Failed (K.Failure_None) and then Got = KF.Default_Adjustment,
             "a new calibration has the defaults");
      KF.Calibration_Computed_Uncalibrated_From_Calibrated (Calib, T, Status);
      Check (Failed (K.Failure_Operator_Not_Trained) and then T = Id,
             "the adjusted transform needs a calibrated calibration");
      KF.Calibration_Add_Point_Pair (Calib, 10.0, 20.0, 0.0, 0.0, Status);
      KF.Calibration_Set_DOFs_To_Compute (Calib, KF.DOF_Translation, Status);
      KF.Calibration_Calibrate (Calib, null, Id, Status);
      Check (Failed (K.Failure_None), "a shift calibrated");

      for Code of Code_List'[-1, 2, K.Int32'Last] loop
         KF.Calibration_Set_Adjustment
           (Calib, (A with delta Calibrated_Origin_Space => Code), Status);
         Check (Failed (K.Failure_Bad_Parameter)
                and then Message_Is ("CalibratedOriginSpace must be 0 "
                                     & "(RawCalibrated) or 1 (Uncalibrated)"),
                "origin space" & Code'Image & " is refused");
         KF.Calibration_Set_Adjustment
           (Calib, (A with delta Calibrated_X_Axis_Rotation_Space => Code),
            Status);
         Check (Failed (K.Failure_Bad_Parameter)
                and then Message_Is ("CalibratedXAxisRotationSpace must be 0 "
                                     & "(RawCalibrated) or 1 (Uncalibrated)"),
                "rotation space" & Code'Image & " is refused");
         KF.Calibration_Set_Adjustment
           (Calib, (A with delta Swap_Calibrated_Handedness => Code), Status);
         Check (Failed (K.Failure_Bad_Parameter)
                and then Message_Is
                           ("SwapCalibratedHandedness must be 0 or 1"),
                "swap flag" & Code'Image & " is refused");
      end loop;
      for Bad of Point_List'[NaN, Inf, -Inf, 2.0E150, -1.1E150] loop
         KF.Calibration_Set_Adjustment
           (Calib, (A with delta Calibrated_Origin_X => Bad), Status);
         Check (Failed (K.Failure_Bad_Parameter), "origin X" & Bad'Image);
         KF.Calibration_Set_Adjustment
           (Calib, (A with delta Calibrated_Origin_Y => Bad), Status);
         Check (Failed (K.Failure_Bad_Parameter), "origin Y" & Bad'Image);
      end loop;
      for Bad of Point_List'[NaN, Inf, -Inf] loop
         KF.Calibration_Set_Adjustment
           (Calib, (A with delta Calibrated_X_Axis_Rotation => Bad), Status);
         Check (Failed (K.Failure_Bad_Parameter), "rotation" & Bad'Image);
      end loop;
      KF.Calibration_Get_Adjustment (Calib, Got, Status);
      KF.Calibration_Calibrated (Calib, Flag, Status);
      Check (Got = KF.Default_Adjustment and then Flag = K.True_Value,
             "refused adjustments change nothing");

      KF.Calibration_Set_Adjustment
        (Calib, (A with delta Calibrated_Origin_X => 1.0E150,
                              Calibrated_X_Axis_Rotation => 1.0E300),
         Status);
      KF.Calibration_Get_Adjustment (Calib, Got, Status);
      Check (Failed (K.Failure_None)
             and then Got.Calibrated_Origin_X = 1.0E150
             and then Got.Calibrated_X_Axis_Rotation > -Pi
             and then Got.Calibrated_X_Axis_Rotation <= Pi,
             "the bound itself, and a huge rotation reduced");
      KF.Calibration_Set_Adjustment
        (Calib, (A with delta Calibrated_Origin_Space =>
                                KF.Adjustment_Space_Uncalibrated,
                              Calibrated_Origin_X => 15.0,
                              Calibrated_Origin_Y => 25.0,
                              Swap_Calibrated_Handedness => K.True_Value),
         Status);
      KF.Calibration_Calibrated (Calib, Flag, Status);
      Check (Flag = K.True_Value, "set: still calibrated");
      KF.Calibration_Computed_Uncalibrated_From_Calibrated (Calib, T, Status);
      Check (Failed (K.Failure_None)
             and then T = (A => 1.0, B => 0.0, C => 0.0, D => -1.0,
                           Translation_X => 15.0, Translation_Y => 25.0),
             "a shift: the origin at the pixel (15, 25), y swapped");
      KF.Calibration_Computed_Fit (Calib, Fit, Status);
      Check (Fit.Transform
               = (A => 1.0, B => 0.0, C => 0.0, D => 1.0,
                  Translation_X => 10.0, Translation_Y => 20.0),
             "the computed fit stays the shift");

      KF.Calibration_Duplicate (Calib, Copy, Status);
      KF.Calibration_Get_Adjustment (Copy, A, Status);
      KF.Calibration_Get_Adjustment (Calib, Got, Status);
      Check (A = Got, "a duplicate has the adjustment");
      KF.Calibration_Uncalibrate (Copy, Status);
      KF.Calibration_Get_Adjustment (Copy, A, Status);
      Check (A = Got, "uncalibrate keeps the adjustment");

      Section ("Kernel: restoring the adjustment");
      KF.Restore_Adjustment (null, Got, Status);
      Check (Failed (K.Failure_Image_File), "restore: null");
      KF.Restore_Adjustment
        (Copy, (Got with delta Calibrated_X_Axis_Rotation => 3.5), Status);
      Check (Failed (K.Failure_Image_File),
             "restore: a rotation that is not reduced");
      KF.Restore_Adjustment
        (Copy, (Got with delta Calibrated_Origin_Y => NaN), Status);
      Check (Failed (K.Failure_Image_File), "restore: a NaN origin");
      KF.Restore_Adjustment (Copy, KF.Default_Adjustment, Status);
      KF.Calibration_Get_Adjustment (Copy, A, Status);
      Check (Failed (K.Failure_None) and then A = KF.Default_Adjustment,
             "restore: the defaults");
      Check (KF.Stream_Code (KF.Mode_Linear, KF.Default_Adjustment)
               = KF.Calibration_Stream_Code
             and then KF.Stream_Code (KF.Mode_Perspective_And_Radial_Warp,
                                      KF.Default_Adjustment)
                        = KF.Calibration_Stream_Code_1
             and then KF.Stream_Code (KF.Mode_Linear, Got)
                        = KF.Calibration_Stream_Code_2
             and then not KF.Stream_Has_Model
                            (KF.Calibration_Stream_Code_2, KF.Mode_Linear)
             and then KF.Stream_Has_Model
                        (KF.Calibration_Stream_Code_2,
                         KF.Mode_Perspective_And_Radial_Warp),
             "the stream layouts");
      KF.Calibration_Destroy (Copy);
      KF.Calibration_Destroy (Calib);
   end Test_Adjustment_Kernel;

   ---------------------------------------------------------------------
   --  The kernel
   ---------------------------------------------------------------------

   procedure Test_Kernel is
      Status : K.Ks_Status;
      Pairs  : KF.Ks_Point_Pairs;
      Copy   : KF.Ks_Point_Pairs;
      Count  : K.Int32;
      X, Y   : Real;
      Fit    : KF.Ks_N_Point_To_N_Point_Fit;
      Calib  : KF.Ks_Calibration;
      Flag   : K.Int32;

      function Failed (Code : K.Int32) return Boolean is
        (Status.Failure = Code);
   begin
      Section ("Kernel: point pairs");
      KF.Pairs_Num_Points (null, Count, Status);
      Check (Failed (K.Failure_None) and then Count = 0, "null: no pairs");
      KF.Pairs_Get_Point (null, 0, KF.Group_A, X, Y, Status);
      Check (Failed (K.Failure_Index_Out_Of_Range), "null: get fails");
      KF.Pairs_Add_Point_Pair (Pairs, 1.0, 2.0, 3.0, 4.0, Status);
      Check (Failed (K.Failure_None) and then Pairs /= null,
             "add creates the handle");
      KF.Pairs_Add_Point_Pair (Pairs, Inf, 2.0, 3.0, 4.0, Status);
      Check (Failed (K.Failure_Bad_Parameter), "an infinite coordinate");
      KF.Pairs_Add_Point_Pair (Pairs, 1.0, 2.0, 3.0, 2.0E150, Status);
      Check (Failed (K.Failure_Bad_Parameter), "beyond the bound");
      KF.Pairs_Get_Point (Pairs, 0, 2, X, Y, Status);
      Check (Failed (K.Failure_Bad_Parameter), "a bad group");
      KF.Pairs_Get_Point (Pairs, 0, KF.Group_B, X, Y, Status);
      Check (Failed (K.Failure_None) and then X = 3.0 and then Y = 4.0,
             "group B point");
      KF.Pairs_Set_Point (Pairs, 0, KF.Group_A, NaN, 0.0, Status);
      Check (Failed (K.Failure_Bad_Parameter), "set a NaN");
      KF.Pairs_Set_Point (Pairs, 1, KF.Group_A, 0.0, 0.0, Status);
      Check (Failed (K.Failure_Index_Out_Of_Range), "set beyond the end");
      KF.Pairs_Duplicate (Pairs, Copy, Status);
      Check (Failed (K.Failure_None) and then Copy /= null, "duplicate");
      KF.Pairs_Clear (Pairs, Status);
      KF.Pairs_Num_Points (Pairs, Count, Status);
      Check (Count = 0, "clear");
      KF.Pairs_Num_Points (Copy, Count, Status);
      Check (Count = 1, "the duplicate keeps its pair");
      KF.Pairs_Destroy (Pairs);
      KF.Pairs_Destroy (Copy);
      KF.Pairs_Destroy (Copy);
      Check (Pairs = null and then Copy = null, "destroy (twice)");

      Section ("Kernel: the fit");
      KF.N_Point_To_N_Point_Compute (null, 8, Fit, Status);
      Check (Failed (K.Failure_Bad_Parameter), "an unknown DOF code");
      KF.N_Point_To_N_Point_Compute (null, -1, Fit, Status);
      Check (Failed (K.Failure_Bad_Parameter), "a negative DOF code");
      KF.N_Point_To_N_Point_Compute (null, KF.DOF_None, Fit, Status);
      Check (Failed (K.Failure_None) and then Fit.Transform = Id
             and then Fit.RMS_Error = 0.0, "none without points");
      KF.N_Point_To_N_Point_Compute (null, KF.DOF_Translation, Fit, Status);
      Check (Failed (K.Failure_Bad_Parameter)
             and then Status.Message (1 .. 40)
                        = "NumPoints must be at least 1 for these D",
             "translation without points");

      Section ("Kernel: the limit of pairs");
      declare
         Start : constant Ada.Calendar.Time := Ada.Calendar.Clock;
      begin
         for I in 1 .. KF.Max_Pairs loop
            KF.Pairs_Add_Point_Pair
              (Pairs, Real (I mod 1000), Real (I / 1000), Real (I mod 1000),
               Real (I / 1000), Status);
            exit when not K.Succeeded (Status);
         end loop;
         Check (Failed (K.Failure_None), "Max_Pairs pairs");
         KF.Pairs_Add_Point_Pair (Pairs, 0.0, 0.0, 0.0, 0.0, Status);
         Check (Failed (K.Failure_Bad_Parameter), "one more is refused");
         KF.N_Point_To_N_Point_Compute
           (Pairs, KF.DOF_Scaling_Aspect_Rotation_Skew_And_Translation, Fit,
            Status);
         Check (Failed (K.Failure_None)
                and then abs (Fit.Transform.A - 1.0) < 1.0E-9
                and then abs (Fit.Transform.D - 1.0) < 1.0E-9
                and then Fit.RMS_Error < 1.0E-6,
                "an affine fit of 524288 pairs");
         Ada.Text_IO.Put_Line
           ("  524288 pairs added and fitted:"
            & Duration'Image (Ada.Calendar."-" (Ada.Calendar.Clock, Start)
                              * 1000.0) & " ms");
         KF.Pairs_Destroy (Pairs);
      end;

      Section ("Kernel: calibrations");
      KF.Calibration_Create (2, Calib, Status);
      Check (Failed (K.Failure_Bad_Parameter) and then Calib = null,
             "a bad kind");
      KF.Calibration_Calibrated (null, Flag, Status);
      Check (Failed (K.Failure_None) and then Flag = K.False_Value,
             "null is not calibrated");
      KF.Calibration_Computed_Fit (null, Fit, Status);
      Check (Failed (K.Failure_Bad_Parameter), "null has no fit");
      KF.Calibration_Add_Point_Pair (null, 0.0, 0.0, 0.0, 0.0, Status);
      Check (Failed (K.Failure_Bad_Parameter), "null: add");
      KF.Calibration_Calibrate (null, null, Id, Status);
      Check (Failed (K.Failure_Bad_Parameter), "null: calibrate");
      KF.Calibration_Create (KF.Kind_Checkerboard, Calib, Status);
      Check (Failed (K.Failure_None), "a checkerboard calibration");
      KF.Calibration_Add_Point_Pair (Calib, 0.0, 0.0, 0.0, 0.0, Status);
      Check (Failed (K.Failure_Bad_Parameter),
             "a checkerboard calibration takes no point pairs");
      KF.Calibration_Set_Physical_Tile_Size (Calib, NaN, 1.0, Status);
      Check (Failed (K.Failure_Bad_Parameter), "a NaN tile size");
      KF.Calibration_Set_Physical_Tile_Size (Calib, 1.0, 2.0E140, Status);
      Check (Failed (K.Failure_Bad_Parameter), "a tile size beyond 1.0E140");
      KF.Calibration_Set_DOFs_To_Compute (Calib, 9, Status);
      Check (Failed (K.Failure_Bad_Parameter), "a bad DOF code");
      KF.Calibration_Computed_Fit (Calib, Fit, Status);
      Check (Failed (K.Failure_Operator_Not_Trained),
             "an uncalibrated calibration has no fit");
      KF.Calibration_Calibrate (Calib, null, Id, Status);
      Check (Failed (K.Failure_Image_No_Pixels), "no calibration image");
      declare
         Image : constant Ks_Image_8_Grey := AMV_Test_Images.Blank (60, 60);
      begin
         KF.Calibration_Calibrate
           (Calib, AMV.Images.Kernel_Images.Kernel_Handle (Image),
            (A => NaN, others => <>), Status);
         Check (Failed (K.Failure_Bad_Parameter),
                "a NaN transform to the selected space");
      end;
      KF.Calibration_Get_Corner (Calib, 0, X, Y, Count, Flag, Status);
      Check (Failed (K.Failure_Index_Out_Of_Range), "no corners");
      KF.Restore_Fit (Calib, (others => <>), Status);
      Check (Failed (K.Failure_Image_File),
             "restoring a fit without corners");
      KF.Restore_Corner (Calib, 10, 10, 9, 10.0, 1.0, 0, 0, 1.0, 1.0, Status);
      Check (Failed (K.Failure_Image_File), "restoring a corner outside");
      KF.Calibration_Destroy (Calib);
      Check (Calib = null, "destroy");

      Section ("Kernel: the tools");
      declare
         Tree     : KC.Ks_Coordinate_Space_Tree;
         Selected : KC.Ks_Space_Name := KI.Root_Space_Name;
         Params   : KF.Ks_Fixture_Run_Params;
         Image    : constant Ks_Image_8_Grey := AMV_Test_Images.Blank (8, 8);
         Handle   : constant access constant KI.Ks_Image_8_Grey_Data :=
           AMV.Images.Kernel_Images.Kernel_Handle (Image);
         Run      : KF.Ks_Calibration_Run_Params;
      begin
         KF.Fixture_Run_Params_Default (Params, Status);
         Check (Params.Fixtured_Space_Name.Length = 7
                and then Params.Space_To_Output = 0
                and then Params.Fixtured_Space_Name_Duplicate_Handling = 1,
                "fixture defaults");
         KF.Fixture_Execute (null, Params, Tree, Selected, Id, Status);
         Check (Failed (K.Failure_Image_No_Pixels), "fixture: null image");
         Params.Space_To_Output := 2;
         KF.Fixture_Execute (Handle, Params, Tree, Selected, Id, Status);
         Check (Failed (K.Failure_Bad_Parameter), "a bad SpaceToOutput");
         Params.Space_To_Output := 0;
         Params.Fixtured_Space_Name_Duplicate_Handling := 0;
         KF.Fixture_Execute (Handle, Params, Tree, Selected, Id, Status);
         Check (Failed (K.Failure_Bad_Parameter), "a bad duplicate code");
         Params.Fixtured_Space_Name_Duplicate_Handling := 1;
         Params.Fixtured_Space_Name.Length := -3;
         KF.Fixture_Execute (Handle, Params, Tree, Selected, Id, Status);
         Check (Failed (K.Failure_Bad_Parameter), "a malformed name");
         Params.Fixtured_Space_Name.Length := 7;
         Tree.Count := 0;
         KF.Fixture_Execute (Handle, Params, Tree, Selected, Id, Status);
         Check (Failed (K.Failure_Bad_Parameter), "an invalid tree");
         Tree.Count := 1;
         KF.Fixture_Execute (Handle, Params, Tree, Selected, Id, Status);
         Check (Failed (K.Failure_None) and then Tree.Count = 2
                and then Selected.Length = 9, "fixture: @\Fixture");
         KF.Calibration_Run_Params_Default (KF.Kind_Checkerboard, Run, Status);
         Check (Run.Calibrated_Space_Name.Length = 24,
                "checkerboard run defaults");
         KF.Calibration_Tool_Execute
           (Handle, null, Run, Tree, Selected, Id, Status);
         Check (Failed (K.Failure_Bad_Parameter), "a null calibration");
         KF.Calibration_Create (KF.Kind_N_Point_To_N_Point, Calib, Status);
         KF.Calibration_Tool_Execute
           (Handle, Calib, Run, Tree, Selected, Id, Status);
         Check (Failed (K.Failure_Operator_Not_Trained),
                "an uncalibrated calibration");
         KF.Calibration_Set_DOFs_To_Compute (Calib, KF.DOF_None, Status);
         KF.Calibration_Calibrate (Calib, null, Id, Status);
         KF.Calibration_Tool_Execute
           (Handle, Calib, Run, Tree, Selected, Id, Status);
         Check (Failed (K.Failure_None) and then Tree.Count = 3,
                "the identity calibration of no points");
         KF.Calibration_Destroy (Calib);
      end;
   end Test_Kernel;

   ---------------------------------------------------------------------
   --  Lens distortion: N-point calibrations
   ---------------------------------------------------------------------
   --  Synthetic pairs from a known model: plate points in millimetres on
   --  the board that Draw_Distorted_Board renders (10 x 7 tiles of
   --  Plate_Tile mm), at random places on it (not a grid), and the
   --  uncalibrated points where the known homography and lens see them
   --  (True_Corner). The model family holds the truth, so without noise
   --  the fit can only miss it by its convergence: the Levenberg-
   --  Marquardt steps stop when no normalised parameter changes by more
   --  than 2**(-40) (about 1.0E-12, a nanopixel), the bisection of
   --  Map_Input_Pixel ends within 4 / 2**64 of the normalised radius.
   --  The exact tolerances below (1.0E-6 pixel, 1.0E-6 for K1 and K2)
   --  leave a wide margin above that and lie far below the error of any
   --  other model (the linear one leaves pixels).

   Plate_Tile  : constant Real := 5.0;
   N_Board     : constant Homography :=
     Board (45.0, Deg (4.0), 95.0, 85.0, P => 0.006, Q => 0.004);
   N_Lens      : constant Lens := (K1 => -0.15, K2 => 0.03);
   Exact_Pixel : constant Real := 1.0E-6;

   procedure Plate_Pixel
     (H    : Homography;
      L    : Lens;
      U, V : Real;
      X, Y : out Real) is
   begin
      True_Corner (640, 480, H, L, U / Plate_Tile, V / Plate_Tile, X, Y);
   end Plate_Pixel;
   --  The observed pixel of the plate point (U, V) (mm).

   procedure Random_Plate_Point (U, V : out Real) is
   begin
      U := Plate_Tile * (5.0 + Noise (4.5));
      V := Plate_Tile * (3.5 + Noise (3.0));
   end Random_Plate_Point;
   --  A random point of the board (mm), half a tile from its edges.

   procedure Add_Pairs
     (Calibration : in out Ks_Calib_N_Point_To_N_Point;
      H           : Homography;
      L           : Lens;
      Count       : Positive;
      Noise_Level : Real := 0.0)
   is
      U, V, X, Y, Nx, Ny : Real;
   begin
      for Unused in 1 .. Count loop
         Random_Plate_Point (U, V);
         Plate_Pixel (H, L, U, V, X, Y);
         Noisy_Point (X, Y, Noise_Level, Nx, Ny);
         Calibration.Add_Point_Pair (Nx, Ny, U, V);
      end loop;
   end Add_Pairs;
   --  Count random pairs of the model (H, L), the uncalibrated points with
   --  uniform noise in [-Noise_Level, Noise_Level].

   function Worst_Model_Error
     (M : Ks_Calib_N_Point_To_N_Point_Warp_Model;
      H : Homography;
      L : Lens) return Real
   is
      U, V, X, Y, Mx, My : Real;
      Worst              : Real := 0.0;
   begin
      for Unused in 1 .. 200 loop
         Random_Plate_Point (U, V);
         Plate_Pixel (H, L, U, V, X, Y);
         Model_Pixel (M, U, V, Mx, My);
         Worst := Real'Max (Worst, EF.Sqrt ((Mx - X) ** 2 + (My - Y) ** 2));
      end loop;
      return Worst;
   end Worst_Model_Error;
   --  The largest distance (pixels) between the model's and the true
   --  pixel of 200 random plate points (the formulas of the kernel's spec:
   --  the plate normalisation is in millimetres here).

   function Near_Relative (A, B, Tolerance : Real) return Boolean is
     (abs (A - B) <= Tolerance * abs B + 1.0E-15);

   procedure Test_N_Point_Warp is
      Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
      Tool  : Ks_Calib_N_Point_To_N_Point_Tool;
      Model : Ks_Calib_N_Point_To_N_Point_Warp_Model;
      Pixel_From_Calibrated : AMV.Transforms.Ks_Transform_2D_Linear;
      U, V, X, Y : Real;
      Ux, Uy     : Real;
      Ix, Iy     : Real;
      Inside     : Boolean;
      Worst_Out  : Real := 0.0;
      Worst_In   : Real := 0.0;
      Warp_Only  : constant String :=
        "CalibratedOriginSpace and CalibratedXAxisRotationSpace must be "
        & "RawCalibrated in ComputationMode PerspectiveAndRadialWarp";
   begin
      Draw_Distorted_Board (Image, N_Board, N_Lens, 10, 7);

      Section ("Lens distortion, N-point: the fit recovers a known model");
      Add_Pairs (Tool.Calibration, N_Board, N_Lens, 40);
      Check (Tool.Calibration.Computation_Mode = Linear,
             "N-point: the default mode is Linear");
      Tool.Calibration.Set_Computation_Mode (Perspective_And_Radial_Warp);
      Tool.Calibration.Calibrate (Image);
      Model := Tool.Calibration.Get_Computed_Warp_Model;
      Check (Tool.Calibration.Calibrated
             and then Tool.Calibration.Num_Points = 40
             and then Model.Image_Width = 640
             and then Model.Image_Height = 480
             and then Model.Center_X = 319.5 and then Model.Center_Y = 239.5,
             "N-point warp: calibrated with a model of the image's size");
      Check (Tool.Calibration.Computed_RMS_Error <= Exact_Pixel
             and then Tool.Calibration.Computed_RMS_Error = Model.RMS_Error,
             "N-point warp: RMS error near 0 ("
             & Tool.Calibration.Computed_RMS_Error'Image & ")");
      Check (abs (Model.K1 - N_Lens.K1) <= 1.0E-6
             and then abs (Model.K2 - N_Lens.K2) <= 1.0E-6,
             "N-point warp: K1 and K2 recovered (" & Model.K1'Image
             & Model.K2'Image & ")");
      Worst_Out := Worst_Model_Error (Model, N_Board, N_Lens);
      Check (Worst_Out <= Exact_Pixel,
             "N-point warp: the model is the truth at 200 other points "
             & "(worst" & Worst_Out'Image & ")");
      Ada.Text_IO.Put_Line
        ("  N-point warp, exact: RMS"
         & Tool.Calibration.Computed_RMS_Error'Image & " px, K1 error"
         & Real'Image (Model.K1 - N_Lens.K1) & ", K2 error"
         & Real'Image (Model.K2 - N_Lens.K2) & ", model error"
         & Worst_Out'Image & " px," & Model.Iterations'Image & " steps");
      Worst_Out := 0.0;
      Pixel_From_Calibrated :=
        Tool.Calibration.Get_Output_Pixel_From_Calibrated_Transform;
      for Unused in 1 .. 200 loop
         Random_Plate_Point (U, V);
         Plate_Pixel (N_Board, N_Lens, U, V, X, Y);
         Map_Point (Pixel_From_Calibrated, U, V, Ux, Uy);
         Tool.Calibration.Map_Output_Pixel (Ux, Uy, Ix, Iy, Inside);
         Worst_Out := Real'Max
           (Worst_Out,
            (if Inside then EF.Sqrt ((Ix - X) ** 2 + (Iy - Y) ** 2)
             else 1.0E9));
         Tool.Calibration.Map_Input_Pixel (X, Y, Ix, Iy, Inside);
         Worst_In := Real'Max
           (Worst_In,
            (if Inside then EF.Sqrt ((Ix - Ux) ** 2 + (Iy - Uy) ** 2)
             else 1.0E9));
      end loop;
      Check (Worst_Out <= Exact_Pixel,
             "N-point warp: Map_Output_Pixel of a plate point's output "
             & "pixel is its true input pixel (worst" & Worst_Out'Image
             & ")");
      Check (Worst_In <= Exact_Pixel,
             "N-point warp: Map_Input_Pixel of a plate point's true input "
             & "pixel is its output pixel (worst" & Worst_In'Image & ")");
      Ada.Text_IO.Put_Line
        ("  N-point warp, exact: Map_Output_Pixel" & Worst_Out'Image
         & " px, Map_Input_Pixel" & Worst_In'Image & " px");

      Section ("Lens distortion, N-point: the warped output image");
      Tool.Input_Image := Image;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Output_Image.Allocated
             and then Tool.Output_Image.Width = 640
             and then Tool.Output_Image.Height = 480,
             "N-point warp: the tool runs (" & Tool.Run_Status.Message
             & ")");
      if Tool.Run_Status.Result = Accept_Result then
         Check (Tool.Output_Image.Selected_Space_Name
                = "@\N-Point Calibration",
                "N-point warp: the calibrated space selected");
         Check_Transform (Tool.Output_Image.Get_Transform ("#", "."),
                          Kernel_Of (Pixel_From_Calibrated), 1.0E-9,
                          "N-point warp: pixels from calibrated");
         declare
            --  The board's corners found again in the output lie on a
            --  regular grid, on multiples of the tile in calibrated
            --  coordinates (to the accuracy of finding them in a
            --  resampled image: Check_Warp_Output).
            Output : Ks_Image_8_Grey := Tool.Output_Image;
            Again  : Ks_Calib_Checkerboard;
            Px, Py, Cx, Cy : Real;
            Gi, Gj : Integer;
            Worst  : Real := 0.0;
         begin
            Output.Set_Selected_Space_Name ("#");
            Again.Set_Calibration_Image (Output);
            Again.Calibrate;
            Check (Again.Num_Points = 54
                   and then Again.Computed_RMS_Error <= 0.1,
                   "N-point warp: the output's corners on an affine grid "
                   & "(RMS"
                   & Integer'Image
                       (Integer (Again.Computed_RMS_Error * 1000.0))
                   & " mpx)");
            for K in 0 .. Again.Num_Points - 1 loop
               Again.Get_Corner (K, Px, Py, Gi, Gj);
               Map_Point (Tool.Output_Image.Get_Transform (".", "#"), Px, Py,
                          Cx, Cy);
               Map_Point (Pixel_From_Calibrated,
                          Plate_Tile * Real'Rounding (Cx / Plate_Tile),
                          Plate_Tile * Real'Rounding (Cy / Plate_Tile),
                          Ux, Uy);
               Worst := Real'Max (Worst,
                                  EF.Sqrt ((Ux - Px) ** 2 + (Uy - Py) ** 2));
            end loop;
            Check (Worst <= 0.15,
                   "N-point warp: the output's corners on the calibrated "
                   & "lattice (worst"
                   & Integer'Image (Integer (Worst * 1000.0)) & " mpx)");
         end;
      end if;

      Section ("Lens distortion, N-point: the origin adjustment");
      declare
         Raw : constant AMV.Transforms.Ks_Transform_2D_Linear :=
           Tool.Calibration
             .Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform;
         T   : AMV.Transforms.Ks_Transform_2D_Linear;
      begin
         Check (Kernel_Of (Tool.Calibration
                  .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                = Kernel_Of (Raw),
                "N-point warp: the defaults give the output's transform");
         Tool.Calibration.Set_Calibrated_Origin_X (4.0);
         Tool.Calibration.Set_Calibrated_Origin_Y (6.0);
         Tool.Calibration.Set_Calibrated_X_Axis_Rotation (Deg (90.0));
         Tool.Calibration.Set_Swap_Calibrated_Handedness (True);
         Check (Tool.Calibration.Calibrated,
                "N-point warp: the setters keep it calibrated");
         T := Tool.Calibration
                .Get_Computed_Uncalibrated_From_Calibrated_Transform;
         Check_Rigid (Raw_From_Calibrated (Raw, T), Deg (90.0), True, 4.0,
                      6.0, "N-point warp: an adjustment in raw calibrated "
                           & "space");
         Tool.Run;
         Check (Tool.Run_Status.Result = Accept_Result,
                "N-point warp: the tool runs with the adjustment");
         Check_Transform (Tool.Output_Image.Get_Transform ("#", "."),
                          Kernel_Of (T), 1.0E-12,
                          "N-point warp: the output's calibrated space is "
                          & "F * R");
         Map_Point (Pixel_From_Calibrated, 4.0, 6.0, Ux, Uy);
         Map_Point (Tool.Output_Image.Get_Transform (".", "#"), Ux, Uy, X,
                    Y);
         Check (abs X < 1.0E-9 and then abs Y < 1.0E-9,
                "N-point warp: the raw calibrated point (4, 6) is "
                & "calibrated (0, 0)");
         Tool.Calibration.Set_Calibrated_Origin_Space (Uncalibrated);
         begin
            T := Tool.Calibration
                   .Get_Computed_Uncalibrated_From_Calibrated_Transform;
            Fail ("N-point warp: an uncalibrated origin space");
         exception
            when E : AMV.Ks_Bad_Parameter_Exception =>
               Check (Ada.Exceptions.Exception_Message (E) = Warp_Only,
                      "N-point warp: an uncalibrated origin space is "
                      & "refused");
         end;
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Message = Warp_Only
                and then not Tool.Output_Image.Allocated,
                "N-point warp: the tool refuses an uncalibrated origin "
                & "space");
         Tool.Calibration.Set_Calibrated_Origin_Space (Raw_Calibrated);
         Tool.Calibration.Set_Calibrated_Origin_X (0.0);
         Tool.Calibration.Set_Calibrated_Origin_Y (0.0);
         Tool.Calibration.Set_Calibrated_X_Axis_Rotation (0.0);
         Tool.Calibration.Set_Swap_Calibrated_Handedness (False);
      end;

      Section ("Lens distortion, N-point: the calibration image's space");
      declare
         --  The same pairs measured in a stage space of the image: the
         --  same model, and the fit through the stage.
         Stage  : constant AMV.Transforms.Ks_Transform_2D_Linear :=
           Create_Similarity (0.5, -0.3, 40.0, 25.0);
         Staged : Ks_Image_8_Grey := Image;
         Calib  : Ks_Calib_N_Point_To_N_Point;
         Other  : Ks_Calib_N_Point_To_N_Point_Warp_Model;
         Same   : Boolean;
      begin
         Staged.Coordinate_Space_Tree.Add_Space ("@", "Stage", Stage);
         Staged.Set_Selected_Space_Name ("@\Stage");
         for K in 0 .. Tool.Calibration.Num_Points - 1 loop
            Tool.Calibration.Get_Uncalibrated_Point (K, X, Y);
            Map_Point (Staged.Get_Transform (".", "#"), X, Y, Ux, Uy);
            Calib.Add_Point_Pair
              (Ux, Uy, Tool.Calibration.Get_Raw_Calibrated_Point_X (K),
               Tool.Calibration.Get_Raw_Calibrated_Point_Y (K));
         end loop;
         Calib.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Calib.Calibrate (Staged);
         Other := Calib.Get_Computed_Warp_Model;
         Same := abs (Other.K1 - Model.K1) <= 1.0E-9
                 and then abs (Other.K2 - Model.K2) <= 1.0E-9
                 and then abs (Other.H11 - Model.H11) <= 1.0E-9
                 and then abs (Other.H32 - Model.H32) <= 1.0E-9
                 and then Calib.Computed_RMS_Error <= Exact_Pixel;
         Check (Same, "N-point warp: points in a stage space give the "
                      & "model of their pixels");
         Check_Transform
           (Calib.Get_Computed_Uncalibrated_From_Raw_Calibrated_Transform,
            Kernel_Of (Staged.Get_Transform (".", "#")
                       * Calib.Get_Output_Pixel_From_Calibrated_Transform),
            1.0E-9, "N-point warp: the fit is the stage from the output's "
                    & "pixels");
         Tool.Calibration := Calib;
         Tool.Input_Image := Staged;
         Tool.Run;
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Output_Image.Selected_Space_Name
                           = "@\Stage\N-Point Calibration",
                "N-point warp: the calibrated space under the stage");
         Check_Transform
           (Tool.Output_Image.Get_Transform ("#", "."),
            Kernel_Of (Calib.Get_Output_Pixel_From_Calibrated_Transform),
            1.0E-9, "N-point warp: pixels from calibrated through the "
                    & "stage");
         Tool.Input_Image := AMV_Test_Images.Blank (320, 240);
         Tool.Run;
         Check (Tool.Run_Status.Result = Error
                and then Tool.Run_Status.Exception_Name
                           = "AMV.KS_BAD_PARAMETER_EXCEPTION"
                and then not Tool.Output_Image.Allocated,
                "N-point warp: an input of another size");
      end;

      Section ("Lens distortion, N-point: noise and unfilled pixels");
      declare
         --  Uniform noise of +/-0.25 pixel along each axis (a standard
         --  deviation of 0.144) on 60 pairs, a pincushion lens and a
         --  tilted plate. The RMS error is the RMS of the distances, of
         --  two coordinates: a least squares fit of 10 parameters to 120
         --  coordinates leaves about 0.144 * Sqrt (2 * 110 / 120) = 0.195
         --  pixel. The model then lies within a few hundredths of a pixel
         --  of the truth on average. Its largest error on the plate depends
         --  on the draw of the noise: over 400 draws it was 0.06 to 0.58
         --  pixel (median 0.16), with the RMS error from 0.17 to 0.23 and
         --  K1 within 0.01 in 99 draws of 100 (Test_Radial_Fit holds the
         --  checkerboard to that). The model is therefore held to three
         --  times the amplitude of the noise.
         H     : constant Homography :=
           Board (48.0, Deg (-10.0), 110.0, 140.0, P => -0.01, Q => 0.015);
         L     : constant Lens := (K1 => 0.08, K2 => 0.0);
         Noisy : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
         Calib : Ks_Calib_N_Point_To_N_Point_Tool;
         M     : Ks_Calib_N_Point_To_N_Point_Warp_Model;
         Worst : Real;
      begin
         Draw_Distorted_Board (Noisy, H, L, 10, 7);
         Add_Pairs (Calib.Calibration, H, L, 60, Noise_Level => 0.25);
         Calib.Calibration.Set_Computation_Mode
           (Perspective_And_Radial_Warp);
         Calib.Calibration.Calibrate (Noisy);
         M := Calib.Calibration.Get_Computed_Warp_Model;
         Worst := Worst_Model_Error (M, H, L);
         Check (M.RMS_Error >= 0.15 and then M.RMS_Error <= 0.24,
                "N-point warp, noise: the RMS error is the noise's ("
                & Integer'Image (Integer (M.RMS_Error * 1000.0))
                & " mpx)");
         Check (abs (M.K1 - L.K1) <= 0.01 and then abs M.K2 <= 0.02,
                "N-point warp, noise: K1 and K2 (" & M.K1'Image
                & M.K2'Image & ")");
         Check (Worst <= 0.75,
                "N-point warp, noise: the model near the truth (worst"
                & Integer'Image (Integer (Worst * 1000.0)) & " mpx)");
         Ada.Text_IO.Put_Line
           ("  N-point warp, noise 0.25: RMS"
            & Integer'Image (Integer (M.RMS_Error * 1000.0))
            & " mpx, K1" & M.K1'Image & " K2" & M.K2'Image
            & ", model error" & Integer'Image (Integer (Worst * 1000.0))
            & " mpx," & M.Iterations'Image & " steps");
         Calib.Input_Image := Noisy;
         Calib.Run;
         Calib.Calibration.Map_Output_Pixel (0.0, 0.0, Ix, Iy, Inside);
         Check (Calib.Run_Status.Result = Accept_Result
                and then (not Inside or else Ix < -0.5 or else Iy < -0.5)
                and then Calib.Output_Image.Get_Pixel (0, 0) = 0,
                "N-point warp: an output pixel that shows nothing is 0");
      end;

      Section ("Lens distortion, N-point: the computation mode");
      declare
         Calib    : Ks_Calib_N_Point_To_N_Point;
         Linear_T : KT.Ks_Transform_2D_Linear;
         Warped   : Ks_Calib_N_Point_To_N_Point_Warp_Model;
         RMS      : Real;
      begin
         Add_Pairs (Calib, N_Board, N_Lens, 30);
         Calib.Calibrate;
         Linear_T := Kernel_Of
           (Calib.Get_Computed_Uncalibrated_From_Calibrated_Transform);
         RMS := Calib.Computed_RMS_Error;
         Calib.Calibrate (Image);
         Check (Kernel_Of (Calib
                  .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                = Linear_T and then Calib.Computed_RMS_Error = RMS
                and then RMS > 0.5,
                "N-point: the linear mode ignores the calibration image");
         Calib.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Check (not Calib.Calibrated and then Calib.Num_Points = 30
                and then Calib.Computation_Mode
                           = Perspective_And_Radial_Warp,
                "N-point: setting the mode uncalibrates, keeps the pairs");
         Calib.Calibrate (Image);
         Warped := Calib.Get_Computed_Warp_Model;
         Check (Calib.Calibrated
                and then Calib.Computed_RMS_Error < RMS / 1000.0,
                "N-point: the warp mode fits the distortion");
         Calib.Set_DOFs_To_Compute (Translation);
         Check (not Calib.Calibrated, "N-point warp: a new DOF uncalibrates");
         Calib.Calibrate (Image);
         Check (Calib.Calibrated
                and then Calib.Get_Computed_Warp_Model = Warped,
                "N-point warp: DOFsToCompute is not used");
         for Mode in Linescan_Warp .. No_Distortion_Warp loop
            begin
               Calib.Set_Computation_Mode (Mode);
               Fail ("N-point: the mode " & Mode'Image & " is not supported");
            exception
               when AMV.Ks_Bad_Parameter_Exception =>
                  Check (Calib.Computation_Mode = Perspective_And_Radial_Warp
                         and then Calib.Calibrated,
                         "N-point: the mode " & Mode'Image
                         & " is refused, nothing changed");
            end;
         end loop;
         begin
            Calib.Calibrate;
            Fail ("N-point warp: Calibrate without the image");
         exception
            when E : AMV.Ks_Image_No_Pixels_Exception =>
               Check (Ada.Exceptions.Exception_Message (E)
                      = "CalibrationImage has no pixels"
                      and then not Calib.Calibrated,
                      "N-point warp: Calibrate without the image");
         end;
         declare
            Unallocated : Ks_Image_8_Grey;
         begin
            Calib.Calibrate (Unallocated);
            Fail ("N-point warp: an unallocated image");
         exception
            when AMV.Ks_Image_No_Pixels_Exception =>
               Check (not Calib.Calibrated,
                      "N-point warp: an unallocated image");
         end;
         Calib.Set_Computation_Mode (Linear);
         Calib.Set_DOFs_To_Compute
           (Scaling_Aspect_Rotation_Skew_And_Translation);
         Calib.Calibrate;
         Check (Kernel_Of (Calib
                  .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                = Linear_T,
                "N-point: back in the linear mode, the same fit");
         begin
            Warped := Calib.Get_Computed_Warp_Model;
            Fail ("N-point: the linear mode has no warp model");
         exception
            when AMV.Ks_Bad_Parameter_Exception =>
               Check (True, "N-point: the linear mode has no warp model");
         end;
      end;

      Section ("Lens distortion, N-point: too few and degenerate points");
      declare
         procedure Expect
           (Calib   : in out Ks_Calib_N_Point_To_N_Point;
            Message : String;
            What    : String) is
         begin
            Calib.Set_Computation_Mode (Perspective_And_Radial_Warp);
            Calib.Calibrate (Image);
            Fail (What & ": calibrated");
         exception
            when E : AMV.Ks_Bad_Parameter_Exception =>
               Check (not Calib.Calibrated
                      and then (Message = ""
                                or else Ada.Exceptions.Exception_Message (E)
                                          = Message),
                      What & " (" & Ada.Exceptions.Exception_Message (E)
                      & ")");
         end Expect;
         Seven, Eight, Line, Equal : Ks_Calib_N_Point_To_N_Point;
         Pixels_Line, Off          : Ks_Calib_N_Point_To_N_Point;
      begin
         Add_Pairs (Seven, N_Board, N_Lens, 7);
         Expect (Seven, "Calibrate: PerspectiveAndRadialWarp needs at least "
                        & "8 point pairs", "N-point warp: 7 pairs");
         Add_Pairs (Eight, N_Board, N_Lens, 8);
         Eight.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Eight.Calibrate (Image);
         Check (Eight.Calibrated
                and then Eight.Computed_RMS_Error <= Exact_Pixel
                and then Worst_Model_Error
                           (Eight.Get_Computed_Warp_Model, N_Board, N_Lens)
                         <= 1.0E-3,
                "N-point warp: 8 exact pairs give the model");
         --  Raw calibrated points on one line (the plate's diagonal).
         for I in 1 .. 12 loop
            U := Plate_Tile * (0.5 + 0.75 * Real (I));
            V := 0.6 * U;
            Plate_Pixel (N_Board, N_Lens, U, V, X, Y);
            Line.Add_Point_Pair (X, Y, U, V);
         end loop;
         Expect (Line, "", "N-point warp: raw calibrated points on a line");
         for I in 1 .. 12 loop
            Plate_Pixel (N_Board, N_Lens, 25.0, 17.0, X, Y);
            Equal.Add_Point_Pair (X + Real (I), Y, 25.0, 17.0);
         end loop;
         Expect (Equal, "Calibrate: the points do not span the plate "
                        & "(PerspectiveAndRadialWarp)",
                 "N-point warp: equal raw calibrated points");
         for I in 1 .. 12 loop
            Random_Plate_Point (U, V);
            Pixels_Line.Add_Point_Pair
              (100.0 + 30.0 * Real (I), 80.0 + 20.0 * Real (I), U, V);
         end loop;
         Expect (Pixels_Line, "",
                 "N-point warp: uncalibrated points on a line");
         Add_Pairs (Off, N_Board, N_Lens, 12);
         Off.Set_Uncalibrated_Point (3, -0.6, 200.0);
         Expect (Off, "Calibrate: an uncalibrated point lies outside "
                      & "CalibrationImage (PerspectiveAndRadialWarp)",
                 "N-point warp: an uncalibrated point off the image");
         Off.Set_Uncalibrated_Point (3, 200.0, 479.6);
         Expect (Off, "Calibrate: an uncalibrated point lies outside "
                      & "CalibrationImage (PerspectiveAndRadialWarp)",
                 "N-point warp: an uncalibrated point below the image");
      end;

      Section ("Lens distortion, N-point: streams");
      declare
         S     : aliased Ada.Streams.Storage.Unbounded.Stream_Type;
         Calib : Ks_Calib_N_Point_To_N_Point;
         Back  : Ks_Calib_N_Point_To_N_Point;
         Code  : K.Int32;
         Run   : Ks_Calib_N_Point_To_N_Point_Tool;
         First, Second : Ks_Image_8_Grey;
         Same  : Boolean := True;
      begin
         Add_Pairs (Calib, N_Board, N_Lens, 20);
         Calib.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Calib.Calibrate (Image);
         Ks_Calib_N_Point_To_N_Point'Write (S'Access, Calib);
         K.Int32'Read (S'Access, Code);
         Check (Code = KF.Calibration_Stream_Code_1,
                "N-point warp: layout 1");
         S.Clear;
         Ks_Calib_N_Point_To_N_Point'Write (S'Access, Calib);
         Ks_Calib_N_Point_To_N_Point'Read (S'Access, Back);
         Check (Back.Calibrated
                and then Back.Computation_Mode = Perspective_And_Radial_Warp
                and then Back.Num_Points = 20
                and then Back.Get_Computed_Warp_Model
                           = Calib.Get_Computed_Warp_Model
                and then Kernel_Of
                           (Back
                            .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                         = Kernel_Of
                             (Calib
                              .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                and then Back.Computed_RMS_Error = Calib.Computed_RMS_Error,
                "N-point warp: read back with its model");
         Run.Input_Image := Image;
         Run.Calibration := Calib;
         Run.Run;
         First := Run.Output_Image;
         Run.Calibration := Back;
         Run.Run;
         Second := Run.Output_Image;
         for Row in 0 .. 479 loop
            for Column in 0 .. 639 loop
               Same := Same and then First.Get_Pixel (Column, Row)
                                       = Second.Get_Pixel (Column, Row);
            end loop;
         end loop;
         Check (Same, "N-point warp: the calibration read back warps the "
                      & "same");
         S.Clear;
         Calib.Uncalibrate;
         Ks_Calib_N_Point_To_N_Point'Write (S'Access, Calib);
         Ks_Calib_N_Point_To_N_Point'Read (S'Access, Back);
         Check (not Back.Calibrated and then Back.Num_Points = 20
                and then Back.Computation_Mode = Perspective_And_Radial_Warp,
                "N-point warp: an uncalibrated one reads back");
         --  With an origin adjustment: layout 2 with the model.
         S.Clear;
         Calib.Calibrate (Image);
         Calib.Set_Calibrated_Origin_X (3.0);
         Ks_Calib_N_Point_To_N_Point'Write (S'Access, Calib);
         Ks_Calib_N_Point_To_N_Point'Read (S'Access, Back);
         Check (Back.Calibrated and then Back.Calibrated_Origin_X = 3.0
                and then Back.Get_Computed_Warp_Model
                           = Calib.Get_Computed_Warp_Model,
                "N-point warp: layout 2 with the model");
      end;
   end Test_N_Point_Warp;

   procedure Test_N_Point_Of_Checkerboard is
      --  The generalised fit on the checkerboard's own data: an N-point
      --  calibration whose pairs are the corners found (pixel positions,
      --  grid indices times the tile) gives the checkerboard's model and
      --  transforms exactly, for tiles of 1 and of 2 (the normalisation
      --  of grid steps and of millimetres then differ by a power of two,
      --  which is exact). And the checkerboard's model of a board rendered
      --  through a homography (Draw_Board) is the one AMV computed before
      --  the fit took real plate coordinates (values printed then, to
      --  17 digits; a relative 1.0E-12 allows for nothing but rounding).
      Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
   begin
      Section ("Lens distortion: N-point pairs of a checkerboard's corners");
      Draw_Distorted_Board
        (Image, Board (46.0, Deg (8.0), 120.0, 80.0, P => 0.012, Q => 0.008),
         (K1 => -0.15, K2 => 0.03), 10, 7);
      for Tile of Point_List'[1.0, 2.0] loop
         declare
            Checker  : Ks_Calib_Checkerboard;
            Calib    : Ks_Calib_N_Point_To_N_Point;
            Expected : Ks_Calib_Checkerboard_Warp_Model;
            Px, Py   : Real;
            Gi, Gj   : Integer;
         begin
            Checker.Set_Calibration_Image (Image);
            Checker.Set_Physical_Tile_Size_X (Tile);
            Checker.Set_Physical_Tile_Size_Y (Tile);
            Checker.Set_Computation_Mode (Perspective_And_Radial_Warp);
            Checker.Calibrate;
            for K in 0 .. Checker.Num_Points - 1 loop
               Checker.Get_Corner (K, Px, Py, Gi, Gj);
               Calib.Add_Point_Pair (Px, Py, Tile * Real (Gi),
                                     Tile * Real (Gj));
            end loop;
            Calib.Set_Computation_Mode (Perspective_And_Radial_Warp);
            Calib.Calibrate (Image);
            --  The plate normalisation is in millimetres here, in grid
            --  steps there.
            Expected := Checker.Get_Computed_Warp_Model;
            Expected.Grid_Center_X := Tile * Expected.Grid_Center_X;
            Expected.Grid_Center_Y := Tile * Expected.Grid_Center_Y;
            Expected.Grid_Scale := Tile * Expected.Grid_Scale;
            Check (Calib.Get_Computed_Warp_Model = Expected
                   and then Kernel_Of
                              (Calib
                               .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                            = Kernel_Of
                                (Checker
                                 .Get_Computed_Uncalibrated_From_Calibrated_Transform)
                   and then Calib.Computed_RMS_Error
                              = Checker.Computed_RMS_Error,
                   "the N-point model of the corners is the checkerboard's, "
                   & "tiles of" & Tile'Image);
         end;
      end loop;

      Section ("Lens distortion: the checkerboard's model is unchanged");
      declare
         Board_Image : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
         Checker     : Ks_Calib_Checkerboard;
         M           : Ks_Calib_Checkerboard_Warp_Model;
         T           : AMV.Transforms.Ks_Transform_2D_Linear;
      begin
         AMV_Test_Images.Draw_Board
           (Board_Image, [44.0, -3.0, 120.0, 4.0, 45.0, 90.0, 0.0005, 0.0003],
            10, 7);
         Checker.Set_Calibration_Image (Board_Image);
         Checker.Set_Physical_Tile_Size_X (2.5);
         Checker.Set_Physical_Tile_Size_Y (4.0);
         Checker.Set_Computation_Mode (Perspective_And_Radial_Warp);
         Checker.Calibrate;
         M := Checker.Get_Computed_Warp_Model;
         T := Checker.Get_Computed_Uncalibrated_From_Calibrated_Transform;
         Check (Checker.Num_Points = 54 and then M.Iterations = 6
                and then Near_Relative (M.H11, 0.43684756721222034, 1.0E-12)
                and then Near_Relative (M.H12, -0.0308604876801848, 1.0E-12)
                and then Near_Relative (M.H22, 0.44768805302709536, 1.0E-12)
                and then Near_Relative (M.H31, 0.0019878691913776548,
                                        1.0E-12)
                and then Near_Relative (M.H32, 0.0011263681568625752,
                                        1.0E-12)
                and then Near_Relative (M.K1, -0.0001387517138940082,
                                        1.0E-12)
                and then Near_Relative (M.K2, 0.00059010344577769777,
                                        1.0E-12)
                and then M.Grid_Center_X = 0.0 and then M.Grid_Center_Y = 0.5
                and then M.Grid_Scale = 4.0
                and then Near_Relative (M.RMS_Error, 0.015622429357305703,
                                        1.0E-12)
                and then Near_Relative (M.Output_Pixel_From_Calibrated.A,
                                        13.971000837806498, 1.0E-12)
                and then Near_Relative
                           (M.Output_Pixel_From_Calibrated.Translation_X,
                            330.79923306612591, 1.0E-12)
                and then Near_Relative (T.Scaling_X, 14.025271932188451,
                                        1.0E-12)
                and then Near_Relative (T.Rotation_X, 0.088000225365086351,
                                        1.0E-12),
                "the checkerboard's warp model is the one before (K1"
                & M.K1'Image & ", RMS" & M.RMS_Error'Image & ")");
      end;
   end Test_N_Point_Of_Checkerboard;

   procedure Test_N_Point_Warp_Kernel is
      Status   : K.Ks_Status;
      Calib    : KF.Ks_Calibration;
      Copy     : KF.Ks_Calibration;
      Linear   : KF.Ks_Calibration;
      Model    : KF.Ks_Radial_Warp_Model;
      Other    : KF.Ks_Radial_Warp_Model;
      Fit      : KF.Ks_N_Point_To_N_Point_Fit;
      Width    : K.Int32;
      Height   : K.Int32;
      Run      : KF.Ks_Calibration_Run_Params;
      Tree     : KC.Ks_Coordinate_Space_Tree;
      Selected : KC.Ks_Space_Name := KI.Root_Space_Name;
      Output   : KI.Ks_Image_8_Grey;
      Image    : Ks_Image_8_Grey := AMV_Test_Images.Blank (640, 480, 90);
      Small    : constant Ks_Image_8_Grey := AMV_Test_Images.Blank (64, 48);
      Handle   : access constant KI.Ks_Image_8_Grey_Data;
      Ignored  : K.Ks_Status;
      U, V, X, Y : Real;

      function Failed (Code : K.Int32) return Boolean is
        (K.Valid (Status) and then Status.Failure = Code);
   begin
      Section ("Kernel: N-point calibrations in PerspectiveAndRadialWarp");
      Draw_Distorted_Board (Image, N_Board, N_Lens, 10, 7);
      Handle := AMV.Images.Kernel_Images.Kernel_Handle (Image);
      KF.Calibration_Create (KF.Kind_N_Point_To_N_Point, Calib, Status);
      KF.Calibration_Set_Computation_Mode
        (Calib, KF.Mode_Perspective_And_Radial_Warp, Status);
      Check (Failed (K.Failure_None), "an N-point calibration takes the warp");
      KF.Calibration_Calibrate (Calib, null, Id, Status);
      Check (Failed (K.Failure_Bad_Parameter),
             "no pairs: Bad_Parameter before the image is checked");
      for I in 1 .. KF.Min_Warp_Points loop
         Random_Plate_Point (U, V);
         Plate_Pixel (N_Board, N_Lens, U, V, X, Y);
         KF.Calibration_Add_Point_Pair (Calib, X, Y, U, V, Status);
      end loop;
      KF.Calibration_Calibrate (Calib, null, Id, Status);
      Check (Failed (K.Failure_Image_No_Pixels),
             "warp: no calibration image");
      KF.Calibration_Calibrate (Calib, Handle, (A => Inf, others => <>),
                                Status);
      Check (Failed (K.Failure_Bad_Parameter), "warp: an infinite transform");
      KF.Calibration_Calibrate (Calib, Handle, (A => 0.0, others => <>),
                                Status);
      Check (Failed (K.Failure_Bad_Parameter),
             "warp: a singular transform to the selected space");
      KF.Calibration_Calibrate (Calib, Handle, Id, Status);
      Check (Failed (K.Failure_None), "warp: calibrated with 8 pairs");
      KF.Calibration_Computed_Warp_Model (Calib, Model, Status);
      KF.Calibration_Computed_Fit (Calib, Fit, Status);
      Check (Failed (K.Failure_None)
             and then Fit.Transform = Model.Output_Pixel_From_Calibrated
             and then Model.Image_Width = 640
             and then Model.Image_Height = 480,
             "warp: the fit is the output's transform");
      KF.Calibration_Corner_Image_Size (Calib, Width, Height, Status);
      Check (Failed (K.Failure_None) and then Width = 0 and then Height = 0,
             "warp: an N-point calibration has no corner image");

      Section ("Kernel: the N-point tool");
      KF.Calibration_Run_Params_Default
        (KF.Kind_N_Point_To_N_Point, Run, Status);
      KF.Calibration_Tool_Execute
        (Handle, Calib, Run, Tree, Selected, Id, Status);
      Check (Failed (K.Failure_Bad_Parameter),
             "the linear tool refuses an N-point warp");
      KF.Calibration_N_Point_Tool_Execute
        (null, Calib, Run, Tree, Selected, Id, Output, Status);
      Check (Failed (K.Failure_Image_No_Pixels) and then Output = null,
             "N-point tool: null image");
      KF.Calibration_N_Point_Tool_Execute
        (Handle, null, Run, Tree, Selected, Id, Output, Status);
      Check (Failed (K.Failure_Bad_Parameter) and then Output = null,
             "N-point tool: null calibration");
      KF.Calibration_N_Point_Tool_Execute
        (AMV.Images.Kernel_Images.Kernel_Handle (Small), Calib, Run, Tree,
         Selected, Id, Output, Status);
      Check (Failed (K.Failure_Bad_Parameter) and then Output = null,
             "N-point tool: an input of another size");
      Run.Space_To_Output := 7;
      KF.Calibration_N_Point_Tool_Execute
        (Handle, Calib, Run, Tree, Selected, Id, Output, Status);
      Check (Failed (K.Failure_Bad_Parameter) and then Output = null,
             "N-point tool: a bad SpaceToOutput frees the warped image");
      Run.Space_To_Output := 0;
      KF.Calibration_N_Point_Tool_Execute
        (Handle, Calib, Run, Tree, Selected, Id, Output, Status);
      Check (Failed (K.Failure_None) and then Output /= null
             and then Output.Width = 640 and then Output.Height = 480
             and then KC.To_String (Selected) = "@\N-Point Calibration",
             "N-point tool: the warped image");
      KI.Destroy (Output, Ignored);
      KF.Calibration_Create (KF.Kind_N_Point_To_N_Point, Linear, Status);
      KF.Calibration_Set_DOFs_To_Compute (Linear, KF.DOF_None, Status);
      KF.Calibration_Calibrate (Linear, null, Id, Status);
      KF.Calibration_N_Point_Tool_Execute
        (Handle, Linear, Run, Tree, Selected, Id, Output, Status);
      Check (Failed (K.Failure_None) and then Output = null,
             "N-point tool: the linear mode returns no image");
      KF.Calibration_N_Point_Tool_Execute
        (Handle, Linear, Run, Tree, Selected, Id, Output, Status);
      KF.Calibration_Uncalibrate (Linear, Status);
      KF.Calibration_N_Point_Tool_Execute
        (Handle, Linear, Run, Tree, Selected, Id, Output, Status);
      Check (Failed (K.Failure_Operator_Not_Trained) and then Output = null,
             "N-point tool: not calibrated");
      KF.Calibration_Destroy (Linear);

      Section ("Kernel: N-point warp copies and restores");
      KF.Calibration_Duplicate (Calib, Copy, Status);
      KF.Calibration_Computed_Warp_Model (Copy, Other, Status);
      Check (Failed (K.Failure_None) and then Other = Model,
             "warp: a duplicate keeps the model");
      KF.Calibration_Uncalibrate (Copy, Status);
      KF.Restore_Model (Copy, Fit, Model, Status);
      Check (Failed (K.Failure_None), "restore: the model of 8 pairs");
      KF.Calibration_Computed_Warp_Model (Copy, Other, Status);
      Check (Failed (K.Failure_None) and then Other = Model,
             "restore: the model restored");
      KF.Calibration_Delete_Point_Pair (Copy, 0, Status);
      KF.Restore_Model (Copy, Fit, Model, Status);
      Check (Failed (K.Failure_Image_File), "restore: a model of 7 pairs");
      KF.Calibration_Add_Point_Pair (Copy, 1.0, 1.0, 1.0, 1.0, Status);
      Other := Model;
      Other.Normalizer := Other.Normalizer * 2.0;
      KF.Restore_Model (Copy, Fit, Other, Status);
      Check (Failed (K.Failure_Image_File),
             "restore: a model with another normaliser");
      KF.Calibration_Set_Computation_Mode (Copy, KF.Mode_Linear, Status);
      KF.Restore_Model (Copy, Fit, Model, Status);
      Check (Failed (K.Failure_Image_File),
             "restore: a model in the linear mode");
      KF.Calibration_Destroy (Copy);

      Section ("Kernel: at most Max_Warp_Points pairs");
      KF.Calibration_Create (KF.Kind_N_Point_To_N_Point, Copy, Status);
      KF.Calibration_Set_Computation_Mode
        (Copy, KF.Mode_Perspective_And_Radial_Warp, Status);
      --  A 256 x 256 grid of plate points over the board, one more.
      for I in 0 .. KF.Max_Warp_Points loop
         U := Plate_Tile * (0.5 + 9.0 * Real (I mod 256) / 255.0);
         V := Plate_Tile * (0.5 + 6.0 * Real ((I / 256) mod 256) / 255.0);
         Plate_Pixel (N_Board, N_Lens, U, V, X, Y);
         KF.Calibration_Add_Point_Pair (Copy, X, Y, U, V, Status);
      end loop;
      KF.Calibration_Calibrate (Copy, Handle, Id, Status);
      Check (Failed (K.Failure_Bad_Parameter),
             "warp: 65537 pairs are too many");
      KF.Calibration_Delete_Point_Pair (Copy, KF.Max_Warp_Points, Status);
      KF.Calibration_Calibrate (Copy, Handle, Id, Status);
      KF.Calibration_Computed_Fit (Copy, Fit, Status);
      Check (Failed (K.Failure_None) and then Fit.RMS_Error <= Exact_Pixel,
             "warp: 65536 exact pairs give the model (RMS"
             & Fit.RMS_Error'Image & ")");
      KF.Calibration_Destroy (Copy);
      KF.Calibration_Destroy (Calib);
   end Test_N_Point_Warp_Kernel;

   procedure Run_All is
   begin
      Test_Fits;
      Test_Fit_Failures;
      Test_Fixture;
      Test_Fixture_N_Point;
      Test_Calib_N_Point;
      Test_Checkerboard;
      Test_Checkerboard_Boards;
      Test_Checkerboard_Tool;
      Test_Origin_Adjustment;
      Test_Checkerboard_Adjustment;
      Test_Radial_Fit;
      Test_Radial_Tool;
      Test_Radial_Modes_And_Streams;
      Test_Radial_Kernel;
      Test_Radial_Adjustment;
      Test_Adjustment_Kernel;
      Test_N_Point_Warp;
      Test_N_Point_Of_Checkerboard;
      Test_N_Point_Warp_Kernel;
      Test_Kernel;
   exception
      when E : others =>
         Fail ("unexpected exception "
               & Ada.Exceptions.Exception_Information (E));
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Calib_Fix;
