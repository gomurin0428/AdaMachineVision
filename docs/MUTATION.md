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
  is in the tests: a search found none (the entry says over how many
  inputs), the input is too large to make in a test, or the result for it
  is not specified. The entry says what input would.
* **Proof not finished**: the tests pass, and the proof of the unit did
  not finish within its time (`prove_timeout_ms`). The entry says what a
  narrower proof showed, where one was made.

The workflow Mutation (`.github/workflows/mutation.yml`) runs AdaMutant
on the bodies that a pull request changes and keeps the report of each
as an artifact of its job. `make mutation MUTATE=src/<file>.adb` runs it
on a whole body here.

Each changed body gets one full-unit baseline proof, independently of
the AdaMutant build. Its successful prover cache is overlaid on the
restored cache in every mutation shard for that body. The baseline job is
limited to 40 minutes, with its proof step stopped after 30 minutes so
failure diagnostics can be uploaded; the mutation job retains its
existing limits.
AMV_PROVE_TIMEOUT sets GNATprove's per-prover time limit in seconds
(120 by default) for both the baseline and mutant proofs; the step limit
remains 200,000. A prover timeout is incomplete proof evidence and fails
the proof. It is not a confirmed semantic defect. AdaMutant's separate
five-minute test and 15-minute mutant-proof limits are unchanged.

The mutation wrapper records each proof invocation's real exit code and
fresh per-unit .spark final-check evidence under a run-specific directory.
AdaMutant's raw report remains unchanged. A proof-killed result passes the
gate only with a fresh selected-unit .spark high-severity final check or a
high-severity diagnostic matched to a fresh unproved check. Every final-check
entry must be well-formed and carry location metadata; one confirmed
counterexample is sufficient despite other well-formed inconclusive checks.
Malformed or unlocated checks block confirmation. Raw Survived results and
NoCoverage results whose reason depends on proof require fresh selected-unit
evidence, GNATprove exit 0, and all final checks proved. Missing, stale,
incomplete, resource-limited, unknown, or timed-out proof evidence is explicitly
Inconclusive and fails the job; the gate stays closed for every resource-only
outcome. A timeout in one prover attempt does not invalidate a final check
marked proved. Proof-killed, Survived, and proof-dependent NoCoverage entries
are removed from a filtered copy of a baseline report so they are rerun;
ordinary test, compile, and runtime results are reused. The last report is
cached only after the gate succeeds, while raw reports and evidence remain
available as artifacts on failure.

The mutation tests include a separate `Test_Max_Pixels_Limit` executable for
the exact `Max_Pixels` boundary. It is not part of the normal `test_suite`.
Its Python launcher sets and verifies both soft and hard `RLIMIT_AS` at
256 MiB on Linux before replacing itself with the Ada test; the Ada test also
refuses to run without the launcher's marker. The unchanged kernel must return
`Out_Of_Memory` with a null image under that cap. The cap keeps this regression
from attempting an unbounded multi-gigabyte allocation, and the launcher fails
closed if it cannot enforce the limit.

Changed bodies with more than 30 added lines use the same seven mutator
shards; 30 or fewer use the default set together. Whole-file requests use
the file's line count for this decision. The workflow records processor
and memory availability and per-stage elapsed/resource statistics.

A test that checks how long a run takes (against a limit, or against
another run) skips that check while a mutant is active
(`AMV_Test_Support.Check_Timing`): the tests of the mutants run beside
the proofs of others, and under that load such a check can fail
whatever the mutant is. Before the check was skipped, four mutants of
the QR Code bodies were counted as detected because `Test_Shape_Match`
failed on its timing; they are listed below with the others.

Until the tests checked the contracts (phase 3 of `docs/PLATINUM.md`),
they checked preconditions only, and a mutant of a postcondition, a
predicate or ghost code was the proof's alone. The rows that say "a
postcondition is not run" come from runs made before then. The build of
the tests now checks postconditions, predicates and ghost code too
(`tests/contracts.adc`), but not loop invariants and assertions, which
are steps of the proofs.

The lists below are those of the last run on each body: the whole body
where it is new, the changed lines where it is not. Mutants that do not
compile, and those whose object code is that of the source (Ignored),
are not listed.

## `AMV.Kernels.Code_Reader.QR_Code`

