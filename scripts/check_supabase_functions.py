#!/usr/bin/env python3
"""Validate selected deployable Edge Function names against source and JWT config.

No dynamic code execution, arbitrary paths or automatic --no-verify-jwt flags.
Outputs validated names, one per line; nonzero exit prevents partial deployment.
"""
from pathlib import Path
import re
import sys
import tomllib

ROOT = Path(__file__).resolve().parents[1]
FUNCTION_DIR = ROOT / "supabase" / "functions"
CONFIG = ROOT / "supabase" / "config.toml"
VALID_NAME = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")


def validate(selection: str, root: Path = ROOT) -> list[str]:
    source = root / "supabase" / "functions"
    config = tomllib.loads((root / "supabase" / "config.toml").read_text())
    policies = config.get("functions", {})
    if not isinstance(policies, dict):
        raise ValueError("invalid functions configuration")
    folders = {
        p.name for p in source.iterdir() if p.is_dir() and p.name != "_shared"
    }
    if not folders or folders != set(policies):
        raise ValueError("Function source/config lists differ")
    for name in folders:
        if (not VALID_NAME.fullmatch(name)
                or not (source / name / "index.ts").is_file()
                or not isinstance(policies[name], dict)
                or type(policies[name].get("verify_jwt")) is not bool):
            raise ValueError("Function missing source or explicit verify_jwt policy")

    names = selection.split()
    if not names or len(names) != len(set(names)):
        raise ValueError("empty or duplicated function selection")
    if any(not VALID_NAME.fullmatch(n) or n not in folders for n in names):
        raise ValueError("unknown/invalid Function name; use names, not paths")
    return names


if __name__ == "__main__":
    try:
        if len(sys.argv) != 2:
            raise ValueError("expected one space-separated selection argument")
        print(" ".join(validate(sys.argv[1])))
    except (ValueError, OSError) as exc:
        print(f"Function selection rejected: {exc}", file=sys.stderr)
        sys.exit(1)
