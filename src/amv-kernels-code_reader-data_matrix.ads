--  Data Matrix (ECC 200): from the modules of a symbol to its text, for
--  AMV.Kernels.Code_Reader. Internal: no entry points of its own (no
--  export); public so that the tests can call it.
--
--  The symbol. A grid of Rows by Columns modules, row 0 at the top. The
--  left column and the bottom row are dark (the "L"); the top row and
--  the right column alternate. There are 24 square sizes from 10 x 10 to
--  144 x 144 and 6 rectangular ones, and 18 more rectangular ones in the
--  rectangular extension (DMRE, ISO/IEC 21471), from 8 x 48 to 26 x 64.
--  The larger sizes are divided into regions, each with such a border of
--  its own; without the borders the regions together are the mapping
--  matrix, which holds the codewords: eight modules each, in the shape
--  and the order that the symbology defines (Place), the most
--  significant bit first.
--
--  The codewords. The first Data of them carry the message, the others
--  are the check codewords of a Reed-Solomon code over GF(256) (field
--  polynomial 16#12D#, first root 1). In the larger sizes the codewords
--  are dealt out to several blocks in turn, each corrected by itself.
--
--  The message (To_Text). Codewords in the ASCII encodation give one
--  character (1 .. 128), two digits (130 .. 229) or a command: the end
--  of the message (129), a latch to the C40, Text, X12, EDIFACT or
--  Base 256 encodation, FNC1, the upper shift, the two macros. The text
--  reported is the characters as they are encoded (0 .. 255). As for
--  Code 128, FNC1 as the first codeword adds nothing and FNC1 elsewhere
--  is the character GS (29). A macro codeword adds the characters that
--  it stands for ("[)>" RS "05" GS or "[)>" RS "06" GS before the
--  message, RS EOT after it). Extended channel interpretations,
--  structured append and reader programming are passed over: the
--  characters after them are reported as they are encoded.
--
--  Proved (docs/PROOF.md): no run-time error for any grid. Not proved
--  (tested): that the text is that of the symbol.

pragma Validity_Checks ("F");
with AMV.Kernels.Code_Reader.Reed_Solomon;

package AMV.Kernels.Code_Reader.Data_Matrix
  with SPARK_Mode, Preelaborate
is

   package RS renames AMV.Kernels.Code_Reader.Reed_Solomon;

   Max_Side : constant := 144;
   --  The modules along a side, at most.

   type Module_Index is range 0 .. Max_Side - 1;

   type Module_Grid is array (Module_Index, Module_Index) of Boolean;
   --  (Row, Column); True: dark.

   ---------------------------------------------------------------------
   --  The sizes
   ---------------------------------------------------------------------

   Num_Sizes : constant := 48;

   subtype Size_Index is Positive range 1 .. Num_Sizes;
   --  1 .. 24: the square sizes; 25 .. 30: the rectangular ones;
   --  31 .. 48: those of the rectangular extension.

   Max_Codewords : constant := 2178;
   Max_Data      : constant := 1558;
   --  The codewords of the largest size: all of them, and those of the
   --  message.

   type Size_Info is record
      Rows, Columns                : Positive range 8 .. Max_Side;
      --  The modules of the symbol, with the borders.
      Region_Rows, Region_Columns  : Positive range 6 .. 24;
      --  The modules of one region, without its border.
      Regions_Down, Regions_Across : Positive range 1 .. 6;
      Data                         : Positive range 3 .. Max_Data;
      Check                        : Positive range 5 .. 620;
      --  The codewords of the message and the check codewords.
      Blocks                       : Positive range 1 .. 10;
   end record;

   type Size_Table is array (Size_Index) of Size_Info;

   Sizes : constant Size_Table :=
     [(10, 10, 8, 8, 1, 1, 3, 5, 1),
      (12, 12, 10, 10, 1, 1, 5, 7, 1),
      (14, 14, 12, 12, 1, 1, 8, 10, 1),
      (16, 16, 14, 14, 1, 1, 12, 12, 1),
      (18, 18, 16, 16, 1, 1, 18, 14, 1),
      (20, 20, 18, 18, 1, 1, 22, 18, 1),
      (22, 22, 20, 20, 1, 1, 30, 20, 1),
      (24, 24, 22, 22, 1, 1, 36, 24, 1),
      (26, 26, 24, 24, 1, 1, 44, 28, 1),
      (32, 32, 14, 14, 2, 2, 62, 36, 1),
      (36, 36, 16, 16, 2, 2, 86, 42, 1),
      (40, 40, 18, 18, 2, 2, 114, 48, 1),
      (44, 44, 20, 20, 2, 2, 144, 56, 1),
      (48, 48, 22, 22, 2, 2, 174, 68, 1),
      (52, 52, 24, 24, 2, 2, 204, 84, 2),
      (64, 64, 14, 14, 4, 4, 280, 112, 2),
      (72, 72, 16, 16, 4, 4, 368, 144, 4),
      (80, 80, 18, 18, 4, 4, 456, 192, 4),
      (88, 88, 20, 20, 4, 4, 576, 224, 4),
      (96, 96, 22, 22, 4, 4, 696, 272, 4),
      (104, 104, 24, 24, 4, 4, 816, 336, 6),
      (120, 120, 18, 18, 6, 6, 1050, 408, 6),
      (132, 132, 20, 20, 6, 6, 1304, 496, 8),
      (144, 144, 22, 22, 6, 6, 1558, 620, 10),
      (8, 18, 6, 16, 1, 1, 5, 7, 1),
      (8, 32, 6, 14, 1, 2, 10, 11, 1),
      (12, 26, 10, 24, 1, 1, 16, 14, 1),
      (12, 36, 10, 16, 1, 2, 22, 18, 1),
      (16, 36, 14, 16, 1, 2, 32, 24, 1),
      (16, 48, 14, 22, 1, 2, 49, 28, 1),
      (8, 48, 6, 22, 1, 2, 18, 15, 1),
      (8, 64, 6, 14, 1, 4, 24, 18, 1),
      (8, 80, 6, 18, 1, 4, 32, 22, 1),
      (8, 96, 6, 22, 1, 4, 38, 28, 1),
      (8, 120, 6, 18, 1, 6, 49, 32, 1),
      (8, 144, 6, 22, 1, 6, 63, 36, 1),
      (12, 64, 10, 14, 1, 4, 43, 27, 1),
      (12, 88, 10, 20, 1, 4, 64, 36, 1),
      (16, 64, 14, 14, 1, 4, 62, 36, 1),
      (20, 36, 18, 16, 1, 2, 44, 28, 1),
      (20, 44, 18, 20, 1, 2, 56, 34, 1),
      (20, 64, 18, 14, 1, 4, 84, 42, 1),
      (22, 48, 20, 22, 1, 2, 72, 38, 1),
      (24, 48, 22, 22, 1, 2, 80, 41, 1),
      (24, 64, 22, 14, 1, 4, 108, 46, 1),
      (26, 40, 24, 18, 1, 2, 70, 38, 1),
      (26, 48, 24, 22, 1, 2, 90, 42, 1),
      (26, 64, 24, 14, 1, 4, 118, 50, 1)];

   function Find_Size (Rows, Columns : Integer) return Natural
   with Post => Find_Size'Result <= Num_Sizes
                and then
                  (if Find_Size'Result > 0
                   then Sizes (Find_Size'Result).Rows = Rows
                        and then Sizes (Find_Size'Result).Columns = Columns);
   --  The size of Rows by Columns modules; 0 if there is none.

   ---------------------------------------------------------------------
   --  The places of the codewords
   ---------------------------------------------------------------------

   subtype Codeword_Count is Natural range 0 .. Max_Codewords;
   subtype Codeword_Index is Positive range 1 .. Max_Codewords;

   type Module_Place is record
      Row, Column : Module_Index := 0;
   end record;

   subtype Bit_Index is Positive range 1 .. 8;
   --  1: the most significant bit.

   type Placement is array (Codeword_Index, Bit_Index) of Module_Place;

   procedure Place
     (Size  : Size_Index;
      Map   : out Placement;
      Count : out Codeword_Count;
      OK    : out Boolean);
   --  Map: the module of the symbol that holds each bit of each
   --  codeword. Count: the codewords placed. OK: Count is the number of
   --  codewords of the size, and every module was in the symbol (true
   --  for every size; the tests check it).

   ---------------------------------------------------------------------
   --  Decoding
   ---------------------------------------------------------------------

   type Codeword_Array is array (Codeword_Index range <>) of RS.Element;

   type Text_Buffer is array (Positive range <>) of Character;

   Max_Text_Length : constant := 2 * Max_Data + 9;
   --  No symbol has a longer text: a codeword gives two characters at
   --  most, the macros add nine.

   procedure To_Text
     (Data   : Codeword_Array;
      Text   : out Text_Buffer;
      Length : out Natural;
      OK     : out Boolean)
   with
     Pre  => Data'First = 1 and then Data'Length >= 1
             and then Text'First = 1 and then Text'Last >= 0,
     Post => Length <= Text'Length;
   --  The message of the data codewords. Not OK: a codeword that is not
   --  defined, a message that ends within an encodation unit, or a text
   --  longer than Text.

   procedure Decode
     (Grid      : Module_Grid;
      Size      : Size_Index;
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
   --  Reads the codewords of the symbol of the size Size whose modules
   --  are Grid (only the modules of the mapping matrix are looked at),
   --  corrects them and gives the message. Field: the tables of
   --  RS.Data_Matrix_Polynomial. Corrected: the codewords changed.
   --  Not Success: a block that cannot be corrected, or To_Text not OK.

end AMV.Kernels.Code_Reader.Data_Matrix;
