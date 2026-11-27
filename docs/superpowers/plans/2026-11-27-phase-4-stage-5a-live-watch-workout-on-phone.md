# Phase 4 stage 5a: a live watch workout on the phone (watch owns) — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (Adi's choice: one Sonnet agent runs the whole plan, then an Opus review). Steps use checkbox (`- [ ]`) syntax. Strict TDD.

**Goal:** a workout started on the Apple Watch can be followed live and controlled from the iPhone.
- When the phone app is opened mid-workout, it shows the same workout at the same set.
- Sets can be logged or corrected, rest can be started or skipped, and the workout can be paused, resumed, finished or discarded from the phone.
- The watch stays the owner. The phone sends commands; the watch applies them as its own journal events, commits, and broadcasts the new state. The phone shows "Saving…" until a broadcast confirms the command.

**Stage 5 split (my call):**
- **5a (this plan):** the watch owns the workout, and the phone mirrors it and sends commands.
- **5b (next):** the phone owns the workout and the watch joins it (`startWatchApp`, a watch `HKWorkoutSession` for heart rate, the watch saving the one `HKWorkout`, watch commands to the phone engine).

5a is useful on its own and carries the shared pieces (contracts, live link, commands) that 5b reuses.

**Spec:** `docs/superpowers/specs/2026-11-26-phase-4-watch-and-tablet-design.md` §4 (link) and §5.6 (live handoff); ADR-0012 decision 6 (ownership, no transfer).

**Architecture:**
- **Contracts:** `session_state` and `session_command` already exist in `contracts/watch_link/v1` with Dart and Swift codecs. Extend them (Task 1).
- **Watch core (Swift, `swift test`):**
  - `SessionStateBuilder`: controller and template to a `session_state` body, checked by golden cases.
  - `CommandApplier`: validates a `session_command` and applies it through `WorkoutController`, at most once per `command_id` (journal v7 table).
- **Live transport (my call):** HealthKit workout mirroring is primary. Watch: `HKWorkoutSession.startMirroringToCompanionDevice()` and `sendToRemoteWorkoutSession(data:)`. Phone: `HKHealthStore.workoutSessionMirroringStartHandler` and `sendToRemoteWorkoutSession(data:)`. iOS 17+ only, guarded with `#available`; the app minimum stays 15.0.
  - The mirrored session keeps the phone app alive in the background.
  - When there is no `HKWorkoutSession` (Health denied) or iOS is below 17, fall back to `WCSession.sendMessage` while reachable. In that case the phone sees the workout only while the app is in the foreground.
  - The live link carries only `session_state` and `session_command` JSON, never heart rate or energy.
- **Phone, iOS:** a new `apps/mobile/ios/Runner/WorkoutMirrorBridge.swift` on a new method channel `beyondrep/watch_live`. The mirroring start handler must be set in `AppDelegate.application(_:didFinishLaunchingWithOptions:)` before anything else (Apple requires it early). The bridge also forwards `WCSession` `didReceiveMessage` live messages from `WatchLinkBridge`.
- **Phone, Dart (`lib/features/watch/`):**
  - `WatchLiveLink` (data): the channel wrapper.
  - `LiveWatchWorkoutController` (application, Riverpod): in-memory state, account check, staleness, pending commands.
  - `WatchWorkoutMirrorPage` (UI): route `/train/watch-workout`.

## Global constraints

- **Public repository**, synthetic data only. Read `AGENTS.md` and the nested `AGENTS.md` for mobile and watch_os.
- **The phone never creates an ObjectBox session for a watch-owned workout.** The mirror is memory only. The finished workout still arrives through the stage 4a `completed_workout` path, and that path is the only one that writes.
- **Account separation:** the phone ignores a live message whose `account_key` is not the signed-in account's key (`watch_account_key.dart`). It sends commands only with its own key. The watch rejects a command whose key is not its bound key or whose `session_id` is not its active session.
- **One session at a time:**
  - While a watch-owned workout is live and fresh, the phone's Start buttons (Train start card, plan, program day, quick workout) open the mirror instead of starting a phone workout.
  - When a phone workout is already in progress (an unfinished ObjectBox session) and a watch session appears, the phone shows a banner on the mirror and does not block either. Ownership stays with each device; 5b handles phone-owned workouts.
