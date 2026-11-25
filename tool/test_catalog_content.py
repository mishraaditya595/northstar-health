"""Checks on the repository's catalogue source content."""
import json
import re
import unittest
from pathlib import Path

from scripts.catalog_build import assemble, load_lock
from scripts.catalog_validate import MUSCLES, validate_snapshot

ROOT = Path(__file__).resolve().parent.parent
DART_EXERCISES = (
    ROOT / "apps/mobile/lib/features/workouts/data/built_in_exercises.dart"
)
DART_MUSCLES = ROOT / "apps/mobile/lib/features/progress/muscle_recovery.dart"


def source_exercises():
    items = []
    for path in sorted((ROOT / "catalog/exercises").glob("*.json")):
        items.extend(json.loads(path.read_text(encoding="utf-8")))
    return items


class ContentTest(unittest.TestCase):
    def test_repo_catalog_validates(self):
        lock = load_lock(ROOT / "catalog/releases.lock.json")
        nxt = 1 + max((r["release"] for r in lock["releases"]), default=0)
        snap = assemble(ROOT / "catalog", nxt, "2026-11-26T00:00:00Z")
        self.assertEqual(validate_snapshot(snap, lock), [])

    def test_legacy_ids_present_with_same_names_and_modes(self):
        text = DART_EXERCISES.read_text(encoding="utf-8")
        legacy = re.findall(
            r"id:\s*'([^']+)',\s*name:\s*'([^']+)',\s*muscle:\s*'([^']+)',"
            r"(?:.|\n)*?mode:\s*'([^']+)'",
            text,
        )
        self.assertEqual(len(legacy), 18)
        by_id = {e["id"]: e for e in source_exercises()}
        for slug, name, muscle, mode in legacy:
            with self.subTest(slug):
                ex = by_id[f"builtin.v1.{slug}"]
                self.assertEqual(ex["name"], name)
                self.assertEqual(ex["muscleGroup"], muscle)
                self.assertEqual(ex["mode"], mode)

    def test_muscle_vocabulary_matches_dart_enum(self):
        body = re.search(
            r"enum Muscle\s*\{([^}]*)\}", DART_MUSCLES.read_text(encoding="utf-8")
        ).group(1)
        members = {m.strip() for m in body.split(",") if m.strip()}
        self.assertEqual(members, set(MUSCLES))

    def test_no_media_or_url_fields(self):
        bad_key = re.compile(r"image|video|gif|url|media", re.I)

        def walk(node):
            if isinstance(node, dict):
                for key, value in node.items():
                    self.assertIsNone(bad_key.search(key), key)
                    walk(value)
            elif isinstance(node, list):
                for value in node:
                    walk(value)
            elif isinstance(node, str):
                self.assertNotIn("http", node)

        walk(source_exercises())


if __name__ == "__main__":
    unittest.main()
