pragma SPARK_Mode (Off);

with Ada.Characters.Latin_1;
with Ada.Long_Float_Text_IO;
with Ada.Strings.Fixed;

package body AMV.Flow.JSON is

   package L1 renames Ada.Characters.Latin_1;

   ---------------------------------------------------------------------
   --  Reading
   ---------------------------------------------------------------------

   procedure Parse (Doc : out Document; Text : String) is
      Pos : Natural := Text'First;

      procedure Fail (Message : String) with No_Return;

      procedure Fail (Message : String) is
         Line   : Natural := 1;
         Column : Natural := 1;
      begin
         for I in Text'First .. Natural'Min (Pos, Text'Last + 1) - 1 loop
            if Text (I) = L1.LF then
               Line := Line + 1;
               Column := 1;
            else
               Column := Column + 1;
            end if;
         end loop;
         Doc.Entries.Clear;
         raise Ks_Flow_Exception with
           "JSON line" & Line'Image & ", column" & Column'Image & ": "
           & Message;
      end Fail;

      function At_End return Boolean is (Pos > Text'Last);

      procedure Skip_Space is
      begin
         while not At_End
           and then Text (Pos) in ' ' | L1.HT | L1.LF | L1.CR
         loop
            Pos := Pos + 1;
         end loop;
      end Skip_Space;

      procedure Expect (C : Character) is
      begin
         if At_End or else Text (Pos) /= C then
            Fail ("expected '" & C & "'");
         end if;
         Pos := Pos + 1;
      end Expect;

      function Add (E : Entry_Type) return Positive is
      begin
         if Natural (Doc.Entries.Length) >= Max_Values then
            Fail ("more than" & Max_Values'Image & " values");
         end if;
         Doc.Entries.Append (E);
         return Positive (Doc.Entries.Length);
      end Add;

      function New_Entry (Kind : Kind_Type) return Positive is
        (Add (Entry_Type'(Kind => Kind, others => <>)));

      procedure Append_UTF_8 (Buffer : in out Unbounded_String;
                              Code   : Natural) is
         function Byte (Value : Natural) return Character is
           (Character'Val (Value));
      begin
         if Code < 16#80# then
            Append (Buffer, Byte (Code));
         elsif Code < 16#800# then
            Append (Buffer, Byte (16#C0# + Code / 64));
            Append (Buffer, Byte (16#80# + Code mod 64));
         elsif Code < 16#1_0000# then
            Append (Buffer, Byte (16#E0# + Code / 4096));
            Append (Buffer, Byte (16#80# + (Code / 64) mod 64));
            Append (Buffer, Byte (16#80# + Code mod 64));
         else
            Append (Buffer, Byte (16#F0# + Code / 262_144));
            Append (Buffer, Byte (16#80# + (Code / 4096) mod 64));
            Append (Buffer, Byte (16#80# + (Code / 64) mod 64));
            Append (Buffer, Byte (16#80# + Code mod 64));
         end if;
      end Append_UTF_8;

      function Hex_4 return Natural is
         Value : Natural := 0;
         Digit : Natural;
      begin
         for I in 1 .. 4 loop
            if At_End then
               Fail ("unterminated \u escape");
            end if;
            case Text (Pos) is
               when '0' .. '9' =>
                  Digit := Character'Pos (Text (Pos)) - Character'Pos ('0');
               when 'a' .. 'f' =>
                  Digit := Character'Pos (Text (Pos)) - Character'Pos ('a')
                    + 10;
               when 'A' .. 'F' =>
                  Digit := Character'Pos (Text (Pos)) - Character'Pos ('A')
                    + 10;
               when others =>
                  Fail ("bad hexadecimal digit in a \u escape");
            end case;
            Value := Value * 16 + Digit;
            Pos := Pos + 1;
         end loop;
         return Value;
      end Hex_4;

      function Parse_String return String is
         Buffer : Unbounded_String;
         C      : Character;
         Code   : Natural;
         Low    : Natural;
      begin
         Expect ('"');
         loop
            if At_End then
               Fail ("unterminated string");
            end if;
            C := Text (Pos);
            if C = '"' then
               Pos := Pos + 1;
               exit;
            elsif C = '\' then
               Pos := Pos + 1;
               if At_End then
                  Fail ("unterminated string");
               end if;
               C := Text (Pos);
               Pos := Pos + 1;
               case C is
                  when '"' | '\' | '/' => Append (Buffer, C);
                  when 'b' => Append (Buffer, L1.BS);
                  when 'f' => Append (Buffer, L1.FF);
                  when 'n' => Append (Buffer, L1.LF);
                  when 'r' => Append (Buffer, L1.CR);
                  when 't' => Append (Buffer, L1.HT);
                  when 'u' =>
                     Code := Hex_4;
                     if Code in 16#D800# .. 16#DBFF# then
                        if Pos + 1 > Text'Last or else Text (Pos) /= '\'
                          or else Text (Pos + 1) /= 'u'
                        then
                           Fail ("lone surrogate in a \u escape");
                        end if;
                        Pos := Pos + 2;
                        Low := Hex_4;
                        if Low not in 16#DC00# .. 16#DFFF# then
                           Fail ("lone surrogate in a \u escape");
                        end if;
                        Code := 16#1_0000# + (Code - 16#D800#) * 1024
                          + (Low - 16#DC00#);
                     elsif Code in 16#DC00# .. 16#DFFF# then
                        Fail ("lone surrogate in a \u escape");
                     elsif Code = 0 then
                        Fail ("escaped NUL in a string");
                     end if;
                     Append_UTF_8 (Buffer, Code);
                  when others =>
                     Fail ("bad escape '\" & C & "'");
               end case;
            elsif Character'Pos (C) < 32 then
               Fail ("control character in a string");
            else
               Append (Buffer, C);
               Pos := Pos + 1;
            end if;
         end loop;
         return To_String (Buffer);
      end Parse_String;

      function Parse_Number return Long_Float is
         Start    : constant Positive := Pos;
         Has_Frac : Boolean := False;
         Exp_At   : Natural := 0;

         procedure Digits_Needed is
         begin
            if At_End or else Text (Pos) not in '0' .. '9' then
               Fail ("bad number");
            end if;
            while not At_End and then Text (Pos) in '0' .. '9' loop
               Pos := Pos + 1;
            end loop;
         end Digits_Needed;
      begin
         if Text (Pos) = '-' then
            Pos := Pos + 1;
         end if;
         if not At_End and then Text (Pos) = '0' then
            Pos := Pos + 1;
            if not At_End and then Text (Pos) in '0' .. '9' then
               Fail ("leading zero in a number");
            end if;
         else
            Digits_Needed;
         end if;
         if not At_End and then Text (Pos) = '.' then
            Pos := Pos + 1;
            Has_Frac := True;
            Digits_Needed;
         end if;
         if not At_End and then Text (Pos) in 'e' | 'E' then
            Exp_At := Pos;
            Pos := Pos + 1;
            if not At_End and then Text (Pos) in '+' | '-' then
               Pos := Pos + 1;
            end if;
            Digits_Needed;
         end if;
         if Pos - Start > 100 then
            Fail ("number too long");
         end if;
         declare
            Literal : constant String := Text (Start .. Pos - 1);
            --  Ada's 'Value wants a point in a real literal.
            Ada_Literal : constant String :=
              (if Has_Frac then Literal
               elsif Exp_At = 0 then Literal & ".0"
               else Text (Start .. Exp_At - 1) & ".0"
                    & Text (Exp_At .. Pos - 1));
            X : Long_Float;
         begin
            X := Long_Float'Value (Ada_Literal);
            if not X'Valid or else abs X > Long_Float'Last then
               Fail ("number out of range");
            end if;
            return X;
         exception
            when Constraint_Error =>
               Fail ("number out of range");
         end;
      end Parse_Number;

      procedure Parse_Keyword (Word : String) is
      begin
         if Pos + Word'Length - 1 > Text'Last
           or else Text (Pos .. Pos + Word'Length - 1) /= Word
         then
            Fail ("unexpected character '" & Text (Pos) & "'");
         end if;
         Pos := Pos + Word'Length;
      end Parse_Keyword;

      function Parse_Value (Depth : Natural) return Positive is
         Index : Positive;
      begin
         Skip_Space;
         if At_End then
            Fail ("expected a value");
         end if;
         case Text (Pos) is
            when '{' =>
               if Depth >= Max_Depth then
                  Fail ("more than" & Max_Depth'Image & " levels");
               end if;
               Pos := Pos + 1;
               Index := New_Entry (Object_Kind);
               Skip_Space;
               if not At_End and then Text (Pos) = '}' then
                  Pos := Pos + 1;
                  return Index;
               end if;
               loop
                  Skip_Space;
                  declare
                     Name  : constant String := Parse_String;
                     Child : Positive;
                  begin
                     if Doc.Entries (Index).Keys.Contains (Name) then
                        Fail ("key """ & Name & """ appears twice");
                     end if;
                     Skip_Space;
                     Expect (':');
                     Child := Parse_Value (Depth + 1);
                     Doc.Entries (Index).Keys.Append (Name);
                     Doc.Entries (Index).Children.Append (Child);
                  end;
                  Skip_Space;
                  if not At_End and then Text (Pos) = ',' then
                     Pos := Pos + 1;
                  else
                     Expect ('}');
                     exit;
                  end if;
               end loop;
               return Index;

            when '[' =>
               if Depth >= Max_Depth then
                  Fail ("more than" & Max_Depth'Image & " levels");
               end if;
               Pos := Pos + 1;
               Index := New_Entry (Array_Kind);
               Skip_Space;
               if not At_End and then Text (Pos) = ']' then
                  Pos := Pos + 1;
                  return Index;
               end if;
               loop
                  declare
                     Child : constant Positive := Parse_Value (Depth + 1);
                  begin
                     Doc.Entries (Index).Children.Append (Child);
                  end;
                  Skip_Space;
                  if not At_End and then Text (Pos) = ',' then
                     Pos := Pos + 1;
                  else
                     Expect (']');
                     exit;
                  end if;
               end loop;
               return Index;

            when '"' =>
               declare
                  Value : constant String := Parse_String;
               begin
                  return Add (Entry_Type'(Kind => String_Kind,
                                          Str  => To_Unbounded_String (Value),
                                          others => <>));
               end;

            when '-' | '0' .. '9' =>
               declare
                  Value : constant Long_Float := Parse_Number;
               begin
                  return Add (Entry_Type'(Kind => Number_Kind,
                                          Number => Value, others => <>));
               end;

            when 't' =>
               Parse_Keyword ("true");
               return Add (Entry_Type'(Kind => Boolean_Kind, Bool => True,
                                       others => <>));

            when 'f' =>
               Parse_Keyword ("false");
               return New_Entry (Boolean_Kind);

            when 'n' =>
               Parse_Keyword ("null");
               return New_Entry (Null_Kind);

            when others =>
               Fail ("unexpected character '" & Text (Pos) & "'");
         end case;
      end Parse_Value;

      Ignore : Positive;
   begin
      Doc.Entries.Clear;
      if Text'Length > Max_Text_Length then
         Fail ("text longer than" & Max_Text_Length'Image & " characters");
      end if;
      if Text'Length >= 3
        and then Text (Pos .. Pos + 2) = Character'Val (16#EF#)
                 & Character'Val (16#BB#) & Character'Val (16#BF#)
      then
         Pos := Pos + 3;
      end if;
      Ignore := Parse_Value (0);
      Skip_Space;
      if not At_End then
         Fail ("text after the JSON value");
      end if;
   end Parse;

   function Get (Doc : Document; N : Node) return Entry_Type is
   begin
      if N = No_Node or else Natural (N) > Natural (Doc.Entries.Length) then
         raise Ks_Flow_Exception with "no such JSON value";
      end if;
      return Doc.Entries (Positive (N));
   end Get;

   function Kind_Name (Kind : Kind_Type) return String is
   begin
      case Kind is
         when Null_Kind    => return "null";
         when Boolean_Kind => return "a Boolean";
         when Number_Kind  => return "a number";
         when String_Kind  => return "a string";
         when Array_Kind   => return "an array";
         when Object_Kind  => return "an object";
      end case;
   end Kind_Name;

   procedure Require (Doc : Document; N : Node; Kind : Kind_Type) is
      Actual : constant Kind_Type := Get (Doc, N).Kind;
   begin
      if Actual /= Kind then
         raise Ks_Flow_Exception with
           "expected " & Kind_Name (Kind) & ", found " & Kind_Name (Actual);
      end if;
   end Require;

   function Root (Doc : Document) return Node is
   begin
      if Doc.Entries.Is_Empty then
         raise Ks_Flow_Exception with "empty JSON document";
      end if;
      return 1;
   end Root;

   function Kind (Doc : Document; N : Node) return Kind_Type is
     (Get (Doc, N).Kind);

   function Boolean_Value (Doc : Document; N : Node) return Boolean is
   begin
      Require (Doc, N, Boolean_Kind);
      return Doc.Entries (Positive (N)).Bool;
   end Boolean_Value;

   function Number_Value (Doc : Document; N : Node) return Long_Float is
   begin
      Require (Doc, N, Number_Kind);
      return Doc.Entries (Positive (N)).Number;
   end Number_Value;

   function String_Value (Doc : Document; N : Node) return String is
   begin
      Require (Doc, N, String_Kind);
      return To_String (Doc.Entries (Positive (N)).Str);
   end String_Value;

   function Length (Doc : Document; N : Node) return Natural is
      E : constant Entry_Type := Get (Doc, N);
   begin
      if E.Kind not in Array_Kind | Object_Kind then
         raise Ks_Flow_Exception with
           "expected an array or an object, found " & Kind_Name (E.Kind);
      end if;
      return Natural (E.Children.Length);
   end Length;

   function Element (Doc : Document; N : Node; Index : Positive) return Node
   is
   begin
      if Index > Length (Doc, N) then
         raise Ks_Flow_Exception with "no element" & Index'Image;
      end if;
      return Node (Doc.Entries (Positive (N)).Children (Index));
   end Element;

   function Key (Doc : Document; N : Node; Index : Positive) return String is
   begin
      Require (Doc, N, Object_Kind);
      if Index > Length (Doc, N) then
         raise Ks_Flow_Exception with "no member" & Index'Image;
      end if;
      return Doc.Entries (Positive (N)).Keys (Index);
   end Key;

   function Member (Doc : Document; N : Node; Name : String) return Node is
   begin
      Require (Doc, N, Object_Kind);
      declare
         Position : constant Natural :=
           Doc.Entries (Positive (N)).Keys.Find_Index (Name);
      begin
         if Position = Key_Vectors.No_Index then
            return No_Node;
         end if;
         return Node (Doc.Entries (Positive (N)).Children (Position));
      end;
   end Member;

   ---------------------------------------------------------------------
   --  Writing
   ---------------------------------------------------------------------

   function Quote (Text : String) return String is
      Result : Unbounded_String := To_Unbounded_String ("""");
      Hex    : constant String := "0123456789abcdef";
   begin
      for C of Text loop
         case C is
            when '"' => Append (Result, "\""");
            when '\' => Append (Result, "\\");
            when L1.LF => Append (Result, "\n");
            when L1.CR => Append (Result, "\r");
            when L1.HT => Append (Result, "\t");
            when L1.BS => Append (Result, "\b");
            when L1.FF => Append (Result, "\f");
            when others =>
               if Character'Pos (C) < 32 then
                  Append (Result, "\u00");
                  Append (Result, Hex (Character'Pos (C) / 16 + 1));
                  Append (Result, Hex (Character'Pos (C) mod 16 + 1));
               else
                  Append (Result, C);
               end if;
         end case;
      end loop;
      Append (Result, '"');
      return To_String (Result);
   end Quote;

   function Number_Image (X : Long_Float) return String is
      Buffer : String (1 .. 64);
   begin
      if not X'Valid or else abs X > Long_Float'Last then
         raise Ks_Flow_Exception with "a number that is not finite";
      end if;
      if X = 0.0 then
         return "0.0";
      end if;
      if abs X >= 1.0E-4 and then abs X < 1.0E15 then
         for Aft in 1 .. 17 loop
            Ada.Long_Float_Text_IO.Put (Buffer, X, Aft => Aft, Exp => 0);
            declare
               Image : constant String :=
                 Ada.Strings.Fixed.Trim (Buffer, Ada.Strings.Both);
            begin
               if Long_Float'Value (Image) = X then
                  return Image;
               end if;
            end;
         end loop;
      end if;
      for Aft in 1 .. 17 loop
         Ada.Long_Float_Text_IO.Put (Buffer, X, Aft => Aft, Exp => 1);
         declare
            Image : constant String :=
              Ada.Strings.Fixed.Trim (Buffer, Ada.Strings.Both);
         begin
            if Long_Float'Value (Image) = X or else Aft = 17 then
               return Image;
            end if;
         end;
      end loop;
      raise Program_Error;  --  not reached: Aft = 17 returns
   end Number_Image;

   function Inline_Now (W : Writer) return Boolean is
     (not W.Levels.Is_Empty and then W.Levels.Last_Element.Inline);

   procedure New_Line (W : in out Writer; Depth : Natural) is
   begin
      Append (W.Buffer, L1.LF & [1 .. 2 * Depth => ' ']);
   end New_Line;

   procedure Before_Value (W : in out Writer) is
   begin
      if W.After_Key then
         W.After_Key := False;
         return;
      end if;
      if W.Levels.Is_Empty then
         return;
      end if;
      declare
         L : Level renames W.Levels (W.Levels.Last_Index);
      begin
         if L.Count > 0 then
            Append (W.Buffer, ',');
         end if;
         if L.Inline then
            if L.Count > 0 then
               Append (W.Buffer, ' ');
            end if;
         else
            New_Line (W, Natural (W.Levels.Length));
         end if;
         L.Count := L.Count + 1;
      end;
   end Before_Value;

   procedure Begin_Container (W : in out Writer; Object : Boolean;
                              Inline : Boolean) is
      Nested_Inline : constant Boolean := Inline or else Inline_Now (W);
   begin
      Before_Value (W);
      Append (W.Buffer, (if Object then '{' else '['));
      W.Levels.Append (Level'(Is_Object => Object, Inline => Nested_Inline,
                               Count => 0));
   end Begin_Container;

   procedure End_Container (W : in out Writer; Object : Boolean) is
   begin
      if W.Levels.Is_Empty or else W.Levels.Last_Element.Is_Object /= Object
        or else W.After_Key
      then
         raise Program_Error with "JSON writer: unbalanced containers";
      end if;
      declare
         L : constant Level := W.Levels.Last_Element;
      begin
         W.Levels.Delete_Last;
         if not L.Inline and then L.Count > 0 then
            New_Line (W, Natural (W.Levels.Length));
         end if;
         Append (W.Buffer, (if Object then '}' else ']'));
      end;
   end End_Container;

   procedure Begin_Object (W : in out Writer; Inline : Boolean := False) is
   begin
      Begin_Container (W, Object => True, Inline => Inline);
   end Begin_Object;

   procedure End_Object (W : in out Writer) is
   begin
      End_Container (W, Object => True);
   end End_Object;

   procedure Begin_Array (W : in out Writer; Inline : Boolean := False) is
   begin
      Begin_Container (W, Object => False, Inline => Inline);
   end Begin_Array;

   procedure End_Array (W : in out Writer) is
   begin
      End_Container (W, Object => False);
   end End_Array;

   procedure Key (W : in out Writer; Name : String) is
   begin
      if W.Levels.Is_Empty or else not W.Levels.Last_Element.Is_Object
        or else W.After_Key
      then
         raise Program_Error with "JSON writer: a key outside an object";
      end if;
      Before_Value (W);
      Append (W.Buffer, Quote (Name) & ": ");
      W.After_Key := True;
   end Key;

   procedure Value (W : in out Writer; Text : String) is
   begin
      Before_Value (W);
      Append (W.Buffer, Quote (Text));
   end Value;

   procedure Value (W : in out Writer; X : Long_Float) is
      Image : constant String := Number_Image (X);
   begin
      Before_Value (W);
      Append (W.Buffer, Image);
   end Value;

   procedure Value (W : in out Writer; X : Long_Long_Integer) is
   begin
      Before_Value (W);
      Append (W.Buffer,
              Ada.Strings.Fixed.Trim (X'Image, Ada.Strings.Both));
   end Value;

   procedure Value (W : in out Writer; B : Boolean) is
   begin
      Before_Value (W);
      Append (W.Buffer, (if B then "true" else "false"));
   end Value;

   procedure Null_Value (W : in out Writer) is
   begin
      Before_Value (W);
      Append (W.Buffer, "null");
   end Null_Value;

   function Text (W : Writer) return String is (To_String (W.Buffer));

end AMV.Flow.JSON;
