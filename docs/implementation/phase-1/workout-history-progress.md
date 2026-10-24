# Phase 1 — Completed workout history and progress (PR #11)

**Base:** latest `main` after merged PR #10 at
`e2c3ddcb895367f3272c00531f581e624600ed77`.
**Scope:** offline, read-only, factual **NorthStar workout history**.
Adds an ObjectBox **index** on existing `WorkoutSession.status` (a real
schema change with one new index UID). All existing entity, property and index
UIDs are retained; no new entity or health measurements.
No backup, watch tracking, Firebase or write/export permissions.

## Data owner and behavior

- Phone ObjectBox is the source of truth. A read-only repository queries
  `status == completed` and filters soft-deleted records and missing finish
  timestamps. Discarded, paused, in-progress and unknown future statuses
  never appear in a completed session list.
- Sessions are sorted by **finish time descending**, with a deterministic
  UUID tie break. Their original exercise name/equipment snapshots,
  performed reps, load units, RPE, set kind and status are displayed in a
  read-only detail screen. Edits to plans cannot rewrite past sessions.
- History and metrics show 30-day, 90-day or all-time windows. Ranges use a
  rolling UTC finish-time boundary; calendar day labels use the captured
  original timezone offset rather than the phone's present timezone.
  The clock uses an `autoDispose` provider to resample each Progress visit;
  history remains separately cached without a second ObjectBox read.
- Summary shows actual completed-workout count, performed *working*-set
  count and **loaded volume (kg/lb × reps)**. Volume sums integer
  `reps × loadGrams` only for completed working sets with a recorded load.
  Unloaded working sets are counted separately, never converted to zero
  kilograms. When no positively loaded working set exists the volume card
  shows a dash and `No loaded sets`. Explicit 0-kg entries are recorded
  separately and excluded from meaningful loaded strength/volume trends.
  Skipped/planned/warm-up/unsupported sets do not inflate volume. The unit
  chip switches both trend loads and the volume card; display rounds pounds
  to at most two decimals, while stored integer grams stay unchanged.
- Exercise trend is maximum **logged working-set load per finished workout**,
  not an estimated 1RM, rate of strength gain or caloric metric. The trend
  is scoped to a stable exercise definition UUID where present; for older
  snapshots without a definition, an unambiguous match on name, equipment
  AND muscle is merged with the known definition. Variants remain separate;
  ambiguous legacy definitions retain separate keys. The name shown is the
  most recently completed known session's snapshot. Every visible bar and
  accessible summary includes original-local date, load and performed reps,
  in a user-selectable kg/lb unit (defaulting to latest recorded unit).
  Bars scroll horizontally on narrow displays rather than truncating
  exercise data. The date of every trend point is the **session finish**
  in its original timezone offset (not the selected set's completion time),
  so workouts spanning midnight agree with the history list.
- Empty/error cases never render fictitious training numbers. Refresh uses
  a retained `FutureProvider` backed by an ObjectBox background read
  transaction. Switching tabs reuses the cached snapshot rather than
  blocking the main thread or re-reading per visit. Completing or discarding
  a workout or explicit user refresh invalidates the provider. The
  calculation time is injected via `progressNowProvider` for deterministic
  rolling 30/90-day filters, with a tab-leave/return clock regression test.

## Tests / QA

- Pure Dart model tests cover completed-only filtering, planned/warm-up/
  skipped/unloaded exclusion, integer gram arithmetic, per-workout best load,
  stable grouping and stored timezone offsets.
- Real native ObjectBox tests close/reopen the Store, verify history
  persistence, descending order, and exclusion of unfinished/discarded,
  soft-deleted and unknown statuses. The committed frozen pre-index generated
  model at `apps/mobile/test/progress/fixtures/objectbox_pre_status_index.g.dart`
  writes an actual old-format database; the test then closes and opens it
  with the current indexed model and verifies session, exercise, set, counts
  and indexed-status query. Never regenerate the frozen fixture.
- Progress widget tests check empty screen, true recorded volume/trend,
  navigating a completed session into read-only detail, exclusion of
  unfinished sessions, dark theme and wide layout, cross-midnight dates,
  round-trip visit clock expiry and consistent lb trend/volume display.
- Still required before release: physical-device iOS/Android persistence
  and process death, backup exclusions, low-end device performance profiling,
  accessibility at 2× scaling, screen-reader labels, low-end tablets,
  complete CI/Codemagic deployment and manual UX review.

## Known tradeoffs

- Completed sessions are filtered by indexed status and conjunctive
  nondeleted/completed/origin conditions inside ObjectBox. A background
  isolate reads the result, cached across tab switches. Child exercises and sets are hydrated with indexed `sessionUuid` and
  `exerciseUuid` queries in bounded batches of 200, avoiding N+1 reads.
  The 300-session/1,200-set CI benchmark gives an initial hosted-machine
  observation, not a low-end device guarantee. Profile again on real
  devices before release.
- Adding the status index regenerates `objectbox.g.dart` and
  `objectbox-model.json`; preserve all existing UIDs and validate opening
  older persisted databases before shipping. The committed legacy-model
  upgrade test is required in the full Flutter test suite.
- Training volume is deliberately partial if weights are omitted. No
  bodyweight-to-load inference, no personal-record prediction and no
  HealthKit/Health Connect metrics are produced.
- Snapshots from older sessions lacking definition UUIDs can group by
  normalized name; distinct movements with identical historical names may
  collide. This is a read-only presentation fallback, not record mutation.
- Historical records have no account-level backup until Phase 2 consented
  backfill, and should be clearly presented as **local only**.
- Today health metric demo tiles remain prototype-only until Phase 3
  permission-based platform reads; they are not workout history.
- CI also explicitly installs and verifies Android JNI CMake 3.22.1 with
  bounded retries before building the APK. This fixes an Android SDK package
  download failure seen in PR CI; it does not alter workout behavior or
  bypass release checks.
- PR #11 is review-only; **no autonomous merge**.
