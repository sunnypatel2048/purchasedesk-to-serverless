#!/usr/bin/env bash
# Phase 0.5 spike session. Uses whatever AWS credentials are active (AWS_PROFILE).
#
#   spikes/edge/session.sh up         terraform apply, timed, logged to logs/
#   spikes/edge/session.sh test       traffic split checks, one RESULT line each
#   spikes/edge/session.sh down       terraform destroy, timed, then the leftovers check
#   spikes/edge/session.sh leftovers  look for anything tagged Spike=0.5 that survived
set -euo pipefail
cd "$(dirname "$0")"

root="$(git rev-parse --show-toplevel)"
mkdir -p "$root/logs"
stamp="$(date +%Y%m%d-%H%M%S)"
export AWS_REGION=us-east-1 AWS_PAGER=""

# ---------------------------------------------------------------- up / down

up() {
  local log="$root/logs/spike-edge-up-$stamp.log" start
  terraform init -input=false -no-color >/dev/null
  start=$(date +%s)
  terraform apply -auto-approve -input=false -no-color 2>&1 | tee "$log"
  echo "RESULT up total_s=$(( $(date +%s) - start ))" | tee -a "$log"
  grep -E "(aws_cloudfront_vpc_origin|aws_cloudfront_distribution|aws_instance)\..*Creation complete" "$log" || true
}

down() {
  local log="$root/logs/spike-edge-down-$stamp.log" start
  start=$(date +%s)
  terraform destroy -auto-approve -input=false -no-color 2>&1 | tee "$log"
  echo "RESULT down total_s=$(( $(date +%s) - start ))" | tee -a "$log"
  grep -E "(aws_cloudfront_vpc_origin|aws_cloudfront_distribution|aws_subnet|aws_vpc)\..*Destruction complete" "$log" || true
  leftovers
}

# ---------------------------------------------------------------- traffic tests

domain="" kvs=""
load_outputs() {
  domain="$(terraform output -raw domain)"
  kvs="$(terraform output -raw kvs_arn)"
}

put_key() {
  local etag
  etag="$(aws cloudfront-keyvaluestore describe-key-value-store --kvs-arn "$kvs" --query ETag --output text)"
  aws cloudfront-keyvaluestore put-key --kvs-arn "$kvs" --key "$1" --value "$2" --if-match "$etag" >/dev/null
}

# Prints the X-Served-By value of one request, or "error".
side() {
  local s
  s="$(curl -s -D - -o /dev/null --max-time 10 "$@" "https://$domain/api/ping" | tr -d '\r' |
    awk -F': ' 'tolower($1) == "x-served-by" { print $2 }')"
  echo "${s:-error}"
}

# tally <count> <client-id prefix> -> "legacy=N new=N error=N"
tally() {
  local l=0 n=0 e=0 i s
  for ((i = 1; i <= $1; i++)); do
    s="$(side -H "X-Client-Id: $2-$i")"
    case "$s" in legacy) l=$((l + 1)) ;; new) n=$((n + 1)) ;; *) e=$((e + 1)) ;; esac
  done
  echo "legacy=$l new=$n error=$e"
}

# wait_for <description> <test command...>: polls every 2 s, prints seconds waited, fails after 180 s.
wait_for() {
  local what="$1" start
  shift
  start=$(date +%s)
  until "$@"; do
    if (( $(date +%s) - start > 180 )); then
      echo "RESULT wait what=$what status=FAIL reason=timeout-180s" >&2 # stdout is captured by the caller
      return 1
    fi
    sleep 2
  done
  echo $(( $(date +%s) - start ))
}

probes() { tally 20 probe; }
all_legacy() { [[ "$(probes)" == "legacy=20 new=0 error=0" ]]; }
some_new()   { [[ "$(probes)" != *"new=0 "* ]]; }
all_new()    { [[ "$(probes)" == "legacy=0 new=20 error=0" ]]; }
legacy_up()  { [[ "$(side)" == legacy ]]; }

failures=0
check() { # check <name> <pass?> <details>
  local status=PASS
  [[ "$2" == yes ]] || { status=FAIL; failures=$((failures + 1)); }
  echo "RESULT $1 $3 status=$status"
}

