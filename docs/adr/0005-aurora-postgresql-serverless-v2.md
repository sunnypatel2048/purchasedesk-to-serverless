# ADR-0005: Aurora PostgreSQL Serverless v2 as the target database

**Status:** Accepted

## Context

The legacy data is relational: suppliers, purchase orders, order lines and an audit log, with foreign keys,
transactions and paged, sorted searches. SQL Server licences are a large share of a typical Windows estate's
cost. The target should cost close to nothing when idle, because the project runs only during short sessions.

## Decision

Migrate to Aurora PostgreSQL Serverless v2, 0 to 2 capacity units, loaded and kept in sync by AWS DMS. The
PostgreSQL schema is created by the project's own migrations before DMS starts. The business rules that lived
in stored procedures move into tested C# (see the domain library), not into PL/pgSQL.

DynamoDB appears only as the idempotency store for order creation.

## Consequences

- Keeps the relational model; joins, transactions and the existing query shapes carry over.
- Removes the SQL Server licence; the before-and-after cost comparison is a deliverable.
- Pauses to zero instance cost when idle and resumes in about 15 seconds. Client connect timeouts must allow
  for the resume.
- SQL Server and PostgreSQL behave differently in places (rounding, collation, NULL ordering, sequences after a
  copy, `datetime`/`money` precision, `rowversion`). Parity tests exist to catch each one.
- List price checked on 2026-11-21: $0.12 per capacity-unit hour (I/O-Optimized: $0.16).

## Alternatives considered

- **DynamoDB:** was in the first sketch. It would mean defending a key-value store for relational,
  transactional data and rewriting every query.
- **Babelfish for Aurora PostgreSQL:** keeps the T-SQL and stored procedures, which is the very thing being
  moved out of the database.
- **RDS for SQL Server:** a lift-and-shift that keeps the licence cost and the logic in the database.
