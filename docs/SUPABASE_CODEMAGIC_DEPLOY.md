# Codemagic: two manual Supabase deployment jobs

**Source configuration only. No hosted migration or Edge Function deployment is implied.**
See [P2-08 hosted release plan](implementation/phase-2/p2-08-hosted-release-plan.md)
before activating account sync or deletion on real devices.

## Jobs

| Codemagic workflow | Build inputs | Does it write? |
| --- | --- | --- |
| `supabase-database` | action: preview/deploy; project ref and reviewed full commit SHA confirmations | Only when deploy |
| `supabase-functions` | action: preview/deploy; project ref and reviewed full commit SHA confirmations; space-separated Function **names** | Only when deploy |

Both are **manual-only**: no push, PR, cron or publishing triggers.
They require a manually started build on `main` and a trusted initiator.
`preview` is the default. The confirmation inputs use the harmless
`NOT_SET` placeholder, and `function_names` uses `SELECT_FUNCTION`. These
are deliberately **nonempty** because Codemagic rejects empty interpolated
`environment.vars` values during YAML validation. Leave both `NOT_SET`
placeholders unchanged for **any preview**; do not clear the fields.
For a Function preview, explicitly replace `SELECT_FUNCTION` with the
function name(s), e.g. `delete-account`; no Function is preselected.
Leaving `SELECT_FUNCTION` unchanged fails with instructions to select
an actual function name.
Neither placeholder can authorize a deployment or select a Function.
For any `deploy`, manually enter the exact protected project ref and full
40-character **reviewed** commit SHA (not just the branch name). The runner
checks that SHA against `git rev-parse HEAD` **before connecting** and
refuses a stale or mismatched revision. If `main` advances after your
review, review the new commit and reenter its SHA rather than silently
deploying it. This input is an explicit operator confirmation, **not an
independent authorization mechanism**: restrict who can run Codemagic
builds and who can edit protected groups. Running previews never changes
the hosted database or deploys a Function, though `supabase link`
writes local CLI metadata on the build machine.

### One-time setup

Create a **private app-level** Codemagic variable group named
`ns_supabase_deploy` for exactly **one** Supabase target. Do not import
both staging and production credentials into the same workflow.

| Variable in protected group | Value |
| --- | --- |
| `SUPABASE_ACCESS_TOKEN` | Permission- and project-scoped PAT if supported by the CLI |
| `SUPABASE_DB_PASSWORD` | This target's database password |
| `SUPABASE_PROJECT_ID` | Exact 20-character Supabase project ref |

**These three variables are the complete required group configuration.**
`SUPABASE_PROJECT_ID` is the actual deployment target; there is no separate
`NS_SUPABASE_TARGET` label to maintain. If an older Codemagic group still
contains `NS_SUPABASE_TARGET`, the deployment script now **ignores it**;
you can safely delete that leftover variable from the group. Mark both
credentials **Secret** in Codemagic. Only trusted maintainers may edit this group or start privileged
builds. The YAML imports **only** the `ns_supabase_deploy` group. Input
values such as Function names are not credentials and must **never** contain
secrets.

**Environment isolation:** A single YAML workflow cannot safely select
one of multiple independently secured credential groups using a free-form
build input. Configure the jobs for staging first. For production, use an
independently permissioned Codemagic application/configuration importing
its own app-level group of the **same name** (or perform a separately
reviewed production configuration change). Never swap credentials in the
shared group in the middle of a release or expose both sets to one build.
If scoped PATs are unavailable, a broad PAT can reach more projects than
the group label implies; control access and keep the project-ref confirmation.

## Deploy database migrations

1. Merge the reviewed migration files into `main`; verify GitHub SQL/pgTAP
   CI. Back up the **correct** hosted project, inspect SQL effects and
   resolve any migration-history drift. In particular, the pending
   `20261025090000` migration deletes non-completed workout records, and
   the P2-05 backfill's `SET LOCAL TIMEZONE` requires transaction-level UTC
   verification before deployment. Avoid concurrent deployment runs.
2. In Codemagic, **Start new build** on `main` and select
   `supabase-database`, action `preview`. Leave both `NOT_SET`
   confirmation fields unchanged. Examine the output of
   `supabase migration list --linked` and `supabase db push --linked --dry-run`.
   Pending versions are expected; unexpected remote-only versions or
   malformed history stop the job.
