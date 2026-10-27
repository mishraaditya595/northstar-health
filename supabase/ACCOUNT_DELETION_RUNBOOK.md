# P2-07c account deletion — deployment, security, recovery

**Implementation:** [P2-07c issue #28](https://github.com/mishraaditya595/northstar-health/issues/28). Human-reviewed PR #29 is the delivery unit. **Not deployed, not tested with real accounts.** This is an operational runbook, not proof of a successful deletion.

## Data ownership and deletion boundary

The Flutter client can send a verified user JWT but **never a service-role key**. Only `supabase/functions/delete-account/index.ts` accesses `auth.admin.deleteUser` with a server-injected `SUPABASE_SERVICE_ROLE_KEY`.

A successful **hard** deletion of the caller's `auth.users` row causes the existing `ON DELETE CASCADE` foreign keys to remove:
- `public.workout_records`: completed aggregate payloads and deletion tombstones
- `public.workout_sync_operations`: idempotency receipts and their hashes
- `northstar_private.workout_owner_cursors`: per-owner restore/sync sequence

The global restore epoch and schema metadata are NOT owner data and remain. No user-owned Supabase Storage objects are supported in this phase. **If user-owned Storage objects are added, revise the deletion design before enabling it**: GoTrue can refuse to delete their owner until the objects are cleaned. Other new user-associated tables must get explicit reviewed cascade/delete handling.

The client-side owner-specific ObjectBox directory is **not erased** by this feature; it is rendered inaccessible by deleting its securely stored binding and unmounting its authenticated ProviderScope. A newly created account, even with the same email, must NEVER be bound to that prior UUID's partition. No guest migration or cloud reassociation is permitted.

## Verify before enabling in any environment

1. Apply the committed P2-07c migration `20261027180000_p2_07c_recent_account_session_gate.sql` only after reconciling **all prior** migrations/hosted drift and making a backup. Run clean `supabase test db` and review its SQL privilege/session tests.
2. Deploy the Edge Function `delete-account` through the environment's reviewed release pipeline; verify its **runtime** (not Flutter) receives `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY`. Do not commit/print their values. The function has `verify_jwt=false` at the gateway because publishable keys are not necessarily legacy JWTs; the handler explicitly enforces bearer token Auth `getUser` and fresh-session RPC. Deploying without this handler validation is unsafe.
3. Create two disposable confirmed accounts A and B via the real email-code sign-in flow in a nonproduction project. Confirm `auth.sessions.created_at` genuinely changes on a new `verifyOTP`, and that an access-token refresh does **not** change the session's creation time.
4. Test missing/invalid bearer, anonymous identities, expired/revoked sessions, stale sessions (older than 5 minutes), mismatched UUID in the JSON body, changed identity between request and response, non-POST methods, unknown keys, and replay with the old bearer token. All must fail without privileged deletion. Test that the server only deletes the Auth UID from the **current token**.
5. Populate A and B with synthetic completed histories, receipts, owner cursors and tombstones. Generate a separate locally pending workout on device A. Export A's history first. With newly verified A OTP and final explicit confirmation, issue one deletion. Confirm the response is exactly `{schema_version:1,deleted:true}`, Auth A cannot obtain a fresh token and A's database rows are gone, while B's remain intact. The locally pending workout must never be reassociated to B.
6. On a second device that holds A's earlier JWT, retry authenticated `sync_workout`, progress, pull/feed, conflict-lookup and raw RLS SELECT. Ensure no deleted A data is returned, and no new orphan row is created. Old JWTs can remain cryptographically valid until expiry; do not claim immediate global JWT invalidation. Validate Auth-session existence for sensitive operations when necessary.
7. Simulate remote timeout **after** server commit, network outage before request, sign-out during re-verification, wrong-owner OTP, secure-keychain deletion failure, frozen/restarted app and simultaneous A/B sessions. Verify the app never claims an unacknowledged deletion and never opens the wrong account's local ObjectBox.
8. Measure and validate the P2-07b export's provisional 4 MiB limit on real low-memory hardware or implement reviewed streaming **before product release**. Large-account users currently cannot obtain the mandated all-history file.
9. Obtain the maintainer's approval for applicable legal retention and privacy disclosure. Document any required separate retention; never quietly preserve exported private payloads or analytics of deletion requests.

## Live workflow and ambiguous outcomes

1. UI displays a warning about unsynced/local-only/unfinished workouts and offers JSON export first. The user confirms and receives an OTP sent only to the verified Auth email with `shouldCreateUser:false`.
2. OTP verification creates a **new** Auth session. The client checks its UUID against the locked owner. If wrong, **no deletion endpoint is called**.
3. The client clears the device's secure bound-account key. If that fails, it does not send deletion. After a successful clear, the account UI and serialized upload/restore worker unmount; the old local workout partition remains untouched and inaccessible.
4. The server verifies `getUser` and the immutable `auth.sessions.created_at` with `authorize_account_deletion`, then hard-deletes the verified Auth UID. FK cascades happen transactionally in PostgreSQL. A `{deleted:true}` response is a confirmed server success. No local restore or log replay may occur afterwards.
5. If the HTTP response is interrupted, distinguish **unknown** from **failed**. The local binding stays cleared; app shows a locked state. The user must verify whether the original account still exists via a new email-code sign-in or contact support. The app must never recreate that deleted UUID. There is no client-side or anonymous privileged retry.
6. A second deletion attempt made with the old JWT cannot succeed because the Auth user/session no longer exists; `getUser` rejects it. Do not return a fabricated idempotent success for a different or deleted account.

## Emergency disabling / rollback

Disable the server-side `delete-account` function before reverting clients. Revoke authenticated `authorize_account_deletion()` EXECUTE if the endpoint is compromised. Preserve existing workout rows and backups: never drop `workout_records` or revert migrations destructively. A successful deletion is irreversible and cannot be rolled back by redeploying an older app; any restoration requires an explicit user/operations/privacy decision. New deployment/release requires independent security review and hosted tests.

**Outstanding P2-08 gates:** Real signed-JWT hosted tests, two-device auth behavior and cross-owner negative cases, low-memory JSON export, Android/iOS OTP/UI/storage behavior, provider token-expiry tests, Auth-user blocking Storage objects, and confirmed FK cascades. No such hosted or physical-device result is claimed here.
