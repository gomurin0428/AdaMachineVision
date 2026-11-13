pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

package body AMV.Kernels.Blob.Segmentation with SPARK_Mode is

   procedure Free is new Ada.Unchecked_Deallocation
     (U8_Matrix, U8_Matrix_Access);

   ---------------------------------------------------------------------
   --  Histogram
   ---------------------------------------------------------------------

   procedure Compute_Histogram
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Hist   : out Histogram)
   is
      B : constant Box := Box_Of (Region);
   begin
      Hist := [others => 0];
      for Y in B.Y_Min .. B.Y_Max loop
         for X in B.X_Min .. B.X_Max loop
            if KR.Contains (Region, Int32 (X), Int32 (Y)) then
               declare
                  V : constant Grey_8 := Image.Pixels (Y, X);
               begin
                  if Hist (V) < Max_Bin then
                     Hist (V) := Hist (V) + 1;
                  end if;
               end;
            end if;
         end loop;
      end loop;
   end Compute_Histogram;

   ---------------------------------------------------------------------
   --  Thresholds
   ---------------------------------------------------------------------

   function Level_At_Rank (Hist : Histogram; Rank : Int64) return Int32
   with Post => Level_At_Rank'Result in 0 .. 255;
   --  The grey value of the pixel of rank Rank (from 0) in increasing
   --  order of grey value: the smallest level whose cumulative count
   --  exceeds Rank (255 when none does).

   function Level_At_Rank (Hist : Histogram; Rank : Int64) return Int32 is
      Cumulative : Int64 := 0;
   begin
      for V in Grey_8 loop
         Cumulative := Cumulative + Hist (V);
         if Cumulative > Rank then
            return Int32 (V);
         end if;
         pragma Loop_Invariant
           (Cumulative in 0 .. (Int64 (V) + 1) * Max_Bin);
      end loop;
      return 255;
   end Level_At_Rank;

   function Percent_Of (Count : Int64; Percent : Int32) return Int64
   with
     Pre  => Count in 0 .. 256 * Max_Bin and then Percent in 0 .. 100,
     Post => Percent_Of'Result in 0 .. Count;
   --  floor (Count * Percent / 100).

   function Percent_Of (Count : Int64; Percent : Int32) return Int64 is
     (Count * Int64 (Percent) / 100);

   function Ceiling_Percent (Span, Percent : Int32) return Int32
   with
     Pre  => Span in 0 .. 255 and then Percent in 0 .. 100,
     Post => Ceiling_Percent'Result in 0 .. Span;
   --  ceiling (Span * Percent / 100).

   function Ceiling_Percent (Span, Percent : Int32) return Int32 is
     ((Span * Percent + 99) / 100);

   procedure Lemma_Ceiling_Monotone (Span, P1, P2 : Int32)
   with
     Ghost,
     Global => null,
     Pre  => Span in 0 .. 255 and then P1 in 0 .. 100
             and then P2 in P1 .. 100,
     Post => Ceiling_Percent (Span, P1) <= Ceiling_Percent (Span, P2);
   --  A larger percentage gives a level at least as high.

   procedure Lemma_Ceiling_Monotone (Span, P1, P2 : Int32) is
   begin
      pragma Assert (Span * P1 <= Span * P2);
      pragma Assert (Span * P1 + 99 <= Span * P2 + 99);
   end Lemma_Ceiling_Monotone;

   procedure Tail_Levels
     (Hist                : Histogram;
      Tail_Low, Tail_High : Int32;
      Low, High           : out Int32)
   with
     Pre  => Tail_Low in 0 .. 100 and then Tail_High in 0 .. 100,
     Post => Low in 0 .. 255 and then High in Low .. 255;
   --  The levels Low and High at the ends of the histogram once the
   --  darkest Tail_Low and the brightest Tail_High percent of its pixels
   --  are set aside (see AMV.Kernels.Blob); 0 and 0 for an empty
   --  histogram.

   procedure Tail_Levels
     (Hist                : Histogram;
      Tail_Low, Tail_High : Int32;
      Low, High           : out Int32)
   is
      Count   : constant Int64 := AMV.Kernels.Otsu.Total (Hist);
      Lo_Rank : Int64;
      Hi_Rank : Int64;
   begin
      if Count = 0 then
         Low := 0;
         High := 0;
         return;
      end if;
      Lo_Rank := Int64'Min (Percent_Of (Count, Tail_Low), Count - 1);
      Hi_Rank := Count - 1 - Percent_Of (Count, Tail_High);
      if Hi_Rank < Lo_Rank then
         Hi_Rank := Lo_Rank;
      end if;
      Low := Level_At_Rank (Hist, Lo_Rank);
      High := Level_At_Rank (Hist, Hi_Rank);
      if High < Low then
         High := Low;
      end if;
   end Tail_Levels;

   function Relative_Threshold
     (Hist                         : Histogram;
      Percent, Tail_Low, Tail_High : Int32) return Int32
   with
     Pre  => Percent in 0 .. 100 and then Tail_Low in 0 .. 100
             and then Tail_High in 0 .. 100,
     Post => Relative_Threshold'Result in 0 .. 510;
   --  Low + ceiling ((High - Low) * Percent / 100) with Low and High the
   --  tail levels of the histogram (Tail_Levels); 0 for an empty
   --  histogram.

   function Relative_Threshold
     (Hist                         : Histogram;
      Percent, Tail_Low, Tail_High : Int32) return Int32
   is
      Low  : Int32;
      High : Int32;
   begin
      Tail_Levels (Hist, Tail_Low, Tail_High, Low, High);
      return Low + Ceiling_Percent (High - Low, Percent);
   end Relative_Threshold;

   function Otsu_Threshold (Hist : Histogram; Polarity : Int32) return Int32
   with Post => Otsu_Threshold'Result in 0 .. 256;
   --  Otsu's threshold (AMV.Kernels.Otsu); 256 for light blobs and 0 for
   --  dark blobs when no T splits the pixels into two non-empty classes.

   function Otsu_Threshold (Hist : Histogram; Polarity : Int32) return Int32
   is
      T : constant Int32 := AMV.Kernels.Otsu.Threshold (Hist);
   begin
      if T = AMV.Kernels.Otsu.No_Split then
         return (if Polarity = Polarity_Light_Blobs then 256 else 0);
      end if;
      return T;
   end Otsu_Threshold;

   function Compute_Threshold
     (Params : Ks_Blob_Segmentation_Params;
      Hist   : Histogram) return Int32
   is
   begin
      case Params.Mode is
         when Segmentation_Hard_Fixed_Threshold =>
            return Params.Hard_Fixed_Threshold;
         when Segmentation_Hard_Relative_Threshold =>
            return Relative_Threshold
              (Hist, Params.Hard_Relative_Threshold, Params.Tail_Low,
               Params.Tail_High);
         when Segmentation_Hard_Dynamic_Threshold =>
            return Otsu_Threshold (Hist, Params.Polarity);
         when others =>
            return 1;
      end case;
   end Compute_Threshold;

   ---------------------------------------------------------------------
   --  Segmentation (Gold)
   ---------------------------------------------------------------------

   procedure Segment
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Region              : access constant KR.Ks_Pixel_Region_Data;
      Polarity, Threshold : Int32;
      S                   : in out U8_Matrix)
   is
   begin
      for Y in S'Range (1) loop
         for X in S'Range (2) loop
            S (Y, X) :=
              Expected_Segment (Image, Region, Polarity, Threshold, X, Y);
            pragma Loop_Invariant
              (for all XX in S'First (2) .. X =>
                 S (Y, XX)
                   = Expected_Segment
                       (Image, Region, Polarity, Threshold, XX, Y));
            pragma Loop_Invariant
              (for all YY in S'First (1) .. Y - 1 =>
                 (for all XX in S'Range (2) =>
                    S (YY, XX)
                      = Expected_Segment
                          (Image, Region, Polarity, Threshold, XX, YY)));
         end loop;
         pragma Loop_Invariant
           (for all YY in S'First (1) .. Y =>
              (for all XX in S'Range (2) =>
                 S (YY, XX)
                   = Expected_Segment
                       (Image, Region, Polarity, Threshold, XX, YY)));
      end loop;
   end Segment;

   ---------------------------------------------------------------------
   --  Morphology
   ---------------------------------------------------------------------

   procedure Morph_Step
     (S      : in out U8_Matrix;
      T      : out U8_Matrix;
      Dilate : Boolean;
      RX, RY : Int64)
   with
     Pre => T'First (1) = S'First (1) and then T'Last (1) = S'Last (1)
            and then T'First (2) = S'First (2)
            and then T'Last (2) = S'Last (2)
            and then RX in 0 .. 1 and then RY in 0 .. 1;
   --  One erosion (Dilate False) or dilation of the foreground of S with
   --  the (2 RX + 1) x (2 RY + 1) element, looking only at pixels that are
   --  not outside; T receives the previous S.

   procedure Morph_Step
     (S      : in out U8_Matrix;
      T      : out U8_Matrix;
      Dilate : Boolean;
      RX, RY : Int64)
   is
   begin
      T := S;
      for Y in S'Range (1) loop
         for X in S'Range (2) loop
            if T (Y, X) /= Seg_Outside then
               declare
                  Result : Boolean := not Dilate;
               begin
                  for DY in -RY .. RY loop
                     for DX in -RX .. RX loop
                        declare
                           NY : constant Int64 := Int64 (Y) + DY;
                           NX : constant Int64 := Int64 (X) + DX;
                        begin
                           if NY in Int64 (T'First (1)) .. Int64 (T'Last (1))
                             and then NX
                                        in Int64 (T'First (2))
                                         .. Int64 (T'Last (2))
                           then
                              declare
                                 C : constant Grey_8 :=
                                   T (Natural (NY), Natural (NX));
                              begin
                                 if C = Seg_Foreground and then Dilate then
                                    Result := True;
                                 elsif C = Seg_Background
                                   and then not Dilate
                                 then
                                    Result := False;
                                 end if;
                              end;
                           end if;
                        end;
                     end loop;
                  end loop;
                  S (Y, X) :=
                    (if Result then Seg_Foreground else Seg_Background);
               end;
            end if;
         end loop;
      end loop;
   end Morph_Step;

   procedure Apply_Morphology
     (Operations : Ks_Blob_Morphology_Collection;
      S          : in out U8_Matrix;
      Status     : out Ks_Status)
   is
      T    : U8_Matrix_Access;
      Last : constant Int32 :=
        Int32'Max (0, Int32'Min (Operations.Count,
                                 Max_Morphology_Operations)) - 1;
   begin
      if Last < 0 then
         Set_Success (Status);
         return;
      end if;
      Allocate_U8_Matrix
        ((X_Min => S'First (2), Y_Min => S'First (1),
          X_Max => S'Last (2), Y_Max => S'Last (1)), T);
      if T = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "RunParams.MorphologyOperations: out of memory");
         return;
      end if;
      for I in 0 .. Last loop
         declare
            Code   : constant Int32 := Operations.Items (Integer (I));
            Shape  : constant Int32 := Code mod 3;
            RX     : constant Int64 := (if Shape = 1 then 0 else 1);
            RY     : constant Int64 := (if Shape = 0 then 0 else 1);
         begin
            case Code is
               when Morphology_Erode_Horizontal .. Morphology_Erode_Square =>
                  Morph_Step (S, T.all, False, RX, RY);
               when Morphology_Dilate_Horizontal
                  .. Morphology_Dilate_Square =>
                  Morph_Step (S, T.all, True, RX, RY);
               when Morphology_Close_Horizontal .. Morphology_Close_Square =>
                  Morph_Step (S, T.all, True, RX, RY);
                  Morph_Step (S, T.all, False, RX, RY);
               when Morphology_Open_Horizontal .. Morphology_Open_Square =>
                  Morph_Step (S, T.all, False, RX, RY);
                  Morph_Step (S, T.all, True, RX, RY);
               when others =>
                  null;
            end case;
         end;
         pragma Loop_Invariant
           (T /= null
            and then T'First (1) = S'First (1) and then T'Last (1) = S'Last (1)
            and then T'First (2) = S'First (2)
            and then T'Last (2) = S'Last (2));
      end loop;
      Free (T);
      Set_Success (Status);
   end Apply_Morphology;

   ---------------------------------------------------------------------
   --  Soft segmentation
   ---------------------------------------------------------------------

   procedure Soft_Band
     (Params    : Ks_Blob_Segmentation_Params;
      Hist      : Histogram;
      Low, High : out Threshold_Level)
   is
   begin
      if Params.Mode = Segmentation_Soft_Fixed_Threshold then
         Low := Params.Soft_Fixed_Threshold_Low;
         High := Params.Soft_Fixed_Threshold_High;
         return;
      end if;
      declare
         Tail_Lo : Int32;
         Tail_Hi : Int32;
      begin
         Tail_Levels (Hist, Params.Tail_Low, Params.Tail_High, Tail_Lo,
                      Tail_Hi);
         Lemma_Ceiling_Monotone
           (Tail_Hi - Tail_Lo, Params.Soft_Relative_Threshold_Low,
            Params.Soft_Relative_Threshold_High);
         Low := Tail_Lo
           + Ceiling_Percent (Tail_Hi - Tail_Lo,
                              Params.Soft_Relative_Threshold_Low);
         High := Tail_Lo
           + Ceiling_Percent (Tail_Hi - Tail_Lo,
                              Params.Soft_Relative_Threshold_High);
      end;
   end Soft_Band;

   type Level_Table is array (Grey_8) of Grey_8;

   procedure Segment_Soft
     (Image     : access constant KI.Ks_Image_8_Grey_Data;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Polarity  : Int32;
      Low, High : Threshold_Level;
      Softness  : Softness_Value;
      S         : in out U8_Matrix;
      Levels    : in out U8_Matrix)
   is
      Table : constant Level_Table :=
        [for V in Grey_8 =>
           Grey_8 (Soft_Level (Polarity, Low, High, Softness, V))];
      --  The level of every grey value, so that a pixel costs one lookup.
   begin
      for Y in S'Range (1) loop
         for X in S'Range (2) loop
            if not KR.Contains (Region, Int32 (X), Int32 (Y))
              or else Image = null or else Image.Pixels = null
              or else Y not in Image.Pixels'Range (1)
              or else X not in Image.Pixels'Range (2)
            then
               S (Y, X) := Seg_Outside;
               Levels (Y, X) := 0;
            else
               declare
                  L : constant Grey_8 := Table (Image.Pixels (Y, X));
               begin
                  Levels (Y, X) := L;
                  S (Y, X) := (if L > 0 then Seg_Foreground
                               else Seg_Background);
               end;
            end if;
            pragma Loop_Invariant
              (for all XX in S'First (2) .. X =>
                 S (Y, XX)
                   = Expected_Soft_Segment
                       (Image, Region, Polarity, Low, High, Softness, XX, Y)
                 and then
                   Levels (Y, XX)
                     = Expected_Level
                         (Image, Region, Polarity, Low, High, Softness,
                          XX, Y));
            pragma Loop_Invariant
              (for all YY in S'First (1) .. Y - 1 =>
                 (for all XX in S'Range (2) =>
                    S (YY, XX)
                      = Expected_Soft_Segment
                          (Image, Region, Polarity, Low, High, Softness,
                           XX, YY)
                    and then
                      Levels (YY, XX)
                        = Expected_Level
                            (Image, Region, Polarity, Low, High, Softness,
                             XX, YY)));
         end loop;
         pragma Loop_Invariant
           (for all YY in S'First (1) .. Y =>
              (for all XX in S'Range (2) =>
                 S (YY, XX)
                   = Expected_Soft_Segment
                       (Image, Region, Polarity, Low, High, Softness,
                        XX, YY)
                 and then
                   Levels (YY, XX)
                     = Expected_Level
                         (Image, Region, Polarity, Low, High, Softness,
                          XX, YY)));
      end loop;
   end Segment_Soft;

   procedure Soft_Morph_Step
     (S      : in out U8_Matrix;
      Levels : in out U8_Matrix;
      T      : out U8_Matrix;
      Dilate : Boolean;
      RX, RY : Int64)
   with
     Pre => T'First (1) = S'First (1) and then T'Last (1) = S'Last (1)
            and then T'First (2) = S'First (2)
            and then T'Last (2) = S'Last (2)
            and then Levels'First (1) = S'First (1)
            and then Levels'Last (1) = S'Last (1)
            and then Levels'First (2) = S'First (2)
            and then Levels'Last (2) = S'Last (2)
            and then RX in 0 .. 1 and then RY in 0 .. 1;
   --  One grey erosion (Dilate False: the least level) or dilation (the
   --  greatest level) of the levels of the pixels of the region with the
   --  (2 RX + 1) x (2 RY + 1) element, looking only at pixels that are
   --  not outside; the classes follow the new levels. T receives the
   --  previous levels. (A pixel's class changes only between foreground
   --  and background, so S tells which pixels are outside throughout.)

   procedure Soft_Morph_Step
     (S      : in out U8_Matrix;
      Levels : in out U8_Matrix;
      T      : out U8_Matrix;
      Dilate : Boolean;
      RX, RY : Int64)
   is
   begin
      T := Levels;
      for Y in S'Range (1) loop
         for X in S'Range (2) loop
            if S (Y, X) /= Seg_Outside then
               declare
                  Result : Grey_8 := T (Y, X);
               begin
                  for DY in -RY .. RY loop
                     for DX in -RX .. RX loop
                        declare
                           NY : constant Int64 := Int64 (Y) + DY;
                           NX : constant Int64 := Int64 (X) + DX;
                        begin
                           if NY in Int64 (S'First (1)) .. Int64 (S'Last (1))
                             and then NX
                                        in Int64 (S'First (2))
                                         .. Int64 (S'Last (2))
                             and then S (Natural (NY), Natural (NX))
                                        /= Seg_Outside
                           then
                              declare
                                 C : constant Grey_8 :=
                                   T (Natural (NY), Natural (NX));
                              begin
                                 if Dilate then
                                    Result := Grey_8'Max (Result, C);
                                 else
                                    Result := Grey_8'Min (Result, C);
                                 end if;
                              end;
                           end if;
                        end;
                     end loop;
                  end loop;
                  Levels (Y, X) := Result;
                  S (Y, X) :=
                    (if Result > 0 then Seg_Foreground else Seg_Background);
               end;
            end if;
         end loop;
      end loop;
   end Soft_Morph_Step;

   procedure Apply_Soft_Morphology
     (Operations : Ks_Blob_Morphology_Collection;
      S          : in out U8_Matrix;
      Levels     : in out U8_Matrix;
      Status     : out Ks_Status)
   is
      T    : U8_Matrix_Access;
      Last : constant Int32 :=
        Int32'Max (0, Int32'Min (Operations.Count,
                                 Max_Morphology_Operations)) - 1;
   begin
      if Last < 0 then
         Set_Success (Status);
         return;
      end if;
      Allocate_U8_Matrix
        ((X_Min => S'First (2), Y_Min => S'First (1),
          X_Max => S'Last (2), Y_Max => S'Last (1)), T);
      if T = null then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "RunParams.MorphologyOperations: out of memory");
         return;
      end if;
      for I in 0 .. Last loop
         declare
            Code   : constant Int32 := Operations.Items (Integer (I));
            Shape  : constant Int32 := Code mod 3;
            RX     : constant Int64 := (if Shape = 1 then 0 else 1);
            RY     : constant Int64 := (if Shape = 0 then 0 else 1);
         begin
            case Code is
               when Morphology_Erode_Horizontal .. Morphology_Erode_Square =>
                  Soft_Morph_Step (S, Levels, T.all, False, RX, RY);
               when Morphology_Dilate_Horizontal
                  .. Morphology_Dilate_Square =>
                  Soft_Morph_Step (S, Levels, T.all, True, RX, RY);
               when Morphology_Close_Horizontal .. Morphology_Close_Square =>
                  Soft_Morph_Step (S, Levels, T.all, True, RX, RY);
                  Soft_Morph_Step (S, Levels, T.all, False, RX, RY);
               when Morphology_Open_Horizontal .. Morphology_Open_Square =>
                  Soft_Morph_Step (S, Levels, T.all, False, RX, RY);
                  Soft_Morph_Step (S, Levels, T.all, True, RX, RY);
               when others =>
                  null;
            end case;
         end;
         pragma Loop_Invariant
           (T /= null
            and then T'First (1) = S'First (1) and then T'Last (1) = S'Last (1)
            and then T'First (2) = S'First (2)
            and then T'Last (2) = S'Last (2));
      end loop;
      Free (T);
      Set_Success (Status);
   end Apply_Soft_Morphology;

   ---------------------------------------------------------------------
   --  Saved segmented images
   ---------------------------------------------------------------------

   procedure Segment_Box_Hard
     (Image               : access constant KI.Ks_Image_8_Grey_Data;
      Polarity, Threshold : Int32;
      M                   : in out U8_Matrix)
   is
   begin
      for Y in M'Range (1) loop
         for X in M'Range (2) loop
            M (Y, X) := Hard_Level (Polarity, Threshold, Image.Pixels (Y, X));
            pragma Loop_Invariant
              (for all XX in M'First (2) .. X =>
                 M (Y, XX)
                   = Hard_Level (Polarity, Threshold, Image.Pixels (Y, XX)));
            pragma Loop_Invariant
              (for all YY in M'First (1) .. Y - 1 =>
                 (for all XX in M'Range (2) =>
                    M (YY, XX)
                      = Hard_Level
                          (Polarity, Threshold, Image.Pixels (YY, XX))));
         end loop;
         pragma Loop_Invariant
           (for all YY in M'First (1) .. Y =>
              (for all XX in M'Range (2) =>
                 M (YY, XX)
                   = Hard_Level (Polarity, Threshold, Image.Pixels (YY, XX))));
      end loop;
   end Segment_Box_Hard;

   procedure Segment_Box_Soft
     (Image     : access constant KI.Ks_Image_8_Grey_Data;
      Polarity  : Int32;
      Low, High : Threshold_Level;
      Softness  : Softness_Value;
      M         : in out U8_Matrix)
   is
   begin
      for Y in M'Range (1) loop
         for X in M'Range (2) loop
            M (Y, X) :=
              Grey_8 (Soft_Level (Polarity, Low, High, Softness,
                                  Image.Pixels (Y, X)));
            pragma Loop_Invariant
              (for all XX in M'First (2) .. X =>
                 M (Y, XX)
                   = Grey_8 (Soft_Level (Polarity, Low, High, Softness,
                                         Image.Pixels (Y, XX))));
            pragma Loop_Invariant
              (for all YY in M'First (1) .. Y - 1 =>
                 (for all XX in M'Range (2) =>
                    M (YY, XX)
                      = Grey_8 (Soft_Level (Polarity, Low, High, Softness,
                                            Image.Pixels (YY, XX)))));
         end loop;
         pragma Loop_Invariant
           (for all YY in M'First (1) .. Y =>
              (for all XX in M'Range (2) =>
                 M (YY, XX)
                   = Grey_8 (Soft_Level (Polarity, Low, High, Softness,
                                         Image.Pixels (YY, XX)))));
      end loop;
   end Segment_Box_Soft;

   procedure To_Levels (S : U8_Matrix; M : in out U8_Matrix) is
   begin
      for Y in M'Range (1) loop
         for X in M'Range (2) loop
            M (Y, X) := (if S (Y, X) = Seg_Foreground then 1 else 0);
            pragma Loop_Invariant
              (for all XX in M'First (2) .. X =>
                 M (Y, XX) = (if S (Y, XX) = Seg_Foreground then 1 else 0));
            pragma Loop_Invariant
              (for all YY in M'First (1) .. Y - 1 =>
                 (for all XX in M'Range (2) =>
                    M (YY, XX)
                      = (if S (YY, XX) = Seg_Foreground then 1 else 0)));
         end loop;
         pragma Loop_Invariant
           (for all YY in M'First (1) .. Y =>
              (for all XX in M'Range (2) =>
                 M (YY, XX)
                   = (if S (YY, XX) = Seg_Foreground then 1 else 0)));
      end loop;
   end To_Levels;

end AMV.Kernels.Blob.Segmentation;
