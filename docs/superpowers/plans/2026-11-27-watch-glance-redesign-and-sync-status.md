# Watch glance redesign and sync status Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the Apple Watch app a two-page (Home, Train) app with an even Option-A glance, tappable detail screens with 7-day trends, and a watch-confirmed sync status shown on both watch and phone.

**Architecture:**
- The phone adds optional fields to the existing `watch_link/v1` `health_snapshot`: sleep stages, usual values, readiness factors and a 7-day `week`.
- The watch replies with the existing `ack` message over `transferUserInfo`.
- The phone turns bridge status plus the acks into a pure `WatchStatus`. It shows that status as a top banner, a bottom line on Today, and a section on Account & sync.
- All watch mapping lives in the `BeyondRepWatchCore` package, so it can be tested with `swift test`. The SwiftUI files only draw.

**Tech Stack:**
- Phone: Flutter 3.47.7, Dart, Riverpod, shared_preferences.
- Watch: SwiftUI on watchOS 10, Swift Charts, WatchConnectivity, SQLite (`BeyondRepWatchCore`).
- Contract tests: Python `jsonschema`.

**Spec:** `docs/superpowers/specs/2026-11-27-watch-glance-redesign-and-sync-status-design.md` (read it first; section numbers below refer to it).

## Global Constraints

- **Public repo.** Synthetic data only. No keys, no profiles, no hosted project refs, no real emails.
- **Contract:**
  - `schema_version` stays `1`.
  - Every new `health_snapshot` field is optional.
  - Unknown keys are still rejected at every level.
  - Python, Dart and Swift must agree on every fixture.
  - `minLength`/`maxLength` count code points.
- **Missing health values** are left out and shown as "—", never 0.
- **The phone writes all wording and computes all numbers** (ADR-0012 decision 4). The watch only formats and draws them.
- **Factors:**
  - `factors[].input` is one of `sleep`, `hrv`, `resting_hr`, `training_load`, with no duplicates and at most 4.
  - `status` is 1–24 code points.
  - `tone` is one of `good`, `neutral`, `caution`.
- **Week:**
  - `week` has 1–7 items, with `local_date` strictly ascending and the last one ≤ the snapshot `local_date`.
  - Day keys are `asleep_minutes`, `sleep_score` (0–100), `resting_hr_bpm`, `hrv_ms` and `steps`, each an integer ≥ 0 and optional.
- **Sync states:**
  - The stale threshold is **48 hours**.
  - Phone `WatchStatus` values are `hidden`, `notInstalled`, `waiting`, `synced(at)` and `stale(at)`.
  - Watch `SyncLine` values are `synced(at)`, `phoneAway(at)` and `notPaired`.
- **Copy (exact):**
  - "BeyondRep isn't on your watch yet"
  - "Open the Watch app on this iPhone, find BeyondRep under Available Apps and tap Install."
  - "Show me how", "Not now"
  - "Your watch hasn't synced since {day time}"
  - "Open the BeyondRep app on your watch"
  - "Apple Watch · synced {time}"
  - "Turn the crown for your workouts", "Got it"
  - "Phone not nearby"
  - "Synced {time}"
  - "Open BeyondRep on your iPhone"
- **Phone UI** uses `apps/mobile/lib/core/design/` only. `test/design_kit_guard_test.dart` must pass, and features must not call raw `showModalBottomSheet`, `SnackBar` and the like.
- **No new dependencies.** Swift Charts ships with watchOS 10.
- **Phone checks** before each commit, from `apps/mobile/` with `export PATH=/root/sdk/flutter/bin:$PATH`:
  - `dart format --output=none --set-exit-if-changed lib test`
  - `flutter analyze`
  - the touched tests
- **Contract tests:** `python3 -m unittest tool.test_watch_link_contract` from the repo root.
- **Swift:** this Linux container has no Swift toolchain. Swift changes are verified by `swift test` and `xcodebuild` in `.github/workflows/watchos_smoke.yml` on the PR. Write the Swift tests first anyway and keep them compiling by inspection. Never claim Swift tests passed locally.
- **Commits:** end every commit message with the attribution lines the session gives you.

## Review Focus

