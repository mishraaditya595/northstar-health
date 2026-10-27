# P2-08 — Workout-history export release verification

**Status:** Not executed. This is a required **release gate**, not an automatic
merge block for P2-07b PR #27. It does not assert the feature is safe to ship
or that native / hosted checks have already passed.

**Owner:** Human maintainer, using disposable test accounts and synthetic
completed NorthStar phone workouts only. Record hardware/OS builds and results
before approving a release. Never commit test JWTs, export files or PII.

## 1. Bounded export / peak-memory measurement

P2-07b currently caps **output JSON bytes at 4 MiB**, a provisional limit
picked conservatively. It is **not measured** in app heap or process RSS and
must not become a permanent all-history limit under ADR-0005.

- Test on the lowest supported RAM-class Android phone (ideally 2–3 GB) and
  a low-memory supported iPhone, plus a representative tablet. Record exact
  device, RAM, API/iOS version, build SHA, performance mode and storage target.
- Generate only synthetic account workloads: empty; 100; 1,000; near-4 MiB,
  at-4 MiB and over-4 MiB JSON; many exercises/sets and nullable values.
- For Android, sample process memory while fetching, serializing, launching
  the picker and saving to local Documents and a slow SAF/cloud provider.
  Record `adb shell dumpsys meminfo dev.northstar.northstar_health` along
  with Android Studio Memory Profiler's **peak PSS/RSS**, collection cadence
  and observed low-memory events/ANRs. OS tools may report PSS rather than
  RSS; label values accurately and do not misrepresent one as the other.
- For iOS, profile the real Runner with Xcode Instruments (Allocations and
  VM Tracker) / Xcode memory gauge across the same stages. Record peak resident
  memory/footprint and any termination or UI stalls.
- Inspect actual exported files: valid UTF-8 JSON; complete workout count and
  exercise/set/null values; correct account; no tombstones, local-only pending
  uploads, custom plans or physiological data. Check cancellation creates no
  claimed successful export.
- Confirm oversize histories show a usable explanation, leave no purported
  complete export, and remain available in cloud. **Before production release,
  remove the inability to export larger accounts**: implement a reviewed
  bounded-memory/streaming architecture or increase the limit only to a
  defensible value supported by recorded device measurements. Repeat the
  all-history test with data exceeding the old cap.
- The user-selected SAF/iOS destination can be unencrypted or backed up by
  another service. Disclosure remains necessary regardless of memory result.

**Evidence record (fill in after execution):**

| Device / OS / RAM | App SHA | Synthetic JSON size | Save destination | Peak process memory + tool | ANR/OOM | Full file verified? |
| --- | --- | --- | --- | --- | --- | --- |
| Not run | — | — | — | — | — | — |

## 2. Android document lifecycle and provider failure

Use two disposable synthetic exports with different workout counts so files
cannot be confused:

1. Export to local Documents and a cloud/SAF provider. Confirm the result
   only reports **saved** after the byte stream closes successfully. Simulate
   an Activity recreation/rotation while the provider write is still running:
   the old Activity must not report a false failure before writer completion.
   If Flutter's old engine was destroyed and cannot receive the result, the
   user must independently check the selected file.
2. During a slow write, kill the **process**. Launch the app again and verify
   best-effort cleanup of the selected incomplete document. Repeat when the
   provider refuses `DocumentsContract.deleteDocument` or URI permission
   has expired; document the remaining external partial-file risk (not
   controllable by NorthStar).
3. Restart while an abandoned-export cleanup is active. Attempt a new export.
   It must be blocked until the cleanup finishes; the old marker must not
   clear or delete the new export's marker/file.
4. Test a writer failure, cancellation, and a picker result arriving after
   activity recreation. The `wt` open mode must truncate an existing document
   where the SAF provider supports it; failed writes attempt deletion without
   leaking URI/payload into logs.

The lifecycle implementation uses a **process-wide** synchronized cleanup
gate, unique marker token per write and a compare-before-clear marker; an
in-progress writer owns the terminal callback. These are code guarantees to
review, **not physical device results**.

## 3. iOS document lifecycle

- Compile Runner on a real iPhone/iPad. Exercise successful save,
  cancelled sheet, dismissal without delegate callback, failed presentation
  and app kill while the picker is open.
- Confirm temporary JSON uses atomic **complete file protection** at first
  write and the app cleans its own `northstar-export-*` temp folders after
  completion and on next launch. Confirm it never touches ObjectBox folders.
- Check re-entry after an interrupted presentation and verify the Account
  export action does not remain stuck on “Preparing export…”.
- Inspect exported file's JSON contents/owner. Record the observed data
  protection behavior on locked devices.

## 4. Hosted signed-JWT owner/RLS test (must be run against a test project)

The current `SupabaseWorkoutExportReader` test uses **mock HTTP**. SQL
pgTAP tests exercise policies under simulated roles. **Neither is a hosted
signed-JWT test.** No live hosted result is claimed for PR #27.

On a **nonproduction test project** with all Phase 2 migrations applied:

1. Create two disposable verified (non-anonymous) users A and B through the
   normal sign-in flow. Obtain short-lived JWTs **outside source control**,
   and prepare a fresh unauthenticated request. Do not use `service_role`
   for any client query.
2. Using the same public REST endpoints and project publishable key as the
   phone, create separate completed synthetic workouts with authenticated
   `sync_workout` for A and B. Verify each operation's owner and revision.
3. With A's JWT, GET `/rest/v1/workout_records` using the export reader's
   owner/status/deleted_at/high-water filters. Check only A's completed,
   undeleted payloads appear; B's records must not leak even when the query
   explicitly supplies B's UUID. Repeat inversely with B's JWT.
4. Create A's deletion tombstone via the authenticated delete command.
   Confirm the head query (which omits status/deleted filters) includes the
   tombstone's change sequence, while the completed-only export query
   excludes its payload. Include a page-size-limited (>100 rows) fixture,
   ID ordering and keyset `gt` traversal.
5. Repeat read attempts with anonymous auth, no JWT, expired/revoked JWT,
   wrong-owner filters and malformed bearer tokens. Verify denied/empty
   behavior as dictated by RLS and grants; never confuse a 401/403 with a
   valid empty history.
6. Make a concurrent owner mutation during multi-page export and assert
   final high-watermark changed and no file was reported saved.
7. Verify deletion of all **synthetic** fixtures and test users via the
   project's approved cleanup process, outside the test app. Record
   timestamp, project identifier, migration hashes, test harness version,
   pass/fail per case and sanitized evidence. Never publish tokens/exports.

**Evidence:** Not run; attach a sanitized results document only after actual
hosted execution. Account deletion itself is P2-07c and requires its own
P2-08 cross-device security tests.

## Release decision

Do not mark Phase 2 released until P2-07c and P2-08 pass, including
**all-history export at realistic account sizes**, hosted signed-JWT RLS and
native iOS/Android lifecycle/memory checks. A human may review and merge
code earlier under `AGENTS.md`; an agent must never merge.
