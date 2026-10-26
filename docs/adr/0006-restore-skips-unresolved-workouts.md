# ADR-0006 — Restore skips a workout with an unresolved upload

**Status:** **Proposed** — the owner chose this direction in the PR #22 review on 2026-10-26; acceptance requires owner approval on the PR. Agent-authored text is never approval.
**Amends:** P2-06 foreground restore behavior. ADR-0005 sync scope, CAS and no-last-write-wins rules are unchanged.

## Context

The foreground worker uploads, then pulls an ordered change feed with one cursor per account. An earlier draft paused the whole account's restore while any upload was not acknowledged. `blocked` (cannot upload, e.g. too large or invalid) and `conflict` (another device wrote first) rows are never cleared automatically, so one such workout stopped restore on that phone permanently and invisibly.

## Decision

1. Restore still waits for **pending** uploads, which clear on their own.
2. For a workout with a `blocked` or `conflict` upload, the importer **keeps the local copy**, does not import that workout's remote change, and records it in a durable, owner-bound `WorkoutRestoreSkipEntity` (workout UUID, server change sequence, epoch, tombstone flag, time). The rest of the page imports and the cursor advances in the same transaction.
3. A later successfully applied remote change for that workout removes its skip record.
4. The skip is shown to the user: Progress tags the workout **Not synced** (or **Local only** when blocked), and Today counts not-synced workouts with a **Sync now** action that runs the existing foreground worker.

## Consequences

- One unresolved workout no longer stops restore of every other workout.
- The server version of a skipped workout is not on the phone until a reviewed resolution flow (P2-06/P2-07) re-fetches it. No last-write-wins and no silent overwrite of local data.
- Skip records stay local; they are never uploaded or sent to telemetry.
- Additive ObjectBox model change (one new entity; existing UIDs unchanged).
