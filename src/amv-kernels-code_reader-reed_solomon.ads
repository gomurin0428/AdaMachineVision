--  Reed-Solomon error correction over GF(256), for the two-dimensional
--  symbologies of AMV.Kernels.Code_Reader. Internal: no entry points of
--  its own (no export); public so that the tests can call it.
--
--  The field. An element is a polynomial over GF(2) of degree below 8,
--  held as the byte whose bit k is the coefficient of x**k. The sum of
--  two elements is their xor; the product is taken modulo the polynomial
--  of the field (16#12D# for Data Matrix and 16#11D# for QR Code).
--  Alpha is the element x. Make_Field builds the tables of the powers of
--  Alpha and of their logarithms.
--
--  The code. A word W of n elements (n <= 255) stands for the polynomial
--  whose coefficient of the highest degree is W (W'First). It is a
--  codeword of the code with Parity check elements and the first root
--  First_Root when it is zero at Alpha ** (First_Root + j) for j in
--  0 .. Parity - 1: its Parity syndromes are zero. Data Matrix has
--  First_Root = 1, QR Code 0. Two codewords differ in more than Parity
--  places: at most Parity / 2 wrong elements leave one nearest codeword.
--
--  Correct finds it: the syndromes, the error locator by the
--  Berlekamp-Massey algorithm, its roots by trying every place (Chien),
--  the error values by Forney's formula. It then computes the syndromes
--  of the corrected word again and counts the changed elements, and
--  succeeds only if every syndrome is zero and at most Parity / 2
--  elements changed.
--
--  Proved: no run-time error for any input (any tables, even those of a
--  polynomial that gives no field), and the postcondition of Correct:
--  after a success the word is a codeword that differs from the word
--  given in Corrected <= Parity / 2 places; after a failure the word is
--  unchanged. Not proved (tested): that a word with at most Parity / 2
--  wrong elements is always corrected.

pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

package AMV.Kernels.Code_Reader.Reed_Solomon
  with SPARK_Mode, Preelaborate
is

   type Element is mod 2 ** 8;
   --  An element of GF(256). "xor" adds two of them.

   subtype Exponent is Natural range 0 .. 254;
   --  Alpha ** 255 = 1.

   type Exp_Table is array (Exponent) of Element;
   type Log_Table is array (Element) of Exponent;

   type Field is record
      Exp : Exp_Table := [others => 1];
      --  Exp (K) = Alpha ** K.
      Log : Log_Table := [others => 0];
      --  Log (Exp (K)) = K; Log (0) is not used.
   end record;

   subtype Field_Polynomial is Natural range 16#100# .. 16#1FF#;

   Data_Matrix_Polynomial : constant Field_Polynomial := 16#12D#;
   QR_Code_Polynomial     : constant Field_Polynomial := 16#11D#;

   function Make_Field (Polynomial : Field_Polynomial) return Field;
   --  The tables of GF(256) modulo Polynomial (which must be primitive
   --  for them to be the tables of a field; the two above are).

   function Mul (F : Field; A, B : Element) return Element is
     (if A = 0 or else B = 0
      then 0
      else F.Exp ((F.Log (A) + F.Log (B)) mod 255));
   --  A * B.

   function Inverse (F : Field; A : Element) return Element is
     (F.Exp ((255 - F.Log (A)) mod 255));
   --  1 / A, for A /= 0.

   Max_Length : constant := 255;
   --  The longest word.

   subtype Word_Index is Positive range 1 .. Max_Length;

   type Word is array (Word_Index range <>) of Element;

   function Syndrome
     (F    : Field;
      W    : Word;
      Root : Exponent) return Element;
   --  The value at Alpha ** Root of the polynomial that W stands for.

   function Is_Codeword
     (F          : Field;
      W          : Word;
      Parity     : Positive;
      First_Root : Exponent) return Boolean
   is
     (for all J in 0 .. Parity - 1 =>
        Syndrome (F, W, (First_Root + J) mod 255) = 0)
   with Pre => Parity < Max_Length;
   --  Every syndrome of W is zero.

   function Differences
     (A, B : Word;
      Last : Natural) return Natural
   is
     (if Last = 0
      then 0
      else Differences (A, B, Last - 1)
           + (if A (Last) /= B (Last) then 1 else 0))
   with
     Ghost,
     Pre  => A'First = 1 and then B'First = 1
             and then Last <= A'Last and then Last <= B'Last,
     Post => Differences'Result <= Last,
     Subprogram_Variant => (Decreases => Last);
   --  The number of places up to Last where A and B differ.

   procedure Correct
     (F          : Field;
      W          : in out Word;
      Parity     : Positive;
      First_Root : Exponent;
      Corrected  : out Natural;
      Success    : out Boolean)
   with
     Pre  => W'First = 1 and then Parity < W'Length,
     Post => (if Success
              then Is_Codeword (F, W, Parity, First_Root)
                   and then Corrected <= Parity / 2
                   and then Corrected = Differences (W, W'Old, W'Last)
              else W = W'Old and then Corrected = 0);
   --  Corrects W, whose last Parity elements are the check elements.
   --  Corrected: the number of elements changed.

end AMV.Kernels.Code_Reader.Reed_Solomon;
