## Why / linked issue

Closes #

## What changed

## AI assistance
- [ ] No AI agent wrote any of this PR
- [ ] An AI agent wrote part or all of it: <!-- which agent? --> and I have read the full diff and ran the checks below myself

## Screenshots (UI changes only)
- [ ] Phone (light/dark)
- [ ] Tablet / split view (light/dark)

## Checks
Tick only what you actually ran. Write "not run" and why for anything else.
- [ ] `dart format --output=none --set-exit-if-changed lib test`
- [ ] `flutter analyze`
- [ ] `flutter test`
- [ ] Ran the app against my own Supabase project ([guide](https://github.com/mishraaditya595/northstar-health/blob/main/docs/CONTRIBUTOR_SUPABASE_SETUP.md))
- [ ] Real device tests (required where platform APIs changed)
- Not run and why:

## Risks / rollback / deferred work

---

<details>
<summary><strong>Only if you touched data, sync, auth, storage, platform or build files</strong></summary>

These areas need a maintainer-approved issue first (see [AGENTS.md](https://github.com/mishraaditya595/northstar-health/blob/main/AGENTS.md#external-contributions)).

### Data flows and privacy
- [ ] No new collection, export or cloud upload (or provide detailed permission + consent change)
- [ ] ObjectBox local write and model JSON migration reviewed
- [ ] Supabase completed-workout-only backup, version/conflict/RLS tested
- [ ] HealthKit/Health Connect read/write scope and source receipts reviewed
- [ ] Watch native session + offline ACK/replay reviewed
- [ ] Firebase SDK auto-collection OFF until separate consent; telemetry payload allowlist tested
- [ ] Offline/empty/stale/error/denied/account-switch coverage

### Independent review handoff: challenge these files and state transitions

### Monorepo / native packaging
- [ ] `apps/mobile` Flutter lockfile/runners correct; no duplicate root package
- [ ] `apps/wear_os` Gradle build, watch manifest, source ownership checked
- [ ] `apps/watch_os` native SwiftUI sources and **actual** iPhone companion embedding status disclosed
- [ ] `contracts/workout_sync/v1` versioned fixtures validated
- [ ] No CI write permission or credentials in normal build workflows

</details>
