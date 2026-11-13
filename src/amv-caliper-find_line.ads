--  Find line: the counterpart of CogFindLineTool (run parameters
--  CogFindLine, results CogFindLineResults and CogFindLineResult).
--
--  NumCalipers calipers are placed along the expected line segment, from
--  its start point to its end point (the first and the last on the end
--  points), each searching along the segment's direction turned by
--  CaliperSearchDirection (Pi / 2 by default: across the segment). Every
--  caliper that finds an edge contributes the position of its best
--  result, and a line is fitted to those points by orthogonal least
--  squares, NumToIgnore of them discarded as outliers (one at a time, the
--  point whose removal lowers the RMS error most). Everything is reported
--  in the input image's selected space.
--
--     Tool.Input_Image := Image;
--     Tool.Run_Params.Expected_Line_Segment.Set_Start_End
--       (40.0, 100.0, 200.0, 120.0);
--     Tool.Run;
--     Line := Tool.Results.Get_Line;
--
--  The SPARK kernel AMV.Kernels.Find_Line does the work (C API:
--  include/amv_caliper.h); its spec describes the placement, the fit and
--  the failures. Its proofs cover, besides the absence of run-time errors,
--  that the results hold one item per caliper, that only found points are
--  used, and that NumPointsUsed <= NumPointsFound <= NumCalipers count
--  exactly the used and found items.

pragma SPARK_Mode (Off);
pragma Validity_Checks ("F");

with AMV.Images;
with AMV.Kernels.Find_Line;
with AMV.Shapes;
with AMV.Tools;

private with AMV.Shared_Handles;

package AMV.Caliper.Find_Line is

   package KF renames AMV.Kernels.Find_Line;

   Defaults : constant KF.Ks_Find_Line_Run_Params := (others => <>);
   --  The kernel's defaults, which the record below starts from.

   type Ks_Find_Line is record
      Expected_Line_Segment     : AMV.Shapes.Ks_Line_Segment;
      Num_Calipers              : Integer := Integer (Defaults.Num_Calipers);
      Caliper_Search_Length     : Real := Defaults.Caliper_Search_Length;
      Caliper_Projection_Length : Real := Defaults.Caliper_Projection_Length;
      Caliper_Search_Direction  : Real := Defaults.Caliper_Search_Direction;
      Num_To_Ignore             : Integer :=
        Integer (Defaults.Num_To_Ignore);
      Decrement_Num_To_Ignore   : Boolean := False;
      Caliper_Run_Params        : AMV.Caliper.Ks_Caliper;
   end record;
   --  CogFindLine. Expected_Line_Segment is taken in its own selected
   --  space (default "."; default segment from (0, 0) to (100, 0)).
   --  Defaults: 6 calipers, search length 30, projection length 10,
   --  search direction Pi / 2, NumToIgnore 0, DecrementNumToIgnore False
   --  (when set, NumToIgnore is lowered as far as needed to keep 2
   --  points), and the default caliper parameters. Checked when the tool
   --  runs: NumCalipers in 2 .. 1000, NumToIgnore in 0 .. NumCalipers - 2,
   --  lengths > 0, a segment of length > 0 (Ks_Bad_Parameter_Exception).

   function Get_Caliper_Region
     (Params : Ks_Find_Line;
      Index  : Natural) return AMV.Shapes.Ks_Rectangle_Affine;
   --  (AMV name) The region of caliper Index (0-based), in the expected
   --  segment's selected space (for display; VisionPro draws them as a
   --  record graphic). Constraint_Error unless Index < NumCalipers.

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   type Ks_Find_Line_Result is record
      Found            : Boolean := False;
      Used             : Boolean := False;
      X                : Real := 0.0;
      Y                : Real := 0.0;
      Distance_To_Line : Real := 0.0;
      Caliper_Results  : AMV.Caliper.Ks_Caliper_Results;
   end record;
   --  CogFindLineResult: whether the caliper found an edge, whether its
   --  point was used in the fit, the point (0 when not found), its
   --  distance from the fitted line (>= 0) and the caliper's own results.

   type Ks_Find_Line_Results is tagged private;
   --  CogFindLineResults: one item per caliper, in the order of the
   --  calipers; empty before the first successful run.

   function Count (Results : Ks_Find_Line_Results) return Natural;
   function Item
     (Results : Ks_Find_Line_Results;
      Index   : Natural) return Ks_Find_Line_Result;
   --  Item Index (0-based); Constraint_Error unless Index < Count.

   function Get_Line
     (Results : Ks_Find_Line_Results) return AMV.Shapes.Ks_Line;
   --  The fitted line, through the centroid of the used points and
   --  directed like the expected segment. Ks_Bad_Parameter_Exception
   --  before a successful run.

   function Get_Line_Segment
     (Results : Ks_Find_Line_Results) return AMV.Shapes.Ks_Line_Segment;
   --  The part of the line between the projections of the two extreme
   --  used points.

   function RMS_Error (Results : Ks_Find_Line_Results) return Real;
   function Num_Points_Found (Results : Ks_Find_Line_Results) return Natural;
   function Num_Points_Used (Results : Ks_Find_Line_Results) return Natural;
   --  0 before a successful run.

   ---------------------------------------------------------------------
   --  The tool (CogFindLineTool)
   ---------------------------------------------------------------------

   type Ks_Find_Line_Tool is new AMV.Tools.Ks_Tool with record
      Input_Image : AMV.Images.Ks_Image_8_Grey;
      Run_Params  : Ks_Find_Line;
      Results     : Ks_Find_Line_Results;
   end record;

   overriding procedure Execute (Tool : in out Ks_Find_Line_Tool);
   --  Runs the calipers and fits the line. Raises
   --  Ks_Image_No_Pixels_Exception for an unallocated image,
   --  Ks_Bad_Parameter_Exception for bad run parameters, and Ks_Exception
   --  when fewer than 2 points remain for the fit; Run reports them in
   --  Run_Status (and leaves no results).

   overriding procedure Reset_Results (Tool : in out Ks_Find_Line_Tool);

private

   procedure Destroy (Handle : in out KF.Ks_Find_Line_Results);

   package Results_Holders is new AMV.Shared_Handles
     (KF.Ks_Find_Line_Results, null, Destroy);

   type Ks_Find_Line_Results is tagged record
      Holder : Results_Holders.Holder;
   end record;

end AMV.Caliper.Find_Line;
