--  A robustness sweep of the whole Ada API (docs/DESIGN.md section 8).
--
--  Every tool type of the Ada API (every extension of AMV.Tools.Ks_Tool)
--  runs with adversarial inputs: an unallocated input image, a 1 x 1
--  image, a larger image, images whose pixel-from-root transform scales by
--  1.0E140 or 1.0E-140 or mirrors, and each numeric run parameter, region
--  and shape coordinate set in turn to NaN, +Inf, -Inf, 0, -1 and huge
--  values (1.0E300 and the bound 1.0E150 of the kernels), each integer
--  parameter to Integer'First, -1, 0 and Integer'Last where its Ada type
--  allows, and each space name to malformed or missing names. Run must
--  not raise, and a run that fails must report an AMV exception
--  (AMV.KS_...) in its Run_Status: never Constraint_Error, Program_Error,
--  Storage_Error or another exception of the language or the runtime.
--
--  The subprograms outside the tools that take numbers directly (shape
--  setters, transform constructors and Map_Point, image Create with odd
--  sizes, coordinate space operations, the geometry and image math
--  helpers, the accessors of results with bad indices, ...) are called
--  with the same values, and every exception they raise must be an AMV
--  exception, except the Constraint_Error that a spec documents for an
--  index beyond a collection or an image.
--
--  The library is compiled with the test switches, -gnatVa (validity
--  checks) and Initialize_Scalars included, so a NaN that the Ada layer
--  copies on its way to a kernel shows up as the Constraint_Error that it
--  would raise there.
--
--  Each area counts as one check; every leak is printed as a line
--  "LEAK [area] <call>: <exception>: <message>". A few checks besides pin
--  down the exception of the readers of records changed by hand (Kind,
--  Enabled and Count of caliper scorers and IP operators).

pragma Validity_Checks ("F");
--  The sweeps pass NaNs and infinities on purpose.

with Ada.Exceptions;
with Ada.Numerics;
with Ada.Numerics.Long_Elementary_Functions;
with Ada.Streams;
with Ada.Streams.Storage.Unbounded;
with Ada.Strings.Fixed;
with Ada.Strings.Unbounded;
with Ada.Text_IO;

with AMV;                                  use AMV;
with AMV.Blob;
with AMV.Calib_Fix;
with AMV.Caliper;
with AMV.Caliper.Find_Circle;
with AMV.Caliper.Find_Line;
with AMV.CNL_Search;
with AMV.Coordinate_Spaces;
with AMV.Dimensioning;
with AMV.Dimensioning.Create_Shapes;
with AMV.Dimensioning.Fitting;
with AMV.Geometry;
with AMV.Image_File;
with AMV.Image_Math;
with AMV.Image_Processing.Affine_Transform;
with AMV.Image_Processing.Copy_Region;
with AMV.Image_Processing.Histogram;
with AMV.Image_Processing.Image_Convert;
with AMV.Image_Processing.IP_One_Image;
with AMV.Image_Processing.IP_Two_Image;
with AMV.Image_Processing.Pixel_Map;
with AMV.Image_Processing.Polar_Unwrap;
with AMV.Image_Processing.Sharpness;
with AMV.Image_Processing.Sobel_Edge;
with AMV.Images;                           use AMV.Images;
with AMV.Images.Image_Holders;
with AMV.Kernels;
with AMV.Misc;
with AMV.PM_Align;
with AMV.Regions;
with AMV.Shapes;                           use AMV.Shapes;
with AMV.Shapes.Region_Holders;
with AMV.Tool_Block;
with AMV.Tool_Group;
with AMV.Tools;                            use AMV.Tools;
with AMV.Transforms;                       use AMV.Transforms;
with AMV_Test_Images;
with AMV_Test_Support;                     use AMV_Test_Support;

