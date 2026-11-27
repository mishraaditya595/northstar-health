"""Offline tests for the Codemagic release-type version bump rules."""
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import codemagic_release_version as rv  # noqa: E402
from codemagic_release_version import ResolveError  # noqa: E402


class ReleaseVersionTest(unittest.TestCase):
    def test_parse_pads_short_versions(self):
        self.assertEqual(rv.parse_version("0.6"), (0, 6, 0))
        self.assertEqual(rv.parse_version("2"), (2, 0, 0))
        self.assertEqual(rv.parse_version(" 1.2.3 "), (1, 2, 3))
        self.assertIsNone(rv.parse_version("1.02.0"))
        self.assertIsNone(rv.parse_version("1.2.3.4"))
        self.assertIsNone(rv.parse_version(""))

    def test_highest_compares_numerically(self):
        self.assertEqual(rv.highest([(0, 9, 3), (1, 0, 0), (0, 10, 0)]), (1, 0, 0))
        self.assertIsNone(rv.highest([]))

    def test_format_version(self):
        self.assertEqual(rv.format_version((0, 6, 0)), "0.6.0")

    def test_release_types_order(self):
        self.assertEqual(rv.RELEASE_TYPES, (
            "Fix or optimisation", "Feature", "Major",
            "Same version, new build", "Exact version",
        ))

    def test_fix_feature_major_bumps(self):
        cur = (0, 6, 1)
        self.assertEqual(rv.next_version(rv.FIX, "AUTO", cur), (0, 6, 2))
        self.assertEqual(rv.next_version(rv.FEATURE, "AUTO", cur), (0, 7, 0))
        self.assertEqual(rv.next_version(rv.MAJOR, "AUTO", cur), (1, 0, 0))

    def test_no_current_version_starts_from_zero(self):
        self.assertEqual(rv.next_version(rv.FIX, "AUTO", None), (0, 0, 1))
        self.assertEqual(rv.next_version(rv.FEATURE, "AUTO", None), (0, 1, 0))

    def test_same_version_reuses_current(self):
        self.assertEqual(rv.next_version(rv.SAME, "AUTO", (0, 6, 1)), (0, 6, 1))
        with self.assertRaises(ResolveError) as ctx:
            rv.next_version(rv.SAME, "AUTO", None)
        self.assertIn("no version", str(ctx.exception))

    def test_exact_version_rules(self):
        cur = (0, 6, 1)
        self.assertEqual(rv.next_version(rv.EXACT, "0.7", cur), (0, 7, 0))
        self.assertEqual(rv.next_version(rv.EXACT, "0.6.1", cur), (0, 6, 1))
        with self.assertRaises(ResolveError) as ctx:
            rv.next_version(rv.EXACT, "0.6.0", cur)
        self.assertIn("0.6.1", str(ctx.exception))
        with self.assertRaises(ResolveError):
            rv.next_version(rv.EXACT, "AUTO", cur)
        with self.assertRaises(ResolveError):
            rv.next_version(rv.EXACT, "abc", cur)

    def test_exact_version_trims_and_rejects_prefix(self):
        self.assertEqual(rv.next_version(rv.EXACT, " 1.2.0 ", (0, 6, 1)), (1, 2, 0))
        with self.assertRaises(ResolveError):
            rv.next_version(rv.EXACT, "v1.2.0", (0, 6, 1))

    def test_version_name_with_non_exact_type_is_rejected(self):
        with self.assertRaises(ResolveError) as ctx:
            rv.next_version(rv.FIX, "1.2.0", (0, 6, 1))
        self.assertIn("Exact version", str(ctx.exception))

    def test_unknown_release_type_lists_choices(self):
        with self.assertRaises(ResolveError) as ctx:
            rv.next_version("feature", "AUTO", (0, 6, 1))
        for choice in rv.RELEASE_TYPES:
            self.assertIn(choice, str(ctx.exception))


if __name__ == "__main__":
    unittest.main()
