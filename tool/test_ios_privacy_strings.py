"""Guards the iOS Runner purpose strings that App Store Connect requires.

App Store Connect rejects an upload (ITMS-90683) when the app has an
entitlement, or links code, that needs a purpose string the Info.plist lacks.
The HealthKit entitlement and the `health` plugin's HKHealthStore calls need
both the share (read) and update (write) strings, even though BeyondRep only
reads health data.
"""
from pathlib import Path
import plistlib
import unittest

ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "apps" / "mobile" / "ios" / "Runner"

HEALTHKIT_KEYS = (
    "NSHealthShareUsageDescription",
    "NSHealthUpdateUsageDescription",
)


def _load(name):
    with (RUNNER / name).open("rb") as f:
        return plistlib.load(f)


class IosPrivacyStringsTest(unittest.TestCase):
    def setUp(self):
        self.info = _load("Info.plist")
        self.entitlements = _load("Runner.entitlements")

    def test_healthkit_entitlement_has_both_purpose_strings(self):
        self.assertTrue(self.entitlements.get("com.apple.developer.healthkit"))
        for key in HEALTHKIT_KEYS:
            with self.subTest(key=key):
                value = self.info.get(key)
                self.assertIsInstance(value, str, f"{key} missing from Info.plist")
                self.assertGreaterEqual(len(value.strip()), 40, f"{key} too short")
                self.assertIn("BeyondRep", value)

    def test_update_string_mentions_writing(self):
        value = self.info.get("NSHealthUpdateUsageDescription", "")
        self.assertIn("write", value.lower())

    def test_clinical_records_string_present_when_entitled(self):
        access = self.entitlements.get("com.apple.developer.healthkit.access", [])
        if "health-records" in access:
            self.assertTrue(
                self.info.get("NSHealthClinicalHealthRecordsShareUsageDescription")
            )
        else:
            self.assertNotIn(
                "NSHealthClinicalHealthRecordsShareUsageDescription", self.info
            )


if __name__ == "__main__":
    unittest.main()
