# NorthStar independent AI code review protocol

The implementing agent cannot self-approve. Reviewer reads the **actual diff**, ADRs, data flows and test evidence rather than trusting the PR summary. Human approval is required for scope, network, privacy/consent, schema, health permissions and watch-session behavior changes.

## Severity rubric

**Blocker:** unauthorized sensitive-data upload, fabricated health data, workout loss, cross-user RLS bypass, automatic platform health write or duplicate workout, uncommitted local save acknowledged to user/watch, SDK diagnostic upload before consent, database UID reset.

**High:** double counted platform samples, guest workout attached to wrong account, cloud overwrites unsynced edits, watch logs lost on disconnect, missing health cache purge after revocation, tablet inaccessible/overflows, inadequate migration/restore tests.

**Medium:** stale metric labels, deficient large-text layout, missing privacy event-schema tests, wide rebuild/jank, undocumented dependency or improper source metadata.

Every finding: affected file/line, reproducible impact, smallest correction, test coverage and what wasn't validated.

## Mandatory review matrix

- [ ] Phone Android/iOS; tablet/iPad portrait, landscape and split view; dark/light, text scale and keyboard
- [ ] Offline workout edits; process death; rest timer; ObjectBox local write+outbox atomicity
- [ ] ObjectBox generated bindings and `objectbox-model.json` UID stability; migration on prior DB
- [ ] Cloud payload allowlist: authenticated, completed NorthStar phone workouts only; no unfinished sessions, health cache/vitals, rest/recovery checkpoints, imported workouts or plans (ADR-0005)
- [ ] Mandatory signup, no guest mode; logout/account-switch with unsynced data
- [ ] Supabase RLS SELECT/INSERT/UPDATE/DELETE and any privileged RPC ownership, least-privilege
- [ ] Concurrent device update/revision rejection; retry identical operation ID; deletion tombstones/cursor ordering
- [ ] HealthKit/Health Connect source/time/units, per-metric permission, cache expiry/revocation, no double aggregate
- [ ] Export-only completed app-owned summary; Apple Watch saved HKWorkout skip; ambiguous retry reconciliation
- [ ] Firebase native collection default off, separate consent and synthetic sensitive-field redaction test
- [ ] Watch native sensor background session, persistent set events, acknowledgment and interrupted 60–90 min workout on real hardware
- [ ] Test commands/checks truly run; version pinning, performance on entry-level devices, documented rollback

## Definition of done

Document why and scope; screenshots of phone/tablet layouts in both modes if UI changed; privacy and permission inventory; test and CI results; known gaps. Never mark a mocked flow or architectural contract as production-ready. Wear OS/watchOS proof requires real devices, not just simulator screenshots. Follow [CLOUD_SYNC](CLOUD_SYNC.md), [HEALTH_DATA](HEALTH_DATA.md), [FIREBASE_PRIVACY](FIREBASE_PRIVACY.md) and [SYNC_PROTOCOL](SYNC_PROTOCOL.md).

## Repository restructuring / build review

- [ ] Flutter code preserved under `apps/mobile`; root has no duplicate Dart package; native platform runners and lockfile tracked
- [ ] Native mobile runners built from pinned Flutter SDK, tested on actual Android/iOS devices before release
- [ ] watchOS source under `apps/watch_os/Sources`; generated watch-only Xcode project must **not** be confused with verified embedded iPhone companion target
- [ ] independent Wear OS Gradle compilation and watch-manifest checks
- [ ] same versioned event schema + fixtures underpin Dart/Kotlin/Swift adapters when implemented
- [ ] no new HealthKit/Health Services permissions or signing secrets introduced by scaffolding
- [ ] CI workflow paths, readme visual links, AGENTS references and release docs updated
