# Run NorthStar against your own Supabase project

NorthStar requires sign-in before any workout screen opens (see [ADR-0005](adr/0005-mandatory-auth-and-workout-sync.md)). The app therefore cannot start without a Supabase backend. Contributors use **their own free Supabase project**, never the maintainer's development project.

This guide takes about 15 minutes. You need it only to **run the app**. Formatting, `flutter analyze` and `flutter test` work without Supabase.

> Use synthetic workout data only. Your project is yours to delete when you're done.

## What the app checks at startup

`apps/mobile/lib/main.dart` refuses to start unless:

- `SUPABASE_URL` is an `https://` URL, and
- `SUPABASE_PUBLISHABLE_KEY` starts with `sb_publishable_`.

So a local `supabase start` stack (served over `http://127.0.0.1`) and the legacy `anon` JWT key **will not work** for running the app. Use a hosted project.

## 1. Create a project

1. Sign up at [supabase.com](https://supabase.com) and create a new project on the free tier.
2. Save the **database password** you choose; the CLI asks for it in step 3.
3. Note the **project ref**, the `abcd…` part of `https://abcd….supabase.co`.

## 2. Configure email-code sign-in

The app signs in with a **6-digit email code** (`signInWithOtp` + `verifyOTP`, type `email`) and rejects anything that isn't exactly six digits.

In the dashboard, under **Authentication**:

1. **Sign In / Providers → Email**: make sure Email is enabled and the **email OTP length is 6**.
2. **Emails → Templates**: edit both **Magic Link** and **Confirm signup** so the body contains the code, for example:

   ```html
   <h2>Your NorthStar code</h2>
   <p>{{ .Token }}</p>
   ```

   The default templates send a click-through link, which the app does not use.
3. **Email delivery:** Supabase's built-in email sender is heavily rate-limited and may deliver only to addresses on your project's team. Sign in with the email you used for your Supabase account. If you need other addresses, configure custom SMTP under **Authentication → Emails → SMTP settings**.

## 3. Apply the database migrations

Install the [Supabase CLI](https://supabase.com/docs/guides/local-development/cli/getting-started) (CI pins **2.81.3**). From the **repository root** (where the `supabase/` folder lives):

```sh
supabase login
supabase link --project-ref YOUR_PROJECT_REF
supabase db push
```

`db push` applies every file in `supabase/migrations/` in order. Re-run it after pulling new migrations from `main`.

A fresh project needs no restore-epoch rotation. [RESTORE_RUNBOOK.md](../supabase/RESTORE_RUNBOOK.md) applies only after restoring a database backup. The repository now includes **11 migrations**, including a fresh-session gate for the optional account-deletion flow; `supabase db push` does **not** deploy the Edge Function.

### Optional: testing permanent account deletion on your own disposable project

The Account-screen permanent deletion flow additionally requires deployment of the server-only `delete-account` Edge Function, not just SQL migrations. Follow the [account-deletion deployment/security runbook](../supabase/ACCOUNT_DELETION_RUNBOOK.md) and use only **disposable synthetic accounts and workouts**. Never embed `SUPABASE_SERVICE_ROLE_KEY` or other privileged secrets in Flutter, screenshots or Git. You can run and test ordinary workout features without enabling deletion; do not interpret an unconfigured function as proof that deletion is safe or available.

## 4. Copy your public keys

Under **Project Settings → API Keys**, copy:

- the **Project URL** (`https://YOUR_PROJECT_REF.supabase.co`)
- the **Publishable key** (`sb_publishable_…`)

**Never** use the secret key (`sb_secret_…`), the legacy `service_role` key, or your database password in the app. The publishable key is public by design; row-level security protects the data.

## 5. Run the app

```sh
cd apps/mobile
cp supabase.local.example.json supabase.local.json
# edit supabase.local.json with your URL and publishable key
flutter pub get --enforce-lockfile
flutter run --dart-define-from-file=supabase.local.json
```

`supabase.local.json` is git-ignored. Don't commit it, and don't paste your keys into issues or PRs.

Enter your email, wait for the code, and enter it. The workout app opens after verification.

## Testing the SQL locally (optional)

The pgTAP suite does not need a hosted project. With Docker running:

```sh
supabase start
supabase db reset     # replays all migrations from scratch
supabase test db      # same as the CI job
supabase stop
```

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| "A public Supabase URL and publishable key are required." | Missing `--dart-define-from-file`, an `http://` URL, or a legacy `anon` key instead of `sb_publishable_…` |
| Email contains a link, not a code | `{{ .Token }}` missing from the Magic Link / Confirm signup template |
| Code is rejected as invalid | OTP length isn't 6, or the code expired; request a new one |
| No email arrives | Built-in sender rate limit or unauthorized address; use your team email or custom SMTP |
| Sync calls fail with missing function errors | Migrations not applied; run `supabase db push` again |
| `db push` reports remote history mismatch | You changed the database by hand; reset the project or follow the CLI's `migration repair` hint |

Dashboard menu names change over time. If a step doesn't match what you see, search the [Supabase docs](https://supabase.com/docs) for the setting and open an issue so we can update this guide.
