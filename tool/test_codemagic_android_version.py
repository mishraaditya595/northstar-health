"""Offline tests for the Google Play version name and versionCode resolver.

A local stub stands in for the Codemagic `google-play` CLI. These tests never
contact Google Play and use a fake, non-secret credentials value.
"""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "codemagic_android_version.py"
FAKE_CREDENTIALS = '{"type": "service_account", "fake": true}'

STUB = """#!/usr/bin/env python3
import json
import os
import sys
args = sys.argv[1:]
with open(os.environ['NS_FAKE_PLAY_LOG'], 'a', encoding='utf-8') as f:
    f.write(json.dumps(args) + '\\n')
if args[:1] == ['get-latest-build-number']:
    if os.environ.get('NS_FAKE_LATEST_FAIL') == '1':
        print('API error', file=sys.stderr)
        sys.exit(2)
    print(os.environ.get('NS_FAKE_LATEST', ''))
    sys.exit(0)
sys.exit(9)
"""


class AndroidVersionResolverTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        temp = Path(self.tmp.name)
        stub = temp / "google-play"
        stub.write_text(STUB, encoding="utf-8")
        stub.chmod(0o755)
        self.log = temp / "calls.log"
        self.cm_env = temp / "cm_env"
        self.cm_env.write_text("", encoding="utf-8")
        self.pubspec = temp / "pubspec.yaml"
        self.pubspec.write_text(
            "name: beyondrep\nversion: 0.3.1+7\n", encoding="utf-8"
        )
        self.path = f"{temp}{os.pathsep}{os.environ['PATH']}"

    def run_resolver(self, version="AUTO", build="AUTO", track="internal", **extra):
        env = {
            "PATH": self.path,
            "HOME": self.tmp.name,
            "CM_ENV": str(self.cm_env),
            "NS_FAKE_PLAY_LOG": str(self.log),
            "NS_VERSION_NAME": version,
            "NS_BUILD_NUMBER": build,
            "NS_PLAY_TRACK": track,
            "NS_FAKE_LATEST": "41",
            "GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS": FAKE_CREDENTIALS,
        }
        env.update(extra)
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(self.pubspec)],
            env=env, capture_output=True, text=True,
        )

    def exported(self):
        values = {}
        for line in self.cm_env.read_text(encoding="utf-8").splitlines():
            key, _, value = line.partition("=")
            values[key] = value
        return values

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_auto_uses_pubspec_version_and_latest_play_build_plus_one(self):
        result = self.run_resolver()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.exported(),
            {"BEYONDREP_VERSION_NAME": "0.3.1", "BEYONDREP_BUILD_NUMBER": "42"},
        )
        call = self.calls()[0]
        self.assertEqual(call[:3], ["get-latest-build-number", "--package-name", "in.beyondrep.app"])
        self.assertIn("--include-uploaded-builds", call)
        # The credentials are passed by reference, never on the command line.
        self.assertIn("@env:GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS", call)
        self.assertNotIn(FAKE_CREDENTIALS, result.stdout + result.stderr)

    def test_no_previous_build_starts_at_one(self):
        result = self.run_resolver(NS_FAKE_LATEST="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.exported()["BEYONDREP_BUILD_NUMBER"], "1")

    def test_manual_values_are_kept_when_higher(self):
        result = self.run_resolver(version="1.2.0", build="50")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.exported(),
            {"BEYONDREP_VERSION_NAME": "1.2.0", "BEYONDREP_BUILD_NUMBER": "50"},
        )

    def test_manual_build_not_above_latest_fails(self):
        result = self.run_resolver(build="41")
        self.assertEqual(result.returncode, 1)
        self.assertIn("higher than the latest Google Play build, 41", result.stderr)
        self.assertEqual(self.exported(), {})

    def test_invalid_inputs_fail_before_lookup(self):
        for kwargs in (
            {"build": "007"},
            {"build": "0"},
            {"build": "2100000001"},
            {"version": "1.2.3.4"},
            {"track": "production"},
            {"track": ""},
        ):
            with self.subTest(**kwargs):
                result = self.run_resolver(**kwargs)
                self.assertEqual(result.returncode, 1)
                self.assertEqual(self.exported(), {})
        self.assertEqual(self.calls(), [])

    def test_lookup_failure_fails_auto_and_uploads(self):
        for kwargs in (
            {"build": "AUTO", "track": "none"},
            {"build": "5", "track": "internal"},
        ):
            with self.subTest(**kwargs):
                result = self.run_resolver(NS_FAKE_LATEST_FAIL="1", **kwargs)
                self.assertEqual(result.returncode, 1)
                self.assertIn("Google Play lookup failed", result.stderr)
        self.assertEqual(self.exported(), {})

    def test_first_manual_build_without_upload_survives_lookup_failure(self):
        result = self.run_resolver(build="1", track="none", NS_FAKE_LATEST_FAIL="1")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.exported()["BEYONDREP_BUILD_NUMBER"], "1")

    def test_missing_credentials(self):
        blank = {"GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS": ""}
        for kwargs in (
            {"build": "AUTO", "track": "none"},
            {"build": "3", "track": "alpha"},
        ):
            with self.subTest(**kwargs):
                result = self.run_resolver(**kwargs, **blank)
                self.assertEqual(result.returncode, 1)
                self.assertIn("is not set", result.stderr)
        self.assertEqual(self.exported(), {})
        result = self.run_resolver(build="1", track="none", **blank)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.exported()["BEYONDREP_BUILD_NUMBER"], "1")
        self.assertEqual(self.calls(), [])


if __name__ == "__main__":
    unittest.main()
