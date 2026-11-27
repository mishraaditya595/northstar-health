# Phase 4 stage 3: phone–watch link, health glance and TestFlight embedding — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The iPhone app sends the signed-in account's binding, plans and today's health numbers to a BeyondRep Apple Watch app that shows them as a glance, and the watch app ships inside the iPhone build through the existing TestFlight job.

**Architecture:** The phone builds `watch_link/v1` messages (stage 2 codecs) from providers it already has and pushes the latest of each through WatchConnectivity's application context; one-off messages (`account_cleared`) go by `transferUserInfo`. A small Swift bridge in Runner exposes WatchConnectivity to Dart; all logic stays in Dart (`lib/features/watch/`). On the watch, a `PhoneInbox` in the core package decodes and stores messages in the `WatchJournal`, and a pure `GlanceState` turns them into what the SwiftUI Home screen shows. The watch target is added to `Runner.xcodeproj` by a committed, idempotent Ruby `xcodeproj` script and referenced from `apps/watch_os/Sources`; nothing is copied into `apps/mobile/ios`.

**Tech Stack:** Flutter/Riverpod, `MethodChannel`, Swift 5.9, WatchConnectivity, SwiftUI (watchOS 10), Ruby `xcodeproj` gem (script only, not an app dependency), GitHub Actions `macos-15`, Codemagic.

**Spec:** `docs/superpowers/specs/2026-11-26-phase-4-watch-and-tablet-design.md` §4.4, §5.2–5.4, §5.7–5.8; ADR-0012.

## Global Constraints

- No workout logging, no HealthKit access and no HealthKit entitlement on the watch in this stage (stage 4). The watch shows plans read-only; no Start button (AGENTS.md: a watch UI must not fake a saved session).
- The watch shows only phone-computed values; **missing is shown as "—", never 0**; readiness from a date other than the watch's current local date is never shown.
- Watch bundle id `in.beyondrep.app.watchkitapp`, `WKCompanionAppBundleIdentifier` `in.beyondrep.app`, watchOS 10.0. iPhone deployment target stays 15.0; WatchConnectivity calls are guarded by `WCSession.isSupported()`.
- Watch Swift sources stay only in `apps/watch_os/` (ADR-0004); Runner references them by path.
- The watch never receives the raw user id or email: only `watchAccountKey(userId)` (stage 2).
- Snapshot JSON per message ≤ 60 000 bytes (WatchConnectivity payload headroom); caps from `watch_link/v1` (≤ 100 plans, ≤ 40 exercises, ≤ 30 sets, ≤ 30 recent exercises).
- Android: a no-op link; nothing changes on Android.
- Codemagic: keep automatic signing via the `Codemagic Signing` integration; add no new credential groups. Signing-file names are referenced by name only.
- Swift is verified on GitHub Actions (`watchos_smoke.yml`, `workflow_dispatch` on the branch); Dart/Python locally. Actions pinned to full SHAs.

## Review Focus