1. **Watch on an older build during an update:** the new snapshot is rejected, the glance shows "—" and there is no crash. Pinned by the Swift test in Task 1 that an unknown key is still rejected.
2. **Snapshot from yesterday after midnight on the watch:** no detail screen shows the old week. Test in Task 4.
3. **An ack for another account arrives after sign-out and sign-in as someone else:** it must not mark the new account synced. Test in Task 6.
4. **A phone with no paired watch, iPad, or Android:** no banner, no footer, no section, and nothing listens. Tests in Tasks 6 and 7.
5. **Very large text on Today:** the banner and footer wrap and do not overflow at text scale 2.0. Test in Task 7.

---

### Task 1: Contract fields, fixtures and all three codecs

**Files:**
- Modify: `contracts/watch_link/v1/message.schema.json` (`$defs.body_health_snapshot`)
- Modify: `contracts/watch_link/v1/README.md` (new fields; old-build note from spec 3.1)
- Create: `contracts/watch_link/v1/fixtures/valid/health_snapshot_full.json`
- Create in `contracts/watch_link/v1/fixtures/invalid/`:
  - `health_snapshot_factor_unknown_input.json`
  - `health_snapshot_factor_duplicate.json`
  - `health_snapshot_week_out_of_order.json`
  - `health_snapshot_week_eight_days.json`
  - `health_snapshot_factor_status_too_long.json`
  - `health_snapshot_usual_negative.json`
- Modify: `tool/test_watch_link_contract.py` (add the cross-field checks for duplicates and order that JSON Schema cannot express, next to existing similar checks)
- Modify: `apps/mobile/lib/features/watch/domain/watch_message.dart` (`health_snapshot` decode; `HealthSnapshot` gains `restingHrUsualBpm`, `hrvUsualMs`, `week` as `List<Map<String, Object?>>?`; `readiness`/`sleep` remain maps)
- Modify: `apps/watch_os/Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/Contracts/WatchMessage.swift`
- Test:
  - `apps/mobile/test/watch/contract_fixtures_test.dart` and `ContractFixtureTests.swift`. Both already iterate all fixtures; confirm they pick up the new files.
  - New Swift test `testHealthSnapshotStillRejectsUnknownKey` in `ContractFixtureTests.swift`.

**Interfaces:**
- Produces Dart `HealthSnapshot({..., int? restingHrUsualBpm, int? hrvUsualMs, List<Map<String, Object?>>? week})`. The JSON keys are `resting_hr_usual_bpm`, `hrv_usual_ms` and `week`. `readiness` may contain `factors`, and `sleep` may contain `core_minutes` and `awake_minutes`.
- Swift `.healthSnapshot(localDate:raw:)` is unchanged. `raw` now may hold the new keys.

- [ ] **Step 1:** Write `health_snapshot_full.json` with synthetic values.
  - Use the existing envelope values from `health_snapshot.json` and a new `message_id` ending `...000000000030`.
  - Fill every field from spec 3.1: 4 factors, 7 week days ending on `local_date`, one day missing `hrv_ms`, and the stages.
  - Write the six invalid fixtures, each differing from the full one in exactly the one way its name says.
- [ ] **Step 2:** Run `python3 -m unittest tool.test_watch_link_contract`. Expect the new valid fixture to FAIL because of unknown keys.
- [ ] **Step 3:** Extend the schema.
  - `sleep.properties` gains `core_minutes` and `awake_minutes`.
  - `readiness.properties.factors` is an array with `maxItems` 4. Each item has `input`, `status` and `tone`, all required, with `additionalProperties: false`.
  - The top level gains `resting_hr_usual_bpm`, `hrv_usual_ms`, and `week`: `minItems` 1, `maxItems` 7, each item requiring `local_date` with the optional metric keys.
  - Add the Python cross-field checks:
    - a factor input must not repeat;
    - `week` dates must be strictly ascending, and the last must be ≤ `local_date`.
