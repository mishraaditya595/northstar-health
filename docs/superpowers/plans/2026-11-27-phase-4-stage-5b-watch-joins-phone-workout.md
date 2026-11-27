# Phase 4 stage 5b: the watch joins a workout the phone owns — implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans (Adi's choice: one Sonnet agent runs the whole plan, then an Opus review). Steps use checkbox (`- [ ]`) syntax. Strict TDD: write the failing test first.

**Goal:** when a workout is started on the iPhone and the Apple Watch is paired with BeyondRep installed:
- the phone launches the watch app;
- the watch shows the same live workout at the same set and can log, skip, rest, pause, resume and finish it, by sending commands to the phone;
- the watch runs its own `HKWorkoutSession` for heart rate, mirrors it back to the phone as the live channel, and saves the one `HKWorkout` at the end.

The phone's ObjectBox engine stays the only authority for the workout.

**Spec:** `docs/superpowers/specs/2026-11-26-phase-4-watch-and-tablet-design.md` §5.6 ("Phone owns"), ADR-0012 decisions 2 and 6. Builds on stage 5a (`session_state`, `session_command`, `WorkoutMirrorBridge`, `LiveLink`, `CommandApplier` patterns).

**Architecture:**
- **Phone, Dart:**
  - `PhoneSessionStateBuilder` turns the active workout (`activeWorkoutProvider` / `ActiveWorkoutView`) into a `session_state` body with `owner: "phone"`.
  - `PhoneLiveBroadcaster` sends it after every change and every 30 s while a watch is linked.
  - `PhoneCommandApplier` applies watch `session_command`s through `WorkoutActions`.
  - All of these live in `lib/features/watch/application/`, with their own tests.
- **Phone, iOS:**
  - `WorkoutMirrorBridge` gains `startWatchApp()`, using `HKHealthStore.startWatchApp(with:completion:)` with a traditional-strength-training configuration.
  - It also gains `sendState(json)`, sent over the mirrored session when present, else `WCSession.sendMessage` when reachable.
  - The mirroring start handler now serves both directions. Which one applies is decided in Dart by the first `session_state` `owner`, or by a watch `join` hello (see Task 1).
