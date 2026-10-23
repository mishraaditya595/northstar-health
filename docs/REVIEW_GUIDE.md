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
- [ ] Cloud payload allowlist: **completed logs only**, no health cache/vitals/drafts/plans
- [ ] Guest->account import consent; logout/account-switch with unsynced data
- [ ] Supabase RLS SELECT/INSERT/UPDATE/DELETE and any privileged RPC ownership, least-privilege
- [ ] Concurrent device update/revision rejection; retry identical operation ID; deletion tombstones/cursor ordering
- [ ] HealthKit/Health Connect source/time/units, per-metric permission, cache expiry/revocation, no double aggregate
- [ ] Export-only completed app-owned summary; Apple Watch saved HKWorkout skip; ambiguous retry reconciliation
- [ ] Firebase native collection default off, separate consent and synthetic sensitive-field redaction test
- [ ] Watch native sensor background session, persistent set events, acknowledgment and interrupted 60–90 min workout on real hardware
- [ ] Test commands/checks truly run; version pinning, performance on entry-level devices, documented rollback

## Definition of done

Document why and scope; screenshots of phone/tablet layouts in both modes if UI changed; privacy and permission inventory; test and CI results; known gaps. Never mark a mocked flow or architectural contract as production-ready. Wear OS/watchOS proof requires real devices, not just simulator screenshots. Follow [CLOUD_SYNC](CLOUD_SYNC.md), [HEALTH_DATA](HEALTH_DATA.md), [FIREBASE_PRIVACY](FIREBASE_PRIVACY.md) and [SYNC_PROTOCOL](SYNC_PROTOCOL.md).
