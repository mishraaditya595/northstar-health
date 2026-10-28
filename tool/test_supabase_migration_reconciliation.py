"""Synthetic contract tests for CLI migration-list reconciliation."""
from pathlib import Path
import tempfile
import unittest

from scripts.check_supabase_migrations import check_migrations


class MigrationReconciliationTest(unittest.TestCase):
    def setUp(self):
        self.root = tempfile.TemporaryDirectory()
        self.addCleanup(self.root.cleanup)
        self.directory = Path(self.root.name)
        self.versions = ("20261025060300", "20261027180000")
        for version in self.versions:
            (self.directory / (version + "_synthetic.sql")).write_text(
                "-- synthetic\n", encoding="utf-8",
            )

    def table(self, *, remote=None):
        remote = set(self.versions if remote is None else remote)
        rows = ["  Local | Remote | Time (UTC)", "--------|--------|-----------"]
        for version in self.versions:
            rows.append(f" {version} | {version if version in remote else ''} | 2026")
        return "\n".join(rows)

    def test_aligned_versions(self):
        result = check_migrations(self.table(), self.directory)
        self.assertIn("2 local/remote migration versions are aligned", result)

    def test_supabase_cli_unicode_table_separators(self):
        table = self.table().replace("|", "│")
        result = check_migrations(table, self.directory)
        self.assertIn("2 local/remote migration versions are aligned", result)

    def test_pending_last_session_gate_is_blocking(self):
        with self.assertRaisesRegex(ValueError, "1 migration\\(s\\) still pending"):
            check_migrations(
                self.table(remote={self.versions[0]}), self.directory,
            )

    def test_preview_reports_pending_without_authorizing_function_deploy(self):
        result = check_migrations(
            self.table(remote={self.versions[0]}),
            self.directory,
            report_only=True,
        )
        self.assertIn("1/2 migration versions applied", result)
        self.assertIn("1 pending", result)
        self.assertNotIn("Verified", result)

    def test_preview_reports_up_to_date_without_sql_integrity_claim(self):
        result = check_migrations(
            self.table(), self.directory, report_only=True,
        )
        self.assertIn("versions are aligned", result)

    def test_preview_rejects_unparseable_and_extra_remote_history(self):
        with self.assertRaisesRegex(ValueError, "does not match local files"):
            check_migrations("unrecognized CLI output", self.directory,
                             report_only=True)
        with self.assertRaisesRegex(ValueError, "19990101000000"):
            check_migrations(
                self.table() + "\n | 19990101000000 | extra\n",
                self.directory,
                report_only=True,
            )

    def test_no_parsable_rows_are_not_up_to_date(self):
        with self.assertRaisesRegex(ValueError, "does not match local files"):
            check_migrations("Up to date!\n", self.directory)

    def test_remote_history_drift_is_blocking(self):
        table = self.table() + "\n  | 19990101000000 | unexpected\n"
        with self.assertRaisesRegex(ValueError, "absent locally"):
            check_migrations(table, self.directory)

    def test_remote_only_versions_are_named_and_sorted(self):
        table = (
            self.table()
            + "\n | 20270101000000 | unexpected\n"
            + " | 20250101000000 | unexpected\n"
        )
        with self.assertRaisesRegex(
            ValueError,
            "absent locally: 20250101000000, 20270101000000",
        ):
            check_migrations(table, self.directory)
        with self.assertRaisesRegex(
            ValueError,
            "absent locally: 20250101000000, 20270101000000",
        ):
            check_migrations(table, self.directory, report_only=True)

    def test_misaligned_row_is_blocking(self):
        table = self.table().replace(
            self.versions[0] + " | " + self.versions[0],
            self.versions[0] + " | " + self.versions[1],
        )
        with self.assertRaisesRegex(ValueError, "diverge"):
            check_migrations(table, self.directory)

    def test_duplicates_are_blocking(self):
        table = self.table() + f"\n | {self.versions[0]} | duplicate\n"
        with self.assertRaisesRegex(ValueError, "duplicate versions"):
            check_migrations(table, self.directory)

    def test_missing_repository_migration_is_blocking(self):
        (self.directory / "20261027180000_synthetic.sql").unlink()
        with self.assertRaisesRegex(ValueError, "does not match local files"):
            check_migrations(self.table(), self.directory)

    def test_out_of_date_or_corrupted_local_filenames_are_blocking(self):
        (self.directory / "not-a-timestamp.sql").write_text("-- bad\n")
        with self.assertRaisesRegex(ValueError, "invalid local migration file"):
            check_migrations(self.table(), self.directory)


if __name__ == "__main__":
    unittest.main()
