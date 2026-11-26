# Phase 4: Apple Watch companion and tablet layouts — design

Date: 2026-11-26. Owner: Adi. Status: **draft, awaiting owner approval.**
Brainstorm thread: "Plan Phase 4 watch and tablet apps".

## 1. Intent

BeyondRep should be usable on the wrist during a workout and comfortable to read
on a tablet.

- **Watch, workout mode:** the watch is the training companion. It shows live
  heart rate, the current exercise and set ("Bench press, set 1, 50 kg × 10"),
  lets you log or adjust reps, weight and RPE for each set, runs the rest timer
  with a tap on the wrist when rest ends, and a swipe shows total workout time.
- **Watch, the rest of the day:** opening the app shows a glance of today's
  health: readiness, sleep, resting heart rate, steps, and other numbers the
  phone's Today and Health screens show.
- **Standalone:** the watch can start and finish a whole workout with the phone
  left in a locker. It keeps its own copy of plans and saves every set on the
  watch first; the workout reaches the phone (and then the cloud) later.
- **Live handoff:** when phone and watch are both in range, they show the same
  live workout. Start on the watch, pull out the phone at set 3, and the phone
  opens at exactly that point, and the other way round.
- **Tablet:** "look at all the data in a better laid out format." Same app and
  features, using the width instead of a narrow phone column.

Adi has a real Apple Watch and uses an iPad simulator. He has no Wear OS watch
and no Android tablet.

## 2. Goals, non-goals, anti-goals

**Goals**

1. Native SwiftUI Apple Watch app, embedded in the iPhone build and installable
   through internal TestFlight.
2. Watch logging that works fully offline and never loses a set it showed as
   saved.
3. Live mid-workout handoff between iPhone and Apple Watch.
4. Watch health glance whose numbers are identical to the phone's.
5. Wide-screen (tablet) layouts for Today, Health, Health details, Progress and
   history, and the training library.

**Non-goals (this phase)**

- Wear OS. It becomes its own later phase, reusing the message format and the
  shared test files from this phase. Built when Adi has a Wear OS watch or
  decides emulator-only verification is enough.
- Android tablet device verification (layouts are Flutter and shared, so they
  apply, but are only checked in tests and the iPad simulator).
- Plan editing, library browsing, history and charts on the watch. These stay on
  the phone.
- Computing readiness or sleep score on the watch (see 4.4).
- Writing phone-only workouts to Apple Health / Health Connect. That is the old
  "Phase 4 write-back" and moves to a later phase.
- Watch complications and Smart Stack widgets (follow-up once the app is stable).
- Background health refresh on the phone (see 4.4, limitation).
- A shared C++/Rust formula library (see 4.5 for when to revisit).

**Anti-goals (failure even if it "works")**

- Two workouts for one session, anywhere: in history, in the cloud, or in Apple
  Health.
- Phone and watch showing different readiness, sleep or step numbers for the
  same moment.
- A set the watch showed as saved disappearing after a crash, a reboot, or the
  phone being away.
- A watch workout attached to a different BeyondRep account than the one it was
  started under.
- A tablet layout that stretches a phone card across 1,000 px, or breaks at
  200 % text.

## 3. Constraints (from the repo)

- `AGENTS.md` data ownership: the watch owns its recording session and local
  journal; the phone is the only cloud coordinator; only **completed** workouts
  are backed up; health values never reach Supabase or telemetry.
- `docs/SYNC_PROTOCOL.md`: watch persists set + outbound event in one local
  transaction; phone commits imported data + inbox receipt atomically in
  ObjectBox before ACK; ACK #1 (phone stored) is separate from ACK #2 (cloud).
  Corrections are new events with `supersedes_event_id`.
- `docs/WEARABLES.md`, ADR-0002: native `HKWorkoutSession` /
  `HKLiveWorkoutBuilder` owns the live session; no ObjectBox on watchOS; Swift
  sources live only in `apps/watch_os/Sources`, embedded into the Runner archive,
  never copied into `apps/mobile/ios/Runner`.
