# Release-type versioning Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the "version name or AUTO (pubspec)" box on the manual iOS TestFlight and Android Play Codemagic jobs with a release-type dropdown. The version is bumped from the highest version already in App Store Connect and Google Play.

**Architecture:** A new stdlib-only module, `scripts/codemagic_release_version.py`, holds the version parsing, the bump rules and the two store lookups. Both job resolvers (`codemagic_ios_version.py`, `codemagic_android_version.py`) call it instead of reading pubspec. `codemagic.yaml` gains a `release_type` choice input on both jobs, plus the cross-store access. The Android upload names each Play release after its version.

**Tech Stack:** Python 3 stdlib, `unittest` with stub CLIs on `PATH` (existing pattern in `tool/test_codemagic_ios_version.py`), Codemagic YAML, codemagic-cli-tools (`app-store-connect`, `google-play`).

**Spec:** `docs/superpowers/specs/2026-11-27-release-type-versioning-design.md`

## Global Constraints

- Release types are these exact strings, in this order: `Fix or optimisation`, `Feature`, `Major`, `Same version, new build`, `Exact version`. The default is `Fix or optimisation`.
- Version format: `MAJOR.FEATURE.FIX`. Input versions with one or two numbers are padded (`0.6` → `0.6.0`). Output is always three numbers. Each part matches the existing `VERSION_NAME` rule (0–9999, no leading zero).
- Bump rules: Fix `X.Y.Z → X.Y.Z+1`. Feature `X.Y.Z → X.Y+1.0`. Major `X.Y.Z → X+1.0.0`. Same returns the current version and fails when there is none. Exact uses `version_name`, which must be valid, not `AUTO`, and `>=` the current version.
- `version_name` that is not `AUTO` with a non-Exact type is an error.
- If neither store has a version, the current version is `0.0.0` (so Fix gives `0.0.1`).
- Build-number behaviour is unchanged on both jobs.
- No pubspec reads in either resolver. No CI commits or tags. No new secrets, groups or integrations beyond `ns_google_play` (iOS job) and `app_store_connect: Codemagic Signing` (Android job), which both already exist.
- An App Store Connect lookup failure stops the job. If `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS` is unset or blank, Play is skipped with a printed note. A Play lookup failure with credentials set stops the job, except for the Android first build (manual build number and `play_track: none`), which already goes on.
- Never print credential values. Tests never contact a store.
- From the repo root: `python3 -m unittest discover -s tool -p 'test_*.py'` must pass.

## Review Focus

- Store reports `1.0` (two parts) next to `0.9.3`: the max must compare numerically after padding, giving `1.0.0`, never a string compare. Test: Task 1 `test_highest_compares_numerically`.
- Play release names that aren't versions (`"Internal test 3"`, `"12 (1.0)"`, missing `name`): ignore them, don't crash. Test: Task 2 `test_play_ignores_non_version_names`.
- A typed exact version with whitespace or a `v` prefix (`" 1.2.0 "`, `"v1.2.0"`): trim whitespace. `v1.2.0` is rejected with the usage message. Test: Task 1 `test_exact_version_trims_and_rejects_prefix`.
- The iOS TestFlight and App Store version lists contain other platforms (`MAC_OS`, `TV_OS`): count only `IOS`. Test: Task 2 `test_asc_counts_only_ios_platform`.
- Release type typed with odd spacing or case through the API (`"feature"`): reject it, listing the allowed values. Test: Task 1 `test_unknown_release_type_lists_choices`.

---

### Task 1: Version parsing and bump rules

**Files:**
- Create: `scripts/codemagic_release_version.py`
- Test: `tool/test_codemagic_release_version.py`

**Interfaces:**
- Consumes: `ResolveError`, `AUTO`, `VERSION_NAME` from `scripts/codemagic_ios_version.py` (import with the same `sys.path.insert` pattern the Android script uses).
- Produces:
  - `RELEASE_TYPES: tuple[str, ...]` (the five strings in Global Constraints order) plus constants `FIX`, `FEATURE`, `MAJOR`, `SAME`, `EXACT`.
  - `Version = tuple[int, int, int]`
  - `parse_version(text: str) -> Version | None`: returns None for anything not matching `VERSION_NAME` after `strip()`.
  - `format_version(v: Version) -> str`
  - `highest(versions: Iterable[Version]) -> Version | None`
  - `next_version(release_type: str, version_name: str, current: Version | None) -> Version`: raises `ResolveError` for every invalid case in Global Constraints.

