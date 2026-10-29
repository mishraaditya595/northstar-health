"""Offline tests for the two manual Supabase Codemagic deployment jobs.

A local stub simulates the Supabase CLI. These tests never deploy anything.
"""
from pathlib import Path
import json
import os
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "codemagic_supabase.sh"
VALIDATOR = ROOT / "scripts" / "check_supabase_functions.py"
REF = "abcdefghijklmnopqrst"
SHA = subprocess.run(
    ["git", "rev-parse", "HEAD"], cwd=ROOT,
    capture_output=True, text=True, check=True,
).stdout.strip()


class SupabaseCodemagicTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        temp = Path(self.tmp.name)
        self.log = temp / "calls.log"
        stub = temp / "npx"
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
    if state == 'list_error':
        sys.exit(3)
    if state == 'unparseable':
        print('unexpected output format')
        sys.exit(0)
    with open(log, encoding='utf-8') as f:
        pushed = any(
            'db' in (previous := json.loads(line))
            and 'push' in previous and '--dry-run' not in previous
            for line in f
        )
    versions = sorted(
        os.path.basename(path).split('_', 1)[0]
        for path in glob.glob('supabase/migrations/*.sql')
    )
    print(' Local | Remote | Time (UTC)')
    print('-------|--------|-----------')
    for i, version in enumerate(versions):
        remote = version
        if state in ('pending', 'stuck_after_push') and i == len(versions) - 1:
            if state == 'stuck_after_push' or not pushed:
                remote = ''
        if state == 'drift' and i == len(versions) - 1:
            remote = '19990101000000'
        print(f' {version} | {remote} | 2026-10-29')
