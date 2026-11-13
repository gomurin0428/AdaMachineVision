--  FlipRotate of AMV.Kernels.IP_One_Image: mirrors and quarter turns of
--  the whole image, and the transform each makes of the pixel grid.
--  Internal.

pragma Validity_Checks ("F");

pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

with AMV.Kernels.IP_One_Image.Common;

private package AMV.Kernels.IP_One_Image.Flip_Rotate
  with SPARK_Mode, Preelaborate
is

   function Swapping (Code : Flip_Rotate_Code) return Boolean is
     (Code in Flip_Rotate_Rotate_90_Deg | Flip_Rotate_Rotate_270_Deg
            | Flip_Rotate_Flip_And_Rotate_90_Deg
            | Flip_Rotate_Flip_And_Rotate_270_Deg);
   --  The codes that swap Width and Height.

   --  For an input of W x H pixels, the output pixel (X, Y) holds the
   --  input pixel (Source_X, Source_Y):
   --
   --     code  operation          Source_X     Source_Y
   --       0   None               X            Y
   --       1   Rotate90Deg        Y            H - 1 - X
   --       2   Rotate180Deg       W - 1 - X    H - 1 - Y
   --       3   Rotate270Deg       W - 1 - Y    X
   --       4   Flip               W - 1 - X    Y
   --       5   FlipAndRotate90    W - 1 - Y    H - 1 - X
   --       6   FlipAndRotate180   X            H - 1 - Y
   --       7   FlipAndRotate270   Y            X

   function Source_X
     (Code : Flip_Rotate_Code;
      W, H : Int32;
      X, Y : Natural) return Natural
   is
     (case Code is
         when 0 | 6 => X,
         when 2 | 4 => Natural (W) - 1 - X,
         when 1 | 7 => Y,
         when 3 | 5 => Natural (W) - 1 - Y)
   with
     Pre  => W >= 1 and then H >= 1
             and then X < Natural (if Swapping (Code) then H else W)
             and then Y < Natural (if Swapping (Code) then W else H),
     Post => Source_X'Result < Natural (W);

   function Source_Y
     (Code : Flip_Rotate_Code;
      W, H : Int32;
      X, Y : Natural) return Natural
   is
     (case Code is
         when 0 | 4 => Y,
         when 2 | 6 => Natural (H) - 1 - Y,
         when 3 | 7 => X,
         when 1 | 5 => Natural (H) - 1 - X)
   with
     Pre  => W >= 1 and then H >= 1
             and then X < Natural (if Swapping (Code) then H else W)
             and then Y < Natural (if Swapping (Code) then W else H),
     Post => Source_Y'Result < Natural (H);

   type Grid_Map is record
      Swap   : Boolean := False;
      Flip_X : Boolean := False;
      Flip_Y : Boolean := False;
      TX, TY : Int64 := 0;
   end record;
   --  The map from input to output pixel coordinates of a sequence of
   --  these operators: without Swap, (x, y) goes to (SX x + TX, SY y +
   --  TY); with Swap, to (SX y + TX, SY x + TY); SX is -1 when Flip_X and
   --  1 otherwise, SY likewise. The default is the identity.

   Identity : constant Grid_Map := (others => <>);

   function Step_Map (Code : Flip_Rotate_Code; W, H : Int32) return Grid_Map
   is
     (case Code is
         when 0 => Identity,
         when 1 => (True, True, False, Int64 (H) - 1, 0),
         when 2 => (False, True, True, Int64 (W) - 1, Int64 (H) - 1),
         when 3 => (True, False, True, 0, Int64 (W) - 1),
         when 4 => (False, True, False, Int64 (W) - 1, 0),
         when 5 => (True, True, True, Int64 (H) - 1, Int64 (W) - 1),
         when 6 => (False, False, True, 0, Int64 (H) - 1),
         when 7 => (True, False, False, 0, 0))
   with
     Pre  => W >= 1 and then H >= 1,
     Post => Step_Map'Result.TX in 0 .. Int64 (Int32'Last)
             and then Step_Map'Result.TY in 0 .. Int64 (Int32'Last)
             and then (if Code = 0 then Step_Map'Result = Identity);
   --  The map of one operator on a W x H image (the inverse of the table
   --  above).

   function Negated (Flip : Boolean; V : Int64) return Int64 is
     (if Flip then -V else V)
   with Pre => V > Int64'First;

   function Then_Map (First, Second : Grid_Map) return Grid_Map is
     (if Second.Swap
      then (Swap   => not First.Swap,
            Flip_X => Second.Flip_X /= First.Flip_Y,
            Flip_Y => Second.Flip_Y /= First.Flip_X,
            TX     => Negated (Second.Flip_X, First.TY) + Second.TX,
            TY     => Negated (Second.Flip_Y, First.TX) + Second.TY)
      else (Swap   => First.Swap,
            Flip_X => Second.Flip_X /= First.Flip_X,
            Flip_Y => Second.Flip_Y /= First.Flip_Y,
            TX     => Negated (Second.Flip_X, First.TX) + Second.TX,
            TY     => Negated (Second.Flip_Y, First.TY) + Second.TY))
   with
     Pre => First.TX in -2**60 .. 2**60 and then First.TY in -2**60 .. 2**60
            and then Second.TX in -2**60 .. 2**60
            and then Second.TY in -2**60 .. 2**60;
   --  First, then Second.

   procedure Apply
     (Source : access constant KI.Ks_Image_8_Grey_Data;
      Code   : Flip_Rotate_Code;
      Result : out KI.Ks_Image_8_Grey;
      Status : out Ks_Status)
   with
     Pre  => Common.Usable (Source),
     Post => Valid (Status)
             and then Status.Failure in Failure_None | Failure_Out_Of_Memory
             and then
               (if Succeeded (Status)
                then KI.Valid_Image (Result)
                     and then
                       (if Swapping (Code)
                        then Result.Width = Source.Height
                             and then Result.Height = Source.Width
                        else Result.Width = Source.Width
                             and then Result.Height = Source.Height)
                     and then
                       (for all Y in Result.Pixels'Range (1) =>
                          (for all X in Result.Pixels'Range (2) =>
                             Result.Pixels (Y, X)
                               = Source.Pixels
                                   (Source_Y (Code, Source.Width,
                                              Source.Height, X, Y),
                                    Source_X (Code, Source.Width,
                                              Source.Height, X, Y))))
                else Result = null);
   --  The turned or mirrored image (Gold: every pixel exactly where the
   --  table above puts it).

end AMV.Kernels.IP_One_Image.Flip_Rotate;
