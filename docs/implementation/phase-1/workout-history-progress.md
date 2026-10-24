# Phase 1 — Completed workout history and progress (PR #11)

**Base:** latest `main` after merged PR #10 at
`e2c3ddcb895367f3272c00531f581e624600ed77`.
**Scope:** offline, read-only, factual **NorthStar workout history**.
Adds an indexed `WorkoutSession.status` property to the existing ObjectBox
schema (regenerated model and stable UIDs); no new entity or new health data.
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
- Summary shows actual completed-workout count, performed *working*-set
  count and **loaded volume (kg × reps)**. Volume sums integer
  `reps × loadGrams` only for completed working sets with a recorded load.
  Unloaded working sets are counted separately, never converted to zero
  kilograms. When no positively loaded working set exists the volume card
  shows a dash and `No loaded sets`. Explicit 0-kg entries are recorded
  separately and excluded from meaningful loaded strength/volume trends. Skipped/planned/warm-up/unsupported sets do not inflate volume.
- Exercise trend is maximum **logged working-set load per finished workout**,
  not an estimated 1RM, rate of strength gain or caloric metric. The trend
  is scoped to a stable exercise definition UUID where present; for older
  snapshots without a definition, an unambiguous match on name, equipment
  AND muscle is merged with the known definition. Variants remain separate;
  ambiguous legacy definitions retain separate keys. The name shown is the
  most recently completed known session's snapshot. Every visible bar and
  accessible summary includes date, load and performed reps, in a user-
  selectable kg/lb unit (defaulting to latest recorded unit).
- Empty/error cases never render fictitious training numbers. Refresh uses
  a retained `FutureProvider` backed by an ObjectBox background read
  transaction. Switching tabs reuses the cached snapshot rather than
  blocking the main thread or re-reading per visit. Completing or discarding
  a workout or explicit user refresh invalidates the provider. The
  calculation time is injected via `progressNowProvider` for deterministic
  rolling 30/90-day filters.

## Tests / QA

- Pure Dart model tests cover completed-only filtering, planned/warm-up/
  skipped/unloaded exclusion, integer gram arithmetic, per-workout best load,
  stable grouping and stored timezone offsets.
- Real native ObjectBox tests close/reopen the Store, verify history
  persistence, descending order, and exclusion of unfinished/discarded,
  soft-deleted and unknown statuses.
- Progress widget tests check empty screen, true recorded volume/trend,
  navigating a completed session into read-only detail, exclusion of
  unfinished sessions, dark theme and wide layout.
- Still required before release: physical-device iOS/Android persistence
  and process death, backup exclusions, large-database performance profiling,
  accessibility at 2× scaling, screen-reader labels, low-end tablets,
  complete CI/Codemagic deployment and manual UX review.

## Known tradeoffs

- Completed sessions are filtered by indexed status and conjunctive
  nondeleted/completed/origin conditions inside ObjectBox. A background
  isolate reads the result, cached across tab switches. Per-session/exercise
  lookups still scale with history size: the 300-session/1,200-set CI
  benchmark gives an initial hosted-machine observation, not a low-end
  device guarantee. Profile again on real devices before release.
- Adding the status index regenerates `objectbox.g.dart` and
  `objectbox-model.json`; preserve all existing UIDs and validate opening
  older persisted databases before shipping.
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
- PR #11 is review-only; **no autonomous merge**.
