"""The Apple Watch app is embedded in Runner by a committed script (ADR-0004).

Checks the generated project file, that watch sources stay in apps/watch_os,
and (when Ruby and the pinned xcodeproj gem are available) that re-running the
script changes nothing.
"""

import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "apps" / "mobile" / "ios"
PBXPROJ = IOS / "Runner.xcodeproj" / "project.pbxproj"
SCRIPT = ROOT / "tool" / "embed_watch_target.rb"
# RunnerTests.swift is the stock Flutter unit-test stub, not watch code.
ALLOWED_IOS_SWIFT = {
    "AppDelegate.swift",
    "SceneDelegate.swift",
    "WatchLinkBridge.swift",
    "RunnerTests.swift",
}


class WatchEmbeddingTest(unittest.TestCase):
    def setUp(self):
        self.pbx = PBXPROJ.read_text(encoding="utf-8")

    def test_watch_target_with_bundle_id(self):
        self.assertIn("name = BeyondRepWatch;", self.pbx)
        self.assertIn("PRODUCT_BUNDLE_IDENTIFIER = in.beyondrep.app.watchkitapp;", self.pbx)
        self.assertIn("INFOPLIST_KEY_WKCompanionAppBundleIdentifier = in.beyondrep.app;", self.pbx)
        self.assertIn("WATCHOS_DEPLOYMENT_TARGET = 10.0;", self.pbx)
        self.assertIn("SDKROOT = watchos;", self.pbx)

    def test_runner_embeds_the_watch_app(self):
        self.assertIn('name = "Embed Watch Content";', self.pbx)
        self.assertIn('dstPath = "$(CONTENTS_FOLDER_PATH)/Watch";', self.pbx)
        self.assertIn("PBXTargetDependency", self.pbx)

    def test_watch_sources_are_referenced_not_copied(self):
        self.assertIn("../../watch_os", self.pbx)
        self.assertIn("libsqlite3.tbd", self.pbx)
        tracked = subprocess.run(
            ["git", "ls-files", "apps/mobile/ios"], cwd=ROOT, capture_output=True, text=True, check=True
        ).stdout.splitlines()
        swift = {Path(p).name for p in tracked if p.endswith(".swift")}
        self.assertEqual(swift - ALLOWED_IOS_SWIFT, set(), "watch Swift must stay in apps/watch_os")

    def test_no_signing_material_in_the_project(self):
        self.assertNotIn("DEVELOPMENT_TEAM", self.pbx)
        self.assertNotIn("PROVISIONING_PROFILE", self.pbx)

    def test_script_is_idempotent(self):
        ruby, bundle = shutil.which("ruby"), shutil.which("bundle")
        if not ruby or not bundle:
            self.skipTest("ruby/bundler not installed")
        probe = subprocess.run(
            [bundle, "exec", ruby, "-e", 'require "xcodeproj"'],
            cwd=ROOT / "tool", capture_output=True, text=True,
        )
        if probe.returncode != 0:
            self.skipTest("the pinned xcodeproj gem is not installed (cd tool && bundle install)")
        with tempfile.TemporaryDirectory() as tmp:
            copy = Path(tmp) / "Runner.xcodeproj"
            shutil.copytree(IOS / "Runner.xcodeproj", copy)
            before = (copy / "project.pbxproj").read_bytes()
            run = subprocess.run(
                [bundle, "exec", ruby, str(SCRIPT), str(copy)],
                cwd=ROOT / "tool", capture_output=True, text=True,
            )
            self.assertEqual(run.returncode, 0, run.stderr)
            self.assertEqual((copy / "project.pbxproj").read_bytes(), before)
        self.assertEqual(PBXPROJ.read_text(encoding="utf-8"), self.pbx)


if __name__ == "__main__":
    unittest.main()
