# Watch glance redesign, detail screens and sync status — design

Date: 2026-11-27. Owner: Adi. Status: **approved by Adi ("go ahead", 2026-11-27).**
Mockups agreed in the thread "Build the Apple Watch app" (private artifact
"BeyondRep Watch Glance", version 2). A small stage between Phase 4 stage 3
(link and glance, merged in #86–#89) and stage 4 (watch workouts).

## 1. Intent

Adi installed the stage-3 watch app from TestFlight. He found it "very basic and
boring": nothing can be tapped, and the plans are hidden below a scroll. He asked
for three things.

1. **A better looking glance** in the same design language as the phone, in
   the style of Bevel: even containers, nothing crowded, everything readable.
2. **Tap-to-open detail screens** for sleep (with stages), resting heart rate,
   HRV, steps and readiness, each with a 7-day trend.
3. **Watch status on both devices.** The phone says whether the watch app is
   connected and synced, and the watch says whether it is synced with the phone.

## 2. Decisions made with Adi

| # | Decision | Source |
|---|----------|--------|
| D1 | Home is **Option A**: a readiness hero (ring, headline, reason), then an even 2×2 grid of Sleep, Resting HR, HRV and Steps. Each tile has a label, a big value and one coloured status line ("Score 90", "−2 vs usual", "today"). | Comment on the mockup |
| D2 | **Home and Train are two vertical pages** (`TabView` with `.verticalPage`), with the system page dots beside the crown. A round green **Train** button in the bottom corner of Home jumps to the Train page. On first launch only, a full-screen hint says "Turn the crown for your workouts" with a "Got it" button. | Adi: "Many users might not even know that they have to scroll" |
| D3 | Train shows today's program workout first (a highlighted card), then the plans. It stays read-only in this stage: there is no Start button until stage 4. | Mockup |
| D4 | Detail screens (in a `NavigationStack` pushed from Home): **Sleep** (score, time asleep, a stages bar with Deep/Core/REM/Awake, the 7-night average), **Resting HR** and **HRV** (today, usual, 7-day line), **Steps** (today so far, 7-day bars with today highlighted), **Readiness** (one line per input with the phone's wording). | "yes" to detail screens; mockup |
| D5 | **Phone rule:** a problem is a banner at the **top** of Today, and an OK status is a quiet line at the **bottom** of Today ("Apple Watch · synced Today 10:43" (or "synced Tue 10:43")). Tapping either opens Account & sync, which gets a new **Apple Watch** section above Cloud backup. | Adi: "On the top, if watch app is not connected. If everything works well, in the bottom." |
| D6 | **People without an Apple Watch see nothing.** No banner, footer or section unless iOS reports a paired Apple Watch. Android and iPad show nothing (Wear OS is a later phase). | Comment: "Will this show for users who don't even use the apple watch?" |
| D7 | The "BeyondRep isn't on your watch yet" banner has **Show me how** and **Not now**. Not now hides that banner for good on this phone, and the state stays visible on Account & sync. | Mockup |
| D8 | "Synced" is **confirmed by the watch**: the watch replies with an `ack` when it has stored the phone's data. The phone never claims a sync it has not heard back about. | Mockup note "What synced means" |
| D9 | The watch keeps today's values **plus the 7 days ending today**, all inside today's `health_snapshot`. It is replaced with each snapshot, wiped at local midnight and on sign-out, and never sent anywhere. This amends ADR-0012 decision 4. | Mockup note "What stays the same"; this doc |

## 3. Design

### 3.1 Contract: `watch_link/v1` `health_snapshot` gets optional fields

Every new field is **optional** and additive. `schema_version` stays 1. The
phone and the watch ship in the same TestFlight build (the watch is embedded),
so both decoders change together. A watch still on the old build rejects the
new snapshot, because its decoder rejects unknown keys. It then shows "—" until
it updates. This is acceptable for an internal build and is recorded in the
contract README.

New fields in `body_health_snapshot` (every list is oldest first, and no value
is ever sent as 0 for "missing"):

```jsonc
{
  "sleep": {
    // existing: score, asleep_minutes, deep_minutes, rem_minutes
    "core_minutes": 220,          // new, only when the night has stages
    "awake_minutes": 18           // new, only when the night has stages
  },
  "resting_hr_usual_bpm": 63,     // new: the readiness baseline mean, only when a 14-day baseline exists
  "hrv_usual_ms": 42,             // new: same rule
  "readiness": {
    // existing: score, band, headline, reason
    "factors": [                  // new, 0..4 items, the inputs the score used
      { "input": "sleep", "status": "Slept 7h 6m", "tone": "good" },
      { "input": "hrv", "status": "Above usual", "tone": "good" },
      { "input": "resting_hr", "status": "Below usual", "tone": "good" },
      { "input": "training_load", "status": "Normal", "tone": "neutral" }
    ]
  },
  "week": [                       // new, 1..7 items, the local dates ending today, ascending, unique
    { "local_date": "2026-10-17", "asleep_minutes": 412, "sleep_score": 74,
      "resting_hr_bpm": 64, "hrv_ms": 38, "steps": 8120 }
    // every metric key is optional per day
  ]
}
```

Rules:

- `factors[].input` is one of `sleep`, `hrv`, `resting_hr`, `training_load`, and
  each appears at most once (the codecs check this, the JSON Schema can only
  cap the count). `status` has 1–24 code points and `tone` is one of `good`,
  `neutral`, `caution`. The **phone writes the words**. The watch only shows them,
  so the two devices always say the same thing.
- `week[].local_date` uses the `local_date` pattern. Items are strictly
  ascending, and the last one is not later than the snapshot's `local_date`.
  The codecs check the order. Metric keys are the same integers as today's
  values, with `minimum: 0` and `sleep_score` 0–100.
- `README.md` adds the new fields and the old-build note. The rule that only
  `health_snapshot` may carry health values still holds, and the CI test
  already checks it.
- New valid fixture: `health_snapshot_full.json` (every new field). New invalid
  fixtures: an unknown factor input, a duplicate factor, `week` out of order,
  `week` with 8 items, a `status` over 24, a negative `hrv_usual_ms`. The
  existing `health_snapshot.json` stays valid unchanged. Python, Dart and Swift
  must agree on all of them, as the README's cross-language rule requires.

### 3.2 Phone builds the richer snapshot

`buildHealthSnapshot` in `lib/features/watch/application/watch_snapshots.dart`
adds the new fields from data `HealthOverview` already holds. Nothing new is
read from HealthKit:

- **Stages:** `core_minutes` and `awake_minutes` come from `lastNight`, only when
  `hasStages` is true.
- **Usual:** `resting_hr_usual_bpm` and `hrv_usual_ms` come from
  `ReadinessOverview.restingHrBaseline` and `hrvBaseline` (the mean, rounded),
  only when those are set.
- **Factors:** built next to `readinessReasons` in
  `lib/features/health/widgets/readiness_card.dart`, as a new pure function
  `readinessFactors(...)` that uses the same trend words ("above / below / about
  your normal"). The readiness card, `readinessReasons` and the Today hero must
  not change.
- **Week:** the 7 local days ending today, from `SleepOverview.nights`,
  `HeartOverview.restingHrDaily` and `hrvDaily`, and
  `ActivityOverview.stepsDaily` (today's steps use `stepsToday`). A day with no
  value for a metric omits that key, and a day with no values at all is left
  out.
- The snapshot stays well under `watchSnapshotMaxBytes`, which a test checks
  with a full week.

### 3.3 Watch replies: `ack` for what it stored

The `ack` message already exists in the contract (`acked_message_id`,
`result`: `stored|duplicate|rejected`, optional `reason`).

- **Watch:** after `PhoneInbox` applies a context, the watch sends one `ack`
  for each message it handled: binding, plans and health.
  - `stored` means applied.
  - `duplicate` means it had already applied that message id.
  - `rejected` with `wrong_account` means plans or health for an account that
    is not bound. It is sent only when a binding exists and the account key
    differs.
  - `rejected` with `invalid` covers decode failures. The account key of an
    undecodable message is unknown, so no ack is sent for those.

  Acks go with `WCSession.transferUserInfo(["json": ...])`, which is queued
  and survives the phone being away. The `ack.account_key` is the key of the
  message being acked. The watch never sends health values back.
- **Watch journal:** it records the time it last stored a phone context
  (`last_received_ms`, in a small `link_state` row). Clearing the account
  deletes the row. This drives the watch's "Synced Today 10:43".
- **Phone bridge:** `WatchLinkBridge` implements
  `session(_:didReceiveUserInfo:)` and forwards the JSON string to Dart as
  `watchMessage`. It adds a `watchStatus` method that returns `supported`,
  `paired`, `installed` and `reachable` (iPad and unsupported devices return
  `supported: false`).
- **Phone Dart:** `WatchLink` gains `Future<WatchDeviceStatus> status()` and
  `Stream<String> messages`. `WatchSyncController` remembers the message ids of
  the last context it sent, decodes incoming acks with the strict
  `watch_message.dart` codec, ignores acks whose `account_key` is not the
  signed-in account's, and records the time it heard a `stored` or
  `duplicate` ack for the latest health or plans message.

### 3.4 Phone status model and UI

There is a new pure state, `WatchStatus`, in `lib/features/watch/domain/`. It
is built from the bridge status, the last confirmed time, the time the last
unconfirmed context was sent, and now:

| State | When | Today | Account & sync |
|-------|------|-------|----------------|
| `hidden` | not supported, or no paired watch, or signed out | nothing | no Apple Watch section |
| `notInstalled` | paired, app not installed | top banner (unless dismissed) | "BeyondRep on watch: Not installed" |
| `waiting` | installed, never confirmed yet | nothing (it settles within minutes) | "Waiting for the watch" |
| `synced(at)` | installed, a confirmation exists, and no send has waited unconfirmed for 48 h | bottom line "Apple Watch · synced 10:43" | "Connected", "Last synced Today 10:43" |
| `stale(at)` | installed, a confirmation exists, and the oldest send since it that the watch has not confirmed is 48 h old or older (kept per account on the phone, cleared by a confirming ack, sign-out and deletion; opening the app after days away shows synced until a send goes unconfirmed that long) | top banner "Your watch hasn't synced since Tue 10:43" with "Open the BeyondRep app on your watch" | "Last synced Tue 10:43" in caution colour |

- The last confirmed time and the "Not now" choice live in
  `SharedPreferences`. The confirmed time is keyed by account key, and both are
  cleared on sign-out and account deletion. They hold no health values.
- **UI uses the component kit.** The banner is the existing `InsightCard`
  pattern that `BackupStatusNotice` uses. The footer is a small kit-styled row,
  and if the kit lacks one, a theme-first addition to `lib/core/design/` goes
  in the same PR as its own commit. The Account & sync section reuses the
  page's existing section and row widgets. `design_kit_guard_test.dart` must
  pass.
- **"Show me how"** opens a short kit bottom sheet with three steps: open the
  Watch app on this iPhone, scroll to Available Apps, tap Install next to
  BeyondRep.
- **Tablet and iPad:** `supported` is false, so it shows nothing.

### 3.5 Watch app UI (SwiftUI, `apps/watch_os/Sources`)

- **Structure:** `RootView` holds a `NavigationStack` around a
  `TabView(.verticalPage)` with `HomePage` and `TrainPage`. Tapping a tile or
  the hero pushes a detail screen. The Train button is in the bottom-trailing
  toolbar slot of Home (`.toolbar { ToolbarItem(placement: .bottomBar) }`,
  watchOS 10) and sets the tab selection.
- **Top line on Home:** the sync status ("● Synced Today 10:43", "● Phone not nearby",
  or nothing when not paired) plus the system clock. Tapping it opens the
  **Sync** screen, which shows the three states in the mockup: all good, phone
  away (data stays and is dated), and not set up ("Open BeyondRep on your
  iPhone").
  - "Phone not nearby" uses `WCSession.isReachable == false`.
  - The time is the journal's `last_received_ms`.
- **First-launch hint:** `@AppStorage("didShowTrainHint")`. It shows once, and
  only when a binding exists.
- **Look:** the Performance V2 dark tokens already in `HomeView.swift` move to
  a shared `Palette.swift`, adding the sleep (#C1A9FF), heart (#FF8587) and
  steps (#7FD8FF) colours from the mockup.
  - All tiles have one shape and a fixed height.
  - Values use rounded system fonts with `monospacedDigit()`.
  - Text scales with Dynamic Type. At the largest sizes the grid becomes one
    column.
  - Charts use Swift Charts (watchOS 10): `BarMark` for steps and sleep,
    `LineMark` with a dashed `RuleMark` for usual.
  - Every tile and chart has an accessibility label that reads the value and
    the trend in words.
- **State in the core package:** `GlanceState` grows into a `Glance` model with
  `tiles` (each with `status` text and tone), `readinessFactors`, and a
  `DetailModel` per metric (`today`, `usual`, `week: [DayPoint]`, and the sleep
  stages). It is still built from the journal and still shows "—" for missing,
  never 0. `SyncLine` (`synced(at)`, `phoneAway(at)`, `notPaired`) is also
  computed there. Reachability is passed in, so tests need no `WCSession`.
  - Tile status lines:
    - Sleep: "Score 90".
    - Resting HR and HRV: "−2 vs usual" / "+6 vs usual" against the usual,
      green when better (lower for RHR, higher for HRV), neutral otherwise.
    - Steps: "today".
    - When a value or usual is missing, the line is "no usual yet" or empty.

### 3.6 ADR-0012 amendment

Decision 4 gets an amendment dated 2026-11-27, approved by Adi: the watch keeps
today's `health_snapshot` including the 7 days ending today and the phone's
usual values and readiness wording. It is still computed only on the phone,
replaced on every snapshot, cleared at local midnight and on sign-out, and
never synced, backed up, logged or sent to telemetry. The ack the watch sends
carries only message ids and a result, never health values.

`docs/HEALTH_DATA.md` and `docs/SYNC_PROTOCOL.md` get one line each that
points to the amendment.

## 4. Data ownership and privacy check

- **No new storage of health values on the phone.** The phone stores only a
  timestamp and a dismissed flag in `SharedPreferences`.
- **On the watch,** values are still for one day plus a 7-day context, held
  under the existing journal health row. That row is purged by
  `purgeHealth(exceptLocalDate:)` and by `clearAccount`.
- **Nothing reaches Supabase, Firebase or logs.** Acks are not backed up.
- **Account separation:** acks with another account key are ignored, and the
  watch never acks plans or health for an unbound account as `stored`.

## 5. Testing

- **Contracts:** new fixtures pass or fail identically in
  `tool/test_watch_link_contract.py`, Dart `watch_message_test.dart` and Swift
  `ContractFixtureTests`.
- **Dart unit tests:**
  - `buildHealthSnapshot` with a full week, with missing days, without stages
    and without a baseline (key absent, never 0), and the size budget.
  - `readinessFactors` wording matches `readinessReasons`.
  - `WatchStatus` for every row of the table above, including the 48 h edge.
  - Ack handling: wrong account ignored, old message id ignored, duplicate
    counts as confirmed.
  - The controller does not send or listen when `supported` is false.
- **Dart widget tests:**
  - The Today banner on top for `notInstalled` and `stale`, the footer at the
    bottom for `synced`, nothing for `hidden`, and Not now persists.
  - The Account & sync section.
  - Light and dark mode and text scale 2.0.
- **Swift `swift test`:**
  - The `GlanceState`/`DetailModel` mapping: tile lines, missing values,
    another day's data, and the week order.
  - The `SyncLine` states.
  - The `PhoneInbox` ack results (stored, duplicate, wrong account).
  - The `link_state` write and clear.
- **Build checks:** CI `watchos_smoke.yml` builds the watch target in the
  simulator, and the existing unsigned release build still passes.
- **Device (Adi, not CI):**
  - Install from TestFlight.
  - Check the pages, the Train button, the hint, every detail screen, and the
    sync line.
  - Turn Bluetooth off on the phone and check "Phone not nearby".
  - Delete the watch app and check the phone banner and Not now.
  - Added to `docs/RELEASE.md` as an open device check.

## 6. Out of scope

- Starting or recording workouts on the watch (stage 4).
- Complications and widgets.
- Wear OS.
- Insights on the watch beyond readiness factors.
- Sending weight or VO2 max.
- Any change to the phone's Health tab or readiness maths.

## 7. Risks

- **Old watch build:** an old watch build rejects new snapshots until it
  updates (see 3.1). Mitigation: the TestFlight build carries both apps.
- **Ack delivery:** `transferUserInfo` can be delayed for minutes when the
  phone app is suspended. The 48 h stale threshold and the `waiting` state
  absorb this, so there is no false alarm on Today.
- **Small watches:** on a 41 mm screen at large text, the 2×2 grid falls back
  to one column. Check it in the 41 mm simulator.
