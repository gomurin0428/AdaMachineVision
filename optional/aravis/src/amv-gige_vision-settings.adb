pragma SPARK_Mode (Off);

with Interfaces.C;
with System;

package body AMV.GigE_Vision.Settings is
   use type Interfaces.C.int;
   use type System.Address;

   subtype C_Double is Interfaces.C.double;
   subtype Error_Text is Interfaces.C.char_array (0 .. 511);

   function C_Set_Exposure_Time
     (Handle : System.Address; Value : C_Double;
      Error : out Error_Text; Error_Size : Interfaces.C.size_t)
      return Interfaces.C.int
     with Import, Convention => C,
       External_Name => "amv_aravis_set_exposure_time";

   function C_Get_Exposure_Time
     (Handle : System.Address; Value, Minimum, Maximum : out C_Double;
      Error : out Error_Text; Error_Size : Interfaces.C.size_t)
      return Interfaces.C.int
     with Import, Convention => C,
       External_Name => "amv_aravis_get_exposure_time";

   function C_Set_Exposure_Auto
     (Handle : System.Address; Enabled : Interfaces.C.int;
      Error : out Error_Text; Error_Size : Interfaces.C.size_t)
      return Interfaces.C.int
     with Import, Convention => C,
       External_Name => "amv_aravis_set_exposure_auto";

   function C_Set_Gain
     (Handle : System.Address; Value : C_Double;
      Error : out Error_Text; Error_Size : Interfaces.C.size_t)
      return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_aravis_set_gain";

   function C_Get_Gain
     (Handle : System.Address; Value, Minimum, Maximum : out C_Double;
      Error : out Error_Text; Error_Size : Interfaces.C.size_t)
      return Interfaces.C.int
     with Import, Convention => C, External_Name => "amv_aravis_get_gain";

   function Handle_Of (Camera : Ks_GigE_Camera) return System.Address is
   begin
      if Camera.Handle = System.Null_Address then
         raise AMV.Ks_Bad_Parameter_Exception with "Camera is not open";
      end if;
      return Camera.Handle;
   end Handle_Of;

   procedure Check_Finite (Value : Long_Float; Name : String) is
   begin
      if not Value'Valid then
         raise AMV.Ks_Bad_Parameter_Exception with Name & " is not finite";
      end if;
   end Check_Finite;

   procedure Check_Result (Code : Interfaces.C.int; Error : Error_Text) is
   begin
      if Code = 3 then
         raise AMV.Ks_Bad_Parameter_Exception with Interfaces.C.To_Ada (Error);
      elsif Code /= 0 then
         raise AMV.Ks_Exception with Interfaces.C.To_Ada (Error);
      end if;
   end Check_Result;

   procedure Set_Exposure_Time
     (Camera : in out Ks_GigE_Camera; Microseconds : Long_Float)
   is
      Error : Error_Text := [others => Interfaces.C.nul];
   begin
      Check_Finite (Microseconds, "Exposure time");
      Check_Result
        (C_Set_Exposure_Time
           (Handle_Of (Camera), C_Double (Microseconds), Error,
            Error'Length),
         Error);
   end Set_Exposure_Time;

   procedure Get_Exposure_Time
     (Camera                          : in out Ks_GigE_Camera;
      Microseconds, Minimum, Maximum : out Long_Float)
   is
      Error : Error_Text := [others => Interfaces.C.nul];
      Value, Low, High : C_Double := 0.0;
   begin
      Check_Result
        (C_Get_Exposure_Time
           (Handle_Of (Camera), Value, Low, High, Error, Error'Length),
         Error);
      Microseconds := Long_Float (Value);
      Minimum := Long_Float (Low);
      Maximum := Long_Float (High);
   end Get_Exposure_Time;

   procedure Set_Auto_Exposure
     (Camera : in out Ks_GigE_Camera; Enabled : Boolean)
   is
      Error : Error_Text := [others => Interfaces.C.nul];
   begin
      Check_Result
        (C_Set_Exposure_Auto
           (Handle_Of (Camera), Boolean'Pos (Enabled), Error, Error'Length),
         Error);
   end Set_Auto_Exposure;

   procedure Set_Gain (Camera : in out Ks_GigE_Camera; Gain : Long_Float) is
      Error : Error_Text := [others => Interfaces.C.nul];
   begin
      Check_Finite (Gain, "Gain");
      Check_Result
        (C_Set_Gain (Handle_Of (Camera), C_Double (Gain), Error,
                     Error'Length),
         Error);
   end Set_Gain;

   procedure Get_Gain
     (Camera                 : in out Ks_GigE_Camera;
      Gain, Minimum, Maximum : out Long_Float)
   is
      Error : Error_Text := [others => Interfaces.C.nul];
      Value, Low, High : C_Double := 0.0;
   begin
      Check_Result
        (C_Get_Gain (Handle_Of (Camera), Value, Low, High, Error,
                     Error'Length),
         Error);
      Gain := Long_Float (Value);
      Minimum := Long_Float (Low);
      Maximum := Long_Float (High);
   end Get_Gain;

end AMV.GigE_Vision.Settings;
