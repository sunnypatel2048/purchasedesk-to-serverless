#!/usr/bin/env bash
# Apply .github/rulesets/main.json to the repository: branch protection as code.
# Creates the ruleset the first time and updates it in place afterwards.
#
#   scripts/apply-ruleset.sh       (or: make ruleset)
#
# What it enforces on main:
#   - changes arrive through pull requests (0 approvals: a one-person repo cannot approve its own pull requests;
#     the point is that every change runs CI)
#   - "infra passed", "legacy passed" and "legacy/ and golden/ are frozen" must succeed, reported by GitHub Actions
#     itself (integration 15368), so no other app can fake them
#   - no force pushes, no deleting main
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FILE="$ROOT/.github/rulesets/main.json"
REPO="$(gh repo view --json nameWithOwner --jq .nameWithOwner)"
NAME="$(jq -r .name "$FILE")"

id="$(gh api "repos/$REPO/rulesets" --jq ".[] | select(.name == \"$NAME\") | .id")"
if [[ -n "$id" ]]; then
  gh api -X PUT "repos/$REPO/rulesets/$id" --input "$FILE" --jq '"Updated ruleset \(.name) (id \(.id))"'
else
  gh api -X POST "repos/$REPO/rulesets" --input "$FILE" --jq '"Created ruleset \(.name) (id \(.id))"'
fi
