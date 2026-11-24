"""Offline tests for the TestFlight version name and build number resolver.

A local stub stands in for the Codemagic `app-store-connect` CLI. These tests
never contact App Store Connect.
"""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "codemagic_ios_version.py"

STUB = """#!/usr/bin/env python3
import json
import os
import sys
args = sys.argv[1:]
with open(os.environ['NS_FAKE_ASC_LOG'], 'a', encoding='utf-8') as f:
    f.write(json.dumps(args) + '\\n')
if args[:2] == ['apps', 'list']:
    if os.environ.get('NS_FAKE_APP_MISSING') == '1':
        print('[]')
    else:
        print(json.dumps([{'id': '6700000001', 'type': 'apps'}]))
    sys.exit(0)
if args[:1] == ['get-latest-testflight-build-number']:
    if os.environ.get('NS_FAKE_LATEST_FAIL') == '1':
        print('API error', file=sys.stderr)
        sys.exit(2)
    print(os.environ.get('NS_FAKE_LATEST', ''))
    sys.exit(0)
sys.exit(9)
"""


class IosVersionResolverTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        temp = Path(self.tmp.name)
        stub = temp / "app-store-connect"
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

    def run_resolver(self, version="AUTO", build="AUTO", **extra):
        env = {
            "PATH": self.path,
            "HOME": self.tmp.name,
            "CM_ENV": str(self.cm_env),
            "NS_FAKE_ASC_LOG": str(self.log),
            "NS_VERSION_NAME": version,
            "NS_BUILD_NUMBER": build,
            "NS_FAKE_LATEST": "41",
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

    def test_auto_uses_pubspec_version_and_next_testflight_build(self):
        result = self.run_resolver()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.exported(),
            {"BEYONDREP_VERSION_NAME": "0.3.1", "BEYONDREP_BUILD_NUMBER": "42"},
        )
        calls = self.calls()
        self.assertEqual(
            calls[0],
            ["apps", "list", "--bundle-id-identifier", "in.beyondrep.app",
             "--strict-match-identifier", "--json"],
        )
        self.assertEqual(
            calls[1],
            ["get-latest-testflight-build-number", "6700000001",
             "--platform", "IOS", "--all-versions"],
        )

    def test_auto_build_is_one_when_app_has_no_builds_yet(self):
        result = self.run_resolver(NS_FAKE_LATEST="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.exported()["BEYONDREP_BUILD_NUMBER"], "1")

    def test_manual_values_are_used_when_above_latest(self):
        result = self.run_resolver(version="1.2.0", build="100")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.exported(),
            {"BEYONDREP_VERSION_NAME": "1.2.0", "BEYONDREP_BUILD_NUMBER": "100"},
        )

    def test_values_are_trimmed(self):
        result = self.run_resolver(version=" 1.2 ", build=" 50 ")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.exported(),
            {"BEYONDREP_VERSION_NAME": "1.2", "BEYONDREP_BUILD_NUMBER": "50"},
        )

    def test_manual_build_not_above_latest_is_rejected_before_building(self):
        for build in ("41", "3"):
            with self.subTest(build=build):
                self.cm_env.write_text("", encoding="utf-8")
                result = self.run_resolver(build=build)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("41", result.stderr)
                self.assertEqual(self.cm_env.read_text(encoding="utf-8"), "")

    def test_invalid_version_names_are_rejected(self):
        for version in ("", "1.2.3.4", "v1.0", "1.0-beta", "1..2", "01.0", "1.0;rm"):
            with self.subTest(version=version):
                result = self.run_resolver(version=version)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("version", result.stderr.lower())
                self.assertEqual(self.cm_env.read_text(encoding="utf-8"), "")

    def test_invalid_build_numbers_are_rejected(self):
        for build in ("", "0", "-1", "1.5", "abc", "007", "2100000001", "5;id"):
            with self.subTest(build=build):
                result = self.run_resolver(build=build)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("build", result.stderr.lower())
                self.assertEqual(self.cm_env.read_text(encoding="utf-8"), "")

    def test_lookup_failure_stops_the_build(self):
        for build in ("AUTO", "500"):
            with self.subTest(build=build):
                result = self.run_resolver(build=build, NS_FAKE_LATEST_FAIL="1")
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("App Store Connect", result.stderr)
                self.assertEqual(self.cm_env.read_text(encoding="utf-8"), "")

    def test_missing_app_record_stops_the_build(self):
        result = self.run_resolver(NS_FAKE_APP_MISSING="1")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("in.beyondrep.app", result.stderr)

    def test_unparseable_latest_build_stops_the_build(self):
        result = self.run_resolver(NS_FAKE_LATEST="1.0.3")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("App Store Connect", result.stderr)

    def test_pubspec_without_version_is_rejected_in_auto_mode(self):
        self.pubspec.write_text("name: beyondrep\n", encoding="utf-8")
        result = self.run_resolver()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("pubspec", result.stderr)

    def test_real_pubspec_version_is_valid(self):
        self.pubspec.write_text(
            (ROOT / "apps" / "mobile" / "pubspec.yaml").read_text(encoding="utf-8"),
            encoding="utf-8",
        )
        result = self.run_resolver()
        self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
