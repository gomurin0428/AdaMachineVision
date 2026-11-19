pragma Validity_Checks ("F");
with AMV.Kernels.Numerics;

package body AMV.Kernels.Code_Reader.Views
  with SPARK_Mode
is

   package N renames AMV.Kernels.Numerics;

   pragma Compile_Time_Error
     (Most /= N.Mul_Limit, "Most is the limit of N.Quotient_Within");

   function Distance (A, B : Corner) return Length_Value is
   begin
      return N.Hypot (B.X - A.X, B.Y - A.Y);
   end Distance;

   function Off_Line (A, B, P : Corner) return Cross is
   begin
      return N.Mul_Within (B.X - A.X, P.Y - A.Y, Span, Span)
        - N.Mul_Within (B.Y - A.Y, P.X - A.X, Span, Span);
   end Off_Line;

   function Quotient
     (X, Y  : Long_Float;
      Bound : Long_Float) return Long_Float
   is
      Q    : Long_Float;
      Fits : Boolean;
   begin
      N.Quotient_Within (abs X, abs Y, Bound, Q, Fits);
      if not Fits then
         Q := Bound;
      end if;
      return (if (X < 0.0) = (Y < 0.0) then Q else -Q);
   end Quotient;

   function Floor_Index (X : Long_Float; High : Natural) return Natural is
   begin
      return Natural'Min (Natural (Long_Float'Floor (X)), High);
   end Floor_Index;

   function Factor_Of
     (From, To : Coordinate;
      T        : Tilt) return Factor is
   begin
      return To - From + N.Mul_Within (T, To, Tilt_Limit, Limit);
   end Factor_Of;

   subtype Wide_Factor is Long_Float
     range -4.0 * Factor_Limit .. 4.0 * Factor_Limit;

   function Times (F : Factor; U : Spread) return Wide_Factor is
     (N.Times_Small (F, U));
   --  A part of the sums of Project: a factor of a mapping times a
   --  coordinate.

   procedure Project
     (M     : Mapping;
      U, V  : Spread;
      X, Y  : out Long_Float;
      Ahead : out Boolean)
   is
      W : constant Long_Float := Times (M.G, U) + Times (M.H, V) + 1.0;
   begin
      Ahead := W > 1.0E-6;
      if Ahead then
         X := Quotient (Times (M.A, U) + Times (M.B, V) + M.X0, W, Far);
         Y := Quotient (Times (M.D, U) + Times (M.E, V) + M.Y0, W, Far);
      else
         X := 0.0;
         Y := 0.0;
      end if;
   end Project;

   function Dark_In
     (Map  : DA.Mark_Map;
      M    : Mapping;
      U, V : Spread) return Boolean
   is
      X, Y  : Long_Float;
      Ahead : Boolean;
   begin
      Project (M, U, V, X, Y, Ahead);
      return Ahead and then Dark_At (Map, X, Y);
   end Dark_In;

end AMV.Kernels.Code_Reader.Views;
