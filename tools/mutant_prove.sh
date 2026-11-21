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
# mutant makes fail stops there. AMV_PROVE_TIMEOUT bounds each prover
# call in seconds (120 by default), preventing an unbounded solver call.
# A timeout is incomplete proof evidence, never a confirmed semantic defect.
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
  spark_unit=${u##*/}
  spark_unit=${spark_unit%.*}
  if [ -d build/obj/gnatprove ]; then
    rm -f "build/obj/gnatprove/$spark_unit.spark"
  fi
done
# The why3 sessions of earlier proofs in this copy (build/obj/gnatprove,
# the files why3session.xml and why3shapes). gnatwhy3 can answer a goal
# with the attempt that a session holds for a goal it pairs it with, a
# failed one included: after a proof whose provers failed, the proof of
# the unchanged Visit of Sobel_Edge reported ten checks unproved, and
# with the session files deleted all 27 proved in 5 s. Each proof starts
# without them; the cache answers the goals proved before.
if [ -d build/obj/gnatprove ]; then
  find build/obj/gnatprove \( -name 'why3session.xml*' -o -name 'why3shapes*' \) \
    -type f -delete
fi
set -- gnatprove -P amv.gpr -j"${AMV_PROVE_JOBS:-1}" \
  --steps="${AMV_PROVE_STEPS:-200000}" \
  --timeout="${AMV_PROVE_TIMEOUT:-120}" --checks-as-errors=on \
  --report=fail --counterexamples=on \
  ${cache:+--memcached-server=file:$cache} $args
evidence_dir="${AMV_PROVE_EVIDENCE_DIR:-}"
mutant_id="${ADAMUTANT_MUTANT_ID:-}"
if [ -n "$evidence_dir" ] && [ -n "$mutant_id" ] && \
   mkdir -p "$evidence_dir" 2>/dev/null; then
  log_file=$(mktemp "$evidence_dir/.gnatprove.XXXXXX" 2>/dev/null || true)
else
  log_file=""
fi
if [ -z "$log_file" ]; then
  exec "$@"
fi
started_ns=$(python3 -c 'import time; print(time.time_ns())')
if "$@" >"$log_file" 2>&1; then
  prove_status=0
else
  prove_status=$?
fi
cat "$log_file"
script_dir=$(CDPATH= cd "$(dirname "$0")" && pwd)
python3 "$script_dir/mutation_proof_gate.py" record \
  --evidence-dir "$evidence_dir" --mutant-id "$mutant_id" \
  --started-ns "$started_ns" --exit-code "$prove_status" \
  --spark-root build/obj/gnatprove --log "$log_file" --units "$units" ||
  echo "GNATprove evidence recording failed; the mutation gate will fail closed" >&2
rm -f "$log_file" || true
exit "$prove_status"
