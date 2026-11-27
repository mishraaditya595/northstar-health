"""Offline tests for the Codemagic release-type version bump rules."""
from pathlib import Path
import contextlib
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import codemagic_release_version as rv  # noqa: E402
from codemagic_release_version import ResolveError  # noqa: E402


class ReleaseVersionTest(unittest.TestCase):
    def test_parse_pads_short_versions(self):
        self.assertEqual(rv.parse_version("0.6"), (0, 6, 0))
        self.assertEqual(rv.parse_version("2"), (2, 0, 0))
        self.assertEqual(rv.parse_version(" 1.2.3 "), (1, 2, 3))
        self.assertIsNone(rv.parse_version("1.02.0"))
        self.assertIsNone(rv.parse_version("1.2.3.4"))
        self.assertIsNone(rv.parse_version(""))

    def test_highest_compares_numerically(self):
        self.assertEqual(rv.highest([(0, 9, 3), (1, 0, 0), (0, 10, 0)]), (1, 0, 0))
        self.assertIsNone(rv.highest([]))

    def test_format_version(self):
        self.assertEqual(rv.format_version((0, 6, 0)), "0.6.0")

    def test_release_types_order(self):
        self.assertEqual(rv.RELEASE_TYPES, (
            "Fix or optimisation", "Feature", "Major",
            "Same version, new build", "Exact version",
        ))

    def test_fix_feature_major_bumps(self):
        cur = (0, 6, 1)
        self.assertEqual(rv.next_version(rv.FIX, "AUTO", cur), (0, 6, 2))
        self.assertEqual(rv.next_version(rv.FEATURE, "AUTO", cur), (0, 7, 0))
        self.assertEqual(rv.next_version(rv.MAJOR, "AUTO", cur), (1, 0, 0))

    def test_no_current_version_starts_from_zero(self):
        self.assertEqual(rv.next_version(rv.FIX, "AUTO", None), (0, 0, 1))
        self.assertEqual(rv.next_version(rv.FEATURE, "AUTO", None), (0, 1, 0))

    def test_same_version_reuses_current(self):
        self.assertEqual(rv.next_version(rv.SAME, "AUTO", (0, 6, 1)), (0, 6, 1))
        with self.assertRaises(ResolveError) as ctx:
            rv.next_version(rv.SAME, "AUTO", None)
        self.assertIn("no version", str(ctx.exception))

    def test_exact_version_rules(self):
        cur = (0, 6, 1)
        self.assertEqual(rv.next_version(rv.EXACT, "0.7", cur), (0, 7, 0))
        self.assertEqual(rv.next_version(rv.EXACT, "0.6.1", cur), (0, 6, 1))
        with self.assertRaises(ResolveError) as ctx:
            rv.next_version(rv.EXACT, "0.6.0", cur)
        self.assertIn("0.6.1", str(ctx.exception))
        with self.assertRaises(ResolveError):
            rv.next_version(rv.EXACT, "AUTO", cur)
        with self.assertRaises(ResolveError):
            rv.next_version(rv.EXACT, "abc", cur)

    def test_exact_version_trims_and_rejects_prefix(self):
        self.assertEqual(rv.next_version(rv.EXACT, " 1.2.0 ", (0, 6, 1)), (1, 2, 0))
        with self.assertRaises(ResolveError):
            rv.next_version(rv.EXACT, "v1.2.0", (0, 6, 1))

    def test_version_name_with_non_exact_type_is_rejected(self):
        with self.assertRaises(ResolveError) as ctx:
            rv.next_version(rv.FIX, "1.2.0", (0, 6, 1))
        self.assertIn("Exact version", str(ctx.exception))

    def test_fix_overflow_is_rejected(self):
        with self.assertRaises(ResolveError):
            rv.next_version(rv.FIX, "AUTO", (0, 0, 9999))

    def test_unknown_release_type_lists_choices(self):
        with self.assertRaises(ResolveError) as ctx:
            rv.next_version("feature", "AUTO", (0, 6, 1))
        for choice in rv.RELEASE_TYPES:
            self.assertIn(choice, str(ctx.exception))


