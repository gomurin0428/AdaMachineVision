pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with Interfaces;

package body AMV.Kernels.Code_Reader.Reed_Solomon with SPARK_Mode is

   use type Interfaces.Unsigned_16;

   subtype Degree is Natural range 0 .. 255;

   type Polynomial is array (Degree) of Element;
   --  Coefficient K is that of x ** K.

   ----------------
   -- Make_Field --
   ----------------

   function Make_Field (Polynomial : Field_Polynomial) return Field is
      F : Field;
      X : Interfaces.Unsigned_16 := 1;
   begin
      for K in Exponent loop
         F.Exp (K) := Element (X);
         F.Log (Element (X)) := K;
         X := X * 2;
         if X >= 256 then
            X := (X xor Interfaces.Unsigned_16 (Polynomial)) and 16#FF#;
         end if;
         pragma Loop_Invariant (X <= 255);
      end loop;
      return F;
   end Make_Field;

   --------------
   -- Syndrome --
   --------------

   function Syndrome
     (F    : Field;
      W    : Word;
      Root : Exponent) return Element
   is
      X : constant Element := F.Exp (Root);
      R : Element := 0;
   begin
      for I in W'Range loop
         R := Mul (F, R, X) xor W (I);
      end loop;
      return R;
   end Syndrome;

   --------------
   -- Value_At --
   --------------

   function Value_At
     (F    : Field;
      P    : Polynomial;
      Last : Degree;
      X    : Element) return Element;
   --  The value at X of the terms 0 .. Last of P.

   function Value_At
     (F    : Field;
      P    : Polynomial;
      Last : Degree;
      X    : Element) return Element
   is
      R : Element := 0;
   begin
      for K in reverse 0 .. Last loop
         R := Mul (F, R, X) xor P (K);
      end loop;
      return R;
   end Value_At;

   -------------
   -- Locator --
   -------------

   procedure Locator
     (F      : Field;
      S      : Polynomial;
      Parity : Positive;
      Lambda : out Polynomial;
      Errors : out Natural)
   with
     Pre  => Parity < Max_Length,
     Post => Errors <= Parity;
   --  Berlekamp-Massey: the shortest recurrence that gives the syndromes
   --  S (0 .. Parity - 1). Lambda: its polynomial, the error locator
   --  (Lambda (0) = 1); Errors: its length, the number of errors.

   procedure Locator
     (F      : Field;
      S      : Polynomial;
      Parity : Positive;
      Lambda : out Polynomial;
      Errors : out Natural)
   is
      B     : Polynomial := [0 => 1, others => 0];
      --  The locator before the last change of length.
      T     : Polynomial;
      L     : Natural := 0;
      M     : Positive := 1;
      --  The steps since that change.
      B_D   : Element := 1;
      --  The discrepancy at that change.
      D     : Element;
      Scale : Element;
   begin
      Lambda := [0 => 1, others => 0];

      for Step in 0 .. Parity - 1 loop
         pragma Loop_Invariant (L <= Step);
         pragma Loop_Invariant (M <= Step + 1);

         D := S (Step);
         for I in 1 .. L loop
            D := D xor Mul (F, Lambda (I), S (Step - I));
         end loop;

         if D = 0 then
            M := M + 1;
         else
            Scale := Mul (F, D, Inverse (F, B_D));
            T := Lambda;
            for I in 0 .. 255 - M loop
               Lambda (I + M) := Lambda (I + M) xor Mul (F, Scale, B (I));
            end loop;
            if 2 * L <= Step then
               L := Step + 1 - L;
               B := T;
               B_D := D;
               M := 1;
            else
               M := M + 1;
            end if;
         end if;
      end loop;

      Errors := L;
   end Locator;

   ----------------
   -- Lemma_Same --
   ----------------

   procedure Lemma_Same (A, B : Word; Last : Natural)
   with
     Ghost,
     Pre  => A'First = 1 and then B'First = 1
             and then Last <= A'Last and then Last <= B'Last
             and then (for all I in 1 .. Last => A (I) = B (I)),
     Post => Differences (A, B, Last) = 0,
     Subprogram_Variant => (Decreases => Last);
   --  Words that are the same up to Last differ nowhere up to Last.

   procedure Lemma_Same (A, B : Word; Last : Natural) is
   begin
      if Last > 0 then
         Lemma_Same (A, B, Last - 1);
      end if;
   end Lemma_Same;

   -------------
   -- Correct --
   -------------

   procedure Correct
     (F          : Field;
      W          : in out Word;
      Parity     : Positive;
      First_Root : Exponent;
      Corrected  : out Natural;
      Success    : out Boolean)
   is
      Old : constant Word := W;
      N   : constant Positive := W'Last;

      S      : Polynomial := [others => 0];
      --  The syndromes.
      Lambda : Polynomial;
      --  The error locator.
      Omega  : Polynomial := [others => 0];
      --  The error evaluator: S * Lambda modulo x ** Parity.
      Slope  : Polynomial := [others => 0];
      --  The derivative of Lambda.

      Clean  : Boolean := True;
      Errors : Natural;
      Found  : Natural := 0;
      Count  : Natural := 0;
      Sum    : Element;
      Power  : Exponent;
      X_Inv  : Element;
      Bottom : Element;
      Value  : Element;
   begin
      Corrected := 0;
      Success := False;

      --  The syndromes.

      for J in 0 .. Parity - 1 loop
         S (J) := Syndrome (F, W, (First_Root + J) mod 255);
         if S (J) /= 0 then
            Clean := False;
         end if;
         pragma Loop_Invariant
           (if Clean
            then (for all K in 0 .. J =>
                    Syndrome (F, W, (First_Root + K) mod 255) = 0));
      end loop;

      if Clean then
         Lemma_Same (W, Old, N);
         Success := True;
         return;
      end if;

      --  The error locator and what Forney's formula needs.

      Locator (F, S, Parity, Lambda, Errors);

      if Errors = 0 or else Errors > Parity / 2 then
         return;
      end if;

      for K in 0 .. Parity - 1 loop
         Sum := 0;
         for I in 0 .. Natural'Min (K, Errors) loop
            Sum := Sum xor Mul (F, Lambda (I), S (K - I));
         end loop;
         Omega (K) := Sum;
      end loop;

      for K in 1 .. Errors loop
         if K mod 2 = 1 then
            Slope (K - 1) := Lambda (K);
         end if;
      end loop;

      --  The places of the errors and their values. Place I has the
      --  degree N - I.

      for I in 1 .. N loop
         pragma Loop_Invariant (Found < I);

         Power := N - I;
         X_Inv := F.Exp ((255 - Power) mod 255);

         if Value_At (F, Lambda, Errors, X_Inv) = 0 then
            Found := Found + 1;
            Bottom := Value_At (F, Slope, Errors, X_Inv);
            if Bottom = 0 then
               W := Old;
               return;
            end if;

            Value :=
              Mul (F,
                   Value_At (F, Omega, Parity - 1, X_Inv),
                   Inverse (F, Bottom));
            --  Times (Alpha ** Power) ** (1 - First_Root).
            Value := Mul (F, Value, F.Exp (Power));
            Value :=
              Mul (F, Value,
                   F.Exp ((((255 - Power) mod 255) * First_Root) mod 255));

            W (I) := W (I) xor Value;
         end if;
      end loop;

      if Found /= Errors then
         W := Old;
         return;
      end if;

      --  The corrected word must be a codeword near the word given.

      for J in 0 .. Parity - 1 loop
         if Syndrome (F, W, (First_Root + J) mod 255) /= 0 then
            W := Old;
            return;
         end if;
         pragma Loop_Invariant
           (for all K in 0 .. J =>
              Syndrome (F, W, (First_Root + K) mod 255) = 0);
      end loop;

      for I in 1 .. N loop
         if W (I) /= Old (I) then
            Count := Count + 1;
         end if;
         pragma Loop_Invariant (Count = Differences (W, Old, I));
      end loop;

      if Count > Parity / 2 then
         W := Old;
         return;
      end if;

      Corrected := Count;
      Success := True;
   end Correct;

end AMV.Kernels.Code_Reader.Reed_Solomon;
