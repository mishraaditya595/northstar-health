"""Offline execution tests: never connect to Supabase or Codemagic.

A stub npx records CLI argument *names*, never secrets. Real remote deploys
must be approved and tested separately by the human maintainer.
"""
from pathlib import Path
import json
import os
import re
import shlex
import subprocess
import tempfile
import tomllib
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "codemagic_supabase.sh"
REF = "abcdefghijklmnopqrst"
SHA = subprocess.run(
    ["git", "rev-parse", "HEAD"],
    cwd=ROOT,
    text=True,
    capture_output=True,
    check=True,
).stdout.strip()


class SupabaseCodemagicTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        root = Path(self.tmp.name)
        self.log = root / "cli.log"
        stub = root / "npx"
        stub.write_text(
            """#!/usr/bin/env python3
import glob
import json
import os
import sys
args = sys.argv[1:]
log = os.environ['NS_FAKE_NPX_LOG']
with open(log, 'a', encoding='utf-8') as f:
    f.write(json.dumps(args) + '\\n')
if '--version' in args:
    print('2.81.3')
if 'db' in args and 'push' in args and '--dry-run' not in args:
    if os.environ.get('NS_FAKE_FAIL_PUSH') == '1':
        sys.exit(3)
if 'migration' in args and 'list' in args:
    state = os.environ.get('NS_FAKE_REMOTE_STATE', 'current')
    if state == 'unparseable':
        print('response format unexpectedly changed')
        sys.exit(0)
    if state == 'list_error':
        sys.exit(3)
    applied_push = False
    with open(log, encoding='utf-8') as f:
        for line in f:
            previous = json.loads(line)
            if 'db' in previous and 'push' in previous and '--dry-run' not in previous:
                applied_push = True
    versions = sorted(
        os.path.basename(path).split('_', 1)[0]
        for path in glob.glob('supabase/migrations/*.sql')
    )
    print('        Local           |          Remote         | Time (UTC)')
    print('------------------------|-------------------------|------------')
    for i, version in enumerate(versions):
        remote = version
        if state in ('pending', 'stuck_after_push') and i == len(versions) - 1:
            if state == 'pending' and applied_push:
                remote = version
            else:
                remote = ''
        if state == 'drift' and i == len(versions) - 1:
            remote = '19990101000000'
        print(f' {version} | {remote} | 2026-10-28')
""",
            encoding="utf-8",
        )
        stub.chmod(0o700)
        self.env = {
            **os.environ,
            "PATH": str(root) + os.pathsep + os.environ["PATH"],
            "NS_FAKE_NPX_LOG": str(self.log),
            "CM_TRIGGER_SOURCE": "api",
            "CM_BRANCH": "main",
            "CM_BUILD_STARTED_BY": "maintainer@example.invalid",
            "NS_SUPABASE_ACTION": "preview",
            "NS_SUPABASE_TARGET": "staging",
            "NS_SUPABASE_GROUP_TARGET": "staging",
            "SUPABASE_ACCESS_TOKEN": "synthetic-access-token",
            "SUPABASE_DB_PASSWORD": "synthetic-db-password",
            "SUPABASE_PROJECT_ID": REF,
            "NS_SUPABASE_APPROVED_SHA": SHA,
            "NS_SUPABASE_APPROVED_PROJECT_ID": REF,
            "NS_SUPABASE_FUNCTION_APPROVED_SHA": SHA,
        }

    def run_shell(self, **overrides):
        env = {**self.env, **overrides}
        result = subprocess.run(
            ["bash", str(SCRIPT)], cwd=ROOT, env=env,
            capture_output=True, text=True, check=False, timeout=20,
        )
        output = result.stdout + result.stderr
        # This only catches accidental echo in the runner: the fake CLI never
        # prints credentials, so it does NOT prove real CLI log-redaction.
        for name in ("SUPABASE_ACCESS_TOKEN", "SUPABASE_DB_PASSWORD"):
            value = env.get(name)
            if value:  # The empty string is present in every Python string.
                self.assertNotIn(value, output)
        return result

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_preview_only_links_and_dry_runs(self):
        result = self.run_shell()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls(), [
            ["--yes", "supabase@2.81.3", "--version"],
            ["--yes", "supabase@2.81.3", "link", "--project-ref", REF],
            ["--yes", "supabase@2.81.3", "db", "push", "--linked", "--dry-run"],
            ["--yes", "supabase@2.81.3", "migration", "list", "--linked"],
        ])

    def test_migrations_are_separate_from_function_deploy(self):
        result = self.run_shell(NS_SUPABASE_ACTION="migrate")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-2:], [
            ["--yes", "supabase@2.81.3", "db", "push", "--linked", "--yes"],
            ["--yes", "supabase@2.81.3", "migration", "list", "--linked"],
        ])
        self.assertFalse(any("functions" in c for c in self.calls()))

    def test_function_requires_separate_approval_and_never_pushes_db(self):
        result = self.run_shell(NS_SUPABASE_ACTION="function")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.calls()[-1], [
            "--yes", "supabase@2.81.3", "functions", "deploy", "delete-account",
            "--project-ref", REF, "--use-api",
        ])
        self.assertEqual(
            sum("push" in args for args in self.calls()), 1,
        )  # dry-run only; linked migration list additionally verifies parity
        for args in self.calls():
            self.assertNotIn("--no-verify-jwt", args)
        config = tomllib.loads(
            (ROOT / "supabase" / "config.toml").read_text(encoding="utf-8")
        )
        self.assertIs(
            config["functions"]["delete-account"]["verify_jwt"], False
        )  # Only this reviewed function explicitly disables the gateway check.

    def test_every_deployed_function_has_source_and_explicit_jwt_policy(self):
        # Read the actual deploy allowlist instead of assuming it contains
        # only delete-account. Newly added names must be reviewed in TOML.
        script = SCRIPT.read_text(encoding="utf-8")
        matches = re.findall(r"(?m)^FUNCTIONS=\(([^)\n]*)\)$", script)
        self.assertEqual(len(matches), 1, "one literal FUNCTIONS allowlist required")
        function_names = shlex.split(matches[0])
        self.assertTrue(function_names, "deployment allowlist must not be empty")
        self.assertEqual(len(function_names), len(set(function_names)))
        config = tomllib.loads(
            (ROOT / "supabase" / "config.toml").read_text(encoding="utf-8")
        )
        policies = config["functions"]
        # Compare in both directions: an unlisted Function folder or TOML
        # entry must fail CI just as a missing source/config entry does.
        # _shared is Supabase's conventional reusable-code directory,
        # not an independently deployable Edge Function.
        source_folders = {
            entry.name
            for entry in (ROOT / "supabase" / "functions").iterdir()
            if entry.is_dir() and entry.name != "_shared"
        }
        self.assertSetEqual(
            set(function_names),
            source_folders,
            "every Function directory must appear exactly once in FUNCTIONS",
        )
        self.assertSetEqual(
            set(function_names),
            set(policies),
            "every config.toml Function entry must appear in FUNCTIONS",
        )
        for name in function_names:
            with self.subTest(function=name):
                self.assertRegex(name, r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
                self.assertTrue(
                    (ROOT / "supabase" / "functions" / name / "index.ts").is_file(),
                    f"missing deploy source for {name}",
                )
                self.assertIn(name, policies, f"missing config.toml policy for {name}")
                self.assertIn(
                    "verify_jwt", policies[name],
                    f"missing explicit JWT policy for {name}",
                )
                self.assertIsInstance(policies[name]["verify_jwt"], bool)

    def test_wrong_or_missing_manual_runtime_context_is_blocked(self):
        cases = (
            ({"CM_TRIGGER_SOURCE": "webhook"}, "must be started manually"),
            ({"CM_BRANCH": "feature/pr"}, "main branch required"),
            ({"CM_BUILD_STARTED_BY": ""}, "initiator identity"),
            ({"NS_SUPABASE_GROUP_TARGET": "production"}, "does not match"),
            ({"NS_SUPABASE_ACTION": "unknown"}, "invalid action"),
            ({"SUPABASE_ACCESS_TOKEN": ""}, "missing required setting"),
            ({"SUPABASE_DB_PASSWORD": ""}, "missing required setting"),
            ({"SUPABASE_PROJECT_ID": ""}, "missing required setting"),
            ({"SUPABASE_PROJECT_ID": "bad-ref"}, "malformed"),
        )
        for changes, reason in cases:
            with self.subTest(changes=changes):
                result = self.run_shell(**changes)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(reason, result.stderr)
                self.assertEqual(self.calls(), [])

    def test_deploy_requires_matching_reviewed_commit_and_project(self):
        cases = (
            ({"NS_SUPABASE_APPROVED_SHA": ""}, "missing required setting"),
            ({"NS_SUPABASE_APPROVED_SHA": "0" * 40}, "does not match"),
            ({"NS_SUPABASE_APPROVED_PROJECT_ID": REF[::-1]}, "does not match"),
        )
        for changes, reason in cases:
            with self.subTest(changes=changes):
                result = self.run_shell(NS_SUPABASE_ACTION="migrate", **changes)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn(reason, result.stderr)
                self.assertEqual(self.calls(), [])

    def test_function_deploy_denied_without_distinct_approval(self):
        result = self.run_shell(
            NS_SUPABASE_ACTION="function",
            NS_SUPABASE_FUNCTION_APPROVED_SHA="",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing required setting", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_cli_failure_halts_before_later_operation(self):
        result = self.run_shell(
            NS_SUPABASE_ACTION="migrate",
            NS_FAKE_FAIL_PUSH="1",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(
            self.calls()[-1],
            ["--yes", "supabase@2.81.3", "db", "push", "--linked", "--yes"],
        )

    def test_production_requires_matching_group_and_sha(self):
        production = {
            "NS_SUPABASE_TARGET": "production",
            "NS_SUPABASE_GROUP_TARGET": "production",
        }
        preview = self.run_shell(**production)
        self.assertEqual(preview.returncode, 0, preview.stderr)
        self.log.unlink()
        wrong_sha = self.run_shell(
            **production, NS_SUPABASE_ACTION="migrate",
            NS_SUPABASE_APPROVED_SHA="0" * 40,
        )
        self.assertNotEqual(wrong_sha.returncode, 0)
        self.assertIn("reviewed commit approval does not match", wrong_sha.stderr)
        self.assertEqual(self.calls(), [])
        wrong_group = self.run_shell(
            NS_SUPABASE_TARGET="production",
            NS_SUPABASE_GROUP_TARGET="staging",
            NS_SUPABASE_ACTION="migrate",
        )
        self.assertNotEqual(wrong_group.returncode, 0)
        self.assertIn("secret group does not match", wrong_group.stderr)
        self.assertEqual(self.calls(), [])

    def test_function_refuses_pending_migration_even_when_dry_run_exits_zero(self):
        result = self.run_shell(
            NS_SUPABASE_ACTION="function",
            NS_FAKE_REMOTE_STATE="pending",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("migration(s) still pending", result.stderr)
        self.assertFalse(any("functions" in args for args in self.calls()))

    def test_function_refuses_drift_or_unrecognized_listing(self):
        for state in ("drift", "unparseable", "list_error"):
            with self.subTest(state=state):
                if self.log.exists():
                    self.log.unlink()
                result = self.run_shell(
                    NS_SUPABASE_ACTION="function", NS_FAKE_REMOTE_STATE=state,
                )
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse(any("functions" in args for args in self.calls()))

    def test_post_migration_missing_remote_version_is_failure(self):
        result = self.run_shell(
            NS_SUPABASE_ACTION="migrate",
            NS_FAKE_REMOTE_STATE="stuck_after_push",
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("migration(s) still pending", result.stderr)
        self.assertFalse(any("functions" in args for args in self.calls()))
        self.assertEqual(
            self.calls()[-1],
            ["--yes", "supabase@2.81.3", "migration", "list", "--linked"],
        )

    def test_preview_does_not_claim_approval_with_pending_remote_versions(self):
        result = self.run_shell(NS_FAKE_REMOTE_STATE="pending")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("Verified", result.stdout)
        self.assertIn("1 pending", result.stdout)
        self.assertEqual(
            self.calls()[-1],
            ["--yes", "supabase@2.81.3", "migration", "list", "--linked"],
        )
        self.assertFalse(any(
            "functions" in args for args in self.calls()
        ))

    def test_preview_rejects_unparseable_real_cli_table_safely(self):
        result = self.run_shell(NS_FAKE_REMOTE_STATE="unparseable")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("could not reconcile linked migration list", result.stderr)
        self.assertEqual(
            self.calls()[-1],
            ["--yes", "supabase@2.81.3", "migration", "list", "--linked"],
        )


if __name__ == "__main__":
    unittest.main()
