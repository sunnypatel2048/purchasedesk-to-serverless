#!/usr/bin/env bash
# Forgotten-teardown check: anything this project left running in AWS.
#
#   scripts/leftovers.sh        (or: make leftovers; CI runs it nightly with the read-only plan role)
#
# The rule: every resource is tagged Project=purchasedesk. Only the bootstrap layer (Layer=bootstrap) and the Windows
# image (Layer=image: the AMI and its snapshot) may exist between sessions; anything else tagged Project=purchasedesk
# is a leftover, including an instance left by a crashed image build (Layer=image-build). Filtering
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

# Tagged resources outside the persistent layers. The tagging API keeps deleted EC2 instances, volumes and network
# interfaces visible for an hour or more after they are gone (seen after the Phase 3.3 image build), so those three
# are counted separately below, from EC2 itself, which lists only what still exists.
tagged_not_bootstrap() {
  aws resourcegroupstaggingapi get-resources --region "$REGION" \
    --tag-filters "Key=Project,Values=$PROJECT" \
    --query "ResourceTagMappingList[?length(Tags[?Key=='Layer' && (Value=='bootstrap' || Value=='image')]) == \`0\`].ResourceARN" \
    --output text | tr '\t' '\n' | { grep -v -E ':(instance|volume|network-interface)/' || true; }
}

running_instances() {
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Project,Values=$PROJECT" Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down \
    --query 'Reservations[].Instances[].InstanceId' --output text
}

existing_volumes() {
  aws ec2 describe-volumes --region "$REGION" \
    --filters "Name=tag:Project,Values=$PROJECT" \
    --query 'Volumes[].VolumeId' --output text
}

existing_network_interfaces() {
  aws ec2 describe-network-interfaces --region "$REGION" \
    --filters "Name=tag:Project,Values=$PROJECT" \
    --query 'NetworkInterfaces[].NetworkInterfaceId' --output text
}

echo "Leftovers check for $PROJECT in $REGION (anything tagged Project=$PROJECT outside the bootstrap and image layers):"
check "tagged resources (not bootstrap or image)" tagged_not_bootstrap
check "EC2 instances (not terminated)" running_instances
check "EBS volumes" existing_volumes
check "network interfaces" existing_network_interfaces

echo "RESULT leftovers total=$total status=$([[ $total -eq 0 ]] && echo PASS || echo FAIL)"
[[ $total -eq 0 ]]
