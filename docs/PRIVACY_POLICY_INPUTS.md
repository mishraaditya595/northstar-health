# Privacy policy inputs

**Status:** inventory for [issue #52](https://github.com/mishraaditya595/northstar-health/issues/52), audited against `main` at `0d69b0a` (2026-11-24) and the Phase 3 health-reads branch (`claude/project-thread-0kmghd`, ADR-0008). This is **not** the published policy and not legal advice. It lists every fact the privacy policy, the account-deletion page and the store privacy forms need, where each fact comes from in the code, and the decisions still open.

Rules for whoever writes the policy from this:

- Describe the build being shipped, not the roadmap. Section 4 marks each data flow as **Shipped (main)**, **Phase 3 branch** or **Planned**. Only include Phase 3 health reads once that branch is merged and in the build being submitted.
- Keep the hosted project ref/URL, keys and personal contact details out of this repo (see `AGENTS.md`, "Secrets in a public repository"). Use placeholders here; put real values only on the published page.

## 1. Who and what

| Item | Value / source |
| --- | --- |
| App name | BeyondRep |
| App ID | `in.beyondrep.app` (iOS and Android) |
| Policy URL (proposed) | `https://beyondrep.in/privacy` |
| Deletion page URL (proposed) | `https://beyondrep.in/delete-account` |
| Data controller | **Open:** Adi as an individual, or a business entity. Policy must name it and give a postal country. |
| Contact for privacy requests | **Open:** a dedicated address such as `privacy@beyondrep.in` (do not commit a personal email). |
| Platforms | iPhone/iPad (iOS), Android phone/tablet. Watch apps are not shipped and collect nothing. |

## 2. Data inventory

### 2.1 Account and sign-in (Shipped, main)

Sign-in is mandatory, by email one-time code only (no passwords, no social login). `apps/mobile/lib/features/account/account_auth_controller.dart` calls Supabase `signInWithOtp` (`shouldCreateUser: true` for sign-up, `false` for sign-in, account recovery and deletion re-verification).

| Data | Where it lives | Notes for the policy |
| --- | --- | --- |
| Email address | Supabase Auth (`auth.users`) | Required to create the account and to receive codes. Not used for marketing. |
| Account ID (UUID) | Supabase Auth; on device in the OS secure store | Internal identifier; ties workouts to the account. |
| One-time sign-in code | Supabase Auth (hashed), sent by email through Brevo SMTP | 6 digits, expiry set to 600 s in the dashboard. |
| Session/refresh tokens | Supabase Auth; on device in Keychain (iOS, `first_unlock_this_device`) / Android Keystore-backed `flutter_secure_storage` | Never stored in ObjectBox or app files. |
| Auth timestamps (created, confirmed, last sign-in) | Supabase Auth | Standard Supabase fields. |
| IP address and user agent of sign-in requests | Supabase Auth `auth.sessions` and `auth.audit_log_entries`; Supabase platform/API logs | Collected by the platform, not by app code. Used for security/abuse prevention. **Must be disclosed.** See open question Q3 on retention after deletion. |

The app does not collect name, phone number, date of birth, photo, contacts, location, advertising ID or any device identifier.

### 2.2 Workout data synced to the cloud (Shipped, main)

Only **completed** workouts are uploaded (ADR-0005, `docs/CLOUD_SYNC.md`). The server accepts exactly these payload keys (allow-list in `supabase/migrations/20261025090000_phase2_completed_only_scope.sql` and later):

- Workout: `workout_id`, `origin`, `status`, `name` (free text), `started_at_utc`, `completed_at_utc`, `original_offset_minutes` (the device's UTC offset at start, so it reveals a time zone), `schema_version`.
- Exercise: `id`, `name` (free text), `position`, `muscle`, `equipment`.
- Set: `id`, `position`, `kind`, `status`, `reps`, `load_grams`, `input_unit`, `rpe`, `completed_at_utc`.

Server tables (`public.workout_records`, `public.workout_sync_operations`, `northstar_private.workout_owner_cursors`) also hold revision numbers, change sequence numbers, a deletion tombstone (`deleted_at`) and derived totals (working sets, loaded volume) per workout. Row-level security limits every row to its owner.

**Never uploaded** (enforced by the allow-list and client code): in-progress, paused and discarded sessions; rest-timer and checkpoint state; custom plans and templates (including plan exercise notes, the only free-text notes field in the app); the exercise catalog; theme preference; any health platform data.

Policy wording should mention that workout and exercise **names are free text**, so users should not put sensitive information in them.

### 2.3 Sync receipts (Shipped, main)

`public.workout_sync_operations` keeps an idempotency receipt per upload: operation ID, workout ID, expected/applied revision, action, a SHA-256 hash of the request (no plaintext payload) and timestamps. Each expires 90 days after commit (`expires_at`), is pruned on the owner's next sync and by a daily pg_cron job at 03:17 UTC (`20261124120000_p2_08_schedule_receipt_prune.sql`).

### 2.4 Data stored only on the device (Shipped, main)

| Data | Store | Protection |
| --- | --- | --- |
| All workouts (including unfinished), plans, exercise catalog, rest/checkpoint state, sync outbox (pending payloads), restore cursors | ObjectBox, one directory per account | iOS: excluded from iCloud/iTunes backup, `completeUntilFirstUserAuthentication` file protection (`ios/Runner/AppDelegate.swift`). Android: `allowBackup="false"`, cloud backup and device transfer excluded (`res/xml/data_extraction_rules.xml`). Not app-level encrypted beyond OS file encryption. |
| Session token, bound account ID, deletion-recovery markers | `flutter_secure_storage` (Keychain / Keystore) | See 2.1. Note: iOS Keychain items can survive an app uninstall/reinstall (finding from the P2-08 review). |
| Appearance (light/dark) | `shared_preferences` | Not personal data. |

Another account on the same phone cannot open a different account's ObjectBox directory.

### 2.5 Workout export file (Shipped, main)

Account > export writes all of the user's cloud workouts as `beyondrep-workouts.json` and hands it to the OS save dialog (`workout_export_file_writer.dart`, `saveFile` channel). The file goes wherever the user saves it; BeyondRep does not upload it anywhere. This is the policy's **access/portability** mechanism.

### 2.6 Health platform reads (Phase 3 branch, not on main)

From ADR-0008 and the branch diff:

| Item | Detail |
| --- | --- |
| Types read | Sleep (asleep stages, last night), steps (today), resting heart rate (newest in 7 days), weight (newest in 30 days). Read only; nothing is written to Apple Health or Health Connect. |
| Sources | Apple HealthKit (iOS), Google Health Connect (Android 9+), via the `health` 14.0.0 package. |
| Permissions | iOS: HealthKit entitlement, `NSHealthShareUsageDescription` ("BeyondRep reads your sleep, steps, resting heart rate and weight to show a daily summary. This data stays on your phone."), no update/write description. Android: `READ_SLEEP`, `READ_STEPS`, `READ_RESTING_HEART_RATE`, `READ_WEIGHT`; no `READ_HEALTH_DATA_HISTORY`, no background read. |
| When asked | Only when the user taps Connect, never at sign-up. |
| Storage | Values are held in memory for the life of the app process only. **No health value is written to disk**, synced to Supabase, put in the outbox or export file, logged, or sent to any third party. A guard test enforces the import boundary. |
| What is stored | A per-account "connected" flag (`HealthConnectionEntity { id, connectedAt }`) in that account's ObjectBox directory. No health values. Removed on Disconnect and with the account's local data. |
| Revoking | Disconnect in the app removes the flag; OS access must be revoked in the Health app / Health Connect settings (the app cannot revoke it). |
| Purpose | Show a daily summary to the user. Not advice, not diagnosis, not advertising, not shared. |

Because health data is processed only on the device and never leaves it, it is generally **not "collected"** for the Apple and Google forms (section 6), but the policy text, the HealthKit and Health Connect rules still require it to be described (section 7).

### 2.7 Not present (say so in the policy)

- No analytics, crash reporting, advertising or attribution SDK. Firebase Crashlytics/Analytics is a decided future provider but **not integrated** (`docs/FIREBASE_PRIVACY.md`); adding it needs a policy update and consent.
- No tracking across apps or websites (no ATT prompt needed); no sale or sharing of personal data.
- No location, camera, microphone, contacts or photos access. The only Android permission on main is `INTERNET`.
- No payments or subscriptions.
- No server-side application logging in the `delete-account` function (no `console.*` calls).

## 3. Processors and other third parties

| Party | Role | Data it handles | Status |
| --- | --- | --- | --- |
| Supabase | Auth, Postgres database, Edge Function hosting | Email, account ID, tokens, IP/user agent, completed workouts, receipts | Shipped. Hosted region: AWS ap-south-1 (Mumbai, India). Free plan. |
| Brevo (Sendinblue) | Transactional SMTP for sign-in code emails | Email address, code email content, delivery/open logs held by Brevo | Shipped |
| Apple / Google | App distribution; HealthKit / Health Connect on device | Store-side data under their own policies; health data stays on the device | Shipped / Phase 3 |
| Cloudflare Turnstile | CAPTCHA on sign-in (issue #53) | IP address, browser/device signals for bot detection | **Planned.** Add to the policy in the same release that ships the app change. |
| Firebase (Google) | Crash reporting / analytics | Allow-listed, non-health events only | **Planned**, gated on privacy review |
| Codemagic, GitHub | Build and source hosting | No user data | Not a processor of user data; do not list as one |

Policy needs: each processor's name, purpose, and a link to its privacy policy / DPA. Supabase and Brevo DPAs should be accepted in their dashboards (**Open, Q5**).

## 4. Purposes and legal bases

| Purpose | Data | Suggested basis (GDPR wording) |
| --- | --- | --- |
| Create and secure the account, send sign-in codes | Email, account ID, tokens, IP/user agent | Contract (needed to provide the service); legitimate interest for abuse prevention |
| Back up and sync completed workouts across devices, server-side progress totals | Section 2.2 | Contract |
| Prevent duplicate uploads | Sync receipts | Contract |
| Show the daily health summary (Phase 3) | Section 2.6, on device only | Explicit consent via the OS permission prompt |

Under India's DPDP Act 2023 (the likely home jurisdiction, with a `.in` domain and Indian hosting), the equivalent is consent with a clear notice; the notice must list the data and purpose and say how to withdraw consent and complain. **Open, Q1** on which jurisdictions to target.

## 5. Retention and deletion

| Data | Retention |
| --- | --- |
| Completed workouts in the cloud | Until the user deletes the workout or the account |
| Deletion tombstones | Lifetime of the account (needed so other devices learn of the deletion) |
| Sync receipts | 90 days, purged daily |
| Auth user, sessions, refresh tokens, identities | Until account deletion (cascades in Supabase Auth) |
| Supabase `auth.audit_log_entries` (IP, actor email/ID) | **Not covered by the FK cascade.** Needs a decision and possibly a cleanup job (Q3) |
| Supabase platform/API logs | Per Supabase plan (verify; free plan retention is short) |
| Brevo email logs and contact record | Per Brevo settings (Q3) |
| On-device data | Until the account is deleted (local directory erased), or the app is uninstalled |
| Health readings (Phase 3) | Not retained; memory only |

**Account deletion (Shipped, main, PR #29):** in-app at Account > Delete account. The user sees a warning about unsynced data, is offered an export first, re-verifies with a fresh email code, and the `delete-account` Edge Function hard-deletes the Supabase Auth user. FK cascades remove `workout_records`, `workout_sync_operations` and `workout_owner_cursors`. The app then erases that account's local ObjectBox directory. Details and uncertain-outcome handling: `supabase/ACCOUNT_DELETION_RUNBOOK.md`. Database backups held by Supabase roll off per Supabase's backup window (free plan has no PITR; verify, Q3).

Deleting a single completed workout (history detail > Delete workout) uploads a tombstone that removes its contents from the cloud copy.

**Deletion web page (needed for Google Play):** explain the in-app path; give an off-app route (email to the privacy contact), verify identity by sending a code to the account email, state a response time (e.g. 30 days) and what is deleted vs. kept.

## 6. Store forms

### 6.1 App Store Connect, App Privacy

Draft carried over from the P2-08 security review, checked against the code:

| Apple data type | Collected | Linked to user | Tracking | Purpose |
| --- | --- | --- | --- | --- |
| Contact Info > Email Address | Yes | Yes | No | App Functionality |
| Health & Fitness > Fitness (completed workouts) | Yes | Yes | No | App Functionality |
| Identifiers > User ID (account UUID) | Yes | Yes | No | App Functionality |
| Health & Fitness > Health (Phase 3 HealthKit reads) | **No**: processed on device only, never sent off the device | n/a | n/a | n/a |
| Diagnostics, Usage Data, Location, Identifiers > Device ID | No | | | |

Also on iOS:

- **Privacy manifest:** there is no `PrivacyInfo.xcprivacy` in `ios/Runner`. Apple requires one for apps (and SDKs) using required-reason APIs; `shared_preferences` uses `UserDefaults`. Confirm the plugins ship their own manifests and add an app-level one before submission (**finding**).
- `ITSAppUsesNonExemptEncryption` is `false` on the Phase 3 branch (HTTPS only).
- Revisit the answers when Turnstile or Firebase ships (Turnstile likely adds "Other Diagnostic Data"/fraud prevention; Firebase adds Crash Data / Product Interaction).

### 6.2 Google Play, Data safety

| Google category > type | Collected | Shared | Optional | Purpose |
| --- | --- | --- | --- | --- |
| Personal info > Email address | Yes | No | Required | Account management, App functionality |
| Personal info > User IDs | Yes | No | Required | Account management, App functionality |
| Health and fitness > Fitness info | Yes | No | Required to use sync (sync is part of the account) | App functionality |
| Health and fitness > Health info (Phase 3) | **No**: on-device processing only | No | | |

Other answers: data encrypted in transit (HTTPS/TLS to Supabase); users can request deletion (in-app and web URL); no data shared with third parties (processors acting on our behalf are not "sharing" under Google's definition); not independently security-reviewed (MASA) unless that is done.

Play Console also needs: privacy policy URL, account deletion URL, and the **Health apps declaration** (Phase 3 build, see 7.2).

## 7. Health platform policy requirements (Phase 3)

### 7.1 Apple HealthKit (App Review Guidelines 5.1.1, 5.1.2, 5.1.3, 2.5.1)

The policy and the app must show that:

- HealthKit data is used only to provide the daily summary to the user, never for advertising, marketing, data mining or sold/shared with third parties.
- HealthKit data is not stored in iCloud (true: nothing is stored).
- The app has a privacy policy URL in App Store Connect and reachable inside the app (**Open, Q4**: there is no in-app link today).
- The UI clearly identifies the HealthKit functionality (Connect card on the Health tab).
- The app does not write false or inaccurate data (Phase 3 is read only).

### 7.2 Google Health Connect

- The privacy policy must describe the handling of each Health Connect data type and is linked from the Health Connect permission screen through the rationale intent / `ViewPermissionUsageActivity` alias. The branch currently opens the app there (`TODO(#52)` in `AndroidManifest.xml`); it must show the policy before release.
- Complete the Play Console **Health apps declaration** listing each permission (`READ_SLEEP`, `READ_STEPS`, `READ_RESTING_HEART_RATE`, `READ_WEIGHT`) with its justification.
- Follow the Health Connect **Limited Use** requirements: use only to provide the user-facing feature; no transfer except as needed for that feature, legal compliance or a merger; no ads; no human reading except with consent, for security or legal reasons. The policy should contain a Limited Use statement.
- Request only needed permissions (no history or background permissions requested).

## 8. User rights to describe

| Right | How it is met today |
| --- | --- |
| Access / portability | In-app JSON export of all cloud workouts (2.5) |
| Correction | Completed workouts cannot be edited after finishing; the user can delete one (history detail > Delete workout) and log it again. Email cannot be changed in-app (**Open, Q6**) |
| Deletion | In-app account deletion; delete a single workout; web page / email route |
| Withdraw health consent | Disconnect in-app plus OS Health settings (Phase 3) |
| Objection / complaint | Contact address; name the supervisory authority / Data Protection Board as applicable |

## 9. Other required policy sections

- **Security:** HTTPS to Supabase; row-level security per account; tokens in Keychain/Keystore; local data excluded from device backups; service-role keys only on the server.
- **International transfers:** data is hosted in India (Supabase ap-south-1); Brevo is EU-based; describe transfers if serving users outside India.
- **Children:** **Open, Q2.** DPDP treats under-18s as children and needs verifiable parental consent; GDPR digital consent age is 13-16; COPPA applies under 13. Simplest is to state the app is not for users under 18 (or 16) and set store age ratings accordingly.
- **Changes to the policy:** "last updated" date at the top; announce material changes in the app or by email before they take effect.
- **No medical advice:** the health summary is informational, not diagnosis (also matches ADR-0008).

## 10. Open questions for Adi

1. **Jurisdictions:** which countries will the app be released in? Drives whether GDPR/UK GDPR and US state law sections are needed on top of DPDP.
2. **Minimum age:** 18+, 16+ or 13+? Drives store age rating and policy wording.
3. **Post-deletion retention:** what to do with Supabase `auth.audit_log_entries`, Supabase platform logs and backups, and Brevo contact/log copies after an account is deleted, and for how long. The cleanest answer is a scheduled purge of audit entries for deleted users plus a stated maximum (e.g. 30 days) for logs/backups.
4. **In-app policy link:** add a "Privacy policy" row on the sign-in and Account screens (needed for HealthKit review and good practice for Play).
5. **DPAs:** accept Supabase's and Brevo's data processing agreements.
6. **Email change:** support changing the account email, or document that users delete and recreate the account.
7. **Controller identity and contact address** for the policy (section 1).

## 11. Change triggers

Update the policy, the App Privacy answers and the Data safety form before shipping any of: Phase 3 health reads (this branch), Cloudflare Turnstile (#53), Firebase Crashlytics/Analytics, Phase 4 health write-back, watch workout recording, a new processor, or a change to what is synced.
