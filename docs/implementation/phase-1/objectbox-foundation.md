# Phase 1 — Offline workout logger implementation

**Status:** PR #5 hardening; storage model only, **no active workout UI**.

## Durability and retry contract

- Domain UUIDs differ from ObjectBox internal IDs; generated UIDs are frozen.
- `WorkoutRepository.saveSet` requires `expectedRevision`. The method
  compares this with the current session revision **inside the write transaction**.
  A duplicate identical set is acknowledged without creating a new record,
  even if the revision advanced. A stale changed retry raises
  `WorkoutRevisionConflict` and cannot overwrite newer reps, weights or RPE.
  Callers must reload the aggregate and explicitly resolve the conflict. Never
  auto-retry conflicts with the latest revision.
- Each successful set save updates its session revision and recovery checkpoint
  in the same ObjectBox transaction; if checkpoint lookup fails after set
  write, ObjectBox rolls back all changes. No UI should show success before
  the method returns.
- `createSession` and `addExercise` accept exact duplicate
  commands and reject conflicting reuse of UUIDs. The deprecated
  `finishSession` now **requires expectedRevision** and rejects stale
  commands. Production completion uses `LiveWorkoutEngine.finishWorkout`. Exercise and set ordinal
  positions are unique **per parent**, enforced in repository transactions.
  There is no composite unique DB index yet; all writes must use repositories.
- Missing values remain nullable. Unknown persisted status/kind/unit strings
  decode to read-only `unknown`, so the session remains readable without
  treating unknown values as safe to edit.

## Outbox scope: deliberately absent in Phase 1

`AGENTS.md` describes an atomic local-write + `SyncOutbox` transaction
**when a cloud-associated owner exists and remote backup is enabled**.
Phase 1 is offline and guest-only with no Supabase Auth, no server, no upload
agreement, and therefore **creates no outbox records**. This is consistent
with `docs/OBJECTBOX.md`'s rule against assigning guest data silently.

**Phase 2 association/backfill proposal (not implemented in this PR):**
1. Require login and **explicit consent** to associate this device's existing
   completed NorthStar sessions with the signed-in account.
2. In one ObjectBox transaction, mark the eligible completed session(s) as
   associated with that owner and enqueue idempotent, versioned portable
   aggregate snapshots in a durable outbox, with stable operation IDs.
   Do not enqueue drafts, custom plans, imported health samples or caches.
3. The worker sends only for the current authenticated owner and only after
   association; server checks expected revision and durable ACK before dequeue.
4. If the user logs out/switches accounts, pause queue delivery and preserve
   unsent local records; do not automatically reassociate them.
5. Deduplicate backfill after crash/restart by session UUID and intended
   associated revision. Cloud RLS and conflict tests are required in Phase 2.

## OS backup policy — intentionally local-only (until further decision)

Phase 1 excludes the ObjectBox database from Android Auto Backup, Android
12+ device-to-device extraction and iOS iCloud/iTunes app-data backups:
- Android manifest opts out with `allowBackup=false` plus explicit pre-12
  and Android 12+ XML rules excluding app data.
- iOS sets `isExcludedFromBackup` and the
  `completeUntilFirstUserAuthentication` data-protection class on the
  default Documents/objectbox directory before the Flutter Store opens.
- This prevents unapproved backup flows but **does not encrypt ObjectBox
  itself**. Device OS-level encryption is a separate protection.
- **Deleting the app or losing the device can permanently lose all Phase 1
  workouts and custom plans.** The UI must disclose this before release.
- Verify on actual Android/iOS devices and investigate OEM backup behavior;
  do not claim device-only policy is fully validated by static configuration.
- When Supabase backup ships, revisit OS backup exclusion and UX consent,
  rather than silently enabling system backups.

## Tests / release gates

CI installs the checksum-verified pinned ObjectBox C library v5.3.2 for Linux,
then runs true native ObjectBox repository tests in temporary directories.
Covered: persistence/reopen, null round-trip, exact retry, late conflicting
retry, rejected cross-session write, invalid status/position, soft-deleted
guard, idempotent commands, and rollback after partial write.

Still required before approving release: Android/iOS real process-death and
low-storage smoke tests, OS backup/restore policy inspection, and first
frozen-UID version upgrade fixture when the model actually changes.
Schema source of truth: `apps/mobile/lib/objectbox-model.json`;
never delete/regenerate UIDs to resolve a migration conflict.
