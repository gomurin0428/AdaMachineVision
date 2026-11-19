#!/bin/sh
# mutant_shard.sh SHARD: writes adamutant-SHARD.toml, adamutant.toml with
# only the mutators of one part, so that the mutants of a large body can
# be run in parallel jobs (the workflow Mutation; make mutation
# MUTATION_CONFIG=adamutant-SHARD.toml). The parts:
#
#   logical     LogicalOperator, MembershipOperator
#   arithmetic  ArithmeticOperator, UnaryOperator, AttributeSwap
#   conditions  EqualityOperator, ConditionalExpression (together: the
#               first also replaces a whole relation by True or False,
#               which the second does too, and AdaMutant keeps one)
#   numbers     NumericLiteral
#   statements  StatementDeletion, BooleanLiteral, StringLiteral
#   conjuncts   ConjunctDeletion
#   assertions  AssertionDeletion
#   all         every mutator of AdaMutant's default set
#
# The time of a part goes mostly to the mutants that pass the tests and
# go to the proof of the unit (the contracts, and the changes that the
# tests do not see), each up to prove_timeout_ms: the parts keep these
# few enough for the time of a job. Together the first seven are
# AdaMutant's default set (all but LoopDirection) as of its version in
# .github/workflows/mutation.yml; a mutator that a later version adds is
# in "all" only until it is put here.
set -eu
case "${1:-}" in
  logical)
    list='"LogicalOperator", "MembershipOperator"' ;;
  arithmetic)
    list='"ArithmeticOperator", "UnaryOperator", "AttributeSwap"' ;;
  conditions)
    list='"EqualityOperator", "ConditionalExpression"' ;;
  numbers)
    list='"NumericLiteral"' ;;
  statements)
    list='"StatementDeletion", "BooleanLiteral", "StringLiteral"' ;;
  conjuncts)
    list='"ConjunctDeletion"' ;;
  assertions)
    list='"AssertionDeletion"' ;;
  all)
    list='' ;;
  *)
    echo "usage: $0 logical|arithmetic|conditions|numbers|statements|conjuncts|assertions|all" >&2
    exit 2 ;;
esac
out="adamutant-$1.toml"
# The setting goes in front of the first table ([thresholds]).
awk -v list="$list" '
  !done && /^\[/ {
    if (list != "") print "mutators = [" list "]\n"
    done = 1
  }
  { print }
' adamutant.toml > "$out"
echo "$out"
