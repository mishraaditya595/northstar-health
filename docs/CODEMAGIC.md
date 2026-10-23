# NorthStar Codemagic CI/CD skeleton

**Status: templates only.** The root `codemagic.yaml` defines 11 named **manual** workflows with intentionally non-successful placeholder steps. It is **not** yet a functional Codemagic build, release or distribution pipeline. No actual builds, Codemagic account connection, publishing or new signing credentials were configured as part of this change.

Codemagic reads `codemagic.yaml` **from the repository root**, even though apps live under `apps/`. Each workflow sets `working_directory` to the appropriate project. See [Codemagic YAML docs](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/) and [monorepo directory guidance](https://docs.codemagic.io/getting-started/adding-apps/).

## Available placeholders

| Workflow ID | Project path | Intended build |
| --- | --- | --- |
| `quality-checks` | root | Static checks, protocol tests, Flutter analyze/tests |
| `mobile-android-debug` | `apps/mobile` | Flutter Android debug APK |
| `mobile-android-profile` | `apps/mobile` | Flutter Android profile APK |
| `mobile-android-release` | `apps/mobile` | Flutter Android release AAB |
| `mobile-ios-simulator` | `apps/mobile` | Unsigned iOS simulator/debug build |
| `mobile-ios-adhoc` | `apps/mobile` | Signed Ad Hoc distribution IPA |
| `mobile-ios-testflight` | `apps/mobile` | Signed App Store/TestFlight IPA |
| `wear-os-debug` | `apps/wear_os` | Kotlin/Compose Wear OS debug APK |
| `wear-os-release` | `apps/wear_os` | Kotlin/Compose Wear OS release AAB |
| `watchos-simulator` | `apps/watch_os` | Standalone XcodeGen SwiftUI simulator proof |
| `watchos-companion-release` | `apps/mobile` | Intended embedded watchOS/iOS companion archive; **blocked** |

### Why every template intentionally exits with failure

Codemagic's manual Start new build can select a workflow even without an automatic `triggering` block. If a workflow only printed “hello,” it might be marked successful without compiling anything. Each stub prints **TEMPLATE ONLY** and `exit 1` to prevent false release confidence. Replace this guard with working code and validated artifacts before running a real build. No `publishing`, `android_signing`, `ios_signing` or active variable-group declarations are included.

## Setup sequence

1. Connect `mishraaditya595/northstar-health` to Codemagic and select **YAML configuration**. Once this PR is merged, scan its `codemagic.yaml` on the desired branch.
2. Determine machine entitlement and budget. All stubs use `mac_mini_m2` for a common starting point; `linux_x2` can be cheaper for Android/Wear OS but requires billing-enabled Codemagic access. Mac builds are required for iOS/watchOS.
3. Activate `quality-checks`, `mobile-android-debug`, and `wear-os-debug` first with actual commands from the existing GitHub workflows. Add Flutter lockfile enforcement and protocol tests. **Don't disable existing green GitHub checks until equivalent Codemagic jobs pass.**
4. Activate `mobile-ios-simulator` and `watchos-simulator` when Xcode/toolchains are confirmed. **The watchOS target currently only compiles standalone and is not embedded in iOS Runner.**
5. Finalize package/bundle IDs and configure signing identities/environment variable groups in the Codemagic UI. Never commit private keys, service account JSON, provisioning profiles or secrets.
6. Add artifacts and only then controlled App Store Connect / Play publishing to the proper release workflows. Define branch, tag, PR filters and approvals deliberately.
7. After successful Codemagic equivalent checks, modify or disable redundant `.github/workflows/*` build workflows to prevent duplicate CI billing. Keep independent lightweight repository/code review gates if useful.

## Release safety gates

- The **Apple Watch companion release** must remain disabled until `apps/watch_os/Sources` is integrated into `apps/mobile/ios` as a real embedded, correctly signed watch target and an iPhone/watch archive is verified.
- No workflow deploys or backs up personal health data. Firebase and Supabase credentials belong in scoped Codemagic groups; no debug `printenv`, secret echo or health records in CI artifacts/logs.
- Signed Android and Wear OS package identity, target API/permissions, store disclosures and physical-device tests precede production distribution.
- Before release, validate repository contracts, ObjectBox model UID changes, HealthKit/Health Connect permissions and consent/privacy tests.

## Validation

This template is checked for YAML parseability, known workflow IDs, project paths, manual-only triggers, absence of publishing credentials, and intentionally failing placeholders by `tool/test_codemagic_config.py`. **This test validates the template contract, not Codemagic's hosted build execution.**
