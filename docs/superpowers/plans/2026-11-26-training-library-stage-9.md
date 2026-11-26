# Training library stage 9: release verification

> **For agentic workers:** REQUIRED SUB-SKILL: use superpowers:executing-plans to carry out this plan task by task, with superpowers:test-driven-development for every code or test change.

**Goal.** Close the training library work (issue #63, spec `docs/superpowers/specs/2026-11-25-training-library-design.md` section 8 item 9). This stage covers everything that can be checked without a device: automated accessibility, tablet and process-death coverage, measured catalogue performance, and a security review of the catalogue API. It also leaves one ordered device script, so the owner can verify iOS, Android and tablet in a single sitting.

**What this stage is not.** No new features, no catalogue release, no ObjectBox model change, no sync or contract change, and no Supabase migration. If verification finds a real bug, fix it with a failing test first, in its own commit, and list it in the report. If a fix would need a model, sync or server change, stop and report it instead of making it.

**Branch.** Work on the local `claude/project-thread-r1zdx7` on top of the stage 8 commits. Do not push. The coordinator will rebase onto `main` after PR #76 merges.

**Checks.** Run these from `apps/mobile`: `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze` and `flutter test`. From the repo root, run `python3 -m unittest discover -s tool -p 'test_*.py'` and `python3 scripts/catalog_build.py check`. Flutter is at `/opt/sdk/flutter/bin/flutter`.

---

## Task 1: Accessibility guideline tests

Add `test/accessibility/training_library_a11y_test.dart`. Pump each screen below with fixture data (reuse `test/train/template_test_support.dart`, `test/train/program_test_support.dart` and the Today test helpers). Assert `androidTapTargetGuideline`, `iOSTapTargetGuideline`, `labeledTapTargetGuideline` and `textContrastGuideline` in light and in dark:

1. Exercise catalogue page and exercise detail
2. Workouts list (with the filter sheet open) and template detail
3. Programs list (with the filter sheet open), program detail with a day expanded, and Your program with done, missed and upcoming tags
4. Today with the program card on a training day, a rest day, "Done for today", and with the missed line
5. The retired "no longer available" detail state

Where a guideline fails, decide whether it's a real problem (a small tap target, a missing label, or low contrast from a non-token colour) or a test artifact (for example, contrast on a decorative chart). Fix real problems in the feature or the kit, using kit tokens, with that guideline test as the red test. Document an artifact with a one-line comment and a narrower check, never a skip. Also add semantics assertions for:
- the missed line's label
- the Your program day tags, so a status is announced in words and not only by colour
- the filter count ("Filters, 2 active", or whatever the kit's button exposes)

**Verify:** the new test file passes, and any fix has its red run noted in the commit message.

## Task 2: Tablet and split-screen layout tests

Add `test/train/training_library_layout_test.dart`. Pump the screens from Task 1 at these sizes, each in light and dark:
- phone 360×740
- tablet portrait 820×1180
- tablet landscape 1180×820
- split view 507×1024 (half-width iPad)

Assert there are no overflow errors (`tester.takeException()` is null), primary actions can be found and tapped (Start, Add program, Copy to My Plans, Filters), and the content doesn't stretch to more than the kit's maximum readable width where the app already applies one. Check how existing pages handle wide layouts first; don't invent a new tablet layout. Also run text scale 2.0 at the split-view size.

**Verify:** the file passes, and any overflow found is fixed with that test as red.

## Task 3: Process death and restart coverage

First, list the restart cases that the existing tests already cover. For each case below, either name the existing test that covers it (record it in the report) or add a test using a real ObjectBox store that is closed and reopened (follow the pattern in `test/programs/objectbox_program_repository_test.dart`):

1. Starting a program day, then closing and reopening the store: the in-progress session still has `programUuid` and `programDayLocalDate`, and finishing it marks that day done.
2. Starting a missed day, then restarting: the stored date is the missed date, not today.
3. An import interrupted at every `debugImportHook` point, then a reopen: there's no partial program, and a retry creates exactly one.
4. Copying a template to My Plans, killed mid-way, then reopened: either no plan, or exactly one. A retry with the same request id gives one plan.
5. Catalogue cache: a stale `snapshot.json.tmp` and a corrupt `meta.json` on launch. The last good snapshot loads, or the app shows the empty or offline state, never a crash. This may already be covered in `catalog_repository_test.dart`; if so, cite it.
6. Account switch after a restart: account B sees none of account A's programs, sessions or week status, and the shared catalogue cache is still used.

**Verify:** each case has either a cited test or a new passing test.

## Task 4: Catalogue performance measurements

Add `apps/mobile/test/catalog/catalog_performance_test.dart`, tagged `@Tags(['performance'])` so it can be run alone, plus a `dart_test.yaml` tag entry if the repo doesn't have one. Build the real release 4 snapshot from the repo catalogue: either read the generated content out of `supabase/migrations/20261126050000_catalog_release_4.sql` in a test helper, or add `python3 scripts/catalog_build.py` output to a temp file in a `setUpAll`. Pick whichever needs no new dependency. Measure:

- raw snapshot bytes and gzip bytes (`dart:io` `gzip`)
- SHA-256 verify plus parse plus reference validation, as a median of 20 runs
- cold cache load from a temp directory (read `snapshot.json` and `meta.json`, parse, and publish to the provider)
- search: the median time of 50 queries over the exercise list (short prefixes, aliases, no matches) and of applying filters on the template and program lists

Assert generous budgets so CI doesn't flake: parse under 500 ms, a single search under 20 ms, and raw size under the validator's size warning limit. Print the measured numbers.

Record the numbers in `docs/CATALOG.md` under a new "Measured performance (stage 9)" heading. Say they're cloud-container numbers, and that device timings are a row in `docs/RELEASE.md`. Also estimate the first-download bandwidth (gzip bytes per user per release), and compare it with the Supabase free-plan egress noted in the spec's constraints.

**Verify:** the test passes, and the numbers are in the docs.

## Task 5: Owner device script

In `docs/RELEASE.md`, add a section "Training library release verification (ADR-0010, owner actions, none done)" above "Feature and privacy readiness". It should be one ordered script that covers the open rows of the stage 2 to 8 sections without duplicating them: each step references the row it closes. Group the steps so one sitting works on each device:

1. Fresh install, offline first launch, then online: catalogue first download time and size from Account > Sync or the debug log, whichever exists. Then measure cache load on a cold relaunch.
2. Browse and search: exercise search feel, filters, and both detail screens.
3. Workouts: start from a template, copy to My Plans, double-tap protection.
4. Programs: add, set active, Today card, finish, missed day, midnight session, time-zone change.
5. Process death: force-quit mid-workout on a program day and reopen; force-quit right after tapping Add program.
6. Accessibility: VoiceOver (iOS) and TalkBack (Android) through Today, Programs and the filter sheet. Text size at 200 percent, reduced motion, dark mode.
7. Tablet: iPad portrait, landscape and split view, and an Android tablet or a large-screen emulator if available.
8. Low-end Android: list scroll and search with 240 exercises.

Each step has an iOS and an Android column, set to "not run". Update `docs/ROADMAP.md` (stage 9: automated verification done, device script open) and the "Project state" training library line in `CLAUDE.md`, keeping its existing style. Don't claim any device result.

**Verify:** `python3 -m unittest discover -s tool -p 'test_*.py'` passes (layout and docs guards).

## Task 6: Report

Write `docs/implementation/training-library/stage-9-verification.md` with:
- the a11y, tablet and process-death results, listing each case and its test
- the performance numbers
- the fixes made, with their commits
- anything found but not fixed, and why
- what is still owner-only

Keep it factual. "Not run" means not run.

---

## Security review (done separately)

An independent Opus reviewer audits the catalogue API in parallel with the implementer and doesn't edit the repo. The review covers:
- `catalog_manifest()` and the release fetch: grants, `security definer` search paths, and the verified-user check
- RLS on `catalog_live` and `catalog_releases`
- immutability triggers
- publish and rollback being reachable only through migrations
- the phone's size, checksum and schema checks, and how it handles hostile content (huge strings, deep nesting, unknown keys, bad references)
- that no user data reaches catalogue tables or logs

The coordinator also runs read-only advisor and grant queries on the hosted project. Findings land in this stage's PR or as issues, as the owner decides.
