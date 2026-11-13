pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Unchecked_Deallocation;

with AMV.Kernels.Filter_Inputs;
with AMV.Kernels.Image_Math;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Sobel_Edge with SPARK_Mode is

   pragma Unevaluated_Use_Of_Old (Allow);
   --  Postconditions and loop invariants compare sizes with their values
   --  on entry through the total ghost function KI.Size_Of (contracts are
   --  proved, never executed).

   package FI renames AMV.Kernels.Filter_Inputs;
   package KM renames AMV.Kernels.Image_Math;
   package N renames AMV.Kernels.Numerics;

   use type KI.Image_Size;
   use type KM.Ks_Real_Image;

   procedure Free is new Ada.Unchecked_Deallocation
     (KM.Real_Matrix, KM.Real_Pixels);
   procedure Free is new Ada.Unchecked_Deallocation
     (KM.Ks_Real_Image_Data, KM.Ks_Real_Image);

   type Position is record
      X, Y : Int32 := 0;
   end record;
   --  A pixel waiting in the hysteresis work stack.

   type Position_Array is array (Natural range <>) of Position;
   type Position_Array_Access is access Position_Array;

   procedure Free is new Ada.Unchecked_Deallocation
     (Position_Array, Position_Array_Access);

   type Offsets is array (0 .. 7) of Int64;

   DX : constant Offsets := [1, 1, 0, -1, -1, -1, 0, 1];
   DY : constant Offsets := [0, 1, 1, 1, 0, -1, -1, -1];
   --  The 8 neighbours in the order of the binary angle: sector K is the
   --  direction K * 45 degrees from +x towards +y.

   ---------------------------------------------------------------------
   --  Trusted helpers (SPARK_Mode Off bodies, listed in docs/PROOF.md)
   ---------------------------------------------------------------------

   procedure Allocate_Stack
     (Capacity : Positive;
      Stack    : out Position_Array_Access)
   with
     Global => null,
     Post   => (if Stack /= null
                then Stack'First = 0 and then Stack'Last = Capacity - 1);
   --  A new work stack of Capacity positions, or null when the memory
   --  cannot be allocated. Trusted: the allocator raises Storage_Error,
   --  which SPARK cannot express.

   procedure Allocate_Stack
     (Capacity : Positive;
      Stack    : out Position_Array_Access)
     with SPARK_Mode => Off
   is
   begin
      Stack := new Position_Array (0 .. Capacity - 1);
   exception
      when Storage_Error =>
         Stack := null;
   end Allocate_Stack;

   ---------------------------------------------------------------------
   --  Messages
   ---------------------------------------------------------------------

   procedure Bad
     (Status  : out Ks_Status;
      Message : String)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad
     (Status  : out Ks_Status;
      Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Out_Of_Memory (Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure = Failure_Out_Of_Memory;

   procedure Out_Of_Memory (Status : out Ks_Status) is
   begin
      Set_Failure (Status, Failure_Out_Of_Memory,
                   "SobelEdge: not enough memory for the images");
   end Out_Of_Memory;

   procedure Check_Params
     (Params : Ks_Sobel_Edge;
      Status : out Ks_Status)
   with Post => Valid (Status)
                and then Status.Failure in Failure_None | Failure_Bad_Parameter
                and then (if Succeeded (Status) then Valid_Params (Params));

   procedure Check_Params
     (Params : Ks_Sobel_Edge;
      Status : out Ks_Status) is
   begin
      if not (Params.Magnitude_Scale >= 0.0
              and then Params.Magnitude_Scale <= Max_Magnitude_Scale)
      then
         Bad (Status, "RunParams.MagnitudeScale must be in 0 .. 50");
      elsif Params.Post_Process_Mode
              not in Post_Process_None .. Post_Process_Hysteresis_Threshold
      then
         Bad (Status, "RunParams.PostProcessMode must be None (0), "
                      & "PeakDetect (1) or HysteresisThreshold (2)");
      elsif Params.Peak_Detect_Threshold not in 0 .. 255 then
         Bad (Status, "RunParams.PeakDetectThreshold must be in 0 .. 255");
      elsif Params.Hysteresis_Threshold_Low not in 0 .. 255 then
         Bad (Status,
              "RunParams.HysteresisThresholdLow must be in 0 .. 255");
      elsif Params.Hysteresis_Threshold_High not in 0 .. 255 then
         Bad (Status,
              "RunParams.HysteresisThresholdHigh must be in 0 .. 255");
      elsif Params.Hysteresis_Threshold_High
              < Params.Hysteresis_Threshold_Low
      then
         Bad (Status, "RunParams.HysteresisThresholdHigh must be >= "
                      & "HysteresisThresholdLow");
      elsif Params.Hysteresis_Survivor_Pel_Value not in 0 .. 255 then
         Bad (Status,
              "RunParams.HysteresisSurvivorPelValue must be in 0 .. 255");
      elsif Params.Hysteresis_Non_Survivor_Pel_Value not in 0 .. 255 then
         Bad (Status, "RunParams.HysteresisNonSurvivorPelValue must be in "
                      & "0 .. 255");
      else
         Set_Success (Status);
      end if;
   end Check_Params;

   procedure Run_Params_Default (Params : out Ks_Sobel_Edge) is
   begin
      Params := (others => <>);
   end Run_Params_Default;

   ---------------------------------------------------------------------
   --  Pixel values
   ---------------------------------------------------------------------

   Max_Derivative : constant := 127.5;
   --  The largest derivative ks_real_image_sobel gives for grey levels
   --  0 .. 255 (4 * 255 / 8). Reading through this clamp never changes a
   --  derivative of an 8-bit image.

   function To_Byte (V : Long_Float) return KI.Grey_8
   with Pre => V >= 0.0 and then V <= 1.0E6;
   --  V rounded to the nearest integer (halves away from zero), at most
   --  255.

   function To_Byte (V : Long_Float) return KI.Grey_8 is
   begin
      if V >= 255.0 then
         return 255;
      else
         return KI.Grey_8 (Integer (V));
      end if;
   end To_Byte;

   function Magnitude_Byte (Dx, Dy, Scale : Long_Float) return KI.Grey_8
   with Pre => Scale >= 0.0 and then Scale <= Max_Magnitude_Scale;
   --  The EdgeMagnitudeImage value for the derivatives Dx, Dy.

   function Magnitude_Byte (Dx, Dy, Scale : Long_Float) return KI.Grey_8
   is
      Gx : constant Long_Float := 2.0 * N.Clamp (Dx, Max_Derivative);
      Gy : constant Long_Float := 2.0 * N.Clamp (Dy, Max_Derivative);
      M  : constant Long_Float :=
        Long_Float'Min (N.Hypot (Gx, Gy), Max_Magnitude);
      S  : constant Long_Float :=
        Long_Float'Max
          (0.0, N.Mul_Within (M, Scale, Max_Magnitude, Max_Magnitude_Scale));
   begin
      return To_Byte (S);
   end Magnitude_Byte;

   function Code_Byte (Code : Long_Float) return KI.Grey_8
   with Pre => Code >= 0.0 and then Code <= 256.0;
   --  Code rounded to the nearest integer, modulo 256.

   function Code_Byte (Code : Long_Float) return KI.Grey_8 is
      K : constant Integer := Integer (Code);
   begin
      return KI.Grey_8 (K mod 256);
   end Code_Byte;

   function Angle_Byte (Dx, Dy : Long_Float) return KI.Grey_8
   with Post => (if N.Clamp (Dx, Max_Derivative) = 0.0
                   and then N.Clamp (Dy, Max_Derivative) = 0.0
                 then Angle_Byte'Result = 0);
   --  The EdgeAngleImage value (the binary angle of the gradient) for the
   --  derivatives Dx, Dy; 0 without gradient.

   function Angle_Byte (Dx, Dy : Long_Float) return KI.Grey_8 is
      Gx : constant Long_Float := N.Clamp (Dx, Max_Derivative);
      Gy : constant Long_Float := N.Clamp (Dy, Max_Derivative);
      Theta : Long_Float;
      Code  : Long_Float;
   begin
      if Gx = 0.0 and then Gy = 0.0 then
         return 0;
      end if;
      Theta := N.Direction (Gy, Gx);
      if Theta < 0.0 then
         Theta := Theta + N.Two_Pi;
      end if;
      Code := Theta * (256.0 / N.Two_Pi);
      return Code_Byte (Long_Float'Max (0.0, Long_Float'Min (Code, 256.0)));
   end Angle_Byte;

   function Neighbour
     (Image : access constant KI.Ks_Image_8_Grey_Data;
      X, Y  : Int64) return KI.Grey_8
   is
     (if X >= 0 and then Y >= 0
        and then X <= Int64 (Image.Width) - 1
        and then Y <= Int64 (Image.Height) - 1
      then Image.Pixels (Natural (Y), Natural (X))
      else 0)
   with Pre => KI.Valid_Image (Image);
   --  The pixel at (X, Y); 0 outside the image.

   function Peak_Value
     (Magnitude : access constant KI.Ks_Image_8_Grey_Data;
      Code      : KI.Grey_8;
      X, Y      : Natural;
      Threshold : Int32) return KI.Grey_8
   with
     Pre  => KI.Valid_Image (Magnitude)
             and then Y in Magnitude.Pixels'Range (1)
             and then X in Magnitude.Pixels'Range (2),
     Post => Peak_Value'Result = 0
             or else Peak_Value'Result = Magnitude.Pixels (Y, X);
   --  The PeakDetect value of pixel (X, Y) whose angle code is Code.

   function Peak_Value
     (Magnitude : access constant KI.Ks_Image_8_Grey_Data;
      Code      : KI.Grey_8;
      X, Y      : Natural;
      Threshold : Int32) return KI.Grey_8
   is
      M      : constant KI.Grey_8 := Magnitude.Pixels (Y, X);
      Sector : constant Natural := ((Natural (Code) + 16) / 32) mod 8;
      Ahead  : constant KI.Grey_8 :=
        Neighbour (Magnitude, Int64 (X) + DX (Sector),
                   Int64 (Y) + DY (Sector));
      Behind : constant KI.Grey_8 :=
        Neighbour (Magnitude, Int64 (X) - DX (Sector),
                   Int64 (Y) - DY (Sector));
   begin
      if Int32 (M) >= Threshold and then M >= Behind and then M > Ahead then
         return M;
      else
         return 0;
      end if;
   end Peak_Value;

   ---------------------------------------------------------------------
   --  Filling the images
   ---------------------------------------------------------------------

   function Gradient_Pair
     (Target : access constant KI.Ks_Image_8_Grey_Data;
      Gx, Gy : access constant KM.Ks_Real_Image_Data) return Boolean
   is
     (KI.Valid_Image (Target)
      and then KM.Valid_Image (Gx) and then KM.Valid_Image (Gy)
      and then Gx.Width = Target.Width and then Gx.Height = Target.Height
      and then Gy.Width = Target.Width and then Gy.Height = Target.Height);
   --  Gx and Gy have the size of Target.

   procedure Fill_Magnitude
     (Gx, Gy : access constant KM.Ks_Real_Image_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Scale  : Long_Float;
      Target : KI.Ks_Image_8_Grey)
   with
     Pre  => Gradient_Pair (Target, Gx, Gy)
             and then Scale >= 0.0 and then Scale <= Max_Magnitude_Scale,
     Post => KI.Valid_Image (Target)
             and then KI.Size_Of (Target) = KI.Size_Of (Target)'Old
             and then Zero_Outside (Region, Target);
   --  Writes EdgeMagnitudeImage into Target.

   procedure Fill_Magnitude
     (Gx, Gy : access constant KM.Ks_Real_Image_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Scale  : Long_Float;
      Target : KI.Ks_Image_8_Grey) is
   begin
      for Y in Target.Pixels'Range (1) loop
         for X in Target.Pixels'Range (2) loop
            if KR.Contains (Region, Int32 (X), Int32 (Y)) then
               Target.Pixels (Y, X) :=
                 Magnitude_Byte (Gx.Pixels (Y, X), Gy.Pixels (Y, X), Scale);
            else
               Target.Pixels (Y, X) := 0;
            end if;
            pragma Loop_Invariant
              (Gradient_Pair (Target, Gx, Gy)
               and then KI.Size_Of (Target) = KI.Size_Of (Target)'Loop_Entry);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Target.Pixels'Range (2)
                   => (if not KR.Contains (Region, Int32 (I), Int32 (J))
                       then Target.Pixels (J, I) = 0)));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => (if not KR.Contains (Region, Int32 (I), Int32 (Y))
                   then Target.Pixels (Y, I) = 0));
         end loop;
         pragma Loop_Invariant
           (Gradient_Pair (Target, Gx, Gy)
            and then KI.Size_Of (Target) = KI.Size_Of (Target)'Loop_Entry);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Target.Pixels'Range (2)
                => (if not KR.Contains (Region, Int32 (I), Int32 (J))
                    then Target.Pixels (J, I) = 0)));
      end loop;
   end Fill_Magnitude;

   procedure Fill_Angle
     (Gx, Gy : access constant KM.Ks_Real_Image_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Target : KI.Ks_Image_8_Grey)
   with
     Pre  => Gradient_Pair (Target, Gx, Gy),
     Post => KI.Valid_Image (Target)
             and then KI.Size_Of (Target) = KI.Size_Of (Target)'Old
             and then Zero_Outside (Region, Target);
   --  Writes EdgeAngleImage into Target.

   procedure Fill_Angle
     (Gx, Gy : access constant KM.Ks_Real_Image_Data;
      Region : access constant KR.Ks_Pixel_Region_Data;
      Target : KI.Ks_Image_8_Grey) is
   begin
      for Y in Target.Pixels'Range (1) loop
         for X in Target.Pixels'Range (2) loop
            if KR.Contains (Region, Int32 (X), Int32 (Y)) then
               Target.Pixels (Y, X) :=
                 Angle_Byte (Gx.Pixels (Y, X), Gy.Pixels (Y, X));
            else
               Target.Pixels (Y, X) := 0;
            end if;
            pragma Loop_Invariant
              (Gradient_Pair (Target, Gx, Gy)
               and then KI.Size_Of (Target) = KI.Size_Of (Target)'Loop_Entry);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Target.Pixels'Range (2)
                   => (if not KR.Contains (Region, Int32 (I), Int32 (J))
                       then Target.Pixels (J, I) = 0)));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => (if not KR.Contains (Region, Int32 (I), Int32 (Y))
                   then Target.Pixels (Y, I) = 0));
         end loop;
         pragma Loop_Invariant
           (Gradient_Pair (Target, Gx, Gy)
            and then KI.Size_Of (Target) = KI.Size_Of (Target)'Loop_Entry);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Target.Pixels'Range (2)
                => (if not KR.Contains (Region, Int32 (I), Int32 (J))
                    then Target.Pixels (J, I) = 0)));
      end loop;
   end Fill_Angle;

   function Same_Grid
     (Target           : access constant KI.Ks_Image_8_Grey_Data;
      Magnitude, Angle : access constant KI.Ks_Image_8_Grey_Data)
      return Boolean
   is
     (KI.Valid_Image (Target)
      and then KI.Valid_Image (Magnitude) and then KI.Valid_Image (Angle)
      and then Magnitude.Width = Target.Width
      and then Magnitude.Height = Target.Height
      and then Angle.Width = Target.Width
      and then Angle.Height = Target.Height);
   --  Magnitude and Angle have the size of Target.

   procedure Peak_Detect
     (Magnitude : access constant KI.Ks_Image_8_Grey_Data;
      Angle     : access constant KI.Ks_Image_8_Grey_Data;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Threshold : Int32;
      Target    : KI.Ks_Image_8_Grey)
   with
     Pre  => Same_Grid (Target, Magnitude, Angle),
     Post => KI.Valid_Image (Target)
             and then KI.Size_Of (Target) = KI.Size_Of (Target)'Old
             and then Zero_Outside (Region, Target)
             and then (for all Y in Target.Pixels'Range (1)
                       => (for all X in Target.Pixels'Range (2)
                           => Target.Pixels (Y, X) = 0
                              or else Target.Pixels (Y, X)
                                        = Magnitude.Pixels (Y, X)));
   --  Writes the PeakDetect FinalMagnitudeImage into Target.

   procedure Peak_Detect
     (Magnitude : access constant KI.Ks_Image_8_Grey_Data;
      Angle     : access constant KI.Ks_Image_8_Grey_Data;
      Region    : access constant KR.Ks_Pixel_Region_Data;
      Threshold : Int32;
      Target    : KI.Ks_Image_8_Grey) is
   begin
      for Y in Target.Pixels'Range (1) loop
         for X in Target.Pixels'Range (2) loop
            if KR.Contains (Region, Int32 (X), Int32 (Y)) then
               Target.Pixels (Y, X) :=
                 Peak_Value (Magnitude, Angle.Pixels (Y, X), X, Y,
                             Threshold);
            else
               Target.Pixels (Y, X) := 0;
            end if;
            pragma Loop_Invariant
              (Same_Grid (Target, Magnitude, Angle)
               and then KI.Size_Of (Target) = KI.Size_Of (Target)'Loop_Entry);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Target.Pixels'Range (2)
                   => (if not KR.Contains (Region, Int32 (I), Int32 (J))
                       then Target.Pixels (J, I) = 0)
                      and then (Target.Pixels (J, I) = 0
                                or else Target.Pixels (J, I)
                                          = Magnitude.Pixels (J, I))));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => (if not KR.Contains (Region, Int32 (I), Int32 (Y))
                   then Target.Pixels (Y, I) = 0)
                  and then (Target.Pixels (Y, I) = 0
                            or else Target.Pixels (Y, I)
                                      = Magnitude.Pixels (Y, I)));
         end loop;
         pragma Loop_Invariant
           (Same_Grid (Target, Magnitude, Angle)
            and then KI.Size_Of (Target) = KI.Size_Of (Target)'Loop_Entry);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Target.Pixels'Range (2)
                => (if not KR.Contains (Region, Int32 (I), Int32 (J))
                    then Target.Pixels (J, I) = 0)
                   and then (Target.Pixels (J, I) = 0
                             or else Target.Pixels (J, I)
                                       = Magnitude.Pixels (J, I))));
      end loop;
   end Peak_Detect;

   function Two_Valued
     (Target                 : access constant KI.Ks_Image_8_Grey_Data;
      Region                 : access constant KR.Ks_Pixel_Region_Data;
      Survivor, Non_Survivor : KI.Grey_8) return Boolean
   is
     (for all Y in Target.Pixels'Range (1)
      => (for all X in Target.Pixels'Range (2)
          => (if KR.Contains (Region, Int32 (X), Int32 (Y))
              then Target.Pixels (Y, X) = Survivor
                   or else Target.Pixels (Y, X) = Non_Survivor
              else Target.Pixels (Y, X) = 0)))
   with Ghost, Pre => KI.Valid_Image (Target);
   --  Every pixel of the region holds one of the two values, every other
   --  pixel 0.

   procedure Visit
     (Magnitude              : access constant KI.Ks_Image_8_Grey_Data;
      Region                 : access constant KR.Ks_Pixel_Region_Data;
      Low                    : Int32;
      Survivor, Non_Survivor : KI.Grey_8;
      Target                 : KI.Ks_Image_8_Grey;
      NX, NY                 : Int64;
      Stack                  : in out Position_Array;
      Top                    : in out Natural)
   with
     Pre  => KI.Valid_Image (Target) and then KI.Valid_Image (Magnitude)
             and then Magnitude.Width = Target.Width
             and then Magnitude.Height = Target.Height
             and then Stack'First = 0 and then Stack'Last < Natural'Last
             and then Top <= Stack'Last + 1,
     Post => KI.Valid_Image (Target)
             and then KI.Size_Of (Target) = KI.Size_Of (Target)'Old
             and then Top <= Stack'Last + 1
             and then
               (if Two_Valued (Target, Region, Survivor, Non_Survivor)'Old
                then Two_Valued (Target, Region, Survivor, Non_Survivor));
   --  One step of the flood fill: the pixel (NX, NY), when it lies in the
   --  image and the region, has a magnitude >= Low and is not a survivor
   --  yet, becomes one and is pushed onto Stack (Top is the number of
   --  positions on it).

   procedure Visit
     (Magnitude              : access constant KI.Ks_Image_8_Grey_Data;
      Region                 : access constant KR.Ks_Pixel_Region_Data;
      Low                    : Int32;
      Survivor, Non_Survivor : KI.Grey_8;
      Target                 : KI.Ks_Image_8_Grey;
      NX, NY                 : Int64;
      Stack                  : in out Position_Array;
      Top                    : in out Natural)
   is
      pragma Unreferenced (Non_Survivor);
      --  Only the postcondition refers to it.
   begin
      if NX >= 0 and then NY >= 0
        and then NX < Int64 (Target.Width)
        and then NY < Int64 (Target.Height)
      then
         declare
            I : constant Natural := Natural (NX);
            J : constant Natural := Natural (NY);
         begin
            if KR.Contains (Region, Int32 (I), Int32 (J))
              and then Int32 (Magnitude.Pixels (J, I)) >= Low
              and then Target.Pixels (J, I) /= Survivor
            then
               Target.Pixels (J, I) := Survivor;
               if Top <= Stack'Last then
                  Stack (Top) := (X => Int32 (I), Y => Int32 (J));
                  Top := Top + 1;
               end if;
            end if;
         end;
      end if;
   end Visit;

   procedure Hysteresis
     (Magnitude              : access constant KI.Ks_Image_8_Grey_Data;
      Region                 : access constant KR.Ks_Pixel_Region_Data;
      Low, High              : Int32;
      Survivor, Non_Survivor : KI.Grey_8;
      Target                 : KI.Ks_Image_8_Grey;
      Done                   : out Boolean)
   with
     Pre  => KI.Valid_Image (Target) and then KI.Valid_Image (Magnitude)
             and then Magnitude.Width = Target.Width
             and then Magnitude.Height = Target.Height
             and then Int64 (Target.Width) * Int64 (Target.Height)
                        <= KI.Max_Pixels,
     Post => KI.Valid_Image (Target)
             and then KI.Size_Of (Target) = KI.Size_Of (Target)'Old
             and then Two_Valued (Target, Region, Survivor, Non_Survivor);
   --  Writes the HysteresisThreshold FinalMagnitudeImage into Target.
   --  Done is False when the work stack cannot be allocated (Target then
   --  holds Non_Survivor in the region and 0 elsewhere).

   procedure Hysteresis
     (Magnitude              : access constant KI.Ks_Image_8_Grey_Data;
      Region                 : access constant KR.Ks_Pixel_Region_Data;
      Low, High              : Int32;
      Survivor, Non_Survivor : KI.Grey_8;
      Target                 : KI.Ks_Image_8_Grey;
      Done                   : out Boolean)
   is
      W     : constant Int64 := Int64 (Target.Width);
      H     : constant Int64 := Int64 (Target.Height);
      Stack : Position_Array_Access;
      Top   : Natural;
   begin
      --  Every pixel of the region starts as a non-survivor.
      for Y in Target.Pixels'Range (1) loop
         for X in Target.Pixels'Range (2) loop
            if KR.Contains (Region, Int32 (X), Int32 (Y)) then
               Target.Pixels (Y, X) := Non_Survivor;
            else
               Target.Pixels (Y, X) := 0;
            end if;
            pragma Loop_Invariant
              (KI.Valid_Image (Target)
               and then KI.Size_Of (Target) = KI.Size_Of (Target)'Loop_Entry);
            pragma Loop_Invariant
              (for all J in 0 .. Y - 1
               => (for all I in Target.Pixels'Range (2)
                   => (if KR.Contains (Region, Int32 (I), Int32 (J))
                       then Target.Pixels (J, I) = Non_Survivor
                       else Target.Pixels (J, I) = 0)));
            pragma Loop_Invariant
              (for all I in 0 .. X
               => (if KR.Contains (Region, Int32 (I), Int32 (Y))
                   then Target.Pixels (Y, I) = Non_Survivor
                   else Target.Pixels (Y, I) = 0));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Target)
            and then KI.Size_Of (Target) = KI.Size_Of (Target)'Loop_Entry);
         pragma Loop_Invariant
           (for all J in 0 .. Y
            => (for all I in Target.Pixels'Range (2)
                => (if KR.Contains (Region, Int32 (I), Int32 (J))
                    then Target.Pixels (J, I) = Non_Survivor
                    else Target.Pixels (J, I) = 0)));
      end loop;
      Done := True;
      if Survivor = Non_Survivor then
         --  Every pixel of the region has the one value already.
         return;
      end if;

      --  A pixel is marked once it holds Survivor (which differs from
      --  Non_Survivor), so each pixel enters the stack at most once and
      --  W * H entries always suffice; the test before a push never fails.
      Allocate_Stack (Positive (W * H), Stack);
      if Stack = null then
         Done := False;
         return;
      end if;
      for Y in Target.Pixels'Range (1) loop
         for X in Target.Pixels'Range (2) loop
            if KR.Contains (Region, Int32 (X), Int32 (Y))
              and then Int32 (Magnitude.Pixels (Y, X)) >= High
              and then Target.Pixels (Y, X) /= Survivor
            then
               --  A new seed: mark it and every pixel connected to it.
               Target.Pixels (Y, X) := Survivor;
               Stack (0) := (X => Int32 (X), Y => Int32 (Y));
               Top := 1;
               while Top > 0 loop
                  Top := Top - 1;
                  declare
                     PX : constant Int64 := Int64 (Stack (Top).X);
                     PY : constant Int64 := Int64 (Stack (Top).Y);
                  begin
                     for K in Offsets'Range loop
                        Visit (Magnitude, Region, Low, Survivor, Non_Survivor,
                               Target, PX + DX (K), PY + DY (K), Stack.all,
                               Top);
                        pragma Loop_Invariant
                          (KI.Valid_Image (Target)
                           and then KI.Size_Of (Target)
                                      = KI.Size_Of (Target)'Loop_Entry);
                        pragma Loop_Invariant
                          (Stack /= null and then Stack'First = 0
                           and then Stack'Last < Natural'Last
                           and then Top <= Stack'Last + 1);
                        pragma Loop_Invariant
                          (Two_Valued
                             (Target, Region, Survivor, Non_Survivor));
                     end loop;
                  end;
                  pragma Loop_Invariant
                    (KI.Valid_Image (Target)
                     and then KI.Size_Of (Target)
                                = KI.Size_Of (Target)'Loop_Entry);
                  pragma Loop_Invariant
                    (Stack /= null and then Stack'First = 0
                     and then Stack'Last < Natural'Last
                     and then Top <= Stack'Last + 1);
                  pragma Loop_Invariant
                    (Two_Valued (Target, Region, Survivor, Non_Survivor));
               end loop;
            end if;
            pragma Loop_Invariant
              (KI.Valid_Image (Target)
               and then KI.Size_Of (Target) = KI.Size_Of (Target)'Loop_Entry
               and then Stack /= null
               and then Stack'First = 0
               and then Stack'Last < Natural'Last
               and then Two_Valued (Target, Region, Survivor, Non_Survivor));
         end loop;
         pragma Loop_Invariant
           (KI.Valid_Image (Target)
            and then KI.Size_Of (Target) = KI.Size_Of (Target)'Loop_Entry
            and then Stack /= null
            and then Stack'First = 0
            and then Stack'Last < Natural'Last
            and then Two_Valued (Target, Region, Survivor, Non_Survivor));
      end loop;
      Free (Stack);
   end Hysteresis;

   ---------------------------------------------------------------------
   --  Entry point
   ---------------------------------------------------------------------

   procedure Release (Image : in out KI.Ks_Image_8_Grey)
   with Post => Image = null;
   --  Frees Image (if any).

   procedure Release (Image : in out KI.Ks_Image_8_Grey) is
      Ignored : Ks_Status;
   begin
      KI.Destroy (Image, Ignored);
   end Release;

   procedure Execute
     (Image                 : access constant KI.Ks_Image_8_Grey_Data;
      Region                : access constant KR.Ks_Pixel_Region_Data;
      Params                : Ks_Sobel_Edge;
      Edge_Magnitude_Image  : out KI.Ks_Image_8_Grey;
      Edge_Angle_Image      : out KI.Ks_Image_8_Grey;
      Final_Magnitude_Image : out KI.Ks_Image_8_Grey;
      Status                : out Ks_Status)
   is
      Real, Gx, Gy : KM.Ks_Real_Image;
      Done         : Boolean := True;
   begin
      Edge_Magnitude_Image := null;
      Edge_Angle_Image := null;
      Final_Magnitude_Image := null;
      FI.Check_Input (Image, Region, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Check_Params (Params, Status);
      if not Succeeded (Status) then
         return;
      end if;

      --  The derivatives of the whole image.
      KM.From_Grey_8 (Image, Real, Status);
      if not Succeeded (Status) then
         Out_Of_Memory (Status);
         return;
      end if;
      KM.Sobel (Real, Gx, Gy, Status);
      Free (Real.Pixels);
      Free (Real);
      if not Succeeded (Status) then
         Out_Of_Memory (Status);
         return;
      end if;

      --  The magnitude and angle images.
      KI.Create (Image.Width, Image.Height, 0, Edge_Magnitude_Image, Status);
      if Succeeded (Status) then
         KI.Create (Image.Width, Image.Height, 0, Edge_Angle_Image, Status);
      end if;
      if not Succeeded (Status) then
         Free (Gx.Pixels);
         Free (Gx);
         Free (Gy.Pixels);
         Free (Gy);
         Release (Edge_Magnitude_Image);
         Out_Of_Memory (Status);
         return;
      end if;
      Fill_Magnitude
        (Gx, Gy, Region, Params.Magnitude_Scale, Edge_Magnitude_Image);
      Fill_Angle (Gx, Gy, Region, Edge_Angle_Image);
      Free (Gx.Pixels);
      Free (Gx);
      Free (Gy.Pixels);
      Free (Gy);

      --  The final image.
      if Params.Post_Process_Mode = Post_Process_None then
         KI.Duplicate (Edge_Magnitude_Image, Final_Magnitude_Image, Status);
      else
         KI.Create (Image.Width, Image.Height, 0, Final_Magnitude_Image,
                    Status);
         if Succeeded (Status) then
            if Params.Post_Process_Mode = Post_Process_Peak_Detect then
               Peak_Detect
                 (Edge_Magnitude_Image, Edge_Angle_Image, Region,
                  Params.Peak_Detect_Threshold, Final_Magnitude_Image);
            else
               Hysteresis
                 (Edge_Magnitude_Image, Region,
                  Params.Hysteresis_Threshold_Low,
                  Params.Hysteresis_Threshold_High,
                  KI.Grey_8 (Params.Hysteresis_Survivor_Pel_Value),
                  KI.Grey_8 (Params.Hysteresis_Non_Survivor_Pel_Value),
                  Final_Magnitude_Image, Done);
            end if;
         end if;
      end if;
      if not Succeeded (Status) or else not Done then
         Release (Edge_Magnitude_Image);
         Release (Edge_Angle_Image);
         Release (Final_Magnitude_Image);
         Out_Of_Memory (Status);
         return;
      end if;
      Set_Success (Status);
   end Execute;

   procedure Check_Input_Image
     (Image  : access constant KI.Ks_Image_8_Grey_Data;
      Status : out Ks_Status) is
   begin
      FI.Check_Image (Image, Status);
   end Check_Input_Image;

   procedure Check_Run_Params
     (Params : Ks_Sobel_Edge;
      Status : out Ks_Status) is
   begin
      Check_Params (Params, Status);
   end Check_Run_Params;

end AMV.Kernels.Sobel_Edge;
