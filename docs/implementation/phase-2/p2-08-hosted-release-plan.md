# P2-08 — Hosted preflight and Phase 2 release execution plan

**Status: In progress, NOT validated/released (27 October 2026).**
P2-01 through P2-07 are merged in source. This is the first P2-08
implementation slice, not evidence that Phase 2 may be shipped. The human
maintainer must review the PR, approve deployment, own device checks and sign
the final release record. Never merge/deploy automatically.

## Current hosted inventory (read-only observation, 27 October 2026)

The connected **NorthStar-Health** Supabase project returned:
- **6 of 11** ordered SQL migrations installed, through
  `20261025071009_phase2_tombstone_delete_retry_guard`; **5 missing**.
- **No** deployed Edge Functions (`delete-account` is absent).
- **0** Auth users, **0** `workout_records`, **0** sync receipts and **0**
  rows requiring cleanup by the completed-only migration at the moment checked.
- Public workout tables had RLS enabled. The SQL session timezone was UTC;
  this **does not prove** transaction-local UTC semantics of the pending
  P2-05 migration's historical backfill.

This is a dated snapshot, not a backup or authorization to run a migration.
Reinspect the target project immediately before deployment. No hosted
schema/data writes or Auth deletions were performed during this preflight.

## Work order and stop conditions

| Gate | Needed evidence | Current status |
| --- | --- | --- |
| 1. Deployment preflight | target is explicitly approved **nonproduction** project; backup, migration hashes, 11-file/remote reconciliation, pending SQL and UTC/backfill review, local pgTAP and function tests | **Blocked: 5 migrations missing** |
| 2. Backend activation | reviewed sequential schema deployment, provision/configure verified Auth email-code flow, deploy `delete-account` with handler-side validation, security advisors | Not executed |
| 3. Hosted signed-JWT owner isolation | real verified A/B sessions and synthetic completed fixtures; green read-only audit in this PR plus write/RPC/expired-token negative tests and unchanged B data | Harness implemented; live execution pending |
| 4. Two phones / one account | offline completed workout, serial uploads, crash/relaunch, idempotent replay, two-device restore, revision CAS and conflict actions, tombstone/non-resurrection, epoch rotation drill | Not run |
| 5. Account deletion | fresh OTP session gate, old-session/old-JWT denial across every RPC, server hard delete/cascade, B unaffected, both ADR-0007 recovery exits and protected local partitions | Not run |
| 6. All-history export | beyond 4 MiB without data loss/OOM, strict owner/cursor checks, iOS picker and Android SAF process-death/cancel/permission/memory probes | **Blocked by 4 MiB cap** |
| 7. Release reliability | offline restart, RLS/advisors, retention of tombstones and 90-day receipt pruning including inactive accounts, privacy/security review, Android/iOS CI, low-end memory/accessibility | Not run |

**Do not** deploy to production, enable real-user deletion, change JWT
lifetimes, publish to stores, or claim a test passed from a mock/pgTAP alone.
Any unexpected drift, destructive migration impact, stale-JWT leak, cross-owner
exposure or data loss is an unconditional stop.

## Signed-JWT read-isolation smoke audit

`scripts/p2_08_hosted_rls.py` uses Python standard library only. It calls
the **real hosted REST API** with a publishable key and two verified, nonanonymous
Supabase Auth access tokens. It **never writes or deletes** data, accounts or
migrations, and never prints response bodies, tokens or owner/workout UUIDs.
The audit checks:

- `GET /auth/v1/user` verifies **two distinct** nonanonymous owner UUIDs.
- A and B can each read their known, completed, undeleted seeded fixture.
  An empty project is a **failure**, not a pass.
- A cannot SELECT B's fixture and vice versa, including workout-ID-only
  filters without a supplied owner.
- Owner-authenticated `get_workout_for_resolution` reveals only that owner's
  record; foreign lookup is `change:null`.
- Paginated `get_workout_changes` uses stable epoch, increasing cursor,
  a maximum of 100 pages and finds each seeded fixture without seeing the
  other owner's workout ID.
- Unauthenticated requests cannot read a known owner fixture.

**Prerequisites:** Once the first **ten** migrations are verified on an
isolated hosted test environment, the Auth UI is configured with a six-digit
email OTP template, and A/B have each completed one synthetic workout via the
phone's normal flow, record the two respective workout UUIDs and access tokens
locally **outside** the repository. Those credentials expire; get fresh ones
via actual email-code sign-in. Apply the eleventh migration and the deletion
function *only after* the separate fresh-session review and rollback plan.
For the complete release acceptance, **all eleven** and the function must
be verified, even though this read-only audit itself uses only the read/RPC
features available through migration ten.

