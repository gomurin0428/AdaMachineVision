--  The view of a flat symbol in an image, for the two-dimensional
--  symbologies of AMV.Kernels.Code_Reader: points and outlines, the
--  dark pixel at a point, and the perspective mapping from the plane of
--  a symbol to the image. Internal: no entry points of its own (no
--  export); public so that the tests can call it.
--
--  Proved (docs/PROOF.md): no run-time error for any map and mapping.

pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Code_Reader.Dark_Areas;

package AMV.Kernels.Code_Reader.Views
  with SPARK_Mode, Preelaborate
is

   package DA renames AMV.Kernels.Code_Reader.Dark_Areas;

   use type DA.Mark;

   ---------------------------------------------------------------------
   --  Points
   ---------------------------------------------------------------------

   Limit : constant := 2.0 ** 28;

   subtype Coordinate is Long_Float range -Limit .. Limit;

   type Corner is record
      X, Y : Coordinate := 0.0;
   end record;
   --  A point of a map: the pixel (X, Y) covers X .. X + 1 and
   --  Y .. Y + 1.

   type Outline is record
      Upper_Left, Upper_Right, Lower_Right, Lower_Left : Corner;
   end record;
   --  The corners of a symbol as it is printed.

   Span : constant := 2.0 * Limit;
   --  The difference of two coordinates, at most.

   Far : constant := 2.0 * Span;
   --  The distance of two points, at most (twice the larger of the two
   --  differences of their coordinates bounds it).

   Wide : constant := 2.0 * Span * Span;
   --  Off_Line, at most.

   subtype Length_Value is Long_Float range 0.0 .. Far;
   subtype Offset is Long_Float range -Span .. Span;
   subtype Cross is Long_Float range -Wide .. Wide;

   function Distance (A, B : Corner) return Length_Value
   with Post => Distance'Result <= Far;
   --  The postcondition says no more than the subtype: with a contract,
   --  the function is proved once, and not again inside every caller.

   function Off_Line (A, B, P : Corner) return Cross
   with Post => abs Off_Line'Result <= Wide;
   --  The distance of P from the line from A to B, times the length of
   --  the line; positive on the right of the line as the image is seen.

   Most : constant := 2.0 ** 510;
   --  The values that Quotient takes, at most.

   function Quotient
     (X, Y  : Long_Float;
      Bound : Long_Float) return Long_Float
   with Pre  => abs X <= Most and then Y /= 0.0
                and then abs Y <= Most
                and then Bound in 1.0 .. Most,
        Post => abs Quotient'Result <= Bound
                and then (if X >= 0.0 and then Y > 0.0
                          then Quotient'Result >= 0.0);
   --  X / Y where that is within Bound of 0, else Bound with the sign
   --  of X / Y.

   ---------------------------------------------------------------------
   --  Pixels
   ---------------------------------------------------------------------

   function Floor_Index (X : Long_Float; High : Natural) return Natural
   with Pre  => X >= 0.0 and then X <= Far,
        Post => Floor_Index'Result <= High;
   --  The whole part of X, and High where that is more.

   function Dark_At (Map : DA.Mark_Map; X, Y : Long_Float) return Boolean
   is
     (X >= 0.0 and then Y >= 0.0
      and then X < Long_Float (Map'Length (2))
      and then Y < Long_Float (Map'Length (1))
      and then Map (Floor_Index (Y, Map'Last (1)),
                    Floor_Index (X, Map'Last (2))) /= DA.Light)
   with Pre => DA.Valid_Map (Map);
   --  The pixel that holds the point is dark (outside the map: light).

   ---------------------------------------------------------------------
   --  The mapping
   ---------------------------------------------------------------------

   Tilt_Limit : constant := 2.0 ** 100;
   --  The two factors of a mapping that make the view a perspective
   --  one, at most.

   Factor_Limit : constant := 2.0 ** 130;
   --  The other factors of a mapping, at most.

   subtype Tilt is Long_Float range -Tilt_Limit .. Tilt_Limit;
   subtype Factor is Long_Float range -Factor_Limit .. Factor_Limit;

   type Mapping is record
      G, H       : Tilt := 0.0;
      A, B, D, E : Factor := 0.0;
      X0, Y0     : Coordinate := 0.0;
   end record;
   --  The perspective mapping that takes the point (U, V) of the plane
   --  of a symbol to the point
   --  ((A U + B V + X0) / W, (D U + E V + Y0) / W) of the image, with
   --  W = G U + H V + 1.

   function Factor_Of
     (From, To : Coordinate;
      T        : Tilt) return Factor
   with Post => abs Factor_Of'Result <= Factor_Limit;
   --  To - From + T * To.
   --  A factor of the mapping that takes (0, 0) to a point with the
   --  coordinate From and (1, 0), or (0, 1), to one with the coordinate
   --  To, with the factor T of the perspective view along that axis.

   subtype Spread is Long_Float range -4.0 .. 4.0;
   --  A coordinate of the plane of a symbol.

   procedure Project
     (M     : Mapping;
      U, V  : Spread;
      X, Y  : out Long_Float;
      Ahead : out Boolean)
   with Global => null, Post => abs X <= Far and then abs Y <= Far;
   --  The point (X, Y) of the image to which the mapping takes (U, V).
   --  Not Ahead: the mapping gives none (W is not above 1.0E-6). A
   --  point farther than Far from an axis is given at Far from it: no
   --  pixel is there, and no corner.

   function Dark_In
     (Map  : DA.Mark_Map;
      M    : Mapping;
      U, V : Spread) return Boolean
   with Pre => DA.Valid_Map (Map);
   --  The pixel to which the mapping takes (U, V) is dark.

end AMV.Kernels.Code_Reader.Views;
