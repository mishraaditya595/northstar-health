# ADE harness pilot — NorthStar Health

This PR adds an **isolated, non-deploying CI smoke test** of the [Agentic Development Environment](https://github.com/mishraaditya595/agentic-development-environment). It does not install ADE into NorthStar's committed source tree or change the existing agent agreement, Supabase data, Flutter dependencies, Android/iOS targets, or release workflows.

## What it tests

The GitHub Actions workflow checks out NorthStar and a pinned ADE revision into sibling temporary directories. It previews and runs ADE bootstrap, re-runs it for idempotency, ensures NorthStar's original `AGENTS.md` remains intact with a managed routing section added, and confirms `CLAUDE.md` still imports that agreement.

It then configures two **Python-only** checks via the harness: compiling `tool/` and `scripts/`, followed by NorthStar's existing protocol and repository unit tests. It checks the harness's doctor, evidence and session commands, including that an initial session status does not create a journal. Finally, it installs optional **personal-only** Claude hook settings in the temporary checkout and invokes the generated prompt hook command from `apps/mobile/`.

## Safety and scope

- This is a **pilot validation**, not a permanent ADE installation or CI-enforced harness policy.
- ADE source is pinned to commit `61c69fd786653151107a3a38b3eca0919a9481ad` to make the test reproducible; update it deliberately after reviewing future releases.
- No Supabase credentials are supplied. No database start/reset, migration, deployment, cloud sync, physical device, or native watch activity is performed.
- No Flutter SDK is installed in this job. Existing NorthStar CI remains responsible for Flutter analyze/test and native builds.
- The hook installer is opt-in and limited to `.claude/settings.local.json` in the temporary runner. This does **not** prove behavior in an interactive Claude or Codex session.
- The workflow requires read-only GitHub permissions. No push, merge or secrets are needed.

## What to do after CI succeeds

Review the CI logs for successful installation, unmodified original instructions and truthful check evidence. If the pilot is useful, plan a separate maintainer-approved PR to formally adopt ADE with a checked-in configuration and integrate Flutter, Supabase, and Android/watch verification as appropriately gated checks. Do not treat absent checks as passed or enable hooks for collaborators by default.