Never use production users, real health measurements or service-role keys as
client credentials. A passing run proves only the named signed-session
*read-isolation* checks; it does **not** cover write/RPC denial, Auth-user
hard deletion, old token behavior, two-device concurrency or native storage.

Run from the checked-out repository on a **nonproduction** project with
only expendable synthetic data (environment variables are not committed):

```bash
export NS_P2_08_DISPOSABLE_ACK=nonproduction-disposable-only
export NS_P2_08_URL='https://YOUR-TEST-PROJECT.supabase.co'
export NS_P2_08_PUBLISHABLE_KEY='YOUR_PUBLIC_KEY'
export NS_P2_08_JWT_A='VERIFIED_A_ACCESS_TOKEN'
export NS_P2_08_JWT_B='VERIFIED_B_ACCESS_TOKEN'
export NS_P2_08_WORKOUT_A='A_COMPLETED_WORKOUT_UUID'
export NS_P2_08_WORKOUT_B='B_COMPLETED_WORKOUT_UUID'
python3 scripts/p2_08_hosted_rls.py
unset NS_P2_08_JWT_A NS_P2_08_JWT_B
```

Avoid shell history or terminal recording of real tokens. Prefer process-scoped
secret injection or secure local credential tooling. The sample commands are
placeholders, **not** working credentials. Failure returns nonzero; no assertion
is reported as successful if one fixture is missing.

Offline contract regression tests are wired into existing
`contracts_ci.yml` through the `tool/test_*.py` suite and can be run with:

```bash
python3 -m unittest discover -s tool -p 'test_p2_08_hosted_rls.py'
```

## Deployment readiness: ordered manual operator checklist

1. Confirm project ID/environment, no production data, available backup and
   capability to restore. Capture `supabase migration list --linked` and
   compare every version and migration hash to the **11 committed files**.
   Recheck row counts before the seventh migration, which deletes noncompleted
   rows; do not rely on the earlier zero-row observation.
2. Inspect SQL diffs and P2-05 timezone/backfill transaction context; test
   clean reset and pgTAP on the identical Supabase CLI image/toolchain. Record
   transactional UTC results and an explain/lock-impact review. Deployment is
   blocked if the migration does not preserve existing meaningful data.
3. With maintainer review, deploy the missing **ordered** migrations to
   nonproduction, verify installed version set and RLS grants, then use normal
   email OTP with two verified synthetic users. No production keys in Flutter.
4. Run the read-only audit above; separately exercise real signed-JWT
   `sync_workout` input validation/replay, direct table write denial, RLS
   summaries, P2-06 concurrency and tombstones. Record statuses and owner
   isolation, but not account IDs, tokens or payloads in the repository.
5. After fresh-session migration is reviewed, deploy the server-only Edge
   Function and follow
   [ACCOUNT_DELETION_RUNBOOK.md](../../../supabase/ACCOUNT_DELETION_RUNBOOK.md).
   Test deleted-user stale JWT calls on the **second device**; never infer
   revocation merely from `auth.admin.deleteUser`. Protect B and verify
   irreversible deletion only with disposable A.
6. Review
   [workout-export release matrix](p2-08-workout-export-release-validation.md)
   on physical Android/iOS hardware and remove the 4 MiB all-history blocker.
   Verify both account-recovery choices from
   [ADR-0007](../../adr/0007-account-deletion-recovery-exit-choices.md)
   with separate confirmations and no cross-account data transfer.
7. Independently review privacy and receipt-retention operations, migration
   rollback/epoch rotation plan, CI results, App Store/Play eligibility and
   developer sign-off. Do **not** turn watch/HealthKit/Health Connect
   future work into a Phase 2 delivery claim.

## Evidence to attach before sign-off

For **each** test record code SHA, Supabase project role (test/staging),
sanitized migration **versions/hashes**, app/platform version, tester,
test timestamp, exact test case, expected versus observed behavior, PASS/FAIL,
evidence link and outstanding risks. Attach no tokens, user UUIDs, exports,
phone logs with personal data, or secrets. A passing code CI job alone is
insufficient.

| Gate | Code SHA / environment | Evidence reference | Verdict |
| --- | --- | --- | --- |
| Hosted migration/UTC audit | Pending | Pending | NOT RUN |
| Hosted signed-JWT RLS/CRUD/RPC | Pending | Pending | NOT RUN |
| Two-device offline/sync/conflicts | Pending | Pending | NOT RUN |
| Stale-token/account deletion/cascade | Pending | Pending | NOT RUN |
| Large export / native Android+iOS | Pending | Pending | NOT RUN |
| Physical device / security / retention | Pending | Pending | NOT RUN |

**Release decision:** BLOCKED until all gates pass and the maintainer
explicitly signs off.
