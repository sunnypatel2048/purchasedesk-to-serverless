#!/usr/bin/env bash
# Waits for the legacy server's boot script to finish, prints its RESULT lines, and fails if it failed (ADR-0012).
# Terraform runs it after creating or changing the boot association, so `terraform apply` ends only when the server
# is ready. (The association's own wait_for_success reports success before the instance has even registered with
# Systems Manager, seen in Phase 4.2, so it cannot be the ready signal.)
#
#   scripts/wait-for-legacy-boot.sh <instance-id> <association-id> [timeout-seconds]
#
# Uses the credentials of whoever runs `terraform apply`; CI never applies.
set -euo pipefail

instance="$1"
association="$2"
timeout="${3:-1800}"
REGION="${AWS_REGION:-us-east-1}"
export AWS_PAGER=""

# The run to wait for is the association's current version on this instance. A new instance reports nothing until
# its first run; after a document change the previous version's Success is still reported until the new run ends.
version="$(aws ssm describe-association --region "$REGION" --association-id "$association" \
  --query 'AssociationDescription.AssociationVersion' --output text)"

start=$(date +%s)
last=""
while true; do
  elapsed=$(( $(date +%s) - start ))
  read -r status reported < <(aws ssm describe-instance-associations-status --region "$REGION" --instance-id "$instance" \
    --query "InstanceAssociationStatusInfos[?AssociationId=='$association'] | [0].[Status, AssociationVersion]" \
    --output text 2>/dev/null || echo "Unreachable -")

  if [[ "$reported" == "$version" && "$status" =~ ^(Success|Failed)$ ]]; then
    break
  fi
  if [[ "$status" != "$last" ]]; then
    echo "boot: ${status} (version ${reported}, waiting for ${version}) after ${elapsed}s"
    last="$status"
  fi
  if (( elapsed > timeout )); then
    echo "boot: no result after ${timeout}s (last status: ${status})" >&2
    exit 1
  fi
  sleep 15
done

# The boot script's output: each association run is a Run Command invocation on the instance. Selected by version,
# like the wait above (a Status filter returned an older run in Phase 4.2).
execution="$(aws ssm describe-association-executions --region "$REGION" --association-id "$association" \
  --query "AssociationExecutions[?AssociationVersion=='$version'] | [0].ExecutionId" --output text)"
command_id="$(aws ssm describe-association-execution-targets --region "$REGION" --association-id "$association" \
  --execution-id "$execution" --filters Key=ResourceId,Value="$instance" \
  --query 'AssociationExecutionTargets[0].OutputSource.OutputSourceId' --output text)"
aws ssm get-command-invocation --region "$REGION" --command-id "$command_id" --instance-id "$instance" \
  --query 'StandardOutputContent' --output text | grep '^RESULT' || echo "boot: no RESULT lines found in the output"

echo "boot: ${status} after $(( $(date +%s) - start ))s"
[[ "$status" == "Success" ]]
