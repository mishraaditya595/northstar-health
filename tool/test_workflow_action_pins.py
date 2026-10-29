"""Prevent mutable GitHub Actions references from returning to CI workflows."""

from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
WORKFLOWS = ROOT / ".github" / "workflows"
USE_PATTERN = re.compile(r"(?m)^\s*(?:-\s*)?uses:\s*([^\s#]+)")
PIN_PATTERN = re.compile(r"^[^@\s]+@[0-9a-f]{40}$")


class WorkflowActionPinTests(unittest.TestCase):
    def test_external_actions_use_full_commit_sha(self):
        inspected = 0
        for workflow in sorted([*WORKFLOWS.glob("*.yml"), *WORKFLOWS.glob("*.yaml")]):
            text = workflow.read_text(encoding="utf-8")
            for match in USE_PATTERN.finditer(text):
                reference = match.group(1)
                if reference.startswith(("./", "docker://")):
                    continue
                inspected += 1
                line = text.count("\n", 0, match.start()) + 1
                with self.subTest(workflow=workflow.name, line=line, action=reference):
                    self.assertRegex(reference, PIN_PATTERN)

        self.assertGreater(inspected, 0, "Expected to inspect GitHub Action references")


if __name__ == "__main__":
    unittest.main()
