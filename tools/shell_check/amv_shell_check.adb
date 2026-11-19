--  amv_shell_check SRC_DIR LEGACY_LIST
--
--  Checks that the bodies of the Ada API stay thin wrappers around the
--  SPARK kernels (docs/DESIGN.md section 9). It reads every
--  SRC_DIR/amv-*.adb except the kernels (amv-kernels*.adb) and the files
--  named in LEGACY_LIST (one file name per line; "#" starts a comment),
--  which hold code that has not moved into a kernel yet.
--
--  Outside comments, string literals and character literals, it reports:
--
--  * loops: the reserved word "loop" and quantified expressions
--    ("for all", "for some");
--  * any mention of Ada.Numerics;
--  * real (floating point) literals such as 1.0 or 2.5E3;
--  * arithmetic operators: + - * / ** mod rem abs.
--
--  A line whose comment contains "SHELL:" followed by a reason is
--  accepted as it is (for example the timing arithmetic in Run).
--
--  It also reports every SRC_DIR/amv-*.ads and amv-*.adb outside the
--  kernels (the legacy files included) that does not have the line
--  pragma Validity_Checks ("F"); before its library unit: the Ada API
--  passes NaNs and infinities on to the kernels, which reject them with
--  Bad_Parameter, and must not raise Constraint_Error on them itself
--  (docs/DESIGN.md section 9.3).
--
--  The specifications of the kernels (SRC_DIR/amv-spec*.ads and .adb) are
--  SPARK, not wrappers, and are not read as the bodies above are. A unit
--  of them that is not ghost, or that depends on a unit other than
--  AMV.Spec and its children, AMV.Kernels, Interfaces and the big numbers
--  of Ada 2022, is reported (src/amv-spec.ads).
--
--  And it reports every pragma Assertion_Policy in SRC_DIR/amv-*.ads and
--  amv-*.adb, the kernels included: the policies of the library and of
--  the tests are configuration pragma files (contracts.adc,
--  tests/contracts.adc; docs/DESIGN.md section 9.2).
--
--  Prints one line per finding as FILE:LINE:COLUMN: message, and exits
--  with status 1 when there is any finding (2 for a usage error).

with Ada.Characters.Handling;
with Ada.Command_Line;
with Ada.Containers.Indefinite_Ordered_Sets;
with Ada.Directories;
with Ada.Strings.Fixed;
with Ada.Text_IO;

