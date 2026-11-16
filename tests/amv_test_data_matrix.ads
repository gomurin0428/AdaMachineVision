--  A Data Matrix (ECC 200) encoder for the tests: from a text to the
--  codewords of an encodation, and from the codewords to the modules of
--  a symbol.
--
--  It shares only the table of the sizes with the kernel that reads the
--  symbols (AMV.Kernels.Code_Reader.Data_Matrix.Sizes, which the tests
--  check by itself). Its arithmetic in GF(256) is shift and xor without
--  tables, its check codewords are the remainder of a division by the
--  generator polynomial, and its placement of the codewords is the
--  program of the symbology's specification, which marks every module of
--  the mapping matrix with its codeword and bit.
--
--  Draw paints the modules into an image between any four corners, so
--  that the tests know where a symbol is and how it lies.

with AMV.Images;
with AMV.Kernels.Code_Reader.Data_Matrix;

package AMV_Test_Data_Matrix is

   package DM renames AMV.Kernels.Code_Reader.Data_Matrix;

   subtype Byte is Natural range 0 .. 255;

   type Byte_List is array (Positive range <>) of Byte;

   ---------------------------------------------------------------------
   --  From a text to codewords
   ---------------------------------------------------------------------

   --  Each function gives the codewords that stand for Text when the
   --  ASCII encodation is in force before them, and leaves the ASCII
   --  encodation in force after them. Constraint_Error: a character
   --  that the encodation does not have.

   function ASCII (Text : String) return Byte_List;
   --  Two digits in one codeword where there are two; the upper shift
   --  before a character above 127.

   function C40 (Text : String) return Byte_List;
   function Lower (Text : String) return Byte_List;
   --  The C40 and the Text encodation: the latch, the values three to
   --  two codewords (two values at the end are filled up with the value
   --  of shift 1), the unlatch. Where one value would be left over, the
   --  characters from there on follow the unlatch in the ASCII
   --  encodation.

   function X12 (Text : String) return Byte_List;
   --  Text: a multiple of three characters.

   function EDIFACT (Text : String) return Byte_List;
   --  The latch, the characters and the unlatch value, four values to
   --  three codewords; the last codewords only as far as they have bits
   --  of a value. Two codewords or more must follow in the symbol.

   function Hidden (Value : Byte; Place : Positive) return Byte;
   --  The byte Value as a codeword of the Base 256 encodation at the
   --  place Place among the codewords of the symbol.

   function Base_256
     (Text  : String;
      First : Positive := 1) return Byte_List;
   --  The latch, the length and the bytes. First: the place of the
   --  latch among the codewords of the symbol (the bytes are hidden
   --  behind numbers that follow from their places).

   ---------------------------------------------------------------------
   --  From codewords to a symbol
   ---------------------------------------------------------------------

   function Smallest_Size
     (Count       : Positive;
      Rectangular : Boolean := False) return DM.Size_Index;
   --  The smallest square (or rectangular) size for Count codewords.

   function Padded
     (Data : Byte_List;
      Size : DM.Size_Index) return Byte_List;
   --  Data and the pad codewords that fill the size.

   function Stream
     (Data : Byte_List;
      Size : DM.Size_Index) return Byte_List;
   --  Data (as many codewords as the size has) and the check codewords,
   --  in the order of their places.

   type Mark_Matrix is
     array (Natural range <>, Natural range <>) of Natural;

   function Marks (Size : DM.Size_Index) return Mark_Matrix;
   --  The mapping matrix of the size (the regions without their borders,
   --  (Row, Column) from 0) as the program of the specification fills
   --  it: 10 * codeword + bit (bit 1: the most significant), 1 for the
   --  two dark modules of the fixed pattern in the lower right corner
   --  and 0 for its two light ones.

   function Symbol_Row
     (Size : DM.Size_Index;
      Row  : Natural) return Natural;
   function Symbol_Column
     (Size   : DM.Size_Index;
      Column : Natural) return Natural;
   --  The row and the column of the symbol that hold the row Row and
   --  the column Column of the mapping matrix.

   type Module_Matrix is
     array (Natural range <>, Natural range <>) of Boolean;
   --  (Row, Column) from 0; True: dark.

   function Modules
     (Codewords : Byte_List;
      Size      : DM.Size_Index) return Module_Matrix;
   --  The symbol with the codewords Codewords (all of them: Stream).

   function Symbol
     (Data : Byte_List;
      Size : DM.Size_Index) return Module_Matrix
   is (Modules (Stream (Padded (Data, Size), Size), Size));

   function Symbol (Data : Byte_List) return Module_Matrix
   is (Symbol (Data, Smallest_Size (Data'Length)));

   function Grid (Symbol : Module_Matrix) return DM.Module_Grid;
   --  The modules as the kernel takes them.

   ---------------------------------------------------------------------
   --  From the modules to an image
   ---------------------------------------------------------------------

   type Place is record
      X, Y : Long_Float := 0.0;
   end record;
   --  A point of pixel space: the middle of pixel (I, J) is at (I, J).

   type Corners is record
      Upper_Left, Upper_Right, Lower_Right, Lower_Left : Place;
   end record;
   --  The corners of a symbol as it is printed: the L runs from the
   --  upper left corner by the lower left one to the lower right one.

   function Placed
     (Center_X, Center_Y : Long_Float;
      Width, Height      : Long_Float;
      Rotation           : Long_Float := 0.0;
      Mirror             : Boolean := False) return Corners;
   --  The corners of a symbol of Width by Height pixels with its middle
   --  at (Center_X, Center_Y) and its lower side, from the corner of the
   --  L, along the direction Rotation (radians; 0.0: as it is printed).
   --  Mirror: the symbol as it is seen from behind, its upper side
   --  where the lower one would be.

   function Middle (Where : Corners) return Place;
   --  Where the diagonals cross.

   procedure Draw
     (Image  : in out AMV.Images.Ks_Image_8_Grey;
      Symbol : Module_Matrix;
      Where  : Corners;
      Dark   : AMV.Images.Grey_8 := 0);
   --  Paints the dark modules of the symbol between the corners, which
   --  may be those of any convex quadrilateral (a symbol seen at an
   --  angle; the modules follow in perspective). A pixel moves towards
   --  the level Dark by the share of its 4 by 4 sample points that lie
   --  in a dark module; the light modules and the margin are whatever
   --  the image holds.

end AMV_Test_Data_Matrix;
