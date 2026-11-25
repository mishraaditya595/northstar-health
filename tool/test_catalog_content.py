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


def source_programs():
    items = []
    for path in sorted((ROOT / "catalog/programs").glob("*.json")):
        items.extend(json.loads(path.read_text(encoding="utf-8")))
    return items


LEVEL_RANK = {"beginner": 0, "intermediate": 1, "advanced": 2}


def used_templates(program, templates_by_id):
    return [templates_by_id[day] for day in program["week"] if day is not None]


def program_shape_errors(programs, templates_by_id):
    errors = []
    for prog in programs:
        pid = prog["id"]
        days = used_templates(prog, templates_by_id)
        if not 2 <= prog["daysPerWeek"] <= 6:
            errors.append(f"{pid}: daysPerWeek outside 2 to 6")
        hardest = max((LEVEL_RANK[t["tags"]["level"]] for t in days), default=0)
        if LEVEL_RANK[prog["level"]] < hardest:
            errors.append(f"{pid}: level is easier than its hardest template")
        average = sum(t["estimatedMinutes"] for t in days) / max(len(days), 1)
        if abs(prog["estimatedMinutes"] - average) > 5:
            errors.append(f"{pid}: estimatedMinutes is not within 5 of {average:.0f}")
        text = prog["description"].strip()
        sentences = [x for x in re.split(r"(?<=[.!?])\s+", text) if x]
        if not text or len(sentences) > 2:
            errors.append(f"{pid}: description must be 1 or 2 sentences")
        if re.search(r"next week|week \d|this week", text, re.I):
            errors.append(f"{pid}: the schedule is a fixed repeating week")
        for value in (prog["name"], text):
            if OUTCOME_CLAIM.search(value):
                errors.append(f"{pid}: outcome claim in {value!r}")
    return errors


def program_equipment_errors(programs, templates_by_id):
    errors = []
    for prog in programs:
        used = set()
        for tpl in used_templates(prog, templates_by_id):
            used |= set(tpl["tags"]["equipment"])
        if len(used) > 1:
            used.discard("bodyweight")
        if set(prog["equipment"]) != used:
            errors.append(f"{prog['id']}: equipment {sorted(prog['equipment'])} != {sorted(used)}")
    return errors


def orphan_template_errors(programs, templates):
    used = {day for prog in programs for day in prog["week"] if day is not None}
    return [
        f"{tpl['id']}: program-only template is used by no program"
        for tpl in templates
        if tpl.get("standalone", True) is False and tpl["id"] not in used
    ]


def rest_spacing_errors(programs):
    errors = []
    for prog in programs:
        if prog["daysPerWeek"] > 4:
            continue
        week = [day is not None for day in prog["week"]]
        # The week repeats, so Sunday-to-Monday counts as consecutive too.
        for start in range(7):
            if all(week[(start + i) % 7] for i in range(3)):
                errors.append(f"{prog['id']}: 3 training days in a row")
                break
    return errors


