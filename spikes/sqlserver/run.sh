#!/usr/bin/env bash
# Phase 0.4 spike: prove SQL Server in Docker on the Mac runs usp_RoundAmount.
#
# Usage: spikes/sqlserver/run.sh [cycles]        (default 1)
#        SQLSERVER_TAG=2022-CU28-ubuntu-22.04 spikes/sqlserver/run.sh 3
#
# Each cycle wipes the container and its data, starts SQL Server, loads the procedure and checks that
# ROUND(2.5) returns 3. Prints one RESULT line per cycle and a summary; exits non-zero on any failure.
set -euo pipefail
cd "$(dirname "$0")"

cycles="${1:-1}"
tag="${SQLSERVER_TAG:-2019-CU32-GDR8-ubuntu-20.04}"

if [[ ! -f .env ]]; then
  umask 077
  printf 'MSSQL_SA_PASSWORD=Sp1-%s\n' "$(openssl rand -hex 16)" > .env
  echo "Created .env with a random sa password (gitignored)."
fi

# Run sqlcmd inside the container: no sqlcmd install on the Mac, and the password never leaves the container env.
sql() {
  docker compose exec -T sqlserver bash -c '
    for p in /opt/mssql-tools18/bin/sqlcmd /opt/mssql-tools/bin/sqlcmd; do
      [ -x "$p" ] && exec "$p" -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -b -h -1 -W "$@"
    done
    echo "sqlcmd not found in the image" >&2; exit 1' sqlcmd "$@"
}

passed=0
for ((i = 1; i <= cycles; i++)); do
  docker compose down --volumes --remove-orphans >/dev/null 2>&1 || true

  start=$(date +%s)
  if ! docker compose up --detach --wait --wait-timeout 180 >/dev/null 2>&1; then
    echo "RESULT cycle=$i image=$tag status=FAIL reason=not-healthy"
    docker compose logs --tail 40 sqlserver || true
    continue
  fi
  ready_s=$(( $(date +%s) - start ))

  sql -Q "SET NOCOUNT ON; CREATE DATABASE Spike;"
  sql -d Spike -i /spike-database/usp_RoundAmount.sql
  rounded=$(sql -d Spike -Q "SET NOCOUNT ON; EXEC dbo.usp_RoundAmount @Amount = 2.5;" | tr -d '[:space:]')
  # SERVERPROPERTY returns sql_variant, which CONCAT will not convert implicitly.
  version=$(sql -Q "SET NOCOUNT ON; SELECT CONCAT(CAST(SERVERPROPERTY('ProductVersion') AS nvarchar(32)), '-', CAST(SERVERPROPERTY('ProductUpdateLevel') AS nvarchar(16)));" | tr -d '[:space:]')
  state=$(docker inspect --format '{{.State.Status}}/restarts={{.RestartCount}}' "$(docker compose ps -q sqlserver)")

  if awk -v v="$rounded" 'BEGIN { exit !(v == 3) }' && [[ "$state" == running/restarts=0 ]]; then
    status=PASS
    passed=$((passed + 1))
  else
    status=FAIL
  fi
  echo "RESULT cycle=$i image=$tag version=$version ready_s=$ready_s rounded=$rounded state=$state status=$status"
done

echo "RESULT summary image=$tag passed=$passed/$cycles"
echo "SQL Server is still running on 127.0.0.1:1433. Stop it with: docker compose -f spikes/sqlserver/compose.yaml down --volumes"
[[ "$passed" -eq "$cycles" ]]
