with Ada.Text_IO;
with AMV;
with AMV.GigE_Vision;
with AMV.GigE_Vision.Settings;
with AMV.GigE_Vision_Bayer;
with AMV.Images;
with Interfaces.C;
with Test_GigE_Vision_Fixtures;

procedure Test_GigE_Vision is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type AMV.Images.Grey_8;

   function C_Fake_Start return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_test_fake_start";

   function C_Fake_Set_Packet_Loss
     (Enabled : Interfaces.C.int) return Interfaces.C.int
     with Import, Convention => C,
       External_Name => "amv_test_fake_set_packet_loss";

   function C_Fake_Set_Mono16 return Interfaces.C.int
     with Import, Convention => C,
       External_Name => "amv_test_fake_set_mono16";

   function C_Fake_Set_Mono8 return Interfaces.C.int
     with Import, Convention => C,
       External_Name => "amv_test_fake_set_mono8";

   function C_Fake_Set_Pixel_Format
     (Pixel_Format : Interfaces.C.unsigned) return Interfaces.C.int
     with Import, Convention => C,
       External_Name => "amv_test_fake_set_pixel_format";

   procedure C_Fake_Stop
     with Import, Convention => C, External_Name => "amv_test_fake_stop";

   procedure C_Test_Reset_Stop_Attempts
     with Import, Convention => C,
       External_Name => "amv_aravis_test_reset_stop_attempts";

   procedure C_Test_Fail_Next_Stop
     with Import, Convention => C,
       External_Name => "amv_aravis_test_fail_next_stop";

   function C_Test_Stop_Attempts return Interfaces.C.unsigned
     with Import, Convention => C,
       External_Name => "amv_aravis_test_stop_attempts";

   function C_Test_Selector_Policy return Interfaces.C.int
     with Import, Convention => C,
       External_Name => "amv_aravis_test_selector_policy";

   Camera : AMV.GigE_Vision.Ks_GigE_Camera;
   Frame : AMV.Images.Ks_Image_8_Grey;
   Next_Frame : AMV.Images.Ks_Image_8_Grey;
   Saved_Pixel : AMV.Images.Grey_8;
   Raised : Boolean;

   procedure Check (Condition : Boolean; Message : String) is
   begin
      if not Condition then
         raise Program_Error with Message;
      end if;
   end Check;

   procedure Check_Bad_Parameter (Message : String) is
   begin
      Raised := False;
      begin
         Camera.Start;
      exception
         when AMV.Ks_Bad_Parameter_Exception =>
            Raised := True;
      end;
      Check (Raised, Message);
   end Check_Bad_Parameter;

   procedure Check_Stop_Failure (Message : String) is
   begin
      Raised := False;
      begin
         Camera.Stop;
      exception
         when AMV.Ks_Exception =>
            Raised := True;
      end;
      Check (Raised, Message);
   end Check_Stop_Failure;

   --  The fake camera fills red 200, green 100 and blue 40, so every grey
   --  pixel is (77 * 200 + 75 * 200 + 29 * 40 + 128) / 256 = 123; a
   --  layout with red and blue exchanged would give 93.
   Bayer_Grey : constant AMV.Images.Grey_8 := 123;

   function Grab_Complete return AMV.Images.Ks_Image_8_Grey;

   procedure Check_Bayer_Frame
     (Pixel_Format : AMV.GigE_Vision_Bayer.T.Unsigned_32; Name : String) is
      Grey : AMV.Images.Ks_Image_8_Grey;
   begin
      Check (C_Fake_Set_Pixel_Format
               (Interfaces.C.unsigned (Pixel_Format)) = 0,
             "set fake camera to " & Name);
      Camera.Open ("127.0.0.1");
      Camera.Start;
      Grey := Grab_Complete;
      Camera.Stop;
      Camera.Close;
      Check (AMV.Images.Width (Grey) = 64
             and AMV.Images.Height (Grey) = 48,
             Name & " frame converts to a 64x48 grey image");
      for Y in 0 .. 47 loop
         for X in 0 .. 63 loop
            Check (Grey.Get_Pixel (X, Y) = Bayer_Grey,
                   Name & " pixel is the luma of its 2x2 window");
         end loop;
      end loop;
      Ada.Text_IO.Put_Line ("PASS: loopback " & Name & " frame to grey");
   end Check_Bayer_Frame;

   function Grab_Complete return AMV.Images.Ks_Image_8_Grey is
   begin
      for Attempt in 1 .. 5 loop
         begin
            return Camera.Grab (2_000);
         exception
            when AMV.Ks_Exception =>
               null;
         end;
      end loop;
      raise Program_Error with "No complete frame arrived after packet loss";
   end Grab_Complete;

