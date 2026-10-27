# P2-07 — Account status, export and deletion milestones

**Status:** P2-07a account/sync status UI (#25) merged. P2-07b cloud-history JSON export (#27) is implemented in code; P2-07c account deletion is implemented in draft PR #29 but has **not** been deployed or security-accepted. Phase 2 is not released.

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

## P2-07b: authenticated machine-readable JSON export (#27)

Required by ADR-0005 before release. Implementation and review requirements:

1. Read owner-scoped `public.workout_records` with existing authenticated
   SELECT + RLS. No new SECURITY DEFINER endpoint, owner parameter in an RPC,
   schema migration or secret/service key. The client filters by its verified
   account as defence in depth, checks response owner IDs, and rechecks the
   auth session before/after every network call. Hosted JWT/RLS adversarial
   tests are still a P2-08 release gate.
2. Page by workout UUID with **explicit ascending PostgreSQL UUID order**
   (verified on the actual Dart PostgREST HTTP builder; its implicit default
   produced descending order and was unsafe for a `gt` keyset). Enforce a
   strict request cap of 100 rows and filter by the initial
   highest owner change sequence (including tombstones) and re-read the same
   maximum at the end. Stop only on an empty page (not a short page): a
   lower PostgREST server-side row cap must not silently truncate exports.
   Any concurrent owner write/delete increases that
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
   materialized in memory with a temporary conservative 4 MiB *output byte*
   bound (not a measured heap bound); larger accounts fail explicitly and
   never report success with truncated data. The Dart JSON buffer, channel
   copy and native picker can hold multiple representations simultaneously.
   **No low-memory device peak-RSS figure has been measured yet**; this is a
   **P2-08 release gate, not a P2-07b merge gate**. Native Android streams writing on a background thread
   using truncate mode, with best-effort DocumentsContract deletion for failed,
   abandoned or incomplete files; providers can deny deletion. In-flight writes
   own their completion across Activity teardown, rather than falsely
   reporting failure while a background write is still active. A process-wide
   cleanup lock, unique generation marker and compare-and-clear protect new
   exports from stale startup cleanup. Native iOS
   atomic write uses complete file protection (without redundant after-write
   protection changes) and stale temporary export folders are purged on launch. Both pickers require physical-device QA. Streaming
   large-account exports beyond 4 MiB remain follow-up work before the
   all-history requirement can be considered satisfied at arbitrary scale.
   The user-selected destination is outside NorthStar's control; warn that
   the exported file is sensitive. Test native delivery on physical iOS
   and Android before release.
4. Dart synthetic unit/widget tests cover empty accounts, 1,201 workouts
   with an additional empty-terminal page, **short server pages**, nulls,
   changed server watermark, expired/switched auth, wrong-account rows,
   malformed payloads/UUIDs, out-of-order pages, excessive output, and
   Dart MethodChannel's mocked native save/cancel/failure responses.
   Actual SupabaseWorkoutExportReader queries are asserted over mocked HTTP,
   including owner, status, tombstone exclusion, ordering, cap and high-water
   query. **These are not Kotlin/Swift native tests**, not real cloud RLS tests,
   and not proof of platform file-provider behavior. Native export tests,
   hosted signed JWT/RLS tests, simultaneous second-device changes, Drive/SAF
   denial of delete, app kill/restart cleanup, iOS picker presentation failure,
   and Android low-memory (including peak RSS) remain release gates.
   The concrete, **unrun** hardware and hosted verification matrix is
   [P2-08 workout export release validation](p2-08-workout-export-release-validation.md).

## P2-07c: irreversible account deletion (draft PR #29, not deployed)

Implementation uses an OTP verified against the *same* Supabase account to
create a genuinely new Auth session. The read-only
`public.authorize_account_deletion()` checks its `auth.sessions.created_at`
against a five-minute window, so simply refreshing a JWT is insufficient.
The server-only `delete-account` Edge Function verifies the caller again and
uses `auth.admin.deleteUser` with a server-held privileged key; existing
cascade FKs remove completed history, receipts, tombstones and owner cursors.
The phone clears its secure bound-account identity before asking the server,
unmounting its upload/restore worker and locking the original local partition.
After an exact server success receipt, the app attempts a durable confirmed-cleanup marker and erases the original owner's ObjectBox directory after Store unmount (retry on launch if the marker was saved). If this marker write fails, the verified response still permits immediate erase; if that also fails, the persisted uncertain-recovery marker remains locked. **Owner decision, 2026-10-27 (ADR-0007):** uncertain recovery offers **Use another account (keep old data locked)** (clear binding, then recovery marker; leave original owner files untouched and never transfer them) and **Erase local data and leave** (clear binding, erase original owner files, then recovery marker; failed erase retains recovery). Both are separately confirmed with **Keep recovering** cancellation. An original account that still exists can subsequently reopen its own local files only with a successful sign-in to the same verified Auth UUID. No uncertain result triggers automatic local erasure; explicit separate user consent is required to erase while the server outcome is unknown. Only that UUID's directory is eligible; uncertain server results lock without erasing. Explicit handler 4xx refusals can rebind only if the same verified owner remains active.

The following requirements are **implemented in code, not yet demonstrated
against a hosted project or physical device**. See
[Account deletion runbook](../../../supabase/ACCOUNT_DELETION_RUNBOOK.md). The two recovery exit options amend ADR-0005 item 4 under [owner-approved ADR-0007](../../adr/0007-account-deletion-recovery-exit-choices.md).

- Require online, **freshly reverified** non-anonymous authentication and an
  unmistakable confirmation that server workout history and tombstones are
  irrecoverable; offer export first. Warn about pending offline changes and
  other devices. Never treat sign-out as account deletion.
- Pause account-bound sync and stop new uploads before any destructive step.
  Implement verified server-side deletion of the account and related workout
  records, receipts, owner cursors and auth identity with server-side
  authorization; never place service_role keys or privileged deletions in
  Flutter. Define recovery for uncertain network responses.
- Lock only the original owner's local ObjectBox partition before the
  irreversible network operation. Never purge local records on an uncertain
  response. A successful server deletion durably records a local cleanup
  task, unmounts ObjectBox, and deletes only that owner's local workouts,
  plans and outbox; failed deletion is retried at next launch or from the
  locked account screen. No partition may ever be reassigned to another user.
- Run the newly committed synthetic controller and SQL session-age tests.
  Hosted end-to-end proof is still required for stale/replayed tokens,
  mid-request account switches, second-device stale JWTs, network ambiguity,
  cascade cleanup, Storage-object deletion blockers and retention/legal policy.
  An uncertain result always keeps local access locked and never claims a
  successful rollback. The server deletion is a single Auth admin hard-delete
  with FK cascades, not a multi-table client cleanup.

## P2-08 release QA remains mandatory

Hosted Supabase migration drift, JWT/RLS adversarial tests, signed two-device
sync/restore/deletion and iOS/Android storage/device testing are independent
release gates. All CI on the PR head and independent code/security review
must pass before merge. No deployment from this PR.
