--  A QR Code (Model 2) encoder for the tests: from a text to the bits of
--  a segment, from the bits to the codewords, and from the codewords to
--  the modules of a symbol.
--
--  It shares only the table of the blocks with the kernel that reads the
--  symbols (AMV.Kernels.Code_Reader.QR_Code.Blocks, which the tests
--  check by itself). Its arithmetic in GF(256) is shift and xor without
--  tables, its check codewords are the remainder of a division by the
--  generator polynomial, the words of the format and of the version
--  information are remainders too, the alignment patterns are where a
--  formula puts them, and the patterns are painted one after another,
--  each marking its modules. The masks are written in other terms than
--  the kernel's.
--
--  AMV_Test_Data_Matrix.Draw paints the modules into an image (the type
--  of the modules is the same).

with AMV.Kernels.Code_Reader.QR_Code;
with AMV_Test_Data_Matrix;

package AMV_Test_QR_Code is

   package QR renames AMV.Kernels.Code_Reader.QR_Code;

   subtype Byte is AMV_Test_Data_Matrix.Byte;
   subtype Byte_List is AMV_Test_Data_Matrix.Byte_List;
   subtype Module_Matrix is AMV_Test_Data_Matrix.Module_Matrix;
   --  (Row, Column) from 0; True: dark.

   type Bit_List is array (Positive range <>) of Boolean;
   --  True: a one.

   type Number_List is array (Positive range <>) of Natural;

   ---------------------------------------------------------------------
   --  From a text to bits
   ---------------------------------------------------------------------

   function Bits (Value : Natural; Count : Natural) return Bit_List;
   --  The lowest Count bits of Value, the most significant first.

   type Mode is (Numeric, Alphanumeric, Bytes, Kanji);

   function Count_Bits
     (Kind    : Mode;
      Version : QR.Version_Number) return Positive;
   --  The bits of the count of a segment.

   function Segment_Bits
     (Kind       : Mode;
      Characters : Natural;
      Version    : QR.Version_Number) return Positive;
   --  The bits of a segment with Characters characters.

   function Segment
     (Kind    : Mode;
      Text    : String;
      Version : QR.Version_Number) return Bit_List;
   --  The mode, the count and the characters of Text. Kanji: two bytes
   --  of Text are a character, as Shift JIS has it. Constraint_Error: a
   --  character that the mode does not have, or more characters than
   --  the count can say.

   function ECI (Designator : Natural) return Bit_List;
   --  The mode and the designator of an extended channel
   --  interpretation, in one, two or three codewords.

   function FNC1_First return Bit_List;
   function FNC1_Second (Indicator : Byte) return Bit_List;
   --  The modes of FNC1 in the first and in the second position, the
   --  latter with its application indicator.

   function Structured_Append
     (Index, Last : Natural;
      Parity      : Byte) return Bit_List;
   --  The mode, the place of the symbol among those of a message (from
   --  0), the last such place, and the parity of the message.

   ---------------------------------------------------------------------
   --  From bits to codewords
   ---------------------------------------------------------------------

   function Block_Count
     (Version : QR.Version_Number;
      Level   : QR.Level) return Positive;

   function Data_Count
     (Version : QR.Version_Number;
      Level   : QR.Level) return Positive;
   --  The blocks, and the codewords of the message, from the table of
   --  the blocks.

   function Total_Count (Version : QR.Version_Number) return Positive;
   --  The codewords of a symbol: an eighth of its modules outside the
   --  patterns (Function_Modules).

   function Smallest_Version
     (Kind  : Mode;
      Text  : String;
      Level : QR.Level) return QR.Version_Number;
   --  The smallest version that holds Segment (Kind, Text, Version) at
   --  the level. Constraint_Error: none.

   function Data_Codewords
     (Message : Bit_List;
      Version : QR.Version_Number;
      Level   : QR.Level) return Byte_List;
   --  The bits Message, the terminator (four zero bits, or as many as
   --  the symbol has room for), zero bits up to a codeword, and the pad
   --  codewords 236 and 17 in turn. Constraint_Error: more bits than
   --  the symbol holds.

   function Blocks_Of_Places
     (Version : QR.Version_Number;
      Level   : QR.Level) return Number_List;
   --  The block (from 1) of the codeword at every place of Stream.

   function Stream
     (Data    : Byte_List;
      Version : QR.Version_Number;
      Level   : QR.Level) return Byte_List;
   --  Data (as many codewords as the version has at the level) in its
   --  blocks, each with its check codewords, in the order of their
   --  places in the symbol.

   ---------------------------------------------------------------------
   --  From codewords to a symbol
   ---------------------------------------------------------------------

   function Alignment_Centres
     (Version : QR.Version_Number) return Number_List;
   --  The rows, and columns, of the middles of the alignment patterns.

   function Format_Word
     (Level : QR.Level;
      Mask  : QR.Mask_Pattern) return Natural;
   function Version_Word (Version : QR.Version_Number) return Natural;
   --  The fifteen bits of the format information (with its mask) and
   --  the eighteen bits of the version information.

   subtype Copy_Number is Positive range 1 .. 2;

   procedure Put_Format
     (Symbol : in out Module_Matrix;
      Copy   : Copy_Number;
      Word   : Natural);
   --  Writes the fifteen bits Word where a copy of the format
   --  information is: 1, around the upper left finder pattern; 2, half
   --  beside the upper right and half beside the lower left one.

   procedure Put_Version
     (Symbol : in out Module_Matrix;
      Copy   : Copy_Number;
      Word   : Natural);
   --  Writes the eighteen bits Word where a copy of the version
   --  information is: 1, beside the upper right finder pattern; 2,
   --  above the lower left one. For the symbols of the versions from 7.

   function Masked
     (Mask        : QR.Mask_Pattern;
      Row, Column : Natural) return Boolean;
   --  The mask turns the module over.

   function Function_Modules
     (Version : QR.Version_Number) return Module_Matrix;
   --  True: a module of a pattern, of the light modules around a finder
   --  pattern, or of the format or version information.

   function Modules
     (Codewords : Byte_List;
      Version   : QR.Version_Number;
      Level     : QR.Level;
      Mask      : QR.Mask_Pattern) return Module_Matrix;
   --  The symbol with the codewords Codewords (all of them: Stream).

   function Symbol
     (Message : Bit_List;
      Version : QR.Version_Number;
      Level   : QR.Level;
      Mask    : QR.Mask_Pattern := 0) return Module_Matrix
   is (Modules
         (Stream (Data_Codewords (Message, Version, Level), Version, Level),
          Version, Level, Mask));

   function Grid (Symbol : Module_Matrix) return QR.Module_Grid;
   --  The modules as the kernel takes them.

   function Transposed (Symbol : Module_Matrix) return Module_Matrix;
   --  The symbol as it is seen from behind: rows for columns.

end AMV_Test_QR_Code;
