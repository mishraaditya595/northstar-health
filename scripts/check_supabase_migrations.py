#!/usr/bin/env python3
"""Fail-closed check that the linked Supabase migration history matches Git.

Consumes the standard `supabase migration list --linked` table from stdin.
This checks *migration versions*, not SQL drift, hashes or actual schema;
independent deployment approval and real hosted QA remain mandatory.
"""
from pathlib import Path
import re
import sys

MIGRATIONS = Path(__file__).resolve().parents[1] / "supabase" / "migrations"
VERSION = re.compile(r"\d{14}")
ROW = re.compile(
    r"^\s*(\d{14})?\s*[|│]\s*(\d{14})?\s*[|│].*$"
)


def check_migrations(
    table: str, migration_dir: Path = MIGRATIONS, *, report_only: bool = False
) -> str:
    expected = []
    for path in sorted(migration_dir.glob("*.sql")):
        version = path.name.split("_", 1)[0]
        if not VERSION.fullmatch(version):
            raise ValueError("invalid local migration file")
        expected.append(version)
    if not expected or len(expected) != len(set(expected)):
        raise ValueError("missing or duplicated local migration versions")

    local = []
    remote = []
    for line in table.splitlines():
        match = ROW.fullmatch(line)
        if match is None:
            continue
        left, right = match.groups()
        if left is None and right is None:
            continue
        if left:
            local.append(left)
        if right:
            remote.append(right)
        if left and right and left != right:
            raise ValueError("remote and local migration histories diverge")

    # No table (or truncated/changed CLI output) must never authorize deploy.
    if sorted(local) != sorted(expected):
        raise ValueError("migration list output does not match local files")
    if len(remote) != len(set(remote)):
        raise ValueError("remote migration history has duplicate versions")
    unexpected = set(remote) - set(expected)
    if unexpected:
        raise ValueError(
            "remote history includes migrations absent locally: "
            + ", ".join(sorted(unexpected))
        )
    pending = set(expected) - set(remote)
    if pending:
        if report_only:
            return (
                f"Preview: {len(remote)}/{len(expected)} migration versions applied; "
                f"{len(pending)} pending. Manual SQL/schema review required before deploy."
            )
        raise ValueError(f"{len(pending)} migration(s) still pending remotely")
    if sorted(remote) != sorted(expected):
        raise ValueError("remote migration history is incomplete")
    return f"Verified {len(expected)} local/remote migration versions are aligned"


def main() -> int:
    try:
        if len(sys.argv) > 2 or (
            len(sys.argv) == 2 and sys.argv[1] != "--report-only"
        ):
            raise ValueError("unsupported arguments")
        result = check_migrations(
            sys.stdin.read(), report_only="--report-only" in sys.argv[1:]
        )
    except ValueError as error:
        print(f"Remote migration verification FAILED: {error}", file=sys.stderr)
        return 1
    print(result)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
