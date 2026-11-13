pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics.Long_Elementary_Functions;

with AMV.Kernels.Dimensioning.Ellipses;
with AMV.Kernels.Dimensioning.Planar;
with AMV.Kernels.Geometry;
with AMV.Kernels.Numerics;

package body AMV.Kernels.Dimensioning with SPARK_Mode is

   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package EL renames AMV.Kernels.Dimensioning.Ellipses;
   package KG renames AMV.Kernels.Geometry;
   package N renames AMV.Kernels.Numerics;
   package P renames AMV.Kernels.Dimensioning.Planar;

   ---------------------------------------------------------------------
   --  Failures
   ---------------------------------------------------------------------

   procedure Bad
     (Status  : out Ks_Status;
      Message : String)
   with Post => Valid (Status) and then Status.Failure = Failure_Bad_Parameter;

   procedure Bad
     (Status  : out Ks_Status;
      Message : String) is
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
   end Bad;

   procedure Out_Of_Bound
     (Tool   : String;
      Status : out Ks_Status)
   with Pre  => Tool'First = 1 and then Tool'Length <= 40,
        Post => Valid (Status)
                and then Status.Failure = Failure_Bad_Parameter;
   --  "<Tool>: the result would exceed +/-1.0E150".

   procedure Out_Of_Bound
     (Tool   : String;
      Status : out Ks_Status) is
   begin
      Bad (Status, Tool & ": the result would exceed +/-1.0E150");
   end Out_Of_Bound;

   function Code (Flag : Boolean) return Int32 is
     (if Flag then True_Value else False_Value);

   ---------------------------------------------------------------------
   --  Inputs: checks and mapping into the measuring space
   ---------------------------------------------------------------------

   --  Each helper does nothing when Status is already a failure; otherwise
   --  it checks (and maps) its input, and sets Status to the failure that
   --  names the property when the input is not acceptable.

   function Kept_Or (Old_Status, New_Status : Ks_Status; Code : Int32)
      return Boolean
   is (New_Status.Failure = Old_Status.Failure
       or else New_Status.Failure = Code)
   with Ghost;

   procedure Get_Point
     (X, Y           : Long_Float;
      Name_X, Name_Y : String;
      Q              : out P.Point;
      Status         : in out Ks_Status)
   with Pre  => Valid (Status)
                and then Name_X'First = 1 and then Name_X'Length <= 40
                and then Name_Y'First = 1 and then Name_Y'Length <= 40,
        Post => Valid (Status)
                and then Kept_Or (Status'Old, Status, Failure_Bad_Parameter)
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old));

   procedure Get_Point
     (X, Y           : Long_Float;
      Name_X, Name_Y : String;
      Q              : out P.Point;
      Status         : in out Ks_Status) is
   begin
      Q := P.Origin;
      if not Succeeded (Status) then
         return;
      elsif not Bounded (X) then
         Bad (Status, Name_X & " must be finite and within +/-1.0E150");
      elsif not Bounded (Y) then
         Bad (Status, Name_Y & " must be finite and within +/-1.0E150");
      else
         Q := (X, Y);
      end if;
   end Get_Point;

   procedure Check_Transform
     (Transform : KT.Ks_Transform_2D_Linear;
      Name      : String;
      Status    : in out Ks_Status)
   with Pre  => Valid (Status)
                and then Name'First = 1 and then Name'Length <= 40,
        Post => Valid (Status)
                and then Kept_Or (Status'Old, Status, Failure_Bad_Parameter)
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old)
                               and then KT.Bounded (Transform));

   procedure Check_Transform
     (Transform : KT.Ks_Transform_2D_Linear;
      Name      : String;
      Status    : in out Ks_Status) is
   begin
      if Succeeded (Status) and then not KT.Bounded (Transform) then
         Bad (Status, "the transform of " & Name
                      & " must be finite and within +/-1.0E150");
      end if;
   end Check_Transform;

   procedure Get_Line
     (Line      : KS.Ks_Line;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : String;
      L         : out P.Line;
      Status    : in out Ks_Status)
   with Pre  => Valid (Status)
                and then Name'First = 1 and then Name'Length <= 40,
        Post => Valid (Status)
                and then (Kept_Or (Status'Old, Status, Failure_Bad_Parameter)
                          or else Status.Failure
                                    = Failure_Transform_Singular)
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old));
   --  The line mapped into the measuring space.

   procedure Get_Line
     (Line      : KS.Ks_Line;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : String;
      L         : out P.Line;
      Status    : in out Ks_Status)
   is
      Mapped : KS.Ks_Line;
      S      : Ks_Status;
   begin
      L := (P => P.Origin, C => 1.0, S => 0.0, Rotation => 0.0);
      if not Succeeded (Status) then
         return;
      elsif not KS.Valid_Line (Line) then
         Bad (Status, Name & " must be finite and within +/-1.0E150");
         return;
      end if;
      Check_Transform (Transform, Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Map (Line, Transform, Mapped, S);
      if S.Failure = Failure_Transform_Singular then
         Set_Failure (Status, Failure_Transform_Singular,
                      "the transform of " & Name & " is singular");
      elsif not Succeeded (S) then
         Bad (Status, Name & ": in the measuring space it would exceed"
                      & " +/-1.0E150");
      else
         L := (P        => (Mapped.X, Mapped.Y),
               C        => EF.Cos (Mapped.Rotation),
               S        => EF.Sin (Mapped.Rotation),
               Rotation => Mapped.Rotation);
      end if;
   end Get_Line;

   procedure Get_Segment
     (Segment   : KS.Ks_Line_Segment;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : String;
      S         : out P.Segment;
      Status    : in out Ks_Status)
   with Pre  => Valid (Status)
                and then Name'First = 1 and then Name'Length <= 40,
        Post => Valid (Status)
                and then Kept_Or (Status'Old, Status, Failure_Bad_Parameter)
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old));
   --  The segment mapped into the measuring space.

   procedure Get_Segment
     (Segment   : KS.Ks_Line_Segment;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : String;
      S         : out P.Segment;
      Status    : in out Ks_Status)
   is
      Mapped : KS.Ks_Line_Segment;
      Map_S  : Ks_Status;
   begin
      S := (A => P.Origin, B => P.Origin);
      if not Succeeded (Status) then
         return;
      elsif not KS.Valid_Line_Segment (Segment) then
         Bad (Status, Name & " must be finite and within +/-1.0E150");
         return;
      end if;
      Check_Transform (Transform, Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Map (Segment, Transform, Mapped, Map_S);
      if not Succeeded (Map_S) then
         Bad (Status, Name & ": in the measuring space it would exceed"
                      & " +/-1.0E150");
      else
         S := (A => (Mapped.Start_X, Mapped.Start_Y),
               B => (Mapped.End_X, Mapped.End_Y));
      end if;
   end Get_Segment;

   procedure Get_Circle
     (Circle    : KS.Ks_Circle;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : String;
      C         : out P.Circle;
      Status    : in out Ks_Status)
   with Pre  => Valid (Status)
                and then Name'First = 1 and then Name'Length <= 40,
        Post => Valid (Status)
                and then Kept_Or (Status'Old, Status, Failure_Bad_Parameter)
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old));
   --  The circle mapped into the measuring space; its transform must keep
   --  it a circle, and its radius there must be within Max_Value.

   procedure Get_Circle
     (Circle    : KS.Ks_Circle;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : String;
      C         : out P.Circle;
      Status    : in out Ks_Status)
   is
      Kind           : Int32;
      Mapped         : KS.Ks_Circle;
      Unused_Ellipse : KS.Ks_Ellipse;
      Map_S          : Ks_Status;
   begin
      C := (Center => P.Origin, Radius => 0.0);
      if not Succeeded (Status) then
         return;
      elsif not KS.Valid_Circle (Circle) then
         Bad (Status, Name & " must be finite and within +/-1.0E150"
                      & " (radius >= 0)");
         return;
      end if;
      Check_Transform (Transform, Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Map (Circle, Transform, Kind, Mapped, Unused_Ellipse, Map_S);
      if not Succeeded (Map_S) then
         Bad (Status, Name & ": in the measuring space it would exceed"
                      & " +/-1.0E150");
      elsif Kind /= KS.Shape_Circle then
         Bad (Status, Name & ": its transform to the measuring space is"
                      & " not a similarity (the circle would become an"
                      & " ellipse)");
      elsif Mapped.Radius > Max_Value then
         Bad (Status, Name & ".Radius must be within 1.0E150 in the"
                      & " measuring space");
      else
         C := (Center => (Mapped.Center_X, Mapped.Center_Y),
               Radius => Mapped.Radius);
      end if;
   end Get_Circle;

   procedure Get_Ellipse
     (Ellipse   : KS.Ks_Ellipse;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : String;
      E         : out EL.Ellipse;
      Status    : in out Ks_Status)
   with Pre  => Valid (Status)
                and then Name'First = 1 and then Name'Length <= 40,
        Post => Valid (Status)
                and then Kept_Or (Status'Old, Status, Failure_Bad_Parameter)
                and then (if Succeeded (Status)
                          then Succeeded (Status'Old)
                               and then EL.Valid_Ellipse (E));
   --  The ellipse mapped into the measuring space; both radii must be > 0
   --  and within Max_Value there.

   procedure Get_Ellipse
     (Ellipse   : KS.Ks_Ellipse;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : String;
      E         : out EL.Ellipse;
      Status    : in out Ks_Status)
   is
      Mapped : KS.Ks_Ellipse;
      Map_S  : Ks_Status;
   begin
      E := (Center => P.Origin, Radius_X => 1.0, Radius_Y => 1.0,
            C => 1.0, S => 0.0);
      if not Succeeded (Status) then
         return;
      elsif not KS.Valid_Ellipse (Ellipse) then
         Bad (Status, Name & " must be finite and within +/-1.0E150"
                      & " (radii >= 0)");
         return;
      elsif Ellipse.Radius_X = 0.0 or else Ellipse.Radius_Y = 0.0 then
         Bad (Status, Name & ".RadiusX and " & Name
                      & ".RadiusY must be > 0");
         return;
      end if;
      Check_Transform (Transform, Name, Status);
      if not Succeeded (Status) then
         return;
      end if;
      KS.Map (Ellipse, Transform, Mapped, Map_S);
      if not Succeeded (Map_S) then
         Bad (Status, Name & ": in the measuring space it would exceed"
                      & " +/-1.0E150");
      elsif Mapped.Radius_X > Max_Value or else Mapped.Radius_Y > Max_Value
      then
         Bad (Status, Name & ": its radii must be within 1.0E150 in the"
                      & " measuring space");
      elsif Mapped.Radius_X = 0.0 or else Mapped.Radius_Y = 0.0 then
         Bad (Status, Name & ": a radius becomes 0 in the measuring"
                      & " space");
      else
         E := (Center   => (Mapped.Center_X, Mapped.Center_Y),
               Radius_X => Mapped.Radius_X,
               Radius_Y => Mapped.Radius_Y,
               C        => EF.Cos (Mapped.Rotation),
               S        => EF.Sin (Mapped.Rotation));
      end if;
   end Get_Ellipse;

   function Angle_From (A, B : P.Line) return Long_Float
   with Post => Valid_Angle (Angle_From'Result);
   --  B.Rotation - A.Rotation reduced to (-Pi, Pi].

   function Angle_From (A, B : P.Line) return Long_Float is
     (N.Reduce_Two_Pi (B.Rotation - A.Rotation));

   ---------------------------------------------------------------------
   --  Points and angles
   ---------------------------------------------------------------------

   procedure Distance_Point_Point
     (Start_X, Start_Y, End_X, End_Y : Long_Float;
      Result                         : out Ks_Distance_Point_Point_Result;
      Status                         : out Ks_Status)
   is
      A, B : P.Point;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Point (Start_X, Start_Y, "StartX", "StartY", A, Status);
      Get_Point (End_X, End_Y, "EndX", "EndY", B, Status);
      if Succeeded (Status) then
         Result := (Distance => P.Distance (A, B),
                    Angle    => P.Direction_Of (A, B));
      end if;
   end Distance_Point_Point;

   procedure Angle_Point_Point
     (Start_X, Start_Y, End_X, End_Y : Long_Float;
      Angle                          : out Long_Float;
      Status                         : out Ks_Status)
   is
      A, B : P.Point;
   begin
      Angle := 0.0;
      Set_Success (Status);
      Get_Point (Start_X, Start_Y, "StartX", "StartY", A, Status);
      Get_Point (End_X, End_Y, "EndX", "EndY", B, Status);
      if Succeeded (Status) then
         Angle := P.Direction_Of (A, B);
      end if;
   end Angle_Point_Point;

   procedure Angle_Line_Line
     (Line_A, Line_B       : KS.Ks_Line;
      Selected_From_Line_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Line_B : KT.Ks_Transform_2D_Linear;
      Angle                : out Long_Float;
      Status               : out Ks_Status)
   is
      A, B : P.Line;
   begin
      Angle := 0.0;
      Set_Success (Status);
      Get_Line (Line_A, Selected_From_Line_A, "LineA", A, Status);
      Get_Line (Line_B, Selected_From_Line_B, "LineB", B, Status);
      if Succeeded (Status) then
         Angle := Angle_From (A, B);
      end if;
   end Angle_Line_Line;

   ---------------------------------------------------------------------
   --  Distances
   ---------------------------------------------------------------------

   procedure Distance_Point_Line
     (X, Y               : Long_Float;
      Line               : KS.Ks_Line;
      Selected_From_Line : KT.Ks_Transform_2D_Linear;
      Result             : out Ks_Distance_Point_Line_Result;
      Status             : out Ks_Status)
   is
      Q, F : P.Point;
      L    : P.Line;
      Fits : Boolean;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Point (X, Y, "X", "Y", Q, Status);
      Get_Line (Line, Selected_From_Line, "Line", L, Status);
      if not Succeeded (Status) then
         return;
      end if;
      P.Foot (Q, L, F, Fits);
      if not Fits then
         Out_Of_Bound ("DistancePointLine", Status);
         return;
      end if;
      Result := (Distance => abs P.Offset (Q, L),
                 Line_X   => F.X,
                 Line_Y   => F.Y);
   end Distance_Point_Line;

   procedure Distance_Point_Segment
     (X, Y                  : Long_Float;
      Segment               : KS.Ks_Line_Segment;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Distance_Point_Segment_Result;
      Status                : out Ks_Status)
   is
      Q, C : P.Point;
      S    : P.Segment;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Point (X, Y, "X", "Y", Q, Status);
      Get_Segment (Segment, Selected_From_Segment, "Segment", S, Status);
      if not Succeeded (Status) then
         return;
      end if;
      P.Closest_On_Segment (Q, S, C);
      Result := (Distance  => P.Distance (Q, C),
                 Segment_X => C.X,
                 Segment_Y => C.Y);
   end Distance_Point_Segment;

   procedure Distance_Point_Circle
     (X, Y                 : Long_Float;
      Input_Circle         : KS.Ks_Circle;
      Selected_From_Circle : KT.Ks_Transform_2D_Linear;
      Result               : out Ks_Distance_Point_Circle_Result;
      Status               : out Ks_Status)
   is
      Q, Near : P.Point;
      C       : P.Circle;
      D       : P.Signed_Length;
      Fits    : Boolean;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Point (X, Y, "X", "Y", Q, Status);
      Get_Circle (Input_Circle, Selected_From_Circle, "InputCircle", C,
                  Status);
      if not Succeeded (Status) then
         return;
      end if;
      P.Point_Circle (Q, C, D, Near, Fits);
      if not Fits then
         Out_Of_Bound ("DistancePointCircle", Status);
         return;
      end if;
      Result := (Distance => D, Circle_X => Near.X, Circle_Y => Near.Y);
   end Distance_Point_Circle;

   procedure Distance_Point_Ellipse
     (X, Y                  : Long_Float;
      Ellipse               : KS.Ks_Ellipse;
      Selected_From_Ellipse : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Distance_Point_Ellipse_Result;
      Status                : out Ks_Status)
   is
      Q, Near : P.Point;
      E       : EL.Ellipse;
      D       : P.Signed_Length;
      Fits    : Boolean;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Point (X, Y, "X", "Y", Q, Status);
      Get_Ellipse (Ellipse, Selected_From_Ellipse, "Ellipse", E, Status);
      if not Succeeded (Status) then
         return;
      end if;
      EL.Point_Ellipse (Q, E, D, Near, Fits);
      if not Fits then
         Out_Of_Bound ("DistancePointEllipse", Status);
         return;
      end if;
      Result := (Distance => D, Ellipse_X => Near.X, Ellipse_Y => Near.Y);
   end Distance_Point_Ellipse;

   procedure Distance_Segment_Segment
     (Segment_A, Segment_B    : KS.Ks_Line_Segment;
      Selected_From_Segment_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Segment_B : KT.Ks_Transform_2D_Linear;
      Result                  : out Ks_Distance_Segment_Segment_Result;
      Status                  : out Ks_Status)
   is
      A, B   : P.Segment;
      D      : P.Length;
      QA, QB : P.Point;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Segment (Segment_A, Selected_From_Segment_A, "SegmentA", A,
                   Status);
      Get_Segment (Segment_B, Selected_From_Segment_B, "SegmentB", B,
                   Status);
      if not Succeeded (Status) then
         return;
      end if;
      P.Segment_Segment (A, B, D, QA, QB);
      Result := (Distance    => D,
                 Segment_A_X => QA.X,
                 Segment_A_Y => QA.Y,
                 Segment_B_X => QB.X,
                 Segment_B_Y => QB.Y);
   end Distance_Segment_Segment;

   procedure Distance_Segment_Line
     (Segment               : KS.Ks_Line_Segment;
      Line                  : KS.Ks_Line;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Selected_From_Line    : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Distance_Segment_Line_Result;
      Status                : out Ks_Status)
   is
      S      : P.Segment;
      L      : P.Line;
      D      : P.Length;
      QS, QL : P.Point;
      Fits   : Boolean;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Segment (Segment, Selected_From_Segment, "Segment", S, Status);
      Get_Line (Line, Selected_From_Line, "Line", L, Status);
      if not Succeeded (Status) then
         return;
      end if;
      P.Segment_Line (S, L, D, QS, QL, Fits);
      if not Fits then
         Out_Of_Bound ("DistanceSegmentLine", Status);
         return;
      end if;
      Result := (Distance  => D,
                 Segment_X => QS.X,
                 Segment_Y => QS.Y,
                 Line_X    => QL.X,
                 Line_Y    => QL.Y);
   end Distance_Segment_Line;

   procedure Distance_Line_Circle
     (Line                 : KS.Ks_Line;
      Input_Circle         : KS.Ks_Circle;
      Selected_From_Line   : KT.Ks_Transform_2D_Linear;
      Selected_From_Circle : KT.Ks_Transform_2D_Linear;
      Result               : out Ks_Distance_Line_Circle_Result;
      Status               : out Ks_Status)
   is
      L      : P.Line;
      C      : P.Circle;
      D      : P.Length;
      QL, QC : P.Point;
      Fits   : Boolean;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Line (Line, Selected_From_Line, "Line", L, Status);
      Get_Circle (Input_Circle, Selected_From_Circle, "InputCircle", C,
                  Status);
      if not Succeeded (Status) then
         return;
      end if;
      P.Line_Circle (L, C, D, QL, QC, Fits);
      if not Fits then
         Out_Of_Bound ("DistanceLineCircle", Status);
         return;
      end if;
      Result := (Distance => D,
                 Line_X   => QL.X,
                 Line_Y   => QL.Y,
                 Circle_X => QC.X,
                 Circle_Y => QC.Y);
   end Distance_Line_Circle;

   procedure Distance_Segment_Circle
     (Segment               : KS.Ks_Line_Segment;
      Input_Circle          : KS.Ks_Circle;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Selected_From_Circle  : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Distance_Segment_Circle_Result;
      Status                : out Ks_Status)
   is
      S      : P.Segment;
      C      : P.Circle;
      D      : P.Signed_Length;
      QS, QC : P.Point;
      Fits   : Boolean;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Segment (Segment, Selected_From_Segment, "Segment", S, Status);
      Get_Circle (Input_Circle, Selected_From_Circle, "InputCircle", C,
                  Status);
      if not Succeeded (Status) then
         return;
      end if;
      P.Segment_Circle (S, C, D, QS, QC, Fits);
      if not Fits then
         Out_Of_Bound ("DistanceSegmentCircle", Status);
         return;
      end if;
      Result := (Distance  => D,
                 Segment_X => QS.X,
                 Segment_Y => QS.Y,
                 Circle_X  => QC.X,
                 Circle_Y  => QC.Y);
   end Distance_Segment_Circle;

   procedure Distance_Circle_Circle
     (Circle_A, Circle_B     : KS.Ks_Circle;
      Selected_From_Circle_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Circle_B : KT.Ks_Transform_2D_Linear;
      Result                 : out Ks_Distance_Circle_Circle_Result;
      Status                 : out Ks_Status)
   is
      A, B   : P.Circle;
      D      : P.Signed_Length;
      QA, QB : P.Point;
      Fits   : Boolean;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Circle (Circle_A, Selected_From_Circle_A, "CircleA", A, Status);
      Get_Circle (Circle_B, Selected_From_Circle_B, "CircleB", B, Status);
      if not Succeeded (Status) then
         return;
      end if;
      P.Circle_Circle (A, B, D, QA, QB, Fits);
      if not Fits then
         Out_Of_Bound ("DistanceCircleCircle", Status);
         return;
      end if;
      Result := (Distance   => D,
                 Circle_A_X => QA.X,
                 Circle_A_Y => QA.Y,
                 Circle_B_X => QB.X,
                 Circle_B_Y => QB.Y);
   end Distance_Circle_Circle;

   procedure Distance_Line_Ellipse
     (Line                  : KS.Ks_Line;
      Ellipse               : KS.Ks_Ellipse;
      Selected_From_Line    : KT.Ks_Transform_2D_Linear;
      Selected_From_Ellipse : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Distance_Line_Ellipse_Result;
      Status                : out Ks_Status)
   is
      L      : P.Line;
      E      : EL.Ellipse;
      D      : P.Length;
      QL, QE : P.Point;
      Fits   : Boolean;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Line (Line, Selected_From_Line, "Line", L, Status);
      Get_Ellipse (Ellipse, Selected_From_Ellipse, "Ellipse", E, Status);
      if not Succeeded (Status) then
         return;
      end if;
      EL.Line_Ellipse (L, E, D, QL, QE, Fits);
      if not Fits then
         Out_Of_Bound ("DistanceLineEllipse", Status);
         return;
      end if;
      Result := (Distance  => D,
                 Line_X    => QL.X,
                 Line_Y    => QL.Y,
                 Ellipse_X => QE.X,
                 Ellipse_Y => QE.Y);
   end Distance_Line_Ellipse;

   procedure Distance_Segment_Ellipse
     (Segment               : KS.Ks_Line_Segment;
      Ellipse               : KS.Ks_Ellipse;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Selected_From_Ellipse : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Distance_Segment_Ellipse_Result;
      Status                : out Ks_Status)
   is
      S      : P.Segment;
      E      : EL.Ellipse;
      D      : P.Signed_Length;
      QS, QE : P.Point;
      Fits   : Boolean;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Segment (Segment, Selected_From_Segment, "Segment", S, Status);
      Get_Ellipse (Ellipse, Selected_From_Ellipse, "Ellipse", E, Status);
      if not Succeeded (Status) then
         return;
      end if;
      EL.Segment_Ellipse (S, E, D, QS, QE, Fits);
      if not Fits then
         Out_Of_Bound ("DistanceSegmentEllipse", Status);
         return;
      end if;
      Result := (Distance  => D,
                 Segment_X => QS.X,
                 Segment_Y => QS.Y,
                 Ellipse_X => QE.X,
                 Ellipse_Y => QE.Y);
   end Distance_Segment_Ellipse;

   ---------------------------------------------------------------------
   --  Intersections
   ---------------------------------------------------------------------

   procedure Intersect_Line_Line
     (Line_A, Line_B       : KS.Ks_Line;
      Selected_From_Line_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Line_B : KT.Ks_Transform_2D_Linear;
      Result               : out Ks_Intersect_Line_Line_Result;
      Status               : out Ks_Status)
   is
      A, B : P.Line;
      X    : P.Crossing;
      Fits : Boolean;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Line (Line_A, Selected_From_Line_A, "LineA", A, Status);
      Get_Line (Line_B, Selected_From_Line_B, "LineB", B, Status);
      if not Succeeded (Status) then
         return;
      end if;
      P.Intersect_Lines (A, B, X, Fits);
      if not Fits then
         Out_Of_Bound ("IntersectLineLine", Status);
         return;
      end if;
      Result := (Intersects => Code (X.Count /= 0),
                 Num_Points => X.Count,
                 X          => X.Where.X,
                 Y          => X.Where.Y,
                 Angle      => Angle_From (A, B));
   end Intersect_Line_Line;

   procedure Intersect_Segment_Line
     (Segment               : KS.Ks_Line_Segment;
      Line                  : KS.Ks_Line;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Selected_From_Line    : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Intersect_Segment_Line_Result;
      Status                : out Ks_Status)
   is
      S : P.Segment;
      L : P.Line;
      X : P.Crossing;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Segment (Segment, Selected_From_Segment, "Segment", S, Status);
      Get_Line (Line, Selected_From_Line, "Line", L, Status);
      if not Succeeded (Status) then
         return;
      end if;
      P.Intersect_Segment_Line (S, L, X);
      Result := (Intersects => Code (X.Count /= 0),
                 Num_Points => X.Count,
                 X          => X.Where.X,
                 Y          => X.Where.Y);
   end Intersect_Segment_Line;

   procedure Intersect_Segment_Segment
     (Segment_A, Segment_B    : KS.Ks_Line_Segment;
      Selected_From_Segment_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Segment_B : KT.Ks_Transform_2D_Linear;
      Result                  : out Ks_Intersect_Segment_Segment_Result;
      Status                  : out Ks_Status)
   is
      A, B : P.Segment;
      X    : P.Crossing;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Segment (Segment_A, Selected_From_Segment_A, "SegmentA", A,
                   Status);
      Get_Segment (Segment_B, Selected_From_Segment_B, "SegmentB", B,
                   Status);
      if not Succeeded (Status) then
         return;
      end if;
      P.Intersect_Segments (A, B, X);
      Result := (Intersects => Code (X.Count /= 0),
                 Num_Points => X.Count,
                 X          => X.Where.X,
                 Y          => X.Where.Y);
   end Intersect_Segment_Segment;

   function Two_Points_Result
     (Count  : Int32;
      P1, P2 : P.Point) return Ks_Intersect_Two_Points_Result
   with Pre  => Count in 0 .. 2,
        Post => Valid_Result (Two_Points_Result'Result);
   --  The result with Count points, P1 first; the points not reported are
   --  (0, 0).

   function Two_Points_Result
     (Count  : Int32;
      P1, P2 : P.Point) return Ks_Intersect_Two_Points_Result
   is
      Q1 : constant P.Point := (if Count >= 1 then P1 else P.Origin);
      Q2 : constant P.Point := (if Count = 2 then P2 else P.Origin);
   begin
      return (Intersects => Code (Count /= 0),
              Num_Points => Count,
              X0         => Q1.X,
              Y0         => Q1.Y,
              X1         => Q2.X,
              Y1         => Q2.Y);
   end Two_Points_Result;

   function To_KG_Line (L : P.Line) return KG.Ks_Line_2D is
     ((X => L.P.X, Y => L.P.Y, Rotation => L.Rotation));

   function To_KG_Circle (C : P.Circle) return KG.Ks_Circle_2D is
     ((Center_X => C.Center.X, Center_Y => C.Center.Y,
       Radius   => C.Radius));

   procedure Intersect_Line_Circle
     (Line                 : KS.Ks_Line;
      Input_Circle         : KS.Ks_Circle;
      Selected_From_Line   : KT.Ks_Transform_2D_Linear;
      Selected_From_Circle : KT.Ks_Transform_2D_Linear;
      Result               : out Ks_Intersect_Line_Circle_Result;
      Status               : out Ks_Status)
   is
      L      : P.Line;
      C      : P.Circle;
      P1, P2 : KG.Ks_Point_2D;
      Count  : Int32;
      S      : Ks_Status;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Line (Line, Selected_From_Line, "Line", L, Status);
      Get_Circle (Input_Circle, Selected_From_Circle, "InputCircle", C,
                  Status);
      if not Succeeded (Status) then
         return;
      end if;
      KG.Intersect_Line_Circle (To_KG_Line (L), To_KG_Circle (C), P1, P2,
                                Count, S);
      if not Succeeded (S) then
         Out_Of_Bound ("IntersectLineCircle", Status);
         return;
      end if;
      Result := Two_Points_Result (Count, (P1.X, P1.Y), (P2.X, P2.Y));
   end Intersect_Line_Circle;

   procedure Intersect_Segment_Circle
     (Segment               : KS.Ks_Line_Segment;
      Input_Circle          : KS.Ks_Circle;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Selected_From_Circle  : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Intersect_Segment_Circle_Result;
      Status                : out Ks_Status)
   is
      S      : P.Segment;
      C      : P.Circle;
      Dir    : P.Direction_Info;
      L      : P.Line;
      P1, P2 : KG.Ks_Point_2D;
      Found  : Int32;
      Map_S  : Ks_Status;
      Count  : Int32 range 0 .. 2 := 0;
      Kept_1 : P.Point := P.Origin;
      Kept_2 : P.Point := P.Origin;
      Tol    : Long_Float;

      procedure Keep (Q : P.Point)
      with Pre  => Count < 2,
           Post => Count = Count'Old + 1;
      --  Adds Q, moved onto the nearer end when it lies beyond one.

      procedure Keep (Q : P.Point) is
         T : constant P.Signed_Length := P.Along (Q, L);
         K : constant P.Point :=
           (if T < 0.0 then S.A elsif T > Dir.Length then S.B else Q);
      begin
         Count := Count + 1;
         if Count = 1 then
            Kept_1 := K;
         else
            Kept_2 := K;
         end if;
      end Keep;

      function On_Segment (Q : P.Point) return Boolean is
        (P.Along (Q, L) >= -Tol and then P.Along (Q, L) <= Dir.Length + Tol);

   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Segment (Segment, Selected_From_Segment, "Segment", S, Status);
      Get_Circle (Input_Circle, Selected_From_Circle, "InputCircle", C,
                  Status);
      if not Succeeded (Status) then
         return;
      end if;
      Dir := P.Direction (S);
      L := P.Line_Of (S);
      Tol := P.Relative_Tolerance * Dir.Length;
      if Dir.Length = 0.0 then
         --  A point: on the circle within the tangency tolerance.
         if abs (P.Distance (C.Center, S.A) - C.Radius)
              <= P.Relative_Tolerance * Long_Float'Max (1.0, C.Radius)
         then
            Result := Two_Points_Result (1, S.A, P.Origin);
         end if;
         return;
      end if;
      KG.Intersect_Line_Circle (To_KG_Line (L), To_KG_Circle (C), P1, P2,
                                Found, Map_S);
      if not Succeeded (Map_S) then
         Out_Of_Bound ("IntersectSegmentCircle", Status);
         return;
      end if;
      if Found >= 1 and then On_Segment ((P1.X, P1.Y)) then
         Keep ((P1.X, P1.Y));
      end if;
      if Found = 2 and then On_Segment ((P2.X, P2.Y)) then
         Keep ((P2.X, P2.Y));
      end if;
      Result := Two_Points_Result (Count, Kept_1, Kept_2);
   end Intersect_Segment_Circle;

   procedure Intersect_Circle_Circle
     (Circle_A, Circle_B     : KS.Ks_Circle;
      Selected_From_Circle_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Circle_B : KT.Ks_Transform_2D_Linear;
      Result                 : out Ks_Intersect_Circle_Circle_Result;
      Status                 : out Ks_Status)
   is
      A, B   : P.Circle;
      P1, P2 : KG.Ks_Point_2D;
      Count  : Int32;
      S      : Ks_Status;
      Tol    : Long_Float;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Circle (Circle_A, Selected_From_Circle_A, "CircleA", A, Status);
      Get_Circle (Circle_B, Selected_From_Circle_B, "CircleB", B, Status);
      if not Succeeded (Status) then
         return;
      end if;
      Tol := P.Relative_Tolerance
             * Long_Float'Max (1.0, A.Radius + B.Radius);
      if P.Distance (A.Center, B.Center) <= Tol
        and then abs (A.Radius - B.Radius) <= Tol
      then
         --  Identical circles.
         Result := (Intersects => True_Value, Num_Points => -1,
                    others     => 0.0);
         return;
      end if;
      KG.Intersect_Circles (To_KG_Circle (A), To_KG_Circle (B), P1, P2,
                            Count, S);
      if not Succeeded (S) then
         Out_Of_Bound ("IntersectCircleCircle", Status);
         return;
      end if;
      Result := (Intersects => Code (Count /= 0),
                 Num_Points => Count,
                 X0         => (if Count >= 1 then P1.X else 0.0),
                 Y0         => (if Count >= 1 then P1.Y else 0.0),
                 X1         => (if Count = 2 then P2.X else 0.0),
                 Y1         => (if Count = 2 then P2.Y else 0.0),
                 others     => 0.0);
   end Intersect_Circle_Circle;

   procedure Intersect_Line_Ellipse
     (Line                  : KS.Ks_Line;
      Ellipse               : KS.Ks_Ellipse;
      Selected_From_Line    : KT.Ks_Transform_2D_Linear;
      Selected_From_Ellipse : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Intersect_Line_Ellipse_Result;
      Status                : out Ks_Status)
   is
      L     : P.Line;
      E     : EL.Ellipse;
      Found : EL.Two_Points;
      Fits  : Boolean;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Line (Line, Selected_From_Line, "Line", L, Status);
      Get_Ellipse (Ellipse, Selected_From_Ellipse, "Ellipse", E, Status);
      if not Succeeded (Status) then
         return;
      end if;
      EL.Intersect_Line_Ellipse (L, E, Found, Fits);
      if not Fits then
         Out_Of_Bound ("IntersectLineEllipse", Status);
         return;
      end if;
      Result := Two_Points_Result (Found.Count, Found.P1, Found.P2);
   end Intersect_Line_Ellipse;

   procedure Intersect_Segment_Ellipse
     (Segment               : KS.Ks_Line_Segment;
      Ellipse               : KS.Ks_Ellipse;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Selected_From_Ellipse : KT.Ks_Transform_2D_Linear;
      Result                : out Ks_Intersect_Segment_Ellipse_Result;
      Status                : out Ks_Status)
   is
      S     : P.Segment;
      E     : EL.Ellipse;
      Found : EL.Two_Points;
      Fits  : Boolean;
   begin
      Result := (others => <>);
      Set_Success (Status);
      Get_Segment (Segment, Selected_From_Segment, "Segment", S, Status);
      Get_Ellipse (Ellipse, Selected_From_Ellipse, "Ellipse", E, Status);
      if not Succeeded (Status) then
         return;
      end if;
      EL.Intersect_Segment_Ellipse (S, E, Found, Fits);
      if not Fits then
         Out_Of_Bound ("IntersectSegmentEllipse", Status);
         return;
      end if;
      Result := Two_Points_Result (Found.Count, Found.P1, Found.P2);
   end Intersect_Segment_Ellipse;

end AMV.Kernels.Dimensioning;
