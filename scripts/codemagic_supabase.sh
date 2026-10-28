#!/usr/bin/env bash
# Codemagic-only Supabase preview, migration and Edge Function deployments.
# All real credentials and approval values are supplied in encrypted
# Codemagic variable groups. Never print them or enable shell tracing.
set -euo pipefail
set +x

fail() { printf 'Supabase deployment blocked: %s\n' "$1" >&2; exit 1; }
require() { [[ -n "${!1:-}" ]] || fail "missing required setting $1"; }

# Do not allow a manual/API-triggered job to deploy PR/unreviewed source.
[[ "${CM_TRIGGER_SOURCE:-}" == "api" ]] || fail "must be started manually in Codemagic"
[[ "${CM_BRANCH:-}" == "main" ]] || fail "main branch required"
[[ -n "${CM_BUILD_STARTED_BY:-}" ]] || fail "initiator identity is missing"
case "${NS_SUPABASE_ACTION:-}" in
  preview|migrate|function) ;;
  *) fail "invalid action" ;;
esac
case "${NS_SUPABASE_TARGET:-}" in
  staging|production) ;;
  *) fail "invalid environment" ;;
esac
[[ "${NS_SUPABASE_GROUP_TARGET:-}" == "$NS_SUPABASE_TARGET" ]] ||
  fail "secret group does not match the requested environment"

for setting in SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD SUPABASE_PROJECT_ID; do
  require "$setting"
done
# Project refs are not secrets, but do not print one from a private group.
[[ "$SUPABASE_PROJECT_ID" =~ ^[a-z0-9]{20}$ ]] ||
  fail "malformed Supabase project reference"

[[ -f supabase/config.toml && -d supabase/migrations &&
   -d supabase/functions ]] ||
  fail "must be run from the reviewed repository root"

current_sha="$(git rev-parse HEAD)" || fail "git head unavailable"
[[ "$current_sha" =~ ^[0-9a-f]{40}$ ]] || fail "invalid git head"

if [[ "$NS_SUPABASE_ACTION" != "preview" ]]; then
  require NS_SUPABASE_APPROVED_SHA
  require NS_SUPABASE_APPROVED_PROJECT_ID
  [[ "$NS_SUPABASE_APPROVED_SHA" == "$current_sha" ]] ||
    fail "reviewed commit approval does not match the current build"
  [[ "$NS_SUPABASE_APPROVED_PROJECT_ID" == "$SUPABASE_PROJECT_ID" ]] ||
    fail "reviewed project approval does not match the secret group"
fi

if [[ "$NS_SUPABASE_ACTION" == "function" ]]; then
  # Separate acknowledgement, only granted after the matching migrations
  # have been applied and signed-JWT/deletion gates reviewed.
  require NS_SUPABASE_FUNCTION_APPROVED_SHA
  [[ "$NS_SUPABASE_FUNCTION_APPROVED_SHA" == "$current_sha" ]] ||
    fail "function-specific approval missing for this commit"
fi

command -v npx >/dev/null || fail "Node.js 20+ and npx are required"
command -v python3 >/dev/null || fail "Python 3 is required for migration reconciliation"
# Exact CLI version. npm global installation and CLI login are unnecessary.
cli() { npx --yes supabase@2.81.3 "$@"; }
[[ "$(cli --version)" == "2.81.3" ]] || fail "unexpected Supabase CLI version"

# SUPABASE_DB_PASSWORD is read from the environment by the CLI; never pass
# it as a command argument, write it to a file, or echo it.
cli link --project-ref "$SUPABASE_PROJECT_ID"

# All functions in this reviewed release must be listed here. Each newly
# added function requires owner/security review and its own migration contract.
FUNCTIONS=(delete-account)
for function_name in "${FUNCTIONS[@]}"; do
  [[ -f "supabase/functions/$function_name/index.ts" ]] ||
    fail "missing reviewed function source"
done

# `db push --dry-run` exits 0 even if there are unapplied migrations.
# Never equate its exit status with schema readiness. Require a complete,
# independently parsed local/remote migration version match instead.
verify_remote_migrations() {
  local mode="$1"
  local history
  history="$(cli migration list --linked)" ||
    fail "could not read linked migration history"
  if [[ "$mode" == "report" ]]; then
    # Preview parses the real CLI table even when versions are pending; it
    # never treats pending migrations as a deploy-ready database.
    printf '%s\n' "$history" | python3 scripts/check_supabase_migrations.py --report-only ||
      fail "could not reconcile linked migration list for preview"
  else
    printf '%s\n' "$history" | python3 scripts/check_supabase_migrations.py ||
      fail "linked database is not migration-current"
  fi
}

# Read-only preview surfaces migration ordering/drift before any writes.
cli db push --linked --dry-run

case "$NS_SUPABASE_ACTION" in
  preview)
    verify_remote_migrations report
    echo "Preview complete. No hosted migrations or Edge Functions deployed."
    ;;
  migrate)
    # Only unapplied migrations, never seeds, reset, repair or remote rollback.
    cli db push --linked --yes
    # Dry-run success is not proof; verify remote version history after push.
    verify_remote_migrations strict
    echo "Migration versions verified. Review hosted schema, UTC and RLS QA."
    ;;
  function)
    # Fail closed if even one migration is missing, or the history format is
    # unrecognized. No delete endpoint can deploy before its session gate.
    verify_remote_migrations strict
    # Each Function must enforce its own server-side Auth checks. The reviewed
    # delete-account handler uses Auth.getUser and a recent-session RPC.
    for function_name in "${FUNCTIONS[@]}"; do
      # Respect each function's verify_jwt setting in supabase/config.toml.
      # Never globally disable gateway verification for added functions.
      cli functions deploy "$function_name" --project-ref "$SUPABASE_PROJECT_ID" --use-api
    done
    echo "Edge Function deploy completed; real Auth/deletion tests still required."
    ;;
esac
