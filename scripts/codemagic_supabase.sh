#!/usr/bin/env bash
# Manual Codemagic entry point for exactly two jobs: database or functions.
# Secrets are provided by a protected, project-bound Codemagic variable group.
set -euo pipefail
set +x

fail() { printf 'Supabase deployment blocked: %s\n' "$1" >&2; exit 1; }
require() { [[ -n "${!1:-}" ]] || fail "missing required setting $1"; }

[[ "$#" == 1 ]] || fail "expected database or functions job"
case "$1" in database|functions) job="$1" ;; *) fail "invalid job" ;; esac
[[ "${CM_TRIGGER_SOURCE:-}" == "api" ]] || fail "must be started manually in Codemagic"
[[ "${CM_BRANCH:-}" == "main" ]] || fail "main branch required"
require CM_BUILD_STARTED_BY

case "${NS_SUPABASE_ACTION:-}" in
  preview|deploy) ;;
  *) fail "invalid action (preview or deploy)" ;;
esac
for setting in SUPABASE_ACCESS_TOKEN SUPABASE_DB_PASSWORD SUPABASE_PROJECT_ID NS_SUPABASE_TARGET; do
  require "$setting"
done
[[ "$NS_SUPABASE_TARGET" == "staging" || "$NS_SUPABASE_TARGET" == "production" ]] ||
  fail "invalid target environment"
[[ "$SUPABASE_PROJECT_ID" =~ ^[a-z0-9]{20}$ ]] || fail "malformed Supabase project ref"

# Deployment requires an exact project ID and full reviewed commit SHA,
# explicitly supplied in this build. Reject a stale build/source revision.
# Preview remains read-only against the hosted project.
if [[ "$NS_SUPABASE_ACTION" == "deploy" ]]; then
  require NS_SUPABASE_CONFIRM_PROJECT_ID
  [[ "$NS_SUPABASE_CONFIRM_PROJECT_ID" == "$SUPABASE_PROJECT_ID" ]] ||
    fail "deployment project confirmation does not match protected credentials"
  require NS_SUPABASE_CONFIRM_COMMIT_SHA
  [[ "$NS_SUPABASE_CONFIRM_COMMIT_SHA" =~ ^[0-9a-f]{40}$ ]] ||
    fail "reviewed commit confirmation must be a full 40-character SHA"
  command -v git >/dev/null || fail "git is required for reviewed commit verification"
  current_sha="$(git rev-parse HEAD)" || fail "could not read checked-out commit"
  [[ "$NS_SUPABASE_CONFIRM_COMMIT_SHA" == "$current_sha" ]] ||
    fail "reviewed commit SHA does not match checked-out HEAD"
fi
[[ -f supabase/config.toml && -d supabase/migrations &&
   -d supabase/functions ]] || fail "must run from repository root"

command -v python3 >/dev/null || fail "Python 3.11+ is required"
python3 -c 'import sys; sys.exit(0 if sys.version_info >= (3, 11) else 1)' ||
  fail "Python 3.11+ is required (tomllib)"

# Validate all requested names and JWT policies before making any network calls.
if [[ "$job" == "functions" ]]; then
  require NS_SUPABASE_FUNCTIONS
  validated="$(python3 scripts/check_supabase_functions.py "$NS_SUPABASE_FUNCTIONS")" ||
    fail "invalid function selection/configuration"
  read -r -a selected_functions <<< "$validated"
fi

command -v npx >/dev/null || fail "Node.js/npx is required"
cli() { npx --yes supabase@2.81.3 "$@"; }
[[ "$(cli --version)" == "2.81.3" ]] || fail "unexpected Supabase CLI version"
cli link --project-ref "$SUPABASE_PROJECT_ID"

# Supabase tracks versions; this lightweight guard fails closed on history
# drift and on missing migrations before any Function deployment.
verify_history() {
  local history
  history="$(cli migration list --linked)" || fail "could not read migration history"
  if [[ "$1" == "report" ]]; then
    printf '%s\n' "$history" | python3 scripts/check_supabase_migrations.py --report-only ||
      fail "migration history differs from repository"
  else
    printf '%s\n' "$history" | python3 scripts/check_supabase_migrations.py ||
      fail "database migrations must be current before deploying functions"
  fi
}

if [[ "$job" == "database" ]]; then
  verify_history report
  cli db push --linked --dry-run
  if [[ "$NS_SUPABASE_ACTION" == "deploy" ]]; then
    # Supabase applies every outstanding file in timestamp order; no ad-hoc
    # SQL paths, seeds, migration repair, or database reset are accepted.
    cli db push --linked --yes
    verify_history strict
    echo "Migration deployment complete; hosted SQL/RLS QA remains required."
  else
    echo "Database preview complete; no hosted schema changes."
  fi
else
  # A successful db push dry-run is NOT proof that migrations are deployed.
  verify_history strict
  if [[ "$NS_SUPABASE_ACTION" == "deploy" ]]; then
    for name in "${selected_functions[@]}"; do
      # Respect per-function config.toml JWT settings; never override globally.
      cli functions deploy "$name" --project-ref "$SUPABASE_PROJECT_ID" --use-api
    done
    echo "Selected Edge Functions deployed; verify deployed JWT settings and Auth behavior."
  else
    printf 'Edge Function preview only (%s selected); nothing deployed.\n' "${#selected_functions[@]}"
  fi
fi
