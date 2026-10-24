# Phase 1 — Exercise catalog and plan editor follow-up

**PR scope:** hardening of the merged exercise/plan builder (PR #7).
No ObjectBox model/property changes and no cloud, login or health permissions.

## Repository contracts

- Reject *new* plan rows referencing an archived exercise definition **inside
  the plan write transaction**. Pre-existing `PlanExercise` rows with the
  **same row UUID and exercise UUID** remain valid so previously saved plans
  can be edited safely after a custom exercise is archived. A second new row
  referencing that archived exercise is rejected; attempted saves roll back.
- `archivePlan(uuid, expectedUpdatedAtMs: ...)` rejects stale archive requests.
  Revisions advance monotonically during edits; the editor must refresh on
  `PlanEditConflict`.
- Removing rows from a plan only removes **that plan's children**; other
  plans and historical sessions are never affected.

## Editor and layout

- A boolean unavailable state replaces comparisons of error-string wording.
- The editor no longer reseeds the built-in catalog in `initState` and does
  not directly query ObjectBox/repositories in its build method. It consumes
  the Riverpod library snapshot and awaits its readiness when adding an item.
- Reload latest plan action on optimistic concurrency conflicts; requires
  explicit confirmation before discarding locally edited fields.
- Back navigation warns when local edits would be lost. Save and Archive
  navigate away only after their commit is successful.
- The summary displays upper-only rep targets, and Train content has a
  constrained maximum width on wide tablet viewports.

## Test evidence and deferred QA

- Native repository tests cover archived-row retention vs new-row rejection,
  safe removal of another plan's rows and stale archive rejection.
- Widget tests cover existing plan edits, conflict reload/discard, archive
  behavior and unsaved-exit guard.
- macOS local tests require v5.3.2 native ObjectBox: use
  `scripts/test_objectbox_macos.sh` from repo root. The script checks the
  official archive's SHA-256, temporarily copies the dylib into
  `apps/mobile/` (ignored by Git), runs tests, then removes the copy.
  No `DYLD_LIBRARY_PATH` dependency. The script was validated on macOS
  with Flutter 3.47.3. Linux CI continues to use the repository's pinned
  Flutter 3.47.7 and native ObjectBox setup.
- Android APK, device reboot/reinstall semantics, light/dark, tablet, 200%
  text scaling, accessibility and iOS build remain independent QA gates.
