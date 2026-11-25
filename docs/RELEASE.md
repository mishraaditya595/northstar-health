# BeyondRep release-readiness gates

**Status (27 October 2026):** Phase 1 and P2-01–P2-07 source features are merged, **not released or verified for production**. P2-08 hosted security, native-device and large-history/data-rights acceptance is outstanding. Watch recording and health writes remain unimplemented; Phase 3 health reads exist in source only (see Phase 3 gates below); neither mobile nor watch app is ready for store distribution.

## Source and builds

- Mobile Flutter project rooted at `apps/mobile`, version-controlled Android and iOS runners plus `pubspec.lock`; no project generation in normal CI.
- Separate `apps/wear_os` APK build with committed official Gradle wrapper and Kotlin/Compose app.
- SwiftUI `apps/watch_os/Sources` is the single watch source; XcodeGen proof-target compiles only on macOS with Xcode/watchOS SDK. **An actual Apple Watch companion target embedded in the iOS Runner/Xcode workspace is still a blocker.**
- Mobile iOS Release archive with correct app ID, provisioning/signing, HealthKit entitlements only when health is implemented; validate launch and rotation on phones/iPads.
- Watch iOS embedding, companion bundle identifiers, signing, TestFlight archive/physical pairing and watch-only source experiment must not be confused.
- Wear OS uses final app identity/signing, Play Console declarations and physical round-watch layout tests; package IDs in scaffolding are placeholders.
- Keep FlutterWatch custom toolchain out of stable builds; experimental comparison only.
- **Versioning:** `version:` in `apps/mobile/pubspec.yaml` is the default user-visible version name; bump it in a PR. The manual TestFlight job takes optional `version_name` and `build_number` inputs and, on `AUTO`, uses the pubspec version and the latest App Store Connect build plus one ([details](IOS_TESTFLIGHT_CODEMAGIC.md#version-name-and-build-number)). Android has no release job yet, so its `versionCode` strategy (latest Google Play build plus one) is still open in issue #49.

**Controlled backend deployment pipeline:** Codemagic now has [two manual Supabase jobs for database migrations and Edge Functions](SUPABASE_CODEMAGIC_DEPLOY.md), with preview/deploy inputs, project-bound protected credentials, explicit target confirmation and operator acceptance. The existence of these workflows is **not evidence of any hosted deployment**. Ten app/watch Codemagic builds remain templates; the manual [`mobile-ios-testflight` job](IOS_TESTFLIGHT_CODEMAGIC.md) uploads for internal TestFlight testing only and is not a release.

## P2-08 immediate release blockers

**P2-08 work started, not passed:** The [hosted preflight and release execution plan](implementation/phase-2/p2-08-hosted-release-plan.md) adds a read-only, two-signed-user security audit and synthetic CI tests. The connected development project was observed with 6/11 migrations and no Edge Functions on 27 October 2026; no deployment or real-account audit has been performed. The read-only audit is only a subset of hosted release acceptance.

- **Hosted database rollout:** reconcile migration history with the **11 committed migrations** (including the P2-07c fresh Auth-session gate) and verify UTC backfill semantics and transaction/index impact before deploying to a data-bearing project. The repository does not prove hosted application.
- **Real-account security:** independently test signed user JWTs and RLS against a nonproduction hosted project: cross-user SELECT/RPC restrictions, two-device upload/restore/revisions/tombstones, stale/deleted-user JWT paths, fresh-session deletion gate, Auth hard-delete cascades and network-uncertain recovery. Synthetic pgTAP and mocked HTTP are necessary but not substitutes.
- **JSON export rights:** export streams page-by-page through a protected temporary file (no size cap; bounded-memory in code, unmeasured on hardware). Measure Android/iOS low-memory behavior and native SAF/UIDocumentPicker lifecycle with histories well above the former 4 MiB cap before release. Verify complete and correct synthetic exports.
- **Safe account exit:** device-test confirmation, verified deletion cleanup/retry, fail-closed uncertainty, and ADR-0007's two separately confirmed recovery exits (keep original owner's files locked, or explicitly erase only that owner's local partition), including cancellation and crash/relaunch.
- **Operations/privacy:** owner-scoped receipt-expiry pruning schedule, backup/restore epoch rotation runbook, legal retention/disclosure, secure logging and independent security review. No diagnostics data collection until the separately reviewed Firebase gate is met.

Track evidence in [P2-08 export validation](implementation/phase-2/p2-08-workout-export-release-validation.md) and the [account deletion runbook](../supabase/ACCOUNT_DELETION_RUNBOOK.md).

## Phase 3 health-read release gates (owner actions, none done)

Implemented in source, **not released or device-verified**. Evidence and unrun checks: [p3-01](implementation/phase-3/p3-01-daily-health-summary.md).

- **Apple signing, before the next TestFlight build:** enable the HealthKit capability on the App ID in the Apple developer portal and regenerate the App Store provisioning profile used by the Codemagic TestFlight job. The app now ships a HealthKit entitlement, so signing is expected to fail without this. Not done.
- **Privacy policy live (issue #52)** and wired to the Health Connect rationale screen (currently a `TODO(#52)` that opens the app). Not done.
- **Store declarations:** App Store privacy labels; Google Play Data Safety form and Health Connect permissions declaration. Not done.
- **Builds:** the first Android debug APK build happens in GitHub Actions on the PR (not run locally); no Xcode build has been run, and the hand-edited Runner project and entitlements are unverified in Xcode.
- **Manual device matrix (all not run):**
  - iPhone with and without Apple Watch: grant, deny, revoke.
  - Android 14+ and Android 9-13, with and without the Health Connect app.
  - Android partial grant (some types allowed, others denied).
  - Android: deny twice, then tap Not allowed · Manage (Health Connect may stop showing the sheet).
  - Android: Not allowed · Manage opens Health Connect settings (not run).
  - Android: session-only sleep source shows the session duration (not run).
  - Android workout JSON export still saves after the `FlutterFragmentActivity` change (highest risk).
  - Account A, sign out, account B: B sees the Connect card.

## Health insights stage 1 device QA (ADR-0009, owner actions, none done)

Implemented in source on a feature branch, **not released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Two wearables write sleep the same night (e.g. watch and ring): one source per night, caption names it | not run | not run |
| Phase 3 account upgrades: "Allow more data" shows once, hides after one request even with types still declined | not run | not run |
| Health Connect history permission granted vs not: 30-day and earlier reads | n/a | not run |
| iOS denial of the new types reads as empty, never 0 | not run | n/a |
| Text scale 2.0 on overview and the four detail screens | not run | not run |
| Tablet / split screen layout | not run | not run |
| Light and dark themes | not run | not run |
| A Health Connect source that writes sleep sessions without stages: the night shows its duration, no stages, no score | n/a | not run |
| Skin temperature on a Pixel / Galaxy Watch: sleep detail shows a deviation vs baseline, never an absolute °C | n/a | not run |

## Health insights stage 2 device QA (ADR-0009, owner actions, none done)

Readiness is implemented in source, **not released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Good day with a watch: readiness card, detail screen and Today row show a score and its parts | not run | not run |
| Low day: note on the Train card, and the start note appears once per day before a workout (Train and Today) | not run | not run |
| HRV without resting heart rate (and the reverse): score still shows from the input present | not run | not run |
| Baseline building (under 14 days): "not ready" with days remaining, no score | not run | not run |
| Phone only, no watch or wearable: no score, no zero | not run | not run |

## Health insights stage 3 device QA (ADR-0009, owner actions, none done)

Training tie-ins are implemented in source, **not released or device-verified**. Every row is not run.

| Check | iOS | Android |
| --- | --- | --- |
| Muscle recovery map after a heavy leg day and after an arm day: legs fade over 72 h, arms over 48 h | not run | not run |
| Train "Better fit today" with real workout history: suggests the most recovered plan, never one hitting recovering muscles | not run | not run |
| Low readiness day: suggestion is the lightest recovered plan | not run | not run |
| Insights after 30 days of sleep, resting heart rate and workouts: "From your training" on Health, Sleep detail and Heart detail | not run | not run |
| Fewer than the minimum nights or sessions: no insight line shown | not run | not run |
| No wearable: Better fit and recovery lines still work, no insight lines | not run | not run |

## Feature and privacy readiness

- ObjectBox real sessions/sets with generated model UID fixture migration, durable offline writes and recovery through process death.
- No Supabase synchronization release until mandatory authentication, authenticated RLS, strict completed-workout DTO allowlist, conflicts, tombstones, owner-scoped restoration and privacy disclosures are verified under ADR-0005. The development RPC/migrations are not a release.
- HealthKit/Health Connect daily-summary reads are implemented in source (Phase 3, ADR-0008) but gated by the Phase 3 list below. No health writes or summary exports until permissions/consent, provenance, stale/denied, duplicate-platform-workout prevention and release policy review.
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
4. Complete the Phase 3 health-read gates above, then begin Phase 4 user-controlled health-platform summary export only after the separate consent and provenance designs are verified.
5. Implement durable native watch workout recording, offline event transport, deduplication and the watch-to-phone-to-cloud two-stage ACK before claiming wearable logging support.

## CI/CD cutover status

Codemagic will become the main build/release provider, but `codemagic.yaml` is currently a **manual-only, intentionally failing template**. Refer to [Codemagic setup](CODEMAGIC.md). Existing GitHub Actions checks remain the only verified build automation until Codemagic is connected and equivalent builds pass. No CI template authorizes store delivery or watchOS companion release.
