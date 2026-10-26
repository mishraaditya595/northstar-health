# NorthStar workout database restore: cursor epoch recovery

**Applies to:** P2-06 server-side completed-workout restore feed (PR #18). **Operator-only procedure.**

## Why epoch rotation is mandatory

A point-in-time restore can rewind account-local sync sequences; after new writes overtake an old device cursor, numeric comparisons cannot detect the gap. Restore responses therefore include a database-wide **cursor_epoch**. Devices bootstrap with cursor 0 and a missing epoch, then echo the returned epoch with every subsequent request. Mismatched or missing epochs trigger **cursor_reset = true** and a restart cursor of zero.

**A database backup contains the epoch itself.** Restoring that backup also restores its old epoch. The function cannot determine whether the current database is a historical snapshot using only its contents. **A privileged operator must rotate the epoch after every restore, before reopening clients.** Skipping this step reintroduces silent missed changes. The application has no permission to perform rotation.

## Required sequence for every restore, including PITR

1. **Quiesce app traffic, writers and sync RPCs** under an approved maintenance plan. Do not let clients resume until after the epoch rotation commits.
2. Restore the snapshot using the approved infrastructure procedure. Verify migrations, including P2-06. If the backup predates P2-06, reapply reviewed missing migrations in order first.
3. Connect as the **privileged database owner (postgres)**, never a mobile JWT, anonymous role, or application credential. Commit a fresh global epoch in a short transaction:

   ```sql
   begin;
   select northstar_private.rotate_workout_restore_epoch() as new_epoch;
   commit;
   ```

   The rotation function uses SECURITY INVOKER and is not executable by PUBLIC, anon, or authenticated. It changes **only the epoch**, not workout records, receipts, tombstones, owner cursors or mobile outboxes.
4. From the privileged session verify exactly one non-null epoch record and the rotation timestamp:

   ```sql
   select epoch, rotated_at
   from northstar_private.workout_restore_epoch
   where singleton = true;
   ```

   Compare to the old epoch if known; verify schema/RLS, migration history and record integrity. If rotation failed or rolled back, **keep traffic blocked**.
5. Resume clients after the epoch change and checks. Devices echoing an older epoch must receive a reset even if their stale sequence is less than the server's current counter. Persist the new epoch together with restored ObjectBox data and next cursor, as one owner-scoped transaction. Preserve local unsynced/blocked/conflicted workouts, do not resurrect tombstones, and reconcile revisions rather than overwriting local edits. This mobile importer is **not yet implemented** in PR #18.

## Normal operations and incidents

- Normal database restarts and app deployments without restoring old data **do not require** an epoch rotation. Rotating unnecessarily causes every device to perform a full owner-scoped reconciliation.
- If a restore accidentally served traffic before epoch rotation, stop clients, rotate immediately, and investigate skipped or lost writes. An epoch reset cannot recreate records erased by the restore; recover from backups or retained device outboxes when possible.
- A newly authenticated device starts at cursor 0 with no epoch. It may correctly see tombstones for workouts it never stored; these must not create phantom workout entries.
- Rotating the epoch invalidates all clients' old epochs, but **never deletes data**.
- No application/cloud restoration can be declared production-ready without a client that implements epoch echo, crash-atomic imports, tombstone handling and safe conflict resolution.

## Pre-release tests and boundaries

Clean CI must exercise missing and mismatched epochs, a cursor ahead of the owner counter, **an old-epoch cursor of 8 when the current counter has reached 10** (simulated restore rotation), exact-limit pagination and private role grants. Stage an actual database backup/restore and confirm the operator runbook rotates the epoch before network access. Test at least two independent signed-in sessions. pgTAP is single-session and cannot prove writer commit ordering; the reviewer separately checked that property with two concurrent connections.

**Never rewrite already deployed migrations, drop workout tables, or use an old unguarded read RPC as a rollback path.**
