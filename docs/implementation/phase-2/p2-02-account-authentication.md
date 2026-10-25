# Phase 2 / P2-02 — Mandatory Flutter authentication and account-local gate

**Status:** PR implementation under review; not deployed or released.
**Authoritative policy:** [ADR-0005](../../adr/0005-mandatory-auth-and-workout-sync.md). P2-01's Supabase RPC and RLS remain unchanged. Only **completed** phone workouts will synchronize in P2-03/P2-04; in-progress, paused and discarded logs remain local.

## Implemented in this milestone

- **No guest mode.** The Flutter entry point initializes Supabase Auth before mounting any workout routes or opening ObjectBox. Failure to load secure storage, missing build-time public config, or no trusted account shows an auth/error screen, not the workout app.
- **Online first authentication.** An email OTP flow provides signup/sign-in and verification. OTPs never reach logs/telemetry. After successful verification, persist a *trusted account UUID* in OS secure storage; only after persistence succeeds does workout UI become available.
- **Returning offline use.** For a previously verified device/account, a securely persisted account binding permits access to **only that same account's local ObjectBox partition** even when token refresh cannot connect. Per ADR-0005 this also holds when Supabase drops a session whose refresh token was rejected; cloud transfer must re-authenticate first. A corrupt stored binding counts as no binding (sign-in shown, no data deleted); an unreadable secure store shows a retryable error. Network and valid JWT remain required before any Supabase upload. Offline trust means access to this device's prior local data, not authorization on the server.
- **Account partitioning.** Open ObjectBox only at `<default ObjectBox directory>/northstar_accounts/<verified UUID>`, distinct from the pre-Phase-2 local root database and any other account's directory. User-entered strings are never used to build the path. Secure session and trusted-account storage keys are also namespaced by Supabase host, keeping dev and production separate. Legacy root workouts are deliberately quarantined; there is no guest migration or silent assignment.
- **Security.** Supabase's session JSON (including refresh/access tokens) is stored in Keychain on iOS and encrypted native storage on Android using `flutter_secure_storage`. The auth grant is separately protected. iOS items use `first_unlock_this_device`, so a refresh while the screen is locked still persists and items stay out of device backups. Do not use SharedPreferences for auth tokens. Neither credentials nor health/workout data go to analytics or logs.
- **Sign-out.** User sign-out first deletes the trusted binding, then removes workout UI and closes its ObjectBox store, then performs local Supabase sign-out; failure to delete the secure binding fails closed and is reported on the Today screen. An offline server revoke is not a failure: Supabase removes its local session first.
- **Responsive design.** Email-code sign-in is accessible on phone and tablet, with themed light/dark surfaces and active/completed backup disclosure. Guest deep links and navigation never enter the workout widget tree.
- **Testing.** Unit/widget tests simulate fresh install, missing authorization, email normalization/OTP, returning offline access, rejected refresh, corrupt binding, binding write failure, offline sign-out, cross-account mismatch, anonymous-account rejection, secure clear failure, sign-out locking, and traversal/untrusted identifier rejection.

## Required configuration (public settings only)

The application requires **public** build-time values:

```bash
flutter run \
  --dart-define=SUPABASE_URL=https://YOUR-PROJECT.supabase.co \
  --dart-define=SUPABASE_PUBLISHABLE_KEY=sb_publishable_YOUR_PUBLIC_KEY
```

Only the **public URL/publishable key** are expected. These values can be extracted from the compiled binary, so they are not authorization secrets. They may be set as ordinary Codemagic build environment variables and passed using `--dart-define`. **Never** use Supabase secret/service-role keys, access tokens, database credentials or personal API tokens as Flutter compile-time settings or GitHub/Codemagic generated source.

**Supabase Email OTP prerequisite:** In the project Supabase Dashboard, Email Auth must be enabled; the Magic Link email template must include `{{ .Token }}` to deliver a six-digit code. Default template may send a click-through link instead of an OTP. Configure redirect/rate-limits, custom SMTP and signup rules for production separately. No production email template change is made by this PR.

iOS needs no Keychain Sharing entitlement (no shared access group). Android declares `INTERNET` and keeps Flutter's default minimum SDK (24 in Flutter 3.47.7), which matches `flutter_secure_storage` 11.2.0's own floor. Android auto backup stays disabled. Real iOS provisioning and Android device tests remain required.

## Explicit non-goals / remaining gates

- **No cloud sync implementation yet:** logging repositories/outbox, sync queue, server upload and remote restore are P2-03 onward. P2-01 restricts the server to completed workouts only.
- The authentication gate does not migrate any existing root ObjectBox workout: there is no production guest data according to ADR-0005. If beta users have data, investigate before release, never silently assign it.
- **P2-03 gate:** the controller does not yet listen to `onAuthStateChange`, so a revocation while the app runs is not observed. Before any upload, add that listener and an explicit "session expired, backup paused" state.
- Online revocation/account deletion and refreshed server sessions must be reconciled before privileged cloud operations. Prior offline trust is limited to the already bound account's local partition, not remote access; full device-loss/revocation policy needs release review.
- A cloud-down OTP attempt cannot establish a *new* offline account; correct behavior is blocked with retry.
- Pending local changes and account switching need additional UX/guarding in P2-03 and later, including a sign-out confirmation that warns about an in-progress session (needs the design-kit dialog).
- iOS Keychain items survive an uninstall, so a reinstall restores the binding and session; a first-run reset is a release gate.
- Sign-in uses raw `TextField`; switch to the design-kit input when this branch is rebased onto the kit.
- Account deletion, data export, privacy policy links, legal retention obligations, native smoke tests, iOS signing and final device secure storage validation remain release gates.
- CI must confirm Dart formatting, `flutter analyze`, `flutter test`, `flutter pub get --enforce-lockfile` and Android build; ensure auto-resolved dependency lockfile is committed. Do not merge without an independent review.

## Rollback

Revert P2-02 UI entry/auth changes without touching local account-partitioned ObjectBox files or secrets; do not repoint a previous shared ObjectBox Store to an arbitrary account. On sign-out/storage failure, fail closed rather than deleting user data. Never ship a fallback guest login.
