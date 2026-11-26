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

with AMV.Spec.Image_Convert;
with AMV.Spec.IP_Two_Image;
with AMV.Spec.Pixel_Map;
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

   procedure Test_Image_Convert is
      package S renames AMV.Spec.Image_Convert;
      use type S.Level;
   begin
      Section ("AMV.Spec.Image_Convert: the high byte, the intensity, the "
               & "planes");
      pragma Assert (S.High_Byte (16#1234#) = 16#12#);
      Expect ("the high byte of 16#1234# is 16#12#");
      pragma Assert (S.High_Byte (255) = 0);
      Expect ("the high byte of 255 is 0");
      pragma Assert (S.Intensity (255, 255, 255) = 255);
      Expect ("the intensity of white is 255: the weights add up to 1");
      pragma Assert (S.Intensity (255, 0, 0) = 76);
      Expect ("the intensity of red: 0.299 * 255 = 76.245 gives 76");
      pragma Assert (S.Intensity (0, 0, 255) = 29);
      Expect ("the intensity of blue: 0.114 * 255 = 29.07 gives 29");
      pragma Assert (S.Intensity (0, 12, 4) = 8);
      Expect ("a half is rounded up: 0.587 * 12 + 0.114 * 4 = 7.5 gives 8");
      pragma Assert (S.Colour (6, 1, 2, 3) = 1
                     and then S.Colour (7, 1, 2, 3) = 2
                     and then S.Colour (8, 1, 2, 3) = 3);
      Expect ("Plane0, Plane1 and Plane2 are the red, green and blue "
              & "planes");
      pragma Assert (S.Colour (1, 255, 0, 0) = 76);
      Expect ("Intensity of a colour pixel is its intensity");
   end Test_Image_Convert;

   procedure Test_Pixel_Map is
      package S renames AMV.Spec.Pixel_Map;
      use type S.Level;
      Invert : constant S.Table := [for V in S.Level => 255 - V]
        with Ghost;
   begin
      Section ("AMV.Spec.Pixel_Map: map[value] in the region, the value "
               & "elsewhere");
      pragma Assert (S.Mapped (Invert, True, 10) = 245);
      Expect ("a pixel of the region gets map[value]: 255 - 10 = 245");
      pragma Assert (S.Mapped (Invert, False, 10) = 10);
      Expect ("a pixel outside the region keeps its value");
      pragma Assert (S.Mapped ([others => 7], True, 200) = 7);
      Expect ("a constant map gives its constant in the region");
   end Test_Pixel_Map;

   procedure Run_All is
   begin
      Test_IP_Two_Image;
      Test_Image_Convert;
      Test_Pixel_Map;
      Ada.Text_IO.Put_Line ("Test_Spec done");
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);

begin
   Main;
end Test_Spec;