- [ ] **Step 1: Write the failing tests** (import the module directly, no subprocess):
  - `test_parse_pads_short_versions`: `parse_version("0.6") == (0,6,0)`, `parse_version("2") == (2,0,0)`, `parse_version(" 1.2.3 ") == (1,2,3)`, `parse_version("1.02.0") is None`, `parse_version("1.2.3.4") is None`, `parse_version("") is None`.
  - `test_highest_compares_numerically`: `highest([(0,9,3),(1,0,0),(0,10,0)]) == (1,0,0)`. `highest([]) is None`.
  - `test_fix_feature_major_bumps`: from `(0,6,1)`, `FIX → (0,6,2)`, `FEATURE → (0,7,0)`, `MAJOR → (1,0,0)`, each with `version_name="AUTO"`.
  - `test_no_current_version_starts_from_zero`: `FIX, "AUTO", None → (0,0,1)`. `FEATURE → (0,1,0)`.
  - `test_same_version_reuses_current`: `SAME, "AUTO", (0,6,1) → (0,6,1)`. `SAME, "AUTO", None` raises `ResolveError` whose message contains `"no version"`.
  - `test_exact_version_rules`: `EXACT, "0.7", (0,6,1) → (0,7,0)`. Equal `"0.6.1"` → `(0,6,1)`. Lower `"0.6.0"` raises, with the message containing `"0.6.1"`. `"AUTO"` raises. `"abc"` raises.
  - `test_exact_version_trims_and_rejects_prefix`: `" 1.2.0 " → (1,2,0)`. `"v1.2.0"` raises.
  - `test_version_name_with_non_exact_type_is_rejected`: `FIX, "1.2.0", (0,6,1)` raises, with the message containing `"Exact version"`.
  - `test_unknown_release_type_lists_choices`: `"feature"` raises, with the message containing every entry of `RELEASE_TYPES`.
- [ ] **Step 2: Run them to see them fail**: `python3 -m unittest tool.test_codemagic_release_version -v`. Expected: an import error or failures.
- [ ] **Step 3: Implement** the functions above in `scripts/codemagic_release_version.py`, with a module docstring in the style of `codemagic_ios_version.py`.
- [ ] **Step 4: Run them to see them pass**: same command. Expected: OK.
- [ ] **Step 5: Commit**: `git add scripts/codemagic_release_version.py tool/test_codemagic_release_version.py && git commit -m "ci: add release-type version bump rules"`

### Task 2: Store version lookups

**Files:**
- Modify: `scripts/codemagic_ios_version.py` (extract the app-id lookup from `latest_testflight_build`)
- Modify: `scripts/codemagic_release_version.py`
- Test: `tool/test_codemagic_release_version.py` (add a class with stub `app-store-connect` and `google-play` on `PATH`, copying the stub pattern in `tool/test_codemagic_ios_version.py`)

**Interfaces:**
- Consumes: `asc(*args) -> str` from `codemagic_ios_version.py`.
- Produces:
  - `codemagic_ios_version.app_store_app_id() -> str`. `latest_testflight_build()` now calls it. Behaviour and messages are unchanged, and the existing iOS tests must still pass.
  - `asc_versions() -> list[Version]`: runs `app-store-connect apps pre-release-versions <id> --json` and `app-store-connect apps app-store-versions <id> --json`. Each prints a JSON list of `{"id", "type", "attributes": {...}}`. Read `attributes.version` (pre-release) and `attributes.versionString` (App Store) where `attributes.platform == "IOS"`. Unparseable strings are skipped. Bad JSON raises `ResolveError`.
  - `play_versions() -> list[Version]`: runs `google-play tracks list --package-name in.beyondrep.app --credentials @env:GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS --json`. That prints a JSON list of `{"track", "releases": [{"name", "status", "versionCodes"}]}`, where `releases` may be missing. Parse every `name`. A non-zero exit raises `ResolveError` with the last stderr line, like `latest_play_build`.
  - `current_version(*, play_optional: bool) -> Version | None`: the highest of the ASC and Play results. Play is skipped with a printed note when the credentials variable is blank. When `play_optional` is True, a Play `ResolveError` is printed and skipped. When it is False, the error propagates. An ASC error always propagates.

