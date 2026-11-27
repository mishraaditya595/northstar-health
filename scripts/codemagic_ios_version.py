#!/usr/bin/env python3
"""Resolve the TestFlight version name and build number for Codemagic.

Inputs (from the manual build form, via environment variables):
  NS_RELEASE_TYPE  Fix or optimisation, Feature, Major, Same version, new
                   build, or Exact version
  NS_VERSION_NAME  AUTO, or a version such as 1.2.0 (only for Exact version)
  NS_BUILD_NUMBER  AUTO, or a positive integer

The current version is the highest TestFlight version in App Store Connect
(iOS; every App Store build is first a TestFlight build) and, when
GOOGLE_PLAY_SERVICE_ACCOUNT_CREDENTIALS is set and works, Google Play. Google
Play is optional here: missing credentials or a failed lookup print a note and
the job goes on with App Store Connect alone. The release type decides the next version from it; see
codemagic_release_version.py.
AUTO build number is the highest build of in.beyondrep.app in App Store
Connect (all versions) plus one. A manual build number must be higher than
that, so a run fails here instead of after a long build and upload.

The result is appended to $CM_ENV as BEYONDREP_VERSION_NAME and
BEYONDREP_BUILD_NUMBER for later build steps. Authentication comes from the
App Store Connect integration's environment; no credential is read here.
"""
import os
from pathlib import Path
import re
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
from codemagic_release_version import (  # noqa: E402
    AUTO,
    ResolveError,
    app_store_app_id,
    asc,
    current_version,
    format_version,
    next_version,
)

# Positive integer, no leading zero. Also a valid Android versionCode.
BUILD_NUMBER = re.compile(r"[1-9][0-9]{0,9}\Z")
MAX_BUILD_NUMBER = 2_100_000_000


def latest_testflight_build() -> int:
    app_id = app_store_app_id()
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
    if len(argv) != 1:
        print("usage: codemagic_ios_version.py", file=sys.stderr)
        return 2
    try:
        release_type = os.environ.get("NS_RELEASE_TYPE", "").strip()
        current = current_version(play_optional=True)
        new = next_version(release_type, os.environ.get("NS_VERSION_NAME", ""), current)
        version = format_version(new)
        build = resolve_build(os.environ.get("NS_BUILD_NUMBER", ""))
    except ResolveError as error:
        print(f"Version check failed: {error}", file=sys.stderr)
        return 1
    with open(os.environ["CM_ENV"], "a", encoding="utf-8") as env_file:
        env_file.write(f"BEYONDREP_VERSION_NAME={version}\n")
        env_file.write(f"BEYONDREP_BUILD_NUMBER={build}\n")
    before = format_version(current) if current is not None else "none"
    print(f"Release type {release_type}: {before} -> {version}, build number {build}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
