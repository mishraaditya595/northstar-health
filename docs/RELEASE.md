# BeyondRep release-readiness gates

**Status (27 October 2026):** Phase 1 and P2-01–P2-07 source features are merged, **not released or verified for production**. P2-08 hosted security, native-device and large-history/data-rights acceptance is outstanding. Watch recording and health writes remain unimplemented; Phase 3 health reads exist in source only (see Phase 3 gates below); neither mobile nor watch app is ready for store distribution.

## Source and builds

- Mobile Flutter project rooted at `apps/mobile`, version-controlled Android and iOS runners plus `pubspec.lock`; no project generation in normal CI.
- Separate `apps/wear_os` APK build with committed official Gradle wrapper and Kotlin/Compose app.
- SwiftUI `apps/watch_os/Sources` is the single watch source; XcodeGen proof-target compiles only on macOS with Xcode/watchOS SDK. **An actual Apple Watch companion target embedded in the iOS Runner/Xcode workspace is still a blocker.**
- Mobile iOS Release archive with correct app ID, provisioning/signing, HealthKit entitlements only when health is implemented; validate launch and rotation on phones/iPads.
- Watch iOS embedding, companion bundle identifiers, signing, TestFlight archive/physical pairing and watch-only source experiment must not be confused.
- Wear OS uses final app identity/signing, Play Console declarations and physical round-watch layout tests; package IDs in scaffolding are placeholders.
- Keep FlutterWatch custom toolchain out of stable builds; experimental comparison only.
- **Versioning:** the manual TestFlight and Play jobs take a `release_type` input (`Fix or optimisation`, `Feature`, `Major`, `Same version, new build`, `Exact version`). The version name is worked out from the highest version in App Store Connect and Google Play, and the build number is the latest store build plus one on `AUTO` ([iOS details](IOS_TESTFLIGHT_CODEMAGIC.md#version-name-and-build-number), [Android details](ANDROID_PLAY_CODEMAGIC.md#version-name-and-versioncode)). The pubspec `version:` is not read by these jobs.

**Controlled backend deployment pipeline:** Codemagic now has [two manual Supabase jobs for database migrations and Edge Functions](SUPABASE_CODEMAGIC_DEPLOY.md), with preview/deploy inputs, project-bound protected credentials, explicit target confirmation and operator acceptance. The existence of these workflows is **not evidence of any hosted deployment**. Nine app/watch Codemagic builds remain templates; the manual [`mobile-ios-testflight` job](IOS_TESTFLIGHT_CODEMAGIC.md) uploads for internal TestFlight testing only and the manual [`mobile-android-release` job](ANDROID_PLAY_CODEMAGIC.md) uploads only drafts to Play testing tracks. Neither is a release.

## P2-08 immediate release blockers

**P2-08 work started, not passed:** The [hosted preflight and release execution plan](implementation/phase-2/p2-08-hosted-release-plan.md) adds a read-only, two-signed-user security audit and synthetic CI tests. The connected development project was observed with 6/11 migrations and no Edge Functions on 27 October 2026; no deployment or real-account audit has been performed. The read-only audit is only a subset of hosted release acceptance.

- **Hosted database rollout:** reconcile migration history with the **11 committed migrations** (including the P2-07c fresh Auth-session gate) and verify UTC backfill semantics and transaction/index impact before deploying to a data-bearing project. The repository does not prove hosted application.
- **Real-account security:** independently test signed user JWTs and RLS against a nonproduction hosted project: cross-user SELECT/RPC restrictions, two-device upload/restore/revisions/tombstones, stale/deleted-user JWT paths, fresh-session deletion gate, Auth hard-delete cascades and network-uncertain recovery. Synthetic pgTAP and mocked HTTP are necessary but not substitutes.
- **JSON export rights:** export streams page-by-page through a protected temporary file (no size cap; bounded-memory in code, unmeasured on hardware). Measure Android/iOS low-memory behavior and native SAF/UIDocumentPicker lifecycle with histories well above the former 4 MiB cap before release. Verify complete and correct synthetic exports.
- **Safe account exit:** device-test confirmation, verified deletion cleanup/retry, fail-closed uncertainty, and ADR-0007's two separately confirmed recovery exits (keep original owner's files locked, or explicitly erase only that owner's local partition), including cancellation and crash/relaunch.
- **Operations/privacy:** owner-scoped receipt-expiry pruning schedule, backup/restore epoch rotation runbook, legal retention/disclosure, secure logging and independent security review. No diagnostics data collection until the separately reviewed Firebase gate is met.

Track evidence in [P2-08 export validation](implementation/phase-2/p2-08-workout-export-release-validation.md) and the [account deletion runbook](../supabase/ACCOUNT_DELETION_RUNBOOK.md).

## Phase 3 health-read release gates (owner actions, none done)

Implemented in source, **not released or device-verified**. Evidence and unrun checks: [p3-01](implementation/phase-3/p3-01-daily-health-summary.md).

- **Apple signing, before the next TestFlight build:** enable the HealthKit capability on the App ID in the Apple developer portal and regenerate the App Store provisioning profile used by the Codemagic TestFlight job. The app now ships a HealthKit entitlement, so signing is expected to fail without this. Not done.
- **Privacy policy live (issue #52):** the Health Connect rationale screen now opens `https://beyondrep.in/privacy` (not device-tested). The page is still marked Draft and must be final before the Health apps declaration. Not done.
- **Store declarations:** App Store privacy labels; Google Play Data Safety form and Health Connect permissions declaration. Not done.
- **Builds:** the first Android debug APK build happens in GitHub Actions on the PR (not run locally); no Xcode build has been run, and the hand-edited Runner project and entitlements are unverified in Xcode.
- **Manual device matrix (all not run):**
  - iPhone with and without Apple Watch: grant, deny, revoke.
  - Android 14+ and Android 9-13, with and without the Health Connect app.
  - Android partial grant (some types allowed, others denied).
  - Android: deny twice, then tap Not allowed · Manage (Health Connect may stop showing the sheet).
  - Android: Not allowed · Manage opens Health Connect settings (not run).
  - Android: session-only sleep source shows the session duration (not run).
  - Android workout JSON export still saves after the `FlutterFragmentActivity` change (highest risk).
  - Account A, sign out, account B: B sees the Connect card.

## Health insights stage 1 device QA (ADR-0009, owner actions, none done)

Implemented in source on a feature branch, **not released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Two wearables write sleep the same night (e.g. watch and ring): one source per night, caption names it | not run | not run |
| Phase 3 account upgrades: "Allow more data" shows once, hides after one request even with types still declined | not run | not run |
| Health Connect history permission granted vs not: 30-day and earlier reads | n/a | not run |
| iOS denial of the new types reads as empty, never 0 | not run | n/a |
| Text scale 2.0 on overview and the four detail screens | not run | not run |
| Tablet / split screen layout | not run | not run |
| Light and dark themes | not run | not run |
| A Health Connect source that writes sleep sessions without stages: the night shows its duration, no stages, no score | n/a | not run |
| Skin temperature on a Pixel / Galaxy Watch: sleep detail shows a deviation vs baseline, never an absolute °C | n/a | not run |

## Health insights stage 2 device QA (ADR-0009, owner actions, none done)

Readiness is implemented in source, **not released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Good day with a watch: readiness card, detail screen and Today row show a score and its parts | not run | not run |
| Low day: note on the Train card, and the start note appears once per day before a workout (Train and Today) | not run | not run |
| HRV without resting heart rate (and the reverse): score still shows from the input present | not run | not run |
| Baseline building (under 14 days): "not ready" with days remaining, no score | not run | not run |
| Phone only, no watch or wearable: no score, no zero | not run | not run |

## Health insights stage 3 device QA (ADR-0009, owner actions, none done)

Training tie-ins are implemented in source, **not released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Muscle recovery map after a heavy leg day and after an arm day: legs fade over 72 h, arms over 48 h | not run | not run |
| Train "Better fit today" with real workout history: suggests the most recovered plan, never one hitting recovering muscles | not run | not run |
| Low readiness day: suggestion is the lightest recovered plan | not run | not run |
| Insights after 30 days of sleep, resting heart rate and workouts: "From your training" on Health, Sleep detail and Heart detail | not run | not run |
| Fewer than the minimum nights or sessions: no insight line shown | not run | not run |
| No wearable: Better fit and recovery lines still work, no insight lines | not run | not run |

## Health polish stage 1 device QA (ADR-0009, owner actions, none done)

The Today readiness hero and tiles, explain sheets, Health terms page and the Train start-card readiness strip are implemented in source, **not released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Today health row (hero or slim card, 2x2 tiles) in light, dark, 2x text and tablet split screen | not run | not run |
| Train start card with and without a program workout today; readiness strip opens the readiness detail; Low shows "Your plans are not changed" | not run | not run |
| Every explain (i) sheet and Health terms entry opens, reads correctly and closes with the screen reader on | not run | not run |
| Core vs Light sleep stage naming on Android | not run | not run |

## Health polish stage 2 device QA (ADR-0011, owner actions, none done)

Workouts from other apps and the training-load readiness input are implemented in source, **not released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Apple Watch (or another source) logs the same lift as a BeyondRep session: Activity and Progress show one merged session ("From Apple Watch · kcal · avg bpm"), not two, and the Today Workouts count is not raised | not run | n/a |
| A third-party app workout (for example a run): it shows in Activity, in Progress history tagged "From <app> · read only" with a read-only detail, and in the Today Workouts tile | not run | not run |
| Android 14+ with the history permission, and without it (only 30 days before the grant): the Workouts panel and history show what Health Connect returns, no error | n/a | not run |
| Android workouts show no kcal and no distance (only `READ_EXERCISE` is requested) | n/a | not run |
| Permission added after an existing connect: the Health tab shows "Allow more data", and tapping it requests only the new workouts type | not run | not run |
| Workouts not allowed (denied or not requested): Activity shows the gap row, Progress and Today look as before, readiness scores from BeyondRep-only load | not run | not run |
| Readiness with 14+ days of workouts: the detail lists Training load and its (i); with fewer days it is not listed and the score matches stage 1 | not run | not run |
| Account switch: sign in as another account, no workout or load from the first account appears | not run | not run |
| No outside workout, kcal, heart rate or load appears in Account > export, Supabase, logs or an iCloud/Android backup | not run | not run |

## Energy score stages 1 and 2 device QA (ADR-0013, owner actions, none done)

Energy on the Health tab hero, the detail Today view, Today, the Train strip, the pre-workout note, "Better fit today" and the watch is implemented in source, **not released or device-verified**. Every row is not run.

**Release gate:** energy stages 1 and 2 ship together; stage 3 tuning is implemented in source and its rows below are not run.

| Check | iOS | Android |
| --- | --- | --- |
| A morning gym session: energy drops after it and the detail shows its "Workout at" row | not run | not run |
| A late session finishing after midnight: energy still shows for the waking day that began at the morning wake, the session drains it, and calendar readiness for the new date stays not ready | not run | not run |
| A nap tracked by Apple Watch (iOS) or a Health Connect source (Android): a "Nap at" row adds recharge and never lifts energy above the morning start | not run | not run |
| The next morning before last night's sleep syncs: no stale energy from yesterday shows, the hero shows the not-enough-data state | not run | not run |
| Android without the active-energy permission: no "Active day so far" row and no zero, energy is still computed from the other parts | n/a | not run |
| Stage 2: the Today hero shows energy now with the change since morning and the learning line while it applies | not run | not run |
| Stage 2: the Train strip and the low note after a draining workout (good morning start, Low energy) | not run | not run |
| Stage 2: "Better fit today" on a low-energy afternoon picks the lightest recovered plan | not run | not run |
| Stage 2: watch Home and detail show energy and `· still learning`, cleared at local midnight | n/a | not run |
| Stage 2: VoiceOver and TalkBack read "Energy" on Today, Train and the watch, never "Readiness" | not run | not run |
| Stage 2: 41 mm Apple Watch Home shows the whole reason line including `· still learning` | not run | n/a |
| Stage 3: a late-night trainer (usual sessions 22:00-23:00) sees no awake dip at the usual hour and the dip at 15:00 | not run | not run |
| Stage 3: the first Health open of the day on Android does not hit the Health Connect read quota on repeated resumes (the three extra reads happen once per local day) | n/a | not run |
| Stage 3: an account switch drops the cached history and tuning | not run | not run |

## Phase 4 stage 3: watch link, glance and TestFlight embedding (owner actions, none done)

The iPhone app sends the signed-in account's plans and today's numbers to the BeyondRep Apple Watch app, which shows them read-only; the watch app is embedded in the iPhone build. All implemented in source, **not released or device-verified**. Compared values are the phone's own, never recomputed on the watch. Every row is not run.

| Check | Result |
| --- | --- |
| TestFlight build installs the BeyondRep watch app from the iPhone Watch app | not run |
| Signed in, the watch shows the same readiness, sleep, resting HR, HRV and steps as the phone's Today and Health tabs, with the same "as of" time | not run |
| The watch plan list matches the phone's plans, with today's program workout named when there is one | not run |
| Phone in airplane mode: the last glance stays, with its "as of" time | not run |
| After local midnight the watch shows "Open BeyondRep on your iPhone to refresh", no readiness and dashes, not yesterday's values | not run |
| Sign out on the phone: the watch shows "Open BeyondRep on your iPhone to sign in." | not run |
| Sign in as a second account: no data from the first account appears on the watch, also if the first account's messages arrive late | not run |
| A metric the phone lacks (no HRV, no steps) shows a dash on the watch, never 0 | not run |
| Resting HR, HRV and sleep reach the watch only when the phone has a value dated today, so a dash in the morning before today's reading exists is expected, not a fault | not run |
| Sign out, then force-quit and reopen the watch app: the account does not come back; sign in as the same account again: it binds | not run |
| The BeyondRep icon shows in the iPhone Watch app and on the watch | not run |
| Large text and VoiceOver on a small and a large watch: tiles read "Resting heart rate, 54 beats per minute" and "Steps, no data", nothing clipped | not run |
| Watch signing through the Codemagic job works without the fallback profile (see IOS_TESTFLIGHT_CODEMAGIC.md) | not run |

## Phase 4 stage 4a: watch workout import and `beyondrep_watch` origin (owner actions, none done)

The phone imports a completed workout from the watch, backs it up with origin `beyondrep_watch`, and resends an account-deletion wipe until the watch confirms it. Implemented in source, **not released or device-verified**. The watch cannot send a completed workout until stage 4b, so the import cannot be tested end to end yet. Every row is not run.

| Check | Result |
| --- | --- |
| Deploy order: the `supabase-database` job has applied `20261127090000_workout_origin_beyondrep_watch.sql` to the project under test before any build that uploads watch workouts | not run |
| Every install on every phone of the test account is updated before the first watch workout is uploaded (older builds refuse the origin when restoring and also fail the whole account JSON export and conflict review once any watch workout exists in the cloud) | not run |
| `Supabase SQL and RLS` (`workout_watch_origin` and the existing pgTAP files) passes on the PR | not run |
| A watch workout restored on a second phone shows the Apple Watch tag in history and its detail | not run |
| A watch workout appears once in Account > export with origin `beyondrep_watch` | not run |
| Delete the account with the watch out of range, then bring it in range: the watch drops that account's unsent workouts | not run |
| Delete the account with the watch out of range, force-quit and relaunch with the watch in range: the wipe is resent and the watch drops the workouts | not run |

## Phase 4 watch glance redesign and sync status (owner actions, none done)

The two-page watch app, its detail screens and the watch status on the iPhone are implemented in source, **not released or device-verified**. The Swift unit tests run in `watchos_smoke.yml`; none of these device checks is CI. Every row is not run.

| Check | Result |
| --- | --- |
| TestFlight build installs on the watch; Home shows the readiness hero and an even 2x2 grid with a status line on each tile | not run |
| The Train button in the bottom corner of Home opens the Train page; the crown also scrolls between Home and Train; the "Turn the crown for your workouts" hint shows once and "Got it" dismisses it for good | not run |
| Train shows today's program workout first, then the plans, with no Start button | not run |
| Every tile, the hero and the top status line open a detail screen; sleep shows stages, resting HR and HRV a dashed usual line, steps bars with today highlighted, readiness one line per input; a day without data has no mark, never 0 | not run |
| The detail values match the phone's Health tab and the readiness words match the phone | not run |
| Large text and VoiceOver on a 41 mm and a larger watch: tiles read "Resting heart rate 61 beats per minute, 2 below your usual", the grid falls back to one column, nothing clipped | not run |
| Turn Bluetooth off on the iPhone: the watch top line says "Phone not nearby", the Sync screen shows the dated data; turn it on: "Synced" with the time | not run |
| Open the watch app before signing in on the phone: the Sync screen says "Open BeyondRep on your iPhone" | not run |
| The iPhone shows "Apple Watch · synced" at the bottom of Today only after the watch has confirmed; Account & sync shows Connected, Installed, Last synced and what was sent | not run |
| Delete the watch app: the iPhone shows "BeyondRep isn't on your watch yet" at the top of Today; "Show me how" opens the three steps; "Not now" hides the banner for good while Account & sync still says Not installed | not run |
| Leave the watch out of use for two days while the iPhone app keeps sending: the iPhone banner says the watch has not synced since the last confirmation | not run |
| An iPhone with no paired Apple Watch, an iPad and an Android phone show no banner, no footer and no Apple Watch section | not run |
| After local midnight the watch shows no detail screen from the day before | not run |
| An old watch build next to the new phone build shows dashes, no crash (the new snapshot is rejected until the watch updates) | not run |
| After updating from the previous build, the watch sync line appears once the phone sends (it reads "Not paired" style until then) | not run |
| Relaunch the watch app several times: the "Synced" day and time on Home does not move until the iPhone sends something new | not run |
| Open the iPhone app after three days away: Today shows the old synced time, not the "hasn't synced" banner; the banner appears only when a send has gone unconfirmed for 48 hours | not run |

## Phase 4 stage 1: tablet layouts (owner actions, none done)

Wide-window layouts (window width 840 dp or more) are implemented in source, **not released or device-verified**. The automated sweep (`test/accessibility/wide_layout_sweep_test.dart`) checks for overflow at five sizes, both themes and 200 % text in the test font; it does not replace these checks. Every row is not run.

| Check | iPad | Phone |
| --- | --- | --- |
| iPad simulator landscape (Today, Train, Exercises, Workouts, Programs, Progress, Health and each Health detail) in light and dark: two columns or grids as designed, nothing clipped | not run | n/a |
| Split view dragged across 840 dp with a Progress workout, an exercise, a workout or a program open: the open item stays open as a pushed page when the window narrows, and the list stays when it widens | not run | n/a |
| 200 % text on iPad landscape: grids drop to fewer columns, nothing overflows | not run | n/a |
| iPad portrait (820 wide) and phone: every screen looks as before, one column | not run | not run |
| Add program from the programs detail pane: the program opens on top and back returns to the Programs list | not run | n/a |

## Training library stage 2 device QA (ADR-0010, owner actions, none done)

The catalogue cache and exercise pickers are implemented in source, **not released or device-verified**, and need the stage 1 catalogue migrations applied to the project under test. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| First download: fresh install, sign in online, the Exercises page and both pickers show the catalogue exercises within a few seconds | not run | not run |
| Offline fresh install: signed in earlier, then wipe the cache, go offline, relaunch: the "hasn't downloaded yet" copy with Retry, local exercises still work, Retry succeeds once online | not run | not run |
| Airplane mode after a download: pickers and the Exercises page still list the saved catalogue | not run | not run |
| Kill the app during the first download: next launch has no partial catalogue, then downloads normally | not run | not run |
| Account switch: sign out and sign in as another account on the same backend: the second account sees the saved catalogue without a new download within 24 hours | not run | not run |
| Rollback: roll back to a previous release on the test project, pull to refresh: the app switches to the rolled-back release and shows no error | not run | not run |
| Pick a catalogue exercise in a plan and in an active workout: it is saved offline and logs sets | not run | not run |

## Training library stage 3 device QA (ADR-0010, owner actions, none done)

Specific muscles are implemented in source, **not deployed, released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Deploy order: the `supabase-database` job has applied `20261126010000_workout_exercise_muscles.sql` to the project under test **before** this build is uploaded | not run | not run |
| Update every TestFlight and Android install to this build: an older build rejects the new exercise fields when restoring | not run | not run |
| Recovery after an RDL day: finish a Romanian deadlift workout, then Progress shades hamstrings and glutes fully, lower back about half, quads not at all, and Train names Hamstrings and Glutes instead of Legs for plans of those exercises | not run | not run |
| Restore on a second device: sign in as the same account on a second device, the RDL workout restores and the body map shows the same muscles | not run | not run |
| Existing plans of the 18 built-ins show specific muscles after the catalogue downloads, without picking the exercises again | not run | not run |
| Exercise detail: open an exercise from the Exercises page, front and back body maps match the Primary and Secondary lists; a custom exercise shows the "Muscles aren't mapped yet" text | not run | not run |
| A workout logged before this build still uploads, restores and counts toward recovery by its coarse group | not run | not run |

## Training library stage 4 device QA (ADR-0010, owner actions, none done)

Timed sets are implemented in source, **not deployed, released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Deploy order: the `supabase-database` job has applied `20261126020000_workout_set_duration.sql` to the project under test **before** this build is uploaded | not run | not run |
| Update every TestFlight and Android install to this build: an older build rejects the new set field when restoring | not run | not run |
| Log a plank with the timer: Start, wait, Stop, record; the set shows seconds, there is no reps field, and the workout uploads | not run | not run |
| Background the app with a timer running, return after a minute: the stopwatch shows the real elapsed time. Force-quit the app with a timer running: the running timer is lost by design (it is a draft, never saved) and the seconds can be typed and recorded | not run | not run |
| Restore a timed workout on a second device: sign in as the same account, the plank set shows its seconds in history | not run | not run |
| Plan a plank at 45 s: the row reads "3 sets · 45 s" and a workout started from the plan logs seconds | not run | not run |
| A rep workout logged before this build still uploads, restores and counts as before | not run | not run |

## Training library stage 5 device QA (ADR-0010, owner actions, none done)

The expanded library (release 2, 240 exercises) and the picker filters are implemented in source, **not deployed, released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Deploy order: the owner has read the review sheet, merged, and the `supabase-database` job has applied `20261126030000_catalog_release_2.sql` | not run | not run |
| First download of release 2: an install with release 1 cached updates to 240 exercises on the next refresh and the Exercises page lists them | not run | not run |
| Picker scroll and filter at large text: at text size 200 percent, open the picker, scroll the full list, pick a muscle group chip and an equipment, then search; nothing overflows and rows stay tappable | not run | not run |
| Search by muscle: typing "hamstrings" lists Romanian deadlifts | not run | not run |
| Offline with a cached release 1, then online: the picker shows release 1 while offline and release 2 after reconnecting | not run | not run |
| Custom exercises and the 18 earlier built-ins still appear under All and under their own group chip | not run | not run |

## Training library stage 6 device QA (ADR-0010, owner actions, none done)

Workout templates (release 3, 16 templates) are implemented in source, **not deployed, released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Deploy order: the owner has read the template review sheet, merged, and the `supabase-database` job has applied `20261126040000_catalog_release_3.sql` | not run | not run |
| Browse: Train, then Workouts lists the templates; search and the level chips narrow the list; a template opens with every exercise, its sets, reps or seconds, rest and note | not run | not run |
| Start now on a template with a plank: the logger opens, the plank row logs seconds, rep exercises log reps and weight, and no plan is saved | not run | not run |
| Copy to My Plans twice: the first makes the plan, the second makes "<name> (2)"; the plan opens from the Edit action and from Your plans, and editing it never changes the template | not run | not run |
| Copy offline with the cached catalogue: the copy and a started workout work with no network | not run | not run |
| Start now while a workout is already running: the message shows and nothing changes | not run | not run |
| Text size 200 percent on a 7-exercise template in light and dark: nothing overflows and both buttons can be reached | not run | not run |
| Kill the app during a copy or a start, then reopen: either the whole plan or workout is there, or none of it | not run | not run |

## Training library stage 7 device QA (ADR-0010, owner actions, none done)

Programs (release 4, 17 programs) are implemented in source, **not deployed, released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Deploy order: the owner has read the program review sheet, merged, and the `supabase-database` job has applied `20261126050000_catalog_release_4.sql` | not run | not run |
| Add a program: Train, Programs, open one, pick the weekday and add it; Your program opens, its workouts are not under Your plans | not run | not run |
| Switch the active program: add a second one as active; the first shows Not active and Train shows the second | not run | not run |
| Edit the schedule: change a day to Rest, point a day at another workout, change the start day; the week updates and survives a restart | not run | not run |
| Start today's workout from Your program: the logger opens, the finished workout syncs as a normal workout and nothing about the program reaches the cloud | not run | not run |
| Edit a program workout in the plan editor: the changes stay, and there is no archive button | not run | not run |
| Archive a program: its plans disappear and logged workouts stay in history | not run | not run |
| Upgrade an install that has plans and workouts from the previous build: everything is still there and Programs opens | not run | not run |
| Text size 200 percent on a 6-day program and on Your program in light and dark: nothing overflows and the buttons can be reached | not run | not run |

## Training library stage 8 device QA (ADR-0010, owner actions, none done)

Today and scheduling (Today program card, missed days, filters, retiring) is implemented in source, **not released or device-verified**. It needs no database deploy and publishes no catalogue release. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Today on a training day with an active program: the program card shows the workout, exercise count and about minutes; Start opens the logger and Open program opens Your program | not run | not run |
| Today on a rest day: "Rest day" with "Next: <weekday> · <workout>" and no Start | not run | not run |
| Today after finishing the day's workout: "Done for today" with the next workout; the day is Done in Your program | not run | not run |
| Missed line: skip a training day, then on Today tap "Missed <weekday>: <workout>", confirm; the logger opens, and after finishing the missed day is Done and the line moves to an older miss or disappears | not run | not run |
| Older misses in the same week start from "Start for <weekday>" in Your program; a new program week clears them | not run | not run |
| Session across midnight: start at 23:50, finish after midnight; the start date is marked done, not the next day | not run | not run |
| Time-zone change after starting: change the device time zone mid-workout; the recorded day does not move | not run | not run |
| Schedule edit after sessions: change a day or the start day; finished days stay done, and the missed list follows the new schedule | not run | not run |
| Program switch: make a second program active; Today shows it, the first shows no Start and "Make this your active program to start its workouts" | not run | not run |
| Unfinished workout: Today keeps the Resume card above everything, with no program card or missed line | not run | not run |
| Filters: goal, equipment I have and days per week narrow Workouts and Programs, "Filters (n)" and Clear work, and nothing is remembered after leaving the page | not run | not run |
| Text size 200 percent on Today with the missed line, Your program with tags, and both filter sheets in light and dark: nothing overflows and the buttons can be reached | not run | not run |

## Training library release verification (ADR-0010, owner actions, none done)

One ordered script for the open rows of the stage 2 to 8 sections above, grouped so one sitting works on one device. It does not repeat those rows: each step names the row it closes ("S5 picker scroll" is the "Picker scroll and filter at large text" row of the stage 5 section). The automated part of stage 9 (accessibility guidelines, tablet and split-view layout, process-death store tests, catalogue performance in a container) is in [stage-9-verification.md](implementation/training-library/stage-9-verification.md); everything below is what that cannot show. Every cell is **not run**; nothing here is a device result.

Neither Account > Sync nor a debug log reports catalogue download time or size today. Use a stopwatch and the platform's network profiler (Xcode Instruments network, Android Studio Network Inspector or a proxy you trust) for steps 1.1 and 1.2.

| Step | What to do and what it closes | iOS | Android |
| --- | --- | --- | --- |
| **1. Fresh install** | | | |
| 1.1 | Sign in once, then wipe the catalogue cache (reinstall and sign in again), turn airplane mode on and relaunch: "hasn't downloaded yet" with Retry (S2 offline fresh install) | not run | not run |
| 1.2 | Go online and Retry: record seconds to a usable list and bytes downloaded (expect about 154 KB raw, up to 22.5 KB gzip, see [CATALOG.md](CATALOG.md)) (S2 first download, S5 first download of release 2) | not run | not run |
| 1.3 | Force-quit and relaunch with the cache present, no network: record seconds from tap to a populated Exercises page (cold cache load) | not run | not run |
| **2. Browse and search** | | | |
| 2.1 | Exercises page: type prefixes and an alias such as "hip bridge"; note any lag typing (S5 search by muscle) | not run | not run |
| 2.2 | Muscle group and equipment filters, then the picker at large text (S5 picker scroll and filter) | not run | not run |
| 2.3 | Open an exercise detail and a template detail; body maps match the lists (S3 exercise detail, S6 template screen) | not run | not run |
| **3. Workouts** | | | |
| 3.1 | Start now from a template; the workout logs and no plan is created (S6 start now) | not run | not run |
| 3.2 | Copy to My Plans, double-tap the button: one plan, editable, independent of the catalogue (S6 copy to My Plans, S6 double tap) | not run | not run |
| **4. Programs** | | | |
| 4.1 | Add a program on a Wednesday, set active, open Your program (S7 add program, set active) | not run | not run |
| 4.2 | Today card on a training day, rest day and after finishing; Start, Open program (S8 Today rows) | not run | not run |
| 4.3 | Skip a training day: the missed line, confirm, finish, the day is Done (S8 missed line, older misses) | not run | not run |
| 4.4 | Start at 23:50 and finish after midnight (S8 session across midnight) | not run | not run |
| 4.5 | Change the device time zone mid-workout (S8 time-zone change) | not run | not run |
| 4.6 | Edit a day, change the start day, switch the active program (S8 schedule edit, program switch) | not run | not run |
| **5. Process death** | | | |
| 5.1 | On a program day start the workout, log a set, force-quit, reopen: the Resume card is above the program card and finishing marks the day Done (S8 unfinished workout) | not run | not run |
| 5.2 | Tap Add program and force-quit within a second, reopen: either no program or exactly one, never a partial one; adding again gives one program or "(2)" only by choice (S7 kill during add) | not run | not run |
| **6. Accessibility** | | | |
| 6.1 | VoiceOver (iOS) and TalkBack (Android) through Today, Programs, Your program and the filter sheet: each day is read with its status and the filter button with its count | not run | not run |
| 6.2 | Text size 200 percent on Today with the missed line, Your program and both filter sheets, light and dark (S8 text size) | not run | not run |
| 6.3 | Reduced motion on, and dark mode: sheets and cards behave and nothing is unreadable | not run | not run |
| **7. Tablet** | | | |
| 7.1 | iPad portrait, landscape and split view; Android tablet or large-screen emulator where available: Today, Train, Programs, Your program, template detail; nothing stretches or overflows and the sheet buttons clear the bottom bar | not run | not run |
| **8. Low-end Android** | | | |
| 8.1 | A low-end phone with the 240 exercises: scroll the Exercises page and type in search; note dropped frames or lag | not run | not run |

## Feature and privacy readiness

- ObjectBox real sessions/sets with generated model UID fixture migration, durable offline writes and recovery through process death.
- No Supabase synchronization release until mandatory authentication, authenticated RLS, strict completed-workout DTO allowlist, conflicts, tombstones, owner-scoped restoration and privacy disclosures are verified under ADR-0005. The development RPC/migrations are not a release.
- HealthKit/Health Connect daily-summary reads are implemented in source (Phase 3, ADR-0008) but gated by the Phase 3 list below. No health writes or summary exports until permissions/consent, provenance, stale/denied, duplicate-platform-workout prevention and release policy review.
- No Firebase SDK collection until separate diagnostics/analytics default-off initialization, consent controls, redaction and synthetic leak tests.
- Watch set logging must persist locally and survive screen off, disconnect, battery constraints and reconnect before UI claims success; native sensors and workout lifecycle operate independently of UI. Two-stage ACK (watch->phone and phone->Supabase).

## Device validation

- Android low-memory device and current Android tablet in portrait/landscape, resizing; iPhone and iPad split view; dynamic text, talkback/voiceover and both themes.
- Apple Watch and Wear OS physical watch: real 60–90 minute workout, pause/resume/end, health permissions, workout summary ownership, power/battery/CPU profiling, offline log replay/duplicate handling, recovery after killed UI.
- Reproducible CI passes for contract fixtures, Flutter format/analyze/test/APK, Wear OS debug, macOS iOS/watchOS target builds.
- Distribution is gated by independent review and manual Apple/Google store smoke testing; passing unit tests alone never authorizes a release.

## Ordered engineering follow-ups

1. Finish the **P2-08 release gates above** before describing Phase 2 as shipped; retain real-device and hosted test evidence with commit SHA, environment and outcome.
2. Integrate `apps/watch_os/Sources` into an actual embedded iOS Runner watchOS companion target; verify bundle IDs, signing and TestFlight/physical pairing.
3. Verify mobile iOS, standalone watchOS and Wear OS builds in macOS/Android CI and profile low-end devices. Replace placeholder app identifiers only with approved production identities.
4. Complete the Phase 3 health-read gates above, then begin Phase 4 user-controlled health-platform summary export only after the separate consent and provenance designs are verified.
5. Implement durable native watch workout recording, offline event transport, deduplication and the watch-to-phone-to-cloud two-stage ACK before claiming wearable logging support.

## CI/CD cutover status

Codemagic will become the main build/release provider, but `codemagic.yaml` is currently a **manual-only, intentionally failing template**. Refer to [Codemagic setup](CODEMAGIC.md). Existing GitHub Actions checks remain the only verified build automation until Codemagic is connected and equivalent builds pass. No CI template authorizes store delivery or watchOS companion release.

## Phase 4 stage 4b: record workouts on the Apple Watch (device checks, none run)

The watch starts a plan, today's program workout or a quick workout, logs sets, rests with a haptic, saves one workout to Apple Health and sends it to the phone. Implemented in source, **not released or device-verified**. Every row is not run. The watch App ID has HealthKit and the `beyondrep_watch_app_store` profile includes it (confirmed by the owner on 2026-11-27, see [IOS_TESTFLIGHT_CODEMAGIC.md](IOS_TESTFLIGHT_CODEMAGIC.md)); no signed build with it has been run yet.

| Check | Result |
|---|---|
| A 45-minute workout with the phone left in another room: every set is kept, and the workout reaches the phone when it is back in range | not run |
| Screen off during rest: the haptic fires at zero | not run |
| Force-quit the watch app mid-workout: it restores to the same set with the same rest | not run |
| Force-quit right after Save: one HKWorkout in the Health app, and the workout appears on the phone | not run |
| Force-quit right after Save, relaunch with the watch locked: one HKWorkout, and the workout still reaches the phone | not run |
| Deny the HealthKit prompt: the workout records without heart rate and still reaches the phone | not run |
| A second workout from the same plan imports on the phone (no `exercise_uuid_collision`) | not run |
| Discard: nothing appears on the phone | not run |
| Sign in as another account with an unsent workout: it waits ("from another account waiting"), is not sent as the new account's and is not deleted | not run |
| Dynamic Type on 41 mm: weight, reps and the rest timer are not truncated | not run |

## Phase 4 stage 4c: Apple Watch workout heart rate on the phone (device checks, none run)

The phone's history detail for an Apple Watch workout shows average and max heart rate and active energy read fresh from Apple Health through the stored receipt. Implemented in source, **not released or device-verified**. Every row is not run.

| Check | Result |
|---|---|
| Apple Watch workout detail on iPhone shows average/max heart rate and kcal from Apple Health | not run |
| Delete that workout in the Health app: the section disappears | not run |
| Disconnect Health in BeyondRep: the section disappears | not run |

## Phase 4 stage 5a: live watch workout on the phone (device checks, none run)

A workout started on the Apple Watch is followed and controlled from the iPhone over HealthKit workout mirroring (iOS 17 and watchOS 10), with `WCSession.sendMessage` as the fallback. Implemented in source, **not released or device-verified**; the Swift builds and passes its tests on CI only. Every row is not run.

Open decisions to verify first:

- **`workout-processing` background mode (Info.plist):** not added. Apple's documentation for `HKHealthStore.workoutSessionMirroringStartHandler` says the system launches the iPhone app in the background to call the handler and names no background mode. If the phone is not woken when the watch starts mirroring (phone locked, app not running), add `UIBackgroundModes` `workout-processing` to `apps/mobile/ios/Runner/Info.plist` and re-test.
- **No new phone HealthKit permission:** the phone only receives a session the watch starts. Confirm no new prompt appears on the phone and the existing Health permissions are unchanged.
- **Does the background launch run Dart at all?** The iOS app uses the implicit-engine UIScene setup. When HealthKit launches the phone app in the background to call `workoutSessionMirroringStartHandler`, check that the Flutter engine starts and the Dart live controller receives the first state, and that the bridge buffers messages until Dart says `ready` (`WorkoutMirrorBridge`). If no Dart runs, the mirror still works only after the person opens the app.
- **Does receiving a mirrored session need phone HealthKit authorization?** Test on a phone where BeyondRep has never asked for Health access (and again with access denied): the handler must still fire and deliver the watch's states.

| Check | Result |
|---|---|
| Start a workout on the watch, open the phone: the same set is current on both | not run |
| Log a set on the phone: "Saving..." clears and the watch shows it | not run |
| Phone locked for 10 minutes mid-workout, then unlocked: still live and current | not run |
| Walk out of Bluetooth range: "Apple Watch out of reach" and controls off; back in range, it resumes | not run |
| Health denied on the watch: the mirror works only with the app open (fallback path) | not run |
| Finish from the phone: one workout in BeyondRep history and one HKWorkout in Apple Health | not run |
| Discard from the phone: nothing in history, none in Apple Health | not run |
| Phone force-quit during the workout, relaunch: the mirror comes back or shows out of reach, never a second workout | not run |
| Starting a workout on the phone while the watch workout is live opens the mirror instead | not run |
| Background launch: phone locked and BeyondRep not running, start a workout on the watch: Dart runs and the card shows the workout on unlock | not run |
| Phone never granted Health access: the mirrored session is still received | not run |
| Mirroring reconnects after the phone goes out of range and comes back (the watch retries on its 30 s heartbeat; the phone card returns to live without reopening the app) | not run |
| A mirrored send that fails falls back to the WatchConnectivity message (turn the mirror off mid-workout, the state still reaches the open phone app) | not run |
| Force-quit the watch app right after a discard (before HealthKit ends), relaunch: no HealthKit workout keeps running on the watch | not run |
| The "already mirroring" error text on a second `startMirroringToCompanionDevice` matches the watch's check (`WorkoutRecorder.isAlreadyMirroring`) | not run |

## Phase 4: Apple Watch reads its own sleep, steps, HRV and resting heart rate (device checks, none run)

The watch Home tiles show values read from the watch's own HealthKit store, in memory only, before a phone sync (ADR-0012 decision 4 amendment 2026-11-27). Implemented in source, **not released or device-verified**. Every row is not run.

| Check | Result |
|---|---|
| First Home with a paired account shows the HealthKit permission prompt once (sleep, steps, HRV, resting heart rate, heart rate, active energy, workouts) | not run |
| Phone off or out of range: sleep, resting HR, HRV and steps show on Home with the caption "From this watch. Open BeyondRep on your iPhone for readiness" and no readiness | not run |
| Steps grow while walking (refresh on opening Home and every 5 minutes) | not run |
| After a phone sync the phone's sleep, resting HR and HRV replace the watch's, steps show the larger value, and the caption reads "as of" | not run |
| A phone snapshot sent mid-sleep keeps the phone's shorter night on the watch until the phone sends again (by design: the phone's value wins), even if the watch's own read is longer | not run |
| Deny the permission: the tiles show "—", not 0, and the prompt does not return | not run |
| Sign out on the phone: the watch values disappear; sign in as another account shows nothing from the first | not run |

## Phase 4 stage 5b: the watch joins a workout the phone owns (device checks, none run)

The phone owns the workout; the watch follows it and saves the one `HKWorkout`. Implemented in source, **not released or device-verified**; the Swift builds and passes its tests on CI only. Every row is not run.

| Check | Result |
|---|---|
| Start a workout on the phone: the watch opens at the same set | not run |
| Log a set on the watch: "Saving..." clears and the phone shows it | not run |
| Finish on the phone: one workout in history, heart rate and energy in "From Apple Health", one workout in Apple Health | not run |
| Discard on the phone: no workout in history and none in Apple Health | not run |
| Watch out of range, then back: "iPhone out of reach", controls off, then live again | not run |
| The watch joins late (launch arrives, first state after some seconds): "Connecting to your iPhone..." then the set | not run |
| The watch never joins (watch app not reachable): the phone workout is unaffected and no second workout appears | not run |
| A watch session already running: the phone workout starts without the watch joining | not run |
| `startWatchApp` needs no new permission prompt on the phone | not run |
| Watch force-quit mid-workout, relaunch: it follows again; finishing on the phone still saves one HKWorkout and links it | not run |
| Phone unreachable at finish: the link is resent until the phone acks it, never a second HKWorkout | not run |
| Missed end: take the phone out of range, finish (or discard) on the phone, bring it back: within about 30 s the watch asks again (`join`), the phone answers `ended`, and the watch saves its one HKWorkout and links it (finish) or drops it (discard); the HealthKit session does not keep running for 6 h | not run |
| Pause on the phone: the watch's HealthKit session pauses too (its elapsed clock and heart rate stop counting) and resumes with the phone | not run |
| Pause time is kept in memory on the phone: after a phone relaunch during a pause, the watch clock counts the earlier pause as workout time (display only; the saved workout is unchanged) | not run |
| Old watch app with the new phone: `startWatchApp` brings the old watch app to Home on every phone workout (it cannot join); nothing else changes | not run |
| A relaunch while HealthKit cannot answer (device locked): the follower row is kept and retried at the next launch, not dropped | not run |

## Wear OS stage 2: link, glance and Play install (device checks, none run)

The Android phone sends account binding, plans and today's health to the BeyondRep watch app over the Wear Data Layer; the watch shows Home and Train. Implemented in source, **not released or device-verified**: the Android parts (`WearLinkBridge.kt`, `apps/wear_os/app`) build and test on GitHub CI only, the Python and Dart tests ran locally, and the Codemagic job has never run. Needs an Android phone and a Wear OS watch (a Samsung Galaxy Watch or Pixel Watch). Every row is not run.

| Check | Result |
|---|---|
| Run `mobile-android-release` with `play_track` `internal`: both drafts appear (phone on internal, watch on the Wear OS internal track); Play accepts `wear:internal`; roll both out and add the watch's account as a tester | not run |
| Install the phone app and the watch app from the internal tracks; both show the same version name and the watch versionCode is the phone's + 1 | not run |
| Before sign-in the watch says "Open BeyondRep on your phone to sign in." | not run |
| Sign in on the phone: within a minute the watch Home shows the sync line, energy ring and four tiles with "vs usual" lines, and Train lists today's program workout first, then plans | not run |
| Tap a plan on Train: a read-only preview with exercises and sets x reps, no Start button; tap tiles and the ring: the detail screens open and swipe back works | not run |
| Rotary (bezel or crown) scrolls the lists; two dots at the right edge show Home or Train | not run |
| Crown or rotary scrolling works on a real watch on the Home and Train pages, including a flick past the last tile and moving between the two pages: the app uses neither `ScreenScaffold` nor `TimeText` and pages with the foundation `VerticalPager`, so rotary input is not wired by a scaffold | not run |
| Round 192 dp and 240 dp watches at font scale 1.3 (and the largest system font size): no clipped text, the last tile is reachable | not run |
| TalkBack on the watch reads the ring, each tile ("Resting heart rate 54 beats per minute, 2 below your usual") and the plan rows | not run |
| Missing health shows "—", never 0; after midnight Home shows the refresh caption and dashes until the phone sends again | not run |
| Sign out on the phone: the watch returns to the sign-in text and shows nothing from the first account; sign in as another account shows nothing from the first | not run |
| Delete the account on the phone: the watch is wiped and the wipe is resent until acked | not run |
| Phone app force-stopped, then a watch ack or message produced: it reaches the phone on the next start, exactly once | not run |
| Watch in airplane mode, then back: the sync line says "Phone not nearby" and then "Synced" again; data stays dated | not run |
| A phone without the watch app, with a paired Wear OS watch: Today shows the install banner and its steps (Play Store on the watch), "Not now" hides it | not run |
| A phone with no Wear OS companion app (or no Play services): no banner, no footer line and no watch section in Account & sync | not run |
| After a sync the phone shows "Watch · synced ..." at the bottom of Today and a "WATCH" section in Account & sync | not run |
| Watch app or phone app updated alone: the link still works (same Data Layer version) | not run |

## Phase 5: save phone workouts to Apple Health / Health Connect (ADR-0014, device checks, none run)

Opt-in per-account write of completed phone workouts. Implemented in source, **not released or device-verified**. Every row is not run.

| Check | Result |
|---|---|
| iPhone first use: Health tab, switch, sheet "Turn on" shows the HealthKit workout prompt once; "Not now" shows no prompt | not run |
| Android first use: the Health Connect permission sheet lists exercise write and read; "Not now" shows none | not run |
| Backfill of a real history (more than 50 workouts): all appear in Apple Health / Health Connect after a few passes, one entry each, none twice | not run |
| Finish a workout on the phone: one Strength training entry with the workout name's start and end, no heart rate or calories, appears within a pass | not run |
| Delete a workout in BeyondRep: the entry is gone from Apple Health / Health Connect | not run |
| Edit-free rewrite: restore the account on a second phone (same Apple ID or a Health Connect device): no second entry appears for existing workouts | not run |
| The Apple Watch joined a phone workout (stage 5b): exactly one entry in Apple Health, ours is removed or never written | not run |
| iPhone with a paired watch: a workout finished on the phone is not written for 10 minutes | not run |
| Our own saved workouts do not show up under "From other apps" or add to training load | not run |
| Health Connect not installed or needs update: the row is hidden or says so, nothing crashes, no write | not run |
| Revoke write access in Settings, resume the app: the row says "Allow access in Settings", tapping opens a sheet whose "Open Settings" opens settings; after allowing it and resuming, waiting workouts are saved | not run |
| Switch off: no new writes, no deletes, entries already saved stay; switching on again does not rewrite them | not run |
| Airplane mode and low-power: a workout finished offline is saved locally and exported without needing the network | not run |
| Account A on, sign out, account B: B shows Off and writes nothing | not run |
| Store disclosures: App Privacy answers, App Store review notes, Play Health apps declaration and the privacy policy mention the write permission before release | not run |

## Log weight device QA (ADR-0016, owner actions, none done)

Log a new weight to Apple Health / Health Connect. Implemented in source, **not released or device-verified**. Every row is not run.

| Check | Result |
|---|---|
| iPhone first Save: the HealthKit weight prompt appears once; nothing is asked at connect | not run |
| Android first Save: the Health Connect permission sheet lists weight write; nothing is asked at connect | not run |
| Deny the prompt: the sheet stays open with "Open Settings"; after allowing it in Settings, Save works | not run |
| Save a weight: it shows in the Health app / Health Connect and as the latest weight on the Health tab | not run |
| Undo in the snackbar removes that entry from the Health app / Health Connect | not run |
| Sheet cannot be closed while saving; the snackbar still appears after it closes | not run |
| VoiceOver and TalkBack read the sheet, the field error and the snackbar Undo | not run |
| Store disclosures: Play Health apps declaration lists `WRITE_WEIGHT`; App Privacy answers unchanged | not run |