- `docs/DESIGN_SYSTEM.md`: 320–599 bottom nav; 600–839 rail and constrained
  content; 840+ rail, up to ~1120 dp dashboard and optional secondary panel.
  Shared component kit only (`design_kit_guard_test.dart`).
- Policy/permission changes need a numbered ADR. HealthKit **write** of the
  watch workout is new (see 4.6), so this phase adds **ADR-0012**.
- Repo is public: no bundle-ID-specific signing material, profiles or hosted
  refs in Git.
- Existing state: `apps/watch_os` is a two-file, 45-line placeholder with an XcodeGen spec
  (watchOS 10.0, bundle `in.beyondrep.watch.dev`, `WKWatchOnly`) and a macOS
  GitHub Actions build (`watchos_smoke.yml`). The tablet shell already switches
  to a `NavigationRail` at 600 dp and caps content at 1120 dp
  (`apps/mobile/lib/app/beyondrep_app.dart`). iPhone deployment target is
  iOS 15.0.

## 4. Decisions made with Adi

### 4.1 Scope and order (Adi picked approach A)

Apple Watch + tablet now; Wear OS is a later phase.

Approaches considered:

| | Approach | Trade-off |
|---|---|---|
| **A (picked)** | Apple Watch + tablet now, Wear OS next | Everything is verifiable on Adi's devices. Wear OS waits. |
| B | All three now, Wear OS on emulator only | Wear OS's hard parts (screen-off session, haptics, battery) can't be trusted on an emulator; roughly doubles watch work before anything is usable. |
| C | Apple Watch first, tablet later | Tablet is cheap and independent; holding it back gains nothing. |

### 4.2 Watch features (Adi confirmed)

Workout mode: live HR, current exercise/set, log/adjust reps, weight, RPE per
set, swipe for total workout time, rest timer with haptic at the end, Digital
Crown adjusts reps and weight. Outside a workout: health glance. Editing plans,
library, history and charts stay on the phone.

### 4.3 Session rules (Adi confirmed)

- **Standalone:** the watch can start and finish a workout with no phone.
- **One owner:** the device that started the session owns it. The other device
  sends its changes through the owner, so a session can never split into two
  workouts.
- **Concurrent edits:** if the same set is edited on both, the later edit wins
  and the earlier one is kept in the session's event history, not lost.
- **One platform workout:** only one workout ever reaches Apple Health.

### 4.4 Health numbers on the watch (Adi picked "phone computes, watch shows")

The phone computes readiness, sleep score and the rest with its existing Dart
code and sends the finished values to the watch. Phone and watch therefore
always match because there is one calculation. The only value the watch measures
itself is **live heart rate during a workout**. Steps on the glance come from
the phone's snapshot too, with its "as of" time, because the watch's own step
count differs from the iPhone's merged total. *(My call, from the "no
different numbers" rule.)*

Snapshot fields *(my call)*: readiness score, band and the one-line reason;
sleep score, time asleep, deep and REM; resting HR; HRV; steps today; active
energy today; the local date and `as_of` time. Each field may be missing, and the
watch shows it as missing.

Why not compute on the watch: Apple Watch's HealthKit store keeps only about a
week of samples and may not hold sleep or weight written by iPhone-only apps,
while readiness uses a 30-day baseline window needing at least 14 days of data
(`readiness.dart`). A watch calculation would often differ.

Consequences:

- The watch holds **today's** snapshot (values + "as of" time) until it is
  replaced or the day ends. This is a deliberate, narrow exception to "store
  nothing": on-watch only, never backed up, never in telemetry, cleared on sign
  out and when the day rolls over. Recorded in ADR-0012.
- When the phone is out of reach, the watch shows the last snapshot labelled
  "as of 7:10 AM". Readiness from a previous day is never shown as today's.
