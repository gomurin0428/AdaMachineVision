pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

package body AMV.Kernels.IP_One_Image.Morphology with SPARK_Mode is

   subtype Grey_8 is KI.Grey_8;

   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Grey_8_Matrix, KI.Grey_8_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KI.Ks_Image_8_Grey_Data, KI.Ks_Image_8_Grey);

   procedure Release (Image : in out KI.Ks_Image_8_Grey)
   with Post => Image = null;
   --  Frees Image (if any).

   procedure Release (Image : in out KI.Ks_Image_8_Grey) is
   begin
      if Image /= null then
         Free (Image.Pixels);
      end if;
      Free (Image);
   end Release;

   type Extreme is (Minimum, Maximum);

   function Combine (E : Extreme; A, B : Grey_8) return Grey_8 is
     (if E = Minimum then Grey_8'Min (A, B) else Grey_8'Max (A, B));
   --  The extreme of two values.

   function Bounded_By (E : Extreme; V, Bound : Grey_8) return Boolean is
     (if E = Minimum then V <= Bound else V >= Bound);
   --  V does not pass Bound in the direction of E.

   function Line_Of (Line : access constant KI.Ks_Image_8_Grey_Data;
                     Length : Int64) return Boolean
   is
     (KI.Valid_Image (Line)
      and then Int64 (Line.Width) = Length and then Line.Height = 1);
   --  A work line of Length values (a one-row image).

   procedure New_Lines
     (Length : Int64;
      G, H   : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Length >= 1,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Line_Of (G, Length) and then Line_Of (H, Length)
                       else G = null and then H = null);
   --  The two work lines of the running extrema.

   procedure New_Lines
     (Length : Int64;
      G, H   : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      G := null;
      H := null;
      if Length > KI.Max_Pixels then
         Set_Failure (Status, Failure_Out_Of_Memory,
                      "IPOneImage: a line of the image is too long for the"
                      & " kernel");
         return;
      end if;
      Common.New_Image (Int32 (Length), 1, G, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Common.New_Image (Int32 (Length), 1, H, Status);
      if not Succeeded (Status) then
         Release (G);
      end if;
   end New_Lines;

   ---------------------------------------------------------------------
   --  One direction
   ---------------------------------------------------------------------

   procedure Rows_Pass
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Size   : Int32;
      E      : Extreme;
      Target : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Odd_Size (Size, Max_Kernel_Size),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Common.Same_Size (Target, Source)
                       else Target = null);
   --  Target (Y, X): the extreme of Source over X - R .. X + R in row Y
   --  (R = (Size - 1) / 2, reflected at the ends).

   procedure Rows_Pass
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Size   : Int32;
      E      : Extreme;
      Target : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      W : constant Int64 := Int64 (Source.Width);
      K : constant Int64 := Int64 (Size);
      R : constant Int64 := (K - 1) / 2;
      L : constant Int64 := W + K - 1;
      G, H : KI.Ks_Image_8_Grey;
   begin
      Target := null;
      New_Lines (L, G, H, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Common.New_Image (Source.Width, Source.Height, Target, Status);
      if not Succeeded (Status) then
         Free (G.Pixels);
         Free (G);
         Free (H.Pixels);
         Free (H);
         return;
      end if;
      for Y in Source.Pixels'Range (1) loop
         --  G: the extreme from the start of each block of K values.
         declare
            Phase : Int64 := 0;
         begin
            for J in 0 .. Natural (L - 1) loop
               declare
                  P : constant Grey_8 :=
                    Source.Pixels (Y, Common.Fold (Int64 (J) - R, W));
               begin
                  if Phase = 0 or else J = 0 then
                     G.Pixels (0, J) := P;
                  else
                     G.Pixels (0, J) := Combine (E, G.Pixels (0, J - 1), P);
                  end if;
               end;
               Phase := (if Phase = K - 1 then 0 else Phase + 1);
               pragma Loop_Invariant (Phase in 0 .. K - 1);
               pragma Loop_Invariant (Line_Of (G, L));
            end loop;
         end;
         --  H: the extreme up to the end of each block.
         declare
            Phase : Int64 := (L - 1) mod K;
         begin
            for J in reverse 0 .. Natural (L - 1) loop
               declare
                  P : constant Grey_8 :=
                    Source.Pixels (Y, Common.Fold (Int64 (J) - R, W));
               begin
                  if Phase = K - 1 or else Int64 (J) = L - 1 then
                     H.Pixels (0, J) := P;
                  else
                     H.Pixels (0, J) := Combine (E, H.Pixels (0, J + 1), P);
                  end if;
               end;
               Phase := (if Phase = 0 then K - 1 else Phase - 1);
               pragma Loop_Invariant (Phase in 0 .. K - 1);
               pragma Loop_Invariant (Line_Of (H, L));
            end loop;
         end;
         --  The window X - R .. X + R is the line's X .. X + K - 1.
         for X in Target.Pixels'Range (2) loop
            Target.Pixels (Y, X) :=
              Combine (E, H.Pixels (0, X), G.Pixels (0, X + Natural (K) - 1));
            pragma Loop_Invariant (Common.Same_Size (Target, Source));
         end loop;
         pragma Loop_Invariant (Common.Same_Size (Target, Source));
         pragma Loop_Invariant (Line_Of (G, L) and then Line_Of (H, L));
      end loop;
      Free (G.Pixels);
      Free (G);
      Free (H.Pixels);
      Free (H);
   end Rows_Pass;

   procedure Columns_Pass
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Size   : Int32;
      E      : Extreme;
      Bound  : access constant KI.Ks_Image_8_Grey_Data;
      Target : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source) and then Common.Same_Size (Bound, Source)
             and then Odd_Size (Size, Max_Kernel_Size),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Target, Source)
                     and then
                       (for all Y in Target.Pixels'Range (1) =>
                          (for all X in Target.Pixels'Range (2) =>
                             Bounded_By (E, Target.Pixels (Y, X),
                                         Bound.Pixels (Y, X))))
                else Target = null);
   --  Target (Y, X): the extreme of Source over Y - R .. Y + R in column
   --  X, and of Bound (Y, X), a limit that never acts when the window's
   --  extreme is Bound's (the window contains the pixel itself).

   procedure Columns_Pass
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Size   : Int32;
      E      : Extreme;
      Bound  : access constant KI.Ks_Image_8_Grey_Data;
      Target : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Hgt : constant Int64 := Int64 (Source.Height);
      K   : constant Int64 := Int64 (Size);
      R   : constant Int64 := (K - 1) / 2;
      L   : constant Int64 := Hgt + K - 1;
      G, H : KI.Ks_Image_8_Grey;
   begin
      Target := null;
      New_Lines (L, G, H, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Common.New_Image (Source.Width, Source.Height, Target, Status);
      if not Succeeded (Status) then
         Free (G.Pixels);
         Free (G);
         Free (H.Pixels);
         Free (H);
         return;
      end if;
      for X in Source.Pixels'Range (2) loop
         declare
            Phase : Int64 := 0;
         begin
            for J in 0 .. Natural (L - 1) loop
               declare
                  P : constant Grey_8 :=
                    Source.Pixels (Common.Fold (Int64 (J) - R, Hgt), X);
               begin
                  if Phase = 0 or else J = 0 then
                     G.Pixels (0, J) := P;
                  else
                     G.Pixels (0, J) := Combine (E, G.Pixels (0, J - 1), P);
                  end if;
               end;
               Phase := (if Phase = K - 1 then 0 else Phase + 1);
               pragma Loop_Invariant (Phase in 0 .. K - 1);
               pragma Loop_Invariant (Line_Of (G, L));
            end loop;
         end;
         declare
            Phase : Int64 := (L - 1) mod K;
         begin
            for J in reverse 0 .. Natural (L - 1) loop
               declare
                  P : constant Grey_8 :=
                    Source.Pixels (Common.Fold (Int64 (J) - R, Hgt), X);
               begin
                  if Phase = K - 1 or else Int64 (J) = L - 1 then
                     H.Pixels (0, J) := P;
                  else
                     H.Pixels (0, J) := Combine (E, H.Pixels (0, J + 1), P);
                  end if;
               end;
               Phase := (if Phase = 0 then K - 1 else Phase - 1);
               pragma Loop_Invariant (Phase in 0 .. K - 1);
               pragma Loop_Invariant (Line_Of (H, L));
            end loop;
         end;
         for Y in Target.Pixels'Range (1) loop
            Target.Pixels (Y, X) :=
              Combine (E,
                       Combine (E, H.Pixels (0, Y),
                                G.Pixels (0, Y + Natural (K) - 1)),
                       Bound.Pixels (Y, X));
            pragma Loop_Invariant (Common.Same_Size (Target, Source));
            pragma Loop_Invariant
              (for all J in Target.Pixels'Range (1) =>
                 (for all I in 0 .. X - 1 =>
                    Bounded_By (E, Target.Pixels (J, I),
                                Bound.Pixels (J, I))));
            pragma Loop_Invariant
              (for all J in 0 .. Y =>
                 Bounded_By (E, Target.Pixels (J, X), Bound.Pixels (J, X)));
         end loop;
         pragma Loop_Invariant (Common.Same_Size (Target, Source));
         pragma Loop_Invariant (Line_Of (G, L) and then Line_Of (H, L));
         pragma Loop_Invariant
           (for all J in Target.Pixels'Range (1) =>
              (for all I in 0 .. X =>
                 Bounded_By (E, Target.Pixels (J, I), Bound.Pixels (J, I))));
      end loop;
      Free (G.Pixels);
      Free (G);
      Free (H.Pixels);
      Free (H);
   end Columns_Pass;

   procedure Extreme_Filter
     (Source        : access constant KI.Ks_Image_8_Grey_Data;
      Width, Height : Int32;
      E             : Extreme;
      Result        : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Odd_Size (Width, Max_Kernel_Size)
             and then Odd_Size (Height, Max_Kernel_Size),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Result, Source)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Bounded_By (E, Result.Pixels (Y, X),
                                         Source.Pixels (Y, X))))
                else Result = null);
   --  The extreme over the rectangle: rows, then columns.

   procedure Extreme_Filter
     (Source        : access constant KI.Ks_Image_8_Grey_Data;
      Width, Height : Int32;
      E             : Extreme;
      Result        : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status)
   is
      Rows : KI.Ks_Image_8_Grey;
   begin
      Result := null;
      Rows_Pass (Source, Width, E, Rows, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Columns_Pass (Rows, Height, E, Source, Result, Status);
      Free (Rows.Pixels);
      Free (Rows);
   end Extreme_Filter;

   procedure Erode
     (Source        : access constant KI.Ks_Image_8_Grey_Data;
      Width, Height : Int32;
      Result        : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status) is
   begin
      Extreme_Filter (Source, Width, Height, Minimum, Result, Status);
   end Erode;

   procedure Dilate
     (Source        : access constant KI.Ks_Image_8_Grey_Data;
      Width, Height : Int32;
      Result        : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status) is
   begin
      Extreme_Filter (Source, Width, Height, Maximum, Result, Status);
   end Dilate;

   ---------------------------------------------------------------------
   --  The operator
   ---------------------------------------------------------------------

   procedure Difference
     (A, B   : access constant KI.Ks_Image_8_Grey_Data;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (A) and then Common.Same_Size (B, A),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Common.Same_Size (Result, A)
                       else Result = null);
   --  A - B, limited to >= 0.

   procedure Difference
     (A, B   : access constant KI.Ks_Image_8_Grey_Data;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status) is
   begin
      Common.New_Image (A.Width, A.Height, Result, Status);
      if not Succeeded (Status) then
         return;
      end if;
      for Y in Result.Pixels'Range (1) loop
         for X in Result.Pixels'Range (2) loop
            Result.Pixels (Y, X) :=
              (if A.Pixels (Y, X) >= B.Pixels (Y, X)
               then A.Pixels (Y, X) - B.Pixels (Y, X) else 0);
            pragma Loop_Invariant (Common.Same_Size (Result, A));
         end loop;
         pragma Loop_Invariant (Common.Same_Size (Result, A));
      end loop;
   end Difference;

   procedure Opening_Or_Closing
     (Source        : access constant KI.Ks_Image_8_Grey_Data;
      Width, Height : Int32;
      Opening       : Boolean;
      Result        : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Odd_Size (Width, Max_Kernel_Size)
             and then Odd_Size (Height, Max_Kernel_Size),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Common.Usable (Result)
                            and then Common.Same_Size (Result, Source)
                       else Result = null);
   --  Dilate (Erode (Source)) for Opening, Erode (Dilate (Source))
   --  otherwise.

   procedure Opening_Or_Closing
     (Source        : access constant KI.Ks_Image_8_Grey_Data;
      Width, Height : Int32;
      Opening       : Boolean;
      Result        : out KI.Ks_Image_8_Grey;
      Status        : out Ks_Status)
   is
      First : KI.Ks_Image_8_Grey;
   begin
      Result := null;
      if Opening then
         Erode (Source, Width, Height, First, Status);
      else
         Dilate (Source, Width, Height, First, Status);
      end if;
      if not Succeeded (Status) then
         return;
      end if;
      if Opening then
         Dilate (First, Width, Height, Result, Status);
      else
         Erode (First, Width, Height, Result, Status);
      end if;
      Free (First.Pixels);
      Free (First);
   end Opening_Or_Closing;

   procedure Full_Result
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Params : Ks_IP_One_Image_Grey_Morphology_NxM;
      Full   : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source)
             and then Params.Operation in Morphology_Code
             and then Odd_Size (Params.Kernel_Width, Max_Kernel_Size)
             and then Odd_Size (Params.Kernel_Height, Max_Kernel_Size),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Common.Same_Size (Full, Source)
                     and then
                       (if Params.Operation = Morphology_Erode
                        then (for all Y in Full.Pixels'Range (1) =>
                                (for all X in Full.Pixels'Range (2) =>
                                   Full.Pixels (Y, X)
                                     <= Source.Pixels (Y, X))))
                     and then
                       (if Params.Operation = Morphology_Dilate
                        then (for all Y in Full.Pixels'Range (1) =>
                                (for all X in Full.Pixels'Range (2) =>
                                   Full.Pixels (Y, X)
                                     >= Source.Pixels (Y, X))))
                else Full = null);
   --  The operation over the whole image.

   procedure Full_Result
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Params : Ks_IP_One_Image_Grey_Morphology_NxM;
      Full   : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      W : constant Int32 := Params.Kernel_Width;
      H : constant Int32 := Params.Kernel_Height;
      A, B : KI.Ks_Image_8_Grey;
   begin
      Full := null;
      case Params.Operation is
         when Morphology_Erode =>
            Erode (Source, W, H, Full, Status);
         when Morphology_Dilate =>
            Dilate (Source, W, H, Full, Status);
         when Morphology_Open =>
            Opening_Or_Closing (Source, W, H, True, Full, Status);
         when Morphology_Close =>
            Opening_Or_Closing (Source, W, H, False, Full, Status);
         when Morphology_Dilate_Minus_Erode =>
            Dilate (Source, W, H, A, Status);
            if not Succeeded (Status) then
               return;
            end if;
            Erode (Source, W, H, B, Status);
            if not Succeeded (Status) then
               Free (A.Pixels);
               Free (A);
               return;
            end if;
            Difference (A, B, Full, Status);
            Free (A.Pixels);
            Free (A);
            Free (B.Pixels);
            Free (B);
         when Morphology_Close_Minus_Original =>
            Opening_Or_Closing (Source, W, H, False, A, Status);
            if not Succeeded (Status) then
               return;
            end if;
            Difference (A, Source, Full, Status);
            Free (A.Pixels);
            Free (A);
         when Morphology_Original_Minus_Open =>
            Opening_Or_Closing (Source, W, H, True, A, Status);
            if not Succeeded (Status) then
               return;
            end if;
            Difference (Source, A, Full, Status);
            Free (A.Pixels);
            Free (A);
         when others =>
            --  Excluded by the precondition.
            Set_Failure (Status, Failure_Out_Of_Memory,
                         "IPOneImage: unknown morphology operation");
      end case;
   end Full_Result;

   procedure Grey_Morphology
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Whole  : Boolean;
      Params : Ks_IP_One_Image_Grey_Morphology_NxM;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   is
      Full : KI.Ks_Image_8_Grey;
   begin
      Result := null;
      Full_Result (Source, Params, Full, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Common.Select_Pixels (Source, Full, Region, Whole, Result, Status);
      if Succeeded (Status) then
         pragma Assert
           (if Params.Operation = Morphology_Erode
            then (for all Y in Result.Pixels'Range (1) =>
                    (for all X in Result.Pixels'Range (2) =>
                       Result.Pixels (Y, X) <= Source.Pixels (Y, X))));
         pragma Assert
           (if Params.Operation = Morphology_Dilate
            then (for all Y in Result.Pixels'Range (1) =>
                    (for all X in Result.Pixels'Range (2) =>
                       Result.Pixels (Y, X) >= Source.Pixels (Y, X))));
      end if;
      Free (Full.Pixels);
      Free (Full);
   end Grey_Morphology;

end AMV.Kernels.IP_One_Image.Morphology;
