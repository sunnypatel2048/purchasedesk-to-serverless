# ADR-0009: Recorded legacy responses (golden files) define "equivalent"

**Status:** Accepted (recorded in Phase 1.6, frozen at `legacy-v1`)

## Context

The new system must behave like the legacy one wherever clients can tell the difference. Writing expectations by
hand would encode what we think the legacy app does, not what it does, and SQL Server to PostgreSQL moves change
behaviour in quiet ways: rounding, collation, NULL ordering, date precision, number formatting, encodings.
The legacy app runs only on Windows, so its behaviour has to be captured somewhere the new code can be checked
against without running it.

## Decision

- Record what the legacy system actually returns into committed files under `golden/`: 38 API responses
  (`golden/api/`, request and response: status, `Content-Type`, `Location`, body) and 2 nightly export files
  (`golden/export/`, exact bytes).
- Record on GitHub's Windows runners, against a freshly loaded database, in one fixed sequence: reads, then writes
  (so the first new order is always id 2001), then the export. CI reloads a fresh database before other suites.
- JSON is parsed so nothing is lost: decimals keep their scale (`150.1500`) and dates stay the strings emitted.
- Normalise only what cannot repeat: every `Version` (a rowversion) becomes `<rowversion>`, and in responses to
  writes `OrderDate` and `DecidedAt` (from `GETDATE()`) become `<now>`, and only when they have the expected shape.
- A missing golden file is a failure. Golden files are created only by recording a run, reviewing it, and
  committing it. CI uploads every run's recordings as the `golden-actual` artifact.
- After `legacy-v1`, `legacy/` and `golden/` change only to fix a broken build (`legacy-frozen` check).

## Consequences

- "Equivalent" has a precise, reviewable meaning; the Phase 6 parity tests compare the new API with these files.
- Traits are visible in the files themselves: PascalCase names, four-decimal money, `T00:00:00` on date-only values,
  `.997`/`.003` milliseconds, NULL-first sorting, the collation's supplier order, Windows-1252 and CRLF in the export.
- Some legacy behaviour is a defect the new system will not copy. Each such difference is listed and justified
  rather than hidden. The first: a line Sku longer than 40 characters returns **500** from the legacy API
  (`golden/api/write-12-create-sku-41-chars.json`); the new API returns 400.
- The golden test must run first on a fresh database, which costs a reload (about 20 seconds) per CI run.

## Alternatives considered

- **Hand-written expected values:** encode assumptions, and miss the traits nobody thought to check.
- **Comparing against a live legacy server:** that is the Phase 6 deployed check (`make parity`), but CI cannot run
  a Windows server on every change, and a live comparison has no history to review.
- **Snapshot normalisation of everything volatile-looking** (all dates, all ids): hides exactly the precision and
  numbering behaviour the migration has to preserve.
