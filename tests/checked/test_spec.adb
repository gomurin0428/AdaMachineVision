--  The specifications of the kernels (AMV.Spec) on their own, on values
--  worked by hand from the definitions that they transcribe. The proofs
--  tie the kernels to the specifications; these tests tie the
--  specifications to their definitions (docs/PLATINUM.md).
--
--  Ghost functions can be called only from ghost code and assertions, so
--  each check is a pragma Assert, which this unit checks, and then Expect,
--  which counts it. Only the build of the tests that checks every
--  contract has this unit; the other ignores ghost code, and its
--  Test_Spec (tests/library) does nothing.

pragma Assertion_Policy (Assert => Check, Ghost => Check);

with Ada.Text_IO;

with AMV.Spec.IP_Two_Image;
with AMV_Test_Support;

procedure Test_Spec is

   use AMV_Test_Support;

   procedure Expect (Description : String) is
   begin
      Check (True, Description);
   end Expect;
   --  Counts a check whose pragma Assert has just held.

   procedure Test_IP_Two_Image is
      package S renames AMV.Spec.IP_Two_Image;
      use type S.Level;
   begin
      Section ("AMV.Spec.IP_Two_Image: the formulas of the documentation");
      --  Add: Bounded min (A + B, 255), Wrap (A + B) mod 256, Shift
      --  (A + B) / 2 rounded down.
      pragma Assert (S.Add (0, 200, 100) = 255);
      Expect ("Add, Bounded: 200 + 100 is limited to 255");
      pragma Assert (S.Add (0, 100, 50) = 150);
      Expect ("Add, Bounded: 100 + 50 = 150");
      pragma Assert (S.Add (1, 200, 100) = 44);
      Expect ("Add, Wrap: 300 mod 256 = 44");
      pragma Assert (S.Add (1, 255, 1) = 0);
      Expect ("Add, Wrap: 256 mod 256 = 0");
      pragma Assert (S.Add (2, 255, 254) = 254);
      Expect ("Add, Shift: 509 / 2 rounded down = 254");
      pragma Assert (S.Add (2, 1, 0) = 0);
      Expect ("Add, Shift: 1 / 2 rounded down = 0");
      --  Subtract (A - B): Bounded max (A - B, 0), Wrap (A - B) mod 256,
      --  Shift (A - B + 256) / 2 rounded down, Absolute abs (A - B).
      pragma Assert (S.Subtract (0, 50, 100) = 0);
      Expect ("Subtract, Bounded: 50 - 100 is limited to 0");
      pragma Assert (S.Subtract (0, 200, 100) = 100);
      Expect ("Subtract, Bounded: 200 - 100 = 100");
      pragma Assert (S.Subtract (1, 50, 100) = 206);
      Expect ("Subtract, Wrap: -50 mod 256 = 206");
      pragma Assert (S.Subtract (2, 100, 100) = 128);
      Expect ("Subtract, Shift: A - B = 0 gives 128");
      pragma Assert (S.Subtract (2, 255, 0) = 255);
      Expect ("Subtract, Shift: (255 + 256) / 2 rounded down = 255");
      pragma Assert (S.Subtract (2, 0, 255) = 0);
      Expect ("Subtract, Shift: (-255 + 256) / 2 rounded down = 0");
      pragma Assert (S.Subtract (3, 50, 100) = 50);
      Expect ("Subtract, Absolute: abs (50 - 100) = 50");
      --  MinMax: Min min (A, B), Max max (A, B).
      pragma Assert (S.Min_Max (0, 7, 3) = 3);
      Expect ("MinMax, Min: min (7, 3) = 3");
      pragma Assert (S.Min_Max (1, 7, 3) = 7);
      Expect ("MinMax, Max: max (7, 3) = 7");
   end Test_IP_Two_Image;

   procedure Run_All is
   begin
      Test_IP_Two_Image;
      Ada.Text_IO.Put_Line ("Test_Spec done");
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Spec;