1. **Account switch on the phone (A signs out, B signs in):** the watch must never show A's plans or health under B, and A's unsent workouts (none yet, but the table exists) are kept. Tests in Task 1 (`PhoneInbox`) and Task 4 (controller order: `account_cleared` for A before B's binding).
2. **Midnight:** a snapshot read at 23:50 and viewed at 00:05 shows "Open BeyondRep on your iPhone to refresh", not yesterday's readiness. Test in Task 1 (`GlanceState`).
3. **No watch / app not installed / Android:** the phone sends nothing and logs nothing; no exceptions. Test in Task 4.
4. **Big libraries:** 150 plans with 40 exercises each still produce a valid snapshot under 60 000 bytes (deterministic truncation: today's program plan first, then most recently used). Test in Task 2.
5. **Rebuild storms:** providers rebuild often; identical content must not be re-sent. Test in Task 4 (same snapshot twice → one `updateContext` call).

---

### Task 1: Watch core — binding, inbox and glance state

**Files:**
- Modify: `apps/watch_os/Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/Store/WatchJournal.swift` (binding table, `user_version` 2 with a tested migration from 1)
- Create: `Sources/BeyondRepWatchCore/Link/PhoneInbox.swift`, `Sources/BeyondRepWatchCore/Glance/GlanceState.swift`
- Test: `Tests/BeyondRepWatchCoreTests/PhoneInboxTests.swift`, `GlanceStateTests.swift`, extend `WatchJournalTests.swift`

**Interfaces:**
- Consumes: `WatchMessage`, `WatchJournal` (stage 2).
- Produces:
  - `WatchJournal.saveBinding(_ message: WatchMessage) throws`, `WatchJournal.binding() throws -> (accountKey: String, unit: String)?`; `clearAccount` also removes the binding when its key matches.
  - `struct PhoneInbox { init(journal: WatchJournal); func receive(applicationContext: [String: Any]) throws; func receive(userInfo: [String: Any]) throws }`. Context keys are the message types (`account_binding`, `plans_snapshot`, `health_snapshot`), each value a JSON string; userInfo is `["json": String]`. Order inside a context: binding first. A binding with a new key clears the previous key's plans and health (`wipeUnsent: false`) before saving. Plans/health whose `account_key` differs from the stored binding are dropped. `account_cleared` → `clearAccount(key, wipeUnsent:)`. Undecodable entries are skipped (counted in a `rejectedCount` for tests), never crash.
  - `enum GlanceState: Equatable { case notPaired; case ready(Glance) }`, `struct Glance: Equatable { readiness: ReadinessLine?; tiles: [GlanceTile]; caption: String; today: PlanRow?; plans: [PlanRow] }`, `struct GlanceTile: Equatable { label; value; unit: String? }`, `static func make(journal: WatchJournal, now: Date, timeZone: TimeZone, locale: Locale) throws -> GlanceState`.
  - Tiles, in order: Sleep (asleep as "7h 12m", plus score when present), Resting HR (bpm), HRV (ms), Steps. Missing field → value "—". Caption: "as of 7:10 AM" (locale short time of `as_of_utc`) when health matches today's local date; otherwise **"Open BeyondRep on your iPhone to refresh"** and no readiness and all tiles "—". No binding → `.notPaired`.
  - `ReadinessLine { score: Int; band: String; headline: String }` straight from the snapshot.

- [ ] **Step 1: Write the failing tests:** `binding replaces and clears the previous account's plans and health`; `plans for another account are dropped`; `account_cleared without wipe keeps the outbox`; `bad JSON entry is skipped and counted`; `glance not paired without binding`; `glance shows readiness and tiles for today`; `glance after midnight shows the refresh caption and dashes` (as_of 23:50 local, now 00:05); `missing steps shows a dash, not 0`; `journal migrates user_version 1 to 2 keeping outbox rows`.
- [ ] **Step 2: Push**, run `watchos_smoke.yml` on the branch — FAIL in the new tests.
- [ ] **Step 3: Implement.** **Step 4: Push**, CI — PASS.
- [ ] **Step 5: Commit** `feat(watch-core): phone inbox, account binding and glance state`

---

### Task 2: Phone snapshot builders

**Files:**
- Create: `apps/mobile/lib/features/watch/application/watch_snapshots.dart`
- Test: `apps/mobile/test/watch/watch_snapshots_test.dart`

**Interfaces:**
- Consumes: stage-2 `WatchMessage` codecs, `watchAccountKey`; `HealthOverview` (`health_overview.dart`), `ReadinessOverview.result`, `WorkoutLibrarySnapshot` (`trainLibraryProvider`), `ProgramWeek` (`programWeekProvider`), completed history (`completedWorkoutHistoryProvider`), the unit preference in `lib/core/units/load_units.dart`.
- Produces (pure functions, ids and clock injected):
  - `AccountBindingMessage buildAccountBinding({required String accountKey, required String unit, required String messageId, required DateTime nowUtc})`
  - `AccountClearedMessage buildAccountCleared({required String accountKey, required bool wipeUnsent, required String messageId, required DateTime nowUtc})`
  - `PlansSnapshotMessage buildPlansSnapshot({required String accountKey, required WorkoutLibrarySnapshot library, ProgramWeek? week, required List<…> recentSessions, required DateTime nowUtc, required String messageId})` — plan order: today's program plan, then by most recent use, then name; truncate to the contract caps; `today` set only when the program has a workout today; `recent_exercises` = last 30 distinct exercises from completed sessions.
  - `HealthSnapshotMessage? buildHealthSnapshot({required String accountKey, required HealthOverview? overview, required DateTime localNow, required String messageId})` — null when overview is null or `readAt` is not today's local date. Readiness only for `ReadinessReady`: `score`, `band` (`good|fair|low`), `headline` and `reason` reusing the exact strings the phone's readiness card shows (find them in `lib/features/health/widgets/readiness_card.dart` / `readiness_strip.dart`; extract to a shared function if they are private, without changing their text). Each other field only when the overview has it (a `SectionGap` omits it).
  - (Use the concrete stage-2 class names; the names above stand for the binding/cleared/plans/health subclasses of `WatchMessage`.)

- [ ] **Step 1: Write the failing tests:** `binding round-trips through the codec`; `health snapshot omits missing values instead of zero`; `no health snapshot when readAt is yesterday`; `readiness headline equals the phone card's text` (compare with the shared function); `not-ready readiness is omitted`; `plans put today's program plan first`; `150 plans x 40 exercises stays under 60000 bytes and within caps`; `every built message passes WatchMessage.fromJson(toJson())`.
- [ ] **Step 2: Run** `flutter test test/watch/watch_snapshots_test.dart` — FAIL. **Step 3: Implement.** **Step 4: Run** — PASS.
- [ ] **Step 5: Commit** `feat(watch): phone-side watch snapshot builders`

---

### Task 3: iOS WatchConnectivity bridge and Dart link

**Files:**
- Create: `apps/mobile/lib/features/watch/data/watch_link.dart`, `apps/mobile/ios/Runner/WatchLinkBridge.swift`
- Modify: `apps/mobile/ios/Runner/AppDelegate.swift` (register the channel in `didInitializeImplicitFlutterEngine` next to `northstar/workout_export`), `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (add `WatchLinkBridge.swift` to Runner sources)
- Test: `apps/mobile/test/watch/watch_link_test.dart`

**Interfaces:**
- Produces:
  - `abstract interface class WatchLink { Future<bool> isReachableForUpdates(); Future<void> updateContext(Map<String, String> latestByType); Future<void> transfer(String json); }`
  - `class MethodChannelWatchLink implements WatchLink` on channel **`beyondrep/watch_link`**, methods `isReachableForUpdates` (bool: `isPaired && isWatchAppInstalled` after activation), `updateContext` (`{type: json}`), `transfer` (`{json}`). Platform errors map to a quiet `false`/no-op (never surface WatchConnectivity errors to UI); `MissingPluginException` → treated as unsupported.
  - `class NoopWatchLink implements WatchLink` (Android, tests).
  - `final watchLinkProvider = Provider<WatchLink>` — `MethodChannelWatchLink` on iOS, `NoopWatchLink` elsewhere.
  - Swift `final class WatchLinkBridge: NSObject, WCSessionDelegate` — activates once, `updateApplicationContext(_:)` with the map, `transferUserInfo(["json": json])`; all calls no-ops when `!WCSession.isSupported()`.
- [ ] **Step 1: Write the failing tests** (mock the method channel): `updateContext sends the map unchanged`; `transfer sends json`; `MissingPluginException means unsupported and nothing throws`; `platform error from updateContext is swallowed`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** Dart and Swift. **Step 4: Run** Dart tests — PASS (Swift compiled in Task 6's iOS CI job).
- [ ] **Step 5: Commit** `feat(watch): WatchConnectivity bridge for the iPhone app`

---

### Task 4: Watch sync controller

**Files:**
- Create: `apps/mobile/lib/features/watch/application/watch_sync_controller.dart`
- Modify: the app root where app-wide listeners start (find where `workoutUploadKickProvider` or similar app-lifetime providers are kept alive, e.g. `lib/app/beyondrep_app.dart`), and the account deletion success path (`account_auth_controller.dart` ~line 588) to call `accountDeleted`
- Test: `apps/mobile/test/watch/watch_sync_controller_test.dart`

**Interfaces:**
- Consumes: Task 2 builders, Task 3 `watchLinkProvider`, `accountAuthControllerProvider` (`signedInUserId`), the providers listed in Task 2, `localNowProvider`.
- Produces: `final watchSyncControllerProvider` (kept alive for the app's lifetime) with `Future<void> accountDeleted(String userId)`.
  - Signed in and `isReachableForUpdates()`: build binding + plans + health (when available) and call `updateContext` with all present entries, **debounced 2 s** after any input changes, and only when the JSON (ignoring `message_id` and `sent_at_utc`/`generated_at_utc`) differs from the last sent.
  - Signed-in user id changes from A to anything else: first `transfer(account_cleared(key(A), wipeUnsent: false))`, then proceed for the new state; with no new user, also `updateContext({})`.
  - `accountDeleted(userId)`: `transfer(account_cleared(key, wipeUnsent: true))`.
  - Not reachable / Noop: nothing sent; re-check on app resume (`AppLifecycleListener`).
- [ ] **Step 1: Write the failing tests** (fake `WatchLink` recording calls, `fake_async` for the debounce): `signed in sends binding, plans and health in one context`; `identical rebuild does not resend`; `health refresh resends only after 2 s`; `sign out sends account_cleared for the old key before anything else`; `account switch A to B: cleared(A) then B's binding`; `account deletion sends wipe true`; `not reachable sends nothing`; `noop link on Android sends nothing and throws nothing`.
- [ ] **Step 2: Run** — FAIL. **Step 3: Implement** and wire. **Step 4: Run** the file and `flutter test test/account` — PASS.
- [ ] **Step 5: Commit** `feat(watch): keep the watch's plans and health glance current`

---

### Task 5: Watch app Home screen and phone link

**Files:**
- Create: `apps/watch_os/Sources/Connectivity/PhoneLink.swift` (`WCSessionDelegate`: `didReceiveApplicationContext` → `PhoneInbox.receive(applicationContext:)`, `didReceiveUserInfo` → `receive(userInfo:)`; also reads `receivedApplicationContext` on activation), `apps/watch_os/Sources/Features/Home/HomeView.swift`, `apps/watch_os/Sources/App/AppModel.swift` (owns the journal at Application Support `beyondrep-watch.sqlite`, recomputes `GlanceState` on inbox changes and on `scenePhase` active and at local midnight)
- Modify: `apps/watch_os/Sources/App/BeyondRepWatchApp.swift`, delete `apps/watch_os/Sources/Features/Workout/WorkoutHomeView.swift` (placeholder), `apps/watch_os/project.yml` (bundle id `in.beyondrep.app.watchkitapp`, remove `WKWatchOnly`, add `WKCompanionAppBundleIdentifier: in.beyondrep.app`, add the core package's `Sources/BeyondRepWatchCore` to the target's sources, exclude Tests)

HomeView (Performance V2 colours from `docs/DESIGN_SYSTEM.md` dark tokens; mockup board "Apple Watch: home and workout" in https://claude.ai/artifact/Ti6r6dNGEiJF9zReV9b57V): `.notPaired` → "Open BeyondRep on your iPhone to sign in." `.ready` → readiness ring with score and headline (or nothing when absent), the caption line, a 2×2 grid of tiles, then "Today: <label>" if present and the plan names list (read-only, no buttons). Dynamic Type, VoiceOver labels per tile ("Resting heart rate, 54 beats per minute", "Steps, no data").

- [ ] **Step 1:** Implement (UI logic already tested in Task 1).
- [ ] **Step 2: Push**, CI: `watchos_smoke.yml` standalone build and package tests PASS.
- [ ] **Step 3: Commit** `feat(watch): Home glance and phone link`

---

### Task 6: Embed the watch app in Runner and build it in CI

**Files:**
- Create: `tool/embed_watch_target.rb`, `tool/Gemfile` + `tool/Gemfile.lock` (pin `xcodeproj`), `tool/test_watch_embedding.py`
- Modify: `apps/mobile/ios/Runner.xcodeproj/project.pbxproj` (generated by the script, committed), `.github/workflows/watchos_smoke.yml` (new job `ios-with-watch`), `docs/REPOSITORY_LAYOUT.md`/`apps/watch_os/README.md` (how the embedding is produced)

`embed_watch_target.rb` (idempotent; re-running changes nothing): adds target **`BeyondRepWatch`** (product type watch2 app, SDK watchos, deployment 10.0, bundle id `in.beyondrep.app.watchkitapp`, `GENERATE_INFOPLIST_FILE` with the same Info keys as `project.yml`, `SKIP_INSTALL = YES`, Automatic signing style) whose sources are file references to `../../watch_os/Sources/**/*.swift` and `../../watch_os/Packages/BeyondRepWatchCore/Sources/**/*.swift` (relative to `apps/mobile/ios`), links `libsqlite3.tbd`, and adds to Runner a target dependency plus a copy-files phase **"Embed Watch Content"** to `$(CONTENTS_FOLDER_PATH)/Watch`.

CI job `ios-with-watch` (macos-15, path filter `apps/watch_os/**`, `apps/mobile/ios/**`, `contracts/**`, the workflow): checkout, the Flutter setup action already pinned in `mobile_ci.yml`, `flutter pub get --enforce-lockfile`, then from `apps/mobile`: `flutter build ios --simulator --debug --no-codesign`, and assert `build/ios/iphonesimulator/Runner.app/Watch/BeyondRepWatch.app` exists.

- [ ] **Step 1: Write the failing test** `tool/test_watch_embedding.py`: pbxproj contains a target named `BeyondRepWatch` with `in.beyondrep.app.watchkitapp`, an "Embed Watch Content" phase in Runner, no `.swift` file under `apps/mobile/ios` other than `AppDelegate.swift`, `SceneDelegate.swift`, `WatchLinkBridge.swift` (ADR-0004), and (when `ruby` and the bundle are available) running the script again leaves the file byte-identical.
- [ ] **Step 2: Run** `python3 -m unittest tool.test_watch_embedding` — FAIL.
- [ ] **Step 3:** Write the script, `cd tool && bundle install && bundle exec ruby embed_watch_target.rb`, commit the pbxproj.
- [ ] **Step 4: Run** the test — PASS; `python3 -m unittest tool.test_workflow_action_pins` — PASS. **Push**, run the workflow — `ios-with-watch` PASS and the `.app` exists.
- [ ] **Step 5: Commit** `build(ios): embed the Apple Watch app in Runner`

---

### Task 7: TestFlight job, release rows and docs

**Files:**
- Modify: `codemagic.yaml` (`mobile-ios-testflight` only), `docs/IOS_TESTFLIGHT_CODEMAGIC.md`, `docs/RELEASE.md`, `docs/ROADMAP.md`, `CLAUDE.md`, `docs/WEARABLES.md`; `tool/test_codemagic_config.py` if it pins the job's shape

- `codemagic.yaml`: keep `ios_signing: distribution_type: app_store, bundle_identifier: in.beyondrep.app` (Codemagic's automatic signing also covers identifiers that extend it, per its docs; **unverified until the first run**). Add a comment naming the fallback. No other workflow changes.
- `IOS_TESTFLIGHT_CODEMAGIC.md` owner steps: (1) in Apple Developer, create App ID `in.beyondrep.app.watchkitapp` (HealthKit can be ticked now for stage 4); (2) run the job; (3) **if it fails on watch signing**, create an App Store profile for the watch ID, upload it to Codemagic code signing identities as `beyondrep_watch_app_store`, and switch the job to `provisioning_profiles: [beyondrep_app_store, beyondrep_watch_app_store]` with `certificates: [apple_distribution]`; (4) on the iPhone, TestFlight install → Watch app → BeyondRep → Install. Replace "No Apple Watch companion is embedded."
- `RELEASE.md` "Phase 4 stage 3" rows, all **not run**: TestFlight build installs the watch app; signed in, the watch shows the same readiness, sleep, resting HR, HRV and steps as the phone's Today/Health at the same "as of" time; plans list matches; phone in airplane mode → last glance stays with its time; after midnight → refresh caption; sign out on phone → watch shows "sign in"; sign in as a second account → no first-account data; large text and VoiceOver on both watch sizes.
- `ROADMAP.md`/`CLAUDE.md`/`WEARABLES.md`: stage 3 implemented in source, embedded companion present but not device-verified; update CLAUDE.md "Not implemented" so it no longer lists "iPhone companion embedding" but still lists watch workout recording.

- [ ] **Step 1:** Make the edits.
- [ ] **Step 2: Run** the full gate: from `apps/mobile` `dart format --output=none --set-exit-if-changed lib test`, `flutter analyze`, `flutter test`; from repo root `python3 -m unittest discover -s tool -p 'test_*.py'`; latest `watchos_smoke.yml` run on the head green (package tests, standalone build, `ios-with-watch`).
- [ ] **Step 3: Commit** `docs: Phase 4 stage 3 TestFlight steps and device rows`
