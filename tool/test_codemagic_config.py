"""Guard rails for the unconfigured Codemagic CI/CD skeleton.

Validates existing inert templates plus manual-only, credential-free Supabase YAML.
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
    "mobile-android-release": "apps/mobile",
    "mobile-ios-simulator": "apps/mobile",
    "mobile-ios-adhoc": "apps/mobile",
    "mobile-ios-testflight": "apps/mobile",
    "wear-os-debug": "apps/wear_os",
    "wear-os-release": "apps/wear_os",
    "watchos-simulator": "apps/watch_os",
    "watchos-companion-release": "apps/mobile",
}

SUPABASE_WORKFLOWS = {
    f"supabase-{target}-{action}": (target, action)
    for target in ("staging", "production")
    for action in ("preview", "migrate", "function")
}


class CodemagicTemplateTest(unittest.TestCase):
    def test_templates_are_manual_inert_and_refer_to_real_directories(self):
        self.assertTrue(FILE.is_file())
        document = yaml.safe_load(FILE.read_text(encoding="utf-8"))
        self.assertIsInstance(document, dict)
        self.assertEqual(set(document), {"workflows"})
        self.assertEqual(set(EXPECTED) | set(SUPABASE_WORKFLOWS), set(document["workflows"]))

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

    def test_supabase_workflows_are_manual_scoped_and_have_no_embedded_secrets(self):
        document = yaml.safe_load(FILE.read_text(encoding="utf-8"))
        for name, (target, action) in SUPABASE_WORKFLOWS.items():
            with self.subTest(workflow=name):
                workflow = document["workflows"][name]
                self.assertNotIn("triggering", workflow)
                self.assertNotIn("publishing", workflow)
                self.assertNotIn("artifacts", workflow)
                self.assertEqual(workflow["working_directory"], ".")
                self.assertEqual(workflow["instance_type"], "mac_mini_m2")
                env = workflow["environment"]
                self.assertEqual(env["groups"], [f"ns_supabase_{target}"])
                self.assertEqual(env["vars"], {
                    "NS_SUPABASE_TARGET": target,
                    "NS_SUPABASE_ACTION": action,
                })
                self.assertEqual(len(workflow["scripts"]), 1)
                self.assertEqual(
                    workflow["scripts"][0]["script"].strip(),
                    "bash scripts/codemagic_supabase.sh",
                )
                # Variable groups resolve privately in Codemagic; no
                # credential literals or project refs belong in YAML.
                for secret_name in (
                    "SUPABASE_ACCESS_TOKEN", "SUPABASE_DB_PASSWORD",
                    "SUPABASE_PROJECT_ID", "SUPABASE_SERVICE_ROLE_KEY",
                ):
                    self.assertNotIn(secret_name, workflow["scripts"][0]["script"])
                self.assertNotIn("android_signing", env)
                self.assertNotIn("ios_signing", env)

    def test_watchos_companion_is_explicitly_blocked(self):
        workflow = yaml.safe_load(FILE.read_text(encoding="utf-8"))["workflows"][
            "watchos-companion-release"
        ]
        self.assertIn("BLOCKED", workflow["scripts"][0]["script"])


if __name__ == "__main__":
    unittest.main()
