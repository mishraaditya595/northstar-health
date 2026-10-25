# ADR-0005 — Mandatory accounts and automatic workout lifecycle sync

**Status:** **Proposed — awaiting explicit owner approval on PR #13.** The user previously instructed mandatory account creation and automatic synchronization of each workout, but has not signed off this ADR's complete privacy, retention, deletion or export policy. This document cannot approve itself.  
**Supersedes:** ADR-0003 and earlier Phase 1/2 roadmaps **only where they specify optional accounts, guest access for new users, and completed-workout-only cloud backup**. All privacy and local-first constraints not explicitly changed remain in force.

## Decision and rationale

NorthStar requires a verified account before a new user can access workout features. Initial signup/sign-in requires network access. Once a user has authenticated and the device has a securely bound local account identity, the user can log workouts offline. A revoked or unknown account must never be treated as another user's owner; auth refresh failures pause cloud transfer, not already-authorized local saves.

Every NorthStar-authored phone workout is represented in Supabase by an authenticated, versioned aggregate, including `inProgress`, `paused`, `completed` and `discarded` lifecycle states, with deletion tombstones. Only recorded sets and essential historical exercise snapshots are synchronized, not recovery UI checkpoints, rest timers, platform measurements or watch sensor streams. Completed-session statistics are calculated on the server from validated sets; unfinished/discarded sessions never present completed totals. The phone commits workout changes and a durable outbox entry atomically; sync sends automatically when authenticated connectivity returns.

This is **synchronization plus backup**, not an unrestricted replication of ObjectBox. Source attribution is required: the initial RPC admits only `northstar_phone`, and must reject missing origin and external/health-provider workouts. Watch-origin implementation remains a separate policy and transport review.

## Owner decisions required before ADR acceptance

The owner has already requested **mandatory accounts** and **automatic synchronization of every workout, including active and unfinished sessions**. The following additional policy choices are **proposals, not approved facts**, and must be explicitly reviewed and approved in PR #13:

1. **Active-session disclosure and acknowledgement.** During onboarding, before the first cloud upload, clearly disclose that **sets, exercise labels, repetitions, loads, workout state and timestamps will automatically leave the device even when a workout is unfinished**, once connectivity returns. Provide links to the privacy notice and require an explicit acknowledgement. Do not silently enable upload of historical Phase 1 guest data. If acknowledgement has not occurred, keep pending data local and prevent activation of cloud sync; resolve the required-account/onboarding UX before release.
2. **Workout retention.** Proposed policy: retain workouts (completed, in-progress, paused and discarded) while the account remains active unless the user deletes them; delete the payload immediately on a verified delete and retain the *tombstone* until **the account itself is deleted**, rather than expire tombstones and risk resurrection by an offline device. The old workout UUID must never be implicitly reused; a new workout gets a new UUID. Continue a 90-day expiry for hash-only request receipts, with global scheduled pruning still a release gate. Determine any separate legal retention obligations before shipping.
3. **User export.** Provide an authenticated, owner-scoped, machine-readable JSON export of all current workout history and draft snapshots (schema version, IDs, timestamps, exercises and sets), excluding access tokens and other accounts' records. Export must be available before account deletion. Document what is *not* included, such as custom plans and platform-owned physiological records.
4. **Account deletion.** Provide a clearly labeled in-app delete-account workflow requiring an online, freshly verified session and explicit confirmation. Warn about pending offline changes and irreversible deletion; pause sync queues, revoke sessions, delete account-related database records and tombstones with verified server-side authorization, then safely clear or lock local owner-bound data. The server must not silently re-associate orphaned records to another account. An operational retention/deletion runbook, status feedback, and cross-device verification are needed before release.

**Merge rule:** Marking ADR-0005 accepted requires the human owner to comment on PR #13 approving *both* the product policy changes and the final privacy/retention/export/deletion terms. Agent-authored text and past general project instructions are not a document-level approval. Do not merge while this approval is missing.

## Privacy and identity rules

- Supabase publishable keys and project URL are not privileged secrets, but the public open-source app must **never contain service-role keys, secret keys, personal access tokens, database passwords or real user data**. The Supabase Auth user JWT plus RLS and a server-enforced authenticated RPC control access.
- Workout data is sensitive, including active session sets. Update privacy policy/data retention disclosures **before release**. No physiological measurements, HR/HRV, sleep, steps, SpO₂, GPS trails, external workouts, custom plan definitions, platform permissions or local ObjectBox files go to Supabase.
- Every server mutation uses a stable operation UUID, an account/workout ID, a server revision CAS and server-computed results. Conflicts are explicit, with no last-write-wins.
- Anonymous Supabase Auth identities are **not** sufficient; a verified non-anonymous user is required.
- Authentication credentials use vetted secure OS storage and are never stored in the ObjectBox workout tables or diagnostics.
- Historical Phase 1 anonymous local workouts may exist. On first sign-in explicitly offer a one-time account-association migration, showing the account and scope; do **not** silently bind local history to whoever signs in. Refusal leaves legacy records isolated and local; never erase or upload them without consent. This is migration support only, **not an ongoing guest mode**.
- Account switching requires suspending the previous owner's outbox, clearing in-memory identity-bound views, requiring the new owner's auth and guarding against cross-account reads/uploads. Unsynced changes remain recoverable and are never reassigned automatically.

## Reliability and retention

- Default is automatic sync for active and completed states, but absence of connectivity never blocks an ObjectBox commit. User-facing status distinguishes saved locally, queued, synced, conflict, and processing completion. Initial sign-in cannot occur offline.
- The server validates a strict versioned DTO before locking; uses a per-user transaction lock plus conditional revision update; allocates an account-local, transactionally ordered change cursor; stores only a SHA-256 request digest for idempotent receipt matching.
- Workout payloads are deleted from the main aggregate upon deletion. Hash-only replay receipts retain for **90 days**, then are opportunistically purged on the next account sync; a verified administrative schedule is still required to purge receipts for inactive accounts. After expiry, an old retry may receive a revision conflict rather than an original replay ACK; clients must reconcile. Tombstones are kept until a tested multi-device catch-up/retention protocol is approved. Receipt pruning never removes tombstones.
- Cross-device processing and restoration must remain explicit about lifecycle conflicts. Do not claim full in-progress checkpoint restoration until phone implementation supports it. Cloud sync does not restore custom plans, exercise catalogs or app preferences in Phase 2.

## Implications and roll-out gates

Update `AGENTS.md`, `docs/CLOUD_SYNC.md`, `docs/ROADMAP.md`, `docs/ARCHITECTURE.md`, `docs/OBJECTBOX.md`, `docs/adr/0003-data-cloud-health.md`, `supabase/README.md`, implementation docs and public user-facing disclosures to reflect this decision. Require RLS negative tests, malformed-payload tests, idempotency/revision tests, cross-account/restore tests, schema-upgrade tests and Android/iOS QA. This ADR records the owner's changed requirements; it does **not** approve an untested PR for merge or release.

## Rollback

Do **not** revert the schema by dropping tables containing workout data. Emergency stop: revoke authenticated RPC EXECUTE and disable mobile sync while preserving local outboxes and server records. Roll forward with a tested corrective migration and rotate affected credentials if necessary; restore access only after privacy and functional checks. For application rollback, a previous version must not overwrite newer server revisions.