test_split() {
  load_outputs
  local r l n e s waited token

  echo "Waiting for the legacy instance to answer through CloudFront..."
  waited="$(wait_for legacy-ready legacy_up)"
  echo "RESULT legacy-ready waited_s=$waited"

  # 1. Weight 0: everything to legacy.
  put_key "weight:GET:/api/ping" 0
  r="$(tally 200 w0)"
  check weight-0 "$([[ "$r" == "legacy=200 new=0 error=0" ]] && echo yes)" "$r"

  # 2. Weight 50: time the change, then expect roughly half on each side.
  put_key "weight:GET:/api/ping" 50
  waited="$(wait_for weight-50 some_new)"
  echo "RESULT propagation to=50 waited_s=$waited"
  r="$(tally 200 w50)"
  read -r l n e <<<"$(echo "$r" | sed -E 's/[a-z]+=//g')"
  check weight-50 "$([[ $e -eq 0 && $n -ge 86 && $n -le 114 ]] && echo yes)" "$r expected_new=86..114"

  # 3. Stickiness: one client, twenty requests, one side.
  s="$(for i in $(seq 20); do side -H "X-Client-Id: sticky-client"; done | sort -u | tr '\n' ' ')"
  check sticky "$([[ "$(echo "$s" | wc -w | tr -d ' ')" == 1 && "$s" != *error* ]] && echo yes)" "sides=${s% }"

  # 4. Weight 100: everything to new.
  put_key "weight:GET:/api/ping" 100
  waited="$(wait_for weight-100 all_new)"
  echo "RESULT propagation to=100 waited_s=$waited"
  r="$(tally 200 w100)"
  check weight-100 "$([[ "$r" == "legacy=0 new=200 error=0" ]] && echo yes)" "$r"

  # 5. Override: with the token it forces a side; without it, the weight decides.
  token="$(openssl rand -hex 16)"
  put_key "override-token" "$token"
  put_key "weight:GET:/api/ping" 0
  waited="$(wait_for weight-0-again all_legacy)"
  echo "RESULT propagation to=0 waited_s=$waited"
  sleep 5 # the token was written just before the weight; give it the same head start
  s="$(side -H "X-Force-Origin: new" -H "X-Override-Token: $token")/$(side -H "X-Force-Origin: new" -H "X-Override-Token: wrong")"
  check override "$([[ "$s" == "new/legacy" ]] && echo yes)" "with_token/wrong_token=$s"

  echo "RESULT summary failed=$failures"
  [[ $failures -eq 0 ]]
}

# ---------------------------------------------------------------- leftovers

leftovers() {
  local total=0
  count() { # count <name> <command...>: prints and adds the number of resources found
    local out c
    # A failed call must not read as "nothing left": count it as a leftover and show the error.
    if ! out="$("${@:2}" 2>&1)"; then
      echo "  $1: ERROR $out"
      total=$((total + 1))
      return
    fi
    # --output text prints "None" when a CloudFront list is empty.
    # grep exits 1 when nothing is left, which pipefail would turn into a script failure.
    c="$(echo "$out" | tr -s '[:space:]' '\n' | { grep -v -x -e '' -e None || true; } | wc -l | tr -d ' ')"
    echo "  $1: $c"
    total=$((total + c))
  }
  echo "Leftovers check (tag Spike=0.5, names starting purchasedesk-spike):"
  count vpcs aws ec2 describe-vpcs --filters Name=tag:Spike,Values=0.5 --query 'Vpcs[].VpcId' --output text
  count instances aws ec2 describe-instances --filters Name=tag:Spike,Values=0.5 \
    Name=instance-state-name,Values=pending,running,stopping,stopped,shutting-down \
    --query 'Reservations[].Instances[].InstanceId' --output text
  count security-groups aws ec2 describe-security-groups --filters Name=tag:Spike,Values=0.5 --query 'SecurityGroups[].GroupId' --output text
  count distributions aws cloudfront list-distributions \
    --query "DistributionList.Items[?Comment=='purchasedesk-spike front door'].Id" --output text
  count vpc-origins aws cloudfront list-vpc-origins \
    --query "VpcOriginList.Items[?starts_with(Name, 'purchasedesk-spike')].Id" --output text
  count functions aws cloudfront list-functions \
    --query "FunctionList.Items[?starts_with(Name, 'purchasedesk-spike')].Name" --output text
  count key-value-stores aws cloudfront list-key-value-stores \
    --query "KeyValueStoreList.Items[?starts_with(Name, 'purchasedesk-spike')].Name" --output text
  count lambdas aws lambda list-functions --query "Functions[?starts_with(FunctionName, 'purchasedesk-spike')].FunctionName" --output text
  count http-apis aws apigatewayv2 get-apis --query "Items[?starts_with(Name, 'purchasedesk-spike')].ApiId" --output text
  count log-groups aws logs describe-log-groups --log-group-name-prefix /aws/lambda/purchasedesk-spike --query 'logGroups[].logGroupName' --output text
  count iam-roles aws iam list-roles --query "Roles[?starts_with(RoleName, 'purchasedesk-spike')].RoleName" --output text
  echo "RESULT leftovers total=$total status=$([[ $total -eq 0 ]] && echo PASS || echo FAIL)"
  [[ $total -eq 0 ]]
}

case "${1:-}" in
  up) up ;;
  test) test_split ;;
  down) down ;;
  leftovers) leftovers ;;
  *) echo "usage: $0 up|test|down|leftovers" >&2; exit 2 ;;
esac
