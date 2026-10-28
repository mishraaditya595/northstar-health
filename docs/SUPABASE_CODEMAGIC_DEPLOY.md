# Codemagic: controlled Supabase migrations and Edge Function deploys

**Status:** Configured as **manual-only workflows in source**. No hosted
Codemagic run, hosted migration or Edge Function deployment is asserted by this
document. See [Phase 2 hosted QA](implementation/phase-2/p2-08-hosted-release-plan.md)
and [account deletion runbook](../supabase/ACCOUNT_DELETION_RUNBOOK.md).

The public repository contains *commands*, migrations and reviewed Function
source, not credentials. Codemagic supplies encrypted, protected secrets at run
time. Publishing a pipeline file is not the same as publishing the secrets it
references. Restrict access to the Codemagic app, build logs, API tokens and
variable groups; a contributor who can modify scripts executed on a trusted
branch or run an untrusted workflow with secrets could still extract them.

## Workflows (all manual, on main only)

| Workflow ID | Result | Database writes? |
| --- | --- | --- |
| `supabase-staging-preview` | Linked database migration **dry run** | No |
| `supabase-staging-migrate` | Apply pending migration files in order | **Yes** |
| `supabase-staging-function` | Deploy `delete-account` Edge Function | **Yes** |
| `supabase-production-preview` | Linked production migration **dry run** | No |
| `supabase-production-migrate` | Apply reviewed pending production migrations | **Yes** |
| `supabase-production-function` | Deploy `delete-account` to production | **Yes** |

No `triggering` blocks or `publishing` blocks exist on these workflows.
Codemagic can still start them via its **manual UI or API**; protect *both*
permissions. The script explicitly rejects webhook/scheduled invocation,
non-`main` branches and an absent initiator identity. Do **not** add automatic
push, PR, tag or cron deployment triggers.

The original 11 Flutter/watch workflows remain intentionally failing
placeholders. Database operations have no relationship to App Store/Play
distribution.

## One-time setup in Codemagic UI — never in Git

1. Connect the repository to Codemagic using the YAML configuration. Set
   appropriate organization/app permissions: **only trusted maintainers** can
   run privileged jobs, edit settings/groups, or change environment variables.
   Protect `main` with required reviews and disallow PR-origin secret builds.
2. Provision **two independent Supabase projects** for staging and production.
   Staging must use disposable synthetic workouts/accounts for destructive
   tests. Do not point both groups at the same project.
3. In the Codemagic app **Environment variables** settings create groups
   `ns_supabase_staging` and `ns_supabase_production`. Add these names
   separately in **each** group:

   | Variable name | Setup | Sensitive? |
   | --- | --- | --- |
   | `SUPABASE_ACCESS_TOKEN` | A reviewed Supabase PAT; use a **project- and permission-scoped** PAT if available, never a legacy full-access token | **Secret** |
   | `SUPABASE_DB_PASSWORD` | Database password for that environment | **Secret** |
   | `SUPABASE_PROJECT_ID` | Exact 20-character project ref of that environment | Mark private |
   | `NS_SUPABASE_GROUP_TARGET` | Literal `staging` or `production` matching the group | Not a password |

   The first two must be marked **Secret** in Codemagic's UI. Keep the
   project reference private as an operational preference. **Legacy/full-access
   personal tokens can operate on every project the issuing user can access,
   including production**; merely putting two broad tokens in separate
   Codemagic groups does **not** isolate their privileges. Supabase now offers
   project- and permission-scoped PATs in its dashboard: select one for each
   environment and verify the scope; for genuinely independent administration,
   use separate Supabase accounts or organizations. The explicit
   `NS_SUPABASE_APPROVED_PROJECT_ID` equality guard is an important last
   safeguard against accidental cross-project deployment, **not** isolation
   against malicious edits to a workflow holding broadly privileged tokens.
   Do not share database passwords between projects.
