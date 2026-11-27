"""The Apple Watch app is embedded in Runner by a committed script (ADR-0004).

Checks the generated project file, that watch sources stay in apps/watch_os,
and (when Ruby and the pinned xcodeproj gem are available) that re-running the
script changes nothing.
"""

import os
import plistlib
import re
import shutil
import struct
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IOS = ROOT / "apps" / "mobile" / "ios"
PBXPROJ = IOS / "Runner.xcodeproj" / "project.pbxproj"
SCRIPT = ROOT / "tool" / "embed_watch_target.rb"
WATCH = ROOT / "apps" / "watch_os"
SOURCE_DIRS = ("Sources", "Packages/BeyondRepWatchCore/Sources/BeyondRepWatchCore")
ICON = WATCH / "Sources" / "Resources" / "Assets.xcassets" / "AppIcon.appiconset" / "AppIcon.png"
# RunnerTests.swift is the stock Flutter unit-test stub, not watch code.
ALLOWED_IOS_SWIFT = {
    "AppDelegate.swift",
    "SceneDelegate.swift",
    "WatchLinkBridge.swift",
    "WorkoutMirrorBridge.swift",
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

    def test_every_watch_configuration_builds_for_watchos_only(self):
        # The Flutter project sets SUPPORTED_PLATFORMS = iphoneos at project level
        # for Release and Profile; without an override the watch target inherits
        # it and Xcode builds it for iOS in device archives.
        configs = re.findall(
            r"isa = XCBuildConfiguration;.*?buildSettings = \{(.*?)\n\t\t\t\};",
            self.pbx,
            re.S,
        )
        watch = [c for c in configs if "in.beyondrep.app.watchkitapp" in c]
        self.assertEqual(len(watch), 3)
        for config in watch:
            self.assertIn('SUPPORTED_PLATFORMS = "watchos watchsimulator";', config)

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

    def _referenced_swift(self, text):
        found = set()
        for match in re.finditer(r'path = "?([^;"]+\.swift)"?;', text):
            path = match.group(1)
            if path.startswith(SOURCE_DIRS):
                found.add(path)
        return found

    def test_watch_swift_files_on_disk_equal_those_in_the_project(self):
        on_disk = {
            str(p.relative_to(WATCH))
            for d in SOURCE_DIRS
            for p in (WATCH / d).rglob("*.swift")
        }
        self.assertEqual(
            self._referenced_swift(self.pbx), on_disk,
            "run tool/embed_watch_target.rb to sync the Runner project",
        )

    def test_runner_keeps_its_watch_link_bridge(self):
        self.assertIn("WatchLinkBridge.swift in Sources", self.pbx)

    def test_runner_compiles_the_workout_mirror_bridge(self):
        self.assertIn("WorkoutMirrorBridge.swift in Sources", self.pbx)
        self.assertTrue((IOS / "Runner" / "WorkoutMirrorBridge.swift").is_file())

    def test_watch_has_an_opaque_1024_app_icon_in_its_resources(self):
        self.assertIn("ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;", self.pbx)
        self.assertIn("Sources/Resources/Assets.xcassets", self.pbx)
        self.assertIn("Assets.xcassets in Resources", self.pbx)
        data = ICON.read_bytes()
        self.assertEqual(data[:8], b"\x89PNG\r\n\x1a\n")
        width, height, _depth, color_type = struct.unpack(">IIBB", data[16:26])
        self.assertEqual((width, height), (1024, 1024))
        self.assertIn(color_type, (0, 2), "the App Store icon must have no alpha channel")
        self.assertNotIn(b"tRNS", data)

    def test_watch_info_plist_keys(self):
        self.assertIn("INFOPLIST_KEY_WKApplication = YES;", self.pbx)
        self.assertIn(
            "INFOPLIST_KEY_WKApplication: YES",
            (WATCH / "project.yml").read_text(encoding="utf-8"),
        )

    def test_watch_has_healthkit_entitlement_and_workout_background_mode(self):
        entitlements = WATCH / "BeyondRepWatch.entitlements"
        info = WATCH / "Sources" / "Resources" / "Info.plist"
        # Same two HealthKit keys as the phone's Runner.entitlements, nothing else.
        self.assertEqual(
            plistlib.loads(entitlements.read_bytes()),
            {"com.apple.developer.healthkit": True, "com.apple.developer.healthkit.access": []},
        )
        self.assertEqual(plistlib.loads(info.read_bytes()), {"WKBackgroundModes": ["workout-processing"]})
        share = "BeyondRep reads your sleep, steps, heart rate, HRV and active energy to show them on your watch and during a workout."
        update = "BeyondRep saves each strength workout you finish on your watch to Apple Health."
        configs = re.findall(
            r"isa = XCBuildConfiguration;.*?buildSettings = \{(.*?)\n\t\t\t\};", self.pbx, re.S
        )
        watch = [c for c in configs if "in.beyondrep.app.watchkitapp" in c]
        self.assertEqual(len(watch), 3)
        for config in watch:
            self.assertIn("CODE_SIGN_ENTITLEMENTS = ../../watch_os/BeyondRepWatch.entitlements;", config)
            self.assertIn("INFOPLIST_FILE = ../../watch_os/Sources/Resources/Info.plist;", config)
            self.assertIn(f'INFOPLIST_KEY_NSHealthShareUsageDescription = "{share}";', config)
            self.assertIn(f'INFOPLIST_KEY_NSHealthUpdateUsageDescription = "{update}";', config)
        # A plist in Resources would make two commands produce Info.plist.
        self.assertNotIn("/* Info.plist in Resources", self.pbx)
        yml = (WATCH / "project.yml").read_text(encoding="utf-8")
        self.assertIn("CODE_SIGN_ENTITLEMENTS: BeyondRepWatch.entitlements", yml)
        self.assertIn("INFOPLIST_FILE: Sources/Resources/Info.plist", yml)
        self.assertIn(f"INFOPLIST_KEY_NSHealthShareUsageDescription: {share}", yml)
        self.assertIn(f"INFOPLIST_KEY_NSHealthUpdateUsageDescription: {update}", yml)
        self.assertIn("Resources/Info.plist", yml.split("sources:")[1].split("dependencies:")[0])

    def _bundle_ready(self):
        ruby, bundle = shutil.which("ruby"), shutil.which("bundle")
        if not ruby or not bundle:
            self.skipTest("ruby/bundler not installed")
        probe = subprocess.run(
            [bundle, "exec", ruby, "-e", 'require "xcodeproj"'],
            cwd=ROOT / "tool", capture_output=True, text=True,
        )
        if probe.returncode != 0:
            self.skipTest("the pinned xcodeproj gem is not installed (cd tool && bundle install)")
        return ruby, bundle

    def test_script_syncs_files_added_and_removed_on_disk(self):
        ruby, bundle = self._bundle_ready()
        with tempfile.TemporaryDirectory() as tmp:
            watch = Path(tmp) / "watch_os"
            shutil.copytree(WATCH, watch)
            copy = Path(tmp) / "Runner.xcodeproj"
            shutil.copytree(IOS / "Runner.xcodeproj", copy)
            env = dict(os.environ, BEYONDREP_WATCH_DIR=str(watch))

            def run():
                result = subprocess.run(
                    [bundle, "exec", ruby, str(SCRIPT), str(copy)],
                    cwd=ROOT / "tool", capture_output=True, text=True, env=env,
                )
                self.assertEqual(result.returncode, 0, result.stderr)
                return (copy / "project.pbxproj").read_text(encoding="utf-8")

            (watch / "Sources" / "App" / "Extra.swift").write_text("import Foundation\n")
            added = run()
            self.assertIn("Sources/App/Extra.swift", added)
            self.assertIn("WatchLinkBridge.swift in Sources", added)
            self.assertIn("WorkoutMirrorBridge.swift in Sources", added)
            self.assertEqual(run(), added, "a second run changes nothing")

            (watch / "Sources" / "App" / "Extra.swift").unlink()
            removed = run()
            self.assertNotIn("Extra.swift", removed)

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
