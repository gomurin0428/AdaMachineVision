#!/bin/sh
# The proof that AdaMutant runs for a mutant that the tests do not
# detect (adamutant.toml): gnatprove on the unit of the mutated body,
# with a steps limit and counterexamples, which AdaMutant uses to tell a
# confirmed failure from one of a contract that says too little. A body
# that is not SPARK has nothing to prove and passes.
#
# AdaMutant gives the mutated file in ADAMUTANT_MUTANT_FILE (a path from
# the root of the repository) and runs this script from the root of a
# copy of the repository. In its runs of the unchanged project the
# variable is empty: then the units in AMV_PROVE_UNITS (make mutation
# gives those of the bodies mutated) are proved, which fills the cache,
# or nothing.
#
# The cache of prover results: AMV_PROVE_CACHE, an absolute directory
# that the copies share and that outlives the run (make mutation gives
# one), or else the one of the copy that AdaMutant gives. Its keys are
# the goals with the prover switches, so the goals that a mutant does
# not change are answered from it. AMV_PROVE_JOBS: prover processes.
# AMV_PROVE_STEPS: the steps limit of the provers, 200000 by default
# (the checks of the code reader need 88627 at most): a goal that a
# mutant makes fail stops there, and with the cache a time limit alone
# would keep a prover four times as long. The time limit of amv.gpr is
# taken off (--timeout=0): on a loaded machine the provers reached it
# before their steps, and the proofs of mutants that change nothing
# failed; with steps alone the result is the same under any load.
set -eu
file="${ADAMUTANT_MUTANT_FILE:-}"
if [ -n "$file" ]; then
  units="$(basename "$file")"
else
  units="${AMV_PROVE_UNITS:-}"
  if [ -z "$units" ]; then
    exit 0
  fi
fi
cache="${AMV_PROVE_CACHE:-${ADAMUTANT_PROVE_CACHE:-}}"
args=""
for u in $units; do
  args="$args -u $u"
done
exec gnatprove -P amv.gpr -j"${AMV_PROVE_JOBS:-1}" \
  --steps="${AMV_PROVE_STEPS:-200000}" --timeout=0 --checks-as-errors=on \
  --report=fail --counterexamples=on \
  ${cache:+--memcached-server=file:$cache} $args
