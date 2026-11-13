--  2D linear (affine) transforms: the counterpart of CogTransform2DLinear.
--
--  A transform maps a point (x, y) to
--
--     x' = A * x + B * y + Translation_X
--     y' = C * x + D * y + Translation_Y
--
--  The linear part is also available decomposed:
--
--     image of the x axis:
--        (A, C) = Scaling_X * (cos Rotation_X, sin Rotation_X)
--     image of the y axis:
--        (B, D) = Scaling_Y * (-sin Rotation_Y, cos Rotation_Y)
--
--     Rotation = Rotation_X
--     Skew     = Norm_Angle (Rotation_Y - Rotation_X)
--     Scaling  = Scaling_X
--     Aspect   = Scaling_Y / Scaling_X
--
--  Scaling_X and Scaling_Y are never negative; a reflection shows up as a
--  skew near Pi. When a scaling is zero the corresponding rotation is
--  reported as 0.0, and when Scaling_X is zero Aspect is reported as 0.0
--  (instead of raising).
--
--  While Scaling_X and Scaling_Y are both non-zero, setting one decomposed
--  property keeps the others (and the translation) unchanged. A zero
--  column has no direction to keep, so the promise cannot hold there:
--
--  * A setter that makes a scaling zero (Set_Scaling, Set_Scaling_X,
--    Set_Scaling_Y or Set_Aspect with 0.0) loses that axis's rotation,
--    which then reads 0.0; Rotation or Skew can change as a result.
--  * With Scaling_X = 0 (and Scaling_Y non-zero), Rotation always reads
--    0.0. Set_Rotation and Set_Skew both turn the remaining y axis,
--    measured from that reported Rotation of 0.0: Set_Rotation (V) adds V
--    to Rotation_Y, so Skew changes and Rotation stays 0.0; Set_Skew (V)
--    makes Skew read V (normalised) and Rotation stays 0.0.
--  * With Scaling_Y = 0 (and Scaling_X non-zero), Rotation_Y always reads
--    0.0, so Skew reads Norm_Angle (-Rotation): Set_Rotation (V) changes
--    Skew to Norm_Angle (-V), and Set_Skew and Set_Rotation_Y leave the
--    matrix unchanged (up to rounding).
--  * With a zero linear part every decomposed property reads 0.0, and of
--    the decomposed setters only Set_Scaling, Set_Scaling_X and
--    Set_Scaling_Y change the matrix.
--
--  Setters and constructors accept negative scalings and aspects: the
--  formulas above are applied as written, so a negative value reverses
--  that axis. Reading the transform back then reports the magnitude, with
--  the corresponding rotation turned by Pi.
--
--  The computations are done by the SPARK kernel AMV.Kernels.Transforms
--  (the C functions ks_transform_2d_linear_*), which bounds every value so
--  that nothing can overflow:
--
--  * every matrix entry, translation, coordinate, area, aspect, angle and
--    tolerance passed to an operation must be finite and within
--    [-1.0E150, 1.0E150], and every scaling within [-2.0E150, 2.0E150];
--    otherwise the operation raises Ks_Bad_Parameter_Exception naming the
--    argument (a NaN or an infinity included). Create,
--    Set_Matrix_Elements_Translation and the translation setters only
--    store their values; the check happens when the transform is used;
--  * a result that would leave those bounds (a mapped point or area, a
--    composed transform, an aspect, a changed scaling or entry) raises
--    Ks_Bad_Parameter_Exception as well, so every transform an operation
--    returns is a valid argument again. For Invert see below.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

private with AMV.Kernels.Transforms;