- **Limitation:** the phone computes only when the BeyondRep app runs (it reads
  health fresh and has no background health refresh). The watch snapshot
  updates when the phone app is opened or brought to the foreground and after a
  workout finishes. Background refresh is a non-goal for this phase.
- Missing values are shown as missing, never zero (existing rule).

### 4.5 Shared logic (Adi agreed)

Readiness and other formulas stay in Dart only. Logic that runs on both phone
and watch (message encoding, session ownership, edit merging, set and volume
totals) is checked by **one set of language-neutral test files** under
`contracts/` that the Dart and Swift code must both pass (the pattern
`contracts/workout_sync/v1` already started). Wear OS's Kotlin will pass the
same files later.

Trigger to revisit a shared C++/Rust library: the watch needs to compute
readiness or another formula itself.

### 4.6 Apple Health write (my call, flagged to Adi)

A watch workout session (`HKWorkoutSession` + `HKLiveWorkoutBuilder`) saves an
`HKWorkout` (traditional strength training) with heart rate and active energy.
That is a HealthKit **write** and needs workout share permission on the watch.
It is limited to that one workout per session. ADR-0012 records this.

After saving, the watch writes a `platform_workout_exported` event carrying the
`HKWorkout` UUID (the receipt `SYNC_PROTOCOL.md` already defines), and the phone
stores it with the workout. *(My call: the `health` plugin exposes a workout's
UUID but not its metadata, so matching by receipt needs no native phone code.)*

The phone's outside-workouts reader (ADR-0011) currently drops only workouts
whose source is exactly `in.beyondrep.app`
(`platform_health_reader.dart`), so the watch's workout
(`in.beyondrep.app.watchkitapp`) would show as an outside workout. Stage 4 changes
the reader to drop any workout whose UUID is in a stored receipt, and also any
source starting with `in.beyondrep.app`, and amends ADR-0011 rule 3 accordingly.
Heart rate and calories from that `HKWorkout` attach to the BeyondRep session
through the receipt.

## 5. Design

### 5.1 Tablet layouts (Flutter only)

Width classes follow `DESIGN_SYSTEM.md`. Only the **840 dp+** class changes;
below that, today's layouts stay. Portrait iPad (~820 dp) and split screen keep
the constrained single column.

| Screen | 840+ layout |
|---|---|
| Today | Readiness hero and the 2×2 tiles side by side; program card and recent workouts in a second row of two columns |
| Health | Cards in a 2-column grid (3 if width allows within 1120 dp) |
| Health detail (sleep, heart, activity, body, readiness) | Chart takes the main column; numbers and explanations in a side column |
| Progress / history | List on the left, tapped workout's detail on the right |
| Exercises, Workouts, Programs | List (with filters) on the left, detail on the right |
| Train | Start card and Your program side by side; plans below in two columns |
| Live workout, sign-in, account | Unchanged single focused column |

List–detail behaviour: tapping in the list replaces the right pane instead of
pushing a route; deep links and back behaviour on phones stay as they are. When
the window narrows below 840 (split screen), the open detail becomes a pushed
route so nothing is lost.

Mockups are produced before the stage plan is final; the look is Adi's call.
New layout primitives (for example a list–detail scaffold or a responsive card
grid) go into `lib/core/design/` first, per the kit rule.

### 5.2 Apple Watch app structure

`apps/watch_os/` becomes:

- `Packages/BeyondRepWatchCore/` — a pure Swift package with **no** Apple
  framework imports beyond Foundation and SQLite: message codecs, the session
  state machine, the on-watch journal, edit merging, totals. Tested with
  `swift test` (macOS CI) against the shared `contracts/` files.
- `Sources/` — the watch app: SwiftUI screens, `HealthKit/` (workout session,
  HR, permissions), `Connectivity/` (WatchConnectivity), wiring the core.
