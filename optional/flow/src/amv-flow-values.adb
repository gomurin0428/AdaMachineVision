pragma SPARK_Mode (Off);

with Ada.Strings.Fixed;

package body AMV.Flow.Values is

   use AMV.Flow.JSON;

   function Has_Value (Value : Ks_Flow_Value) return Boolean is (Value.Set);

   function Kind (Value : Ks_Flow_Value) return Ks_Flow_Value_Type is
   begin
      if not Value.Set then
         raise Ks_Flow_Exception with "no value";
      end if;
      return Value.Kind;
   end Kind;

   function From_Real (X : Real) return Ks_Flow_Value is
   begin
      if not X'Valid or else abs X > Real'Last then
         raise AMV.Ks_Bad_Parameter_Exception with
           "a real value must be finite";
      end if;
      return (Set => True, Kind => Real_Type, Real_V => X, others => <>);
   end From_Real;

   function From_Integer (X : Long_Long_Integer) return Ks_Flow_Value is
     ((Set => True, Kind => Integer_Type, Integer_V => X, others => <>));

   function From_Boolean (X : Boolean) return Ks_Flow_Value is
     ((Set => True, Kind => Boolean_Type, Boolean_V => X, others => <>));

   function From_String (X : String) return Ks_Flow_Value is
     ((Set => True, Kind => String_Type,
       String_V => To_Unbounded_String (X), others => <>));

   function From_Image (X : AMV.Images.Ks_Image_8_Grey) return Ks_Flow_Value
   is ((Set => True, Kind => Image_8_Grey_Type, Image_V => X, others => <>));

   function From_Transform
     (X : AMV.Transforms.Ks_Transform_2D_Linear) return Ks_Flow_Value
   is ((Set => True, Kind => Transform_Type, Transform_V => X,
        others => <>));

   function From_Shape (X : AMV.Shapes.Ks_Shape'Class) return Ks_Flow_Value
   is ((Set => True, Kind => Shape_Type,
        Shape_V => Shape_Holders.To_Holder (X), others => <>));

   procedure Require (Value : Ks_Flow_Value; Kind : Ks_Flow_Value_Type) is
   begin
      if not Value.Set then
         raise Ks_Flow_Exception with
           "no value where " & Type_Name (Kind) & " is needed";
      elsif Value.Kind /= Kind then
         raise Ks_Flow_Exception with
           Type_Name (Value.Kind) & " where " & Type_Name (Kind)
           & " is needed";
      end if;
   end Require;

   function As_Real (Value : Ks_Flow_Value) return Real is
   begin
      if Value.Set and then Value.Kind = Integer_Type then
         return Real (Value.Integer_V);
      end if;
      Require (Value, Real_Type);
      return Value.Real_V;
   end As_Real;

   function As_Integer (Value : Ks_Flow_Value) return Long_Long_Integer is
   begin
      Require (Value, Integer_Type);
      return Value.Integer_V;
   end As_Integer;

   function As_Boolean (Value : Ks_Flow_Value) return Boolean is
   begin
      Require (Value, Boolean_Type);
      return Value.Boolean_V;
   end As_Boolean;

   function As_String (Value : Ks_Flow_Value) return String is
   begin
      Require (Value, String_Type);
      return To_String (Value.String_V);
   end As_String;

   function As_Image (Value : Ks_Flow_Value) return AMV.Images.Ks_Image_8_Grey
   is
   begin
      Require (Value, Image_8_Grey_Type);
      return Value.Image_V;
   end As_Image;

   function As_Transform
     (Value : Ks_Flow_Value) return AMV.Transforms.Ks_Transform_2D_Linear is
   begin
      Require (Value, Transform_Type);
      return Value.Transform_V;
   end As_Transform;

   function As_Shape (Value : Ks_Flow_Value) return AMV.Shapes.Ks_Shape'Class
   is
   begin
      Require (Value, Shape_Type);
      return Value.Shape_V.Element;
   end As_Shape;

   function Trimmed (S : String) return String is
     (Ada.Strings.Fixed.Trim (S, Ada.Strings.Both));

   function Shape_Type_Name (Shape : AMV.Shapes.Ks_Shape'Class) return String
   is
   begin
      if Shape in AMV.Shapes.Ks_Rectangle'Class then
         return "Rectangle";
      elsif Shape in AMV.Shapes.Ks_Rectangle_Affine'Class then
         return "RectangleAffine";
      elsif Shape in AMV.Shapes.Ks_Circle'Class then
         return "Circle";
      elsif Shape in AMV.Shapes.Ks_Ellipse'Class then
         return "Ellipse";
      elsif Shape in AMV.Shapes.Ks_Polygon'Class then
         return "Polygon";
      elsif Shape in AMV.Shapes.Ks_Circular_Annulus_Section'Class then
         return "CircularAnnulusSection";
      elsif Shape in AMV.Shapes.Ks_Line_Segment'Class then
         return "LineSegment";
      elsif Shape in AMV.Shapes.Ks_Line'Class then
         return "Line";
      elsif Shape in AMV.Shapes.Ks_Point_Marker'Class then
         return "PointMarker";
      elsif Shape in AMV.Shapes.Ks_Circular_Arc'Class then
         return "CircularArc";
      else
         return "Shape";
      end if;
   end Shape_Type_Name;

   function Image (Value : Ks_Flow_Value) return String is
   begin
      if not Value.Set then
         return "";
      end if;
      case Value.Kind is
         when Real_Type =>
            return AMV.Flow.JSON.Number_Image (Value.Real_V);
         when Integer_Type =>
            return Trimmed (Value.Integer_V'Image);
         when Boolean_Type =>
            return (if Value.Boolean_V then "true" else "false");
         when String_Type =>
            return To_String (Value.String_V);
         when Image_8_Grey_Type =>
            return "image" & Value.Image_V.Width'Image & "x"
              & Trimmed (Value.Image_V.Height'Image);
         when Transform_Type =>
            return "transform";
         when Shape_Type =>
            return Shape_Type_Name (Value.Shape_V.Element);
      end case;
   end Image;

   ---------------------------------------------------------------------
   --  Shapes in flow files
   ---------------------------------------------------------------------

   procedure Write_Shape (W     : in out AMV.Flow.JSON.Writer;
                          Shape : AMV.Shapes.Ks_Shape'Class)
   is
      procedure Number (Name : String; X : Real) is
      begin
         W.Key (Name);
         W.Value (X);
      end Number;
   begin
      W.Begin_Object (Inline => True);
      W.Key ("shape");
      W.Value (Shape_Type_Name (Shape));
      W.Key ("space");
      W.Value (Shape.Selected_Space_Name);
      if Shape in AMV.Shapes.Ks_Rectangle'Class then
         declare
            R : constant AMV.Shapes.Ks_Rectangle :=
              AMV.Shapes.Ks_Rectangle (Shape);
         begin
            Number ("centerX", R.Center_X);
            Number ("centerY", R.Center_Y);
            Number ("width", R.Width);
            Number ("height", R.Height);
         end;
      elsif Shape in AMV.Shapes.Ks_Rectangle_Affine'Class then
         declare
            R : constant AMV.Shapes.Ks_Rectangle_Affine :=
              AMV.Shapes.Ks_Rectangle_Affine (Shape);
         begin
            Number ("centerX", R.Center_X);
            Number ("centerY", R.Center_Y);
            Number ("sideX", R.Side_X_Length);
            Number ("sideY", R.Side_Y_Length);
            Number ("rotation", R.Rotation);
            Number ("skew", R.Skew);
         end;
      elsif Shape in AMV.Shapes.Ks_Circle'Class then
         declare
            C : constant AMV.Shapes.Ks_Circle := AMV.Shapes.Ks_Circle (Shape);
         begin
            Number ("centerX", C.Center_X);
            Number ("centerY", C.Center_Y);
            Number ("radius", C.Radius);
         end;
      else
         raise Ks_Flow_Exception with
           "a " & Shape_Type_Name (Shape) & " cannot be saved yet";
      end if;
      W.End_Object;
   end Write_Shape;

   function Read_Shape (Doc : AMV.Flow.JSON.Document;
                        N   : AMV.Flow.JSON.Node)
                        return AMV.Shapes.Ks_Shape'Class
   is
      Type_Node : Node;
      Used      : Natural := 1;

      function Number (Name : String) return Real is
         M : constant Node := Member (Doc, N, Name);
      begin
         if M = No_Node then
            raise Ks_Flow_Exception with "the shape has no """ & Name & """";
         end if;
         Used := Used + 1;
         return Number_Value (Doc, M);
      end Number;

      function Space return String is
         M : constant Node := Member (Doc, N, "space");
      begin
         if M = No_Node then
            return ".";
         end if;
         Used := Used + 1;
         return String_Value (Doc, M);
      end Space;

      procedure Check_All_Used is
      begin
         if Used /= Length (Doc, N) then
            raise Ks_Flow_Exception with
              "the shape has members that a " & String_Value (Doc, Type_Node)
              & " does not have";
         end if;
      end Check_All_Used;
   begin
      if Kind (Doc, N) /= Object_Kind then
         raise Ks_Flow_Exception with
           "a shape must be an object, not " & Kind_Name (Kind (Doc, N));
      end if;
      Type_Node := Member (Doc, N, "shape");
      if Type_Node = No_Node then
         raise Ks_Flow_Exception with "the shape has no ""shape"" (its type)";
      end if;
      declare
         Type_Name_Text : constant String := String_Value (Doc, Type_Node);
      begin
         if Type_Name_Text = "Rectangle" then
            declare
               R : AMV.Shapes.Ks_Rectangle;
            begin
               R.Set_Selected_Space_Name (Space);
               R.Set_Center_Width_Height
                 (Number ("centerX"), Number ("centerY"), Number ("width"),
                  Number ("height"));
               Check_All_Used;
               return R;
            end;
         elsif Type_Name_Text = "RectangleAffine" then
            declare
               R : AMV.Shapes.Ks_Rectangle_Affine;
            begin
               R.Set_Selected_Space_Name (Space);
               R.Set_Center_Lengths_Rotation_Skew
                 (Number ("centerX"), Number ("centerY"), Number ("sideX"),
                  Number ("sideY"), Number ("rotation"), Number ("skew"));
               Check_All_Used;
               return R;
            end;
         elsif Type_Name_Text = "Circle" then
            declare
               C : AMV.Shapes.Ks_Circle;
            begin
               C.Set_Selected_Space_Name (Space);
               C.Set_Center_Radius
                 (Number ("centerX"), Number ("centerY"), Number ("radius"));
               Check_All_Used;
               return C;
            end;
         else
            raise Ks_Flow_Exception with
              "unknown shape type """ & Type_Name_Text & """";
         end if;
      end;
   end Read_Shape;

end AMV.Flow.Values;
