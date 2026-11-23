# Independent Lean camera specifications

This package compares separately authored Lean models with selected SPARK contracts on the current Ada sources. It covers the lifecycle operations `Open`, `Start`, `Stop`, `Close`, `Is_Open`, and `Is_Streaming`, plus the acquisition contract relations for `Grab` and `Build_Frame`. The models are authored separately from the generated Ada comparison modules.

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
python3 tools/extract_grab_contracts.py --check
python3 -m unittest discover -s tests -v
lake build CameraLifecycle
python3 tools/check_axioms.py
```

The focused workflow is `.github/workflows/lean-camera.yml`. It checks both generated comparison modules, runs the Python parser and source-mutation tests, builds the Lean proofs, and audits proof axioms. The Grab extractor reads the three Aravis Ada specifications plus `src/amv-kernels-images.ads` and `src/amv-kernels.ads`.

## Source translation and proof boundary

`tools/extract_contracts.py` is a deliberately small Python-standard-library tokenizer, recursive-descent expression parser, type checker, and Lean emitter. It reads the three Ada specifications directly at the checked-out paths. It validates the selected enum domains, `T`/`N` aliases, formal names/types/modes, exact selected Pre/Post presence, allowed calls, and full consumption of every selected expression. Unsupported tokens, operators, calls, clauses, aliases, domains, or signatures fail extraction. `--check` compares the generated source text with `CameraLifecycle/Generated.lean`; a hash match alone is not accepted as agreement.

For the lifecycle specification, the only generated logic is `CameraLifecycle/Generated.lean`. `CameraLifecycle/Model.lean` is authored separately from the state-machine requirements. `CameraLifecycle/Proofs.lean` proves equality of each helper and equivalence of each full allowed transition relation in both directions, including all selected preconditions and postconditions. The relation quantifies over arbitrary `Nat` handle identities. `0` represents null; handles are only compared, never dereferenced. The Grab comparison is generated separately in `CameraLifecycle/Grab/Generated.lean` and checked against the authored model and proofs under `CameraLifecycle/Grab/`.

`Device_ID` is abstracted to a `selectorValid : Bool` input only at approved `Valid_Selector`, `Open_Status`, and `Open_State` arguments. The extractor validates `Valid_Selector`'s `String`-to-`Boolean` profile and rejects any aspects, but does not translate its string body; the string predicate itself is not claimed. `Camera_Result` is accepted only as exactly `Camera_Result (Result)`, once in each of `Open_Status`, `Start_Status`, and `Stop_Status`, and nowhere else, including preconditions. Generated call-path guards therefore account for the actual restricted call argument and prove that each call satisfies `Camera_Result`'s precondition excluding `Native_Not_Called`.

The lifecycle trusted translation boundary is the tokenizer/parser/type checker and its explicit supported expression subset, including `Old`/`Result` attributes. The handle model's `Nat` identity, null `0`, non-null test, and preservation-by-equality are abstraction assumptions; these theorems do not establish native `Address` semantics or actual pointer behavior.

## Grab and frame-contract scope

`tools/extract_grab_contracts.py` is a separate, fail-closed Python-standard-library extractor for the actual `Grab` Pre/Post, `Build_Frame` Post, and the expression dependencies `Grab_Status`, `Pixel_At`, `Valid_Observation`, and the 8-bit `Valid_Image` overload. It validates the selected enum and record domains, aliases, helper/operation profiles and modes, array/access/image type declarations, integer ranges, relevant constants, overload set, and exact selected aspects. It translates every selected expression into `Grab/Generated.lean`; unsupported or trailing syntax, types, attributes, calls, profiles, or additional selected contract aspects fail extraction. The independent model is in `Grab/Model.lean`; `Grab/Proofs.lean` proves helper agreement and iff agreement for the complete bounded `Grab` and `Build_Frame` relations, including their respective pre/post constraints.

The model spells out all ten frame statuses and preserves source precedence: non-streaming or zero timeout, acquisition outcomes, buffer timeout/failure, payload and Mono8 format, positive dimensions, the strict `width * height > 2^31 - 1` limit, then byte/source length and pointer/bounds checks. Exactly `2^31 - 1` pixels is not classified as too large. `Grab` retains its handle/state precondition, valid-observation and acquisition-dispatch clauses, all nine canonical observation fields when acquisition is not called, success-to-out-of-memory status allowance, image dimensions, and every universal pixel equality. Non-success requires a null image. `Build_Frame` is modeled only with its own Post; it is not strengthened with Grab's precondition, dispatch, observation-validity, or canonical-output clauses.

Frame bytes and image/pixel pointers are explicit nullable options. Non-null byte arrays and matrices have explicit first/last bounds and arbitrary content functions with `UInt8` values; the model does not enumerate sample images or restrict pixel contents. The 8-bit image invariant includes both pointer null checks, positive dimensions, zero first row/column, and last bounds equal to dimension minus one. `Pixel_At` keeps its fallback guards and its actual row-major byte access `Y * Width + X + 1`; the success-pixel corollaries connect arbitrary valid output pixels to that byte content.

The bounded domains are explicit: `Int32` and `Int64` use their validated signed ranges; `Unsigned_32` and `Unsigned_64` use `0 .. 2^32-1` and `0 .. 2^64-1`; `Pixel`/`Grey_8` values are Lean `UInt8`; and `Natural`, `Positive`, and `Integer` use the supported GNAT target assumption that Standard `Integer` is 32-bit and `Natural` is `0 .. 2^31-1`. The byte-array and matrix bounds are represented independently, including nullable arrays. Before emission, the extractor type-checks selected expression trees and performs conservative interval and path-condition analysis for casts and signed/Standard-integer `+`, `-`, and `*` intermediates. It erases an integral conversion only when the input is proven to fit the target range on that evaluation path: for example, positive dimensions precede `Natural` casts, the maximum-pixel branch bounds the `Unsigned_64` product cast, and the strict byte-count guard bounds the row offset before its `Natural` conversion and `+ 1`. It preserves `and then`/`or else` evaluation paths and prior-false `elsif` conditions; eager `and`/`or` do not supply short-circuit range facts. Unproved conversions, overflow-capable intermediates, modular arithmetic, and wrapping unsigned conversions are rejected. This static range analysis is part of the trusted extractor, not a kernel-proved fact. These are mathematical contract-domain assumptions, not claims about unbounded Ada arithmetic.

The acquisition extractor's trusted boundary is its strict tokenizer, expression parser, profile/domain validator, and emitter for the selected comparisons, arithmetic, Boolean operators, membership, casts, record fields, array bounds/access, `if`/`elsif` (including the contract's implicit `True` else), approved helper calls, and nested `for all` ranges. It uses predefined operators only and rejects local operator overloads and contract pragmas rather than silently changing or omitting their meaning. The Lean theorems establish source-contract agreement over the stated bounded mathematical domains. They do **not** prove procedure bodies, allocation or pointer validity, array storage, absence of compiler/runtime errors, native `Address` or C/Aravis semantics, Aravis internals, GigE Vision protocol behavior, physical cameras, or total C-memory correctness. They make no `Global`/`Depends` agreement claim; the existing selector and opaque-handle abstractions remain unchanged. Temporary-source mutation tests regenerate from edited Ada and require semantic changes to fail in the Lean proof module, rather than relying on source hashes.
