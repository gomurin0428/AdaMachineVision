pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with Ada.IO_Exceptions;
with Interfaces;

with AMV.Checks;
with AMV.Kernels.Transforms;

package body AMV.Shapes is

   package K renames AMV.Kernels.Shapes;
   package KT renames AMV.Kernels.Transforms;

   use type AMV.Kernels.Int32;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;
   subtype U32 is Interfaces.Unsigned_32;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   function Is_True (Flag : Int32) return Boolean is
     (Flag = AMV.Kernels.True_Value);

   function To_Kernel
     (Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return KT.Ks_Transform_2D_Linear;

   function To_Kernel
     (Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return KT.Ks_Transform_2D_Linear
   is
      Result : KT.Ks_Transform_2D_Linear;
   begin
      Transform.Get_Matrix_Elements_Translation
        (Result.A, Result.B, Result.C, Result.D, Result.Translation_X,
         Result.Translation_Y);
      return Result;
   end To_Kernel;

   ---------------------------------------------------------------------
   --  ICogShape
   ---------------------------------------------------------------------

   function Selected_Space_Name (Shape : Ks_Shape) return String is
     (Ada.Strings.Unbounded.To_String (Shape.Space_Name));

   procedure Set_Selected_Space_Name
     (Shape : in out Ks_Shape; Space_Name : String) is
   begin
      Shape.Space_Name :=
        Ada.Strings.Unbounded.To_Unbounded_String (Space_Name);
   end Set_Selected_Space_Name;

   ---------------------------------------------------------------------
   --  Results of Map whose type the kernel chooses
   ---------------------------------------------------------------------

   function Rectangle_Or_Affine
     (Shape       : Ks_Shape'Class;
      Result_Type : Int32;
      Rectangle   : K.Ks_Rectangle;
      Affine      : K.Ks_Rectangle_Affine) return Ks_Shape'Class;
   --  The Ada shape of the type the kernel's Result_Type names, with
   --  Shape's selected space name.

   function Rectangle_Or_Affine
     (Shape       : Ks_Shape'Class;
      Result_Type : Int32;
      Rectangle   : K.Ks_Rectangle;
      Affine      : K.Ks_Rectangle_Affine) return Ks_Shape'Class is
   begin
      if Result_Type = K.Shape_Rectangle then
         return Result : Ks_Rectangle do
            Result.Space_Name := Shape.Space_Name;
            Result.Data := Rectangle;
         end return;
      end if;
      return Result : Ks_Rectangle_Affine do
         Result.Space_Name := Shape.Space_Name;
         Result.Data := Affine;
      end return;
   end Rectangle_Or_Affine;

   function Circle_Or_Ellipse
     (Shape       : Ks_Shape'Class;
      Result_Type : Int32;
      Circle      : K.Ks_Circle;
      Ellipse     : K.Ks_Ellipse) return Ks_Shape'Class;
   --  The same for a mapped circle.

   function Circle_Or_Ellipse
     (Shape       : Ks_Shape'Class;
      Result_Type : Int32;
      Circle      : K.Ks_Circle;
      Ellipse     : K.Ks_Ellipse) return Ks_Shape'Class is
   begin
      if Result_Type = K.Shape_Circle then
         return Result : Ks_Circle do
            Result.Space_Name := Shape.Space_Name;
            Result.Data := Circle;
         end return;
      end if;
      return Result : Ks_Ellipse do
         Result.Space_Name := Shape.Space_Name;
         Result.Data := Ellipse;
      end return;
   end Circle_Or_Ellipse;

   ---------------------------------------------------------------------
   --  CogRectangle
   ---------------------------------------------------------------------

   function X (Rectangle : Ks_Rectangle) return Real is (Rectangle.Data.X);
   function Y (Rectangle : Ks_Rectangle) return Real is (Rectangle.Data.Y);
   function Width (Rectangle : Ks_Rectangle) return Real is
     (Rectangle.Data.Width);
   function Height (Rectangle : Ks_Rectangle) return Real is
     (Rectangle.Data.Height);

   function Center_X (Rectangle : Ks_Rectangle) return Real is
      Center_X, Center_Y, Width, Height : Real;
   begin
      Rectangle.Get_Center_Width_Height (Center_X, Center_Y, Width, Height);
      return Center_X;
   end Center_X;

   function Center_Y (Rectangle : Ks_Rectangle) return Real is
      Center_X, Center_Y, Width, Height : Real;
   begin
      Rectangle.Get_Center_Width_Height (Center_X, Center_Y, Width, Height);
      return Center_Y;
   end Center_Y;

   procedure Set_X (Rectangle : in out Ks_Rectangle; Value : Real) is
   begin
      Rectangle.Set_XY_Width_Height
        (Value, Rectangle.Data.Y, Rectangle.Data.Width,
         Rectangle.Data.Height);
   end Set_X;

   procedure Set_Y (Rectangle : in out Ks_Rectangle; Value : Real) is
   begin
      Rectangle.Set_XY_Width_Height
        (Rectangle.Data.X, Value, Rectangle.Data.Width,
         Rectangle.Data.Height);
   end Set_Y;

   procedure Set_Width (Rectangle : in out Ks_Rectangle; Value : Real) is
   begin
      Rectangle.Set_XY_Width_Height
        (Rectangle.Data.X, Rectangle.Data.Y, Value, Rectangle.Data.Height);
   end Set_Width;

   procedure Set_Height (Rectangle : in out Ks_Rectangle; Value : Real) is
   begin
      Rectangle.Set_XY_Width_Height
        (Rectangle.Data.X, Rectangle.Data.Y, Rectangle.Data.Width, Value);
   end Set_Height;

   procedure Set_XY_Width_Height
     (Rectangle : in out Ks_Rectangle; X, Y, Width, Height : Real)
   is
      Result : K.Ks_Rectangle;
      Status : Ks_Status;
   begin
      K.Set_XY_Width_Height (X, Y, Width, Height, Result, Status);
      Check (Status);
      Rectangle.Data := Result;
   end Set_XY_Width_Height;

   procedure Get_XY_Width_Height
     (Rectangle : Ks_Rectangle; X, Y, Width, Height : out Real) is
   begin
      X := Rectangle.Data.X;
      Y := Rectangle.Data.Y;
      Width := Rectangle.Data.Width;
      Height := Rectangle.Data.Height;
   end Get_XY_Width_Height;

   procedure Set_Center_Width_Height
     (Rectangle : in out Ks_Rectangle;
      Center_X, Center_Y, Width, Height : Real)
   is
      Result : K.Ks_Rectangle;
      Status : Ks_Status;
   begin
      K.Set_Center_Width_Height
        (Center_X, Center_Y, Width, Height, Result, Status);
      Check (Status);
      Rectangle.Data := Result;
   end Set_Center_Width_Height;

   procedure Get_Center_Width_Height
     (Rectangle : Ks_Rectangle;
      Center_X, Center_Y, Width, Height : out Real)
   is
      Status : Ks_Status;
   begin
      K.Get_Center_Width_Height
        (Rectangle.Data, Center_X, Center_Y, Width, Height, Status);
      Check (Status);
   end Get_Center_Width_Height;

   overriding function Map
     (Shape     : Ks_Rectangle;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class
   is
      Result_Type : Int32;
      Rectangle   : K.Ks_Rectangle;
      Affine      : K.Ks_Rectangle_Affine;
      Status      : Ks_Status;
   begin
      K.Map (Shape.Data, To_Kernel (Transform), Result_Type, Rectangle,
             Affine, Status);
      Check (Status);
      return Rectangle_Or_Affine (Shape, Result_Type, Rectangle, Affine);
   end Map;

   overriding function Contains_Point
     (Region : Ks_Rectangle; X, Y : Real) return Boolean
   is
      Result : Int32;
      Status : Ks_Status;
   begin
      K.Contains_Point (Region.Data, X, Y, Result, Status);
      Check (Status);
      return Is_True (Result);
   end Contains_Point;

   overriding function Boundary_Slack (Region : Ks_Rectangle) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Boundary_Slack (Region.Data, Result, Status);
      Check (Status);
      return Result;
   end Boundary_Slack;

   overriding procedure Get_Bounding_Box
     (Region                     : Ks_Rectangle;
      Min_X, Min_Y, Max_X, Max_Y : out Real)
   is
      Status : Ks_Status;
   begin
      K.Get_Bounding_Box (Region.Data, Min_X, Min_Y, Max_X, Max_Y, Status);
      Check (Status);
   end Get_Bounding_Box;

   overriding function Area (Region : Ks_Rectangle) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Area (Region.Data, Result, Status);
      Check (Status);
      return Result;
   end Area;

   function Perimeter (Rectangle : Ks_Rectangle) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Perimeter (Rectangle.Data, Result, Status);
      Check (Status);
      return Result;
   end Perimeter;

   function Enclosing_Rectangle (Region : Ks_Region'Class) return Ks_Rectangle
   is
      Min_X, Min_Y, Max_X, Max_Y : Real;
      Status                     : Ks_Status;
   begin
      Region.Get_Bounding_Box (Min_X, Min_Y, Max_X, Max_Y);
      return Result : Ks_Rectangle do
         Result.Space_Name := Region.Space_Name;
         K.Rectangle_From_Bounding_Box
           (Min_X, Min_Y, Max_X, Max_Y, Result.Data, Status);
         Check (Status);
      end return;
   end Enclosing_Rectangle;

   ---------------------------------------------------------------------
   --  CogRectangleAffine
   ---------------------------------------------------------------------

   function Corners
     (Rectangle : Ks_Rectangle_Affine) return K.Ks_Rectangle_Affine_Corners;
   --  The four corners (kernel).

   function Corners
     (Rectangle : Ks_Rectangle_Affine) return K.Ks_Rectangle_Affine_Corners
   is
      Result : K.Ks_Rectangle_Affine_Corners;
      Status : Ks_Status;
   begin
      K.Get_Corners (Rectangle.Data, Result, Status);
      Check (Status);
      return Result;
   end Corners;

   function Center_X (Rectangle : Ks_Rectangle_Affine) return Real is
     (Rectangle.Data.Center_X);
   function Center_Y (Rectangle : Ks_Rectangle_Affine) return Real is
     (Rectangle.Data.Center_Y);
   function Side_X_Length (Rectangle : Ks_Rectangle_Affine) return Real is
     (Rectangle.Data.Side_X_Length);
   function Side_Y_Length (Rectangle : Ks_Rectangle_Affine) return Real is
     (Rectangle.Data.Side_Y_Length);
   function Rotation (Rectangle : Ks_Rectangle_Affine) return Real is
     (Rectangle.Data.Rotation);
   function Skew (Rectangle : Ks_Rectangle_Affine) return Real is
     (Rectangle.Data.Skew);

   procedure Set_Center_X
     (Rectangle : in out Ks_Rectangle_Affine; Value : Real)
   is
      D : K.Ks_Rectangle_Affine renames Rectangle.Data;
   begin
      Rectangle.Set_Center_Lengths_Rotation_Skew
        (Value, D.Center_Y, D.Side_X_Length, D.Side_Y_Length, D.Rotation,
         D.Skew);
   end Set_Center_X;

   procedure Set_Center_Y
     (Rectangle : in out Ks_Rectangle_Affine; Value : Real)
   is
      D : K.Ks_Rectangle_Affine renames Rectangle.Data;
   begin
      Rectangle.Set_Center_Lengths_Rotation_Skew
        (D.Center_X, Value, D.Side_X_Length, D.Side_Y_Length, D.Rotation,
         D.Skew);
   end Set_Center_Y;

   procedure Set_Side_X_Length
     (Rectangle : in out Ks_Rectangle_Affine; Value : Real)
   is
      D : K.Ks_Rectangle_Affine renames Rectangle.Data;
   begin
      Rectangle.Set_Center_Lengths_Rotation_Skew
        (D.Center_X, D.Center_Y, Value, D.Side_Y_Length, D.Rotation,
         D.Skew);
   end Set_Side_X_Length;

   procedure Set_Side_Y_Length
     (Rectangle : in out Ks_Rectangle_Affine; Value : Real)
   is
      D : K.Ks_Rectangle_Affine renames Rectangle.Data;
   begin
      Rectangle.Set_Center_Lengths_Rotation_Skew
        (D.Center_X, D.Center_Y, D.Side_X_Length, Value, D.Rotation,
         D.Skew);
   end Set_Side_Y_Length;

   procedure Set_Rotation
     (Rectangle : in out Ks_Rectangle_Affine; Value : Real)
   is
      D : K.Ks_Rectangle_Affine renames Rectangle.Data;
   begin
      Rectangle.Set_Center_Lengths_Rotation_Skew
        (D.Center_X, D.Center_Y, D.Side_X_Length, D.Side_Y_Length, Value,
         D.Skew);
   end Set_Rotation;

   procedure Set_Skew (Rectangle : in out Ks_Rectangle_Affine; Value : Real)
   is
      D : K.Ks_Rectangle_Affine renames Rectangle.Data;
   begin
      Rectangle.Set_Center_Lengths_Rotation_Skew
        (D.Center_X, D.Center_Y, D.Side_X_Length, D.Side_Y_Length,
         D.Rotation, Value);
   end Set_Skew;

   function Corner_Origin_X (Rectangle : Ks_Rectangle_Affine) return Real is
     (Corners (Rectangle).Origin_X);
   function Corner_Origin_Y (Rectangle : Ks_Rectangle_Affine) return Real is
     (Corners (Rectangle).Origin_Y);
   function Corner_X_X (Rectangle : Ks_Rectangle_Affine) return Real is
     (Corners (Rectangle).Corner_X_X);
   function Corner_X_Y (Rectangle : Ks_Rectangle_Affine) return Real is
     (Corners (Rectangle).Corner_X_Y);
   function Corner_Y_X (Rectangle : Ks_Rectangle_Affine) return Real is
     (Corners (Rectangle).Corner_Y_X);
   function Corner_Y_Y (Rectangle : Ks_Rectangle_Affine) return Real is
     (Corners (Rectangle).Corner_Y_Y);
   function Corner_Opposite_X (Rectangle : Ks_Rectangle_Affine) return Real
   is (Corners (Rectangle).Corner_Opposite_X);
   function Corner_Opposite_Y (Rectangle : Ks_Rectangle_Affine) return Real
   is (Corners (Rectangle).Corner_Opposite_Y);

   procedure Set_Center_Lengths_Rotation_Skew
     (Rectangle : in out Ks_Rectangle_Affine;
      Center_X, Center_Y, Side_X_Length, Side_Y_Length, Rotation, Skew : Real)
   is
      Result : K.Ks_Rectangle_Affine;
      Status : Ks_Status;
   begin
      K.Set_Center_Lengths_Rotation_Skew
        (Center_X, Center_Y, Side_X_Length, Side_Y_Length, Rotation, Skew,
         Result, Status);
      Check (Status);
      Rectangle.Data := Result;
   end Set_Center_Lengths_Rotation_Skew;

   procedure Get_Center_Lengths_Rotation_Skew
     (Rectangle : Ks_Rectangle_Affine;
      Center_X, Center_Y, Side_X_Length, Side_Y_Length, Rotation, Skew :
        out Real) is
   begin
      Center_X := Rectangle.Data.Center_X;
      Center_Y := Rectangle.Data.Center_Y;
      Side_X_Length := Rectangle.Data.Side_X_Length;
      Side_Y_Length := Rectangle.Data.Side_Y_Length;
      Rotation := Rectangle.Data.Rotation;
      Skew := Rectangle.Data.Skew;
   end Get_Center_Lengths_Rotation_Skew;

   procedure Set_Origin_Lengths_Rotation_Skew
     (Rectangle : in out Ks_Rectangle_Affine;
      Origin_X, Origin_Y, Side_X_Length, Side_Y_Length, Rotation, Skew : Real)
   is
      Result : K.Ks_Rectangle_Affine;
      Status : Ks_Status;
   begin
      K.Set_Origin_Lengths_Rotation_Skew
        (Origin_X, Origin_Y, Side_X_Length, Side_Y_Length, Rotation, Skew,
         Result, Status);
      Check (Status);
      Rectangle.Data := Result;
   end Set_Origin_Lengths_Rotation_Skew;

   procedure Get_Origin_Lengths_Rotation_Skew
     (Rectangle : Ks_Rectangle_Affine;
      Origin_X, Origin_Y, Side_X_Length, Side_Y_Length, Rotation, Skew :
        out Real)
   is
      C : constant K.Ks_Rectangle_Affine_Corners := Corners (Rectangle);
   begin
      Origin_X := C.Origin_X;
      Origin_Y := C.Origin_Y;
      Side_X_Length := Rectangle.Data.Side_X_Length;
      Side_Y_Length := Rectangle.Data.Side_Y_Length;
      Rotation := Rectangle.Data.Rotation;
      Skew := Rectangle.Data.Skew;
   end Get_Origin_Lengths_Rotation_Skew;

   procedure Set_Origin_Corner_X_Corner_Y
     (Rectangle : in out Ks_Rectangle_Affine;
      Origin_X, Origin_Y,
      Corner_X_X, Corner_X_Y, Corner_Y_X, Corner_Y_Y : Real)
   is
      Result : K.Ks_Rectangle_Affine;
      Status : Ks_Status;
   begin
      K.Set_Origin_Corner_X_Corner_Y
        (Origin_X, Origin_Y, Corner_X_X, Corner_X_Y, Corner_Y_X, Corner_Y_Y,
         Result, Status);
      Check (Status);
      Rectangle.Data := Result;
   end Set_Origin_Corner_X_Corner_Y;

   procedure Get_Origin_Corner_X_Corner_Y
     (Rectangle : Ks_Rectangle_Affine;
      Origin_X, Origin_Y, Corner_X_X, Corner_X_Y,
      Corner_Y_X, Corner_Y_Y : out Real)
   is
      C : constant K.Ks_Rectangle_Affine_Corners := Corners (Rectangle);
   begin
      Origin_X := C.Origin_X;
      Origin_Y := C.Origin_Y;
      Corner_X_X := C.Corner_X_X;
      Corner_X_Y := C.Corner_X_Y;
      Corner_Y_X := C.Corner_Y_X;
      Corner_Y_Y := C.Corner_Y_Y;
   end Get_Origin_Corner_X_Corner_Y;

   function Get_Parent_From_Child_Transform
     (Rectangle : Ks_Rectangle_Affine)
      return AMV.Transforms.Ks_Transform_2D_Linear
   is
      T      : KT.Ks_Transform_2D_Linear;
      Status : Ks_Status;
   begin
      K.Get_Parent_From_Child_Transform (Rectangle.Data, T, Status);
      Check (Status);
      return AMV.Transforms.Create
        (T.A, T.B, T.C, T.D, T.Translation_X, T.Translation_Y);
   end Get_Parent_From_Child_Transform;

   overriding function Map
     (Shape     : Ks_Rectangle_Affine;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class
   is
      Result : Ks_Rectangle_Affine := Shape;
      Status : Ks_Status;
   begin
      K.Map (Shape.Data, To_Kernel (Transform), Result.Data, Status);
      Check (Status);
      return Result;
   end Map;

   overriding function Contains_Point
     (Region : Ks_Rectangle_Affine; X, Y : Real) return Boolean
   is
      Result : Int32;
      Status : Ks_Status;
   begin
      K.Contains_Point (Region.Data, X, Y, Result, Status);
      Check (Status);
      return Is_True (Result);
   end Contains_Point;

   overriding function Boundary_Slack
     (Region : Ks_Rectangle_Affine) return Real
   is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Boundary_Slack (Region.Data, Result, Status);
      Check (Status);
      return Result;
   end Boundary_Slack;

   overriding procedure Get_Bounding_Box
     (Region                     : Ks_Rectangle_Affine;
      Min_X, Min_Y, Max_X, Max_Y : out Real)
   is
      Status : Ks_Status;
   begin
      K.Get_Bounding_Box (Region.Data, Min_X, Min_Y, Max_X, Max_Y, Status);
      Check (Status);
   end Get_Bounding_Box;

   overriding function Area (Region : Ks_Rectangle_Affine) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Area (Region.Data, Result, Status);
      Check (Status);
      return Result;
   end Area;

   ---------------------------------------------------------------------
   --  CogCircle
   ---------------------------------------------------------------------

   function Center_X (Circle : Ks_Circle) return Real is
     (Circle.Data.Center_X);
   function Center_Y (Circle : Ks_Circle) return Real is
     (Circle.Data.Center_Y);
   function Radius (Circle : Ks_Circle) return Real is (Circle.Data.Radius);

   procedure Set_Center_X (Circle : in out Ks_Circle; Value : Real) is
   begin
      Circle.Set_Center_Radius (Value, Circle.Data.Center_Y,
                                Circle.Data.Radius);
   end Set_Center_X;

   procedure Set_Center_Y (Circle : in out Ks_Circle; Value : Real) is
   begin
      Circle.Set_Center_Radius (Circle.Data.Center_X, Value,
                                Circle.Data.Radius);
   end Set_Center_Y;

   procedure Set_Radius (Circle : in out Ks_Circle; Value : Real) is
   begin
      Circle.Set_Center_Radius (Circle.Data.Center_X, Circle.Data.Center_Y,
                                Value);
   end Set_Radius;

   procedure Set_Center_Radius
     (Circle : in out Ks_Circle; Center_X, Center_Y, Radius : Real)
   is
      Result : K.Ks_Circle;
      Status : Ks_Status;
   begin
      K.Set_Center_Radius (Center_X, Center_Y, Radius, Result, Status);
      Check (Status);
      Circle.Data := Result;
   end Set_Center_Radius;

   procedure Get_Center_Radius
     (Circle : Ks_Circle; Center_X, Center_Y, Radius : out Real) is
   begin
      Center_X := Circle.Data.Center_X;
      Center_Y := Circle.Data.Center_Y;
      Radius := Circle.Data.Radius;
   end Get_Center_Radius;

   overriding function Map
     (Shape     : Ks_Circle;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class
   is
      Result_Type : Int32;
      Circle      : K.Ks_Circle;
      Ellipse     : K.Ks_Ellipse;
      Status      : Ks_Status;
   begin
      K.Map (Shape.Data, To_Kernel (Transform), Result_Type, Circle, Ellipse,
             Status);
      Check (Status);
      return Circle_Or_Ellipse (Shape, Result_Type, Circle, Ellipse);
   end Map;

   overriding function Contains_Point
     (Region : Ks_Circle; X, Y : Real) return Boolean
   is
      Result : Int32;
      Status : Ks_Status;
   begin
      K.Contains_Point (Region.Data, X, Y, Result, Status);
      Check (Status);
      return Is_True (Result);
   end Contains_Point;

   overriding function Boundary_Slack (Region : Ks_Circle) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Boundary_Slack (Region.Data, Result, Status);
      Check (Status);
      return Result;
   end Boundary_Slack;

   overriding procedure Get_Bounding_Box
     (Region                     : Ks_Circle;
      Min_X, Min_Y, Max_X, Max_Y : out Real)
   is
      Status : Ks_Status;
   begin
      K.Get_Bounding_Box (Region.Data, Min_X, Min_Y, Max_X, Max_Y, Status);
      Check (Status);
   end Get_Bounding_Box;

   overriding function Area (Region : Ks_Circle) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Area (Region.Data, Result, Status);
      Check (Status);
      return Result;
   end Area;

   ---------------------------------------------------------------------
   --  CogEllipse
   ---------------------------------------------------------------------

   function Center_X (Ellipse : Ks_Ellipse) return Real is
     (Ellipse.Data.Center_X);
   function Center_Y (Ellipse : Ks_Ellipse) return Real is
     (Ellipse.Data.Center_Y);
   function Radius_X (Ellipse : Ks_Ellipse) return Real is
     (Ellipse.Data.Radius_X);
   function Radius_Y (Ellipse : Ks_Ellipse) return Real is
     (Ellipse.Data.Radius_Y);
   function Rotation (Ellipse : Ks_Ellipse) return Real is
     (Ellipse.Data.Rotation);

   procedure Set_Center_X (Ellipse : in out Ks_Ellipse; Value : Real) is
      D : K.Ks_Ellipse renames Ellipse.Data;
   begin
      Ellipse.Set_Center_XY_Radius_XY_Rotation
        (Value, D.Center_Y, D.Radius_X, D.Radius_Y, D.Rotation);
   end Set_Center_X;

   procedure Set_Center_Y (Ellipse : in out Ks_Ellipse; Value : Real) is
      D : K.Ks_Ellipse renames Ellipse.Data;
   begin
      Ellipse.Set_Center_XY_Radius_XY_Rotation
        (D.Center_X, Value, D.Radius_X, D.Radius_Y, D.Rotation);
   end Set_Center_Y;

   procedure Set_Radius_X (Ellipse : in out Ks_Ellipse; Value : Real) is
      D : K.Ks_Ellipse renames Ellipse.Data;
   begin
      Ellipse.Set_Center_XY_Radius_XY_Rotation
        (D.Center_X, D.Center_Y, Value, D.Radius_Y, D.Rotation);
   end Set_Radius_X;

   procedure Set_Radius_Y (Ellipse : in out Ks_Ellipse; Value : Real) is
      D : K.Ks_Ellipse renames Ellipse.Data;
   begin
      Ellipse.Set_Center_XY_Radius_XY_Rotation
        (D.Center_X, D.Center_Y, D.Radius_X, Value, D.Rotation);
   end Set_Radius_Y;

   procedure Set_Rotation (Ellipse : in out Ks_Ellipse; Value : Real) is
      D : K.Ks_Ellipse renames Ellipse.Data;
   begin
      Ellipse.Set_Center_XY_Radius_XY_Rotation
        (D.Center_X, D.Center_Y, D.Radius_X, D.Radius_Y, Value);
   end Set_Rotation;

   procedure Set_Center_XY_Radius_XY_Rotation
     (Ellipse : in out Ks_Ellipse;
      Center_X, Center_Y, Radius_X, Radius_Y, Rotation : Real)
   is
      Result : K.Ks_Ellipse;
      Status : Ks_Status;
   begin
      K.Set_Center_XY_Radius_XY_Rotation
        (Center_X, Center_Y, Radius_X, Radius_Y, Rotation, Result, Status);
      Check (Status);
      Ellipse.Data := Result;
   end Set_Center_XY_Radius_XY_Rotation;

   procedure Get_Center_XY_Radius_XY_Rotation
     (Ellipse : Ks_Ellipse;
      Center_X, Center_Y, Radius_X, Radius_Y, Rotation : out Real) is
   begin
      Center_X := Ellipse.Data.Center_X;
      Center_Y := Ellipse.Data.Center_Y;
      Radius_X := Ellipse.Data.Radius_X;
      Radius_Y := Ellipse.Data.Radius_Y;
      Rotation := Ellipse.Data.Rotation;
   end Get_Center_XY_Radius_XY_Rotation;

   overriding function Map
     (Shape     : Ks_Ellipse;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class
   is
      Result : Ks_Ellipse := Shape;
      Status : Ks_Status;
   begin
      K.Map (Shape.Data, To_Kernel (Transform), Result.Data, Status);
      Check (Status);
      return Result;
   end Map;

   overriding function Contains_Point
     (Region : Ks_Ellipse; X, Y : Real) return Boolean
   is
      Result : Int32;
      Status : Ks_Status;
   begin
      K.Contains_Point (Region.Data, X, Y, Result, Status);
      Check (Status);
      return Is_True (Result);
   end Contains_Point;

   overriding function Boundary_Slack (Region : Ks_Ellipse) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Boundary_Slack (Region.Data, Result, Status);
      Check (Status);
      return Result;
   end Boundary_Slack;

   overriding procedure Get_Bounding_Box
     (Region                     : Ks_Ellipse;
      Min_X, Min_Y, Max_X, Max_Y : out Real)
   is
      Status : Ks_Status;
   begin
      K.Get_Bounding_Box (Region.Data, Min_X, Min_Y, Max_X, Max_Y, Status);
      Check (Status);
   end Get_Bounding_Box;

   overriding function Area (Region : Ks_Ellipse) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Area (Region.Data, Result, Status);
      Check (Status);
      return Result;
   end Area;

   ---------------------------------------------------------------------
   --  CogPolygon
   ---------------------------------------------------------------------

   overriding procedure Adjust (Vertices : in out Polygon_Vertices) is
      Source : constant K.Ks_Polygon := Vertices.Handle;
      Status : Ks_Status;
   begin
      --  The copy shares the source's handle until it has its own; it
      --  must not keep it if the duplicate cannot be made.
      Vertices.Handle := null;
      K.Duplicate (Source, Vertices.Handle, Status);
      Check (Status);
   end Adjust;

   overriding procedure Finalize (Vertices : in out Polygon_Vertices) is
      Status : Ks_Status;
   begin
      K.Destroy (Vertices.Handle, Status);
   end Finalize;

   overriding function "=" (Left, Right : Polygon_Vertices) return Boolean
   is (K.Same_Vertices (Left.Handle, Right.Handle));

   procedure Write_Vertices
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : Polygon_Vertices)
   is
      Count  : Int32;
      X, Y   : Real;
      Status : Ks_Status;
   begin
      K.Num_Vertices (Item.Handle, Count, Status);
      Check (Status);
      U32'Write (Stream, U32 (Count));
      for Index in 0 .. Count - 1 loop  --  SHELL: stream I/O, every vertex
         K.Get_Vertex (Item.Handle, Index, X, Y, Status);
         Check (Status);
         Real'Write (Stream, X);
         Real'Write (Stream, Y);
      end loop;  --  SHELL: (the loop above)
   end Write_Vertices;

   procedure Swap (Left, Right : in out Polygon_Vertices);
   --  Exchanges the handles of Left and Right.

   procedure Swap (Left, Right : in out Polygon_Vertices) is
      Left_Handle : constant K.Ks_Polygon := Left.Handle;
   begin
      Left.Handle := Right.Handle;
      Right.Handle := Left_Handle;
   end Swap;

   procedure Read_Vertices
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Polygon_Vertices)
   is
      Fresh  : Polygon_Vertices;
      Count  : U32;
      X, Y   : Real;
      Status : Ks_Status;
   begin
      U32'Read (Stream, Count);
      K.Check_Stream_Count (Count, Status);
      Check (Status);
      --  Fresh owns the vertices read so far, so that a failure frees
      --  them and leaves Item unchanged.
      for Index in 1 .. Count loop  --  SHELL: stream I/O, every vertex
         Real'Read (Stream, X);
         Real'Read (Stream, Y);
         K.Add_Vertex (Fresh.Handle, X, Y, K.Append_Index, Status);
         Check (Status);
      end loop;  --  SHELL: (the loop above)
      --  Item takes the vertices read; Fresh frees the old ones.
      Swap (Item, Fresh);
   end Read_Vertices;

   function Num_Vertices (Polygon : Ks_Polygon) return Natural is
      Result : Int32;
      Status : Ks_Status;
   begin
      K.Num_Vertices (Polygon.Vertices.Handle, Result, Status);
      Check (Status);
      return Natural (Result);
   end Num_Vertices;

   procedure Get_Vertex
     (Polygon : Ks_Polygon; Index : Natural; X, Y : out Real)
   is
      Status : Ks_Status;
   begin
      K.Get_Vertex (Polygon.Vertices.Handle, Int32 (Index), X, Y, Status);
      Check (Status);
   end Get_Vertex;

   function Get_Vertex_X (Polygon : Ks_Polygon; Index : Natural) return Real
   is
      X, Y : Real;
   begin
      Polygon.Get_Vertex (Index, X, Y);
      return X;
   end Get_Vertex_X;

   function Get_Vertex_Y (Polygon : Ks_Polygon; Index : Natural) return Real
   is
      X, Y : Real;
   begin
      Polygon.Get_Vertex (Index, X, Y);
      return Y;
   end Get_Vertex_Y;

   procedure Set_Vertex
     (Polygon : in out Ks_Polygon; Index : Natural; X, Y : Real)
   is
      Status : Ks_Status;
   begin
      K.Set_Vertex (Polygon.Vertices.Handle, Int32 (Index), X, Y, Status);
      Check (Status);
   end Set_Vertex;

   procedure Add_Vertex
     (Polygon : in out Ks_Polygon;
      X, Y    : Real;
      Index   : Integer := -1)  --  SHELL: the default of the spec
   is
      Status : Ks_Status;
   begin
      K.Add_Vertex (Polygon.Vertices.Handle, X, Y, Int32 (Index), Status);
      Check (Status);
   end Add_Vertex;

   procedure Remove_Vertex (Polygon : in out Ks_Polygon; Index : Natural) is
      Status : Ks_Status;
   begin
      K.Remove_Vertex (Polygon.Vertices.Handle, Int32 (Index), Status);
      Check (Status);
   end Remove_Vertex;

   procedure Clear (Polygon : in out Ks_Polygon) is
      Status : Ks_Status;
   begin
      K.Clear (Polygon.Vertices.Handle, Status);
      Check (Status);
   end Clear;

   overriding function Map
     (Shape     : Ks_Polygon;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class
   is
      Mapped : K.Ks_Polygon;
      Status : Ks_Status;
   begin
      K.Map (Shape.Vertices.Handle, To_Kernel (Transform), Mapped, Status);
      Check (Status);
      return Result : Ks_Polygon do
         Result.Space_Name := Shape.Space_Name;
         Result.Vertices.Handle := Mapped;
      end return;
   end Map;

   overriding function Contains_Point
     (Region : Ks_Polygon; X, Y : Real) return Boolean
   is
      Result : Int32;
      Status : Ks_Status;
   begin
      K.Contains_Point (Region.Vertices.Handle, X, Y, Result, Status);
      Check (Status);
      return Is_True (Result);
   end Contains_Point;

   overriding procedure Get_Bounding_Box
     (Region                     : Ks_Polygon;
      Min_X, Min_Y, Max_X, Max_Y : out Real)
   is
      Status : Ks_Status;
   begin
      K.Get_Bounding_Box
        (Region.Vertices.Handle, Min_X, Min_Y, Max_X, Max_Y, Status);
      Check (Status);
   end Get_Bounding_Box;

   overriding function Boundary_Slack (Region : Ks_Polygon) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Boundary_Slack (Region.Vertices.Handle, Result, Status);
      Check (Status);
      return Result;
   end Boundary_Slack;

   function Perimeter (Polygon : Ks_Polygon) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Perimeter (Polygon.Vertices.Handle, Result, Status);
      Check (Status);
      return Result;
   end Perimeter;

   overriding function Area (Region : Ks_Polygon) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Area (Region.Vertices.Handle, Result, Status);
      Check (Status);
      return Result;
   end Area;

   ---------------------------------------------------------------------
   --  CogCircularAnnulusSection
   ---------------------------------------------------------------------

   function Center_X (Section : Ks_Circular_Annulus_Section) return Real is
     (Section.Data.Center_X);
   function Center_Y (Section : Ks_Circular_Annulus_Section) return Real is
     (Section.Data.Center_Y);
   function Radius (Section : Ks_Circular_Annulus_Section) return Real is
     (Section.Data.Radius);
   function Radial_Scale
     (Section : Ks_Circular_Annulus_Section) return Real is
     (Section.Data.Radial_Scale);
   function Angle_Start
     (Section : Ks_Circular_Annulus_Section) return Real is
     (Section.Data.Angle_Start);
   function Angle_Span
     (Section : Ks_Circular_Annulus_Section) return Real is
     (Section.Data.Angle_Span);

   procedure Set_Center_X
     (Section : in out Ks_Circular_Annulus_Section; Value : Real)
   is
      D : K.Ks_Circular_Annulus_Section renames Section.Data;
   begin
      Section.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (Value, D.Center_Y, D.Radius, D.Angle_Start, D.Angle_Span,
         D.Radial_Scale);
   end Set_Center_X;

   procedure Set_Center_Y
     (Section : in out Ks_Circular_Annulus_Section; Value : Real)
   is
      D : K.Ks_Circular_Annulus_Section renames Section.Data;
   begin
      Section.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (D.Center_X, Value, D.Radius, D.Angle_Start, D.Angle_Span,
         D.Radial_Scale);
   end Set_Center_Y;

   procedure Set_Radius
     (Section : in out Ks_Circular_Annulus_Section; Value : Real)
   is
      D : K.Ks_Circular_Annulus_Section renames Section.Data;
   begin
      Section.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (D.Center_X, D.Center_Y, Value, D.Angle_Start, D.Angle_Span,
         D.Radial_Scale);
   end Set_Radius;

   procedure Set_Radial_Scale
     (Section : in out Ks_Circular_Annulus_Section; Value : Real)
   is
      D : K.Ks_Circular_Annulus_Section renames Section.Data;
   begin
      Section.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (D.Center_X, D.Center_Y, D.Radius, D.Angle_Start, D.Angle_Span,
         Value);
   end Set_Radial_Scale;

   procedure Set_Angle_Start
     (Section : in out Ks_Circular_Annulus_Section; Value : Real)
   is
      D : K.Ks_Circular_Annulus_Section renames Section.Data;
   begin
      Section.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (D.Center_X, D.Center_Y, D.Radius, Value, D.Angle_Span,
         D.Radial_Scale);
   end Set_Angle_Start;

   procedure Set_Angle_Span
     (Section : in out Ks_Circular_Annulus_Section; Value : Real)
   is
      D : K.Ks_Circular_Annulus_Section renames Section.Data;
   begin
      Section.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (D.Center_X, D.Center_Y, D.Radius, D.Angle_Start, Value,
         D.Radial_Scale);
   end Set_Angle_Span;

   procedure Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
     (Section : in out Ks_Circular_Annulus_Section;
      Center_X, Center_Y, Radius, Angle_Start, Angle_Span, Radial_Scale : Real)
   is
      Result : K.Ks_Circular_Annulus_Section;
      Status : Ks_Status;
   begin
      K.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
        (Center_X, Center_Y, Radius, Angle_Start, Angle_Span, Radial_Scale,
         Result, Status);
      Check (Status);
      Section.Data := Result;
   end Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale;

   procedure Get_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
     (Section : Ks_Circular_Annulus_Section;
      Center_X, Center_Y, Radius, Angle_Start, Angle_Span,
      Radial_Scale : out Real) is
   begin
      Center_X := Section.Data.Center_X;
      Center_Y := Section.Data.Center_Y;
      Radius := Section.Data.Radius;
      Angle_Start := Section.Data.Angle_Start;
      Angle_Span := Section.Data.Angle_Span;
      Radial_Scale := Section.Data.Radial_Scale;
   end Get_Center_Radius_Angle_Start_Angle_Span_Radial_Scale;

   overriding function Map
     (Shape     : Ks_Circular_Annulus_Section;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class
   is
      Result : Ks_Circular_Annulus_Section := Shape;
      Status : Ks_Status;
   begin
      K.Map (Shape.Data, To_Kernel (Transform), Result.Data, Status);
      Check (Status);
      return Result;
   end Map;

   overriding function Contains_Point
     (Region : Ks_Circular_Annulus_Section; X, Y : Real) return Boolean
   is
      Result : Int32;
      Status : Ks_Status;
   begin
      K.Contains_Point (Region.Data, X, Y, Result, Status);
      Check (Status);
      return Is_True (Result);
   end Contains_Point;

   overriding function Boundary_Slack
     (Region : Ks_Circular_Annulus_Section) return Real
   is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Boundary_Slack (Region.Data, Result, Status);
      Check (Status);
      return Result;
   end Boundary_Slack;

   overriding procedure Get_Bounding_Box
     (Region                     : Ks_Circular_Annulus_Section;
      Min_X, Min_Y, Max_X, Max_Y : out Real)
   is
      Status : Ks_Status;
   begin
      K.Get_Bounding_Box (Region.Data, Min_X, Min_Y, Max_X, Max_Y, Status);
      Check (Status);
   end Get_Bounding_Box;

   overriding function Area
     (Region : Ks_Circular_Annulus_Section) return Real
   is
      Result : Real;
      Status : Ks_Status;
   begin
      K.Area (Region.Data, Result, Status);
      Check (Status);
      return Result;
   end Area;

   ---------------------------------------------------------------------
   --  CogLineSegment
   ---------------------------------------------------------------------

   function Start_X (Segment : Ks_Line_Segment) return Real is
     (Segment.Data.Start_X);
   function Start_Y (Segment : Ks_Line_Segment) return Real is
     (Segment.Data.Start_Y);
   function End_X (Segment : Ks_Line_Segment) return Real is
     (Segment.Data.End_X);
   function End_Y (Segment : Ks_Line_Segment) return Real is
     (Segment.Data.End_Y);

   function Length (Segment : Ks_Line_Segment) return Real is
      Start_X, Start_Y, Length, Rotation : Real;
   begin
      Segment.Get_Start_Length_Rotation (Start_X, Start_Y, Length, Rotation);
      return Length;
   end Length;

   function Rotation (Segment : Ks_Line_Segment) return Real is
      Start_X, Start_Y, Length, Rotation : Real;
   begin
      Segment.Get_Start_Length_Rotation (Start_X, Start_Y, Length, Rotation);
      return Rotation;
   end Rotation;

   procedure Get_Midpoint (Segment : Ks_Line_Segment; X, Y : out Real);
   --  MidpointX and MidpointY (kernel).

   procedure Get_Midpoint (Segment : Ks_Line_Segment; X, Y : out Real) is
      Status : Ks_Status;
   begin
      K.Get_Midpoint (Segment.Data, X, Y, Status);
      Check (Status);
   end Get_Midpoint;

   function Midpoint_X (Segment : Ks_Line_Segment) return Real is
      X, Y : Real;
   begin
      Get_Midpoint (Segment, X, Y);
      return X;
   end Midpoint_X;

   function Midpoint_Y (Segment : Ks_Line_Segment) return Real is
      X, Y : Real;
   begin
      Get_Midpoint (Segment, X, Y);
      return Y;
   end Midpoint_Y;

   procedure Set_Start_X (Segment : in out Ks_Line_Segment; Value : Real) is
      D : K.Ks_Line_Segment renames Segment.Data;
   begin
      Segment.Set_Start_End (Value, D.Start_Y, D.End_X, D.End_Y);
   end Set_Start_X;

   procedure Set_Start_Y (Segment : in out Ks_Line_Segment; Value : Real) is
      D : K.Ks_Line_Segment renames Segment.Data;
   begin
      Segment.Set_Start_End (D.Start_X, Value, D.End_X, D.End_Y);
   end Set_Start_Y;

   procedure Set_End_X (Segment : in out Ks_Line_Segment; Value : Real) is
      D : K.Ks_Line_Segment renames Segment.Data;
   begin
      Segment.Set_Start_End (D.Start_X, D.Start_Y, Value, D.End_Y);
   end Set_End_X;

   procedure Set_End_Y (Segment : in out Ks_Line_Segment; Value : Real) is
      D : K.Ks_Line_Segment renames Segment.Data;
   begin
      Segment.Set_Start_End (D.Start_X, D.Start_Y, D.End_X, Value);
   end Set_End_Y;

   procedure Set_Start_End
     (Segment : in out Ks_Line_Segment; Start_X, Start_Y, End_X, End_Y : Real)
   is
      Result : K.Ks_Line_Segment;
      Status : Ks_Status;
   begin
      K.Set_Start_End (Start_X, Start_Y, End_X, End_Y, Result, Status);
      Check (Status);
      Segment.Data := Result;
   end Set_Start_End;

   procedure Get_Start_End
     (Segment : Ks_Line_Segment;
      Start_X, Start_Y, End_X, End_Y : out Real) is
   begin
      Start_X := Segment.Data.Start_X;
      Start_Y := Segment.Data.Start_Y;
      End_X := Segment.Data.End_X;
      End_Y := Segment.Data.End_Y;
   end Get_Start_End;

   procedure Set_Start_Length_Rotation
     (Segment : in out Ks_Line_Segment;
      Start_X, Start_Y, Length, Rotation : Real)
   is
      Result : K.Ks_Line_Segment;
      Status : Ks_Status;
   begin
      K.Set_Start_Length_Rotation
        (Start_X, Start_Y, Length, Rotation, Result, Status);
      Check (Status);
      Segment.Data := Result;
   end Set_Start_Length_Rotation;

   procedure Get_Start_Length_Rotation
     (Segment : Ks_Line_Segment;
      Start_X, Start_Y, Length, Rotation : out Real)
   is
      Status : Ks_Status;
   begin
      K.Get_Start_Length_Rotation
        (Segment.Data, Start_X, Start_Y, Length, Rotation, Status);
      Check (Status);
   end Get_Start_Length_Rotation;

   overriding function Map
     (Shape     : Ks_Line_Segment;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class
   is
      Result : Ks_Line_Segment := Shape;
      Status : Ks_Status;
   begin
      K.Map (Shape.Data, To_Kernel (Transform), Result.Data, Status);
      Check (Status);
      return Result;
   end Map;

   ---------------------------------------------------------------------
   --  CogLine
   ---------------------------------------------------------------------

   function X (Line : Ks_Line) return Real is (Line.Data.X);
   function Y (Line : Ks_Line) return Real is (Line.Data.Y);
   function Rotation (Line : Ks_Line) return Real is (Line.Data.Rotation);

   procedure Set_X (Line : in out Ks_Line; Value : Real) is
   begin
      Line.Set_XY_Rotation (Value, Line.Data.Y, Line.Data.Rotation);
   end Set_X;

   procedure Set_Y (Line : in out Ks_Line; Value : Real) is
   begin
      Line.Set_XY_Rotation (Line.Data.X, Value, Line.Data.Rotation);
   end Set_Y;

   procedure Set_Rotation (Line : in out Ks_Line; Value : Real) is
   begin
      Line.Set_XY_Rotation (Line.Data.X, Line.Data.Y, Value);
   end Set_Rotation;

   procedure Set_XY_Rotation (Line : in out Ks_Line; X, Y, Rotation : Real)
   is
      Result : K.Ks_Line;
      Status : Ks_Status;
   begin
      K.Set_XY_Rotation (X, Y, Rotation, Result, Status);
      Check (Status);
      Line.Data := Result;
   end Set_XY_Rotation;

   procedure Get_XY_Rotation (Line : Ks_Line; X, Y, Rotation : out Real) is
   begin
      X := Line.Data.X;
      Y := Line.Data.Y;
      Rotation := Line.Data.Rotation;
   end Get_XY_Rotation;

   procedure Set_From_Start_XY_End_XY
     (Line : in out Ks_Line; Start_X, Start_Y, End_X, End_Y : Real)
   is
      Result : K.Ks_Line;
      Status : Ks_Status;
   begin
      K.Set_From_Start_XY_End_XY
        (Start_X, Start_Y, End_X, End_Y, Result, Status);
      Check (Status);
      Line.Data := Result;
   end Set_From_Start_XY_End_XY;

   procedure Set_From_Line_Segment
     (Line : in out Ks_Line; Segment : Ks_Line_Segment'Class)
   is
      Result : K.Ks_Line;
      Status : Ks_Status;
   begin
      K.Set_From_Line_Segment (Segment.Data, Result, Status);
      Check (Status);
      Line.Data := Result;
   end Set_From_Line_Segment;

   procedure Set_Distance_Rotation
     (Line : in out Ks_Line; Distance, Rotation : Real)
   is
      Result : K.Ks_Line;
      Status : Ks_Status;
   begin
      K.Set_Distance_Rotation (Distance, Rotation, Result, Status);
      Check (Status);
      Line.Data := Result;
   end Set_Distance_Rotation;

   procedure Get_Distance_Rotation
     (Line : Ks_Line; Distance, Rotation : out Real)
   is
      Status : Ks_Status;
   begin
      K.Get_Distance_Rotation (Line.Data, Distance, Rotation, Status);
      Check (Status);
   end Get_Distance_Rotation;

   overriding function Map
     (Shape     : Ks_Line;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class
   is
      Result : Ks_Line := Shape;
      Status : Ks_Status;
   begin
      K.Map (Shape.Data, To_Kernel (Transform), Result.Data, Status);
      Check (Status);
      return Result;
   end Map;

   ---------------------------------------------------------------------
   --  CogPointMarker
   ---------------------------------------------------------------------

   function X (Marker : Ks_Point_Marker) return Real is (Marker.Data.X);
   function Y (Marker : Ks_Point_Marker) return Real is (Marker.Data.Y);
   function Rotation (Marker : Ks_Point_Marker) return Real is
     (Marker.Data.Rotation);

   procedure Set_XY_Rotation
     (Marker : in out Ks_Point_Marker; X, Y, Rotation : Real);
   --  The three properties together (kernel).

   procedure Set_XY_Rotation
     (Marker : in out Ks_Point_Marker; X, Y, Rotation : Real)
   is
      Result : K.Ks_Point_Marker;
      Status : Ks_Status;
   begin
      K.Set_XY_Rotation (X, Y, Rotation, Result, Status);
      Check (Status);
      Marker.Data := Result;
   end Set_XY_Rotation;

   procedure Set_X (Marker : in out Ks_Point_Marker; Value : Real) is
   begin
      Set_XY_Rotation (Marker, Value, Marker.Data.Y, Marker.Data.Rotation);
   end Set_X;

   procedure Set_Y (Marker : in out Ks_Point_Marker; Value : Real) is
   begin
      Set_XY_Rotation (Marker, Marker.Data.X, Value, Marker.Data.Rotation);
   end Set_Y;

   procedure Set_Rotation (Marker : in out Ks_Point_Marker; Value : Real) is
   begin
      Set_XY_Rotation (Marker, Marker.Data.X, Marker.Data.Y, Value);
   end Set_Rotation;

   overriding function Map
     (Shape     : Ks_Point_Marker;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class
   is
      Result : Ks_Point_Marker := Shape;
      Status : Ks_Status;
   begin
      K.Map (Shape.Data, To_Kernel (Transform), Result.Data, Status);
      Check (Status);
      return Result;
   end Map;

   ---------------------------------------------------------------------
   --  CogCircularArc
   ---------------------------------------------------------------------

   procedure Get_Start_End
     (Arc : Ks_Circular_Arc; Start_X, Start_Y, End_X, End_Y : out Real);
   --  The end points (kernel).

   procedure Get_Start_End
     (Arc : Ks_Circular_Arc; Start_X, Start_Y, End_X, End_Y : out Real)
   is
      Status : Ks_Status;
   begin
      K.Get_Start_End (Arc.Data, Start_X, Start_Y, End_X, End_Y, Status);
      Check (Status);
   end Get_Start_End;

   function Center_X (Arc : Ks_Circular_Arc) return Real is
     (Arc.Data.Center_X);
   function Center_Y (Arc : Ks_Circular_Arc) return Real is
     (Arc.Data.Center_Y);
   function Radius (Arc : Ks_Circular_Arc) return Real is (Arc.Data.Radius);
   function Angle_Start (Arc : Ks_Circular_Arc) return Real is
     (Arc.Data.Angle_Start);
   function Angle_Span (Arc : Ks_Circular_Arc) return Real is
     (Arc.Data.Angle_Span);

   function Start_X (Arc : Ks_Circular_Arc) return Real is
      Start_X, Start_Y, End_X, End_Y : Real;
   begin
      Get_Start_End (Arc, Start_X, Start_Y, End_X, End_Y);
      return Start_X;
   end Start_X;

   function Start_Y (Arc : Ks_Circular_Arc) return Real is
      Start_X, Start_Y, End_X, End_Y : Real;
   begin
      Get_Start_End (Arc, Start_X, Start_Y, End_X, End_Y);
      return Start_Y;
   end Start_Y;

   function End_X (Arc : Ks_Circular_Arc) return Real is
      Start_X, Start_Y, End_X, End_Y : Real;
   begin
      Get_Start_End (Arc, Start_X, Start_Y, End_X, End_Y);
      return End_X;
   end End_X;

   function End_Y (Arc : Ks_Circular_Arc) return Real is
      Start_X, Start_Y, End_X, End_Y : Real;
   begin
      Get_Start_End (Arc, Start_X, Start_Y, End_X, End_Y);
      return End_Y;
   end End_Y;

   procedure Set_Center_X (Arc : in out Ks_Circular_Arc; Value : Real) is
      D : K.Ks_Circular_Arc renames Arc.Data;
   begin
      Arc.Set_Center_Radius_Angle_Start_Angle_Span
        (Value, D.Center_Y, D.Radius, D.Angle_Start, D.Angle_Span);
   end Set_Center_X;

   procedure Set_Center_Y (Arc : in out Ks_Circular_Arc; Value : Real) is
      D : K.Ks_Circular_Arc renames Arc.Data;
   begin
      Arc.Set_Center_Radius_Angle_Start_Angle_Span
        (D.Center_X, Value, D.Radius, D.Angle_Start, D.Angle_Span);
   end Set_Center_Y;

   procedure Set_Radius (Arc : in out Ks_Circular_Arc; Value : Real) is
      D : K.Ks_Circular_Arc renames Arc.Data;
   begin
      Arc.Set_Center_Radius_Angle_Start_Angle_Span
        (D.Center_X, D.Center_Y, Value, D.Angle_Start, D.Angle_Span);
   end Set_Radius;

   procedure Set_Angle_Start (Arc : in out Ks_Circular_Arc; Value : Real) is
      D : K.Ks_Circular_Arc renames Arc.Data;
   begin
      Arc.Set_Center_Radius_Angle_Start_Angle_Span
        (D.Center_X, D.Center_Y, D.Radius, Value, D.Angle_Span);
   end Set_Angle_Start;

   procedure Set_Angle_Span (Arc : in out Ks_Circular_Arc; Value : Real) is
      D : K.Ks_Circular_Arc renames Arc.Data;
   begin
      Arc.Set_Center_Radius_Angle_Start_Angle_Span
        (D.Center_X, D.Center_Y, D.Radius, D.Angle_Start, Value);
   end Set_Angle_Span;

   procedure Set_Center_Radius_Angle_Start_Angle_Span
     (Arc : in out Ks_Circular_Arc;
      Center_X, Center_Y, Radius, Angle_Start, Angle_Span : Real)
   is
      Result : K.Ks_Circular_Arc;
      Status : Ks_Status;
   begin
      K.Set_Center_Radius_Angle_Start_Angle_Span
        (Center_X, Center_Y, Radius, Angle_Start, Angle_Span, Result,
         Status);
      Check (Status);
      Arc.Data := Result;
   end Set_Center_Radius_Angle_Start_Angle_Span;

   procedure Get_Center_Radius_Angle_Start_Angle_Span
     (Arc : Ks_Circular_Arc;
      Center_X, Center_Y, Radius, Angle_Start, Angle_Span : out Real) is
   begin
      Center_X := Arc.Data.Center_X;
      Center_Y := Arc.Data.Center_Y;
      Radius := Arc.Data.Radius;
      Angle_Start := Arc.Data.Angle_Start;
      Angle_Span := Arc.Data.Angle_Span;
   end Get_Center_Radius_Angle_Start_Angle_Span;

   overriding function Map
     (Shape     : Ks_Circular_Arc;
      Transform : AMV.Transforms.Ks_Transform_2D_Linear)
      return Ks_Shape'Class
   is
      Result : Ks_Circular_Arc := Shape;
      Status : Ks_Status;
   begin
      K.Map (Shape.Data, To_Kernel (Transform), Result.Data, Status);
      Check (Status);
      return Result;
   end Map;


   ---------------------------------------------------------------------
   --  Stream attributes of the concrete shapes (see the private part)
   ---------------------------------------------------------------------

   procedure Read_Rectangle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Rectangle)
   is
      Fresh : Ks_Rectangle;
   begin
      Ks_Region'Read (Stream, Ks_Region (Fresh));
      K.Ks_Rectangle'Read (Stream, Fresh.Data);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Rectangle'Read");
   end Read_Rectangle;

   procedure Read_Rectangle_Affine
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Rectangle_Affine)
   is
      Fresh : Ks_Rectangle_Affine;
   begin
      Ks_Region'Read (Stream, Ks_Region (Fresh));
      K.Ks_Rectangle_Affine'Read (Stream, Fresh.Data);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Rectangle_Affine'Read");
   end Read_Rectangle_Affine;

   procedure Read_Circle
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Circle)
   is
      Fresh : Ks_Circle;
   begin
      Ks_Region'Read (Stream, Ks_Region (Fresh));
      K.Ks_Circle'Read (Stream, Fresh.Data);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Circle'Read");
   end Read_Circle;

   procedure Read_Ellipse
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Ellipse)
   is
      Fresh : Ks_Ellipse;
   begin
      Ks_Region'Read (Stream, Ks_Region (Fresh));
      K.Ks_Ellipse'Read (Stream, Fresh.Data);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Ellipse'Read");
   end Read_Ellipse;

   procedure Read_Polygon
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Polygon)
   is
      Fresh : Ks_Polygon;
   begin
      Ks_Region'Read (Stream, Ks_Region (Fresh));
      Polygon_Vertices'Read (Stream, Fresh.Vertices);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Polygon'Read");
   end Read_Polygon;

   procedure Read_Circular_Annulus_Section
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Circular_Annulus_Section)
   is
      Fresh : Ks_Circular_Annulus_Section;
   begin
      Ks_Region'Read (Stream, Ks_Region (Fresh));
      K.Ks_Circular_Annulus_Section'Read (Stream, Fresh.Data);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Circular_Annulus_Section'Read");
   end Read_Circular_Annulus_Section;

   procedure Read_Line_Segment
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Line_Segment)
   is
      Fresh : Ks_Line_Segment;
   begin
      Ks_Shape'Read (Stream, Ks_Shape (Fresh));
      K.Ks_Line_Segment'Read (Stream, Fresh.Data);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Line_Segment'Read");
   end Read_Line_Segment;

   procedure Read_Line
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Line)
   is
      Fresh : Ks_Line;
   begin
      Ks_Shape'Read (Stream, Ks_Shape (Fresh));
      K.Ks_Line'Read (Stream, Fresh.Data);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Line'Read");
   end Read_Line;

   procedure Read_Point_Marker
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Point_Marker)
   is
      Fresh : Ks_Point_Marker;
   begin
      Ks_Shape'Read (Stream, Ks_Shape (Fresh));
      K.Ks_Point_Marker'Read (Stream, Fresh.Data);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Point_Marker'Read");
   end Read_Point_Marker;

   procedure Read_Circular_Arc
     (Stream : not null access Ada.Streams.Root_Stream_Type'Class;
      Item   : out Ks_Circular_Arc)
   is
      Fresh : Ks_Circular_Arc;
   begin
      Ks_Shape'Read (Stream, Ks_Shape (Fresh));
      K.Ks_Circular_Arc'Read (Stream, Fresh.Data);
      Item := Fresh;
   exception
      when Ada.IO_Exceptions.End_Error | Constraint_Error =>
         AMV.Checks.Stream_Malformed ("Ks_Circular_Arc'Read");
   end Read_Circular_Arc;

end AMV.Shapes;