class ProgramContentTest(unittest.TestCase):
    """Shape and safety rules for every source program (stage 7)."""

    def setUp(self):
        self.programs = source_programs()
        self.templates = source_templates()
        self.by_id = {t["id"]: t for t in self.templates}
        self.exercises = {e["id"]: e for e in source_exercises()}

    def test_programs_exist(self):
        self.assertGreaterEqual(len(self.programs), 8)

    def test_program_templates_loggable(self):
        for prog in self.programs:
            for day in prog["week"]:
                if day is None:
                    continue
                with self.subTest(msg=f"{prog['id']} {day}"):
                    self.assertIn(day, self.by_id)
                    for row in self.by_id[day]["exercises"]:
                        ex = self.exercises[row["exerciseId"]]
                        self.assertEqual(ex["status"], "active")
                        self.assertIn(ex["mode"], LOGGABLE_MODES)

    def test_program_shape(self):
        self.assertEqual(program_shape_errors(self.programs, self.by_id), [])

    def test_program_equipment_matches_templates(self):
        self.assertEqual(program_equipment_errors(self.programs, self.by_id), [])

    def test_no_orphan_program_templates(self):
        self.assertEqual(orphan_template_errors(self.programs, self.templates), [])

    def test_program_rest_spacing(self):
        self.assertEqual(rest_spacing_errors(self.programs), [])

    def test_program_only_templates_are_flagged(self):
        used = {d for p in self.programs for d in p["week"] if d}
        standalone_ids = {
            t["id"]
            for t in json.loads(
                (ROOT / "catalog/templates/standalone.json").read_text(encoding="utf-8")
            )
        }
        for tpl in self.templates:
            if tpl["id"] not in standalone_ids:
                with self.subTest(tpl["id"]):
                    self.assertIs(tpl.get("standalone"), False)
                    self.assertIn(tpl["id"], used)

    def test_pull_up_notes_match_the_rep_floor(self):
        for tpl in self.templates:
            for row in tpl["exercises"]:
                if row["exerciseId"] not in (
                    "builtin.v1.pull-up",
                    "builtin.v1.chin-up",
                ):
                    continue
                with self.subTest(msg=f"{tpl['id']} {row['exerciseId']}"):
                    note = row.get("note", "")
                    self.assertIn("assisted", note)
                    self.assertIn(f"{row['repsMin']} clean reps", note)

    def test_unilateral_rows_say_per_side(self):
        side = {
            "builtin.v1.reverse-lunge", "builtin.v1.walking-lunge",
            "builtin.v1.db-reverse-lunge", "builtin.v1.db-walking-lunge",
            "builtin.v1.single-leg-glute-bridge", "builtin.v1.bird-dog",
            "builtin.v1.dead-bug", "builtin.v1.side-plank",
            "builtin.v1.kb-single-leg-deadlift", "builtin.v1.kb-row",
            "builtin.v1.kb-press", "builtin.v1.kb-push-press",
            "builtin.v1.single-arm-cable-row", "builtin.v1.cable-glute-kickback",
        }
        for tpl in self.templates:
            for row in tpl["exercises"]:
                if row["exerciseId"] in side:
                    with self.subTest(msg=f"{tpl['id']} {row['exerciseId']}"):
                        self.assertIn("per side", row.get("note", ""))

    def test_checks_reject_bad_fixtures(self):
        tpl = {
            "id": "tpl.x",
            "tags": {"level": "advanced", "equipment": ["barbell", "bodyweight"]},
            "estimatedMinutes": 40,
            "standalone": False,
        }
        good = {
            "id": "prog.x", "name": "X", "description": "One. Two.",
            "level": "advanced", "daysPerWeek": 3, "estimatedMinutes": 40,
            "equipment": ["barbell"],
            "week": ["tpl.x", None, "tpl.x", None, "tpl.x", None, None],
        }
        by_id = {"tpl.x": tpl}
        self.assertEqual(program_shape_errors([good], by_id), [])
        self.assertEqual(program_equipment_errors([good], by_id), [])
        self.assertEqual(orphan_template_errors([good], [tpl]), [])
        self.assertEqual(rest_spacing_errors([good]), [])
        for change in (
            {"daysPerWeek": 1},
            {"level": "beginner"},
            {"estimatedMinutes": 50},
            {"description": "One. Two. Three."},
            {"description": "Burns fat fast."},
            {"description": "Start the next week with B."},
        ):
            with self.subTest(change=change):
                self.assertNotEqual(
                    program_shape_errors([{**good, **change}], by_id), []
                )
        self.assertNotEqual(
            program_equipment_errors([{**good, "equipment": ["barbell", "band"]}], by_id), []
        )
        self.assertNotEqual(orphan_template_errors([], [tpl]), [])
        three = {**good, "week": ["tpl.x", "tpl.x", "tpl.x", None, None, None, None]}
        self.assertNotEqual(rest_spacing_errors([three]), [])
        wrap = {**good, "week": ["tpl.x", "tpl.x", None, None, None, None, "tpl.x"]}
        self.assertNotEqual(rest_spacing_errors([wrap]), [])


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
