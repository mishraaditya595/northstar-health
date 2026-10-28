# NorthStar release-readiness gates

**Status (27 October 2026):** Phase 1 and P2-01–P2-07 source features are merged, **not released or verified for production**. P2-08 hosted security, native-device and large-history/data-rights acceptance is outstanding. Watch recording and health integration remain unimplemented; neither mobile nor watch app is ready for store distribution.

## Source and builds

- Mobile Flutter project rooted at `apps/mobile`, version-controlled Android and iOS runners plus `pubspec.lock`; no project generation in normal CI.
- Separate `apps/wear_os` APK build with committed official Gradle wrapper and Kotlin/Compose app.
- SwiftUI `apps/watch_os/Sources` is the single watch source; XcodeGen proof-target compiles only on macOS with Xcode/watchOS SDK. **An actual Apple Watch companion target embedded in the iOS Runner/Xcode workspace is still a blocker.**
- Mobile iOS Release archive with correct app ID, provisioning/signing, HealthKit entitlements only when health is implemented; validate launch and rotation on phones/iPads.
- Watch iOS embedding, companion bundle identifiers, signing, TestFlight archive/physical pairing and watch-only source experiment must not be confused.
- Wear OS uses final app identity/signing, Play Console declarations and physical round-watch layout tests; package IDs in scaffolding are placeholders.
- Keep FlutterWatch custom toolchain out of stable builds; experimental comparison only.

**Controlled backend deployment pipeline:** Codemagic now has [manual Supabase staging/production preview, migration and Edge Function workflows](SUPABASE_CODEMAGIC_DEPLOY.md), subject to private credential groups, per-commit approvals and operator acceptance. The existence of these workflows is **not evidence of any hosted deployment**. The 11 existing app/watch Codemagic builds remain templates.

## P2-08 immediate release blockers

**P2-08 work started, not passed:** The [hosted preflight and release execution plan](implementation/phase-2/p2-08-hosted-release-plan.md) adds a read-only, two-signed-user security audit and synthetic CI tests. The connected development project was observed with 6/11 migrations and no Edge Functions on 27 October 2026; no deployment or real-account audit has been performed. The read-only audit is only a subset of hosted release acceptance.

- **Hosted database rollout:** reconcile migration history with the **11 committed migrations** (including the P2-07c fresh Auth-session gate) and verify UTC backfill semantics and transaction/index impact before deploying to a data-bearing project. The repository does not prove hosted application.
- **Real-account security:** independently test signed user JWTs and RLS against a nonproduction hosted project: cross-user SELECT/RPC restrictions, two-device upload/restore/revisions/tombstones, stale/deleted-user JWT paths, fresh-session deletion gate, Auth hard-delete cascades and network-uncertain recovery. Synthetic pgTAP and mocked HTTP are necessary but not substitutes.
- **JSON export rights:** the current **4 MiB in-memory output limit** can block all-history export. Measure Android/iOS low-memory behavior and native SAF/UIDocumentPicker lifecycle; implement/validate a bounded-memory larger-history path (or a justified device-tested ceiling that satisfies the all-history requirement) before release. Verify complete and correct synthetic exports.
- **Safe account exit:** device-test confirmation, verified deletion cleanup/retry, fail-closed uncertainty, and ADR-0007's two separately confirmed recovery exits (keep original owner's files locked, or explicitly erase only that owner's local partition), including cancellation and crash/relaunch.
- **Operations/privacy:** owner-scoped receipt-expiry pruning schedule, backup/restore epoch rotation runbook, legal retention/disclosure, secure logging and independent security review. No diagnostics data collection until the separately reviewed Firebase gate is met.

Track evidence in [P2-08 export validation](implementation/phase-2/p2-08-workout-export-release-validation.md) and the [account deletion runbook](../supabase/ACCOUNT_DELETION_RUNBOOK.md).

## Feature and privacy readiness

- ObjectBox real sessions/sets with generated model UID fixture migration, durable offline writes and recovery through process death.
- No Supabase synchronization release until mandatory authentication, authenticated RLS, strict completed-workout DTO allowlist, conflicts, tombstones, owner-scoped restoration and privacy disclosures are verified under ADR-0005. The development RPC/migrations are not a release.
- No HealthKit/Health Connect reads or summary exports until permissions/consent, provenance, stale/denied, duplicate-platform-workout prevention and release policy review.
- No Firebase SDK collection until separate diagnostics/analytics default-off initialization, consent controls, redaction and synthetic leak tests.
- Watch set logging must persist locally and survive screen off, disconnect, battery constraints and reconnect before UI claims success; native sensors and workout lifecycle operate independently of UI. Two-stage ACK (watch->phone and phone->Supabase).

## Device validation

- Android low-memory device and current Android tablet in portrait/landscape, resizing; iPhone and iPad split view; dynamic text, talkback/voiceover and both themes.
- Apple Watch and Wear OS physical watch: real 60–90 minute workout, pause/resume/end, health permissions, workout summary ownership, power/battery/CPU profiling, offline log replay/duplicate handling, recovery after killed UI.
- Reproducible CI passes for contract fixtures, Flutter format/analyze/test/APK, Wear OS debug, macOS iOS/watchOS target builds.
- Distribution is gated by independent review and manual Apple/Google store smoke testing; passing unit tests alone never authorizes a release.

## Ordered engineering follow-ups

1. Finish the **P2-08 release gates above** before describing Phase 2 as shipped; retain real-device and hosted test evidence with commit SHA, environment and outcome.
2. Integrate `apps/watch_os/Sources` into an actual embedded iOS Runner watchOS companion target; verify bundle IDs, signing and TestFlight/physical pairing.
3. Verify mobile iOS, standalone watchOS and Wear OS builds in macOS/Android CI and profile low-end devices. Replace placeholder app identifiers only with approved production identities.
4. Begin future Phase 3 HealthKit/Health Connect permission-based reads and Phase 4 user-controlled health-platform summary export only after the separate consent and provenance designs are verified.
5. Implement durable native watch workout recording, offline event transport, deduplication and the watch-to-phone-to-cloud two-stage ACK before claiming wearable logging support.

## CI/CD cutover status

Codemagic will become the main build/release provider, but `codemagic.yaml` is currently a **manual-only, intentionally failing template**. Refer to [Codemagic setup](CODEMAGIC.md). Existing GitHub Actions checks remain the only verified build automation until Codemagic is connected and equivalent builds pass. No CI template authorizes store delivery or watchOS companion release.