3. After reviewing the preview and backup, rerun the **same** job with
   action `deploy`. Type the exact project ref in `confirm_project_ref`
   and the **full reviewed commit SHA** in `confirm_commit_sha`.
   The runner invokes `supabase db push --linked --yes`, which applies all
   locally committed, still-pending migration files in timestamp order.
   You **do not pass SQL paths**: the Supabase migration history identifies
   pending versions. The runner then rechecks the version list.
4. Check actual schema, UTC behavior, RLS and hosted Auth/RPC operations.
   An exit code or version match does **not** prove SQL integrity or safety.

Never rewrite an already-applied SQL migration. Add a new migration instead.
Do not automatically invoke `migration repair`, `db reset --linked`,
include seeds, or force remote history. If migration number N succeeds but
N+1 fails, stop, inspect the database, and make a new reviewed plan; don't
blindly rerun a destructive operation.

## Deploy Edge Functions

1. Ensure requested Function directories exist under
   `supabase/functions/<name>/index.ts`, with an explicit Boolean
   `[functions.<name>].verify_jwt` in `supabase/config.toml`.
   The runner validates *all* Function folders/config entries and the
   entire requested selection before deployment. **Every** deployable
   Function folder must have its own matching `config.toml` entry, even
   if it is not selected for this build. A single missing/mismatched entry
   intentionally blocks **all** Function deployments (fail-closed).
   `_shared` is not deployable. Use names (`delete-account another-func`),
   **not paths**. Python **3.11+** is required for `tomllib`; older
   versions fail with a clear error before linking.
2. Start `supabase-functions` on `main` with action `preview`.
   Leave both `NOT_SET` confirmation inputs unchanged and **replace**
   `SELECT_FUNCTION` in `function_names` with your space-separated
   selection. Leaving the placeholder unchanged fails safely with an
   actionable error; `delete-account` is **never** preselected.
   The runner first
   ensures every committed migration is recorded on the remote project.
   If any migration is pending or histories diverge, Function deployment
   is blocked; the CLI's `db push --dry-run` success is insufficient.
3. After Function-specific Auth/JWT and dependency review, rerun
   `supabase-functions` with action `deploy`, the same `function_names`,
   the exact `confirm_project_ref` and the **full reviewed**
   `confirm_commit_sha`. Selected Functions deploy sequentially with
   `supabase functions deploy <name> --use-api`. Pre-deploy selection
   validation is all-or-nothing, but **deployment is not atomic**: if one
   deploy fails, earlier Functions in the selection may already have
   been updated. Inspect their live versions and permissions before retrying.
4. Verify each Function's live JWT configuration and behavior. The runner
   never uses the global `--no-verify-jwt` option. `delete-account`
   intentionally has `verify_jwt=false` **only because the handler calls
   Auth.getUser and the recent-session SQL authorization gate**.
   Do not enable it for real accounts until the P2-08 deletion checks pass.

The runner is `scripts/codemagic_supabase.sh`; source/JWT validation is
in `scripts/check_supabase_functions.py`. The existing
`scripts/check_supabase_migrations.py` compares local/remote **versions**,
not file hashes or live schema. Tests in `tool/test_codemagic_config.py`
and `tool/test_codemagic_supabase.py` use a stub Supabase CLI.

## Recovery, limitations and release gates

For the previously connected development project, the 27 October inventory
showed 6 of 11 migrations and no deployed Functions. That is a dated snapshot,
**not** an instruction to mark all remaining versions as applied. Use
`supabase migration list --linked` and investigate schema drift before making
any repair; never automatically reconcile history.

Codemagic jobs are not a cross-run database lock. Operators must serialize
deployments, protect branch and app permissions, and keep backups. The jobs
currently use `mac_mini_m2`, available in the initial setup; moving to
`linux_x2` requires verifying Codemagic billing/availability. A green
migration push is **not** a Phase 2 release. Hosted signed-JWT owner isolation,
two-device sync, account deletion, all-history export and physical-device
security remain P2-08 gates.

References:
- [Codemagic build inputs](https://docs.codemagic.io/knowledge-codemagic/build-inputs/)
- [Codemagic protected environment groups](https://docs.codemagic.io/yaml-basic-configuration/configuring-environment-variables/)
- [Supabase database migrations](https://supabase.com/docs/guides/deployment/database-migrations)
- [Supabase Edge Function deployment](https://supabase.com/docs/guides/functions/deploy)
