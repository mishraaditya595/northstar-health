# NorthStar Codemagic CI/CD and manual Supabase deployments

**Status:** The original 11 app/watch workflows remain intentionally failing, manual templates. Two additional **manual Supabase workflows** handle database migrations and selected Edge Functions via build inputs, using a private Codemagic group bound to a single target project. None has been run on hosted Codemagic or used to deploy a database. See [Supabase Codemagic deployment runbook](SUPABASE_CODEMAGIC_DEPLOY.md). No mobile build, signing or store release is enabled.

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

### Why the original 11 mobile/watch templates intentionally exit with failure

Codemagic's manual Start new build can select a workflow even without an automatic `triggering` block. If a workflow only printed “hello,” it might be marked successful without compiling anything. Each app/watch stub prints **TEMPLATE ONLY** and `exit 1` to prevent false release confidence. Replace these guards with validated build commands and artifacts before claiming an app build. There is no app `publishing`, signing or credential group. **The two Supabase workflows are different:** they use a project-bound protected Codemagic group and can write only after an explicit `deploy` input and exact project-ref confirmation. See [operator guide](SUPABASE_CODEMAGIC_DEPLOY.md); never trigger them automatically.

## Manual Supabase workflows

`supabase-database` and `supabase-functions` live in the same root YAML. Both are manually started on `main` with build inputs (`preview` or `deploy`, exact project-ref and full reviewed HEAD SHA confirmation for writes and, for Functions, explicitly entered space-separated names). Function selection is empty by default; `delete-account` is never preselected. Both reuse `scripts/codemagic_supabase.sh` and the `ns_supabase_deploy` group, configured for only one project per Codemagic app. Production must use separately isolated credentials, not import staging and production secrets together. All credentials remain in encrypted Codemagic settings, not Git. See [complete setup, procedures, failure and rollback guidance](SUPABASE_CODEMAGIC_DEPLOY.md).

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
- Only the two explicitly manual Supabase workflows can deploy backend schema/Function code; no workflow exports or backs up personal health records. Firebase and Supabase credentials belong in scoped Codemagic groups; never print environment variables, secret values or health records in CI artifacts/logs.
- Signed Android and Wear OS package identity, target API/permissions, store disclosures and physical-device tests precede production distribution.
- Before release, validate repository contracts, ObjectBox model UID changes, HealthKit/Health Connect permissions and consent/privacy tests.

## Validation

The existing templates and new deployment definitions are checked by `tool/test_codemagic_config.py`; the deployment shell is exercised against a stub CLI in `tool/test_codemagic_supabase.py`. These are offline configuration/unit tests and **do not demonstrate a Codemagic hosted deployment or data-security acceptance**.