- **Freshness:**
  - The watch broadcasts after every journal change, and every 30 s while a live link is up (heartbeat).
  - The phone marks state stale 90 s after the last message, or at once when the mirrored session disconnects. Stale state is read-only, with the line "Apple Watch out of reach". It is dropped after 6 h, or at once on a `status: ended` state, sign out or account switch.
- **Commands:**
  - Each command has a new UUID `command_id`. The phone keeps it pending until a state lists it in `applied_command_ids`, and resends the same command id every 5 s while pending and the link is up, for at most 30 s. After that the row shows "Not saved on your watch" and offers retry.
  - The watch applies a given command id at most once, and an already-applied id is not an error.
  - A `log_set` or `correct_set` on a completed set becomes `set_corrected` (ADR-0012 decision 6); on a set never logged either becomes `set_logged` and starts the set's rest.
  - `applied_command_ids` holds at most 20 ids; an id the phone resent (a duplicate) is listed in the next states even when older, so a retry is confirmed.
  - `finish` runs the watch's own two-step finish (`markCompleted`, HealthKit finish, `queueCompleted`). `discard` requires a confirm dialog on the phone (kit dialog).
- **UI (phone):**
  - Design kit only (`lib/core/design/`); `test/design_kit_guard_test.dart` must pass.
  - Reuse the active workout page's set row widgets where they fit (`SetEditorTile` in `lib/features/train/active_workout_page.dart`) rather than inventing new ones. If a widget needs a change, keep the change small and covered by tests.
  - Title: the workout name, with an "Apple Watch" tag. Elapsed time is computed from `started_at_utc` and the new pause fields. A rest countdown shows when `rest_deadline_utc` is in the future.
  - Light, dark, tablet two-column (`lib/core/design/layout.dart`), and text scaling. Reduced motion: no animated countdown ring.
- **Auto-open:** when the app comes to the foreground and a fresh watch-owned state for the signed-in account exists, go to `/train/watch-workout` once per `session_id`. Today and Train also show a kit card "Workout on your Apple Watch · Open".
- **No new phone HealthKit permission.** If mirroring on device turns out to need one, the fallback still works. Record this as an open device check; do not add permissions.
- **Info.plist:** add `UIBackgroundModes` `workout-processing` to the iPhone Runner only if Apple's "Building a multidevice workout app" sample needs it for the mirroring start handler. State in the report what you found and what you relied on. Keep `tool/test_*.py` guards passing.
- **Out of scope:** phone-owned workouts and the watch joining them (5b), ownership transfer, live heart rate on the phone, Wear OS.

## Review focus

1. Is a command applied at most once, even after a resend, an app relaunch or a duplicate delivery over both transports? *(Task 2: `testDuplicateCommandIdIsAppliedOnce`, `testCommandAfterRelaunchIsStillIdempotent`.)*
2. Are commands for another account or another session rejected and never applied? *(Task 2 and Task 5.)*
3. Does the phone never write ObjectBox for a live watch workout? *(Task 5: a test that the store is unchanged after a full live session.)*
4. Stale and ended states: is the read-only UI correct, and are pending commands not resent once stale? *(Task 5.)*
5. Is the transport fallback correct when HealthKit was denied? *(Task 3 and Task 4, reviewed by hand. Device rows in RELEASE.md.)*
6. Does `finish` from the phone still produce exactly one `HKWorkout` and one imported workout? *(Task 2 test plus a device row.)*

---

### Task 1: Contract additions

**Files:**
- `contracts/watch_link/v1/message.schema.json`, fixtures under `valid/` and `invalid/`, and the README.
- `contracts/watch_link/v1/cases/session_state/` (new golden cases).
- The Dart codec `lib/features/watch/domain/watch_message.dart` and the Swift codec `Contracts/WatchMessage.swift`, plus their tests.
- `tool/test_protocol_contract.py`, if it enumerates fixtures.

