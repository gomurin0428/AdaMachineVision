--  The geometry shared by the training, the search and the refinement of
--  AMV.Kernels.PM_Align: 2 x 2 matrices, the mapping of a model feature
--  by a pose into the pixels of a pyramid level, the quantised model the
--  grid search scores, pyramid level coordinates and the zones.
--
--  Every value carries its bound in its subtype, and the products are
--  formed through the bounded helpers of AMV.Kernels.Numerics, so that
--  the callers' proofs stay linear (docs/PROOF.md).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.PM_Align.Poses with SPARK_Mode, Preelaborate is

   Pi     : constant := Ada.Numerics.Pi;
   Two_Pi : constant := 2.0 * Pi;

   subtype Unit is Long_Float range -1.0 .. 1.0;
   subtype Fraction is Long_Float range 0.0 .. 1.0;
   subtype Entry_Value is Long_Float range -Max_Value .. Max_Value;

   Max_Relative : constant := 2.0 * Max_Pattern_Coordinate;
   subtype Relative is Long_Float range -Max_Relative .. Max_Relative;
   --  A feature's pattern coordinates minus the model's centroid.

   subtype Offset is Long_Float range -Max_Offset .. Max_Offset;
   --  A mapped feature's offset from the centroid, in level pixels.

   subtype Scale_Value is Long_Float range Min_Zone_Scale .. Max_Zone_Scale;

   Max_Angle : constant := 4.0 * Max_Zone_Angle;
   subtype Angle_Value is Long_Float range -Max_Angle .. Max_Angle;
   --  An angle on its way into a zone.

   subtype Zone_Angle_Value is Long_Float
     range -Max_Zone_Angle .. Max_Zone_Angle;
   --  An angle in a zone.

   Max_Position : constant := 2.0 ** 33;
   subtype Position is Long_Float range -Max_Position .. Max_Position;
   --  A position in the pixel coordinates of a pyramid level (images have
   --  fewer than 2**31 columns and rows).

   Max_Radius : constant := 4.0E9;
   subtype Pattern_Length is Long_Float range 0.0 .. Max_Radius;
   --  A distance between two points within Max_Pattern_Coordinate (the
   --  Hypot of two differences of at most 2.0E9 each).

   subtype Pixel_Radius is Long_Float range 1.0 .. Max_Offset;

   ---------------------------------------------------------------------
   --  Matrices and rotations
   ---------------------------------------------------------------------

   type Linear is record
      A, B, C, D : Entry_Value := 0.0;
   end record;
   --  The matrix [A B; C D].

   type Unit_Linear is record
      A, B, C, D : Unit := 0.0;
   end record;

   type Rotation is record
      Cos_T : Unit := 1.0;
      Sin_T : Unit := 0.0;
   end record;

   function Rotation_Of (Theta : Long_Float) return Rotation;
   --  The cosine and the sine of Theta.

   function Linear_Of (T : KT.Ks_Transform_2D_Linear) return Linear
   with Pre => KT.Bounded (T);
   --  The matrix of T.

   function Normal_Map (M : Linear) return Unit_Linear;
   --  A positive multiple of the inverse transpose of M (the map of
   --  normals, that is of gradients, under M), scaled so that its largest
   --  entry is 1 in magnitude: Sign (Det M) * [D -C; -B A] / max |entry|.
   --  All zeros for the zero matrix.

   procedure Largest_Stretch
     (M      : Linear;
      Sigma  : out Long_Float;
      Lambda : out Long_Float)
   with Post => Sigma in 0.0 .. 2.0 and then Lambda in 0.0 .. Max_Value;
   --  The largest singular value of M is Sigma * Lambda: Lambda is the
   --  largest entry in magnitude and Sigma that of M / Lambda.

   ---------------------------------------------------------------------
   --  Frames, poses and mapped features
   ---------------------------------------------------------------------

   type Frame is record
      L               : Linear;
      N               : Unit_Linear;
      Sigma           : Long_Float range 0.0 .. 2.0 := 0.0;
      Lambda          : Entry_Value := 0.0;
      Centroid_X      : Pattern_Coordinate := 0.0;
      Centroid_Y      : Pattern_Coordinate := 0.0;
      Radius          : Pattern_Length := 0.0;
      Ignore_Polarity : Boolean := False;
   end record;
   --  What a run computes once: L, the matrix from the input image's
   --  selected space to its pixels, N = Normal_Map (L), its largest
   --  stretch Sigma * Lambda, the model's centroid and radius (the largest
   --  distance of a finest feature from the centroid) in pattern
   --  coordinates, and the pattern's IgnorePolarity.

   function Level_Factor (Level : Level_Index) return Long_Float
   with Post => Level_Factor'Result >= 1.0 / 32.0
                and then Level_Factor'Result <= 1.0;
   --  2 ** (-Level).

   function Level_Size (Level : Level_Index) return Long_Float
   with Post => Level_Size'Result >= 1.0 and then Level_Size'Result <= 32.0;
   --  2 ** Level.

   function To_Level (X0 : Position; Level : Level_Index) return Position;
   --  A level-0 pixel coordinate in the pixels of Level: (X0 - (2**Level
   --  - 1) / 2) / 2**Level (the centre of pixel I of Level covers the
   --  level-0 pixels 2**Level * I .. 2**Level * (I + 1) - 1).

   function From_Level (XL : Position; Level : Level_Index) return Position;
   --  The inverse of To_Level, limited to Position.

   procedure Map_Offset
     (F      : Frame;
      R      : Rotation;
      S      : Scale_Value;
      Level  : Level_Index;
      RX, RY : Relative;
      DX, DY : out Offset);
   --  The offset of a feature at RX, RY from the centroid (pattern
   --  coordinates) mapped by the pose's rotation R and scale S and by
   --  F.L, in pixels of Level: S * L * R * (RX, RY) / 2**Level, each
   --  coordinate limited to Max_Offset.

   procedure Map_Normal
     (F      : Frame;
      R      : Rotation;
      NX, NY : Unit;
      UX, UY : out Unit);
   --  The unit normal (NX, NY) of a feature (pattern coordinates) mapped
   --  into pixels: the direction of F.N * R * (NX, NY), or (0, 0) when
   --  that vector is (nearly) zero.

   procedure Normalise
     (VX, VY : Long_Float;
      UX, UY : out Unit)
   with Pre => abs VX <= 16.0 and then abs VY <= 16.0;
   --  The unit vector along (VX, VY); (0, 0) for a vector shorter than
   --  1.0E-9.

   function Pixel_Radius_Of
     (F     : Frame;
      S     : Scale_Value;
      Level : Level_Index) return Pixel_Radius;
   --  The model's radius in pixels of Level at scale S (an upper bound
   --  for a matrix L that is not a similarity), limited to [1,
   --  Max_Offset].

   procedure Centroid
     (Model  : Model_Level;
      CX, CY : out Pattern_Coordinate);
   --  The mean of the features of Model ((0, 0) when it has none).

   function Pattern_Radius
     (Model  : Model_Level;
      CX, CY : Pattern_Coordinate) return Pattern_Length;
   --  The largest distance of a feature of Model from (CX, CY).

   ---------------------------------------------------------------------
   --  The quantised model (the grid search)
   ---------------------------------------------------------------------

   subtype Quantum is Integer range -127 .. 127;

   Max_Grid_Offset : constant := 2 ** 20;
   subtype Grid_Offset is Integer range -Max_Grid_Offset .. Max_Grid_Offset;

   type Quantised_Feature is record
      OX, OY : Grid_Offset := 0;
      QX, QY : Quantum := 0;
   end record;
   --  A mapped feature: its offset from the centroid rounded to whole
   --  pixels of the level, and its mapped unit normal times 127, rounded.

   type Quantised_Array is array (0 .. Max_Features - 1) of Quantised_Feature;

   type Quantised_Model is record
      Count : Feature_Count := 0;
      Items : Quantised_Array;
   end record;

   procedure Quantise
     (Model : Model_Level;
      F     : Frame;
      Level : Level_Index;
      R     : Rotation;
      S     : Scale_Value;
      Q     : out Quantised_Model)
   with Post => Q.Count = Model.Count;
   --  The features of Model mapped by the pose (R, S) into the pixels of
   --  Level.

   ---------------------------------------------------------------------
   --  Zones
   ---------------------------------------------------------------------

   function Angle_In_Zone
     (Theta : Long_Float;
      Zone  : Ks_PM_Align_Zone_Angle) return Zone_Angle_Value
   with Pre  => Valid_Angle_Zone (Zone) and then abs Theta <= Max_Angle,
        Post => In_Zone (Angle_In_Zone'Result, Zone);
   --  Theta brought into the zone: Nominal for a Nominal zone; for a
   --  LowHigh zone that spans the whole circle, the angle equal to Theta
   --  modulo 2 Pi in (Low, Low + 2 Pi]; otherwise Theta limited to [Low,
   --  High].

   function Scale_In_Zone
     (S    : Long_Float;
      Zone : Ks_PM_Align_Zone_Scale) return Scale_Value
   with Pre  => Valid_Scale_Zone (Zone),
        Post => In_Zone (Scale_In_Zone'Result, Zone);
   --  S limited to the zone (Nominal for a Nominal zone).

   function Angle_Distance (A, B : Zone_Angle_Value) return Long_Float
   with Post => Angle_Distance'Result >= 0.0
                and then Angle_Distance'Result <= Pi;
   --  The absolute difference of A and B modulo 2 Pi, in [0, Pi].

end AMV.Kernels.PM_Align.Poses;
