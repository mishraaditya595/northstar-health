# iOS internal TestFlight upload on Codemagic

**Status:** source configuration only. The `mobile-ios-testflight` workflow has **not** run on hosted Codemagic, and no build has been uploaded to App Store Connect. An internal TestFlight build is a test channel, not a release: every gate in [RELEASE.md](RELEASE.md) still applies.

## What the job does

`mobile-ios-testflight` in the root `codemagic.yaml` is **manual only** (no `triggering` block). When started by hand it:

1. Checks that `SUPABASE_URL` is an `https://<ref>.supabase.co` URL and `SUPABASE_PUBLISHABLE_KEY` is a publishable key (`sb_publishable_…`). It never accepts a service-role or secret key.
2. Runs `flutter pub get --enforce-lockfile`.
3. Applies App Store distribution signing for `in.beyondrep.app` (`xcode-project use-profiles`).
4. Builds a release IPA with `--build-number=$BUILD_NUMBER` and the two public Supabase values passed through a temporary `--dart-define-from-file` that is deleted after the build.
5. Uploads the IPA to App Store Connect with `submit_to_testflight: false` and `submit_to_app_store: false`. The build is therefore only available to **internal** testers on your App Store Connect team. It is never sent to Beta App Review, external testers or App Store review.

`Info.plist` declares `ITSAppUsesNonExemptEncryption = false`. The app only uses standard HTTPS/TLS via the OS and Supabase SDK. Re-check this declaration if any custom cryptography is added.

## One-time setup (owner)

### Apple

1. An active, paid Apple Developer Program membership.
2. In **Certificates, Identifiers & Profiles**, register the explicit App ID `in.beyondrep.app`. This bundle ID is permanent once the App Store Connect record exists.
3. In **App Store Connect → Apps**, create the iOS app with that bundle ID, plus a name and SKU.
4. In **App Store Connect → Users and Access → Integrations → App Store Connect API**, create a Team key with the **App Manager** role. Download the `.p8` once. Note the Issuer ID and Key ID.
5. In **TestFlight → Internal Testing**, create a group, add yourself, and enable automatic distribution.

### Codemagic

1. Add `mishraaditya595/northstar-health` as a Codemagic app using **codemagic.yaml** configuration.
2. **Team settings → Integrations → Developer Portal → Manage keys:** add the API key with the exact name `BeyondRep App Store Connect`, which must match `integrations.app_store_connect` in the YAML.
3. **Team settings → codemagic.yaml settings → Code signing identities:**
   - **iOS certificates:** generate or upload an *Apple Distribution* certificate using the key above.
   - **iOS provisioning profiles:** fetch or create an *App Store* profile for `in.beyondrep.app`.
4. **App → Environment variables:** create the group `ns_mobile_supabase_public` with:

   | Variable | Value |
   | --- | --- |
   | `SUPABASE_URL` | `https://<project-ref>.supabase.co` of the backend testers will use |
   | `SUPABASE_PUBLISHABLE_KEY` | that project's publishable key |

   Both values ship inside the app binary and are public by design. Mark them Secret anyway so they stay out of logs. **Never** put a service-role key, secret key, database password or access token in this group.

Never commit the `.p8`, certificates, provisioning profiles or `supabase.local.json` to Git.

## Before the first upload

The hosted Supabase project named in `SUPABASE_URL` must already have all committed migrations and the `delete-account` Edge Function, and its Auth email template must send a six-digit code. Otherwise testers cannot sign in or will hit missing RPCs. See [SUPABASE_CODEMAGIC_DEPLOY.md](SUPABASE_CODEMAGIC_DEPLOY.md) and the [P2-08 hosted release plan](implementation/phase-2/p2-08-hosted-release-plan.md).

## Run

1. Codemagic → **Start new build** → branch `main` → workflow `mobile-ios-testflight`.
2. When the build finishes, App Store Connect processes the IPA (usually 5–30 minutes). Internal testers then get it in the TestFlight app.
3. Record the commit SHA, Codemagic build number and outcome in the P2-08 evidence before describing the build anywhere.

## Known limits

- The Health tab shows fictional demo data. HealthKit is not implemented, so the app requests no HealthKit entitlement.
- No Apple Watch companion is embedded.
- External TestFlight testing needs Beta App Review, a privacy policy URL and App Privacy answers. It is deliberately not enabled here.
