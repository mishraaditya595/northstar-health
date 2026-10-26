# P2-05 — Server-side completed workout progress

**Implementation record:** [PR #17](https://github.com/mishraaditya595/northstar-health/pull/17), **merged into main on 2026-10-26**. Merge is not a database deployment: hosted P2-05 deployment and live-auth QA remain outstanding.  
**Owner-approved policy:** [ADR-0005](../../adr/0005-mandatory-auth-and-workout-sync.md). Only account-authenticated, completed NorthStar **phone** workouts are eligible for cloud backup. The server stores no heart rate, sleep, steps, or other physiological health samples.

## Scope

P2-01 already computes per-workout validated metrics synchronously during an authenticated `sync_workout` write:

- `completed_working_sets`: working sets with status completed (not warmups)
- `loaded_working_sets`: those completed working sets with a positive, known load
- `loaded_volume_gram_reps`: sum of known positive load in **grams × reps**, or SQL `NULL` if no loaded working set exists

P2-05 adds reliable **cross-workout progress** without a separate denormalized cache that could become stale when a workout is edited or tombstoned. It does **not** send new measurement categories to Supabase or replace Phase 1 offline Progress.

## Server processing and query contract

**Migration:** `20261026063000_phase2_server_progress_aggregation.sql`.

- Add server-owned `progress_completed_at timestamptz` and `progress_local_day date` on `public.workout_records`.
- Compute these in a trigger on every insert/update of validated `payload`, `status`, or `deleted_at`. A tombstone clears both; a corrected completion timestamp moves its aggregate from the old day to the new day. Backfill previously committed records without modifying operation UUIDs, server revisions, change cursors, or payloads. The migration requests `SET LOCAL TIMEZONE = 'UTC'`; however, clean CI replay emitted `25P01` ('SET LOCAL can only be used in transaction blocks'). Until a reviewed deploy-time transaction strategy or additive remedy is verified, **do not assume the UTC session setting took effect for historical zone-free timestamps**.
- Original local date is **UTC completion instant + the recorded original UTC offset**, not the current device offset or server timezone. This preserves the day originally experienced during travel.
- Add a partial owner/day index for nondeleted records. P2-01 migration 7 already enforces `status = 'completed'`, so repeating that predicate in the index and read query is redundant.
- New read-only `public.get_workout_progress(p_start_day date,p_end_day date,p_recent_limit int default 100)` runs as **SECURITY INVOKER**, checks `auth.uid()` and `is_anonymous`, respects existing RLS owner SELECT, and grants EXECUTE only to `authenticated`. It never accepts a `user_id` parameter.
- Return `schema_version:1`, `start_day`, `end_day`, `totals`, `days`, `recent_workouts`, `recent_truncated`. The inclusive date range is limited to **366 calendar days**; invalid or infinite dates return SQLSTATE `22023`, including near PostgreSQL's maximum supported `DATE`. Recent results are limited to **1–200** and are explicitly marked truncated if more records exist. Daily aggregates include only actual workout days; no synthetic zero-workout entries.
- `totals` and each day include workout count, completed working sets, loaded working sets and nullable loaded volume in gram-reps. A day with zero loaded sets has volume `null`, **never 0 pretending weight was recorded**. Null/incomplete stored processing counters propagate as `null` rather than silently reducing true counts. Each recent workout includes its server revision, with `completed_at` serialized in UTC ISO 8601 (six-digit fractional seconds and a literal `Z`) independently of the caller's SQL session timezone. This is read-only history, **not a restore cursor**.
- The RPC reads authoritative data already committed by P2-01. It never reuses client-computed progress, never updates workouts, and never grants new direct table writes. An update/replay does not count twice. A tombstone disappears from visible progress while its sync deletion semantics are preserved.

### Out of scope

No speculative 1RM estimate, calorie estimate, normalized exercise catalog ID or cross-session per-exercise grouping: v1 snapshots contain per-workout exercise UUIDs and display names, not a stable shared exercise ID. Grouping by display names would misattribute renames/different exercises. No Flutter UI integration, mobile pull/restore, client notifications, or cloud raw-health sync in P2-05. UI changes are P2-06/P2-07.

## Tests and verification

`supabase/tests/workout_progress.test.sql` supplies **49 TAP-visible pgTAP assertions**, rolled back after execution, covering:

- Fresh account empty-state semantics, 366-day range / result limits and infinity/max-date boundaries, anon EXECUTE denial, signed-in anonymous rejection, owner-scoped RLS and explicit direct INSERT/UPDATE/DELETE denial.
- Local-day crossing due to original UTC offset; server-calculated working/loaded set counts and gram-rep volume; warmup exclusion and weightless workout volume `null`.
- Multiple workouts and days, bounded recent list/truncation, deterministic sorting and UTC `Z` serialization under a non-UTC database session.
- Privileged synthetic fixture temporarily nulls each server counter independently: verify daily and total counts and loaded volume remain `null`, then restore the fixture before further assertions.
- Server CAS correction replacing volume and original local day, exact idempotent replay, tombstone removal and derived field cleanup.
- Two independent synthetic account JWT contexts with no cross-owner progress exposure.

**Verification:** Clean `supabase db reset` must replay all eight migrations, then `supabase test db` must pass both suites. The expanded P2-05 suite now targets **65** assertions (64 existing + 65 new = **129**), including missing counters, three kinds of direct DML denial, UTC output and extreme date input; the clean Supabase SQL CI passed before merge with 129 assertions; live-auth and device coverage remain outstanding. This is not real multi-client JWT network coverage.

**Development data precheck (26 October 2026):** Read-only aggregate inspection found **0 active completed records**, **0 malformed or zone-free completion timestamps**, and **0 malformed offsets**. The zero malformed counts are not proof that legacy records on other environments are valid; repeat the inspection for each target environment. No records or schema were modified.

**Deployment locking:** The backfill `UPDATE` may hold row locks and generate substantial WAL; ordinary `CREATE INDEX` can block writers. Before production, measure row count/size and live write traffic, then choose a maintenance window **or** split the work into verified batched backfill plus a separately managed non-transactional `CREATE INDEX CONCURRENTLY` migration. Don't present the merged migration as zero-downtime on a populated table.

**Deployment gate:** The connected development Supabase migration history showed only six migrations while GitHub `main` contains seven. Do not deploy P2-05 independently. First reconcile/apply the already-reviewed completed-only seventh P2-01 migration in a controlled dev environment, confirm `supabase_migrations.schema_migrations` matches committed files, then apply P2-05. This PR adds schema SQL to the repo but does not apply it to the connected hosted instance.

Before production: clean CI green, security/performance advisors, signed-JWT two-user RLS tests, latency profiling with long histories, mobile cross-device comparisons, a verified account export and deletion policy, and iOS/Android physical-device QA.

## Rollback and data safety

To temporarily suspend analytics, revoke authenticated EXECUTE on the new read-only RPC or deploy a corrective migration. **Do not delete workouts, current progress metrics, tombstones, outbox operations or P2-01 RPCs.** This feature has no job scheduler, mutation API, or separate rollup table needing destructive rebuild. Repair the trigger/index/function in a forward-only migration if necessary.
