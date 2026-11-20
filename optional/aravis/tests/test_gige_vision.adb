with Ada.Text_IO;
with AMV;
with AMV.GigE_Vision;
with AMV.Images;
with Interfaces.C;

procedure Test_GigE_Vision is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type AMV.Images.Grey_8;

   function C_Test_Copy_Rows return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_test_copy_rows";

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
   Check (C_Test_Copy_Rows = 0, "C Mono8 padding and size fixtures");
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
      Check (C_Fake_Set_Mono8 = 0, "restore fake camera to Mono8");
   exception
      when others =>
         Camera.Close;
         C_Fake_Stop;
         raise;
   end;

   C_Fake_Stop;
   Ada.Text_IO.Put_Line ("PASS: C row-copy fixtures");
   Ada.Text_IO.Put_Line ("PASS: loopback camera lifecycle, timeout, and copy lifetime");
   Ada.Text_IO.Put_Line ("PASS: unsupported pixel format and invalid input");
end Test_GigE_Vision;
