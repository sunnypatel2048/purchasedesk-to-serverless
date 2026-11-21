# ADR-0001: Migrate in stages: replicate data, move reads by percentage, cut writes over once

**Status:** Accepted

## Context

PurchaseDesk is a .NET Framework 4.8 Web API on IIS with its business rules in SQL Server stored procedures.
It has to move to Lambda, API Gateway and Aurora PostgreSQL while it keeps serving requests. A migration of
this kind is judged on two things: how long users are affected, and whether every step can be undone.

## Decision

Run both systems side by side and move in this order:

1. Replicate the data one way, SQL Server to Aurora PostgreSQL, with AWS DMS (full load, then ongoing changes).
2. Prove the new read path returns the same responses as the legacy one for a fixed dataset.
3. Move read routes one at a time, at 10%, 50% and 100%, at the front door.
4. Move all writes in one cutover: freeze writes, let replication drain, verify, switch, unfreeze.
5. Decommission the Windows server and the replication.

Write routes are only ever at 0% or 100%, so the two databases never both accept writes.

## Consequences

- Reads never go down; writes pause once, for a measured window.
- Every step before the write switch can be undone by setting weights back to legacy.
- After the switch there is no automatic way back, because Aurora holds writes SQL Server does not.
  Production would run reverse replication for a bake period; this project states the gap instead.
- While reads are shifting, a client can write on the legacy side and briefly not see it on the new side.
  The replication lag is measured.

## Alternatives considered

- **Big-bang cutover after one data load:** simpler, but one risky moment and no gradual story.
- **Move the code first and point it at SQL Server:** the data access would be written twice, once per database.
- **Dual writes from the application:** hard to keep consistent, and needs changes to legacy code that is frozen.
- **Full load only, with a long write freeze:** kept as the fallback if ongoing replication cannot be made to work.