`body_session_state` gets:
- `status`: add `"ended"`, with a required `end_reason` (`"completed"` or `"discarded"`) when ended.
- optional `paused_at_utc` (date-time, present only while paused);
- optional `paused_seconds` (integer ≥ 0, the total of earlier pauses);
- optional `applied_command_ids` (array of uuid, at most 20, newest last);
- optional `rejected_commands` (array of `{command_id, reason}`, reason enum `"unknown_session" | "unknown_set" | "invalid_values" | "not_allowed"`, at most 20).

`body_session_command`: `correct_set` and `log_set` keep the existing `set` object. Add `"add_set"` with `exercise_id`. `skip_set` requires `set.set_id`, so add a small `if/then` that requires `set` for `log_set`, `correct_set` and `skip_set`.

- [ ] Failing contract tests first:
  - valid fixtures for ended, paused, applied and rejected states and for `add_set`;
  - invalid fixtures for ended without `end_reason`, 21 applied ids, a bad reason, and `skip_set` without `set`.
- [ ] Update the schema and both codecs, and make the tests pass. The Dart run is `flutter test test/watch/`, the Python run is `python3 -m unittest tool.test_protocol_contract`, and Swift runs on CI.
- [ ] Commit.

### Task 2: Watch core: state builder and command applier

**Files:**
- Create `Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/Link/SessionStateBuilder.swift` and `Link/CommandApplier.swift`.
- Modify `Store/WatchJournal.swift` (v7 migration: table `applied_commands(session_id TEXT NOT NULL, command_id TEXT NOT NULL, result TEXT NOT NULL DEFAULT 'applied', reason TEXT, applied_at_ms INTEGER NOT NULL DEFAULT 0, PRIMARY KEY(session_id, command_id))`, rows deleted when their session is abandoned or when the phone acks its completed workout, so a resent `finish` stays a duplicate) and `Session/WorkoutController.swift` (only what the applier needs, for example `logOrCorrect(setValues:)` if it is missing).
- Tests: `SessionStateBuilderTests.swift` (golden cases from Task 1), `CommandApplierTests.swift`, `WatchJournalTests.swift` (migration v6 to v7 on an old database).

- [ ] Failing tests:
  - the builder output equals each golden case;
  - `log_set` on a planned set, then `correct_set` on the same set, gives `set_logged` then `set_corrected`;
  - `skip_set`;
  - `start_rest` with `rest_seconds` and `clear_rest`;
  - `pause` and `resume`, including the pause fields in state;
  - `add_set`;
  - `finish` returns `.needsFinish`, so the app runs the HealthKit finish;
  - `discard`;
  - a duplicate command id is applied once and listed in `applied_command_ids`;
  - the command is still idempotent after the journal is reopened;
  - another account key, another session id, an unknown set id, and invalid values (reps < 0, a load on a duration exercise) each give a rejected entry with no event written;
  - the v7 migration keeps v6 data.
- [ ] Implement. The applier result and the event write commit in one journal transaction.
- [ ] Commit.

### Task 3: Watch app: live link and broadcasting

**Files:**
- Create `apps/watch_os/Sources/Connectivity/LiveLink.swift`.
- Modify `Sources/HealthKit/WorkoutRecorder.swift` (start mirroring after `beginCollection`, `HKWorkoutSessionDelegate` `didReceiveDataFromRemoteWorkoutSession` and `didDisconnectFromRemoteDeviceWithError`, and a send helper), `Sources/Connectivity/PhoneLink.swift` (`session(_:didReceiveMessage:)` and send via `sendMessage`), and `Sources/App/AppModel.swift` (broadcast on every `revision` change while a workout is active, a 30 s heartbeat, applying incoming commands through `CommandApplier`, then broadcasting).
- Run `cd tool && bundle exec ruby embed_watch_target.rb` and commit the project change.

- [ ] `LiveLink.send(state:)` uses the mirrored session when `recorder.isMirroring`, else `WCSession.sendMessage` when reachable, else does nothing. A state is never queued with `transferUserInfo`, because it is latest-wins.
- [ ] After `finish` or `discard`, send one `status: ended` state, then stop mirroring.
- [ ] Commit.

### Task 4: Phone iOS bridge

