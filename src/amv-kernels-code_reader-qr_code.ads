--  QR Code (Model 2): from the modules of a symbol to its text, for
--  AMV.Kernels.Code_Reader. Internal: no entry points of its own (no
--  export); public so that the tests can call it.
--
--  The symbol. A square of 17 + 4 * Version modules a side, for the
--  versions 1 .. 40 (21 .. 177 modules), row 0 at the top. Three corners
--  hold a finder pattern (7 x 7 modules, with a light row and column
--  towards the inside); row 6 and column 6 alternate between them (the
--  timing patterns); from version 2 on, 5 x 5 alignment patterns lie
--  where the rows and columns of Centres cross, except in the three
--  corners with the finder patterns. Next to the finder patterns are the
--  two copies of the format information (15 bits: the error correction
--  level and the mask, with 10 check bits) and, from version 7 on, the
--  two copies of the version information (18 bits, 12 of them check
--  bits). All other modules hold the codewords: eight modules each, the
--  most significant bit first, along pairs of columns from the right to
--  the left, upwards and downwards in turn, the right module of a row
--  before the left one. One of eight masks, named by the format
--  information, inverts some of these modules.
--
--  The codewords. They are dealt out to the blocks of the version and
--  level (Blocks) in turn: first those of the message, then the check
--  codewords of a Reed-Solomon code over GF(256) (field polynomial
--  16#11D#, first root 0), every block corrected by itself: as many
--  wrong codewords as half its check codewords, and fewer in the three
--  smallest symbols (Correctable).
--
--  The message (To_Text). A stream of bits in segments: four bits name
--  the mode, a count follows (its width depends on the version), then
--  the characters: digits three to ten bits (numeric), two characters
--  of a set of 45 to eleven bits (alphanumeric), bytes, or the two bytes
--  of a Shift JIS character to thirteen bits (Kanji). The text reported
--  is the bytes as they are encoded (0 .. 255). As for Code 128, FNC1
--  in the first position adds nothing; FNC1 in the second position adds
--  its application indicator (two digits or a letter) before the
--  message. After either, "%" in an alphanumeric segment is the
--  character GS (29) and "%%" the character "%". Extended channel
--  interpretations and structured append are passed over: the
--  characters after them are reported as they are encoded.
--
--  Not read: Micro QR Code, QR Code Model 1, and the modes that
--  ISO/IEC 18004 does not define.
--
--  Proved (docs/PROOF.md): no run-time error for any grid. Not proved
--  (tested): that the text is that of the symbol.

pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.Code_Reader.Reed_Solomon;

package AMV.Kernels.Code_Reader.QR_Code
  with SPARK_Mode, Preelaborate
is

   package RS renames AMV.Kernels.Code_Reader.Reed_Solomon;

   Max_Version : constant := 40;

   subtype Version_Number is Positive range 1 .. Max_Version;

   Max_Side : constant := 17 + 4 * Max_Version;
   --  The modules along a side, at most (177).

   subtype Side_Length is Positive range 21 .. Max_Side;

   type Module_Index is range 0 .. Max_Side - 1;

   type Module_Grid is array (Module_Index, Module_Index) of Boolean;
   --  (Row, Column); True: dark.

   function Side (Version : Version_Number) return Side_Length is
     (17 + 4 * Version);
   --  The modules along a side of a symbol.

   function Version_Of (Modules : Integer) return Natural is
     (if Modules in Side_Length and then (Modules - 17) mod 4 = 0
      then (Modules - 17) / 4
      else 0)
   with Post => Version_Of'Result <= Max_Version
                and then (if Version_Of'Result > 0
                          then Side (Version_Of'Result) = Modules);
   --  The version of the symbols with Modules modules along a side; 0 if
   --  there is none.

   ---------------------------------------------------------------------
   --  The blocks
   ---------------------------------------------------------------------

   type Level is (L, M, Q, H);
   --  The error correction level: about 7, 15, 25 and 30 % of the
   --  codewords can be corrected.

   type Block_Info is record
      Check    : Positive range 7 .. 30;
      --  The check codewords of every block.
      Blocks_1 : Positive range 1 .. 59;
      Data_1   : Positive range 9 .. 122;
      --  The blocks of the first group and the codewords of the message
      --  in each of them.
      Blocks_2 : Natural range 0 .. 67;
      --  The blocks of the second group, each with one codeword of the
      --  message more.
   end record;

   type Block_Table is array (Version_Number, Level) of Block_Info;

   Blocks : constant Block_Table :=
     [[(7, 1, 19, 0), (10, 1, 16, 0), (13, 1, 13, 0), (17, 1, 9, 0)],
      [(10, 1, 34, 0), (16, 1, 28, 0), (22, 1, 22, 0), (28, 1, 16, 0)],
      [(15, 1, 55, 0), (26, 1, 44, 0), (18, 2, 17, 0), (22, 2, 13, 0)],
      [(20, 1, 80, 0), (18, 2, 32, 0), (26, 2, 24, 0), (16, 4, 9, 0)],
      [(26, 1, 108, 0), (24, 2, 43, 0), (18, 2, 15, 2), (22, 2, 11, 2)],
      [(18, 2, 68, 0), (16, 4, 27, 0), (24, 4, 19, 0), (28, 4, 15, 0)],
      [(20, 2, 78, 0), (18, 4, 31, 0), (18, 2, 14, 4), (26, 4, 13, 1)],
      [(24, 2, 97, 0), (22, 2, 38, 2), (22, 4, 18, 2), (26, 4, 14, 2)],
      [(30, 2, 116, 0), (22, 3, 36, 2), (20, 4, 16, 4), (24, 4, 12, 4)],
      [(18, 2, 68, 2), (26, 4, 43, 1), (24, 6, 19, 2), (28, 6, 15, 2)],
      [(20, 4, 81, 0), (30, 1, 50, 4), (28, 4, 22, 4), (24, 3, 12, 8)],
      [(24, 2, 92, 2), (22, 6, 36, 2), (26, 4, 20, 6), (28, 7, 14, 4)],
      [(26, 4, 107, 0), (22, 8, 37, 1), (24, 8, 20, 4), (22, 12, 11, 4)],
      [(30, 3, 115, 1), (24, 4, 40, 5), (20, 11, 16, 5), (24, 11, 12, 5)],
      [(22, 5, 87, 1), (24, 5, 41, 5), (30, 5, 24, 7), (24, 11, 12, 7)],
      [(24, 5, 98, 1), (28, 7, 45, 3), (24, 15, 19, 2), (30, 3, 15, 13)],
      [(28, 1, 107, 5), (28, 10, 46, 1), (28, 1, 22, 15), (28, 2, 14, 17)],
      [(30, 5, 120, 1), (26, 9, 43, 4), (28, 17, 22, 1), (28, 2, 14, 19)],
      [(28, 3, 113, 4), (26, 3, 44, 11), (26, 17, 21, 4), (26, 9, 13, 16)],
      [(28, 3, 107, 5), (26, 3, 41, 13), (30, 15, 24, 5), (28, 15, 15, 10)],
      [(28, 4, 116, 4), (26, 17, 42, 0), (28, 17, 22, 6), (30, 19, 16, 6)],
      [(28, 2, 111, 7), (28, 17, 46, 0), (30, 7, 24, 16), (24, 34, 13, 0)],
      [(30, 4, 121, 5), (28, 4, 47, 14), (30, 11, 24, 14), (30, 16, 15, 14)],
      [(30, 6, 117, 4), (28, 6, 45, 14), (30, 11, 24, 16), (30, 30, 16, 2)],
      [(26, 8, 106, 4), (28, 8, 47, 13), (30, 7, 24, 22), (30, 22, 15, 13)],
      [(28, 10, 114, 2), (28, 19, 46, 4), (28, 28, 22, 6), (30, 33, 16, 4)],
      [(30, 8, 122, 4), (28, 22, 45, 3), (30, 8, 23, 26), (30, 12, 15, 28)],
      [(30, 3, 117, 10), (28, 3, 45, 23), (30, 4, 24, 31), (30, 11, 15, 31)],
      [(30, 7, 116, 7), (28, 21, 45, 7), (30, 1, 23, 37), (30, 19, 15, 26)],
      [(30, 5, 115, 10), (28, 19, 47, 10), (30, 15, 24, 25), (30, 23, 15, 25)],
      [(30, 13, 115, 3), (28, 2, 46, 29), (30, 42, 24, 1), (30, 23, 15, 28)],
      [(30, 17, 115, 0), (28, 10, 46, 23), (30, 10, 24, 35), (30, 19, 15, 35)],
      [(30, 17, 115, 1), (28, 14, 46, 21), (30, 29, 24, 19), (30, 11, 15, 46)],
      [(30, 13, 115, 6), (28, 14, 46, 23), (30, 44, 24, 7), (30, 59, 16, 1)],
      [(30, 12, 121, 7), (28, 12, 47, 26), (30, 39, 24, 14), (30, 22, 15, 41)],
      [(30, 6, 121, 14), (28, 6, 47, 34), (30, 46, 24, 10), (30, 2, 15, 64)],
      [(30, 17, 122, 4), (28, 29, 46, 14), (30, 49, 24, 10), (30, 24, 15, 46)],
      [(30, 4, 122, 18), (28, 13, 46, 32), (30, 48, 24, 14), (30, 42, 15, 32)],
      [(30, 20, 117, 4), (28, 40, 47, 7), (30, 43, 24, 22), (30, 10, 15, 67)],
      [(30, 19, 118, 6), (28, 18, 47, 31),
       (30, 34, 24, 34), (30, 20, 15, 61)]];
   --  ISO/IEC 18004, the table of the error correction characteristics.
   --  Every block of a version and level has the same number of check
   --  codewords.

   Max_Codewords : constant := 3706;
   Max_Data      : constant := 2956;
   --  The codewords of the largest version: all of them, and those of
   --  the message at the level L.

   subtype Codeword_Total is Positive range 26 .. Max_Codewords;

   type Codeword_Totals is array (Version_Number) of Codeword_Total;

   Codewords : constant Codeword_Totals :=
     [26, 44, 70, 100, 134, 172, 196, 242, 292, 346, 404, 466, 532, 581, 655,
      733, 815, 901, 991, 1085, 1156, 1258, 1364, 1474, 1588, 1706, 1828, 1921,
      2051, 2185, 2323, 2465, 2611, 2761, 2876, 3034, 3196, 3362, 3532, 3706];
   --  All the codewords of a version, those of the message and the
   --  check codewords: the modules that hold codewords, eight to a
   --  codeword (0, 3, 4 or 7 modules are left over). The tests check
   --  that the blocks of every version and level have as many.

   function Correctable
     (Version : Version_Number;
      Grade   : Level) return Positive
   is
     (if Version = 1 and then Grade = L then 2
      elsif (Version = 1 and then Grade = M)
        or else (Version = 2 and then Grade = L)
      then 4
      else Blocks (Version, Grade).Check / 2)
   with Post => Correctable'Result <= 15;
   --  The wrong codewords of a block that are corrected: half its check
   --  codewords. ISO/IEC 18004 keeps some check codewords of the
   --  smallest symbols for telling that a block cannot be corrected, so
   --  that a block with more wrong codewords is not taken for another
   --  one: three of the seven of the version 1 at the level L, and two
   --  of the ten of the version 1 at the level M and of the version 2 at
   --  the level L. (One of the versions 1-Q, 1-H and 3-L, whose number
   --  of check codewords is odd: half of it is the same.) A block of
   --  these three symbols with more wrong codewords than that is not
   --  corrected, although the code could.

   ---------------------------------------------------------------------
   --  The patterns
   ---------------------------------------------------------------------

   Max_Centres : constant := 7;

   subtype Centre_Value is Natural range 0 .. Max_Side - 7;

   type Centre_List is array (1 .. Max_Centres) of Centre_Value;

   type Centre_Table is array (Version_Number) of Centre_List;

   Centres : constant Centre_Table :=
     [[0, 0, 0, 0, 0, 0, 0],
      [6, 18, 0, 0, 0, 0, 0],
      [6, 22, 0, 0, 0, 0, 0],
      [6, 26, 0, 0, 0, 0, 0],
      [6, 30, 0, 0, 0, 0, 0],
      [6, 34, 0, 0, 0, 0, 0],
      [6, 22, 38, 0, 0, 0, 0],
      [6, 24, 42, 0, 0, 0, 0],
      [6, 26, 46, 0, 0, 0, 0],
      [6, 28, 50, 0, 0, 0, 0],
      [6, 30, 54, 0, 0, 0, 0],
      [6, 32, 58, 0, 0, 0, 0],
      [6, 34, 62, 0, 0, 0, 0],
      [6, 26, 46, 66, 0, 0, 0],
      [6, 26, 48, 70, 0, 0, 0],
      [6, 26, 50, 74, 0, 0, 0],
      [6, 30, 54, 78, 0, 0, 0],
      [6, 30, 56, 82, 0, 0, 0],
      [6, 30, 58, 86, 0, 0, 0],
      [6, 34, 62, 90, 0, 0, 0],
      [6, 28, 50, 72, 94, 0, 0],
      [6, 26, 50, 74, 98, 0, 0],
      [6, 30, 54, 78, 102, 0, 0],
      [6, 28, 54, 80, 106, 0, 0],
      [6, 32, 58, 84, 110, 0, 0],
      [6, 30, 58, 86, 114, 0, 0],
      [6, 34, 62, 90, 118, 0, 0],
      [6, 26, 50, 74, 98, 122, 0],
      [6, 30, 54, 78, 102, 126, 0],
      [6, 26, 52, 78, 104, 130, 0],
      [6, 30, 56, 82, 108, 134, 0],
      [6, 34, 60, 86, 112, 138, 0],
      [6, 30, 58, 86, 114, 142, 0],
      [6, 34, 62, 90, 118, 146, 0],
      [6, 30, 54, 78, 102, 126, 150],
      [6, 24, 50, 76, 102, 128, 154],
      [6, 28, 54, 80, 106, 132, 158],
      [6, 32, 58, 84, 110, 136, 162],
      [6, 26, 54, 82, 110, 138, 166],
      [6, 30, 58, 86, 114, 142, 170]];
   --  The rows, and the columns, of the middles of the alignment
   --  patterns of a version, in rising order; 0: none.

   procedure Mark_Functions
     (Version : Version_Number;
      Map     : out Module_Grid);
   --  Map (R, C): the module of the symbol holds no codeword. It is of a
   --  finder pattern with the light modules around it, of a timing or an
   --  alignment pattern, of the format or the version information, or
   --  the module that is always dark. False outside the symbol.

   ---------------------------------------------------------------------
   --  The format and the version information
   ---------------------------------------------------------------------

   type Info_Bits is mod 2 ** 18;
   --  The bits of the format information (15) or of the version
   --  information (18).

   subtype Mask_Pattern is Natural range 0 .. 7;

   type Format_Table is array (0 .. 31) of Info_Bits;

   Format_Words : constant Format_Table :=
     [16#5412#, 16#5125#, 16#5E7C#, 16#5B4B#, 16#45F9#, 16#40CE#, 16#4F97#,
      16#4AA0#, 16#77C4#, 16#72F3#, 16#7DAA#, 16#789D#, 16#662F#, 16#6318#,
      16#6C41#, 16#6976#, 16#1689#, 16#13BE#, 16#1CE7#, 16#19D0#, 16#0762#,
      16#0255#, 16#0D0C#, 16#083B#, 16#355F#, 16#3068#, 16#3F31#, 16#3A06#,
      16#24B4#, 16#2183#, 16#2EDA#, 16#2BED#];
   --  Format_Words (I): the format information of the five bits I as
   --  it is in a symbol. The upper two bits of I are the level (1: L,
   --  0: M, 3: Q, 2: H), the lower three the mask; ten check bits
   --  follow (the remainder of a division by 16#537#), and the fifteen
   --  bits are inverted where 16#5412# has a one. Two of the words
   --  differ in seven bits or more.

   type Version_Table is array (7 .. Max_Version) of Info_Bits;

   Version_Words : constant Version_Table :=
     [16#07C94#, 16#085BC#, 16#09A99#, 16#0A4D3#, 16#0BBF6#, 16#0C762#,
      16#0D847#, 16#0E60D#, 16#0F928#, 16#10B78#, 16#1145D#, 16#12A17#,
      16#13532#, 16#149A6#, 16#15683#, 16#168C9#, 16#177EC#, 16#18EC4#,
      16#191E1#, 16#1AFAB#, 16#1B08E#, 16#1CC1A#, 16#1D33F#, 16#1ED75#,
      16#1F250#, 16#209D5#, 16#216F0#, 16#228BA#, 16#2379F#, 16#24B0B#,
      16#2542E#, 16#26A64#, 16#27541#, 16#28C69#];
   --  Version_Words (V): the version information of the version V: its
   --  six bits and twelve check bits (the remainder of a division by
   --  16#1F25#). Two of the words differ in eight bits or more.

   function Masked
     (Mask        : Mask_Pattern;
      Row, Column : Module_Index) return Boolean;
   --  The mask Mask inverts the module (if it holds a codeword).

   procedure Read_Format
     (Grid       : Module_Grid;
      Version    : Version_Number;
      Mirror     : Boolean;
      Level_Read : out Level;
      Mask       : out Mask_Pattern;
      OK         : out Boolean);
   --  The level and the mask of the symbol: those of the word of
   --  Format_Words that is nearest to either copy of the format
   --  information. Not OK: both copies differ from every word in more
   --  than three bits.

   ---------------------------------------------------------------------
   --  Decoding
   ---------------------------------------------------------------------

   subtype Codeword_Count is Natural range 0 .. Max_Codewords;
   subtype Codeword_Index is Positive range 1 .. Max_Codewords;

   type Codeword_Array is array (Codeword_Index range <>) of RS.Element;

   type Text_Buffer is array (Positive range <>) of Character;

   Max_Text_Length : constant := 7089;
   --  No symbol has a longer text: the digits of version 40 at the
   --  level L.

   procedure To_Text
     (Data    : Codeword_Array;
      Version : Version_Number;
      Text    : out Text_Buffer;
      Length  : out Natural;
      OK      : out Boolean)
   with
     Pre  => Data'First = 1 and then Data'Length >= 1
             and then Text'First = 1 and then Text'Last >= 0,
     Post => Length <= Text'Length;
   --  The message of the data codewords of a symbol of the version
   --  Version (the widths of the counts depend on it). Not OK: a mode
   --  that is not defined, a value that stands for no character, a
   --  segment that the codewords do not hold all of, or a text longer
   --  than Text.

   procedure Decode
     (Grid      : Module_Grid;
      Version   : Version_Number;
      Mirror    : Boolean;
      Field     : RS.Field;
      Text      : out Text_Buffer;
      Length    : out Natural;
      Corrected : out Natural;
      Success   : out Boolean)
   with
     Pre  => Text'First = 1 and then Text'Last >= 0,
     Post => Length <= Text'Length
             and then Corrected <= Max_Codewords
             and then (if not Success then Length = 0);
   --  Reads the format information and the codewords of the symbol of
   --  the version Version whose modules are Grid, corrects them and
   --  gives the message. Mirror: the symbol is seen from behind, and
   --  Grid (C, R) is its module in the row R and the column C. Field:
   --  the tables of RS.QR_Code_Polynomial. Corrected: the codewords
   --  changed. Not Success: no format information; from version 7 on,
   --  both copies of the version information differ from that of
   --  Version in more than three bits; a block with more wrong
   --  codewords than Correctable; or To_Text not OK.

end AMV.Kernels.Code_Reader.QR_Code;
