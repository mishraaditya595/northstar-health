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


LOGGABLE_MODES = {"reps_load", "duration"}
OUTCOME_CLAIM = re.compile(
    r"\b(burn\w*|fat loss|tone[sd]?|toning|prevent\w* injur\w*|cure[sd]?|"
    r"guarantee\w*)\b",
    re.I,
)
LEGACY_SHA256 = "c0dd24bb15ce2319dc3478f50b6be8fc25a626075c8e5348eb6f7d34da8d3509"


class ExerciseStyleTest(unittest.TestCase):
    """Style and safety rules for every source exercise (stage 5 content)."""

    def test_new_exercises_use_loggable_modes(self):
        for ex in source_exercises():
            with self.subTest(ex["id"]):
                self.assertIn(ex["mode"], LOGGABLE_MODES)

    def test_names_and_aliases_are_unique(self):
        exercises = source_exercises()
        names = {}
        for ex in exercises:
            key = ex["name"].casefold()
            self.assertNotIn(key, names, f"duplicate name {ex['name']}")
            names[key] = ex["id"]
        seen = {}
        for ex in exercises:
            for alias in ex["aliases"]:
                key = alias.casefold()
                self.assertNotIn(key, seen, f"duplicate alias {alias}")
                seen[key] = ex["id"]
                if key in names:
                    self.assertEqual(names[key], ex["id"], f"alias {alias} is another exercise")
                    self.fail(f"alias {alias} repeats its own exercise name")

    def test_cue_style(self):
        for ex in source_exercises():
            with self.subTest(ex["id"]):
                # Legacy exercises have 3 cues each, so the same bounds apply.
                self.assertGreaterEqual(len(ex["cues"]), 2)
                self.assertLessEqual(len(ex["cues"]), 4)
                for cue in ex["cues"]:
                    self.assertFalse(cue.endswith("."), cue)
                    self.assertNotIn("http", cue)

    def test_no_outcome_claims(self):
        for ex in source_exercises():
            for text in [ex["name"], *ex["aliases"], *ex["cues"]]:
                with self.subTest(ex["id"], text=text):
                    self.assertIsNone(OUTCOME_CLAIM.search(text))

    def test_outcome_claim_matches_whole_words_only(self):
        self.assertIsNone(OUTCOME_CLAIM.search("Secure the pin"))
        self.assertIsNone(OUTCOME_CLAIM.search("Stone grip"))
        self.assertIsNotNone(OUTCOME_CLAIM.search("Burn fat"))
        self.assertIsNotNone(OUTCOME_CLAIM.search("Tone your arms"))
        self.assertIsNotNone(OUTCOME_CLAIM.search("Helps prevent injury"))

    def test_generic_closing_cues_are_not_overused(self):
        generic = ("lower slowly", "return slowly", "lower under control")
        counts = {g: 0 for g in generic}
        for ex in source_exercises():
            for cue in ex["cues"]:
                if cue.casefold() in counts:
                    counts[cue.casefold()] += 1
        for cue, n in counts.items():
            with self.subTest(cue):
                self.assertLessEqual(n, 5)

    def test_primary_count(self):
        for ex in source_exercises():
            with self.subTest(ex["id"]):
                self.assertTrue(1 <= len(ex["primaryMuscles"]) <= 3)

    @unittest.skipUnless(len(source_exercises()) > 200, "full library not landed yet")
    def test_every_muscle_is_well_covered(self):
        counts = {m: 0 for m in MUSCLES}
        for ex in source_exercises():
            if ex["status"] == "active":
                for m in ex["primaryMuscles"]:
                    counts[m] += 1
        for muscle, n in counts.items():
            with self.subTest(muscle):
                self.assertGreaterEqual(n, 5)

    def test_legacy_file_unchanged(self):
        import hashlib

        data = (ROOT / "catalog/exercises/legacy.json").read_bytes()
        self.assertEqual(hashlib.sha256(data).hexdigest(), LEGACY_SHA256)


def source_templates():
    items = []
    for path in sorted((ROOT / "catalog/templates").glob("*.json")):
        items.extend(json.loads(path.read_text(encoding="utf-8")))
    return items


class TemplateContentTest(unittest.TestCase):
    """Shape and safety rules for every source workout template (stage 6)."""

    def setUp(self):
        self.exercises = {e["id"]: e for e in source_exercises()}

    def test_templates_reference_loggable_active_exercises(self):
        for tpl in source_templates():
            for row in tpl["exercises"]:
                with self.subTest(msg=f"{tpl['id']} {row['exerciseId']}"):
                    ex = self.exercises[row["exerciseId"]]
                    self.assertEqual(ex["status"], "active")
                    self.assertIn(ex["mode"], LOGGABLE_MODES)

    def test_template_shape(self):
        for tpl in source_templates():
            with self.subTest(tpl["id"]):
                ids = [r["exerciseId"] for r in tpl["exercises"]]
                self.assertTrue(4 <= len(ids) <= 7, "4 to 7 exercises")
                self.assertEqual(len(ids), len(set(ids)), "exercise repeated")
                self.assertTrue(20 <= tpl["estimatedMinutes"] <= 75)
                text = tpl["description"].strip()
                self.assertTrue(text, "description is empty")
                sentences = [x for x in re.split(r"(?<=[.!?])\s+", text) if x]
                self.assertLessEqual(len(sentences), 2)
                for value in (tpl["name"], text, *(r.get("note", "") for r in tpl["exercises"])):
                    self.assertIsNone(OUTCOME_CLAIM.search(value), value)

    def test_template_prescriptions_are_conservative(self):
        for tpl in source_templates():
            with self.subTest(tpl["id"]):
                total = sum(r["sets"] for r in tpl["exercises"])
                limit = 18 if tpl["tags"]["level"] == "beginner" else 24
                self.assertLessEqual(total, limit)
                for row in tpl["exercises"]:
                    if row.get("repsMax", 99) <= 8:
                        self.assertGreaterEqual(row["restSeconds"], 60)

    def test_template_equipment_tag_matches_exercises(self):
        for tpl in source_templates():
            with self.subTest(tpl["id"]):
                used = set()
                for row in tpl["exercises"]:
                    used |= set(self.exercises[row["exerciseId"]]["equipment"])
                if len(used) > 1:
                    used.discard("bodyweight")
                self.assertEqual(set(tpl["tags"]["equipment"]), used)


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
