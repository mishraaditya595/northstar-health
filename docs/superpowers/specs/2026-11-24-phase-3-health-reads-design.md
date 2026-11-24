# Phase 3 design: daily health summary from Apple Health and Health Connect

**Date:** 2026-11-24 · **Status:** approved by owner 2026-11-24 · **Roadmap:** Phase 3 (permission-based platform health reads)

## Intent

BeyondRep's Health tab and the Today tab's "Recent health" row show hardcoded fictional values. Phase 3 replaces them with the person's real readings from Apple Health (iOS) and Health Connect (Android), read with their permission.

The owner's stated purpose: a **quick daily summary**. A lifter opens the app and sees how they slept and how today is going at a glance. It is not a training-advice or analytics feature.

## Goals

- Show four real values: **sleep last night, steps today, latest resting heart rate, latest weight**.
- Ask for health permission only when the person taps a Connect card, never during sign-up or first launch. Each BeyondRep account on a phone connects separately.
- Every value says where it came from and when ("Apple Watch · 7:10 AM").
- Missing values show `—` with a reason, never `0`.
- The workout logger keeps working fully for people who never connect.

## Non-goals (this phase)

- Charts, history, weekly averages or trends.
- The Today "One useful context" insight ("last sleep was 52 min shorter than average"). It needs multi-day history. Remove it.
- The "Imported activities" list (external workouts). Remove it.
- Writing anything to Apple Health or Health Connect (Phase 4).
- Background reads, notifications, widgets.
- Watch apps (Phase 5).
- Any other metric (HRV, SpO₂, energy, distance, heart-rate samples).

## Anti-goals (would be a failure even if it works)

- Any health value reaching Supabase, the sync outbox, the workout export file, logs or diagnostics.
- Showing `0` for something that is missing or not allowed.
- A permission prompt the person didn't trigger.
- The logger, sign-in or sync breaking or slowing down because health is unavailable, denied or throws.
- Claiming "not allowed" on iOS when HealthKit can't tell us that (see Platform facts).

## Constraints