procedure Test_Robustness is

   package CS renames AMV.Coordinate_Spaces;
   package IH renames AMV.Images.Image_Holders;
   package RH renames AMV.Shapes.Region_Holders;
   package TI renames AMV_Test_Images;

   subtype Int32 is AMV.Kernels.Int32;

   Pi : constant := Ada.Numerics.Pi;

   ---------------------------------------------------------------------
   --  The values
   ---------------------------------------------------------------------

   Zero : constant Real := Real'Value ("0.0");
   NaN  : constant Real := Zero / Zero;
   Inf  : constant Real := 1.0 / Zero;

   type Real_List is array (Positive range <>) of Real;

   Bad_Reals : constant Real_List :=
     [NaN, Inf, -Inf, 0.0, -1.0, 1.0E300, -1.0E300, 1.0E150, -1.0E150];

   type Integer_List is array (Positive range <>) of Integer;

   Bad_Integers : constant Integer_List :=
     [Integer'First, -1, 0, Integer'Last];
   Bad_Naturals : constant Integer_List := [0, Natural'Last];
   Bad_Indices  : constant Integer_List := [0, 1, 1_000, Natural'Last];

   Bad_Name_Count : constant := 8;

   function Bad_Name (Index : Positive) return String is
     (case Index is
         when 1      => "",
         when 2      => "@\Missing",
         when 3      => "Missing",
         when 4      => "\",
         when 5      => "@\\",
         when 6      => "#\A",
         when 7      => [1 .. 300 => 'x'],
         when others => [1 => Character'Val (0)]);

   function Image (Value : Real) return String is
     (if Value /= Value then "NaN"
      elsif Value > Real'Last then "+Inf"
      elsif Value < -Real'Last then "-Inf"
      else Ada.Strings.Fixed.Trim (Real'Image (Value), Ada.Strings.Left));

   function Image (Value : Integer) return String is
     (Ada.Strings.Fixed.Trim (Integer'Image (Value), Ada.Strings.Left));

   ---------------------------------------------------------------------
   --  Recording calls and leaks
   ---------------------------------------------------------------------

   Area       : Ada.Strings.Unbounded.Unbounded_String;
   Area_Calls : Natural := 0;
   Area_Leaks : Natural := 0;
   All_Calls  : Natural := 0;
   All_Leaks  : Natural := 0;
   Tool_Types : Natural := 0;
   Consumed   : Natural := 0;

   procedure Begin_Area (Name : String; Is_Tool : Boolean := False) is
   begin
      Section ("Robustness: " & Name);
      Area := Ada.Strings.Unbounded.To_Unbounded_String (Name);
      Area_Calls := 0;
      Area_Leaks := 0;
      if Is_Tool then
         Tool_Types := Tool_Types + 1;
      end if;
   end Begin_Area;

   procedure End_Area is
   begin
      Check (Area_Leaks = 0,
             Ada.Strings.Unbounded.To_String (Area) & ":"
             & Area_Calls'Image & " calls," & Area_Leaks'Image
             & " non-AMV exceptions");
      All_Calls := All_Calls + Area_Calls;
      All_Leaks := All_Leaks + Area_Leaks;
   end End_Area;

   procedure Leak (Call, Name, Message : String) is
   begin
      Area_Leaks := Area_Leaks + 1;
      Ada.Text_IO.Put_Line
        ("LEAK [" & Ada.Strings.Unbounded.To_String (Area) & "] " & Call
         & ": " & Name & ": " & Message);
   end Leak;

   function Is_AMV (Name : String) return Boolean is
     (Name'Length > 7 and then Name (Name'First .. Name'First + 6) = "AMV.KS_");

   procedure Note
     (Call                : String;
      Occurrence          : Ada.Exceptions.Exception_Occurrence;
      Index_Error_Allowed : Boolean := False)
   is
      Name : constant String := Ada.Exceptions.Exception_Name (Occurrence);
   begin
      if not Is_AMV (Name)
        and then not (Index_Error_Allowed and then Name = "CONSTRAINT_ERROR")
      then
         Leak (Call, Name, Ada.Exceptions.Exception_Message (Occurrence));
      end if;
   end Note;

   procedure Try
     (Call                : String;
      Action              : not null access procedure;
      Index_Error_Allowed : Boolean := False) is
   begin
      Area_Calls := Area_Calls + 1;
      Action.all;
   exception
      when Occurrence : others =>
         Note (Call, Occurrence, Index_Error_Allowed);
   end Try;
   --  Calls Action; an exception that is not an AMV one (nor, when
   --  allowed, the documented Constraint_Error for a bad index) is a leak.

   procedure Run_Tool
     (Tool                : in out Ks_Tool'Class;
      Call                : String;
      Member_Error_Allowed : Boolean := False) is
   begin
      Area_Calls := Area_Calls + 1;
      begin
         Tool.Run;
      exception
         when Occurrence : others =>
            Leak (Call & " (Run propagated it)",
                  Ada.Exceptions.Exception_Name (Occurrence),
                  Ada.Exceptions.Exception_Message (Occurrence));
            return;
      end;
      if Tool.Run_Status.Result = Error
        and then not Is_AMV (Tool.Run_Status.Exception_Name)
        and then not (Member_Error_Allowed
                      and then Tool.Run_Status.Exception_Name = "")
      then
         Leak (Call, "Run_Status " & Tool.Run_Status.Exception_Name,
               Tool.Run_Status.Message);
      end if;
   end Run_Tool;
   --  A tool group reports a member's failure with an empty
   --  Exception_Name (AMV.Tool_Group); Member_Error_Allowed accepts it.

   procedure Consume (Value : Real) is
      pragma Unreferenced (Value);
   begin
      Consumed := Consumed + 1;
   end Consume;

   procedure Consume (Value : Integer) is
      pragma Unreferenced (Value);
   begin
      Consumed := Consumed + 1;
   end Consume;

   procedure Consume (Value : Boolean) is
      pragma Unreferenced (Value);
   begin
      Consumed := Consumed + 1;
   end Consume;

   procedure Consume (Value : String) is
      pragma Unreferenced (Value);
   begin
      Consumed := Consumed + 1;
   end Consume;

   procedure Use_Nothing (T : Ks_Transform_2D_Linear) is
      pragma Unreferenced (T);
   begin
      Consumed := Consumed + 1;
   end Use_Nothing;

   procedure Composite
     (Name  : String;
      Valid : Real_List;
      Call  : not null access procedure (Args : Real_List))
   is
      procedure Call_Valid is
      begin
         Call (Valid);
      end Call_Valid;
   begin
      Try (Name & " (valid arguments)", Call_Valid'Access);
      for Position in Valid'Range loop
         for Value of Bad_Reals loop
            declare
               Args : Real_List := Valid;
               procedure Action is
               begin
                  Call (Args);
               end Action;
            begin
               Args (Position) := Value;
               Try (Name & " (argument" & Position'Image & " = "
                    & Image (Value) & ")", Action'Access);
            end;
         end loop;
      end loop;
   end Composite;
   --  Calls Call with Valid, then with each argument in turn replaced by
   --  each bad value.

   procedure Field_Sweep
     (Name   : String;
      Count  : Positive;
      Call   : not null access procedure (Field : Positive; Value : Real)) is
   begin
      for Field in 1 .. Count loop
         for Value of Bad_Reals loop
            declare
               procedure Action is
               begin
                  Call (Field, Value);
               end Action;
            begin
               Try (Name & " (field" & Field'Image & " = " & Image (Value)
                    & ")", Action'Access);
            end;
         end loop;
      end loop;
   end Field_Sweep;

   procedure Integer_Sweep
     (Name                : String;
      Values              : Integer_List;
      Call                : not null access procedure (Value : Integer);
      Index_Error_Allowed : Boolean := False) is
   begin
      for Value of Values loop
         declare
            procedure Action is
            begin
               Call (Value);
            end Action;
         begin
            Try (Name & " (" & Image (Value) & ")", Action'Access,
                 Index_Error_Allowed);
         end;
      end loop;
   end Integer_Sweep;

   procedure Name_Sweep
     (Name : String;
      Call : not null access procedure (Value : String)) is
   begin
      for Index in 1 .. Bad_Name_Count loop
         declare
            procedure Action is
            begin
               Call (Bad_Name (Index));
            end Action;
         begin
            Try (Name & " (bad name" & Index'Image & ")", Action'Access);
         end;
      end loop;
   end Name_Sweep;

   function Field_Count (Names : String) return Positive is
     (Ada.Strings.Fixed.Count (Names, ",") + 1);

   function Field_Name (Names : String; Index : Positive) return String is
      First : Positive := Names'First;
      Count : Positive := 1;
   begin
      for I in Names'Range loop
         if Names (I) = ',' then
            if Count = Index then
               return Names (First .. I - 1);
            end if;
            Count := Count + 1;
            First := I + 1;
         end if;
      end loop;
      return Names (First .. Names'Last);
   end Field_Name;

   function Prefixed (Prefix, Fields : String) return String is
      Result : Ada.Strings.Unbounded.Unbounded_String;
   begin
      for I in 1 .. Field_Count (Fields) loop
         if I > 1 then
            Ada.Strings.Unbounded.Append (Result, ",");
         end if;
         Ada.Strings.Unbounded.Append
           (Result, Prefix & "." & Field_Name (Fields, I));
      end loop;
      return Ada.Strings.Unbounded.To_String (Result);
   end Prefixed;

   ---------------------------------------------------------------------
   --  Images
   ---------------------------------------------------------------------

   function Scene (Width, Height : Positive) return Ks_Image_8_Grey is
      W : constant Real := Real (Width);
      H : constant Real := Real (Height);
      Result : Ks_Image_8_Grey := TI.Blank (Width, Height, 40);
   begin
      TI.Draw_Rectangle (Result, 0.3 * W, 0.4 * H, 0.25 * W, 0.3 * H, 0.2,
                         200, Samples => 2);
      TI.Draw_Circle (Result, 0.7 * W, 0.6 * H, 0.15 * H, 220,
                      Samples => 2);
      return Result;
   end Scene;

   function No_Image return Ks_Image_8_Grey is
   begin
      return Result : Ks_Image_8_Grey do
         null;
      end return;
   end No_Image;

   Small : constant Ks_Image_8_Grey := Scene (64, 48);
   Large : constant Ks_Image_8_Grey := Scene (640, 480);
   Tiny  : constant Ks_Image_8_Grey := Create (1, 1, 128);

   function With_Root
     (Image : Ks_Image_8_Grey; T : Ks_Transform_2D_Linear)
      return Ks_Image_8_Grey
   is
      Result : Ks_Image_8_Grey := Image.Copy (Share_Pixels);
   begin
      Result.Set_Pixel_From_Root_Transform (T);
      return Result;
   end With_Root;

   type Image_Case is
     (Unallocated, One_Pixel, Large_Scene, Pixel_From_Root_1E140,
      Pixel_From_Root_1E_Minus_140, Mirrored, Pixel_Space_Selected);

   function Test_Image (Kind : Image_Case) return Ks_Image_8_Grey is
   begin
      case Kind is
         when Unallocated =>
            return No_Image;
         when One_Pixel =>
            return Tiny;
         when Large_Scene =>
            return Large;
         when Pixel_From_Root_1E140 =>
            return With_Root (Small, Create (1.0E140, 0.0, 0.0, 1.0E140,
                                             0.0, 0.0));
         when Pixel_From_Root_1E_Minus_140 =>
            return With_Root (Small, Create (1.0E-140, 0.0, 0.0, 1.0E-140,
                                             0.0, 0.0));
         when Mirrored =>
            return With_Root (Small, Create (-1.0, 0.0, 0.0, 1.0, 63.0,
                                             0.0));
         when Pixel_Space_Selected =>
            return Result : Ks_Image_8_Grey := Small.Copy (Share_Pixels) do
               Result.Set_Selected_Space_Name ("#");
            end return;
      end case;
   end Test_Image;

   ---------------------------------------------------------------------
   --  Shapes with one property replaced (Field 0: the valid shape)
   ---------------------------------------------------------------------

   type Region_Kind is
     (Rectangle, Rectangle_Affine, Circle, Ellipse, Polygon,
      Annulus_Section);
   type Region_Kinds is array (Region_Kind) of Boolean;

   All_Regions : constant Region_Kinds := [others => True];

   function Region_Fields (Kind : Region_Kind) return String is
     (case Kind is
         when Rectangle        => "X,Y,Width,Height",
         when Rectangle_Affine =>
            "CenterX,CenterY,SideXLength,SideYLength,Rotation,Skew",
         when Circle           => "CenterX,CenterY,Radius",
         when Ellipse          => "CenterX,CenterY,RadiusX,RadiusY,Rotation",
         when Polygon          => "Vertex0X,Vertex0Y,Vertex2X,Vertex2Y",
         when Annulus_Section  =>
            "CenterX,CenterY,Radius,RadialScale,AngleStart,AngleSpan");

   function Region_With
     (Kind : Region_Kind; Field : Natural; Value : Real)
      return Ks_Region'Class is
   begin
      case Kind is
         when Rectangle =>
            return R : Ks_Rectangle do
               R.Set_XY_Width_Height (10.0, 8.0, 30.0, 20.0);
               case Field is
                  when 0      => null;
                  when 1      => R.Set_X (Value);
                  when 2      => R.Set_Y (Value);
                  when 3      => R.Set_Width (Value);
                  when others => R.Set_Height (Value);
               end case;
            end return;
         when Rectangle_Affine =>
            return R : Ks_Rectangle_Affine do
               R.Set_Center_Lengths_Rotation_Skew
                 (32.0, 24.0, 30.0, 16.0, 0.2, 0.0);
               case Field is
                  when 0      => null;
                  when 1      => R.Set_Center_X (Value);
                  when 2      => R.Set_Center_Y (Value);
                  when 3      => R.Set_Side_X_Length (Value);
                  when 4      => R.Set_Side_Y_Length (Value);
                  when 5      => R.Set_Rotation (Value);
                  when others => R.Set_Skew (Value);
               end case;
            end return;
         when Circle =>
            return R : Ks_Circle do
               R.Set_Center_Radius (32.0, 24.0, 15.0);
               case Field is
                  when 0      => null;
                  when 1      => R.Set_Center_X (Value);
                  when 2      => R.Set_Center_Y (Value);
                  when others => R.Set_Radius (Value);
               end case;
            end return;
         when Ellipse =>
            return R : Ks_Ellipse do
               R.Set_Center_XY_Radius_XY_Rotation (32.0, 24.0, 20.0, 12.0,
                                                   0.3);
               case Field is
                  when 0      => null;
                  when 1      => R.Set_Center_X (Value);
                  when 2      => R.Set_Center_Y (Value);
                  when 3      => R.Set_Radius_X (Value);
                  when 4      => R.Set_Radius_Y (Value);
                  when others => R.Set_Rotation (Value);
               end case;
            end return;
         when Polygon =>
            return R : Ks_Polygon do
               R.Add_Vertex (10.0, 10.0);
               R.Add_Vertex (50.0, 12.0);
               R.Add_Vertex (30.0, 40.0);
               case Field is
                  when 0      => null;
                  when 1      => R.Set_Vertex (0, Value, 10.0);
                  when 2      => R.Set_Vertex (0, 10.0, Value);
                  when 3      => R.Set_Vertex (2, Value, 40.0);
                  when others => R.Set_Vertex (2, 30.0, Value);
               end case;
            end return;
         when Annulus_Section =>
            return R : Ks_Circular_Annulus_Section do
               R.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
                 (32.0, 24.0, 10.0, 0.0, 5.0, 1.8);
               case Field is
                  when 0      => null;
                  when 1      => R.Set_Center_X (Value);
                  when 2      => R.Set_Center_Y (Value);
                  when 3      => R.Set_Radius (Value);
                  when 4      => R.Set_Radial_Scale (Value);
                  when 5      => R.Set_Angle_Start (Value);
                  when others => R.Set_Angle_Span (Value);
               end case;
            end return;
      end case;
   end Region_With;

   Line_Fields    : constant String := "X,Y,Rotation";
   Segment_Fields : constant String := "StartX,StartY,EndX,EndY";
   Circle_Fields  : constant String := "CenterX,CenterY,Radius";
   Ellipse_Fields : constant String :=
     "CenterX,CenterY,RadiusX,RadiusY,Rotation";
   Arc_Fields     : constant String :=
     "CenterX,CenterY,Radius,AngleStart,AngleSpan";

   function Line_With (Field : Natural; Value : Real) return Ks_Line is
   begin
      return L : Ks_Line do
         L.Set_XY_Rotation (32.0, 24.0, 0.5);
         case Field is
            when 0      => null;
            when 1      => L.Set_X (Value);
            when 2      => L.Set_Y (Value);
            when others => L.Set_Rotation (Value);
         end case;
      end return;
   end Line_With;

   function Line_B_With (Field : Natural; Value : Real) return Ks_Line is
   begin
      return L : Ks_Line := Line_With (Field, Value) do
         if Field /= 3 then
            L.Set_Rotation (2.0);
         end if;
      end return;
   end Line_B_With;
   --  A second line that crosses the first one.

   function Segment_With
     (Field : Natural; Value : Real) return Ks_Line_Segment is
   begin
      return S : Ks_Line_Segment do
         S.Set_Start_End (10.0, 10.0, 50.0, 30.0);
         case Field is
            when 0      => null;
            when 1      => S.Set_Start_X (Value);
            when 2      => S.Set_Start_Y (Value);
            when 3      => S.Set_End_X (Value);
            when others => S.Set_End_Y (Value);
         end case;
      end return;
   end Segment_With;

   function Segment_B_With
     (Field : Natural; Value : Real) return Ks_Line_Segment is
   begin
      return S : Ks_Line_Segment do
         S.Set_Start_End (10.0, 40.0, 50.0, 5.0);
         case Field is
            when 0      => null;
            when 1      => S.Set_Start_X (Value);
            when 2      => S.Set_Start_Y (Value);
            when 3      => S.Set_End_X (Value);
            when others => S.Set_End_Y (Value);
         end case;
      end return;
   end Segment_B_With;

   function Circle_With (Field : Natural; Value : Real) return Ks_Circle is
     (Ks_Circle (Region_With (Circle, Field, Value)));

   function Circle_B_With (Field : Natural; Value : Real) return Ks_Circle
   is
   begin
      return C : Ks_Circle := Circle_With (Field, Value) do
         if Field /= 1 then
            C.Set_Center_X (40.0);
         end if;
      end return;
   end Circle_B_With;

   function Ellipse_With (Field : Natural; Value : Real) return Ks_Ellipse is
     (Ks_Ellipse (Region_With (Ellipse, Field, Value)));

   function Arc_With
     (Field : Natural; Value : Real) return Ks_Circular_Arc is
   begin
      return A : Ks_Circular_Arc do
         A.Set_Center_Radius_Angle_Start_Angle_Span
           (0.7 * 64.0, 0.6 * 48.0, 0.15 * 48.0, 0.0, 2.0 * Pi);
         case Field is
            when 0      => null;
            when 1      => A.Set_Center_X (Value);
            when 2      => A.Set_Center_Y (Value);
            when 3      => A.Set_Radius (Value);
            when 4      => A.Set_Angle_Start (Value);
            when others => A.Set_Angle_Span (Value);
         end case;
      end return;
   end Arc_With;

   ---------------------------------------------------------------------
   --  The tool sweeps
   ---------------------------------------------------------------------

   generic
      type Tool_Type is new Ks_Tool with private;
      Tool_Name : String;
      with procedure Prepare (Tool : in out Tool_Type);
      --  A valid tool on Small.
      with procedure Use_Results (Tool : Tool_Type; Call : String) is null;
      --  Reads the results after each run (with its own calls to Try).
   package Sweeps is

      procedure Run_Case (Tool : in out Tool_Type; Call : String);

      procedure Default_Run;
      --  The prepared tool.

      procedure Images
        (Names : String;
         Set   : not null access procedure
           (Tool : in out Tool_Type; Field : Positive;
            Image : Ks_Image_8_Grey));
      --  Each image of Names set in turn to each Image_Case.

      procedure Reals
        (Names : String;
         Set   : not null access procedure
           (Tool : in out Tool_Type; Field : Positive; Value : Real));

      procedure Integers
        (Names  : String;
         Set    : not null access procedure
           (Tool : in out Tool_Type; Field : Positive; Value : Integer);
         Values : Integer_List := Bad_Integers);

      procedure Strings
        (Names : String;
         Set   : not null access procedure
           (Tool : in out Tool_Type; Field : Positive; Value : String));

      procedure Regions
        (Name  : String;
         Kinds : Region_Kinds;
         Set   : not null access procedure
           (Tool : in out Tool_Type; Region : Ks_Region'Class));
      --  The region set to each kind of Kinds, then with each property
      --  set in turn to each bad value, then with bad space names.

   end Sweeps;

   package body Sweeps is

      procedure Run_Case (Tool : in out Tool_Type; Call : String) is
      begin
         Run_Tool (Tool, Call);
         Use_Results (Tool, Call);
      end Run_Case;

      procedure Default_Run is
         Tool : Tool_Type;
      begin
         Area_Calls := Area_Calls + 1;
         Prepare (Tool);
         Run_Case (Tool, Tool_Name & " (valid inputs)");
         if Tool.Run_Status.Result = Error then
            Ada.Text_IO.Put_Line
              ("note: " & Tool_Name & " fails with its valid inputs: "
               & Tool.Run_Status.Message);
         end if;
      exception
         when Occurrence : others =>
            Note (Tool_Name & " (preparing it)", Occurrence);
      end Default_Run;

      procedure Images
        (Names : String;
         Set   : not null access procedure
           (Tool : in out Tool_Type; Field : Positive;
            Image : Ks_Image_8_Grey)) is
      begin
         for Field in 1 .. Field_Count (Names) loop
            for Kind in Image_Case loop
               declare
                  Call : constant String :=
                    Tool_Name & "." & Field_Name (Names, Field) & " = "
                    & Kind'Image;
                  Tool : Tool_Type;
               begin
                  Area_Calls := Area_Calls + 1;
                  Prepare (Tool);
                  Set (Tool, Field, Test_Image (Kind));
                  Run_Case (Tool, Call);
               exception
                  when Occurrence : others =>
                     Note (Call & " (setting it)", Occurrence);
               end;
            end loop;
         end loop;
      end Images;

      procedure Reals
        (Names : String;
         Set   : not null access procedure
           (Tool : in out Tool_Type; Field : Positive; Value : Real)) is
      begin
         for Field in 1 .. Field_Count (Names) loop
            for Value of Bad_Reals loop
               declare
                  Call : constant String :=
                    Tool_Name & "." & Field_Name (Names, Field) & " = "
                    & Image (Value);
                  Tool : Tool_Type;
               begin
                  Area_Calls := Area_Calls + 1;
                  Prepare (Tool);
                  Set (Tool, Field, Value);
                  Run_Case (Tool, Call);
               exception
                  when Occurrence : others =>
                     Note (Call & " (setting it)", Occurrence);
               end;
            end loop;
         end loop;
      end Reals;

      procedure Integers
        (Names  : String;
         Set    : not null access procedure
           (Tool : in out Tool_Type; Field : Positive; Value : Integer);
         Values : Integer_List := Bad_Integers) is
      begin
         for Field in 1 .. Field_Count (Names) loop
            for Value of Values loop
               declare
                  Call : constant String :=
                    Tool_Name & "." & Field_Name (Names, Field) & " = "
                    & Image (Value);
                  Tool : Tool_Type;
               begin
                  Area_Calls := Area_Calls + 1;
                  Prepare (Tool);
                  Set (Tool, Field, Value);
                  Run_Case (Tool, Call);
               exception
                  when Occurrence : others =>
                     Note (Call & " (setting it)", Occurrence);
               end;
            end loop;
         end loop;
      end Integers;

      procedure Strings
        (Names : String;
         Set   : not null access procedure
           (Tool : in out Tool_Type; Field : Positive; Value : String)) is
      begin
         for Field in 1 .. Field_Count (Names) loop
            for Index in 1 .. Bad_Name_Count loop
               declare
                  Call : constant String :=
                    Tool_Name & "." & Field_Name (Names, Field)
                    & " = bad name" & Index'Image;
                  Tool : Tool_Type;
               begin
                  Area_Calls := Area_Calls + 1;
                  Prepare (Tool);
                  Set (Tool, Field, Bad_Name (Index));
                  Run_Case (Tool, Call);
               exception
                  when Occurrence : others =>
                     Note (Call & " (setting it)", Occurrence);
               end;
            end loop;
         end loop;
      end Strings;

      procedure Regions
        (Name  : String;
         Kinds : Region_Kinds;
         Set   : not null access procedure
           (Tool : in out Tool_Type; Region : Ks_Region'Class))
      is
         procedure One (Kind : Region_Kind; Field : Natural; Value : Real)
         is
            Call : constant String :=
              Tool_Name & "." & Name & " = " & Kind'Image
              & (if Field = 0 then ""
                 else " with " & Field_Name (Region_Fields (Kind), Field)
                      & " = " & Image (Value));
            Tool : Tool_Type;
         begin
            Area_Calls := Area_Calls + 1;
            Prepare (Tool);
            Set (Tool, Region_With (Kind, Field, Value));
            Run_Case (Tool, Call);
         exception
            when Occurrence : others =>
               Note (Call & " (setting it)", Occurrence);
         end One;
      begin
         for Kind in Region_Kind loop
            if Kinds (Kind) then
               One (Kind, 0, 0.0);
               for Field in 1 .. Field_Count (Region_Fields (Kind)) loop
                  for Value of Bad_Reals loop
                     One (Kind, Field, Value);
                  end loop;
               end loop;
               for Index in 1 .. Bad_Name_Count loop
                  declare
                     Call : constant String :=
                       Tool_Name & "." & Name & " = " & Kind'Image
                       & " in space bad name" & Index'Image;
                     Tool   : Tool_Type;
                     Region : Ks_Region'Class := Region_With (Kind, 0, 0.0);
                  begin
                     Area_Calls := Area_Calls + 1;
                     Prepare (Tool);
                     Region.Set_Selected_Space_Name (Bad_Name (Index));
                     Set (Tool, Region);
                     Run_Case (Tool, Call);
                  exception
                     when Occurrence : others =>
                        Note (Call & " (setting it)", Occurrence);
                  end;
               end loop;
            end if;
         end loop;
      end Regions;

   end Sweeps;

   ---------------------------------------------------------------------
   --  AMV.Misc
   ---------------------------------------------------------------------

   procedure Sweep_Misc is
      procedure Deg (A : Real_List) is
      begin
         Consume (AMV.Misc.Deg_To_Rad (A (1)));
      end Deg;
      procedure Rad (A : Real_List) is
      begin
         Consume (AMV.Misc.Rad_To_Deg (A (1)));
      end Rad;
      procedure Norm (A : Real_List) is
      begin
         Consume (AMV.Misc.Norm_Angle (A (1)));
      end Norm;
      procedure Norm_Pi (A : Real_List) is
      begin
         Consume (AMV.Misc.Norm_Angle_Pi (A (1)));
      end Norm_Pi;
      procedure Difference (A : Real_List) is
      begin
         Consume (AMV.Misc.Angle_Difference (A (1), A (2)));
      end Difference;
      procedure Hypot (A : Real_List) is
      begin
         Consume (AMV.Misc.Hypot (A (1), A (2)));
      end Hypot;
   begin
      Begin_Area ("AMV.Misc");
      Composite ("Deg_To_Rad", [1.0], Deg'Access);
      Composite ("Rad_To_Deg", [1.0], Rad'Access);
      Composite ("Norm_Angle", [1.0], Norm'Access);
      Composite ("Norm_Angle_Pi", [1.0], Norm_Pi'Access);
      Composite ("Angle_Difference", [1.0, 2.0], Difference'Access);
      Composite ("Hypot", [3.0, 4.0], Hypot'Access);
      End_Area;
   end Sweep_Misc;

   ---------------------------------------------------------------------
   --  AMV.Transforms
   ---------------------------------------------------------------------

   procedure Use_Transform (Call : String; T : Ks_Transform_2D_Linear) is
      procedure Map_P is
         X, Y : Real;
      begin
         T.Map_Point (1.0, 2.0, X, Y);
         Consume (X);
         Consume (Y);
      end Map_P;
      procedure Map_V is
         X, Y : Real;
      begin
         T.Map_Vector (1.0, 2.0, X, Y);
         Consume (X);
         Consume (Y);
      end Map_V;
      procedure Map_A is
      begin
         Consume (T.Map_Angle (0.3));
      end Map_A;
      procedure Inv is
      begin
         Use_Nothing (T.Invert);
      end Inv;
      procedure Comp is
      begin
         Use_Nothing (T.Compose (T));
      end Comp;
      procedure Getters is
      begin
         Consume (T.Rotation);
      end Getters;
      procedure Getters_2 is
      begin
         Consume (T.Skew);
         Consume (T.Scaling);
         Consume (T.Aspect);
      end Getters_2;
      procedure Getters_3 is
      begin
         Consume (T.Scaling_X);
         Consume (T.Scaling_Y);
         Consume (T.Rotation_X);
         Consume (T.Rotation_Y);
      end Getters_3;
      procedure Getters_4 is
      begin
         Consume (T.Translation_X);
         Consume (T.Translation_Y);
      end Getters_4;
      procedure Composite_Getters is
         S, A, R, K, X, Y : Real;
      begin
         T.Get_Scaling_Aspect_Rotation_Skew_Translation (S, A, R, K, X, Y);
         T.Get_Scalings_Rotations_Translation (S, A, R, K, X, Y);
         T.Get_Matrix_Elements_Translation (S, A, R, K, X, Y);
         Consume (S + A + R + K + X + Y);
      end Composite_Getters;
      procedure Element is
      begin
         Consume (T.Get_Matrix_Element (1, 1));
      end Element;
      procedure Det is
      begin
         Consume (T.Matrix_Determinant);
      end Det;
      procedure Area is
      begin
         Consume (T.Map_Area (2.0));
      end Area;
      procedure Tests is
      begin
         Consume (T.Identity);
      end Tests;
      procedure Tests_2 is
      begin
         Consume (T.Matrix_Identity);
      end Tests_2;
      procedure Tests_3 is
      begin
         Consume (T.Singular (0.0));
      end Tests_3;
      procedure Tests_4 is
      begin
         Consume (T.Is_Similarity);
         Consume (T.Is_Axis_Aligned);
      end Tests_4;
      procedure Set_R is
         U : Ks_Transform_2D_Linear := T;
      begin
         U.Set_Rotation (0.5);
         U.Set_Scaling (2.0);
         U.Set_Skew (0.1);
         U.Set_Aspect (2.0);
      end Set_R;
      procedure On_Image is
         I : Ks_Image_8_Grey := Small.Copy (Share_Pixels);
      begin
         I.Set_Pixel_From_Root_Transform (T);
         Use_Nothing (I.Get_Transform ("#", "@"));
      end On_Image;
      procedure In_Tree is
         Tree : CS.Ks_Coordinate_Space_Tree;
      begin
         Tree.Add_Space ("@", "A", T);
         Use_Nothing (Tree.Get_Transform ("@\A", "@"));
         Use_Nothing (Tree.Get_Transform ("@", "@\A"));
         Tree.Change_Transform ("@\A", T);
      end In_Tree;
      procedure Map_Shapes is
         C : constant Ks_Circle := Circle_With (0, 0.0);
      begin
         Consume (C.Map (T).Selected_Space_Name);
      end Map_Shapes;
      procedure Map_Shapes_2 is
         P : constant Ks_Polygon := Ks_Polygon (Region_With (Polygon, 0, 0.0));
      begin
         Consume (P.Map (T).Selected_Space_Name);
      end Map_Shapes_2;
      procedure Map_Shapes_3 is
         R : constant Ks_Rectangle :=
           Ks_Rectangle (Region_With (Rectangle, 0, 0.0));
      begin
         Consume (R.Map (T).Selected_Space_Name);
      end Map_Shapes_3;
   begin
      Try (Call & " / Map_Point", Map_P'Access);
      Try (Call & " / Map_Vector", Map_V'Access);
      Try (Call & " / Map_Angle", Map_A'Access);
      Try (Call & " / Invert", Inv'Access);
      Try (Call & " / Compose", Comp'Access);
      Try (Call & " / Rotation", Getters'Access);
      Try (Call & " / Skew, Scaling, Aspect", Getters_2'Access);
      Try (Call & " / Scaling_X .. Rotation_Y", Getters_3'Access);
      Try (Call & " / Translation", Getters_4'Access);
      Try (Call & " / composite getters", Composite_Getters'Access);
      Try (Call & " / Get_Matrix_Element", Element'Access);
      Try (Call & " / Matrix_Determinant", Det'Access);
      Try (Call & " / Map_Area", Area'Access);
      Try (Call & " / Identity", Tests'Access);
      Try (Call & " / Matrix_Identity", Tests_2'Access);
      Try (Call & " / Singular", Tests_3'Access);
      Try (Call & " / Is_Similarity", Tests_4'Access);
      Try (Call & " / decomposed setters", Set_R'Access);
      Try (Call & " / Set_Pixel_From_Root_Transform", On_Image'Access);
      Try (Call & " / Add_Space", In_Tree'Access);
      Try (Call & " / Map (circle)", Map_Shapes'Access);
      Try (Call & " / Map (polygon)", Map_Shapes_2'Access);
      Try (Call & " / Map (rectangle)", Map_Shapes_3'Access);
   end Use_Transform;

   procedure Sweep_Transforms is
      procedure Created (A : Real_List) is
      begin
         Use_Transform ("Create", Create (A (1), A (2), A (3), A (4), A (5),
                                          A (6)));
      end Created;
      procedure Created_2 (A : Real_List) is
      begin
         Use_Transform
           ("Create_Scaling_Aspect_Rotation_Skew_Translation",
            Create_Scaling_Aspect_Rotation_Skew_Translation
              (A (1), A (2), A (3), A (4), A (5), A (6)));
      end Created_2;
      procedure Created_3 (A : Real_List) is
      begin
         Use_Transform ("Create_Rigid", Create_Rigid (A (1), A (2), A (3)));
      end Created_3;
      procedure Created_4 (A : Real_List) is
      begin
         Use_Transform ("Create_Similarity",
                        Create_Similarity (A (1), A (2), A (3), A (4)));
      end Created_4;
      procedure Set_Whole (A : Real_List) is
         T : Ks_Transform_2D_Linear;
      begin
         T.Set_Scaling_Aspect_Rotation_Skew_Translation
           (A (1), A (2), A (3), A (4), A (5), A (6));
         Use_Nothing (T.Invert);
      end Set_Whole;
      procedure Set_Whole_2 (A : Real_List) is
         T : Ks_Transform_2D_Linear;
      begin
         T.Set_Scalings_Rotations_Translation
           (A (1), A (2), A (3), A (4), A (5), A (6));
         Use_Nothing (T.Invert);
      end Set_Whole_2;
      procedure Set_Whole_3 (A : Real_List) is
         T : Ks_Transform_2D_Linear;
      begin
         T.Set_Matrix_Elements_Translation
           (A (1), A (2), A (3), A (4), A (5), A (6));
         Use_Nothing (T.Compose (Identity));
      end Set_Whole_3;
      procedure Set_One (Field : Positive; Value : Real) is
         T : Ks_Transform_2D_Linear :=
           Create_Similarity (2.0, 0.3, 1.0, 2.0);
      begin
         case Field is
            when 1 => T.Set_Translation_X (Value);
            when 2 => T.Set_Translation_Y (Value);
            when 3 => T.Set_Rotation (Value);
            when 4 => T.Set_Skew (Value);
            when 5 => T.Set_Scaling (Value);
            when 6 => T.Set_Aspect (Value);
            when 7 => T.Set_Scaling_X (Value);
            when 8 => T.Set_Scaling_Y (Value);
            when 9 => T.Set_Rotation_X (Value);
            when 10 => T.Set_Rotation_Y (Value);
            when others => T.Set_Matrix_Element (1, 0, Value);
         end case;
         Use_Nothing (T.Invert);
      end Set_One;
      Valid : constant Ks_Transform_2D_Linear :=
        Create_Similarity (2.0, 0.3, 1.0, 2.0);
      procedure Map_P (A : Real_List) is
         X, Y : Real;
      begin
         Valid.Map_Point (A (1), A (2), X, Y);
         Valid.Map_Vector (A (1), A (2), X, Y);
         Consume (X + Y);
      end Map_P;
      procedure Map_A (A : Real_List) is
      begin
         Consume (Valid.Map_Angle (A (1)));
      end Map_A;
      procedure Map_Area (A : Real_List) is
      begin
         Consume (Valid.Map_Area (A (1)));
      end Map_Area;
      procedure Tolerances (A : Real_List) is
      begin
         Consume (Valid.Identity (A (1)));
      end Tolerances;
      procedure Tolerances_2 (A : Real_List) is
      begin
         Consume (Valid.Matrix_Identity (A (1)));
      end Tolerances_2;
      procedure Tolerances_3 (A : Real_List) is
      begin
         Consume (Valid.Singular (A (1)));
      end Tolerances_3;
      procedure Tolerances_4 (A : Real_List) is
      begin
         Consume (Valid.Is_Similarity (A (1)));
      end Tolerances_4;
      procedure Tolerances_5 (A : Real_List) is
      begin
         Consume (Valid.Is_Axis_Aligned (A (1)));
      end Tolerances_5;
   begin
      Begin_Area ("AMV.Transforms");
      Composite ("Create", [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], Created'Access);
      Composite ("Create_Scaling_Aspect_Rotation_Skew_Translation",
                 [1.0, 1.0, 0.0, 0.0, 0.0, 0.0], Created_2'Access);
      Composite ("Create_Rigid", [0.3, 1.0, 2.0], Created_3'Access);
      Composite ("Create_Similarity", [2.0, 0.3, 1.0, 2.0],
                 Created_4'Access);
      Composite ("Set_Scaling_Aspect_Rotation_Skew_Translation",
                 [1.0, 1.0, 0.0, 0.0, 0.0, 0.0], Set_Whole'Access);
      Composite ("Set_Scalings_Rotations_Translation",
                 [1.0, 1.0, 0.0, 0.0, 0.0, 0.0], Set_Whole_2'Access);
      Composite ("Set_Matrix_Elements_Translation",
                 [1.0, 0.0, 0.0, 1.0, 0.0, 0.0], Set_Whole_3'Access);
      Field_Sweep ("decomposed setter", 11, Set_One'Access);
      Composite ("Map_Point, Map_Vector", [1.0, 2.0], Map_P'Access);
      Composite ("Map_Angle", [0.3], Map_A'Access);
      Composite ("Map_Area", [2.0], Map_Area'Access);
      Composite ("Identity (tolerance)", [1.0E-12], Tolerances'Access);
      Composite ("Matrix_Identity", [1.0E-12], Tolerances_2'Access);
      Composite ("Singular", [0.0], Tolerances_3'Access);
      Composite ("Is_Similarity", [1.0E-9], Tolerances_4'Access);
      Composite ("Is_Axis_Aligned", [1.0E-9], Tolerances_5'Access);
      for Row of Bad_Integers loop
         for Column of Bad_Integers loop
            declare
               procedure Get is
               begin
                  Consume (Valid.Get_Matrix_Element (Row, Column));
               end Get;
               procedure Set is
                  T : Ks_Transform_2D_Linear := Valid;
               begin
                  T.Set_Matrix_Element (Row, Column, 1.0);
               end Set;
            begin
               Try ("Get_Matrix_Element (" & Image (Row) & ", "
                    & Image (Column) & ")", Get'Access);
               Try ("Set_Matrix_Element (" & Image (Row) & ", "
                    & Image (Column) & ")", Set'Access);
            end;
         end loop;
      end loop;
      End_Area;
   end Sweep_Transforms;

   ---------------------------------------------------------------------
   --  AMV.Images
   ---------------------------------------------------------------------

   procedure Sweep_Images is
      type Size is record
         Width, Height : Positive;
      end record;
      type Size_List is array (Positive range <>) of Size;
      Sizes : constant Size_List :=
        [(1, 1), (Positive'Last, 2), (2, Positive'Last), (65_536, 65_536),
         (Positive'Last, Positive'Last)];
      Colour   : constant Ks_Image_24_Planar_Color := Create (8, 6, 1, 2, 3);
      Image_16 : constant Ks_Image_16_Grey := Create (8, 6, 1000);
   begin
      Begin_Area ("AMV.Images");
      for S of Sizes loop
         declare
            Text : constant String :=
              " (" & Image (S.Width) & ", " & Image (S.Height) & ")";
            procedure Create_8 is
            begin
               Consume (Ks_Image_8_Grey'(Create (S.Width, S.Height)).Width);
            end Create_8;
            procedure Create_16 is
            begin
               Consume (Ks_Image_16_Grey'(Create (S.Width, S.Height)).Width);
            end Create_16;
            procedure Create_24 is
            begin
               Consume (Ks_Image_24_Planar_Color'
                          (Create (S.Width, S.Height)).Width);
            end Create_24;
            procedure Allocate_8 is
               I : Ks_Image_8_Grey;
            begin
               I.Allocate (S.Width, S.Height);
            end Allocate_8;
            procedure Allocate_16 is
               I : Ks_Image_16_Grey;
            begin
               I.Allocate (S.Width, S.Height);
            end Allocate_16;
            procedure Allocate_24 is
               I : Ks_Image_24_Planar_Color;
            begin
               I.Allocate (S.Width, S.Height);
            end Allocate_24;
         begin
            Try ("Create (8-bit)" & Text, Create_8'Access);
            Try ("Create (16-bit)" & Text, Create_16'Access);
            Try ("Create (colour)" & Text, Create_24'Access);
            Try ("Allocate (8-bit)" & Text, Allocate_8'Access);
            Try ("Allocate (16-bit)" & Text, Allocate_16'Access);
            Try ("Allocate (colour)" & Text, Allocate_24'Access);
         end;
      end loop;

      for X of Bad_Indices loop
         for Y of Bad_Indices loop
            declare
               Text : constant String :=
                 " (" & Image (X) & ", " & Image (Y) & ")";
               procedure Get_8 is
               begin
                  Consume (Integer (Small.Get_Pixel (X, Y)));
               end Get_8;
               procedure Set_8 is
                  I : Ks_Image_8_Grey := Small.Copy;
               begin
                  I.Set_Pixel (X, Y, 7);
               end Set_8;
               procedure Get_None is
               begin
                  Consume (Integer (No_Image.Get_Pixel (X, Y)));
               end Get_None;
               procedure Get_16 is
               begin
                  Consume (Integer (Image_16.Get_Pixel (X, Y)));
               end Get_16;
               procedure Set_16 is
                  I : Ks_Image_16_Grey := Image_16.Copy;
               begin
                  I.Set_Pixel (X, Y, 7);
               end Set_16;
               procedure Get_24 is
                  R, G, B : Grey_8;
               begin
                  Colour.Get_Pixel (X, Y, R, G, B);
                  Consume (Integer (R));
               end Get_24;
               procedure Set_24 is
                  I : Ks_Image_24_Planar_Color := Colour.Copy;
               begin
                  I.Set_Pixel (X, Y, 1, 2, 3);
               end Set_24;
            begin
               Try ("Get_Pixel (8-bit)" & Text, Get_8'Access, True);
               Try ("Set_Pixel (8-bit)" & Text, Set_8'Access, True);
               Try ("Get_Pixel (unallocated)" & Text, Get_None'Access, True);
               Try ("Get_Pixel (16-bit)" & Text, Get_16'Access, True);
               Try ("Set_Pixel (16-bit)" & Text, Set_16'Access, True);
               Try ("Get_Pixel (colour)" & Text, Get_24'Access, True);
               Try ("Set_Pixel (colour)" & Text, Set_24'Access, True);
            end;
         end loop;
      end loop;

      for Y of Bad_Indices loop
         for Length of Integer_List'[0, 63, 64, 65] loop
            declare
               Text : constant String :=
                 " (row " & Image (Y) & ", length" & Length'Image & ")";
               procedure Get is
                  Row : Grey_8_Row (1 .. Length);
               begin
                  Small.Get_Row (Y, Row);
               end Get;
               procedure Set is
                  I   : Ks_Image_8_Grey := Small.Copy;
                  Row : constant Grey_8_Row (5 .. Length + 4) := [others => 1];
               begin
                  I.Set_Row (Y, Row);
               end Set;
            begin
               Try ("Get_Row" & Text, Get'Access, True);
               Try ("Set_Row" & Text, Set'Access, True);
            end;
         end loop;
      end loop;

      declare
         procedure Empty_Matrix is
            M : constant Grey_8_Matrix (1 .. 0, 1 .. 5) := [others => [others => 0]];
         begin
            Consume (From_Matrix (M).Width);
         end Empty_Matrix;
         procedure Empty_Matrix_2 is
            M : constant Grey_8_Matrix (3 .. 4, 7 .. 6) := [others => [others => 0]];
         begin
            Consume (From_Matrix (M).Width);
         end Empty_Matrix_2;
         procedure Odd_Bounds is
            M : constant Grey_8_Matrix
              (Natural'Last - 1 .. Natural'Last, Natural'Last .. Natural'Last) :=
              [others => [others => 9]];
         begin
            Consume (From_Matrix (M).Height);
         end Odd_Bounds;
         procedure To_Matrix_None is
         begin
            Consume (To_Matrix (No_Image)'Length (1));
         end To_Matrix_None;
         procedure Copies is
         begin
            Consume (No_Image.Copy (Copy_Pixels).Width);
            Consume (No_Image.Copy (Share_Pixels).Width);
            Consume (No_Image.Copy (No_Pixels).Width);
            Consume (Small.Copy (No_Pixels).Width);
         end Copies;
         procedure Fill_None is
            I : Ks_Image_8_Grey;
         begin
            I.Fill (3);
         end Fill_None;
         procedure Plane_Of_None is
            C : Ks_Image_24_Planar_Color;
         begin
            Consume (C.Get_Plane (Green).Width);
         end Plane_Of_None;
         procedure Set_Plane_Mismatch is
            C : Ks_Image_24_Planar_Color := Colour.Copy;
         begin
            C.Set_Plane (Red, Small);
         end Set_Plane_Mismatch;
         procedure Set_Plane_None is
            C : Ks_Image_24_Planar_Color := Colour.Copy;
         begin
            C.Set_Plane (Blue, No_Image);
         end Set_Plane_None;
         procedure Set_Plane_Of_None is
            C : Ks_Image_24_Planar_Color;
         begin
            C.Set_Plane (Blue, Small);
         end Set_Plane_Of_None;
         procedure Singular_Root is
            I : Ks_Image_8_Grey := Small.Copy (Share_Pixels);
         begin
            I.Set_Pixel_From_Root_Transform (Create (0.0, 0.0, 0.0, 0.0, 0.0,
                                                     0.0));
         end Singular_Root;
         procedure Huge_Root is
            I : Ks_Image_8_Grey := Small.Copy (Share_Pixels);
         begin
            I.Set_Pixel_From_Root_Transform
              (Create (1.0E150, 1.0E150, 1.0E150, 1.0E150 + 1.0E135, 1.0E150,
                       -1.0E150));
            Use_Nothing (I.Get_Transform ("@", "#"));
         end Huge_Root;
         procedure Names (Name : String) is
            I : Ks_Image_8_Grey := Small.Copy (Share_Pixels);
         begin
            I.Set_Selected_Space_Name (Name);
         end Names;
         procedure Names_2 (Name : String) is
         begin
            Use_Nothing (Small.Get_Transform (Name, "#"));
         end Names_2;
         procedure Names_3 (Name : String) is
         begin
            Use_Nothing (Small.Get_Transform ("#", Name));
         end Names_3;
         procedure Names_4 (Name : String) is
         begin
            Consume (Small.Resolve_Space_Name (Name));
         end Names_4;
         procedure Names_5 (Name : String) is
            I : aliased Ks_Image_8_Grey := Small.Copy (Share_Pixels);
         begin
            I.Coordinate_Space_Tree.Add_Space ("@", Name, Identity);
         end Names_5;
      begin
         Try ("From_Matrix (empty rows)", Empty_Matrix'Access);
         Try ("From_Matrix (empty columns)", Empty_Matrix_2'Access);
         Try ("From_Matrix (bounds at Natural'Last)", Odd_Bounds'Access);
         Try ("To_Matrix (unallocated)", To_Matrix_None'Access);
         Try ("Copy (unallocated)", Copies'Access);
         Try ("Fill (unallocated)", Fill_None'Access);
         Try ("Get_Plane (unallocated)", Plane_Of_None'Access);
         Try ("Set_Plane (size mismatch)", Set_Plane_Mismatch'Access);
         Try ("Set_Plane (unallocated pixels)", Set_Plane_None'Access);
         Try ("Set_Plane (unallocated image)", Set_Plane_Of_None'Access);
         Try ("Set_Pixel_From_Root_Transform (singular)",
              Singular_Root'Access);
         Try ("Set_Pixel_From_Root_Transform (huge, nearly singular)",
              Huge_Root'Access);
         Name_Sweep ("Set_Selected_Space_Name", Names'Access);
         Name_Sweep ("Get_Transform (to)", Names_2'Access);
         Name_Sweep ("Get_Transform (from)", Names_3'Access);
         Name_Sweep ("Resolve_Space_Name", Names_4'Access);
         Name_Sweep ("Coordinate_Space_Tree.Add_Space", Names_5'Access);
      end;
      End_Area;
   end Sweep_Images;

   ---------------------------------------------------------------------
   --  AMV.Coordinate_Spaces
   ---------------------------------------------------------------------

   procedure Sweep_Coordinate_Spaces is
      Tree : CS.Ks_Coordinate_Space_Tree;
      procedure Add (Name : String) is
         T : CS.Ks_Coordinate_Space_Tree := Tree;
      begin
         T.Add_Space ("@", Name, Identity);
      end Add;
      procedure Add_Under (Name : String) is
         T : CS.Ks_Coordinate_Space_Tree := Tree;
      begin
         T.Add_Space (Name, "B", Identity);
      end Add_Under;
      procedure Change (Name : String) is
         T : CS.Ks_Coordinate_Space_Tree := Tree;
      begin
         T.Change_Transform (Name, Identity);
      end Change;
      procedure Delete (Name : String) is
         T : CS.Ks_Coordinate_Space_Tree := Tree;
      begin
         T.Delete_Subtree (Name);
      end Delete;
      procedure Get (Name : String) is
      begin
         Use_Nothing (Tree.Get_Transform (Name, "@"));
         Use_Nothing (Tree.Get_Transform ("@", Name));
      end Get;
      procedure Parent (Name : String) is
      begin
         Consume (Tree.Parent_Name (Name, CS.Partial));
      end Parent;
      procedure Children (Name : String) is
      begin
         Consume (CS.Count (Tree.Child_Names (Name)));
         Consume (CS.Count (Tree.All_Child_Names (Name, CS.None, False)));
      end Children;
      procedure Verify (Name : String) is
         Found : Ada.Strings.Unbounded.Unbounded_String;
      begin
         Consume (Tree.Verify_Name (Name, CS.Full, Found));
         Consume (Tree.Space_Exists (Name));
         Consume (Tree.Parent_From_Child_Transform (Name).Rotation);
      end Verify;
      procedure Full (Name : String) is
      begin
         Consume (CS.Full_Space_Name (Name, "B"));
         Consume (CS.Full_Space_Name ("@", Name));
      end Full;
      procedure Too_Many is
         T : CS.Ks_Coordinate_Space_Tree;
      begin
         for I in 1 .. 70 loop
            T.Add_Space ("@", "S" & Image (I), Identity);
         end loop;
      end Too_Many;
      procedure Index (Value : Integer) is
      begin
         Consume (Tree.Space_Name (Value));
      end Index;
      procedure Item (Value : Integer) is
      begin
         Consume (CS.Item (Tree.Child_Names ("@"), Value));
      end Item;
      procedure Delete_Root is
         T : CS.Ks_Coordinate_Space_Tree := Tree;
      begin
         T.Delete_Subtree ("@");
         T.Clear;
      end Delete_Root;
   begin
      Begin_Area ("AMV.Coordinate_Spaces");
      Tree.Add_Space ("@", "A", Create_Similarity (2.0, 0.3, 1.0, 1.0));
      Name_Sweep ("Add_Space (new name)", Add'Access);
      Name_Sweep ("Add_Space (parent name)", Add_Under'Access);
      Name_Sweep ("Change_Transform", Change'Access);
      Name_Sweep ("Delete_Subtree", Delete'Access);
      Name_Sweep ("Get_Transform", Get'Access);
      Name_Sweep ("Parent_Name", Parent'Access);
      Name_Sweep ("Child_Names", Children'Access);
      Name_Sweep ("Verify_Name", Verify'Access);
      Name_Sweep ("Full_Space_Name", Full'Access);
      Try ("Add_Space (beyond 64 spaces)", Too_Many'Access);
      Try ("Delete_Subtree (root)", Delete_Root'Access);
      Integer_Sweep ("Space_Name", Bad_Indices, Index'Access, True);
      Integer_Sweep ("String collection Item", Bad_Indices, Item'Access,
                     True);
      End_Area;
   end Sweep_Coordinate_Spaces;

   ---------------------------------------------------------------------
   --  AMV.Shapes
   ---------------------------------------------------------------------

   procedure Use_Region (Call : String; R : Ks_Region'Class) is
      procedure Area is
      begin
         Consume (R.Area);
      end Area;
      procedure Contains is
      begin
         Consume (R.Contains_Point (1.0, 2.0));
      end Contains;
      procedure Contains_Bad is
      begin
         Consume (R.Contains_Point (NaN, Inf));
      end Contains_Bad;
      procedure Contains_Huge is
      begin
         Consume (R.Contains_Point (1.0E150, -1.0E150));
      end Contains_Huge;
      procedure Slack is
      begin
         Consume (R.Boundary_Slack);
      end Slack;
      procedure Box is
         A, B, C, D : Real;
      begin
         R.Get_Bounding_Box (A, B, C, D);
         Consume (A + B + C + D);
      end Box;
      procedure Enclosing is
      begin
         Consume (Enclosing_Rectangle (R).Width);
      end Enclosing;
      procedure Map_Id is
      begin
         Consume (R.Map (Identity).Selected_Space_Name);
      end Map_Id;
      procedure Map_Big is
      begin
         Consume (R.Map (Create_Similarity (1.0E150, 0.3, 0.0, 0.0))
                    .Selected_Space_Name);
      end Map_Big;
      procedure Map_Flat is
      begin
         Consume (R.Map (Create (1.0, 0.0, 0.0, 0.0, 0.0, 0.0))
                    .Selected_Space_Name);
      end Map_Flat;
      procedure Rasterize is
      begin
         Consume (AMV.Regions.Rasterize (Small, R).Pixel_Count);
      end Rasterize;
      procedure Rasterize_None is
      begin
         Consume (AMV.Regions.Rasterize (No_Image, R).Pixel_Count);
      end Rasterize_None;
      procedure Rasterize_Scaled is
      begin
         Consume (AMV.Regions.Rasterize
                    (Test_Image (Pixel_From_Root_1E140), R).Pixel_Count);
         Consume (AMV.Regions.Rasterize
                    (Test_Image (Pixel_From_Root_1E_Minus_140), R)
                      .Pixel_Count);
      end Rasterize_Scaled;
   begin
      Try (Call & " / Area", Area'Access);
      Try (Call & " / Contains_Point", Contains'Access);
      Try (Call & " / Contains_Point (NaN, Inf)", Contains_Bad'Access);
      Try (Call & " / Contains_Point (huge)", Contains_Huge'Access);
      Try (Call & " / Boundary_Slack", Slack'Access);
      Try (Call & " / Get_Bounding_Box", Box'Access);
      Try (Call & " / Enclosing_Rectangle", Enclosing'Access);
      Try (Call & " / Map (identity)", Map_Id'Access);
      Try (Call & " / Map (scaling 1.0E150)", Map_Big'Access);
      Try (Call & " / Map (flattening)", Map_Flat'Access);
      Try (Call & " / Rasterize", Rasterize'Access);
      Try (Call & " / Rasterize (unallocated)", Rasterize_None'Access);
      Try (Call & " / Rasterize (scaled images)", Rasterize_Scaled'Access);
   end Use_Region;

   procedure Sweep_Shapes is
      procedure Region_Field (Kind : Region_Kind; Field : Positive;
                              Value : Real) is
         Call : constant String :=
           Kind'Image & "." & Field_Name (Region_Fields (Kind), Field)
           & " = " & Image (Value);
         procedure Action is
         begin
            Use_Region (Call, Region_With (Kind, Field, Value));
         end Action;
      begin
         Try (Call, Action'Access);
      end Region_Field;

      procedure Rectangle_1 (A : Real_List) is
         R : Ks_Rectangle;
      begin
         R.Set_XY_Width_Height (A (1), A (2), A (3), A (4));
         Use_Region ("Set_XY_Width_Height", R);
         Consume (R.Perimeter + R.Center_X + R.Center_Y);
      end Rectangle_1;
      procedure Rectangle_2 (A : Real_List) is
         R : Ks_Rectangle;
      begin
         R.Set_Center_Width_Height (A (1), A (2), A (3), A (4));
         Consume (R.Perimeter);
      end Rectangle_2;
      procedure Affine_1 (A : Real_List) is
         R : Ks_Rectangle_Affine;
      begin
         R.Set_Center_Lengths_Rotation_Skew
           (A (1), A (2), A (3), A (4), A (5), A (6));
         Use_Region ("Set_Center_Lengths_Rotation_Skew", R);
         Consume (R.Corner_Opposite_X + R.Corner_X_Y + R.Corner_Y_X);
         Use_Nothing (R.Get_Parent_From_Child_Transform);
      end Affine_1;
      procedure Affine_2 (A : Real_List) is
         R : Ks_Rectangle_Affine;
      begin
         R.Set_Origin_Lengths_Rotation_Skew
           (A (1), A (2), A (3), A (4), A (5), A (6));
         Consume (R.Center_X);
      end Affine_2;
      procedure Affine_3 (A : Real_List) is
         R : Ks_Rectangle_Affine;
      begin
         R.Set_Origin_Corner_X_Corner_Y
           (A (1), A (2), A (3), A (4), A (5), A (6));
         Consume (R.Side_X_Length + R.Skew);
      end Affine_3;
      procedure Circle_1 (A : Real_List) is
         R : Ks_Circle;
      begin
         R.Set_Center_Radius (A (1), A (2), A (3));
         Use_Region ("Set_Center_Radius", R);
      end Circle_1;
      procedure Ellipse_1 (A : Real_List) is
         R : Ks_Ellipse;
      begin
         R.Set_Center_XY_Radius_XY_Rotation (A (1), A (2), A (3), A (4),
                                             A (5));
         Use_Region ("Set_Center_XY_Radius_XY_Rotation", R);
      end Ellipse_1;
      procedure Annulus_1 (A : Real_List) is
         R : Ks_Circular_Annulus_Section;
      begin
         R.Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale
           (A (1), A (2), A (3), A (4), A (5), A (6));
         Use_Region ("Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale",
                     R);
      end Annulus_1;
      procedure Polygon_1 (A : Real_List) is
         R : Ks_Polygon;
      begin
         R.Add_Vertex (A (1), A (2));
         R.Add_Vertex (A (3), A (4));
         R.Add_Vertex (A (5), A (6));
         Use_Region ("Add_Vertex", R);
         Consume (R.Perimeter);
      end Polygon_1;
      procedure Segment_1 (A : Real_List) is
         S : Ks_Line_Segment;
      begin
         S.Set_Start_End (A (1), A (2), A (3), A (4));
         Consume (S.Length + S.Rotation + S.Midpoint_X + S.Midpoint_Y);
         Consume (S.Map (Create_Similarity (1.0E150, 0.0, 0.0, 0.0))
                    .Selected_Space_Name);
      end Segment_1;
      procedure Segment_2 (A : Real_List) is
         S : Ks_Line_Segment;
      begin
         S.Set_Start_Length_Rotation (A (1), A (2), A (3), A (4));
         Consume (S.End_X + S.End_Y);
      end Segment_2;
      procedure Segment_3 (Field : Positive; Value : Real) is
         S : constant Ks_Line_Segment := Segment_With (Field, Value);
         L : Ks_Line;
      begin
         L.Set_From_Line_Segment (S);
         Consume (L.Rotation);
      end Segment_3;
      procedure Line_1 (A : Real_List) is
         L : Ks_Line;
      begin
         L.Set_XY_Rotation (A (1), A (2), A (3));
         Consume (L.Map (Create (1.0, 0.0, 0.0, 0.0, 0.0, 0.0))
                    .Selected_Space_Name);
      end Line_1;
      procedure Line_2 (A : Real_List) is
         L : Ks_Line;
         D, R : Real;
      begin
         L.Set_From_Start_XY_End_XY (A (1), A (2), A (3), A (4));
         L.Get_Distance_Rotation (D, R);
         Consume (D + R);
      end Line_2;
      procedure Line_3 (A : Real_List) is
         L : Ks_Line;
      begin
         L.Set_Distance_Rotation (A (1), A (2));
         Consume (L.X + L.Y);
      end Line_3;
      procedure Line_4 (Field : Positive; Value : Real) is
         L : Ks_Line := Line_With (0, 0.0);
      begin
         case Field is
            when 1 => L.Set_X (Value);
            when 2 => L.Set_Y (Value);
            when others => L.Set_Rotation (Value);
         end case;
      end Line_4;
      procedure Marker (Field : Positive; Value : Real) is
         M : Ks_Point_Marker;
      begin
         case Field is
            when 1 => M.Set_X (Value);
            when 2 => M.Set_Y (Value);
            when others => M.Set_Rotation (Value);
         end case;
         Consume (M.Map (Create_Similarity (1.0E150, 0.0, 1.0E150, 0.0))
                    .Selected_Space_Name);
      end Marker;
      procedure Arc_1 (A : Real_List) is
         C : Ks_Circular_Arc;
      begin
         C.Set_Center_Radius_Angle_Start_Angle_Span
           (A (1), A (2), A (3), A (4), A (5));
         Consume (C.Start_X + C.Start_Y + C.End_X + C.End_Y);
         Consume (C.Map (Create (2.0, 0.0, 0.0, 1.0, 0.0, 0.0))
                    .Selected_Space_Name);
      end Arc_1;
      procedure Arc_2 (Field : Positive; Value : Real) is
      begin
         Consume (Arc_With (Field, Value).End_X);
      end Arc_2;
      Triangle : constant Ks_Polygon :=
        Ks_Polygon (Region_With (Polygon, 0, 0.0));
      procedure Vertex_Get (Index : Integer) is
      begin
         Consume (Triangle.Get_Vertex_X (Index) + Triangle.Get_Vertex_Y (Index));
      end Vertex_Get;
      procedure Vertex_Set (Index : Integer) is
         P : Ks_Polygon := Triangle;
      begin
         P.Set_Vertex (Index, 1.0, 1.0);
      end Vertex_Set;
      procedure Vertex_Remove (Index : Integer) is
         P : Ks_Polygon := Triangle;
      begin
         P.Remove_Vertex (Index);
      end Vertex_Remove;
      procedure Vertex_Add (Index : Integer) is
         P : Ks_Polygon := Triangle;
      begin
         P.Add_Vertex (1.0, 1.0, Index);
      end Vertex_Add;
      procedure Empty_Polygon is
         P : Ks_Polygon;
      begin
         Use_Region ("empty polygon", P);
         P.Add_Vertex (1.0, 1.0);
         Use_Region ("one-vertex polygon", P);
         P.Clear;
      end Empty_Polygon;
      procedure Names (Name : String) is
         C : Ks_Circle := Circle_With (0, 0.0);
      begin
         C.Set_Selected_Space_Name (Name);
         Use_Region ("circle in a bad space", C);
      end Names;
   begin
      Begin_Area ("AMV.Shapes");
      for Kind in Region_Kind loop
         for Field in 1 .. Field_Count (Region_Fields (Kind)) loop
            for Value of Bad_Reals loop
               Region_Field (Kind, Field, Value);
            end loop;
         end loop;
      end loop;
      Composite ("Set_XY_Width_Height", [1.0, 2.0, 3.0, 4.0],
                 Rectangle_1'Access);
      Composite ("Set_Center_Width_Height", [1.0, 2.0, 3.0, 4.0],
                 Rectangle_2'Access);
      Composite ("Set_Center_Lengths_Rotation_Skew",
                 [1.0, 2.0, 3.0, 4.0, 0.5, 0.1], Affine_1'Access);
      Composite ("Set_Origin_Lengths_Rotation_Skew",
                 [1.0, 2.0, 3.0, 4.0, 0.5, 0.1], Affine_2'Access);
      Composite ("Set_Origin_Corner_X_Corner_Y",
                 [1.0, 2.0, 5.0, 2.0, 1.0, 6.0], Affine_3'Access);
      Composite ("Set_Center_Radius", [1.0, 2.0, 3.0], Circle_1'Access);
      Composite ("Set_Center_XY_Radius_XY_Rotation",
                 [1.0, 2.0, 3.0, 4.0, 0.5], Ellipse_1'Access);
      Composite ("Set_Center_Radius_Angle_Start_Angle_Span_Radial_Scale",
                 [1.0, 2.0, 3.0, 0.5, 2.0, 1.5], Annulus_1'Access);
      Composite ("Polygon Add_Vertex", [1.0, 1.0, 9.0, 2.0, 4.0, 8.0],
                 Polygon_1'Access);
      Composite ("Set_Start_End", [1.0, 2.0, 3.0, 4.0], Segment_1'Access);
      Composite ("Set_Start_Length_Rotation", [1.0, 2.0, 3.0, 0.4],
                 Segment_2'Access);
      Field_Sweep ("Set_From_Line_Segment", 4, Segment_3'Access);
      Composite ("Line Set_XY_Rotation", [1.0, 2.0, 0.3], Line_1'Access);
      Composite ("Set_From_Start_XY_End_XY", [1.0, 2.0, 3.0, 4.0],
                 Line_2'Access);
      Composite ("Set_Distance_Rotation", [1.0, 0.3], Line_3'Access);
      Field_Sweep ("Line setters", 3, Line_4'Access);
      Field_Sweep ("Point marker setters", 3, Marker'Access);
      Composite ("Set_Center_Radius_Angle_Start_Angle_Span",
                 [1.0, 2.0, 3.0, 0.5, 2.0], Arc_1'Access);
      Field_Sweep ("Circular arc setters", 5, Arc_2'Access);
      Integer_Sweep ("Get_Vertex", Bad_Indices, Vertex_Get'Access, True);
      Integer_Sweep ("Set_Vertex", Bad_Indices, Vertex_Set'Access, True);
      Integer_Sweep ("Remove_Vertex", Bad_Indices, Vertex_Remove'Access,
                     True);
      Integer_Sweep ("Add_Vertex (index)", Bad_Integers & [-2, 3, 4],
                     Vertex_Add'Access, True);
      Try ("empty polygon", Empty_Polygon'Access);
      Name_Sweep ("Set_Selected_Space_Name", Names'Access);
      End_Area;
   end Sweep_Shapes;

   ---------------------------------------------------------------------
   --  AMV.Regions
   ---------------------------------------------------------------------

   procedure Sweep_Regions is
      Grey_16 : constant Ks_Image_16_Grey := Create (8, 6, 1000);
      Colour  : constant Ks_Image_24_Planar_Color := Create (8, 6, 1, 2, 3);
      Region  : constant AMV.Regions.Pixel_Region :=
        AMV.Regions.Rasterize (Small, Region_With (Circle, 0, 0.0));
      procedure Whole is
      begin
         Consume (AMV.Regions.Whole_Image (No_Image).Pixel_Count);
      end Whole;
      procedure Whole_2 is
      begin
         Consume (AMV.Regions.Whole_Image (Grey_16).Pixel_Count);
         Consume (AMV.Regions.Whole_Image (Colour).Pixel_Count);
         Consume (AMV.Regions.Whole_Image (Tiny).Pixel_Count);
      end Whole_2;
      procedure Holder_Empty is
      begin
         Consume (AMV.Regions.Rasterize (Small, RH.Empty_Holder).Pixel_Count);
         Consume (AMV.Regions.Rasterize (No_Image, RH.Empty_Holder)
                    .Pixel_Count);
      end Holder_Empty;
      procedure Other_Images is
         C : constant Ks_Region'Class := Region_With (Circle, 0, 0.0);
      begin
         Consume (AMV.Regions.Rasterize (Grey_16, C).Pixel_Count);
         Consume (AMV.Regions.Rasterize (Colour, C).Pixel_Count);
         Consume (AMV.Regions.Rasterize (Tiny, C).Pixel_Count);
      end Other_Images;
      procedure Queries is
         Empty : AMV.Regions.Pixel_Region;
      begin
         Consume (Empty.Is_Empty);
         Consume (Empty.X_Min + Empty.Y_Min + Empty.Width + Empty.Height);
         Consume (Region.X_Min + Region.Y_Min + Region.Width + Region.Height);
      end Queries;
   begin
      Begin_Area ("AMV.Regions");
      Try ("Whole_Image (unallocated)", Whole'Access);
      Try ("Whole_Image (other images)", Whole_2'Access);
      Try ("Rasterize (empty holder)", Holder_Empty'Access);
      Try ("Rasterize (other images)", Other_Images'Access);
      Try ("Pixel_Region queries", Queries'Access);
      for X of Bad_Integers loop
         for Y of Bad_Integers loop
            declare
               Text : constant String :=
                 " (" & Image (X) & ", " & Image (Y) & ")";
               procedure Contains is
               begin
                  Consume (Region.Contains (X, Y));
               end Contains;
               procedure Restrict is
               begin
                  Consume (Region.Restrict_To_Mask (Small, X, Y).Pixel_Count);
                  Consume (Region.Restrict_To_Mask (Tiny, X, Y).Pixel_Count);
                  Consume (Region.Restrict_To_Mask (No_Image, X, Y)
                             .Pixel_Count);
               end Restrict;
            begin
               Try ("Contains" & Text, Contains'Access);
               Try ("Restrict_To_Mask" & Text, Restrict'Access);
            end;
         end loop;
      end loop;
      End_Area;
   end Sweep_Regions;

   ---------------------------------------------------------------------
   --  AMV.Image_Math
   ---------------------------------------------------------------------

   procedure Sweep_Image_Math is
      package IM renames AMV.Image_Math;
      R : constant IM.Real_Image := IM.From_Grey_8 (Small);
      Empty : IM.Real_Image;
      procedure Create_Sizes (A : Real_List) is
      begin
         Consume (IM.Create (3, 2, A (1)).Width);
      end Create_Sizes;
      procedure Set_Value (A : Real_List) is
         C : IM.Real_Image := R;
      begin
         C.Set (1, 1, A (1));
         C.Fill (A (1));
      end Set_Value;
      procedure Bilinear (A : Real_List) is
      begin
         Consume (R.Bilinear (A (1), A (2)));
         Consume (R.Is_Inside (A (1), A (2)));
         Consume (IM.Bilinear (Small, A (1), A (2)));
      end Bilinear;
      procedure Bilinear_Empty (A : Real_List) is
      begin
         Consume (Empty.Bilinear (A (1), A (2)));
      end Bilinear_Empty;
      procedure Bilinear_None (A : Real_List) is
      begin
         Consume (IM.Bilinear (No_Image, A (1), A (2)));
      end Bilinear_None;
      procedure Resample (A : Real_List) is
         T : constant Ks_Transform_2D_Linear :=
           Create (A (1), A (2), A (3), A (4), A (5), A (6));
      begin
         Consume (IM.Resample (Small, T, 5, 4).Width);
         Consume (IM.Resample (R, T, 5, 4).Width);
      end Resample;
      procedure Smooth (A : Real_List) is
      begin
         Consume (R.Gaussian_Smooth (A (1)).Width);
         Consume (Empty.Gaussian_Smooth (A (1)).Width);
      end Smooth;
      procedure Sizes (Value : Integer) is
      begin
         Consume (IM.Create (Value, 2).Width);
      end Sizes;
      procedure Sizes_2 (Value : Integer) is
      begin
         Consume (IM.Create (65_536, Value).Width);
      end Sizes_2;
      procedure Resample_Sizes (Value : Integer) is
      begin
         Consume (IM.Resample (Small, Identity, Value, 2).Width);
      end Resample_Sizes;
      procedure Resample_Sizes_2 (Value : Integer) is
      begin
         Consume (IM.Resample (R, Identity, 3, Value).Width);
      end Resample_Sizes_2;
      procedure Box (Value : Integer) is
      begin
         Consume (R.Box_Smooth (Value).Width);
      end Box;
      procedure Window (Value : Integer) is
      begin
         Consume (IM.From_Grey_8 (Small, Value, 0, 4, 4).Width);
         Consume (IM.From_Grey_8 (Small, 0, Value, 4, 4).Width);
         Consume (IM.From_Grey_8 (Small, 0, 0, Value, 4).Width);
         Consume (IM.From_Grey_8 (Small, 0, 0, 4, Value).Width);
      end Window;
      procedure Pixel (Value : Integer) is
         C : IM.Real_Image := R;
      begin
         Consume (R.Get (Value, 1) + R.Get (1, Value));
         C.Set (Value, 0, 1.0);
      end Pixel;
      procedure Others_Empty is
         Gx, Gy : IM.Real_Image;
         M, S, Lo, Hi : Real;
      begin
         Empty.Sobel (Gx, Gy);
         Consume (Empty.Downsample_2.Width);
         Consume (Empty.Box_Smooth (3).Width);
         Empty.Statistics (M, S, Lo, Hi);
         Consume (M + S + Lo + Hi);
         Consume (IM.From_Grey_8 (No_Image).Width);
         Consume (Empty.To_Grey_8.Width);
         Consume (IM.Create (0, 0).Width);
         Consume (IM.Create (0, 5).To_Grey_8.Width);
      end Others_Empty;
      procedure Extreme is
         C : IM.Real_Image := IM.Create (5, 5, IM.Max_Value);
         Gx, Gy : IM.Real_Image;
         M, S, Lo, Hi : Real;
      begin
         C.Set (2, 2, -IM.Max_Value);
         C.Sobel (Gx, Gy);
         C.Statistics (M, S, Lo, Hi);
         Consume (C.Box_Smooth (Natural'Last).Get (0, 0));
         Consume (C.Gaussian_Smooth (IM.Max_Sigma).Get (0, 0));
         Consume (C.Downsample_2.Get (0, 0));
         Consume (C.To_Grey_8.Width);
      end Extreme;
   begin
      Begin_Area ("AMV.Image_Math");
      Composite ("Create (value)", [1.0], Create_Sizes'Access);
      Composite ("Set, Fill", [1.0], Set_Value'Access);
      Composite ("Bilinear, Is_Inside", [1.0, 2.0], Bilinear'Access);
      Composite ("Bilinear (empty)", [1.0, 2.0], Bilinear_Empty'Access);
      Composite ("Bilinear (unallocated)", [1.0, 2.0],
                 Bilinear_None'Access);
      Composite ("Resample", [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
                 Resample'Access);
      Composite ("Gaussian_Smooth", [1.0], Smooth'Access);
      Integer_Sweep ("Create (width)", Bad_Naturals & [65_536],
                     Sizes'Access);
      Integer_Sweep ("Create (65536, height)", Bad_Naturals & [65_536],
                     Sizes_2'Access);
      Integer_Sweep ("Resample (width)", [1, Positive'Last],
                     Resample_Sizes'Access);
      Integer_Sweep ("Resample (height)", [1, Positive'Last],
                     Resample_Sizes_2'Access);
      Integer_Sweep ("Box_Smooth", Bad_Naturals, Box'Access);
      Integer_Sweep ("From_Grey_8 (window)", Bad_Naturals, Window'Access);
      Integer_Sweep ("Get, Set", Bad_Indices, Pixel'Access, True);
      Try ("empty images", Others_Empty'Access);
      Try ("values at the bound", Extreme'Access);
      End_Area;
   end Sweep_Image_Math;

   ---------------------------------------------------------------------
   --  AMV.Geometry
   ---------------------------------------------------------------------

   procedure Sweep_Geometry is
      package G renames AMV.Geometry;
      procedure Points (A : Real_List) is
      begin
         Consume (G.Distance (G.Point_2D'(A (1), A (2)),
                              G.Point_2D'(A (3), A (4))));
      end Points;
      procedure Point_Line (A : Real_List) is
         P : constant G.Point_2D := (A (1), A (2));
         L : constant G.Line_2D := (A (3), A (4), A (5));
      begin
         Consume (G.Signed_Distance (P, L));
         Consume (G.Distance (P, L));
         Consume (G.Project (P, L).X);
         Consume (G.Position_Along (P, L));
      end Point_Line;
      procedure Point_Circle (A : Real_List) is
      begin
         Consume (G.Distance (G.Point_2D'(A (1), A (2)),
                              G.Circle_2D'(A (3), A (4), A (5))));
      end Point_Circle;
      procedure Lines (A : Real_List) is
         P : G.Point_2D;
         Parallel : Boolean;
      begin
         G.Intersect (G.Line_2D'(A (1), A (2), A (3)),
                      G.Line_2D'(A (4), A (5), A (6)), P, Parallel);
         Consume (P.X);
         Consume (G.Angle_Between (G.Line_2D'(A (1), A (2), A (3)),
                                   G.Line_2D'(A (4), A (5), A (6))));
      end Lines;
      procedure Line_Circle (A : Real_List) is
         P, Q : G.Point_2D;
         Count : Natural;
      begin
         G.Intersect (G.Line_2D'(A (1), A (2), A (3)),
                      G.Circle_2D'(A (4), A (5), A (6)), P, Q, Count);
         Consume (Count);
      end Line_Circle;
      procedure Circles (A : Real_List) is
         P, Q : G.Point_2D;
         Count : Natural;
      begin
         G.Intersect (G.Circle_2D'(A (1), A (2), A (3)),
                      G.Circle_2D'(A (4), A (5), A (6)), P, Q, Count);
         Consume (Count);
      end Circles;
      procedure Fits (A : Real_List) is
         Pts : constant G.Point_Array :=
           [(A (1), A (2)), (1.0, 0.0), (0.0, 1.0), (-1.0, 0.0),
            (0.0, -1.0)];
         L : G.Line_2D;
         C : G.Circle_2D;
         E : Real;
         Used : G.Boolean_Array (Pts'Range);
      begin
         G.Fit_Line (Pts, L, E);
         G.Fit_Circle (Pts, C, E);
         G.Fit_Line (Pts, 1, L, E, Used);
         G.Fit_Circle (Pts, 1, C, E, Used);
         Consume (E);
      end Fits;
      procedure Degenerate is
         None : constant G.Point_Array (1 .. 0) := [others => (0.0, 0.0)];
         Pts  : constant G.Point_Array := [(0.0, 0.0), (1.0, 1.0), (2.0, 2.0)];
         L : G.Line_2D;
         C : G.Circle_2D;
         E : Real;
         Used : G.Boolean_Array (1 .. 2);
      begin
         begin
            G.Fit_Line (None, L, E);
         exception
            when AMV.Ks_Bad_Parameter_Exception => null;
         end;
         begin
            G.Fit_Circle (Pts, C, E);
         exception
            when AMV.Ks_Bad_Parameter_Exception => null;
         end;
         begin
            G.Fit_Line (Pts, Natural'Last, L, E, Used);
         exception
            when AMV.Ks_Bad_Parameter_Exception => null;
         end;
         G.Fit_Circle (Pts, Natural'Last, C, E, Used);
      end Degenerate;
   begin
      Begin_Area ("AMV.Geometry");
      Composite ("Distance (points)", [1.0, 2.0, 3.0, 4.0], Points'Access);
      Composite ("point and line", [1.0, 2.0, 3.0, 4.0, 0.5],
                 Point_Line'Access);
      Composite ("Distance (point, circle)", [1.0, 2.0, 3.0, 4.0, 5.0],
                 Point_Circle'Access);
      Composite ("Intersect (lines), Angle_Between",
                 [1.0, 2.0, 0.3, 4.0, 5.0, 1.3], Lines'Access);
      Composite ("Intersect (line, circle)", [1.0, 2.0, 0.3, 4.0, 5.0, 6.0],
                 Line_Circle'Access);
      Composite ("Intersect (circles)", [1.0, 2.0, 3.0, 4.0, 5.0, 6.0],
                 Circles'Access);
      Composite ("Fit_Line, Fit_Circle", [0.5, 0.5], Fits'Access);
      Try ("degenerate fits", Degenerate'Access);
      End_Area;
   end Sweep_Geometry;

   ---------------------------------------------------------------------
   --  Caliper run parameters (shared by the caliper and the find tools)
   ---------------------------------------------------------------------

   Caliper_Real_Fields : constant String :=
     "Edge0Position,Edge1Position,ContrastThreshold,"
     & "SingleEdgeScorers(0).X0,SingleEdgeScorers(0).X1,"
     & "SingleEdgeScorers(0).XC,SingleEdgeScorers(0).Y0,"
     & "SingleEdgeScorers(0).Y1,Pair.TwoEdgeScorers(0).X0,"
     & "Pair.TwoEdgeScorers(0).XC,Pair.Edge1Position";

   procedure Set_Caliper_Real
     (P : in out AMV.Caliper.Ks_Caliper; Field : Positive; Value : Real) is
   begin
      case Field is
         when 1 => P.Edge_0_Position := Value;
         when 2 => P.Edge_1_Position := Value;
         when 3 => P.Contrast_Threshold := Value;
         when 4 => P.Single_Edge_Scorers.Items (0).X0 := Value;
         when 5 => P.Single_Edge_Scorers.Items (0).X1 := Value;
         when 6 => P.Single_Edge_Scorers.Items (0).XC := Value;
         when 7 => P.Single_Edge_Scorers.Items (0).Y0 := Value;
         when 8 => P.Single_Edge_Scorers.Items (0).Y1 := Value;
         when 9 =>
            P.Edge_Mode := AMV.Caliper.Code (AMV.Caliper.Pair);
            P.Two_Edge_Scorers.Items (0).X0 := Value;
         when 10 =>
            P.Edge_Mode := AMV.Caliper.Code (AMV.Caliper.Pair);
            P.Two_Edge_Scorers.Items (0).XC := Value;
         when others =>
            P.Edge_Mode := AMV.Caliper.Code (AMV.Caliper.Pair);
            P.Edge_1_Position := Value;
      end case;
   end Set_Caliper_Real;

   Caliper_Integer_Fields : constant String :=
     "EdgeMode,Edge0Polarity,Edge1Polarity,FilterHalfSizeInPixels,"
     & "MaxResults,SamplingMode,SingleEdgeScorers.Count,"
     & "TwoEdgeScorers.Count,SingleEdgeScorers(0).Kind,"
     & "SingleEdgeScorers(0).Enabled,Pair.TwoEdgeScorers(0).Kind";

   procedure Set_Caliper_Integer
     (P : in out AMV.Caliper.Ks_Caliper; Field : Positive; Value : Integer)
   is
      V : constant Int32 := Int32 (Value);
   begin
      case Field is
         when 1 => P.Edge_Mode := V;
         when 2 => P.Edge_0_Polarity := V;
         when 3 => P.Edge_1_Polarity := V;
         when 4 => P.Filter_Half_Size_In_Pixels := V;
         when 5 => P.Max_Results := V;
         when 6 => P.Sampling_Mode := V;
         when 7 => P.Single_Edge_Scorers.Count := V;
         when 8 =>
            P.Edge_Mode := AMV.Caliper.Code (AMV.Caliper.Pair);
            P.Two_Edge_Scorers.Count := V;
         when 9 => P.Single_Edge_Scorers.Items (0).Kind := V;
         when 10 => P.Single_Edge_Scorers.Items (0).Enabled := V;
         when others =>
            P.Edge_Mode := AMV.Caliper.Code (AMV.Caliper.Pair);
            P.Two_Edge_Scorers.Items (0).Kind := V;
      end case;
   end Set_Caliper_Integer;

   ---------------------------------------------------------------------
   --  Blob
   ---------------------------------------------------------------------

   procedure Sweep_Blob is
      package B renames AMV.Blob;
      procedure Prepare (T : in out B.Ks_Blob_Tool) is
      begin
         T.Input_Image := Small;
         B.Add (T.Run_Params.Run_Time_Measures,
                B.Blob_Measure (B.Area, B.Filter, B.Include_Blobs_In_Range,
                                1.0, 1.0E6));
         B.Add (T.Run_Params.Morphology_Operations, B.Open_Square);
         T.Run_Params.Save_Segmented_Image := B.Code (True);
         T.Run_Params.Save_Segmented_Image_Before_Masking := B.Code (True);
         T.Run_Params.Save_Segmented_Image_Before_Morphology :=
           B.Code (True);
      end Prepare;
      procedure Use_Results (T : B.Ks_Blob_Tool; Call : String) is
         Blobs : constant B.Ks_Blob_Result_Collection'Class :=
           T.Results.Get_Blobs;
         procedure Per_Blob is
         begin
            for I in 0 .. Blobs.Count - 1 loop
               declare
                  R : constant B.Ks_Blob_Result := Blobs.Item (I);
               begin
                  for M in B.Ks_Blob_Measure_Constants loop
                     Consume (B.Get_Measure (R, M));
                  end loop;
                  for A in B.Ks_Blob_Axis_Constants loop
                     Consume (B.Get_Bounding_Box (R, A).Center_X);
                  end loop;
               end;
            end loop;
         end Per_Blob;
         procedure Beyond (Index : Integer) is
         begin
            Consume (Integer (Blobs.Item (Index).ID));
         end Beyond;
         procedure By_ID (ID : Integer) is
         begin
            Consume (Integer (T.Results.Get_Blob_By_ID (ID).ID));
         end By_ID;
         procedure Parent (ID : Integer) is
         begin
            Consume (T.Results.Get_Parent (ID));
         end Parent;
         procedure Boundary (ID : Integer) is
         begin
            Consume (T.Results.Get_Boundary (ID).Num_Vertices);
         end Boundary;
         procedure Medians (ID : Integer) is
         begin
            Consume (T.Results.Get_Median_X (ID, B.Principal));
            Consume (T.Results.Get_Median_Y (ID, B.Extrema_Angle));
         end Medians;
         procedure At_Angle (A : Real_List) is
         begin
            Consume (T.Results.Get_Bounding_Box_At_Angle (0, A (1))
                       .Center_X);
         end At_Angle;
         procedure Tree (ID : Integer) is
         begin
            for Filtered in Boolean loop
               Consume (T.Results.Get_Children (ID, Filtered).Count);
               Consume (T.Results.Get_Siblings (ID, Filtered).Count);
            end loop;
         end Tree;
         procedure Measures_Of (ID : Integer) is
            IDs : constant B.Ks_Blob_ID_Array := [0, ID];
         begin
            Consume (T.Results.Get_Blob_Measure (B.Area, ID));
            Consume (T.Results.Get_Blob_Measures (B.Area, IDs) (1));
         end Measures_Of;
         procedure Whole_Tree is
         begin
            for Filtered in Boolean loop
               Consume (T.Results.Get_Top_Level_Blobs (Filtered).Count);
               Consume (Integer (T.Results.Get_Blob_IDs (Filtered)'Length));
            end loop;
         end Whole_Tree;
         procedure ID_Image is
         begin
            Consume (T.Results.Create_Blob_ID_Image.Width);
            Consume (T.Results.Create_Blob_ID_Image (False).Width);
            Consume (T.Results.Selected_Space_Name);
         end ID_Image;
         procedure Images is
         begin
            for Filtered in Boolean loop
               for Viewable in Boolean loop
                  Consume (T.Results.Create_Blob_Image
                             (Filtered, Viewable, 255).Width);
               end loop;
            end loop;
            for Which in B.Ks_Blob_Segmented_Image_Constants loop
               for Stretch in Boolean loop
                  Consume (T.Results.Create_Segmented_Image
                             (Which, Stretch).Width);
               end loop;
            end loop;
         end Images;
         procedure Background (Value : Integer) is
         begin
            Consume (T.Results.Create_Blob_Image
                       (Viewable => False, Background => Value).Width);
            Consume (T.Results.Create_Blob_Image
                       (Viewable => True, Background => Value).Width);
         end Background;
      begin
         Try (Call & " / measures", Per_Blob'Access);
         Integer_Sweep (Call & " / Item", [Blobs.Count, Natural'Last],
                        Beyond'Access, True);
         Integer_Sweep (Call & " / Get_Blob_By_ID", Bad_Integers & [1],
                        By_ID'Access);
         Integer_Sweep (Call & " / Get_Parent", Bad_Integers, Parent'Access);
         Integer_Sweep (Call & " / Get_Boundary", Bad_Integers,
                        Boundary'Access);
         Integer_Sweep (Call & " / Get_Median_X, Y", Bad_Integers,
                        Medians'Access);
         Composite (Call & " / Get_Bounding_Box_At_Angle", [0.3],
                    At_Angle'Access);
         Try (Call & " / Create_Blob_ID_Image", ID_Image'Access);
         Try (Call & " / Create_Blob_Image, Create_Segmented_Image",
              Images'Access);
         Integer_Sweep (Call & " / Create_Blob_Image (Background)",
                        Bad_Integers & [0, 255, 256], Background'Access);
         Integer_Sweep (Call & " / Get_Children, Get_Siblings",
                        Bad_Integers & [0], Tree'Access);
         Integer_Sweep (Call & " / Get_Blob_Measure(s)", Bad_Integers & [0],
                        Measures_Of'Access);
         Try (Call & " / Get_Top_Level_Blobs, Get_Blob_IDs",
              Whole_Tree'Access);
      end Use_Results;
      package S is new Sweeps (B.Ks_Blob_Tool, "Blob", Prepare, Use_Results);
      procedure Prepare_Soft (T : in out B.Ks_Blob_Tool) is
      begin
         Prepare (T);
         B.Set_Segmentation_Soft_Relative_Threshold
           (T.Run_Params.Segmentation_Params, 1, 1, 30, 70, 254,
            B.Light_Blobs);
      end Prepare_Soft;
      package Soft is new Sweeps
        (B.Ks_Blob_Tool, "Blob (soft)", Prepare_Soft, Use_Results);
      --  The same tool with a soft segmentation (weighted measures and
      --  morphology on the levels).
      procedure Set_Image (T : in out B.Ks_Blob_Tool; F : Positive;
                           I : Ks_Image_8_Grey) is
         pragma Unreferenced (F);
      begin
         T.Input_Image := I;
      end Set_Image;
      procedure Set_Real (T : in out B.Ks_Blob_Tool; F : Positive;
                          V : Real) is
      begin
         case F is
            when 1 => T.Run_Params.Extrema_Angle := V;
            when 2 => T.Run_Params.Run_Time_Measures.Items (0)
                        .Filter_Range_Low := V;
            when others => T.Run_Params.Run_Time_Measures.Items (0)
                             .Filter_Range_High := V;
         end case;
      end Set_Real;
      procedure Set_Integer (T : in out B.Ks_Blob_Tool; F : Positive;
                             V : Integer) is
         P : B.Ks_Blob renames T.Run_Params;
         I : constant Int32 := Int32 (V);
      begin
         case F is
            when 1 => P.Segmentation_Params.Mode := I;
            when 2 => P.Segmentation_Params.Polarity := I;
            when 3 =>
               P.Segmentation_Params.Mode :=
                 B.Code (B.Hard_Fixed_Threshold);
               P.Segmentation_Params.Hard_Fixed_Threshold := I;
            when 4 =>
               P.Segmentation_Params.Mode :=
                 B.Code (B.Hard_Relative_Threshold);
               P.Segmentation_Params.Hard_Relative_Threshold := I;
            when 5 =>
               P.Segmentation_Params.Mode :=
                 B.Code (B.Hard_Relative_Threshold);
               P.Segmentation_Params.Tail_Low := I;
            when 6 =>
               P.Segmentation_Params.Mode :=
                 B.Code (B.Hard_Relative_Threshold);
               P.Segmentation_Params.Tail_High := I;
            when 7 => P.Connectivity_Mode := I;
            when 8 => P.Connectivity_Cleanup := I;
            when 9 => P.Connectivity_Min_Pixels := I;
            when 10 => P.Sort_Enabled := I;
            when 11 => P.Sort_Measure := I;
            when 12 => P.Sort_Ascending := I;
            when 13 => P.Run_Time_Measures.Count := I;
            when 14 => P.Run_Time_Measures.Items (0).Measure := I;
            when 15 => P.Run_Time_Measures.Items (0).Mode := I;
            when 16 => P.Run_Time_Measures.Items (0).Filter_Mode := I;
            when 17 => P.Morphology_Operations.Count := I;
            when 18 =>
               P.Segmentation_Params.Mode := B.Code (B.Soft_Fixed_Threshold);
               P.Segmentation_Params.Soft_Fixed_Threshold_Low := I;
            when 19 =>
               P.Segmentation_Params.Mode := B.Code (B.Soft_Fixed_Threshold);
               P.Segmentation_Params.Soft_Fixed_Threshold_High := I;
            when 20 =>
               P.Segmentation_Params.Mode :=
                 B.Code (B.Soft_Relative_Threshold);
               P.Segmentation_Params.Soft_Relative_Threshold_Low := I;
            when 21 =>
               P.Segmentation_Params.Mode :=
                 B.Code (B.Soft_Relative_Threshold);
               P.Segmentation_Params.Soft_Relative_Threshold_High := I;
            when 22 =>
               P.Segmentation_Params.Mode := B.Code (B.Soft_Fixed_Threshold);
               P.Segmentation_Params.Softness := I;
            when 23 =>
               P.Segmentation_Params.Mode :=
                 B.Code (B.Soft_Relative_Threshold);
               P.Segmentation_Params.Softness := I;
            when 24 =>
               P.Segmentation_Params.Mode :=
                 B.Code (B.Soft_Relative_Threshold);
               P.Segmentation_Params.Tail_Low := I;
            when 25 => P.Save_Segmented_Image := I;
            when 26 => P.Save_Segmented_Image_Before_Masking := I;
            when 27 => P.Save_Segmented_Image_Before_Morphology := I;
            when others => P.Morphology_Operations.Items (0) := I;
         end case;
      end Set_Integer;
      procedure Set_Region (T : in out B.Ks_Blob_Tool;
                            R : Ks_Region'Class) is
      begin
         T.Region := RH.To_Holder (R);
      end Set_Region;
      procedure Measures is
         M : B.Ks_Blob_Measure_Collection;
      begin
         for I in 1 .. 70 loop
            B.Add (M, B.Blob_Measure (B.Area));
         end loop;
      end Measures;
      procedure Morphology is
         M : B.Ks_Blob_Morphology_Collection;
      begin
         for I in 1 .. 40 loop
            B.Add (M, B.Erode_Square);
         end loop;
      end Morphology;
      procedure Forged_Collections (Value : Integer) is
         M : B.Ks_Blob_Measure_Collection;
         O : B.Ks_Blob_Morphology_Collection;
      begin
         M.Count := Int32 (Value);
         O.Count := Int32 (Value);
         begin
            B.Add (M, B.Blob_Measure (B.Area));
         exception
            when Occurrence : others =>
               Note ("Add (forged measure collection," & Value'Image & ")",
                     Occurrence);
         end;
         B.Add (O, B.Dilate_Square);
         B.Clear (M);
         B.Clear (O);
      end Forged_Collections;
      procedure Setters (Value : Integer) is
         --  Every setter of the segmentation parameters, with Value in
         --  each integer argument in turn (the others valid).
         procedure Each (Name : String; Call : not null access procedure)
         is
         begin
            Area_Calls := Area_Calls + 1;
            Call.all;
         exception
            when Occurrence : others =>
               Note (Name & " (" & Image (Value) & ")", Occurrence);
         end Each;
         P : B.Ks_Blob_Segmentation_Params;
         procedure Hard_Fixed is
         begin
            B.Set_Segmentation_Hard_Fixed_Threshold (P, Value, B.Light_Blobs);
         end Hard_Fixed;
         procedure Relative_1 is
         begin
            B.Set_Segmentation_Hard_Relative_Threshold
              (P, Value, 0, 50, B.Dark_Blobs);
         end Relative_1;
         procedure Relative_2 is
         begin
            B.Set_Segmentation_Hard_Relative_Threshold
              (P, 0, Value, 50, B.Dark_Blobs);
         end Relative_2;
         procedure Relative_3 is
         begin
            B.Set_Segmentation_Hard_Relative_Threshold
              (P, 0, 0, Value, B.Dark_Blobs);
         end Relative_3;
         procedure Dynamic_1 is
         begin
            B.Set_Segmentation_Hard_Dynamic_Threshold
              (P, Value, 0, B.Light_Blobs);
         end Dynamic_1;
         procedure Dynamic_2 is
         begin
            B.Set_Segmentation_Hard_Dynamic_Threshold
              (P, 0, Value, B.Light_Blobs);
         end Dynamic_2;
         procedure Fixed_1 is
         begin
            B.Set_Segmentation_Soft_Fixed_Threshold
              (P, Value, 200, 10, B.Light_Blobs);
         end Fixed_1;
         procedure Fixed_2 is
         begin
            B.Set_Segmentation_Soft_Fixed_Threshold
              (P, 0, Value, 10, B.Light_Blobs);
         end Fixed_2;
         procedure Fixed_3 is
         begin
            B.Set_Segmentation_Soft_Fixed_Threshold
              (P, 50, 200, Value, B.Dark_Blobs);
         end Fixed_3;
         procedure Soft_Relative_1 is
         begin
            B.Set_Segmentation_Soft_Relative_Threshold
              (P, Value, 0, 40, 60, 10, B.Light_Blobs);
         end Soft_Relative_1;
         procedure Soft_Relative_2 is
         begin
            B.Set_Segmentation_Soft_Relative_Threshold
              (P, 0, Value, 40, 60, 10, B.Light_Blobs);
         end Soft_Relative_2;
         procedure Soft_Relative_3 is
         begin
            B.Set_Segmentation_Soft_Relative_Threshold
              (P, 0, 0, Value, 60, 10, B.Light_Blobs);
         end Soft_Relative_3;
         procedure Soft_Relative_4 is
         begin
            B.Set_Segmentation_Soft_Relative_Threshold
              (P, 0, 0, 0, Value, 10, B.Light_Blobs);
         end Soft_Relative_4;
         procedure Soft_Relative_5 is
         begin
            B.Set_Segmentation_Soft_Relative_Threshold
              (P, 0, 0, 40, 60, Value, B.Dark_Blobs);
         end Soft_Relative_5;
      begin
         Each ("Set_Segmentation_Hard_Fixed_Threshold", Hard_Fixed'Access);
         Each ("Set_Segmentation_Hard_Relative_Threshold (Tail_Low)",
               Relative_1'Access);
         Each ("Set_Segmentation_Hard_Relative_Threshold (Tail_High)",
               Relative_2'Access);
         Each ("Set_Segmentation_Hard_Relative_Threshold (threshold)",
               Relative_3'Access);
         Each ("Set_Segmentation_Hard_Dynamic_Threshold (Tail_Low)",
               Dynamic_1'Access);
         Each ("Set_Segmentation_Hard_Dynamic_Threshold (Tail_High)",
               Dynamic_2'Access);
         Each ("Set_Segmentation_Soft_Fixed_Threshold (Low)",
               Fixed_1'Access);
         Each ("Set_Segmentation_Soft_Fixed_Threshold (High)",
               Fixed_2'Access);
         Each ("Set_Segmentation_Soft_Fixed_Threshold (Softness)",
               Fixed_3'Access);
         Each ("Set_Segmentation_Soft_Relative_Threshold (Tail_Low)",
               Soft_Relative_1'Access);
         Each ("Set_Segmentation_Soft_Relative_Threshold (Tail_High)",
               Soft_Relative_2'Access);
         Each ("Set_Segmentation_Soft_Relative_Threshold (Low)",
               Soft_Relative_3'Access);
         Each ("Set_Segmentation_Soft_Relative_Threshold (High)",
               Soft_Relative_4'Access);
         Each ("Set_Segmentation_Soft_Relative_Threshold (Softness)",
               Soft_Relative_5'Access);
      end Setters;
      procedure Forged (Field : Positive; Value : Real) is
         R : B.Ks_Blob_Result;
      begin
         case Field is
            when 1 => R.Area := Value;
            when 2 => R.Center_Of_Mass_X := Value;
            when 3 => R.Angle := Value;
            when 4 => R.Pixel_Aligned_Width := Value;
            when others => R.Principal_Axis_Max_X := Value;
         end case;
         for M in B.Ks_Blob_Measure_Constants loop
            Consume (B.Get_Measure (R, M));
         end loop;
         for A in B.Ks_Blob_Axis_Constants loop
            Consume (B.Get_Bounding_Box (R, A).Center_X);
         end loop;
      end Forged;
   begin
      Begin_Area ("Blob", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage", Set_Image'Access);
      Soft.Default_Run;
      Soft.Images ("InputImage", Set_Image'Access);
      Soft.Reals ("ExtremaAngle,Measure(0).FilterRangeLow,"
                  & "Measure(0).FilterRangeHigh", Set_Real'Access);
      Soft.Regions ("Region", All_Regions, Set_Region'Access);
      S.Reals ("ExtremaAngle,Measure(0).FilterRangeLow,"
               & "Measure(0).FilterRangeHigh", Set_Real'Access);
      S.Integers ("Segmentation.Mode,Segmentation.Polarity,"
                  & "HardFixedThreshold,HardRelativeThreshold,TailLow,"
                  & "TailHigh,ConnectivityMode,ConnectivityCleanup,"
                  & "ConnectivityMinPixels,SortEnabled,SortMeasure,"
                  & "SortAscending,RunTimeMeasures.Count,Measure(0).Measure,"
                  & "Measure(0).Mode,Measure(0).FilterMode,"
                  & "MorphologyOperations.Count,SoftFixedThresholdLow,"
                  & "SoftFixedThresholdHigh,SoftRelativeThresholdLow,"
                  & "SoftRelativeThresholdHigh,Softness (fixed),"
                  & "Softness (relative),TailLow (soft relative),"
                  & "SaveSegmentedImage,SaveSegmentedImageBeforeMasking,"
                  & "SaveSegmentedImageBeforeMorphology,"
                  & "MorphologyOperations(0)",
                  Set_Integer'Access,
                  Bad_Integers & [1, 100, 254, 255, 65_534, 65_535]);
      Integer_Sweep ("Set_Segmentation_* (each argument in turn)",
                     Bad_Integers & [1, 100, 101, 254, 255, 65_535],
                     Setters'Access);
      S.Regions ("Region", All_Regions, Set_Region'Access);
      Try ("Ks_Blob_Measure_Collection beyond its limit", Measures'Access);
      Try ("Ks_Blob_Morphology_Collection beyond its limit",
           Morphology'Access);
      Field_Sweep ("Get_Measure, Get_Bounding_Box (forged result)", 5,
                   Forged'Access);
      Integer_Sweep ("Add (forged collections)", Bad_Integers & [32, 64, 65],
                     Forged_Collections'Access);
      End_Area;
   end Sweep_Blob;

   ---------------------------------------------------------------------
   --  Caliper
   ---------------------------------------------------------------------

   procedure Sweep_Caliper is
      package C renames AMV.Caliper;
      procedure Prepare (T : in out C.Ks_Caliper_Tool) is
      begin
         T.Input_Image := Small;
         T.Region.Set_Center_Lengths_Rotation_Skew (19.2, 19.2, 30.0, 10.0,
                                                    0.0, 0.0);
         T.Run_Params.Max_Results := 3;
      end Prepare;
      procedure Use_Results (T : C.Ks_Caliper_Tool; Call : String) is
         procedure Read is
         begin
            for I in 0 .. T.Results.Count - 1 loop
               Consume (T.Results.Item (I).Position_X);
            end loop;
            Consume (Integer (C.Get_Projection_Values (T.Results)'Length));
            Consume (Integer (C.Get_Filtered_Values (T.Results)'Length));
         end Read;
         procedure Beyond (Index : Integer) is
         begin
            Consume (T.Results.Item (Index).Score);
         end Beyond;
      begin
         Try (Call & " / results", Read'Access);
         Integer_Sweep (Call & " / Item", [T.Results.Count, Natural'Last],
                        Beyond'Access, True);
      end Use_Results;
      package S is new Sweeps (C.Ks_Caliper_Tool, "Caliper", Prepare,
                               Use_Results);
      procedure Set_Image (T : in out C.Ks_Caliper_Tool; F : Positive;
                           I : Ks_Image_8_Grey) is
         pragma Unreferenced (F);
      begin
         T.Input_Image := I;
      end Set_Image;
      procedure Set_Real (T : in out C.Ks_Caliper_Tool; F : Positive;
                          V : Real) is
      begin
         Set_Caliper_Real (T.Run_Params, F, V);
      end Set_Real;
      procedure Set_Integer (T : in out C.Ks_Caliper_Tool; F : Positive;
                             V : Integer) is
      begin
         Set_Caliper_Integer (T.Run_Params, F, V);
      end Set_Integer;
      procedure Set_Region (T : in out C.Ks_Caliper_Tool;
                            R : Ks_Region'Class) is
      begin
         T.Region := Ks_Rectangle_Affine (R);
      end Set_Region;
      Scorer : C.Ks_Caliper_Scorer := C.New_Scorer (C.Position);
      procedure Scorer_Parameters (A : Real_List) is
         S : C.Ks_Caliper_Scorer := Scorer;
      begin
         C.Set_XY_Parameters (S, A (1), A (2), A (3), A (4), A (5));
      end Scorer_Parameters;
      procedure Forged_Kind (Value : Integer) is
         S : C.Ks_Caliper_Scorer := Scorer;
      begin
         S.Kind := Int32 (Value);
         Consume (C.Kind (S)'Image);
      end Forged_Kind;
      procedure Forged_Enabled (Value : Integer) is
         S : C.Ks_Caliper_Scorer := Scorer;
      begin
         S.Enabled := Int32 (Value);
         Consume (C.Enabled (S));
      end Forged_Enabled;
      procedure Forged_Count (Value : Integer) is
         L : C.Ks_Caliper_Scorers;
      begin
         L.Count := Int32 (Value);
         Consume (C.Count (L));
      end Forged_Count;
      procedure Kind_9 is
      begin
         Forged_Kind (9);
      end Kind_9;
      procedure Enabled_2 is
      begin
         Forged_Enabled (2);
      end Enabled_2;
      procedure Count_9 is
      begin
         Forged_Count (9);
      end Count_9;
      procedure Check_Kind_9 is new Check_Raises_Exactly
        (Kind_9, AMV.Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Enabled_2 is new Check_Raises_Exactly
        (Enabled_2, AMV.Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Count_9 is new Check_Raises_Exactly
        (Count_9, AMV.Ks_Bad_Parameter_Exception'Identity);
      procedure Forged_List (Value : Integer) is
         L : C.Ks_Caliper_Scorers;
      begin
         L.Count := Int32 (Value);
         C.Add (L, Scorer);
         C.Remove_At (L, 0);
         C.Clear (L);
      end Forged_List;
      procedure Remove (Value : Integer) is
         L : C.Ks_Caliper_Scorers := C.KC.Default_Single_Edge_Scorers;
      begin
         C.Remove_At (L, Value);
      end Remove;
      procedure Full is
         L : C.Ks_Caliper_Scorers;
      begin
         for I in 1 .. 10 loop
            C.Add (L, Scorer);
         end loop;
      end Full;
   begin
      Begin_Area ("Caliper", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage", Set_Image'Access);
      S.Reals (Caliper_Real_Fields, Set_Real'Access);
      S.Integers (Caliper_Integer_Fields, Set_Integer'Access);
      S.Regions ("Region", [Rectangle_Affine => True, others => False],
                 Set_Region'Access);
      C.Set_XY_Parameters (Scorer, 5.0, 5.0, 0.0, 0.0, 1.0);
      Composite ("Set_XY_Parameters", [5.0, 5.0, 0.0, 0.0, 1.0],
                 Scorer_Parameters'Access);
      Integer_Sweep ("Kind (forged scorer)", Bad_Integers & [8, 9],
                     Forged_Kind'Access);
      Integer_Sweep ("Enabled (forged scorer)", Bad_Integers & [1, 2],
                     Forged_Enabled'Access);
      Integer_Sweep ("Count (forged list)", Bad_Integers & [8, 9],
                     Forged_Count'Access);
      Check_Kind_9 ("Kind of a scorer of kind 9: Ks_Bad_Parameter_Exception");
      Check_Enabled_2 ("Enabled of a scorer with Enabled = 2:"
                       & " Ks_Bad_Parameter_Exception");
      Check_Count_9 ("Count of a list with Count = 9:"
                     & " Ks_Bad_Parameter_Exception");
      Integer_Sweep ("Add, Remove_At (forged list)", Bad_Integers & [8, 9],
                     Forged_List'Access);
      Integer_Sweep ("Remove_At", Bad_Indices, Remove'Access, True);
      Try ("Add beyond the limit", Full'Access);
      End_Area;
   end Sweep_Caliper;

   ---------------------------------------------------------------------
   --  Find Line, Find Circle
   ---------------------------------------------------------------------

   procedure Sweep_Find_Line is
      package F renames AMV.Caliper.Find_Line;
      procedure Prepare (T : in out F.Ks_Find_Line_Tool) is
      begin
         T.Input_Image := Small;
         T.Run_Params.Expected_Line_Segment.Set_Start_End (11.0, 5.0, 13.0,
                                                          35.0);
         T.Run_Params.Caliper_Search_Length := 10.0;
         T.Run_Params.Caliper_Projection_Length := 4.0;
         T.Run_Params.Num_Calipers := 5;
      end Prepare;
      procedure Use_Results (T : F.Ks_Find_Line_Tool; Call : String) is
         procedure Read is
         begin
            for I in 0 .. T.Results.Count - 1 loop
               Consume (T.Results.Item (I).X);
               Consume (T.Results.Item (I).Caliper_Results.Count);
            end loop;
            Consume (T.Results.Get_Line.Rotation);
         end Read;
         procedure Read_2 is
         begin
            Consume (T.Results.Get_Line_Segment.Length);
         end Read_2;
         procedure Read_3 is
         begin
            Consume (T.Results.RMS_Error);
            Consume (T.Results.Num_Points_Found);
            Consume (T.Results.Num_Points_Used);
         end Read_3;
         procedure Beyond (Index : Integer) is
         begin
            Consume (T.Results.Item (Index).Y);
         end Beyond;
         procedure Region (Index : Integer) is
         begin
            Consume (F.Get_Caliper_Region (T.Run_Params, Index).Center_X);
         end Region;
      begin
         Try (Call & " / results", Read'Access);
         Try (Call & " / Get_Line_Segment", Read_2'Access);
         Try (Call & " / RMS_Error", Read_3'Access);
         Integer_Sweep (Call & " / Item", [T.Results.Count, Natural'Last],
                        Beyond'Access, True);
         Integer_Sweep (Call & " / Get_Caliper_Region", Bad_Indices,
                        Region'Access, True);
      end Use_Results;
      package S is new Sweeps (F.Ks_Find_Line_Tool, "FindLine", Prepare,
                               Use_Results);
      procedure Set_Image (T : in out F.Ks_Find_Line_Tool; Field : Positive;
                           I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         T.Input_Image := I;
      end Set_Image;
      procedure Set_Real (T : in out F.Ks_Find_Line_Tool; Field : Positive;
                          V : Real) is
      begin
         case Field is
            when 1 => T.Run_Params.Caliper_Search_Length := V;
            when 2 => T.Run_Params.Caliper_Projection_Length := V;
            when 3 => T.Run_Params.Caliper_Search_Direction := V;
            when 4 .. 7 =>
               T.Run_Params.Expected_Line_Segment :=
                 Segment_With (Field - 3, V);
            when others =>
               Set_Caliper_Real (T.Run_Params.Caliper_Run_Params, Field - 7,
                                 V);
         end case;
      end Set_Real;
      procedure Set_Integer (T : in out F.Ks_Find_Line_Tool;
                             Field : Positive; V : Integer) is
      begin
         case Field is
            when 1 => T.Run_Params.Num_Calipers := V;
            when 2 => T.Run_Params.Num_To_Ignore := V;
            when 3 =>
               T.Run_Params.Decrement_Num_To_Ignore := True;
               T.Run_Params.Num_To_Ignore := V;
            when others =>
               Set_Caliper_Integer (T.Run_Params.Caliper_Run_Params,
                                    Field - 3, V);
         end case;
      end Set_Integer;
      procedure Set_Name (T : in out F.Ks_Find_Line_Tool; Field : Positive;
                          V : String) is
         pragma Unreferenced (Field);
      begin
         T.Run_Params.Expected_Line_Segment.Set_Selected_Space_Name (V);
      end Set_Name;
   begin
      Begin_Area ("Find Line", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage", Set_Image'Access);
      S.Reals ("CaliperSearchLength,CaliperProjectionLength,"
               & "CaliperSearchDirection,ExpectedLineSegment.StartX,"
               & "ExpectedLineSegment.StartY,ExpectedLineSegment.EndX,"
               & "ExpectedLineSegment.EndY," & Caliper_Real_Fields,
               Set_Real'Access);
      S.Integers ("NumCalipers,NumToIgnore,NumToIgnore (decremented),"
                  & Caliper_Integer_Fields, Set_Integer'Access);
      S.Strings ("ExpectedLineSegment.SelectedSpaceName", Set_Name'Access);
      End_Area;
   end Sweep_Find_Line;

   procedure Sweep_Find_Circle is
      package F renames AMV.Caliper.Find_Circle;
      procedure Prepare (T : in out F.Ks_Find_Circle_Tool) is
      begin
         T.Input_Image := Small;
         T.Run_Params.Expected_Circular_Arc := Arc_With (0, 0.0);
         T.Run_Params.Caliper_Search_Length := 6.0;
         T.Run_Params.Caliper_Projection_Length := 3.0;
         T.Run_Params.Num_Calipers := 8;
      end Prepare;
      procedure Use_Results (T : F.Ks_Find_Circle_Tool; Call : String) is
         procedure Read is
         begin
            for I in 0 .. T.Results.Count - 1 loop
               Consume (T.Results.Item (I).X);
               Consume (T.Results.Item (I).Caliper_Results.Count);
            end loop;
            Consume (T.Results.Get_Circle.Radius);
         end Read;
         procedure Read_2 is
         begin
            Consume (T.Results.Get_Circular_Arc.Radius);
         end Read_2;
         procedure Read_3 is
         begin
            Consume (T.Results.RMS_Error);
            Consume (T.Results.Num_Points_Found);
            Consume (T.Results.Num_Points_Used);
         end Read_3;
         procedure Beyond (Index : Integer) is
         begin
            Consume (T.Results.Item (Index).Y);
         end Beyond;
         procedure Region (Index : Integer) is
         begin
            Consume (F.Get_Caliper_Region (T.Run_Params, Index).Center_X);
         end Region;
      begin
         Try (Call & " / results", Read'Access);
         Try (Call & " / Get_Circular_Arc", Read_2'Access);
         Try (Call & " / RMS_Error", Read_3'Access);
         Integer_Sweep (Call & " / Item", [T.Results.Count, Natural'Last],
                        Beyond'Access, True);
         Integer_Sweep (Call & " / Get_Caliper_Region", Bad_Indices,
                        Region'Access, True);
      end Use_Results;
      package S is new Sweeps (F.Ks_Find_Circle_Tool, "FindCircle", Prepare,
                               Use_Results);
      procedure Set_Image (T : in out F.Ks_Find_Circle_Tool;
                           Field : Positive; I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         T.Input_Image := I;
      end Set_Image;
      procedure Set_Real (T : in out F.Ks_Find_Circle_Tool;
                          Field : Positive; V : Real) is
      begin
         case Field is
            when 1 => T.Run_Params.Caliper_Search_Length := V;
            when 2 => T.Run_Params.Caliper_Projection_Length := V;
            when 3 =>
               T.Run_Params.Radius_Constraint_Enabled := True;
               T.Run_Params.Radius_Constraint := V;
            when 4 .. 8 =>
               T.Run_Params.Expected_Circular_Arc := Arc_With (Field - 3, V);
            when others =>
               Set_Caliper_Real (T.Run_Params.Caliper_Run_Params, Field - 8,
                                 V);
         end case;
      end Set_Real;
      procedure Set_Integer (T : in out F.Ks_Find_Circle_Tool;
                             Field : Positive; V : Integer) is
      begin
         case Field is
            when 1 => T.Run_Params.Num_Calipers := V;
            when 2 => T.Run_Params.Num_To_Ignore := V;
            when 3 =>
               T.Run_Params.Decrement_Num_To_Ignore := True;
               T.Run_Params.Caliper_Search_Direction := F.Outward;
               T.Run_Params.Num_To_Ignore := V;
            when others =>
               Set_Caliper_Integer (T.Run_Params.Caliper_Run_Params,
                                    Field - 3, V);
         end case;
      end Set_Integer;
      procedure Set_Name (T : in out F.Ks_Find_Circle_Tool;
                          Field : Positive; V : String) is
         pragma Unreferenced (Field);
      begin
         T.Run_Params.Expected_Circular_Arc.Set_Selected_Space_Name (V);
      end Set_Name;
   begin
      Begin_Area ("Find Circle", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage", Set_Image'Access);
      S.Reals ("CaliperSearchLength,CaliperProjectionLength,"
               & "RadiusConstraint,"
               & Prefixed ("ExpectedCircularArc", Arc_Fields) & ","
               & Caliper_Real_Fields, Set_Real'Access);
      S.Integers ("NumCalipers,NumToIgnore,NumToIgnore (decremented),"
                  & Caliper_Integer_Fields, Set_Integer'Access);
      S.Strings ("ExpectedCircularArc.SelectedSpaceName", Set_Name'Access);
      End_Area;
   end Sweep_Find_Circle;

   ---------------------------------------------------------------------
   --  Image processing tools
   ---------------------------------------------------------------------

   procedure Sweep_Histogram is
      package H renames AMV.Image_Processing.Histogram;
      procedure Prepare (T : in out H.Ks_Histogram_Tool) is
      begin
         T.Input_Image := Small;
      end Prepare;
      procedure Use_Results (T : H.Ks_Histogram_Tool; Call : String) is
         procedure Read is
         begin
            Consume (T.Result.Num_Samples);
            Consume (T.Result.Mean + T.Result.Standard_Deviation
                     + T.Result.Variance);
            Consume (T.Result.Minimum + T.Result.Maximum + T.Result.Median
                     + T.Result.Mode);
            Consume (Integer (H.Get_Histogram (T.Result)'Length));
            Consume (T.Result.Get_Minimum_WGV_Threshold);
         end Read;
         procedure Percent (Value : Integer) is
         begin
            Consume (T.Result.Get_Inverse_Cumulative_Grey_Level (Value));
         end Percent;
      begin
         Try (Call & " / result", Read'Access);
         Integer_Sweep (Call & " / Get_Inverse_Cumulative_Grey_Level",
                        Bad_Integers & [50, 100, 101], Percent'Access);
      end Use_Results;
      package S is new Sweeps (H.Ks_Histogram_Tool, "Histogram", Prepare,
                               Use_Results);
      procedure Set_Image (T : in out H.Ks_Histogram_Tool; Field : Positive;
                           I : Ks_Image_8_Grey) is
      begin
         if Field = 1 then
            T.Input_Image := I;
         else
            T.Input_Image_Mask := I;
         end if;
      end Set_Image;
      procedure Set_Integer (T : in out H.Ks_Histogram_Tool;
                             Field : Positive; V : Integer) is
      begin
         case Field is
            when 1 => T.Run_Params.Bin_Mode := Int32 (V);
            when 2 =>
               T.Run_Params.Bin_Mode := H.Uniform;
               T.Run_Params.Num_Bins := Int32 (V);
            when 3 =>
               T.Input_Image_Mask := Small;
               T.Input_Image_Mask_Offset_X := V;
            when 4 =>
               T.Input_Image_Mask := Small;
               T.Input_Image_Mask_Offset_Y := V;
            when others => T.Region_Mode := Int32 (V);
         end case;
      end Set_Integer;
      procedure Set_Region (T : in out H.Ks_Histogram_Tool;
                            R : Ks_Region'Class) is
      begin
         T.Region := RH.To_Holder (R);
      end Set_Region;
      procedure Set_Region_Box (T : in out H.Ks_Histogram_Tool;
                                R : Ks_Region'Class) is
      begin
         T.Region := RH.To_Holder (R);
         T.Region_Mode := H.Pixel_Aligned_Bounding_Box;
      end Set_Region_Box;
      procedure Set_Region_Affine (T : in out H.Ks_Histogram_Tool;
                                   R : Ks_Region'Class) is
      begin
         T.Region := RH.To_Holder (R);
         T.Region_Mode := H.Affine_Transform;
      end Set_Region_Affine;
   begin
      Begin_Area ("Histogram", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage,InputImageMask", Set_Image'Access);
      S.Integers ("BinMode,NumBins,InputImageMaskOffsetX,"
                  & "InputImageMaskOffsetY,RegionMode", Set_Integer'Access);
      S.Regions ("Region", All_Regions, Set_Region'Access);
      S.Regions ("Region (PixelAlignedBoundingBox)", All_Regions,
                 Set_Region_Box'Access);
      S.Regions ("Region (AffineTransform)", All_Regions,
                 Set_Region_Affine'Access);
      End_Area;
   end Sweep_Histogram;

   procedure Sweep_Pixel_Map is
      package P renames AMV.Image_Processing.Pixel_Map;
      procedure Prepare (T : in out P.Ks_Pixel_Map_Tool) is
      begin
         T.Input_Image := Small;
      end Prepare;
      package S is new Sweeps (P.Ks_Pixel_Map_Tool, "PixelMap", Prepare);
      procedure Set_Image (T : in out P.Ks_Pixel_Map_Tool; Field : Positive;
                           I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         T.Input_Image := I;
      end Set_Image;
      procedure Set_Region (T : in out P.Ks_Pixel_Map_Tool;
                            R : Ks_Region'Class) is
      begin
         T.Region := RH.To_Holder (R);
      end Set_Region;
   begin
      Begin_Area ("Pixel Map", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage", Set_Image'Access);
      S.Regions ("Region", All_Regions, Set_Region'Access);
      End_Area;
   end Sweep_Pixel_Map;

   procedure Sweep_Sobel_Edge is
      package P renames AMV.Image_Processing.Sobel_Edge;
      procedure Prepare (T : in out P.Ks_Sobel_Edge_Tool) is
      begin
         T.Input_Image := Small;
      end Prepare;
      procedure Use_Results (T : P.Ks_Sobel_Edge_Tool; Call : String) is
         procedure Read is
         begin
            Consume (T.Result.Edge_Magnitude_Image.Width);
            Consume (T.Result.Edge_Angle_Image.Width);
            Consume (T.Result.Final_Magnitude_Image.Width);
         end Read;
      begin
         Try (Call & " / result images", Read'Access);
      end Use_Results;
      package S is new Sweeps (P.Ks_Sobel_Edge_Tool, "SobelEdge", Prepare,
                               Use_Results);
      procedure Set_Image (T : in out P.Ks_Sobel_Edge_Tool; Field : Positive;
                           I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         T.Input_Image := I;
      end Set_Image;
      procedure Set_Real (T : in out P.Ks_Sobel_Edge_Tool; Field : Positive;
                          V : Real) is
         pragma Unreferenced (Field);
      begin
         T.Run_Params.Magnitude_Scale := V;
      end Set_Real;
      procedure Set_Integer (T : in out P.Ks_Sobel_Edge_Tool;
                             Field : Positive; V : Integer) is
         R : P.Ks_Sobel_Edge renames T.Run_Params;
         I : constant Int32 := Int32 (V);
      begin
         case Field is
            when 1 => R.Post_Process_Mode := I;
            when 2 =>
               R.Post_Process_Mode := P.Peak_Detect;
               R.Peak_Detect_Threshold := I;
            when 3 =>
               R.Post_Process_Mode := P.Hysteresis_Threshold;
               R.Hysteresis_Threshold_Low := I;
            when 4 =>
               R.Post_Process_Mode := P.Hysteresis_Threshold;
               R.Hysteresis_Threshold_High := I;
            when 5 =>
               R.Post_Process_Mode := P.Hysteresis_Threshold;
               R.Hysteresis_Survivor_Pel_Value := I;
            when 6 =>
               R.Post_Process_Mode := P.Hysteresis_Threshold;
               R.Hysteresis_Non_Survivor_Pel_Value := I;
            when 7 =>
               R.Post_Process_Mode := P.Hysteresis_Threshold;
               P.Set_Hysteresis_Thresholds (R, V, V);
            when others =>
               declare
                  A : Ks_Rectangle_Affine;
               begin
                  A.Set_Center_Lengths_Rotation_Skew
                    (30.0, 20.0, 20.0, 12.0, 0.3, 0.0);
                  T.Region := RH.To_Holder (A);
               end;
               R.Region_Mode := I;
         end case;
      end Set_Integer;
      procedure Set_Region (T : in out P.Ks_Sobel_Edge_Tool;
                            R : Ks_Region'Class) is
      begin
         T.Region := RH.To_Holder (R);
      end Set_Region;
      procedure Set_Region_Affine (T : in out P.Ks_Sobel_Edge_Tool;
                                   R : Ks_Region'Class) is
      begin
         T.Run_Params.Region_Mode := P.Affine_Transform;
         T.Region := RH.To_Holder (R);
      end Set_Region_Affine;
   begin
      Begin_Area ("Sobel Edge", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage", Set_Image'Access);
      S.Reals ("MagnitudeScale", Set_Real'Access);
      S.Integers ("PostProcessMode,PeakDetectThreshold,"
                  & "HysteresisThresholdLow,HysteresisThresholdHigh,"
                  & "HysteresisSurvivorPelValue,"
                  & "HysteresisNonSurvivorPelValue,"
                  & "Set_Hysteresis_Thresholds,RegionMode",
                  Set_Integer'Access);
      S.Regions ("Region", All_Regions, Set_Region'Access);
      S.Regions ("Region (AffineTransform)", All_Regions,
                 Set_Region_Affine'Access);
      End_Area;
   end Sweep_Sobel_Edge;

   procedure Sweep_Sharpness is
      package P renames AMV.Image_Processing.Sharpness;
      procedure Prepare (T : in out P.Ks_Image_Sharpness_Tool) is
      begin
         T.Input_Image := Small;
      end Prepare;
      package S is new Sweeps (P.Ks_Image_Sharpness_Tool, "ImageSharpness",
                               Prepare);
      procedure Set_Image (T : in out P.Ks_Image_Sharpness_Tool;
                           Field : Positive; I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         T.Input_Image := I;
      end Set_Image;
      procedure Set_Real (T : in out P.Ks_Image_Sharpness_Tool;
                          Field : Positive; V : Real) is
         R : P.Ks_Image_Sharpness renames T.Run_Params;
      begin
         case Field is
            when 1 =>
               R.Mode := P.Auto_Correlation;
               R.Auto_Correlation_Noise_Level := V;
            when 2 =>
               R.Mode := P.Band_Pass;
               R.Band_Pass_Max_Frequency := V;
            when others =>
               R.Mode := P.Band_Pass;
               R.Band_Pass_Min_Frequency := V;
         end case;
      end Set_Real;
      procedure Set_Integer (T : in out P.Ks_Image_Sharpness_Tool;
                             Field : Positive; V : Integer) is
         R : P.Ks_Image_Sharpness renames T.Run_Params;
         I : constant Int32 := Int32 (V);
      begin
         case Field is
            when 1 => R.Mode := I;
            when 2 =>
               R.Mode := P.Abs_Diff;
               R.Abs_Diff_Distance_X := I;
            when 3 =>
               R.Mode := P.Abs_Diff;
               R.Abs_Diff_Distance_Y := I;
            when others =>
               R.Mode := P.Gradient_Energy;
               R.Gradient_Energy_Low_Pass_Smoothing := I;
         end case;
      end Set_Integer;
      procedure Set_Region (T : in out P.Ks_Image_Sharpness_Tool;
                            R : Ks_Region'Class) is
      begin
         T.Region := RH.To_Holder (R);
      end Set_Region;
   begin
      Begin_Area ("Image Sharpness", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage", Set_Image'Access);
      S.Reals ("AutoCorrelationNoiseLevel,BandPassMaxFrequency,"
               & "BandPassMinFrequency", Set_Real'Access);
      S.Integers ("Mode,AbsDiffDistanceX,AbsDiffDistanceY,"
                  & "GradientEnergyLowPassSmoothing", Set_Integer'Access);
      S.Regions ("Region", All_Regions, Set_Region'Access);
      End_Area;
   end Sweep_Sharpness;

   procedure Sweep_IP_One_Image is
      package P renames AMV.Image_Processing.IP_One_Image;
      procedure Prepare (T : in out P.Ks_IP_One_Image_Tool) is
      begin
         T.Input_Image := Small;
      end Prepare;
      package S is new Sweeps (P.Ks_IP_One_Image_Tool, "IPOneImage",
                               Prepare);
      Integer_Fields : constant String :=
        "Kind,Enabled,AddSubtractConstant.ConstantValue,"
        & "AddSubtractConstant.OverflowMode,Convolve3x3.KernelOrigin,"
        & "ConvolveNxM.KernelWidth,ConvolveNxM.KernelHeight,"
        & "ConvolveNxM.BoundaryMode,FlipRotate.Operation,"
        & "GaussSampler.SmoothnessX,GaussSampler.SmoothnessY,"
        & "GaussSampler.MagnitudeShift,GaussSampler.SampleX,"
        & "GaussSampler.SampleY,GreyMorphologyNxM.Operation,"
        & "GreyMorphologyNxM.KernelWidth,GreyMorphologyNxM.KernelHeight,"
        & "MedianNxM.KernelWidth,MedianNxM.KernelHeight,"
        & "MultiplyConstant.OverflowMode,Quantize.Levels,"
        & "BoxFilter.KernelWidth,BoxFilter.KernelHeight,"
        & "Threshold.Threshold,Threshold.LowValue,Threshold.HighValue,"
        & "UnsharpMask.SmoothnessX,UnsharpMask.SmoothnessY,"
        & "Expand.ExpansionX,Expand.ExpansionY,"
        & "HighPassFilter.ProcessingMode,HighPassFilter.SmoothnessX,"
        & "HighPassFilter.SmoothnessY,HighPassFilter.KernelWidth,"
        & "HighPassFilter.KernelHeight,SubSampler.SampleX,"
        & "SubSampler.SampleY,SubSampler.SpatialAverage,PelSet.Operation,"
        & "PelSet.PelValue,PelSet.InputImageMaskOffsetX,"
        & "PelSet.InputImageMaskOffsetY,Operators.Count,RegionMode";
      function Operator_For
        (Kind : P.Ks_IP_One_Image_Operator_Kind) return P.Ks_IP_One_Image_Operator
        renames P.New_Operator;
      procedure Set_Integer (T : in out P.Ks_IP_One_Image_Tool;
                             Field : Positive; V : Integer) is
         use P;
         I  : constant Int32 := Int32 (V);
         Op : Ks_IP_One_Image_Operator;
      begin
         case Field is
            when 1 =>
               Op := Operator_For (Threshold);
               Op.Kind := I;
            when 2 =>
               Op := Operator_For (Threshold);
               Op.Enabled := I;
            when 3 =>
               Op := Operator_For (Add_Subtract_Constant);
               Op.Add_Subtract_Constant.Constant_Value := I;
            when 4 =>
               Op := Operator_For (Add_Subtract_Constant);
               Op.Add_Subtract_Constant.Overflow_Mode := I;
            when 5 =>
               Op := Operator_For (Convolve_3x3);
               Op.Convolve_3x3.Kernel_Origin := I;
            when 6 =>
               Op := Operator_For (Convolve_NxM);
               Op.Convolve_NxM.Kernel_Width := I;
            when 7 =>
               Op := Operator_For (Convolve_NxM);
               Op.Convolve_NxM.Kernel_Height := I;
            when 8 =>
               Op := Operator_For (Convolve_NxM);
               Op.Convolve_NxM.Boundary_Mode := I;
            when 9 =>
               Op := Operator_For (Flip_Rotate);
               Op.Flip_Rotate.Operation_In_Pixel_Space := I;
            when 10 =>
               Op := Operator_For (Gauss_Sampler);
               Op.Gauss_Sampler.Smoothness_X := I;
            when 11 =>
               Op := Operator_For (Gauss_Sampler);
               Op.Gauss_Sampler.Smoothness_Y := I;
            when 12 =>
               Op := Operator_For (Gauss_Sampler);
               Op.Gauss_Sampler.Magnitude_Shift := I;
            when 13 =>
               Op := Operator_For (Gauss_Sampler);
               Op.Gauss_Sampler.Sample_X := I;
            when 14 =>
               Op := Operator_For (Gauss_Sampler);
               Op.Gauss_Sampler.Sample_Y := I;
            when 15 =>
               Op := Operator_For (Grey_Morphology_NxM);
               Op.Grey_Morphology_NxM.Operation := I;
            when 16 =>
               Op := Operator_For (Grey_Morphology_NxM);
               Op.Grey_Morphology_NxM.Kernel_Width := I;
            when 17 =>
               Op := Operator_For (Grey_Morphology_NxM);
               Op.Grey_Morphology_NxM.Kernel_Height := I;
            when 18 =>
               Op := Operator_For (Median_NxM);
               Op.Median_NxM.Kernel_Width := I;
            when 19 =>
               Op := Operator_For (Median_NxM);
               Op.Median_NxM.Kernel_Height := I;
            when 20 =>
               Op := Operator_For (Multiply_Constant);
               Op.Multiply_Constant.Overflow_Mode := I;
            when 21 =>
               Op := Operator_For (Quantize);
               Op.Quantize.Levels := I;
            when 22 =>
               Op := Operator_For (Box_Filter);
               Op.Box_Filter.Kernel_Width := I;
            when 23 =>
               Op := Operator_For (Box_Filter);
               Op.Box_Filter.Kernel_Height := I;
            when 24 =>
               Op := Operator_For (Threshold);
               Op.Threshold.Threshold := I;
            when 25 =>
               Op := Operator_For (Threshold);
               Op.Threshold.Low_Value := I;
            when 26 =>
               Op := Operator_For (Threshold);
               Op.Threshold.High_Value := I;
            when 27 =>
               Op := Operator_For (Unsharp_Mask);
               Op.Unsharp_Mask.Smoothness_X := I;
            when 28 =>
               Op := Operator_For (Unsharp_Mask);
               Op.Unsharp_Mask.Smoothness_Y := I;
            when 29 =>
               Op := Operator_For (Expand);
               Op.Expand.Expansion_X := I;
            when 30 =>
               Op := Operator_For (Expand);
               Op.Expand.Expansion_Y := I;
            when 31 =>
               Op := Operator_For (High_Pass_Filter);
               Op.High_Pass_Filter.Processing_Mode := I;
            when 32 =>
               Op := Operator_For (High_Pass_Filter);
               Op.High_Pass_Filter.Smoothness_X := I;
            when 33 =>
               Op := Operator_For (High_Pass_Filter);
               Op.High_Pass_Filter.Smoothness_Y := I;
            when 34 =>
               Op := Operator_For (High_Pass_Filter);
               Op.High_Pass_Filter.Processing_Mode :=
                 P.Code (P.Mean);
               Op.High_Pass_Filter.Kernel_Width := I;
            when 35 =>
               Op := Operator_For (High_Pass_Filter);
               Op.High_Pass_Filter.Processing_Mode :=
                 P.Code (P.Median);
               Op.High_Pass_Filter.Kernel_Height := I;
            when 36 =>
               Op := Operator_For (Sub_Sampler);
               Op.Sub_Sampler.Sample_X := I;
            when 37 =>
               Op := Operator_For (Sub_Sampler);
               Op.Sub_Sampler.Sample_Y := I;
            when 38 =>
               Op := Operator_For (Sub_Sampler);
               Op.Sub_Sampler.Spatial_Average := I;
            when 39 =>
               Op := Operator_For (Pel_Set);
               Op.Pel_Set.Operation := I;
            when 40 =>
               Op := Operator_For (Pel_Set);
               Op.Pel_Set.Pel_Value := I;
            when 41 =>
               Op := Operator_For (Pel_Set);
               T.Input_Image_Masks (0) := Small;
               Op.Pel_Set.Input_Image_Mask_Offset_X := I;
            when 42 =>
               Op := Operator_For (Pel_Set);
               T.Input_Image_Masks (0) := Small;
               Op.Pel_Set.Input_Image_Mask_Offset_Y := I;
            when 43 =>
               Op := Operator_For (Equalize);
               P.Add (T.Operators, Op);
               T.Operators.Count := I;
               return;
            when others =>
               declare
                  C : AMV.Shapes.Ks_Circle;
               begin
                  C.Set_Center_Radius (30.0, 20.0, 9.5);
                  T.Region := RH.To_Holder (C);
               end;
               Op := Operator_For (Median_NxM);
               T.Region_Mode := I;
         end case;
         P.Add (T.Operators, Op);
      end Set_Integer;
      procedure Set_Real (T : in out P.Ks_IP_One_Image_Tool;
                          Field : Positive; V : Real) is
         use P;
         Op : Ks_IP_One_Image_Operator;
      begin
         case Field is
            when 1 =>
               Op := Operator_For (Multiply_Constant);
               Op.Multiply_Constant.Constant_Value := V;
            when 2 =>
               Op := Operator_For (Unsharp_Mask);
               Op.Unsharp_Mask.Amount := V;
            when 3 =>
               Op := Operator_For (Convolve_3x3);
               Op.Convolve_3x3.Kernel (4) := V;
            when others =>
               Op := Operator_For (Convolve_NxM);
               Op.Convolve_NxM.Kernel (4) := V;
         end case;
         P.Add (T.Operators, Op);
      end Set_Real;
      procedure Set_Image (T : in out P.Ks_IP_One_Image_Tool;
                           Field : Positive; I : Ks_Image_8_Grey) is
         use P;
      begin
         case Field is
            when 1 =>
               T.Input_Image := I;
            when 2 =>
               P.Add (T.Operators, Operator_For (Flip_Rotate));
               T.Input_Image := I;
            when 3 =>
               P.Add (T.Operators, Operator_For (Expand));
               T.Input_Image := I;
            when others =>
               P.Add (T.Operators, Operator_For (Pel_Set));
               T.Input_Image_Masks (0) := I;
         end case;
      end Set_Image;
      procedure Set_Region (T : in out P.Ks_IP_One_Image_Tool;
                            R : Ks_Region'Class) is
      begin
         P.Add (T.Operators, P.New_Operator (P.Median_3x3));
         T.Region := RH.To_Holder (R);
      end Set_Region;
      procedure Every_Kind is
         T : P.Ks_IP_One_Image_Tool;
      begin
         for Kind in P.Ks_IP_One_Image_Operator_Kind loop
            Prepare (T);
            P.Clear (T.Operators);
            P.Add (T.Operators, P.New_Operator (Kind));
            for Image_Kind in Image_Case loop
               T.Input_Image := Test_Image (Image_Kind);
               Run_Tool (T, "IPOneImage " & Kind'Image & " on "
                         & Image_Kind'Image);
            end loop;
         end loop;
      end Every_Kind;
      Ops : P.Ks_IP_One_Image_Operators;
      procedure Index_Ops (Index : Integer) is
         O : constant P.Ks_IP_One_Image_Operators := Ops;
      begin
         Consume (P.Kind (P.Item (O, Index))'Image);
      end Index_Ops;
      procedure Index_Ops_2 (Index : Integer) is
         O : P.Ks_IP_One_Image_Operators := Ops;
      begin
         P.Set_Item (O, Index, P.New_Operator (P.Equalize));
      end Index_Ops_2;
      procedure Index_Ops_3 (Index : Integer) is
         O : P.Ks_IP_One_Image_Operators := Ops;
      begin
         P.Insert (O, P.New_Operator (P.Equalize), Index);
      end Index_Ops_3;
      procedure Index_Ops_4 (Index : Integer) is
         O : P.Ks_IP_One_Image_Operators := Ops;
      begin
         P.Remove_At (O, Index);
      end Index_Ops_4;
      procedure Index_Ops_5 (Index : Integer) is
         O : P.Ks_IP_One_Image_Operators := Ops;
      begin
         P.Move (O, Index, 0);
         P.Move (O, 0, Index);
      end Index_Ops_5;
      procedure Forged_Kind (Value : Integer) is
         Op : P.Ks_IP_One_Image_Operator := P.New_Operator (P.Equalize);
      begin
         Op.Kind := Int32 (Value);
         Consume (P.Kind (Op)'Image);
      end Forged_Kind;
      procedure Forged_Enabled (Value : Integer) is
         Op : P.Ks_IP_One_Image_Operator := P.New_Operator (P.Equalize);
      begin
         Op.Enabled := Int32 (Value);
         Consume (P.Enabled (Op));
      end Forged_Enabled;
      procedure Forged_Count (Value : Integer) is
         O : P.Ks_IP_One_Image_Operators := Ops;
      begin
         O.Count := Int32 (Value);
         Consume (P.Count (O));
      end Forged_Count;
      procedure Kind_19 is
      begin
         Forged_Kind (19);
      end Kind_19;
      procedure Enabled_2 is
      begin
         Forged_Enabled (2);
      end Enabled_2;
      procedure Count_17 is
      begin
         Forged_Count (17);
      end Count_17;
      procedure Check_Kind_19 is new Check_Raises_Exactly
        (Kind_19, AMV.Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Enabled_2 is new Check_Raises_Exactly
        (Enabled_2, AMV.Ks_Bad_Parameter_Exception'Identity);
      procedure Check_Count_17 is new Check_Raises_Exactly
        (Count_17, AMV.Ks_Bad_Parameter_Exception'Identity);
      procedure Forged_2 (Value : Integer) is
         O : P.Ks_IP_One_Image_Operators := Ops;
      begin
         O.Count := Int32 (Value);
         P.Add (O, P.New_Operator (P.Equalize));
         P.Clear (O);
      end Forged_2;
      procedure Full is
         O : P.Ks_IP_One_Image_Operators;
      begin
         for I in 1 .. 20 loop
            P.Add (O, P.New_Operator (P.Equalize));
         end loop;
      end Full;
      procedure Kernel_Values (Value : Integer) is
         N : P.Ks_IP_One_Image_Convolve_NxM;
      begin
         Consume (P.Get_Kernel_Value (N, Value, 0));
         Consume (P.Get_Kernel_Value (N, 0, Value));
         P.Set_Kernel_Value (N, Value, 1, 1.0);
      end Kernel_Values;
      procedure Kernel_Values_2 (A : Real_List) is
         N : P.Ks_IP_One_Image_Convolve_NxM;
         C : P.Ks_IP_One_Image_Convolve_3x3;
      begin
         P.Set_Kernel_Value (N, 1, 1, A (1));
         P.Set_Kernel_Value (C, P.Center, A (1));
         P.Set_Kernel (C, [others => A (1)]);
         Consume (P.Get_Kernel_Value (C, P.North) + P.Get_Kernel (C) (0));
      end Kernel_Values_2;
      procedure Forged_Kernel (Value : Integer) is
         N : P.Ks_IP_One_Image_Convolve_NxM;
         G : P.Ks_IP_One_Image_Gauss_Sampler;
         H : P.Ks_IP_One_Image_High_Pass_Filter;
      begin
         N.Kernel_Width := Int32 (Value);
         N.Kernel_Height := Int32 (Value);
         G.Smoothness_X := Int32 (Value);
         H.Smoothness_Y := Int32 (Value);
         Consume (P.Sigma_X (G) + P.Sigma_Y (H));
         Consume (P.Get_Kernel_Value (N, 0, 0));
      end Forged_Kernel;
   begin
      Begin_Area ("IP One Image", Is_Tool => True);
      P.Add (Ops, P.New_Operator (P.Equalize));
      P.Add (Ops, P.New_Operator (P.Median_3x3));
      S.Default_Run;
      S.Images ("InputImage,InputImage (FlipRotate),InputImage (Expand),"
                & "InputImageMasks(0)", Set_Image'Access);
      S.Integers (Integer_Fields, Set_Integer'Access);
      S.Reals ("MultiplyConstant.ConstantValue,UnsharpMask.Amount,"
               & "Convolve3x3.Kernel(4),ConvolveNxM.Kernel(4)",
               Set_Real'Access);
      S.Regions ("Region", All_Regions, Set_Region'Access);
      Try ("every operator kind on every image", Every_Kind'Access);
      Integer_Sweep ("Item", Bad_Indices, Index_Ops'Access, True);
      Integer_Sweep ("Set_Item", Bad_Indices, Index_Ops_2'Access, True);
      Integer_Sweep ("Insert", Bad_Indices, Index_Ops_3'Access, True);
      Integer_Sweep ("Remove_At", Bad_Indices, Index_Ops_4'Access, True);
      Integer_Sweep ("Move", Bad_Indices, Index_Ops_5'Access, True);
      Integer_Sweep ("Kind (forged operator)", Bad_Integers & [18, 19],
                     Forged_Kind'Access);
      Integer_Sweep ("Enabled (forged operator)", Bad_Integers & [1, 2],
                     Forged_Enabled'Access);
      Integer_Sweep ("Count (forged list)", Bad_Integers & [16, 17],
                     Forged_Count'Access);
      Check_Kind_19 ("Kind of an operator of kind 19:"
                     & " Ks_Bad_Parameter_Exception");
      Check_Enabled_2 ("Enabled of an operator with Enabled = 2:"
                       & " Ks_Bad_Parameter_Exception");
      Check_Count_17 ("Count of a list with Count = 17:"
                      & " Ks_Bad_Parameter_Exception");
      Integer_Sweep ("Add, Clear (forged list)", Bad_Integers & [16, 17],
                     Forged_2'Access);
      Try ("Add beyond the limit", Full'Access);
      Integer_Sweep ("Get_Kernel_Value, Set_Kernel_Value", Bad_Naturals
                     & [3], Kernel_Values'Access);
      Composite ("Set_Kernel_Value (value)", [1.0], Kernel_Values_2'Access);
      Integer_Sweep ("Sigma_X, Get_Kernel_Value (forged)", Bad_Integers,
                     Forged_Kernel'Access);
      End_Area;
   end Sweep_IP_One_Image;

   procedure Sweep_IP_Two_Image is
      package P renames AMV.Image_Processing.IP_Two_Image;
      procedure Prepare_Add (T : in out P.Ks_IP_Two_Image_Add_Tool) is
      begin
         T.Input_Image_A := Small;
         T.Input_Image_B := Small;
      end Prepare_Add;
      procedure Prepare_Sub (T : in out P.Ks_IP_Two_Image_Subtract_Tool) is
      begin
         T.Input_Image_A := Small;
         T.Input_Image_B := Small;
      end Prepare_Sub;
      procedure Prepare_Min (T : in out P.Ks_IP_Two_Image_Min_Max_Tool) is
      begin
         T.Input_Image_A := Small;
         T.Input_Image_B := Small;
      end Prepare_Min;
      package SA is new Sweeps (P.Ks_IP_Two_Image_Add_Tool, "IPTwoImageAdd",
                                Prepare_Add);
      package SS is new Sweeps (P.Ks_IP_Two_Image_Subtract_Tool,
                                "IPTwoImageSubtract", Prepare_Sub);
      package SM is new Sweeps (P.Ks_IP_Two_Image_Min_Max_Tool,
                                "IPTwoImageMinMax", Prepare_Min);
      procedure Image_Add (T : in out P.Ks_IP_Two_Image_Add_Tool;
                           Field : Positive; I : Ks_Image_8_Grey) is
      begin
         if Field = 1 then
            T.Input_Image_A := I;
         else
            T.Input_Image_B := I;
         end if;
      end Image_Add;
      procedure Image_Sub (T : in out P.Ks_IP_Two_Image_Subtract_Tool;
                           Field : Positive; I : Ks_Image_8_Grey) is
      begin
         if Field = 1 then
            T.Input_Image_A := I;
         else
            T.Input_Image_B := I;
         end if;
      end Image_Sub;
      procedure Image_Min (T : in out P.Ks_IP_Two_Image_Min_Max_Tool;
                           Field : Positive; I : Ks_Image_8_Grey) is
      begin
         if Field = 1 then
            T.Input_Image_A := I;
         else
            T.Input_Image_B := I;
         end if;
      end Image_Min;
      procedure Int_Add (T : in out P.Ks_IP_Two_Image_Add_Tool;
                         Field : Positive; V : Integer) is
         pragma Unreferenced (Field);
      begin
         T.Run_Params.Overflow_Mode := Int32 (V);
      end Int_Add;
      procedure Int_Sub (T : in out P.Ks_IP_Two_Image_Subtract_Tool;
                         Field : Positive; V : Integer) is
         pragma Unreferenced (Field);
      begin
         T.Run_Params.Overflow_Mode := Int32 (V);
      end Int_Sub;
      procedure Int_Min (T : in out P.Ks_IP_Two_Image_Min_Max_Tool;
                         Field : Positive; V : Integer) is
         pragma Unreferenced (Field);
      begin
         T.Run_Params.Operation := Int32 (V);
      end Int_Min;
   begin
      Begin_Area ("IP Two Image Add", Is_Tool => True);
      SA.Default_Run;
      SA.Images ("InputImageA,InputImageB", Image_Add'Access);
      SA.Integers ("OverflowMode", Int_Add'Access);
      End_Area;
      Begin_Area ("IP Two Image Subtract", Is_Tool => True);
      SS.Default_Run;
      SS.Images ("InputImageA,InputImageB", Image_Sub'Access);
      SS.Integers ("OverflowMode", Int_Sub'Access);
      End_Area;
      Begin_Area ("IP Two Image Min Max", Is_Tool => True);
      SM.Default_Run;
      SM.Images ("InputImageA,InputImageB", Image_Min'Access);
      SM.Integers ("Operation", Int_Min'Access);
      End_Area;
   end Sweep_IP_Two_Image;

   procedure Sweep_Affine_Transform is
      package P renames AMV.Image_Processing.Affine_Transform;
      procedure Prepare (T : in out P.Ks_Affine_Transform_Tool) is
      begin
         T.Input_Image := Small;
         T.Region := Ks_Rectangle_Affine (Region_With (Rectangle_Affine, 0,
                                                       0.0));
         T.Create_Output_Image_Mask := True;
      end Prepare;
      package S is new Sweeps (P.Ks_Affine_Transform_Tool, "AffineTransform",
                               Prepare);
      procedure Set_Image (T : in out P.Ks_Affine_Transform_Tool;
                           Field : Positive; I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         T.Input_Image := I;
      end Set_Image;
      procedure Set_Real (T : in out P.Ks_Affine_Transform_Tool;
                          Field : Positive; V : Real) is
      begin
         if Field = 1 then
            T.Run_Params.Scaling_X := V;
         else
            T.Run_Params.Scaling_Y := V;
         end if;
      end Set_Real;
      procedure Set_Integer (T : in out P.Ks_Affine_Transform_Tool;
                             Field : Positive; V : Integer) is
      begin
         case Field is
            when 1 => T.Run_Params.Sampling_Mode := Int32 (V);
            when 2 => T.Run_Params.Clip_Mode := Int32 (V);
            when others =>
               T.Run_Params.Clip_Mode := P.Fill;
               T.Run_Params.Clip_Fill_Value := Int32 (V);
         end case;
      end Set_Integer;
      procedure Set_Region (T : in out P.Ks_Affine_Transform_Tool;
                            R : Ks_Region'Class) is
      begin
         T.Region := Ks_Rectangle_Affine (R);
      end Set_Region;
   begin
      Begin_Area ("Affine Transform", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage", Set_Image'Access);
      S.Reals ("ScalingX,ScalingY", Set_Real'Access);
      S.Integers ("SamplingMode,ClipMode,ClipFillValue", Set_Integer'Access);
      S.Regions ("Region", [Rectangle_Affine => True, others => False],
                 Set_Region'Access);
      End_Area;
   end Sweep_Affine_Transform;

   procedure Sweep_Copy_Region is
      package P renames AMV.Image_Processing.Copy_Region;
      procedure Prepare (T : in out P.Ks_Copy_Region_Tool) is
      begin
         T.Input_Image := Small;
         T.Region := RH.To_Holder (Region_With (Rectangle_Affine, 0, 0.0));
      end Prepare;
      package S is new Sweeps (P.Ks_Copy_Region_Tool, "CopyRegion",
                               Prepare);
      procedure Set_Image (T : in out P.Ks_Copy_Region_Tool;
                           Field : Positive; I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         T.Input_Image := I;
      end Set_Image;
      procedure Set_Integer (T : in out P.Ks_Copy_Region_Tool;
                             Field : Positive; V : Integer) is
         I : constant Int32 := Int32 (V);
      begin
         case Field is
            when 1 => T.Run_Params.Fill_Bounding_Box := I;
            when 2 => T.Run_Params.Fill_Bounding_Box_Value := I;
            when 3 => T.Run_Params.Fill_Region := I;
            when 4 =>
               P.Set_Fill_Region (T.Run_Params, True);
               T.Run_Params.Fill_Region_Value := I;
            when 5 => T.Run_Params.Region_Mode := I;
            when others =>
               T.Run_Params.Region_Mode := P.Affine_Transform;
               P.Set_Fill_Region (T.Run_Params, True);
               T.Run_Params.Fill_Region_Value := I;
         end case;
      end Set_Integer;
      procedure Set_Region (T : in out P.Ks_Copy_Region_Tool;
                            R : Ks_Region'Class) is
      begin
         T.Region := RH.To_Holder (R);
      end Set_Region;
      procedure Set_Region_Affine (T : in out P.Ks_Copy_Region_Tool;
                                   R : Ks_Region'Class) is
      begin
         T.Run_Params.Region_Mode := P.Affine_Transform;
         T.Region := RH.To_Holder (R);
      end Set_Region_Affine;
   begin
      Begin_Area ("Copy Region", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage", Set_Image'Access);
      S.Integers ("FillBoundingBox,FillBoundingBoxValue,FillRegion,"
                  & "FillRegionValue,RegionMode,"
                  & "FillRegionValue (affine mode)", Set_Integer'Access);
      S.Regions ("Region", All_Regions, Set_Region'Access);
      S.Regions ("Region (affine mode)", All_Regions,
                 Set_Region_Affine'Access);
      End_Area;
   end Sweep_Copy_Region;

   procedure Sweep_Polar_Unwrap is
      package P renames AMV.Image_Processing.Polar_Unwrap;
      procedure Prepare (T : in out P.Ks_Polar_Unwrap_Tool) is
      begin
         T.Input_Image := Small;
         T.Region := Ks_Circular_Annulus_Section
           (Region_With (Annulus_Section, 0, 0.0));
      end Prepare;
      package S is new Sweeps (P.Ks_Polar_Unwrap_Tool, "PolarUnwrap",
                               Prepare);
      procedure Set_Image (T : in out P.Ks_Polar_Unwrap_Tool;
                           Field : Positive; I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         T.Input_Image := I;
      end Set_Image;
      procedure Set_Real (T : in out P.Ks_Polar_Unwrap_Tool;
                          Field : Positive; V : Real) is
      begin
         if Field = 1 then
            T.Run_Params.Scaling_X := V;
         else
            T.Run_Params.Scaling_Y := V;
         end if;
      end Set_Real;
      procedure Set_Integer (T : in out P.Ks_Polar_Unwrap_Tool;
                             Field : Positive; V : Integer) is
         pragma Unreferenced (Field);
      begin
         T.Run_Params.Sampling_Mode := Int32 (V);
      end Set_Integer;
      procedure Set_Region (T : in out P.Ks_Polar_Unwrap_Tool;
                            R : Ks_Region'Class) is
      begin
         T.Region := Ks_Circular_Annulus_Section (R);
      end Set_Region;
      Annulus : constant Ks_Circular_Annulus_Section :=
        Ks_Circular_Annulus_Section (Region_With (Annulus_Section, 0, 0.0));
      Params : P.Ks_Polar_Unwrap;
      procedure Points (A : Real_List) is
         X, Y : Real;
      begin
         P.Get_Input_Point_From_Output_Point (Params, Small, Annulus,
                                              A (1), A (2), X, Y);
         P.Get_Output_Point_From_Input_Point (Params, Small, Annulus,
                                              A (1), A (2), X, Y);
         Consume (X + Y);
      end Points;
      procedure Points_2 (Field : Positive; Value : Real) is
         Q : P.Ks_Polar_Unwrap := Params;
         X, Y : Real;
      begin
         if Field = 1 then
            Q.Scaling_X := Value;
         else
            Q.Scaling_Y := Value;
         end if;
         P.Get_Input_Point_From_Output_Point (Q, Small, Annulus, 1.0, 1.0,
                                              X, Y);
         P.Get_Output_Point_From_Input_Point (Q, Small, Annulus, 30.0, 20.0,
                                              X, Y);
         Consume (X + Y);
      end Points_2;
      procedure Points_3 (Field : Positive; Value : Real) is
         X, Y : Real;
      begin
         P.Get_Output_Point_From_Input_Point
           (Params, Small,
            Ks_Circular_Annulus_Section
              (Region_With (Annulus_Section, Field, Value)),
            30.0, 20.0, X, Y);
         P.Get_Input_Point_From_Output_Point
           (Params, Test_Image (Pixel_From_Root_1E140),
            Ks_Circular_Annulus_Section
              (Region_With (Annulus_Section, Field, Value)),
            1.0, 1.0, X, Y);
         Consume (X + Y);
      end Points_3;
      procedure Revolution (Value : Integer) is
         X, Y : Real;
      begin
         P.Get_Output_Point_From_Input_Point (Params, Small, Annulus, 30.0,
                                              20.0, X, Y, Value);
         Consume (X + Y);
      end Revolution;
      procedure No_Pixels is
         X, Y : Real;
      begin
         P.Get_Output_Point_From_Input_Point (Params, No_Image, Annulus,
                                              30.0, 20.0, X, Y);
         Consume (X + Y);
      end No_Pixels;
   begin
      Begin_Area ("Polar Unwrap", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage", Set_Image'Access);
      S.Reals ("ScalingX,ScalingY", Set_Real'Access);
      S.Integers ("SamplingMode", Set_Integer'Access);
      S.Regions ("Region", [Annulus_Section => True, others => False],
                 Set_Region'Access);
      Composite ("Get_Input/Output_Point (points)", [1.0, 2.0],
                 Points'Access);
      Field_Sweep ("Get_Input/Output_Point (scalings)", 2, Points_2'Access);
      Field_Sweep ("Get_Input/Output_Point (annulus)", 6, Points_3'Access);
      Integer_Sweep ("Get_Output_Point_From_Input_Point (revolution)",
                     Bad_Integers, Revolution'Access);
      Try ("Get_Output_Point_From_Input_Point (unallocated)",
           No_Pixels'Access);
      End_Area;
   end Sweep_Polar_Unwrap;

   procedure Sweep_Image_Convert is
      package P renames AMV.Image_Processing.Image_Convert;
      Colour  : constant Ks_Image_24_Planar_Color := Create (16, 12, 10, 200,
                                                             30);
      Grey_16 : constant Ks_Image_16_Grey := Create (16, 12, 40_000);
      procedure Prepare (T : in out P.Ks_Image_Convert_Tool) is
      begin
         T.Input_Image := IH.To_Holder (Small);
      end Prepare;
      package S is new Sweeps (P.Ks_Image_Convert_Tool, "ImageConvert",
                               Prepare);
      procedure Set_Image (T : in out P.Ks_Image_Convert_Tool;
                           Field : Positive; I : Ks_Image_8_Grey) is
      begin
         case Field is
            when 1 => T.Input_Image := IH.To_Holder (I);
            when 2 =>
               T.Run_Params.Run_Mode := P.RGB_From_Bayer;
               T.Input_Image := IH.To_Holder (I);
            when others =>
               T.Run_Params.Run_Mode := P.Pixel_From_Range;
               T.Input_Image := IH.To_Holder (I);
         end case;
      end Set_Image;
      procedure Set_Integer (T : in out P.Ks_Image_Convert_Tool;
                             Field : Positive; V : Integer) is
      begin
         case Field is
            when 1 => T.Run_Params.Run_Mode := Int32 (V);
            when 2 =>
               T.Run_Params.Run_Mode := P.Intensity_From_Bayer;
               T.Run_Params.Bayer_Type := Int32 (V);
            when 3 => T.Run_Params.Share_Pels_If_Possible := Int32 (V);
            when 4 =>
               T.Input_Image := IH.To_Holder (Colour);
               T.Run_Params.Run_Mode := Int32 (V);
            when others =>
               T.Input_Image := IH.To_Holder (Grey_16);
               T.Run_Params.Run_Mode := Int32 (V);
         end case;
      end Set_Integer;
      procedure Set_Real (T : in out P.Ks_Image_Convert_Tool;
                          Field : Positive; V : Real) is
         R : P.Ks_Image_Convert_Run_Params renames T.Run_Params;
      begin
         case Field is
            when 1 .. 3 =>
               T.Input_Image := IH.To_Holder (Colour);
               R.Run_Mode := P.Intensity_From_Weighted_RGB;
               case Field is
                  when 1 => R.Intensity_From_Weighted_RGB_Red_Weight := V;
                  when 2 => R.Intensity_From_Weighted_RGB_Green_Weight := V;
                  when others =>
                     R.Intensity_From_Weighted_RGB_Blue_Weight := V;
               end case;
            when 4 .. 6 =>
               R.Run_Mode := P.Intensity_From_Bayer;
               case Field is
                  when 4 => R.Intensity_From_Bayer_Red_Weight := V;
                  when 5 => R.Intensity_From_Bayer_Green_Weight := V;
                  when others => R.Intensity_From_Bayer_Blue_Weight := V;
               end case;
            when others =>
               R.Run_Mode := P.RGB_From_Bayer;
               case Field is
                  when 7 => R.Color_From_Bayer_Red_Scale := V;
                  when 8 => R.Color_From_Bayer_Green_Scale := V;
                  when others => R.Color_From_Bayer_Blue_Scale := V;
               end case;
         end case;
      end Set_Real;
      procedure Other_Inputs is
         T : P.Ks_Image_Convert_Tool;
      begin
         for Mode in P.Ks_Image_Convert_Run_Mode_Constants loop
            T.Run_Params.Run_Mode := Mode;
            T.Input_Image := IH.To_Holder (Colour);
            Run_Tool (T, "ImageConvert colour, mode" & Mode'Image);
            T.Input_Image := IH.To_Holder (Grey_16);
            Run_Tool (T, "ImageConvert 16-bit, mode" & Mode'Image);
            T.Input_Image := IH.Empty_Holder;
            Run_Tool (T, "ImageConvert no image, mode" & Mode'Image);
            T.Input_Image := IH.To_Holder (Ks_Image_16_Grey'(Create (1, 1)));
            Run_Tool (T, "ImageConvert 1 x 1 16-bit, mode" & Mode'Image);
            T.Input_Image := IH.To_Holder (Tiny);
            Run_Tool (T, "ImageConvert 1 x 1, mode" & Mode'Image);
            declare
               C : Ks_Image_24_Planar_Color;
            begin
               T.Input_Image := IH.To_Holder (C);
               Run_Tool (T, "ImageConvert unallocated colour, mode"
                         & Mode'Image);
            end;
         end loop;
      end Other_Inputs;
   begin
      Begin_Area ("Image Convert", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage,InputImage (RGBFromBayer),"
                & "InputImage (PixelFromRange)", Set_Image'Access);
      S.Integers ("RunMode,BayerType,SharePelsIfPossible,"
                  & "RunMode (colour input),RunMode (16-bit input)",
                  Set_Integer'Access);
      S.Reals ("IntensityFromWeightedRGBRedWeight,"
               & "IntensityFromWeightedRGBGreenWeight,"
               & "IntensityFromWeightedRGBBlueWeight,"
               & "IntensityFromBayerRedWeight,IntensityFromBayerGreenWeight,"
               & "IntensityFromBayerBlueWeight,ColorFromBayerRedScale,"
               & "ColorFromBayerGreenScale,ColorFromBayerBlueScale",
               Set_Real'Access);
      Try ("other inputs in every mode", Other_Inputs'Access);
      End_Area;
   end Sweep_Image_Convert;

   ---------------------------------------------------------------------
   --  Dimensioning, fitting and the create shape tools
   ---------------------------------------------------------------------

   generic
      type Tool_Type is new Ks_Tool with private;
      Tool_Name : String;
      Names     : String;
      with procedure Prepare (Tool : in out Tool_Type);
      with procedure Set (Tool : in out Tool_Type; Field : Positive;
                          Value : Real);
      with procedure Set_Image (Tool : in out Tool_Type;
                                Image : Ks_Image_8_Grey);
   procedure Sweep_Geometric_Tool;
   --  The image cases and every numeric input of a dimensioning or create
   --  shape tool.

   procedure Sweep_Geometric_Tool is
      package S is new Sweeps (Tool_Type, Tool_Name, Prepare);
      procedure Set_Of (T : in out Tool_Type; Field : Positive; V : Real) is
      begin
         Set (T, Field, V);
      end Set_Of;
      procedure Image_Of (T : in out Tool_Type; Field : Positive;
                          I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         Set_Image (T, I);
      end Image_Of;
   begin
      Begin_Area (Tool_Name, Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage", Image_Of'Access);
      S.Reals (Names, Set_Of'Access);
      End_Area;
   end Sweep_Geometric_Tool;

   procedure Sweep_Dimensioning is
      package D renames AMV.Dimensioning;

      --  Distance and angle between two points
      procedure P_DPP (T : in out D.Ks_Distance_Point_Point_Tool) is
      begin
         T.Input_Image := Small;
         T.Start_X := 10.0;
         T.Start_Y := 10.0;
         T.End_X := 40.0;
         T.End_Y := 30.0;
      end P_DPP;
      procedure S_DPP (T : in out D.Ks_Distance_Point_Point_Tool;
                       F : Positive; V : Real) is
      begin
         case F is
            when 1 => T.Start_X := V;
            when 2 => T.Start_Y := V;
            when 3 => T.End_X := V;
            when others => T.End_Y := V;
         end case;
      end S_DPP;
      procedure I_DPP (T : in out D.Ks_Distance_Point_Point_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_DPP;
      procedure DPP is new Sweep_Geometric_Tool
        (D.Ks_Distance_Point_Point_Tool, "DistancePointPoint",
         "StartX,StartY,EndX,EndY", P_DPP, S_DPP, I_DPP);

      procedure P_APP (T : in out D.Ks_Angle_Point_Point_Tool) is
      begin
         T.Input_Image := Small;
         T.Start_X := 10.0;
         T.Start_Y := 10.0;
         T.End_X := 40.0;
         T.End_Y := 30.0;
      end P_APP;
      procedure S_APP (T : in out D.Ks_Angle_Point_Point_Tool;
                       F : Positive; V : Real) is
      begin
         case F is
            when 1 => T.Start_X := V;
            when 2 => T.Start_Y := V;
            when 3 => T.End_X := V;
            when others => T.End_Y := V;
         end case;
      end S_APP;
      procedure I_APP (T : in out D.Ks_Angle_Point_Point_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_APP;
      procedure APP is new Sweep_Geometric_Tool
        (D.Ks_Angle_Point_Point_Tool, "AnglePointPoint",
         "StartX,StartY,EndX,EndY", P_APP, S_APP, I_APP);

      --  Angle between two lines
      procedure P_ALL (T : in out D.Ks_Angle_Line_Line_Tool) is
      begin
         T.Input_Image := Small;
         T.Line_A := Line_With (0, 0.0);
         T.Line_B := Line_B_With (0, 0.0);
      end P_ALL;
      procedure S_ALL (T : in out D.Ks_Angle_Line_Line_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 3 then
            T.Line_A := Line_With (F, V);
         else
            T.Line_B := Line_B_With (F - 3, V);
         end if;
      end S_ALL;
      procedure I_ALL (T : in out D.Ks_Angle_Line_Line_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_ALL;
      procedure ALL_Sweep is new Sweep_Geometric_Tool
        (D.Ks_Angle_Line_Line_Tool, "AngleLineLine",
         Prefixed ("LineA", Line_Fields) & ","
         & Prefixed ("LineB", Line_Fields), P_ALL, S_ALL, I_ALL);

      --  Point and line, segment, circle, ellipse
      procedure P_DPL (T : in out D.Ks_Distance_Point_Line_Tool) is
      begin
         T.Input_Image := Small;
         T.X := 5.0;
         T.Y := 40.0;
         T.Line := Line_With (0, 0.0);
      end P_DPL;
      procedure S_DPL (T : in out D.Ks_Distance_Point_Line_Tool;
                       F : Positive; V : Real) is
      begin
         case F is
            when 1 => T.X := V;
            when 2 => T.Y := V;
            when others => T.Line := Line_With (F - 2, V);
         end case;
      end S_DPL;
      procedure I_DPL (T : in out D.Ks_Distance_Point_Line_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_DPL;
      procedure DPL is new Sweep_Geometric_Tool
        (D.Ks_Distance_Point_Line_Tool, "DistancePointLine",
         "X,Y," & Prefixed ("Line", Line_Fields), P_DPL, S_DPL, I_DPL);

      procedure P_DPS (T : in out D.Ks_Distance_Point_Segment_Tool) is
      begin
         T.Input_Image := Small;
         T.X := 5.0;
         T.Y := 40.0;
         T.Segment := Segment_With (0, 0.0);
      end P_DPS;
      procedure S_DPS (T : in out D.Ks_Distance_Point_Segment_Tool;
                       F : Positive; V : Real) is
      begin
         case F is
            when 1 => T.X := V;
            when 2 => T.Y := V;
            when others => T.Segment := Segment_With (F - 2, V);
         end case;
      end S_DPS;
      procedure I_DPS (T : in out D.Ks_Distance_Point_Segment_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_DPS;
      procedure DPS is new Sweep_Geometric_Tool
        (D.Ks_Distance_Point_Segment_Tool, "DistancePointSegment",
         "X,Y," & Prefixed ("Segment", Segment_Fields), P_DPS, S_DPS,
         I_DPS);

      procedure P_DPC (T : in out D.Ks_Distance_Point_Circle_Tool) is
      begin
         T.Input_Image := Small;
         T.X := 5.0;
         T.Y := 40.0;
         T.Input_Circle := Circle_With (0, 0.0);
      end P_DPC;
      procedure S_DPC (T : in out D.Ks_Distance_Point_Circle_Tool;
                       F : Positive; V : Real) is
      begin
         case F is
            when 1 => T.X := V;
            when 2 => T.Y := V;
            when others => T.Input_Circle := Circle_With (F - 2, V);
         end case;
      end S_DPC;
      procedure I_DPC (T : in out D.Ks_Distance_Point_Circle_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_DPC;
      procedure DPC is new Sweep_Geometric_Tool
        (D.Ks_Distance_Point_Circle_Tool, "DistancePointCircle",
         "X,Y," & Prefixed ("InputCircle", Circle_Fields), P_DPC, S_DPC,
         I_DPC);

      procedure P_DPE (T : in out D.Ks_Distance_Point_Ellipse_Tool) is
      begin
         T.Input_Image := Small;
         T.X := 5.0;
         T.Y := 40.0;
         T.Ellipse := Ellipse_With (0, 0.0);
      end P_DPE;
      procedure S_DPE (T : in out D.Ks_Distance_Point_Ellipse_Tool;
                       F : Positive; V : Real) is
      begin
         case F is
            when 1 => T.X := V;
            when 2 => T.Y := V;
            when others => T.Ellipse := Ellipse_With (F - 2, V);
         end case;
      end S_DPE;
      procedure I_DPE (T : in out D.Ks_Distance_Point_Ellipse_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_DPE;
      procedure DPE is new Sweep_Geometric_Tool
        (D.Ks_Distance_Point_Ellipse_Tool, "DistancePointEllipse",
         "X,Y," & Prefixed ("Ellipse", Ellipse_Fields), P_DPE, S_DPE,
         I_DPE);

      --  Two of line, segment, circle, ellipse
      procedure P_DSS (T : in out D.Ks_Distance_Segment_Segment_Tool) is
      begin
         T.Input_Image := Small;
         T.Segment_A := Segment_With (0, 0.0);
         T.Segment_B := Segment_B_With (0, 0.0);
      end P_DSS;
      procedure S_DSS (T : in out D.Ks_Distance_Segment_Segment_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 4 then
            T.Segment_A := Segment_With (F, V);
         else
            T.Segment_B := Segment_B_With (F - 4, V);
         end if;
      end S_DSS;
      procedure I_DSS (T : in out D.Ks_Distance_Segment_Segment_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_DSS;
      procedure DSS is new Sweep_Geometric_Tool
        (D.Ks_Distance_Segment_Segment_Tool, "DistanceSegmentSegment",
         Prefixed ("SegmentA", Segment_Fields) & ","
         & Prefixed ("SegmentB", Segment_Fields), P_DSS, S_DSS, I_DSS);

      procedure P_DSL (T : in out D.Ks_Distance_Segment_Line_Tool) is
      begin
         T.Input_Image := Small;
         T.Segment := Segment_With (0, 0.0);
         T.Line := Line_B_With (0, 0.0);
      end P_DSL;
      procedure S_DSL (T : in out D.Ks_Distance_Segment_Line_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 4 then
            T.Segment := Segment_With (F, V);
         else
            T.Line := Line_B_With (F - 4, V);
         end if;
      end S_DSL;
      procedure I_DSL (T : in out D.Ks_Distance_Segment_Line_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_DSL;
      procedure DSL is new Sweep_Geometric_Tool
        (D.Ks_Distance_Segment_Line_Tool, "DistanceSegmentLine",
         Prefixed ("Segment", Segment_Fields) & ","
         & Prefixed ("Line", Line_Fields), P_DSL, S_DSL, I_DSL);

      procedure P_DLC (T : in out D.Ks_Distance_Line_Circle_Tool) is
      begin
         T.Input_Image := Small;
         T.Line := Line_With (0, 0.0);
         T.Input_Circle := Circle_With (0, 0.0);
      end P_DLC;
      procedure S_DLC (T : in out D.Ks_Distance_Line_Circle_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 3 then
            T.Line := Line_With (F, V);
         else
            T.Input_Circle := Circle_With (F - 3, V);
         end if;
      end S_DLC;
      procedure I_DLC (T : in out D.Ks_Distance_Line_Circle_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_DLC;
      procedure DLC is new Sweep_Geometric_Tool
        (D.Ks_Distance_Line_Circle_Tool, "DistanceLineCircle",
         Prefixed ("Line", Line_Fields) & ","
         & Prefixed ("InputCircle", Circle_Fields), P_DLC, S_DLC, I_DLC);

      procedure P_DSC (T : in out D.Ks_Distance_Segment_Circle_Tool) is
      begin
         T.Input_Image := Small;
         T.Segment := Segment_With (0, 0.0);
         T.Input_Circle := Circle_With (0, 0.0);
      end P_DSC;
      procedure S_DSC (T : in out D.Ks_Distance_Segment_Circle_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 4 then
            T.Segment := Segment_With (F, V);
         else
            T.Input_Circle := Circle_With (F - 4, V);
         end if;
      end S_DSC;
      procedure I_DSC (T : in out D.Ks_Distance_Segment_Circle_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_DSC;
      procedure DSC is new Sweep_Geometric_Tool
        (D.Ks_Distance_Segment_Circle_Tool, "DistanceSegmentCircle",
         Prefixed ("Segment", Segment_Fields) & ","
         & Prefixed ("InputCircle", Circle_Fields), P_DSC, S_DSC, I_DSC);

      procedure P_DCC (T : in out D.Ks_Distance_Circle_Circle_Tool) is
      begin
         T.Input_Image := Small;
         T.Circle_A := Circle_With (0, 0.0);
         T.Circle_B := Circle_B_With (0, 0.0);
      end P_DCC;
      procedure S_DCC (T : in out D.Ks_Distance_Circle_Circle_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 3 then
            T.Circle_A := Circle_With (F, V);
         else
            T.Circle_B := Circle_B_With (F - 3, V);
         end if;
      end S_DCC;
      procedure I_DCC (T : in out D.Ks_Distance_Circle_Circle_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_DCC;
      procedure DCC is new Sweep_Geometric_Tool
        (D.Ks_Distance_Circle_Circle_Tool, "DistanceCircleCircle",
         Prefixed ("CircleA", Circle_Fields) & ","
         & Prefixed ("CircleB", Circle_Fields), P_DCC, S_DCC, I_DCC);

      procedure P_DLE (T : in out D.Ks_Distance_Line_Ellipse_Tool) is
      begin
         T.Input_Image := Small;
         T.Line := Line_With (0, 0.0);
         T.Ellipse := Ellipse_With (0, 0.0);
      end P_DLE;
      procedure S_DLE (T : in out D.Ks_Distance_Line_Ellipse_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 3 then
            T.Line := Line_With (F, V);
         else
            T.Ellipse := Ellipse_With (F - 3, V);
         end if;
      end S_DLE;
      procedure I_DLE (T : in out D.Ks_Distance_Line_Ellipse_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_DLE;
      procedure DLE is new Sweep_Geometric_Tool
        (D.Ks_Distance_Line_Ellipse_Tool, "DistanceLineEllipse",
         Prefixed ("Line", Line_Fields) & ","
         & Prefixed ("Ellipse", Ellipse_Fields), P_DLE, S_DLE, I_DLE);

      procedure P_DSE (T : in out D.Ks_Distance_Segment_Ellipse_Tool) is
      begin
         T.Input_Image := Small;
         T.Segment := Segment_With (0, 0.0);
         T.Ellipse := Ellipse_With (0, 0.0);
      end P_DSE;
      procedure S_DSE (T : in out D.Ks_Distance_Segment_Ellipse_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 4 then
            T.Segment := Segment_With (F, V);
         else
            T.Ellipse := Ellipse_With (F - 4, V);
         end if;
      end S_DSE;
      procedure I_DSE (T : in out D.Ks_Distance_Segment_Ellipse_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_DSE;
      procedure DSE is new Sweep_Geometric_Tool
        (D.Ks_Distance_Segment_Ellipse_Tool, "DistanceSegmentEllipse",
         Prefixed ("Segment", Segment_Fields) & ","
         & Prefixed ("Ellipse", Ellipse_Fields), P_DSE, S_DSE, I_DSE);

      --  Intersections
      procedure P_ILL (T : in out D.Ks_Intersect_Line_Line_Tool) is
      begin
         T.Input_Image := Small;
         T.Line_A := Line_With (0, 0.0);
         T.Line_B := Line_B_With (0, 0.0);
      end P_ILL;
      procedure S_ILL (T : in out D.Ks_Intersect_Line_Line_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 3 then
            T.Line_A := Line_With (F, V);
         else
            T.Line_B := Line_B_With (F - 3, V);
         end if;
      end S_ILL;
      procedure I_ILL (T : in out D.Ks_Intersect_Line_Line_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_ILL;
      procedure ILL is new Sweep_Geometric_Tool
        (D.Ks_Intersect_Line_Line_Tool, "IntersectLineLine",
         Prefixed ("LineA", Line_Fields) & ","
         & Prefixed ("LineB", Line_Fields), P_ILL, S_ILL, I_ILL);

      procedure P_ISL (T : in out D.Ks_Intersect_Segment_Line_Tool) is
      begin
         T.Input_Image := Small;
         T.Segment := Segment_With (0, 0.0);
         T.Line := Line_B_With (0, 0.0);
      end P_ISL;
      procedure S_ISL (T : in out D.Ks_Intersect_Segment_Line_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 4 then
            T.Segment := Segment_With (F, V);
         else
            T.Line := Line_B_With (F - 4, V);
         end if;
      end S_ISL;
      procedure I_ISL (T : in out D.Ks_Intersect_Segment_Line_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_ISL;
      procedure ISL is new Sweep_Geometric_Tool
        (D.Ks_Intersect_Segment_Line_Tool, "IntersectSegmentLine",
         Prefixed ("Segment", Segment_Fields) & ","
         & Prefixed ("Line", Line_Fields), P_ISL, S_ISL, I_ISL);

      procedure P_ISS (T : in out D.Ks_Intersect_Segment_Segment_Tool) is
      begin
         T.Input_Image := Small;
         T.Segment_A := Segment_With (0, 0.0);
         T.Segment_B := Segment_B_With (0, 0.0);
      end P_ISS;
      procedure S_ISS (T : in out D.Ks_Intersect_Segment_Segment_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 4 then
            T.Segment_A := Segment_With (F, V);
         else
            T.Segment_B := Segment_B_With (F - 4, V);
         end if;
      end S_ISS;
      procedure I_ISS (T : in out D.Ks_Intersect_Segment_Segment_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_ISS;
      procedure ISS is new Sweep_Geometric_Tool
        (D.Ks_Intersect_Segment_Segment_Tool, "IntersectSegmentSegment",
         Prefixed ("SegmentA", Segment_Fields) & ","
         & Prefixed ("SegmentB", Segment_Fields), P_ISS, S_ISS, I_ISS);

      procedure P_ILC (T : in out D.Ks_Intersect_Line_Circle_Tool) is
      begin
         T.Input_Image := Small;
         T.Line := Line_With (0, 0.0);
         T.Input_Circle := Circle_With (0, 0.0);
      end P_ILC;
      procedure S_ILC (T : in out D.Ks_Intersect_Line_Circle_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 3 then
            T.Line := Line_With (F, V);
         else
            T.Input_Circle := Circle_With (F - 3, V);
         end if;
      end S_ILC;
      procedure I_ILC (T : in out D.Ks_Intersect_Line_Circle_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_ILC;
      procedure ILC is new Sweep_Geometric_Tool
        (D.Ks_Intersect_Line_Circle_Tool, "IntersectLineCircle",
         Prefixed ("Line", Line_Fields) & ","
         & Prefixed ("InputCircle", Circle_Fields), P_ILC, S_ILC, I_ILC);

      procedure P_ISC (T : in out D.Ks_Intersect_Segment_Circle_Tool) is
      begin
         T.Input_Image := Small;
         T.Segment := Segment_With (0, 0.0);
         T.Input_Circle := Circle_With (0, 0.0);
      end P_ISC;
      procedure S_ISC (T : in out D.Ks_Intersect_Segment_Circle_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 4 then
            T.Segment := Segment_With (F, V);
         else
            T.Input_Circle := Circle_With (F - 4, V);
         end if;
      end S_ISC;
      procedure I_ISC (T : in out D.Ks_Intersect_Segment_Circle_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_ISC;
      procedure ISC is new Sweep_Geometric_Tool
        (D.Ks_Intersect_Segment_Circle_Tool, "IntersectSegmentCircle",
         Prefixed ("Segment", Segment_Fields) & ","
         & Prefixed ("InputCircle", Circle_Fields), P_ISC, S_ISC, I_ISC);

      procedure P_ICC (T : in out D.Ks_Intersect_Circle_Circle_Tool) is
      begin
         T.Input_Image := Small;
         T.Circle_A := Circle_With (0, 0.0);
         T.Circle_B := Circle_B_With (0, 0.0);
      end P_ICC;
      procedure S_ICC (T : in out D.Ks_Intersect_Circle_Circle_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 3 then
            T.Circle_A := Circle_With (F, V);
         else
            T.Circle_B := Circle_B_With (F - 3, V);
         end if;
      end S_ICC;
      procedure I_ICC (T : in out D.Ks_Intersect_Circle_Circle_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_ICC;
      procedure ICC is new Sweep_Geometric_Tool
        (D.Ks_Intersect_Circle_Circle_Tool, "IntersectCircleCircle",
         Prefixed ("CircleA", Circle_Fields) & ","
         & Prefixed ("CircleB", Circle_Fields), P_ICC, S_ICC, I_ICC);

      procedure P_ILE (T : in out D.Ks_Intersect_Line_Ellipse_Tool) is
      begin
         T.Input_Image := Small;
         T.Line := Line_With (0, 0.0);
         T.Ellipse := Ellipse_With (0, 0.0);
      end P_ILE;
      procedure S_ILE (T : in out D.Ks_Intersect_Line_Ellipse_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 3 then
            T.Line := Line_With (F, V);
         else
            T.Ellipse := Ellipse_With (F - 3, V);
         end if;
      end S_ILE;
      procedure I_ILE (T : in out D.Ks_Intersect_Line_Ellipse_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_ILE;
      procedure ILE is new Sweep_Geometric_Tool
        (D.Ks_Intersect_Line_Ellipse_Tool, "IntersectLineEllipse",
         Prefixed ("Line", Line_Fields) & ","
         & Prefixed ("Ellipse", Ellipse_Fields), P_ILE, S_ILE, I_ILE);

      procedure P_ISE (T : in out D.Ks_Intersect_Segment_Ellipse_Tool) is
      begin
         T.Input_Image := Small;
         T.Segment := Segment_With (0, 0.0);
         T.Ellipse := Ellipse_With (0, 0.0);
      end P_ISE;
      procedure S_ISE (T : in out D.Ks_Intersect_Segment_Ellipse_Tool;
                       F : Positive; V : Real) is
      begin
         if F <= 4 then
            T.Segment := Segment_With (F, V);
         else
            T.Ellipse := Ellipse_With (F - 4, V);
         end if;
      end S_ISE;
      procedure I_ISE (T : in out D.Ks_Intersect_Segment_Ellipse_Tool;
                       I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_ISE;
      procedure ISE is new Sweep_Geometric_Tool
        (D.Ks_Intersect_Segment_Ellipse_Tool, "IntersectSegmentEllipse",
         Prefixed ("Segment", Segment_Fields) & ","
         & Prefixed ("Ellipse", Ellipse_Fields), P_ISE, S_ISE, I_ISE);

      procedure Outputs is
         A : D.Ks_Distance_Point_Point_Tool;
         B : D.Ks_Intersect_Circle_Circle_Tool;
         C : D.Ks_Intersect_Segment_Ellipse_Tool;
      begin
         Consume (A.Distance + A.Angle);
         Consume (B.Intersects);
         Consume (B.Num_Points);
         Consume (B.X3 + B.Y3);
         Consume (C.Num_Points);
      end Outputs;
   begin
      DPP;
      APP;
      ALL_Sweep;
      DPL;
      DPS;
      DPC;
      DPE;
      DSS;
      DSL;
      DLC;
      DSC;
      DCC;
      DLE;
      DSE;
      ILL;
      ISL;
      ISS;
      ILC;
      ISC;
      ICC;
      ILE;
      ISE;
      Begin_Area ("Dimensioning outputs before a run");
      Try ("outputs", Outputs'Access);
      End_Area;
   end Sweep_Dimensioning;

   procedure Sweep_Create_Shapes is
      package C renames AMV.Dimensioning.Create_Shapes;

      procedure P_CC (T : in out C.Ks_Create_Circle_Tool) is
      begin
         T.Input_Image := Small;
         T.Input_Circle := Circle_With (0, 0.0);
      end P_CC;
      procedure S_CC (T : in out C.Ks_Create_Circle_Tool; F : Positive;
                      V : Real) is
      begin
         T.Input_Circle := Circle_With (F, V);
      end S_CC;
      procedure I_CC (T : in out C.Ks_Create_Circle_Tool;
                      I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_CC;
      procedure CC is new Sweep_Geometric_Tool
        (C.Ks_Create_Circle_Tool, "CreateCircle",
         Prefixed ("InputCircle", Circle_Fields), P_CC, S_CC, I_CC);

      procedure P_CE (T : in out C.Ks_Create_Ellipse_Tool) is
      begin
         T.Input_Image := Small;
         T.Ellipse := Ellipse_With (0, 0.0);
      end P_CE;
      procedure S_CE (T : in out C.Ks_Create_Ellipse_Tool; F : Positive;
                      V : Real) is
      begin
         T.Ellipse := Ellipse_With (F, V);
      end S_CE;
      procedure I_CE (T : in out C.Ks_Create_Ellipse_Tool;
                      I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_CE;
      procedure CE is new Sweep_Geometric_Tool
        (C.Ks_Create_Ellipse_Tool, "CreateEllipse",
         Prefixed ("Ellipse", Ellipse_Fields), P_CE, S_CE, I_CE);

      procedure P_CL (T : in out C.Ks_Create_Line_Tool) is
      begin
         T.Input_Image := Small;
         T.Line := Line_With (0, 0.0);
      end P_CL;
      procedure S_CL (T : in out C.Ks_Create_Line_Tool; F : Positive;
                      V : Real) is
      begin
         T.Line := Line_With (F, V);
      end S_CL;
      procedure I_CL (T : in out C.Ks_Create_Line_Tool;
                      I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_CL;
      procedure CL is new Sweep_Geometric_Tool
        (C.Ks_Create_Line_Tool, "CreateLine",
         Prefixed ("Line", Line_Fields), P_CL, S_CL, I_CL);

      procedure P_CS (T : in out C.Ks_Create_Segment_Tool) is
      begin
         T.Input_Image := Small;
         T.Segment := Segment_With (0, 0.0);
      end P_CS;
      procedure S_CS (T : in out C.Ks_Create_Segment_Tool; F : Positive;
                      V : Real) is
      begin
         T.Segment := Segment_With (F, V);
      end S_CS;
      procedure I_CS (T : in out C.Ks_Create_Segment_Tool;
                      I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_CS;
      procedure CS_Sweep is new Sweep_Geometric_Tool
        (C.Ks_Create_Segment_Tool, "CreateSegment",
         Prefixed ("Segment", Segment_Fields), P_CS, S_CS, I_CS);

      procedure P_CB (T : in out C.Ks_Create_Line_Bisect_Points_Tool) is
      begin
         T.Input_Image := Small;
         T.Start_X := 10.0;
         T.Start_Y := 10.0;
         T.End_X := 40.0;
         T.End_Y := 30.0;
      end P_CB;
      procedure S_CB (T : in out C.Ks_Create_Line_Bisect_Points_Tool;
                      F : Positive; V : Real) is
      begin
         case F is
            when 1 => T.Start_X := V;
            when 2 => T.Start_Y := V;
            when 3 => T.End_X := V;
            when others => T.End_Y := V;
         end case;
      end S_CB;
      procedure I_CB (T : in out C.Ks_Create_Line_Bisect_Points_Tool;
                      I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_CB;
      procedure CB is new Sweep_Geometric_Tool
        (C.Ks_Create_Line_Bisect_Points_Tool, "CreateLineBisectPoints",
         "StartX,StartY,EndX,EndY", P_CB, S_CB, I_CB);

      procedure P_CP (T : in out C.Ks_Create_Line_Parallel_Tool) is
      begin
         T.Input_Image := Small;
         T.X := 5.0;
         T.Y := 40.0;
         T.Line := Line_With (0, 0.0);
      end P_CP;
      procedure S_CP (T : in out C.Ks_Create_Line_Parallel_Tool;
                      F : Positive; V : Real) is
      begin
         case F is
            when 1 => T.X := V;
            when 2 => T.Y := V;
            when others => T.Line := Line_With (F - 2, V);
         end case;
      end S_CP;
      procedure I_CP (T : in out C.Ks_Create_Line_Parallel_Tool;
                      I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_CP;
      procedure CP is new Sweep_Geometric_Tool
        (C.Ks_Create_Line_Parallel_Tool, "CreateLineParallel",
         "X,Y," & Prefixed ("Line", Line_Fields), P_CP, S_CP, I_CP);

      procedure P_CN (T : in out C.Ks_Create_Line_Perpendicular_Tool) is
      begin
         T.Input_Image := Small;
         T.X := 5.0;
         T.Y := 40.0;
         T.Line := Line_With (0, 0.0);
      end P_CN;
      procedure S_CN (T : in out C.Ks_Create_Line_Perpendicular_Tool;
                      F : Positive; V : Real) is
      begin
         case F is
            when 1 => T.X := V;
            when 2 => T.Y := V;
            when others => T.Line := Line_With (F - 2, V);
         end case;
      end S_CN;
      procedure I_CN (T : in out C.Ks_Create_Line_Perpendicular_Tool;
                      I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_CN;
      procedure CN is new Sweep_Geometric_Tool
        (C.Ks_Create_Line_Perpendicular_Tool, "CreateLinePerpendicular",
         "X,Y," & Prefixed ("Line", Line_Fields), P_CN, S_CN, I_CN);

      procedure P_CA (T : in out C.Ks_Create_Segment_Avg_Segs_Tool) is
      begin
         T.Input_Image := Small;
         T.Segment_A := Segment_With (0, 0.0);
         T.Segment_B := Segment_B_With (0, 0.0);
      end P_CA;
      procedure S_CA (T : in out C.Ks_Create_Segment_Avg_Segs_Tool;
                      F : Positive; V : Real) is
      begin
         if F <= 4 then
            T.Segment_A := Segment_With (F, V);
         else
            T.Segment_B := Segment_B_With (F - 4, V);
         end if;
      end S_CA;
      procedure I_CA (T : in out C.Ks_Create_Segment_Avg_Segs_Tool;
                      I : Ks_Image_8_Grey) is
      begin
         T.Input_Image := I;
      end I_CA;
      procedure CA is new Sweep_Geometric_Tool
        (C.Ks_Create_Segment_Avg_Segs_Tool, "CreateSegmentAvgSegs",
         Prefixed ("SegmentA", Segment_Fields) & ","
         & Prefixed ("SegmentB", Segment_Fields), P_CA, S_CA, I_CA);

      procedure Outputs is
         A : C.Ks_Create_Circle_Tool;
         B : C.Ks_Create_Segment_Avg_Segs_Tool;
         L : C.Ks_Create_Line_Bisect_Points_Tool;
      begin
         Consume (A.Get_Output_Circle.Radius);
         Consume (B.Get_Output_Segment.Length);
         Consume (L.Get_Output_Line.Rotation);
      end Outputs;
   begin
      CC;
      CE;
      CL;
      CS_Sweep;
      CB;
      CP;
      CN;
      CA;
      Begin_Area ("Create shape outputs before a run");
      Try ("outputs", Outputs'Access);
      End_Area;
   end Sweep_Create_Shapes;

   procedure Sweep_Fitting is
      package F renames AMV.Dimensioning.Fitting;

      procedure Add_Circle_Points (P : in out F.Ks_Fit_Points'Class) is
      begin
         for I in 0 .. 11 loop
            P.Add_Point (30.0 + 10.0 * Ada.Numerics.Long_Elementary_Functions.Cos (Real (I) * 0.5),
                         20.0 + 6.0 * Ada.Numerics.Long_Elementary_Functions.Sin (Real (I) * 0.5));
         end loop;
      end Add_Circle_Points;

      procedure Use_Fit (R : F.Ks_Fit_Result'Class; Call : String) is
         procedure Read is
         begin
            Consume (R.Num_Points + R.Num_Points_Used);
            Consume (R.RMS_Error);
            for I in 0 .. R.Num_Points - 1 loop
               Consume (R.Get_X (I) + R.Get_Y (I) + R.Get_Distance (I));
               Consume (R.Get_Used (I));
            end loop;
         end Read;
         procedure Beyond (Index : Integer) is
            X, Y, D : Real;
            U : Boolean;
         begin
            R.Get_XY_Used_Distance (Index, X, Y, U, D);
            Consume (X + Y + D);
         end Beyond;
      begin
         Try (Call & " / result", Read'Access);
         Integer_Sweep (Call & " / Get_XY_Used_Distance",
                        [R.Num_Points, Natural'Last], Beyond'Access, True);
      end Use_Fit;

      procedure P_FL (T : in out F.Ks_Fit_Line_Tool) is
      begin
         T.Input_Image := Small;
         Add_Circle_Points (T.Run_Params);
      end P_FL;
      procedure U_FL (T : F.Ks_Fit_Line_Tool; Call : String) is
         procedure Shape is
         begin
            Consume (T.Result.Get_Line.Rotation);
         end Shape;
      begin
         Use_Fit (T.Result, Call);
         Try (Call & " / Get_Line", Shape'Access);
      end U_FL;
      procedure P_FC (T : in out F.Ks_Fit_Circle_Tool) is
      begin
         T.Input_Image := Small;
         Add_Circle_Points (T.Run_Params);
      end P_FC;
      procedure U_FC (T : F.Ks_Fit_Circle_Tool; Call : String) is
         procedure Shape is
         begin
            Consume (T.Result.Get_Circle.Radius);
         end Shape;
      begin
         Use_Fit (T.Result, Call);
         Try (Call & " / Get_Circle", Shape'Access);
      end U_FC;
      procedure P_FE (T : in out F.Ks_Fit_Ellipse_Tool) is
      begin
         T.Input_Image := Small;
         Add_Circle_Points (T.Run_Params);
      end P_FE;
      procedure U_FE (T : F.Ks_Fit_Ellipse_Tool; Call : String) is
         procedure Shape is
         begin
            Consume (T.Result.Get_Ellipse.Radius_X);
         end Shape;
      begin
         Use_Fit (T.Result, Call);
         Try (Call & " / Get_Ellipse", Shape'Access);
      end U_FE;
      package SL is new Sweeps (F.Ks_Fit_Line_Tool, "FitLine", P_FL, U_FL);
      package SC is new Sweeps (F.Ks_Fit_Circle_Tool, "FitCircle", P_FC,
                                U_FC);
      package SE is new Sweeps (F.Ks_Fit_Ellipse_Tool, "FitEllipse", P_FE,
                                U_FE);

      procedure Set_Points (P : in out F.Ks_Fit_Points'Class; Field : Positive;
                            V : Real) is
      begin
         case Field is
            when 1 => P.Set_X (0, V);
            when 2 => P.Set_Y (0, V);
            when 3 => P.Set_Point (5, V, V);
            when 4 =>
               --  Every point at V, then one point moved by 1.
               for I in 0 .. P.Num_Points - 1 loop
                  P.Set_Point (I, V, V);
               end loop;
               P.Set_X (3, V + 1.0);
            when others =>
               P.Add_Point (V, -V);
         end case;
      end Set_Points;
      Point_Fields : constant String :=
        "Point(0).X,Point(0).Y,Point(5),every point,Add_Point";
      procedure R_FL (T : in out F.Ks_Fit_Line_Tool; Field : Positive;
                      V : Real) is
      begin
         Set_Points (T.Run_Params, Field, V);
      end R_FL;
      procedure R_FC (T : in out F.Ks_Fit_Circle_Tool; Field : Positive;
                      V : Real) is
      begin
         if Field = 6 then
            T.Run_Params.Set_Radius_Constraint_Enabled (True);
            T.Run_Params.Set_Radius_Constraint (V);
         else
            Set_Points (T.Run_Params, Field, V);
         end if;
      end R_FC;
      procedure R_FE (T : in out F.Ks_Fit_Ellipse_Tool; Field : Positive;
                      V : Real) is
      begin
         if Field = 6 then
            T.Run_Params.Set_Rotation_Constraint_Enabled (True);
            T.Run_Params.Set_Rotation_Constraint (V);
         else
            Set_Points (T.Run_Params, Field, V);
         end if;
      end R_FE;
      procedure N_FL (T : in out F.Ks_Fit_Line_Tool; Field : Positive;
                      V : Integer) is
      begin
         if Field = 1 then
            T.Run_Params.Set_Num_To_Ignore (V);
         else
            T.Run_Params.Set_Num_Points (V);
         end if;
      end N_FL;
      procedure N_FC (T : in out F.Ks_Fit_Circle_Tool; Field : Positive;
                      V : Integer) is
      begin
         if Field = 1 then
            T.Run_Params.Set_Num_To_Ignore (V);
         else
            T.Run_Params.Set_Num_Points (V);
         end if;
      end N_FC;
      procedure N_FE (T : in out F.Ks_Fit_Ellipse_Tool; Field : Positive;
                      V : Integer) is
      begin
         if Field = 1 then
            T.Run_Params.Set_Num_To_Ignore (V);
         else
            T.Run_Params.Set_Num_Points (V);
         end if;
      end N_FE;
      procedure I_FL (T : in out F.Ks_Fit_Line_Tool; Field : Positive;
                      I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         T.Input_Image := I;
      end I_FL;
      procedure I_FC (T : in out F.Ks_Fit_Circle_Tool; Field : Positive;
                      I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         T.Input_Image := I;
      end I_FC;
      procedure I_FE (T : in out F.Ks_Fit_Ellipse_Tool; Field : Positive;
                      I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         T.Input_Image := I;
      end I_FE;

      Points : F.Ks_Fit_Line;
      procedure Index_Calls (Index : Integer) is
         P : constant F.Ks_Fit_Line := Points;
         X, Y : Real;
      begin
         P.Get_Point (Index, X, Y);
         Consume (P.Get_X (Index) + P.Get_Y (Index) + X + Y);
      end Index_Calls;
      procedure Index_Calls_2 (Index : Integer) is
         P : F.Ks_Fit_Line := Points;
      begin
         P.Set_Point (Index, 1.0, 1.0);
         P.Set_X (Index, 1.0);
         P.Set_Y (Index, 1.0);
      end Index_Calls_2;
      procedure Index_Calls_3 (Index : Integer) is
         P : F.Ks_Fit_Line := Points;
      begin
         P.Delete_Point (Index);
      end Index_Calls_3;
      procedure Sizes (Value : Integer) is
         P : F.Ks_Fit_Line := Points;
      begin
         P.Set_Num_Points (Value);
      end Sizes;
      procedure Values (A : Real_List) is
         P : F.Ks_Fit_Circle;
      begin
         P.Add_Point (A (1), A (2));
         P.Set_Radius_Constraint (A (1));
      end Values;
      procedure Execute_Names (Name : String) is
      begin
         Consume (F.Execute (Points, Name).RMS_Error);
      end Execute_Names;
      procedure Empty_Results is
         R : F.Ks_Fit_Circle_Result;
         E : F.Ks_Fit_Ellipse_Result;
      begin
         Consume (R.Num_Points);
         Consume (R.Get_Circle.Radius);
         Consume (E.Get_Ellipse.Radius_Y);
      end Empty_Results;
   begin
      Add_Circle_Points (Points);
      Begin_Area ("Fit Line", Is_Tool => True);
      SL.Default_Run;
      SL.Images ("InputImage", I_FL'Access);
      SL.Reals (Point_Fields, R_FL'Access);
      SL.Integers ("NumToIgnore,NumPoints", N_FL'Access,
                   Bad_Naturals & [1, 2, F.Max_Points + 1]);
      End_Area;
      Begin_Area ("Fit Circle", Is_Tool => True);
      SC.Default_Run;
      SC.Images ("InputImage", I_FC'Access);
      SC.Reals (Point_Fields & ",RadiusConstraint", R_FC'Access);
      SC.Integers ("NumToIgnore,NumPoints", N_FC'Access,
                   Bad_Naturals & [1, 2, F.Max_Points + 1]);
      End_Area;
      Begin_Area ("Fit Ellipse", Is_Tool => True);
      SE.Default_Run;
      SE.Images ("InputImage", I_FE'Access);
      SE.Reals (Point_Fields & ",RotationConstraint", R_FE'Access);
      SE.Integers ("NumToIgnore,NumPoints", N_FE'Access,
                   Bad_Naturals & [1, 2, 4, F.Max_Points + 1]);
      End_Area;
      Begin_Area ("Fit point lists");
      Integer_Sweep ("Get_Point, Get_X, Get_Y", Bad_Indices,
                     Index_Calls'Access, True);
      Integer_Sweep ("Set_Point, Set_X, Set_Y", Bad_Indices,
                     Index_Calls_2'Access, True);
      Integer_Sweep ("Delete_Point", Bad_Indices, Index_Calls_3'Access,
                     True);
      Integer_Sweep ("Set_Num_Points", Bad_Naturals & [F.Max_Points + 1],
                     Sizes'Access);
      Composite ("Add_Point, Set_Radius_Constraint", [1.0, 2.0],
                 Values'Access);
      Name_Sweep ("Execute (space name)", Execute_Names'Access);
      Try ("empty results", Empty_Results'Access);
      End_Area;
   end Sweep_Fitting;

   ---------------------------------------------------------------------
   --  CalibFix
   ---------------------------------------------------------------------

   procedure Sweep_Calib_Fix is
      package C renames AMV.Calib_Fix;

      --  Fixture
      procedure P_FX (T : in out C.Ks_Fixture_Tool) is
      begin
         T.Input_Image := Small;
         T.Run_Params.Unfixtured_From_Fixtured_Transform :=
           Create_Rigid (0.3, 10.0, 5.0);
      end P_FX;
      package SX is new Sweeps (C.Ks_Fixture_Tool, "Fixture", P_FX);
      procedure I_FX (T : in out C.Ks_Fixture_Tool; F : Positive;
                      I : Ks_Image_8_Grey) is
         pragma Unreferenced (F);
      begin
         T.Input_Image := I;
      end I_FX;
      procedure R_FX (T : in out C.Ks_Fixture_Tool; F : Positive;
                      V : Real) is
         A : Real_List := [1.0, 0.0, 0.0, 1.0, 2.0, 3.0];
      begin
         A (F) := V;
         T.Run_Params.Unfixtured_From_Fixtured_Transform :=
           Create (A (1), A (2), A (3), A (4), A (5), A (6));
      end R_FX;
      procedure N_FX (T : in out C.Ks_Fixture_Tool; F : Positive;
                      V : String) is
      begin
         if F = 2 then
            T.Run_Params.Fixtured_Space_Name_Duplicate_Handling :=
              C.Enhanced;
         end if;
         T.Run_Params.Fixtured_Space_Name :=
           Ada.Strings.Unbounded.To_Unbounded_String (V);
      end N_FX;

      --  Fixture N point
      procedure P_FN (T : in out C.Ks_Fixture_N_Point_To_N_Point_Tool) is
      begin
         T.Input_Image := Small;
         T.Run_Params.Add_Point_Pair (0.0, 0.0, 1.0, 2.0);
         T.Run_Params.Add_Point_Pair (10.0, 0.0, 11.0, 2.0);
         T.Run_Params.Add_Point_Pair (0.0, 10.0, 1.0, 12.0);
      end P_FN;
      procedure U_FN (T : C.Ks_Fixture_N_Point_To_N_Point_Tool;
                      Call : String) is
         procedure Read is
         begin
            Consume (T.Result.RMS_Error);
            Use_Nothing (T.Result.Get_Unfixtured_From_Fixtured_Transform);
            Consume (T.Result.Output_Image.Width);
         end Read;
      begin
         Try (Call & " / result", Read'Access);
      end U_FN;
      package SN is new Sweeps (C.Ks_Fixture_N_Point_To_N_Point_Tool,
                                "FixtureNPointToNPoint", P_FN, U_FN);
      procedure I_FN (T : in out C.Ks_Fixture_N_Point_To_N_Point_Tool;
                      F : Positive; I : Ks_Image_8_Grey) is
         pragma Unreferenced (F);
      begin
         T.Input_Image := I;
      end I_FN;
      procedure R_FN (T : in out C.Ks_Fixture_N_Point_To_N_Point_Tool;
                      F : Positive; V : Real) is
      begin
         case F is
            when 1 => T.Run_Params.Set_Unfixtured_Point (0, V, 0.0);
            when 2 => T.Run_Params.Set_Unfixtured_Point (1, 10.0, V);
            when 3 => T.Run_Params.Set_Raw_Fixtured_Point (2, V, 12.0);
            when others =>
               T.Run_Params.Set_Raw_Fixtured_Point (0, V, V);
               T.Run_Params.Set_Raw_Fixtured_Point (1, V, V);
               T.Run_Params.Set_Raw_Fixtured_Point (2, V, V);
         end case;
      end R_FN;
      procedure D_FN (T : in out C.Ks_Fixture_N_Point_To_N_Point_Tool;
                      F : Positive; V : Integer) is
      begin
         case F is
            when 1 =>
               T.Run_Params.Set_DOFs_To_Compute
                 (C.Ks_N_Point_To_N_Point_DOF_Constants'Val
                    (V mod (C.Ks_N_Point_To_N_Point_DOF_Constants'Pos
                              (C.Ks_N_Point_To_N_Point_DOF_Constants'Last)
                            + 1)));
            when others =>
               T.Run_Params.Delete_Point_Pair (V mod 3);
               T.Run_Params.Delete_Point_Pair (0);
         end case;
      end D_FN;
      procedure S_FN (T : in out C.Ks_Fixture_N_Point_To_N_Point_Tool;
                      F : Positive; V : String) is
      begin
         if F = 2 then
            T.Run_Params.Set_Fixtured_Space_Name_Duplicate_Handling
              (C.Enhanced);
         end if;
         T.Run_Params.Set_Fixtured_Space_Name (V);
      end S_FN;

      --  Calib N point
      procedure P_CN (T : in out C.Ks_Calib_N_Point_To_N_Point_Tool) is
      begin
         T.Input_Image := Small;
         T.Calibration_Image := Small;
         T.Calibration.Add_Point_Pair (0.0, 0.0, 1.0, 2.0);
         T.Calibration.Add_Point_Pair (10.0, 0.0, 11.0, 2.0);
         T.Calibration.Add_Point_Pair (0.0, 10.0, 1.0, 12.0);
         T.Calibration.Calibrate;
      end P_CN;
      package SC is new Sweeps (C.Ks_Calib_N_Point_To_N_Point_Tool,
                                "CalibNPointToNPoint", P_CN);
      procedure I_CN (T : in out C.Ks_Calib_N_Point_To_N_Point_Tool;
                      F : Positive; I : Ks_Image_8_Grey) is
      begin
         if F = 1 then
            T.Input_Image := I;
         else
            T.Calibration_Image := I;
            T.Calibration.Calibrate (I);
         end if;
      end I_CN;
      procedure R_CN (T : in out C.Ks_Calib_N_Point_To_N_Point_Tool;
                      F : Positive; V : Real) is
      begin
         case F is
            when 1 => T.Calibration.Set_Calibrated_Origin_X (V);
            when 2 => T.Calibration.Set_Calibrated_Origin_Y (V);
            when 3 => T.Calibration.Set_Calibrated_X_Axis_Rotation (V);
            when 4 =>
               T.Calibration.Set_Calibrated_Origin_Space (C.Uncalibrated);
               T.Calibration.Set_Calibrated_Origin_X (V);
            when 5 =>
               T.Calibration.Set_Uncalibrated_Point (0, V, 0.0);
               T.Calibration.Calibrate;
            when others =>
               T.Calibration.Set_Raw_Calibrated_Point (1, V, V);
               T.Calibration.Calibrate;
         end case;
      end R_CN;
      procedure S_CN (T : in out C.Ks_Calib_N_Point_To_N_Point_Tool;
                      F : Positive; V : String) is
         pragma Unreferenced (F);
      begin
         T.Run_Params.Calibrated_Space_Name :=
           Ada.Strings.Unbounded.To_Unbounded_String (V);
      end S_CN;

      --  Calib checkerboard
      Board : Ks_Image_8_Grey := TI.Blank (160, 120, 0);
      Board_Calibration : C.Ks_Calib_Checkerboard;
      procedure P_CB (T : in out C.Ks_Calib_Checkerboard_Tool) is
      begin
         T.Input_Image := Board;
         T.Calibration := Board_Calibration;
      end P_CB;
      package SB is new Sweeps (C.Ks_Calib_Checkerboard_Tool,
                                "CalibCheckerboard", P_CB);
      procedure I_CB (T : in out C.Ks_Calib_Checkerboard_Tool;
                      F : Positive; I : Ks_Image_8_Grey) is
      begin
         if F = 1 then
            T.Input_Image := I;
         else
            T.Calibration.Set_Calibration_Image (I);
            T.Calibration.Calibrate;
         end if;
      end I_CB;
      procedure R_CB (T : in out C.Ks_Calib_Checkerboard_Tool;
                      F : Positive; V : Real) is
      begin
         case F is
            when 1 => T.Calibration.Set_Calibrated_Origin_X (V);
            when 2 => T.Calibration.Set_Calibrated_Origin_Y (V);
            when 3 => T.Calibration.Set_Calibrated_X_Axis_Rotation (V);
            when 4 =>
               T.Calibration.Set_Physical_Tile_Size_X (V);
               T.Calibration.Calibrate;
            when others =>
               T.Calibration.Set_Physical_Tile_Size_Y (V);
               T.Calibration.Calibrate;
         end case;
      end R_CB;
      procedure N_CB (T : in out C.Ks_Calib_Checkerboard_Tool;
                      F : Positive; V : Integer) is
      begin
         T.Run_Params.Unfilled_Pel_Value_Enabled := F = 2;
         T.Run_Params.Unfilled_Pel_Value := V;
      end N_CB;
      procedure S_CB (T : in out C.Ks_Calib_Checkerboard_Tool;
                      F : Positive; V : String) is
         pragma Unreferenced (F);
      begin
         T.Run_Params.Calibrated_Space_Name :=
           Ada.Strings.Unbounded.To_Unbounded_String (V);
      end S_CB;
      procedure Warp_Mode (T : in out C.Ks_Calib_Checkerboard_Tool;
                           F : Positive; I : Ks_Image_8_Grey) is
      begin
         T.Calibration.Set_Computation_Mode (C.Perspective_And_Radial_Warp);
         T.Calibration.Calibrate;
         if F = 1 then
            T.Input_Image := I;
         else
            T.Calibration.Set_Calibration_Image (I);
            T.Calibration.Calibrate;
         end if;
      end Warp_Mode;

      --  Outside the tools
      Pairs : C.Ks_N_Point_To_N_Point;
      procedure Pair_Values (A : Real_List) is
         P : C.Ks_N_Point_To_N_Point := Pairs;
      begin
         P.Add_Point_Pair (A (1), A (2), A (3), A (4));
         Use_Nothing (P.Compute_Group_A_From_Group_B_Transform);
      end Pair_Values;
      procedure Pair_Values_2 (A : Real_List) is
         P : C.Ks_N_Point_To_N_Point := Pairs;
      begin
         P.Set_Group_A_Point (0, A (1), A (2));
         P.Set_Group_B_Point (1, A (3), A (4));
         Use_Nothing (P.Compute_Group_A_From_Group_B_Transform);
      end Pair_Values_2;
      procedure Pair_Index (Index : Integer) is
         P : C.Ks_N_Point_To_N_Point := Pairs;
         X, Y : Real;
      begin
         P.Get_Group_A_Point (Index, X, Y);
         P.Get_Group_B_Point (Index, X, Y);
         Consume (P.Get_Group_A_Point_X (Index) + X + Y);
         P.Set_Group_A_Point (Index, 1.0, 1.0);
         P.Delete_Point_Pair (Index);
      end Pair_Index;
      procedure Pair_Degenerate is
         P : C.Ks_N_Point_To_N_Point;
         E : Real;
      begin
         for Dof in C.Ks_N_Point_To_N_Point_DOF_Constants loop
            P.Set_DOFs_To_Compute (Dof);
            begin
               Use_Nothing (P.Compute_Group_A_From_Group_B_Transform (E));
            exception
               when Occurrence : others =>
                  Note ("Compute (no points, " & Dof'Image & ")",
                        Occurrence);
            end;
            P.Add_Point_Pair (1.0, 1.0, 1.0, 1.0);
         end loop;
      end Pair_Degenerate;
      Calibration : C.Ks_Calib_N_Point_To_N_Point;
      procedure Calib_Maps (A : Real_List) is
         X, Y : Real;
         Inside : Boolean;
      begin
         Calibration.Map_Output_Pixel (A (1), A (2), X, Y, Inside);
         Calibration.Map_Input_Pixel (A (1), A (2), X, Y, Inside);
         Board_Calibration.Map_Output_Pixel (A (1), A (2), X, Y, Inside);
         Board_Calibration.Map_Input_Pixel (A (1), A (2), X, Y, Inside);
         Consume (X + Y);
      end Calib_Maps;
      procedure Calib_Index (Index : Integer) is
         X, Y : Real;
         I, J : Integer;
      begin
         Board_Calibration.Get_Corner (Index, X, Y, I, J);
         Consume (I + J);
         Consume (Board_Calibration.Get_Uncalibrated_Point_X (Index));
         Consume (Calibration.Get_Raw_Calibrated_Point_Y (Index));
      end Calib_Index;
      procedure Not_Calibrated is
         N : C.Ks_Calib_N_Point_To_N_Point;
         B : C.Ks_Calib_Checkerboard;
         X, Y : Real;
         Inside : Boolean;
      begin
         begin
            Use_Nothing
              (N.Get_Computed_Uncalibrated_From_Calibrated_Transform);
         exception
            when Occurrence : others =>
               Note ("not calibrated: N point transform", Occurrence);
         end;
         begin
            N.Map_Output_Pixel (1.0, 1.0, X, Y, Inside);
         exception
            when Occurrence : others =>
               Note ("not calibrated: N point map", Occurrence);
         end;
         begin
            Consume (B.Computed_RMS_Error);
         exception
            when Occurrence : others =>
               Note ("not calibrated: checkerboard RMS", Occurrence);
         end;
         begin
            B.Calibrate;
         exception
            when Occurrence : others =>
               Note ("checkerboard without an image", Occurrence);
         end;
         B.Set_Calibration_Image (Tiny);
         B.Calibrate;
      end Not_Calibrated;
      procedure Fixture_Execute (Field : Positive; Value : Real) is
         P : C.Ks_Fixture;
         A : Real_List := [1.0, 0.0, 0.0, 1.0, 2.0, 3.0];
      begin
         A (Field) := Value;
         P.Unfixtured_From_Fixtured_Transform :=
           Create (A (1), A (2), A (3), A (4), A (5), A (6));
         Consume (C.Execute (P, Small).Width);
      end Fixture_Execute;
   begin
      AMV_Test_Images.Checkerboard (Board, 80.3, 60.2, 16.0, 0.1);
      Board_Calibration.Set_Calibration_Image (Board);
      Board_Calibration.Set_Physical_Tile_Size_X (2.0);
      Board_Calibration.Set_Physical_Tile_Size_Y (2.0);
      Board_Calibration.Calibrate;
      Pairs.Add_Point_Pair (0.0, 0.0, 1.0, 2.0);
      Pairs.Add_Point_Pair (10.0, 0.0, 11.0, 2.0);
      Pairs.Add_Point_Pair (0.0, 10.0, 1.0, 12.0);
      Calibration.Add_Point_Pair (0.0, 0.0, 1.0, 2.0);
      Calibration.Add_Point_Pair (10.0, 0.0, 11.0, 2.0);
      Calibration.Add_Point_Pair (0.0, 10.0, 1.0, 12.0);
      Calibration.Calibrate;

      Begin_Area ("Fixture", Is_Tool => True);
      SX.Default_Run;
      SX.Images ("InputImage", I_FX'Access);
      SX.Reals ("UnfixturedFromFixtured.A,B,C,D,TranslationX,TranslationY",
                R_FX'Access);
      SX.Strings ("FixturedSpaceName,FixturedSpaceName (enhanced)",
                  N_FX'Access);
      End_Area;

      Begin_Area ("Fixture N Point To N Point", Is_Tool => True);
      SN.Default_Run;
      SN.Images ("InputImage", I_FN'Access);
      SN.Reals ("UnfixturedPoint(0).X,UnfixturedPoint(1).Y,"
                & "RawFixturedPoint(2).X,every RawFixturedPoint",
                R_FN'Access);
      SN.Integers ("DOFsToCompute,DeletePointPair", D_FN'Access,
                   Bad_Integers & [1, 2, 3, 4, 5, 6, 7]);
      SN.Strings ("FixturedSpaceName,FixturedSpaceName (enhanced)",
                  S_FN'Access);
      End_Area;

      Begin_Area ("Calib N Point To N Point", Is_Tool => True);
      SC.Default_Run;
      SC.Images ("InputImage,CalibrationImage", I_CN'Access);
      SC.Reals ("CalibratedOriginX,CalibratedOriginY,"
                & "CalibratedXAxisRotation,"
                & "CalibratedOriginX (uncalibrated space),"
                & "UncalibratedPoint(0).X,every RawCalibratedPoint(1)",
                R_CN'Access);
      SC.Strings ("CalibratedSpaceName", S_CN'Access);
      End_Area;

      Begin_Area ("Calib Checkerboard", Is_Tool => True);
      SB.Default_Run;
      SB.Images ("InputImage,CalibrationImage", I_CB'Access);
      SB.Images ("InputImage (warp),CalibrationImage (warp)",
                 Warp_Mode'Access);
      SB.Reals ("CalibratedOriginX,CalibratedOriginY,"
                & "CalibratedXAxisRotation,PhysicalTileSizeX,"
                & "PhysicalTileSizeY", R_CB'Access);
      SB.Integers ("UnfilledPelValue,UnfilledPelValue (enabled)",
                   N_CB'Access);
      SB.Strings ("CalibratedSpaceName", S_CB'Access);
      End_Area;

      Begin_Area ("CalibFix outside the tools");
      Composite ("Add_Point_Pair", [1.0, 2.0, 3.0, 4.0],
                 Pair_Values'Access);
      Composite ("Set_Group_A_Point, Set_Group_B_Point",
                 [1.0, 2.0, 3.0, 4.0], Pair_Values_2'Access);
      Integer_Sweep ("point pair index", Bad_Indices, Pair_Index'Access,
                     True);
      Try ("degenerate point pairs", Pair_Degenerate'Access);
      Composite ("Map_Output_Pixel, Map_Input_Pixel", [1.0, 2.0],
                 Calib_Maps'Access);
      Integer_Sweep ("Get_Corner, Get_*_Point_X", Bad_Indices,
                     Calib_Index'Access, True);
      Try ("before calibration", Not_Calibrated'Access);
      Field_Sweep ("Fixture Execute (transform)", 6,
                   Fixture_Execute'Access);
      End_Area;
   end Sweep_Calib_Fix;

   ---------------------------------------------------------------------
   --  CNL Search, PMAlign
   ---------------------------------------------------------------------

   procedure Sweep_CNL_Search is
      package C renames AMV.CNL_Search;
      Trained : C.Ks_CNL_Search_Pattern;
      procedure Prepare (T : in out C.Ks_CNL_Search_Tool) is
      begin
         T.Input_Image := Small;
         T.Pattern := Trained;
         T.Run_Params.Max_Results := 2;
      end Prepare;
      procedure Use_Results (T : C.Ks_CNL_Search_Tool; Call : String) is
         procedure Read is
         begin
            for I in 0 .. T.Results.Count - 1 loop
               Consume (T.Results.Item (I).Score);
            end loop;
         end Read;
         procedure Beyond (Index : Integer) is
         begin
            Consume (T.Results.Item (Index).Score);
         end Beyond;
      begin
         Try (Call & " / results", Read'Access);
         Integer_Sweep (Call & " / Item", [T.Results.Count, Natural'Last],
                        Beyond'Access, True);
      end Use_Results;
      package S is new Sweeps (C.Ks_CNL_Search_Tool, "CNLSearch", Prepare,
                               Use_Results);
      procedure Set_Image (T : in out C.Ks_CNL_Search_Tool; F : Positive;
                           I : Ks_Image_8_Grey) is
      begin
         case F is
            when 1 => T.Input_Image := I;
            when 2 =>
               T.Pattern.Set_Train_Image (I);
               T.Pattern.Train;
            when others =>
               T.Pattern.Set_Train_Image_Mask (I);
               T.Pattern.Train;
         end case;
      end Set_Image;
      procedure Set_Real (T : in out C.Ks_CNL_Search_Tool; F : Positive;
                          V : Real) is
      begin
         case F is
            when 1 => T.Run_Params.Accept_Threshold := V;
            when 2 => T.Run_Params.Confusion_Threshold := V;
            when 3 => T.Run_Params.XY_Overlap := V;
            when 4 =>
               T.Pattern.Set_Origin_X (V);
               T.Pattern.Train;
            when 5 =>
               T.Pattern.Set_Origin_Y (V);
               T.Pattern.Train;
            when others =>
               --  An origin of a pattern trained in the mode
               --  AffineTransform (carried into the resampled pattern).
               T.Pattern.Set_Train_Region
                 (RH.To_Holder (Region_With (Rectangle_Affine, 0, 0.0)));
               T.Pattern.Set_Train_Region_Mode (C.Affine_Transform);
               T.Pattern.Set_Origin_X (V);
               T.Pattern.Train;
         end case;
      end Set_Real;
      procedure Set_Integer (T : in out C.Ks_CNL_Search_Tool; F : Positive;
                             V : Integer) is
         R : C.Ks_CNL_Search_Run_Params renames T.Run_Params;
         I : constant Int32 := Int32 (V);
      begin
         case F is
            when 1 => R.Algorithm := I;
            when 2 => R.Accuracy := I;
            when 3 => R.Max_Results := I;
            when 4 => R.Search_Region_Mode := I;
            when 5 => R.Partial_Match_Limit_Left := I;
            when 6 => R.Partial_Match_Limit_Right := I;
            when 7 => R.Partial_Match_Limit_Up := I;
            when 8 => R.Partial_Match_Limit_Down := I;
            when 9 => R.Partial_Match_Reduce_Score := I;
            when 10 =>
               R.Algorithm := C.Linear_CNLPAS;
               R.Accuracy := I;
            when 11 =>
               T.Pattern.Set_Train_Image_Mask (Small);
               T.Pattern.Set_Train_Image_Mask_Offset_X (V);
               T.Pattern.Train;
            when 12 =>
               T.Pattern.Set_Train_Image_Mask (Small);
               T.Pattern.Set_Train_Image_Mask_Offset_Y (V);
               T.Pattern.Train;
            when 13 =>
               --  Only the codes the Ada subtype allows.
               if I in C.Ks_CNL_Search_Accuracy_Constants then
                  T.Pattern.Set_Algorithms (C.Linear_CNLPAS);
                  T.Pattern.Set_Accuracies (I);
                  T.Pattern.Train;
               end if;
            when 14 =>
               T.Pattern.Set_Train_Region
                 (RH.To_Holder (Region_With (Circle, 0, 0.0)));
               T.Pattern.Set_Train_Region_Mode (I);
               T.Pattern.Train;
            when 15 =>
               T.Pattern.Set_Train_Region
                 (RH.To_Holder (Region_With (Rectangle_Affine, 0, 0.0)));
               T.Pattern.Set_Train_Region_Mode (I);
               T.Pattern.Train;
            when others =>
               --  The mask's offset of a pattern trained in the mode
               --  AffineTransform (the mask is resampled with the region).
               T.Pattern.Set_Train_Region
                 (RH.To_Holder (Region_With (Rectangle_Affine, 0, 0.0)));
               T.Pattern.Set_Train_Region_Mode (C.Affine_Transform);
               T.Pattern.Set_Train_Image_Mask (Small);
               T.Pattern.Set_Train_Image_Mask_Offset_X (V);
               T.Pattern.Train;
         end case;
      end Set_Integer;
      procedure Set_Region (T : in out C.Ks_CNL_Search_Tool;
                            R : Ks_Region'Class) is
      begin
         T.Search_Region := RH.To_Holder (R);
      end Set_Region;
      procedure Set_Region_Affine (T : in out C.Ks_CNL_Search_Tool;
                                   R : Ks_Region'Class) is
      begin
         T.Run_Params.Search_Region_Mode := C.Affine_Transform;
         T.Search_Region := RH.To_Holder (R);
      end Set_Region_Affine;
      procedure Set_Train_Region (T : in out C.Ks_CNL_Search_Tool;
                                  R : Ks_Region'Class) is
      begin
         T.Pattern.Set_Train_Region (RH.To_Holder (R));
         T.Pattern.Train;
      end Set_Train_Region;
      procedure Set_Train_Region_Affine (T : in out C.Ks_CNL_Search_Tool;
                                         R : Ks_Region'Class) is
      begin
         T.Pattern.Set_Train_Region_Mode (C.Affine_Transform);
         T.Pattern.Set_Train_Region (RH.To_Holder (R));
         T.Pattern.Train;
      end Set_Train_Region_Affine;
      procedure Untrained is
         P : C.Ks_CNL_Search_Pattern;
      begin
         Consume (P.Trained_Pattern_Width + P.Trained_Pattern_Height);
         Consume (P.Get_Trained_Pattern_Image.Width);
      end Untrained;
   begin
      Trained.Set_Train_Image (Small);
      Trained.Set_Train_Region (RH.To_Holder
                                  (Region_With (Rectangle, 0, 0.0)));
      Trained.Set_Origin_X (20.0);
      Trained.Set_Origin_Y (18.0);
      Trained.Train;
      Begin_Area ("CNL Search", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage,Pattern.TrainImage,Pattern.TrainImageMask",
                Set_Image'Access);
      S.Reals ("AcceptThreshold,ConfusionThreshold,XYOverlap,"
               & "Pattern.OriginX,Pattern.OriginY,"
               & "Pattern.OriginX (affine mode)", Set_Real'Access);
      S.Integers ("Algorithm,Accuracy,MaxResults,SearchRegionMode,"
                  & "PartialMatchLimitLeft,PartialMatchLimitRight,"
                  & "PartialMatchLimitUp,PartialMatchLimitDown,"
                  & "PartialMatchReduceScore,Accuracy (CNLPAS),"
                  & "Pattern.TrainImageMaskOffsetX,"
                  & "Pattern.TrainImageMaskOffsetY,Pattern.Accuracies,"
                  & "Pattern.TrainRegionMode,"
                  & "Pattern.TrainRegionMode (affine rectangle),"
                  & "Pattern.TrainImageMaskOffsetX (affine mode)",
                  Set_Integer'Access);
      S.Regions ("SearchRegion", All_Regions, Set_Region'Access);
      S.Regions ("SearchRegion (affine mode)", All_Regions,
                 Set_Region_Affine'Access);
      S.Regions ("Pattern.TrainRegion", All_Regions,
                 Set_Train_Region'Access);
      S.Regions ("Pattern.TrainRegion (affine mode)", All_Regions,
                 Set_Train_Region_Affine'Access);
      Try ("untrained pattern", Untrained'Access);
      End_Area;
   end Sweep_CNL_Search;

   procedure Sweep_PM_Align is
      package P renames AMV.PM_Align;
      Trained : P.Ks_PM_Align_Pattern;
      procedure Prepare (T : in out P.Ks_PM_Align_Tool) is
      begin
         T.Input_Image := Small;
         T.Pattern := Trained;
      end Prepare;
      procedure Use_Results (T : P.Ks_PM_Align_Tool; Call : String) is
         procedure Read is
         begin
            for I in 0 .. T.Results.Count - 1 loop
               Use_Nothing (P.Get_Pose (T.Results.Item (I)));
            end loop;
         end Read;
         procedure Beyond (Index : Integer) is
         begin
            Consume (T.Results.Item (Index).Score);
         end Beyond;
      begin
         Try (Call & " / results", Read'Access);
         Integer_Sweep (Call & " / Item", [T.Results.Count, Natural'Last],
                        Beyond'Access, True);
      end Use_Results;
      package S is new Sweeps (P.Ks_PM_Align_Tool, "PMAlign", Prepare,
                               Use_Results);
      procedure Set_Image (T : in out P.Ks_PM_Align_Tool; F : Positive;
                           I : Ks_Image_8_Grey) is
      begin
         case F is
            when 1 => T.Input_Image := I;
            when 2 => T.Search_Image_Mask := I;
            when 3 =>
               T.Pattern.Set_Train_Image (I);
               T.Pattern.Train;
            when others =>
               T.Pattern.Set_Train_Image_Mask (I);
               T.Pattern.Train;
         end case;
      end Set_Image;
      procedure Set_Real (T : in out P.Ks_PM_Align_Tool; F : Positive;
                          V : Real) is
         R : P.Ks_PM_Align_Run_Params renames T.Run_Params;
      begin
         case F is
            when 1 => R.Accept_Threshold := V;
            when 2 =>
               R.Coarse_Accept_Threshold_Enabled := 1;
               R.Coarse_Accept_Threshold := V;
            when 3 => R.Contrast_Threshold := V;
            when 4 => R.Outside_Region_Threshold := V;
            when 5 =>
               R.Timeout_Enabled := 1;
               R.Timeout := V;
            when 6 =>
               R.Zone_Angle.Configuration := P.Code (P.Low_High);
               R.Zone_Angle.Low := V;
            when 7 =>
               R.Zone_Angle.Configuration := P.Code (P.Low_High);
               R.Zone_Angle.High := V;
            when 8 => R.Zone_Angle.Nominal := V;
            when 9 =>
               R.Zone_Scale.Configuration := P.Code (P.Low_High);
               R.Zone_Scale.Low := V;
            when 10 =>
               R.Zone_Scale.Configuration := P.Code (P.Low_High);
               R.Zone_Scale.High := V;
            when 11 => R.Zone_Scale.Nominal := V;
            when 12 => R.XY_Overlap := V;
            when 13 =>
               T.Pattern.Set_Grain_Limit_Auto_Select (False);
               T.Pattern.Set_Grain_Limit_Coarse (V);
               T.Pattern.Train;
            when 14 =>
               T.Pattern.Set_Grain_Limit_Auto_Select (False);
               T.Pattern.Set_Grain_Limit_Fine (V);
               T.Pattern.Train;
            when others =>
               T.Pattern.Set_Origin (Create_Rigid (0.0, V, 10.0));
               T.Pattern.Train;
         end case;
      end Set_Real;
      procedure Set_Integer (T : in out P.Ks_PM_Align_Tool; F : Positive;
                             V : Integer) is
         R : P.Ks_PM_Align_Run_Params renames T.Run_Params;
         I : constant Int32 := Int32 (V);
      begin
         case F is
            when 1 => R.Approximate_Number_To_Find := I;
            when 2 => R.Run_Algorithm := I;
            when 3 => R.Score_Using_Clutter := I;
            when 4 => R.Timeout_Enabled := I;
            when 5 => R.Coarse_Accept_Threshold_Enabled := I;
            when 6 => R.Zone_Angle.Configuration := I;
            when 7 => R.Zone_Scale.Configuration := I;
            when 8 =>
               T.Search_Image_Mask := Small;
               T.Search_Image_Mask_Offset_X := V;
            when 9 =>
               T.Search_Image_Mask := Small;
               T.Search_Image_Mask_Offset_Y := V;
            when 10 =>
               T.Pattern.Set_Train_Image_Mask (Small);
               T.Pattern.Set_Train_Image_Mask_Offset_X (V);
               T.Pattern.Train;
            when others =>
               T.Pattern.Set_Train_Image_Mask (Small);
               T.Pattern.Set_Train_Image_Mask_Offset_Y (V);
               T.Pattern.Train;
         end case;
      end Set_Integer;
      procedure Set_Region (T : in out P.Ks_PM_Align_Tool;
                            R : Ks_Region'Class) is
      begin
         T.Search_Region := RH.To_Holder (R);
      end Set_Region;
      procedure Set_Train_Region (T : in out P.Ks_PM_Align_Tool;
                                  R : Ks_Region'Class) is
      begin
         T.Pattern.Set_Train_Region (RH.To_Holder (R));
         T.Pattern.Train;
      end Set_Train_Region;
      procedure Pose (Field : Positive; Value : Real) is
         R : P.Ks_PM_Align_Result;
      begin
         case Field is
            when 1 => R.Translation_X := Value;
            when 2 => R.Translation_Y := Value;
            when 3 => R.Rotation := Value;
            when others => R.Scaling := Value;
         end case;
         Use_Nothing (P.Get_Pose (R));
      end Pose;
      procedure Origin (A : Real_List) is
         Q : P.Ks_PM_Align_Pattern := Trained;
      begin
         Q.Set_Origin (Create (A (1), A (2), A (3), A (4), A (5), A (6)));
         Q.Train;
      end Origin;
      procedure Untrained is
         Q : P.Ks_PM_Align_Pattern;
      begin
         Consume (Integer (P.Get_Trained_Features (Q, True)'Length));
      end Untrained;
      procedure Codes (Value : Integer) is
      begin
         Consume (P.Zone (Int32 (Value))'Image);
      end Codes;
   begin
      Trained.Set_Train_Image (Small);
      Trained.Set_Train_Region (RH.To_Holder
                                  (Region_With (Rectangle, 0, 0.0)));
      Trained.Train;
      Begin_Area ("PMAlign", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage,SearchImageMask,Pattern.TrainImage,"
                & "Pattern.TrainImageMask", Set_Image'Access);
      S.Reals ("AcceptThreshold,CoarseAcceptThreshold,ContrastThreshold,"
               & "OutsideRegionThreshold,Timeout,ZoneAngle.Low,"
               & "ZoneAngle.High,ZoneAngle.Nominal,ZoneScale.Low,"
               & "ZoneScale.High,ZoneScale.Nominal,XYOverlap,"
               & "Pattern.GrainLimitCoarse,Pattern.GrainLimitFine,"
               & "Pattern.Origin.TranslationX", Set_Real'Access);
      S.Integers ("ApproximateNumberToFind,RunAlgorithm,ScoreUsingClutter,"
                  & "TimeoutEnabled,CoarseAcceptThresholdEnabled,"
                  & "ZoneAngle.Configuration,ZoneScale.Configuration,"
                  & "SearchImageMaskOffsetX,SearchImageMaskOffsetY,"
                  & "Pattern.TrainImageMaskOffsetX,"
                  & "Pattern.TrainImageMaskOffsetY", Set_Integer'Access);
      S.Regions ("SearchRegion", All_Regions, Set_Region'Access);
      S.Regions ("Pattern.TrainRegion", All_Regions,
                 Set_Train_Region'Access);
      Field_Sweep ("Get_Pose (forged result)", 4, Pose'Access);
      Composite ("Pattern.Set_Origin", [1.0, 0.0, 0.0, 1.0, 0.0, 0.0],
                 Origin'Access);
      Try ("untrained pattern", Untrained'Access);
      Integer_Sweep ("Zone (code)", Bad_Integers, Codes'Access, True);
      End_Area;
   end Sweep_PM_Align;

   ---------------------------------------------------------------------
   --  ToolGroup, ToolBlock, Image File
   ---------------------------------------------------------------------

   procedure Run_Each_Tool
     (Group     : in out AMV.Tool_Group.Ks_Tool_Group'Class;
      Message   : in out Ada.Strings.Unbounded.Unbounded_String;
      Result    : in out Ks_Tool_Result_Constants;
      Run_Tools : out Boolean) is
   begin
      for I in 0 .. Group.Count - 1 loop
         Group.Run_Tool (Group.Item (I), Message, Result);
      end loop;
      Run_Tools := False;
   end Run_Each_Tool;
   --  A script that runs every member through RunTool.

   procedure Sweep_Tool_Group is
      package G renames AMV.Tool_Group;
      package K renames AMV.Tool_Block;
      Bad_Blob : aliased AMV.Blob.Ks_Blob_Tool;
      Caliper  : aliased AMV.Caliper.Ks_Caliper_Tool;
      Group    : aliased G.Ks_Tool_Group;
      Block    : aliased K.Ks_Tool_Block;
      procedure Index_Calls (Index : Integer) is
         C : G.Ks_Tool_Group := Group;
      begin
         Consume (C.Item (Index).Name);
         Consume (C.Disabled (Index));
         C.Set_Disabled (Index, True);
         C.Move (Index, 0);
         C.Move (0, Index);
         C.Remove_At (Index);
      end Index_Calls;
      procedure Index_Calls_2 (Index : Integer) is
         C : G.Ks_Tool_Group;
      begin
         C.Insert (Index, Caliper'Access);
      end Index_Calls_2;
      procedure Names (Name : String) is
         C : G.Ks_Tool_Group := Group;
      begin
         Consume (C.Index_Of (Name));
         Consume (C.Contains (Name));
         begin
            Consume (C.Item (Name).Name);
         exception
            when Occurrence : others =>
               Note ("Item (name)", Occurrence);
         end;
         C.Remove (Name);
      end Names;
      procedure Terminal_Reals (A : Real_List) is
         C : K.Ks_Tool_Block_Terminal_Collection;
      begin
         C.Add ("R", 1.0);
         C.Set ("R", A (1));
         C.Add ("S", A (1));
         Consume (C.Get_Real ("R"));
      end Terminal_Reals;
      procedure Terminal_Integers (Value : Integer) is
         C : K.Ks_Tool_Block_Terminal_Collection;
         V : constant Long_Long_Integer :=
           (case Value is
               when Integer'First => Long_Long_Integer'First,
               when Integer'Last  => Long_Long_Integer'Last,
               when others        => Long_Long_Integer (Value));
      begin
         C.Add ("I", V);
         C.Set ("I", V);
         Consume (Integer (C.Get_Integer ("I") mod 7));
         Consume (C.Get_Real ("I"));
      end Terminal_Integers;
      procedure Terminal_Index (Index : Integer) is
         C : K.Ks_Tool_Block_Terminal_Collection;
      begin
         C.Add ("A", 1.0);
         C.Add ("B", K.Transform_Type);
         Consume (C.Name_Of (Index));
         C.Insert (Index, "C", K.Shape_Type);
         C.Move (Index, 0);
         C.Remove_At (Index);
      end Terminal_Index;
      procedure Terminal_Names (Name : String) is
         C : K.Ks_Tool_Block_Terminal_Collection;
      begin
         C.Add ("A", 1.0);
         Consume (C.Index_Of (Name));
         Consume (C.Contains (Name));
         begin
            Consume (C.Value_Type (Name)'Image);
         exception
            when Occurrence : others =>
               Note ("Value_Type (name)", Occurrence);
         end;
         begin
            Consume (C.Has_Value (Name));
         exception
            when Occurrence : others =>
               Note ("Has_Value (name)", Occurrence);
         end;
         begin
            Use_Nothing (C.Get_Transform (Name));
         exception
            when Occurrence : others =>
               Note ("Get_Transform (name)", Occurrence);
         end;
         C.Add (Name, Name);
      end Terminal_Names;
      procedure Terminal_Types is
         C : K.Ks_Tool_Block_Terminal_Collection;
      begin
         for T in K.Ks_Tool_Block_Terminal_Type loop
            C.Add ("T" & Image (K.Ks_Tool_Block_Terminal_Type'Pos (T)), T);
         end loop;
         for T in K.Ks_Tool_Block_Terminal_Type loop
            declare
               N : constant String :=
                 "T" & Image (K.Ks_Tool_Block_Terminal_Type'Pos (T));
            begin
               begin
                  Consume (C.Get_Real (N));
               exception
                  when Occurrence : others => Note ("Get_Real", Occurrence);
               end;
               begin
                  Consume (Integer (C.Get_Integer (N) mod 7));
               exception
                  when Occurrence : others =>
                     Note ("Get_Integer", Occurrence);
               end;
               begin
                  Consume (C.Get_Image_8_Grey (N).Width);
               exception
                  when Occurrence : others =>
                     Note ("Get_Image_8_Grey", Occurrence);
               end;
               begin
                  Consume (C.Get_Shape (N).Selected_Space_Name);
               exception
                  when Occurrence : others => Note ("Get_Shape", Occurrence);
               end;
               begin
                  C.Set (N, String'(1 .. 2_000 => 'z'));
               exception
                  when Occurrence : others => Note ("Set (long)", Occurrence);
               end;
            end;
         end loop;
         for I in 1 .. 200 loop
            C.Add ("X" & Image (I), 1.0);
         end loop;
      end Terminal_Types;
   begin
      Begin_Area ("ToolGroup", Is_Tool => True);
      Bad_Blob.Input_Image := Small;
      Bad_Blob.Run_Params.Extrema_Angle := NaN;
      Bad_Blob.Set_Name ("bad blob");
      Caliper.Input_Image := No_Image;
      Group.Add (Bad_Blob'Access);
      Group.Add (Caliper'Access);
      Run_Tool (Group, "ToolGroup with failing members",
                Member_Error_Allowed => True);
      Run_Tool (Bad_Blob, "ToolGroup member Blob (NaN extrema angle)");
      Run_Tool (Caliper, "ToolGroup member Caliper (no image)");
      Group.Set_Abort_Run_On_Tool_Failure (True);
      Run_Tool (Group, "ToolGroup aborting on failure",
                Member_Error_Allowed => True);
      Group.Set_Script (Run_Each_Tool'Unrestricted_Access);
      Run_Tool (Group, "ToolGroup script with RunTool, aborting");
      Group.Set_Abort_Run_On_Tool_Failure (False);
      Run_Tool (Group, "ToolGroup script with RunTool",
                Member_Error_Allowed => True);
      Group.Set_Disabled (0, True);
      Run_Tool (Group, "ToolGroup script with RunTool, a disabled member",
                Member_Error_Allowed => True);
      Group.Set_Disabled (0, False);
      Group.Set_Script (null);
      Integer_Sweep ("ToolGroup index", Bad_Indices, Index_Calls'Access,
                     True);
      Integer_Sweep ("ToolGroup Insert", Bad_Indices, Index_Calls_2'Access,
                     True);
      Name_Sweep ("ToolGroup names", Names'Access);
      End_Area;

      Begin_Area ("ToolBlock", Is_Tool => True);
      Block.Add (Bad_Blob'Access);
      Block.Inputs.Add ("Threshold", K.Real_Type);
      Run_Tool (Block, "ToolBlock with a failing member",
                Member_Error_Allowed => True);
      Composite ("terminal Real", [1.0], Terminal_Reals'Access);
      Integer_Sweep ("terminal Integer", Bad_Integers,
                     Terminal_Integers'Access);
      Integer_Sweep ("terminal index", Bad_Indices, Terminal_Index'Access,
                     True);
      Name_Sweep ("terminal names", Terminal_Names'Access);
      Try ("terminal types and limits", Terminal_Types'Access);
      End_Area;
   end Sweep_Tool_Group;

   procedure Sweep_Image_File is
      package F renames AMV.Image_File;
      procedure Prepare (T : in out F.Ks_Image_File_Tool) is
      begin
         T.Input_Image := Small;
      end Prepare;
      package S is new Sweeps (F.Ks_Image_File_Tool, "ImageFile", Prepare);
      procedure Set_Image (T : in out F.Ks_Image_File_Tool; Field : Positive;
                           I : Ks_Image_8_Grey) is
         pragma Unreferenced (Field);
      begin
         T.Input_Image := I;
      end Set_Image;
      procedure Set_Integer (T : in out F.Ks_Image_File_Tool;
                             Field : Positive; V : Integer) is
         pragma Unreferenced (Field);
      begin
         T.Next_Index := V;
      end Set_Integer;
      procedure Read (Index : Integer) is
      begin
         Consume (F.Read_Image ("build/no-such-file.pgm", Index).Width);
      end Read;
      procedure Read_2 (Name : String) is
      begin
         Consume (F.Read_Image_8_Grey (Name).Width);
      end Read_2;
      procedure Closed (Index : Integer) is
         File : F.Ks_Image_File;
      begin
         Consume (File.Count);
         Consume (File.Item (Index).Width);
      end Closed;
      procedure Open_Names (Name : String) is
         File : F.Ks_Image_File;
      begin
         File.Open (Name, F.Read);
      end Open_Names;
   begin
      Begin_Area ("Image File", Is_Tool => True);
      S.Default_Run;
      S.Images ("InputImage", Set_Image'Access);
      S.Integers ("NextIndex", Set_Integer'Access, Bad_Naturals);
      Integer_Sweep ("Read_Image (missing file)", Bad_Naturals, Read'Access);
      Name_Sweep ("Read_Image_8_Grey (names)", Read_2'Access);
      Integer_Sweep ("Item (closed file)", Bad_Indices, Closed'Access, True);
      Name_Sweep ("Open (names)", Open_Names'Access);
      End_Area;
   end Sweep_Image_File;

   ---------------------------------------------------------------------
   --  Streams
   ---------------------------------------------------------------------

   generic
      type Item_Type is private;
      Name : String;
      with function Make return Item_Type;
      with procedure Use_Item (Item : Item_Type);
   procedure Stream_Sweep;
   --  Writes Make to a stream and reads it back as written, truncated
   --  after each length and with each byte overwritten in turn by 16#00#
   --  and 16#80# (every length and byte of the first 64, then a sample),
   --  and uses what was read. Every exception must be an AMV one (the
   --  specs say Ks_Image_File_Exception, or Ks_Bad_Parameter_Exception for
   --  a polygon).
   --
   --  A size read from a stream is allocated before the data that follows
   --  it is read (AMV.Images), so an overwritten byte can make a reader
   --  allocate whatever size the format allows: the objects are kept
   --  small and the values limited to 16#00# and 16#80#, which keep that
   --  below about 150 MB (16#80# in the third byte of a size).

   procedure Stream_Sweep is
      use Ada.Streams;
      package Storage renames Ada.Streams.Storage.Unbounded;

      function Bytes_Of (Item : Item_Type) return Stream_Element_Array is
         S : aliased Storage.Stream_Type;
      begin
         Item_Type'Write (S'Access, Item);
         declare
            Result : Stream_Element_Array (1 .. S.Element_Count);
            Last   : Stream_Element_Offset;
         begin
            S.Read (Result, Last);
            return Result (1 .. Last);
         end;
      end Bytes_Of;

      Written : constant Stream_Element_Array := Bytes_Of (Make);
      Step    : constant Stream_Element_Offset :=
        Stream_Element_Offset'Max (1, Written'Length / 200);

      procedure Read_Back (Call : String; Bytes : Stream_Element_Array) is
         procedure Action is
            S    : aliased Storage.Stream_Type;
            Item : Item_Type;
         begin
            S.Write (Bytes);
            Item_Type'Read (S'Access, Item);
            Use_Item (Item);
         end Action;
      begin
         Try (Call, Action'Access);
      end Read_Back;
   begin
      Read_Back (Name & "'Read (as written)", Written);
      for Length in Stream_Element_Offset range 0 .. Written'Length - 1 loop
         if Length < 64 or else Length mod Step = 0 then
            Read_Back (Name & "'Read (first" & Length'Image & " bytes)",
                       Written (1 .. Length));
         end if;
      end loop;
      for Position in Written'Range loop
         if Position <= 64 or else Position mod Step = 0 then
            for Value of Stream_Element_Array'[16#00#, 16#80#] loop
               declare
                  Copy : Stream_Element_Array := Written;
               begin
                  Copy (Position) := Value;
                  Read_Back (Name & "'Read (byte" & Position'Image & " ="
                             & Value'Image & ")", Copy);
               end;
            end loop;
         end if;
      end loop;
   end Stream_Sweep;

   procedure Sweep_Streams is
      Tiny_Scene : constant Ks_Image_8_Grey := Scene (12, 10);

      function Make_8 return Ks_Image_8_Grey is
         I : aliased Ks_Image_8_Grey := Create (3, 2, 7);
      begin
         I.Coordinate_Space_Tree.Add_Space ("@", "A",
                                            Create_Rigid (0.3, 1.0, 2.0));
         I.Set_Selected_Space_Name ("@\A");
         I.Set_Pixel_From_Root_Transform (Create_Similarity (2.0, 0.1, 3.0,
                                                             4.0));
         return I;
      end Make_8;
      procedure Use_8 (I : Ks_Image_8_Grey) is
      begin
         Consume (I.Width + Integer (I.Get_Pixel (0, 0)));
         Use_Nothing (I.Get_Transform (".", "#"));
      end Use_8;
      procedure Images_8 is new Stream_Sweep
        (Ks_Image_8_Grey, "Ks_Image_8_Grey", Make_8, Use_8);

      function Make_16 return Ks_Image_16_Grey is
        (Create (3, 2, 40_000));
      procedure Use_16 (I : Ks_Image_16_Grey) is
      begin
         Consume (I.Width + Integer (I.Get_Pixel (2, 1)));
      end Use_16;
      procedure Images_16 is new Stream_Sweep
        (Ks_Image_16_Grey, "Ks_Image_16_Grey", Make_16, Use_16);

      function Make_24 return Ks_Image_24_Planar_Color is
        (Create (3, 2, 1, 2, 3));
      procedure Use_24 (I : Ks_Image_24_Planar_Color) is
         R, G, B : Grey_8;
      begin
         I.Get_Pixel (2, 1, R, G, B);
         Consume (I.Get_Plane (Blue).Width + Integer (R));
      end Use_24;
      procedure Images_24 is new Stream_Sweep
        (Ks_Image_24_Planar_Color, "Ks_Image_24_Planar_Color", Make_24,
         Use_24);

      function Make_Tree return CS.Ks_Coordinate_Space_Tree is
      begin
         return T : CS.Ks_Coordinate_Space_Tree do
            T.Add_Space ("@", "A", Create_Rigid (0.3, 1.0, 2.0));
            T.Add_Space ("@\A", "B", Create_Similarity (2.0, 0.0, 1.0, 1.0));
         end return;
      end Make_Tree;
      procedure Use_Tree (T : CS.Ks_Coordinate_Space_Tree) is
      begin
         Consume (T.Space_Count);
         Use_Nothing (T.Get_Transform ("@", T.Space_Name (T.Space_Count - 1)));
      end Use_Tree;
      procedure Trees is new Stream_Sweep
        (CS.Ks_Coordinate_Space_Tree, "Ks_Coordinate_Space_Tree", Make_Tree,
         Use_Tree);

      function Make_Region return AMV.Regions.Pixel_Region is
        (AMV.Regions.Rasterize (Tiny_Scene, Region_With (Circle, 0, 0.0)));
      procedure Use_Region (R : AMV.Regions.Pixel_Region) is
      begin
         Consume (R.Pixel_Count + R.Width + R.X_Min);
         Consume (R.Contains (3, 3));
      end Use_Region;
      procedure Pixel_Regions is new Stream_Sweep
        (AMV.Regions.Pixel_Region, "Pixel_Region", Make_Region, Use_Region);

      function Make_Real return AMV.Image_Math.Real_Image is
        (AMV.Image_Math.Create (2, 1, 1.5));
      procedure Use_Real (R : AMV.Image_Math.Real_Image) is
         M, S, Lo, Hi : Real;
      begin
         R.Statistics (M, S, Lo, Hi);
         Consume (M + S + Lo + Hi);
      end Use_Real;
      procedure Real_Images is new Stream_Sweep
        (AMV.Image_Math.Real_Image, "Real_Image", Make_Real, Use_Real);

      --  Every concrete shape: Make gives a shape whose space name is
      --  set, Use maps it and reads its space name back.

      Moved : constant Ks_Transform_2D_Linear :=
        Create_Similarity (1.5, 0.2, 3.0, -4.0);

      generic
         type Shape is new Ks_Shape with private;
         Name : String;
         with function Default return Shape;
      procedure Shape_Sweep;

      procedure Shape_Sweep is
         function Make return Shape is
         begin
            return S : Shape := Default do
               S.Set_Selected_Space_Name ("@\A");
            end return;
         end Make;
         procedure Use_Shape (S : Shape) is
         begin
            Consume (S.Selected_Space_Name);
            Consume (S.Map (Moved).Selected_Space_Name);
         end Use_Shape;
         procedure Sweep is new Stream_Sweep (Shape, Name, Make, Use_Shape);
      begin
         Sweep;
      end Shape_Sweep;

      function Rectangle_Default return Ks_Rectangle is
        (Ks_Rectangle (Region_With (Rectangle, 0, 0.0)));
      function Affine_Default return Ks_Rectangle_Affine is
        (Ks_Rectangle_Affine (Region_With (Rectangle_Affine, 0, 0.0)));
      function Circle_Default return Ks_Circle is
        (Ks_Circle (Region_With (Circle, 0, 0.0)));
      function Ellipse_Default return Ks_Ellipse is
        (Ks_Ellipse (Region_With (Ellipse, 0, 0.0)));
      function Polygon_Default return Ks_Polygon is
        (Ks_Polygon (Region_With (Polygon, 0, 0.0)));
      function Annulus_Default return Ks_Circular_Annulus_Section is
        (Ks_Circular_Annulus_Section (Region_With (Annulus_Section, 0, 0.0)));
      function Segment_Default return Ks_Line_Segment is
      begin
         return S : Ks_Line_Segment;
      end Segment_Default;
      function Line_Default return Ks_Line is
      begin
         return L : Ks_Line;
      end Line_Default;
      function Marker_Default return Ks_Point_Marker is
      begin
         return M : Ks_Point_Marker;
      end Marker_Default;
      function Arc_Default return Ks_Circular_Arc is
      begin
         return A : Ks_Circular_Arc;
      end Arc_Default;

      procedure Rectangles is new Shape_Sweep
        (Ks_Rectangle, "Ks_Rectangle", Rectangle_Default);
      procedure Affine_Rectangles is new Shape_Sweep
        (Ks_Rectangle_Affine, "Ks_Rectangle_Affine", Affine_Default);
      procedure Circles is new Shape_Sweep
        (Ks_Circle, "Ks_Circle", Circle_Default);
      procedure Ellipses is new Shape_Sweep
        (Ks_Ellipse, "Ks_Ellipse", Ellipse_Default);
      procedure Polygons is new Shape_Sweep
        (Ks_Polygon, "Ks_Polygon", Polygon_Default);
      procedure Annulus_Sections is new Shape_Sweep
        (Ks_Circular_Annulus_Section, "Ks_Circular_Annulus_Section",
         Annulus_Default);
      procedure Line_Segments is new Shape_Sweep
        (Ks_Line_Segment, "Ks_Line_Segment", Segment_Default);
      procedure Lines is new Shape_Sweep (Ks_Line, "Ks_Line", Line_Default);
      procedure Point_Markers is new Shape_Sweep
        (Ks_Point_Marker, "Ks_Point_Marker", Marker_Default);
      procedure Circular_Arcs is new Shape_Sweep
        (Ks_Circular_Arc, "Ks_Circular_Arc", Arc_Default);

      function Make_CNL return AMV.CNL_Search.Ks_CNL_Search_Pattern is
      begin
         return P : AMV.CNL_Search.Ks_CNL_Search_Pattern do
            P.Set_Train_Image (Tiny_Scene);
            P.Set_Train_Image_Mask (Tiny_Scene);
            P.Train;
         end return;
      end Make_CNL;
      procedure Use_CNL (P : AMV.CNL_Search.Ks_CNL_Search_Pattern) is
      begin
         Consume (P.Trained);
         Consume (P.Trained_Pattern_Width);
         Consume (P.Origin_X);
      end Use_CNL;
      procedure CNL_Patterns is new Stream_Sweep
        (AMV.CNL_Search.Ks_CNL_Search_Pattern, "Ks_CNL_Search_Pattern",
         Make_CNL, Use_CNL);
      function Make_CNL_Affine
         return AMV.CNL_Search.Ks_CNL_Search_Pattern is
         Rectangle : Ks_Rectangle_Affine;
      begin
         Rectangle.Set_Center_Lengths_Rotation_Skew
           (5.5, 4.5, 9.0, 8.0, 0.1, 0.0);
         return P : AMV.CNL_Search.Ks_CNL_Search_Pattern do
            P.Set_Train_Image (Tiny_Scene);
            P.Set_Train_Region (RH.To_Holder (Rectangle));
            P.Set_Train_Region_Mode (AMV.CNL_Search.Affine_Transform);
            P.Set_Origin_X (5.0);
            P.Set_Origin_Y (4.0);
            P.Train;
         end return;
      end Make_CNL_Affine;
      procedure CNL_Affine_Patterns is new Stream_Sweep
        (AMV.CNL_Search.Ks_CNL_Search_Pattern,
         "Ks_CNL_Search_Pattern (AffineTransform)", Make_CNL_Affine,
         Use_CNL);

      function Make_PM return AMV.PM_Align.Ks_PM_Align_Pattern is
      begin
         return P : AMV.PM_Align.Ks_PM_Align_Pattern do
            P.Set_Train_Image (Small);
            P.Set_Train_Region
              (RH.To_Holder (Region_With (Rectangle, 0, 0.0)));
            P.Train;
         end return;
      end Make_PM;
      procedure Use_PM (P : AMV.PM_Align.Ks_PM_Align_Pattern) is
      begin
         Consume (P.Trained);
         Consume (Integer (AMV.PM_Align.Get_Trained_Features (P, True)
                             'Length));
      end Use_PM;
      procedure PM_Patterns is new Stream_Sweep
        (AMV.PM_Align.Ks_PM_Align_Pattern, "Ks_PM_Align_Pattern", Make_PM,
         Use_PM);

      function Make_Pairs return AMV.Calib_Fix.Ks_N_Point_To_N_Point is
      begin
         return P : AMV.Calib_Fix.Ks_N_Point_To_N_Point do
            P.Add_Point_Pair (0.0, 0.0, 1.0, 2.0);
            P.Add_Point_Pair (10.0, 0.0, 11.0, 2.0);
            P.Add_Point_Pair (0.0, 10.0, 1.0, 12.0);
         end return;
      end Make_Pairs;
      procedure Use_Pairs (P : AMV.Calib_Fix.Ks_N_Point_To_N_Point) is
      begin
         Consume (P.Num_Points);
         Consume (P.DOFs_To_Compute'Image);
         Use_Nothing (P.Compute_Group_A_From_Group_B_Transform);
      end Use_Pairs;
      procedure Pairs is new Stream_Sweep
        (AMV.Calib_Fix.Ks_N_Point_To_N_Point, "Ks_N_Point_To_N_Point",
         Make_Pairs, Use_Pairs);

      function Make_Calib return AMV.Calib_Fix.Ks_Calib_N_Point_To_N_Point
      is
      begin
         return C : AMV.Calib_Fix.Ks_Calib_N_Point_To_N_Point do
            C.Add_Point_Pair (0.0, 0.0, 1.0, 2.0);
            C.Add_Point_Pair (10.0, 0.0, 11.0, 2.0);
            C.Add_Point_Pair (0.0, 10.0, 1.0, 12.0);
            C.Calibrate;
         end return;
      end Make_Calib;
      procedure Use_Calib (C : AMV.Calib_Fix.Ks_Calib_N_Point_To_N_Point) is
      begin
         Consume (C.Calibrated);
         Use_Nothing (C.Get_Computed_Uncalibrated_From_Calibrated_Transform);
      end Use_Calib;
      procedure Calibrations is new Stream_Sweep
        (AMV.Calib_Fix.Ks_Calib_N_Point_To_N_Point,
         "Ks_Calib_N_Point_To_N_Point", Make_Calib, Use_Calib);

      function Make_Fixture return AMV.Calib_Fix.Ks_Fixture_N_Point_To_N_Point
      is
      begin
         return F : AMV.Calib_Fix.Ks_Fixture_N_Point_To_N_Point do
            F.Add_Point_Pair (0.0, 0.0, 1.0, 2.0);
            F.Add_Point_Pair (10.0, 0.0, 11.0, 2.0);
            F.Set_Fixtured_Space_Name ("Fx");
         end return;
      end Make_Fixture;
      procedure Use_Fixture
        (F : AMV.Calib_Fix.Ks_Fixture_N_Point_To_N_Point) is
      begin
         Consume (F.Num_Points);
         Consume (F.DOFs_To_Compute'Image);
         Consume (F.Fixtured_Space_Name);
         Consume (F.Space_To_Output'Image);
         Consume (F.Fixtured_Space_Name_Duplicate_Handling'Image);
      end Use_Fixture;
      procedure Fixtures is new Stream_Sweep
        (AMV.Calib_Fix.Ks_Fixture_N_Point_To_N_Point,
         "Ks_Fixture_N_Point_To_N_Point", Make_Fixture, Use_Fixture);

      function Make_Checkerboard return AMV.Calib_Fix.Ks_Calib_Checkerboard
      is
      begin
         return C : AMV.Calib_Fix.Ks_Calib_Checkerboard do
            C.Set_Calibration_Image (Tiny_Scene);
         end return;
      end Make_Checkerboard;
      procedure Use_Checkerboard
        (C : AMV.Calib_Fix.Ks_Calib_Checkerboard) is
      begin
         Consume (C.Calibrated);
         Consume (C.Calibration_Image.Width);
         Consume (C.DOFs_To_Compute'Image);
      end Use_Checkerboard;
      procedure Checkerboards is new Stream_Sweep
        (AMV.Calib_Fix.Ks_Calib_Checkerboard, "Ks_Calib_Checkerboard",
         Make_Checkerboard, Use_Checkerboard);

      function Make_Fit return AMV.Dimensioning.Fitting.Ks_Fit_Circle is
      begin
         return F : AMV.Dimensioning.Fitting.Ks_Fit_Circle do
            F.Add_Point (1.0, 0.0);
            F.Add_Point (0.0, 1.0);
            F.Add_Point (-1.0, 0.0);
            F.Add_Point (0.0, -1.0);
            F.Set_Radius_Constraint (2.0);
         end return;
      end Make_Fit;
      procedure Use_Fit (F : AMV.Dimensioning.Fitting.Ks_Fit_Circle) is
      begin
         Consume (F.Num_To_Ignore);
         Consume (F.Radius_Constraint_Enabled);
         Consume (AMV.Dimensioning.Fitting.Execute (F).RMS_Error);
      end Use_Fit;
      procedure Fits is new Stream_Sweep
        (AMV.Dimensioning.Fitting.Ks_Fit_Circle, "Ks_Fit_Circle", Make_Fit,
         Use_Fit);

      function Make_Ellipse_Fit
        return AMV.Dimensioning.Fitting.Ks_Fit_Ellipse is
      begin
         return F : AMV.Dimensioning.Fitting.Ks_Fit_Ellipse do
            F.Add_Point (2.0, 0.0);
            F.Add_Point (0.0, 1.0);
            F.Add_Point (-2.0, 0.0);
            F.Add_Point (0.0, -1.0);
            F.Add_Point (1.4, 0.7);
            F.Set_Num_To_Ignore (1);
            F.Set_Rotation_Constraint_Enabled (True);
         end return;
      end Make_Ellipse_Fit;
      procedure Use_Ellipse_Fit
        (F : AMV.Dimensioning.Fitting.Ks_Fit_Ellipse) is
      begin
         Consume (F.Num_To_Ignore);
         Consume (F.Rotation_Constraint_Enabled);
         Consume (F.Rotation_Constraint);
      end Use_Ellipse_Fit;
      procedure Ellipse_Fits is new Stream_Sweep
        (AMV.Dimensioning.Fitting.Ks_Fit_Ellipse, "Ks_Fit_Ellipse",
         Make_Ellipse_Fit, Use_Ellipse_Fit);

      function Make_Line_Fit return AMV.Dimensioning.Fitting.Ks_Fit_Line is
      begin
         return F : AMV.Dimensioning.Fitting.Ks_Fit_Line do
            F.Add_Point (0.0, 0.0);
            F.Add_Point (1.0, 1.0);
         end return;
      end Make_Line_Fit;
      procedure Use_Line_Fit (F : AMV.Dimensioning.Fitting.Ks_Fit_Line) is
      begin
         Consume (F.Num_Points);
         Consume (F.Num_To_Ignore);
      end Use_Line_Fit;
      procedure Line_Fits is new Stream_Sweep
        (AMV.Dimensioning.Fitting.Ks_Fit_Line, "Ks_Fit_Line", Make_Line_Fit,
         Use_Line_Fit);
   begin
      Begin_Area ("Streams");
      Images_8;
      Images_16;
      Images_24;
      Trees;
      Pixel_Regions;
      Real_Images;
      End_Area;

      Begin_Area ("Streams of shapes");
      Rectangles;
      Affine_Rectangles;
      Circles;
      Ellipses;
      Polygons;
      Annulus_Sections;
      Line_Segments;
      Lines;
      Point_Markers;
      Circular_Arcs;
      End_Area;

      Begin_Area ("Streams of patterns, calibrations and fits");
      CNL_Patterns;
      CNL_Affine_Patterns;
      PM_Patterns;
      Pairs;
      Calibrations;
      Fixtures;
      Checkerboards;
      Fits;
      Ellipse_Fits;
      Line_Fits;
      End_Area;
   end Sweep_Streams;

   procedure Run_All is
   begin
      Sweep_Misc;
      Sweep_Transforms;
      Sweep_Images;
      Sweep_Coordinate_Spaces;
      Sweep_Shapes;
      Sweep_Regions;
      Sweep_Image_Math;
      Sweep_Geometry;
      Sweep_Blob;
      Sweep_Caliper;
      Sweep_Find_Line;
      Sweep_Find_Circle;
      Sweep_Histogram;
      Sweep_Pixel_Map;
      Sweep_Sobel_Edge;
      Sweep_Sharpness;
      Sweep_IP_One_Image;
      Sweep_IP_Two_Image;
      Sweep_Affine_Transform;
      Sweep_Copy_Region;
      Sweep_Polar_Unwrap;
      Sweep_Image_Convert;
      Sweep_Dimensioning;
      Sweep_Create_Shapes;
      Sweep_Fitting;
      Sweep_Calib_Fix;
      Sweep_CNL_Search;
      Sweep_PM_Align;
      Sweep_Tool_Group;
      Sweep_Image_File;
      Sweep_Streams;
      Ada.Text_IO.Put_Line
        ("Robustness:" & Tool_Types'Image & " tool types," & All_Calls'Image
         & " calls," & All_Leaks'Image & " non-AMV exceptions ("
         & Consumed'Image & " results read)");
   end Run_All;

   procedure Main is new AMV_Test_Support.Standalone (Run_All);
begin
   Main;
end Test_Robustness;