ASC_STUB = """#!/usr/bin/env python3
import json
import os
import sys
args = sys.argv[1:]
with open(os.environ['NS_FAKE_LOG'], 'a', encoding='utf-8') as f:
    f.write(json.dumps(['asc'] + args) + '\\n')
if args[:2] == ['apps', 'list']:
    print(json.dumps([{'id': '6700000001', 'type': 'apps'}]))
    sys.exit(0)
if args[:2] == ['apps', 'pre-release-versions']:
    if os.environ.get('NS_FAKE_ASC_FAIL') == '1':
        print('API error', file=sys.stderr)
        sys.exit(2)
    items = json.loads(os.environ.get('NS_FAKE_PRE', '[]'))
    print(json.dumps([
        {'id': str(i), 'type': 'preReleaseVersions',
         'attributes': {'platform': p, 'version': v}}
        for i, (p, v) in enumerate(items)]))
    sys.exit(0)
if args[:2] == ['apps', 'app-store-versions']:
    items = json.loads(os.environ.get('NS_FAKE_STORE', '[]'))
    print(json.dumps([
        {'id': str(i), 'type': 'appStoreVersions',
         'attributes': {'platform': p, 'versionString': v}}
        for i, (p, v) in enumerate(items)]))
    sys.exit(0)
sys.exit(9)
"""

# codemagic-cli-tools wraps each Track as {"track": {"track": ..., "releases": [...]}}.
PLAY_STUB = """#!/usr/bin/env python3
import json
import os
import sys
args = sys.argv[1:]
with open(os.environ['NS_FAKE_LOG'], 'a', encoding='utf-8') as f:
    f.write(json.dumps(['play'] + args) + '\\n')
if os.environ.get('NS_FAKE_PLAY_FAIL') == '1':
    print('permission denied', file=sys.stderr)
    sys.exit(2)
print(json.dumps([{'track': t} for t in json.loads(os.environ.get('NS_FAKE_TRACKS', '[]'))]))
"""