- `project.yml` — watch app target (companion, no longer `WKWatchOnly`) plus a
  test target, used for standalone builds and CI.

**On-watch storage:** SQLite from the system library (`libsqlite3`, WAL mode),
no third-party dependency. Tables: plans snapshot, health snapshot, sessions,
sets, event journal/outbox, account binding. One transaction per user action,
writing state + outbound event together. *(My call: SQLite over SwiftData for
explicit transaction control and testability in a plain Swift package.)*

**Minimum watchOS:** 10.0, as already in `project.yml`. *(My call.)*

### 5.3 Phone ↔ watch link

**Transport (iOS):** WatchConnectivity.

- `sendMessage` for live traffic when both are reachable (handoff, commands).
- `transferUserInfo` (queued, survives app exit) for anything that must arrive
  eventually: completed workouts, events, ACKs.
- `updateApplicationContext` (latest-wins) for the plans snapshot and the
  health snapshot.

Delivery is never acknowledgment: durability is the explicit ACK messages from
`SYNC_PROTOCOL.md`.

**Phone side:** a small Swift bridge in `apps/mobile/ios/Runner` exposes
WatchConnectivity to Dart over a method/event channel. Dart owns all logic in a
new `lib/features/watch/` module (repository + Riverpod state); widgets never
touch the channel. Android gets a no-op implementation for now.

**Messages (new `contracts/watch_link/v1/`):** JSON Schema + fixtures, valid and
invalid, synthetic only.

- Phone → watch: `account_binding` (opaque account key, unit preference),
  `account_cleared`, `plans_snapshot` (plans, today's program workout if any,
  the exercises they reference with name, kind reps/duration, muscle group),
  `health_snapshot` (values + `as_of` + local date), session commands, ACKs.
- Watch → phone: the existing `workout_sync/v1` envelope events
  (`workout_started`, `set_logged`, `set_corrected`, `workout_paused/resumed`,
  `workout_completed`, `workout_abandoned`), a `completed_workout` message
  carrying the final workout in the existing cloud payload shape, session
  state for mirroring, ACKs.

`workout_sync/v1` set payloads require `reps`, `load` and `unit` and forbid
extra keys, so RPE and timed sets (`duration_seconds`, no reps) cannot fit.
Stage 2 introduces **`workout_sync/v2`** with those fields, keeping v1 fixtures
and rejecting unknown versions as today. Nothing ships v1, so there is no
migration.

**Live channel while a workout runs:** HealthKit workout mirroring
(`startMirroringToCompanionDevice` and `sendToRemoteWorkoutSession`, iOS 17 /
watchOS 10). The watch always runs the `HKWorkoutSession` (5.6), mirrors it to
the iPhone, and the mirrored session keeps the phone app running in the
background even when the phone is locked in a pocket. WatchConnectivity carries
everything outside a live session. *(My call. The app's iOS minimum stays 15.0;
the watch features need iOS 17, which watchOS 10 already requires of the paired
iPhone, so no extra users lose anything.)*

### 5.4 Accounts on the watch

The watch has no Supabase session and never talks to the cloud. The phone sends
an opaque account key with every snapshot: an HMAC-SHA-256 of the Supabase user
id under a fixed app constant (the `crypto` package is already a dependency). It
is the same on every install, reinstall or new iPhone for that account, so a
stranded workout is picked up as soon as that account signs in again; the raw id
and email never reach the watch. *(My call.)* Every watch workout records the key it started under.

- Phone accepts a completed workout only if its key matches the signed-in
  account. Otherwise the workout stays on the watch, marked "waiting for the
  account it was recorded under", and the phone shows nothing for it.
- Sign out on the phone sends `account_cleared`: the watch drops plans and the
  health snapshot, keeps unsent workouts for that key.
- Account deletion sends a wipe for that key, including unsent workouts.
- With no binding (watch never paired with a signed-in phone), the watch can't
  start a workout and says to open BeyondRep on the iPhone.

