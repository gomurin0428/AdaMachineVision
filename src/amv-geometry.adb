pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Checks;

package body AMV.Geometry is

   package KG renames AMV.Kernels.Geometry;

   subtype Int32 is AMV.Kernels.Int32;
   subtype Ks_Status is AMV.Kernels.Ks_Status;

   use type Int32;

   procedure Check (Status : Ks_Status) renames AMV.Checks.Check;

   ---------------------------------------------------------------------
   --  Distances and projections
   ---------------------------------------------------------------------

   function Distance (P, Q : Point_2D) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      KG.Distance (P, Q, Result, Status);
      Check (Status);
      return Result;
   end Distance;

   function Signed_Distance (P : Point_2D; Line : Line_2D) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      KG.Signed_Distance (P, Line, Result, Status);
      Check (Status);
      return Result;
   end Signed_Distance;

   function Distance (P : Point_2D; Line : Line_2D) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      KG.Line_Distance (P, Line, Result, Status);
      Check (Status);
      return Result;
   end Distance;

   function Project (P : Point_2D; Line : Line_2D) return Point_2D is
      Result : Point_2D;
      Status : Ks_Status;
   begin
      KG.Project (P, Line, Result, Status);
      Check (Status);
      return Result;
   end Project;

   function Position_Along (P : Point_2D; Line : Line_2D) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      KG.Position_Along (P, Line, Result, Status);
      Check (Status);
      return Result;
   end Position_Along;

   function Distance (P : Point_2D; Circle : Circle_2D) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      KG.Circle_Distance (P, Circle, Result, Status);
      Check (Status);
      return Result;
   end Distance;

   ---------------------------------------------------------------------
   --  Intersections and angles
   ---------------------------------------------------------------------

   procedure Intersect
     (Line_1, Line_2 : Line_2D;
      Point          : out Point_2D;
      Parallel       : out Boolean)
   is
      Flag   : Int32;
      Status : Ks_Status;
   begin
      KG.Intersect_Lines (Line_1, Line_2, Point, Flag, Status);
      Check (Status);
      Parallel := Flag = AMV.Kernels.True_Value;
   end Intersect;

   procedure Intersect
     (Line         : Line_2D;
      Circle       : Circle_2D;
      Point_1      : out Point_2D;
      Point_2      : out Point_2D;
      Count        : out Natural)
   is
      Points : Int32;
      Status : Ks_Status;
   begin
      KG.Intersect_Line_Circle (Line, Circle, Point_1, Point_2, Points,
                                Status);
      Check (Status);
      Count := Natural (Points);
   end Intersect;

   procedure Intersect
     (Circle_1, Circle_2 : Circle_2D;
      Point_1            : out Point_2D;
      Point_2            : out Point_2D;
      Count              : out Natural)
   is
      Points : Int32;
      Status : Ks_Status;
   begin
      KG.Intersect_Circles (Circle_1, Circle_2, Point_1, Point_2, Points,
                            Status);
      Check (Status);
      Count := Natural (Points);
   end Intersect;

   function Angle_Between (Line_1, Line_2 : Line_2D) return Real is
      Result : Real;
      Status : Ks_Status;
   begin
      KG.Angle_Between (Line_1, Line_2, Result, Status);
      Check (Status);
      return Result;
   end Angle_Between;

   ---------------------------------------------------------------------
   --  Fits
   ---------------------------------------------------------------------

   procedure Fit_Line
     (Points    : Point_Array;
      Line      : out Line_2D;
      RMS_Error : out Real)
   is
      Status : Ks_Status;
   begin
      KG.Fit_Line (KG.Point_Array (Points), Line, RMS_Error, Status);
      Check (Status);
   end Fit_Line;

   procedure Fit_Line
     (Points        : Point_Array;
      Num_To_Ignore : Natural;
      Line          : out Line_2D;
      RMS_Error     : out Real;
      Used          : out Boolean_Array)
   is
      Status : Ks_Status;
   begin
      KG.Fit_Line_Robust (KG.Point_Array (Points), Int32 (Num_To_Ignore),
                          Line, RMS_Error, KG.Flag_Array (Used), Status);
      Check (Status);
   end Fit_Line;

   procedure Fit_Circle
     (Points    : Point_Array;
      Circle    : out Circle_2D;
      RMS_Error : out Real)
   is
      Status : Ks_Status;
   begin
      KG.Fit_Circle (KG.Point_Array (Points), Circle, RMS_Error, Status);
      Check (Status);
   end Fit_Circle;

   procedure Fit_Circle
     (Points        : Point_Array;
      Num_To_Ignore : Natural;
      Circle        : out Circle_2D;
      RMS_Error     : out Real;
      Used          : out Boolean_Array)
   is
      Status : Ks_Status;
   begin
      KG.Fit_Circle_Robust (KG.Point_Array (Points), Int32 (Num_To_Ignore),
                            Circle, RMS_Error, KG.Flag_Array (Used), Status);
      Check (Status);
   end Fit_Circle;

end AMV.Geometry;
