#!/usr/bin/env bash
# Forgotten-teardown check: anything this project left running in AWS.
#
#   scripts/leftovers.sh        (or: make leftovers; CI runs it nightly with the read-only plan role)
#
# The rule: every resource is tagged Project=purchasedesk by the providers' default_tags. Only the bootstrap layer
# (Layer=bootstrap) may exist between sessions; anything else tagged Project=purchasedesk is a leftover. Filtering
# on this project's tag means another project in the same account can never show up here.
# Resource types that cannot carry tags (some CloudFront and network objects) get their own checks in Phase 4.
#
# Prints one line per check and a RESULT line; exits non-zero if anything is left or a check itself failed.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
PROJECT="purchasedesk"
export AWS_PAGER=""

total=0

# A failed AWS call must never read as "nothing left": it counts as a leftover and shows the error.
check() { # check <name> <command...>
  local name="$1" out count
  shift
  if ! out="$("$@" 2>&1)"; then
    echo "  $name: ERROR $out"
    total=$((total + 1))
    return
  fi
  # --output text prints "None" for an empty list; grep exits 1 when nothing is left.
  count="$(tr -s '[:space:]' '\n' <<<"$out" | { grep -v -x -e '' -e None || true; } | wc -l | tr -d ' ')"
  echo "  $name: $count"
  [[ "$count" -eq 0 ]] || tr -s '[:space:]' '\n' <<<"$out" | { grep -v -x -e '' -e None || true; } | sed 's/^/    /'
  total=$((total + count))
}

# Tagged resources outside the bootstrap layer. The tagging API keeps terminated EC2 instances visible for a while,
# so instances are counted separately, by state.
tagged_not_bootstrap() {
  aws resourcegroupstaggingapi get-resources --region "$REGION" \
    --tag-filters "Key=Project,Values=$PROJECT" \
    --query "ResourceTagMappingList[?length(Tags[?Key=='Layer' && Value=='bootstrap']) == \`0\`].ResourceARN" \
    --output text | tr '\t' '\n' | { grep -v ':instance/' || true; }
}

running_instances() {
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Project,Values=$PROJECT" Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down \
    --query 'Reservations[].Instances[].InstanceId' --output text
}

echo "Leftovers check for $PROJECT in $REGION (anything tagged Project=$PROJECT outside the bootstrap layer):"
check "tagged resources (not bootstrap)" tagged_not_bootstrap
check "EC2 instances (not terminated)" running_instances

echo "RESULT leftovers total=$total status=$([[ $total -eq 0 ]] && echo PASS || echo FAIL)"
[[ $total -eq 0 ]]
