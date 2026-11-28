# Wear OS stage 2: link, glance and Play install — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** An Android phone paired with a Wear OS watch sends account binding, plans and today's health to the BeyondRep watch app over the Wear Data Layer; the watch shows Home and Train pages with detail screens and acks; the phone shows watch status; one Codemagic job builds and drafts both the phone and the watch bundles to Play so Adi can install them.

**Architecture:** Phone: a Kotlin `WearLinkBridge` in `apps/mobile/android` implements the existing `beyondrep/watch_link` method channel with Data Layer calls (spec 5.2 table), so the Dart watch code runs unchanged on Android except provider gates and labels. Watch: pure-Kotlin glance logic and Data Layer path rules in `:core`; Android glue (`WearableListenerService`, `DataClient`, `CapabilityClient`) and Compose for Wear OS screens in `:app`, tested with Robolectric + Compose UI tests on the JVM. Live workout traffic (`WatchLiveLink`) stays iOS-only until stage 4; recording is stage 3.

**Tech Stack:** Flutter 3.47.7 (phone Dart), Kotlin 2.1.20, AGP 8.9.2, `com.google.android.gms:play-services-wearable` 19.0.0 (phone and watch), `org.jetbrains.kotlinx:kotlinx-coroutines-play-services` 1.10.2, Wear Compose Material3 1.5.0 + `androidx.wear.compose:compose-navigation` 1.5.0, Robolectric 4.14.1, `androidx.compose.ui:ui-test-junit4` (BOM), Codemagic CLI `google-play`.

**Spec:** `docs/superpowers/specs/2026-11-27-wear-os-companion-design.md` (4.2 stage 2, 4.4, 5.2, 5.3, 5.4, 5.7). Reference implementation: Apple Watch stage 3 + the glance redesign (`apps/watch_os/Sources/Features/{Root,Home,Train,Detail,Sync,Onboarding,Design}`, `apps/watch_os/Sources/App/AppModel.swift`, `BeyondRepWatchCore/Glance/*`, `apps/mobile/ios/Runner/WatchLinkBridge.swift`), and `docs/superpowers/specs/2026-11-27-watch-glance-redesign-and-sync-status-design.md`.

## Global Constraints

