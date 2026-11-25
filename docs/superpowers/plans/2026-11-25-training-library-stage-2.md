# Training library stage 2: phone catalogue cache, implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The app downloads the live catalogue release from Supabase, verifies it, keeps it as an atomically swapped file shared across accounts, refreshes it at most once a day in the background, and offers catalogue exercises next to local ones in the exercise pickers and the Exercises page, copying a catalogue exercise into the account's ObjectBox store when it is picked.

**Architecture:** New feature module `apps/mobile/lib/features/catalog/` with a pure-Dart `domain/` (canonical JSON, SHA-256, snapshot parsing and validation, exercise choices), `data/` (Supabase transport, file store, repository with coalesced refresh) and `application/` (Riverpod providers and a lifecycle refresh host). Workouts gain one repository method to materialize a catalogue exercise. Train screens use one shared picker sheet.

**Tech Stack:** Flutter 3.47.7 / Dart, Riverpod 3, supabase_flutter 2.18.3, ObjectBox 5, `crypto` 3.0.7 (already in `pubspec.lock` as a transitive dependency; this plan makes it direct).

**Spec:** `docs/superpowers/specs/2026-11-25-training-library-design.md` sections 4.4, 4.5, 6.1, 6.2 (exercise materialization and picker only) and 8 stage 2. Stage 1 operating guide: `docs/CATALOG.md`. Executors read both.

## Decisions this plan makes (owner sees them with the plan)

- **New direct dependency `crypto: 3.0.7`** (Dart team package, already resolved transitively). AGENTS.md lists new dependencies as needing owner approval; approving this plan approves it.
- **Cache location** `${defaultStoreDirectory().path}/northstar_catalog/<projectHost>/` using the `defaultStoreDirectory()` the account stores already use, so no `path_provider` dependency. Per backend host like account stores; shared across accounts on that host.
- **The snapshot file is self-describing** (it is the canonical snapshot bytes, which contain `release`). A separate `meta.json` holds only `lastCheckedAtMs`. A crash between writes can therefore never pair a snapshot with the wrong metadata.
- **No ObjectBox model change in stage 2.** Primary/secondary muscles on local definitions arrive in stage 3. A materialized definition stores name, coarse `muscleGroup`, an equipment label, category and mode in the existing fields.
- **Materialize at pick time.** Picking a catalogue exercise in a picker upserts its local definition immediately (idempotent); no plan or session write is involved.

## Running the Flutter checks

Flutter 3.47.7 stable must be installed (`flutter --version`). If it is missing, install that exact version. If installation is impossible in the execution environment, write tests and code carefully, push the branch, and treat the `mobile` GitHub Actions job (`.github/workflows/mobile_ci.yml`) as the result; say so in the PR. From `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`.

## Global Constraints

- AGENTS.md: UI renders Riverpod state; ObjectBox, files and Supabase only behind repositories; no raw `TextField`, `AlertDialog`, `showDialog`, `showModalBottomSheet`, `ChoiceChip`/`FilterChip` or `SnackBar` in features (`test/design_kit_guard_test.dart`). Use `NsTextField`, `showNsSheet`, `NsListCard`, `NsChip`, `NsTag`, `SectionHeading` from `lib/core/design/`.
- Canonical bytes must equal the Python form `json.dumps(obj, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")`: object keys sorted by Unicode code point, no whitespace, strings escaped exactly as Python does with `ensure_ascii=False` (only `"`, `\\`, and control characters U+0000 to U+001F escaped; `\n`, `\r`, `\t`, `\b`, `\f` use the short forms, other controls `\u00XX` lowercase hex), integers in plain decimal. A double anywhere is an error.
- `supportedCatalogSchema = 1`. A manifest whose `minAppCatalogSchema` is greater is "outdated app".
- RPC names: `catalog_manifest` (no params), `catalog_snapshot` (param `p_release`). Manifest keys: `release`, `schemaVersion`, `minAppCatalogSchema`, `publishedAt`, `sha256`, `sizeBytes`, `url`.
- Freshness window 24 hours. Timeouts: manifest 10 s, snapshot 20 s.
- Only a verified, non-anonymous, unexpired session for the bound account may call the RPCs (reuse `matchesCloudWorkoutSession` from `lib/features/sync/cloud_session_guard.dart`).
- Catalogue IDs start with `builtin.v1.`; custom exercise IDs never do (`saveCustomExercise` already rejects `builtin.` prefixes).
- No health, user or account data in the catalogue cache directory. Logs and failure kinds never include response bodies.
- Copy (exact):
  - Unavailable, no cache: `The exercise library hasn't downloaded yet. Your own exercises and the basics still work.` with a `Retry` button.
  - Outdated app: `Update BeyondRep to get the latest exercises.`
  - Refresh failed with a cache: no banner (silent); pull-to-refresh failure shows `Couldn't update the exercise library. Showing the saved copy.` via `showNsMessage` (`lib/core/design/dialogs.dart`).

