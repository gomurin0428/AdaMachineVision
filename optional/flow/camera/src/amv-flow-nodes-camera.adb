pragma SPARK_Mode (Off);

with Ada.Exceptions;
with Ada.Real_Time;

with AMV.Flow.Kinds;
with AMV.Flow.Values;
with AMV.GigE_Vision;
with AMV.GigE_Vision.Settings;
with AMV.Images;

package body AMV.Flow.Nodes.Camera is

   use AMV.Flow.Values;

   package Settings renames AMV.GigE_Vision.Settings;

   type Camera_Node is new Ks_Flow_Node with record
      Device        : AMV.GigE_Vision.Ks_GigE_Camera;
      Opened_Id     : Unbounded_String;
      Camera_Id     : Unbounded_String;
      Exposure_Us   : Real := 0.0;
      Gain          : Real := -1.0;
      Auto_Exposure : Boolean := False;
      Timeout_Ms    : Positive := 2_000;
      Send_Settings : Boolean := True;
      Image_Out     : Ks_Flow_Value;
      Exposure_Now  : Ks_Flow_Value;
      Gain_Now      : Ks_Flow_Value;
   end record;

   overriding function Kind_Id (Node : Camera_Node) return String;
   overriding function Ports (Node : Camera_Node) return Port_Array;
   overriding function Params (Node : Camera_Node) return Param_Array;
   overriding procedure Set_Param
     (Node : in out Camera_Node; Name : String; Value : Ks_Flow_Value);
   overriding function Get_Param
     (Node : Camera_Node; Name : String) return Ks_Flow_Value;
   overriding procedure Set_Input
     (Node : in out Camera_Node; Port : String; Value : Ks_Flow_Value);
   overriding procedure Clear_Inputs (Node : in out Camera_Node);
   overriding function Problem (Node : Camera_Node) return String;
   overriding procedure Execute (Node : in out Camera_Node);
   overriding function Get_Output
     (Node : Camera_Node; Port : String) return Ks_Flow_Value;

   overriding function Kind_Id (Node : Camera_Node) return String is
     ("Camera");

   overriding function Ports (Node : Camera_Node) return Port_Array is
     [Out_Port ("Image", Image_8_Grey_Type, "the newest frame"),
      Out_Port ("ExposureUs", Real_Type, "as read back from the camera"),
      Out_Port ("Gain", Real_Type, "as read back from the camera")];

   overriding function Params (Node : Camera_Node) return Param_Array is
     [String_Param_Of ("CameraId",
                       "the camera's IPv4 address or Aravis device ID"),
      Real_Param_Of ("ExposureUs", 0.0, 1.0E7, "us",
                     "the exposure time; 0 leaves the camera's"),
      Real_Param_Of ("Gain", -1.0, 1.0E3, "",
                     "the gain; negative leaves the camera's"),
      Boolean_Param_Of ("AutoExposure", "the camera sets its exposure"),
      Integer_Param_Of ("TimeoutMs", 10.0, 60_000.0,
                        "how long a run waits for a frame")];

   overriding procedure Set_Param
     (Node : in out Camera_Node; Name : String; Value : Ks_Flow_Value) is
   begin
      if Name = "CameraId" then
         Node.Camera_Id := To_Unbounded_String (Value.As_String);
      elsif Name = "ExposureUs" then
         Node.Exposure_Us := Value.As_Real;
      elsif Name = "Gain" then
         Node.Gain := Value.As_Real;
      elsif Name = "AutoExposure" then
         Node.Auto_Exposure := Value.As_Boolean;
      elsif Name = "TimeoutMs" then
         Node.Timeout_Ms := Positive (Value.As_Integer);
         return;
      else
         raise Ks_Flow_Exception with
           "Camera has no parameter """ & Name & """";
      end if;
      Node.Send_Settings := True;
   end Set_Param;

   overriding function Get_Param
     (Node : Camera_Node; Name : String) return Ks_Flow_Value is
   begin
      if Name = "CameraId" then
         return From_String (To_String (Node.Camera_Id));
      elsif Name = "ExposureUs" then
         return From_Real (Node.Exposure_Us);
      elsif Name = "Gain" then
         return From_Real (Node.Gain);
      elsif Name = "AutoExposure" then
         return From_Boolean (Node.Auto_Exposure);
      elsif Name = "TimeoutMs" then
         return From_Integer (Long_Long_Integer (Node.Timeout_Ms));
      end if;
      raise Ks_Flow_Exception with "Camera has no parameter """ & Name & """";
   end Get_Param;

   overriding procedure Set_Input
     (Node : in out Camera_Node; Port : String; Value : Ks_Flow_Value) is
   begin
      raise Ks_Flow_Exception with "Camera has no input """ & Port & """";
   end Set_Input;

   overriding procedure Clear_Inputs (Node : in out Camera_Node) is
   begin
      Node.Image_Out := No_Value;
      Node.Exposure_Now := No_Value;
      Node.Gain_Now := No_Value;
   end Clear_Inputs;

   overriding function Problem (Node : Camera_Node) return String is
     (if Length (Node.Camera_Id) = 0 then "no camera (CameraId)" else "");

   function Grab_Latest (Node : in out Camera_Node)
                         return AMV.Images.Ks_Image_8_Grey
   is
      --  One Grab that waits up to the timeout, then quick Grabs that
      --  empty the stream's queue: frames that arrived while the flow ran
      --  are dropped, and a frame that came with no free buffer (returned
      --  at once, incomplete) is skipped.
      use type Ada.Real_Time.Time;
      use type Ada.Real_Time.Time_Span;
      Result  : AMV.Images.Ks_Image_8_Grey;
      Got     : Boolean := False;
      Started : Ada.Real_Time.Time;
      Last    : Ada.Exceptions.Exception_Occurrence;
   begin
      for Attempt in 1 .. 8 loop
         Started := Ada.Real_Time.Clock;
         begin
            Result := Node.Device.Grab
              (if Attempt = 1 then Node.Timeout_Ms else 1);
            Got := True;
         exception
            when E : AMV.GigE_Vision.Ks_GigE_Vision_Timeout_Exception
                   | AMV.Ks_Exception =>
               Ada.Exceptions.Save_Occurrence (Last, E);
               exit when Attempt > 1
                 and then Ada.Real_Time.Clock - Started
                          > Ada.Real_Time.Milliseconds (1);
         end;
      end loop;
      if not Got then
         raise Ks_Flow_Exception with
           "no frame from the camera within" & Node.Timeout_Ms'Image
           & " ms (check the cable, the firewall and the trigger): "
           & Ada.Exceptions.Exception_Message (Last);
      end if;
      return Result;
   end Grab_Latest;

   procedure Send_Settings (Node : in out Camera_Node) is
      Refused : Unbounded_String;

      procedure Note (What : String; E : Ada.Exceptions.Exception_Occurrence)
      is
      begin
         Append (Refused, (if Length (Refused) > 0 then "; " else "")
                 & What & ": " & Ada.Exceptions.Exception_Message (E));
      end Note;
   begin
      begin
         Settings.Set_Auto_Exposure (Node.Device, Node.Auto_Exposure);
      exception
         when E : AMV.Ks_Exception | AMV.Ks_Bad_Parameter_Exception =>
            if Node.Auto_Exposure then
               Note ("auto exposure", E);
            end if;
      end;
      if not Node.Auto_Exposure and then Node.Exposure_Us > 0.0 then
         begin
            Settings.Set_Exposure_Time (Node.Device, Node.Exposure_Us);
         exception
            when E : AMV.Ks_Exception | AMV.Ks_Bad_Parameter_Exception =>
               Note ("exposure", E);
         end;
      end if;
      if Node.Gain >= 0.0 then
         begin
            Settings.Set_Gain (Node.Device, Node.Gain);
         exception
            when E : AMV.Ks_Exception | AMV.Ks_Bad_Parameter_Exception =>
               Note ("gain", E);
         end;
      end if;
      Node.Send_Settings := False;
      if Length (Refused) > 0 then
         Set_Result (Node, AMV.Tools.Warning,
                     "the camera refused: " & To_String (Refused));
      end if;
   end Send_Settings;

   overriding procedure Execute (Node : in out Camera_Node) is
      Value, Low, High : Long_Float;
   begin
      Node.Image_Out := No_Value;
      if not Node.Device.Is_Open or else Node.Opened_Id /= Node.Camera_Id then
         Node.Device.Close;
         Node.Opened_Id := Null_Unbounded_String;
         begin
            Node.Device.Open (To_String (Node.Camera_Id));
         exception
            when E : others =>
               raise Ks_Flow_Exception with
                 "cannot open the camera " & To_String (Node.Camera_Id) & ": "
                 & Ada.Exceptions.Exception_Message (E);
         end;
         Node.Opened_Id := Node.Camera_Id;
         Node.Send_Settings := True;
      end if;
      if Node.Send_Settings then
         Send_Settings (Node);
      end if;
      if not Node.Device.Is_Streaming then
         Node.Device.Start;
      end if;
      Node.Image_Out := From_Image (Grab_Latest (Node));
      begin
         Settings.Get_Exposure_Time (Node.Device, Value, Low, High);
         Node.Exposure_Now := From_Real (Value);
         Settings.Get_Gain (Node.Device, Value, Low, High);
         Node.Gain_Now := From_Real (Value);
      exception
         when AMV.Ks_Exception | AMV.Ks_Bad_Parameter_Exception =>
            null;  --  a camera without these features
      end;
   end Execute;

   overriding function Get_Output
     (Node : Camera_Node; Port : String) return Ks_Flow_Value is
   begin
      if Port = "Image" then
         return Node.Image_Out;
      elsif Port = "ExposureUs" then
         return Node.Exposure_Now;
      elsif Port = "Gain" then
         return Node.Gain_Now;
      end if;
      raise Ks_Flow_Exception with "Camera has no output """ & Port & """";
   end Get_Output;

   function Create_Camera return Node_Access is (new Camera_Node);

   procedure Register is
   begin
      if not AMV.Flow.Kinds.Exists ("Camera") then
         AMV.Flow.Kinds.Register ("Camera", Create_Camera'Access);
      end if;
   end Register;

end AMV.Flow.Nodes.Camera;
