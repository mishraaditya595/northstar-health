"""Offline tests for the check that the iOS export options name a watch profile."""
from pathlib import Path
import plistlib
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "codemagic_check_watch_profile.py"


def run(profiles):
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "export_options.plist"
        path.write_bytes(plistlib.dumps({"method": "app-store", "provisioningProfiles": profiles}))
        return subprocess.run(
            [sys.executable, str(SCRIPT), str(path)], capture_output=True, text=True
        )


class WatchProfileCheckTest(unittest.TestCase):
    def test_passes_when_both_bundle_ids_have_a_profile(self):
        result = run({"in.beyondrep.app": "phone", "in.beyondrep.app.watchkitapp": "watch"})
        self.assertEqual(result.returncode, 0, result.stderr)

    def test_fails_without_a_watch_profile_and_points_to_the_fallback(self):
        result = run({"in.beyondrep.app": "phone"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("in.beyondrep.app.watchkitapp", result.stderr)
        self.assertIn("docs/IOS_TESTFLIGHT_CODEMAGIC.md", result.stderr)

    def test_fails_without_a_phone_profile(self):
        result = run({"in.beyondrep.app.watchkitapp": "watch"})
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("in.beyondrep.app", result.stderr)

    def test_missing_file_fails(self):
        result = subprocess.run(
            [sys.executable, str(SCRIPT), "/nonexistent/export_options.plist"],
            capture_output=True, text=True,
        )
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
