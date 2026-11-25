with Ada.Calendar;
with Ada.Calendar.Formatting;
with Ada.Calendar.Time_Zones;
with Ada.Characters.Conversions;
with Ada.Command_Line;
with Ada.Containers.Indefinite_Vectors;
with Ada.Directories;
with Ada.Exceptions;
with Ada.Long_Float_Text_IO;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Real_Time;
with Ada.Streams;
with Ada.Streams.Stream_IO;
with Ada.Strings.Fixed;
with Ada.Strings.UTF_Encoding.Wide_Strings;
with Ada.Text_IO;
with Interfaces;
with Interfaces.C;
with System;

with AMV;
with AMV.GigE_Vision;
with AMV.GigE_Vision.Settings;
with AMV.Image_File;
with AMV.Images;

with Circularity_Measure;
with Win32_Lite;

package body Live_App is
   use Win32_Lite;
   use type Interfaces.C.int;
   use type Interfaces.Integer_32;
   use type Interfaces.Unsigned_32;
   use type Interfaces.Unsigned_64;
   use type System.Address;

   package CM renames Circularity_Measure;
   package EF renames Ada.Numerics.Long_Elementary_Functions;
   package Settings renames AMV.GigE_Vision.Settings;

   CRLF : constant Wide_String :=
     Wide_Character'Val (13) & Wide_Character'Val (10);

   Class_Name     : constant Wide_String := "AMVLiveCircularity";
   Window_Title   : constant Wide_String :=
     "Live Circularity - AdaMachineVision";
   Default_Camera : constant Wide_String := "169.254.151.175";
   Capture_Folder : constant String := "captures";
   Log_File_Name  : constant String := "captures/circularity_log.csv";
   Log_Header     : constant String :=
     "time,image,found,circularity,roundness,diameter_px,area_px2,"
     & "perimeter_px,center_x,center_y,radius_min,radius_max,clipped,"
     & "exposure_us,gain,threshold,mm_per_px,diameter_mm,area_mm2,"
     & "perimeter_mm";
   Calibration_File : constant String := "calibration.txt";

   --  Outer rim diameter of a Haagen-Dazs mini cup (110 ml) as published
   --  by sellers (about 7.5 to 7.6 cm, not a maker's figure); the user
   --  can type the value measured on their own cup instead.
   Default_Reference_MM : constant Long_Float := 76.0;

   Id_Camera         : constant := 101;
   Id_Connect        : constant := 102;
   Id_Auto_Exposure  : constant := 103;
   Id_Auto_Threshold : constant := 106;
   Id_Light          : constant := 108;
   Id_Dark           : constant := 109;
   Id_Min_Area       : constant := 110;
   Id_Exposure_Edit  : constant := 111;
   Id_Exposure_Set   : constant := 112;
   Id_Capture        : constant := 113;
   Id_Reference_Edit : constant := 114;
   Id_Calibrate      : constant := 115;

   VK_RETURN : constant := 16#0D#;
   VK_F2     : constant := 16#71#;

   type HWND_List is array (Positive range <>) of HWND;

   package String_Vectors is new Ada.Containers.Indefinite_Vectors
     (Positive, String);

   Timer_Id       : constant WPARAM := 1;
   Panel_Width    : constant := 340;
   Margin         : constant := 14;
   Exposure_Steps : constant := 1_000;
   Gain_Steps     : constant := 200;
   Grab_Timeout   : constant := 2_000;  --  milliseconds

   Main               : HWND := Null_Handle;
   Camera_Caption     : HWND := Null_Handle;
   Camera_Edit        : HWND := Null_Handle;
   Connect_Button     : HWND := Null_Handle;
   Exposure_Label     : HWND := Null_Handle;
   Exposure_Bar       : HWND := Null_Handle;
   Exposure_Edit      : HWND := Null_Handle;
   Exposure_Unit      : HWND := Null_Handle;
   Exposure_Set       : HWND := Null_Handle;
   Auto_Exposure_Box  : HWND := Null_Handle;
   Gain_Label         : HWND := Null_Handle;
   Gain_Bar           : HWND := Null_Handle;
   Threshold_Label    : HWND := Null_Handle;
   Threshold_Bar      : HWND := Null_Handle;
   Auto_Threshold_Box : HWND := Null_Handle;
   Light_Radio        : HWND := Null_Handle;
   Dark_Radio         : HWND := Null_Handle;
   Min_Area_Caption   : HWND := Null_Handle;
   Min_Area_Edit      : HWND := Null_Handle;
   Results_Label      : HWND := Null_Handle;
   Capture_Button     : HWND := Null_Handle;
   Reference_Caption  : HWND := Null_Handle;
   Reference_Edit     : HWND := Null_Handle;
   Calibrate_Button   : HWND := Null_Handle;
   Status_Label       : HWND := Null_Handle;

   UI_Font     : HFONT := Null_Handle;
   Result_Font : HFONT := Null_Handle;
   Big_Font    : HFONT := Null_Handle;

   Camera       : AMV.GigE_Vision.Ks_GigE_Camera;
   Connected    : Boolean := False;
   Camera_Name  : Wide_String (1 .. 64);
   Camera_Len   : Natural := 0;
   --  The sliders' ranges (exposure on a log scale, so above zero) ...
   Exposure_Min : Long_Float := 10.0;
   Exposure_Max : Long_Float := 1.0E6;
   Gain_Min     : Long_Float := 1.0;
   Gain_Max     : Long_Float := 16.0;
   --  ... and the camera's, which every value sent is kept within.
   Exposure_Low  : Long_Float := 10.0;
   Exposure_High : Long_Float := 1.0E6;
   Gain_Low      : Long_Float := 1.0;
   Gain_High     : Long_Float := 16.0;
   --  The camera's values as last read back from it, for the log.
   Exposure_Now   : Long_Float := 0.0;   --  microseconds
   Gain_Now       : Long_Float := 0.0;
   Exposure_Known : Boolean := False;
   Gain_Known     : Boolean := False;
   MM_Per_Px    : Long_Float := 0.0;   --  0.0: not calibrated, show pixels
   Reference_MM : Long_Float := Default_Reference_MM;

   Config     : CM.Settings;
   Last_Image : AMV.Images.Ks_Image_8_Grey;
   Have_Image : Boolean := False;
   Outcome    : CM.Result;
   Boundary   : CM.Point_Vectors.Vector;

   Memory_DC     : HDC := Null_Handle;
   Bitmap        : HBITMAP := Null_Handle;
   First_Bitmap  : HGDIOBJ := Null_Handle;
   Bits          : System.Address := System.Null_Address;
   Bitmap_Width  : Natural := 0;
   Bitmap_Height : Natural := 0;

   Frames     : Natural := 0;
   FPS_Start  : Interfaces.Unsigned_64 := 0;
   FPS        : Long_Float := 0.0;
   Frame_Text : Natural := 0;
   Last_Frame : Interfaces.Unsigned_64 := 0;  --  tick of the last good frame
   Measure_Ms : Interfaces.Unsigned_64 := 0;
   Captures   : Natural := 0;
   Status_Hold_Until : Interfaces.Unsigned_64 := 0;
   --  Show_Running_Status leaves a capture's message up until this tick.

   ---------------------------------------------------------------------
   --  Text helpers
   ---------------------------------------------------------------------

   function Wide (Text : String) return Wide_String is
   begin
      return Ada.Strings.UTF_Encoding.Wide_Strings.Decode (Text);
   exception
      when others =>
         return Ada.Characters.Conversions.To_Wide_String (Text);
   end Wide;

   function Fixed (Value : Long_Float; Aft : Positive) return Wide_String is
      Buffer : String (1 .. 40);
   begin
      Ada.Long_Float_Text_IO.Put (Buffer, Value, Aft => Aft, Exp => 0);
      return Wide (Ada.Strings.Fixed.Trim (Buffer, Ada.Strings.Both));
   exception
      when others =>
         return "-";
   end Fixed;

   function Whole (Value : Long_Float) return Wide_String is
      Image : constant String :=
        Long_Long_Integer'Image (Long_Long_Integer (Value));
   begin
      return Wide (Ada.Strings.Fixed.Trim (Image, Ada.Strings.Both));
   end Whole;

   function Fixed_String (Value : Long_Float; Aft : Positive) return String
   is
      Buffer : String (1 .. 40);
   begin
      Ada.Long_Float_Text_IO.Put (Buffer, Value, Aft => Aft, Exp => 0);
      return Ada.Strings.Fixed.Trim (Buffer, Ada.Strings.Both);
   end Fixed_String;

   function Local_Time_Stamp return String is
     (Ada.Calendar.Formatting.Image
        (Ada.Calendar.Clock,
         Time_Zone => Ada.Calendar.Time_Zones.UTC_Time_Offset));
   --  "YYYY-MM-DD HH:MM:SS"

   procedure Set_Status (Text : Wide_String) is
   begin
      Set_Text (Status_Label, Text);
   end Set_Status;

   ---------------------------------------------------------------------
   --  Exposure, gain and threshold controls
   ---------------------------------------------------------------------

   function Exposure_At (Position : Integer) return Long_Float is
     (Exposure_Min * EF."**" (Exposure_Max / Exposure_Min,
                              Long_Float (Position)
                              / Long_Float (Exposure_Steps)));

   function Exposure_Position (Microseconds : Long_Float) return Integer is
      Ratio : constant Long_Float :=
        EF.Log (Long_Float'Max (Microseconds, Exposure_Min) / Exposure_Min)
        / EF.Log (Exposure_Max / Exposure_Min);
   begin
      return Integer'Max
        (0, Integer'Min (Exposure_Steps,
                         Integer (Ratio * Long_Float (Exposure_Steps))));
   end Exposure_Position;

   function Gain_At (Position : Integer) return Long_Float is
     (Gain_Min + (Gain_Max - Gain_Min) * Long_Float (Position)
                 / Long_Float (Gain_Steps));

   function Gain_Position (Gain : Long_Float) return Integer is
     (Integer'Max
        (0, Integer'Min
              (Gain_Steps,
               Integer ((Gain - Gain_Min) / (Gain_Max - Gain_Min)
                        * Long_Float (Gain_Steps)))));

   function Clamp (Value, Low, High : Long_Float) return Long_Float is
     (Long_Float'Min (High, Long_Float'Max (Low, Value)));

   procedure Show_Exposure (Microseconds : Long_Float) is
   begin
      Set_Text (Exposure_Label,
                "Exposure: " & Fixed (Microseconds / 1_000.0, 2) & " ms");
      Set_Text (Exposure_Edit, Fixed (Microseconds / 1_000.0, 2));
   end Show_Exposure;

   procedure Show_Gain (Gain : Long_Float) is
   begin
      Set_Text (Gain_Label, "Gain: " & Fixed (Gain, 2));
   end Show_Gain;

   --  A value read back from the camera: shown and kept for the log.

   procedure Note_Exposure (Microseconds : Long_Float) is
   begin
      Exposure_Now := Microseconds;
      Exposure_Known := True;
      Show_Exposure (Microseconds);
   end Note_Exposure;

   procedure Note_Gain (Gain : Long_Float) is
   begin
      Gain_Now := Gain;
      Gain_Known := True;
      Show_Gain (Gain);
   end Note_Gain;

   procedure Show_Threshold is
   begin
      if Config.Auto_Threshold then
         Set_Text (Threshold_Label, "Threshold: auto (Otsu)");
      else
         Set_Text (Threshold_Label,
                   "Threshold:" & Natural'Wide_Image (Config.Threshold));
      end if;
   end Show_Threshold;

   procedure Read_Exposure is
      Value, Low, High : Long_Float;
   begin
      Settings.Get_Exposure_Time (Camera, Value, Low, High);
      Exposure_Low := Low;
      Exposure_High := Long_Float'Max (High, Low);
      Exposure_Min := Long_Float'Max (Low, 1.0);
      Exposure_Max := Long_Float'Max (High, Exposure_Min * 2.0);
      Set_Trackbar (Exposure_Bar, 0, Exposure_Steps,
                    Exposure_Position (Value));
      Note_Exposure (Value);
   end Read_Exposure;

   procedure Read_Gain is
      Value, Low, High : Long_Float;
   begin
      Settings.Get_Gain (Camera, Value, Low, High);
      Gain_Low := Low;
      Gain_High := Long_Float'Max (High, Low);
      Gain_Min := Low;
      Gain_Max := Long_Float'Max (High, Low + 1.0);
      Set_Trackbar (Gain_Bar, 0, Gain_Steps, Gain_Position (Value));
      Note_Gain (Value);
   end Read_Gain;

   procedure Read_Camera_Settings is
   begin
      begin
         Read_Exposure;
      exception
         when AMV.Ks_Exception =>
            null;  --  the camera has no exposure time it lets us read
      end;
      begin
         Read_Gain;
      exception
         when AMV.Ks_Exception =>
            null;
      end;
   end Read_Camera_Settings;

   procedure Enable_Exposure_Controls is
      Manual : constant Boolean := not Is_Checked (Auto_Exposure_Box);
   begin
      Enable (Exposure_Bar, Manual);
      Enable (Exposure_Edit, Manual);
      Enable (Exposure_Set, Manual);
   end Enable_Exposure_Controls;

   ---------------------------------------------------------------------
   --  Drawing
   ---------------------------------------------------------------------

   procedure Ensure_Bitmap (Width, Height : Positive) is
      Header : aliased constant BITMAPINFOHEADER :=
        (Size        => BITMAPINFOHEADER'Size / 8,
         Width       => Interfaces.Integer_32 (Width),
         Height      => -Interfaces.Integer_32 (Height),  --  top-down
         Planes      => 1,
         Bit_Count   => 32,
         Compression => BI_RGB,
         others      => <>);
      Screen     : HDC;
      New_Bitmap : HBITMAP;
      New_Bits   : aliased System.Address := System.Null_Address;
      Ignore_I   : int;
      Ignore_B   : BOOL;
      Ignore_O   : HGDIOBJ;
   begin
      if Bitmap /= Null_Handle
        and then Width = Bitmap_Width and then Height = Bitmap_Height
      then
         return;
      end if;
      Screen := Get_DC (Main);
      if Memory_DC = Null_Handle then
         Memory_DC := Create_Compatible_DC (Screen);
      end if;
      New_Bitmap := Create_DIB_Section
        (Screen, Header'Access, DIB_RGB_COLORS, New_Bits'Access,
         Null_Handle, 0);
      Ignore_I := Release_DC (Main, Screen);
      if New_Bitmap = Null_Handle then
         raise Storage_Error with "CreateDIBSection failed";
      end if;
      if Bitmap = Null_Handle then
         First_Bitmap := Select_Object (Memory_DC, New_Bitmap);
      else
         Ignore_O := Select_Object (Memory_DC, New_Bitmap);
         Ignore_B := Delete_Object (Bitmap);
      end if;
      Bitmap := New_Bitmap;
      Bits := New_Bits;
      Bitmap_Width := Width;
      Bitmap_Height := Height;
   end Ensure_Bitmap;

   procedure Render (Image : AMV.Images.Ks_Image_8_Grey) is
      Width  : constant Positive := AMV.Images.Width (Image);
      Height : constant Positive := AMV.Images.Height (Image);
   begin
      Ensure_Bitmap (Width, Height);
      declare
         type Pixel_Buffer is
           array (0 .. Width * Height - 1) of Interfaces.Unsigned_32
           with Convention => C;
         Target : Pixel_Buffer with Import, Address => Bits;
         Row    : AMV.Images.Grey_8_Row (0 .. Width - 1);
         Grey   : Interfaces.Unsigned_32;
      begin
         for Y in 0 .. Height - 1 loop
            Image.Get_Row (Y, Row);
            for X in Row'Range loop
               Grey := Interfaces.Unsigned_32 (Row (X));
               Target (Y * Width + X) :=
                 Grey or Interfaces.Shift_Left (Grey, 8)
                      or Interfaces.Shift_Left (Grey, 16);
            end loop;
         end loop;
      end;

      if not Outcome.Found then
         return;
      end if;

      declare
         function To_Int (Value : Long_Float) return int is
           (int (Long_Float'Floor (Value + 0.5)));
         --  Pixel centres are whole numbers; GDI pixel X spans X .. X + 1.
         function Screen_X (Value : Long_Float) return int is
           (To_Int (Value + 0.5));

         Count    : constant Natural := Natural (Boundary.Length);
         Points   : POINT_Array (0 .. Count);
         --  One-pixel (cosmetic) pens: GDI draws a wide pen's joins at every
         --  vertex, which takes most of a second for a long boundary. The
         --  outlines are drawn several times, shifted, to be thicker.
         Line_Pen : constant HPEN := Create_Pen (PS_SOLID, 1, RGB (0, 230, 0));
         Mark_Pen : constant HPEN := Create_Pen (PS_SOLID, 1, RGB (255, 40, 40));
         Old_Pen   : HGDIOBJ;
         Old_Brush : HGDIOBJ;
         CX        : constant int := Screen_X (Outcome.Center_X);
         CY        : constant int := Screen_X (Outcome.Center_Y);
         Ignore_B  : BOOL;
         Ignore_O  : HGDIOBJ;
      begin
         for I in 1 .. Count loop
            Points (I - 1) := (Screen_X (Boundary (I).X),
                               Screen_X (Boundary (I).Y));
         end loop;
         Points (Count) := Points (0);

         Old_Pen := Select_Object (Memory_DC, Line_Pen);
         Old_Brush := Select_Object (Memory_DC, Get_Stock_Object (NULL_BRUSH));
         for Shift in 0 .. 2 loop
            Ignore_B := Polyline (Memory_DC, Points'Address, int (Count + 1));
            for P of Points loop
               P := (if Shift = 0 then (P.X + 1, P.Y) else (P.X - 1, P.Y + 1));
            end loop;
         end loop;

         Ignore_O := Select_Object (Memory_DC, Mark_Pen);
         for D in int range -1 .. 1 loop
            Ignore_B := Move_To (Memory_DC, CX - 15, CY + D,
                                 System.Null_Address);
            Ignore_B := Line_To (Memory_DC, CX + 16, CY + D);
            Ignore_B := Move_To (Memory_DC, CX + D, CY - 15,
                                 System.Null_Address);
            Ignore_B := Line_To (Memory_DC, CX + D, CY + 16);
         end loop;

         Ignore_O := Select_Object (Memory_DC, Old_Pen);
         Ignore_O := Select_Object (Memory_DC, Old_Brush);
         Ignore_B := Delete_Object (Line_Pen);
         Ignore_B := Delete_Object (Mark_Pen);
      end;
   end Render;

   procedure Image_Area
     (Client : RECT; X, Y, Width, Height : out Integer)
   is
      Area_Width  : constant Integer :=
        Integer'Max (1, Integer (Client.Right) - Panel_Width);
      Area_Height : constant Integer :=
        Integer'Max (1, Integer (Client.Bottom));
      Source_W    : constant Integer :=
        (if Bitmap_Width > 0 then Bitmap_Width else 1280);
      Source_H    : constant Integer :=
        (if Bitmap_Height > 0 then Bitmap_Height else 1024);
   begin
      if Area_Width * Source_H <= Area_Height * Source_W then
         Width := Area_Width;
         Height := Area_Width * Source_H / Source_W;
      else
         Height := Area_Height;
         Width := Area_Height * Source_W / Source_H;
      end if;
      X := (Area_Width - Width) / 2;
      Y := (Area_Height - Height) / 2;
   end Image_Area;

   procedure Paint (Window : HWND) is
      Paint_Info : aliased PAINTSTRUCT;
      DC         : constant HDC := Begin_Paint (Window, Paint_Info'Access);
      Client     : aliased RECT;
      X, Y, W, H : Integer;
      Dark       : constant HBRUSH := Get_Stock_Object (DKGRAY_BRUSH);
      Face       : constant HBRUSH := Get_Sys_Color_Brush (COLOR_BTNFACE);
      Left_Width : Integer;
      Ignore_B   : BOOL;
      Ignore_I   : int;

      procedure Fill (L, T, R, B : Integer; Brush : HBRUSH) is
         Area : aliased constant RECT := (int (L), int (T), int (R), int (B));
      begin
         if R > L and then B > T then
            Ignore_I := Fill_Rect (DC, Area'Access, Brush);
         end if;
      end Fill;
   begin
      Ignore_B := Get_Client_Rect (Window, Client'Access);
      Image_Area (Client, X, Y, W, H);
      Left_Width := Integer (Client.Right) - Panel_Width;
      Fill (0, 0, Left_Width, Y, Dark);
      Fill (0, Y + H, Left_Width, Integer (Client.Bottom), Dark);
      Fill (0, Y, X, Y + H, Dark);
      Fill (X + W, Y, Left_Width, Y + H, Dark);
      Fill (Left_Width, 0, Integer (Client.Right), Integer (Client.Bottom),
            Face);
      if Bitmap /= Null_Handle then
         Ignore_I := Set_Stretch_Blt_Mode (DC, HALFTONE);
         Ignore_B := Set_Brush_Org_Ex (DC, 0, 0, System.Null_Address);
         Ignore_B := Stretch_Blt
           (DC, int (X), int (Y), int (W), int (H), Memory_DC, 0, 0,
            int (Bitmap_Width), int (Bitmap_Height), SRCCOPY);
      else
         Fill (X, Y, X + W, Y + H, Dark);
      end if;
      Ignore_B := End_Paint (Window, Paint_Info'Access);
   end Paint;

   ---------------------------------------------------------------------
   --  Results
   ---------------------------------------------------------------------

   function Length_Text (Pixels : Long_Float) return Wide_String is
     (if MM_Per_Px > 0.0 then Fixed (Pixels * MM_Per_Px, 2) & " mm"
      else Fixed (Pixels, 1) & " px");

   function Area_Text (Pixels : Long_Float) return Wide_String is
     (if MM_Per_Px > 0.0 then Whole (Pixels * MM_Per_Px * MM_Per_Px) & " mm²"
      else Whole (Pixels) & " px²");

   procedure Show_Results is
   begin
      if not Have_Image then
         Set_Text (Results_Label, "Connect to a camera");
      elsif not Outcome.Found then
         Set_Text (Results_Label,
                   "No object found" & CRLF & CRLF
                   & "Adjust the threshold," & CRLF
                   & "polarity or minimum area");
      else
         Set_Text
           (Results_Label,
            "Roundness    " & Fixed (Outcome.Roundness, 3) & CRLF
            & "Diameter     " & Length_Text (2.0 * Outcome.Radius) & CRLF
            & "Area         " & Area_Text (Outcome.Area) & CRLF
            & "Perimeter    " & Length_Text (Outcome.Perimeter) & CRLF
            & "Center px    " & Fixed (Outcome.Center_X, 1) & ", "
            & Fixed (Outcome.Center_Y, 1) & CRLF
            & (if MM_Per_Px > 0.0
               then "Scale        " & Fixed (MM_Per_Px, 4) & " mm/px"
               else "Not calibrated (pixels)")
            & (if Outcome.Clipped then CRLF & "* Touches image border"
               else ""));
      end if;
   end Show_Results;

   procedure Show_Running_Status is
   begin
      if Get_Tick_Count_64 < Status_Hold_Until then
         return;
      end if;
      Set_Status
        ("Connected: " & Camera_Name (1 .. Camera_Len) & "   "
         & Fixed (FPS, 1) & " fps (measure"
         & Interfaces.Unsigned_64'Wide_Image (Measure_Ms) & " ms)" & CRLF
         & "Roundness = smallest / largest radius");
   end Show_Running_Status;

   ---------------------------------------------------------------------
   --  Camera
   ---------------------------------------------------------------------

   procedure Disconnect is
   begin
      Stop_Timer (Main, Timer_Id);
      Camera.Close;
      Connected := False;
      Set_Text (Connect_Button, "Connect");
      Enable (Camera_Edit, True);
      Set_Status ("Disconnected");
   end Disconnect;

   procedure Connect is
      Name : constant Wide_String := Get_Text (Camera_Edit);
   begin
      Camera_Len := Natural'Min (Name'Length, Camera_Name'Length);
      Camera_Name (1 .. Camera_Len) :=
        Name (Name'First .. Name'First + Camera_Len - 1);
      Set_Status ("Connecting...");
      Camera.Open (Ada.Characters.Conversions.To_String (Name));
      Exposure_Known := False;
      Gain_Known := False;
      begin
         Settings.Set_Auto_Exposure
           (Camera, Is_Checked (Auto_Exposure_Box));
      exception
         when AMV.Ks_Exception =>
            Set_Checked (Auto_Exposure_Box, False);
      end;
      Enable_Exposure_Controls;
      Read_Camera_Settings;
      Camera.Start;
      Connected := True;
      Set_Text (Connect_Button, "Disconnect");
      Enable (Camera_Edit, False);
      Frames := 0;
      FPS := 0.0;
      FPS_Start := Get_Tick_Count_64;
      Last_Frame := FPS_Start;
      Start_Timer (Main, Timer_Id, 10);
      Set_Status ("Connected: " & Name);
   exception
      when E : others =>
         Camera.Close;
         Connected := False;
         Set_Status ("Cannot connect: "
                     & Wide (Ada.Exceptions.Exception_Message (E)));
   end Connect;

   function Grab_Latest (Wait : Positive) return Boolean;
   --  Takes the newest complete frame into Last_Image: one Grab that waits
   --  up to Wait ms, then quick Grabs that empty the stream's queue. While
   --  a frame is being measured the camera fills every stream buffer, and
   --  frames that arrive with no free buffer come out incomplete (reported
   --  as timeouts at once); emptying the queue returns the buffers, so the
   --  next frames are whole. At most eight Grabs, twice the adapter's four
   --  stream buffers: a camera that sends frames faster than they can be
   --  taken off the queue may leave a newer one in it. False when no
   --  complete frame came.

   function Grab_Latest (Wait : Positive) return Boolean is
      use type Ada.Real_Time.Time;
      use type Ada.Real_Time.Time_Span;
      Got     : Boolean := False;
      Started : Ada.Real_Time.Time;
   begin
      for Attempt in 1 .. 8 loop
         Started := Ada.Real_Time.Clock;
         begin
            Last_Image := Camera.Grab (if Attempt = 1 then Wait else 1);
            Got := True;
         exception
            when AMV.GigE_Vision.Ks_GigE_Vision_Timeout_Exception
               | AMV.Ks_Exception =>
               --  An incomplete buffer comes back at once; a Grab that
               --  had to wait found the queue empty.
               exit when Attempt > 1
                 and then Ada.Real_Time.Clock - Started
                          > Ada.Real_Time.Milliseconds (1);
         end;
      end loop;
      return Got;
   end Grab_Latest;

   procedure Tick is
      Now   : Interfaces.Unsigned_64;
      Start : Interfaces.Unsigned_64;
   begin
      if not Grab_Latest (200) then
         if Get_Tick_Count_64 - Last_Frame > Grab_Timeout then
            Set_Status ("No frames are arriving (timeout)." & CRLF
                        & "Check the cable and the firewall.");
         end if;
         return;
      end if;
      Have_Image := True;
      Start := Get_Tick_Count_64;
      Last_Frame := Start;
      CM.Measure (Last_Image, Config, Outcome, Boundary);
      Measure_Ms := Get_Tick_Count_64 - Start;
      Render (Last_Image);
      Invalidate (Main);
      Show_Results;

      Frames := Frames + 1;
      Now := Get_Tick_Count_64;
      if Now - FPS_Start >= 1_000 then
         FPS := Long_Float (Frames) * 1_000.0 / Long_Float (Now - FPS_Start);
         Frames := 0;
         FPS_Start := Now;
         Show_Running_Status;
      end if;

      Frame_Text := Frame_Text + 1;
      if Frame_Text >= 10 and then Is_Checked (Auto_Exposure_Box) then
         Frame_Text := 0;
         declare
            Value, Low, High : Long_Float;
         begin
            Settings.Get_Exposure_Time (Camera, Value, Low, High);
            Note_Exposure (Value);
            Set_Trackbar_Position (Exposure_Bar, Exposure_Position (Value));
            Settings.Get_Gain (Camera, Value, Low, High);
            Note_Gain (Value);
         end;
      end if;
   end Tick;

   ---------------------------------------------------------------------
   --  Saving
   ---------------------------------------------------------------------

   function Capture_Stamp return String is
      Image : constant String :=
        Ada.Calendar.Formatting.Image
          (Ada.Calendar.Clock,
           Include_Time_Fraction => True,
           Time_Zone => Ada.Calendar.Time_Zones.UTC_Time_Offset);
      --  "YYYY-MM-DD HH:MM:SS.ss"
   begin
      return Image (1 .. 4) & Image (6 .. 7) & Image (9 .. 10) & "_"
        & Image (12 .. 13) & Image (15 .. 16) & Image (18 .. 19) & "_"
        & Image (21 .. 22);
   end Capture_Stamp;

   procedure Write_Shown_Image (Name : String);
   --  Writes the picture on screen (the frame with the measurement drawn
   --  on it) as a 24-bit BMP.

   procedure Write_Shown_Image (Name : String) is
      use Ada.Streams;
      use Ada.Streams.Stream_IO;
      Width     : constant Natural := Bitmap_Width;
      Height    : constant Natural := Bitmap_Height;
      Row_Bytes : constant Natural := ((Width * 3 + 3) / 4) * 4;
      Data_Size : constant Natural := Row_Bytes * Height;
      type Pixel_Buffer is
        array (0 .. Width * Height - 1) of Interfaces.Unsigned_32
        with Convention => C;
      Source : Pixel_Buffer with Import, Address => Bits;
      Header : Stream_Element_Array (1 .. 54) := [others => 0];
      Row    : Stream_Element_Array (1 .. Stream_Element_Offset (Row_Bytes))
        := [others => 0];
      Pixel  : Interfaces.Unsigned_32;
      File   : File_Type;

      procedure Put (At_Index : Stream_Element_Offset; Value : Natural;
                     Bytes : Positive := 4) is
         Rest : Natural := Value;
      begin
         for I in 0 .. Stream_Element_Offset (Bytes) - 1 loop
            Header (At_Index + I) := Stream_Element (Rest mod 256);
            Rest := Rest / 256;
         end loop;
      end Put;

      function Byte (Value : Interfaces.Unsigned_32; Shift : Natural)
        return Stream_Element is
        (Stream_Element (Interfaces.Shift_Right (Value, Shift) and 16#FF#));
   begin
      Header (1) := Character'Pos ('B');
      Header (2) := Character'Pos ('M');
      Put (3, 54 + Data_Size);
      Put (11, 54);
      Put (15, 40);
      Put (19, Width);
      Put (23, Height);          --  bottom-up rows
      Put (27, 1, 2);
      Put (29, 24, 2);
      Put (35, Data_Size);
      Put (39, 2_835);
      Put (43, 2_835);
      Create (File, Out_File, Name);
      Write (File, Header);
      for Y in reverse 0 .. Height - 1 loop
         for X in 0 .. Width - 1 loop
            Pixel := Source (Y * Width + X);
            Row (Stream_Element_Offset (3 * X + 1)) := Byte (Pixel, 0);
            Row (Stream_Element_Offset (3 * X + 2)) := Byte (Pixel, 8);
            Row (Stream_Element_Offset (3 * X + 3)) := Byte (Pixel, 16);
         end loop;
         Write (File, Row);
      end loop;
      Close (File);
   end Write_Shown_Image;

   procedure Upgrade_Log_Header;
   --  Rewrites the log's first line as Log_Header when it is an older
   --  header (rows written before keep their fewer columns), or writes it
   --  into an empty log. Reads only the first line of a current log.

   procedure Upgrade_Log_Header is
      File    : Ada.Text_IO.File_Type;
      Lines   : String_Vectors.Vector;
      Current : Boolean;
   begin
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Log_File_Name);
      Current := not Ada.Text_IO.End_Of_File (File)
        and then Ada.Text_IO.Get_Line (File) = Log_Header;
      if not Current then
         while not Ada.Text_IO.End_Of_File (File) loop
            Lines.Append (Ada.Text_IO.Get_Line (File));
         end loop;
      end if;
      Ada.Text_IO.Close (File);
      if Current then
         return;
      end if;
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Log_File_Name);
      Ada.Text_IO.Put_Line (File, Log_Header);
      for Line of Lines loop
         Ada.Text_IO.Put_Line (File, Line);
      end loop;
      Ada.Text_IO.Close (File);
   end Upgrade_Log_Header;

   procedure Append_Log (Image_Name : String) is
      File  : Ada.Text_IO.File_Type;
      Found : constant Boolean := Outcome.Found;
      Scale : constant Boolean := Found and then MM_Per_Px > 0.0;
      function Value (X : Long_Float; Aft : Positive) return String is
        (if Found then Fixed_String (X, Aft) else "");
      function MM (X : Long_Float; Aft : Positive) return String is
        (if Scale then Fixed_String (X, Aft) else "");
   begin
      if Ada.Directories.Exists (Log_File_Name) then
         Upgrade_Log_Header;
         Ada.Text_IO.Open (File, Ada.Text_IO.Append_File, Log_File_Name);
      else
         Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Log_File_Name);
         Ada.Text_IO.Put_Line (File, Log_Header);
      end if;
      Ada.Text_IO.Put_Line
        (File,
         Local_Time_Stamp & "," & Image_Name & ","
         & (if Found then "1" else "0") & ","
         & Value (Outcome.Circularity, 4) & ","
         & Value (Outcome.Roundness, 4) & ","
         & Value (2.0 * Outcome.Radius, 2) & ","
         & Value (Outcome.Area, 1) & ","
         & Value (Outcome.Perimeter, 2) & ","
         & Value (Outcome.Center_X, 2) & ","
         & Value (Outcome.Center_Y, 2) & ","
         & Value (Outcome.Radius_Min, 2) & ","
         & Value (Outcome.Radius_Max, 2) & ","
         & (if Found and then Outcome.Clipped then "1" else "0") & ","
         & (if Exposure_Known then Fixed_String (Exposure_Now, 1) else "")
         & ","
         & (if Gain_Known then Fixed_String (Gain_Now, 2) else "") & ","
         & (if Config.Auto_Threshold then "auto"
            else Ada.Strings.Fixed.Trim
                   (Natural'Image (Config.Threshold), Ada.Strings.Both))
         & ","
         & (if MM_Per_Px > 0.0 then Fixed_String (MM_Per_Px, 6) else "")
         & "," & MM (2.0 * Outcome.Radius * MM_Per_Px, 3)
         & "," & MM (Outcome.Area * MM_Per_Px * MM_Per_Px, 1)
         & "," & MM (Outcome.Perimeter * MM_Per_Px, 3));
      Ada.Text_IO.Close (File);
   end Append_Log;

   function Take_Frame return Boolean is
   begin
      if not Grab_Latest (Grab_Timeout) then
         return False;
      end if;
      Have_Image := True;
      Last_Frame := Get_Tick_Count_64;
      CM.Measure (Last_Image, Config, Outcome, Boundary);
      Render (Last_Image);
      Invalidate (Main);
      Show_Results;
      return True;
   end Take_Frame;
   --  Takes and measures the newest frame from the camera now, as Tick
   --  does; False when none came.

   function Capture_Text return Wide_String is
     ("Capture [F2]"
      & (if Captures = 0 then ""
         else "  (" & Wide (Ada.Strings.Fixed.Trim
                               (Natural'Image (Captures), Ada.Strings.Both))
              & " saved)"));

   procedure Capture is
   begin
      if not Connected then
         Set_Status ("Connect to a camera before capturing");
         return;
      end if;
      if not Take_Frame then
         Set_Status ("Capture failed: no frame arrived");
         return;
      end if;

      Ada.Directories.Create_Path (Capture_Folder);
      declare
         Base : constant String := "cup_" & Capture_Stamp;
         Path : constant String := Capture_Folder & "/" & Base;
      begin
         AMV.Image_File.Write_Image (Path & ".bmp", Last_Image);
         Write_Shown_Image (Path & "_result.bmp");
         Append_Log (Base & ".bmp");
         Captures := Captures + 1;
         Set_Text (Capture_Button, Capture_Text);
         Status_Hold_Until := Get_Tick_Count_64 + 6_000;
         Set_Status
           ("Captured: " & Wide (Base) & ".bmp" & CRLF
            & (if Outcome.Found
               then "Roundness " & Fixed (Outcome.Roundness, 3)
                    & "   Diameter " & Length_Text (2.0 * Outcome.Radius)
               else "No object found")
            & CRLF & "Saved in: ...\"
            & Wide (Ada.Directories.Simple_Name
                      (Ada.Directories.Containing_Directory
                         (Ada.Directories.Full_Name (Capture_Folder))))
            & "\" & Wide (Capture_Folder));
      end;
   end Capture;

   procedure Save_Calibration is
      File : Ada.Text_IO.File_Type;
   begin
      Ada.Text_IO.Create (File, Ada.Text_IO.Out_File, Calibration_File);
      Ada.Text_IO.Put_Line
        (File, "reference_mm=" & Fixed_String (Reference_MM, 3));
      Ada.Text_IO.Put_Line (File, "mm_per_px=" & Fixed_String (MM_Per_Px, 8));
      Ada.Text_IO.Close (File);
   end Save_Calibration;

   procedure Load_Calibration is
      File : Ada.Text_IO.File_Type;
   begin
      if not Ada.Directories.Exists (Calibration_File) then
         return;
      end if;
      Ada.Text_IO.Open (File, Ada.Text_IO.In_File, Calibration_File);
      while not Ada.Text_IO.End_Of_File (File) loop
         declare
            Line  : constant String := Ada.Text_IO.Get_Line (File);
            Equal : constant Natural := Ada.Strings.Fixed.Index (Line, "=");
         begin
            if Equal > 0 then
               declare
                  Key   : constant String := Line (Line'First .. Equal - 1);
                  Value : constant Long_Float :=
                    Long_Float'Value (Line (Equal + 1 .. Line'Last));
               begin
                  if Key = "reference_mm" and then Value > 0.0 then
                     Reference_MM := Value;
                  elsif Key = "mm_per_px" and then Value > 0.0 then
                     MM_Per_Px := Value;
                  end if;
               end;
            end if;
         exception
            when Constraint_Error =>
               null;  --  a line that is not key=number
         end;
      end loop;
      Ada.Text_IO.Close (File);
   end Load_Calibration;

   procedure Calibrate is
      Text  : constant Wide_String := Get_Text (Reference_Edit);
      Value : Long_Float;
   begin
      begin
         Value := Long_Float'Value
           (Ada.Characters.Conversions.To_String (Text));
      exception
         when Constraint_Error =>
            Value := 0.0;
      end;
      --  Always from a frame taken now: the one on screen may be from
      --  before a disconnection or before the reference cup was put in.
      if Value <= 0.0 then
         Set_Status ("Enter the reference diameter in millimetres");
         return;
      elsif not Connected then
         Set_Status ("Connect to a camera before calibrating");
         return;
      elsif not Take_Frame then
         Set_Status ("Calibration failed: no frame arrived");
         return;
      elsif not Outcome.Found then
         Set_Status ("Put the reference cup in view first");
         return;
      elsif Outcome.Clipped then
         Set_Status ("The cup touches the image border:" & CRLF
                     & "move it fully into view first");
         return;
      end if;
      Reference_MM := Value;
      MM_Per_Px := Value / (2.0 * Outcome.Radius);
      Save_Calibration;
      Show_Results;
      Status_Hold_Until := Get_Tick_Count_64 + 6_000;
      Set_Status ("Calibrated: " & Fixed (2.0 * Outcome.Radius, 1) & " px = "
                  & Fixed (Value, 2) & " mm" & CRLF
                  & Fixed (MM_Per_Px, 5) & " mm/px, saved in "
                  & Wide (Calibration_File));
   end Calibrate;

   procedure Apply_Exposure is
      Text  : constant Wide_String := Get_Text (Exposure_Edit);
      Value : Long_Float;
      Low, High : Long_Float;
   begin
      begin
         Value := Long_Float'Value
           (Ada.Characters.Conversions.To_String (Text)) * 1_000.0;
      exception
         when Constraint_Error =>
            Set_Status ("Enter the exposure in milliseconds (e.g. 12.5)");
            return;
      end;
      if not Connected then
         Set_Status ("Connect to a camera first");
         return;
      end if;
      Settings.Set_Exposure_Time
        (Camera, Clamp (Value, Exposure_Low, Exposure_High));
      Settings.Get_Exposure_Time (Camera, Value, Low, High);
      Note_Exposure (Value);
      Set_Trackbar_Position (Exposure_Bar, Exposure_Position (Value));
      Status_Hold_Until := Get_Tick_Count_64 + 3_000;
      Set_Status ("Exposure set to " & Fixed (Value / 1_000.0, 3)
                  & " ms");
   end Apply_Exposure;

   function Key_Pressed (Window : HWND; Key : WPARAM) return Boolean is
   begin
      if Key = VK_RETURN and then Window = Exposure_Edit then
         Apply_Exposure;
         return True;
      elsif Key = VK_F2 then
         Capture;
         return True;
      end if;
      return False;
   exception
      when E : others =>
         Set_Status ("Error: " & Wide (Ada.Exceptions.Exception_Message (E)));
         return True;
   end Key_Pressed;

   ---------------------------------------------------------------------
   --  Window
   ---------------------------------------------------------------------

   procedure Create_Controls (Window : HWND) is
      function Static (Text : Wide_String) return HWND is
        (Create_Control (Window, "STATIC", Text, 0));
      function Bar return HWND is
        (Create_Control (Window, "msctls_trackbar32", "",
                         WS_TABSTOP or TBS_NOTICKS));
      function Box (Text : Wide_String; Id : Natural) return HWND is
        (Create_Control (Window, "BUTTON", Text,
                         WS_TABSTOP or BS_AUTOCHECKBOX, Id));
      function Button (Text : Wide_String; Id : Natural) return HWND is
        (Create_Control (Window, "BUTTON", Text,
                         WS_TABSTOP or BS_PUSHBUTTON, Id));
   begin
      UI_Font := Create_UI_Font ("Segoe UI", 16);
      Result_Font := Create_UI_Font ("Consolas", 20, 700);
      Big_Font := Create_UI_Font ("Segoe UI", 20, 700);

      Camera_Caption := Static ("Camera (IP address)");
      Camera_Edit := Create_Control
        (Window, "EDIT", Default_Camera, WS_TABSTOP or ES_AUTOHSCROLL,
         Id_Camera, WS_EX_CLIENTEDGE);
      Connect_Button := Button ("Connect", Id_Connect);
      Exposure_Label := Static ("Exposure: -");
      Exposure_Bar := Bar;
      Exposure_Edit := Create_Control
        (Window, "EDIT", "", WS_TABSTOP or ES_AUTOHSCROLL, Id_Exposure_Edit,
         WS_EX_CLIENTEDGE);
      Exposure_Unit := Static ("ms");
      Exposure_Set := Button ("Set", Id_Exposure_Set);
      Auto_Exposure_Box := Box ("Auto exposure", Id_Auto_Exposure);
      Gain_Label := Static ("Gain: -");
      Gain_Bar := Bar;
      Threshold_Label := Static ("");
      Threshold_Bar := Bar;
      Auto_Threshold_Box := Box ("Automatic threshold", Id_Auto_Threshold);
      Light_Radio := Create_Control
        (Window, "BUTTON", "Object lighter than background",
         WS_TABSTOP or WS_GROUP or BS_AUTORADIOBUTTON, Id_Light);
      Dark_Radio := Create_Control
        (Window, "BUTTON", "Object darker than background", BS_AUTORADIOBUTTON, Id_Dark);
      Min_Area_Caption := Static ("Min. area (px)");
      Min_Area_Edit := Create_Control
        (Window, "EDIT", "2000", WS_TABSTOP or ES_AUTOHSCROLL or ES_NUMBER,
         Id_Min_Area, WS_EX_CLIENTEDGE);
      Reference_Caption := Static ("Ref. dia (mm)");
      Reference_Edit := Create_Control
        (Window, "EDIT", Fixed (Reference_MM, 1),
         WS_TABSTOP or ES_AUTOHSCROLL, Id_Reference_Edit, WS_EX_CLIENTEDGE);
      Calibrate_Button := Button ("Calibrate", Id_Calibrate);
      Results_Label := Static ("");
      Capture_Button := Button (Capture_Text, Id_Capture);
      Status_Label := Static ("Check the camera's IP address and press Connect");

      for Control of HWND_List'
        (Camera_Caption, Camera_Edit, Connect_Button, Exposure_Label,
         Exposure_Bar, Exposure_Edit, Exposure_Unit, Exposure_Set,
         Auto_Exposure_Box, Gain_Label, Gain_Bar, Threshold_Label,
         Threshold_Bar, Auto_Threshold_Box, Light_Radio, Dark_Radio,
         Min_Area_Caption, Min_Area_Edit, Reference_Caption, Reference_Edit,
         Calibrate_Button, Status_Label)
      loop
         Set_Font (Control, UI_Font);
      end loop;
      Set_Font (Results_Label, Result_Font);
      Set_Font (Capture_Button, Big_Font);

      Set_Trackbar (Exposure_Bar, 0, Exposure_Steps, Exposure_Steps / 2);
      Set_Trackbar (Gain_Bar, 0, Gain_Steps, 0);
      Set_Trackbar (Threshold_Bar, 0, 255, Config.Threshold);
      Set_Checked (Auto_Threshold_Box, Config.Auto_Threshold);
      Enable (Threshold_Bar, not Config.Auto_Threshold);
      Set_Checked (Light_Radio, True);
      Show_Threshold;
      Show_Results;
   end Create_Controls;

   procedure Layout (Window : HWND) is
      Results_Top : constant := 432;
      Capture_H   : constant := 44;
      Status_Min  : constant := 40;
      Client    : aliased RECT;
      Ignore    : BOOL;
      Left      : Integer;
      Width     : constant Integer := Panel_Width - 2 * Margin;
      Results_H : Integer;
      Capture_Y : Integer;
      Status_Y  : Integer;
   begin
      Ignore := Get_Client_Rect (Window, Client'Access);
      Left := Integer (Client.Right) - Panel_Width + Margin;
      --  The results give up height, down to two lines, so that Capture
      --  and the status stay in a short window (F2 captures as well).
      Results_H := Integer'Max
        (44, Integer'Min (170, Integer (Client.Bottom) - Results_Top
                                - 4 - Capture_H - 8 - Status_Min - 4));
      Capture_Y := Results_Top + Results_H + 4;
      Status_Y := Capture_Y + Capture_H + 8;
      Place (Camera_Caption, Left, 12, Width, 20);
      Place (Camera_Edit, Left, 34, Width - 96, 28);
      Place (Connect_Button, Left + Width - 88, 33, 88, 30);
      Place (Exposure_Label, Left, 76, Width, 20);
      Place (Exposure_Bar, Left - 4, 96, Width + 8, 30);
      Place (Exposure_Edit, Left, 128, 80, 28);
      Place (Exposure_Unit, Left + 84, 133, 26, 22);
      Place (Exposure_Set, Left + 112, 127, 64, 30);
      Place (Auto_Exposure_Box, Left + 190, 131, Width - 190, 22);
      Place (Gain_Label, Left, 168, Width, 20);
      Place (Gain_Bar, Left - 4, 188, Width + 8, 30);
      Place (Threshold_Label, Left, 228, Width, 20);
      Place (Threshold_Bar, Left - 4, 248, Width + 8, 30);
      Place (Auto_Threshold_Box, Left, 278, Width, 22);
      Place (Light_Radio, Left, 304, Width, 22);
      Place (Dark_Radio, Left, 328, Width, 22);
      Place (Min_Area_Caption, Left, 362, 120, 22);
      Place (Min_Area_Edit, Left + 124, 358, 110, 28);
      Place (Reference_Caption, Left, 396, 120, 22);
      Place (Reference_Edit, Left + 124, 392, 70, 28);
      Place (Calibrate_Button, Left + 202, 391, Width - 202, 30);
      Place (Results_Label, Left, Results_Top, Width, Results_H);
      Place (Capture_Button, Left, Capture_Y, Width, Capture_H);
      Place (Status_Label, Left, Status_Y, Width,
             Integer'Max (Status_Min,
                          Integer (Client.Bottom) - Status_Y - 4));
      Invalidate (Window);
   end Layout;

   procedure On_Command (Id, Code : Natural) is
   begin
      case Id is
         when Id_Connect =>
            if Connected then
               Disconnect;
            else
               Connect;
            end if;
         when Id_Auto_Exposure =>
            --  The box has already toggled itself; it goes back when the
            --  camera refuses, and the manual controls follow it.
            if Connected then
               begin
                  Settings.Set_Auto_Exposure
                    (Camera, Is_Checked (Auto_Exposure_Box));
               exception
                  when others =>
                     Set_Checked (Auto_Exposure_Box,
                                  not Is_Checked (Auto_Exposure_Box));
                     raise;
               end;
               Read_Camera_Settings;
            end if;
            Enable_Exposure_Controls;
         when Id_Auto_Threshold =>
            Config.Auto_Threshold := Is_Checked (Auto_Threshold_Box);
            Enable (Threshold_Bar, not Config.Auto_Threshold);
            Show_Threshold;
         when Id_Light =>
            Config.Polarity := CM.Light_Object;
         when Id_Dark =>
            Config.Polarity := CM.Dark_Object;
         when Id_Min_Area =>
            if Code = EN_CHANGE then
               declare
                  Text : constant Wide_String := Get_Text (Min_Area_Edit);
               begin
                  if Text'Length > 0 then
                     Config.Min_Area := Long_Float'Value
                       (Ada.Characters.Conversions.To_String (Text));
                  end if;
               exception
                  when Constraint_Error =>
                     null;
               end;
            end if;
         when Id_Exposure_Set =>
            Apply_Exposure;
         when Id_Capture =>
            Capture;
         when Id_Calibrate =>
            Calibrate;
         when others =>
            null;
      end case;
   end On_Command;

   procedure On_Scroll (Bar : HWND) is
   begin
      --  A slider's value is sent within the camera's range and what the
      --  camera then holds is read back; when it refuses, the slider goes
      --  back to the last value read.
      if Bar = Exposure_Bar then
         declare
            Value : Long_Float :=
              Exposure_At (Trackbar_Position (Exposure_Bar));
            Low, High : Long_Float;
         begin
            if not Connected then
               Show_Exposure (Value);
               return;
            end if;
            begin
               Settings.Set_Exposure_Time
                 (Camera, Clamp (Value, Exposure_Low, Exposure_High));
            exception
               when others =>
                  if Exposure_Known then
                     Set_Trackbar_Position
                       (Exposure_Bar, Exposure_Position (Exposure_Now));
                  end if;
                  raise;
            end;
            Settings.Get_Exposure_Time (Camera, Value, Low, High);
            Note_Exposure (Value);
         end;
      elsif Bar = Gain_Bar then
         declare
            Value : Long_Float := Gain_At (Trackbar_Position (Gain_Bar));
            Low, High : Long_Float;
         begin
            if not Connected then
               Show_Gain (Value);
               return;
            end if;
            begin
               Settings.Set_Gain (Camera, Clamp (Value, Gain_Low, Gain_High));
            exception
               when others =>
                  if Gain_Known then
                     Set_Trackbar_Position
                       (Gain_Bar, Gain_Position (Gain_Now));
                  end if;
                  raise;
            end;
            Settings.Get_Gain (Camera, Value, Low, High);
            Note_Gain (Value);
         end;
      elsif Bar = Threshold_Bar then
         Config.Threshold :=
           Natural'Min (255, Natural'Max (0, Trackbar_Position (Threshold_Bar)));
         Show_Threshold;
      end if;
   end On_Scroll;

   procedure Shut_Down is
      Ignore_B : BOOL;
      Ignore_O : HGDIOBJ;
   begin
      Stop_Timer (Main, Timer_Id);
      Camera.Close;
      Connected := False;
      if Memory_DC /= Null_Handle and then Bitmap /= Null_Handle then
         Ignore_O := Select_Object (Memory_DC, First_Bitmap);
         Ignore_B := Delete_Object (Bitmap);
      end if;
      Post_Quit_Message (0);
   end Shut_Down;

   function Window_Proc
     (Window : HWND; Message : UINT; W : WPARAM; L : LPARAM) return LRESULT
     with Convention => Stdcall;

   function Window_Proc
     (Window : HWND; Message : UINT; W : WPARAM; L : LPARAM) return LRESULT
   is
   begin
      case Message is
         when WM_CREATE =>
            Main := Window;
            Create_Controls (Window);
            return 0;
         when WM_SIZE =>
            Layout (Window);
            return 0;
         when WM_ERASEBKGND =>
            return 1;
         when WM_PAINT =>
            Paint (Window);
            return 0;
         when WM_TIMER =>
            if Connected then
               Tick;
            end if;
            return 0;
         when WM_COMMAND =>
            On_Command (Natural (W mod 2 ** 16),
                        Natural ((W / 2 ** 16) mod 2 ** 16));
            return 0;
         when WM_HSCROLL =>
            On_Scroll (To_Handle (L));
            return 0;
         when WM_CTLCOLORSTATIC =>
            declare
               Ignore : int;
            begin
               Ignore := Set_Bk_Mode (To_Handle (W), TRANSPARENT);
            end;
            return To_LPARAM (Get_Sys_Color_Brush (COLOR_BTNFACE));
         when WM_DESTROY =>
            Shut_Down;
            return 0;
         when others =>
            return Def_Window_Proc (Window, Message, W, L);
      end case;
   exception
      when E : others =>
         if Status_Label /= Null_Handle then
            Set_Status ("Error: "
                        & Wide (Ada.Exceptions.Exception_Message (E)));
         end if;
         return 0;
   end Window_Proc;

   procedure Run is
      Window : HWND;
      Ignore : Integer;
   begin
      Init_Common_Controls;
      Load_Calibration;
      if not Register_Window_Class (Class_Name, Window_Proc'Access) then
         Show_Error (Null_Handle, "Cannot register the window class",
                     Window_Title);
         return;
      end if;
      Window := Create_Main_Window (Class_Name, Window_Title, 1240, 790);
      if Window = Null_Handle then
         Show_Error (Null_Handle, "Cannot create the window", Window_Title);
         return;
      end if;
      Show (Window);
      if Ada.Command_Line.Argument_Count >= 1 then
         Set_Text (Camera_Edit, Wide (Ada.Command_Line.Argument (1)));
         Connect;
      end if;
      Ignore := Message_Loop (Key_Pressed'Access);
   end Run;

end Live_App;
