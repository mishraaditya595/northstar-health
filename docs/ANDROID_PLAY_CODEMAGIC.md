# Android Google Play release on Codemagic

**Status:** source configuration only. The `mobile-android-release` workflow (phone and Wear OS bundles) has **not** run on hosted Codemagic, no release AAB has been built with the upload key, and nothing has been uploaded to Google Play. A draft on a testing track is not a release: every gate in [RELEASE.md](RELEASE.md) still applies.

## What the job does

`mobile-android-release` in the root `codemagic.yaml` is **manual only** (no `triggering` block). When started by hand it:

1. Checks that `SUPABASE_URL` is an `https://<ref>.supabase.co` URL and `SUPABASE_PUBLISHABLE_KEY` is a publishable key (`sb_publishable_…`).
2. Resolves the version name and versionCode (see [Version name and versionCode](#version-name-and-versioncode)).
3. Runs `flutter pub get --enforce-lockfile`.
4. Builds a release AAB with `--build-name`, `--build-number` and the two public Supabase values through a temporary `--dart-define-from-file`. `BEYONDREP_REQUIRE_RELEASE_SIGNING=true` makes Gradle fail if the upload key is missing, so the job can never fall back to the debug key.
5. Refuses the AAB if `keytool -printcert -jarfile` shows it unsigned or signed by `CN=Android Debug`.
6. Builds the Wear OS bundle from `apps/wear_os` with Gradle (`:app:bundleRelease`, Java 17), versionCode = the phone's + 1 and the same version name, signed with the same upload key, and refuses it if it is unsigned or debug-signed (see [Wear OS bundle](#wear-os-bundle)).
7. If the `play_track` input is `internal` or `alpha` (closed testing), uploads the phone AAB to that track and the Wear OS AAB to the Wear OS form-factor track of the same name (`wear:internal` or `wear:alpha`), both as **draft** releases with `google-play bundles publish --draft` and the same release name. Nothing reaches testers until you roll the drafts out in Play Console. `none` keeps the AABs as build artifacts only. Production is not an option.

The phone AAB, the R8 `mapping.txt` and the Wear OS AAB are kept as build artifacts.

## Wear OS bundle

The watch app (`apps/wear_os`) has the same application ID as the phone app, `in.beyondrep.app`, so Google Play shows one listing with a phone and a watch build, and the Wear Data Layer connects them (it only links apps with the same package name and signing certificate).

- **Signing:** `apps/wear_os/app/build.gradle.kts` signs `release` with the same upload key as the phone, from `apps/wear_os/key.properties` (gitignored) or the Codemagic `CM_KEYSTORE_*` variables, and fails when `BEYONDREP_REQUIRE_RELEASE_SIGNING=true` and none is set. Both builds use the same upload key, so Play App Signing gives them the same app signing key, which the Data Layer needs.
- **Version codes:** the phone build gets `N` and the watch build `N + 1` (`BEYONDREP_WATCH_BUILD_NUMBER`, passed to Gradle as `-Pbeyondrep.versionCode`; `-Pbeyondrep.versionName` is the shared version name). Play requires distinct codes in one listing. The next `AUTO` build is above the highest bundle Play has, phone or watch.
- **Tracks:** the watch bundle goes to `wear:<play_track>`. The Codemagic `google-play` CLI passes the track name to the Play API unchanged; whether Play accepts `wear:internal` for this app has **not** been exercised and is checked on the first run.

Owner steps in Play Console, outside Git:

1. Add the **Wear OS** form factor to the app (**Test and release → Advanced settings → Form factors**) and accept the Wear OS requirements.
2. Opt in to Wear OS testing tracks and add the testers (the watch's Google account) to the internal or closed track.
3. Roll out the phone draft and the Wear OS draft, then install the phone app from the Play Store and the watch app from the Play Store on the watch (or from the phone's Play Store listing, **Install on watch**).

## Release signing in Gradle

`apps/mobile/android/app/build.gradle.kts` signs `release` builds with the **upload key** from, in this order:

1. `apps/mobile/android/key.properties` (gitignored, for local builds) with `storeFile`, `storePassword`, `keyAlias` and `keyPassword`. A relative `storeFile` is resolved from `apps/mobile/android/app/`. An incomplete file fails the build.
2. Codemagic's `android_signing` variables `CM_KEYSTORE_PATH`, `CM_KEYSTORE_PASSWORD`, `CM_KEY_ALIAS` and `CM_KEY_PASSWORD`.

With neither, release builds use the debug key so `flutter run --release` keeps working, unless `BEYONDREP_REQUIRE_RELEASE_SIGNING=true`. Never commit a keystore or `key.properties`; `.gitignore` and `tool/test_repository_layout.py` block them.

With **Play App Signing**, Google holds the app signing key and this upload key only proves uploads come from you. If the upload key is lost, Play Console support can reset it.

## Health Connect rationale screen

`PermissionsRationaleActivity` handles `androidx.health.ACTION_SHOW_PERMISSIONS_RATIONALE` (Android 13 and lower) and is the target of the `ViewPermissionUsageActivity` alias (Android 14+). It opens `https://beyondrep.in/privacy` in the browser and closes; without a browser it opens the app. Play requires this to be the same policy as the store listing's privacy policy URL (issue #52).

## One-time setup (owner)

### Google Play Console

1. Create the app with package `in.beyondrep.app` (the package name is permanent once a bundle is uploaded).
2. Create a Google Cloud service account with a JSON key, then in **Play Console → Users and permissions** invite its email with the **View app information** and **Release to testing tracks** permissions for this app. Keep the JSON out of Git.
3. Upload the **first** AAB by hand (Google Play rejects API uploads for an app that has never had one): run the job with `build_number` `1` and `play_track` `none`, download `app-release.aab` from the build artifacts, and upload it to the internal testing track in Play Console. Accept Play App Signing when asked.

### Codemagic

1. **Team settings → codemagic.yaml settings → Code signing identities → Android keystores:** upload the upload keystore with the reference name `beyondrep_upload`, which must match `android_signing` in the YAML, plus its passwords and alias.
2. **App → Environment variables:**
   - `ns_mobile_supabase_public` (shared with the iOS job): `SUPABASE_URL` and `SUPABASE_PUBLISHABLE_KEY`.
   - `ns_google_play`: `GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS`, the full service account JSON, marked **Secure**.

## Version name and versionCode

`scripts/codemagic_android_version.py` mirrors the iOS resolver (issue #49). **Start new build** shows four inputs.

| Input | Default | Meaning |
| --- | --- | --- |
| `release_type` | `Fix or optimisation` | What kind of release this is. It decides the version name. |
| `version_name` | `AUTO` | Only for `Exact version`: a version such as `1.2.0`. Leave `AUTO` otherwise. |
| `build_number` | `AUTO` | `AUTO` is the highest versionCode Google Play has for `in.beyondrep.app` (all tracks and uploaded bundles) plus one. A manual number must be higher than that. |
| `play_track` | `none` | `none`, `internal` or `alpha`. |

Versions are `MAJOR.FEATURE.FIX`. The version name is `versionName`; the build number is `versionCode`.

| Release type | New version, from the current one `X.Y.Z` |
| --- | --- |
| `Fix or optimisation` | `X.Y.Z+1` |
| `Feature` | `X.Y+1.0` |
| `Major` | `X+1.0.0` |
| `Same version, new build` | `X.Y.Z` (a new build of the same version) |
| `Exact version` | `version_name`, which must not be below `X.Y.Z` |

The current version is the highest version found in:

- Google Play: every release name on every track that has at least two dot-separated parts (a name such as `3` is ignored).
- App Store Connect: TestFlight versions of the iOS app (every App Store build is first a TestFlight build; the App Store version list is not read because of its placeholder `1.0`).

If neither store has a version, the current version is `0.0.0`, so a fix gives `0.0.1`. The pubspec version is not read.

The job uses the existing `Codemagic Signing` App Store Connect integration to read the iOS versions. No new credential is needed. An App Store Connect lookup failure stops the job. To keep iOS and Android on the same number for one release, run the second platform with `Same version, new build` after the first upload shows in its store (TestFlight processing can take a few minutes).

The Play release name is now the version, such as `0.6.2`. The upload step passes it with `--release-name`. Release names that are not a version are ignored when the current version is worked out.

The step prints one line, such as `Release type Fix or optimisation: 0.6.1 -> 0.6.2, build number 42, watch build number 43`.

The step fails before the build starts when:

- `version_name` is set but the type is not `Exact version`.
- `Exact version` has an invalid `version_name`, or one below the current version.
- `Same version, new build` finds no current version.
- A manual build number is malformed or not above the latest Play build.
- An App Store Connect lookup fails.
- A Google Play lookup fails, except on the first build below.

Only a manual `build_number` with `play_track` `none` may go on without Play credentials or when a Play lookup fails. That is the first build in step 3 above.

Tested offline by `tool/test_codemagic_android_version.py` against stub CLIs.

## Not covered

- Promoting a release to production. Personal Play developer accounts created after 13 November 2023 must first run a closed test with at least 12 testers opted in for 14 days, then apply for production access in Play Console.
- The Health apps declaration and Data safety form in Play Console.
- Device testing of the release build (R8, Health Connect permissions, the rationale screen, workout export).
