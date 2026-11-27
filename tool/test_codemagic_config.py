"""Guard rails for the unconfigured Codemagic CI/CD skeleton.

Validates existing inert templates, manual-only credential-free Supabase YAML,
the manual internal-TestFlight iOS upload and the manual Android Play AAB.
It does not test Codemagic hosted execution, signing or real build artifacts.
"""

from pathlib import Path
import unittest

import yaml

ROOT = Path(__file__).resolve().parents[1]
FILE = ROOT / "codemagic.yaml"
EXPECTED = {
    "quality-checks": ".",
    "mobile-android-debug": "apps/mobile",
    "mobile-android-profile": "apps/mobile",
    "mobile-ios-simulator": "apps/mobile",
    "mobile-ios-adhoc": "apps/mobile",
    "wear-os-debug": "apps/wear_os",
    "wear-os-release": "apps/wear_os",
    "watchos-simulator": "apps/watch_os",
    "watchos-companion-release": "apps/mobile",
}

SUPABASE_WORKFLOWS = {
    "supabase-database": "database",
    "supabase-functions": "functions",
}


class CodemagicTemplateTest(unittest.TestCase):
    def test_templates_are_manual_inert_and_refer_to_real_directories(self):
        self.assertTrue(FILE.is_file())
        document = yaml.safe_load(FILE.read_text(encoding="utf-8"))
        self.assertIsInstance(document, dict)
        self.assertEqual(set(document), {"workflows"})
        self.assertEqual(
            set(EXPECTED)
            | set(SUPABASE_WORKFLOWS)
            | {"mobile-ios-testflight", "mobile-android-release"},
            set(document["workflows"]),
        )

        for name, target_directory in EXPECTED.items():
            with self.subTest(workflow=name):
                workflow = document["workflows"][name]
                self.assertEqual(workflow["working_directory"], target_directory)
                self.assertTrue((ROOT / target_directory).is_dir())
                self.assertEqual(workflow["instance_type"], "mac_mini_m2")
                self.assertIn("TEMPLATE", workflow["name"])
                self.assertNotIn("triggering", workflow)
                self.assertNotIn("publishing", workflow)
                self.assertNotIn("artifacts", workflow)
                env = workflow.get("environment", {})
                for forbidden in ("android_signing", "ios_signing", "groups"):
                    self.assertNotIn(forbidden, env)
                self.assertEqual(len(workflow["scripts"]), 1)
                body = workflow["scripts"][0]["script"]
                self.assertIn("TEMPLATE ONLY", body)
                self.assertTrue(body.rstrip().endswith("exit 1"))

    def test_two_supabase_workflows_have_safe_manual_inputs(self):
        document = yaml.safe_load(FILE.read_text(encoding="utf-8"))
        workflows = document["workflows"]
        for key, kind in SUPABASE_WORKFLOWS.items():
            with self.subTest(workflow=key):
                workflow = workflows[key]
                for forbidden in ("triggering", "publishing", "artifacts"):
                    self.assertNotIn(forbidden, workflow)
                self.assertEqual(workflow["working_directory"], ".")
                self.assertEqual(workflow["instance_type"], "mac_mini_m2")
                self.assertEqual(
                    workflow["environment"]["groups"], ["ns_supabase_deploy"]
                )
                variables = workflow["environment"]["vars"]
                self.assertEqual(
                    variables["NS_SUPABASE_ACTION"], "${{ inputs.action }}"
                )
                self.assertEqual(
                    variables["NS_SUPABASE_CONFIRM_PROJECT_ID"],
                    "${{ inputs.confirm_project_ref }}",
                )
                self.assertEqual(
                    variables["NS_SUPABASE_CONFIRM_COMMIT_SHA"],
                    "${{ inputs.confirm_commit_sha }}",
                )
                inputs = workflow["inputs"]
                self.assertEqual(inputs["action"]["type"], "choice")
                self.assertEqual(inputs["action"]["options"], ["preview", "deploy"])
                self.assertEqual(inputs["action"]["default"], "preview")
                self.assertEqual(inputs["confirm_project_ref"]["default"], "NOT_SET")
                self.assertEqual(inputs["confirm_commit_sha"]["type"], "string")
                self.assertEqual(inputs["confirm_commit_sha"]["default"], "NOT_SET")
                # Codemagic substitutes input defaults before validating the
                # environment vars schema, which rejects empty string values.
                # Every referenced default must resolve to a nonempty string.
                for value in variables.values():
                    self.assertTrue(
                        value.startswith("${{ inputs.") and value.endswith(" }}"),
                        f"unexpected input binding: {value}",
                    )
                    input_name = value[len("${{ inputs."):-len(" }}")]
                    self.assertIn(input_name, inputs)
                    resolved_default = inputs[input_name].get("default")
                    self.assertIsInstance(resolved_default, str)
                    self.assertTrue(
                        resolved_default,
                        f"empty default for {input_name} would break Codemagic YAML",
                    )
                self.assertEqual(len(workflow["scripts"]), 1)
                self.assertEqual(
                    workflow["scripts"][0]["script"].strip(),
                    f"bash scripts/codemagic_supabase.sh {kind}",
                )
                self.assertNotIn("SUPABASE_SERVICE_ROLE_KEY", str(workflow))
                self.assertNotIn("SUPABASE_ACCESS_TOKEN", str(workflow))
                self.assertNotIn("SUPABASE_DB_PASSWORD", str(workflow))
                if kind == "functions":
                    self.assertEqual(
                        inputs["function_names"]["default"], "SELECT_FUNCTION"
                    )
                    self.assertEqual(
                        variables["NS_SUPABASE_FUNCTIONS"],
                        "${{ inputs.function_names }}",
                    )
                else:
                    self.assertNotIn("function_names", inputs)
                    self.assertNotIn("NS_SUPABASE_FUNCTIONS", variables)

    def test_ios_testflight_is_manual_internal_upload_without_secrets(self):
        workflow = yaml.safe_load(FILE.read_text(encoding="utf-8"))["workflows"][
            "mobile-ios-testflight"
        ]
        self.assertNotIn("triggering", workflow)
        self.assertIn("MANUAL", workflow["name"])
        self.assertEqual(workflow["working_directory"], "apps/mobile")
        env = workflow["environment"]
        self.assertEqual(env["flutter"], "3.47.7")
        self.assertEqual(
            env["ios_signing"],
            {
                # Manual profiles: automatic signing fetched no profile for the
                # embedded watch app on the first run (2026-11-27).
                "provisioning_profiles": [
                    "beyondrep_app_store",
                    "beyondrep_watch_app_store",
                ],
                "certificates": ["Apple Distribution"],
            },
        )
        # No ns_google_play on iOS: Codemagic refuses to start a build that
        # names a variable group that does not exist yet, and without the Play
        # credentials the version comes from App Store Connect alone.
        self.assertEqual(env["groups"], ["ns_mobile_supabase_public"])
        self.assertEqual(
            env["vars"],
            {
                "NS_RELEASE_TYPE": "${{ inputs.release_type }}",
                "NS_VERSION_NAME": "${{ inputs.version_name }}",
                "NS_BUILD_NUMBER": "${{ inputs.build_number }}",
            },
        )
        inputs = workflow["inputs"]
        self.assertEqual(set(inputs), {"release_type", "version_name", "build_number"})
        self.assertEqual(inputs["release_type"]["type"], "choice")
        self.assertEqual(
            inputs["release_type"]["options"],
            [
                "Fix or optimisation", "Feature", "Major",
                "Same version, new build", "Exact version",
            ],
        )
        self.assertEqual(inputs["release_type"]["default"], "Fix or optimisation")
        self.assertIn("Exact version", inputs["version_name"]["description"])
        for name in ("version_name", "build_number"):
            self.assertEqual(inputs[name]["type"], "string")
            # Codemagic rejects empty interpolated inputs; AUTO is the default.
            self.assertEqual(inputs[name]["default"], "AUTO")
        self.assertEqual(
            workflow["publishing"],
            {
                "app_store_connect": {
                    "auth": "integration",
                    "submit_to_testflight": False,
                    "submit_to_app_store": False,
                }
            },
        )
        self.assertEqual(workflow["artifacts"], ["build/ios/ipa/*.ipa"])
        scripts = "\n".join(step["script"] for step in workflow["scripts"])
        self.assertIn("flutter pub get --enforce-lockfile", scripts)
        self.assertIn("flutter build ipa --release", scripts)
        # Issue #49: never use Codemagic's per-workflow run counter.
        self.assertNotIn("$BUILD_NUMBER", scripts)
        self.assertIn("python3 ../../scripts/codemagic_ios_version.py", scripts)
        self.assertIn('--build-name="$BEYONDREP_VERSION_NAME"', scripts)
        self.assertIn('--build-number="$BEYONDREP_BUILD_NUMBER"', scripts)
        names = [step["name"] for step in workflow["scripts"]]
        self.assertLess(
            names.index("Resolve version name and build number"),
            names.index("Build signed IPA"),
        )
        self.assertIn("sb_publishable_", scripts)
        self.assertIn("scripts/codemagic_check_watch_profile.py", scripts)
        self.assertLess(
            names.index("Apply App Store signing profiles"),
            names.index("Check the watch app has a signing profile"),
        )
        self.assertLess(
            names.index("Check the watch app has a signing profile"),
            names.index("Build signed IPA"),
        )
        for forbidden in (
            "SERVICE_ROLE",
            "SUPABASE_ACCESS_TOKEN",
            "SUPABASE_DB_PASSWORD",
            "PRIVATE_KEY",
            "printenv",
            "set -x",
        ):
            self.assertNotIn(forbidden, str(workflow))

    def test_android_release_is_manual_signed_draft_upload_without_secrets(self):
        workflow = yaml.safe_load(FILE.read_text(encoding="utf-8"))["workflows"][
            "mobile-android-release"
        ]
        self.assertNotIn("triggering", workflow)
        # Uploads happen in a script with --draft, never Codemagic publishing.
        self.assertNotIn("publishing", workflow)
        self.assertIn("MANUAL", workflow["name"])
        self.assertEqual(workflow["working_directory"], "apps/mobile")
        env = workflow["environment"]
        self.assertEqual(env["flutter"], "3.47.7")
        self.assertEqual(env["android_signing"], ["beyondrep_upload"])
        self.assertEqual(
            env["groups"], ["ns_mobile_supabase_public", "ns_google_play"]
        )
        self.assertEqual(
            workflow["integrations"], {"app_store_connect": "Codemagic Signing"}
        )
        self.assertEqual(
            env["vars"],
            {
                "NS_RELEASE_TYPE": "${{ inputs.release_type }}",
                "NS_VERSION_NAME": "${{ inputs.version_name }}",
                "NS_BUILD_NUMBER": "${{ inputs.build_number }}",
                "NS_PLAY_TRACK": "${{ inputs.play_track }}",
                "BEYONDREP_REQUIRE_RELEASE_SIGNING": "true",
            },
        )
        inputs = workflow["inputs"]
        self.assertEqual(
            set(inputs), {"release_type", "version_name", "build_number", "play_track"}
        )
        self.assertEqual(inputs["release_type"]["type"], "choice")
        self.assertEqual(
            inputs["release_type"]["options"],
            [
                "Fix or optimisation", "Feature", "Major",
                "Same version, new build", "Exact version",
            ],
        )
        self.assertEqual(inputs["release_type"]["default"], "Fix or optimisation")
        self.assertIn("Exact version", inputs["version_name"]["description"])
        for name in ("version_name", "build_number"):
            self.assertEqual(inputs[name]["type"], "string")
            self.assertEqual(inputs[name]["default"], "AUTO")
        track = inputs["play_track"]
        self.assertEqual(track["type"], "choice")
        # Never production; uploading is opt-in per run.
        self.assertEqual(track["options"], ["none", "internal", "alpha"])
        self.assertEqual(track["default"], "none")
        self.assertEqual(
            workflow["artifacts"][0], "build/app/outputs/bundle/release/*.aab"
        )
        scripts = "\n".join(step["script"] for step in workflow["scripts"])
        self.assertIn("flutter pub get --enforce-lockfile", scripts)
        self.assertIn("flutter build appbundle --release", scripts)
        self.assertNotIn("$BUILD_NUMBER", scripts)
        self.assertIn("python3 ../../scripts/codemagic_android_version.py\n", scripts + "\n")
        self.assertNotIn("codemagic_android_version.py pubspec", scripts)
        self.assertIn('--release-name "$BEYONDREP_VERSION_NAME"', scripts)
        self.assertIn('--build-name="$BEYONDREP_VERSION_NAME"', scripts)
        self.assertIn('--build-number="$BEYONDREP_BUILD_NUMBER"', scripts)
        self.assertIn("CN=Android Debug", scripts)
        self.assertIn("--draft", scripts)
        self.assertNotIn("production", scripts)
        self.assertNotIn("--rollout-fraction", scripts)
        names = [step["name"] for step in workflow["scripts"]]
        self.assertLess(
            names.index("Resolve version name and build number"),
            names.index("Build signed AAB"),
        )
        self.assertLess(
            names.index("Refuse a debug-signed AAB"),
            names.index("Upload draft release to Google Play"),
        )
        self.assertIn("sb_publishable_", scripts)
        for forbidden in (
            "SERVICE_ROLE",
            "SUPABASE_ACCESS_TOKEN",
            "SUPABASE_DB_PASSWORD",
            "PRIVATE_KEY",
            "printenv",
            "set -x",
        ):
            self.assertNotIn(forbidden, str(workflow))

    def test_watchos_companion_is_explicitly_blocked(self):
        workflow = yaml.safe_load(FILE.read_text(encoding="utf-8"))["workflows"][
            "watchos-companion-release"
        ]
        self.assertIn("BLOCKED", workflow["scripts"][0]["script"])


if __name__ == "__main__":
    unittest.main()