- [ ] **Step 0: Pin the JSON shapes.** `pip install codemagic-cli-tools` in a scratch venv. Build `PreReleaseVersion`, `AppStoreVersion` and `Track` from sample API dicts and print `.dict()`. Confirm the keys above, and fix this plan's key names if they differ. Note the result in the commit message.
- [ ] **Step 1: Write the failing tests**:
  - `test_asc_reads_testflight_and_app_store_versions`: the stub returns pre-release `["0.5.0","0.6.0"]` and App Store `["0.4.2"]`, all `IOS`. `current_version(play_optional=False)` with Play creds blank returns `(0,6,0)`.
  - `test_asc_counts_only_ios_platform`: a `MAC_OS` pre-release `9.0.0` is ignored.
  - `test_play_versions_raise_the_max`: ASC max `0.6.0`, Play release names `["0.6.1", None-name release]` → `(0,6,1)`.
  - `test_play_ignores_non_version_names`: names `"Internal test 3"`, `"12 (1.0)"`, a release with no `name`, and a track with no `releases` all lead to the ASC value.
  - `test_blank_play_credentials_skip_play`: the Play stub is never called (check the call log).
  - `test_play_failure_stops_unless_optional`: Play stub exits 2. `play_optional=False` raises `ResolveError`. `play_optional=True` returns the ASC value.
  - `test_asc_failure_always_stops`: the ASC stub exits 2 for pre-release-versions and raises even with `play_optional=True`.
  - `test_no_versions_anywhere_is_none`: empty lists → `None`.
- [ ] **Step 2: Run** `python3 -m unittest tool.test_codemagic_release_version tool.test_codemagic_ios_version -v`. Expected: the new tests fail and the old iOS tests pass.
- [ ] **Step 3: Implement** `app_store_app_id`, `asc_versions`, `play_versions` and `current_version`.
- [ ] **Step 4: Run** the same command. Expected: OK.
- [ ] **Step 5: Commit**: `git commit -m "ci: read current version from App Store Connect and Google Play"`

### Task 3: Wire the iOS TestFlight job

**Files:**
- Modify: `scripts/codemagic_ios_version.py` (`main`, docstring; remove `resolve_version` and `PUBSPEC_VERSION` once nothing imports them)
- Modify: `codemagic.yaml` (job `mobile-ios-testflight`)
- Modify: `tool/test_codemagic_ios_version.py`, `tool/test_codemagic_config.py`
- Modify: `docs/IOS_TESTFLIGHT_CODEMAGIC.md` ("Version name and build number" section)

**Interfaces:**
- Consumes: `RELEASE_TYPES`, `next_version`, `current_version`, `format_version` (Tasks 1–2).
- Produces: `main(argv)` takes no pubspec argument (`usage: codemagic_ios_version.py`). It reads `NS_RELEASE_TYPE`, `NS_VERSION_NAME` and `NS_BUILD_NUMBER`, writes `BEYONDREP_VERSION_NAME` and `BEYONDREP_BUILD_NUMBER` to `$CM_ENV`, and prints `Release type <type>: <current or none> -> <new>, build number <n>`.

