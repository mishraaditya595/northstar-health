"""Fail CI if monorepo boundaries regress."""

import fnmatch
import subprocess
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

# The repository is public. Signing material, credentials and local secret
# config must never be tracked. Patterns are matched against file basenames,
# except entries containing "/", which are matched against the full path.
SECRET_PATTERNS = (
    "*.p8",
    "*.p12",
    "*.cer",
    "*.certSigningRequest",
    "*.mobileprovision",
    "*.provisionprofile",
    "*.pem",
    "*.key",
    "*.keystore",
    "*.jks",
    "*.ipa",
    "*.aab",
    "*.apk",
    "key.properties",
    ".env",
    ".env.*",
    "service-account*.json",
    "google-services.json",
    "GoogleService-Info.plist",
    "supabase.local.json",
    "supabase/.temp/*",
)
ALLOWED_TRACKED = {".env.example"}


class LayoutTest(unittest.TestCase):
    def test_required_app_entries(self):
        required = [
            "apps/mobile/pubspec.yaml",
            "apps/mobile/lib/main.dart",
            "apps/mobile/test/app_test.dart",
            "apps/watch_os/project.yml",
            "apps/watch_os/Sources/App/BeyondRepWatchApp.swift",
            "apps/wear_os/app/build.gradle.kts",
            "apps/wear_os/app/src/main/AndroidManifest.xml",
            "apps/website/package.json",
            "apps/website/astro.config.mjs",
            "contracts/workout_sync/v1/envelope.schema.json",
            "catalog/schema/catalog.schema.json",
            "catalog/releases.lock.json",
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
            "apps/website/package-lock.json",
        ]
        for entry in required:
            with self.subTest(entry=entry):
                self.assertTrue((ROOT / entry).is_file(), entry)

    def test_flutter_not_at_repo_root(self):
        for forbidden in ("pubspec.yaml", "lib/main.dart", "test/app_test.dart"):
            self.assertFalse((ROOT / forbidden).exists(), forbidden)


if __name__ == "__main__":
    unittest.main()


class SecretHygieneTest(unittest.TestCase):
    def test_no_secret_or_signing_files_are_tracked(self):
        tracked = subprocess.run(
            ["git", "-C", str(ROOT), "ls-files"],
            check=True,
            capture_output=True,
            text=True,
        ).stdout.splitlines()
        offenders = []
        for path in tracked:
            name = path.rsplit("/", 1)[-1]
            if name in ALLOWED_TRACKED:
                continue
            for pattern in SECRET_PATTERNS:
                target = path if "/" in pattern else name
                if fnmatch.fnmatch(target, pattern) or fnmatch.fnmatch(
                    path, "*/" + pattern
                ):
                    offenders.append(path)
                    break
        self.assertEqual(offenders, [], "secret or signing files are tracked")

    def test_gitignore_blocks_signing_material(self):
        ignore = (ROOT / ".gitignore").read_text(encoding="utf-8").splitlines()
        for pattern in (
            "*.p8",
            "*.p12",
            "*.mobileprovision",
            "*.keystore",
            "*.jks",
            ".env",
            "apps/mobile/supabase.local.json",
            "supabase/.temp/",
        ):
            with self.subTest(pattern=pattern):
                self.assertIn(pattern, ignore)
