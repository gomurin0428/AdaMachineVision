pragma SPARK_Mode (Off);

private with Ada.Containers.Indefinite_Vectors;
private with Ada.Containers.Vectors;
private with Ada.Strings.Unbounded;

--  The JSON of the flow files: a reader that builds a document from text
--  and a writer that builds text, indented two spaces per level.
--
--  The reader treats its text as untrusted: it accepts exactly RFC 8259
--  JSON (no comments, no trailing commas, no leading zeros, no NaN), at
--  most Max_Text_Length characters (an optional UTF-8 byte order mark
--  first) and Max_Depth levels of arrays and objects, and rejects a key
--  that appears twice in an object, a control character in a string, an
--  escaped NUL, a lone surrogate and a number outside Long_Float. Strings
--  are returned in UTF-8; their other bytes are passed on unchanged.
--  Every failure raises AMV.Flow.Ks_Flow_Exception with the line and
--  column ("JSON line 3, column 14: expected ':'").

package AMV.Flow.JSON is

   type Kind_Type is
     (Null_Kind, Boolean_Kind, Number_Kind, String_Kind, Array_Kind,
      Object_Kind);

   Max_Text_Length : constant := 64 * 1024 * 1024;
   Max_Depth       : constant := 64;
   Max_Values      : constant := 4_000_000;

   ---------------------------------------------------------------------
   --  Reading
   ---------------------------------------------------------------------

   type Document is tagged private;
   --  A parsed JSON text; empty (no root) before Parse.

   type Node is private;
   --  A value within a document.

   No_Node : constant Node;
   --  What Member returns for a missing key.

   procedure Parse (Doc : out Document; Text : String);
   --  Parses Text. On failure Doc is left empty.

   function Root (Doc : Document) return Node;
   --  The top value; Ks_Flow_Exception for an empty document.

   function Kind (Doc : Document; N : Node) return Kind_Type;

   function Boolean_Value (Doc : Document; N : Node) return Boolean;
   function Number_Value (Doc : Document; N : Node) return Long_Float;
   function String_Value (Doc : Document; N : Node) return String;
   --  The value of N; Ks_Flow_Exception when N is of another kind.

   function Length (Doc : Document; N : Node) return Natural;
   --  The number of elements of an array or members of an object.

   function Element (Doc : Document; N : Node; Index : Positive) return Node;
   --  The element Index (1-based) of an array, or the value of the member
   --  Index of an object, in the order of the text.

   function Key (Doc : Document; N : Node; Index : Positive) return String;
   --  The key of the member Index of an object.

   function Member (Doc : Document; N : Node; Name : String) return Node;
   --  The value of the member Name of an object; No_Node when it has
   --  none.

   function Kind_Name (Kind : Kind_Type) return String;
   --  "null", "a Boolean", "a number", "a string", "an array",
   --  "an object": for messages.

   ---------------------------------------------------------------------
   --  Writing
   ---------------------------------------------------------------------

   type Writer is tagged private;
   --  Builds JSON text. Values go into the array or object most recently
   --  begun; a value in an object follows its Key. A container begun
   --  Inline (or inside an inline one) is written on one line.

   procedure Begin_Object (W : in out Writer; Inline : Boolean := False);
   procedure End_Object (W : in out Writer);
   procedure Begin_Array (W : in out Writer; Inline : Boolean := False);
   procedure End_Array (W : in out Writer);
   procedure Key (W : in out Writer; Name : String);

   procedure Value (W : in out Writer; Text : String);
   procedure Value (W : in out Writer; X : Long_Float);
   --  X must be finite (Ks_Flow_Exception otherwise).
   procedure Value (W : in out Writer; X : Long_Long_Integer);
   procedure Value (W : in out Writer; B : Boolean);
   procedure Null_Value (W : in out Writer);

   function Text (W : Writer) return String;
   --  The text written so far.

   function Quote (Text : String) return String;
   --  Text as a JSON string literal.

   function Number_Image (X : Long_Float) return String;
   --  The shortest decimal form of X (with at most 17 significant digits)
   --  that reads back as X: "0.6", "120.0", "3.141592653589793",
   --  "1.5E+20".

private

   use Ada.Strings.Unbounded;

   type Node is new Natural;
   No_Node : constant Node := 0;

   package Index_Vectors is new Ada.Containers.Vectors (Positive, Positive);
   package Key_Vectors is new Ada.Containers.Indefinite_Vectors
     (Positive, String);

   type Entry_Type is record
      Kind     : Kind_Type := Null_Kind;
      Bool     : Boolean := False;
      Number   : Long_Float := 0.0;
      Str      : Unbounded_String;      --  a string's value
      Keys     : Key_Vectors.Vector;    --  object members' keys
      Children : Index_Vectors.Vector;  --  elements or members' values
   end record;

   package Entry_Vectors is new Ada.Containers.Vectors (Positive, Entry_Type);

   type Document is tagged record
      Entries : Entry_Vectors.Vector;
   end record;

   type Level is record
      Is_Object : Boolean := False;
      Inline    : Boolean := False;
      Count     : Natural := 0;
   end record;

   package Level_Vectors is new Ada.Containers.Vectors (Positive, Level);

   type Writer is tagged record
      Buffer    : Unbounded_String;
      Levels    : Level_Vectors.Vector;
      After_Key : Boolean := False;
   end record;

end AMV.Flow.JSON;
