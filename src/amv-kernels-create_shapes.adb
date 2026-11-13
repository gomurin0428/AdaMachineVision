pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Numerics;

package body AMV.Kernels.Create_Shapes with SPARK_Mode is

   package N renames AMV.Kernels.Numerics;

   ---------------------------------------------------------------------
   --  Statuses
   ---------------------------------------------------------------------

   function Success return Ks_Status
   with Post => Valid (Success'Result) and then Succeeded (Success'Result);

   function Success return Ks_Status is
      Status : Ks_Status;
   begin
      Set_Success (Status);
      return Status;
   end Success;

   function Bad (Message : String) return Ks_Status
   with Post => Valid (Bad'Result)
                and then Bad'Result.Failure = Failure_Bad_Parameter;

   function Bad (Message : String) return Ks_Status is
      Status : Ks_Status;
   begin
      Set_Failure (Status, Failure_Bad_Parameter, Message);
      return Status;
   end Bad;

   function Image (Name : Input_Name) return String is
     (case Name is
         when Input_Circle_Name => "InputCircle",
         when Ellipse_Name      => "Ellipse",
         when Line_Name         => "Line",
         when Segment_Name      => "Segment",
         when Segment_A_Name    => "SegmentA",
         when Segment_B_Name    => "SegmentB")
   with Post => Image'Result'First = 1 and then Image'Result'Length <= 40;
   --  The property name of an input shape.

   function Out_Of_Bound (Name : String) return Ks_Status is
     (Bad (Name & " must be finite and within +/-1.0E150"))
   with Pre  => Name'First = 1 and then Name'Length <= 40,
        Post => Valid (Out_Of_Bound'Result)
                and then Out_Of_Bound'Result.Failure = Failure_Bad_Parameter;
   --  The failure of an input that is not finite or beyond the bound.

   function Bad_Transform (Name : String) return Ks_Status is
     (Bad ("the transform of " & Name
           & " must be finite and within +/-1.0E150"))
   with Pre  => Name'First = 1 and then Name'Length <= 40,
        Post => Valid (Bad_Transform'Result)
                and then Bad_Transform'Result.Failure
                           = Failure_Bad_Parameter;

   function Too_Far (Name : String) return Ks_Status is
     (Bad (Name & ": in the selected space it would exceed +/-1.0E150"))
   with Pre  => Name'First = 1 and then Name'Length <= 40,
        Post => Valid (Too_Far'Result)
                and then Too_Far'Result.Failure = Failure_Bad_Parameter;
   --  The failure of a shape that leaves the bound once mapped.

   ---------------------------------------------------------------------
   --  The constructions
   ---------------------------------------------------------------------

   function Normalize (A : Long_Float) return Long_Float is
     (if Valid_Angle (A) then A else N.Reduce_Two_Pi (A));

   function Direction_Of (DX, DY : Long_Float) return Long_Float is
     (N.Direction (DY, DX));

   ---------------------------------------------------------------------
   --  Inputs mapped into the selected space
   ---------------------------------------------------------------------

   function Map_Line
     (Line      : KS.Ks_Line;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : Input_Name) return Mapped_Line
   is
      Prop   : constant String := Image (Name);
      Mapped : KS.Ks_Line;
      S      : Ks_Status;
   begin
      if not KS.Valid_Line (Line) then
         return (Line => (others => <>), Status => Out_Of_Bound (Prop));
      elsif not KT.Bounded (Transform) then
         return (Line => (others => <>), Status => Bad_Transform (Prop));
      end if;
      KS.Map (Line, Transform, Mapped, S);
      if S.Failure = Failure_Transform_Singular then
         Set_Failure (S, Failure_Transform_Singular,
                      "the transform of " & Prop & " is singular");
         return (Line => (others => <>), Status => S);
      elsif not Succeeded (S) then
         return (Line => (others => <>), Status => Too_Far (Prop));
      end if;
      return (Line   => (X        => Mapped.X,
                         Y        => Mapped.Y,
                         Rotation => Normalize (Mapped.Rotation)),
              Status => Success);
   end Map_Line;

   function Map_Segment
     (Segment   : KS.Ks_Line_Segment;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : Input_Name) return Mapped_Segment
   is
      Prop   : constant String := Image (Name);
      Mapped : KS.Ks_Line_Segment;
      S      : Ks_Status;
   begin
      if not KS.Valid_Line_Segment (Segment) then
         return (Segment => (others => <>), Status => Out_Of_Bound (Prop));
      elsif not KT.Bounded (Transform) then
         return (Segment => (others => <>), Status => Bad_Transform (Prop));
      end if;
      KS.Map (Segment, Transform, Mapped, S);
      if not Succeeded (S) then
         return (Segment => (others => <>), Status => Too_Far (Prop));
      end if;
      return (Segment => Mapped, Status => Success);
   end Map_Segment;

   function Map_Circle
     (Circle    : KS.Ks_Circle;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : Input_Name) return Mapped_Circle
   is
      Prop           : constant String := Image (Name);
      Kind           : Int32;
      Mapped         : KS.Ks_Circle;
      Unused_Ellipse : KS.Ks_Ellipse;
      S              : Ks_Status;
   begin
      if not KS.Valid_Circle (Circle) then
         return (Circle => (others => <>),
                 Status => Bad (Prop & " must be finite and within"
                                & " +/-1.0E150 (radius >= 0)"));
      elsif not KT.Bounded (Transform) then
         return (Circle => (others => <>), Status => Bad_Transform (Prop));
      end if;
      KS.Map (Circle, Transform, Kind, Mapped, Unused_Ellipse, S);
      if not Succeeded (S) then
         return (Circle => (others => <>), Status => Too_Far (Prop));
      elsif Kind /= KS.Shape_Circle then
         return (Circle => (others => <>),
                 Status => Bad (Prop & ": its transform to the selected"
                                & " space is not a similarity (the circle"
                                & " would become an ellipse)"));
      elsif Mapped.Radius > Max_Value then
         return (Circle => (others => <>),
                 Status => Bad (Prop & ".Radius would exceed 1.0E150 in the"
                                & " selected space"));
      end if;
      return (Circle => Mapped, Status => Success);
   end Map_Circle;

   function Map_Ellipse
     (Ellipse   : KS.Ks_Ellipse;
      Transform : KT.Ks_Transform_2D_Linear;
      Name      : Input_Name) return Mapped_Ellipse
   is
      Prop   : constant String := Image (Name);
      Mapped : KS.Ks_Ellipse;
      S      : Ks_Status;
   begin
      if not KS.Valid_Ellipse (Ellipse) then
         return (Ellipse => (others => <>),
                 Status  => Bad (Prop & " must be finite and within"
                                 & " +/-1.0E150 (radii >= 0)"));
      elsif Ellipse.Radius_X = 0.0 or else Ellipse.Radius_Y = 0.0 then
         return (Ellipse => (others => <>),
                 Status  => Bad (Prop & ".RadiusX and " & Prop
                                 & ".RadiusY must be > 0"));
      elsif not KT.Bounded (Transform) then
         return (Ellipse => (others => <>), Status => Bad_Transform (Prop));
      end if;
      KS.Map (Ellipse, Transform, Mapped, S);
      if not Succeeded (S) then
         return (Ellipse => (others => <>), Status => Too_Far (Prop));
      elsif Mapped.Radius_X > Max_Value or else Mapped.Radius_Y > Max_Value
      then
         return (Ellipse => (others => <>),
                 Status  => Bad (Prop & ": its radii would exceed 1.0E150"
                                 & " in the selected space"));
      elsif Mapped.Radius_X = 0.0 or else Mapped.Radius_Y = 0.0 then
         return (Ellipse => (others => <>),
                 Status  => Bad (Prop & ": a radius becomes 0 in the"
                                 & " selected space"));
      end if;
      return (Ellipse => Mapped, Status => Success);
   end Map_Ellipse;

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   procedure Create_Circle
     (Input_Circle               : KS.Ks_Circle;
      Selected_From_Input_Circle : KT.Ks_Transform_2D_Linear;
      Result                     : out KS.Ks_Circle;
      Status                     : out Ks_Status)
   is
      M : constant Mapped_Circle :=
        Map_Circle
          (Input_Circle, Selected_From_Input_Circle, Input_Circle_Name);
   begin
      Result := M.Circle;
      Status := M.Status;
   end Create_Circle;

   procedure Create_Ellipse
     (Ellipse               : KS.Ks_Ellipse;
      Selected_From_Ellipse : KT.Ks_Transform_2D_Linear;
      Result                : out KS.Ks_Ellipse;
      Status                : out Ks_Status)
   is
      M : constant Mapped_Ellipse :=
        Map_Ellipse (Ellipse, Selected_From_Ellipse, Ellipse_Name);
   begin
      Result := M.Ellipse;
      Status := M.Status;
   end Create_Ellipse;

   procedure Create_Line
     (Line               : KS.Ks_Line;
      Selected_From_Line : KT.Ks_Transform_2D_Linear;
      Result             : out KS.Ks_Line;
      Status             : out Ks_Status)
   is
      M : constant Mapped_Line :=
        Map_Line (Line, Selected_From_Line, Line_Name);
   begin
      Result := M.Line;
      Status := M.Status;
   end Create_Line;

   procedure Create_Segment
     (Segment               : KS.Ks_Line_Segment;
      Selected_From_Segment : KT.Ks_Transform_2D_Linear;
      Result                : out KS.Ks_Line_Segment;
      Status                : out Ks_Status)
   is
      M : constant Mapped_Segment :=
        Map_Segment (Segment, Selected_From_Segment, Segment_Name);
   begin
      Result := M.Segment;
      Status := M.Status;
   end Create_Segment;

   procedure Create_Line_Bisect_Points
     (Start_X, Start_Y, End_X, End_Y : Long_Float;
      Result                         : out KS.Ks_Line;
      Status                         : out Ks_Status)
   is
      DX, DY : Long_Float;
   begin
      Result := (others => <>);
      if not Bounded (Start_X) then
         Status := Out_Of_Bound ("StartX");
      elsif not Bounded (Start_Y) then
         Status := Out_Of_Bound ("StartY");
      elsif not Bounded (End_X) then
         Status := Out_Of_Bound ("EndX");
      elsif not Bounded (End_Y) then
         Status := Out_Of_Bound ("EndY");
      else
         DX := End_X - Start_X;
         DY := End_Y - Start_Y;
         if DX = 0.0 and then DY = 0.0 then
            Status := Bad ("StartX, StartY and EndX, EndY are the same"
                           & " point (the bisector needs a direction)");
         else
            Result := (X        => Midpoint (Start_X, End_X),
                       Y        => Midpoint (Start_Y, End_Y),
                       Rotation => Quarter_Turn (Direction_Of (DX, DY)));
            Status := Success;
         end if;
      end if;
   end Create_Line_Bisect_Points;

   procedure Create_Line_Parallel
     (X, Y               : Long_Float;
      Line               : KS.Ks_Line;
      Selected_From_Line : KT.Ks_Transform_2D_Linear;
      Result             : out KS.Ks_Line;
      Status             : out Ks_Status)
   is
      M : constant Mapped_Line :=
        Map_Line (Line, Selected_From_Line, Line_Name);
   begin
      Result := (others => <>);
      if not Bounded (X) then
         Status := Out_Of_Bound ("X");
      elsif not Bounded (Y) then
         Status := Out_Of_Bound ("Y");
      else
         Status := M.Status;
         if Succeeded (M.Status) then
            Result := (X => X, Y => Y, Rotation => M.Line.Rotation);
         end if;
      end if;
   end Create_Line_Parallel;

   procedure Create_Line_Perpendicular
     (X, Y               : Long_Float;
      Line               : KS.Ks_Line;
      Selected_From_Line : KT.Ks_Transform_2D_Linear;
      Result             : out KS.Ks_Line;
      Status             : out Ks_Status)
   is
      M : constant Mapped_Line :=
        Map_Line (Line, Selected_From_Line, Line_Name);
   begin
      Result := (others => <>);
      if not Bounded (X) then
         Status := Out_Of_Bound ("X");
      elsif not Bounded (Y) then
         Status := Out_Of_Bound ("Y");
      else
         Status := M.Status;
         if Succeeded (M.Status) then
            Result := (X        => X,
                       Y        => Y,
                       Rotation => Quarter_Turn (M.Line.Rotation));
         end if;
      end if;
   end Create_Line_Perpendicular;

   procedure Create_Segment_Avg_Segs
     (Segment_A, Segment_B    : KS.Ks_Line_Segment;
      Selected_From_Segment_A : KT.Ks_Transform_2D_Linear;
      Selected_From_Segment_B : KT.Ks_Transform_2D_Linear;
      Result                  : out KS.Ks_Line_Segment;
      Status                  : out Ks_Status)
   is
      A : constant Mapped_Segment :=
        Map_Segment (Segment_A, Selected_From_Segment_A, Segment_A_Name);
      B : constant Mapped_Segment :=
        Map_Segment (Segment_B, Selected_From_Segment_B, Segment_B_Name);
   begin
      Result := (others => <>);
      if not Succeeded (A.Status) then
         Status := A.Status;
      elsif not Succeeded (B.Status) then
         Status := B.Status;
      else
         Result := Average (A.Segment, B.Segment);
         Status := Success;
      end if;
   end Create_Segment_Avg_Segs;

end AMV.Kernels.Create_Shapes;
