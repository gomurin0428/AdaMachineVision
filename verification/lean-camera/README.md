# Independent Lean camera lifecycle specification

This package compares a separately authored Lean lifecycle model with the selected SPARK contracts on the current Ada sources. It covers only `Open`, `Start`, `Stop`, `Close`, `Is_Open`, and `Is_Streaming`; it makes no claim about `Grab`, frame construction, strings, `Global`/`Depends`, native code, GigE Vision protocol conformance, or physical-device interoperability.

## Reproduce

The local installer below is the official Elan installation command documented at <https://github.com/leanprover/elan#installation>:

```sh
curl https://elan.lean-lang.org/elan-init.sh -sSf | sh -s -- -y --no-modify-path --default-toolchain none
export PATH="$HOME/.elan/bin:$PATH"
elan toolchain install leanprover/lean4:v4.19.0
```

The `lean-toolchain` file pins Lean and Lake to `leanprover/lean4:v4.19.0`. The Lake project has no external package dependencies and uses only Lean core/Std; it does not require Mathlib.

From this directory:

```sh
python3 tools/extract_contracts.py --check
python3 -m unittest discover -s tests -v
lake build CameraLifecycle
python3 tools/check_axioms.py
```

The focused workflow is `.github/workflows/lean-camera.yml`. It regenerates and checks the tracked comparison module, runs the Python parser and source-mutation tests, builds the Lean proofs, and audits proof axioms.

## Source translation and proof boundary

`tools/extract_contracts.py` is a deliberately small Python-standard-library tokenizer, recursive-descent expression parser, type checker, and Lean emitter. It reads the three Ada specifications directly at the checked-out paths. It validates the selected enum domains, `T`/`N` aliases, formal names/types/modes, exact selected Pre/Post presence, allowed calls, and full consumption of every selected expression. Unsupported tokens, operators, calls, clauses, aliases, domains, or signatures fail extraction. `--check` compares the generated source text with `CameraLifecycle/Generated.lean`; a hash match alone is not accepted as agreement.

The only generated logic is `Generated.lean`. `Model.lean` is authored separately from the state-machine requirements. `Proofs.lean` proves equality of each helper and equivalence of each full allowed transition relation in both directions, including all selected preconditions and postconditions. The relation quantifies over arbitrary `Nat` handle identities. `0` represents null; handles are only compared, never dereferenced.

`Device_ID` is abstracted to a `selectorValid : Bool` input only at approved `Valid_Selector`, `Open_Status`, and `Open_State` arguments. The extractor validates `Valid_Selector`'s `String`-to-`Boolean` profile and rejects any aspects, but does not translate its string body; the string predicate itself is not claimed. `Camera_Result` is accepted only as exactly `Camera_Result (Result)`, once in each of `Open_Status`, `Start_Status`, and `Stop_Status`, and nowhere else, including preconditions. Generated call-path guards therefore account for the actual restricted call argument and prove that each call satisfies `Camera_Result`'s precondition excluding `Native_Not_Called`.

The trusted translation boundary is the tokenizer/parser/type checker and its explicit mapping of Ada short-circuit Boolean operators, equality/inequality, `not`, `if`/`elsif` (including Ada Boolean implicit-`True` else), enum `case` choices, approved helper calls, and unqualified `Old`/`Result` attributes into Lean. Any locally declared Ada operator function in the three input files fails extraction because the emitter relies on predefined operators; contract pragmas such as `Precondition` and `Postcondition` are likewise rejected rather than silently omitted (the existing non-contract `Validity_Checks` pragma is allowed). The handle model's `Nat` identity, null `0`, non-null test, and preservation-by-equality are abstraction assumptions; these theorems do not establish native `Address` semantics or actual pointer behavior. The independent Lean kernel checks the resulting theorems. This does not prove the Ada compiler, the parser implementation, execution of the procedures, `Global`/`Depends`, the native C/Aravis boundary, frame behavior, or protocol/hardware behavior. Negative integration tests edit temporary copies of the Ada contract sources, regenerate the comparison side, and require Lean agreement proofs to fail for semantic changes.
