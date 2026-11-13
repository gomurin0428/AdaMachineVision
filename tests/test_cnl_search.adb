--  Tests for AMV.CNL_Search (CogCNLSearchTool, CogCNLSearchPattern) and
--  its kernel AMV.Kernels.CNL_Search.
--
--  The scenes are drawn with AMV_Test_Images: a composite of rectangles
--  turned by generic angles, circles and a triangle, placed at whole and
--  fractional positions, so that every instance is the trained pattern
--  moved by a known translation (the renderer places such edges within a
--  few thousandths of a pixel). The train image mask is tested with a
--  block of the pattern whose texture changes from image to image. The
--  kernel is also called directly for what the Ada API cannot reach (null
--  handles, bad codes, non-finite values, limits), and the timings of
--  640 x 480 searches are printed.

pragma Validity_Checks ("F");
--  The kernel tests build NaNs on purpose.

with Ada.Calendar;
with Ada.Characters.Handling;
with Ada.Exceptions;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Streams.Storage.Unbounded;
with Ada.Strings.Unbounded;
with Ada.Text_IO;
with Interfaces;

with AMV;                    use AMV;
with AMV.CNL_Search;         use AMV.CNL_Search;
with AMV.Coordinate_Spaces;
with AMV.Images;             use AMV.Images;
with AMV.Images.Kernel_Images;
with AMV.Kernels;
with AMV.Kernels.CNL_Search;
with AMV.Kernels.CNL_Search.Region_Modes;
with AMV.Kernels.Images;
with AMV.Kernels.Regions;
with AMV.Kernels.Shapes;
with AMV.Kernels.Transforms;
with AMV.Regions;
with AMV.Shapes;             use AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tools;              use AMV.Tools;
with AMV.Transforms;         use AMV.Transforms;
with AMV_Test_Images;
with AMV_Test_Support;       use AMV_Test_Support;