4. For each **particular, reviewed** deployment, add/update the following
   per-environment variables **in the corresponding group**, not in Git:

   | Variable | Required for |
   | --- | --- |
   | `NS_SUPABASE_APPROVED_SHA` | Migration and Function deploy: full 40-character `main` commit SHA selected by the maintainer |
   | `NS_SUPABASE_APPROVED_PROJECT_ID` | Migration and Function deploy: target project ref, independently reconfirmed |
   | `NS_SUPABASE_FUNCTION_APPROVED_SHA` | **Function only:** independent approval of the same commit after migrations/security acceptance |

   Preview needs none of these approvals. **Do not configure approvals
   permanently**: remove/clear them immediately after a deployment. The
   script refuses different commits, mismatched projects, environments or
   missing approvals. Approval fields are **manual release controls**, not
   substitutes for human review, backup or Supabase role isolation.

Codemagic UI: select the app, **Environment variables**, the group, then
add the values, marking tokens/passwords Secret. Never place actual values in
`codemagic.yaml`, PR descriptions, screenshots, issue comments or job logs.
Do not use `printenv`, `set -x`, `--debug`, `echo` for credential values
or `supabase login` in CI. The CLI reads `SUPABASE_DB_PASSWORD` from the
environment, without passing it as a password command-line argument.

**Important:** Supabase CLI `link` may read project settings and require
access to keys; supply an appropriately scoped management access token.
Scoped Supabase PATs do **not** work with `supabase whoami`, which this
pipeline deliberately does not invoke. The exact minimum scopes needed by
`link`, `db push` and `functions deploy` must be verified with the first
staging preview and subsequent approved staging jobs; do not broaden scopes
without a separate review. Keep
`SUPABASE_SERVICE_ROLE_KEY` out of Codemagic and out of the Flutter app.
Supabase-hosted Functions receive configured server-side credentials within
the Supabase runtime. Review runtime availability before enabling deletion.

## How to perform a release

1. Merge and review migrations/Function source; verify GitHub `supabase_sql`
   CI and its pgTAP/Deno tests. Confirm backup/snapshot, current remote
   migration versions, existing rows, and any migration side effects. The
   migration `20261025090000` **deletes** records not in `completed`
   state. The P2-05 UTC backfill and index locking require separate approval.
2. Codemagic → **Start new build** → branch **main** → choose
   `supabase-staging-preview`. The script uses pinned Supabase CLI
   `2.81.3`, `supabase link` and `supabase db push --linked --dry-run`,
   followed by **`supabase migration list --linked` parsed in read-only
   report mode**. The log reports applied versus pending migration counts
   and fails safely on unexpected table formats or divergent history.
   Unexpected remote-only migration versions are named in the failure
   message for manual investigation; no history is repaired automatically.
   This first staging preview also validates the real CLI table format
   and scoped token permissions without deploying. Record expected migration
   versions (never passwords or user data). A green preview with pending
   migrations is **not** permission to deploy a Function and does not attest
   schema drift, UTC conversion, or absence of destructive SQL; the maintainer
   must review these separately.
3. After the appropriate database backup and owner approval, set both
   `NS_SUPABASE_APPROVED_SHA` and
   `NS_SUPABASE_APPROVED_PROJECT_ID` in **staging** group. Manually start
   `supabase-staging-migrate` on the **same SHA from main**. It previews,
   then runs `supabase db push --linked --yes` (no seeds, repair or resets).
   After the push, it checks **`supabase migration list --linked`**
   against all committed local versions; there is **no redundant second
   dry run**. A `db push` exit code alone is insufficient.
   Verify the actual schema and signed-JWT RLS with two fresh synthetic
   verified users. **Do not deploy the Edge Function merely because migrations
   applied.**
