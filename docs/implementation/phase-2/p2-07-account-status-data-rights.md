# P2-07 — Account status, export and deletion milestones

**Status:** P2-07a account/sync status UI (#25) implemented. JSON export and permanent account deletion remain unimplemented. Phase 2 is not released.

## P2-07a: account and sync status UI (#25)

- Today opens a dedicated Account screen with an AppBar/back navigation via an account icon, instead of
  offering sign-out as its only account action.
- Display the current **device** cloud-session state and counts of distinct
  unresolved workout uploads, conflict/skipped workouts and local-only
  workouts, plus the number of *blocked operations* (not workouts).
  A paused shared restore cursor is surfaced independently. Zero flags never
  means a verified all-cloud-backups-complete state.
- **Sync now** reuses the existing authenticated foreground upload-and-restore
  worker. It is disabled without a live matching cloud session, is never
  presented as a background job, and never claims completion before server ACK.
  **Refresh status** rereads durable ObjectBox-derived indicators, not a server
  inventory. **Review sync issues** routes to the existing P2-06 per-workout
  conflict recovery.
- **Sign out** continues to use P2-02's secure binding clear and local lock,
  with confirmation explicitly warning of unresolved local changes. Sign-out
  must not be confused with data deletion: locally bound stores remain separate
  for future sign-in by the same owner; no cloud account mutation occurs.
- Disclose that *only* completed native-phone workouts and their sets are cloud
  eligible. Unfinished sessions, plans, device preferences, and physiological
  readings are not backed up under ADR-0005.
- No new ObjectBox schema, SQL migration, credentials, auth grant or dependency.

## P2-07b: authenticated machine-readable JSON export (not yet implemented)

Required by ADR-0005 before release. Deliver separately with:

1. A read-only owner-verified server export endpoint, scoped to the currently
   authenticated non-anonymous user. No caller-provided owner ID or service
   keys on the phone. RLS/grants and malicious cross-owner tests are required.
2. Stable, bounded pagination and a clearly documented consistency cutoff.
   Exclude deletion tombstones' payloads, expired receipts, credentials,
   health-platform data, and other accounts. Preserve UUIDs, UTC timestamps,
   exercises, sets, reps, grams, nulls, and schema/version metadata.
3. A device-controlled file export with deliberate user action (not automatic
   clipboard or analytics logging), clear indication of excluded local-only
   plans/unfinished sessions, and retry/error handling. Export must be
   available before any permanent account deletion action. Prevent account
   switch during pagination/writing from producing a mixed-owner artifact.
4. Authenticated tests for empty accounts, thousands of pages, concurrent
   edits/deletions, revoked auth, path/export failure, and per-owner isolation.

## P2-07c: irreversible account deletion (not yet implemented)

**Do not expose a working deletion button until an audited server workflow
exists.** It must:

- Require online, **freshly reverified** non-anonymous authentication and an
  unmistakable confirmation that server workout history and tombstones are
  irrecoverable; offer export first. Warn about pending offline changes and
  other devices. Never treat sign-out as account deletion.
- Pause account-bound sync and stop new uploads before any destructive step.
  Implement verified server-side deletion of the account and related workout
  records, receipts, owner cursors and auth identity with server-side
  authorization; never place service_role keys or privileged deletions in
  Flutter. Define recovery for uncertain network responses.
- Lock or safely purge only that owner's local ObjectBox partition after
  a verified server deletion receipt; preserve strict account isolation and
  never reassign local data to another user.
- Document retention/legal policy and a production runbook, test idempotent
  retries, stolen/replayed auth, mid-request account switches, second-device
  stale sessions, offline failure, and partially completed server cleanup.

## P2-08 release QA remains mandatory

Hosted Supabase migration drift, JWT/RLS adversarial tests, signed two-device
sync/restore/deletion and iOS/Android storage/device testing are independent
release gates. All CI on the PR head and independent code/security review
must pass before merge. No deployment from this PR.
