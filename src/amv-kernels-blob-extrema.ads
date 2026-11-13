--  Extrema-angle measures and the axis queries on demand for
--  AMV.Kernels.Blob: the box along the axes at any angle around the mapped
--  pixel squares of a feature, and the medians of the coordinates of its
--  mapped pixel centres along the axes of a box, selected exactly from the
--  computed coordinates without a sort (a three-way partition selection).
--
--  A frame row (P, Q) maps the offset (DX, DY) of a pixel centre from the
--  feature's centre of mass in pixel space to the coordinate P DX + Q DY
--  along one axis of the selected space, measured from the mapped centre
--  of mass: for the axes at the angle A, (P, Q) is Turned (T.A, T.C),
--  Turned (T.B, T.D) for the first axis (cos A, sin A) and Turned (T.C,
--  -T.A), Turned (T.D, -T.B) for the second (-sin A, cos A), computed as
--  AMV.Kernels.Blob.Measures computes the principal axes, so that both
--  give the same bits.
--
--  Gold: the extents of a feature along a row contain the coordinate of
--  each of its pixel centres (Feature_Extent, in the body); a median lies
--  within the extents it is selected from (Select_Median, in the body);
--  for every item, Extrema_Angle_Min_X <= Median_Extrema_Angle_X <=
--  Extrema_Angle_Max_X and likewise in y (Finish_Item, in the body).
--  Not proved (tested against sorting): that the selection gives the
--  middle value, and that every pixel of a feature reaches the selection
--  (the tables are read through range tests that never fail).

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.Blob.Extrema
  with SPARK_Mode, Preelaborate
is

   Center_Limit : constant := 2.0 ** 33;
   --  The bound of a centre of mass in pixel space (pixel coordinates lie
   --  below 2**31; AMV.Kernels.Blob.Measures keeps them within 2**33).

   Mass_Limit : constant := Max_Translation + 2.0 ** 98;
   --  The bound of a centre of mass in the selected space.

   Coefficient_Limit : constant := 2.0 ** 65;
   --  The bound of P and Q in a frame row (twice Max_Scale).

   Projection_Limit : constant := 2.0 ** 101;
   --  The bound of a coordinate along a row: abs P DX + abs Q DY with
   --  offsets below 2**34.

   function Valid_Row (P, Q : Long_Float) return Boolean is
     (P >= -Coefficient_Limit and then P <= Coefficient_Limit
      and then Q >= -Coefficient_Limit and then Q <= Coefficient_Limit);

   function Turned (P, Q, Cos_A, Sin_A : Long_Float) return Long_Float
   with
     Pre  => abs P <= Max_Scale and then abs Q <= Max_Scale
             and then abs Cos_A <= 1.0 and then abs Sin_A <= 1.0,
     Post => abs Turned'Result <= Coefficient_Limit;
   --  P Cos_A + Q Sin_A.

   procedure Compute_Extrema
     (Map     : Int32_Matrix;
      Count   : Int32;
      Area    : Int64_Array;
      Cx, Cy  : Real_Array;
      T       : KT.Ks_Transform_2D_Linear;
      Angle   : Long_Float;
      Items   : in out Result_Array;
      Status  : out Ks_Status)
   with
     Pre  => Map'First (1) <= Map'Last (1)
             and then Map'First (2) <= Map'Last (2)
             and then Count >= 1
             and then Area'First = 0
             and then Int64 (Area'Last) = Int64 (Count) - 1
             and then Cx'First = 0 and then Cx'Last = Area'Last
             and then Cy'First = 0 and then Cy'Last = Area'Last
             and then Items'First = 0 and then Items'Last = Area'Last
             and then Bounded_Transform (T)
             and then Angle >= -Max_Extrema_Angle
             and then Angle <= Max_Extrema_Angle,
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory;
   --  The extrema-angle box, measures and medians of every item (see
   --  Ks_Blob_Result) at the angle Angle, from the feature map Map (ID + 1
   --  per pixel), the pixel counts Area, the centres of mass Cx, Cy in
   --  pixel space and the items' centres of mass in the selected space.
   --  Out_Of_Memory when the work tables cannot be allocated (one real
   --  per pixel of the features and a few per feature).

   procedure Box_At_Angle
     (Map    : Int32_Matrix;
      Id     : Int32;
      Cx, Cy : Long_Float;
      Mass_X : Long_Float;
      Mass_Y : Long_Float;
      T      : KT.Ks_Transform_2D_Linear;
      Angle  : Long_Float;
      Box    : out KS.Ks_Rectangle_Affine;
      Found  : out Boolean)
   with
     Pre  => abs Cx <= Center_Limit and then abs Cy <= Center_Limit
             and then abs Mass_X <= Mass_Limit
             and then abs Mass_Y <= Mass_Limit
             and then Bounded_Transform (T)
             and then Angle >= -Max_Extrema_Angle
             and then Angle <= Max_Extrema_Angle,
     Post => (if Found then KS.Valid_Rectangle_Affine (Box));
   --  The smallest rectangle along the axes at Angle around the mapped
   --  pixel squares of the feature numbered Id (ID + 1) in Map, whose
   --  centre of mass is (Cx, Cy) in pixel space and (Mass_X, Mass_Y) in
   --  the selected space. Found is False when no pixel has the number.

   procedure Median_Along
     (Map    : Int32_Matrix;
      Id     : Int32;
      Pixels : Int32;
      Cx, Cy : Long_Float;
      P, Q   : Long_Float;
      Median : out Long_Float;
      Found  : out Boolean;
      Memory : out Boolean)
   with
     Pre  => abs Cx <= Center_Limit and then abs Cy <= Center_Limit
             and then Valid_Row (P, Q),
     Post => Median >= -Projection_Limit and then Median <= Projection_Limit
             and then (if not Memory then not Found);
   --  The median of the coordinates P DX + Q DY of the pixel centres of
   --  the feature numbered Id (Pixels of them, its Pixel_Count), measured
   --  from its centre of mass (Cx, Cy). Memory is False when the work
   --  table cannot be allocated; Found is False (and Median 0) when the
   --  feature has no pixel.

end AMV.Kernels.Blob.Extrema;