procedure AMV_Shell_Check is

   use Ada.Characters.Handling;
   use Ada.Text_IO;

   package Name_Sets is new Ada.Containers.Indefinite_Ordered_Sets (String);

   Findings : Natural := 0;

   procedure Report (File : String; Line, Column : Positive; What : String)
   is
   begin
      Findings := Findings + 1;
      Put_Line (File & ":" & Ada.Strings.Fixed.Trim (Line'Image, Ada.Strings.Left)
                & ":" & Ada.Strings.Fixed.Trim (Column'Image, Ada.Strings.Left)
                & ": shell check: " & What);
   end Report;

   function Is_Word_Char (C : Character) return Boolean is
     (Is_Alphanumeric (C) or else C = '_');

   --  Returns Text with comments, string literals and character literals
   --  replaced by spaces (so that columns stay the same), and sets
   --  Justified when the comment contains "SHELL:".

   procedure Strip
     (Text      : String;
      Code      : out String;
      Justified : out Boolean)
   is
      I         : Natural := Text'First;
      Last_Code : Character := ' ';
      --  The last non-blank character of code seen, to tell a character
      --  literal from an attribute tick.
   begin
      Code := [others => ' '];
      Justified := False;
      while I <= Text'Last loop
         declare
            C : constant Character := Text (I);
         begin
            if C = '-' and then I < Text'Last and then Text (I + 1) = '-'
            then
               Justified :=
                 Ada.Strings.Fixed.Index (Text (I .. Text'Last), "SHELL:")
                   > 0;
               return;
            elsif C = '"' then
               --  A string literal; "" inside it is a quote.
               I := I + 1;
               while I <= Text'Last loop
                  if Text (I) = '"' then
                     exit when I = Text'Last or else Text (I + 1) /= '"';
                     I := I + 1;
                  end if;
                  I := I + 1;
               end loop;
               Last_Code := '"';
               I := I + 1;
            elsif C = '''
              and then not (Is_Word_Char (Last_Code)
                            or else Last_Code in ')' | ']')
              and then I + 2 <= Text'Last and then Text (I + 2) = '''
            then
               --  A character literal such as 'x' or '-'.
               Last_Code := ''';
               I := I + 3;
            else
               Code (Code'First + (I - Text'First)) := C;
               if C /= ' ' and then C /= ASCII.HT then
                  Last_Code := C;
               end if;
               I := I + 1;
            end if;
         end;
      end loop;
   end Strip;

   procedure Check_Line (File : String; Number : Positive; Text : String) is
      Code      : String (1 .. Text'Length);
      Justified : Boolean;
      Lower     : String (1 .. Text'Length);
   begin
      Strip (Text, Code, Justified);
      if Justified then
         return;
      end if;
      Lower := To_Lower (Code);

      --  Words.
      declare
         I : Positive := Lower'First;
      begin
         while I <= Lower'Last loop
            if Is_Letter (Lower (I))
              and then (I = Lower'First or else not Is_Word_Char (Lower (I - 1)))
            then
               declare
                  J : Positive := I;
               begin
                  while J < Lower'Last and then Is_Word_Char (Lower (J + 1))
                  loop
                     J := J + 1;
                  end loop;
                  declare
                     Word : constant String := Lower (I .. J);
                     Next : constant String :=
                       Ada.Strings.Fixed.Trim
                         (Lower (J + 1 .. Lower'Last), Ada.Strings.Left);
                  begin
                     if Word = "loop" then
                        Report (File, Number, I, "loop");
                     elsif Word = "for"
                       and then (Ada.Strings.Fixed.Head (Next, 4) = "all "
                                 or else Ada.Strings.Fixed.Head (Next, 5)
                                           = "some ")
                     then
                        Report (File, Number, I, "quantified expression");
                     elsif Word in "mod" | "rem" | "abs" then
                        Report (File, Number, I,
                                "arithmetic operator """ & Word & """");
                     elsif Word = "ada"
                       and then Ada.Strings.Fixed.Index
                                  (Lower (J + 1 .. Lower'Last), ".numerics")
                                  = J + 1
                     then
                        Report (File, Number, I, "use of Ada.Numerics");
                     end if;
                  end;
                  I := J + 1;
               end;
            elsif Is_Digit (Lower (I))
              and then (I = Lower'First or else not Is_Word_Char (Lower (I - 1)))
            then
               --  A numeric literal: digits, underscores, a point, an
               --  exponent, based notation.
               declare
                  J    : Positive := I;
                  Real : Boolean := False;
               begin
                  while J < Lower'Last
                    and then (Is_Word_Char (Lower (J + 1))
                              or else Lower (J + 1) = '#'
                              or else (Lower (J + 1) = '.'
                                       and then J + 2 <= Lower'Last
                                       and then Is_Hexadecimal_Digit
                                                  (Lower (J + 2)))
                              or else (Lower (J + 1) in '+' | '-'
                                       and then Lower (J) = 'e'))
                  loop
                     if Lower (J + 1) = '.' then
                        Real := True;
                     end if;
                     J := J + 1;
                  end loop;
                  if Real then
                     Report (File, Number, I,
                             "real literal " & Code (I .. J));
                  end if;
                  I := J + 1;
               end;
            else
               I := I + 1;
            end if;
         end loop;
      end;

      --  Operators.
      for I in Code'Range loop
         declare
            C    : constant Character := Code (I);
            Next : constant Character :=
              (if I < Code'Last then Code (I + 1) else ' ');
            Prev : constant Character :=
              (if I > Code'First then Code (I - 1) else ' ');
         begin
            if C = '+'
              or else (C = '-')
              or else (C = '*' and then Prev /= '*')
              or else (C = '/' and then Next /= '=')
            then
               if not (C in '+' | '-'
                       and then I > Code'First + 1
                       and then Is_Digit (Code (I - 2))
                       and then Prev = 'E')
               then
                  Report (File, Number, I,
                          "arithmetic operator """
                          & (if C = '*' and then Next = '*' then "**"
                             else [1 => C])
                          & """");
               end if;
            end if;
         end;
      end loop;
   end Check_Line;

   Validity_Pragma : constant String := "pragma Validity_Checks (""F"");";

   function Starts_With (Line, Word : String) return Boolean is
     (Ada.Strings.Fixed.Head (To_Lower (Line), Word'Length) = Word);

   function Starts_Unit (Line : String) return Boolean is
     (Starts_With (Line, "package ")
      or else Starts_With (Line, "private package ")
      or else Starts_With (Line, "generic")
      or else Starts_With (Line, "procedure ")
      or else Starts_With (Line, "function ")
      or else Starts_With (Line, "separate"));
   --  Whether Line (trimmed) starts the library unit of the file.

   procedure Check_Header (Path, Name : String) is
      F      : File_Type;
      Number : Natural := 0;
   begin
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         Number := Number + 1;
         declare
            Line : constant String :=
              Ada.Strings.Fixed.Trim (Get_Line (F), Ada.Strings.Both);
         begin
            if Ada.Strings.Fixed.Head (Line, Validity_Pragma'Length)
              = Validity_Pragma
            then
               Close (F);
               return;
            end if;
            exit when Starts_Unit (Line);
         end;
      end loop;
      Close (F);
      Report (Name, Positive'Max (Number, 1), 1,
              "no " & Validity_Pragma & " before the unit"
              & " (docs/DESIGN.md 9.3)");
   end Check_Header;

   procedure Check_No_Policy (Path, Name : String) is
      F      : File_Type;
      Number : Natural := 0;
   begin
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         Number := Number + 1;
         if Starts_With
              (Ada.Strings.Fixed.Trim (Get_Line (F), Ada.Strings.Both),
               "pragma assertion_policy")
         then
            Report (Name, Number, 1,
                    "pragma Assertion_Policy in a unit: the policies are"
                    & " contracts.adc and tests/contracts.adc"
                    & " (docs/DESIGN.md 9.2)");
         end if;
      end loop;
      Close (F);
   end Check_No_Policy;

   function Allowed_In_Spec (Unit : String) return Boolean is
     (Unit = "amv.spec" or else Starts_With (Unit, "amv.spec.")
      or else Unit = "amv.kernels"
      or else Unit = "interfaces" or else Starts_With (Unit, "interfaces.")
      or else Unit = "ada.numerics.big_numbers"
      or else Starts_With (Unit, "ada.numerics.big_numbers."));
   --  The units that a unit of AMV.Spec may depend on (src/amv-spec.ads):
   --  never the kernel that it specifies.

   procedure Check_Spec_Unit (Path, Name : String) is
      F        : File_Type;
      Number   : Natural := 0;
      In_Unit  : Boolean := False;
      Ghost    : Boolean := False;
      Unit_Row : Natural := 0;
   begin
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         Number := Number + 1;
         declare
            Line : constant String :=
              To_Lower (Ada.Strings.Fixed.Trim (Get_Line (F),
                                                Ada.Strings.Both));
            Dash : constant Natural := Ada.Strings.Fixed.Index (Line, "--");
            Code : constant String :=
              Ada.Strings.Fixed.Trim
                ((if Dash = 0 then Line else Line (Line'First .. Dash - 1)),
                 Ada.Strings.Both);
         begin
            if not In_Unit and then Starts_With (Code, "with ") then
               --  "with A, B;": every unit named.
               declare
                  First : Positive := Code'First + 5;
               begin
                  for I in Code'First + 5 .. Code'Last loop
                     if Code (I) = ',' or else Code (I) = ';' then
                        declare
                           Unit : constant String :=
                             Ada.Strings.Fixed.Trim
                               (Code (First .. I - 1), Ada.Strings.Both);
                        begin
                           if not Allowed_In_Spec (Unit) then
                              Report (Name, Number, 1,
                                      "a specification depends on " & Unit
                                      & " (src/amv-spec.ads)");
                           end if;
                        end;
                        First := I + 1;
                     end if;
                  end loop;
               end;
            elsif not In_Unit and then Starts_Unit (Code) then
               In_Unit := True;
               Unit_Row := Number;
            end if;
            if In_Unit and then Unit_Row > 0 then
               --  The declaration of the unit, up to its "is".
               if Ada.Strings.Fixed.Index (" " & Code & " ", " ghost") > 0
               then
                  Ghost := True;
               end if;
               if Code = "is" or else Ada.Strings.Fixed.Tail (Code, 3) = " is"
               then
                  Unit_Row := 0;
               end if;
            end if;
         end;
      end loop;
      Close (F);
      if Ada.Strings.Fixed.Tail (Name, 4) = ".ads" and then not Ghost then
         Report (Name, 1, 1,
                 "a specification that is not ghost (src/amv-spec.ads)");
      end if;
   end Check_Spec_Unit;

   procedure Check_File (Path, Name : String) is
      F      : File_Type;
      Number : Natural := 0;
   begin
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         Number := Number + 1;
         Check_Line (Name, Number, Get_Line (F));
      end loop;
      Close (F);
   end Check_File;

   function Read_Legacy (Path : String) return Name_Sets.Set is
      F      : File_Type;
      Result : Name_Sets.Set;
   begin
      Open (F, In_File, Path);
      while not End_Of_File (F) loop
         declare
            Line  : constant String := Get_Line (F);
            Hash  : constant Natural := Ada.Strings.Fixed.Index (Line, "#");
            Entry_Text : constant String :=
              Ada.Strings.Fixed.Trim
                ((if Hash = 0 then Line else Line (Line'First .. Hash - 1)),
                 Ada.Strings.Both);
         begin
            if Entry_Text /= "" then
               Result.Include (Entry_Text);
            end if;
         end;
      end loop;
      Close (F);
      return Result;
   end Read_Legacy;

begin
   if Ada.Command_Line.Argument_Count /= 2 then
      Put_Line (Standard_Error, "usage: amv_shell_check SRC_DIR LEGACY_LIST");
      Ada.Command_Line.Set_Exit_Status (2);
      return;
   end if;
   declare
      Src    : constant String := Ada.Command_Line.Argument (1);
      Legacy : constant Name_Sets.Set :=
        Read_Legacy (Ada.Command_Line.Argument (2));
      Search : Ada.Directories.Search_Type;
      Item   : Ada.Directories.Directory_Entry_Type;
      Names  : Name_Sets.Set;
      Specs  : Name_Sets.Set;
      Seen   : Name_Sets.Set;
   begin
      Ada.Directories.Start_Search
        (Search, Src, "amv-*.adb",
         [Ada.Directories.Ordinary_File => True, others => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         Names.Include (Ada.Directories.Simple_Name (Item));
      end loop;
      Ada.Directories.End_Search (Search);
      Ada.Directories.Start_Search
        (Search, Src, "amv-*.ads",
         [Ada.Directories.Ordinary_File => True, others => False]);
      while Ada.Directories.More_Entries (Search) loop
         Ada.Directories.Get_Next_Entry (Search, Item);
         Specs.Include (Ada.Directories.Simple_Name (Item));
      end loop;
      Ada.Directories.End_Search (Search);

      for Name of Names loop
         Check_No_Policy (Ada.Directories.Compose (Src, Name), Name);
         if Ada.Strings.Fixed.Head (Name, 11) = "amv-kernels" then
            null;
         elsif Ada.Strings.Fixed.Head (Name, 8) = "amv-spec" then
            Check_Header (Ada.Directories.Compose (Src, Name), Name);
            Check_Spec_Unit (Ada.Directories.Compose (Src, Name), Name);
         else
            Check_Header (Ada.Directories.Compose (Src, Name), Name);
            if Legacy.Contains (Name) then
               Seen.Include (Name);
            else
               Check_File (Ada.Directories.Compose (Src, Name), Name);
            end if;
         end if;
      end loop;

      for Name of Specs loop
         Check_No_Policy (Ada.Directories.Compose (Src, Name), Name);
         if Ada.Strings.Fixed.Head (Name, 11) /= "amv-kernels" then
            Check_Header (Ada.Directories.Compose (Src, Name), Name);
         end if;
         if Ada.Strings.Fixed.Head (Name, 8) = "amv-spec" then
            Check_Spec_Unit (Ada.Directories.Compose (Src, Name), Name);
         end if;
      end loop;

      for Name of Legacy loop
         if not Seen.Contains (Name) then
            Put_Line ("note: " & Name
                      & " is in the legacy list but not in " & Src
                      & "; remove it from the list");
         end if;
      end loop;
   end;

   if Findings > 0 then
      Put_Line (Findings'Image & " finding(s); move the logic into a kernel"
                & " or justify the line with ""--  SHELL: reason"" (for a"
                & " missing pragma, add it after pragma SPARK_Mode (Off))");
      Ada.Command_Line.Set_Exit_Status (1);
   end if;
end AMV_Shell_Check;
