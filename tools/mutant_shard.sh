#!/bin/sh
# mutant_shard.sh SHARD: writes adamutant-SHARD.toml, adamutant.toml with
# only the mutators of one part, so that the mutants of a large body can
# be run in parallel jobs (the workflow Mutation; make mutation
# MUTATION_CONFIG=adamutant-SHARD.toml). The parts:
#
#   operators  ArithmeticOperator, LogicalOperator, UnaryOperator,
#              MembershipOperator, AttributeSwap
#   conditions EqualityOperator, ConditionalExpression (together: the
#              first also replaces a whole relation by True or False,
#              which the second does too, and AdaMutant keeps one)
#   values     NumericLiteral, BooleanLiteral, StringLiteral,
#              StatementDeletion
#   contracts  ConjunctDeletion, AssertionDeletion (each goes to the
#              proof of its unit, the tests seeing no contract but a
#              precondition)
#   all        every mutator of AdaMutant's default set
#
# Together the first four are AdaMutant's default set (all but
# LoopDirection) as of its version in .github/workflows/mutation.yml; a
# mutator that a later version adds is in "all" only until it is put
# here.
set -eu
case "${1:-}" in
  operators)
    list='"ArithmeticOperator", "LogicalOperator", "UnaryOperator",'
    list="$list"' "MembershipOperator", "AttributeSwap"' ;;
  conditions)
    list='"EqualityOperator", "ConditionalExpression"' ;;
  values)
    list='"NumericLiteral", "BooleanLiteral", "StringLiteral",'
    list="$list"' "StatementDeletion"' ;;
  contracts)
    list='"ConjunctDeletion", "AssertionDeletion"' ;;
  all)
    list='' ;;
  *)
    echo "usage: $0 operators|conditions|values|contracts|all" >&2
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