**Files:**
- Create `apps/mobile/ios/Runner/WorkoutMirrorBridge.swift`, and add it to `Runner.xcodeproj` the same way `WatchLinkBridge.swift` is included.
- Modify `AppDelegate.swift` (register first), `WatchLinkBridge.swift` (forward `didReceiveMessage` JSON to the live bridge; reply handler not used), and `Info.plist` (see the global constraints).

- [ ] Method channel `beyondrep/watch_live`:
  - to Dart: `liveMessage(String json)`, `liveDisconnected()`;
  - from Dart: `sendCommand(String json) -> bool`, which sends through the mirrored session when present, else `WCSession.sendMessage` when reachable, and returns false when neither is available.
- [ ] Keep the mirrored session reference while it runs. Clear it when the remote session disconnects or ends.
- [ ] No HealthKit reads or writes on the phone.
- [ ] Commit.

### Task 5: Phone Dart: live state and commands

**Files:**
- Create `lib/features/watch/data/watch_live_link.dart`, with an interface plus a `MethodChannel` implementation and a fake for tests.
- Create `lib/features/watch/application/live_watch_workout.dart`, the controller and its providers.
- Tests in `test/watch/live_watch_workout_test.dart`.

- [ ] Failing tests:
  - a state for the signed-in key is shown, and another key is ignored;
  - a newer `sent_at_utc` replaces an older one, and an older or duplicate one is ignored;
  - stale after 90 s with a fake clock, and stale at once on disconnect;
  - `ended` drops the state;
  - sign out or account switch drops the state;
  - a command is pending until it appears in `applied_command_ids`;
  - resend every 5 s for at most 30 s, then failed, with retry making a new attempt using the same command id;
  - a rejected command shows its reason;
  - commands are not sent while stale;
  - no ObjectBox write during a whole live session (open a temporary store and assert counts are unchanged).
- [ ] Implement and make the tests pass.
- [ ] Commit.

### Task 6: Phone UI: mirror page, cards and start blocking

**Files:**
- Create `lib/features/watch/widgets/watch_workout_mirror_page.dart` and `lib/features/watch/widgets/live_watch_workout_card.dart`.
- Modify `lib/app/beyondrep_app.dart` (route and foreground auto-open), the Today and Train pages (card), and the Train start entry points (open the mirror while a fresh watch workout is live).
- Widget tests in `test/watch/watch_workout_mirror_page_test.dart`.

- [ ] Failing widget tests:
  - the current set is highlighted and completed sets show their values;
  - logging a set shows "Saving…" until confirmed;
  - the stale banner is shown and the controls are disabled;
  - discard asks for confirmation;
  - finish sends `finish` and, after `ended`, pops to Train with a kit snackbar ("Saved on your Apple Watch").
  - Further cases:
    - Train start opens the mirror while live;
    - auto-open happens once per session;
    - a tablet layout at 1,000 dp;
    - 200 % text has no overflow;
    - the design kit guard passes.
- [ ] Implement and make the tests pass.
- [ ] Commit.

### Task 7: Docs

- [ ] ADR-0012: add a stage 5a consequence line (live mirror, commands, transport, no phone-side storage).
- [ ] `docs/SYNC_PROTOCOL.md`: the command idempotency rule.
- [ ] `docs/WEARABLES.md`.
- [ ] `docs/RELEASE.md` device rows, all "not run":
  - start on the watch, open the phone, and it is at the same set;
  - log on the phone and the watch updates;
  - phone locked in a pocket for 10 minutes, then unlock, and the workout is still live;
  - walk away, the line says out of reach, come back, and it resumes;
  - Health denied on the watch, so the mirror works only with the phone app open;
  - finish from the phone gives one workout in history and one in Apple Health;
  - discard from the phone.
- [ ] `docs/ROADMAP.md` and the `CLAUDE.md` Phase 4 line: "implemented in source, not released or device-verified".
- [ ] Run `python3 -m unittest discover -s tool -p 'test_*.py'`.
- [ ] Commit.

## Checks before handing back

From `apps/mobile`:
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- the full `flutter test`

From the repo root:
- the Python tool tests

Swift runs on CI only (`watchos_smoke.yml`: `swift test`, the watch build, and the iPhone build with the watch).