- [ ] **Step 1: Update the tests first.**
  - Extend the iOS stub with `apps pre-release-versions` and `apps app-store-versions`, driven by env such as `NS_FAKE_PRERELEASE` (a JSON list).
  - Replace the pubspec tests with:
    - `test_fix_bumps_latest_store_version_and_build` (`0.6.1` → `0.6.2`, the build = latest+1, the printed line matches)
    - `test_feature_and_major` (both bumps)
    - `test_same_version_new_build`
    - `test_exact_version_used`
    - `test_exact_lower_than_store_fails_before_build`
    - `test_version_name_with_fix_fails`
    - `test_play_credentials_blank_ios_still_works`
  - Keep the build-number tests, with `NS_RELEASE_TYPE` set.
  - In `tool/test_codemagic_config.py` (iOS job), assert:
    - `inputs` keys are `{"release_type","version_name","build_number"}`.
    - `release_type` is `type: choice`, its `options` equal the five strings, and its `default` is `"Fix or optimisation"`.
    - `version_name` is a string defaulting to `AUTO`, with a description that mentions `Exact version`.
    - `vars` includes `"NS_RELEASE_TYPE": "${{ inputs.release_type }}"`.
    - `groups == ["ns_mobile_supabase_public", "ns_google_play"]`.
    - The resolve script line is `python3 ../../scripts/codemagic_ios_version.py`.
- [ ] **Step 2: Run** `python3 -m unittest tool.test_codemagic_ios_version tool.test_codemagic_config -v`. Expected: the new assertions fail.
- [ ] **Step 3: Implement.** Make `main` use `current_version(play_optional=False)`. Edit the YAML job (quote `"Same version, new build"`) and the input descriptions: version_name becomes "Only for Exact version: a version such as 1.2.0. Leave AUTO otherwise". Rewrite the doc section to cover the five types, the version sources, the failure rules and the `ns_google_play` note.
- [ ] **Step 4: Run** the same command, then the full suite `python3 -m unittest discover -s tool -p 'test_*.py'`. Expected: OK.
- [ ] **Step 5: Commit**: `git commit -m "ci(ios): pick a release type instead of the pubspec version"`

### Task 4: Wire the Android Play job

**Files:**
- Modify: `scripts/codemagic_android_version.py` (`main`, docstring, imports)
- Modify: `codemagic.yaml` (job `mobile-android-release`)
- Modify: `tool/test_codemagic_android_version.py`, `tool/test_codemagic_config.py`
- Modify: `docs/ANDROID_PLAY_CODEMAGIC.md`

**Interfaces:**
- Consumes: the same as Task 3.
- Produces: `main(argv)` takes no pubspec argument. Play is optional only on the first build, that is, when `NS_BUILD_NUMBER != AUTO` and `NS_PLAY_TRACK == none`, matching the existing `resolve_build` exception. The printed line has the same format as iOS.

- [ ] **Step 1: Update the tests first.**
  - Add an `app-store-connect` stub (copy the Task 3 one) and a `tracks list` branch to the Play stub.
  - New tests:
    - `test_version_is_max_of_both_stores` (ASC `0.6.1`, Play `0.6.0` → Fix `0.6.2`)
    - `test_first_build_survives_play_failure` (manual build, track none, Play exits 2 → uses ASC)
    - `test_auto_build_play_failure_stops`
    - `test_asc_failure_stops_android`
  - Update the existing pubspec-based tests to set `NS_RELEASE_TYPE` and expect store-based versions.
  - Config test (Android job):
    - `release_type` is asserted the same way as iOS, and `NS_RELEASE_TYPE` is in `vars`.
    - `workflow["integrations"] == {"app_store_connect": "Codemagic Signing"}`.
    - The upload script contains `--release-name "$BEYONDREP_VERSION_NAME"`.
    - The resolve line has no pubspec argument.
- [ ] **Step 2: Run** `python3 -m unittest tool.test_codemagic_android_version tool.test_codemagic_config -v`. Expected: failures.
- [ ] **Step 3: Implement** the script, YAML and doc changes.
- [ ] **Step 4: Run** the full suite `python3 -m unittest discover -s tool -p 'test_*.py'`. Expected: OK. Also `grep -rn "pubspec version" codemagic.yaml docs/IOS_TESTFLIGHT_CODEMAGIC.md docs/ANDROID_PLAY_CODEMAGIC.md` should return nothing.
- [ ] **Step 5: Commit**: `git commit -m "ci(android): pick a release type and name Play releases by version"`

## After the tasks

Opus whole-branch review (superpowers:requesting-code-review), then a PR. Hosted Codemagic is not run by agents. The PR states that the first real run of each job is the only end-to-end check, and that Codemagic's display of the choice labels is unverified.
