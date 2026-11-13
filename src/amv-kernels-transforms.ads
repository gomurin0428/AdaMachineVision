--  Kernel of AMV.Transforms: 2D linear (affine) transforms, the
--  counterpart of CogTransform2DLinear.
--
--  A transform maps (x, y) to (A x + B y + Translation_X,
--  C x + D y + Translation_Y). The decomposed form, the composition order
--  and the meaning of every operation are documented in AMV.Transforms.
--
--  Bounds. Every matrix entry, translation, coordinate, area, aspect,
--  angle and tolerance that an entry point takes or returns lies within
--  [-Max_Value, Max_Value] (1.0E150), and every scaling within
--  [-Max_Scaling, Max_Scaling] (the determinant, up to 2 Max_Value**2,
--  is the one result that is not a valid argument again). With that
--  bound no product of two
--  values and no sum of a few of them can overflow (1.0E150 squared is
--  1.0E300, below Long_Float'Last, about 1.8E308), and a matrix whose
--  inverse is within the bound has a determinant of at least 1 / (4
--  Max_Value**2), far above the smallest normal Long_Float, so the plain
--  formulas keep their precision. An argument outside the bound, or a
--  NaN or an infinity, gives Bad_Parameter; a result that would leave it
--  gives Bad_Parameter too (Transform_Singular for an inverse). So every
--  transform the kernel produces is a valid argument again.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Ada.Numerics;

package AMV.Kernels.Transforms with SPARK_Mode, Pure is

   Pi : constant := Ada.Numerics.Pi;

   Max_Value : constant := 1.0E150;

   Max_Scaling : constant := 2.0 * Max_Value;
   --  Scalings are column lengths, up to Sqrt (2) times the largest
   --  entry; they are bounded by Max_Scaling instead of Max_Value.

   type Ks_Transform_2D_Linear is record
      A             : Long_Float := 1.0;
      B             : Long_Float := 0.0;
      C             : Long_Float := 0.0;
      D             : Long_Float := 1.0;
      Translation_X : Long_Float := 0.0;
      Translation_Y : Long_Float := 0.0;
   end record
     with Convention => C;
   --  C: ks_transform_2d_linear. The default is the identity.

   function Bounded (X : Long_Float) return Boolean is
     (X >= -Max_Value and then X <= Max_Value);

   function Bounded (T : Ks_Transform_2D_Linear) return Boolean is
     (Bounded (T.A) and then Bounded (T.B) and then Bounded (T.C)
      and then Bounded (T.D) and then Bounded (T.Translation_X)
      and then Bounded (T.Translation_Y));
   --  Every field within [-Max_Value, Max_Value].

   Map_Angle_Zero_Tolerance : constant := 1.0E-14;

   --  The decomposed quantities, as one record (C: ks_transform_2d_
   --  linear_decomposition): Scaling_X, Scaling_Y in [0, Max_Scaling];
   --  Rotation_X, Rotation_Y in (-Pi, Pi]; Skew = Rotation_Y - Rotation_X
   --  reduced to (-Pi, Pi]. (Scaling = Scaling_X and Rotation =
   --  Rotation_X; Aspect has an entry point of its own, since it can
   --  exceed every bound.)

   type Ks_Decomposition is record
      Scaling_X  : Long_Float := 1.0;
      Scaling_Y  : Long_Float := 1.0;
      Rotation_X : Long_Float := 0.0;
      Rotation_Y : Long_Float := 0.0;
      Skew       : Long_Float := 0.0;
   end record
     with Convention => C;

   ---------------------------------------------------------------------
   --  Entry points
   ---------------------------------------------------------------------

   --  Every entry point below fails with Bad_Parameter, naming the
   --  argument, when an argument is not finite or not within
   --  [-Max_Value, Max_Value] (for a transform: any of its six fields).

   procedure Decompose
     (Transform : Ks_Transform_2D_Linear;
      Result    : out Ks_Decomposition;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_decompose",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Result.Scaling_X in 0.0 .. Max_Scaling
                            and then Result.Scaling_Y in 0.0 .. Max_Scaling
                            and then Result.Rotation_X > -Pi
                            and then Result.Rotation_X <= Pi
                            and then Result.Rotation_Y > -Pi
                            and then Result.Rotation_Y <= Pi
                            and then Result.Skew > -Pi
                            and then Result.Skew <= Pi);
   --  The decomposed properties. A zero column has rotation 0.0.

   procedure Aspect
     (Transform : Ks_Transform_2D_Linear;
      Result    : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_aspect",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Result in 0.0 .. Max_Value);
   --  Scaling_Y / Scaling_X; 0.0 when Scaling_X is zero. Bad_Parameter
   --  when it would exceed Max_Value.

   procedure Recompose
     (Scaling_X, Scaling_Y, Rotation_X, Rotation_Y : Long_Float;
      Translation_X, Translation_Y                 : Long_Float;
      Result                                       : out Ks_Transform_2D_Linear;
      Status                                       : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_recompose",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Bounded (Result));
   --  The transform with the given scalings (within Max_Scaling),
   --  rotations and translation (SetScalingsRotationsTranslation): (A, C) = Scaling_X (cos
   --  Rotation_X, sin Rotation_X), (B, D) = Scaling_Y (-sin Rotation_Y,
   --  cos Rotation_Y). Negative scalings are allowed (see AMV.Transforms).
   --  Bad_Parameter when an entry of the result would exceed Max_Value.

   procedure Recompose_Scaling_Aspect
     (Scaling, Aspect, Rotation, Skew : Long_Float;
      Translation_X, Translation_Y    : Long_Float;
      Result                          : out Ks_Transform_2D_Linear;
      Status                          : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_recompose_scaling_aspect",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Bounded (Result));
   --  SetScalingAspectRotationSkewTranslation: Recompose with
   --  Scaling_X = Scaling, Scaling_Y = Scaling * Aspect,
   --  Rotation_X = Rotation, Rotation_Y = Rotation + Skew (Scaling within
   --  Max_Scaling). Bad_Parameter when Scaling * Aspect would exceed
   --  Max_Scaling or an entry of the result Max_Value.

   --  The single-property setters (SetRotation, SetSkew, ...): the
   --  transform with that property changed and the others kept, as
   --  described in AMV.Transforms. Property is one of the codes below.

   Property_Rotation   : constant Int32 := 0;
   Property_Skew       : constant Int32 := 1;
   Property_Scaling    : constant Int32 := 2;
   Property_Aspect     : constant Int32 := 3;
   Property_Scaling_X  : constant Int32 := 4;
   Property_Scaling_Y  : constant Int32 := 5;
   Property_Rotation_X : constant Int32 := 6;
   Property_Rotation_Y : constant Int32 := 7;

   procedure Set_Property
     (Transform : Ks_Transform_2D_Linear;
      Property  : Int32;
      Value     : Long_Float;
      Result    : out Ks_Transform_2D_Linear;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_set_property",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Bounded (Result));
   --  Value is within Max_Scaling for the scalings and within Max_Value
   --  otherwise. Bad_Parameter for an unknown Property code, when the
   --  aspect (Property_Scaling keeps it) exceeds Max_Value, and when a
   --  changed scaling or an entry of the result would leave its bound.

   procedure Create_Similarity
     (Scaling, Rotation, Translation_X, Translation_Y : Long_Float;
      Result : out Ks_Transform_2D_Linear;
      Status : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_create_similarity",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Bounded (Result)
                            and then Result.A = Result.D
                            and then Result.B = -Result.C);
   --  Uniform scaling and rotation about the origin, then translation,
   --  built so that A = D and B = -C hold exactly.

   procedure Map_Point
     (Transform          : Ks_Transform_2D_Linear;
      X, Y               : Long_Float;
      Mapped_X, Mapped_Y : out Long_Float;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_map_point",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Bounded (Mapped_X) and then Bounded (Mapped_Y));
   --  (A X + B Y + Translation_X, C X + D Y + Translation_Y).
   --  Bad_Parameter when the result would exceed Max_Value.

   procedure Map_Vector
     (Transform          : Ks_Transform_2D_Linear;
      X, Y               : Long_Float;
      Mapped_X, Mapped_Y : out Long_Float;
      Status             : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_map_vector",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status)
                       then Bounded (Mapped_X) and then Bounded (Mapped_Y));
   --  (A X + B Y, C X + D Y): the linear part only.

   procedure Map_Angle
     (Transform : Ks_Transform_2D_Linear;
      Angle     : Long_Float;
      Result    : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_map_angle",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Transform_Singular
             and then (if Succeeded (Status)
                       then Result > -Pi and then Result <= Pi);
   --  The direction in (-Pi, Pi] of the mapped unit vector (cos Angle,
   --  sin Angle). Transform_Singular when that vector maps to zero, that
   --  is when both its components are at most Map_Angle_Zero_Tolerance
   --  times the largest absolute matrix entry.

   procedure Invert
     (Transform : Ks_Transform_2D_Linear;
      Result    : out Ks_Transform_2D_Linear;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_invert",
     Post => Valid (Status)
             and then Status.Failure
                        in Failure_None | Failure_Bad_Parameter
                         | Failure_Transform_Singular
             and then (if Succeeded (Status) then Bounded (Result));
   --  The inverse transform. Transform_Singular when the determinant is
   --  zero or when an entry of the inverse, its translation included,
   --  would exceed Max_Value.

   procedure Compose
     (Transform, Other : Ks_Transform_2D_Linear;
      Result           : out Ks_Transform_2D_Linear;
      Status           : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_compose",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Bounded (Result));
   --  The transform that applies Other first and then Transform.
   --  Bad_Parameter when an entry of the result would exceed Max_Value.

   procedure Matrix_Determinant
     (Transform : Ks_Transform_2D_Linear;
      Result    : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_matrix_determinant",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter;
   --  MatrixDeterminant: A * D - B * C, evaluated as written (at most
   --  2.0E300 in magnitude; it loses precision or gives 0.0 when the
   --  products fall below about 2.2E-308).

   procedure Map_Area
     (Transform : Ks_Transform_2D_Linear;
      Area      : Long_Float;
      Result    : out Long_Float;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_map_area",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Succeeded (Status) then Bounded (Result));
   --  MapArea: abs (A * D - B * C) * Area, the area that a region of area
   --  Area covers after the mapping (the translation plays no part). The
   --  determinant is evaluated as Matrix_Determinant evaluates it. Area
   --  may be negative (a signed area keeps its sign). Bad_Parameter when
   --  the result would exceed Max_Value.

   --  Matrix elements by index (GetMatrixElement / SetMatrixElement):
   --  row 0 is (A, B), row 1 is (C, D); column 0 is (A, C), column 1 is
   --  (B, D). Row and Column must be 0 or 1 (Bad_Parameter otherwise,
   --  checked after the transform).

   function Matrix_Element
     (T : Ks_Transform_2D_Linear; Row, Column : Int32) return Long_Float
   is (if Row = 0 then (if Column = 0 then T.A else T.B)
       else (if Column = 0 then T.C else T.D));
   --  The element at (Row, Column), for Row and Column in 0 .. 1 (any
   --  other Row reads as row 1, any other Column as column 1).

   procedure Get_Matrix_Element
     (Transform   : Ks_Transform_2D_Linear;
      Row, Column : Int32;
      Result      : out Long_Float;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_get_matrix_element",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Row not in 0 .. 1 or else Column not in 0 .. 1
                       then Status.Failure = Failure_Bad_Parameter)
             and then (if Succeeded (Status)
                       then Bounded (Result)
                            and then Result
                                       = Matrix_Element
                                           (Transform, Row, Column));
   --  The matrix element at (Row, Column).

   procedure Set_Matrix_Element
     (Transform   : Ks_Transform_2D_Linear;
      Row, Column : Int32;
      Value       : Long_Float;
      Result      : out Ks_Transform_2D_Linear;
      Status      : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_set_matrix_element",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then (if Row not in 0 .. 1 or else Column not in 0 .. 1
                       then Status.Failure = Failure_Bad_Parameter)
             and then (if Succeeded (Status)
                       then Bounded (Result)
                            and then Result.A
                                       = (if Row = 0 and then Column = 0
                                          then Value else Transform.A)
                            and then Result.B
                                       = (if Row = 0 and then Column = 1
                                          then Value else Transform.B)
                            and then Result.C
                                       = (if Row = 1 and then Column = 0
                                          then Value else Transform.C)
                            and then Result.D
                                       = (if Row = 1 and then Column = 1
                                          then Value else Transform.D)
                            and then Result.Translation_X
                                       = Transform.Translation_X
                            and then Result.Translation_Y
                                       = Transform.Translation_Y);
   --  The transform with the element at (Row, Column) replaced by Value
   --  (within Max_Value) and everything else kept.

   --  Classification. Tolerance must be finite, >= 0 and within
   --  Max_Value; Result is True_Value or False_Value.

   procedure Identity
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_identity",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result in False_Value | True_Value;
   --  Identity (tolerance): every matrix and translation entry within
   --  Tolerance of the identity's.

   procedure Matrix_Identity
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_matrix_identity",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result in False_Value | True_Value;
   --  MatrixIdentity (tolerance): abs (A - 1), abs B, abs C and
   --  abs (D - 1) at most Tolerance; the translation is ignored.

   procedure Singular
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_singular",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result in False_Value | True_Value;
   --  Singular (tolerance): abs (A * D - B * C) at most Tolerance, an
   --  absolute bound on the determinant as Matrix_Determinant evaluates
   --  it (so a determinant that underflows to 0.0 is singular for every
   --  Tolerance).

   procedure Is_Similarity
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_is_similarity",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result in False_Value | True_Value;
   --  With the matrix divided by its largest absolute entry: abs (A - D)
   --  and abs (B + C) at most Tolerance, and a positive determinant.

   procedure Is_Axis_Aligned
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Long_Float;
      Result    : out Int32;
      Status    : out Ks_Status)
   with
     Export, Convention => C,
     External_Name => "ks_transform_2d_linear_is_axis_aligned",
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Bad_Parameter
             and then Result in False_Value | True_Value;
   --  abs B and abs C at most Tolerance times the largest absolute matrix
   --  entry.

end AMV.Kernels.Transforms;
