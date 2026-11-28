"""Guards the Health Connect write permissions declared by the Android app.

BeyondRep writes only these records: the opt-in workout summary
(WRITE_EXERCISE, ADR-0014), the heart rate and calories of a Wear OS watch
workout (WRITE_HEART_RATE, WRITE_TOTAL_CALORIES_BURNED, ADR-0015) and the
weights the user logs (WRITE_WEIGHT, ADR-0016). Any other health write
permission needs a new ADR.
"""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = (
    ROOT / "apps" / "mobile" / "android" / "app" / "src" / "main" / "AndroidManifest.xml"
)
HEALTH = "android.permission.health."


class AndroidHealthPermissionsTest(unittest.TestCase):
    def setUp(self):
        text = MANIFEST.read_text(encoding="utf-8")
        self.declared = set(
            re.findall(r'<uses-permission\s+android:name="([^"]+)"', text)
        )

    def test_write_weight_is_declared(self):
        self.assertIn(HEALTH + "WRITE_WEIGHT", self.declared)

    def test_only_the_adr_approved_writes(self):
        writes = {
            name[len(HEALTH):]
            for name in self.declared
            if name.startswith(HEALTH + "WRITE_")
        }
        self.assertEqual(
            writes,
            {
                "WRITE_EXERCISE",
                "WRITE_HEART_RATE",
                "WRITE_TOTAL_CALORIES_BURNED",
                "WRITE_WEIGHT",
            },
        )


if __name__ == "__main__":
    unittest.main()