- Repo rules: `AGENTS.md`, `docs/HEALTH_DATA.md`, ADR-0003. Health data is read-only, on-device only, never in Supabase. UI uses the shared kit in `lib/core/design/` (no raw Material dialogs/sheets/snackbars). Widgets don't call SDKs; a repository does.
- Repo is public: no secrets, project refs or real personal data in code, fixtures or screenshots.
- iOS deployment target is already 15.0; the `health` package needs iOS 15.
- **Store prerequisite:** the privacy policy page (issue #52) must be live before a store build with health permissions. Health Connect's permission screen links to it, and App Review expects one for HealthKit. Development and TestFlight internal builds can proceed before #52.
- A provider/dependency choice is involved, so the work includes a new numbered ADR (ADR-0008).

## Approaches considered

| | Approach | Trade-off | Outcome |
|---|---|---|---|
| A | Community **`health`** Flutter package (carp-dk), wrapping HealthKit and Health Connect | One new dependency; fastest (a few hundred lines of Dart); we inherit its release cadence and bugs | **Chosen by owner** |
| B | Hand-written Swift (HealthKit) + Kotlin (Google `connect-client`) bridges over a method channel | Full control, no third-party Flutter package; ~3–4× the work, two native codebases to test, still adds Google's library | Rejected: a four-number daily glance doesn't justify it |

Either way the screens depend only on a small `HealthReader` interface, so B remains possible later without UI changes.

## Platform facts that shape the design (from `health` 14.0.0 README)

- **iOS hides read denial.** A denied read returns only the app's own samples, so steps read as `0` and other types as empty. The app cannot tell "denied" from "no data". `getRequestStatusForAuthorization()` only says whether the permission sheet would still be shown.
- **Android reports denial.** `hasPermissions` is reliable per type; `getTotalStepsInInterval` throws `HealthErrorCode.permissionDenied` without read permission. A `true` from `requestAuthorization` means at least one type was granted, not all.
- Android needs `MainActivity` to extend **`FlutterFragmentActivity`**, minSdk ≥ 26, Health Connect installed (built into Android 14+; a separate app on Android 9–13), and a privacy-policy activity alias (`ViewPermissionUsageActivity`) in the manifest.
- Health Connect limits reads to 30 days before the grant without `READ_HEALTH_DATA_HISTORY`. We don't request that permission; 30 days is enough.
- Steps: `getTotalStepsInInterval` uses HealthKit statistics / Health Connect aggregates, which de-duplicate phone + watch overlap (Health Connect by the user's app priority list).
- Sleep: `getHealthIntervalDataFromTypes` returns minutes per interval with overlapping points counted once per type.

## Design

### What the person sees

**Not connected** (default). Health tab and the Today "Recent health" row each show one Connect card built from `InsightCard` (or `NsListCard`) with a Connect action:

```
Health
[♥] Connect Apple Health            (Android: "Connect Health Connect")
    See today's sleep, steps, resting heart rate
    and weight. Read-only; stays on this phone.
                                         [Connect]
```

Tapping Connect requests read access to the four types (one system sheet). On Android 9–13 without Health Connect installed, the card instead says Health Connect is needed and its action opens the install page (`installHealthConnect()`).

**Connected.** Health tab: four cards in the current 1/2-column grid. Today: the existing three-card row (sleep, steps, resting HR). Each card: label, value, caption with source and time.

| Card | Value | Caption |
|---|---|---|
| Sleep | `6h 18m` asleep, last night | `Apple Watch · ended 6:52 AM` |
| Steps | `6,420` today since local midnight | `Apple Health · as of 6:20 PM` (time of our read; the de-duplicated total has no per-source detail) |
| Resting heart rate | `58 bpm`, newest sample in last 7 days | `Apple Watch · today 7:10 AM` or `· 21 Nov` |
| Weight | `74.2 kg`, newest sample in last 30 days | `Withings · 22 Nov` |

**Per-card empty states** (value shows `—`):

| State | Caption | When |
|---|---|---|
| No data | `No sleep recorded last night` / `No steps yet today` / `None in the last 7 days` / `None in the last 30 days` | Read succeeded, nothing in window. On iOS also covers silent denial. |
| Not allowed (Android only) | `Not allowed · Manage` (opens Health Connect settings) | `hasPermissions` false for that type |
| Couldn't read | `Couldn't read · Try again` | Plugin threw anything else |
| Unsupported | `Not available on this device` | Type not supported |

On iOS the "No data" caption is followed, once on the Health tab only, by a muted line: "Missing something? Check BeyondRep's access in the Health app." Steps reading `0` on iOS displays `—` / `No steps yet today`, because 0 is indistinguishable from denial there.

The page header eyebrow drops "FICTIONAL DEMO DATA"; the "Not connected" tag and demo `InsightCard` go away.

### Refresh and storage

- Read when the Health tab or Today tab is shown, on app resume (`AppLifecycleState.resumed`) while one of them is visible, and on pull-to-refresh on the Health tab.
- **No health values are written to disk.** Readings live in Riverpod state for the life of the process. No cache, no TTL, so no stale-cache purge logic. (HEALTH_DATA.md allows an expiring cache; this phase deliberately uses none.)
- **"Connected" is stored per BeyondRep account (owner decision).** The OS grants health access to the app, not to an account, so without this a second account signing in on the same phone would see the first person's data without ever tapping Connect. Each account must tap Connect itself.
  - Stored as a single-row ObjectBox entity `HealthConnectionEntity { id, connectedAt }` in the **account-partitioned store** (`core/storage/account_store.dart`). Row present = this account opted in. It holds no health values.
  - Account deletion already erases the whole partition directory, so the flag goes with it. Sign-out keeps partitions today, so the flag stays with its account and returns when that account signs back in, which is the intended behaviour.
  - New entity means an ObjectBox model change: stable UIDs, regenerate and commit `objectbox.g.dart` + `objectbox-model.json`, and a test that opens a pre-change database (AGENTS.md durable-write rules).
- **Connected state shown** = account flag present **and** the OS still allows at least one type. Flag present but OS access revoked → Android cards show "Not allowed · Manage"; iOS shows "No data" (it can't tell).
- **Tapping Connect** writes the flag after `requestAuthorization` returns (whatever it returns; per-card states show what was actually granted). If another account on this phone already granted access, the OS shows no sheet (iOS) or a sheet with toggles already on (Android); the account still had to tap Connect, which is the consent we record.
- **Disconnect:** a small "Disconnect" action at the bottom of the connected Health tab deletes the flag and returns to the Connect card. It cannot revoke OS access (apps can't on iOS), so it adds one line: "To stop BeyondRep reading health data on this phone, turn it off in Health settings."
- The four reads run in parallel and fail independently; one failing card never blanks the others.

### Code shape

```
lib/features/health/
  data/health_connection_entity.dart // ObjectBox per-account opt-in flag
  data/health_connection_repository.dart
  data/health_reader.dart          // interface + value types (no plugin import)
  data/platform_health_reader.dart // only file that imports package:health
  application/health_summary_provider.dart // Riverpod: connection state + 4 readings
  health_page.dart                 // renders state; no SDK calls
  widgets/health_metric_card.dart  // shared by Health and Today
lib/features/today/today_page.dart // "Recent health" row uses the same provider/card
```

Value type (sketch):

```dart
sealed class HealthReading { }          // per metric
class HealthValue extends HealthReading { num value; String unit;
  DateTime measuredAt; List<String> sources; }
class HealthNoData, HealthNotAllowed, HealthReadFailed, HealthUnsupported
  extends HealthReading { }
```

Source names come from the plugin's `sourceName` (bundle IDs / package names joined by `", "`). Map known ones to friendly names (`com.apple.health` → "Apple Watch"/"iPhone" by device, `com.google.android.apps.fitness` → "Fit") where obvious; otherwise show "Apple Health" / "Health Connect". Never show raw IDs.

### Platform setup

- `pubspec.yaml`: `health: 14.0.0` (exact pin, matching how the repo pins other SDKs).
- iOS: HealthKit capability + entitlement (read only, no clinical records), `NSHealthShareUsageDescription` in `Info.plist` ("BeyondRep reads your sleep, steps, resting heart rate and weight to show a daily summary. This data stays on your phone."). No `NSHealthUpdateUsageDescription` (no writes). Check the Codemagic TestFlight job's provisioning profile includes HealthKit; the App ID capability must be enabled in the Apple developer portal (owner action).
- Android: `minSdk = 26`; `MainActivity` extends `FlutterFragmentActivity` (keep the existing export method channel and `onActivityResult`; FragmentActivity still forwards it); manifest `READ_SLEEP`, `READ_STEPS`, `READ_RESTING_HEART_RATE`, `READ_WEIGHT`, the Health Connect `<queries>` entry, and the `ViewPermissionUsageActivity` alias plus `ACTION_SHOW_PERMISSIONS_RATIONALE` intent filter routing to a privacy-policy screen/URL (URL from #52; placeholder until then).
- Platform store disclosures (App Store privacy labels, Play Data Safety, Health Connect declaration form) are release tasks, listed in the ADR, not code.

### Privacy guarantees and how they're checked

- `platform_health_reader.dart` is the only importer of `package:health`; a guard test (like `design_kit_guard_test.dart`) enforces that, and that nothing under `features/sync`, `features/account` or `core/storage` imports `features/health`.
- Errors are mapped to the sealed states; raw exception text is never logged or shown.
- A test asserts the workout export / sync DTOs contain no health fields (they have none today; the guard keeps it that way).

### Testing

- Unit: `PlatformHealthReader` mapping with a fake `Health` facade — each metric's value, no-data, permission-denied, thrown error, unsupported, iOS steps `0` → no data, sleep across midnight, DST change day, travel timezone (local-midnight boundaries).
- Account separation: account A connects, signs out, account B signs in → B sees the Connect card and no values; A signs back in → connected again; deleting A removes its flag. Old-database test for the new entity.
- Widget: Health page and Today row in not-connected, connected, mixed (some cards missing), Health Connect not installed; light/dark, tablet two-column, large text scale. Golden tests not required.
- Regression: workout export on Android still works after the `FlutterFragmentActivity` switch (manual on device; existing Dart tests still pass).
- Manual device QA (owner, recorded as run/not run): iPhone with and without Apple Watch; grant, deny, revoke in Settings then return to app; Android 14+ and Android 9–13 with/without Health Connect app; partial grant.

## Owner decisions in this design

- Purpose is a quick daily summary.
- Metrics: sleep, steps, resting HR, weight. Insight and imported activities dropped.
- Permission requested only on tapping Connect.
- Approach A, the `health` package (new dependency approved by that choice).
- Each BeyondRep account connects itself; health access does not carry over between accounts on one phone.

## Calls made by the designer (owner may override)

- No on-disk cache of health values; read on view/resume/pull-to-refresh. The only stored item is the per-account opt-in flag, kept in the account's ObjectBox partition.
- A Disconnect action that clears the flag, with a pointer to OS settings.
- Windows: steps since local midnight; resting HR newest in 7 days; weight newest in 30 days; sleep as defined below.
- Pin `health` to exactly 14.0.0 (released 2026-11-20). It's new, but its structured `HealthErrorCode` and Android paging fixes are what make the denied/no-data mapping clean; 13.3.2 lacks them. If a 14.0.x patch lands before implementation, take it.
- Steps caption names the platform and the time we read it, not individual sources: the de-duplicating aggregate returns only a number, and a second raw-sample query just for the caption isn't worth its extra failure mode.
- Android counts as connected when at least one of the four types is granted; the others show "Not allowed".
- Android 8 (API 26–27), where Health Connect can't be installed: the card shows "Not available on this device".
- Per-value fields from `HEALTH_DATA.md` that a no-cache daily glance doesn't need (platform sample ID, date imported) are dropped; ADR-0008 says so.
- Weight shown in kg (as the demo does); no unit preference this phase.
- iOS shows "No data" rather than "Not allowed", plus a one-line hint.
- ADR-0008 records the provider choice and the no-cache decision; `docs/HEALTH_DATA.md`, `docs/ROADMAP.md` and `CLAUDE.md` status lines get updated.

## Left to the builder

- Sleep window: suggested "sleep that ended between 18:00 yesterday and now", asleep stages only (asleep/light/deep/REM, not in-bed or awake); confirm the plugin's per-type overlap handling doesn't double count across stage types and adjust.
- Exact friendly-name mapping for sources.
- Whether the Connect card is an `InsightCard` with an action or an `NsListCard`; extend the kit in its own small PR only if neither fits.
- PR split. Suggested: (1) ADR-0008 + docs; (2) `HealthConnectionEntity` + repository with old-database and account-separation tests; (3) `HealthReader` interface, fake, provider and UI states with the fake only; (4) `health` package, native setup and platform reader; (5) Today row. Each independently reviewable.
