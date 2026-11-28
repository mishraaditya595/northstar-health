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

### 2.6 Health platform reads (main: Phase 3 plus health insights)

From ADR-0008, ADR-0009 and `platform_health_reader.dart`:

| Item | Detail |
| --- | --- |
| Types read | Sleep sessions and stages (asleep, light, deep, REM, awake, in bed), steps, active calories burned, heart rate, resting heart rate, heart rate variability (SDNN on iOS, RMSSD on Android), walking heart rate (iOS), respiratory rate, blood oxygen, VO2 max, weight, body fat, lean body mass, skin temperature (Android, where available) / wrist temperature (iOS), and workouts other apps saved (HealthKit workouts / Health Connect exercise sessions: type, start, end, and on iOS active energy and distance; ADR-0011). Up to the last 90 days (detail trends read two 30-day periods plus a 30-day baseline; VO2 max 89 days). Read only; nothing is written to Apple Health or Health Connect. |
| Sources | Apple HealthKit (iOS), Google Health Connect (Android 9+), via the `health` 14.0.0 package. |
| Permissions | iOS: HealthKit entitlement, `NSHealthShareUsageDescription` ("BeyondRep reads your sleep, heart, activity, workouts and body measurements to show your daily summary, trends and training history. This data stays on your phone."), `NSHealthUpdateUsageDescription` ("BeyondRep writes the workouts you finish on this phone to Apple Health when you turn on saving in the Health tab."; shown with the HealthKit prompt only after the user turns that switch on, ADR-0014). Android: `READ_SLEEP`, `READ_STEPS`, `READ_ACTIVE_CALORIES_BURNED`, `READ_EXERCISE` (exercise sessions only; no calories or distance permission is requested for them, so Android workouts carry neither), `WRITE_EXERCISE` (only when the user turns on saving workouts to Health Connect; one strength-training session per finished phone workout with its name, start and end, no calories or heart rate, ADR-0014), `READ_HEART_RATE`, `READ_RESTING_HEART_RATE`, `READ_HEART_RATE_VARIABILITY`, `READ_RESPIRATORY_RATE`, `READ_OXYGEN_SATURATION`, `READ_VO2_MAX`, `READ_WEIGHT`, `READ_BODY_FAT`, `READ_LEAN_BODY_MASS`, `READ_SKIN_TEMPERATURE` (requested only where available) and `READ_HEALTH_DATA_HISTORY` (Health Connect otherwise returns only data from 30 days before the first grant). No background read. |
| When asked | Only when the user taps Connect, never at sign-up. |
| Storage | Values are held in memory for the life of the app process only. **No health value is written to disk**, synced to Supabase, put in the outbox or export file, logged, or sent to any third party. A guard test enforces the import boundary. |
| What is stored | A per-account "connected" flag (`HealthConnectionEntity { id, connectedAt }`) in that account's ObjectBox directory. No health values. Removed on Disconnect and with the account's local data. |
| Revoking | Disconnect in the app removes the flag; OS access must be revoked in the Health app / Health Connect settings (the app cannot revoke it). |
| Purpose | Show the user a daily summary, 7/30-day trends, detail screens, an on-device sleep score and energy score (Health tab, Today, Train, pre-workout note, Apple Watch; the energy score includes recent training load from BeyondRep and outside workouts), workouts from other apps in Activity, Progress history and Today (merged in memory with overlapping BeyondRep sessions, read fresh and never stored), and insights joined in memory with the user's logged workouts. The energy score learns the user's usual training hours and one drain adjustment from the last 90 days of BeyondRep workouts and up to 120 days of sleep, HRV and resting heart rate, worked out on the device each time and never stored. Not advice, not diagnosis, not advertising, not shared. |

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
| Supabase `auth.audit_log_entries` (IP, actor email/ID) | Not written on the hosted project: checked 2026-11-26, 0 rows with 2 users who have signed in, so "write auth audit logs to project database" is off. Auth audit events go only to Supabase log storage. If that setting is turned on again, rows would survive account deletion (no FK cascade), and a purge job and policy update are needed first. |
| Supabase platform/API/Auth logs | Per Supabase plan; the policy states 1 day for the free plan (owner to confirm in the dashboard; update if the plan changes) |
| Brevo email logs and contact record | Per Brevo's own retention rules (policy says "a limited period") |
| On-device data | Until the account is deleted (local directory erased), or the app is uninstalled |
| Health readings (Phase 3) | Not retained; memory only |