""",
            encoding="utf-8",
        )
        stub.chmod(0o700)
        self.env = {
            **os.environ,
            "PATH": str(temp) + os.pathsep + os.environ["PATH"],
            "NS_FAKE_NPX_LOG": str(self.log),
            "CM_TRIGGER_SOURCE": "api",
            "CM_BRANCH": "main",
            "CM_BUILD_STARTED_BY": "maintainer@example.invalid",
            "SUPABASE_ACCESS_TOKEN": "synthetic-access-token",
            "SUPABASE_DB_PASSWORD": "synthetic-db-password",
            "SUPABASE_PROJECT_ID": REF,
            "NS_SUPABASE_ACTION": "preview",
            "NS_SUPABASE_CONFIRM_PROJECT_ID": "",
            "NS_SUPABASE_CONFIRM_COMMIT_SHA": "",
            "NS_SUPABASE_FUNCTIONS": "delete-account",
        }
        # The inherited runner environment must not supply a legacy label.
        self.env.pop("NS_SUPABASE_TARGET", None)

    def run_job(self, job="database", **override):
        env = {**self.env, **override}
        result = subprocess.run(
            ["bash", str(SCRIPT), job], cwd=ROOT, env=env,
            capture_output=True, text=True, timeout=20, check=False,
        )
        for name in ("SUPABASE_ACCESS_TOKEN", "SUPABASE_DB_PASSWORD"):
            value = env.get(name)
            if value:
                self.assertNotIn(value, result.stdout + result.stderr)
        return result

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(l) for l in self.log.read_text().splitlines()]

    def test_database_preview_reports_pending_but_does_not_write(self):
        r = self.run_job(NS_FAKE_REMOTE_STATE="pending")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertIn("1 pending", r.stdout)
        self.assertEqual(self.calls()[-1], [
            "--yes", "supabase@2.81.3", "db", "push", "--linked", "--dry-run"
        ])
        self.assertFalse(any("functions" in c for c in self.calls()))

    def test_database_deploy_only_pushes_pending_and_verifies(self):
        r = self.run_job(NS_SUPABASE_ACTION="deploy", NS_SUPABASE_CONFIRM_PROJECT_ID=REF,
                         NS_SUPABASE_CONFIRM_COMMIT_SHA=SHA, NS_FAKE_REMOTE_STATE="pending")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.calls()[-2:], [
            ["--yes", "supabase@2.81.3", "db", "push", "--linked", "--yes"],
            ["--yes", "supabase@2.81.3", "migration", "list", "--linked"],
        ])
        self.assertFalse(any("functions" in c for c in self.calls()))

    def test_function_preview_does_not_push_or_deploy(self):
        r = self.run_job("functions")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(self.calls()[-1][-3:] == ["migration", "list", "--linked"])
        self.assertFalse(any("push" in c or "functions" in c for c in self.calls()))

    def test_function_deploy_uses_only_selected_name_and_no_global_jwt_flag(self):
        r = self.run_job("functions", NS_SUPABASE_ACTION="deploy",
                         NS_SUPABASE_CONFIRM_PROJECT_ID=REF,
                         NS_SUPABASE_CONFIRM_COMMIT_SHA=SHA)
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertEqual(self.calls()[-1], [
            "--yes", "supabase@2.81.3", "functions", "deploy",
            "delete-account", "--project-ref", REF, "--use-api",
        ])
        self.assertFalse(any("--no-verify-jwt" in c for c in self.calls()))
        self.assertFalse(any("push" in c for c in self.calls()))

    def test_rejects_webhooks_unreviewed_branch_missing_credentials_and_bad_action(self):
        cases = (
            ({"CM_TRIGGER_SOURCE": "webhook"}, "must be started manually"),
            ({"CM_BRANCH": "feature"}, "main branch"),
            ({"CM_BUILD_STARTED_BY": ""}, "missing required"),
            ({"NS_SUPABASE_ACTION": "migrate"}, "invalid action"),
            ({"SUPABASE_PROJECT_ID": "bad"}, "malformed"),
            ({"SUPABASE_DB_PASSWORD": ""}, "missing required"),
            ({"SUPABASE_ACCESS_TOKEN": ""}, "missing required"),
        )
        for env, reason in cases:
            with self.subTest(env=env):
                if self.log.exists():
                    self.log.unlink()
                r = self.run_job(**env)
                self.assertNotEqual(r.returncode, 0)
                self.assertIn(reason, r.stderr)
                self.assertEqual(self.calls(), [])

    def test_no_target_label_is_required_or_enforced(self):
        # The linked Supabase project ref is the actual deployment target.
        # A stale custom target label must have no impact on either job.
        self.assertNotIn("NS_SUPABASE_TARGET", self.env)
        for job in ("database", "functions"):
            for label in (None, "not-a-real-environment"):
                with self.subTest(job=job, label=label):
                    if self.log.exists():
                        self.log.unlink()
                    overrides = {} if label is None else {"NS_SUPABASE_TARGET": label}
                    preview = self.run_job(job, **overrides)
                    self.assertEqual(preview.returncode, 0, preview.stderr)
                    self.assertTrue(self.calls())
                    self.assertFalse(
                        any("functions" in call or
                            ("push" in call and "--dry-run" not in call)
                            for call in self.calls())
                    )
        # Existing deploy tests verify that project + reviewed SHA
        # confirmations remain mandatory without the legacy target label.

    def test_deploy_needs_exact_project_confirmation(self):
        for job in ("database", "functions"):
            for value in ("", "0" * 20):
                with self.subTest(job=job, value=value):
                    if self.log.exists():
                        self.log.unlink()
                    r = self.run_job(job, NS_SUPABASE_ACTION="deploy",
                                     NS_SUPABASE_CONFIRM_COMMIT_SHA=SHA,
                                     NS_SUPABASE_CONFIRM_PROJECT_ID=value)
                    self.assertNotEqual(r.returncode, 0)
                    self.assertEqual(self.calls(), [])

    def test_deploy_requires_exact_reviewed_commit_on_both_jobs(self):
        for job in ("database", "functions"):
            for value in ("", "0" * 40, SHA[:12], "G" * 40):
                with self.subTest(job=job, confirm_commit_sha=value):
                    if self.log.exists():
                        self.log.unlink()
                    r = self.run_job(
                        job, NS_SUPABASE_ACTION="deploy",
                        NS_SUPABASE_CONFIRM_PROJECT_ID=REF,
                        NS_SUPABASE_CONFIRM_COMMIT_SHA=value,
                    )
                    self.assertNotEqual(r.returncode, 0)
                    self.assertIn("commit", r.stderr.lower())
                    self.assertEqual(self.calls(), [])

    def test_preview_does_not_require_reviewed_commit(self):
        for job in ("database", "functions"):
            with self.subTest(job=job):
                if self.log.exists():
                    self.log.unlink()
                r = self.run_job(job, NS_SUPABASE_CONFIRM_COMMIT_SHA="")
                self.assertEqual(r.returncode, 0, r.stderr)

    def test_function_selection_is_explicit_even_for_preview(self):
        r = self.run_job("functions", NS_SUPABASE_FUNCTIONS="")
        self.assertNotEqual(r.returncode, 0)
        self.assertEqual(self.calls(), [])
        self.assertIn("missing required setting NS_SUPABASE_FUNCTIONS", r.stderr)

    def test_python_older_than_311_fails_before_link(self):
        fake_py = Path(self.tmp.name) / "python3"
        fake_py.write_text(
            '#!/bin/sh\nif [ "$1" = "-c" ]; then exit 1; fi\nexit 99\n',
            encoding="utf-8",
        )
        fake_py.chmod(0o700)
        result = self.run_job("functions")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Python 3.11+ is required", result.stderr)
        self.assertEqual(self.calls(), [])

    def test_a_missing_function_config_blocks_other_valid_selections(self):
        from scripts.check_supabase_functions import validate
        local = Path(self.tmp.name) / "sandbox"
        source = local / "supabase" / "functions"
        for name in ("valid-func", "missing-config"):
            folder = source / name
            folder.mkdir(parents=True)
            (folder / "index.ts").write_text("export {};", encoding="utf-8")
        (local / "supabase" / "config.toml").write_text(
            "[functions.valid-func]\nverify_jwt = true\n", encoding="utf-8"
        )
        with self.assertRaisesRegex(ValueError, "source/config lists differ"):
            validate("valid-func", root=local)

    def test_function_validation_fails_closed_before_linking(self):
        for selection in ("", "../delete-account", "delete-account delete-account",
                          "not-a-function", "delete-account;echo-hello",
                          "delete-account _shared"):
            with self.subTest(selection=selection):
                if self.log.exists():
                    self.log.unlink()
                r = self.run_job("functions", NS_SUPABASE_FUNCTIONS=selection)
                self.assertNotEqual(r.returncode, 0)
                self.assertEqual(self.calls(), [])

    def test_function_requires_all_migrations_even_in_preview(self):
        for state in ("pending", "drift", "unparseable", "list_error"):
            with self.subTest(state=state):
                if self.log.exists():
                    self.log.unlink()
                r = self.run_job("functions", NS_FAKE_REMOTE_STATE=state)
                self.assertNotEqual(r.returncode, 0)
                self.assertFalse(any("functions" in c for c in self.calls()))

    def test_database_preview_rejects_remote_drift_or_broken_listing(self):
        for state in ("drift", "unparseable", "list_error"):
            with self.subTest(state=state):
                if self.log.exists():
                    self.log.unlink()
                r = self.run_job(NS_FAKE_REMOTE_STATE=state)
                self.assertNotEqual(r.returncode, 0)
                self.assertFalse(any("db" in c for c in self.calls()))

    def test_database_failed_push_or_missing_post_version_is_failure(self):
        for changes in ({"NS_FAKE_FAIL_PUSH": "1"},
                        {"NS_FAKE_REMOTE_STATE": "stuck_after_push"}):
            with self.subTest(changes=changes):
                if self.log.exists():
                    self.log.unlink()
                r = self.run_job(NS_SUPABASE_ACTION="deploy",
                                 NS_SUPABASE_CONFIRM_PROJECT_ID=REF,
                                 NS_SUPABASE_CONFIRM_COMMIT_SHA=SHA, **changes)
                self.assertNotEqual(r.returncode, 0)
                self.assertFalse(any("functions" in c for c in self.calls()))

    def test_repo_function_source_and_config_are_bijective(self):
        result = subprocess.run(
            ["python3", str(VALIDATOR), "delete-account"],
            cwd=ROOT, text=True, capture_output=True, check=False,
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(result.stdout.strip(), "delete-account")


if __name__ == "__main__":
    unittest.main()
