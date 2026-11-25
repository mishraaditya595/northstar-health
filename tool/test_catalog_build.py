"""Tests for catalogue assembly, canonical bytes and hashing."""
import contextlib
import hashlib
import io
import json
import shutil
import tempfile
import unittest
from pathlib import Path

from scripts.catalog_build import (
    assemble,
    canonical_bytes,
    digest,
    lock_entry,
    load_lock,
    main,
    render_publish_migration,
    render_rollback_migration,
)

REPO = Path(__file__).resolve().parent.parent


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


def tiny_snapshot(**extra):
    with tempfile.TemporaryDirectory() as tmp:
        write_root(tmp, {"exercises/e.json": [exercise("x", **extra)]})
        return assemble(Path(tmp), 1, "2026-11-26T00:00:00Z")


def temp_repo(tmp):
    shutil.copytree(REPO / "catalog", Path(tmp) / "catalog")
    # Start from the pre-release-1 state whatever the repository has published.
    (Path(tmp) / "catalog/releases.lock.json").write_text('{"releases": []}\n')
    (Path(tmp) / "catalog/CHANGELOG.md").write_text(
        "# Catalogue changelog\n\n## Unreleased\n\n- Starter content.\n"
    )
    (Path(tmp) / "supabase" / "migrations").mkdir(parents=True)
    return Path(tmp)


def run_cli(root, *args):
    out = io.StringIO()
    with contextlib.redirect_stdout(out), contextlib.redirect_stderr(out):
        code = main(list(args), root=root)
    return code, out.getvalue()