- [ ] **Step 4:** Rerun the Python test and expect PASS for all fixtures.
- [ ] **Step 5:** Run `flutter test test/watch/contract_fixtures_test.dart`. Expect FAIL on the full fixture.
- [ ] **Step 6:** Extend the Dart decoder.
  - Use the existing `object`/`optionalInteger`/`oneOf`/`string(max:)` helpers.
  - Add list handling in the style used for `plans_snapshot` items.
  - Enforce the factor duplicate and week order rules, and throw `WatchContractException('invalid_value')` when either is broken.
  - Update `bodyJson`.
- [ ] **Step 7:** Rerun the Dart test and expect PASS.
- [ ] **Step 8:** Extend the Swift decoder with the same rules, and add `testHealthSnapshotStillRejectsUnknownKey`, which adds `"bedtime": "23:40"` to the body and expects a throw.
- [ ] **Step 9:** Update the README. Commit as `feat(watch-link): optional week, usual and factors in health_snapshot`.

### Task 2: Phone builds the richer snapshot

**Files:**
- Modify: `apps/mobile/lib/features/health/widgets/readiness_card.dart`. Add `readinessFactors` next to `readinessReasons` and leave `readinessReasons` unchanged.
- Modify: `apps/mobile/lib/features/watch/application/watch_snapshots.dart` (`buildHealthSnapshot`)
- Test:
  - `apps/mobile/test/watch/watch_snapshots_test.dart`
  - `apps/mobile/test/health/readiness_factors_test.dart` (new; place it beside existing readiness tests if a different folder holds them)

**Interfaces:**
- Consumes Task 1 `HealthSnapshot` fields.
- Produces `List<ReadinessFactor> readinessFactors(HealthOverview overview, ReadinessOverview value, Readiness readiness)` with `class ReadinessFactor { final String input; final String status; final String tone; }`.
  - `input` uses the contract strings.
  - **status** wording (each ≤ 24):
    - sleep: "Slept {formatDuration}";
    - hrv and resting_hr: "Above usual", "Below usual" or "About usual" from the same `TrendDirection` mapping `readinessReasons` uses;
    - training_load: "Above usual" when `loadRatio > 1.3`, otherwise "Normal".
  - **tone:**
    - `good` for HRV up, resting HR down, or sleep ≥ 7 h;
    - `caution` for HRV down, resting HR up, sleep < 6 h, or load > 1.3;
    - `neutral` otherwise.
  - Only inputs in `readiness.parts` are listed, plus training_load when `loadRatio` is non-null. The order is sleep, hrv, resting_hr, training_load.

- [ ] **Step 1:** Write failing tests in `readiness_factors_test.dart`:
  - `lists only the inputs the score used, in order`;
  - `wording follows the same trend as readinessReasons`;
  - `status never exceeds 24 code points`.
- [ ] **Step 2:** Run and expect FAIL. Then implement `readinessFactors` and rerun to PASS.
- [ ] **Step 3:** Write failing tests in `watch_snapshots_test.dart`, using the existing overview fixtures and helpers in that file:
  - `week holds the 7 days ending today, oldest first`;
  - `a day with no values is left out and a missing metric key is absent`;
  - `today's steps in week come from stepsToday`;
  - `core and awake minutes only when the night has stages`;
  - `usual values only when a baseline exists`;
  - `factors copied into readiness`;
  - `full week snapshot stays under watchSnapshotMaxBytes`;
  - `round-trips through WatchMessage.fromJson`.
- [ ] **Step 4:** Run and expect FAIL. Then implement:
  - Find days by `dayOf(...)` equality against `today` minus 0..6 days.
  - `sleep_score` comes from the night's score if `SleepNight` carries one; otherwise omit it. Do not compute a score.
  - Round doubles with `.round()`.
- [ ] **Step 5:** Run `flutter test test/watch test/health` and expect PASS. Run format and analyze. Commit as `feat(watch): send week, usual values and readiness factors`.

### Task 3: Watch journal link state and inbox ack outcomes

**Files:**
- Modify: `apps/watch_os/Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/Store/WatchJournal.swift`
  - Add a `link_state(slot INTEGER PRIMARY KEY CHECK(slot = 1), last_received_ms INTEGER NOT NULL)` table.
  - Bump `user_version` 4 to 5.
  - `clearAccount` deletes the row.
