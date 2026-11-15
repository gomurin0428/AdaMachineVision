--  The decoders of the linear symbologies of AMV.Kernels.Code_Reader:
--  EAN-13, EAN-8, UPC-A, UPC-E, Code 128, Code 39 and Interleaved 2 of 5.
--  Internal: not an entry point (no export), so the package is private to
--  the code reader.
--
--  A segment of a scan line arrives as the positions of its edges, in
--  1/256 pixel from the start of the segment:
--
--     Edges (0)     the start of the segment
--     Edges (K)     the edge between run K - 1 and run K
--     Edges (Last)  the end of the segment
--
--  Run K lies between Edges (K) and Edges (K + 1). The runs with an even
--  index are light and those with an odd index are dark; Last is odd, so
--  that the first and the last run are light. A segment that starts or
--  ends dark has a first or last run of no width.
--
--  The decoders use integers only. A character of n modules is measured
--  against its own width S: a distance d between two edges of the same
--  kind is Round (n * d / S) modules. A light margin is required before
--  and after a symbol; at the start or the end of the segment (the border
--  of the image or of the region) one module of margin is enough, except
--  for ITF.

pragma Validity_Checks ("F");
pragma Assertion_Policy
  (Pre => Check, Post => Ignore, Ghost => Ignore,
   Loop_Invariant => Ignore, Loop_Variant => Ignore, Assert => Ignore,
   Assert_And_Cut => Ignore, Contract_Cases => Ignore,
   Subprogram_Variant => Ignore, Dynamic_Predicate => Ignore,
   Type_Invariant => Ignore, Default_Initial_Condition => Ignore);

private package AMV.Kernels.Code_Reader.Linear
  with SPARK_Mode, Preelaborate
is

   Max_Position : constant := 2 ** 28;
   --  Max_Line_Samples pixels in 1/256 pixel.

   subtype Position is Int32 range 0 .. Max_Position;

   type Position_Array is array (Natural range <>) of Position;

   Max_Edges : constant := 2 ** 21;
   --  A bound of the index of an edge.

   function Well_Formed
     (Edges : Position_Array; Last : Natural) return Boolean
   is
     (Edges'First = 0
      and then Edges'Last <= Max_Edges
      and then Last in 1 .. Edges'Last
      and then Last mod 2 = 1);
   --  Edges (0 .. Last) can be the edges of a segment.

   type Decode_Options is record
      EAN_13         : Boolean := True;
      EAN_8          : Boolean := True;
      UPC_A          : Boolean := True;
      UPC_E          : Boolean := True;
      Code_128       : Boolean := True;
      Code_39        : Boolean := True;
      ITF            : Boolean := True;
      Code_39_Check  : Boolean := False;
      ITF_Check      : Boolean := False;
      ITF_Min_Digits : Positive := 6;
   end record;

   type Reading is record
      Symbology : Int32 := Symbology_EAN_13;
      Length    : Text_Length := 0;
      Text      : Code_Text := No_Text;
      Last_Edge : Natural := 0;
      --  The edge that ends the last bar of the symbol.
   end record;

   No_Reading : constant Reading := (others => <>);

   procedure Decode_At
     (Edges   : Position_Array;
      Last    : Natural;
      Start   : Positive;
      Options : Decode_Options;
      Found   : out Boolean;
      Item    : out Reading)
   with
     Pre  => Well_Formed (Edges, Last)
             and then Start mod 2 = 1 and then Start < Last,
     Post => (if Found
              then Is_Symbology (Item.Symbology)
                   and then Item.Length >= 1
                   and then Item.Last_Edge in Start + 16 .. Last
                   and then (for all I in Item.Length + 1 .. Code_Text'Last
                               => Item.Text (I) = ASCII.NUL));
   --  Tries every enabled symbology on a symbol whose first bar is run
   --  Start, that is, whose first edge is Edges (Start).

end AMV.Kernels.Code_Reader.Linear;