4. Review `delete-account` handler Auth.getUser verification, five-minute
   persisted session gate, owner-scoped cascades and separate user-confirmed
   local recovery behaviors. Once the backend is accepted, set
   `NS_SUPABASE_FUNCTION_APPROVED_SHA` in staging (same SHA) and manually
   start `supabase-staging-function`. It uses
   `supabase functions deploy delete-account --project-ref ... --use-api`.
   **The function workflow refuses to deploy if `supabase migration list
   --linked` shows missing, extra or mismatched remote migration versions**
   (even if `db push --dry-run` exited successfully). The current reviewed
   Function list contains only `delete-account`; future Functions must
   receive a separate code/security review before joining it. The version
   check is not proof of SQL integrity, so a drift/schema audit remains
   necessary. **The CLI uses each Function's `verify_jwt` setting from
   `supabase/config.toml`**; the deploy runner never passes the global
   `--no-verify-jwt` flag. Only `delete-account` currently has
   `verify_jwt = false` because its handler validates a caller with
   `Auth.getUser` and the fresh-session authorization RPC. Adding a new
   Function must include an explicit gateway-vs-handler authorization review;
   never assume unauthenticated invocation is safe. Verify the deployed
   Function's configured JWT setting and runtime environment separately.
   Offline contract tests enforce **bidirectional parity** between the
   `FUNCTIONS` allowlist, deployable directories under
   `supabase/functions/`, and `[functions.<name>]` entries in
   `supabase/config.toml`. The conventional `_shared` helper directory
   is excluded. Each listed Function must also have `index.ts` and an
   explicit Boolean `verify_jwt`. Any unlisted Function folder or TOML
   entry fails CI before a deploy can be approved.
5. Run all hosted signed-JWT, two-device, stale/deleted-token, Auth-deletion
   and physical-device P2-08 checks using **disposable** accounts. The
   read-only Python audit alone is not sufficient.
6. Repeat preview, manual approval and separate migration/Function workflows
   for **production only after staging passes** and independent release
   approval is recorded. Do not reuse staging credentials or test identities.
7. Remove the approval variables from both groups after each approved run and
   rotate/revoke credentials when appropriate. Record sanitized build ID,
   repository SHA, target environment, migration versions, security verdict
   and release-owner sign-off.

Only the **same reviewed SHA** from main may be deployed. On a later commit
or a changed target, approvals must be reissued in Codemagic settings.

## Manual migration-history reconciliation (development project)

A historical read-only inspection of the connected NorthStar-Health development
database found **6 of 11** committed migrations recorded on 27 October 2026.
That is a dated observation, **not proof** of the project's current state or
evidence that the remaining SQL was applied. **Missing history and legitimately
unapplied migrations are different cases.** Do not repair versions merely
because they appear pending.

1. Explicitly identify the **nonproduction development project** and make a
   restorable backup/snapshot. Record the current database schema, migration
   tracking entries, and migration SQL before any writes. Never run this
   procedure against an unidentified or live-user project.
2. With a trusted operator environment and a scoped PAT, use the **reviewed**
   repository's migration files and first inspect:

   ```bash
   supabase link --project-ref YOUR_APPROVED_DEV_PROJECT_REF
   supabase migration list --linked
   supabase db push --linked --dry-run
   ```

   Confirm the listed project reference is the intended one. Compare **every
   version** against `supabase/migrations/` and inspect actual objects/RPCs
   and SQL effects before classifying it. Review pending deletion of
   non-completed records and the historical UTC backfill warning in the P2-05
   SQL.
3. Make and record a **human decision per version**:
   - **Local only and SQL not yet applied:** leave as pending; after review,
     use the *separately approved* staging migration workflow. **Do not**
     mark an unexecuted migration as applied.
   - **Local only but verified SQL is already applied** outside tracked
     migrations: only after proving the schema/effects match the immutable
     migration SQL, the maintainer may reconcile history with
     `supabase migration repair VERSION --status applied --linked`.
   - **Remote marked applied but verified SQL was never executed:** after
     comparing schema/backups, the maintainer may mark that version
     `--status reverted` so it can later be applied properly. This does
     **not** reverse SQL.
   - **Remote-only version, drift, partial application or uncertain history:**
     **stop**. Investigate source and live schema; prepare a reviewed
     corrective migration/reconciliation plan instead of guessing.
4. If and only if a history correction was approved, run that **specific**
   `supabase migration repair` command manually outside Codemagic. It
   modifies the migration history table, **not the schema**, and must not be
   automated. Re-run `supabase migration list --linked` and
   `supabase db push --linked --dry-run`, then review the differences again
   before authorizing any migration push.
5. After normal migrations have been safely applied, check the recorded remote
   history contains **all eleven expected versions**, confirm the actual
   schema/RPCs and UTC semantics, and perform hosted signed-JWT/RLS testing.
   Only then consider a separately approved `delete-account` deployment.