- Data Layer paths (exact): phone → watch latest-wins `/beyondrep/context/<type>`; phone → watch queued `/beyondrep/queue/phone/<message_id>`; watch → phone queued `/beyondrep/queue/watch/<message_id>`. Each DataItem holds one key `json` (String, UTF-8). The receiver deletes a queued item after handing it on; context items are replaced by the phone and deleted when `updateContext` gets an empty map.
- Capabilities (exact): the watch app declares `beyondrep_watch_app`, the phone app declares `beyondrep_phone_app` (`res/values/wear.xml`, `android_wear_capabilities`).
- `watchStatus` on Android: `supported` = Wearable API available on this phone; `paired` = at least one connected node; `installed` = a node with `beyondrep_watch_app` (`FILTER_ALL`); `reachable` = such a node in `FILTER_REACHABLE`. No Wear companion app or Play services → `supported=false`, and the phone shows nothing (same as iPad).
- A Data Layer item is at most 100 KB; the phone never sends a larger `json` (bridge returns `FlutterError("too_large")`, Dart already swallows `PlatformException`).
- Labels: "Apple Watch" on iOS, "Watch" (title case in tags/titles, "watch" mid-sentence) on Android, through one helper. History tag on Android: "Watch" (spec 4.4).
- Health values only in `health_snapshot`, kept on the watch per ADR-0012 decision 4 as amended (today + 7 days, cleared at local midnight and on sign out, never logged). The watch reads no health itself in this stage and asks for no permission.
- Watch UI: same information and hierarchy as the Apple Watch (Home = readiness ring hero + even 2×2 tiles with "vs usual" lines + sync line; Home and Train are two vertical pages; Train lists today's program workout first, then plans; tapping opens a read-only plan preview; no Start button in this stage; detail screens for readiness, sleep and the trend metrics; "Open BeyondRep on your phone" when unbound). Performance V2 colours from `Palette.swift`. Round screens 192–240 dp, font scale up to 1.3, TalkBack labels.
- No new phone permission. No Health Services or Health Connect on the watch in this stage. `apps/watch_os` unchanged except one line in `WatchLinkBridge.swift` (Task 2).
- Public repo: no keys, no keystores, no real data. Codemagic references secrets by group/keystore name only.
- Merging and running Codemagic are Adi's; never claim a Codemagic or device run.

## Review Focus

1. Watch messages that arrive while the phone app is not running must reach Dart on the next start, exactly once per item — Task 2 test `pendingQueuedItemsAreDeliveredWhenDartStartsListening` (Dart side) and the bridge's `startMessages` flush.
2. An empty `updateContext` (sign out) must delete every `/beyondrep/context/*` item, or the watch keeps showing the last account's plans — Task 4 test `emptyContextMeansAccountCleared` on the watch side and the bridge delete in Task 3.
3. A context item and a queued item from the same phone in one `onDataChanged` batch must be applied in `sent_at_utc` order like Swift's inbox (binding before plans) — Task 4 test `batchAppliesBindingBeforePlans`.
4. Watch with no binding, then binding arrives while Home is open: Home must switch from the onboarding screen without a relaunch — Task 6 test `homeSwitchesWhenBindingArrives`.
5. Phone on Android without Wear OS companion app: no banner, no footer, no Account & sync section, no crash — Task 1 test `unsupportedAndroidShowsNothing`.

---

### Task 1: Phone Dart — Android gates and labels

**Files:**
- Create: `apps/mobile/lib/features/watch/domain/watch_platform.dart`
- Modify: `apps/mobile/lib/features/watch/data/watch_link.dart` (provider gate; `_attach('messages')` invokes `startMessages`, ignoring `MissingPluginException`/`PlatformException`), `apps/mobile/lib/main.dart:87` (wipe retrier on iOS and Android), `widgets/watch_install_steps_sheet.dart`, `widgets/watch_status_banner.dart`, `widgets/watch_status_footer.dart`, `widgets/watch_account_section.dart`, `apps/mobile/lib/features/progress/progress_page.dart:748`, `apps/mobile/lib/features/progress/workout_history_detail_page.dart:129`
- Leave iOS-only: `watch_live_link.dart` provider, live card, mirror page, `active_workout_page.dart` "Open on Apple Watch" (stage 4).
- Test: `apps/mobile/test/watch/watch_platform_test.dart`, extend the existing banner/footer/section/install-sheet/history widget tests.

**Interfaces:**
- Produces: `String watchName(TargetPlatform p)` → `'Apple Watch'` for iOS, `'Watch'` otherwise; `String watchNameInSentence(TargetPlatform p)` → `'Apple Watch'` / `'watch'`; `List<String> watchInstallSteps(TargetPlatform p)`. Android steps (exact): `'On your watch, open the Play Store.'`, `'Scroll to Apps on your phone.'`, `'Tap Install next to BeyondRep.'`.

- [ ] **Step 1:** Tests with `debugDefaultTargetPlatformOverride = TargetPlatform.android`: `watchLinkProvider` returns `MethodChannelWatchLink.shared`; footer reads `'Watch · synced …'`; banner and install sheet use the Android copy; history tag reads `'Watch'`; `unsupportedAndroidShowsNothing` (status `unsupported` → no banner, footer or section). iOS goldens/strings unchanged (existing tests stay green). `pendingQueuedItemsAreDeliveredWhenDartStartsListening`: a fake channel records `startMessages` on the first `messages` listener, then a `watchMessage` call reaches the stream.
- [ ] **Step 2:** Run `cd apps/mobile && flutter test test/watch test/progress` → new tests FAIL.
- [ ] **Step 3:** Implement. Banner copy on Android: reuse the iOS sentence structure with `watchInstallSteps`.
- [ ] **Step 4:** Run the same command → PASS; then `dart format --output=none --set-exit-if-changed lib test` and `flutter analyze` → clean. Commit (`feat(watch): Android watch gates and labels`).

### Task 2: iOS bridge accepts `startMessages`

**Files:** Modify `apps/mobile/ios/Runner/WatchLinkBridge.swift` (`case "startMessages": result(nil)`).

- [ ] **Step 1:** Add the case. No Swift test exists for the bridge; verified by the `ios-with-watch` CI build. Commit (`fix(watch): iOS bridge accepts startMessages`).

### Task 3: Phone Android Data Layer bridge

**Files:**
- Create: `apps/mobile/android/app/src/main/kotlin/in/beyondrep/app/WearLinkBridge.kt`, `apps/mobile/android/app/src/main/res/values/wear.xml`
- Modify: `MainActivity.kt` (register in `configureFlutterEngine`, unregister listeners in `onDestroy`), `apps/mobile/android/app/build.gradle.kts` (dependencies above).

**Interfaces:**
- Consumes: channel `beyondrep/watch_link` methods `isReachableForUpdates`, `watchStatus`, `updateContext` (Map<String,String>), `transfer` ({json}), `startMessages`; calls back `watchStateChanged`, `watchReachabilityChanged`, `watchMessage` (String) — same as `WatchLinkBridge.swift`.
- Produces: `class WearLinkBridge(context: Context, messenger: BinaryMessenger)` with `register()` / `dispose()`.

- [ ] **Step 1:** Implement with `Wearable.getDataClient/NodeClient/CapabilityClient` and coroutines (`await()`), results on the main thread. `updateContext`: put each `/beyondrep/context/<type>` with `setUrgent()`, delete context paths not in the map (all of them for an empty map). `transfer`: put `/beyondrep/queue/phone/<message_id>` (`message_id` read from the JSON; malformed → `FlutterError("bad_arguments")`). Incoming: a `DataClient.OnDataChangedListener` and `CapabilityClient.OnCapabilityChangedListener`; `/beyondrep/queue/watch/*` items are buffered until `startMessages`, then each is sent as `watchMessage` and deleted; on `startMessages` also read existing items with `getDataItems(Uri("wear://*/beyondrep/queue/watch/"), FILTER_PREFIX)`. Capability changes → `watchStateChanged` and `watchReachabilityChanged`.
- [ ] **Step 2:** Verification: `flutter build apk --debug --no-pub` from `apps/mobile` (needs an Android SDK; if absent locally, CI `mobile` job). No unit test: the bridge only maps calls; behaviour is pinned by Task 1's Dart tests and device rows in Task 8. Commit (`feat(watch): Android Wear Data Layer bridge`).

### Task 4: Watch core — Data Layer routing and glance

**Files:**
- Create in `apps/wear_os/core/src/main/kotlin/in/beyondrep/wear/core/`: `link/DataLayerPaths.kt`, `link/DataLayerRouter.kt`, `glance/LocalDay.kt`, `glance/GlanceState.kt`, `glance/DetailModel.kt`, `glance/SyncLine.kt`
- Test: `link/DataLayerPathsTest.kt`, `link/DataLayerRouterTest.kt`, ports of `GlanceStateTests.swift`, `DetailModelTests.swift`, `SyncLineTests.swift`

**Interfaces:**
- Produces: `object DataLayerPaths { fun context(type: String): String; fun phoneQueue(id: String): String; fun watchQueue(id: String): String; fun parse(path: String): Route? }` with `sealed interface Route { data class Context(val type: String); data class PhoneQueued(val id: String); data class WatchQueued(val id: String) }`. `class DataLayerRouter(inbox: PhoneInbox) { fun apply(changes: List<DataChange>, now: Instant): List<AckOutcome> }` with `data class DataChange(val path: String, val json: String?, val deleted: Boolean)`. Glance types and functions as in Swift (`GlanceState.make`, `DetailModel.make`, `SyncLine.make`, `WaitingWorkouts.make`), `Date` → `Instant`/`LocalDate` with an explicit `ZoneId`.

- [ ] **Step 1:** Tests: paths round-trip and reject other prefixes; `emptyContextMeansAccountCleared` (all context items deleted in one batch → the journal has no plans or health for the bound key, same effect as Swift receiving an empty application context — read `PhoneInbox.swift` to confirm what an empty context does and pin that); `batchAppliesBindingBeforePlans` (a `plans_snapshot` context change and an `account_binding` context change in one batch, plans listed first → plans are stored for the new key); deleted queued items and `WatchQueued` paths are ignored; glance ports.
- [ ] **Step 2:** `cd apps/wear_os && ./gradlew :core:test -Pbeyondrep.coreOnly=true --no-daemon` → FAIL. Implement. → PASS. Commit (`feat(wear-core): Data Layer routing and glance state`).

### Task 5: Watch link service

**Files:**
- Create in `apps/wear_os/app/src/main/java/in/beyondrep/wear/`: `link/LinkListenerService.kt`, `link/DataLayerLink.kt`, `app/WatchGraph.kt` (process singleton: `AndroidSqlDatabase`, `WatchJournal`, `PhoneInbox`, `DataLayerRouter`, a `StateFlow<Long>` journal revision bumped after every write), `res/values/wear.xml`
- Modify: `AndroidManifest.xml` (service with `com.google.android.gms.wearable.DATA_CHANGED` filter for `/beyondrep` prefix), `app/build.gradle.kts` (dependencies; `testOptions.unitTests.isIncludeAndroidResources = true`; Robolectric).
- Test: `app/src/test/java/in/beyondrep/wear/link/DataLayerLinkTest.kt` (Robolectric, with a fake `DataClient` wrapper interface `DataItems` so the link logic is testable).

**Interfaces:**
- Consumes: Task 4 router, Stage 1 `AckBuilder`.
- Produces: `interface DataItems { suspend fun put(path: String, json: String); suspend fun delete(path: String); suspend fun all(prefix: String): List<DataChange> }`; `class DataLayerLink(items: DataItems, router: DataLayerRouter, clock: () -> Instant)` with `suspend fun onChanges(changes: List<DataChange>)` (route, put each ack at `watchQueue(ackId)`, delete handled phone-queued items, bump revision) and `suspend fun catchUp()` (read all `/beyondrep/context/` and `/beyondrep/queue/phone/` items; called from the activity's `onResume`).

- [ ] **Step 1:** Tests: a queued `account_binding` produces one put at `/beyondrep/queue/watch/<ack id>` whose JSON decodes as an `ack` for that message, and deletes the phone item; `catchUp` applies items present before the app started; a malformed item is deleted and acked as Swift does (or ignored, whichever `PhoneInbox` does — pin it).
- [ ] **Step 2:** `./gradlew :app:testDebugUnitTest` → FAIL (CI or a machine with the SDK). Implement. → PASS. Commit (`feat(wear): Data Layer link service`).

### Task 6: Watch screens

**Files:**
- Create in `apps/wear_os/app/src/main/java/in/beyondrep/wear/ui/`: `Palette.kt`, `RootScreen.kt` (vertical pager Home/Train + navigation), `HomeScreen.kt`, `TrainScreen.kt`, `PlanPreviewScreen.kt`, `ReadinessDetailScreen.kt`, `SleepDetailScreen.kt`, `TrendDetailScreen.kt`, `SyncScreen.kt`, `UnboundScreen.kt`, `WatchViewModel.kt` (maps journal revision + clock → `GlanceState`, plan rows, sync line; midnight tick)
- Modify: `WearMainActivity.kt` (hosts `RootScreen`, calls `catchUp` on resume; remove the "coming soon" text)
- Test: `app/src/test/java/in/beyondrep/wear/ui/*Test.kt` (Robolectric + `createComposeRule`)

**Interfaces:**
- Consumes: `WatchGraph`, glance types (Task 4), `WatchJournal.plans/health/bindingState/lastReceivedMs`.
- Produces: `class WatchViewModel(graph: WatchGraph, clock: () -> Instant, zone: () -> ZoneId) : ViewModel` exposing `StateFlow<WatchUi>`; `sealed interface WatchUi { data object Unbound; data class Ready(val glance: GlanceState, val plans: List<PlanRow>, val today: PlanRow?, val sync: SyncLine) }`.

- [ ] **Step 1:** Tests: `homeShowsReadinessAndFourTiles` (fixture `health_snapshot_full.json` → score text, four tile labels, "vs usual" lines); missing value shows "—" never "0"; `homeSwitchesWhenBindingArrives`; Train lists today's program workout first; tapping a plan opens the preview with its exercises; no Start button exists; detail screens open from tiles; content descriptions present for ring and tiles; layout at 192 dp and 240 dp round with font scale 1.3 has no clipped text (assert `assertIsDisplayed` on the last tile).
- [ ] **Step 2:** Run `./gradlew :app:testDebugUnitTest` → FAIL. Implement by porting the SwiftUI views' structure and copy; Wear components: `ScalingLazyColumn`, `VerticalPager` (or `HorizontalPageIndicator`-free vertical pages with dots), `AppScaffold`/`ScreenScaffold`, `TimeText`, `CircularProgressIndicator` for the ring. Rotary scrolling via `rotaryScrollable` (default in `ScalingLazyColumn`).
- [ ] **Step 3:** Run → PASS. Commit (`feat(wear): Home, Train and detail screens`).

### Task 7: Release signing and the Play job

**Files:**
- Modify: `apps/wear_os/app/build.gradle.kts` (release `signingConfig` from the same `CM_KEYSTORE_PATH`/`CM_KEYSTORE_PASSWORD`/`CM_KEY_ALIAS`/`CM_KEY_PASSWORD` or `apps/wear_os/key.properties`, failing when `BEYONDREP_REQUIRE_RELEASE_SIGNING=true` and none is set, copied from `apps/mobile/android/app/build.gradle.kts:9-96`; `versionCode`/`versionName` from Gradle properties `beyondrep.versionCode`/`beyondrep.versionName`, defaults 1/"0.1.0"), `.gitignore` (`apps/wear_os/key.properties`), `codemagic.yaml` `mobile-android-release`, `scripts/codemagic_android_version.py`, `tool/test_codemagic_android_version.py`, `tool/test_codemagic_config.py`, `docs/ANDROID_PLAY_CODEMAGIC.md`.

**Interfaces / rules:**
- The job builds the phone AAB with build number N (unchanged) and then the watch AAB from `apps/wear_os` with `-Pbeyondrep.versionCode=$((N+1)) -Pbeyondrep.versionName=$BEYONDREP_VERSION_NAME`, Java 17, `bundleRelease`; refuses a debug-signed watch AAB like the phone step; artifacts include both AABs.
- Upload: phone to `$NS_PLAY_TRACK` as today; watch to `wear:$NS_PLAY_TRACK` (Play's Wear OS form-factor track), both `--draft`, same release name. Before writing, run `pip install codemagic-cli-tools` and `google-play bundles publish --help` to confirm the flags and whether form-factor track names are accepted; if not, stop and report.
- Version script: the latest Play build must include Wear form-factor tracks, so the next phone build is above the last watch build. Test: Play reports internal 40 and wear:internal 41 → next N = 42 (watch 43).
- Docs: owner steps in Play Console (add the Wear OS form factor, opt in to Wear OS testing tracks, add testers), and that both builds use the same upload key so Play App Signing gives them the same signing key (Data Layer requirement).

- [ ] **Step 1:** Python tests first (`python3 -m unittest tool.test_codemagic_android_version tool.test_codemagic_config`) → FAIL; implement → PASS; run the whole `tool` suite → PASS.
- [ ] **Step 2:** `./gradlew :app:bundleRelease` cannot run without the keystore; verify `:app:assembleDebug` still works (CI). Commit (`feat(release): build and draft the Wear OS bundle with the phone release`).

### Task 8: Docs and CI

**Files:** `.github/workflows/mobile_ci.yml` (`wear_os` job: `./gradlew :core:test :app:testDebugUnitTest :app:assembleDebug --no-daemon`), `docs/RELEASE.md` (Wear OS stage 2 device rows: install both from the internal track; bind after sign-in; Home and Train show plans and health; sign out clears the watch; phone without the watch app shows the install banner; phone app killed, watch acks arrive next start; airplane mode on watch then back), `docs/ROADMAP.md`, `CLAUDE.md` (Wear OS stage 2 bullet, implemented in source, not released or device-verified), `docs/adr/0015-wear-os-companion.md` (consequences: stage 2), `apps/wear_os/README.md`, `apps/wear_os/AGENTS.md` if a rule changed, `docs/WEARABLES.md`.

- [ ] **Step 1:** Write. Run the whole Python `tool` suite, `flutter test`, `dart format …`, `flutter analyze`, `:core:test`. Commit (`docs(wear): stage 2 docs, device checks and CI`).