## Review Focus

1. **Crash or kill during a download or write** (stale `snapshot.json.tmp`, truncated `snapshot.json`): on next start the temp file is deleted, an unparsable or invalid snapshot file is deleted and treated as "no cache", and the app never shows a partial catalogue (Task 3 and Task 5 tests).
2. **Rollback race:** the manifest names release N, then `catalog_snapshot(N)` fails with `P0002`: keep the cache, do not update `lastCheckedAtMs`, report `notLive` (Task 5).
3. **Clock moved backwards** so `lastCheckedAtMs` is in the future: treat as stale and check (Task 5).
4. **Account switch while a refresh is in flight:** the old scope's repository is disposed; its write still lands as a valid shared file; the new scope loads that file; no ObjectBox write happens from the refresh (Task 6).
5. **Anonymous or expired session, or signed out:** no network call, no `lastCheckedAtMs` update, result `unauthorized` (Tasks 4 and 5).

---

## File structure

| Path | Responsibility |
| --- | --- |
| `lib/features/catalog/domain/canonical_json.dart` | `canonicalJsonBytes`, `sha256Hex` |
| `lib/features/catalog/domain/catalog_models.dart` | `CatalogSnapshot`, `CatalogExercise`, `CatalogManifest`, `CatalogFormatException` |
| `lib/features/catalog/domain/catalog_parser.dart` | `parseCatalogSnapshot`, `parseCatalogManifest`, `supportedCatalogSchema` |
| `lib/features/catalog/domain/exercise_choices.dart` | `ExerciseChoice`, `buildExerciseChoices`, `equipmentLabel` |
| `lib/features/catalog/data/catalog_file_store.dart` | Atomic file cache |
| `lib/features/catalog/data/catalog_transport.dart` | `CatalogTransport`, `SupabaseCatalogTransport` |
| `lib/features/catalog/data/catalog_repository.dart` | Load, coalesced refresh, state |
| `lib/features/catalog/application/catalog_providers.dart` | Providers |
| `lib/features/catalog/application/catalog_refresh_host.dart` | Lifecycle widget that triggers refresh |
| `lib/features/workouts/domain/workout_library_repository.dart`, `.../data/objectbox_workout_library_repository.dart` | `materializeCatalogExercise` |
| `lib/features/train/exercise_picker_sheet.dart` | Shared picker used by plan editor and active workout |
| `lib/features/train/exercise_catalog_page.dart` | Union list, alias search, status, pull to refresh |
| `lib/features/account/account_gate.dart` | Wire directory provider and refresh host |
| Tests under `test/catalog/`, `test/workouts/`, `test/train/` | |

---

### Task 1: Canonical JSON and SHA-256, matched against release 1

