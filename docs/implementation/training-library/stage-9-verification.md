# Training library stage 9: verification results

Plan: `docs/superpowers/plans/2026-11-26-training-library-stage-9.md`. Everything here ran in a Linux cloud container with synthetic data. **Nothing was run on a device**; "not run" means not run.

## Accessibility (automated)

`apps/mobile/test/accessibility/training_library_a11y_test.dart` asserts `androidTapTargetGuideline`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline`, in light and dark, over the app shell (tab bar) at 390x844:

| Screen | Test |
| --- | --- |
| Exercise catalogue page | `exercise catalogue` |
| Exercise detail | `exercise detail` |
| Workouts list, filter sheet open | `workouts list with the filter sheet open` |
| Template detail | `template detail` |
| Programs list, filter sheet open | `programs list with the filter sheet open` |
| Program detail with a day expanded | `program detail with a day expanded` |
| Your program with Done, Missed and Upcoming days | `your program with done, missed and upcoming days` |
| Retired template and retired program ("no longer available") | `retired template and program detail` |
| Today program card: training day, rest day, Done for today, missed line | `Today program card` group |

Semantics assertions: the missed line is announced as "Missed Monday: Push day. Start it now"; each Your program day card carries its status word in its label ("Wednesday · ... Missed"), so status is not colour only; the filter button exposes the tooltip "Filters" and, with a filter on, "Filters (1)" and "Clear" are announced. The filter count is the visible `Filters (n)` text, not part of the button.

Problems found (both real, both fixed, red run recorded in the commit message):

1. `SquareButton` (Filters, and the Today and Progress header buttons) was 44x44, under the 48 dp Android guideline. Now 48x48. Commit `ea72bd3`. A knock-on: the taller header moved the missed line past the first build extent in the Today text-scale-2.0 test, which now scrolls to it first (test change, not a behaviour change).
2. The inactive nav label in light mode was 4.39:1 at 10 px (needs 4.5:1). The literal is now `#5B6B69`. Same commit. This is the shared floating nav bar, not training library code; it showed up because the screens are tested inside the shell.

No other guideline failure. No test was skipped.

## Tablet and split view (automated)

