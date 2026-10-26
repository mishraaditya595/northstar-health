# P2-04 — Automatic authenticated upload of completed workouts

**Status:** PR #16 **merged**. Production release remains gated by real authenticated RLS/E2E and device QA.  
**Policy:** [ADR-0005](../../adr/0005-mandatory-auth-and-workout-sync.md) — mandatory account; **only completed phone workouts** synchronize. The phone is local-first.

## Delivered in this milestone

- `WorkoutUploadCoordinator` starts inside **each authenticated account's own ProviderScope/ObjectBox Store**, not in the global or logged-out app. It attempts upload after startup, after finishing a workout, when Supabase authentication becomes usable again, on app resume, and every 45 seconds while foregrounded. In-flight triggers set a coalesced run-again flag; the first kick is deferred until after Riverpod provider construction. This is *foreground best effort*, not an unsupported iOS/Android periodic background guarantee.
- `SupabaseWorkoutUploadTransport` uses the existing `public.sync_workout` RPC and **only** the configured Supabase client (public publishable key plus the user's normal JWT). It checks a live, unexpired, non-anonymous Supabase session matching the locally bound account before dispatch. The RPC itself derives account ownership using `auth.uid()` and enforces RLS.
- Outbox operations remain durable; `reserveNext` records attempt count and attempted timestamp **before** any await/network call. It uses the existing ObjectBox schema; no model IDs change. Unacknowledged requests retry after durable exponential backoff (5 seconds doubling up to 10 minutes), including app/process restarts. A future-dated attempt from a corrected device clock is considered immediately retryable.
- Each operation keeps its **immutable operation UUID and payload** across retries. Initial request expects server revision 0. Later revisions of the *same* workout wait for the previous ACK and use its stored server revision. A later revision never leapfrogs an unacknowledged/blocked/conflicting predecessor. This is optimistic compare-and-swap, not last-write-wins.
- Server `applied` response is acknowledged locally only with valid `revision == expected + 1`, `change_seq > 0`, `processing == processed` and explicit replay flag. Missing or malformed replies remain pending. `conflict` is durable and never silently overwritten; SQLSTATE `22023` becomes a local `blocked` receipt, never an infinite upload retry.
- Backfill scans **only completed sessions with non-null completion timestamps, nondeleted NorthStar-authored sessions in the already-verified account's partition**, adding an operation if that workout has no outbox record. Malformed records are skipped per session, preventing them from blocking later uploads. A whole-backfill error is attempted once per app session and reported as `backfill_failed`, while already-pending uploads continue. It does not migrate old root stores, unfinished sessions, discarded sessions, imported wearables, external workouts, or plans.
- Outbox notes, ACKs, retry state and snapshots stay in the same account-specific ObjectBox Store. The non-sensitive `lastFailureKind` reports categories such as `backfill_failed`, `rpc_timeout`, `invalid_server_ack` and `local_queue_failure`; raw payloads, tokens and exception contents are never printed. Malformed queued rows become `blocked` and trigger a post-transaction blocked-count refresh. HTTP timeouts and disconnects never count as success.
- A worker is canceled/invalidated with its account ProviderScope; if the SDK changes account identity while a request is in flight, it cannot acknowledge that operation in the prior account's Store after the await.

## Timing and delivery boundaries

- Launch while online and authenticated: backfill completed account-local history, then process up to **25** eligible operations per drain.
- Resume, foreground interval or workout completion: attempt the next eligible batch, respecting durable per-operation retry delay.
- Offline, expired JWT or anonymous state: keep using the local logger; **no RPC**. On sign-in or session refresh, resume from saved operations.
- Request sent but response lost: same operation UUID, same expected server revision and JSON payload are retried. Server idempotency receipt returns the original revision, not a duplicate workout.
- Conflict or validation reject: do not advance the server cursor or delete local data. Human-friendly recovery/conflict UX and remote reconciliation are part of P2-06/P2-07.
- **No restoration** of cloud history to a new device in this milestone. **No completed-workout deletion sync yet** because that command path is not implemented; a tombstone/reconciliation flow must be added later.
- No guarantee that the app can process uploads while terminated or kept in the background for extended periods. OS-managed background scheduling requires separate design and device testing.

## Deferred queue visibility gaps (P2-06/P2-07)

- A `blocked` or `conflict` predecessor prevents later revisions of the same workout from uploading; these remain `pending` until reconciliation. P2-06/P2-07 must show the dependency clearly and provide explicit recovery.
- `reserveNext` scans the first 500 pending operations. A large set of skipped or dependency-blocked rows may hide eligible work after that window. P2-06/P2-07 need fair cursor-based selection and stalled-queue status without data loss.
- Historical backfill that fails globally remains disabled for the current account session and exposes `lastFailureKind = backfill_failed`; a safe operator/user-controlled recheck belongs to P2-07.

## Security and account safety

The application never embeds `service_role`, `sb_secret_` credentials, database passwords, project access tokens or private signing keys. The client uses `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY` public build settings from P2-02; Supabase Auth supplies each session JWT at request time. Always preserve server-side authenticated RPC restrictions and RLS. Sync must not upload incomplete, paused, discarded or watch-imported data.

The uploader never observes or reads another account's ObjectBox Store. Changing users unmounts the previous ProviderScope, cancels the worker and keeps pending data on disk for the rightful original account. Previously untrusted guest/root workout data must never be auto-associated.

## Verification and release gates

Native tests with fake RPC transport plus real ObjectBox verify: malformed/null-completion and per-session-failure backfill, foreground host wiring, resume and session triggers, the 25-operation cap, in-flight re-kicks, future-clock attempts, ten-minute retry cap, missing-only-`replay` ACK and transport session checks, alongside: first upload, exact replay, two local revisions, conflict, server validation failure, expired authentication, cross-account change mid-flight, malformed ACK, old completed-only backfill, persistent retry timing, and noncompleted rejection. Live Supabase end-to-end tests with independent real Auth sessions **have not been executed** and are required before production.

Before merge: CI should pass Dart formatting, analyzer, native tests, Android build, repository contracts and watch CI. Before release: Android/iOS physical-device lifecycle and secure-storage checks, live RLS/account-scoping tests, cloud replay under network interruption, metrics correctness, pending/blocked/conflict UX, scheduled global 90-day receipt cleanup and account deletion/export.

## Rollback

Disable the uploader/foreground runner via a reviewed client rollback and/or revoke the authenticated RPC `EXECUTE` grant server-side. Preserve **all local outbox operations and server workout rows**; never clear a queue just because an HTTP request may have reached the server. Recover using the same stable operation UUID after reauthorization.