Reference: [Supabase database migration reconciliation and
`migration repair`](https://supabase.com/docs/guides/deployment/database-migrations).
**Never use `db reset --linked`, automated repair, or speculative rollback.**

## Contributor workflow (own isolated Supabase project)

Contributors and AI agents must **not** run deployment workflows against
NorthStar's staging/production or reuse the maintainer's database credentials.
For local investigation, create a personally controlled disposable Supabase
project, check out the branch being reviewed, install the repository-pinned CLI
(`2.81.3`), and run:

```bash
supabase link --project-ref YOUR_OWN_DISPOSABLE_PROJECT_REF
supabase migration list --linked
supabase db push --linked --dry-run
```

The **dry run does not apply migrations**. Review the proposed SQL and compare
history before attempting any further action; never run `db push` on the
project merely to make a CI check green. Do not commit the project's tokens,
passwords, `.env`, downloaded credentials or generated local link state.
If you need to test a real deployment to **your own** disposable project,
obtain explicit authorization for the destructive effects of migrations and
use synthetic records only. PR evidence must distinguish a dry run from an
actual hosted deployment.

## Deploy serialization and machine cost

**Run only one migration deployment against a given Supabase project at a
time**, including local CLI, Codemagic and any other CI providers. The YAML
does not enforce a cross-run distributed lock; Codemagic manual launches can
overlap. The maintainer must check that no deployment or schema operation is
active before starting another and keep staging/production approvals per run.
If another run starts, cancel it before any migration write and inspect the
remote history before restarting. Concurrent deployments can race and leave
partially applied or unexpectedly interleaved operations.

The six backend jobs currently use `mac_mini_m2` because it is available on
the project's initial Codemagic plan. A Node/Python CLI runner does not need
macOS. **Switch all six backend jobs to `linux_x2` once Codemagic billing
and Linux machine access are enabled**; do not switch the iOS/watchOS
workflows, which require macOS. Linux can be billed differently from free
macOS build minutes; compare the actual account entitlement first.

## Failure, rollback and ownership

- Missing variables, wrong group/environment, wrong SHA, PR/webhook builds,
  absent initiator and mismatched project approval fail **before connecting**
  to Supabase.
- The preview is read-only against the hosted DB; `link` writes local CLI
  metadata in the ephemeral runner only. Its report-only migration parser
  **allows and reports pending versions** but fails on drift or unrecognized
  status output; it does not authorize a deployment. Migration and Function
  actions instead require strict `migration list --linked` parity with
  **zero pending versions**. These checks compare version IDs, not migration
  SQL hashes or live schema drift.
  Migration deployments are
  **non-atomic across files** and can partially succeed. If a later migration
  fails, **stop and inspect migration history**. Do not use `db reset
  --linked`, `migration repair`, reverse/drop tables, or replay old
  migrations in an automated retry.
- If the Function deployment fails, the successfully applied migrations
  remain. Previous deployed Function versions may still be active. Verify
  actual Function state before retrying or rolling back.
- To disable account deletion, disable/withdraw the server-side Function and
  revoke the deletion authorization RPC privilege by a reviewed corrective
  migration; preserve existing user data. Completed hard deletions cannot
  be undone by redeploying an old build.
- Secrets are available to the Codemagic build process while it runs. UI
  masking is not a security boundary against intentionally malicious scripts.
  Require owner code review, restricted Codemagic access, main-branch
  protection, separate credentials and frequent credential rotation.

## Validation

The public repo uses `tool/test_codemagic_config.py` for YAML structural
gates and `tool/test_codemagic_supabase.py` for offline, stubbed CLI failure
and approval tests (discovered by the existing contract workflow). These tests
**cannot** prove Codemagic integration, migration success or Supabase account
security. A real Codemagic *preview* should be the first hosted action after
the owner configures groups.

References: [Codemagic encrypted groups](https://docs.codemagic.io/yaml-basic-configuration/configuring-environment-variables/),
[Codemagic manual workflows](https://docs.codemagic.io/yaml-basic-configuration/yaml-getting-started/),
[Supabase CLI migration workflow](https://supabase.com/docs/guides/local-development/cli-workflows),
[Supabase managing environments](https://supabase.com/docs/guides/deployment/managing-environments),
[Supabase Edge deployment](https://supabase.com/docs/guides/functions/deploy).
