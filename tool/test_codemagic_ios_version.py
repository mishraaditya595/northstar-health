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
if args[:2] == ['apps', 'pre-release-versions']:
    print(os.environ.get('NS_FAKE_PRERELEASE', '[]'))
    sys.exit(0)
if args[:2] == ['apps', 'app-store-versions']:
    print(os.environ.get('NS_FAKE_STORE', '[]'))
    sys.exit(0)
if args[:1] == ['get-latest-testflight-build-number']:
    if os.environ.get('NS_FAKE_LATEST_FAIL') == '1':
        print('API error', file=sys.stderr)
        sys.exit(2)
    print(os.environ.get('NS_FAKE_LATEST', ''))
    sys.exit(0)
sys.exit(9)
"""


def prerelease(*versions):
    return json.dumps([
        {"id": str(i), "type": "preReleaseVersions",
         "attributes": {"platform": "IOS", "version": v}}
        for i, v in enumerate(versions)
    ])


def store(*versions):
    return json.dumps([
        {"id": str(i), "type": "appStoreVersions",
         "attributes": {"platform": "IOS", "versionString": v}}
        for i, v in enumerate(versions)
    ])


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
        self.path = f"{temp}{os.pathsep}{os.environ['PATH']}"

    def run_resolver(
        self, release="Fix or optimisation", version="AUTO", build="AUTO", **extra
    ):
        env = {
            "PATH": self.path,
            "HOME": self.tmp.name,
            "CM_ENV": str(self.cm_env),
            "NS_FAKE_ASC_LOG": str(self.log),
            "NS_RELEASE_TYPE": release,
            "NS_VERSION_NAME": version,
            "NS_BUILD_NUMBER": build,
            "NS_FAKE_LATEST": "41",
            "NS_FAKE_PRERELEASE": prerelease("0.6.1"),
        }
        env.update(extra)
        return subprocess.run(
            [sys.executable, str(SCRIPT)],
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

    def test_fix_bumps_latest_store_version_and_build(self):
        result = self.run_resolver()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.exported(),
            {"BEYONDREP_VERSION_NAME": "0.6.2", "BEYONDREP_BUILD_NUMBER": "42"},
        )
        self.assertIn(
            "Release type Fix or optimisation: 0.6.1 -> 0.6.2, build number 42",
            result.stdout,
        )
        self.assertIn(
            ["get-latest-testflight-build-number", "6700000001",
             "--platform", "IOS", "--all-versions"],
            self.calls(),
        )

    def test_feature_and_major(self):
        result = self.run_resolver(release="Feature")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.exported()["BEYONDREP_VERSION_NAME"], "0.7.0")
        self.cm_env.write_text("", encoding="utf-8")
        result = self.run_resolver(release="Major")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.exported()["BEYONDREP_VERSION_NAME"], "1.0.0")

    def test_app_store_placeholder_version_is_ignored(self):
        result = self.run_resolver(NS_FAKE_STORE=store("1.0"))
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.exported()["BEYONDREP_VERSION_NAME"], "0.6.2")

    def test_no_store_versions_starts_from_zero(self):
        result = self.run_resolver(NS_FAKE_PRERELEASE="[]", NS_FAKE_LATEST="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.exported(),
            {"BEYONDREP_VERSION_NAME": "0.0.1", "BEYONDREP_BUILD_NUMBER": "1"},
        )
        self.assertIn("none -> 0.0.1", result.stdout)

    def test_same_version_new_build(self):
        result = self.run_resolver(release="Same version, new build")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.exported(),
            {"BEYONDREP_VERSION_NAME": "0.6.1", "BEYONDREP_BUILD_NUMBER": "42"},
        )

    def test_same_version_without_store_version_fails(self):
        result = self.run_resolver(
            release="Same version, new build", NS_FAKE_PRERELEASE="[]"
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.cm_env.read_text(encoding="utf-8"), "")

    def test_exact_version_used(self):
        result = self.run_resolver(release="Exact version", version="1.2", build="100")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.exported(),
            {"BEYONDREP_VERSION_NAME": "1.2.0", "BEYONDREP_BUILD_NUMBER": "100"},
        )

    def test_exact_lower_than_store_fails_before_build(self):
        result = self.run_resolver(release="Exact version", version="0.5.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("0.6.1", result.stderr)
        self.assertEqual(self.cm_env.read_text(encoding="utf-8"), "")

    def test_version_name_with_fix_fails(self):
        result = self.run_resolver(version="1.2.0")
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Exact version", result.stderr)
        self.assertEqual(self.cm_env.read_text(encoding="utf-8"), "")

    def test_unknown_release_type_fails(self):
        for release in ("", "Patch"):
            with self.subTest(release=release):
                result = self.run_resolver(release=release)
                self.assertNotEqual(result.returncode, 0)
                self.assertIn("release type", result.stderr.lower())
                self.assertEqual(self.cm_env.read_text(encoding="utf-8"), "")

    def test_play_credentials_blank_ios_still_works(self):
        for value in ("", "  "):
            with self.subTest(value=value):
                self.cm_env.write_text("", encoding="utf-8")
                result = self.run_resolver(GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS=value)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn("Google Play not checked", result.stdout)
                self.assertEqual(self.exported()["BEYONDREP_VERSION_NAME"], "0.6.2")

    def test_play_lookup_failure_does_not_stop_ios(self):
        temp = Path(self.tmp.name)
        play = temp / "google-play"
        play.write_text(
            "#!/usr/bin/env python3\nimport sys\nsys.exit(2)\n", encoding="utf-8"
        )
        play.chmod(0o755)
        result = self.run_resolver(GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS="secret-json")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("Google Play not checked", result.stdout)
        self.assertIn("Using App Store Connect only", result.stdout)
        self.assertNotIn("secret-json", result.stdout + result.stderr)
        self.assertEqual(self.exported()["BEYONDREP_VERSION_NAME"], "0.6.2")

    def test_no_pubspec_argument_is_accepted(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "pubspec.yaml"],
            env={"PATH": self.path, "CM_ENV": str(self.cm_env)},
            capture_output=True, text=True,
        )
        self.assertEqual(result.returncode, 2)
        self.assertIn("usage: codemagic_ios_version.py", result.stderr)

    def test_auto_build_is_one_when_app_has_no_builds_yet(self):
        result = self.run_resolver(NS_FAKE_LATEST="")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.exported()["BEYONDREP_BUILD_NUMBER"], "1")

    def test_manual_build_and_trimmed_values_are_used(self):
        result = self.run_resolver(
            release=" Exact version ", version=" 1.2 ", build=" 50 "
        )
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(
            self.exported(),
            {"BEYONDREP_VERSION_NAME": "1.2.0", "BEYONDREP_BUILD_NUMBER": "50"},
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
        for version in ("", "AUTO", "1.2.3.4", "v1.0", "1.0-beta", "1..2", "01.0", "1.0;rm"):
            with self.subTest(version=version):
                result = self.run_resolver(release="Exact version", version=version)
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


if __name__ == "__main__":
    unittest.main()
