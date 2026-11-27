# Release-type versioning for the manual store jobs (design)

Status: proposed, 2026-11-27. Size: small change (short design).

## Why

On the manual Codemagic store jobs ("MANUAL - Mobile iOS - TestFlight internal upload" and "MANUAL - Mobile Android - Play release AAB") the owner types a version name, or leaves `AUTO`, which reads `version:` from `apps/mobile/pubspec.yaml`. Pubspec still says `0.1.0` while the TestFlight builds are at `0.6.x`, so `AUTO` is never right and every release means working out the next number by hand. The owner wants to pick **what kind of release this is** and let the job work out the number, as `MAJOR.FEATURE.FIX`.

## Goals

- A dropdown on both job forms: the release type.
- The job finds the current version, bumps it according to the type, and builds with it.
- iOS and Android stay on the same version number.
- An exact version can still be typed when needed.

## Non-goals

- No change to build numbers: iOS stays "latest App Store Connect build + 1", Android stays "latest Play versionCode + 1" (PR #56, PR #78, #49).
- No commit, tag or push from CI. Pubspec is no longer read by these jobs and is not updated by them.
- No automatic triggers, and no new secrets, groups or integrations.

## Anti-goals

- A build that silently reuses or goes backwards on a version because a store lookup failed. A failed lookup stops the job before the build.
- iOS and Android drifting onto different numbers for the same release.

## Approaches considered

| | Approach | Trade-off |
|---|---|---|
| **A (picked)** | Read the highest version already in App Store Connect and Google Play, bump the higher one | No commit, no new secret. Depends on two store lookups; a build stops early if one fails. |
| B | Bump the pubspec version | CI cannot push to `main`, so pubspec still has to be bumped in a PR before each release: the chore this removes. |
| C | A git tag per release, bumped and pushed by the job | One history in GitHub, but Codemagic needs a token that can write to this public repo. |

The owner picked A on 2026-11-27, and agreed to a "same version, new build" option.

## Design

### Form inputs (both jobs)

- `release_type`, `type: choice`. Options in this order:
  - `Fix or optimisation` bumps the last number: 0.6.1 → 0.6.2
  - `Feature` bumps the middle number and resets the last: 0.6.1 → 0.7.0
  - `Major` bumps the first number and resets the rest: 0.6.1 → 1.0.0
  - `Same version, new build` reuses the current version, for re-uploading during testing. It fails if no version exists yet.
  - `Exact version` uses `version_name` as typed
- `version_name` stays as a string with default `AUTO`. It is read only when `release_type` is `Exact version`, and then it must be a real version, not `AUTO`. If it is anything other than `AUTO` with another release type, the job fails, so a typed number is never silently ignored.
- `build_number` (and the Android `play_track`) are unchanged.

*Builder's call:* the default is `Fix or optimisation`. That's the most common release, and a wasted version number costs nothing.

### Finding the current version

The current version is the highest version, compared number by number, across:

1. **App Store Connect:** the TestFlight versions (`app-store-connect apps pre-release-versions <app_id> --json`) for `in.beyondrep.app`, with the app id found the way the build-number lookup already finds it.
2. **Google Play:** the release names on every track (`google-play tracks list --package-name in.beyondrep.app --json`). A release name that is not a version, or has only one part (`3`), is ignored.

A version with one or two numbers is read as three (`0.6` is `0.6.0`). If neither store has any version, the current version is `0.0.0`.

Wiring, using only what Codemagic already has:
- The iOS job adds the existing `ns_google_play` group (Play read access).
- The Android job adds the existing `integrations: app_store_connect: Codemagic Signing`.
- The Android upload step passes `--release-name "$BEYONDREP_VERSION_NAME"`, so every Play release from now on is named by its version and can be read back.

Failure rules:
- An App Store Connect lookup failure always stops the job.
- In Google Play, if the app has no releases yet (true until Android's first upload by hand), Play contributes nothing. Any other Play failure (bad credentials, network) stops the job.
- The existing exception stays: the Android first build (`play_track: none`, manual build number, no Play credentials) may skip the Play lookup, so App Store Connect alone decides the version.

Revised after final review:
- App Store versions are not read. App Store Connect auto-creates an App Store version `1.0` in PREPARE_FOR_SUBMISSION, which would make every current version 1.0.0. Every App Store build is first a TestFlight build, so TestFlight alone is enough.
- Google Play is optional on iOS, always: missing credentials or a failed lookup print a note and iOS uses App Store Connect alone. Android still requires Play, except for the first build.

### Exact versions

An exact version must be one to three numbers, using the existing `VERSION_NAME` rule. It must not be lower than the current version, so a typed number can't go backwards. Being equal to it is allowed, and behaves like "Same version, new build".

### Output

The resolve step prints one line, such as `Release type Feature: 0.6.1 -> 0.7.0, build number 43`. It writes `BEYONDREP_VERSION_NAME` and `BEYONDREP_BUILD_NUMBER` to `$CM_ENV` exactly as today, so the build steps don't change.

## Changed files (expected)

- `scripts/codemagic_ios_version.py`, `scripts/codemagic_android_version.py`: the store version lookups and the bump. Where the shared code lives (a new `scripts/codemagic_release_version.py` or the existing iOS module) is the builder's call.
- `codemagic.yaml`: the `release_type` input, `NS_RELEASE_TYPE`, the iOS group, the Android integration and `--release-name`.
- `tool/test_codemagic_ios_version.py`, `tool/test_codemagic_android_version.py`, `tool/test_codemagic_config.py`: TDD with the store CLIs faked. Cover every release type, multi-store max, 1- and 2-part versions, ignored non-version Play names, empty stores, lookup failures, exact lower/equal/invalid, and `version_name` set with a non-exact type.
- `docs/IOS_TESTFLIGHT_CODEMAGIC.md`, `docs/ANDROID_PLAY_CODEMAGIC.md`: the new form and how the version is found.

## Left to the builder (verify, don't assume)

- The exact JSON shape of `pre-release-versions`, `app-store-versions` and `tracks list` (codemagic-cli-tools 0.73 has all three commands). Check it against the library's resource models, not memory.
- Which error `tracks list` gives for an app with no releases, so it can be told apart from an auth failure.
- How Codemagic shows choice labels that contain spaces and commas. If it mangles them, use short values (`fix`, `feature`, `major`, `same`, `exact`) with a description that explains them.

## Verification

Local: `python3 -m unittest discover -s tool -p 'test_*.py'`. Hosted: the first real run of each job is the only end-to-end check. Record the printed resolve line in the release evidence, as today.
