# Mutants that survive

AdaMutant (https://github.com/gomurin0428/AdaMutant) makes small changes
to the bodies (mutants: `<` for `<=`, a literal one higher, a statement
taken out, `'Min` for `'Max`), runs each with the areas of `test_suite`
that execute it and, where they all pass, with the proof of its unit
(`docs/DESIGN.md` 8, `adamutant.toml`, `tools/mutant_prove.sh`). A mutant
that neither detects survives. A survivor is a gap in the tests or in the
contracts until it is shown to be otherwise; this file lists the ones that
are left, body by body, with the reason, so that the code itself carries
no notes about its mutants.

The reasons are of four kinds:

* **Changes nothing**: no input gives another result. A value is read
  only where it was set again, a test is the same mirrored, a contract
  says more than its callers and the run need.
* **Not reached**: the mutant changes a bound or a guard that no input of
  the pass reaches (a map of the pass is at most 2 ** 26 pixels a side,
  for example).
* **Not pinned**: an input would tell the mutant from the source, but none
  is in the tests: a search over millions of maps found none, the input
  is too large to make in a test, or the result for it is not specified.
  The entry says what input would.
* **Proof not finished**: the tests pass, and the proof of the unit did
  not finish within its time (`prove_timeout_ms`). The entry says what a
  narrower proof showed, where one was made.

The workflow Mutation (`.github/workflows/mutation.yml`) runs AdaMutant
on the bodies that a pull request changes and keeps the report of each
as an artifact of its job. `make mutation MUTATE=src/<file>.adb` runs it
on a whole body here.

The lists below are those of the last run on each body: the whole body
where it is new, the changed lines where it is not. Mutants that do not
compile, and those whose object code is that of the source (Ignored),
are not listed.

## `AMV.Kernels.Code_Reader.QR_Code`

| Subprogram | Code | Change | Why it survives |
|---|---|---|---|
| (package) | `subtype Module_Number is Natural range 0 .. Max_Side - 1;` | `1` to `0`; `-` to `+` | Changes nothing: the rows and the columns are below `Max_Side` either way. Proof not finished. |
| `Mark_Functions` | `Last : Centre_Value := 0;` | `0` to `1` | Changes nothing: the loop that follows sets it to the largest centre; the centres of version 1 are all 0, and none of them is marked either way. |
| `Mark_Functions` | `Fill (Map, 6, 6, 0, S - 1);`, `Fill (Map, 0, S - 1, 6, 6);` | `0` to `1` | Changes nothing: the module 0 of either timing pattern is in the upper left finder pattern, marked above. |
| `Mark_Functions` | `and then not (R = 6 and then C = 6)` | either `6` to `7`; `R = 6` or `C = 6` to `False` | Changes nothing: the alignment pattern that it leaves out, around (6, 6), lies in the upper left finder pattern and its separator, marked above. |
| `Mark_Functions` | `Fill (Map, 0, 5, S - 11, S - 9);`, `Fill (Map, S - 11, S - 9, 0, 5);` | `5` to `6` | Changes nothing: the row 6 and the column 6 are the timing patterns, marked above. |
| `Masked` | the `+` of the masks 0 and 4, both of the mask 7 and the outer one of the mask 6 | `+` to `-` | Changes nothing: a difference has the parity of the sum. |
| `Read_Format` | `Which : Natural range 0 .. 31 := 0;` | `0` to `1` | Changes nothing: the first format word is nearer than `Bit_Total'Last` and replaces it. |
| `Read_Format` | `if Diff < Best then` | `<` to `<=` | Not pinned: copies as near to two format words (one to each) leave the format open, and which is taken is not specified; the source takes the first word, the mutant the last. |
| `Version_Agrees` | `A, B : Info_Bits := 0;` | `0` to `1` | Changes nothing: eighteen bits are pushed in after it, and `Info_Bits` keeps eighteen. |
| `Read_Codewords` | `V : RS.Element := 0;`, `V := 0;` after a codeword | `0` to `1`; the second taken out | Changes nothing: eight doublings push the old bits out of `V` (`RS.Element` is mod 256) before it is stored. |
| `Read_Codewords` | `Words := [others => 0];` | `0` to `1` | Changes nothing: `Words (1 .. Total)` are all set below, and only they are read. |
| `Read_Codewords` | `for Pair in 0 .. (S - 1) / 2 - 1 loop` | `1` to `0` | Changes nothing: the side is odd. |
| `Read_Codewords` | `if Right <= 6 then` | `6` to `7` | Changes nothing: `Right` is even. |
| `Read_Codewords` | `OK := Count = Total and then not Over;` | `and then` to `or else` | Changes nothing: the modules of the data of every version are `Total` codewords and fewer than eight bits more (the tests read every version), so both hold. |
| `Decode` | `return;` where `Read_Codewords` is not OK | taken out | Not reached: `Read_Codewords` is always OK, as above. |
| `Correct_Blocks` | `and then N_Data <= Max_Data` (postcondition) | taken out; to `True` | Changes nothing: a postcondition is not run, and the proof of `Decode` does not need this one. |
| `Correct_Blocks` | `Data := [others => 0];` | `0` to `1` | Changes nothing: `Data (1 .. N_Data)` is all set, and only it is read. |
| `Correct_Blocks` | `if P > Total then` (the codeword that a long block has more) | `>` to `>=` | Not reached: that codeword is one of the `D` of the message, all before the check codewords. |
| `Correct_Blocks` | `Corrected := 0;` where a block cannot be corrected | taken out | Changes nothing: `Decode` sets `Corrected` to 0 where `Correct_Blocks` fails. |
| `Correct_Blocks` | `if Offset + N_Own > D then`, and `Corrected := 0;` under it | `+` to `-`; taken out | Not reached: the codewords of the message of the blocks up to this one are among the `D` of them. |
| `To_Text` | `Lowest`: `1`, `7`, `31`, `32767` | `1` to `0`, the others one more | Not reached: `Get` takes no count of 1, 3, 5 or 15 bits. |
| `To_Text`, `Alphanumeric` | `Percent : Boolean := False;`, `Percent := False;` at the end of `Alphanumeric` | `False` to `True` | Changes nothing: `Percent` is read only within `Alphanumeric`, which sets it to `False` first. |
| `Get` | `V : Value_16 := 0;` | `0` to `1` | Changes nothing: the mask `Lowest (Count)` takes the higher bit off. |
| `Get` | `Value := 0;` where fewer bits are left | `0` to `1` | Changes nothing: `Good` no longer holds, and the text is not the result. |
| `Get` | `Valid and then Value <= Natural (Lowest (Count))` (postcondition) | `Valid` taken out; `and then` to `or else` | Proof not finished: the proof of `Numeric` alone fails with either ("cannot prove Valid"); that of the whole unit, with so many goals that fail, takes longer than its time. |
| `Put_Digits` | `Count <= 3 and then Value <= 999` (precondition) | `3` to `4`; `999` to `1000` | Changes nothing: the callers give at most three digits and 999, and the body is as safe with one more. |
| `Numeric`, `Alphanumeric` | `elsif Good then` (three) | `Good` to `True` | Changes nothing: where `Good` does not hold, the text is not the result. |
| `To_Text` | `for Step in 1 .. 2 * N loop` | `1` to `0`; `2` to `3` | Changes nothing: every segment takes four bits at least, so the loop leaves before its last step either way. |

## `AMV.Kernels.Code_Reader`

The changed lines: the symbols of the passes, the reading of QR Code
symbols and their places in the results.

| Subprogram | Code | Change | Why it survives |
|---|---|---|---|
| `Same_Text` | `Pool'First = 1 and then Text'First = 1 and then Length <= Text'Last` (precondition) | a relation to `False`; `=` to `/=`; `1` to `0`; `'First` to `'Last` and back; `<=` to `<` or `=` | Not pinned: `Same_Text` is called only for a symbol read a second time (`Add_Symbol`, below). Proof not finished. |
| `Add_Symbol` | `Text'First = 1 and then Length <= Text'Last and then Length <= Max_Matrix_Text_Length` (precondition) | `and then` to `or else`; a relation to `True` | Changes nothing: every caller meets the stronger one. Proof not finished. |
| `Add_Symbol` | `if Symbols (I).Kind = Kind and then Symbols (I).Length = Length` | the whole or a relation to `False`; `=` to `/=`; `and then` to `or else` | Not pinned: a symbol read a second time, from other finder patterns or from another dark area; no test image gives one (`Find_QR_Symbols` does not try the patterns of a symbol again). Some: proof not finished. |
| (package) | `Max_Partners : constant := 32;` | `32` to `33` | Not pinned: more than 30 patterns as wide nearer to a corner than its two others, none of which make a symbol with it. |
| `Read_Triple` | `Version := Symbol.Version + Step;` | `+` to `-` | Changes nothing: the same versions in another order (`Version_Steps` is symmetric), and a symbol is read with its own version only. |
| `Read_Triple` | `if OK then` | `OK` to `True` | Changes nothing: where `Sample` is not OK the grid is all light; it has no format information, and `Decode` fails at once. |
| `Read_Triple` | `Length := 0;` after a reading without a text | taken out | Changes nothing: `Length` is 0 there already (`Decode` gives 0 where it fails, and the text read was empty otherwise). |
| `Find_QR_Symbols` | `Ways : Way_List := [others => 0.0];` | `0.0` to `1.0` | Changes nothing: only `Ways (1 .. Nearest)` is read, and it is set before. |
| `Find_QR_Symbols` | `if not Taken (I) then` | to `True` | Not pinned: a corner already of a symbol, tried again with the patterns not of one; no test image gives a symbol from it. |
| `Find_QR_Symbols` | `if J /= I and then not Taken (J) and then QF.Akin (...)` | `J /= I` to `True`; either `and then` to `or else`; the whole to `True` | Not pinned: the corner itself, patterns already of a symbol and patterns of other widths among the nearest; no test image gives another result with them. The whole to `True`: proof not finished. |
| `Find_QR_Symbols` | `if Nearest < Max_Partners or else Way < Ways (Max_Partners)` | the whole to `True`; either `<` to `<=`; the second `<` to `/=` | Not pinned: more than 32 patterns as wide around a corner (see `Max_Partners`). |
| `Find_QR_Symbols` | `while Slot > 1 and then Ways (Slot - 1) > Way loop` and `Ways (Slot) := Ways (Slot - 1);` | `>` to `>=`; the statement taken out; `1` to `0` | Not pinned: patterns as far from the corner, or the nearest in another order; no test image gives another result with them. |
| `Find_QR_Symbols` | `for A in 1 .. B - 1 loop` | `1` to `0` | Changes nothing: a pair of one pattern twice is no symbol to `Place` (an angle of 0). |
| `Find_QR_Symbols` | `Taken (I) := True;`, `Taken (Near (A)) := True;`, `Taken (Near (B)) := True;` | taken out; `True` to `False` | Not pinned: the patterns of a symbol read, tried again with other corners; `Add_Symbol` does not add the symbol twice, and no test image gives another result with them. |
| `Find_Symbols` | `for Y in 0 .. H - 1 loop`, `for X in 0 .. W - 1 loop` (the dark areas) | `0` to `1` | Not pinned: an area whose outline is not reached from another row or column; a symbol at the edge of the map is read either way. |
| `Make_Matrix_Item` | `Valid_Item (Item) and then ...` (postcondition) | `and then` to `or else` | Changes nothing: a postcondition is not run. Proof not finished. |

## `AMV.Kernels.Code_Reader.Views`

| Subprogram | Code | Change | Why it survives |
|---|---|---|---|
| `Quotient` | `(if (X < 0.0) = (Y < 0.0) then Q else -Q)` | `Y < 0.0` to `Y <= 0.0` | Changes nothing: `Y` is never 0.0 (the precondition). |
| `Project` | `Ahead := W > 1.0E-6;` | `>` to `>=`; `1.0E-6` to `0.0` | Not pinned: a W of 1.0E-6 exactly, or above 0.0 and at most 1.0E-6 at a point that the mapping still puts within 2 ** 28 pixels of the axes; no map was found. |
| `Project` | `X := 0.0;`, `Y := 0.0;` | `0.0` to `1.0` | Changes nothing: `X` and `Y` are read only where `Ahead` holds. |

## `AMV.Kernels.Code_Reader.Data_Matrix.Finder`

No changed line has a survivor.