- **Watch:**
  - A new follower mode. `WKApplicationDelegate.handle(_ workoutConfiguration:)`, through a `WKApplicationDelegateAdaptor`, starts a follower `HKWorkoutSession` and mirrors it.
  - The follower UI renders the phone's `session_state`. It reuses the 5a phone mirror's ideas in SwiftUI and the existing set and rest page styles where they fit.
  - At the end, the watch saves the `HKWorkout` (`HKMetadataKeyExternalUUID` set to the phone's workout UUID) and queues a durable `workout_link` message until the phone acks it.

## Global constraints

- **Public repository**, synthetic data only. Read `AGENTS.md` and the nested `AGENTS.md` files for mobile and watch_os.
- **One authority, the phone.** The watch never writes the phone's sets to its own journal as a session. The phone never creates a second session for a watch command.
  - When a phone workout is unfinished and the watch has its own active or paused session (5a), the watch does not join. It shows nothing new and keeps its own session.
- **Command idempotency on the phone:** the phone keeps the applied `command_id`s in memory per session (the newest 50) and echoes them in `applied_command_ids`.
  - Durability comes from each effect being naturally idempotent:
    - `log_set` and `correct_set` write the same values to the same set id;
    - `skip_set` on a skipped set is a duplicate;
    - `pause` while paused, `resume` while active and `finish` once finished are duplicates;
    - a repeated `start_rest` with the same command id is not re-applied while that id is in memory.
  - No new ObjectBox entity. *(My call: it avoids a model migration. A phone relaunch can lose the in-memory ids, and every command is then still safe to repeat.)*
- **Account separation:**
  - The phone sends state with its own key.
  - The watch joins only when its bound key matches the state's `account_key`; otherwise it ends its follower `HKWorkoutSession` with discard.
  - The phone ignores commands with another key or another session id.
- **Exactly one `HKWorkout`, and only from the watch.**
  - When the phone finishes, the watch ends its follower session, saves one `HKWorkout` and queues `workout_link`.
  - When the phone discards, the watch discards its `HKWorkout`.
  - When the watch never joins, there is no Apple Health record (the phone never writes, as before).
  - When the watch joins late, its workout starts when it joined.
- **`workout_link` (new watch → phone `watch_link/v1` type):** body `{ workout_id (phone session uuid), healthkit_workout_uuid }`.
  - The phone stores it as a `WatchWorkoutReceiptEntity`: `workoutUuid` is the phone workout, `messageId` is the link message, `platformWorkoutUuid` is the HK uuid. It is written in one ObjectBox transaction, and the phone then acks it.
  - A link for an unknown or not-completed workout id gets no ack.
  - The watch keeps it in its outbox (journal `outbox.type = "workout_link"`) and resends until acked.
  - Health values never travel.
- **Health on the phone:** the stage 4c "From Apple Health" section shows for any workout that has a receipt with an HKWorkout id, not only `beyondrep_watch` origin. It is still read fresh and never stored. The cloud origin of a phone workout stays `beyondrep_phone`.
- **Launching the watch app:** call `startWatchApp` once when a phone workout starts, and again from a visible "Open on Apple Watch" action on the active workout page. Only do this when the watch status is paired and installed. A failure is silent; the phone workout goes on as today.
- **Link loss:** the phone carries on. The watch follower shows the last state read-only with "iPhone out of reach" and keeps its live heart rate and its `HKWorkoutSession`. When state arrives again it resumes. After 6 h without state the watch ends with discard, because the phone's own end message never arrived.
- **Watch UI:**
  - Performance V2 colours and type, as in stage 4b.
  - The header reads "On your iPhone".
  - It has Set, Rest and Overview pages; the Overview has live heart rate (watch-local, never sent).
  - Controls show "Saving…" until confirmed.
  - It supports large text, VoiceOver and both wrist sizes.
- **No new phone HealthKit permission.** `startWatchApp` needs none. If a device check shows otherwise, it becomes a RELEASE row, not a silent permission add.
- **Out of scope:** ownership transfer, phone-side heart rate during the live workout, Wear OS.

## Review focus

1. Is exactly one `HKWorkout` saved for finish, none for discard, and none when the watch never joins? Does a resent `workout_link` after a relaunch create no second receipt? *(Task 3 core tests and the Task 2 Dart test.)*
2. Is a repeated watch command harmless after a phone relaunch? *(Task 2: `replayed commands after the id memory is lost are no-ops`.)*
3. A phone workout and a watch-owned workout at the same time: which wins, and what does each screen show? *(Task 2 and Task 4.)*
4. Is the account check right on join and on every state? *(Task 3.)*
5. Do health values stay off the live link, the link message and storage? *(Grep in Task 5.)*

---

### Task 1: Contracts

**Files:**
- `contracts/watch_link/v1/message.schema.json`, its fixtures and README.
- The Dart codec `watch_message.dart` and the Swift codec `WatchMessage.swift`, with their tests.
- `tool/test_protocol_contract.py` and `tool/test_watch_link_contract.py`, if they list types.

- [ ] Failing tests first. Add the type `workout_link` with body `{workout_id: uuid, healthkit_workout_uuid: uuid}` (required, no extra keys), and the type `join` (watch → phone) with body `{session_id?: uuid}` (optional: a freshly launched watch does not know the session yet). `join` tells the phone that a follower is attached, so it broadcasts at once. Add valid and invalid fixtures. Confirm that `owner: "phone"` states pass the existing schema.
- [ ] Implement both codecs and make the tests pass.
- [ ] Commit.

### Task 2: Phone, Dart: broadcast, apply commands, store the link

**Files:**
- Create `lib/features/watch/application/phone_live_session.dart` (builder, broadcaster, command applier and providers).
- Modify `lib/features/watch/application/watch_workout_inbox.dart` (`workout_link`), `lib/features/watch/data/objectbox_watch_workout_importer.dart` (receipt write for a phone workout), `lib/features/watch/data/watch_live_link.dart` (`sendState`, `startWatchApp`), the `own_workout_health.dart` gate, and `lib/features/train/active_workout_page.dart` ("Open on Apple Watch" action, kit button).
- Tests in `test/watch/phone_live_session_test.dart` and the importer and inbox tests.

- [ ] Failing tests:
  - the state built from an active workout matches the schema, with completed, planned and skipped sets, rest deadline, pause fields and `owner: "phone"`;
  - a broadcast after a set save and every 30 s while linked, and none without a link;
  - each command applies through `WorkoutActions`;
  - a duplicate command id is applied once and echoed;
  - replayed commands after the id memory is lost (a new controller) are no-ops on the workout;
  - wrong key or session is ignored;
  - `finish` from the watch finishes the phone workout and the next state is `ended/completed`;
  - `discard` from the watch is applied only after the phone shows its own confirm dialog; on decline it is rejected with `not_allowed`.
  - Further cases:
    - `workout_link` for a completed phone workout gives a receipt and an ack;
    - a duplicate link gives a single receipt and is acked again;
    - a link for an unknown workout gives no ack;
    - the "From Apple Health" section shows for a phone workout with a receipt;
    - `startWatchApp` is called on start only when the watch is paired and installed;
    - no broadcast while a 5a watch-owned workout is live.
- [ ] Implement and make the tests pass.
- [ ] Commit.

### Task 3: Watch core: follower model and the link outbox

**Files:**
- Create `Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore/Link/FollowerSession.swift`, which holds the phone's state, its freshness, pending commands with resend every 5 s for 30 s, and the "out of reach" and 6 h end rules.
- Modify `Store/WatchJournal.swift` (queue and ack of `workout_link` in the outbox; a small `follower` table with `session_id`, `account_key`, `joined_at_ms`, `phase` so a relaunch mid-workout recovers the follower; migration v8).
- Tests: `FollowerSessionTests.swift` and additions to `WatchJournalTests.swift`.

- [ ] Failing tests:
  - a state for the bound key is accepted, and another key means do not join;
  - the "should join" rule: a phone state with no own active or paused session joins; an own session never joins;
  - a pending command is confirmed by `applied_command_ids`, and rejected with its reason;
  - stale after 90 s, with no commands sent while stale;
  - `ended/completed` gives finish-and-link, `ended/discarded` gives discard, and 6 h without state gives discard;
  - the link is queued once per workout id and survives a reopen, and the ack removes it;
  - the follower row survives a reopen;
  - the v7 to v8 migration keeps old data.
- [ ] Implement and make the tests pass.
- [ ] Commit.

### Task 4: Watch app: launch by the phone, follower UI, HealthKit

**Files:**
- Modify `Sources/App/BeyondRepWatchApp.swift` (`WKApplicationDelegateAdaptor`, `handle(_ workoutConfiguration:)`), `Sources/App/AppModel.swift`, `Sources/HealthKit/WorkoutRecorder.swift` (a follower begin that reuses `begin`, external UUID set to the phone workout id at finish), and `Sources/Connectivity/LiveLink.swift` and `PhoneLink.swift` (receive phone state, send `join` and commands, send `workout_link` with `transferUserInfo`).
- Create `Sources/Features/Follower/FollowerView.swift` (and pages if needed).
- Run `cd tool && bundle exec ruby embed_watch_target.rb` and commit the project change.

- [ ] Launch order: when launched with a workout configuration and no own session, start the follower `HKWorkoutSession`, start mirroring, send `join`, and show the follower UI with "Connecting to your iPhone…" until the first state. If the first state's key does not match, or no state arrives within 60 s, discard the HK session and return to Home.
- [ ] A relaunch with a follower row recovers the HK session (`recoverActiveWorkoutSession`) and the follower.
- [ ] Previews use synthetic data.
- [ ] Commit.

### Task 5: Docs and checks

- [ ] ADR-0012: add a stage 5b consequence line. It records:
  - the watch saving the one `HKWorkout` for a phone-owned session;
  - `workout_link`;
  - the "From Apple Health" section widened to any workout with a receipt;
  - command idempotency on the phone, by effect.
- [ ] `docs/SYNC_PROTOCOL.md`: the `workout_link` ack rule.
- [ ] `docs/WEARABLES.md`.
- [ ] `docs/RELEASE.md` device rows, all "not run":
  - start on the phone and the watch opens at the same set;
  - log on the watch and the phone updates;
  - finish on the phone gives one workout in history, with heart rate in "From Apple Health" and one workout in Apple Health;
  - discard on the phone leaves no Apple Health workout;
  - watch out of range, then back;
  - the watch joins late;
  - the watch never joins;
  - a watch session already running means no join;
  - `startWatchApp` needs no phone permission.
- [ ] `docs/ROADMAP.md` and the `CLAUDE.md` Phase 4 line: "implemented in source, not released or device-verified".
- [ ] Run `grep -rn "heart\|kcal\|energy" lib/features/watch/application/phone_live_session.dart apps/watch_os/Sources/Connectivity` and confirm no health value is sent.
- [ ] Commit.

## Checks before handing back

From `apps/mobile`:
- `dart format --output=none --set-exit-if-changed lib test`
- `flutter analyze`
- the full `flutter test`

From the repo root:
- `python3 -m unittest discover -s tool -p 'test_*.py'`

Swift runs on CI only (`watchos_smoke.yml`).