class MigrationTest(unittest.TestCase):
    def test_publish_migration_contains_canonical_json_and_sha(self):
        snap = tiny_snapshot(aliases=["Sumo \u00fc"])
        sha, size = digest(snap)
        sql = render_publish_migration(snap, sha, size)
        self.assertIn(canonical_bytes(snap).decode("utf-8"), sql)
        self.assertIn(sha, sql)
        self.assertIn("Generated by scripts/catalog_build.py; do not edit", sql)
        self.assertIn("northstar_private.publish_catalog_release(", sql)
        self.assertIn("$catalog$::jsonb", sql)

    def test_publish_refuses_dollar_tag_in_content(self):
        snap = tiny_snapshot(cues=["costs $catalog$ money"])
        with self.assertRaises(ValueError):
            render_publish_migration(snap, "a" * 64, 10)

    def test_rollback_requires_published_release(self):
        lock = {"releases": [{"release": 1, "sha256": "a" * 64}]}
        with self.assertRaises(ValueError):
            render_rollback_migration(7, lock)
        sql = render_rollback_migration(1, lock)
        self.assertIn("northstar_private.set_live_catalog_release(1)", sql)

    def test_publish_cli_writes_migration_and_lock(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = temp_repo(tmp)
            code, out = run_cli(
                root, "publish", "--timestamp", "20261126000100",
                "--published-at", "2026-11-26T00:00:00Z",
            )
            self.assertEqual(code, 0, out)
            sql = (root / "supabase/migrations/20261126000100_catalog_release_1.sql")
            self.assertTrue(sql.exists())
            lock = load_lock(root / "catalog/releases.lock.json")
            self.assertEqual(len(lock["releases"]), 1)
            entry = lock["releases"][0]
            self.assertEqual(entry["release"], 1)
            source = sum(
                len(json.loads(path.read_text(encoding="utf-8")))
                for path in (root / "catalog/exercises").glob("*.json")
            )
            self.assertEqual(len(entry["exercises"]), source)
            self.assertIn(entry["sha256"], sql.read_text(encoding="utf-8"))
            changelog = (root / "catalog/CHANGELOG.md").read_text(encoding="utf-8")
            self.assertIn("Release 1", changelog)
            self.assertIn(entry["sha256"], changelog)
            # A second publish of unchanged content must not reuse the release.
            code, _ = run_cli(
                root, "publish", "--timestamp", "20261126000200",
                "--published-at", "2026-11-27T00:00:00Z",
            )
            self.assertEqual(code, 0)
            self.assertEqual(len(load_lock(root / "catalog/releases.lock.json")["releases"]), 2)

    def test_rollback_cli(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = temp_repo(tmp)
            run_cli(root, "publish", "--timestamp", "20261126000100",
                    "--published-at", "2026-11-26T00:00:00Z")
            before = (root / "catalog/releases.lock.json").read_text()
            code, _ = run_cli(root, "rollback", "--to", "1", "--timestamp", "20261126000300")
            self.assertEqual(code, 0)
            self.assertTrue(
                (root / "supabase/migrations/20261126000300_catalog_rollback_to_1.sql").exists()
            )
            self.assertEqual((root / "catalog/releases.lock.json").read_text(), before)
            code, _ = run_cli(root, "rollback", "--to", "9", "--timestamp", "20261126000400")
            self.assertNotEqual(code, 0)
            self.assertFalse(
                (root / "supabase/migrations/20261126000400_catalog_rollback_to_9.sql").exists()
            )

    def test_check_cli_exits_nonzero_on_invalid(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = temp_repo(tmp)
            code, out = run_cli(root, "check")
            self.assertEqual(code, 0, out)
            self.assertIn("sha256", out)
            path = root / "catalog/exercises/legacy.json"
            data = json.loads(path.read_text(encoding="utf-8"))
            data[0]["primaryMuscles"] = ["quadz"]
            path.write_text(json.dumps(data), encoding="utf-8")
            code, out = run_cli(root, "check")
            self.assertEqual(code, 1)
            self.assertIn("quadz", out)
            code, _ = run_cli(root, "publish", "--timestamp", "20261126000100",
                              "--published-at", "2026-11-26T00:00:00Z")
            self.assertEqual(code, 1)
            self.assertEqual(list((root / "supabase/migrations").iterdir()), [])


class GeneratorSafetyTest(unittest.TestCase):
    def publish(self, root, ts="20261126000100"):
        return run_cli(root, "publish", "--timestamp", ts,
                       "--published-at", "2026-11-26T00:00:00Z")

    def test_publish_refuses_timestamp_not_later_than_newest_migration(self):
        for newest, ts in (("20261126000100", "20261126000100"),
                           ("20261126000100", "20261125235959")):
            with self.subTest(ts=ts), tempfile.TemporaryDirectory() as tmp:
                root = temp_repo(tmp)
                (root / "supabase/migrations" / f"{newest}_existing.sql").write_text("select 1;\n")
                lock_before = (root / "catalog/releases.lock.json").read_text()
                code, out = self.publish(root, ts)
                self.assertEqual(code, 1, out)
                self.assertIn("timestamp", out)
                self.assertEqual(
                    sorted(p.name for p in (root / "supabase/migrations").iterdir()),
                    [f"{newest}_existing.sql"])
                self.assertEqual((root / "catalog/releases.lock.json").read_text(), lock_before)

    def test_publish_refuses_existing_target_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = temp_repo(tmp)
            target = root / "supabase/migrations/20261126000100_catalog_release_1.sql"
            target.write_text("hand written\n")
            code, out = self.publish(root)
            self.assertEqual(code, 1, out)
            self.assertEqual(target.read_text(), "hand written\n")

    def test_rollback_refuses_old_timestamp_and_existing_file(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = temp_repo(tmp)
            self.assertEqual(self.publish(root)[0], 0)
            code, _ = run_cli(root, "rollback", "--to", "1", "--timestamp", "20261126000100")
            self.assertEqual(code, 1)
            code, _ = run_cli(root, "rollback", "--to", "1", "--timestamp", "20260101000000")
            self.assertEqual(code, 1)
            self.assertEqual(len(list((root / "supabase/migrations").iterdir())), 1)

    def test_failure_after_migration_write_leaves_nothing_behind(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = temp_repo(tmp)
            changelog = root / "catalog/CHANGELOG.md"
            changelog.unlink()
            changelog.mkdir()  # makes the changelog step fail
            lock_before = (root / "catalog/releases.lock.json").read_text()
            code, out = self.publish(root)
            self.assertEqual(code, 1, out)
            self.assertEqual(list((root / "supabase/migrations").iterdir()), [])
            self.assertEqual((root / "catalog/releases.lock.json").read_text(), lock_before)

    def test_check_names_the_placeholder_date(self):
        with tempfile.TemporaryDirectory() as tmp:
            code, out = run_cli(temp_repo(tmp), "check")
            self.assertEqual(code, 0)
            self.assertIn("placeholder publish date", out)


if __name__ == "__main__":
    unittest.main()
