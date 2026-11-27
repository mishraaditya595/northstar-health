# iOS internal TestFlight upload on Codemagic

**Status:** source configuration only. The `mobile-ios-testflight` workflow has **not** run on hosted Codemagic, and no build has been uploaded to App Store Connect. An internal TestFlight build is a test channel, not a release: every gate in [RELEASE.md](RELEASE.md) still applies.

## What the job does

`mobile-ios-testflight` in the root `codemagic.yaml` is **manual only** (no `triggering` block). When started by hand it:

1. Checks that `SUPABASE_URL` is an `https://<ref>.supabase.co` URL and `SUPABASE_PUBLISHABLE_KEY` is a publishable key (`sb_publishable_…`). It never accepts a service-role or secret key.
2. Resolves the version name and build number (see [Version name and build number](#version-name-and-build-number)).
3. Runs `flutter pub get --enforce-lockfile`.
4. Applies the uploaded App Store profiles for `in.beyondrep.app` and the embedded watch app `in.beyondrep.app.watchkitapp` (`xcode-project use-profiles`), then checks the watch app has one.
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
   - **iOS certificates:** generate or upload an *Apple Distribution* certificate using the key above, with the reference name `Apple Distribution`. Both App Store profiles below must be made with this same certificate (in the Apple portal a profile holds one distribution certificate; Codemagic shows a green check on a profile whose certificate it holds).
   - **iOS provisioning profiles:** two *App Store* profiles, both made with that certificate: `in.beyondrep.app` with the reference name `beyondrep_app_store`, and `in.beyondrep.app.watchkitapp` with the reference name `beyondrep_watch_app_store`. After enabling HealthKit on an App ID, regenerate its profile before the next run; a profile without the capability cannot sign the build.
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

**Start new build** shows three inputs.

| Input | Default | Meaning |
| --- | --- | --- |
| `release_type` | `Fix or optimisation` | What kind of release this is. It decides the version name. |
| `version_name` | `AUTO` | Only for `Exact version`: a version such as `1.2.0`. Leave `AUTO` otherwise. |
| `build_number` | `AUTO` | `AUTO` is the highest build of `in.beyondrep.app` in App Store Connect, across all versions, plus one. A manual value must be a whole number above that build. |

Versions are `MAJOR.FEATURE.FIX`. The version name is `CFBundleShortVersionString`; the build number is `CFBundleVersion`.

| Release type | New version, from the current one `X.Y.Z` |
| --- | --- |
| `Fix or optimisation` | `X.Y.Z+1` |
| `Feature` | `X.Y+1.0` |
| `Major` | `X+1.0.0` |
| `Same version, new build` | `X.Y.Z` (a new build of the same version) |
| `Exact version` | `version_name`, which must not be below `X.Y.Z` |

The current version is the highest version found in:

- App Store Connect: TestFlight versions of the iOS app (every App Store build is first a TestFlight build; the App Store version list is not read because App Store Connect creates a placeholder `1.0` there).
- Google Play: release names with at least two dot-separated parts on every track, when the `ns_google_play` credentials are set and the lookup works.

If neither store has a version, the current version is `0.0.0`, so a fix gives `0.0.1`. The pubspec version is not read.

`ns_google_play` is optional for iOS. Without the Play credentials, iOS uses App Store Connect alone and prints a note. A failed Play lookup also prints a note (`Google Play not checked: ...`, never a credential) and the job goes on. Google Play never stops the iOS job. To keep iOS and Android on the same number for one release, run the second platform with `Same version, new build` after the first upload shows in its store (TestFlight processing can take a few minutes).

`scripts/codemagic_ios_version.py` uses the Codemagic `app-store-connect` CLI and the `Codemagic Signing` integration. No extra variable or credential is needed. The step prints one line, such as `Release type Fix or optimisation: 0.6.1 -> 0.6.2, build number 42`.

The step fails before the build starts when:

- The release type is empty or unknown.
- `version_name` is set but the type is not `Exact version`.
- `Exact version` has an invalid `version_name`, or one below the current version.
- `Same version, new build` finds no current version.
- A manual build number is malformed or not above the latest build.
- An App Store Connect lookup fails.

It never falls back to Codemagic's `$BUILD_NUMBER`, which restarts at 1 if the workflow is renamed or the Codemagic app is recreated.

Don't start two runs at once, or a second run before App Store Connect lists the first upload: both would pick the same build number and the later upload is rejected after the build.

## Run

1. Codemagic → **Start new build** → branch `main` → workflow `mobile-ios-testflight`. Pick a `release_type` and leave the other inputs on `AUTO`, or set them as described above.
2. When the build finishes, App Store Connect processes the IPA (usually 5–30 minutes). Internal testers then get it in the TestFlight app.
3. Record the commit SHA, version name, build number (printed by the resolve step) and outcome in the P2-08 evidence before describing the build anywhere.

## Apple Watch app

The watch target is added to `Runner.xcodeproj` by `tool/embed_watch_target.rb` (see `apps/watch_os/README.md`); the sources stay in `apps/watch_os`. Owner steps:

1. In Apple Developer, create the App ID `in.beyondrep.app.watchkitapp` (you may tick HealthKit now; the watch does not use it until stage 4).
2. In Apple Developer, create an **App Store** provisioning profile for `in.beyondrep.app.watchkitapp` with the Apple Distribution certificate, download it, and upload it in Codemagic code signing identities as `beyondrep_watch_app_store` (see setup step 3). Automatic signing with only `bundle_identifier: in.beyondrep.app` fetched no watch profile on the first run (2026-11-27), so the job lists both uploaded profiles by name. Never commit profiles.
3. Run `mobile-ios-testflight` as above. The step "Check the watch app has a signing profile" fails the build early, before the archive, if the export options have no profile for `in.beyondrep.app.watchkitapp`.
4. On the iPhone, install from TestFlight, open the Watch app, find BeyondRep and tap Install.

The watch target has an App Icon asset catalog (`apps/watch_os/Sources/Resources/Assets.xcassets`, the iPhone 1024 px icon, opaque), so a missing-icon rejection is not expected; whether App Store Connect accepts it is unverified until the first upload.

## Known limits

- The Health tab reads sleep, steps, resting heart rate and weight from HealthKit (read-only) and ships a HealthKit entitlement, so the App ID capability and regenerated profile above are required. It is not yet device-verified.
- The build embeds the BeyondRep Apple Watch app (`in.beyondrep.app.watchkitapp`), which shows a read-only glance of plans, readiness, sleep, resting heart rate, HRV and steps that the phone sends. It has no workout recording and no HealthKit access yet. It has never been installed on a watch, and signing it through this job is unverified until the first run (see "Apple Watch app" below).
- External TestFlight testing needs Beta App Review, a privacy policy URL and App Privacy answers. It is deliberately not enabled here.
