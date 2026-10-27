# P2-07 — Account status, export and deletion milestones

**Status:** P2-07a account/sync status UI (#25) merged. P2-07b cloud-history JSON export implementation is under review; account deletion remains unimplemented. Phase 2 is not released.

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

## P2-07b: authenticated machine-readable JSON export (under review)

Required by ADR-0005 before release. Implementation and review requirements:

1. Read owner-scoped `public.workout_records` with existing authenticated
   SELECT + RLS. No new SECURITY DEFINER endpoint, owner parameter in an RPC,
   schema migration or secret/service key. The client filters by its verified
   account as defence in depth, checks response owner IDs, and rechecks the
   auth session before/after every network call. Hosted JWT/RLS adversarial
   tests are still a P2-08 release gate.
2. Page by workout UUID (max 100 rows/request), filter by the initial
   highest owner change sequence (including tombstones) and re-read the same
   maximum at the end. Any concurrent owner write/delete increases that
   sequence and aborts the export *before* platform file handoff; no partial
   document is saved. No durable snapshot is reserved across requests.
   Database PITR requires epoch rotation per the existing restore runbook.
   Preserve original DTO UUIDs, UTC timestamp strings, sets, nulls and schema
   fields; exclude tombstones, expired receipts, credentials, health data,
   outbox, unfinished workouts, plans and other owners.
3. Explicit Account-screen action presents Android's system Create Document
   picker or iOS's UIDocumentPicker. No extra dependency or app-level
   permanent file is created; iOS writes a protected temporary file deleted
   on picker completion. No clipboard, analytics logging or in-app automatic
   saving. Native picker cancellation does not say exported. The JSON is
   materialized in memory with a strict 64 MiB bound; larger accounts fail
   explicitly instead of generating truncated data. Streaming large-account
   exports beyond this limit are a separate P2-07b follow-up before the
   all-history requirement can be considered satisfied at arbitrary scale.
   The user-selected destination is outside NorthStar's control; warn that
   the exported file is sensitive. Test native delivery on physical iOS
   and Android before release.
4. Synthetic tests for empty accounts, 1,201 workouts over 13 pages, null
   values, changed server watermark, expired/switched auth, wrong-account
   rows, malformed payloads, out-of-order pages, oversized output and native
   save/cancel/write failures. Hosted signed JWT/RLS tests, simultaneous
   second-device changes and iOS document-picker device tests remain P2-08
   acceptance gates.

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
