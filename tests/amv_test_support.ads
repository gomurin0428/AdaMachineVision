--  Minimal test harness shared by every test procedure.
--
--  A test procedure calls Section to label what follows, then Check /
--  Check_Near. Failures are printed immediately with the current section.
--  Finish prints the totals and sets the process exit status (1 if any
--  check failed); test_suite calls it once at the end, and a test procedure
--  used as a standalone main is wrapped so that Finish runs too (see
--  Standalone).
--
--  Stack size: every test runs on the environment task's stack. A
--  program that links the tasking runtime (anything using AMV.Tools,
--  which times runs with Ada.Real_Time, and therefore test_suite) gets a
--  main stack of only 2 MB on Windows. Keep large sample sets and
--  temporary arrays on the heap or stream over them; an array of a few
--  hundred thousand points built on the stack overflows it.

with Ada.Exceptions;

with AMV;

package AMV_Test_Support is

   procedure Section (Name : String);

   procedure Check (Condition : Boolean; Description : String);

   procedure Check_Near
     (Actual, Expected : AMV.Real;
      Tolerance        : AMV.Real;
      Description      : String);
   --  Passes when abs (Actual - Expected) <= Tolerance. Prints both values
   --  on failure.

   procedure Check_Angle_Near
     (Actual, Expected : AMV.Real;
      Tolerance        : AMV.Real;
      Description      : String);
   --  Like Check_Near on the angle difference normalised to (-Pi, Pi].

   generic
      with procedure Body_Of_Test;
   procedure Check_Raises (Description : String);
   --  Passes when Body_Of_Test raises any exception.

   generic
      with procedure Action;
      Expected : Ada.Exceptions.Exception_Id;
   procedure Check_Raises_Exactly (Description : String);
   --  One check that passes only when Action raises the exception whose
   --  identity is Expected (write Some_Exception'Identity). No exception,
   --  or a different one, is a failure; the failure message names the
   --  exception that was raised and its message. Prefer this to
   --  Check_Raises when a test must show the documented exception type:
   --
   --     procedure Bad_Width is ... end Bad_Width;
   --     procedure Check_Bad_Width is new Check_Raises_Exactly
   --       (Bad_Width, AMV.Ks_Bad_Parameter_Exception'Identity);
   --     ...
   --     Check_Bad_Width ("negative width is rejected");

   procedure Fail (Description : String);
   --  An unconditional failure (for unexpected paths).

   function Failures return Natural;
   function Checks return Natural;

   procedure Finish;
   --  Prints "<checks> checks, <failures> failures" and sets the exit
   --  status. Finishing twice prints twice; harmless.

   generic
      with procedure Test;
   procedure Standalone;
   --  Runs Test, catching and reporting any unexpected exception as a
   --  failure, then calls Finish. Each tests/test_<area>.adb main is written
   --  as:
   --
   --     procedure Test_Blob is
   --        procedure Run_All is ... end Run_All;
   --        procedure Main is new AMV_Test_Support.Standalone (Run_All);
   --     begin
   --        Main;
   --     end Test_Blob;
   --
   --  test_suite does not use Standalone for the areas it calls; it calls
   --  each Test_<area> procedure, whose own Finish call only prints running
   --  totals, and then calls Finish at the end.

end AMV_Test_Support;