procedure Test_CNL_Search is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package K renames AMV.Kernels;
   package KC renames AMV.Kernels.CNL_Search;
   package KI renames AMV.Kernels.Images;
   package KM renames AMV.Kernels.CNL_Search.Region_Modes;
   package KR renames AMV.Kernels.Regions;
   package KSH renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;
   package RH renames AMV.Shapes.Region_Holders;
   package SU renames Ada.Streams.Storage.Unbounded;
   package TI renames AMV_Test_Images;

   use type Ada.Exceptions.Exception_Id;
   use type Ada.Streams.Stream_Element_Offset;
   use type K.Int32;
   use type KC.Ks_CNL_Search_Pattern;
   use type KC.Ks_CNL_Search_Results;
   use type KC.Ks_CNL_Search_Run_Params;
   use type KC.Ks_CNL_Search_Train_Params;
   use type KI.Ks_Image_8_Grey;
   use type Interfaces.Unsigned_8;

   Zero : constant Real := Real'Value ("0.0");

   Background : constant := 100.0;

   ---------------------------------------------------------------------
   --  Scenes
   ---------------------------------------------------------------------

   function Level (V, Gain, Offset : Real) return Grey_8 is
     (Grey_8 (Real'Max (0.0, Real'Min (255.0, Offset + Gain * V))));
   --  A grey level of the composite under a change of contrast and
   --  brightness.

   procedure Draw_Composite
     (Image  : in out Ks_Image_8_Grey;
      CX, CY : Real;
      Gain   : Real := 1.0;
      Offset : Real := 0.0);
   --  The pattern, centred at (CX, CY): about 40 x 40 pixels of shapes of
   --  several grey levels on the background (which the caller draws).

   procedure Draw_Composite
     (Image  : in out Ks_Image_8_Grey;
      CX, CY : Real;
      Gain   : Real := 1.0;
      Offset : Real := 0.0) is
   begin
      TI.Draw_Rectangle (Image, CX - 5.0, CY - 3.0, 22.0, 7.0, 0.31,
                         Level (220.0, Gain, Offset));
      TI.Draw_Circle (Image, CX + 9.0, CY + 8.0, 6.5,
                      Level (30.0, Gain, Offset));
      TI.Draw_Rectangle (Image, CX + 6.0, CY - 10.0, 9.0, 5.0, -0.53,
                         Level (170.0, Gain, Offset));
      TI.Draw_Polygon (Image,
                       [CX - 14.3, CY + 6.2, CX - 4.1, CY + 14.6,
                        CX - 12.7, CY + 15.3],
                       Level (210.0, Gain, Offset));
      TI.Draw_Circle (Image, CX - 9.0, CY - 12.0, 3.5,
                      Level (60.0, Gain, Offset));
   end Draw_Composite;

   type Point is record
      X, Y : Real;
   end record;

   type Point_List is array (Positive range <>) of Point;

   function Scene
     (Width, Height : Positive;
      Centres       : Point_List;
      Gain          : Real := 1.0;
      Offset        : Real := 0.0) return Ks_Image_8_Grey
   is
      Image : Ks_Image_8_Grey :=
        TI.Blank (Width, Height, Level (Background, Gain, Offset));
   begin
      for C of Centres loop
         Draw_Composite (Image, C.X, C.Y, Gain, Offset);
      end loop;
      return Image;
   end Scene;
   --  A Width x Height image with the composite at each centre.

   Train_Centre : constant := 50.0;

   function Train_Rectangle return Ks_Rectangle is
      R : Ks_Rectangle;
   begin
      R.Set_XY_Width_Height (27.5, 27.5, 44.0, 44.0);
      return R;
   end Train_Rectangle;
   --  The pixels 28 .. 71 along both axes around the composite of the
   --  train image (centred at 50, 50).

   function Trained_Pattern
     (Algorithms : Ks_CNL_Search_Algorithm_Constants :=
        Linear_Search + Linear_CNLPAS;
      Accuracies : Ks_CNL_Search_Accuracy_Constants :=
        Very_Fine + Fine + Coarse;
      Ignore     : Boolean := False) return Ks_CNL_Search_Pattern
   is
      Pattern : Ks_CNL_Search_Pattern;
   begin
      Pattern.Set_Train_Image
        (Scene (100, 100, [1 => (Train_Centre, Train_Centre)]));
      Pattern.Set_Train_Region (RH.To_Holder (Train_Rectangle));
      Pattern.Set_Origin_X (Train_Centre);
      Pattern.Set_Origin_Y (Train_Centre);
      Pattern.Set_Algorithms (Algorithms);
      Pattern.Set_Accuracies (Accuracies);
      Pattern.Set_Ignore_Polarity (Ignore);
      Pattern.Train;
      return Pattern;
   end Trained_Pattern;
   --  The composite trained with its centre as origin.

   procedure Report (Tool : Ks_CNL_Search_Tool; Description : String);
   --  Prints the run status when it is not Accept_Result.

   procedure Report (Tool : Ks_CNL_Search_Tool; Description : String) is
   begin
      if Tool.Run_Status.Result /= Accept_Result then
         Ada.Text_IO.Put_Line
           ("  " & Description & ": " & Tool.Run_Status.Result'Image & " "
            & Exception_Name (Tool.Run_Status) & " "
            & Message (Tool.Run_Status));
      end if;
   end Report;

   function Failed_With
     (Tool    : Ks_CNL_Search_Tool;
      Name    : String;
      Message : String := "") return Boolean
   is (Tool.Run_Status.Result = Error
       and then Exception_Name (Tool.Run_Status)
                  = "AMV." & Ada.Characters.Handling.To_Upper (Name)
       and then (Message = ""
                 or else AMV.Tools.Message (Tool.Run_Status) = Message));

   function Text_Of (S : K.Ks_Status) return String is
     (String (S.Message (1 .. Natural (S.Length))));
   --  The message of a kernel status.

   type Accuracy_List is array (Positive range <>)
     of Ks_CNL_Search_Accuracy_Constants;
   type Train_Params_List is array (Positive range <>)
     of KC.Ks_CNL_Search_Train_Params;
   type Run_Params_List is array (Positive range <>)
     of KC.Ks_CNL_Search_Run_Params;

   function Distance (R : Ks_CNL_Search_Result; P : Point) return Real is
     (Real'Max (abs (R.Location_X - P.X), abs (R.Location_Y - P.Y)));
   --  The larger of the distances along x and y of a result's location
   --  from P.

   ---------------------------------------------------------------------
   --  Defaults and the pattern
   ---------------------------------------------------------------------

   procedure Test_Defaults is
      P       : constant Ks_CNL_Search_Run_Params := (others => <>);
      Pattern : Ks_CNL_Search_Pattern;
      KP      : KC.Ks_CNL_Search_Run_Params;
      TP      : KC.Ks_CNL_Search_Train_Params;
      S       : K.Ks_Status;
      Tool    : Ks_CNL_Search_Tool;
   begin
      Section ("CNL search: defaults");
      Check (P.Algorithm = Linear_Search and then P.Accuracy = Very_Fine
             and then P.Max_Results = 1
             and then P.Search_Region_Mode = Pixel_Aligned_Bounding_Box,
             "codes: LinearSearch, VeryFine, 1 result, bounding box");
      Check (P.Accept_Threshold = 0.3 and then P.Confusion_Threshold = 0.5
             and then P.XY_Overlap = 1.0,
             "thresholds 0.3 and 0.5, XYOverlap 1.0");
      KC.Run_Params_Default (KP, S);
      Check (K.Succeeded (S) and then KP = P, "run params default entry");
      KC.Train_Params_Default (TP, S);
      Check (K.Succeeded (S) and then TP.Origin_X = 70.0
             and then TP.Origin_Y = 70.0
             and then TP.Algorithms = Linear_Search
             and then TP.Accuracies = Very_Fine
             and then TP.Ignore_Polarity = 0,
             "train params default entry");
      Check (Pattern.Origin_X = 70.0 and then Pattern.Origin_Y = 70.0,
             "pattern origin 70, 70");
      Check (Pattern.Algorithms = Linear_Search
             and then Pattern.Accuracies = Very_Fine
             and then not Pattern.Ignore_Polarity,
             "pattern algorithms, accuracies, polarity");
      Check (not Pattern.Trained, "pattern untrained");
      Check (not Pattern.Train_Image.Allocated
             and then Pattern.Train_Region.Is_Empty,
             "no train image, empty train region");
      Check (not Pattern.Train_Image_Mask.Allocated
             and then Pattern.Train_Image_Mask_Offset_X = 0
             and then Pattern.Train_Image_Mask_Offset_Y = 0,
             "no train image mask, offsets 0");
      Check (Tool.Results.Count = 0, "no results before a run");
   end Test_Defaults;

   procedure Test_Pattern is
      Pattern : Ks_CNL_Search_Pattern := Trained_Pattern;
      Copy    : Ks_CNL_Search_Pattern;
      Train   : constant Ks_Image_8_Grey := Pattern.Train_Image;
   begin
      Section ("CNL search: pattern");
      Check (Pattern.Trained, "trained");
      Check (Pattern.Trained_Pattern_Width = 44
             and then Pattern.Trained_Pattern_Height = 44,
             "the train region's 44 x 44 pixels");
      declare
         Pixels : constant Ks_Image_8_Grey :=
           Pattern.Get_Trained_Pattern_Image;
         Same   : Boolean := True;
      begin
         for Y in 0 .. 43 loop
            for X in 0 .. 43 loop
               Same := Same
                 and then Pixels.Get_Pixel (X, Y)
                            = Train.Get_Pixel (X + 28, Y + 28);
            end loop;
         end loop;
         Check (Pixels.Width = 44 and then Pixels.Height = 44 and then Same,
                "the trained pattern image is the train region's pixels");
      end;
      Copy := Pattern;
      Check (Copy.Trained and then Copy.Trained_Pattern_Width = 44,
             "a copy is trained");
      Pattern.Untrain;
      Check (not Pattern.Trained and then Copy.Trained,
             "untraining the pattern leaves its copy trained");
      Pattern := Copy;
      Pattern.Set_Origin_X (40.0);
      Check (not Pattern.Trained and then Pattern.Origin_X = 40.0,
             "setting the origin untrains");
      Pattern := Copy;
      Pattern.Set_Train_Image (Train);
      Check (not Pattern.Trained, "setting the train image untrains");
      Pattern := Copy;
      Pattern.Set_Train_Region (RH.Empty_Holder);
      Check (not Pattern.Trained, "setting the train region untrains");
      Pattern := Copy;
      Pattern.Set_Accuracies (Fine);
      Check (not Pattern.Trained and then Pattern.Accuracies = Fine,
             "setting the accuracies untrains");
      Pattern.Train;
      Check (Pattern.Trained and then Pattern.Trained_Pattern_Width = 44,
             "trained again");

      --  The whole image as train region.
      Pattern.Set_Train_Region (RH.Empty_Holder);
      Pattern.Train;
      Check (Pattern.Trained_Pattern_Width = 100
             and then Pattern.Trained_Pattern_Height = 100,
             "an empty train region: the whole image");
   end Test_Pattern;

   procedure Test_Pattern_Failures is
      Pattern : Ks_CNL_Search_Pattern;

      procedure No_Image is
      begin
         Pattern.Train;
      end No_Image;

      procedure Small_Region is
         R : Ks_Rectangle;
      begin
         Pattern.Set_Train_Image (Scene (100, 100, [1 => (50.0, 50.0)]));
         R.Set_XY_Width_Height (40.5, 40.5, 7.0, 20.0);
         Pattern.Set_Train_Region (RH.To_Holder (R));
         Pattern.Train;
      end Small_Region;

      procedure Flat_Region is
         R : Ks_Rectangle;
      begin
         Pattern.Set_Train_Image (TI.Blank (100, 100, 77));
         R.Set_XY_Width_Height (10.5, 10.5, 20.0, 20.0);
         Pattern.Set_Train_Region (RH.To_Holder (R));
         Pattern.Train;
      end Flat_Region;

      procedure Outside_Region is
         R : Ks_Rectangle;
      begin
         Pattern.Set_Train_Image (Scene (100, 100, [1 => (50.0, 50.0)]));
         R.Set_XY_Width_Height (200.5, 10.5, 20.0, 20.0);
         Pattern.Set_Train_Region (RH.To_Holder (R));
         Pattern.Train;
      end Outside_Region;

      procedure Unknown_Space is
         R : Ks_Rectangle;
      begin
         Pattern.Set_Train_Image (Scene (100, 100, [1 => (50.0, 50.0)]));
         R.Set_XY_Width_Height (27.5, 27.5, 44.0, 44.0);
         R.Set_Selected_Space_Name ("@\Nowhere");
         Pattern.Set_Train_Region (RH.To_Holder (R));
         Pattern.Train;
      end Unknown_Space;

      procedure Non_Linear is
      begin
         Pattern.Set_Algorithms (Non_Linear_CNLPAS);
      end Non_Linear;

      procedure No_Algorithm is
      begin
         Pattern.Set_Algorithms (0);
      end No_Algorithm;

      procedure Bad_Accuracies is
      begin
         Pattern.Set_Accuracies (0);
      end Bad_Accuracies;

      procedure NaN_Origin is
      begin
         Pattern.Set_Origin_X (Zero / Zero);
      end NaN_Origin;

      procedure Untrained_Width is
         W : Natural;
      begin
         Pattern.Untrain;
         W := Pattern.Trained_Pattern_Width;
         Check (W = 0, "never reached");
      end Untrained_Width;

      procedure Untrained_Image is
         I : Ks_Image_8_Grey;
      begin
         Pattern.Untrain;
         I := Pattern.Get_Trained_Pattern_Image;
         Check (not I.Allocated, "never reached");
      end Untrained_Image;

      procedure Check_No_Image is new Check_Raises_Exactly
        (No_Image, Ks_Image_No_Pixels_Exception'Identity);
      procedure Check_Small is new Check_Raises_Exactly
        (Small_Region, Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Flat is new Check_Raises_Exactly
        (Flat_Region, Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Outside is new Check_Raises_Exactly
        (Outside_Region, Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Space is new Check_Raises_Exactly
        (Unknown_Space, Ks_Image_Bad_Selected_Space_Name_Exception'Identity);
      procedure Check_Non_Linear is new Check_Raises_Exactly
        (Non_Linear, Ks_Bad_Parameter_Exception'Identity);
      procedure Check_No_Algorithm is new Check_Raises_Exactly
        (No_Algorithm, Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Accuracies is new Check_Raises_Exactly
        (Bad_Accuracies, Ks_Bad_Parameter_Exception'Identity);
      procedure Check_NaN is new Check_Raises_Exactly
        (NaN_Origin, Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Untrained_Width is new Check_Raises_Exactly
        (Untrained_Width, Ks_Operator_Not_Trained_Exception'Identity);
      procedure Check_Untrained_Image is new Check_Raises_Exactly
        (Untrained_Image, Ks_Operator_Not_Trained_Exception'Identity);
   begin
      Section ("CNL search: pattern failures");
      Check_No_Image ("Train without a train image");
      Check_Small ("a train region narrower than 8 pixels");
      Check (not Pattern.Trained, "untrained after a failed Train");
      Check_Flat ("a flat train region");
      Check_Outside ("a train region outside the train image");
      Check_Space ("a train region in an unknown space");
      Check (not Pattern.Trained, "untrained after a failed rasterisation");
      Check_Non_Linear ("NonLinearCNLPAS is not supported");
      Check_No_Algorithm ("no algorithm");
      Check_Accuracies ("no accuracy");
      Check_NaN ("a NaN origin");
      Check (Pattern.Algorithms = Linear_Search
             and then Pattern.Origin_X = 70.0,
             "the parameters are unchanged after a rejected setter");
      Check_Untrained_Width ("TrainedPatternWidth of an untrained pattern");
      Check_Untrained_Image ("GetTrainedPatternImage of an untrained pattern");
   end Test_Pattern_Failures;

   ---------------------------------------------------------------------
   --  Searching
   ---------------------------------------------------------------------

   procedure Test_Exact is
      Pattern : constant Ks_CNL_Search_Pattern := Trained_Pattern;
      Tool    : Ks_CNL_Search_Tool;
      R       : Ks_CNL_Search_Result;
   begin
      Section ("CNL search: the train image itself");
      Tool.Pattern := Pattern;
      Tool.Input_Image := Pattern.Train_Image;
      for Algorithm in Linear_Search .. Linear_CNLPAS loop
         Tool.Run_Params.Algorithm := Algorithm;
         Tool.Run;
         Report (Tool, "exact");
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Results.Count = 1,
                "one result" & Algorithm'Image);
         R := Tool.Results.Item (0);
         Check_Near (R.Score, 1.0, 1.0E-9, "score 1" & Algorithm'Image);
         Check_Near (R.Location_X, Train_Centre, 1.0E-9,
                     "location X exact" & Algorithm'Image);
         Check_Near (R.Location_Y, Train_Centre, 1.0E-9,
                     "location Y exact" & Algorithm'Image);
         Check_Near (R.Contrast, 1.0, 1.0E-9, "contrast 1" & Algorithm'Image);
         Check (R.ID = 0 and then R.Accepted = 1
                and then R.Contrast_Computed = 1 and then R.Edge_Hit = None,
                "ID, Accepted, ContrastComputed, EdgeHit" & Algorithm'Image);
      end loop;
   end Test_Exact;

   procedure Test_Sub_Pixel is
      Pattern : constant Ks_CNL_Search_Pattern := Trained_Pattern;
      Offsets : constant Point_List :=
        [(0.0, 0.0), (0.25, 0.0), (0.5, 0.5), (0.75, 0.3), (0.13, 0.87),
         (0.6, 0.45), (0.38, 0.62), (0.91, 0.08)];
      Tool    : Ks_CNL_Search_Tool;
      Worst   : array (Ks_CNL_Search_Accuracy_Constants range 1 .. 4)
                  of Real := [others => 0.0];
   begin
      Section ("CNL search: sub-pixel positions");
      Tool.Pattern := Pattern;
      for O of Offsets loop
         declare
            Where : constant Point := (110.0 + O.X, 85.0 + O.Y);
         begin
            Tool.Input_Image := Scene (220, 180, [1 => Where]);
            for Algorithm in Linear_Search .. Linear_CNLPAS loop
               for Accuracy of Accuracy_List'[Very_Fine, Fine, Coarse] loop
                  Tool.Run_Params.Algorithm := Algorithm;
                  Tool.Run_Params.Accuracy := Accuracy;
                  Tool.Run;
                  Report (Tool, "sub-pixel");
                  if Tool.Results.Count /= 1 then
                     Fail ("sub-pixel: one result at" & O.X'Image
                           & O.Y'Image);
                  else
                     declare
                        R : constant Ks_CNL_Search_Result :=
                          Tool.Results.Item (0);
                        E : constant Real :=
                          Real'Max (abs (R.Location_X - Where.X),
                                    abs (R.Location_Y - Where.Y));
                     begin
                        Check (R.Score > 0.9,
                               "score above 0.9 at" & O.X'Image & O.Y'Image
                               & R.Score'Image);
                        Worst (Accuracy) := Real'Max (Worst (Accuracy), E);
                     end;
                  end if;
               end loop;
            end loop;
         end;
      end loop;
      --  A finer grid of offsets, with the defaults.
      Tool.Run_Params := (others => <>);
      for IX in 0 .. 4 loop
         for IY in 0 .. 4 loop
            declare
               Where : constant Point :=
                 (110.0 + Real (IX) / 5.0 + 0.07,
                  85.0 + Real (IY) / 5.0 + 0.03);
            begin
               Tool.Input_Image := Scene (220, 180, [1 => Where]);
               Tool.Run;
               if Tool.Results.Count = 1 then
                  Worst (Very_Fine) :=
                    Real'Max (Worst (Very_Fine),
                              Distance (Tool.Results.Item (0), Where));
               else
                  Fail ("sub-pixel grid: one result");
               end if;
            end;
         end loop;
      end loop;
      Ada.Text_IO.Put_Line
        ("  largest position error: VeryFine" & Worst (Very_Fine)'Image
         & ", Fine" & Worst (Fine)'Image & ", Coarse"
         & Worst (Coarse)'Image & " pixel");
      Check (Worst (Very_Fine) < 0.1, "VeryFine: within 0.1 pixel");
      Check (Worst (Fine) < 0.3, "Fine: within 0.3 pixel");
      Check (Worst (Coarse) < 1.0, "Coarse: a whole pixel next to it");
   end Test_Sub_Pixel;

   procedure Test_Several is
      Where : constant Point_List :=
        [(70.3, 60.6), (200.7, 80.2), (150.4, 180.9)];
      Tool  : Ks_CNL_Search_Tool;
   begin
      Section ("CNL search: several instances");
      Tool.Pattern := Trained_Pattern;
      Tool.Input_Image := Scene (320, 240, Where);
      for Algorithm in Linear_Search .. Linear_CNLPAS loop
         Tool.Run_Params.Algorithm := Algorithm;
         Tool.Run_Params.Max_Results := 3;
         Tool.Run;
         Report (Tool, "several");
         Check (Tool.Results.Count = 3, "three found" & Algorithm'Image);
         if Tool.Results.Count = 3 then
            for P of Where loop
               declare
                  Found : Boolean := False;
               begin
                  for I in 0 .. 2 loop
                     Found := Found
                       or else Distance (Tool.Results.Item (I), P) < 0.1;
                  end loop;
                  Check (Found, "instance at" & P.X'Image & " found"
                         & Algorithm'Image);
               end;
            end loop;
            Check (Tool.Results.Item (0).Score >= Tool.Results.Item (1).Score
                   and then Tool.Results.Item (1).Score
                              >= Tool.Results.Item (2).Score,
                   "sorted by score" & Algorithm'Image);
            Check (Tool.Results.Item (2).ID = 2, "IDs are the indices");
         end if;
         Tool.Run_Params.Max_Results := 2;
         Tool.Run;
         Check (Tool.Results.Count = 2, "MaxResults 2" & Algorithm'Image);
         Tool.Run_Params.Max_Results := 10;
         Tool.Run;
         Check (Tool.Results.Count = 3,
                "MaxResults 10: the three instances only" & Algorithm'Image);
      end loop;
   end Test_Several;

   procedure Test_Contrast is
      Tool  : Ks_CNL_Search_Tool;
      Where : constant Point := (120.4, 90.7);
   begin
      Section ("CNL search: contrast and brightness");
      Tool.Pattern := Trained_Pattern;
      Tool.Input_Image := Scene (240, 180, [1 => Where], 0.5, 60.0);
      for Algorithm in Linear_Search .. Linear_CNLPAS loop
         Tool.Run_Params.Algorithm := Algorithm;
         Tool.Run;
         Report (Tool, "low contrast");
         Check (Tool.Results.Count = 1
                and then Tool.Results.Item (0).Score > 0.9
                and then Distance (Tool.Results.Item (0), Where) < 0.1,
                "half the contrast, brighter: found" & Algorithm'Image);
         if Tool.Results.Count = 1 then
            Check_Near (Tool.Results.Item (0).Contrast, 0.5, 0.05,
                        "contrast about 0.5" & Algorithm'Image);
         end if;
      end loop;
      Tool.Input_Image := Scene (240, 180, [1 => Where], 1.1, -20.0);
      Tool.Run;
      Check (Tool.Results.Count = 1
             and then Tool.Results.Item (0).Score > 0.9,
             "more contrast, darker: found");
      if Tool.Results.Count = 1 then
         Check_Near (Tool.Results.Item (0).Contrast, 1.1, 0.05,
                     "contrast about 1.1");
      end if;

      --  The opposite polarity.
      Tool.Input_Image := Scene (240, 180, [1 => Where], -1.0, 255.0);
      Tool.Run_Params.Algorithm := Linear_Search;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 0,
             "the inverted pattern is not found");
      Tool.Pattern := Trained_Pattern (Ignore => True);
      Tool.Run;
      Check (Tool.Results.Count = 1
             and then Tool.Results.Item (0).Score > 0.9
             and then Distance (Tool.Results.Item (0), Where) < 0.1,
             "IgnorePolarity: the inverted pattern is found");
      Tool.Run_Params.Algorithm := Linear_CNLPAS;
      Tool.Run;
      Check (Tool.Results.Count = 0,
             "IgnorePolarity does not apply to LinearCNLPAS");
   end Test_Contrast;

   procedure Test_Noise is
      Tool  : Ks_CNL_Search_Tool;
      Where : constant Point := (100.6, 70.3);
      Image : Ks_Image_8_Grey := Scene (200, 150, [1 => Where]);
   begin
      Section ("CNL search: noise");
      TI.Add_Noise (Image, 25.0, Seed => 7);
      Tool.Pattern := Trained_Pattern;
      Tool.Input_Image := Image;
      for Algorithm in Linear_Search .. Linear_CNLPAS loop
         Tool.Run_Params.Algorithm := Algorithm;
         Tool.Run;
         Report (Tool, "noise");
         Check (Tool.Results.Count = 1, "found" & Algorithm'Image);
         if Tool.Results.Count = 1 then
            Check (Tool.Results.Item (0).Score > 0.6,
                   "score above 0.6" & Algorithm'Image
                   & Tool.Results.Item (0).Score'Image);
            Check (Distance (Tool.Results.Item (0), Where) < 0.2,
                   "within 0.2 pixel" & Algorithm'Image);
         end if;
      end loop;
   end Test_Noise;

   procedure Test_Region is
      First  : constant Point := (60.4, 60.2);
      Second : constant Point := (200.6, 100.3);
      Tool   : Ks_CNL_Search_Tool;
      R      : Ks_Rectangle;
   begin
      Section ("CNL search: search region");
      Tool.Pattern := Trained_Pattern;
      Tool.Input_Image := Scene (280, 180, [First, Second]);
      Tool.Run_Params.Max_Results := 2;
      Tool.Run;
      Check (Tool.Results.Count = 2, "both without a region");
      R.Set_XY_Width_Height (150.0, 50.0, 110.0, 110.0);
      Tool.Search_Region := RH.To_Holder (R);
      for Algorithm in Linear_Search .. Linear_CNLPAS loop
         Tool.Run_Params.Algorithm := Algorithm;
         Tool.Run;
         Report (Tool, "region");
         Check (Tool.Results.Count = 1
                and then Distance (Tool.Results.Item (0), Second) < 0.1,
                "only the instance in the region" & Algorithm'Image);
      end loop;
      --  A region that cuts the second instance: the pattern must lie in
      --  the region's bounding box.
      R.Set_XY_Width_Height (190.0, 50.0, 60.0, 110.0);
      Tool.Search_Region := RH.To_Holder (R);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 0,
             "an instance that does not fit in the region is not found");
      R.Set_XY_Width_Height (10.0, 10.0, 30.0, 30.0);
      Tool.Search_Region := RH.To_Holder (R);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 0,
             "a region smaller than the pattern: no results");
      R.Set_XY_Width_Height (500.0, 500.0, 30.0, 30.0);
      Tool.Search_Region := RH.To_Holder (R);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 0,
             "a region outside the image: no results");
   end Test_Region;

   procedure Test_Failures is
      Tool : Ks_CNL_Search_Tool;
   begin
      Section ("CNL search: run failures");
      Tool.Input_Image := Scene (120, 120, [1 => (60.0, 60.0)]);
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Operator_Not_Trained_Exception",
                          "Pattern is not trained"),
             "untrained: Error with Ks_Operator_Not_Trained_Exception");
      Tool.Pattern := Trained_Pattern (Algorithms => Linear_Search,
                                       Accuracies => Very_Fine);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 1, "trained: found");
      Tool.Run_Params.Algorithm := Linear_CNLPAS;
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception",
                          "RunParams.Algorithm must be one of the pattern's "
                          & "trained Algorithms"),
             "an algorithm the pattern was not trained for");
      Check (Tool.Results.Count = 0, "results cleared after a failed run");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Accuracy := Fine;
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception"),
             "an accuracy the pattern was not trained for");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Accept_Threshold := 1.5;
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception",
                          "RunParams.AcceptThreshold must be in 0 .. 1"),
             "AcceptThreshold above 1");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Confusion_Threshold := 0.2;
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception",
                          "RunParams.ConfusionThreshold must be >= "
                          & "RunParams.AcceptThreshold"),
             "ConfusionThreshold below AcceptThreshold");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Max_Results := 0;
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception",
                          "RunParams.MaxResults must be in 1 .. 1000"),
             "MaxResults 0");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.XY_Overlap := Zero / Zero;
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception",
                          "RunParams.XYOverlap must be in 0 .. 1"),
             "a NaN XYOverlap");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Search_Region_Mode := Affine_Transform;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 1,
             "SearchRegionMode AffineTransform without a search region: the"
             & " whole image");
      Tool.Run_Params.Search_Region_Mode := 3;
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception",
                          "RunParams.SearchRegionMode must be "
                          & "PixelAlignedBoundingBox or AffineTransform"),
             "SearchRegionMode 3");
      Tool.Run_Params := (others => <>);
      Tool.Run_Params.Algorithm := Non_Linear_CNLPAS;
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception",
                          "RunParams.Algorithm NonLinearCNLPAS is not "
                          & "supported"),
             "NonLinearCNLPAS");
      Tool.Run_Params := (others => <>);
      Tool.Input_Image := Copy (Tool.Input_Image, No_Pixels);
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Image_No_Pixels_Exception",
                          "InputImage has no pixels"),
             "an unallocated input image");
   end Test_Failures;

   procedure Test_Fixture is
      Pattern : Ks_CNL_Search_Pattern := Trained_Pattern;
      Where   : constant Point := (130.3, 95.8);
      Image   : Ks_Image_8_Grey := Scene (240, 180, [1 => Where]);
      Tree    : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
      Pose    : constant Ks_Transform_2D_Linear :=
        Create_Similarity (2.0, 0.5, 10.0, 20.0);
      Tool    : Ks_CNL_Search_Tool;
      X, Y    : Real;
      R       : Ks_CNL_Search_Result;
   begin
      Section ("CNL search: fixture spaces");
      Tree.Add_Space ("@", "Fixture", Pose);
      Image.Set_Coordinate_Space_Tree (Tree);
      Image.Set_Selected_Space_Name ("@\Fixture");
      Tool.Pattern := Pattern;
      Tool.Input_Image := Image;
      Tool.Run;
      Report (Tool, "fixture");
      Check (Tool.Results.Count = 1, "found in a fixtured image");
      Invert (Pose).Map_Point (Where.X, Where.Y, X, Y);
      if Tool.Results.Count = 1 then
         R := Tool.Results.Item (0);
         Check_Near (R.Location_X, X, 0.05, "location X in the fixture");
         Check_Near (R.Location_Y, Y, 0.05, "location Y in the fixture");
      end if;

      --  A search region given in the fixture space.
      declare
         Region : Ks_Rectangle;
         U, V   : Real;
      begin
         Invert (Pose).Map_Point (Where.X - 30.0, Where.Y - 30.0, U, V);
         Region.Set_XY_Width_Height (U - 20.0, V - 20.0, 70.0, 70.0);
         Tool.Search_Region := RH.To_Holder (Region);
         Tool.Run;
         Report (Tool, "fixture region");
         Check (Tool.Results.Count = 1, "a region in the fixture space");
         Tool.Search_Region := RH.Empty_Holder;
      end;

      --  The train image in a fixture space: the origin is given there.
      declare
         Train_Pose : constant Ks_Transform_2D_Linear :=
           Create_Similarity (0.5, -0.3, 30.0, 12.0);
         Train      : Ks_Image_8_Grey := Pattern.Train_Image;
         Train_Tree : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
         Region     : Ks_Rectangle := Train_Rectangle;
         OX, OY     : Real;
      begin
         Train := Copy (Train);
         Train_Tree.Add_Space ("@", "Part", Train_Pose);
         Train.Set_Coordinate_Space_Tree (Train_Tree);
         Train.Set_Selected_Space_Name ("@\Part");
         Invert (Train_Pose).Map_Point (Train_Centre, Train_Centre, OX, OY);
         Region.Set_Selected_Space_Name ("#");
         Pattern.Set_Train_Image (Train);
         Pattern.Set_Train_Region (RH.To_Holder (Region));
         Pattern.Set_Origin_X (OX);
         Pattern.Set_Origin_Y (OY);
         Pattern.Train;
         Tool.Pattern := Pattern;
         Tool.Input_Image := Scene (240, 180, [1 => Where]);
         Tool.Run;
         Check (Tool.Results.Count = 1
                and then Distance (Tool.Results.Item (0), Where) < 0.1,
                "an origin given in the train image's fixture space");
      end;
   end Test_Fixture;

   procedure Test_Streams is
      Pattern : constant Ks_CNL_Search_Pattern := Trained_Pattern;
      Where   : constant Point := (90.7, 75.2);
      Tool    : Ks_CNL_Search_Tool;
      Before  : Ks_CNL_Search_Result;
      After   : Ks_CNL_Search_Result;
   begin
      Section ("CNL search: streams");
      Tool.Input_Image := Scene (180, 150, [1 => Where]);
      Tool.Pattern := Pattern;
      Tool.Run;
      Check (Tool.Results.Count = 1, "found before writing");
      if Tool.Results.Count = 1 then
         Before := Tool.Results.Item (0);
      end if;

      --  Change the train image after training: the stream keeps the
      --  trained pixels.
      declare
         Train : Ks_Image_8_Grey := Pattern.Train_Image;
      begin
         Train.Fill (0);
      end;
      declare
         S    : aliased SU.Stream_Type;
         Read : Ks_CNL_Search_Pattern := Trained_Pattern (Linear_Search);
      begin
         Ks_CNL_Search_Pattern'Write (S'Access, Pattern);
         Ks_CNL_Search_Pattern'Read (S'Access, Read);
         Check (S.Element_Count = 0, "the whole pattern is read");
         Check (Read.Trained, "read back trained");
         Check (Read.Algorithms = Linear_Search + Linear_CNLPAS
                and then Read.Accuracies = Very_Fine + Fine + Coarse
                and then Read.Origin_X = Train_Centre
                and then Read.Origin_Y = Train_Centre,
                "the training parameters read back");
         Check (Read.Train_Region.Is_Empty = False
                and then Read.Train_Image.Allocated
                and then Read.Train_Image.Get_Pixel (50, 50) = 0,
                "the training inputs read back");
         Tool.Pattern := Read;
         for Algorithm in Linear_Search .. Linear_CNLPAS loop
            Tool.Run_Params.Algorithm := Algorithm;
            Tool.Run;
            Check (Tool.Results.Count = 1, "found after reading");
            if Tool.Results.Count = 1 then
               After := Tool.Results.Item (0);
               Check (After.Location_X = Before.Location_X
                      and then After.Location_Y = Before.Location_Y
                      and then After.Score = Before.Score,
                      "the same result after reading" & Algorithm'Image);
            end if;
         end loop;
         Tool.Run_Params := (others => <>);
      end;

      --  An untrained pattern.
      declare
         S       : aliased SU.Stream_Type;
         Plain   : Ks_CNL_Search_Pattern;
         Read    : Ks_CNL_Search_Pattern := Trained_Pattern;
      begin
         Plain.Set_Origin_X (12.5);
         Plain.Set_Accuracies (Coarse);
         Ks_CNL_Search_Pattern'Write (S'Access, Plain);
         Ks_CNL_Search_Pattern'Read (S'Access, Read);
         Check (not Read.Trained and then Read.Origin_X = 12.5
                and then Read.Accuracies = Coarse
                and then not Read.Train_Image.Allocated,
                "an untrained pattern reads back untrained");
      end;

      --  Malformed streams.
      declare
         S    : aliased SU.Stream_Type;
         Read : Ks_CNL_Search_Pattern := Trained_Pattern;
         Raised : Boolean := False;
      begin
         Interfaces.Unsigned_32'Write (S'Access, 16#1234_5678#);
         begin
            Ks_CNL_Search_Pattern'Read (S'Access, Read);
         exception
            when E : others =>
               Raised := Ada.Exceptions.Exception_Identity (E)
                           = Ks_Image_File_Exception'Identity;
         end;
         Check (Raised, "a wrong format code: Ks_Image_File_Exception");
         Check (Read.Trained, "the target is unchanged after a failure");
      end;
      declare
         S      : aliased SU.Stream_Type;
         Read   : Ks_CNL_Search_Pattern := Trained_Pattern;
         Raised : Boolean := False;
         Empty  : Ks_Image_8_Grey;
      begin
         Interfaces.Unsigned_32'Write (S'Access, KC.Stream_Code);
         K.Int32'Write (S'Access, 1);
         K.Int32'Write (S'Access, 1);
         K.Int32'Write (S'Access, 0);
         Real'Write (S'Access, 70.0);
         Real'Write (S'Access, 70.0);
         Ks_Image_8_Grey'Write (S'Access, Empty);
         RH.Holder'Write (S'Access, RH.Empty_Holder);
         Interfaces.Unsigned_32'Write (S'Access, 2);
         begin
            Ks_CNL_Search_Pattern'Read (S'Access, Read);
         exception
            when E : others =>
               Raised := Ada.Exceptions.Exception_Identity (E)
                           = Ks_Image_File_Exception'Identity;
         end;
         Check (Raised, "a trained flag of 2: Ks_Image_File_Exception");
      end;
      declare
         S      : aliased SU.Stream_Type;
         Read   : Ks_CNL_Search_Pattern := Trained_Pattern;
         Raised : Boolean := False;
         Empty  : Ks_Image_8_Grey;
      begin
         Interfaces.Unsigned_32'Write (S'Access, KC.Stream_Code);
         K.Int32'Write (S'Access, 1);
         K.Int32'Write (S'Access, 1);
         K.Int32'Write (S'Access, 0);
         Real'Write (S'Access, 70.0);
         Real'Write (S'Access, 70.0);
         Ks_Image_8_Grey'Write (S'Access, Empty);
         RH.Holder'Write (S'Access, RH.Empty_Holder);
         Interfaces.Unsigned_32'Write (S'Access, 1);
         Real'Write (S'Access, 1.0E200);
         Real'Write (S'Access, 0.0);
         Ks_Image_8_Grey'Write (S'Access, Scene (20, 20, [1 => (9.0, 9.0)]));
         begin
            Ks_CNL_Search_Pattern'Read (S'Access, Read);
         exception
            when E : others =>
               Raised := Ada.Exceptions.Exception_Identity (E)
                           = Ks_Bad_Parameter_Exception'Identity;
         end;
         Check (Raised, "a trained origin beyond 1.0E140: "
                & "Ks_Bad_Parameter_Exception");
         Check (Read.Trained, "the target is unchanged");
      end;
   end Test_Streams;

   ---------------------------------------------------------------------
   --  The kernel
   ---------------------------------------------------------------------

   procedure Test_Kernel is
      Image   : constant Ks_Image_8_Grey :=
        Scene (120, 100, [1 => (60.0, 50.0)]);
      Handle  : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Image);
      Region  : KR.Ks_Pixel_Region;
      Other   : KR.Ks_Pixel_Region;
      Pattern : KC.Ks_CNL_Search_Pattern;
      Copy    : KC.Ks_CNL_Search_Pattern;
      Results : KC.Ks_CNL_Search_Results;
      Params  : KC.Ks_CNL_Search_Run_Params := (others => <>);
      TP      : KC.Ks_CNL_Search_Train_Params := (others => <>);
      Id      : constant KT.Ks_Transform_2D_Linear := (others => <>);
      Item    : KC.Ks_CNL_Search_Result;
      Count   : K.Int32;
      W, H    : K.Int32;
      Flag    : K.Int32;
      X, Y    : Real;
      Pixels  : KI.Ks_Image_8_Grey;
      S       : K.Ks_Status;

      function Bad return Boolean is
        (S.Failure = K.Failure_Bad_Parameter);
   begin
      Section ("CNL search kernel: null handles and failures");
      KR.Whole_Image (120, 100, Region, S);

      --  A null pattern is untrained.
      KC.Execute (Handle, Region, null, Params, Id, Results, S);
      Check (S.Failure = K.Failure_Operator_Not_Trained and then Results = null,
             "execute: a null pattern is not trained");
      KC.Pattern_Trained (null, Flag, S);
      Check (K.Succeeded (S) and then Flag = 0, "trained: 0 for null");
      KC.Pattern_Get_Train_Params (null, TP, S);
      Check (K.Succeeded (S) and then TP = (others => <>),
             "train params: the defaults for null");
      KC.Pattern_Trained_Size (null, W, H, S);
      Check (S.Failure = K.Failure_Operator_Not_Trained and then W = 0,
             "trained size: not trained for null");
      KC.Pattern_Trained_Origin (null, X, Y, S);
      Check (S.Failure = K.Failure_Operator_Not_Trained,
             "trained origin: not trained for null");
      KC.Pattern_Get_Trained_Pattern_Image (null, Pixels, S);
      Check (S.Failure = K.Failure_Operator_Not_Trained and then Pixels = null,
             "trained pattern image: not trained for null");
      KC.Pattern_Duplicate (null, Copy, S);
      Check (K.Succeeded (S) and then Copy = null, "duplicate of null");
      KC.Pattern_Untrain (null, S);
      Check (K.Succeeded (S), "untrain null");

      --  An untrained pattern never yields results.
      KC.Pattern_Create (Pattern, S);
      Check (K.Succeeded (S) and then Pattern /= null, "create");
      KC.Execute (Handle, Region, Pattern, Params, Id, Results, S);
      Check (S.Failure = K.Failure_Operator_Not_Trained and then Results = null,
             "execute: an untrained pattern");

      --  Training.
      KC.Pattern_Train (Pattern, null, Region, Id, S);
      Check (S.Failure = K.Failure_Image_No_Pixels
             and then Text_Of (S) = "TrainImage has no pixels",
             "train: a null image");
      KC.Pattern_Train (Pattern, Handle, null, Id, S);
      Check (Bad, "train: the empty region");
      KR.Whole_Image (200, 100, Other, S);
      KC.Pattern_Train (Pattern, Handle, Other, Id, S);
      Check (Bad, "train: a region of a larger image");
      KR.Destroy (Other, S);
      KC.Pattern_Train (Pattern, Handle, Region,
                        (A => Zero / Zero, others => <>), S);
      Check (Bad, "train: a NaN transform");
      TP := (others => <>);
      TP.Origin_X := 60.0;
      TP.Origin_Y := 50.0;
      TP.Algorithms := Linear_Search + Linear_CNLPAS;
      KC.Pattern_Set_Train_Params (Pattern, TP, S);
      Check (K.Succeeded (S), "set train params");
      KC.Pattern_Train (Pattern, Handle, Region,
                        (Translation_X => 1.0E150, others => <>), S);
      Check (Bad, "train: an origin mapped beyond 1.0E150");
      KC.Pattern_Train (Pattern, Handle, Region, Id, S);
      Check (K.Succeeded (S), "train on the whole image");
      KC.Pattern_Trained_Size (Pattern, W, H, S);
      Check (K.Succeeded (S) and then W = 120 and then H = 100,
             "trained size 120 x 100");
      KC.Pattern_Trained_Origin (Pattern, X, Y, S);
      Check (K.Succeeded (S) and then X = 60.0 and then Y = 50.0,
             "trained origin in the pattern's pixels");

      --  Setting bad training parameters leaves the pattern as it was.
      for Bad_Params of Train_Params_List'
        [(Algorithms => 0, others => <>),
         (Algorithms => 4, others => <>),
         (Algorithms => 8, others => <>),
         (Accuracies => 0, others => <>),
         (Accuracies => 8, others => <>),
         (Ignore_Polarity => 2, others => <>),
         (Origin_X => Zero / Zero, others => <>),
         (Origin_Y => 1.0 / Zero, others => <>),
         (Origin_X => 2.0E150, others => <>)]
      loop
         KC.Pattern_Set_Train_Params (Pattern, Bad_Params, S);
         Check (Bad, "set train params: rejected");
      end loop;
      KC.Pattern_Trained (Pattern, Flag, S);
      Check (Flag = 1, "still trained after rejected parameters");

      --  Running.
      KC.Execute (null, Region, Pattern, Params, Id, Results, S);
      Check (S.Failure = K.Failure_Image_No_Pixels and then Results = null,
             "execute: a null image");
      KC.Execute (Handle, null, Pattern, Params, Id, Results, S);
      KC.Results_Count (Results, Count, S);
      Check (K.Succeeded (S) and then Results /= null and then Count = 0,
             "execute: the empty region gives no results");
      KC.Results_Destroy (Results);
      Check (Results = null, "results destroyed");
      KC.Execute (Handle, Region, Pattern, Params, Id, Results, S);
      KC.Results_Count (Results, Count, S);
      Check (Count = 1, "execute: one result");
      KC.Results_Item (Results, 0, Item, S);
      Check (K.Succeeded (S) and then Item.Location_X = 60.0
             and then Item.Location_Y = 50.0 and then Item.Score = 1.0,
             "the whole image found at its origin");
      KC.Results_Item (Results, 1, Item, S);
      Check (S.Failure = K.Failure_Index_Out_Of_Range,
             "item: index beyond the count");
      KC.Results_Item (Results, -1, Item, S);
      Check (S.Failure = K.Failure_Index_Out_Of_Range,
             "item: a negative index");
      KC.Results_Destroy (Results);
      KC.Results_Count (null, Count, S);
      Check (K.Succeeded (S) and then Count = 0, "count: 0 for null");
      KC.Results_Item (null, 0, Item, S);
      Check (S.Failure = K.Failure_Index_Out_Of_Range, "item of null");

      for Bad_Run of Run_Params_List'
        [(Algorithm => 3, others => <>),
         (Algorithm => 0, others => <>),
         (Algorithm => 4, others => <>),
         (Accuracy => 3, others => <>),
         (Accuracy => 2, others => <>),
         (Max_Results => 0, others => <>),
         (Max_Results => 1001, others => <>),
         (Search_Region_Mode => 0, others => <>),
         (Search_Region_Mode => 3, others => <>),
         (Accept_Threshold => -0.1, others => <>),
         (Accept_Threshold => Zero / Zero, others => <>),
         (Confusion_Threshold => 1.0 / Zero, others => <>),
         (Accept_Threshold => 0.6, Confusion_Threshold => 0.5,
          others => <>),
         (XY_Overlap => 1.5, others => <>)]
      loop
         KC.Execute (Handle, Region, Pattern, Bad_Run, Id, Results, S);
         Check (Bad and then Results = null, "execute: bad run parameters");
      end loop;
      KC.Execute (Handle, Region, Pattern, Params,
                  (D => Zero / Zero, others => <>), Results, S);
      Check (Bad and then Results = null, "execute: a NaN transform");
      KC.Execute (Handle, Region, Pattern, Params,
                  (A => 1.0E149, others => <>), Results, S);
      Check (Bad and then Results = null
             and then Text_Of (S) = "a result's location lies beyond 1.0E150",
             "execute: a location beyond 1.0E150");
      KC.Execute (Handle, Region, Pattern,
                  (Search_Region_Mode => KC.Region_Mode_Affine_Transform,
                   others             => <>), Id, Results, S);
      KC.Results_Count (Results, Count, S);
      Check (K.Succeeded (S) and then Count = 1,
             "execute: SearchRegionMode AffineTransform searches the box of "
             & "a pixel region");
      KC.Results_Destroy (Results);
      KR.Whole_Image (200, 100, Other, S);
      KC.Execute (Handle, Other, Pattern, Params, Id, Results, S);
      Check (Bad and then Results = null,
             "execute: a region that does not lie in the image");
      KR.Destroy (Other, S);
      Params.Max_Results := 1000;
      KC.Execute (Handle, Region, Pattern, Params, Id, Results, S);
      KC.Results_Count (Results, Count, S);
      Check (Count = 1, "MaxResults 1000 accepted");
      KC.Results_Destroy (Results);
      Params := (others => <>);

      --  Duplicate and untrain.
      KC.Pattern_Duplicate (Pattern, Copy, S);
      KC.Pattern_Trained (Copy, Flag, S);
      Check (Flag = 1, "a duplicate is trained");
      KC.Pattern_Untrain (Pattern, S);
      KC.Pattern_Trained (Pattern, Flag, S);
      Check (K.Succeeded (S) and then Flag = 0, "untrained");
      KC.Pattern_Trained (Copy, Flag, S);
      Check (Flag = 1, "the duplicate stays trained");
      KC.Pattern_Get_Trained_Pattern_Image (Copy, Pixels, S);
      Check (K.Succeeded (S) and then Pixels /= null,
             "trained pattern image");
      KI.Destroy (Pixels, S);

      --  Restoring (the stream helper).
      KC.Restore_Trained (Pattern, null, null, 0.0, 0.0, S);
      Check (S.Failure = K.Failure_Image_No_Pixels, "restore: no image");
      KC.Restore_Trained (Pattern, Handle, null, Zero / Zero, 0.0, S);
      Check (Bad, "restore: a NaN origin");
      KC.Restore_Trained (Pattern, Handle, null, 60.0, 50.0, S);
      Check (K.Succeeded (S), "restore");
      KC.Pattern_Trained_Origin (Pattern, X, Y, S);
      Check (X = 60.0 and then Y = 50.0, "restored origin");

      --  A flat image cannot be trained.
      declare
         Flat : constant Ks_Image_8_Grey := TI.Blank (30, 30, 40);
      begin
         KC.Restore_Trained (Pattern,
                             AMV.Images.Kernel_Images.Kernel_Handle (Flat),
                             null, 1.0, 1.0, S);
         Check (Bad, "restore: a flat image");
         KC.Pattern_Trained (Pattern, Flag, S);
         Check (Flag = 0, "untrained after a failed restore");
      end;

      KC.Pattern_Destroy (Pattern, S);
      Check (Pattern = null, "destroyed");
      KC.Pattern_Destroy (Copy, S);
      KR.Destroy (Region, S);
   end Test_Kernel;

   procedure Test_Limits is
      Pattern : Ks_CNL_Search_Pattern;
      Tool    : Ks_CNL_Search_Tool;
   begin
      Section ("CNL search kernel: limits");
      --  A pattern of more than 1024 pixels along a side.
      declare
         Wide : Ks_Image_8_Grey := TI.Blank (1100, 20, 10);
         procedure Train_Wide is
         begin
            Pattern.Train;
         end Train_Wide;
         procedure Check_Wide is new Check_Raises_Exactly
           (Train_Wide, Ks_Bad_Parameter_Exception'Identity);
      begin
         TI.Draw_Rectangle (Wide, 550.0, 10.0, 300.0, 8.0, 0.0, 200);
         Pattern.Set_Train_Image (Wide);
         Check_Wide ("a train region wider than 1024 pixels");
      end;
      --  A search box of more than 2**24 pixels.
      Tool.Pattern := Trained_Pattern;
      Tool.Input_Image := TI.Blank (4100, 4100, 0);
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception",
                          "SearchRegion: the search box must have at most "
                          & "16777216 pixels"),
             "a search box beyond Max_Search_Pixels");
   end Test_Limits;

   procedure Test_Timing is
      Where   : constant Point := (401.3, 287.6);
      Image   : Ks_Image_8_Grey := Scene (640, 480, [1 => Where]);
      Tool    : Ks_CNL_Search_Tool;
      Start   : Ada.Calendar.Time;
      use type Ada.Calendar.Time;
   begin
      Section ("CNL search: 640 x 480 timing");
      TI.Add_Noise (Image, 10.0, Seed => 3);
      Tool.Pattern := Trained_Pattern;
      Tool.Input_Image := Image;
      for Algorithm in Linear_Search .. Linear_CNLPAS loop
         Tool.Run_Params.Algorithm := Algorithm;
         Start := Ada.Calendar.Clock;
         Tool.Run;
         Ada.Text_IO.Put_Line
           ("  640 x 480, 44 x 44 pattern, "
            & (if Algorithm = Linear_Search then "LinearSearch"
               else "LinearCNLPAS") & ":"
            & Duration'Image (Ada.Calendar.Clock - Start) & " s");
         Check (Tool.Results.Count = 1
                and then Distance (Tool.Results.Item (0), Where) < 0.1,
                "found in 640 x 480" & Algorithm'Image);
      end loop;
   end Test_Timing;

   ---------------------------------------------------------------------
   --  The train image mask
   ---------------------------------------------------------------------

   procedure Texture
     (Image  : in out Ks_Image_8_Grey;
      X0, Y0 : Natural;
      Side   : Positive;
      Seed   : Natural);
   --  Fills the Side x Side pixels from (X0, Y0) with a random texture
   --  (all grey levels; the same for the same Seed).

   procedure Texture
     (Image  : in out Ks_Image_8_Grey;
      X0, Y0 : Natural;
      Side   : Positive;
      Seed   : Natural)
   is
      use type Interfaces.Unsigned_32;
      State : Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Seed) * 2_654_435_761 + 12_345;
   begin
      for Y in Y0 .. Y0 + Side - 1 loop
         for X in X0 .. X0 + Side - 1 loop
            State := State * 1_664_525 + 1_013_904_223;
            Image.Set_Pixel
              (X, Y, Grey_8 (Interfaces.Shift_Right (State, 24)));
         end loop;
      end loop;
   end Texture;

   function Block_Mask
     (Width, Height : Positive;
      X0, Y0        : Natural;
      Side          : Positive;
      Inside        : Grey_8;
      Outside       : Grey_8) return Ks_Image_8_Grey;
   --  A Width x Height mask of value Outside, Inside in the Side x Side
   --  pixels from (X0, Y0).

   function Block_Mask
     (Width, Height : Positive;
      X0, Y0        : Natural;
      Side          : Positive;
      Inside        : Grey_8;
      Outside       : Grey_8) return Ks_Image_8_Grey
   is
      Mask : Ks_Image_8_Grey := TI.Blank (Width, Height, Outside);
   begin
      for Y in Y0 .. Y0 + Side - 1 loop
         for X in X0 .. X0 + Side - 1 loop
            Mask.Set_Pixel (X, Y, Inside);
         end loop;
      end loop;
      return Mask;
   end Block_Mask;

   --  The block that changes from part to part: 12 x 12 pixels in the top
   --  right corner of the 44 x 44 pattern (pixels 32 .. 43 by 0 .. 11 of
   --  the pattern, 60 .. 71 by 28 .. 39 of the train image).

   Block_Side : constant := 12;
   Block_X    : constant := 32;
   Block_Y    : constant := 0;
   Pattern_X0 : constant := 28;
   Pattern_Y0 : constant := 28;

   function Textured_Scene
     (Width, Height : Positive;
      Where         : Point;
      Seed          : Natural) return Ks_Image_8_Grey;
   --  The composite centred at Where (whole pixels) with the block of
   --  the pattern there textured with Seed.

   function Textured_Scene
     (Width, Height : Positive;
      Where         : Point;
      Seed          : Natural) return Ks_Image_8_Grey
   is
      Image : Ks_Image_8_Grey := Scene (Width, Height, [1 => Where]);
   begin
      Texture (Image,
               Natural (Where.X - Train_Centre) + Pattern_X0 + Block_X,
               Natural (Where.Y - Train_Centre) + Pattern_Y0 + Block_Y,
               Block_Side, Seed);
      return Image;
   end Textured_Scene;

   function Masked_Pattern
     (Mask     : Ks_Image_8_Grey;
      Offset_X : Integer := 0;
      Offset_Y : Integer := 0) return Ks_CNL_Search_Pattern
   is
      Pattern : Ks_CNL_Search_Pattern;
   begin
      Pattern.Set_Train_Image
        (Textured_Scene (100, 100, (Train_Centre, Train_Centre), 1));
      Pattern.Set_Train_Region (RH.To_Holder (Train_Rectangle));
      Pattern.Set_Origin_X (Train_Centre);
      Pattern.Set_Origin_Y (Train_Centre);
      Pattern.Set_Algorithms (Linear_Search + Linear_CNLPAS);
      Pattern.Set_Accuracies (Very_Fine + Fine + Coarse);
      Pattern.Set_Train_Image_Mask (Mask);
      Pattern.Set_Train_Image_Mask_Offset_X (Offset_X);
      Pattern.Set_Train_Image_Mask_Offset_Y (Offset_Y);
      Pattern.Train;
      return Pattern;
   end Masked_Pattern;
   --  The composite with the block textured (seed 1) trained with Mask
   --  (unallocated: none) at the offsets.

   function No_Image return Ks_Image_8_Grey is
      Image : Ks_Image_8_Grey;
   begin
      return Image;
   end No_Image;
   --  An unallocated image (no mask).

   function Full_Mask return Ks_Image_8_Grey is
     (Block_Mask (100, 100, Pattern_X0 + Block_X, Pattern_Y0 + Block_Y,
                  Block_Side, 0, 255));
   --  A mask of the train image's size over the block.

   function Same (A, B : Ks_CNL_Search_Result) return Boolean is
     (A.Score = B.Score and then A.Location_X = B.Location_X
      and then A.Location_Y = B.Location_Y and then A.Contrast = B.Contrast);

   procedure Search
     (Pattern   : Ks_CNL_Search_Pattern;
      Image     : Ks_Image_8_Grey;
      Algorithm : Ks_CNL_Search_Algorithm_Constants;
      Result    : out Ks_CNL_Search_Result;
      Found     : out Boolean;
      Accuracy  : Ks_CNL_Search_Accuracy_Constants := Very_Fine);
   --  Runs the search for one result; Found when there is one.

   procedure Search
     (Pattern   : Ks_CNL_Search_Pattern;
      Image     : Ks_Image_8_Grey;
      Algorithm : Ks_CNL_Search_Algorithm_Constants;
      Result    : out Ks_CNL_Search_Result;
      Found     : out Boolean;
      Accuracy  : Ks_CNL_Search_Accuracy_Constants := Very_Fine)
   is
      Tool : Ks_CNL_Search_Tool;
   begin
      Tool.Pattern := Pattern;
      Tool.Input_Image := Image;
      Tool.Run_Params.Algorithm := Algorithm;
      Tool.Run_Params.Accuracy := Accuracy;
      Tool.Run;
      Report (Tool, "masked search");
      Found := Tool.Run_Status.Result = Accept_Result
        and then Tool.Results.Count = 1;
      Result := (if Found then Tool.Results.Item (0) else (others => <>));
   end Search;

   procedure Test_Mask is
      Where    : constant Point := (90.0, 75.0);
      Image    : constant Ks_Image_8_Grey :=
        Textured_Scene (180, 150, Where, 2);
      Other    : constant Ks_Image_8_Grey :=
        Textured_Scene (180, 150, Where, 3);
      Plain    : constant Ks_CNL_Search_Pattern :=
        Masked_Pattern (No_Image);
      Masked   : constant Ks_CNL_Search_Pattern :=
        Masked_Pattern (Full_Mask);
      R_Plain  : Ks_CNL_Search_Result;
      R_Masked : Ks_CNL_Search_Result;
      R        : Ks_CNL_Search_Result;
      R_Coarse : Ks_CNL_Search_Result;
      Found    : Boolean;
   begin
      Section ("CNL search: the train image mask");
      Check (Masked.Trained and then Masked.Train_Image_Mask.Width = 100
             and then Masked.Train_Image_Mask_Offset_X = 0
             and then Masked.Train_Image_Mask_Offset_Y = 0,
             "trained with a mask");
      Check (not Plain.Train_Image_Mask.Allocated, "no mask by default");

      --  The texture under the block changes between the train image and
      --  the searched one: without the mask the score drops, with it the
      --  instance scores 1 (the cared-for pixels are the same).
      for Algorithm in Linear_Search .. Linear_CNLPAS loop
         Search (Plain, Image, Algorithm, R_Plain, Found);
         Check (Found and then Distance (R_Plain, Where) < 0.5,
                "without the mask: found" & Algorithm'Image);
         Search (Masked, Image, Algorithm, R_Masked, Found);
         Check (Found and then R_Masked.Score > 0.999
                and then Distance (R_Masked, Where) < 0.1,
                "with the mask: score near 1 at the instance"
                & Algorithm'Image & R_Masked.Score'Image
                & Distance (R_Masked, Where)'Image);
         Check_Near (R_Masked.Contrast, 1.0, 0.01,
                     "with the mask: contrast 1" & Algorithm'Image);
         Check (R_Plain.Score < R_Masked.Score - 0.05,
                "without the mask the score is lower"
                & R_Plain.Score'Image & Algorithm'Image);
         --  Another texture under the mask: the instance's own score is
         --  the same (its neighbours' windows reach into the block with
         --  cared-for pixels, so the sub-pixel position may move; Coarse
         --  compares whole pixels).
         Search (Masked, Image, Algorithm, R_Coarse, Found, Coarse);
         Search (Masked, Other, Algorithm, R, Found, Coarse);
         Check (Found and then Same (R, R_Coarse)
                and then R.Score = R_Masked.Score,
                "another texture under the mask: the same score"
                & Algorithm'Image);
      end loop;
      Ada.Text_IO.Put_Line
        ("  block of 144 of 1936 pixels re-textured: score"
         & R_Plain.Score'Image & " without the mask,"
         & R_Masked.Score'Image & " with it");

      --  The same model from a small mask placed by its offsets, and from
      --  a mask larger than the train image at negative offsets.
      Search (Masked_Pattern
                (Block_Mask (Block_Side, Block_Side, 0, 0, Block_Side, 0, 0),
                 Pattern_X0 + Block_X, Pattern_Y0 + Block_Y),
              Image, Linear_Search, R, Found);
      Check (Found and then Same (R, R_Masked),
             "a 12 x 12 mask at offsets (60, 28): the same results");
      Search (Masked_Pattern
                (Block_Mask (130, 130, Pattern_X0 + Block_X + 10,
                             Pattern_Y0 + Block_Y + 10, Block_Side, 0, 7),
                 -10, -10),
              Image, Linear_Search, R, Found);
      Check (Found and then Same (R, R_Masked),
             "a 130 x 130 mask at offsets (-10, -10): the same results");
      Search (Masked_Pattern
                (Block_Mask (Block_Side, Block_Side, 0, 0, Block_Side, 0, 0),
                 300, 0),
              Image, Linear_Search, R, Found);
      Check (Found and then Same (R, R_Plain),
             "a mask beyond the train image: the results of no mask");

      --  A mask that leaves every pixel cared for gives exactly the
      --  results of no mask (the masked sums are those of the integral
      --  images), for every algorithm and accuracy.
      declare
         All_Care : constant Ks_CNL_Search_Pattern :=
           Masked_Pattern (TI.Blank (100, 100, 1));
         Tool_A   : Ks_CNL_Search_Tool;
         Tool_B   : Ks_CNL_Search_Tool;
         Equal    : Boolean := True;
         Noisy    : Ks_Image_8_Grey :=
           Scene (200, 160, [(60.3, 50.6), (140.0, 110.2)]);
      begin
         TI.Add_Noise (Noisy, 15.0, Seed => 4);
         Tool_A.Pattern := Plain;
         Tool_B.Pattern := All_Care;
         Tool_A.Input_Image := Noisy;
         Tool_B.Input_Image := Noisy;
         for Algorithm in Linear_Search .. Linear_CNLPAS loop
            for Accuracy of Accuracy_List'[Very_Fine, Fine, Coarse] loop
               Tool_A.Run_Params :=
                 (Algorithm => Algorithm, Accuracy => Accuracy,
                  Max_Results => 3, Accept_Threshold => 0.2, others => <>);
               Tool_B.Run_Params := Tool_A.Run_Params;
               Tool_A.Run;
               Tool_B.Run;
               Equal := Equal
                 and then Tool_A.Results.Count = 2
                 and then Tool_B.Results.Count = Tool_A.Results.Count;
               if Equal then
                  for I in 0 .. Tool_A.Results.Count - 1 loop
                     Equal := Equal
                       and then Same (Tool_A.Results.Item (I),
                                      Tool_B.Results.Item (I));
                  end loop;
               end if;
            end loop;
         end loop;
         Check (Equal, "a mask that cares for every pixel: exactly the "
                & "results of no mask");
      end;

      --  Copies and the setters.
      declare
         Copy : Ks_CNL_Search_Pattern := Masked;
      begin
         Search (Copy, Image, Linear_Search, R, Found);
         Check (Found and then Same (R, R_Masked), "a copy: the same results");
         Copy.Set_Train_Image_Mask_Offset_X (3);
         Check (not Copy.Trained and then Copy.Train_Image_Mask_Offset_X = 3,
                "setting the mask offset X untrains");
         Copy := Masked;
         Copy.Set_Train_Image_Mask_Offset_Y (-4);
         Check (not Copy.Trained and then Copy.Train_Image_Mask_Offset_Y = -4,
                "setting the mask offset Y untrains");
         Copy := Masked;
         Copy.Set_Train_Image_Mask (No_Image);
         Check (not Copy.Trained and then not Copy.Train_Image_Mask.Allocated,
                "setting the mask untrains");
         Copy.Train;
         Search (Copy, Image, Linear_Search, R, Found);
         Check (Found and then Same (R, R_Plain),
                "trained again without the mask: the results of no mask");
      end;

      --  The time of a masked search of 640 x 480 pixels (the masked sums
      --  are taken window by window).
      declare
         use type Ada.Calendar.Time;
         Big   : Ks_Image_8_Grey :=
           Textured_Scene (640, 480, (401.0, 287.0), 5);
         Start : Ada.Calendar.Time;
         Spent : array (Boolean) of Duration;
      begin
         TI.Add_Noise (Big, 10.0, Seed => 3);
         for Algorithm in Linear_Search .. Linear_CNLPAS loop
            for With_Mask in Boolean loop
               Start := Ada.Calendar.Clock;
               Search ((if With_Mask then Masked else Plain), Big, Algorithm,
                       R, Found);
               Spent (With_Mask) := Ada.Calendar.Clock - Start;
               Check (Found and then Distance (R, (401.0, 287.0)) < 0.5,
                      "640 x 480: found" & Algorithm'Image
                      & With_Mask'Image);
            end loop;
            Ada.Text_IO.Put_Line
              ("  640 x 480, 44 x 44 pattern, "
               & (if Algorithm = Linear_Search then "LinearSearch"
                  else "LinearCNLPAS") & ":"
               & Spent (False)'Image & " s without the mask,"
               & Spent (True)'Image & " s with it");
         end loop;
      end;
   end Test_Mask;

   procedure Test_Mask_Failures is
      Pattern : Ks_CNL_Search_Pattern;

      procedure Nothing_Cared is
      begin
         Pattern := Masked_Pattern (TI.Blank (100, 100, 0));
      end Nothing_Cared;

      procedure Flat_Cared is
      begin
         --  Only the 8 x 8 pixels 28 .. 35 of the background are cared for.
         Pattern := Masked_Pattern (Block_Mask (100, 100, 28, 28, 8, 1, 0));
      end Flat_Cared;

      procedure Check_Nothing is new Check_Raises_Exactly
        (Nothing_Cared, Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Flat is new Check_Raises_Exactly
        (Flat_Cared, Ks_Bad_Parameter_Exception'Identity);
   begin
      Section ("CNL search: train image mask failures");
      Check_Nothing ("a mask that leaves no pixel cared for");
      Check_Flat ("a mask that leaves only flat pixels cared for");
      Check (not Pattern.Trained, "untrained after a failed Train");
   end Test_Mask_Failures;

   procedure Test_Mask_Streams is
      Where  : constant Point := (90.0, 75.0);
      Image  : constant Ks_Image_8_Grey := Textured_Scene (180, 150, Where, 2);
      Mask   : Ks_Image_8_Grey :=
        Block_Mask (Block_Side, Block_Side, 0, 0, Block_Side, 0, 0);
      Masked : Ks_CNL_Search_Pattern;
      Before : Ks_CNL_Search_Result;
      R      : Ks_CNL_Search_Result;
      Found  : Boolean;
   begin
      Section ("CNL search: streams with the train image mask");
      Masked := Masked_Pattern (Mask, Pattern_X0 + Block_X,
                                Pattern_Y0 + Block_Y);
      Search (Masked, Image, Linear_CNLPAS, Before, Found);
      Check (Found and then Before.Score > 0.999, "found before writing");
      --  The mask changes after training (its pixels are shared): the
      --  stream keeps the care flags the pattern was trained with.
      Mask.Fill (255);
      declare
         S    : aliased SU.Stream_Type;
         Read : Ks_CNL_Search_Pattern := Trained_Pattern;
      begin
         Ks_CNL_Search_Pattern'Write (S'Access, Masked);
         Ks_CNL_Search_Pattern'Read (S'Access, Read);
         Check (S.Element_Count = 0, "the whole pattern is read");
         Check (Read.Trained and then Read.Train_Image_Mask.Width = Block_Side
                and then Read.Train_Image_Mask.Get_Pixel (5, 5) = 255
                and then Read.Train_Image_Mask_Offset_X = 60
                and then Read.Train_Image_Mask_Offset_Y = 28,
                "the mask and its offsets read back");
         for Algorithm in Linear_Search .. Linear_CNLPAS loop
            Search (Masked, Image, Algorithm, Before, Found);
            Search (Read, Image, Algorithm, R, Found);
            Check (Found and then Same (R, Before)
                   and then R.Score > 0.999,
                   "the same results after reading" & Algorithm'Image);
         end loop;
         Read.Train;
         Search (Read, Image, Linear_Search, R, Found);
         Check (Found and then R.Score < 0.99,
                "trained again with the changed mask (all care)");
      end;

      --  The format before the mask ("KSCN"): no mask, trained.
      declare
         Plain : constant Ks_CNL_Search_Pattern := Trained_Pattern;
         S     : aliased SU.Stream_Type;
         Read  : Ks_CNL_Search_Pattern := Masked;
         Empty : Ks_Image_8_Grey;
         Tool  : Ks_CNL_Search_Tool;
      begin
         Interfaces.Unsigned_32'Write (S'Access, KC.Stream_Code);
         K.Int32'Write (S'Access, Linear_Search + Linear_CNLPAS);
         K.Int32'Write (S'Access, Very_Fine + Fine + Coarse);
         K.Int32'Write (S'Access, 0);
         Real'Write (S'Access, Train_Centre);
         Real'Write (S'Access, Train_Centre);
         Ks_Image_8_Grey'Write (S'Access, Empty);
         RH.Holder'Write (S'Access, RH.To_Holder (Train_Rectangle));
         Interfaces.Unsigned_32'Write (S'Access, 1);
         Real'Write (S'Access, Train_Centre - 28.0);
         Real'Write (S'Access, Train_Centre - 28.0);
         Ks_Image_8_Grey'Write (S'Access, Plain.Get_Trained_Pattern_Image);
         Ks_CNL_Search_Pattern'Read (S'Access, Read);
         Check (S.Element_Count = 0, "the previous format is read whole");
         Check (Read.Trained and then not Read.Train_Image_Mask.Allocated
                and then Read.Train_Image_Mask_Offset_X = 0
                and then Read.Train_Image_Mask_Offset_Y = 0
                and then Read.Algorithms = Linear_Search + Linear_CNLPAS,
                "the previous format: trained, no mask");
         Tool.Input_Image := Plain.Train_Image;
         Tool.Pattern := Read;
         Tool.Run;
         Check (Tool.Results.Count = 1, "the previous format: found");
         if Tool.Results.Count = 1 then
            Check_Near (Tool.Results.Item (0).Score, 1.0, 1.0E-9,
                        "the previous format: score 1");
            Check_Near (Distance (Tool.Results.Item (0),
                                  (Train_Centre, Train_Centre)), 0.0, 1.0E-9,
                        "the previous format: at the train centre");
         end if;
      end;

      --  Care flags of the wrong size.
      declare
         S      : aliased SU.Stream_Type;
         Read   : Ks_CNL_Search_Pattern := Masked;
         Empty  : Ks_Image_8_Grey;
         Raised : Boolean := False;
      begin
         Interfaces.Unsigned_32'Write (S'Access, KC.Stream_Code_Masked);
         K.Int32'Write (S'Access, 1);
         K.Int32'Write (S'Access, 1);
         K.Int32'Write (S'Access, 0);
         Real'Write (S'Access, 70.0);
         Real'Write (S'Access, 70.0);
         Ks_Image_8_Grey'Write (S'Access, Empty);
         RH.Holder'Write (S'Access, RH.Empty_Holder);
         Ks_Image_8_Grey'Write (S'Access, Empty);
         K.Int32'Write (S'Access, 0);
         K.Int32'Write (S'Access, 0);
         Interfaces.Unsigned_32'Write (S'Access, 1);
         Real'Write (S'Access, 1.0);
         Real'Write (S'Access, 1.0);
         Ks_Image_8_Grey'Write (S'Access, Scene (20, 20, [1 => (9.0, 9.0)]));
         Ks_Image_8_Grey'Write (S'Access, TI.Blank (19, 20, 1));
         begin
            Ks_CNL_Search_Pattern'Read (S'Access, Read);
         exception
            when E : others =>
               Raised := Ada.Exceptions.Exception_Identity (E)
                           = Ks_Bad_Parameter_Exception'Identity;
         end;
         Check (Raised, "care flags of another size: "
                & "Ks_Bad_Parameter_Exception");
         Check (Read.Trained and then Read.Train_Image_Mask.Allocated,
                "the target is unchanged");
      end;
   end Test_Mask_Streams;

   procedure Test_Mask_Kernel is
      Image   : constant Ks_Image_8_Grey :=
        Scene (120, 100, [1 => (60.0, 50.0)]);
      Handle  : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Image);
      Region  : KR.Ks_Pixel_Region;
      Pattern : KC.Ks_CNL_Search_Pattern;
      Copy    : KC.Ks_CNL_Search_Pattern;
      Id      : constant KT.Ks_Transform_2D_Linear := (others => <>);
      Broken  : aliased KI.Ks_Image_8_Grey_Data;
      Care    : KI.Ks_Image_8_Grey;
      Flag    : K.Int32;
      S       : K.Ks_Status;

      use type K.Int64;
      use type KI.Grey_8_Matrix;
      use type KC.Level_Table;

      function Bad return Boolean is
        (S.Failure = K.Failure_Bad_Parameter);

      function Cared_Block (Count : Natural) return Ks_Image_8_Grey;
      --  A mask of the image's size that cares for the first Count pixels
      --  (row by row) of the 8 x 8 block from (52, 42), which holds parts
      --  of several shapes of the composite.

      function Cared_Block (Count : Natural) return Ks_Image_8_Grey is
         Mask : Ks_Image_8_Grey := TI.Blank (120, 100, 0);
         Left : Natural := Count;
      begin
         for Y in 42 .. 49 loop
            for X in 52 .. 59 loop
               if Left > 0 then
                  Mask.Set_Pixel (X, Y, 9);
                  Left := Left - 1;
               end if;
            end loop;
         end loop;
         return Mask;
      end Cared_Block;
   begin
      Section ("CNL search kernel: the train image mask");
      KR.Whole_Image (120, 100, Region, S);
      KC.Pattern_Train_Masked (Pattern, Handle, Region, Id, Broken'Access, 0,
                               0, S);
      Check (Bad and then Text_Of (S)
                            = "TrainImageMask is not a valid image handle"
             and then Pattern /= null,
             "train_masked: an inconsistent mask handle");
      KC.Pattern_Trained (Pattern, Flag, S);
      Check (K.Succeeded (S) and then Flag = 0, "untrained after it");
      KC.Pattern_Train_Masked
        (Pattern, Handle, Region, Id,
         AMV.Images.Kernel_Images.Kernel_Handle (Cared_Block (63)), 0, 0, S);
      Check (Bad and then Text_Of (S) = "TrainImageMask leaves fewer than 64 "
             & "pixels of the pattern cared for",
             "train_masked: 63 cared-for pixels");
      KC.Pattern_Train_Masked
        (Pattern, Handle, Region, Id,
         AMV.Images.Kernel_Images.Kernel_Handle (Cared_Block (64)), 0, 0, S);
      Check (K.Succeeded (S), "train_masked: 64 cared-for pixels");
      KC.Pattern_Get_Trained_Care_Image (Pattern, Care, S);
      declare
         Cared : Natural := 0;
      begin
         if K.Succeeded (S) and then Care /= null then
            for Y in 0 .. 99 loop
               for X in 0 .. 119 loop
                  if Care.Pixels (Y, X) /= 0 then
                     Cared := Cared + 1;
                  end if;
               end loop;
            end loop;
         end if;
         Check (K.Succeeded (S) and then Care /= null
                and then Care.Width = 120 and then Care.Height = 100
                and then Cared = 64 and then Care.Pixels (42, 52) = 1
                and then Care.Pixels (0, 0) = 0,
                "the trained care flags: 64 pixels of value 1");
      end;

      --  Restoring with the care flags gives the same pattern.
      KC.Pattern_Duplicate (Pattern, Copy, S);
      KC.Restore_Trained (Copy, Handle, Care, 60.0, 50.0, S);
      Check (K.Succeeded (S) and then Copy.Care /= null
             and then Copy.Care.Pixels.all = Pattern.Care.Pixels.all
             and then Copy.Info = Pattern.Info,
             "restore with the care flags: the same levels and flags");
      declare
         Small : constant Ks_Image_8_Grey := TI.Blank (10, 10, 1);
      begin
         KC.Restore_Trained
           (Copy, Handle, AMV.Images.Kernel_Images.Kernel_Handle (Small),
            60.0, 50.0, S);
         Check (Bad, "restore: care flags of another size");
      end;
      KC.Restore_Trained (Copy, Handle, Broken'Access, 60.0, 50.0, S);
      Check (Bad, "restore: inconsistent care flags");
      KI.Destroy (Care, S);

      --  Without a mask there are no care flags.
      KC.Pattern_Train_Masked (Pattern, Handle, Region, Id, null, 5, 5, S);
      Check (K.Succeeded (S) and then Pattern.Care = null
             and then Pattern.Info (0).Count = 120 * 100,
             "train_masked with a null mask: no care flags");
      KC.Pattern_Get_Trained_Care_Image (Pattern, Care, S);
      Check (K.Succeeded (S) and then Care = null,
             "trained care image: null without a mask");
      KC.Pattern_Untrain (Pattern, S);
      KC.Pattern_Get_Trained_Care_Image (Pattern, Care, S);
      Check (S.Failure = K.Failure_Operator_Not_Trained and then Care = null,
             "trained care image: not trained");
      KC.Pattern_Get_Trained_Care_Image (null, Care, S);
      Check (S.Failure = K.Failure_Operator_Not_Trained,
             "trained care image: not trained for null");
      declare
         Masked, Moded : Boolean;
      begin
         KC.Check_Stream_Code (KC.Stream_Code, Masked, Moded, S);
         Check (K.Succeeded (S) and then not Masked and then not Moded,
                "stream code KSCN");
         KC.Check_Stream_Code (KC.Stream_Code_Masked, Masked, Moded, S);
         Check (K.Succeeded (S) and then Masked and then not Moded,
                "stream code KSCM");
         KC.Check_Stream_Code (KC.Stream_Code_Region_Mode, Masked, Moded, S);
         Check (K.Succeeded (S) and then Masked and then Moded,
                "stream code KSCR");
      end;
      KC.Pattern_Destroy (Pattern, S);
      KC.Pattern_Destroy (Copy, S);
      KR.Destroy (Region, S);
   end Test_Mask_Kernel;

   ---------------------------------------------------------------------
   --  Partial matches
   ---------------------------------------------------------------------

   --  The brute-force reference: a 16 x 12 random texture pattern
   --  (trained on the whole of its own image, origin at its first pixel,
   --  so that a location is the window's first pixel), pasted partly
   --  outside each side of a 64 x 52 random image with noise added; the
   --  test computes the clipped correlation at every position of the
   --  search area extended by the limits with 64-bit integer sums, as the
   --  kernel specification defines it, finds the local maxima by the
   --  kernel's rule, and compares them, sorted, with the results of a
   --  LinearSearch / Coarse run (scores, whole-pixel locations, contrasts
   --  and EdgeHit).

   type Int_Matrix is array (Integer range <>, Integer range <>) of Integer;
   --  Grey levels indexed (Y, X).

   function Pixels_Of (Image : Ks_Image_8_Grey) return Int_Matrix is
      Result : Int_Matrix (0 .. Image.Height - 1, 0 .. Image.Width - 1);
   begin
      for Y in Result'Range (1) loop
         for X in Result'Range (2) loop
            Result (Y, X) := Integer (Image.Get_Pixel (X, Y));
         end loop;
      end loop;
      return Result;
   end Pixels_Of;

   function Noise_Image
     (Width, Height : Positive;
      Seed          : Natural) return Ks_Image_8_Grey;
   --  A Width x Height image of random grey levels (Texture's generator).

   function Noise_Image
     (Width, Height : Positive;
      Seed          : Natural) return Ks_Image_8_Grey
   is
      use type Interfaces.Unsigned_32;
      Image : Ks_Image_8_Grey := TI.Blank (Width, Height, 0);
      State : Interfaces.Unsigned_32 :=
        Interfaces.Unsigned_32 (Seed) * 2_654_435_761 + 12_345;
   begin
      for Y in 0 .. Height - 1 loop
         for X in 0 .. Width - 1 loop
            State := State * 1_664_525 + 1_013_904_223;
            Image.Set_Pixel
              (X, Y, Grey_8 (Interfaces.Shift_Right (State, 24)));
         end loop;
      end loop;
      return Image;
   end Noise_Image;

   procedure Paste
     (Image  : in out Ks_Image_8_Grey;
      Source : Ks_Image_8_Grey;
      X0, Y0 : Integer);
   --  Copies Source into Image with its first pixel at (X0, Y0), leaving
   --  out the pixels that fall outside Image.

   procedure Paste
     (Image  : in out Ks_Image_8_Grey;
      Source : Ks_Image_8_Grey;
      X0, Y0 : Integer) is
   begin
      for V in 0 .. Source.Height - 1 loop
         for U in 0 .. Source.Width - 1 loop
            if X0 + U in 0 .. Image.Width - 1
              and then Y0 + V in 0 .. Image.Height - 1
            then
               Image.Set_Pixel (X0 + U, Y0 + V, Source.Get_Pixel (U, V));
            end if;
         end loop;
      end loop;
   end Paste;

   Texture_Width  : constant := 16;
   Texture_Height : constant := 12;

   function Texture_Pattern
     (Mask : Ks_Image_8_Grey) return Ks_CNL_Search_Pattern;
   --  The 16 x 12 random texture trained on its whole image, origin at
   --  its first pixel, LinearSearch, every accuracy, with Mask (of the
   --  pattern's size; unallocated: none).

   function Texture_Image return Ks_Image_8_Grey is
     (Noise_Image (Texture_Width, Texture_Height, 11));

   function Texture_Pattern
     (Mask : Ks_Image_8_Grey) return Ks_CNL_Search_Pattern
   is
      Pattern : Ks_CNL_Search_Pattern;
   begin
      Pattern.Set_Train_Image (Texture_Image);
      Pattern.Set_Origin_X (0.0);
      Pattern.Set_Origin_Y (0.0);
      Pattern.Set_Algorithms (Linear_Search + Linear_CNLPAS);
      Pattern.Set_Accuracies (Very_Fine + Fine + Coarse);
      Pattern.Set_Train_Image_Mask (Mask);
      Pattern.Train;
      return Pattern;
   end Texture_Pattern;

   function Partial_Scene return Ks_Image_8_Grey is
      Image : Ks_Image_8_Grey := Noise_Image (64, 52, 7);
   begin
      Paste (Image, Texture_Image, -5, 20);   --  5 columns out on the left
      Paste (Image, Texture_Image, 55, 8);    --  7 out on the right
      Paste (Image, Texture_Image, 24, -4);   --  4 rows out at the top
      Paste (Image, Texture_Image, 40, 45);   --  5 out at the bottom
      Paste (Image, Texture_Image, -3, -2);   --  the top left corner
      Paste (Image, Texture_Image, 20, 25);   --  inside
      TI.Add_Noise (Image, 20.0, Seed => 9);
      return Image;
   end Partial_Scene;
   --  The texture pasted partly outside each side, at a corner and inside
   --  a random image, with noise.

   type Partial_Setup is record
      Box_X, Box_Y : Natural := 0;
      Box_W, Box_H : Positive := 1;
      Whole        : Boolean := True;
      Left, Right  : Natural := 0;
      Up, Down     : Natural := 0;
      Reduce       : Boolean := False;
   end record;
   --  A run: the search area (the whole image when Whole), the limits and
   --  PartialMatchReduceScore.

   type Reference_Value is record
      Score    : Real := 0.0;
      Contrast : Real := 0.0;
   end record;

   function Reference
     (Image   : Int_Matrix;
      Pattern : Int_Matrix;
      Care    : Int_Matrix;
      S       : Partial_Setup;
      WX, WY  : Integer) return Reference_Value
   is
      subtype Big is Long_Long_Integer;
      Total : Big := 0;
      N, SP, SP2, SW, SW2, SPW : Big := 0;
   begin
      for V in Pattern'Range (1) loop
         for U in Pattern'Range (2) loop
            if Care (V, U) /= 0 then
               Total := Total + 1;
               if WX + U in S.Box_X .. S.Box_X + S.Box_W - 1
                 and then WY + V in S.Box_Y .. S.Box_Y + S.Box_H - 1
               then
                  declare
                     P : constant Big := Big (Pattern (V, U));
                     W : constant Big := Big (Image (WY + V, WX + U));
                  begin
                     N := N + 1;
                     SP := SP + P;
                     SP2 := SP2 + P * P;
                     SW := SW + W;
                     SW2 := SW2 + W * W;
                     SPW := SPW + P * W;
                  end;
               end if;
            end if;
         end loop;
      end loop;
      if N = 0 or else 4 * N < Total then
         return (others => <>);
      end if;
      declare
         PS  : constant Big := N * SP2 - SP * SP;
         WS  : constant Big := N * SW2 - SW * SW;
         Num : constant Big := N * SPW - SP * SW;
         R   : Reference_Value;
      begin
         if PS <= 0 or else WS <= 0 then
            return (others => <>);
         end if;
         R.Contrast := EF.Sqrt (Real (WS) / Real (PS));
         if Num > 0 then
            declare
               M      : constant Real := Real (Num);
               Square : constant Real := M * M;
               Den    : constant Real := Real (PS) * Real (WS);
            begin
               R.Score := (if Square >= Den then 1.0 else Square / Den);
            end;
         end if;
         if S.Reduce and then N < Total then
            R.Score := R.Score * (Real (N) / Real (Total));
         end if;
         return R;
      end;
   end Reference;
   --  The score and the contrast of the window whose first pixel lies at
   --  (WX, WY) of Image, over the cared-for pixels of Pattern (Care /= 0)
   --  whose window pixel lies in the search area of S (the kernel's
   --  definition, with exact integer sums).

   type Expected_Result is record
      X, Y     : Integer := 0;
      Score    : Real := 0.0;
      Contrast : Real := 0.0;
      Edge_Hit : Ks_CNL_Search_Edge_Hit_Constants := None;
   end record;

   type Expected_List is array (Positive range <>) of Expected_Result;

   procedure Compare_With_Reference
     (Description : String;
      Image       : Ks_Image_8_Grey;
      Mask        : Ks_Image_8_Grey;
      S           : Partial_Setup;
      Threshold   : Real;
      Minimum     : Natural := 1);
   --  Runs a LinearSearch / Coarse search of the texture pattern (with
   --  Mask) in Image with S and compares its results with the local
   --  maxima of the reference scores (at least Minimum of them).

   procedure Compare_With_Reference
     (Description : String;
      Image       : Ks_Image_8_Grey;
      Mask        : Ks_Image_8_Grey;
      S           : Partial_Setup;
      Threshold   : Real;
      Minimum     : Natural := 1)
   is
      Pixels  : constant Int_Matrix := Pixels_Of (Image);
      Pattern : constant Int_Matrix := Pixels_Of (Texture_Image);
      Care    : Int_Matrix (Pattern'Range (1), Pattern'Range (2)) :=
        [others => [others => 1]];
      Area    : Partial_Setup := S;
      Last_X  : Integer;
      Last_Y  : Integer;
      Tool    : Ks_CNL_Search_Tool;
   begin
      if Mask.Allocated then
         Care := Pixels_Of (Mask);
      end if;
      if S.Whole then
         Area.Box_X := 0;
         Area.Box_Y := 0;
         Area.Box_W := Image.Width;
         Area.Box_H := Image.Height;
      end if;
      Last_X := Area.Box_W - Texture_Width + S.Left + S.Right;
      Last_Y := Area.Box_H - Texture_Height + S.Up + S.Down;
      declare
         Scores  : array (0 .. Last_Y, 0 .. Last_X) of Reference_Value;
         Found   : Expected_List (1 .. (Last_X + 1) * (Last_Y + 1));
         Count   : Natural := 0;
         Equal   : Boolean := True;
         Message : Ada.Strings.Unbounded.Unbounded_String;

         function Peak (X, Y : Integer) return Boolean;
         --  The kernel's local maximum: above the neighbours before it in
         --  raster order, at least those after it.

         function Peak (X, Y : Integer) return Boolean is
            Centre : constant Real := Scores (Y, X).Score;
         begin
            for DY in -1 .. 1 loop
               for DX in -1 .. 1 loop
                  if (DX /= 0 or else DY /= 0)
                    and then X + DX in 0 .. Last_X
                    and then Y + DY in 0 .. Last_Y
                  then
                     declare
                        Other : constant Real :=
                          Scores (Y + DY, X + DX).Score;
                     begin
                        if DY < 0 or else (DY = 0 and then DX < 0) then
                           if Centre <= Other then
                              return False;
                           end if;
                        elsif Centre < Other then
                           return False;
                        end if;
                     end;
                  end if;
               end loop;
            end loop;
            return True;
         end Peak;
      begin
         for Y in 0 .. Last_Y loop
            for X in 0 .. Last_X loop
               Scores (Y, X) :=
                 Reference (Pixels, Pattern, Care, Area,
                            Area.Box_X - S.Left + X, Area.Box_Y - S.Up + Y);
            end loop;
         end loop;
         --  The maxima, best first (ties in raster order).
         for Y in 0 .. Last_Y loop
            for X in 0 .. Last_X loop
               if Scores (Y, X).Score >= Threshold and then Peak (X, Y) then
                  declare
                     WX   : constant Integer := Area.Box_X - S.Left + X;
                     WY   : constant Integer := Area.Box_Y - S.Up + Y;
                     Item : constant Expected_Result :=
                       (X        => WX,
                        Y        => WY,
                        Score    => Scores (Y, X).Score,
                        Contrast => Scores (Y, X).Contrast,
                        Edge_Hit =>
                          (if WX < Area.Box_X then Left else None)
                          + (if WY < Area.Box_Y then Top else None)
                          + (if WX > Area.Box_X + Area.Box_W - Texture_Width
                             then Right else None)
                          + (if WY > Area.Box_Y + Area.Box_H - Texture_Height
                             then Bottom else None));
                     Slot : Positive := Count + 1;
                  begin
                     while Slot > 1 and then Found (Slot - 1).Score < Item.Score
                     loop
                        Found (Slot) := Found (Slot - 1);
                        Slot := Slot - 1;
                     end loop;
                     Found (Slot) := Item;
                     Count := Count + 1;
                  end;
               end if;
            end loop;
         end loop;

         Tool.Pattern := Texture_Pattern (Mask);
         Tool.Input_Image := Image;
         if not S.Whole then
            declare
               R : Ks_Rectangle;
            begin
               R.Set_XY_Width_Height
                 (Real (S.Box_X) - 0.5, Real (S.Box_Y) - 0.5, Real (S.Box_W),
                  Real (S.Box_H));
               Tool.Search_Region := RH.To_Holder (R);
            end;
         end if;
         Tool.Run_Params :=
           (Algorithm                  => Linear_Search,
            Accuracy                   => Coarse,
            Max_Results                => 1000,
            Accept_Threshold           => Threshold,
            Confusion_Threshold        => 1.0,
            Partial_Match_Limit_Left   => K.Int32 (S.Left),
            Partial_Match_Limit_Right  => K.Int32 (S.Right),
            Partial_Match_Limit_Up     => K.Int32 (S.Up),
            Partial_Match_Limit_Down   => K.Int32 (S.Down),
            Partial_Match_Reduce_Score => Boolean'Pos (S.Reduce),
            others                     => <>);
         Tool.Run;
         Report (Tool, Description);
         if Tool.Results.Count /= Natural'Min (Count, 1000) then
            Equal := False;
            Ada.Strings.Unbounded.Append
              (Message, " count" & Tool.Results.Count'Image & " expected"
               & Count'Image);
         else
            for I in 1 .. Natural'Min (Count, 1000) loop
               declare
                  R : constant Ks_CNL_Search_Result :=
                    Tool.Results.Item (I - 1);
                  E : constant Expected_Result := Found (I);
               begin
                  if not (R.Location_X = Real (E.X)
                          and then R.Location_Y = Real (E.Y)
                          and then abs (R.Score - E.Score) <= 1.0E-12
                          and then abs (R.Contrast - E.Contrast) <= 1.0E-9
                          and then R.Edge_Hit = E.Edge_Hit)
                  then
                     if Equal then
                        Ada.Strings.Unbounded.Append
                          (Message, " result" & I'Image & ":"
                           & R.Location_X'Image & R.Location_Y'Image
                           & R.Score'Image & R.Edge_Hit'Image
                           & " expected" & E.X'Image & E.Y'Image
                           & E.Score'Image & E.Edge_Hit'Image);
                     end if;
                     Equal := False;
                  end if;
               end;
            end loop;
         end if;
         Check (Equal and then Count >= Minimum,
                Description & ": the" & Count'Image
                & " local maxima of the clipped correlation"
                & Ada.Strings.Unbounded.To_String (Message));
         declare
            Partial : Natural := 0;
         begin
            for I in 1 .. Count loop
               if Found (I).Edge_Hit /= None then
                  Partial := Partial + 1;
               end if;
            end loop;
            Ada.Text_IO.Put_Line
              ("  " & Description & ":" & Count'Image & " maxima of"
               & Natural'Image ((Last_X + 1) * (Last_Y + 1))
               & " positions," & Partial'Image & " of them partial");
         end;
      end;
   end Compare_With_Reference;

   function Edge_Count
     (Tool : Ks_CNL_Search_Tool;
      Flag : Ks_CNL_Search_Edge_Hit_Constants) return Natural;
   --  The number of results whose EdgeHit is exactly Flag.

   function Edge_Count
     (Tool : Ks_CNL_Search_Tool;
      Flag : Ks_CNL_Search_Edge_Hit_Constants) return Natural
   is
      Result : Natural := 0;
   begin
      for I in 0 .. Tool.Results.Count - 1 loop
         if Tool.Results.Item (I).Edge_Hit = Flag then
            Result := Result + 1;
         end if;
      end loop;
      return Result;
   end Edge_Count;

   procedure Test_Partial_Reference is
      Image  : constant Ks_Image_8_Grey := Partial_Scene;
      Holes  : Ks_Image_8_Grey := TI.Blank (Texture_Width, Texture_Height, 1);
      Narrow : Ks_Image_8_Grey := TI.Blank (Texture_Width, Texture_Height, 0);
      Tool   : Ks_CNL_Search_Tool;
   begin
      Section ("CNL search: partial matches against a brute-force reference");
      --  Don't-care pixels: the first 3 columns and a 4 x 4 block.
      for Y in 0 .. Texture_Height - 1 loop
         for X in 0 .. 2 loop
            Holes.Set_Pixel (X, Y, 0);
         end loop;
      end loop;
      for Y in 5 .. 8 loop
         for X in 9 .. 12 loop
            Holes.Set_Pixel (X, Y, 0);
         end loop;
      end loop;
      --  Cared-for pixels: the first 10 columns only.
      for Y in 0 .. Texture_Height - 1 loop
         for X in 0 .. 9 loop
            Narrow.Set_Pixel (X, Y, 1);
         end loop;
      end loop;

      --  Every instance is found once the limits reach it.
      Tool.Pattern := Texture_Pattern (No_Image);
      Tool.Input_Image := Image;
      Tool.Run_Params.Max_Results := 10;
      Tool.Run_Params.Accept_Threshold := 0.5;
      Tool.Run;
      Check (Tool.Results.Count = 1 and then Edge_Count (Tool, None) = 1,
             "limits 0: only the instance inside");
      Tool.Run_Params.Partial_Match_Limit_Left := 8;
      Tool.Run_Params.Partial_Match_Limit_Right := 8;
      Tool.Run_Params.Partial_Match_Limit_Up := 6;
      Tool.Run_Params.Partial_Match_Limit_Down := 6;
      Tool.Run;
      Check (Tool.Results.Count = 6
             and then Edge_Count (Tool, None) = 1
             and then Edge_Count (Tool, Left) = 1
             and then Edge_Count (Tool, Right) = 1
             and then Edge_Count (Tool, Top) = 1
             and then Edge_Count (Tool, Bottom) = 1
             and then Edge_Count (Tool, Left + Top) = 1,
             "the largest limits: every instance, with its EdgeHit");

      Compare_With_Reference ("limits 0", Image, No_Image, (others => <>),
                              0.01, 20);
      Compare_With_Reference
        ("limits 8, 8, 6, 6", Image, No_Image,
         (Left => 8, Right => 8, Up => 6, Down => 6, others => <>), 0.01, 20);
      Compare_With_Reference
        ("limits 8, 8, 6, 6, ReduceScore", Image, No_Image,
         (Left => 8, Right => 8, Up => 6, Down => 6, Reduce => True,
          others => <>), 0.01, 20);
      Compare_With_Reference
        ("limits 3, 7, 0, 5 in a box", Image, No_Image,
         (Box_X => 4, Box_Y => 3, Box_W => 55, Box_H => 46, Whole => False,
          Left => 3, Right => 7, Up => 0, Down => 5, others => <>), 0.01, 20);
      Compare_With_Reference
        ("a mask, limits 8, 8, 6, 6", Image, Holes,
         (Left => 8, Right => 8, Up => 6, Down => 6, others => <>), 0.01, 20);
      Compare_With_Reference
        ("a mask, limits 8, 8, 6, 6, ReduceScore", Image, Holes,
         (Left => 8, Right => 8, Up => 6, Down => 6, Reduce => True,
          others => <>), 0.01, 20);
      --  A mask that cares for the first 10 columns only: a window that
      --  crosses the left side by 8 keeps 2 of them, fewer than a quarter.
      Compare_With_Reference
        ("a narrow mask, limits 8, 8, 6, 6, ReduceScore", Image, Narrow,
         (Left => 8, Right => 8, Up => 6, Down => 6, Reduce => True,
          others => <>), 0.01, 20);
   end Test_Partial_Reference;

   type Side_Case is record
      Where    : Point;
      Edge_Hit : Ks_CNL_Search_Edge_Hit_Constants;
      Inside   : Real;
   end record;
   --  A composite centred at Where in a 200 x 160 image, the EdgeHit of
   --  its window and the fraction of the pattern inside the image.

   type Side_Case_List is array (Positive range <>) of Side_Case;

   procedure Set_Limits
     (Tool                    : in out Ks_CNL_Search_Tool;
      Left, Right, Up, Down   : K.Int32;
      Reduce                  : Boolean := False);

   procedure Set_Limits
     (Tool                    : in out Ks_CNL_Search_Tool;
      Left, Right, Up, Down   : K.Int32;
      Reduce                  : Boolean := False) is
   begin
      Tool.Run_Params.Partial_Match_Limit_Left := Left;
      Tool.Run_Params.Partial_Match_Limit_Right := Right;
      Tool.Run_Params.Partial_Match_Limit_Up := Up;
      Tool.Run_Params.Partial_Match_Limit_Down := Down;
      Tool.Run_Params.Partial_Match_Reduce_Score := Boolean'Pos (Reduce);
   end Set_Limits;

   procedure Test_Partial_Sides is
      --  The window of the composite is 44 x 44 pixels with the centre at
      --  its pixel (22, 22): centred on a side of the image, half of it
      --  lies outside (the largest limit, 22).
      Exact : constant Side_Case_List :=
        [((0.0, 80.0), Left, 0.5),
         ((200.0, 80.0), Right, 0.5),
         ((100.0, 0.0), Top, 0.5),
         ((100.0, 160.0), Bottom, 0.5),
         ((0.0, 0.0), Left + Top, 0.25),
         ((200.0, 160.0), Right + Bottom, 0.25)];
      Fractional : constant Side_Case_List :=
        [((1.3, 80.4), Left, 0.0),
         ((198.6, 80.3), Right, 0.0),
         ((100.3, 1.4), Top, 0.0),
         ((100.6, 158.7), Bottom, 0.0),
         ((1.4, 158.3), Left + Bottom, 0.0),
         ((10.6, 70.2), Left, 0.0)];
      Tool  : Ks_CNL_Search_Tool;
      Worst : Real := 0.0;
   begin
      Section ("CNL search: patterns half outside each side");
      Tool.Pattern := Trained_Pattern;
      for C of Exact loop
         Tool.Input_Image := Scene (200, 160, [1 => C.Where]);
         Tool.Run_Params := (Accuracy => Coarse, Accept_Threshold => 0.2,
                             others => <>);
         Tool.Run;
         Check (Tool.Run_Status.Result = Accept_Result
                and then (Tool.Results.Count = 0
                          or else Tool.Results.Item (0).Score < 0.9),
                "limits 0: not found at" & C.Where.X'Image
                & C.Where.Y'Image);
         Set_Limits (Tool, 22, 22, 22, 22);
         for Reduce in Boolean loop
            Tool.Run_Params.Partial_Match_Reduce_Score := Boolean'Pos (Reduce);
            Tool.Run;
            Report (Tool, "half outside");
            if Tool.Results.Count >= 1 then
               declare
                  R : constant Ks_CNL_Search_Result := Tool.Results.Item (0);
               begin
                  Check (R.Location_X = C.Where.X
                         and then R.Location_Y = C.Where.Y
                         and then abs (R.Score
                                       - (if Reduce then C.Inside else 1.0))
                                    <= 1.0E-12
                         and then abs (R.Contrast - 1.0) <= 1.0E-9
                         and then R.Edge_Hit = C.Edge_Hit,
                         "found exactly at" & C.Where.X'Image
                         & C.Where.Y'Image & ", ReduceScore "
                         & Reduce'Image & ":" & R.Location_X'Image
                         & R.Location_Y'Image & R.Score'Image
                         & R.Edge_Hit'Image);
               end;
            else
               Fail ("found at" & C.Where.X'Image & C.Where.Y'Image);
            end if;
         end loop;
      end loop;

      --  Sub-pixel positions, the defaults otherwise (VeryFine).
      for C of Fractional loop
         Tool.Input_Image := Scene (200, 160, [1 => C.Where]);
         Tool.Run_Params := (others => <>);
         Set_Limits (Tool, 22, 22, 22, 22);
         Tool.Run;
         if Tool.Results.Count = 1 then
            declare
               R : constant Ks_CNL_Search_Result := Tool.Results.Item (0);
            begin
               Worst := Real'Max (Worst, Distance (R, C.Where));
               Check (R.Score > 0.9 and then R.Edge_Hit = C.Edge_Hit,
                      "sub-pixel: score and EdgeHit at" & C.Where.X'Image
                      & C.Where.Y'Image & R.Score'Image & R.Edge_Hit'Image);
            end;
         else
            Fail ("sub-pixel: one result at" & C.Where.X'Image
                  & C.Where.Y'Image);
         end if;
      end loop;
      Ada.Text_IO.Put_Line
        ("  partial windows: largest position error (VeryFine)"
         & Worst'Image & " pixel");
      Check (Worst < 0.15,
             "partial windows, VeryFine: within 0.15 pixel (about half of "
             & "the pattern inside)");

      --  A search region smaller than the image: the area's side is the
      --  reference, and the image pixels beyond it do not count.
      declare
         R : Ks_Rectangle;
      begin
         Tool.Input_Image := Scene (200, 160, [1 => (100.0, 80.0)]);
         R.Set_XY_Width_Height (89.5, 9.5, 110.0, 140.0);
         Tool.Search_Region := RH.To_Holder (R);
         Tool.Run_Params := (Accuracy => Coarse, others => <>);
         Tool.Run;
         Check (Tool.Results.Count = 0
                or else Tool.Results.Item (0).Score < 0.9,
                "a region that cuts the instance, limits 0: not found");
         Set_Limits (Tool, 22, 0, 0, 0, Reduce => True);
         Tool.Run;
         Check (Tool.Results.Count = 1
                and then Distance (Tool.Results.Item (0), (100.0, 80.0)) = 0.0
                and then abs (Tool.Results.Item (0).Score - 32.0 / 44.0)
                           <= 1.0E-12
                and then Tool.Results.Item (0).Edge_Hit = Left,
                "a region that cuts the instance by 12 columns, limit 22: "
                & "found, EdgeHit Left, score reduced to 32/44");
         Tool.Search_Region := RH.Empty_Holder;
      end;

      --  XYOverlap and MaxResults: two instances 35 rows apart, both half
      --  outside on the left (their windows share 9/44 of their area).
      Tool.Input_Image := Scene (200, 160, [(2.0, 40.0), (2.0, 75.0)]);
      Tool.Run_Params := (Accuracy => Coarse, Max_Results => 2,
                          others => <>);
      Set_Limits (Tool, 22, 22, 22, 22);
      Tool.Run;
      Check (Tool.Results.Count = 2 and then Edge_Count (Tool, Left) = 2,
             "two partial instances, XYOverlap 1");
      Tool.Run_Params.XY_Overlap := 0.3;
      Tool.Run;
      Check (Tool.Results.Count = 2, "XYOverlap 0.3 keeps both");
      Tool.Run_Params.XY_Overlap := 0.1;
      Tool.Run;
      Check (Tool.Results.Count = 1, "XYOverlap 0.1 drops one");
      Tool.Run_Params.XY_Overlap := 1.0;
      Tool.Run_Params.Max_Results := 1;
      Tool.Run;
      Check (Tool.Results.Count = 1
             and then Tool.Results.Item (0).Edge_Hit = Left,
             "MaxResults 1");

      --  The train image mask: when the pattern's columns outside are all
      --  don't-care, a partial window scores as a whole one, and
      --  ReduceScore leaves it (every cared-for pixel is inside).
      declare
         Mask   : Ks_Image_8_Grey := TI.Blank (100, 100, 1);
         Masked : Ks_CNL_Search_Pattern := Trained_Pattern;
      begin
         for Y in 0 .. 99 loop
            for X in 0 .. 49 loop
               Mask.Set_Pixel (X, Y, 0);
            end loop;
         end loop;
         Masked.Set_Train_Image_Mask (Mask);
         Masked.Train;
         Tool.Pattern := Masked;
         Tool.Input_Image := Scene (200, 160, [1 => (0.0, 80.0)]);
         Tool.Run_Params := (Accuracy => Coarse, others => <>);
         Set_Limits (Tool, 22, 22, 22, 22, Reduce => True);
         Tool.Run;
         Check (Tool.Results.Count = 1
                and then Distance (Tool.Results.Item (0), (0.0, 80.0)) = 0.0
                and then Tool.Results.Item (0).Score = 1.0
                and then Tool.Results.Item (0).Edge_Hit = Left,
                "a mask whose cared-for half lies inside: score 1, "
                & "not reduced");
      end;
   end Test_Partial_Sides;

   procedure Test_Partial_Defaults is
      type Golden is record
         Score, X, Y, Contrast : Real;
      end record;
      type Golden_List is array (1 .. 2) of Golden;
      --  The results of the kernel before partial matches (origin/main
      --  before this change), with the default limits: the noisy scene
      --  below, MaxResults 3, AcceptThreshold 0.2 (the same for both
      --  algorithms).
      Plain_Very_Fine  : constant Golden_List :=
        [(9.4520931744878967E-01, 1.4000697173067368E+02,
          1.1016040268803438E+02, 1.0203600626857601E+00),
         (8.9568713326738791E-01, 6.0341939101613306E+01,
          5.0587352312249337E+01, 1.0209955978546850E+00)];
      Plain_Fine       : constant Golden_List :=
        [(9.4520931744878967E-01, 1.3992636213392927E+02,
          1.1015314233392795E+02, 1.0203600626857601E+00),
         (8.9568713326738791E-01, 6.0421449239200541E+01,
          5.0586939154059777E+01, 1.0209955978546850E+00)];
      Masked_Very_Fine : constant Golden_List :=
        [(9.4801119970027148E-01, 1.4000718287685984E+02,
          1.1016110674486725E+02, 1.0190952901885237E+00),
         (8.9838709165085950E-01, 6.0269224861225496E+01,
          5.0580263496842122E+01, 1.0188085954800643E+00)];
      Masked_Fine      : constant Golden_List :=
        [(9.4801119970027148E-01, 1.3992682037295657E+02,
          1.1015223908874803E+02, 1.0190952901885237E+00),
         (8.9838709165085950E-01, 6.0419370020858373E+01,
          5.0588642193823389E+01, 1.0188085954800643E+00)];
      Noisy : Ks_Image_8_Grey :=
        Scene (200, 160, [(60.3, 50.6), (140.0, 110.2)]);
      Tool  : Ks_CNL_Search_Tool;

      function Matches (Expected : Golden_List) return Boolean is
        (Tool.Results.Count = 2
         and then (for all I in 1 .. 2 =>
                     abs (Tool.Results.Item (I - 1).Score
                          - Expected (I).Score) <= 1.0E-12
                     and then abs (Tool.Results.Item (I - 1).Location_X
                                   - Expected (I).X) <= 1.0E-9
                     and then abs (Tool.Results.Item (I - 1).Location_Y
                                   - Expected (I).Y) <= 1.0E-9
                     and then abs (Tool.Results.Item (I - 1).Contrast
                                   - Expected (I).Contrast) <= 1.0E-12
                     and then Tool.Results.Item (I - 1).Edge_Hit = None));
   begin
      Section ("CNL search: the default limits give the results of before");
      TI.Add_Noise (Noisy, 15.0, Seed => 4);
      Tool.Input_Image := Noisy;
      for With_Mask in Boolean loop
         Tool.Pattern :=
           (if With_Mask then Masked_Pattern (Full_Mask)
            else Trained_Pattern);
         for Algorithm in Linear_Search .. Linear_CNLPAS loop
            for Accuracy of Accuracy_List'[Very_Fine, Fine] loop
               for Reduce in Boolean loop
                  Tool.Run_Params :=
                    (Algorithm => Algorithm, Accuracy => Accuracy,
                     Max_Results => 3, Accept_Threshold => 0.2,
                     Partial_Match_Reduce_Score => Boolean'Pos (Reduce),
                     others => <>);
                  Tool.Run;
                  Check (Matches
                           (if With_Mask
                            then (if Accuracy = Very_Fine
                                  then Masked_Very_Fine else Masked_Fine)
                            else (if Accuracy = Very_Fine
                                  then Plain_Very_Fine else Plain_Fine)),
                         "the results of before: mask " & With_Mask'Image
                         & ", algorithm" & Algorithm'Image & ", accuracy"
                         & Accuracy'Image & ", ReduceScore "
                         & Reduce'Image);
               end loop;
            end loop;
         end loop;
      end loop;
   end Test_Partial_Defaults;

   procedure Test_Partial_Failures is
      Tool : Ks_CNL_Search_Tool;

      procedure Expect (Message : String; Description : String) is
      begin
         Tool.Run;
         Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception", Message)
                and then Tool.Results.Count = 0, Description);
      end Expect;
   begin
      Section ("CNL search: partial match parameter failures");
      Tool.Pattern := Trained_Pattern;
      Tool.Input_Image := Scene (200, 160, [1 => (0.0, 80.0)]);
      Set_Limits (Tool, 23, 0, 0, 0);
      Expect ("RunParams.PartialMatchLimitLeft must be in 0 .. "
              & "TrainedPatternWidth / 2", "Left beyond half the width");
      Set_Limits (Tool, 0, -1, 0, 0);
      Expect ("RunParams.PartialMatchLimitRight must be in 0 .. "
              & "TrainedPatternWidth / 2", "a negative Right");
      Set_Limits (Tool, 0, 0, 23, 0);
      Expect ("RunParams.PartialMatchLimitUp must be in 0 .. "
              & "TrainedPatternHeight / 2", "Up beyond half the height");
      Set_Limits (Tool, 0, 0, 0, K.Int32'Last);
      Expect ("RunParams.PartialMatchLimitDown must be in 0 .. "
              & "TrainedPatternHeight / 2", "a huge Down");
      Set_Limits (Tool, 0, 0, 0, 0);
      Tool.Run_Params.Partial_Match_Reduce_Score := 2;
      Expect ("RunParams.PartialMatchReduceScore must be 0 or 1",
              "ReduceScore 2");
      Set_Limits (Tool, 5, 0, 0, 0);
      Tool.Run_Params.Algorithm := Linear_CNLPAS;
      Expect ("RunParams.PartialMatchLimitLeft, Right, Up and Down must be "
              & "0 with LinearCNLPAS", "LinearCNLPAS with a limit");
      Set_Limits (Tool, 0, 0, 0, 0, Reduce => True);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result,
             "LinearCNLPAS with the limits 0 and ReduceScore 1");
      Tool.Run_Params := (others => <>);
      Set_Limits (Tool, 22, 22, 22, 22);
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 1,
             "the limits 22 = TrainedPatternWidth / 2 are accepted");
   end Test_Partial_Failures;

   procedure Test_Partial_Kernel is
      Image   : constant Ks_Image_8_Grey := Texture_Image;
      Handle  : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Image);
      Big     : constant Ks_Image_8_Grey := Partial_Scene;
      Region  : KR.Ks_Pixel_Region;
      Pattern : KC.Ks_CNL_Search_Pattern;
      Results : KC.Ks_CNL_Search_Results;
      Params  : KC.Ks_CNL_Search_Run_Params := (others => <>);
      Id      : constant KT.Ks_Transform_2D_Linear := (others => <>);
      Item    : KC.Ks_CNL_Search_Result;
      S       : K.Ks_Status;
      Probe   : constant KC.Ks_CNL_Search_Run_Params := (others => <>);
   begin
      Section ("CNL search kernel: partial matches");
      Check (KC.Ks_CNL_Search_Run_Params'Object_Size = 64 * 8
             and then Probe.Partial_Match_Limit_Left'Position = 40
             and then Probe.Partial_Match_Reduce_Score'Position = 56
             and then KC.Ks_CNL_Search_Result'Object_Size = 48 * 8,
             "run parameter and result layout match include/amv_cnl_search.h");
      Check (Params.Partial_Match_Limit_Left = 0
             and then Params.Partial_Match_Limit_Right = 0
             and then Params.Partial_Match_Limit_Up = 0
             and then Params.Partial_Match_Limit_Down = 0
             and then Params.Partial_Match_Reduce_Score = 0,
             "the partial match defaults: 0");
      KC.Pattern_Set_Train_Params
        (Pattern,
         (Algorithms => Linear_Search + Linear_CNLPAS,
          Accuracies => Very_Fine + Fine + Coarse,
          Origin_X   => 0.0,
          Origin_Y   => 0.0,
          others     => <>), S);
      KR.Whole_Image (Texture_Width, Texture_Height, Region, S);
      KC.Pattern_Train (Pattern, Handle, Region, Id, S);
      Check (K.Succeeded (S), "train the texture");
      KR.Destroy (Region, S);
      KR.Whole_Image (64, 52, Region, S);
      Params.Accuracy := Coarse;
      Params.Max_Results := 10;
      Params.Accept_Threshold := 0.5;
      Params.Partial_Match_Limit_Left := 8;
      Params.Partial_Match_Limit_Right := 3;
      Params.Partial_Match_Limit_Up := 6;
      Params.Partial_Match_Limit_Down := 1;
      KC.Execute (AMV.Images.Kernel_Images.Kernel_Handle (Big), Region,
                  Pattern, Params, Id, Results, S);
      Check (K.Succeeded (S) and then Results /= null
             and then Results.Area_X_First = -8
             and then Results.Area_Y_First = -6
             and then Results.Area_X_Last = 64 - 16 + 3
             and then Results.Area_Y_Last = 52 - 12 + 1
             and then Results.Margin_Left = 8 and then Results.Margin_Right = 3
             and then Results.Margin_Up = 6 and then Results.Margin_Down = 1,
             "the scored positions: the image extended by the limits");
      --  The instances 5 columns out on the left, 4 rows out at the top,
      --  at the corner and inside (7 out on the right and 5 at the bottom
      --  exceed the limits 3 and 1).
      if Results /= null then
         Check (Results.Count = 4, "four instances within the limits");
         for I in 0 .. Integer (Results.Count) - 1 loop
            KC.Results_Item (Results, K.Int32 (I), Item, S);
            Check (Item.Edge_Hit
                     = (if Item.Location_X < 0.0 then Left else None)
                       + (if Item.Location_Y < 0.0 then Top else None)
                   and then Item.Edge_Hit = KC.Edge_Hit_Of
                                              (Results.Items (I), Results),
                   "EdgeHit of result" & I'Image & Item.Edge_Hit'Image);
         end loop;
      end if;
      KC.Results_Destroy (Results);
      Params.Algorithm := Linear_CNLPAS;
      KC.Execute (AMV.Images.Kernel_Images.Kernel_Handle (Big), Region,
                  Pattern, Params, Id, Results, S);
      Check (S.Failure = K.Failure_Bad_Parameter and then Results = null
             and then Text_Of (S) = "RunParams.PartialMatchLimitLeft, "
                                    & "Right, Up and Down must be 0 with "
                                    & "LinearCNLPAS",
             "execute: LinearCNLPAS with limits");
      Params.Algorithm := Linear_Search;
      for Bad_Run of Run_Params_List'
        [(Partial_Match_Limit_Left => 9, others => <>),
         (Partial_Match_Limit_Right => -3, others => <>),
         (Partial_Match_Limit_Up => 7, others => <>),
         (Partial_Match_Limit_Down => K.Int32'First, others => <>),
         (Partial_Match_Reduce_Score => -1, others => <>)]
      loop
         KC.Execute (AMV.Images.Kernel_Images.Kernel_Handle (Big), Region,
                     Pattern, Bad_Run, Id, Results, S);
         Check (S.Failure = K.Failure_Bad_Parameter and then Results = null,
                "execute: partial match parameters out of range ("
                & Text_Of (S) & ")");
      end loop;
      KC.Pattern_Destroy (Pattern, S);
      KR.Destroy (Region, S);
   end Test_Partial_Kernel;

   procedure Test_Train_Region_Mode is
      type Algorithm_List is array (Positive range <>)
        of Ks_CNL_Search_Algorithm_Constants;
      type Image_List is array (Positive range <>) of Ks_Image_8_Grey;
      type Mode_List is array (Positive range <>) of K.Int32;
      Train  : constant Ks_Image_8_Grey :=
        Textured_Scene (100, 100, (Train_Centre, Train_Centre), 1);
      T      : constant Grey_8_Matrix := Train.To_Matrix;
      Where  : constant Point := (90.0, 75.0);
      Adjust : constant K.Int32 := Pixel_Aligned_Bounding_Box_Adjust_Mask;
      Box    : constant K.Int32 := Pixel_Aligned_Bounding_Box;

      function Disc return RH.Holder is
         C : Ks_Circle;
      begin
         C.Set_Center_Radius (Train_Centre, Train_Centre, 20.0);
         return RH.To_Holder (C);
      end Disc;

      R  : constant AMV.Regions.Pixel_Region :=
        AMV.Regions.Rasterize (Train, Disc);
      DX : constant Integer := Integer (Where.X - Train_Centre);
      DY : constant Integer := Integer (Where.Y - Train_Centre);

      function Disc_Mask return Ks_Image_8_Grey is
        (From_Matrix
           ([for Y in T'Range (1) =>
               [for X in T'Range (2) =>
                  (if R.Contains (X, Y) then 255 else 0)]]));
      --  A train image mask marking the disc's pixels "care".

      function Search_Scene (Corners : Boolean) return Ks_Image_8_Grey is
         S : Grey_8_Matrix :=
           Textured_Scene (180, 150, Where, 2).To_Matrix;
      begin
         --  The train pixels of the disc's box at the place of the match;
         --  with Corners, the box's pixels outside the disc differ.
         for Y in R.Y_Min .. R.Y_Min + R.Height - 1 loop
            for X in R.X_Min .. R.X_Min + R.Width - 1 loop
               S (Y + DY, X + DX) :=
                 (if R.Contains (X, Y) or else not Corners then T (Y, X)
                  else T (Y, X) + 97);
            end loop;
         end loop;
         return From_Matrix (S);
      end Search_Scene;

      function Pattern_Of
        (Region     : RH.Holder;
         Mode       : K.Int32;
         Algorithms : Ks_CNL_Search_Algorithm_Constants :=
           Linear_Search + Linear_CNLPAS;
         Mask       : Ks_Image_8_Grey := No_Image)
         return Ks_CNL_Search_Pattern
      is
         Pattern : Ks_CNL_Search_Pattern;
      begin
         Pattern.Set_Train_Image (Train);
         Pattern.Set_Train_Region (Region);
         Pattern.Set_Origin_X (Train_Centre);
         Pattern.Set_Origin_Y (Train_Centre);
         Pattern.Set_Algorithms (Algorithms);
         Pattern.Set_Accuracies (Very_Fine + Fine + Coarse);
         Pattern.Set_Train_Region_Mode (Mode);
         if Mask.Allocated then
            Pattern.Set_Train_Image_Mask (Mask);
         end if;
         Pattern.Train;
         return Pattern;
      end Pattern_Of;

      Corners : constant Ks_Image_8_Grey := Search_Scene (True);
      Plain   : constant Ks_Image_8_Grey := Search_Scene (False);
      Masked  : constant Ks_CNL_Search_Pattern := Pattern_Of (Disc, Adjust);
      Whole   : constant Ks_CNL_Search_Pattern := Pattern_Of (Disc, Box);
      A, B    : Ks_CNL_Search_Result;
      FA, FB  : Boolean;
   begin
      Section ("CNL search: TrainRegionMode");
      declare
         Pattern : Ks_CNL_Search_Pattern;
      begin
         Check (Pattern.Train_Region_Mode = Adjust,
                "the default is Pixel_Aligned_Bounding_Box_Adjust_Mask");
      end;
      Check (Masked.Trained and then Whole.Trained
             and then Masked.Trained_Pattern_Width = R.Width
             and then Whole.Trained_Pattern_Width = R.Width
             and then R.Width < 44 and then R.Pixel_Count < R.Width * R.Height,
             "both modes train the disc's box");
      --  Adjust_Mask: the box's pixels outside the disc are don't-care, as
      --  a train image mask of the disc makes them.
      for Algorithm of Algorithm_List'(Linear_Search, Linear_CNLPAS) loop
         for Scene of Image_List'(Corners, Plain) loop
            Search (Masked, Scene, Algorithm, A, FA);
            Search (Pattern_Of (Disc, Box, Mask => Disc_Mask), Scene,
                    Algorithm, B, FB);
            Check (FA and then FB and then Same (A, B),
                   "Adjust_Mask gives the results of a train image mask of"
                   & " the region (" & Algorithm'Image & ")");
         end loop;
      end loop;
      Search (Masked, Corners, Linear_Search, A, FA);
      Search (Whole, Corners, Linear_Search, B, FB);
      Check (FA and then abs (A.Score - 1.0) < 1.0E-9
             and then abs (A.Location_X - Where.X) < 0.02
             and then abs (A.Location_Y - Where.Y) < 0.02,
             "Adjust_Mask: the corners of the box change nothing:"
             & A.Score'Image & A.Location_X'Image & A.Location_Y'Image);
      Check (FB and then B.Score < 0.95,
             "Pixel_Aligned_Bounding_Box: they lower the score:"
             & B.Score'Image);
      --  LinearCNLPAS alone treats the region as its box, as VisionPro.
      Search (Pattern_Of (Disc, Adjust, Linear_CNLPAS), Corners,
              Linear_CNLPAS, A, FA);
      Search (Pattern_Of (Disc, Box, Linear_CNLPAS), Corners, Linear_CNLPAS,
              B, FB);
      Check (FA and then FB and then Same (A, B),
             "a pattern for LinearCNLPAS alone: the whole box");
      --  A rectangle fills its box: both modes give one pattern.
      Search (Pattern_Of (RH.To_Holder (Train_Rectangle), Adjust), Corners,
              Linear_Search, A, FA);
      Search (Pattern_Of (RH.To_Holder (Train_Rectangle), Box), Corners,
              Linear_Search, B, FB);
      Check (FA and then FB and then Same (A, B),
             "a rectangle: the same pattern in both modes");

      Section ("CNL search: TrainRegionMode errors and streams");
      declare
         Pattern : Ks_CNL_Search_Pattern := Masked;
         Raised  : Boolean;
         Message : Ada.Strings.Unbounded.Unbounded_String;
      begin
         for Mode of Mode_List'(3, -1) loop
            Raised := False;
            begin
               Pattern.Set_Train_Region_Mode (Mode);
            exception
               when E : Ks_Bad_Parameter_Exception =>
                  Raised := True;
                  Message := Ada.Strings.Unbounded.To_Unbounded_String
                               (Ada.Exceptions.Exception_Message (E));
            end;
            Check (Raised and then Pattern.Train_Region_Mode = Adjust,
                   "Train_Region_Mode" & Mode'Image & ": "
                   & Ada.Strings.Unbounded.To_String (Message));
         end loop;
         Pattern := Masked;
         Pattern.Set_Train_Region_Mode (Box);
         Check (not Pattern.Trained and then Pattern.Train_Region_Mode = Box,
                "the setter untrains the pattern");
         declare
            Thin : Ks_Rectangle_Affine;
         begin
            Thin.Set_Center_Lengths_Rotation_Skew
              (Train_Centre, Train_Centre, 40.0, 1.2, 0.785, 0.0);
            Raised := False;
            begin
               Pattern := Pattern_Of (RH.To_Holder (Thin), Adjust);
            exception
               when E : Ks_Bad_Parameter_Exception =>
                  Raised := True;
                  Message := Ada.Strings.Unbounded.To_Unbounded_String
                               (Ada.Exceptions.Exception_Message (E));
            end;
            Check (Raised
                   and then Ada.Strings.Unbounded.To_String (Message)
                     = "TrainRegion (TrainRegionMode "
                       & "PixelAlignedBoundingBoxAdjustMask) and "
                       & "TrainImageMask leave fewer than 64 pixels of the "
                       & "pattern cared for",
                   "a thin region leaves too few pixels: "
                   & Ada.Strings.Unbounded.To_String (Message));
         end;
         for Mode of Mode_List'(Adjust, Box) loop
            declare
               S    : aliased SU.Stream_Type;
               Back : Ks_CNL_Search_Pattern;
               P    : constant Ks_CNL_Search_Pattern :=
                 Pattern_Of (Disc, Mode);
            begin
               Ks_CNL_Search_Pattern'Write (S'Access, P);
               Ks_CNL_Search_Pattern'Read (S'Access, Back);
               Search (Back, Corners, Linear_Search, A, FA);
               Search (P, Corners, Linear_Search, B, FB);
               Check (Back.Train_Region_Mode = Mode and then Back.Trained
                      and then FA and then FB and then Same (A, B),
                      "a stream keeps the mode and the trained pattern"
                      & Mode'Image);
            end;
         end loop;
         declare
            S    : aliased SU.Stream_Type;
            Back : Ks_CNL_Search_Pattern;
            Empty : Ks_Image_8_Grey;
         begin
            --  A pattern written before the mode existed ("KSCM").
            Interfaces.Unsigned_32'Write (S'Access, KC.Stream_Code_Masked);
            K.Int32'Write (S'Access, 1);
            K.Int32'Write (S'Access, 1);
            K.Int32'Write (S'Access, 0);
            Real'Write (S'Access, 70.0);
            Real'Write (S'Access, 70.0);
            Ks_Image_8_Grey'Write (S'Access, Empty);
            RH.Holder'Write (S'Access, RH.Empty_Holder);
            Ks_Image_8_Grey'Write (S'Access, Empty);
            K.Int32'Write (S'Access, 0);
            K.Int32'Write (S'Access, 0);
            Interfaces.Unsigned_32'Write (S'Access, 0);
            Ks_CNL_Search_Pattern'Read (S'Access, Back);
            Check (Back.Train_Region_Mode = Box and then not Back.Trained,
                   "an older stream reads as Pixel_Aligned_Bounding_Box");
         end;
      end;
   end Test_Train_Region_Mode;

   ---------------------------------------------------------------------
   --  The AffineTransform region mode
   ---------------------------------------------------------------------

   type Algorithm_List is array (Positive range <>)
     of Ks_CNL_Search_Algorithm_Constants;

   function Turned (X, Y, Angle : Real) return Point is
     ((EF.Cos (Angle) * X - EF.Sin (Angle) * Y,
       EF.Sin (Angle) * X + EF.Cos (Angle) * Y));
   --  (X, Y) turned by Angle (radians, AMV's sense of rotation).

   function Plus (P : Point; D : Point) return Point is
     ((P.X + D.X, P.Y + D.Y));

   procedure Draw_Turned
     (Image  : in out Ks_Image_8_Grey;
      CX, CY : Real;
      Angle  : Real);
   --  The composite of Draw_Composite turned by Angle about (CX, CY).

   procedure Draw_Turned
     (Image  : in out Ks_Image_8_Grey;
      CX, CY : Real;
      Angle  : Real)
   is
      function X (DX, DY : Real) return Real is
        (CX + Turned (DX, DY, Angle).X);
      function Y (DX, DY : Real) return Real is
        (CY + Turned (DX, DY, Angle).Y);
   begin
      TI.Draw_Rectangle (Image, X (-5.0, -3.0), Y (-5.0, -3.0), 22.0, 7.0,
                         0.31 + Angle, 220);
      TI.Draw_Circle (Image, X (9.0, 8.0), Y (9.0, 8.0), 6.5, 30);
      TI.Draw_Rectangle (Image, X (6.0, -10.0), Y (6.0, -10.0), 9.0, 5.0,
                         -0.53 + Angle, 170);
      TI.Draw_Polygon (Image,
                       [X (-14.3, 6.2), Y (-14.3, 6.2),
                        X (-4.1, 14.6), Y (-4.1, 14.6),
                        X (-12.7, 15.3), Y (-12.7, 15.3)],
                       210);
      TI.Draw_Circle (Image, X (-9.0, -12.0), Y (-9.0, -12.0), 3.5, 60);
   end Draw_Turned;

   function Turned_Scene
     (Width, Height : Positive;
      Where         : Point;
      Angle         : Real) return Ks_Image_8_Grey
   is
      Image : Ks_Image_8_Grey :=
        TI.Blank (Width, Height, Grey_8 (Background));
   begin
      Draw_Turned (Image, Where.X, Where.Y, Angle);
      return Image;
   end Turned_Scene;
   --  A Width x Height image with the composite turned by Angle at Where.

   function Affine
     (CX, CY, Side_X, Side_Y, Rotation : Real;
      Skew                             : Real := 0.0)
      return Ks_Rectangle_Affine
   is
      R : Ks_Rectangle_Affine;
   begin
      R.Set_Center_Lengths_Rotation_Skew
        (CX, CY, Side_X, Side_Y, Rotation, Skew);
      return R;
   end Affine;

   function Train_Failure (Pattern : in out Ks_CNL_Search_Pattern)
      return String;
   --  Trains Pattern: "" when that succeeds, otherwise the name and the
   --  message of the exception.

   function Train_Failure (Pattern : in out Ks_CNL_Search_Pattern)
      return String is
   begin
      Pattern.Train;
      return "";
   exception
      when E : others =>
         return Ada.Exceptions.Exception_Name (E) & ": "
           & Ada.Exceptions.Exception_Message (E);
   end Train_Failure;

   Turn : constant := 0.5;
   --  The angle of the turned parts and rectangles (radians).

   Spot : constant Point := (9.0, 8.0);
   --  The centre of the composite's dark circle, from its centre: the
   --  origin of the patterns of these tests.

   function Turned_Pattern
     (Mask     : Ks_Image_8_Grey := No_Image;
      Offset_X : Integer := 0;
      Offset_Y : Integer := 0) return Ks_CNL_Search_Pattern
   is
      Origin  : constant Point := Turned (Spot.X, Spot.Y, Turn);
      Pattern : Ks_CNL_Search_Pattern;
   begin
      Pattern.Set_Train_Image
        (Turned_Scene (120, 120, (60.0, 60.0), Turn));
      Pattern.Set_Train_Region
        (RH.To_Holder (Affine (60.0, 60.0, 44.0, 44.0, Turn)));
      Pattern.Set_Origin_X (60.0 + Origin.X);
      Pattern.Set_Origin_Y (60.0 + Origin.Y);
      Pattern.Set_Algorithms (Linear_Search + Linear_CNLPAS);
      Pattern.Set_Accuracies (Very_Fine + Fine + Coarse);
      Pattern.Set_Train_Region_Mode (Affine_Transform);
      if Mask.Allocated then
         Pattern.Set_Train_Image_Mask (Mask);
         Pattern.Set_Train_Image_Mask_Offset_X (Offset_X);
         Pattern.Set_Train_Image_Mask_Offset_Y (Offset_Y);
      end if;
      Pattern.Train;
      return Pattern;
   end Turned_Pattern;
   --  The composite turned by Turn at (60, 60) of a 120 x 120 image,
   --  trained in the mode AffineTransform from the 44 x 44 rectangle
   --  turned with it, with the dark circle's centre as its origin.

   function Spot_Pattern return Ks_CNL_Search_Pattern is
      Pattern : Ks_CNL_Search_Pattern := Trained_Pattern;
   begin
      Pattern.Set_Origin_X (Train_Centre + Spot.X);
      Pattern.Set_Origin_Y (Train_Centre + Spot.Y);
      Pattern.Train;
      return Pattern;
   end Spot_Pattern;
   --  The composite trained upright (pixel aligned), with the dark
   --  circle's centre as its origin.

   function Same_Results (A, B : Ks_CNL_Search_Tool; Tolerance : Real)
      return Boolean;
   --  Both runs succeeded with the same results: the same scores,
   --  contrasts and EdgeHit, the locations within Tolerance.

   function Same_Results (A, B : Ks_CNL_Search_Tool; Tolerance : Real)
      return Boolean is
   begin
      if A.Run_Status.Result /= Accept_Result
        or else B.Run_Status.Result /= Accept_Result
        or else A.Results.Count /= B.Results.Count
      then
         return False;
      end if;
      for I in 0 .. A.Results.Count - 1 loop
         declare
            RA : constant Ks_CNL_Search_Result := A.Results.Item (I);
            RB : constant Ks_CNL_Search_Result := B.Results.Item (I);
         begin
            if RA.Score /= RB.Score or else RA.Contrast /= RB.Contrast
              or else RA.Edge_Hit /= RB.Edge_Hit
              or else abs (RA.Location_X - RB.Location_X) > Tolerance
              or else abs (RA.Location_Y - RB.Location_Y) > Tolerance
            then
               return False;
            end if;
         end;
      end loop;
      return True;
   end Same_Results;

   procedure Test_Affine_Train is
      Where   : constant Point := (90.3, 75.6);
      Upright : constant Ks_Image_8_Grey := Scene (180, 150, [1 => Where]);
      Pattern : constant Ks_CNL_Search_Pattern := Turned_Pattern;
      R, B    : Ks_CNL_Search_Result;
      Found   : Boolean;
      FB      : Boolean;
   begin
      Section ("CNL search: TrainRegionMode AffineTransform");
      Check (Pattern.Trained
             and then Pattern.Train_Region_Mode = Affine_Transform
             and then Pattern.Trained_Pattern_Width = 44
             and then Pattern.Trained_Pattern_Height = 44,
             "a turned 44 x 44 affine rectangle trains a 44 x 44 pattern");
      --  The pattern is the part upright, and its origin the circle's
      --  centre wherever the part lies.
      for Algorithm of Algorithm_List'(Linear_Search, Linear_CNLPAS) loop
         for Accuracy of Accuracy_List'(Very_Fine, Fine) loop
            Search (Pattern, Upright, Algorithm, R, Found, Accuracy);
            Check (Found and then R.Score > 0.95
                   and then Distance (R, Plus (Where, Spot)) < 0.1,
                   "trained turned, found upright at the trained point ("
                   & Algorithm'Image & Accuracy'Image & "):"
                   & R.Score'Image & R.Location_X'Image
                   & R.Location_Y'Image);
         end loop;
      end loop;
      Search (Spot_Pattern, Upright, Linear_Search, B, FB);
      Search (Pattern, Upright, Linear_Search, R, Found);
      Check (Found and then FB
             and then abs (R.Location_X - B.Location_X) < 0.1
             and then abs (R.Location_Y - B.Location_Y) < 0.1,
             "the location of the same part trained upright");

      --  A rectangle along the axes on whole pixels resamples exactly the
      --  pixels of its box: the pattern of PixelAlignedBoundingBox.
      declare
         Boxed      : Ks_CNL_Search_Pattern := Trained_Pattern;
         Affine_Box : Ks_CNL_Search_Pattern := Trained_Pattern;
      begin
         Boxed.Set_Train_Region_Mode (Pixel_Aligned_Bounding_Box);
         Boxed.Train;
         Affine_Box.Set_Train_Region
           (RH.To_Holder (Affine (49.5, 49.5, 44.0, 44.0, 0.0)));
         Affine_Box.Set_Train_Region_Mode (Affine_Transform);
         Affine_Box.Train;
         Check (Affine_Box.Get_Trained_Pattern_Image.To_Matrix
                  = Boxed.Get_Trained_Pattern_Image.To_Matrix,
                "an upright rectangle on whole pixels: the box's pixels");
         Search (Boxed, Upright, Linear_Search, B, FB);
         Search (Affine_Box, Upright, Linear_Search, R, Found);
         Check (Found and then FB and then Same (R, B),
                "... and the results of the box");
      end;

      --  The region and the origin in a fixture of the train image turned
      --  with the part: a rectangle along the fixture's axes.
      declare
         Pose  : constant Ks_Transform_2D_Linear :=
           Create_Similarity (2.0, Turn, 60.0, 60.0);
         Tree  : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
         Train : Ks_Image_8_Grey :=
           Turned_Scene (120, 120, (60.0, 60.0), Turn);
         P     : Ks_CNL_Search_Pattern;
      begin
         Tree.Add_Space ("@", "Part", Pose);
         Train.Set_Coordinate_Space_Tree (Tree);
         Train.Set_Selected_Space_Name ("@\Part");
         P.Set_Train_Image (Train);
         --  The part's 44 x 44 pixels are 22 x 22 units of the fixture.
         P.Set_Train_Region
           (RH.To_Holder (Affine (0.0, 0.0, 22.0, 22.0, 0.0)));
         P.Set_Origin_X (Spot.X / 2.0);
         P.Set_Origin_Y (Spot.Y / 2.0);
         P.Set_Train_Region_Mode (Affine_Transform);
         P.Train;
         Search (P, Upright, Linear_Search, R, Found);
         Check (P.Trained and then P.Trained_Pattern_Width = 44
                and then Found and then R.Score > 0.95
                and then Distance (R, Plus (Where, Spot)) < 0.1,
                "a train region and an origin in a turned fixture:"
                & R.Score'Image & R.Location_X'Image & R.Location_Y'Image);
      end;

      --  The train image mask, resampled with the rectangle: on whole
      --  pixels, exactly the mask of the box (at offsets too).
      declare
         Image : constant Ks_Image_8_Grey :=
           Textured_Scene (180, 150, (90.0, 75.0), 2);
         Block : constant Ks_Image_8_Grey :=
           TI.Blank (Block_Side, Block_Side, 0);

         function Affine_Masked
           (Mask : Ks_Image_8_Grey; OX, OY : Integer)
            return Ks_CNL_Search_Pattern
         is
            P : Ks_CNL_Search_Pattern := Masked_Pattern (Mask, OX, OY);
         begin
            P.Set_Train_Region
              (RH.To_Holder (Affine (49.5, 49.5, 44.0, 44.0, 0.0)));
            P.Set_Train_Region_Mode (Affine_Transform);
            P.Train;
            return P;
         end Affine_Masked;
      begin
         Search (Masked_Pattern (Full_Mask), Image, Linear_Search, B, FB);
         Search (Affine_Masked (Full_Mask, 0, 0), Image, Linear_Search, R,
                 Found);
         Check (Found and then FB and then Same (R, B)
                and then abs (R.Score - 1.0) < 1.0E-9
                and then Distance (R, (90.0, 75.0)) < 0.1,
                "a mask resampled on whole pixels: the box's care flags");
         Search (Masked_Pattern (Block, Pattern_X0 + Block_X,
                                 Pattern_Y0 + Block_Y),
                 Image, Linear_CNLPAS, B, FB);
         Search (Affine_Masked (Block, Pattern_X0 + Block_X,
                                Pattern_Y0 + Block_Y),
                 Image, Linear_CNLPAS, R, Found);
         Check (Found and then FB and then Same (R, B)
                and then abs (R.Score - 1.0) < 1.0E-9,
                "... with the mask's offsets (LinearCNLPAS)");
      end;

      --  Turned: a mask over the left half of the train image leaves the
      --  part of the pattern there out, so that the left half of the part
      --  may change.
      declare
         Left_Half : constant Ks_Image_8_Grey := TI.Blank (60, 120, 0);
         Changed   : Ks_Image_8_Grey := Copy (Upright);
         Masked    : constant Ks_CNL_Search_Pattern :=
           Turned_Pattern (Left_Half);
         Plain     : Ks_CNL_Search_Result;
         FP        : Boolean;
      begin
         --  A bright bar over the part's left side, beyond the circle.
         TI.Draw_Rectangle (Changed, Where.X - 12.0, Where.Y, 6.0, 30.0,
                            0.0, 250);
         Search (Masked, Changed, Linear_Search, R, Found);
         Search (Turned_Pattern, Changed, Linear_Search, Plain, FP);
         Check (Found and then FP and then R.Score > Plain.Score + 0.1
                and then Distance (R, Plus (Where, Spot)) < 0.15,
                "a turned mask: the masked part does not count:"
                & R.Score'Image & Plain.Score'Image & R.Location_X'Image
                & R.Location_Y'Image);
      end;
   end Test_Affine_Train;

   procedure Test_Affine_Train_Failures is
      type Holder_List is array (Positive range <>) of RH.Holder;

      Bad    : constant String := "AMV.KS_BAD_PARAMETER_EXCEPTION: ";
      Circle : Ks_Circle;
      Box    : Ks_Rectangle;

      function Failure_With (Region : RH.Holder) return String is
         P : Ks_CNL_Search_Pattern := Turned_Pattern;
      begin
         P.Set_Train_Region (Region);
         return Message : constant String := Train_Failure (P) do
            Check (not P.Trained, "untrained after: " & Message);
         end return;
      end Failure_With;

      function Starts_With (S, Prefix : String) return Boolean is
        (S'Length >= Prefix'Length
         and then S (S'First .. S'First + Prefix'Length - 1) = Prefix);
   begin
      Section ("CNL search: TrainRegionMode AffineTransform failures");
      Circle.Set_Center_Radius (60.0, 60.0, 25.0);
      Box.Set_XY_Width_Height (37.5, 37.5, 44.0, 44.0);
      for Region of Holder_List'(RH.To_Holder (Box), RH.To_Holder (Circle),
                                 RH.Empty_Holder)
      loop
         declare
            Message : constant String := Failure_With (Region);
         begin
            Check (Message
                     = Bad & "TrainRegion must be an affine rectangle for "
                       & "TrainRegionMode AffineTransform",
                   "a train region that is not an affine rectangle: "
                   & Message);
         end;
      end loop;
      Check (Failure_With (RH.To_Holder (Affine (25.0, 60.0, 44.0, 44.0,
                                                  Turn)))
               = Bad & "TrainRegion must lie entirely in TrainImage for "
                 & "TrainRegionMode AffineTransform",
             "a rectangle partly outside the train image");
      Check (Failure_With (RH.To_Holder (Affine (60.0, 60.0, 44.0, 7.4,
                                                  Turn)))
               = Bad & "TrainRegion must span at least 8 x 8 pixels",
             "a rectangle less than 8 pixels high");
      Check (Failure_With (RH.To_Holder (Affine (60.0, 60.0, 1100.0, 20.0,
                                                  Turn)))
               = Bad & "TrainRegion must span at most 1024 x 1024 pixels",
             "a rectangle more than 1024 pixels wide");
      declare
         R : Ks_Rectangle_Affine := Affine (60.0, 60.0, 44.0, 44.0, Turn);
      begin
         R.Set_Selected_Space_Name ("@\Nowhere");
         Check (Starts_With
                  (Failure_With (RH.To_Holder (R)),
                   "AMV.KS_IMAGE_BAD_SELECTED_SPACE_NAME_EXCEPTION"),
                "a rectangle in an unknown space");
      end;
      declare
         P : Ks_CNL_Search_Pattern := Turned_Pattern;
      begin
         P.Set_Train_Image (TI.Blank (120, 120, 77));
         Check (Train_Failure (P)
                  = Bad & "Pattern cannot be trained: every pixel of "
                    & "TrainRegion has the same grey level",
                "a flat rectangle");
         P := Turned_Pattern;
         P.Set_Origin_X (1.0E150);
         Check (Train_Failure (P)
                  = Bad & "Pattern.OriginX, OriginY lie more than 1.0E140 "
                    & "pixels from TrainRegion",
                "an origin too far away");
         P := Turned_Pattern;
         P.Set_Train_Image_Mask (TI.Blank (120, 120, 0));
         Check (Train_Failure (P)
                  = Bad & "TrainImageMask leaves fewer than 64 pixels of "
                    & "the pattern cared for",
                "a mask over the whole rectangle");
         P := Turned_Pattern;
         P.Set_Train_Image_Mask (TI.Blank (120, 120, 0));
         P.Set_Train_Image_Mask_Offset_X (200);
         Check (Train_Failure (P) = "" and then P.Trained,
                "a mask that covers nothing of the rectangle");
      end;
      declare
         P : Ks_CNL_Search_Pattern := Turned_Pattern;
      begin
         P.Set_Train_Region_Mode (Pixel_Aligned_Bounding_Box);
         Check (not P.Trained and then Train_Failure (P) = ""
                and then P.Trained_Pattern_Width > 44,
                "the same affine rectangle pixel aligned: its bounding box");
      end;
   end Test_Affine_Train_Failures;

   procedure Test_Affine_Search is
      Where    : constant Point := (100.4, 80.7);
      Image    : constant Ks_Image_8_Grey :=
        Turned_Scene (200, 160, Where, Turn);
      Expected : constant Point := Plus (Where, Turned (Spot.X, Spot.Y, Turn));
      Rect     : constant Ks_Rectangle_Affine :=
        Affine (101.0, 79.0, 90.0, 80.0, Turn);
      Tool     : Ks_CNL_Search_Tool;
   begin
      Section ("CNL search: SearchRegionMode AffineTransform");
      Tool.Pattern := Spot_Pattern;
      Tool.Input_Image := Image;
      Tool.Search_Region := RH.To_Holder (Rect);
      Tool.Run_Params.Search_Region_Mode := Affine_Transform;
      for Algorithm of Algorithm_List'(Linear_Search, Linear_CNLPAS) loop
         Tool.Run_Params.Algorithm := Algorithm;
         Tool.Run;
         Report (Tool, "affine search");
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Results.Count = 1
                and then Tool.Results.Item (0).Score > 0.95
                and then Distance (Tool.Results.Item (0), Expected) < 0.1,
                "a part turned with the rectangle, found at its point ("
                & Algorithm'Image & ")");
         if Tool.Results.Count = 1 then
            Ada.Text_IO.Put_Line
              ("  " & Algorithm'Image & ":"
               & Tool.Results.Item (0).Score'Image
               & Tool.Results.Item (0).Location_X'Image
               & Tool.Results.Item (0).Location_Y'Image);
         end if;
      end loop;
      --  The pixel aligned mode searches the rectangle's bounding box for
      --  the part upright.
      Tool.Run_Params.Algorithm := Linear_Search;
      Tool.Run_Params.Search_Region_Mode := Pixel_Aligned_Bounding_Box;
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then (Tool.Results.Count = 0
                       or else Tool.Results.Item (0).Score < 0.8),
             "the bounding box: the turned part does not match upright");

      --  A rectangle along the axes of a fixture turned with the part,
      --  and the location in that fixture.
      declare
         Pose     : constant Ks_Transform_2D_Linear :=
           Create_Similarity (2.0, Turn, 10.0, 20.0);
         Tree     : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
         Fixtured : Ks_Image_8_Grey := Image;
         U, V     : Real;
      begin
         Tree.Add_Space ("@", "Fixture", Pose);
         Fixtured.Set_Coordinate_Space_Tree (Tree);
         Fixtured.Set_Selected_Space_Name ("@\Fixture");
         Invert (Pose).Map_Point (101.0, 79.0, U, V);
         Tool.Input_Image := Fixtured;
         Tool.Search_Region := RH.To_Holder (Affine (U, V, 45.0, 40.0, 0.0));
         Tool.Run_Params.Search_Region_Mode := Affine_Transform;
         Tool.Run;
         Report (Tool, "fixture");
         Invert (Pose).Map_Point (Expected.X, Expected.Y, U, V);
         Check (Tool.Run_Status.Result = Accept_Result
                and then Tool.Results.Count = 1
                and then Distance (Tool.Results.Item (0), (U, V)) < 0.05,
                "a rectangle along a turned fixture's axes, the location in"
                & " the fixture");
      end;

      --  A rectangle smaller than the pattern: no results.
      Tool.Input_Image := Image;
      Tool.Search_Region := RH.To_Holder (Affine (101.0, 79.0, 40.0, 80.0,
                                                  Turn));
      Tool.Run;
      Check (Tool.Run_Status.Result = Accept_Result
             and then Tool.Results.Count = 0,
             "a rectangle narrower than the pattern: no results");

      --  Any other region is searched in its bounding box (VisionPro).
      declare
         Circle : Ks_Circle;
         Other  : Ks_CNL_Search_Tool := Tool;
      begin
         Circle.Set_Center_Radius (101.0, 79.0, 45.0);
         Tool.Search_Region := RH.To_Holder (Circle);
         Tool.Run;
         Other.Search_Region := RH.To_Holder (Circle);
         Other.Run_Params.Search_Region_Mode := Pixel_Aligned_Bounding_Box;
         Other.Run;
         Check (Same_Results (Tool, Other, 0.0),
                "a circle in the mode AffineTransform: its bounding box");
      end;

      --  Failures (the shape's own setters reject non-finite values; the
      --  kernel's checks of them are tested in Test_Affine_Kernel).
      Tool.Search_Region :=
        RH.To_Holder (Affine (101.0, 79.0, 9000.0, 8000.0, Turn));
      Tool.Run;
      Check (Failed_With (Tool, "Ks_Bad_Parameter_Exception",
                          "SearchRegion: the resampled rectangle must have "
                          & "at most 16777216 pixels"),
             "a rectangle too large");
      Check (Tool.Results.Count = 0, "no results after a failed run");
      declare
         R : Ks_Rectangle_Affine := Rect;
      begin
         R.Set_Selected_Space_Name ("@\Nowhere");
         Tool.Search_Region := RH.To_Holder (R);
         Tool.Run;
         Check (Failed_With (Tool,
                             "Ks_Image_Bad_Selected_Space_Name_Exception"),
                "a rectangle in an unknown space");
      end;
      Tool.Search_Region := RH.To_Holder (Rect);
      declare
         Untrained : Ks_CNL_Search_Pattern;
      begin
         Tool.Pattern := Untrained;
         Tool.Run;
         Check (Failed_With (Tool, "Ks_Operator_Not_Trained_Exception",
                             "Pattern is not trained"),
                "an untrained pattern");
      end;
   end Test_Affine_Search;

   procedure Test_Affine_Box is
      Instances : constant Point_List :=
        [(90.3, 75.6), (40.0, 60.0), (125.2, 95.4)];
      Image     : constant Ks_Image_8_Grey := Scene (180, 150, Instances);
      Pose      : constant Ks_Transform_2D_Linear :=
        Create_Similarity (0.7, 1.1, 5.0, -3.0);
      Tree      : AMV.Coordinate_Spaces.Ks_Coordinate_Space_Tree;
      Fixtured  : Ks_Image_8_Grey := Image;
      Box       : Ks_Rectangle;
      Rect      : Ks_Rectangle_Affine :=
        Affine (89.5, 74.5, 120.0, 110.0, 0.0);
      A, B      : Ks_CNL_Search_Tool;

      function Left_Hits (T : Ks_CNL_Search_Tool) return Natural is
         N : Natural := 0;
      begin
         for I in 0 .. T.Results.Count - 1 loop
            if T.Results.Item (I).Edge_Hit = Left then
               N := N + 1;
            end if;
         end loop;
         return N;
      end Left_Hits;
      --  The results whose window crosses the left side of the area.
   begin
      Section ("CNL search: SearchRegionMode AffineTransform against the "
               & "box");
      --  The pixels 30 .. 149 by 20 .. 129, as a box and as an affine
      --  rectangle (resampled exactly), both in pixel space.
      Box.Set_XY_Width_Height (29.5, 19.5, 120.0, 110.0);
      Box.Set_Selected_Space_Name ("#");
      Rect.Set_Selected_Space_Name ("#");
      Tree.Add_Space ("@", "Fixture", Pose);
      Fixtured.Set_Coordinate_Space_Tree (Tree);
      Fixtured.Set_Selected_Space_Name ("@\Fixture");
      A.Pattern := Trained_Pattern;
      A.Search_Region := RH.To_Holder (Box);
      A.Run_Params.Search_Region_Mode := Pixel_Aligned_Bounding_Box;
      A.Run_Params.Max_Results := 5;
      A.Run_Params.Accept_Threshold := 0.8;
      A.Run_Params.Confusion_Threshold := 0.9;
      B := A;
      B.Search_Region := RH.To_Holder (Rect);
      B.Run_Params.Search_Region_Mode := Affine_Transform;
      for In_Fixture in Boolean loop
         for L in 0 .. 1 loop
            for Algorithm of Algorithm_List'(Linear_Search, Linear_CNLPAS)
            loop
               if L = 0 or else Algorithm = Linear_Search then
                  A.Input_Image := (if In_Fixture then Fixtured else Image);
                  B.Input_Image := A.Input_Image;
                  A.Run_Params.Algorithm := Algorithm;
                  A.Run_Params.Partial_Match_Limit_Left := K.Int32 (15 * L);
                  B.Run_Params.Algorithm := A.Run_Params.Algorithm;
                  B.Run_Params.Partial_Match_Limit_Left :=
                    A.Run_Params.Partial_Match_Limit_Left;
                  A.Run;
                  B.Run;
                  Report (A, "box");
                  Report (B, "affine box");
                  Check (Same_Results (A, B, 1.0E-9)
                         and then A.Results.Count = 2 + L
                         and then Left_Hits (A) = L,
                         "the results of the box (fixture "
                         & In_Fixture'Image & ", PartialMatchLimitLeft"
                         & K.Int32'Image (K.Int32 (15 * L)) & ", "
                         & Algorithm'Image & "):"
                         & A.Results.Count'Image & B.Results.Count'Image);
               end if;
            end loop;
         end loop;
      end loop;
   end Test_Affine_Box;

   procedure Test_Affine_Streams is
      Where   : constant Point := (90.3, 75.6);
      Upright : constant Ks_Image_8_Grey := Scene (180, 150, [1 => Where]);
      Masked  : constant Ks_CNL_Search_Pattern :=
        Turned_Pattern (TI.Blank (60, 120, 0));
      type Pattern_List is array (Positive range <>)
        of Ks_CNL_Search_Pattern;
      A, B   : Ks_CNL_Search_Result;
      FA, FB : Boolean;
   begin
      Section ("CNL search: streams of AffineTransform patterns");
      for P of Pattern_List'(Turned_Pattern, Masked) loop
         declare
            S    : aliased SU.Stream_Type;
            Back : Ks_CNL_Search_Pattern;
         begin
            Ks_CNL_Search_Pattern'Write (S'Access, P);
            Ks_CNL_Search_Pattern'Read (S'Access, Back);
            Search (Back, Upright, Linear_Search, A, FA);
            Search (P, Upright, Linear_Search, B, FB);
            Check (Back.Trained
                   and then Back.Train_Region_Mode = Affine_Transform
                   and then Back.Trained_Pattern_Width = 44
                   and then Back.Train_Image_Mask.Allocated
                              = P.Train_Image_Mask.Allocated
                   and then FA and then FB and then Same (A, B),
                   "a stream keeps the mode and the trained pattern (mask "
                   & P.Train_Image_Mask.Allocated'Image & ")");
            --  The train region (an affine rectangle) comes back too.
            Back.Train;
            Search (Back, Upright, Linear_Search, A, FA);
            Check (FA and then Same (A, B), "... and trains again the same");
         end;
      end loop;
   end Test_Affine_Streams;

   procedure Test_Affine_Kernel is
      Train   : constant Ks_Image_8_Grey :=
        Turned_Scene (120, 120, (60.0, 60.0), Turn);
      Handle  : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Train);
      Where   : constant Point := (100.4, 80.7);
      Search_Image : constant Ks_Image_8_Grey :=
        Turned_Scene (200, 160, Where, Turn);
      Search_Handle : constant access constant KI.Ks_Image_8_Grey_Data :=
        AMV.Images.Kernel_Images.Kernel_Handle (Search_Image);
      Half    : constant Ks_Image_8_Grey := TI.Blank (60, 120, 0);
      Rect    : constant KSH.Ks_Rectangle_Affine :=
        (Center_X      => 60.0,
         Center_Y      => 60.0,
         Side_X_Length => 44.0,
         Side_Y_Length => 44.0,
         Rotation      => Turn,
         Skew          => 0.0);
      Search_Rect : constant KSH.Ks_Rectangle_Affine :=
        (Rect with delta Center_X => 101.0, Center_Y => 79.0,
                         Side_X_Length => 90.0, Side_Y_Length => 80.0);
      Id       : constant KT.Ks_Transform_2D_Linear := (others => <>);
      Singular : constant KT.Ks_Transform_2D_Linear :=
        (A => 1.0, B => 1.0, C => 1.0, D => 1.0, others => <>);
      NaN_PFR  : constant KT.Ks_Transform_2D_Linear :=
        (A => Zero / Zero, others => <>);
      Affine_Params : constant KC.Ks_CNL_Search_Train_Params :=
        (Train_Region_Mode => KC.Region_Mode_Affine_Transform,
         Origin_X          => 60.0,
         Origin_Y          => 60.0,
         Algorithms        => Linear_Search + Linear_CNLPAS,
         others            => <>);
      Run      : constant KC.Ks_CNL_Search_Run_Params :=
        (Search_Region_Mode => KC.Region_Mode_Affine_Transform,
         others             => <>);
      Pattern  : KC.Ks_CNL_Search_Pattern;
      Region   : KR.Ks_Pixel_Region;
      Results  : KC.Ks_CNL_Search_Results;
      Item     : KC.Ks_CNL_Search_Result;
      Broken   : aliased KI.Ks_Image_8_Grey_Data;
      Care     : KI.Ks_Image_8_Grey;
      Count    : K.Int32;
      W, H     : K.Int32;
      X, Y     : Real;
      S        : K.Ks_Status;

      function Failed (Code : K.Failure_Code; Message : String := "")
         return Boolean
      is (S.Failure = Code
          and then (Message = "" or else Text_Of (S) = Message));

      procedure Train_Expect
        (Region    : KSH.Ks_Rectangle_Affine;
         PFR, PFS  : KT.Ks_Transform_2D_Linear;
         Mask      : access constant KI.Ks_Image_8_Grey_Data;
         Code      : K.Failure_Code;
         Message   : String;
         Image     : access constant KI.Ks_Image_8_Grey_Data := Handle)
      is
         Flag : K.Int32;
      begin
         KM.Train_Affine (Pattern, Image, Region, PFR, PFS, Mask, 0, 0, S);
         Check (Failed (Code, Message),
                "train_affine: " & Message & " (" & Text_Of (S) & ")");
         KC.Pattern_Trained (Pattern, Flag, S);
         Check (Flag = 0, "... untrained after it");
      end Train_Expect;

      procedure Execute_Expect
        (Region   : KSH.Ks_Rectangle_Affine;
         PFR, SFP : KT.Ks_Transform_2D_Linear;
         Params   : KC.Ks_CNL_Search_Run_Params;
         Code     : K.Failure_Code;
         Message  : String;
         Image    : access constant KI.Ks_Image_8_Grey_Data :=
           Search_Handle) is
      begin
         KM.Execute_Affine (Image, Region, PFR, Pattern, Params, SFP,
                            Results, S);
         Check (Failed (Code, Message) and then Results = null,
                "execute_affine: " & Message & " (" & Text_Of (S) & ")");
      end Execute_Expect;

      Bad : constant K.Failure_Code := K.Failure_Bad_Parameter;
   begin
      Section ("CNL search kernel: the AffineTransform region mode");
      KM.Check_Affine_Train_Region (KSH.Shape_Rectangle_Affine, S);
      Check (K.Succeeded (S), "check_affine_train_region: an affine "
             & "rectangle");
      KM.Check_Affine_Train_Region (KSH.Shape_Rectangle, S);
      Check (Failed (Bad, "TrainRegion must be an affine rectangle for "
                     & "TrainRegionMode AffineTransform"),
             "check_affine_train_region: a rectangle");

      --  A null pattern, and one in another mode.
      KM.Train_Affine (Pattern, Handle, Rect, Id, Id, null, 0, 0, S);
      Check (Failed (Bad, "Pattern.TrainRegionMode must be AffineTransform "
                     & "(2) for ks_cnl_search_pattern_train_affine")
             and then Pattern = null,
             "train_affine: a null pattern has the default mode");
      KC.Pattern_Create (Pattern, S);
      Train_Expect (Rect, Id, Id, null, Bad,
                    "Pattern.TrainRegionMode must be AffineTransform (2) "
                    & "for ks_cnl_search_pattern_train_affine");
      KC.Pattern_Set_Train_Params (Pattern, Affine_Params, S);
      Check (K.Succeeded (S), "set_train_params: AffineTransform");
      KR.Whole_Image (120, 120, Region, S);
      KC.Pattern_Train (Pattern, Handle, Region, Id, S);
      Check (Failed (Bad, "Pattern.TrainRegionMode AffineTransform needs an "
                     & "affine rectangle TrainRegion "
                     & "(ks_cnl_search_pattern_train_affine)"),
             "train with a pixel region in the mode AffineTransform");
      KR.Destroy (Region, S);

      --  Failures, in order.
      Train_Expect (Rect, Id, Id, null, K.Failure_Image_No_Pixels,
                    "TrainImage has no pixels", null);
      Train_Expect (Rect, Id, Id, null, Bad, "TrainImage is not a valid "
                    & "image", Broken'Access);
      Train_Expect ((Rect with delta Center_X => Zero / Zero), Id, Id, null,
                    Bad, "TrainRegion.CenterX must be finite and within "
                    & "1.0E150");
      Train_Expect ((Rect with delta Side_Y_Length => -1.0), Id, Id, null,
                    Bad, "TrainRegion.SideYLength must be in 0 .. 4.0E150");
      Train_Expect ((Rect with delta Skew => 1.0 / Zero), Id, Id, null,
                    Bad, "TrainRegion.Skew must be finite and within "
                    & "1.0E150");
      Train_Expect (Rect, NaN_PFR, Id, null, Bad,
                    "the transform from TrainRegion's space to pixel space "
                    & "must be finite and within 1.0E150");
      Train_Expect (Rect, Id, NaN_PFR, null, Bad,
                    "Pixel_From_Selected must be finite and within 1.0E150");
      Train_Expect (Rect, Id, Id, Broken'Access, Bad,
                    "TrainImageMask is not a valid image handle");
      Train_Expect ((Rect with delta Side_X_Length => 7.4), Id, Id, null,
                    Bad, "TrainRegion must span at least 8 x 8 pixels");
      Train_Expect ((Rect with delta Rotation => 0.0), Singular, Id, null,
                    K.Failure_Transform_Singular, "");
      Train_Expect ((Rect with delta Center_X => 100.0), Id, Id, null, Bad,
                    "TrainRegion must lie entirely in TrainImage for "
                    & "TrainRegionMode AffineTransform");
      Train_Expect (Rect, Id, (Translation_X => 1.0E145, others => <>), null,
                    Bad, "Pattern.OriginX, OriginY lie more than 1.0E140 "
                    & "pixels from TrainRegion");

      --  The pattern, its origin and its care flags.
      KM.Train_Affine (Pattern, Handle, Rect, Id, Id, null, 0, 0, S);
      Check (K.Succeeded (S) and then Pattern.Care = null,
             "train_affine: no care flags without a mask");
      KC.Pattern_Trained_Size (Pattern, W, H, S);
      KC.Pattern_Trained_Origin (Pattern, X, Y, S);
      Check (W = 44 and then H = 44 and then abs (X - 21.5) < 1.0E-9
             and then abs (Y - 21.5) < 1.0E-9,
             "the rectangle's centre is the centre of the 44 x 44 pattern:"
             & X'Image & Y'Image);
      KM.Train_Affine (Pattern, Handle, Rect, Id, Id,
                       AMV.Images.Kernel_Images.Kernel_Handle (Half), 0, 0,
                       S);
      KC.Pattern_Get_Trained_Care_Image (Pattern, Care, S);
      declare
         Wrong, Cared, Ignored : Natural := 0;
      begin
         if K.Succeeded (S) and then Care /= null then
            for J in 0 .. 43 loop
               for I in 0 .. 43 loop
                  declare
                     --  The sample point of pattern pixel (I, J).
                     P : constant Point :=
                       Plus ((60.0, 60.0),
                             Turned (Real (I) + 0.5 - 22.0,
                                     Real (J) + 0.5 - 22.0, Turn));
                  begin
                     if Care.Pixels (J, I) = 0 then
                        Ignored := Ignored + 1;
                     else
                        Cared := Cared + 1;
                     end if;
                     --  Don't care exactly where the nearest train pixel
                     --  is left of column 60 (the mask's 60 columns).
                     if abs (P.X - 59.5) > 1.0E-6
                       and then (Care.Pixels (J, I) = 0) /= (P.X < 59.5)
                     then
                        Wrong := Wrong + 1;
                     end if;
                  end;
               end loop;
            end loop;
         end if;
         Check (K.Succeeded (S) and then Care /= null and then Wrong = 0
                and then Cared > 500 and then Ignored > 500,
                "the care flags: the mask's value at the train pixel nearest "
                & "to each sample (" & Cared'Image & Ignored'Image
                & Wrong'Image & ")");
      end;
      KI.Destroy (Care, S);

      --  Searching.
      Execute_Expect (Search_Rect, Id, Id, Run, K.Failure_Image_No_Pixels,
                      "InputImage has no pixels", null);
      KM.Execute_Affine (Search_Handle, Search_Rect, Id, null, Run, Id,
                         Results, S);
      Check (Failed (K.Failure_Operator_Not_Trained,
                     "Pattern is not trained")
             and then Results = null,
             "execute_affine: a null pattern");
      Execute_Expect (Search_Rect, Id, Id, (others => <>), Bad,
                      "RunParams.SearchRegionMode PixelAlignedBoundingBox "
                      & "needs a pixel region (ks_cnl_search_execute)");
      Execute_Expect (Search_Rect, Id, Id,
                      (Run with delta Accept_Threshold => 2.0), Bad,
                      "RunParams.AcceptThreshold must be in 0 .. 1");
      Execute_Expect ((Search_Rect with delta Center_Y => 1.0 / Zero), Id,
                      Id, Run, Bad, "SearchRegion.CenterY must be finite "
                      & "and within 1.0E150");
      Execute_Expect (Search_Rect, NaN_PFR, Id, Run, Bad,
                      "the transform from SearchRegion's space to pixel "
                      & "space must be finite and within 1.0E150");
      Execute_Expect (Search_Rect, Id, NaN_PFR, Run, Bad,
                      "Selected_From_Pixel must be finite and within "
                      & "1.0E150");
      Execute_Expect ((Search_Rect with delta Side_X_Length => 5000.0,
                                              Side_Y_Length => 5000.0),
                      Id, Id, Run, Bad, "SearchRegion: the resampled "
                      & "rectangle must have at most 16777216 pixels");
      Execute_Expect ((Search_Rect with delta Rotation => 0.0), Singular,
                      Id, Run, K.Failure_Transform_Singular, "");
      Execute_Expect (Search_Rect, Id, (A => 1.0E149, others => <>), Run,
                      Bad, "the transform from the resampled SearchRegion "
                      & "to the selected space exceeds 1.0E150");
      KM.Execute_Affine (Search_Handle,
                         (Search_Rect with delta Side_X_Length => 43.0),
                         Id, Pattern, Run, Id, Results, S);
      KC.Results_Count (Results, Count, S);
      Check (K.Succeeded (S) and then Results /= null and then Count = 0,
             "execute_affine: a rectangle narrower than the pattern");
      KC.Results_Destroy (Results);
      KM.Execute_Affine (Search_Handle, Search_Rect, Id, Pattern, Run, Id,
                         Results, S);
      KC.Results_Item (Results, 0, Item, S);
      Check (K.Succeeded (S) and then Item.Score > 0.95
             and then abs (Item.Location_X - Where.X) < 0.1
             and then abs (Item.Location_Y - Where.Y) < 0.1,
             "execute_affine: the part turned with the rectangle, at the "
             & "trained origin (its centre):" & Item.Location_X'Image
             & Item.Location_Y'Image);
      KC.Results_Destroy (Results);
      KC.Pattern_Destroy (Pattern, S);
   end Test_Affine_Kernel;

   procedure Run_All is
   begin
      Test_Defaults;
      Test_Pattern;
      Test_Pattern_Failures;
      Test_Exact;
      Test_Sub_Pixel;
      Test_Several;
      Test_Contrast;
      Test_Noise;
      Test_Region;
      Test_Failures;
      Test_Fixture;
      Test_Streams;
      Test_Kernel;
      Test_Limits;
      Test_Mask;
      Test_Mask_Failures;
      Test_Mask_Streams;
      Test_Mask_Kernel;
      Test_Train_Region_Mode;
      Test_Affine_Train;
      Test_Affine_Train_Failures;
      Test_Affine_Search;
      Test_Affine_Box;
      Test_Affine_Streams;
      Test_Affine_Kernel;
      Test_Partial_Reference;
      Test_Partial_Sides;
      Test_Partial_Defaults;
      Test_Partial_Failures;
      Test_Partial_Kernel;
      Test_Timing;
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_CNL_Search;
