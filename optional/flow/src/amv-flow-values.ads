pragma SPARK_Mode (Off);

with AMV.Flow.JSON;
with AMV.Images;
with AMV.Shapes;
with AMV.Transforms;

private with Ada.Containers.Indefinite_Holders;
private with Ada.Strings.Unbounded;

--  The values that ports, parameters and flow inputs and outputs hold: a
--  type (AMV.Flow.Ks_Flow_Value_Type) and, once set, a value of it.
--  Images share their pixels as AMV images do; shapes and transforms are
--  copied.

package AMV.Flow.Values is

   type Ks_Flow_Value is tagged private;
   --  No_Value by default.

   No_Value : constant Ks_Flow_Value;

   function Has_Value (Value : Ks_Flow_Value) return Boolean;
   function Kind (Value : Ks_Flow_Value) return Ks_Flow_Value_Type;
   --  The type of a value that has one (Ks_Flow_Exception otherwise).

   function From_Real (X : Real) return Ks_Flow_Value;
   --  X must be finite (AMV.Ks_Bad_Parameter_Exception otherwise).
   function From_Integer (X : Long_Long_Integer) return Ks_Flow_Value;
   function From_Boolean (X : Boolean) return Ks_Flow_Value;
   function From_String (X : String) return Ks_Flow_Value;
   function From_Image (X : AMV.Images.Ks_Image_8_Grey) return Ks_Flow_Value;
   function From_Transform
     (X : AMV.Transforms.Ks_Transform_2D_Linear) return Ks_Flow_Value;
   function From_Shape (X : AMV.Shapes.Ks_Shape'Class) return Ks_Flow_Value;

   --  The value as a type: the type it has, or Real from Integer. Another
   --  type, or no value, raises Ks_Flow_Exception.
   function As_Real (Value : Ks_Flow_Value) return Real;
   function As_Integer (Value : Ks_Flow_Value) return Long_Long_Integer;
   function As_Boolean (Value : Ks_Flow_Value) return Boolean;
   function As_String (Value : Ks_Flow_Value) return String;
   function As_Image (Value : Ks_Flow_Value) return AMV.Images.Ks_Image_8_Grey;
   function As_Transform
     (Value : Ks_Flow_Value) return AMV.Transforms.Ks_Transform_2D_Linear;
   function As_Shape (Value : Ks_Flow_Value) return AMV.Shapes.Ks_Shape'Class;

   function Image (Value : Ks_Flow_Value) return String;
   --  A short text for logs and CSV: a number, true / false, the string,
   --  "image 640x480", "transform", the shape's type; "" for no value.

   ---------------------------------------------------------------------
   --  Shapes in flow files
   ---------------------------------------------------------------------

   --  A shape is written as an object with "shape" (its type), "space"
   --  (its selected space name) and its geometry:
   --     Rectangle:        centerX, centerY, width, height
   --     RectangleAffine:  centerX, centerY, sideX, sideY, rotation, skew
   --     Circle:           centerX, centerY, radius
   --  Lengths in the space's units, angles in radians. Other shape types
   --  cannot be written yet (Ks_Flow_Exception).

   procedure Write_Shape (W     : in out AMV.Flow.JSON.Writer;
                          Shape : AMV.Shapes.Ks_Shape'Class);

   function Read_Shape (Doc : AMV.Flow.JSON.Document;
                        N   : AMV.Flow.JSON.Node)
                        return AMV.Shapes.Ks_Shape'Class;
   --  Ks_Flow_Exception for an unknown type, a missing or extra member, a
   --  value of the wrong kind; the shape's own setters reject values out
   --  of range (AMV.Ks_Bad_Parameter_Exception).

private

   use Ada.Strings.Unbounded;

   package Shape_Holders is new Ada.Containers.Indefinite_Holders
     (AMV.Shapes.Ks_Shape'Class, AMV.Shapes."=");

   type Ks_Flow_Value is tagged record
      Set       : Boolean := False;
      Kind      : Ks_Flow_Value_Type := Real_Type;
      Real_V    : Real := 0.0;
      Integer_V : Long_Long_Integer := 0;
      Boolean_V : Boolean := False;
      String_V  : Unbounded_String;
      Image_V   : AMV.Images.Ks_Image_8_Grey;
      Transform_V : AMV.Transforms.Ks_Transform_2D_Linear;
      Shape_V   : Shape_Holders.Holder;
   end record;

   No_Value : constant Ks_Flow_Value := (others => <>);

end AMV.Flow.Values;
