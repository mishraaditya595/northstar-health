# ADR-0010 — Shared training catalogue

**Status:** **Accepted** — decided by the human owner on 2026-11-25.
**Does not alter:** [ADR-0005](0005-mandatory-auth-and-workout-sync.md) backup scope or [ADR-0003](0003-data-cloud-health.md) ownership. Design: [`docs/superpowers/specs/2026-11-25-training-library-design.md`](../superpowers/specs/2026-11-25-training-library-design.md). Tracker: issue #63.

## Context

New users start with 18 hard-coded exercises and no ready plans. The product needs a growing library of exercises, workout templates and programs that can change after release without an app update. That content is the same for everyone, so it is not user data and does not belong in the account-scoped backup.

## Decision

1. **Shared reference content from Supabase.** The catalogue is non-personal, identical for all users and holds no user, health or account data.
2. **Read-only access for signed-in users only.** Clients call `catalog_manifest()` and `catalog_snapshot(release)`. Both tables have RLS enabled with no policies and no client grants. `anon` has no access.
3. **Immutable releases, one live pointer.** A release row is never updated or deleted (trigger enforced). `catalog_live` points at one release. `catalog_snapshot` serves only the live release, so rolling back withdraws a bad release.
4. **Published by reviewed, generated migrations.** `scripts/catalog_build.py` renders each release and each rollback as a migration that calls a private function with no client access. They deploy through the existing manual `supabase-database` job, with no new credential path and no `codemagic.yaml` change. CI replays them against a clean database.
5. **Phone cache outside account-partitioned ObjectBox (stage 2).** The cache is a validated snapshot file, because the content is shared. Anything a user takes from the catalogue becomes their own local, editable copy, always account-scoped and local-only.
6. **Backup scope unchanged.** Plans, programs and templates copied from the catalogue are not backed up in this phase (ADR-0005).

## Consequences

- Content changes are pull requests with a deterministic checksum and a lock file that forbids removing IDs, changing an exercise mode or reusing a retired slug.
- A rollback never changes user data, because user copies are independent of the catalogue.
- The hosted signed-JWT audit gains catalogue checks; the live run stays a manual release gate.