class StoreVersionLookupTest(unittest.TestCase):
    def setUp(self):
        tmp = tempfile.TemporaryDirectory()
        self.addCleanup(tmp.cleanup)
        temp = Path(tmp.name)
        for name, body in (("app-store-connect", ASC_STUB), ("google-play", PLAY_STUB)):
            stub = temp / name
            stub.write_text(body, encoding="utf-8")
            stub.chmod(0o755)
        self.log = temp / "calls.log"
        self.out = io.StringIO()
        redirect = contextlib.redirect_stdout(self.out)
        redirect.__enter__()
        self.addCleanup(redirect.__exit__, None, None, None)
        saved = dict(os.environ)
        self.addCleanup(lambda: (os.environ.clear(), os.environ.update(saved)))
        for key in [k for k in os.environ if k.startswith("NS_FAKE_")]:
            del os.environ[key]
        os.environ["PATH"] = f"{temp}{os.pathsep}{os.environ['PATH']}"
        os.environ["NS_FAKE_LOG"] = str(self.log)
        os.environ.pop(rv.CREDENTIALS, None)

    def setup_asc(self, pre=(), store=()):
        os.environ["NS_FAKE_PRE"] = json.dumps(list(pre))
        os.environ["NS_FAKE_STORE"] = json.dumps(list(store))

    def setup_play(self, tracks):
        os.environ[rv.CREDENTIALS] = "fake-credentials"
        os.environ["NS_FAKE_TRACKS"] = json.dumps(tracks)

    def calls(self):
        if not self.log.exists():
            return []
        return [json.loads(line) for line in self.log.read_text().splitlines()]

    def test_asc_reads_testflight_versions_only(self):
        self.setup_asc(pre=[("IOS", "0.5.0"), ("IOS", "0.6.0")])
        self.assertEqual(rv.current_version(play_optional=False), (0, 6, 0))
        self.assertIn(
            ["asc", "apps", "pre-release-versions", "6700000001", "--json"],
            self.calls(),
        )

    def test_app_store_placeholder_version_is_never_read(self):
        # App Store Connect auto-creates an App Store version "1.0".
        self.setup_asc(pre=[("IOS", "0.6.1")], store=[("IOS", "1.0")])
        self.assertEqual(rv.current_version(play_optional=False), (0, 6, 1))
        self.assertFalse(
            [c for c in self.calls() if "app-store-versions" in c]
        )

    def test_asc_counts_only_ios_platform(self):
        self.setup_asc(pre=[("IOS", "0.5.0"), ("MAC_OS", "9.0.0")])
        self.assertEqual(rv.current_version(play_optional=False), (0, 5, 0))

    def test_play_versions_raise_the_max(self):
        self.setup_asc(pre=[("IOS", "0.6.0")])
        self.setup_play([
            {"track": "internal", "releases": [
                {"name": "0.6.1", "status": "completed", "versionCodes": ["3"]},
                {"status": "draft"},
            ]},
        ])
        self.assertEqual(rv.current_version(play_optional=False), (0, 6, 1))
        self.assertIn(
            ["play", "tracks", "list", "--package-name", "in.beyondrep.app",
             "--credentials", "@env:GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS",
             "--json"],
            self.calls(),
        )

    def test_play_reads_unwrapped_track_items_too(self):
        self.setup_asc(pre=[("IOS", "0.6.0")])
        self.setup_play([])
        stub_out = json.dumps(
            [{"track": "internal", "releases": [{"name": "0.7.0"}]}]
        )
        os.environ["NS_FAKE_TRACKS"] = "[]"
        original = subprocess.run

        def fake_run(cmd, **kwargs):
            if cmd[0] == "google-play":
                return subprocess.CompletedProcess(cmd, 0, stdout=stub_out, stderr="")
            return original(cmd, **kwargs)

        subprocess.run = fake_run
        self.addCleanup(lambda: setattr(subprocess, "run", original))
        self.assertEqual(rv.current_version(play_optional=False), (0, 7, 0))

    def test_play_ignores_non_version_names(self):
        self.setup_asc(pre=[("IOS", "0.6.0")])
        self.setup_play([
            {"track": "internal", "releases": [
                {"name": "Internal test 3"},
                {"name": "12 (1.0)"},
                {"status": "draft"},
            ]},
            {"track": "production"},
        ])
        self.assertEqual(rv.current_version(play_optional=False), (0, 6, 0))

    def test_play_ignores_one_part_release_names(self):
        self.setup_asc(pre=[("IOS", "0.6.0")])
        self.setup_play([
            {"track": "internal", "releases": [{"name": "3"}, {"name": "12"}]},
        ])
        self.assertEqual(rv.current_version(play_optional=False), (0, 6, 0))

    def test_blank_play_credentials_skip_play(self):
        self.setup_asc(pre=[("IOS", "0.6.0")])
        os.environ[rv.CREDENTIALS] = "   "
        self.assertEqual(rv.current_version(play_optional=False), (0, 6, 0))
        self.assertFalse([c for c in self.calls() if c[0] == "play"])

    def test_play_failure_stops_unless_optional(self):
        self.setup_asc(pre=[("IOS", "0.6.0")])
        self.setup_play([])
        os.environ["NS_FAKE_PLAY_FAIL"] = "1"
        with self.assertRaises(ResolveError) as ctx:
            rv.current_version(play_optional=False)
        self.assertIn("permission denied", str(ctx.exception))
        self.assertNotIn("fake-credentials", str(ctx.exception))
        self.out.truncate(0)
        self.assertEqual(rv.current_version(play_optional=True), (0, 6, 0))
        note = self.out.getvalue()
        self.assertIn("Google Play not checked", note)
        self.assertIn("Using App Store Connect only", note)
        self.assertNotIn("fake-credentials", note)

    def test_asc_failure_always_stops(self):
        self.setup_asc(pre=[("IOS", "0.6.0")])
        self.setup_play([])
        os.environ["NS_FAKE_ASC_FAIL"] = "1"
        for optional in (False, True):
            with self.subTest(play_optional=optional):
                with self.assertRaises(ResolveError):
                    rv.current_version(play_optional=optional)

    def test_no_versions_anywhere_is_none(self):
        self.setup_asc()
        self.setup_play([])
        self.assertIsNone(rv.current_version(play_optional=False))


if __name__ == "__main__":
    unittest.main()
