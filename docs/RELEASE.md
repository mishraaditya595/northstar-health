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
- **Versioning:** `version:` in `apps/mobile/pubspec.yaml` is the default user-visible version name; bump it in a PR. The manual TestFlight job takes optional `version_name` and `build_number` inputs and, on `AUTO`, uses the pubspec version and the latest App Store Connect build plus one ([details](IOS_TESTFLIGHT_CODEMAGIC.md#version-name-and-build-number)). The manual Android Play job does the same with the latest Google Play versionCode plus one ([details](ANDROID_PLAY_CODEMAGIC.md#version-name-and-versioncode)).

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