**Files:**
- Modify: `apps/mobile/pubspec.yaml` (add `crypto: 3.0.7` under `dependencies`), `apps/mobile/pubspec.lock` (via `flutter pub get`; only the `crypto` entry's `dependency:` line should change to `"direct main"`)
- Create: `lib/features/catalog/domain/canonical_json.dart`
- Test: `test/catalog/canonical_json_test.dart`

**Interfaces:**
- Produces: `Uint8List canonicalJsonBytes(Object? value)` (throws `ArgumentError` on `double`, non-string map keys, or unsupported types); `String sha256Hex(List<int> bytes)`.

- [ ] **Step 1: Write failing tests:**
  - `sorts keys by code point and removes whitespace`: `{'b': 1, 'a': [true, null, 'x']}` → `{"a":[true,null,"x"],"b":1}`.
  - `keeps non-ASCII as UTF-8`: `{'n': 'Sumo-Kreuzheben ü'}` bytes contain `0xC3 0xBC`.
  - `escapes like Python`: `'a"b\\c\n\t\u0001'` → `"a\"b\\c\n\t\u0001"` (literal backslash sequences), and `'/'` is not escaped.
  - `rejects doubles`: `canonicalJsonBytes({'x': 45.0})` throws `ArgumentError`.
  - `matches published release 1`: read `../../supabase/migrations/20261126000100_catalog_release_1.sql`, take the text between the first `$catalog$` and the next `$catalog$`, `jsonDecode` it, and assert `utf8.decode(canonicalJsonBytes(decoded)) == body` and `sha256Hex(canonicalJsonBytes(decoded))` equals the `sha256` of release 1 in `../../catalog/releases.lock.json` (read it, do not hard-code).
- [ ] **Step 2: Run** `flutter test test/catalog/canonical_json_test.dart`. Expected: FAIL (file missing).
- [ ] **Step 3: Add the dependency and implement** both functions (recursive writer into a `StringBuffer`, then `utf8.encode`; `crypto`'s `sha256.convert(bytes).toString()`).
- [ ] **Step 4: Run** the test. Expected: PASS.
- [ ] **Step 5: Commit** `feat(catalog): canonical JSON and SHA-256 matching the published release`

### Task 2: Snapshot and manifest parsing with validation

**Files:**
- Create: `lib/features/catalog/domain/catalog_models.dart`, `lib/features/catalog/domain/catalog_parser.dart`
- Test: `test/catalog/catalog_parser_test.dart`

**Interfaces:**
- Consumes: Task 1.
- Produces:
  - `const supportedCatalogSchema = 1;`
  - `class CatalogExercise { String id; String name; List<String> aliases; String muscleGroup; List<String> primaryMuscles; List<String> secondaryMuscles; List<String> equipment; String category; String mode; List<String> cues; bool retired; }` (const constructor, all final).
  - `class CatalogSnapshot { int release; int schemaVersion; int minAppCatalogSchema; String publishedAt; String sha256; List<CatalogExercise> exercises; List<Map<String, Object?>> templates; List<Map<String, Object?>> programs; }` plus `Iterable<CatalogExercise> get activeExercises`.
  - `class CatalogManifest { int release; int schemaVersion; int minAppCatalogSchema; String publishedAt; String sha256; int sizeBytes; }`.
  - `class CatalogFormatException implements Exception { final String code; }` with codes used below.
  - `CatalogSnapshot parseCatalogSnapshot(Object? json, {String? expectedSha256})`: computes the SHA over `canonicalJsonBytes(json)`; throws `CatalogFormatException` with code `checksum` (mismatch with `expectedSha256` when given), `schema` (`schemaVersion` > `supportedCatalogSchema`), `shape` (missing or wrongly typed field, double), `duplicateId`, `reference` (template exercise or program week entry not found, or a template/program referencing a retired exercise), `range` (sets 1 to 30, reps 1 to 1000 with min ≤ max, rest 0 to 3600, duration 1 to 3600, `week` length 7), `mode` (reps on `duration`/`duration_load`, seconds on `reps_load`/`reps`, or both).
  - `CatalogManifest? parseCatalogManifest(Object? json)`: `null` input returns `null` (no live release); otherwise all keys required with the right types and a 64-character lowercase hex `sha256`, else `CatalogFormatException('shape')`.

- [ ] **Step 1: Write failing tests**, using a helper that builds a valid map (two exercises, one template, one program) and mutates one thing per test: `parses valid snapshot`, `parses the published release 1` (body extracted as in Task 1; 18 exercises; `builtin.v1.plank` mode `duration`), and one test per exception code above; `manifest null means no live release`; `manifest rejects bad sha`; `manifest rejects missing key`.
- [ ] **Step 2: Run** `flutter test test/catalog/catalog_parser_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the models and both parsers (pure Dart, no Flutter imports).
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(catalog): parse and validate catalogue snapshots and manifests`

### Task 3: Atomic file store

**Files:**
- Create: `lib/features/catalog/data/catalog_file_store.dart`
- Test: `test/catalog/catalog_file_store_test.dart`

**Interfaces:**
- Produces: `class CatalogFileStore { CatalogFileStore(Directory directory); Future<void> prepare(); Future<String?> readSnapshotText(); Future<void> writeSnapshotText(String text); Future<void> deleteSnapshot(); Future<int?> readLastCheckedAtMs(); Future<void> writeLastCheckedAtMs(int value); }`. Also top-level `String catalogCacheRelativePath(String projectHost)` returning `northstar_catalog/<host>` with the same host validation as `accountStoreRelativePath`.
- File names: `snapshot.json`, `snapshot.json.tmp`, `meta.json` (`{"lastCheckedAtMs": <int>}`), `meta.json.tmp`.

- [ ] **Step 1: Write failing tests** with a temp directory: `prepare creates the directory and deletes stale temp files`; `write then read round-trips`; `write replaces atomically` (after writing A then B, `snapshot.json` is exactly B and no `.tmp` remains); `write leaves the old file when the temp write fails` (inject failure by creating a directory named `snapshot.json.tmp` before the write: expect a `FileSystemException` and `snapshot.json` still A); `corrupt meta reads as null`; `missing files read as null`; `relative path rejects an invalid host`.
- [ ] **Step 2: Run** `flutter test test/catalog/catalog_file_store_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement**: write to `.tmp` with `flush: true`, then `rename` over the target.
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(catalog): atomic on-device catalogue file store`

### Task 4: Supabase transport

**Files:**
- Create: `lib/features/catalog/data/catalog_transport.dart`
- Test: `test/catalog/catalog_transport_test.dart`

**Interfaces:**
- Consumes: `parseCatalogManifest` (Task 2), `matchesCloudWorkoutSession`, `RestoreSessionSnapshot`/`RestoreSessionReader`/`RestoreRpcInvoker` typedef style from `workout_restore_transport.dart` (define equivalent catalogue typedefs locally rather than importing sync internals if the names do not fit).
- Produces:
  - `abstract interface class CatalogTransport { Future<CatalogManifest?> fetchManifest(); Future<Object?> fetchSnapshot(int release); }`
  - `class CatalogUnauthorized implements Exception`, `class CatalogNotLive implements Exception`, `class CatalogNetworkFailure implements Exception { final String kind; }` (`timeout`, `network`, `server`).
  - `class SupabaseCatalogTransport implements CatalogTransport` with a test constructor `(accountId, readSession, invokeRpc, clockSeconds)` and `factory SupabaseCatalogTransport.fromClient(SupabaseClient client, String accountId)`.
- Behaviour: check the session before every call (throw `CatalogUnauthorized` without invoking the RPC); `fetchManifest` calls `catalog_manifest` with a 10 s timeout and parses; `fetchSnapshot` calls `catalog_snapshot` with `{'p_release': release}` and a 20 s timeout; a `PostgrestException` with `code == 'P0002'` becomes `CatalogNotLive`; `TimeoutException` becomes `CatalogNetworkFailure('timeout')`; socket and client errors become `network`; other Postgrest errors become `server`. No exception message or body is kept.

- [ ] **Step 1: Write failing tests** with fake `readSession`/`invokeRpc`: `anonymous session never calls the RPC`, `expired session never calls the RPC`, `other account never calls the RPC`, `manifest null maps to null`, `manifest parsed`, `snapshot passes p_release`, `P0002 maps to CatalogNotLive`, `timeout maps to timeout` (fake that never completes, test clock via `fakeAsync`), `other postgrest error maps to server`.
- [ ] **Step 2: Run** `flutter test test/catalog/catalog_transport_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(catalog): authenticated Supabase catalogue transport`

### Task 5: Repository: load, coalesced refresh, atomic activation

**Files:**
- Create: `lib/features/catalog/data/catalog_repository.dart`
- Test: `test/catalog/catalog_repository_test.dart`

**Interfaces:**
- Consumes: Tasks 1 to 4.
- Produces:
  - `enum CatalogStatus { loading, ready, unavailable, outdatedApp }`
  - `class CatalogState { CatalogSnapshot? snapshot; CatalogStatus status; String? lastFailureKind; }`
  - `enum CatalogRefreshOutcome { skippedFresh, upToDate, updated, noLiveRelease, outdatedApp, unauthorized, notLive, invalid, failed }`
  - `class CatalogRepository extends ChangeNotifier { CatalogRepository({required CatalogTransport transport, required CatalogFileStore store, DateTime Function()? clock, Future<CatalogSnapshot?> Function(String text)? parseInBackground}); CatalogState get state; Future<void> load(); Future<CatalogRefreshOutcome> refresh({bool force = false}); void dispose(); }`
- `parseInBackground` defaults to `Isolate.run(() => parseCatalogSnapshot(jsonDecode(text)))` returning `null` on any exception; tests inject a synchronous parser.
- Rules:
  - `load()`: `store.prepare()`, read snapshot text; if present and parses, state `ready`; if present and fails to parse, `deleteSnapshot()` and state `unavailable`; if absent, `unavailable`. `load()` runs once; later calls return the same future.
  - `refresh()`: if another refresh is in flight, return the same future. Unless `force`, skip with `skippedFresh` when `lastCheckedAtMs` exists, is not in the future, and is under 24 h old.
  - Manifest `null` → write `lastCheckedAtMs`, `noLiveRelease`, keep state.
  - `minAppCatalogSchema > supportedCatalogSchema` → write `lastCheckedAtMs`, status `outdatedApp` (keep any snapshot), `outdatedApp`.
  - Same `release` and `sha256` as the loaded snapshot → write `lastCheckedAtMs`, `upToDate`.
  - Otherwise fetch the snapshot, `parseCatalogSnapshot(json, expectedSha256: manifest.sha256)`, require `release == manifest.release`, write `utf8.decode(canonicalJsonBytes(json))` with `writeSnapshotText`, write `lastCheckedAtMs`, set state `ready` with the new snapshot, `updated`.
  - `CatalogUnauthorized` → `unauthorized`; `CatalogNotLive` → `notLive`; `CatalogFormatException` or release mismatch → `invalid`; `CatalogNetworkFailure` or `FileSystemException` → `failed` with `lastFailureKind`. None of these write `lastCheckedAtMs` or change the snapshot.
  - After `dispose()`, `refresh()` returns `failed` without calling the transport, and an in-flight refresh does not call `notifyListeners`.

- [ ] **Step 1: Write failing tests** with a fake transport (counts calls, scripted results), a real `CatalogFileStore` in a temp dir and an injectable clock:
  - `first launch downloads and activates`
  - `fresh check is skipped within 24 hours` and `force ignores the window`
  - `clock moved backwards forces a check`
  - `same release is a no-op refresh` (no snapshot fetch, file bytes unchanged)
  - `new release replaces the file and state`
  - `checksum mismatch keeps the old cache` (outcome `invalid`, file unchanged, `lastCheckedAtMs` unchanged)
  - `unsupported schema reports outdated app and keeps cache`
  - `not live during rollback keeps cache` (outcome `notLive`)
  - `timeout keeps cache and does not mark checked`
  - `unauthorized makes no snapshot call`
  - `concurrent refreshes share one request` (two calls before the first completes → one manifest call, same outcome)
  - `corrupt cached file is deleted on load` and `stale temp file is removed on load`
  - `write failure keeps the old snapshot` (make the directory read-only or inject a failing store subclass)
  - `dispose during refresh does not notify`
- [ ] **Step 2: Run** `flutter test test/catalog/catalog_repository_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(catalog): cached catalogue repository with coalesced refresh`

### Task 6: Providers, account wiring and lifecycle refresh

**Files:**
- Create: `lib/features/catalog/application/catalog_providers.dart`, `lib/features/catalog/application/catalog_refresh_host.dart`
- Modify: `lib/features/account/account_gate.dart` (override `catalogDirectoryProvider`; wrap the child in `CatalogRefreshHost`)
- Test: `test/catalog/catalog_refresh_host_test.dart`

**Interfaces:**
- Consumes: Task 5; `accountAuthControllerProvider` (its `userId` and `cloudBackupReady`), `defaultStoreDirectory()`, `catalogCacheRelativePath`.
- Produces:
  - `final catalogDirectoryProvider = Provider<Directory>((ref) => throw StateError('Catalogue directory not initialized'));`
  - `final catalogTransportProvider = Provider<CatalogTransport>` (builds `SupabaseCatalogTransport.fromClient(Supabase.instance.client, owner)` for the bound account; tests override).
  - `final catalogRepositoryProvider = Provider<CatalogRepository>`: creates the repository, calls `load()`, and disposes it with `ref.onDispose`.
  - `final catalogStateProvider = NotifierProvider<CatalogStateNotifier, CatalogState>(CatalogStateNotifier.new)`: `build()` reads the repository, adds a listener that sets `state = repository.state`, removes it on dispose (the codebase uses `NotifierProvider`, see `lib/app/theme_controller.dart`; no `ChangeNotifierProvider`).
  - `class CatalogRefreshHost extends ConsumerStatefulWidget { const CatalogRefreshHost({required Widget child}); }`: on first frame and on every `AppLifecycleState.resumed`, and when the auth controller notifies with `cloudBackupReady` true, calls `refresh()` (not forced) after `load()` completes.
- `account_gate.dart`: resolve the directory once in `_open()` alongside the store (`'${(await defaultStoreDirectory()).path}/${catalogCacheRelativePath(widget.projectHost)}'`) and override `catalogDirectoryProvider`; child becomes `AccountWorkoutUploadHost(child: CatalogRefreshHost(child: BeyondRepApp()))`.

- [ ] **Step 1: Write failing widget tests** with overridden transport and directory: `refreshes once on start`, `refreshes again on resume after 24 hours` (inject clock), `does not refresh while signed out or not ready`, `switching account scope reloads the shared file` (two `ProviderScope`s over the same directory; the second sees the first's snapshot without a network call).
- [ ] **Step 2: Run** `flutter test test/catalog/catalog_refresh_host_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** and wire `account_gate.dart`.
- [ ] **Step 4: Run** this test and `flutter test test/account`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(catalog): refresh the catalogue on start and resume for the signed-in account`

### Task 7: Materialize catalogue exercises into the account

**Files:**
- Modify: `lib/features/workouts/domain/workout_library_repository.dart`, `lib/features/workouts/data/objectbox_workout_library_repository.dart`
- Test: `test/workouts/objectbox_workout_library_repository_test.dart`

**Interfaces:**
- Produces: `ExerciseRecord materializeCatalogExercise({required String id, required String name, required String muscleGroup, required String equipment, required String category, required String mode, required int release})`.
- Rules (one write transaction): `id` must start with `builtin.v1.` (else `ArgumentError`). Missing → insert with `isBuiltIn: true`, `catalogVersion: release`. Existing built-in with `catalogVersion < release` → update `name`, `muscleGroup`, `equipment`, `movementCategory`, `catalogVersion`, `updatedAtMs`; never change `inputMode` (mode is fixed per ID); if the stored mode differs, throw `StateError` (data corruption guard). Existing with `catalogVersion >= release` → no write. Returns the stored record. Never touches plans or sessions.

- [ ] **Step 1: Write failing tests**: `inserts a new catalogue exercise`, `is idempotent for the same release` (`updatedAtMs` unchanged), `updates display fields for a newer release`, `ignores an older release`, `never changes mode`, `rejects a non-catalogue id`, `legacy seeded squat is upgraded from catalogVersion 1 only by a newer release` (seed via `ensureCatalogSeeded`, materialize release 1 → no change; release 2 → name updated), `plans referencing the exercise are untouched`.
- [ ] **Step 2: Run** `flutter test test/workouts/objectbox_workout_library_repository_test.dart`. Expected: new tests FAIL.
- [ ] **Step 3: Implement.**
- [ ] **Step 4: Run.** Expected: PASS.
- [ ] **Step 5: Commit** `feat(workouts): copy catalogue exercises into the account library`

### Task 8: Exercise choices and the shared picker

**Files:**
- Create: `lib/features/catalog/domain/exercise_choices.dart`, `lib/features/train/exercise_picker_sheet.dart`
- Modify: `lib/features/train/plan_editor_page.dart` (`_addExercise` uses the picker), `lib/features/train/active_workout_page.dart` (`_chooseExercise` uses the picker)
- Test: `test/catalog/exercise_choices_test.dart`, `test/train/exercise_picker_sheet_test.dart`; existing `test/train/plan_builder_widget_test.dart` and `active_workout_widget_test.dart` keep passing

**Interfaces:**
- Consumes: Tasks 2, 6, 7; `trainLibraryProvider`.
- Produces:
  - `String equipmentLabel(List<String> equipment)`: maps vocabulary to labels (`barbell`→`Barbell`, `dumbbell`→`Dumbbell`, `kettlebell`→`Kettlebell`, `machine`→`Machine`, `cable`→`Cable`, `band`→`Band`, `bodyweight`→`Bodyweight`, `bench`→`Bench`, `pull_up_bar`→`Pull-up bar`, `ez_bar`→`EZ bar`, `trap_bar`→`Trap bar`, `plate`→`Plate`, `box`→`Box`, `rings`→`Rings`, `other`→`Other`) joined with `, `.
  - `class ExerciseChoice { String id; String name; List<String> aliases; String muscleGroup; String equipment; String mode; bool isCustom; CatalogExercise? catalog; ExerciseRecord? local; }`
  - `List<ExerciseChoice> buildExerciseChoices({required List<ExerciseRecord> local, CatalogSnapshot? catalog})`: one entry per id; active catalogue exercises use catalogue name, aliases, group and equipment label and attach the local record if one exists; local built-ins not in the catalogue (or catalogue retired but locally present) appear from local data; custom exercises appear as `isCustom`; archived local records are excluded; sorted by name case-insensitively.
  - `bool matchesExerciseQuery(ExerciseChoice c, String query)`: lower-cased substring over name, aliases, muscle group and equipment.
  - `final exerciseChoicesProvider = Provider<AsyncValue<List<ExerciseChoice>>>` combining `trainLibraryProvider` and `catalogStateProvider`.
  - `Future<ExerciseRecord?> showExercisePicker(BuildContext context, WidgetRef ref, {required String title})`: `showNsSheet` with an `NsTextField` search and an `NsListCard` list; on tap, if the choice has no local record, calls `materializeCatalogExercise` with the catalogue values and current release, then `ref.invalidate(trainLibraryProvider)`; returns the local `ExerciseRecord`. Shows `No matching exercises.` when empty, and the unavailable copy (Global Constraints) with Retry (`refresh(force: true)`) above the list when the catalogue status is `unavailable`.
- Plan editor keeps its default targets: duration mode → no reps; otherwise 8 to 12, 3 sets, 90 s rest.

- [ ] **Step 1: Write failing tests**:
  - choices: `merges catalogue and local by id`, `catalogue-only exercise has no local record`, `custom exercises are marked`, `archived local hidden`, `retired catalogue exercise still shown when local exists`, `alias search finds RDL`, `equipment labels`.
  - picker widget: `lists catalogue-only exercises when cache is ready`, `picking a catalogue-only exercise materializes it and returns the record`, `picking a local exercise does not write`, `shows unavailable copy and Retry with no cache`, `Retry forces a refresh`.
- [ ] **Step 2: Run** `flutter test test/catalog/exercise_choices_test.dart test/train/exercise_picker_sheet_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** the choices, provider and picker; replace both inline pickers.
- [ ] **Step 4: Run** those tests plus `flutter test test/train test/design_kit_guard_test.dart`. Expected: PASS.
- [ ] **Step 5: Commit** `feat(train): one exercise picker over the catalogue and local exercises`

### Task 9: Exercises page, docs and full checks

**Files:**
- Modify: `lib/features/train/exercise_catalog_page.dart`, `docs/CATALOG.md` (client section: cache path, freshness, outcomes, failure behaviour), `docs/ROADMAP.md` (stage 2 "in source, not released"), `docs/RELEASE.md` (device checks: first download, offline fresh install, airplane mode after download, kill during first download, account switch)
- Test: `test/train/exercise_catalog_page_test.dart` (create if missing)

**Interfaces:**
- Consumes: Tasks 6 and 8.
- Behaviour: the list comes from `exerciseChoicesProvider` with `matchesExerciseQuery`; catalogue and local built-ins show `NsTag('Built-in')`; the existing "Custom only" chip and custom edit/archive menu keep working; a `RefreshIndicator` calls `refresh(force: true)` and shows the failure copy with `showNsMessage` on `invalid`, `failed`, `notLive` or `unauthorized`; status copy for `unavailable` (with Retry) and `outdatedApp` appears under the heading.

- [ ] **Step 1: Write failing widget tests**: `shows catalogue exercises with Built-in tag`, `alias search`, `custom only still filters`, `unavailable shows retry copy`, `outdated app copy`, `pull to refresh failure shows the message and keeps list`, light and dark at text scale 2.0 without overflow.
- [ ] **Step 2: Run** `flutter test test/train/exercise_catalog_page_test.dart`. Expected: FAIL.
- [ ] **Step 3: Implement** and update the docs.
- [ ] **Step 4: Run the full mobile checks** from `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`. Expected: all pass. From the repo root: `python3 -m unittest discover -s tool -p 'test_*.py'`. Expected: pass.
- [ ] **Step 5: Commit** `feat(train): show the downloaded catalogue on the Exercises page`

## Out of scope for stage 2

Specific-muscle fields and recovery (stage 3), timed sets (stage 4), more exercise content (stage 5), templates and programs (stages 6 and 7), category/equipment filter chips beyond the existing ones (stage 5 polish). Physical-device checks are listed in `docs/RELEASE.md` and are not run by this stage.
