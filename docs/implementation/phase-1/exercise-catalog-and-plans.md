# Phase 1 — PR 2: Offline exercise catalog and training plans

**Source branch:** `feat/phase1-exercise-catalog-plan-builder`, created from verified `main` at `671d546c6e4e40e9350e5a0f0fcd354d1b8b0a5a`.

## Scope and invariants

- **Data owner:** device-local ObjectBox. Custom exercise definitions and plans never enter Supabase in the initial backup scope; no network, authentication or health permissions.
- Reuse **all existing PR1 entities**, generated `objectbox-model.json`, and model UIDs **unchanged**.
- Seed 18 deterministic version-1 built-in exercises on first Train usage, idempotently. Never overwrite or delete a saved definition on bootstrap.
- Custom exercises can be created, renamed and archived; built-in definitions cannot be edited or archived.
- Training plans can be created, edited, reordered and archived with sets/rep range/rest prescriptions. Entire plan with all child rows is one ObjectBox transaction. Historical workout snapshots remain untouched.
- Existing archived definitions remain stored so old plans stay understandable; they cannot be picked for newly added exercises.
- Editing a plan or custom exercise requires its last observed `updatedAtMs` so stale editors cannot silently overwrite a more recent edit. The timestamp advances monotonically even for multiple edits in one millisecond.
- No training sessions are started in this PR. A plan is not a completed workout or an active session.

## Verification

- Native repository tests: built-in seed/reopen/idempotency; custom CRUD/soft archive; duplicate names; plan save/reorder/reopen; stale edit; invalid input; uniqueness rollback after a parent/header is written; archived reference retention.
- Flutter analyzer, formatting, widget tests and debug Android build via existing CI.
- UI smoke: narrow 320dp, 390dp, 700dp and 1024dp, text scale 2, light/dark, screen-reader control labels.
- Offline and process-death restore on real iOS and Android before release. No promise of cross-device plan restore.

## Deferred to later Phase 1 PRs

Recording workouts, live set edits, rest timer, progress calculations, saved workout history, watch input, cloud sync and health access.