- Modify: `apps/watch_os/Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/Link/PhoneInbox.swift`
- Create: `apps/watch_os/Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/Link/AckBuilder.swift`
- Test:
  - `PhoneInboxTests.swift`
  - `WatchJournalTests.swift`
  - new `AckBuilderTests.swift`

**Interfaces:**
- Produces:
  - `WatchJournal.recordReceived(atMs: Int64) throws` and `WatchJournal.lastReceivedMs() throws -> Int64?`
  - `public struct AckOutcome: Equatable { public let messageId: String; public let accountKey: String; public let result: String; public let reason: String? }`
  - `PhoneInbox.receive(applicationContext:now:) throws -> [AckOutcome]` and `receive(userInfo:now:) throws -> [AckOutcome]`. Callers that ignore the result are fine.
  - `AckBuilder.json(for: AckOutcome, messageId: UUID, now: Date) -> String` builds a valid contract `ack` message.
- `AckOutcome` rules:
  - Binding, plans or health applied → `stored`.
  - The same message id as the stored one → `duplicate`.
  - Plans or health whose key differs from an existing binding → `rejected`/`wrong_account`.
  - With no binding at all, no outcome.
  - Undecodable entries → no outcome.
  - `account_cleared` → `stored`.
  - Any `stored` or `duplicate` health, plans or binding calls `recordReceived(now)`.

- [ ] **Step 1:** Write failing tests:
  - `testStoredAckForEachAppliedContextMessage`
  - `testSameHealthTwiceIsDuplicate`
  - `testPlansForAnotherBoundAccountAreRejectedWrongAccount`
  - `testNoAckWithoutBinding`
  - `testReceivedTimeRecordedAndClearedWithAccount`
  - `testMigrationFromVersion4KeepsData`, which follows the existing migration test pattern
  - `testAckJsonDecodesAsContractAck`, which runs `AckBuilder` output through `WatchMessage(json:)`
- [ ] **Step 2:** Implement. Health duplicate detection compares the stored health message's id with the incoming one; store and compare the same way for plans.
- [ ] **Step 3:** Commit as `feat(watch-core): ack outcomes and last received time`. Swift is verified on the PR (see Global Constraints).

### Task 4: Glance, detail and sync models in the core package

**Files:**
- Modify: `apps/watch_os/Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/Glance/GlanceState.swift`
- Create: `.../Glance/DetailModel.swift` and `.../Glance/SyncLine.swift`
- Test: `GlanceStateTests.swift`, plus new `DetailModelTests.swift` and `SyncLineTests.swift`

**Interfaces:**
- Produces:
  - `GlanceTile` gains `status: String?`, `tone: Tone` (`enum Tone: String { good, neutral, caution }`) and `metric: Metric` (`enum Metric { sleep, restingHr, hrv, steps }`).
  - `Glance` gains:
    - `readinessReason: String?`
    - `factors: [Factor]`, where `Factor { input, status, tone }`
    - `today: PlanRow?` with `subtitle: String?`; the subtitle is "Week 3 · Day 2 · 6 exercises" only from data present, so if the snapshot lacks week/day show "{n} exercises"
    - `plans: [PlanRow]` with `exerciseCount: Int`
  - `DetailModel.make(metric: Metric, journal:, now:, timeZone:, locale:) throws -> DetailModel?` returns:
    - `title`, `value`, `unit`, `caption`;
    - `usual: Int?`;
    - `week: [DayPoint]`, where `DayPoint { date: Date; label: String /* one-letter weekday */; value: Int?; isToday: Bool }` always has 7 entries ending today, with `value` nil for missing days;
    - `stages: SleepStages?`, where `SleepStages { deep, core, rem, awake: Int }`, present only when all four keys exist;
    - `weekAverage: Int?`.
  - `SyncLine.make(journal:, isPhoneReachable: Bool, now:, timeZone:, locale:) throws -> SyncLine` with `enum SyncLine: Equatable { case notPaired; case synced(String); case phoneAway(String) }`, where the String is the short local time of `lastReceivedMs`.
