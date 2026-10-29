"""Language-neutral watch event contract checks; run from repository root.

Dependencies: python3 -m pip install -r tool/requirements-ci.txt
"""

import json
import unittest
from pathlib import Path

from jsonschema import Draft202012Validator, FormatChecker

ROOT = Path(__file__).resolve().parents[1]
PROTOCOL = ROOT / "contracts" / "workout_sync" / "v1"
SCHEMA = json.loads((PROTOCOL / "envelope.schema.json").read_text(encoding="utf-8"))


class ProtocolFixturesTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        Draft202012Validator.check_schema(SCHEMA)
        cls.validator = Draft202012Validator(SCHEMA, format_checker=FormatChecker())

    def test_valid_messages(self):
        fixtures = sorted((PROTOCOL / "fixtures/valid").glob("*.json"))
        self.assertGreaterEqual(len(fixtures), 3)
        for path in fixtures:
            with self.subTest(file=path.name):
                data = json.loads(path.read_text(encoding="utf-8"))
                self.validator.validate(data)

    def test_invalid_messages(self):
        fixtures = sorted((PROTOCOL / "fixtures/invalid").glob("*.json"))
        self.assertGreaterEqual(len(fixtures), 4)
        for path in fixtures:
            with self.subTest(file=path.name):
                data = json.loads(path.read_text(encoding="utf-8"))
                self.assertTrue(list(self.validator.iter_errors(data)), path.name)

    def test_no_platform_sensor_payload_in_valid_fixtures(self):
        forbidden = {"heart_rate", "spo2", "hrv", "sleep", "steps", "gps"}
        for path in (PROTOCOL / "fixtures/valid").glob("*.json"):
            with self.subTest(file=path.name):
                serialized = json.dumps(json.loads(path.read_text(encoding="utf-8"))).lower()
                for word in forbidden:
                    self.assertNotIn(word, serialized)


if __name__ == "__main__":
    unittest.main()