### 5.5 Standalone watch workout

1. Start from a plan or today's program workout (or an empty quick workout).
   The watch creates the session UUID, starts `HKWorkoutSession`, writes
   session + `workout_started` event in one transaction.
2. Each set log, correction, pause/resume writes state + event together.
   "Saved" shows only after the commit.
3. Rest timer: wall-clock deadline stored in the session, haptic at the end, also
   correct if the app was backgrounded (the workout session keeps it running).
4. Finish: end the HealthKit session, save the `HKWorkout` with session-UUID
   metadata, write `workout_completed` + the final workout in one transaction.
5. When the phone is reachable, send the completed workout (`transferUserInfo`),
   retrying until ACK.
6. Phone: validate, then in **one ObjectBox transaction** store the workout as a
   normal completed workout, its inbox receipt (dedup by workout UUID + event
   ids), and the cloud `SyncOutbox` entry; then ACK. A duplicate delivery
   returns the same ACK and writes nothing.
7. Watch marks it delivered on ACK and later prunes it.

Discard on the watch writes `workout_abandoned`; nothing is sent to the phone's
history or the cloud. In-progress watch sessions are never backed up.

Cloud backup (**Adi chose: yes, tagged as watch workouts**): the phone uploads
a completed watch workout through the same outbox and `sync_workout` RPC as its
own, with `origin: "beyondrep_watch"`. This needs:

- a Supabase migration that lets `validate_workout_v1` accept `beyondrep_watch`
  as well as `northstar_phone` (nothing else in the payload changes), deployed
  before any app build that uploads it, via the Codemagic database job;
- the restore parser and export accepting both origins, and the phone's local
  `origin` field keeping `beyondrep_watch` so restore and history show where it
  was recorded (the history query in
  `objectbox_workout_history_repository.dart` filters on `northstar_phone` and
  must include it);
- ADR-0012 to also change ADR-0005's "watch-origin workouts are not
  synchronized" rule and `SYNC_PROTOCOL.md` rule 5: completed watch workouts are
  backed up once, by the phone, after the phone's durable import. In-progress
  watch sessions, raw heart rate and the health snapshot are still never
  backed up.

Older app builds reject an unknown origin when restoring, so every install must
be updated before watch workouts are uploaded (the same rule as stage 4 of the
training library).

Program day: if started from today's program workout, the program day is
recorded on the phone when the workout is imported, as for phone sessions.

### 5.6 Live handoff

- When both are reachable, the **owner** broadcasts its session state (current
  exercise, set, values, rest deadline, elapsed) after every change.
- The **non-owner** shows the same live screen. Its edits are sent as commands
  to the owner; the owner applies them as events, commits, and broadcasts. The
  non-owner shows "saving…" until the broadcast confirms.
- **Watch owns:** phone shows a live mirror (not an ObjectBox session) and
  cannot start a second workout. If the phone is opened mid-workout it jumps
  straight to the mirror at the current set.
- **Phone owns:** the phone's existing ObjectBox live engine stays the
  authority. When the watch is reachable, the phone launches the watch app
  (`HKHealthStore.startWatchApp`), the watch starts its own `HKWorkoutSession`
  for heart rate, mirrors it back to the phone as the live channel, and is the
  one that saves the `HKWorkout` (so there is still only one). Watch edits are
  commands to the phone. If the watch joins late, its `HKWorkout` covers from the
  moment it joined. If it never joins, the session has no Apple Health record in
  this phase (phone write-back is a later phase). *(My calls.)*
- **Concurrent edits:** the owner orders commands by arrival; a later edit of the
  same set becomes a `set_corrected` event superseding the earlier one, which
  stays in the event history.
- **Losing the link mid-workout:** the owner carries on. A watch that is not the
  owner keeps showing the last state read-only with "phone out of reach" and
  live heart rate. Ownership never transfers in this phase. *(My call: transfer
  would reintroduce the split-session risk; revisit if it hurts in use.)*
