# Training library stage 1: catalogue backbone, implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A versioned, read-only exercise catalogue that can be authored as JSON in the repo, validated in CI, published to Supabase as one immutable release, read by signed-in clients through two RPCs, and rolled back, with the 18 existing exercises as release 1.

**Architecture:** Source JSON in `catalog/` is assembled by `scripts/catalog_build.py` into one canonical snapshot and checked by `scripts/catalog_validate.py`. Publishing and rollback are generated SQL migrations that call private functions, so they deploy through the existing reviewed `supabase-database` Codemagic job and are replayed by the existing pgTAP CI. Clients call `catalog_manifest()` and `catalog_snapshot(release)`; tables are not readable directly.

**Tech Stack:** Python 3.12 (stdlib + `jsonschema==4.23.0` already in `tool/requirements-ci.txt`), PostgreSQL/Supabase migrations, pgTAP, `unittest`.

**Spec:** `docs/superpowers/specs/2026-11-25-training-library-design.md` (sections 4.1, 4.2, 4.4, 4.5, 5.1 to 5.3, 7, 8 stage 1). Executors read both.

## Deviation from the spec (approved by the owner with this plan)

Spec 5.3 proposes a new manual Codemagic job that writes releases with a privileged connection. This plan instead publishes each release as a **generated migration** (`supabase/migrations/<ts>_catalog_release_<n>.sql`) that calls `northstar_private.publish_catalog_release(...)`. Reasons: no `codemagic.yaml` change or new credential path (AGENTS.md Codemagic rules), every release is reviewed in a PR, CI replays it against a clean database (the staging step), and the existing migration reconciliation check already guards hosted drift. Rollback is a generated migration calling `northstar_private.set_live_catalog_release(n)`. Task 7 updates the spec's section 5.3 to match.

## Running the database tests

`supabase test db` needs the Supabase CLI 2.81.3 and Docker. If the CLI is not installed, install that pinned version first. If Docker cannot start the stack in the execution environment, run the Python tests locally, push the branch, and use the `Supabase SQL and RLS` GitHub Actions check (`.github/workflows/supabase_sql.yml`, which replays every migration and runs pgTAP) as the result for the SQL steps; say so in the PR.

## Global Constraints

- Public repository: no project ref, URL, keys, real emails or personal data in `catalog/`, scripts, tests or docs (AGENTS.md "Secrets in a public repository"). Use `YOUR_PROJECT_REF` in docs.
- Exercise IDs: `builtin.v1.<slug>`, slug matches `^[a-z0-9]+(-[a-z0-9]+)*$`. The 18 existing IDs from `apps/mobile/lib/features/workouts/data/built_in_exercises.dart` appear unchanged. Templates `tpl.<slug>`, programs `prog.<slug>`. Never renamed, never reused, never removed (retire instead).
- Muscle vocabulary is exactly the Dart `Muscle` enum in `apps/mobile/lib/features/progress/muscle_recovery.dart`: `chest, shoulders, biceps, forearms, abs, obliques, quads, calves, traps, lats, lowerBack, triceps, glutes, hamstrings`.
- Coarse `muscleGroup` vocabulary: `Chest, Back, Legs, Shoulders, Arms, Core`.
- Modes: `reps_load`, `reps`, `duration`, `duration_load`.
- Prescription ranges: sets 1 to 30, reps 1 to 1000 with min ≤ max, rest 0 to 3600 s, duration 1 to 3600 s.
- Canonical snapshot bytes: `json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")`. Integers only (no floats anywhere in content). `sha256` is hex of SHA-256 over these bytes; `size_bytes` is their length. Stage 2's Dart client reproduces this exact canonical form.
- `schemaVersion` = 1, `minAppCatalogSchema` = 1 for release 1.
- Catalogue text is original BeyondRep writing; provenance `{"source": "BeyondRep original", "license": "MPL-2.0", "attribution": ""}`. No media fields.
- No user, health or account data in any catalogue table.
- Do not modify `prototypes/performance-v2/`, `LICENSE`, `.github/CODEOWNERS`, `codemagic.yaml`.

