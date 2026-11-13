pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.Numerics;

package body AMV.Kernels.Regions with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  Loop invariants refer to values on loop entry after a condition;
   --  contracts are proved, never executed.

   package N renames AMV.Kernels.Numerics;

   use type Interfaces.Unsigned_32;

   subtype U32 is Interfaces.Unsigned_32;

   procedure Free is new Ada.Unchecked_Deallocation
     (Flag_Matrix, Flag_Matrix_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Pixel_Region_Data, Ks_Pixel_Region);
   procedure Free is new Ada.Unchecked_Deallocation
     (Bool_Array, Bool_Array_Access);
   procedure Free is new Ada.Unchecked_Deallocation
     (Ks_Region_Reader_Data, Ks_Region_Reader);

   Initial_Capacity : constant := 65_536;
   --  The number of elements first allocated while reading a stream; the
   --  buffer then doubles as elements arrive, up to the number expected.

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Region (Region : out Ks_Pixel_Region)
   with
     Global => null,
     Post   => (if Region /= null
                then Region.X_Min = 0 and then Region.Y_Min = 0
                     and then Region.Width = 0 and then Region.Height = 0
                     and then Region.Count = 0
                     and then Region.Flags = null);
   --  A new handle with the record's default values, or null when the
   --  memory cannot be allocated. Trusted: the allocator raises
   --  Storage_Error, which SPARK cannot express.

   procedure Allocate_Region (Region : out Ks_Pixel_Region)
     with SPARK_Mode => Off
   is
   begin
      Region := new Ks_Pixel_Region_Data;
   exception
      when Storage_Error =>
         Region := null;
   end Allocate_Region;

   procedure Allocate_Flags
     (Y_First, Y_Last, X_First, X_Last : Natural;
      Flags                            : out Flag_Matrix_Access)
   with
     Global => null,
     Pre    => Y_First <= Y_Last and then X_First <= X_Last,
     Post   => (if Flags /= null
                then Flags'First (1) = Y_First
                     and then Flags'Last (1) = Y_Last
                     and then Flags'First (2) = X_First
                     and then Flags'Last (2) = X_Last);
   --  A new flag matrix with these bounds (every flag False, the default
   --  component value), or null when the memory cannot be allocated.
   --  Trusted as above.

   procedure Allocate_Flags
     (Y_First, Y_Last, X_First, X_Last : Natural;
      Flags                            : out Flag_Matrix_Access)
     with SPARK_Mode => Off
   is
   begin
      Flags := new Flag_Matrix (Y_First .. Y_Last, X_First .. X_Last);
   exception
      when Storage_Error =>
         Flags := null;
   end Allocate_Flags;

   procedure Allocate_Reader (Reader : out Ks_Region_Reader)
   with
     Global => null,
     Post   => (if Reader /= null
                then Reader.X_Min = 0 and then Reader.Y_Min = 0
                     and then Reader.Width = 0 and then Reader.Height = 0
                     and then Reader.Count = 0 and then Reader.Total = 0
                     and then Reader.Filled = 0
                     and then Reader.Buffer = null);
   --  A new reader with the record's default values, or null. Trusted as
   --  above.

   procedure Allocate_Reader (Reader : out Ks_Region_Reader)
     with SPARK_Mode => Off
   is
   begin
      Reader := new Ks_Region_Reader_Data;
   exception
      when Storage_Error =>
         Reader := null;
   end Allocate_Reader;

   procedure Allocate_Buffer
     (Capacity : Positive;
      Buffer   : out Bool_Array_Access)
   with
     Global => null,
     Post   => (if Buffer /= null
                then Buffer'First = 0 and then Buffer'Last = Capacity - 1);
   --  A new buffer of Capacity elements (all False), or null. Trusted as
   --  above.

   procedure Allocate_Buffer
     (Capacity : Positive;
      Buffer   : out Bool_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Buffer := new Bool_Array (0 .. Capacity - 1);
   exception
      when Storage_Error =>
         Buffer := null;
   end Allocate_Buffer;

   ---------------------------------------------------------------------
   --  Proof helpers
   ---------------------------------------------------------------------

   procedure Lemma_Mul_Le (A, B, K : Int64)
   with
     Ghost,
     Global => null,
     Pre    => 0 <= A and then A <= B and then 0 <= K,
     Post   => Big (A) * Big (K) <= Big (B) * Big (K);
   --  Multiplication by a non-negative number keeps the order.

   procedure Lemma_Mul_Le (A, B, K : Int64) is null;

   procedure Lemma_Box_Size (W1, H1, W2, H2 : Int64)
   with
     Ghost,
     Global => null,
     Pre    => 1 <= W1 and then W1 <= W2 and then 1 <= H1
               and then H1 <= H2 and then W2 <= 2**31 and then H2 <= 2**31
               and then W2 * H2 <= Max_Pixels,
     Post   => W1 * H1 <= W2 * H2;
   --  A smaller box has fewer pixels.

   procedure Lemma_Box_Size (W1, H1, W2, H2 : Int64) is
   begin
      Lemma_Mul_Le (W1, W2, H1);
      Lemma_Mul_Le (H1, H2, W2);
   end Lemma_Box_Size;

   procedure Lemma_Row_Full (F : Flag_Matrix; Y : Natural; X : Int64)
   with
     Ghost,
     Global => null,
     Pre    => Y in F'Range (1)
               and then X >= Int64 (F'First (2))
               and then X <= Int64 (F'Last (2)) + 1
               and then Row_Count (F, Y, X) = X - Int64 (F'First (2)),
     Post   => (for all I in F'Range (2) =>
                  (if Int64 (I) < X then F (Y, I))),
     Subprogram_Variant => (Decreases => X);
   --  A row whose count left of X is X - F'First (2) is all True there.

   procedure Lemma_Row_Full (F : Flag_Matrix; Y : Natural; X : Int64) is
   begin
      if X > Int64 (F'First (2)) then
         Lemma_Row_Full (F, Y, X - 1);
      end if;
   end Lemma_Row_Full;

   procedure Lemma_Rows_Full (F : Flag_Matrix; Y : Int64)
   with
     Ghost,
     Global => null,
     Pre    => F'First (2) <= F'Last (2)
               and then Y >= Int64 (F'First (1))
               and then Y <= Int64 (F'Last (1)) + 1
               and then Big (Rows_Count (F, Y))
                          = Big (Y - Int64 (F'First (1)))
                            * Big (Length_2 (F)),
     Post   => (for all J in F'Range (1) =>
                  (if Int64 (J) < Y
                   then (for all I in F'Range (2) => F (J, I)))),
     Subprogram_Variant => (Decreases => Y);
   --  Rows above Y holding as many True flags as they have flags are all
   --  True.

   procedure Lemma_Rows_Full (F : Flag_Matrix; Y : Int64) is
   begin
      if Y > Int64 (F'First (1)) then
         pragma Assert
           (Big (Rows_Count (F, Y - 1))
              = Big (Y - 1 - Int64 (F'First (1))) * Big (Length_2 (F)));
         Lemma_Rows_Full (F, Y - 1);
         Lemma_Row_Full (F, Natural (Y - 1), Int64 (F'Last (2)) + 1);
      end if;
   end Lemma_Rows_Full;

   procedure Lemma_Row_Positive
     (F : Flag_Matrix; Y : Natural; X : Int64; X0 : Natural)
   with
     Ghost,
     Global => null,
     Pre    => Y in F'Range (1)
               and then X >= Int64 (F'First (2))
               and then X <= Int64 (F'Last (2)) + 1
               and then X0 in F'Range (2) and then Int64 (X0) < X
               and then F (Y, X0),
     Post   => Row_Count (F, Y, X) >= 1,
     Subprogram_Variant => (Decreases => X);
   --  A True flag left of X is counted.

   procedure Lemma_Row_Positive
     (F : Flag_Matrix; Y : Natural; X : Int64; X0 : Natural) is
   begin
      if Int64 (X0) < X - 1 then
         Lemma_Row_Positive (F, Y, X - 1, X0);
      end if;
   end Lemma_Row_Positive;

   procedure Lemma_Rows_Positive
     (F : Flag_Matrix; Y : Int64; Y0, X0 : Natural)
   with
     Ghost,
     Global => null,
     Pre    => F'First (2) <= F'Last (2)
               and then Y >= Int64 (F'First (1))
               and then Y <= Int64 (F'Last (1)) + 1
               and then Y0 in F'Range (1) and then Int64 (Y0) < Y
               and then X0 in F'Range (2)
               and then F (Y0, X0),
     Post   => Rows_Count (F, Y) >= 1,
     Subprogram_Variant => (Decreases => Y);
   --  A True flag above row Y is counted.

   procedure Lemma_Rows_Positive
     (F : Flag_Matrix; Y : Int64; Y0, X0 : Natural) is
   begin
      if Int64 (Y0) < Y - 1 then
         Lemma_Rows_Positive (F, Y - 1, Y0, X0);
      else
         Lemma_Row_Positive (F, Y0, Int64 (F'Last (2)) + 1, X0);
      end if;
   end Lemma_Rows_Positive;

   ---------------------------------------------------------------------
   --  Messages and failures
   ---------------------------------------------------------------------

   subtype Name_Text is String
     with Dynamic_Predicate =>
       Name_Text'First = 1 and then Name_Text'Length <= 80;
   --  An operation name or a reason that a message is built from.

   function Image_Of (Value : Int64) return String
   with Pre  => Value > Int64'First,
        Post => Image_Of'Result'First = 1
                and then Image_Of'Result'Length in 1 .. 20;
   --  The decimal digits of Value, with a leading '-' when it is negative.

   function Image_Of (Value : Int64) return String is
      Text  : String (1 .. 20) := [others => '0'];
      Rest  : Int64 := abs Value;
      First : Positive;
   begin
      --  At most 19 digits; the first character is left for the sign.
      for K in reverse 2 .. 20 loop
         Text (K) := Character'Val (Character'Pos ('0') + Rest mod 10);
         Rest := Rest / 10;
         First := K;
         exit when Rest = 0;
         pragma Loop_Invariant (First = K and then Rest >= 1);
      end loop;
      if Value < 0 then
         First := First - 1;
         Text (First) := '-';
      end if;
      declare
         Last   : constant Natural := 21 - First;
         Result : constant String (1 .. Last) := Text (First .. 20);
      begin
         return Result;
      end;
   end Image_Of;

   procedure Bad (Status : out Ks_Status; Message : String)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad (Status : out Ks_Status; Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Bad_Handle (Status : out Ks_Status; Operation : Name_Text)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;
   --  "<Operation>: the region handle is inconsistent".

   procedure Bad_Handle (Status : out Ks_Status; Operation : Name_Text) is
   begin
      Bad (Status, Operation & ": the region handle is inconsistent");
   end Bad_Handle;

   procedure Out_Of_Memory (Status : out Ks_Status; Operation : Name_Text)
   with Post => Valid (Status) and then Status.Failure = Failure_Out_Of_Memory;
   --  "<Operation>: not enough memory for the region".

   procedure Out_Of_Memory (Status : out Ks_Status; Operation : Name_Text) is
   begin
      Set_Failure (Status, Failure_Out_Of_Memory,
                   Operation & ": not enough memory for the region");
   end Out_Of_Memory;

   procedure Malformed (Status : out Ks_Status; Why : Name_Text)
   with Post => Valid (Status) and then Status.Failure = Failure_Image_File;
   --  "Pixel_Region'Read: <Why>", for a stream that does not hold a valid
   --  region.

   procedure Malformed (Status : out Ks_Status; Why : Name_Text) is
   begin
      Set_Failure (Status, Failure_Image_File, "Pixel_Region'Read: " & Why);
   end Malformed;

   procedure Check_Image
     (Operation     : Name_Text;
      Width, Height : Int32;
      Status        : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                and then Succeeded (Status)
                           = Valid_Image_Size (Width, Height);
   --  Image_No_Pixels for 0 x 0 ("<Operation>: the image has no pixels"),
   --  Bad_Parameter for another size that is not a valid image size.

   procedure Check_Image
     (Operation     : Name_Text;
      Width, Height : Int32;
      Status        : out Ks_Status) is
   begin
      if Width = 0 and then Height = 0 then
         Set_Failure (Status, Failure_Image_No_Pixels,
                      Operation & ": the image has no pixels");
      elsif not Valid_Image_Size (Width, Height) then
         Bad (Status, Operation & ": the image size "
                      & Image_Of (Int64 (Width)) & " x "
                      & Image_Of (Int64 (Height)) & " is not valid");
      else
         Set_Success (Status);
      end if;
   end Check_Image;

   ---------------------------------------------------------------------
   --  Counting
   ---------------------------------------------------------------------

   function Count_Flags (F : Flag_Matrix) return Int64
   with
     Pre  => F'First (1) <= F'Last (1) and then F'First (2) <= F'Last (2),
     Post => Count_Flags'Result = Count_Of (F);
   --  The number of True flags.

   function Count_Flags (F : Flag_Matrix) return Int64 is
      Count : Int64 := 0;
   begin
      for Y in F'Range (1) loop
         pragma Loop_Invariant (Count = Rows_Count (F, Int64 (Y)));
         for X in F'Range (2) loop
            if F (Y, X) then
               Count := Count + 1;
            end if;
            pragma Loop_Invariant
              (Count = Rows_Count (F, Int64 (Y))
                       + Row_Count (F, Y, Int64 (X) + 1));
         end loop;
      end loop;
      return Count;
   end Count_Flags;

   ---------------------------------------------------------------------
   --  Rasterisation
   ---------------------------------------------------------------------

   function Map_X
     (Transform : KT.Ks_Transform_2D_Linear;
      X, Y      : Int32) return Long_Float
   is ((N.Mul (Transform.A, Long_Float (X))
        + N.Mul (Transform.B, Long_Float (Y)))
       + Transform.Translation_X);

   function Map_Y
     (Transform : KT.Ks_Transform_2D_Linear;
      X, Y      : Int32) return Long_Float
   is ((N.Mul (Transform.C, Long_Float (X))
        + N.Mul (Transform.D, Long_Float (Y)))
       + Transform.Translation_Y);

   function Inside
     (Shape             : Shape_Data;
      Polygon           : access constant KS.Ks_Polygon_Data;
      Region_From_Pixel : KT.Ks_Transform_2D_Linear;
      X, Y              : Int32) return Boolean
   is
      U : constant Long_Float := Map_X (Region_From_Pixel, X, Y);
      V : constant Long_Float := Map_Y (Region_From_Pixel, X, Y);
   begin
      return KS.Bounded (U) and then KS.Bounded (V)
        and then Shape_Contains (Shape, Polygon, U, V);
   end Inside;

   Corner_Limit : constant := 2.0 ** 1004;
   --  A corner of a bounding box mapped into pixel space: two products of
   --  values within 1.0E150 (below 2**501) and a translation.

   function Corner_X
     (T    : KT.Ks_Transform_2D_Linear;
      X, Y : Long_Float) return Long_Float
   is ((N.Mul_Small (T.A, X) + N.Mul_Small (T.B, Y)) + T.Translation_X)
   with Pre  => KT.Bounded (T) and then KS.Bounded (X)
                and then KS.Bounded (Y),
        Post => abs Corner_X'Result <= Corner_Limit;
   --  The x of (X, Y) mapped by T, as Map_Point computes it.

   function Corner_Y
     (T    : KT.Ks_Transform_2D_Linear;
      X, Y : Long_Float) return Long_Float
   is ((N.Mul_Small (T.C, X) + N.Mul_Small (T.D, Y)) + T.Translation_Y)
   with Pre  => KT.Bounded (T) and then KS.Bounded (X)
                and then KS.Bounded (Y),
        Post => abs Corner_Y'Result <= Corner_Limit;

   function Ceiling_Index (X : Long_Float; Last : Int32) return Int32
   with Pre  => Last >= 0 and then X > 0.0
                and then X <= Long_Float (Last),
        Post => Ceiling_Index'Result in 0 .. Last;
   --  The smallest integer not below X (in 1 .. Last).

   function Ceiling_Index (X : Long_Float; Last : Int32) return Int32 is
      K : Int64 := Int64 (X);
   begin
      if Long_Float (K) < X then
         K := K + 1;
      end if;
      --  K is in 1 .. Last; the bounds below never change it (a run-time
      --  guard listed in docs/PROOF.md).
      return Int32 (Int64'Max (0, Int64'Min (K, Int64 (Last))));
   end Ceiling_Index;

   function Floor_Index (X : Long_Float; Last : Int32) return Int32
   with Pre  => Last >= 0 and then X >= 0.0
                and then X < Long_Float (Last),
        Post => Floor_Index'Result in 0 .. Last;
   --  The largest integer not above X (in 0 .. Last - 1).

   function Floor_Index (X : Long_Float; Last : Int32) return Int32 is
      K : Int64 := Int64 (X);
   begin
      if Long_Float (K) > X then
         K := K - 1;
      end if;
      --  As in Ceiling_Index.
      return Int32 (Int64'Max (0, Int64'Min (K, Int64 (Last))));
   end Floor_Index;

   procedure Candidate_Box
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
      Slack                     : Long_Float;
      Box                       : out Pixel_Box;
      Found                     : out Boolean)
   is
      T : KT.Ks_Transform_2D_Linear renames Pixel_From_Region;

      --  The image of the slack (see AMV.Regions) plus half a pixel.
      Margin_X : constant Long_Float :=
        0.5 + N.Mul_Small (Slack, abs T.A + abs T.B);
      Margin_Y : constant Long_Float :=
        0.5 + N.Mul_Small (Slack, abs T.C + abs T.D);

      --  The four corners of the bounding box in pixel space.
      X1 : constant Long_Float := Corner_X (T, Min_X, Min_Y);
      Y1 : constant Long_Float := Corner_Y (T, Min_X, Min_Y);
      X2 : constant Long_Float := Corner_X (T, Max_X, Min_Y);
      Y2 : constant Long_Float := Corner_Y (T, Max_X, Min_Y);
      X3 : constant Long_Float := Corner_X (T, Min_X, Max_Y);
      Y3 : constant Long_Float := Corner_Y (T, Min_X, Max_Y);
      X4 : constant Long_Float := Corner_X (T, Max_X, Max_Y);
      Y4 : constant Long_Float := Corner_Y (T, Max_X, Max_Y);

      Lo_X : constant Long_Float :=
        Long_Float'Min (Long_Float'Min (X1, X2), Long_Float'Min (X3, X4))
        - Margin_X;
      Hi_X : constant Long_Float :=
        Long_Float'Max (Long_Float'Max (X1, X2), Long_Float'Max (X3, X4))
        + Margin_X;
      Lo_Y : constant Long_Float :=
        Long_Float'Min (Long_Float'Min (Y1, Y2), Long_Float'Min (Y3, Y4))
        - Margin_Y;
      Hi_Y : constant Long_Float :=
        Long_Float'Max (Long_Float'Max (Y1, Y2), Long_Float'Max (Y3, Y4))
        + Margin_Y;

      Last_X : constant Int32 := Image_Width - 1;
      Last_Y : constant Int32 := Image_Height - 1;
   begin
      Box := (others => 0);
      Found := False;
      --  The comparisons come first, so that the conversions below only
      --  see coordinates within the image.
      if Hi_X >= 0.0 and then Lo_X <= Long_Float (Last_X)
        and then Hi_Y >= 0.0 and then Lo_Y <= Long_Float (Last_Y)
      then
         Box.X_First :=
           (if Lo_X <= 0.0 then 0 else Ceiling_Index (Lo_X, Last_X));
         Box.X_Last :=
           (if Hi_X >= Long_Float (Last_X) then Last_X
            else Floor_Index (Hi_X, Last_X));
         Box.Y_First :=
           (if Lo_Y <= 0.0 then 0 else Ceiling_Index (Lo_Y, Last_Y));
         Box.Y_Last :=
           (if Hi_Y >= Long_Float (Last_Y) then Last_Y
            else Floor_Index (Hi_Y, Last_Y));
         Found := Box.X_First <= Box.X_Last
                  and then Box.Y_First <= Box.Y_Last;
      end if;
   end Candidate_Box;

   procedure Fill_Inside
     (Shape   : Shape_Data;
      Polygon : access constant KS.Ks_Polygon_Data;
      Inverse : KT.Ks_Transform_2D_Linear;
      Flags   : in out Flag_Matrix)
   with
     Pre  => Valid_Shape (Shape, Polygon) and then KT.Bounded (Inverse),
     Post => (for all Y in Flags'Range (1) =>
                (for all X in Flags'Range (2) =>
                   Flags (Y, X)
                     = Inside (Shape, Polygon, Inverse, Int32 (X),
                               Int32 (Y))));
   --  Sets every flag to Inside of its pixel.

   procedure Fill_Inside
     (Shape   : Shape_Data;
      Polygon : access constant KS.Ks_Polygon_Data;
      Inverse : KT.Ks_Transform_2D_Linear;
      Flags   : in out Flag_Matrix) is
   begin
      for Y in Flags'Range (1) loop
         pragma Loop_Invariant
           (for all J in Flags'First (1) .. Y - 1 =>
              (for all I in Flags'Range (2) =>
                 Flags (J, I)
                   = Inside (Shape, Polygon, Inverse, Int32 (I), Int32 (J))));
         for X in Flags'Range (2) loop
            Flags (Y, X) :=
              Inside (Shape, Polygon, Inverse, Int32 (X), Int32 (Y));
            pragma Loop_Invariant
              (for all J in Flags'First (1) .. Y - 1 =>
                 (for all I in Flags'Range (2) =>
                    Flags (J, I)
                      = Inside (Shape, Polygon, Inverse, Int32 (I),
                                Int32 (J))));
            pragma Loop_Invariant
              (for all I in Flags'First (2) .. X =>
                 Flags (Y, I)
                   = Inside (Shape, Polygon, Inverse, Int32 (I), Int32 (Y)));
         end loop;
      end loop;
   end Fill_Inside;

   procedure Fill_Restricted
     (Region             : access constant Ks_Pixel_Region_Data;
      Mask               : access constant KI.Ks_Image_8_Grey_Data;
      Offset_X, Offset_Y : Int32;
      Flags              : in out Flag_Matrix)
   with
     Post => (for all Y in Flags'Range (1) =>
                (for all X in Flags'Range (2) =>
                   Flags (Y, X)
                     = (Contains (Region, Int32 (X), Int32 (Y))
                        and then Cared_For (Mask, Offset_X, Offset_Y,
                                            Int32 (X), Int32 (Y)))));
   --  Sets every flag to whether its pixel is a care pixel of Region.

   procedure Fill_Restricted
     (Region             : access constant Ks_Pixel_Region_Data;
      Mask               : access constant KI.Ks_Image_8_Grey_Data;
      Offset_X, Offset_Y : Int32;
      Flags              : in out Flag_Matrix) is
   begin
      for Y in Flags'Range (1) loop
         pragma Loop_Invariant
           (for all J in Flags'First (1) .. Y - 1 =>
              (for all I in Flags'Range (2) =>
                 Flags (J, I)
                   = (Contains (Region, Int32 (I), Int32 (J))
                      and then Cared_For (Mask, Offset_X, Offset_Y,
                                          Int32 (I), Int32 (J)))));
         for X in Flags'Range (2) loop
            Flags (Y, X) :=
              Contains (Region, Int32 (X), Int32 (Y))
              and then Cared_For (Mask, Offset_X, Offset_Y, Int32 (X),
                                  Int32 (Y));
            pragma Loop_Invariant
              (for all J in Flags'First (1) .. Y - 1 =>
                 (for all I in Flags'Range (2) =>
                    Flags (J, I)
                      = (Contains (Region, Int32 (I), Int32 (J))
                         and then Cared_For (Mask, Offset_X, Offset_Y,
                                             Int32 (I), Int32 (J)))));
            pragma Loop_Invariant
              (for all I in Flags'First (2) .. X =>
                 Flags (Y, I)
                   = (Contains (Region, Int32 (I), Int32 (Y))
                      and then Cared_For (Mask, Offset_X, Offset_Y,
                                          Int32 (I), Int32 (Y))));
         end loop;
      end loop;
   end Fill_Restricted;

   procedure Find_Bounds
     (Flags : Flag_Matrix;
      Found : out Boolean;
      Min_X, Max_X, Min_Y, Max_Y       : out Natural;
      Top_X, Bottom_X, Left_Y, Right_Y : out Natural)
   with
     Pre  => Flags'First (1) <= Flags'Last (1)
             and then Flags'First (2) <= Flags'Last (2),
     Post =>
       (for all Y in Flags'Range (1) =>
          (for all X in Flags'Range (2) =>
             (if Flags (Y, X)
              then Found and then X in Min_X .. Max_X
                   and then Y in Min_Y .. Max_Y)))
       and then
         (if Found
          then Min_X >= Flags'First (2) and then Max_X <= Flags'Last (2)
               and then Min_X <= Max_X
               and then Min_Y >= Flags'First (1)
               and then Max_Y <= Flags'Last (1)
               and then Min_Y <= Max_Y
               and then Top_X in Min_X .. Max_X
               and then Flags (Min_Y, Top_X)
               and then Bottom_X in Min_X .. Max_X
               and then Flags (Max_Y, Bottom_X)
               and then Left_Y in Min_Y .. Max_Y
               and then Flags (Left_Y, Min_X)
               and then Right_Y in Min_Y .. Max_Y
               and then Flags (Right_Y, Max_X));
   --  The smallest rectangle around the True flags (Found is False when
   --  there is none), with a True flag in each of its border rows and
   --  columns: (Min_Y, Top_X), (Max_Y, Bottom_X), (Left_Y, Min_X) and
   --  (Right_Y, Max_X).

   procedure Find_Bounds
     (Flags : Flag_Matrix;
      Found : out Boolean;
      Min_X, Max_X, Min_Y, Max_Y       : out Natural;
      Top_X, Bottom_X, Left_Y, Right_Y : out Natural) is
   begin
      Found := False;
      Min_X := Flags'First (2);
      Max_X := Flags'First (2);
      Min_Y := Flags'First (1);
      Max_Y := Flags'First (1);
      Top_X := Flags'First (2);
      Bottom_X := Flags'First (2);
      Left_Y := Flags'First (1);
      Right_Y := Flags'First (1);
      for Y in Flags'Range (1) loop
         pragma Loop_Invariant
           (for all J in Flags'First (1) .. Y - 1 =>
              (for all I in Flags'Range (2) =>
                 (if Flags (J, I)
                  then Found and then I in Min_X .. Max_X
                       and then J in Min_Y .. Max_Y)));
         pragma Loop_Invariant
           (if Found
            then Min_X >= Flags'First (2) and then Max_X <= Flags'Last (2)
                 and then Min_X <= Max_X
                 and then Min_Y >= Flags'First (1) and then Min_Y <= Max_Y
                 and then Max_Y < Y
                 and then Top_X in Min_X .. Max_X
                 and then Flags (Min_Y, Top_X)
                 and then Bottom_X in Min_X .. Max_X
                 and then Flags (Max_Y, Bottom_X)
                 and then Left_Y in Min_Y .. Max_Y
                 and then Flags (Left_Y, Min_X)
                 and then Right_Y in Min_Y .. Max_Y
                 and then Flags (Right_Y, Max_X));
         for X in Flags'Range (2) loop
            if Flags (Y, X) then
               if not Found then
                  Found := True;
                  Min_X := X;
                  Max_X := X;
                  Min_Y := Y;
                  Max_Y := Y;
                  Top_X := X;
                  Bottom_X := X;
                  Left_Y := Y;
                  Right_Y := Y;
               else
                  if X < Min_X then
                     Min_X := X;
                     Left_Y := Y;
                  end if;
                  if X > Max_X then
                     Max_X := X;
                     Right_Y := Y;
                  end if;
                  if Y > Max_Y then
                     Max_Y := Y;
                     Bottom_X := X;
                  end if;
               end if;
            end if;
            pragma Loop_Invariant
              (for all J in Flags'First (1) .. Y - 1 =>
                 (for all I in Flags'Range (2) =>
                    (if Flags (J, I)
                     then Found and then I in Min_X .. Max_X
                          and then J in Min_Y .. Max_Y)));
            pragma Loop_Invariant
              (for all I in Flags'First (2) .. X =>
                 (if Flags (Y, I)
                  then Found and then I in Min_X .. Max_X
                       and then Y in Min_Y .. Max_Y));
            pragma Loop_Invariant
              (if Found
               then Min_X >= Flags'First (2) and then Max_X <= Flags'Last (2)
                    and then Min_X <= Max_X
                    and then Min_Y >= Flags'First (1) and then Min_Y <= Max_Y
                    and then Max_Y <= Y
                    and then Top_X in Min_X .. Max_X
                    and then Flags (Min_Y, Top_X)
                    and then (Min_Y < Y or else Top_X <= X)
                    and then Bottom_X in Min_X .. Max_X
                    and then Flags (Max_Y, Bottom_X)
                    and then (Max_Y < Y or else Bottom_X <= X)
                    and then Left_Y in Min_Y .. Max_Y
                    and then Flags (Left_Y, Min_X)
                    and then (Left_Y < Y or else Min_X <= X)
                    and then Right_Y in Min_Y .. Max_Y
                    and then Flags (Right_Y, Max_X)
                    and then (Right_Y < Y or else Max_X <= X));
         end loop;
      end loop;
   end Find_Bounds;

   procedure Copy_Flags (Source : Flag_Matrix; Target : in out Flag_Matrix)
   with
     Pre  => Target'First (1) <= Target'Last (1)
             and then Target'First (2) <= Target'Last (2)
             and then Target'First (1) >= Source'First (1)
             and then Target'Last (1) <= Source'Last (1)
             and then Target'First (2) >= Source'First (2)
             and then Target'Last (2) <= Source'Last (2),
     Post => (for all Y in Target'Range (1) =>
                (for all X in Target'Range (2) =>
                   Target (Y, X) = Source (Y, X)));
   --  Copies the part of Source that Target covers.

   procedure Copy_Flags (Source : Flag_Matrix; Target : in out Flag_Matrix)
   is
   begin
      for Y in Target'Range (1) loop
         pragma Loop_Invariant
           (for all J in Target'First (1) .. Y - 1 =>
              (for all I in Target'Range (2) =>
                 Target (J, I) = Source (J, I)));
         for X in Target'Range (2) loop
            Target (Y, X) := Source (Y, X);
            pragma Loop_Invariant
              (for all J in Target'First (1) .. Y - 1 =>
                 (for all I in Target'Range (2) =>
                    Target (J, I) = Source (J, I)));
            pragma Loop_Invariant
              (for all I in Target'First (2) .. X =>
                 Target (Y, I) = Source (Y, I));
         end loop;
      end loop;
   end Copy_Flags;

   procedure Copy_Shifted_Flags
     (Source       : Flag_Matrix;
      Y_Off, X_Off : Natural;
      Target       : in out Flag_Matrix)
   with
     Pre  => Target'First (1) = 0 and then Target'First (2) = 0
             and then Target'Last (1) >= 0 and then Target'Last (2) >= 0
             and then Source'First (1) = Y_Off
             and then Source'First (2) = X_Off
             and then Int64 (Target'Last (1)) + Int64 (Y_Off)
                        <= Int64 (Source'Last (1))
             and then Int64 (Target'Last (2)) + Int64 (X_Off)
                        <= Int64 (Source'Last (2)),
     Post => (for all Y in Target'Range (1) =>
                (for all X in Target'Range (2) =>
                   Target (Y, X) = Source (Y_Off + Y, X_Off + X)));
   --  Copies Source, moved by (-X_Off, -Y_Off), into Target.

   procedure Copy_Shifted_Flags
     (Source       : Flag_Matrix;
      Y_Off, X_Off : Natural;
      Target       : in out Flag_Matrix)
   is
   begin
      for Y in Target'Range (1) loop
         pragma Loop_Invariant
           (for all J in 0 .. Y - 1 =>
              (for all I in Target'Range (2) =>
                 Target (J, I) = Source (Y_Off + J, X_Off + I)));
         for X in Target'Range (2) loop
            Target (Y, X) := Source (Y_Off + Y, X_Off + X);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1 =>
                 (for all I in Target'Range (2) =>
                    Target (J, I) = Source (Y_Off + J, X_Off + I)));
            pragma Loop_Invariant
              (for all I in 0 .. X =>
                 Target (Y, I) = Source (Y_Off + Y, X_Off + I));
         end loop;
      end loop;
   end Copy_Shifted_Flags;

   procedure Release (Region : in out Ks_Pixel_Region)
   with Post => Region = null;
   --  Frees Region (if any) and its flags.

   procedure Release (Region : in out Ks_Pixel_Region) is
   begin
      if Region /= null then
         Free (Region.Flags);
         Free (Region);
      end if;
   end Release;

   procedure Build_Region
     (Operation : Name_Text;
      Flags     : in out Flag_Matrix_Access;
      Region    : out Ks_Pixel_Region;
      Status    : out Ks_Status)
   with
     Pre  => Flags /= null
             and then Flags'First (1) <= Flags'Last (1)
             and then Flags'First (2) <= Flags'Last (2)
             and then (Int64 (Flags'Last (2)) - Int64 (Flags'First (2)) + 1)
                      * (Int64 (Flags'Last (1)) - Int64 (Flags'First (1))
                         + 1)
                        <= Max_Pixels,
     Post => Flags = null
             and then Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then Consistent (Region)
                     and then
                       (Region = null
                        or else
                          (Int64 (Region.X_Min)
                             >= Int64 (Flags.all'Old'First (2))
                           and then Int64 (Region.Y_Min)
                                      >= Int64 (Flags.all'Old'First (1))
                           and then Int64 (Region.X_Min)
                                      + Int64 (Region.Width) - 1
                                      <= Int64 (Flags.all'Old'Last (2))
                           and then Int64 (Region.Y_Min)
                                      + Int64 (Region.Height) - 1
                                      <= Int64 (Flags.all'Old'Last (1))))
                     and then
                       (for all Y in Flags.all'Old'Range (1) =>
                          (for all X in Flags.all'Old'Range (2) =>
                             Contains (Region, Int32 (X), Int32 (Y))
                               = Flags.all'Old (Y, X)))
                else Region = null);
   --  The region of the True flags of Flags, one flag per pixel indexed by
   --  the pixel coordinates (Gold: for every flag, Contains of the result
   --  is exactly the flag; the rectangle lies within the flags, so no
   --  other pixel belongs to the region; Count and the smallest rectangle
   --  by Consistent). Null when no flag is set. It takes Flags over: the
   --  matrix becomes the region's flags when the smallest rectangle around
   --  the True flags is the whole matrix and not every flag is set, and is
   --  freed otherwise (after copying the flags of that rectangle when not
   --  every one of them is set). Out_Of_Memory ("<Operation>: not enough
   --  memory for the region") when the handle or the copy cannot be
   --  allocated.

   procedure Build_Region
     (Operation : Name_Text;
      Flags     : in out Flag_Matrix_Access;
      Region    : out Ks_Pixel_Region;
      Status    : out Ks_Status)
   is
      Old_Flags : constant Flag_Matrix := Flags.all with Ghost;
      Keep      : Flag_Matrix_Access;
      Found     : Boolean;
      Min_X, Max_X, Min_Y, Max_Y       : Natural;
      Top_X, Bottom_X, Left_Y, Right_Y : Natural;
      Count     : Int64;
   begin
      Region := null;
      Find_Bounds (Flags.all, Found, Min_X, Max_X, Min_Y, Max_Y, Top_X,
                   Bottom_X, Left_Y, Right_Y);

      --  What the search found, stated on the flags on entry, so that it
      --  outlives them.
      pragma Assert
        (for all Y in Old_Flags'Range (1) =>
           (for all X in Old_Flags'Range (2) =>
              (if Old_Flags (Y, X)
               then Found and then X in Min_X .. Max_X
                    and then Y in Min_Y .. Max_Y)));

      if not Found then
         Free (Flags);
         Set_Success (Status);
         return;
      end if;

      Allocate_Region (Region);
      if Region = null then
         Free (Flags);
         Out_Of_Memory (Status, Operation);
         return;
      end if;

      if Min_X = Flags'First (2) and then Max_X = Flags'Last (2)
        and then Min_Y = Flags'First (1) and then Max_Y = Flags'Last (1)
      then
         --  Nothing to shrink: keep the matrix.
         Keep := Flags;
         Flags := null;
      else
         Allocate_Flags (Min_Y, Max_Y, Min_X, Max_X, Keep);
         if Keep = null then
            Free (Flags);
            Release (Region);
            Out_Of_Memory (Status, Operation);
            return;
         end if;
         Copy_Flags (Flags.all, Keep.all);
         Free (Flags);
      end if;
      pragma Assert
        (for all Y in Keep'Range (1) =>
           (for all X in Keep'Range (2) => Keep (Y, X) = Old_Flags (Y, X)));
      pragma Assert (Keep (Keep'First (1), Top_X));
      pragma Assert (Keep (Keep'Last (1), Bottom_X));
      pragma Assert (Keep (Left_Y, Keep'First (2)));
      pragma Assert (Keep (Right_Y, Keep'Last (2)));
      pragma Assert (Smallest (Keep.all));

      Lemma_Box_Size
        (W1 => Int64 (Max_X) - Int64 (Min_X) + 1,
         H1 => Int64 (Max_Y) - Int64 (Min_Y) + 1,
         W2 => Int64 (Old_Flags'Last (2)) - Int64 (Old_Flags'First (2)) + 1,
         H2 => Int64 (Old_Flags'Last (1)) - Int64 (Old_Flags'First (1)) + 1);

      Count := Count_Flags (Keep.all);
      Lemma_Rows_Positive
        (Keep.all, Int64 (Keep'Last (1)) + 1, Keep'First (1), Top_X);

      declare
         Width  : constant Int64 := Int64 (Max_X) - Int64 (Min_X) + 1;
         Height : constant Int64 := Int64 (Max_Y) - Int64 (Min_Y) + 1;
      begin
         pragma Assert (Length_2 (Keep.all) = Width);
         pragma Assert
           (Int64 (Keep'Last (1)) + 1 - Int64 (Keep'First (1)) = Height);
         pragma Assert
           (Count = Rows_Count (Keep.all, Int64 (Keep'Last (1)) + 1));
         pragma Assert (Big (Count) <= Big (Height) * Big (Width));
         Region.X_Min := Int32 (Min_X);
         Region.Y_Min := Int32 (Min_Y);
         Region.Width := Int32 (Width);
         Region.Height := Int32 (Height);
         Region.Count := Int32 (Count);
         if Count = Width * Height then
            --  Every pixel of the rectangle is in the region: no flags.
            pragma Assert (Big (Count) = Big (Height) * Big (Width));
            Lemma_Rows_Full (Keep.all, Int64 (Keep'Last (1)) + 1);
            pragma Assert
              (for all Y in Keep'Range (1) =>
                 (for all X in Keep'Range (2) => Keep (Y, X)));
            pragma Assert
              (for all Y in Keep'Range (1) =>
                 (for all X in Keep'Range (2) => Old_Flags (Y, X)));
            Free (Keep);
            pragma Assert (Valid_Region (Region));
         else
            Region.Flags := Keep;
            pragma Assert (Valid_Region (Region));
            pragma Assert
              (Int64 (Region.Count) = Count_Of (Region.Flags.all));
            pragma Assert (Smallest (Region.Flags.all));
         end if;
      end;
      pragma Assert
        (for all Y in Old_Flags'Range (1) =>
           (for all X in Old_Flags'Range (2) =>
              Contains (Region, Int32 (X), Int32 (Y)) = Old_Flags (Y, X)));
      Set_Success (Status);
   end Build_Region;

   procedure Rasterize_Box
     (Shape             : Shape_Data;
      Polygon           : access constant KS.Ks_Polygon_Data;
      Region_From_Pixel : KT.Ks_Transform_2D_Linear;
      Box               : Pixel_Box;
      Region            : out Ks_Pixel_Region;
      Status            : out Ks_Status)
   is
      Flags : Flag_Matrix_Access;
   begin
      Region := null;
      Allocate_Flags
        (Natural (Box.Y_First), Natural (Box.Y_Last),
         Natural (Box.X_First), Natural (Box.X_Last), Flags);
      if Flags = null then
         Out_Of_Memory (Status, "Rasterize");
         return;
      end if;
      Fill_Inside (Shape, Polygon, Region_From_Pixel, Flags.all);
      Build_Region ("Rasterize", Flags, Region, Status);
      pragma Assert (Flags = null);
      --  The region took the flags over or they were freed.
   end Rasterize_Box;

   procedure Prepare
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Inverse                   : out KT.Ks_Transform_2D_Linear;
      Status                    : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure
                           in Failure_None | Failure_Image_No_Pixels
                            | Failure_Bad_Parameter
                            | Failure_Transform_Singular
                and then (if Succeeded (Status)
                          then Valid_Image_Size (Image_Width, Image_Height)
                               and then KT.Bounded (Pixel_From_Region)
                               and then KT.Bounded (Inverse));
   --  The checks of the image size and the transform, and the inverse of
   --  the transform.

   procedure Prepare
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Inverse                   : out KT.Ks_Transform_2D_Linear;
      Status                    : out Ks_Status) is
   begin
      Inverse := (others => <>);
      Check_Image ("Rasterize", Image_Width, Image_Height, Status);
      if not Succeeded (Status) then
         return;
      elsif not KT.Bounded (Pixel_From_Region) then
         Bad (Status, "Rasterize: Pixel_From_Region must be finite and "
                      & "within +/-1.0E150");
         return;
      end if;
      KT.Invert (Pixel_From_Region, Inverse, Status);
   end Prepare;

   procedure Rasterize_Shape
     (Shape                     : Shape_Data;
      Polygon                   : access constant KS.Ks_Polygon_Data;
      Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Inverse                   : KT.Ks_Transform_2D_Linear;
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
      Slack                     : Long_Float;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   with
     Pre  => Valid_Shape (Shape, Polygon)
             and then Valid_Image_Size (Image_Width, Image_Height)
             and then KT.Bounded (Pixel_From_Region)
             and then KT.Bounded (Inverse)
             and then KS.Valid_Box (Min_X, Min_Y, Max_X, Max_Y)
             and then Slack in 0.0 .. KS.Max_Slack,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then (if Succeeded (Status)
                       then Consistent (Region)
                            and then In_Image
                                       (Region, Image_Width, Image_Height)
                       else Region = null);
   --  The candidate box and Rasterize_Box: the common end of the entry
   --  points.

   procedure Rasterize_Shape
     (Shape                     : Shape_Data;
      Polygon                   : access constant KS.Ks_Polygon_Data;
      Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Inverse                   : KT.Ks_Transform_2D_Linear;
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
      Slack                     : Long_Float;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   is
      Box   : Pixel_Box;
      Found : Boolean;
   begin
      Region := null;
      Candidate_Box
        (Image_Width, Image_Height, Pixel_From_Region, Min_X, Min_Y, Max_X,
         Max_Y, Slack, Box, Found);
      if not Found then
         Set_Success (Status);
         return;
      end if;
      Lemma_Box_Size
        (W1 => Int64 (Box.X_Last) - Int64 (Box.X_First) + 1,
         H1 => Int64 (Box.Y_Last) - Int64 (Box.Y_First) + 1,
         W2 => Int64 (Image_Width),
         H2 => Int64 (Image_Height));
      Rasterize_Box (Shape, Polygon, Inverse, Box, Region, Status);
   end Rasterize_Shape;

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Whole_Image
     (Image_Width, Image_Height : Int32;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status) is
   begin
      Region := null;
      Check_Image ("Whole_Image", Image_Width, Image_Height, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Allocate_Region (Region);
      if Region = null then
         Out_Of_Memory (Status, "Whole_Image");
         return;
      end if;
      Region.Width := Image_Width;
      Region.Height := Image_Height;
      Region.Count := Int32 (Int64 (Image_Width) * Int64 (Image_Height));
   end Whole_Image;

   procedure Destroy
     (Region : in out Ks_Pixel_Region;
      Status : out Ks_Status) is
   begin
      Release (Region);
      Set_Success (Status);
   end Destroy;

   procedure Duplicate
     (Region : access constant Ks_Pixel_Region_Data;
      Result : out Ks_Pixel_Region;
      Status : out Ks_Status)
   is
      Copy : Flag_Matrix_Access;
   begin
      Result := null;
      if Region = null then
         Set_Success (Status);
         return;
      elsif not Valid_Region (Region) then
         Bad_Handle (Status, "Duplicate");
         return;
      end if;
      Allocate_Region (Result);
      if Result = null then
         Out_Of_Memory (Status, "Duplicate");
         return;
      end if;
      Result.X_Min := Region.X_Min;
      Result.Y_Min := Region.Y_Min;
      Result.Width := Region.Width;
      Result.Height := Region.Height;
      Result.Count := Region.Count;
      if Region.Flags /= null then
         Allocate_Flags
           (Region.Flags'First (1), Region.Flags'Last (1),
            Region.Flags'First (2), Region.Flags'Last (2), Copy);
         if Copy = null then
            Release (Result);
            Out_Of_Memory (Status, "Duplicate");
            return;
         end if;
         Copy.all := Region.Flags.all;
         Result.Flags := Copy;
      end if;
      Set_Success (Status);
   end Duplicate;

   procedure Bounding_Box
     (Region : access constant Ks_Pixel_Region_Data;
      Result : out Ks_Pixel_Region;
      Status : out Ks_Status)
   is
   begin
      Result := null;
      if Region = null then
         Set_Success (Status);
         return;
      elsif not Valid_Region (Region) then
         Bad_Handle (Status, "Bounding_Box");
         return;
      end if;
      Allocate_Region (Result);
      if Result = null then
         Out_Of_Memory (Status, "Bounding_Box");
         return;
      end if;
      Result.X_Min := Region.X_Min;
      Result.Y_Min := Region.Y_Min;
      Result.Width := Region.Width;
      Result.Height := Region.Height;
      Result.Count := Int32 (Int64 (Region.Width) * Int64 (Region.Height));
      Set_Success (Status);
   end Bounding_Box;

   procedure Shift_To_Origin
     (Region : access constant Ks_Pixel_Region_Data;
      Result : out Ks_Pixel_Region;
      Status : out Ks_Status)
   is
      Copy : Flag_Matrix_Access;
   begin
      Result := null;
      if Region = null or else not Valid_Region (Region) then
         Bad_Handle (Status, "Shift_To_Origin");
         return;
      end if;
      Allocate_Region (Result);
      if Result = null then
         Out_Of_Memory (Status, "Shift_To_Origin");
         return;
      end if;
      Result.Width := Region.Width;
      Result.Height := Region.Height;
      Result.Count := Region.Count;
      if Region.Flags /= null then
         Allocate_Flags
           (0, Natural (Region.Height) - 1, 0, Natural (Region.Width) - 1,
            Copy);
         if Copy = null then
            Release (Result);
            Out_Of_Memory (Status, "Shift_To_Origin");
            return;
         end if;
         Copy_Shifted_Flags
           (Region.Flags.all, Natural (Region.Y_Min), Natural (Region.X_Min),
            Copy.all);
         Result.Flags := Copy;
      end if;
      Set_Success (Status);
   end Shift_To_Origin;

   procedure Is_Empty
     (Region : access constant Ks_Pixel_Region_Data;
      Result : out Int32;
      Status : out Ks_Status) is
   begin
      Result := False_Value;
      if Region = null then
         Result := True_Value;
         Set_Success (Status);
      elsif not Valid_Region (Region) then
         Bad_Handle (Status, "Is_Empty");
      else
         Set_Success (Status);
      end if;
   end Is_Empty;

   procedure Pixel_Count
     (Region : access constant Ks_Pixel_Region_Data;
      Result : out Int32;
      Status : out Ks_Status) is
   begin
      Result := 0;
      if Region = null then
         Set_Success (Status);
      elsif not Valid_Region (Region) then
         Bad_Handle (Status, "Pixel_Count");
      else
         Result := Region.Count;
         Set_Success (Status);
      end if;
   end Pixel_Count;

   procedure Get_Bounds
     (Region                     : access constant Ks_Pixel_Region_Data;
      X_Min, Y_Min, Width, Height : out Int32;
      Status                     : out Ks_Status) is
   begin
      X_Min := 0;
      Y_Min := 0;
      Width := 0;
      Height := 0;
      if Region = null then
         Set_Success (Status);
      elsif not Valid_Region (Region) then
         Bad_Handle (Status, "Bounds");
      else
         X_Min := Region.X_Min;
         Y_Min := Region.Y_Min;
         Width := Region.Width;
         Height := Region.Height;
         Set_Success (Status);
      end if;
   end Get_Bounds;

   function Contains_Pixel
     (Region : access constant Ks_Pixel_Region_Data;
      X, Y   : Int32) return Int32 is
     (if Contains (Region, X, Y) then True_Value else False_Value);

   procedure Rasterize_Rectangle
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Rectangle                 : KS.Ks_Rectangle;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   is
      Inverse                    : KT.Ks_Transform_2D_Linear;
      Slack                      : Long_Float;
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
   begin
      Region := null;
      Prepare (Image_Width, Image_Height, Pixel_From_Region, Inverse,
               Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Boundary_Slack (Rectangle, Slack, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Get_Bounding_Box (Rectangle, Min_X, Min_Y, Max_X, Max_Y, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Rasterize_Shape
        ((Kind => Rectangle_Shape, Rectangle => Rectangle), null,
         Image_Width, Image_Height, Pixel_From_Region, Inverse,
         Min_X, Min_Y, Max_X, Max_Y, Slack, Region, Status);
   end Rasterize_Rectangle;

   procedure Rasterize_Rectangle_Affine
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Rectangle                 : KS.Ks_Rectangle_Affine;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   is
      Inverse                    : KT.Ks_Transform_2D_Linear;
      Slack                      : Long_Float;
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
   begin
      Region := null;
      Prepare (Image_Width, Image_Height, Pixel_From_Region, Inverse,
               Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Boundary_Slack (Rectangle, Slack, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Get_Bounding_Box (Rectangle, Min_X, Min_Y, Max_X, Max_Y, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Rasterize_Shape
        ((Kind => Rectangle_Affine_Shape, Rectangle_Affine => Rectangle),
         null, Image_Width, Image_Height, Pixel_From_Region, Inverse,
         Min_X, Min_Y, Max_X, Max_Y, Slack, Region, Status);
   end Rasterize_Rectangle_Affine;

   procedure Rasterize_Circle
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Circle                    : KS.Ks_Circle;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   is
      Inverse                    : KT.Ks_Transform_2D_Linear;
      Slack                      : Long_Float;
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
   begin
      Region := null;
      Prepare (Image_Width, Image_Height, Pixel_From_Region, Inverse,
               Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Boundary_Slack (Circle, Slack, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Get_Bounding_Box (Circle, Min_X, Min_Y, Max_X, Max_Y, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Rasterize_Shape
        ((Kind => Circle_Shape, Circle => Circle), null,
         Image_Width, Image_Height, Pixel_From_Region, Inverse,
         Min_X, Min_Y, Max_X, Max_Y, Slack, Region, Status);
   end Rasterize_Circle;

   procedure Rasterize_Ellipse
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Ellipse                   : KS.Ks_Ellipse;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   is
      Inverse                    : KT.Ks_Transform_2D_Linear;
      Slack                      : Long_Float;
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
   begin
      Region := null;
      Prepare (Image_Width, Image_Height, Pixel_From_Region, Inverse,
               Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Boundary_Slack (Ellipse, Slack, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Get_Bounding_Box (Ellipse, Min_X, Min_Y, Max_X, Max_Y, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Rasterize_Shape
        ((Kind => Ellipse_Shape, Ellipse => Ellipse), null,
         Image_Width, Image_Height, Pixel_From_Region, Inverse,
         Min_X, Min_Y, Max_X, Max_Y, Slack, Region, Status);
   end Rasterize_Ellipse;

   procedure Rasterize_Polygon
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Polygon                   : access constant KS.Ks_Polygon_Data;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   is
      Inverse                    : KT.Ks_Transform_2D_Linear;
      Slack                      : Long_Float;
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
   begin
      Region := null;
      Prepare (Image_Width, Image_Height, Pixel_From_Region, Inverse,
               Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Boundary_Slack (Polygon, Slack, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Get_Bounding_Box (Polygon, Min_X, Min_Y, Max_X, Max_Y, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Rasterize_Shape
        ((Kind => Polygon_Shape), Polygon,
         Image_Width, Image_Height, Pixel_From_Region, Inverse,
         Min_X, Min_Y, Max_X, Max_Y, Slack, Region, Status);
   end Rasterize_Polygon;

   procedure Rasterize_Circular_Annulus_Section
     (Image_Width, Image_Height : Int32;
      Pixel_From_Region         : KT.Ks_Transform_2D_Linear;
      Section                   : KS.Ks_Circular_Annulus_Section;
      Region                    : out Ks_Pixel_Region;
      Status                    : out Ks_Status)
   is
      Inverse                    : KT.Ks_Transform_2D_Linear;
      Slack                      : Long_Float;
      Min_X, Min_Y, Max_X, Max_Y : Long_Float;
   begin
      Region := null;
      Prepare (Image_Width, Image_Height, Pixel_From_Region, Inverse,
               Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Boundary_Slack (Section, Slack, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Get_Bounding_Box (Section, Min_X, Min_Y, Max_X, Max_Y, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Rasterize_Shape
        ((Kind => Section_Shape, Section => Section), null,
         Image_Width, Image_Height, Pixel_From_Region, Inverse,
         Min_X, Min_Y, Max_X, Max_Y, Slack, Region, Status);
   end Rasterize_Circular_Annulus_Section;

   procedure Restrict_To_Mask
     (Region             : access constant Ks_Pixel_Region_Data;
      Mask               : access constant KI.Ks_Image_8_Grey_Data;
      Offset_X, Offset_Y : Int32;
      Result             : out Ks_Pixel_Region;
      Status             : out Ks_Status)
   is
      Flags : Flag_Matrix_Access;
   begin
      Result := null;
      if Region /= null and then not Valid_Region (Region) then
         Bad_Handle (Status, "Restrict_To_Mask");
         return;
      elsif Mask /= null and then not KI.Valid_Image (Mask) then
         Bad (Status, "Restrict_To_Mask: the mask is not a valid image "
                      & "handle");
         return;
      elsif Region = null then
         Set_Success (Status);
         return;
      end if;
      --  One flag per pixel of the region's bounding rectangle.
      Allocate_Flags
        (Natural (Region.Y_Min), Natural (Region.Y_Min + (Region.Height - 1)),
         Natural (Region.X_Min), Natural (Region.X_Min + (Region.Width - 1)),
         Flags);
      if Flags = null then
         Out_Of_Memory (Status, "Restrict_To_Mask");
         return;
      end if;
      Fill_Restricted (Region, Mask, Offset_X, Offset_Y, Flags.all);
      Build_Region ("Restrict_To_Mask", Flags, Result, Status);
      pragma Assert (Flags = null);
      --  The result took the flags over or they were freed.
   end Restrict_To_Mask;

   ---------------------------------------------------------------------
   --  For the Ada API only
   ---------------------------------------------------------------------

   procedure Check_Rasterize
     (Image_Width, Image_Height : Int32;
      Shape_Type                : Int32;
      Status                    : out Ks_Status) is
   begin
      Check_Image ("Rasterize", Image_Width, Image_Height, Status);
      if Succeeded (Status)
        and then Shape_Type
                   not in KS.Shape_Rectangle | KS.Shape_Rectangle_Affine
                        | KS.Shape_Circle | KS.Shape_Ellipse
                        | KS.Shape_Polygon
                        | KS.Shape_Circular_Annulus_Section
      then
         Bad (Status, "Rasterize: the region must be a Ks_Rectangle, "
                      & "Ks_Rectangle_Affine, Ks_Circle, Ks_Ellipse, "
                      & "Ks_Polygon or Ks_Circular_Annulus_Section");
      end if;
   end Check_Rasterize;

   --  Streams

   procedure Put_Number
     (Header : in out Header_Bytes;
      Index  : Positive;
      Value  : U32)
   with Pre => Index <= 6;
   --  Bytes 4 * Index - 3 .. 4 * Index: Value, least significant first.

   procedure Put_Number
     (Header : in out Header_Bytes;
      Index  : Positive;
      Value  : U32)
   is
      Rest : U32 := Value;
   begin
      for K in 4 * Index - 3 .. 4 * Index loop
         Header (K) := Interfaces.Unsigned_8 (Rest and 16#FF#);
         Rest := Interfaces.Shift_Right (Rest, 8);
      end loop;
   end Put_Number;

   function Get_Number (Header : Header_Bytes; Index : Positive) return U32
   with Pre => Index <= 6;
   --  The number stored by Put_Number.

   function Get_Number (Header : Header_Bytes; Index : Positive) return U32
   is
      Value : U32 := 0;
   begin
      for K in reverse 4 * Index - 3 .. 4 * Index loop
         Value := Interfaces.Shift_Left (Value, 8) or U32 (Header (K));
      end loop;
      return Value;
   end Get_Number;

   procedure Stream_Header
     (Region : access constant Ks_Pixel_Region_Data;
      Header : out Header_Bytes;
      Status : out Ks_Status) is
   begin
      Header := [others => 0];
      Put_Number (Header, 1, Format_Code);
      if Region = null then
         Set_Success (Status);
      elsif not Valid_Region (Region) then
         Bad_Handle (Status, "Pixel_Region'Write");
      else
         Put_Number (Header, 2, U32 (Region.X_Min));
         Put_Number (Header, 3, U32 (Region.Y_Min));
         Put_Number (Header, 4, U32 (Region.Width));
         Put_Number (Header, 5, U32 (Region.Height));
         Put_Number (Header, 6, U32 (Region.Count));
         Set_Success (Status);
      end if;
   end Stream_Header;

   procedure Next_Write_Chunk
     (Region   : access constant Ks_Pixel_Region_Data;
      Position : Flag_Position;
      Limit    : Positive;
      Length   : out Natural)
   is
      Total : constant Int64 := Stream_Total (Region);
   begin
      if Position.Done < 0 or else Position.Done >= Total then
         Length := 0;
      else
         Length :=
           Natural (Int64'Min (Int64 (Limit), Total - Position.Done));
      end if;
   end Next_Write_Chunk;

   procedure Get_Flag_Bytes
     (Region   : access constant Ks_Pixel_Region_Data;
      Position : in out Flag_Position;
      Bytes    : out Byte_Array;
      Status   : out Ks_Status)
   is
      Total : constant Int64 := Stream_Total (Region);
   begin
      Bytes := [others => 0];
      if Total = 0 then
         Bad (Status, "Pixel_Region'Write: the region has no pixel "
                      & "elements");
         return;
      elsif Position.Done < 0
        or else Int64 (Bytes'Length) > Total - Position.Done
        or else Position.Row < 0 or else Position.Column < 0
        or else Position.Column >= Region.Width
      then
         Bad (Status, "Pixel_Region'Write: the position is not valid");
         return;
      end if;
      for K in Bytes'Range loop
         if Position.Row >= Region.Height then
            --  A position whose row and column do not match Done.
            Bad (Status, "Pixel_Region'Write: the position is not valid");
            return;
         end if;
         if Region.Flags
              (Integer (Region.Y_Min + Position.Row),
               Integer (Region.X_Min + Position.Column))
         then
            Bytes (K) := 1;
         end if;
         if Position.Column = Region.Width - 1 then
            Position.Column := 0;
            Position.Row := Position.Row + 1;
         else
            Position.Column := Position.Column + 1;
         end if;
         Position.Done := Position.Done + 1;
         pragma Loop_Invariant
           (Position.Row in 0 .. Region.Height
            and then Position.Column in 0 .. Region.Width - 1
            and then Position.Done
                       = Position.Done'Loop_Entry
                         + Int64 (K - Bytes'First + 1)
            and then Position.Done'Loop_Entry >= 0
            and then Position.Done'Loop_Entry + Int64 (Bytes'Length)
                       <= Total);
      end loop;
      Set_Success (Status);
   end Get_Flag_Bytes;

   procedure Read_Header
     (Header : Header_Bytes;
      Reader : out Ks_Region_Reader;
      Status : out Ks_Status)
   is
      Limit : constant U32 := U32 (Int32'Last);
   begin
      Reader := null;
      if Get_Number (Header, 1) /= Format_Code then
         Malformed (Status, "the stream does not hold a Pixel_Region "
                            & "(wrong format code)");
         return;
      elsif Get_Number (Header, 2) > Limit then
         Malformed (Status, "X_Min exceeds Natural'Last");
         return;
      elsif Get_Number (Header, 3) > Limit then
         Malformed (Status, "Y_Min exceeds Natural'Last");
         return;
      elsif Get_Number (Header, 4) > Limit then
         Malformed (Status, "Width exceeds Natural'Last");
         return;
      elsif Get_Number (Header, 5) > Limit then
         Malformed (Status, "Height exceeds Natural'Last");
         return;
      elsif Get_Number (Header, 6) > Limit then
         Malformed (Status, "Pixel_Count exceeds Natural'Last");
         return;
      end if;
      declare
         X_Min  : constant Int32 := Int32 (Get_Number (Header, 2));
         Y_Min  : constant Int32 := Int32 (Get_Number (Header, 3));
         Width  : constant Int32 := Int32 (Get_Number (Header, 4));
         Height : constant Int32 := Int32 (Get_Number (Header, 5));
         Count  : constant Int32 := Int32 (Get_Number (Header, 6));
      begin
         if Count = 0 then
            if X_Min /= 0 or else Y_Min /= 0 or else Width /= 0
              or else Height /= 0
            then
               Malformed (Status, "an empty region must have all bounds 0");
               return;
            end if;
         elsif Width = 0 or else Height = 0 then
            Malformed (Status, "a region with pixels needs a positive "
                               & "Width and Height");
            return;
         elsif Int64 (Width) * Int64 (Height) > Max_Pixels then
            Malformed (Status, "Width * Height exceeds Natural'Last");
            return;
         elsif Int64 (X_Min) + Int64 (Width) - 1 > Int64 (Int32'Last)
           or else Int64 (Y_Min) + Int64 (Height) - 1 > Int64 (Int32'Last)
         then
            Malformed (Status, "the bounding rectangle extends past "
                               & "Natural'Last");
            return;
         elsif Int64 (Count) > Int64 (Width) * Int64 (Height) then
            Malformed (Status, "Pixel_Count exceeds Width * Height");
            return;
         end if;
         Allocate_Reader (Reader);
         if Reader = null then
            Out_Of_Memory (Status, "Pixel_Region'Read");
            return;
         end if;
         Reader.X_Min := X_Min;
         Reader.Y_Min := Y_Min;
         Reader.Width := Width;
         Reader.Height := Height;
         Reader.Count := Count;
         if Count > 0
           and then Int64 (Count) < Int64 (Width) * Int64 (Height)
         then
            Reader.Total := Int64 (Width) * Int64 (Height);
         end if;
         Set_Success (Status);
      end;
   end Read_Header;

   procedure Next_Read_Chunk
     (Reader : access constant Ks_Region_Reader_Data;
      Limit  : Positive;
      Length : out Natural) is
   begin
      if not Valid_Reader (Reader) then
         Length := 0;
      else
         Length :=
           Natural (Int64'Min (Int64 (Limit), Reader.Total - Reader.Filled));
      end if;
   end Next_Read_Chunk;

   procedure Put_Read_Bytes
     (Reader : Ks_Region_Reader;
      Bytes  : Byte_Array;
      Status : out Ks_Status)
   is
      Capacity : Int64;
   begin
      if not Valid_Reader (Reader) then
         Bad (Status, "Pixel_Region'Read: the reader is inconsistent");
         return;
      elsif Int64 (Bytes'Length) > Reader.Total - Reader.Filled then
         Bad (Status, "Pixel_Region'Read: more pixel elements than the "
                      & "region has");
         return;
      elsif Bytes'Length = 0 then
         Set_Success (Status);
         return;
      end if;

      Capacity :=
        (if Reader.Buffer = null then 0
         else Int64 (Reader.Buffer'Last) + 1);
      if Reader.Filled + Int64 (Bytes'Length) > Capacity then
         --  Grow (never past Total) only when the elements read so far
         --  fill the buffer, so the memory follows the data present.
         declare
            Needed       : constant Int64 :=
              Reader.Filled + Int64 (Bytes'Length);
            New_Capacity : constant Int64 :=
              Int64'Min
                (Reader.Total,
                 Int64'Max
                   (Needed,
                    (if Capacity = 0 then Initial_Capacity
                     else 2 * Capacity)));
            Bigger       : Bool_Array_Access;
         begin
            Allocate_Buffer (Positive (New_Capacity), Bigger);
            if Bigger = null then
               Out_Of_Memory (Status, "Pixel_Region'Read");
               return;
            end if;
            if Reader.Filled > 0 then
               Bigger (0 .. Natural (Reader.Filled) - 1) :=
                 Reader.Buffer (0 .. Natural (Reader.Filled) - 1);
            end if;
            Free (Reader.Buffer);
            Reader.Buffer := Bigger;
         end;
      end if;

      for K in Bytes'Range loop
         pragma Loop_Invariant
           (Valid_Reader (Reader)
            and then Reader.Buffer /= null
            and then Reader.Filled
                       = Reader.Filled'Loop_Entry
                         + Int64 (K - Bytes'First)
            and then Reader.Filled'Loop_Entry + Int64 (Bytes'Length)
                       <= Int64 (Reader.Buffer'Last) + 1
            and then Reader.Filled'Loop_Entry + Int64 (Bytes'Length)
                       <= Reader.Total);
         case Bytes (K) is
            when 0 =>
               Reader.Buffer (Natural (Reader.Filled)) := False;
            when 1 =>
               Reader.Buffer (Natural (Reader.Filled)) := True;
            when others =>
               Malformed (Status, "a pixel element is neither 0 nor 1");
               return;
         end case;
         Reader.Filled := Reader.Filled + 1;
      end loop;
      Set_Success (Status);
   end Put_Read_Bytes;

   procedure Fill_From_Buffer
     (Buffer : Bool_Array;
      Flags  : in out Flag_Matrix)
   with
     Pre => Flags'First (1) <= Flags'Last (1)
            and then Flags'First (2) <= Flags'Last (2)
            and then Buffer'First = 0
            and then Int64 (Flags'Last (1)) - Int64 (Flags'First (1)) + 1
                       <= 2**31
            and then Int64 (Flags'Last (2)) - Int64 (Flags'First (2)) + 1
                       <= 2**31
            and then Int64 (Buffer'Last) + 1
                       = (Int64 (Flags'Last (1)) - Int64 (Flags'First (1))
                          + 1)
                         * (Int64 (Flags'Last (2)) - Int64 (Flags'First (2))
                            + 1);
   --  Flags, row after row, from Buffer.

   procedure Fill_From_Buffer
     (Buffer : Bool_Array;
      Flags  : in out Flag_Matrix)
   is
      Rows    : constant Int64 :=
        Int64 (Flags'Last (1)) - Int64 (Flags'First (1)) + 1;
      Columns : constant Int64 :=
        Int64 (Flags'Last (2)) - Int64 (Flags'First (2)) + 1;
      K       : Int64 := 0;
   begin
      for Y in Flags'Range (1) loop
         pragma Loop_Invariant
           (Big (K) = Big (Int64 (Y) - Int64 (Flags'First (1)))
                      * Big (Columns));
         Lemma_Mul_Le
           (Int64 (Y) - Int64 (Flags'First (1)), Rows - 1, Columns);
         for X in Flags'Range (2) loop
            Flags (Y, X) := Buffer (Natural (K));
            K := K + 1;
            pragma Loop_Invariant
              (Big (K) = Big (Int64 (Y) - Int64 (Flags'First (1)))
                         * Big (Columns)
                         + Big (Int64 (X) - Int64 (Flags'First (2))) + 1);
         end loop;
      end loop;
   end Fill_From_Buffer;

   procedure Destroy_Reader (Reader : in out Ks_Region_Reader) is
   begin
      if Reader /= null then
         Free (Reader.Buffer);
         Free (Reader);
      end if;
   end Destroy_Reader;

   procedure Finish_Read
     (Reader : in out Ks_Region_Reader;
      Region : out Ks_Pixel_Region;
      Status : out Ks_Status)
   is
      Flags  : Flag_Matrix_Access;
      Count  : Int64;
   begin
      Region := null;
      if not Valid_Reader (Reader) then
         Bad (Status, "Pixel_Region'Read: the reader is inconsistent");
         Destroy_Reader (Reader);
         return;
      elsif Reader.Filled /= Reader.Total then
         Bad (Status, "Pixel_Region'Read: pixel elements are missing");
         Destroy_Reader (Reader);
         return;
      elsif Reader.Count = 0 then
         --  The empty region.
         Destroy_Reader (Reader);
         Set_Success (Status);
         return;
      end if;

      Allocate_Region (Region);
      if Region = null then
         Destroy_Reader (Reader);
         Out_Of_Memory (Status, "Pixel_Region'Read");
         return;
      end if;
      Region.X_Min := Reader.X_Min;
      Region.Y_Min := Reader.Y_Min;
      Region.Width := Reader.Width;
      Region.Height := Reader.Height;
      Region.Count := Reader.Count;

      if Reader.Total > 0 then
         Allocate_Flags
           (Natural (Reader.Y_Min),
            Natural (Reader.Y_Min + (Reader.Height - 1)),
            Natural (Reader.X_Min),
            Natural (Reader.X_Min + (Reader.Width - 1)), Flags);
         if Flags = null then
            Release (Region);
            Destroy_Reader (Reader);
            Out_Of_Memory (Status, "Pixel_Region'Read");
            return;
         end if;
         Fill_From_Buffer (Reader.Buffer.all, Flags.all);
         Destroy_Reader (Reader);

         Count := Count_Flags (Flags.all);
         if Count /= Int64 (Region.Count) then
            Free (Flags);
            Release (Region);
            Malformed (Status, "the number of pixels in the region is not "
                               & "Pixel_Count");
            return;
         elsif not Smallest (Flags.all) then
            Free (Flags);
            Release (Region);
            Malformed (Status, "the bounding rectangle is not the smallest "
                               & "one around the pixels");
            return;
         end if;
         Region.Flags := Flags;
      else
         Destroy_Reader (Reader);
      end if;
      Set_Success (Status);
   end Finish_Read;

   procedure Stream_Ended (Status : out Ks_Status) is
   begin
      Malformed (Status, "the stream ends before the region is complete");
   end Stream_Ended;

end AMV.Kernels.Regions;
