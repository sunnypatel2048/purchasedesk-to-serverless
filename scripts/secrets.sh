#!/usr/bin/env bash
# Creates the project's application secrets in Parameter Store, once (ADR-0007: never managed by Terraform, which
# would copy them into state).
#
#   scripts/secrets.sh        (or: make secrets; uses the current AWS credentials)
#
# Existing secrets are never changed or printed. Each is a SecureString under /purchasedesk/secrets/, tagged
# Layer=secrets so the leftovers check knows it is meant to persist between sessions.
#
#   /purchasedesk/secrets/legacy-api-key   the legacy API's shared X-Api-Key; written into Web.config at boot
#
# Phase 5.2 adds the DMS login here.
set -euo pipefail

REGION="${AWS_REGION:-us-east-1}"
export AWS_PAGER=""

tmp="$(mktemp)"
chmod 600 "$tmp"
trap 'rm -f "$tmp"' EXIT

create() { # create <name> <description>: a random value, created only if the parameter does not exist yet
  local name="$1" description="$2" existing
  existing="$(aws ssm describe-parameters --region "$REGION" \
    --parameter-filters "Key=Name,Option=Equals,Values=$name" --query 'length(Parameters)' --output text)"
  if [[ "$existing" != "0" ]]; then
    echo "RESULT secret $name status=exists (unchanged)"
    return
  fi
  # 32 random bytes, URL-safe base64. Passed through a private temporary file, never on a command line.
  openssl rand -base64 32 | tr '+/' '-_' | tr -d '=\n' > "$tmp"
  aws ssm put-parameter --region "$REGION" --name "$name" --description "$description" \
    --type SecureString --value "file://$tmp" \
    --tags Key=Project,Value=purchasedesk Key=Layer,Value=secrets Key=ManagedBy,Value=make-secrets > /dev/null
  : > "$tmp"
  echo "RESULT secret $name status=created"
}

create /purchasedesk/secrets/legacy-api-key "Legacy API shared key (X-Api-Key), written into Web.config at boot"
