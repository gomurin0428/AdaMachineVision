--  Runs every test area of the library in one program.
--
--  Each Test_<area> procedure is a complete standalone main: it runs its
--  checks and prints the running totals of the shared counters in
--  AMV_Test_Support. The final Finish call below prints the totals over
--  all areas and sets the exit status from the cumulative failure count
--  (1 if any check in any area failed).
--
--  Run it from the repository root: Test_Image_File writes its files to
--  tests/output relative to the current directory.

with Ada.Text_IO;

with AMV_Test_Support;

with Test_Transforms;
with Test_Coordinate_Spaces;
with Test_Images;
with Test_Image_File;
with Test_Kernels;
with Test_Shapes;
with Test_Regions;
with Test_Geometry;
with Test_Tools;
with Test_Image_Math;
with Test_Test_Images;
with Test_Image_Processing_Filters;
with Test_Blob;
with Test_Caliper;
with Test_Find_Line;
with Test_Find_Circle;
with Test_IP_One_Image;
with Test_IP_Geometry;
with Test_Dimensioning;
with Test_Create_Shapes;
with Test_Calib_Fix;
with Test_CNL_Search;
with Test_PM_Align;
with Test_Tool_Group;
with Test_Robustness;

procedure Test_Suite is

   procedure Run_Area (Name : String; Area : not null access procedure) is
   begin
      Ada.Text_IO.Put_Line ("=== " & Name);
      Area.all;
   end Run_Area;

begin
   --  Ordered from the packages with no AMV dependencies up to the ones
   --  that build on them, so that a failure low in the stack shows first.
   Run_Area ("Test_Kernels", Test_Kernels'Access);
   Run_Area ("Test_Transforms", Test_Transforms'Access);
   Run_Area ("Test_Coordinate_Spaces", Test_Coordinate_Spaces'Access);
   Run_Area ("Test_Geometry", Test_Geometry'Access);
   Run_Area ("Test_Tools", Test_Tools'Access);
   Run_Area ("Test_Images", Test_Images'Access);
   Run_Area ("Test_Image_File", Test_Image_File'Access);
   Run_Area ("Test_Shapes", Test_Shapes'Access);
   Run_Area ("Test_Regions", Test_Regions'Access);
   Run_Area ("Test_Image_Math", Test_Image_Math'Access);
   Run_Area ("Test_Test_Images", Test_Test_Images'Access);
   Run_Area ("Test_Image_Processing_Filters",
             Test_Image_Processing_Filters'Access);
   Run_Area ("Test_Blob", Test_Blob'Access);
   Run_Area ("Test_Caliper", Test_Caliper'Access);
   Run_Area ("Test_Find_Line", Test_Find_Line'Access);
   Run_Area ("Test_Find_Circle", Test_Find_Circle'Access);
   Run_Area ("Test_IP_One_Image", Test_IP_One_Image'Access);
   Run_Area ("Test_IP_Geometry", Test_IP_Geometry'Access);
   Run_Area ("Test_Dimensioning", Test_Dimensioning'Access);
   Run_Area ("Test_Create_Shapes", Test_Create_Shapes'Access);
   Run_Area ("Test_Calib_Fix", Test_Calib_Fix'Access);
   Run_Area ("Test_CNL_Search", Test_CNL_Search'Access);
   Run_Area ("Test_PM_Align", Test_PM_Align'Access);
   Run_Area ("Test_Tool_Group", Test_Tool_Group'Access);
   Run_Area ("Test_Robustness", Test_Robustness'Access);

   Ada.Text_IO.Put_Line ("=== Total");
   AMV_Test_Support.Finish;
end Test_Suite;
