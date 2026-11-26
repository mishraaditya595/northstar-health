"""Rule-by-rule tests for the catalogue snapshot validator."""
import copy
import unittest

from scripts import catalog_validate
from scripts.catalog_validate import EMPTY_LOCK, validate_snapshot


def valid_snapshot():
    return {
        "schemaVersion": 1,
        "minAppCatalogSchema": 1,
        "release": 1,
        "publishedAt": "2026-11-26T00:00:00Z",
        "provenance": {
            "source": "BeyondRep original",
            "license": "MPL-2.0",
            "attribution": "",
        },
        "exercises": [
            {
                "id": "builtin.v1.squat",
                "name": "Barbell back squat",
                "aliases": [],
                "muscleGroup": "Legs",
                "primaryMuscles": ["quads"],
                "secondaryMuscles": ["glutes"],
                "equipment": ["barbell"],
                "category": "squat",
                "mode": "reps_load",
                "cues": ["Brace before you descend"],
                "status": "active",
            },
            {
                "id": "builtin.v1.plank",
                "name": "Plank",
                "aliases": [],
                "muscleGroup": "Core",
                "primaryMuscles": ["abs"],
                "secondaryMuscles": [],
                "equipment": ["bodyweight"],
                "category": "core",
                "mode": "duration",
                "cues": ["Ribs down"],
                "status": "active",
            },
        ],
        "templates": [
            {
                "id": "tpl.test",
                "name": "Test",
                "description": "A test template.",
                "tags": {
                    "goal": ["strength"],
                    "level": "beginner",
                    "equipment": ["barbell"],
                },
                "estimatedMinutes": 45,
                "standalone": True,
                "exercises": [
                    {
                        "exerciseId": "builtin.v1.squat",
                        "sets": 3,
                        "repsMin": 5,
                        "repsMax": 8,
                        "restSeconds": 120,
                        "note": "",
                    },
                    {
                        "exerciseId": "builtin.v1.plank",
                        "sets": 3,
                        "durationSeconds": 45,
                        "restSeconds": 60,
                    },
                ],
            }
        ],
        "programs": [
            {
                "id": "prog.test",
                "name": "Test program",
                "description": "A test program.",
                "goals": ["strength"],
                "level": "beginner",
                "daysPerWeek": 1,
                "estimatedMinutes": 45,
                "equipment": ["barbell"],
                "week": ["tpl.test", None, None, None, None, None, None],
            }
        ],
    }


def lock_with(**release):
    entry = {
        "release": 1,
        "sha256": "a" * 64,
        "exercises": {},
        "retired": [],
        "templates": [],
        "programs": [],
    }
    entry.update(release)
    return {"releases": [entry]}


def mutated(fn):
    snap = valid_snapshot()
    fn(snap)
    return snap


def has_error(errors, text):
    return any(text in e for e in errors)