- Tile status rules (spec 3.5):
  - Sleep: "Score {n}" in tone good.
  - Resting HR: `today − usual` formatted as "−2 vs usual" (U+2212 minus) or "+2 vs usual"; tone good when below usual, neutral otherwise.
  - HRV: the same format; tone good when above usual.
  - Without usual: status nil.
  - Steps: "today", neutral.
- `week` is ignored entirely when the snapshot's `local_date` ≠ today, because the existing purge already enforces that.

- [ ] **Step 1:** Write failing tests:
  - `testTileStatusLinesFromUsual`
  - `testMissingUsualGivesNoStatus`
  - `testMissingValueIsDashNeverZero`
  - `testDetailWeekHasSevenDaysEndingTodayWithGaps`
  - `testStagesOnlyWhenAllFourPresent`
  - `testYesterdaysSnapshotGivesNoDetail`
  - `testSyncLineStates`, covering not paired, synced and phone away
  - `testFactorsInPhoneOrder`
- [ ] **Step 2:** Implement, keeping the existing `GlanceState` cases and the `refreshCaption` behaviour.
- [ ] **Step 3:** Commit as `feat(watch-core): tiles with status, detail and sync models`.

### Task 5: Watch app screens and acks over WatchConnectivity

**Files:**
- Create in `apps/watch_os/Sources/Features/`:
  - `Design/Palette.swift`, which moves the tokens out of `HomeView.swift` and adds sleep `#C1A9FF`, heart `#FF8587` and steps `#7FD8FF`
  - `Root/RootView.swift`
  - `Home/HomePage.swift`, which replaces `HomeView.swift`; delete the old file and update `BeyondRepWatchApp.swift`
  - `Train/TrainPage.swift`
  - `Detail/SleepDetailView.swift`
  - `Detail/TrendDetailView.swift`, used for resting HR, HRV and steps
  - `Detail/ReadinessDetailView.swift`
  - `Sync/SyncView.swift`
  - `Onboarding/TrainHintView.swift`
- Modify:
  - `apps/watch_os/Sources/App/AppModel.swift`, which publishes `syncLine` and exposes `detail(for:)`
  - `apps/watch_os/Sources/Connectivity/PhoneLink.swift`, which sends acks and reports reachability
- Modify: `apps/watch_os/project.yml` and `tool/embed_watch_target.rb`, only if the new folders are not already picked up by the existing `Sources` glob. Check `tool/test_watch_embedding.py` and update it if it lists files.

**Interfaces:**
- Consumes Task 3 `AckOutcome`/`AckBuilder` and Task 4 models.
- Changes:
  - `AppModel.receive(...)` gets the outcomes from `PhoneInbox` and calls `link.send(acks:)`.
  - `PhoneLink.send(acks: [String])` calls `WCSession.default.transferUserInfo(["json": json])` for each ack.
  - `sessionReachabilityDidChange` updates `AppModel.isPhoneReachable`.

- [ ] **Step 1:** Build the screens to match the mockup and spec 3.5:
  - `TabView(selection:)` with `.tabViewStyle(.verticalPage)`.
  - A Home toolbar `ToolbarItem(placement: .bottomBar)` trailing round button with an SF Symbol `dumbbell.fill`, `.tint(Palette.performance)`, and the accessibility label "Train".
  - `NavigationLink` from each tile and from the hero.
  - Tapping the top status line opens `SyncView`.
  - `@AppStorage("didShowTrainHint")` shows `TrainHintView` as a `.fullScreenCover` once, when the glance is `.ready`.
  - Tiles have a fixed height and `monospacedDigit()`. `@Environment(\.dynamicTypeSize)` of `.accessibility1` or larger switches the grid to one column.
  - Charts use `Chart` with `BarMark` (steps, sleep) and `LineMark` plus a dashed `RuleMark(y: usual)`.
  - Every tile and chart has an `.accessibilityLabel` in words, for example "Resting heart rate 61 beats per minute, 2 below your usual".
- [ ] **Step 2:** Wire the acks and reachability.
- [ ] **Step 3:** Add `#Preview`s with synthetic data for Home, Train, each detail screen and the Sync states, for Adi's simulator.
- [ ] **Step 4:** Commit as `feat(watch): Home and Train pages, detail screens, sync screen`. The build is verified by `watchos_smoke.yml` on the PR.

