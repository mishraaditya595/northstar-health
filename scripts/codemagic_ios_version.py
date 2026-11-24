#!/usr/bin/env python3
"""Resolve the TestFlight version name and build number for Codemagic.

Inputs (from the manual build form, via environment variables):
  NS_VERSION_NAME  AUTO, or a version such as 1.2.0 (one to three integers)
  NS_BUILD_NUMBER  AUTO, or a positive integer

AUTO version name takes the part before "+" of `version:` in pubspec.yaml.
AUTO build number is the highest build of in.beyondrep.app in App Store
Connect (all versions) plus one. A manual build number must be higher than
that, so a run fails here instead of after a long build and upload.

The result is appended to $CM_ENV as BEYONDREP_VERSION_NAME and
BEYONDREP_BUILD_NUMBER for later build steps. Authentication comes from the
App Store Connect integration's environment; no credential is read here.
"""
import json
import os
from pathlib import Path
import re
import subprocess
import sys

BUNDLE_ID = "in.beyondrep.app"
AUTO = "AUTO"
# CFBundleShortVersionString: one to three period-separated integers.
VERSION_NAME = re.compile(r"(0|[1-9][0-9]{0,3})(\.(0|[1-9][0-9]{0,3})){0,2}\Z")
# Positive integer, no leading zero. Also a valid Android versionCode.
BUILD_NUMBER = re.compile(r"[1-9][0-9]{0,9}\Z")
MAX_BUILD_NUMBER = 2_100_000_000
PUBSPEC_VERSION = re.compile(r"^version:\s*([^\s+#]+)", re.MULTILINE)


class ResolveError(Exception):
    pass


def asc(*args: str) -> str:
    try:
        result = subprocess.run(
            ["app-store-connect", *args],
            capture_output=True, text=True, timeout=300,
        )
    except (OSError, subprocess.TimeoutExpired) as error:
        raise ResolveError(f"App Store Connect lookup failed: {error}")
    if result.returncode != 0:
        detail = result.stderr.strip().splitlines()[-1:] or [""]
        raise ResolveError(
            f"App Store Connect lookup failed (exit {result.returncode}): "
            f"{detail[0]} Check the 'Codemagic Signing' integration, or that "
            "codemagic-cli-tools is 0.69 or newer (needs --all-versions)."
        )
    return result.stdout.strip()


def latest_testflight_build() -> int:
    try:
        apps = json.loads(asc(
            "apps", "list", "--bundle-id-identifier", BUNDLE_ID,
            "--strict-match-identifier", "--json",
        ))
        app_id = str(apps[0]["id"])
    except (ValueError, LookupError, TypeError):
        raise ResolveError(f"No App Store Connect app found for {BUNDLE_ID}.")
    latest = asc(
        "get-latest-testflight-build-number", app_id,
        "--platform", "IOS", "--all-versions",
    )
    if latest == "":
        return 0
    if not re.fullmatch(r"[0-9]+", latest):
        raise ResolveError(
            f"App Store Connect returned an unexpected build number: {latest!r}"
        )
    return int(latest)


def resolve_version(raw: str, pubspec: Path) -> str:
    value = raw.strip()
    if value == AUTO:
        match = PUBSPEC_VERSION.search(pubspec.read_text(encoding="utf-8"))
        if not match:
            raise ResolveError(f"No version: line found in pubspec {pubspec}.")
        value = match.group(1)
    if not VERSION_NAME.match(value):
        raise ResolveError(
            f"Invalid version name {value!r}: use one to three numbers "
            "separated by dots, such as 1.2.0, or AUTO."
        )
    return value


def resolve_build(raw: str) -> str:
    value = raw.strip()
    if value != AUTO and not (
        BUILD_NUMBER.match(value) and int(value) <= MAX_BUILD_NUMBER
    ):
        raise ResolveError(
            f"Invalid build number {value!r}: use a whole number from 1 to "
            f"{MAX_BUILD_NUMBER} with no leading zero, or AUTO."
        )
    latest = latest_testflight_build()
    if value == AUTO:
        return str(latest + 1)
    if int(value) <= latest:
        raise ResolveError(
            f"Build number {value} must be higher than the latest App Store "
            f"Connect build, {latest}. Use AUTO or a number above {latest}."
        )
    return value


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: codemagic_ios_version.py PUBSPEC", file=sys.stderr)
        return 2
    try:
        version = resolve_version(os.environ.get("NS_VERSION_NAME", ""), Path(argv[1]))
        build = resolve_build(os.environ.get("NS_BUILD_NUMBER", ""))
    except ResolveError as error:
        print(f"Version check failed: {error}", file=sys.stderr)
        return 1
    with open(os.environ["CM_ENV"], "a", encoding="utf-8") as env_file:
        env_file.write(f"BEYONDREP_VERSION_NAME={version}\n")
        env_file.write(f"BEYONDREP_BUILD_NUMBER={build}\n")
    print(f"Version name {version}, build number {build}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