## Review Focus

1. **A published release is edited or deleted in a later migration.** Expect the immutability trigger to raise on UPDATE and DELETE of `catalog_releases` (Task 4 test `releases are immutable`).
2. **Phone asks for a release that is no longer live (publish or rollback race).** Expect `catalog_snapshot` to raise SQLSTATE `P0002` with message `catalog release not live`, never return stale content (Task 4).
3. **A content PR silently changes an existing exercise's mode, removes an ID, or reuses a retired slug.** Expect the validator, run against `catalog/releases.lock.json`, to reject it (Task 1 tests, Task 3 lock file).
4. **Building the same source twice gives different bytes (dict order, trailing newline, unicode escaping).** Expect identical SHA-256 (Task 2 determinism test, including a non-ASCII alias).
5. **Rollback to a release that was never published or is newer than any published.** Expect `set_live_catalog_release` to raise and the generator to refuse (Tasks 4 and 5).

---

## File structure

| Path | Responsibility |
| --- | --- |
| `catalog/schema/catalog.schema.json` | JSON Schema (2020-12) for one assembled snapshot |
| `catalog/exercises/*.json` | Source: each file is a JSON array of exercise objects |
| `catalog/templates/*.json`, `catalog/programs/*.json` | Source arrays (empty in stage 1; directories kept with `.gitkeep`) |
| `catalog/releases.lock.json` | Every published release: number, sha256, ids by kind, mode per exercise id, retired ids |
| `catalog/PROVENANCE.md`, `catalog/CHANGELOG.md` | Licence and release log |
| `scripts/catalog_validate.py` | `validate_snapshot(snapshot, lock) -> list[str]` |
| `scripts/catalog_build.py` | Assemble, canonicalize, hash; generate publish/rollback migrations; update lock |
| `tool/test_catalog_validate.py`, `tool/test_catalog_build.py`, `tool/test_catalog_content.py` | Unit tests, run by existing `contracts_ci.yml` discovery |
| `supabase/migrations/20261126000000_catalog_backbone.sql` | Tables, trigger, private publish/rollback functions, public RPCs, grants |
| `supabase/migrations/20261126000100_catalog_release_1.sql` | Generated: release 1 |
| `supabase/tests/catalog.test.sql` | pgTAP |
| `scripts/p2_08_hosted_rls.py`, `tool/test_p2_08_hosted_rls.py` | Hosted catalogue access audit |
| `docs/adr/0010-shared-training-catalogue.md`, `docs/CATALOG.md` | Decision and operating guide |

---

### Task 1: Snapshot schema and validator

**Files:**
- Create: `catalog/schema/catalog.schema.json`, `scripts/catalog_validate.py`
- Test: `tool/test_catalog_validate.py`

**Interfaces:**
- Produces: `scripts.catalog_validate.validate_snapshot(snapshot: dict, lock: dict) -> list[str]` (empty list means valid; each string is a human-readable error naming the offending id). `scripts.catalog_validate.EMPTY_LOCK: dict` = `{"releases": []}`. `scripts.catalog_validate.MUSCLES`, `MUSCLE_GROUPS`, `MODES`, `EQUIPMENT`, `CATEGORIES` (frozensets).
- Lock format consumed: `{"releases": [{"release": int, "sha256": str, "exercises": {id: mode}, "retired": [id], "templates": [id], "programs": [id]}]}`.

Snapshot shape is spec 4.4 exactly, plus `minAppCatalogSchema` (int) at top level and `standalone` (bool, default true) on templates. Equipment vocabulary: `barbell, dumbbell, kettlebell, machine, cable, band, bodyweight, bench, pull_up_bar, ez_bar, trap_bar, plate, box, rings, other`. Category vocabulary: `squat, hinge, lunge, push_horizontal, push_vertical, pull_horizontal, pull_vertical, carry, core, isolation, calf, conditioning, mobility`. Text limits: name ≤ 80, alias ≤ 60 (≤ 10 aliases), cue ≤ 160 (≤ 6 cues), description ≤ 1000, note ≤ 300. `status` ∈ `active, retired`.

