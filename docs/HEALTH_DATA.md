# HealthKit / Health Connect — health data and workout export boundary

**Authority:** [ADR-0003](adr/0003-data-cloud-health.md), with account and sync scope superseded by [ADR-0005](adr/0005-mandatory-auth-and-workout-sync.md). Mobile Flutter demo currently shows **fictional** values only.

## Phase 3 scope

Phase 3 is limited to a read-only daily summary of four metrics: sleep, steps, resting heart rate and weight. It keeps **no on-disk cache of health values** and stores only a per-account opt-in flag in the account's ObjectBox partition, which narrows the optional cache described below for this phase. Permission is requested only when the person taps Connect. See [ADR-0008](adr/0008-daily-health-summary-reads.md).

**Health insights stages 1-3 (ADR-0009, stages 1-2 merged on `main`, stage 3 implemented in source, none released or device-verified):** [ADR-0009](adr/0009-health-insights-trends.md) widens the read scope beyond these four metrics and adds a sleep score computed on device, with 7/30-day trends and four detail screens. It amends ADR-0008's metric list, cache and Android history items; still no on-disk cache, nothing stored, and nothing in the cloud. Stage 2 adds a readiness score (0-100) computed on device from four inputs: HRV against the 30-day baseline, resting heart rate against its baseline, last night's sleep score (or sleep duration against 7h30 when there is no score), and last night's sleep against the previous seven nights (sleep debt). Weights are 0.40, 0.25, 0.25 and 0.10, rescaled over the inputs present. It needs at least 14 baseline days, last night's sleep, and HRV or resting heart rate today; otherwise the card says it is not ready and how many days remain. Bands: 70 and above good, 50 to 69 fair, below 50 low. The score is read fresh each time and **never stored**; the low-readiness note before a workout is remembered in memory for the day only. It is a suggestion, not medical advice. Stage 3 (training tie-ins) joins health values with completed workouts in memory only, from the last 30 days, and never stores the result or sends it to workouts, outbox, sync, export or logs. Two insights exist: sleep after training days vs other nights (at least 5 nights each side, at least 30 minutes apart) and resting heart rate the morning after the biggest sessions (top third by working sets, at least 5 each side, at least 3 bpm apart), both compared only from the first logged workout onward; below the minimums nothing is shown, and the Health tab shows one of the two (sleep first). Muscle recovery uses workout data only (reps 5 or more or unknown weigh 1.0, under 5 weigh 0.7, times an effort weight; a group under 0.1 counts as recovered); the Train "Better fit today" suggestion uses it plus today's readiness band, in memory, and works without health access. The spec's other two insights are not implemented.

Stage 1 requests read access to these types in one permission sheet (`platform_health_reader.dart`):