**Account deletion (Shipped, main, PR #29):** in-app at Account > Delete account. The user sees a warning about unsynced data, is offered an export first, re-verifies with a fresh email code, and the `delete-account` Edge Function hard-deletes the Supabase Auth user. FK cascades remove `workout_records`, `workout_sync_operations` and `workout_owner_cursors`. The app then erases that account's local ObjectBox directory. Details and uncertain-outcome handling: `supabase/ACCOUNT_DELETION_RUNBOOK.md`. The free plan keeps no automatic database backups (Supabase docs: daily backups start on Pro), so deleted rows are not kept in a backup. Upgrading the plan needs a policy update.

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
- The app does not write false or inaccurate data. Phase 5 (ADR-0014, opt-in) writes only the name, start and end of workouts the user finished in BeyondRep, never measured or estimated values. Update the App Privacy answers, the App Store review notes and this section before release.

### 7.2 Google Health Connect

- The privacy policy must describe the handling of each Health Connect data type and is linked from the Health Connect permission screen through the rationale intent / `ViewPermissionUsageActivity` alias. `PermissionsRationaleActivity` now opens `https://beyondrep.in/privacy` there; the page must be final, not Draft, before release.
- Complete the Play Console **Health apps declaration** listing each permission in section 2.6 with its justification, including `READ_EXERCISE` (shows and merges workouts other apps saved, and feeds training load) and `READ_HEALTH_DATA_HISTORY` (trends and baselines compare today with up to 90 days). The policy's Health section has a table naming every type and its use.
- Follow the Health Connect **Limited Use** requirements: use only to provide the user-facing feature; no transfer except as needed for that feature, legal compliance or a merger; no ads; no human reading except with consent, for security or legal reasons. The policy should contain a Limited Use statement.
- Request only needed permissions: every type in section 2.6 is shown in the app; `READ_HEALTH_DATA_HISTORY` is requested for the 90-day baselines; no background read permission. `READ_EXERCISE` is requested for workouts from other apps; no calories or distance permission is. Adding a type (for example total calories or distance for Android workouts) needs this section, 2.6 and the policy updated first.

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

## 10. Owner answers (2026-11-26)

1. **Jurisdictions:** India first. The policy is written for the DPDP Act 2023. Add GDPR or US sections before releasing elsewhere.
2. **Minimum age:** 13. Because DPDP treats under-18s as children, the policy says under-18s may use the app only with a parent's or guardian's consent. The app has no verifiable parental-consent flow; this is an accepted risk, and 18+ would remove it.
3. **Post-deletion retention:** no database audit rows (see section 5); Supabase logs for 1 day on the free plan; Brevo per its own rules; no database backups on the free plan.
4. **In-app policy link:** yes, a Privacy policy button on the sign-in and Account screens (PR #81).
5. **DPAs:** the owner has accepted Supabase's and Brevo's.
6. **Email change:** not supported. The policy tells users to export, delete the account and sign up again.
7. **Controller:** Aditya Mishra, Brahmapur, Odisha, India. The privacy contact is the owner's Zoho Mail address until privacy@beyondrep.in routing is set up; then switch `privacyEmail` in `apps/website/src/site.ts`.

## 11. Change triggers

Update the policy, the App Privacy answers and the Data safety form before shipping any of: Phase 3 health reads (this branch), Cloudflare Turnstile (#53), Firebase Crashlytics/Analytics, Phase 4 health write-back, Phase 5 saving workouts to Apple Health / Health Connect (ADR-0014), watch workout recording, a new processor, or a change to what is synced.