| Subprogram | Code | Change | Why it survives |
|---|---|---|---|
| (package) | `subtype Module_Number is Natural range 0 .. Max_Side - 1;` | `-` to `+` | Changes nothing at run time: the rows and the columns are below `Max_Side` either way. Proof not finished; with `1` to `0`, which widens the range less, the proof fails (a range check of a column). |
| `Mark_Functions` | `Last : Centre_Value := 0;` | `0` to `1` | Changes nothing: the loop that follows sets it to the largest centre; the centres of version 1 are all 0, and none of them is marked either way. |
| `Mark_Functions` | `Fill (Map, 6, 6, 0, S - 1);`, `Fill (Map, 0, S - 1, 6, 6);` | `0` to `1` | Changes nothing: the module 0 of either timing pattern is in the upper left finder pattern, marked above. |
| `Mark_Functions` | `and then not (R = 6 and then C = 6)` | either `6` to `7`; `R = 6` or `C = 6` to `False` | Changes nothing: the alignment pattern that it leaves out, around (6, 6), lies in the upper left finder pattern and its separator, marked above. |
| `Mark_Functions` | `and then not (R = 6 and then C = Last)`, `and then not (R = Last and then C = 6)` | `C = Last`, `R = Last` to `>=` | Changes nothing: `Last` is the largest of the centres, so none is above it. |
| `Mark_Functions` | `Fill (Map, 0, 5, S - 11, S - 9);`, `Fill (Map, S - 11, S - 9, 0, 5);` | `5` to `6` | Changes nothing: the row 6 and the column 6 are the timing patterns, marked above. |
| `Masked` | the `+` of the masks 0 and 4, both of the mask 7 and the outer one of the mask 6 | `+` to `-` | Changes nothing: a difference has the parity of the sum. |
| `Read_Format` | `Which : Natural range 0 .. 31 := 0;` | `0` to `1` | Changes nothing: the first format word is nearer than `Bit_Total'Last` and replaces it. |
| `Read_Format` | `if Diff < Best then` | `<` to `<=` | Not pinned: copies as near to two format words (one to each) leave the format open, and which is taken is not specified; the source takes the first word, the mutant the last. |
| `Version_Agrees` | `A, B : Info_Bits := 0;` | `0` to `1` | Changes nothing: eighteen bits are pushed in after it, and `Info_Bits` keeps eighteen. |
| `Read_Codewords` | `V : RS.Element := 0;`, `V := 0;` after a codeword | `0` to `1`; the second taken out | Changes nothing: eight doublings push the old bits out of `V` (`RS.Element` is mod 256) before it is stored. |
| `Read_Codewords` | `Words := [others => 0];` | `0` to `1` | Changes nothing: `Words (1 .. Total)` are all set below, and only they are read. |
| `Read_Codewords` | `for Pair in 0 .. (S - 1) / 2 - 1 loop` | `1` to `0` | Changes nothing: the side is odd. |
| `Read_Codewords` | `if Right <= 6 then` | `6` to `7` | Changes nothing: `Right` is even. |
| `Read_Codewords` | `OK := Count = Total and then not Over;` | `and then` to `or else`; `=` to `<=` or `>=` | Changes nothing: the modules of the data of every version are `Total` codewords and fewer than eight bits more (the tests read every version), so `Count = Total` and `not Over` both hold. |
| `Decode` | `return;` where `Read_Codewords` is not OK | taken out | Not reached: `Read_Codewords` is always OK, as above. |
| `Correct_Blocks` | `and then N_Data <= Max_Data` (postcondition) | taken out; to `True` | Changes nothing: a postcondition is not run, and the proof of `Decode` does not need this one. |
| `Correct_Blocks` | `Data := [others => 0];` | `0` to `1` | Changes nothing: `Data (1 .. N_Data)` is all set, and only it is read. |
| `Correct_Blocks` | `if D + Info.Check * NB /= Total or else D > Max_Data then` | `/=` to `<` or `>` | Changes nothing: for the tables of the symbology the sum is `Total` (the tests read every version and level), so neither holds. |
| `Correct_Blocks` | `if P > Total then` (the codeword that a long block has more) | `>` to `>=` | Not reached: that codeword is one of the `D` of the message, all before the check codewords. |
| `Correct_Blocks` | `Corrected := 0;` where a block cannot be corrected | taken out | Changes nothing: `Decode` sets `Corrected` to 0 where `Correct_Blocks` fails. |
| `Correct_Blocks` | `if Offset + N_Own > D then`, and `Corrected := 0;` under it | `+` to `-`; taken out | Not reached: the codewords of the message of the blocks up to this one are among the `D` of them. |
| `To_Text` | `Lowest`: `1`, `7`, `31`, `32767` | `1` to `0`, the others one more | Not reached: `Get` takes no count of 1, 3, 5 or 15 bits. |
| `To_Text`, `Alphanumeric` | `Percent : Boolean := False;`, `Percent := False;` at the end of `Alphanumeric` | `False` to `True` | Changes nothing: `Percent` is read only within `Alphanumeric`, which sets it to `False` first. |
| `To_Text` | `Valid`: `Data'First = 1 and then N = Data'Last and then N_Bits = 8 * N ... and then Text'First = 1 ...` | `Data'First = 1`, `Text'First = 1` to `<=`; `N = Data'Last`, `N_Bits = 8 * N` to `<=` or `>=` | Changes nothing: `Data` and `Text` are indexed from `Positive`, and `N` and `N_Bits` are constants declared as `Data'Last` and `8 * N`. |
| `Get` | `V : Value_16 := 0;` | `0` to `1` | Changes nothing: the mask `Lowest (Count)` takes the higher bit off. |
| `Get` | `Value := 0;` where fewer bits are left | `0` to `1` | Changes nothing: `Good` no longer holds, and the text is not the result. |
| `Get` | `Valid and then Value <= Natural (Lowest (Count))` (postcondition) | `Valid` taken out; `and then` to `or else` | Proof not finished: the proof of `Numeric` alone fails with either ("cannot prove Valid"); that of the whole unit, with so many goals that fail, takes longer than its time. |
| `Put_Digits` | `Count <= 3 and then Value <= 999` (precondition) | `3` to `4`; `999` to `1000` | Changes nothing: the callers give at most three digits and 999, and the body is as safe with one more. |
| `Numeric` | `elsif Good and then Count mod 3 = 1 then` | `=` to `>=` | Changes nothing: the remainder 2 is taken by the branch before. |
| `Numeric`, `Alphanumeric` | `elsif Good then` (three) | `Good` to `True` | Changes nothing: where `Good` does not hold, the text is not the result. |
| `To_Text` | `for Step in 1 .. 2 * N loop` | `1` to `0`; `2` to `3` | Changes nothing: every segment takes four bits at least, so the loop leaves before its last step either way. |