class ValidatorTest(unittest.TestCase):
    def test_valid_snapshot_has_no_errors(self):
        self.assertEqual(validate_snapshot(valid_snapshot(), EMPTY_LOCK), [])

    def test_schema_violation_reported(self):
        snap = valid_snapshot()
        del snap["exercises"]
        errors = validate_snapshot(snap, EMPTY_LOCK)
        self.assertTrue(errors)
        self.assertTrue(has_error(errors, "exercises"))

    def test_float_anywhere_rejected(self):
        snap = mutated(lambda s: s["templates"][0].update(estimatedMinutes=45.0))
        errors = validate_snapshot(snap, EMPTY_LOCK)
        self.assertTrue(has_error(errors, "float"))

    def test_duplicate_id_within_validator(self):
        def f(s):
            s["exercises"].append(copy.deepcopy(s["exercises"][0]))

        errors = validate_snapshot(mutated(f), EMPTY_LOCK)
        self.assertTrue(has_error(errors, "duplicate id builtin.v1.squat"))

    def test_duplicate_id_across_kinds_rejected(self):
        snap = mutated(lambda s: s["templates"][0].update(id="builtin.v1.squat"))
        self.assertTrue(validate_snapshot(snap, EMPTY_LOCK))

    def test_schema_enforces_id_patterns(self):
        for key, bad in (("exercises", "builtin.v1.Bad"), ("templates", "tpl-x"),
                         ("programs", "prog_x")):
            with self.subTest(key):
                snap = mutated(lambda s: s[key][0].update(id=bad))
                errors = validate_snapshot(snap, EMPTY_LOCK)
                self.assertTrue(has_error(errors, "schema:"), errors)

    def test_published_at_must_be_utc_rfc3339(self):
        for bad in ("2026-11-26", "2026-11-26T00:00:00+01:00",
                    "2026-11-26 00:00:00Z", "2026-13-40T00:00:00Z"):
            with self.subTest(bad):
                snap = mutated(lambda s: s.update(publishedAt=bad))
                self.assertTrue(validate_snapshot(snap, EMPTY_LOCK))
        snap = mutated(lambda s: s.update(publishedAt="2026-11-26T00:00:00.5Z"))
        self.assertEqual(validate_snapshot(snap, EMPTY_LOCK), [])

    def test_muscle_both_primary_and_secondary(self):
        snap = mutated(lambda s: s["exercises"][0].update(
            primaryMuscles=["quads"], secondaryMuscles=["quads", "glutes"]))
        errors = validate_snapshot(snap, EMPTY_LOCK)
        self.assertTrue(has_error(errors, "builtin.v1.squat"))
        self.assertTrue(has_error(errors, "primary and secondary"))

    def test_control_characters_rejected(self):
        for bad in ("Squat\nrow", "Tab\there", "Nul\u0000", "Del\u007f"):
            with self.subTest(repr(bad)):
                snap = mutated(lambda s: s["exercises"][0].update(name=bad))
                errors = validate_snapshot(snap, EMPTY_LOCK)
                self.assertTrue(has_error(errors, "control character"), errors)

    def test_snapshot_size_limit(self):
        self.assertEqual(catalog_validate.MAX_SNAPSHOT_BYTES, 2 * 1024 * 1024)
        old = catalog_validate.MAX_SNAPSHOT_BYTES
        catalog_validate.MAX_SNAPSHOT_BYTES = 100
        try:
            errors = validate_snapshot(valid_snapshot(), EMPTY_LOCK)
        finally:
            catalog_validate.MAX_SNAPSHOT_BYTES = old
        self.assertTrue(has_error(errors, "snapshot size"))

    def test_bad_id_prefix_or_slug(self):
        snap = mutated(lambda s: s["exercises"][0].update(id="builtin.v1.Bad_Slug"))
        self.assertTrue(validate_snapshot(snap, EMPTY_LOCK))
        snap = mutated(lambda s: s["templates"][0].update(id="tpl-x"))
        self.assertTrue(validate_snapshot(snap, EMPTY_LOCK))

    def test_unknown_muscle(self):
        snap = mutated(lambda s: s["exercises"][0].update(primaryMuscles=["quadz"]))
        self.assertTrue(validate_snapshot(snap, EMPTY_LOCK))

    def test_no_primary_muscle(self):
        snap = mutated(lambda s: s["exercises"][0].update(primaryMuscles=[]))
        self.assertTrue(validate_snapshot(snap, EMPTY_LOCK))

    def test_unknown_equipment(self):
        snap = mutated(lambda s: s["exercises"][0].update(equipment=["jetpack"]))
        self.assertTrue(validate_snapshot(snap, EMPTY_LOCK))

    def test_unknown_group(self):
        snap = mutated(lambda s: s["exercises"][0].update(muscleGroup="Neck"))
        self.assertTrue(validate_snapshot(snap, EMPTY_LOCK))

    def test_unknown_exercise_reference(self):
        snap = mutated(
            lambda s: s["templates"][0]["exercises"][0].update(
                exerciseId="builtin.v1.ghost"
            )
        )
        errors = validate_snapshot(snap, EMPTY_LOCK)
        self.assertTrue(has_error(errors, "builtin.v1.ghost"))

    def test_unknown_template_reference(self):
        snap = mutated(
            lambda s: s["programs"][0].update(
                week=["tpl.ghost", None, None, None, None, None, None]
            )
        )
        errors = validate_snapshot(snap, EMPTY_LOCK)
        self.assertTrue(has_error(errors, "tpl.ghost"))

    def test_template_references_retired_exercise(self):
        snap = mutated(lambda s: s["exercises"][0].update(status="retired"))
        errors = validate_snapshot(snap, EMPTY_LOCK)
        self.assertTrue(has_error(errors, "retired"))
        self.assertTrue(has_error(errors, "builtin.v1.squat"))

    def test_status_is_optional_and_defaults_to_active(self):
        snap = valid_snapshot()
        self.assertNotIn("status", snap["templates"][0])
        self.assertNotIn("status", snap["programs"][0])
        self.assertEqual(validate_snapshot(snap, EMPTY_LOCK), [])
        snap["templates"][0]["status"] = "active"
        snap["programs"][0]["status"] = "active"
        self.assertEqual(validate_snapshot(snap, EMPTY_LOCK), [])

    def test_status_must_be_active_or_retired(self):
        for key in ("templates", "programs"):
            snap = mutated(lambda s, k=key: s[k][0].update(status="archived"))
            errors = validate_snapshot(snap, EMPTY_LOCK)
            self.assertTrue(has_error(errors, "status"), key)

    def test_active_program_cannot_use_retired_template(self):
        snap = mutated(lambda s: s["templates"][0].update(status="retired"))
        errors = validate_snapshot(snap, EMPTY_LOCK)
        self.assertTrue(has_error(errors, "prog.test"))
        self.assertTrue(has_error(errors, "tpl.test"))
        self.assertTrue(has_error(errors, "retired"))

    def test_retired_program_may_keep_its_retired_template(self):
        def retire(s):
            s["templates"][0]["status"] = "retired"
            s["programs"][0]["status"] = "retired"

        self.assertEqual(validate_snapshot(mutated(retire), EMPTY_LOCK), [])

    def test_retired_program_may_use_an_active_template(self):
        snap = mutated(lambda s: s["programs"][0].update(status="retired"))
        self.assertEqual(validate_snapshot(snap, EMPTY_LOCK), [])

    def test_retired_template_must_still_use_active_exercises(self):
        # Older apps ignore status and still reject retired exercises.
        def retire(s):
            s["templates"][0]["status"] = "retired"
            s["programs"][0]["status"] = "retired"
            s["exercises"][0]["status"] = "retired"

        errors = validate_snapshot(mutated(retire), EMPTY_LOCK)
        self.assertTrue(has_error(errors, "retired exercise"))
        self.assertTrue(has_error(errors, "builtin.v1.squat"))

    def test_week_must_have_seven_entries(self):
        snap = mutated(lambda s: s["programs"][0].update(week=["tpl.test", None]))
        self.assertTrue(validate_snapshot(snap, EMPTY_LOCK))

    def test_program_needs_training_day(self):
        snap = mutated(
            lambda s: s["programs"][0].update(week=[None] * 7, daysPerWeek=0)
        )
        errors = validate_snapshot(snap, EMPTY_LOCK)
        self.assertTrue(has_error(errors, "prog.test"))

    def test_days_per_week_mismatch(self):
        snap = mutated(lambda s: s["programs"][0].update(daysPerWeek=3))
        errors = validate_snapshot(snap, EMPTY_LOCK)
        self.assertTrue(has_error(errors, "daysPerWeek"))

    def test_ranges(self):
        def set_ex(i, **kw):
            def f(s):
                s["templates"][0]["exercises"][i].update(kw)
            return f

        cases = {
            "sets 0": set_ex(0, sets=0),
            "sets 31": set_ex(0, sets=31),
            "repsMin 0": set_ex(0, repsMin=0),
            "repsMin > repsMax": set_ex(0, repsMin=9, repsMax=8),
            "reps over 1000": set_ex(0, repsMax=1001),
            "rest 3601": set_ex(0, restSeconds=3601),
            "duration 0": set_ex(1, durationSeconds=0),
            "duration 3601": set_ex(1, durationSeconds=3601),
        }
        for label, fn in cases.items():
            with self.subTest(label):
                self.assertTrue(validate_snapshot(mutated(fn), EMPTY_LOCK))

    def test_reps_on_duration_exercise(self):
        def f(s):
            ex = s["templates"][0]["exercises"][1]
            del ex["durationSeconds"]
            ex.update(repsMin=5, repsMax=8)

        errors = validate_snapshot(mutated(f), EMPTY_LOCK)
        self.assertTrue(has_error(errors, "builtin.v1.plank"))

    def test_duration_on_reps_exercise(self):
        def f(s):
            ex = s["templates"][0]["exercises"][0]
            del ex["repsMin"], ex["repsMax"]
            ex["durationSeconds"] = 30

        errors = validate_snapshot(mutated(f), EMPTY_LOCK)
        self.assertTrue(has_error(errors, "builtin.v1.squat"))

    def test_both_reps_and_duration(self):
        snap = mutated(
            lambda s: s["templates"][0]["exercises"][0].update(durationSeconds=30)
        )
        errors = validate_snapshot(snap, EMPTY_LOCK)
        self.assertTrue(has_error(errors, "builtin.v1.squat"))

    def test_mode_change_against_lock(self):
        lock = lock_with(exercises={"builtin.v1.squat": "reps"})
        snap = valid_snapshot()
        snap["release"] = 2
        errors = validate_snapshot(snap, lock)
        self.assertTrue(has_error(errors, "builtin.v1.squat"))
        self.assertTrue(has_error(errors, "mode"))

    def test_removed_id_against_lock(self):
        lock = lock_with(
            exercises={"builtin.v1.squat": "reps_load", "builtin.v1.deadlift": "reps_load"}
        )
        snap = valid_snapshot()
        snap["release"] = 2
        errors = validate_snapshot(snap, lock)
        self.assertTrue(has_error(errors, "builtin.v1.deadlift"))
        self.assertTrue(has_error(errors, "removed"))

    def test_retired_slug_reused(self):
        lock = lock_with(retired=["builtin.v1.old"])
        snap = valid_snapshot()
        snap["release"] = 2
        snap["exercises"].append(
            dict(copy.deepcopy(snap["exercises"][0]), id="builtin.v1.old")
        )
        errors = validate_snapshot(snap, lock)
        self.assertTrue(has_error(errors, "builtin.v1.old"))
        self.assertTrue(has_error(errors, "retired"))

    def test_kind_change_against_lock(self):
        lock = lock_with(
            exercises={"builtin.v1.squat": "reps_load", "builtin.v1.plank": "duration"},
            programs=["tpl.test"],
        )
        snap = valid_snapshot()
        snap["release"] = 2
        errors = validate_snapshot(snap, lock)
        self.assertTrue(has_error(errors, "tpl.test"))
        self.assertTrue(has_error(errors, "kind"))

    def test_release_must_exceed_lock(self):
        lock = lock_with(
            exercises={"builtin.v1.squat": "reps_load", "builtin.v1.plank": "duration"}
        )
        errors = validate_snapshot(valid_snapshot(), lock)
        self.assertTrue(has_error(errors, "release"))


if __name__ == "__main__":
    unittest.main()
