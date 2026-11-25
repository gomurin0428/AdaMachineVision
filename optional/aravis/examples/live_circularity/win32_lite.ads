with Interfaces;
with Interfaces.C;
with System;

--  The few Win32 calls (user32, gdi32, comctl32, kernel32) the live
--  circularity window needs, with small wrappers that take Wide_String.
package Win32_Lite is
   pragma Linker_Options ("-lcomctl32");
   pragma Linker_Options ("-lgdi32");
   pragma Linker_Options ("-luser32");

   subtype HANDLE is System.Address;
   subtype HWND is HANDLE;
   subtype HINSTANCE is HANDLE;
   subtype HDC is HANDLE;
   subtype HGDIOBJ is HANDLE;
   subtype HBITMAP is HANDLE;
   subtype HBRUSH is HANDLE;
   subtype HPEN is HANDLE;
   subtype HFONT is HANDLE;
   subtype HCURSOR is HANDLE;
   Null_Handle : constant HANDLE := System.Null_Address;

   subtype int is Interfaces.C.int;
   subtype UINT is Interfaces.C.unsigned;
   subtype DWORD is Interfaces.Unsigned_32;
   subtype BOOL is Interfaces.C.int;
   type WPARAM is mod 2 ** 64;
   type LPARAM is range -(2 ** 63) .. 2 ** 63 - 1;
   subtype LRESULT is LPARAM;
   subtype COLORREF is DWORD;

   type WNDPROC is access function
     (Window : HWND; Message : UINT; W : WPARAM; L : LPARAM) return LRESULT
     with Convention => Stdcall;

   type POINT is record
      X, Y : int := 0;
   end record
     with Convention => C;

   type POINT_Array is array (Natural range <>) of POINT
     with Convention => C;

   type RECT is record
      Left, Top, Right, Bottom : int := 0;
   end record
     with Convention => C;

   type WNDCLASSEXW is record
      Size         : UINT := 0;
      Style        : UINT := 0;
      Proc         : WNDPROC := null;
      Class_Extra  : int := 0;
      Window_Extra : int := 0;
      Instance     : HINSTANCE := Null_Handle;
      Icon         : HANDLE := Null_Handle;
      Cursor       : HCURSOR := Null_Handle;
      Background   : HBRUSH := Null_Handle;
      Menu_Name    : System.Address := System.Null_Address;
      Class_Name   : System.Address := System.Null_Address;
      Small_Icon   : HANDLE := Null_Handle;
   end record
     with Convention => C;

   type MSG is record
      Window       : HWND := Null_Handle;
      Message      : UINT := 0;
      W            : WPARAM := 0;
      L            : LPARAM := 0;
      Time         : DWORD := 0;
      Pt           : POINT;
      Private_Data : DWORD := 0;
   end record
     with Convention => C;

   type Byte_32 is array (1 .. 32) of Interfaces.Unsigned_8
     with Convention => C;

   type PAINTSTRUCT is record
      DC         : HDC := Null_Handle;
      Erase      : BOOL := 0;
      Paint      : RECT;
      Restore    : BOOL := 0;
      Inc_Update : BOOL := 0;
      Reserved   : Byte_32 := [others => 0];
   end record
     with Convention => C;

   type BITMAPINFOHEADER is record
      Size             : DWORD := 0;
      Width            : Interfaces.Integer_32 := 0;
      Height           : Interfaces.Integer_32 := 0;
      Planes           : Interfaces.Unsigned_16 := 0;
      Bit_Count        : Interfaces.Unsigned_16 := 0;
      Compression      : DWORD := 0;
      Size_Image       : DWORD := 0;
      X_Pels_Per_Meter : Interfaces.Integer_32 := 0;
      Y_Pels_Per_Meter : Interfaces.Integer_32 := 0;
      Clr_Used         : DWORD := 0;
      Clr_Important    : DWORD := 0;
   end record
     with Convention => C;

   type INITCOMMONCONTROLSEX is record
      Size : DWORD := 0;
      ICC  : DWORD := 0;
   end record
     with Convention => C;

   --  Messages, styles and other constants
   WM_CREATE           : constant := 16#0001#;
   WM_DESTROY          : constant := 16#0002#;
   WM_SIZE             : constant := 16#0005#;
   WM_PAINT            : constant := 16#000F#;
   WM_ERASEBKGND       : constant := 16#0014#;
   WM_SETFONT          : constant := 16#0030#;
   WM_COMMAND          : constant := 16#0111#;
   WM_TIMER            : constant := 16#0113#;
   WM_HSCROLL          : constant := 16#0114#;
   WM_CTLCOLORSTATIC   : constant := 16#0138#;
   WM_USER             : constant := 16#0400#;

   WS_OVERLAPPEDWINDOW : constant DWORD := 16#00CF_0000#;
   WS_CLIPCHILDREN     : constant DWORD := 16#0200_0000#;
   WS_CHILD            : constant DWORD := 16#4000_0000#;
   WS_VISIBLE          : constant DWORD := 16#1000_0000#;
   WS_TABSTOP          : constant DWORD := 16#0001_0000#;
   WS_GROUP            : constant DWORD := 16#0002_0000#;
   WS_EX_CLIENTEDGE    : constant DWORD := 16#0000_0200#;
   CW_USEDEFAULT       : constant int := int'First;

   BS_PUSHBUTTON       : constant DWORD := 16#0000#;
   BS_AUTOCHECKBOX     : constant DWORD := 16#0003#;
   BS_AUTORADIOBUTTON  : constant DWORD := 16#0009#;
   ES_AUTOHSCROLL      : constant DWORD := 16#0080#;
   ES_NUMBER           : constant DWORD := 16#2000#;
   TBS_NOTICKS         : constant DWORD := 16#0010#;
   BN_CLICKED          : constant := 0;
   EN_CHANGE           : constant := 16#0300#;
   BM_GETCHECK         : constant := 16#00F0#;
   BM_SETCHECK         : constant := 16#00F1#;
   TBM_GETPOS          : constant := WM_USER;
   TBM_SETPOS          : constant := WM_USER + 5;
   TBM_SETRANGEMIN     : constant := WM_USER + 7;
   TBM_SETRANGEMAX     : constant := WM_USER + 8;
   ICC_BAR_CLASSES     : constant DWORD := 16#0004#;

   SW_SHOW             : constant := 5;
   COLOR_BTNFACE       : constant := 15;
   DIB_RGB_COLORS      : constant := 0;
   BI_RGB              : constant := 0;
   SRCCOPY             : constant DWORD := 16#00CC_0020#;
   HALFTONE            : constant := 4;
   PS_SOLID            : constant := 0;
   TRANSPARENT         : constant := 1;
   NULL_BRUSH          : constant := 5;
   DKGRAY_BRUSH        : constant := 3;
   MB_ICONERROR        : constant := 16#0010#;
   IDC_ARROW           : constant := 32_512;

   --  user32
   function Register_Class (Class : access constant WNDCLASSEXW)
     return Interfaces.Unsigned_16
     with Import, Convention => Stdcall, External_Name => "RegisterClassExW";
   function Create_Window_Ex
     (Ex_Style : DWORD; Class_Name, Window_Name : System.Address;
      Style : DWORD; X, Y, Width, Height : int; Parent : HWND;
      Menu : HANDLE; Instance : HINSTANCE; Param : System.Address)
      return HWND
     with Import, Convention => Stdcall, External_Name => "CreateWindowExW";
   function Def_Window_Proc
     (Window : HWND; Message : UINT; W : WPARAM; L : LPARAM) return LRESULT
     with Import, Convention => Stdcall, External_Name => "DefWindowProcW";
   function Get_Message
     (Message : access MSG; Window : HWND; Min, Max : UINT) return BOOL
     with Import, Convention => Stdcall, External_Name => "GetMessageW";
   function Translate_Message (Message : access constant MSG) return BOOL
     with Import, Convention => Stdcall, External_Name => "TranslateMessage";
   function Dispatch_Message (Message : access constant MSG) return LRESULT
     with Import, Convention => Stdcall, External_Name => "DispatchMessageW";
   procedure Post_Quit_Message (Exit_Code : int)
     with Import, Convention => Stdcall, External_Name => "PostQuitMessage";
   function Send_Message
     (Window : HWND; Message : UINT; W : WPARAM; L : LPARAM) return LRESULT
     with Import, Convention => Stdcall, External_Name => "SendMessageW";
   function Begin_Paint (Window : HWND; Paint : access PAINTSTRUCT)
     return HDC
     with Import, Convention => Stdcall, External_Name => "BeginPaint";
   function End_Paint (Window : HWND; Paint : access constant PAINTSTRUCT)
     return BOOL
     with Import, Convention => Stdcall, External_Name => "EndPaint";
   function Get_Client_Rect (Window : HWND; Area : access RECT) return BOOL
     with Import, Convention => Stdcall, External_Name => "GetClientRect";
   function Get_DC (Window : HWND) return HDC
     with Import, Convention => Stdcall, External_Name => "GetDC";
   function Release_DC (Window : HWND; DC : HDC) return int
     with Import, Convention => Stdcall, External_Name => "ReleaseDC";
   function Fill_Rect
     (DC : HDC; Area : access constant RECT; Brush : HBRUSH) return int
     with Import, Convention => Stdcall, External_Name => "FillRect";
   function Get_Sys_Color_Brush (Index : int) return HBRUSH
     with Import, Convention => Stdcall,
       External_Name => "GetSysColorBrush";
   function Get_Sys_Color (Index : int) return COLORREF
     with Import, Convention => Stdcall, External_Name => "GetSysColor";

   --  gdi32
   function Get_Stock_Object (Index : int) return HGDIOBJ
     with Import, Convention => Stdcall, External_Name => "GetStockObject";
   function Create_Compatible_DC (DC : HDC) return HDC
     with Import, Convention => Stdcall,
       External_Name => "CreateCompatibleDC";
   function Create_DIB_Section
     (DC : HDC; Info : access constant BITMAPINFOHEADER; Usage : UINT;
      Bits : access System.Address; Section : HANDLE; Offset : DWORD)
      return HBITMAP
     with Import, Convention => Stdcall,
       External_Name => "CreateDIBSection";
   function Select_Object (DC : HDC; Object : HGDIOBJ) return HGDIOBJ
     with Import, Convention => Stdcall, External_Name => "SelectObject";
   function Delete_Object (Object : HGDIOBJ) return BOOL
     with Import, Convention => Stdcall, External_Name => "DeleteObject";
   function Set_Stretch_Blt_Mode (DC : HDC; Mode : int) return int
     with Import, Convention => Stdcall,
       External_Name => "SetStretchBltMode";
   function Set_Brush_Org_Ex
     (DC : HDC; X, Y : int; Previous : System.Address) return BOOL
     with Import, Convention => Stdcall, External_Name => "SetBrushOrgEx";
   function Stretch_Blt
     (Destination : HDC; X, Y, Width, Height : int; Source : HDC;
      Source_X, Source_Y, Source_Width, Source_Height : int; Rop : DWORD)
      return BOOL
     with Import, Convention => Stdcall, External_Name => "StretchBlt";
   function Create_Pen (Style, Width : int; Colour : COLORREF) return HPEN
     with Import, Convention => Stdcall, External_Name => "CreatePen";
   function Polyline (DC : HDC; Points : System.Address; Count : int)
     return BOOL
     with Import, Convention => Stdcall, External_Name => "Polyline";
   function Ellipse (DC : HDC; Left, Top, Right, Bottom : int) return BOOL
     with Import, Convention => Stdcall, External_Name => "Ellipse";
   function Move_To (DC : HDC; X, Y : int; Previous : System.Address)
     return BOOL
     with Import, Convention => Stdcall, External_Name => "MoveToEx";
   function Line_To (DC : HDC; X, Y : int) return BOOL
     with Import, Convention => Stdcall, External_Name => "LineTo";
   function Set_Bk_Mode (DC : HDC; Mode : int) return int
     with Import, Convention => Stdcall, External_Name => "SetBkMode";

   --  kernel32
   function Get_Tick_Count_64 return Interfaces.Unsigned_64
     with Import, Convention => Stdcall, External_Name => "GetTickCount64";

   --  Wrappers
   function Module_Instance return HINSTANCE;
   function RGB (Red, Green, Blue : Natural) return COLORREF;
   function To_Handle (Value : LPARAM) return HANDLE;
   function To_Handle (Value : WPARAM) return HANDLE;
   function To_LPARAM (Value : HANDLE) return LPARAM;
   --  Bit-for-bit: handles passed in messages may have the top bit set.

   procedure Init_Common_Controls;
   function Register_Window_Class
     (Class_Name : Wide_String; Proc : WNDPROC) return Boolean;
   function Create_Main_Window
     (Class_Name, Title : Wide_String; Width, Height : Natural) return HWND;
   function Create_Control
     (Parent   : HWND;
      Class    : Wide_String;
      Text     : Wide_String;
      Style    : DWORD;
      Id       : Natural := 0;
      Ex_Style : DWORD := 0) return HWND;
   function Create_UI_Font
     (Face : Wide_String; Height : Integer; Weight : Integer := 400)
      return HFONT;
   type Key_Handler is access function (Window : HWND; Key : WPARAM)
     return Boolean;
   function Message_Loop (On_Key : Key_Handler := null) return Integer;
   --  Runs until WM_QUIT. A key press (WM_KEYDOWN) is first offered to
   --  On_Key, with the window that has the focus; True means it was
   --  handled and is not passed on.

   procedure Show (Window : HWND);
   procedure Place (Window : HWND; X, Y, Width, Height : Integer);
   procedure Invalidate (Window : HWND);
   procedure Enable (Window : HWND; On : Boolean);
   procedure Set_Text (Window : HWND; Text : Wide_String);
   function Get_Text (Window : HWND) return Wide_String;
   procedure Set_Font (Window : HWND; Font : HFONT);
   function Is_Checked (Button : HWND) return Boolean;
   procedure Set_Checked (Button : HWND; Checked : Boolean);
   procedure Set_Trackbar (Bar : HWND; Low, High, Position : Integer);
   procedure Set_Trackbar_Position (Bar : HWND; Position : Integer);
   function Trackbar_Position (Bar : HWND) return Integer;
   procedure Start_Timer (Window : HWND; Id : WPARAM; Milliseconds : Natural);
   procedure Stop_Timer (Window : HWND; Id : WPARAM);
   procedure Show_Error (Owner : HWND; Text, Caption : Wide_String);

end Win32_Lite;