package AMV.Transforms is
   pragma Preelaborate;

   type Ks_Transform_2D_Linear is tagged private;
   --  Default value: the identity.

   function Identity return Ks_Transform_2D_Linear;

   function Create
     (A, B, C, D, Translation_X, Translation_Y : Real)
      return Ks_Transform_2D_Linear;
   --  The transform with the given matrix and translation.

   function Create_Scaling_Aspect_Rotation_Skew_Translation
     (Scaling, Aspect, Rotation, Skew, Translation_X, Translation_Y : Real)
      return Ks_Transform_2D_Linear;
   --  The transform with Scaling_X = Scaling, Scaling_Y = Scaling * Aspect,
   --  Rotation_X = Rotation, Rotation_Y = Rotation + Skew and the given
   --  translation.

   function Create_Rigid
     (Rotation, Translation_X, Translation_Y : Real)
      return Ks_Transform_2D_Linear;
   --  Rotation about the origin followed by translation, unit scaling.

   function Create_Similarity
     (Scaling, Rotation, Translation_X, Translation_Y : Real)
      return Ks_Transform_2D_Linear;
   --  Uniform scaling and rotation about the origin, then translation.

   --  Matrix form. VisionPro's elem00, elem01, elem10 and elem11 are A, B,
   --  C and D (row-major: row 0 is (A, B), row 1 is (C, D)).

   procedure Get_Matrix_Elements_Translation
     (Transform                            : Ks_Transform_2D_Linear;
      A, B, C, D, Translation_X, Translation_Y : out Real);
   --  GetMatrixElementsTranslation: the stored values, exactly.

   procedure Set_Matrix_Elements_Translation
     (Transform                            : in out Ks_Transform_2D_Linear;
      A, B, C, D, Translation_X, Translation_Y : Real);
   --  SetMatrixElementsTranslation: replaces the whole transform. The
   --  values are stored as given (like Create); they are checked when the
   --  transform is used.

   function Get_Matrix_Element
     (Transform : Ks_Transform_2D_Linear;
      Row       : Integer;
      Column    : Integer) return Real;
   --  GetMatrixElement: the element in row Row and column Column (0 .. 1
   --  each): (0, 0) is A, (0, 1) is B, (1, 0) is C and (1, 1) is D. Raises
   --  Ks_Bad_Parameter_Exception (VisionPro: ArgumentException) when Row
   --  or Column is outside 0 .. 1, and, like every operation that uses the
   --  transform, when an entry or the translation is beyond the bounds
   --  above.

   procedure Set_Matrix_Element
     (Transform : in out Ks_Transform_2D_Linear;
      Row       : Integer;
      Column    : Integer;
      Value     : Real);
   --  SetMatrixElement: replaces that one element, keeping the others and
   --  the translation. Value must be within the bounds above. Raises
   --  Ks_Bad_Parameter_Exception as Get_Matrix_Element does, or for Value;
   --  Transform is then unchanged.

   --  Decomposed properties

   function Translation_X (Transform : Ks_Transform_2D_Linear) return Real;
   function Translation_Y (Transform : Ks_Transform_2D_Linear) return Real;
   function Rotation (Transform : Ks_Transform_2D_Linear) return Real;
   function Skew (Transform : Ks_Transform_2D_Linear) return Real;
   function Scaling (Transform : Ks_Transform_2D_Linear) return Real;
   function Aspect (Transform : Ks_Transform_2D_Linear) return Real;
   function Scaling_X (Transform : Ks_Transform_2D_Linear) return Real;
   function Scaling_Y (Transform : Ks_Transform_2D_Linear) return Real;
   function Rotation_X (Transform : Ks_Transform_2D_Linear) return Real;
   function Rotation_Y (Transform : Ks_Transform_2D_Linear) return Real;

   procedure Set_Translation_X
     (Transform : in out Ks_Transform_2D_Linear; Value : Real);
   procedure Set_Translation_Y
     (Transform : in out Ks_Transform_2D_Linear; Value : Real);
   procedure Set_Rotation
     (Transform : in out Ks_Transform_2D_Linear; Value : Real);
   procedure Set_Skew
     (Transform : in out Ks_Transform_2D_Linear; Value : Real);
   procedure Set_Scaling
     (Transform : in out Ks_Transform_2D_Linear; Value : Real);
   --  Changes Scaling_X and Scaling_Y together, keeping Aspect. When
   --  Scaling_X is zero the aspect reads as 0.0, so Scaling_Y becomes zero.
   procedure Set_Aspect
     (Transform : in out Ks_Transform_2D_Linear; Value : Real);
   --  Changes Scaling_Y to Scaling_X * Value, keeping Scaling_X.
   procedure Set_Scaling_X
     (Transform : in out Ks_Transform_2D_Linear; Value : Real);
   procedure Set_Scaling_Y
     (Transform : in out Ks_Transform_2D_Linear; Value : Real);
   procedure Set_Rotation_X
     (Transform : in out Ks_Transform_2D_Linear; Value : Real);
   procedure Set_Rotation_Y
     (Transform : in out Ks_Transform_2D_Linear; Value : Real);
   --  Set_Scaling_X, Set_Scaling_Y, Set_Rotation_X and Set_Rotation_Y are
   --  AMV additions: ScalingX, ScalingY, RotationX and RotationY are
   --  read-only in VisionPro, which sets them only together, through
   --  SetScalingsRotationsTranslation.

   procedure Set_Scaling_Aspect_Rotation_Skew_Translation
     (Transform : in out Ks_Transform_2D_Linear;
      Scaling, Aspect, Rotation, Skew, Translation_X, Translation_Y : Real);

   procedure Get_Scaling_Aspect_Rotation_Skew_Translation
     (Transform : Ks_Transform_2D_Linear;
      Scaling, Aspect, Rotation, Skew,
      Translation_X, Translation_Y : out Real);

   procedure Set_Scalings_Rotations_Translation
     (Transform : in out Ks_Transform_2D_Linear;
      Scaling_X, Scaling_Y, Rotation_X, Rotation_Y,
      Translation_X, Translation_Y : Real);

   procedure Get_Scalings_Rotations_Translation
     (Transform : Ks_Transform_2D_Linear;
      Scaling_X, Scaling_Y, Rotation_X, Rotation_Y,
      Translation_X, Translation_Y : out Real);
   --  The composite setters replace the whole transform; the composite
   --  getters return the same values as the individual getters.

   --  Mapping

   procedure Map_Point
     (Transform          : Ks_Transform_2D_Linear;
      X, Y               : Real;
      Mapped_X, Mapped_Y : out Real);
   --  Maps the point (X, Y).

   procedure Map_Vector
     (Transform          : Ks_Transform_2D_Linear;
      X, Y               : Real;
      Mapped_X, Mapped_Y : out Real);
   --  Maps the free vector (X, Y): the linear part only, no translation.

   function Map_Angle
     (Transform : Ks_Transform_2D_Linear; Angle : Real) return Real;
   --  The direction (in (-Pi, Pi]) of the mapped unit vector
   --  (cos Angle, sin Angle). Raises Ks_Transform_Singular_Exception when
   --  that vector maps to zero. Because cos and sin are rounded, "zero"
   --  means: both components of the mapped vector are at most
   --  Map_Angle_Zero_Tolerance times the largest absolute matrix entry
   --  (an all-zero matrix always raises).

   Map_Angle_Zero_Tolerance : constant := 1.0E-14;

   function Invert
     (Transform : Ks_Transform_2D_Linear) return Ks_Transform_2D_Linear;
   --  The inverse transform, by the plain formulas (D / Det, -B / Det,
   --  ..., with Det = A * D - B * C). Raises
   --  Ks_Transform_Singular_Exception when the determinant is zero or
   --  when an entry of the inverse, its translation included, would
   --  exceed 1.0E150. A matrix whose inverse is within that bound has a
   --  determinant of at least about 2.5E-301 in magnitude, so the plain
   --  formulas keep full precision for every inverse that is returned,
   --  however small, large or anisotropic the entries are.

   function Compose
     (Transform, Other : Ks_Transform_2D_Linear)
      return Ks_Transform_2D_Linear;
   --  The transform that applies Other first and then Transform:
   --  Transform.Compose (Other).Map_Point (P) = Transform (Other (P)).

   function "*"
     (Left, Right : Ks_Transform_2D_Linear) return Ks_Transform_2D_Linear
     renames Compose;

   function Matrix_Determinant
     (Transform : Ks_Transform_2D_Linear) return Real;
   --  MatrixDeterminant: A * D - B * C, evaluated as written (at most
   --  2.0E300 in magnitude for entries within the bounds). It loses
   --  precision or gives 0.0 when the products fall below about 2.2E-308.

   function Map_Area
     (Transform : Ks_Transform_2D_Linear; Area : Real) return Real;
   --  MapArea: the area that a region of area Area covers after the
   --  mapping, abs (Matrix_Determinant) * Area (the translation plays no
   --  part; a negative Area keeps its sign). Area must be within the
   --  bounds above, and so must the result: otherwise
   --  Ks_Bad_Parameter_Exception.

   --  Tests. Tolerance must be finite, >= 0 and within 1.0E150
   --  (Ks_Bad_Parameter_Exception otherwise).

   function Identity
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Real := 1.0E-12) return Boolean;
   --  Identity (tolerance): True when every matrix and translation entry
   --  is within Tolerance of the identity's. (VisionPro does not document
   --  this test exactly; AMV compares the whole transform.) It overloads
   --  the parameterless constructor Identity above: T.Identity and
   --  Identity (T) are this test, Identity alone is the constructor.

   function Matrix_Identity
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Real := 1.0E-12) return Boolean;
   --  MatrixIdentity (tolerance): True when A, B, C and D are each within
   --  Tolerance of the identity's 1, 0, 0, 1; the translation is ignored.

   function Singular
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Real) return Boolean;
   --  Singular (tolerance): True when abs (Matrix_Determinant) is at most
   --  Tolerance. The bound is absolute (it applies to the determinant,
   --  whose scale is that of the entries squared), so there is no default.
   --  A determinant that underflows to 0.0 counts as singular.

   --  AMV additions (no VisionPro counterpart).

   function Is_Similarity
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Real := 1.0E-9) return Boolean;
   --  True when the linear part is a rotation times a uniform positive
   --  scaling (no aspect, skew or reflection), within a relative Tolerance:
   --  abs (A - D) and abs (B + C) are at most Tolerance times the largest
   --  absolute matrix entry, and the determinant is positive. The
   --  translation is ignored.

   function Is_Axis_Aligned
     (Transform : Ks_Transform_2D_Linear;
      Tolerance : Real := 1.0E-9) return Boolean;
   --  True when B and C are both zero within a relative Tolerance, that is
   --  at most Tolerance times the largest absolute matrix entry (scaling
   --  along x and y, possibly with reflection or zero scaling, plus
   --  translation).

private

   type Ks_Transform_2D_Linear is tagged record
      Data : AMV.Kernels.Transforms.Ks_Transform_2D_Linear;
      --  The identity by default.
   end record;

end AMV.Transforms;
