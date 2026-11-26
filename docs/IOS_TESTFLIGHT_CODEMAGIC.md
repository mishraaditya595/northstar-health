# iOS internal TestFlight upload on Codemagic

**Status:** source configuration only. The `mobile-ios-testflight` workflow has **not** run on hosted Codemagic, and no build has been uploaded to App Store Connect. An internal TestFlight build is a test channel, not a release: every gate in [RELEASE.md](RELEASE.md) still applies.

## What the job does

`mobile-ios-testflight` in the root `codemagic.yaml` is **manual only** (no `triggering` block). When started by hand it:

1. Checks that `SUPABASE_URL` is an `https://<ref>.supabase.co` URL and `SUPABASE_PUBLISHABLE_KEY` is a publishable key (`sb_publishable_…`). It never accepts a service-role or secret key.
2. Resolves the version name and build number (see [Version name and build number](#version-name-and-build-number)).
3. Runs `flutter pub get --enforce-lockfile`.
4. Applies App Store distribution signing for `in.beyondrep.app` (`xcode-project use-profiles`).
5. Builds a release IPA with `--build-name` and `--build-number` from step 2 and the two public Supabase values passed through a temporary `--dart-define-from-file` that is deleted after the build.
6. Uploads the IPA to App Store Connect with `submit_to_testflight: false` and `submit_to_app_store: false`. The build is therefore only available to **internal** testers on your App Store Connect team. It is never sent to Beta App Review, external testers or App Store review.

`Info.plist` declares `ITSAppUsesNonExemptEncryption = false`. The app only uses standard HTTPS/TLS via the OS and Supabase SDK. Re-check this declaration if any custom cryptography is added.

## One-time setup (owner)

### Apple

1. An active, paid Apple Developer Program membership.
2. In **Certificates, Identifiers & Profiles**, register the explicit App ID `in.beyondrep.app`. This bundle ID is permanent once the App Store Connect record exists. Enable the **HealthKit** capability on this App ID (the app now ships a HealthKit entitlement).
3. In **App Store Connect → Apps**, create the iOS app with that bundle ID, plus a name and SKU.
4. In **App Store Connect → Users and Access → Integrations → App Store Connect API**, create a Team key with the **App Manager** role. Download the `.p8` once. Note the Issuer ID and Key ID.
5. In **TestFlight → Internal Testing**, create a group, add yourself, and enable automatic distribution.

### Codemagic

1. Add `mishraaditya595/northstar-health` as a Codemagic app using **codemagic.yaml** configuration.
2. **Team settings → Integrations → Developer Portal → Manage keys:** add the API key with the exact name `Codemagic Signing`, which must match `integrations.app_store_connect` in the YAML.
3. **Team settings → codemagic.yaml settings → Code signing identities:**
   - **iOS certificates:** generate or upload an *Apple Distribution* certificate using the key above.
   - **iOS provisioning profiles:** fetch or create an *App Store* profile for `in.beyondrep.app`. After enabling HealthKit on the App ID, regenerate this App Store provisioning profile before the next run; a profile without the capability cannot sign the build.
4. **App → Environment variables:** create the group `ns_mobile_supabase_public` with:

   | Variable | Value |
   | --- | --- |
   | `SUPABASE_URL` | `https://<project-ref>.supabase.co` of the backend testers will use |
   | `SUPABASE_PUBLISHABLE_KEY` | that project's publishable key |

   Both values ship inside the app binary and are public by design. Mark them Secret anyway so they stay out of logs. **Never** put a service-role key, secret key, database password or access token in this group.

Never commit the `.p8`, certificates, provisioning profiles or `supabase.local.json` to Git.

## Before the first upload

The hosted Supabase project named in `SUPABASE_URL` must already have all committed migrations and the `delete-account` Edge Function, and its Auth email template must send a six-digit code. Otherwise testers cannot sign in or will hit missing RPCs. See [SUPABASE_CODEMAGIC_DEPLOY.md](SUPABASE_CODEMAGIC_DEPLOY.md) and the [P2-08 hosted release plan](implementation/phase-2/p2-08-hosted-release-plan.md).

## Version name and build number

**Start new build** shows two inputs. Both default to `AUTO`.

| Input | `AUTO` | Manual value |
| --- | --- | --- |
| `version_name` (shown to users, `CFBundleShortVersionString`) | the part before `+` of `version:` in `apps/mobile/pubspec.yaml` | one to three numbers separated by dots, such as `1.2.0` |
| `build_number` (`CFBundleVersion`) | the highest build of `in.beyondrep.app` in App Store Connect, across all versions, plus one | a whole number higher than that latest build |

`scripts/codemagic_ios_version.py` looks up the latest build with the Codemagic `app-store-connect` CLI (`apps list` by bundle ID, then `get-latest-testflight-build-number --all-versions`), using the `Codemagic Signing` integration. No extra variable or credential is needed. The step fails before the build starts if a value is malformed, a manual build number is not above the latest, or the lookup fails. It never falls back to Codemagic's `$BUILD_NUMBER`, which restarts at 1 if the workflow is renamed or the Codemagic app is recreated.

Don't start two `AUTO` runs at once, or a second run before App Store Connect lists the first upload: both would pick the same number and the later upload is rejected after the build.

The `+N` part of the pubspec version is not used for TestFlight builds. To change the default version name, bump `version:` in pubspec in a PR.

## Run

1. Codemagic → **Start new build** → branch `main` → workflow `mobile-ios-testflight`. Leave both inputs on `AUTO`, or set them as described above.
2. When the build finishes, App Store Connect processes the IPA (usually 5–30 minutes). Internal testers then get it in the TestFlight app.
3. Record the commit SHA, version name, build number (printed by the resolve step) and outcome in the P2-08 evidence before describing the build anywhere.

## Apple Watch app

The watch target is added to `Runner.xcodeproj` by `tool/embed_watch_target.rb` (see `apps/watch_os/README.md`); the sources stay in `apps/watch_os`. Owner steps:

1. In Apple Developer, create the App ID `in.beyondrep.app.watchkitapp` (you may tick HealthKit now; the watch does not use it until stage 4).
2. Run `mobile-ios-testflight` as above. Codemagic's automatic signing is expected to cover the watch App ID that extends the app's ID. **This is unverified until the first run.**
3. **If the build fails on watch signing**, create an App Store provisioning profile for `in.beyondrep.app.watchkitapp`, upload it to Codemagic code signing identities as `beyondrep_watch_app_store`, and change the job's `environment` to `ios_signing: provisioning_profiles: [beyondrep_app_store, beyondrep_watch_app_store]` with `certificates: [apple_distribution]` (the iPhone profile keeps its existing identity name). Reference profiles by name only; never commit them.
4. On the iPhone, install from TestFlight, open the Watch app, find BeyondRep and tap Install.

The watch app has no app icon yet; if App Store Connect rejects the upload for a missing watch icon, add an asset catalog to the watch target before the next run.

## Known limits

- The Health tab reads sleep, steps, resting heart rate and weight from HealthKit (read-only) and ships a HealthKit entitlement, so the App ID capability and regenerated profile above are required. It is not yet device-verified.
- The build embeds the BeyondRep Apple Watch app (`in.beyondrep.app.watchkitapp`), which shows a read-only glance of plans, readiness, sleep, resting heart rate, HRV and steps that the phone sends. It has no workout recording and no HealthKit access yet. It has never been installed on a watch, and signing it through this job is unverified until the first run (see "Apple Watch app" below).
- External TestFlight testing needs Beta App Review, a privacy policy URL and App Privacy answers. It is deliberately not enabled here.