begin
   Test_GigE_Vision_Fixtures.Run;
   Ada.Text_IO.Put_Line
     ("PASS: GigE Vision spec and production-kernel fixtures");
   Check (not Camera.Is_Open, "default camera is closed");
   Check_Bad_Parameter ("Start on a closed camera is rejected");
   Raised := False;
   begin
      Frame := Camera.Grab (100);
   exception
      when AMV.Ks_Bad_Parameter_Exception =>
         Raised := True;
   end;
   Check (Raised, "Grab on a closed camera is rejected");
   Camera.Stop;
   Camera.Close;

   Raised := False;
   begin
      Camera.Open ("   ");
   exception
      when AMV.Ks_Bad_Parameter_Exception =>
         Raised := True;
   end;
   Check (Raised, "empty device selector is rejected");
   Check (C_Test_Selector_Policy = 0,
          "test adapter accepts only the literal loopback selector");

   Check (C_Fake_Start = 0, "loopback fake camera starts");
   begin
      Check (C_Fake_Set_Packet_Loss (1) = 0, "enable fake packet loss");
      declare
         Scoped_Camera : AMV.GigE_Vision.Ks_GigE_Camera;
      begin
         Scoped_Camera.Open ("127.0.0.1");
         Scoped_Camera.Start;
      end;
      Camera.Open ("127.0.0.1");
      Check (Camera.Is_Open, "explicit loopback address opens");

      Raised := False;
      begin
         Camera.Open ("127.0.0.1");
      exception
         when AMV.Ks_Bad_Parameter_Exception =>
            Raised := True;
      end;
      Check (Raised, "opening an already-open camera is rejected");

      Camera.Start;
      Camera.Start;
      Check (Camera.Is_Streaming, "Start is idempotent");

      Raised := False;
      begin
         Frame := Camera.Grab (0);
      exception
         when AMV.Ks_Bad_Parameter_Exception =>
            Raised := True;
      end;
      Check (Raised, "zero timeout is rejected");

      Raised := False;
      begin
         Frame := Camera.Grab (100);
      exception
         when AMV.GigE_Vision.Ks_GigE_Vision_Timeout_Exception =>
            Raised := True;
      end;
      Check (Raised, "packet loss produces the finite timeout exception");
      Check (Camera.Is_Streaming, "timeout leaves acquisition streaming");

      Check (C_Fake_Set_Packet_Loss (0) = 0, "restore fake packet delivery");
      Frame := Grab_Complete;
      Check (AMV.Images.Width (Frame) > 0
             and AMV.Images.Height (Frame) > 0,
             "captured Mono8 frame dimensions are positive");
      Check (AMV.Images.Width (Frame) = 64
             and AMV.Images.Height (Frame) = 48,
             "captured Mono8 frame dimensions are 64x48");
      Ada.Text_IO.Put_Line ("PASS: loopback Mono8 frame dimensions 64x48");
      Saved_Pixel := Frame.Get_Pixel (0, 0);
      for Index in 1 .. 5 loop
         Next_Frame := Grab_Complete;
      end loop;
      Check (Next_Frame.Get_Pixel (0, 0) /= Saved_Pixel,
             "fake frames have distinct fill values");
      Camera.Stop;
      Camera.Stop;
      Check (not Camera.Is_Streaming, "Stop is idempotent");
      Camera.Start;
      Check (Camera.Is_Streaming, "camera can restart after Stop");

      C_Test_Reset_Stop_Attempts;
      C_Test_Fail_Next_Stop;
      Check_Stop_Failure ("stop failure is reported");
      Check (Camera.Is_Streaming,
             "failed Stop preserves the streaming state");
      Check (C_Test_Stop_Attempts = 1,
             "first Stop attempted acquisition shutdown");
      Camera.Stop;
      Check (C_Test_Stop_Attempts = 2,
             "Stop retries acquisition shutdown");
      Check (not Camera.Is_Streaming,
             "successful Stop retry clears the streaming state");

      Camera.Start;
      C_Test_Reset_Stop_Attempts;
      C_Test_Fail_Next_Stop;
      Check_Stop_Failure ("second stop failure is reported");
      Check (Camera.Is_Streaming,
             "failed Stop leaves resources available to Close");
      Camera.Close;
      Check (C_Test_Stop_Attempts = 2,
             "Close retries acquisition shutdown after Stop failure");
      Check (Frame.Get_Pixel (0, 0) = Saved_Pixel,
             "captured image owns pixels after buffer reuse and Close");
      Check (not Camera.Is_Open, "Close clears the camera state");
      Camera.Close;
      Camera.Stop;

      Check (C_Fake_Set_Mono16 = 0, "set fake camera to Mono16");
      Raised := False;
      begin
         Camera.Open ("127.0.0.1");
      exception
         when AMV.Ks_Exception =>
            Raised := True;
      end;
      Check (Raised, "unsupported pixel format is rejected");
      Check (not Camera.Is_Open, "failed Open leaves camera closed");

      Check_Bayer_Frame
        (AMV.GigE_Vision_Bayer.Arv_Pixel_Format_Bayer_RG_8, "BayerRG8");
      Check_Bayer_Frame
        (AMV.GigE_Vision_Bayer.Arv_Pixel_Format_Bayer_GR_8, "BayerGR8");
      Check_Bayer_Frame
        (AMV.GigE_Vision_Bayer.Arv_Pixel_Format_Bayer_GB_8, "BayerGB8");
      Check_Bayer_Frame
        (AMV.GigE_Vision_Bayer.Arv_Pixel_Format_Bayer_BG_8, "BayerBG8");
      Check (C_Fake_Set_Mono8 = 0, "restore fake camera to Mono8");

      declare
         package Settings renames AMV.GigE_Vision.Settings;
         Value, Low, High : Long_Float;
      begin
         Raised := False;
         begin
            Settings.Set_Gain (Camera, 2.0);
         exception
            when AMV.Ks_Bad_Parameter_Exception =>
               Raised := True;
         end;
         Check (Raised, "settings of a closed camera are rejected");

         Camera.Open ("127.0.0.1");
         Camera.Start;
         Settings.Set_Exposure_Time (Camera, 5_000.0);
         Settings.Get_Exposure_Time (Camera, Value, Low, High);
         Check (abs (Value - 5_000.0) < 1.0 and then Low <= Value
                and then Value <= High,
                "exposure time is set while streaming");
         Settings.Set_Gain (Camera, 3.0);
         Settings.Get_Gain (Camera, Value, Low, High);
         Check (abs (Value - 3.0) < 0.5 and then Low <= Value
                and then Value <= High,
                "gain is set while streaming");
         Raised := False;
         begin
            Settings.Set_Auto_Exposure (Camera, True);
         exception
            when AMV.Ks_Exception =>
               Raised := True;
         end;
         Check (Raised, "a missing ExposureAuto feature is reported");
         Frame := Grab_Complete;
         Camera.Close;
         Ada.Text_IO.Put_Line ("PASS: loopback exposure and gain settings");
      end;
   exception
      when others =>
         Camera.Close;
         C_Fake_Stop;
         raise;
   end;

   C_Fake_Stop;
   Ada.Text_IO.Put_Line ("PASS: loopback camera lifecycle, timeout, and copy lifetime");
   Ada.Text_IO.Put_Line ("PASS: unsupported pixel format and invalid input");
end Test_GigE_Vision;
