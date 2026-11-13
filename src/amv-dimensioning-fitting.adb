pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.IO_Exceptions;
with Interfaces;

with AMV.Checks;
with AMV.Kernels;

package body AMV.Dimensioning.Fitting is

   use Ada.Strings.Unbounded;

   use type AMV.Kernels.Int32;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;
   subtype U32 is Interfaces.Unsigned_32;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   ---------------------------------------------------------------------
   --  The points
   ---------------------------------------------------------------------

   overriding procedure Adjust (Points : in out Point_List) is
      Source : constant KS.Ks_Polygon := Points.Handle;
      Status : Ks_Status;
   begin
      --  The copy shares the source's handle until it has its own; it
      --  must not keep it if the duplicate cannot be made.
      Points.Handle := null;
      KF.Points_Duplicate (Source, Points.Handle, Status);
      Check (Status);
   end Adjust;

   overriding procedure Finalize (Points : in out Point_List) is
   begin
      KF.Points_Destroy (Points.Handle);
   end Finalize;

   overriding function "=" (Left, Right : Point_List) return Boolean
   is (KS.Same_Vertices (Left.Handle, Right.Handle));

   procedure Write_Points
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Point_List)
   is
      Count  : Int32;
      X, Y   : Real;
      Status : Ks_Status;
   begin
      KF.Points_Num_Points (Item.Handle, Count, Status);
      Check (Status);
      U32'Write (Stream, U32 (Count));
      for Index in 0 .. Count - 1 loop  --  SHELL: stream I/O, every point
         KF.Points_Get_Point (Item.Handle, Index, X, Y, Status);
         Check (Status);
         Real'Write (Stream, X);
         Real'Write (Stream, Y);
      end loop;  --  SHELL: (the loop above)
   end Write_Points;

   procedure Swap (Left, Right : in out Point_List);
   --  Exchanges the handles of Left and Right.

   procedure Swap (Left, Right : in out Point_List) is
      Left_Handle : constant KS.Ks_Polygon := Left.Handle;
   begin
      Left.Handle := Right.Handle;
      Right.Handle := Left_Handle;
   end Swap;

   procedure Read_Points
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Point_List)
   is
      Fresh  : Point_List;
      Count  : U32;
      X, Y   : Real;
      Status : Ks_Status;
   begin
      U32'Read (Stream, Count);
      KS.Check_Stream_Count (Count, Status);
      Check (Status);
      --  Fresh owns the points read so far, so that a failure frees them
      --  and leaves Item unchanged.
      for Index in 1 .. Count loop  --  SHELL: stream I/O, every point
         Real'Read (Stream, X);
         Real'Read (Stream, Y);
         KF.Points_Add_Point (Fresh.Handle, X, Y, Status);
         Check (Status);
      end loop;  --  SHELL: (the loop above)
      --  Item takes the points read; Fresh frees the old ones.
      Swap (Item, Fresh);
   end Read_Points;

   function Num_Points (Params : Ks_Fit_Points) return Natural is
      Count  : Int32;
      Status : Ks_Status;
   begin
      KF.Points_Num_Points (Params.Points.Handle, Count, Status);
      Check (Status);
      return Natural (Count);
   end Num_Points;

   procedure Set_Num_Points (Params : in out Ks_Fit_Points; Value : Natural)
   is
      Status : Ks_Status;
   begin
      KF.Points_Set_Num_Points (Params.Points.Handle, Int32 (Value), Status);
      Check (Status);
   end Set_Num_Points;

   procedure Add_Point (Params : in out Ks_Fit_Points; X, Y : Real) is
      Status : Ks_Status;
   begin
      KF.Points_Add_Point (Params.Points.Handle, X, Y, Status);
      Check (Status);
   end Add_Point;

   procedure Delete_Point (Params : in out Ks_Fit_Points; Index : Natural) is
      Status : Ks_Status;
   begin
      KF.Points_Delete_Point (Params.Points.Handle, Int32 (Index), Status);
      Check (Status);
   end Delete_Point;

   procedure Get_Point
     (Params : Ks_Fit_Points;
      Index  : Natural;
      X, Y   : out Real)
   is
      Status : Ks_Status;
   begin
      KF.Points_Get_Point (Params.Points.Handle, Int32 (Index), X, Y,
                           Status);
      Check (Status);
   end Get_Point;

   procedure Set_Point
     (Params : in out Ks_Fit_Points;
      Index  : Natural;
      X, Y   : Real)
   is
      Status : Ks_Status;
   begin
      KF.Points_Set_Point (Params.Points.Handle, Int32 (Index), X, Y,
                           Status);
      Check (Status);
   end Set_Point;

   function Get_X (Params : Ks_Fit_Points; Index : Natural) return Real is
      X, Y : Real;
   begin
      Get_Point (Params, Index, X, Y);
      return X;
   end Get_X;

   function Get_Y (Params : Ks_Fit_Points; Index : Natural) return Real is
      X, Y : Real;
   begin
      Get_Point (Params, Index, X, Y);
      return Y;
   end Get_Y;

   procedure Set_X
     (Params : in out Ks_Fit_Points;
      Index  : Natural;
      Value  : Real)
   is
      Status : Ks_Status;
   begin
      KF.Points_Set_X (Params.Points.Handle, Int32 (Index), Value, Status);
      Check (Status);
   end Set_X;

   procedure Set_Y
     (Params : in out Ks_Fit_Points;
      Index  : Natural;
      Value  : Real)
   is
      Status : Ks_Status;
   begin
      KF.Points_Set_Y (Params.Points.Handle, Int32 (Index), Value, Status);
      Check (Status);
   end Set_Y;

   function Num_To_Ignore (Params : Ks_Fit_Points) return Natural is
     (Params.Num_To_Ignore);

   procedure Set_Num_To_Ignore
     (Params : in out Ks_Fit_Points;
      Value  : Natural) is
   begin
      Params.Num_To_Ignore := Value;
   end Set_Num_To_Ignore;

   function Radius_Constraint_Enabled (Params : Ks_Fit_Circle) return Boolean
   is (Params.Radius_Constraint_Enabled);

   procedure Set_Radius_Constraint_Enabled
     (Params : in out Ks_Fit_Circle;
      Value  : Boolean) is
   begin
      Params.Radius_Constraint_Enabled := Value;
   end Set_Radius_Constraint_Enabled;

   function Radius_Constraint (Params : Ks_Fit_Circle) return Real is
     (Params.Radius_Constraint);

   procedure Set_Radius_Constraint
     (Params : in out Ks_Fit_Circle;
      Value  : Real) is
   begin
      Params.Radius_Constraint := Value;
   end Set_Radius_Constraint;

   function Rotation_Constraint_Enabled
     (Params : Ks_Fit_Ellipse) return Boolean
   is (Params.Rotation_Constraint_Enabled);

   procedure Set_Rotation_Constraint_Enabled
     (Params : in out Ks_Fit_Ellipse;
      Value  : Boolean) is
   begin
      Params.Rotation_Constraint_Enabled := Value;
   end Set_Rotation_Constraint_Enabled;

   function Rotation_Constraint (Params : Ks_Fit_Ellipse) return Real is
     (Params.Rotation_Constraint);

   procedure Set_Rotation_Constraint
     (Params : in out Ks_Fit_Ellipse;
      Value  : Real) is
   begin
      Params.Rotation_Constraint := Value;
   end Set_Rotation_Constraint;

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   procedure Destroy (Handle : in out KF.Ks_Fit_Result) is
   begin
      KF.Result_Destroy (Handle);
   end Destroy;

   function Handle_Of (Result : Ks_Fit_Result'Class)
      return KF.Ks_Fit_Result is
     (Result_Holders.Get (Result.Holder));

   function Num_Points (Result : Ks_Fit_Result) return Natural is
      Count  : Int32;
      Status : Ks_Status;
   begin
      KF.Result_Num_Points (Handle_Of (Result), Count, Status);
      Check (Status);
      return Natural (Count);
   end Num_Points;

   function RMS_Error (Result : Ks_Fit_Result) return Real is
      Value  : Real;
      Status : Ks_Status;
   begin
      KF.Result_RMS_Error (Handle_Of (Result), Value, Status);
      Check (Status);
      return Value;
   end RMS_Error;

   function Num_Points_Used (Result : Ks_Fit_Result) return Natural is
      Count  : Int32;
      Status : Ks_Status;
   begin
      KF.Result_Num_Points_Used (Handle_Of (Result), Count, Status);
      Check (Status);
      return Natural (Count);
   end Num_Points_Used;

   procedure Get_XY_Used_Distance
     (Result   : Ks_Fit_Result;
      Index    : Natural;
      X, Y     : out Real;
      Used     : out Boolean;
      Distance : out Real)
   is
      Used_Code : Int32;
      Status    : Ks_Status;
   begin
      KF.Result_Get_XY_Used_Distance
        (Handle_Of (Result), Int32 (Index), X, Y, Used_Code, Distance,
         Status);
      Check (Status);
      Used := Boolean'Val (Used_Code);
   end Get_XY_Used_Distance;

   type Point_Report is record
      X, Y     : Real;
      Used     : Boolean;
      Distance : Real;
   end record;

   function Report_Of (Result : Ks_Fit_Result'Class; Index : Natural)
      return Point_Report
   is
   begin
      return R : Point_Report do
         Result.Get_XY_Used_Distance (Index, R.X, R.Y, R.Used, R.Distance);
      end return;
   end Report_Of;

   function Get_X (Result : Ks_Fit_Result; Index : Natural) return Real is
     (Report_Of (Result, Index).X);

   function Get_Y (Result : Ks_Fit_Result; Index : Natural) return Real is
     (Report_Of (Result, Index).Y);

   function Get_Used (Result : Ks_Fit_Result; Index : Natural) return Boolean
   is (Report_Of (Result, Index).Used);

   function Get_Distance (Result : Ks_Fit_Result; Index : Natural)
      return Real
   is (Report_Of (Result, Index).Distance);

   function Get_Line (Result : Ks_Fit_Line_Result) return AMV.Shapes.Ks_Line
   is
      Line   : KS.Ks_Line;
      Status : Ks_Status;
   begin
      KF.Result_Get_Line (Handle_Of (Result), Line, Status);
      Check (Status);
      return Shape : AMV.Shapes.Ks_Line do
         Shape.Set_XY_Rotation (Line.X, Line.Y, Line.Rotation);
         Shape.Set_Selected_Space_Name (To_String (Result.Space_Name));
      end return;
   end Get_Line;

   function Get_Circle
     (Result : Ks_Fit_Circle_Result) return AMV.Shapes.Ks_Circle
   is
      Circle : KS.Ks_Circle;
      Status : Ks_Status;
   begin
      KF.Result_Get_Circle (Handle_Of (Result), Circle, Status);
      Check (Status);
      return Shape : AMV.Shapes.Ks_Circle do
         Shape.Set_Center_Radius
           (Circle.Center_X, Circle.Center_Y, Circle.Radius);
         Shape.Set_Selected_Space_Name (To_String (Result.Space_Name));
      end return;
   end Get_Circle;

   function Get_Ellipse
     (Result : Ks_Fit_Ellipse_Result) return AMV.Shapes.Ks_Ellipse
   is
      Ellipse : KS.Ks_Ellipse;
      Status  : Ks_Status;
   begin
      KF.Result_Get_Ellipse (Handle_Of (Result), Ellipse, Status);
      Check (Status);
      return Shape : AMV.Shapes.Ks_Ellipse do
         Shape.Set_Center_XY_Radius_XY_Rotation
           (Ellipse.Center_X, Ellipse.Center_Y, Ellipse.Radius_X,
            Ellipse.Radius_Y, Ellipse.Rotation);
         Shape.Set_Selected_Space_Name (To_String (Result.Space_Name));
      end return;
   end Get_Ellipse;

   ---------------------------------------------------------------------
   --  Execution
   ---------------------------------------------------------------------

   function Execute
     (Params              : Ks_Fit_Line'Class;
      Selected_Space_Name : String := ".") return Ks_Fit_Line_Result
   is
      Handle : KF.Ks_Fit_Result;
      Status : Ks_Status;
   begin
      KF.Line_Execute
        (Params.Points.Handle,
         (Num_To_Ignore => Int32 (Params.Num_To_Ignore)), Handle, Status);
      Check (Status);
      return Result : Ks_Fit_Line_Result do
         Result_Holders.Set (Result.Holder, Handle);
         Result.Space_Name := To_Unbounded_String (Selected_Space_Name);
      end return;
   end Execute;

   function Execute
     (Params              : Ks_Fit_Circle'Class;
      Selected_Space_Name : String := ".") return Ks_Fit_Circle_Result
   is
      Handle : KF.Ks_Fit_Result;
      Status : Ks_Status;
   begin
      KF.Circle_Execute
        (Params.Points.Handle,
         (Num_To_Ignore             => Int32 (Params.Num_To_Ignore),
          Radius_Constraint_Enabled =>
            Boolean'Pos (Params.Radius_Constraint_Enabled),
          Radius_Constraint         => Params.Radius_Constraint),
         Handle, Status);
      Check (Status);
      return Result : Ks_Fit_Circle_Result do
         Result_Holders.Set (Result.Holder, Handle);
         Result.Space_Name := To_Unbounded_String (Selected_Space_Name);
      end return;
   end Execute;

   function Execute
     (Params              : Ks_Fit_Ellipse'Class;
      Selected_Space_Name : String := ".") return Ks_Fit_Ellipse_Result
   is
      Handle : KF.Ks_Fit_Result;
      Status : Ks_Status;
   begin
      KF.Ellipse_Execute
        (Params.Points.Handle,
         (Num_To_Ignore               => Int32 (Params.Num_To_Ignore),
          Rotation_Constraint_Enabled =>
            Boolean'Pos (Params.Rotation_Constraint_Enabled),
          Rotation_Constraint         => Params.Rotation_Constraint),
         Handle, Status);
      Check (Status);
      return Result : Ks_Fit_Ellipse_Result do
         Result_Holders.Set (Result.Holder, Handle);
         Result.Space_Name := To_Unbounded_String (Selected_Space_Name);
      end return;
   end Execute;

   ---------------------------------------------------------------------
   --  The tools
   ---------------------------------------------------------------------

   overriding procedure Execute (Tool : in out Ks_Fit_Line_Tool) is
   begin
      Tool.Result := Execute (Tool.Run_Params);
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Fit_Line_Tool) is
   begin
      Result_Holders.Clear (Tool.Result.Holder);
   end Reset_Results;

   overriding procedure Execute (Tool : in out Ks_Fit_Circle_Tool) is
   begin
      Tool.Result := Execute (Tool.Run_Params);
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Fit_Circle_Tool) is
   begin
      Result_Holders.Clear (Tool.Result.Holder);
   end Reset_Results;

   overriding procedure Execute (Tool : in out Ks_Fit_Ellipse_Tool) is
   begin
      Tool.Result := Execute (Tool.Run_Params);
   end Execute;

   overriding procedure Reset_Results (Tool : in out Ks_Fit_Ellipse_Tool) is
   begin
      Result_Holders.Clear (Tool.Result.Holder);
   end Reset_Results;


   ---------------------------------------------------------------------
   --  Stream attributes of the run parameters (see the private part)
   ---------------------------------------------------------------------

   procedure Read_Fit_Points
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Fit_Points)
   is
      Fresh : Ks_Fit_Points;
   begin
      Point_List'Read (Stream, Fresh.Points);
      Natural'Read (Stream, Fresh.Num_To_Ignore);
      AMV.Checks.Check_Read (Fresh.Num_To_Ignore'Valid,
                             "Ks_Fit_Points'Read");
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Fit_Points'Read");
   end Read_Fit_Points;

   procedure Read_Fit_Circle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Fit_Circle)
   is
      Fresh : Ks_Fit_Circle;
   begin
      Ks_Fit_Points'Read (Stream, Ks_Fit_Points (Fresh));
      Boolean'Read (Stream, Fresh.Radius_Constraint_Enabled);
      Real'Read (Stream, Fresh.Radius_Constraint);
      AMV.Checks.Check_Read (Fresh.Radius_Constraint_Enabled'Valid,
                             "Ks_Fit_Circle'Read");
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Fit_Circle'Read");
   end Read_Fit_Circle;

   procedure Read_Fit_Ellipse
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Fit_Ellipse)
   is
      Fresh : Ks_Fit_Ellipse;
   begin
      Ks_Fit_Points'Read (Stream, Ks_Fit_Points (Fresh));
      Boolean'Read (Stream, Fresh.Rotation_Constraint_Enabled);
      Real'Read (Stream, Fresh.Rotation_Constraint);
      AMV.Checks.Check_Read (Fresh.Rotation_Constraint_Enabled'Valid,
                             "Ks_Fit_Ellipse'Read");
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Fit_Ellipse'Read");
   end Read_Fit_Ellipse;

end AMV.Dimensioning.Fitting;
