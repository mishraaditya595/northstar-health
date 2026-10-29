# Semgrep security scanning

`.github/workflows/semgrep.yml` runs Semgrep AppSec Platform scans on same-repository pull requests, pushes to `main`, nightly at 15:12 UTC (20:42 IST), and manual dispatch. It complements — and does not replace — Flutter analysis/tests and Supabase SQL/RLS checks.

## One-time setup (maintainer)

1. In [Semgrep AppSec Platform](https://semgrep.dev), connect `mishraaditya595/northstar-health` and configure the code-scanning rules and policies that should run in CI.
2. In Semgrep AppSec Platform **Settings**, generate a CI/deployment API token. Treat it as a secret; do not commit it or paste it into issues, PRs, logs, or documentation.
3. In this repository, open **Settings → Secrets and variables → Actions → New repository secret**, name it `SEMGREP_APP_TOKEN`, and paste the token as the value. Confirm the secret is available to this workflow.
4. Trigger a same-repository PR scan and inspect both the GitHub Actions logs (actual rule/target counts and completion) and the Semgrep findings dashboard. A green result alone does not prove that any rules were enabled.
5. Configure high-confidence rules/policies in **Block** mode if they should fail the check. Monitor/comment-only findings are reported without blocking. Only make `semgrep/ci` a required status check after both smoke tests below pass.

## Validation / fail-closed smoke tests

- **Missing token:** In a controlled test, temporarily remove or rename the repository secret and trigger a fresh same-repository PR run. `Require Semgrep token` must fail with `SEMGREP_APP_TOKEN is not configured`; it must **not** show a green Semgrep scan. Restore the token immediately after the test.
- **Blocking detection:** With the token restored, enable an appropriate hard-coded-credential **Block** rule in Semgrep. Add a *synthetic, nonworking* hard-coded `password = "semgrep-test-only-not-a-real-secret"` to a temporary scratch PR branch in a language the enabled rule scans. Verify the job reports a blocking finding and fails. Remove the synthetic test code afterward; verify a clean follow-up run. Do not use a real credential.
- **Successful scan:** Confirm the log reports an actual completed scan and rules/targets analyzed, not just an exit code of zero. Confirm the corresponding Semgrep dashboard scan.

The workflow explicitly rejects an empty token and runs `semgrep ci --no-suppress-errors`, so scanner errors (including rejected credentials) are not silently treated as success. This option may also fail on parser errors; assess any such error instead of suppressing it automatically. If no rules are configured in the platform, scans can still yield no findings, so the positive detection test is necessary.

## Trust boundary and limitations

Fork PRs and Dependabot PRs intentionally **skip** the Semgrep job because repository secrets are not available to them. GitHub can count a skipped job as successful for required checks. Their merged code is scanned on the next `main` push and in nightly scans; this is a deliberate tradeoff, not equivalent to pre-merge protection. Other PR checks and human review still apply.

Semgrep only blocks findings covered by enabled blocking policies. Keep policy configuration under review and re-run the smoke tests when the token, scanning policies, or workflow change. `semgrep/semgrep` currently tracks upstream updates; changing the scanner version or adding a `.semgrepignore` should be separately reviewed for changes in coverage.

## GitHub Actions supply-chain protections

Workflow steps that use third-party GitHub Actions are pinned to verified full commit SHAs rather than mutable version tags or branches. A contract test in `tool/test_workflow_action_pins.py` rejects unpinned external actions, including new workflow files. The readable trailing version comments describe the pinned release or version branch; they do not affect execution.

Dependabot checks pinned GitHub Actions for updates every week through `.github/dependabot.yml`. Review proposed changes and their upstream release notes before merging. The Semgrep workflow currently skips Dependabot PRs because it needs a repository secret, so a passing/skipped Semgrep check on those PRs is **not** security approval; other PR checks and manual review still apply.
