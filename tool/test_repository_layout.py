"""Fail CI if monorepo boundaries regress."""

import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


class LayoutTest(unittest.TestCase):
    def test_required_app_entries(self):
        required = [
            "apps/mobile/pubspec.yaml",
            "apps/mobile/lib/main.dart",
            "apps/mobile/test/app_test.dart",
            "apps/watch_os/project.yml",
            "apps/watch_os/Sources/App/NorthStarWatchApp.swift",
            "apps/wear_os/app/build.gradle.kts",
            "apps/wear_os/app/src/main/AndroidManifest.xml",
            "contracts/workout_sync/v1/envelope.schema.json",
        ]
        for entry in required:
            with self.subTest(entry=entry):
                self.assertTrue((ROOT / entry).is_file(), entry)

    def test_versioned_native_runners_and_dependency_locks(self):
        required = [
            "apps/mobile/android/app/build.gradle.kts",
            "apps/mobile/ios/Runner.xcodeproj/project.pbxproj",
            "apps/mobile/pubspec.lock",
            "apps/wear_os/gradlew",
            "apps/wear_os/gradle/wrapper/gradle-wrapper.jar",
        ]
        for entry in required:
            with self.subTest(entry=entry):
                self.assertTrue((ROOT / entry).is_file(), entry)

    def test_flutter_not_at_repo_root(self):
        for forbidden in ("pubspec.yaml", "lib/main.dart", "test/app_test.dart"):
            self.assertFalse((ROOT / forbidden).exists(), forbidden)


if __name__ == "__main__":
    unittest.main()
