# ADR-0006 — Restore skips a workout with an unresolved upload

**Status:** **Proposed** — the owner chose this direction in the PR #22 review on 2026-10-26; acceptance requires owner approval on the PR. Agent-authored text is never approval.
**Amends:** P2-06 foreground restore behavior. ADR-0005 sync scope, CAS and no-last-write-wins rules are unchanged.

## Context

The foreground worker uploads, then pulls an ordered change feed with one cursor per account. An earlier draft paused the whole account's restore while any upload was not acknowledged. `blocked` (cannot upload, e.g. too large or invalid) and `conflict` (another device wrote first) rows are never cleared automatically, so one such workout stopped restore on that phone permanently and invisibly.

## Decision

1. Restore still waits for **pending** uploads, which clear on their own.
2. For a workout with a `blocked` or `conflict` upload, the importer **keeps the local copy**, does not import that workout's remote change, and records it in a durable, owner-bound `WorkoutRestoreSkipEntity` (workout UUID, server change sequence, epoch, tombstone flag, time). The rest of the page imports and the cursor advances in the same transaction.
3. Skip records are **only cleared by a reviewed resolution flow** (P2-06/P2-07, not built). Deleting the conflicted/blocked outbox row alone is not a resolution: the importer refuses to overwrite a local copy it has no remote baseline for (`untracked_local_workout` / `local_revision_changed`), which would durably block the account. Resolution must therefore, in one transaction, reconcile the workout's importer baseline (`WorkoutRemoteStateEntity` and local revision, or an acknowledged upload) and obtain the server version through a **per-workout server read that does not exist yet**; rewinding the shared cursor is not an option because already-imported workouts would fail as `duplicate_remote_sequence`.
4. The state is shown to the user with warning-tone tags: **Not synced** (pending upload; Today offers **Sync now**, which runs the existing foreground worker), **Needs review** (conflict or skipped remote change; Today explains it and offers no retry, because retrying cannot fix it), **Local only** (blocked; existing "not backup-compatible" notice).

## Consequences

- One unresolved workout no longer stops restore of every other workout.
- The server version of a skipped workout is not on the phone until the resolution flow in decision 3 exists. Until then the workout stays **Needs review**. No last-write-wins and no silent overwrite of local data.
- Skip records stay local; they are never uploaded or sent to telemetry.
- Additive ObjectBox model change (one new entity; existing UIDs unchanged).
