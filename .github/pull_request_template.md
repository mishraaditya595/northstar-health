## Why / linked issue

## Actual behavior, code changes and affected device layouts

## UI screenshots
- [ ] Phone (light/dark)
- [ ] Tablet / split view (light/dark)

## Data flows and privacy
- [ ] No new collection, export or cloud upload (or provide detailed permission + consent change)
- [ ] ObjectBox local write and model JSON migration reviewed
- [ ] Supabase completed-workout-only backup, version/conflict/RLS tested
- [ ] HealthKit/Health Connect read/write scope and source receipts reviewed
- [ ] Watch native session + offline ACK/replay reviewed
- [ ] Firebase SDK auto-collection OFF until separate consent; telemetry payload allowlist tested

## Quality and security
- [ ] dart format --output=none --set-exit-if-changed lib test
- [ ] flutter analyze
- [ ] flutter test
- [ ] Offline/empty/stale/error/denied/account-switch coverage
- [ ] Real device tests where platform APIs changed
- [ ] Checks not run and why

## Risks / rollback / explicitly deferred work

## Independent review handoff: challenge these files and state transitions

## Monorepo / native packaging (when affected)
- [ ] `apps/mobile` Flutter lockfile/runners correct; no duplicate root package
- [ ] `apps/wear_os` Gradle build, watch manifest, source ownership checked
- [ ] `apps/watch_os` native SwiftUI sources and **actual** iPhone companion embedding status disclosed
- [ ] `contracts/workout_sync/v1` versioned fixtures validated
- [ ] No CI write permission or credentials in normal build workflows