## `AMV.Kernels.Code_Reader.QR_Code.Finder`

Many of the mutants that only a picture of a certain kind would tell
apart were looked for with a search: random symbols drawn in perspective
(their corners rounded to half a pixel, some of them with modules changed
around the alignment pattern), each read by the finder and by the finder
with the mutant, linked side by side. The entries give how many symbols
such a search drew. The new tests of the finder patterns and of the
sampling came from hits of the same search.

| Subprogram | Code | Change | Why it survives |
|---|---|---|---|
| (package) | `subtype Run_Length is Natural range 0 .. 2 ** 28;` | `28` to `29` | Not reached: a run is at most `DA.Max_Side` (2 ** 26) pixels. |
| `Alike` | `T in 0 .. 2 ** 32 and then Other in 0 .. 2 ** 32` (precondition) | the first `0` to `1`; a `2` to `3`; a `32` to `33` | Changes nothing: `T`, the five runs together, is never 0 (the middle run has its pixel), and the body is as safe with the wider bounds. |
| `Walk` | `DA.Valid_Map (Map) and then X <= Map'Last (2) and then Y <= Map'Last (1)` (precondition) | `DA.Valid_Map (Map)` taken out; `and then` to `or else` | Changes nothing at run time: the callers meet the whole. Proof not finished; with `DA.Valid_Map (Map)` taken out, the proof of `Walk` alone fails. |
| `Walk` | `A <= DA.Max_Side + 1 and then B <= DA.Max_Side + 1 and then C <= DA.Max_Side + 1` (postcondition) | each `+` to `-` | A postcondition is not run. Proof not finished; with a bound one lower (each `1` to `0`) the proof fails at the postcondition, so with one two lower it would too. |
| `Cross_Check` | `DA.Valid_Map (Map) and then ...` (precondition) | `and then` to `or else` | Changes nothing at run time: the callers meet the whole. Proof not finished. |
| `Cross_Check` | `Twice <= 2 ** 28 and then Sum in 0 .. 2 ** 29 and then (if OK then ...)` (postcondition) | `0` to `1`; `29` to `30`; `Twice <= 2 ** 28` to `True` or `<`; `if OK` to `if True` | Changes nothing: a postcondition is not run, and the proof passes with each (`Sum` is never 0, the middle run has its pixel; where `OK` does not hold, `Place` and `Twice` are 0 and meet the bounds too). |
| `Cross_Check` | the same | `in` to `not in`; `and then` to `or else` | A postcondition is not run. Proof not finished. |
| `Cross_Check` | `Place := 0;`, `Twice := 0;` | `0` to `1` | Changes nothing: `Place` and `Twice` are read only where `OK` holds. |
| `Cross_Check` | `and then First >= 0` | `0` to `1`; `>=` to `>` | Changes nothing: two runs come before the middle one, so `First` is 2 or more. |
| `Cross_Check` | `and then First + (A1 + A2) / 2 <= Last` | `<=` to `<` | Changes nothing: two runs come after the middle one, so its middle is before `Last`. |
| `Slanted` | `DA.Valid_Map (Map) and then X <= ... and then Width in 0 .. 2 ** 32` (precondition) | the second line taken out; `and then` to `or else` | Changes nothing at run time: the callers meet the whole. Proof not finished; with the second line taken out, the proof of `Slanted` alone fails. |
| `Slanted` | `Width in 0 .. 2 ** 32` | `2` to `3`; `32` to `33` | Changes nothing: the body is as safe with the wider bound. |
| `Mean` | `Seen <= Max_Seen` (precondition) | `<=` to `<` | Changes nothing: the callers meet the stronger one too (the proof passes). |
| `Mean` | `N.Mul_Within (Old, Count, VW.Limit, 2.0 ** 20)` | `20` to `21` | Not reached: `Count` is at most `Max_Seen` (2 ** 20). |
| `Purge` | `Patterns'First = 1` (precondition) | `=` to `<=` | Changes nothing: `Pattern_Array` is indexed from `Positive`. |
| `Add` | `and then (Apart <= 1.0 or else Apart <= P.Module)` | `1.0` to `0.0`; either relation to `True`; the first `<=` to `<` or `=`; the second `<=` to `<` | Not pinned: modules about a pixel wide, or narrower, found again at a middle about a pixel or a module apart; a search over 20 000 symbols found none on which it acts. |
| `Add` | `if Count < Patterns'Length then` | `<` to `/=` | Changes nothing: `Count` is never above `Patterns'Length`. |
| (package) | `Max_Reach : constant := 2 ** 12;` | `2` to `3`; `12` to `13` | Not reached at run time (`Reach` is at most 4002). Proof not finished; the proof of `Rows_Of` alone fails with either. |
| `Dark_Beside` | `DA.Valid_Map (Map)` (precondition) | taken out | Changes nothing: the callers meet it, and the proof of the body passes without it. |
| `Dark_Beside` | `DX /= 0` (precondition) | to `True` | Changes nothing: the callers give -1 and 1, and the proof of the body passes without it. |
| `Dark_Beside` | `Dark_Beside'Result <= Reach and then (if DX = 1 then ... <= Map'Last (2) - X else ... <= X)` (postcondition) | the first to `True` | Changes nothing: a postcondition is not run, and the proof of the callers passes without it. |
| `Dark_Beside` | the same | the second taken out; `1` to `0`; `=` to `/=`; `-` to `+`; `and then` to `or else` | A postcondition is not run. Proof not finished; with the second taken out, the proof of `Settle` alone fails, and with `1` to `0`, that of `Dark_Beside` alone. |
| `Weighted` | `Twice <= 2 ** 28` (precondition) | `<=` to `<` | Changes nothing: the callers meet the stronger one too (the proof passes). |
| `Weighted` | `Weighted'Result in 0 .. 2 ** 40` (postcondition) | `40` to `41` | A postcondition is not run. Proof not finished; with `40` to `41`, the proof of `Rows_Of` alone fails. |
| `Rows_Of` | `Area in 0 .. 2 ** 24 and then Sum_X in 0 .. 2 ** 52 and then Sum_Y in 0 .. 2 ** 52` (postcondition) | `2` to `3`; `24` to `25`; `52` to `53` | Changes nothing: a postcondition is not run, and the callers need no lower bounds (the proof passes). |
| `Rows_Of` | the same | each `0` to `1`; each `in` to `not in`; each `**` to `*` | A postcondition is not run. Proof not finished; with `0` to `1` for any of the three, the proof of `Rows_Of` alone fails at that postcondition. |
| `Rows_Of` | the loop invariant | taken out; a conjunct taken out | `not OK` taken out: changes nothing, the proof passes without it. The others: proof not finished; the proof of `Rows_Of` alone fails without the invariant, and without any one of its conjuncts on `Area`, `Sum_X` and `Sum_Y`. |
| `Settle` | `if P.Module > 1000.0` | to `False`; `>` to `>=` | Not pinned: modules 1000 pixels wide or wider, a pattern on a map of more than 7000 pixels a side, too large for a test. |
| `Settle` | `Reach := 2 + VW.Floor_Index (4.0 * P.Module, 4000);` | `4000` to `4001` | Not reached: `P.Module` is at most 1000 there. |
| `Settle` | `if OK_1 and then OK_2 and then A1 + A2 > 0 then` | `0` to `1` | Not pinned: it acts only for a middle of one pixel, where the rows and the columns put the centre already; a search over 20 000 symbols found none on which it acts. |
| `Settle` | the same | `>` to `/=` | Changes nothing: the areas are not negative (the postcondition of `Rows_Of`). |
| `Find_Patterns` | `for Y in 0 .. Map'Last (1) loop` | `0` to `1` | Changes nothing: row 0 is the middle row of no pattern, for the check down the column needs two runs above the middle one. |
| `Find_Patterns` | `if not OK and then Row < Map'Last (1) and then Map (Row + 1, X) /= DA.Light`, and the same with `Row > 0` and `Row - 1` | `<` to `/=`; `0` to `1`; either `1` of `Row + 1` and `Row - 1` to `0`; a pixel's relation to `True` | Changes nothing: `Row` is never beyond `Map'Last (1)`, and two runs lie above the middle one, so `Row` is 2 or more; where the pixel beside is light, the middle run of the column has one pixel or two, the row scanned is the middle row or the one after it, and the check along it always holds (`OK`), so neither branch is taken; `Map (Row, X)` is dark. |
| `Find_Patterns` | `Dark := False;` (at the start of a row) | `False` to `True` | Changes nothing: a row that begins light has one more `Check` at its start, with no runs, which `In_Proportion` turns away. |
| `Find_Patterns` | the loop invariant of the columns | taken out; `Total (Runs) <= Int64 (X)` taken out | Proof not finished; with it or `Total (Runs) <= Int64 (X)` taken out, the proof of `Find_Patterns` alone fails. |
| `Find_Patterns` | `Purge (Patterns, Count, 2.0 ** 40);` | `40` to `41` | Not reached: both are beyond every row. |
| `Find_Patterns` | `pragma Loop_Invariant (Count <= Patterns'Length);` (the loop of `Settle`) | taken out | Changes nothing: `Count` does not change in that loop. |
| `Half_Way` | `Length := 0.0;` | `0.0` to `1.0` | Changes nothing: `Length` is read only where `OK` holds. |
| `Module_Along` | `Width in 0.0 .. 2.0 ** 18` (postcondition) | `18` to `19` | Changes nothing: a postcondition is not run, and the callers need no lower bound (the proof passes). |
| `Module_Along` | `Width := (if OK then (Ahead + Back) / 7.0 else 0.0);` | `0.0` to `1.0`; `OK` to `True` | Changes nothing: `Width` is read only where `OK` holds. |
| `Arm` | `Modules in 0.0 .. 2.0 ** 32` (postcondition) | `32` to `33` | Changes nothing: a postcondition is not run, and the callers need no lower bound (the proof passes). |
| `Arm` | the same | `in` to `not in` | A postcondition is not run. Proof not finished. |
| `Arm` | `Modules := 0.0;` | `0.0` to `1.0` | Changes nothing: `Modules` is read only where `OK` holds. |
| `Arm` | `elsif OK_2 then` | to `True` | Changes nothing: where neither width is found, `W2` is 0.0 (`Module_Along`), below `Min_Module`, and `OK` stays False. |
| `Place` | `if D1 < Min_Arm or else D2 < Min_Arm` | `or else` to `and then` | Not pinned: one arm shorter than `Min_Arm` and the other not, on a symbol that is read all the same; a search over 20 000 symbols found none. |
| `Place` | `or else abs Dot > 0.5 * N.Mul_Within (D1, D2, VW.Far, VW.Far)` | `>` to `>=` | Not pinned: arms exactly 60 degrees apart; the same search found none. The proof of the mutant passed in one run of the workflow and failed in the next (a range check in `Place` not proved), so it is listed here. |
| `Place` | `or else Turn = 0.0`, `if Turn > 0.0 then` | `0.0` to `1.0`; `>` to `>=` | Changes nothing: `Turn` is 86.6 or more, or -86.6 or less, there (arms of 10 pixels or more, 60 degrees apart or more). |
| `Share` | `Steps in -2 ** 12 .. 2 ** 12` (precondition) | a `2` to `3`; a `12` to `13` | Changes nothing: the body is as safe with the wider bounds. |
| `Awry` | `Share (Home + P + Fine * I, Size)`, `Share (Home + Q + Fine * J, Size)` | the `+` before `Fine` to `-` | Changes nothing: `I` and `J` run over -2 .. 2 and the alignment pattern is the same mirrored, so the same 25 modules are counted, in another order; the count stops at `Allow + 1` in either. |
| `Patterns_Fit` | `P : constant Natural := (if Which = 1 then Arm else 0);` | `1` to `0` | Changes nothing: the three finder patterns are looked at in another order, and `Amiss` counts them all. |
| `Patterns_Fit` | `Share (P + Fine * K, Size)`, `Share (Q + Fine * K, Size)` | `+` to `-` | Changes nothing: `K` runs over -3 .. 3 and a finder pattern is the same mirrored, so the same modules are counted. |
| `Patterns_Fit` | the inner loop invariant | taken out | Changes nothing: an invariant is not run, and the proof passes without it. |
| `Timed` | `for K in 0 .. 2 * Due + 1 loop` | `0` to `1` | Not pinned: a timing pattern whose first module reads light, where the source counts one change more; the count is accepted within a slack of 2 or more, and no test has a symbol on which that one change decides. |
| `Find_Alignment` | `Best_P : ... := 0;`, `Best_Q : ... := 0;` | `0` to `1` | Changes nothing: they are read only where a place was found, which sets them. |
| `Find_Alignment` | `Least : Natural := Natural'Last;` | `'Last` to `'First` | Not pinned: the first places looked at are allowed fewer modules amiss; a search over 3 000 symbols with modules changed around the alignment pattern found none on which it acts. |
| `Find_Alignment` | `U := 0.0;`, `V := 0.0;` | `0.0` to `1.0` | Changes nothing: `U` and `V` are read only where `Found` holds. |
| `Find_Alignment` | `for Round in 1 .. 2 loop` | `1` to `0` | Changes nothing: the place taken is the one with the fewest modules amiss, of those the nearest to the expected one, and of those the first looked at; a round 0 looks at the expected place alone, which no other place is as near as. |
| `Find_Alignment` | the loop invariants of the mean | the outer one taken out; the inner one taken out | The outer one: changes nothing, the proof passes without it. The inner one: proof not finished; without it, the proof of `Find_Alignment` alone fails. |
| `Tilt` | `if abs Den < 1.0E-9 then` | `<` to `<=` | Not pinned: a determinant of exactly 1.0E-9; a search over 4 000 symbols found none. |
| `Point` | `abs X <= VW.Limit and then abs Y <= VW.Limit` | either `<=` to `<` | Not pinned: a point mapped exactly 2 ** 28 pixels from an axis. |
| `Sample` | `Grid := [others => [others => False]];` | `False` to `True` | Changes nothing: the modules beyond `Side (Version)` are not part of the result, and the others are all set below. |
| `Sample` | `if not OK then return; end if;` | the condition to `False`; `return` taken out | Changes nothing: where neither mapping fits, the rest fills the grid and the corners, but `OK` stays False (`Point` only ever sets it to False), and the callers read nothing else of a sample that is not OK. |
| `Sample` | `if Found then Point (...)` (two) | to `True` | Changes nothing: `Point` only ever sets its last parameter to False, so `Found` stays False, and `Q` is read only where it holds. |

## `AMV.Kernels.Code_Reader`

The changed lines: the symbols of the passes, the reading of QR Code
symbols and their places in the results.

| Subprogram | Code | Change | Why it survives |
|---|---|---|---|
| `Same_Text` | `Pool'First = 1 and then Text'First = 1 and then Length <= Text'Last` (precondition) | a relation to `False`; `=` to `/=`; `1` to `0`; `'First` to `'Last` and back; `<=` to `<` or `=` | Not pinned: `Same_Text` is called only for a symbol read a second time (`Add_Symbol`, below). Proof not finished. |
| `Same_Text` | the same | `Pool'First = 1`, `Text'First = 1` to `<=` | Changes nothing: `Text_Pool` is indexed from `Positive`. |
| `Add_Symbol` | `Text'First = 1 and then Length <= Text'Last and then Length <= Max_Matrix_Text_Length` (precondition) | a conjunct taken out; `and then` to `or else`; a relation to `True`; `Text'First = 1` to `<=` or `>=` | Changes nothing: every caller meets the stronger one. Proof not finished. |
| `Add_Symbol` | `... and then Symbols_OK (Symbols, Count, Used) and then Pool_OK (Pool, Used)` (precondition) | the last `and then` to `or else` | Changes nothing at run time: every caller meets the whole. Not proved in the workflow, whose run counted it as detected by the timing of `Test_Shape_Match` (above); the proof of `Add_Symbol` alone fails (`Count <= Room` in the postcondition, the indices of the text and the pool). |
| `Add_Symbol` | `if Symbols (I).Kind = Kind and then Symbols (I).Length = Length` | the whole or a relation to `False`; `=` to `/=`, `<=` or `>=`; `and then` to `or else` | Not pinned: a symbol read a second time, from other finder patterns or from another dark area; no test image gives one (`Find_QR_Symbols` does not try the patterns of a symbol again). Some: proof not finished. |
| (package) | `Max_Partners : constant := 32;` | `32` to `33` | Not pinned: more than 30 patterns as wide nearer to a corner than its two others, none of which make a symbol with it. |
| `Read_Triple` | `Tried and then Length in 1 .. QR.Max_Text_Length` (postcondition, where `Success`) | `Length in 1 .. QR.Max_Text_Length` taken out | Changes nothing: a postcondition is not run, and the proof of `Find_QR_Symbols` passes without it. |
| `Read_Triple` | the three `pragma Loop_Invariant (Tried and then not Success and then Length = 0);` | taken out; a conjunct taken out | Changes nothing: an invariant is not run, and the proof passes without it: the loops return as soon as a text is read, and set `Success` and `Length` back before the next step. |
| `Read_Triple` | `Version := Symbol.Version + Step;` | `+` to `-` | Changes nothing: the same versions in another order (`Version_Steps` is symmetric), and a symbol is read with its own version only. |
| `Read_Triple` | `if OK then` | `OK` to `True` | Changes nothing: where `Sample` is not OK the grid is all light; it has no format information, and `Decode` fails at once. |
| `Read_Triple` | `Length := 0;` after a reading without a text | taken out | Changes nothing: `Length` is 0 there already (`Decode` gives 0 where it fails, and the text read was empty otherwise). |
| `Find_QR_Symbols` | `Ways : Way_List := [others => 0.0];` | `0.0` to `1.0` | Changes nothing: only `Ways (1 .. Nearest)` is read, and it is set before. |
| `Find_QR_Symbols` | `if not Taken (I) then` | to `True` | Not pinned: a corner already of a symbol, tried again with the patterns not of one; no test image gives a symbol from it. |
| `Find_QR_Symbols` | `if J /= I and then not Taken (J) and then QF.Akin (...)` | `J /= I` to `True`; either `and then` to `or else`; the whole to `True` | Not pinned: the corner itself, patterns already of a symbol and patterns of other widths among the nearest; no test image gives another result with them. The whole to `True`: proof not finished. |
| `Find_QR_Symbols` | `if Nearest < Max_Partners or else Way < Ways (Max_Partners)` | the whole to `True`; either `<` to `<=`; the second `<` to `/=` | Not pinned: more than 32 patterns as wide around a corner (see `Max_Partners`). |
| `Find_QR_Symbols` | `while Slot > 1 and then Ways (Slot - 1) > Way loop` and `Ways (Slot) := Ways (Slot - 1);` | `>` to `>=`; the statement taken out; `1` to `0` | Not pinned: patterns as far from the corner, or the nearest in another order; no test image gives another result with them. |
| `Find_QR_Symbols` | `pragma Loop_Invariant (Slot in 2 .. Nearest);`, `pragma Loop_Variant (Decreases => Slot);` | taken out | Changes nothing: neither is run, and the proof passes without them (the condition of the loop bounds `Slot`). |
| `Find_QR_Symbols` | the invariants of the loops `Pairs` and `for A` (`Outcome = Done and then Count <= Room and then Tries < Max_Tries and then ...`) | a conjunct taken out | Changes nothing: an invariant is not run, and the proof passes without any one of these conjuncts. |
| `Find_QR_Symbols` | `for A in 1 .. B - 1 loop` | `1` to `0` | Changes nothing: a pair of one pattern twice is no symbol to `Place` (an angle of 0). |
| `Find_QR_Symbols` | `Taken (I) := True;`, `Taken (Near (A)) := True;`, `Taken (Near (B)) := True;` | taken out; `True` to `False` | Not pinned: the patterns of a symbol read, tried again with other corners; `Add_Symbol` does not add the symbol twice, and no test image gives another result with them. |
| `Find_Symbols` | the invariants of the loops over the rows and the columns of the dark areas (`Map /= null and then ...`, the bounds of `Map`, `DA.Extents_Fit (...)`) | taken out; a conjunct taken out | Changes nothing: an invariant is not run, and the proof passes without it: the loops do not change these variables, and gnatprove keeps what a loop does not change. |
| `Find_Symbols` | `for Y in 0 .. H - 1 loop`, `for X in 0 .. W - 1 loop` (the dark areas) | `0` to `1` | Not pinned: an area whose outline is not reached from another row or column; a symbol at the edge of the map is read either way. |
| `Make_Matrix_Item` | `Valid_Item (Item) and then ...` (postcondition) | `and then` to `or else`; `Is_Matrix (Item.Symbology)` taken out | Changes nothing: a postcondition is not run. Taken out, the proof of the callers passes without it; to `or else`, proof not finished. |

## `AMV.Kernels.Code_Reader.Views`

| Subprogram | Code | Change | Why it survives |
|---|---|---|---|
| `Quotient` | `(if (X < 0.0) = (Y < 0.0) then Q else -Q)` | `Y < 0.0` to `Y <= 0.0` | Changes nothing: `Y` is never 0.0 (the precondition). |
| `Project` | `Ahead := W > 1.0E-6;` | `>` to `>=`; `1.0E-6` to `0.0` | Not pinned: a W of 1.0E-6 exactly, or above 0.0 and at most 1.0E-6 at a point that the mapping still puts within 2 ** 28 pixels of the axes; no map was found. |
| `Project` | `X := 0.0;`, `Y := 0.0;` | `0.0` to `1.0` | Changes nothing: `X` and `Y` are read only where `Ahead` holds. |

## `AMV.Kernels.Code_Reader.Data_Matrix.Finder`

No changed line has a survivor.

## `AMV.Kernels.Shape_Match`

The changed lines: the postcondition of `Clear_Model`, whose conjuncts
change places so that `'Old` is evaluated whenever the postcondition is.

| Subprogram | Code | Change | Why it survives |
|---|---|---|---|
| `Clear_Model` | `Pattern.Params = Pattern.Params'Old and then not Pattern.Trained` (postcondition) | the first conjunct taken out | Changes nothing: the body meets the weaker postcondition too, and the callers need only `not Pattern.Trained` (the proof passes without the first). |

## `AMV.Kernels.Shape_Match.Training`

The changed lines: the invariants of the loops of `Extract_Ignored`,
without the conjunct that the type of `Ignored_Count` makes true.

| Subprogram | Code | Change | Why it survives |
|---|---|---|---|
| `Extract_Ignored` | `pragma Loop_Invariant (Model.Count = Model.Count'Loop_Entry and then Model.Spacing = ... and then Model.Features = ...)` (the loop over the rows of cells) | taken out; the conjunct on `Count` or on `Features` taken out | Changes nothing: an invariant is not run, and the proof passes without them; the loop assigns none of these components. With the conjunct on `Spacing` taken out, the proof fails. |

## `AMV.Kernels.Sobel_Edge`

The changed lines: the postcondition of `Visit`, now of the level
`Static`, and an assertion in `Execute`.

| Subprogram | Code | Change | Why it survives |
|---|---|---|---|
| `Visit` | `(Static => KI.Valid_Image (Target) and then KI.Size_Of (Target) = KI.Size_Of (Target)'Old and then Top <= Stack'Last + 1 and then (if Two_Valued (...)'Old then Two_Valued (...)))` (postcondition) | a conjunct taken out; an `and then` to `or else`; `=` to `/=`; `<=` to `<` or `=`; `'Last` to `'First`; `+` to `-`; `1` to `0`; the condition `Two_Valued (...)'Old` to `True` or `False` | A `Static` postcondition is run in no build. Proof not finished. Each fails a narrower proof: the changes that the body does not meet that of `Visit` alone, at the postcondition, and the others that of `Hysteresis` alone, at the loop invariants that need what they take away. |

## `AMV.Kernels.Blob.Extrema`

The changed lines are four `pragma Warnings (Off, ...)` in place of a
`pragma Unreferenced`: no mutant.