### Task 6: Phone bridge, link and status model

**Files:**
- Modify: `apps/mobile/ios/Runner/WatchLinkBridge.swift`
  - Add a `watchStatus` method that returns `["supported": Bool, "paired": Bool, "installed": Bool, "reachable": Bool]`.
  - Add `session(_:didReceiveUserInfo:)`, which forwards `userInfo["json"] as? String` to Dart via `invokeMethod("watchMessage", json)` on the main queue.
  - Call `notifyWatchStateChanged` from `sessionReachabilityDidChange` too.
- Modify: `apps/mobile/lib/features/watch/data/watch_link.dart`
- Create: `apps/mobile/lib/features/watch/domain/watch_status.dart` and `apps/mobile/lib/features/watch/data/watch_status_store.dart`
- Modify: `apps/mobile/lib/features/watch/application/watch_sync_controller.dart`
- Test:
  - `test/watch/watch_link_test.dart`
  - new `test/watch/watch_status_test.dart`
  - `test/watch/watch_sync_controller_test.dart`

**Interfaces:**
- Produces:
  - `class WatchDeviceStatus { final bool supported, paired, installed, reachable; static const unsupported; }`
  - `WatchLink.status() -> Future<WatchDeviceStatus>` and `WatchLink.messages -> Stream<String>`. `NoopWatchLink` returns `unsupported` and an empty stream, and so does a `MissingPluginException`.
  - `sealed class WatchStatus` with `WatchHidden`, `WatchNotInstalled`, `WatchWaiting`, `WatchSynced(DateTime at)` and `WatchStale(DateTime at)`.
  - `WatchStatus watchStatusOf({required WatchDeviceStatus device, required bool signedIn, required DateTime? lastConfirmedAt, required DateTime? lastSentAt, required DateTime now})`, implementing the spec 3.4 table: stale when `now − lastConfirmedAt ≥ 48h` and `lastSentAt` is after `lastConfirmedAt`.
  - `WatchStatusStore` over `SharedPreferences`, with:
    - `DateTime? confirmedAt(String accountKey)`
    - `Future<void> setConfirmedAt(String accountKey, DateTime at)`
    - `bool installHintDismissed`
    - `Future<void> dismissInstallHint()`
    - `Future<void> clear()`, called from the controller's sign-out and `onAccountDeleted` paths
  - `watchStatusProvider`, a Riverpod provider of `WatchStatus` fed by `WatchSyncController`. It updates when device status changes, after each send, and on each confirmed ack.
- Controller ack rule:
  - Decode with `WatchMessage.fromJson`, and ignore failures.
  - Accept only `Ack` with `result` `stored` or `duplicate`, whose `accountKey` equals the current account key, and whose `ackedMessageId` is the health or plans id of the latest or the previous sent context.
  - When accepted, `setConfirmedAt(key, now)`.
  - `lastSentAt` is the time of the last successful `updateContext`.

- [ ] **Step 1:** Write failing tests:
  - `watch_status_test.dart`: one test per table row, plus `exactly 48 hours is stale` and `confirmed after last send is never stale`.
  - `watch_link_test.dart`: `status maps the platform dictionary`, `status is unsupported on MissingPluginException`, `watchMessage calls arrive on messages`.
  - `watch_sync_controller_test.dart`:
    - `stored ack for latest health marks synced`
    - `ack for another account is ignored`
    - `ack for an unknown message id is ignored`
    - `unsupported device stays hidden and sends nothing`
    - `sign out clears confirmed time and status becomes hidden`
- [ ] **Step 2:** Implement and run `flutter test test/watch` until it passes. Run format and analyze. The Swift bridge change is verified by the `ios-with-watch` CI build.
- [ ] **Step 3:** Commit as `feat(watch): watch status from bridge and watch acks`.

### Task 7: Phone UI on Today and Account & sync

**Files:**
- Create:
  - `apps/mobile/lib/features/watch/widgets/watch_status_banner.dart`
  - `apps/mobile/lib/features/watch/widgets/watch_status_footer.dart`
  - `apps/mobile/lib/features/watch/widgets/watch_install_steps_sheet.dart`
  - `apps/mobile/lib/features/watch/widgets/watch_account_section.dart`