| | Both platforms | iOS only | Android only |
| --- | --- | --- | --- |
| Sleep | asleep, awake, deep, REM, light (Core) | in bed, sleeping wrist temperature | sleep session |
| Heart | heart rate, resting heart rate, VO₂ max | HRV (SDNN), walking heart rate | HRV (RMSSD) |
| Breathing | respiratory rate, blood oxygen | | |
| Activity | steps, active energy | | |
| Body | weight, body fat, lean body mass | | skin temperature (only where Health Connect offers it; a deviation from the device's own baseline, shown as such, never as an absolute reading) |

On Android it also requests Health Connect's history permission where available. Without it Health Connect returns data from 30 days before the app was first granted access onward. The app does not know that grant date, so it uses the account's connect date instead: that date is never earlier than the first grant, so the approximation can only hide a comparison, never show a period that is not readable. The only things stored are the per-account opt-in row (connected time and the version of the requested type list, so Android offers "Allow more data" once per new list); no health value or score.

## Data ownership

- **BeyondRep** owns detailed workouts it records: sets, reps, weights, rest, RPE/RIR, exercise snapshots and notes. Mobile ObjectBox persists them, and Supabase synchronizes authenticated, completed BeyondRep phone workouts under ADR-0005; unfinished sessions, local rest/recovery checkpoints and physiological data remain outside cloud.
- **HealthKit / Health Connect and their source apps/devices** own physiological and aggregate activity observations. BeyondRep reads authorized sources on demand, optionally retaining **expiring local aggregates only**. **Never cloud-backup** HR, HRV, sleep, SpO₂, steps, energy, distance, raw vitals or GPS/health traces.
- **External workouts** imported from health platforms are read/display references, not automatically owned BeyondRep strength logs and never re-exported. Stage 2 of the health polish ([ADR-0011](adr/0011-read-workouts-from-health-platforms.md), implemented in source, not released or device-verified) reads them fresh (last 90 days, `READ_EXERCISE` only on Android, so no kcal or distance there), merges any that overlap a finished BeyondRep session by at least 50% of the shorter one into that session, lists them in Activity, Progress history and the Today Workouts tile, and counts them in training load (a readiness input). They are held in memory only: never stored, synced, backed up, exported or logged, and they do not change muscle recovery, the Progress workout count or volume. A workout from `in.beyondrep.app` is dropped.
- **Smartwatch workouts** generated by BeyondRep have an explicit origin/owner and a durable set journal. HealthKit workout and BeyondRep set log are separate objects.

A health value must carry type/unit, measured time (UTC + relevant local calendar grouping), source application/device, platform sample ID where available, date last imported, permission/cache status. Display `—` for unavailable instead of 0; permission denied, no record, stale cache and unsupported type are distinct.

## Health read pathway (read-only in MVP)

| Feature | Platform inputs | Local policy |
| --- | --- | --- |
| Steps, distance, active energy | HealthKit quantity statistics; Health Connect appropriate aggregates | Temporary daily aggregates with source and retrieved-at |
| HR/resting HR/HRV | Supported quantity/sample records | Query bounded range; temporary chart samples only if required |
| Sleep stages and duration | HealthKit category samples; Health Connect sleep sessions/stages | Temporary interpreted summary with source |
| SpO₂, respiratory rate, weight | Platform record when available and user opts in | Temporary on-demand data |
| External workout timeline | HealthKit workout / Health Connect exercise session (`READ_EXERCISE`) | Read fresh for the last 90 days, memory only, source-aware display, merged with overlapping BeyondRep sessions; no BeyondRep backup, no export |

Use platform aggregates where supported, respecting metric-specific dedup behavior. Do not assume all wearables or providers contribute all measurements to the platform store. Re-check per-type permissions; Android historical records may require additional permission. Honor change tokens/anchors and invalidate relevant cache after source changes, data deletion, account switch or permission revocation.

### Proposed cache limits, to profile

Current dashboard aggregates ~5–30 minute TTL while in use; historical aggregates up to ~24 hours; raw detailed chart samples short-lived and size-bounded. These are **initial suggestions**, not API guarantees. Always display stale/last-updated context; purge no-longer-authorized caches. Health-platform change tokens remain device-local, never in Supabase.

## Health export (separate permission, **never automatic by default**)

Only for **completed BeyondRep-owned sessions**, not drafts or imported workouts. A settings control and contextual first-use explanation are required. Track origin: `northstar_phone`, `beyondrep_apple_watch`, `northstar_wear_os`, `external_platform`, `manual`. Do not synthesize energy, heart rate or sleep to improve activity-ring metrics. Set-by-set details are not portable platform measurements.

### Export receipt state machine

`not_requested` -> `pending` -> `exporting` -> `confirmed`  
Any uncertain interruption -> `reconciliation_required`; recoverable error -> `failed_retryable`; permanent permission/error -> `blocked`. Store platform, BeyondRep workout UUID, platform identifier when available, attempted revision, completion status and observed app-owned record identifiers in ObjectBox. Separate permission from cloud-backup setting.

- **Apple Watch:** if the watch owns and has saved `HKWorkout`, phone **never writes the same session again**. Watch sends origin + reference/receipt along with detailed sets. If receipt is missing after an uncertain crash, reconcile app-owned HealthKit samples first; `HKMetadataKeyExternalUUID` aids matching but is **not an automatic uniqueness guarantee**. App-owned HealthKit edits/deletions need a separate explicit permission-aware reconciliation policy.
- **Wear OS:** designate exactly one platform health writer for a BeyondRep session (typically the phone Health Connect integration); the watch event journal is not a second platform writer.
- **Android Health Connect:** stable `clientRecordId` and `clientRecordVersion` for idempotent/versioned updates where supported; confirm provider behavior and permissions during native implementation.
- **External/imported source:** never create a BeyondRep clone in HealthKit/Health Connect, never feed read-data back to export service.

A successful platform write must not trigger cloud sync of platform measurements; a cloud backup must not cause re-export on a restored device.

## Safety/privacy and platform review

Never log health values, notes, tokens, source IDs, free-form exceptions containing records, raw API responses or photos in diagnostics. Health read, health write and BeyondRep backup are **three independent disclosures**; a user can use the logger without granting platform access. Only request needed permissions after contextual explanation, handle partial grants/revocation, assess store disclosures and OS version requirements at implementation time. HealthKit/Health Connect do not make the app a medical diagnostic service.

## Tests

Unknown vs zero, cross-device overlap and platform aggregates, changing source priority, stale/denied after cache expiry, permission revoked during workout, daylight-saving and travel, workout export interrupted before/after external write, repeated reconnect, post-export correction, watch-owned HKWorkout not re-exported, guest/account switch, no platform raw data included in Supabase payload.