- [ ] **Step 1: Write failing tests** in `tool/test_catalog_validate.py`, one per rule, each starting from a helper `valid_snapshot()` (two exercises: `builtin.v1.squat` reps_load, `builtin.v1.plank` duration; one template `tpl.test` using both correctly; one program `prog.test` with `week` = `["tpl.test", None, None, None, None, None, None]`, `daysPerWeek` 1) and mutating one thing:
  - `test_valid_snapshot_has_no_errors`: `validate_snapshot(valid_snapshot(), EMPTY_LOCK) == []`
  - `test_schema_violation_reported` (missing `exercises` key)
  - `test_float_anywhere_rejected` (`estimatedMinutes: 45.0`)
  - `test_duplicate_id_across_kinds` (template id equals an exercise id)
  - `test_bad_id_prefix_or_slug` (`builtin.v1.Bad_Slug`, `tpl-x`)
  - `test_unknown_muscle`, `test_no_primary_muscle`, `test_unknown_equipment`, `test_unknown_group`
  - `test_unknown_exercise_reference`, `test_unknown_template_reference`
  - `test_template_references_retired_exercise`
  - `test_week_must_have_seven_entries`, `test_program_needs_training_day`, `test_days_per_week_mismatch`
  - `test_ranges`: sets 0 and 31; repsMin 0; repsMin > repsMax; rest 3601; duration 0 and 3601 (subTests)
  - `test_reps_on_duration_exercise`, `test_duration_on_reps_exercise`, `test_both_reps_and_duration`
  - `test_mode_change_against_lock`: lock release 1 has `{"builtin.v1.squat": "reps"}` → error mentions `builtin.v1.squat`
  - `test_removed_id_against_lock`: lock lists `builtin.v1.deadlift`, snapshot lacks it
  - `test_retired_slug_reused`: lock `retired` contains `builtin.v1.old`, snapshot has active `builtin.v1.old`
  - `test_kind_change_against_lock`: lock lists `tpl.test` under `programs`
  - `test_release_must_exceed_lock`: lock has release 1, snapshot `release` 1 → error

- [ ] **Step 2: Run** `python3 -m unittest tool.test_catalog_validate -v` from repo root. Expected: FAIL (`ModuleNotFoundError: scripts.catalog_validate`).