- Modify:
  - `apps/mobile/lib/features/today/today_page.dart`: the banner goes first in both `ListView`s, above `BackupStatusNotice`, and the footer goes last.
  - `apps/mobile/lib/features/account/account_sync_page.dart`: the section goes above the cloud backup section.
  - `lib/core/design/` only if no existing kit widget fits the footer row. Make that a separate commit, `feat(design): ...`, with its own test in the kit's test folder, and document it in `docs/DESIGN_SYSTEM.md`.
- Test:
  - new `apps/mobile/test/watch/watch_status_widgets_test.dart`
  - extend the existing Today and Account & sync page tests where they build those pages

**Interfaces:**
- Consumes `watchStatusProvider`, `WatchStatusStore` and `WatchStatus` from Task 6.
- Widget behaviour:
  - **Banner** (an `InsightCard`, as in `BackupStatusNotice`):
    - `WatchNotInstalled` when the hint is not dismissed: the install copy plus the "Show me how" and "Not now" actions.
    - `WatchStale`: the stale copy, with `{day time}` from `MaterialLocalizations`/`intl` in the style other Today copy uses.
    - Otherwise it builds `SizedBox.shrink()`.
  - **Footer:** only for `WatchSynced`. It shows "Apple Watch · synced {time}" with a performance-colour dot, and tapping it opens Account & sync with the route the existing backup notice uses.
  - **"Show me how"** opens the kit bottom sheet with three numbered steps (spec 3.4).
  - **Account section:** hidden for `WatchHidden`. Otherwise it has these rows:
    - Status: Connected, Not installed, Waiting for the watch, or Not synced recently.
    - BeyondRep on watch: Installed or Not installed.
    - Last synced: "Today 10:43" or "Tue 10:43", in caution colour when stale.
    - Sent to watch: "Readiness, health, {n} plans", from the last sent snapshot counts that the controller exposes as `lastSentSummary`. Add it to the Task 6 provider state if needed.

- [ ] **Step 1:** Write failing widget tests:
  - `hidden shows nothing on Today or Account`
  - `not installed shows banner first on Today`
  - `Not now hides the banner and persists`
  - `stale shows banner with last time`
  - `synced shows footer last and no banner`
  - `footer opens Account and sync`
  - `Show me how opens three steps`
  - `banner and footer fit at text scale 2.0 in light and dark`
  - `account section rows per state`
- [ ] **Step 2:** Implement and run the tests to PASS. Then run `flutter test test/design_kit_guard_test.dart` plus format and analyze.
- [ ] **Step 3:** Commit as `feat(watch): watch status on Today and Account & sync`.

### Task 8: ADR amendment, docs and full check

**Files:**
- Modify:
  - `docs/adr/0012-apple-watch-companion.md`: add the decision 4 amendment text from spec 3.6, dated 2026-11-27 and approved by Adi.
  - `docs/HEALTH_DATA.md` and `docs/SYNC_PROTOCOL.md`: one pointer line each.
  - `docs/ROADMAP.md`: a new line under Phase 4 for this mini-stage, "implemented in source, not released or device-verified".
  - `docs/RELEASE.md`: the device checks from spec section 5, "Device (Adi, not CI)", as open boxes.
  - `CLAUDE.md`: extend the Phase 4 stage 3 bullet with one sentence on the redesign, the detail screens and the sync status, "implemented in source, not released or device-verified".
- Test: the full phone suite and the repo tool tests.

- [ ] **Step 1:** Make the doc edits.
- [ ] **Step 2:** Run the full checks:
  - from `apps/mobile/`: `dart format --output=none --set-exit-if-changed lib test && flutter analyze && flutter test`;
  - from the repo root: `python3 -m pip install -r tool/requirements-ci.txt && python3 -m unittest discover -s tool -p 'test_*.py'`.

  Expect everything to pass. Record any failure honestly.
- [ ] **Step 3:** Run `git status` and confirm there are no unexpected files and no secrets. Commit as `docs: watch glance redesign and sync status (ADR-0012 amendment)`.
