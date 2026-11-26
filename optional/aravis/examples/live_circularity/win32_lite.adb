with Ada.Unchecked_Conversion;
with System.Storage_Elements;

package body Win32_Lite is
   use type Interfaces.C.int;
   use type Interfaces.C.unsigned;
   use type Interfaces.Unsigned_16;
   use type Interfaces.Unsigned_32;

   function Get_Module_Handle (Name : System.Address) return HINSTANCE
     with Import, Convention => Stdcall, External_Name => "GetModuleHandleW";
   function Show_Window (Window : HWND; Command : int) return BOOL
     with Import, Convention => Stdcall, External_Name => "ShowWindow";
   function Update_Window (Window : HWND) return BOOL
     with Import, Convention => Stdcall, External_Name => "UpdateWindow";
   function Move_Window
     (Window : HWND; X, Y, Width, Height : int; Repaint : BOOL) return BOOL
     with Import, Convention => Stdcall, External_Name => "MoveWindow";
   function Invalidate_Rect
     (Window : HWND; Area : System.Address; Erase : BOOL) return BOOL
     with Import, Convention => Stdcall, External_Name => "InvalidateRect";
   function Enable_Window (Window : HWND; Enable : BOOL) return BOOL
     with Import, Convention => Stdcall, External_Name => "EnableWindow";
   function Set_Window_Text (Window : HWND; Text : System.Address) return BOOL
     with Import, Convention => Stdcall, External_Name => "SetWindowTextW";
   function Get_Window_Text
     (Window : HWND; Buffer : System.Address; Max_Count : int) return int
     with Import, Convention => Stdcall, External_Name => "GetWindowTextW";
   function Get_Window_Text_Length (Window : HWND) return int
     with Import, Convention => Stdcall,
       External_Name => "GetWindowTextLengthW";
   function Load_Cursor (Instance : HINSTANCE; Name : System.Address)
     return HCURSOR
     with Import, Convention => Stdcall, External_Name => "LoadCursorW";
   function Set_Timer
     (Window : HWND; Id : WPARAM; Elapse : UINT; Proc : System.Address)
      return WPARAM
     with Import, Convention => Stdcall, External_Name => "SetTimer";
   function Kill_Timer (Window : HWND; Id : WPARAM) return BOOL
     with Import, Convention => Stdcall, External_Name => "KillTimer";
   function Message_Box
     (Window : HWND; Text, Caption : System.Address; Kind : UINT) return int
     with Import, Convention => Stdcall, External_Name => "MessageBoxW";
   function Create_Font
     (Height, Width, Escapement, Orientation, Weight : int;
      Italic, Underline, Strike_Out, Char_Set, Out_Precision,
      Clip_Precision, Quality, Pitch_And_Family : DWORD;
      Face : System.Address) return HFONT
     with Import, Convention => Stdcall, External_Name => "CreateFontW";
   function Init_Common_Controls_Ex
     (Init : access constant INITCOMMONCONTROLSEX) return BOOL
     with Import, Convention => Stdcall,
       External_Name => "InitCommonControlsEx";

   Nul : constant Wide_Character := Wide_Character'Val (0);

   function Module_Instance return HINSTANCE is
     (Get_Module_Handle (System.Null_Address));

   function RGB (Red, Green, Blue : Natural) return COLORREF is
     (COLORREF (Red mod 256) + COLORREF (Green mod 256) * 256
      + COLORREF (Blue mod 256) * 65_536);

   function L_To_Handle is new Ada.Unchecked_Conversion (LPARAM, HANDLE);
   function W_To_Handle is new Ada.Unchecked_Conversion (WPARAM, HANDLE);
   function Handle_To_L is new Ada.Unchecked_Conversion (HANDLE, LPARAM);

   function To_Handle (Value : LPARAM) return HANDLE is (L_To_Handle (Value));
   function To_Handle (Value : WPARAM) return HANDLE is (W_To_Handle (Value));
   function To_LPARAM (Value : HANDLE) return LPARAM is (Handle_To_L (Value));

   procedure Init_Common_Controls is
      Init : aliased constant INITCOMMONCONTROLSEX :=
        (Size => INITCOMMONCONTROLSEX'Size / 8, ICC => ICC_BAR_CLASSES);
      Ignore : BOOL;
   begin
      Ignore := Init_Common_Controls_Ex (Init'Access);
   end Init_Common_Controls;

   Stored_Class_Name : access Wide_String;

   function Register_Window_Class
     (Class_Name : Wide_String; Proc : WNDPROC) return Boolean
   is
      Class : aliased WNDCLASSEXW;
   begin
      Stored_Class_Name := new Wide_String'(Class_Name & Nul);
      Class :=
        (Size       => WNDCLASSEXW'Size / 8,
         Style      => 3,  --  CS_HREDRAW | CS_VREDRAW
         Proc       => Proc,
         Instance   => Module_Instance,
         Cursor     => Load_Cursor
                         (Null_Handle, System'To_Address (IDC_ARROW)),
         Background => Null_Handle,
         Class_Name => Stored_Class_Name.all'Address,
         others     => <>);
      return Register_Class (Class'Access) /= 0;
   end Register_Window_Class;

   function Create_Main_Window
     (Class_Name, Title : Wide_String; Width, Height : Natural) return HWND
   is
      Class_Z : aliased constant Wide_String := Class_Name & Nul;
      Title_Z : aliased constant Wide_String := Title & Nul;
   begin
      return Create_Window_Ex
        (0, Class_Z'Address, Title_Z'Address,
         WS_OVERLAPPEDWINDOW or WS_CLIPCHILDREN,
         CW_USEDEFAULT, CW_USEDEFAULT, int (Width), int (Height),
         Null_Handle, Null_Handle, Module_Instance, System.Null_Address);
   end Create_Main_Window;

   function Create_Control
     (Parent   : HWND;
      Class    : Wide_String;
      Text     : Wide_String;
      Style    : DWORD;
      Id       : Natural := 0;
      Ex_Style : DWORD := 0) return HWND
   is
      Class_Z : aliased constant Wide_String := Class & Nul;
      Text_Z  : aliased constant Wide_String := Text & Nul;
   begin
      return Create_Window_Ex
        (Ex_Style, Class_Z'Address, Text_Z'Address,
         WS_CHILD or WS_VISIBLE or Style, 0, 0, 10, 10, Parent,
         System'To_Address (Id), Module_Instance, System.Null_Address);
   end Create_Control;

   function Create_UI_Font
     (Face : Wide_String; Height : Integer; Weight : Integer := 400)
      return HFONT
   is
      Face_Z : aliased constant Wide_String := Face & Nul;
   begin
      --  DEFAULT_CHARSET 1, CLEARTYPE_QUALITY 5
      return Create_Font
        (int (-Height), 0, 0, 0, int (Weight), 0, 0, 0, 1, 0, 0, 5, 0,
         Face_Z'Address);
   end Create_UI_Font;

   function Message_Loop (On_Key : Key_Handler := null) return Integer is
      WM_KEYDOWN : constant := 16#0100#;
      Message : aliased MSG;
      Ignore_B : BOOL;
      Ignore_R : LRESULT;
   begin
      while Get_Message (Message'Access, Null_Handle, 0, 0) > 0 loop
         if Message.Message = WM_KEYDOWN and then On_Key /= null
           and then On_Key (Message.Window, Message.W)
         then
            null;
         else
            Ignore_B := Translate_Message (Message'Access);
            Ignore_R := Dispatch_Message (Message'Access);
         end if;
      end loop;
      return Integer (Message.W mod 2 ** 31);
   end Message_Loop;

   procedure Show (Window : HWND) is
      Ignore : BOOL;
   begin
      Ignore := Show_Window (Window, SW_SHOW);
      Ignore := Update_Window (Window);
   end Show;

   procedure Place (Window : HWND; X, Y, Width, Height : Integer) is
      Ignore : BOOL;
   begin
      Ignore := Move_Window
        (Window, int (X), int (Y), int (Width), int (Height), 1);
   end Place;

   procedure Invalidate (Window : HWND) is
      Ignore : BOOL;
   begin
      Ignore := Invalidate_Rect (Window, System.Null_Address, 0);
   end Invalidate;

   procedure Enable (Window : HWND; On : Boolean) is
      Ignore : BOOL;
   begin
      Ignore := Enable_Window (Window, Boolean'Pos (On));
   end Enable;

   procedure Set_Text (Window : HWND; Text : Wide_String) is
      Text_Z : aliased constant Wide_String := Text & Nul;
      Ignore : BOOL;
   begin
      Ignore := Set_Window_Text (Window, Text_Z'Address);
   end Set_Text;

   function Get_Text (Window : HWND) return Wide_String is
      Length : constant Natural := Natural (Get_Window_Text_Length (Window));
      Buffer : aliased Wide_String (1 .. Length + 1);
      Copied : int;
   begin
      Copied := Get_Window_Text (Window, Buffer'Address, int (Length + 1));
      return Buffer (1 .. Natural (Copied));
   end Get_Text;

   procedure Set_Font (Window : HWND; Font : HFONT) is
      Ignore : LRESULT;
   begin
      Ignore := Send_Message
        (Window, WM_SETFONT,
         WPARAM (System.Storage_Elements.To_Integer (Font)), 1);
   end Set_Font;

   function Is_Checked (Button : HWND) return Boolean is
     (Send_Message (Button, BM_GETCHECK, 0, 0) = 1);

   procedure Set_Checked (Button : HWND; Checked : Boolean) is
      Ignore : LRESULT;
   begin
      Ignore := Send_Message
        (Button, BM_SETCHECK, WPARAM (Boolean'Pos (Checked)), 0);
   end Set_Checked;

   procedure Set_Trackbar (Bar : HWND; Low, High, Position : Integer) is
      Ignore : LRESULT;
   begin
      Ignore := Send_Message (Bar, TBM_SETRANGEMIN, 0, LPARAM (Low));
      Ignore := Send_Message (Bar, TBM_SETRANGEMAX, 1, LPARAM (High));
      Set_Trackbar_Position (Bar, Position);
   end Set_Trackbar;

   procedure Set_Trackbar_Position (Bar : HWND; Position : Integer) is
      Ignore : LRESULT;
   begin
      Ignore := Send_Message (Bar, TBM_SETPOS, 1, LPARAM (Position));
   end Set_Trackbar_Position;

   function Trackbar_Position (Bar : HWND) return Integer is
     (Integer (Send_Message (Bar, TBM_GETPOS, 0, 0)));

   procedure Start_Timer (Window : HWND; Id : WPARAM; Milliseconds : Natural)
   is
      Ignore : WPARAM;
   begin
      Ignore := Set_Timer
        (Window, Id, UINT (Milliseconds), System.Null_Address);
   end Start_Timer;

   procedure Stop_Timer (Window : HWND; Id : WPARAM) is
      Ignore : BOOL;
   begin
      Ignore := Kill_Timer (Window, Id);
   end Stop_Timer;

   procedure Show_Error (Owner : HWND; Text, Caption : Wide_String) is
      Text_Z    : aliased constant Wide_String := Text & Nul;
      Caption_Z : aliased constant Wide_String := Caption & Nul;
      Ignore    : int;
   begin
      Ignore := Message_Box
        (Owner, Text_Z'Address, Caption_Z'Address, MB_ICONERROR);
   end Show_Error;

end Win32_Lite;