- [ ] **Step 3: Write `catalog/schema/catalog.schema.json`** (structure, types, vocabularies as `enum`, `additionalProperties: false`, integer types, string lengths) **and implement `validate_snapshot`** in `scripts/catalog_validate.py`: run `jsonschema.Draft202012Validator` first and return its errors if any; then the cross-reference, range, mode and lock rules in plain Python. Floats are rejected by a recursive walk (the schema's `integer` type accepts `45.0` in jsonschema, so the walk is required). Duration rules: a `duration`/`duration_load` exercise prescription must have `durationSeconds` and no reps; `reps_load`/`reps` must have `repsMin` and `repsMax` and no `durationSeconds`.

- [ ] **Step 4: Run** the same command. Expected: all PASS.

- [ ] **Step 5: Commit** `git add catalog/schema scripts/catalog_validate.py tool/test_catalog_validate.py && git commit -m "feat(catalog): snapshot schema and validator"`

### Task 2: Build, canonical bytes and hashing

**Files:**
- Create: `scripts/catalog_build.py`
- Test: `tool/test_catalog_build.py`

**Interfaces:**
- Consumes: `validate_snapshot`, `EMPTY_LOCK` (Task 1).
- Produces:
  - `assemble(root: Path, release: int, published_at: str, schema_version: int = 1, min_app_schema: int = 1) -> dict`: reads `root/exercises/*.json`, `root/templates/*.json`, `root/programs/*.json` (sorted file order, each an array), concatenates, sorts each list by `id`, adds `provenance` from the Global Constraints.
  - `canonical_bytes(snapshot: dict) -> bytes` (exact form in Global Constraints).
  - `digest(snapshot: dict) -> tuple[str, int]` returns `(sha256_hex, size_bytes)`.
  - `load_lock(path: Path) -> dict`, `lock_entry(snapshot: dict, sha256: str) -> dict` (shape from Task 1).

- [ ] **Step 1: Write failing tests**:
  - `test_assemble_sorts_and_merges`: two exercise files in a temp dir in reverse id order → output ids sorted, both present, `templates == []`.
  - `test_canonical_bytes_deterministic`: same input assembled twice with dict keys inserted in different orders and an alias `"Sumo-Kreuzheben ü"` → identical bytes, bytes contain the raw UTF-8 `ü` (not `ü`), no spaces after `:` or `,`.
  - `test_digest_matches_hashlib`: `digest(s) == (hashlib.sha256(canonical_bytes(s)).hexdigest(), len(canonical_bytes(s)))`.
  - `test_lock_entry_records_modes_and_retired`.

- [ ] **Step 2: Run** `python3 -m unittest tool.test_catalog_build -v`. Expected: FAIL (import error).
- [ ] **Step 3: Implement** the four functions above in `scripts/catalog_build.py`.
- [ ] **Step 4: Run** again. Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat(catalog): deterministic snapshot build and hashing"`

### Task 3: Starter content (the 18 existing exercises)

**Files:**
- Create: `catalog/exercises/legacy.json`, `catalog/templates/.gitkeep`, `catalog/programs/.gitkeep`, `catalog/releases.lock.json` (`{"releases": []}`), `catalog/PROVENANCE.md`, `catalog/CHANGELOG.md`
- Test: `tool/test_catalog_content.py`

**Interfaces:**
- Consumes: `assemble`, `validate_snapshot`, `load_lock` (Tasks 1 and 2).

Each of the 18 entries in `built_in_exercises.dart` becomes an exercise with id `builtin.v1.<id>`, the same `name`, `muscleGroup` = the Dart `muscle`, `mode` = the Dart `mode`, `primaryMuscles`/`secondaryMuscles` from the enum vocabulary, `equipment` list, `category` from the vocabulary, 0 to 3 aliases and 2 to 4 short original technique cues, `status: "active"`.

- [ ] **Step 1: Write failing tests** in `tool/test_catalog_content.py`:
  - `test_repo_catalog_validates`: `validate_snapshot(assemble(ROOT/"catalog", next_release, "2026-11-26T00:00:00Z"), load_lock(...)) == []` where `next_release` is 1 + the highest release in the lock (1 when empty).
  - `test_legacy_ids_present_with_same_names_and_modes`: parse `built_in_exercises.dart` with a regex over `id:`, `name:`, `muscle:`, `mode:` fields; every one maps to a catalogue exercise with matching `name`, `muscleGroup`, `mode`.
  - `test_muscle_vocabulary_matches_dart_enum`: regex-extract the `enum Muscle { ... }` members from `muscle_recovery.dart`; equals `MUSCLES`.
  - `test_no_media_or_url_fields`: no key in any exercise matches `image|video|gif|url|media` and no string value contains `http`.
- [ ] **Step 2: Run** `python3 -m unittest tool.test_catalog_content -v`. Expected: FAIL (files missing).
- [ ] **Step 3: Write the content files.** `PROVENANCE.md` states: original BeyondRep text, licence MPL-2.0 (repository licence), no third-party text or media, any checklist source used for coverage is named with its licence. `CHANGELOG.md` starts with an "Unreleased" heading.
- [ ] **Step 4: Run** again. Expected: PASS.
- [ ] **Step 5: Commit** `git commit -m "feat(catalog): starter content for the 18 existing exercises"`

### Task 4: Backend schema, private publish/rollback and read RPCs

**Files:**
- Create: `supabase/migrations/20261126000000_catalog_backbone.sql`, `supabase/tests/catalog.test.sql`

**Interfaces:**
- Produces (SQL):
  - `public.catalog_releases(release int primary key check (release > 0), schema_version int not null, min_app_schema int not null, content jsonb not null, sha256 text not null check (sha256 ~ '^[0-9a-f]{64}$'), size_bytes int not null check (size_bytes > 0), published_at timestamptz not null, created_at timestamptz not null default now())`, RLS enabled, no policies, `revoke all ... from anon, authenticated, public`.
  - `public.catalog_live(singleton boolean primary key default true check (singleton), release int not null references public.catalog_releases(release), updated_at timestamptz not null default now())`, same RLS and revokes.
  - Trigger `catalog_releases_immutable` (BEFORE UPDATE OR DELETE) raising `catalog releases are immutable`.
  - `northstar_private.publish_catalog_release(p_release int, p_schema_version int, p_min_app_schema int, p_content jsonb, p_sha256 text, p_size_bytes int, p_published_at timestamptz) returns void`: requires `p_release` greater than every existing release; requires `p_content->>'release'` = `p_release` and `p_content->>'schemaVersion'` = `p_schema_version`; inserts the row and upserts `catalog_live` to it, in the calling transaction.
  - `northstar_private.set_live_catalog_release(p_release int) returns void`: raises if the release does not exist; sets `catalog_live.release`.
  - Both private functions: `revoke execute ... from public, anon, authenticated`.
  - `public.catalog_manifest() returns jsonb` (`security definer`, `stable`, `set search_path = ''`): `{"release", "schemaVersion", "minAppCatalogSchema", "publishedAt", "sha256", "sizeBytes", "url"}` for the live row; `url` = `'/rest/v1/rpc/catalog_snapshot'`. Returns `null` when no row is live.
  - `public.catalog_snapshot(p_release int) returns jsonb` (`security definer`, `stable`, `set search_path = ''`): returns `content` when `p_release` is live; otherwise `raise exception 'catalog release not live' using errcode = 'P0002'`.
  - `revoke execute on both public functions from public, anon; grant execute to authenticated`.

- [ ] **Step 1: Write the failing pgTAP file** `supabase/tests/catalog.test.sql` following `receipt_prune_schedule.test.sql` style (`begin; ... select plan(N); ... select * from finish(); rollback;`). Publish two synthetic releases inside the test with `northstar_private.publish_catalog_release` using releases 900 and 901 (content `{"release": 900, "schemaVersion": 1, "exercises": [], "templates": [], "programs": []}` and sha `repeat('a',64)`), then assert:
  - `anon` lacks EXECUTE on `catalog_manifest()` and `catalog_snapshot(integer)`; `authenticated` has it.
  - `anon` and `authenticated` lack SELECT, INSERT, UPDATE, DELETE on both tables.
  - `anon`, `authenticated`, `public` lack EXECUTE on both private functions.
  - After publishing 900 then 901: manifest `release` = 901 and `url` = `/rest/v1/rpc/catalog_snapshot`.
  - `catalog_snapshot(901)` returns content with `release` 901; `catalog_snapshot(900)` throws `P0002` (`throws_ok`).
  - Publishing 900 again throws; publishing 899 throws; mismatched `content.release` throws.
  - `releases are immutable`: UPDATE and DELETE on `catalog_releases` throw.
  - `set_live_catalog_release(900)` makes manifest release 900 and `catalog_snapshot(901)` throw; `set_live_catalog_release(12345)` throws.
  - Run the reads as the authenticated role via `set local role authenticated` with a synthetic `request.jwt.claims` like the existing tests do; reset role after.
- [ ] **Step 2: Run** `supabase start && supabase db reset && supabase test db` (local stack, CLI 2.81.3 as in CI). Expected: catalog test FAILS (relations and functions missing); other tests pass.
- [ ] **Step 3: Write the migration** with the objects above.
- [ ] **Step 4: Run** `supabase db reset && supabase test db`. Expected: all files PASS.
- [ ] **Step 5: Commit** `git commit -m "feat(supabase): read-only catalogue releases with private publish and rollback"`

### Task 5: Release and rollback migration generator, release 1

**Files:**
- Modify: `scripts/catalog_build.py` (add CLI)
- Modify: `tool/test_catalog_build.py`
- Create (generated): `supabase/migrations/20261126000100_catalog_release_1.sql`; update `catalog/releases.lock.json`, `catalog/CHANGELOG.md`
- Modify: `supabase/tests/catalog.test.sql` (assert release 1 is live after migrations, before the synthetic publishes)

**Interfaces:**
- Consumes: Tasks 1 to 4.
- Produces:
  - `render_publish_migration(snapshot: dict, sha256: str, size_bytes: int) -> str`: a SQL file calling `northstar_private.publish_catalog_release(...)` with the canonical JSON as a dollar-quoted literal using tag `$catalog$` (generator raises if the content contains `$catalog$`), cast to `jsonb`. Header comment: release number, sha256, "Generated by scripts/catalog_build.py; do not edit".
  - `render_rollback_migration(target: int, lock: dict) -> str`: raises `ValueError` unless `target` is a published release in the lock; body calls `northstar_private.set_live_catalog_release(target)`.
  - CLI: `python3 scripts/catalog_build.py check` (assemble next release, validate against lock, print sha and size, exit 1 on errors); `publish --timestamp YYYYMMDDHHMMSS --published-at ISO8601` (validate, write `supabase/migrations/<ts>_catalog_release_<n>.sql`, append lock entry, prepend a CHANGELOG entry with release, date, sha256 and counts); `rollback --to N --timestamp ...` (write `<ts>_catalog_rollback_to_<n>.sql`; lock unchanged).
- [ ] **Step 1: Write failing tests**: `test_publish_migration_contains_canonical_json_and_sha`, `test_publish_refuses_dollar_tag_in_content`, `test_rollback_requires_published_release` (unknown 7 → `ValueError`), `test_publish_cli_writes_migration_and_lock` (temp repo root with copied `catalog/`; lock gains release 1 with all 18 modes), `test_check_cli_exits_nonzero_on_invalid` (inject a bad muscle).
- [ ] **Step 2: Run** `python3 -m unittest tool.test_catalog_build -v`. Expected: new tests FAIL.
- [ ] **Step 3: Implement** the renderers and CLI (`argparse`, paths relative to the repo root found from `__file__`).
- [ ] **Step 4: Run** tests. Expected: PASS.
- [ ] **Step 5: Generate release 1**: `python3 scripts/catalog_build.py publish --timestamp 20261126000100 --published-at 2026-11-26T00:00:00Z`. Add to `catalog.test.sql`, before the synthetic publishes: manifest `release` = 1, `sha256` equals the lock's sha for release 1 (inline the value), and `jsonb_array_length(catalog_snapshot(1)->'exercises')` = 18. Run `supabase db reset && supabase test db`. Expected: PASS. Run `python3 -m unittest discover -s tool -p 'test_*.py'`. Expected: PASS (includes migration reconciliation and layout tests).
- [ ] **Step 6: Commit** `git commit -m "feat(catalog): release and rollback migration generator; publish release 1"`

### Task 6: Hosted catalogue access audit

**Files:**
- Modify: `scripts/p2_08_hosted_rls.py`, `tool/test_p2_08_hosted_rls.py`

**Interfaces:**
- Consumes: the existing `Reply`, `AuditFailure`, `_require` and `call(method, path, token=None, query=None, payload=None) -> Reply` requester in `p2_08_hosted_rls.py`.
- Produces: `run_catalog_audit(call: Callable[..., Reply], token: str) -> str` (summary line) and a call to it from `main()` after `run_audit`.

Checks, each failing with a distinct `AuditFailure` code: anonymous `POST /rest/v1/rpc/catalog_manifest` is denied (401 or 403, or 404 for a function hidden from `anon`); authenticated manifest returns 200 with integer `release` ≥ 1 and a 64-hex `sha256`; authenticated `catalog_snapshot` with that release returns 200 with matching `release`; authenticated `catalog_snapshot` with `release + 1000` is an error status; authenticated `GET /rest/v1/catalog_releases?select=release` and `/rest/v1/catalog_live` return 401/403/404 or an empty array (never rows); authenticated `POST /rest/v1/rpc/publish_catalog_release` is not 2xx.
- [ ] **Step 1: Write failing tests** in `tool/test_p2_08_hosted_rls.py` using a small fake `call` per test: `test_catalog_audit_passes_on_locked_down_backend`, `test_catalog_anonymous_manifest_leak`, `test_catalog_table_rows_leak`, `test_catalog_stale_release_served`, `test_catalog_publish_reachable`, `test_catalog_manifest_malformed_sha`.
- [ ] **Step 2: Run** `python3 -m unittest tool.test_p2_08_hosted_rls -v`. Expected: new tests FAIL.
- [ ] **Step 3: Implement** `run_catalog_audit` and wire it into `main()`.
- [ ] **Step 4: Run** again. Expected: PASS. Live hosted run stays a manual release gate (record "not run").
- [ ] **Step 5: Commit** `git commit -m "test(supabase): hosted catalogue access audit"`

### Task 7: ADR, docs and layout

**Files:**
- Create: `docs/adr/0010-shared-training-catalogue.md`, `docs/CATALOG.md`
- Modify: `docs/REPOSITORY_LAYOUT.md` (add `catalog/` row), `docs/ARCHITECTURE.md` (catalogue data flow), `docs/ROADMAP.md` (issue #63 tracker, stage 1 "in source, not deployed"), `docs/SUPABASE_CODEMAGIC_DEPLOY.md` (catalogue releases deploy as migrations through `supabase-database`), `docs/superpowers/specs/2026-11-25-training-library-design.md` section 5.3 (migration-based publishing, matching this plan), `tool/test_repository_layout.py` (add `catalog/schema/catalog.schema.json` and `catalog/releases.lock.json` to required entries)
- Test: `tool/test_repository_layout.py`

ADR-0010 records: shared, non-personal reference content published from Supabase; read-only RPC access for authenticated users only; releases immutable, one live pointer, rollback withdraws; published by reviewed generated migrations; phone cache outside account-partitioned ObjectBox (stage 2) with user copies always account-scoped and local-only; does not change ADR-0005 backup scope; no health or user data. Status: Accepted, decided by the owner on 2026-11-25. `docs/CATALOG.md` covers format, vocabularies, validation rules, canonical bytes and checksum, `check`/`publish`/`rollback` commands, deploying with the `supabase-database` job, provenance and licence, and that live hosted checks are a release gate.

- [ ] **Step 1: Add the two required entries** to `tool/test_repository_layout.py`; run `python3 -m unittest tool.test_repository_layout -v`. Expected: PASS (files exist from Tasks 1 and 3). If they were missing it would FAIL; confirm by temporarily renaming one locally, then restore.
- [ ] **Step 2: Write the docs** listed above.
- [ ] **Step 3: Run the full repo checks**: `python3 -m unittest discover -s tool -p 'test_*.py'` and `supabase db reset && supabase test db`. Expected: all PASS. `apps/mobile` is untouched in this stage, so Flutter checks are not required; state that in the PR.
- [ ] **Step 4: Commit** `git commit -m "docs: ADR-0010 and catalogue operating guide"`

## Out of scope for stage 1

Phone cache and client (stage 2), sync payload changes (stages 3 and 4), any template or program content (stages 6 and 7), and deploying release 1 to the hosted project (owner runs the `supabase-database` job after merge).
