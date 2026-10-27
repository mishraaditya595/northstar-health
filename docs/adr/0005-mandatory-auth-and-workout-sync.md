# ADR-0005 — Mandatory accounts and automatic completed-workout sync

**Status:** **Accepted** — approved by the project owner on 2026-10-25 (PR #13).  
**Supersedes:** ADR-0003 and earlier Phase 1/2 roadmaps **only where they specify optional accounts and guest access**. ADR-0003's completed-workout-only cloud scope is **kept**. All privacy and local-first constraints not explicitly changed remain in force.

## Decision and rationale

NorthStar requires a verified account before anyone can use workout features. There is **no guest mode**. Initial signup/sign-in requires network access. Once a user has authenticated and the device has a securely bound local account identity, the user can log workouts offline. A revoked or unknown account must never be treated as another user's owner; auth refresh failures pause cloud transfer, not already-authorized local saves.

Only workouts the user has **finished on the phone** (`completed`) are synchronized to Supabase, as authenticated, versioned aggregates with deletion tombstones. In-progress, paused and discarded sessions **never leave the device**, and a completed workout cannot return to an unfinished state. Upload starts automatically once the workout is finished and authenticated connectivity is available; later edits to a completed workout upload as new revisions. Only recorded sets and essential historical exercise snapshots are synchronized, not recovery UI checkpoints, rest timers, platform measurements or watch sensor streams. Completed-session statistics are calculated on the server from validated sets. The phone commits workout changes and a durable outbox entry atomically.

This is **synchronization plus backup** of finished history, not an unrestricted replication of ObjectBox. Source attribution is required: the initial RPC admits only `northstar_phone`, and must reject missing origin and external/health-provider workouts. Watch-origin workouts are **not** synchronized until a separate policy and transport review; cloud history is phone-only until then.

## Owner decisions

The owner decided on 2026-10-25: mandatory accounts, no guest mode, completed-only sync, automatic upload after the workout ends, and tombstones kept for the account lifetime. The owner also approved the following terms:

1. **Disclosure.** The privacy notice and signup flow state that finished workouts (sets, exercise labels, repetitions, loads and timestamps) are backed up automatically to the user's account.
2. **Workout retention.** Completed workouts are kept while the account exists unless the user deletes them. A verified delete removes the payload and statistics immediately and keeps a *tombstone* (user ID, workout ID, revision, deletion time; no workout content) until **the account itself is deleted**, so an offline or second device cannot resurrect it. The old workout UUID is never reused. Hash-only request receipts expire after 90 days, with global scheduled pruning still a release gate. Determine any separate legal retention obligations before shipping.
3. **User export.** Provide an authenticated, owner-scoped, machine-readable JSON export of all completed workout history (schema version, IDs, timestamps, exercises and sets), excluding access tokens and other accounts' records. Export must be available before account deletion. Document what is *not* included, such as custom plans and platform-owned physiological records.
4. **Account deletion.** Provide a clearly labeled in-app delete-account workflow requiring an online, freshly verified session and explicit confirmation. Warn about pending offline changes and irreversible deletion; pause sync queues, revoke sessions, delete account-related database records and tombstones with verified server-side authorization, then permanently erase only the original owner's local ObjectBox data after an exact confirmed server-success receipt, retaining a durable retry-on-launch cleanup marker until erasure succeeds. Uncertain results must lock, not **automatically** erase, the original partition. **Owner-approved refinement (2026-10-27; ADR-0007):** the uncertainty/recovery screen offers two independently confirmed paths. **Use another account (keep old data locked)** clears the secure account binding before clearing the recovery marker and preserves the original owner's local ObjectBox partition without transferring or opening it for another identity; a future verified sign-in by that same existing Auth UUID can reopen it. **Erase local data and leave** clears the binding, deletes only the original owner's files, then clears the recovery marker; erase failure retains that marker. Both confirmation dialogs offer **Keep recovering**. Local erasure following an uncertain outcome must never occur without the user's separate explicit consent; initial deletion consent covers local erasure only after the server confirms success. If persisting the confirmed-cleanup marker fails after an exact server receipt, immediately attempt owner-scoped local erasure while confirmation is in memory; if local erasure also fails, keep the uncertain recovery guard locked. A later explicit, separately warned user decision to discard this device's local data may erase it even if the cloud outcome is unknown; this never claims to delete cloud records. The server must not silently re-associate orphaned records to another account. An operational retention/deletion runbook, status feedback, and cross-device verification are needed before release.

**Approval:** Original decisions accepted by the human owner on PR #13. The 2026-10-27 recovery exit refinement above is explicitly requested and approved by the human owner in the review discussion of PR #29 and is formally recorded in [ADR-0007](0007-account-deletion-recovery-exit-choices.md). Future changes to these terms require a new numbered ADR; agent-authored text is never approval.

## Privacy and identity rules

- Supabase publishable keys and project URL are not privileged secrets, but the public open-source app must **never contain service-role keys, secret keys, personal access tokens, database passwords or real user data**. The Supabase Auth user JWT plus RLS and a server-enforced authenticated RPC control access.
- Workout data is sensitive. Update privacy policy/data retention disclosures **before release**. No physiological measurements, HR/HRV, sleep, steps, SpO₂, GPS trails, external workouts, custom plan definitions, unfinished sessions, platform permissions or local ObjectBox files go to Supabase.
- Every server mutation uses a stable operation UUID, an account/workout ID, a server revision CAS and server-computed results. Conflicts are explicit, with no last-write-wins.
- Anonymous Supabase Auth identities are **not** sufficient; a verified non-anonymous user is required.
- Authentication credentials use vetted secure OS storage and are never stored in the ObjectBox workout tables or diagnostics.
- No guest data exists to migrate: no Phase 1 build with real guest workouts is in users' hands. If that assumption changes, a new decision is required before any local history is attached to an account.
- Account switching requires suspending the previous owner's outbox, clearing in-memory identity-bound views, requiring the new owner's auth and guarding against cross-account reads/uploads. Unsynced changes remain recoverable and are never reassigned automatically.

## Reliability and retention

- Sync is automatic for completed workouts, but absence of connectivity never blocks an ObjectBox commit. User-facing status distinguishes saved locally, queued, synced, conflict, and processing completion. Initial sign-in cannot occur offline.
- The server validates a strict versioned DTO before locking; uses a per-user transaction lock plus conditional revision update; allocates an account-local, transactionally ordered change cursor; stores only a SHA-256 request digest for idempotent receipt matching.
- Workout payloads are deleted from the main aggregate upon deletion; the tombstone remains until account deletion. Hash-only replay receipts retain for **90 days**, then are opportunistically purged on the next account sync; a verified administrative schedule is still required to purge receipts for inactive accounts. After expiry, an old retry may receive a revision conflict rather than an original replay ACK; clients must reconcile. Receipt pruning never removes tombstones.
- Cloud sync restores completed workout history only. It does not restore unfinished sessions, custom plans, exercise catalogs or app preferences in Phase 2.

## Implications and roll-out gates

Update `AGENTS.md`, `docs/CLOUD_SYNC.md`, `docs/ROADMAP.md`, `docs/ARCHITECTURE.md`, `docs/OBJECTBOX.md`, `docs/adr/0003-data-cloud-health.md`, `supabase/README.md`, implementation docs and public user-facing disclosures to reflect this decision. Require RLS negative tests, malformed-payload tests, idempotency/revision tests, cross-account/restore tests, schema-upgrade tests and Android/iOS QA. This ADR records the owner's requirements; it does **not** approve an untested PR for merge or release.

## Rollback

Do **not** revert the schema by dropping tables containing workout data. Emergency stop: revoke authenticated RPC EXECUTE and disable mobile sync while preserving local outboxes and server records. Roll forward with a tested corrective migration and rotate affected credentials if necessary; restore access only after privacy and functional checks. For application rollback, a previous version must not overwrite newer server revisions.
