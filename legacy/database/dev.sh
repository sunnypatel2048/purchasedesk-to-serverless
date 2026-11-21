#!/usr/bin/env bash
# Local SQL Server for the legacy database.
#
#   legacy/database/dev.sh up       start SQL Server and load the scripts into an empty PurchaseDesk database
#   legacy/database/dev.sh reset    wipe everything and load again from scratch
#   legacy/database/dev.sh check    verify the schema; one RESULT line per check, non-zero exit on failure
#   legacy/database/dev.sh sql ...  run sqlcmd inside the container, e.g. dev.sh sql -Q "SELECT 1"
#   legacy/database/dev.sh down     stop and remove the container and its data
set -euo pipefail
cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  umask 077
  printf 'MSSQL_SA_PASSWORD=Pd1-%s\n' "$(openssl rand -hex 16)" > .env
  echo "Created .env with a random sa password (gitignored)."
fi

# sqlcmd inside the container: nothing to install on the Mac, and the password stays in the container env.
sql() {
  docker compose exec -T sqlserver bash -c \
    '/opt/mssql-tools18/bin/sqlcmd -S localhost -U sa -P "$MSSQL_SA_PASSWORD" -C -b "$@"' sqlcmd "$@"
}

# Runs a query and prints its single value, trimmed. Optional second argument: database (default master).
# Connecting with -d rather than USE keeps "Changed database context" out of the output.
scalar() {
  sql -d "${2:-master}" -h -1 -W -Q "SET NOCOUNT ON; $1" | tr -d '[:space:]'
}

load() {
  for f in [0-9][0-9]-*.sql; do
    echo "Loading $f"
    sql -i "/db/$f"
  done
}

up() {
  docker compose --progress quiet up --detach --wait --wait-timeout 180
  if [[ "$(scalar "SELECT CASE WHEN OBJECT_ID(N'PurchaseDesk.dbo.Suppliers') IS NULL THEN 0 ELSE 1 END;")" == 1 ]]; then
    echo "PurchaseDesk is already loaded. Use dev.sh reset to load it again from scratch."
  else
    load
  fi
  echo "SQL Server is running on 127.0.0.1:1433."
}

failures=0
result() { # result <name> <expected> <actual>
  local status=PASS
  [[ "$2" == "$3" ]] || { status=FAIL; failures=$((failures + 1)); }
  echo "RESULT $1 expected=$2 actual=$3 status=$status"
}

check() {
  result tables-with-primary-keys 4 "$(scalar "
    SELECT COUNT(*) FROM sys.tables t
    WHERE t.name IN ('Suppliers', 'PurchaseOrders', 'PurchaseOrderLines', 'AuditLog')
      AND EXISTS (SELECT 1 FROM sys.key_constraints k WHERE k.parent_object_id = t.object_id AND k.type = 'PK');" PurchaseDesk)"

  result collation SQL_Latin1_General_CP1_CI_AS "$(scalar "SELECT CONVERT(varchar(64), DATABASEPROPERTYEX('PurchaseDesk', 'Collation'));")"

  # 2627 = unique constraint violation. Rolled back either way.
  result supplier-code-case-insensitive 2627 "$(scalar "
    BEGIN TRANSACTION;
    DECLARE @r int = 0;
    INSERT dbo.Suppliers (Code, Name) VALUES ('ACME', N'Acme Ltd');
    BEGIN TRY INSERT dbo.Suppliers (Code, Name) VALUES ('acme', N'Acme lower'); END TRY
    BEGIN CATCH SET @r = ERROR_NUMBER(); END CATCH;
    ROLLBACK TRANSACTION;
    SELECT @r;" PurchaseDesk)"

  result rowversion-changes-on-update changed "$(scalar "
    BEGIN TRANSACTION;
    INSERT dbo.Suppliers (Code, Name) VALUES ('RV-CHECK', N'Rowversion check');
    INSERT dbo.PurchaseOrders (OrderNumber, SupplierId, CreatedBy)
      VALUES ('PO-CHECK-1', SCOPE_IDENTITY(), N'check');
    DECLARE @id int = SCOPE_IDENTITY();
    DECLARE @before binary(8) = (SELECT RowVer FROM dbo.PurchaseOrders WHERE Id = @id);
    UPDATE dbo.PurchaseOrders SET Notes = N'touched' WHERE Id = @id;
    DECLARE @after binary(8) = (SELECT RowVer FROM dbo.PurchaseOrders WHERE Id = @id);
    ROLLBACK TRANSACTION;
    SELECT CASE WHEN @before <> @after THEN 'changed' ELSE 'unchanged' END;" PurchaseDesk)"

  echo "RESULT summary failed=$failures"
  [[ $failures -eq 0 ]]
}

case "${1:-}" in
  up) up ;;
  reset) docker compose down --volumes >/dev/null 2>&1 || true; up ;;
  check) check ;;
  sql) shift; sql "$@" ;;
  down) docker compose down --volumes ;;
  *) echo "usage: $0 up|reset|check|sql|down" >&2; exit 2 ;;
esac
