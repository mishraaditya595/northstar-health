"""Checks on the repository's catalogue source content."""
import json
import re
import unittest
from pathlib import Path

from scripts.catalog_build import (
    assemble,
    canonical_bytes,
    digest,
    load_lock,
    lock_entry,
)
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

    def test_aliases_do_not_name_a_different_movement(self):
        by_id = {e["id"]: e for e in source_exercises()}
        # A chin-up is a different (supinated) lift than the pull-up, and a
        # stiff-leg deadlift differs from the Romanian deadlift.
        self.assertNotIn("Chin-up", by_id["builtin.v1.pull-up"]["aliases"])
        self.assertNotIn("Stiff-leg deadlift", by_id["builtin.v1.rdl"]["aliases"])

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


class PublishedReleaseTest(unittest.TestCase):
    """Each committed release migration must be exactly what the lock records."""

    def release_files(self):
        found = {}
        for path in sorted((ROOT / "supabase/migrations").glob("*_catalog_release_*.sql")):
            number = int(re.search(r"_catalog_release_(\d+)\.sql$", path.name).group(1))
            self.assertNotIn(number, found, f"two migrations publish release {number}")
            found[number] = path
        return found

    def test_release_migrations_match_lock_one_to_one(self):
        lock = load_lock(ROOT / "catalog/releases.lock.json")
        entries = {}
        for entry in lock["releases"]:
            self.assertNotIn(entry["release"], entries, "duplicate lock entry")
            entries[entry["release"]] = entry
        files = self.release_files()
        self.assertEqual(set(files), set(entries))
        for number, path in files.items():
            with self.subTest(release=number):
                text = path.read_text(encoding="utf-8")
                match = re.search(
                    r"\$catalog\$(.*)\$catalog\$::jsonb,\n  '([0-9a-f]{64})',\n"
                    r"  (\d+),\n  '([^']+)'::timestamptz\n\);\n$",
                    text, re.S,
                )
                self.assertIsNotNone(match, "unexpected migration shape")
                body, call_sha, call_size, call_at = match.groups()
                header_sha = re.search(r"^-- sha256: ([0-9a-f]{64})$", text, re.M).group(1)
                snapshot = json.loads(body)
                self.assertEqual(canonical_bytes(snapshot), body.encode("utf-8"))
                sha, size = digest(snapshot)
                self.assertEqual({sha}, {header_sha, call_sha, entries[number]["sha256"]})
                self.assertEqual(size, int(call_size))
                self.assertEqual(snapshot["release"], number)
                self.assertEqual(snapshot["publishedAt"], call_at)
                self.assertEqual(lock_entry(snapshot, sha), entries[number])


if __name__ == "__main__":
    unittest.main()