- Ending on either device ends the owner's session.

### 5.7 Watch screens (SwiftUI, Performance V2 colours and type adapted to watch)

- **Home:** health glance (readiness with band, sleep, resting HR, steps live
  from the watch) with "as of" time; "Start" with today's program workout first,
  then plans.
- **Workout (vertical pages or TabView):** current set (exercise, set n of m,
  weight × reps, Crown to adjust the focused value, RPE picker, Log); rest
  timer; overview (total time, live HR, sets done). Swipe between them.
- **Large text, VoiceOver, both wrist sizes**, always-on dimmed state.

### 5.8 Distribution

- Watch target embedded into `apps/mobile/ios/Runner.xcodeproj` as the Runner's
  companion watch app (bundle `in.beyondrep.app.watchkitapp`), sources still
  referenced from `apps/watch_os/Sources` and the core package.
- Owner actions (outside Git): create the watch App ID with HealthKit, a watch
  App Store profile, add it to the Codemagic signing setup.
- `mobile-ios-testflight` signs both and uploads one build; testers install the
  watch app from the iPhone's Watch app.

## 6. Stages

Each stage is independently verifiable and merged on its own.

1. **Tablet layouts.** Kit primitives, then the screens in 5.1. Verified by
   widget/golden tests at 700/1024/1366 widths and 200 % text, and the iPad
   simulator.
2. **Contracts and watch core.** ADR-0012; `contracts/watch_link/v1` schema +
   fixtures with the Python contract tests; `BeyondRepWatchCore` (codecs,
   journal, state machine, merging) and the Dart codecs, both passing the same
   fixtures. No UI. Includes `workout_sync/v2`.
3. **Link, glance and TestFlight.** WatchConnectivity bridge, Dart
   `features/watch`, account binding, plans and health snapshots, watch Home
   screen, watch embedded in Runner, Codemagic job updated. First thing on
   Adi's wrist.
4. **Standalone watch workout.** HealthKit session, logging screens, rest timer
   and haptics, durable journal, completed-workout transfer and atomic phone
   import into the outbox, outside-workout matching (4.6), `beyondrep_watch`
   origin migration and client support (5.5).
5. **Live handoff.** Ownership, mirroring, commands, both start directions,
   link loss.
6. **Release verification and docs.** Device script in `RELEASE.md` (60–90 min
   real workout, screen off, phone away and back, watch reboot mid-workout,
   duplicate delivery, sign-out with unsent workout), `ROADMAP.md` renumbering
   (Phase 4 = watch + tablet, write-back later), `WEARABLES.md`, `CLAUDE.md`.

## 7. Testing

- Flutter: unit and widget tests as today, plus Dart codec tests on the shared
  fixtures and the atomic import (crash between steps, duplicate delivery,
  wrong account).
- Swift: `swift test` for the core package on macOS CI; journal crash-safety
  tests (kill between write and ACK), fixture parity with Dart.
- Contracts: Python schema tests in `tool/` like `workout_sync/v1`.
- Device (Adi, Apple Watch + iPhone): the script in stage 6. Nothing is called
  device-verified until it is run.

## 8. Left to the builder

- Exact SwiftUI layout within the screens above, Crown step sizes, haptic types.
- Table schemas and migrations for the watch SQLite store.
- Exact message field names (fixtures are the authority once written).
- How the method/event channel is shaped.
- Tablet breakpoint details within 840–1120 dp, guided by the mockups.

## 9. Risks

- WatchConnectivity delivery timing is unpredictable; tests must not assume
  immediacy, and the UI must show pending state honestly.
- Codemagic watch signing has never run; expect a round of profile fixes.
- The outside-workouts merge (ADR-0011) must recognise watch-saved workouts or
  they appear twice in Activity.
- HealthKit store on the watch: permission prompts on the watch itself; test
  denied heart rate (the workout still logs, HR shows missing).
