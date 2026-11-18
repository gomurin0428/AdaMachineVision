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

The reasons are of three kinds:

* **Changes nothing**: no input gives another result. A value is read
  only where it was set again, a test is the same mirrored, a bound is
  one that is never reached.
* **Not reached**: the mutant changes a bound or a guard that no input of
  the pass reaches (a map of the pass is at most 2 ** 26 pixels a side,
  for example).
* **Not pinned**: an input would tell the mutant from the source, but none
  is in the tests: a search over millions of maps found none, or the
  input is too large to make in a test. The entry says what input would.

The workflow Mutation (`.github/workflows/mutation.yml`) runs AdaMutant
on the bodies that a pull request changes and keeps the report of each
as an artifact of its job. `make mutation MUTATE=src/<file>.adb` runs it
on a whole body here.

The lists below are those of the last run on each body.
