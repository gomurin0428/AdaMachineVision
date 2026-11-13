pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;

package body AMV.Transforms is

   package K renames AMV.Kernels.Transforms;

   use type AMV.Kernels.Int32;

   procedure Check (Status : AMV.Kernels.Ks_Status) renames AMV.Checks.Check;

   function Decompose
     (Transform : Ks_Transform_2D_Linear) return K.Ks_Decomposition;

   function Decompose
     (Transform : Ks_Transform_2D_Linear) return K.Ks_Decomposition
   is
      Result : K.Ks_Decomposition;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Decompose (Transform.Data, Result, Status);
      Check (Status);
      return Result;
   end Decompose;

   procedure Set_Property
     (Transform : in out Ks_Transform_2D_Linear;
      Property  : AMV.Kernels.Int32;
      Value     : Real);

   procedure Set_Property
     (Transform : in out Ks_Transform_2D_Linear;
      Property  : AMV.Kernels.Int32;
      Value     : Real)
   is
      Result : K.Ks_Transform_2D_Linear;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Set_Property (Transform.Data, Property, Value, Result, Status);
      Check (Status);
      Transform.Data := Result;
   end Set_Property;

   function Is_True (Flag : AMV.Kernels.Int32) return Boolean is
     (Flag = AMV.Kernels.True_Value);

   --  Constructors

   function Identity return Ks_Transform_2D_Linear is
     ((Data => <>));

   function Create
     (A, B, C, D, Translation_X, Translation_Y : Real)
      return Ks_Transform_2D_Linear is
     ((Data => (A => A, B => B, C => C, D => D,
                Translation_X => Translation_X,
                Translation_Y => Translation_Y)));

   function Create_Scaling_Aspect_Rotation_Skew_Translation
     (Scaling, Aspect, Rotation, Skew, Translation_X, Translation_Y : Real)
      return Ks_Transform_2D_Linear
   is
      Result : Ks_Transform_2D_Linear;
   begin
      Result.Set_Scaling_Aspect_Rotation_Skew_Translation
        (Scaling, Aspect, Rotation, Skew, Translation_X, Translation_Y);
      return Result;
   end Create_Scaling_Aspect_Rotation_Skew_Translation;

   Unit_Scaling : constant Real := 1.0;  --  SHELL: rigid = unit scaling

   function Create_Rigid
     (Rotation, Translation_X, Translation_Y : Real)
      return Ks_Transform_2D_Linear is
     (Create_Similarity
        (Unit_Scaling, Rotation, Translation_X, Translation_Y));

   function Create_Similarity
     (Scaling, Rotation, Translation_X, Translation_Y : Real)
      return Ks_Transform_2D_Linear
   is
      Result : Ks_Transform_2D_Linear;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Create_Similarity
        (Scaling, Rotation, Translation_X, Translation_Y, Result.Data,
         Status);
      Check (Status);
      return Result;
   end Create_Similarity;

   --  Matrix form

   procedure Get_Matrix_Elements_Translation
     (Transform                                : Ks_Transform_2D_Linear;
      A, B, C, D, Translation_X, Translation_Y : out Real) is
   begin
      A := Transform.Data.A;
      B := Transform.Data.B;
      C := Transform.Data.C;
      D := Transform.Data.D;
      Translation_X := Transform.Data.Translation_X;
      Translation_Y := Transform.Data.Translation_Y;
   end Get_Matrix_Elements_Translation;

   procedure Set_Matrix_Elements_Translation
     (Transform : in out Ks_Transform_2D_Linear;
      A, B, C, D, Translation_X, Translation_Y : Real) is
   begin
      Transform := Create (A, B, C, D, Translation_X, Translation_Y);
   end Set_Matrix_Elements_Translation;

   function Get_Matrix_Element
     (Transform : Ks_Transform_2D_Linear;
      Row       : Integer;
      Column    : Integer) return Real
   is
      Result : Real;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Get_Matrix_Element
        (Transform.Data, AMV.Kernels.Int32 (Row),
         AMV.Kernels.Int32 (Column), Result, Status);
      Check (Status);
      return Result;
   end Get_Matrix_Element;

   procedure Set_Matrix_Element
     (Transform : in out Ks_Transform_2D_Linear;
      Row       : Integer;
      Column    : Integer;
      Value     : Real)
   is
      Result : K.Ks_Transform_2D_Linear;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Set_Matrix_Element
        (Transform.Data, AMV.Kernels.Int32 (Row),
         AMV.Kernels.Int32 (Column), Value, Result, Status);
      Check (Status);
      Transform.Data := Result;
   end Set_Matrix_Element;

   --  Decomposed properties

   function Translation_X (Transform : Ks_Transform_2D_Linear) return Real is
     (Transform.Data.Translation_X);

   function Translation_Y (Transform : Ks_Transform_2D_Linear) return Real is
     (Transform.Data.Translation_Y);

   function Rotation (Transform : Ks_Transform_2D_Linear) return Real is
     (Decompose (Transform).Rotation_X);

   function Skew (Transform : Ks_Transform_2D_Linear) return Real is
     (Decompose (Transform).Skew);

   function Scaling (Transform : Ks_Transform_2D_Linear) return Real is
     (Decompose (Transform).Scaling_X);

   function Aspect (Transform : Ks_Transform_2D_Linear) return Real is
      Result : Real;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Aspect (Transform.Data, Result, Status);
      Check (Status);
      return Result;
   end Aspect;

   function Scaling_X (Transform : Ks_Transform_2D_Linear) return Real is
     (Decompose (Transform).Scaling_X);

   function Scaling_Y (Transform : Ks_Transform_2D_Linear) return Real is
     (Decompose (Transform).Scaling_Y);

   function Rotation_X (Transform : Ks_Transform_2D_Linear) return Real is
     (Decompose (Transform).Rotation_X);

   function Rotation_Y (Transform : Ks_Transform_2D_Linear) return Real is
     (Decompose (Transform).Rotation_Y);

   procedure Set_Translation_X
     (Transform : in out Ks_Transform_2D_Linear; Value : Real) is
   begin
      Transform.Data.Translation_X := Value;
   end Set_Translation_X;

   procedure Set_Translation_Y
     (Transform : in out Ks_Transform_2D_Linear; Value : Real) is
   begin
      Transform.Data.Translation_Y := Value;
   end Set_Translation_Y;

   procedure Set_Rotation
     (Transform : in out Ks_Transform_2D_Linear; Value : Real) is
   begin
      Set_Property (Transform, K.Property_Rotation, Value);
   end Set_Rotation;

   procedure Set_Skew
     (Transform : in out Ks_Transform_2D_Linear; Value : Real) is
   begin
      Set_Property (Transform, K.Property_Skew, Value);
   end Set_Skew;

   procedure Set_Scaling
     (Transform : in out Ks_Transform_2D_Linear; Value : Real) is
   begin
      Set_Property (Transform, K.Property_Scaling, Value);
   end Set_Scaling;

   procedure Set_Aspect
     (Transform : in out Ks_Transform_2D_Linear; Value : Real) is
   begin
      Set_Property (Transform, K.Property_Aspect, Value);
   end Set_Aspect;

   procedure Set_Scaling_X
     (Transform : in out Ks_Transform_2D_Linear; Value : Real) is
   begin
      Set_Property (Transform, K.Property_Scaling_X, Value);
   end Set_Scaling_X;

   procedure Set_Scaling_Y
     (Transform : in out Ks_Transform_2D_Linear; Value : Real) is
   begin
      Set_Property (Transform, K.Property_Scaling_Y, Value);
   end Set_Scaling_Y;

   procedure Set_Rotation_X
     (Transform : in out Ks_Transform_2D_Linear; Value : Real) is
   begin
      Set_Property (Transform, K.Property_Rotation_X, Value);
   end Set_Rotation_X;

   procedure Set_Rotation_Y
     (Transform : in out Ks_Transform_2D_Linear; Value : Real) is
   begin
      Set_Property (Transform, K.Property_Rotation_Y, Value);
   end Set_Rotation_Y;

   procedure Set_Scaling_Aspect_Rotation_Skew_Translation
     (Transform : in out Ks_Transform_2D_Linear;
      Scaling, Aspect, Rotation, Skew, Translation_X, Translation_Y : Real)
   is
      Result : K.Ks_Transform_2D_Linear;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Recompose_Scaling_Aspect
        (Scaling, Aspect, Rotation, Skew, Translation_X, Translation_Y,
         Result, Status);
      Check (Status);
      Transform.Data := Result;
   end Set_Scaling_Aspect_Rotation_Skew_Translation;

   procedure Get_Scaling_Aspect_Rotation_Skew_Translation
     (Transform : Ks_Transform_2D_Linear;
      Scaling, Aspect, Rotation, Skew, Translation_X, Translation_Y : out Real)
   is
      D : constant K.Ks_Decomposition := Decompose (Transform);
   begin
      Scaling := D.Scaling_X;
      Aspect := AMV.Transforms.Aspect (Transform);
      Rotation := D.Rotation_X;
      Skew := D.Skew;
      Translation_X := Transform.Data.Translation_X;
      Translation_Y := Transform.Data.Translation_Y;
   end Get_Scaling_Aspect_Rotation_Skew_Translation;

   procedure Set_Scalings_Rotations_Translation
     (Transform : in out Ks_Transform_2D_Linear;
      Scaling_X, Scaling_Y, Rotation_X, Rotation_Y,
      Translation_X, Translation_Y : Real)
   is
      Result : K.Ks_Transform_2D_Linear;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Recompose
        (Scaling_X, Scaling_Y, Rotation_X, Rotation_Y, Translation_X,
         Translation_Y, Result, Status);
      Check (Status);
      Transform.Data := Result;
   end Set_Scalings_Rotations_Translation;

   procedure Get_Scalings_Rotations_Translation
     (Transform : Ks_Transform_2D_Linear;
      Scaling_X, Scaling_Y, Rotation_X, Rotation_Y,
      Translation_X, Translation_Y : out Real)
   is
      D : constant K.Ks_Decomposition := Decompose (Transform);
   begin
      Scaling_X := D.Scaling_X;
      Scaling_Y := D.Scaling_Y;
      Rotation_X := D.Rotation_X;
      Rotation_Y := D.Rotation_Y;
      Translation_X := Transform.Data.Translation_X;
      Translation_Y := Transform.Data.Translation_Y;
   end Get_Scalings_Rotations_Translation;

   --  Mapping

   procedure Map_Point
     (Transform          : Ks_Transform_2D_Linear;
      X, Y               : Real;
      Mapped_X, Mapped_Y : out Real)
   is
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Map_Point (Transform.Data, X, Y, Mapped_X, Mapped_Y, Status);
      Check (Status);
   end Map_Point;

   procedure Map_Vector
     (Transform          : Ks_Transform_2D_Linear;
      X, Y               : Real;
      Mapped_X, Mapped_Y : out Real)
   is
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Map_Vector (Transform.Data, X, Y, Mapped_X, Mapped_Y, Status);
      Check (Status);
   end Map_Vector;

   function Map_Angle
     (Transform : Ks_Transform_2D_Linear; Angle : Real) return Real
   is
      Result : Real;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Map_Angle (Transform.Data, Angle, Result, Status);
      Check (Status);
      return Result;
   end Map_Angle;

   function Invert
     (Transform : Ks_Transform_2D_Linear) return Ks_Transform_2D_Linear
   is
      Result : Ks_Transform_2D_Linear;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Invert (Transform.Data, Result.Data, Status);
      Check (Status);
      return Result;
   end Invert;

   function Compose
     (Transform, Other : Ks_Transform_2D_Linear)
      return Ks_Transform_2D_Linear
   is
      Result : Ks_Transform_2D_Linear;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Compose (Transform.Data, Other.Data, Result.Data, Status);
      Check (Status);
      return Result;
   end Compose;

   function Matrix_Determinant
     (Transform : Ks_Transform_2D_Linear) return Real
   is
      Result : Real;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Matrix_Determinant (Transform.Data, Result, Status);
      Check (Status);
      return Result;
   end Matrix_Determinant;

   function Map_Area
     (Transform : Ks_Transform_2D_Linear; Area : Real) return Real
   is
      Result : Real;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Map_Area (Transform.Data, Area, Result, Status);
      Check (Status);
      return Result;
   end Map_Area;

   function Identity
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Real := 1.0E-12) return Boolean  --  SHELL: default
   is
      Result : AMV.Kernels.Int32;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Identity (Transform.Data, Tolerance, Result, Status);
      Check (Status);
      return Is_True (Result);
   end Identity;

   function Matrix_Identity
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Real := 1.0E-12) return Boolean  --  SHELL: default
   is
      Result : AMV.Kernels.Int32;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Matrix_Identity (Transform.Data, Tolerance, Result, Status);
      Check (Status);
      return Is_True (Result);
   end Matrix_Identity;

   function Singular
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Real) return Boolean
   is
      Result : AMV.Kernels.Int32;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Singular (Transform.Data, Tolerance, Result, Status);
      Check (Status);
      return Is_True (Result);
   end Singular;

   function Is_Similarity
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Real := 1.0E-9) return Boolean  --  SHELL: default
   is
      Result : AMV.Kernels.Int32;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Is_Similarity (Transform.Data, Tolerance, Result, Status);
      Check (Status);
      return Is_True (Result);
   end Is_Similarity;

   function Is_Axis_Aligned
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Real := 1.0E-9) return Boolean  --  SHELL: default
   is
      Result : AMV.Kernels.Int32;
      Status : AMV.Kernels.Ks_Status;
   begin
      K.Is_Axis_Aligned (Transform.Data, Tolerance, Result, Status);
      Check (Status);
      return Is_True (Result);
   end Is_Axis_Aligned;

end AMV.Transforms;