`apps/mobile/test/train/training_library_layout_test.dart` pumps the same screens inside the app shell (tab bar below 600 dp, rail from 600) at phone 360x740, tablet portrait 820x1180, tablet landscape 1180x820 and split view 507x1024, each in light and dark, plus split view at text scale 2.0. It asserts no exception (overflow), that Filters (and the sheet's Show results and Clear after scrolling to its end), Copy to My Plans, Add program, Start for a missed day and Open program can be hit-tested, and that list width stays within the shell's 1120 dp cap (`AdaptiveShell`; Your program adds its own 900 dp cap). 90 tests. No overflow and no covered control was found, so no layout fix was made. No new tablet layout was added.

Not covered: real device rendering, safe areas on a physical iPad, Android tablet. Those are owner steps 7.1 in `docs/RELEASE.md`.

## Process death and restart

A closed ObjectBox store stands in for a killed process (ObjectBox keeps only committed transactions). New tests are in `apps/mobile/test/restart/training_library_restart_test.dart` (15 tests, all pass, no bug found):

| Case | Covered by |
| --- | --- |
| 1. Program day started, store reopened: `programUuid` and `programDayLocalDate` kept, finishing marks the day Done | `restart: today: both fields persist and finishing marks the day done`. Before this: `start_program_day_test.dart` "a program-day start stores both fields" (no reopen) |
| 2. Missed day started, reopened: the stored date is the missed date | `restart: a missed day keeps the missed date, not today`. Before this: `start_program_day_test.dart` "stores the missed date..." and `today_missed_real_store_test.dart` (no reopen) |
| 3. Import interrupted at every `debugImportHook` point, reopen | `restart: 3` group (five hooks: nothing after reopen, one program after retry and after another restart, replay after commit). Before this: `objectbox_program_repository_test.dart` "a failure after ... leaves nothing behind" (no reopen) |
| 4. Template copy interrupted, reopen, retry with the same request id | `restart: 4` group (three hooks; zero then exactly one; replay after commit). Before this: `objectbox_workout_library_repository_test.dart` "a failure after ... leaves nothing behind" (no reopen) |
| 5. Catalogue cache with a stale `snapshot.json.tmp` and a corrupt `meta.json` | `restart: 5` group: the last good snapshot loads and an offline refresh keeps it; with no snapshot the state is `unavailable`, no crash. Already covered separately: `catalog_repository_test.dart` (corrupt, truncated and invalid cached file deleted; stale temp removed), `catalog_file_store_test.dart` (corrupt meta reads as null, only old temp files deleted, atomic replace) |
| 6. Account switch after a restart | `restart: 6`: two account-path stores reopened in the other order, B has no program, session, recovery or week status of A (same UUIDs in both in `program_week_provider_test.dart`), and one shared catalogue cache loads for both. The shared cache directory is per host, not per account (`catalogDirectoryProvider`) |

Note: a plain `snapshot.json.tmp` does not match the store's temp pattern (`snapshot.json.<name>.tmp`), so it is neither cleaned nor read; it is harmless.

Not covered: a real OS kill, low-memory kill and restore. Owner steps 5.1 and 5.2.

## Performance (cloud container numbers)

Measured by `apps/mobile/test/catalog/catalog_performance_test.dart` on release 4 (240 exercises, 38 templates, 17 programs); details and the bandwidth estimate are in `docs/CATALOG.md`.

| What | Result |
| --- | --- |
| Raw / gzip size | 154,237 bytes / 22,549 bytes |
| Decode + SHA-256 + parse + references, median of 20 | 5.8 ms |
| Cold cache load (files, isolate parse, publish), median of 5 | 12.3 ms |
| Exercise search, 50 queries over 240 exercises | median 0.22 ms, worst 1.19 ms |
| Template and program filters, 50 applications | median 0.009 ms, worst 0.58 ms |

Device timings: not run.

## Fixes

| Fix | Commit |
| --- | --- |
| 48 dp `SquareButton`, readable inactive nav label | `ea72bd3` |

## Found and not fixed

- None in the library behaviour. The checks above are characterization of existing behaviour plus the two kit fixes.
- No on-screen or log report of catalogue download time and size exists (no Account > Sync field, no debug log), so owner step 1.2 needs a network profiler. Adding one would be a feature, outside this stage.

## Security review follow-ups (client and tooling)

| Item | Change | Test |
| --- | --- | --- |
| M1 | `tool/test_catalog_migrations.py`: each `*_catalog_release_*.sql` body is byte-identical to its canonical form; sha256, size, header, publish arguments and lock entry agree; the validator passes against the releases locked before it; one migration per lock entry | tampered temp copies for body, header hash, size, lock, missing and extra migration |
| M2 | Phone parser enforces the schema lengths, id patterns, closed vocabularies, no control characters or lone surrogates; copied catalogue text is clamped to 160 code points and a blank name is refused | `catalog_parser_test.dart` "schema limits", library repository tests |
| M3 | Canonicalisation and hashing of a download run in `Isolate.run` with a hard cap of min(manifest size + 1 KiB, 2 MiB); over-cap content is rejected with backoff | `canonical_json_test.dart`, `catalog_repository_test.dart` |
| L1 | A checksum mismatch is found before the structural parse | parse-count test |
| L2 | Canonical JSON depth limit 32; any canonicalisation error is invalid with backoff | depth and hostile-nesting tests |
| L6 | `meta.json` records release and sha256, compared on load; old meta files are accepted and rewritten on the next refresh; a dropped cache is rechecked at once | store and repository tests |

Server hardening (owner-approved): `supabase/migrations/20261126060000_catalog_hardening.sql` revokes all on both catalogue tables from `service_role` and adds `check (size_bytes <= 2097152)` and `check (octet_length(content::text) <= 4194304)`. Exact equality of `size_bytes` with the canonical text is not reproducible in SQL (jsonb text reorders keys and adds spaces), so CI enforces it in `tool/test_catalog_migrations.py` instead. A per-schema `alter default privileges ... revoke ... from public` would not remove the global PUBLIC default, so the guard is a pgTAP test over every `northstar_private` function (allowlist: `sync_workout_internal`, `current_workout_restore_state`). `supabase/tests/catalog.test.sql` gained 13 tests (plan 63): service-key and client TRUNCATE/REFERENCES/TRIGGER privileges, `prosecdef` and `search_path`, the private-function guard, the 2 MiB refusal, the truncate trigger, `catalog_snapshot(null)`, client INSERT/DELETE on the live pointer, a JWT without `is_anonymous`, an empty JWT on the snapshot, and a null manifest with nothing live. Docker is not available, so real pgTAP was not run; the file was run against a local PostgreSQL 16 with stub `auth` functions and Supabase roles and a minimal pgTAP shim: 63 of 63 passed, and with the hardening removed the two new guards failed. CI's `database` job is the real run.

## Still owner-only

Every row of the stage 2 to 8 device sections and the new script in `docs/RELEASE.md` (iOS and Android devices, VoiceOver, TalkBack, tablets, low-end Android, physical process kill, time zone and midnight), the owner review of releases 2 to 4, merging and the `supabase-database` job, the live hosted RLS audit, and the security review follow-ups.
