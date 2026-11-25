"""Tests for catalogue assembly, canonical bytes and hashing."""
import hashlib
import json
import tempfile
import unittest
from pathlib import Path

from scripts.catalog_build import (
    assemble,
    canonical_bytes,
    digest,
    lock_entry,
    load_lock,
)


def exercise(slug, **extra):
    base = {
        "id": f"builtin.v1.{slug}",
        "name": slug.title(),
        "aliases": [],
        "muscleGroup": "Legs",
        "primaryMuscles": ["quads"],
        "secondaryMuscles": [],
        "equipment": ["barbell"],
        "category": "squat",
        "mode": "reps_load",
        "cues": ["Brace"],
        "status": "active",
    }
    base.update(extra)
    return base


def write_root(root, files):
    for rel, data in files.items():
        path = Path(root) / rel
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(data), encoding="utf-8")


class BuildTest(unittest.TestCase):
    def test_assemble_sorts_and_merges(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_root(tmp, {
                "exercises/a.json": [exercise("zeta")],
                "exercises/b.json": [exercise("alpha")],
            })
            snap = assemble(Path(tmp), 1, "2026-11-26T00:00:00Z")
        self.assertEqual(
            [e["id"] for e in snap["exercises"]],
            ["builtin.v1.alpha", "builtin.v1.zeta"],
        )
        self.assertEqual(snap["templates"], [])
        self.assertEqual(snap["programs"], [])
        self.assertEqual(snap["release"], 1)
        self.assertEqual(snap["provenance"]["license"], "MPL-2.0")

    def test_canonical_bytes_deterministic(self):
        alias = "Sumo-Kreuzheben ü"
        first = exercise("x", aliases=[alias])
        reordered = dict(reversed(list(first.items())))
        with tempfile.TemporaryDirectory() as a, tempfile.TemporaryDirectory() as b:
            write_root(a, {"exercises/e.json": [first]})
            write_root(b, {"exercises/e.json": [reordered]})
            one = canonical_bytes(assemble(Path(a), 1, "2026-11-26T00:00:00Z"))
            two = canonical_bytes(assemble(Path(b), 1, "2026-11-26T00:00:00Z"))
        self.assertEqual(one, two)
        self.assertIn("ü".encode("utf-8"), one)
        self.assertNotIn(b"\\u00fc", one)
        self.assertNotIn(b": ", one)
        self.assertNotIn(b", ", one)
        self.assertFalse(one.endswith(b"\n"))

    def test_digest_matches_hashlib(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_root(tmp, {"exercises/e.json": [exercise("x")]})
            snap = assemble(Path(tmp), 1, "2026-11-26T00:00:00Z")
        raw = canonical_bytes(snap)
        self.assertEqual(digest(snap), (hashlib.sha256(raw).hexdigest(), len(raw)))

    def test_lock_entry_records_modes_and_retired(self):
        with tempfile.TemporaryDirectory() as tmp:
            write_root(tmp, {"exercises/e.json": [
                exercise("a"),
                exercise("b", mode="duration", status="retired"),
            ]})
            snap = assemble(Path(tmp), 3, "2026-11-26T00:00:00Z")
        entry = lock_entry(snap, "f" * 64)
        self.assertEqual(entry["release"], 3)
        self.assertEqual(entry["sha256"], "f" * 64)
        self.assertEqual(
            entry["exercises"],
            {"builtin.v1.a": "reps_load", "builtin.v1.b": "duration"},
        )
        self.assertEqual(entry["retired"], ["builtin.v1.b"])
        self.assertEqual(entry["templates"], [])
        self.assertEqual(entry["programs"], [])

    def test_load_lock_missing_file_is_empty(self):
        with tempfile.TemporaryDirectory() as tmp:
            self.assertEqual(load_lock(Path(tmp) / "none.json"), {"releases": []})


if __name__ == "__main__":
    unittest.main()
